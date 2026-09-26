--!strict
-- egg-army-game :: โครงข้อมูลผู้เล่นและกฎการเซฟ (ตรรกะล้วน ไม่แตะ DataStore)
--
-- ⚠️ ทำไมแยกจาก DataService: ไฟล์นี้ **ไม่เรียก service ของ Roblox เลยสักตัว**
-- จึง require เข้าชุดเทสต์ที่รันด้วย luau CLI ได้ตรง ๆ
-- ตรรกะที่พังแล้วผู้เล่นเสียของ (template · migration · กฎ encode · โครง heldEggs)
-- จึงทดสอบได้โดยไม่ต้องเปิด Studio — ส่วน DataService ที่เหลือมีแค่การคุยกับ DataStore
--
-- ⚠️ กฎเหล็กของไฟล์นี้: ทุกอย่างที่ออกจากที่นี่ต้อง **encode ลง JSON ได้**
-- Roblox เซฟ DataStore ด้วย JSON กฎที่ห้ามผิดอยู่ใน docs/data-schema.md §9.3
-- `sanitizeForSave()` บังคับกฎพวกนั้นทุกครั้งก่อนเขียนจริง

local Config = (if script then require(script.Parent.Config) else require("./Config")) :: any

local PlayerData = {}

local DS = Config.DataStore
local HATCHERY = Config.Balance.Hatchery

--------------------------------------------------------------------------------
-- ชนิดข้อมูล
--------------------------------------------------------------------------------

-- ไข่ 1 ฟองในกระเป๋า — **มี id ประจำฟอง ไม่ใช่ตำแหน่งในอาเรย์**
export type HeldEgg = {
	id: number, -- ไม่ซ้ำภายในผู้เล่นคนนี้ ห้าม reuse
	eggId: string,
	weight: number, -- น้ำหนักแม่ที่จะได้ตอนฟัก (จำนวนเต็ม) ล็อกตั้งแต่ตอนสร้างไข่
}

-- ⚠️ โครงหลัก: เก็บ **เฉพาะฟองที่มีจริง** ไม่ใช่อาเรย์ยาวคงที่ที่เติม false
--
-- โครงเดิมยาวเท่า BAG_CAPACITY เสมอ พอเพดานขึ้นเป็น 10,000 แปลว่าต้องเขียน
-- `false` หมื่นตัวลง DataStore ทุกครั้งที่เซฟ ต่อให้ผู้เล่นถือไข่จริงแค่ 3 ฟอง
export type HeldEggs = {
	nextEggId: number, -- ตัวนับ **ห้ามลด ห้าม reuse** (เหตุผลเดียวกับ nextUid)
	items: { HeldEgg }, -- array แน่น ไม่มีรู ไม่มี false
}

export type HatchSlot = {
	eggId: string,
	weight: number,
	-- ตัวละครที่จะฟักออกมา — สุ่มไว้ตั้งแต่ตอนวางไข่ลงสวนฟัก (ไม่ใช่ตอนฟักเสร็จ) เพราะเวลาฟัก
	-- ต้องใช้คลาสมาคำนวณ (Config.getHatchSeconds) ผู้เล่นยังไม่เห็นค่านี้จนกว่าจะฟักเสร็จจริง
	-- (ห้ามส่งฟิลด์นี้เข้า sync payload ที่ client เห็น)
	--
	-- ⚠️ optional เพื่อรองรับช่องที่ค้างฟักอยู่จากก่อนเพิ่มฟิลด์นี้ (ไข่ที่วางไปแล้วตอน deploy
	-- รุ่นเก่า) — EggService.hatch() มี fallback สุ่มให้ตอนนั้นถ้าไม่มีค่านี้ติดมา
	charId: string?,
	startedAt: number,
	hatchAt: number,
}

export type Mother = {
	uid: string,
	charId: string,
	weight: number,
	statuses: { string },
	lastProducedAt: number?, -- มีเฉพาะแม่ในคอก
	obtainedAt: number,
	locked: boolean,
}

export type StageProgress = {
	defendersRemaining: number,
	wallHpRemaining: number,
}

export type SessionLock = {
	jobId: string,
	placeId: number,
	at: number, -- os.time() ตอนตั้ง/ต่ออายุ
}

