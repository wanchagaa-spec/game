--!strict
-- egg-army-game :: ระบบไข่ (วาง → จับเวลา → ฟัก → สุ่มทหาร → เข้าคลัง)
--
-- ⚠️ server-authoritative ทั้งหมด:
--   - เวลาฟักนับที่ server ด้วย os.clock() ซึ่งเป็นนาฬิกา monotonic client แก้ไม่ได้
--   - การสุ่มทหารเกิดที่ server ตอนไข่ครบเวลาเท่านั้น ไม่ได้สุ่มไว้ล่วงหน้า
--   - client มีหน้าที่ "ขอ" อย่างเดียว ทุกค่าที่ส่งมาถือว่าเชื่อไม่ได้จนกว่าจะ validate
--
-- Phase 1: คลังทหารอยู่ใน memory ของ server เท่านั้น
-- ผู้เล่นออกจากเกม = ข้อมูลหาย (Phase 2 จะต่อ DataStore)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlotService = require(ServerScriptService.PlotService)

local EggService = {}

local FARM = Config.Farm

-- ไข่ 1 ฟองที่กำลังฟักอยู่ในช่อง
type EggSlot = {
	eggId: string,
	hatchAt: number, -- ค่า os.clock() ที่ครบกำหนดฟัก
	total: number, -- เวลาฟักเต็ม (วินาที) ไว้ให้ client คิด progress
}

-- ทหาร 1 ตัวในคลัง
type UnitRecord = {
	uid: number, -- เลขประจำตัวไม่ซ้ำภายในผู้เล่นคนนั้น
	unitId: string, -- อ้างถึง Config.UnitTypes
	obtainedAt: number, -- os.time() ตอนได้มา
}

-- รูปทรงของช่อง 1 ช่องที่ส่งไปให้ client
-- ช่องว่างจะมีแค่ occupied = false ฟิลด์ที่เหลือจึงเป็น optional
type SlotView = {
	occupied: boolean,
	eggId: string?,
	eggName: string?,
	remaining: number?,
	total: number?,
}

type PlayerState = {
	slots: { [number]: EggSlot }, -- [slotIndex] = ไข่ที่วางอยู่ (ช่องว่างจะไม่มีคีย์)
	units: { UnitRecord },
	nextUid: number,
	lastPlaceAt: number, -- ไว้กันสแปม
}

local states: { [number]: PlayerState } = {}
local rng = Random.new()

local placeEggRequest: RemoteEvent
local eggHatched: RemoteEvent
local farmStateSync: RemoteEvent

--------------------------------------------------------------------------------
-- ตัวช่วย
--------------------------------------------------------------------------------

