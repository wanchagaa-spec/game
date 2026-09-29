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
		check("  หมูเล่นอนิเมชันจริง (animated · ไม่กระเด้งเอง)", MotherModels.getBlueprint("pig").motion, "animated")
		-- ตัวละครที่ถือของ: ของอยู่มือขวา (+X) · หน้าหัน −Z (ส่วนหน้าสุดต้องอยู่ฝั่ง −Z)
		local lo, hi = MotherModels.getBounds("horse")
		check("ม้าหันหน้า −Z (จมูกยื่นไปทาง −Z มากกว่าหางไป +Z)", -lo[3] > hi[3], true)
	end

	----------------------------------------------------------------------------
	print("── หมู + ปลาทรงกล่อง (ผู้ใช้สั่ง: เลิกทรงกลม — กลมแล้วดูอ้วน) ──")
	----------------------------------------------------------------------------
	do
		for _, charId in { "pig", "fish" } do
			local balls = {}
			for _, part in MotherModels.getBlueprint(charId).parts do
				if part.shape == "Ball" or part.shape == "Cylinder" then
					table.insert(balls, part.name)
				end
			end
			check(`{charId}: ไม่มีชิ้นทรงกลม/ทรงกระบอก`, table.concat(balls, ","), "")
		end
		local _, _, pigSize = MotherModels.getBounds("pig")
		local _, _, fishSize = MotherModels.getBounds("fish")
		check(`หมูยาวกว่ากว้าง (ตัวยาวแบบหมู · {string.format("%.2f × %.2f", pigSize[1], pigSize[3])})`, pigSize[3] > pigSize[1] * 1.5, true)
		check(`ปลาตัวยาวกว่าสูง 1.5 เท่า (ไม่อ้วนกลม · {string.format("%.2f × %.2f", fishSize[3], fishSize[2])})`, fishSize[3] > fishSize[2] * 1.5, true)
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
	print("── rig R6: ข้อต่อตรง rig R6 มาตรฐานของ Roblox · อนิเมชันตั้งต้นของ Roblox ──")
	----------------------------------------------------------------------------
	local function vecEq(a, b)
		return math.abs(a[1] - b[1]) < 1e-9 and math.abs(a[2] - b[2]) < 1e-9 and math.abs(a[3] - b[3]) < 1e-9
	end
	do
		-- rig R6 ขนาดจริงของ Roblox (ยืนตรง · กลางลำตัว Y = 3) → ต้องได้ C0/C1 เท่ากับ rig R6 ตั้งต้นทุกข้อ
		local function rigPart(name, sx, sy, sz, x, y)
			return { name = name, shape = "Block", size = { sx, sy, sz }, pos = { x, y, 0 }, color = { 0, 0, 0 } }
		end
		local standardParts = {
			rigPart("HumanoidRootPart", 2, 2, 1, 0, 3),
			rigPart("Torso", 2, 2, 1, 0, 3),
			rigPart("Head", 2, 1, 1, 0, 4.5),
			rigPart("Right Arm", 1, 2, 1, 1.5, 3),
			rigPart("Left Arm", 1, 2, 1, -1.5, 3),
			rigPart("Right Leg", 1, 2, 1, 0.5, 1),
			rigPart("Left Leg", 1, 2, 1, -0.5, 1),
		}
		local standard = MotherModels.computeR6Joints(standardParts)
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
			check(`  {joint.name}: ทิศ R6 เป็นการหมุนจริง`, MotherModels.isRotation(joint.rotation), true)
		end
		check("ขาดชิ้น rig → nil", MotherModels.computeR6Joints({ rigPart("Torso", 2, 2, 1, 0, 3) }), nil)
		-- jointOverrides: แทนเฉพาะข้อที่ระบุ · ท่ายืนยังตรง
		local moved = MotherModels.computeR6Joints(standardParts, { ["Right Hip"] = { point = { 0.5, 2, 0.3 } } })
		local byJoint = {}
		for _, joint in moved or {} do
			byJoint[joint.name] = joint
		end
		check("override จุดหมุนสะโพกขวา → C0 = จุดใหม่ − กลางลำตัว", vecEq(byJoint["Right Hip"].c0, { 0.5, -1, 0.3 }), true)
		check("  C1 = จุดใหม่ − กลางขา", vecEq(byJoint["Right Hip"].c1, { 0, 1, 0.3 }), true)
		check("  ข้ออื่นไม่เปลี่ยน", vecEq(byJoint["Left Hip"].c0, { -1, -1, 0 }), true)
		check("  ทิศเดิม (ไม่ได้ override)", table.concat(byJoint["Right Hip"].rotation, ","), "0,0,1,0,1,0,-1,0,0")
		check("isRotation: กระจกเงา (det −1) = ไม่ใช่", MotherModels.isRotation({ -1, 0, 0, 0, 1, 0, 0, 0, 1 }), false)
		check("isRotation: ไม่ครบ 9 ค่า = ไม่ใช่", MotherModels.isRotation({ 1, 0, 0 }), false)
	end

	----------------------------------------------------------------------------
	print("── ทุกตัวเป็น rig R6 (ผู้ใช้สั่ง \"ใส่อนิเมชันให้ทุกตัว\") · ท่ายืนตรงข้อต่อ · ชุดท่าถูกตัว ──")
	----------------------------------------------------------------------------
	local BIPEDS = { "monkey", "bajie", "wujing", "tang", "wukong", "guanyin", "jade_emperor", "yulai" }
	local QUADRUPEDS = { "pig", "horse", "dragon_horse" }
	do
		local rigCount = 0
		for _, charId in Config.CharacterOrder do
			local blueprint = MotherModels.getBlueprint(charId)
			if blueprint and blueprint.rig == "R6" then
				rigCount += 1
			end
			local byName = {}
			for _, part in blueprint.parts do
				byName[part.name] = part
			end
			local joints = MotherModels.getJoints(charId)
			check(`{charId}: rig R6 ข้อต่อครบ 6`, joints and #joints, 6)
			local consistent = true
			for _, joint in joints or {} do
				-- ท่ายืน: กลาง part1 = กลาง part0 + c0 − c1 (ชิ้นวางตรงข้อต่อพอดี ไม่มีอะไรกระโดดตอนต่อข้อ)
				local p0, p1 = byName[joint.part0].pos, byName[joint.part1].pos
				local want = { p0[1] + joint.c0[1] - joint.c1[1], p0[2] + joint.c0[2] - joint.c1[2], p0[3] + joint.c0[3] - joint.c1[3] }
				if not vecEq(want, p1) or not MotherModels.isRotation(joint.rotation) then
					consistent = false
				end
			end
			check(`  ท่ายืนตรงกับข้อต่อทุกข้อ · ทิศเป็นการหมุนจริง`, consistent, true)
			local root = byName.HumanoidRootPart
			check(`  HumanoidRootPart = PrimaryPart ใส (ไม่เห็น) อยู่กลางลำตัว`,
				root.primary == true and root.transparency == 1 and vecEq(root.pos, byName.Torso.pos), true)
			check(`  ความเร็วท่าเดิน 0.3–0.8 (แม่เดินช้ากว่าคน Roblox มาก)`,
				blueprint.walkAnimSpeed ~= nil and blueprint.walkAnimSpeed >= 0.3 and blueprint.walkAnimSpeed <= 0.8, true)
		end
		check("rig R6 ครบ 12 ตัว", rigCount, 12)

		for _, charId in BIPEDS do
			local animations = MotherModels.getAnimations(charId)
			check(`{charId} (คน): เดิน/ยืน/เหวี่ยงแขน`, animations and animations.walk == 180426354 and animations.idle == 180435571
				and animations.punch == 129967390, true)
			check(`  motion = animated`, MotherModels.getBlueprint(charId).motion, "animated")
		end
		for _, charId in { "pig", "horse", "dragon_horse", "fish" } do
			local animations = MotherModels.getAnimations(charId)
			check(`{charId} (สัตว์): เดิน/ยืน ไม่มีเหวี่ยงแขน (ขาหน้า/ครีบยกทะลุหัว)`,
				animations and animations.walk == 180426354 and animations.idle == 180435571 and animations.punch == nil, true)
		end
		check("ไม่มีตัวไหนใส่ท่านั่ง (R6 ต้องมีที่นั่ง ไม่งั้นขาลอย)", MotherModels.R6_ANIMATIONS.sit == nil and MotherModels.R6_BASIC_ANIMATIONS.sit == nil, true)
		check("charId ไม่มีแบบ → ไม่มีอนิเมชัน", MotherModels.getAnimations("ghost_char"), nil)
		check("  ไม่มีข้อต่อ", MotherModels.getJoints("ghost_char"), nil)

		local _, _, monkeySize = MotherModels.getBounds("monkey")
		check(`ลิงสูง {string.format("%.2f", monkeySize[2])} ≈ 5 (เท่าลิง mesh เดิม · MOTHER_MESH_BASE_HEIGHT)`, monkeySize[2] > 4.5 and monkeySize[2] < 5.5, true)
	end

	----------------------------------------------------------------------------
	print("── สัตว์สี่ขา: ขาหน้า = แขน · ขาหลัง = ขา · หมุนจากบนสุดของขา · ขาทแยงก้าวพร้อมกัน ──")
	----------------------------------------------------------------------------
	do
		for _, charId in QUADRUPEDS do
			local byName = {}
			for _, part in MotherModels.getBlueprint(charId).parts do
				byName[part.name] = part
			end
			check(`{charId}: ขาหน้า (แขน) อยู่หน้า −Z · ขาหลัง (ขา) อยู่หลัง +Z`,
				byName["Right Arm"].pos[3] < 0 and byName["Left Arm"].pos[3] < 0 and byName["Right Leg"].pos[3] > 0 and byName["Left Leg"].pos[3] > 0, true)
			for _, joint in MotherModels.getJoints(charId) do
				if joint.name ~= "RootJoint" and joint.name ~= "Neck" then
					local limb = byName[joint.part1]
					local pivotY = limb.pos[2] + joint.c1[2]
					check(`  {joint.name}: หมุนจากบนสุดของขา (Y {string.format("%.2f", pivotY)})`,
						math.abs(pivotY - (limb.pos[2] + limb.size[2] / 2)) < 1e-6 and math.abs(joint.c1[1]) < 1e-6 and math.abs(joint.c1[3]) < 1e-6, true)
					-- ทิศยังเป็น R6 เดิม → แกว่งหน้า-หลังรอบแกน X · ท่าเดิน R6 = แขนขวาไปพร้อมขาซ้าย = ขาทแยง (เดินเหยาะ)
					check(`  {joint.name}: ทิศ R6 เดิม (แกว่งหน้า-หลัง)`, math.abs(joint.rotation[3]) + math.abs(joint.rotation[7]), 2)
				end
			end
		end
	end

	----------------------------------------------------------------------------
	print("── ปลา: ลอย + rig · ครีบพายตามแขน · หางส่ายซ้าย-ขวาตามขาขวา ──")
	----------------------------------------------------------------------------
	do
		local fish = MotherModels.getBlueprint("fish")
		check("ปลา motion = float + rig R6 (ลอยขึ้นลง + อนิเมชันซ้อน)", fish.motion == "float" and fish.rig == "R6", true)
		local attached = {}
		for _, part in fish.parts do
			if part.attach then
				attached[part.name] = part.attach
			end
		end
		check("  ครีบติดแขน (ขวา/ซ้าย)", attached.FinR == "Right Arm" and attached.FinL == "Left Arm", true)
		check("  หางบน/ล่างติดขาขวาทั้งคู่ (ไม่แยกกรรไกร)", attached.TailTop == "Right Leg" and attached.TailBottom == "Right Leg", true)
		local hip
		for _, joint in MotherModels.getJoints("fish") do
			if joint.name == "Right Hip" then
				hip = joint
			end
		end
		local r = hip.rotation
		-- แกน Z ของข้อต่อ (คอลัมน์ที่ 3: R02, R12, R22) = แกนที่อนิเมชันแกว่ง → ต้องเป็นแกนตั้งของโลก
		check("  สะโพกขวาแกว่งรอบแกนตั้ง (หางส่ายข้าง ไม่ใช่พับขึ้นลง)", `{r[3]},{r[6]},{r[9]}`, "0,1,0")
		check("  = TAIL_WAG_ROTATION · เป็นการหมุนจริง", table.concat(r, ",") == table.concat(MotherModels.TAIL_WAG_ROTATION, ",")
			and MotherModels.isRotation(r), true)
		local torso
		for _, part in fish.parts do
			if part.name == "Torso" then
				torso = part
			end
		end
		check("  จุดหมุนหาง = กลางผิวหลังลำตัว", vecEq(hip.c0, { 0, 0, torso.size[3] / 2 }), true)
	end

	----------------------------------------------------------------------------
	print("── ชุดยาว (พระถัง · องค์หญิงพัดเหล็ก · เง็กเซียน): ขาใสในกระโปรง · รองเท้าติดขา · กระโปรงติดลำตัว ──")
	----------------------------------------------------------------------------
	do
		for _, charId in { "tang", "guanyin", "jade_emperor" } do
			local byName = {}
			for _, part in MotherModels.getBlueprint(charId).parts do
				byName[part.name] = part
			end
			check(`{charId}: ขาใส (มองไม่เห็น)`, byName["Right Leg"].transparency == 1 and byName["Left Leg"].transparency == 1, true)
			check(`  รองเท้าติดขาของตัวเอง`, byName.ShoeR.attach == "Right Leg" and byName.ShoeL.attach == "Left Leg", true)
			local skirt = byName.Skirt or byName.Robe
			check(`  กระโปรงติดลำตัว (ไม่แกว่งตามขา)`, skirt.attach, "Torso")
			check(`  ≤ 40 ชิ้นหลังเพิ่มชิ้น rig`, MotherModels.getPartCount(charId) <= 40, true)
		end
	end
end