export type Data = {
	schemaVersion: number,
	currency: { coins: number, gems: number },
	mothersInPen: { Mother },
	mothersInBag: { Mother },
	-- ⚠️ ที่อยู่แห่งที่สามของแม่ (Phase 3C-1 · schema v2) — แม่ที่ส่งไปรบแล้ว
	-- แม่หนึ่งตัวอยู่ได้ที่เดียวเสมอ (คอก / กระเป๋า / roster) ส่งไปรบ = ย้ายออกจากกระเป๋ามาไว้นี่
	-- ย้อนกลับไม่ได้ · ตายหมดพร้อมกันตอนด่านที่กำลังตีพัง (CombatService) · uid ไม่ถูก reuse
	battleRoster: { Mother },
	nextUid: number,
	children: { [string]: number },
	penLevel: number,
	productionLevel: number,
	damageLevel: number,
	weaponLevel: number,
	speedLevel: number,
	wallProgress: number,
	hatching: { HatchSlot | false },
	heldEggs: HeldEggs,
	stageProgress: { StageProgress | false },
	summonEnabled: boolean,
	-- ⚠️ true เฉพาะตอนที่ auto-pause (§7.6) เป็นคนปิด summonEnabled ให้เอง
	-- ผู้เล่นกดปิดเองไม่ตั้งค่านี้ — ใช้แยกว่าจะโชว์แจ้งเตือน "ตีไม่เข้า" หรือเปล่า (3B)
	combatAutoPaused: boolean,
	-- ⚠️ อาเรย์ของ stack key (Config.makeStackKey()) เรียงลำดับที่ผู้เล่นตั้งไว้เอง
	-- หัวอาเรย์ = ปล่อยก่อน · กองที่หมด (count เป็น 0/ไม่มีใน children) ยังค้างอยู่ในนี้
	-- ไม่ถูกลบ (เผื่อผลิตเพิ่มมาเติมทีหลัง) · กองใหม่ที่ยังไม่เคยอยู่ในนี้ถูกต่อท้ายอัตโนมัติ
	-- (CombatService.reconcileReleaseOrder) ห้ามเขียนตรง ๆ ที่อื่นนอกจาก CombatService
	releaseOrder: { string },
	stats: { [string]: any },
	sessionLock: SessionLock?,
	lastSaveAt: number,
}

--------------------------------------------------------------------------------
-- ผู้เล่นใหม่
--------------------------------------------------------------------------------

-- ⚠️ ไม่แจกไข่เริ่มต้นที่นี่ — ไข่ต้องสุ่มน้ำหนักซึ่งต้องใช้ rng ฝั่ง server
-- EggService เป็นคนแจกหลังโหลดเสร็จ และ **แจกเฉพาะตอนที่เป็นผู้เล่นใหม่จริง**
-- (ถ้าแจกทุกครั้งที่เข้าเกม = ไข่ฟรีทุกล็อกอิน)
function PlayerData.createNew(): Data
	local newPlayer = Config.Balance.NewPlayer

	-- ⚠️ อาเรย์ยาวคงที่ ช่องว่างใช้ false ห้ามใช้ nil
	-- nil กลางอาเรย์ทำให้ความยาวเพี้ยนและ encode ออกมาเป็นของคนละรูป (data-schema §9.3)
	local hatching: { HatchSlot | false } = {}
	for index = 1, HATCHERY.MAX_SLOTS do
		hatching[index] = false
	end

	local stageProgress: { StageProgress | false } = {}
	for index = 1, Config.Balance.Stage.COUNT do
		stageProgress[index] = false
	end

	return {
		schemaVersion = Config.SCHEMA_VERSION,

		currency = { coins = newPlayer.coins, gems = newPlayer.gems },

		mothersInPen = {},
		mothersInBag = {},
		battleRoster = {},
		nextUid = 1,
		children = {},

		penLevel = 1,
		productionLevel = 0,
		damageLevel = 0,
		weaponLevel = 1,

		-- ⚠️ อ่านจาก Config ไม่ใช่เขียน 0 ลงไปตรง ๆ
		-- `wallProgress` เริ่มที่ **1** ไม่ใช่ 0 — ถ้าเป็น 0 เพดาน upgrade damage
		-- (wallProgress × STEPS_PER_STAGE) จะกลายเป็น 0 แล้วผู้เล่นใหม่ซื้ออะไรไม่ได้เลย
		speedLevel = newPlayer.speedLevel,
		wallProgress = newPlayer.wallProgress,

		hatching = hatching,
		heldEggs = { nextEggId = 1, items = {} },
		stageProgress = stageProgress,
		summonEnabled = Config.Balance.Combat.SUMMON_DEFAULT_ON,
		combatAutoPaused = false,
		releaseOrder = {},

		stats = {
			eggsHatched = 0,
			eggsGrabbed = 0,
			bossKilled = 0,
			coinsFromKills = 0,
			coinsFromBoss = 0,
			childrenProduced = 0,
			mothersLost = 0,
			childrenLost = 0,
			heaviestMother = 0,
			totalCoinsEarned = 0,
			firstJoinAt = os.time(),
			lastSeenAt = os.time(),
			playTimeSeconds = 0,
		},

		lastSaveAt = os.time(),
	}
