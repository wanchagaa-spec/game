--!nocheck
-- egg-army-game :: ชุดเทสต์โมเดลตัวละคร (ประกอบจาก Part ในโค้ด · MotherModels) + เปลี่ยนชื่อ 2 ตัวละคร
--
-- ตรวจแบบ (ข้อมูลล้วน) นอก Studio: ทุกตัวละครมีโมเดล · ≤ 40 ชิ้น · มี PrimaryPart · รูปทรงถูกกติกา ·
-- ตัวใหญ่สุด (tier 7) ยังอยู่ในคอกไม่ทะลุรั้ว · ชื่อใหม่ + charId เดิม
-- การสร้าง Instance จริง (CanCollide/Anchored/ViewportFrame/เงาดำ) ตรวจใน tools/check-ui-smoke.py

local MotherModels = require("../src/shared/MotherModels")

return function(t, Config)
	local check = t.check
	local visual = Config.Balance.VisualScale
	local TIER7 = visual.WEIGHT_MULTIPLIER[#visual.WEIGHT_MULTIPLIER]

	----------------------------------------------------------------------------
	print("── เปลี่ยน 2 ตัวละคร: ชื่อใหม่ · charId/คลาส/ตัวคูณ/ลำดับเดิม ──")
	----------------------------------------------------------------------------
	do
		local bull = Config.getCharacter("yulai")
		local fan = Config.getCharacter("guanyin")
		check("yulai (charId เดิม) = ราชาปีศาจวัว", bull and bull.name, "ราชาปีศาจวัว")
		check("  ยังคลาส SS ×432", bull and bull.class == "SS" and Config.getCharacterMultiplier("yulai") == 432, true)
		check("guanyin (charId เดิม) = องค์หญิงพัดเหล็ก", fan and fan.name, "องค์หญิงพัดเหล็ก")
		check("  ยังคลาส S ×216", fan and fan.class == "S" and Config.getCharacterMultiplier("guanyin") == 216, true)
		check("ลำดับในดัชนีเดิม (yulai 1 · guanyin 2)", Config.CharacterOrder[1] == "yulai" and Config.CharacterOrder[2] == "guanyin", true)
		local leftovers = {}
		for charId, character in Config.Characters do
			if string.find(character.name, "ยูไล", 1, true) or string.find(character.name, "กวนอิม", 1, true) then
				table.insert(leftovers, charId)
			end
		end
		check("ไม่มีชื่อตัวละครที่ยังเป็นชื่อเดิม (ยูไล/กวนอิม)", #leftovers, 0)
	end

	----------------------------------------------------------------------------
	print("── ทุกตัวละครมีโมเดลประกอบจาก Part ครบ 12 ตัว (ลิงเลิกใช้ mesh แล้ว) · ไม่มีแบบเกิน ──")
	----------------------------------------------------------------------------
	do
		local missing, both, partCount = {}, {}, 0
		for _, charId in Config.CharacterOrder do
			local character = Config.getCharacter(charId)
			local hasMesh = character.modelAssetId ~= nil
			local hasParts = MotherModels.hasBlueprint(charId)
			if not hasMesh and not hasParts then
				table.insert(missing, charId)
			end
			if hasMesh and hasParts then
				table.insert(both, charId)
			end
			if hasParts then
				partCount += 1
			end
		end
		check("ทุก charId ใน Config มีโมเดล", table.concat(missing, ","), "")
		check("  ไม่มีตัวไหนมีทั้ง mesh และแบบ Part", table.concat(both, ","), "")
		check("  ประกอบจาก Part ครบ 12 ตัว", partCount, 12)
		check("  ลิงเลิกใช้ mesh (ไม่มี modelAssetId/animationIds แล้ว)",
			Config.getCharacter("monkey").modelAssetId == nil and Config.getCharacter("monkey").animationIds == nil, true)
		local stray = {}
		for _, charId in MotherModels.listCharIds() do
			if Config.getCharacter(charId) == nil then
				table.insert(stray, charId)
			end
		end
		check("  ไม่มีแบบของ charId ที่ไม่มีใน Config", table.concat(stray, ","), "")
		check("ชื่อต้นแบบ: ประกอบจาก Part = charId", Config.getMotherTemplateName("monkey"), "monkey")
		check("  (หมู)", Config.getMotherTemplateName("pig"), "pig")
	end

	----------------------------------------------------------------------------
	print("── แบบถูกกติกา: ≤ 40 ชิ้น · PrimaryPart 1 ชิ้นไม่หมุน · Ball เท่ากันสามแกน · เท้าแตะพื้น ──")
	----------------------------------------------------------------------------
	do
		local problems = MotherModels.validate()
		for _, problem in problems do
			print(`   ⚠ {problem}`)
		end
		check("MotherModels.validate() ไม่มีปัญหา", #problems, 0)
		check("เพดาน 40 ชิ้น", MotherModels.PART_LIMIT, 40)
		local counts = {}
		for _, charId in Config.CharacterOrder do
			if MotherModels.hasBlueprint(charId) then
				local count = MotherModels.getPartCount(charId)
				check(`  {charId} {count} ชิ้น ≤ 40`, count <= 40 and count > 0, true)
				table.insert(counts, `{charId} {count}`)
			end
		end
		print(`   จำนวนชิ้น: {table.concat(counts, " · ")}`)
		check("ปลาลอย (float) แทนการเดิน", MotherModels.getBlueprint("fish").motion, "float")
		check("  ตัวอื่นกระเด้งตอนเดิน (hop)", MotherModels.getBlueprint("pig").motion, "hop")
		-- ตัวละครที่ถือของ: ของอยู่มือขวา (+X) · หน้าหัน −Z (ส่วนหน้าสุดต้องอยู่ฝั่ง −Z)
		local lo, hi = MotherModels.getBounds("horse")
		check("ม้าหันหน้า −Z (จมูกยื่นไปทาง −Z มากกว่าหางไป +Z)", -lo[3] > hi[3], true)
	end

	----------------------------------------------------------------------------
	print("── ขนาดตามคลาส: C 1.0 → SS 1.5 · ราชาปีศาจวัวตัวใหญ่สุด ──")
	----------------------------------------------------------------------------
	do
		check("C = 1.0", Config.getMotherClassScale("C"), 1)
		check("SS = 1.5", Config.getMotherClassScale("SS"), 1.5)
		check("คลาสแปลก = 1", Config.getMotherClassScale("??"), 1)
		local tallestId, tallest = nil, 0
		for _, charId in MotherModels.listCharIds() do
			local _, _, size = MotherModels.getBounds(charId)
			local height = size[2] * Config.getMotherClassScale(Config.getCharacter(charId).class)
			if height > tallest then
				tallestId, tallest = charId, height
			end
		end
		check(`ตัวใหญ่สุดตอน tier 1 = ราชาปีศาจวัว (สูง {string.format("%.1f", tallest)})`, tallestId, "yulai")
	end

	----------------------------------------------------------------------------
	print("── ตัวใหญ่สุด (tier 7) ยังอยู่ในคอก: ครึ่งเส้นทแยงพื้น ≤ ครึ่งพื้นที่ในรั้ว ──")
	----------------------------------------------------------------------------
	do
		local pen = Config.MapDimensions.Pen
		local innerHalf = math.min(pen.Size.X, pen.Size.Y) / 2 - pen.EdgeMargin
		local worst, worstId = 0, nil
		local report = {}
		for _, charId in MotherModels.listCharIds() do
			local _, _, size = MotherModels.getBounds(charId)
			local scale = TIER7 * visual.MOTHER_PEN_SHRINK * Config.getMotherClassScale(Config.getCharacter(charId).class)
			local halfDiagonal = math.sqrt((size[1] * scale) ^ 2 + (size[3] * scale) ^ 2) / 2
			check(`  {charId}: tier 7 ครึ่งเส้นทแยง {string.format("%.1f", halfDiagonal)} ≤ {innerHalf}`, halfDiagonal <= innerHalf, true)
			if halfDiagonal > worst then
				worst, worstId = halfDiagonal, charId
			end
			table.insert(report, `{charId} สูง {string.format("%.1f", size[2] * scale)}`)
		end
		print(`   tier 7: {table.concat(report, " · ")}`)
		print(`   กว้างสุด = {worstId} ครึ่งเส้นทแยง {string.format("%.1f", worst)} / ในรั้ว {innerHalf}`)
	end

	----------------------------------------------------------------------------
	print("── rig R6 (ลิง): ข้อต่อตรง rig R6 มาตรฐานของ Roblox · อนิเมชันตั้งต้นของ Roblox ──")
	----------------------------------------------------------------------------
	do
		local function vecEq(a, b)
			return math.abs(a[1] - b[1]) < 1e-9 and math.abs(a[2] - b[2]) < 1e-9 and math.abs(a[3] - b[3]) < 1e-9
		end
		-- rig R6 ขนาดจริงของ Roblox (ยืนตรง · กลางลำตัว Y = 3) → ต้องได้ C0/C1 เท่ากับ rig R6 ตั้งต้นทุกข้อ
		local function rigPart(name, sx, sy, sz, x, y)
			return { name = name, shape = "Block", size = { sx, sy, sz }, pos = { x, y, 0 }, color = { 0, 0, 0 } }
		end
		local standard = MotherModels.computeR6Joints({
			rigPart("HumanoidRootPart", 2, 2, 1, 0, 3),
			rigPart("Torso", 2, 2, 1, 0, 3),
			rigPart("Head", 2, 1, 1, 0, 4.5),
			rigPart("Right Arm", 1, 2, 1, 1.5, 3),
			rigPart("Left Arm", 1, 2, 1, -1.5, 3),
			rigPart("Right Leg", 1, 2, 1, 0.5, 1),
			rigPart("Left Leg", 1, 2, 1, -0.5, 1),
		})
		-- ค่าจาก rig R6 ตั้งต้นของ Roblox (C0 / C1 ตำแหน่ง)
		local expected = {
			RootJoint = { { 0, 0, 0 }, { 0, 0, 0 } },
			Neck = { { 0, 1, 0 }, { 0, -0.5, 0 } },
			["Right Shoulder"] = { { 1, 0.5, 0 }, { -0.5, 0.5, 0 } },
			["Left Shoulder"] = { { -1, 0.5, 0 }, { 0.5, 0.5, 0 } },
			["Right Hip"] = { { 1, -1, 0 }, { 0.5, 1, 0 } },
			["Left Hip"] = { { -1, -1, 0 }, { -0.5, 1, 0 } },
		}
		local rotations = {
			RootJoint = { -1, 0, 0, 0, 0, 1, 0, 1, 0 },
			Neck = { -1, 0, 0, 0, 0, 1, 0, 1, 0 },
			["Right Shoulder"] = { 0, 0, 1, 0, 1, 0, -1, 0, 0 },
			["Left Shoulder"] = { 0, 0, -1, 0, 1, 0, 1, 0, 0 },
			["Right Hip"] = { 0, 0, 1, 0, 1, 0, -1, 0, 0 },
			["Left Hip"] = { 0, 0, -1, 0, 1, 0, 1, 0, 0 },
		}
		check("rig ขนาดมาตรฐาน: ได้ 6 ข้อต่อ", standard and #standard, 6)
		for _, joint in standard or {} do
			local want = expected[joint.name]
			check(`  {joint.name}: C0/C1 ตรง rig R6 ของ Roblox`, want ~= nil and vecEq(joint.c0, want[1]) and vecEq(joint.c1, want[2]), true)
			check(`  {joint.name}: ทิศข้อต่อตรง R6`, table.concat(joint.rotation, ","), table.concat(rotations[joint.name], ","))
		end
		check("ขาดชิ้น rig → nil", MotherModels.computeR6Joints({ rigPart("Torso", 2, 2, 1, 0, 3) }), nil)

		local monkey = MotherModels.getBlueprint("monkey")
		check("ลิงเป็น rig R6", monkey.rig, "R6")
		check("  motion = animated (ไม่กระเด้งเอง)", monkey.motion, "animated")
		local byName = {}
		for _, part in monkey.parts do
			byName[part.name] = part
		end
		local joints = MotherModels.computeR6Joints(monkey.parts)
		check("  ข้อต่อครบ 6", joints and #joints, 6)
		local consistent = true
		for _, joint in joints or {} do
			-- ท่ายืน: กลาง part1 = กลาง part0 + c0 − c1 (ชิ้นวางตรงข้อต่อพอดี ไม่มีอะไรกระโดดตอนต่อข้อ)
			local p0, p1 = byName[joint.part0].pos, byName[joint.part1].pos
			local want = { p0[1] + joint.c0[1] - joint.c1[1], p0[2] + joint.c0[2] - joint.c1[2], p0[3] + joint.c0[3] - joint.c1[3] }
			if not vecEq(want, p1) then
				consistent = false
			end
		end
		check("  ท่ายืนตรงกับข้อต่อทุกข้อ", consistent, true)
		check("  HumanoidRootPart = PrimaryPart ใส (ไม่เห็น)", byName.HumanoidRootPart.primary == true and byName.HumanoidRootPart.transparency == 1, true)
		local _, _, size = MotherModels.getBounds("monkey")
		check(`  สูง {string.format("%.2f", size[2])} ≈ 5 (เท่าลิง mesh เดิม · MOTHER_MESH_BASE_HEIGHT)`, size[2] > 4.5 and size[2] < 5.5, true)
		local animations = MotherModels.getAnimations("monkey")
		check("อนิเมชันของ Roblox: เดิน 180426354", animations and animations.walk, 180426354)
		check("  ยืน 180435571", animations and animations.idle, 180435571)
		check("  เหวี่ยงแขน (punch) 129967390", animations and animations.punch, 129967390)
		check("  ไม่ใส่ท่านั่ง (R6 ต้องมีที่นั่ง ไม่งั้นขาลอย)", animations and animations.sit, nil)
		check("ตัวที่ไม่มี rig → ไม่มีอนิเมชัน", MotherModels.getAnimations("pig"), nil)
	end
end
