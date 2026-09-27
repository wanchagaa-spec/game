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
		check(
			"กำแพงกั้นหนาไม่น้อยกว่าเกณฑ์ความเร็ว",
			Config.MapDimensions.BossArena.BarrierThickness >= Config.getMinWallThickness(),
			true
		)
		check("กำแพงกั้นอยู่หลังจุดเริ่มกำแพงข้างเลน", Config.getBossBarrierFrontX() >= Config.getLaneWallStartX(), true)
		check(
			"กำแพงกั้นอยู่ก่อนห้องบอส",
			Config.getBossBarrierX() < Config.getBossArenaCenter().X - Config.MapDimensions.BossRoom.Size.X / 2,
			true
		)
		check(
			"กำแพงกั้นกว้างพอดีผิวด้านในกำแพงข้างเลน (ไม่ยื่นเข้าเนื้อกำแพง)",
			Config.getBossBarrierSize().Z,
			Config.MapDimensions.Lane.Width - Config.MapDimensions.Lane.WallThickness
		)

		local minGap = math.huge
		local allInFront = true
		for i = 1, Config.World.MAX_PENS do
			local a = Config.getBossGatherSpot(i)
			if a.X >= Config.getBossBarrierFrontX() then
				allInFront = false
			end
			for j = i + 1, Config.World.MAX_PENS do
				local b = Config.getBossGatherSpot(j)
				minGap = math.min(minGap, math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2))
			end
		end
		check("จุดยืนหน้าป้อมครบทุกคนในเซิร์ฟ อยู่หน้ากำแพงกั้นทั้งหมด", allInFront, true)
		check("  ไม่มีสองจุดซ้อนกัน (ห่าง ≥ 4)", minGap >= 4, true)

		check("จุดไข่ 6 จุด (5B)", cycle.EGGS_PER_NIGHT, 6)
		local behind = true
		for i = 1, cycle.EGGS_PER_NIGHT do
			local egg = Config.getBossCycleEggSpot(i)
			if egg.X <= Config.getBossArenaCenter().X + Config.MapDimensions.BossArena.BossSize.X / 2 then
				behind = false
			end
		end
		check("  ทุกจุดอยู่หลังตัวบอส", behind, true)

		check("isInBossArena: กลางห้องบอส", Config.isInBossArena(Config.getBossArenaCenter()), true)
		check("isInBossArena: หน้าป้อม (ยังไม่ผ่านกำแพงกั้น)", Config.isInBossArena(Config.getBossGatherSpot(1)), false)
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
end
