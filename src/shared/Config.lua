--!strict
-- egg-army-game :: Config กลาง
--
-- ⚠️ ไฟล์นี้คือ "โครงหลัก" ตาม CLAUDE.md
-- ทั้ง server และ client อ่านค่าจากที่นี่ที่เดียว ห้าม hard-code ตัวเลขซ้ำที่อื่น
-- การแก้ id / โครงสร้างตารางในไฟล์นี้กระทบข้อมูลผู้เล่นที่บันทึกไว้ (ตั้งแต่ Phase 2 เป็นต้นไป)
-- → ต้องทวนก่อนแก้เสมอ
--
-- หมายเหตุ Phase 1: ยังไม่มี DataStore ข้อมูลอยู่ใน memory ฝั่ง server เท่านั้น

local Config = {}

-- เวอร์ชันของโครงสร้าง PlayerData ที่โค้ดชุดนี้เขียน/อ่านได้
-- ⚠️ ทุกครั้งที่เปลี่ยนโครง PlayerData ต้องบวกเลขนี้ + เขียน migration
-- รายละเอียดใน docs/data-schema.md
Config.SCHEMA_VERSION = 1

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

-- ระดับความหายากของทหาร ใช้ทั้งตอนแสดงผลและตอนคิดราคา/อัปเกรดใน Phase 4
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type UnitType = {
	id: string, -- คีย์ที่ใช้อ้างอิงในโค้ดและในข้อมูลที่บันทึก (ห้ามเปลี่ยนพร่ำเพรื่อ)
	name: string, -- ชื่อไทยสำหรับโชว์ใน UI
	rarity: Rarity, -- ระดับความหายาก
	hp: number, -- เลือดตั้งต้น ใช้ตอน combat (Phase 3)
	damage: number, -- ดาเมจต่อการโจมตี 1 ครั้ง (Phase 3)
	speed: number, -- ความเร็วเดิน studs/วินาที ยิ่งมากยิ่งถึงฐานศัตรูก่อน (Phase 3)
	enabled: boolean, -- false = เลิกใช้แล้ว แต่ยัง lookup ได้ (ห้ามลบทิ้ง ดู docs/data-schema.md)
}

-- หนึ่งแถวในตารางสุ่มของไข่: ทหารตัวไหน น้ำหนักเท่าไหร่
-- โอกาสออก = weight ของตัวนั้น ÷ ผลรวม weight ทั้งตาราง
export type HatchEntry = {
	unitId: string,
	weight: number,
}

export type EggType = {
	id: string, -- คีย์อ้างอิง (ห้ามเปลี่ยนพร่ำเพรื่อ)
	name: string, -- ชื่อไทยสำหรับโชว์ใน UI
	price: number, -- ราคาซื้อ (ยังไม่หักจริงใน Phase 1 — ระบบ currency อยู่ Phase 4)
	hatchTime: number, -- เวลาฟักเป็นวินาที นับฝั่ง server เท่านั้น
	-- ⚠️ Color3 เซฟลง DataStore ไม่ได้ ห้ามให้ค่านี้หลุดเข้าไปใน PlayerData
	color: Color3, -- สีของก้อนไข่ตอนวางในฟาร์ม (ชั่วคราว ไว้ดูด้วยตาตอนเทสต์)
	hatchTable: { HatchEntry }, -- ตารางน้ำหนักการสุ่มว่าฟักแล้วออกทหารตัวไหน
	enabled: boolean, -- false = ไม่ให้สุ่ม/ซื้อได้อีก แต่ของเก่าที่ผู้เล่นถืออยู่ยังอ่านได้
}

-- สถานะที่ติดกับ "ตัวแม่" ได้ (Phase 4 ค่อยมีของจริง ตอนนี้เตรียมโครงไว้ก่อน)
export type StatusType = {
	id: string, -- ตัวอักษรเล็กภาษาอังกฤษเท่านั้น เพราะถูกใช้ประกอบ stack key
	name: string, -- ชื่อไทยสำหรับ UI
	order: number, -- ลำดับที่ใช้เรียงตอนแสดงผล (ไม่เกี่ยวกับการเรียงใน stack key)
	enabled: boolean,
}

-- หนึ่งชั้นน้ำหนักของตัวแม่
export type WeightTier = {
	id: number,
	min: number, -- น้ำหนักต่ำสุดในชั้นนี้ (kg, จำนวนเต็ม)
	max: number, -- น้ำหนักสูงสุดในชั้นนี้ (kg, จำนวนเต็ม) — ชั้นบนสุด min = max
	weight: number, -- น้ำหนักการสุ่ม ต่อ Config.Weight.TIER_ROLL_MAX
}

-- ชุดค่าคงที่ของสูตรแปลงน้ำหนัก → damage
export type DamageFormula = {
	id: string,
	name: string,
	kind: string, -- "power" = baseDamage * (w/ref)^exponent | "log" = baseDamage * (1 + log10(w/ref))
	exponent: number?, -- ใช้เฉพาะ kind = "power"
	baseDamage: number, -- damage ที่น้ำหนัก = referenceWeight
	referenceWeight: number, -- น้ำหนักอ้างอิง (kg)
	minDamage: number, -- พื้นบังคับ กันสูตร log ให้ค่าติดลบกับตัวเบามาก
}

