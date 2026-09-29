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
-- ผลของ "สวมใส่ที่ดีที่สุด" (autoFillPen) — ไว้ให้ handler ประกอบข้อความตอบกลับ
export type EquipBestSummary = { movedIn: number, movedOut: number }

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
local sellMothersBatchRequest: RemoteEvent
local sendMotherToBattleRequest: RemoteEvent
local sendMothersToBattleBatchRequest: RemoteEvent
local autoFillPenRequest: RemoteEvent
local buyDamageUpgradeRequest: RemoteEvent
local buySpeedUpgradeRequest: RemoteEvent
local buyClubTierRequest: RemoteEvent
local eggHatched: RemoteEvent
local farmStateSync: RemoteEvent
local actionResult: RemoteEvent
local stageClearedNotify: RemoteEvent
local toggleMotherLockRequest: RemoteEvent

-- Phase 5A: ผู้เล่นติดล็อกอัญเชิญเพราะบอสไหม — BossService เป็นเจ้าของสถานะ (Main.server.lua ต่อสายผ่าน
-- setBossLockProvider) · inject แทน require ตรง ๆ ให้ harness ใน tools/ ที่โหลดไฟล์นี้ไม่ต้องรู้จัก BossService
-- ค่าเริ่มต้น = ไม่มีใครถูกล็อก (ก่อนต่อสาย / ในเทสต์)
local isBossLocked: (userId: number) -> boolean = function(_userId)
	return false
end

function EggService.setBossLockProvider(provider: (userId: number) -> boolean)
	isBossLocked = provider
end

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

-- ⚠️ ทางเดียวที่ไข่ (ที่มีน้ำหนักแล้ว) เข้ากระเป๋า — grantEgg (สุ่มน้ำหนักเอง) กับไข่บอส 5B (น้ำหนักสุ่มไว้ตั้งแต่บอสเกิด)
-- ใช้ตัวเดียวกัน: PlayerData.addHeldEgg → sync → log · เต็ม = คืน false "ถือไข่เต็มแล้ว" เหมือนกันทุกทาง
local function addEggToBag(player: Player, data: Data, eggId: string, weight: number): (boolean, string?)
	local egg = PlayerData.addHeldEgg(data.heldEggs, eggId, weight)
	if not egg then
		return false, "ถือไข่เต็มแล้ว"
	end

	EggService.sync(player)

	print(`[EggService] {player.Name} ได้ {egg.eggId} #{egg.id} น้ำหนัก {Config.formatWeight(egg.weight)}`)
	return true, nil
end

-- ⚠️ ห้ามให้ client เรียกถึงได้ และห้ามรับน้ำหนักมาจาก client
-- ใช้กับไข่รางวัลผ่านด่าน · ไข่เริ่มต้น · ไข่ตำนาน · คำสั่งเทสต์ (ไข่บอส 5B ใช้ grantBossEgg — น้ำหนักมาก่อนแล้ว)
function EggService.grantEgg(player: Player, eggId: string): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local rolledId, weight = rollEgg(eggId)
	if not rolledId or not weight then
		return false, `สร้างไข่ "{eggId}" ไม่ได้ (ไม่มีอยู่ หรือถูกปิดไปแล้ว)`
	end

	return addEggToBag(player, data, rolledId, weight)
end

-- 5B: ไข่บอสที่ผู้เล่นถือกลับถึงเซฟโซน — **น้ำหนักสุ่มไว้แล้วตอนบอสเกิด** (BossService · Config.rollMotherWeightForEgg ตัวเดิม)
-- ห้ามสุ่มใหม่ (ผู้เล่นเห็นขนาดไข่ตั้งแต่ไข่อยู่ในห้อง) · เข้ากระเป๋าทางเดียวกับ grantEgg
-- 5B-2: eggId = ไข่ของห้องที่หยิบมา (Config.getBossEggId(ห้อง) = egg_stageN) — ตัวนี้ไม่ต้องรู้ว่ามาจากห้องไหน
-- ⚠️ BossService เรียกเท่านั้น (inject ผ่าน Main.server.lua) · น้ำหนักมาจากสถานะของ server ไม่ใช่จาก client
function EggService.grantBossEgg(player: Player, eggId: string, weight: number): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end
	local eggType = Config.getEgg(eggId)
	if not eggType or not eggType.enabled then
		return false, `ไข่ "{eggId}" ไม่มีอยู่ หรือถูกปิดไปแล้ว`
	end
	if type(weight) ~= "number" or weight < 1 or weight % 1 ~= 0 then
		return false, "น้ำหนักไข่ต้องเป็นจำนวนเต็มบวก"
	end
	return addEggToBag(player, data, eggType.id, weight)
end

--------------------------------------------------------------------------------
-- ประกอบข้อมูลที่ส่งให้ client
--------------------------------------------------------------------------------

local function describeMother(mother: Mother, wallProgress: number)
	local character = Config.getCharacter(mother.charId)
	return {
		uid = mother.uid,
		charId = mother.charId,
		charName = if character then character.name else mother.charId,
		class = if character then character.class else "?",
		weight = mother.weight,
		weightText = Config.formatWeight(mother.weight),
		locked = mother.locked,
		-- UI-1: ค่าแสดงผลเท่านั้น (แผงเท้า/หน้ารายละเอียดแม่) — สูตรเดียวกับที่ ProductionService จ่ายจริง
		-- ⚠️ คิดที่ server เพราะรวมบัฟสถานะ (statuses ไม่ได้ส่งให้ client) · แม่ในกระเป๋าไม่ได้ผลิตจริง
		-- ค่านี้คือ "ถ้าเข้าคอกจะได้เท่าไหร่"
		coinsPerMinute = Config.getCoinsPerMinute(mother.weight, wallProgress, mother.statuses),
		-- UI-2: ราคาขายที่ร้านขายแม่ — สูตรเดียวกับที่ sellMother จ่ายจริง (client ห้ามคิดราคาเอง)
		sellPrice = Config.getMotherSellPrice(mother.weight, wallProgress, mother.statuses),
	}
end

-- กองลูก 1 กอง (stack key + จำนวน) ในรูปพร้อมโชว์
local function describeStack(key: string, count: number, damageLevel: number, robuxDamageBonus: number)
	local charId, weight, statuses = Config.parseStackKey(key)
	local character = if charId then Config.getCharacter(charId) else nil
	-- UI-3: พลังต่อตัว (พลังเต็ม) — สูตรเดียวกับที่ CombatService ใช้ตีจริง (รวมสถานะ + damageLevel
	-- + โบนัส Robux ที่ทะลุเพดาน — UI-5) · 5E-1: ดาเมจ/วิบนสนาม = พลังนี้ × อัตราปล่อย ÷ 6 · เลือด = พลังฐาน
	-- ⚠️ คิดที่ server (client ห้ามคิดเอง) · key เพี้ยน = nil (ไม่น่าเกิด — key มาจาก makeStackKey เท่านั้น)
	local power = if charId and weight
		then Config.computeBattlePower(Config.getChildWeight(weight, statuses), charId, statuses, damageLevel, robuxDamageBonus)
		else nil
	return {
		key = key,
		charId = charId,
		charName = if character then character.name else charId,
		class = if character then character.class else "?",
		weight = weight,
		weightText = if weight then Config.formatWeight(Config.getChildWeight(weight)) else "?",
		statuses = statuses,
		count = count,
		power = power,
	}
end

-- ⚠️ กระเป๋าไข่จุได้ถึง 10,000 ฟอง — **ห้ามส่งทั้งหมดทุกครั้งที่ sync**
-- sync วิ่งทุก SYNC_INTERVAL วินาที ส่งหมื่นฟองทุกวินาทีคือถล่มแบนด์วิดท์ของตัวเอง
-- ส่งเท่าที่ UI แสดงจริง + จำนวนรวม ที่เหลือรอจนกว่า UI จะทำ virtualize (Phase 5.5)
local HELD_EGGS_PER_SYNC = 50

