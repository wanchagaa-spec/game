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

	-- 5E-1 เดินทัพ: ลงสนามแล้วต้องเดินจากแท่นอัญเชิญก่อนถึงแนวรบ (ด่าน 9 เต็มทาง ~44 วิ) → tick ซ้ำจนด่านพัง
	-- คืนผลของ tick ที่ด่านพัง (หรือ tick สุดท้ายถ้าไม่พังภายใน maxSeconds)
	local function tickUntilCleared(data, meta, maxSeconds: number?)
		local limit = maxSeconds or 120
		local elapsed = 0
		local result
		repeat
			result = CombatService.tick(data, meta, 5)
			elapsed += 5
		until result.stageCleared or elapsed >= limit
		return result
	end

	-- ลงสนาม + เดินเวลาจนกองทัพเดินทัพถึงแนวรบ (ระหว่างเดินไม่มีใครตีใคร) · คืนผลรวมระหว่างเดิน
	local function tickThroughMarch(data, meta)
		local total = { damageDealt = 0, turretShots = 0, unitsReleased = 0, childrenLost = 0 }
		local function add(r)
			total.damageDealt += r.damageDealt
			total.turretShots += r.turretShots
			total.unitsReleased += r.unitsReleased
			total.childrenLost += r.childrenLost
		end
		add(CombatService.tick(data, meta, 0.01))
		while meta.marchRemaining > 0 do
			add(CombatService.tick(data, meta, math.min(5, meta.marchRemaining)))
		end
		return total
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
		data.releaseOrder = { key } -- UI-3: ปล่อยเฉพาะกองที่ติ๊ก

		check("ผู้เล่นใหม่ wallProgress = ค่าเริ่มต้น", data.wallProgress, Config.Balance.NewPlayer.wallProgress)

		-- ด่าน 1 ไม่มีทหารฝ่ายรับ/กำแพง (0,0) → พังเรียบร้อยทันทีที่ tick แรกที่เปิดอัญเชิญ
		CombatService.tick(data, meta, 1)
		check("ด่าน 1 พังเรียบร้อยแล้ว (ไม่มีกำแพงให้พังตั้งแต่แรก)", CombatService.getActiveStage(data), 2)
		check(
			"จำลองตีด่าน 1 จนพังสมบูรณ์ → wallProgress ต้องเป็น 1 (ด่าน 1 ไม่มีกำแพงจริง ไม่นับเพิ่ม)",
			data.wallProgress,
			1
		)

		-- ด่าน 2 ต้องการ 15,000 HP รวม — 5E-1: ช่องเต็ม 6 ตัว ดาเมจรวม 360 × อัตราปล่อย 1 = 360/วิ → ~45 วิ
		for _ = 1, 30 do
			if CombatService.tick(data, meta, 5).stageCleared then
				break
			end
		end
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
		dataA.releaseOrder = { key } -- UI-3: ปล่อยเฉพาะกองที่ติ๊ก
		dataB.releaseOrder = { key }

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

	print("── 3C-1 → 5E-1 แม่ลงสนาม: เลือด = พลังฐาน · ดาเมจ/วิ = พลังเต็ม × อัตราปล่อย ÷ 6 · แม่ 1 = ลูก 10 ──")

	do
		local motherPower = Config.computeBattlePower(100, "monkey", {}, 0)
		local childPower = Config.computeBattlePower(Config.getChildWeight(100, {}), "monkey", {}, 0)
		local near = t.near
		near("แม่ลิง 100 kg พลัง 10", motherPower, 10, 1e-9)
		near("แม่แรงเป็น 10 เท่าของลูกตัวเอง (กฎ 'แม่ 1 = ลูก 10')", motherPower / childPower, 10, 1e-9)

		local data = dataAtStage2()
		local meta = freshMeta()
		table.insert(data.battleRoster, makeMother())
		table.insert(data.battleRoster, makeMother())
		local before = data.stageProgress[2].defendersRemaining

		local marched = tickThroughMarch(data, meta)
		check("ไม่มีลูกในคลัง → แม่ 2 ตัวลงสนาม (ลูกหมด = แม่ลงช่องอื่นได้)", marched.unitsReleased, 2)
		check("  ระหว่างเดินทัพไปกึ่งกลางยังไม่มีใครตีใคร", marched.damageDealt, 0)
		check("  เดินถึงกึ่งกลางเลนแล้ว", meta.lineAt, "middle")
		local result = CombatService.tick(data, meta, 2)
		check("  แม่ตัวแรกยืนช่องหลังสุด", meta.field[Config.Balance.Combat.MOTHER_SLOT].uid, data.battleRoster[1].uid)
		check("  แม่ตัวที่สองลงช่องหน้าสุด", meta.field[1].uid, data.battleRoster[2].uid)
		-- ด่าน 2 อัตราปล่อย 1 → แม่ละ 10 × 1 ÷ 6 ต่อวิ × 2 ตัว × 2 วิ
		near("แม่ 2 ตัว × (10 × 1 ÷ 6) × 2 วินาที", result.damageDealt, 2 * 10 / 6 * 2, 1e-6)
		near("ทหารฝ่ายรับลดลงเท่าดาเมจจริง", before - data.stageProgress[2].defendersRemaining, result.damageDealt, 1e-6)
		check("ด่านยังไม่พัง แม่ยังไม่ตาย → roster ครบ", #data.battleRoster, 2)
		check("ด่านยังไม่พัง → mothersLost = 0", result.mothersLost, 0)
		near("เลือดแม่ = พลังฐาน (ไม่รวมอัปดาเมจ)", meta.field[1].maxHp, 10, 1e-9)

		-- damageLevel ที่ซื้อไว้มีผลกับแม่ด้วย (ตัวคูณเป็นของบัญชี) แต่ไม่เพิ่มเลือด
		data.damageLevel = 8
		CombatService.tick(data, meta, 0.01)
		near("ดาเมจ/วิของแม่คูณ 1.1^damageLevel ด้วย", meta.field[1].dps, Config.computeBattlePower(100, "monkey", {}, 8) / 6, 1e-6)
		near("  เลือดยังเท่าเดิม", meta.field[1].maxHp, 10, 1e-9)
		check("ไม่มี getRosterDps แล้ว (แม่ไม่ตีรวดทั้ง roster)", CombatService.getRosterDps, nil)
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

		local result = tickUntilCleared(data, meta)
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
			local result = tickUntilCleared(data, freshMeta())
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
		local first = tickUntilCleared(data, meta)
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
		local result = tickUntilCleared(migrated, freshMeta())
		check("ด่าน 4 เพิ่งพังหลังอัปเดต → ได้ไข่ของด่าน 4 เท่านั้น (2 ฟอง)", result.bonusEggs, 2)
		check("  ธงด่าน 4 = true", migrated.stageClearBonusGranted[4], true)
		check("  ด่าน 1–3 ที่พังก่อนอัปเดตยังไม่ได้รางวัล (false)", countTrue(migrated.stageClearBonusGranted), 1)
	end

	print("── 4A stageClearBonusGranted ผ่าน encode/decode ครบ ──")

	do
		local data = dataAboutToClear(5)
		tickUntilCleared(data, freshMeta())
		PlayerData.sanitizeForSave(data) -- ต้องไม่ throw (อาเรย์ boolean ยาวคงที่ ไม่มีรู)
		local back = Json.decode(PlayerData.encode(data))
		check("ธงด่าน 5 กลับมาเป็น true", back.stageClearBonusGranted[5], true)
		check("ธงด่าน 4 กลับมาเป็น false", back.stageClearBonusGranted[4], false)
		check("ยาว 9 ช่องเท่าเดิม", #back.stageClearBonusGranted, 9)
	end

	----------------------------------------------------------------------------
	-- Phase 4B แจ้งแม่ในสนามรบที่ตายรวมกับ popup ผ่านด่าน + ล็อกแม่ยังกันส่งไปรบ
	----------------------------------------------------------------------------

	print("── 4B ข้อความ popup ผ่านด่าน 4 กรณี (Config.formatStageClearedMessage) ──")

	do
		local function fullText(stage: number, eggs: number, deaths: number): string
			local title, body = Config.formatStageClearedMessage(stage, eggs, deaths)
			return `{title} {body}`
		end
		check("ไข่ + แม่ตาย", fullText(4, 2, 3), "ผ่านด่าน 4 สำเร็จ! ได้รับไข่ฟรี 2 ฟอง • เสียแม่ในสนามรบ 3 ตัว")
		check("ไข่อย่างเดียว", fullText(2, 1, 0), "ผ่านด่าน 2 สำเร็จ! ได้รับไข่ฟรี 1 ฟอง")
		check("แม่ตายอย่างเดียว", fullText(7, 0, 10), "ผ่านด่าน 7 สำเร็จ! เสียแม่ในสนามรบ 10 ตัว")
		-- (0, 0) มาถึง client ได้กรณีเดียว = ควรได้ไข่แต่กระเป๋าไข่เต็ม (พฤติกรรมเดิม 4A)
		-- ส่วน "ไม่มีทั้งคู่จริง ๆ" server ไม่ยิงเลย — ตรวจที่ shouldNotifyStageCleared ข้างล่าง
		check("0/0 = กระเป๋าไข่เต็ม (ข้อความเดิม 4A)", fullText(3, 0, 0), "ผ่านด่าน 3 สำเร็จ! กระเป๋าไข่เต็ม — ไม่ได้รับไข่ฟรีของด่านนี้")
		local title = Config.formatStageClearedMessage(5, 2, 1)
		check("หัวข้อแยกออกมาได้ (ใช้กับ label หัวข้อของ popup)", title, "ผ่านด่าน 5 สำเร็จ!")
	end

	print("── 4B server ตัดสินใจยิง popup: มีไข่ หรือ มีแม่ตาย อย่างใดอย่างหนึ่ง ──")

	do
		local function result(clearedStage: number?, bonusEggs: number, mothersLost: number)
			return {
				unitsReleased = 0,
				damageDealt = 0,
				coinsEarned = 0,
				stageCleared = clearedStage ~= nil,
				autoPaused = false,
				mothersLost = mothersLost,
				clearedStage = clearedStage,
				bonusEggs = bonusEggs,
			}
		end
		check("ไข่ + แม่ตาย → ยิง", CombatService.shouldNotifyStageCleared(result(4, 2, 3)), true)
		check("ไข่อย่างเดียว → ยิง", CombatService.shouldNotifyStageCleared(result(2, 1, 0)), true)
		check("แม่ตายอย่างเดียว → ยิง", CombatService.shouldNotifyStageCleared(result(2, 0, 1)), true)
		check("ไม่มีทั้งคู่ → ไม่ยิง (ไม่มี popup ว่าง)", CombatService.shouldNotifyStageCleared(result(2, 0, 0)), false)
		check("ด่านไม่พัง → ไม่ยิง", CombatService.shouldNotifyStageCleared(result(nil, 0, 0)), false)
	end

	print("── 4B ผ่าน tick จริง: นับแม่ตายก่อนล้าง roster แล้วส่งต่อได้ครบ ──")

	do
		-- ครั้งแรกที่ด่าน 2 พัง + roster 3 ตัว → ได้ทั้งไข่และแม่ตาย
		local data = dataAboutToClear(2)
		table.insert(data.battleRoster, makeMother())
		table.insert(data.battleRoster, makeMother())
		local first = tickUntilCleared(data, freshMeta())
		check("ด่าน 2 พังครั้งแรก: ไข่ 1", first.bonusEggs, 1)
		check("  แม่ตาย 3 (นับก่อนล้าง roster)", first.mothersLost, 3)
		check("  roster ถูกล้างแล้วจริง", #data.battleRoster, 0)
		check("  → ยิง popup", CombatService.shouldNotifyStageCleared(first), true)

		-- พังซ้ำหลังได้รางวัลไปแล้ว (เช่น debug ตั้ง HP ด่าน 2 กลับมา) + มีแม่ในสนาม → แม่ตายอย่างเดียว
		local again = dataAboutToClear(2)
		again.stageClearBonusGranted[2] = true
		local repeatResult = tickUntilCleared(again, freshMeta())
		check("พังซ้ำ: ไม่ได้ไข่", repeatResult.bonusEggs, 0)
		check("  แม่ตาย 1", repeatResult.mothersLost, 1)
		check("  → ยังยิง popup (แจ้งแม่ตาย)", CombatService.shouldNotifyStageCleared(repeatResult), true)

		-- ด่าน 1 (ไม่มีศัตรู) พังฟรี: ไม่มีไข่ แม่ไม่ตาย → ไม่ยิง (คงพฤติกรรมเดิม)
		local stage1 = freshData()
		stage1.summonEnabled = true
		table.insert(stage1.battleRoster, makeMother())
		local freeClear = CombatService.tick(stage1, freshMeta(), 1)
		check("ด่าน 1 พังฟรี: clearedStage = 1", freeClear.clearedStage, 1)
		check("  → ไม่ยิง popup", CombatService.shouldNotifyStageCleared(freeClear), false)
	end

	print("── 4B แม่ที่ล็อกยังส่งไปรบไม่ได้ · ปลดล็อกแล้วส่งได้ (logic ส่งไปรบเดิม ไม่ได้แก้) ──")

	do
		local data = dataAtStage2()
		local mother = makeMother()
		mother.locked = true
		table.insert(data.mothersInBag, mother)
		local ok, message = CombatService.handleSendMotherToBattle(data, mother.uid)
		check("ล็อกอยู่ → ปฏิเสธ", ok, false)
		check("  ข้อความเดิม", message, "แม่ตัวนี้ถูกล็อกไว้ ส่งไปรบไม่ได้")
		check("  ยังอยู่ในกระเป๋า", #data.mothersInBag, 1)
		check("  roster ว่าง", #data.battleRoster, 0)

		mother.locked = false
		check("ปลดล็อกแล้ว → ส่งได้", (CombatService.handleSendMotherToBattle(data, mother.uid)), true)
		check("  ย้ายเข้า roster", #data.battleRoster, 1)
	end

	----------------------------------------------------------------------------
	-- UI-3: ส่งแม่ไปรบเป็นชุด (SendMothersToBattleBatchRequest) — แกนเดียวกับส่งทีละตัว
	----------------------------------------------------------------------------
	print("── UI-3 ส่งแม่เป็นชุด: ผลเท่ากับส่งทีละตัว · ลำดับ roster = ลำดับที่ส่ง ──")

	do
		local batchData = dataAtStage2()
		local singleData = dataAtStage2()
		local uids = {}
		for index = 1, 4 do
			local mother = makeMother(100 * index)
			table.insert(uids, mother.uid)
			table.insert(batchData.mothersInBag, table.clone(mother))
			table.insert(singleData.mothersInBag, table.clone(mother))
		end
		-- ส่งสลับลำดับ (3, 1, 4) ไม่ส่งตัวที่ 2
		local order = { uids[3], uids[1], uids[4] }
		local ok, reason, summary = CombatService.handleSendMothersToBattleBatch(batchData, order)
		for _, uid in order do
			CombatService.handleSendMotherToBattle(singleData, uid)
		end
		check("ส่งเป็นชุดสำเร็จ", ok, true)
		check("  reason เป็น nil", reason, nil)
		check("  ส่งได้ 3 ข้าม 0", summary and `{summary.sent}/{summary.skipped}`, "3/0")
		check("  roster 3 ตัว", summary and summary.rosterCount, 3)
		check("roster เท่ากับส่งทีละตัว (จำนวน)", #batchData.battleRoster, #singleData.battleRoster)
		for index = 1, 3 do
			check(`  roster ช่อง {index} = uid ลำดับที่ส่ง`, batchData.battleRoster[index].uid, order[index])
			check(`  ช่อง {index} ตรงกับส่งทีละตัว`, batchData.battleRoster[index].uid, singleData.battleRoster[index].uid)
		end
		check("กระเป๋าเหลือตัวที่ไม่ได้ส่ง (ตัวที่ 2)", batchData.mothersInBag[1] and batchData.mothersInBag[1].uid, uids[2])
		check("กระเป๋าเท่ากับส่งทีละตัว", #batchData.mothersInBag, #singleData.mothersInBag)
	end

	print(`── UI-3 ส่งเป็นชุด: ในสนามแล้ว 5 ตัว ส่งเพิ่ม 10 → roster ไม่เกิน {MAX_ROSTER} ──`)

	do
		local data = dataAtStage2()
		for _ = 1, 5 do
			table.insert(data.battleRoster, makeMother())
		end
		local uids = {}
		for _ = 1, 10 do
			local mother = makeMother()
			table.insert(data.mothersInBag, mother)
			table.insert(uids, mother.uid)
		end
		local ok, _, summary = CombatService.handleSendMothersToBattleBatch(data, uids)
		check("ส่งได้บางตัว = สำเร็จ", ok, true)
		check(`  roster = {MAX_ROSTER} พอดี ไม่เกิน`, #data.battleRoster, MAX_ROSTER)
		check("  ส่งได้ 5 · ข้าม 5 (roster เต็ม)", summary and `{summary.sent}/{summary.skipped}`, "5/5")
		check("  5 ตัวแรกที่ส่งเข้า roster (ตามลำดับ)", data.battleRoster[6].uid, uids[1])
		check("  ตัวที่ถูกข้ามยังอยู่ในกระเป๋า", #data.mothersInBag, 5)
		check("  ตัวที่ถูกข้ามคือ 5 ตัวท้าย", data.mothersInBag[1].uid, uids[6])
	end

	print("── UI-3 ส่งเป็นชุด: ข้ามแม่ล็อก / แม่ในคอก / ของคนอื่น / uid ซ้ำ แล้วส่งตัวอื่นต่อ ──")

	do
		local data = dataAtStage2()
		local good1, good2 = makeMother(), makeMother()
		local locked = makeMother()
		locked.locked = true
		local inPen = makeMother()
		table.insert(data.mothersInBag, good1)
		table.insert(data.mothersInBag, locked)
		table.insert(data.mothersInBag, good2)
		table.insert(data.mothersInPen, inPen)
		local foreign = Config.makeUid(999, 7)

		local ok, _, summary = CombatService.handleSendMothersToBattleBatch(
			data,
			{ good1.uid, locked.uid, inPen.uid, foreign, good1.uid, good2.uid }
		)
		check("สำเร็จ (มีตัวที่ส่งได้)", ok, true)
		check("  ส่ง 2 · ข้าม 4 (ล็อก · คอก · คนอื่น · ซ้ำ)", summary and `{summary.sent}/{summary.skipped}`, "2/4")
		check("  roster = good1, good2 ตามลำดับ", `{data.battleRoster[1].uid},{data.battleRoster[2].uid}`, `{good1.uid},{good2.uid}`)
		check("  แม่ล็อกยังอยู่ในกระเป๋า", data.mothersInBag[1] and data.mothersInBag[1].uid, locked.uid)
		check("  แม่ในคอกยังอยู่ในคอก", #data.mothersInPen, 1)

		local okNone, reasonNone, summaryNone = CombatService.handleSendMothersToBattleBatch(data, { locked.uid })
		check("ส่งไม่ได้สักตัว → ok = false", okNone, false)
		check("  ยังมี summary (ไม่ใช่ปฏิเสธทั้งชุด)", summaryNone ~= nil, true)
		check("  มีเหตุผล", type(reasonNone), "string")
	end

	print("── UI-3 ส่งเป็นชุด: ไม่มีด่านให้ส่ง (ด่าน HP 0 / ผ่านครบ) → ปฏิเสธทั้งชุด ──")

	do
		-- ด่านที่กำลังตีคือด่าน 1 (HP 0)
		local data = freshData()
		local mother = makeMother()
		table.insert(data.mothersInBag, mother)
		local ok, reason, summary = CombatService.handleSendMothersToBattleBatch(data, { mother.uid })
		check("ด่านที่กำลังตี HP 0 → ปฏิเสธ", ok, false)
		check("  ไม่มี summary (ปฏิเสธทั้งชุด)", summary, nil)
		check("  ข้อความเดียวกับส่งทีละตัว", reason, (select(2, CombatService.handleSendMotherToBattle(data, mother.uid))))
		check("  แม่ยังอยู่ในกระเป๋า", #data.mothersInBag, 1)

		local cleared = freshData()
		for stage = 1, Config.Balance.Stage.COUNT do
			cleared.stageProgress[stage] = { defendersRemaining = 0, wallHpRemaining = 0 }
		end
		local m2 = makeMother()
		table.insert(cleared.mothersInBag, m2)
		local ok2, reason2, summary2 = CombatService.handleSendMothersToBattleBatch(cleared, { m2.uid })
		check("ผ่านครบทุกด่าน → ปฏิเสธ", ok2, false)
		check("  ไม่มี summary", summary2, nil)
		check("  ข้อความ 'ผ่านครบทุกด่าน'", reason2, "ผ่านครบทุกด่านแล้ว ไม่มีด่านให้ส่งแม่ไปรบ")
		check("  roster ว่าง", #cleared.battleRoster, 0)

		check("sync บอกเหตุผลเดียวกัน (ด่าน HP 0)", CombatService.buildSyncFields(data).sendStageBlockReason, reason)
		check("sync บอกเหตุผลเดียวกัน (ผ่านครบ)", CombatService.buildSyncFields(cleared).sendStageBlockReason, reason2)
		check("ด่าน 2 มีศัตรู → sync ไม่มีเหตุผลกั้น", CombatService.buildSyncFields(dataAtStage2()).sendStageBlockReason, nil)
	end

	print("── UI-3 ส่งเป็นชุด: ข้อมูลขยะ → ปฏิเสธทั้งชุด ไม่แตะอะไรเลย ──")

	do
		local data = dataAtStage2()
		local mother = makeMother()
		table.insert(data.mothersInBag, mother)
		local tooMany = {}
		for _ = 1, MAX_ROSTER + 1 do
			table.insert(tooMany, mother.uid)
		end
		local junk = {
			{ "ไม่ใช่ตาราง", "abc" },
			{ "nil", nil },
			{ "ตารางว่าง", {} },
			{ "สมาชิกเป็นตัวเลข", { 1, 2 } },
			{ "มี key ที่ไม่ใช่ตัวเลข", { mother.uid, extra = "x" } },
			{ "มีรู", { [1] = mother.uid, [3] = mother.uid } },
			{ `เกิน {MAX_ROSTER} ตัว`, tooMany },
		}
		for _, case in junk do
			local ok, reason, summary = CombatService.handleSendMothersToBattleBatch(data, case[2])
			check(`{case[1]} → ปฏิเสธ`, ok, false)
			check("  ไม่มี summary", summary, nil)
			check("  มีเหตุผล", type(reason), "string")
		end
		check("แม่ยังอยู่ในกระเป๋าครบ", #data.mothersInBag, 1)
		check("roster ว่าง", #data.battleRoster, 0)
	end

	----------------------------------------------------------------------------
	-- 5E-1 รบแบบชุด 6 ช่อง
	----------------------------------------------------------------------------
	local SLOTS = Config.Balance.Combat.FIELD_SLOTS
	local MOTHER_SLOT = Config.Balance.Combat.MOTHER_SLOT
	local GATHER = Config.Balance.Combat.GATHER_SIZE
	local near = t.near

	-- ด่าน 1..stage-1 พังแล้ว · เปิดอัญเชิญ · ไม่มีแม่ในคอก (ไม่มีกองที่ผลิตเติม → รวมพลไม่รอ ปล่อยเท่าที่มี)
	local function battleData(stage: number)
		local data = freshData()
		for index = 1, stage - 1 do
			data.stageProgress[index] = { defendersRemaining = 0, wallHpRemaining = 0 }
		end
		CombatService.ensureStageStarted(data, stage)
		data.summonEnabled = true
		table.clear(data.mothersInPen)
		return data
	end

	local function layout(meta): string
		local parts = {}
		for slot = 1, SLOTS do
			local unit = meta.field[slot]
			parts[slot] = if unit == nil then "-" elseif unit.kind == "mother" then "m" else "c"
		end
		return table.concat(parts)
	end

	-- ผู้เล่นอ้างอิงของด่าน (ยามสมดุล) + จำลองการผลิตทีละวินาที → คืนชั่วโมงที่ใช้ตีด่านจนพัง
	local function runReference(stage: number): number
		local data = battleData(stage)
		data.wallProgress = stage
		data.damageLevel = Config.getMaxDamageLevel(stage)
		local ref = Config.getReferenceUnitStats(stage)
		local weight = Config.Balance.BalanceCheck.REFERENCE_WEIGHT[stage]
		for index = 1, Config.getPenCapacity(stage) do
			table.insert(data.mothersInPen, { uid = Config.makeUid(777, index), charId = ref.charId, weight = weight,
				statuses = {}, obtainedAt = 0, lastProducedAt = 0, locked = false })
		end
		local key = Config.makeStackKey(ref.charId, weight, {})
		data.releaseOrder = { key }
		local meta = freshMeta()
		local produced, seconds = 0, 0
		while seconds < 200 * 3600 do
			produced += ref.producedPerSecond
			local whole = math.floor(produced)
			produced -= whole
			data.children[key] = math.min(Config.getStackCap(), (data.children[key] or 0) + whole)
			seconds += 1
			if CombatService.tick(data, meta, 1).stageCleared then
				break
			end
		end
		return seconds / 3600
	end

	print("── 5E-1 ชุดละ 6 ตัว: แม่ 1 (ช่องหลังสุด) + ลูก 5 · ลูกบนสนามยังนับอยู่ในกองจนกว่าจะตาย ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local keyA = Config.makeStackKey("wukong", 10000, {})
		data.children[keyA] = 20
		data.releaseOrder = { keyA }
		local m1, m2 = makeMother(), makeMother()
		table.insert(data.battleRoster, m1)
		table.insert(data.battleRoster, m2)

		local result = CombatService.tick(data, meta, 0.01)
		check("ลงสนามครบ 6", result.unitsReleased, 6)
		check("  ลูก 5 ช่องหน้า + แม่ช่องหลังสุด", layout(meta), "cccccm")
		check("  แม่ในช่องหลังคือแม่ตัวแรกของ roster", meta.field[MOTHER_SLOT].uid, m1.uid)
		check("  กองยังนับลูกบนสนามอยู่ (หักตอนตาย)", data.children[keyA], 20)
		check("  ลูกบนสนามจากกองนี้ 5 ตัว", CombatService.getReservedChildren(meta)[keyA], 5)
		check("  พร้อมลงต่อ = ลูก 15 + แม่ 1", CombatService.countAvailable(data, meta), 16)
		near("  เลือดลูก = พลังฐาน", meta.field[1].maxHp, Config.computePower(100, "wukong", {}), 1e-9)
		near("  ดาเมจลูก = พลังเต็ม × อัตราปล่อย ÷ 6", meta.field[1].dps,
			Config.computeBattlePower(100, "wukong", {}, data.damageLevel) * Config.getReleaseRate(2) / SLOTS, 1e-9)
	end

	print("── 5E-1 แม่หมด → ลูก 6 · ลูกหมด → แม่หลายตัว · ไม่มีทางรวมพลครบ → ปล่อยเท่าที่มี ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local keyA = Config.makeStackKey("wukong", 10000, {})
		data.children[keyA] = 20
		data.releaseOrder = { keyA }
		CombatService.tick(data, meta, 0.01)
		check("ไม่มีแม่ → ลูก 6 (ลูกลงช่องแม่)", layout(meta), "cccccc")

		local data2 = battleData(2)
		local meta2 = freshMeta()
		for _ = 1, 8 do
			table.insert(data2.battleRoster, makeMother())
		end
		CombatService.tick(data2, meta2, 0.01)
		check("ไม่มีลูก → แม่ 6", layout(meta2), "mmmmmm")
		check("  ช่องหลังสุด = แม่ตัวแรก", meta2.field[MOTHER_SLOT].uid, data2.battleRoster[1].uid)
		check("  ช่อง 1 = แม่ตัวที่สอง (ตามลำดับ roster)", meta2.field[1].uid, data2.battleRoster[2].uid)
		check("  แม่รอคิว 2 ตัว", CombatService.countAvailable(data2, meta2), 2)

		local data3 = battleData(2)
		local meta3 = freshMeta()
		data3.children[keyA] = 3
		data3.releaseOrder = { keyA }
		table.insert(data3.battleRoster, makeMother())
		CombatService.tick(data3, meta3, 0.01)
		check("ลูก 3 + แม่ 1 · ไม่มีกองที่ผลิตเติม → ลงเท่าที่มี", layout(meta3), "ccc--m")
		check("  ไม่ได้รอรวมพล", meta3.gathering, false)
	end

	print("── 5E-1 ลำดับตรงกับที่ติ๊ก: ลูกตาม releaseOrder (หมดกองแรกไปกองถัดไป) · แม่ตาม roster ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local keyA = Config.makeStackKey("wukong", 10000, {})
		local keyB = Config.makeStackKey("monkey", 800, {})
		data.children[keyA] = 10
		data.children[keyB] = 2
		data.releaseOrder = { keyB, keyA }
		table.insert(data.battleRoster, makeMother())
		CombatService.tick(data, meta, 0.01)
		check("ช่อง 1 = กองที่ติ๊กก่อน", meta.field[1].key, keyB)
		check("ช่อง 2 = กองที่ติ๊กก่อน (ตัวสุดท้ายของกอง)", meta.field[2].key, keyB)
		check("ช่อง 3–5 = กองถัดไป", `{meta.field[3].key == keyA}{meta.field[4].key == keyA}{meta.field[5].key == keyA}`, "truetruetrue")
		check("กองที่ไม่ได้ติ๊กไม่ถูกแตะ", (function()
			local data2 = battleData(2)
			local meta2 = freshMeta()
			data2.children[keyA] = 10
			data2.children[keyB] = 5
			data2.releaseOrder = { keyA }
			CombatService.tick(data2, meta2, 0.01)
			return CombatService.getReservedChildren(meta2)[keyB] == nil and #data2.releaseOrder == 1
		end)(), true)
		local data3 = battleData(2)
		data3.children[keyA] = 100
		local r3 = CombatService.tick(data3, freshMeta(), 1)
		check("releaseOrder ว่าง → ไม่มีใครลงสนาม แม้คลังมีของ", r3.unitsReleased, 0)
		check("  คลังไม่ลด", data3.children[keyA], 100)
		check("ไม่มีฟังก์ชันต่อท้ายอัตโนมัติเหลืออยู่", CombatService.reconcileReleaseOrder, nil)
	end

	print("── 5E-1 ตัวที่ตาย → ตัวถัดไปลงช่องเดิมทันที · ลูกหักจากกอง · แม่ตายถาวรออกจาก roster ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local keyA = Config.makeStackKey("wukong", 10000, {})
		data.children[keyA] = 20
		data.releaseOrder = { keyA }
		local m1, m2 = makeMother(), makeMother()
		table.insert(data.battleRoster, m1)
		table.insert(data.battleRoster, m2)
		CombatService.tick(data, meta, 0.01)

		local oldUnit = meta.field[3]
		oldUnit.hp = 0
		local r = CombatService.tick(data, meta, 0.01)
		check("ลูกช่อง 3 ตาย 1 ตัว", r.childrenLost, 1)
		check("  หักจากกอง 1 ตัว", data.children[keyA], 19)
		check("  stats.childrenLost นับด้วย", data.stats.childrenLost, 1)
		check("  ช่อง 3 มีตัวใหม่ลงแทนทันที", meta.field[3] ~= nil and meta.field[3] ~= oldUnit, true)
		check("  ตัวใหม่เลือดเต็ม", meta.field[3].hp, meta.field[3].maxHp)
		check("  สนามยังเต็ม 6", layout(meta), "cccccm")

		local lostBefore = data.stats.mothersLost
		meta.field[MOTHER_SLOT].hp = 0
		local r2 = CombatService.tick(data, meta, 0.01)
		check("แม่ตายกลางสนาม → mothersFallen 1", r2.mothersFallen, 1)
		check("  ออกจาก roster ถาวร", #data.battleRoster, 1)
		check("  เหลือ m2", data.battleRoster[1].uid, m2.uid)
		check("  stats.mothersLost +1", data.stats.mothersLost - lostBefore, 1)
		check("  m2 ลงช่องแม่แทนทันที", meta.field[MOTHER_SLOT].uid, m2.uid)
		check("  ไม่นับใน mothersLost ของ popup ผ่านด่าน", r2.mothersLost, 0)
		check("ข้อความแจ้งแม่ตายกลางสนาม", Config.formatMotherFallenMessage(1, 1),
			`แม่ตายในสนามรบ 1 ตัว (ตายถาวร) · เหลือในสนามรบ 1/{MAX_ROSTER}`)
	end

	print("── 5E-1 ศัตรูชุดละ ใหญ่ 1 + เล็ก 5 · ตัวใหญ่ 5 เท่า · ตายแล้วชนิดเดียวกันลงช่องเดิม ──")

	do
		local stats = Config.getStageEnemyStats(2)
		local enemy = CombatService.buildEnemyState(2, Config.getStageDefenderHp(2))
		check("ช่อง 1 = ตัวใหญ่", enemy.field[1].kind, "big")
		local smallOk = true
		for slot = 2, SLOTS do
			if not enemy.field[slot] or enemy.field[slot].kind ~= "small" then smallOk = false end
		end
		check("ช่อง 2–6 = ตัวเล็ก", smallOk, true)
		check("คิวตัวใหญ่ = ทั้งด่าน − 1", enemy.bigQueue, stats.bigCount - 1)
		check("คิวตัวเล็ก = ทั้งด่าน − 5", enemy.smallQueue, stats.smallCount - 5)
		check("ตัวใหญ่เลือด 5 เท่า", enemy.field[1].maxHp, enemy.field[2].maxHp * 5)
		check("ตัวใหญ่ดาเมจ 5 เท่า", enemy.field[1].dps, enemy.field[2].dps * 5)
		local function total(state)
			local sum = state.bigQueue * stats.bigHp + state.smallQueue * stats.smallHp
			for slot = 1, SLOTS do
				if state.field[slot] then sum += state.field[slot].hp end
			end
			return sum
		end
		near("เลือดรวมแถวศัตรู = HP ทหารฝ่ายรับทั้งด่าน", total(enemy), Config.getStageDefenderHp(2), 1e-6)
		local half = CombatService.buildEnemyState(2, Config.getStageDefenderHp(2) * 0.37)
		near("สร้างจาก HP ที่เหลือ 37% → เลือดรวมตรงเป๊ะ", total(half), Config.getStageDefenderHp(2) * 0.37, 1e-6)
		check("  ยังเป็นใหญ่ + เล็ก (หมดพร้อมกัน)", half.field[1].kind == "big" and half.field[2].kind == "small", true)
		check("ด่าน 1 ไม่มีศัตรู", CombatService.countEnemies(CombatService.buildEnemyState(1, 0)), 0)

		-- ตีจริง: ตัวที่ตายถูกแทนด้วยชนิดเดิมในช่องเดิม
		local data = battleData(2)
		local meta = freshMeta()
		local keyA = Config.makeStackKey("wukong", 10000, {})
		data.children[keyA] = 100
		data.releaseOrder = { keyA }
		CombatService.tick(data, meta, 3)
		local kindsOk = meta.enemy.field[1].kind == "big"
		for slot = 2, SLOTS do
			kindsOk = kindsOk and meta.enemy.field[slot].kind == "small"
		end
		check("ตีไป 3 วิ ศัตรูตายหลายตัวแล้ว สนามยังเป็นใหญ่ 1 + เล็ก 5", kindsOk, true)
		local big, small = CombatService.countEnemies(meta.enemy)
		check("  ศัตรูลดลงจริง", big + small < stats.bigCount + stats.smallCount, true)
	end

	print("── 5E-1 เลือดรวม/เงินรวมต่อด่านเท่าเดิม · กำแพงโดนหลังศัตรูหมดเท่านั้น · ป้อมยิงเฉพาะตอนถึงกำแพง ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local key = Config.makeStackKey("wukong", 250000, {}) -- ลูก 2,500 kg พลัง 1,800 · อึดมาก ไม่ตาย
		data.children[key] = 50
		data.releaseOrder = { key }
		local coinsBefore = data.currency.coins
		local stats = Config.getStageEnemyStats(2)
		local wallFull = Config.getStageWallHp(2)
		local wallTouchedEarly, killed, damage = false, 0, 0
		local shotsEnemy, shotsWall, shotsWhileMarching = 0, 0, 0
		local wallHitWhileMarching, sawMiddleToWall = false, false
		for _ = 1, 200 do
			local progressBefore = data.stageProgress[2].defendersRemaining
			local wallBefore = data.stageProgress[2].wallHpRemaining
			local marchingBefore = meta.marchRemaining > 0
			local r = CombatService.tick(data, meta, 0.5)
			killed += r.enemiesKilled
			damage += r.damageDealt
			if progressBefore > 0 then
				shotsEnemy += r.turretShots
			else
				shotsWall += r.turretShots
			end
			local p = data.stageProgress[2]
			if p.defendersRemaining > 0 and p.wallHpRemaining < wallFull then
				wallTouchedEarly = true
			end
			if progressBefore <= 0 and marchingBefore and meta.marchRemaining > 0 then
				-- ทั้ง tick อยู่ระหว่างเดินจากกึ่งกลางไปกำแพง
				shotsWhileMarching += r.turretShots
				if p.wallHpRemaining < wallBefore then
					wallHitWhileMarching = true
				end
			end
			if meta.marchFrom == "middle" and meta.lineAt == "wall" then
				sawMiddleToWall = true
			end
			if r.stageCleared then
				break
			end
		end
		check("ด่าน 2 พัง", CombatService.getActiveStage(data), 3)
		check("กำแพงไม่โดนเลยตอนศัตรูยังเหลือ", wallTouchedEarly, false)
		check("ศัตรูตายครบทั้งด่าน (ใหญ่ + เล็ก)", killed, stats.bigCount + stats.smallCount)
		near("HP ที่ลดรวม = HP ทหารฝ่ายรับ + กำแพง", damage, Config.getStageTotalHp(2), 1e-6)
		check("เงินรวมทั้งด่าน = เงินกวาดทหารเดิม (±1 จากเศษ)", math.abs((data.currency.coins - coinsBefore) - Config.getStageDefenderRewardTotal(2)) <= 1, true)
		check("ป้อมไม่ยิงช่วงสู้ศัตรู (สู้กันกึ่งกลางเลน นอกระยะป้อม)", shotsEnemy, 0)
		check("ศัตรูหมด → เดินจากกึ่งกลางไปกำแพง", sawMiddleToWall, true)
		check("  ระหว่างเดินไปกำแพง: ป้อมไม่ยิง", shotsWhileMarching, 0)
		check("  ระหว่างเดินไปกำแพง: กำแพงไม่โดน", wallHitWhileMarching, false)
		check("ป้อมยิงช่วงตีกำแพง (เดินถึงแล้ว)", shotsWall > 0, true)
		check("ลูกที่รอดกลับกองครบ (ไม่มีใครตาย)", data.children[key], 50)
		check("สนามว่างหลังด่านพัง", layout(meta), "------")
		check("แถวศัตรูถูกล้างรอด่านใหม่", meta.enemy, nil)

		-- ป้อมยิงตัวหน้าสุด · ปิดป้อม (debug) = ไม่ยิง
		local data2 = battleData(3)
		local meta2 = freshMeta()
		data2.stageProgress[3].defendersRemaining = 0 -- ศัตรูหมดแล้ว → ลงสนามแล้วเดินเต็มทางไปกำแพง
		data2.children[key] = 50
		data2.releaseOrder = { key }
		local marched = tickThroughMarch(data2, meta2)
		check("ศัตรูหมดแล้ว → เดินจากแท่นเต็มทาง (2 เท่าของครึ่งทาง)", meta2.marchDuration, Config.getArmyMarchSeconds(3) * 2)
		check("  เดินจากแท่นอัญเชิญ", meta2.marchFrom, "pedestal")
		check("  ระหว่างเดิน ป้อมไม่ยิง · กำแพงไม่โดน", `{marched.turretShots} {marched.damageDealt}`, "0 0")
		check("  ถึงกำแพงแล้ว", meta2.lineAt, "wall")
		local r1 = CombatService.tick(data2, meta2, 2)
		check("ป้อมยิง 1 นัด/วิ (นับจากเดินถึง)", r1.turretShots, 2)
		check("  เป้า = ช่องหน้าสุด", meta2.lastTurretTarget, 1)
		CombatService.setTurretEnabled(false)
		local r2 = CombatService.tick(data2, meta2, 3)
		check("debugTurret(false) → ป้อมไม่ยิง", r2.turretShots, 0)
		CombatService.setTurretEnabled(true)
		check("เปิดกลับแล้ว", CombatService.isTurretEnabled(), true)
	end

	print("── 5E-1 ศัตรูที่บาดเจ็บคงสถานะ: ปิดอัญเชิญ/ทหารหมด/ออกเกม ไม่รีเซ็ต HP ──")

	do
		local data = battleData(3)
		local meta = freshMeta()
		local key = Config.makeStackKey("wukong", 10000, {})
		data.children[key] = 40
		data.releaseOrder = { key }
		tickThroughMarch(data, meta)
		CombatService.tick(data, meta, 2.3)
		local snapshot = {}
		for slot = 1, SLOTS do
			snapshot[slot] = meta.enemy.field[slot] and meta.enemy.field[slot].hp
		end
		local remaining = data.stageProgress[3].defendersRemaining
		local wounded = false
		for slot = 1, SLOTS do
			if snapshot[slot] and snapshot[slot] < meta.enemy.field[slot].maxHp then wounded = true end
		end
		check("มีศัตรูบาดเจ็บอยู่บนสนาม", wounded, true)
		local childrenBefore = data.children[key]

		CombatService.handleSetSummonEnabled(data, meta, false)
		check("ปิดอัญเชิญ → สนามฝั่งเราว่างทันที", layout(meta), "------")
		check("  ลูกที่รอดกลับกอง (กองไม่ลด)", data.children[key], childrenBefore)
		CombatService.tick(data, meta, 5)
		local same = true
		for slot = 1, SLOTS do
			local foe = meta.enemy.field[slot]
			if (foe and foe.hp) ~= snapshot[slot] then same = false end
		end
		check("  ศัตรูบาดเจ็บค้างไว้ HP เท่าเดิมทุกช่อง", same, true)
		check("  HP ทหารฝ่ายรับที่เซฟไม่เปลี่ยน", data.stageProgress[3].defendersRemaining, remaining)

		CombatService.handleSetSummonEnabled(data, meta, true)
		CombatService.tick(data, meta, 0.1)
		local continued = true
		for slot = 1, SLOTS do
			local foe = meta.enemy.field[slot]
			if snapshot[slot] and foe and foe.hp > snapshot[slot] + 1e-9 then continued = false end
		end
		check("เปิดใหม่ → ตีต่อจากแผลเดิม (ไม่มีใครเลือดกลับมาเต็ม)", continued, true)

		-- ออกเกม (meta ใหม่) → สร้างแถวจาก HP รวมที่เซฟ · เลือดรวมตรงเป๊ะ
		local rejoin = CombatService.buildEnemyState(3, data.stageProgress[3].defendersRemaining)
		local stats = Config.getStageEnemyStats(3)
		local sum = rejoin.bigQueue * stats.bigHp + rejoin.smallQueue * stats.smallHp
		for slot = 1, SLOTS do
			if rejoin.field[slot] then sum += rejoin.field[slot].hp end
		end
		near("เข้าเกมใหม่ → เลือดรวมศัตรู = HP ที่เซฟไว้", sum, data.stageProgress[3].defendersRemaining, 1e-6)
		local meta2 = freshMeta()
		CombatService.tick(data, meta2, 0.01)
		check("  meta ใหม่ ลูกบนสนามเก่าไม่หาย (ไม่เคยถูกหัก)", data.children[key] >= childrenBefore - 1, true)
	end

	print("── 5E-1 รวมพล (ค3): สนามว่าง → รอครบ 12 ก่อน · ไม่มีทางถึง → ปล่อยเท่าที่มี ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local key = Config.makeStackKey("monkey", 500, {})
		table.insert(data.mothersInPen, { uid = Config.makeUid(1, 99), charId = "monkey", weight = 500, statuses = {},
			obtainedAt = 0, lastProducedAt = 0, locked = false })
		data.children[key] = 7
		data.releaseOrder = { key }
		local r = CombatService.tick(data, meta, 1)
		check("มีกองที่ผลิตเติม · พร้อม 7 < 12 → ยังไม่ลง", r.unitsReleased, 0)
		check("  กำลังรวมพล", meta.gathering, true)
		local battle = CombatService.buildSyncFields(data, false, meta).battle
		check("  sync บอก 'กำลังรวมพล 7/12'", `{battle.gathering} {battle.available}/{battle.gatherTarget}`, `true 7/{GATHER}`)
		data.children[key] = 12
		local r2 = CombatService.tick(data, meta, 0.01)
		check("ครบ 12 → ลง 6", r2.unitsReleased, 6)
		check("  อีก 6 เป็นคลังสำรอง", CombatService.countAvailable(data, meta), 6)
		check("  เลิกรวมพล", meta.gathering, false)
		-- ระหว่างสู้: ตายแล้วเติมทีละตัว ไม่รอรวมพล
		meta.field[1].hp = 0
		CombatService.tick(data, meta, 0.01)
		check("ระหว่างสู้เติมทีละตัว", layout(meta), "cccccc")
		check("  คลังสำรองเหลือ 5", CombatService.countAvailable(data, meta), 5)

		local data2 = battleData(2)
		local meta2 = freshMeta()
		data2.children[key] = 7
		data2.releaseOrder = { key }
		CombatService.tick(data2, meta2, 0.01)
		check("ไม่มีแม่ในคอกผลิตเติม → ไม่มีทางถึง 12 → ลงเท่าที่มี", layout(meta2), "cccccc")
		check("  ไม่รอ", meta2.gathering, false)
	end

	print("── 5E-1 auto-pause: ตายติดกัน 30 ตัวโดยที่ HP ฝั่งตรงข้ามไม่ลดเลย → หยุดปล่อย ──")

	do
		local threshold = Config.Balance.Combat.AUTO_PAUSE_AFTER_DEATHS
		-- ดาเมจ 0 ไม่เกิดในเกมจริง (พลังมีพื้นบวกเสมอ) → จำลองด้วยการสลับสูตรดาเมจชั่วคราวในเทสต์นี้เท่านั้น
		local realDps = Config.getUnitDps
		Config.getUnitDps = function()
			return 0
		end
		local data = battleData(2)
		local meta = freshMeta()
		local key = Config.makeStackKey("monkey", 100, {}) -- ลูก 1 kg เลือด 1 → โดนรุมตายเร็ว
		data.children[key] = 200
		data.releaseOrder = { key }
		local paused, deaths = false, 0
		for _ = 1, 60 do
			local r = CombatService.tick(data, meta, 1)
			deaths += r.childrenLost
			if r.autoPaused then
				paused = true
				break
			end
		end
		Config.getUnitDps = realDps
		check("ตายครบเกณฑ์แล้วหยุดเอง", paused, true)
		check("  ตายพอดีเกณฑ์", deaths, threshold)
		check("  ปิดอัญเชิญ", data.summonEnabled, false)
		check("  ธง combatAutoPaused", data.combatAutoPaused, true)
		check("  สนามว่าง (ตัวที่รอดกลับกอง)", layout(meta), "------")
		check("  กองเหลือ = 200 − ตัวที่ตาย", data.children[key], 200 - threshold)

		-- ตายเยอะแต่ HP ศัตรูยังลด = คืบหน้า → ไม่หยุด
		local data2 = battleData(5)
		local meta2 = freshMeta()
		data2.children[key] = 300
		data2.releaseOrder = { key }
		local anyPause, deaths2 = false, 0
		for _ = 1, 30 do
			local r = CombatService.tick(data2, meta2, 1)
			deaths2 += r.childrenLost
			anyPause = anyPause or r.autoPaused
		end
		check("ตายเกิน 30 ตัวแต่ HP ศัตรูลดตลอด → ไม่หยุด", deaths2 > threshold and not anyPause, true)
		check("  ยังเปิดอัญเชิญ", data2.summonEnabled, true)

		-- กดเปิดกลับเอง → ล้างธง + ตัวนับ
		meta.deathsSinceProgress = 29
		check("เปิดอัญเชิญกลับได้", CombatService.handleSetSummonEnabled(data, meta, true), true)
		check("  ธงแจ้งเตือนถูกล้าง", data.combatAutoPaused, false)
		check("  ตัวนับรีเซ็ต", meta.deathsSinceProgress, 0)
	end

	print("── 5E-1 ผลแน่นอนเมื่อรันซ้ำ (ไม่สุ่ม) ──")

	do
		local function scenario()
			local data = battleData(4)
			local meta = freshMeta()
			local keyA = Config.makeStackKey("wukong", 10000, {})
			local keyB = Config.makeStackKey("tang", 3000, {})
			data.children[keyA] = 60
			data.children[keyB] = 30
			data.releaseOrder = { keyB, keyA }
			data.damageLevel = 12
			table.insert(data.battleRoster, makeMother(20000, "wukong"))
			for _ = 1, 40 do
				CombatService.tick(data, meta, 0.7)
			end
			local p = data.stageProgress[4]
			return string.format("%.12g|%.12g|%d|%s|%s|%d|%s", p.defendersRemaining, p.wallHpRemaining, data.currency.coins,
				tostring(data.children[keyA]), tostring(data.children[keyB]), #data.battleRoster, layout(meta))
		end
		local first, second = scenario(), scenario()
		check("สองรอบได้ผลเหมือนกันทุกค่า", first, second)
	end

	print("── 5E-1 ป้อมยิงแม่ตัวเดียวในสนาม → แม่ตายถาวร · กำแพงพังแม่ที่เหลือตายหมด (กติกาเดิม) ──")

	do
		local data = battleData(9)
		local meta = freshMeta()
		data.stageProgress[9] = { defendersRemaining = 0, wallHpRemaining = Config.getStageWallHp(9) }
		table.insert(data.battleRoster, makeMother(100, "monkey")) -- เลือด 10 · ป้อมด่าน 9 ยิงนัดละ ~161
		local marched = tickThroughMarch(data, meta)
		check("เดินเต็มทางไปกำแพงด่าน 9 ป้อมยังไม่ยิง", marched.turretShots, 0)
		check("  แม่ยังอยู่ใน roster", #data.battleRoster, 1)
		local r = CombatService.tick(data, meta, 1.5)
		check("แม่ตัวเดียวโดนป้อมยิงตาย", r.mothersFallen, 1)
		check("  roster ว่าง", #data.battleRoster, 0)
	end

	print("── 5E-1 sync สนามรบ (ภาพชั่วคราว + HUD) ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local key = Config.makeStackKey("wukong", 10000, {})
		data.children[key] = 30
		data.releaseOrder = { key }
		table.insert(data.battleRoster, makeMother())
		CombatService.tick(data, meta, 1)
		local battle = CombatService.buildSyncFields(data, false, meta).battle
		check("ฝั่งเรา 6 ช่อง", #battle.our, 6)
		check("ศัตรู 6 ช่อง", #battle.enemies, 6)
		check("ช่อง 6 เป็นแม่", battle.our[6].kind, "mother")
		check("ศัตรูช่อง 1 ตัวใหญ่", battle.enemies[1].kind, "big")
		check("ช่วง = สู้ศัตรู", battle.phase, "enemies")
		local stats = Config.getStageEnemyStats(2)
		check("นับศัตรูที่เหลือได้", battle.bigLeft + battle.smallLeft <= stats.bigCount + stats.smallCount, true)
		check("ป้อมทำงาน", battle.turretActive, true)
		check("เดินทัพจากแท่นไปกึ่งกลาง", `{battle.marchFrom} → {battle.line}`, "pedestal → middle")
		check("  ยังเดินไม่ถึง", battle.marchRemaining > 0 and battle.marchRemaining < battle.marchDuration, true)
		check("  ศัตรูกำลังเดินออกมา (ยังไม่ถึงกึ่งกลาง)", battle.enemiesAtMiddle, false)
		check("  ป้อมไม่ยิง", battle.turretFiring, false)
		tickThroughMarch(data, meta)
		local arrived = CombatService.buildSyncFields(data, false, meta).battle
		check("เดินถึงแล้ว: ศัตรูยืนกึ่งกลาง", `{arrived.enemiesAtMiddle} {arrived.marchRemaining}`, "true 0")
		check("  สู้กึ่งกลางเลน ป้อมยังไม่ยิง", arrived.turretFiring, false)
		near("  กึ่งกลาง = ระหว่างแท่นอัญเชิญกับกำแพง", Config.getBattleMeetX(2),
			(Config.getSummonPedestalCenter().X + Config.getWallX(2)) / 2, 1e-9)
		local noMeta = CombatService.buildSyncFields(data).battle
		check("ไม่มี meta → สนามว่าง ไม่ error", #noMeta.our, 0)
		check("  ยังนับศัตรูจาก HP รวมได้", noMeta.bigLeft + noMeta.smallLeft > 0, true)
		local text = CombatService.describeBattle(data, meta)
		check("debugBattleStatus มีครบ 6 แถว", select(2, string.gsub(text, "ช่อง %d", "")), SLOTS)
	end

	print("── 5E-1 ด่าน 1 (ไม่มีศัตรู) พังทันทีที่เปิดอัญเชิญ แม้ไม่มีทหาร ──")

	do
		local data = freshData()
		data.summonEnabled = true
		local r = CombatService.tick(data, freshMeta(), 1)
		check("ด่าน 1 พัง", r.clearedStage, 1)
		check("  ไม่มีใครลงสนาม", r.unitsReleased, 0)
		check("  ด่านถัดไป = 2", CombatService.getActiveStage(data), 2)
	end

	print("── 5E-1 เครื่องยนต์จริง vs โมเดลสมดุล (ผู้เล่นอ้างอิง · ต่างไม่เกิน 10%) ──")

	do
		for _, stage in { 2, 3, 4 } do
			local engineHours = runReference(stage)
			local modelHours = Config.getReferenceClearHours(stage)
			local diff = engineHours / modelHours - 1
			check(`ด่าน {stage}: เครื่องยนต์ต่างจากโมเดล ≤ 10%`, math.abs(diff) <= 0.10, true)
			print(string.format("   ด่าน %d: เครื่องยนต์ %.3f ชม. · โมเดล %.3f ชม. (%+.1f%%)", stage, engineHours, modelHours, diff * 100))
		end
	end
end