--------------------------------------------------------------------------------
-- ค่าตั้งของฟาร์ม
--------------------------------------------------------------------------------

Config.Farm = {
	-- จำนวน plot สูงสุดในเซิร์ฟเวอร์ = จำนวนผู้เล่นสูงสุดที่มีฟาร์มได้พร้อมกัน
	MAX_PLOTS = 6,

	-- จำนวนช่องวางไข่ต่อผู้เล่น 1 คน
	EGG_SLOTS_PER_PLAYER = 4,

	-- ขนาดพื้น plot และระยะห่างระหว่าง plot (studs)
	PLOT_SIZE = Vector3.new(32, 1, 32),
	PLOT_SPACING = 40,
	PLOT_ORIGIN = Vector3.new(0, 0, 0),

	-- ทุกกี่วินาที server จะเช็คไข่ที่ครบเวลา แล้ว sync สถานะกลับไปหา client
	-- ค่านี้เป็นความละเอียดของตัวจับเวลาด้วย (1 = คลาดเคลื่อนได้ไม่เกิน 1 วินาที)
	SYNC_INTERVAL = 1,

	-- กันผู้เล่นสแปมกดวางไข่ (วินาที) — ด่านแรกของการกัน exploit
	PLACE_EGG_COOLDOWN = 0.25,
}

--------------------------------------------------------------------------------
-- ชื่อ RemoteEvent
--------------------------------------------------------------------------------
-- ⚠️ โครงหลัก: ชื่อกับ signature ที่ client-server ตกลงกัน เปลี่ยนแล้วพังทั้งสองฝั่ง
--
-- signature ที่ใช้ใน Phase 1:
--
--   PlaceEggRequest  (client → server)
--     :FireServer(eggId: string, slotIndex: number?)
--     slotIndex เป็น nil ได้ = ให้ server เลือกช่องว่างช่องแรกให้
--
--   EggHatched       (server → client)
--     :FireClient(player, payload)
--     payload = { slotIndex: number, eggId: string, unitId: string,
--                 unitName: string, rarity: string }
--
--   FarmStateSync    (server → client)
--     :FireClient(player, payload)
--     payload = {
--       slots = { [i] = { occupied: boolean, eggId: string?, eggName: string?,
--                         remaining: number?, total: number? } },
--       unitCount = number,
--     }
--     ส่งทุก SYNC_INTERVAL วินาที และส่งทันทีเมื่อสถานะเปลี่ยน

Config.RemoteNames = {
	FOLDER = "Remotes", -- Folder ใน ReplicatedStorage ที่เก็บ RemoteEvent ทั้งหมด
	PLACE_EGG_REQUEST = "PlaceEggRequest",
	EGG_HATCHED = "EggHatched",
	FARM_STATE_SYNC = "FarmStateSync",
}

--------------------------------------------------------------------------------
-- DataStore
--------------------------------------------------------------------------------
-- ⚠️ เปลี่ยน NAME หรือ KEY_PREFIX = ผู้เล่นเก่าอ่านข้อมูลตัวเองไม่เจอ = เริ่มใหม่หมด

Config.DataStore = {
	NAME = "PlayerData_v1", -- ใช้ตอน publish จริง
	DEV_NAME = "PlayerData_dev_v1", -- ใช้ตอนทดสอบใน Studio จะได้ไม่เขียนทับข้อมูลจริง
	KEY_PREFIX = "player_", -- key เต็ม = KEY_PREFIX .. UserId (ลิมิตของ Roblox คือ 50 ตัวอักษร)

	AUTOSAVE_INTERVAL = 60, -- เซฟอัตโนมัติทุกกี่วินาที (งบเขียน = 60 + ผู้เล่น×10 ต่อนาที)
	LOAD_RETRY_COUNT = 3, -- โหลดไม่สำเร็จ ลองซ้ำกี่ครั้ง
	LOAD_RETRY_BASE_DELAY = 1, -- หน่วงครั้งแรกกี่วินาที แล้วคูณสองไปเรื่อย ๆ
}

--------------------------------------------------------------------------------
-- น้ำหนักตัวแม่
--------------------------------------------------------------------------------
-- ⚠️ โครงหลัก: น้ำหนักแม่เป็นส่วนหนึ่งของ stack key ของลูก เปลี่ยนวิธีสุ่มหรือ
-- วิธีปัดเศษเมื่อไหร่ กองลูกเดิมของผู้เล่นจะแตกเป็นคนละกองทันที
--
-- วิธีสุ่ม 2 ขั้น (ห้ามสุ่ม uniform ทั้งช่วง 100–100,000,000 รวดเดียว):
--   ขั้น 1  สุ่มว่าจะได้ tier ไหน ตามค่า weight ในตาราง
--   ขั้น 2  สุ่มน้ำหนักภายใน tier นั้นแบบ uniform
-- ถ้าสุ่ม uniform ทั้งช่วงรวดเดียว โอกาสได้ต่ำกว่า 1,000 kg จะเหลือ ~0.001%
-- แทนที่จะเป็น 90% ตามที่ออกแบบไว้ — คนละเกมกันเลย
--
-- ทำไม weight เป็นจำนวนเต็มต่อ 1,000,000 ไม่ใช่เปอร์เซ็นต์ทศนิยม:
-- อัตราต่ำสุดคือ 0.0001% ถ้าเก็บเป็น float แล้วบวกสะสมจะเจอ error ปัดเศษ
-- จนผลรวมไม่เท่ากับ 100 พอดี ใช้จำนวนเต็มแล้วเทียบด้วย NextInteger จบปัญหา

