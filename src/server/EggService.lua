--!strict
-- egg-army-game :: ระบบไข่ (สร้าง → ฟัก → ได้ตัวแม่ → เข้าคอก/กระเป๋า)
--
-- ⚠️ server-authoritative ทั้งหมด:
--   - เวลาฟักนับที่ server ด้วย os.time() (เซฟลง DataStore ได้ ต่างจาก os.clock())
--   - การสุ่มทุกอย่างเกิดที่ server เท่านั้น client ไม่เคยส่งผลสุ่มมาเอง
--   - client มีหน้าที่ "ขอ" อย่างเดียว ทุกค่าที่ส่งมาถือว่าเชื่อไม่ได้จนกว่าจะ validate
--
-- ⚠️ กฎข้อเดียวที่ต้องจำ: **น้ำหนักมาก่อน และมาตั้งแต่ตอนสร้างไข่**
--
--   สร้างไข่ (บอสวาง / แจกผู้เล่นใหม่ / คำสั่งเทสต์)
--       └─ สุ่ม "น้ำหนัก" ตรงนี้ ด้วย Config.rollMotherWeightForEgg()
--   ไข่เข้ากระเป๋า (heldEggs) → เข้าสวนฟัก (hatching)
--       └─ น้ำหนักเดินทางไปด้วยทุกขั้น ห้ามสุ่มใหม่ ห้ามคำนวณใหม่
--   ครบเวลาฟัก
--       └─ สุ่ม "ตัวละคร" ตรงนี้เท่านั้น ด้วย Config.rollCharacter()
--
--   เหตุผล: ขนาดโมเดลไข่ในรังบอกน้ำหนักให้ผู้เล่นเห็น (Phase 5) การแย่งไข่จึงมีเป้าหมายจริง
--   ผลที่ตามมา: ไข่ชนิดเดียวกันน้ำหนักต่างกันได้ → เก็บ "รายฟอง" ไม่ใช่ตัวนับ
--
-- Phase 1.5: ข้อมูลอยู่ใน memory ของ server เท่านั้น
-- ผู้เล่นออกจากเกม = ข้อมูลหาย (Phase 2 จะต่อ DataStore)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PenService = require(ServerScriptService.PenService)

local EggService = {}

local WORLD = Config.World
-- ⚠️ สองค่านี้แยกกันแล้ว (บังเอิญเท่ากันที่ 50 ไม่ใช่เพราะต้องเท่า)
-- BAG_SLOTS   = ความยาวของ state.heldEggs — ไข่ที่ถือไว้ ยังไม่เข้าสวน
-- HATCH_SLOTS = ความยาวของ state.hatching — ไข่ที่กำลังฟัก
-- ใช้สลับกันเมื่อไหร่ = index หลุดขอบอาเรย์ทันทีที่ปรับค่าใดค่าหนึ่ง
local BAG_SLOTS = Config.Hatchery.BAG_CAPACITY
local HATCH_SLOTS = Config.Hatchery.MAX_SLOTS

-- ไข่ 1 ฟองที่ถืออยู่ (ยังไม่เข้าสวนฟัก)
-- ⚠️ มีน้ำหนักของตัวเองตั้งแต่วินาทีที่เกิด
export type HeldEgg = {
	eggId: string,
	weight: number, -- น้ำหนักแม่ที่จะได้ตอนฟัก (จำนวนเต็ม)
}

-- ไข่ 1 ฟองที่กำลังฟักอยู่ในสวน
export type HatchSlot = {
	eggId: string,
	weight: number, -- ยกมาจาก HeldEgg ตรง ๆ ห้ามสุ่มใหม่
	startedAt: number, -- os.time() ตอนวาง
	hatchAt: number, -- os.time() ที่ครบกำหนด
}

-- ตัวแม่ 1 ตัว — โครงตรงกับ docs/data-schema.md §3
export type Mother = {
	uid: string, -- "<UserId ผู้ฟักคนแรก>-<เลขนับ>" ไม่ซ้ำทั้งเกม
	charId: string,
	weight: number,
	statuses: { string },
	lastProducedAt: number?, -- มีเฉพาะแม่ในคอก (แม่ในกระเป๋าไม่ผลิตจึงไม่ต้องนับเวลา)
	obtainedAt: number,
	locked: boolean,
}

-- รูปทรงของ 1 ช่องที่ส่งไปให้ client
-- ช่องว่างมีแค่ occupied = false ฟิลด์ที่เหลือจึงเป็น optional
type EggView = {
	occupied: boolean,
	eggId: string?,
	eggName: string?,
	weight: number?,
	weightText: string?,
	remaining: number?,
	total: number?,
}

