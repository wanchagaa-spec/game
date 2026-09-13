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
	color: Color3, -- สีของก้อนไข่ตอนวางในฟาร์ม (ชั่วคราว ไว้ดูด้วยตาตอนเทสต์)
	hatchTable: { HatchEntry }, -- ตารางน้ำหนักการสุ่มว่าฟักแล้วออกทหารตัวไหน
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
-- ทหาร
--------------------------------------------------------------------------------
-- ตัวเลข hp/damage/speed ยังไม่ได้ balance จริง ใช้เป็นตุ๊กตาไปก่อนจนถึง Phase 3

local UnitTypes: { [string]: UnitType } = {
	recruit = {
		id = "recruit",
		name = "พลทหารฝึกหัด",
		rarity = "Common",
		hp = 100,
		damage = 10,
		speed = 12,
	},
	spearman = {
		id = "spearman",
		name = "พลหอก",
		rarity = "Common",
		hp = 140,
		damage = 14,
		speed = 11,
	},
	archer = {
		id = "archer",
		name = "พลธนู",
		rarity = "Rare",
		hp = 110,
		damage = 22,
		speed = 13,
	},
	knight = {
		id = "knight",
		name = "อัศวิน",
		rarity = "Rare",
		hp = 260,
		damage = 26,
		speed = 10,
	},
	mage = {
		id = "mage",
		name = "จอมเวท",
		rarity = "Epic",
		hp = 180,
		damage = 45,
		speed = 12,
	},
	dragon_rider = {
		id = "dragon_rider",
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
end

return Config