local WeightTiers: { WeightTier } = {
	-- id      ช่วงน้ำหนัก (kg)                    weight     = โอกาส      พบ 1 ใน
	{ id = 1, min = 100, max = 999, weight = 900000 }, -- 90%       1
	{ id = 2, min = 1000, max = 9999, weight = 90000 }, -- 9%        11
	{ id = 3, min = 10000, max = 99999, weight = 9000 }, -- 0.9%      111
	{ id = 4, min = 100000, max = 999999, weight = 900 }, -- 0.09%     1,111
	{ id = 5, min = 1000000, max = 9999999, weight = 90 }, -- 0.009%    11,111
	{ id = 6, min = 10000000, max = 99999999, weight = 9 }, -- 0.0009%   111,111
	{ id = 7, min = 100000000, max = 100000000, weight = 1 }, -- 0.0001%   1,000,000
}

Config.Weight = {
	-- ลูกหนัก 1% ของแม่เสมอ
	-- ⚠️ ค่านี้ทำให้น้ำหนักลูกเป็นทศนิยมได้ (แม่ 999 → ลูก 9.99)
	-- จึงห้ามเอาน้ำหนักลูกไปสร้าง stack key ให้ใช้น้ำหนัก "แม่" ซึ่งเป็นจำนวนเต็มเสมอ
	CHILD_RATIO = 0.01,

	-- ผลรวม weight ของทุก tier ต้องเท่ากับค่านี้พอดี (validate() เช็คให้)
	TIER_ROLL_MAX = 1000000,

	TIERS = WeightTiers,
}

--------------------------------------------------------------------------------
-- อัตราผลิตลูก
--------------------------------------------------------------------------------
-- แม่ 1 ตัวผลิตลูกอัตโนมัติ ลูกที่ได้หนัก 1% ของแม่ และคัดลอกชุดสถานะของแม่
-- ณ เวลาที่ผลิต (ดู docs/data-schema.md)
--
-- ทั้งออนไลน์และออฟไลน์คำนวณจาก timestamp ไม่ใช่ loop นับสด
-- เพื่อให้ผลลัพธ์เหมือนกันไม่ว่าเซิร์ฟเวอร์จะกระตุกหรือผู้เล่นจะออกไปนานแค่ไหน

Config.Production = {
	ONLINE_PER_MINUTE = 1, -- ตอนออนไลน์ แม่ 1 ตัวผลิตกี่ตัวต่อนาที
	OFFLINE_PER_MINUTE = 0.1, -- ตอนออฟไลน์ ช้ากว่า 10 เท่า
	OFFLINE_CAP_SECONDS = 8 * 60 * 60, -- สะสมออฟไลน์ได้สูงสุด 8 ชั่วโมง (= 48 ตัวต่อแม่ 1 ตัว)

	TICK_INTERVAL = 5, -- ตอนออนไลน์เช็คทุกกี่วินาที (ไม่กระทบผลลัพธ์ แค่ความถี่อัปเดต UI)

	-- เพดานกันเลขบวมกรณีนาฬิกาเซิร์ฟเวอร์กระโดด
	-- ถ้าคำนวณได้เกินนี้ในการ settle ครั้งเดียว ให้ตัดที่ค่านี้แล้ว warn
	MAX_PER_SETTLE = 100000,

	-- Phase 4 จะมี upgrade มาคูณอัตราผลิต (ตัวคูณเก็บใน PlayerData ไม่ใช่ที่นี่)
	MAX_RATE_MULTIPLIER = 100,
}

--------------------------------------------------------------------------------
-- สถานะของตัวแม่
--------------------------------------------------------------------------------
-- Phase 1-3 ยังไม่มีสถานะจริง (enabled = false ทุกตัว) แต่ schema รองรับไว้แล้ว
-- ⚠️ id ต้องเป็นตัวอักษรเล็กภาษาอังกฤษล้วน ห้ามมีอักขระคั่นของ stack key
-- และ "ห้ามเปลี่ยน id หลังจากมีผู้เล่นถือลูกที่ติดสถานะนั้นแล้ว"
-- เพราะ id ฝังอยู่ใน stack key ที่เซฟลง DataStore ไปแล้ว

local Statuses: { [string]: StatusType } = {
	gold = { id = "gold", name = "ทอง", order = 1, enabled = false },
	silver = { id = "silver", name = "เงิน", order = 2, enabled = false },
}

Config.Statuses = Statuses

