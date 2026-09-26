--!nocheck
-- egg-army-game :: ชุดเทสต์ของ ProductionService (Phase 2B-1)
--
-- ⚠️ ทำไมชุดนี้ถึงจำเป็น: การผลิตคำนวณจาก timestamp ไม่ใช่ loop นับสด
-- ถ้าสูตร floor/cap/เลื่อน lastProducedAt พลาดแม้นิดเดียว ผู้เล่นจะไม่ได้ของที่ควรได้
-- (เศษเวลาหาย) หรือฟาร์มได้ฟรีเกินจริง (เวลาเดิมถูกนับซ้ำ) — สองอย่างนี้มองไม่เห็นด้วยตา
-- จนกว่าจะปล่อยจริงหลายชั่วโมง จึงต้องมีเทสต์ที่เร่งเวลาด้วยนาฬิกาปลอมแทน
--
-- ทุกอย่างที่นี่รันด้วย luau CLI ไม่ต้องเปิด Studio (ProductionService.injectForTests)

local PlayerData = require("../src/shared/PlayerData")
local ProductionService = require("../src/server/ProductionService")

return function(t, Config)
	local check = t.check

	-- แม่ 100kg คลาส A (wukong) ไม่มีสถานะ — เลขกลม ๆ คำนวณมือเทียบง่าย
	local function makeMother(overrides: { [string]: any }?)
		local mother = {
			uid = "1-1",
			charId = "wukong",
			weight = 100,
			statuses = {},
			obtainedAt = 0,
			locked = false,
			lastProducedAt = 0,
		}
		if overrides then
			for k, v in overrides do
				mother[k] = v
			end
		end
		return mother
	end

	local function freshData()
		local data = PlayerData.createNew()
		data.wallProgress = 1 -- byStage = STAGE_MULTIPLIER^0 = 1 คำนวณมือง่าย
		return data
	end

	----------------------------------------------------------------------------
	-- อัตราออนไลน์: แม่ 100kg ต้องผลิตตามสูตรที่ยืนยันจาก Config ตรง ๆ
	----------------------------------------------------------------------------
	-- Config.getProductionPerMinute(100, {}, 0, true)
	--   = ONLINE_PER_MINUTE(1) × (100/100)^0.25 × getProductionMultiplier(0)(=RATE^0=1) = 1 ตัว/นาที
	-- Config.getCoinsPerMinute(100, 1, {})
	--   = BASE_PER_MINUTE(1) × (100/100)^0.5 × STAGE_MULTIPLIER^0(=1) = 1 เหรียญ/นาที
	print("── อัตราออนไลน์: แม่ 100kg = 1 ตัว/นาที และ 1 เหรียญ/นาที ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		local startCoins = data.currency.coins -- ผู้เล่นใหม่เริ่มด้วย Config.Balance.NewPlayer.coins ไม่ใช่ 0
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		clock += 300 -- 5 นาที
		local children, coins, hitCap = ProductionService.settleMother(data, mother, true)

		check("5 นาที ผ่านไป ได้ลูก 5 ตัว (floor(300×1/60))", children, 5)
		check("5 นาที ผ่านไป ได้เหรียญ 5 (floor(300×1/60))", coins, 5)
		check("ไม่ชนเพดานคลัง", hitCap, false)

		local key = Config.makeStackKey("wukong", 100, {})
		check("ลูกเข้ากอง stack key ที่ถูกต้อง", data.children[key], 5)
		check("เงินเข้า currency.coins (บวกจากยอดเริ่มต้น)", data.currency.coins - startCoins, 5)
		-- ⚠️ จุดสำคัญ: lastProducedAt ต้องเลื่อนไปเท่าที่ "ใช้จริง" (5×60=300 วิ) ไม่ใช่ nowValue เฉย ๆ
		-- กรณีนี้ elapsed พอดีหารลงตัว เลยเท่ากับ nowValue — ดูเคสเศษเวลาที่เทสต์แยกด้านล่าง
		check("lastProducedAt เลื่อนไปเท่าเวลาที่ใช้จริง", mother.lastProducedAt, clock)
		check("stats.childrenProduced สะสมด้วย", data.stats.childrenProduced, 5)
		check("stats.totalCoinsEarned สะสมด้วย", data.stats.totalCoinsEarned, 5)
	end

	----------------------------------------------------------------------------
	-- เศษเวลาที่ยังไม่ครบ 1 ตัว ต้องไม่ถูกทิ้ง (เก็บไว้ใน lastProducedAt)
	----------------------------------------------------------------------------
	print("── เศษเวลาไม่ครบ 1 ตัว ต้องไม่หาย ต้องเก็บไว้ใน lastProducedAt ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		-- 65 วิ ที่ 1/60 ตัว/วิ = 1.083 ตัว → floor = 1 ตัว ใช้เวลาจริงแค่ 60 วิ เหลือเศษ 5 วิ
		clock += 65
		local children = ProductionService.settleMother(data, mother, true)
		check("65 วิ ได้ลูก 1 ตัว (floor(65/60))", children, 1)
		check("เศษ 5 วิที่ยังไม่ครบ 1 ตัว ถูกเก็บไว้ ไม่ถูกทิ้ง", mother.lastProducedAt, clock - 5)

		-- อีก 55 วิถัดมา รวมกับเศษที่ค้างไว้ (5+55=60 วิ) ต้องได้อีก 1 ตัวพอดี
		clock += 55
		local children2 = ProductionService.settleMother(data, mother, true)
		check("รวมเศษเดิมแล้วครบ 60 วิ ได้อีก 1 ตัว", children2, 1)
		check("รวมสองรอบได้ 2 ตัว ไม่มีเศษหาย", data.children[Config.makeStackKey("wukong", 100, {})], 2)
	end

	----------------------------------------------------------------------------
	-- แม่ในกระเป๋าไม่ผลิตอะไรเลย
	----------------------------------------------------------------------------
	print("── แม่ในกระเป๋า (ไม่มี lastProducedAt) ไม่ผลิตอะไรเลย ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		-- ⚠️ ตั้งเป็น nil หลังสร้างตาราง ไม่ใช่ผ่าน overrides = { lastProducedAt = nil } —
		-- table constructor ที่ค่าเป็น nil จะไม่สร้าง key นั้นขึ้นมาเลย (key จะไม่มีอยู่ในตาราง)
		-- ทำให้ for-in ของ makeMother มองไม่เห็นและปล่อยค่า default เดิม (0) ไว้เฉย ๆ
		local bagMother = makeMother()
		bagMother.lastProducedAt = nil
		table.insert(data.mothersInBag, bagMother)

		clock += 10000
		local children, coins, hitCap = ProductionService.settleMother(data, bagMother, true)
		check("แม่ในกระเป๋า: ไม่ได้ลูกเลย", children, 0)
		check("แม่ในกระเป๋า: ไม่ได้เงินเลย", coins, 0)
		check("แม่ในกระเป๋า: ไม่ชนเพดาน (ไม่ได้ทำอะไรเลย)", hitCap, false)
		check("settleAllInPen ไม่แตะแม่ในกระเป๋า (อยู่คนละอาเรย์)", #data.mothersInPen, 0)
	end

	----------------------------------------------------------------------------
	-- ผลิตหลายรอบ → รวมกอง stack เดียว ไม่แยกกอง
	----------------------------------------------------------------------------
	print("── ผลิตหลายรอบด้วย tick ถี่ ๆ → รวมกองเดียว ไม่แยกกอง ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		-- จำลอง tick ทุก 5 วิ (Production.TICK_INTERVAL) ต่อเนื่อง 12 ครั้ง = 60 วิ
		for _ = 1, 12 do
			clock += 5
			ProductionService.settleAllInPen(data, true)
		end

		local key = Config.makeStackKey("wukong", 100, {})
		local stackCount = 0
		for _ in data.children do
			stackCount += 1
		end
		check("มีกองเดียวเท่านั้น ไม่แยกกองตาม tick", stackCount, 1)
		check("60 วิ สะสมจาก tick ถี่ ๆ ได้ 1 ตัวพอดี ไม่หายจากการ floor ทุกรอบ", data.children[key], 1)
	end

	----------------------------------------------------------------------------
	-- ออฟไลน์ gap สั้น (< 8 ชม.) — ใช้ OFFLINE_RATE_RATIO
	----------------------------------------------------------------------------
	print("── ออฟไลน์ 1 ชม. (< เพดาน 8 ชม.) คิดด้วยอัตราออฟไลน์ ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		clock += 3600 -- 1 ชม.
		local children, coins = ProductionService.settleMother(data, mother, false)

		-- อัตราออฟไลน์ = อัตราออนไลน์ × OFFLINE_RATE_RATIO(0.1) = 0.1 ตัว/นาที = 0.1/60 ตัว/วิ
		-- floor(3600 × 0.1/60) = floor(6) = 6 ตัว/เหรียญ
		check("ออฟไลน์ 1 ชม. ได้ลูก 6 ตัว (อัตรา ×0.1)", children, 6)
		check("ออฟไลน์ 1 ชม. ได้เหรียญ 6 (อัตรา ×0.1)", coins, 6)
	end

	----------------------------------------------------------------------------
	-- ออฟไลน์เกินเพดาน → คิดแค่ 8 ชม. ไม่เกิน
	----------------------------------------------------------------------------
	print("── ออฟไลน์เกินเพดาน (30 ชม.) → คิดแค่ 8 ชม. ไม่เกิน ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		clock += 30 * 3600 -- หายไป 30 ชม. เกินเพดาน 8 ชม. (28,800 วิ) ไปมาก
		local children, coins = ProductionService.settleMother(data, mother, false)

		-- floor(28800 × 0.1/60) = floor(48) = 48 — ตรงกับตัวอย่างใน docs/data-schema.md
		-- ("48 ตัวต่อแม่ 100kg ที่เพดานออฟไลน์เต็ม 8 ชม.")
		check("คิดแค่ 8 ชม. ได้ลูก 48 ตัว ไม่ใช่ตามเวลาที่หายไปจริง 30 ชม.", children, 48)
		check("คิดแค่ 8 ชม. ได้เหรียญ 48 เท่ากัน", coins, 48)
		check(
			"lastProducedAt เลื่อนมาจากขอบเพดาน ไม่ใช่จาก lastProducedAt เดิมที่เก่ากว่านั้น",
			mother.lastProducedAt,
			clock - Config.Balance.Production.OFFLINE_CAP_SECONDS + 48 * 600
		)
	end

	----------------------------------------------------------------------------
	-- ย้ายแม่ออกจากคอกกลางคัน → settle ผลผลิตค้างก่อนเสมอ ไม่หาย
	----------------------------------------------------------------------------
	print("── ย้ายแม่ออกจากคอกกลางคัน: settle ก่อนเคลียร์ lastProducedAt ไม่หายของ ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		local startCoins = data.currency.coins
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		clock += 120 -- 2 นาที ในคอก
		-- นี่คือสิ่งที่ EggService.moveMother ทำก่อนล้าง lastProducedAt เป็น nil เสมอ
		local children, coins = ProductionService.settleMother(data, mother, true)
		check("ก่อนย้ายออก: ได้เครดิตของ 2 นาทีที่ผลิตในคอกครบ", children, 2)
		check("ก่อนย้ายออก: ได้เงินของ 2 นาทีครบ", coins, 2)

		-- ย้ายเข้ากระเป๋า (จำลองสิ่งที่ moveMother ทำหลัง settle)
		mother.lastProducedAt = nil
		table.remove(data.mothersInPen, 1)
		table.insert(data.mothersInBag, mother)

		-- เวลาผ่านไปอีกมากตอนอยู่ในกระเป๋า ต้องไม่ได้ของเพิ่มอีกเลย
		clock += 100000
		local childrenAfter, coinsAfter = ProductionService.settleMother(data, mother, true)
		check("อยู่ในกระเป๋าแล้ว ไม่ได้ลูกเพิ่มอีก", childrenAfter, 0)
		check("อยู่ในกระเป๋าแล้ว ไม่ได้เงินเพิ่มอีก", coinsAfter, 0)

		local key = Config.makeStackKey("wukong", 100, {})
		check("รวมแล้วมีแค่ของช่วงที่อยู่ในคอกจริง ไม่มากไม่น้อยไปกว่านั้น", data.children[key], 2)
		check("เงินรวมตรงกับช่วงที่อยู่ในคอกจริงเท่านั้น (บวกจากยอดเริ่มต้น)", data.currency.coins - startCoins, 2)
	end

	----------------------------------------------------------------------------
	-- เงินเข้า currency.coins เท่านั้น ไม่กระทบ gems
	----------------------------------------------------------------------------
	print("── เงินเข้า currency.coins เท่านั้น ไม่แตะ gems ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		check("gems เริ่มต้นตาม Config.Balance.NewPlayer", data.currency.gems, Config.Balance.NewPlayer.gems)
		local startCoins = data.currency.coins

		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		clock += 600 -- 10 นาที → 10 เหรียญ
		ProductionService.settleMother(data, mother, true)

		check("coins เพิ่มขึ้นตามที่ผลิตได้ (บวกจากยอดเริ่มต้น)", data.currency.coins - startCoins, 10)
		check("gems ไม่ถูกแตะเลย", data.currency.gems, Config.Balance.NewPlayer.gems)
	end

	----------------------------------------------------------------------------
	-- 🔴 จำลอง exploit: settle ซ้ำโดยไม่มีเวลาผ่านไปจริง ต้องไม่ได้ของฟรี
	----------------------------------------------------------------------------
	-- ⚠️ เฟสนี้ไม่มี RemoteEvent ให้ client ส่ง "จำนวนที่ผลิตได้" หรือ "จำนวนเงิน" เข้ามาเอง
	-- เลย — ตัวเลขทั้งหมดคำนวณจาก mother.lastProducedAt ฝั่ง server เท่านั้น
	-- การจำลอง exploit ที่ตรงกับดีไซน์นี้คือ: ผู้เล่นสแปมคำขอ (เช่น ขอย้ายแม่/ขอ sync)
	-- ให้ settle ทำงานถี่ ๆ โดยเวลาจริงไม่ได้เดินเลย → ต้องได้ (0, 0) ทุกครั้งที่ซ้ำ
	-- ไม่ใช่ได้ผลผลิตเพิ่มจากการเรียกซ้ำ (ซึ่งจะเป็นช่องโหว่ให้ฟาร์มไม่จำกัด)
	print("── exploit: สแปม settle โดยเวลาไม่ขยับ ต้องไม่ได้ของเพิ่ม ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		local startCoins = data.currency.coins
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		clock += 300
		local firstChildren, firstCoins = ProductionService.settleMother(data, mother, true)
		check("รอบแรกได้ของตามเวลาที่ผ่านไปจริง", firstChildren, 5)

		-- สแปมเรียกซ้ำ 20 ครั้งติด ๆ กัน โดยนาฬิกาปลอมไม่ขยับเลย (จำลองคำขอรัว ๆ ในวินาทีเดียว)
		local totalExtraChildren, totalExtraCoins = 0, 0
		for _ = 1, 20 do
			local c, coinsGot = ProductionService.settleMother(data, mother, true)
			totalExtraChildren += c
			totalExtraCoins += coinsGot
		end

		check("สแปม 20 ครั้งโดยเวลาไม่ขยับ ไม่ได้ลูกเพิ่มเลยสักตัว", totalExtraChildren, 0)
		check("สแปม 20 ครั้งโดยเวลาไม่ขยับ ไม่ได้เงินเพิ่มเลย", totalExtraCoins, 0)

		local key = Config.makeStackKey("wukong", 100, {})
		check("ยอดสะสมสุดท้ายตรงกับที่เวลาจริงอนุญาตเท่านั้น", data.children[key], firstChildren)
		check(
			"เงินสะสมสุดท้ายตรงกับที่เวลาจริงอนุญาตเท่านั้น (บวกจากยอดเริ่มต้น)",
			data.currency.coins - startCoins,
			firstCoins
		)
	end

	----------------------------------------------------------------------------
	-- เพดานคลังต่อกอง (STACK_CAP) — ชนแล้วต้องหยุดที่เพดานพอดี ไม่ทะลุ
	----------------------------------------------------------------------------
	print("── ชนเพดานคลัง 500 ตัว: หยุดพอดีที่เพดาน ไม่ทะลุ ──")

	do
		local clock = 1000
		ProductionService.injectForTests({ now = function() return clock end })

		local data = freshData()
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)

		local key = Config.makeStackKey("wukong", 100, {})
		data.children[key] = Config.getStackCap() - 1 -- เหลือที่ว่าง 1 ตัว

		clock += 600 -- ปกติจะได้ 10 ตัว แต่ที่ว่างเหลือแค่ 1
		local children, coins, hitCap = ProductionService.settleMother(data, mother, true)

		check("ได้แค่เท่าที่ว่างเหลือ ไม่ทะลุเพดาน", children, 1)
		check("แจ้งว่าชนเพดานคลัง", hitCap, true)
		check("กองไม่เกินเพดานที่ตั้งไว้", data.children[key], Config.getStackCap())
		-- ⚠️ ผลข้างเคียงที่ยอมรับแล้ว (คอมเมนต์ใน ProductionService): เงินรอบนี้คำนวณจาก
		-- timeUsed ที่สั้นลงตามลูกที่ผลิตได้จริง (1 ตัว = 60 วิ) ไม่ใช่ elapsed เต็ม 600 วิ
		check("เงินก็ถูกตัดตาม timeUsed ที่สั้นลงด้วย (ใช้ timestamp เดียวกัน)", coins, 1)
	end

	----------------------------------------------------------------------------
	-- log "คลังเต็ม" — พิมพ์แค่รอบที่เพิ่งเต็ม ไม่ใช่ทุกรอบที่ยังเต็มค้าง
	----------------------------------------------------------------------------
	print("── log คลังเต็ม: พิมพ์ครั้งเดียวตอนเพิ่งเต็ม · เต็มค้างไม่พิมพ์ซ้ำ · ลดแล้วเต็มใหม่พิมพ์ใหม่ ──")

	do
		local clock = 1000
		local logs: { string } = {}
		ProductionService.injectForTests({
			now = function() return clock end,
			log = function(message: string) table.insert(logs, message) end,
		})

		local data = freshData()
		local mother = makeMother({ lastProducedAt = clock })
		table.insert(data.mothersInPen, mother)
		local key = Config.makeStackKey("wukong", 100, {})
		local cap = Config.getStackCap()

		data.children[key] = cap - 1
		clock += 600
		ProductionService.settleMother(data, mother, true)
		check("เพิ่งเต็ม (ผลิตเกินที่ว่าง) → พิมพ์ 1 ครั้ง", #logs, 1)

		for _ = 1, 5 do
			clock += 600
			local _, _, hitCap = ProductionService.settleMother(data, mother, true)
			check("เต็มค้าง: hitCap ยังเป็น true เหมือนเดิม", hitCap, true)
		end
		check("เต็มค้างอีก 5 รอบ → ไม่พิมพ์ซ้ำ (ยัง 1)", #logs, 1)

		data.children[key] = cap - 3 -- ปล่อยลูกออกไปรบจนกองลด
		clock += 600
		ProductionService.settleMother(data, mother, true)
		check("กองลดแล้วเต็มใหม่ → พิมพ์ใหม่ (2)", #logs, 2)

		data.children[key] = cap - 5
		mother.lastProducedAt = clock
		clock += 300 -- ได้ 5 ตัวพอดีกับที่ว่าง (hitCap = false แต่เต็มแล้ว)
		local produced, _, exactHitCap = ProductionService.settleMother(data, mother, true)
		check("เติมพอดีเพดาน: ผลิต 5 ตัว", produced, 5)
		check("เติมพอดีเพดาน: hitCap = false (ไม่มีส่วนเกิน)", exactHitCap, false)
		check("เติมพอดีเพดาน → ยังนับว่าเพิ่งเต็ม พิมพ์ (3)", #logs, 3)

		ProductionService.injectForTests({ now = function() return clock end })
	end
end
