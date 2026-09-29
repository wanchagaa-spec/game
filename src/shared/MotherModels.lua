--!strict
-- egg-army-game :: โมเดลตัวละครแม่ที่ประกอบจาก Part ในโค้ด (ครบ 12 ตัว · ลิงเปลี่ยนจาก mesh มาเป็นแบบนี้แล้ว)
--
-- สไตล์: บล็อกน่ารัก หัวโต (chibi) · ใช้แค่ Part ธรรมดา (Block/Ball/Cylinder) + WedgePart · ไม่มี asset ภายนอก · ไม่มี Union
-- ⚠️ หน้าตาออกแบบเองจากภาพไซอิ๋วแบบทั่วไป — **ห้ามเลียนแบบตัวละครจากการ์ตูน/เกมที่มีลิขสิทธิ์**
--
-- ══ หน่วย + ทิศ ══
--   ออกแบบเป็น **studs จริงที่ขนาด tier 1 คลาส C** (คน/ลิงสูง ≈ 5 = VisualScale.MOTHER_MESH_BASE_HEIGHT เท่ากับลิง mesh)
--   → PenService คูณ ตัวคูณน้ำหนัก × ตัวคูณคลาส (Config.getMotherClassScale) เอง · **ไม่ normalize ความสูง**
--     (หมูเตี้ยกว่าคนตามที่ออกแบบ · ของที่ถือไม่ทำให้ตัวหดลง)
--   เท้าอยู่ที่ Y = 0 · กึ่งกลางตัวที่ X = 0, Z = 0 · **หน้าหัน −Z** (LookVector ของ pivot) · มือขวา = +X
--   pivot ของโมเดล = จุดกำเนิด (0, 0, 0) ไม่หมุน · PrimaryPart = ชิ้นลำตัว (`primary = true` · ห้ามหมุน)
--
-- ══ กฎรูปทรง ══ (tests/models.spec.luau ตรวจ)
--   · Ball ขนาดเท่ากันทั้งสามแกน (กฎเดิมของโปรเจกต์ — ลูกบอลขนาดไม่เท่ากัน Roblox วาดไม่แน่นอน)
--   · Cylinder แกนยาว = X · Y = Z เสมอ (หมุนเอาเองด้วย rot)
--   · Wedge ด้านสูงอยู่ +Z ด้านเตี้ย (สันศูนย์) อยู่ −Z · ≤ PART_LIMIT ชิ้นต่อตัว
--   · rot = องศา (rx, ry, rz) แบบ CFrame.Angles (หมุน Z → Y → X ในกรอบโลก)
--
-- ══ rig R6 (ลิง · ผู้ใช้สั่ง "ทำ rig + ใช้อนิเมชันของ Roblox") ══
--   แบบที่มี `rig = "R6"` ต้องมีชิ้นชื่อตรง R6 ครบ 7 ชิ้น (HumanoidRootPart · Torso · Head · Right/Left Arm · Right/Left Leg)
--   → build() ต่อ Motor6D 6 ตัวชื่อ/ทิศตาม rig R6 มาตรฐานของ Roblox เป๊ะ (เฉพาะจุดหมุนขยับตามขนาดชิ้นของเรา · computeR6Joints)
--   → **อนิเมชันตั้งต้นของ Roblox (R6) เล่นได้เลย** (เป็นของ Roblox → ทุกเกมใช้ได้ · R6_ANIMATIONS) ผ่าน AnimationController
--     (⚠️ ไม่ใช่ Humanoid — กฎเดิม "ห้ามใช้ Humanoid กับแม่") · ชิ้นตกแต่งเชื่อมกับชิ้น rig ด้วย Weld (`attach`)
--   → HumanoidRootPart (ใส · ไม่มีตัวตน) เป็น PrimaryPart และ**ชิ้นเดียวที่ Anchored** — ชิ้นอื่นขยับตามข้อต่อ (อนิเมชันขยับได้)
--
-- ⚠️ ไฟล์นี้**ไม่แตะ Roblox API ตอน require** (ข้อมูลล้วน + ฟังก์ชันคำนวณ) — เทสต์นอก Studio ได้
--   build() เท่านั้นที่สร้าง Instance (เรียกจาก server ตอนบูต — PenService ใส่ต้นแบบลง ReplicatedStorage.MotherModelTemplates)

local MotherModels = {}

-- เพดานชิ้นต่อตัว — คอกเต็ม 6 คน × 14 ตัว + ตัวอย่าง showcase ต้องไม่หน่วง (ผู้ใช้กำหนด)
MotherModels.PART_LIMIT = 40

export type Shape = "Block" | "Ball" | "Cylinder" | "Wedge"
export type Vec = { number } -- { x, y, z }

export type PartSpec = {
	name: string,
	shape: Shape,
	size: Vec,
	pos: Vec,
	rot: Vec?, -- องศา · nil = ไม่หมุน
	color: Vec, -- RGB 0–255
	material: string?, -- ชื่อ Enum.Material · nil = SmoothPlastic
	primary: boolean?,
	transparency: number?, -- nil = 0 (ทึบ)
	-- rig เท่านั้น: ชื่อชิ้น rig ที่ชิ้นตกแต่งนี้ติดไปด้วย (Weld) — ชิ้น rig เองไม่มี
	attach: string?,
}

-- "hop" = กระเด้งเบา ๆ ตอนเดิน (ไม่มีอนิเมชัน) · "float" = ลอยเหนือพื้นแล้วขยับขึ้นลงตลอด (ปลา) ·
-- "animated" = rig เล่นอนิเมชันจริง (ไม่กระเด้งเอง)
export type Motion = "hop" | "float" | "animated"

export type Blueprint = {
	motion: Motion,
	parts: { PartSpec },
	rig: "R6"?, -- มี = ต่อข้อต่อ R6 + เล่นอนิเมชัน R6 ของ Roblox
	-- ความเร็วเล่นท่าเดินที่ tier 1 (rig) — อนิเมชันเดิน R6 ของ Roblox ตั้งมาที่ 14.5 studs/วิ ขายาว 2 ·
	-- แม่เดิน 4 studs/วิ ขาสั้นกว่า → ช้าลงให้เท้าไม่ไถล (ตัวใหญ่ PenService ช้าลงอีก √s เหมือนเดิม)
	walkAnimSpeed: number?,
}