local function buildSyncPayload(data: Data, bossLocked: boolean?, combatMeta: any?)
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
		table.insert(pen, describeMother(mother, data.wallProgress))
	end

	local bag = table.create(#data.mothersInBag)
	for _, mother in data.mothersInBag do
		table.insert(bag, describeMother(mother, data.wallProgress))
	end

	-- ⚠️ กองลูก — จำนวน stack key ยังเล็กมาก (สถานะยังไม่เปิดใช้จริง) ส่งทั้งหมดได้
	-- ต่างจากกระเป๋าไข่ (10,000 ฟอง) ที่ต้อง virtualize เพราะเป็นคนละขนาดกัน
	-- 5E-1: ลูกที่ยืนอยู่บนสนามยังนับอยู่ในกอง (หักตอนตาย) → โชว์เฉพาะที่ "พร้อมปล่อย" (หักตัวบนสนามออก)
	-- กองที่ทั้งกองอยู่บนสนามโชว์เป็น 0 ตัว (ยังติ๊กอยู่ตามลำดับเดิม)
	local reserved = CombatService.getReservedChildren(combatMeta)
	local children = {}
	for key, count in data.children do
		table.insert(children, describeStack(key, math.max(0, count - (reserved[key] or 0)), data.damageLevel, data.robuxDamageBonus))
	end

	local discoveredList: { string } = {}
	for charId, value in data.discovered do
		if value == true then
			table.insert(discoveredList, charId)
		end
	end
	table.sort(discoveredList)

	-- UI-3: กองที่ติ๊กไว้ใน releaseOrder แต่ตอนนี้หมด (ปล่อยออกไปหมดแล้ว) **และแม่ในคอกยังผลิตเติมอยู่**
	-- → หน้าต่างอัญเชิญโชว์เป็นการ์ด "0 ตัว · รอผลิต" ที่ยังติ๊กอยู่ตามลำดับเดิม ไม่หายไปเฉย ๆ
	-- (กองที่หมดและไม่มีแม่ผลิตเติมแล้ว — ขาย/ย้าย/ตาย — ไม่ส่ง · ติ๊กชุดใหม่แล้วหลุดจากลำดับเอง)
	local producing: { [string]: boolean } = {}
	for _, mother in data.mothersInPen do
		producing[Config.makeStackKey(mother.charId, mother.weight, mother.statuses)] = true
	end
	local waitingStacks = {}
	for _, key in data.releaseOrder do
		if producing[key] and not data.children[key] then
			table.insert(waitingStacks, describeStack(key, 0, data.damageLevel, data.robuxDamageBonus))
		end
	end

	-- ⚠️ Phase 3A: ฟิลด์การรบ (stageProgress/summonEnabled/releaseOrder/...) มาจาก
	-- CombatService.buildSyncFields() ล้วน ๆ ไม่คำนวณซ้ำที่นี่ — แค่ merge เข้า payload เดียวกัน
	-- ให้ 3B ใช้ต่อได้โดยไม่ต้องมี RemoteEvent แยก
	local combat = CombatService.buildSyncFields(data, bossLocked, combatMeta)

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
		-- ⚠️ UI-5: ตัวคูณ/ความเร็วที่แสดง = ค่าจริงที่ใช้รบ (ปกติ + โบนัส Robux รวมแล้ว) ไม่ใช่แค่ส่วนที่ซื้อด้วยเงินในเกม
		-- ป้าย UI-2 เดิมจึงเห็นค่าจริงถูกต้องโดยอัตโนมัติโดยไม่ต้องแก้โค้ดฝั่งนั้นเลย
		damageMultiplier = Config.getArmyDamageMultiplier(data.damageLevel) * Config.getRobuxDamageMultiplier(data.robuxDamageBonus),
		damageUpgradeCost = damageUpgradeCost, -- nil = เต็มเพดานของด่านนี้แล้ว
		speedLevel = data.speedLevel,
		maxSpeedLevel = Config.Balance.SpeedUpgrade.MAX_LEVEL,
		walkSpeed = Config.getEffectiveWalkSpeed(data.speedLevel, data.robuxSpeedBonus),
		speedUpgradeCost = Config.getSpeedUpgradeCost(data.speedLevel), -- nil = เต็มเพดานแล้ว
		-- UI-5: ร้าน Robux — จำนวนขั้นที่ซื้อไปแล้ว (ตัวคูณ/โบนัสจริงคำนวณรวมไว้ในสองฟิลด์ข้างบนแล้ว)
		robuxDamageBonus = data.robuxDamageBonus,
		robuxSpeedBonus = data.robuxSpeedBonus,
		robuxSpeedHardCap = Config.getRobuxSpeedHardCap(), -- client เช็คว่า "ซื้อต่อไปก็ไม่มีผลแล้ว"
		-- 5C: ขั้นกระบองปัจจุบัน (clamp แล้ว — ค่าเซฟแปลก ๆ ไม่หลุดถึง client) · ดาเมจ/ราคา/ชื่อ client อ่านจาก Config เอง
		clubTier = Config.clampClubTier(data.weaponLevel),
		clubMaxTier = Config.Balance.Weapon.MAX_LEVEL,
		children = children,
		waitingStacks = waitingStacks, -- UI-3: กองที่ติ๊กไว้แต่หมดชั่วคราว (count 0 · แม่ในคอกผลิตเติมอยู่)
		-- UI-4: ตัวละครที่เคยได้ (ดัชนี) — array ของ charId เรียงแล้ว (ข้อมูลเล็ก ≤ จำนวนตัวละคร)
		-- ⚠️ ส่งทั้งที่ไม่มีใน Config แล้วก็ได้ — client ข้ามเอง · "ตอนนี้มี N ตัว" client นับจากคอก+กระเป๋า+roster
		discovered = discoveredList,
		-- ⚠️ ข้อ D: จำนวนแม่ที่ฟักเสร็จแล้วแต่ยังค้างในสวนฟักเพราะคอก+กระเป๋าเต็มพร้อมกัน
		-- client ใช้ค่านี้โชว์ข้อความ "กระเป๋าแม่เต็ม ขายแม่บางตัวเพื่อรับแม่ที่ฟักเสร็จแล้ว" (ยังไม่ทำ UI เฟสนี้)
		stuckHatchCount = stuckHatchCount,
		activeStage = combat.activeStage,
		stageProgress = combat.stageProgress,
		summonEnabled = combat.summonEnabled,
		combatAutoPaused = combat.combatAutoPaused,
		releaseOrder = combat.releaseOrder,
		-- Phase 3C-1: แม่ในสนามรบ { uid, charId, charName, class, weight, weightText, statuses }
		-- (เพดาน = Config.Balance.Combat.MAX_BATTLE_MOTHERS)
		battleRoster = combat.battleRoster,
		sendStageBlockReason = combat.sendStageBlockReason, -- UI-3: nil = ส่งแม่ไปรบได้
		-- Phase 5A: ล็อกอัญเชิญเพราะบอส — nil = เปิดอัญเชิญได้ · หน้าต่างอัญเชิญปิดปุ่มส่ง + โชว์ข้อความนี้
		summonBlockReason = combat.summonBlockReason,
		bossLocked = combat.bossLocked,
	}
end