--------------------------------------------------------------------------------
-- Stack key ของกองลูก
--------------------------------------------------------------------------------
-- ⚠️ โครงหลัก: รูปแบบ key นี้คือคีย์ของ dictionary ที่เซฟลง DataStore
-- เปลี่ยนรูปแบบเมื่อไหร่ = กองลูกเดิมของผู้เล่นทุกคนอ่านไม่ออก ต้อง migrate
--
-- รูปแบบ:  "<น้ำหนักแม่><FIELD_SEPARATOR><สถานะเรียงแล้ว คั่นด้วย STATUS_SEPARATOR>"
--   ไม่มีสถานะ   → "1500|"
--   สถานะเดียว   → "1500|gold"
--   หลายสถานะ    → "1500|gold,silver"
--
-- กฎที่ห้ามพลาด (ใช้ Config.makeStackKey เสมอ ห้ามต่อ string เอง):
--   1. ใช้น้ำหนัก "แม่" (จำนวนเต็ม) ไม่ใช่น้ำหนักลูก (ทศนิยม → key เพี้ยน)
--   2. เรียงสถานะด้วย table.sort ก่อนเสมอ ไม่งั้น {gold,silver} กับ
--      {silver,gold} จะกลายเป็นคนละกองทั้งที่ควรเป็นกองเดียวกัน
--   3. ตัดสถานะซ้ำออกก่อนเรียง

Config.Stack = {
	FIELD_SEPARATOR = "|",
	STATUS_SEPARATOR = ",",
}

--------------------------------------------------------------------------------
-- สูตรแปลงน้ำหนัก → damage
--------------------------------------------------------------------------------
-- ⚠️ ยังไม่ได้เลือกสูตร — ACTIVE_FORMULA เป็น nil โดยตั้งใจ
-- ตารางเปรียบเทียบทั้ง 3 สูตรอยู่ใน docs/data-schema.md
-- เลือกแล้วค่อยใส่ id ลงไป แล้วเขียนตัวคำนวณจริงใน Phase 3
--
-- ทุกสูตรตั้งให้แม่ 100 kg = 10 damage เท่ากัน จะได้เทียบความชันกันตรง ๆ
-- ทุกสูตรเป็นแบบถดถอย (ยิ่งหนักยิ่งได้ damage เพิ่มในอัตราที่ลดลง)
-- ไม่มีสูตรไหนแปรผันตรงกับน้ำหนัก เพราะแม่ 100,000,000 kg จะแรงกว่า
-- แม่ 100 kg ถึงล้านเท่า ซึ่งทำให้ตัวเล็กไร้ความหมายทันที

local DamageFormulas: { [string]: DamageFormula } = {
	sqrt = {
		id = "sqrt",
		name = "รากที่สอง",
		kind = "power",
		exponent = 0.5,
		baseDamage = 10,
		referenceWeight = 100,
		minDamage = 1,
	},
	cbrt = {
		id = "cbrt",
		name = "รากที่สาม",
		kind = "power",
		exponent = 1 / 3,
		baseDamage = 10,
		referenceWeight = 100,
		minDamage = 1,
	},
	log10 = {
		id = "log10",
		name = "ลอการิทึม",
		kind = "log",
		exponent = nil,
		baseDamage = 10,
		referenceWeight = 100,
		-- สูตร log ให้ค่า "ติดลบ" กับตัวที่เบากว่า referenceWeight
		-- เช่นลูกของแม่ 100 kg หนัก 1 kg จะได้ -10
		-- พื้นบังคับนี้จึงจำเป็นจริง ๆ ไม่ใช่แค่กันเหนียว
		minDamage = 1,
	},
}

local Damage: { ACTIVE_FORMULA: string?, FORMULAS: { [string]: DamageFormula } } = {
	ACTIVE_FORMULA = nil, -- ⚠️ รอเลือก: "sqrt" | "cbrt" | "log10"
	FORMULAS = DamageFormulas,
}

Config.Damage = Damage

--------------------------------------------------------------------------------
-- เพดานคลัง
--------------------------------------------------------------------------------
-- ตัวเลขพวกนี้เป็นข้อเสนอ รอยืนยัน — มีไว้กันข้อมูลบวมและกัน exploit
-- ต้องมีตั้งแต่วันแรก เพราะ "เพิ่ม" เพดานทีหลังง่าย แต่ "ลด" ทีหลังแปลว่าต้องยึดของผู้เล่น

Config.Inventory = {
	MAX_MOTHERS = 200, -- แม่คือเครื่องผลิต จำกัดไว้เพื่อคุมทั้งขนาดข้อมูลและอัตราผลิตรวม
	MAX_CHILD_STACKS = 500, -- จำนวน "กอง" ไม่ใช่จำนวนลูก (ลูกในกองเดียวมีได้เป็นล้าน)
	MAX_CHILDREN_PER_STACK = 1000000000, -- กันเลขล้นตอนบวกสะสม
	MAX_HELD_EGGS_PER_TYPE = 999,

	MAX_TEAMS = 1, -- Phase 3 เริ่มที่ทีมเดียว โครงเป็น array ไว้เผื่อขยาย
	MAX_TEAM_MOTHERS = 3, -- แม่ในทีมตายถาวร จำกัดไว้ไม่ให้เสียหายหนักเกินไปในตาเดียว
	MAX_TEAM_CHILD_STACKS = 5,
	MAX_TEAM_NAME_LENGTH = 20,
}

--------------------------------------------------------------------------------
-- ผู้เล่นใหม่
--------------------------------------------------------------------------------
-- ค่าตั้งต้นตอนสร้าง PlayerData ครั้งแรก อยู่ที่นี่ไม่ใช่ฝังใน DataService
-- จะได้ปรับ onboarding ได้โดยไม่ต้องแตะโค้ดเซฟ