-- ══ rig R6 ══ ชื่อชิ้น + ข้อต่อ + ทิศข้อต่อ **ตาม rig R6 มาตรฐานของ Roblox** (อนิเมชัน R6 อ้างชื่อชิ้น + หมุนรอบแกนของข้อต่อ)
-- ทิศ (เมทริกซ์ 3×3 แบบ CFrame.new(x, y, z, R00…R22)) ห้ามแก้ — แก้แล้วอนิเมชันหมุนผิดแกน (ขาแกว่งออกข้างแทนหน้า-หลัง)
MotherModels.R6_PARTS = { "HumanoidRootPart", "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
local R6_ROOT_ROTATION = { -1, 0, 0, 0, 0, 1, 0, 1, 0 }
local R6_RIGHT_ROTATION = { 0, 0, 1, 0, 1, 0, -1, 0, 0 }
local R6_LEFT_ROTATION = { 0, 0, -1, 0, 1, 0, 1, 0, 0 }
export type JointSpec = {
	name: string,
	part0: string,
	part1: string,
	c0: Vec, -- จุดหมุนในกรอบของ part0 (ตำแหน่งเท่านั้น · ทิศ = rotation)
	c1: Vec, -- จุดหมุนในกรอบของ part1
	rotation: { number }, -- 9 ค่า
}

-- อนิเมชันตั้งต้นของ Roblox สำหรับ rig R6 (จากสคริปต์ Animate R6 ของ Roblox · เจ้าของคือ Roblox → ใช้ได้ทุกเกม)
-- ท่าที่ PenService ใช้: walk ตอนเดิน · idle/punch วนตอนหยุดพัก (ดู REST_POSE_ORDER)
-- ⚠️ ไม่ใส่ sit (178130996) — ท่านั่งของ R6 ต้องมีที่นั่ง ไม่มีแล้วขาเหยียดลอยกลางอากาศ
-- ท่าอื่นที่มีให้ใช้ถ้าอยากเพิ่ม: wave 128777973 · cheer 129423030 · laugh 129423131 · dance 182435998 · point 128853357
MotherModels.R6_ANIMATIONS = {
	walk = 180426354,
	idle = 180435571,
	punch = 129967390, -- toolslash: เหวี่ยงแขนขวา (ใกล้ท่าต่อยที่สุดของชุดตั้งต้น)
}

-- ท่าขยับ (สัดส่วนของความสูงตัวที่วาดจริง — ตัวใหญ่ขยับมากตาม · PenService คูณเอง)
MotherModels.HOP = {
	HEIGHT_RATIO = 0.05, -- กระเด้งสูงสุด = 5% ของความสูงตัว
	STEPS_PER_SECOND = 2.4, -- ที่ tier 1 · ตัวใหญ่ s เท่าช้าลง √s (ก้าวยาวขึ้น แบบเดียวกับอนิเมชันลิง)
}
MotherModels.FLOAT = {
	HOVER_RATIO = 0.12, -- ลอยเหนือพื้น 12% ของความสูงตัว
	BOB_RATIO = 0.035, -- ขยับขึ้นลง ±3.5%
	PERIOD = 2.4, -- วินาทีต่อรอบขึ้น-ลง
}

--------------------------------------------------------------------------------
-- ตัวช่วยเขียนแบบ
--------------------------------------------------------------------------------

local function spec(shape: Shape, name: string, size: Vec, pos: Vec, color: Vec, extra: { [string]: any }?): PartSpec
	local out: PartSpec = { name = name, shape = shape, size = size, pos = pos, color = color }
	if extra then
		out.rot = extra.rot
		out.material = extra.material
		out.primary = extra.primary
		out.transparency = extra.transparency
		out.attach = extra.attach
	end
	return out
end

local function block(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Vec, extra: { [string]: any }?): PartSpec
	return spec("Block", name, { sx, sy, sz }, { x, y, z }, color, extra)
end

local function ball(name: string, d: number, x: number, y: number, z: number, color: Vec, extra: { [string]: any }?): PartSpec
	return spec("Ball", name, { d, d, d }, { x, y, z }, color, extra)
end

-- ทรงกระบอก: แกนยาวตาม X (ของ Roblox) · หมุนเอาเองด้วย extra.rot
local function cyl(name: string, length: number, d: number, x: number, y: number, z: number, color: Vec, extra: { [string]: any }?): PartSpec
	return spec("Cylinder", name, { length, d, d }, { x, y, z }, color, extra)
end

-- ลิ่ม: สูงเต็มที่ฝั่ง +Z เตี้ยเป็นสันที่ฝั่ง −Z
local function wedge(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Vec, extra: { [string]: any }?): PartSpec
	return spec("Wedge", name, { sx, sy, sz }, { x, y, z }, color, extra)
end

-- กระจกเงาข้ามระนาบ X = 0 (ชิ้นซ้าย ↔ ขวา) — หมุนรอบ Y และ Z กลับทิศ รอบ X คงเดิม · ติดกับแขน/ขาขวา → ซ้าย
local function mirror(source: PartSpec, name: string): PartSpec
	local rot = source.rot
	local attach = source.attach
	return {
		name = name,
		shape = source.shape,
		size = source.size,
		pos = { -source.pos[1], source.pos[2], source.pos[3] },
		rot = if rot then { rot[1], -rot[2], -rot[3] } else nil,
		color = source.color,
		material = source.material,
		primary = nil,
		transparency = source.transparency,
		attach = if attach then (string.gsub(attach, "^Right ", "Left ")) else nil,
	}
end

-- ประกอบรายการชิ้น: ใส่ชิ้นเดี่ยว หรือ pair(ชิ้นฝั่งขวา +X) = ได้ทั้งขวา + ซ้าย
type Entry = PartSpec | { pair: PartSpec }

local function pair(right: PartSpec): Entry
	return { pair = right }
end

local function assemble(entries: { Entry }): { PartSpec }
	local parts: { PartSpec } = {}
	for _, entry in entries do
		local pairEntry = (entry :: any).pair
		if pairEntry then
			local right = pairEntry :: PartSpec
			local baseName = right.name
			table.insert(parts, {
				name = baseName .. "R",
				shape = right.shape,
				size = right.size,
				pos = right.pos,
				rot = right.rot,
				color = right.color,
				material = right.material,
				transparency = right.transparency,
				attach = right.attach,
			})
			table.insert(parts, mirror(right, baseName .. "L"))
		else
			table.insert(parts, entry :: PartSpec)
		end
	end
	return parts
end

--------------------------------------------------------------------------------
-- สี (RGB 0–255)
--------------------------------------------------------------------------------

local COLOR = {
	eye = { 22, 22, 26 },
	black = { 35, 33, 38 },
	white = { 246, 246, 248 },
	skin = { 255, 214, 172 },
	gold = { 238, 192, 64 },
	red = { 205, 45, 45 },
	darkRed = { 135, 22, 28 },
	yellow = { 246, 206, 72 },
	-- หมู
	pink = { 250, 172, 186 },
	pinkLight = { 255, 204, 214 },
	pinkDark = { 226, 128, 150 },
	-- ม้า
	brown = { 150, 96, 56 },
	brownDark = { 92, 58, 34 },
	tan = { 232, 194, 144 },
	hoof = { 45, 40, 38 },
	-- ปลา
	orange = { 255, 140, 42 },
	finBlue = { 64, 150, 235 },
	-- ซัวเจ๋ง
	robeKhaki = { 150, 112, 62 },
	pantsDark = { 70, 62, 58 },
	skinBlue = { 122, 152, 176 },
	beardRed = { 200, 52, 36 },
	bone = { 236, 222, 188 },
	silver = { 186, 192, 204 },
	-- ม้าขาวมังกร
	horseWhite = { 244, 244, 250 },
	muzzleGrey = { 218, 220, 230 },
	scaleCyan = { 88, 190, 232 },
	-- องค์หญิงพัดเหล็ก
	green = { 58, 158, 92 },
	leafGreen = { 134, 176, 64 },
	leafVein = { 86, 122, 40 },
	hair = { 28, 24, 30 },
	-- เง็กเซียน
	jade = { 84, 176, 126 },
	imperial = { 248, 202, 58 },
	-- ราชาปีศาจวัว
	armor = { 42, 36, 44 },
	armorRed = { 178, 30, 36 },
	bullHide = { 64, 42, 36 },
	bullMuzzle = { 196, 156, 118 },
	horn = { 236, 226, 202 },
	hornTip = { 96, 90, 84 },
	glowRed = { 255, 42, 30 },
	fist = { 92, 56, 40 },
	wood = { 132, 84, 46 },
	iron = { 170, 176, 188 },
}

-- ท่ายืนตรง: ลำตัวไม่หมุน · หมุนแค่อุปกรณ์/หู/หาง
local UPRIGHT = { 0, 0, 90 } -- ทรงกระบอกตั้งตรง (แกน X → Y)
local FACING = { 0, 90, 0 } -- ทรงกระบอกหันหน้า (แกน X → Z · จาน/ปลายจมูกมองจากด้านหน้าเป็นวงกลม)

--------------------------------------------------------------------------------
-- แบบของแต่ละตัว (charId ต้องตรงกับ Config.Characters)
--------------------------------------------------------------------------------

local BLUEPRINTS: { [string]: Blueprint } = {}

-- ══ C · ลิง ══ (ผู้ใช้สั่ง: เลิกใช้ mesh เดิม · ทำใหม่เป็นบล็อกเข้าชุด + rig R6 เล่นอนิเมชันของ Roblox)
-- ขนน้ำตาล · หน้า/พุง/มือ/เท้าสีครีม · หูกลมใหญ่ · หางม้วนขึ้น · ไม่มีเสื้อผ้า (ต่างจากซุนหงอคงที่ใส่ชุด+รัดเกล้า)
-- ⚠️ ชิ้น rig ห้ามหมุน (จุดหมุนข้อต่อคำนวณจากกล่องของชิ้น) · ชิ้นตกแต่งทุกชิ้นต้องมี attach
BLUEPRINTS.monkey = {
	motion = "animated",
	rig = "R6",
	walkAnimSpeed = 0.55, -- = 4 ÷ 14.5 × (2 ÷ ขายาว 1.1) ≈ 0.5 · ปัดขึ้นให้ก้าวถี่นิด ๆ แบบลิง
	parts = assemble({
		block("HumanoidRootPart", 1.0, 1.0, 0.6, 0, 1.8, 0, COLOR.brown, { primary = true, transparency = 1 }),
		block("Torso", 1.7, 1.4, 1.0, 0, 1.8, 0, COLOR.brown),
		block("Head", 2.3, 2.0, 2.0, 0, 3.5, 0, COLOR.brown),
		block("Right Arm", 0.55, 1.3, 0.6, 1.125, 1.85, 0, COLOR.brown),
		block("Left Arm", 0.55, 1.3, 0.6, -1.125, 1.85, 0, COLOR.brown),
		block("Right Leg", 0.7, 1.1, 0.75, 0.45, 0.55, 0, COLOR.brown),
		block("Left Leg", 0.7, 1.1, 0.75, -0.45, 0.55, 0, COLOR.brown),
		-- หน้า
		block("Face", 1.7, 1.45, 0.1, 0, 3.4, -1.03, COLOR.tan, { attach = "Head" }),
		block("Muzzle", 1.0, 0.55, 0.35, 0, 2.95, -1.2, COLOR.tan, { attach = "Head" }),
		block("Nose", 0.3, 0.12, 0.06, 0, 3.1, -1.39, COLOR.brownDark, { attach = "Head" }),
		block("Mouth", 0.45, 0.08, 0.06, 0, 2.86, -1.39, COLOR.brownDark, { attach = "Head" }),
		pair(block("Eye", 0.25, 0.32, 0.08, 0.4, 3.62, -1.1, COLOR.eye, { attach = "Head" })),
		pair(cyl("Ear", 0.18, 0.85, 1.22, 3.5, 0, COLOR.tan, { attach = "Head" })),
		wedge("HairTuft", 0.5, 0.35, 0.6, 0, 4.67, -0.3, COLOR.brownDark, { attach = "Head" }),
		-- ตัว
		block("Belly", 1.1, 1.0, 0.08, 0, 1.75, -0.52, COLOR.tan, { attach = "Torso" }),
		pair(ball("Hand", 0.55, 1.125, 1.2, 0, COLOR.tan, { attach = "Right Arm" })),
		pair(block("Foot", 0.72, 0.2, 0.9, 0.45, 0.1, -0.1, COLOR.tan, { attach = "Right Leg" })),
		block("Tail1", 0.26, 1.2, 0.26, 0, 1.3, 0.85, COLOR.brown, { rot = { 60, 0, 0 }, attach = "Torso" }),
		block("Tail2", 0.26, 1.0, 0.26, 0, 2.05, 1.45, COLOR.brown, { rot = { 10, 0, 0 }, attach = "Torso" }),
		ball("TailTip", 0.36, 0, 2.6, 1.5, COLOR.brownDark, { attach = "Torso" }),
	}),
}

-- ══ C · หมู ══ ตัวกลมสีชมพู จมูกแบน หูตก หางขด
BLUEPRINTS.pig = {
	motion = "hop",
	parts = assemble({
		pair(block("FrontLeg", 0.6, 0.8, 0.6, 0.7, 0.4, -0.75, COLOR.pinkDark)),
		pair(block("BackLeg", 0.6, 0.8, 0.6, 0.7, 0.4, 0.85, COLOR.pinkDark)),
		ball("Body", 3.0, 0, 1.95, 0.25, COLOR.pink, { primary = true }),
		ball("Head", 2.4, 0, 2.75, -1.35, COLOR.pink),
		cyl("Snout", 0.4, 1.0, 0, 2.55, -2.55, COLOR.pinkLight, { rot = FACING }),
		pair(block("Nostril", 0.15, 0.25, 0.06, 0.18, 2.55, -2.77, COLOR.pinkDark)),
		pair(ball("Eye", 0.32, 0.45, 3.0, -2.4, COLOR.eye)),
		pair(block("Ear", 0.7, 0.14, 0.6, 0.8, 3.62, -1.25, COLOR.pinkDark, { rot = { -15, 0, -35 } })),
		ball("Tail1", 0.32, 0, 2.2, 1.78, COLOR.pinkDark),
		ball("Tail2", 0.26, 0.16, 2.42, 1.9, COLOR.pinkDark),
		ball("Tail3", 0.2, 0.02, 2.6, 1.86, COLOR.pinkDark),
	}),
}

-- ══ C · ม้า ══ สีน้ำตาล แผงคอ หาง ขาสี่ขา
local function horseBody(coat: Vec, hoof: Vec, muzzle: Vec, extras: { Entry }): { PartSpec }
	local entries: { Entry } = {
		pair(block("FrontLeg", 0.5, 1.4, 0.5, 0.55, 0.95, -1.05, coat)),
		pair(block("BackLeg", 0.5, 1.4, 0.5, 0.55, 0.95, 1.05, coat)),
		pair(block("FrontHoof", 0.56, 0.3, 0.56, 0.55, 0.15, -1.05, hoof)),
		pair(block("BackHoof", 0.56, 0.3, 0.56, 0.55, 0.15, 1.05, hoof)),
		block("Body", 1.6, 1.5, 3.0, 0, 2.35, 0, coat, { primary = true }),
		block("Neck", 0.9, 1.6, 1.0, 0, 3.4, -1.25, coat, { rot = { -25, 0, 0 } }),
		block("Head", 1.2, 1.2, 1.9, 0, 4.35, -1.95, coat),
		block("Muzzle", 1.0, 0.75, 0.55, 0, 4.0, -2.95, muzzle),
		pair(block("Nostril", 0.16, 0.22, 0.06, 0.24, 4.05, -3.24, COLOR.eye)),
		pair(block("Eye", 0.22, 0.3, 0.08, 0.36, 4.6, -2.92, COLOR.eye)),
	}
	for _, entry in extras do
		table.insert(entries, entry)
	end
	return assemble(entries)
end

BLUEPRINTS.horse = {
	motion = "hop",
	parts = horseBody(COLOR.brown, COLOR.hoof, COLOR.tan, {
		block("Blaze", 0.3, 0.5, 0.06, 0, 4.62, -2.92, COLOR.white),
		pair(block("Ear", 0.25, 0.55, 0.25, 0.38, 5.2, -1.6, COLOR.brown, { rot = { 0, 0, -12 } })),
		block("Mane", 0.3, 1.9, 0.4, 0, 3.8, -0.88, COLOR.brownDark, { rot = { -25, 0, 0 } }),
		block("Forelock", 0.5, 0.3, 0.35, 0, 5.0, -2.55, COLOR.brownDark),
		block("Tail", 0.4, 1.5, 0.4, 0, 2.3, 1.85, COLOR.brownDark, { rot = { -25, 0, 0 } }),
	}),
}

-- ══ C · ปลา ══ ลำตัวส้ม ลายขาว ครีบ/หางฟ้า · ลอยตัวขยับขึ้นลงแทนการเดิน
BLUEPRINTS.fish = {
	motion = "float",
	parts = assemble({
		ball("Body", 2.6, 0, 1.3, 0, COLOR.orange, { primary = true }),
		cyl("Stripe1", 0.35, 2.64, 0, 1.3, 0.25, COLOR.white, { rot = FACING }),
		cyl("Stripe2", 0.3, 1.86, 0, 1.3, 0.95, COLOR.white, { rot = FACING }),
		wedge("TailTop", 0.22, 1.0, 1.1, 0, 1.8, 1.75, COLOR.finBlue),
		wedge("TailBottom", 0.22, 1.0, 1.1, 0, 0.8, 1.75, COLOR.finBlue, { rot = { 0, 0, 180 } }),
		wedge("Dorsal", 0.2, 0.9, 1.3, 0, 2.8, 0.3, COLOR.finBlue),
		pair(block("Fin", 0.8, 0.14, 0.55, 1.35, 1.05, 0.1, COLOR.finBlue, { rot = { 0, -25, -30 } })),
		pair(ball("EyeWhite", 0.8, 0.55, 1.7, -1.05, COLOR.white)),
		pair(ball("Pupil", 0.42, 0.58, 1.7, -1.38, COLOR.eye)),
		block("Mouth", 0.5, 0.14, 0.1, 0, 0.95, -1.24, COLOR.eye),
	}),
}

-- ══ B · ตือโป๊ยก่าย ══ คนหัวหมู พุงโต หูใหญ่ ชุดดำ ถือคราดเก้าซี่
do
	local entries: { Entry } = {
		pair(block("Leg", 0.8, 1.0, 0.8, 0.55, 0.5, 0, COLOR.black)),
		block("Body", 2.2, 1.6, 1.6, 0, 1.8, 0, COLOR.black, { primary = true }),
		ball("Belly", 1.9, 0, 1.75, -0.45, COLOR.pink),
		pair(block("Arm", 0.6, 1.3, 0.7, 1.4, 2.0, 0, COLOR.black)),
		pair(ball("Hand", 0.65, 1.4, 1.2, 0, COLOR.pink)),
		block("Head", 2.4, 2.1, 2.1, 0, 3.65, 0, COLOR.pink),
		cyl("Snout", 0.4, 1.0, 0, 3.35, -1.2, COLOR.pinkLight, { rot = FACING }),
		pair(block("Nostril", 0.15, 0.25, 0.06, 0.2, 3.35, -1.42, COLOR.pinkDark)),
		pair(block("Eye", 0.26, 0.36, 0.08, 0.55, 3.95, -1.07, COLOR.eye)),
		pair(block("Ear", 1.1, 0.18, 1.1, 1.35, 4.35, -0.1, COLOR.pinkDark, { rot = { -10, 0, -35 } })),
		block("Cap", 2.2, 0.35, 1.9, 0, 4.85, 0.05, COLOR.black),
		cyl("RakeHandle", 5.4, 0.22, 1.72, 2.7, -0.3, COLOR.wood, { rot = UPRIGHT }),
		block("RakeHead", 1.7, 0.3, 0.3, 1.72, 5.3, -0.3, COLOR.iron, { material = "Metal" }),
	}
	-- คราดเก้าซี่ — ซี่ยื่นไปข้างหน้าจากหัวคราด
	for tooth = 1, 9 do
		table.insert(entries, block(`RakeTooth{tooth}`, 0.1, 0.12, 0.6, 1.72 + (tooth - 5) * 0.2, 5.2, -0.75, COLOR.iron, { material = "Metal" }))
	end
	BLUEPRINTS.bajie = { motion = "hop", parts = assemble(entries) }
end

-- ══ B · ซัวเจ๋ง ══ ผิวเทาอมฟ้า เคราแดง หัวโล้น สร้อยลูกประคำเม็ดใหญ่ ถือไม้พลองปลายจันทร์เสี้ยว
do
	local entries: { Entry } = {
		pair(block("Leg", 0.75, 1.0, 0.8, 0.5, 0.5, 0, COLOR.pantsDark)),
		block("Body", 2.1, 1.6, 1.4, 0, 1.8, 0, COLOR.robeKhaki, { primary = true }),
		pair(block("Arm", 0.6, 1.4, 0.7, 1.35, 1.9, 0, COLOR.skinBlue)),
		block("Head", 2.3, 2.1, 2.1, 0, 3.65, 0, COLOR.skinBlue),
		block("Beard", 1.9, 0.85, 0.35, 0, 2.95, -1.1, COLOR.beardRed),
		pair(block("Sideburn", 0.3, 1.1, 1.2, 1.18, 3.35, -0.4, COLOR.beardRed)),
		pair(block("Eye", 0.28, 0.3, 0.08, 0.5, 3.9, -1.07, COLOR.eye)),
		pair(block("Brow", 0.55, 0.15, 0.08, 0.5, 4.2, -1.08, COLOR.beardRed, { rot = { 0, 0, 12 } })),
		cyl("Staff", 5.2, 0.22, 1.7, 2.6, -0.3, COLOR.silver, { rot = UPRIGHT, material = "Metal" }),
		-- ปลายจันทร์เสี้ยว: รูปตัว U เปิดขึ้นบน
		block("MoonBase", 0.8, 0.2, 0.2, 1.7, 5.25, -0.3, COLOR.silver, { material = "Metal" }),
		block("MoonHornR", 0.2, 0.7, 0.2, 2.12, 5.55, -0.3, COLOR.silver, { rot = { 0, 0, -25 }, material = "Metal" }),
		block("MoonHornL", 0.2, 0.7, 0.2, 1.28, 5.55, -0.3, COLOR.silver, { rot = { 0, 0, 25 }, material = "Metal" }),
	}
	-- สร้อยลูกประคำ 7 เม็ดโค้งเป็นรูปตัว U กลางอก
	local beadX = { -0.85, -0.6, -0.32, 0, 0.32, 0.6, 0.85 }
	local beadY = { 2.5, 2.2, 1.99, 1.92, 1.99, 2.2, 2.5 }
	for index = 1, #beadX do
		table.insert(entries, ball(`Bead{index}`, 0.42, beadX[index], beadY[index], -0.78, COLOR.bone))
	end
	BLUEPRINTS.wujing = { motion = "hop", parts = assemble(entries) }
end

-- ══ B · ม้าขาวมังกร ══ ม้าขาว มีเขาเล็ก สันหลังเป็นเกล็ด หางเป็นพู่
BLUEPRINTS.dragon_horse = {
	motion = "hop",
	parts = horseBody(COLOR.horseWhite, COLOR.gold, COLOR.muzzleGrey, {
		pair(block("Horn", 0.18, 0.75, 0.18, 0.3, 5.25, -1.55, COLOR.gold, { rot = { 25, 0, -12 } })),
		wedge("Scale1", 0.22, 0.45, 0.55, 0, 3.32, 1.0, COLOR.scaleCyan),
		wedge("Scale2", 0.22, 0.45, 0.55, 0, 3.32, 0.35, COLOR.scaleCyan),
		wedge("Scale3", 0.22, 0.45, 0.55, 0, 3.32, -0.3, COLOR.scaleCyan),
		wedge("Scale4", 0.22, 0.45, 0.55, 0, 3.95, -0.95, COLOR.scaleCyan, { rot = { -25, 0, 0 } }),
		block("Forelock", 0.5, 0.3, 0.35, 0, 5.0, -2.55, COLOR.scaleCyan),
		block("Tail", 0.3, 1.5, 0.3, 0, 2.3, 1.85, COLOR.horseWhite, { rot = { -25, 0, 0 } }),
		ball("TailTuft", 0.85, 0, 1.55, 2.2, COLOR.scaleCyan),
	}),
}

-- ══ A · พระถังซัมจั๋ง ══ จีวรแดง-เหลือง หมวกทรงมงกุฎห้าแฉก ถือไม้เท้าหัวห่วง
do
	local entries: { Entry } = {
		block("Skirt", 2.0, 1.5, 1.6, 0, 0.75, 0, COLOR.yellow),
		block("Body", 1.9, 1.3, 1.3, 0, 2.15, 0, COLOR.red, { primary = true }),
		-- จีวรลายตาราง (ผ้าปะ) สีทอง
		pair(block("RobeLineV", 0.12, 1.3, 0.06, 0.45, 2.15, -0.67, COLOR.gold)),
		block("RobeLineH", 1.9, 0.1, 0.06, 0, 2.15, -0.67, COLOR.gold),
		pair(block("Sleeve", 0.6, 1.2, 0.7, 1.25, 2.2, 0, COLOR.yellow)),
		pair(ball("Hand", 0.55, 1.25, 1.45, 0, COLOR.skin)),
		block("Head", 2.2, 2.0, 2.0, 0, 3.8, 0, COLOR.skin),
		pair(block("Eye", 0.24, 0.32, 0.08, 0.48, 3.95, -1.02, COLOR.eye)),
		block("Mouth", 0.4, 0.1, 0.06, 0, 3.4, -1.02, COLOR.darkRed),
		block("CrownBand", 2.3, 0.35, 2.1, 0, 4.62, 0, COLOR.gold, { material = "Metal" }),
		block("CrownTop", 2.0, 0.3, 1.9, 0, 4.9, 0.05, COLOR.red),
		-- ไม้เท้าหัวห่วง (ขักขระ): ด้าม + ห่วงสี่เหลี่ยมข้าวหลามตัด + ลูกกระพรวน
		cyl("StaffHandle", 5.0, 0.2, 1.6, 2.5, -0.3, COLOR.gold, { rot = UPRIGHT, material = "Metal" }),
		block("RingTR", 0.85, 0.12, 0.12, 1.885, 5.635, -0.3, COLOR.gold, { rot = { 0, 0, -45 }, material = "Metal" }),
		block("RingTL", 0.85, 0.12, 0.12, 1.315, 5.635, -0.3, COLOR.gold, { rot = { 0, 0, 45 }, material = "Metal" }),
		block("RingBR", 0.85, 0.12, 0.12, 1.885, 5.065, -0.3, COLOR.gold, { rot = { 0, 0, 45 }, material = "Metal" }),
		block("RingBL", 0.85, 0.12, 0.12, 1.315, 5.065, -0.3, COLOR.gold, { rot = { 0, 0, -45 }, material = "Metal" }),
		ball("JingleR", 0.26, 2.2, 4.95, -0.3, COLOR.gold, { material = "Metal" }),
		ball("JingleL", 0.26, 1.0, 4.95, -0.3, COLOR.gold, { material = "Metal" }),
	}
	-- มงกุฎห้าแฉก: กลีบตั้งเรียงครึ่งวงหน้าหมวก หันออกนอก
	for index, angle in { -64, -32, 0, 32, 64 } do
		local radians = math.rad(angle)
		table.insert(entries, block(`CrownPetal{index}`, 0.5, 0.85, 0.12, 1.12 * math.sin(radians), 5.05, -1.12 * math.cos(radians), COLOR.gold, {
			rot = { 0, -angle, 0 },
			material = "Metal",
		}))
	end
	BLUEPRINTS.tang = { motion = "hop", parts = assemble(entries) }
end

-- ══ A · ซุนหงอคง ══ ลิงยืนสองขา รัดเกล้าทอง ชุดแดง-เหลือง ถือกระบองทอง
BLUEPRINTS.wukong = {
	motion = "hop",
	parts = assemble({
		pair(block("Leg", 0.7, 1.0, 0.8, 0.5, 0.5, 0, COLOR.yellow)),
		pair(block("Boot", 0.75, 0.3, 0.9, 0.5, 0.15, -0.05, COLOR.black)),
		block("Body", 1.8, 1.4, 1.2, 0, 1.7, 0, COLOR.red, { primary = true }),
		block("Belt", 1.85, 0.25, 1.25, 0, 1.2, 0, COLOR.yellow),
		pair(block("Arm", 0.5, 1.3, 0.55, 1.15, 1.8, 0, COLOR.brown)),
		block("Head", 2.3, 2.1, 2.1, 0, 3.45, 0, COLOR.brown),
		block("Face", 1.7, 1.45, 0.1, 0, 3.4, -1.08, COLOR.tan),
		block("Muzzle", 1.0, 0.55, 0.35, 0, 2.95, -1.25, COLOR.tan),
		pair(block("Eye", 0.25, 0.32, 0.08, 0.4, 3.62, -1.14, COLOR.eye)),
		pair(cyl("Ear", 0.18, 0.75, 1.22, 3.55, 0, COLOR.tan)),
		block("Circlet", 2.4, 0.3, 2.2, 0, 4.05, 0, COLOR.gold, { material = "Foil" }),
		block("Tail1", 0.28, 1.3, 0.28, 0, 1.4, 0.95, COLOR.brown, { rot = { 60, 0, 0 } }),
		block("Tail2", 0.28, 1.1, 0.28, 0, 2.25, 1.6, COLOR.brown, { rot = { 10, 0, 0 } }),
		cyl("Staff", 4.8, 0.3, 1.5, 2.5, -0.3, COLOR.gold, { rot = UPRIGHT, material = "Foil" }),
		cyl("StaffBandTop", 0.4, 0.34, 1.5, 4.6, -0.3, COLOR.red, { rot = UPRIGHT }),
		cyl("StaffBandBottom", 0.4, 0.34, 1.5, 0.4, -0.3, COLOR.red, { rot = UPRIGHT }),
	}),
}

-- ══ S · องค์หญิงพัดเหล็ก (charId เดิม guanyin) ══ ชุดยาวแดง-เขียว ผมมวย ถือพัดใบตาลขนาดใหญ่
BLUEPRINTS.guanyin = {
	motion = "hop",
	parts = assemble({
		block("Skirt", 2.2, 1.6, 1.7, 0, 0.8, 0, COLOR.red),
		block("Hem", 2.25, 0.25, 1.75, 0, 0.13, 0, COLOR.green),
		block("Belt", 1.75, 0.25, 1.2, 0, 1.62, 0, COLOR.gold),
		block("Body", 1.7, 1.3, 1.15, 0, 2.25, 0, COLOR.green, { primary = true }),
		block("CollarTrim", 0.3, 1.3, 0.06, 0, 2.25, -0.6, COLOR.red),
		pair(block("Sleeve", 0.55, 1.2, 0.6, 1.13, 2.25, 0, COLOR.green)),
		pair(ball("Hand", 0.5, 1.13, 1.5, 0, COLOR.skin)),
		block("Head", 2.1, 1.9, 1.9, 0, 3.85, 0, COLOR.skin),
		block("HairBack", 2.2, 1.8, 0.55, 0, 3.8, 0.8, COLOR.hair),
		block("HairTop", 2.2, 0.45, 2.0, 0, 4.8, 0.05, COLOR.hair),
		block("Bangs", 2.15, 0.3, 0.2, 0, 4.5, -0.93, COLOR.hair),
		pair(block("SideLock", 0.25, 1.1, 0.5, 1.1, 3.95, -0.55, COLOR.hair)),
		ball("Bun", 1.1, 0, 5.35, 0.25, COLOR.hair),
		cyl("Hairpin", 1.6, 0.12, 0, 5.35, 0.25, COLOR.gold, { material = "Metal" }),
		ball("HairJewel", 0.3, 0.8, 5.35, 0.25, COLOR.red),
		pair(block("Eye", 0.22, 0.3, 0.08, 0.45, 3.9, -0.97, COLOR.eye)),
		block("Lips", 0.3, 0.12, 0.06, 0, 3.35, -0.97, COLOR.red),
		-- พัดใบตาล: ด้ามเฉียงจากมือขวาขึ้นไปหาใบพัดกลมใหญ่ข้างหัว
		cyl("FanHandle", 1.8, 0.16, 1.75, 2.2, -0.3, COLOR.wood, { rot = { 0, 0, 52 } }),
		cyl("FanLeaf", 0.12, 2.4, 2.3, 4.1, -0.3, COLOR.leafGreen, { rot = FACING }),
		block("FanVein1", 0.08, 2.2, 0.05, 2.3, 4.1, -0.385, COLOR.leafVein),
		block("FanVein2", 0.08, 2.0, 0.05, 2.3, 4.1, -0.385, COLOR.leafVein, { rot = { 0, 0, 35 } }),
		block("FanVein3", 0.08, 2.0, 0.05, 2.3, 4.1, -0.385, COLOR.leafVein, { rot = { 0, 0, -35 } }),
	}),
}

-- ══ S · เง็กเซียนฮ่องเต้ ══ ชุดจักรพรรดิเหลือง มงกุฎแบนมีพู่ลูกปัดห้อยหน้า-หลัง เครายาว
do
	local entries: { Entry } = {
		block("Robe", 2.2, 1.5, 1.7, 0, 0.75, 0, COLOR.imperial),
		block("Hem", 2.25, 0.2, 1.75, 0, 0.1, 0, COLOR.red),
		block("Belt", 2.05, 0.25, 1.45, 0, 1.55, 0, COLOR.jade),
		block("Body", 2.0, 1.4, 1.4, 0, 2.2, 0, COLOR.imperial, { primary = true }),
		cyl("Emblem", 0.06, 0.8, 0, 2.2, -0.73, COLOR.red, { rot = FACING }),
		pair(block("Sleeve", 0.8, 1.3, 1.0, 1.35, 2.15, 0, COLOR.imperial)),
		pair(ball("Hand", 0.5, 1.35, 1.35, 0, COLOR.skin)),
		block("Head", 2.1, 1.9, 1.9, 0, 3.85, 0, COLOR.skin),
		block("Beard", 0.9, 1.5, 0.25, 0, 2.95, -1.0, COLOR.hair),
		block("Mustache", 1.3, 0.18, 0.15, 0, 3.62, -1.0, COLOR.hair),
		pair(block("Eye", 0.24, 0.28, 0.08, 0.45, 3.98, -0.97, COLOR.eye)),
		pair(block("Brow", 0.5, 0.12, 0.06, 0.45, 4.22, -0.97, COLOR.hair)),
		block("CrownBand", 1.95, 0.15, 1.85, 0, 4.85, 0, COLOR.gold, { material = "Metal" }),
		block("CrownCap", 1.9, 0.55, 1.8, 0, 5.05, 0, COLOR.black),
		block("CrownBoard", 1.5, 0.12, 2.9, 0, 5.4, 0, COLOR.black),
	}
	-- พู่ลูกปัดห้อยหน้า-หลังแผ่นมงกุฎ (หน้า 4 สาย · หลัง 4 สาย) — เส้น + ลูกปัดปลายสาย สลับสีหยก/แดง
	for side, z in { -1.35, 1.35 } do
		for index, x in { -0.55, -0.2, 0.2, 0.55 } do
			local beadColor = if index % 2 == 1 then COLOR.jade else COLOR.red
			local label = if side == 1 then "Front" else "Back"
			table.insert(entries, block(`Tassel{label}{index}`, 0.1, 0.85, 0.1, x, 4.95, z, beadColor))
			table.insert(entries, ball(`TasselBead{label}{index}`, 0.2, x, 4.5, z, beadColor))
		end
	end
	BLUEPRINTS.jade_emperor = { motion = "hop", parts = assemble(entries) }
end

-- ══ SS · ราชาปีศาจวัว (charId เดิม yulai) ══ หัววัวเขาใหญ่ เกราะดำ-แดง ผ้าคลุม ตาแดงเรืองแสง ตัวใหญ่สุด (สเกลคลาส SS)
BLUEPRINTS.yulai = {
	motion = "hop",
	parts = assemble({
		pair(block("Leg", 0.85, 1.1, 0.9, 0.55, 0.55, 0, COLOR.armor)),
		block("Body", 2.3, 1.6, 1.4, 0, 1.9, 0, COLOR.armor, { primary = true }),
		block("ChestPlate", 1.8, 1.1, 0.15, 0, 2.05, -0.75, COLOR.armorRed),
		block("Belt", 2.35, 0.28, 1.45, 0, 1.25, 0, COLOR.gold, { material = "Metal" }),
		block("Cape", 2.6, 2.5, 0.15, 0, 1.55, 0.82, COLOR.darkRed, { rot = { -6, 0, 0 }, material = "Fabric" }),
		pair(block("Pauldron", 1.0, 0.5, 1.2, 1.5, 2.7, 0, COLOR.armorRed)),
		pair(wedge("PauldronSpike", 0.3, 0.45, 0.5, 1.5, 3.17, 0.1, COLOR.gold, { material = "Metal" })),
		pair(block("Arm", 0.7, 1.3, 0.8, 1.5, 1.95, 0, COLOR.armor)),
		pair(ball("Fist", 0.75, 1.5, 1.15, 0, COLOR.fist)),
		block("Head", 2.4, 2.2, 2.2, 0, 3.8, 0, COLOR.bullHide),
		block("Muzzle", 1.6, 0.95, 0.5, 0, 3.3, -1.3, COLOR.bullMuzzle),
		pair(block("Nostril", 0.22, 0.26, 0.06, 0.36, 3.35, -1.57, COLOR.eye)),
		cyl("NoseRing", 0.08, 0.55, 0, 2.95, -1.6, COLOR.gold, { material = "Metal" }),
		pair(block("Eye", 0.42, 0.24, 0.08, 0.55, 4.05, -1.12, COLOR.glowRed, { material = "Neon" })),
		pair(block("Brow", 0.6, 0.15, 0.1, 0.55, 4.3, -1.13, COLOR.eye, { rot = { 0, 0, 20 } })),
		pair(block("Ear", 0.6, 0.3, 0.35, 1.4, 3.9, 0.1, COLOR.bullHide, { rot = { 0, 0, -15 } })),
		-- เขาใหญ่: ออกข้าง → ตั้งขึ้นโค้งเข้า → ปลายเข้ม
		pair(block("HornBase", 1.3, 0.5, 0.5, 1.75, 4.55, -0.1, COLOR.horn, { rot = { 0, 0, 15 } })),
		pair(block("HornRise", 0.45, 1.1, 0.45, 2.26, 5.13, -0.1, COLOR.horn, { rot = { 0, 0, 15 } })),
		pair(block("HornTip", 0.3, 0.5, 0.3, 2.01, 5.89, -0.1, COLOR.hornTip, { rot = { 0, 0, 25 } })),
	}),
}

--------------------------------------------------------------------------------
-- อ่านแบบ
--------------------------------------------------------------------------------

function MotherModels.getBlueprint(charId: string): Blueprint?
	return BLUEPRINTS[charId]
end

function MotherModels.hasBlueprint(charId: string): boolean
	return BLUEPRINTS[charId] ~= nil
end

-- charId ทุกตัวที่มีแบบ (เรียงชื่อ — ไว้เทสต์/debug)
function MotherModels.listCharIds(): { string }
	local ids = {}
	for charId in BLUEPRINTS do
		table.insert(ids, charId)
	end
	table.sort(ids)
	return ids
end

-- ท่าอนิเมชันของตัวที่เป็น rig (nil = ไม่มี rig · ใช้ท่ากระเด้ง/ลอยแทน)
function MotherModels.getAnimations(charId: string): { [string]: number }?
	local blueprint = BLUEPRINTS[charId]
	if blueprint and blueprint.rig == "R6" then
		return MotherModels.R6_ANIMATIONS
	end
	return nil
end

-- ข้อต่อ R6 จากขนาด/ตำแหน่งชิ้น rig (ท่ายืนตรง) — จุดหมุนตามสัดส่วนของ rig R6 มาตรฐาน:
--   RootJoint กลาง Torso · Neck ขอบบน Torso · Shoulder ขอบข้าง Torso ต่ำจากบนแขนเท่าครึ่งความกว้างแขน ·
--   Hip ขอบล่าง Torso ที่ขอบนอกของขา · c0/c1 = จุดหมุน − กลางชิ้น (ชิ้น rig ไม่หมุน)
-- ⚠️ กับขนาด R6 จริง (Torso 2×2×1 · แขน/ขา 1×2×1 · หัว 2×1×1) ได้ C0/C1 ตรงกับของ Roblox ทุกข้อ (tests/models.spec.luau)
function MotherModels.computeR6Joints(parts: { PartSpec }): { JointSpec }?
	local byName: { [string]: PartSpec } = {}
	for _, part in parts do
		byName[part.name] = part
	end
	for _, name in MotherModels.R6_PARTS do
		if not byName[name] then
			return nil
		end
	end
	local function center(name: string): Vec
		return byName[name].pos
	end
	local function half(name: string, axis: number): number
		return byName[name].size[axis] / 2
	end
	local function joint(name: string, part0: string, part1: string, point: Vec, rotation: { number }): JointSpec
		local c0, c1 = center(part0), center(part1)
		return {
			name = name,
			part0 = part0,
			part1 = part1,
			c0 = { point[1] - c0[1], point[2] - c0[2], point[3] - c0[3] },
			c1 = { point[1] - c1[1], point[2] - c1[2], point[3] - c1[3] },
			rotation = rotation,
		}
	end
	local torso = center("Torso")
	local torsoTop = torso[2] + half("Torso", 2)
	local torsoBottom = torso[2] - half("Torso", 2)
	local function shoulder(side: number, armName: string): Vec
		local arm = center(armName)
		return { torso[1] + side * half("Torso", 1), arm[2] + half(armName, 2) - half(armName, 1), arm[3] }
	end
	local function hip(side: number, legName: string): Vec
		local leg = center(legName)
		return { leg[1] + side * half(legName, 1), torsoBottom, leg[3] }
	end
	return {
		joint("RootJoint", "HumanoidRootPart", "Torso", torso, R6_ROOT_ROTATION),
		joint("Neck", "Torso", "Head", { torso[1], torsoTop, torso[3] }, R6_ROOT_ROTATION),
		joint("Right Shoulder", "Torso", "Right Arm", shoulder(1, "Right Arm"), R6_RIGHT_ROTATION),
		joint("Left Shoulder", "Torso", "Left Arm", shoulder(-1, "Left Arm"), R6_LEFT_ROTATION),
		joint("Right Hip", "Torso", "Right Leg", hip(1, "Right Leg"), R6_RIGHT_ROTATION),
		joint("Left Hip", "Torso", "Left Leg", hip(-1, "Left Leg"), R6_LEFT_ROTATION),
	}
end

function MotherModels.getPartCount(charId: string): number
	local blueprint = BLUEPRINTS[charId]
	return if blueprint then #blueprint.parts else 0
end

-- เมทริกซ์หมุนแบบ CFrame.Angles(rx, ry, rz) = Rx · Ry · Rz (องศา)
local function rotationMatrix(rot: Vec?): { { number } }
	if not rot then
		return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
	end
	local ax, ay, az = math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3])
	local cx, sx = math.cos(ax), math.sin(ax)
	local cy, sy = math.cos(ay), math.sin(ay)
	local cz, sz = math.cos(az), math.sin(az)
	local rx = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local ry = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local rz = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	local function mul(a: { { number } }, b: { { number } }): { { number } }
		local out = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
		for i = 1, 3 do
			for j = 1, 3 do
				out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
			end
		end
		return out
	end
	return mul(mul(rx, ry), rz)