type PlayerState = {
	-- อาเรย์ยาวคงที่ ช่องว่างใช้ false ห้ามใช้ nil (เหตุผลใน docs/data-schema.md §9.3)
	heldEggs: { HeldEgg | false },
	hatching: { HatchSlot | false },

	-- ⚠️ แยกสองอาเรย์ ไม่ใช่ฟิลด์ inPen ในตัวเดียว
	-- โค้ด settle การผลิต (Phase 2) ต้องวนเฉพาะแม่ในคอก แยกโครงไว้ทำให้ลืมกรองไม่ได้
	mothersInPen: { Mother },
	mothersInBag: { Mother },

	nextUid: number, -- ตัวนับต่อผู้เล่น ห้ามรีเซ็ต ห้ามลด
	penLevel: number,
	lastRequestAt: number, -- ไว้กันสแปม
}

local states: { [number]: PlayerState } = {}
local rng = Random.new()

local placeEggRequest: RemoteEvent
local moveMotherRequest: RemoteEvent
local eggHatched: RemoteEvent
local farmStateSync: RemoteEvent

--------------------------------------------------------------------------------
-- สร้างไข่ — ทางเดียวที่ไข่เกิดได้
--------------------------------------------------------------------------------

-- ⚠️ ทุกทางที่ไข่เกิด (บอสวาง / แจกผู้เล่นใหม่ / คำสั่งเทสต์) ต้องผ่านตัวนี้
-- เพื่อให้ไม่มีไข่ฟองไหนหลุดออกมาโดยไม่มีน้ำหนัก
local function makeEgg(eggId: string): HeldEgg?
	local egg = Config.getEgg(eggId)
	if not egg or not egg.enabled then
		return nil
	end

	local weight = Config.rollMotherWeightForEgg(eggId, rng)
	if not weight then
		return nil
	end

	return { eggId = egg.id, weight = weight }
end

-- หาช่องว่างช่องแรกในอาเรย์ยาวคงที่ คืน nil ถ้าเต็ม
local function findFreeSlot(list: { any }, size: number): number?
	for index = 1, size do
		if list[index] == false then
			return index
		end
	end
	return nil
end

local function countFilled(list: { any }, size: number): number
	local total = 0
	for index = 1, size do
		if list[index] ~= false then
			total += 1
		end
	end
	return total
end

--------------------------------------------------------------------------------
-- แจกไข่ (server เท่านั้น)
--------------------------------------------------------------------------------

-- ⚠️ ห้ามให้ client เรียกถึงได้ และห้ามรับน้ำหนักมาจาก client
-- Phase 5 บอสจะเรียกตัวนี้ตอนผู้เล่นแย่งไข่สำเร็จ
-- ระหว่างที่ยังไม่มีบอส ใช้เป็นคำสั่งเทสต์ใน command bar ฝั่ง server
function EggService.grantEgg(player: Player, eggId: string): (boolean, string?)
	local state = states[player.UserId]
	if not state then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local egg = makeEgg(eggId)
	if not egg then
		return false, `สร้างไข่ "{eggId}" ไม่ได้ (ไม่มีอยู่ หรือถูกปิดไปแล้ว)`
	end

	local slot = findFreeSlot(state.heldEggs, BAG_SLOTS)
	if not slot then
		return false, "ถือไข่เต็มแล้ว"
	end

	state.heldEggs[slot] = egg
	EggService.sync(player)

	print(`[EggService] {player.Name} ได้ {egg.eggId} น้ำหนัก {Config.formatWeight(egg.weight)}`)
	return true, nil
end

--------------------------------------------------------------------------------
-- ประกอบข้อมูลที่ส่งให้ client
--------------------------------------------------------------------------------

local function describeMother(mother: Mother)
	local character = Config.getCharacter(mother.charId)
	return {
		uid = mother.uid,
		charId = mother.charId,
		charName = if character then character.name else mother.charId,
		class = if character then character.class else "?",
		weight = mother.weight,
		weightText = Config.formatWeight(mother.weight),
		locked = mother.locked,
	}
end

