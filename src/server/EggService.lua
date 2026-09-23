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
--       └─ ⚠️ สุ่ม "ตัวละคร" ตรงนี้ด้วย ด้วย Config.rollCharacter() — เก็บไว้เงียบ ๆ ใน
--          HatchSlot.charId **ไม่ส่งให้ client เห็น** เหตุผล: เวลาฟัก (Config.getHatchSeconds)
--          ต้องรู้คลาสก่อนคำนวณ ผู้เล่นยังไม่เห็นผลจนกว่าจะฟักเสร็จจริงเหมือนเดิม
--          (ไข่ source="robux" ไม่ต้องรู้คลาสก่อน เพราะฟักคงที่เสมอ — ยังคง roll ตรงนี้ทันที
--          เพื่อให้โครง HatchSlot เหมือนกันทุกไข่)
--   ครบเวลาฟัก
--       └─ อ่าน "ตัวละคร" จาก slot.charId ที่สุ่มค้างไว้ตั้งแต่ตอนวาง (ไม่สุ่มใหม่)
--
--   เหตุผล: ขนาดโมเดลไข่ในรังบอกน้ำหนักให้ผู้เล่นเห็น (Phase 5) การแย่งไข่จึงมีเป้าหมายจริง
--   ผลที่ตามมา: ไข่ชนิดเดียวกันน้ำหนักต่างกันได้ → เก็บ "รายฟอง" ไม่ใช่ตัวนับ
--
-- ⚠️ Phase 2A: ข้อมูลมาจาก DataStore แล้ว (DataService) ไม่ใช่ตารางใน memory ที่สร้างใหม่ทุกครั้ง
-- ไฟล์นี้จึง **ไม่ถือ state ของตัวเอง** อ่าน/เขียนผ่าน DataService.getCached() ทางเดียว
-- ของที่ไม่ควรเซฟ (ตัวกันสแปม) แยกไว้ใน sessionMeta ที่ตายพร้อมเซสชัน

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(ServerScriptService.DataService)
local PenService = require(ServerScriptService.PenService)
local ProductionService = require(ServerScriptService.ProductionService)
local CombatService = require(ServerScriptService.CombatService)

local EggService = {}

local WORLD = Config.World
local HATCH_SLOTS = Config.Balance.Hatchery.MAX_SLOTS

type Data = PlayerData.Data
type HatchSlot = PlayerData.HatchSlot

-- ⚠️ โครงของตัวแม่ย้ายไปอยู่ที่ PlayerData แล้ว (เพราะมันเป็นส่วนหนึ่งของข้อมูลที่เซฟ)
-- ประกาศ export ต่อไว้เพื่อให้โมดูลที่เคย require ชนิดนี้จาก EggService ใช้ได้เหมือนเดิม
export type Mother = PlayerData.Mother

-- รูปทรงของ 1 ช่องสวนฟักที่ส่งไปให้ client
type SlotView = {
	occupied: boolean,
	eggId: string?,
	eggName: string?,
	weight: number?,
	weightText: string?,
	remaining: number?,
	total: number?,
	-- ครบเวลาฟักแล้วแต่ยังวางแม่ไม่ได้ (คอก+กระเป๋าเต็มพร้อมกัน — ข้อ D) รอที่ว่างอยู่
	stuck: boolean?,
}

-- ⚠️ ของที่ **ห้ามเซฟ** — ตายพร้อมเซสชัน
-- ถ้าเอาไปใส่ใน PlayerData จะกลายเป็นฟิลด์ใหม่ใน schema ที่ต้องดูแลตลอดไปโดยไม่มีประโยชน์
type SessionMeta = {
	lastRequestAt: number,
}

local sessionMeta: { [number]: SessionMeta } = {}
local rng = Random.new()

local placeEggRequest: RemoteEvent
local moveMotherRequest: RemoteEvent
local upgradePenRequest: RemoteEvent
local sellMotherRequest: RemoteEvent
local autoFillPenRequest: RemoteEvent
local buyDamageUpgradeRequest: RemoteEvent
local buySpeedUpgradeRequest: RemoteEvent
local eggHatched: RemoteEvent
local farmStateSync: RemoteEvent
local actionResult: RemoteEvent

-- ⚠️ ส่งผลลัพธ์ (สำเร็จ/ล้มเหลว + เหตุผล) ของคำขอกลับไปหาผู้เล่นคนที่ยิงคำขอมาเท่านั้น
-- ก่อนหน้านี้ผลลัพธ์ไปโผล่แค่ print ใน server console เท่านั้น ผู้เล่นไม่เห็นอะไรเลย
local function reportResult(player: Player, ok: boolean, message: string)
	actionResult:FireClient(player, ok, message)
end

local function dataOf(player: Player): Data?
	return DataService.getCached(player.UserId)
end

--------------------------------------------------------------------------------
-- สร้างไข่ — ทางเดียวที่ไข่เกิดได้
--------------------------------------------------------------------------------

-- ⚠️ ทุกทางที่ไข่เกิด (บอสวาง / แจกผู้เล่นใหม่ / คำสั่งเทสต์) ต้องผ่านตัวนี้
-- เพื่อให้ไม่มีไข่ฟองไหนหลุดออกมาโดยไม่มีน้ำหนัก
-- คืน (eggId, weight) — ส่วน id ประจำฟองแจกโดย PlayerData.addHeldEgg
local function rollEgg(eggId: string): (string?, number?)
	local egg = Config.getEgg(eggId)
	if not egg or not egg.enabled then
		return nil, nil
	end

	local weight = Config.rollMotherWeightForEgg(eggId, rng)
	if not weight then
		return nil, nil
	end

	return egg.id, weight
end

-- หาช่องว่างช่องแรกในสวนฟัก (อาเรย์ยาวคงที่) คืน nil ถ้าเต็ม
local function findFreeHatchSlot(hatching: { HatchSlot | false }): number?
	for index = 1, HATCH_SLOTS do
		if hatching[index] == false then
			return index
		end
	end
	return nil
end

local function countHatching(hatching: { HatchSlot | false }): number
	local total = 0
	for index = 1, HATCH_SLOTS do
		if hatching[index] ~= false then
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
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local rolledId, weight = rollEgg(eggId)
	if not rolledId or not weight then
		return false, `สร้างไข่ "{eggId}" ไม่ได้ (ไม่มีอยู่ หรือถูกปิดไปแล้ว)`
	end

	local egg = PlayerData.addHeldEgg(data.heldEggs, rolledId, weight)
	if not egg then
		return false, "ถือไข่เต็มแล้ว"
	end

	EggService.sync(player)

	print(`[EggService] {player.Name} ได้ {egg.eggId} #{egg.id} น้ำหนัก {Config.formatWeight(egg.weight)}`)
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

-- ⚠️ กระเป๋าไข่จุได้ถึง 10,000 ฟอง — **ห้ามส่งทั้งหมดทุกครั้งที่ sync**
-- sync วิ่งทุก SYNC_INTERVAL วินาที ส่งหมื่นฟองทุกวินาทีคือถล่มแบนด์วิดท์ของตัวเอง
-- ส่งเท่าที่ UI แสดงจริง + จำนวนรวม ที่เหลือรอจนกว่า UI จะทำ virtualize (Phase 5.5)
local HELD_EGGS_PER_SYNC = 50

