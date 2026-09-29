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
	print("── 5A Config: 10 / 9 / 1 นาที · ห้อง 1 เข้าได้ทุกคน · จุดยืน/จุดไข่ครบ ──")
	----------------------------------------------------------------------------
	do
		check("กลางวัน 9 นาที", DAY, 540)
		check("กลางคืน 1 นาที", NIGHT, 60)
		check("รอบละ 10 นาที", Config.getBossCycleSeconds(), 600)
		-- 5B-2: ไม่มี "ลานบอสกลาง" แล้ว — ห้อง 1 คือห้องที่ไม่มีกำแพง (ทุกคนเดินถึง)
		check("ห้อง 1: ด่าน 1 ไม่มีกำแพง (ทุกคนเดินถึง)", Config.getWallX(1), nil)
		check("  ผู้เล่นใหม่ (wallProgress 1) มีสิทธิ์ห้อง 1", Config.canAccessBossRoom(1, 1), true)

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

		check("จุดไข่ 6 จุดต่อห้อง (5B)", cycle.EGGS_PER_NIGHT, 6)
		local boss = Config.getBossCornerCenter(1)
		local behind = true
		for i = 1, cycle.EGGS_PER_NIGHT do
			local egg = Config.getBossEggSpot(1, i)
			if egg.X <= boss.X + map.BossArena.BossSize.X / 2 then
				behind = false
			end
		end
		check("  ห้อง 1: ทุกจุดอยู่หลังตัวบอส", behind, true)

		check("getStageRoomAt: กลางห้องบอส 1", Config.getStageRoomAt(Config.getBossNestCenter(1)), 1)
		check("getStageRoomAt: ตัวบอสห้อง 1 (มุมห้อง)", Config.getStageRoomAt(boss), 1)
		check("getStageRoomAt: หน้าป้อม (ฝั่งลาน) = ไม่อยู่ห้องไหน", Config.getStageRoomAt(Config.getBossGatherSpot(1)), nil)
		check("getStageRoomAt: ลานคอก = ไม่อยู่ห้องไหน", Config.getStageRoomAt(pos(0, 0)), nil)

		check("ข้อความล็อกอัญเชิญ", Config.BOSS_LOCK_MESSAGE, "กำจัดบอสก่อนจึงจะอัญเชิญต่อได้")
		check("ข้อความบอสตาย (ไม่มีห้อง = ข้อความเดิม)", Config.formatBossEventMessage("killed"), "กำจัดบอสแล้ว!")
		check("ข้อความบอสตายห้อง 3", Config.formatBossEventMessage("killed", 3), "กำจัดบอสห้อง 3 แล้ว!")
		check(
			"ข้อความติดล็อก (ส่งเฉพาะคนที่ติด) มีข้อความล็อกอยู่ในนั้น",
			string.find(Config.formatBossEventMessage("locked", 2), Config.BOSS_LOCK_MESSAGE, 1, true) ~= nil,
			true
		)
		check(
			"  บอกห้องที่ทำให้ติดล็อก",
			string.find(Config.formatBossEventMessage("locked", 2), "บอสห้อง 2", 1, true) ~= nil,
			true
		)
		check("ข้อความชนิดแปลก = ว่าง", Config.formatBossEventMessage("???"), "")

		-- ก่อน BossService.start() (เช่นในเทสต์/harness) ต้องไม่มีใครถูกล็อก และล็อกไม่ได้
		check("ก่อน start: ไม่มีใครติดล็อก", BossService.isLocked(1), false)
		check("ก่อน start: ไม่มีบอสห้อง 1", BossService.isBossAlive(1), false)
		check("ก่อน start: ไม่มีบอสห้อง 9", BossService.isBossAlive(9), false)
		check("ก่อน start: ล็อกไม่ได้", BossService.lock(1, 2), false)
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

	-- 5B-2: HP บอสห้อง 1 (โมเดลสมดุล Config.getBossHp(1)) — เดิมใช้ BossCycle.BOSS_HP ที่ลบแล้ว
	local HP1 = Config.getBossHp(1)

	----------------------------------------------------------------------------
	print("── 5A วงจร: เซิร์ฟเปิด = ต้นกลางวัน ไม่มีบอส · เปลี่ยนตรงจังหวะ 9:00 / 1:00 ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(1000)
		check("เริ่มกลางวัน", s.phase, "day")
		check("  ไม่มีบอสจนคืนแรก (ห้อง 1)", s.rooms[1].bossAlive, false)
		check("  มีครบ 9 ห้อง", #s.rooms, Config.Balance.Stage.COUNT)
		check("  จบกลางวันที่ +540", s.phaseEndsAt, 1540)

		check("8:59.9 ยังกลางวัน (ไม่มีเหตุการณ์)", #BossService.step(s, 1539.9), 0)
		check("  phase ยังเป็น day", s.phase, "day")

		local events = BossService.step(s, 1540)
		check("9:00 พอดี → เข้ากลางคืน", events[1], "night")
		check("  phase = night", s.phase, "night")
		check("  บอสห้อง 1 เกิด", s.rooms[1].bossAlive, true)
		check("  HP เต็ม = Config.getBossHp(1)", s.rooms[1].bossHp, HP1)
		check("  คืนที่ 1", s.cycle, 1)
		check("  จบกลางคืนที่ +600", s.phaseEndsAt, 1600)

		check("0:59.9 ของคืน ยังกลางคืน", #BossService.step(s, 1599.9), 0)
		local dayEvents = BossService.step(s, 1600)
		check("1:00 พอดี → เข้ากลางวัน", dayEvents[1], "day")
		check("  phase = day", s.phase, "day")
		check("  กลางวันใหม่จบที่ +1140", s.phaseEndsAt, 2140)
		check("  บอสยังอยู่ (ตีได้ตลอดกลางวัน)", s.rooms[1].bossAlive, true)

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
		BossService.applyDamage(s, 1, 111, 30, 610)
		check("ตีไป 30 → HP เหลือ HP เต็ม − 30", s.rooms[1].bossHp, HP1 - 30)
		BossService.step(s, 1140) -- คืน 2 บอสยังไม่ตาย
		check("คืนถัดไปบอสยังไม่ตาย → HP เต็มอีกครั้ง", s.rooms[1].bossHp, HP1)
		check("  ยังมีชีวิต", s.rooms[1].bossAlive, true)
		check("  บันทึกผู้ทำดาเมจเริ่มใหม่ (บอสตัวใหม่)", s.rooms[1].damageBy[111], nil)

		BossService.step(s, 1200) -- เช้า
		local _, killed = BossService.applyDamage(s, 1, 222, 99999, 1300)
		check("ฆ่าได้", killed, true)
		check("  ตายแล้ว", s.rooms[1].bossAlive, false)
		check("  เวลาตายถูกบันทึก", s.rooms[1].bossDiedAt, 1300)
		check("  บันทึกผู้ทำดาเมจยังอยู่หลังตาย (อ่านตอนแบ่งเงิน)", s.rooms[1].damageBy[222], HP1)

		BossService.step(s, 1739) -- ยังกลางวันเดิม
		check("ตายแล้วไม่เกิดระหว่างวัน", s.rooms[1].bossAlive, false)
		BossService.step(s, 1740) -- คืน 3
		check("คืนถัดไปเกิดใหม่", s.rooms[1].bossAlive, true)
		check("  HP เต็ม", s.rooms[1].bossHp, HP1)
	end

	----------------------------------------------------------------------------
	print("── 5A ดาเมจ: กลางคืน/ไม่มีบอส ตีไม่เข้า · เกิน HP นับเท่าที่เข้าจริง · บันทึกรายคน ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		local dealt = BossService.applyDamage(s, 1, 1, 5, 10)
		check("กลางวันแรก ไม่มีบอส → ตีไม่เข้า", dealt, 0)
		BossService.step(s, 540)
		dealt = BossService.applyDamage(s, 1, 1, 5, 545)
		check("กลางคืน (บอสอยู่หลังกำแพงกั้น) → ตีไม่เข้า", dealt, 0)
		check("  HP ไม่ลด", s.rooms[1].bossHp, HP1)

		BossService.step(s, 600)
		BossService.applyDamage(s, 1, 1, 10, 601)
		BossService.applyDamage(s, 1, 2, 25, 602)
		BossService.applyDamage(s, 1, 1, 5, 603)
		check("บันทึก: คน 1 = 15", s.rooms[1].damageBy[1], 15)
		check("บันทึก: คน 2 = 25", s.rooms[1].damageBy[2], 25)
		local list = BossService.getContributors(s, 1)
		check("เรียงมาก → น้อย: อันดับ 1 = คน 2", list[1].userId, 2)
		check("  อันดับ 2 = คน 1", list[2].userId, 1)

		local last, killed = BossService.applyDamage(s, 1, 3, 99999, 604)
		check("ฟันสุดท้ายเกิน HP → นับเท่าที่เหลือจริง", last, HP1 - 40)
		check("  ฆ่าได้", killed, true)
		local total = 0
		for _, entry in BossService.getContributors(s, 1) do
			total += entry.damage
		end
		check("ผลรวมดาเมจที่บันทึก = HP เต็มพอดี", total, HP1)
		check("ตีศพต่อ → ไม่เข้า", (BossService.applyDamage(s, 1, 1, 10, 605)), 0)
		check("ห้องแปลก (0 / 10 / 1.5) → ไม่เข้า", (BossService.applyDamage(s, 0, 1, 10, 605)) + (BossService.applyDamage(s, 10, 1, 10, 605)) + (BossService.applyDamage(s, 1.5, 1, 10, 605)), 0)
	end

	----------------------------------------------------------------------------
	print("── 5A ตีด้วยอาวุธ: server ตรวจ กลางวัน · ห้อง · สิทธิ์ · บอสอยู่ · คูลดาวน์ · ระยะ · ดาเมจจาก weaponLevel ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		BossService.step(s, 540)
		check("กลางคืน → night", (BossService.tryAttack(s, 7, 541, 1, 5, 1, 1)), "night")
		BossService.step(s, 600)
		local result, dealt = BossService.tryAttack(s, 7, 601, 1, 5, 1, 1)
		check("ใกล้ + กลางวัน + ห้อง 1 → ok", result, "ok")
		check("  ดาเมจ = Config.getWeaponDamage(1)", dealt, Config.getWeaponDamage(1))
		check("ฟันถี่เกินคูลดาวน์ → cooldown", (BossService.tryAttack(s, 7, 601 + cycle.PLAYER_ATTACK_COOLDOWN / 2, 1, 5, 1, 1)), "cooldown")
		check("ครบคูลดาวน์ → ok", (BossService.tryAttack(s, 7, 601 + cycle.PLAYER_ATTACK_COOLDOWN, 1, 5, 1, 1)), "ok")
		check("คนอื่นไม่ติดคูลดาวน์ของเรา", (BossService.tryAttack(s, 8, 601.1, 1, 5, 1, 1)), "ok")
		check("ไกลเกินระยะ → range", (BossService.tryAttack(s, 9, 610, 1, cycle.PLAYER_ATTACK_RANGE + 1, 1, 1)), "range")
		check("ไม่อยู่ห้องบอสไหน (room = nil) → noroom", (BossService.tryAttack(s, 9, 611, nil, 0, 1, 9)), "noroom")
		-- บอสตัวใหม่ HP เต็ม (ตัวบนโดนไปแล้ว — ดาเมจจะถูกตัดที่ HP ที่เหลือ)
		local fresh = BossService.newState(0)
		BossService.step(fresh, 540)
		BossService.step(fresh, 600)
		local _, dealt2 = BossService.tryAttack(fresh, 10, 611, 2, 5, 2, 2)
		check("อาวุธขั้น 2 ที่ห้อง 2 → ดาเมจตามสูตรเดิม", dealt2, math.min(Config.getWeaponDamage(2), Config.getBossHp(2)))
		BossService.applyDamage(s, 1, 10, 99999, 612)
		check("บอสตายแล้ว → dead", (BossService.tryAttack(s, 11, 620, 1, 5, 1, 1)), "dead")
		check("ระยะแนวราบไม่นับแกน Y", BossService.horizontalDistance({ X = 0, Y = 100, Z = 0 }, { X = 3, Y = 0, Z = 4 }), 5)
	end

	----------------------------------------------------------------------------
	print("── 5C กระบอง: ดาเมจจาก weaponLevel ตามตาราง · ขั้น N ตีห้อง N คนเดียวตายภายในกลางวันจริง (จำลองทีละครั้ง) ──")
	----------------------------------------------------------------------------
	do
		local W = Config.Balance.Weapon
		for tier = 1, W.MAX_LEVEL do
			local s = BossService.newState(0)
			BossService.step(s, 540)
			BossService.step(s, 600)
			local room = Config.getClubTargetRoom(tier)
			local _, dealt = BossService.tryAttack(s, 77, 600, room, 5, tier, room)
			check(`ขั้น {tier} ที่ห้อง {room} → ดาเมจ {Config.getClubDamage(tier)} ตามตาราง`, dealt,
				math.min(Config.getClubDamage(tier), Config.getBossHp(room)))
		end
		-- ⚠️ กันปัญหาล็อกอัญเชิญ: ตีจริงทีละครั้งตามคูลดาวน์ จนบอสตาย · ต้องจบก่อนหมดกลางวัน ทุกห้อง
		for room = 1, Config.Balance.Stage.COUNT do
			local s = BossService.newState(0)
			BossService.step(s, 540)
			BossService.step(s, 600)
			local t0, now, killed, allOk = 600, 600, false, true
			while now < 600 + cycle.DAY_SECONDS and not killed do
				local result, _, k = BossService.tryAttack(s, 5, now, room, 5, room, room)
				killed = k
				now += cycle.PLAYER_ATTACK_COOLDOWN
				if result ~= "ok" then
					allOk = false
					break
				end
			end
			check(`ห้อง {room}: ทุกครั้งที่ครบคูลดาวน์ตีเข้า (ok)`, allOk, true)
			check(`ห้อง {room}: กระบองขั้น {room} คนเดียวตีตายก่อนหมดกลางวัน ({now - t0} วิ)`, killed, true)
		end
		local s = BossService.newState(0)
		BossService.step(s, 540)
		BossService.step(s, 600)
		local _, tooWeak = BossService.tryAttack(s, 6, 600, 9, 5, 99, 9)
		check("weaponLevel เซฟเกินเพดาน (99) → ดาเมจขั้น 10 (clamp)", tooWeak, Config.getClubDamage(10))
		local s2 = BossService.newState(0)
		BossService.step(s2, 540)
		BossService.step(s2, 600)
		local _, weird = BossService.tryAttack(s2, 6, 600, 1, 5, -3, 1)
		check("weaponLevel เซฟติดลบ → ดาเมจขั้น 1 (clamp) ไม่ crash", weird, Config.getClubDamage(1))
		check("damageLevel (ป้ายอัปดาเมจ) ไม่อยู่ในสูตรกระบองเลย — tryAttack ไม่รับค่านี้", Config.getClubDamage(5), Config.getWeaponDamage(5))
	end

	----------------------------------------------------------------------------
	print("── 5A ล็อกอัญเชิญ: เฉพาะตอนบอสห้องนั้นมีชีวิต · ไม่ปลดข้ามคืน · บอสห้องนั้นตาย = ปลด ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		check("ไม่มีบอส → ล็อกไม่ได้", BossService.lockUser(s, 5, 2), false)
		check("  ไม่ติดล็อก", BossService.isUserLocked(s, 5), false)
		BossService.step(s, 540)
		check("บอสห้อง 2 อยู่ → ล็อกได้", BossService.lockUser(s, 5, 2), true)
		BossService.lockUser(s, 6, 2)
		check("  คน 5 ติดล็อก", BossService.isUserLocked(s, 5), true)
		check("  ติดเพราะห้อง 2", BossService.getLockedRoom(s, 5), 2)
		check("  คนอื่นไม่ติดด้วย", BossService.isUserLocked(s, 7), false)
		BossService.step(s, 600)
		BossService.step(s, 1140) -- คืนถัดไป บอสยังไม่ตาย → ฟื้น HP เต็ม
		check("บอสไม่ตายข้ามคืน → ยังล็อกอยู่", BossService.isUserLocked(s, 5), true)
		BossService.step(s, 1200)
		BossService.applyDamage(s, 2, 99, 99999999, 1210)
		check("บอสห้อง 2 ตาย → คน 5 ปลดล็อก", BossService.isUserLocked(s, 5), false)
		check("  คน 6 ปลดล็อกพร้อมกัน", BossService.isUserLocked(s, 6), false)
		check("บอสห้อง 2 ตายแล้วพังกำแพง 2 → ไม่ล็อก", BossService.lockUser(s, 5, 2), false)
		BossService.step(s, 1740)
		check("คืนถัดไปบอสเกิดใหม่ → พังกำแพงอีกครั้งก็ล็อกได้อีก", BossService.lockUser(s, 5, 2), true)
		check("ห้องแปลก → ล็อกไม่ได้", BossService.lockUser(s, 8, 0), false)
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
		BossService.step(s, 540) -- บอสทุกห้องอยู่
		local data = aboutToClearStage2()
		local meta = CombatService.newMeta()
		local result = CombatService.tick(data, meta, 1)
		-- 5B-2: ดูบอสห้องของด่านที่เพิ่งพัง (ห้อง 2) — แบบเดียวกับ CombatService.start
		local cleared = result.clearedStage
		if cleared and CombatService.shouldBossLock(cleared, s.rooms[cleared].bossAlive) then
			BossService.lockUser(s, 42, cleared)
			CombatService.applyBossLock(data)
		end

		check("ด่าน 2 พังเหมือนไม่มีบอส", result.clearedStage, baseResult.clearedStage)
		check("  ไข่รางวัล 4A เท่าเดิม", result.bonusEggs, baseResult.bonusEggs)
		check("  แม่ตายเท่าเดิม", result.mothersLost, baseResult.mothersLost)
		check("  ธงรางวัลด่าน 2 ติด", data.stageClearBonusGranted[2], true)
		check("  wallProgress ขยับตามเดิม", data.wallProgress, base.wallProgress)
		check("  roster ถูกล้างตามเดิม", #data.battleRoster, 0)
		check("ติดล็อก", BossService.isUserLocked(s, 42), true)
		check("  ติดเพราะบอสห้อง 2 (ด่านที่เพิ่งพัง)", BossService.getLockedRoom(s, 42), 2)
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
	-- (5B-2: ทุกฟังก์ชันรับเลขห้อง · หยิบต้องกดค้างครบ — ตัวช่วย pick() จดจังหวะเริ่มกดให้ก่อน)
	--==========================================================================
	-- ตัวสุ่ม stub: lowRng = ได้ค่าต่ำสุดทุกครั้ง (tier 1 · 100 kg) · highRng = สูงสุด (tier 7 · 100M kg)
	local lowRng = { NextInteger = function(_self, lo, _hi) return lo end }
	local highRng = { NextInteger = function(_self, _lo, hi) return hi end }
	local arena = Config.MapDimensions.BossArena
	local pickupRange = arena.EggPickupRange
	local HOLD = cycle.EGG_PICKUP_HOLD_SECONDS
	local STAGES = Config.Balance.Stage.COUNT

	-- หยิบแบบผู้เล่นจริง: เริ่มกดค้าง (ยืนใกล้) แล้วค่อยขอหยิบเมื่อครบเวลา · wallProgress ไม่ใส่ = ผ่านครบ (มีสิทธิ์ทุกห้อง)
	local clock = 100000
	local function pick(s, userId, room, index, distance, wallProgress)
		distance = distance or 0
		clock += 10
		BossService.beginHold(s, userId, room, index, math.min(distance, pickupRange), clock)
		clock += HOLD
		return BossService.pickUpEgg(s, userId, room, index, distance, wallProgress or STAGES, clock)
	end

	-- บอสทุกห้องตายแล้ว (ต้นกลางวันแรก ฆ่าทิ้ง) พร้อมไข่ 6 ฟองต่อห้อง — ใช้ซ้ำหลายเทสต์
	local function killedState(rng)
		local s = BossService.newState(0, rng or lowRng)
		BossService.step(s, DAY) -- กลางคืนแรก: บอส + ไข่ 6 ฟองทุกห้อง
		BossService.step(s, DAY + NIGHT) -- เช้า
		for room = 1, STAGES do
			BossService.applyDamage(s, room, 900, s.rooms[room].bossHp, DAY + NIGHT + 1)
		end
		return s
	end

	----------------------------------------------------------------------------
	print("── 5B ไข่บอส: เกิด 6 ฟองพร้อมบอส · น้ำหนักสุ่มตอนเกิด · ชนิดไข่เดิม ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		check("เซิร์ฟเปิด (ยังไม่ถึงคืนแรก) = ยังไม่มีไข่", #s.rooms[1].eggs, 0)
		check("  หยิบตอนยังไม่มีไข่ → alive (ยังไม่มีบอสตาย = ไม่มีไข่ให้หยิบ) หรือ taken", (pick(s, 1, 1, 1)) ~= "ok", true)
		BossService.step(s, DAY)
		check("ต้นกลางคืน: ไข่ 6 ฟองเกิดพร้อมบอส (ห้อง 1)", #s.rooms[1].eggs, 6)
		local allResting, allTypeOk, allWeightOk = true, true, true
		for index, egg in s.rooms[1].eggs do
			if egg.status ~= "resting" or egg.index ~= index or egg.room ~= 1 or egg.carrier ~= nil then
				allResting = false
			end
			if egg.eggId ~= "egg_stage1" then
				allTypeOk = false
			end
			if egg.weight ~= 100 or egg.weight % 1 ~= 0 then
				allWeightOk = false
			end
		end
		check("  ทุกฟองวางอยู่ (resting) ไม่มีคนถือ", allResting, true)
		check("  ชนิดไข่ห้อง 1 = egg_stage1 (ไข่ด่าน 1 เดิม · ไม่ได้สร้างชนิดใหม่)", allTypeOk, true)
		check("  น้ำหนักสุ่มแล้วตั้งแต่บอสเกิด (ตัวสุ่มเดิม · จำนวนเต็ม)", allWeightOk, true)
		local fixed = s.rooms[1].eggs[1].weight
		BossService.step(s, DAY + NIGHT) -- เช้า — น้ำหนักต้องไม่ถูกสุ่มใหม่
		check("  เช้าแล้วน้ำหนักไม่เปลี่ยน (ไม่สุ่มใหม่)", s.rooms[1].eggs[1].weight, fixed)

		local heavy = BossService.newState(0, highRng)
		BossService.step(heavy, DAY)
		check("ตัวสุ่มสูงสุด → ไข่ tier 7 (100M kg) ตามตารางเดิม", heavy.rooms[1].eggs[1].weight, 100000000)
	end

	----------------------------------------------------------------------------
	print("── 5B หยิบไข่: ก่อนบอสตายไม่ได้ · ถือทีละฟอง · ไกลถูกปฏิเสธ · index แปลกทิ้ง ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		check("กลางคืน (บอสอยู่) หยิบไม่ได้ → alive", (pick(s, 1, 1, 1)), "alive")
		BossService.step(s, DAY + NIGHT)
		check("กลางวัน บอสยังอยู่ → alive", (pick(s, 1, 1, 1)), "alive")
		check("  ไข่ยังวางอยู่", s.rooms[1].eggs[1].status, "resting")
		BossService.applyDamage(s, 1, 900, s.rooms[1].bossHp, DAY + NIGHT + 1)
		check("บอสห้อง 1 ตายแล้ว → ไม่มีบอส", s.rooms[1].bossAlive, false)

		local result, egg = pick(s, 1, 1, 1)
		check("บอสตาย + ในห้อง + ใกล้ + กดค้างครบ → หยิบได้ (ไม่ต้องเคยตีบอส)", result, "ok")
		check("  ได้ไข่ห้อง 1 ฟองที่ 1", egg and (egg.room * 10 + egg.index), 11)
		check("  สถานะ carried · คนถือ = userId 1", s.rooms[1].eggs[1].status == "carried" and s.rooms[1].eggs[1].carrier == 1, true)
		check("  getCarriedEgg คืนฟองที่ถือ", BossService.getCarriedEgg(s, 1), s.rooms[1].eggs[1])

		check("ถืออยู่แล้วหยิบฟองที่ 2 → carrying (ถือได้ทีละฟอง)", (pick(s, 1, 1, 2)), "carrying")
		check("  ฟองที่ 2 ยังวางอยู่", s.rooms[1].eggs[2].status, "resting")
		check("คนอื่นหยิบฟองที่มีคนถือ → taken", (pick(s, 2, 1, 1)), "taken")

		check("ไกลกว่าระยะหยิบ → range", (pick(s, 2, 1, 2, pickupRange + 0.01)), "range")
		check("ไม่อยู่ห้องไหน (room = nil) แม้ใกล้ → range", (pick(s, 2, nil, 2)), "range")
		check("  ถูกปฏิเสธแล้วไข่ยังวางอยู่", s.rooms[1].eggs[2].status, "resting")
		check("ระยะพอดีขอบ → หยิบได้", (pick(s, 2, 1, 2, pickupRange)), "ok")

		for _, bad in { 0, 7, 1.5, -1, 0 / 0, "1", nil, true } do
			check(`index แปลก ({tostring(bad)}) → invalid`, (pick(s, 3, 1, bad)), "invalid")
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

		pick(s, 1, 1, 4)
		local carried = s.rooms[1].eggs[4]
		local inLane = pos(Config.getSafeZoneEdgeX() + 1, 0)
		check("ยังอยู่ในเลน (ไม่ถึงเซฟโซน) → outside", (BossService.tryDeliver(s, 1, inLane, grant)), "outside")
		check("  ยังไม่เรียกทางเพิ่มไข่", grantCalls, 0)

		local safe = pos(Config.getSafeZoneEdgeX() - 1, 0)
		local result, egg = BossService.tryDeliver(s, 1, safe, grant)
		check("เข้าเซฟโซน → delivered", result, "delivered")
		check("  ไข่เข้ากระเป๋า 1 ฟอง", #data.heldEggs.items, before + 1)
		local added = data.heldEggs.items[#data.heldEggs.items]
		check("  น้ำหนักเท่าที่สุ่มไว้ตอนบอสเกิด (ไม่สุ่มใหม่)", added.weight, carried.weight)
		check("  ชนิดไข่ตรง (ห้อง 1 = egg_stage1)", added.eggId, "egg_stage1")
		check("  คืนไข่ฟองที่ส่ง", egg, carried)
		check("  ไข่ฟองนั้นหมดไป (gone)", carried.status, "gone")
		check("  ไม่ได้ถืออะไรแล้ว", BossService.getCarriedEgg(s, 1), nil)
		check("เรียกซ้ำ (ยืนในเซฟโซนต่อ) → none", (BossService.tryDeliver(s, 1, safe, grant)), "none")
		check("  ได้ไข่ครั้งเดียวพอดี", #data.heldEggs.items, before + 1)
		check("  ทางเพิ่มไข่ถูกเรียกครั้งเดียว", grantCalls, 1)
		check("หยิบฟองที่เก็บไปแล้วซ้ำ → taken", (pick(s, 1, 1, 4)), "taken")

		-- กระเป๋าเต็ม → เข้ากระเป๋าไม่ได้ ยังถือค้าง (ไม่หาย ไม่งอก)
		pick(s, 1, 1, 5)
		local full = function()
			return false
		end
		check("กระเป๋าเต็ม → full", (BossService.tryDeliver(s, 1, safe, full)), "full")
		check("  ยังถือฟองเดิมอยู่", BossService.getCarriedEgg(s, 1), s.rooms[1].eggs[5])
		check("  สถานะยัง carried", s.rooms[1].eggs[5].status, "carried")
		check("มีที่ว่างแล้ว → delivered", (BossService.tryDeliver(s, 1, safe, grant)), "delivered")

		-- หยิบครบ 6 ฟองแล้วหยิบไม่ได้อีก
		for index = 1, cycle.EGGS_PER_NIGHT do
			if s.rooms[1].eggs[index].status == "resting" then
				pick(s, 1, 1, index)
				BossService.tryDeliver(s, 1, safe, grant)
			end
		end
		local anyLeft = false
		for index = 1, cycle.EGGS_PER_NIGHT do
			if (pick(s, 77, 1, index)) ~= "taken" then
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
		pick(s, 1, 1, 3)
		local dropped = BossService.dropCarriedEgg(s, 1)
		check("ออกเกมระหว่างถือ → ไข่กลับจุดเดิม (resting)", dropped and dropped.status, "resting")
		check("  ไม่มีคนถือ", s.rooms[1].eggs[3].carrier, nil)
		check("  คนอื่นหยิบใหม่ได้", (pick(s, 2, 1, 3)), "ok")
		check("ทิ้งตอนไม่ได้ถือ → nil (ไม่พัง)", BossService.dropCarriedEgg(s, 1), nil)

		-- คนที่ 2 ถือฟองที่ 3 ค้างไว้จนกลางคืน
		local oldEggs = s.rooms[1].eggs
		local data = PlayerData.createNew()
		local before = #data.heldEggs.items
		local events = BossService.step(s, DAY + NIGHT + DAY) -- คืนที่สอง
		check("ถึงกลางคืน", events[1], "night")
		check("  ไข่ชุดใหม่ 6 ฟอง (คนละชุด)", #s.rooms[1].eggs == 6 and s.rooms[1].eggs ~= oldEggs, true)
		local allFresh = true
		for _, egg in s.rooms[1].eggs do
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
		check("  คืนนี้บอสเกิดใหม่ → หยิบไม่ได้จนกว่าจะตาย", (pick(s, 2, 1, 1)), "alive")
	end

	----------------------------------------------------------------------------
	print("── 5B ประกาศไข่หนัก: เฉพาะไข่ที่หนักเกิน 100,000 kg (5B-2: รวมทุกห้องข้อความเดียว) ──")
	----------------------------------------------------------------------------
	do
		check("เกณฑ์ประกาศ = 100,000 kg (Config)", cycle.HEAVY_EGG_ALERT_KG, 100000)
		local s = BossService.newState(0, lowRng)
		check("ยังไม่มีไข่ → ไม่ประกาศ", #BossService.getHeavyEggAlerts(s), 0)
		BossService.step(s, DAY)
		check("ไข่ tier 1 ทั้งหมด → ไม่ประกาศ", #BossService.getHeavyEggAlerts(s), 0)
		s.rooms[1].eggs[3].weight = 100000
		check("หนัก 100,000 พอดี (ไม่เกิน) → ไม่ประกาศ", #BossService.getHeavyEggAlerts(s), 0)
		s.rooms[1].eggs[5].weight = 152300
		local one = BossService.getHeavyEggAlerts(s)
		check("มีฟองหนัก 152,300 ที่ห้อง 1 → 1 รายการ", #one == 1 and one[1].room == 1 and one[1].weight == 152300, true)
		s.rooms[1].eggs[1].weight = 999999
		check("  หลายฟองเกินในห้องเดียว → ประกาศฟองที่หนักสุดของห้อง", BossService.getHeavyEggAlerts(s)[1].weight, 999999)
		local heavy = BossService.newState(0, highRng)
		BossService.step(heavy, DAY)
		local all = BossService.getHeavyEggAlerts(heavy)
		check("ตัวสุ่มสูงสุด (tier 7) → ประกาศครบทุกห้อง", #all, STAGES)
		check("  ห้อง 1 = 100M", all[1].weight, 100000000)
	end

	----------------------------------------------------------------------------
	print("── 5B เงินบอส: แบ่งเท่ากัน (ปัดลง) เฉพาะคนที่ตีและยังอยู่ในห้อง · รวมไม่เกินก้อน ──")
	----------------------------------------------------------------------------
	do
		local total = Config.getBossKillReward(1)
		check("เงินก้อนบอสห้อง 1 (โมเดลสมดุล · ชั่วคราว) = 10,000", total, 10000)

		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		BossService.step(s, DAY + NIGHT)
		BossService.applyDamage(s, 1, 11, 20, DAY + NIGHT + 1)
		BossService.applyDamage(s, 1, 22, 20, DAY + NIGHT + 2)
		BossService.applyDamage(s, 1, 33, s.rooms[1].bossHp, DAY + NIGHT + 3) -- คนฆ่า
		check("บอสตายแล้ว", s.rooms[1].bossAlive, false)
		local present = { [11] = true, [22] = false, [33] = true, [44] = true }
		local share, recipients, planned = BossService.planReward(s, 1, function(userId)
			return present[userId] == true
		end)
		check("ก้อนเงินที่แบ่ง = เงินบอสห้อง 1", planned, total)
		check("ได้เฉพาะคนที่ตี + ยังอยู่ในห้อง (11, 33)", table.concat(recipients, ","), "11,33")
		check("  คนที่ตีแต่ออกนอกห้อง/หลุด (22) ไม่ได้", table.find(recipients, 22), nil)
		check("  คนที่อยู่ในห้องแต่ไม่ได้ตี (44) ไม่ได้", table.find(recipients, 44), nil)
		check("  แบ่งเท่ากัน ไม่ตามสัดส่วนดาเมจ", share, 5000)
		check("  รวมไม่เกินก้อน", share * #recipients <= total, true)

		present[22] = true
		local share3, three = BossService.planReward(s, 1, function(userId)
			return present[userId] == true
		end)
		check("3 คน → คนละ 3,333 (ปัดลง)", share3, 3333)
		check("  รวม 9,999 ไม่เกิน 10,000 (ไม่งอกเงินจากการปัด)", share3 * #three, 9999)
		local shareNone, nobody = BossService.planReward(s, 1, function()
			return false
		end)
		check("ไม่มีใครอยู่ในห้อง → ไม่มีใครได้ · 0", #nobody == 0 and shareNone == 0, true)
		check("splitReward(7, 3) = 2", BossService.splitReward(7, 3), 2)
		check("splitReward(x, 0) = 0", BossService.splitReward(total, 0), 0)

		s.rooms[1].damageBy[55] = 0.5
		local _, withTiny = BossService.planReward(s, 1, function()
			return true
		end)
		check("ดาเมจต่ำกว่า BOSS_REWARD_MIN_DAMAGE ไม่นับว่าร่วมตี", table.find(withTiny, 55), nil)
		check(
			"ข้อความรายคน (ไม่มีห้อง = ข้อความเดิม)",
			Config.formatBossEventMessage("reward", 3333, 3),
			"ได้ $3,333 จากบอส (แบ่ง 3 คน)"
		)
		check(
			"ข้อความรายคนบอกห้อง (5B-2)",
			Config.formatBossEventMessage("reward", 3333, 3, 4),
			"ได้ $3,333 จากบอสห้อง 4 (แบ่ง 3 คน)"
		)
		check("ข้อความเก็บไข่เริ่มด้วย \"เก็บไข่บอสแล้ว\"", string.sub(Config.formatBossEventMessage("delivered", 500), 1, #"เก็บไข่บอสแล้ว"), "เก็บไข่บอสแล้ว")
		check("หยิบไม่ได้ = toast สีเตือน", Config.isBossEventWarning("pickupRange"), true)
		check("  กดค้างไม่ครบ = สีเตือน", Config.isBossEventWarning("pickupHold"), true)
		check("  ไม่มีสิทธิ์ห้องนี้ = สีเตือน", Config.isBossEventWarning("pickupAccess"), true)
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
		check("  แท่นอัญเชิญอยู่ในห้องบอส 1", Config.getStageRoomAt(Config.getSummonPedestalCenter()), 1)
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

		check("ตารางฝั่งมุมบอสครบ 9 ด่าน", #map.BossRoom.CornerSide, STAGES)
		local alternates = true
		for stage = 2, STAGES do
			if map.BossRoom.CornerSide[stage] == map.BossRoom.CornerSide[stage - 1] then
				alternates = false
			end
		end
		check("  สลับฟันปลาทุกด่าน", alternates, true)
		check("  ด่าน 1 = ขวา (+Z)", Config.getBossCornerSign(1), 1)
		check("  ด่าน 2 = ซ้าย (−Z)", Config.getBossCornerSign(2), -1)
		local boss = Config.getBossCornerCenter(1)
		check("บอสด่าน 1 อยู่มุมขวา (Z > 0)", boss.Z > 0, true)
		check("  ลึกเข้าไปในห้อง (เลยกึ่งกลางห้องไปทาง +X)", boss.X > Config.getBossNestCenter(1).X, true)
		local reach = math.max(cycle.PLAYER_ATTACK_RANGE, Config.getBossSlamRadius()) -- 5D: วงฟาดที่วาด
		local laneInner = map.Lane.Width / 2 - map.Lane.WallThickness / 2
		check(
			"ทางวิ่งฝั่งซ้าย (นอกวงบอสฟาด) กว้าง ≥ RunPathMinWidth",
			boss.Z - reach + laneInner >= arena.RunPathMinWidth,
			true
		)
		local eggsCorner = true
		for index = 1, cycle.EGGS_PER_NIGHT do
			local egg = Config.getBossEggSpot(1, index)
			if egg.Z <= 0 or egg.X <= boss.X then
				eggsCorner = false
			end
		end
		check("ไข่ 6 ฟองอยู่หลังบอส มุมเดียวกัน", eggsCorner, true)
		local stage2Egg = Config.getBossEggSpot(2, 1)
		check("ห้องด่าน 2: ไข่อยู่ฝั่งซ้าย", stage2Egg.Z < 0, true)

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
		check("ยืนห้องบอส → วาป", BossService.shouldGatherAtNight(Config.getBossCornerCenter(1)), true)
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

	--==========================================================================
	-- Phase 5B-2 — บอสทุกห้อง (ผู้ใช้ยืนยัน · docs/boss-plan.md)
	--==========================================================================

	----------------------------------------------------------------------------
	print("── 5B-2 บอสทั้ง 9 ห้องเกิดพร้อมกันทุกคืน · ตัวที่ยังไม่ตายฟื้น HP เต็ม · ไข่ทุกห้องรีเซ็ต ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		local noneAlive = true
		for room = 1, STAGES do
			if s.rooms[room].bossAlive then
				noneAlive = false
			end
		end
		check("เซิร์ฟเปิด (กลางวันแรก) ไม่มีบอสห้องไหน", noneAlive, true)
		BossService.step(s, DAY) -- คืน 1
		local allAlive, allFull, allEggs = true, true, true
		for room = 1, STAGES do
			local r = s.rooms[room]
			if not r.bossAlive or r.bossSpawnedAt ~= DAY then
				allAlive = false
			end
			if r.bossHp ~= Config.getBossHp(room) or r.bossMaxHp ~= Config.getBossHp(room) then
				allFull = false
			end
			if #r.eggs ~= cycle.EGGS_PER_NIGHT then
				allEggs = false
			end
		end
		check("คืนแรก: บอสครบ 9 ห้อง เกิดพร้อมกันจังหวะเดียว", allAlive, true)
		check("  HP เต็มตาม Config.getBossHp(ห้อง) ทุกห้อง", allFull, true)
		check("  ไข่ 6 ฟองทุกห้อง", allEggs, true)

		-- กลางวัน: ฆ่าห้อง 3 · ตีห้อง 5 ไม่ตาย · ห้องอื่นไม่แตะ
		BossService.step(s, DAY + NIGHT)
		BossService.applyDamage(s, 3, 1, s.rooms[3].bossHp, DAY + NIGHT + 5)
		BossService.applyDamage(s, 5, 1, 1000, DAY + NIGHT + 6)
		pick(s, 1, 3, 2) -- ถือไข่ห้อง 3 ค้างไว้
		local oldRoom7Eggs = s.rooms[7].eggs
		BossService.step(s, DAY + NIGHT + DAY) -- คืน 2
		check("คืนถัดไป: ห้อง 3 (ตายไปแล้ว) เกิดใหม่", s.rooms[3].bossAlive, true)
		check("  ห้อง 5 (ไม่ตาย) ฟื้น HP เต็ม", s.rooms[5].bossHp, Config.getBossHp(5))
		check("  บันทึกดาเมจห้อง 5 เริ่มใหม่", s.rooms[5].damageBy[1], nil)
		check("  ไข่ห้อง 7 (ไม่มีใครแตะ) ก็รีเซ็ตเป็นชุดใหม่", s.rooms[7].eggs ~= oldRoom7Eggs and #s.rooms[7].eggs == 6, true)
		check("  ไข่ที่ถือจากห้อง 3 หายก่อนวาป", BossService.getCarriedEgg(s, 1), nil)
		check("  จดคนที่ไข่หาย", table.concat(s.lostCarriers, ","), "1")
	end

	----------------------------------------------------------------------------
	print("── 5B-2 สถานะแยกห้อง: HP · บันทึกดาเมจ · ตาย/เป็น · ไข่ ไม่ปนกัน ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		BossService.step(s, DAY + NIGHT)
		BossService.applyDamage(s, 2, 50, 300, DAY + NIGHT + 1)
		check("ตีห้อง 2 → HP ห้อง 2 ลด", s.rooms[2].bossHp, Config.getBossHp(2) - 300)
		check("  HP ห้อง 1 ไม่แตะ", s.rooms[1].bossHp, Config.getBossHp(1))
		check("  HP ห้อง 3 ไม่แตะ", s.rooms[3].bossHp, Config.getBossHp(3))
		check("  บันทึกดาเมจอยู่ห้อง 2 เท่านั้น", s.rooms[2].damageBy[50] == 300 and s.rooms[1].damageBy[50] == nil, true)
		local _, killed = BossService.applyDamage(s, 1, 51, s.rooms[1].bossHp, DAY + NIGHT + 2)
		check("ฆ่าห้อง 1", killed, true)
		check("  ห้อง 2 ยังมีชีวิต", s.rooms[2].bossAlive, true)
		check("  ไข่ห้อง 1 หยิบได้แล้ว", (pick(s, 60, 1, 1)), "ok")
		check("  ไข่ห้อง 2 ยังหยิบไม่ได้ (บอสห้อง 2 อยู่)", (pick(s, 61, 2, 1)), "alive")
		check("HP ต่อห้องไล่ ×10 ตามโมเดลสมดุล (ห้อง 1 = 100 · ห้อง 9 = 10,000,000,000)",
			Config.getBossHp(1) == 100 and Config.getBossHp(9) == 10000000000, true)
		check("เงินต่อห้องไล่ ×10 ตามโมเดลสมดุล (ห้อง 1 = 10,000 · ห้อง 9 = 1,000,000,000,000)",
			Config.getBossKillReward(1) == 10000 and Config.getBossKillReward(9) == 1000000000000, true)
		local _, _, room4Total = BossService.planReward(s, 4, function()
			return true
		end)
		check("ก้อนเงินที่แบ่งห้อง 4 = Config.getBossKillReward(4)", room4Total, Config.getBossKillReward(4))
		check("ห้องแปลก → ไม่มีเงิน ไม่มีใครได้", select(3, BossService.planReward(s, 12, function() return true end)), 0)
	end

	----------------------------------------------------------------------------
	print("── 5B-2 ไข่ห้อง N = ไข่ด่าน N (egg_stageN · ตารางคลาสรายด่านเดิม) ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		local allMatch = true
		for room = 1, STAGES do
			for _, egg in s.rooms[room].eggs do
				if egg.eggId ~= `egg_stage{room}` or egg.eggId ~= Config.getBossEggId(room) or egg.room ~= room then
					allMatch = false
				end
			end
		end
		check("ทุกห้อง: ไข่ทุกฟอง = Config.getBossEggId(ห้อง) = egg_stageN", allMatch, true)
		check("  ไข่ห้อง 9 เป็นไข่จากบอสที่เปิดใช้ ผูกด่าน 9", Config.getEgg("egg_stage9").source == "boss"
			and Config.getEgg("egg_stage9").enabled and Config.getEgg("egg_stage9").stage == 9, true)
		-- ส่งเข้ากระเป๋าด้วยชนิดของห้องนั้น
		local k = killedState()
		local data = PlayerData.createNew()
		pick(k, 1, 7, 1)
		BossService.tryDeliver(k, 1, pos(0, 0), function(eggId, weight)
			return PlayerData.addHeldEgg(data.heldEggs, eggId, weight) ~= nil
		end)
		check("ถือไข่ห้อง 7 กลับเซฟโซน → เข้ากระเป๋าเป็น egg_stage7", data.heldEggs.items[#data.heldEggs.items].eggId, "egg_stage7")
	end

	----------------------------------------------------------------------------
	print("── 5B-2 ตำแหน่งทุกห้องผ่าน validate(): บอส · ไข่ · ทางวิ่ง อยู่ในห้องของตัวเอง ──")
	----------------------------------------------------------------------------
	do
		check("validate() ผ่าน (ตรวจครบ 9 ห้อง)", pcall(Config.validate), true)
		local reach = math.max(cycle.PLAYER_ATTACK_RANGE, Config.getBossSlamRadius()) -- 5D: วงฟาดที่วาด
		local laneInner = Config.MapDimensions.Lane.Width / 2 - Config.MapDimensions.Lane.WallThickness / 2
		local bossOk, eggOk, runOk, sideOk = true, true, true, true
		for room = 1, STAGES do
			local boss = Config.getBossCornerCenter(room)
			if Config.getStageRoomAt(boss) ~= room then
				bossOk = false
			end
			if Config.getBossCornerSign(room) * boss.Z <= 0 then
				sideOk = false
			end
			if Config.getBossCornerSign(room) * boss.Z - reach + laneInner < arena.RunPathMinWidth then
				runOk = false
			end
			for index = 1, cycle.EGGS_PER_NIGHT do
				if Config.getStageRoomAt(Config.getBossEggSpot(room, index)) ~= room then
					eggOk = false
				end
			end
		end
		check("  บอสทุกห้องอยู่ในห้องของตัวเอง (ที่ server ใช้ตัดสิน)", bossOk, true)
		check("  ไข่ทุกฟองอยู่ในห้องของตัวเอง", eggOk, true)
		check("  บอสอยู่ฝั่งมุมตามตาราง", sideOk, true)
		check("  ทางวิ่งนอกวงบอสฟาดกว้างพอทุกห้อง (5D)", runOk, true)
		local minX9, maxX9 = Config.getStageRoomRangeX(9)
		check("ห้อง 9 = หลังกำแพง 9 ถึงปลายเลน", minX9 == Config.getWallX(9) + Config.MapDimensions.StageWall.Thickness / 2
			and maxX9 == Config.getLaneEndX(), true)
		check("  ไข่ท้ายสุดห้อง 9 ยังไม่ถึงปลายเลน", Config.getBossEggSpot(9, 6).X < Config.getLaneEndX(), true)

		-- ยาม: ย้ายบอสลึกจนระยะตีลากถึงกำแพงท้ายห้อง → ไม่ผ่าน
		local savedX = arena.BossCornerX
		arena.BossCornerX = 60
		check("ย้ายบอสลึกจนชนท้ายห้อง → validate ไม่ผ่าน", pcall(Config.validate), false)
		arena.BossCornerX = savedX
		check("  คืนค่าแล้ว validate ผ่าน", pcall(Config.validate), true)
		-- ยาม: ค่าห้องเดียวที่ลบแล้วห้ามเติมกลับ
		cycle.KILL_REWARD = 10000 -- legacy-boss: ok (เทสต์ยาม)
		check("เติม BossCycle.KILL_REWARD กลับ → validate ไม่ผ่าน", pcall(Config.validate), false)
		cycle.KILL_REWARD = nil -- legacy-boss: ok
		check("  ลบออกแล้ว validate ผ่าน", pcall(Config.validate), true)
	end

	----------------------------------------------------------------------------
	print("── 5B-2 สิทธิ์: ยังไม่พังกำแพง N ตี/หยิบห้อง N ไม่ได้ แม้ปลอมตำแหน่ง ──")
	----------------------------------------------------------------------------
	do
		check("canAccessBossRoom: ผู้เล่นใหม่ (1) → ห้อง 1 ได้", Config.canAccessBossRoom(1, 1), true)
		check("  ผู้เล่นใหม่ → ห้อง 2 ไม่ได้", Config.canAccessBossRoom(1, 2), false)
		check("  พังกำแพง 4 แล้ว (wallProgress 4) → ห้อง 4 ได้", Config.canAccessBossRoom(4, 4), true)
		check("  wallProgress 4 → ห้อง 5 ไม่ได้", Config.canAccessBossRoom(4, 5), false)
		check("  ไม่มีข้อมูล (nil) → ห้อง 1 ได้ · ห้อง 2 ไม่ได้", Config.canAccessBossRoom(nil, 1) and not Config.canAccessBossRoom(nil, 2), true)
		check("  ห้องแปลก → ไม่ได้", Config.canAccessBossRoom(9, 10) or Config.canAccessBossRoom(9, 0) or Config.canAccessBossRoom(9, 2.5), false)

		-- ตำแหน่งปลอม: server "เห็น" ว่ายืนข้างบอสห้อง 5 (room = 5 · ระยะ 0) แต่ความคืบหน้าแค่ด่าน 4
		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		BossService.step(s, DAY + NIGHT)
		local now = DAY + NIGHT + 10
		check("ตีบอสห้อง 5 ด้วย wallProgress 4 (ปลอมตำแหน่ง) → noaccess", (BossService.tryAttack(s, 70, now, 5, 0, 9, 4)), "noaccess")
		check("  HP ห้อง 5 ไม่ลด", s.rooms[5].bossHp, Config.getBossHp(5))
		check("  ไม่ถูกบันทึกเป็นผู้ทำดาเมจ (ไม่ได้ส่วนแบ่ง)", s.rooms[5].damageBy[70], nil)
		check("  ไม่ติดคูลดาวน์ (ไม่นับว่าตี)", s.lastAttackAt[70], nil)
		BossService.applyDamage(s, 5, 71, s.rooms[5].bossHp, now + 1) -- คนที่มีสิทธิ์ฆ่าห้อง 5
		check("หยิบไข่ห้อง 5 ด้วย wallProgress 4 (ปลอมตำแหน่ง + กดค้างครบ) → access", (pick(s, 70, 5, 1, 0, 4)), "access")
		check("  ไข่ยังวางอยู่", s.rooms[5].eggs[1].status, "resting")
		check("ผู้เล่นใหม่ (wallProgress 1) ปลอมตำแหน่งไปห้อง 2 → ตีไม่ได้", (BossService.tryAttack(s, 72, now, 2, 0, 1, 1)), "noaccess")
		check("  wallProgress 5 (พังกำแพง 5 แล้ว) หยิบไข่ห้อง 5 ได้", (pick(s, 73, 5, 1, 0, 5)), "ok")
	end

	----------------------------------------------------------------------------
	print("── 5B-2 คนที่ไปไกลกว่า ตี/หยิบห้องก่อนหน้าได้ ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		BossService.step(s, DAY + NIGHT)
		local now = DAY + NIGHT + 10
		check("wallProgress 7 ตีบอสห้อง 1 → ok", (BossService.tryAttack(s, 80, now, 1, 0, 1, 7)), "ok")
		check("wallProgress 7 ตีบอสห้อง 3 → ok", (BossService.tryAttack(s, 81, now, 3, 0, 1, 7)), "ok")
		check("wallProgress 7 ตีบอสห้อง 7 → ok", (BossService.tryAttack(s, 82, now, 7, 0, 1, 7)), "ok")
		BossService.applyDamage(s, 3, 81, s.rooms[3].bossHp, now + 1)
		check("wallProgress 9 หยิบไข่ห้อง 3 → ok", (pick(s, 83, 3, 2, 0, 9)), "ok")
		check("  ไข่ที่ได้เป็นของห้อง 3 (egg_stage3)", BossService.getCarriedEgg(s, 83).eggId, "egg_stage3")
	end

	----------------------------------------------------------------------------
	print("── 5B-2 ล็อกอัญเชิญผูกกับบอสห้อง N เท่านั้น ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		BossService.step(s, DAY + NIGHT)
		local now = DAY + NIGHT + 10
		BossService.lockUser(s, 90, 2) -- พังกำแพง 2 ขณะบอสห้อง 2 อยู่
		BossService.lockUser(s, 91, 4) -- พังกำแพง 4 ขณะบอสห้อง 4 อยู่
		check("คน 90 ติดเพราะห้อง 2", BossService.getLockedRoom(s, 90), 2)
		BossService.applyDamage(s, 3, 1, s.rooms[3].bossHp, now)
		check("ฆ่าบอสห้อง 3 (ห้องอื่น) → คน 90 ยังติดล็อก", BossService.isUserLocked(s, 90), true)
		BossService.applyDamage(s, 1, 1, s.rooms[1].bossHp, now + 1)
		check("ฆ่าบอสห้อง 1 → คน 90 ยังติดล็อก", BossService.isUserLocked(s, 90), true)
		BossService.applyDamage(s, 2, 1, s.rooms[2].bossHp, now + 2)
		check("ฆ่าบอสห้อง 2 → คน 90 ปลดล็อก", BossService.isUserLocked(s, 90), false)
		check("  คน 91 (ห้อง 4) ยังติดล็อก", BossService.isUserLocked(s, 91), true)
		check("พังกำแพง 3 ตอนบอสห้อง 3 ตายแล้ว → ไม่ล็อก (แม้ห้องอื่นยังมีบอส)", BossService.lockUser(s, 92, 3), false)
		check("CombatService.shouldBossLock ดูบอสห้องของด่านที่พัง: ห้อง 3 ตาย → ไม่ล็อก",
			CombatService.shouldBossLock(3, s.rooms[3].bossAlive), false)
		check("  ห้อง 5 ยังอยู่ → ล็อก", CombatService.shouldBossLock(5, s.rooms[5].bossAlive), true)
	end

	----------------------------------------------------------------------------
	print("── 5B-2 กดค้าง: server จับเวลาเอง · ยิงหยิบตรง ๆ โดยไม่กดค้างครบ = ปฏิเสธ ──")
	----------------------------------------------------------------------------
	do
		local s = killedState()
		local need = BossService.getRequiredHoldSeconds()
		check("เวลาขั้นต่ำ = 3 วิ − tolerance", need, HOLD - cycle.EGG_PICKUP_HOLD_TOLERANCE)
		check("  tolerance น้อยกว่าครึ่งเวลากดค้าง", cycle.EGG_PICKUP_HOLD_TOLERANCE < HOLD / 2, true)
		local t0 = 5000
		check("ยิงหยิบตรง ๆ ไม่เคยเริ่มกด → hold", (BossService.pickUpEgg(s, 1, 1, 1, 0, 9, t0)), "hold")
		check("  ไข่ยังวางอยู่", s.rooms[1].eggs[1].status, "resting")

		BossService.beginHold(s, 1, 1, 1, 0, t0)
		check("เริ่มกดแล้วยิงหยิบทันที → hold", (BossService.pickUpEgg(s, 1, 1, 1, 0, 9, t0 + 0.1)), "hold")
		check("  กดได้ 2 วิ → hold", (BossService.pickUpEgg(s, 1, 1, 1, 0, 9, t0 + 2)), "hold")

		BossService.beginHold(s, 2, 1, 2, 0, t0)
		BossService.endHold(s, 2, t0 + 1) -- ปล่อยก่อนครบ
		check("ปล่อยก่อนครบแล้วรอให้ครบเวลาค่อยยิงหยิบ → hold", (BossService.pickUpEgg(s, 2, 1, 2, 0, 9, t0 + 5)), "hold")

		BossService.beginHold(s, 3, 1, 3, 0, t0)
		check("กดค้างฟอง 3 แต่ขอหยิบฟอง 4 → hold (ต้องฟองเดียวกัน)", (BossService.pickUpEgg(s, 3, 1, 4, 0, 9, t0 + HOLD)), "hold")
		check("กดค้างครบที่ฟองเดียวกัน → ok", (BossService.pickUpEgg(s, 3, 1, 3, 0, 9, t0 + HOLD)), "ok")

		BossService.beginHold(s, 4, 1, 5, 0, t0)
		BossService.endHold(s, 4, t0 + HOLD) -- ปล่อยตอนครบแล้ว (ลำดับ event ฝั่ง client ไม่แน่นอน)
		check("ปล่อยตอนครบแล้วค่อยยิงหยิบ → ok (ไม่ถูกปฏิเสธเพราะลำดับ event)", (BossService.pickUpEgg(s, 4, 1, 5, 0, 9, t0 + HOLD + 0.05)), "ok")
		check("  ใช้จังหวะกดค้างไปแล้ว (หยิบฟองถัดไปต้องกดใหม่)", s.holds[4], nil)

		BossService.beginHold(s, 5, 1, 6, 0, t0)
		check("  jitter: สั้นกว่า 3 วิ 0.25 วิ (ไม่เกิน tolerance) → ok", (BossService.pickUpEgg(s, 5, 1, 6, 0, 9, t0 + HOLD - 0.25)), "ok")

		local fresh = killedState()
		check("เริ่มกดจากไกลเกินระยะหยิบ → ไม่จด", BossService.beginHold(fresh, 6, 1, 1, pickupRange + 5, t0), false)
		check("  แล้วเดินเข้ามายิงหยิบ → hold", (BossService.pickUpEgg(fresh, 6, 1, 1, 0, 9, t0 + HOLD)), "hold")
		check("เริ่มกดห้อง 2 แล้วขอหยิบฟองเดียวกันที่ห้อง 1 → hold", BossService.beginHold(fresh, 7, 2, 1, 0, t0)
			and (BossService.pickUpEgg(fresh, 7, 1, 1, 0, 9, t0 + HOLD)) == "hold", true)
		check("ค่าแปลกตอนเริ่มกด (index 0 / ห้อง 10) → ไม่จด", BossService.beginHold(fresh, 8, 1, 0, 0, t0)
			or BossService.beginHold(fresh, 8, 10, 1, 0, t0), false)
		BossService.beginHold(fresh, 9, 1, 2, 0, t0)
		BossService.step(fresh, DAY + NIGHT + DAY) -- ข้ามไปคืนถัดไป → จังหวะกดค้างเก่าหาย
		check("กลางคืนล้างจังหวะกดค้างที่ค้างอยู่", fresh.holds[9], nil)
		check("ข้อความกดค้างไม่ครบ", Config.formatBossEventMessage("pickupHold"), `ต้องกด E ค้างให้ครบ {HOLD} วินาที`)
	end

	----------------------------------------------------------------------------
	print("── 5B-2 ประกาศไข่หนัก: ข้อความเดียวรวมทุกห้อง · ไม่มีห้องไหนเกิน = ไม่ประกาศ ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0, lowRng)
		BossService.step(s, DAY)
		check("ไม่มีห้องไหนเกิน → รายการว่าง (ไม่ประกาศ)", #BossService.getHeavyEggAlerts(s), 0)
		check("  ข้อความของรายการว่าง = ว่าง (client ไม่โชว์)", Config.formatBossEventMessage("heavy", {}), "")
		s.rooms[9].eggs[4].weight = 410000
		s.rooms[7].eggs[2].weight = 152300
		s.rooms[7].eggs[6].weight = 120000 -- ห้องเดียวกันหลายฟอง → เอาฟองหนักสุด
		local alerts = BossService.getHeavyEggAlerts(s)
		check("2 ห้องเกิน → 2 รายการ เรียงตามห้อง", #alerts == 2 and alerts[1].room == 7 and alerts[2].room == 9, true)
		check("  ห้อง 7 = ฟองหนักสุดของห้อง", alerts[1].weight, 152300)
		check(
			"ข้อความเดียวรวมทุกห้อง",
			Config.formatBossEventMessage("heavy", alerts),
			"🥚 คืนนี้: ห้อง 7 ไข่ 152,300 กก. · ห้อง 9 ไข่ 410,000 กก."
		)
		check("  ข้อมูลเพี้ยน (ไม่ใช่รายการ) → ว่าง", Config.formatBossEventMessage("heavy", 152300), "")
	end

	----------------------------------------------------------------------------
	print("── 5B-2 โอกาสไข่หนักเกิน 100,000 kg จากตัวสุ่มจริง (ใช้รายงาน · ไม่ใช่เกณฑ์เกม) ──")
	----------------------------------------------------------------------------
	do
		-- ตัวสุ่มจริงของเกม (Config.rollMotherWeightForEgg) · ตารางน้ำหนักเดียวทุกด่าน → ทุกห้องต้องได้ใกล้เคียงกัน
		math.randomseed(20260928)
		local rng = { NextInteger = function(_self, lo, hi) return math.random(lo, hi) end }
		local rolls = 200000
		local pooledHeavy, pooledTotal = 0, 0
		local maxRate = 0
		for room = 1, STAGES do
			local heavyCount = 0
			for _ = 1, rolls / STAGES do
				if Config.rollMotherWeightForEgg(Config.getBossEggId(room), rng) > cycle.HEAVY_EGG_ALERT_KG then
					heavyCount += 1
				end
			end
			pooledHeavy += heavyCount
			pooledTotal += math.floor(rolls / STAGES)
			maxRate = math.max(maxRate, heavyCount / math.floor(rolls / STAGES))
		end
		local rate = pooledHeavy / pooledTotal
		-- ทฤษฎี: tier 4 (0.09% · เกือบทุกค่า > 100,000) + tier 5–7 (0.01%) ≈ 0.1% ต่อฟอง
		print(`  ต่อฟอง ≈ {string.format("%.4f", rate * 100)}% (ทฤษฎี 0.1000%) · สุ่ม {pooledTotal} ครั้ง`)
		check("ต่อฟอง ≈ 0.1% (ช่วงยอมรับ 0.05–0.2%)", rate > 0.0005 and rate < 0.002, true)
		check("  ห้องไหนก็ไม่เกิน 0.3% (ตารางน้ำหนักเดียวกันทุกด่าน)", maxRate < 0.003, true)
	end

	----------------------------------------------------------------------------
	print("── 5D บอสฟาด: ค่าที่ตั้ง (วงวาด 18 · วงตัดสิน 16 · ง้าง 1 วิ · พัก 4 วิ · เลือด 100 · ครั้งละ 20) ──")
	----------------------------------------------------------------------------
	local function dayWithBosses()
		local s = BossService.newState(0)
		BossService.step(s, DAY)
		BossService.step(s, DAY + NIGHT)
		return s, DAY + NIGHT
	end
	do
		check("บอสฟาดเปิดใน Config", cycle.BOSS_ATTACK_ENABLED, true)
		check("  state เริ่มตามค่าใน Config", BossService.newState(0).attackEnabled, true)
		check("วงที่วาด = ระยะตีกระบอง 14 + 4 = 18", Config.getBossSlamRadius(), 18)
		check("วงที่ตัดสิน = 18 − 2 = 16 (เล็กกว่าวงที่วาด)", Config.getBossSlamHitRadius(), 16)
		check("  ยืนตีที่ระยะสุด (14) ยังอยู่ในวงตัดสิน → ต้องถอย", cycle.PLAYER_ATTACK_RANGE < Config.getBossSlamHitRadius(), true)
		check("ง้าง 1 วิ · พัก 4 วิ · รอบละ 5 วิ", cycle.BOSS_SLAM_WINDUP_SECONDS == 1 and cycle.BOSS_SLAM_REST_SECONDS == 4
			and Config.getBossSlamPeriodSeconds() == 5, true)
		check("เลือดเต็ม 100", cycle.PLAYER_MAX_HEALTH, 100)
		check("ดาเมจต่อครั้ง = 100 ÷ 5 = 20", Config.getBossSlamDamage(), 20)
		-- แก้ 5D (ผู้ใช้สั่ง): เริ่มฟื้น 10 วิหลังโดนครั้งล่าสุด (เดิม 5 = เท่ารอบฟาดพอดี) · ฟื้นทีละนิดเต็มหลอดใน 5 วิ (20/วิ)
		check("เริ่มฟื้นเลือด 10 วิหลังโดนครั้งล่าสุด · เต็มหลอด 5 วิ · เกิดใหม่ 5 วิ", cycle.PLAYER_REGEN_DELAY_SECONDS == 10
			and cycle.PLAYER_REGEN_FILL_SECONDS == 5 and cycle.PLAYER_RESPAWN_SECONDS == 5, true)
		check("  ฟื้น 20 ต่อวินาที (100 ÷ 5)", Config.getPlayerRegenPerSecond(), 20)
		check("  เวลาเริ่มฟื้นมากกว่ารอบฟาด (5 วิ) อย่างน้อย 1 รอบ", cycle.PLAYER_REGEN_DELAY_SECONDS - Config.getBossSlamPeriodSeconds()
			>= Config.getBossSlamPeriodSeconds(), true)
		local savedDelay = cycle.PLAYER_REGEN_DELAY_SECONDS
		cycle.PLAYER_REGEN_DELAY_SECONDS = 5 -- ค่าเดิม = เท่ารอบฟาดพอดี
		check("  เวลาเริ่มฟื้น 5 (= รอบฟาด) → validate ไม่ผ่าน", pcall(Config.validate), false)
		cycle.PLAYER_REGEN_DELAY_SECONDS = 9.9
		check("  9.9 (มากกว่ารอบฟาดไม่ถึง 1 รอบ) → validate ไม่ผ่าน", pcall(Config.validate), false)
		cycle.PLAYER_REGEN_DELAY_SECONDS = savedDelay
		local savedFill = cycle.PLAYER_REGEN_FILL_SECONDS
		cycle.PLAYER_REGEN_FILL_SECONDS = 0
		check("  เต็มหลอด 0 วิ (= เต็มทันที) → validate ไม่ผ่าน", pcall(Config.validate), false)
		cycle.PLAYER_REGEN_FILL_SECONDS = savedFill
		check("ค่าบอสตีกลับเดิม (DAMAGE/INTERVAL/RANGE) ลบแล้ว", cycle.BOSS_ATTACK_DAMAGE == nil and cycle.BOSS_ATTACK_INTERVAL == nil
			and cycle.BOSS_ATTACK_RANGE == nil, true)
		cycle.BOSS_ATTACK_RANGE = 14
		check("  เติม BOSS_ATTACK_RANGE กลับ → validate ไม่ผ่าน", pcall(Config.validate), false)
		cycle.BOSS_ATTACK_RANGE = nil
		local savedMargin = cycle.BOSS_SLAM_HIT_MARGIN
		cycle.BOSS_SLAM_HIT_MARGIN = 5 -- วงตัดสิน 13 < ระยะตี 14 = มีจุดยืนตีฟรี
		check("  วงตัดสินเล็กกว่าระยะตีกระบอง → validate ไม่ผ่าน", pcall(Config.validate), false)
		cycle.BOSS_SLAM_HIT_MARGIN = savedMargin
		local savedHits = cycle.BOSS_HITS_TO_KILL_PLAYER
		cycle.BOSS_HITS_TO_KILL_PLAYER = 3 -- 100 ÷ 3 ไม่ลงตัว
		check("  เลือดหารจำนวนครั้งไม่ลงตัว → validate ไม่ผ่าน", pcall(Config.validate), false)
		cycle.BOSS_HITS_TO_KILL_PLAYER = savedHits
		check("  คืนค่าแล้ว validate ผ่าน", pcall(Config.validate), true)
	end

	----------------------------------------------------------------------------
	print("── 5D บอสฟาด: ไม่มีใครในวง = ไม่ฟาด · มีคนในวง = ง้าง 1 วิแล้วฟาด · นอกวงตัดสินไม่โดน ──")
	----------------------------------------------------------------------------
	do
		local s, t0 = dayWithBosses()
		local boss1 = Config.getBossCornerCenter(1)
		local far = { [1] = pos(boss1.X - 40, boss1.Z) }
		check("ไม่มีใครในวง → ไม่มีเหตุการณ์", #BossService.stepSlams(s, t0, far), 0)
		check("  ผ่านไป 30 วิก็ยังไม่ฟาด", #BossService.stepSlams(s, t0 + 30, far), 0)
		check("  ห้อง 1 ยัง idle", s.rooms[1].slamPhase, "idle")

		-- คนที่ 1 ยืนตี (ระยะ 10) · คนที่ 2 อยู่ระหว่างวงตัดสินกับวงที่วาด (17) · คนที่ 3 นอกวง (19)
		local positions = {
			[1] = pos(boss1.X - 10, boss1.Z),
			[2] = pos(boss1.X - 17, boss1.Z),
			[3] = pos(boss1.X - 19, boss1.Z),
		}
		local ev = BossService.stepSlams(s, t0 + 31, positions)
		check("มีคนเข้าวง → ง้าง (วงแดงขึ้น)", #ev == 1 and ev[1].kind == "windup" and ev[1].room == 1, true)
		check("  ฟาดลงหลังง้าง 1 วิ", ev[1].at, t0 + 32)
		check("  ระหว่างง้างยังไม่ฟาด", #BossService.stepSlams(s, t0 + 31.9, positions), 0)
		ev = BossService.stepSlams(s, t0 + 32, positions)
		check("ครบ 1 วิ → ฟาด", #ev == 1 and ev[1].kind == "slam", true)
		check("  โดนเฉพาะคนในวงตัดสิน (คนที่ 1)", #ev[1].targets == 1 and ev[1].targets[1] == 1, true)
		check("  คนที่ยืน 17 (ในวงที่วาด นอกวงตัดสิน) ไม่โดน — เผื่อเน็ตหน่วย", table.find(ev[1].targets, 2), nil)
		check("  คนนอกวง (19) ไม่โดน", table.find(ev[1].targets, 3), nil)
		check("  ฟาดแล้วพัก", s.rooms[1].slamPhase, "rest")
		check("ระหว่างพัก 4 วิไม่ง้างใหม่", #BossService.stepSlams(s, t0 + 35.9, positions), 0)
		ev = BossService.stepSlams(s, t0 + 36, positions)
		check("พักครบแล้วยังมีคนในวง → ง้างใหม่ทันที (รอบละ 5 วิ)", #ev == 1 and ev[1].kind == "windup" and ev[1].at == t0 + 37, true)

		-- หลบทัน: เห็นวงแล้ววิ่งออกพ้นวงตัดสินก่อนฟาด = รอด
		local escaped = { [1] = pos(boss1.X - 16.5, boss1.Z) }
		ev = BossService.stepSlams(s, t0 + 37, escaped)
		check("วิ่งออกพ้นวงตัดสินทันก่อนฟาด → ฟาดลงแต่ไม่โดนใคร", #ev == 1 and ev[1].kind == "slam" and #ev[1].targets == 0, true)

		-- ห้องอื่นไม่เกี่ยว: ยืนข้างบอสห้อง 1 ไม่ทำให้บอสห้อง 2 ง้าง
		check("บอสห้อง 2 ไม่ง้างเพราะคนข้างบอสห้อง 1", s.rooms[2].slamPhase, "idle")
		-- ตีทุกคนในวง รวมคนวิ่งผ่าน/คนที่ไม่มีสิทธิ์ห้อง (ไม่ดู wallProgress)
		local boss3 = Config.getBossCornerCenter(3)
		check("getSlamTargets ไม่ดูสิทธิ์ห้อง (คนวิ่งผ่านก็โดน)",
			#BossService.getSlamTargets(3, { [9] = pos(boss3.X + 3, boss3.Z) }), 1)
	end

	----------------------------------------------------------------------------
	print("── 5D บอสฟาด: ไม่ฟาดตอนกลางคืน · บอสตายกลางจังหวะง้าง = ยกเลิก · ปิดสวิตช์ = ไม่ฟาด ──")
	----------------------------------------------------------------------------
	do
		local boss1 = Config.getBossCornerCenter(1)
		local near = { [1] = pos(boss1.X - 10, boss1.Z) }
		local s0 = BossService.newState(0)
		check("เซิร์ฟเปิดใหม่ (ยังไม่มีบอส) → ไม่ฟาด", #BossService.stepSlams(s0, 10, near), 0)
		BossService.step(s0, DAY)
		check("กลางคืน (บอสเพิ่งเกิด) → ไม่ฟาด", #BossService.stepSlams(s0, DAY + 1, near), 0)

		local s, t0 = dayWithBosses()
		BossService.stepSlams(s, t0, near)
		check("กลางวัน → ง้าง", s.rooms[1].slamPhase, "windup")
		BossService.applyDamage(s, 1, 7, Config.getBossHp(1), t0 + 0.5)
		local ev = BossService.stepSlams(s, t0 + 0.5, near)
		check("บอสตายกลางจังหวะง้าง → ยกเลิก (วงหาย ไม่ฟาด)", #ev == 1 and ev[1].kind == "cancel", true)
		check("  ผ่านจังหวะฟาดไปแล้วก็ไม่ฟาด", #BossService.stepSlams(s, t0 + 2, near), 0)

		local s2, t2 = dayWithBosses()
		BossService.stepSlams(s2, t2, near)
		BossService.step(s2, t2 + DAY) -- เข้ากลางคืน
		ev = BossService.stepSlams(s2, t2 + DAY, near)
		check("ง้างค้างตอนเข้ากลางคืน → ยกเลิก", #ev == 1 and ev[1].kind == "cancel", true)

		local s3, t3 = dayWithBosses()
		s3.attackEnabled = false -- debugBossAttack(false)
		check("ปิดสวิตช์ (debugBossAttack off) → ไม่ฟาด", #BossService.stepSlams(s3, t3, near), 0)
		s3.attackEnabled = true
		check("  เปิดกลับ → ง้าง", BossService.stepSlams(s3, t3, near)[1].kind, "windup")
		s3.attackEnabled = false
		check("  ปิดระหว่างง้าง → ยกเลิกทันที", BossService.stepSlams(s3, t3 + 0.2, near)[1].kind, "cancel")
	end

	----------------------------------------------------------------------------
	print("── 5D เลือด: ไม่ฟื้นระหว่างสู้ · ไม่โดนตีครบ 10 วิ แล้วฟื้นทีละนิด (เต็มใน 5 วิ) · เซฟโซน = เต็มทันที · ตายแล้วไม่ฟื้น ──")
	----------------------------------------------------------------------------
	do
		local s = BossService.newState(0)
		local MAX = cycle.PLAYER_MAX_HEALTH
		BossService.recordHit(s, 1, 100)
		check("เพิ่งโดนตี (0 วิ) → ไม่ฟื้น", BossService.planHealth(s, 1, 60, MAX, false, 100, 0.25), 60)
		check("  5 วิ (เท่ารอบฟาด) → ยังไม่ฟื้น (เดิมเต็มทันที)", BossService.planHealth(s, 1, 60, MAX, false, 105, 0.25), 60)
		check("  9.9 วิ → ยังไม่ฟื้น", BossService.planHealth(s, 1, 60, MAX, false, 109.9, 0.25), 60)
		check("  10.25 วิ (ผ่านจุดเริ่มฟื้นมา 0.25 วิ) → +5 (20/วิ) ไม่เต็มทันที",
			BossService.planHealth(s, 1, 60, MAX, false, 110.25, 0.25), 65)
		check("  ช่วง dt คร่อมจุดเริ่มฟื้น → นับเฉพาะส่วนที่เลยจุดเริ่มแล้ว (10.1 · dt 0.25 → +2)",
			math.abs(BossService.planHealth(s, 1, 60, MAX, false, 110.1, 0.25) - 62) < 1e-9, true)
		-- ไล่ทีละ 0.25 วิ จาก 0 → ต้องเต็มในราว 5 วิหลังเริ่มฟื้น
		local health, t = 1, 110
		while health < MAX and t < 130 do
			t += 0.25
			health = BossService.planHealth(s, 1, health, MAX, false, t, 0.25)
		end
		check(`  จาก 1 → เต็ม ใช้ {t - 110} วิหลังเริ่มฟื้น (≈ 5 วิ)`, t - 110 <= cycle.PLAYER_REGEN_FILL_SECONDS and t - 110 >= 4.5, true)
		check("  ไม่เกินเลือดเต็ม", health, MAX)
		BossService.recordHit(s, 1, 112)
		check("  โดนซ้ำระหว่างฟื้น → หยุดฟื้น นับ 10 วิใหม่ (121 ยังไม่ฟื้น)", BossService.planHealth(s, 1, 40, MAX, false, 121, 0.25), 40)
		check("เข้าเซฟโซน → เต็มทันทีแม้เพิ่งโดน", BossService.planHealth(s, 1, 40, MAX, true, 112.1, 0.25), MAX)
		check("ตายแล้ว (0) → ไม่ฟื้น (รอเกิดใหม่)", BossService.planHealth(s, 1, 0, MAX, true, 999, 0.25), 0)
		check("เต็มอยู่แล้ว → เดิม", BossService.planHealth(s, 1, MAX, MAX, false, 112.1, 0.25), MAX)
		check("ไม่เคยโดนบอส (เลือดลดจากทางอื่น) → ฟื้นทีละนิด ไม่เต็มทันที", BossService.planHealth(s, 2, 50, MAX, false, 0, 0.25), 55)
	end

	----------------------------------------------------------------------------
	print("── 5D เลือด (จำลองลูปจริง): ยืนในวงไม่หลบเลย → ตายภายใน 5 ครั้งที่ฟาด · หลบ 1 โดน 1 → ตายในที่สุด ──")
	----------------------------------------------------------------------------
	do
		-- จำลองลูปจริงของ BossService.start: ลูปหลักทุก worldDt (stepSlams → planHealth ด้วย dt จริง)
		--   + ตัวตั้งเวลาฟาดแม่น ๆ ที่ slamAt + 0.02 (task.delay) · ง้างใหม่หลังพักจับได้ที่ลูปหลักเท่านั้น (ช้าได้ถึง worldDt)
		-- dodge(i) = ง้างครั้งที่ i หลบไหม (หลบ = วิ่งออกนอกวงตอนเห็นวง · ฟาดแล้วกลับเข้ามายืนตีต่อ)
		local SLAM_SLACK = 0.02
		local function fight(dodge: (number) -> boolean, worldDt: number, room: number)
			local s, t0 = dayWithBosses()
			local boss = Config.getBossCornerCenter(room)
			local inRing = pos(boss.X - 10, boss.Z)
			local outside = pos(boss.X - (Config.getBossSlamRadius() + 1), boss.Z)
			local health = cycle.PLAYER_MAX_HEALTH
			local windups, slams, hits, dodgingNow = 0, 0, 0, false
			local hpBeforeHit: { number } = {}
			local nextWorld, pendingSlam = t0, nil :: number?
			local lastWorld: number? = nil
			local limit = t0 + DAY
			while nextWorld <= limit do
				local isWorld = pendingSlam == nil or nextWorld <= (pendingSlam :: number)
				local now = if isWorld then nextWorld else pendingSlam :: number
				local positions = { [1] = if dodgingNow then outside else inRing }
				for _, e in BossService.stepSlams(s, now, positions) do
					if e.kind == "windup" then
						windups += 1
						dodgingNow = dodge(windups)
						pendingSlam = e.at + SLAM_SLACK
					elseif e.kind == "slam" then
						slams += 1
						pendingSlam = nil
						if table.find(e.targets, 1) then
							hits += 1
							table.insert(hpBeforeHit, health)
							BossService.recordHit(s, 1, now)
							health = math.max(0, health - Config.getBossSlamDamage())
							if health <= 0 then
								return hits, slams, now - t0, hpBeforeHit
							end
						end
						dodgingNow = false -- ฟาดแล้วกลับเข้ามายืนตีต่อ
					end
				end
				if isWorld then
					local dt = if lastWorld then now - (lastWorld :: number) else 0
					lastWorld = now
					health = BossService.planHealth(s, 1, health, cycle.PLAYER_MAX_HEALTH, false, now, dt)
					nextWorld += worldDt
				elseif pendingSlam ~= nil and now >= (pendingSlam :: number) then
					pendingSlam = nil -- ตัวตั้งเวลาทำงานแล้ว (ฟาดจริงถ้าถึงเวลา — ไม่งั้นลูปหลักรับต่อ)
				end
			end
			return hits, slams, math.huge, hpBeforeHit
		end

		for _, worldDt in { 0.25, 0.05 } do
			local hits, slams, seconds, before = fight(function(_i)
				return false
			end, worldDt, 4)
			check(`ยืนในวงไม่หลบ (ลูป {worldDt} วิ): ตายภายใน 5 ครั้งที่ฟาด (โดน {hits}/{slams} · {string.format("%.2f", seconds)} วิ)`,
				hits == 5 and slams <= 5, true)
			check(`  ไม่ได้ฟื้นเลยระหว่างโดน (เลือดก่อนโดนแต่ละครั้ง 100 → 80 → 60 → 40 → 20)`,
				before[1] == 100 and before[2] == 80 and before[3] == 60 and before[4] == 40 and before[5] == 20, true)
			print(string.format("   ยืนในวงไม่หลบ (ลูป %.2f วิ): ตายที่ฟาดครั้งที่ %d · %.2f วิ", worldDt, slams, seconds))
		end

		-- หลบ 1 โดน 1 (เริ่มด้วยโดน / เริ่มด้วยหลบ) · ลูปหลักจริง task.wait(0.25) มักช้ากว่าที่ขอเล็กน้อย → ลอง 0.27 / 0.3 ด้วย
		--   (ง้างใหม่จับได้ช้าสุดเกือบ 1 ลูป → ช่วงห่างระหว่างโดนยาวเกิน 10 วิ = ได้ฟื้นเล็กน้อย — กรณีแย่สุดของกติกานี้)
		for _, startWithDodge in { false, true } do
			for _, worldDt in { 0.25, 0.27, 0.3, 0.05 } do
				local hits, slams, seconds, before = fight(function(i)
					return (i % 2 == 1) == startWithDodge
				end, worldDt, 6)
				local maxRegain = 0
				for index = 2, #before do
					maxRegain = math.max(maxRegain, before[index] - (before[index - 1] - Config.getBossSlamDamage()))
				end
				check(`หลบ 1 โดน 1 ({if startWithDodge then "เริ่มหลบ" else "เริ่มโดน"} · ลูป {worldDt} วิ): ตายในที่สุด `
					.. `(โดน {hits} ครั้งจากฟาด {slams} · {string.format("%.1f", seconds)} วิ · ฟื้นระหว่างคู่สูงสุด {string.format("%.1f", maxRegain)})`,
					seconds < DAY, true)
				check(`  ฟื้นระหว่างโดนแต่ละครั้งน้อยกว่าดาเมจ 1 ครั้ง (เลือดลดลงสุทธิทุกคู่)`, maxRegain < Config.getBossSlamDamage(), true)
				print(string.format("   หลบ 1 โดน 1 (%s · ลูป %.2f วิ): ตายหลังโดน %d ครั้ง (ฟาด %d) · %.1f วิ · ฟื้นระหว่างคู่สูงสุด %.1f",
					if startWithDodge then "เริ่มหลบ" else "เริ่มโดน", worldDt, hits, slams, seconds, maxRegain))
			end
		end
	end

	----------------------------------------------------------------------------
	print("── 5D ตาย/เกิดใหม่: สนามรบ → หน้าทางเข้าเลน · เซฟโซน → คอก · ไข่กลับที่ · ดาเมจยังนับ · ข้อมูลผู้เล่นไม่เปลี่ยน ──")
	----------------------------------------------------------------------------
	do
		local s, t0 = dayWithBosses()
		local bossRoom = Config.getBossCornerCenter(1)
		check("ตายในห้องบอส (สนามรบ) → เกิดหน้าทางเข้าเลน", (BossService.handleDeath(s, 1, pos(bossRoom.X - 10, bossRoom.Z))), true)
		check("  เกิดใหม่แล้วอ่านได้ครั้งเดียว", BossService.takeGateRespawn(s, 1), true)
		check("  ตายรอบหน้าตัดสินใหม่ (ไม่ค้าง)", BossService.takeGateRespawn(s, 1), false)
		check("ตายที่แท่นอัญเชิญ (ในเลน) → หน้าทางเข้าเลน", (BossService.handleDeath(s, 2, Config.getSummonPedestalCenter())), true)
		check("ตายในคอก (เซฟโซน) → เกิดตามปกติ", (BossService.handleDeath(s, 3, pos(0, 85))), false)
		check("  ไม่ย้ายตอนเกิด", BossService.takeGateRespawn(s, 3), false)
		check("ตายกลางลาน (เซฟโซน) → เกิดตามปกติ", (BossService.handleDeath(s, 4, Config.getBossGatherSpot(1))), false)
		check("ไม่รู้ตำแหน่งตอนตาย → เกิดตามปกติ", (BossService.handleDeath(s, 5, nil)), false)

		-- ไข่ที่ถือกลับจุดเดิม · ดาเมจที่ทำไว้ยังนับ · เลือด/กดค้างล้าง
		BossService.applyDamage(s, 1, 8, 10, t0)
		BossService.applyDamage(s, 1, 9, Config.getBossHp(1), t0) -- บอสห้อง 1 ตาย (คนที่ 9 ฆ่า)
		pick(s, 8, 1, 1)
		check("คนที่ 8 ถือไข่ห้อง 1 อยู่", BossService.getCarriedEgg(s, 8) ~= nil, true)
		BossService.recordHit(s, 8, t0)
		s.holds[8] = { room = 1, index = 2, beganAt = t0 }
		local gate, egg = BossService.handleDeath(s, 8, pos(bossRoom.X, 0))
		check("ตายระหว่างถือไข่ → ไข่กลับจุดเดิม (resting)", egg ~= nil and egg.status == "resting" and egg.carrier == nil, true)
		check("  ไม่ถือแล้ว", BossService.getCarriedEgg(s, 8), nil)
		check("  เกิดหน้าทางเข้าเลน", gate, true)
		check("  จังหวะกดค้างที่ค้างอยู่ถูกล้าง", s.holds[8], nil)
		check("  เวลาโดนตีล่าสุดถูกล้าง (เกิดใหม่เลือดเต็ม)", s.lastHitAt[8], nil)
		check("ดาเมจที่ทำใส่บอสไว้ยังนับหลังตาย", s.rooms[1].damageBy[8], 10)

		-- เงินบอส: กติกาเดิม — ตาย/อยู่นอกห้องตอนบอสตาย = ไม่ได้ · กลับเข้าห้องทันก็ได้ตามปกติ
		local s2, t2 = dayWithBosses()
		BossService.applyDamage(s2, 2, 1, 50, t2)
		BossService.applyDamage(s2, 2, 2, 50, t2)
		BossService.handleDeath(s2, 2, pos(Config.getBossCornerCenter(2).X, 0))
		local _, recipients = BossService.planReward(s2, 2, function(userId)
			return userId == 1 -- คนที่ 2 ยังตาย/อยู่หน้าทางเข้าเลน (ไม่อยู่ในห้อง)
		end)
		check("ตายแล้วไม่อยู่ในห้องตอนบอสตาย → ไม่ได้ส่วนแบ่ง", #recipients == 1 and recipients[1] == 1, true)
		local _, back = BossService.planReward(s2, 2, function(_userId)
			return true -- คนที่ 2 วิ่งกลับเข้าห้องทันก่อนบอสตาย
		end)
		check("กลับเข้าห้องทันก่อนบอสตาย → ได้ส่วนแบ่งตามปกติ (ดาเมจเดิมยังนับ)", #back, 2)

		-- ไม่แตะข้อมูลผู้เล่นเลย: handleDeath ไม่รับ PlayerData — ยืนยันว่าข้อมูลที่เซฟไว้เหมือนเดิมทุกไบต์
		local data = PlayerData.createNew()
		data.currency.coins = 123456
		local before = PlayerData.encode(data)
		local s3 = dayWithBosses()
		BossService.handleDeath(s3, 1, pos(Config.getBossCornerCenter(1).X, 0))
		BossService.takeGateRespawn(s3, 1)
		check("ตาย/เกิดใหม่ไม่แตะ PlayerData (เงิน · แม่ · ไข่ · ทหาร · อัญเชิญ)", PlayerData.encode(data), before)
		check("  ล็อกอัญเชิญไม่เปลี่ยนเพราะตาย", (function()
			local s4 = dayWithBosses()
			BossService.lockUser(s4, 1, 3)
			BossService.handleDeath(s4, 1, pos(Config.getBossCornerCenter(3).X, 0))
			return BossService.getLockedRoom(s4, 1)
		end)(), 3)
	end

	----------------------------------------------------------------------------
	print("── 5D เกิดใหม่หน้าทางเข้าเลน: จุดวาปกลางคืน กระจายไม่ซ้อน · กระบองกลับมา ──")
	----------------------------------------------------------------------------
	do
		check("ไม่มีใครอยู่ → จุด 1", BossService.pickGateSpot({}), 1)
		local first = Config.getBossGatherSpot(1)
		local second = BossService.pickGateSpot({ first })
		check("มีคนยืนจุด 1 → ได้จุดอื่น", second ~= 1, true)
		local taken = { first, Config.getBossGatherSpot(second) }
		local third = BossService.pickGateSpot(taken)
		check("  คนที่สาม → ไม่ซ้อนสองคนแรก", third ~= 1 and third ~= second, true)
		local allSafe = true
		for index = 1, Config.World.MAX_PENS do
			if not Config.isInSafeZone(Config.getBossGatherSpot(index)) then
				allSafe = false
			end
		end
		check("จุดเกิดหน้าทางเข้าเลนทุกจุดอยู่ในเซฟโซน (เต็มเลือดทันที · ฝั่งลานกลาง)", allSafe, true)
		check("ตายแล้วกระบองหาย (ไม่อยู่ทั้งมือและกระเป๋า) → สร้างใหม่", BossService.needsWeapon(true, false, false), true)
		check("  มีในกระเป๋าแล้ว → ไม่สร้างซ้ำ", BossService.needsWeapon(true, false, true), false)
		check("  ถืออยู่ในมือ → ไม่สร้างซ้ำ", BossService.needsWeapon(true, true, false), false)
		check("  ยังตายอยู่ (รอเกิด) → ยังไม่สร้าง", BossService.needsWeapon(false, false, false), false)
		check("กระบองที่สร้างใหม่ = ขั้นที่เซฟไว้ (clamp weaponLevel)", Config.clampClubTier(7), 7)
	end

	----------------------------------------------------------------------------
	print("── 5D หลบบอสฟาดแล้วตีต่อ (จำลองทีละ 0.05 วิ): ขั้น N ตีห้อง N คนเดียวทันกลางวัน · ไม่โดนสักครั้ง ──")
	----------------------------------------------------------------------------
	do
		-- ผู้เล่นทำตามโมเดลใน Config.getBossDodgeUptime: เห็นวงแดงแล้ววิ่งออกทันที (ตีไม่ได้ทั้งช่วงง้าง) ·
		-- ฟาดลงแล้ววิ่งกลับจากขอบวงที่วาดเข้าระยะตี ((18 − 14) ÷ 32 วิ) แล้วตีตามคูลดาวน์
		local walkBack = (Config.getBossSlamRadius() - cycle.PLAYER_ATTACK_RANGE) / Config.MapDimensions.Player.WalkSpeed
		local function simulate(tier, room)
			local s, t0 = dayWithBosses()
			local boss = Config.getBossCornerCenter(room)
			local inRange = pos(boss.X - 10, boss.Z)
			local outside = pos(boss.X - (Config.getBossSlamRadius() + 1), boss.Z)
			local dodging, backAt, nextAttack, everHit = false, t0, t0, false
			local i = 0
			while true do
				local now = t0 + i * 0.05
				if now > t0 + DAY then
					return math.huge, everHit
				end
				for _, e in BossService.stepSlams(s, now, { [1] = if dodging then outside else inRange }) do
					if e.kind == "windup" then
						dodging = true
					elseif e.kind == "slam" then
						if table.find(e.targets, 1) then
							everHit = true
						end
						dodging = false
						backAt = e.at + walkBack
					end
				end
				if not dodging and now >= backAt and now >= nextAttack then
					local result, _, killed = BossService.tryAttack(s, 1, now, room, 10, tier, room)
					nextAttack = now + cycle.PLAYER_ATTACK_COOLDOWN
					if result == "ok" and killed then
						return now - t0, everHit
					end
				end
				i += 1
			end
		end
		local worst = 0
		for room = 1, STAGES do
			local seconds, hit = simulate(room, room)
			worst = math.max(worst, seconds)
			check(`ห้อง {room}: ขั้น {room} หลบแล้วตีตาย {string.format("%.1f", seconds)} วิ ≤ กลางวัน · หลบทันทุกครั้ง`,
				seconds <= DAY and not hit, true)
			check(`  ไม่ช้ากว่าค่าประเมินใน Config (หักหลบแบบเผื่อ)`, seconds <= Config.getClubSoloKillSecondsWithDodge(room, room) + 0.5, true)
		end
		local rookie, rookieHit = simulate(1, 2)
		check(`มือใหม่ขั้น 1 ตีห้อง 2 หลบแล้ว {string.format("%.1f", rookie)} วิ ≤ กลางวัน (ทางเลือก B)`, rookie <= DAY and not rookieHit, true)
		local capstone = simulate(10, 9)
		check(`ขั้น 10 ตีห้อง 9 หลบแล้ว {string.format("%.1f", capstone)} วิ`, capstone <= DAY, true)
		print(string.format("   ห้อง 1 %.1f วิ · ห้อง 2–9 (ขั้น N) ช้าสุด %.1f วิ · มือใหม่ %.1f วิ · ขั้น 10 ห้อง 9 %.1f วิ",
			(simulate(1, 1)), worst, rookie, capstone))
	end
end
