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
local eggHatched: RemoteEvent
local farmStateSync: RemoteEvent

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

	local hatching: { SlotView } = table.create(HATCH_SLOTS)
	for index = 1, HATCH_SLOTS do
		local slot = data.hatching[index]
		-- ⚠️ ใช้ type() ไม่ใช่ `~= false` — Luau ขยาย `X | false` เป็น `X | boolean`
		-- ทำให้เทียบกับ false แล้วไม่แคบลง แต่ type() แคบลงได้เสมอ
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
		penCapacity = Config.getPenCapacity(data.penLevel),
		bagCapacity = Config.Balance.Bag.CAPACITY,
		coins = data.currency.coins,
		children = children,
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

local function hatch(player: Player, data: Data, slotIndex: number, slot: HatchSlot)
	data.hatching[slotIndex] = false
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
		uid = Config.makeUid(player.UserId, data.nextUid),
		charId = charId,
		weight = slot.weight, -- ← น้ำหนักเดิมของไข่ เป๊ะ
		statuses = {},
		-- ⚠️ ใช้ slot.hatchAt ไม่ใช่ os.time() — เวลาที่ "ควรฟักเสร็จจริง" ไม่ใช่เวลาที่โค้ดมาเช็คเจอ
		-- ต่างกันได้ถึง 8 ชั่วโมงตอนผู้เล่นล็อกอินกลับมาแล้วเช็คไข่ที่ค้างจากตอนออฟไลน์
		-- (docs/data-schema.md §5.3) ถ้าใช้ os.time() แม่ตัวนี้จะไม่ได้เครดิตผลิตย้อนหลังเลย
		-- ทั้งที่ควรได้ตั้งแต่วินาทีที่ไข่ครบเวลาจริง ไม่ใช่วินาทีที่ผู้เล่นเข้าเกม
		obtainedAt = slot.hatchAt,
		locked = false,
	}
	data.nextUid += 1

	-- คอกมีที่ว่างก็เข้าคอก (ผลิตได้) ไม่งั้นเข้ากระเป๋า
	local placedIn: string
	if #data.mothersInPen < Config.getPenCapacity(data.penLevel) then
		mother.lastProducedAt = slot.hatchAt
		table.insert(data.mothersInPen, mother)
		placedIn = "pen"
	elseif #data.mothersInBag < Config.Balance.Bag.CAPACITY then
		table.insert(data.mothersInBag, mother)
		placedIn = "bag"
	else
		-- คอกและกระเป๋าเต็มทั้งคู่ — แม่ตัวนี้หายไป
		-- ⚠️ Phase 2B ต้องเปลี่ยนเป็น "ค้างไว้ในสวนจนกว่าจะมีที่ว่าง" (data-schema §13 ข้อ D)
		warn(`[EggService] {player.Name} คอกและกระเป๋าเต็ม แม่ที่ฟักได้หายไป`)
		return
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
local function processReadyHatchSlots(player: Player, data: Data, nowValue: number)
	for slotIndex = 1, HATCH_SLOTS do
		local slot = data.hatching[slotIndex]
		if type(slot) == "table" and nowValue >= slot.hatchAt then
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

	-- 5) ผ่านหมดแล้ว ย้ายทั้งฟอง (eggId + weight) เข้าสวน
	-- ⚠️ ลบออกจากกระเป๋าด้วย id ไม่ใช่ตำแหน่งที่หาเจอเมื่อกี้ — กันกรณีอาเรย์ขยับระหว่างทาง
	PlayerData.removeHeldEgg(data.heldEggs, rawEggId)
	data.hatching[slotIndex] = {
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

	PenService.refreshMothers(player, data.mothersInPen)
	EggService.sync(player)
	return true, nil
end

--------------------------------------------------------------------------------
-- DEBUG เท่านั้น — ไม่มี UI เรียกผ่าน command bar ฝั่ง server:
--     local EggService = require(game.ServerScriptService.EggService)
--     EggService.debugFillHatchery(game.Players.<ชื่อ>)
--     EggService.debugClearBag(game.Players.<ชื่อ>)
--     EggService.debugResetAll(game.Players.<ชื่อ>)
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

-- ล้างทุกอย่าง: แม่ในคอก + แม่ในกระเป๋า + ไข่ในกระเป๋า + ไข่ที่กำลังฟัก
-- เหมือนเริ่มเกมใหม่ (แต่ไม่แจกไข่เริ่มต้นให้อัตโนมัติ — ต้องเรียก grantEgg เอง)
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

	-- ⚠️ แม่ในคอกก็มีโมเดลเดินอยู่จริง ต้อง refreshMothers ให้คอกว่างตามข้อมูล
	PenService.refreshMothers(player, data.mothersInPen)
	EggService.sync(player)

	print(
		`[EggService] debugResetAll: {player.Name} ล้างแม่ในคอก {motherPenRemoved} ตัว · `
			.. `แม่ในกระเป๋า {motherBagRemoved} ตัว · ไข่ในกระเป๋า {eggsRemoved} ฟอง · `
			.. `ไข่ที่กำลังฟัก {hatchingRemoved} ฟอง · `
			.. debugSaveNow(player)
	)
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
				PenService.showEgg(player, slotIndex, eggType)
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
	eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
	farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)

	placeEggRequest.OnServerEvent:Connect(function(player, rawEggId, rawSlotIndex)
		local ok, reason = EggService.placeEgg(player, rawEggId, rawSlotIndex)
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