function EggService.sync(player: Player)
	local data = dataOf(player)
	if not data then
		return
	end
	farmStateSync:FireClient(player, buildSyncPayload(data, isBossLocked(player.UserId), CombatService.getMeta(player.UserId)))
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

	-- ⚠️ สร้างผ่านจุดกลาง PlayerData.createMother เท่านั้น (uid + บันทึกดัชนี · UI-4)
	-- น้ำหนัก = น้ำหนักเดิมของไข่เป๊ะ
	-- ⚠️ obtainedAt ใช้ slot.hatchAt ไม่ใช่ os.time() — เวลาที่ "ควรฟักเสร็จจริง" ไม่ใช่เวลาที่โค้ดมาเช็คเจอ
	-- ต่างกันได้ถึง 8 ชั่วโมงตอนผู้เล่นล็อกอินกลับมาแล้วเช็คไข่ที่ค้างจากตอนออฟไลน์
	-- (docs/data-schema.md §5.3) ถ้าใช้ os.time() แม่ตัวนี้จะไม่ได้เครดิตผลิตย้อนหลังเลย
	-- ทั้งที่ควรได้ตั้งแต่วินาทีที่ไข่ครบเวลาจริง ไม่ใช่วินาทีที่ผู้เล่นเข้าเกม
	--
	-- ⚠️ ข้อ D: ถ้าแม่ตัวนี้เพิ่งค้างมาก่อน (เต็มตอนฟักเสร็จรอบแรก) ก็ยังใช้ hatchAt เดิมนี้
	-- ไม่ใช่เวลาที่วางสำเร็จจริง — เพดานออฟไลน์ 8 ชม. ของ ProductionService ครอบไว้อยู่แล้ว
	-- จึงไม่มีทางได้เครดิตเกินจริงแม้จะค้างอยู่นานกว่านั้น
	local mother: Mother = PlayerData.createMother(data, player.UserId, charId, slot.weight, slot.hatchAt)

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

-- "สวมใส่ที่ดีที่สุด" (UI-1 · ผู้ใช้อนุมัติแล้ว) — คอกต้องจบด้วยแม่ N ตัวที่เก่งที่สุด (N = ความจุคอก)
-- จากแม่ทั้งหมดในคอก + กระเป๋า · ตัวอ่อนกว่าในคอกถูกสลับออกไปกระเป๋า ตัวเก่งกว่าในกระเป๋าเข้ามาแทน
-- (เดิมเติมแค่ช่องว่าง ไม่เคยเอาตัวในคอกออก)
-- เกณฑ์ "เก่ง" = รายได้เงิน/นาที Config.getCoinsPerMinute() สูตรเดียวกับที่จ่ายจริง (รวมบัฟสถานะ Phase 7)
-- ⚠️ เสมอกัน → ตัวที่อยู่ในคอกอยู่แล้วชนะ (ไม่สลับเปล่า ๆ) แล้วค่อยเรียงด้วย uid → กดซ้ำรอบสองไม่มีอะไรเปลี่ยน
-- ⚠️ แม่ที่ล็อกก็ถูกสลับได้ (ล็อกกันแค่ขาย/ส่งไปรบ ไม่กันย้ายคอก — Phase 4B) · แม่ใน battleRoster ไม่อยู่ในการพิจารณา
-- คืนรายชื่อ uid ที่ต้องย้าย: toPen (จากกระเป๋า เก่งสุดก่อน) · toBag (จากคอก อ่อนสุดก่อน)
function EggService.planEquipBest(data: Data): ({ string }, { string })
	local capacity = Config.getPenCapacity(data.penLevel)
	local entries: { { mother: Mother, inPen: boolean, coins: number } } = {}
	for _, mother in data.mothersInPen do
		table.insert(entries, {
			mother = mother,
			inPen = true,
			coins = Config.getCoinsPerMinute(mother.weight, data.wallProgress, mother.statuses),
		})
	end
	for _, mother in data.mothersInBag do
		table.insert(entries, {
			mother = mother,
			inPen = false,
			coins = Config.getCoinsPerMinute(mother.weight, data.wallProgress, mother.statuses),
		})
	end
	table.sort(entries, function(a, b)
		if a.coins ~= b.coins then
			return a.coins > b.coins
		end
		if a.inPen ~= b.inPen then
			return a.inPen
		end
		return a.mother.uid < b.mother.uid
	end)

	local toPen: { string } = {}
	local toBag: { string } = {}
	for rank, entry in entries do
		if rank <= capacity and not entry.inPen then
			table.insert(toPen, entry.mother.uid)
		end
	end
	for rank = #entries, capacity + 1, -1 do
		local entry = entries[rank]
		if entry.inPen then
			table.insert(toBag, entry.mother.uid)
		end
	end
	return toPen, toBag
end