local function buildSyncPayload(data: Data)
	local now = os.time()

	local heldItems = data.heldEggs.items
	local shown = math.min(#heldItems, HELD_EGGS_PER_SYNC)
	local held = table.create(shown)
	for index = 1, shown do
		local egg = heldItems[index]
		local eggType = Config.getEgg(egg.eggId)
		held[index] = {
			-- ⚠️ ส่ง id ประจำฟอง **ไม่ใช่ตำแหน่ง** — client ต้องอ้างกลับมาด้วย id นี้
			id = egg.id,
			eggId = egg.eggId,
			eggName = if eggType then eggType.name else egg.eggId,
			weight = egg.weight,
			weightText = Config.formatWeight(egg.weight),
		}
	end

	-- ⚠️ ข้อ D: slot ที่ครบเวลาฟักแล้วแต่ยังวางแม่ไม่ได้ (คอก+กระเป๋าเต็มพร้อมกัน) ยังนับเป็น
	-- occupied=true ตามปกติ (ไม่มีการเคลียร์ slot จนกว่าจะวางสำเร็จ — ดู hatch()) แค่ remaining=0
	-- ค้างอยู่เฉย ๆ · เพิ่ม stuck=true ให้ต่างหากเพื่อให้ client แยกแสดงได้ว่า "รอที่ว่าง" ไม่ใช่
	-- "กำลังฟักอยู่" และนับรวมเป็น stuckHatchCount ให้ข้อความแจ้งเตือนใช้
	local hatching: { SlotView } = table.create(HATCH_SLOTS)
	local stuckHatchCount = 0
	for index = 1, HATCH_SLOTS do
		local slot = data.hatching[index]
		-- ⚠️ ใช้ type() ไม่ใช่ `~= false` — Luau ขยาย `X | false` เป็น `X | boolean`
		-- ทำให้เทียบกับ false แล้วไม่แคบลง แต่ type() แคบลงได้เสมอ
		if type(slot) == "table" then
			local eggType = Config.getEgg(slot.eggId)
			local stuck = now >= slot.hatchAt
			if stuck then
				stuckHatchCount += 1
			end
			hatching[index] = {
				occupied = true,
				eggId = slot.eggId,
				eggName = if eggType then eggType.name else slot.eggId,
				weight = slot.weight,
				weightText = Config.formatWeight(slot.weight),
				remaining = math.max(0, slot.hatchAt - now),
				total = math.max(1, slot.hatchAt - slot.startedAt),
				stuck = stuck,
			}
		else
			hatching[index] = { occupied = false }
		end
	end

	local pen = table.create(#data.mothersInPen)
	for _, mother in data.mothersInPen do
		table.insert(pen, describeMother(mother))
	end

	local bag = table.create(#data.mothersInBag)
	for _, mother in data.mothersInBag do
		table.insert(bag, describeMother(mother))
	end

	-- ⚠️ กองลูก — จำนวน stack key ยังเล็กมาก (สถานะยังไม่เปิดใช้จริง) ส่งทั้งหมดได้
	-- ต่างจากกระเป๋าไข่ (10,000 ฟอง) ที่ต้อง virtualize เพราะเป็นคนละขนาดกัน
	local children = {}
	for key, count in data.children do
		local charId, weight, statuses = Config.parseStackKey(key)
		local character = if charId then Config.getCharacter(charId) else nil
		table.insert(children, {
			key = key,
			charName = if character then character.name else charId,
			class = if character then character.class else "?",
			weight = weight,
			weightText = if weight then Config.formatWeight(Config.getChildWeight(weight)) else "?",
			statuses = statuses,
			count = count,
		})
	end

	-- ⚠️ Phase 3A: ฟิลด์การรบ (stageProgress/summonEnabled/releaseOrder/...) มาจาก
	-- CombatService.buildSyncFields() ล้วน ๆ ไม่คำนวณซ้ำที่นี่ — แค่ merge เข้า payload เดียวกัน
	-- ให้ 3B ใช้ต่อได้โดยไม่ต้องมี RemoteEvent แยก
	local combat = CombatService.buildSyncFields(data)

	-- ⚠️ เพดานที่ซื้อได้ผูกกับ wallProgress (off-by-one: ด่าน 1 = 8 ขั้น ไม่ใช่ 0 — ดู
	-- docs/data-schema.md §8.6) ต้องเช็คเพดานนี้ก่อนถามราคา ไม่งั้น damageUpgradeCost จะไม่ nil
	-- ตอนติดเพดานด่าน ทั้งที่ยังไม่ถึงเพดานรวม 72 ขั้นของทั้งเกม
	local maxDamageLevel = Config.getMaxDamageLevel(data.wallProgress)
	local damageUpgradeCost = if data.damageLevel < maxDamageLevel
		then Config.getDamageUpgradeCost(data.damageLevel + 1)
		else nil

	return {
		heldEggs = held,
		heldCount = #heldItems,
		heldShown = shown,
		bagSize = Config.Balance.Hatchery.BAG_CAPACITY,
		hatching = hatching,
		hatchingCount = countHatching(data.hatching),
		hatcherySize = HATCH_SLOTS,
		mothersInPen = pen,
		mothersInBag = bag,
		penLevel = data.penLevel,
		penCapacity = Config.getPenCapacity(data.penLevel),
		penUpgradeCost = Config.getPenUpgradeCost(data.penLevel), -- nil = เต็มเพดานแล้ว
		bagCapacity = Config.Balance.Bag.CAPACITY,
		coins = data.currency.coins,
		wallProgress = data.wallProgress,
		damageLevel = data.damageLevel,
		maxDamageLevel = maxDamageLevel,
		damageMultiplier = Config.getArmyDamageMultiplier(data.damageLevel),
		damageUpgradeCost = damageUpgradeCost, -- nil = เต็มเพดานของด่านนี้แล้ว
		speedLevel = data.speedLevel,
		maxSpeedLevel = Config.Balance.SpeedUpgrade.MAX_LEVEL,
		walkSpeed = Config.getWalkSpeed(data.speedLevel),
		speedUpgradeCost = Config.getSpeedUpgradeCost(data.speedLevel), -- nil = เต็มเพดานแล้ว
		children = children,
		-- ⚠️ ข้อ D: จำนวนแม่ที่ฟักเสร็จแล้วแต่ยังค้างในสวนฟักเพราะคอก+กระเป๋าเต็มพร้อมกัน
		-- client ใช้ค่านี้โชว์ข้อความ "กระเป๋าแม่เต็ม ขายแม่บางตัวเพื่อรับแม่ที่ฟักเสร็จแล้ว" (ยังไม่ทำ UI เฟสนี้)
		stuckHatchCount = stuckHatchCount,
		activeStage = combat.activeStage,
		stageProgress = combat.stageProgress,
		summonEnabled = combat.summonEnabled,
		combatAutoPaused = combat.combatAutoPaused,
		releaseOrder = combat.releaseOrder,
	}
end

function EggService.sync(player: Player)
	local data = dataOf(player)
	if not data then
		return
	end
	farmStateSync:FireClient(player, buildSyncPayload(data))
end

--------------------------------------------------------------------------------
-- ฟักไข่
--------------------------------------------------------------------------------

-- ⚠️ ข้อ D (data-schema §13): คอก+กระเป๋าเต็มพร้อมกันตอนไข่ครบเวลาฟักพอดี
-- แก้โดย **ไม่แตะ schema เลย**: ถ้าวางแม่ไม่ได้ ให้ return เฉย ๆ โดยไม่เคลียร์ data.hatching[slotIndex]
-- และไม่ hideEgg — ไข่ฟองนั้นค้างอยู่ในสวนฟักเหมือนเดิมทุกอย่าง (โมเดลยังโชว์ ยังนับเป็นไข่ที่ฟักอยู่)
-- แค่ตอนนี้ "ครบเวลาแล้วแต่ยังไม่มีที่ให้ไปต่อ" — ตัวจับเวลาผ่าน 0 แล้วค้างที่ 0
-- รอบ tick ถัดไป / ตอนมีที่ว่างเปิด (ขายแม่ · อัปคอก · ย้ายแม่) จะเรียก hatch() ซ้ำที่ slot นี้เอง
-- (processReadyHatchSlots เห็น slot นี้ครบเวลาแล้วเสมอ จนกว่าจะวางสำเร็จจริง) ไม่ใช่บั๊ก เป็นการรอที่ตั้งใจ
local function hatch(player: Player, data: Data, slotIndex: number, slot: HatchSlot)
	-- ⚠️ ตัวละครสุ่มไว้แล้วตั้งแต่ตอนวางไข่ลงสวนฟัก (EggService.placeEgg) อ่านจาก slot.charId
	-- ตรง ๆ ไม่สุ่มใหม่ตรงนี้ — สุ่มใหม่จะทำให้เวลาฟักที่คำนวณไว้ตอนวาง (จากคลาสที่สุ่มได้ตอนนั้น)
	-- ไม่ตรงกับคลาสที่ได้จริงตอนฟัก
	--
	-- ⚠️ fallback: ช่องที่ค้างฟักมาจากก่อนเพิ่มฟิลด์นี้ (deploy รุ่นเก่า) จะไม่มี charId ติดมา
	-- สุ่มให้ตรงนี้แทนเป็นกรณีพิเศษ (เวลาฟักของช่องนั้นคำนวณจากคลาสเก่าไปแล้ว แก้ย้อนหลังไม่ได้
	-- แต่ไม่กระทบอะไรเพิ่ม เพราะไข่ฟักไปแล้วตอนนี้พอดี)
	local charId = slot.charId or Config.rollCharacter(slot.eggId, rng)
	if not charId then
		warn(`[EggService] ไข่ "{slot.eggId}" ไม่มีตารางคลาส ฟักไม่ได้`)
		-- ⚠️ เคสนี้ต่างจากข้อ D: แก้ด้วยการรอไม่ได้ (ตารางคลาสหายไปจริง ไม่ใช่แค่ที่เต็มชั่วคราว)
		-- เคลียร์ช่องทิ้งเหมือนพฤติกรรมเดิม กันไข่ค้างค้างอยู่ตลอดไปโดยไม่มีทางแก้
		data.hatching[slotIndex] = false
		PenService.hideEgg(player, slotIndex)
		return
	end

	local character = Config.getCharacter(charId)
	if not character then
		warn(`[EggService] ตารางคลาสของไข่ "{slot.eggId}" ชี้ไปที่ตัวละคร "{charId}" ที่ไม่มีอยู่`)
		data.hatching[slotIndex] = false
		PenService.hideEgg(player, slotIndex)
		return
	end

	-- ⚠️ เช็คที่ว่างก่อนเคลียร์ช่อง/ซ่อนโมเดลไข่เสมอ (ข้อ D) — ถ้าเต็มทั้งคู่ ไม่แตะอะไรเลย
	-- แล้วปล่อยให้ tick ถัดไปหรือ event ที่เปิดที่ว่าง (ขาย/อัปคอก/ย้ายแม่) มาเรียกซ้ำเอง
	local penFull = #data.mothersInPen >= Config.getPenCapacity(data.penLevel)
	local bagFull = #data.mothersInBag >= Config.Balance.Bag.CAPACITY
	if penFull and bagFull then
		return
	end

	-- ผ่านจุดนี้แปลว่าวางแม่ได้แน่นอน — ค่อยเคลียร์ช่อง/ซ่อนโมเดลไข่
	data.hatching[slotIndex] = false
	PenService.hideEgg(player, slotIndex)

	local mother: Mother = {
		uid = Config.makeUid(player.UserId, data.nextUid),
		charId = charId,
		weight = slot.weight, -- ← น้ำหนักเดิมของไข่ เป๊ะ
		statuses = {},
		-- ⚠️ ใช้ slot.hatchAt ไม่ใช่ os.time() — เวลาที่ "ควรฟักเสร็จจริง" ไม่ใช่เวลาที่โค้ดมาเช็คเจอ
		-- ต่างกันได้ถึง 8 ชั่วโมงตอนผู้เล่นล็อกอินกลับมาแล้วเช็คไข่ที่ค้างจากตอนออฟไลน์
		-- (docs/data-schema.md §5.3) ถ้าใช้ os.time() แม่ตัวนี้จะไม่ได้เครดิตผลิตย้อนหลังเลย
		-- ทั้งที่ควรได้ตั้งแต่วินาทีที่ไข่ครบเวลาจริง ไม่ใช่วินาทีที่ผู้เล่นเข้าเกม
		--
		-- ⚠️ ข้อ D: ถ้าแม่ตัวนี้เพิ่งค้างมาก่อน (เต็มตอนฟักเสร็จรอบแรก) ก็ยังใช้ hatchAt เดิมนี้
		-- ไม่ใช่เวลาที่วางสำเร็จจริง — เพดานออฟไลน์ 8 ชม. ของ ProductionService ครอบไว้อยู่แล้ว
		-- จึงไม่มีทางได้เครดิตเกินจริงแม้จะค้างอยู่นานกว่านั้น
		obtainedAt = slot.hatchAt,
		locked = false,
	}
	data.nextUid += 1

	local placedIn: string
	if not penFull then
		mother.lastProducedAt = slot.hatchAt
		table.insert(data.mothersInPen, mother)
		placedIn = "pen"
	else
		table.insert(data.mothersInBag, mother)
		placedIn = "bag"
	end

	data.stats.eggsHatched += 1
	if mother.weight > data.stats.heaviestMother then
		data.stats.heaviestMother = mother.weight
	end

	PenService.refreshMothers(player, data.mothersInPen)

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

-- ฟักไข่ทุกฟองในสวนที่ครบเวลาแล้ว ณ nowValue — ใช้ทั้งจาก loop ออนไลน์ (ทุก SYNC_INTERVAL)
-- และตอน login เพื่อ "ตามให้ทัน" ไข่ที่ครบเวลาไปแล้วระหว่างออฟไลน์
-- ⚠️ ต้องเรียกตัวนี้ก่อน settle การผลิตเสมอ (docs/data-schema.md §5.3) ไม่งั้นแม่ที่เพิ่งฟัก
-- ออกมาระหว่างช่วงออฟไลน์จะไม่ได้รับเครดิตผลิตย้อนหลังของตัวเองเลย
--
-- ⚠️ ตัวนี้ยังเป็นจุดเดียวที่ "ลองย้ายแม่ที่ค้างอยู่" (ข้อ D) เข้าคอก/กระเป๋าด้วย — เรียกซ้ำได้
-- ปลอดภัยเสมอ (slot ที่วางสำเร็จแล้วเป็น false ไปแล้ว จะไม่ถูกแตะซ้ำ)
--
-- ⚠️ ต้องเรียง slot ตาม hatchAt (น้อยสุดก่อน) ไม่ใช่ตาม slotIndex ตรง ๆ — สำคัญตอนคอก+กระเป๋า
-- เต็มพร้อมกันและมีหลายฟองค้างพร้อมกัน (ข้อ D) ต้องได้คิวตามลำดับฟักเสร็จก่อน-หลังจริง
-- ไม่ใช่ตามเลขช่องในสวนฟักซึ่งไม่มีความหมายเชิงเวลาเลย
local function processReadyHatchSlots(player: Player, data: Data, nowValue: number)
	local readySlots: { number } = {}
	for slotIndex = 1, HATCH_SLOTS do
		local slot = data.hatching[slotIndex]
		if type(slot) == "table" and nowValue >= slot.hatchAt then
			table.insert(readySlots, slotIndex)
		end
	end

	table.sort(readySlots, function(a, b)
		return (data.hatching[a] :: HatchSlot).hatchAt < (data.hatching[b] :: HatchSlot).hatchAt
	end)

	for _, slotIndex in readySlots do
		local slot = data.hatching[slotIndex]
		if type(slot) == "table" then
			hatch(player, data, slotIndex, slot)
		end
	end
end

--------------------------------------------------------------------------------
-- ย้ายไข่จากกระเป๋าเข้าสวนฟัก
--------------------------------------------------------------------------------

-- รับค่าดิบจาก client จึงประกาศเป็น unknown แล้วค่อย validate ทีละชั้น
--
-- ⚠️ รับ **id ประจำฟอง** ไม่ใช่ตำแหน่งในอาเรย์
-- `items` เป็นอาเรย์แน่น การลบฟองหนึ่งทำให้ฟองที่อยู่หลังมันเลื่อนตำแหน่งทั้งแถว
-- ถ้า client อ้างด้วยตำแหน่ง แล้วมีไข่ฟักเสร็จคั่นจังหวะพอดี เขาจะได้ไข่ผิดฟอง
-- (สวนฟัก 50 ช่องทำให้มีไข่ฟักเสร็จบ่อยมาก — ไม่ใช่เคสทฤษฎี)
function EggService.placeEgg(player: Player, rawEggId: unknown, rawSlotIndex: unknown): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local meta = sessionMeta[player.UserId]
	if not meta then
		return false, "ยังไม่มีเซสชัน"
	end

	-- 1) กันสแปม
	local now = os.time()
	if now - meta.lastRequestAt < WORLD.REQUEST_COOLDOWN then
		return false, "กดเร็วเกินไป"
	end
	meta.lastRequestAt = now

	-- 2) id ต้องเป็นจำนวนเต็มบวก และต้องหาเจอในกระเป๋าจริง
	-- ⚠️ ไม่มี "ช่วงที่อนุญาต" ให้เช็คอีกแล้ว — id เดินหน้าเรื่อย ๆ ไม่ผูกกับความจุ
	-- สิ่งที่ตัดสินว่าใช้ได้ไหมคือ "อยู่ใน items ของคนนี้หรือเปล่า" เท่านั้น
	if type(rawEggId) ~= "number" then
		return false, "eggId ไม่ใช่ number"
	end
	if rawEggId % 1 ~= 0 or rawEggId < 1 then
		return false, "eggId ต้องเป็นจำนวนเต็มบวก"
	end

	local _, heldEgg = PlayerData.findHeldEgg(data.heldEggs, rawEggId)
	if not heldEgg then
		return false, `ไม่มีไข่ #{rawEggId} ในกระเป๋า`
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
		local free = findFreeHatchSlot(data.hatching)
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
		if data.hatching[rawSlotIndex] ~= false then
			return false, "ช่องนี้มีไข่อยู่แล้ว"
		end
		slotIndex = rawSlotIndex
	end

	-- 5) สุ่มตัวละครตอนนี้เลย (ก่อนแตะกระเป๋า/สวนฟักจริง กันเซฟข้อมูลค้างถ้าสุ่มไม่ผ่าน)
	-- ⚠️ ย้ายมาจาก "ตอนฟักเสร็จ" — เวลาฟักต้องใช้คลาสมาคำนวณ (Config.getHatchSeconds)
	-- server รู้ผลไว้ก่อนแล้ว แต่ยังไม่ส่งให้ client เห็น (ดูคอมเมนต์หัวไฟล์)
	local charId = Config.rollCharacter(heldEgg.eggId, rng)
	if not charId then
		return false, `ไข่ "{heldEgg.eggId}" ไม่มีตารางคลาส ฟักไม่ได้`
	end

	-- ⚠️ ไข่ source="robux" (ไข่ตำนาน) ฟักคงที่เสมอ ไม่ขึ้นกับ tier/คลาส — ใช้ eggType.hatchTime
	-- ตรง ๆ · ไข่ source="boss" คำนวณจากน้ำหนัก+คลาสที่เพิ่งสุ่มได้ (Config.getHatchSeconds)
	local hatchSeconds: number
	if eggType.source == "robux" then
		hatchSeconds = eggType.hatchTime
	else
		hatchSeconds = Config.getHatchSeconds(heldEgg.weight, charId)
	end

	-- 6) ผ่านหมดแล้ว ย้ายทั้งฟอง (eggId + weight + charId) เข้าสวน
	-- ⚠️ ลบออกจากกระเป๋าด้วย id ไม่ใช่ตำแหน่งที่หาเจอเมื่อกี้ — กันกรณีอาเรย์ขยับระหว่างทาง
	PlayerData.removeHeldEgg(data.heldEggs, rawEggId)
	data.hatching[slotIndex] = {
		eggId = heldEgg.eggId,
		weight = heldEgg.weight, -- ← เดินทางไปด้วย ไม่สุ่มใหม่
		charId = charId, -- ← สุ่มไว้แล้ว ไม่บอก client จนกว่าจะฟักเสร็จ (ดู hatch())
		startedAt = now,
		hatchAt = now + hatchSeconds,
	}

	PenService.showEgg(player, slotIndex, eggType, heldEgg.weight)
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
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	if type(rawUid) ~= "string" then
		return false, "uid ไม่ใช่ string"
	end
	if rawTarget ~= "pen" and rawTarget ~= "bag" then
		return false, "ปลายทางต้องเป็น pen หรือ bag เท่านั้น"
	end

	if rawTarget == "pen" then
		if #data.mothersInPen >= Config.getPenCapacity(data.penLevel) then
			return false, "คอกเต็มแล้ว"
		end
		local mother = takeMother(data.mothersInBag, rawUid)
		if not mother then
			return false, "ไม่พบแม่ตัวนี้ในกระเป๋า"
		end
		-- เริ่มนับเวลาผลิตใหม่ตั้งแต่วินาทีที่เข้าคอก (Phase 2B จะใช้ค่านี้)
		mother.lastProducedAt = os.time()
		table.insert(data.mothersInPen, mother)
	else
		if #data.mothersInBag >= Config.Balance.Bag.CAPACITY then
			return false, "กระเป๋าเต็มแล้ว"
		end
		local mother = takeMother(data.mothersInPen, rawUid)
		if not mother then
			return false, "ไม่พบแม่ตัวนี้ในคอก"
		end
		-- ⚠️ ต้อง settle ผลผลิตค้างก่อนเอาออกจากคอกเสมอ (ทั้งลูกและเงิน) ไม่งั้นเวลาที่ยังไม่ settle
		-- จะหายไปเฉย ๆ — lastProducedAt ถูกล้างเป็น nil บรรทัดถัดไป พอออกจากคอกแล้วหาไม่เจออีกแล้ว
		ProductionService.settleMother(data, mother, true)
		-- แม่ในกระเป๋าไม่ผลิตอะไรเลย จึงไม่ต้องเก็บเวลาผลิตไว้
		mother.lastProducedAt = nil
		table.insert(data.mothersInBag, mother)
	end

	-- ⚠️ ย้ายแม่ = เปิดที่ว่างอีกฝั่งเสมอ (เข้าคอกเปิดที่ว่างในกระเป๋า / เข้ากระเป๋าเปิดที่ว่างในคอก)
	-- ลองย้ายแม่ที่ค้างในสวนฟักมาเข้าทันที เผื่อพอดีมีของรออยู่ (ข้อ D — data-schema §13)
	processReadyHatchSlots(player, data, os.time())

	PenService.refreshMothers(player, data.mothersInPen)
	EggService.sync(player)
	return true, nil