end

--------------------------------------------------------------------------------
-- กระเป๋าไข่ — ทุกการแก้ต้องผ่านสามฟังก์ชันนี้
--------------------------------------------------------------------------------

-- ⚠️ ห้ามแตะ `items` ตรง ๆ ที่อื่น เพราะ id ต้องเดินหน้าอย่างเดียว
-- คืน nil เมื่อกระเป๋าเต็ม
function PlayerData.addHeldEgg(heldEggs: HeldEggs, eggId: string, weight: number): HeldEgg?
	if #heldEggs.items >= HATCHERY.BAG_CAPACITY then
		return nil
	end

	local egg: HeldEgg = { id = heldEggs.nextEggId, eggId = eggId, weight = weight }
	heldEggs.nextEggId += 1
	table.insert(heldEggs.items, egg)
	return egg
end

function PlayerData.findHeldEgg(heldEggs: HeldEggs, id: number): (number?, HeldEgg?)
	for index, egg in heldEggs.items do
		if egg.id == id then
			return index, egg
		end
	end
	return nil, nil
end

-- ⚠️ นี่คือเหตุผลที่ต้องมี id: ลบฟองกลางอาเรย์แล้วฟองที่อยู่หลังมันเลื่อนตำแหน่งทั้งแถว
-- ถ้า client อ้างด้วย "ตำแหน่ง" มันจะชี้ผิดฟองทันทีที่มีไข่ฟักเสร็จคั่นจังหวะ
function PlayerData.removeHeldEgg(heldEggs: HeldEggs, id: number): HeldEgg?
	local index = PlayerData.findHeldEgg(heldEggs, id)
	if not index then
		return nil
	end
	return table.remove(heldEggs.items, index)
end

--------------------------------------------------------------------------------
-- session lock
--------------------------------------------------------------------------------

-- lock ยังมีชีวิตอยู่ไหม — แยกออกมาเป็นฟังก์ชันล้วนเพื่อให้เทสต์ยิงเวลาเองได้
-- ⚠️ `lock.at` มาจากเซิร์ฟเวอร์เครื่องอื่น นาฬิกาอาจไม่ตรงกันเป๊ะ
-- lock ที่ดู "มาจากอนาคต" จึงนับว่ายังมีชีวิต (ปลอดภัยกว่าปล่อยให้เข้า)
function PlayerData.isLockActive(lock: SessionLock?, now: number): boolean
	if type(lock) ~= "table" then
		return false
	end
	return now - lock.at < DS.SESSION_LOCK_SECONDS
end

--------------------------------------------------------------------------------
-- migration
--------------------------------------------------------------------------------

-- [เวอร์ชันเดิม] = ฟังก์ชันที่แปลงขึ้นอีกหนึ่งขั้น
-- ⚠️ แต่ละตัวต้อง idempotent และ **ห้ามอ่านค่าจาก Config ปัจจุบัน**
-- Config เปลี่ยนได้ แต่ migration ต้องให้ผลเดิมเสมอ ต้องใช้ค่าคงที่ก็ hard-code ไว้ในตัวมันเอง
local MIGRATIONS: { [number]: (Data) -> Data } = {}

-- v1 → v2 (Phase 3C-1): เพิ่ม battleRoster — ข้อมูลเก่ายังไม่เคยส่งแม่ไปรบ เริ่มว่างเสมอ
-- ไม่ทับของที่มีอยู่แล้ว (idempotent — รันซ้ำกับข้อมูลที่มีแล้วไม่เปลี่ยนอะไร)
MIGRATIONS[1] = function(data: Data): Data
	local raw = data :: any
	if type(raw.battleRoster) ~= "table" then
		raw.battleRoster = {}
	end
	return data
end