end

-- กล่องล้อมรอบแนวแกนโลกของชิ้นเดียว (กล่องหมุนแล้ว) · คืน (min, max)
function MotherModels.getPartBounds(part: PartSpec): (Vec, Vec)
	local m = rotationMatrix(part.rot)
	local half = { part.size[1] / 2, part.size[2] / 2, part.size[3] / 2 }
	local lo, hi = {}, {}
	for axis = 1, 3 do
		local extent = math.abs(m[axis][1]) * half[1] + math.abs(m[axis][2]) * half[2] + math.abs(m[axis][3]) * half[3]
		lo[axis] = part.pos[axis] - extent
		hi[axis] = part.pos[axis] + extent
	end
	return lo, hi
end

-- กล่องล้อมรอบทั้งตัว (studs ออกแบบ · ก่อนคูณน้ำหนัก/คลาส) = ของเดียวกับ Model:GetBoundingBox()
-- เพราะลำตัว (PrimaryPart) ไม่หมุน · คืน (min, max, size)
function MotherModels.getBounds(charId: string): (Vec?, Vec?, Vec?)
	local blueprint = BLUEPRINTS[charId]
	if not blueprint then
		return nil, nil, nil
	end
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, part in blueprint.parts do
		local partLo, partHi = MotherModels.getPartBounds(part)
		for axis = 1, 3 do
			lo[axis] = math.min(lo[axis], partLo[axis])
			hi[axis] = math.max(hi[axis], partHi[axis])
		end
	end
	return lo, hi, { hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3] }