end

--------------------------------------------------------------------------------
-- จัดแม่เข้าคอกอัตโนมัติ — ฟีเจอร์ถาวร (ไม่ใช่ TEMP)
--------------------------------------------------------------------------------

-- ⚠️ เติมเฉพาะ "ช่องว่างที่เหลือ" เท่านั้น — ห้ามเตะแม่ที่อยู่ในคอกอยู่แล้วออกไม่ว่ากรณีไหน
-- (โค้ดนี้ไม่มี path ไหนแตะ data.mothersInPen นอกจากการ table.insert เพิ่มเข้าไปเลย)
-- เกณฑ์ "ดีที่สุด" = รายได้เงิน/นาทีสูงสุด ใช้ Config.getCoinsPerMinute() สูตรเดียวกับที่ทั้งเกม
-- ใช้จริงตรง ๆ (ไม่ใช้น้ำหนักเทียบตรง ๆ) เพราะสถานะ (Phase 7 — ยังไม่เปิดใช้) มีผลต่อรายได้ด้วย
-- แต่ไม่มีผลต่อน้ำหนัก ใช้สูตรจริงเผื่อผลลัพธ์ไม่เพี้ยนตอนสถานะเปิดใช้งานจริงทีหลัง
function EggService.autoFillPen(player: Player): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local freeSlots = Config.getPenCapacity(data.penLevel) - #data.mothersInPen
	if freeSlots <= 0 then
		return false, "คอกเต็มแล้ว"
	end
	if #data.mothersInBag == 0 then
		return false, "ไม่มีแม่ให้จัด"
	end

	-- เรียงกระเป๋าจากรายได้/นาทีมากไปน้อย แล้วหยิบจากหัวลิสต์ไปเรื่อย ๆ จนเต็มช่องว่างหรือกระเป๋าหมด
	table.sort(data.mothersInBag, function(a, b)
		return Config.getCoinsPerMinute(a.weight, data.wallProgress, a.statuses)
			> Config.getCoinsPerMinute(b.weight, data.wallProgress, b.statuses)
	end)

	local moved = 0
	while moved < freeSlots and #data.mothersInBag > 0 do
		local mother = table.remove(data.mothersInBag, 1)
		if not mother then
			-- ⚠️ เข้าไม่ถึงจริงเพราะเช็ค #data.mothersInBag > 0 ไว้แล้วในเงื่อนไข while
			-- แต่ table.remove() คืน T? เสมอตามชนิดของมัน ต้องเช็คให้ type checker ยอมผ่าน
			break
		end
		-- เริ่มนับเวลาผลิตใหม่ตั้งแต่วินาทีที่เข้าคอก (เหมือน moveMother ตอนย้ายเข้าคอก)
		mother.lastProducedAt = os.time()
		table.insert(data.mothersInPen, mother)
		moved += 1
	end

	-- ⚠️ เหตุผลเดียวกับ moveMother — เปิดที่ว่างในกระเป๋าแล้ว ลองย้ายแม่ที่ค้างในสวนฟักมาเข้าทันที
	-- เผื่อพอดีมีของรออยู่ (ข้อ D — data-schema §13)
	processReadyHatchSlots(player, data, os.time())

	PenService.refreshMothers(player, data.mothersInPen)
	EggService.sync(player)

	print(`[EggService] {player.Name} จัดแม่เข้าคอกอัตโนมัติ {moved} ตัว`)
	return true, nil