-- สุ่มทหารจากตารางน้ำหนักของไข่
-- วิธี: รวม weight ทั้งหมด สุ่มเลขในช่วง [0, total) แล้วไล่หักทีละแถว
local function rollUnit(egg: Config.EggType): string
	local total = 0
	for _, entry in egg.hatchTable do
		total += entry.weight
	end

	local roll = rng:NextNumber() * total
	local acc = 0
	for _, entry in egg.hatchTable do
		acc += entry.weight
		if roll < acc then
			return entry.unitId
		end
	end

	-- ตกมาถึงตรงนี้ได้เฉพาะกรณีปัดเศษ ให้คืนแถวสุดท้าย
	return egg.hatchTable[#egg.hatchTable].unitId
end

-- วางก้อนไข่บนแท่น ให้เห็นด้วยตาว่ามีไข่อยู่
local function showEgg(player: Player, slotIndex: number, egg: Config.EggType)
	local pad = PlotService.getPad(player, slotIndex)
	if not pad then
		return
	end

	local old = pad:FindFirstChild("Egg")
	if old then
		old:Destroy()
	end

	local part = Instance.new("Part")
	part.Name = "Egg"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(3, 3, 3)
	part.Position = pad.Position + Vector3.new(0, 2.2, 0)
	part.Color = egg.color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.Parent = pad
end

local function hideEgg(player: Player, slotIndex: number)
	local pad = PlotService.getPad(player, slotIndex)
	if not pad then
		return
	end
	local egg = pad:FindFirstChild("Egg")
	if egg then
		egg:Destroy()
	end
end

-- ประกอบข้อมูลสถานะฟาร์มที่จะส่งให้ client
local function buildSyncPayload(state: PlayerState)
	local now = os.clock()
	local slots: { SlotView } = table.create(FARM.EGG_SLOTS_PER_PLAYER)

	for slotIndex = 1, FARM.EGG_SLOTS_PER_PLAYER do
		local slot = state.slots[slotIndex]
		if slot then
			local egg = Config.getEgg(slot.eggId)
			slots[slotIndex] = {
				occupied = true,
				eggId = slot.eggId,
				eggName = if egg then egg.name else slot.eggId,
				remaining = math.max(0, slot.hatchAt - now),
				total = slot.total,
			}
		else
			slots[slotIndex] = { occupied = false }
		end
	end

	return {
		slots = slots,
		unitCount = #state.units,
	}
end

function EggService.sync(player: Player)
	local state = states[player.UserId]
	if not state then
		return
	end
	farmStateSync:FireClient(player, buildSyncPayload(state))
end

--------------------------------------------------------------------------------
-- ฟักไข่
--------------------------------------------------------------------------------

local function hatch(player: Player, slotIndex: number, slot: EggSlot)
	local state = states[player.UserId]
	if not state then
		return
	end

	local egg = Config.getEgg(slot.eggId)
	if not egg then
		-- ไข่ชนิดนี้ถูกลบออกจาก Config ระหว่างที่ฟักอยู่ ทิ้งไปเงียบ ๆ
		state.slots[slotIndex] = nil
		hideEgg(player, slotIndex)
		return
	end

	local unitId = rollUnit(egg)
	local unit = Config.getUnit(unitId)
	if not unit then
		warn(`[EggService] ตารางสุ่มของไข่ "{egg.id}" ชี้ไปที่ทหาร "{unitId}" ที่ไม่มีอยู่`)
		state.slots[slotIndex] = nil
		hideEgg(player, slotIndex)
		return
	end

	local record: UnitRecord = {
		uid = state.nextUid,
		unitId = unitId,
		obtainedAt = os.time(),
	}
	state.nextUid += 1
	table.insert(state.units, record)

	state.slots[slotIndex] = nil
	hideEgg(player, slotIndex)

	eggHatched:FireClient(player, {
		slotIndex = slotIndex,
		eggId = egg.id,
		unitId = unit.id,
		unitName = unit.name,
		rarity = unit.rarity,
	})

	print(`[EggService] {player.Name} ฟัก {egg.name} ช่อง {slotIndex} ได้ {unit.name} ({unit.rarity})`)
end

--------------------------------------------------------------------------------
-- วางไข่
--------------------------------------------------------------------------------

-- รับค่าดิบจาก client จึงประกาศเป็น unknown แล้วค่อย validate ทีละชั้น
-- คืน (สำเร็จ, เหตุผลที่ไม่สำเร็จ)
function EggService.placeEgg(player: Player, rawEggId: unknown, rawSlotIndex: unknown): (boolean, string?)
	local state = states[player.UserId]
	if not state then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	-- 1) กันสแปม
	local now = os.clock()
	if now - state.lastPlaceAt < FARM.PLACE_EGG_COOLDOWN then
		return false, "กดเร็วเกินไป"
	end
	state.lastPlaceAt = now

	-- 2) eggId ต้องเป็น string และต้องมีอยู่จริงใน Config
	if type(rawEggId) ~= "string" then
		return false, "eggId ไม่ใช่ string"
	end
	local egg = Config.getEgg(rawEggId)
	if not egg then
		return false, `ไม่มีไข่ชนิด "{rawEggId}"`
	end

	-- 3) ต้องมี plot ก่อนถึงจะวางไข่ได้
	if not PlotService.getPlot(player) then
		return false, "ยังไม่ได้รับ plot (ฟาร์มเต็ม)"
	end

	-- 4) slotIndex ส่งมาหรือไม่ส่งก็ได้ ถ้าไม่ส่ง server เลือกช่องว่างช่องแรกให้
	local slotIndex: number
	if rawSlotIndex == nil then
		local free: number? = nil
		for index = 1, FARM.EGG_SLOTS_PER_PLAYER do
			if state.slots[index] == nil then
				free = index
				break
			end
		end
		if not free then
			return false, "ช่องวางไข่เต็มแล้ว"
		end
		slotIndex = free
	else
		if type(rawSlotIndex) ~= "number" then
			return false, "slotIndex ไม่ใช่ number"
		end
		if rawSlotIndex % 1 ~= 0 or rawSlotIndex < 1 or rawSlotIndex > FARM.EGG_SLOTS_PER_PLAYER then
			return false, "slotIndex อยู่นอกช่วงที่อนุญาต"
		end
		if state.slots[rawSlotIndex] ~= nil then
			return false, "ช่องนี้มีไข่อยู่แล้ว"
		end
		slotIndex = rawSlotIndex
	end

	-- 5) ผ่านหมดแล้ว วางจริง
	-- ราคาไข่ยังไม่ถูกหักใน Phase 1 เพราะระบบ currency อยู่ Phase 4
	state.slots[slotIndex] = {
		eggId = egg.id,
		hatchAt = now + egg.hatchTime,
		total = egg.hatchTime,
	}

	showEgg(player, slotIndex, egg)
	EggService.sync(player)

	return true, nil
end

--------------------------------------------------------------------------------
-- วงจรชีวิตผู้เล่น
--------------------------------------------------------------------------------

function EggService.onPlayerAdded(player: Player)
	states[player.UserId] = {
		slots = {},
		units = {},
		nextUid = 1,
		lastPlaceAt = 0,
	}
	EggService.sync(player)
end

function EggService.onPlayerRemoving(player: Player)
	-- Phase 1 ทิ้งข้อมูลทั้งหมด Phase 2 ตรงนี้จะกลายเป็นจุดเซฟลง DataStore
	states[player.UserId] = nil
end

-- อ่านคลังทหาร (Phase 2 จะเอาไปทำ UI คลังกับ DataStore)
function EggService.getUnits(player: Player): { UnitRecord }
	local state = states[player.UserId]
	if not state then
		return {}
	end
	return state.units
end

--------------------------------------------------------------------------------
-- เริ่มระบบ
--------------------------------------------------------------------------------

function EggService.start()
	placeEggRequest = Remotes.waitFor(Config.RemoteNames.PLACE_EGG_REQUEST)
	eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
	farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)

	placeEggRequest.OnServerEvent:Connect(function(player, rawEggId, rawSlotIndex)
		local ok, reason = EggService.placeEgg(player, rawEggId, rawSlotIndex)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอวางไข่ของ {player.Name}: {reason}`)
		end
	end)

	-- ลูปเดียวคุมทั้งการฟักและการ sync
	-- ความละเอียดของตัวจับเวลา = SYNC_INTERVAL
	task.spawn(function()
		while true do
			task.wait(FARM.SYNC_INTERVAL)

			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local state = states[player.UserId]
				if state then
					for slotIndex, slot in state.slots do
						if now >= slot.hatchAt then
							hatch(player, slotIndex, slot)
						end
					end
					EggService.sync(player)
				end
			end
		end
	end)
end

return EggService
