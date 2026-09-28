--!nocheck
-- egg-army-game :: ชุดเทสต์ Phase 5A — วงจรกลางวัน/กลางคืน · บอสตัวเดียวของเซิร์ฟ · ล็อกอัญเชิญ
--
-- BossService แยกฟังก์ชันสถานะ (newState/step/applyDamage/tryAttack/lockUser …) ออกจากส่วนที่แตะ Roblox
-- (start) → เทสต์ส่ง `now` เองได้ ไม่ต้องรอ 9 นาทีจริง · ส่วน CombatService ใช้ตัวจริงเหมือน combat.spec

local PlayerData = require("../src/shared/PlayerData")
local CombatService = require("../src/server/CombatService")
local BossService = require("../src/server/BossService")

return function(t, Config)
	local check = t.check
	local cycle = Config.Balance.BossCycle
	local DAY, NIGHT = cycle.DAY_SECONDS, cycle.NIGHT_SECONDS

	local function pos(x, z)
		return { X = x, Y = 0, Z = z }
	end

	----------------------------------------------------------------------------
	print("── 5A Config: 10 / 9 / 1 นาที · ลานบอสอยู่ด่านที่ไม่มีกำแพง · จุดยืน/จุดไข่ครบ ──")
	----------------------------------------------------------------------------
	do
		check("กลางวัน 9 นาที", DAY, 540)
		check("กลางคืน 1 นาที", NIGHT, 60)
		check("รอบละ 10 นาที", Config.getBossCycleSeconds(), 600)
		check("ลานบอสอยู่ด่าน 1", Config.MapDimensions.BossArena.Stage, 1)
		check("  ด่าน 1 ไม่มีกำแพง (ทุกคนเดินถึง)", Config.getWallX(Config.MapDimensions.BossArena.Stage), nil)
		check("  กึ่งกลางลาน = ห้องบอสด่าน 1", Config.getBossArenaCenter().X, Config.getBossNestCenter(1).X)

		-- 5B: กำแพงกั้นปิดช่องทางเข้าเลนพอดี (ช่องประตูของกำแพงหินขอบแมพฝั่งตะวันออก)
		local map = Config.MapDimensions
		local barrierSize = Config.getBossBarrierSize()
		check("กำแพงกั้นหนาไม่น้อยกว่าเกณฑ์ความเร็ว", barrierSize.X >= Config.getMinWallThickness(), true)
		check("กำแพงกั้นอยู่แนวเดียวกับกำแพงหินขอบแมพ (X 160)", Config.getBossBarrierX(), Config.getEastBoundaryX())
		check("  หนาเท่ากำแพงหิน", barrierSize.X, map.Boundary.Thickness)
		check("  สูงเท่ากำแพงหิน", barrierSize.Y, map.Boundary.Height)
		check("  กว้างเท่าช่องประตูพอดี (60)", barrierSize.Z, map.Lane.Width)
		check("  ผิวหน้า (ฝั่งลาน) = X 157.5", Config.getBossBarrierFrontX(), 157.5)
		check("  ผิวหลังไม่ล้ำเข้ากำแพงข้างเลน", Config.getBossBarrierX() + barrierSize.X / 2 <= Config.getLaneWallStartX(), true)
		local pedestal = Config.getSummonPedestalCenter()
		-- 5B-fix: แท่นอัญเชิญย้ายเข้าเลน (สนามรบ) หลังกำแพงกั้น · จุดกด E ไม่ทะลุออกมาฝั่งลาน
		check(
			"  แท่นอัญเชิญอยู่หลังกำแพงกั้น (ในสนามรบ)",
			pedestal.X - map.SummonPedestal.Diameter / 2 >= Config.getBossBarrierX() + barrierSize.X / 2,
			true
		)
		check("  จุดกด E ของแท่นกดจากฝั่งลานไม่ได้", pedestal.X - map.SummonPedestal.PromptDistance >= Config.getBossBarrierFrontX(), true)

		local minGap = math.huge
		local allInFront = true
		local allSafe = true
		for i = 1, Config.World.MAX_PENS do
			local a = Config.getBossGatherSpot(i)
			if a.X >= Config.getBossBarrierFrontX() then
				allInFront = false
			end
			if not Config.isInSafeZone(a) then
				allSafe = false
			end
			for j = i + 1, Config.World.MAX_PENS do
				local b = Config.getBossGatherSpot(j)
				minGap = math.min(minGap, math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2))
			end
		end
		check("จุดยืนหน้าป้อมครบทุกคนในเซิร์ฟ อยู่หน้ากำแพงกั้น (ฝั่งลาน) ทั้งหมด", allInFront, true)
		check("  ทุกจุดอยู่ในเซฟโซน", allSafe, true)
		check("  ไม่มีสองจุดซ้อนกัน (ห่าง ≥ 4)", minGap >= 4, true)

		check("จุดไข่ 6 จุด (5B)", cycle.EGGS_PER_NIGHT, 6)
		local boss = Config.getBossPosition()
		local behind = true
		for i = 1, cycle.EGGS_PER_NIGHT do
			local egg = Config.getBossCycleEggSpot(i)
			if egg.X <= boss.X + map.BossArena.BossSize.X / 2 then
				behind = false
			end
		end
		check("  ทุกจุดอยู่หลังตัวบอส", behind, true)

		check("isInBossArena: กลางห้องบอส", Config.isInBossArena(Config.getBossArenaCenter()), true)
		check("isInBossArena: ตัวบอส (มุมห้อง)", Config.isInBossArena(boss), true)
		check("isInBossArena: หน้าป้อม (ฝั่งลาน)", Config.isInBossArena(Config.getBossGatherSpot(1)), false)
		check("isInBossArena: ลานคอก", Config.isInBossArena(pos(0, 0)), false)

		check("ข้อความล็อกอัญเชิญ", Config.BOSS_LOCK_MESSAGE, "กำจัดบอสก่อนจึงจะอัญเชิญต่อได้")
		check("ข้อความบอสตาย", Config.formatBossEventMessage("killed"), "กำจัดบอสแล้ว!")
		check(
			"ข้อความติดล็อก (ส่งเฉพาะคนที่ติด) มีข้อความล็อกอยู่ในนั้น",
			string.find(Config.formatBossEventMessage("locked"), Config.BOSS_LOCK_MESSAGE, 1, true) ~= nil,
			true
		)
		check("ข้อความชนิดแปลก = ว่าง", Config.formatBossEventMessage("???"), "")

		-- ก่อน BossService.start() (เช่นในเทสต์/harness) ต้องไม่มีใครถูกล็อก และล็อกไม่ได้
		check("ก่อน start: ไม่มีใครติดล็อก", BossService.isLocked(1), false)
		check("ก่อน start: ไม่มีบอส", BossService.isBossAlive(), false)
		check("ก่อน start: ล็อกไม่ได้", BossService.lock(1), false)
		local gate = BossService.getGate()
		check("gate ครบ 3 ฟังก์ชัน", type(gate.isBossAlive) == "function" and type(gate.isUserLocked) == "function"
			and type(gate.lockUser) == "function", true)
	end

	----------------------------------------------------------------------------
	print("── 5A ตัวเลขนับถอยหลัง 59 → 0 (เลขละ 1 วินาที) ──")
	----------------------------------------------------------------------------
	do
		check("เริ่มคืน (เหลือ 60 เต็ม) → 59", Config.getBossCountdownValue(60), 59)
		check("เหลือ 59.5 → 59", Config.getBossCountdownValue(59.5), 59)
		check("เหลือ 59.0 → 58", Config.getBossCountdownValue(59), 58)
		check("เหลือ 30.2 → 30", Config.getBossCountdownValue(30.2), 30)
		check("เหลือ 1.0 → 0", Config.getBossCountdownValue(1), 0)
		check("เหลือ 0.4 → 0", Config.getBossCountdownValue(0.4), 0)
		check("หมดเวลาแล้ว (ติดลบ) → 0 ไม่ติดลบ", Config.getBossCountdownValue(-3), 0)
		check("เกินกลางคืน (ข้อมูลเพี้ยน) → ไม่เกิน 59", Config.getBossCountdownValue(500), 59)
		local seen = {}
		for s = 0, NIGHT - 1 do
			seen[Config.getBossCountdownValue(NIGHT - s - 0.5)] = true
		end
		local count = 0
		for _ in seen do
			count += 1
		end
		check("ตลอดคืนเห็นเลขครบ 60 ตัว (59 … 0)", count, 60)
	end

	----------------------------------------------------------------------------
	print("── 5A วงจร: เซิร์ฟเปิด = ต้นกลางวัน ไม่มีบอส · เปลี่ยนตรงจังหวะ 9:00 / 1:00 ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(1000)
		check("เริ่มกลางวัน", s.phase, "day")
		check("  ไม่มีบอสจนคืนแรก", s.bossAlive, false)
		check("  จบกลางวันที่ +540", s.phaseEndsAt, 1540)

		check("8:59.9 ยังกลางวัน (ไม่มีเหตุการณ์)", #BossService.step(s, 1539.9), 0)
		check("  phase ยังเป็น day", s.phase, "day")

		local events = BossService.step(s, 1540)
		check("9:00 พอดี → เข้ากลางคืน", events[1], "night")
		check("  phase = night", s.phase, "night")
		check("  บอสเกิด", s.bossAlive, true)
		check("  HP เต็ม", s.bossHp, cycle.BOSS_HP)
		check("  คืนที่ 1", s.cycle, 1)
		check("  จบกลางคืนที่ +600", s.phaseEndsAt, 1600)

		check("0:59.9 ของคืน ยังกลางคืน", #BossService.step(s, 1599.9), 0)
		local dayEvents = BossService.step(s, 1600)
		check("1:00 พอดี → เข้ากลางวัน", dayEvents[1], "day")
		check("  phase = day", s.phase, "day")
		check("  กลางวันใหม่จบที่ +1140", s.phaseEndsAt, 2140)
		check("  บอสยังอยู่ (ตีได้ตลอดกลางวัน)", s.bossAlive, true)

		-- ลูปหน่วงไป 3 วิ → เปลี่ยน phase ที่จังหวะเดิม ไม่เลื่อนรอบ
		local late = BossService.newState(0)
		BossService.step(late, 543)
		check("ลูปหน่วง 3 วิ: คืนยังจบที่ 600 (ไม่ใช่ 603)", late.phaseEndsAt, 600)
	end

	----------------------------------------------------------------------------
	print("── 5A เซิร์ฟค้างนานหลายรอบ → ข้ามรอบที่เลยไป ไม่วาป/แจ้งเตือนรัว ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		local events = BossService.step(s, 600 * 10 + 30) -- 10 รอบกับอีก 30 วิ (อยู่ในกลางวัน)
		check("เหตุการณ์ไม่เกิน 2 อัน", #events <= 2, true)
		check("  phase ถูกต้องตามเวลาจริง (กลางวัน)", s.phase, "day")
		check("  จบกลางวันถัดไปตรงจังหวะรอบเดิม", s.phaseEndsAt % 600, 540)
		check("  นับคืนครบ 10", s.cycle, 10)
	end

	----------------------------------------------------------------------------
	print("── 5A บอสไม่ตายข้ามคืน → เกิดใหม่ HP เต็ม · ตายแล้วไม่เกิดจนคืนถัดไป ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		BossService.step(s, 540) -- คืน 1
		BossService.step(s, 600) -- เช้า
		BossService.applyDamage(s, 111, 300, 610)
		check("ตีไป 300 → HP เหลือ 700", s.bossHp, cycle.BOSS_HP - 300)
		BossService.step(s, 1140) -- คืน 2 บอสยังไม่ตาย
		check("คืนถัดไปบอสยังไม่ตาย → HP เต็มอีกครั้ง", s.bossHp, cycle.BOSS_HP)
		check("  ยังมีชีวิต", s.bossAlive, true)
		check("  บันทึกผู้ทำดาเมจเริ่มใหม่ (บอสตัวใหม่)", s.damageBy[111], nil)

		BossService.step(s, 1200) -- เช้า
		local _, killed = BossService.applyDamage(s, 222, 99999, 1300)
		check("ฆ่าได้", killed, true)
		check("  ตายแล้ว", s.bossAlive, false)
		check("  เวลาตายถูกบันทึก", s.bossDiedAt, 1300)
		check("  บันทึกผู้ทำดาเมจยังอยู่หลังตาย (5B อ่านได้)", s.damageBy[222], cycle.BOSS_HP)

		BossService.step(s, 1739) -- ยังกลางวันเดิม
		check("ตายแล้วไม่เกิดระหว่างวัน", s.bossAlive, false)
		BossService.step(s, 1740) -- คืน 3
		check("คืนถัดไปเกิดใหม่", s.bossAlive, true)
		check("  HP เต็ม", s.bossHp, cycle.BOSS_HP)
	end

	----------------------------------------------------------------------------
	print("── 5A ดาเมจ: กลางคืน/ไม่มีบอส ตีไม่เข้า · เกิน HP นับเท่าที่เข้าจริง · บันทึกรายคน ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		local dealt = BossService.applyDamage(s, 1, 50, 10)
		check("กลางวันแรก ไม่มีบอส → ตีไม่เข้า", dealt, 0)
		BossService.step(s, 540)
		dealt = BossService.applyDamage(s, 1, 50, 545)
		check("กลางคืน (บอสอยู่หลังกำแพงกั้น) → ตีไม่เข้า", dealt, 0)
		check("  HP ไม่ลด", s.bossHp, cycle.BOSS_HP)

		BossService.step(s, 600)
		BossService.applyDamage(s, 1, 100, 601)
		BossService.applyDamage(s, 2, 250, 602)
		BossService.applyDamage(s, 1, 50, 603)
		check("บันทึก: คน 1 = 150", s.damageBy[1], 150)
		check("บันทึก: คน 2 = 250", s.damageBy[2], 250)
		local list = BossService.getContributors(s)
		check("เรียงมาก → น้อย: อันดับ 1 = คน 2", list[1].userId, 2)
		check("  อันดับ 2 = คน 1", list[2].userId, 1)

		local last, killed = BossService.applyDamage(s, 3, 99999, 604)
		check("ฟันสุดท้ายเกิน HP → นับเท่าที่เหลือจริง", last, cycle.BOSS_HP - 400)
		check("  ฆ่าได้", killed, true)
		local total = 0
		for _, entry in BossService.getContributors(s) do
			total += entry.damage
		end
		check("ผลรวมดาเมจที่บันทึก = HP เต็มพอดี", total, cycle.BOSS_HP)
		check("ตีศพต่อ → ไม่เข้า", (BossService.applyDamage(s, 1, 10, 605)), 0)
	end

	----------------------------------------------------------------------------
	print("── 5A ตีด้วยอาวุธ: server ตรวจ กลางวัน · บอสอยู่ · คูลดาวน์ · ระยะ · ดาเมจจาก weaponLevel ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		BossService.step(s, 540)
		check("กลางคืน → night", (BossService.tryAttack(s, 7, 541, 5, 1)), "night")
		BossService.step(s, 600)
		local result, dealt = BossService.tryAttack(s, 7, 601, 5, 1)
		check("ใกล้ + กลางวัน → ok", result, "ok")
		check("  ดาเมจ = Config.getWeaponDamage(1)", dealt, Config.getWeaponDamage(1))
		check("ฟันถี่เกินคูลดาวน์ → cooldown", (BossService.tryAttack(s, 7, 601 + cycle.PLAYER_ATTACK_COOLDOWN / 2, 5, 1)), "cooldown")
		check("ครบคูลดาวน์ → ok", (BossService.tryAttack(s, 7, 601 + cycle.PLAYER_ATTACK_COOLDOWN, 5, 1)), "ok")
		check("คนอื่นไม่ติดคูลดาวน์ของเรา", (BossService.tryAttack(s, 8, 601.1, 5, 1)), "ok")
		check("ไกลเกินระยะ → range", (BossService.tryAttack(s, 9, 610, cycle.PLAYER_ATTACK_RANGE + 1, 1)), "range")
		-- บอสตัวใหม่ HP เต็ม (ตัวบนโดนไปแล้ว — ดาเมจจะถูกตัดที่ HP ที่เหลือ)
		local fresh = BossService.newState(0)
		BossService.step(fresh, 540)
		BossService.step(fresh, 600)
		local _, dealt3 = BossService.tryAttack(fresh, 10, 611, 5, 3)
		check("อาวุธขั้น 3 → ดาเมจตามสูตรเดิม", dealt3, math.min(Config.getWeaponDamage(3), cycle.BOSS_HP))
		BossService.applyDamage(s, 10, 99999, 612)
		check("บอสตายแล้ว → dead", (BossService.tryAttack(s, 11, 620, 5, 1)), "dead")
		check("ระยะแนวราบไม่นับแกน Y", BossService.horizontalDistance({ X = 0, Y = 100, Z = 0 }, { X = 3, Y = 0, Z = 4 }), 5)
	end

	----------------------------------------------------------------------------
	print("── 5A บอสตีกลับ: ปิดไว้ใน config → ไม่เลือกใครเลย ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		BossService.step(s, 540)
		BossService.step(s, 600)
		local near = { [1] = pos(Config.getBossArenaCenter().X + 3, 0) }
		check("BOSS_ATTACK_ENABLED = false", cycle.BOSS_ATTACK_ENABLED, false)
		check("  ไม่มีเป้าหมาย", #BossService.pickCounterTargets(s, Config.getBossArenaCenter(), near), 0)
		-- เปิดชั่วคราวเพื่อตรวจการเลือกเป้า แล้วคืนค่าเดิม
		cycle.BOSS_ATTACK_ENABLED = true
		local positions = {
			[1] = pos(Config.getBossArenaCenter().X + 3, 0),
			[2] = pos(Config.getBossArenaCenter().X + cycle.BOSS_ATTACK_RANGE + 5, 0),
		}
		local targets = BossService.pickCounterTargets(s, Config.getBossArenaCenter(), positions)
		check("เปิดแล้ว: เลือกเฉพาะคนในระยะ", #targets == 1 and targets[1] == 1, true)
		cycle.BOSS_ATTACK_ENABLED = false
	end

	----------------------------------------------------------------------------
	print("── 5A ล็อกอัญเชิญ: เฉพาะตอนบอสมีชีวิต · ไม่ปลดข้ามคืน · บอสตาย = ปลดทุกคน ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		check("ไม่มีบอส → ล็อกไม่ได้", BossService.lockUser(s, 5), false)
		check("  ไม่ติดล็อก", BossService.isUserLocked(s, 5), false)
		BossService.step(s, 540)
		check("บอสอยู่ → ล็อกได้", BossService.lockUser(s, 5), true)
		BossService.lockUser(s, 6)
		check("  คน 5 ติดล็อก", BossService.isUserLocked(s, 5), true)
		check("  คนอื่นไม่ติดด้วย", BossService.isUserLocked(s, 7), false)
		BossService.step(s, 600)
		BossService.step(s, 1140) -- คืนถัดไป บอสยังไม่ตาย → ฟื้น HP เต็ม
		check("บอสไม่ตายข้ามคืน → ยังล็อกอยู่", BossService.isUserLocked(s, 5), true)
		BossService.step(s, 1200)
		BossService.applyDamage(s, 99, 99999, 1210)
		check("บอสตาย → คน 5 ปลดล็อก", BossService.isUserLocked(s, 5), false)
		check("  คน 6 ปลดล็อกพร้อมกัน", BossService.isUserLocked(s, 6), false)
		check("บอสตายแล้วพังกำแพง → ไม่ล็อก", BossService.lockUser(s, 5), false)
		BossService.step(s, 1740)
		check("คืนถัดไปบอสเกิดใหม่ → พังกำแพงอีกครั้งก็ล็อกได้อีก", BossService.lockUser(s, 5), true)
	end

	----------------------------------------------------------------------------
	print("── 5A CombatService.shouldBossLock: เฉพาะด่านที่มีกำแพงจริง + บอสยังอยู่ ──")
	----------------------------------------------------------------------------
	do
		check("ด่าน 1 (ไม่มีกำแพง) พัง + บอสอยู่ → ไม่ล็อก (ผู้เล่นใหม่ไม่ติดตั้งแต่วินาทีแรก)", CombatService.shouldBossLock(1, true), false)
		check("ด่าน 2 พัง + บอสอยู่ → ล็อก", CombatService.shouldBossLock(2, true), true)
		check("ด่าน 9 พัง + บอสอยู่ → ล็อก", CombatService.shouldBossLock(9, true), true)
		check("ด่าน 2 พัง + บอสตายแล้ว → ไม่ล็อก", CombatService.shouldBossLock(2, false), false)
		check("ไม่มีด่านพัง → ไม่ล็อก", CombatService.shouldBossLock(nil, true), false)
	end

	----------------------------------------------------------------------------
	print("── 5A ล็อกหลัง tick ไม่กระทบการผ่านด่าน · รางวัล 4A · แม่ตาย ──")
	----------------------------------------------------------------------------
	do
		local function makeMother(n)
			return {
				uid = Config.makeUid(515151, n),
				charId = "monkey",
				weight = 100,
				statuses = {},
				obtainedAt = 0,
				locked = false,
			}
		end
		local function aboutToClearStage2()
			local data = PlayerData.createNew()
			data.stageProgress[1] = { defendersRemaining = 0, wallHpRemaining = 0 }
			data.stageProgress[2] = { defendersRemaining = 0, wallHpRemaining = 1 }
			data.summonEnabled = true
			table.insert(data.battleRoster, makeMother(1))
			table.insert(data.battleRoster, makeMother(2))
			return data
		end

		-- ผลของ tick ตอนไม่มีบอส (ฐานเปรียบเทียบ) กับตอนมีบอส ต้องเหมือนกันทุกช่อง — ล็อกเกิด "หลัง" tick
		local base = aboutToClearStage2()
		local baseResult = CombatService.tick(base, CombatService.newMeta(), 1)

		local s = BossService.newState(0)
		BossService.step(s, 540) -- บอสอยู่
		local data = aboutToClearStage2()
		local meta = CombatService.newMeta()
		local result = CombatService.tick(data, meta, 1)
		if CombatService.shouldBossLock(result.clearedStage, s.bossAlive) then
			BossService.lockUser(s, 42)
			CombatService.applyBossLock(data)
		end

		check("ด่าน 2 พังเหมือนไม่มีบอส", result.clearedStage, baseResult.clearedStage)
		check("  ไข่รางวัล 4A เท่าเดิม", result.bonusEggs, baseResult.bonusEggs)
		check("  แม่ตายเท่าเดิม", result.mothersLost, baseResult.mothersLost)
		check("  ธงรางวัลด่าน 2 ติด", data.stageClearBonusGranted[2], true)
		check("  wallProgress ขยับตามเดิม", data.wallProgress, base.wallProgress)
		check("  roster ถูกล้างตามเดิม", #data.battleRoster, 0)
		check("ติดล็อก", BossService.isUserLocked(s, 42), true)
		check("  อัญเชิญถูกปิด (ทหารหยุด)", data.summonEnabled, false)

		local after = CombatService.tick(data, meta, 5)
		check("tick ถัดไปไม่ปล่อยทหาร", after.unitsReleased, 0)
		check("  ด่าน 3 ไม่ถูกตี", data.stageProgress[3], false)
	end

	----------------------------------------------------------------------------
	print("── 5A ติดล็อก: เปิดอัญเชิญ/ส่งแม่ถูกปฏิเสธ · รวมกับ auto-pause (ไม่แทนที่) · sync บอกเหตุผล ──")
	----------------------------------------------------------------------------
	do
		local data = PlayerData.createNew()
		data.stageProgress[1] = { defendersRemaining = 0, wallHpRemaining = 0 }
		data.stageProgress[2] = { defendersRemaining = 0, wallHpRemaining = 0 }
		CombatService.ensureStageStarted(data, 3)
		data.summonEnabled = false
		data.combatAutoPaused = true -- auto-pause เดิมค้างอยู่ด้วย
		local meta = CombatService.newMeta()

		check("ติดล็อก + ขอเปิด → ปฏิเสธ", CombatService.handleSetSummonEnabled(data, meta, true, true), false)
		check("  อัญเชิญยังปิด", data.summonEnabled, false)
		check("  ธง auto-pause ไม่ถูกล้าง (ไม่ได้เปิดจริง)", data.combatAutoPaused, true)
		check("ติดล็อก + ขอปิด → ได้", CombatService.handleSetSummonEnabled(data, meta, false, true), true)
		check("ไม่ติดล็อก + ขอเปิด → ได้ (auto-pause เดิมทำงานเหมือนเดิม)", CombatService.handleSetSummonEnabled(data, meta, true, false), true)
		check("  เปิดแล้วล้างธง auto-pause ตามเดิม", data.combatAutoPaused, false)
		check("ไม่ส่งพารามิเตอร์ล็อก = พฤติกรรมเดิม", CombatService.handleSetSummonEnabled(data, meta, true), true)

		check("เหตุผลส่งแม่ตอนติดล็อก", CombatService.getSendStageBlockReason(data, true), Config.BOSS_LOCK_MESSAGE)
		check("ไม่ติดล็อก → ส่งแม่ได้ (ด่าน 3 มีศัตรู)", CombatService.getSendStageBlockReason(data, false), nil)
		local cleared = PlayerData.createNew()
		for stage = 1, Config.Balance.Stage.COUNT do
			cleared.stageProgress[stage] = { defendersRemaining = 0, wallHpRemaining = 0 }
		end
		check("ผ่านครบทุกด่าน + ติดล็อก → บอกว่าผ่านครบ (ความจริงที่ตรงกว่า)", CombatService.getSendStageBlockReason(cleared, true), "ผ่านครบทุกด่านแล้ว ไม่มีด่านให้ส่งแม่ไปรบ")

		local mother = {
			uid = Config.makeUid(616161, 1),
			charId = "monkey",
			weight = 100,
			statuses = {},
			obtainedAt = 0,
			locked = false,
		}
		table.insert(data.mothersInBag, mother)
		local ok, message = CombatService.handleSendMotherToBattle(data, mother.uid, true)
		check("ส่งแม่ทีละตัวตอนติดล็อก → ปฏิเสธ", ok, false)
		check("  ข้อความล็อกบอส", message, Config.BOSS_LOCK_MESSAGE)
		local batchOk, reason, summary = CombatService.handleSendMothersToBattleBatch(data, { mother.uid }, true)
		check("ส่งแม่เป็นชุดตอนติดล็อก → ปฏิเสธทั้งชุด", batchOk == false and summary == nil, true)
		check("  ข้อความล็อกบอส", reason, Config.BOSS_LOCK_MESSAGE)
		check("  แม่ยังอยู่ในกระเป๋า", #data.mothersInBag, 1)

		local locked = CombatService.buildSyncFields(data, true)
		check("sync: summonBlockReason = ข้อความล็อก", locked.summonBlockReason, Config.BOSS_LOCK_MESSAGE)
		check("sync: bossLocked = true", locked.bossLocked, true)
		check("sync: sendStageBlockReason = ข้อความล็อก", locked.sendStageBlockReason, Config.BOSS_LOCK_MESSAGE)
		local free = CombatService.buildSyncFields(data)
		check("sync ไม่ติดล็อก: summonBlockReason = nil", free.summonBlockReason, nil)
		check("  bossLocked = false", free.bossLocked, false)
	end

	--==========================================================================
	-- Phase 5B — ไข่บอส 6 ฟอง · หยิบแล้ววิ่งกลับเซฟโซน · แบ่งเงิน · แจ้งเตือนไข่หนัก · ผังใหม่
	--==========================================================================
	-- ตัวสุ่ม stub: lowRng = ได้ค่าต่ำสุดทุกครั้ง (tier 1 · 100 kg) · highRng = สูงสุด (tier 7 · 100M kg)
	local lowRng = { NextInteger = function(_self, lo, _hi) return lo end }
	local highRng = { NextInteger = function(_self, _lo, hi) return hi end }
	local arena = Config.MapDimensions.BossArena
	local pickupRange = arena.EggPickupRange

	-- บอสตายแล้ว (ต้นกลางวันแรก ฆ่าทิ้ง) พร้อมไข่ 6 ฟอง — ใช้ซ้ำหลายเทสต์
	local function killedState(rng)
		local s = BossService.newState(0, rng or lowRng)
		BossService.step(s, DAY) -- กลางคืนแรก: บอส + ไข่ 6 ฟอง
		BossService.step(s, DAY + NIGHT) -- เช้า
		BossService.applyDamage(s, 900, s.bossHp, DAY + NIGHT + 1)
		return s
	end

	----------------------------------------------------------------------------
	print("── 5B ไข่บอส: เกิด 6 ฟองพร้อมบอส · น้ำหนักสุ่มตอนเกิด · ชนิดไข่เดิม ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		check("เซิร์ฟเปิด (ยังไม่ถึงคืนแรก) = ยังไม่มีไข่", #s.eggs, 0)
		check("  หยิบตอนยังไม่มีไข่ → taken", (BossService.pickUpEgg(s, 1, 1, 0, true)), "taken")
		BossService.step(s, DAY)
		check("ต้นกลางคืน: ไข่ 6 ฟองเกิดพร้อมบอส", #s.eggs, 6)
		local allResting, allTypeOk, allWeightOk = true, true, true
		for index, egg in s.eggs do
			if egg.status ~= "resting" or egg.index ~= index or egg.carrier ~= nil then
				allResting = false
			end
			if egg.eggId ~= cycle.EGG_ID then
				allTypeOk = false
			end
			if egg.weight ~= 100 or egg.weight % 1 ~= 0 then
				allWeightOk = false
			end
		end
		check("  ทุกฟองวางอยู่ (resting) ไม่มีคนถือ", allResting, true)
		check("  ชนิดไข่ = ไข่ที่มีอยู่แล้ว (BossCycle.EGG_ID)", allTypeOk, true)
		check("  ชนิดไข่บอส = egg_stage1 (ไข่ด่าน 1 · ไม่ได้สร้างชนิดใหม่)", cycle.EGG_ID, "egg_stage1")
		check("  น้ำหนักสุ่มแล้วตั้งแต่บอสเกิด (ตัวสุ่มเดิม · จำนวนเต็ม)", allWeightOk, true)
		local fixed = s.eggs[1].weight
		BossService.step(s, DAY + NIGHT) -- เช้า — น้ำหนักต้องไม่ถูกสุ่มใหม่
		check("  เช้าแล้วน้ำหนักไม่เปลี่ยน (ไม่สุ่มใหม่)", s.eggs[1].weight, fixed)

		local heavy = BossService.newState(0, highRng)
		BossService.step(heavy, DAY)
		check("ตัวสุ่มสูงสุด → ไข่ tier 7 (100M kg) ตามตารางเดิม", heavy.eggs[1].weight, 100000000)
	end

	----------------------------------------------------------------------------
	print("── 5B หยิบไข่: ก่อนบอสตายไม่ได้ · ถือทีละฟอง · ไกลถูกปฏิเสธ · index แปลกทิ้ง ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		check("กลางคืน (บอสอยู่) หยิบไม่ได้ → alive", (BossService.pickUpEgg(s, 1, 1, 0, true)), "alive")
		BossService.step(s, DAY + NIGHT)
		check("กลางวัน บอสยังอยู่ → alive", (BossService.pickUpEgg(s, 1, 1, 0, true)), "alive")
		check("  ไข่ยังวางอยู่", s.eggs[1].status, "resting")
		BossService.applyDamage(s, 900, s.bossHp, DAY + NIGHT + 1)
		check("บอสตายแล้ว → ไม่มีบอส", s.bossAlive, false)

		local result, egg = BossService.pickUpEgg(s, 1, 1, 0, true)
		check("บอสตาย + ในห้อง + ใกล้ → หยิบได้ (ไม่ต้องเคยตีบอส)", result, "ok")
		check("  ได้ไข่ฟองที่ 1", egg and egg.index, 1)
		check("  สถานะ carried · คนถือ = userId 1", s.eggs[1].status == "carried" and s.eggs[1].carrier == 1, true)
		check("  getCarriedEgg คืนฟองที่ถือ", BossService.getCarriedEgg(s, 1), s.eggs[1])

		check("ถืออยู่แล้วหยิบฟองที่ 2 → carrying (ถือได้ทีละฟอง)", (BossService.pickUpEgg(s, 1, 2, 0, true)), "carrying")
		check("  ฟองที่ 2 ยังวางอยู่", s.eggs[2].status, "resting")
		check("คนอื่นหยิบฟองที่มีคนถือ → taken", (BossService.pickUpEgg(s, 2, 1, 0, true)), "taken")

		check("ไกลกว่าระยะหยิบ → range", (BossService.pickUpEgg(s, 2, 2, pickupRange + 0.01, true)), "range")
		check("ไม่อยู่ในห้อง (แม้ใกล้) → range", (BossService.pickUpEgg(s, 2, 2, 0, false)), "range")
		check("  ถูกปฏิเสธแล้วไข่ยังวางอยู่", s.eggs[2].status, "resting")
		check("ระยะพอดีขอบ → หยิบได้", (BossService.pickUpEgg(s, 2, 2, pickupRange, true)), "ok")

		for _, bad in { 0, 7, 1.5, -1, 0 / 0, "1", nil, true } do
			check(`index แปลก ({tostring(bad)}) → invalid`, (BossService.pickUpEgg(s, 3, bad, 0, true)), "invalid")
		end
		check("  คำขอแปลกไม่ทำให้ใครถือไข่", BossService.getCarriedEgg(s, 3), nil)
	end

	----------------------------------------------------------------------------
	print("── 5B ส่งไข่: เข้าเซฟโซนได้ไข่ครั้งเดียวพอดี (ทางเพิ่มไข่เดิม) · เต็มแล้วยังถือค้าง ──")
	----------------------------------------------------------------------------
	do
		local s = killedState()
		local data = PlayerData.createNew()
		local grantCalls = 0
		local function grant(eggId, weight)
			grantCalls += 1
			return PlayerData.addHeldEgg(data.heldEggs, eggId, weight) ~= nil
		end
		local before = #data.heldEggs.items
		check("ไม่ได้ถือไข่ → none", (BossService.tryDeliver(s, 1, pos(0, 0), grant)), "none")

		BossService.pickUpEgg(s, 1, 4, 0, true)
		local carried = s.eggs[4]
		local inLane = pos(Config.getSafeZoneEdgeX() + 1, 0)
		check("ยังอยู่ในเลน (ไม่ถึงเซฟโซน) → outside", (BossService.tryDeliver(s, 1, inLane, grant)), "outside")
		check("  ยังไม่เรียกทางเพิ่มไข่", grantCalls, 0)

		local safe = pos(Config.getSafeZoneEdgeX() - 1, 0)
		local result, egg = BossService.tryDeliver(s, 1, safe, grant)
		check("เข้าเซฟโซน → delivered", result, "delivered")
		check("  ไข่เข้ากระเป๋า 1 ฟอง", #data.heldEggs.items, before + 1)
		local added = data.heldEggs.items[#data.heldEggs.items]
		check("  น้ำหนักเท่าที่สุ่มไว้ตอนบอสเกิด (ไม่สุ่มใหม่)", added.weight, carried.weight)
		check("  ชนิดไข่ตรง", added.eggId, cycle.EGG_ID)
		check("  คืนไข่ฟองที่ส่ง", egg, carried)
		check("  ไข่ฟองนั้นหมดไป (gone)", carried.status, "gone")
		check("  ไม่ได้ถืออะไรแล้ว", BossService.getCarriedEgg(s, 1), nil)
		check("เรียกซ้ำ (ยืนในเซฟโซนต่อ) → none", (BossService.tryDeliver(s, 1, safe, grant)), "none")
		check("  ได้ไข่ครั้งเดียวพอดี", #data.heldEggs.items, before + 1)
		check("  ทางเพิ่มไข่ถูกเรียกครั้งเดียว", grantCalls, 1)
		check("หยิบฟองที่เก็บไปแล้วซ้ำ → taken", (BossService.pickUpEgg(s, 1, 4, 0, true)), "taken")

		-- กระเป๋าเต็ม → เข้ากระเป๋าไม่ได้ ยังถือค้าง (ไม่หาย ไม่งอก)
		BossService.pickUpEgg(s, 1, 5, 0, true)
		local full = function()
			return false
		end
		check("กระเป๋าเต็ม → full", (BossService.tryDeliver(s, 1, safe, full)), "full")
		check("  ยังถือฟองเดิมอยู่", BossService.getCarriedEgg(s, 1), s.eggs[5])
		check("  สถานะยัง carried", s.eggs[5].status, "carried")
		check("มีที่ว่างแล้ว → delivered", (BossService.tryDeliver(s, 1, safe, grant)), "delivered")

		-- หยิบครบ 6 ฟองแล้วหยิบไม่ได้อีก
		for index = 1, cycle.EGGS_PER_NIGHT do
			if s.eggs[index].status == "resting" then
				BossService.pickUpEgg(s, 1, index, 0, true)
				BossService.tryDeliver(s, 1, safe, grant)
			end
		end
		local anyLeft = false
		for index = 1, cycle.EGGS_PER_NIGHT do
			if (BossService.pickUpEgg(s, 77, index, 0, true)) ~= "taken" then
				anyLeft = true
			end
		end
		check("หมด 6 ฟองแล้ว ทุกฟองหยิบไม่ได้ (taken)", anyLeft, false)
		check("  ได้ไข่รวมพอดี 6 ฟอง (ไม่เกิน)", #data.heldEggs.items, before + 6)
	end

	----------------------------------------------------------------------------
	print("── 5B ออกเกม/ตายระหว่างถือ → ไข่กลับจุดเดิม · กลางคืนระหว่างถือ → หาย ไม่มีไข่ฟรี ──")
	----------------------------------------------------------------------------
	do
		local s = killedState()
		BossService.pickUpEgg(s, 1, 3, 0, true)
		local dropped = BossService.dropCarriedEgg(s, 1)
		check("ออกเกมระหว่างถือ → ไข่กลับจุดเดิม (resting)", dropped and dropped.status, "resting")
		check("  ไม่มีคนถือ", s.eggs[3].carrier, nil)
		check("  คนอื่นหยิบใหม่ได้", (BossService.pickUpEgg(s, 2, 3, 0, true)), "ok")
		check("ทิ้งตอนไม่ได้ถือ → nil (ไม่พัง)", BossService.dropCarriedEgg(s, 1), nil)

		-- คนที่ 2 ถือฟองที่ 3 ค้างไว้จนกลางคืน
		local oldEggs = s.eggs
		local data = PlayerData.createNew()
		local before = #data.heldEggs.items
		local events = BossService.step(s, DAY + NIGHT + DAY) -- คืนที่สอง
		check("ถึงกลางคืน", events[1], "night")
		check("  ไข่ชุดใหม่ 6 ฟอง (คนละชุด)", #s.eggs == 6 and s.eggs ~= oldEggs, true)
		local allFresh = true
		for _, egg in s.eggs do
			if egg.status ~= "resting" or egg.carrier ~= nil then
				allFresh = false
			end
		end
		check("  ทุกฟองของชุดใหม่วางอยู่", allFresh, true)
		check("  ไข่ที่ถือหาย (ไม่มีใครถืออะไร)", BossService.getCarriedEgg(s, 2), nil)
		check("  จดคนที่ไข่หายไว้แจ้งเตือน", table.concat(s.lostCarriers, ","), "2")
		local result = BossService.tryDeliver(s, 2, pos(0, 0), function(eggId, weight)
			return PlayerData.addHeldEgg(data.heldEggs, eggId, weight) ~= nil
		end)
		check("  วิ่งเข้าเซฟโซนหลังไข่หาย → none (ไม่ได้ไข่ฟรี)", result, "none")
		check("  กระเป๋าไม่เพิ่ม", #data.heldEggs.items, before)
		check("  คืนนี้บอสเกิดใหม่ → หยิบไม่ได้จนกว่าจะตาย", (BossService.pickUpEgg(s, 2, 1, 0, true)), "alive")
	end

	----------------------------------------------------------------------------
	print("── 5B ประกาศไข่หนัก: เฉพาะไข่ที่หนักเกิน 100,000 kg ──")
	----------------------------------------------------------------------------
	do
		check("เกณฑ์ประกาศ = 100,000 kg (Config)", cycle.HEAVY_EGG_ALERT_KG, 100000)
		local s = BossService.newState(0, lowRng)
		check("ยังไม่มีไข่ → ไม่ประกาศ", BossService.getHeavyEggAlert(s), nil)
		BossService.step(s, DAY)
		check("ไข่ tier 1 ทั้งหมด → ไม่ประกาศ", BossService.getHeavyEggAlert(s), nil)
		s.eggs[3].weight = 100000
		check("หนัก 100,000 พอดี (ไม่เกิน) → ไม่ประกาศ", BossService.getHeavyEggAlert(s), nil)
		s.eggs[5].weight = 152300
		check("มีฟองหนัก 152,300 → ประกาศน้ำหนักฟองที่หนักสุด", BossService.getHeavyEggAlert(s), 152300)
		s.eggs[1].weight = 999999
		check("  หลายฟองเกิน → ประกาศฟองที่หนักสุด", BossService.getHeavyEggAlert(s), 999999)
		check(
			"ข้อความประกาศ",
			Config.formatBossEventMessage("heavy", 152300),
			"🥚 คืนนี้บอสเฝ้าไข่ 152,300 กก.!"
		)
		local heavy = BossService.newState(0, highRng)
		BossService.step(heavy, DAY)
		check("ตัวสุ่มสูงสุด (tier 7) → ประกาศ 100M", BossService.getHeavyEggAlert(heavy), 100000000)
	end

	----------------------------------------------------------------------------
	print("── 5B เงินบอส: แบ่งเท่ากัน (ปัดลง) เฉพาะคนที่ตีและยังอยู่ในห้อง · รวมไม่เกินก้อน ──")
	----------------------------------------------------------------------------
	do
		local total = cycle.KILL_REWARD
		check("เงินก้อนบอส (ชั่วคราว) = 10,000", total, 10000)
		check("  เท่าเงินบอสด่าน 1 ของโมเดลสมดุล", total, Config.getBossKillReward(1))

		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		BossService.step(s, DAY + NIGHT)
		BossService.applyDamage(s, 11, 600, DAY + NIGHT + 1)
		BossService.applyDamage(s, 22, 300, DAY + NIGHT + 2)
		BossService.applyDamage(s, 33, s.bossHp, DAY + NIGHT + 3) -- คนฆ่า
		check("บอสตายแล้ว", s.bossAlive, false)
		local present = { [11] = true, [22] = false, [33] = true, [44] = true }
		local share, recipients = BossService.planReward(s, function(userId)
			return present[userId] == true
		end)
		check("ได้เฉพาะคนที่ตี + ยังอยู่ในห้อง (11, 33)", table.concat(recipients, ","), "11,33")
		check("  คนที่ตีแต่ออกนอกห้อง/หลุด (22) ไม่ได้", table.find(recipients, 22), nil)
		check("  คนที่อยู่ในห้องแต่ไม่ได้ตี (44) ไม่ได้", table.find(recipients, 44), nil)
		check("  แบ่งเท่ากัน ไม่ตามสัดส่วนดาเมจ", share, 5000)
		check("  รวมไม่เกินก้อน", share * #recipients <= total, true)

		present[22] = true
		local share3, three = BossService.planReward(s, function(userId)
			return present[userId] == true
		end)
		check("3 คน → คนละ 3,333 (ปัดลง)", share3, 3333)
		check("  รวม 9,999 ไม่เกิน 10,000 (ไม่งอกเงินจากการปัด)", share3 * #three, 9999)
		local shareNone, nobody = BossService.planReward(s, function()
			return false
		end)
		check("ไม่มีใครอยู่ในห้อง → ไม่มีใครได้ · 0", #nobody == 0 and shareNone == 0, true)
		check("splitReward(7, 3) = 2", BossService.splitReward(7, 3), 2)
		check("splitReward(x, 0) = 0", BossService.splitReward(total, 0), 0)

		s.damageBy[55] = 0.5
		local _, withTiny = BossService.planReward(s, function()
			return true
		end)
		check("ดาเมจต่ำกว่า BOSS_REWARD_MIN_DAMAGE ไม่นับว่าร่วมตี", table.find(withTiny, 55), nil)
		check(
			"ข้อความรายคน",
			Config.formatBossEventMessage("reward", 3333, 3),
			"ได้ $3,333 จากบอส (แบ่ง 3 คน)"
		)
		check("ข้อความเก็บไข่เริ่มด้วย \"เก็บไข่บอสแล้ว\"", string.sub(Config.formatBossEventMessage("delivered", 500), 1, #"เก็บไข่บอสแล้ว"), "เก็บไข่บอสแล้ว")
		check("หยิบไม่ได้ = toast สีเตือน", Config.isBossEventWarning("pickupRange"), true)
		check("ได้เงิน = toast สีปกติ", Config.isBossEventWarning("reward"), false)
	end

	----------------------------------------------------------------------------
	print("── 5B ผัง: โซน · กำแพงกั้นปิดปากเลน · พื้นปากเลน · บอส/ไข่มุมห้อง สลับฟันปลา ──")
	----------------------------------------------------------------------------
	do
		local map = Config.MapDimensions
		local edge = Config.getSafeZoneEdgeX()
		check("ขอบเซฟโซน = ผิวหน้ากำแพงกั้น (X 157.5)", edge, 157.5)
		check("สนามรบ (5B-fix): แท่นอัญเชิญ", Config.isInSafeZone(Config.getSummonPedestalCenter()), false)
		check("  แท่นอัญเชิญอยู่ในห้องด่าน 1", Config.isInBossArena(Config.getSummonPedestalCenter()), true)
		check("เซฟโซน: กลางลานคอก", Config.isInSafeZone(pos(0, 0)), true)
		local spawnsSafe = true
		for index = 1, Config.World.MAX_PENS do
			if not Config.isInSafeZone(Config.getSpawnPointForPen(index)) then
				spawnsSafe = false
			end
		end
		check("เซฟโซน: จุดเกิดทุกคอก", spawnsSafe, true)
		check("ขอบพอดี (157.5) = สนามรบแล้ว", Config.isInSafeZone(pos(edge, 0)), false)
		local minX, maxX = Config.getStageRoomRangeX(1)
		check("ห้องด่าน 1 เริ่มที่ปากเลน (ขอบเซฟโซน)", minX, edge)
		check("ห้องด่าน 1 จบที่ผิวหน้ากำแพงด่าน 2 (X 317.5)", maxX, Config.getWallX(2) - map.StageWall.Thickness / 2)
		check("ในห้องด่าน 1: กลางเลน", Config.isInStageRoom(1, pos(200, 0)), true)
		check("ไม่ใช่ห้องด่าน 1: เลยกำแพงด่าน 2", Config.isInStageRoom(1, pos(330, 0)), false)
		check("ไม่ใช่ห้องด่าน 1: ลานคอก", Config.isInStageRoom(1, pos(100, 0)), false)

		check("พื้นเลนเริ่มที่แนวกำแพงหิน (ไม่ยื่นบนหญ้า)", Config.getLaneFloorStartX(), 157.5)
		check("  ต้นเลน (การรบ/แท่นอัญเชิญ) ยังเป็น X 140 เหมือนเดิม", Config.getLaneStartX(), 140)
		check("  แท่นอัญเชิญย้ายเข้าเลนที่ X 177 (5B-fix)", Config.getSummonPedestalCenter().X, 177)

		check("ตารางฝั่งมุมบอสครบ 9 ด่าน", #map.BossRoom.CornerSide, Config.Balance.Stage.COUNT)
		local alternates = true
		for stage = 2, Config.Balance.Stage.COUNT do
			if map.BossRoom.CornerSide[stage] == map.BossRoom.CornerSide[stage - 1] then
				alternates = false
			end
		end
		check("  สลับฟันปลาทุกด่าน", alternates, true)
		check("  ด่าน 1 = ขวา (+Z)", Config.getBossCornerSign(1), 1)
		check("  ด่าน 2 = ซ้าย (−Z)", Config.getBossCornerSign(2), -1)
		local boss = Config.getBossPosition()
		check("บอสด่าน 1 อยู่มุมขวา (Z > 0)", boss.Z > 0, true)
		check("  ลึกเข้าไปในห้อง (เลยกึ่งกลางห้องไปทาง +X)", boss.X > Config.getBossArenaCenter().X, true)
		local reach = math.max(cycle.PLAYER_ATTACK_RANGE, cycle.BOSS_ATTACK_RANGE)
		local laneInner = map.Lane.Width / 2 - map.Lane.WallThickness / 2
		check(
			"ทางวิ่งฝั่งซ้าย (นอกระยะตีบอส) กว้าง ≥ RunPathMinWidth",
			boss.Z - reach + laneInner >= arena.RunPathMinWidth,
			true
		)
		local eggsCorner = true
		for index = 1, cycle.EGGS_PER_NIGHT do
			local egg = Config.getBossCycleEggSpot(index)
			if egg.Z <= 0 or egg.X <= boss.X then
				eggsCorner = false
			end
		end
		check("ไข่ 6 ฟองอยู่หลังบอส มุมเดียวกัน", eggsCorner, true)
		local stage2Egg = Config.getBossEggSpot(2, 1)
		check("ห้องด่าน 2 (รอบหน้า): ไข่อยู่ฝั่งซ้าย", stage2Egg.Z < 0, true)

		-- ยามต้องจับตารางฝั่งที่ไม่สลับ
		local saved = map.BossRoom.CornerSide[2]
		map.BossRoom.CornerSide[2] = map.BossRoom.CornerSide[1]
		check("ตั้งด่าน 1 กับ 2 ฝั่งเดียวกัน → validate ไม่ผ่าน", pcall(Config.validate), false)
		map.BossRoom.CornerSide[2] = saved
		check("  คืนค่าแล้ว validate ผ่าน", pcall(Config.validate), true)
	end

	----------------------------------------------------------------------------
	print("── 5B-fix (ผลทดสอบ Studio รอบ 1): วาปเฉพาะคนในสนามรบ · ไม่บอกน้ำหนักไข่ก่อนเก็บ ──")
	----------------------------------------------------------------------------
	do
		local edge = Config.getSafeZoneEdgeX()
		check("ยืนในคอก → ไม่วาป", BossService.shouldGatherAtNight(pos(0, 85)), false)
		check("ยืนกลางลาน/หน้าป้อม → ไม่วาป", BossService.shouldGatherAtNight(Config.getBossGatherSpot(1)), false)
		check("ยืนร้านค้า → ไม่วาป", BossService.shouldGatherAtNight(Config.getShopCenter()), false)
		check("ยืนในเลน (สนามรบ) → วาป", BossService.shouldGatherAtNight(pos(200, 0)), true)
		check("ยืนที่แท่นอัญเชิญ (ในเลนแล้ว) → วาป", BossService.shouldGatherAtNight(Config.getSummonPedestalCenter()), true)
		check("ยืนห้องบอส → วาป", BossService.shouldGatherAtNight(Config.getBossPosition()), true)
		check("ยืนเลยกำแพงด่าน 2 (ด่านไกล) → วาป", BossService.shouldGatherAtNight(pos(600, 0)), true)
		check("ขอบพอดี (ช่องประตู) = สนามรบ → วาป", BossService.shouldGatherAtNight(pos(edge, 0)), true)

		local picked = Config.formatBossEventMessage("picked", 152300)
		check("ข้อความหยิบไข่ไม่บอกน้ำหนัก (ให้ลุ้น)", string.find(picked, "กก.", 1, true), nil)
		check("  ไม่มีตัวเลขน้ำหนักหลุดมา", string.find(picked, "152", 1, true), nil)
		check(
			"ข้อความเก็บเข้ากระเป๋ายังเฉลยน้ำหนัก",
			Config.formatBossEventMessage("delivered", 152300),
			"เก็บไข่บอสแล้ว (152,300 กก.)"
		)
	end
end