end

--------------------------------------------------------------------------------
-- อัปเกรดคอก
--------------------------------------------------------------------------------

-- ไม่มีพารามิเตอร์ — อัปคอกของผู้เล่นเองขึ้น 1 ขั้นเสมอ ใช้ตาราง Config.Balance.Pen ตรง ๆ
function EggService.upgradePen(player: Player): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local cost = Config.getPenUpgradeCost(data.penLevel)
	if not cost then
		return false, "คอกเต็มเพดานแล้ว"
	end
	if data.currency.coins < cost then
		return false, "เงินไม่พอ"
	end

	-- ⚠️ หักเงิน + เพิ่มเลเวลต้องทำพร้อมกันไม่มี yield คั่นกลาง (ไม่มี task.wait ระหว่างสองบรรทัดนี้)
	-- กันเคส "หักเงินแล้วแต่เลเวลไม่ขึ้น" ถ้ามี error กลางทาง — Luau เป็น single-thread
	-- ไม่มีจุด yield ระหว่างสองบรรทัดนี้เลย จึง atomic โดยธรรมชาติอยู่แล้ว
	data.currency.coins -= cost
	data.penLevel += 1

	-- ⚠️ ความจุที่เพิ่มขึ้นมีผลทันทีอยู่แล้ว เพราะทุกจุดอ่าน Config.getPenCapacity(data.penLevel)
	-- สด ๆ ทุกครั้ง (ไม่มีการ cache ความจุไว้ที่ไหน) — แต่ต้องลองดันแม่ที่ค้างเข้าคอกทันทีด้วย
	-- เผื่อเพิ่งเปิดที่ว่างพอดี (ข้อ D)
	processReadyHatchSlots(player, data, os.time())

	PenService.refreshMothers(player, data.mothersInPen)
	EggService.sync(player)

	print(`[EggService] {player.Name} อัปเกรดคอกเป็น Lv{data.penLevel} (จ่าย {cost} coins)`)
	return true, nil
end

--------------------------------------------------------------------------------
-- ขายแม่ — เฉพาะแม่ในกระเป๋าเท่านั้น (ย้อนกลับไม่ได้)
--------------------------------------------------------------------------------

-- ⚠️ ขายได้เฉพาะแม่ใน mothersInBag เท่านั้น (เหมือนกฎเดิม "ส่งรบได้แค่จากกระเป๋า")
-- กันขายพลาดตัวที่กำลังผลิตอยู่ในคอกโดยไม่ได้ตั้งใจ — อยากขายแม่ในคอกต้องย้ายออกมาก่อน
function EggService.sellMother(player: Player, rawUid: unknown): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	if type(rawUid) ~= "string" then
		return false, "uid ไม่ใช่ string"
	end

	local mother = takeMother(data.mothersInBag, rawUid)
	if not mother then
		-- ข้อความช่วยเหลือ: บอกสาเหตุที่ชัดเจนกว่าถ้าแม่ตัวนี้อยู่ในคอกจริง (ไม่ใช่ข้อมูลของคนอื่น
		-- เพราะเช็คแค่ในอาเรย์ของ player คนนี้เอง ไม่รั่วไหลข้อมูลข้ามบัญชี)
		for _, m in data.mothersInPen do
			if m.uid == rawUid then
				return false, "แม่ตัวนี้อยู่ในคอก ต้องย้ายเข้ากระเป๋าก่อนถึงขายได้"
			end
		end
		return false, "ไม่พบแม่ตัวนี้ในกระเป๋า"
	end

	-- ⚠️ คำนวณราคาฝั่ง server เท่านั้น — remote นี้รับแค่ uid ไม่มีพารามิเตอร์ราคาให้ client ส่งมาเอง
	-- ใช้ Config.getMotherSellPrice() ตัวเดียวกับที่ Config เตรียมไว้แล้ว (สูตร §2 ในสรุปท้ายงาน)
	local price = Config.getMotherSellPrice(mother.weight, data.wallProgress, mother.statuses)
	data.currency.coins += price
	data.stats.totalCoinsEarned += price

	-- ⚠️ ขายแล้วเปิดที่ว่างในกระเป๋า ลองย้ายแม่ที่ค้างในสวนฟักมาเข้าทันที (ข้อ D)
	processReadyHatchSlots(player, data, os.time())

	EggService.sync(player)

	print(`[EggService] {player.Name} ขายแม่ {mother.uid} ({Config.formatWeight(mother.weight)}) ได้ {price} coins`)
	return true, nil
end

--------------------------------------------------------------------------------
-- ซื้อตัวคูณ damage / ความเร็ว — ทั้งคู่เป็นของบัญชีผู้เล่น (ไม่ใช่ของแม่รายตัว)
--------------------------------------------------------------------------------