local function buildSyncPayload(state: PlayerState)
	local now = os.time()

	local held: { EggView } = table.create(BAG_SLOTS)
	for index = 1, BAG_SLOTS do
		local egg = state.heldEggs[index]
		-- ⚠️ ใช้ type() ไม่ใช่ `~= false` — Luau ขยาย `X | false` เป็น `X | boolean`
		-- ทำให้เทียบกับ false แล้วไม่แคบลง แต่ type() แคบลงได้เสมอ
		if type(egg) == "table" then
			local eggType = Config.getEgg(egg.eggId)
			held[index] = {
				occupied = true,
				eggId = egg.eggId,
				eggName = if eggType then eggType.name else egg.eggId,
				weight = egg.weight,
				weightText = Config.formatWeight(egg.weight),
			}
		else
			held[index] = { occupied = false }
		end
	end

	local hatching: { EggView } = table.create(HATCH_SLOTS)
	for index = 1, HATCH_SLOTS do
		local slot = state.hatching[index]
		if type(slot) == "table" then
			local eggType = Config.getEgg(slot.eggId)
			hatching[index] = {
				occupied = true,
				eggId = slot.eggId,
				eggName = if eggType then eggType.name else slot.eggId,
				weight = slot.weight,
				weightText = Config.formatWeight(slot.weight),
				remaining = math.max(0, slot.hatchAt - now),
				total = math.max(1, slot.hatchAt - slot.startedAt),
			}
		else
			hatching[index] = { occupied = false }
		end
	end

	local pen = table.create(#state.mothersInPen)
	for _, mother in state.mothersInPen do
		table.insert(pen, describeMother(mother))
	end

	local bag = table.create(#state.mothersInBag)
	for _, mother in state.mothersInBag do
		table.insert(bag, describeMother(mother))
	end

	return {
		heldEggs = held,
		heldCount = countFilled(state.heldEggs, BAG_SLOTS),
		bagSize = BAG_SLOTS,
		hatching = hatching,
		hatchingCount = countFilled(state.hatching, HATCH_SLOTS),
		hatcherySize = HATCH_SLOTS,
		mothersInPen = pen,
		mothersInBag = bag,
		penCapacity = Config.getPenCapacity(state.penLevel),
		bagCapacity = Config.Bag.CAPACITY,
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

local function hatch(player: Player, slotIndex: number, slot: HatchSlot)
	local state = states[player.UserId]
	if not state then
		return
	end

	state.hatching[slotIndex] = false
	PenService.hideEgg(player, slotIndex)

	-- ⚠️ สุ่มแค่ "ตัวละคร" ตรงนี้ · น้ำหนักยกมาจากตัวไข่ ไม่สุ่มใหม่
	local charId = Config.rollCharacter(slot.eggId, rng)
	if not charId then
		warn(`[EggService] ไข่ "{slot.eggId}" ไม่มีตารางคลาส ฟักไม่ได้`)
		return
	end

	local character = Config.getCharacter(charId)
	if not character then
		warn(`[EggService] ตารางคลาสของไข่ "{slot.eggId}" ชี้ไปที่ตัวละคร "{charId}" ที่ไม่มีอยู่`)
		return
	end

	local mother: Mother = {
		uid = Config.makeUid(player.UserId, state.nextUid),
		charId = charId,
		weight = slot.weight, -- ← น้ำหนักเดิมของไข่ เป๊ะ
		statuses = {},
		obtainedAt = os.time(),
		locked = false,
	}
	state.nextUid += 1

	-- คอกมีที่ว่างก็เข้าคอก (ผลิตได้) ไม่งั้นเข้ากระเป๋า
	local placedIn: string
	if #state.mothersInPen < Config.getPenCapacity(state.penLevel) then
		mother.lastProducedAt = os.time()
		table.insert(state.mothersInPen, mother)
		placedIn = "pen"
	elseif #state.mothersInBag < Config.Bag.CAPACITY then
		table.insert(state.mothersInBag, mother)
		placedIn = "bag"
	else
		-- คอกและกระเป๋าเต็มทั้งคู่ — แม่ตัวนี้หายไป
		-- ⚠️ Phase 2 ต้องเปลี่ยนเป็น "ค้างไว้ในสวนจนกว่าจะมีที่ว่าง" (data-schema §13 ข้อ D)
		warn(`[EggService] {player.Name} คอกและกระเป๋าเต็ม แม่ที่ฟักได้หายไป`)
		return
	end

	PenService.refreshMothers(player, state.mothersInPen)

	eggHatched:FireClient(player, {
		slotIndex = slotIndex,
		eggId = slot.eggId,
		charId = charId,
		charName = character.name,
		class = character.class,
		weight = mother.weight,
		weightText = Config.formatWeight(mother.weight),
		placedIn = placedIn,
	})

	print(
		`[EggService] {player.Name} ฟัก {slot.eggId} ช่อง {slotIndex} ได้ {character.name} `
			.. `({character.class}) {Config.formatWeight(mother.weight)} → {placedIn}`
	)
end

--------------------------------------------------------------------------------
-- ย้ายไข่จากกระเป๋าเข้าสวนฟัก
--------------------------------------------------------------------------------

-- รับค่าดิบจาก client จึงประกาศเป็น unknown แล้วค่อย validate ทีละชั้น
-- ⚠️ รับ "ตำแหน่งไข่ใน heldEggs" ไม่ใช่ชนิดไข่ — ไข่ชนิดเดียวกันน้ำหนักต่างกันได้
function EggService.placeEgg(player: Player, rawHeldIndex: unknown, rawSlotIndex: unknown): (boolean, string?)
	local state = states[player.UserId]
	if not state then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	-- 1) กันสแปม
	local now = os.time()
	if now - state.lastRequestAt < WORLD.REQUEST_COOLDOWN then
		return false, "กดเร็วเกินไป"
	end
	state.lastRequestAt = now

	-- 2) heldIndex ต้องเป็นจำนวนเต็มในช่วง และช่องนั้นต้องมีไข่จริง
	if type(rawHeldIndex) ~= "number" then
		return false, "heldIndex ไม่ใช่ number"
	end
	if rawHeldIndex % 1 ~= 0 or rawHeldIndex < 1 or rawHeldIndex > BAG_SLOTS then
		return false, "heldIndex อยู่นอกช่วงที่อนุญาต"
	end
	local heldEgg = state.heldEggs[rawHeldIndex]
	if type(heldEgg) ~= "table" then
		return false, "ช่องนั้นไม่มีไข่"
	end

	local eggType = Config.getEgg(heldEgg.eggId)
	if not eggType then
		return false, `ไข่ "{heldEgg.eggId}" ไม่มีใน Config แล้ว`
	end

	-- 3) ต้องมีคอกก่อนถึงจะวางไข่ได้
	if not PenService.getPen(player) then
		return false, "ยังไม่ได้รับคอก (เซิร์ฟเวอร์เต็ม)"
	end

	-- 4) slotIndex ส่งมาหรือไม่ส่งก็ได้ ถ้าไม่ส่ง server เลือกช่องว่างช่องแรกให้
	local slotIndex: number
	if rawSlotIndex == nil then
		local free = findFreeSlot(state.hatching, HATCH_SLOTS)
		if not free then
			return false, "สวนฟักเต็มแล้ว"
		end
		slotIndex = free
	else
		if type(rawSlotIndex) ~= "number" then
			return false, "slotIndex ไม่ใช่ number"
		end
		if rawSlotIndex % 1 ~= 0 or rawSlotIndex < 1 or rawSlotIndex > HATCH_SLOTS then
			return false, "slotIndex อยู่นอกช่วงที่อนุญาต"
		end
		if state.hatching[rawSlotIndex] ~= false then
			return false, "ช่องนี้มีไข่อยู่แล้ว"
		end
		slotIndex = rawSlotIndex
	end

	-- 5) ผ่านหมดแล้ว ย้ายทั้งฟอง (eggId + weight) เข้าสวน
	state.heldEggs[rawHeldIndex] = false
	state.hatching[slotIndex] = {
		eggId = heldEgg.eggId,
		weight = heldEgg.weight, -- ← เดินทางไปด้วย ไม่สุ่มใหม่
		startedAt = now,
		hatchAt = now + eggType.hatchTime,
	}

	PenService.showEgg(player, slotIndex, eggType)
	EggService.sync(player)

	return true, nil
