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
	print("── ทุกตัวละครมีโมเดล: mesh (ลิง) หรือประกอบจาก Part (11 ตัว) · ไม่มีแบบเกิน ──")
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
		check("  ไม่มีตัวไหนมีทั้ง mesh และแบบ Part (ลิงคง mesh เดิม)", table.concat(both, ","), "")
		check("  ประกอบจาก Part 11 ตัว", partCount, 11)
		check("  ลิงยังเป็น mesh เดิม (ไม่ถูกเปลี่ยน)", Config.getCharacter("monkey").modelAssetId, 109724272624838)
		local stray = {}
		for _, charId in MotherModels.listCharIds() do
			if Config.getCharacter(charId) == nil then
				table.insert(stray, charId)
			end
		end
		check("  ไม่มีแบบของ charId ที่ไม่มีใน Config", table.concat(stray, ","), "")
		check("ชื่อต้นแบบ: mesh = เลข asset (เดิม)", Config.getMotherTemplateName("monkey"), "109724272624838")
		check("  ประกอบจาก Part = charId", Config.getMotherTemplateName("pig"), "pig")
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
end