-- ตั้ง Humanoid.WalkSpeed จริงตาม speedLevel ที่ซื้อไว้ — เรียกทั้งตอนซื้อสำเร็จ (มีผลทันที
-- ไม่ต้องรอ respawn) และทุกครั้งที่ CharacterAdded (Roblox รีเซ็ต WalkSpeed กลับไปเป็นค่าฐาน
-- ของ StarterPlayer ทุกครั้งที่ Humanoid ใหม่ถูกสร้าง — ตายแล้วเกิดใหม่จะเสียตัวคูณถ้าไม่ตั้งซ้ำ)
function EggService.applyWalkSpeed(player: Player)
	local data = dataOf(player)
	if not data then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.getWalkSpeed(data.speedLevel)
	end
end

-- ⚠️ ไม่แตะ data.damageLevel นอกจากที่นี่ — CombatService อ่านค่านี้อย่างเดียว ไม่เคยเขียน
-- ซื้อได้ทีละขั้นเสมอ (ขั้นถัดไปจาก damageLevel ปัจจุบัน) ไม่มีพารามิเตอร์ให้ client เลือกขั้น
function EggService.buyDamageUpgrade(player: Player): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local maxLevel = Config.getMaxDamageLevel(data.wallProgress)
	if data.damageLevel >= maxLevel then
		return false, "ซื้อครบเพดานของด่านนี้แล้ว — พังกำแพงด่านถัดไปก่อนถึงจะซื้อเพิ่มได้"
	end

	-- ⚠️ getDamageUpgradeCost รับ "ขั้นที่กำลังจะซื้อ" (1-indexed) ไม่ใช่ขั้นที่มีอยู่ตอนนี้
	local nextLevel = data.damageLevel + 1
	local cost = Config.getDamageUpgradeCost(nextLevel)
	if not cost then
		return false, "ซื้อครบเพดานของด่านนี้แล้ว — พังกำแพงด่านถัดไปก่อนถึงจะซื้อเพิ่มได้"
	end
	if data.currency.coins < cost then
		return false, "เงินไม่พอ"
	end

	-- ⚠️ หักเงิน + เพิ่มขั้นต้องไม่มี yield คั่นกลาง (เหตุผลเดียวกับ upgradePen)
	data.currency.coins -= cost
	data.damageLevel = nextLevel

	EggService.sync(player)

	print(`[EggService] {player.Name} ซื้อตัวคูณ damage ขั้น {data.damageLevel}/{maxLevel} (จ่าย {cost} coins)`)
	return true, nil
end

-- ⚠️ ไม่แตะ data.speedLevel นอกจากที่นี่ · เพดาน MAX_LEVEL = 5 ขั้น ตัดสินถาวร ห้ามขยาย (§8.8)
function EggService.buySpeedUpgrade(player: Player): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	-- ⚠️ getSpeedUpgradeCost รับ "ขั้นที่มีอยู่ตอนนี้" (0-indexed) ต่างจาก getDamageUpgradeCost
	-- — ห้ามส่ง data.speedLevel + 1 เข้าไปเหมือนฝั่ง damage
	local cost = Config.getSpeedUpgradeCost(data.speedLevel)
	if not cost then
		return false, "ซื้อครบเพดานความเร็วแล้ว"
	end
	if data.currency.coins < cost then
		return false, "เงินไม่พอ"
	end

	data.currency.coins -= cost
	data.speedLevel += 1

	-- ⚠️ ต้องมีผลทันที ไม่ต้องรอ respawn — ผู้เล่นกดซื้อแล้วคาดว่าจะวิ่งเร็วขึ้นเลย
	EggService.applyWalkSpeed(player)
	EggService.sync(player)

	print(`[EggService] {player.Name} ซื้อความเร็ววิ่งขั้น {data.speedLevel} (จ่าย {cost} coins)`)
	return true, nil
end

--------------------------------------------------------------------------------
-- DEBUG เท่านั้น — ไม่มี UI เรียกผ่าน command bar ฝั่ง server:
--     local EggService = require(game.ServerScriptService.EggService)
--     EggService.debugFillHatchery(game.Players.<ชื่อ>)
--     EggService.debugClearBag(game.Players.<ชื่อ>)
--     EggService.debugResetAll(game.Players.<ชื่อ>)
--     EggService.debugGrantMother(game.Players.<ชื่อ>, 1500, "wukong", "pen")
--     EggService.debugGrantEggWithWeight(game.Players.<ชื่อ>, "egg_stage5", 100000000)
--     EggService.debugSetWallProgress(game.Players.<ชื่อ>, 7)
--     EggService.debugSetCurrency(game.Players.<ชื่อ>, 1000000)
--     EggService.debugSnapshot(game.Players.<ชื่อ>)
--     EggService.debugWipeSavedData(game.Players.<ชื่อ>, "<ชื่อ>")  -- 🔴 ลบถาวร ดูคำเตือนด้านล่าง
-- 📄 รายละเอียด + ตัวอย่างใช้ทดสอบครบทุก tier น้ำหนัก อยู่ใน docs/debug-commands.md
--------------------------------------------------------------------------------

-- เซฟทันทีให้ทุกฟังก์ชัน debug ในนี้ ไม่รอ autosave
-- ⚠️ releaseLock = false เหมือน autosave ปกติทุกประการ — แค่สั่งเองตอนนี้เลย
-- ไม่ปลด session lock ผู้เล่นเล่นต่อได้เหมือนไม่มีอะไรเกิดขึ้น (คนละเคสกับตอนออกเกม)
local function debugSaveNow(player: Player): string
	local ok, err = DataService.saveAsync(player.UserId, false)
	return if ok then "เซฟแล้ว" else `เซฟไม่สำเร็จ: {err}`
end

-- เอาไข่จากกระเป๋าผู้เล่นมาวางลงสวนฟักให้เต็มทุกช่องว่าง (หรือจนไข่ในกระเป๋าหมด)
-- ⚠️ ใช้ EggService.placeEgg() ตัวเดียวกับที่ปุ่มวางไข่ในเกมใช้จริงทุกฟอง
-- ผ่าน validate ครบทุกจุดเหมือนผู้เล่นกดเอง (eggId มีจริงในกระเป๋า, มีคอก, ช่องว่าง ฯลฯ)
-- ⚠️ ยกเว้นตัวกันสแปม REQUEST_COOLDOWN — นั่นเป็นตัวจับเวลาไม่ให้ "คนกดรัว" ไม่ใช่กฎถูก/ผิด
-- ของการวางไข่ ฟังก์ชันนี้ตั้งใจวางรัวในลูปเดียวเพื่อทดสอบเคส "สวนฟักเต็ม" ก่อนไข่ฟองแรก
-- จะฟักเสร็จ จึงรีเซ็ตให้เองทุกรอบ ไม่งั้นวางได้ฟองเดียวแล้วโดนปฏิเสธเป็น "กดเร็วเกินไป" ทันที
function EggService.debugFillHatchery(player: Player)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugFillHatchery: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return
	end

	local meta = sessionMeta[player.UserId]
	if not meta then
		warn(`[EggService] debugFillHatchery: {player.Name} ยังไม่มีเซสชัน`)
		return
	end

	local placed = 0
	while true do
		local nextEgg = data.heldEggs.items[1]
		if not nextEgg then
			break
		end

		meta.lastRequestAt = 0 -- ข้ามตัวกันสแปม (ดูเหตุผลด้านบน)
		local ok, reason = EggService.placeEgg(player, nextEgg.id, nil)
		if not ok then
			print(`[EggService] debugFillHatchery: {player.Name} หยุดที่ {placed} ฟอง — {reason}`)
			break
		end
		placed += 1
	end

	local hatchingNow = countHatching(data.hatching)
	print(
		`[EggService] debugFillHatchery: {player.Name} วางได้ {placed} ฟอง · `
			.. `เหลือในกระเป๋า {#data.heldEggs.items} ฟอง · `
			.. `สวนฟัก {hatchingNow}/{HATCH_SLOTS} `
			.. `({if hatchingNow >= HATCH_SLOTS then "เต็มแล้ว" else "ยังไม่เต็ม"}) · `
			.. debugSaveNow(player)
	)
end

-- ลบแม่ทั้งหมดในกระเป๋า (mothersInBag) + ไข่ทั้งหมดในกระเป๋า (heldEggs)
-- ⚠️ ไม่แตะแม่ในคอก (mothersInPen) และไม่แตะสวนฟัก (hatching) เลย
function EggService.debugClearBag(player: Player)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugClearBag: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return
	end

	local mothersRemoved = #data.mothersInBag
	local eggsRemoved = #data.heldEggs.items

	table.clear(data.mothersInBag)
	table.clear(data.heldEggs.items)

	EggService.sync(player)

	print(
		`[EggService] debugClearBag: {player.Name} ลบแม่ในกระเป๋า {mothersRemoved} ตัว · `
			.. `ไข่ในกระเป๋า {eggsRemoved} ฟอง · `
			.. debugSaveNow(player)
	)
end

