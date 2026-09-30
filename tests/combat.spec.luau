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

	print("── 3C-1 → 5E-1b แม่ในแถว: เลือด = พลังฐาน · ดาเมจ/วิ = พลังเต็ม × อัตราปล่อย · ตีแค่ตัวหน้าสุด · แม่ 1 = ลูก 10 ──")

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
		check("ไม่มีลูกในคลัง → แม่ 2 ตัวเข้าแถว", marched.unitsReleased, 2)
		check("  ระหว่างเดินทัพไปกึ่งกลางยังไม่มีใครตีใคร", marched.damageDealt, 0)
		check("  เดินถึงกึ่งกลางเลนแล้ว", meta.lineAt, "middle")
		check("  หน้าสุด = แม่ตัวแรกของ roster", meta.line[1].uid, data.battleRoster[1].uid)
		check("  ตัวที่ 2 = แม่ตัวที่สอง", meta.line[2].uid, data.battleRoster[2].uid)
		local secondHp = meta.line[2].hp
		local result = CombatService.tick(data, meta, 2)
		-- ด่าน 2 อัตราปล่อย 1 → ตัวหน้าสุดตี 10 × 1 ต่อวิ × 2 วิ (ตัวที่สองรอคิว ไม่ตี)
		near("ตีแค่ตัวหน้าสุด: 10 × 1 × 2 วินาที", result.damageDealt, 10 * 1 * 2, 1e-6)
		near("ทหารฝ่ายรับลดลงเท่าดาเมจจริง", before - data.stageProgress[2].defendersRemaining, result.damageDealt, 1e-6)
		check("  ตัวที่ 2 ไม่โดนตี (ศัตรูตีแค่ตัวหน้าสุด)", meta.line[2].hp, secondHp)
		check("ด่านยังไม่พัง แม่ยังไม่ตาย → roster ครบ", #data.battleRoster, 2)
		check("ด่านยังไม่พัง → mothersLost = 0", result.mothersLost, 0)
		near("เลือดแม่ = พลังฐาน (ไม่รวมอัปดาเมจ)", meta.line[1].maxHp, 10, 1e-9)

		-- damageLevel ที่ซื้อไว้มีผลกับแม่ด้วย (ตัวคูณเป็นของบัญชี) แต่ไม่เพิ่มเลือด
		data.damageLevel = 8
		CombatService.tick(data, meta, 0.01)
		near("ดาเมจ/วิของแม่คูณ 1.1^damageLevel ด้วย", meta.line[1].dps, Config.computeBattlePower(100, "monkey", {}, 8), 1e-6)
		near("  เลือดยังเท่าเดิม", meta.line[1].maxHp, 10, 1e-9)
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
	-- 5E-1b แถวเดียวแบบ Age of War (แทนสนาม 6 ช่อง + รวมพลของ 5E-1)
	----------------------------------------------------------------------------
	local LINE = Config.Balance.Combat.LINE_LENGTH
	local near = t.near

	-- ด่าน 1..stage-1 พังแล้ว · เปิดอัญเชิญ · ไม่มีแม่ในคอก (ไม่มีกองที่ผลิตเติม)
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

	-- แถวเราเป็นข้อความ: รหัสรายการของแต่ละตัว (หน้าสุดก่อน)
	local function lineIds(meta, names): string
		local parts = {}
		for _, unit in meta.line do
			local id = if unit.kind == "mother" then unit.uid else unit.key
			table.insert(parts, names[id] or "?")
		end
		return table.concat(parts, ",")
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

	print("── 5E-1b รอบวน: 7 รายการ แถวยาว 10 = 1..7,1,2,3 · ตัวหน้าตาย → แถวขยับ + ปล่อยตัวถัดไปต่อท้าย (4) ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local names = {}
		local order = {}
		-- 6 กองลูก + แม่ 1 ตัว (ลำดับ 4) ในรอบวนเดียวกัน
		local charIds = { "monkey", "pig", "horse", "fish", "wukong", "tang" }
		local mother = makeMother()
		table.insert(data.battleRoster, mother)
		local position = 0
		for index, charId in charIds do
			if index == 4 then
				table.insert(order, mother.uid)
				position += 1
				names[mother.uid] = tostring(position)
			end
			local key = Config.makeStackKey(charId, 1000, {})
			data.children[key] = 50
			table.insert(order, key)
			position += 1
			names[key] = tostring(position)
		end
		check("ตั้งลำดับรวม (กอง + uid แม่) ผ่าน", CombatService.handleSetReleaseOrder(data, order, meta), true)
		check("  releaseOrder ที่เซฟ = กองลูกล้วน (ความหมายเดิม · ไม่แตะ schema)", #data.releaseOrder, 6)
		check("  รอบวนใน memory ครบ 7 รายการ", #CombatService.getReleaseCycle(data, meta), 7)
		local r = CombatService.tick(data, meta, 0.01)
		check("ปล่อยทีละตัวตามรอบวนจนแถวยาว 10", r.unitsReleased, LINE)
		check("  แถว = 1,2,3,4(แม่),5,6,7,1,2,3", lineIds(meta, names), "1,2,3,4,5,6,7,1,2,3")
		check("  ลูกในแถวยังนับอยู่ในกอง (หักตอนตาย)", data.children[order[1]], 50)
		check("  ลูกกอง 1 ในแถว 2 ตัว", CombatService.getReservedChildren(meta)[order[1]], 2)
		local oldFront = meta.line[1]
		oldFront.hp = 0
		local r2 = CombatService.tick(data, meta, 0.01)
		check("ตัวหน้าสุดตาย 1 ตัว", r2.childrenLost, 1)
		check("  แถวขยับขึ้น + ตัวถัดไปในรอบวน (4 = แม่ แต่อยู่ในแถวแล้ว → ข้าม) = 5 ต่อท้าย",
			lineIds(meta, names), "2,3,4,5,6,7,1,2,3,5")
		check("  หักจากกองที่ตาย 1 ตัว", data.children[order[1]], 49)
		meta.line[1].hp = 0
		CombatService.tick(data, meta, 0.01)
		check("ตายอีกตัว → ต่อท้ายด้วย 6", lineIds(meta, names), "3,4,5,6,7,1,2,3,5,6")
	end

	print("── 5E-1b ตัวอย่างผู้ใช้: 7 กองลูก · ตัวแรกตาย → 2..7,1,2,3,4 ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local names, order = {}, {}
		for index, charId in { "monkey", "pig", "horse", "fish", "wukong", "tang", "jade_emperor" } do
			local key = Config.makeStackKey(charId, 1000 + index, {})
			data.children[key] = 30
			table.insert(order, key)
			names[key] = tostring(index)
		end
		CombatService.handleSetReleaseOrder(data, order, meta)
		CombatService.tick(data, meta, 0.01)
		check("แถว = 1,2,3,4,5,6,7,1,2,3", lineIds(meta, names), "1,2,3,4,5,6,7,1,2,3")
		meta.line[1].hp = 0
		CombatService.tick(data, meta, 0.01)
		check("ตัวแรกตาย → 2,3,4,5,6,7,1,2,3,4", lineIds(meta, names), "2,3,4,5,6,7,1,2,3,4")
	end

	print("── 5E-1b กองหมดข้าม · แม่ออกครั้งเดียว · ตายแล้วข้าม · ทุกรายการหมด = หยุดปล่อย ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local keyA = Config.makeStackKey("wukong", 10000, {})
		local keyB = Config.makeStackKey("monkey", 800, {})
		data.children[keyA] = 2
		data.children[keyB] = 1
		local m1 = makeMother()
		table.insert(data.battleRoster, m1)
		local names = { [keyA] = "A", [keyB] = "B", [m1.uid] = "M" }
		CombatService.handleSetReleaseOrder(data, { keyA, m1.uid, keyB }, meta)
		local r = CombatService.tick(data, meta, 0.01)
		check("A,M,B,A แล้วหมด (B หมด · M อยู่ในแถวแล้ว) → หยุดปล่อยที่ 4 ตัว", lineIds(meta, names), "A,M,B,A")
		check("  ปล่อยรอบนี้ 4 ตัว", r.unitsReleased, 4)
		check("  พร้อมปล่อยเหลือ 0", CombatService.countAvailable(data, meta), 0)
		-- แม่ตายกลางสนาม → ออกจาก roster ถาวร · ไม่กลับมาในรอบวน
		meta.line[1].hp = 0 -- A ตาย
		CombatService.tick(data, meta, 0.01)
		check("A ตาย → แถวขยับ ไม่มีอะไรต่อท้าย", lineIds(meta, names), "M,B,A")
		local lostBefore = data.stats.mothersLost
		meta.line[1].hp = 0 -- แม่ตาย
		local r2 = CombatService.tick(data, meta, 0.01)
		check("แม่ตายกลางสนาม → mothersFallen 1", r2.mothersFallen, 1)
		check("  ออกจาก roster ถาวร", #data.battleRoster, 0)
		check("  stats.mothersLost +1", data.stats.mothersLost - lostBefore, 1)
		check("  ไม่นับใน mothersLost ของ popup ผ่านด่าน", r2.mothersLost, 0)
		check("  แม่หลุดจากรอบวน", #CombatService.getReleaseCycle(data, meta), 2)
		check("  แถวเหลือ B,A สู้ต่อ", lineIds(meta, names), "B,A")
		-- ผลิตเพิ่ม → ปล่อยต่อเอง (tick ถัดไป)
		data.children[keyB] = 3
		CombatService.tick(data, meta, 0.01)
		check("ผลิตเพิ่มมา → ปล่อยต่อตามรอบวน", lineIds(meta, names), "B,A,B,B")
		check("ข้อความแจ้งแม่ตายกลางสนาม", Config.formatMotherFallenMessage(1, 0),
			`แม่ตายในสนามรบ 1 ตัว (ตายถาวร) · เหลือในสนามรบ 0/{MAX_ROSTER}`)

		-- แม่ที่รอดแล้วกลับมา (ปิดอัญเชิญ) ปล่อยได้อีก — "ออกได้ครั้งเดียว" = ห้ามอยู่ในแถวสองตัวพร้อมกัน
		local data2 = battleData(2)
		local meta2 = freshMeta()
		local m2 = makeMother()
		table.insert(data2.battleRoster, m2)
		CombatService.tick(data2, meta2, 0.01)
		check("แม่ตัวเดียวในรอบวน → เข้าแถวแค่ตัวเดียว", #meta2.line, 1)
		CombatService.handleSetSummonEnabled(data2, meta2, false)
		CombatService.handleSetSummonEnabled(data2, meta2, true)
		CombatService.tick(data2, meta2, 0.01)
		check("  ปิด/เปิดอัญเชิญ → แม่ที่รอดกลับเข้าแถวได้อีก", #meta2.line == 1 and meta2.line[1].uid == m2.uid, true)
	end

	print("── 5E-1b ลำดับรวมผ่าน remote: stack key + uid ปนกัน · ตรวจทั้งชุด · client เก่า (key ล้วน) ยังใช้ได้ ──")

	do
		local keyA = Config.makeStackKey("wukong", 10000, {})
		local keyB = Config.makeStackKey("monkey", 800, {})
		local uid = Config.makeUid(424242, 999)
		local keys, mixed = CombatService.validateReleaseOrder({ keyA, uid, keyB })
		check("ปน key + uid → ผ่าน", keys ~= nil and mixed ~= nil, true)
		check("  keys = กองลูกล้วนตามลำดับ", table.concat(keys :: any, ","), `{keyA},{keyB}`)
		check("  ลำดับรวมครบ", table.concat(mixed :: any, ","), `{keyA},{uid},{keyB}`)
		check("ของแปลก → ปฏิเสธทั้งชุด", (CombatService.validateReleaseOrder({ keyA, "not-a-uid" })), nil)
		check("uid ทศนิยม → ปฏิเสธ", (CombatService.validateReleaseOrder({ "424242-1.5" })), nil)
		check("uid เลขนำหน้า 0 → ปฏิเสธ", (CombatService.validateReleaseOrder({ "0424242-1" })), nil)
		check("ซ้ำ → ปฏิเสธ", (CombatService.validateReleaseOrder({ uid, uid })), nil)
		local tooManyMothers = {}
		for index = 1, MAX_ROSTER + 1 do
			table.insert(tooManyMothers, Config.makeUid(424242, 5000 + index))
		end
		check(`แม่เกิน {MAX_ROSTER} → ปฏิเสธ`, (CombatService.validateReleaseOrder(tooManyMothers)), nil)
		check("ไม่ใช่ table → ปฏิเสธ", (CombatService.validateReleaseOrder("x")), nil)

		-- client เก่าส่ง key ล้วน → แม่ใน roster ต่อท้ายรอบวนเอง
		local data = battleData(2)
		local meta = freshMeta()
		local m = makeMother()
		table.insert(data.battleRoster, m)
		CombatService.handleSetReleaseOrder(data, { keyA, keyB }, meta)
		local cycle = CombatService.getReleaseCycle(data, meta)
		check("key ล้วน → แม่ใน roster ต่อท้าย", `{cycle[1].id},{cycle[2].id},{cycle[3].kind}`, `{keyA},{keyB},mother`)
		-- meta หาย (ออกเกม/เซิร์ฟใหม่) → ลำดับแม่หาย ต่อท้ายตาม roster · กองตาม releaseOrder ที่เซฟ
		CombatService.handleSetReleaseOrder(data, { m.uid, keyB, keyA }, meta)
		check("แม่ขึ้นหน้า (memory)", CombatService.getReleaseCycle(data, meta)[1].id, m.uid)
		local fresh = CombatService.getReleaseCycle(data, freshMeta())
		check("meta ใหม่ → กองตามที่เซฟ (B, A) แล้วแม่ต่อท้าย", `{fresh[1].id},{fresh[2].id},{fresh[3].id}`, `{keyB},{keyA},{m.uid}`)
		check("ไม่มีฟังก์ชันต่อท้ายอัตโนมัติเหลืออยู่", CombatService.reconcileReleaseOrder, nil)
		-- กองที่ไม่ได้ติ๊กไม่ถูกแตะ
		local data3 = battleData(2)
		data3.children[keyA] = 100
		local r3 = CombatService.tick(data3, freshMeta(), 1)
		check("releaseOrder ว่าง + ไม่มีแม่ → ไม่มีใครเข้าแถว แม้คลังมีของ", r3.unitsReleased, 0)
		check("  คลังไม่ลด", data3.children[keyA], 100)
	end

	print("── 5E-1b ตีกันแค่ตัวหน้าสุด ตัวต่อตัว · ตัวอื่นรอคิวไม่โดนตี ──")

	do
		local data = battleData(3)
		local meta = freshMeta()
		local key = Config.makeStackKey("wukong", 10000, {})
		data.children[key] = 40
		data.releaseOrder = { key }
		tickThroughMarch(data, meta)
		local hpBefore = {}
		for index, unit in meta.line do
			hpBefore[index] = unit.hp
		end
		local enemyBefore = meta.enemy.frontIndex
		local defendersBefore = data.stageProgress[3].defendersRemaining
		CombatService.tick(data, meta, 0.2)
		check("ตัวหน้าสุดของเราโดนตี", meta.line[1].hp < hpBefore[1], true)
		local othersUntouched = true
		for index = 2, #meta.line do
			if meta.line[index].hp ~= meta.line[index].maxHp then othersUntouched = false end
		end
		check("  ตัวอื่นในแถวเลือดเต็ม (รอคิว)", othersUntouched, true)
		near("ดาเมจที่ทำ = ตัวหน้าสุดตัวเดียว × เวลา", defendersBefore - data.stageProgress[3].defendersRemaining,
			meta.line[1].dps * 0.2, 1e-6)
		check("  ศัตรูตายเรียงลำดับ (ตัวหน้าสุดเดินหน้าเท่านั้น)", meta.enemy.frontIndex >= enemyBefore, true)
		near("  ดาเมจตัวหน้าสุด = พลังเต็ม × อัตราปล่อย", meta.line[1].dps,
			Config.computeBattlePower(100, "wukong", {}, data.damageLevel) * Config.getReleaseRate(3), 1e-9)
		near("  เลือด = พลังฐาน", meta.line[1].maxHp, Config.computePower(100, "wukong", {}), 1e-9)
	end

	print("── 5E-1b ศัตรูวน เล็ก 5 → ใหญ่ 1 · สร้างจาก HP รวมได้เป๊ะ · เลือด/เงินรวมต่อด่านเท่าเดิม ──")

	do
		local stats = Config.getStageEnemyStats(2)
		local enemy = CombatService.buildEnemyState(2, Config.getStageDefenderHp(2))
		check("เริ่มด่าน: หน้าสุด = ตัวที่ 1 เลือดเต็ม (เล็ก)", `{enemy.frontIndex} {enemy.frontHp == stats.smallHp}`, "1 true")
		check("  จำนวนทั้งด่าน = ใหญ่ + เล็ก", enemy.total, stats.bigCount + stats.smallCount)
		local big, small = CombatService.countEnemies(enemy)
		check("  นับเหลือ = ทั้งด่าน", big == stats.bigCount and small == stats.smallCount, true)
		-- ตีไปแล้ว 5 เล็ก + ครึ่งตัวใหญ่ → หน้าสุด = ตัวที่ 6 (ใหญ่) เลือดเหลือครึ่ง
		local dealt = 5 * stats.smallHp + stats.bigHp / 2
		local mid = CombatService.buildEnemyState(2, Config.getStageDefenderHp(2) - dealt)
		check("ตีไป 5 เล็ก + ครึ่งใหญ่ → หน้าสุด = ตัวที่ 6 (ใหญ่)", `{mid.frontIndex} {Config.getEnemyKindAt(mid.frontIndex)}`, "6 big")
		near("  เลือดตัวหน้าสุดเหลือครึ่ง", mid.frontHp, stats.bigHp / 2, 1e-6)
		local midBig, midSmall = CombatService.countEnemies(mid)
		check("  เหลือ ใหญ่ ทั้งหมด · เล็ก ทั้งหมด − 5", midBig == stats.bigCount and midSmall == stats.smallCount - 5, true)
		check("ด่าน 1 ไม่มีศัตรู", CombatService.countEnemies(CombatService.buildEnemyState(1, 0)), 0)

		-- ตีจริงจนหมด: ศัตรูตายเรียงลำดับ · กำแพงโดนหลังศัตรูหมด · เลือด/เงินรวมตรง · ป้อมยิงเฉพาะตอนถึงกำแพง
		local data = battleData(2)
		local meta = freshMeta()
		local key = Config.makeStackKey("wukong", 250000, {}) -- ลูก 2,500 kg พลัง 1,800 · อึดมาก ไม่ตาย
		data.children[key] = 50
		data.releaseOrder = { key }
		local coinsBefore = data.currency.coins
		local wallFull = Config.getStageWallHp(2)
		local wallTouchedEarly, killed, damage = false, 0, 0
		local shotsEnemy, shotsWall, shotsWhileMarching = 0, 0, 0
		local wallHitWhileMarching, sawMiddleToWall, kindsOk = false, false, true
		local lastFront = 1
		for _ = 1, 400 do
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
				shotsWhileMarching += r.turretShots
				if p.wallHpRemaining < wallBefore then
					wallHitWhileMarching = true
				end
			end
			if meta.marchFrom == "middle" and meta.lineAt == "wall" then
				sawMiddleToWall = true
			end
			if meta.enemy and meta.enemy.frontIndex < lastFront then
				kindsOk = false -- ตายเรียงลำดับเท่านั้น ห้ามถอยหลัง
			end
			if meta.enemy then
				lastFront = meta.enemy.frontIndex
			end
			if r.stageCleared then
				break
			end
		end
		check("ด่าน 2 พัง", CombatService.getActiveStage(data), 3)
		check("กำแพงไม่โดนเลยตอนศัตรูยังเหลือ", wallTouchedEarly, false)
		check("ศัตรูตายครบทั้งด่าน (ใหญ่ + เล็ก)", killed, stats.bigCount + stats.smallCount)
		check("  ตายเรียงลำดับ (ตัวหน้าสุดไม่ถอยหลัง)", kindsOk, true)
		near("HP ที่ลดรวม = HP ทหารฝ่ายรับ + กำแพง", damage, Config.getStageTotalHp(2), 1e-6)
		check("เงินรวมทั้งด่าน = เงินกวาดทหารเดิม (±1 จากเศษ)", math.abs((data.currency.coins - coinsBefore) - Config.getStageDefenderRewardTotal(2)) <= 1, true)
		check("ป้อมไม่ยิงช่วงสู้ศัตรู (สู้กันกึ่งกลางเลน นอกระยะป้อม)", shotsEnemy, 0)
		check("ศัตรูหมด → เดินจากกึ่งกลางไปกำแพง", sawMiddleToWall, true)
		check("  ระหว่างเดินไปกำแพง: ป้อมไม่ยิง", shotsWhileMarching, 0)
		check("  ระหว่างเดินไปกำแพง: กำแพงไม่โดน", wallHitWhileMarching, false)
		check("ป้อมยิงช่วงตีกำแพง (เดินถึงแล้ว)", shotsWall > 0, true)
		check("ลูกที่รอดกลับกองครบ (ไม่มีใครตาย)", data.children[key], 50)
		check("แถวว่างหลังด่านพัง", #meta.line, 0)
		check("แถวศัตรูถูกล้างรอด่านใหม่", meta.enemy, nil)
	end

	print("── 5E-1b ป้อมยิงตัวหน้าสุด 1 นัด/วิ หลังเดินถึงกำแพง · debugTurret(false) ไม่ยิง ──")

	do
		local key = Config.makeStackKey("wukong", 250000, {})
		local data2 = battleData(3)
		local meta2 = freshMeta()
		data2.stageProgress[3].defendersRemaining = 0 -- ศัตรูหมดแล้ว → ปล่อยแล้วเดินเต็มทางไปกำแพง
		data2.children[key] = 50
		data2.releaseOrder = { key }
		local marched = tickThroughMarch(data2, meta2)
		check("ศัตรูหมดแล้ว → เดินจากแท่นเต็มทาง (2 เท่าของครึ่งทาง)", meta2.marchDuration, Config.getArmyMarchSeconds(3) * 2)
		check("  เดินจากแท่นอัญเชิญ", meta2.marchFrom, "pedestal")
		check("  ระหว่างเดิน ป้อมไม่ยิง · กำแพงไม่โดน", `{marched.turretShots} {marched.damageDealt}`, "0 0")
		check("  ถึงกำแพงแล้ว", meta2.lineAt, "wall")
		local secondHp = meta2.line[2].hp
		local r1 = CombatService.tick(data2, meta2, 2)
		check("ป้อมยิง 1 นัด/วิ (นับจากเดินถึง)", r1.turretShots, 2)
		check("  เป้า = ตัวหน้าสุด", meta2.lastTurretTarget, 1)
		check("  ตัวที่ 2 ไม่โดน", meta2.line[2].hp, secondHp)
		CombatService.setTurretEnabled(false)
		local r2 = CombatService.tick(data2, meta2, 3)
		check("debugTurret(false) → ป้อมไม่ยิง", r2.turretShots, 0)
		CombatService.setTurretEnabled(true)
		check("เปิดกลับแล้ว", CombatService.isTurretEnabled(), true)

		-- ป้อมด่าน 9 ยิงแม่ตัวเดียวตาย (ตายถาวร)
		local data = battleData(9)
		local meta = freshMeta()
		data.stageProgress[9] = { defendersRemaining = 0, wallHpRemaining = Config.getStageWallHp(9) }
		table.insert(data.battleRoster, makeMother(100, "monkey")) -- เลือด 10 · ป้อมด่าน 9 ยิงนัดละ ~161
		local marched9 = tickThroughMarch(data, meta)
		check("เดินเต็มทางไปกำแพงด่าน 9 ป้อมยังไม่ยิง", marched9.turretShots, 0)
		check("  แม่ยังอยู่ใน roster", #data.battleRoster, 1)
		local r = CombatService.tick(data, meta, 1.5)
		check("แม่ตัวเดียวโดนป้อมยิงตาย", r.mothersFallen, 1)
		check("  roster ว่าง", #data.battleRoster, 0)
	end

	print("── 5E-1b ศัตรูบาดเจ็บคงสถานะ: ปิดอัญเชิญ/แถวหมด/ออกเกม ไม่รีเซ็ต HP ──")

	do
		local data = battleData(3)
		local meta = freshMeta()
		local key = Config.makeStackKey("wukong", 10000, {})
		data.children[key] = 40
		data.releaseOrder = { key }
		tickThroughMarch(data, meta)
		CombatService.tick(data, meta, 0.3)
		local front, frontHp = meta.enemy.frontIndex, meta.enemy.frontHp
		local maxHp = Config.getEnemyKindAt(front) == "big" and Config.getStageEnemyStats(3).bigHp or Config.getStageEnemyStats(3).smallHp
		check("ศัตรูหน้าสุดบาดเจ็บ", frontHp < maxHp, true)
		local childrenBefore = data.children[key]
		local remaining = data.stageProgress[3].defendersRemaining
		CombatService.handleSetSummonEnabled(data, meta, false)
		check("ปิดอัญเชิญ → แถวเราว่างทันที", #meta.line, 0)
		check("  ลูกที่รอดกลับกอง (กองไม่ลด)", data.children[key], childrenBefore)
		CombatService.tick(data, meta, 5)
		check("  ศัตรูบาดเจ็บค้างไว้ (ตัวเดิม เลือดเดิม)", meta.enemy.frontIndex == front and meta.enemy.frontHp == frontHp, true)
		check("  HP ทหารฝ่ายรับที่เซฟไม่เปลี่ยน", data.stageProgress[3].defendersRemaining, remaining)
		-- ออกเกม (meta ใหม่) → คำนวณตัวหน้าสุด + เลือดจาก HP รวมได้เป๊ะ
		local rejoin = CombatService.buildEnemyState(3, remaining)
		check("เข้าเกมใหม่ → ตัวหน้าสุดเดิม", rejoin.frontIndex, front)
		near("  เลือดตัวหน้าสุดเท่าเดิม", rejoin.frontHp, frontHp, maxHp * 1e-6)
		CombatService.handleSetSummonEnabled(data, meta, true)
		CombatService.tick(data, meta, 0.1)
		check("เปิดใหม่ → เดินทัพจากแท่นใหม่ · ศัตรูยืนกึ่งกลางรอ", meta.marchFrom == "pedestal" and meta.enemy.atMiddle, true)
	end

	print("── 5E-1b auto-pause: ตายติดกัน 30 ตัวโดยที่ HP ฝั่งตรงข้ามไม่ลดเลย → หยุดปล่อย ──")

	do
		local threshold = Config.Balance.Combat.AUTO_PAUSE_AFTER_DEATHS
		local realDps = Config.getUnitDps
		Config.getUnitDps = function()
			return 0
		end
		local data = battleData(2)
		local meta = freshMeta()
		local key = Config.makeStackKey("monkey", 100, {}) -- ลูก 1 kg เลือด 1 → ตายเร็ว
		data.children[key] = 200
		data.releaseOrder = { key }
		local paused, deaths = false, 0
		for _ = 1, 120 do
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
		check("  แถวว่าง (ตัวที่รอดกลับกอง)", #meta.line, 0)
		check("  กองเหลือ = 200 − ตัวที่ตาย", data.children[key], 200 - threshold)

		-- ตายเยอะแต่ HP ศัตรูยังลด = คืบหน้า → ไม่หยุด
		local data2 = battleData(5)
		local meta2 = freshMeta()
		data2.children[key] = 400
		data2.releaseOrder = { key }
		local anyPause, deaths2 = false, 0
		for _ = 1, 40 do
			local r = CombatService.tick(data2, meta2, 1)
			deaths2 += r.childrenLost
			anyPause = anyPause or r.autoPaused
		end
		check("ตายเกิน 30 ตัวแต่ HP ศัตรูลดตลอด → ไม่หยุด", deaths2 > threshold and not anyPause, true)
		check("  ยังเปิดอัญเชิญ", data2.summonEnabled, true)

		meta.deathsSinceProgress = 29
		check("เปิดอัญเชิญกลับได้", CombatService.handleSetSummonEnabled(data, meta, true), true)
		check("  ธงแจ้งเตือนถูกล้าง", data.combatAutoPaused, false)
		check("  ตัวนับรีเซ็ต", meta.deathsSinceProgress, 0)
	end

	print("── 5E-1b ผลแน่นอน: รันซ้ำเหมือนเดิม · tick ใหญ่ = tick เล็กรวมกัน (รวมทางลัดทีละรอบวน) ──")

	do
		local function scenario(step: number, steps: number)
			local data = battleData(4)
			local meta = freshMeta()
			local keyA = Config.makeStackKey("wukong", 10000, {})
			local keyB = Config.makeStackKey("tang", 3000, {})
			data.children[keyA] = 60
			data.children[keyB] = 30
			local m = makeMother(20000, "wukong")
			table.insert(data.battleRoster, m)
			CombatService.handleSetReleaseOrder(data, { keyB, m.uid, keyA }, meta)
			data.damageLevel = 12
			for _ = 1, steps do
				CombatService.tick(data, meta, step)
			end
			local p = data.stageProgress[4]
			return string.format("%.9g|%.9g|%s|%s|%d", p.defendersRemaining, p.wallHpRemaining,
				tostring(data.children[keyA]), tostring(data.children[keyB]), #data.battleRoster)
		end
		check("สองรอบได้ผลเหมือนกันทุกค่า", scenario(0.7, 40), scenario(0.7, 40))
		-- ผู้เล่นแรงมาก (ฆ่าหลายรอบวนต่อ tick) → ทางลัดทีละรอบวนต้องได้ผลเท่าวนทีละตัว
		local function strong(step: number, steps: number): (number, number)
			local data = battleData(2)
			local meta = freshMeta()
			local key = Config.makeStackKey("wukong", 1000000, {}) -- ลูก 10,000 kg คลาส A → ฆ่าหลายสิบตัวต่อวิ
			data.children[key] = 20
			data.releaseOrder = { key }
			data.damageLevel = 16
			local killed = 0
			for _ = 1, steps do
				killed += CombatService.tick(data, meta, step).enemiesKilled
			end
			return data.stageProgress[2].defendersRemaining + data.stageProgress[2].wallHpRemaining, killed
		end
		local bigHp, bigKilled = strong(5, 2)
		local smallHp, smallKilled = strong(0.05, 200)
		near("tick 5 วิ × 2 = tick 0.05 วิ × 200 (HP ที่เหลือ)", bigHp, smallHp, math.max(1, Config.getStageTotalHp(2)) * 1e-6)
		check("  ฆ่าเท่ากัน", bigKilled, smallKilled)
		check("  ฆ่าได้หลายรอบวนจริง (ทดสอบทางลัด)", bigKilled > 12, true)
	end

	print("── 5E-1b แม่ในแถว: ด่านพัง = แม่ที่เหลือใน roster ตายหมด (กติกาเดิม) ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		data.stageProgress[2] = { defendersRemaining = 0, wallHpRemaining = 1 }
		table.insert(data.battleRoster, makeMother())
		table.insert(data.battleRoster, makeMother())
		local r = tickUntilCleared(data, meta)
		check("ด่านพัง → แม่ใน roster ตายทั้ง 2", r.mothersLost, 2)
		check("  roster ว่าง", #data.battleRoster, 0)
	end

	print("── 5E-1b sync สนามรบ (ภาพชั่วคราว + HUD) ──")

	do
		local data = battleData(2)
		local meta = freshMeta()
		local key = Config.makeStackKey("wukong", 10000, {})
		data.children[key] = 30
		data.releaseOrder = { key }
		local m = makeMother()
		table.insert(data.battleRoster, m)
		CombatService.tick(data, meta, 1)
		local fields = CombatService.buildSyncFields(data, false, meta)
		local battle = fields.battle
		check("ฝั่งเรา 10 ตัว (แถวเต็ม)", #battle.our, LINE)
		check("  ตัวหน้าสุด pos 1 มี id", battle.our[1].pos == 1 and type(battle.our[1].id) == "number", true)
		check("ศัตรูแสดง 10 ตัวแรกของแถว", #battle.enemies, LINE)
		check("  ศัตรูรอบวน: 1–5 เล็ก · 6 ใหญ่", `{battle.enemies[5].kind} {battle.enemies[6].kind}`, "small big")
		check("  id ศัตรู = ตัวที่เท่าไรของด่าน", battle.enemies[1].id, meta.enemy.frontIndex)
		check("ความยาวแถวส่งไปด้วย", battle.lineLength, LINE)
		check("ไม่มีรวมพลแล้ว", battle.gathering == nil and battle.gatherTarget == nil, true)
		check("ช่วง = สู้ศัตรู", battle.phase, "enemies")
		check("ป้อมทำงาน", battle.turretActive, true)
		check("เดินทัพจากแท่นไปกึ่งกลาง", `{battle.marchFrom} → {battle.line}`, "pedestal → middle")
		check("  ยังเดินไม่ถึง", battle.marchRemaining > 0 and battle.marchRemaining < battle.marchDuration, true)
		check("  ศัตรูกำลังเดินออกมา (ยังไม่ถึงกึ่งกลาง)", battle.enemiesAtMiddle, false)
		check("  ป้อมไม่ยิง", battle.turretFiring, false)
		check("รอบวนส่งไปด้วย (กอง + แม่)", `{#fields.releaseCycle} {fields.releaseCycle[2].kind}`, "2 mother")
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
		check("debugBattleStatus มีแถวเรา · แถวศัตรู · รอบวน",
			string.find(text, "แถวเรา (10/10", 1, true) ~= nil
				and string.find(text, "แถวศัตรู (หน้าสุด = ตัวที่", 1, true) ~= nil
				and string.find(text, "รอบวน (▶ = ตัวถัดไป)", 1, true) ~= nil, true)
		check("  บอกตำแหน่งถัดไปในรอบวน", string.find(text, "▶", 1, true) ~= nil, true)
	end

	print("── 5E-1b ด่าน 1 (ไม่มีศัตรู) พังทันทีที่เปิดอัญเชิญ แม้ไม่มีทหาร ──")

	do
		local data = freshData()
		data.summonEnabled = true
		local r = CombatService.tick(data, freshMeta(), 1)
		check("ด่าน 1 พัง", r.clearedStage, 1)
		check("  ไม่มีใครเข้าแถว", r.unitsReleased, 0)
		check("  ด่านถัดไป = 2", CombatService.getActiveStage(data), 2)
	end

	print("── 5E-1b เครื่องยนต์จริง vs โมเดลสมดุล (ผู้เล่นอ้างอิง · ต่างไม่เกิน 10%) ──")

	do
		for _, stage in { 2, 3, 4, 5 } do
			local engineHours = runReference(stage)
			local modelHours = Config.getReferenceClearHours(stage)
			local diff = engineHours / modelHours - 1
			check(`ด่าน {stage}: เครื่องยนต์ต่างจากโมเดล ≤ 10%`, math.abs(diff) <= 0.10, true)
			print(string.format("   ด่าน %d: เครื่องยนต์ %.3f ชม. · โมเดล %.3f ชม. (%+.1f%%)", stage, engineHours, modelHours, diff * 100))
		end
	end
end