-- [eggId] = จำนวน — แถมไข่ให้ลองวางทันทีโดยไม่ต้องซื้อ
local startingEggs: { [string]: number } = {
	egg_common = 1,
}

Config.NewPlayer = {
	coins = 500, -- ซื้อไข่ธรรมดาได้ 5 ฟอง
	gems = 0,
	startingEggs = startingEggs,
}

--------------------------------------------------------------------------------
-- ลำดับความหายาก
--------------------------------------------------------------------------------
-- type Rarity เป็น union ซึ่ง iterate ไม่ได้ ตัวนี้คือ list เรียงจากธรรมดา → หายากสุด
-- ใช้ตอนเรียง UI คลัง และตอนทำสถิติแยกตามความหายาก

local Rarities: { Rarity } = { "Common", "Rare", "Epic", "Legendary" }

Config.Rarities = Rarities

--------------------------------------------------------------------------------
-- ทหาร
--------------------------------------------------------------------------------
-- ตัวเลข hp/damage/speed ยังไม่ได้ balance จริง ใช้เป็นตุ๊กตาไปก่อนจนถึง Phase 3

local UnitTypes: { [string]: UnitType } = {
	recruit = {
		id = "recruit",
		enabled = true,
		name = "พลทหารฝึกหัด",
		rarity = "Common",
		hp = 100,
		damage = 10,
		speed = 12,
	},
	spearman = {
		id = "spearman",
		enabled = true,
		name = "พลหอก",
		rarity = "Common",
		hp = 140,
		damage = 14,
		speed = 11,
	},
	archer = {
		id = "archer",
		enabled = true,
		name = "พลธนู",
		rarity = "Rare",
		hp = 110,
		damage = 22,
		speed = 13,
	},
	knight = {
		id = "knight",
		enabled = true,
		name = "อัศวิน",
		rarity = "Rare",
		hp = 260,
		damage = 26,
		speed = 10,
	},
	mage = {
		id = "mage",
		enabled = true,
		name = "จอมเวท",
		rarity = "Epic",
		hp = 180,
		damage = 45,
		speed = 12,
	},
	dragon_rider = {
		id = "dragon_rider",
		enabled = true,
		name = "ผู้ขี่มังกร",
		rarity = "Legendary",
		hp = 420,
		damage = 70,
		speed = 16,
	},
}

Config.UnitTypes = UnitTypes

--------------------------------------------------------------------------------
-- ไข่
--------------------------------------------------------------------------------
-- weight ไม่ต้องรวมกันได้ 100 โค้ดหารด้วยผลรวมเองอยู่แล้ว
-- อยากเพิ่มโอกาสตัวไหนก็เพิ่มตัวเลข weight ของตัวนั้น

local EggTypes: { [string]: EggType } = {
	egg_common = {
		id = "egg_common",
		enabled = true,
		name = "ไข่ธรรมดา",
		price = 100,
		hatchTime = 30,
		color = Color3.fromRGB(235, 235, 225),
		hatchTable = {
			{ unitId = "recruit", weight = 55 }, -- 55%
			{ unitId = "spearman", weight = 30 }, -- 30%
			{ unitId = "archer", weight = 12 }, -- 12%
			{ unitId = "knight", weight = 3 }, -- 3%
		},
	},
	egg_rare = {
		id = "egg_rare",
		enabled = true,
		name = "ไข่หายาก",
		price = 500,
		hatchTime = 120,
		color = Color3.fromRGB(90, 160, 235),
		hatchTable = {
			{ unitId = "spearman", weight = 30 },
			{ unitId = "archer", weight = 35 },
			{ unitId = "knight", weight = 25 },
			{ unitId = "mage", weight = 9 },
			{ unitId = "dragon_rider", weight = 1 },
		},
	},
	egg_legendary = {
		id = "egg_legendary",
		enabled = true,
		name = "ไข่ตำนาน",
		price = 2500,
		hatchTime = 300,
		color = Color3.fromRGB(240, 185, 60),
		hatchTable = {
			{ unitId = "knight", weight = 30 },
			{ unitId = "mage", weight = 45 },
			{ unitId = "dragon_rider", weight = 25 },
		},
	},
}

Config.EggTypes = EggTypes

-- ไข่ที่ปุ่มทดสอบฝั่ง client ใช้ (Phase 1 มีปุ่มเดียว)
Config.DEFAULT_EGG_ID = "egg_common"

--------------------------------------------------------------------------------
-- ตัวช่วยอ่านค่า
--------------------------------------------------------------------------------
-- คืน nil เมื่อหาไม่เจอ ฝั่ง server ต้องเช็ค nil เสมอ เพราะ id อาจมาจาก client

function Config.getUnit(unitId: string): UnitType?
	return UnitTypes[unitId]
end

function Config.getEgg(eggId: string): EggType?
	return EggTypes[eggId]
end

function Config.getStatus(statusId: string): StatusType?
	return Statuses[statusId]
end

-- สูตร damage ที่เลือกใช้อยู่ คืน nil ถ้ายังไม่ได้เลือก (สถานะปัจจุบัน)
function Config.getActiveDamageFormula(): DamageFormula?
	local id = Damage.ACTIVE_FORMULA
	if not id then
		return nil
	end
	return DamageFormulas[id]
end