function EggService.autoFillPen(player: Player): (boolean, string?, EquipBestSummary?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น", nil
	end
	if #data.mothersInPen + #data.mothersInBag == 0 then
		return false, "ไม่มีแม่ให้จัด", nil
	end

	local toPen, toBag = EggService.planEquipBest(data)
	local capacity = Config.getPenCapacity(data.penLevel)
	local now = os.time()
	local movedIn, movedOut = 0, 0

	for _, inUid in toPen do
		if #data.mothersInPen < capacity then
			-- ช่องว่างในคอก: ย้ายเข้าตรง ๆ (กระเป๋าลดลง ไม่มีทางล้น)
			local incoming = takeMother(data.mothersInBag, inUid)
			if not incoming then
				break
			end
			incoming.lastProducedAt = now
			table.insert(data.mothersInPen, incoming)
			movedIn += 1
		else
			-- คอกเต็ม: สลับทีละคู่ — ⚠️ ดึงตัวเก่งออกจากกระเป๋า**ก่อน** แล้วค่อยใส่ตัวอ่อนกลับ
			-- จำนวนแม่ในกระเป๋าจึงไม่เกินความจุแม้แต่จังหวะเดียว (กระเป๋าเต็มพอดีก็สลับได้)
			local outUid = toBag[movedOut + 1]
			if not outUid then
				break
			end
			local incoming = takeMother(data.mothersInBag, inUid)
			if not incoming then
				break
			end
			local outgoing = takeMother(data.mothersInPen, outUid)
			if not outgoing then
				table.insert(data.mothersInBag, incoming) -- คืนที่เดิม (เข้าไม่ถึงจริง — plan มาจากข้อมูลชุดเดียวกัน)
				break
			end
			-- ⚠️ settle ผลผลิตค้างก่อนออกจากคอกเสมอ (เหตุผลเดียวกับ moveMother)
			ProductionService.settleMother(data, outgoing, true)
			outgoing.lastProducedAt = nil
			incoming.lastProducedAt = now
			table.insert(data.mothersInPen, incoming)
			table.insert(data.mothersInBag, outgoing)
			movedIn += 1
			movedOut += 1
		end
	end

	-- ⚠️ เหตุผลเดียวกับ moveMother — ช่องว่างในกระเป๋าอาจเปิด ลองย้ายแม่ที่ค้างในสวนฟักมาเข้าทันที (ข้อ D)
	if movedIn > 0 then
		processReadyHatchSlots(player, data, now)
		PenService.refreshMothers(player, data.mothersInPen)
	end
	EggService.sync(player)

	print(`[EggService] {player.Name} สวมใส่ที่ดีที่สุด: เข้าคอก {movedIn} ตัว · ออกไปกระเป๋า {movedOut} ตัว`)
	return true, nil, { movedIn = movedIn, movedOut = movedOut }
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
--
-- ⚠️ แกนของการขาย 1 ตัว — ใช้ร่วมกันทั้งขายทีละตัว (sellMother) และขายเป็นชุด (sellMothersBatch)
-- **ไม่ sync และไม่ย้ายแม่ที่ค้างในสวนฟัก** — ผู้เรียกทำเองหลังขายเสร็จ (ชุดละครั้งเดียว)
-- คืน (ok, reason?, ราคาที่ได้?)
local function sellOneMother(player: Player, data: Data, rawUid: unknown): (boolean, string?, number?)
	if type(rawUid) ~= "string" then
		return false, "uid ไม่ใช่ string"
	end

	-- ⚠️ Phase 4B: ตรวจล็อก**ก่อน** takeMother — takeMother ถอดแม่ออกจากกระเป๋าทันทีที่เจอ
	for _, m in data.mothersInBag do
		if m.uid == rawUid and m.locked then
			return false, "แม่ตัวนี้ถูกล็อกไว้ ขายไม่ได้"
		end
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

	print(`[EggService] {player.Name} ขายแม่ {mother.uid} ({Config.formatWeight(mother.weight)}) ได้ {price} coins`)
	return true, nil, price
end

function EggService.sellMother(player: Player, rawUid: unknown): (boolean, string?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local ok, reason = sellOneMother(player, data, rawUid)
	if not ok then
		return false, reason
	end

	-- ⚠️ ขายแล้วเปิดที่ว่างในกระเป๋า ลองย้ายแม่ที่ค้างในสวนฟักมาเข้าทันที (ข้อ D)
	processReadyHatchSlots(player, data, os.time())

	EggService.sync(player)
	return true, nil
end

export type SellBatchSummary = {
	sold: number,
	skipped: number,
	coins: number,
}

-- อ่านรายการ uid ที่จะขาย · คืน (รายการ, nil) หรือ (nil, เหตุผลที่ปฏิเสธทั้งชุด)
-- ⚠️ ตรวจรูปร่างด้วย Config.parseUidList ตัวเดียวกับส่งแม่ไปรบเป็นชุด (UI-3) — ที่นี่แค่แปลงรหัสเป็นข้อความ
local function readSellUids(raw: unknown, limit: number): ({ string }?, string?)
	local list, listError = Config.parseUidList(raw, limit)
	if list then
		return list, nil
	end
	if listError == "not_string" then
		return nil, "uid ในรายการต้องเป็น string"
	elseif listError == "too_many" then
		return nil, `ขายได้ครั้งละไม่เกิน {limit} ตัว (ความจุกระเป๋า)`
	elseif listError == "empty" then
		return nil, "ยังไม่ได้เลือกแม่ที่จะขาย"
	end
	return nil, "รายการแม่ที่จะขายต้องเป็น array"
end

-- ขายแม่เป็นชุด (UI-2 · SellMothersBatchRequest) — ร้านขายแม่ยิงครั้งเดียวแทนทีละตัว
-- ⚠️ ตรวจรูปร่างทั้งชุดก่อน (readSellUids) ไม่ผ่าน = ปฏิเสธทั้งชุด ไม่ขายสักตัว
--   เพดาน = ความจุกระเป๋า — ขายได้เฉพาะแม่ในกระเป๋า ส่งมาเกินนั้นไม่ใช่คำขอจาก UI จริง
-- ⚠️ แต่ละตัวผ่าน sellOneMother ตัวเดียวกับขายทีละตัว (ราคา · ล็อก · เฉพาะกระเป๋า เหมือนเดิมทุกอย่าง)
--   ตัวที่ขายไม่ได้ (ล็อก / ไม่ใช่ของตัวเอง / อยู่ในคอก / uid ซ้ำในชุด) ข้าม แล้วขายตัวอื่นต่อ
-- sync + ย้ายแม่ที่ค้างในสวนฟักครั้งเดียวหลังจบชุด
-- คืน (ok, reason?, summary?) · summary = nil เฉพาะตอนปฏิเสธทั้งชุด
function EggService.sellMothersBatch(player: Player, rawUids: unknown): (boolean, string?, SellBatchSummary?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น", nil
	end

	local uids, rejectReason = readSellUids(rawUids, Config.Balance.Bag.CAPACITY)
	if not uids then
		return false, rejectReason, nil
	end

	local summary: SellBatchSummary = { sold = 0, skipped = 0, coins = 0 }
	local seen: { [string]: boolean } = {}
	for _, uid in uids do
		-- ⚠️ uid ซ้ำในชุด = ข้าม (ตัวแรกขายไปแล้ว ตัวที่สองต้องไม่ได้เงินซ้ำ)
		if seen[uid] then
			summary.skipped += 1
		else
			seen[uid] = true
			local ok, _, price = sellOneMother(player, data, uid)
			if ok then
				summary.sold += 1
				summary.coins += price or 0
			else
				summary.skipped += 1
			end
		end
	end

	if summary.sold > 0 then
		-- ⚠️ ขายแล้วเปิดที่ว่างในกระเป๋า ลองย้ายแม่ที่ค้างในสวนฟักมาเข้าทันที (ข้อ D)
		processReadyHatchSlots(player, data, os.time())
	end
	EggService.sync(player)

	print(
		`[EggService] {player.Name} ขายแม่เป็นชุด: ขาย {summary.sold} · ข้าม {summary.skipped} · ได้ {summary.coins} coins`
	)
	if summary.sold == 0 then
		return false, "ไม่มีแม่ตัวไหนขายได้", summary
	end
	return true, nil, summary
end

--------------------------------------------------------------------------------
-- ล็อกแม่ (Phase 4B) — กันขาย/ส่งไปรบพลาด ไม่กันการย้ายคอก↔กระเป๋า
--------------------------------------------------------------------------------

-- สลับ mother.locked ของแม่ในคอกหรือกระเป๋าของผู้เล่นเอง · คืน (ok, reason?, lockedใหม่?)
-- ⚠️ แม่ใน battleRoster ไม่อยู่ในสองอาเรย์นี้ → "ไม่พบ" (ส่งไปแล้วดึงกลับไม่ได้ ล็อกไปก็ไม่มีผลอะไร)
-- `locked` เป็นฟิลด์ของแม่ที่มีอยู่แล้วตั้งแต่ schema v1 — ย้ายคอก↔กระเป๋าย้ายทั้งตาราง ล็อกจึงติดไปด้วย
function EggService.toggleMotherLock(player: Player, rawUid: unknown): (boolean, string?, boolean?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น", nil
	end

	if type(rawUid) ~= "string" then
		return false, "uid ไม่ใช่ string", nil
	end

	local target: Mother? = nil
	for _, list in { data.mothersInPen, data.mothersInBag } do
		for _, mother in list do
			if mother.uid == rawUid then
				target = mother
				break
			end
		end
		if target then
			break
		end
	end
	if not target then
		return false, "ไม่พบแม่ตัวนี้ในคอกหรือกระเป๋า", nil
	end

	target.locked = not target.locked
	EggService.sync(player)
	return true, nil, target.locked
end

-- ส่งแม่จากกระเป๋าไปรบ (Phase 3C-1) — ตรรกะ/การตรวจทั้งหมดอยู่ที่ CombatService.handleSendMotherToBattle
-- ที่นี่แค่ต่อสายกับผู้เล่น · คืน (ok, message) ภาษาไทยพร้อมโชว์ทั้งสองกรณี
function EggService.sendMotherToBattle(player: Player, rawUid: unknown): (boolean, string)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end

	local ok, message = CombatService.handleSendMotherToBattle(data, rawUid, isBossLocked(player.UserId))
	if ok then
		-- ส่งไปรบแล้วกระเป๋าว่างขึ้นหนึ่งช่อง — รับแม่ที่ค้างในสวนฟักเข้ามาทันที (ข้อ D เหมือนตอนขาย)
		processReadyHatchSlots(player, data, os.time())
		EggService.sync(player)
		print(`[EggService] {player.Name} ส่งแม่ {rawUid} ไปรบ · roster {#data.battleRoster}`)
	end
	return ok, message
end

-- ส่งแม่ไปรบเป็นชุด (UI-3 · แท่นอัญเชิญ) — ตรรกะ/การตรวจทั้งหมดอยู่ที่ CombatService.handleSendMothersToBattleBatch
-- (ใช้แกนส่งทีละตัวตัวเดิม) · ที่นี่ต่อสายกับผู้เล่น + ย้ายแม่ที่ค้างในสวนฟัก + sync ครั้งเดียวท้ายชุด
function EggService.sendMothersToBattleBatch(
	player: Player,
	rawUids: unknown
): (boolean, string?, CombatService.SendBatchSummary?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น", nil
	end

	local ok, reason, summary = CombatService.handleSendMothersToBattleBatch(data, rawUids, isBossLocked(player.UserId))
	if not summary then
		return false, reason, nil -- ปฏิเสธทั้งชุด ไม่มีอะไรเปลี่ยน ไม่ต้อง sync
	end
	if summary.sent > 0 then
		-- ส่งไปรบแล้วกระเป๋าว่างขึ้น — รับแม่ที่ค้างในสวนฟักเข้ามาทันที (ข้อ D เหมือนตอนขาย)
		processReadyHatchSlots(player, data, os.time())
	end
	EggService.sync(player)
	print(
		`[EggService] {player.Name} ส่งแม่ไปรบเป็นชุด: ส่ง {summary.sent} · ข้าม {summary.skipped} · roster {summary.rosterCount}`
	)
	return ok, reason, summary
end

-- รางวัลผ่านด่าน (Phase 4A) — CombatService.tick ตัดสินแล้วว่าได้ (ติดธงไปแล้ว ให้ซ้ำไม่ได้)
-- ที่นี่แค่แจกไข่ของรังบอสด่านนั้นผ่าน grantEgg (สุ่มน้ำหนักแบบเดียวกับไข่ทุกแหล่ง) แล้วแจ้ง client
-- ⚠️ กระเป๋าไข่เต็มกลางทาง = แจกเท่าที่ใส่ได้ ธงติดไปแล้ว (ได้ครั้งเดียว) popup บอกจำนวนที่ได้จริง
-- Phase 4B: popup เดียวกันบอกจำนวนแม่ใน roster ที่ตายด้วย (`deathCount` — CombatService นับไว้ก่อนล้าง roster)
-- eggCount = 0 ได้ (ด่านพังซ้ำแต่มีแม่ตาย) → ไม่แจกอะไร แจ้งแค่แม่ตาย
function EggService.grantStageClearBonus(player: Player, stage: number, eggCount: number, deathCount: number)
	local eggId = Config.getBossEggId(stage)
	local granted = 0
	for _ = 1, eggCount do
		local ok, err = EggService.grantEgg(player, eggId)
		if not ok then
			warn(`[EggService] รางวัลผ่านด่าน {stage} ของ {player.Name}: แจกได้ {granted}/{eggCount} ฟอง ({err})`)
			break
		end
		granted += 1
	end

	stageClearedNotify:FireClient(player, stage, granted, deathCount)
	print(`[EggService] {player.Name} ผ่านด่าน {stage} · ได้ {eggId} ฟรี {granted}/{eggCount} ฟอง · แม่ในสนามตาย {deathCount} ตัว`)
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
		-- UI-5: รวมโบนัส Robux เข้ากับความเร็วปกติเสมอ (แทร็ก SpeedUpgrade เดิมไม่ถูกแก้เลย)
		humanoid.WalkSpeed = Config.getEffectiveWalkSpeed(data.speedLevel, data.robuxSpeedBonus)
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

-- 5C: ร้านกระบอง — ซื้อได้แค่ขั้นถัดไป (ไม่มีพารามิเตอร์จาก client) · ตรวจ/หักเงิน/เพิ่มขั้นในก้อนเดียว (PlayerData.buyNextClubTier)
-- ⚠️ ไม่แตะ data.weaponLevel นอกจากที่นี่ + debugSetWeaponTier + debugResetAll · BossService อ่านอย่างเดียว
--   (ประกอบกระบองในมือใหม่เองภายใน 1 tick เมื่อเห็นขั้นเปลี่ยน — ไม่ต้องเรียกข้ามโมดูล)
function EggService.buyClubTier(player: Player): (boolean, string?, number?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น", nil
	end
	local ok, reason, tier, price = PlayerData.buyNextClubTier(data)
	if not ok then
		return false, reason, nil
	end
	EggService.sync(player)
	print(`[EggService] {player.Name} ซื้อกระบองขั้น {tier}/{Config.Balance.Weapon.MAX_LEVEL} (จ่าย {price} coins)`)
	return true, nil, tier
end

--------------------------------------------------------------------------------
-- ร้าน Robux (UI-5)
--------------------------------------------------------------------------------

-- เร่งไข่ที่กำลังฟักอยู่ **ทุกฟอง** ให้ครบเวลาทันที — ใช้ตรรกะฟักเดิม (processReadyHatchSlots/hatch)
-- ทั้งหมด ไม่เขียนใหม่ (แม่ยังวางไม่ได้ถ้าคอก+กระเป๋าเต็มพร้อมกัน = ข้อ D เดิมเป๊ะ ไม่ใช่เคสพิเศษ)
-- ⚠️ คืน (true, nil, จำนวนที่เร่ง) เสมอตราบใดที่มีข้อมูลผู้เล่น แม้ rushed = 0 (ไม่มีไข่ให้เร่งตอนนั้นพอดี)
-- — **ไม่ใช่ความล้มเหลว** เพราะ Robux ถูกใช้ไปแล้ว การ retry ไปก็ไม่มีไข่งอกขึ้นมาเองให้เร่ง
function EggService.rushAllHatching(player: Player): (boolean, string?, number?)
	local data = dataOf(player)
	if not data then
		return false, "ยังไม่มีข้อมูลผู้เล่น", nil
	end

	local now = os.time()
	local rushed = PlayerData.rushAllHatchSlots(data, now)
	processReadyHatchSlots(player, data, now)
	EggService.sync(player)

	return true, nil, rushed
end

-- เพิ่มขั้นโบนัส damage จาก Robux — แยกจาก buyDamageUpgrade (เงินในเกม) โดยสิ้นเชิง ไม่แตะ damageLevel
function EggService.grantRobuxDamageBonus(player: Player, steps: number): boolean
	local data = dataOf(player)
	if not data then
		return false
	end
	PlayerData.addRobuxDamageSteps(data, steps)
	EggService.sync(player)
	return true
end

-- เพิ่มขั้นโบนัส speed จาก Robux — แยกจาก buySpeedUpgrade (เงินในเกม) โดยสิ้นเชิง ไม่แตะ speedLevel
function EggService.grantRobuxSpeedBonus(player: Player, steps: number): boolean
	local data = dataOf(player)
	if not data then
		return false
	end
	PlayerData.addRobuxSpeedSteps(data, steps)
	-- ⚠️ ต้องมีผลทันที เหมือน buySpeedUpgrade — ผู้เล่นกดซื้อแล้วคาดว่าจะวิ่งเร็วขึ้นเลย
	EggService.applyWalkSpeed(player)
	EggService.sync(player)
	return true
end

-- ⚠️ จุดเดียวที่ผูกกับ MarketplaceService.ProcessReceipt (Main.server.lua เป็นคนต่อสาย)
-- กฎเหล็ก (docs/data-schema.md §8.7):
--   1. idempotent ด้วย PurchaseId — Roblox เรียกซ้ำได้เสมอไม่ว่าจะสำเร็จแค่ไหน ต้องคืน
--      PurchaseGranted ทันทีถ้าเคยให้ของจากใบเสร็จนี้ไปแล้ว โดยไม่ให้ของซ้ำ
--   2. ให้ของก่อน แล้วค่อยเซฟ แล้วค่อยคืน PurchaseGranted — **ห้ามคืนก่อนเซฟสำเร็จ**
--      (เซฟไม่ผ่านแล้วเซิร์ฟดับ = ของที่เพิ่งให้หายไปจริง ทั้งที่ Roblox คิดว่าจบแล้วไม่ retry อีก)
--   3. ให้ของไม่สำเร็จไม่ว่าเหตุผลอะไร (ผู้เล่นออกไปแล้ว/ข้อมูลยังไม่โหลด/กระเป๋าเต็มจริง ๆ)
--      → คืน NotProcessedYet เสมอ ไม่ error ไม่ throw — Roblox จะเรียกซ้ำเอง (อาจข้ามเซิร์ฟเวอร์)
--
-- ⚠️ คืน **string ธรรมดา** ("PurchaseGranted" / "NotProcessedYet") ไม่ใช่ Enum.ProductPurchaseDecision
-- ตรง ๆ — กัน EggService.lua ต้องรู้จัก global `Enum` ของ Roblox (ไฟล์นี้จงใจแตะ Roblox API ให้น้อย
-- ที่สุด เหมือน CombatService ที่กันไว้ที่ .start() เท่านั้น — ทดสอบนอก Studio ได้มากขึ้น)
-- Main.server.lua เป็นคนแปลงเป็น Enum จริงตรงจุดที่ผูกกับ MarketplaceService.ProcessReceipt
function EggService.processReceipt(receiptInfo: { [string]: any }): string
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- ผู้เล่นออกจากเซิร์ฟไปแล้วระหว่างซื้อ (หรือกำลังจะเข้า) — Roblox จะ retry เองตอนเข้าเซิร์ฟถัดไป
		return "NotProcessedYet"
	end

	local data = dataOf(player)
	if not data then
		-- ข้อมูลยังโหลดไม่เสร็จ (เพิ่งเข้าเกม) — รอรอบถัดไป
		return "NotProcessedYet"
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if PlayerData.hasProcessedPurchase(data, purchaseId) then
		return "PurchaseGranted"
	end

	local productId = receiptInfo.ProductId
	local eggProduct = Config.findProductByRobloxId(productId)
	local robuxProduct = Config.findRobuxProductByRobloxId(productId)

	local granted = false
	local grantLabel = "?"

	if eggProduct then
		grantLabel = eggProduct.name
		granted = (EggService.grantEgg(player, eggProduct.grantEggId))
	elseif robuxProduct then
		grantLabel = robuxProduct.name
		if robuxProduct.kind == "damage_bonus" then
			granted = EggService.grantRobuxDamageBonus(player, robuxProduct.amount)
		elseif robuxProduct.kind == "speed_bonus" then
			granted = EggService.grantRobuxSpeedBonus(player, robuxProduct.amount)
		elseif robuxProduct.kind == "hatch_rush" then
			granted = (EggService.rushAllHatching(player))
		end
	else
		-- productId ไม่รู้จัก (ปิด enabled ไปแล้ว/ตั้งผิด) — ไม่คืน Granted เดี๋ยวของหาย เผื่อเป็นแค่ชั่วคราว
		warn(`[EggService] ProcessReceipt: ไม่รู้จัก productId {productId} (PurchaseId {purchaseId})`)
		return "NotProcessedYet"
	end

	if not granted then
		return "NotProcessedYet"
	end

	PlayerData.markPurchaseProcessed(data, purchaseId)

	-- ⚠️ ห้ามคืน PurchaseGranted ก่อนจุดนี้ — ดูกฎข้อ 2 ข้างบน
	local saved, saveErr = DataService.saveAsync(player.UserId, false)
	if not saved then
		warn(`[EggService] ProcessReceipt: ให้ "{grantLabel}" แล้วแต่เซฟไม่สำเร็จ ({saveErr}) — รอ retry`)
		return "NotProcessedYet"
	end

	print(`[EggService] {player.Name} ซื้อ "{grantLabel}" สำเร็จ (PurchaseId {purchaseId})`)
	return "PurchaseGranted"
end

--------------------------------------------------------------------------------
-- DEBUG เท่านั้น — ไม่มี UI เรียกผ่าน command bar ฝั่ง server
-- ⚠️ require จาก Command Bar ได้โมดูลอีกชุดที่ไม่มีข้อมูลผู้เล่น → เรียกผ่านสะพานใน Main.server.lua แทน:
--     game.ServerStorage.EggServiceDebug:Invoke("debugResetAll", game.Players:GetPlayers()[1])
-- รายชื่อด้านล่างเขียนแบบเรียกตรงเพื่อให้อ่านง่าย (docs/debug-commands.md)
--     local EggService = require(game.ServerScriptService.EggService)
--     EggService.debugFillHatchery(game.Players.<ชื่อ>)
--     EggService.debugClearBag(game.Players.<ชื่อ>)
--     EggService.debugResetAll(game.Players.<ชื่อ>)
--     EggService.debugGrantMother(game.Players.<ชื่อ>, 1500, "wukong", "pen")
--     EggService.debugGrantEggWithWeight(game.Players.<ชื่อ>, "egg_stage5", 100000000)
--     EggService.debugSetWallProgress(game.Players.<ชื่อ>, 7)
--     EggService.debugSetCurrency(game.Players.<ชื่อ>, 1000000)
--     EggService.debugSetWeaponTier(game.Players.<ชื่อ>, 5)   -- 5C: ตั้งขั้นกระบอง 1–10 (ไม่หักเงิน)
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
	table.clear(data.battleRoster) -- แม่ในสนามรบก็เป็นแม่ รีเซ็ตทั้งหมด = ล้างด้วย
	table.clear(data.heldEggs.items)
	table.clear(data.discovered) -- ดัชนี (UI-4) — รีเซ็ตแล้วทดสอบ "ได้ตัวใหม่ครั้งแรก" ซ้ำได้

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
		-- ธงรางวัลผ่านด่าน (Phase 4A) กลับเป็น false ด้วย — ไม่งั้นรีเซ็ตแล้วตีใหม่จะไม่ได้ไข่ ทดสอบซ้ำไม่ได้
		data.stageClearBonusGranted[stage] = false
	end
	data.wallProgress = Config.Balance.NewPlayer.wallProgress
	-- 5C: กระบองกลับเป็นขั้นเริ่มต้น (ขั้น 1 ฟรี) — ทดสอบร้านกระบองซ้ำได้ · กระบองในมือเปลี่ยนเองใน 1 tick (BossService)
	local weaponBefore = data.weaponLevel
	data.weaponLevel = Config.Balance.Weapon.START_TIER

	-- ⚠️ แม่ในคอกก็มีโมเดลเดินอยู่จริง ต้อง refreshMothers ให้คอกว่างตามข้อมูล
	PenService.refreshMothers(player, data.mothersInPen)
	EggService.sync(player)

	print(
		`[EggService] debugResetAll: {player.Name} ล้างแม่ในคอก {motherPenRemoved} ตัว · `
			.. `แม่ในกระเป๋า {motherBagRemoved} ตัว · ไข่ในกระเป๋า {eggsRemoved} ฟอง · `
			.. `ไข่ที่กำลังฟัก {hatchingRemoved} ฟอง · `
			.. `stageProgress ที่ล้าง {stageProgressCleared}/{Config.Balance.Stage.COUNT} ด่าน · `
			.. `wallProgress {wallProgressBefore} → {data.wallProgress} · `
			.. `กระบอง {weaponBefore} → {data.weaponLevel} · `
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

	-- ⚠️ ผ่านจุดกลางเดียวกับฟักไข่ (uid + บันทึกดัชนี · UI-4)
	local mother: Mother = PlayerData.createMother(data, player.UserId, resolvedCharId, flooredWeight, os.time())

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

-- ให้แม่**ครบทุกตัวละคร** (ตามลำดับดัชนี Config.CharacterOrder · ตัวละครละ 1 ตัว) เข้ากระเป๋า — ไว้ดูโมเดลในการ์ด/ดัชนี/คอก
-- (รอบโมเดลตัวละคร) · weight ไม่ใส่ = 100 kg (tier 1) · กระเป๋าว่างไม่พอทั้งชุด = ปฏิเสธทั้งชุด (ไม่แจกครึ่ง ๆ)
-- ⚠️ ผ่านจุดกลาง PlayerData.createMother ทุกตัว (uid + ดัชนี · tools/check-mother-creation.py ตรวจ)
function EggService.debugGrantAllCharacters(player: Player, weight: number?): (boolean, string?)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugGrantAllCharacters: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return false, "ยังไม่มีข้อมูลผู้เล่น"
	end
	-- ⚠️ น้ำหนักแม่ต้องเป็นจำนวนเต็มเสมอ (ส่วนหนึ่งของ stack key) — เหมือน debugGrantMother
	local flooredWeight = math.floor(weight or 100)
	if flooredWeight <= 0 then
		warn(`[EggService] debugGrantAllCharacters: น้ำหนักต้องมากกว่า 0`)
		return false, "น้ำหนักต้องมากกว่า 0"
	end

	local charIds: { string } = {}
	for _, charId in Config.CharacterOrder do
		local character = Config.getCharacter(charId)
		if character and character.enabled then
			table.insert(charIds, charId)
		end
	end
	-- เช็คที่ว่างก่อนสร้างแม่จริง กันเปลือง uid (เดินหน้าอย่างเดียว ห้าม reuse)
	local free = Config.Balance.Bag.CAPACITY - #data.mothersInBag
	if free < #charIds then
		warn(`[EggService] debugGrantAllCharacters: {player.Name} กระเป๋าว่าง {free} ช่อง ต้องการ {#charIds}`)
		return false, `กระเป๋าว่าง {free} ช่อง ต้องการ {#charIds}`
	end

	local now = os.time()
	for _, charId in charIds do
		table.insert(data.mothersInBag, PlayerData.createMother(data, player.UserId, charId, flooredWeight, now))
	end

	EggService.sync(player)

	print(
		`[EggService] debugGrantAllCharacters: {player.Name} ได้แม่ครบ {#charIds} ตัวละคร `
			.. `{Config.formatWeight(flooredWeight)} → กระเป๋า · `
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

-- ตั้งค่า wallProgress ที่เก็บฝั่ง server ตรง ๆ — ⚠️ ตั้งแล้ว**ไม่แตะ** data.stageProgress เลย
-- (client ได้รับ wallProgress ผ่าน sync จริงตั้งแต่มีปุ่มซื้อ damage/speed upgrade แล้ว แต่
-- WallRenderer วาดกำแพงจาก stageProgress เท่านั้น ไม่ได้อ่านค่านี้) ใช้ทดสอบสูตรเงิน
-- (Config.getCoinsPerMinute) และเพดาน damage upgrade ที่ผูกกับ wallProgress โดยไม่ต้องตีด่านจริง
-- ⚠️ ตั้งค่าตรงนี้แล้วปล่อยไว้ = stageProgress กับ wallProgress เพี้ยนไปจากกันชั่วคราว
-- (recomputeWallProgress ไม่เรียกจากตรงนี้ เพราะไม่รู้ว่า stageProgress ควรเป็นค่าไหน) จะกลับมา
-- ตรงกันเองก็ต่อเมื่อตีด่านใหม่จริงจนแซงค่าที่ตั้งไว้ (docs/data-schema.md — ดู debugResetAll
-- ถ้าต้องการล้างทั้งคู่กลับเป็นค่าเริ่มต้น หรือ debugSetStageProgress ถ้าอยากตั้ง stageProgress
-- ตรง ๆ แทนแล้วให้ wallProgress sync ตามจริง)
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

-- ตั้งค่า defendersRemaining/wallHpRemaining ของด่านหนึ่งตรง ๆ ข้ามการตีจริงทั้งหมด — ใช้ทดสอบ
-- ภาพกำแพงแตก 5 ระดับ + เลขความเสียหายลอย (3B-2) โดยไม่ต้องตีทหารฝ่ายรับนับพันล้าน HP จริงในด่านสูง
-- ⚠️ ไม่ validate ค่าเกินจริงของ HP เต็มด่านนั้นเลย (เป็นเครื่องมือ Studio-only เหมือน
-- debugSetWallProgress — อยากตั้งเกิน HP จริงเพื่อดูว่าอะไรพังก็ทำได้) clamp แค่ไม่ให้ติดลบ
-- และ clamp `stage` ให้อยู่ในช่วง 1..Config.Balance.Stage.COUNT เท่านั้น (ดัชนีนอกช่วงนี้จะ
-- เขียนทับ array ยาวคงที่ 9 ช่องของ stageProgress ให้เพี้ยนไปจากโครงที่ PlayerData คาดไว้)
--
-- ⚠️ ถ้าตั้งเป็น "พังทั้งด่าน" (defendersRemaining=0 และ wallHpRemaining=0) จะเรียก
-- CombatService.recomputeWallProgress(data) ต่อท้ายทันที — เหตุผลเดียวกับที่ CombatService.tick()
-- เรียกตัวนี้เองตอนตีพังจริง (docs/data-schema.md §7) ไม่งั้นเครื่องมือนี้จะสร้างสภาพที่
-- stageProgress บอกว่าพังแล้วแต่ wallProgress (เงิน + เพดาน damage upgrade) ไม่ขยับตาม
function EggService.debugSetStageProgress(
	player: Player,
	stage: number,
	defendersRemaining: number,
	wallHpRemaining: number
)
	local data = dataOf(player)
	if not data then
		warn(`[EggService] debugSetStageProgress: {player.Name} ยังไม่มีข้อมูลผู้เล่น`)
		return
	end

	local clampedStage = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	local clampedDefenders = math.max(0, math.floor(defendersRemaining))
	local clampedWallHp = math.max(0, math.floor(wallHpRemaining))

	data.stageProgress[clampedStage] = {
		defendersRemaining = clampedDefenders,
		wallHpRemaining = clampedWallHp,
	}

	local wallProgressBefore = data.wallProgress
	if clampedDefenders <= 0 and clampedWallHp <= 0 then
		CombatService.recomputeWallProgress(data)
	end

	EggService.sync(player)

	print(
		`[EggService] debugSetStageProgress: {player.Name} ด่าน {clampedStage}`
			.. `{if clampedStage ~= stage then ` (clamp จาก {stage})` else ""} → `
			.. `defendersRemaining={clampedDefenders} wallHpRemaining={clampedWallHp} · `
			.. `wallProgress {wallProgressBefore} → {data.wallProgress} · `
			.. debugSaveNow(player)
	)
end

-- 5E-1: สนามรบทั้ง 12 ช่อง (เรา 6 · ศัตรู 6) + เลือด + คิวที่เหลือ — พิมพ์ลง Output และคืนข้อความเดียวกัน
function EggService.debugBattleStatus(player: Player): string
	local data = dataOf(player)
	if not data then
		local message = `[EggService] debugBattleStatus: {player.Name} ยังไม่มีข้อมูลผู้เล่น`
		warn(message)
		return message
	end
	local text = CombatService.describeBattle(data, CombatService.getMeta(player.UserId))
	print(`[EggService] debugBattleStatus: {player.Name}\n{text}`)
	return text
end

-- 5E-1: เปิด/ปิดป้อมบนกำแพง **ทั้งเซิร์ฟ** (ไม่เซฟ · เซิร์ฟใหม่ = เปิดเสมอ) — ทดสอบว่าเวลาตี/การตายเปลี่ยนตามป้อมจริง
-- ⚠️ ป้อมไม่ใช่ของผู้เล่นรายคน — รับได้ทั้ง debugTurret(false) และแบบสะพานปกติ debugTurret(player, false)
-- ค่าที่ไม่ใช่ boolean = ปฏิเสธ
function EggService.debugTurret(first: any, second: any?): string
	local enabled = if type(first) == "boolean" then first else second
	if type(enabled) ~= "boolean" then
		return "debugTurret: ต้องส่ง true (เปิด) หรือ false (ปิด)"
	end
	CombatService.setTurretEnabled(enabled)
	local message = `[EggService] debugTurret: ป้อมบนกำแพง{if enabled then "เปิด" else "ปิด"}แล้ว (ทั้งเซิร์ฟ · ไม่เซฟ)`
	print(message)
	return message
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

-- 5C: ตั้งขั้นกระบองตรง ๆ (ไม่หักเงิน) — ทดสอบดาเมจ/หน้าตากระบองแต่ละขั้น · รับ 1..MAX_LEVEL จำนวนเต็มเท่านั้น
-- คืนข้อความผลลัพธ์ (ค่าแปลก = ปฏิเสธ ไม่แตะข้อมูล) · กระบองในมือเปลี่ยนเองใน 1 tick (BossService เทียบขั้นทุก tick)
function EggService.debugSetWeaponTier(player: Player, rawTier: any): string
	local data = dataOf(player)
	if not data then
		return `debugSetWeaponTier: {player.Name} ยังไม่มีข้อมูลผู้เล่น`
	end
	local maxTier = Config.Balance.Weapon.MAX_LEVEL
	if type(rawTier) ~= "number" or rawTier % 1 ~= 0 or rawTier < 1 or rawTier > maxTier then
		local message = `debugSetWeaponTier: ขั้นต้องเป็นจำนวนเต็ม 1–{maxTier} (ได้ {tostring(rawTier)}) — ไม่แตะข้อมูล`
		warn(`[EggService] {message}`)
		return message
	end
	local before = data.weaponLevel
	data.weaponLevel = rawTier
	EggService.sync(player)
	local message = `debugSetWeaponTier: {player.Name} กระบอง {before} → {rawTier} `
		.. `({Config.getClubVisual(rawTier).name} · ดาเมจ {Config.getClubDamage(rawTier)}/ครั้ง) · `
		.. debugSaveNow(player)
	print(`[EggService] {message}`)
	return message
end

-- ⚠️ UI-5: จำลอง MarketplaceService.ProcessReceipt โดยไม่ต้องมี Robux จริง/publish จริง
-- ใช้ทดสอบ idempotency ตรง ๆ: เรียกซ้ำด้วย purchaseId เดิม → ครั้งที่สองต้องไม่ให้ของซ้ำ (docs/data-schema.md §8.7)
-- productKey = "legendary_egg" | "robux_damage_step" | "robux_speed_step" | "robux_hatch_rush"
-- คืน string ของ Enum.ProductPurchaseDecision ที่ processReceipt ตัดสินใจจริง (เรียกฟังก์ชันเดียวกับที่
-- MarketplaceService.ProcessReceipt ผูกไว้เป๊ะ ไม่ใช่โค้ดทดสอบแยกชุด)
function EggService.debugSimulateReceipt(player: Player, productKey: string, purchaseId: string): string
	local product = Config.getDeveloperProduct(productKey) or Config.getRobuxProduct(productKey)
	if not product then
		return `ไม่รู้จัก product "{productKey}"`
	end

	local decision = EggService.processReceipt({
		PlayerId = player.UserId,
		ProductId = product.productId,
		PurchaseId = purchaseId,
	})
	return tostring(decision)
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
	sellMothersBatchRequest = Remotes.waitFor(Config.RemoteNames.SELL_MOTHERS_BATCH_REQUEST)
	sendMotherToBattleRequest = Remotes.waitFor(Config.RemoteNames.SEND_MOTHER_TO_BATTLE_REQUEST)
	sendMothersToBattleBatchRequest = Remotes.waitFor(Config.RemoteNames.SEND_MOTHERS_TO_BATTLE_BATCH_REQUEST)
	autoFillPenRequest = Remotes.waitFor(Config.RemoteNames.AUTO_FILL_PEN_REQUEST)
	buyDamageUpgradeRequest = Remotes.waitFor(Config.RemoteNames.BUY_DAMAGE_UPGRADE_REQUEST)
	buySpeedUpgradeRequest = Remotes.waitFor(Config.RemoteNames.BUY_SPEED_UPGRADE_REQUEST)
	buyClubTierRequest = Remotes.waitFor(Config.RemoteNames.BUY_CLUB_TIER_REQUEST)
	eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
	farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)
	actionResult = Remotes.waitFor(Config.RemoteNames.ACTION_RESULT)
	stageClearedNotify = Remotes.waitFor(Config.RemoteNames.STAGE_CLEARED_NOTIFY)
	toggleMotherLockRequest = Remotes.waitFor(Config.RemoteNames.TOGGLE_MOTHER_LOCK_REQUEST)

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

	-- UI-2: ร้านขายแม่ขายเป็นชุด — ข้อความสรุปครั้งเดียวต่อชุด (ไม่ใช่ทีละตัว)
	sellMothersBatchRequest.OnServerEvent:Connect(function(player, rawUids)
		local ok, reason, summary = EggService.sellMothersBatch(player, rawUids)
		if summary then
			reportResult(player, ok, Config.formatSellBatchMessage(summary.sold, summary.coins, summary.skipped))
		else
			print(`[EggService] ปฏิเสธคำขอขายแม่เป็นชุดของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "ขายแม่ไม่สำเร็จ")
		end
	end)

	toggleMotherLockRequest.OnServerEvent:Connect(function(player, rawUid)
		local ok, reason, locked = EggService.toggleMotherLock(player, rawUid)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอล็อกแม่ของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "ล็อกแม่ไม่สำเร็จ")
		elseif locked then
			reportResult(player, true, "🔒 ล็อกแม่แล้ว — ขาย/ส่งไปรบไม่ได้จนกว่าจะปลดล็อก")
		else
			reportResult(player, true, "🔓 ปลดล็อกแม่แล้ว")
		end
	end)

	sendMotherToBattleRequest.OnServerEvent:Connect(function(player, rawUid)
		local ok, message = EggService.sendMotherToBattle(player, rawUid)
		if not ok then
			print(`[EggService] ปฏิเสธคำขอส่งแม่ไปรบของ {player.Name}: {message}`)
		end
		reportResult(player, ok, message)
	end)

	-- UI-3: แท่นอัญเชิญส่งแม่เป็นชุด — ข้อความสรุปครั้งเดียวต่อชุด (ไม่ใช่ทีละตัว)
	sendMothersToBattleBatchRequest.OnServerEvent:Connect(function(player, rawUids)
		local ok, reason, summary = EggService.sendMothersToBattleBatch(player, rawUids)
		if summary then
			reportResult(player, ok, Config.formatSendBatchMessage(summary.sent, summary.rosterCount, summary.skipped))
		else
			print(`[EggService] ปฏิเสธคำขอส่งแม่ไปรบเป็นชุดของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "ส่งแม่ไปรบไม่สำเร็จ")
		end
	end)

	autoFillPenRequest.OnServerEvent:Connect(function(player)
		local ok, reason, summary = EggService.autoFillPen(player)
		if not ok or not summary then
			print(`[EggService] สวมใส่ที่ดีที่สุดของ {player.Name} ไม่ทำอะไร: {reason}`)
			reportResult(player, false, reason or "สวมใส่ที่ดีที่สุดไม่สำเร็จ")
		elseif summary.movedIn == 0 then
			reportResult(player, true, "คอกมีแม่ที่ดีที่สุดครบแล้ว ไม่มีอะไรเปลี่ยน")
		elseif summary.movedOut == 0 then
			reportResult(player, true, `สวมใส่ที่ดีที่สุดแล้ว: เข้าคอก +{summary.movedIn} ตัว`)
		else
			reportResult(
				player,
				true,
				`สวมใส่ที่ดีที่สุดแล้ว: สลับเข้า {summary.movedIn} ตัว · ออกไปกระเป๋า {summary.movedOut} ตัว`
			)
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

	-- 5C: ร้านกระบอง — ไม่รับพารามิเตอร์ใด ๆ จาก client (ค่าที่ส่งมาถูกทิ้ง) · ซื้อได้แค่ขั้นถัดไป
	buyClubTierRequest.OnServerEvent:Connect(function(player)
		local ok, reason, tier = EggService.buyClubTier(player)
		if not ok or tier == nil then
			print(`[EggService] ปฏิเสธคำขอซื้อกระบองของ {player.Name}: {reason}`)
			reportResult(player, false, reason or "ซื้อกระบองไม่สำเร็จ")
		else
			reportResult(player, true, Config.formatClubBoughtMessage(tier))
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