-- ล้างทุกอย่าง: แม่ในคอก + แม่ในกระเป๋า + ไข่ในกระเป๋า + ไข่ที่กำลังฟัก + stageProgress + wallProgress
-- เหมือนเริ่มเกมใหม่ (แต่ไม่แจกไข่เริ่มต้นให้อัตโนมัติ — ต้องเรียก grantEgg เอง)
-- ⚠️ stageProgress/wallProgress เพิ่งเพิ่มเข้ามาทีหลัง (เดิมล้างแค่แม่/ไข่ ปล่อยสภาพที่ตั้งเอง
-- ผ่าน debugSetWallProgress หรือตีด่านทดสอบค้างไว้) ไม่แตะ CombatService เลย เพราะฟิลด์ทั้งสอง
-- เป็นแค่ข้อมูลใน PlayerData ธรรมดา (recompute logic ของ CombatService จะอ่านค่าที่ล้างแล้วเองในตาถัดไป)
-- ⚠️ ยังไม่ล้าง `currency`/`children`/`releaseOrder` — ไม่ใช่ "สภาพเริ่มต้นจริง" ทั้ง 100% (ยังไม่ได้ขอ)
function EggService.debugResetAll(player: Player)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugResetAll: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return
	end

	local motherPenRemoved = #data.mothersInPen
	local motherBagRemoved = #data.mothersInBag
	local eggsRemoved = #data.heldEggs.items

	-- ⚠️ ไข่ที่กำลังฟักมีโมเดลโชว์อยู่ในคอกด้วย ต้อง hideEgg ทีละช่องเหมือนตอนฟักเสร็จจริง
	-- ไม่งั้นข้อมูลถูกล้างแต่โมเดลไข่ค้างอยู่ในคอกให้เห็น (ข้อมูลกับภาพไม่ตรงกัน)
	local hatchingRemoved = 0
	for slotIndex = 1, HATCH_SLOTS do
		if type(data.hatching[slotIndex]) == "table" then
			PenService.hideEgg(player, slotIndex)
			data.hatching[slotIndex] = false
			hatchingRemoved += 1
		end
	end

	table.clear(data.mothersInPen)
	table.clear(data.mothersInBag)
	table.clear(data.heldEggs.items)

	-- ⚠️ ล้าง stageProgress ทุกด่านกลับเป็น false (รูปแบบเดียวกับ PlayerData.createNew()) แล้วดัน
	-- wallProgress กลับไปที่ค่าเริ่มต้นของผู้เล่นใหม่ — ไม่ใช่ 1 ดิบ ๆ เพราะ Config.Balance.NewPlayer
	-- คือแหล่งความจริงเดียวของค่าเริ่มต้น (เหตุผลเดียวกับที่ createNew() อ่านจากตรงนั้น)
	local wallProgressBefore = data.wallProgress
	local stageProgressCleared = 0
	for stage = 1, Config.Balance.Stage.COUNT do
		if data.stageProgress[stage] ~= false then
			stageProgressCleared += 1
		end
		data.stageProgress[stage] = false
	end
	data.wallProgress = Config.Balance.NewPlayer.wallProgress

	-- ⚠️ แม่ในคอกก็มีโมเดลเดินอยู่จริง ต้อง refreshMothers ให้คอกว่างตามข้อมูล
	PenService.refreshMothers(player, data.mothersInPen)
	EggService.sync(player)

	print(
		`[EggService] debugResetAll: {player.Name} ล้างแม่ในคอก {motherPenRemoved} ตัว · `
			.. `แม่ในกระเป๋า {motherBagRemoved} ตัว · ไข่ในกระเป๋า {eggsRemoved} ฟอง · `
			.. `ไข่ที่กำลังฟัก {hatchingRemoved} ฟอง · `
			.. `stageProgress ที่ล้าง {stageProgressCleared}/{Config.Balance.Stage.COUNT} ด่าน · `
			.. `wallProgress {wallProgressBefore} → {data.wallProgress} · `
			.. debugSaveNow(player)
	)
end

-- 🔴 ลบข้อมูลผู้เล่นออกจาก DataStore แบบถาวร กู้คืนไม่ได้ — ต่างจาก debugResetAll ตรงที่
-- debugResetAll แค่ล้างของในเกม (คอก/กระเป๋า/สวนฟัก) แต่ "ยังเป็นผู้เล่นเก่า" อยู่เสมอ
-- (isNew จะเป็น false ตลอดไป) ตัวนี้ลบทั้ง key ออกจาก DataStore เลย ทำให้เข้าเกมครั้งถัดไป
-- isNew = true จริง ได้ไข่เริ่มต้น (Config.Balance.NewPlayer.startingEggs) + ค่าเริ่มต้นทุกอย่าง
-- เหมือนผู้เล่นคนใหม่แกะกล่อง — ใช้ตอนต้องทดสอบ flow "ผู้เล่นใหม่" ซ้ำหลายรอบโดยไม่ต้องสลับ account
--
-- ⚠️ ต้องส่งชื่อผู้เล่นเป๊ะ ๆ เป็นอาร์กิวเมนต์ที่ 2 เพื่อยืนยัน กันเผลอรันคำสั่งที่ก็อปมาโดยไม่ทันคิด
-- ⚠️⚠️ เตะผู้เล่นออกทันทีหลังลบสำเร็จเสมอ — **ไม่ใช่บั๊ก ห้ามลบพฤติกรรมนี้ออก**
-- ข้อมูลของเซสชันปัจจุบันยังค้างอยู่ในหน่วยความจำ (ดูคอมเมนต์ที่ DataService.wipeAsync)
-- ถ้าปล่อยให้เล่นต่อ autosave รอบถัดไปจะเขียนของเก่ากลับเข้า DataStore ใหม่ทันที
-- ทำให้ลบไปแล้วก็เหมือนไม่ได้ลบ — ต้องออกจากเกมแล้วเข้าใหม่เท่านั้นถึงจะเห็นผลจริง
function EggService.debugWipeSavedData(player: Player, confirmName: string?): (boolean, string?)
	if confirmName ~= player.Name then
		warn(
			`[EggService] debugWipeSavedData: ต้องส่งชื่อผู้เล่นเป๊ะ ๆ เป็นอาร์กิวเมนต์ที่ 2 เพื่อยืนยัน `
				.. `(ลบข้อมูลถาวร กู้คืนไม่ได้) เช่น EggService.debugWipeSavedData(player, "{player.Name}")`
		)
		return false, "ต้องยืนยันด้วยชื่อผู้เล่น"
	end

	local ok, err = DataService.wipeAsync(player.UserId)
	if not ok then
		warn(`[EggService] debugWipeSavedData: ลบข้อมูลของ {player.Name} ไม่สำเร็จ: {err}`)
		return false, err
	end

	sessionMeta[player.UserId] = nil
	print(`[EggService] debugWipeSavedData: ลบข้อมูลของ {player.Name} แล้ว — กำลังเตะออกให้เข้าใหม่`)
	player:Kick("ข้อมูล (debug) ถูกลบเพื่อทดสอบ — เข้าเกมใหม่เพื่อเริ่มเป็นผู้เล่นใหม่")
	return true, nil
end

-- ⚠️ ใช้เป็นตารางคลาสอ้างอิงตอน debugGrantMother ต้องสุ่มคลาสเอง (charId = nil) — เครื่องมือนี้
-- ไม่ผูกกับด่านไหนอยู่แล้ว (ให้ระบุน้ำหนักได้ทุก tier อิสระจากด่าน) จึงต้องเลือกไข่สักชนิดมาใช้
-- ตารางคลาสของมัน · egg_stage1 รับประกันมีอยู่จริงและเปิดใช้เสมอ (validate() บังคับทุกด่านต้องมี
-- ไข่ของตัวเองที่เปิดใช้อยู่) จึงปลอดภัยสุดที่จะ hardcode ไว้ตรงนี้
local DEBUG_RANDOM_CLASS_EGG_ID = "egg_stage1"

-- สร้างแม่ตรง ๆ ข้ามขั้นตอนฟักทั้งหมด — ใช้ทดสอบขนาดโมเดล/ราคาขาย/ความจุคอกทุก tier
-- โดยไม่ต้องพึ่งการสุ่มธรรมชาติ (tier 7 = 100,000,000 kg ออกแค่ 1 ในล้านฟองจริง ทดสอบด้วยการ
-- สุ่มเล่น ๆ ไม่ทันแน่นอน)
--
-- charId = nil แปลว่า "สุ่มคลาสเอง เหมือนฟักไข่ปกติ" — ใช้ Config.rollCharacter() ตัวเดียวกับที่
-- placeEgg()/hatch() ใช้จริง ไม่เขียนตรรกะสุ่มคลาสซ้ำเอง (ดู DEBUG_RANDOM_CLASS_EGG_ID ด้านบน)
--
-- destination: "pen" | "bag" — ⚠️ ถ้า "pen" แต่คอกเต็ม **ปฏิเสธตรง ๆ ไม่ fallback ไปกระเป๋าเงียบ ๆ**
-- เพราะ fallback แบบนั้นจะทำให้เทสต์ "คอกเต็มพอดี" (ข้อ D) ที่ตั้งใจตั้งไว้เพี้ยนไปเป็นอย่างอื่น
-- โดยที่คนเรียกไม่รู้ตัว
function EggService.debugGrantMother(
	player: Player,
	weight: number,
	charId: string?,
	destination: string
): (boolean, string?)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugGrantMother: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local resolvedCharId: string
	if charId then
		resolvedCharId = charId
	else
		local rolled = Config.rollCharacter(DEBUG_RANDOM_CLASS_EGG_ID, rng)
		if not rolled then
			warn(`[EggService] debugGrantMother: สุ่มคลาสไม่สำเร็จ (ไม่มีตัวละครที่เปิดใช้อยู่เลย)`)
			return false, "สุ่มคลาสไม่สำเร็จ"
		end
		resolvedCharId = rolled
	end

	local character = Config.getCharacter(resolvedCharId)
	if not character then
		warn(`[EggService] debugGrantMother: ไม่มีตัวละคร "{resolvedCharId}" ใน Config`)
		return false, `ไม่มีตัวละคร "{resolvedCharId}"`
	end

	if destination ~= "pen" and destination ~= "bag" then
		warn(`[EggService] debugGrantMother: destination ต้องเป็น "pen" หรือ "bag" เท่านั้น`)
		return false, `destination ต้องเป็น "pen" หรือ "bag" เท่านั้น`
	end

	-- ⚠️ น้ำหนักแม่ต้องเป็นจำนวนเต็มเสมอ (เป็นส่วนหนึ่งของ stack key) — เครื่องมือ debug ก็ต้อง
	-- รักษากติกานี้ ไม่งั้นกองลูกที่ผลิตจากแม่ตัวนี้ทีหลังจะได้ stack key เพี้ยนไปจากแม่ตัวอื่น
	local flooredWeight = math.floor(weight)
	if flooredWeight <= 0 then
		warn(`[EggService] debugGrantMother: น้ำหนักต้องมากกว่า 0`)
		return false, "น้ำหนักต้องมากกว่า 0"
	end

	-- เช็คที่ว่างก่อนสร้างแม่จริง กันเปลือง uid (เดินหน้าอย่างเดียว ห้าม reuse) ถ้าจะโดนปฏิเสธ
	if destination == "pen" and #data.mothersInPen >= Config.getPenCapacity(data.penLevel) then
		warn(`[EggService] debugGrantMother: {player.Name} คอกเต็มแล้ว`)
		return false, "คอกเต็มแล้ว"
	end
	if destination == "bag" and #data.mothersInBag >= Config.Balance.Bag.CAPACITY then
		warn(`[EggService] debugGrantMother: {player.Name} กระเป๋าเต็มแล้ว`)
		return false, "กระเป๋าเต็มแล้ว"
	end

	local mother: Mother = {
		uid = Config.makeUid(player.UserId, data.nextUid),
		charId = resolvedCharId,
		weight = flooredWeight,
		statuses = {},
		obtainedAt = os.time(),
		locked = false,
	}
	data.nextUid += 1

	if destination == "pen" then
		mother.lastProducedAt = os.time()
		table.insert(data.mothersInPen, mother)
		PenService.refreshMothers(player, data.mothersInPen)
	else
		table.insert(data.mothersInBag, mother)
	end

	EggService.sync(player)

	print(
		`[EggService] debugGrantMother: {player.Name} ได้ {character.name} ({character.class}) `
			.. `{Config.formatWeight(flooredWeight)} → {destination} · `
			.. debugSaveNow(player)
	)
	return true, nil