end

-- ตรวจแบบทุกตัว · คืนรายการปัญหา (ว่าง = ผ่าน) — เทสต์เรียก + PenService warn ตอนบูต
function MotherModels.validate(): { string }
	local problems: { string } = {}
	local function fail(message: string)
		table.insert(problems, message)
	end
	for charId, blueprint in BLUEPRINTS do
		local isRig = blueprint.rig == "R6"
		if blueprint.rig ~= nil and not isRig then
			fail(`{charId}: rig รองรับแค่ "R6"`)
		end
		if isRig and blueprint.motion ~= "animated" then
			fail(`{charId}: rig ต้องใช้ motion = "animated" (เล่นอนิเมชันจริง ไม่กระเด้งเอง)`)
		end
		if not isRig and blueprint.motion ~= "hop" and blueprint.motion ~= "float" then
			fail(`{charId}: motion ต้องเป็น "hop" หรือ "float" (ไม่มี rig)`)
		end
		if isRig then
			local partNames: { [string]: PartSpec } = {}
			for _, part in blueprint.parts do
				partNames[part.name] = part
			end
			for _, rigName in MotherModels.R6_PARTS do
				local rigPart = partNames[rigName]
				if not rigPart then
					fail(`{charId}: rig R6 ขาดชิ้น "{rigName}"`)
				elseif rigPart.rot or rigPart.attach then
					fail(`{charId}.{rigName}: ชิ้น rig ห้ามหมุนและห้ามมี attach`)
				end
			end
			local root = partNames.HumanoidRootPart
			if root and not root.primary then
				fail(`{charId}: HumanoidRootPart ต้องเป็น PrimaryPart (ชิ้นเดียวที่ Anchored)`)
			end
			for _, part in blueprint.parts do
				if table.find(MotherModels.R6_PARTS, part.name) == nil then
					local target = part.attach
					if target == nil or partNames[target] == nil or table.find(MotherModels.R6_PARTS, target) == nil then
						fail(`{charId}.{part.name}: ชิ้นตกแต่งของ rig ต้อง attach กับชิ้น rig (ได้ {tostring(target)})`)
					end
				end
			end
		else
			for _, part in blueprint.parts do
				if part.attach then
					fail(`{charId}.{part.name}: attach ใช้ได้เฉพาะแบบที่เป็น rig`)
				end
			end
		end
		if #blueprint.parts > MotherModels.PART_LIMIT then
			fail(`{charId}: {#blueprint.parts} ชิ้น เกินเพดาน {MotherModels.PART_LIMIT}`)
		end
		local primaries = 0
		local names: { [string]: boolean } = {}
		for _, part in blueprint.parts do
			if names[part.name] then
				fail(`{charId}: ชื่อชิ้น "{part.name}" ซ้ำ`)
			end
			names[part.name] = true
			local size = part.size
			if size[1] <= 0 or size[2] <= 0 or size[3] <= 0 then
				fail(`{charId}.{part.name}: ขนาดต้องมากกว่า 0 ทุกแกน`)
			end
			if part.shape == "Ball" and not (size[1] == size[2] and size[2] == size[3]) then
				fail(`{charId}.{part.name}: Ball ต้องขนาดเท่ากันทั้งสามแกน`)
			end
			if part.shape == "Cylinder" and size[2] ~= size[3] then
				fail(`{charId}.{part.name}: Cylinder ต้องมี Y = Z (เส้นผ่านศูนย์กลาง)`)
			end
			if part.primary then
				primaries += 1
				local rot = part.rot
				if rot and (rot[1] ~= 0 or rot[2] ~= 0 or rot[3] ~= 0) then
					fail(`{charId}.{part.name}: PrimaryPart ห้ามหมุน (กล่องล้อมรอบใช้ทิศของชิ้นนี้)`)
				end
			end
		end
		if primaries ~= 1 then
			fail(`{charId}: ต้องมี PrimaryPart 1 ชิ้นพอดี (มี {primaries})`)
		end
		local lo = MotherModels.getBounds(charId)
		if lo and math.abs(lo[2]) > 0.05 then
			fail(`{charId}: เท้าต้องแตะ Y = 0 (ต่ำสุดอยู่ที่ {lo[2]})`)
		end
	end
	return problems