PlayerData.MIGRATIONS = MIGRATIONS

-- คืน (data, err) — err ไม่ nil แปลว่า **ห้ามเซฟทับ**
function PlayerData.migrate(data: Data): (Data?, string?)
	local version = data.schemaVersion
	if type(version) ~= "number" then
		version = 1 -- ข้อมูลยุคก่อนมี schemaVersion
		data.schemaVersion = 1
	end

	-- ⚠️ ข้อมูลใหม่กว่าโค้ดที่รันอยู่ = เซิร์ฟเวอร์ถูก rollback
	-- เซฟทับเมื่อไหร่ ของที่ผู้เล่นได้มาจากเวอร์ชันใหม่หายถาวร
	if version > Config.SCHEMA_VERSION then
		return nil, `ข้อมูลเป็น schema v{version} แต่เซิร์ฟเวอร์รู้จักถึง v{Config.SCHEMA_VERSION} เท่านั้น`
	end

	while data.schemaVersion < Config.SCHEMA_VERSION do
		local step = MIGRATIONS[data.schemaVersion]
		if not step then
			return nil, `ไม่มี migration จาก v{data.schemaVersion} ไป v{data.schemaVersion + 1}`
		end
		data = step(data)
		data.schemaVersion += 1
	end

	return data, nil
end

--------------------------------------------------------------------------------
-- เติมฟิลด์ที่ขาด
--------------------------------------------------------------------------------

-- ⚠️ ตาข่ายชั้นสุดท้าย กัน migration ลืมเติมฟิลด์ใหม่
-- เติมเฉพาะฟิลด์ที่ "ไม่มี" เท่านั้น ห้ามทับค่าที่ผู้เล่นมีอยู่
local function fillMissing(target: { [string]: any }, template: { [string]: any })
	for key, value in template do
		if target[key] == nil then
			if type(value) == "table" then
				local copy = {}
				fillMissing(copy, value)
				target[key] = copy
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" and #value == 0 then
			-- ลงลึกเฉพาะ dictionary (เช่น currency, stats) ไม่ลงไปในอาเรย์ของผู้เล่น
			fillMissing(target[key], value)
		end
	end
end

function PlayerData.normalize(data: Data): Data
	fillMissing(data :: any, PlayerData.createNew() :: any)

	-- อาเรย์ยาวคงที่ต้องยาวเท่าเดิมเสมอ (Config อาจขยายช่องระหว่างเวอร์ชัน)
	for index = 1, HATCHERY.MAX_SLOTS do
		if data.hatching[index] == nil then
			data.hatching[index] = false
		end
	end
	for index = 1, Config.Balance.Stage.COUNT do
		if data.stageProgress[index] == nil then
			data.stageProgress[index] = false
		end
	end

	-- ⚠️ nextEggId ต้องมากกว่า id ที่ใช้ไปแล้วเสมอ
	-- ถ้าข้อมูลเพี้ยนจนตัวนับต่ำกว่าของจริง ไข่สองฟองจะได้ id เดียวกัน
	local maxId = 0
	for _, egg in data.heldEggs.items do
		if egg.id > maxId then
			maxId = egg.id
		end
	end
	if data.heldEggs.nextEggId <= maxId then
		data.heldEggs.nextEggId = maxId + 1
	end

	return data
end

--------------------------------------------------------------------------------
-- กฎ encode — เรียกก่อนเขียนจริงทุกครั้ง
--------------------------------------------------------------------------------

-- ⚠️ ความผิดพลาดในตารางนี้ **ไม่มี error ตอนเซฟ** แต่ข้อมูลกลับมาไม่เหมือนเดิม
-- ที่เจ็บสุดคือ key ตัวเลขแบบมีรู: encode ได้ decode กลับมา key กลายเป็น string
-- แล้ว `hatching[2]` คืน nil ทั้งที่ข้อมูลยังอยู่ครบ (docs/data-schema.md §9.3)
local MAX_SAFE_INTEGER = 9007199254740992

