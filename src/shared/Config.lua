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

-- คลาสของตัวละคร (SS/S/A/B/C) — ตัวคูณใช้กับทั้ง damage และ HP
export type CharacterClass = {
	id: string,
	multiplier: number, -- ตัวคูณ damage/HP ของตัวละครคลาสนี้
	order: number, -- ลำดับแสดงผล 1 = เก่งสุด
}

-- ตัวละคร 1 ตัว (แทนที่ UnitTypes เดิมตั้งแต่ Phase 2 เป็นต้นไป)
export type Character = {
	id: string, -- ⚠️ ฝังอยู่ใน stack key ที่เซฟลง DataStore ห้ามเปลี่ยน
	name: string, -- ชื่อไทยสำหรับ UI
	class: string, -- คีย์ใน Config.CharacterClasses
	enabled: boolean,
}

-- หนึ่งแถวในตารางสุ่มคลาสของไข่
export type ClassChance = {
	class: string,
	weight: number,
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

	-- upgrade อัตราผลิต: 10 ขั้น ราคาโต ×10 แต่ผลโต ×3
	--
	-- ทำไมผลเป็น ×3 ไม่ใช่ ×10 ทั้งที่ราคาเป็น ×10:
	-- ถ้าผลเป็น ×10 ด้วย อัตราผลิตรวมจะโต ×10^10 ซึ่งแรงกว่าความยากของด่าน
	-- (ที่โต ×10^8) ทำให้ตั้งแต่ด่าน 5 ขึ้นไปสะสมกองทัพเสร็จทันที กำแพงหมดความหมาย
	-- ที่ ×3 กองทัพยังต้องใช้เวลาสะสมจริงทุกด่าน (ไม่กี่ชั่วโมงถึงหนึ่งวัน)
	-- การที่จ่ายแพงขึ้นแต่ได้ผลน้อยกว่ายังทำให้ผู้เล่นต้องเลือกว่าจะอัปอะไรก่อน
	UPGRADE_MAX_LEVEL = 10,
	UPGRADE_BASE_COST = 1000,
	UPGRADE_COST_MULTIPLIER = 10,
	UPGRADE_RATE_MULTIPLIER = 3,
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
-- รูปแบบ:  "<ตัวละคร>|<น้ำหนักแม่>|<สถานะเรียงแล้ว คั่นด้วยจุลภาค>"
--   ไม่มีสถานะ   → "wukong|1500|"
--   สถานะเดียว   → "wukong|1500|gold"
--   หลายสถานะ    → "wukong|1500|gold,silver"
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
-- ใช้สูตรเดียวกันทั้ง damage และ HP: **HP ของตัวเรา = damage ของตัวเรา**
-- (ทั้งแม่และลูก) ตัวคูณคลาสของตัวละครคูณทั้งสองค่าพร้อมกัน
--
-- ตารางเปรียบเทียบ 3 สูตรที่เคยพิจารณาอยู่ใน docs/data-schema.md
-- เก็บอีก 2 สูตรไว้เพื่อให้สลับกลับได้โดยไม่ต้องหาตัวเลขใหม่
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
	-- เลือกแล้ว: รากที่สอง (ช่วงพลังทั้งเกม ×1,000 · ลูกแรง 10% ของแม่คงที่ทุกน้ำหนัก)
	ACTIVE_FORMULA = "sqrt",
	FORMULAS = DamageFormulas,
}

Config.Damage = Damage

--------------------------------------------------------------------------------
-- เพดานคลัง
--------------------------------------------------------------------------------
-- ตัวเลขพวกนี้เป็นข้อเสนอ รอยืนยัน — มีไว้กันข้อมูลบวมและกัน exploit
-- ต้องมีตั้งแต่วันแรก เพราะ "เพิ่ม" เพดานทีหลังง่าย แต่ "ลด" ทีหลังแปลว่าต้องยึดของผู้เล่น

