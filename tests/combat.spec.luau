--!nocheck
-- egg-army-game :: ชุดเทสต์ของ CombatService (Phase 3A)
--
-- ⚠️ ต่างจาก ProductionService: ไม่มี offline catch-up ให้ระบบนี้ ฟังก์ชันหลัก
-- (CombatService.tick) จึงรับ elapsedSeconds ตรง ๆ จากผู้เรียก ไม่ต้องปลอมนาฬิกา
-- ระบบเลย — ทุกเทสต์เรียกฟังก์ชันตรง ๆ ด้วยตัวเลขที่กำหนดเอง
--
-- ทุกอย่างที่นี่รันด้วย luau CLI ไม่ต้องเปิด Studio (CombatService ไม่แตะ Roblox API
-- เลยสักตัว ยกเว้น CombatService.start() ซึ่งเทสต์ชุดนี้ไม่เรียก)

local PlayerData = require("../src/shared/PlayerData")
local CombatService = require("../src/server/CombatService")
local Json = require("./jsonlite")

return function(t, Config)
	local check = t.check

	local function freshData()
		return PlayerData.createNew()
	end

	local function freshMeta()
		return CombatService.newMeta()
	end

	----------------------------------------------------------------------------
	-- init ด่านใหม่ถูกต้องตามสูตร
	----------------------------------------------------------------------------
	print("── init ด่านใหม่ถูกต้องตามสูตร (defendersRemaining/wallHpRemaining) ──")

	do
		local data = freshData()
		check("ด่าน 3 ยังไม่เคยแตะ (false)", data.stageProgress[3], false)

		CombatService.ensureStageStarted(data, 3)
		local progress = data.stageProgress[3]
		check(
			"defendersRemaining เริ่มจาก Config.getStageDefenderHp(3) (ไม่ใช่ getStageTotalHp ที่รวมกำแพงด้วย)",
			progress.defendersRemaining,
			Config.getStageDefenderHp(3)
		)
		check("wallHpRemaining เริ่มจาก Config.getStageWallHp(3)", progress.wallHpRemaining, Config.getStageWallHp(3))

		-- เรียกซ้ำต้อง idempotent ไม่รีเซ็ตค่าที่ตีไปแล้วทับ
		data.stageProgress[3].defendersRemaining = 10
		CombatService.ensureStageStarted(data, 3)
		check("เรียกซ้ำไม่รีเซ็ตค่าที่ตีไปแล้ว (idempotent)", data.stageProgress[3].defendersRemaining, 10)
	end

	----------------------------------------------------------------------------
	-- getActiveStage: ด่านแรกที่ยังไม่จบ ตีเรียงลำดับเท่านั้น
	----------------------------------------------------------------------------
	print("── getActiveStage: ด่านแรกที่ยังไม่จบ เรียงลำดับ ไม่ข้ามด่าน ──")

	do
		local data = freshData()
		check("ผู้เล่นใหม่ ด่านที่กำลังตี = 1", CombatService.getActiveStage(data), 1)

		data.stageProgress[1] = { defendersRemaining = 0, wallHpRemaining = 0 }
		check("ด่าน 1 พังแล้ว → ด่าน 2 เป็นด่านถัดไป", CombatService.getActiveStage(data), 2)

		for stage = 1, Config.Balance.Stage.COUNT do
			data.stageProgress[stage] = { defendersRemaining = 0, wallHpRemaining = 0 }
		end
		check("พังครบทุกด่านแล้ว → ไม่มีด่านให้ตี (nil)", CombatService.getActiveStage(data), nil)
	end

	----------------------------------------------------------------------------
	-- ทหารฝ่ายรับหมดก่อนถึงตีกำแพง + damage ส่วนเกินไหลไปกำแพงในตาเดียวกัน + เงินตามสัดส่วน HP
	----------------------------------------------------------------------------
	-- ด่าน 2: defenders=100 × DEFENDER_HP(100) = 10,000 · wallHp = 10,000×0.5 = 5,000
	-- เงิน/ตัว = KILL_DEFENDER_BASE(100) × MULTIPLIER(2)^(2-1) = 200 · เงินรวมด่าน = 100×200 = 20,000
	-- ⇒ เงิน/HP ทหาร 1 หน่วย = 20,000 ÷ 10,000 = 2 พอดี (เลขกลม ๆ คำนวณมือง่าย)
	print("── ทหารฝ่ายรับหมดก่อนถึงตีกำแพง + damage ส่วนเกินไหลไปกำแพงในตาเดียวกัน + เงินตามสัดส่วน HP ──")

	do
		local data = freshData()
		local meta = freshMeta()
		CombatService.ensureStageStarted(data, 2)
		check("defendersRemaining เริ่มต้น = 10,000 (100 ตัว × 100 HP)", data.stageProgress[2].defendersRemaining, 10000)
		check("wallHpRemaining เริ่มต้น = 5,000 (ครึ่งของทหาร)", data.stageProgress[2].wallHpRemaining, 5000)

		local startCoins = data.currency.coins

		-- ตาแรก: ตีเข้าไป 9,700 < ทหารฝ่ายรับที่เหลือ (10,000) → ตกที่ทหารฝ่ายรับทั้งหมด ไม่ทะลุกำแพง
		local d1, w1, coins1, cleared1 = CombatService.applyDamageToStage(data, meta, 2, 9700)
		check("damage < ทหารฝ่ายรับที่เหลือ → ตกที่ทหารฝ่ายรับทั้งหมด", d1, 9700)
		check("ไม่มีส่วนเกินไปกำแพง", w1, 0)
		check("กำแพงยัง HP เต็ม", data.stageProgress[2].wallHpRemaining, 5000)
		check("ทหารฝ่ายรับเหลือ 300", data.stageProgress[2].defendersRemaining, 300)
		check("ด่านยังไม่จบ", cleared1, false)
		check("เงินรางวัลตรงสัดส่วน HP ทหาร (9,700 × 2 บาท/HP)", coins1, 19400)

		-- ตาที่สอง: เหลือทหาร 300 แต่ตีเข้าไป 800 → ทหารตายครบ 300 ส่วนเกิน 500 ไหลไปกำแพงทันที
		local d2, w2, coins2, cleared2 = CombatService.applyDamageToStage(data, meta, 2, 800)
		check("ทหารฝ่ายรับตายครบเท่าที่เหลือ (300) ไม่เกิน", d2, 300)
		check("ส่วนเกิน 500 ไหลไปตีกำแพงในตาเดียวกัน", w2, 500)
		check("ทหารฝ่ายรับเหลือ 0", data.stageProgress[2].defendersRemaining, 0)
		check("กำแพงเหลือ 4,500 (5,000-500)", data.stageProgress[2].wallHpRemaining, 4500)
		check("เงินรางวัลตาที่สอง (300 × 2 บาท/HP) — ส่วนเกินที่ไปกำแพงไม่ได้เงิน", coins2, 600)
		check("ด่านยังไม่จบ (กำแพงยังไม่หมด)", cleared2, false)

		check("เงินรวมสองตาเข้า currency.coins ครบ", data.currency.coins - startCoins, 19400 + 600)
		check("stats.coinsFromKills สะสมด้วย", data.stats.coinsFromKills, 19400 + 600)
		check("stats.totalCoinsEarned สะสมด้วย", data.stats.totalCoinsEarned, 19400 + 600)

		-- ตีกำแพงที่เหลือให้หมดพอดี
		local d3, w3, coins3, cleared3 = CombatService.applyDamageToStage(data, meta, 2, 4500)
		check("damage ทั้งหมดตกที่กำแพง (ทหารฝ่ายรับหมดแล้ว)", w3, 4500)
		check("ทหารฝ่ายรับไม่ได้ damage เพิ่ม (หมดไปแล้ว)", d3, 0)
		check("ตีกำแพงไม่ได้เงินเลย (รางวัลผูกกับทหารฝ่ายรับเท่านั้น ไม่มีฟังก์ชันรางวัลของกำแพง)", coins3, 0)
		check("ด่านจบแล้ว (ทหารฝ่ายรับ+กำแพงหมดทั้งคู่)", cleared3, true)
		check("กำแพงเหลือ 0 พอดี ไม่ติดลบ", data.stageProgress[2].wallHpRemaining, 0)
	end

	----------------------------------------------------------------------------
	-- ปล่อยทหารตามลำดับ releaseOrder — ข้ามกองว่างไม่ลบออกจากลำดับ + ดึงข้ามกองถูกสัดส่วน
	----------------------------------------------------------------------------
	-- power ต่อตัว (damageLevel=0): wukong (คลาส A ×36)
	--   น้ำหนักแม่ 10,000 → ลูก 100 kg → 10×(100/100)^0.5×36 = 360
	--   น้ำหนักแม่ 250,000 → ลูก 2,500 kg → 10×(2,500/100)^0.5×36 = 10×5×36 = 1,800
	print("── ปล่อยทหารตามลำดับ releaseOrder: ข้ามกองว่างไม่ลบออกจากลำดับ + ดึงข้ามกองถูกสัดส่วน ──")

	do
		local data = freshData()
		local keyA = Config.makeStackKey("wukong", 10000, {}) -- power 360/ตัว
		local keyB = Config.makeStackKey("wukong", 250000, {}) -- power 1,800/ตัว
		local keyEmpty = Config.makeStackKey("wukong", 500, {}) -- ไม่เคยผลิตเลย ไม่มีใน children

		data.children[keyA] = 5
		data.children[keyB] = 10
		data.releaseOrder = { keyEmpty, keyA, keyB }

		-- ขอปล่อย 8 ตัว: keyEmpty ข้ามไป (ไม่มีของ) → เอาจาก keyA ทั้ง 5 ตัว (5×360=1,800)
		-- แล้วอีก 3 ตัวจาก keyB (3×1,800=5,400) รวม damage = 1,800+5,400 = 7,200
		local released, power = CombatService.releaseFromQueue(data, 8)
		check("ปล่อยได้ 8 ตัวตามที่ขอ (มีของพอในสองกองรวมกัน)", released, 8)
		check(
			"damage รวมถ่วงน้ำหนักตามจำนวนที่ดึงจากแต่ละกองถูกต้อง (5×360 + 3×1,800)",
			power,
			5 * 360 + 3 * 1800
		)
		check("กอง A หมดแล้วถูกลบออกจาก children", data.children[keyA], nil)
		check("กอง B เหลือ 7 ตัว (10-3)", data.children[keyB], 7)
		check("keyEmpty ยังอยู่หัวแถวใน releaseOrder ไม่ถูกลบ", data.releaseOrder[1], keyEmpty)
		check("ลำดับ releaseOrder ยาวเท่าเดิม (แค่ children ถูกดึงออก ไม่แตะลำดับ)", #data.releaseOrder, 3)

		-- ผลิตเพิ่มมาเติม keyEmpty ทีหลัง → ต้องกลับมาปล่อยได้จากตำแหน่งเดิมในคิว (ไม่ต้องจัดใหม่)
		data.children[keyEmpty] = 2
		local released2, power2 = CombatService.releaseFromQueue(data, 1)
		check("กองที่เคยว่างแล้วมีของมาเติม ปล่อยได้จากตำแหน่งเดิมในคิวทันที", released2, 1)
		check("power2 > 0 (ดึงจาก keyEmpty ได้จริง)", power2 > 0, true)
	end

	----------------------------------------------------------------------------
	-- คลังว่างเปล่าทั้งหมด (ทุกกองในลำดับ count=0) → ไม่ error แค่หยุด
	----------------------------------------------------------------------------
	print("── คลังว่างเปล่าทั้งหมด: ไม่ error แค่หยุด รอคลังมีของจากการผลิตต่อ ──")

	do
		local data = freshData()
		data.releaseOrder = { Config.makeStackKey("wukong", 100, {}) }

		local released, power = CombatService.releaseFromQueue(data, 50)
		check("ไม่มีของเลย → ปล่อยได้ 0 ตัว ไม่ error", released, 0)
		check("damage เป็น 0", power, 0)
	end

	----------------------------------------------------------------------------
	-- กองใหม่ที่ไม่เคยอยู่ใน releaseOrder ถูกต่อท้ายอัตโนมัติ
	----------------------------------------------------------------------------
	print("── กองใหม่ที่ไม่เคยอยู่ใน releaseOrder ถูกต่อท้ายอัตโนมัติ ──")

	do
		local data = freshData()
		local keyA = Config.makeStackKey("wukong", 10000, {})
		local keyB = Config.makeStackKey("wukong", 250000, {})
		data.releaseOrder = { keyA }
		data.children[keyA] = 5
		data.children[keyB] = 3 -- เพิ่งผลิตครั้งแรก ยังไม่เคยอยู่ในลำดับ

		CombatService.reconcileReleaseOrder(data)
		check("ลำดับยาวขึ้นเป็น 2 (ต่อท้าย keyB)", #data.releaseOrder, 2)
		check("keyA ยังอยู่หัวแถวเหมือนเดิม", data.releaseOrder[1], keyA)
		check("keyB ถูกต่อท้าย", data.releaseOrder[2], keyB)

		CombatService.reconcileReleaseOrder(data)
		check("เรียกซ้ำไม่ต่อท้ายซ้ำ (idempotent)", #data.releaseOrder, 2)
	end

	----------------------------------------------------------------------------
	-- SetReleaseOrderRequest: ปฏิเสธ key ที่ไม่ถูกต้อง/ไม่มีอยู่จริงทั้งชุดเงียบ ๆ
	----------------------------------------------------------------------------
	print("── SetReleaseOrderRequest: ปฏิเสธ key ที่ไม่ถูกต้อง/ไม่มีอยู่จริงทั้งชุดเงียบ ๆ ──")

	do
		local data = freshData()
		local keyA = Config.makeStackKey("wukong", 10000, {})
		local keyB = Config.makeStackKey("wukong", 250000, { "gold" })
		data.releaseOrder = { keyA }

		local ok1 = CombatService.handleSetReleaseOrder(data, { keyB, keyA })
		check("ชุดที่ถูกต้องทั้งหมด → apply สำเร็จ", ok1, true)
		check("releaseOrder ถูกแทนที่ตามที่ส่งมา (ตัวแรก)", data.releaseOrder[1], keyB)
		check("releaseOrder ถูกแทนที่ตามที่ส่งมา (ตัวที่สอง)", data.releaseOrder[2], keyA)

		local before = data.releaseOrder
		local ok2 = CombatService.handleSetReleaseOrder(data, { keyA, "not-a-real-key" })
		check("มี key ปลอมปนอยู่แม้แค่ตัวเดียว → ปฏิเสธทั้งชุด", ok2, false)
		check("releaseOrder เดิมไม่ถูกแตะเลย", data.releaseOrder, before)

		local fakeCharKey = Config.makeStackKey("not_a_real_character", 100, {})
		local ok3 = CombatService.handleSetReleaseOrder(data, { fakeCharKey })
		check("charId ไม่มีจริงใน Config.Characters → ปฏิเสธ", ok3, false)

		local ok4 = CombatService.handleSetReleaseOrder(data, { keyA, keyA })
		check("มี key ซ้ำกันในชุดเดียว → ปฏิเสธ", ok4, false)

		local ok5 = CombatService.handleSetReleaseOrder(data, "wukong|100|")
		check("ส่งมาไม่ใช่ table เลย → ปฏิเสธ", ok5, false)

		local tooLong = {}
		for index = 1, Config.Inventory.MAX_CHILD_STACKS + 1 do
			tooLong[index] = keyA
		end
		local ok6 = CombatService.handleSetReleaseOrder(data, tooLong)
		check("ยาวเกินเพดานจำนวนกองสูงสุด (MAX_CHILD_STACKS) → ปฏิเสธ", ok6, false)
	end

	----------------------------------------------------------------------------
	-- Auto-pause: ปล่อยครบ AUTO_PAUSE_AFTER_UNITS ตัวแล้วไม่มี progress → ปิดอัตโนมัติ
	----------------------------------------------------------------------------
	-- ⚠️ ในเฟสนี้ (ยังไม่มี turret) "ตีแล้ว HP ไม่ลด" แทบไม่เกิดจริงในเกม เพราะ
	-- computeBattlePower มีพื้นบวกเสมอ — เทสต์นี้เรียก CombatService.registerProgress ตรง ๆ
	-- (ตัวนับที่ CombatService.tick ใช้ภายใน) เพื่อยืนยันตาข่ายกันไว้ทำงานถูกต้อง โดยไม่ต้อง
	-- พึ่งพาสถานการณ์เกมจริงที่ยังไม่เกิดขึ้นได้ในเฟสนี้
	print("── Auto-pause ทำงานถูกจังหวะ (ปล่อยครบ AUTO_PAUSE_AFTER_UNITS แล้วไม่มี progress) ──")

	do
		local data = freshData()
		local meta = freshMeta()
		local threshold = Config.Balance.Combat.AUTO_PAUSE_AFTER_UNITS

		check("เริ่มต้น summonEnabled ตาม SUMMON_DEFAULT_ON", data.summonEnabled, Config.Balance.Combat.SUMMON_DEFAULT_ON)

		-- ปล่อยไปเรื่อย ๆ ทีละ 1 หน่วยโดยไม่มี progress เลย จนเกือบครบเพดาน
		for _ = 1, threshold - 1 do
			local paused = CombatService.registerProgress(data, meta, 1, 0)
			check("ยังไม่ถึงเพดาน ไม่ปิดปุ่มอัญเชิญ", paused, false)
		end
		check("summonEnabled ยังเปิดอยู่ (ยังไม่ถึงเพดาน)", data.summonEnabled, true)

		-- หน่วยสุดท้ายที่ครบเพดานพอดี → ต้องปิดปุ่มอัญเชิญ + ตั้ง flag
		local pausedNow = CombatService.registerProgress(data, meta, 1, 0)
		check("ครบเพดานพอดี → auto-pause ทำงาน", pausedNow, true)
		check("summonEnabled ถูกปิดเอง", data.summonEnabled, false)
		check("combatAutoPaused ถูกตั้งเป็น true", data.combatAutoPaused, true)
		check("ตัวนับรีเซ็ตหลัง auto-pause ทำงานแล้ว", meta.unitsSinceProgress, 0)

		-- มี progress จริงเมื่อไหร่ ตัวนับต้องรีเซ็ตทันที ไม่สะสมข้ามไปเรื่อย ๆ
		local meta2 = freshMeta()
		CombatService.registerProgress(data, meta2, 50, 0)
		CombatService.registerProgress(data, meta2, 1, 10) -- มี progress จริง (HP ลด 10)
		check("มี progress จริง → ตัวนับรีเซ็ตเป็น 0 ทันที", meta2.unitsSinceProgress, 0)

		-- ผู้เล่นกดเปิดปุ่มอัญเชิญกลับ → เคลียร์ flag แจ้งเตือน + รีเซ็ตตัวนับ
		local metaResume = freshMeta()
		metaResume.unitsSinceProgress = 999
		local okResume = CombatService.handleSetSummonEnabled(data, metaResume, true)
		check("เปิดปุ่มอัญเชิญกลับสำเร็จ", okResume, true)
		check("combatAutoPaused ถูกเคลียร์กลับ false", data.combatAutoPaused, false)
		check("summonEnabled เปิดกลับมา", data.summonEnabled, true)
		check("ตัวนับ auto-pause รีเซ็ตด้วยตอนเปิดกลับ", metaResume.unitsSinceProgress, 0)
	end

	----------------------------------------------------------------------------
	-- ปิดเกม/ออกเกม → ไม่มี offline progress (ตรงข้ามกับ ProductionService โดยตั้งใจ)
	----------------------------------------------------------------------------
	print("── ปิดเกม/ออกเกม → ไม่มี offline progress เกิดขึ้น (ตรงข้ามกับ ProductionService) ──")

	do
		local data = freshData()
		local key = Config.makeStackKey("wukong", 10000, {})
		data.children[key] = 100000 -- คลังเยอะพอไม่ให้ชนเพดานระหว่างเทสต์

		local meta1 = CombatService.newMeta()
		local result1 = CombatService.tick(data, meta1, 1) -- ออนไลน์ปกติ 1 วิ (อัตราด่าน 1 = 1 ตัว/วิ)
		check("ตอนออนไลน์ปกติ 1 วิ ปล่อยได้ตามอัตราด่าน (1 ตัว/วิ)", result1.unitsReleased, 1)

		-- จำลอง "ออกเกม" (ล้าง meta ทิ้งแบบเดียวกับ CombatService.clearMeta ตอน PlayerRemoving)
		-- แล้วเวลาผ่านไปยาวนานมาก (เช่น 8 ชั่วโมง) โดยไม่มีใครเรียก tick() ให้เลยสักครั้ง —
		-- นี่คือหัวใจของกติกา: ไม่มีฟังก์ชันไหนในไฟล์นี้รับ "เวลาที่หายไปตอนออฟไลน์" มา
		-- settle ย้อนหลังให้เลย (ต่างจาก ProductionService.settleMother ที่รับ elapsed จาก
		-- timestamp ย้อนหลังได้)

		-- "กลับมาเข้าเกมใหม่" = สร้าง meta ใหม่ (เหมือน getOrCreateMeta หลัง clearMeta)
		local meta2 = CombatService.newMeta()
		local result2 = CombatService.tick(data, meta2, 1) -- ออนไลน์ปกติอีก 1 วิ
		check(
			"กลับมาเข้าเกมใหม่แล้ว tick 1 วิ ได้แค่ตามอัตราปกติ ไม่ได้โบนัสจากเวลาที่หายไปเลย",
			result2.unitsReleased,
			1
		)
	end

	----------------------------------------------------------------------------
	-- wallProgress เชื่อมกับ stageProgress ที่ตีผ่านจริง (แพตช์ 3A)
	----------------------------------------------------------------------------
	-- ด่าน 1: defenders=0, wallHp=0 → "พังเรียบร้อย" ฟรีตั้งแต่ tick แรก แต่ไม่มีกำแพงจริงให้พัง
	-- จึงไม่นับเป็นความคืบหน้าเพิ่มจากค่าเริ่มต้น (wallProgress ยังคง 1 เท่าเดิม)
	-- ด่าน 2: defenders=100×100HP=10,000 · wallHp=10,000×0.5=5,000 รวม 15,000 — มีกำแพงจริง
	-- พังด่านนี้ครั้งแรกจึงทำให้ wallProgress ขยับจาก 1 เป็น 2 จริง
	print("── wallProgress เชื่อมกับ stageProgress ที่ตีผ่านจริง (แพตช์ 3A) ──")

	do
		local data = freshData()
		local meta = freshMeta()
		local key = Config.makeStackKey("wukong", 10000, {}) -- power 360/ตัว (damageLevel=0)
		data.children[key] = 100000

		check("ผู้เล่นใหม่ wallProgress = ค่าเริ่มต้น", data.wallProgress, Config.Balance.NewPlayer.wallProgress)

		-- ด่าน 1 ไม่มีทหารฝ่ายรับ/กำแพง (0,0) → พังเรียบร้อยทันทีที่ tick แรกที่ปล่อยได้จริง
		CombatService.tick(data, meta, 1)
		check("ด่าน 1 พังเรียบร้อยแล้ว (ไม่มีกำแพงให้พังตั้งแต่แรก)", CombatService.getActiveStage(data), 2)
		check(
			"จำลองตีด่าน 1 จนพังสมบูรณ์ → wallProgress ต้องเป็น 1 (ด่าน 1 ไม่มีกำแพงจริง ไม่นับเพิ่ม)",
			data.wallProgress,
			1
		)

		-- ด่าน 2 ต้องการ 15,000 HP รวม — ปล่อย 50 ตัว × 360 = 18,000 เกินพอในตาเดียว
		CombatService.tick(data, meta, 50)
		check("ด่าน 2 พังเรียบร้อยจริง (ไม่ใช่แค่ wallProgress ขยับลอย ๆ)", CombatService.getActiveStage(data), 3)
		check("ตีด่าน 2 ต่อจนพัง → wallProgress ต้องเป็น 2", data.wallProgress, 2)

		-- integration: เงิน/เพดานอัปเกรดที่ผูกกับ wallProgress ต้องเปลี่ยนค่าจริงตามด้วย
		-- ไม่ใช่แค่ตัวเลข wallProgress เปลี่ยนลอย ๆ โดยไม่มีผลอะไรต่อ
		check(
			"getCoinsPerMinute ใช้ wallProgress ใหม่จริง (คูณ ×10 จากตอน wallProgress=1)",
			Config.getCoinsPerMinute(100, data.wallProgress, {}),
			Config.getCoinsPerMinute(100, 1, {}) * 10
		)
		check(
			"เพดานซื้อตัวคูณ damage ใช้ wallProgress ใหม่จริง (โตขึ้นตาม STEPS_PER_STAGE)",
			Config.getMaxDamageLevel(data.wallProgress),
			Config.getMaxDamageLevel(1) + Config.Balance.DamageUpgrade.STEPS_PER_STAGE
		)
	end

	print("── ทหารฝ่ายรับหมดแต่กำแพงยังไม่หมด HP → wallProgress ต้องไม่ขยับ ──")

	do
		local data = freshData()
		local meta = freshMeta()
		-- จำลองว่าผ่านด่าน 1 มาแล้ว (ฟรี ไม่มีกำแพง) ตั้งด่าน 2 ให้ทหารฝ่ายรับเหลือ 1 HP
		-- (ตายตาต่อไปพอดี) แต่กำแพงยังเต็ม — ห้ามให้ damage ทะลุไปโดนกำแพงเด็ดขาดในเทสต์นี้
		data.stageProgress[1] = { defendersRemaining = 0, wallHpRemaining = 0 }
		data.stageProgress[2] = { defendersRemaining = 1, wallHpRemaining = Config.getStageWallHp(2) }
		data.wallProgress = 1

		CombatService.applyDamageToStage(data, meta, 2, 1)
		check("ทหารฝ่ายรับด่าน 2 หมดพอดี", data.stageProgress[2].defendersRemaining, 0)
		check("กำแพงด่าน 2 ยังเต็ม ไม่โดนแตะเลย", data.stageProgress[2].wallHpRemaining, Config.getStageWallHp(2))

		CombatService.recomputeWallProgress(data)
		check("ทหารฝ่ายรับหมดแต่กำแพงยังไม่หมด HP → wallProgress ไม่ขยับ", data.wallProgress, 1)
	end

	----------------------------------------------------------------------------
	-- Persistence: ออก-เข้าใหม่ → stageProgress/releaseOrder/currency อยู่ครบ
	----------------------------------------------------------------------------
	print("── Persistence: stageProgress/releaseOrder/combatAutoPaused ผ่าน encode/decode ครบ ──")

	do
		local data = freshData()
		data.stageProgress[4] = { defendersRemaining = 4200, wallHpRemaining = 3300 }
		data.releaseOrder = { Config.makeStackKey("wukong", 10000, {}), Config.makeStackKey("wukong", 250000, {}) }
		data.combatAutoPaused = true
		data.summonEnabled = false
		data.currency.coins += 12345
		-- ⚠️ จำลองว่าเคยตีผ่านมาแล้ว 3 ด่าน (ดูชุดเทสต์ "wallProgress เชื่อมกับ stageProgress"
		-- ด้านบนสำหรับเทสต์ตัว recomputeWallProgress เอง — ตรงนี้เช็คแค่ว่า encode/decode ไม่ทำค่าหาย)
		data.wallProgress = 3

		PlayerData.sanitizeForSave(data) -- ต้องไม่ throw (encode ได้ตามกฎ §9.3)

		local back = Json.decode(PlayerData.encode(data))
		check("stageProgress[4].defendersRemaining กลับมาครบ", back.stageProgress[4].defendersRemaining, 4200)
		check("stageProgress[4].wallHpRemaining กลับมาครบ", back.stageProgress[4].wallHpRemaining, 3300)
		check("releaseOrder กลับมาครบ (ตัวแรก)", back.releaseOrder[1], data.releaseOrder[1])
		check("releaseOrder กลับมาครบ (ตัวที่สอง)", back.releaseOrder[2], data.releaseOrder[2])
		check("combatAutoPaused กลับมาครบ", back.combatAutoPaused, true)
		check("summonEnabled กลับมาครบ", back.summonEnabled, false)
		check("currency.coins กลับมาครบ", back.currency.coins, data.currency.coins)
		check("wallProgress ที่ตีผ่านมาแล้วกลับมาครบ (ออก-เข้าใหม่ไม่หาย)", back.wallProgress, 3)
	end

	----------------------------------------------------------------------------
	-- 🔴 จำลอง exploit: client ส่งค่า damage/เงินมาตรง ๆ ไม่มีผลอะไรเลย
	----------------------------------------------------------------------------
	-- ⚠️ RemoteEvent สองตัวที่ client ยิงถึง CombatService ได้ (SetReleaseOrderRequest /
	-- SetSummonEnabledRequest) ไม่มีพารามิเตอร์ไหนรับ "จำนวน damage" หรือ "จำนวนเงิน" เลย —
	-- ทุก state เปลี่ยนได้ก็ต่อเมื่อผ่าน CombatService.tick() คำนวณเองเท่านั้น
	print("── exploit: client ส่งค่า damage/เงินมาตรง ๆ ไม่มีผลอะไรเลย (ต้องผ่าน CombatService คำนวณเอง) ──")

	do
		local data = freshData()
		local startCoins = data.currency.coins
		CombatService.ensureStageStarted(data, 2)
		local before = {
			defendersRemaining = data.stageProgress[2].defendersRemaining,
			wallHpRemaining = data.stageProgress[2].wallHpRemaining,
		}

		-- จำลอง client แนบฟิลด์ปลอมแฝงมาด้วย (object ที่มี .damage/.coins) แทนที่จะเป็น
		-- string ตรง ๆ — ยังโดนปฏิเสธเหมือนเดิม เพราะ validate ที่ระดับ "ต้องเป็น string ที่
		-- round-trip กับ Config.makeStackKey() เป๊ะ" เท่านั้น ไม่มีช่องให้ตัวเลขอื่นหลุดเข้ามาได้
		local spoofed = { { key = "wukong|10000|", damage = 999999999, coins = 999999999 } }
		local ok = CombatService.handleSetReleaseOrder(data, spoofed)
		check("ส่ง object แปลกปลอมแทน string → ปฏิเสธ", ok, false)
		check("HP ทหารฝ่ายรับไม่ถูกแตะเลย", data.stageProgress[2].defendersRemaining, before.defendersRemaining)
		check("HP กำแพงไม่ถูกแตะเลย", data.stageProgress[2].wallHpRemaining, before.wallHpRemaining)

		-- SetSummonEnabledRequest รับได้แค่ boolean ล้วน ๆ ส่งตัวเลขเข้ามาไม่มีผลอะไรเลย
		local ok2 = CombatService.handleSetSummonEnabled(data, CombatService.newMeta(), 999999999)
		check("ส่งตัวเลขแทน boolean → ปฏิเสธ", ok2, false)
		check("เงินไม่ถูกแตะเลยจากทั้งสองคำขอ", data.currency.coins, startCoins)
	end

	----------------------------------------------------------------------------
	-- ผู้เล่น 2 คนตีคนละด่าน/คนละความคืบหน้า ไม่กระทบกัน
	----------------------------------------------------------------------------
	print("── ผู้เล่น 2 คนตีคนละด่าน/คนละความคืบหน้า ไม่กระทบกัน ──")

	do
		local dataA = freshData()
		local dataB = freshData()
		local metaA = CombatService.newMeta()
		local metaB = CombatService.newMeta()

		local key = Config.makeStackKey("wukong", 10000, {})
		dataA.children[key] = 100000
		dataB.children[key] = 100000

		-- A ตีไปสองตา: พังด่าน 1 (ว่างเปล่าอยู่แล้ว) แล้วเริ่มตีด่าน 2 ต่อทันที
		CombatService.tick(dataA, metaA, 1)
		CombatService.tick(dataA, metaA, 5)

		check("A เริ่มแตะด่าน 2 แล้ว (stageProgress[2] เป็น table)", type(dataA.stageProgress[2]), "table")
		check("B ยังไม่เคยแตะด่านไหนเลย (stageProgress[1] ยังเป็น false)", dataB.stageProgress[1], false)
		check("B ไม่ได้รับผลกระทบจากการตีของ A เลย", dataB.stageProgress[2], false)

		-- B ตีด่าน 1 (ว่างเปล่า) ไปตาเดียว โดยไม่ต้องพึ่งความคืบหน้าของ A เลย
		CombatService.tick(dataB, metaB, 1)
		check("B พังด่าน 1 ได้เองอิสระ ไม่ผูกกับความคืบหน้าของ A", dataB.stageProgress[1].defendersRemaining, 0)
		check("ความคืบหน้าด่าน 2 ของ A ไม่ถูก B แตะต้อง", type(dataA.stageProgress[2]), "table")
		check("B ยังไม่แตะด่าน 2 เลย แม้ A จะไปถึงแล้ว", dataB.stageProgress[2], false)

		check("เงินสะสมของ A กับ B ไม่ผูกกัน (A ตีด่าน 2 ได้เงินจริง ส่วน B ยังไม่ได้เลย)", dataA.currency.coins ~= dataB.currency.coins, true)
	end

	----------------------------------------------------------------------------
	-- Phase 3C-1: battleRoster — ส่งแม่ไปรบ
	----------------------------------------------------------------------------
	local MAX_ROSTER = Config.Balance.Combat.MAX_BATTLE_MOTHERS
	local nextTestUid = 0

	-- แม่ลิง (C ×1) 100 kg → พลัง = 10 พอดี (คำนวณมือง่าย) เว้นแต่ระบุอย่างอื่น
	local function makeMother(weight: number?, charId: string?)
		nextTestUid += 1
		return {
			uid = Config.makeUid(424242, nextTestUid),
			charId = charId or "monkey",
			weight = weight or 100,
			statuses = {},
			obtainedAt = 0,
			locked = false,
		}
	end

	-- ผู้เล่นที่ผ่านด่าน 1 (ว่างเปล่า) แล้ว กำลังตีด่าน 2 · ไม่มีลูกในคลังเลย
	local function dataAtStage2()
		local data = freshData()
		data.stageProgress[1] = { defendersRemaining = 0, wallHpRemaining = 0 }
		CombatService.ensureStageStarted(data, 2)
		data.summonEnabled = true
		return data
	end

	print("── 3C-1 ส่งแม่ไปรบ: ย้ายจากกระเป๋าเข้า roster · ปฏิเสธทุกกรณีที่ไม่ควรผ่าน ──")

	do
		local data = freshData()
		local mother = makeMother()
		table.insert(data.mothersInBag, mother)

		-- ด่าน 1 ยังไม่เคยแตะ = ด่านที่กำลังตีคือด่าน 1 ซึ่งไม่มีศัตรู → แม่จะตายฟรี ต้องปฏิเสธ
		local ok = CombatService.handleSendMotherToBattle(data, mother.uid)
		check("ด่านที่กำลังตีไม่มีศัตรู (ด่าน 1) → ปฏิเสธ", ok, false)
		check("  แม่ยังอยู่ในกระเป๋า", #data.mothersInBag, 1)
		check("  roster ยังว่าง", #data.battleRoster, 0)

		data.stageProgress[1] = { defendersRemaining = 0, wallHpRemaining = 0 }
		local okSend, message = CombatService.handleSendMotherToBattle(data, mother.uid)
		check("ด่าน 2 มีศัตรู → ส่งสำเร็จ", okSend, true)
		check("  ข้อความสำเร็จบอกจำนวนใน roster", string.find(message, `1/{MAX_ROSTER}`, 1, true) ~= nil, true)
		check("  แม่ออกจากกระเป๋าแล้ว (อยู่ได้ที่เดียว)", #data.mothersInBag, 0)
		check("  แม่อยู่ใน roster", data.battleRoster[1] and data.battleRoster[1].uid, mother.uid)

		check("ส่ง uid เดิมซ้ำ (อยู่ใน roster แล้ว ไม่อยู่ในกระเป๋า) → ปฏิเสธ",
			(CombatService.handleSendMotherToBattle(data, mother.uid)), false)
		check("  roster ไม่เพิ่มซ้ำ", #data.battleRoster, 1)

		local penMother = makeMother()
		table.insert(data.mothersInPen, penMother)
		check("แม่ในคอก → ปฏิเสธ (ส่งได้เฉพาะจากกระเป๋า)",
			(CombatService.handleSendMotherToBattle(data, penMother.uid)), false)
		check("  แม่ในคอกยังอยู่ในคอก", #data.mothersInPen, 1)

		check("uid ที่ไม่ใช่ของผู้เล่นคนนี้ → ปฏิเสธ",
			(CombatService.handleSendMotherToBattle(data, Config.makeUid(999, 1))), false)
		check("uid ไม่ใช่ string → ปฏิเสธ", (CombatService.handleSendMotherToBattle(data, 12345)), false)
		check("uid เป็น nil → ปฏิเสธ", (CombatService.handleSendMotherToBattle(data, nil)), false)

		local lockedMother = makeMother()
		lockedMother.locked = true
		table.insert(data.mothersInBag, lockedMother)
		check("แม่ที่ล็อกไว้ → ปฏิเสธ", (CombatService.handleSendMotherToBattle(data, lockedMother.uid)), false)
		check("  แม่ที่ล็อกยังอยู่ในกระเป๋า", #data.mothersInBag, 1)
	end

	print(`── 3C-1 roster เต็ม {MAX_ROSTER} ตัว → ตัวถัดไปถูกปฏิเสธ ไม่หายจากกระเป๋า ──`)

	do
		local data = dataAtStage2()
		for _ = 1, MAX_ROSTER + 1 do
			table.insert(data.mothersInBag, makeMother())
		end

		for _ = 1, MAX_ROSTER do
			CombatService.handleSendMotherToBattle(data, data.mothersInBag[1].uid)
		end
		check(`ส่งครบ {MAX_ROSTER} ตัว`, #data.battleRoster, MAX_ROSTER)
		check("กระเป๋าเหลือ 1 ตัว", #data.mothersInBag, 1)

		local ok, message = CombatService.handleSendMotherToBattle(data, data.mothersInBag[1].uid)
		check(`ตัวที่ {MAX_ROSTER + 1} → ปฏิเสธ`, ok, false)
		check("  ข้อความบอกว่า roster เต็ม", string.find(message, "roster เต็มแล้ว", 1, true) ~= nil, true)
		check("  roster ไม่เกินเพดาน", #data.battleRoster, MAX_ROSTER)
		check("  ตัวที่ถูกปฏิเสธยังอยู่ในกระเป๋า", #data.mothersInBag, 1)
	end

	print("── 3C-1 ผ่านครบทุกด่านแล้ว → ส่งแม่ไปรบไม่ได้ (ไม่มีอะไรให้ตี แม่จะค้างใน roster ตลอดไป) ──")

	do
		local data = freshData()
		for stage = 1, Config.Balance.Stage.COUNT do
			data.stageProgress[stage] = { defendersRemaining = 0, wallHpRemaining = 0 }
		end
		local mother = makeMother()
		table.insert(data.mothersInBag, mother)
		check("ไม่มีด่านให้ตี → ปฏิเสธ", (CombatService.handleSendMotherToBattle(data, mother.uid)), false)
		check("  แม่ยังอยู่ในกระเป๋า", #data.mothersInBag, 1)
	end

	print("── 3C-1 แม่ใน roster ตีทุกวินาที แรงเท่า computeBattlePower · แม่ 1 ตัว = ลูก 10 ตัว ──")

	do
		local motherPower = Config.computeBattlePower(100, "monkey", {}, 0)
		local childPower = Config.computeBattlePower(Config.getChildWeight(100, {}), "monkey", {}, 0)
		local near = t.near
		near("แม่ลิง 100 kg แรง 10 ต่อวินาที", motherPower, 10, 1e-9)
		near("แม่แรงเป็น 10 เท่าของลูกตัวเอง (กฎ 'แม่ 1 = ลูก 10')", motherPower / childPower, 10, 1e-9)

		local data = dataAtStage2()
		local meta = freshMeta()
		table.insert(data.battleRoster, makeMother())
		table.insert(data.battleRoster, makeMother())
		local before = data.stageProgress[2].defendersRemaining

		local result = CombatService.tick(data, meta, 2)
		check("ไม่มีลูกในคลังเลย → ไม่มีหน่วยถูกปล่อย", result.unitsReleased, 0)
		near("แม่ 2 ตัว × 10 × 2 วินาที = damage 40", result.damageDealt, 40, 1e-9)
		near("ทหารฝ่ายรับลดลง 40 จริง", before - data.stageProgress[2].defendersRemaining, 40, 1e-9)
		check("ด่านยังไม่พัง → แม่ยังอยู่ครบ", #data.battleRoster, 2)
		check("ด่านยังไม่พัง → mothersLost = 0", result.mothersLost, 0)

		-- damageLevel ที่ซื้อไว้มีผลกับแม่ด้วย (ตัวคูณเป็นของบัญชี ไม่ใช่ของลูกอย่างเดียว)
		data.damageLevel = 8
		near("damage ของ roster คูณ 1.1^damageLevel ด้วย",
			CombatService.getRosterDps(data), 2 * Config.computeBattlePower(100, "monkey", {}, 8), 1e-6)
	end

	print("── 3C-1 ปิดอัญเชิญ → แม่หยุดตี ไม่ตาย รออยู่ใน roster ──")

	do
		local data = dataAtStage2()
		data.summonEnabled = false
		table.insert(data.battleRoster, makeMother())
		local before = data.stageProgress[2].defendersRemaining

		local result = CombatService.tick(data, freshMeta(), 5)
		check("ปิดอัญเชิญ → ไม่มี damage", result.damageDealt, 0)
		check("  HP ทหารฝ่ายรับไม่ลด", data.stageProgress[2].defendersRemaining, before)
		check("  แม่ยังอยู่ใน roster", #data.battleRoster, 1)
	end

	print("── 3C-1 ด่านที่กำลังตีพัง → แม่ทั้ง roster ตายถาวรพร้อมกัน · กระเป๋าไม่ถูกแตะ ──")

	do
		local data = dataAtStage2()
		local meta = freshMeta()
		-- เหลือกำแพงแค่ 5 HP — แม่ roster เต็มตีทีเดียวพังแน่นอน
		data.stageProgress[2] = { defendersRemaining = 0, wallHpRemaining = 5 }
		for _ = 1, MAX_ROSTER do
			table.insert(data.battleRoster, makeMother())
		end
		table.insert(data.mothersInBag, makeMother())
		table.insert(data.mothersInBag, makeMother())
		local lostBefore = data.stats.mothersLost

		local result = CombatService.tick(data, meta, 1)
		check("ด่าน 2 พัง", result.stageCleared, true)
		check(`แม่ตายพร้อมกันทั้ง {MAX_ROSTER} ตัว`, result.mothersLost, MAX_ROSTER)
		check("roster เหลือ 0", #data.battleRoster, 0)
		check("stats.mothersLost เพิ่มตามจำนวนที่ตาย", data.stats.mothersLost - lostBefore, MAX_ROSTER)
		check("แม่ในกระเป๋าไม่ถูกแตะ (ยังอยู่ 2 ตัว)", #data.mothersInBag, 2)
		check("wallProgress ขยับตามด่านที่พัง", data.wallProgress >= 2, true)
		check("ด่านที่กำลังตีเลื่อนไปด่าน 3", CombatService.getActiveStage(data), 3)

		-- ด่านใหม่: roster ว่างแล้ว ส่งใหม่ได้ตามปกติ
		local fresh = data.mothersInBag[1]
		check("หลังด่านพัง ส่งแม่ชุดใหม่เข้าด่าน 3 ได้", (CombatService.handleSendMotherToBattle(data, fresh.uid)), true)
	end

	print("── 3C-1 ตาข่ายชั้นสอง: ด่านที่ไม่มีศัตรู (HP รวม 0) พัง → ไม่ฆ่าแม่ ──")

	do
		local data = freshData()
		table.insert(data.battleRoster, makeMother())
		check("killRoster(ด่าน 1) ไม่ฆ่าใคร", CombatService.killRoster(data, 1), 0)
		check("  แม่ยังอยู่", #data.battleRoster, 1)
		check("killRoster(ด่าน 2) ฆ่าจริง", CombatService.killRoster(data, 2), 1)
		check("  roster ว่าง", #data.battleRoster, 0)
	end

	print("── 3C-1 battleRoster ผ่าน encode/decode ครบ + อยู่ใน sync payload ──")

	do
		local data = dataAtStage2()
		local mother = makeMother(123456, "wukong")
		mother.statuses = { "gold" }
		table.insert(data.battleRoster, mother)

		PlayerData.sanitizeForSave(data) -- ต้องไม่ throw
		local back = Json.decode(PlayerData.encode(data))
		check("roster กลับมาครบ (uid)", back.battleRoster[1].uid, mother.uid)
		check("roster กลับมาครบ (น้ำหนัก)", back.battleRoster[1].weight, 123456)
		check("roster กลับมาครบ (สถานะ)", back.battleRoster[1].statuses[1], "gold")

		local sync = CombatService.buildSyncFields(data)
		check("sync มี battleRoster", #sync.battleRoster, 1)
		check("  sync ส่ง charId", sync.battleRoster[1].charId, "wukong")
		check("  sync ส่งน้ำหนัก", sync.battleRoster[1].weight, 123456)
	end

	----------------------------------------------------------------------------
	-- Phase 4A รางวัลผ่านด่าน (ไข่ฟรีครั้งเดียวต่อด่าน)
	----------------------------------------------------------------------------
	local EXPECTED_BONUS = { 0, 1, 1, 2, 2, 2, 3, 3, 3 }

	-- ผู้เล่นที่ด่าน 1..stage-1 พังแล้ว · ด่าน stage เหลือกำแพง 1 HP · มีแม่ 1 ตัวใน roster (ตี 10/วิ)
	local function dataAboutToClear(stage: number)
		local data = freshData()
		for index = 1, stage - 1 do
			data.stageProgress[index] = { defendersRemaining = 0, wallHpRemaining = 0 }
		end
		data.stageProgress[stage] = { defendersRemaining = 0, wallHpRemaining = 1 }
		data.summonEnabled = true
		table.insert(data.battleRoster, makeMother())
		return data
	end

	local function countTrue(flags): number
		local total = 0
		for _, flag in flags do
			if flag == true then
				total += 1
			end
		end
		return total
	end

	print("── 4A จำนวนไข่ต่อด่านตรงตาราง (ด่าน 1 = 0 เพราะไม่มีกำแพง · 2–3 = 1 · 4–6 = 2 · 7–9 = 3) ──")

	do
		for stage = 1, Config.Balance.Stage.COUNT do
			check(`Config: ด่าน {stage} = {EXPECTED_BONUS[stage]} ฟอง`, Config.getStageClearBonusEggs(stage), EXPECTED_BONUS[stage])
		end
		for stage = 2, Config.Balance.Stage.COUNT do
			check(`ด่าน {stage} ตรงสูตร floor((ด่าน-1)/3)+1`, Config.getStageClearBonusEggs(stage), math.floor((stage - 1) / 3) + 1)
		end
		check("ขอบ: ด่าน 3 → 1", Config.getStageClearBonusEggs(3), 1)
		check("ขอบ: ด่าน 4 → 2", Config.getStageClearBonusEggs(4), 2)
		check("ขอบ: ด่าน 9 → 3", Config.getStageClearBonusEggs(9), 3)
		check("นอกช่วง (ด่าน 10) → 0", Config.getStageClearBonusEggs(10), 0)

		-- ผ่าน tick จริงทีละด่าน: ด่านเพิ่งพังต้องคืนจำนวนไข่ตามตาราง + ติดธงเฉพาะด่านนั้น
		for stage = 2, Config.Balance.Stage.COUNT do
			local data = dataAboutToClear(stage)
			local result = CombatService.tick(data, freshMeta(), 1)
			check(`tick พังด่าน {stage}: clearedStage`, result.clearedStage, stage)
			check(`tick พังด่าน {stage}: ได้ไข่ {EXPECTED_BONUS[stage]} ฟอง`, result.bonusEggs, EXPECTED_BONUS[stage])
			check(`  ติดธงด่าน {stage}`, data.stageClearBonusGranted[stage], true)
			check(`  ติดธงแค่ด่านเดียว`, countTrue(data.stageClearBonusGranted), 1)
		end
	end

	print("── 4A ให้รางวัลครั้งเดียวจริง: recompute/tick/claim ซ้ำหลังพังแล้ว ไม่ได้ไข่ซ้ำ ──")

	do
		local data = dataAboutToClear(2)
		local meta = freshMeta()
		local first = CombatService.tick(data, meta, 1)
		check("รอบแรก: ด่าน 2 พัง ได้ไข่ 1", first.bonusEggs, 1)
		check("  ธงด่าน 2 = true", data.stageClearBonusGranted[2], true)

		local totalBonus = 0
		for _ = 1, 5 do
			CombatService.recomputeWallProgress(data)
		end
		for _ = 1, 5 do
			table.insert(data.battleRoster, makeMother())
			totalBonus += CombatService.tick(data, meta, 1).bonusEggs
		end
		check("recompute ×5 + tick ×5 (ด่าน 3 ยังไม่พัง) → ไม่ได้ไข่เพิ่ม", totalBonus, 0)
		check("claim ด่าน 2 ซ้ำตรง ๆ → 0", CombatService.claimStageClearBonus(data, 2), 0)
		check("claim ด่าน 2 ซ้ำอีกรอบ → 0", CombatService.claimStageClearBonus(data, 2), 0)
		check("ธงยังติดแค่ด่านเดียว (ไม่ถูกเซ็ตซ้ำ/ลาม)", countTrue(data.stageClearBonusGranted), 1)
	end

	print("── 4A ด่าน 1 (ไม่มีกำแพง) พังฟรีตอนปล่อยครั้งแรก → ไม่ได้ไข่ ไม่ติดธง ──")

	do
		local data = freshData()
		data.summonEnabled = true
		table.insert(data.battleRoster, makeMother())
		local result = CombatService.tick(data, freshMeta(), 1)
		check("ด่าน 1 พัง", result.clearedStage, 1)
		check("  ไม่ได้ไข่", result.bonusEggs, 0)
		check("  ธงด่าน 1 ยังเป็น false", data.stageClearBonusGranted[1], false)
		check("claim ด่าน 1 ตรง ๆ ก็ได้ 0", CombatService.claimStageClearBonus(data, 1), 0)
	end

	print("── 4A ผู้เล่นเก่า (v2) พังด่าน 1–3 ไปก่อนอัปเดต → migrate แล้วไม่ได้ไข่ย้อนหลัง ──")

	do
		local old = freshData()
		old.schemaVersion = 2
		old.stageClearBonusGranted = nil
		for index = 1, 3 do
			old.stageProgress[index] = { defendersRemaining = 0, wallHpRemaining = 0 }
		end
		old.stageProgress[4] = { defendersRemaining = 0, wallHpRemaining = 1 }
		old.wallProgress = 3

		local migrated = PlayerData.migrate(old)
		check("migrate v2 → v3 สำเร็จ", migrated ~= nil, true)
		check("  ธงเป็น false ทั้ง 9 ช่อง (ด่านที่พังแล้วก็ false)", countTrue(migrated.stageClearBonusGranted), 0)
		check("  ธงยาว 9 ช่อง", #migrated.stageClearBonusGranted, 9)

		for _ = 1, 3 do
			CombatService.recomputeWallProgress(migrated)
		end
		check("recompute ซ้ำ → ไม่ติดธงให้ด่านเก่า", countTrue(migrated.stageClearBonusGranted), 0)

		migrated.summonEnabled = true
		table.insert(migrated.battleRoster, makeMother())
		local result = CombatService.tick(migrated, freshMeta(), 1)
		check("ด่าน 4 เพิ่งพังหลังอัปเดต → ได้ไข่ของด่าน 4 เท่านั้น (2 ฟอง)", result.bonusEggs, 2)
		check("  ธงด่าน 4 = true", migrated.stageClearBonusGranted[4], true)
		check("  ด่าน 1–3 ที่พังก่อนอัปเดตยังไม่ได้รางวัล (false)", countTrue(migrated.stageClearBonusGranted), 1)
	end

	print("── 4A stageClearBonusGranted ผ่าน encode/decode ครบ ──")

	do
		local data = dataAboutToClear(5)
		CombatService.tick(data, freshMeta(), 1)
		PlayerData.sanitizeForSave(data) -- ต้องไม่ throw (อาเรย์ boolean ยาวคงที่ ไม่มีรู)
		local back = Json.decode(PlayerData.encode(data))
		check("ธงด่าน 5 กลับมาเป็น true", back.stageClearBonusGranted[5], true)
		check("ธงด่าน 4 กลับมาเป็น false", back.stageClearBonusGranted[4], false)
		check("ยาว 9 ช่องเท่าเดิม", #back.stageClearBonusGranted, 9)
	end
end