end

-- วางไข่ในกระเป๋าโดย**บังคับน้ำหนัก**ตามที่ระบุ (ข้าม RNG ของ Config.rollMotherWeightForEgg)
-- ยังคงสุ่ม "ตัวละคร" ตามตารางคลาสของ eggId นั้นตามปกติตอนวางลงสวนฟัก (ไม่ได้บังคับคลาส)
-- ใช้ทดสอบว่าขนาดโมเดลไข่/เวลาฟักคำนวณถูกตามน้ำหนักที่กำหนดครบทุก tier
function EggService.debugGrantEggWithWeight(player: Player, eggId: string, weightOverride: number): (boolean, string?)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugGrantEggWithWeight: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local egg = Config.getEgg(eggId)
	if not egg or not egg.enabled then
		warn(`[EggService] debugGrantEggWithWeight: ไข่ "{eggId}" ไม่มีอยู่หรือถูกปิดไปแล้ว`)
		return false, `ไข่ "{eggId}" ไม่มีอยู่หรือถูกปิดไปแล้ว`
	end

	-- ⚠️ เหตุผลเดียวกับ debugGrantMother — น้ำหนักไข่/แม่ต้องเป็นจำนวนเต็มเสมอ
	local flooredWeight = math.floor(weightOverride)
	if flooredWeight <= 0 then
		warn(`[EggService] debugGrantEggWithWeight: น้ำหนักต้องมากกว่า 0`)
		return false, "น้ำหนักต้องมากกว่า 0"
	end

	local heldEgg = PlayerData.addHeldEgg(data.heldEggs, egg.id, flooredWeight)
	if not heldEgg then
		warn(`[EggService] debugGrantEggWithWeight: {player.Name} ถือไข่เต็มแล้ว`)
		return false, "ถือไข่เต็มแล้ว"
	end

	EggService.sync(player)

	print(
		`[EggService] debugGrantEggWithWeight: {player.Name} ได้ {heldEgg.eggId} #{heldEgg.id} `
			.. `น้ำหนักบังคับ {Config.formatWeight(heldEgg.weight)} · `
			.. debugSaveNow(player)
	)
	return true, nil
end

-- ตั้งค่า wallProgress ที่เก็บฝั่ง server ตรง ๆ — ⚠️ คนละตัวกับกำแพงที่ WallRenderer วาดฝั่ง
-- client (client ยังไม่ได้รับค่านี้ผ่าน sync ในเฟสนี้ ตั้งแล้วต้องดูผลจากสูตร ไม่ใช่จากภาพกำแพง)
-- ใช้ทดสอบสูตรเงิน (Config.getCoinsPerMinute) และเพดาน damage upgrade ที่ผูกกับ wallProgress
function EggService.debugSetWallProgress(player: Player, n: number)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugSetWallProgress: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return
	end

	local before = data.wallProgress
	-- ⚠️ clamp ในช่วง 1..จำนวนด่าน เหมือนที่ Config.getCoinsPerMinute/getMaxDamageLevel ทำเอง
	-- ตั้งนอกช่วงนี้ไม่มีความหมายเชิงเกม (ไม่มีด่านที่ 0 หรือด่านที่ 10)
	local clamped = math.clamp(math.floor(n), 1, Config.Balance.Stage.COUNT)
	data.wallProgress = clamped

	EggService.sync(player)

	print(
		`[EggService] debugSetWallProgress: {player.Name} {before} → {clamped}`
			.. `{if clamped ~= n then ` (ปัด/clamp จาก {n})` else ""} · `
			.. debugSaveNow(player)
	)
end

-- ตั้งค่า currency.coins ตรง ๆ — ใช้ทดสอบอัปเกรดคอก/ขายแม่โดยไม่ต้องรอสะสมเงินจริง
-- ⚠️ แตะแค่ coins ไม่แตะ gems (คนละบ่อ ยังไม่มีระบบ Robux ให้ debug ในเฟสนี้)
function EggService.debugSetCurrency(player: Player, coins: number)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugSetCurrency: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return
	end

	local before = data.currency.coins
	local clamped = math.max(0, math.floor(coins))
	data.currency.coins = clamped

	EggService.sync(player)

	print(`[EggService] debugSetCurrency: {player.Name} เงิน {before} → {clamped} coins · ` .. debugSaveNow(player))
end

-- พิมพ์ข้อมูลสำคัญทั้งหมดของผู้เล่นแบบอ่านง่าย — ⚠️ read-only ไม่แก้อะไรเลย จึงไม่เซฟ
-- (เซฟข้อมูลที่ไม่เปลี่ยนแปลงคือเขียน DataStore ทิ้งเปล่า ๆ) ใช้หา uid จริงของแม่เพื่อทดสอบ
-- SellMotherRequest/MoveMotherRequest ต่อผ่าน command bar
function EggService.debugSnapshot(player: Player)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugSnapshot: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return
	end

	print(`━━ debugSnapshot: {player.Name} ━━`)
	print(`  เงิน: {data.currency.coins} coins · {data.currency.gems} gems`)
	print(
		`  คอก: Lv{data.penLevel} ({#data.mothersInPen}/{Config.getPenCapacity(data.penLevel)}) · `
			.. `wallProgress: {data.wallProgress}`
	)

	print(`  แม่ในคอก ({#data.mothersInPen} ตัว):`)
	for _, mother in data.mothersInPen do
		print(`    · {mother.uid} — {mother.charId} {Config.formatWeight(mother.weight)}`)
	end

	print(`  แม่ในกระเป๋า ({#data.mothersInBag}/{Config.Balance.Bag.CAPACITY} ตัว):`)
	for _, mother in data.mothersInBag do
		print(`    · {mother.uid} — {mother.charId} {Config.formatWeight(mother.weight)}`)
	end

	print(`  ไข่ในกระเป๋า: {#data.heldEggs.items} ฟอง`)

	local now = os.time()
	local occupiedSlots = 0
	for slotIndex = 1, HATCH_SLOTS do
		local slot = data.hatching[slotIndex]
		if type(slot) == "table" then
			occupiedSlots += 1
			local status = if now >= slot.hatchAt
				then "ครบเวลาแล้ว — ค้างรอที่ว่าง (ข้อ D)"
				else `เหลืออีก {slot.hatchAt - now} วิ`
			print(`    · ช่อง {slotIndex}: {slot.eggId} {Config.formatWeight(slot.weight)} — {status}`)
		end
	end
	print(`  สวนฟัก: {occupiedSlots}/{HATCH_SLOTS} ช่องไม่ว่าง`)
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end

--------------------------------------------------------------------------------
-- วงจรชีวิตผู้เล่น
--------------------------------------------------------------------------------