end

--------------------------------------------------------------------------------
-- สร้าง Instance (Roblox เท่านั้น)
--------------------------------------------------------------------------------

-- สร้างโมเดลจากแบบ — nil = charId นี้ไม่มีแบบ · CanCollide/CanTouch/CanQuery ปิด · Massless ทุกชิ้น
-- ไม่มี rig: ทุกชิ้น Anchored (เหมือนที่ PenService บังคับกับโมเดล mesh: ขยับด้วย PivotTo ล้วน ผู้เล่นเดินทะลุได้)
-- rig R6: Anchored แค่ HumanoidRootPart · ชิ้น rig ต่อ Motor6D (ทิศ R6) · ชิ้นตกแต่ง Weld กับชิ้นที่ attach
--   ⚠️ ตั้ง CFrame ทุกชิ้นให้ตรงท่ายืนก่อนต่อข้อต่อ — ต้นแบบใน ReplicatedStorage/ViewportFrame ไม่มีฟิสิกส์มาจัดให้
function MotherModels.build(charId: string): Model?
	local blueprint = BLUEPRINTS[charId]
	if not blueprint then
		return nil
	end
	local isRig = blueprint.rig == "R6"
	local model = Instance.new("Model")
	model.Name = charId
	local built: { [string]: BasePart } = {}
	for _, partSpec in blueprint.parts do
		local part: BasePart
		if partSpec.shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			local plain = Instance.new("Part")
			plain.Shape = (Enum.PartType :: any)[partSpec.shape]
			part = plain
		end
		part.Name = partSpec.name
		part.Size = Vector3.new(partSpec.size[1], partSpec.size[2], partSpec.size[3])
		local rot = partSpec.rot
		local cframe = CFrame.new(partSpec.pos[1], partSpec.pos[2], partSpec.pos[3])
		if rot then
			cframe *= CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		end
		part.CFrame = cframe
		part.Color = Color3.fromRGB(partSpec.color[1], partSpec.color[2], partSpec.color[3])
		part.Material = (Enum.Material :: any)[partSpec.material or "SmoothPlastic"]
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Transparency = partSpec.transparency or 0
		part.Anchored = not isRig or partSpec.name == "HumanoidRootPart"
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.Parent = model
		built[partSpec.name] = part
		if partSpec.primary then
			model.PrimaryPart = part
		end
	end
	if isRig then
		-- ข้อต่อ R6: ชื่อ + part0/part1 + ทิศตาม rig มาตรฐาน (อนิเมชันของ Roblox หาข้อต่อจากชื่อชิ้น)
		for _, jointSpec in MotherModels.computeR6Joints(blueprint.parts) :: { JointSpec } do
			local r = jointSpec.rotation
			local motor = Instance.new("Motor6D")
			motor.Name = jointSpec.name
			motor.Part0 = built[jointSpec.part0]
			motor.Part1 = built[jointSpec.part1]
			motor.C0 = CFrame.new(jointSpec.c0[1], jointSpec.c0[2], jointSpec.c0[3], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
			motor.C1 = CFrame.new(jointSpec.c1[1], jointSpec.c1[2], jointSpec.c1[3], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
			motor.Parent = built[jointSpec.part0]
		end
		-- ชิ้นตกแต่งติดกับชิ้น rig ที่ attach (Weld แบบกำหนด C0 เอง — แน่นอนกว่า WeldConstraint ตอนยังไม่อยู่ใน Workspace)
		for _, partSpec in blueprint.parts do
			local target = partSpec.attach
			if target then
				local part0, part1 = built[target], built[partSpec.name]
				local weld = Instance.new("Weld")
				weld.Name = "Attach"
				weld.Part0 = part0
				weld.Part1 = part1
				weld.C0 = part0.CFrame:Inverse() * part1.CFrame
				weld.Parent = part1
			end
		end
	end
	-- pivot = เท้ากลางตัว หันหน้า −Z (ลำตัวไม่หมุน → กล่องล้อมรอบแนวเดียวกับ pivot)
	model.WorldPivot = CFrame.new(0, 0, 0)
	model:SetAttribute("Motion", blueprint.motion)
	return model
end

return MotherModels
