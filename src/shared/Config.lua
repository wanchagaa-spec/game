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
-- v2 (Phase 3C-1): เพิ่ม battleRoster (แม่ที่ส่งไปรบ) — migration อยู่ที่ PlayerData.MIGRATIONS[1]
-- v3 (Phase 4A): เพิ่ม stageClearBonusGranted (ธงรางวัลผ่านด่าน 9 ช่อง) — PlayerData.MIGRATIONS[2]
-- v4 (UI-4): เพิ่ม discovered (ตัวละครที่เคยได้ · ดัชนี) — PlayerData.MIGRATIONS[3]
-- v5 (UI-5): เพิ่ม robuxDamageBonus / robuxSpeedBonus / processedPurchaseIds (ร้าน Robux) — PlayerData.MIGRATIONS[4]
Config.SCHEMA_VERSION = 5

--------------------------------------------------------------------------------
-- ทำให้ไฟล์นี้โหลดได้นอก Roblox ด้วย (สำหรับชุดเทสต์ใน tests/)
--------------------------------------------------------------------------------
-- ⚠️ Config ต้องโหลดได้สองที่:
--   1. ใน Roblox — มี Color3 / Vector3 ครบ ใช้ของจริง
--   2. ใน luau CLI ตอนรันเทสต์ — ไม่มีทั้งคู่ เพราะเป็น API ของ Roblox
-- การอ่าน global ที่ไม่มีอยู่ใน luau ได้ nil เฉย ๆ ไม่ error จึงเช็คแล้ว fallback ได้
--
-- ค่าที่ fallback คืนเป็น table หน้าตาเหมือนของจริงแต่ไม่มีเมธอด
-- ใช้ได้เพราะ **ไม่มีตรรกะไหนในเกมอ่านค่าสีหรือขนาดกลับมาคำนวณ** มีแต่ส่งต่อให้ Roblox วาด
-- (ถ้าวันไหนมีคนเอา .Magnitude หรือ :Lerp() ไปใช้ ต้องกลับมาเติมที่นี่)
local HAS_COLOR3 = (Color3 :: any) ~= nil
local HAS_VECTOR3 = (Vector3 :: any) ~= nil
local HAS_VECTOR2 = (Vector2 :: any) ~= nil

-- ⚠️⚠️ **fallback ต้องเข้มเท่าของจริง ไม่งั้นเทสต์จะบอกว่าผ่านทั้งที่ Studio พัง**
--
-- `Vector2` / `Vector3` ของ Roblox เป็น **userdata ที่ error ทันทีเมื่ออ่าน member ที่ไม่มี**
-- ส่วน table ธรรมดาคืน `nil` เงียบ ๆ · ความต่างนี้เคยทำให้บั๊กหลุดไปถึง Studio มาแล้ว:
-- `validate()` เขียน `value.Z` บนค่าที่เป็น Vector2 → เทสต์ผ่าน (nil) แต่ Studio พัง (error)
-- → `Config.validate()` ตายตอนบูต → `MapBuilder.build()` ไม่ถูกเรียก → **แมพไม่ขึ้นทั้งใบ**
--
-- ทำ fallback ให้ error แบบเดียวกัน = ความผิดแบบนี้จะถูกจับตั้งแต่ `luau tests/run.luau`
local function strictVector(fields: { [string]: number }, typeName: string): any
	return setmetatable(fields, {
		__index = function(_, key)
			error(`{key} is not a valid member of {typeName}`, 2)
		end,
	})
end

local function rgb(r: number, g: number, b: number): Color3
	if HAS_COLOR3 then
		return Color3.fromRGB(r, g, b)
	end
	return ({ R = r / 255, G = g / 255, B = b / 255 } :: any) :: Color3
end

local function vec3(x: number, y: number, z: number): Vector3
	if HAS_VECTOR3 then
		return Vector3.new(x, y, z)
	end
	return strictVector({ X = x, Y = y, Z = z }, "Vector3") :: Vector3
end

-- คูณ Vector3 ด้วยตัวเลข — เขียนเองแทนใช้ `*` ตรง ๆ เพราะ fallback ข้างบนไม่มี __mul
-- (ตั้งใจไม่เติม __mul ให้ fallback ทั้งระบบ ตามกฎ "fallback ต้องเข้มเท่าของจริง" —
-- เติม metamethod ทั่วไปจะหลอกให้โค้ดอื่นเผลอทำเลขเวกเตอร์ใน Config ได้โดยไม่ตั้งใจ)
local function scaleVec3(v: Vector3, factor: number): Vector3
	local raw = v :: any
	return vec3(raw.X * factor, raw.Y * factor, raw.Z * factor)
end

local function vec2(x: number, y: number): Vector2
	if HAS_VECTOR2 then
		return Vector2.new(x, y)
	end
	return strictVector({ X = x, Y = y }, "Vector2") :: Vector2
end

-- ⚠️ อ่านแกน Z จากค่าที่ **อาจเป็น Vector2 หรือ Vector3** โดยไม่พัง
-- `Vector2` ของ Roblox เป็น userdata → อ่าน `.Z` แล้ว **error** ไม่ใช่คืน nil
-- ส่วน fallback นอก Roblox ก็ถูกทำให้ error เหมือนกัน (strictVector ข้างบน)
-- จึงต้องห่อด้วย pcall ทั้งสองโลก
local function optionalZ(value: any): number?
	local ok, z = pcall(function()
		return value.Z
	end)
	if ok then
		return z
	end
	return nil
end

-- เปิดออกมาให้ชุดเทสต์เรียกได้ด้วย — เทสต์ตรึงไว้ว่าค่าสองแกนต้องคืน nil ไม่ใช่ error
-- (ถ้าวันไหนมีคนลบตัวช่วยนี้แล้วกลับไปอ่าน `.Z` ตรง ๆ เทสต์จะล้มทันที)
Config.getOptionalZ = optionalZ

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

export type EggType = {
	id: string, -- คีย์อ้างอิง (ห้ามเปลี่ยนพร่ำเพรื่อ)
	name: string, -- ชื่อไทยสำหรับโชว์ใน UI
	-- ⚠️ ไม่มีฟิลด์ price โดยตั้งใจ — ไข่ซื้อด้วยเงินในเกมไม่ได้เลย
	-- ไข่ปกติได้จากการแย่งในรังบอส · ไข่ตำนานซื้อด้วย Robux ผ่าน Developer Product
	-- เงินในเกมใช้ซื้อได้แค่ อาวุธ · อัปเกรดอาวุธ · อัปเกรดคอก
	source: string, -- "boss" = แย่งจากรังบอส | "robux" = Developer Product
	-- เวลาฟักเป็นวินาที นับฝั่ง server เท่านั้น
	-- ⚠️ ไข่ source="robux" (ไข่ตำนาน) ใช้ค่านี้ตรง ๆ เสมอ (คงที่ ไม่ขึ้นกับ tier/คลาส — ตั้งใจ
	-- "จ่ายเงินจริงซื้อความเร็ว") ส่วนไข่ source="boss" ค่านี้เป็นแค่ metadata/ประวัติที่ยังคง
	-- ไว้ให้ validate() ตรวจสอบสูตร SECONDS_PER_STAGE ต่อไป **ไม่ใช่ค่าที่ใช้จริงในการฟักแล้ว**
	-- เวลาฟักจริงของไข่ source="boss" มาจาก Config.getHatchSeconds(weight, charId) แทน
	-- (ขึ้นกับน้ำหนัก+คลาสของสิ่งที่จะฟักออกมา ซึ่งฐานเวลาฟักตามด่าน/SECONDS_PER_STAGE เดิม
	-- ไม่มีที่ให้ยืนแล้วเพราะไม่มีมิติน้ำหนัก/คลาสเข้ามาเกี่ยว — ดู docs/data-schema.md §5.1)
	hatchTime: number,

	-- ด่านที่ไข่ฟองนี้มาจาก (บอสด่าน N วางไข่ของด่าน N เท่านั้น)
	-- nil = ไม่ผูกกับด่าน (ไข่ Robux ใช้ด่านที่ผู้ซื้ออยู่)
	stage: number?,

	-- รับประกัน tier น้ำหนักขั้นต่ำ (nil = ไม่รับประกัน สุ่มตามตารางล้วน)
	-- สุ่มตามตารางปกติก่อน ถ้าได้ต่ำกว่านี้ค่อยดันขึ้นมา — ยังลุ้นตัวใหญ่กว่าได้
	-- ใช้กับไข่ที่จ่ายเงินจริง เพื่อให้ "จ่ายแล้วไม่มีทางเสียใจ"
	guaranteedTier: number?,
	-- ⚠️ Color3 เซฟลง DataStore ไม่ได้ ห้ามให้ค่านี้หลุดเข้าไปใน PlayerData
	color: Color3, -- สีของก้อนไข่ตอนวางในฟาร์ม (ชั่วคราว ไว้ดูด้วยตาตอนเทสต์)
	enabled: boolean, -- false = ไม่ให้สุ่ม/ซื้อได้อีก แต่ของเก่าที่ผู้เล่นถืออยู่ยังอ่านได้
}

-- สถานะที่ติดกับ "ตัวแม่" ได้ (Phase 4 ค่อยมีของจริง ตอนนี้เตรียมโครงไว้ก่อน)
export type StatusType = {
	id: string, -- ตัวอักษรเล็กภาษาอังกฤษเท่านั้น เพราะถูกใช้ประกอบ stack key
	name: string, -- ชื่อไทยสำหรับ UI
	order: number, -- ลำดับที่ใช้เรียงตอนแสดงผล (ไม่เกี่ยวกับการเรียงใน stack key)
	enabled: boolean, -- false = ยังไม่เปิดใช้ ตัวคูณทั้งหมดจะถูกข้าม

	-- ตัวคูณ 3 ตัวนี้ 1 = ไม่มีผล แม่ติดหลายสถานะ = คูณสะสมกัน
	damageMultiplier: number, -- คูณ damage และ HP
	coinMultiplier: number, -- คูณรายได้เงิน
	productionMultiplier: number, -- คูณความเร็วในการผลิตลูก

	-- บวกเข้ากับ Config.Balance.Weight.CHILD_RATIO (0.01)
	-- เช่น +0.01 → ลูกหนัก 2% ของแม่แทนที่จะเป็น 1%
	childRatioBonus: number,
}

-- ผลรวมของทุกสถานะที่แม่ติดอยู่ คำนวณด้วย Config.getStatusEffects()
export type StatusEffects = {
	damageMultiplier: number,
	coinMultiplier: number,
	productionMultiplier: number,
	childRatio: number, -- สัดส่วนน้ำหนักลูกต่อแม่ หลังรวมโบนัสแล้ว
}

-- หนึ่งชั้นน้ำหนักของตัวแม่
export type WeightTier = {
	id: number,
	min: number, -- น้ำหนักต่ำสุดในชั้นนี้ (kg, จำนวนเต็ม)
	max: number, -- น้ำหนักสูงสุดในชั้นนี้ (kg, จำนวนเต็ม) — ชั้นบนสุด min = max
	weight: number, -- น้ำหนักการสุ่ม ต่อ Config.Balance.Weight.TIER_ROLL_MAX
}

-- ค่าประจำด่าน 1 ด่าน
export type StageDef = {
	id: number,
	defenders: number, -- จำนวนทหารฝ่ายรับ
}

-- ของที่ซื้อด้วย Robux ผ่าน MarketplaceService
-- ⚠️ ห้ามเก็บราคา Robux ที่นี่ ราคาจริงตั้งใน Creator Dashboard เท่านั้น
-- ถ้าเก็บไว้สองที่ วันที่ปรับราคาแล้วลืมแก้ Config ผู้ใช้จะเห็นราคาผิด
export type DeveloperProduct = {
	id: string,
	name: string, -- ชื่อไทยสำหรับปุ่มในร้าน
	description: string,
	productId: number, -- เลขจาก Creator Dashboard (0 = ยังไม่ได้สร้าง)
	grantEggId: string, -- ซื้อแล้วได้ไข่ชนิดไหน
	grantAmount: number, -- ได้กี่ฟองต่อการซื้อ 1 ครั้ง
	enabled: boolean,
}

-- ⚠️ UI-5: ของที่ซื้อด้วย Robux ที่ "ไม่ใช่ไข่" — คนละ shape จาก DeveloperProduct
-- (ให้ของเป็นขั้น/การกระทำ ไม่ใช่ไข่) แยกตารางเพื่อไม่ต้องยัด field ที่ไม่เกี่ยวกันเข้า DeveloperProduct
-- ทุกตัวเป็น Developer Product แบบซื้อซ้ำได้ (ไม่ใช่ Gamepass) — ProcessReceipt เดียวกันดูแลทั้งคู่
export type RobuxProductKind = "damage_bonus" | "speed_bonus" | "hatch_rush"

export type RobuxProduct = {
	id: string,
	name: string,
	description: string,
	productId: number, -- เลขจาก Creator Dashboard (0 = ยังไม่ได้สร้าง)
	kind: RobuxProductKind,
	amount: number, -- ต่อการซื้อ 1 ครั้ง: จำนวนขั้น (damage_bonus/speed_bonus) หรือ 1 เสมอ (hatch_rush)
	enabled: boolean,
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
	-- id ของ **Model asset** ที่พับลิชขึ้น Roblox แล้ว (ไม่ใช่ Mesh asset เฉย ๆ — ต้องเป็น
	-- Model เพราะ PenService ใช้ InsertService:LoadAsset() แล้ว clone ทั้งก้อนมาสเกล/วางตำแหน่ง)
	-- nil = ยังไม่มีโมเดลเฉพาะตัว ใช้กล่องสี่เหลี่ยมสีตามคลาสแทน (ค่าเริ่มต้นของทุกตัวละคร)
	-- ⚠️ ห้ามมี Humanoid ติดมา (ถูกถอดทิ้ง — เหตุผลเดียวกับที่ห้ามใช้ Humanoid กับแม่ทั้งหมด
	-- ดูหัว PenService.lua) · โครงกระดูก (Bone) + AnimationController ใช้ได้ ไว้เล่นอนิเมชัน
	modelAssetId: number?,
	-- อนิเมชันของโมเดลข้างบน (ต้องมี modelAssetId ด้วยเสมอ · validate() บังคับ)
	-- เดินตอนเคลื่อนที่ · พอหยุดพักวนท่าพักที่มี ตามลำดับ ยืนพัก → นั่ง → ต่อย → ยืนพัก ...
	-- (ดู PenService.updateWander) · ขาดท่าไหนก็ข้ามท่านั้นไป
	-- ต้อง publish ด้วยบัญชีเดียวกับเจ้าของเกม ไม่งั้นเล่นไม่ออก
	animationIds: CharacterAnimations?,
}

export type CharacterAnimations = {
	walk: number?,
	idle: number?,
	sit: number?,
	punch: number?,
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

-- ⚠️ เปลี่ยนชื่อจาก Config.Farm ตอน Phase 1.5 — ดีไซน์ใหม่เรียกพื้นที่ของผู้เล่นว่า "คอก"
-- ตรงนี้เก็บ "กติกาของเซิร์ฟเวอร์" ส่วน **รูปทรงของโลกอยู่ที่ Config.MapDimensions**
-- และความจุคอก (กี่ตัว) อยู่ที่ Config.Balance.Pen ซึ่งโตตามเลเวล
Config.World = {
	-- จำนวนคอกสูงสุดในเซิร์ฟเวอร์ = จำนวนผู้เล่นสูงสุดที่มีคอกได้พร้อมกัน
	-- ⚠️ ต้องเท่ากับ BalanceCheck.PLAYERS_PER_SERVER เสมอ (validate() บังคับแบบเท่ากันเป๊ะ)
	-- เคยตั้งไม่ตรงกัน (6 กับ 7) ซึ่งทำให้โมเดลสมดุลกับโลกจริงไม่ตรงกัน
	-- ⚠️ ต้องเท่ากับ Map.PEN_ROWS × Map.PEN_PER_ROW ด้วย (validate() บังคับเช่นกัน)
	MAX_PENS = 6,

	-- ทุกกี่วินาที server จะเช็คไข่ที่ครบเวลา แล้ว sync สถานะกลับไปหา client
	-- ค่านี้เป็นความละเอียดของตัวจับเวลาด้วย (1 = คลาดเคลื่อนได้ไม่เกิน 1 วินาที)
	SYNC_INTERVAL = 1,

	-- กันผู้เล่นสแปมคำขอ (วินาที) — ด่านแรกของการกัน exploit
	REQUEST_COOLDOWN = 0.25,
}

--------------------------------------------------------------------------------
-- รูปทรงของแมพ (Map) — blockout
--------------------------------------------------------------------------------
-- ⚠️ **โครงหลัก** — ทุกพิกัดในโลกมาจากที่นี่ที่เดียว
-- src/server/MapBuilder.lua อ่านค่าจากตรงนี้ล้วน ๆ ห้าม hardcode ตัวเลขในสคริปต์สร้างแมพ
-- ปรับค่าที่นี่แล้ว generate ใหม่ได้ทันที ไม่ต้องปั้นโมเดลใหม่
--
-- ══ ระบบพิกัด ══ มองจากด้านบน
--
--   X เดินจากซ้ายไปขวา:   ร้านค้า → ลานคอก → เลนรบ (ยาวออกไป 9 ด่าน)
--   Z เป็นแกนขวาง:        คอกแถวบน (+Z) · ทางเดินกลาง (Z=0) · คอกแถวล่าง (−Z)
--   Y คือความสูง พื้นทุกอย่างอยู่ที่ Y = 0
--
--        +Z  ┌─────┐ ┌─────┐ ┌─────┐
--            │คอก 1│ │คอก 2│ │คอก 3│
--   ┌────┐   └─────┘ └─────┘ └─────┘
--   │ร้าน│  ═══════ ทางเดินกลาง ═══════╗
--   └────┘   ┌─────┐ ┌─────┐ ┌─────┐   ║  จุดปล่อย → เลนรบ →→→ ด่าน 1..9
--        −Z  │คอก 4│ │คอก 5│ │คอก 6│   ╚═════════════════════════════════→
--            └─────┘ └─────┘ └─────┘
--
-- ══ ลำดับของเลนรบ ══ ด่าน N กินช่วง X ยาว LANE_LENGTH_PER_STAGE
--   กำแพงด่าน N อยู่ที่ **ต้นช่วง** · รังบอสด่าน N อยู่ที่ **ท้ายช่วง** (คือหลังกำแพง)
--   ด่าน 1 ไม่มีกำแพง → เดินเข้ารังบอสด่าน 1 ได้ตั้งแต่เข้าเกมครั้งแรก
--
-- ⚠️ กำแพง / ทหารฝ่ายรับ / กองทัพตัวเอง **วาดฝั่ง client เท่านั้น**
-- เพราะแต่ละคนพังกำแพงคนละด่านแต่ยืนบนเลนเดียวกัน (ดู docs/map-layout.md)
-- ความกว้างต่ำสุดที่ตัวละคร Roblox มาตรฐาน (กว้างราว 4 studs) เดินผ่านได้แบบสวนกันได้
-- ใช้เป็นเกณฑ์ของ validate() กันตั้งทางเดิน/เลนแคบจนแมพขาดเป็นสองส่วน
local MIN_WALKABLE_WIDTH = 8

--------------------------------------------------------------------------------
-- ขนาดแมพ (MapDimensions) — ⚠️ แหล่งความจริงแหล่งเดียวของรูปทรงแมพ
--------------------------------------------------------------------------------
-- ⚠️ โครงหลัก: แก้ค่าในนี้แล้วของทุกอย่างในโลกขยับตาม
-- **ทุกพิกัดต้องมาจากที่นี่หรือจาก Config.get*() เท่านั้น ห้าม hardcode ตัวเลขในสคริปต์**
--
-- ⚠️ เคยมีตารางที่สองชื่อ `Config.Map` เป็น alias ของตารางนี้ (สร้างตอนขยายแมพ
-- เพื่อไม่ต้องแตะ PenService ที่ยังใช้ชื่อเดิม) **ยุบทิ้งแล้ว**
-- เพราะการมีสองชื่อสำหรับของเดียวกันทำให้คนอ่านโค้ดใหม่ไม่รู้ว่าควรใช้อันไหน
-- และต้องมี assert คอยตรวจว่าสองฝั่งตรงกัน ซึ่งเป็นงานที่ไม่ควรต้องมีตั้งแต่แรก
--
-- ⚠️ ขนาดที่เป็นพื้นที่ใช้ `vec2(กว้าง, ลึก)` — **ไม่มีแกน Y** เพราะเป็นผังบนพื้น
-- ส่วนขนาดของ Part จริง ๆ ใช้ `vec3` (มีความสูง)
Config.MapDimensions = {
	-- ══ ตัวละครผู้เล่น ══
	Player = {
		Height = 5, -- ความสูงตัวละครมาตรฐาน (อ้างอิงเฉย ๆ ไม่ได้เอาไปตั้งค่าอะไร)

		-- ⚠️ ×2 จากค่าปกติของ Roblox (16) — แมพใหญ่ขึ้นมาก ถ้าเดินเท่าเดิมจะน่าเบื่อ
		-- ตั้งจริงที่ StarterPlayer.CharacterWalkSpeed ใน default.project.json
		-- และ Main.server.lua เช็คซ้ำตอนบูตว่าตรงกับค่านี้
		-- ⚠️ ซื้อเพิ่มได้ถึง ×4 ด้วย Config.Balance.SpeedUpgrade — ค่านี้เป็นแค่ "ขั้น 0"
		WalkSpeed = 32,

		-- ความสูงที่กระโดดได้ (studs) — ใช้เป็นเกณฑ์ว่ากำแพงใสต้องสูงกว่านี้ (validate() บังคับ)
		--
		-- ⚠️ Roblox มีสองโหมด และค่านี้จะมีผลก็ต่อเมื่ออยู่โหมดที่ถูก:
		--   UseJumpPower = true  (ค่า default) → ใช้ JumpPower แล้วคำนวณความสูงเอง
		--                                        JumpPower 50 → 50²/(2×196.2) ≈ 6.37
		--   UseJumpPower = false                → ใช้ JumpHeight ตรง ๆ เป็น studs
		--
		-- เดิมเขียน 7 ไว้เฉย ๆ โดยที่โปรเจกต์ยังอยู่โหมด JumpPower → **ของจริงคือ 6.37
		-- ส่วน 7 เป็นตัวเลขที่ไม่มีใครใช้** assert จึงเทียบกับค่าที่ไม่ได้เกิดขึ้นจริง
		--
		-- ตอนนี้ `default.project.json` ตั้ง CharacterUseJumpPower = false
		-- และ CharacterJumpHeight = 7.2 ให้ตรงกับค่านี้ · Main.server.lua เช็คซ้ำตอนบูต
		JumpHeight = 7.2,

		-- แผ่นจุดเกิดในคอกของแต่ละคน (CanCollide = false จะได้ไม่สะดุดตอนเดินผ่าน)
		SpawnPadSize = vec3(10, 0.4, 10),
	},

	-- ══ คอก ══ 2 แถว × 3 คอลัมน์ = 6 แปลง
	Pen = {
		-- ขนาดคอกต่อคน — **พื้นเป็นหญ้าทั้งผืน ไม่มีแปลงหรือช่องตาราง**
		-- ตัวแม่เดินได้อิสระทั่วคอก ไข่วางตรงไหนก็ได้
		Size = vec2(80, 80),

		-- ⚠️ Rows × PerRow ต้องเท่ากับ World.MAX_PENS เป๊ะ (validate() บังคับ)
		Rows = 2,
		PerRow = 3,

		-- ⚠️ ทางเดินกลางต้องกว้างกว่าเลนรบ (60) ไม่งั้นเดินจากลานเข้าเลนแล้วรู้สึกคอขวด
		-- เดิม 30 ซึ่งแคบกว่าเลนครึ่งหนึ่ง · 90 = กว้างกว่าเลน 1.5 เท่า
		RowGap = 90, -- ทางเดินกลางระหว่าง 2 แถว (เชื่อมร้านค้ากับต้นเลนรบ)
		ColumnGap = 20, -- ช่องระหว่างคอกในแถวเดียวกัน

		-- ระยะที่แม่/ไข่ต้องอยู่ห่างจากขอบคอก กันไม่ให้ไปยืนซ้อนกับรั้ว
		EdgeMargin = 4,

		-- ความหนาแผ่นพื้นคอก — **เป็นแค่แผ่นสีทับบนหญ้า ไม่ใช่ขั้นบันได**
		-- ⚠️ **ผิวบนของแผ่นนี้คือระดับที่แม่กับไข่ยืน** — MapBuilder สร้างแผ่น
		-- ส่วน PenService วางของบนนั้น ทั้งสองไฟล์ต้องอ่านค่าเดียวกัน
		--
		-- ⚠️⚠️ **ต้องบางมาก** เพราะ:
		--   · แผ่นนี้ `CanCollide = false` → **ผู้เล่นเดินบนหญ้าที่ Y = 0 ไม่ได้เดินบนแผ่นนี้**
		--   · สีเกือบเท่าหญ้า (grass / grassAlt) → มองไม่ออกว่าเป็นแท่นยกสูง
		--   → ของที่วางบนผิวแผ่นจะดู "ลอยเหนือพื้น" เท่ากับความหนาแผ่น
		-- เคยตั้ง 0.3 แล้วไข่ (ทรงกลม แตะพื้นจุดเดียว) ดูลอยชัดเจน
		-- ส่วนแม่ไม่เห็นเพราะเป็นทรงกล่อง ก้นแบนแนบขอบแผ่นพอดี
		FloorThickness = 0.05,

		-- ══ รั้วไม้เตี้ย ══ **แค่บอกขอบเขต ไม่ใช่กำแพงกันทาง**
		-- ⚠️ `CanCollide = false` ทั้งเส้น ผู้เล่นและแม่เดินทะลุได้
		-- เคยทำหนา 5 เพื่อให้ผ่านกฎความหนา-ความเร็ว แล้วมันกลายเป็น "กำแพงเตี้ย" ไม่ใช่รั้ว
		-- ตอนนี้ยกเว้นรั้วออกจากกฎนั้นแทน เพราะกฎมีไว้กับกำแพงที่ต้อง **หยุด** ผู้เล่นเท่านั้น
		FenceHeight = 3, -- รั้วไม้ฟาร์มปกติ ไม่ใช่กำแพง
		FenceThickness = 1, -- เสากับคานบาง ๆ
		FencePostSpacing = 8, -- เสาทุก ๆ ระยะนี้
		FenceRailCount = 2, -- คานแนวนอนกี่ชั้น

		-- ช่องประตูหน้าคอก — ทำโดย **เว้นช่องกลางรั้วด้านที่หันเข้าทางเดิน** ไม่มีบานประตู
		-- ทั้ง 6 คอกหันประตูเข้าทางเดินกลาง (แถวบนหันลง · แถวล่างหันขึ้น)
		GateWidth = 8,

		-- ป้ายชื่อคอก — ปักบนหญ้า **ข้างประตู ไม่ใช่กลางประตู** (กันเดินชน)
		SignSize = vec3(10, 3, 0.4),
		SignPostHeight = 5, -- ยกป้ายให้อ่านได้จากมุมกล้องปกติ
		SignGateClearance = 3, -- ระยะจากขอบประตูถึงเสาป้าย
	},

	-- ══ เลนรบ ══ ที่เดียวในแมพที่มีกำแพงสองข้างทาง
	Lane = {
		Width = 60,
		LengthPerStage = 180, -- เลนทั้งเส้น = ค่านี้ × Stage.COUNT

		-- กำแพงสองข้างเลน (กันเดินอ้อมกำแพงกั้นด่าน) — **ของ server ทุกคนเห็นเหมือนกัน**
		WallHeight = 40,
		-- ⚠️ เคยเขียนเป็น `FENCE_THICKNESS * 4` ใน MapBuilder ซึ่งผูกความหนา
		-- **กำแพงกันตก** ไว้กับความหนา **รั้วประดับ** โดยไม่มีเหตุผลเชิงดีไซน์
		WallThickness = 5,

		-- เลนต่อจากปลายลานคอกทันที ไม่มีช่องว่างคั่น (ตามรูปทรงที่ตกลง)
		StartGap = 0,
	},

	-- ══ แท่นอัญเชิญ (UI-3) ══ แทนแท่นปล่อยทหารสี่เหลี่ยมเดิม (16 × 28 · X 140–156)
	-- จานหินเรืองแสง · ทหาร (ภาพ) โผล่ที่กึ่งกลางแท่นแล้วเดินเข้าเลน · กด E ค้างเปิดหน้าต่างอัญเชิญ
	-- ⚠️ **ภาพ + จุดกดเท่านั้น** — การรบคิดเป็นตัวเลขล้วน (CombatService ไม่อ่านพิกัดใด ๆ)
	--   ต้นเลน · ความยาวเลน · ระยะด่าน ยังอ่าน getLaneStartX / LengthPerStage เหมือนเดิม
	-- ⚠️ 5B-fix (ผลทดสอบ Studio · ผู้ใช้สั่ง): ย้าย**เข้าไปในเลน = พื้นที่สนามรบ** หลังช่องประตู/กำแพงกั้น
	--   กึ่งกลาง = ผิวหลังช่องประตู (getLaneWallStartX · X 162.5) + EntranceGap + รัศมี = **X 177**
	--   (เดิม X 148 ในลาน = ต้นเลน + 8) · ผลที่ตามมา: กลางคืนกำแพงกั้นปิดทางไปแท่น (1 นาที) ·
	--   คนยืนที่แท่นตอนต้นกลางคืนอยู่ในสนามรบ → ถูกวาปออกมาหน้าป้อม
	-- ⚠️ CanCollide = false ทั้งแท่น (เดินทับได้ ไม่บังทางเดิน) · validate() บังคับว่าอยู่ในเลนหลังช่องประตู
	--   ก่อนห้องบอสด่าน 1 · จุดกด E ไม่ทะลุกำแพงกั้นออกมาฝั่งลาน · ห่างระยะตีบอส
	SummonPedestal = {
		Diameter = 14, -- ฐานหิน
		CoreDiameter = 10, -- แกนเรืองแสง (Neon) บนฐาน
		BaseHeight = 0.4,
		CoreHeight = 0.2, -- แกนนูนเหนือฐานเท่านี้
		EntranceGap = 7.5, -- ระยะจากผิวหลังช่องประตู (X 162.5) ถึงขอบแท่น — เดินเข้าเลนมาแล้วไม่เหยียบแท่นทันที
		PromptHoldSeconds = 0.5, -- กด E ค้าง
		PromptDistance = 12, -- วัดจากกึ่งกลางแท่น (รัศมีแท่น 7)
		CloseDistance = 18, -- เดินออกห่างจากกึ่งกลางแท่นเกินนี้ หน้าต่างอัญเชิญปิดเอง
		LightRange = 18,
	},

	-- ══ กำแพงกั้นด่าน ══ **วาดฝั่ง client** (ค่าตรงนี้ให้ทั้งสองฝั่งอ่านตรงกัน)
	-- ⚠️ ความสูงใช้ Lane.WallHeight ร่วมกัน จะได้ดูเป็นชิ้นเดียวกับกำแพงข้างเลน
	-- **ไม่เก็บซ้ำเป็นค่าของตัวเอง** เพราะซ้ำแล้วมีวันที่สองค่าไม่ตรงกัน
	StageWall = {
		Thickness = 5,
	},

	-- ══ รังบอส ══ 1 ห้องต่อด่าน อยู่ท้ายช่วงด่าน = หลังกำแพงของด่านนั้น
	-- ⚠️ กว้างกว่าเลน → เลนต้อง "ผายออก" ตรงห้อง กำแพงข้างเลนจึงเดินเป็นขั้น
	BossRoom = {
		Size = vec2(80, 80),

		-- ⚠️ 5B: บอส + ไข่อยู่**มุมห้อง** ฝั่งเดียว อีกฝั่งเว้นเป็นทางวิ่งผ่าน (นอกระยะตีบอส) ไปด่านถัดไป
		-- ฝั่งของแต่ละด่าน **สลับฟันปลา** (validate() บังคับว่าติดกันต้องคนละฝั่ง) — ผู้ใช้วางแผนไว้ใน docs/boss-plan.md
		-- ซ้าย/ขวา = ยืนหันหน้าไปทางปลายเลน (+X): **ขวา = +Z · ซ้าย = −Z**
		-- ⚠️ 5B-2: ใช้จริงครบทั้ง 9 ห้องแล้ว (บอสทุกห้อง) — validate() ตรวจบอส/ไข่/ทางวิ่งทุกห้อง
		-- (เดิมมีไข่ 5 จุดวางเป็นวงกลม EggRadiusRatio/EggPadSize ของดีไซน์ "บอสด่านละตัวรีเกิด 5 นาที" — ลบแล้วใน 5B)
		CornerSide = { "right", "left", "right", "left", "right", "left", "right", "left", "right" },
	},

	-- ══ บอสทุกห้อง (Phase 5A → 5B-2) ══ บอส 1 ตัวต่อห้องด่าน · ค่าในกลุ่มนี้ใช้ร่วมกันทุกห้อง
	-- ⚠️ 5B-2: เลิกใช้ "บอสกลางตัวเดียวที่ห้องด่าน 1" แล้ว (ลบ `Stage` ออก) — ห้อง N = ช่วงเลนหลังกำแพงด่าน N
	--   ถึงกำแพงด่าน N+1 (Config.getStageRoomRangeX) · เข้าได้เมื่อพังกำแพงด่าน N แล้ว (Config.canAccessBossRoom)
	--   ห้อง 1 ไม่มีกำแพง = ทุกคนเข้าได้ · server ตรวจสิทธิ์จากความคืบหน้า **ไม่ใช่แค่ตำแหน่ง** (กำแพงด่านวาดฝั่ง client)
	-- กำแพงกั้นกลางคืน = ของ server ชิ้นเดียว · ทหารไม่โดน (ทหารเป็นภาพ Anchored ไม่ชน)
	-- ⚠️ 5B: กำแพงกั้นย้ายไป**ปิดช่องทางเข้าเลนพอดี** (ช่องประตูของกำแพงหินขอบแมพฝั่งตะวันออก X 157.5–162.5)
	--   ขนาด/ตำแหน่งคำนวณจากกำแพงขอบแมพเอง (getBossBarrierX/Size) — ไม่มีค่าของตัวเองให้ตั้งผิดแล้ว
	--   5B-2: ยังเป็นชิ้นเดียวที่ปากเลน (ผู้ใช้ยืนยัน) — กลางคืนปิดสนามรบทั้งเส้น เช้าแต่ละคนวิ่งไปห้องของตัวเอง
	BossArena = {
		BossSize = vec3(10, 14, 10), -- blockout กล่อง (ไม่ใช่ Humanoid)
		-- หน้าป้อม: จุดยืนตอนวาปกลางคืน **ฝั่งลานกลาง** หน้ากำแพงกั้น — แถวละ GatherPerRow คน ถอยจากกำแพงออกมา
		-- ⚠️ ถอยไกลพอให้เห็นตัวเลขนับถอยหลังทั้งแผ่น (กำแพงสูง 40) และพ้นแท่นอัญเชิญ (X 141–155 · validate() บังคับ)
		GatherPerRow = 3,
		GatherFrontGap = 25, -- แถวแรกห่างผิวหน้ากำแพงกั้น (ฝั่งลาน) เท่านี้
		GatherRowGap = 10,
		GatherSpacingZ = 15,
		-- ══ 5B: บอสอยู่มุมห้อง (ฝั่งตาม BossRoom.CornerSide) ══
		BossCornerX = 10, -- กึ่งกลางบอสเลยกึ่งกลางห้องลึกเข้าไปทาง +X เท่านี้
		BossCornerZ = 22, -- กึ่งกลางบอสห่างแนวกลางเลนเท่านี้ ไปทางฝั่งมุม
		-- ทางวิ่งฝั่งตรงข้ามมุม (นอกระยะตีของบอส) ต้องกว้างอย่างน้อยเท่านี้ — วัดที่ช่วงเลนปกติ (แคบกว่าห้อง) · validate()
		RunPathMinWidth = 20,
		-- ไข่ 6 ฟอง**หลังบอส** (+X) มุมเดียวกัน — ตาราง EggColumns คอลัมน์ · แถวกลางตรงกับ Z ของบอส
		EggColumns = 2,
		EggBackOffset = 14, -- คอลัมน์แรกห่างกึ่งกลางบอสไปทาง +X เท่านี้
		EggColumnGap = 8,
		EggRowGap = 8,
		-- หยิบไข่: กด E ค้าง (client · UiKit.prompt) · server ตรวจระยะจากตำแหน่งตัวละครที่ server เห็นอีกชั้น
		EggPromptDistance = 8,
		EggPickupRange = 10, -- server ยอมคลาดจาก prompt เล็กน้อย (ตำแหน่ง client/server ห่างกันได้ช่วงเดินอยู่)
	},

	-- ══ ร้านค้า ══ แผงเล็ก ๆ วางที่ขอบลาน **ไม่ใช่อาคารใหญ่**
	-- ตัวแผงเป็นแค่ฉาก ของจริงคือ UI · แผง MapSign.SellStallIndex = ร้านขายแม่ (UI-2 · กด E)
	Shop = {
		StallSize = vec2(12, 12),
		StallCount = 2,
		StallHeight = 8, -- ความสูงหลังคาแผง (แค่ฉาก)
		Gap = 20, -- ระยะจากขอบซ้ายของลานคอก ถึงแนวแผง
		-- ⚠️ UI-2 (ผลทดสอบ Studio): แผงวาง**ติดกันกลางผนังด้านหลัง** (Z = 0) ไม่ใช่ขนาบทางเดินกลางไปคนละฝั่งแล้ว
		-- ช่องเดินระหว่างสองแผง — ต้องไม่แคบกว่าประตูคอก (validate() บังคับ)
		StallGap = 10,
	},

	-- ══ ป้ายบนแมพ (UI-2) ══ แผ่นไม้บนเสา เดินเข้าใกล้แล้วกด E (ProximityPrompt)
	-- ป้ายอัปดาเมจ 1 จุด (ปากเลนฝั่งลาน) · ป้ายอัปค่าวิ่ง + อัปคอก ข้างประตู**ทุกคอก** · ร้านขายแม่ = แผงร้าน
	-- ⚠️ ตัวป้าย (เสา + แผ่นไม้) server สร้าง ทุกคนเห็นเหมือนกัน · **ข้อความ (เลเวล/ราคา) client วาดเอง**
	--   เพราะแต่ละคนเห็นค่าของตัวเอง — ห้ามเขียนค่าของใครลงป้ายที่คนอื่นเห็นด้วย
	-- ตำแหน่งจริงคำนวณที่ Config.getPenUpgradeSignSpot / getDamageSignSpot / getSellShopSpot
	MapSign = {
		BoardSize = vec3(9, 5, 0.4), -- กว้าง · สูง · หนา (ใหญ่กว่าป้ายชื่อคอก — มี 3 บรรทัด)
		PostHeight = 3, -- เสาใต้ขอบล่างแผ่น · ขอบบนแผ่น = 3 + 5 = 8 เท่าป้ายชื่อคอก
		NameSignGap = 3, -- ป้ายที่ปักฝั่งเดียวกับป้ายชื่อคอก เว้นห่างจากป้ายชื่อเท่านี้
		-- ⚠️ UI-fix รอบ 1: ลดจาก 6 → 2 (ขยับป้ายเข้าใกล้กำแพงทางเข้าเลนมากขึ้น ยังคง < ต้นเลนเสมอ — validate() บังคับ)
		DamageInsetX = 2, -- ป้ายดาเมจถอยจากต้นเลนเข้ามาในลานคอก (ไม่ขวางปากเลน)
		-- ⚠️ UI-fix รอบ 1: ระยะจากขอบเลน (Lane.Width/2) ถึงป้าย — ให้ป้ายชิดแนวเลนแทนที่จะอยู่กึ่งกลาง
		-- ระหว่างเลนกับแถวคอก (เดิมดูกลืนไปกับโซนคอก) ยังอยู่ในช่วงที่ validate() กำหนดไว้ (ไม่ทับเลน/แถวคอก)
		DamageInsetZ = 5,
		PromptDistance = 10, -- ระยะกด E ของป้ายอัปเกรด
		-- แผงร้านที่เป็นร้านขายแม่ — แผง 1 (เดิมป้าย "ขายของ · ซื้อไข่" · ตัดสินใน UI-2)
		-- ⚠️ ป้ายเดิมมีคำว่า "ซื้อไข่" ซึ่งขัดกฎ (เงินในเกมซื้อไข่ไม่ได้) จึงเปลี่ยนเป็น "ร้านขายแม่"
		SellStallIndex = 1,
		SellPromptDistance = 14, -- วัดจากกึ่งกลางแผง (แผงกว้าง 12) จึงต้องไกลกว่าป้าย
		SellCloseDistance = 20, -- เดินออกห่างจากกึ่งกลางแผงเกินนี้ หน้าต่างขายปิดเอง
		-- 5C: แผงร้านที่เป็นร้านกระบอง (ป้าย "ซื้ออาวุธ" เดิม) — ระยะเดียวกับร้านขายแม่ (แผงขนาดเท่ากัน)
		WeaponStallIndex = 2,
		WeaponPromptDistance = 14,
		WeaponCloseDistance = 20,
	},

	-- ══ ขอบแมพ ══ แท่นลอย ตกได้ → กั้นด้วยกำแพงใส
	Boundary = {
		-- ⚠️ ตั้งเท่ากับ Lane.WallHeight เสมอ (sync ไว้ท้ายไฟล์ตาราง MapDimensions)
		-- เดิมเก็บเป็นค่าของตัวเอง (50) แยกจาก Lane.WallHeight (40) แล้ววันหนึ่งสองค่า
		-- ไม่ตรงกัน — เห็นกำแพงสองความสูงในเฟรมเดียวตรงปากทางเข้าเลน (จุดปล่อยทหารด่าน 1
		-- ที่กำแพงขอบแมพกับกำแพงข้างเลนมาเจอกันพอดี) หลักการเดียวกับที่ StageWall ใช้อยู่แล้ว
		Height = 40, -- ต้องสูงกว่า Player.JumpHeight (validate() บังคับ) — ค่าจริง sync จาก Lane.WallHeight

		-- ระยะจากกำแพงใสถึงขอบพื้น = **แถบหญ้าที่มองเห็นแต่เดินไปไม่ถึง**
		-- มีไว้ให้ขอบแมพไม่จบห้วน ๆ ตรงที่ชนกำแพงพอดี
		-- ⚠️ พื้นลานขยายตามค่านี้เอง (getPlazaMinX / getPlazaHalfDepth บวกไว้ให้แล้ว)
		-- ไม่ใช่การ "หดกำแพงเข้ามา" — เคยเป็นแบบนั้นแล้วดันค่าขึ้นทีไรกำแพงกินเข้าไปในคอก
		Margin = 50,

		Thickness = 5,
	},

	-- ══ แม่เดินไปมาในคอก ══
	-- ⚠️ **ห้ามใช้ Humanoid** — แม่เต็มคอก × ผู้เล่นเต็มเซิร์ฟ = Humanoid หลักร้อยตัว หนักเกินไป
	-- ใช้ CFrame lerp: สุ่มจุดหมายในคอก เดินไปหา หยุดพัก แล้วสุ่มใหม่
	-- ⚠️ **ห้ามเซฟตำแหน่งลง DataStore** — สุ่มใหม่ทุกครั้งที่เข้าเกม
	-- ตำแหน่งไม่มีความหมายเชิงเกม และเซฟแล้วกิน DataStore ฟรี ๆ
	Wander = {
		-- ⚠️ เป็น **studs ต่อวินาที** (duration = ระยะ ÷ ค่านี้) ไม่ใช่ "เวลาต่อระยะ"
		-- คอกใหญ่ขึ้นแล้วแม่จะใช้เวลาเดินนานขึ้นตามระยะจริง ซึ่งถูกต้อง
		Speed = 4,
		PauseMin = 1.5, -- หยุดพักก่อนออกเดินรอบถัดไป (วินาที)
		PauseMax = 5,
		Tick = 0.1, -- ความถี่ที่ขยับ (วินาที) — ยิ่งถี่ยิ่งลื่นแต่กิน CPU
	},

	-- ══ ขนาดโมเดล blockout ══ (หน้าตาล้วน ๆ ไม่กระทบกติกา)
	Blockout = {
		MotherSize = vec3(3.5, 3.5, 5),

		-- ⚠️ **ต้องเท่ากันทั้งสามแกน** เพราะไข่วาดด้วย `Shape = Ball`
		-- Roblox ไม่รับประกันว่าลูกบอลที่ขนาดไม่เท่ากันทุกแกนจะวาดออกมาเป็นอะไร
		-- (เคยตั้ง (3, 3.8, 3) → เลข 3.8 ไม่มีผลต่อภาพ แต่ไปหลอกให้โค้ดคิดว่ารัศมี = 1.9
		--  ทั้งที่ของจริง 1.5 → ไข่ลอย) · เท่ากันทุกแกนแล้วตีความยังไงก็ได้ค่าเดียวกัน
		EggSize = vec3(3, 3, 3),
	},
}

-- ⚠️ sync ค่าให้ตรงกับ Lane.WallHeight เสมอ — table literal ข้างบนอ้างอิงข้ามคีย์กันเองไม่ได้
-- ตอนกำลังสร้าง (Boundary ยังไม่รู้จัก Lane ระหว่างเขียน) จึงต้องมาตั้งซ้ำตรงนี้แทนการ
-- เขียนเลข 40 ซ้ำอีกที่หนึ่งซึ่งเป็นสาเหตุที่มันหลุดไม่ตรงกัน (50 vs 40) มาก่อนแล้ว
Config.MapDimensions.Boundary.Height = Config.MapDimensions.Lane.WallHeight

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

-- ⚠️ โครงหลัก: ชื่อและ signature ที่ client-server ตกลงกัน
-- เปลี่ยนแล้วต้องแก้ทั้งสองฝั่งพร้อมกันเสมอ
Config.RemoteNames = {
	FOLDER = "Remotes", -- Folder ใน ReplicatedStorage ที่เก็บ RemoteEvent ทั้งหมด

	-- client → server : FireServer(heldIndex, slotIndex?)
	-- ⚠️ ส่ง "ตำแหน่งไข่ใน heldEggs" ไม่ใช่ชนิดไข่
	-- เพราะไข่ชนิดเดียวกันน้ำหนักต่างกันได้ ระบุด้วยชนิดไม่ได้อีกแล้ว
	PLACE_EGG_IN_HATCHERY_REQUEST = "PlaceEggInHatcheryRequest",

	-- client → server : FireServer(uid, "pen" | "bag")
	MOVE_MOTHER_REQUEST = "MoveMotherRequest",

	-- client → server : FireServer() — ไม่มีพารามิเตอร์ อัปคอกของผู้เล่นเองขึ้น 1 ขั้นเสมอ
	UPGRADE_PEN_REQUEST = "UpgradePenRequest",

	-- client → server : FireServer(motherUid) — ขายได้เฉพาะแม่ในกระเป๋าเท่านั้น
	-- ⚠️ ไม่มีพารามิเตอร์ราคา — ราคาคำนวณฝั่ง server เสมอ ไม่มีช่องให้ client ส่งราคามาเอง
	SELL_MOTHER_REQUEST = "SellMotherRequest",

	-- client → server : FireServer() — ไม่มีพารามิเตอร์ "สวมใส่ที่ดีที่สุด" (UI-1 · ชื่อ remote เดิม)
	-- คอกจบด้วยแม่ N ตัวที่รายได้เงิน/นาทีสูงสุดจากคอก+กระเป๋า — **สลับตัวอ่อนในคอกออกไปกระเป๋าได้**
	-- (เดิมเติมแค่ช่องว่าง) · สลับทีละคู่ กระเป๋าไม่ล้นระหว่างทาง · ดู EggService.planEquipBest
	AUTO_FILL_PEN_REQUEST = "AutoFillPenRequest",

	-- client → server : FireServer(orderedStackKeys: {string})
	-- ⚠️ UI-3: แทนที่ releaseOrder ทั้งชุด = **กองที่ติ๊กให้ปล่อย** เรียงตามลำดับติ๊ก (ว่าง = ไม่ปล่อยลูกเลย)
	-- กองที่ไม่อยู่ในนี้ไม่ถูกปล่อย (เดิม server ต่อท้ายกองใหม่ให้เองทุก tick — ตัดแล้ว) · signature ไม่เปลี่ยน
	-- ⚠️ ต้องเป็น stack key ที่ผ่าน Config.makeStackKey() เป๊ะ (round-trip ตรงตัว) เท่านั้น
	-- ไม่ต้องเป็นกองที่ผู้เล่นมีอยู่ตอนนี้ (กองที่ว่างชั่วคราวยังตั้งลำดับล่วงหน้าได้) —
	-- server ปฏิเสธทั้งคำขอเงียบ ๆ ถ้ามี key แปลกปลอมหรือซ้ำแม้แค่ตัวเดียว (CombatService)
	SET_RELEASE_ORDER_REQUEST = "SetReleaseOrderRequest",

	-- client → server : FireServer(enabled: boolean) — เปิด/ปิดปุ่มอัญเชิญ (data.summonEnabled)
	SET_SUMMON_ENABLED_REQUEST = "SetSummonEnabledRequest",

	-- client → server : FireServer() — ไม่มีพารามิเตอร์ ซื้อขั้นถัดไปเสมอ (data.damageLevel + 1)
	-- ราคา/เพดานคำนวณฝั่ง server ทั้งหมดจาก Config.getDamageUpgradeCost / getMaxDamageLevel
	BUY_DAMAGE_UPGRADE_REQUEST = "BuyDamageUpgradeRequest",

	-- client → server : FireServer() — ไม่มีพารามิเตอร์ ซื้อขั้นถัดไปเสมอ (data.speedLevel + 1)
	-- ⚠️ ซื้อสำเร็จแล้วต้องมีผลกับ Humanoid.WalkSpeed ทันที ไม่ต้องรอ respawn
	BUY_SPEED_UPGRADE_REQUEST = "BuySpeedUpgradeRequest",

	-- client → server : FireServer() — ไม่มีพารามิเตอร์ (Phase 5C · ร้านกระบอง)
	-- ⚠️ ซื้อได้แค่ "ขั้นถัดไป" เสมอ (weaponLevel + 1) · **ไม่รับเลขขั้นจาก client** · ราคา/เงิน/เพดานตรวจฝั่ง server
	--   (Config.planClubPurchase → PlayerData.buyNextClubTier) · สำเร็จ = ActionResult "ได้กระบองขั้น N" + sync
	BUY_CLUB_TIER_REQUEST = "BuyClubTierRequest",

	-- server → client : { slotIndex, eggId, charId, charName, class, weight, placedIn }
	EGG_HATCHED = "EggHatched",

	-- server → client : { heldEggs, hatching, mothersInPen, mothersInBag, penCapacity, ... }
	FARM_STATE_SYNC = "FarmStateSync",

	-- server → client : FireClient(ok: boolean, message: string)
	-- ผลลัพธ์ล่าสุดของ PlaceEggInHatcheryRequest / MoveMotherRequest / UpgradePenRequest /
	-- SellMotherRequest — ก่อนมี remote นี้ผลลัพธ์เห็นได้แค่ผ่าน print ใน server console เท่านั้น
	-- ⚠️ เป็น "ผลล่าสุดแบบ broadcast" ไม่ผูกกับ request ไหนเจาะจง (พอสำหรับ UI ทดสอบตอนนี้ที่
	-- ยิงคำขอทีละอันอยู่แล้ว ไม่มีคำขอค้างซ้อนกันจนสับสนว่าอันไหนตอบอันไหน)
	ACTION_RESULT = "ActionResult",

	-- client → server : FireServer(motherUid) — ส่งแม่ **จากกระเป๋าเท่านั้น** เข้า battleRoster
	-- ⚠️ ย้อนกลับไม่ได้ แม่ตายถาวรตอนด่านที่กำลังตีพัง (CombatService.handleSendMotherToBattle)
	-- client ต้องขึ้นกล่องยืนยันก่อนยิงทุกครั้ง · ผลตอบกลับทาง ACTION_RESULT
	-- · UI-3: client ไม่ใช้แล้ว (หน้าต่างแท่นอัญเชิญยิง SEND_MOTHERS_TO_BATTLE_BATCH_REQUEST) — server ยังรับอยู่
	SEND_MOTHER_TO_BATTLE_REQUEST = "SendMotherToBattleRequest",

	-- server → client : FireClient(stage, eggCount, deathCount) — ด่านเพิ่งพัง (Phase 4A · ขยาย 4B)
	-- eggCount = ไข่ฟรีที่แจกได้จริง (ครั้งแรกที่ด่านพังเท่านั้น) · deathCount = แม่ใน roster ที่ตายตอนด่านพัง
	-- ยิงเมื่อ "ควรได้ไข่" หรือ "มีแม่ตาย" อย่างใดอย่างหนึ่ง ไม่มีทั้งคู่ = ไม่ยิง
	-- (0, 0) มาถึง client ได้กรณีเดียว = ควรได้ไข่แต่กระเป๋าไข่เต็ม → Config.formatStageClearedMessage
	-- ⚠️ เหตุการณ์ที่ server เป็นคนเริ่มเอง (ไม่ได้มาจากปุ่มที่ผู้เล่นกด) จึงแยกจาก ACTION_RESULT
	-- ยิงครั้งเดียวตอนเกิดเหตุ ไม่อยู่ใน FARM_STATE_SYNC — resync กี่รอบ popup ก็ไม่โผล่ซ้ำ
	STAGE_CLEARED_NOTIFY = "StageClearedNotify",

	-- client → server : FireServer(motherUid) — สลับล็อก/ปลดล็อกแม่ของตัวเอง (Phase 4B)
	-- แม่ในคอกหรือกระเป๋าเท่านั้น (แม่ใน battleRoster ไม่ได้) · ผลตอบกลับทาง ACTION_RESULT
	-- ล็อกแล้วกันได้ 2 อย่าง: ขาย (EggService.sellMother) · ส่งไปรบ (CombatService.handleSendMotherToBattle)
	-- ⚠️ ไม่กันการย้ายคอก↔กระเป๋า (ย้ายไม่ได้ทำให้แม่หาย)
	TOGGLE_MOTHER_LOCK_REQUEST = "ToggleMotherLockRequest",

	-- client → server : FireServer(motherUids: { string }) — ขายแม่เป็นชุด (UI-2 · ร้านขายแม่)
	-- ⚠️ ไม่ใช่ array / สมาชิกไม่ใช่ string / ว่าง / ยาวเกินความจุกระเป๋า → ปฏิเสธทั้งชุด
	-- แต่ละตัวผ่านแกนขายเดียวกับ SELL_MOTHER_REQUEST (ราคาคิดที่ server · เฉพาะกระเป๋า · ล็อกขายไม่ได้)
	-- ตัวที่ขายไม่ได้ (ล็อก / ไม่ใช่ของตัวเอง / อยู่ในคอก / uid ซ้ำในชุด) ข้ามไป ขายตัวอื่นต่อ
	-- sync ครั้งเดียวท้ายชุด · ผลสรุปครั้งเดียวทาง ACTION_RESULT (Config.formatSellBatchMessage)
	-- · SELL_MOTHER_REQUEST (ทีละตัว) ยังอยู่ ไม่ได้ลบ
	SELL_MOTHERS_BATCH_REQUEST = "SellMothersBatchRequest",

	-- client → server : FireServer(motherUids: { string }) — ส่งแม่ไปรบเป็นชุด (UI-3 · แท่นอัญเชิญ)
	-- ⚠️ ไม่ใช่ array / สมาชิกไม่ใช่ string / ว่าง / เกิน MAX_BATTLE_MOTHERS ตัว → ปฏิเสธทั้งชุด
	-- ⚠️ ไม่มีด่านให้ส่ง (ผ่านครบทุกด่าน / ด่านที่กำลังตี HP 0) → ปฏิเสธทั้งชุด
	-- แต่ละตัวผ่านแกนเดียวกับ SEND_MOTHER_TO_BATTLE_REQUEST (CombatService.handleSendMotherToBattle) ตามลำดับที่ส่ง
	-- ตัวที่ส่งไม่ได้ (ล็อก / ไม่ใช่ของตัวเอง / อยู่ในคอก / roster เต็ม / uid ซ้ำในชุด) ข้าม · roster ไม่เกินเพดาน
	-- sync ครั้งเดียวท้ายชุด · ผลสรุปครั้งเดียวทาง ACTION_RESULT (Config.formatSendBatchMessage)
	-- · client ต้องขึ้นกล่องยืนยันก่อนยิงทุกครั้ง · SEND_MOTHER_TO_BATTLE_REQUEST (ทีละตัว) ยังอยู่ ไม่ได้ลบ
	SEND_MOTHERS_TO_BATTLE_BATCH_REQUEST = "SendMothersToBattleBatchRequest",

	-- server → client : FireAllClients(kind: "night" | "day" | "killed") — Phase 5A วงจรบอส
	--   + FireClient(player, "locked") เฉพาะคนที่เพิ่งติดล็อกอัญเชิญ (พังกำแพงขณะบอสยังอยู่)
	-- ⚠️ เหตุการณ์ที่ server เริ่มเอง จึงแยกจาก ACTION_RESULT (หลักเดียวกับ STAGE_CLEARED_NOTIFY)
	-- ข้อความจริงอยู่ที่ Config.formatBossEventMessage(kind) · สถานะต่อเนื่อง (phase/เวลา/HP) ไม่ส่งทางนี้
	-- แต่อยู่ใน Attribute ของ ReplicatedStorage[Config.BOSS_STATE_FOLDER] (ทุกคนเห็นค่าเดียวกัน)
	-- ⚠️ การตีบอส **ไม่มี RemoteEvent** — ใช้ Tool.Activated ของอาวุธที่ server สร้างเอง (ยิงถึง server ในตัว)
	-- ⚠️ 5B เพิ่ม kind + ตัวเลขต่อท้าย (ตัวเลขมาจาก server เสมอ · signature (kind, a?, b?) ของเดิมยังใช้ได้):
	--   FireAllClients("heavy", น้ำหนัก) ตอนบอสเกิดถ้าไข่หนักเกิน HEAVY_EGG_ALERT_KG
	--   FireClient(player, "picked") · ("delivered", น้ำหนัก — เฉลยตอนเข้ากระเป๋า) · ("reward", เงินที่ได้, จำนวนคนแบ่ง) · "bagFull" · "eggLost"
	--   (5B-fix: "picked" ไม่มีน้ำหนักแล้ว — ให้ผู้เล่นลุ้น)
	--   · "pickupAlive" | "pickupCarrying" | "pickupTaken" | "pickupRange" (หยิบไม่สำเร็จ)
	-- ⚠️ 5B-2 (บอสทุกห้อง): "killed" มีเลขห้อง (a) · "locked" มีเลขห้อง (a) · "reward" มีเลขห้องเป็นตัวที่ 3 (c) ·
	--   "heavy" ส่ง**รายการ** { { room, weight } } ของทุกห้องที่มีไข่หนักเกินเกณฑ์ในข้อความเดียว (ไม่ใช่ตัวเลขเดียวแล้ว) ·
	--   หยิบไม่สำเร็จเพิ่ม "pickupAccess" (ยังพังกำแพงไม่ถึงห้องนั้น) · "pickupHold" (กดค้างไม่ครบ)
	BOSS_EVENT_NOTIFY = "BossEventNotify",

	-- client → server : PickUpBossEggRequest(eggIndex: number) — 5B หยิบไข่บอส (กด E ค้างที่ไข่ · UiKit.prompt)
	-- ⚠️ ส่งแค่ "กดที่ฟองไหน" · server ตัดสินเองทั้งหมด (บอสตายแล้วไหม · ฟองนั้นยังอยู่ไหม · ถืออยู่แล้วไหม ·
	--   ระยะจากตำแหน่งตัวละครที่ server เห็น) · index ไม่ใช่จำนวนเต็ม 1..EGGS_PER_NIGHT = ทิ้งเงียบ ๆ
	-- ⚠️ 5B-2: **ห้องไหน server ดูจากตำแหน่งตัวละครเอง** (Config.getStageRoomAt) ไม่รับเลขห้องจาก client ·
	--   ต้องมีสิทธิ์เข้าห้องนั้น (Config.canAccessBossRoom) · ต้องกดค้างครบตาม BOSS_EGG_HOLD_REQUEST (ข้างล่าง)
	PICK_UP_BOSS_EGG_REQUEST = "PickUpBossEggRequest",

	-- client → server : BossEggHoldRequest(eggIndex: number, holding: boolean) — 5B-2 ให้ server จับเวลากดค้างเอง
	--   true = เริ่มกดค้าง (ProximityPrompt.PromptButtonHoldBegan) · false = ปล่อยปุ่ม (PromptButtonHoldEnded)
	-- ⚠️ prompt เป็นของ client (UiKit.prompt) server จึงไม่เห็นการกดค้างเอง — client บอกจังหวะ server จดเวลา**ของ server**
	--   ตอนหยิบ (PickUpBossEggRequest) ต้องห่างจากจังหวะเริ่ม ≥ EGG_PICKUP_HOLD_SECONDS − EGG_PICKUP_HOLD_TOLERANCE
	--   ยิงหยิบตรง ๆ โดยไม่เคยเริ่ม / ปล่อยก่อนครบ / เริ่มแล้วยิงหยิบเร็วเกิน = ปฏิเสธ ("pickupHold")
	--   ค่าแปลก (index ไม่ใช่ 1..EGGS_PER_NIGHT · holding ไม่ใช่ boolean) = ทิ้งเงียบ ๆ
	BOSS_EGG_HOLD_REQUEST = "BossEggHoldRequest",
}

--------------------------------------------------------------------------------
-- DataStore
--------------------------------------------------------------------------------
-- ⚠️ เปลี่ยน NAME หรือ KEY_PREFIX = ผู้เล่นเก่าอ่านข้อมูลตัวเองไม่เจอ = เริ่มใหม่หมด

Config.DataStore = {
	NAME = "PlayerData_v1", -- ใช้ตอน publish จริง
	DEV_NAME = "PlayerData_dev_v1", -- ใช้ตอนทดสอบใน Studio จะได้ไม่เขียนทับข้อมูลจริง
	KEY_PREFIX = "player_", -- key เต็ม = KEY_PREFIX .. UserId (ลิมิตของ Roblox คือ 50 ตัวอักษร)

	-- ⚠️ เลือก store ด้วย `RunService:IsStudio()` **ไม่ใช่ธงที่ต้องสลับมือ**
	-- ธงที่ต้องสลับมือมีวันลืมสลับ แล้ววันนั้นคือวันที่เทสต์เขียนทับข้อมูลผู้เล่นจริง
	-- (ดู DataService.storeName)

	AUTOSAVE_INTERVAL = 60, -- เซฟอัตโนมัติทุกกี่วินาที (งบเขียน = 60 + ผู้เล่น×10 ต่อนาที)

	-- ⚠️ ผู้เล่นคนที่ N เลื่อนรอบเซฟออกไป N × ค่านี้ วินาที
	-- ไม่งั้น 6 คนที่เข้าพร้อมกันจะเซฟพร้อมกันทุกนาที = งบเขียนพีคเป็นก้อน
	-- 6 คน × 10 วิ = 50 วิ ซึ่งยังน้อยกว่า AUTOSAVE_INTERVAL จึงไม่มีใครถูกเลื่อนข้ามรอบ
	AUTOSAVE_STAGGER = 10,

	RETRY_COUNT = 3, -- ลองซ้ำกี่ครั้งรวมทั้งหมด (ทั้งโหลดและเซฟ)
	RETRY_BASE_DELAY = 2, -- หน่วงก่อนลองซ้ำครั้งแรก แล้วคูณสองไปเรื่อย ๆ (2 · 4 · 8)

	-- ⚠️ session lock กันผู้เล่นคนเดียวกันเปิดสองเซิร์ฟเวอร์พร้อมกัน
	-- ถ้าไม่มี: เซิร์ฟ A กับ B ต่างถือข้อมูลคนละชุด ใครเซฟทีหลังทับของอีกคนทั้งชุด
	-- อายุ 5 นาทีเพราะ autosave ทุก 60 วิ ต่อ lock ให้เรื่อย ๆ อยู่แล้ว
	-- ค้างเกิน 5 นาที = เซิร์ฟเวอร์นั้นดับไปแล้วจริง ๆ ปล่อยให้เข้าได้
	SESSION_LOCK_SECONDS = 300,

	-- ⚠️ BindToClose ของ Roblox ให้เวลาแค่ 30 วินาทีแล้วปิดเซิร์ฟทิ้ง
	-- เผื่อไว้ 25 เพื่อให้มีจังหวะ log ก่อนถูกตัด
	BIND_TO_CLOSE_SECONDS = 25,

	-- ⚠️ เซฟรอบสุดท้าย (ตอนออกเกม/ปิดเซิร์ฟ) ต้อง **รอ** รอบที่ค้างอยู่ให้จบก่อน ห้ามข้าม
	-- เคยเป็นบั๊กจริง: autosave ค้างอยู่ระหว่างยิงข้ามเน็ต ผู้เล่นกดออกพอดี
	-- เซฟรอบสุดท้ายเห็นว่า "กำลังเซฟอยู่แล้ว" เลยไม่ทำอะไรเลย แล้วข้อมูลถูกทิ้ง
	-- → ของที่ได้มาหลัง autosave รอบนั้นหายหมด และ session lock ก็ไม่ถูกปลดด้วย
	SAVE_WAIT_LIMIT = 10, -- รอรอบก่อนหน้าได้นานสุดกี่วินาที
	SAVE_WAIT_STEP = 0.2, -- เช็คซ้ำถี่แค่ไหนระหว่างรอ

	-- ⚠️ ลิมิตจริงของ Roblox คือ 4 MB ต่อ 1 key · ตั้งเพดานตัวเองไว้ที่ 3 MB
	-- เผื่อไว้เพราะตัวประเมินขนาดของเราไม่ใช่ตัว encode ตัวเดียวกับที่ Roblox ใช้จริง
	-- `PlayerData.validate()` วัดข้อมูลที่เต็มทุกเพดานแล้วเทียบกับค่านี้ตอนบูต
	MAX_PLAYER_DATA_BYTES = 3 * 1024 * 1024,

	-- ⚠️ UI-5: จำนวน PurchaseId ล่าสุดที่จำไว้กันให้ของซ้ำ (data.processedPurchaseIds)
	-- เก็บแบบ FIFO ต่อผู้เล่น — เกินแล้วตัดตัวเก่าสุดทิ้ง (ไม่ใช่ audit log ถาวร แค่กันซ้ำตอน retry)
	PROCESSED_PURCHASE_LOG_CAP = 200,
}

--------------------------------------------------------------------------------
-- Config.Balance — ลูกบิดสมดุลทั้งหมดอยู่ใต้ชื่อเดียว
--------------------------------------------------------------------------------
-- ⚠️ **ค่าที่ปรับแล้วเกมยากขึ้น/ง่ายขึ้น ต้องอยู่ใน Config.Balance เท่านั้น**
-- ส่วนที่อยู่นอก Balance คือของที่ปรับแล้วเกม "ไม่เหมือนเดิม" คนละแบบ:
-- id · schema · ชื่อ RemoteEvent · รูปทรงแมพ · รูปแบบ key — พวกนั้นแก้แล้วต้องเขียน migration
--
-- ที่ต้องแยกเพราะก่อนหน้านี้ลูกบิดสมดุลกับของที่ห้ามแตะนั่งปนกันอยู่ชั้นเดียวกัน
-- ใครเปิดไฟล์มาแล้วเห็น `Config.Pen` กับ `Config.Stack` เรียงติดกัน ไม่มีอะไรบอกเลยว่า
-- อันหนึ่งปรับได้ทุกวัน อีกอันแก้แล้วข้อมูลผู้เล่นอ่านไม่ออก
--
-- ⚠️ `validate()` บังคับสองทาง: ทุกกลุ่มใน BALANCE_GROUPS ต้องมีอยู่ใน Config.Balance
-- **และต้องไม่มีชื่อเดียวกันโผล่ที่ Config ชั้นบนสุด** — กันไม่ให้ใครเผลอเติมกลับเข้าไป
--
-- ⚠️ ชื่อคีย์ข้างในทุกตัว **คงเดิมทั้งหมด** (ONLINE_PER_MINUTE · STEPS_PER_STAGE ฯลฯ)
-- ย้ายแค่ที่อยู่ ไม่ได้เปลี่ยนชื่อ เพราะคีย์พวกนี้อยู่ในเอกสารสมดุลและในหัวคนทำงานแล้ว
local Balance = {}

-- ⚠️ รายชื่อกลุ่มที่ต้องอยู่ใน Balance — `validate()` เดินตามรายการนี้
-- เพิ่มกลุ่มสมดุลใหม่เมื่อไหร่ **ต้องเติมชื่อตรงนี้ด้วย** ไม่งั้นยามมองไม่เห็น
local BALANCE_GROUPS: { string } = {
	"StageWeightTiers", "Weight", "Production", "Damage", "NewPlayer",
	"Economy", "Pen", "Bag", "Hatchery", "Stages", "Stage",
	"DamageUpgrade", "SpeedUpgrade", "Combat", "BalanceCheck", "Weapon",
	"VisualScale", "RobuxBoost", "BossCycle",
}

-- กลุ่มที่ลบทิ้งแล้ว — validate() บังคับว่าห้ามโผล่กลับมา (ทั้งใน Config.Balance และชั้นบนสุด)
-- "Boss" = ดีไซน์ "บอสด่านละตัว รีเกิด 5 นาที · ไข่ 5 ฟอง" (ลบใน 5B · ค่าที่ยังใช้ย้ายไป BossCycle)
local REMOVED_BALANCE_GROUPS: { string } = { "Boss" }

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

-- ตารางสุ่มน้ำหนักแยกตามด่านของบอสที่ไข่ฟองนั้นมาจาก
--
-- ✅ **ตัดสินถาวรแล้ว: ทุกด่านใช้ตารางเดียวกัน ไม่ใช่ของค้างรอเติม**
--
-- เหตุผล: ถ้าด่านสูงให้แม่หนักกว่าด้วย เกมจะมีแกนไต่สองแกนพร้อมกัน
-- (น้ำหนัก ×1,000 ตลอดเกม + คลาส ×216) ซึ่งคุมสมดุลไม่ไหว
-- และที่แย่กว่านั้นคือ **น้ำหนักดี ๆ หายากเกินกว่าจะเป็นเส้นทางหลักได้**
-- (tier 6 = 1 ใน 111,111 ฟอง ที่อัตราไข่จริงคือหลักหมื่นชั่วโมง)
--
-- แกนที่ไต่ตามด่านจึงเป็น "คลาส" อย่างเดียว ผ่านตารางคลาสของไข่รายด่าน
-- ส่วนน้ำหนักเป็นมิติของ "ดวง" ที่ใช้ได้ตลอดเกมโดยไม่ผูกกับด่าน
--
-- โครง [stage] ยังคงไว้เพราะ getWeightTiers() กับไข่รายด่านเรียกใช้อยู่
-- และเผื่อวันหนึ่งอยากทำอีเวนต์ที่ด่านใดด่านหนึ่งสุ่มต่างออกไป
local StageWeightTiers: { [number]: { WeightTier } } = {
	[1] = WeightTiers,
}

Balance.StageWeightTiers = StageWeightTiers

Balance.Weight = {
	-- ลูกหนัก 1% ของแม่เสมอ
	-- ⚠️ ค่านี้ทำให้น้ำหนักลูกเป็นทศนิยมได้ (แม่ 999 → ลูก 9.99)
	-- จึงห้ามเอาน้ำหนักลูกไปสร้าง stack key ให้ใช้น้ำหนัก "แม่" ซึ่งเป็นจำนวนเต็มเสมอ
	CHILD_RATIO = 0.01,

	-- เพดานสัดส่วนน้ำหนักลูกหลังรวมโบนัสจากสถานะแล้ว
	-- 1.0 = ลูกหนักเท่าแม่ได้มากสุด ห้ามเกินเพราะจะขัดกับกติกา "ลูกคือลูกของแม่"
	MAX_CHILD_RATIO = 1,

	-- ผลรวม weight ของทุก tier ต้องเท่ากับค่านี้พอดี (validate() เช็คให้)
	TIER_ROLL_MAX = 1000000,

	TIERS = WeightTiers,
}

--------------------------------------------------------------------------------
-- ขนาดโมเดลไข่/แม่ตามน้ำหนัก
--------------------------------------------------------------------------------
-- ไข่กับแม่ scale ตามน้ำหนักด้วย **ตัวคูณชุดเดียวกัน** (คนละฐาน — ฐานคือ
-- MapDimensions.Blockout.EggSize / MotherSize ที่ tier 1) ตัวคูณจึงมาอยู่รวมกันที่นี่
-- แทนที่จะแยกเป็น EggVisualScale/MotherVisualScale สองตาราง (ค่าจะซ้ำกันเป๊ะทุกแถว
-- แก้ตัวหนึ่งแล้วลืมอีกตัวได้ง่าย) — ดู Config.getEggVisualSize / getMotherVisualSize
--
-- ⚠️ ต้องมี 7 ค่าตรงกับ 7 tier ใน WeightTiers เสมอ · validate() บังคับ
Balance.VisualScale = {
	-- tier 1..7 → ตัวคูณขนาด (100kg = ฐานเป๊ะ, 100M kg = ใหญ่กว่าฐาน 5.25 เท่า)
	WEIGHT_MULTIPLIER = { 1.00, 1.32, 1.74, 2.29, 3.02, 3.98, 5.25 },

	-- ขนาดแม่ในคอก (ฟาร์ม) เทียบกับตอน "ถือ" (กระเป๋า/เลือกตัว) หรือ "ส่งรบ" · ทุก tier เท่ากัน
	-- ไข่ไม่มีกฎนี้ (ไข่แสดงขนาดเดียวกันทุกที่ที่เห็น)
	-- เดิม 0.1 (ย่อ 1/10) → เปลี่ยนเป็น 1 (1:1) ตามที่ผู้ใช้สั่ง — ย่อแล้วโมเดลจริง (กอริลลา) เล็กเกินไป
	MOTHER_PEN_SHRINK = 1,

	-- ══ โมเดล mesh (Character.modelAssetId) ══ — กล่องสีไม่ใช้สองค่านี้
	-- ความสูงตอน tier 1 (studs) ไม่ว่าไฟล์ต้นฉบับ import มาขนาดไหน แล้วค่อยคูณ WEIGHT_MULTIPLIER
	-- 5 ≈ ความสูงตัวละครผู้เล่นปกติ (ผู้ใช้ขอให้ tier 1 ตัวเท่าคน)
	MOTHER_MESH_BASE_HEIGHT = 5,
	-- ความเร็วเดิน (studs/วิ) ของโมเดลขนาด tier 1 ตอนอนิเมชันเดินเล่นความเร็วปกติ
	-- ตัวใหญ่ขึ้น s เท่า → เดินเร็วขึ้น √s เท่า + อนิเมชันช้าลง √s เท่า → ระยะต่อก้าวโต s เท่า
	-- พอดีกับขนาดตัว (สัตว์จริงก็ขยายแบบนี้) · เท้าไถล = ค่านี้มากไป · ย่ำอยู่กับที่ = น้อยไป
	MOTHER_MESH_WALK_SPEED = 4,
}

--------------------------------------------------------------------------------
-- อัตราผลิตลูก
--------------------------------------------------------------------------------
-- แม่ 1 ตัวผลิตลูกอัตโนมัติ ลูกที่ได้หนัก 1% ของแม่ และคัดลอกชุดสถานะของแม่
-- ณ เวลาที่ผลิต (ดู docs/data-schema.md)
--
-- ทั้งออนไลน์และออฟไลน์คำนวณจาก timestamp ไม่ใช่ loop นับสด
-- เพื่อให้ผลลัพธ์เหมือนกันไม่ว่าเซิร์ฟเวอร์จะกระตุกหรือผู้เล่นจะออกไปนานแค่ไหน

Balance.Production = {
	-- อัตราผลิต = ONLINE_PER_MINUTE × (น้ำหนักแม่ ÷ WEIGHT_REFERENCE)^WEIGHT_EXPONENT
	--
	-- ⚠️ ทำไม exponent = 0.25 ไม่ใช่ 0.5
	-- น้ำหนักมีผลอยู่แล้ว 2 ทาง: เงิน (√) และ damage ต่อตัว (√)
	-- ถ้าอัตราผลิตใช้ √ ด้วย damage รวมต่อวันจะแปรผัน "ตรง" กับน้ำหนัก
	-- → ช่องว่างระหว่างแม่ 100 kg กับ 100M kg จะกลายเป็น 1,000,000 เท่า
	-- ใช้ 0.25 ได้ราว 31,623 เท่า — กว้างพอให้ตัวหนักคุ้มค่า แต่ไม่ถึงกับขาดกัน
	--
	--   100 kg → 1.0/นาที · 10,000 kg → 3.2 · 1M kg → 10 · 100M kg → 31.6
	ONLINE_PER_MINUTE = 1, -- อัตราฐานที่น้ำหนัก = WEIGHT_REFERENCE
	WEIGHT_REFERENCE = 100,
	WEIGHT_EXPONENT = 0.25,

	-- ตอนออฟไลน์ผลิตช้ากว่า 10 เท่า (เป็นสัดส่วนของอัตราออนไลน์ ไม่ใช่ค่าคงที่
	-- เพราะอัตราออนไลน์แปรตามน้ำหนักแล้ว)
	OFFLINE_RATE_RATIO = 0.1,

	-- ⚠️ ความจุคลังต่อ 1 กอง
	-- แม่ 1 ตัวที่น้ำหนักฐานผลิต ~1 ตัว/นาที → 500 ตัว ≈ 8 ชั่วโมง
	-- ตรงกับ cap ออฟไลน์ 8 ชั่วโมงพอดี ระบบจึงสม่ำเสมอกันทั้งเกม
	-- 500 ตัวปล่อยที่ 1 ตัว/วินาที = ระบายหมดใน ~8 นาที (นั่งดูได้จริง)
	-- คลังเต็ม → แม่ตัวนั้น **หยุดผลิต** + แจ้งเตือนผู้เล่น
	-- ⚠️ ตายตัว 500 ไม่มีระบบอัปเกรด (ตัดสินแล้ว)
	STACK_CAP = 500,

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
	-- ⚠️ ตัดจาก 10 เหลือ 5 ขั้น (ตัดสินแล้ว — ทางเลือก ก)
	--
	-- ตั้งแต่ด่าน 3 คอขวดเป็น "การปล่อย" ถาวร → upgrade นี้หยุดเพิ่ม damage
	-- เหลือประโยชน์แค่ "เติมคลังเร็วขึ้น" ซึ่งไม่คุ้มราคาที่ไต่ถึง 1e12
	--
	-- ที่ 5 ขั้น ผู้เล่นอ้างอิงยังผลิตเกินอัตราปล่อย 7.9-15.1 เท่าที่ด่าน 6-9
	-- (เดิมเกิน 3,327 เท่า ซึ่งไร้สาระ) และ **เวลาตีทุกด่านไม่เปลี่ยนเลย**
	-- เพราะคอขวดยังเป็นการปล่อยอยู่ดี — ตรวจแล้วทั้ง 9 ด่าน
	UPGRADE_MAX_LEVEL = 5,
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

-- ⚠️ ตัวเลขตัวคูณข้างล่างเป็น "ตัวอย่างรอปรับ" — ยังไม่มีผลเพราะ enabled = false
-- โครงพร้อมรับแล้ว ตอน Phase 6 แค่เปิด enabled แล้วปรับตัวเลข ไม่ต้องแตะ schema
local Statuses: { [string]: StatusType } = {
	gold = {
		id = "gold",
		name = "ทอง",
		order = 1,
		enabled = false,
		damageMultiplier = 2,
		coinMultiplier = 2,
		productionMultiplier = 1.5,
		childRatioBonus = 0.01, -- 1% → 2%
	},
	silver = {
		id = "silver",
		name = "เงิน",
		order = 2,
		enabled = false,
		damageMultiplier = 1.5,
		coinMultiplier = 1.5,
		productionMultiplier = 1.2,
		childRatioBonus = 0,
	},
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
-- uid ของตัวแม่
--------------------------------------------------------------------------------
-- ⚠️ โครงหลัก: uid เป็น **string แบบ global** ไม่ใช่ number ที่ไม่ซ้ำแค่ในผู้เล่นคนเดียว
--
-- รูปแบบ: "<UserId>-<เลขนับของเจ้าของคนแรก>"  เช่น "1234567-42"
--
-- ทำไมต้อง global: มีแผนจะทำเทรดแม่ระหว่างผู้เล่น
-- ถ้า uid ไม่ซ้ำแค่ในคนเดียว พอแม่ย้ายเจ้าของแล้ว uid จะไปชนกับแม่ของคนรับ
-- → ทีมที่จัดไว้จะชี้ผิดตัวทันที และแก้ทีหลังไม่ได้เพราะ uid ฝังอยู่ในทีมที่เซฟแล้ว
--
-- UserId ในนี้คือ "ผู้เล่นที่ฟักแม่ตัวนี้ออกมาครั้งแรก" ไม่ใช่เจ้าของปัจจุบัน
-- ห้ามเปลี่ยนตอนเทรด เพราะจุดประสงค์คือความไม่ซ้ำ ไม่ใช่การบอกเจ้าของ

Config.Uid = {
	SEPARATOR = "-",
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

Balance.Damage = Damage

--------------------------------------------------------------------------------
-- เพดานคลัง
--------------------------------------------------------------------------------
-- ตัวเลขพวกนี้เป็นข้อเสนอ รอยืนยัน — มีไว้กันข้อมูลบวมและกัน exploit
-- ต้องมีตั้งแต่วันแรก เพราะ "เพิ่ม" เพดานทีหลังง่าย แต่ "ลด" ทีหลังแปลว่าต้องยึดของผู้เล่น

Config.Inventory = {
	-- จำนวนแม่ทั้งหมดที่ถือได้ = Config.Balance.Bag.CAPACITY + ความจุคอกตามเลเวล
	-- (ค่าสองตัวนั้นเป็นแหล่งความจริง ตัวนี้เป็นเพดานกันพลาดอีกชั้น)
	MAX_MOTHERS = 200,

	-- จำนวน "กอง" ไม่ใช่จำนวนลูก
	-- กองแตกตาม (ตัวละคร 12 × น้ำหนักแม่ × ชุดสถานะ) จึงต้องเผื่อไว้เยอะกว่าเดิม
	MAX_CHILD_STACKS = 2000,

	-- ⚠️ ที่ด่าน 9 อัตราผลิตเต็ม ผู้เล่นผลิตลูกได้ระดับแสนล้านตัวต่อวัน
	-- ค่าเดิม 1e9 ล้นแน่นอน ตั้งที่ 1e15 เพราะ Luau เก็บจำนวนเต็มแม่นยำถึง 9e15
	MAX_CHILDREN_PER_STACK = 1000000000000000,

	MAX_HELD_EGGS_PER_TYPE = 999,

	-- ⚠️ ค่ากลุ่ม MAX_TEAM* เป็นดีไซน์ "ทีม" ยุคก่อน Age of War ที่ไม่เคยเขียนเป็นโค้ด
	-- **ถูกแทนด้วย battleRoster แล้ว** (Phase 3C-1 · เพดานอยู่ที่ Balance.Combat.MAX_BATTLE_MOTHERS)
	-- ยังไม่ลบเพราะ Inventory เป็นโครงหลัก — ไม่มีโค้ดไหนอ่านค่าพวกนี้แล้ว
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

-- [eggId] = จำนวน — แถมไข่ให้ลองฟักทันที
-- ⚠️ เป็นแค่ "คำสั่งแจกไข่" ไม่ใช่รูปแบบที่เก็บใน PlayerData
-- ตอนแจกจริง server ต้องสุ่มน้ำหนักให้ไข่แต่ละฟองด้วย rollMotherWeightForEgg()
-- แล้วเก็บเป็นรายฟอง (ดู docs/data-schema.md §3 — heldEggs เป็นอาเรย์ ไม่ใช่ตัวนับ)
-- ⚠️⚠️ TEMP: 100 ฟองเป็นค่าทดสอบชั่วคราวสำหรับทดสอบบนเกมจริงเท่านั้น (Phase 2B)
-- เพื่อให้มีแม่/ไข่พอกระจายทุก tier น้ำหนักให้ทดสอบขนาดโมเดล/เวลาฟัก/ผลิต/ขายได้จริง
-- โดยไม่ต้องพึ่งการแย่งไข่จากบอส (ยังไม่มีในเกม) **ต้อง revert กลับเป็น 1 ก่อน publish จริง**
-- (ดู CLAUDE.md หัวข้อ "โครงหลัก" — มีเตือนไว้อีกจุดกันลืมตอน Phase 7)
local startingEggs: { [string]: number } = {
	egg_stage1 = 100,
}

Balance.NewPlayer = {
	coins = 500, -- ซื้อไข่ธรรมดาได้ 5 ฟอง
	gems = 0,
	startingEggs = startingEggs,

	-- ด่านที่ยืนอยู่ = กำแพงที่พังแล้ว + 1 → ผู้เล่นใหม่อยู่ด่าน 1
	-- ⚠️ ต้องเป็น 1 ไม่ใช่ 0 ไม่งั้นเพดาน upgrade damage (wallProgress × STEPS_PER_STAGE)
	-- จะกลายเป็น 0 แล้วผู้เล่นใหม่ซื้ออะไรไม่ได้เลย (ดู getMaxDamageLevel)
	wallProgress = 1,

	-- ขั้นความเร็วที่ซื้อแล้ว — เริ่มที่ 0 = วิ่งที่ MapDimensions.Player.WalkSpeed เฉย ๆ
	-- ⚠️ เป็นของบัญชี ไม่ใช่ของตัวละคร ตายแล้วเกิดใหม่ต้องได้ความเร็วเดิมกลับมา
	speedLevel = 0,
}

--------------------------------------------------------------------------------
-- ลำดับความหายาก
--------------------------------------------------------------------------------
-- ⚠️ เลิกใช้แล้วตอน Phase 1.5 — ระบบจริงใช้คลาส SS/S/A/B/C (Config.CharacterClasses)
-- เก็บไว้เพราะ UnitTypes ที่ปิดไปยังอ้างถึงอยู่ ห้ามลบตามกฎ id

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

-- ⚠️ ตัวคูณคลาส = "แกนที่ไต่ตามด่าน" ของเกมนี้
--
-- ตารางสุ่มน้ำหนักเหมือนกันทุกด่าน (ตัดสินถาวรแล้ว) ด่านสูงจึงไม่ได้ให้แม่หนักกว่า
-- สิ่งที่ด่านสูงให้คือ "โอกาสได้คลาสดีกว่า" → คลาสต้องรับภาระเป็นตัวไต่ทั้งหมด
-- ไล่ ×6 ต่อขั้นจาก C ถึง S (1 → 6 → 36 → 216)
--
-- ⚠️⚠️ SS ตั้งไว้แค่ ×2 เหนือ S โดยตั้งใจ ไม่ใช่ ×6 — ห้ามแก้เป็น 1,296
--
--   SS ออกจากไข่ Robux เท่านั้น ถ้าไล่ ×6 ต่อไปจนถึง 1,296 คนจ่ายเงินจะแรงกว่า
--   คนไม่จ่าย 1,296 เท่า = pay-to-win เต็มรูปแบบ เกมจะตายเพราะคนไม่จ่ายเลิกเล่น
--   บีบให้ห่างจาก S แค่เท่าตัว → ไข่ตำนานยังคุ้มซื้อ (ได้ ×2 บวกกับรับประกัน tier 3+)
--   แต่ไม่ถึงกับ "ซื้อแล้วชนะ" เพราะ S หาได้ฟรีจากบอสด่าน 7 ขึ้นไป
--
--   validate() บังคับว่า SS ÷ S ต้องไม่เกิน MAX_SS_OVER_S_RATIO (2.5) — เกินแล้วเซิร์ฟไม่บูต
local CharacterClasses: { [string]: CharacterClass } = {
	SS = { id = "SS", multiplier = 432, order = 1 }, -- = S × 2 เท่านั้น (ดูบล็อกข้างบน)
	S = { id = "S", multiplier = 216, order = 2 },
	A = { id = "A", multiplier = 36, order = 3 },
	B = { id = "B", multiplier = 6, order = 4 },
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
	-- modelAssetId = โมเดลลิง (Model asset ที่ผู้ใช้ publish เอง · แทนกอริลลาเดิม ดู CLAUDE.md)
	monkey = {
		id = "monkey",
		name = "ลิง",
		class = "C",
		enabled = true,
		modelAssetId = 109724272624838,
		animationIds = { walk = 107531970151372, idle = 120196087973871, punch = 108427117124537 },
	},
	pig = { id = "pig", name = "หมู", class = "C", enabled = true },
	horse = { id = "horse", name = "ม้า", class = "C", enabled = true },
	fish = { id = "fish", name = "ปลา", class = "C", enabled = true },
}

Config.Characters = Characters

-- ลำดับตัวละครในดัชนี (UI-4) — ตาราง Characters เป็น dictionary ไม่มีลำดับ จึงเขียนลำดับไว้ที่นี่
-- = ลำดับที่เขียนในตารางข้างบน · ดัชนีจัดกลุ่มตามคลาสก่อน แล้วเรียงในกลุ่มตามลำดับนี้
-- ⚠️ validate() บังคับว่ามีตัวละครครบทุกตัว ตัวละครละครั้งเดียว (เพิ่มตัวละครใหม่ต้องเติมที่นี่ด้วย)
Config.CharacterOrder = {
	"yulai",
	"guanyin",
	"jade_emperor",
	"tang",
	"wukong",
	"bajie",
	"wujing",
	"dragon_horse",
	"monkey",
	"pig",
	"horse",
	"fish",
} :: { string }

--------------------------------------------------------------------------------
-- ไข่ชนิดไหนออกตัวละครคลาสไหนได้
--------------------------------------------------------------------------------
-- ไข่ทุกชนิดใช้ "ตาราง tier น้ำหนักชุดเดียวกัน" (Config.Balance.Weight.TIERS)
-- ความต่างของไข่อยู่ที่คลาสตัวละครที่ออกได้ ซึ่งเป็นตัวคูณ damage/HP โดยตรง
--
-- กติกา:
--   ไข่จากบอส   ออกได้ตั้งแต่ C ถึง S — **ไม่มี SS**
--                ไข่ธรรมดา C/B/A · ไข่หายากตัด C ออกและเพิ่ม S
--   ไข่ตำนาน    (Robux) ตัด C ออก · มีทั้ง S และ SS
--                **SS ออกได้จากไข่ตำนานเท่านั้น**
--
-- weight เป็นจำนวนเต็มต่อ 10,000 (validate() บังคับผลรวมให้เท่ากับ CLASS_ROLL_MAX)
-- สุ่ม 2 ขั้นเหมือนน้ำหนัก: สุ่มคลาสก่อน แล้วค่อยสุ่มตัวละครในคลาสนั้นแบบเท่า ๆ กัน
--
-- ⚠️ ไข่จากบอส "คนละใบต่อด่าน" — ด่านสูงออกคลาสสูงบ่อยขึ้น
-- นี่คือสิ่งเดียวที่ต่างกันระหว่างด่าน ตารางสุ่ม "น้ำหนัก" ใช้ชุดเดียวกันทุกด่าน
-- (ความคุ้มของการไต่ด่านจึงมาจากโอกาสได้คลาสดี ไม่ใช่โอกาสได้ตัวหนัก)

Config.CLASS_ROLL_MAX = 10000

local EggCharacterPools: { [string]: { ClassChance } } = {
	egg_common = {
		{ class = "C", weight = 8000 }, -- 80%
		{ class = "B", weight = 1800 }, -- 18%
		{ class = "A", weight = 200 }, -- 2%
	},
	egg_rare = {
		{ class = "B", weight = 7000 }, -- 70%
		{ class = "A", weight = 2700 }, -- 27%
		{ class = "S", weight = 300 }, -- 3%   ← เพดานของไข่จากบอส
	},
	egg_stage1 = {
		{ class = "C", weight = 9000 }, -- 90%
		{ class = "B", weight = 1000 }, -- 10%
	},
	egg_stage2 = {
		{ class = "C", weight = 8000 }, -- 80%
		{ class = "B", weight = 2000 }, -- 20%
	},
	egg_stage3 = {
		{ class = "C", weight = 7000 }, -- 70%
		{ class = "B", weight = 2990 }, -- 29.9%
		{ class = "A", weight = 10 }, -- 0.1%
	},
	egg_stage4 = {
		{ class = "C", weight = 6000 }, -- 60%
		{ class = "B", weight = 3900 }, -- 39%
		{ class = "A", weight = 100 }, -- 1%
	},
	egg_stage5 = {
		{ class = "C", weight = 5000 }, -- 50%
		{ class = "B", weight = 4500 }, -- 45%
		{ class = "A", weight = 500 }, -- 5%
	},
	egg_stage6 = {
		{ class = "C", weight = 4000 }, -- 40%
		{ class = "B", weight = 5000 }, -- 50%
		{ class = "A", weight = 1000 }, -- 10%
	},
	egg_stage7 = {
		{ class = "C", weight = 3000 }, -- 30%
		{ class = "B", weight = 4500 }, -- 45%
		{ class = "A", weight = 2400 }, -- 24%
		{ class = "S", weight = 100 }, -- 1%
	},
	egg_stage8 = {
		{ class = "C", weight = 2000 }, -- 20%
		{ class = "B", weight = 3000 }, -- 30%
		{ class = "A", weight = 4000 }, -- 40%
		{ class = "S", weight = 1000 }, -- 10%
	},
	egg_stage9 = {
		{ class = "C", weight = 1000 }, -- 10%
		{ class = "B", weight = 2000 }, -- 20%
		{ class = "A", weight = 5000 }, -- 50%
		{ class = "S", weight = 2000 }, -- 20%
	},
	egg_legendary = {
		{ class = "B", weight = 3500 }, -- 35%
		{ class = "A", weight = 4500 }, -- 45%
		{ class = "S", weight = 1800 }, -- 18%
		{ class = "SS", weight = 200 }, -- 2%   ← ออกได้จากไข่ตำนานเท่านั้น
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

Balance.Economy = {
	BASE_PER_MINUTE = 1, -- แม่น้ำหนัก REFERENCE_WEIGHT ที่ด่าน 1 ได้กี่ coins/นาที
	REFERENCE_WEIGHT = 100,
	EXPONENT = 0.5, -- ถดถอยแบบรากที่สอง (ชุดเดียวกับสูตร damage)
	STAGE_MULTIPLIER = 10, -- ตัวคูณเงินต่อ 1 ด่านที่พังกำแพงได้

	-- ราคาขายแม่ = รายได้ของแม่ตัวนั้นคูณจำนวนนาทีนี้
	-- ผูกกับสูตรเงินอัตโนมัติ ไม่ต้องตั้งตารางแยก
	SELL_MOTHER_MINUTES = 30,

	----------------------------------------------------------------------------
	-- เงินจากการฆ่า (บ่อเงินที่สอง นอกเหนือจากแม่ในคอก)
	----------------------------------------------------------------------------
	-- ⚠️ server เป็นคนคำนวณและมอบเงินเท่านั้น ห้าม client แจ้งยอดมาเอง
	--
	-- ทหารฝ่ายรับ: KILL_DEFENDER_BASE × KILL_DEFENDER_MULTIPLIER^(ด่าน-1) ต่อตัว
	--   จำนวนทหารโต ×10 ต่อด่านอยู่แล้ว เงินต่อตัวโตอีก ×2
	--   → เงินรวมทั้งด่านโต ×20 ต่อด่าน ซึ่งเร็วกว่าราคาของที่โต ×10
	--   → บ่อนี้ไม่ตกยุค (validate() บังคับข้อนี้ไว้)
	--
	-- ⚠️ ทหารฝ่ายรับตายแล้วไม่เกิดใหม่ และ stageProgress เซฟความคืบหน้าถาวร
	--   ทหาร 1 ตัวจึงจ่ายเงินได้ "ครั้งเดียวตลอดกาล" ต่อผู้เล่น 1 คน
	--   ห้ามจ่ายซ้ำตอนโหลดข้อมูลกลับมา (ดู docs/data-schema.md §12)
	KILL_DEFENDER_BASE = 100,
	KILL_DEFENDER_MULTIPLIER = 2,

	-- บอส: KILL_BOSS_BASE × KILL_BOSS_MULTIPLIER^(ด่าน-1) ต่อการฆ่า 1 ครั้ง
	--   ใช้ ×10 ไม่ใช่ ×2 เพราะบอสฆ่าซ้ำได้เรื่อย ๆ (เกิดใหม่ทุกคืน — รอบละ getBossCycleSeconds())
	--   ⚠️ 5B-2: บอสห้อง N จ่ายตามสูตรนี้จริงแล้ว (Config.getBossKillReward(N) · แบ่งเท่ากันปัดลง) — ค่าชั่วคราว จูน Phase 6
	--   ต้องตามราคาของที่โต ×10 ให้ทัน ไม่งั้นบอสกลายเป็นเศษเงินตั้งแต่กลางเกม
	--
	KILL_BOSS_BASE = 10000,
	KILL_BOSS_MULTIPLIER = 10,

	-- ⚠️ บอสช่วยกันฆ่าได้ทั้งเซิร์ฟ — **แบ่งเท่ากันทุกคนที่ร่วมตี** (ตัดสินแล้ว)
	--
	-- ไม่แบ่งตามสัดส่วน damage เพราะการตีบอสใช้เวลาไม่นาน และการตีบอสเป็นแค่กิมมิค
	-- กลไกจริงของเกมคือการแย่งไข่ ไม่ต้องซีเรียสกับความยุติธรรมของส่วนแบ่งขนาดนั้น
	--
	-- ผลข้างเคียงที่รับได้: คนที่ตีครั้งเดียวตอนบอสใกล้ตายก็ได้ส่วนแบ่งเต็ม
	-- แลกกับที่ผู้เล่นใหม่ (อาวุธอ่อน) ยังได้เงินจากบอสด่านสูงที่คนอื่นตี
	BOSS_REWARD_SPLIT_EQUALLY = true,

	-- ต้องทำ damage ให้บอสอย่างน้อยเท่านี้ถึงนับว่า "ร่วมตี"
	-- กันคนที่ยืนเฉย ๆ ในพื้นที่บอสแล้วได้เงินฟรี
	BOSS_REWARD_MIN_DAMAGE = 1,
}

--------------------------------------------------------------------------------
-- คอก (Pen) — พื้นที่ให้แม่อยู่แล้วผลิตลูกและผลิตเงิน
-- ⚠️ ความจุคือ "กี่ตัว" ไม่ใช่ "กี่ช่อง" — คอกเป็นพื้นที่เปิดโล่ง แม่เดินอิสระ (ดู docs/map-layout.md)
--------------------------------------------------------------------------------
-- ความจุ = BASE_CAPACITY + (level - 1)   →  Lv1 = 5 ตัว, Lv15 = 19 ตัว
-- ค่าอัปเกรด Lv N → N+1 = UPGRADE_BASE_COST × UPGRADE_COST_MULTIPLIER ^ (N-1)

Balance.Pen = {
	BASE_CAPACITY = 5,
	CAPACITY_PER_LEVEL = 1,

	-- ⚠️ ตัดจาก 15 เหลือ 10 ขั้น (ตัดสินแล้ว — ทางเลือก ก)
	-- เลเวล 11-15 เป็น "ของตายในตาราง": ราคาไต่ถึง 1e17 ขณะที่รายได้ทั้งด่าน 9
	-- มีแค่ 1.28e14 → ไม่มีผู้เล่นคนไหนไปถึงได้เลย เป็นแค่ตัวเลขหลอกตา
	-- ตัดทิ้งแล้วราคารวมทั้งสายลดจาก 1e17 เหลือ 1.1e12 (ถูกลง ~90,000 เท่า)
	-- ความจุที่ผู้เล่นอ้างอิงใช้จริงคือ 5-13 ตัว (ด่าน 1-9) ซึ่งยังอยู่ในเพดานใหม่สบาย ๆ
	MAX_LEVEL = 10,
	UPGRADE_BASE_COST = 1000,
	UPGRADE_COST_MULTIPLIER = 10,
}

--------------------------------------------------------------------------------
-- กระเป๋า (Bag) — ที่เก็บแม่ที่ไม่ได้วาง ไม่ผลิตอะไรเลย
--------------------------------------------------------------------------------
-- นับแยกจากคอก: ถือได้รวมสูงสุด CAPACITY + ความจุคอก

Balance.Bag = {
	CAPACITY = 100,
}

--------------------------------------------------------------------------------
-- ไข่: กระเป๋าไข่ และ สวนฟัก (Hatchery)
--------------------------------------------------------------------------------
-- ไข่ที่แย่งมาจากรังบอสเดินทางผ่านสองที่ ตามลำดับนี้
--
--   แย่งไข่จากรัง → กระเป๋าไข่ (heldEggs) → สวนฟัก (hatching) → ฟักได้ตัวแม่
--                     BAG_CAPACITY ฟอง      MAX_SLOTS ฟอง
--
-- ⚠️ **เป็นเพดานคนละตัว ห้ามเอากลับมารวมกัน**
-- เคยใช้ค่าเดียวกันทั้งสองที่ ซึ่งบังเอิญเท่ากันเฉย ๆ ไม่ใช่เพราะต้องเท่า
-- ผูกไว้แบบนั้นแล้วปรับแยกไม่ได้เลย ทั้งที่สองอย่างนี้คุมคนละเรื่อง:
--   BAG_CAPACITY — คุมว่า "แย่งไข่ตุนไว้ได้แค่ไหน" (เกี่ยวกับรอบรีเกิดบอส 5 นาที)
--   MAX_SLOTS    — คุมว่า "ฟักพร้อมกันได้กี่ฟอง" (เกี่ยวกับเวลาฟัก 30 วิ × เลขด่าน)
-- ตอนนี้ตั้งเท่ากันไว้ก่อนที่ 50 เพื่อไม่ให้พฤติกรรมเปลี่ยน แต่ขยับแยกกันได้แล้ว
--
-- ทั้งสองเต็มแล้วหยิบไข่เพิ่มไม่ได้ ต้องแจ้งเตือนผู้เล่น

Balance.Hatchery = {
	-- จำนวนไข่ที่ถือติดตัวได้ ยังไม่เข้าสวนฟัก (PlayerData.heldEggs)
	-- ⚠️ เคยขึ้นไปถึง 10,000 ตอน Phase 2A (ทำได้เพราะ `heldEggs` เลิกเป็นอาเรย์ยาวคงที่แล้ว
	-- โครงเดิมเขียน `false` ให้ครบความยาวทุกครั้งที่เซฟ → ที่ 10,000 คือ ~62 KB ต่อให้ผู้เล่น
	-- ถือไข่จริง 3 ฟอง · โครงใหม่เก็บเฉพาะฟองที่มีจริง ~200 B) — ภายหลังลดลงมาที่ 1,000
	-- ⚠️ UI ต้อง virtualize ลิสต์นี้ ห้ามสร้าง GUI element ตามจำนวนไข่ตรง ๆ
	BAG_CAPACITY = 1000,

	-- จำนวนไข่ที่ฟักพร้อมกันได้ = จำนวนแท่นในสวนฟัก (PlayerData.hatching)
	MAX_SLOTS = 50,

	-- ⚠️ `EggTypes[eggId].hatchTime` ของไข่รายด่านยังคงสูตร SECONDS_PER_STAGE × เลขด่านไว้
	-- (ด่าน 1 = 30 วิ · ด่าน 9 = 270 วิ) และ validate() ยังบังคับสูตรนี้เหมือนเดิม
	-- แต่ค่านี้ **ไม่ใช่เวลาฟักจริงของไข่รายด่านอีกต่อไป** ตั้งแต่เพิ่มระบบเวลาฟักตามน้ำหนัก+คลาส —
	-- เก็บไว้เป็น metadata/ประวัติเท่านั้น (ลบออกไปเลยเป็นการรื้อ field ที่ core-locked ไว้
	-- ใน CLAUDE.md แยกต่างหาก ไม่ได้อยู่ในขอบเขตงานนี้)
	SECONDS_PER_STAGE = 30,

	-- ⚠️ เวลาฟักจริงของไข่ source="boss" (ไข่รายด่านทั้ง 9) มาจากตารางนี้แทน:
	-- tier น้ำหนัก 1..7 → เวลาฐาน (วินาที) ของคลาส C แล้วคูณด้วย ClassHatchMultiplier
	-- ดู Config.getHatchSeconds() · ต้องมี 7 ค่าตรงกับ 7 tier ใน WeightTiers เสมอ · validate() บังคับ
	HatchTimeByTier = {
		60, -- tier 1 (100-999 kg)     = 1 นาที
		300, -- tier 2 (1K-9.9K)        = 5 นาที
		1800, -- tier 3 (10K-99K)        = 30 นาที
		7200, -- tier 4 (100K-999K)      = 2 ชม.
		28800, -- tier 5 (1M-9.9M)        = 8 ชม.
		57600, -- tier 6 (10M-99M)        = 16 ชม.
		86400, -- tier 7 (100M คงที่)     = 24 ชม.
	},

	-- ตัวคูณเวลาฟักตามคลาสที่จะฟักออกมา (รู้ผลตอนวางไข่ลงสวนฟัก ไม่ใช่ตอนฟักเสร็จ —
	-- ดูคอมเมนต์ที่ EggService.placeEgg) · ต้องมีครบทุกคลาสใน CharacterClasses · validate() บังคับ
	ClassHatchMultiplier = {
		C = 1,
		B = 1.15,
		A = 1.35,
		S = 2,
		SS = 2.6,
	},

	-- เพดานกันตั้งเลขพลาดใน HatchTimeByTier/ClassHatchMultiplier จนเวลาฟักยาวเวอร์
	-- (เช่น tier 7 × SS = 24 ชม. × 2.6 = 62.4 ชม. ต้องไม่เกินนี้) · validate() บังคับ
	MAX_HATCH_SECONDS = 7 * 24 * 3600, -- 7 วัน

	-- ไข่ตำนานไม่ผูกด่านและไม่ผูก tier/คลาส จึงมีเวลาฟักคงที่ของตัวเอง (EggTypes.hatchTime
	-- ของ egg_legendary ใช้ค่านี้ตรง ๆ) — ⚠️ ตั้งใจให้ "จ่ายเงินจริงซื้อความเร็ว":
	-- เร็วกว่าไข่ tier 1 (60 วิ) พอดี ไม่ใช่ 300 วิเหมือนก่อนเพิ่มระบบเวลาฟักตามน้ำหนัก+คลาส
	-- (ตอนนั้น 300 ตั้งใจให้ "ยาวกว่าด่าน 9" — ฐานเปลี่ยนไปแล้วเพราะด่าน 9 ตอนนี้ฟักได้ถึง 62.4 ชม.)
	LEGENDARY_SECONDS = 60,
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

-- ตารางประจำด่าน — แก้ทีละด่านได้โดยไม่กระทบด่านอื่น
-- จำนวนทหารมาจากกติกา ×10 ต่อด่าน แต่เก็บเป็นตารางไม่ใช่สูตร
-- เพื่อให้ปรับด่านใดด่านหนึ่งตอน balance ได้โดยไม่ต้องรื้อทั้งแถว
--
-- ⚠️ ตารางนี้ **ไม่มี turretDps แล้ว** — ดูเหตุผลที่ Config.Balance.Combat.TURRET_TOLL
local Stages: { StageDef } = {
	-- ⚠️ ด่าน 1 ไม่มีกำแพงและไม่มีทหารฝ่ายรับ
	-- เป็นด่านเริ่มต้น ผู้เล่นเดินไปสู้บอสตัวเล็กเอาไข่ได้เลยตั้งแต่เข้าเกมครั้งแรก
	-- แก้ปัญหาไก่กับไข่: ต้องมีแม่ถึงจะมีกองทัพ ต้องมีไข่ถึงจะมีแม่
	{ id = 1, defenders = 0 },
	{ id = 2, defenders = 100 },
	{ id = 3, defenders = 1000 },
	{ id = 4, defenders = 10000 },
	{ id = 5, defenders = 100000 },
	{ id = 6, defenders = 1000000 },
	{ id = 7, defenders = 10000000 },
	{ id = 8, defenders = 100000000 },
	{ id = 9, defenders = 1000000000 },
}

Balance.Stages = Stages

Balance.Stage = {
	COUNT = 9,

	DEFENDER_HP = 100, -- HP ต่อทหารฝ่ายรับ 1 ตัว
	DEFENDER_DAMAGE = 10, -- damage ที่ทหารฝ่ายรับ 1 ตัวตีกลับใส่กองทัพเรา

	WALL_HP_RATIO = 0.5, -- HP กำแพง = สัดส่วนนี้ของ HP ทหารรวมในด่านนั้น

	-- ลำดับการตี: ทหารฝ่ายรับหมดก่อน แล้วค่อยตีกำแพงได้
	SEQUENTIAL_TARGETING = true,

	DISPLAY_MODELS_MIN = 20, -- จำนวนโมเดลที่แสดงตอน HP เหลือน้อยสุด (แต่ยังไม่หมด)
	DISPLAY_MODELS_MAX = 50, -- จำนวนโมเดลที่แสดงตอน HP เต็ม
}

--------------------------------------------------------------------------------
-- บอสและการแย่งไข่ — Phase 5A/5B วงจรกลางวัน/กลางคืน · 5B-2 บอสทุกห้อง
--------------------------------------------------------------------------------
-- ⚠️ ดีไซน์ใหม่ (ผู้ใช้ยืนยันแล้ว): รอบละ DAY + NIGHT วินาที · กลางคืนบอสเกิดพร้อมไข่ EGGS_PER_NIGHT ฟอง
-- ⚠️ 5B-2: **บอส 1 ตัวต่อห้องด่าน ครบ 9 ห้อง** (เดิม 5A/5B = บอสกลางตัวเดียวที่ห้องด่าน 1) · แผนเต็มใน docs/boss-plan.md
--   ต้นกลางคืน บอสทั้ง 9 ห้องเกิดพร้อมกัน (ตัวที่ยังไม่ตาย = ฟื้น HP เต็ม) · ไข่ทุกห้องรีเซ็ตเป็น 6 ฟองใหม่
--   แต่ละห้องมี HP / บันทึกดาเมจ / สถานะตาย-เป็น / ไข่ ของตัวเอง
--   HP ห้อง N = Config.getBossHp(N) (โมเดลสมดุล: BOSS_HP_BASE × BOSS_HP_MULTIPLIER^(N-1) ผูกอาวุธ ×10)
--   เงินห้อง N = Config.getBossKillReward(N) (โมเดลสมดุล: Economy.KILL_BOSS_BASE × ×10^(N-1))
--   ไข่ห้อง N = Config.getBossEggId(N) = egg_stageN (ตารางคลาสไข่รายด่านเดิม · ตารางน้ำหนักชุดเดียวทุกด่าน)
--   ⚠️ ทั้งหมดเป็นค่าชั่วคราว จูนจริง Phase 6 · ลบ BOSS_HP / KILL_REWARD / EGG_ID (ค่าห้องเดียวของ 5A/5B) แล้ว
-- ⚠️ 5B: **ลบ `Balance.Boss` ชุดเก่าแล้ว** (ดีไซน์ "บอสด่านละตัว รีเกิด 5 นาที · ไข่ 5 ฟอง") — ค่าที่ยังใช้จริงย้ายมาที่นี่:
--   RESPAWN_SECONDS / EGGS_PER_SPAWN → MODEL_BOSS_SPAWN_SECONDS / MODEL_EGGS_PER_SPAWN (**โมเดลสมดุลเท่านั้น** ตัวเลขเดิม)
--   EGG_GRAB_HOLD_SECONDS → EGG_PICKUP_HOLD_SECONDS
--   HP_BASE / HP_MULTIPLIER → BOSS_HP_BASE / BOSS_HP_MULTIPLIER (สเกลบอสต่อด่าน ผูกกับอาวุธ ×10 — validate())
-- เซิร์ฟเปิดใหม่เริ่มที่ต้นกลางวันเสมอ · **ไม่เซฟ DataStore** (สถานะไข่/คนถือไข่ก็ไม่เซฟ)
-- กลางคืน: วาปคนที่อยู่ในสนามรบมาหน้าป้อม (5B-fix) · กำแพงกั้นขึ้น · บอสทุกห้องเกิด (ตัวเก่ายังไม่ตาย = ฟื้น HP เต็ม) · ไข่ชุดใหม่
-- กลางวัน: กำแพงกั้นหาย เข้าไปตีบอสห้องที่มีสิทธิ์ได้ · บอสตายแล้วไม่เกิดจนคืนถัดไป · บอสห้องไหนตาย ไข่ห้องนั้นถึงหยิบได้
-- ⚠️ server เป็นคนตัดสินเจ้าของไข่เท่านั้น ห้าม client ตัดสินเด็ดขาด
Balance.BossCycle = {
	DAY_SECONDS = 540, -- 9 นาที
	NIGHT_SECONDS = 60, -- 1 นาที (ตัวเลขนับถอยหลัง 59 → 0 บนกำแพงกั้น)

	-- สเกล HP บอสต่อด่าน (ย้ายจาก Balance.Boss) — HP ด่าน N = BASE × MULTIPLIER^(N-1) · 5B-2: บอสห้อง N ใช้ค่านี้จริงแล้ว (Config.getBossHp)
	-- ⚠️ 5C: ดาเมจกระบอง**คำนวณจาก HP นี้** (Balance.Weapon · Config.getClubDamage) — แก้ HP แล้วกระบองขยับตามเอง
	--   (เดิม "อาวุธ ×10 ต่อขั้น ตี 10 ครั้งพอดี" ยกเลิกแล้ว → ขั้น N ตีห้อง N คนเดียวราว 3 นาที)
	BOSS_HP_BASE = 100,
	BOSS_HP_MULTIPLIER = 10,

	-- ⚠️⚠️ **ค่าของโมเดลสมดุล (ยาม validate + เทสต์) ไม่ใช่วงจรจริง** — ย้ายจาก Balance.Boss ตัวเลขเดิมเป๊ะ
	-- วงจรจริงคือบอสเกิดคืนละครั้ง (getBossCycleSeconds = 600 วิ) · ไข่ EGGS_PER_NIGHT = 6 ฟอง
	-- ลองเปลี่ยนโมเดลให้อ่านวงจรจริงแล้ว (5B): validate() ยังผ่าน แต่ไข่/คน/ชม. 10 → 6 · เงินบอสในโมเดลหายครึ่ง
	--   → ราคาอัปดาเมจกินรายได้ 35% → 51–63% · ส่วนเกินเงินด่าน 2–4 เหลือ 1.13–1.35 เท่า (เทสต์ต้องการ ≥ 1.5)
	--   = **เปลี่ยนสมดุล** ซึ่งไม่ได้สั่ง จึงคงตัวเลขเดิมไว้ก่อน · ผู้ใช้ตัดสินแล้ว (5B-2): **รอจูนใน Phase 6 ห้ามแตะตอนนี้**
	MODEL_BOSS_SPAWN_SECONDS = 300,
	MODEL_EGGS_PER_SPAWN = 5,

	-- ⚠️ ค่าชั่วคราวทั้งหมดข้างล่าง — จูนจริง Phase 6
	-- ผู้เล่นตีบอสด้วยกระบอง (5C) — ดาเมจ Config.getClubDamage(weaponLevel) · ⚠️ คูลดาวน์นี้เป็นตัวตั้งของตารางดาเมจกระบองด้วย
	PLAYER_ATTACK_COOLDOWN = 0.5, -- วินาทีต่อครั้ง (server นับเอง ห้ามเชื่อ client)
	PLAYER_ATTACK_RANGE = 14, -- ระยะแนวราบจากกึ่งกลางบอสถึงตัวผู้เล่น (บอสกว้าง 10 → ยืนชิดตัวได้ 9)

	-- บอสตีกลับ — **ปิดไว้ก่อน** (ยังไม่มีระบบตาย/เกิดใหม่เต็มรูปแบบของ Phase 4)
	BOSS_ATTACK_ENABLED = false,
	BOSS_ATTACK_DAMAGE = 10, -- ต่อครั้ง (Humanoid.Health เต็ม 100)
	BOSS_ATTACK_INTERVAL = 2, -- วินาที
	BOSS_ATTACK_RANGE = 14, -- แนวราบจากกึ่งกลางบอส

	-- ══ 5B: ไข่บอส ══ เกิดพร้อมบอสต้นกลางคืน หลังตัวบอสมุมเดียวกัน · หยิบได้หลังบอสห้องนั้นตายเท่านั้น
	-- ชนิดไข่ห้อง N = Config.getBossEggId(N) (5B-2 · เดิม EGG_ID = "egg_stage1" ห้องเดียว — ลบแล้ว)
	-- น้ำหนักสุ่มด้วย Config.rollMotherWeightForEgg ตัวเดิม **ตอนบอสเกิด** (ไม่ใช่ตอนหยิบ/ตอนเข้ากระเป๋า)
	EGGS_PER_NIGHT = 6,
	EGG_PICKUP_HOLD_SECONDS = 3, -- กด E ค้างกี่วินาทีถึงหยิบได้ (ย้ายจาก Balance.Boss.EGG_GRAB_HOLD_SECONDS)
	-- 5B-2: server จับเวลากดค้างเอง (BossEggHoldRequest) · ยอมให้สั้นกว่า EGG_PICKUP_HOLD_SECONDS ได้ไม่เกินเท่านี้ (วินาที)
	-- เผื่อ network jitter ระหว่างสัญญาณ "เริ่มกด" กับ "หยิบ" ที่มาถึง server ไม่เท่ากัน · ต้อง < EGG_PICKUP_HOLD_SECONDS (validate())
	EGG_PICKUP_HOLD_TOLERANCE = 0.3,
	-- ไข่หนักเกินค่านี้ (kg · มากกว่า ไม่ใช่เท่ากับ) → ประกาศทั้งเซิร์ฟตอนบอสเกิด
	-- 5B-2: รวมทุกห้องในข้อความเดียว "คืนนี้: ห้อง 7 ไข่ 152,300 กก. · ห้อง 9 ไข่ 410,000 กก." · ไม่มีห้องไหนเกิน = ไม่ประกาศ
	HEAVY_EGG_ALERT_KG = 100000,
}

-- 5B-2: ค่าห้องเดียวของ 5A/5B ที่ลบแล้ว — แทนด้วยค่าต่อห้อง (validate() กันไม่ให้เติมกลับ มีสองแหล่งแล้วอ่านผิดแหล่ง)
local REMOVED_BOSS_CYCLE_KEYS = {
	BOSS_HP = "Config.getBossHp(ห้อง)",
	KILL_REWARD = "Config.getBossKillReward(ห้อง)",
	EGG_ID = "Config.getBossEggId(ห้อง)",
}

--------------------------------------------------------------------------------
-- ตัวคูณ damage ของกองทัพ — "ซื้อด้วยเงิน" ไม่ใช่ได้ฟรีตามด่าน
--------------------------------------------------------------------------------
-- ⚠️ ระบบเดิม (STAGE_DAMAGE_BASE ^ (wallProgress-1)) **ยกเลิกแล้วทั้งหมด**
--
-- ทำไมถึงเปลี่ยน: ตัวคูณตามด่านเป็นของที่ได้ฟรีอัตโนมัติ ไม่มีการตัดสินใจของผู้เล่นเลย
-- ขณะเดียวกันเงินในเกมล้นเกินที่ต้องใช้ 11 เท่า (ด่าน 2) ถึง 299 เท่า (ด่าน 9)
-- เพราะคอขวดพลิกเป็น "การปล่อย" ตั้งแต่ด่าน 3 ทำให้ upgrade อัตราผลิตกับคอกหมดความหมาย
-- → ยุบสองปัญหาเข้าหากัน: ตัวคูณ damage กลายเป็นของที่ต้องซื้อ เงินที่ล้นจึงมีที่ไป
--
-- ⚠️ ผลข้างเคียงที่ **ตัดสินใจรับไว้แล้ว ไม่ใช่บั๊กที่ต้องแก้กลับ**
--   เกมเอียงไปทาง idle มากขึ้น และน้ำหนัก/คลาสของแม่มีน้ำหนักน้อยลง
--   เมื่อเทียบกับ "ฟาร์มเงินแล้วอัป" — ความคืบหน้าย้ายจากดวงมาอยู่ที่รายได้ที่คาดเดาได้
--
--------------------------------------------------------------------------------
-- ⚠️ ทำไม 8 ขั้น/ด่าน ไม่ใช่ 9
--------------------------------------------------------------------------------
-- ค่าที่สั่งมาคือ "×1.1 ต่อขั้น · 9 ขั้นต่อด่าน · รวม 72 ขั้น" ซึ่งขัดกันเอง
-- เพราะเพดาน = (กำแพงที่พังแล้ว + 1) × ขั้นต่อด่าน → 9 ขั้น/ด่าน = 81 ขั้น ไม่ใช่ 72
--
-- และที่ 9 ขั้น/ด่าน ตัวคูณจะแรงเกินไปจนด่าน 4 จบใน 0.502 ชม.
-- ซึ่งเฉียดพื้น 0.5 ชม. แบบไม่มีระยะเผื่อเลย (เพดานจริงคือ ×1.10014 ต่อขั้น)
-- แก้อะไรอย่างอื่นอีกนิดเดียวก็หลุด
--
--     ขั้น/ด่าน | ขั้นรวม | ด่าน 4   | ด่าน 9  | ผ่านยาม
--     ----------|---------|----------|---------|--------
--      7        | 63      | 1.08 ชม. | 128 ชม. | ❌ เกินเพดาน 72 ชม.
--      **8**    | **72**  | **0.74** | **54**  | ✅ มีระยะเผื่อทั้งสองด้าน
--      9        | 81      | 0.502    | 23.0    | ⚠️ ผ่านแบบเฉียดพื้น 0.4%
--
-- เลือก 8 ขั้น/ด่าน → ตรงกับ "รวม 72 ขั้น" ที่สั่งมาพอดี และ 1.1^8 = 2.14/ด่าน
-- ซึ่งใกล้ตัวคูณ 2.5/ด่านของระบบเดิมพอ ๆ กับที่ 1.1^9 = 2.36 ใกล้
--
--------------------------------------------------------------------------------
-- ⚠️ off-by-one ที่พลาดง่ายที่สุดในไฟล์นี้ (ย้ายมาจากระบบเดิม)
--------------------------------------------------------------------------------
--   ตอนผู้เล่น "อยู่ด่าน N" เขาพังกำแพงมาแล้ว N-1 ด่าน
--   เพดานขั้นที่ซื้อได้ = (N-1 + 1) × STEPS_PER_STAGE = wallProgress × STEPS_PER_STAGE
--
--   ด่าน 1 (ยังไม่เคยพังอะไร) → ซื้อได้ถึงขั้น 8  ← **ต้องไม่ใช่ 0**
--   ด่าน 9 (พังมาแล้ว 8 ด่าน) → ซื้อได้ถึงขั้น 72
--
--   ถ้าเผลอเขียน (wallProgress - 1) × STEPS_PER_STAGE ผู้เล่นใหม่จะซื้ออะไรไม่ได้เลย
--   และตันตั้งแต่ด่านแรก — validate() assert ตรง ๆ ว่าด่าน 1 ต้องได้ 8 ขั้น
--
-- ตัวคูณเป็นของ **บัญชีผู้เล่น** ไม่ใช่ของแม่รายตัว (ฟิลด์ damageLevel ใน PlayerData)
-- ใช้กับทั้งตัวแม่และตัวลูกที่ส่งไปรบ · แม่ตายไปก็ไม่เสียการลงทุน
-- และลูกที่สะสมไว้ตั้งแต่ด่านต้นแรงขึ้นตามผู้เล่น ไม่มีกองที่ตกยุค

Balance.DamageUpgrade = {
	STEP_MULTIPLIER = 1.1, -- ตัวคูณ damage ต่อ 1 ขั้น
	STEPS_PER_STAGE = 8, -- ปลดล็อกกี่ขั้นต่อ 1 กำแพงที่พังได้
	MAX_LEVEL = 72, -- = STEPS_PER_STAGE × Stage.COUNT (validate() เช็คให้)

	-- ราคาภายในด่านเดียวกันไล่ขึ้น ×นี้ ต่อขั้น
	-- ขั้นแรกของด่านใหม่จึงถูก (รางวัลทันทีที่พังกำแพง) ขั้นท้าย ๆ ถึงจะแพง
	COST_MULTIPLIER_IN_STAGE = 1.3,

	-- ⚠️ ราคาขั้นแรกของแต่ละด่าน — **ไม่ได้ตั้งลอย ๆ แต่แก้สมการหามา**
	--
	-- เป้าหมาย: ซื้อครบเพดานของด่านนั้นแล้วรายได้ส่วนเกินเหลือ 2–3 เท่า
	-- (ไม่ใช่ 0 เพราะยังต้องเหลือซื้ออาวุธและอัปคอก)
	--
	--   ราคารวมของด่าน N  = B_N × (w^8 - 1) ÷ (w - 1)   โดย w = 1.3 → ตัวคูณ 23.86
	--   ต้องการ ราคารวม   = 0.40 × รายได้ทั้งด่าน N
	--   →  B_N = 0.40 × รายได้ด่าน N ÷ 23.86
	--
	-- "รายได้ทั้งด่าน" = (เงินจากคอก + เงินจากบอส) × เวลาตีด่านนั้น + เงินจากกวาดทหารทั้งด่าน
	-- ของผู้เล่นอ้างอิงที่ซื้อครบเพดาน (ดู Config.getReferenceStageIncome)
	--
	-- ด่าน 1 ไม่มีกำแพง จึงไม่มี "เวลาตี" ใช้รายได้ 1 ชั่วโมงแรกเป็นฐานแทน
	-- ด่าน 4 ดันขึ้นจาก 360,000 เป็น 420,000 เพื่อให้ราคาไล่ขึ้นตลอด 72 ขั้นไม่มีสะดุด
	-- (รายได้ด่าน 4 โตแค่ 5.6 เท่าเพราะเป็นด่านที่เพิ่งได้คลาสใหม่ เวลาตีจึงสั้น)
	STAGE_COST_BASE = {
		300, -- ด่าน 1  ผู้เล่นใหม่มี 500 coins ซื้อขั้นแรกได้ทันที
		3100, -- ด่าน 2
		64000, -- ด่าน 3
		420000, -- ด่าน 4
		9700000, -- ด่าน 5
		300000000, -- ด่าน 6
		2400000000, -- ด่าน 7
		67000000000, -- ด่าน 8
		2100000000000, -- ด่าน 9
	},
}

--------------------------------------------------------------------------------
-- อัปเกรดความเร็ววิ่ง — บ่อเงินบ่อที่สอง
--------------------------------------------------------------------------------
-- ⚠️ โครงหลัก: เป็นบ่อดูดเงินบ่อที่สองต่อจาก DamageUpgrade
-- `speedLevel` ฝังอยู่ใน PlayerData ที่เซฟไปแล้ว · **เป็นของบัญชีผู้เล่น ไม่ใช่ของตัวละคร**
-- (ตายแล้วเกิดใหม่ต้องได้ความเร็วเดิมกลับมา ไม่ต้องซื้อซ้ำ)
--
-- ที่มา: เกมแนวขโมยไข่ให้ผู้เล่นวิ่งบนลู่เพื่อเก็บความเร็ว เกมนี้เปลี่ยนเป็น
-- **ซื้อด้วยเงิน** แทน แบบเดียวกับตัวคูณ damage เพราะแมพยาว 1,968 studs
-- และเวลาเดินทางไป-กลับรังบอสด่าน 9 กินถึง 33% ของรอบบอส 5 นาที
--
-- ⚠️⚠️ **5 ขั้น ไม่ใช่ 10 — เป็นการตัดสินใจถาวร ห้ามขยาย**
-- ราคาไล่ ×10 ต่อขั้น ถ้าทำ 10 ขั้น ขั้นสุดท้ายจะแพงกว่าขั้นแรก **หนึ่งพันล้านเท่า**
-- แต่ให้ความเร็วเพิ่มแค่ 3-4% (เพราะตัวคูณถดถอยและชนเพดาน ×4)
-- = ขั้นที่ไม่มีใครซื้อ เป็นตัวเลขหลอกตาในตารางเฉย ๆ แบบเดียวกับคอก Lv11-15 ที่ตัดทิ้งไปแล้ว
-- 5 ขั้นจบที่ 100M ยังคุ้มทุกขั้น และครอบคลุมช่วงเกมพอแล้ว (ดู docs/data-schema.md §8.8)
Balance.SpeedUpgrade = {
	MAX_LEVEL = 5, -- ⚠️ ห้ามขยายเป็น 10 (เหตุผลข้างบน)

	-- ราคา: ขั้นแรก 10,000 แล้ว ×10 ทุกขั้น → 10K · 100K · 1M · 10M · 100M (รวม 111.11M)
	-- ไล่ ×10 ให้ตรงกับรายได้ที่โต ×10 ต่อด่าน → ขั้น N ซื้อไหวพอดีที่ด่าน N
	BASE_COST = 10000,
	COST_MULTIPLIER = 10,

	-- ตัวคูณความเร็วสูงสุดที่ขั้นสุดท้าย (ขั้น 0 = ×1 เสมอ)
	MAX_MULTIPLIER = 4,

	-- ⚠️ **ตัวคูณถดถอย** — ขั้นแรกให้เยอะสุด (+90%) แล้วค่อย ๆ ลดลงเหลือ +13%
	-- สูตร: ตัวคูณ = 1 + (MAX_MULTIPLIER - 1) × (ขั้น ÷ MAX_LEVEL) ^ CURVE_EXPONENT
	-- ยิ่งเลขชี้กำลังน้อย ขั้นแรก ๆ ยิ่งให้เยอะ · 1.0 = เพิ่มเท่ากันทุกขั้น
	-- ตั้งเป็นค่าใน Config เพื่อให้ปรับความรู้สึกได้โดยไม่ต้องแก้โค้ด
	CURVE_EXPONENT = 0.75,

	-- ⚠️ เพดานที่ Roblox รับได้ — ต่ำกว่า ~100 ปลอดภัย · 100-200 เริ่มทะลุของบาง ·
	-- เกิน 200 ทะลุบ่อยจนเล่นไม่ได้ · ความเร็วสูงสุดตอนนี้ 128 อยู่ในโซนเสี่ยง
	-- จึงต้องมีกฎความหนากำแพงคู่กันเสมอ (Config.getMinWallThickness)
	SPEED_CEILING = 200,

	-- เฟรมเรตที่ใช้คิดว่า "ขยับกี่ stud ต่อเฟรม" ตอนหาความหนากำแพงขั้นต่ำ
	-- 60 fps เป็นค่าปกติของ Roblox · ต่ำกว่านี้ยิ่งขยับไกลต่อเฟรมยิ่งต้องหนา
	PHYSICS_FPS = 60,

	-- เผื่อกี่เท่าของระยะต่อเฟรม — 2 เท่าคือเผื่อกรณีเฟรมตกครึ่งหนึ่ง
	THICKNESS_SAFETY = 2,
}

--------------------------------------------------------------------------------
-- Robux: ทะลุเพดานดาเมจ/ความเร็ว + เร่งฟักไข่ (UI-5)
--------------------------------------------------------------------------------
-- ⚠️ แยกจาก DamageUpgrade/SpeedUpgrade (เงินในเกม) โดยสิ้นเชิง — คนละฟิลด์ใน PlayerData
-- (robuxDamageBonus / robuxSpeedBonus) คนละสูตร ไม่มี MAX_LEVEL แบบ DamageUpgrade
--
-- ดาเมจ: ไม่มีเพดานทางฟิสิกส์ผูกอยู่ (ต่างจากความเร็ว) จึงปล่อยทวีคูณไปได้ตรง ๆ ไม่ต้อง clamp
-- ความเร็ว: **ต้องมี hard cap** เพราะความหนากำแพงทุกชนิดที่สร้างไปแล้ว (§ผังแมพ) คำนวณจาก
-- ความเร็วสูงสุดของแทร็กปกติ (128) ไว้ล่วงหน้า ถ้าความเร็วจริงพุ่งเกินกว่าที่กำแพงรับไหว
-- ผู้เล่นจะวิ่งทะลุกำแพงได้ — ดู Config.getRobuxSpeedHardCap() (คำนวณย้อนกลับจากความหนาที่สร้างจริง
-- แทนที่จะเผื่อพื้นที่กำแพงใหม่ กันไม่ต้องแตะ MapDimensions ที่เป็นโครงหลักที่ล็อกไว้แล้ว)
Balance.RobuxBoost = {
	-- ตัวคูณ damage ต่อ 1 ขั้นที่ซื้อด้วย Robux — ไม่มีเพดานขั้น (ต่างจาก DamageUpgrade.MAX_LEVEL)
	DAMAGE_MULTIPLIER_PER_STEP = 1.1,

	-- ความเร็วที่เพิ่มต่อ 1 ขั้น (studs/วินาที) — ผลจริงถูก clamp ด้วย getRobuxSpeedHardCap() เสมอ
	SPEED_PER_STEP = 4,
}

Balance.Combat = {
	--------------------------------------------------------------------------
	-- อาวุธป้องกันของกำแพง — เก็บเป็น "สัดส่วน" ไม่ใช่ตัวเลข damage
	--------------------------------------------------------------------------
	-- ⚠️ เดิมเก็บเป็นตาราง turretDps ดิบ 9 ค่า ซึ่ง **เปราะมาก**
	-- เพราะค่าที่ถูกต้องคือ TOLL × damage/วินาทีของผู้เล่นอ้างอิงเสมอ
	-- และ damage/วินาที แปรตามของอย่างน้อย 5 อย่าง:
	--     ตัวคูณคลาส · ตัวคูณ damage ที่ซื้อได้ · อัตราปล่อย · อัตราผลิต · ความจุคอก
	-- แตะอย่างใดอย่างหนึ่ง = ต้องนั่งคำนวณ 9 ค่าใหม่ด้วยมือ ซึ่งทำมาแล้ว 5 รอบ
	-- และยามจับได้แค่ตอน "เกินเพดาน" ถ้าค่าเพี้ยนไปอยู่ที่ 2% ก็ปล่อยผ่านเงียบ ๆ
	--
	-- ตอนนี้จึงเก็บแค่ "สัดส่วนกำลังพลที่ยอมให้ turret กิน" แล้วให้
	-- Config.getStageTurretDps() คำนวณ damage จริงจากสูตร:
	--
	--     turretDps(N) = TURRET_TOLL[N] × Config.getReferenceDps(N)
	--
	-- ปรับตัวคูณคลาส/upgrade/อัตราปล่อยอะไรก็ตาม turret ขยับตามเองทันที
	-- อยากให้ด่านไหนโหดขึ้นเป็นพิเศษ ก็ดัน TOLL ของด่านนั้นตัวเดียว
	--
	-- ⚠️ ผลข้างเคียงที่ **ตั้งใจ**: ค่านี้อิงผู้เล่นอ้างอิงที่ "ซื้อ upgrade ครบเพดาน"
	-- ผู้เล่นที่ยังไม่ซื้อจะเจอ turret ที่กินกำลังพลมากกว่าสัดส่วนนี้ตามที่เขาขาด
	-- ซึ่งถูกต้องแล้ว — ไม่ซื้อของก็ควรเจอกำแพงที่เขี้ยวกว่า
	--
	-- ด่าน 1 ไม่มีกำแพง จึงเป็น 0
	TURRET_TOLL = { 0, 0.10, 0.11, 0.13, 0.14, 0.16, 0.17, 0.19, 0.20 },

	-- อัตราปล่อยทหารออกจากจุดสปอน (ตัว/วินาที) ต่อด่าน
	-- ⚠️ นี่คือ "เพดาน damage ต่อวินาที" ของผู้เล่น และเป็นคอขวดหลักตั้งแต่ด่าน 3 ขึ้นไป
	-- ปล่อยเฉพาะตอนออนไลน์ · ออฟไลน์ไม่ปล่อย (แต่แม่ยังผลิตตามกติกาออฟไลน์เดิม)
	--
	-- ⚠️ ตัวเลขชุดนี้หามาจากการไล่คำนวณ ไม่ได้ตั้งลอย ๆ
	-- ด่าน 1-2 คอขวดอยู่ที่ "การผลิต" (ผลิตได้ 0.12 และ 0.63 ตัว/วิ) เพดานปล่อยยังไม่มีผล
	-- ตั้งแต่ด่าน 3 ขึ้นไปคอขวดพลิกเป็น "การปล่อย" ถาวร
	-- ถ้าเร่งปล่อยเร็วเกินตรงรอยต่อนี้ เส้นเวลาจะแอ่นลง (ด่าน 3 ง่ายกว่าด่าน 2)
	RELEASE_PER_SECOND = { 1, 1, 1, 2, 3, 4, 6, 8, 10 },

	-- ปุ่มอัญเชิญ: ปิด = หยุดปล่อย สะสมไว้ในคลัง · เปิด = ปล่อยต่อเนื่องอัตโนมัติ
	-- กลไกหลักของเกมคือสะสมกองใหญ่แล้วปล่อยรวดเดียวทะลุ
	-- ดีกว่าปล่อยทีละตัวแล้วถูกกินทีละตัว
	SUMMON_DEFAULT_ON = true,

	-- auto-pause: ปล่อยไปครบเท่านี้ตัวแล้ว HP ฝ่ายตรงข้ามไม่ลดเลย → หยุดปล่อยเอง
	-- กันไม่ให้ทหารถูกป้อนเข้าเครื่องบดหายถาวรโดยไม่ได้ damage
	AUTO_PAUSE_AFTER_UNITS = 100,

	-- cap โมเดลทหารฝ่ายเราที่แสดงพร้อมกัน ส่วนเกินรวมเป็นตัวเลข
	-- แสดงเฉพาะทหารของผู้เล่นคนนั้นเอง ไม่แสดงของคนอื่น
	-- ประมาณการ: 10 ตัว/วินาที × เดินถึงกำแพง ~30 วินาที = 300 ตัวมีชีวิตพร้อมกัน
	MAX_VISIBLE_UNITS = 120,
	WALK_SECONDS_TO_WALL = 30, -- เวลาเดินจากจุดสปอนถึงกำแพง ใช้ประมาณจำนวนบนจอ

	-- ⚠️ ห้ามระบบ auto ปล่อย "ตัวแม่" เด็ดขาด — auto ปล่อยได้เฉพาะตัวลูก
	-- ผู้เล่นต้องกดเลือกและส่งแม่เองทีละครั้ง + กล่องยืนยัน
	-- และ **เลือกได้เฉพาะแม่ที่อยู่ในกระเป๋า** แม่ในคอกเลือกไม่ได้
	-- (กันไม่ให้เผลอส่งเครื่องผลิตไปตาย)
	ALLOW_AUTO_RELEASE_MOTHERS = false,
	MOTHERS_SELECTABLE_FROM_PEN = false,

	-- ══ แม่ในสนามรบ (battleRoster · Phase 3C-1) ══
	-- จำนวนแม่ที่ส่งไปรบพร้อมกันได้สูงสุด — แม่ทั้ง roster ตายถาวรพร้อมกันตอนด่านที่กำลังตีพัง
	-- แม่แต่ละตัวตีวินาทีละครั้ง แรง = Config.computeBattlePower (แม่ 1 ตัว = ลูก 10 ตัวต่อวินาที)
	-- ⚠️ ยามเวลาผ่านด่าน (assertProgressionIsSane) คิดจากผู้เล่นที่ไม่ส่งแม่ — ส่งแม่ = เร็วขึ้น
	-- แลกกับเสียเครื่องผลิตถาวร ซึ่งเป็นการเลือกของผู้เล่นเอง
	MAX_BATTLE_MOTHERS = 10,

	-- ══ รางวัลผ่านด่าน (Phase 4A) ══ ไข่ฟรีตอนกำแพงด่านนั้นพังเป็นครั้งแรก (ได้ครั้งเดียวต่อด่าน)
	-- ไข่ = Config.getBossEggId(ด่าน) คือไข่ของรังบอสที่เพิ่งปลดล็อก · สุ่มน้ำหนักตามปกติผ่าน EggService.grantEgg
	-- ⚠️ ให้เป็นไข่ ไม่ใช่เงิน — เงินเพิ่งถูกดูดส่วนเกินด้วย DamageUpgrade ใส่เงินก้อนเพิ่ม = ย้อนปัญหาเดิม
	-- ⚠️ ด่าน 1 = 0 เสมอ: ไม่มีกำแพงให้พัง ("พัง" ฟรีตั้งแต่ตาแรกที่ปล่อยทหาร) · validate() บังคับ
	-- ด่าน 2–3 = 1 · 4–6 = 2 · 7–9 = 3 → รวม 17 ฟองทั้งเกม (~3% ของไข่จากบอสตลอดทางถึงด่าน 9)
	STAGE_CLEAR_BONUS_EGGS = { 0, 1, 1, 2, 2, 2, 3, 3, 3 },
}

--------------------------------------------------------------------------------
-- ยามเฝ้าสมดุล
--------------------------------------------------------------------------------
-- ค่าอ้างอิงของ "ผู้เล่นชั้นกลาง" ที่แต่ละด่าน ใช้เป็นไม้บรรทัดวัดว่าเกมยังเล่นจบได้
-- ไม่ใช่ข้อมูลเกม — ไม่มีใครอ่านค่านี้ตอนเล่นจริง มีไว้ให้ validate() ใช้อย่างเดียว

Balance.BalanceCheck = {
	-- เวลาสะสมกองทัพต่อ 1 ด่านต้องอยู่ในช่วงนี้
	MIN_HOURS_PER_STAGE = 0.5, -- เร็วกว่านี้ = ด่านไม่มีความหมาย
	MAX_HOURS_PER_STAGE = 72, -- ช้ากว่านี้ = ผู้เล่นเลิกเล่น

	-- ══ ผู้เล่นอ้างอิง ══
	--
	-- ⚠️ เคยตั้งเป็น "แม่หนักขึ้น ×4 ทุกด่าน" (500 → 30,000,000 kg) ซึ่งผิด
	-- เพราะตารางสุ่มน้ำหนักเหมือนกันทุกด่าน แม่ 30M kg คือ tier 6 = 1 ใน 111,111
	-- ที่อัตราไข่จริง (5 ฟอง/5 นาที ÷ 6 คน) ต้องฟาร์มหลักหมื่นชั่วโมง
	-- ขณะที่เวลาตีกำแพงด่าน 9 อยู่หลักสิบชั่วโมง → ยามผ่าน ทั้งที่เกมเล่นไม่ไหว
	--
	-- ตอนนี้จึงใช้ **น้ำหนักคงที่ระดับ tier 1** (ซึ่ง 90% ของไข่ให้)
	-- แล้วให้ "คลาส" เป็นตัวไต่ตามด่านแทน — นี่คือเส้นทางที่ผู้เล่นจริงเดิน
	REFERENCE_WEIGHT = { 500, 500, 500, 500, 500, 500, 500, 500, 500 },

	-- คลาสที่ผู้เล่นทั่วไปหาได้จริงตอนอยู่ด่านนั้น
	-- เทียบกับตารางคลาสของไข่ด่านนั้น: A ที่ด่าน 7 = 25% ของไข่ · S = 1% เท่านั้น
	-- จึงตั้งเพดานไว้ที่ A ไม่ใช่ S — S/SS เป็นของแถมที่ทำให้เร็วขึ้น ไม่ใช่ของที่ต้องมี
	REFERENCE_CLASS = { "C", "C", "C", "B", "B", "B", "A", "A", "A" },

	-- ══ โมเดลอัตราได้ไข่ ══ ใช้ตรวจว่า "เวลาฟาร์ม" ไม่บานเกินเวลาตี
	-- บอสเกิดทุก BossCycle.MODEL_BOSS_SPAWN_SECONDS วางไข่ MODEL_EGGS_PER_SPAWN ฟอง หารกันทั้งเซิร์ฟ
	-- (5B: ตัวเลขเดิมของ Balance.Boss ที่ลบแล้ว — ไม่ใช่วงจรจริง 10 นาที/6 ฟอง · เหตุผลอยู่ที่ตัวค่าใน BossCycle)
	PLAYERS_PER_SERVER = 6,

	-- เวลาฟาร์มไข่ให้ได้ของที่ด่านนั้นต้องการ ต้องไม่เกินเวลาตีกำแพงกี่เท่า
	-- เกินเมื่อไหร่แปลว่าเกมกลายเป็น "นั่งรอไข่" ไม่ใช่ "ตีกำแพง"
	MAX_FARM_TO_CLEAR_RATIO = 5,

	-- เพดานอัตราส่วนตัวคูณคลาส SS ÷ S — กัน pay-to-win
	MAX_SS_OVER_S_RATIO = 2.5,

	-- ราคา upgrade ตัวคูณ damage ของด่านหนึ่ง ต้องกินรายได้ของด่านนั้นในสัดส่วนนี้
	-- ต่ำกว่านี้ = เงินยังล้น upgrade ไม่ได้ทำหน้าที่เป็นบ่อเงิน
	-- สูงกว่านี้ = ผู้เล่นซื้อไม่ไหว แล้วตันเพราะ damage ไม่พอ
	MIN_UPGRADE_SHARE = 0.30,
	MAX_UPGRADE_SHARE = 0.70,

	-- ⚠️ เพดานสัดส่วนกำลังพลที่ turret กินได้ของผู้เล่นชั้นกลาง
	-- turretDps ที่ตั้งไว้ตอนนี้ไล่ 10% → 20% เผื่อไว้ถึง 35% กันตั้งพลาด
	-- เกินจากนี้ = ทหารตายเร็วกว่าที่ทำ damage ได้ → ด่านนั้นผ่านไม่ได้เลย
	TURRET_TOLL_CEILING = 0.35,
}

--------------------------------------------------------------------------------
-- ของที่ซื้อด้วย Robux (Developer Product)
--------------------------------------------------------------------------------
-- ⚠️ ห้ามเก็บราคา Robux ที่นี่ — ราคาจริงอยู่ใน Creator Dashboard ที่เดียว
-- ฝั่ง client ให้ดึงราคามาโชว์ด้วย MarketplaceService:GetProductInfo()
--
-- ไข่ตำนานเป็นของที่ซื้อด้วย Robux เท่านั้น ซื้อซ้ำได้ (Developer Product
-- ไม่ใช่ Gamepass) การให้ของต้องผ่าน ProcessReceipt ซึ่งต้องทน retry ได้
-- รายละเอียดวิธีทำให้ปลอดภัยอยู่ใน docs/data-schema.md

-- ⚠️ UI-5: **ตารางเดียวที่รวม placeholder productId ทุกตัวในเกม** (DeveloperProducts + RobuxProducts
-- ข้างล่าง) — ห้ามมี productId ปลอมกระจายอยู่ที่อื่น validate() เช็ค unique ข้ามสองตารางนี้ด้วย
-- ราคาจริงทั้งหมด = 1 Robux ชั่วคราว (ตั้งจริงที่เว็บ Roblox เอง) เลขที่ใส่ไว้เป็นเลขปลอม
-- ต้องแทนที่ด้วย Product ID จริงจาก Creator Dashboard ก่อน publish (ดู docs/data-schema.md §8.7)
local DeveloperProducts: { [string]: DeveloperProduct } = {
	legendary_egg = {
		id = "legendary_egg",
		name = "ไข่ตำนาน",
		description = "ไข่ที่ออกตัวละครระดับ S และ SS ได้ ซื้อด้วย Robux เท่านั้น",
		productId = 1000001, -- TODO: แทนที่ด้วย Product ID จริงจากเว็บ Roblox
		grantEggId = "egg_legendary",
		grantAmount = 1,
		enabled = true, -- UI-5: เปิดขายจริง (ราคาจริงตั้งที่เว็บ Roblox ก่อน publish)
	},
}

Config.DeveloperProducts = DeveloperProducts

-- ⚠️ UI-5: ของที่ซื้อด้วย Robux ที่ไม่ใช่ไข่ — ทะลุเพดานดาเมจ/ความเร็ว + เร่งฟักไข่
-- ทุกตัวซื้อซ้ำได้ (Developer Product เดียวใช้ทุกครั้งที่ซื้อ ไม่ใช่ Gamepass/คนละ id ต่อขั้น)
-- เพราะ ProcessReceipt ไม่ได้รับพารามิเตอร์ที่ผู้เล่นเลือกไว้ตอนกด (เช่น "ฟองไหน") มาด้วย —
-- เก็บ "จะซื้อกี่ขั้น/เร่งกี่ฟอง" ไว้ในตัว amount ของสินค้าแทน ไม่ใช่ที่ตัวธุรกรรม
local RobuxProducts: { [string]: RobuxProduct } = {
	robux_damage_step = {
		id = "robux_damage_step",
		name = "พลังทะลุเพดาน",
		description = "เพิ่มตัวคูณดาเมจแบบไม่มีเพดาน ซื้อได้เรื่อย ๆ",
		productId = 1000002, -- TODO: แทนที่ด้วย Product ID จริงจากเว็บ Roblox
		kind = "damage_bonus",
		amount = 1,
		enabled = true,
	},
	robux_speed_step = {
		id = "robux_speed_step",
		name = "ความเร็วทะลุเพดาน",
		description = "เพิ่มความเร็ววิ่งเกินเพดานปกติ (ยังมีเพดานความปลอดภัยของแมพกันไว้) ซื้อได้เรื่อย ๆ",
		productId = 1000003, -- TODO: แทนที่ด้วย Product ID จริงจากเว็บ Roblox
		kind = "speed_bonus",
		amount = 1,
		enabled = true,
	},
	robux_hatch_rush = {
		id = "robux_hatch_rush",
		name = "เร่งฟักไข่ทั้งหมด",
		description = "ทำให้ไข่ที่กำลังฟักอยู่ทุกฟองเสร็จทันที",
		productId = 1000004, -- TODO: แทนที่ด้วย Product ID จริงจากเว็บ Roblox
		kind = "hatch_rush",
		amount = 1,
		enabled = true,
	},
}

Config.RobuxProducts = RobuxProducts

-- คีย์ที่ใช้เก็บ log ธุรกรรมใน DataStore (แยกจาก PlayerData)
-- ⚠️ UI-5: **ไม่ได้ใช้จริง** — เลือกเก็บ processedPurchaseIds ต่อผู้เล่นใน PlayerData แทน
-- (อะตอมมิกไปกับการเซฟ PlayerData ก้อนเดียวกันโดยไม่ต้องเปิด DataStore ที่สอง) ตารางนี้แช่แข็งไว้
-- เผื่อวันหนึ่งอยากทำ audit-trail แยกอายุจาก PlayerData จริง ๆ (ดู docs/data-schema.md §8.7)
Config.PurchaseLog = {
	STORE_NAME = "PurchaseLog_v1",
	-- key = "receipt_<PurchaseId>" ใช้กันการให้ของซ้ำตอน Roblox retry
	RECEIPT_PREFIX = "receipt_",
}

--------------------------------------------------------------------------------
-- อาวุธของผู้เล่น = กระบอง 10 ขั้น (Phase 5C · ใช้ตีบอส ไม่เกี่ยวกับกองทัพ)
--------------------------------------------------------------------------------
-- ✅ ผู้ใช้ยืนยัน (5C): อาวุธชนิดเดียว = กระบองฟาดระยะใกล้ · ซื้อด้วยเงินในเกม · ซื้อเรียงขั้น (ต้องมี N-1 ก่อน N)
--   ไม่ผูกด่าน · ขั้น 1–9 จับคู่บอสห้อง 1–9 · ขั้น 10 = ขั้นพิเศษหลังผ่านด่าน 9 (แพงมาก · ตีห้อง 9 เร็วขึ้นชัด)
--   ⚠️ ป้ายอัปดาเมจ (damageLevel) **ไม่มีผลกับกระบอง** · ดาเมจกระบองขึ้นกับขั้นกระบองอย่างเดียว
--   ⚠️ โบนัส Robux ดาเมจ (robuxDamageBonus · UI-5) ก็ไม่มีผล — คูณเฉพาะกองทัพ (computeBattlePower)
--
-- ⚠️ **ไม่มีตารางตัวเลขดิบ** (บทเรียนเดียวกับ TURRET_TOLL — เก็บเลขดิบแล้วต้องคำนวณมือใหม่ทุกครั้งที่แก้อย่างอื่น)
--   ดาเมจขั้น N = HP บอสห้องเป้าหมาย (Config.getBossHp) × คูลดาวน์ตีจริง (BossCycle.PLAYER_ATTACK_COOLDOWN)
--                 ÷ เวลาเป้าหมาย → **ปัดขึ้น**เป็นเลขนัยสำคัญ DAMAGE_SIGNIFICANT_DIGITS ตัว (อย่างน้อย 1)
--     ปัดขึ้น = ตีตายไม่ช้ากว่าเป้าเสมอ · ขั้น 1–9 เป้า = ห้องเดียวกัน · ขั้น 10 เป้า = ห้องสุดท้าย เร็วกว่า
--   ราคาขั้น N = รายได้/ชม. ของผู้เล่นอ้างอิงด่าน N (Config.getReferenceIncomePerHour · โมเดลสมดุลเดิม)
--                × PRICE_INCOME_MINUTES ÷ 60 → ปัดเลขนัยสำคัญ PRICE_SIGNIFICANT_DIGITS ตัว · ขั้น 1 ฟรี (START_TIER)
--     ขั้น 10 อิงรายได้ด่านสุดท้าย × CAPSTONE_PRICE_INCOME_MINUTES
--   → แก้ HP บอส / คูลดาวน์ / รายได้ในโมเดล แล้วตารางกระบองขยับตามเอง · validate() ตรวจทุกขั้น
--   ดูตารางจริง: Config.getClubDamage / getClubPrice / getClubSoloKillSeconds (หรือ luau tools/dump-balance.luau)
--
-- ⚠️ ขั้นที่ซื้อเก็บใน PlayerData.weaponLevel (มีตั้งแต่ schema v1 · ไม่แตะ schema) · ค่านอกช่วง clamp ตอนอ่าน (clampClubTier)

Balance.Weapon = {
	MAX_LEVEL = 10, -- ขั้น 1..จำนวนด่าน จับคู่ห้องบอส + ขั้นพิเศษ 1 ขั้น (validate() บังคับ = Stage.COUNT + 1)
	START_TIER = 1, -- ผู้เล่นใหม่ได้ฟรี · debugResetAll กลับมาที่ขั้นนี้

	-- ขั้น N ตีบอสห้อง N คนเดียวตายใน ~เท่านี้ (วินาที · ปัดดาเมจขึ้น จึงไม่เกินค่านี้)
	-- ⚠️ ต้องไม่เกินกลางวัน (BossCycle.DAY_SECONDS) — ไม่งั้นพังกำแพง N ขณะบอสห้อง N อยู่ = ติดล็อกอัญเชิญถาวร
	TARGET_SOLO_KILL_SECONDS = 180,
	-- ขั้นพิเศษ (ขั้นสุดท้าย) ตีบอสห้องสุดท้ายคนเดียวตายใน ~เท่านี้ (ขั้นก่อนหน้า ~TARGET_SOLO_KILL_SECONDS)
	CAPSTONE_SOLO_KILL_SECONDS = 60,
	DAMAGE_SIGNIFICANT_DIGITS = 1, -- 27.8 → 30 · 2.78 → 3 (อ่านง่าย · ขั้น 2–9 โต ×10 เท่ากันพอดี)

	-- ราคา = รายได้กี่นาทีของผู้เล่นอ้างอิงด่านนั้น
	-- ⚠️ เพดานจากเทสต์สมดุลเดิม "ส่วนเกิน ≥ 1.5 เท่า": ด่าน 4 ตึงสุด → ไม่เกิน ~10 นาที · ตั้ง 5 (ส่วนเกินต่ำสุด 1.70)
	PRICE_INCOME_MINUTES = 5,
	-- ขั้นพิเศษ: รายได้ด่านสุดท้ายกี่นาที (แพงมาก — ของเก็บเงินหลังผ่านเกม ไม่อยู่ในโมเดลรายด่าน)
	CAPSTONE_PRICE_INCOME_MINUTES = 180,
	PRICE_SIGNIFICANT_DIGITS = 2, -- 17,334 → 17,000
}

-- 5C: สูตรอาวุธเดิม (×10 ต่อขั้น · ตี 10 ครั้งพอดี · ราคา ×10) ลบแล้ว — validate() กันไม่ให้เติมกลับ
local REMOVED_WEAPON_KEYS = {
	DAMAGE_BASE = "Config.getClubDamage(ขั้น) — คำนวณจาก HP บอส",
	DAMAGE_MULTIPLIER = "Config.getClubDamage(ขั้น) — คำนวณจาก HP บอส",
	UPGRADE_BASE_COST = "Config.getClubPrice(ขั้น) — คำนวณจากรายได้",
	UPGRADE_COST_MULTIPLIER = "Config.getClubPrice(ขั้น) — คำนวณจากรายได้",
}

-- ปิดชุด Balance — ตั้งแต่บรรทัดนี้ลงไปอ่านผ่าน `Config.Balance.<กลุ่ม>` ได้แล้ว
Config.Balance = Balance

--------------------------------------------------------------------------------
-- ทหาร
--------------------------------------------------------------------------------
-- ตัวเลข hp/damage/speed ยังไม่ได้ balance จริง ใช้เป็นตุ๊กตาไปก่อนจนถึง Phase 3

-- ⚠️ ตกค้างจากกลไกเก่า "ฟักไข่ → ได้ทหาร" ซึ่งถูกแทนที่ด้วย Config.Characters แล้ว
-- **ปิดทั้งหมดตอน Phase 1.5 แต่ห้ามลบ** — unitId เคยอยู่ในข้อมูลที่เซฟไปแล้ว
-- (กฎ id ใน CLAUDE.md: เลิกใช้ให้ตั้ง enabled = false แทนการลบ)
local UnitTypes: { [string]: UnitType } = {
	recruit = {
		id = "recruit",
		enabled = false,
		name = "พลทหารฝึกหัด",
		rarity = "Common",
		hp = 100,
		damage = 10,
		speed = 12,
	},
	spearman = {
		id = "spearman",
		enabled = false,
		name = "พลหอก",
		rarity = "Common",
		hp = 140,
		damage = 14,
		speed = 11,
	},
	archer = {
		id = "archer",
		enabled = false,
		name = "พลธนู",
		rarity = "Rare",
		hp = 110,
		damage = 22,
		speed = 13,
	},
	knight = {
		id = "knight",
		enabled = false,
		name = "อัศวิน",
		rarity = "Rare",
		hp = 260,
		damage = 26,
		speed = 10,
	},
	mage = {
		id = "mage",
		enabled = false,
		name = "จอมเวท",
		rarity = "Epic",
		hp = 180,
		damage = 45,
		speed = 12,
	},
	dragon_rider = {
		id = "dragon_rider",
		enabled = false,
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
	-- ⚠️ ไข่เดิมสองใบนี้ "เลิกใช้แล้ว" แต่ห้ามลบ (กฎ eggId ใน CLAUDE.md)
	-- ระบบใหม่ใช้ไข่รายด่าน egg_stage1..egg_stage9 แทน
	egg_common = {
		id = "egg_common",
		enabled = false,
		guaranteedTier = nil,
		name = "ไข่ธรรมดา",
		source = "boss",
		hatchTime = 30,
		color = rgb(235, 235, 225),
	},
	egg_rare = {
		id = "egg_rare",
		enabled = false,
		guaranteedTier = nil,
		name = "ไข่หายาก",
		source = "boss",
		hatchTime = 120,
		color = rgb(90, 160, 235),
	},
	egg_stage1 = {
		id = "egg_stage1",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 1",
		source = "boss",
		stage = 1,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 1,
		color = rgb(235, 235, 225),
	},
	egg_stage2 = {
		id = "egg_stage2",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 2",
		source = "boss",
		stage = 2,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 2,
		color = rgb(200, 225, 235),
	},
	egg_stage3 = {
		id = "egg_stage3",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 3",
		source = "boss",
		stage = 3,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 3,
		color = rgb(150, 200, 235),
	},
	egg_stage4 = {
		id = "egg_stage4",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 4",
		source = "boss",
		stage = 4,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 4,
		color = rgb(120, 215, 180),
	},
	egg_stage5 = {
		id = "egg_stage5",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 5",
		source = "boss",
		stage = 5,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 5,
		color = rgb(150, 220, 120),
	},
	egg_stage6 = {
		id = "egg_stage6",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 6",
		source = "boss",
		stage = 6,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 6,
		color = rgb(235, 215, 110),
	},
	egg_stage7 = {
		id = "egg_stage7",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 7",
		source = "boss",
		stage = 7,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 7,
		color = rgb(240, 170, 80),
	},
	egg_stage8 = {
		id = "egg_stage8",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 8",
		source = "boss",
		stage = 8,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 8,
		color = rgb(230, 110, 90),
	},
	egg_stage9 = {
		id = "egg_stage9",
		enabled = true,
		guaranteedTier = nil,
		name = "ไข่ด่าน 9",
		source = "boss",
		stage = 9,
		hatchTime = Balance.Hatchery.SECONDS_PER_STAGE * 9,
		color = rgb(190, 110, 235),
	},
	egg_legendary = {
		id = "egg_legendary",
		enabled = true,
		guaranteedTier = 3,
		name = "ไข่ตำนาน",
		source = "robux",
		stage = nil, -- ไม่ผูกด่าน — ใช้ด่านที่ผู้ซื้ออยู่ตอนกด
		hatchTime = Balance.Hatchery.LEGENDARY_SECONDS,
		color = rgb(240, 185, 60),
	},
}

Config.EggTypes = EggTypes

-- ไข่ที่ปุ่มทดสอบฝั่ง client ใช้ (Phase 1 มีปุ่มเดียว)
Config.DEFAULT_EGG_ID = "egg_stage1"

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

function Config.getDeveloperProduct(productKey: string): DeveloperProduct?
	return DeveloperProducts[productKey]
end

-- หา Developer Product จากเลข productId ที่ Roblox ส่งมาใน ProcessReceipt
function Config.findProductByRobloxId(productId: number): DeveloperProduct?
	for _, product in DeveloperProducts do
		if product.enabled and product.productId == productId then
			return product
		end
	end
	return nil
end

function Config.getRobuxProduct(productKey: string): RobuxProduct?
	return RobuxProducts[productKey]
end

-- หาสินค้า Robux (ที่ไม่ใช่ไข่) จากเลข productId — ใช้คู่กับ findProductByRobloxId ใน ProcessReceipt
-- (เช็คทั้งสองตาราง เพราะ Roblox ส่งมาแค่ productId เดียว ไม่บอกว่ามาจากตารางไหน)
function Config.findRobuxProductByRobloxId(productId: number): RobuxProduct?
	for _, product in RobuxProducts do
		if product.enabled and product.productId == productId then
			return product
		end
	end
	return nil
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

--------------------------------------------------------------------------------
-- ผลรวมของสถานะ
--------------------------------------------------------------------------------
-- แม่ติดหลายสถานะ = ตัวคูณคูณสะสมกัน ส่วนโบนัสน้ำหนักลูกบวกกัน
-- สถานะที่ enabled = false จะถูกข้าม (Phase 1-5 ยังไม่เปิดสักตัว ผลจึงเป็นกลางหมด)
--
-- ⚠️ โบนัสน้ำหนักลูก "ไม่" กระทบ stack key เพราะ key เก็บน้ำหนัก "แม่"
-- ลูกในกองเดียวกันมีชุดสถานะเดียวกันอยู่แล้ว จึงมีสัดส่วนน้ำหนักเท่ากันเสมอ

function Config.getStatusEffects(statuses: { string }?): StatusEffects
	local effects: StatusEffects = {
		damageMultiplier = 1,
		coinMultiplier = 1,
		productionMultiplier = 1,
		childRatio = Config.Balance.Weight.CHILD_RATIO,
	}

	if not statuses then
		return effects
	end

	local seen: { [string]: boolean } = {}
	for _, statusId in statuses do
		if not seen[statusId] then
			seen[statusId] = true
			local status = Statuses[statusId]
			if status and status.enabled then
				effects.damageMultiplier *= status.damageMultiplier
				effects.coinMultiplier *= status.coinMultiplier
				effects.productionMultiplier *= status.productionMultiplier
				effects.childRatio += status.childRatioBonus
			end
		end
	end

	-- กันลูกหนักเกินแม่
	effects.childRatio = math.min(effects.childRatio, Config.Balance.Weight.MAX_CHILD_RATIO)

	return effects
end

-- น้ำหนักลูกจากน้ำหนักแม่ (อาจเป็นทศนิยม — ห้ามเอาไปทำ stack key)
function Config.getChildWeight(motherWeight: number, statuses: { string }?): number
	return motherWeight * Config.getStatusEffects(statuses).childRatio
end

--------------------------------------------------------------------------------
-- สุ่มน้ำหนักตัวแม่
--------------------------------------------------------------------------------
-- สุ่ม 2 ขั้นตามที่อธิบายไว้ข้างบน: เลือก tier ก่อน แล้วค่อยสุ่มในช่วงของ tier นั้น
-- rng ส่งเข้ามาจากข้างนอกเพื่อให้เทสต์ซ้ำได้ด้วย seed เดิม

-- ตารางสุ่มน้ำหนักของด่านนั้น
-- ตอนนี้ทุกด่านถอยมาใช้ตารางด่าน 1 ซึ่งเป็น **พฤติกรรมที่ต้องการ ไม่ใช่ของค้าง**
-- (ด่าน 1 กำหนดไว้แล้วเสมอ จึงมีของให้ถอยไปใช้แน่นอน)
function Config.getWeightTiers(stage: number): { WeightTier }
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	for index = clamped, 1, -1 do
		local tiers = StageWeightTiers[index]
		if tiers then
			return tiers
		end
	end
	return WeightTiers
end

-- stage = ด่านของบอสที่ไข่ฟองนี้มาจาก (ไข่ตำนานที่ซื้อด้วย Robux ใช้ด่านสูงสุด)
function Config.rollMotherWeight(rng: Random, stage: number?, guaranteedTier: number?): number
	local tiers = Config.getWeightTiers(stage or 1)

	-- ขั้น 1: สุ่ม tier — ใช้จำนวนเต็มล้วน ไม่มี float เข้ามาเกี่ยวเลย
	local roll = rng:NextInteger(1, Config.Balance.Weight.TIER_ROLL_MAX)
	local acc = 0
	local chosenIndex = #tiers -- ตกมาถึงค่านี้ไม่ได้ถ้า validate() ผ่าน แต่กันไว้

	for index, tier in tiers do
		acc += tier.weight
		if roll <= acc then
			chosenIndex = index
			break
		end
	end

	-- ขั้น 1.5: ดันขึ้นถ้าได้ต่ำกว่าที่รับประกันไว้
	-- ทำหลังสุ่มไม่ใช่ก่อน เพื่อให้ยังลุ้น tier ที่สูงกว่าการรับประกันได้ตามปกติ
	if guaranteedTier then
		local floorIndex = math.clamp(math.floor(guaranteedTier), 1, #tiers)
		if chosenIndex < floorIndex then
			chosenIndex = floorIndex
		end
	end

	-- ขั้น 2: สุ่มน้ำหนักภายใน tier ที่ได้ แบบ uniform
	local tier = tiers[chosenIndex]
	return rng:NextInteger(tier.min, tier.max)
end

-- สุ่มน้ำหนักโดยอ่านการรับประกันจากตัวไข่เอง — ใช้ตัวนี้เป็นหลัก
--
-- ⚠️ เรียกตอน "บอสวางไข่ในรัง" ไม่ใช่ตอนฟัก
-- น้ำหนักถูกล็อกตั้งแต่ไข่โผล่ในรัง แล้วเอาไปกำหนดขนาดโมเดลไข่ให้ผู้เล่นเห็น
-- (ไข่ใหญ่ = หนัก) การแย่งไข่จึงมีเป้าหมายจริง ไม่ใช่กดสุ่มมั่ว ๆ
-- ส่วนการสุ่ม "ตัวละคร" ทำตอน **วางไข่ลงสวนฟัก** ด้วย Config.rollCharacter()
-- ⚠️ ย้ายจาก "ตอนฟักเสร็จ" มาเป็น "ตอนวางไข่" แล้ว (เดิมสุ่มตอนฟักเสร็จ) เพราะเวลาฟัก
-- ต้องใช้คลาสของตัวละครมาคำนวณ (Config.getHatchSeconds) — server รู้ผลไว้ก่อนแล้ว
-- แต่ยังไม่บอก client จนกว่าจะฟักเสร็จจริง ความเซอร์ไพรส์ตอนฟักของผู้เล่นจึงยังอยู่ครบ
--
-- ไข่ที่ผูกด่านไว้แล้ว (ไข่จากบอส) ใช้ด่านของตัวเองเสมอ
-- ไข่ที่ไม่ผูกด่าน (ไข่ Robux) ใช้ค่า stage ที่ผู้เรียกส่งมา
function Config.rollMotherWeightForEgg(eggId: string, rng: Random, stage: number?): number?
	local egg = EggTypes[eggId]
	if not egg then
		return nil
	end
	return Config.rollMotherWeight(rng, egg.stage or stage, egg.guaranteedTier)
end

--------------------------------------------------------------------------------
-- ขนาดโมเดล + เวลาฟักตามน้ำหนัก (ใช้ตาราง WeightTiers ฐานเสมอ ไม่ใช่ตารางรายด่าน —
-- ตารางน้ำหนักใช้ชุดเดียวกันทุกด่านอยู่แล้วตามที่ตัดสินไว้)
--------------------------------------------------------------------------------

-- น้ำหนัก (kg) → index ของ tier ใน WeightTiers (1..7) — ต่ำกว่า tier 1 ถือเป็น tier 1,
-- สูงกว่า tier สุดท้ายถือเป็น tier สุดท้าย (กันพังถ้ามีใครส่งค่าผิดช่วงเข้ามา)
function Config.getWeightTierIndex(weight: number): number
	for index, tier in WeightTiers do
		if weight <= tier.max then
			return index
		end
	end
	return #WeightTiers
end

-- ตัวคูณขนาดโมเดลตาม tier ของน้ำหนักนี้ — ใช้ร่วมกันทั้งไข่และแม่ (Config.getEggVisualSize /
-- Config.getMotherVisualSize คูณค่านี้กับฐานคนละค่า)
function Config.getVisualScaleMultiplier(weight: number): number
	local tierIndex = Config.getWeightTierIndex(weight)
	return Config.Balance.VisualScale.WEIGHT_MULTIPLIER[tierIndex]
end

-- ขนาดโมเดลไข่ตามน้ำหนัก — ไข่แสดงขนาดเดียวกันทุกที่ที่เห็น ไม่มีเวอร์ชันย่อ
function Config.getEggVisualSize(weight: number): Vector3
	return scaleVec3(Config.MapDimensions.Blockout.EggSize, Config.getVisualScaleMultiplier(weight))
end

-- ขนาดโมเดลแม่ตามน้ำหนัก — inPen = true คูณ MOTHER_PEN_SHRINK (ตอนนี้ = 1 คือ 1:1
-- เท่ากับตอน "ถือ"/"ส่งรบ" · ทุก tier เท่ากัน)
function Config.getMotherVisualSize(weight: number, inPen: boolean): Vector3
	local multiplier = Config.getVisualScaleMultiplier(weight)
	if inPen then
		multiplier *= Config.Balance.VisualScale.MOTHER_PEN_SHRINK
	end
	return scaleVec3(Config.MapDimensions.Blockout.MotherSize, multiplier)
end

-- เวลาฟักจริง (วินาที) ของไข่ source="boss" — คิดจาก tier น้ำหนัก × ตัวคูณคลาสของตัวละคร
-- ที่จะฟักออกมา
--
-- ⚠️ charId ต้องรู้ผลแล้วก่อนเรียกฟังก์ชันนี้ — เท่ากับว่าต้องสุ่มตัวละคร (Config.rollCharacter)
-- ตั้งแต่ตอน "วางไข่ลงสวนฟัก" ไม่ใช่ตอน "ฟักเสร็จ" เหมือนเดิม (เปลี่ยนจังหวะนี้โดยตั้งใจ —
-- ยืนยันกับผู้ใช้แล้วว่ายอมรับการเปลี่ยนนี้ ดู EggService.placeEgg) ผลลัพธ์ยังไม่บอก client
-- จนกว่าจะฟักเสร็จจริง (server เก็บไว้เงียบ ๆ ใน HatchSlot.charId) ความ "เซอร์ไพรส์" ตอนฟัก
-- จึงยังอยู่ครบสำหรับผู้เล่น ต่างกันแค่ server รู้ผลก่อนเท่านั้น
--
-- ไข่ source="robux" (ไข่ตำนาน) **ไม่ใช้ฟังก์ชันนี้** ใช้ eggType.hatchTime ตรง ๆ เสมอ (คงที่)
function Config.getHatchSeconds(weight: number, charId: string): number
	local hatchery = Config.Balance.Hatchery
	local tierIndex = Config.getWeightTierIndex(weight)
	local base = hatchery.HatchTimeByTier[tierIndex]

	local character = Config.getCharacter(charId)
	local classId = if character then character.class else "C"
	local classMultiplier = hatchery.ClassHatchMultiplier[classId] or 1

	return base * classMultiplier
end

-- ไข่ที่บอสของด่านนั้นวางในรัง (ด่านนอกช่วงถูก clamp)
function Config.getBossEggId(stage: number): string
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	return `egg_stage{clamped}`
end

--------------------------------------------------------------------------------
-- uid
--------------------------------------------------------------------------------
-- ห้ามประกอบ/แยก uid ด้วยมือที่อื่น ใช้สองฟังก์ชันนี้เท่านั้น

function Config.makeUid(userId: number, counter: number): string
	return string.format("%d", userId) .. Config.Uid.SEPARATOR .. string.format("%d", counter)
end

-- คืน (userId ของผู้ฟักคนแรก, เลขนับ) หรือ nil ทั้งคู่ถ้า uid ผิดรูป
function Config.parseUid(uid: string): (number?, number?)
	local at = string.find(uid, Config.Uid.SEPARATOR, 1, true)
	if not at then
		return nil, nil
	end

	local userId = tonumber(string.sub(uid, 1, at - 1))
	local counter = tonumber(string.sub(uid, at + 1))
	if userId == nil or counter == nil then
		return nil, nil
	end

	return userId, counter
end

-- รายการ uid ที่ client ส่งมาเป็นชุด (ขายเป็นชุด UI-2 · ส่งแม่ไปรบเป็นชุด UI-3) — ตรวจรูปร่างอย่างเดียว
-- คืน (รายการ, nil) หรือ (nil, เหตุผลแบบรหัส) → ผู้เรียกแปลงเป็นข้อความของตัวเอง
-- ⚠️ ต้องเป็น array จริง (key = 1..n ครบไม่มีรู ไม่มี key อื่น) · สมาชิกเป็น string ทุกตัว · 1..limit ตัว
-- ⚠️ ไม่ตรวจว่า uid มีอยู่จริง/เป็นของใคร/ซ้ำไหม — เป็นงานของแกนที่เรียกต่อ (ขาย/ส่งไปรบ ทีละตัว)
export type UidListError = "not_array" | "not_string" | "empty" | "too_many"

function Config.parseUidList(raw: unknown, limit: number): ({ string }?, UidListError?)
	if type(raw) ~= "table" then
		return nil, "not_array"
	end
	local count = 0
	for key, value in raw :: { [any]: any } do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return nil, "not_array"
		end
		if type(value) ~= "string" then
			return nil, "not_string"
		end
		count += 1
		-- ⚠️ หยุดนับทันทีที่เกิน — ไม่ไล่ตาราง "ขยะ" ขนาดใหญ่จนจบ
		if count > limit then
			return nil, "too_many"
		end
	end
	if count == 0 then
		return nil, "empty"
	end
	local list: { string } = table.create(count)
	for index = 1, count do
		local value = (raw :: { any })[index]
		if value == nil then
			return nil, "not_array" -- มีรู (key ไม่ต่อเนื่อง)
		end
		list[index] = value
	end
	return list, nil
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

-- ══ ดัชนี (UI-4) ══
-- คลาสเรียงจากธรรมดา → หายากสุด (C → SS) = order มาก → น้อย · ทุกคลาสแสดงแม้ยังไม่ได้สักตัว
function Config.getIndexClasses(): { string }
	local classes: { string } = {}
	for classId in CharacterClasses do
		table.insert(classes, classId)
	end
	table.sort(classes, function(a: string, b: string): boolean
		return CharacterClasses[a].order > CharacterClasses[b].order
	end)
	return classes
end

-- ตัวละครที่เปิดใช้ในคลาสนั้น ตามลำดับ Config.CharacterOrder (1 ช่องดัชนี = 1 ตัวละคร)
-- ⚠️ ตัวละครที่ enabled = false ไม่นับในดัชนี (ได้ไม่ได้อยู่แล้ว) — ถ้าวันหนึ่งปิดตัวที่มีคนเคยได้ไปแล้ว
--   ช่องนั้นหายจากดัชนี แต่ข้อมูลใน discovered ไม่ถูกลบ (เปิดกลับมาก็กลับมาครบ)
function Config.getIndexCharacters(classId: string): { string }
	local list: { string } = {}
	for _, charId in Config.CharacterOrder do
		local character = Characters[charId]
		if character and character.enabled and character.class == classId then
			table.insert(list, charId)
		end
	end
	return list
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

function Config.computePower(weight: number, charId: string?, statuses: { string }?): number
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

	if statuses then
		value *= Config.getStatusEffects(statuses).damageMultiplier
	end

	return math.max(formula.minDamage, value)
end

--------------------------------------------------------------------------------
-- ตัวคูณ damage ตามด่าน
--------------------------------------------------------------------------------

-- ตัวคูณ damage ของกองทัพจากขั้น upgrade ที่ซื้อไว้ (ขั้น 0 = ยังไม่ซื้อ = ×1)
function Config.getArmyDamageMultiplier(damageLevel: number): number
	local clamped = math.clamp(math.floor(damageLevel or 0), 0, Config.Balance.DamageUpgrade.MAX_LEVEL)
	return Config.Balance.DamageUpgrade.STEP_MULTIPLIER ^ clamped
end

-- ⚠️ UI-5: ตัวคูณ damage จากขั้นที่ซื้อด้วย **Robux** — แยกจาก getArmyDamageMultiplier โดยสิ้นเชิง
-- (คนละฟิลด์ใน PlayerData: robuxDamageBonus ไม่ใช่ damageLevel) **ไม่มีเพดาน** ต่างจากแทร็กเงินในเกม
-- ที่ clamp ที่ MAX_LEVEL เพราะไม่มีค่าคงที่ทางฟิสิกส์ผูกกับ damage แบบที่ WalkSpeed ผูกกับความหนากำแพง
function Config.getRobuxDamageMultiplier(robuxDamageSteps: number): number
	local steps = math.max(0, math.floor(robuxDamageSteps or 0))
	return Config.Balance.RobuxBoost.DAMAGE_MULTIPLIER_PER_STEP ^ steps
end

-- เพดานขั้นที่ซื้อได้ตอนนี้ — ⚠️ off-by-one อยู่ตรงนี้ ดูคำอธิบายข้างบน
-- wallProgress = ด่านที่ผู้เล่นอยู่ (= กำแพงที่พังแล้ว + 1) → ด่าน 1 ได้ 8 ขั้น ไม่ใช่ 0
function Config.getMaxDamageLevel(wallProgress: number): number
	local clamped = math.clamp(math.floor(wallProgress), 1, Config.Balance.Stage.COUNT)
	return clamped * Config.Balance.DamageUpgrade.STEPS_PER_STAGE
end

-- ราคาของขั้นที่ `level` (1 = ขั้นแรกของเกม) · คืน nil ถ้าเกิน MAX_LEVEL
function Config.getDamageUpgradeCost(level: number): number?
	local upgrade = Config.Balance.DamageUpgrade
	local target = math.floor(level)
	if target < 1 or target > upgrade.MAX_LEVEL then
		return nil
	end

	local stage = math.floor((target - 1) / upgrade.STEPS_PER_STAGE) + 1
	local indexInStage = (target - 1) % upgrade.STEPS_PER_STAGE
	return upgrade.STAGE_COST_BASE[stage] * upgrade.COST_MULTIPLIER_IN_STAGE ^ indexInStage
end

-- ราคารวมของทุกขั้นที่ปลดล็อกในด่านนั้น (8 ขั้น)
function Config.getStageDamageUpgradeTotal(stage: number): number
	local upgrade = Config.Balance.DamageUpgrade
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	local total = 0
	for index = 1, upgrade.STEPS_PER_STAGE do
		total += Config.getDamageUpgradeCost((clamped - 1) * upgrade.STEPS_PER_STAGE + index) or 0
	end
	return total
end

--------------------------------------------------------------------------------
-- อัปเกรดความเร็ววิ่ง
--------------------------------------------------------------------------------

-- ตัวคูณความเร็วที่ขั้นนั้น (ขั้น 0 = ×1) — ถดถอย ขั้นแรกให้เยอะสุด
function Config.getSpeedMultiplier(level: number): number
	local upgrade = Config.Balance.SpeedUpgrade
	local clamped = math.clamp(math.floor(level), 0, upgrade.MAX_LEVEL)
	if clamped <= 0 then
		return 1
	end
	local progress = clamped / upgrade.MAX_LEVEL
	return 1 + (upgrade.MAX_MULTIPLIER - 1) * progress ^ upgrade.CURVE_EXPONENT
end

-- ความเร็ววิ่งจริงที่ขั้นนั้น (studs/วินาที)
function Config.getWalkSpeed(level: number): number
	return Config.MapDimensions.Player.WalkSpeed * Config.getSpeedMultiplier(level)
end

-- ความเร็วสูงสุดที่เป็นไปได้ในเกม — ตัวตั้งของกฎความหนากำแพง
function Config.getMaxWalkSpeed(): number
	return Config.getWalkSpeed(Config.Balance.SpeedUpgrade.MAX_LEVEL)
end

-- ราคาอัปจากขั้น level ไปขั้นถัดไป · nil = เต็มเพดานแล้ว
-- ⚠️ level เป็น "ขั้นที่มีอยู่ตอนนี้" (0 = ยังไม่ได้ซื้ออะไร) ไม่ใช่ขั้นที่จะซื้อ
function Config.getSpeedUpgradeCost(level: number): number?
	local upgrade = Config.Balance.SpeedUpgrade
	local current = math.floor(level)
	if current < 0 or current >= upgrade.MAX_LEVEL then
		return nil
	end
	return upgrade.BASE_COST * upgrade.COST_MULTIPLIER ^ current
end

-- ราคารวมของทุกขั้นความเร็ว (ซื้อครบตั้งแต่ 0 ถึงเพดาน)
function Config.getSpeedUpgradeTotalCost(): number
	local total = 0
	for level = 0, Config.Balance.SpeedUpgrade.MAX_LEVEL - 1 do
		total += Config.getSpeedUpgradeCost(level) or 0
	end
	return total
end

-- ⚠️ ความหนาขั้นต่ำที่กำแพงทุกชนิดต้องมี — **ผูกกับความเร็วสูงสุดจริง ไม่ใช่เลขตายตัว**
--
-- ที่ความเร็ว v ผู้เล่นขยับ v ÷ PHYSICS_FPS stud ต่อเฟรม
-- กำแพงที่บางกว่านั้นจะถูก "ข้าม" ไปทั้งชิ้นระหว่างสองเฟรมโดยไม่มีการชนเกิดขึ้นเลย
-- คูณ THICKNESS_SAFETY เผื่อกรณีเฟรมตก
--
-- เขียนเป็นสูตรเพราะถ้าวันไหนขึ้นความเร็วแล้วลืมเพิ่มความหนา **เซิร์ฟจะไม่บูต**
-- แทนที่จะปล่อยให้ผู้เล่นไปเจอเองว่าวิ่งทะลุกำแพงได้
function Config.getMinWallThickness(): number
	local upgrade = Config.Balance.SpeedUpgrade
	return Config.getMaxWalkSpeed() / upgrade.PHYSICS_FPS * upgrade.THICKNESS_SAFETY
end

-- ⚠️ UI-5: เพดานความเร็วจริงสูงสุดที่โบนัส Robux ดันไปได้ — คำนวณ **ย้อนกลับ** จากความหนากำแพง
-- ที่สร้างไว้แล้วจริง (ตรงข้ามทิศทางกับ getMinWallThickness ที่คำนวณความหนาจากความเร็ว)
-- เพื่อให้ Robux speed bonus ทะลุเพดานแทร็กปกติ (128) ได้ตามที่ออกแบบไว้ โดย**ไม่ต้องแตะ
-- MapDimensions ที่เป็นโครงหลักที่ล็อกไว้แล้ว** — ความเร็วรวมจริงจะไม่มีทางเกินที่กำแพงที่มีอยู่รับไหว
function Config.getRobuxSpeedHardCap(): number
	local dim = Config.MapDimensions
	local upgrade = Config.Balance.SpeedUpgrade
	local builtThickness = math.min(dim.StageWall.Thickness, dim.Lane.WallThickness, dim.Boundary.Thickness)
	return builtThickness / upgrade.THICKNESS_SAFETY * upgrade.PHYSICS_FPS
end

-- ความเร็ววิ่งจริงที่ใช้ (ปกติ + โบนัส Robux) — เรียกที่นี่ที่เดียว ห้ามคำนวณเองที่อื่น
-- ⚠️ โบนัส Robux ทะลุเพดานแทร็กปกติ (getWalkSpeed สูงสุด 128) ได้ตามที่ออกแบบไว้ แต่ผลรวมจริง
-- **clamp ที่ getRobuxSpeedHardCap() เสมอ** (กันวิ่งทะลุกำแพงที่สร้างไว้แล้ว) และไม่เกิน SPEED_CEILING
function Config.getEffectiveWalkSpeed(speedLevel: number, robuxSpeedSteps: number): number
	local base = Config.getWalkSpeed(speedLevel)
	local steps = math.max(0, math.floor(robuxSpeedSteps or 0))
	local bonus = steps * Config.Balance.RobuxBoost.SPEED_PER_STEP
	local cap = math.min(Config.getRobuxSpeedHardCap(), Config.Balance.SpeedUpgrade.SPEED_CEILING)
	return math.min(cap, base + bonus)
end

-- จำนวนไข่ฟรีตอนกำแพงด่านนั้นพังครั้งแรก (Phase 4A) — ด่านนอกช่วง = 0
function Config.getStageClearBonusEggs(stage: number): number
	return Config.Balance.Combat.STAGE_CLEAR_BONUS_EGGS[stage] or 0
end

-- ข้อความ popup "ผ่านด่าน" (Phase 4B) จาก payload ของ StageClearedNotify → (หัวข้อ, เนื้อความ)
-- หัวข้อ + " " + เนื้อความ = ข้อความเต็มบรรทัดเดียว เช่น "ผ่านด่าน 4 สำเร็จ! ได้รับไข่ฟรี 2 ฟอง • เสียแม่ในสนามรบ 3 ตัว"
-- ⚠️ อยู่ใน Config (ไม่ใช่ใน client) เพื่อให้เทสต์ทุกกรณีได้นอก Studio
-- (0, 0) ไม่ใช่ "ไม่มีอะไรเกิดขึ้น" — server ไม่ยิงกรณีนั้นเลย (CombatService.shouldNotifyStageCleared)
-- จึงแปลว่า "ควรได้ไข่แต่กระเป๋าไข่เต็ม" เสมอ (พฤติกรรมเดิมของ Phase 4A)
function Config.formatStageClearedMessage(stage: number, eggCount: number, deathCount: number): (string, string)
	local title = `ผ่านด่าน {stage} สำเร็จ!`
	local parts: { string } = {}
	if eggCount > 0 then
		table.insert(parts, `ได้รับไข่ฟรี {eggCount} ฟอง`)
	end
	if deathCount > 0 then
		table.insert(parts, `เสียแม่ในสนามรบ {deathCount} ตัว`)
	end
	if #parts == 0 then
		return title, "กระเป๋าไข่เต็ม — ไม่ได้รับไข่ฟรีของด่านนี้"
	end
	return title, table.concat(parts, " • ")
end

-- จำนวนเต็มคั่นหลักพัน: 1234567 → "1,234,567" (เงินเป็นจำนวนเต็มเสมอ)
function Config.formatCoins(value: number): string
	local sign = if value < 0 then "-" else ""
	local digits = string.format("%d", math.abs(math.floor(value)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return sign .. (string.gsub(grouped, "^,", ""))
end

-- ข้อความสรุปผลขายแม่เป็นชุด (UI-2 · SellMothersBatchRequest) — ขึ้นครั้งเดียวต่อชุด
-- ⚠️ อยู่ใน Config (ไม่ใช่ใน EggService) เพื่อให้เทสต์ทุกกรณีได้นอก Studio
function Config.formatSellBatchMessage(sold: number, coins: number, skipped: number): string
	local skippedText = if skipped > 0 then ` · ข้าม {skipped} ตัว (ล็อก / ไม่อยู่ในกระเป๋า / ซ้ำ)` else ""
	if sold <= 0 then
		return `ขายไม่ได้สักตัว{skippedText}`
	end
	return `ขายแม่ {sold} ตัว ได้ ฿{Config.formatCoins(coins)}{skippedText}`
end

-- ข้อความสรุปผลส่งแม่ไปรบเป็นชุด (UI-3 · SendMothersToBattleBatchRequest) — ขึ้นครั้งเดียวต่อชุด
function Config.formatSendBatchMessage(sent: number, rosterCount: number, skipped: number): string
	local maxMothers = Config.Balance.Combat.MAX_BATTLE_MOTHERS
	local skippedText = if skipped > 0 then ` · ข้าม {skipped} ตัว (ล็อก / ไม่อยู่ในกระเป๋า / roster เต็ม / ซ้ำ)` else ""
	if sent <= 0 then
		return `ส่งแม่ไปรบไม่ได้สักตัว (roster {rosterCount}/{maxMothers}){skippedText}`
	end
	return `ส่งแม่ {sent} ตัวไปรบ (roster {rosterCount}/{maxMothers}){skippedText}`
end

-- อัตราปล่อยทหารของด่านนั้น (ตัว/วินาที)
function Config.getReleaseRate(stage: number): number
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	return Config.Balance.Combat.RELEASE_PER_SECOND[clamped]
end

-- อัตราผลิตลูกของแม่ 1 ตัว (ตัว/นาที)
-- แปรตามน้ำหนักด้วยเลขชี้กำลัง WEIGHT_EXPONENT แล้วคูณด้วย upgrade และบัฟสถานะ
-- online = false → คูณ OFFLINE_RATE_RATIO
function Config.getProductionPerMinute(
	motherWeight: number,
	statuses: { string }?,
	productionLevel: number,
	online: boolean?
): number
	local production = Config.Balance.Production

	local rate = production.ONLINE_PER_MINUTE
		* (motherWeight / production.WEIGHT_REFERENCE) ^ production.WEIGHT_EXPONENT
		* Config.getProductionMultiplier(productionLevel)

	if statuses then
		rate *= Config.getStatusEffects(statuses).productionMultiplier
	end

	if online == false then
		rate *= production.OFFLINE_RATE_RATIO
	end

	return rate
end

-- ความจุคลังต่อกอง — แยกเป็นฟังก์ชันไว้เผื่อทำเป็น upgrade ทีหลัง
function Config.getStackCap(): number
	return Config.Balance.Production.STACK_CAP
end

-- ประมาณจำนวนโมเดลทหารฝ่ายเราที่มีชีวิตพร้อมกันบนจอ
-- = อัตราปล่อย × เวลาเดินถึงกำแพง แล้วตัดที่ MAX_VISIBLE_UNITS
-- ส่วนเกินไม่ spawn โมเดล ให้รวมเป็นตัวเลขแทน (วิธีเดียวกับทหารฝ่ายรับ)
function Config.getVisibleUnitCount(stage: number): number
	local alive = Config.getReleaseRate(stage) * Config.Balance.Combat.WALK_SECONDS_TO_WALL
	return math.min(math.ceil(alive), Config.Balance.Combat.MAX_VISIBLE_UNITS)
end

-- damage/HP ของหน่วย 1 ตัวตอนเข้ารบ = พลังพื้นฐาน × ตัวคูณตามด่าน
-- ใช้ได้ทั้งแม่และลูก ส่ง weight ของตัวนั้นเข้ามา
-- พลังจริงตอนเข้ารบ = พลังพื้นฐาน × ตัวคูณที่ซื้อไว้
-- ⚠️ damageLevel เป็นของบัญชีผู้เล่น ไม่ใช่ของแม่รายตัว และคำนวณตอนเข้ารบทุกครั้ง
-- ไม่เก็บตัวคูณติดไปกับกองลูก → ลูกที่สะสมไว้แต่ด่านต้นแรงขึ้นตามผู้เล่น ไม่มีกองตกยุค
--
-- ⚠️ UI-5: `robuxDamageSteps` เป็นพารามิเตอร์เสริม (nil/0 = พฤติกรรมเดิมเป๊ะ ไม่กระทบผู้เล่นที่ไม่จ่าย)
-- คูณเพิ่มจาก getRobuxDamageMultiplier ซึ่งไม่มีเพดาน — สูตรเดิม (computePower × getArmyDamageMultiplier)
-- ไม่ถูกแก้เลยสักตัวอักษร แค่มีตัวคูณอิสระอีกตัวคูณต่อท้าย
function Config.computeBattlePower(
	weight: number,
	charId: string?,
	statuses: { string }?,
	damageLevel: number,
	robuxDamageSteps: number?
): number
	return Config.computePower(weight, charId, statuses)
		* Config.getArmyDamageMultiplier(damageLevel)
		* Config.getRobuxDamageMultiplier(robuxDamageSteps or 0)
end

--------------------------------------------------------------------------------
-- คอก / กระเป๋า
--------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------------------------------------
-- พิกัดในแมพ — คำนวณจาก Config.MapDimensions ทั้งหมด
--------------------------------------------------------------------------------
-- ⚠️ ทุกอย่างที่ต้องรู้ "ของอยู่ตรงไหน" ให้เรียกฟังก์ชันพวกนี้
-- ห้ามคำนวณพิกัดเองใน MapBuilder / PenService / client — ไม่งั้นแก้ Config แล้วจะหลุดกัน
--
-- ══ ระบบพิกัด ══ X ซ้าย→ขวา: ร้านค้า → ลานคอก → เลนรบ · Z แกนขวาง · พื้นที่ Y = 0

-- ความกว้างรวมของลานคอกตามแกน X
function Config.getPenYardWidth(): number
	local map = Config.MapDimensions
	return map.Pen.PerRow * map.Pen.Size.X + (map.Pen.PerRow - 1) * map.Pen.ColumnGap
end

-- ความลึกรวมของลานคอกตามแกน Z (สองแถว + ทางเดินกลาง)
function Config.getPenYardDepth(): number
	local map = Config.MapDimensions
	return map.Pen.Rows * map.Pen.Size.Y + (map.Pen.Rows - 1) * map.Pen.RowGap
end

-- กึ่งกลางคอกแปลงที่ index (1..MAX_PENS) — ลานคอกอยู่กลางแมพที่ X = 0
-- เรียงซ้าย→ขวาในแถวบนก่อน (1..PER_ROW) แล้วค่อยแถวล่าง
function Config.getPenPlotCenter(index: number): Vector3
	local map = Config.MapDimensions
	local perRow = map.Pen.PerRow
	local row = math.floor((index - 1) / perRow) -- 0 = แถวบน (+Z)
	local col = (index - 1) % perRow

	local step = map.Pen.Size.X + map.Pen.ColumnGap
	local x = (col - (perRow - 1) / 2) * step

	-- แถวบนอยู่ +Z แถวล่างอยู่ −Z ห่างจากกึ่งกลางทางเดินเท่ากัน
	local offset = map.Pen.RowGap / 2 + map.Pen.Size.Y / 2
	local z = if row == 0 then offset else -offset

	return vec3(x, 0, z)
end

-- ขอบซ้าย/ขวาของลานคอก
function Config.getPenYardRightX(): number
	return Config.getPenYardWidth() / 2
end

function Config.getPenYardLeftX(): number
	return -Config.getPenYardWidth() / 2
end

-- ต้นเลนรบ = จุดปล่อยทหาร (ต่อจากปลายลานคอกทันที)
function Config.getLaneStartX(): number
	return Config.getPenYardRightX() + Config.MapDimensions.Lane.StartGap
end

-- กึ่งกลางแท่นอัญเชิญบนพื้น (UI-3) — MapBuilder วางแท่น · client ติดจุดกด E · TroopRenderer เริ่มเดินทหารจากตรงนี้
-- ⚠️ ภาพ/จุดกดเท่านั้น ไม่มีการคำนวณรบใดอ่านค่านี้
-- ⚠️ 5B-fix: อยู่**ในเลน (สนามรบ)** หลังช่องประตู = getLaneWallStartX() + EntranceGap + รัศมี (X 177) — เดิม X 148 ในลาน
function Config.getSummonPedestalCenter(): Vector3
	local pedestal = Config.MapDimensions.SummonPedestal
	return vec3(Config.getLaneWallStartX() + pedestal.EntranceGap + pedestal.Diameter / 2, 0, 0)
end

-- ความยาวเลนทั้งเส้น
function Config.getLaneLength(): number
	return Config.MapDimensions.Lane.LengthPerStage * Config.Balance.Stage.COUNT
end

function Config.getLaneEndX(): number
	return Config.getLaneStartX() + Config.getLaneLength()
end

-- X ที่ช่วงของด่านนั้นเริ่ม
function Config.getStageStartX(stage: number): number
	local clamped = math.clamp(stage, 1, Config.Balance.Stage.COUNT)
	return Config.getLaneStartX() + (clamped - 1) * Config.MapDimensions.Lane.LengthPerStage
end

-- X ของกำแพงกั้นด่านนั้น (อยู่ที่ต้นช่วง)
-- ⚠️ คืน nil เมื่อด่านนั้นไม่มีกำแพง (ด่าน 1) — ผู้เรียกต้องเช็ค
function Config.getWallX(stage: number): number?
	if Config.getStageWallHp(stage) <= 0 then
		return nil
	end
	return Config.getStageStartX(stage)
end

-- ระยะจากท้ายช่วงด่าน ถอยกลับมาถึงกึ่งกลางรังบอส
-- คำนวณจากขนาดห้องเอง เพื่อให้ห้องอยู่ในช่วงด่านเสมอแม้ปรับขนาด
function Config.getBossRoomInset(): number
	return Config.MapDimensions.BossRoom.Size.X / 2 + 10
end

-- กึ่งกลางรังบอสของด่านนั้น — อยู่ท้ายช่วง คือ **หลังกำแพง**ของด่านนั้น
function Config.getBossNestCenter(stage: number): Vector3
	local endX = Config.getStageStartX(stage) + Config.MapDimensions.Lane.LengthPerStage
	return vec3(endX - Config.getBossRoomInset(), 0, 0)
end

-- ══ มุมบอสในห้องบอส (5B) ══ ฝั่งมุมของด่านนั้น: +1 = ขวา (+Z) · −1 = ซ้าย (−Z) — ยืนหันไปทางปลายเลน (+X)
-- ⚠️ อ่านจาก BossRoom.CornerSide (สลับฟันปลาต่อด่าน · validate() บังคับ) · ห้ามตัดสินฝั่งเองที่อื่น
function Config.getBossCornerSign(stage: number): number
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	return if Config.MapDimensions.BossRoom.CornerSide[clamped] == "left" then -1 else 1
end

-- กึ่งกลางบอส (บนพื้น) ในห้องบอสด่านนั้น — มุมห้องฝั่ง getBossCornerSign · อีกฝั่งเว้นเป็นทางวิ่ง
function Config.getBossCornerCenter(stage: number): Vector3
	local arena = Config.MapDimensions.BossArena
	local room = Config.getBossNestCenter(stage)
	return vec3(room.X + arena.BossCornerX, 0, room.Z + Config.getBossCornerSign(stage) * arena.BossCornerZ)
end

-- จุดวางไข่ที่ i (1..BossCycle.EGGS_PER_NIGHT) **หลังบอส** (+X) มุมเดียวกับบอส — ตาราง EggColumns คอลัมน์
-- เรียงคอลัมน์ใกล้บอสก่อน · ในคอลัมน์เรียงจากแนวกลางเลนออกไปทางผนัง · แถวกลางตรงกับ Z ของบอส
function Config.getBossEggSpot(stage: number, index: number): Vector3
	local arena = Config.MapDimensions.BossArena
	local total = Config.Balance.BossCycle.EGGS_PER_NIGHT
	local columns = arena.EggColumns
	local rows = math.ceil(total / columns)
	local i = math.clamp(math.floor(index), 1, total) - 1
	local column = i // rows
	local row = i % rows
	local boss = Config.getBossCornerCenter(stage)
	local sign = Config.getBossCornerSign(stage)
	local x = boss.X + arena.EggBackOffset + column * arena.EggColumnGap
	local z = boss.Z + sign * (row - (rows - 1) / 2) * arena.EggRowGap
	return vec3(x, 0, z)
end

-- ══ บอสทุกห้อง (Phase 5A · 5B · 5B-2) ══ MapBuilder วาง · BossService ใช้ · docs/map-layout.md §4.3
-- ⚠️ ทุกพิกัดของบอส/ไข่มาจากชุดนี้ (getBossCornerCenter(ห้อง) · getBossEggSpot(ห้อง, i)) ห้ามคำนวณเองใน MapBuilder/BossService
-- ⚠️ 5B-2: ลบของ "บอสกลางห้องเดียว" แล้ว (getBossArenaCenter · getBossPosition · getBossCycleEggSpot · isInBossArena ·
--   MapDimensions.BossArena.Stage) — ทุกฟังก์ชันรับเลขห้องเอง

-- ความยาวหนึ่งรอบ (กลางวัน + กลางคืน)
function Config.getBossCycleSeconds(): number
	return Config.Balance.BossCycle.DAY_SECONDS + Config.Balance.BossCycle.NIGHT_SECONDS
end

-- ══ กำแพงกั้นกลางคืน (5B) ══ **ปิดช่องทางเข้าเลนพอดี** = ช่องประตูในกำแพงหินขอบแมพฝั่งตะวันออก
-- ⚠️ ผูกกับกำแพงขอบแมพทั้งชุด (X · ความหนา · ความสูง · ช่องประตูกว้าง Lane.Width) — ไม่มีค่าของตัวเองให้ตั้งผิด
--   กว้างเต็มช่อง ไม่มีช่องว่าง ไม่ยื่น · ไม่ทับกำแพงหินข้าง ๆ (ชนปลายกันพอดีที่ Z = ±Lane.Width/2 = กระพริบไม่ได้)
--   เดิม (5A) ขวางกลางเลนที่ X 217.5–222.5 → ย้ายตามแผนผู้ใช้: กลางคืนปิดทั้งสนามรบ ทุกคนอยู่ฝั่งลาน
function Config.getBossBarrierX(): number
	return Config.getEastBoundaryX()
end

function Config.getBossBarrierSize(): Vector3
	local map = Config.MapDimensions
	return vec3(map.Boundary.Thickness, map.Boundary.Height, map.Lane.Width)
end

-- ผิวหน้ากำแพงกั้น (ฝั่งลานกลาง −X) — ตัวเลขนับถอยหลังติดผิวนี้ · หน้าป้อมนับระยะจากผิวนี้ · = ขอบเซฟโซน
function Config.getBossBarrierFrontX(): number
	return Config.getBossBarrierX() - Config.getBossBarrierSize().X / 2
end

-- จุดยืนหน้าป้อมตอนวาปกลางคืน (ฝั่งลานกลาง) · index = 1..World.MAX_PENS · แถวละ GatherPerRow คน ไม่ซ้อนกัน (validate())
function Config.getBossGatherSpot(index: number): Vector3
	local arena = Config.MapDimensions.BossArena
	local perRow = arena.GatherPerRow
	local i = math.max(1, math.floor(index)) - 1
	local row = i // perRow
	local col = i % perRow
	local x = Config.getBossBarrierFrontX() - arena.GatherFrontGap - row * arena.GatherRowGap
	local z = (col - (perRow - 1) / 2) * arena.GatherSpacingZ
	return vec3(x, 0, z)
end

-- ══ โซนของแมพ (5B · แผนผู้ใช้ docs/boss-plan.md) ══
--   เซฟโซน = คอกทั้งหมด + ลานกลาง (ทุกอย่างฝั่งตะวันตกของแนวกำแพงหินขอบแมพฝั่งตะวันออก)
--   สนามรบ = ตั้งแต่ปากทางเข้าเลน (ผิวหน้ากำแพงกั้น X 157.5) เป็นต้นไป
--   ห้องด่าน N = ช่วงเลนของด่าน N ที่เดินได้จริง · ด่าน 1 = ปากเลน → ผิวหน้ากำแพงด่าน 2
-- ⚠️ server ตัดสินจากตำแหน่งตัวละครที่ server เห็นเท่านั้น (ส่งไข่เข้ากระเป๋า · แบ่งเงินบอส · ถืออาวุธ)

-- ขอบเซฟโซน = ผิวหน้ากำแพงกั้น (ฝั่งลาน) = ผิวด้านในของกำแพงหินขอบแมพฝั่งตะวันออก
function Config.getSafeZoneEdgeX(): number
	return Config.getBossBarrierFrontX()
end

-- อยู่ในเซฟโซนไหม — X น้อยกว่าขอบ (ฝั่งลาน) · ลานล้อมด้วยกำแพงหินอยู่แล้ว ไม่ต้องเช็คแกนอื่น
function Config.isInSafeZone(position: Vector3): boolean
	return position.X < Config.getSafeZoneEdgeX()
end

-- ช่วง X ของห้องด่านนั้น (minX, maxX) — จากผิวหลังกำแพงด่านนั้น (ด่านไม่มีกำแพง = ขอบเซฟโซน) ถึงผิวหน้ากำแพง
-- ด่านถัดไป (ด่านสุดท้าย = ปลายเลน) · ความหนากำแพงด่านอ่าน StageWall.Thickness เหมือน WallRenderer
function Config.getStageRoomRangeX(stage: number): (number, number)
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	local half = Config.MapDimensions.StageWall.Thickness / 2
	local wallX = Config.getWallX(clamped)
	local minX = if wallX then wallX + half else Config.getSafeZoneEdgeX()
	local maxX = Config.getLaneEndX()
	for next = clamped + 1, Config.Balance.Stage.COUNT do
		local nextWallX = Config.getWallX(next)
		if nextWallX then
			maxX = nextWallX - half
			break
		end
	end
	return minX, maxX
end

function Config.isInStageRoom(stage: number, position: Vector3): boolean
	local minX, maxX = Config.getStageRoomRangeX(stage)
	return position.X >= minX and position.X <= maxX and math.abs(position.Z) <= Config.getLaneHalfWidthAt(position.X)
end

-- 5B-2: ยืนอยู่ห้องด่านไหน (nil = ไม่อยู่ห้องไหนเลย — เซฟโซน · ในเนื้อกำแพงด่าน · นอกเลน)
-- ⚠️ server ใช้ตัดสินว่า "ตี/หยิบ/แบ่งเงิน/ถืออาวุธ" ห้องไหน — ตำแหน่งตัวละครที่ server เห็นเท่านั้น
--   และ**ต้องเช็คสิทธิ์คู่กันเสมอ** (canAccessBossRoom) เพราะตำแหน่งปลอมได้ ส่วนกำแพงด่านเป็นของ client
function Config.getStageRoomAt(position: Vector3): number?
	for stage = 1, Config.Balance.Stage.COUNT do
		if Config.isInStageRoom(stage, position) then
			return stage
		end
	end
	return nil
end

-- 5B-2 (ผู้ใช้ยืนยัน): มีสิทธิ์เข้าห้องด่านนี้ไหม = **พังกำแพงด่าน N แล้ว** (ห้องที่ไม่มีกำแพง = ห้อง 1 ทุกคนเข้าได้)
-- วัดจาก wallProgress (จำนวนด่านที่พังติดต่อกันนับจากด่าน 1 · CombatService.recomputeWallProgress) = สิทธิ์เข้าพื้นที่บอส
-- คนที่อยู่ด่านไกลกว่ามีสิทธิ์ทุกห้องที่ผ่านมาแล้ว (wallProgress 5 → ห้อง 1–5) · ค่าแปลก = ไม่มีสิทธิ์
-- ⚠️ ตัวกันหลักของ "ปลอมตำแหน่ง" — กำแพงด่านวาด/ชนฝั่ง client ล้วน server เชื่อตำแหน่งอย่างเดียวไม่ได้
function Config.canAccessBossRoom(wallProgress: number?, room: number?): boolean
	if type(room) ~= "number" or room % 1 ~= 0 or room < 1 or room > Config.Balance.Stage.COUNT then
		return false
	end
	-- กำแพงด่านที่ใกล้ห้องนี้ที่สุด (นับถอยจากห้องนี้) ต้องพังแล้ว — ไม่มีกำแพงเลยก่อนถึงห้องนี้ (ห้อง 1) = เข้าได้ทุกคน
	for stage = room, 1, -1 do
		if Config.getWallX(stage) ~= nil then
			return type(wallProgress) == "number" and wallProgress >= stage
		end
	end
	return true
end

-- เลขนับถอยหลังบนกำแพงกั้น จาก "วินาทีที่เหลือของกลางคืน" → 59, 58 … 0 (เลขละ 1 วินาทีพอดี)
-- ⚠️ ceil − 1 ไม่ใช่ floor: เหลือ 60 เต็ม (วินาทีแรก) ต้องขึ้น 59 ไม่ใช่ 60 · เหลือ 0.x = 0
function Config.getBossCountdownValue(remainingSeconds: number): number
	local nightSeconds = Config.Balance.BossCycle.NIGHT_SECONDS
	return math.clamp(math.ceil(remainingSeconds) - 1, 0, math.max(0, nightSeconds - 1))
end

-- ข้อความเหตุการณ์บอส (BossEventNotify(kind, a?, b?, c?)) — client โชว์เป็น toast · ข้อความล็อกอัญเชิญอยู่ที่ BOSS_LOCK_MESSAGE
-- ⚠️ ตัวเลข (a/b/c) มาจาก server เสมอ (น้ำหนักไข่ · เงินที่ได้ · จำนวนคนแบ่ง · เลขห้อง) — client แค่จัดรูปข้อความ
-- 5B-2: "heavy" รับ**รายการ** a = { { room = ห้อง, weight = kg } } เรียงตามห้อง → ข้อความเดียวรวมทุกห้อง
function Config.formatBossEventMessage(kind: string, a: any?, b: number?, c: number?): string
	if kind == "night" then
		return "🌙 กลางคืนแล้ว — บอสตื่นครบทุกห้อง · รอเช้าแล้วเข้าไปตีห้องที่พังกำแพงถึงได้"
	elseif kind == "day" then
		return "☀️ เช้าแล้ว — กำแพงกั้นเปิด เข้าไปตีบอสได้"
	elseif kind == "killed" then
		-- 5B-2: a = ห้องที่บอสตาย (ไม่ส่ง = ข้อความเดิม)
		return if type(a) == "number" then `กำจัดบอสห้อง {a} แล้ว!` else "กำจัดบอสแล้ว!"
	elseif kind == "locked" then
		-- ส่งเฉพาะคนที่เพิ่งติดล็อก (ไม่ใช่ทุกคน) — บอกว่าทำไมทหารหยุดเอง · 5B-2: a = ห้อง (= ด่านที่เพิ่งพังกำแพง)
		local where = if type(a) == "number" then `พังกำแพงด่าน {a} แล้วแต่บอสห้อง {a} ยังอยู่` else "พังกำแพงแล้วแต่บอสยังอยู่"
		return `🔒 {where} — {Config.BOSS_LOCK_MESSAGE}`
	-- ══ 5B ══
	elseif kind == "heavy" then
		-- ทุกคน ตอนบอสเกิด · เฉพาะคืนที่มีไข่หนักเกิน HEAVY_EGG_ALERT_KG · 5B-2: ทุกห้องรวมในข้อความเดียว
		if type(a) ~= "table" or #a == 0 then
			return ""
		end
		local parts: { string } = {}
		for _, entry in a do
			if type(entry) == "table" and type(entry.room) == "number" and type(entry.weight) == "number" then
				table.insert(parts, `ห้อง {entry.room} ไข่ {Config.formatCoins(entry.weight)} กก.`)
			end
		end
		if #parts == 0 then
			return ""
		end
		return `🥚 คืนนี้: {table.concat(parts, " · ")}`
	elseif kind == "picked" then
		-- 5B-fix: ไม่บอกน้ำหนักตอนหยิบ (ให้ลุ้น) — เฉลยตอนเก็บเข้ากระเป๋า ("delivered")
		return "🥚 หยิบไข่บอสแล้ว — วิ่งกลับเซฟโซน (ลานกลาง) เพื่อเก็บเข้ากระเป๋า"
	elseif kind == "delivered" then
		return `เก็บไข่บอสแล้ว ({Config.formatCoins(if type(a) == "number" then a else 0)} กก.)`
	elseif kind == "bagFull" then
		return "กระเป๋าไข่เต็ม — ถือไข่บอสไว้ก่อน มีที่ว่างเมื่อไหร่เก็บให้เอง"
	elseif kind == "eggLost" then
		return "🌙 กลางคืนแล้ว — ไข่บอสที่ถืออยู่หายไป (ไข่ชุดใหม่เกิดพร้อมบอส)"
	elseif kind == "reward" then
		-- 5B-2: c = ห้อง (ไม่ส่ง = ข้อความเดิม)
		local from = if type(c) == "number" then `บอสห้อง {c}` else "บอส"
		return `ได้ ${Config.formatCoins(if type(a) == "number" then a else 0)} จาก{from} (แบ่ง {b or 0} คน)`
	elseif kind == "pickupAlive" then
		return "ต้องกำจัดบอสห้องนี้ก่อนถึงหยิบไข่ได้"
	elseif kind == "pickupCarrying" then
		return "ถือไข่บอสได้ทีละฟอง — เอาฟองที่ถืออยู่ไปเก็บที่เซฟโซนก่อน"
	elseif kind == "pickupTaken" then
		return "ไข่ฟองนี้ไม่อยู่แล้ว"
	elseif kind == "pickupRange" then
		return "อยู่ไกลไข่เกินไป — เดินเข้าไปใกล้ ๆ ก่อน"
	elseif kind == "pickupAccess" then
		-- 5B-2: ยังพังกำแพงไม่ถึงห้องนี้ (ปกติเดินมาไม่ถึงอยู่แล้ว — กันตำแหน่งปลอม)
		return "ยังพังกำแพงไม่ถึงห้องนี้ — หยิบไข่ห้องนี้ไม่ได้"
	elseif kind == "pickupHold" then
		-- 5B-2: server จับเวลากดค้างเองแล้วไม่ครบ
		return `ต้องกด E ค้างให้ครบ {Config.Balance.BossCycle.EGG_PICKUP_HOLD_SECONDS} วินาที`
	end
	return ""
end

-- เหตุการณ์ที่เป็น "ทำไม่สำเร็จ/เสียของ" → client โชว์ toast สีเตือน (ที่เหลือ = สีปกติ)
function Config.isBossEventWarning(kind: string): boolean
	-- 5B-2: "pickupAccess" / "pickupHold" ขึ้นต้นด้วย "pickup" → สีเตือนอัตโนมัติ
	return kind == "locked"
		or kind == "bagFull"
		or kind == "eggLost"
		or string.sub(kind, 1, 6) == "pickup"
end

-- ⚠️ ข้อความเดียวทั้ง server (ปฏิเสธคำขอ) และ client (โชว์ในหน้าต่างอัญเชิญ) — Phase 5A ล็อกอัญเชิญ
Config.BOSS_LOCK_MESSAGE = "กำจัดบอสก่อนจึงจะอัญเชิญต่อได้"
-- ชื่อของใน Workspace/ReplicatedStorage ที่ server สร้างและ client หาด้วยชื่อเดียวกัน
Config.BOSS_STATE_FOLDER = "BossState" -- Folder ใน ReplicatedStorage · Attribute: Phase · PhaseEndsAt · Cycle
--   5B-2: + ต่อห้อง Config.getBossStateAttribute("BossAlive" | "BossHp" | "BossMaxHp", ห้อง) = "BossAlive3" ฯลฯ
--   (เดิม BossAlive/BossHp/BossMaxHp ตัวเดียวของบอสกลาง — ลบแล้ว)
Config.BOSS_ARENA_NAME = "BossArena" -- Model ใต้ Workspace.Map
Config.BOSS_BARRIER_NAME = "BossBarrier" -- Part ใน BossArena (กำแพงกั้นกลางคืน)
Config.BOSS_MODEL_NAME = "CycleBoss" -- Model ใน BossArena (ตัวบอส) · 5B-2: ชื่อจริง "CycleBoss{ห้อง}" (Config.getBossModelName)
Config.WEAPON_TOOL_NAME = "Weapon" -- Tool ที่ server ใส่ Backpack ให้ทุกคน (ถือ/เก็บอัตโนมัติในห้องบอสที่มีสิทธิ์)
-- 5C: Attribute บน Tool = ขั้นกระบองที่ประกอบไว้ (server เทียบกับ weaponLevel ทุกจังหวะ tick แล้วประกอบใหม่ถ้าไม่ตรง)
Config.CLUB_TIER_ATTRIBUTE = "ClubTier"

-- ══ 5C: หน้าตากระบองแต่ละขั้น ══ (ของสวย ๆ ไม่ใช่ลูกบิดสมดุล จึงไม่อยู่ใน Balance)
-- ไม้ → หิน → เหล็ก → ทอง → เรืองแสง · ขนาดโตตามขั้น · handle = ด้าม (ยาวตามแกน Y) · head = หัวกระบองปลายด้าม
-- material เป็นชื่อ Enum.Material (Config เทสต์นอก Studio ได้ ไม่มี Enum) · glow = ความสว่างไฟ (0 = ไม่มี)
-- ⚠️ server ประกอบ Part จริงใน Tool (BossService) · client วาดรูปเล็ก 2D ในร้าน (WeaponShopWindow) จากสีชุดเดียวกัน
export type ClubVisual = {
	name: string,
	handleLength: number,
	handleThickness: number,
	handleColor: Color3,
	handleMaterial: string,
	headSize: Vector3,
	headColor: Color3,
	headMaterial: string,
	glow: number,
}
local function club(
	name: string,
	handleLength: number,
	handleColor: Color3,
	handleMaterial: string,
	headWidth: number,
	headLength: number,
	headColor: Color3,
	headMaterial: string,
	glow: number
): ClubVisual
	return {
		name = name,
		handleLength = handleLength,
		handleThickness = 0.35,
		handleColor = handleColor,
		handleMaterial = handleMaterial,
		headSize = vec3(headWidth, headLength, headWidth),
		headColor = headColor,
		headMaterial = headMaterial,
		glow = glow,
	}
end
local WOOD = rgb(120, 80, 45)
local DARK_WOOD = rgb(85, 55, 32)
local GRIP = rgb(60, 40, 30)
Config.ClubVisuals = {
	club("กระบองไม้", 2.6, WOOD, "Wood", 0.9, 1.3, rgb(150, 105, 60), "Wood", 0),
	club("กระบองไม้แกร่ง", 2.7, DARK_WOOD, "Wood", 1.0, 1.45, rgb(105, 68, 38), "WoodPlanks", 0),
	club("กระบองหิน", 2.8, WOOD, "Wood", 1.1, 1.55, rgb(125, 125, 130), "Slate", 0),
	club("กระบองหินแกรนิต", 2.9, DARK_WOOD, "Wood", 1.2, 1.65, rgb(95, 92, 105), "Granite", 0),
	club("กระบองเหล็ก", 3.0, GRIP, "Fabric", 1.3, 1.75, rgb(150, 155, 165), "Metal", 0),
	club("กระบองเหล็กกล้า", 3.1, GRIP, "Fabric", 1.4, 1.85, rgb(185, 190, 200), "DiamondPlate", 0),
	club("กระบองทอง", 3.2, GRIP, "Fabric", 1.5, 1.95, rgb(225, 180, 60), "Metal", 0),
	club("กระบองทองคำแท้", 3.3, rgb(120, 30, 30), "Fabric", 1.6, 2.05, rgb(255, 205, 70), "Foil", 0.6),
	club("กระบองเรืองแสง", 3.4, rgb(30, 40, 70), "Metal", 1.7, 2.15, rgb(90, 220, 255), "Neon", 1.5),
	club("กระบองเทพ", 3.6, rgb(255, 225, 140), "Neon", 1.9, 2.35, rgb(255, 245, 190), "Neon", 3),
} :: { ClubVisual }
-- ══ 5B: ไข่บอส ══
Config.BOSS_EGG_FOLDER = "BossEggs" -- Folder ใน BossArena · Part ไข่อยู่ตลอด ซ่อน/โชว์ตามสถานะ
--   5B-2: ชื่อ Part = Config.getBossEggPartName(ห้อง, i) = "BossEgg{ห้อง}_{i}" (i = 1..EGGS_PER_NIGHT) · 9 × 6 = 54 ฟอง
-- Attribute บน Part ไข่: Room (1..9 · 5B-2) · Index (1..N) · Status ("none" | "resting" | "carried" | "gone")
--   ⚠️ 5B-fix: **ไม่มี Weight** — ไม่ส่งน้ำหนักให้ client (ให้ผู้เล่นลุ้น · เห็นแค่ขนาดไข่)
--   client ติดจุดกด E (UiKit.prompt) ที่ Part พวกนี้ · เปิดเฉพาะ Status = "resting" + บอสห้องนั้นตายแล้ว + ตัวเองไม่ได้ถือไข่

-- 5B-2: ชื่อ Attribute สถานะบอสต่อห้องบน BossState ("BossAlive3") — server ตั้ง · client อ่านชื่อเดียวกัน
function Config.getBossStateAttribute(field: string, room: number): string
	return `{field}{room}`
end

function Config.getBossModelName(room: number): string
	return `{Config.BOSS_MODEL_NAME}{room}`
end

function Config.getBossEggPartName(room: number, index: number): string
	return `BossEgg{room}_{index}`
end
Config.BOSS_EGG_CARRY_ATTRIBUTE = "CarryingBossEgg" -- Attribute บน Player: true = กำลังถือไข่บอส (server ตั้ง)
Config.BOSS_CARRIED_EGG_NAME = "CarriedBossEgg" -- Part ใน character ของคนถือ (server สร้าง · ทุกคนเห็น)

-- ══ ร้านค้า ══ แผงเล็ก ๆ วางเรียงติดกันที่ขอบซ้ายของลานคอก ตรงกลางผนังด้านหลัง (UI-2)
-- กึ่งกลางแนวแผง (ใช้เป็น "ตำแหน่งร้าน" ตอนวัดระยะ)
function Config.getShopCenter(): Vector3
	local map = Config.MapDimensions
	local x = Config.getPenYardLeftX() - map.Shop.Gap - map.Shop.StallSize.X / 2
	return vec3(x, 0, 0)
end

-- กึ่งกลางแผงที่ i (1..SHOP_STALL_COUNT) — เรียงตามแกน Z ติดกัน สมมาตรรอบ Z = 0
function Config.getShopStallCenter(index: number): Vector3
	local map = Config.MapDimensions
	local center = Config.getShopCenter()
	local count = map.Shop.StallCount
	-- ⚠️ UI-2: เรียงติดกันกลางผนังด้านหลัง สมมาตรรอบ Z = 0 · เว้นช่องเดิน Shop.StallGap ระหว่างแผง
	-- (เดิมขนาบทางเดินกลาง Z = ±51 — ผลทดสอบ Studio: แยกไปคนละฝั่ง ไกลกันเกิน)
	local spacing = map.Shop.StallSize.Y + map.Shop.StallGap -- กึ่งกลางแผงถึงกึ่งกลางแผงถัดไป
	local offset = (index - (count + 1) / 2) * spacing
	return vec3(center.X, center.Y, offset)
end

-- ══ ขอบเขตพื้นของลานคอก ══ (รวมแถบร้านค้าทางซ้าย + แถบหญ้านอกกำแพงใส)
-- ⚠️ ต้องบวก BOUNDARY_MARGIN ด้วยเสมอ
-- กำแพงใสวางถอยเข้ามาจากขอบพื้นเท่ากับ margin (ดู MapBuilder.buildBoundary)
-- ถ้าพื้นไม่โตตาม การดัน margin ขึ้นจะกลายเป็นการ **หดกำแพงเข้ามากินพื้นที่เล่น**
-- แทนที่จะเป็นการเพิ่มแถบหญ้านอกกำแพง — เคยพลาดตรงนี้แล้วกำแพงกินเข้าไปในคอก 30 studs
function Config.getPlazaMinX(): number
	local map = Config.MapDimensions
	return Config.getShopCenter().X - map.Shop.StallSize.X / 2 - map.Shop.Gap - map.Boundary.Margin
end

-- ⚠️ **ไม่บวก margin แบบสามด้านที่เหลือ** เพราะจุดนี้ = ขอบคอกพอดี = ต้นเลนรบ
-- (Lane.StartGap = 0 บังคับให้พื้นลานกับพื้นเลนต่อกันสนิทไม่มีช่องว่าง)
-- ดังนั้น "ขอบพื้นฝั่งตะวันออก" กับ "ต้นเลน" ต้องเป็นจุดเดียวกันเป๊ะ ห้ามบวกอะไรเข้าไปตรงนี้
-- ระยะห่างระหว่างรั้วคอกกับกำแพงใสฝั่งนี้คำนวณแยกไว้ที่ Config.getEastBoundaryX() แทน
function Config.getPlazaMaxX(): number
	return Config.getPenYardRightX()
end

-- ══ กำแพงใสฝั่งตะวันออก (ติดปากทางเข้าเลนรบ) ══
-- ⚠️ ห้ามใช้ getPlazaMaxX() ตรง ๆ เป็นตำแหน่งกำแพง — จุดนั้นชนกับขอบคอกคอลัมน์ขวาสุดพอดี
-- (รั้วไม้ของคอกวางอยู่ที่ขอบเป๊ะเหมือนกัน) เคยเป็นบั๊ก "รั้วซ้อนกำแพง" ตรงจุดปล่อยทหารด่าน 1
-- ดันออกมาอีก Shop.Gap studs ให้ได้ระยะห่างเท่ากับที่กำแพง North/South มีจากคอกอยู่แล้ว
-- (getPlazaHalfDepth ก็บวก Shop.Gap ก่อนบวก Margin ด้วยเหตุผลเดียวกัน)
-- ⚠️ ใช้ฟังก์ชันนี้ทั้งฝั่งวางกำแพง (MapBuilder.buildBoundary) และฝั่งต่อพื้นหญ้าปีก
-- (MapBuilder.buildPlaza) ห้ามคำนวณเลขนี้แยกกันสองที่ — เคยพลาดแบบเดียวกันมาแล้วกับ
-- Y ของพื้นคอก (ดู Config.getPenRestingY)
function Config.getEastBoundaryX(): number
	return Config.getPlazaMaxX() + Config.MapDimensions.Shop.Gap
end

-- ══ กำแพงข้างเลน: จุดเริ่ม ══ เสมอผิว**ด้านนอก** (ฝั่งเลน) ของกำแพงหินขอบแมพฝั่งตะวันออก (UI-2 · UI-fix รอบ 1)
-- ⚠️ เดิมเริ่มที่ต้นเลน (getLaneStartX = ขอบคอกคอลัมน์ขวา X 140) → ยื่นเข้าลานเกินแนวกำแพงขอบแมพ 17.5 studs
--   ทั้งสองฝั่งปากเลน (ข้างคอก 3 และคอก 6)
-- ⚠️⚠️ **UI-fix รอบ 1**: เคยลองให้เริ่มที่ผิว**ด้านใน** (`- Thickness/2` = X 157.5) มาก่อน แต่ผิวด้านในนั้น
-- คือหน้าตัดเดียวกับที่กำแพงขอบแมพเริ่มต้น (กำแพงขอบแมพหนา `Boundary.Thickness` เต็ม ๆ) → กำแพงข้างเลน
-- (แนวโค้งไปตามแกน X) กับกำแพงขอบแมพ (แนวไปตามแกน Z) เกิด**หน้าตัดซ้อนทับกันพอดีที่ระนาบเดียวกัน**
-- ตลอดความหนากำแพงขอบแมพ (5 studs) = z-fighting (ภาพกระพริบ) ตรงมุมปากเลนทั้งสองฝั่ง
-- แก้โดยขยับจุดเริ่มไปที่ผิว**ด้านนอก** (`+ Thickness/2`) แทน — กำแพงสองชิ้นชนกันพอดี (ไม่มีช่อง ไม่ทับกัน)
-- เหมือนกำแพงจริงสองผืนที่ต่อชนกัน ไม่ใช่ซ้อนกัน
-- ⚠️ ขยับแค่ "ตัวกำแพงข้างเลน" — ต้นเลน · พื้นเลน · จุดปล่อยทหาร · ทางเดินทหาร · ความยาวเลน · ระยะการรบ
--   ยังอ่าน getLaneStartX เหมือนเดิม ไม่มีอะไรเปลี่ยน · จุดปล่อยทหารจึงอยู่ตรงปากเลน ก่อนถึงกำแพงข้าง
function Config.getLaneWallStartX(): number
	return Config.getEastBoundaryX() + Config.MapDimensions.Boundary.Thickness / 2
end

-- ══ พื้นเลน (สีน้ำตาล): จุดเริ่ม ══ เสมอผิว**ด้านใน** (ฝั่งลาน) ของกำแพงหินขอบแมพ = ขอบช่องประตูเลน (5B)
-- ⚠️ เดิมพื้นเลนเริ่มที่ต้นเลน (getLaneStartX = X 140) → แผ่นน้ำตาลยื่นออกมาบนหญ้าในลาน 17.5 studs
--   ช่วง X 140 → ค่านี้ ตรงช่อง Z ของเลน เป็นหญ้าแทน (MapBuilder "LaneMouthGrass")
-- ⚠️ **ภาพล้วน** — ไม่มีการคำนวณใดอ่านค่านี้ · ต้นเลน · แท่นอัญเชิญ · ทางเดินทหาร · ความยาวเลน · ระยะการรบ
--   ยังอ่าน getLaneStartX เหมือนเดิม (validate() บังคับว่าค่านี้ไม่ก่อนต้นเลน)
function Config.getLaneFloorStartX(): number
	return Config.getEastBoundaryX() - Config.MapDimensions.Boundary.Thickness / 2
end

-- ขอบพื้นจริงฝั่งตะวันออก — แถบหญ้าที่มองเห็นได้แต่เดินไปไม่ถึง เท่ากับสามด้านที่เหลือ
-- (กำแพงถอยเข้ามาจากขอบพื้นเท่ากับ Boundary.Margin เหมือนกันทุกด้าน)
function Config.getEastFloorEdgeX(): number
	return Config.getEastBoundaryX() + Config.MapDimensions.Boundary.Margin
end

-- ความลึกของลานต้องคลุมทั้งคอกและแผงร้าน + แถบหญ้านอกกำแพงใส
-- ⚠️ เหตุผลที่บวก BOUNDARY_MARGIN เหมือนกับ getPlazaMinX ข้างบน
function Config.getPlazaHalfDepth(): number
	local map = Config.MapDimensions
	local byPens = Config.getPenYardDepth() / 2
	local byStalls = math.abs(Config.getShopStallCenter(1).Z) + map.Shop.StallSize.Y / 2
	return math.max(byPens, byStalls) + map.Shop.Gap + map.Boundary.Margin
end

-- ครึ่งความกว้างของเลนตรงจุด X นั้น — ผายออกตรงรังบอส
-- ⚠️ รังบอสกว้างกว่าเลน กำแพงข้างเลนจึงต้องเดินเป็นขั้นตรงห้อง ไม่ใช่เส้นตรงยาว
function Config.getLaneHalfWidthAt(x: number): number
	local map = Config.MapDimensions
	local half = map.Lane.Width / 2
	local roomHalfX = map.BossRoom.Size.X / 2
	for stage = 1, Config.Balance.Stage.COUNT do
		local center = Config.getBossNestCenter(stage)
		if x >= center.X - roomHalfX and x <= center.X + roomHalfX then
			return math.max(half, map.BossRoom.Size.Y / 2)
		end
	end
	return half
end

-- ══ วางของบนพื้นคอก ══
-- ⚠️ **ทั้งแม่และไข่ต้องใช้ชุดฟังก์ชันนี้ ห้ามคำนวณ Y เอง**
-- เคยคำนวณแยกกันสองที่แล้วไข่ลอยเหนือพื้น 0.4 studs อยู่หลายรอบโดยไม่มีใครจับได้
-- (แม่นั่งพื้นพอดีเพราะบังเอิญเป็นทรงกล่อง ส่วนไข่เป็นทรงกลมซึ่งคิดรัศมีคนละแบบ)

-- ผิวบนของแผ่นพื้นคอก = ระดับที่ของทุกอย่างในคอกวางอยู่
-- แผ่นพื้นสร้างที่ Y = 0 แล้วยกขึ้นครึ่งความสูง จึงกินช่วง 0 .. FloorThickness
function Config.getPenFloorY(): number
	return Config.MapDimensions.Pen.FloorThickness
end

-- ⚠️ รัศมีจริงของ Part ที่ `Shape = Ball`
-- **Roblox วาดลูกบอลด้วยเส้นผ่านศูนย์กลาง = min(X, Y, Z) ไม่ใช่ Y**
-- แกนที่เหลือถูกเพิกเฉยทั้งหมด · ไข่ blockout ขนาด (3, 3.8, 3) จึงเป็นทรงกลมเส้นผ่านศูนย์กลาง 3
-- ไม่ใช่ 3.8 → ใครใช้ Y/2 เป็นรัศมีจะได้ค่ามากเกินจริงแล้วของลอย
function Config.getBallRadius(size: Vector3): number
	return math.min(size.X, size.Y, size.Z) / 2
end

-- Y ของ **จุดศูนย์กลาง** Part ที่วางแตะพื้นคอกพอดี
-- ส่งครึ่งความสูงจริงของ Part เข้ามา (ทรงกล่อง = Y/2 · ทรงกลม = getBallRadius)
-- ⚠️ ของที่ขนาดต่างกันทุกฟองก็ใช้ได้ เพราะรับครึ่งความสูงของชิ้นนั้น ๆ ไม่ได้อ่านค่ากลาง
function Config.getPenRestingY(halfHeight: number): number
	return Config.getPenFloorY() + halfHeight
end

-- จุดที่ผู้เล่นเกิด — ⚠️ เกิดใกล้คอกตัวเอง ไม่ต้องวิ่งข้ามลานไปหา
-- ยืนที่ทางเดินกลางตรงหน้าคอกแปลงนั้นพอดี
function Config.getSpawnPointForPen(index: number): Vector3
	local center = Config.getPenPlotCenter(index)
	local map = Config.MapDimensions
	-- ขยับเข้าหาทางเดินกลาง (ฝั่งตรงข้ามกับด้านนอกของคอก)
	local toward = if center.Z > 0 then -1 else 1
	local z = center.Z + toward * (map.Pen.Size.Y / 2 + map.Pen.RowGap / 4)
	return vec3(center.X, 0, z)
end

-- จุดเกิดกลาง (เผื่อกรณียังไม่ได้คอก) — กลางทางเดิน
function Config.getSpawnPoint(): Vector3
	return vec3(0, 0, 0)
end

-- ══ ประตูคอก ══ Z ของแนวรั้วที่เว้นช่องประตู + ทิศ "ออกไปทางทางเดินกลาง" ตามแกน Z
-- (−1 = คอกแถวบน ทางเดินอยู่ฝั่ง −Z · +1 = คอกแถวล่าง ทางเดินอยู่ฝั่ง +Z)
-- ⚠️ MapBuilder วางรั้วประตู/ป้ายชื่อ และป้าย UI-2 จากค่าชุดนี้ — ห้ามคำนวณแยกเอง
function Config.getPenGateLine(index: number): (number, number)
	local center = Config.getPenPlotCenter(index)
	local halfZ = Config.MapDimensions.Pen.Size.Y / 2
	if center.Z > 0 then
		return center.Z - halfZ, -1
	end
	return center.Z + halfZ, 1
end

-- ป้ายชื่อ "คอก N" — ข้างประตูฝั่ง +X (ไม่ใช่กลางประตู กันเดินชน) · คืนจุดบนพื้นใต้เสา
function Config.getPenNameSignSpot(index: number): Vector3
	local pen = Config.MapDimensions.Pen
	local center = Config.getPenPlotCenter(index)
	local gateZ, outward = Config.getPenGateLine(index)
	local x = center.X + pen.GateWidth / 2 + pen.SignGateClearance + pen.SignSize.X / 2
	return vec3(x, 0, gateZ + outward * pen.SignSize.Z * 2)
end

export type PenSignKind = "speed" | "pen"
-- ป้ายสองชนิดที่ปักข้างประตูทุกคอก (MapBuilder สร้าง · client ติดข้อความ/จุดกด)
function Config.getPenSignKinds(): { PenSignKind }
	return { "speed", "pen" }
end

-- ป้ายอัปเกรดข้างประตูคอก (UI-2) · คืน (จุดบนพื้นใต้เสา, ทิศที่หน้าป้ายหันไป)
-- ⚠️ ซ้าย/ขวา = **ยืนบนทางเดินกลางหันหน้าเข้าประตู** (ตัดสินใน UI-2): ค่าวิ่ง = ซ้ายมือ · อัปคอก = ขวามือ
--   คอกแถวบนกับแถวล่างหันหน้าคนละทาง → ป้ายสองแถวจึงอยู่คนละฝั่ง X กัน (ทุกคนเห็นค่าวิ่งอยู่ซ้ายมือ)
--   ฝั่ง +X มีป้ายชื่อคอกอยู่แล้ว → ป้ายฝั่งนั้นปักถัดออกไปจากป้ายชื่อ (ไม่ย้ายป้ายชื่อ)
-- หน้าป้ายหันเข้าทางเดินกลางเสมอ
function Config.getPenUpgradeSignSpot(index: number, kind: PenSignKind): (Vector3, Vector3)
	local map = Config.MapDimensions
	local center = Config.getPenPlotCenter(index)
	local _, outward = Config.getPenGateLine(index)
	-- หันหน้าเข้าประตู = มองไปทาง −outward (แกน Z) → มือขวาชี้ไปทาง X = outward
	local side = if kind == "pen" then outward else -outward
	local half = map.MapSign.BoardSize.X / 2
	local nearEdge = map.Pen.GateWidth / 2 + map.Pen.SignGateClearance
	local offset = if side > 0
		then nearEdge + map.Pen.SignSize.X + map.MapSign.NameSignGap + half
		else -(nearEdge + half)
	local nameSign = Config.getPenNameSignSpot(index)
	return vec3(center.X + offset, 0, nameSign.Z), vec3(0, 0, outward)
end

-- ป้ายอัปดาเมจ — **จุดเดียวใช้ร่วมกัน ที่ปากทางเข้าเลนรบ ฝั่งลาน** (ตัดสินใน UI-2)
-- กำแพงกั้นด่านเป็นของแต่ละคน (วาดฝั่ง client · อยู่คนละด่านกัน) → จุดร่วมต้องอยู่ช่วงที่ทุกคนเดินผ่าน
-- ยืนบนหญ้าก่อนถึงต้นเลน ชิดแนวเลน (ไม่ใช่กึ่งกลางไปทางแถวคอก) · หน้าป้ายหันไปทางลาน (−X)
-- · คืน (จุดบนพื้นใต้เสา, ทิศที่หน้าป้ายหันไป)
-- ⚠️ UI-fix รอบ 1 (ผลทดสอบ Studio): เดิมอยู่กึ่งกลางพอดีระหว่างขอบเลนกับแถวคอก (X 134, Z 37.5)
-- ดูกลืนไปกับโซนคอกเกินไป — ขยับเข้าใกล้กำแพงทางเข้าเลนขึ้น (X 138) และขยับชิดแนวเลนแทนกึ่งกลาง (Z 35)
-- ยังอยู่ในช่วงที่ validate() บังคับเสมอ (ไม่ทับเลน · ไม่ล้ำแถวคอก · ไม่ล้ำเข้าเลน)
function Config.getDamageSignSpot(): (Vector3, Vector3)
	local map = Config.MapDimensions
	local z = map.Lane.Width / 2 + map.MapSign.DamageInsetZ
	return vec3(Config.getLaneStartX() - map.MapSign.DamageInsetX, 0, z), vec3(-1, 0, 0)
end

-- ร้านขายแม่ = กึ่งกลางแผงร้าน SellStallIndex (ใช้วางจุดกด E และวัดระยะปิดหน้าต่าง)
-- 5C: ร้านกระบอง = กึ่งกลางแผงร้าน WeaponStallIndex (ป้าย "ซื้ออาวุธ") — วางจุดกด E + วัดระยะปิดหน้าต่าง
function Config.getWeaponShopSpot(): Vector3
	return Config.getShopStallCenter(Config.MapDimensions.MapSign.WeaponStallIndex)
end

function Config.getSellShopSpot(): Vector3
	return Config.getShopStallCenter(Config.MapDimensions.MapSign.SellStallIndex)
end

-- ชื่อโมเดลป้ายใน Workspace.Map.MapSigns — MapBuilder ตั้ง · client หาด้วยชื่อเดียวกัน
Config.MAP_SIGN_FOLDER = "MapSigns"
-- แท่นอัญเชิญ (UI-3) — MapBuilder สร้างโมเดลชื่อนี้ใต้ Workspace.Map · client ติดจุดกด E ที่ชิ้นแกน (CORE)
Config.SUMMON_PEDESTAL_NAME = "SummonPedestal"
Config.SUMMON_PEDESTAL_CORE = "Core"
-- Attribute บนตัว Player = เลขคอกที่จองได้ (PenService ตั้งตอนจอง · ล้างตอนคืน) · client ใช้แยกป้ายคอกตัวเอง
Config.PEN_INDEX_ATTRIBUTE = "PenIndex"
function Config.getMapSignName(kind: "damage" | PenSignKind, penIndex: number?): string
	if kind == "damage" then
		return "DamageUpgradeSign"
	end
	local prefix = if kind == "speed" then "SpeedUpgradeSign" else "PenUpgradeSign"
	return `{prefix}{penIndex or 0}`
end

function Config.getPenCapacity(level: number): number
	local clamped = math.clamp(math.floor(level), 1, Config.Balance.Pen.MAX_LEVEL)
	return Config.Balance.Pen.BASE_CAPACITY + (clamped - 1) * Config.Balance.Pen.CAPACITY_PER_LEVEL
end

-- ราคาอัปเกรดจาก level → level+1 คืน nil ถ้าเต็มเลเวลแล้ว
function Config.getPenUpgradeCost(level: number): number?
	if level >= Config.Balance.Pen.MAX_LEVEL then
		return nil
	end
	return Config.Balance.Pen.UPGRADE_BASE_COST * Config.Balance.Pen.UPGRADE_COST_MULTIPLIER ^ (level - 1)
end

--------------------------------------------------------------------------------
-- อาวุธ = กระบอง 10 ขั้น (Phase 5C) — สูตรทั้งหมดอยู่ที่นี่ ตัวเลขตั้งต้นอยู่ใน Balance.Weapon
--------------------------------------------------------------------------------

-- ปัดเป็นเลขนัยสำคัญ `digits` ตัว · roundUp = ปัดขึ้น (ไม่งั้นปัดใกล้สุด) · ≤ 0 = 0
-- (เผื่อทศนิยมลอยนิดหน่อย: 3.0000000001 ปัดขึ้นไม่กลายเป็น 4)
function Config.roundSignificant(value: number, digits: number, roundUp: boolean?): number
	if value <= 0 then
		return 0
	end
	local scale = 10 ^ (math.floor(math.log10(value)) - digits + 1)
	local scaled = value / scale
	local rounded = if roundUp then math.ceil(scaled - 1e-9) else math.floor(scaled + 0.5)
	return rounded * scale
end

-- ขั้นกระบองจากค่าที่เซฟไว้ (weaponLevel) — **ค่าแปลก/นอกช่วง clamp ไม่ crash**
-- ไม่ใช่ตัวเลข/NaN = ขั้นเริ่มต้น · ทศนิยมปัดลง · ต่ำกว่า 1 = 1 · เกินเพดาน = เพดาน
function Config.clampClubTier(raw: any): number
	local weapon = Config.Balance.Weapon
	if type(raw) ~= "number" or raw ~= raw then
		return weapon.START_TIER
	end
	return math.clamp(math.floor(raw), 1, weapon.MAX_LEVEL)
end

-- ห้องบอสที่ขั้นนี้ออกแบบมาตี: ขั้น 1–9 = ห้องเดียวกัน · ขั้นพิเศษ = ห้องสุดท้าย
function Config.getClubTargetRoom(tier: number): number
	return math.min(Config.clampClubTier(tier), Config.Balance.Stage.COUNT)
end

-- ขั้นพิเศษ = ขั้นที่เกินจำนวนห้อง (ขั้น 10)
function Config.isCapstoneClubTier(tier: number): boolean
	return Config.clampClubTier(tier) > Config.Balance.Stage.COUNT
end

-- ดาเมจต่อครั้งของกระบองขั้นนี้ = HP บอสห้องเป้าหมาย × คูลดาวน์ ÷ เวลาเป้าหมาย → ปัดขึ้น (≥ 1)
-- ⚠️ เป็นจำนวนเต็มเสมอ (≥ 1) — ส่วนแบ่งเงินบอสนับคนที่ทำดาเมจ ≥ BOSS_REWARD_MIN_DAMAGE
function Config.getClubDamage(tier: number): number
	local weapon = Config.Balance.Weapon
	local clamped = Config.clampClubTier(tier)
	local target = if Config.isCapstoneClubTier(clamped)
		then weapon.CAPSTONE_SOLO_KILL_SECONDS
		else weapon.TARGET_SOLO_KILL_SECONDS
	local raw = Config.getBossHp(Config.getClubTargetRoom(clamped))
		* Config.Balance.BossCycle.PLAYER_ATTACK_COOLDOWN
		/ target
	return math.max(1, Config.roundSignificant(raw, weapon.DAMAGE_SIGNIFICANT_DIGITS, true))
end

-- ราคาขั้นนี้ (เงินในเกม) · ขั้นเริ่มต้น = 0 (ได้ฟรี) · ขั้นอื่น = รายได้ X นาทีของผู้เล่นอ้างอิงด่านเป้าหมาย
function Config.getClubPrice(tier: number): number
	local weapon = Config.Balance.Weapon
	local clamped = Config.clampClubTier(tier)
	if clamped <= weapon.START_TIER then
		return 0
	end
	local minutes = if Config.isCapstoneClubTier(clamped)
		then weapon.CAPSTONE_PRICE_INCOME_MINUTES
		else weapon.PRICE_INCOME_MINUTES
	local raw = Config.getReferenceIncomePerHour(Config.getClubTargetRoom(clamped)) * minutes / 60
	return Config.roundSignificant(raw, weapon.PRICE_SIGNIFICANT_DIGITS)
end

-- วินาทีที่คนเดียวตีบอสห้องนั้นตายด้วยกระบองขั้นนี้ (จำนวนครั้ง × คูลดาวน์ · นับครั้งแรกเป็นเต็มคูลดาวน์ = ประเมินเผื่อ)
function Config.getClubSoloKillSeconds(tier: number, room: number): number
	local hits = math.ceil(Config.getBossHp(room) / Config.getClubDamage(tier))
	return hits * Config.Balance.BossCycle.PLAYER_ATTACK_COOLDOWN
end

function Config.getClubVisual(tier: number): ClubVisual
	return Config.ClubVisuals[Config.clampClubTier(tier)]
end

function Config.formatClubBoughtMessage(tier: number): string
	return `ได้กระบองขั้น {tier}`
end

-- ซื้อกระบองขั้นถัดไปได้ไหม (pure · server เรียกผ่าน PlayerData.buyNextClubTier · เทสต์นอก Studio ได้)
-- ⚠️ **ไม่มีพารามิเตอร์ขั้น** — ขั้นที่ซื้อ = ขั้นปัจจุบัน (clamp แล้ว) + 1 เสมอ → ข้ามขั้นไม่ได้โดยโครงสร้าง
-- คืน (ซื้อได้ไหม, เหตุผลถ้าไม่ได้, ขั้นถัดไป, ราคา)
function Config.planClubPurchase(rawTier: any, coins: any): (boolean, string?, number?, number?)
	local current = Config.clampClubTier(rawTier)
	if current >= Config.Balance.Weapon.MAX_LEVEL then
		return false, "มีกระบองขั้นสูงสุดแล้ว", nil, nil
	end
	local nextTier = current + 1
	local price = Config.getClubPrice(nextTier)
	if type(coins) ~= "number" or coins ~= coins or coins < price then
		return false, "เงินไม่พอ", nextTier, price
	end
	return true, nil, nextTier, price
end

-- ⚠️ ชื่อเดิม (5A) — BossService ใช้ดาเมจจากตัวนี้ · ตอนนี้ = ดาเมจกระบอง
function Config.getWeaponDamage(level: number): number
	return Config.getClubDamage(level)
end

-- ราคาอัปจากขั้น level → level + 1 (ชื่อเดิม) · เต็มเพดานแล้ว = nil
function Config.getWeaponUpgradeCost(level: number): number?
	local current = Config.clampClubTier(level)
	if current >= Config.Balance.Weapon.MAX_LEVEL then
		return nil
	end
	return Config.getClubPrice(current + 1)
end

--------------------------------------------------------------------------------
-- อัตราผลิตลูก
--------------------------------------------------------------------------------
-- level 0 = ยังไม่อัป (×1) ถึง UPGRADE_MAX_LEVEL

function Config.getProductionMultiplier(level: number): number
	local clamped = math.clamp(math.floor(level), 0, Config.Balance.Production.UPGRADE_MAX_LEVEL)
	return Config.Balance.Production.UPGRADE_RATE_MULTIPLIER ^ clamped
end

function Config.getProductionUpgradeCost(level: number): number?
	if level >= Config.Balance.Production.UPGRADE_MAX_LEVEL then
		return nil
	end
	return Config.Balance.Production.UPGRADE_BASE_COST * Config.Balance.Production.UPGRADE_COST_MULTIPLIER ^ level
end

--------------------------------------------------------------------------------
-- ด่าน กำแพง บอส
--------------------------------------------------------------------------------

function Config.getStage(stage: number): StageDef
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	return Stages[clamped]
end

function Config.getStageDefenderCount(stage: number): number
	return Config.getStage(stage).defenders
end

-- damage/วินาที ที่อาวุธป้องกันของกำแพงยิงใส่กองทัพเรา
function Config.getStageTurretDps(stage: number): number
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	local toll = Config.Balance.Combat.TURRET_TOLL[clamped]
	if toll <= 0 then
		return 0
	end
	return toll * Config.getReferenceDps(clamped)
end

function Config.getStageDefenderHp(stage: number): number
	return Config.getStageDefenderCount(stage) * Config.Balance.Stage.DEFENDER_HP
end

function Config.getStageWallHp(stage: number): number
	return Config.getStageDefenderHp(stage) * Config.Balance.Stage.WALL_HP_RATIO
end

-- damage ที่กองทัพต้องทำรวมทั้งหมดเพื่อผ่านด่านนี้ (ทหาร + กำแพง)
function Config.getStageTotalHp(stage: number): number
	return Config.getStageDefenderHp(stage) + Config.getStageWallHp(stage)
end

-- HP บอสด่านนั้นตามสเกลต่อด่าน (ผูกกับอาวุธ ×10) — 5B-2: บอสห้อง N ใช้ค่านี้จริง (ค่าชั่วคราว จูน Phase 6)
function Config.getBossHp(stage: number): number
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	local cycle = Config.Balance.BossCycle
	return cycle.BOSS_HP_BASE * cycle.BOSS_HP_MULTIPLIER ^ (clamped - 1)
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

	local min = Config.Balance.Stage.DISPLAY_MODELS_MIN
	local max = Config.Balance.Stage.DISPLAY_MODELS_MAX
	return math.max(min, math.ceil(max * ratio))
end

--------------------------------------------------------------------------------
-- เงิน
--------------------------------------------------------------------------------
-- stage = ด่านสูงสุดที่ผู้เล่นพังกำแพงได้แล้ว (เริ่มที่ 1)
-- แม่ในกระเป๋าไม่ผลิตเงิน ผู้เรียกต้องกรองเอาเฉพาะแม่ในคอกก่อนเรียกฟังก์ชันนี้

function Config.getCoinsPerMinute(motherWeight: number, stage: number, statuses: { string }?): number
	local economy = Config.Balance.Economy
	local clampedStage = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)

	local byWeight = economy.BASE_PER_MINUTE * (motherWeight / economy.REFERENCE_WEIGHT) ^ economy.EXPONENT
	local byStage = economy.STAGE_MULTIPLIER ^ (clampedStage - 1)
	local byStatus = if statuses then Config.getStatusEffects(statuses).coinMultiplier else 1

	return byWeight * byStage * byStatus
end

-- ราคาขายแม่ = รายได้ของแม่ตัวนั้น × SELL_MOTHER_MINUTES
function Config.getMotherSellPrice(motherWeight: number, stage: number, statuses: { string }?): number
	return math.floor(
		Config.getCoinsPerMinute(motherWeight, stage, statuses) * Config.Balance.Economy.SELL_MOTHER_MINUTES
	)
end

--------------------------------------------------------------------------------
-- แสดงน้ำหนักเป็นข้อความ
--------------------------------------------------------------------------------
-- 1200 → "1.2K", 3400000 → "3.4M", 1100000000 → "1.1B"
-- ต่ำกว่าพันแสดงทศนิยมได้ถึง 2 ตำแหน่งแล้วตัดศูนย์ท้ายทิ้ง
-- (ลูกของแม่ตัวเล็กหนักไม่ถึง 10 kg เช่นแม่ 999 → ลูก 9.99)
-- ไม่ใส่หน่วย "kg" ให้ ผู้เรียกเติมเองตามบริบท

-- เงินที่ได้จากการฆ่าทหารฝ่ายรับ 1 ตัวในด่านนั้น
function Config.getDefenderKillReward(stage: number): number
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	return Config.Balance.Economy.KILL_DEFENDER_BASE * Config.Balance.Economy.KILL_DEFENDER_MULTIPLIER ^ (clamped - 1)
end

-- เงินรวมที่ได้จากการกวาดทหารฝ่ายรับทั้งด่านจนหมด (ได้ครั้งเดียวต่อผู้เล่น)
function Config.getStageDefenderRewardTotal(stage: number): number
	return Config.getStageDefenderCount(stage) * Config.getDefenderKillReward(stage)
end

-- เงินที่ได้จากการฆ่าบอสของด่านนั้น 1 ครั้ง (ก่อนแบ่งให้ผู้เล่นที่ร่วมตี)
function Config.getBossKillReward(stage: number): number
	local clamped = math.clamp(math.floor(stage), 1, Config.Balance.Stage.COUNT)
	return Config.Balance.Economy.KILL_BOSS_BASE * Config.Balance.Economy.KILL_BOSS_MULTIPLIER ^ (clamped - 1)
end

-- ส่วนแบ่งของผู้เล่น 1 คน เมื่อมี participantCount คนร่วมตีบอสตัวนั้น
-- ⚠️ แบ่งเท่ากันทุกคน ไม่ดูสัดส่วน damage (ดูเหตุผลใน Config.Balance.Economy)
-- server เป็นคนนับว่าใครร่วมตีบ้าง (ทำ damage ≥ BOSS_REWARD_MIN_DAMAGE) ห้าม client แจ้ง
function Config.getBossKillShare(stage: number, participantCount: number): number
	local participants = math.max(1, math.floor(participantCount))
	return Config.getBossKillReward(stage) / participants
end

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

--------------------------------------------------------------------------------
-- ยามเฝ้าสมดุล: เกมยังเล่นจบได้ไหม
--------------------------------------------------------------------------------
-- ⚠️ ยามตัวนี้กันปัญหาที่เคยเกิดมาแล้วสองรอบ และมองไม่เห็นด้วยตาเปล่า:
--
--   รอบแรก  ราคาของโต ×10 ต่อขั้น แต่รายได้โตแค่ ×1,000 ตลอดเกม
--           → ผู้เล่นซื้อของขั้นกลางขึ้นไปไม่ได้เลย (แก้ด้วยตัวคูณเงินตามด่าน)
--   รอบสอง  เกือบใส่ตัวคูณ damage ×8 ต่อด่าน ทั้งที่กองทัพโตอยู่แล้ว ×7 ต่อด่าน
--           → ด่าน 4 เป็นต้นไปจะจบทันที เกมง่ายลงเรื่อย ๆ แทนที่จะไต่ระดับ
--
-- ทั้งสองรอบเกิดจากเรื่องเดียวกัน: "อัตราการโต" ของสองฝั่งไม่แมตช์กัน
-- ซึ่งดูจากตัวเลขตรง ๆ ไม่ออก ต้องคำนวณเป็นเวลาถึงจะเห็น
--
-- ยามตัวนี้จึงคำนวณ "ผู้เล่นชั้นกลางใช้เวลากี่ชั่วโมงกว่าจะพังกำแพงด่าน N"
-- แล้วบังคับให้อยู่ในช่วงที่ยอมรับได้ **ทั้งสองด้าน**
-- ช้าไป = ผู้เล่นเลิกเล่น · เร็วไป = ด่านนั้นไม่มีความหมาย
-- ชั่วโมงที่ผู้เล่นชั้นกลางใช้ตีกำแพงด่านนั้นจนพัง (0 = ด่านที่ไม่มีกำแพง)
-- แยกออกมาเป็นฟังก์ชันของโมดูลเพราะยามสองตัวและเทสต์ต้องใช้ค่าเดียวกัน
local function referenceCharForClass(class: string): string
	for id, character in Characters do
		if character.class == class and character.enabled then
			return id
		end
	end
	error(`Config: BalanceCheck อ้างคลาส "{class}" ที่ไม่มีตัวละครที่เปิดใช้อยู่เลย`)
end

-- damage/วินาทีของผู้เล่นชั้นกลางที่ด่านนั้น
-- ⚠️ ระบบปล่อยต่อเนื่อง: อัตราจริง = min(ผลิตได้, ปล่อยได้)
-- พอชนเพดานปล่อยแล้ว upgrade อัตราผลิตหยุดเพิ่ม damage ทันที
function Config.getReferenceDps(stage: number): number
	local check = Config.Balance.BalanceCheck
	local weight = check.REFERENCE_WEIGHT[stage]
	local charId = referenceCharForClass(check.REFERENCE_CLASS[stage])

	-- ผู้เล่นชั้นกลางที่ด่าน N: คอกเลเวล N · upgrade อัตราผลิตขั้น N-1
	local producedPerSecond = Config.getPenCapacity(stage)
		* Config.getProductionPerMinute(weight, nil, stage - 1, true)
		/ 60
	local effectiveRate = math.min(producedPerSecond, Config.getReleaseRate(stage))

	-- ⚠️ สมมติว่าผู้เล่นซื้อ upgrade ครบเพดานของด่านนั้นแล้ว
	-- สมมติแบบนี้ได้อย่างซื่อสัตย์ เพราะเงินเป็น "รายได้ที่คาดเดาได้" ต่างจากคลาสที่เป็นการสุ่ม
	-- และยามราคาข้างล่างบังคับอยู่แล้วว่าราคาต้องอยู่ในวิสัยที่จ่ายไหว
	local damageLevel = Config.getMaxDamageLevel(stage)

	return effectiveRate * Config.computeBattlePower(Config.getChildWeight(weight), charId, nil, damageLevel)
end

-- รายได้รวมที่ผู้เล่นอ้างอิงได้ "ตลอดการตีด่านนั้น"
-- = (เงินจากคอก + เงินจากบอส) × เวลาตี + เงินจากการกวาดทหารทั้งด่าน
-- ด่านที่ไม่มีกำแพง (ด่าน 1) ใช้รายได้ 1 ชั่วโมงแรกเป็นฐานแทน เพราะไม่มี "เวลาตี"
-- รายได้ต่อชั่วโมงของผู้เล่นอ้างอิงที่ด่านนั้น = เงินจากคอก + ส่วนแบ่งเงินบอส (ไม่รวมเงินกวาดทหาร ซึ่งเป็นก้อนเดียวต่อด่าน)
-- ⚠️ 5C: แยกออกมาจาก getReferenceStageIncome (ตัวเลขเดิมเป๊ะ) — ราคากระบอง (getClubPrice) อ่านตัวนี้
function Config.getReferenceIncomePerHour(stage: number): number
	local check = Config.Balance.BalanceCheck
	local weight = check.REFERENCE_WEIGHT[stage]

	local penPerHour = Config.getPenCapacity(stage) * Config.getCoinsPerMinute(weight, stage) * 60
	-- ⚠️ 5B: อัตราบอสของ "โมเดลสมดุล" (BossCycle.MODEL_BOSS_SPAWN_SECONDS = ตัวเลขเดิมของ Balance.Boss ที่ลบแล้ว)
	-- ไม่ใช่วงจรจริง — ดูเหตุผลที่ตัวค่า (อ่านวงจรจริงแล้วส่วนเกินเงินตกต่ำกว่าเกณฑ์ = เปลี่ยนสมดุลโดยไม่ได้สั่ง)
	local bossPerHour = (3600 / Config.Balance.BossCycle.MODEL_BOSS_SPAWN_SECONDS)
		* Config.getBossKillReward(stage)
		/ check.PLAYERS_PER_SERVER

	return penPerHour + bossPerHour
end

function Config.getReferenceStageIncome(stage: number): number
	local hours = Config.getReferenceClearHours(stage)
	if hours <= 0 then
		hours = 1
	end
	return Config.getReferenceIncomePerHour(stage) * hours + Config.getStageDefenderRewardTotal(stage)
end

-- ชั่วโมงที่ใช้ตีกำแพงด่านนั้นจนพัง (0 = ด่านที่ไม่มีกำแพง)
function Config.getReferenceClearHours(stage: number): number
	local totalHp = Config.getStageTotalHp(stage)
	if totalHp <= 0 then
		return 0
	end
	return totalHp / (Config.getReferenceDps(stage) * 3600)
end

-- ไข่ที่ผู้เล่น 1 คนได้ต่อชั่วโมง ตาม "โมเดลสมดุล" (บอสเกิดเรื่อย ๆ หารกันทั้งเซิร์ฟ) — ยามเวลาฟาร์มใช้
-- ⚠️ 5B: อ่าน BossCycle.MODEL_* (ตัวเลขเดิมของ Balance.Boss ที่ลบแล้ว = 10 ฟอง/คน/ชม.) ไม่ใช่วงจรจริง
--   (วงจรจริง 10 นาที · 6 ฟอง = 6 ฟอง/คน/ชม.) — เปลี่ยนเมื่อไหร่ = จูนสมดุล ผู้ใช้ตัดสิน (ดูเหตุผลที่ตัวค่า)
function Config.getEggsPerHour(): number
	local cycle = Config.Balance.BossCycle
	local spawnsPerHour = 3600 / cycle.MODEL_BOSS_SPAWN_SECONDS
	return spawnsPerHour * cycle.MODEL_EGGS_PER_SPAWN / Config.Balance.BalanceCheck.PLAYERS_PER_SERVER
end

-- ชั่วโมงที่ใช้ฟาร์มไข่จนเติมคอกเต็มด้วยแม่คลาสอ้างอิงของด่านนั้น (หรือดีกว่า)
-- ⚠️ น้ำหนักอ้างอิงอยู่ใน tier 1 ซึ่ง 90% ของไข่ให้อยู่แล้ว จึงคิดเฉพาะโอกาสของคลาส
function Config.getReferenceFarmHours(stage: number): number
	local check = Config.Balance.BalanceCheck
	local wanted = check.REFERENCE_CLASS[stage]
	local wantedOrder = CharacterClasses[wanted].order

	-- โอกาสที่ไข่ของด่านนั้นให้คลาสที่ "ดีเท่าหรือดีกว่า" ที่ต้องการ
	-- (order น้อย = คลาสสูงกว่า)
	local pool = EggCharacterPools[Config.getBossEggId(stage)]
	local chance = 0
	for _, entry in pool do
		if CharacterClasses[entry.class].order <= wantedOrder then
			chance += entry.weight
		end
	end
	chance /= Config.CLASS_ROLL_MAX

	if chance <= 0 then
		return math.huge
	end

	local eggsNeeded = Config.getPenCapacity(stage) / chance
	return eggsNeeded / Config.getEggsPerHour()
end

local function assertProgressionIsSane()
	local check = Config.Balance.BalanceCheck

	local firstGuarded: number? = nil
	local lastGuarded: number? = nil

	for stage = 1, Config.Balance.Stage.COUNT do
		assert(
			check.REFERENCE_WEIGHT[stage] ~= nil and check.REFERENCE_CLASS[stage] ~= nil,
			`Config: BalanceCheck ขาดค่าอ้างอิงของด่าน {stage}`
		)

		if Config.getStageTotalHp(stage) > 0 then
			local hours = Config.getReferenceClearHours(stage)

			assert(
				hours <= check.MAX_HOURS_PER_STAGE,
				`Config: ด่าน {stage} ต้องตีนาน {math.floor(hours)} ชั่วโมง (เพดาน {check.MAX_HOURS_PER_STAGE}) `
					.. `— ยากเกินจนผู้เล่นเลิกเล่น ลอง HP ด่านลง หรือดันอัตราปล่อย/damage ขึ้น`
			)
			assert(
				hours >= check.MIN_HOURS_PER_STAGE,
				`Config: ด่าน {stage} ใช้เวลาแค่ {string.format("%.3f", hours)} ชั่วโมง (ขั้นต่ำ {check.MIN_HOURS_PER_STAGE}) `
					.. `— เร็วเกินจนด่านไม่มีความหมาย มักเกิดจากตัวคูณฝั่ง damage โตเร็วกว่า HP ของด่าน`
			)

			-- ⚠️ ยามข้อที่สำคัญที่สุดของรอบนี้
			-- เวลาตีอย่างเดียวไม่พอ ต้องดูด้วยว่า "กว่าจะหาของมาตีได้" ใช้เวลาเท่าไหร่
			-- เคยพลาดมาแล้ว: ยามผ่านทุกด่าน ทั้งที่ของที่ยามสมมติว่าผู้เล่นมี
			-- ต้องฟาร์มหลักหมื่นชั่วโมงถึงจะได้ (แม่ tier 6 = 1 ใน 111,111)
			local farmHours = Config.getReferenceFarmHours(stage)
			assert(
				farmHours <= hours * check.MAX_FARM_TO_CLEAR_RATIO,
				`Config: ด่าน {stage} ใช้เวลาฟาร์มไข่ {string.format("%.1f", farmHours)} ชม. `
					.. `แต่ตีกำแพงแค่ {string.format("%.1f", hours)} ชม. `
					.. `(เกิน {check.MAX_FARM_TO_CLEAR_RATIO} เท่า) — เกมกลายเป็นนั่งรอไข่ ไม่ใช่ตีกำแพง `
					.. `ตรวจ BalanceCheck.REFERENCE_CLASS กับตารางคลาสของไข่ด่านนั้น`
			)

			if firstGuarded == nil then
				firstGuarded = hours
			end
			lastGuarded = hours
		end
	end

	-- เกมควร "ยากขึ้น" เรื่อย ๆ ไม่ใช่ง่ายลง
	assert(firstGuarded ~= nil and lastGuarded ~= nil, "Config: ไม่มีด่านไหนที่มีกำแพงให้ตีเลย")
	assert(
		(lastGuarded :: number) >= (firstGuarded :: number),
		`Config: ด่านที่มีกำแพงด่านสุดท้ายใช้เวลา {string.format("%.2f", lastGuarded :: number)} ชม. `
			.. `น้อยกว่าด่านแรก {string.format("%.2f", firstGuarded :: number)} ชม. `
			.. `— เกมง่ายลงเรื่อย ๆ แทนที่จะไต่ระดับ ตรวจ Config.Balance.DamageUpgrade กับตารางอัตราปล่อย`
	)
end

-- ⚠️ ยามตัวที่สอง: turret ต้องไม่แรงจนกองทัพไปไม่ถึงกำแพง
--
-- เรื่องนี้เคยพลาดมาแล้วและมองไม่เห็นด้วยตาเปล่า: turretDps ชุดแรกตั้งจาก
-- "10% ของ damage ทหารฝ่ายรับทั้งด่าน" ซึ่งดูสมเหตุสมผลมากบนกระดาษ
-- แต่มันเป็นตัวเลขระดับ "ทั้งกองทัพ" ที่ไปยิงใส่ทหารที่ปล่อยได้ทีละ 1-10 ตัว/วินาที
-- ผลจริงคือ turret แรงกว่า damage/วิ ของผู้เล่น 17-238 เท่า = ผ่านไม่ได้สักด่าน
--
-- สูตรที่ใช้ตรวจ (ระยะเวลารบตัดกันออก เพราะ HP ของตัวเรา = damage ของตัวเรา):
--     สัดส่วนกำลังพลที่เสีย = turretDps ÷ (damage/วินาทีของเรา)
local function assertTurretIsSurvivable()
	local check = Config.Balance.BalanceCheck
	local tolls = Config.Balance.Combat.TURRET_TOLL

	assert(
		#tolls == Config.Balance.Stage.COUNT,
		`Config: TURRET_TOLL มี {#tolls} ด่าน แต่เกมมี {Config.Balance.Stage.COUNT} ด่าน`
	)
	assert(tolls[1] == 0, "Config: ด่าน 1 ไม่มีกำแพง TURRET_TOLL[1] ต้องเป็น 0")

	local previous = 0
	for stage = 1, Config.Balance.Stage.COUNT do
		local toll = tolls[stage]
		assert(toll >= 0, `Config: TURRET_TOLL ด่าน {stage} ติดลบ`)
		assert(
			toll <= check.TURRET_TOLL_CEILING,
			`Config: turret ด่าน {stage} กินกำลังพล {string.format("%.1f", toll * 100)}% `
				.. `(เพดาน {check.TURRET_TOLL_CEILING * 100}%) — ทหารจะตายก่อนถึงกำแพง`
		)
		assert(
			toll >= previous,
			`Config: TURRET_TOLL ด่าน {stage} ({toll}) ต่ำกว่าด่านก่อนหน้า ({previous}) `
				.. `— กำแพงด่านสูงควรเขี้ยวขึ้น ไม่ใช่อ่อนลง`
		)
		previous = toll

		-- ค่า damage ที่คำนวณออกมาต้องตรงกับสัดส่วนที่ตั้งใจเป๊ะ
		-- (ดักกรณีมีคนเผลอไปเขียนทับ getStageTurretDps ให้คืนตัวเลขดิบอีก)
		if toll > 0 then
			local ourDps = Config.getReferenceDps(stage)
			assert(ourDps > 0, `Config: ด่าน {stage} คำนวณ damage/วินาที ได้ 0`)
			assert(
				math.abs(Config.getStageTurretDps(stage) / ourDps - toll) < 1e-9,
				`Config: turretDps ด่าน {stage} ไม่ตรงกับ TURRET_TOLL ที่ตั้งไว้ `
					.. `— getStageTurretDps ต้องคำนวณจาก TOLL × getReferenceDps เท่านั้น`
			)
		else
			assert(
				Config.getStageTurretDps(stage) == 0,
				`Config: ด่าน {stage} TOLL เป็น 0 แต่ turretDps ไม่ใช่ 0`
			)
		end
	end
end

-- เช็คความถูกต้องของตารางตอนเซิร์ฟเวอร์บูต
-- ถ้าพิมพ์ unitId ผิดในตารางสุ่ม จะได้รู้ทันทีตอนเปิดเกม ไม่ใช่ตอนผู้เล่นฟักไข่
function Config.validate()
	-- ══ ลูกบิดสมดุลต้องอยู่ใน Config.Balance ที่เดียว ══
	-- ⚠️ เช็คสองทาง ทางเดียวไม่พอ:
	--   1. มีอยู่ใน Balance จริง — กันคนลบกลุ่มทิ้งแล้วโค้ดที่อ่านมันพังตอน runtime
	--   2. **ไม่มีชื่อเดียวกันที่ Config ชั้นบนสุด** — กันคนเผลอเติม `Config.Pen = {...}` กลับเข้าไป
	--      แล้วเกิดของสองชุดที่ค่าไม่ตรงกัน ซึ่งเป็นความผิดที่มองด้วยตาเปล่าไม่เห็นเลย
	--      (เคยเจอมาแล้วกับ `Config.Map` ที่เป็น alias ของ `Config.MapDimensions`)
	for _, groupName in BALANCE_GROUPS do
		assert(
			(Config.Balance :: any)[groupName] ~= nil,
			`Config: ไม่มี Config.Balance.{groupName} — ลูกบิดสมดุลกลุ่มนี้หายไป`
		)
		assert(
			rawget(Config :: any, groupName) == nil,
			`Config: "{groupName}" โผล่ที่ Config ชั้นบนสุด ทั้งที่ต้องอยู่ใน Config.Balance เท่านั้น — `
				.. `มีสองที่แล้วค่าจะไม่ตรงกันโดยไม่มีใครรู้`
		)
	end
	for _, groupName in REMOVED_BALANCE_GROUPS do
		assert(
			(Config.Balance :: any)[groupName] == nil and rawget(Config :: any, groupName) == nil,
			`Config: "{groupName}" ถูกลบไปแล้ว (ค่าที่ยังใช้ย้ายไป Balance.BossCycle) — ห้ามเติมกลับ มีสองชุดแล้วอ่านผิดชุด`
		)
	end

	for eggId, egg in EggTypes do
		assert(egg.id == eggId, `Config: EggTypes["{eggId}"].id ไม่ตรงกับคีย์ ({egg.id})`)
		assert(egg.hatchTime > 0, `Config: ไข่ "{eggId}" มี hatchTime <= 0`)

		-- ⚠️ เวลาฟักของไข่รายด่านต้องมาจาก SECONDS_PER_STAGE เท่านั้น
		-- ใครใส่ตัวเลขดิบกลับเข้าไป ปรับจังหวะเกมรอบหน้าจะลืมแก้ใบนี้
		if egg.enabled and egg.stage ~= nil then
			local expected = Balance.Hatchery.SECONDS_PER_STAGE * egg.stage
			assert(
				egg.hatchTime == expected,
				`Config: ไข่ "{eggId}" มี hatchTime {egg.hatchTime} แต่สูตรให้ {expected} `
					.. `(SECONDS_PER_STAGE × ด่าน {egg.stage})`
			)
		end
	end

	-- ⚠️ ตัวคูณขนาดโมเดลต้องมีครบ 1 ค่าต่อ 1 tier น้ำหนัก และต้องไต่ขึ้นเรื่อย ๆ
	-- (ตัวเล็กแสดงเล็กกว่าตัวใหญ่เสมอ ไม่งั้นขนาดไข่จะบอกน้ำหนักผิด ๆ ขัดกับกลไก "แย่งไข่ที่ใหญ่กว่า")
	do
		local multipliers = Balance.VisualScale.WEIGHT_MULTIPLIER
		assert(
			#multipliers == #WeightTiers,
			`Config: VisualScale.WEIGHT_MULTIPLIER มี {#multipliers} ค่า แต่มี {#WeightTiers} tier น้ำหนัก`
		)
		for index, multiplier in multipliers do
			assert(multiplier > 0, `Config: VisualScale.WEIGHT_MULTIPLIER[{index}] ต้องมากกว่า 0`)
			if index > 1 then
				assert(
					multiplier > multipliers[index - 1],
					`Config: VisualScale.WEIGHT_MULTIPLIER ต้องไต่ขึ้นเรื่อย ๆ ตาม tier `
						.. `(tier {index} = {multiplier} ไม่มากกว่า tier {index - 1} = {multipliers[index - 1]})`
				)
			end
		end
		assert(
			Balance.VisualScale.MOTHER_PEN_SHRINK > 0 and Balance.VisualScale.MOTHER_PEN_SHRINK <= 1,
			`Config: VisualScale.MOTHER_PEN_SHRINK ต้องอยู่ในช่วง (0, 1]`
		)
		assert(
			Balance.VisualScale.MOTHER_MESH_BASE_HEIGHT > 0,
			`Config: VisualScale.MOTHER_MESH_BASE_HEIGHT ต้องมากกว่า 0`
		)
		assert(
			Balance.VisualScale.MOTHER_MESH_WALK_SPEED > 0,
			`Config: VisualScale.MOTHER_MESH_WALK_SPEED ต้องมากกว่า 0`
		)
	end

	-- ⚠️ เวลาฟักตามน้ำหนัก+คลาส (Config.getHatchSeconds) — ตารางต้องครบและเวลาสูงสุด
	-- ต้องไม่เกินเพดานที่ตั้งไว้ กันตั้งเลขพลาดจนไข่บางฟองฟักนานเกินสมเหตุสมผล
	do
		local hatchery = Balance.Hatchery
		local hatchTimeByTier = hatchery.HatchTimeByTier
		assert(
			#hatchTimeByTier == #WeightTiers,
			`Config: Hatchery.HatchTimeByTier มี {#hatchTimeByTier} ค่า แต่มี {#WeightTiers} tier น้ำหนัก`
		)
		for index, seconds in hatchTimeByTier do
			assert(seconds > 0, `Config: Hatchery.HatchTimeByTier[{index}] ต้องมากกว่า 0`)
			if index > 1 then
				assert(
					seconds > hatchTimeByTier[index - 1],
					`Config: Hatchery.HatchTimeByTier ต้องไต่ขึ้นเรื่อย ๆ ตาม tier `
						.. `(tier {index} = {seconds} ไม่มากกว่า tier {index - 1} = {hatchTimeByTier[index - 1]})`
				)
			end
		end

		local maxClassMultiplier = 0
		for classId in CharacterClasses do
			local multiplier = hatchery.ClassHatchMultiplier[classId]
			assert(multiplier ~= nil, `Config: Hatchery.ClassHatchMultiplier ไม่มีคลาส "{classId}"`)
			assert(multiplier > 0, `Config: Hatchery.ClassHatchMultiplier["{classId}"] ต้องมากกว่า 0`)
			maxClassMultiplier = math.max(maxClassMultiplier, multiplier)
		end

		local worstCaseSeconds = hatchTimeByTier[#hatchTimeByTier] * maxClassMultiplier
		assert(
			worstCaseSeconds <= hatchery.MAX_HATCH_SECONDS,
			`Config: เวลาฟักสูงสุดที่เป็นไปได้ {worstCaseSeconds} วิ (tier สูงสุด × ตัวคูณคลาสสูงสุด) `
				.. `เกินเพดาน MAX_HATCH_SECONDS ({hatchery.MAX_HATCH_SECONDS} วิ)`
		)
	end

	for unitId, unit in UnitTypes do
		assert(unit.id == unitId, `Config: UnitTypes["{unitId}"].id ไม่ตรงกับคีย์ ({unit.id})`)
		assert(unit.hp > 0, `Config: ทหาร "{unitId}" มี hp <= 0`)
	end

	assert(EggTypes[Config.DEFAULT_EGG_ID] ~= nil, "Config: DEFAULT_EGG_ID ชี้ไปที่ไข่ที่ไม่มีอยู่")
	assert(Config.World.MAX_PENS > 0, "Config: MAX_PENS ต้องมากกว่า 0")
	-- ⚠️ เคยตั้งไม่ตรงกัน (คอก 6 ช่อง แต่โมเดลสมดุลคิดที่ 7 คน)
	-- ทำให้อัตราได้ไข่ที่ยามใช้คำนวณไม่ตรงกับเกมจริง
	assert(
		Config.World.MAX_PENS == Config.Balance.BalanceCheck.PLAYERS_PER_SERVER,
		`Config: จำนวนคอก ({Config.World.MAX_PENS}) ไม่ตรงกับ PLAYERS_PER_SERVER `
			.. `({Config.Balance.BalanceCheck.PLAYERS_PER_SERVER}) — อัตราได้ไข่ที่ยามคำนวณจะเพี้ยน`
	)

	----------------------------------------------------------------------------
	-- รูปทรงของแมพ
	----------------------------------------------------------------------------
	local dim = Config.MapDimensions

	-- ⚠️ ผังคอกต้องรองรับผู้เล่นได้พอดี ไม่ขาดไม่เกิน
	-- เกิน = มีคอกร้างที่ไม่มีวันมีเจ้าของ · ขาด = ผู้เล่นเข้ามาแล้วไม่มีที่ยืน
	assert(
		dim.Pen.Rows * dim.Pen.PerRow == Config.World.MAX_PENS,
		`Config: ผังคอก {dim.Pen.Rows}×{dim.Pen.PerRow} = {dim.Pen.Rows * dim.Pen.PerRow} แปลง `
			.. `ไม่ตรงกับ MAX_PENS ({Config.World.MAX_PENS})`
	)
	assert(dim.Pen.Rows >= 1 and dim.Pen.Rows % 1 == 0, "Config: Pen.Rows ต้องเป็นจำนวนเต็มบวก")
	assert(dim.Pen.PerRow >= 1 and dim.Pen.PerRow % 1 == 0, "Config: Pen.PerRow ต้องเป็นจำนวนเต็มบวก")


	-- ⚠️ ขอบกันชนต้องเล็กกว่าครึ่งหนึ่งของด้านที่สั้นที่สุด
	-- ไม่งั้นพื้นที่ที่แม่เดินได้จะติดลบ → สุ่มจุดหมายไม่ได้เลย แม่จะยืนนิ่งทั้งคอก
	local shortSide = math.min(dim.Pen.Size.X, dim.Pen.Size.Y)
	assert(
		dim.Pen.EdgeMargin >= 0 and dim.Pen.EdgeMargin < shortSide / 2,
		`Config: PEN_EDGE_MARGIN ({dim.Pen.EdgeMargin}) ต้องน้อยกว่าครึ่งของด้านสั้นสุดของคอก ({shortSide / 2})`
	)

	assert(dim.Lane.StartGap >= 0, "Config: Lane.StartGap ติดลบไม่ได้")
	assert(dim.Shop.StallCount >= 1 and dim.Shop.StallCount % 1 == 0, "Config: Shop.StallCount ต้องเป็นจำนวนเต็มบวก")

	----------------------------------------------------------------------------
	-- ทุกค่าใน MapDimensions ต้องเป็นบวก
	----------------------------------------------------------------------------
	-- ⚠️ วนทั้งตารางแทนที่จะไล่ทีละค่า **ตั้งใจ** — เพิ่มค่าใหม่แล้วถูกตรวจทันที
	-- โดยไม่ต้องจำว่าต้องมาเพิ่มในรายการตรงนี้ด้วย
	-- ค่าที่ยอมให้เป็น 0 ได้ (เช่น Lane.StartGap) assert แยกไว้ข้างบนแล้ว
	local ZERO_ALLOWED = { ["Lane.StartGap"] = true }
	-- ค่าที่ไม่ใช่ตัวเลข/เวกเตอร์ — ตรวจแยกของตัวเองในบล็อกลานบอส (5B: ตารางฝั่งมุมบอส "left"/"right" ต่อด่าน)
	local NOT_A_MEASURE = { ["BossRoom.CornerSide"] = true }
	for groupName, group in dim do
		for key, value in group :: any do
			local path = `{groupName}.{key}`
			if ZERO_ALLOWED[path] or NOT_A_MEASURE[path] then
				continue
			end
			if type(value) == "number" then
				assert(value > 0, `Config: MapDimensions.{path} ({value}) ต้องเป็นบวก`)
			else
				-- vec2 = ผังบนพื้น (ไม่มีแกน Y) · vec3 = ขนาด Part จริง (มีความสูง)
				-- ⚠️ **ห้ามเขียน `value.Z` ตรง ๆ** — `Vector2` จริงของ Roblox เป็น userdata
				-- ที่ **error ทันทีเมื่ออ่าน member ที่ไม่มี** ไม่ใช่คืน nil เหมือน table ธรรมดา
				-- เคยเขียนแบบนั้นแล้ว validate() พังตอนบูตใน Studio (เซิร์ฟไม่สร้างแมพเลย)
				-- แต่เทสต์ผ่าน เพราะ fallback นอก Roblox เป็น table ที่คืน nil
				local z = optionalZ(value)
				local axes = if z ~= nil then "สามแกน" else "สองแกน"
				assert(
					value.X > 0 and value.Y > 0 and (z == nil or z > 0),
					`Config: MapDimensions.{path} ต้องเป็นบวกทั้ง{axes}`
				)
			end
		end
	end

	-- ⚠️ กำแพงใสกั้นขอบแมพต้องสูงกว่าที่ผู้เล่นกระโดดได้
	-- เตี้ยกว่านี้ = กระโดดข้ามแล้วตกแท่นลอย ซึ่งเป็นสิ่งที่กำแพงใสมีไว้กันพอดี
	assert(
		dim.Boundary.Height > dim.Player.JumpHeight,
		`Config: กำแพงใสสูง {dim.Boundary.Height} ไม่เกินความสูงกระโดด {dim.Player.JumpHeight} — กระโดดข้ามได้`
	)

	-- ⚠️ รังบอสต้องอยู่ในช่วงของด่านตัวเอง และ **อยู่หลังกำแพง** ของด่านนั้น
	-- หลุดออกไปเมื่อไหร่ = รังไปโผล่ในด่านอื่น หรือโผล่หน้ากำแพงจนเข้าได้ทั้งที่ยังพังไม่ได้
	local inset = Config.getBossRoomInset()
	assert(
		inset > 0 and inset < dim.Lane.LengthPerStage,
		`Config: รังบอสถอยเข้ามา {inset} เกินความยาวช่วงด่าน ({dim.Lane.LengthPerStage}) — ห้องใหญ่เกินด่าน`
	)
	assert(
		dim.BossRoom.Size.Y <= dim.Lane.Width * 3,
		"Config: รังบอสกว้างเกินเลนไปมาก ผู้เล่นจะเดินอ้อมกำแพงได้"
	)
	for nestStage = 1, Config.Balance.Stage.COUNT do
		local center = Config.getBossNestCenter(nestStage)
		local startX = Config.getStageStartX(nestStage)
		local endX = startX + dim.Lane.LengthPerStage
		assert(
			center.X > startX and center.X < endX,
			`Config: รังบอสด่าน {nestStage} หลุดออกนอกช่วงของด่านตัวเอง`
		)
		-- ด่านที่มีกำแพงต้องมีรังอยู่หลังกำแพงเสมอ (กำแพงอยู่ต้นช่วง)
		local wallX = Config.getWallX(nestStage)
		if wallX then
			assert(
				center.X - dim.BossRoom.Size.X / 2 > wallX + dim.StageWall.Thickness / 2,
				`Config: รังบอสด่าน {nestStage} ล้ำมาหน้ากำแพง — เข้าได้ทั้งที่ยังพังกำแพงไม่ได้`
			)
		end
	end

	-- ด่าน 1 ต้องไม่มีกำแพง ผู้เล่นใหม่ต้องเดินเข้ารังด่าน 1 ได้ทันที
	assert(Config.getWallX(1) == nil, "Config: ด่าน 1 ต้องไม่มีกำแพง (getWallX(1) ต้องเป็น nil)")

	-- ══ โซนต้องไม่ทับกัน ══ เรียงจากซ้ายไปขวา: ร้าน → ลานคอก → เลนรบ
	local shop = Config.getShopCenter()
	assert(
		shop.X + dim.Shop.StallSize.X / 2 < Config.getPenYardLeftX(),
		"Config: แผงร้านค้าทับลานคอก"
	)
	assert(
		Config.getLaneStartX() >= Config.getPenYardRightX(),
		"Config: ต้นเลนรบล้ำเข้าลานคอก"
	)

	-- ⚠️ ทางเดินกลางต้องกว้างพอให้ตัวละครเดินผ่านได้จริง
	-- แคบกว่านี้ = เดินจากร้านไปเลนรบไม่ได้ = แมพขาดเป็นสองส่วน
	-- (ไม่ต้องเช็คว่าคอกล้ำทางเดินไหม เพราะ getPenPlotCenter วางคอกถอยตามความกว้างทางเดินอยู่แล้ว)
	assert(
		dim.Pen.RowGap >= MIN_WALKABLE_WIDTH,
		`Config: ทางเดินกลางกว้าง {dim.Pen.RowGap} แคบกว่าที่ตัวละครเดินผ่านได้ ({MIN_WALKABLE_WIDTH})`
	)
	assert(
		dim.Lane.Width >= MIN_WALKABLE_WIDTH,
		`Config: เลนรบกว้าง {dim.Lane.Width} แคบกว่าที่ตัวละครเดินผ่านได้ ({MIN_WALKABLE_WIDTH})`
	)

	-- ══ คอกต้องไม่ทับกันเอง ══
	for a = 1, Config.World.MAX_PENS do
		local ca = Config.getPenPlotCenter(a)
		for b = a + 1, Config.World.MAX_PENS do
			local cb = Config.getPenPlotCenter(b)
			local apartX = math.abs(ca.X - cb.X) >= dim.Pen.Size.X - 1e-6
			local apartZ = math.abs(ca.Z - cb.Z) >= dim.Pen.Size.Y - 1e-6
			assert(apartX or apartZ, `Config: คอกแปลง {a} กับ {b} ทับกัน`)
		end
	end

	-- ⚠️ จุดเกิดของทุกคนต้องอยู่บนพื้นลาน ไม่ใช่กลางอากาศ
	-- แท่นลอยไม่มีอะไรรับข้างล่าง หลุดขอบเมื่อไหร่ = ตกตั้งแต่วินาทีแรกที่เข้าเกม
	-- และต้องอยู่ในทางเดินกลาง (ไม่ใช่ในคอกของคนอื่น) เพื่อให้เดินออกไปไหนก็ได้ทันที
	local plazaMinX, plazaMaxX = Config.getPlazaMinX(), Config.getPlazaMaxX()
	local plazaHalfZ = Config.getPlazaHalfDepth()
	for penIndex = 1, Config.World.MAX_PENS do
		local point = Config.getSpawnPointForPen(penIndex)
		assert(
			point.X >= plazaMinX and point.X <= plazaMaxX and math.abs(point.Z) <= plazaHalfZ,
			`Config: จุดเกิดของคอก {penIndex} อยู่นอกพื้นลาน — ผู้เล่นจะตกแท่นลอยทันทีที่เข้าเกม`
		)
		assert(
			math.abs(point.Z) <= dim.Pen.RowGap / 2,
			`Config: จุดเกิดของคอก {penIndex} ไม่ได้อยู่ในทางเดินกลาง — ไปโผล่ในคอกคนอื่น`
		)
	end
	local centerSpawn = Config.getSpawnPoint()
	assert(
		centerSpawn.X >= plazaMinX and centerSpawn.X <= plazaMaxX
			and math.abs(centerSpawn.Z) <= plazaHalfZ,
		"Config: จุดเกิดกลางอยู่นอกพื้นลาน"
	)

	----------------------------------------------------------------------------
	-- อัปเกรดความเร็ว + กฎความหนากำแพงที่ผูกกับความเร็ว
	----------------------------------------------------------------------------
	local speed = Config.Balance.SpeedUpgrade
	assert(
		speed.MAX_LEVEL >= 1 and speed.MAX_LEVEL % 1 == 0,
		"Config: SpeedUpgrade.MAX_LEVEL ต้องเป็นจำนวนเต็มบวก"
	)
	assert(speed.BASE_COST > 0, "Config: SpeedUpgrade.BASE_COST ต้องมากกว่า 0")
	assert(speed.COST_MULTIPLIER > 1, "Config: ราคาขั้นความเร็วต้องแพงขึ้นทุกขั้น (COST_MULTIPLIER > 1)")
	assert(speed.CURVE_EXPONENT > 0, "Config: SpeedUpgrade.CURVE_EXPONENT ต้องมากกว่า 0")
	assert(speed.PHYSICS_FPS > 0, "Config: SpeedUpgrade.PHYSICS_FPS ต้องมากกว่า 0")
	assert(speed.THICKNESS_SAFETY >= 1, "Config: SpeedUpgrade.THICKNESS_SAFETY ต้องไม่น้อยกว่า 1")
	assert(
		speed.MAX_MULTIPLIER > 1,
		"Config: SpeedUpgrade.MAX_MULTIPLIER ต้องมากกว่า 1 ไม่งั้นซื้อแล้วไม่ได้อะไร"
	)

	-- ราคาต้องเรียงจากน้อยไปมากเสมอ และขั้นสุดท้ายต้องมีราคา (ไม่ใช่ nil)
	local prevCost = 0
	for level = 0, speed.MAX_LEVEL - 1 do
		local cost = Config.getSpeedUpgradeCost(level)
		assert(cost ~= nil, `Config: ขั้นความเร็ว {level + 1} ไม่มีราคา`)
		assert(
			(cost :: number) > prevCost,
			`Config: ราคาขั้นความเร็ว {level + 1} ({cost}) ไม่ได้แพงกว่าขั้นก่อนหน้า ({prevCost})`
		)
		prevCost = cost :: number
	end
	assert(
		Config.getSpeedUpgradeCost(speed.MAX_LEVEL) == nil,
		"Config: เต็มเพดานความเร็วแล้วต้องซื้อต่อไม่ได้ (ต้องคืน nil)"
	)

	-- ตัวคูณต้องไล่ขึ้นไม่ถอยหลัง และจบที่ MAX_MULTIPLIER พอดี
	local prevMult = 0
	for level = 0, speed.MAX_LEVEL do
		local mult = Config.getSpeedMultiplier(level)
		assert(mult > prevMult, `Config: ตัวคูณความเร็วขั้น {level} ไม่ได้มากกว่าขั้นก่อนหน้า`)
		prevMult = mult
	end
	assert(
		math.abs(Config.getSpeedMultiplier(speed.MAX_LEVEL) - speed.MAX_MULTIPLIER) < 1e-9,
		"Config: ตัวคูณขั้นสุดท้ายต้องเท่ากับ MAX_MULTIPLIER พอดี"
	)

	-- ⚠️ เพดานความเร็วที่ Roblox รับได้ — เกินแล้วตัวละครทะลุของทั้งแมพ
	-- ไม่ใช่เรื่องที่แก้ด้วยความหนากำแพงได้ เพราะกำแพงที่หนาพอจะกินพื้นที่เล่นไปหมด
	local maxSpeed = Config.getMaxWalkSpeed()
	assert(
		maxSpeed <= speed.SPEED_CEILING,
		`Config: ความเร็วสูงสุด {string.format("%.1f", maxSpeed)} เกินเพดาน {speed.SPEED_CEILING} `
			.. `— เกินแล้วตัวละครทะลุกำแพงจนเล่นไม่ได้ ลด MAX_MULTIPLIER หรือ MapDimensions.Player.WalkSpeed`
	)

	-- ⚠️ กำแพงทุกชนิดที่ **ชนได้** ต้องหนากว่าระยะที่ผู้เล่นขยับได้ใน 1 เฟรม
	-- ขึ้นความเร็วแล้วลืมเพิ่มความหนา = วิ่งทะลุ ซึ่งมองไม่เห็นจนกว่าจะเจอในเกม
	local minThickness = Config.getMinWallThickness()
	for _, entry in
		{
			{ name = "Map.WALL_THICKNESS (กำแพงกั้นด่าน)", value = dim.StageWall.Thickness },
			{ name = "Map.LANE_WALL_THICKNESS (กำแพงข้างเลน)", value = dim.Lane.WallThickness },
			{ name = "Map.BOUNDARY_THICKNESS (กำแพงใสขอบแมพ)", value = dim.Boundary.Thickness },
			-- ⚠️ **รั้วคอกไม่อยู่ในรายการนี้โดยตั้งใจ** — `CanCollide = false`
			-- กฎความหนามีไว้กับกำแพงที่ต้อง "หยุด" ผู้เล่นเท่านั้น รั้วเป็นของประดับล้วน
			-- เคยเอาเข้ามาในรายการนี้แล้วต้องดันรั้วหนาเป็น 5 จนกลายเป็นกำแพงเตี้ย
		}
	do
		assert(
			entry.value >= minThickness,
			`Config: {entry.name} หนา {entry.value} บางกว่าขั้นต่ำ {string.format("%.2f", minThickness)} `
				.. `ที่ความเร็วสูงสุด {string.format("%.1f", maxSpeed)} — ผู้เล่นจะวิ่งทะลุ`
		)
	end

	-- ⚠️ รั้ววางคร่อมขอบแปลง ครึ่งหนึ่งยื่นเข้าข้างใน · ขอบกันชนต้องกว้างกว่านั้น
	-- (รั้วทะลุได้ก็จริง แต่แม่ไม่ควรเดินไปยืนซ้อนกับรั้วให้ดูแปลก)
	assert(
		dim.Pen.EdgeMargin >= dim.Pen.FenceThickness / 2,
		`Config: รั้วหนา {dim.Pen.FenceThickness} ยื่นเข้าคอก {dim.Pen.FenceThickness / 2} `
			.. `แต่ขอบกันชนมีแค่ {dim.Pen.EdgeMargin} — แม่จะเดินไปยืนซ้อนกับรั้ว`
	)

	-- ══ ประตูคอก ══ เว้นช่องกลางรั้วด้านที่หันเข้าทางเดิน
	assert(
		dim.Pen.GateWidth < dim.Pen.Size.X,
		`Config: ประตูกว้าง {dim.Pen.GateWidth} แต่คอกกว้างแค่ {dim.Pen.Size.X} — จะไม่เหลือรั้วเลย`
	)
	assert(
		dim.Pen.GateWidth >= MIN_WALKABLE_WIDTH * 0.75,
		`Config: ประตูกว้าง {dim.Pen.GateWidth} แคบเกินกว่าจะเดินเข้าได้สบาย`
	)

	-- ⚠️ ทางเดินกลางต้องกว้างไม่น้อยกว่าเลนรบ
	-- เดินจากลานเข้าเลนแล้วต้องไม่รู้สึกว่าถูกบีบ · เคยกว้างแค่ครึ่งเดียวของเลน
	assert(
		dim.Pen.RowGap >= dim.Lane.Width,
		`Config: ทางเดินกลางกว้าง {dim.Pen.RowGap} แคบกว่าเลนรบ ({dim.Lane.Width}) — `
			.. `ปากทางเข้าเลนจะกลายเป็นคอขวด`
	)

	-- ⚠️⚠️ กำแพงใสต้องอยู่ **นอก** ของทุกอย่างที่ผู้เล่นต้องเดินไปถึง
	-- กำแพงวางถอยเข้ามาจากขอบพื้นเท่ากับ BOUNDARY_MARGIN ดังนั้นถ้าพื้นไม่โตตาม margin
	-- การดัน margin ขึ้นจะกลายเป็นการกินพื้นที่เล่นเข้ามาเรื่อย ๆ
	-- เคยพลาดจริง: ดัน margin 20 → 50 แล้วกำแพงกินเข้าไปในคอก 30 studs
	-- และตัดแผงร้านออกไปอยู่นอกกำแพง โดยที่ไม่มียามตัวไหนจับได้เลย
	local wallHalfZ = Config.getPlazaHalfDepth() - dim.Boundary.Margin
	local wallMinX = Config.getPlazaMinX() + dim.Boundary.Margin
	-- ⚠️ ฝั่งตะวันออกเคยเป็นบั๊กจริง: กำแพงวางชิดขอบคอกคอลัมน์ขวาสุดจนรั้วไม้ซ้อนทับกำแพง
	-- (ไม่มียามตัวไหนจับได้ตอนนั้นเหมือนกัน) เพิ่มยามนี้กันไม่ให้กลับมาเป็นซ้ำ
	local eastWallInnerX = Config.getEastBoundaryX() - dim.Boundary.Thickness / 2
	for penIndex = 1, Config.World.MAX_PENS do
		local center = Config.getPenPlotCenter(penIndex)
		local outerZ = math.abs(center.Z) + dim.Pen.Size.Y / 2
		assert(
			wallHalfZ >= outerZ,
			`Config: กำแพงใสอยู่ที่ Z = ±{wallHalfZ} แต่คอก {penIndex} กินไปถึง ±{outerZ} `
				.. `— กำแพงกินเข้าไปในคอก {outerZ - wallHalfZ} studs`
		)
		assert(
			wallMinX <= center.X - dim.Pen.Size.X / 2,
			`Config: กำแพงใสอยู่ที่ X = {wallMinX} ซึ่งกินเข้าไปในคอก {penIndex}`
		)
		assert(
			center.X + dim.Pen.Size.X / 2 <= eastWallInnerX,
			`Config: กำแพงใสฝั่งตะวันออกอยู่ที่ X = {eastWallInnerX} ซึ่งกินเข้าไปในคอก {penIndex}`
		)
	end
	for stallIndex = 1, dim.Shop.StallCount do
		local stall = Config.getShopStallCenter(stallIndex)
		assert(
			wallMinX <= stall.X - dim.Shop.StallSize.X / 2,
			`Config: กำแพงใสอยู่ที่ X = {wallMinX} แต่แผงร้าน {stallIndex} อยู่ที่ `
				.. `{stall.X - dim.Shop.StallSize.X / 2} — แผงอยู่นอกกำแพง เดินไปไม่ถึง`
		)
		assert(
			math.abs(stall.Z) + dim.Shop.StallSize.Y / 2 <= wallHalfZ,
			`Config: แผงร้าน {stallIndex} อยู่นอกกำแพงใสตามแกน Z`
		)
	end

	-- ══ แผงร้าน (UI-2): ติดกันกลางผนังหลัง เว้นช่องเดินได้ ══
	assert(
		dim.Shop.StallGap >= dim.Pen.GateWidth,
		`Config: Shop.StallGap = {dim.Shop.StallGap} แคบกว่าประตูคอก ({dim.Pen.GateWidth}) — เดินผ่านระหว่างแผงไม่สะดวก`
	)
	-- ══ กำแพงข้างเลน (UI-2): เริ่มเสมอกำแพงใสฝั่งตะวันออก ไม่ยื่นเข้าลาน ══
	local laneWallStart = Config.getLaneWallStartX()
	assert(
		laneWallStart >= Config.getLaneStartX(),
		"Config: กำแพงข้างเลนเริ่มก่อนต้นเลน — ยื่นเข้าลานคอก"
	)
	assert(
		laneWallStart < Config.getBossNestCenter(1).X - dim.BossRoom.Size.X / 2,
		"Config: กำแพงข้างเลนเริ่มเลยห้องบอสด่าน 1 — ช่วงก่อนห้องไม่มีกำแพง"
	)
	-- 5B: พื้นเลนสีน้ำตาลเริ่มเสมอแนวกำแพงหิน (ช่องประตู) — ไม่ยื่นเข้าลาน · ไม่ก่อนต้นเลน (ภาพล้วน)
	assert(
		Config.getLaneFloorStartX() == eastWallInnerX and Config.getLaneFloorStartX() >= Config.getLaneStartX(),
		"Config: พื้นเลนต้องเริ่มที่ผิวด้านในกำแพงหินขอบแมพพอดี (ไม่ยื่นออกมาบนหญ้าในลาน)"
	)

	-- ══ ป้ายบนแมพ (UI-2) ══ ต้องไม่ขวางประตู · ไม่ทับป้ายชื่อ · ไม่ล้ำไปแปลงข้าง ๆ · อยู่ในกำแพงใส
	local sign = dim.MapSign
	assert(
		sign.SellStallIndex >= 1 and sign.SellStallIndex <= dim.Shop.StallCount and sign.SellStallIndex % 1 == 0,
		`Config: MapSign.SellStallIndex = {sign.SellStallIndex} ไม่มีแผงร้านนี้ (มี {dim.Shop.StallCount} แผง)`
	)
	assert(
		sign.SellCloseDistance > sign.SellPromptDistance,
		"Config: MapSign.SellCloseDistance ต้องไกลกว่า SellPromptDistance ไม่งั้นกดเปิดร้านแล้วหน้าต่างปิดเองทันที"
	)
	-- 5C: ร้านกระบอง = อีกแผงหนึ่ง (ไม่ใช่แผงเดียวกับร้านขายแม่ — จุดกด E สองอันบนเคาน์เตอร์เดียวจะแย่งกัน)
	assert(
		sign.WeaponStallIndex >= 1 and sign.WeaponStallIndex <= dim.Shop.StallCount and sign.WeaponStallIndex % 1 == 0,
		`Config: MapSign.WeaponStallIndex = {sign.WeaponStallIndex} ไม่มีแผงร้านนี้ (มี {dim.Shop.StallCount} แผง)`
	)
	assert(sign.WeaponStallIndex ~= sign.SellStallIndex, "Config: ร้านกระบองกับร้านขายแม่ต้องอยู่คนละแผง")
	assert(
		sign.WeaponCloseDistance > sign.WeaponPromptDistance,
		"Config: MapSign.WeaponCloseDistance ต้องไกลกว่า WeaponPromptDistance ไม่งั้นกดเปิดร้านแล้วหน้าต่างปิดเองทันที"
	)
	local signHalf = sign.BoardSize.X / 2
	for penIndex = 1, Config.World.MAX_PENS do
		local center = Config.getPenPlotCenter(penIndex)
		local nameSign = Config.getPenNameSignSpot(penIndex)
		local spots: { Vector3 } = {}
		-- ⚠️ ต้องประกาศชนิดของ kind เอง — ไม่งั้น Luau ขยาย "speed" | "pen" เป็น string แล้วส่งเข้าฟังก์ชันไม่ได้
		local kinds: { PenSignKind } = Config.getPenSignKinds()
		for kindIndex = 1, #kinds do
			local kind: PenSignKind = kinds[kindIndex]
			local spot = Config.getPenUpgradeSignSpot(penIndex, kind)
			table.insert(spots, spot)
			local fromGate = math.abs(spot.X - center.X) - signHalf
			assert(
				fromGate >= dim.Pen.GateWidth / 2 + dim.Pen.SignGateClearance - 1e-6,
				`Config: ป้าย {kind} ของคอก {penIndex} ขวางประตู (ห่างขอบประตู {fromGate - dim.Pen.GateWidth / 2})`
			)
			assert(
				math.abs(spot.X - nameSign.X) >= signHalf + dim.Pen.SignSize.X / 2 - 1e-6,
				`Config: ป้าย {kind} ของคอก {penIndex} ทับป้ายชื่อคอก`
			)
			assert(
				math.abs(spot.X - center.X) + signHalf <= dim.Pen.Size.X / 2,
				`Config: ป้าย {kind} ของคอก {penIndex} ล้ำออกนอกแนวคอก (ไปทับช่องว่างระหว่างคอก)`
			)
		end
		assert(spots[1].X ~= spots[2].X, `Config: ป้ายค่าวิ่งกับป้ายอัปคอกของคอก {penIndex} อยู่ที่เดียวกัน`)
	end
	local damageSpot = Config.getDamageSignSpot()
	assert(
		damageSpot.Z - signHalf >= dim.Lane.Width / 2,
		"Config: ป้ายดาเมจล้ำเข้าไปในปากเลนรบ (ขวางทางเข้าเลน)"
	)
	assert(
		damageSpot.Z + signHalf <= dim.Pen.RowGap / 2,
		"Config: ป้ายดาเมจล้ำเข้าไปในแนวคอกแถวบน"
	)
	assert(
		damageSpot.X < Config.getLaneStartX() and damageSpot.X <= eastWallInnerX,
		"Config: ป้ายดาเมจต้องอยู่ในลาน ก่อนถึงต้นเลน (ในกำแพงใส)"
	)

	-- ══ แท่นอัญเชิญ (UI-3 · ย้ายเข้าเลนใน 5B-fix): อยู่ในเลนหลังช่องประตู ก่อนห้องบอส · ไม่บังทาง · จุดกดไม่ทับป้ายดาเมจ ══
	local pedestal = dim.SummonPedestal
	local pedestalCenter = Config.getSummonPedestalCenter()
	local pedestalHalf = pedestal.Diameter / 2
	assert(pedestal.CoreDiameter < pedestal.Diameter, "Config: แกนเรืองแสงของแท่นอัญเชิญต้องเล็กกว่าฐาน")
	assert(pedestal.EntranceGap >= 0, "Config: SummonPedestal.EntranceGap ติดลบไม่ได้ (แท่นจะล้ำออกมาทับช่องประตู)")
	assert(
		pedestalCenter.X - pedestalHalf >= laneWallStart,
		`Config: แท่นอัญเชิญล้ำออกมาทับช่องประตู/ลาน (ต้องเริ่มหลัง X {laneWallStart} = ในเลน สนามรบ)`
	)
	assert(
		pedestalCenter.X + pedestalHalf <= Config.getBossNestCenter(1).X - dim.BossRoom.Size.X / 2 - dim.Lane.WallThickness / 2,
		"Config: แท่นอัญเชิญล้ำเข้าไปในห้องบอสด่าน 1"
	)
	assert(
		dim.Lane.Width / 2 - dim.Lane.WallThickness / 2 - pedestalHalf >= dim.Pen.GateWidth,
		"Config: แท่นอัญเชิญกว้างจนเหลือทางเดินข้างแท่นแคบกว่าประตูคอก (บังทางเดินในเลน)"
	)
	assert(pedestal.PromptHoldSeconds > 0, "Config: แท่นอัญเชิญต้องกด E ค้าง (PromptHoldSeconds > 0)")
	assert(
		pedestal.PromptDistance > pedestalHalf,
		"Config: ระยะกด E ของแท่นอัญเชิญสั้นกว่ารัศมีแท่น — ยืนบนขอบแท่นแล้วกดไม่ได้"
	)
	assert(
		pedestal.CloseDistance > pedestal.PromptDistance,
		"Config: SummonPedestal.CloseDistance ต้องไกลกว่า PromptDistance ไม่งั้นกดเปิดแล้วหน้าต่างปิดเองทันที"
	)
	local pedestalToDamage = math.sqrt((damageSpot.X - pedestalCenter.X) ^ 2 + (damageSpot.Z - pedestalCenter.Z) ^ 2)
	assert(
		pedestalToDamage > pedestal.PromptDistance + sign.PromptDistance,
		`Config: ระยะกด E ของแท่นอัญเชิญทับป้ายดาเมจ (ห่างกัน {pedestalToDamage})`
	)

	-- ══ บอสทุกห้อง + วงจรกลางวัน/กลางคืน (Phase 5A · 5B · 5B-2) ══
	do
		local cycle = Config.Balance.BossCycle
		local arena = dim.BossArena
		local room = dim.BossRoom
		local stageCount = Config.Balance.Stage.COUNT
		assert(cycle.DAY_SECONDS > 0 and cycle.NIGHT_SECONDS >= 1, "Config: BossCycle ต้องมีทั้งกลางวันและกลางคืน (อย่างน้อย 1 วินาที)")
		-- 5B-2: ค่าห้องเดียวของ 5A/5B ลบแล้ว — ห้ามเติมกลับ (มีสองแหล่งแล้วอ่านผิดแหล่ง)
		for key, replacement in REMOVED_BOSS_CYCLE_KEYS do
			assert(
				(cycle :: any)[key] == nil,
				`Config: BossCycle.{key} ลบแล้วใน 5B-2 (บอสทุกห้อง) — ใช้ {replacement} แทน ห้ามเติมกลับ`
			)
		end
		assert((arena :: any).Stage == nil, "Config: BossArena.Stage ลบแล้วใน 5B-2 — บอสมีทุกห้อง ไม่มี \"ห้องบอสกลาง\" แล้ว")
		-- HP / เงิน / ไข่ ต่อห้อง (ค่าจากโมเดลสมดุล) — เงินต้องเป็นจำนวนเต็ม (แบ่งแบบปัดลง เศษทศนิยมจะงอกเงิน)
		for stage = 1, stageCount do
			local hp = Config.getBossHp(stage)
			local reward = Config.getBossKillReward(stage)
			assert(hp > 0 and hp % 1 == 0, `Config: HP บอสห้อง {stage} ต้องเป็นจำนวนเต็มบวก (ได้ {hp})`)
			assert(reward >= 0 and reward % 1 == 0, `Config: เงินบอสห้อง {stage} ต้องเป็นจำนวนเต็ม ≥ 0 (ได้ {reward})`)
			if stage > 1 then
				assert(hp > Config.getBossHp(stage - 1), `Config: HP บอสห้อง {stage} ต้องมากกว่าห้อง {stage - 1}`)
				assert(reward > Config.getBossKillReward(stage - 1), `Config: เงินบอสห้อง {stage} ต้องมากกว่าห้อง {stage - 1}`)
			end
			-- ไข่ห้อง N = ไข่รายด่านเดิม (egg_stageN) — มีอยู่ เปิดใช้ มาจากบอส (ไม่ใช่ไข่ Robux)
			local eggId = Config.getBossEggId(stage)
			local eggType = EggTypes[eggId]
			assert(
				eggType ~= nil and eggType.enabled and eggType.source == "boss" and eggType.stage == stage,
				`Config: ไข่บอสห้อง {stage} ("{eggId}") ต้องมีอยู่ เปิดใช้ source = "boss" และผูกด่าน {stage}`
			)
		end
		-- ห้อง 1 ต้องเข้าได้ทุกคน (ผู้เล่นใหม่ไม่มีกำแพงให้พัง) · ห้องที่มีกำแพงต้องพังก่อน
		assert(Config.canAccessBossRoom(1, 1), "Config: ห้องบอส 1 ต้องเข้าได้ทุกคน (ด่าน 1 ไม่มีกำแพง)")
		for stage = 2, stageCount do
			assert(
				Config.canAccessBossRoom(stage, stage) and not Config.canAccessBossRoom(stage - 1, stage),
				`Config: สิทธิ์เข้าห้องบอส {stage} ต้องได้เมื่อพังกำแพงด่าน {stage} แล้วเท่านั้น`
			)
		end
		assert(
			cycle.PLAYER_ATTACK_COOLDOWN > 0 and cycle.PLAYER_ATTACK_RANGE > 0,
			"Config: คูลดาวน์/ระยะตีบอสของผู้เล่นต้องมากกว่า 0 (คูลดาวน์ 0 = ยิงรัวได้ไม่จำกัด)"
		)
		assert(type(cycle.BOSS_ATTACK_ENABLED) == "boolean", "Config: BossCycle.BOSS_ATTACK_ENABLED ต้องเป็น boolean")
		assert(
			cycle.BOSS_ATTACK_INTERVAL > 0 and cycle.BOSS_ATTACK_DAMAGE >= 0 and cycle.BOSS_ATTACK_RANGE > 0,
			"Config: ค่าบอสตีกลับต้องเป็นบวก (INTERVAL > 0 · DAMAGE ≥ 0 · RANGE > 0)"
		)
		assert(cycle.EGGS_PER_NIGHT >= 1, "Config: BossCycle.EGGS_PER_NIGHT ต้องมีอย่างน้อย 1")
		assert(cycle.EGG_PICKUP_HOLD_SECONDS > 0, "Config: หยิบไข่บอสต้องกด E ค้าง (EGG_PICKUP_HOLD_SECONDS > 0)")
		assert(
			cycle.EGG_PICKUP_HOLD_TOLERANCE >= 0 and cycle.EGG_PICKUP_HOLD_TOLERANCE < cycle.EGG_PICKUP_HOLD_SECONDS / 2,
			"Config: EGG_PICKUP_HOLD_TOLERANCE ต้อง ≥ 0 และน้อยกว่าครึ่งเวลากดค้าง (ไม่งั้นกดแป๊บเดียวก็หยิบได้)"
		)
		assert(cycle.HEAVY_EGG_ALERT_KG > 0, "Config: BossCycle.HEAVY_EGG_ALERT_KG ต้องมากกว่า 0")
		assert(
			cycle.BOSS_HP_BASE > 0 and cycle.BOSS_HP_MULTIPLIER > 1,
			"Config: สเกล HP บอสต่อด่านต้องเป็นบวกและโตขึ้นทุกด่าน"
		)
		assert(
			cycle.MODEL_BOSS_SPAWN_SECONDS > 0 and cycle.MODEL_EGGS_PER_SPAWN > 0,
			"Config: ค่าบอสของโมเดลสมดุล (MODEL_*) ต้องเป็นบวก — ยามเวลาฟาร์ม/รายได้อ้างอิงหารด้วยค่านี้"
		)

		-- ══ 5B: กำแพงกั้นปิดช่องประตูของกำแพงหินขอบแมพฝั่งตะวันออกพอดี ══
		-- MapBuilder.buildBoundary แบ่งกำแพงฝั่งตะวันออกเป็น EastUpper/EastLower เว้นช่อง |Z| < Lane.Width/2
		-- → กำแพงกั้นต้อง: X เดียวกัน · หนาเท่ากัน · สูงเท่ากัน · กว้างเท่าช่องพอดี (ชนปลายกัน ไม่ทับ = ไม่กระพริบ)
		local barrierSize = Config.getBossBarrierSize()
		local barrierFront = Config.getBossBarrierFrontX()
		assert(
			barrierSize.X >= Config.getMinWallThickness(),
			`Config: กำแพงกั้นบอสหนา {barrierSize.X} บางกว่าเกณฑ์ {Config.getMinWallThickness()} — วิ่งเร็วสุดแล้วทะลุได้`
		)
		assert(
			Config.getBossBarrierX() == Config.getEastBoundaryX() and barrierSize.X == dim.Boundary.Thickness,
			"Config: กำแพงกั้นบอสไม่เสมอแนวกำแพงหินขอบแมพฝั่งตะวันออก — ยื่นเข้าลาน/เข้าเลน"
		)
		assert(barrierSize.Y == dim.Boundary.Height, "Config: กำแพงกั้นบอสสูงไม่เท่ากำแพงหินข้าง ๆ")
		assert(
			barrierSize.Z == dim.Lane.Width,
			"Config: กำแพงกั้นบอสกว้างไม่เท่าช่องทางเข้าเลน (เหลือช่อง = เดินลอดได้ · เกิน = ทับกำแพงหิน = กระพริบ)"
		)
		assert(barrierFront == eastWallInnerX, "Config: ผิวหน้ากำแพงกั้นต้องเสมอผิวด้านในกำแพงหินขอบแมพ")
		assert(
			Config.getBossBarrierX() + barrierSize.X / 2 <= laneWallStart,
			"Config: กำแพงกั้นบอสล้ำเข้าไปในกำแพงข้างเลน (ซ้อนกัน = กระพริบ)"
		)
		-- 5B-fix (ผู้ใช้สั่ง): แท่นอัญเชิญอยู่**หลัง**กำแพงกั้น ในสนามรบ · จุดกด E ต้องไม่ทะลุกำแพงกั้นออกมาถึงฝั่งลาน
		-- (กลางคืนกดที่แท่นไม่ได้ 1 นาที — ยอมรับตามที่สั่ง)
		assert(
			pedestalCenter.X - pedestalHalf >= Config.getBossBarrierX() + barrierSize.X / 2,
			"Config: แท่นอัญเชิญต้องอยู่หลังกำแพงกั้น (ในสนามรบ) ไม่ทับกำแพงกั้น"
		)
		assert(
			pedestalCenter.X - pedestal.PromptDistance >= barrierFront,
			"Config: จุดกด E ของแท่นอัญเชิญยื่นทะลุกำแพงกั้นออกมาฝั่งลาน (กดจากเซฟโซนได้)"
		)

		-- ══ 5B: โซน — เซฟโซนกับห้องด่านบอสต้องต่อกันพอดี (ไม่มีช่วงที่ไม่ใช่ทั้งสองอย่าง) ══
		local roomMinX = Config.getStageRoomRangeX(1)
		assert(Config.getSafeZoneEdgeX() == barrierFront, "Config: ขอบเซฟโซนต้องเป็นผิวหน้ากำแพงกั้น (ปากทางเข้าเลน)")
		assert(roomMinX == Config.getSafeZoneEdgeX(), "Config: ห้องบอส 1 ต้องเริ่มที่ขอบเซฟโซนพอดี")
		-- 5B-2: ห้องต่อกันตามลำดับ · คั่นด้วยเนื้อกำแพงด่านพอดี (ไม่มีช่วงที่เป็นสองห้อง) · ห้องสุดท้ายจบที่ปลายเลน
		for stage = 1, stageCount do
			local minX, maxX = Config.getStageRoomRangeX(stage)
			assert(maxX > minX, `Config: ห้องบอส {stage} ยาว ≤ 0`)
			if stage > 1 then
				local _, prevMax = Config.getStageRoomRangeX(stage - 1)
				assert(
					minX - prevMax == dim.StageWall.Thickness,
					`Config: ห้องบอส {stage - 1} กับ {stage} ไม่ได้คั่นด้วยกำแพงด่าน {stage} พอดี (ห่าง {minX - prevMax})`
				)
			end
			if stage == stageCount then
				assert(maxX == Config.getLaneEndX(), `Config: ห้องบอส {stage} (ห้องสุดท้าย) ต้องจบที่ปลายเลน`)
			end
		end
		assert(
			not Config.isInSafeZone(pedestalCenter) and Config.getStageRoomAt(pedestalCenter) == 1,
			"Config: แท่นอัญเชิญต้องอยู่ในสนามรบ (ห้องบอส 1) ไม่ใช่เซฟโซน (5B-fix)"
		)
		for penIndex = 1, Config.World.MAX_PENS do
			local penCenter = Config.getPenPlotCenter(penIndex)
			assert(
				Config.isInSafeZone(vec3(penCenter.X + dim.Pen.Size.X / 2, 0, penCenter.Z))
					and Config.isInSafeZone(Config.getSpawnPointForPen(penIndex)),
				`Config: คอก {penIndex} / จุดเกิดต้องอยู่ในเซฟโซนทั้งแปลง`
			)
		end

		-- ══ 5B: จุดยืนหน้าป้อม (ฝั่งลานกลาง) — ครบทุกคน · หน้ากำแพงกั้น · ในเซฟโซน · ไม่ทับแท่น/ป้าย/คอก · ไม่ซ้อนกัน ══
		local playerHalf = 2 -- ครึ่งความกว้างตัวละครโดยประมาณ + เผื่อ
		local placed: { Vector3 } = {}
		for index = 1, Config.World.MAX_PENS do
			local spot = Config.getBossGatherSpot(index)
			assert(
				spot.X + playerHalf < barrierFront and Config.isInSafeZone(spot),
				`Config: จุดยืนหน้าป้อม {index} ต้องอยู่ฝั่งลาน (เซฟโซน) หน้ากำแพงกั้น`
			)
			assert(
				math.abs(spot.Z) + playerHalf <= dim.Lane.Width / 2,
				`Config: จุดยืนหน้าป้อม {index} ไม่ได้อยู่ตรงหน้าช่องทางเข้าเลน (มองตัวเลขบนกำแพงกั้นเฉียงเกินไป)`
			)
			assert(spot.X - playerHalf >= wallMinX, `Config: จุดยืนหน้าป้อม {index} อยู่นอกกำแพงขอบแมพฝั่งตะวันตก`)
			local toPedestal = math.sqrt((spot.X - pedestalCenter.X) ^ 2 + (spot.Z - pedestalCenter.Z) ^ 2)
			assert(
				toPedestal > pedestal.PromptDistance,
				`Config: จุดยืนหน้าป้อม {index} ใกล้แท่นอัญเชิญเกิน (ห่าง {toPedestal}) — ทับแท่น/จุดกด E ของแท่นโผล่ตอนรอ`
			)
			local toDamage = math.sqrt((spot.X - damageSpot.X) ^ 2 + (spot.Z - damageSpot.Z) ^ 2)
			assert(toDamage >= signHalf + playerHalf, `Config: จุดยืนหน้าป้อม {index} ทับป้ายดาเมจ`)
			assert(
				spot.X - playerHalf > Config.getPenYardRightX() or math.abs(spot.Z) + playerHalf <= dim.Pen.RowGap / 2,
				`Config: จุดยืนหน้าป้อม {index} ล้ำเข้าไปในคอก`
			)
			for other, prev in placed do
				local gap = math.sqrt((spot.X - prev.X) ^ 2 + (spot.Z - prev.Z) ^ 2)
				assert(gap >= playerHalf * 2, `Config: จุดยืนหน้าป้อม {index} ซ้อนกับจุด {other} (ห่าง {gap})`)
			end
			table.insert(placed, spot)
		end

		-- ตัวบอส: ระยะตียาวกว่าครึ่งตัวบอส (ยืนชิดแล้วต้องตีถึง)
		local bossHalf = math.max(arena.BossSize.X, arena.BossSize.Z) / 2
		assert(bossHalf < room.Size.X / 2 and bossHalf < room.Size.Y / 2, "Config: ตัวบอสใหญ่กว่าห้องบอส")
		assert(
			cycle.PLAYER_ATTACK_RANGE > bossHalf + 1,
			"Config: ระยะตีบอสสั้นกว่าครึ่งตัวบอส — ยืนชิดตัวแล้วยังตีไม่ถึง"
		)
		assert(
			arena.EggPickupRange >= arena.EggPromptDistance and arena.EggPromptDistance > 0,
			"Config: ระยะหยิบไข่ฝั่ง server ต้องไม่สั้นกว่าระยะจุดกด E (ไม่งั้นกดแล้วโดนปฏิเสธว่าไกลเกิน)"
		)
		assert(
			arena.EggColumns >= 1 and arena.EggColumnGap > 0 and arena.EggRowGap > 0,
			"Config: ตารางวางไข่บอสต้องมีอย่างน้อย 1 คอลัมน์และระยะห่างเป็นบวก"
		)

		-- ══ 5B: ฝั่งมุมบอสต่อด่าน — ครบทุกด่าน · สลับฟันปลา ══
		assert(
			#room.CornerSide == Config.Balance.Stage.COUNT,
			`Config: BossRoom.CornerSide มี {#room.CornerSide} ช่อง ต้องมีครบ {Config.Balance.Stage.COUNT} ด่าน`
		)
		for stage = 1, Config.Balance.Stage.COUNT do
			local side = room.CornerSide[stage]
			assert(side == "left" or side == "right", `Config: BossRoom.CornerSide[{stage}] ต้องเป็น "left" หรือ "right"`)
			if stage > 1 then
				assert(
					side ~= room.CornerSide[stage - 1],
					`Config: มุมบอสด่าน {stage - 1} กับ {stage} อยู่ฝั่งเดียวกัน — ต้องสลับฟันปลา (ซ้าย/ขวา) ทุกด่าน`
				)
			end
		end

		-- ══ 5B-2: บอส + ไข่ + ทางวิ่ง ครบทุกห้อง (ใช้จริงทุกห้องแล้ว) ══
		-- บอสในห้อง ฝั่งมุม · ทางวิ่งฝั่งตรงข้ามกว้างพอ (นอกระยะตีบอส) · ไข่หลังบอส มุมเดียวกัน ในห้อง ไม่ซ้อนกัน
		-- ทุกจุด (บอส · ไข่ · จุดยืนหยิบไข่) ต้องอยู่ใน "ห้องด่าน" ที่ server ใช้ตัดสิน (Config.getStageRoomAt) ของห้องตัวเอง
		-- ⚠️ ห้องไหนแคบ/สั้นจนวางไม่ลง = เซิร์ฟไม่บูต — ห้ามแก้ด้วยการย้าย/ขยายกำแพงด่าน (ผู้ใช้สั่ง) ต้องรายงาน
		local wallHalfT = dim.Lane.WallThickness / 2
		local roomInnerX = room.Size.X / 2 - wallHalfT
		local roomInnerZ = room.Size.Y / 2 - wallHalfT
		local laneInnerZ = dim.Lane.Width / 2 - wallHalfT
		local reach = math.max(cycle.PLAYER_ATTACK_RANGE, cycle.BOSS_ATTACK_RANGE)
		local eggRadius = Config.getBallRadius(dim.Blockout.EggSize) -- ไข่ tier 1 (ขนาดที่ออกบ่อยสุด)
		for stage = 1, stageCount do
			local nest = Config.getBossNestCenter(stage)
			local boss = Config.getBossCornerCenter(stage)
			local sign = Config.getBossCornerSign(stage)
			local stageRoomMinX, stageRoomMaxX = Config.getStageRoomRangeX(stage)
			assert(sign * boss.Z > 0, `Config: บอสด่าน {stage} ไม่ได้อยู่ฝั่งมุม ({room.CornerSide[stage]})`)
			assert(
				math.abs(boss.X - nest.X) + arena.BossSize.X / 2 <= roomInnerX
					and math.abs(boss.Z - nest.Z) + arena.BossSize.Z / 2 <= roomInnerZ,
				`Config: บอสด่าน {stage} ยื่นออกนอกห้องบอส`
			)
			assert(Config.getStageRoomAt(boss) == stage, `Config: บอสห้อง {stage} ไม่อยู่ในห้องด่าน {stage} ที่ server ใช้ตัดสิน`)
			-- ระยะตีบอสต้องไม่ถึงกำแพงด่าน (ทางเข้าห้อง) และไม่ถึงกำแพงด่านถัดไป — เข้า/ออกห้องแล้วไม่โดนบอสตีทันที
			assert(
				boss.X - reach > stageRoomMinX and boss.X + reach < stageRoomMaxX,
				`Config: ระยะตีบอสห้อง {stage} ลากถึงกำแพงหัว/ท้ายห้อง — ห้องสั้นเกินไป`
			)
			-- ทางวิ่ง: จากผนังฝั่งตรงข้าม (วัดที่ช่วงเลนปกติซึ่งแคบกว่าห้อง) ถึงขอบระยะตีของบอส
			local runPath = sign * boss.Z - reach + laneInnerZ
			assert(
				runPath >= arena.RunPathMinWidth,
				`Config: ทางวิ่งผ่านบอสด่าน {stage} กว้างแค่ {runPath} (ต้อง ≥ {arena.RunPathMinWidth}) — ระยะตีบอสกินทั้งเลน`
			)
			local eggs: { Vector3 } = {}
			for index = 1, cycle.EGGS_PER_NIGHT do
				local egg = Config.getBossEggSpot(stage, index)
				assert(egg.X - eggRadius > boss.X + arena.BossSize.X / 2, `Config: ไข่ {index} ด่าน {stage} ต้องอยู่หลังตัวบอส`)
				assert(sign * egg.Z > 0, `Config: ไข่ {index} ด่าน {stage} ต้องอยู่มุมเดียวกับบอส`)
				assert(
					math.abs(egg.X - nest.X) + eggRadius <= roomInnerX and math.abs(egg.Z - nest.Z) + eggRadius <= roomInnerZ,
					`Config: ไข่ {index} ด่าน {stage} อยู่นอกห้องบอส`
				)
				assert(egg.X + eggRadius < stageRoomMaxX, `Config: ไข่ {index} ด่าน {stage} ทับกำแพงด่านถัดไป`)
				assert(Config.getStageRoomAt(egg) == stage, `Config: ไข่ {index} ห้อง {stage} ไม่อยู่ในห้องด่าน {stage} ที่ server ใช้ตัดสิน`)
				-- จุดกด E ไม่เอื้อมข้ามกำแพงด่านถัดไป (ยืนอีกห้องแล้วกดไข่ห้องนี้ไม่ได้ · server หาห้องจากตำแหน่งคนกด)
				assert(
					egg.X + arena.EggPickupRange < stageRoomMaxX + dim.StageWall.Thickness,
					`Config: ระยะหยิบไข่ {index} ห้อง {stage} เอื้อมข้ามกำแพงด่านถัดไป`
				)
				for other, prev in eggs do
					local gap = math.sqrt((egg.X - prev.X) ^ 2 + (egg.Z - prev.Z) ^ 2)
					assert(gap >= eggRadius * 2 + 1, `Config: ไข่ {index} ด่าน {stage} ซ้อนกับไข่ {other} (ห่าง {gap})`)
				end
				table.insert(eggs, egg)
			end
		end
		-- 5B-fix: แท่นอัญเชิญอยู่ในห้องบอส 1 — ต้องพ้นระยะตีของบอสห้อง 1 (ยืนกด E ที่แท่นแล้วไม่โดนบอสตี)
		local bossPos = Config.getBossCornerCenter(1)
		local pedestalToBoss = math.sqrt((pedestalCenter.X - bossPos.X) ^ 2 + (pedestalCenter.Z - bossPos.Z) ^ 2)
		assert(
			pedestalToBoss > reach + pedestal.PromptDistance,
			`Config: แท่นอัญเชิญอยู่ใกล้บอสห้อง 1 เกิน (ห่าง {pedestalToBoss}) — ยืนกด E ที่แท่นแล้วอยู่ในระยะตีบอส`
		)
	end

	-- ══ แม่เดินไปมา ══
	assert(dim.Wander.Speed > 0, "Config: WANDER_SPEED ต้องมากกว่า 0")
	assert(dim.Wander.Tick > 0, "Config: WANDER_TICK ต้องมากกว่า 0")
	assert(dim.Player.WalkSpeed > 0, "Config: WALK_SPEED_REFERENCE ต้องมากกว่า 0")
	assert(
		dim.Wander.PauseMin >= 0 and dim.Wander.PauseMax >= dim.Wander.PauseMin,
		"Config: ช่วงเวลาหยุดพักของแม่กลับหัว (MAX ต้องไม่น้อยกว่า MIN)"
	)
	assert(Config.World.SYNC_INTERVAL > 0, "Config: SYNC_INTERVAL ต้องมากกว่า 0")
	assert(Config.World.REQUEST_COOLDOWN >= 0, "Config: REQUEST_COOLDOWN ติดลบไม่ได้")

	----------------------------------------------------------------------------
	-- ตาราง tier น้ำหนัก
	----------------------------------------------------------------------------
	-- ข้อที่สำคัญที่สุดคือผลรวม weight ต้องเท่ากับ TIER_ROLL_MAX พอดี
	-- ถ้าน้อยกว่า จะมีช่วงเลขที่สุ่มออกมาแล้วไม่ตรงกับ tier ไหนเลย
	-- เช็คทุกตารางที่กำหนดไว้ ไม่ใช่แค่ด่าน 1
	assert(StageWeightTiers[1] ~= nil, "Config: ต้องมีตาราง tier ของด่าน 1 เสมอ (ใช้เป็นค่าถอยกลับ)")
	for stageId, tiers in StageWeightTiers do
		assert(
			stageId >= 1 and stageId <= Config.Balance.Stage.COUNT and stageId % 1 == 0,
			`Config: StageWeightTiers มีด่าน {stageId} ที่อยู่นอกช่วง 1..{Config.Balance.Stage.COUNT}`
		)
		local total = 0
		for _, tier in tiers do
			total += tier.weight
		end
		assert(
			total == Config.Balance.Weight.TIER_ROLL_MAX,
			`Config: ตาราง tier ของด่าน {stageId} มีผลรวม weight = {total} แต่ต้องเป็น {Config.Balance.Weight.TIER_ROLL_MAX}`
		)
	end

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
		tierTotal == Config.Balance.Weight.TIER_ROLL_MAX,
		`Config: ผลรวม weight ของ tier = {tierTotal} แต่ TIER_ROLL_MAX = {Config.Balance.Weight.TIER_ROLL_MAX} (ต้องเท่ากันพอดี)`
	)
	assert(Config.Balance.Weight.CHILD_RATIO > 0 and Config.Balance.Weight.CHILD_RATIO < 1, "Config: CHILD_RATIO ต้องอยู่ระหว่าง 0 กับ 1")
	assert(
		Config.Balance.Weight.MAX_CHILD_RATIO >= Config.Balance.Weight.CHILD_RATIO and Config.Balance.Weight.MAX_CHILD_RATIO <= 1,
		"Config: MAX_CHILD_RATIO ต้องอยู่ระหว่าง CHILD_RATIO กับ 1"
	)

	----------------------------------------------------------------------------
	-- อัตราผลิต
	----------------------------------------------------------------------------
	local production = Config.Balance.Production
	assert(production.ONLINE_PER_MINUTE > 0, "Config: ONLINE_PER_MINUTE ต้องมากกว่า 0")
	assert(production.WEIGHT_REFERENCE > 0, "Config: WEIGHT_REFERENCE ต้องมากกว่า 0")
	assert(
		production.WEIGHT_EXPONENT > 0 and production.WEIGHT_EXPONENT < 1,
		"Config: WEIGHT_EXPONENT ของอัตราผลิตต้องอยู่ระหว่าง 0 กับ 1 (ต้องถดถอย)"
	)
	assert(
		production.OFFLINE_RATE_RATIO > 0 and production.OFFLINE_RATE_RATIO <= 1,
		"Config: OFFLINE_RATE_RATIO ต้องอยู่ระหว่าง 0 ถึง 1 — ออฟไลน์ห้ามเร็วกว่าออนไลน์"
	)
	assert(production.STACK_CAP > 0, "Config: STACK_CAP ต้องมากกว่า 0")
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

		-- ตัวคูณต้องไม่ทำให้ค่าติดลบหรือกลายเป็นศูนย์ และโบนัสน้ำหนักลูกต้องไม่ติดลบ
		assert(status.damageMultiplier > 0, `Config: status "{statusId}" มี damageMultiplier <= 0`)
		assert(status.coinMultiplier > 0, `Config: status "{statusId}" มี coinMultiplier <= 0`)
		assert(status.productionMultiplier > 0, `Config: status "{statusId}" มี productionMultiplier <= 0`)
		assert(status.childRatioBonus >= 0, `Config: status "{statusId}" มี childRatioBonus ติดลบ`)
	end

	-- ถ้าเปิดทุกสถานะพร้อมกัน น้ำหนักลูกต้องยังไม่เกินแม่
	local maxChildRatio = Config.Balance.Weight.CHILD_RATIO
	for _, status in Statuses do
		maxChildRatio += status.childRatioBonus
	end
	assert(
		maxChildRatio <= Config.Balance.Weight.MAX_CHILD_RATIO,
		`Config: ติดทุกสถานะพร้อมกันแล้วลูกหนัก {maxChildRatio * 100}% ของแม่ ซึ่งเกินเพดาน {Config.Balance.Weight.MAX_CHILD_RATIO * 100}%`
	)

	-- ตัวคั่นของ uid ต้องไม่ชนกับตัวคั่นของ stack key
	assert(#Config.Uid.SEPARATOR == 1, "Config: ตัวคั่นของ uid ต้องยาว 1 ตัวอักษร")
	assert(
		Config.Uid.SEPARATOR ~= fieldSep and Config.Uid.SEPARATOR ~= statusSep,
		"Config: ตัวคั่นของ uid ห้ามซ้ำกับตัวคั่นของ stack key"
	)

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

	for eggId, amount in Config.Balance.NewPlayer.startingEggs do
		assert(EggTypes[eggId] ~= nil, `Config: NewPlayer.startingEggs อ้างถึงไข่ "{eggId}" ที่ไม่มีอยู่`)
		assert(amount > 0, `Config: NewPlayer.startingEggs["{eggId}"] ต้องมากกว่า 0`)
	end
	assert(Config.Balance.NewPlayer.coins >= 0 and Config.Balance.NewPlayer.gems >= 0, "Config: ของเริ่มต้นติดลบไม่ได้")
	assert(
		Config.Balance.NewPlayer.speedLevel >= 0 and Config.Balance.NewPlayer.speedLevel <= Config.Balance.SpeedUpgrade.MAX_LEVEL,
		"Config: NewPlayer.speedLevel ต้องอยู่ในช่วง 0 ถึงเพดาน"
	)
	-- ⚠️ off-by-one ที่เคยพลาด: wallProgress = 0 ทำให้เพดาน upgrade damage เป็น 0
	-- ผู้เล่นใหม่จะซื้ออะไรไม่ได้เลยและตันตั้งแต่ด่านแรก
	assert(
		Config.Balance.NewPlayer.wallProgress >= 1 and Config.Balance.NewPlayer.wallProgress <= Config.Balance.Stage.COUNT,
		`Config: NewPlayer.wallProgress ({Config.Balance.NewPlayer.wallProgress}) ต้องอยู่ระหว่าง 1 ถึง {Config.Balance.Stage.COUNT}`
	)
	assert(
		Config.getMaxDamageLevel(Config.Balance.NewPlayer.wallProgress) > 0,
		"Config: ผู้เล่นใหม่ซื้อ upgrade damage ไม่ได้เลย — เช็ค wallProgress เริ่มต้น"
	)

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

	-- ดัชนี (UI-4): ลำดับตัวละครต้องครบทุกตัว ตัวละครละครั้งเดียว ไม่มีชื่อแปลกปลอม
	local ordered: { [string]: boolean } = {}
	for _, charId in Config.CharacterOrder do
		assert(Characters[charId] ~= nil, `Config: CharacterOrder มี "{charId}" ที่ไม่มีใน Characters`)
		assert(not ordered[charId], `Config: CharacterOrder มี "{charId}" ซ้ำ`)
		ordered[charId] = true
	end
	for charId in Characters do
		assert(ordered[charId], `Config: ตัวละคร "{charId}" ไม่อยู่ใน CharacterOrder — ดัชนีจะไม่แสดงตัวนี้`)
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
		if character.modelAssetId ~= nil then
			assert(
				character.modelAssetId > 0 and character.modelAssetId % 1 == 0,
				`Config: ตัวละคร "{charId}" มี modelAssetId ที่ไม่ใช่จำนวนเต็มบวก`
			)
		end
		if character.animationIds ~= nil then
			-- อนิเมชันเล่นบนกระดูกของโมเดล mesh — กล่องสีไม่มีกระดูกให้ขยับ
			assert(
				character.modelAssetId ~= nil,
				`Config: ตัวละคร "{charId}" มี animationIds แต่ไม่มี modelAssetId`
			)
			for pose, animationId in character.animationIds :: { [string]: number } do
				assert(
					pose == "walk" or pose == "idle" or pose == "sit" or pose == "punch",
					`Config: ตัวละคร "{charId}" มีท่า "{pose}" ที่ไม่รู้จัก (walk/idle/sit/punch เท่านั้น)`
				)
				assert(
					animationId > 0 and animationId % 1 == 0,
					`Config: ตัวละคร "{charId}" ท่า {pose} มี animation id ที่ไม่ใช่จำนวนเต็มบวก`
				)
			end
		end
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
	-- ไข่รายด่าน — บอสด่าน N ต้องมีไข่ของตัวเองครบทุกด่าน
	----------------------------------------------------------------------------
	-- ถ้าด่านไหนไม่มีไข่ ผู้เล่นที่ไปถึงด่านนั้นจะแย่งไข่ไม่ได้เลย = ตันถาวร
	local eggOfStage: { [number]: string } = {}
	for eggId, egg in EggTypes do
		if egg.stage ~= nil then
			local stageId = egg.stage :: number
			assert(
				stageId % 1 == 0 and stageId >= 1 and stageId <= Config.Balance.Stage.COUNT,
				`Config: ไข่ "{eggId}" ผูกกับด่าน {stageId} ที่อยู่นอกช่วง 1..{Config.Balance.Stage.COUNT}`
			)
			assert(
				egg.source == "boss",
				`Config: ไข่ "{eggId}" ผูกกับด่านแต่ source ไม่ใช่ "boss" — ไข่ที่ซื้อด้วย Robux ห้ามผูกด่าน`
			)
			assert(
				eggOfStage[stageId] == nil,
				`Config: ด่าน {stageId} มีไข่สองใบ ("{eggOfStage[stageId]}" กับ "{eggId}") — ต้องใบเดียวต่อด่าน`
			)
			eggOfStage[stageId] = eggId
		end
	end

	for stageId = 1, Config.Balance.Stage.COUNT do
		local eggId = Config.getBossEggId(stageId)
		local egg = EggTypes[eggId]
		assert(egg ~= nil, `Config: ด่าน {stageId} ไม่มีไข่ "{eggId}" — ผู้เล่นที่ไปถึงด่านนี้จะแย่งไข่ไม่ได้`)
		assert(
			(egg :: EggType).enabled,
			`Config: ไข่ของด่าน {stageId} ("{eggId}") ถูกปิดอยู่ — ด่านนั้นจะไม่มีไข่ให้แย่ง`
		)
		assert(
			eggOfStage[stageId] == eggId,
			`Config: getBossEggId({stageId}) คืน "{eggId}" แต่ไข่ที่ผูกด่าน {stageId} ไว้คือ "{tostring(eggOfStage[stageId])}"`
		)
	end

	-- ของที่แจกให้ผู้เล่นใหม่และไข่ default ต้องไม่ใช่ไข่ที่ปิดไปแล้ว
	assert(
		(EggTypes[Config.DEFAULT_EGG_ID] :: EggType).enabled,
		`Config: DEFAULT_EGG_ID ชี้ไปที่ไข่ "{Config.DEFAULT_EGG_ID}" ที่ถูกปิดอยู่`
	)
	for eggId in Config.Balance.NewPlayer.startingEggs do
		assert(
			(EggTypes[eggId] :: EggType).enabled,
			`Config: NewPlayer.startingEggs แจกไข่ "{eggId}" ที่ถูกปิดอยู่`
		)
	end

	----------------------------------------------------------------------------
	-- เศรษฐกิจ คอก กระเป๋า สวนฟัก
	----------------------------------------------------------------------------
	local economy = Config.Balance.Economy
	assert(economy.BASE_PER_MINUTE > 0, "Config: BASE_PER_MINUTE ต้องมากกว่า 0")
	assert(economy.REFERENCE_WEIGHT > 0, "Config: REFERENCE_WEIGHT ต้องมากกว่า 0")
	assert(economy.EXPONENT > 0 and economy.EXPONENT < 1, "Config: EXPONENT ของเงินต้องอยู่ระหว่าง 0 กับ 1 (ต้องถดถอย)")
	-- ตัวคูณเงินต่อด่านต้องไม่น้อยกว่าอัตราที่ด่านยากขึ้นจริง
	-- ไม่งั้นรายได้จะโตช้ากว่าความยาก แล้วผู้เล่นจะซื้อของขั้นสูงไม่ได้เลย
	-- ⚠️ ข้ามด่านที่ด่านก่อนหน้าไม่มีทหารเลย (ด่าน 1 ไม่มีกำแพง จึงเป็น 0)
	-- ไม่งั้นจะหารด้วยศูนย์แล้วได้ inf
	local steepestStageStep = 1
	for index = 2, #Stages do
		local previous = Stages[index - 1].defenders
		if previous > 0 then
			local step = Stages[index].defenders / previous
			if step > steepestStageStep then
				steepestStageStep = step
			end
		end
	end
	assert(
		economy.STAGE_MULTIPLIER >= steepestStageStep,
		`Config: ตัวคูณเงินต่อด่าน (×{economy.STAGE_MULTIPLIER}) น้อยกว่าอัตราที่ด่านยากขึ้นสูงสุด (×{steepestStageStep}) — ผู้เล่นจะซื้อของขั้นสูงไม่ได้`
	)
	assert(economy.SELL_MOTHER_MINUTES > 0, "Config: SELL_MOTHER_MINUTES ต้องมากกว่า 0")

	assert(Config.Balance.Pen.BASE_CAPACITY > 0, "Config: BASE_CAPACITY ของคอกต้องมากกว่า 0")
	assert(Config.Balance.Pen.MAX_LEVEL >= 1, "Config: MAX_LEVEL ของคอกต้องอย่างน้อย 1")
	assert(Config.Balance.Pen.UPGRADE_COST_MULTIPLIER > 1, "Config: ตัวคูณราคาคอกต้องมากกว่า 1")
	assert(Config.Balance.Bag.CAPACITY > 0, "Config: ความจุกระเป๋าต้องมากกว่า 0")
	-- ⚠️ สองค่านี้แยกกันโดยตั้งใจ ไม่ต้องเท่ากัน แต่ต้องมีจริงทั้งคู่
	-- ค่าใดค่าหนึ่งเป็น 0 = ไข่เดินทางต่อไม่ได้ ผู้เล่นตันถาวรตั้งแต่ฟองแรก
	assert(
		Config.Balance.Hatchery.BAG_CAPACITY > 0 and Config.Balance.Hatchery.BAG_CAPACITY % 1 == 0,
		"Config: Hatchery.BAG_CAPACITY (กระเป๋าไข่) ต้องเป็นจำนวนเต็มบวก"
	)
	assert(
		Config.Balance.Hatchery.MAX_SLOTS > 0 and Config.Balance.Hatchery.MAX_SLOTS % 1 == 0,
		"Config: Hatchery.MAX_SLOTS (ช่องฟัก) ต้องเป็นจำนวนเต็มบวก"
	)
	assert(
		Config.Inventory.MAX_MOTHERS >= Config.Balance.Bag.CAPACITY + Config.getPenCapacity(Config.Balance.Pen.MAX_LEVEL),
		"Config: MAX_MOTHERS น้อยกว่ากระเป๋า + คอกเต็มเลเวล ผู้เล่นจะเก็บของที่ควรเก็บได้ไม่ครบ"
	)

	----------------------------------------------------------------------------
	-- ด่าน บอส อาวุธ
	----------------------------------------------------------------------------
	local stage = Config.Balance.Stage
	assert(stage.COUNT > 0, "Config: จำนวนด่านต้องมากกว่า 0")
	assert(stage.DEFENDER_HP > 0 and stage.DEFENDER_DAMAGE > 0, "Config: HP/damage ของทหารฝ่ายรับต้องมากกว่า 0")

	-- ตารางด่านต้องครบทุกด่าน เรียงตาม id และยากขึ้นเรื่อย ๆ
	assert(#Stages == stage.COUNT, `Config: ตารางด่านมี {#Stages} แถว แต่ COUNT = {stage.COUNT}`)
	-- ด่าน 1 เป็นด่านเริ่มต้น ต้องไม่มีกำแพงและไม่มีทหารฝ่ายรับ
	-- ไม่งั้นผู้เล่นใหม่จะติดกับดักไก่กับไข่: ต้องมีแม่ถึงจะมีกองทัพ ต้องมีไข่ถึงจะมีแม่
	assert(Stages[1].defenders == 0, "Config: ด่าน 1 ต้องไม่มีทหารฝ่ายรับ (ผู้เล่นใหม่ต้องเดินไปหาบอสได้เลย)")
	assert(Config.getStageTotalHp(1) == 0, "Config: ด่าน 1 ต้องไม่มีกำแพงให้ตี")

	local previousDefenders = -1
	for index, def in Stages do
		assert(def.id == index, `Config: ตารางด่านแถวที่ {index} มี id = {def.id} (ต้องตรงกับลำดับ)`)
		assert(def.defenders >= 0, `Config: ด่าน {def.id} มีทหารฝ่ายรับติดลบ`)
		assert(
			def.defenders > previousDefenders,
			`Config: ด่าน {def.id} มีทหารน้อยกว่าหรือเท่าด่านก่อนหน้า — ด่านต้องยากขึ้นเรื่อย ๆ`
		)
		previousDefenders = def.defenders
	end
	assert(stage.WALL_HP_RATIO > 0, "Config: WALL_HP_RATIO ต้องมากกว่า 0")
	assert(
		stage.DISPLAY_MODELS_MIN > 0 and stage.DISPLAY_MODELS_MIN <= stage.DISPLAY_MODELS_MAX,
		"Config: ช่วงจำนวนโมเดลที่แสดงไม่ถูกต้อง"
	)

	-- (5B: ค่ารีเกิด/จำนวนไข่/เวลากดค้างของ Balance.Boss เดิมย้ายไป BossCycle แล้ว — ตรวจในบล็อกลานบอสข้างบน)

	-- ══ 5C: กระบอง 10 ขั้น ══ ตารางคำนวณจาก HP บอส/คูลดาวน์/รายได้ — ตรวจผลทุกขั้นตรงนี้
	do
		local weapon = Config.Balance.Weapon
		local cycle = Config.Balance.BossCycle
		for key, replacement in REMOVED_WEAPON_KEYS do
			assert(
				(weapon :: any)[key] == nil,
				`Config: Balance.Weapon.{key} ลบแล้วใน 5C (สูตรอาวุธเดิม ×10) — ใช้ {replacement} แทน ห้ามเติมกลับ`
			)
		end
		assert(
			weapon.MAX_LEVEL == stage.COUNT + 1,
			`Config: กระบองต้องมี {stage.COUNT + 1} ขั้น (ขั้นละห้องบอส + ขั้นพิเศษ 1) — ได้ {weapon.MAX_LEVEL}`
		)
		assert(weapon.START_TIER == 1, "Config: กระบองขั้นเริ่มต้นต้องเป็น 1 (ผู้เล่นใหม่ได้ฟรี · PlayerData ตั้ง weaponLevel = 1)")
		assert(#Config.ClubVisuals == weapon.MAX_LEVEL, `Config: ClubVisuals ต้องมีครบ {weapon.MAX_LEVEL} ขั้น (มี {#Config.ClubVisuals})`)
		assert(
			weapon.TARGET_SOLO_KILL_SECONDS > 0 and weapon.TARGET_SOLO_KILL_SECONDS <= cycle.DAY_SECONDS,
			"Config: TARGET_SOLO_KILL_SECONDS ต้อง > 0 และไม่เกินกลางวัน (ไม่งั้นติดล็อกอัญเชิญ)"
		)
		assert(
			weapon.CAPSTONE_SOLO_KILL_SECONDS > 0 and weapon.CAPSTONE_SOLO_KILL_SECONDS < weapon.TARGET_SOLO_KILL_SECONDS,
			"Config: CAPSTONE_SOLO_KILL_SECONDS ต้องเร็วกว่า TARGET_SOLO_KILL_SECONDS (ขั้นพิเศษต้องตีห้องสุดท้ายเร็วขึ้น)"
		)
		assert(weapon.PRICE_INCOME_MINUTES > 0, "Config: PRICE_INCOME_MINUTES ต้องมากกว่า 0")
		assert(
			weapon.CAPSTONE_PRICE_INCOME_MINUTES > weapon.PRICE_INCOME_MINUTES,
			"Config: ขั้นพิเศษต้องแพงกว่าขั้นปกติ (CAPSTONE_PRICE_INCOME_MINUTES > PRICE_INCOME_MINUTES)"
		)
		assert(Config.getClubPrice(weapon.START_TIER) == 0, "Config: กระบองขั้นเริ่มต้นต้องฟรี")
		for tier = 1, weapon.MAX_LEVEL do
			local damage = Config.getClubDamage(tier)
			local visual = Config.ClubVisuals[tier]
			assert(
				damage >= 1 and damage % 1 == 0 and damage >= Config.Balance.Economy.BOSS_REWARD_MIN_DAMAGE,
				`Config: ดาเมจกระบองขั้น {tier} ต้องเป็นจำนวนเต็ม ≥ 1 (ได้ {damage})`
			)
			assert(type(visual.name) == "string" and visual.name ~= "", `Config: กระบองขั้น {tier} ไม่มีชื่อ`)
			if tier > 1 then
				assert(damage > Config.getClubDamage(tier - 1), `Config: ดาเมจกระบองขั้น {tier} ต้องมากกว่าขั้น {tier - 1}`)
				local price = Config.getClubPrice(tier)
				assert(price > 0 and price % 1 == 0, `Config: ราคากระบองขั้น {tier} ต้องเป็นจำนวนเต็มบวก (ได้ {price})`)
				assert(price > Config.getClubPrice(tier - 1), `Config: ราคากระบองขั้น {tier} ต้องแพงกว่าขั้น {tier - 1}`)
			end
		end
		-- ⚠️ หัวใจของ 5C: ขั้น N ตีบอสห้อง N คนเดียวตาย**ภายในกลางวัน** — ไม่งั้นพังกำแพง N ขณะบอสอยู่ = ติดล็อกถาวร
		for room = 1, stage.COUNT do
			local seconds = Config.getClubSoloKillSeconds(room, room)
			assert(
				seconds <= weapon.TARGET_SOLO_KILL_SECONDS and seconds <= cycle.DAY_SECONDS,
				`Config: กระบองขั้น {room} ตีบอสห้อง {room} คนเดียว {seconds} วิ เกินเป้า {weapon.TARGET_SOLO_KILL_SECONDS} วิ `
					.. `/ กลางวัน {cycle.DAY_SECONDS} วิ — ติดล็อกอัญเชิญ`
			)
		end
		-- ขั้นพิเศษตีห้องสุดท้ายเร็วกว่าขั้นก่อนหน้า**ชัดเจน** (อย่างน้อยครึ่งหนึ่งของเวลาเดิม)
		local capstone = Config.getClubSoloKillSeconds(weapon.MAX_LEVEL, stage.COUNT)
		local previous = Config.getClubSoloKillSeconds(weapon.MAX_LEVEL - 1, stage.COUNT)
		assert(
			capstone <= weapon.CAPSTONE_SOLO_KILL_SECONDS and capstone * 2 <= previous,
			`Config: กระบองขั้นพิเศษตีห้อง {stage.COUNT} {capstone} วิ ไม่เร็วกว่าขั้นก่อน ({previous} วิ) ชัดเจนพอ`
		)
	end

	----------------------------------------------------------------------------
	-- แหล่งที่มาของไข่ + Developer Product
	----------------------------------------------------------------------------
	for eggId, egg in EggTypes do
		assert(
			egg.source == "boss" or egg.source == "robux",
			`Config: ไข่ "{eggId}" มี source = "{egg.source}" ที่ไม่รู้จัก (ต้องเป็น "boss" หรือ "robux")`
		)
	end

	-- guaranteedTier ต้องชี้ไปที่ tier ที่มีอยู่จริง
	for eggId, egg in EggTypes do
		if egg.guaranteedTier ~= nil then
			local tier = egg.guaranteedTier :: number
			assert(
				tier >= 1 and tier <= #WeightTiers and tier % 1 == 0,
				`Config: ไข่ "{eggId}" รับประกัน tier {tier} ซึ่งอยู่นอกช่วง 1..{#WeightTiers}`
			)
		end
	end

	-- SS ต้องออกได้จากไข่ที่จ่ายเงินจริงเท่านั้น
	-- ถ้าไข่จากบอสให้ SS ได้เมื่อไหร่ ไข่ตำนานจะขายไม่ออกทันที
	for eggId, pool in EggCharacterPools do
		local egg = EggTypes[eggId]
		if egg and egg.source == "boss" then
			for _, entry in pool do
				assert(
					entry.class ~= "SS",
					`Config: ไข่ "{eggId}" มาจากบอสแต่ออกคลาส SS ได้ — SS ต้องมาจากไข่ Robux เท่านั้น`
				)
			end
		end
	end

	local seenProductId: { [number]: string } = {}
	for productKey, product in DeveloperProducts do
		assert(product.id == productKey, `Config: DeveloperProducts["{productKey}"].id ไม่ตรงกับคีย์`)
		assert(product.grantAmount > 0, `Config: product "{productKey}" ให้ของ <= 0 ชิ้น`)

		local egg = EggTypes[product.grantEggId]
		assert(egg ~= nil, `Config: product "{productKey}" ให้ไข่ "{product.grantEggId}" ที่ไม่มีอยู่`)
		assert(
			(egg :: EggType).source == "robux",
			`Config: product "{productKey}" ให้ไข่ "{product.grantEggId}" ที่ source ไม่ใช่ "robux"`
		)

		if product.enabled then
			-- เปิดขายแล้วต้องมีเลข productId จริง ไม่งั้น ProcessReceipt จะจับคู่ไม่ได้
			assert(
				product.productId > 0,
				`Config: product "{productKey}" เปิดขายแล้วแต่ productId ยังเป็น 0 — ต้องใส่เลขจาก Creator Dashboard ก่อน`
			)
			local owner = seenProductId[product.productId]
			assert(
				owner == nil,
				`Config: productId {product.productId} ถูกใช้ทั้งใน "{owner}" และ "{productKey}"`
			)
			seenProductId[product.productId] = productKey
		end
	end

	-- ⚠️ UI-5: RobuxProducts ใช้ productId namespace **เดียวกัน** กับ DeveloperProducts ข้างบน
	-- (seenProductId ตัวเดียวกัน) เพราะ ProcessReceipt รับ productId มาเป็นเลขเดียว ไม่บอกว่ามาจาก
	-- ตารางไหน — ถ้าเผลอตั้งเลขชนกันข้ามสองตาราง ProcessReceipt จะจับคู่สินค้าผิดชนิด
	local validKinds = { damage_bonus = true, speed_bonus = true, hatch_rush = true }
	for productKey, product in RobuxProducts do
		assert(product.id == productKey, `Config: RobuxProducts["{productKey}"].id ไม่ตรงกับคีย์`)
		assert(product.amount > 0, `Config: RobuxProducts["{productKey}"] มี amount <= 0`)
		assert(validKinds[product.kind], `Config: RobuxProducts["{productKey}"].kind "{product.kind}" ไม่รู้จัก`)

		if product.enabled then
			assert(
				product.productId > 0,
				`Config: RobuxProducts["{productKey}"] เปิดขายแล้วแต่ productId ยังเป็น 0 — ต้องใส่เลขจาก Creator Dashboard ก่อน`
			)
			local owner = seenProductId[product.productId]
			assert(
				owner == nil,
				`Config: productId {product.productId} ถูกใช้ทั้งใน "{owner}" และ "{productKey}"`
			)
			seenProductId[product.productId] = productKey
		end
	end

	-- ⚠️ UI-5: โบนัสความเร็ว Robux ต้องมี "ที่ว่างจริง" เหนือเพดานแทร็กปกติ (128) ไม่งั้นซื้อไปก็ไม่ได้อะไร
	-- และต้องไม่มีทางเกิน SPEED_CEILING (200) ที่เป็นเพดานทางฟิสิกส์ของทั้งเกม
	local robuxSpeedCap = Config.getRobuxSpeedHardCap()
	assert(
		robuxSpeedCap > Config.getMaxWalkSpeed(),
		`Config: getRobuxSpeedHardCap() ({robuxSpeedCap}) ต้องมากกว่าเพดานแทร็กปกติ ({Config.getMaxWalkSpeed()}) ไม่งั้นซื้อ robux_speed_step ไปก็ไม่มีผล`
	)
	assert(
		robuxSpeedCap <= Config.Balance.SpeedUpgrade.SPEED_CEILING,
		`Config: getRobuxSpeedHardCap() ({robuxSpeedCap}) เกิน SPEED_CEILING ({Config.Balance.SpeedUpgrade.SPEED_CEILING}) — วิ่งทะลุกำแพงได้`
	)

	-- ⚠️ ตัดขั้นบนของคอก/upgrade ผลิตแล้ว ต้องไม่ตัดจนผู้เล่นอ้างอิงใช้ไม่พอ
	assert(
		Config.Balance.Pen.MAX_LEVEL >= Config.Balance.Stage.COUNT,
		`Config: เพดานคอก ({Config.Balance.Pen.MAX_LEVEL}) ต่ำกว่าจำนวนด่าน ({Config.Balance.Stage.COUNT}) `
			.. `— ผู้เล่นอ้างอิงที่ด่าน N ใช้คอกเลเวล N จะขยายไม่พอ`
	)
	-- upgrade อัตราผลิตตัดได้ลึกกว่า เพราะตั้งแต่ด่าน 3 คอขวดเป็นการปล่อยอยู่แล้ว
	-- แต่ต้องยังผลิตได้ "ไม่ต่ำกว่าอัตราปล่อย" ทุกด่านที่คอขวดเป็นการปล่อย
	-- ไม่งั้นการตัดขั้นจะไปเปลี่ยนเวลาตีโดยไม่ตั้งใจ
	for capStage = 1, Config.Balance.Stage.COUNT do
		local produced = Config.getPenCapacity(capStage)
			* Config.getProductionPerMinute(Config.Balance.BalanceCheck.REFERENCE_WEIGHT[capStage], nil, capStage - 1, true)
			/ 60
		local release = Config.getReleaseRate(capStage)
		assert(
			produced >= release or capStage <= 2,
			`Config: ด่าน {capStage} ผลิตได้ {string.format("%.2f", produced)} ตัว/วิ แต่ปล่อยได้ {release} `
				.. `— ตัดขั้น upgrade อัตราผลิตลึกเกินไป คอขวดย้อนกลับไปเป็นการผลิต`
		)
	end

	----------------------------------------------------------------------------
	-- upgrade อัตราผลิต
	----------------------------------------------------------------------------
	assert(production.UPGRADE_MAX_LEVEL > 0, "Config: UPGRADE_MAX_LEVEL ของอัตราผลิตต้องมากกว่า 0")
	assert(production.UPGRADE_RATE_MULTIPLIER > 1, "Config: UPGRADE_RATE_MULTIPLIER ต้องมากกว่า 1")
	assert(
		production.UPGRADE_RATE_MULTIPLIER <= production.UPGRADE_COST_MULTIPLIER,
		"Config: ผลของ upgrade ต่อขั้นไม่ควรมากกว่าราคาที่จ่ายต่อขั้น ไม่งั้นกำแพงจะหมดความหมายช่วงท้ายเกม"
	)
	local store = Config.DataStore
	assert(store.AUTOSAVE_INTERVAL >= 10, "Config: AUTOSAVE_INTERVAL ถี่เกินไป เสี่ยงโดน throttle")

	-- ⚠️ เซฟห่างเกิน 5 นาที = ผู้เล่นที่เน็ตหลุดเสียงานได้ถึง 5 นาที
	-- และยาวกว่าอายุ session lock ด้วย ซึ่งแปลว่า lock จะหมดอายุก่อนถูกต่อ
	assert(
		store.AUTOSAVE_INTERVAL < 300,
		`Config: AUTOSAVE_INTERVAL = {store.AUTOSAVE_INTERVAL} ห่างเกินไป (ต้องน้อยกว่า 300 วินาที)`
	)

	-- ⚠️ lock ต้องอายุยาวกว่ารอบ autosave ที่เลื่อนช้าสุด ไม่งั้น lock ของคนที่ยังเล่นอยู่
	-- จะหมดอายุระหว่างรอรอบเซฟถัดไป แล้วคนอื่นแย่งเข้าไปทับข้อมูลได้
	local slowestSaveGap = store.AUTOSAVE_INTERVAL + store.AUTOSAVE_STAGGER * Config.World.MAX_PENS
	assert(
		store.SESSION_LOCK_SECONDS > slowestSaveGap,
		`Config: SESSION_LOCK_SECONDS ({store.SESSION_LOCK_SECONDS}) ต้องยาวกว่ารอบเซฟที่ช้าสุด ({slowestSaveGap})`
	)

	-- ⚠️ stagger ของผู้เล่นคนสุดท้ายต้องไม่ยาวจนข้ามรอบ autosave ไปทั้งรอบ
	-- คนที่ 1 เลื่อน 0 วิ · คนที่ 6 เลื่อน (6-1) × 10 = 50 วิ ซึ่งยังอยู่ในรอบ 60 วิ
	-- ⚠️ ใช้ (index - 1) ไม่ใช่ index ตรง ๆ — ถ้าใช้ index คนที่ 6 จะเลื่อน 60 วิพอดี
	-- = ข้ามไปชนรอบถัดไป แล้วเขาจะเซฟห่างกว่าคนอื่นหนึ่งรอบเต็มตลอดไป
	local lastOffset = store.AUTOSAVE_STAGGER * (Config.World.MAX_PENS - 1)
	assert(
		lastOffset < store.AUTOSAVE_INTERVAL,
		`Config: คนสุดท้ายถูกเลื่อนเซฟ {lastOffset} วิ ซึ่งไม่น้อยกว่า AUTOSAVE_INTERVAL `
			.. `({store.AUTOSAVE_INTERVAL}) — เขาจะถูกข้ามไปรอบถัดไปตลอด`
	)

	assert(store.RETRY_COUNT >= 1 and store.RETRY_COUNT % 1 == 0, "Config: RETRY_COUNT ต้องเป็นจำนวนเต็มตั้งแต่ 1")
	assert(store.RETRY_BASE_DELAY > 0, "Config: RETRY_BASE_DELAY ต้องมากกว่า 0")

	-- ⚠️ Roblox ตัดเซิร์ฟที่ 30 วินาทีหลัง BindToClose · retry ทั้งชุดต้องจบก่อนนั้น
	-- เวลารวมของ backoff = BASE × (2^COUNT - 2)  (ครั้งแรกยิงทันที ไม่หน่วง)
	local backoffTotal = store.RETRY_BASE_DELAY * (2 ^ store.RETRY_COUNT - 2)
	assert(
		backoffTotal < store.BIND_TO_CLOSE_SECONDS,
		`Config: หน่วง retry รวม {backoffTotal} วิ ยาวกว่างบตอนปิดเซิร์ฟ ({store.BIND_TO_CLOSE_SECONDS} วิ) — `
			.. `เซฟรอบสุดท้ายจะถูกตัดกลางคัน`
	)
	assert(
		store.BIND_TO_CLOSE_SECONDS < 30,
		"Config: BIND_TO_CLOSE_SECONDS ต้องน้อยกว่า 30 — Roblox ปิดเซิร์ฟทิ้งที่ 30 วินาที"
	)
	assert(store.MAX_PLAYER_DATA_BYTES < 4 * 1024 * 1024, "Config: MAX_PLAYER_DATA_BYTES ต้องต่ำกว่าลิมิตจริง 4 MB")
	assert(store.PROCESSED_PURCHASE_LOG_CAP > 0, "Config: PROCESSED_PURCHASE_LOG_CAP ต้องมากกว่า 0")

	-- ⚠️ เวลารอรอบเซฟก่อนหน้าต้องสั้นกว่างบตอนปิดเซิร์ฟ
	-- ไม่งั้นเซฟรอบสุดท้ายจะหมดเวลาไปกับการรอ แล้วไม่ได้เขียนอะไรเลย
	assert(
		store.SAVE_WAIT_LIMIT < store.BIND_TO_CLOSE_SECONDS,
		`Config: SAVE_WAIT_LIMIT ({store.SAVE_WAIT_LIMIT}) ต้องสั้นกว่า BIND_TO_CLOSE_SECONDS ({store.BIND_TO_CLOSE_SECONDS})`
	)
	assert(
		store.SAVE_WAIT_STEP > 0 and store.SAVE_WAIT_STEP < store.SAVE_WAIT_LIMIT,
		"Config: SAVE_WAIT_STEP ต้องมากกว่า 0 และสั้นกว่า SAVE_WAIT_LIMIT"
	)

	-- ⚠️ กระเป๋าไข่ต้องจุไม่น้อยกว่าสวนฟัก
	-- ไข่ต้องผ่านกระเป๋าก่อนเข้าสวนเสมอ ถ้ากระเป๋าเล็กกว่า จะมีช่องในสวนที่เติมไม่ได้ตลอดกาล
	assert(
		Config.Balance.Hatchery.BAG_CAPACITY >= Config.Balance.Hatchery.MAX_SLOTS,
		`Config: BAG_CAPACITY ({Config.Balance.Hatchery.BAG_CAPACITY}) ต้องไม่น้อยกว่า `
			.. `MAX_SLOTS ({Config.Balance.Hatchery.MAX_SLOTS}) — ไข่ต้องผ่านกระเป๋าก่อนเข้าสวนฟัก`
	)
	assert(Config.SCHEMA_VERSION >= 1 and Config.SCHEMA_VERSION % 1 == 0, "Config: SCHEMA_VERSION ต้องเป็นจำนวนเต็มตั้งแต่ 1")

	----------------------------------------------------------------------------
	-- ตัวคูณ damage ตามด่าน
	----------------------------------------------------------------------------

	-- อัตราปล่อยทหาร
	local combat = Config.Balance.Combat
	assert(
		#combat.RELEASE_PER_SECOND == Config.Balance.Stage.COUNT,
		`Config: ตารางอัตราปล่อยมี {#combat.RELEASE_PER_SECOND} แถว แต่มี {Config.Balance.Stage.COUNT} ด่าน`
	)
	local previousRate = 0
	for index, rate in combat.RELEASE_PER_SECOND do
		assert(rate > 0, `Config: อัตราปล่อยของด่าน {index} ต้องมากกว่า 0`)
		assert(rate >= previousRate, `Config: อัตราปล่อยของด่าน {index} น้อยกว่าด่านก่อนหน้า — ต้องเร่งขึ้นหรือเท่าเดิม`)
		previousRate = rate
	end
	assert(combat.AUTO_PAUSE_AFTER_UNITS > 0, "Config: AUTO_PAUSE_AFTER_UNITS ต้องมากกว่า 0")
	assert(combat.MAX_VISIBLE_UNITS > 0, "Config: MAX_VISIBLE_UNITS ต้องมากกว่า 0")
	assert(combat.WALK_SECONDS_TO_WALL > 0, "Config: WALK_SECONDS_TO_WALL ต้องมากกว่า 0")
	-- ⚠️ กติกาที่ห้ามพลิก: ระบบห้ามปล่อยตัวแม่เอง และห้ามเลือกแม่จากคอก
	assert(
		combat.ALLOW_AUTO_RELEASE_MOTHERS == false,
		"Config: ห้ามเปิด auto ปล่อยตัวแม่ — แม่ตายถาวร ผู้เล่นต้องกดเองพร้อมกล่องยืนยันเท่านั้น"
	)
	assert(
		combat.MOTHERS_SELECTABLE_FROM_PEN == false,
		"Config: ห้ามให้เลือกแม่จากคอกลงสนาม — เลือกได้เฉพาะแม่ในกระเป๋า กันเผลอส่งเครื่องผลิตไปตาย"
	)
	assert(
		combat.MAX_BATTLE_MOTHERS > 0 and combat.MAX_BATTLE_MOTHERS % 1 == 0,
		"Config: MAX_BATTLE_MOTHERS ต้องเป็นจำนวนเต็มบวก"
	)
	-- รางวัลผ่านด่าน: ครบทุกด่าน · จำนวนเต็ม ≥ 0 · ด่านที่ไม่มีอะไรให้ตี (HP รวม 0) ต้องเป็น 0
	-- (ด่านแบบนั้น "พัง" ฟรีตั้งแต่ตาแรก ไม่มีกำแพงให้พังจริง จึงไม่มีรางวัล)
	assert(
		#combat.STAGE_CLEAR_BONUS_EGGS == Config.Balance.Stage.COUNT,
		`Config: STAGE_CLEAR_BONUS_EGGS มี {#combat.STAGE_CLEAR_BONUS_EGGS} ช่อง แต่มี {Config.Balance.Stage.COUNT} ด่าน`
	)
	for bonusStage, eggs in combat.STAGE_CLEAR_BONUS_EGGS do
		assert(eggs >= 0 and eggs % 1 == 0, `Config: STAGE_CLEAR_BONUS_EGGS ด่าน {bonusStage} ต้องเป็นจำนวนเต็ม ≥ 0`)
		if Config.getStageTotalHp(bonusStage) <= 0 then
			assert(eggs == 0, `Config: ด่าน {bonusStage} ไม่มีกำแพง/ทหารให้พัง — STAGE_CLEAR_BONUS_EGGS ต้องเป็น 0`)
		end
	end
	----------------------------------------------------------------------------
	-- ตัวคูณ damage ที่ซื้อด้วยเงิน
	----------------------------------------------------------------------------
	local check = Config.Balance.BalanceCheck
	local upgrade = Config.Balance.DamageUpgrade
	assert(upgrade.STEP_MULTIPLIER > 1, "Config: STEP_MULTIPLIER ของ upgrade damage ต้องมากกว่า 1")
	assert(
		upgrade.STEPS_PER_STAGE >= 1 and upgrade.STEPS_PER_STAGE % 1 == 0,
		"Config: STEPS_PER_STAGE ต้องเป็นจำนวนเต็มบวก"
	)
	assert(
		upgrade.MAX_LEVEL == upgrade.STEPS_PER_STAGE * Config.Balance.Stage.COUNT,
		`Config: MAX_LEVEL ({upgrade.MAX_LEVEL}) ต้องเท่ากับ STEPS_PER_STAGE × จำนวนด่าน `
			.. `({upgrade.STEPS_PER_STAGE} × {Config.Balance.Stage.COUNT} = {upgrade.STEPS_PER_STAGE * Config.Balance.Stage.COUNT})`
	)
	assert(upgrade.COST_MULTIPLIER_IN_STAGE >= 1, "Config: COST_MULTIPLIER_IN_STAGE ต้องไม่น้อยกว่า 1")
	assert(
		#upgrade.STAGE_COST_BASE == Config.Balance.Stage.COUNT,
		`Config: STAGE_COST_BASE มี {#upgrade.STAGE_COST_BASE} ด่าน แต่เกมมี {Config.Balance.Stage.COUNT} ด่าน`
	)

	-- ⚠️ off-by-one: ผู้เล่นใหม่ที่ด่าน 1 ต้องซื้อได้ทันที ไม่ใช่ตันตั้งแต่ต้นเกม
	assert(
		Config.getMaxDamageLevel(1) == upgrade.STEPS_PER_STAGE,
		`Config: เพดาน upgrade ที่ด่าน 1 ต้องเป็น {upgrade.STEPS_PER_STAGE} ขั้น แต่ได้ {Config.getMaxDamageLevel(1)} `
			.. `— น่าจะพลาด off-by-one (ใช้ wallProgress - 1 แทน wallProgress) ผู้เล่นใหม่จะซื้ออะไรไม่ได้เลย`
	)
	assert(
		Config.getMaxDamageLevel(Config.Balance.Stage.COUNT) == upgrade.MAX_LEVEL,
		"Config: เพดานที่ด่านสุดท้ายต้องพอดีกับ MAX_LEVEL"
	)
	assert(Config.getArmyDamageMultiplier(0) == 1, "Config: ยังไม่ซื้อ upgrade ต้องได้ตัวคูณ 1 พอดี")
	assert(Config.getDamageUpgradeCost(0) == nil, "Config: ขั้น 0 ต้องไม่มีราคา")
	assert(
		Config.getDamageUpgradeCost(upgrade.MAX_LEVEL + 1) == nil,
		"Config: ขั้นที่เกินเพดานต้องคืน nil ไม่ใช่ราคา"
	)

	-- ราคาต้องไล่ขึ้นตลอดทั้ง 72 ขั้น ไม่มีช่วงที่ถูกลง
	local previousCost = 0
	for level = 1, upgrade.MAX_LEVEL do
		local cost = Config.getDamageUpgradeCost(level)
		assert(cost ~= nil and (cost :: number) > 0, `Config: ขั้น {level} ไม่มีราคา`)
		assert(
			(cost :: number) >= previousCost,
			`Config: ราคาขั้น {level} ({cost}) ถูกกว่าขั้นก่อนหน้า ({previousCost}) — ราคาต้องไล่ขึ้นตลอด`
		)
		previousCost = cost :: number
	end

	-- ⚠️ ยามที่เป็นหัวใจของรอบนี้: ราคาต้องดูดเงินส่วนเกินให้หมดจริง
	-- ถูกเกินไป = เงินยังล้นเหมือนเดิม upgrade ไม่ได้เป็นบ่อเงินจริง
	-- แพงเกินไป = ผู้เล่นซื้อไม่ไหว แล้วตันเพราะ damage ไม่พอ
	for upgradeStage = 1, Config.Balance.Stage.COUNT do
		local stageTotal = Config.getStageDamageUpgradeTotal(upgradeStage)
		local stageIncome = Config.getReferenceStageIncome(upgradeStage)
		assert(stageIncome > 0, `Config: คำนวณรายได้ของด่าน {upgradeStage} ได้ 0`)

		local share = stageTotal / stageIncome
		assert(
			share >= check.MIN_UPGRADE_SHARE and share <= check.MAX_UPGRADE_SHARE,
			`Config: ราคา upgrade damage ของด่าน {upgradeStage} คิดเป็น {string.format("%.0f", share * 100)}% ของรายได้ด่านนั้น `
				.. `(ต้องอยู่ {check.MIN_UPGRADE_SHARE * 100}–{check.MAX_UPGRADE_SHARE * 100}%) `
				.. `— ถูกไปเงินจะล้นเหมือนเดิม แพงไปผู้เล่นจะตัน ปรับ DamageUpgrade.STAGE_COST_BASE[{upgradeStage}]`
		)
	end

	assert(
		#Config.Balance.BalanceCheck.REFERENCE_WEIGHT == Config.Balance.Stage.COUNT
			and #Config.Balance.BalanceCheck.REFERENCE_CLASS == Config.Balance.Stage.COUNT,
		"Config: ตารางอ้างอิงของ BalanceCheck ต้องมีครบทุกด่าน"
	)
	assert(
		Config.Balance.BalanceCheck.MIN_HOURS_PER_STAGE < Config.Balance.BalanceCheck.MAX_HOURS_PER_STAGE,
		"Config: ช่วงเวลาที่ยอมรับได้ของ BalanceCheck กลับหัว"
	)
	assert(
		Config.Balance.BalanceCheck.TURRET_TOLL_CEILING > 0 and Config.Balance.BalanceCheck.TURRET_TOLL_CEILING < 1,
		"Config: TURRET_TOLL_CEILING ต้องอยู่ระหว่าง 0 กับ 1 (เป็นสัดส่วนของกำลังพล)"
	)
	assert(
		Config.Balance.BalanceCheck.MAX_FARM_TO_CLEAR_RATIO > 0,
		"Config: MAX_FARM_TO_CLEAR_RATIO ต้องมากกว่า 0"
	)
	assert(
		Config.Balance.BalanceCheck.PLAYERS_PER_SERVER > 0,
		"Config: PLAYERS_PER_SERVER ต้องมากกว่า 0"
	)

	----------------------------------------------------------------------------
	-- ตัวคูณคลาส — กัน pay-to-win
	----------------------------------------------------------------------------
	-- SS ออกจากไข่ Robux เท่านั้น ถ้าปล่อยให้ห่างจาก S มาก ๆ คนจ่ายเงินจะชนะขาด
	-- เพดานนี้คือสิ่งเดียวที่กันไม่ให้ใครมาไล่ ×6 ต่อจาก S เป็น 1,296 ทีหลัง
	local ssMultiplier = CharacterClasses.SS.multiplier
	local sMultiplier = CharacterClasses.S.multiplier
	assert(sMultiplier > 0, "Config: ตัวคูณคลาส S ต้องมากกว่า 0")
	assert(
		ssMultiplier / sMultiplier <= Config.Balance.BalanceCheck.MAX_SS_OVER_S_RATIO,
		`Config: คลาส SS แรงกว่า S อยู่ {string.format("%.2f", ssMultiplier / sMultiplier)} เท่า `
			.. `(เพดาน {Config.Balance.BalanceCheck.MAX_SS_OVER_S_RATIO}) — SS ออกจากไข่ Robux เท่านั้น `
			.. `ปล่อยให้ห่างกว่านี้ = pay-to-win`
	)

	-- คลาสต้องเรียงจากแรงมากไปน้อยตาม order ไม่งั้นตาราง UI กับสมดุลจะขัดกันเอง
	local byOrder: { CharacterClass } = {}
	for _, class in CharacterClasses do
		table.insert(byOrder, class)
	end
	table.sort(byOrder, function(a, b)
		return a.order < b.order
	end)
	for index = 2, #byOrder do
		assert(
			byOrder[index].multiplier < byOrder[index - 1].multiplier,
			`Config: คลาส "{byOrder[index].id}" ไม่ได้อ่อนกว่าคลาสที่อยู่เหนือมัน ("{byOrder[index - 1].id}")`
		)
	end

	----------------------------------------------------------------------------
	-- เงินจากการฆ่า — ต้องไม่ตกยุค
	----------------------------------------------------------------------------
	-- ราคาของทุกอย่างโต ×10 ต่อขั้น ถ้าบ่อเงินโตช้ากว่านั้น มันจะกลายเป็นเศษเงิน
	-- กลางเกม แล้วผู้เล่นจะกลับไปติดปัญหาเดิม: มีบ่อเงินแต่ซื้ออะไรไม่ได้
	-- ⚠️ 5C: กระบองไม่อยู่ในนี้แล้ว — ราคากระบองคำนวณจากรายได้ด่านนั้น (getClubPrice) จึงโตเท่ารายได้โดยโครงสร้าง
	local priceGrowth = math.max(
		Config.Balance.Pen.UPGRADE_COST_MULTIPLIER,
		Config.Balance.Production.UPGRADE_COST_MULTIPLIER
	)

	assert(economy.KILL_DEFENDER_BASE > 0, "Config: KILL_DEFENDER_BASE ต้องมากกว่า 0")
	assert(economy.KILL_BOSS_BASE > 0, "Config: KILL_BOSS_BASE ต้องมากกว่า 0")
	assert(
		economy.BOSS_REWARD_MIN_DAMAGE > 0,
		"Config: BOSS_REWARD_MIN_DAMAGE ต้องมากกว่า 0 — ไม่งั้นคนยืนเฉย ๆ ก็ได้ส่วนแบ่ง"
	)
	-- แบ่งเท่ากันแล้วต้องได้ครบพอดี ไม่มีเศษหายหรือเงินงอก
	assert(
		Config.getBossKillShare(5, 1) == Config.getBossKillReward(5),
		"Config: คนเดียวร่วมตีต้องได้เต็มจำนวน"
	)
	assert(
		math.abs(
			Config.getBossKillShare(5, Config.Balance.BalanceCheck.PLAYERS_PER_SERVER)
				* Config.Balance.BalanceCheck.PLAYERS_PER_SERVER
				- Config.getBossKillReward(5)
		) < 1e-6,
		"Config: ส่วนแบ่งรวมของทุกคนต้องเท่ากับรางวัลเต็มพอดี"
	)
	assert(
		economy.KILL_BOSS_MULTIPLIER >= priceGrowth,
		`Config: เงินจากบอสโต ×{economy.KILL_BOSS_MULTIPLIER} ต่อด่าน แต่ราคาของโต ×{priceGrowth} `
			.. `— บอสจะกลายเป็นเศษเงินตั้งแต่กลางเกม`
	)

	for rewardStage = 2, Config.Balance.Stage.COUNT do
		local previous = Config.getStageDefenderRewardTotal(rewardStage - 1)
		if previous > 0 then
			local growth = Config.getStageDefenderRewardTotal(rewardStage) / previous
			assert(
				growth >= priceGrowth,
				`Config: เงินจากการกวาดทหารด่าน {rewardStage} โตแค่ ×{string.format("%.2f", growth)} จากด่านก่อน `
					.. `แต่ราคาของโต ×{priceGrowth} — บ่อเงินนี้จะตกยุค`
			)
		end
	end

	-- ทำท้ายสุด เพราะต้องใช้ค่าที่เช็คไปแล้วข้างบนทั้งหมด
	assertProgressionIsSane()
	assertTurretIsSurvivable()
end

return Config