-- คืน false เมื่อโหลดข้อมูลไม่ได้ — ผู้เล่นถูกเตะออกไปแล้วตอนนั้น
function EggService.onPlayerAdded(player: Player): boolean
	local data, err, isNew = DataService.loadAsync(player.UserId)
	if not data then
		-- ⚠️ เตะออก ไม่ปล่อยให้เล่นต่อด้วยข้อมูลเปล่า
		-- ปล่อยเล่นต่อ = autosave รอบถัดไปเขียนข้อมูลเปล่าทับของจริงที่ยังอยู่ครบ
		warn(`[EggService] โหลดข้อมูลของ {player.Name} ไม่สำเร็จ: {err}`)
		player:Kick(err or DataService.LOAD_FAILED_MESSAGE)
		return false
	end

	sessionMeta[player.UserId] = { lastRequestAt = 0 }

	-- ⚠️ แจกไข่เริ่มต้น **เฉพาะผู้เล่นใหม่จริง ๆ**
	-- ถ้าแจกทุกครั้งที่เข้าเกม ผู้เล่นจะได้ไข่ฟรีทุกล็อกอิน = ฟาร์มด้วยการ rejoin
	-- (บั๊กแบบนี้มองไม่เห็นตอนยังไม่มี DataStore เพราะทุกคนเป็นผู้เล่นใหม่ตลอด)
	if isNew then
		-- แจกทีละฟองผ่าน grantEgg เพื่อให้แต่ละฟองได้สุ่มน้ำหนักของตัวเอง
		-- startingEggs เป็นแค่ "คำสั่งแจก" ไม่ใช่รูปแบบที่เก็บ
		for eggId, amount in Config.Balance.NewPlayer.startingEggs do
			for _ = 1, amount do
				EggService.grantEgg(player, eggId)
			end
		end
		print(`[EggService] {player.Name} เป็นผู้เล่นใหม่ — แจกไข่เริ่มต้นแล้ว`)
	end

	-- ⚠️ ลำดับตอน login ห้ามสลับ (docs/data-schema.md §5.3):
	--   1. โหลดข้อมูล (ทำไปแล้วข้างบน)
	--   2. เคลียร์ไข่ที่ฟักครบระหว่างออฟไลน์ก่อน — สร้างแม่ใหม่ตั้ง lastProducedAt = hatchAt
	--   3. ค่อย settle การผลิตออฟไลน์ (ต้องรวมแม่ที่เพิ่งฟักในข้อ 2 ด้วย)
	-- ถ้าสลับ 2 กับ 3 แม่ที่ฟักออกมาตอนชั่วโมงแรกของการออฟไลน์ 8 ชั่วโมงจะไม่ได้เครดิตย้อนหลังเลย
	local nowValue = os.time()
	processReadyHatchSlots(player, data, nowValue)
	ProductionService.settleAllInPen(data, false)

	-- วาดแม่ที่โหลดกลับมาลงคอก (รวมแม่ที่เพิ่งฟักเสร็จในข้อ 2 ด้วยแล้ว)
	PenService.refreshMothers(player, data.mothersInPen)

	-- ⚠️ ไข่ที่ยัง**ไม่ครบเวลา**ค้างอยู่ในสวนตอนออกเกมต้องกลับมาโชว์ในคอกด้วย
	for slotIndex = 1, HATCH_SLOTS do
		local slot = data.hatching[slotIndex]
		if type(slot) == "table" then
			local eggType = Config.getEgg(slot.eggId)
			if eggType then
				PenService.showEgg(player, slotIndex, eggType, slot.weight)
			end
		end
	end

	EggService.sync(player)
	return true
end

function EggService.onPlayerRemoving(player: Player)
	sessionMeta[player.UserId] = nil

	-- ไม่มีข้อมูลในมือ = โหลดไม่สำเร็จแล้วถูกเตะไปตั้งแต่แรก ไม่มีอะไรให้เซฟ
	-- ⚠️ และ **ห้ามเซฟ** ด้วย เพราะจะกลายเป็นเขียนข้อมูลเปล่าทับของจริง
	local data = DataService.getCached(player.UserId)
	if not data then
		return
	end

	-- ⚠️ settle การผลิตออนไลน์ให้ถึง now ก่อนเซฟเสมอ (docs/data-schema.md §5.4)
	-- ไม่งั้นเวลาที่เพิ่งเล่นอยู่ช่วงท้ายจะถูกนับเป็นออฟไลน์ (ช้ากว่า 10 เท่า) ตอนเข้าเกมครั้งหน้า
	ProductionService.settleAllInPen(data, true)

	-- ⚠️ ปลด session lock ด้วยเสมอ ไม่งั้นเข้าเกมใหม่ไม่ได้จนกว่า lock จะหมดอายุ 5 นาที
	local ok, err = DataService.saveAsync(player.UserId, true)
	if ok then
		print(`[EggService] เซฟข้อมูลของ {player.Name} แล้ว`)
	else
		warn(`[EggService] เซฟข้อมูลของ {player.Name} ไม่สำเร็จ: {err}`)
	end
	DataService.forget(player.UserId)
end

function EggService.getMothersInPen(player: Player): { Mother }
	local data = dataOf(player)
	return if data then data.mothersInPen else {}
end

function EggService.getMothersInBag(player: Player): { Mother }
	local data = dataOf(player)
	return if data then data.mothersInBag else {}
end

--------------------------------------------------------------------------------
-- เริ่มระบบ
--------------------------------------------------------------------------------

function EggService.start()
	placeEggRequest = Remotes.waitFor(Config.RemoteNames.PLACE_EGG_IN_HATCHERY_REQUEST)
	moveMotherRequest = Remotes.waitFor(Config.RemoteNames.MOVE_MOTHER_REQUEST)
	upgradePenRequest = Remotes.waitFor(Config.RemoteNames.UPGRADE_PEN_REQUEST)
	sellMotherRequest = Remotes.waitFor(Config.RemoteNames.SELL_MOTHER_REQUEST)
	autoFillPenRequest = Remotes.waitFor(Config.RemoteNames.AUTO_FILL_PEN_REQUEST)
	buyDamageUpgradeRequest = Remotes.waitFor(Config.RemoteNames.BUY_DAMAGE_UPGRADE_REQUEST)
	buySpeedUpgradeRequest = Remotes.waitFor(Config.RemoteNames.BUY_SPEED_UPGRADE_REQUEST)
	eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
	farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)
	actionResult = Remotes.waitFor(Config.RemoteNames.ACTION_RESULT)

	placeEggRequest.OnServerEvent:Connect(function(player, rawEggId, rawSlotIndex)
		local ok, reason = EggService.placeEgg(player, rawEggId, rawSlotIndex)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอวางไข่ของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "วางไข่ไม่สำเร็จ")
		end
		-- ⚠️ ไม่ส่งข้อความสำเร็จตรงนี้ — "วางลงสวนฟักสำเร็จ" ≠ "ฟักเสร็จ" (ยังต้องรอเวลา)
		-- eggHatched มีข้อความของตัวเองอยู่แล้วตอนฟักเสร็จจริง ส่งซ้อนกันจะงงเปล่า ๆ
	end)

	moveMotherRequest.OnServerEvent:Connect(function(player, rawUid, rawTarget)
		local ok, reason = EggService.moveMother(player, rawUid, rawTarget)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอย้ายแม่ของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "ย้ายแม่ไม่สำเร็จ")
		else
			local destText = if rawTarget == "pen" then "คอก" else "กระเป๋า"
			reportResult(player, true, `ย้ายแม่ → {destText} สำเร็จ`)
		end
	end)

	upgradePenRequest.OnServerEvent:Connect(function(player)
		local ok, reason = EggService.upgradePen(player)
		if not ok then
			print(`[EggService] ปฏิเสธคำขออัปเกรดคอกของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "อัปเกรดคอกไม่สำเร็จ")
		else
			local data = dataOf(player)
			local level = if data then data.penLevel else nil
			local capacity = if level then Config.getPenCapacity(level) else nil
			reportResult(player, true, `อัปเกรดคอกสำเร็จ → Lv{level} (จุแม่ได้ {capacity} ตัว)`)
		end
	end)

	sellMotherRequest.OnServerEvent:Connect(function(player, rawUid)
		local data = dataOf(player)
		local coinsBefore = if data then data.currency.coins else 0
		local ok, reason = EggService.sellMother(player, rawUid)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอขายแม่ของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "ขายแม่ไม่สำเร็จ")
		else
			local coinsAfter = if data then data.currency.coins else coinsBefore
			reportResult(player, true, `ขายแม่สำเร็จ +{coinsAfter - coinsBefore} coins`)
		end
	end)

	autoFillPenRequest.OnServerEvent:Connect(function(player)
		local data = dataOf(player)
		local penBefore = if data then #data.mothersInPen else 0
		local ok, reason = EggService.autoFillPen(player)
		if not ok then
			print(`[EggService] จัดแม่เข้าคอกอัตโนมัติของ {player.Name} ไม่ทำอะไร: {reason}`)
			reportResult(player, false, reason or "จัดแม่เข้าคอกไม่สำเร็จ")
		else
			local penAfter = if data then #data.mothersInPen else penBefore
			reportResult(player, true, `จัดแม่เข้าคอกสำเร็จ +{penAfter - penBefore} ตัว`)
		end
	end)

	buyDamageUpgradeRequest.OnServerEvent:Connect(function(player)
		local ok, reason = EggService.buyDamageUpgrade(player)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอซื้อ damage upgrade ของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "ซื้อตัวคูณ damage ไม่สำเร็จ")
		else
			local data = dataOf(player)
			local level = if data then data.damageLevel else nil
			reportResult(player, true, `ซื้อตัวคูณ damage สำเร็จ → ขั้น {level}`)
		end
	end)

	buySpeedUpgradeRequest.OnServerEvent:Connect(function(player)
		local ok, reason = EggService.buySpeedUpgrade(player)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอซื้อความเร็วของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "ซื้อความเร็วไม่สำเร็จ")
		else
			local data = dataOf(player)
			local level = if data then data.speedLevel else nil
			reportResult(player, true, `ซื้อความเร็วสำเร็จ → ขั้น {level}`)
		end
	end)

	-- ลูปเดียวคุมทั้งการฟักและการ sync
	-- ความละเอียดของตัวจับเวลา = SYNC_INTERVAL
	task.spawn(function()
		while true do
			task.wait(WORLD.SYNC_INTERVAL)

			local nowValue = os.time()
			for _, player in Players:GetPlayers() do
				local data = dataOf(player)
				if data then
					processReadyHatchSlots(player, data, nowValue)
					EggService.sync(player)
				end
			end
		end
	end)
end

return EggService