local function checkValue(value: any, path: string, seen: { [any]: boolean })
	local kind = type(value)

	if kind == "number" then
		assert(value == value, `PlayerData: {path} เป็น NaN — encode ไม่ผ่าน`)
		assert(value ~= math.huge and value ~= -math.huge, `PlayerData: {path} เป็น inf — encode ไม่ผ่าน`)
		assert(
			math.abs(value) <= MAX_SAFE_INTEGER,
			`PlayerData: {path} = {value} เกิน 2^53 — จำนวนเต็มจะถูกปัดเศษเงียบ ๆ`
		)
		return
	end

	if kind == "string" or kind == "boolean" then
		return
	end

	assert(
		kind == "table",
		`PlayerData: {path} เป็น {kind} ซึ่งเซฟลง DataStore ไม่ได้ `
			.. `(Vector3 / Color3 / Enum / Instance / function ห้ามหลุดเข้ามา)`
	)
	assert(not seen[value], `PlayerData: {path} อ้างวนกลับมาที่ตัวเอง — encode ไม่จบ`)
	seen[value] = true

	local arrayCount = #value
	local stringKeys = 0
	local numberKeys = 0

	for key, child in value do
		local keyKind = type(key)
		if keyKind == "number" then
			numberKeys += 1
			assert(
				key % 1 == 0 and key >= 1 and key <= arrayCount,
				`PlayerData: {path} มี key ตัวเลข {key} ที่อยู่นอกช่วงอาเรย์ (1..{arrayCount}) — `
					.. `อาเรย์มีรู decode กลับมา key จะกลายเป็น string`
			)
		elseif keyKind == "string" then
			stringKeys += 1
		else
			error(`PlayerData: {path} มี key ชนิด {keyKind} ซึ่งเซฟไม่ได้`)
		end
		checkValue(child, `{path}.{tostring(key)}`, seen)
	end

	assert(
		stringKeys == 0 or numberKeys == 0,
		`PlayerData: {path} ผสม key ตัวเลขกับ key string ในตารางเดียว — SetAsync จะ error`
	)

	seen[value] = nil
end

-- โยน error ทันทีเมื่อผิดกฎ — ตั้งใจให้ดังตอนเทสต์ ไม่ใช่เงียบตอน production
function PlayerData.sanitizeForSave(data: Data)
	checkValue(data :: any, "PlayerData", {})
end

--------------------------------------------------------------------------------
-- ประเมินขนาด
--------------------------------------------------------------------------------

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