Config.Inventory = {
	-- จำนวนแม่ทั้งหมดที่ถือได้ = Config.Bag.CAPACITY + ความจุคอกตามเลเวล
	-- (ค่าสองตัวนั้นเป็นแหล่งความจริง ตัวนี้เป็นเพดานกันพลาดอีกชั้น)
	MAX_MOTHERS = 200,

	-- จำนวน "กอง" ไม่ใช่จำนวนลูก
	-- กองแตกตาม (ตัวละคร 12 × น้ำหนักแม่ × ชุดสถานะ) จึงต้องเผื่อไว้เยอะกว่าเดิม
	MAX_CHILD_STACKS = 2000,

	-- ⚠️ ที่ด่าน 9 อัตราผลิตเต็ม ผู้เล่นผลิตลูกได้ระดับแสนล้านตัวต่อวัน
	-- ค่าเดิม 1e9 ล้นแน่นอน ตั้งที่ 1e15 เพราะ Luau เก็บจำนวนเต็มแม่นยำถึง 9e15
	MAX_CHILDREN_PER_STACK = 1000000000000000,

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
-- ตัวละคร
--------------------------------------------------------------------------------
-- ⚠️ โครงหลัก: id ของตัวละครฝังอยู่ใน stack key ของกองลูกที่เซฟลง DataStore
-- เปลี่ยน id เมื่อไหร่ = กองลูกของผู้เล่นทุกคนอ่านไม่ออก
--
-- คลาสเป็นตัวคูณ damage และ HP (HP = damage ตามที่ตกลงกัน)
-- คลาสไม่มีผลต่อรายได้เงิน — เงินคิดจากน้ำหนักแม่กับด่านเท่านั้น

local CharacterClasses: { [string]: CharacterClass } = {
	SS = { id = "SS", multiplier = 5, order = 1 },
	S = { id = "S", multiplier = 3, order = 2 },
	A = { id = "A", multiplier = 2, order = 3 },
	B = { id = "B", multiplier = 1.5, order = 4 },
	C = { id = "C", multiplier = 1, order = 5 },
}

Config.CharacterClasses = CharacterClasses

local Characters: { [string]: Character } = {
	-- SS ×5
	yulai = { id = "yulai", name = "องค์ยูไล", class = "SS", enabled = true },

	-- S ×3
	guanyin = { id = "guanyin", name = "พระแม่กวนอิม", class = "S", enabled = true },
	jade_emperor = { id = "jade_emperor", name = "เง็กเซียนฮ่องเต้", class = "S", enabled = true },

	-- A ×2
	tang = { id = "tang", name = "พระถังซัมจั๋ง", class = "A", enabled = true },
	wukong = { id = "wukong", name = "ซุนหงอคง", class = "A", enabled = true },

	-- B ×1.5
	bajie = { id = "bajie", name = "ตือโป๊ยก่าย", class = "B", enabled = true },
	wujing = { id = "wujing", name = "ซัวเจ๋ง", class = "B", enabled = true },
	dragon_horse = { id = "dragon_horse", name = "ม้าขาวมังกร", class = "B", enabled = true },

	-- C ×1
	monkey = { id = "monkey", name = "ลิง", class = "C", enabled = true },
	pig = { id = "pig", name = "หมู", class = "C", enabled = true },
	horse = { id = "horse", name = "ม้า", class = "C", enabled = true },
	fish = { id = "fish", name = "ปลา", class = "C", enabled = true },
}

Config.Characters = Characters

--------------------------------------------------------------------------------
-- ไข่ชนิดไหนออกตัวละครคลาสไหนได้
--------------------------------------------------------------------------------
-- ไข่ทุกชนิดใช้ "ตาราง tier น้ำหนักชุดเดียวกัน" (Config.Weight.TIERS)
-- ความต่างของไข่อยู่ที่คลาสตัวละครที่ออกได้ ซึ่งเป็นตัวคูณ damage/HP โดยตรง
--
-- ตามที่ตกลง: ไข่ธรรมดาไม่มี S/SS · ไข่หายากตัด C ออกและไม่มี S/SS ·
-- ไข่ตำนานตัด C ออกและเพิ่ม S/SS
--
-- weight เป็นจำนวนเต็มต่อ 10,000 (validate() บังคับผลรวมให้เท่ากับ CLASS_ROLL_MAX)
-- สุ่ม 2 ขั้นเหมือนน้ำหนัก: สุ่มคลาสก่อน แล้วค่อยสุ่มตัวละครในคลาสนั้นแบบเท่า ๆ กัน

Config.CLASS_ROLL_MAX = 10000

local EggCharacterPools: { [string]: { ClassChance } } = {
	egg_common = {
		{ class = "C", weight = 8000 }, -- 80%
		{ class = "B", weight = 1800 }, -- 18%
		{ class = "A", weight = 200 }, -- 2%
	},
	egg_rare = {
		{ class = "B", weight = 8000 }, -- 80%
		{ class = "A", weight = 2000 }, -- 20%
	},
	egg_legendary = {
		{ class = "B", weight = 5000 }, -- 50%
		{ class = "A", weight = 4000 }, -- 40%
		{ class = "S", weight = 950 }, -- 9.5%
		{ class = "SS", weight = 50 }, -- 0.5%
	},
}

Config.EggCharacterPools = EggCharacterPools

--------------------------------------------------------------------------------
-- เศรษฐกิจ (เงิน)
--------------------------------------------------------------------------------
-- เงินมาจาก "แม่ที่วางในคอก" เท่านั้น แม่ในกระเป๋าไม่ผลิตอะไรเลย
--
-- สูตร:  coins/นาที = BASE_PER_MINUTE × (น้ำหนักแม่ / REFERENCE_WEIGHT)^EXPONENT
--                     × STAGE_MULTIPLIER ^ (ด่านที่พังกำแพงแล้ว - 1)
--
-- ⚠️ ตัวคูณตามด่านคือหัวใจของเศรษฐกิจเกมนี้ ห้ามตัดทิ้ง
-- เหตุผล: ราคาของทุกอย่าง (คอก อาวุธ อัตราผลิต) โต ×10 ต่อขั้น
-- แต่รายได้จากน้ำหนักโตแค่ ×1,000 ตลอดเกม (เพราะ sqrt บีบไว้)
-- และคอกเพิ่มความจุทีละ 1 ตัว (+6% ถึง +20% ต่อเลเวล)
-- ถ้าไม่มีตัวคูณตามด่าน ผู้เล่นจะซื้อของขั้นกลาง ๆ ขึ้นไปไม่ได้เลย
-- ไม่ว่าจะดันค่าเริ่มต้นขึ้นเท่าไหร่ก็ตาม (คูณค่าเริ่มต้นแค่ "เลื่อน" กำแพง ไม่ได้ลบกำแพง)

Config.Economy = {
	BASE_PER_MINUTE = 1, -- แม่น้ำหนัก REFERENCE_WEIGHT ที่ด่าน 1 ได้กี่ coins/นาที
	REFERENCE_WEIGHT = 100,
	EXPONENT = 0.5, -- ถดถอยแบบรากที่สอง (ชุดเดียวกับสูตร damage)
	STAGE_MULTIPLIER = 10, -- ตัวคูณเงินต่อ 1 ด่านที่พังกำแพงได้

	-- ราคาขายแม่ = รายได้ของแม่ตัวนั้นคูณจำนวนนาทีนี้
	-- ผูกกับสูตรเงินอัตโนมัติ ไม่ต้องตั้งตารางแยก
	SELL_MOTHER_MINUTES = 30,
}

--------------------------------------------------------------------------------
-- คอก (Pen) — ที่วางแม่ให้ผลิตลูกและผลิตเงิน
--------------------------------------------------------------------------------
-- ความจุ = BASE_CAPACITY + (level - 1)   →  Lv1 = 5 ตัว, Lv15 = 19 ตัว
-- ค่าอัปเกรด Lv N → N+1 = UPGRADE_BASE_COST × UPGRADE_COST_MULTIPLIER ^ (N-1)

Config.Pen = {
	BASE_CAPACITY = 5,
	CAPACITY_PER_LEVEL = 1,
	MAX_LEVEL = 15,
	UPGRADE_BASE_COST = 1000,
	UPGRADE_COST_MULTIPLIER = 10,
}

--------------------------------------------------------------------------------
-- กระเป๋า (Bag) — ที่เก็บแม่ที่ไม่ได้วาง ไม่ผลิตอะไรเลย
--------------------------------------------------------------------------------
-- นับแยกจากคอก: ถือได้รวมสูงสุด CAPACITY + ความจุคอก

Config.Bag = {
	CAPACITY = 100,
}

--------------------------------------------------------------------------------
-- สวนฟักไข่ (Hatchery)
--------------------------------------------------------------------------------
-- ไข่ที่แย่งมาจากรังบอสเอามาฟักที่นี่ ฟักพร้อมกันได้สูงสุด MAX_EGGS ฟอง
-- เต็มแล้วหยิบไข่เพิ่มไม่ได้ ต้องแจ้งเตือนผู้เล่น

Config.Hatchery = {
	MAX_EGGS = 50,
}

--------------------------------------------------------------------------------
-- ด่านและกำแพง
--------------------------------------------------------------------------------
-- แมพเป็นเส้นตรง มี STAGE_COUNT ด่าน กำแพงเป็นของแต่ละผู้เล่นแยกกัน
-- พังแล้วเปิดถาวรสำหรับคนนั้น (เก็บใน PlayerData ไม่ใช่ per-server)
--
-- ทหารฝ่ายรับด่าน N = DEFENDER_BASE × DEFENDER_MULTIPLIER ^ (N-1)
--   ด่าน 1 = 10 ตัว ... ด่าน 9 = 1,000,000,000 ตัว
--
-- ⚠️ performance: ห้าม spawn ทหารเป็น Model จริงทั้งหมด
-- เก็บเป็น "HP รวม" ค่าเดียว แล้วแสดงโมเดลประกอบ DISPLAY_MODELS_MIN..MAX ตัว
-- ที่ค่อย ๆ หายไปตามสัดส่วน HP ที่ลดลง (ดู Config.getDisplayModelCount)

Config.Stage = {
	COUNT = 9,

	DEFENDER_BASE = 10, -- จำนวนทหารฝ่ายรับด่าน 1
	DEFENDER_MULTIPLIER = 10, -- คูณต่อด่าน
	DEFENDER_HP = 100, -- HP ต่อทหารฝ่ายรับ 1 ตัว
	DEFENDER_DAMAGE = 10, -- damage ที่ทหารฝ่ายรับ 1 ตัวตีกลับใส่กองทัพเรา

	WALL_HP_RATIO = 0.5, -- HP กำแพง = สัดส่วนนี้ของ HP ทหารรวมในด่านนั้น

	-- ลำดับการตี: ทหารฝ่ายรับหมดก่อน แล้วค่อยตีกำแพงได้
	SEQUENTIAL_TARGETING = true,

	DISPLAY_MODELS_MIN = 20, -- จำนวนโมเดลที่แสดงตอน HP เหลือน้อยสุด (แต่ยังไม่หมด)
	DISPLAY_MODELS_MAX = 50, -- จำนวนโมเดลที่แสดงตอน HP เต็ม
}

--------------------------------------------------------------------------------
-- บอสและการแย่งไข่
--------------------------------------------------------------------------------
-- บอสอยู่ในพื้นที่รังของแต่ละด่าน ใช้ร่วมกันทั้งเซิร์ฟเวอร์
-- แต่เข้าได้เฉพาะคนที่พังกำแพงถึงด่านนั้นแล้ว
--
-- ⚠️ server เป็นคนตัดสินเจ้าของไข่เท่านั้น ห้าม client ตัดสินเด็ดขาด

Config.Boss = {
	RESPAWN_SECONDS = 300, -- รีเกิดทุก 5 นาที
	EGGS_PER_SPAWN = 5, -- ไข่ที่วางในรังตอนบอสเกิด
	EGG_GRAB_HOLD_SECONDS = 3, -- กดค้างกี่วินาทีถึงจะได้ไข่ (โดนตีแล้วนับใหม่)

	HP_BASE = 100, -- HP บอสด่าน 1
	HP_MULTIPLIER = 10, -- คูณต่อด่าน
}

--------------------------------------------------------------------------------
-- อาวุธของผู้เล่น (ใช้ตีบอส ไม่เกี่ยวกับกองทัพ)
--------------------------------------------------------------------------------
-- damage ขั้น N = DAMAGE_BASE × DAMAGE_MULTIPLIER ^ (N-1)
-- ราคาขั้น N → N+1 = UPGRADE_BASE_COST × UPGRADE_COST_MULTIPLIER ^ (N-1)
--
-- สเกลนี้ตั้งใจให้ "อาวุธขั้น N ตีบอสด่าน N ตายใน 10 ครั้งพอดี" ทุกด่าน
-- (HP บอส 100×10^(N-1) ÷ damage 10×10^(N-1) = 10 เสมอ)
-- ห้ามแก้ DAMAGE_BASE หรือ HP_BASE ของบอสข้างเดียว ไม่งั้นความรู้สึกจะเพี้ยนทั้งเกม

Config.Weapon = {
	MAX_LEVEL = 10,
	DAMAGE_BASE = 10,
	DAMAGE_MULTIPLIER = 10,
	UPGRADE_BASE_COST = 1000,
	UPGRADE_COST_MULTIPLIER = 10,
}

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

-- charId       = ตัวละครของแม่ (Config.Characters)
-- motherWeight = น้ำหนัก "แม่" จำนวนเต็ม ไม่ใช่น้ำหนักลูกซึ่งเป็นทศนิยม
function Config.makeStackKey(charId: string, motherWeight: number, statuses: { string }?): string
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

	local sep = Config.Stack.FIELD_SEPARATOR
	return charId
		.. sep
		.. string.format("%d", motherWeight)
		.. sep
		.. table.concat(unique, Config.Stack.STATUS_SEPARATOR)
end

-- แยก stack key กลับเป็น (ตัวละคร, น้ำหนักแม่, รายการสถานะ)
-- คืน nil เป็นค่าแรกถ้า key ผิดรูป — ผู้เรียกต้องเช็ค
function Config.parseStackKey(key: string): (string?, number?, { string })
	local sep = Config.Stack.FIELD_SEPARATOR

	local firstAt = string.find(key, sep, 1, true)
	if not firstAt then
		return nil, nil, {}
	end
	local secondAt = string.find(key, sep, firstAt + 1, true)
	if not secondAt then
		return nil, nil, {}
	end

	local charId = string.sub(key, 1, firstAt - 1)
	local motherWeight = tonumber(string.sub(key, firstAt + 1, secondAt - 1))
	local rest = string.sub(key, secondAt + 1)

	if charId == "" or motherWeight == nil then
		return nil, nil, {}
	end

	local statuses: { string } = {}
	if rest ~= "" then
		for id in string.gmatch(rest, "[^" .. Config.Stack.STATUS_SEPARATOR .. "]+") do
			table.insert(statuses, id)
		end
	end

	return charId, motherWeight, statuses
end

--------------------------------------------------------------------------------
-- ตัวละครและคลาส
--------------------------------------------------------------------------------

function Config.getCharacter(charId: string): Character?
	return Characters[charId]
end

function Config.getCharacterClass(classId: string): CharacterClass?
	return CharacterClasses[classId]
end

-- ตัวคูณ damage/HP ของตัวละคร คืน 1 ถ้าหาไม่เจอ (ปลอดภัยกว่าพัง)
function Config.getCharacterMultiplier(charId: string): number
	local character = Characters[charId]
	if not character then
		return 1
	end
	local class = CharacterClasses[character.class]
	return if class then class.multiplier else 1
end

-- สุ่มตัวละครจากไข่: สุ่มคลาสตามน้ำหนักก่อน แล้วค่อยสุ่มตัวในคลาสนั้นแบบเท่า ๆ กัน
-- คืน nil ถ้า eggId ไม่มีตารางคลาส (ผู้เรียกต้องเช็ค)
function Config.rollCharacter(eggId: string, rng: Random): string?
	local pool = EggCharacterPools[eggId]
	if not pool then
		return nil
	end

	-- ขั้น 1: สุ่มคลาส
	local roll = rng:NextInteger(1, Config.CLASS_ROLL_MAX)
	local acc = 0
	local chosenClass: string? = nil
	for _, entry in pool do
		acc += entry.weight
		if roll <= acc then
			chosenClass = entry.class
			break
		end
	end
	if not chosenClass then
		chosenClass = pool[#pool].class
	end

	-- ขั้น 2: สุ่มตัวละครในคลาสนั้น
	-- เรียง id ก่อนเพื่อให้ลำดับคงที่ ผลการสุ่มด้วย seed เดิมจะได้ซ้ำได้ตอนเทสต์
	local candidates: { string } = {}
	for charId, character in Characters do
		if character.class == chosenClass and character.enabled then
			table.insert(candidates, charId)
		end
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates)

	return candidates[rng:NextInteger(1, #candidates)]
end

--------------------------------------------------------------------------------
-- damage และ HP
--------------------------------------------------------------------------------
-- HP ของตัวเรา = damage ของตัวเรา (ตกลงกันไว้แบบนั้น) จึงใช้ฟังก์ชันเดียวกัน
-- ใช้ได้ทั้งกับแม่ (ส่งน้ำหนักแม่) และลูก (ส่งน้ำหนักลูก = 1% ของแม่)

function Config.computePower(weight: number, charId: string?): number
	local formula = Config.getActiveDamageFormula()
	if not formula then
		return 0
	end

	local ratio = weight / formula.referenceWeight
	local value: number

	if formula.kind == "power" then
		value = formula.baseDamage * ratio ^ (formula.exponent :: number)
	else
		value = formula.baseDamage * (1 + math.log10(ratio))
	end

	if charId then
		value *= Config.getCharacterMultiplier(charId)
	end

	return math.max(formula.minDamage, value)
end

--------------------------------------------------------------------------------
-- คอก / กระเป๋า
--------------------------------------------------------------------------------

function Config.getPenCapacity(level: number): number
	local clamped = math.clamp(math.floor(level), 1, Config.Pen.MAX_LEVEL)
	return Config.Pen.BASE_CAPACITY + (clamped - 1) * Config.Pen.CAPACITY_PER_LEVEL
end

-- ราคาอัปเกรดจาก level → level+1 คืน nil ถ้าเต็มเลเวลแล้ว
function Config.getPenUpgradeCost(level: number): number?
	if level >= Config.Pen.MAX_LEVEL then
		return nil
	end
	return Config.Pen.UPGRADE_BASE_COST * Config.Pen.UPGRADE_COST_MULTIPLIER ^ (level - 1)
end

--------------------------------------------------------------------------------
-- อาวุธ
--------------------------------------------------------------------------------

function Config.getWeaponDamage(level: number): number
	local clamped = math.clamp(math.floor(level), 1, Config.Weapon.MAX_LEVEL)
	return Config.Weapon.DAMAGE_BASE * Config.Weapon.DAMAGE_MULTIPLIER ^ (clamped - 1)
end

function Config.getWeaponUpgradeCost(level: number): number?
	if level >= Config.Weapon.MAX_LEVEL then
		return nil
	end
	return Config.Weapon.UPGRADE_BASE_COST * Config.Weapon.UPGRADE_COST_MULTIPLIER ^ (level - 1)
end

--------------------------------------------------------------------------------
-- อัตราผลิตลูก
--------------------------------------------------------------------------------
-- level 0 = ยังไม่อัป (×1) ถึง UPGRADE_MAX_LEVEL

function Config.getProductionMultiplier(level: number): number
	local clamped = math.clamp(math.floor(level), 0, Config.Production.UPGRADE_MAX_LEVEL)
	return Config.Production.UPGRADE_RATE_MULTIPLIER ^ clamped
end

function Config.getProductionUpgradeCost(level: number): number?
	if level >= Config.Production.UPGRADE_MAX_LEVEL then
		return nil
	end
	return Config.Production.UPGRADE_BASE_COST * Config.Production.UPGRADE_COST_MULTIPLIER ^ level
end

--------------------------------------------------------------------------------
-- ด่าน กำแพง บอส
--------------------------------------------------------------------------------

function Config.getStageDefenderCount(stage: number): number
	local clamped = math.clamp(math.floor(stage), 1, Config.Stage.COUNT)
	return Config.Stage.DEFENDER_BASE * Config.Stage.DEFENDER_MULTIPLIER ^ (clamped - 1)
end

function Config.getStageDefenderHp(stage: number): number
	return Config.getStageDefenderCount(stage) * Config.Stage.DEFENDER_HP
end

function Config.getStageWallHp(stage: number): number
	return Config.getStageDefenderHp(stage) * Config.Stage.WALL_HP_RATIO
end

-- damage ที่กองทัพต้องทำรวมทั้งหมดเพื่อผ่านด่านนี้ (ทหาร + กำแพง)
function Config.getStageTotalHp(stage: number): number
	return Config.getStageDefenderHp(stage) + Config.getStageWallHp(stage)
end

function Config.getBossHp(stage: number): number
	local clamped = math.clamp(math.floor(stage), 1, Config.Stage.COUNT)
	return Config.Boss.HP_BASE * Config.Boss.HP_MULTIPLIER ^ (clamped - 1)
end

-- แปลงสัดส่วน HP ที่เหลือ → จำนวนโมเดลทหารที่ควรแสดงในแมพ
-- HP เต็ม  → DISPLAY_MODELS_MAX ตัว
-- HP หมด   → 0 ตัว
-- ระหว่างนั้นไล่ลงเป็นเส้นตรง แต่ตราบใดที่ยังมี HP เหลือจะไม่ต่ำกว่า DISPLAY_MODELS_MIN
-- เพื่อไม่ให้ด่านดูว่างเปล่าทั้งที่ยังตีไม่จบ
function Config.getDisplayModelCount(hpRatio: number): number
	local ratio = math.clamp(hpRatio, 0, 1)
	if ratio <= 0 then
		return 0
	end

	local min = Config.Stage.DISPLAY_MODELS_MIN
	local max = Config.Stage.DISPLAY_MODELS_MAX
	return math.max(min, math.ceil(max * ratio))
end

--------------------------------------------------------------------------------
-- เงิน
--------------------------------------------------------------------------------
-- stage = ด่านสูงสุดที่ผู้เล่นพังกำแพงได้แล้ว (เริ่มที่ 1)
-- แม่ในกระเป๋าไม่ผลิตเงิน ผู้เรียกต้องกรองเอาเฉพาะแม่ในคอกก่อนเรียกฟังก์ชันนี้

function Config.getCoinsPerMinute(motherWeight: number, stage: number): number
	local economy = Config.Economy
	local clampedStage = math.clamp(math.floor(stage), 1, Config.Stage.COUNT)

	local byWeight = economy.BASE_PER_MINUTE * (motherWeight / economy.REFERENCE_WEIGHT) ^ economy.EXPONENT
	local byStage = economy.STAGE_MULTIPLIER ^ (clampedStage - 1)

	return byWeight * byStage
end

-- ราคาขายแม่ = รายได้ของแม่ตัวนั้น × SELL_MOTHER_MINUTES
function Config.getMotherSellPrice(motherWeight: number, stage: number): number
	return math.floor(Config.getCoinsPerMinute(motherWeight, stage) * Config.Economy.SELL_MOTHER_MINUTES)
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

	----------------------------------------------------------------------------
	-- ตัวละครและคลาส
	----------------------------------------------------------------------------
	local seenClassOrder: { [number]: boolean } = {}
	for classId, class in CharacterClasses do
		assert(class.id == classId, `Config: CharacterClasses["{classId}"].id ไม่ตรงกับคีย์`)
		assert(class.multiplier > 0, `Config: คลาส "{classId}" มีตัวคูณ <= 0`)
		assert(not seenClassOrder[class.order], `Config: คลาส "{classId}" มี order ซ้ำ`)
		seenClassOrder[class.order] = true
	end

	local classHasCharacter: { [string]: boolean } = {}
	for charId, character in Characters do
		assert(character.id == charId, `Config: Characters["{charId}"].id ไม่ตรงกับคีย์ ({character.id})`)
		assert(
			string.match(charId, "^[a-z][a-z0-9_]*$") ~= nil,
			`Config: character id "{charId}" ต้องเป็นตัวเล็ก a-z ขึ้นต้น ตามด้วย a-z 0-9 _ เท่านั้น`
		)
		-- id อยู่ใน stack key จึงห้ามมีอักขระคั่นปนอยู่
		assert(
			not string.find(charId, fieldSep, 1, true) and not string.find(charId, statusSep, 1, true),
			`Config: character id "{charId}" มีอักขระคั่นของ stack key ปนอยู่`
		)
		assert(
			CharacterClasses[character.class] ~= nil,
			`Config: ตัวละคร "{charId}" อยู่คลาส "{character.class}" ที่ไม่มีอยู่`
		)
		if character.enabled then
			classHasCharacter[character.class] = true
		end
	end

	----------------------------------------------------------------------------
	-- ตารางคลาสของไข่
	----------------------------------------------------------------------------
	for eggId, pool in EggCharacterPools do
		assert(EggTypes[eggId] ~= nil, `Config: EggCharacterPools อ้างถึงไข่ "{eggId}" ที่ไม่มีอยู่`)
		assert(#pool > 0, `Config: ไข่ "{eggId}" ไม่มีตารางคลาส`)

		local classTotal = 0
		for _, entry in pool do
			assert(
				CharacterClasses[entry.class] ~= nil,
				`Config: ไข่ "{eggId}" อ้างถึงคลาส "{entry.class}" ที่ไม่มีอยู่`
			)
			assert(
				classHasCharacter[entry.class],
				`Config: ไข่ "{eggId}" สุ่มคลาส "{entry.class}" ได้ แต่ไม่มีตัวละครที่ enabled ในคลาสนั้นเลย`
			)
			assert(entry.weight > 0 and entry.weight % 1 == 0, `Config: ไข่ "{eggId}" คลาส "{entry.class}" มี weight ที่ไม่ใช่จำนวนเต็มบวก`)
			classTotal += entry.weight
		end
		assert(
			classTotal == Config.CLASS_ROLL_MAX,
			`Config: ไข่ "{eggId}" มีผลรวม weight คลาส = {classTotal} แต่ CLASS_ROLL_MAX = {Config.CLASS_ROLL_MAX}`
		)
	end

	for eggId in EggTypes do
		assert(EggCharacterPools[eggId] ~= nil, `Config: ไข่ "{eggId}" ยังไม่มีตารางคลาสใน EggCharacterPools`)
	end

	----------------------------------------------------------------------------
	-- เศรษฐกิจ คอก กระเป๋า สวนฟัก
	----------------------------------------------------------------------------
	local economy = Config.Economy
	assert(economy.BASE_PER_MINUTE > 0, "Config: BASE_PER_MINUTE ต้องมากกว่า 0")
	assert(economy.REFERENCE_WEIGHT > 0, "Config: REFERENCE_WEIGHT ต้องมากกว่า 0")
	assert(economy.EXPONENT > 0 and economy.EXPONENT < 1, "Config: EXPONENT ของเงินต้องอยู่ระหว่าง 0 กับ 1 (ต้องถดถอย)")
	assert(
		economy.STAGE_MULTIPLIER >= Config.Stage.DEFENDER_MULTIPLIER,
		"Config: ตัวคูณเงินต่อด่านต้องไม่น้อยกว่าอัตราที่ด่านยากขึ้น ไม่งั้นผู้เล่นจะซื้อของขั้นสูงไม่ได้"
	)
	assert(economy.SELL_MOTHER_MINUTES > 0, "Config: SELL_MOTHER_MINUTES ต้องมากกว่า 0")

	assert(Config.Pen.BASE_CAPACITY > 0, "Config: BASE_CAPACITY ของคอกต้องมากกว่า 0")
	assert(Config.Pen.MAX_LEVEL >= 1, "Config: MAX_LEVEL ของคอกต้องอย่างน้อย 1")
	assert(Config.Pen.UPGRADE_COST_MULTIPLIER > 1, "Config: ตัวคูณราคาคอกต้องมากกว่า 1")
	assert(Config.Bag.CAPACITY > 0, "Config: ความจุกระเป๋าต้องมากกว่า 0")
	assert(Config.Hatchery.MAX_EGGS > 0, "Config: MAX_EGGS ของสวนฟักต้องมากกว่า 0")
	assert(
		Config.Inventory.MAX_MOTHERS >= Config.Bag.CAPACITY + Config.getPenCapacity(Config.Pen.MAX_LEVEL),
		"Config: MAX_MOTHERS น้อยกว่ากระเป๋า + คอกเต็มเลเวล ผู้เล่นจะเก็บของที่ควรเก็บได้ไม่ครบ"
	)

	----------------------------------------------------------------------------
	-- ด่าน บอส อาวุธ
	----------------------------------------------------------------------------
	local stage = Config.Stage
	assert(stage.COUNT > 0, "Config: จำนวนด่านต้องมากกว่า 0")
	assert(stage.DEFENDER_BASE > 0 and stage.DEFENDER_MULTIPLIER > 1, "Config: ค่าทหารฝ่ายรับไม่ถูกต้อง")
	assert(stage.DEFENDER_HP > 0 and stage.DEFENDER_DAMAGE > 0, "Config: HP/damage ของทหารฝ่ายรับต้องมากกว่า 0")
	assert(stage.WALL_HP_RATIO > 0, "Config: WALL_HP_RATIO ต้องมากกว่า 0")
	assert(
		stage.DISPLAY_MODELS_MIN > 0 and stage.DISPLAY_MODELS_MIN <= stage.DISPLAY_MODELS_MAX,
		"Config: ช่วงจำนวนโมเดลที่แสดงไม่ถูกต้อง"
	)

	assert(Config.Boss.RESPAWN_SECONDS > 0, "Config: เวลารีเกิดบอสต้องมากกว่า 0")
	assert(Config.Boss.EGGS_PER_SPAWN > 0, "Config: จำนวนไข่ต่อรอบต้องมากกว่า 0")
	assert(Config.Boss.EGG_GRAB_HOLD_SECONDS > 0, "Config: เวลากดค้างหยิบไข่ต้องมากกว่า 0")

	-- สเกลที่ทำให้ "อาวุธขั้น N ตีบอสด่าน N ตายในจำนวนครั้งเท่ากันทุกด่าน"
	-- ถ้าตัวคูณสองตัวนี้ไม่เท่ากัน ความรู้สึกตอนสู้บอสจะเพี้ยนไปเรื่อย ๆ ตามด่าน
	assert(
		Config.Weapon.DAMAGE_MULTIPLIER == Config.Boss.HP_MULTIPLIER,
		"Config: ตัวคูณ damage อาวุธกับตัวคูณ HP บอสต้องเท่ากัน ไม่งั้นจำนวนครั้งที่ตีบอสจะเพี้ยนตามด่าน"
	)
	assert(Config.Weapon.MAX_LEVEL >= stage.COUNT, "Config: ขั้นอาวุธต้องมีอย่างน้อยเท่าจำนวนด่าน")

	----------------------------------------------------------------------------
	-- upgrade อัตราผลิต
	----------------------------------------------------------------------------
	assert(production.UPGRADE_MAX_LEVEL > 0, "Config: UPGRADE_MAX_LEVEL ของอัตราผลิตต้องมากกว่า 0")
	assert(production.UPGRADE_RATE_MULTIPLIER > 1, "Config: UPGRADE_RATE_MULTIPLIER ต้องมากกว่า 1")
	assert(
		production.UPGRADE_RATE_MULTIPLIER <= production.UPGRADE_COST_MULTIPLIER,
		"Config: ผลของ upgrade ต่อขั้นไม่ควรมากกว่าราคาที่จ่ายต่อขั้น ไม่งั้นกำแพงจะหมดความหมายช่วงท้ายเกม"
	)
	assert(Config.DataStore.AUTOSAVE_INTERVAL >= 10, "Config: AUTOSAVE_INTERVAL ถี่เกินไป เสี่ยงโดน throttle")
	assert(Config.SCHEMA_VERSION >= 1 and Config.SCHEMA_VERSION % 1 == 0, "Config: SCHEMA_VERSION ต้องเป็นจำนวนเต็มตั้งแต่ 1")
end

return Config