end

--------------------------------------------------------------------------------
-- ย้ายแม่ระหว่างคอกกับกระเป๋า
--------------------------------------------------------------------------------

local function takeMother(list: { Mother }, uid: string): Mother?
	for index, mother in list do
		if mother.uid == uid then
			return table.remove(list, index)
		end
	end
	return nil
end

function EggService.moveMother(player: Player, rawUid: unknown, rawTarget: unknown): (boolean, string?)
	local state = states[player.UserId]
	if not state then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	if type(rawUid) ~= "string" then
		return false, "uid ไม่ใช่ string"
	end
	if rawTarget ~= "pen" and rawTarget ~= "bag" then
		return false, "ปลายทางต้องเป็น pen หรือ bag เท่านั้น"
	end

	if rawTarget == "pen" then
		if #state.mothersInPen >= Config.getPenCapacity(state.penLevel) then
			return false, "คอกเต็มแล้ว"
		end
		local mother = takeMother(state.mothersInBag, rawUid)
		if not mother then
			return false, "ไม่พบแม่ตัวนี้ในกระเป๋า"
		end
		-- เริ่มนับเวลาผลิตใหม่ตั้งแต่วินาทีที่เข้าคอก (Phase 2 จะใช้ค่านี้)
		mother.lastProducedAt = os.time()
		table.insert(state.mothersInPen, mother)
	else
		if #state.mothersInBag >= Config.Bag.CAPACITY then
			return false, "กระเป๋าเต็มแล้ว"
		end
		local mother = takeMother(state.mothersInPen, rawUid)
		if not mother then
			return false, "ไม่พบแม่ตัวนี้ในคอก"
		end
		-- แม่ในกระเป๋าไม่ผลิตอะไรเลย จึงไม่ต้องเก็บเวลาผลิตไว้
		mother.lastProducedAt = nil
		table.insert(state.mothersInBag, mother)
	end

	PenService.refreshMothers(player, state.mothersInPen)
	EggService.sync(player)
	return true, nil