-- น้ำหนักลูกจากน้ำหนักแม่ (อาจเป็นทศนิยม — ห้ามเอาไปทำ stack key)
function Config.getChildWeight(motherWeight: number): number
	return motherWeight * Config.Weight.CHILD_RATIO
end

--------------------------------------------------------------------------------
-- สุ่มน้ำหนักตัวแม่
--------------------------------------------------------------------------------
-- สุ่ม 2 ขั้นตามที่อธิบายไว้ข้างบน: เลือก tier ก่อน แล้วค่อยสุ่มในช่วงของ tier นั้น
-- rng ส่งเข้ามาจากข้างนอกเพื่อให้เทสต์ซ้ำได้ด้วย seed เดิม

function Config.rollMotherWeight(rng: Random): number
	-- ขั้น 1: สุ่ม tier — ใช้จำนวนเต็มล้วน ไม่มี float เข้ามาเกี่ยวเลย
	local roll = rng:NextInteger(1, Config.Weight.TIER_ROLL_MAX)
	local acc = 0

	for _, tier in WeightTiers do
		acc += tier.weight
		if roll <= acc then
			-- ขั้น 2: สุ่มน้ำหนักภายใน tier แบบ uniform
			return rng:NextInteger(tier.min, tier.max)
		end
	end

	-- ตกมาถึงตรงนี้ไม่ได้ถ้า validate() ผ่าน (ผลรวม weight = TIER_ROLL_MAX)
	-- แต่กันไว้ให้คืนค่าที่ใช้งานได้เสมอ
	local last = WeightTiers[#WeightTiers]
	return rng:NextInteger(last.min, last.max)
end

--------------------------------------------------------------------------------
-- Stack key
--------------------------------------------------------------------------------
-- ⚠️ ห้ามต่อ string เองที่อื่น ใช้สองฟังก์ชันนี้เท่านั้น
-- ถ้ามีที่ไหนสร้าง key เองแล้วเรียงสถานะคนละแบบ กองลูกจะแตกโดยไม่มีใครรู้ตัว

-- motherWeight ต้องเป็นจำนวนเต็ม (น้ำหนักแม่) ไม่ใช่น้ำหนักลูก
function Config.makeStackKey(motherWeight: number, statuses: { string }?): string
	local unique: { string } = {}
	local seen: { [string]: boolean } = {}

	if statuses then
		for _, id in statuses do
			if not seen[id] then
				seen[id] = true
				table.insert(unique, id)
			end
		end
	end

	-- เรียงตายตัวเสมอ นี่คือหัวใจของการรวมกอง
	table.sort(unique)

	return string.format("%d", motherWeight)
		.. Config.Stack.FIELD_SEPARATOR
		.. table.concat(unique, Config.Stack.STATUS_SEPARATOR)
end

-- แยก stack key กลับเป็น (น้ำหนักแม่, รายการสถานะ)
-- คืน nil เป็นค่าแรกถ้า key ผิดรูป — ผู้เรียกต้องเช็ค
function Config.parseStackKey(key: string): (number?, { string })
	local at = string.find(key, Config.Stack.FIELD_SEPARATOR, 1, true)
	if not at then
		return nil, {}
	end

	local motherWeight = tonumber(string.sub(key, 1, at - 1))
	local rest = string.sub(key, at + 1)
	local statuses: { string } = {}

	if rest ~= "" then
		for id in string.gmatch(rest, "[^" .. Config.Stack.STATUS_SEPARATOR .. "]+") do
			table.insert(statuses, id)
		end
	end

	return motherWeight, statuses
end

--------------------------------------------------------------------------------
-- แสดงน้ำหนักเป็นข้อความ
--------------------------------------------------------------------------------
-- 1200 → "1.2K", 3400000 → "3.4M", 1100000000 → "1.1B"
-- ต่ำกว่าพันแสดงทศนิยมได้ถึง 2 ตำแหน่งแล้วตัดศูนย์ท้ายทิ้ง
-- (ลูกของแม่ตัวเล็กหนักไม่ถึง 10 kg เช่นแม่ 999 → ลูก 9.99)
-- ไม่ใส่หน่วย "kg" ให้ ผู้เรียกเติมเองตามบริบท

function Config.formatWeight(kg: number): string
	local abs = math.abs(kg)

	if abs >= 1e9 then
		return string.format("%.1fB", kg / 1e9)
	elseif abs >= 1e6 then
		return string.format("%.1fM", kg / 1e6)
	elseif abs >= 1e3 then
		return string.format("%.1fK", kg / 1e3)
	end

	local text = string.format("%.2f", kg)
	text = string.gsub(text, "%.?0+$", "")
	return text
end

-- เช็คความถูกต้องของตารางตอนเซิร์ฟเวอร์บูต
-- ถ้าพิมพ์ unitId ผิดในตารางสุ่ม จะได้รู้ทันทีตอนเปิดเกม ไม่ใช่ตอนผู้เล่นฟักไข่
function Config.validate()
	for eggId, egg in EggTypes do
		assert(egg.id == eggId, `Config: EggTypes["{eggId}"].id ไม่ตรงกับคีย์ ({egg.id})`)
		assert(egg.hatchTime > 0, `Config: ไข่ "{eggId}" มี hatchTime <= 0`)
		assert(#egg.hatchTable > 0, `Config: ไข่ "{eggId}" ไม่มีตารางสุ่ม`)

		local total = 0
		for _, entry in egg.hatchTable do
			assert(
				UnitTypes[entry.unitId] ~= nil,
				`Config: ไข่ "{eggId}" อ้างถึงทหาร "{entry.unitId}" ที่ไม่มีใน UnitTypes`
			)
			assert(entry.weight > 0, `Config: ไข่ "{eggId}" → "{entry.unitId}" มี weight <= 0`)
			total += entry.weight
		end
		assert(total > 0, `Config: ไข่ "{eggId}" มีผลรวม weight เป็น 0`)
	end

	for unitId, unit in UnitTypes do
		assert(unit.id == unitId, `Config: UnitTypes["{unitId}"].id ไม่ตรงกับคีย์ ({unit.id})`)
		assert(unit.hp > 0, `Config: ทหาร "{unitId}" มี hp <= 0`)
	end

	assert(EggTypes[Config.DEFAULT_EGG_ID] ~= nil, "Config: DEFAULT_EGG_ID ชี้ไปที่ไข่ที่ไม่มีอยู่")
	assert(Config.Farm.MAX_PLOTS > 0, "Config: MAX_PLOTS ต้องมากกว่า 0")
	assert(Config.Farm.EGG_SLOTS_PER_PLAYER > 0, "Config: EGG_SLOTS_PER_PLAYER ต้องมากกว่า 0")

	----------------------------------------------------------------------------
	-- ตาราง tier น้ำหนัก
	----------------------------------------------------------------------------
	-- ข้อที่สำคัญที่สุดคือผลรวม weight ต้องเท่ากับ TIER_ROLL_MAX พอดี
	-- ถ้าน้อยกว่า จะมีช่วงเลขที่สุ่มออกมาแล้วไม่ตรงกับ tier ไหนเลย
	local tierTotal = 0
	local previousMax = 0

	for index, tier in WeightTiers do
		assert(tier.id == index, `Config: WeightTier ลำดับที่ {index} มี id = {tier.id} (ต้องตรงกับลำดับ)`)
		assert(tier.min > 0, `Config: tier {tier.id} มี min <= 0`)
		assert(tier.max >= tier.min, `Config: tier {tier.id} มี max < min`)
		assert(tier.min % 1 == 0 and tier.max % 1 == 0, `Config: tier {tier.id} ต้องเป็นจำนวนเต็ม`)
		assert(tier.weight > 0 and tier.weight % 1 == 0, `Config: tier {tier.id} มี weight ที่ไม่ใช่จำนวนเต็มบวก`)
		assert(tier.min > previousMax, `Config: tier {tier.id} ซ้อนทับกับ tier ก่อนหน้า`)
		previousMax = tier.max
		tierTotal += tier.weight
	end

	assert(
		tierTotal == Config.Weight.TIER_ROLL_MAX,
		`Config: ผลรวม weight ของ tier = {tierTotal} แต่ TIER_ROLL_MAX = {Config.Weight.TIER_ROLL_MAX} (ต้องเท่ากันพอดี)`
	)
	assert(Config.Weight.CHILD_RATIO > 0 and Config.Weight.CHILD_RATIO < 1, "Config: CHILD_RATIO ต้องอยู่ระหว่าง 0 กับ 1")

	----------------------------------------------------------------------------
	-- อัตราผลิต
	----------------------------------------------------------------------------
	local production = Config.Production
	assert(production.ONLINE_PER_MINUTE > 0, "Config: ONLINE_PER_MINUTE ต้องมากกว่า 0")
	assert(production.OFFLINE_PER_MINUTE > 0, "Config: OFFLINE_PER_MINUTE ต้องมากกว่า 0")
	assert(
		production.OFFLINE_PER_MINUTE <= production.ONLINE_PER_MINUTE,
		"Config: อัตราออฟไลน์ต้องไม่เร็วกว่าออนไลน์ ไม่งั้นผู้เล่นจะได้เปรียบตอนไม่เล่น"
	)
	assert(production.OFFLINE_CAP_SECONDS > 0, "Config: OFFLINE_CAP_SECONDS ต้องมากกว่า 0")
	assert(production.TICK_INTERVAL > 0, "Config: TICK_INTERVAL ต้องมากกว่า 0")
	assert(production.MAX_PER_SETTLE > 0, "Config: MAX_PER_SETTLE ต้องมากกว่า 0")

	----------------------------------------------------------------------------
	-- สถานะ + stack key
	----------------------------------------------------------------------------
	-- อักขระคั่นสองตัวต้องไม่ซ้ำกัน และ id สถานะต้องไม่มีอักขระคั่นปนอยู่
	-- ไม่งั้น parseStackKey จะแยกกลับผิด
	local fieldSep = Config.Stack.FIELD_SEPARATOR
	local statusSep = Config.Stack.STATUS_SEPARATOR
	assert(fieldSep ~= statusSep, "Config: FIELD_SEPARATOR กับ STATUS_SEPARATOR ต้องไม่เหมือนกัน")
	assert(#fieldSep == 1 and #statusSep == 1, "Config: อักขระคั่นต้องยาว 1 ตัวอักษร")

	local seenOrder: { [number]: boolean } = {}
	for statusId, status in Statuses do
		assert(status.id == statusId, `Config: Statuses["{statusId}"].id ไม่ตรงกับคีย์ ({status.id})`)
		assert(
			string.match(statusId, "^[a-z][a-z0-9_]*$") ~= nil,
			`Config: status id "{statusId}" ต้องเป็นตัวเล็ก a-z ขึ้นต้น ตามด้วย a-z 0-9 _ เท่านั้น`
		)
		assert(
			not string.find(statusId, fieldSep, 1, true) and not string.find(statusId, statusSep, 1, true),
			`Config: status id "{statusId}" มีอักขระคั่นของ stack key ปนอยู่`
		)
		assert(not seenOrder[status.order], `Config: status "{statusId}" มี order ซ้ำกับตัวอื่น`)
		seenOrder[status.order] = true
	end

	----------------------------------------------------------------------------
	-- สูตร damage
	----------------------------------------------------------------------------
	-- ยังไม่เลือกก็ไม่เป็นไร แต่ถ้าเลือกแล้วต้องชี้ไปที่สูตรที่มีอยู่จริง
	for formulaId, formula in DamageFormulas do
		assert(formula.id == formulaId, `Config: DamageFormulas["{formulaId}"].id ไม่ตรงกับคีย์`)
		assert(formula.baseDamage > 0, `Config: สูตร "{formulaId}" มี baseDamage <= 0`)
		assert(formula.referenceWeight > 0, `Config: สูตร "{formulaId}" มี referenceWeight <= 0`)
		assert(formula.minDamage >= 0, `Config: สูตร "{formulaId}" มี minDamage ติดลบ`)
		if formula.kind == "power" then
			assert(formula.exponent ~= nil, `Config: สูตร "{formulaId}" เป็นแบบ power แต่ไม่มี exponent`)
			assert((formula.exponent :: number) < 1, `Config: สูตร "{formulaId}" มี exponent >= 1 (ต้องถดถอย)`)
		else
			assert(formula.kind == "log", `Config: สูตร "{formulaId}" มี kind ที่ไม่รู้จัก ({formula.kind})`)
		end
	end

	local activeFormula = Damage.ACTIVE_FORMULA
	if activeFormula ~= nil then
		assert(DamageFormulas[activeFormula] ~= nil, `Config: ACTIVE_FORMULA = "{activeFormula}" ไม่มีอยู่ใน FORMULAS`)
	end

	----------------------------------------------------------------------------
	-- เพดานคลัง + ผู้เล่นใหม่
	----------------------------------------------------------------------------
	local inventory = Config.Inventory
	assert(inventory.MAX_MOTHERS > 0, "Config: MAX_MOTHERS ต้องมากกว่า 0")
	assert(inventory.MAX_CHILD_STACKS > 0, "Config: MAX_CHILD_STACKS ต้องมากกว่า 0")
	assert(inventory.MAX_TEAMS > 0, "Config: MAX_TEAMS ต้องมากกว่า 0")
	assert(
		inventory.MAX_TEAM_MOTHERS <= inventory.MAX_MOTHERS,
		"Config: MAX_TEAM_MOTHERS มากกว่าจำนวนแม่ที่ถือได้ทั้งหมด"
	)

	for eggId, amount in Config.NewPlayer.startingEggs do
		assert(EggTypes[eggId] ~= nil, `Config: NewPlayer.startingEggs อ้างถึงไข่ "{eggId}" ที่ไม่มีอยู่`)
		assert(amount > 0, `Config: NewPlayer.startingEggs["{eggId}"] ต้องมากกว่า 0`)
	end
	assert(Config.NewPlayer.coins >= 0 and Config.NewPlayer.gems >= 0, "Config: ของเริ่มต้นติดลบไม่ได้")

	----------------------------------------------------------------------------
	-- ความหายาก
	----------------------------------------------------------------------------
	-- ทุก rarity ที่ทหารใช้จริงต้องมีอยู่ในลิสต์ ไม่งั้น UI เรียงแล้วตกหล่น
	local knownRarity: { [string]: boolean } = {}
	for _, rarity in Rarities do
		knownRarity[rarity] = true
	end
	for unitId, unit in UnitTypes do
		assert(knownRarity[unit.rarity], `Config: ทหาร "{unitId}" มี rarity "{unit.rarity}" ที่ไม่มีใน Config.Rarities`)
	end

	----------------------------------------------------------------------------
	-- DataStore
	----------------------------------------------------------------------------
	-- key เต็มยาวได้ไม่เกิน 50 ตัวอักษร UserId ยาวสุดที่เป็นไปได้ตอนนี้ ~10 หลัก
	assert(#Config.DataStore.KEY_PREFIX + 20 <= 50, "Config: KEY_PREFIX ยาวเกินไป เสี่ยงชนลิมิต 50 ตัวอักษรของ DataStore key")
	assert(Config.DataStore.AUTOSAVE_INTERVAL >= 10, "Config: AUTOSAVE_INTERVAL ถี่เกินไป เสี่ยงโดน throttle")
	assert(Config.SCHEMA_VERSION >= 1 and Config.SCHEMA_VERSION % 1 == 0, "Config: SCHEMA_VERSION ต้องเป็นจำนวนเต็มตั้งแต่ 1")
end

return Config