-- ⚠️ ไม่ใช่ตัว encode ตัวเดียวกับที่ Roblox ใช้จริง — ใช้ "วัดขนาด" อย่างเดียว
-- ตัวจริงคือ HttpService:JSONEncode ซึ่งเรียกนอก Roblox ไม่ได้
-- จึงตั้งเพดานตัวเองไว้ที่ 3 MB ไม่ใช่ 4 MB เผื่อส่วนต่าง
function PlayerData.encode(value: any): string
	local kind = type(value)

	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		if value % 1 == 0 then
			return string.format("%d", value)
		end
		return tostring(value)
	elseif kind == "string" then
		return '"' .. (value:gsub('[%c"\\]', function(c)
			return ESCAPES[c] or string.format("\\u%04x", c:byte())
		end)) .. '"'
	end

	assert(kind == "table", `PlayerData.encode: เจอค่าชนิด {kind}`)

	local count = #value
	if count > 0 then
		local parts = table.create(count)
		for index = 1, count do
			parts[index] = PlayerData.encode(value[index])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end

	-- ⚠️ เรียง key ก่อนเสมอ ไม่งั้นขนาดที่วัดได้แกว่งตามลำดับที่ Lua คืนมา
	local keys = {}
	for key in value do
		table.insert(keys, tostring(key))
	end
	if #keys == 0 then
		-- ตารางว่าง: อาเรย์ว่างกับ dict ว่างแยกกันไม่ออก นับเป็น dict ว่าง
		return "{}"
	end
	table.sort(keys)

	local parts = table.create(#keys)
	for index, key in keys do
		parts[index] = PlayerData.encode(key) .. ":" .. PlayerData.encode(value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function PlayerData.estimateBytes(data: Data): number
	return #PlayerData.encode(data :: any)
end

--------------------------------------------------------------------------------
-- ข้อมูลที่เต็มทุกเพดาน — ใช้วัดว่าเพดานที่ตั้งไว้ยังอยู่ในลิมิต DataStore
--------------------------------------------------------------------------------

-- ⚠️ ต้องเป็น "เต็มทุกช่องพร้อมกัน" จริง ๆ ไม่ใช่ประมาณเอา
-- เพราะจุดประสงค์คือรู้ล่วงหน้าว่าเพดานชุดนี้ทำให้ข้อมูลทะลุลิมิตได้ไหม
function PlayerData.buildWorstCase(): Data
	local data = PlayerData.createNew()
	local inventory = Config.Inventory

	-- uid ที่ยาวที่สุดเท่าที่เป็นไปได้ (UserId 10 หลัก + ตัวนับ 6 หลัก)
	local function heavyMother(index: number, inPen: boolean): Mother
		return {
			uid = Config.makeUid(9999999999, 900000 + index),
			charId = "jade_emperor", -- charId ที่ยาวที่สุดในตาราง
			weight = 100000000,
			statuses = { "silver", "gold" },
			lastProducedAt = if inPen then 9999999999 else nil,
			obtainedAt = 9999999999,
			locked = true,
		}
	end

	local penCapacity = Config.getPenCapacity(Config.Balance.Pen.MAX_LEVEL)
	for index = 1, penCapacity do
		table.insert(data.mothersInPen, heavyMother(index, true))
	end
	for index = 1, Config.Balance.Bag.CAPACITY do
		table.insert(data.mothersInBag, heavyMother(index, false))
	end
	-- roster เต็มพร้อมกันด้วย (uid ไม่ชนกับกระเป๋า — แม่ตัวเดียวอยู่ได้ที่เดียว)
	for index = 1, Config.Balance.Combat.MAX_BATTLE_MOTHERS do
		table.insert(data.battleRoster, heavyMother(Config.Balance.Bag.CAPACITY + index, false))
	end

	-- กองลูก: key ยาวสุด × จำนวนกองสูงสุด × จำนวนลูกสูงสุดต่อกอง
	-- ⚠️ releaseOrder เต็มขนาดเดียวกันด้วย (ทุกกองต้องมีที่อยู่ในลำดับปล่อย)
	for index = 1, inventory.MAX_CHILD_STACKS do
		local key = Config.makeStackKey("jade_emperor", 100000000 - index, { "gold", "silver" })
		data.children[key] = inventory.MAX_CHILDREN_PER_STACK
		table.insert(data.releaseOrder, key)
	end

	data.combatAutoPaused = true

	for index = 1, HATCHERY.MAX_SLOTS do
		data.hatching[index] = {
			eggId = "egg_legendary",
			weight = 100000000,
			charId = "jade_emperor",
			startedAt = 9999999999,
			hatchAt = 9999999999,
		}
	end

	-- ⚠️ จุดที่ต้องจับตา: กระเป๋าไข่เต็ม 10,000 ฟอง
	for index = 1, HATCHERY.BAG_CAPACITY do
		table.insert(data.heldEggs.items, {
			id = 999999 + index,
			eggId = "egg_legendary",
			weight = 100000000,
		})
	end
	data.heldEggs.nextEggId = 999999 + HATCHERY.BAG_CAPACITY + 1

	for index = 1, Config.Balance.Stage.COUNT do
		data.stageProgress[index] = { defendersRemaining = 1000000000, wallHpRemaining = 999999999999 }
	end

	data.sessionLock = { jobId = string.rep("0", 36), placeId = 9999999999, at = 9999999999 }

	return data
end

--------------------------------------------------------------------------------
-- ยาม — เรียกตอนบูต คู่กับ Config.validate()
--------------------------------------------------------------------------------

-- ⚠️ แยกจาก Config.validate() เพราะ Config require ไฟล์นี้ไม่ได้ (จะวนกลับมาหากัน)
-- Main.server.lua เรียกทั้งสองตัวเรียงกัน
function PlayerData.validate()
	local worst = PlayerData.buildWorstCase()

	-- ข้อมูลที่เต็มทุกเพดานต้องยัง encode ได้ตามกฎ §9.3
	PlayerData.sanitizeForSave(worst)

	local bytes = PlayerData.estimateBytes(worst)
	assert(
		bytes < DS.MAX_PLAYER_DATA_BYTES,
		`PlayerData: ข้อมูลที่เต็มทุกเพดานมีขนาด {bytes} ไบต์ เกินเพดานที่ตั้งไว้ `
			.. `{DS.MAX_PLAYER_DATA_BYTES} ไบต์ — ลดเพดานใน Config.Inventory หรือ Config.Balance.Hatchery`
	)

	-- ผู้เล่นใหม่ต้องผ่านกฎ encode ด้วย (กันเผลอใส่ของแปลกลง template)
	PlayerData.sanitizeForSave(PlayerData.createNew())

	return bytes
end

return PlayerData