end

--------------------------------------------------------------------------------
-- วงจรชีวิตผู้เล่น
--------------------------------------------------------------------------------

function EggService.onPlayerAdded(player: Player)
	-- ⚠️ อาเรย์ยาวคงที่ ช่องว่างใช้ false ห้ามใช้ nil
	-- (Phase 2 จะเซฟลง DataStore ซึ่งอ่านอาเรย์ที่มีรูกลับมาไม่ได้ — data-schema §9.3)
	-- ⚠️ สองอาเรย์นี้ยาวไม่เท่ากันก็ได้ จึงวนแยกกัน ห้ามยุบเป็นลูปเดียว
	local heldEggs: { HeldEgg | false } = {}
	for index = 1, BAG_SLOTS do
		heldEggs[index] = false
	end

	local hatching: { HatchSlot | false } = {}
	for index = 1, HATCH_SLOTS do
		hatching[index] = false
	end

	states[player.UserId] = {
		heldEggs = heldEggs,
		hatching = hatching,
		mothersInPen = {},
		mothersInBag = {},
		nextUid = 1,
		penLevel = 1,
		lastRequestAt = 0,
	}

	-- ⚠️ แจกไข่เริ่มต้นทีละฟองผ่าน grantEgg เพื่อให้แต่ละฟองได้สุ่มน้ำหนักของตัวเอง
	-- startingEggs เป็นแค่ "คำสั่งแจก" ไม่ใช่รูปแบบที่เก็บ
	for eggId, amount in Config.NewPlayer.startingEggs do
		for _ = 1, amount do
			EggService.grantEgg(player, eggId)
		end
	end

	EggService.sync(player)
end

function EggService.onPlayerRemoving(player: Player)
	-- Phase 1.5 ทิ้งข้อมูลทั้งหมด Phase 2 ตรงนี้จะกลายเป็นจุดเซฟลง DataStore
	states[player.UserId] = nil
end

function EggService.getMothersInPen(player: Player): { Mother }
	local state = states[player.UserId]
	return if state then state.mothersInPen else {}
end

function EggService.getMothersInBag(player: Player): { Mother }
	local state = states[player.UserId]
	return if state then state.mothersInBag else {}
end

--------------------------------------------------------------------------------
-- เริ่มระบบ
--------------------------------------------------------------------------------

function EggService.start()
	placeEggRequest = Remotes.waitFor(Config.RemoteNames.PLACE_EGG_IN_HATCHERY_REQUEST)
	moveMotherRequest = Remotes.waitFor(Config.RemoteNames.MOVE_MOTHER_REQUEST)
	eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
	farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)

	placeEggRequest.OnServerEvent:Connect(function(player, rawHeldIndex, rawSlotIndex)
		local ok, reason = EggService.placeEgg(player, rawHeldIndex, rawSlotIndex)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอวางไข่ของ {player.Name}: {reason}`)
		end
	end)

	moveMotherRequest.OnServerEvent:Connect(function(player, rawUid, rawTarget)
		local ok, reason = EggService.moveMother(player, rawUid, rawTarget)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอย้ายแม่ของ {player.Name}: {reason}`)
		end
	end)

	-- ลูปเดียวคุมทั้งการฟักและการ sync
	-- ความละเอียดของตัวจับเวลา = SYNC_INTERVAL
	task.spawn(function()
		while true do
			task.wait(WORLD.SYNC_INTERVAL)

			local now = os.time()
			for _, player in Players:GetPlayers() do
				local state = states[player.UserId]
				if state then
					for slotIndex = 1, HATCH_SLOTS do
						local slot = state.hatching[slotIndex]
						if type(slot) == "table" and now >= slot.hatchAt then
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
