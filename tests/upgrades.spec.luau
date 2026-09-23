--!nocheck
-- egg-army-game :: ชุดเทสต์ระบบซื้อตัวคูณ damage + ความเร็ว (ปุ่มติดตัว 2 ปุ่ม)
--
-- ⚠️ EggService.lua (ที่มี buyDamageUpgrade / buySpeedUpgrade / applyWalkSpeed จริง) แตะ
-- Roblox API ตรง ๆ ตั้งแต่บรรทัดแรก (`Players = game:GetService(...)`) จึง require นอก Studio
-- ไม่ได้เลย — เหมือนกับ upgradePen/sellMother ในไฟล์เดียวกันที่ไม่เคยมี unit test ตรง ๆ มาก่อน
-- (ดู tests/README.md) ชุดนี้จึงจำลอง "ตรรกะการตัดสินใจ" ของสองฟังก์ชันนั้นทุกขั้นตอนเป๊ะ
-- (เพดาน → ราคาขั้นถัดไป → เงินพอไหม → หักเงิน+เพิ่มขั้นพร้อมกัน) โดยเรียก Config function
-- ตัวเดียวกับที่ EggService เรียกจริงบน PlayerData.createNew() ตรง ๆ
--
-- ⚠️ สิ่งที่ชุดนี้ทดสอบไม่ได้ (ต้องเปิด Studio เอง — ดู tests/README.md):
--   · Humanoid.WalkSpeed เปลี่ยนจริงตอนซื้อสำเร็จ (EggService.applyWalkSpeed)
--   · WalkSpeed ไม่รีเซ็ตกลับ 32 ตอนตายแล้วเกิดใหม่ (Main.server.lua CharacterAdded hook)
-- เหตุผล: ไม่มี Player/Humanoid/CharacterAdded ให้ใช้นอก Roblox — แต่ท้ายไฟล์นี้มีเทสต์ที่
-- ยืนยัน invariant ที่ทำให้พฤติกรรมนั้นเป็นจริงได้ (speedLevel เป็นของ PlayerData ล้วน ๆ
-- ไม่ผูกกับ Character/Humanoid เลย จึงรอดทุกการตาย/relog แล้ว applyWalkSpeed คำนวณซ้ำได้เป๊ะเดิม)

local PlayerData = require("../src/shared/PlayerData")
local CombatService = require("../src/server/CombatService")
local Json = require("./jsonlite")

return function(t, Config)
	local check = t.check
	local near = t.near

	local function freshData()
		return PlayerData.createNew()
	end

	-- ⚠️ จำลอง EggService.buyDamageUpgrade เป๊ะ (ดู src/server/EggService.lua) —
	-- เพดานจาก wallProgress ก่อนเสมอ (getMaxDamageLevel) แล้วค่อยดูราคาขั้นถัดไป
	-- (getDamageUpgradeCost รับ "ขั้นที่กำลังจะซื้อ" 1-indexed) แล้วค่อยเช็คเงิน
	local function simulateBuyDamageUpgrade(data): (boolean, string?)
		local maxLevel = Config.getMaxDamageLevel(data.wallProgress)
		if data.damageLevel >= maxLevel then
			return false, "cap"
		end
		local nextLevel = data.damageLevel + 1
		local cost = Config.getDamageUpgradeCost(nextLevel)
		if not cost then
			return false, "cap"
		end
		if data.currency.coins < cost then
			return false, "funds"
		end
		data.currency.coins -= cost
		data.damageLevel = nextLevel
		return true, nil
	end

	-- ⚠️ จำลอง EggService.buySpeedUpgrade เป๊ะ — getSpeedUpgradeCost รับ "ขั้นที่มีอยู่ตอนนี้"
	-- (0-indexed) ต่างจาก getDamageUpgradeCost โดยตั้งใจ (คนละฟังก์ชัน คนละ convention)
	local function simulateBuySpeedUpgrade(data): (boolean, string?)
		local cost = Config.getSpeedUpgradeCost(data.speedLevel)
		if not cost then
			return false, "cap"
		end
		if data.currency.coins < cost then
			return false, "funds"
		end
		data.currency.coins -= cost
		data.speedLevel += 1
		return true, nil
	end

	----------------------------------------------------------------------------
	-- ซื้อตัวคูณ damage: เงินพอ
	----------------------------------------------------------------------------
	print("── ซื้อตัวคูณ damage: เงินพอ → หักเงิน + เพิ่มขั้นพร้อมกัน ──")

	do
		local data = freshData()
		data.currency.coins = 1000
		check("เริ่มต้น damageLevel = 0", data.damageLevel, 0)

		local cost = Config.getDamageUpgradeCost(1)
		local ok, reason = simulateBuyDamageUpgrade(data)
		check("ซื้อสำเร็จ", ok, true)
		check("reason เป็น nil ตอนสำเร็จ", reason, nil)
		check("damageLevel ขยับเป็น 1", data.damageLevel, 1)
		check("หักเงินตรงราคาขั้น 1 พอดี", data.currency.coins, 1000 - cost)
	end

	----------------------------------------------------------------------------
	-- ซื้อตัวคูณ damage: เงินไม่พอ
	----------------------------------------------------------------------------
	print("── ซื้อตัวคูณ damage: เงินไม่พอ → ปฏิเสธ ไม่แตะเงิน/ขั้นเลย ──")

	do
		local data = freshData()
		data.currency.coins = 1 -- ต่ำกว่าราคาขั้นแรก (300) แน่นอน
		local ok, reason = simulateBuyDamageUpgrade(data)
		check("ปฏิเสธเพราะเงินไม่พอ", ok, false)
		check("เหตุผลคือเงินไม่พอ", reason, "funds")
		check("damageLevel ไม่ขยับ", data.damageLevel, 0)
		check("เงินไม่ถูกหัก", data.currency.coins, 1)
	end

	----------------------------------------------------------------------------
	-- ซื้อตัวคูณ damage: ติดเพดานของด่านปัจจุบัน + จำลอง exploit ยิงซ้ำหลังติดเพดาน
	----------------------------------------------------------------------------
	print("── ซื้อตัวคูณ damage: ติดเพดานด่าน 1 (8 ขั้น) → ปฏิเสธแม้เงินไม่จำกัด + กันยิงซ้ำ ──")

	do
		local data = freshData()
		data.currency.coins = 1e18
		local maxLevel = Config.getMaxDamageLevel(data.wallProgress)
		check("เพดานด่าน 1 = 8 ขั้น (off-by-one ที่ถูกต้อง — ไม่ใช่ 0)", maxLevel, 8)

		for level = 1, maxLevel do
			local ok = simulateBuyDamageUpgrade(data)
			check(`ซื้อขั้น {level} ได้เรื่อย ๆ จนถึงเพดาน`, ok, true)
		end
		check("ซื้อครบเพดานแล้ว damageLevel = 8", data.damageLevel, 8)

		local ok, reason = simulateBuyDamageUpgrade(data)
		check("ซื้อขั้นที่ 9 ถูกปฏิเสธ (เกินเพดานด่าน 1)", ok, false)
		check("เหตุผลคือติดเพดาน", reason, "cap")
		check("damageLevel ยังคงอยู่ที่ 8 ไม่ขยับต่อ", data.damageLevel, 8)

		-- จำลอง exploit: ยิงคำขอซ้ำเกินเพดานรัว ๆ (เช่น สคริปต์ spam remote) ต้องไม่มีผลอะไรเพิ่มเลย
		local coinsBeforeSpam = data.currency.coins
		for _ = 1, 50 do
			simulateBuyDamageUpgrade(data)
		end
		check("ยิงคำขอซ้ำ 50 ครั้งหลังติดเพดาน — damageLevel ไม่ขยับ", data.damageLevel, 8)
		check("ยิงคำขอซ้ำ 50 ครั้งหลังติดเพดาน — เงินไม่ถูกหักเพิ่มเลย", data.currency.coins, coinsBeforeSpam)
	end

	----------------------------------------------------------------------------
	-- integration: เพดาน damage ขยับขึ้นจริงหลัง wallProgress เพิ่ม (ต่อยอดจากแพตช์ 3A)
	----------------------------------------------------------------------------
	-- จำลอง "พังด่าน 2 จริง" ด้วยสูตรเดียวกับ combat.spec.luau (ชุด "wallProgress เชื่อมกับ
	-- stageProgress ที่ตีผ่านจริง") แล้วพิสูจน์ว่า **ซื้อขั้นที่เคยติดเพดานได้จริง**
	-- ไม่ใช่แค่ตัวเลขเพดานขยับลอย ๆ โดยไม่มีผลกับการซื้อจริง
	print("── integration: พังด่าน 2 จริง → เพดาน damage ขยับ → ซื้อขั้นที่เคยติดเพดานได้จริง ──")

	do
		local data = freshData()
		data.currency.coins = 1e18
		local meta = CombatService.newMeta()
		-- ⚠️ power/ตัวจะสูงกว่า 360 ที่ combat.spec.luau ใช้ (นั่นวัดตอน damageLevel=0) เพราะที่นี่
		-- ซื้อ damageLevel ไปแล้ว 8 ขั้นก่อนตี (×1.1^8 ≈ ×2.14) — ยิ่งเกินพอสำหรับ 15,000 ที่ด่าน 2 ต้องใช้
		-- ไม่กระทบผลของเทสต์นี้เลย เพราะเช็คแค่ว่าด่านพังจริงหรือไม่ ไม่ได้เช็คเศษ HP ที่เหลือ
		local key = Config.makeStackKey("wukong", 10000, {})
		data.children[key] = 100000

		for _ = 1, Config.getMaxDamageLevel(1) do
			simulateBuyDamageUpgrade(data)
		end
		check("ซื้อครบเพดานด่าน 1 แล้ว", data.damageLevel, 8)

		local okBefore = simulateBuyDamageUpgrade(data)
		check("ก่อนพังด่าน 2 — ซื้อขั้น 9 ไม่ได้", okBefore, false)

		CombatService.tick(data, meta, 1) -- พังด่าน 1 ฟรี (ไม่มีกำแพงจริง)
		CombatService.tick(data, meta, 50) -- ปล่อยได้ถึง 50 ตัว (RELEASE_PER_SECOND ด่าน 2 = 1/วิ) เกินพอพังด่าน 2
		check("ด่าน 2 พังจริงแล้ว wallProgress = 2", data.wallProgress, 2)

		local okAfter, reasonAfter = simulateBuyDamageUpgrade(data)
		check("หลังพังด่าน 2 — ซื้อขั้น 9 สำเร็จแล้ว (เพดานใหม่ = 16)", okAfter, true)
		check("reason เป็น nil ตอนสำเร็จ", reasonAfter, nil)
		check("damageLevel ขยับเป็น 9", data.damageLevel, 9)
	end

	----------------------------------------------------------------------------
	-- ซื้อความเร็ว: เงินพอ ไล่ซื้อทีละขั้นครบ 5 ขั้น + WalkSpeed ตรงตาราง §8.8
	----------------------------------------------------------------------------
	print("── ซื้อความเร็ว: เงินพอ ไล่ซื้อครบ 5 ขั้น → WalkSpeed ตรงตาราง §8.8 ทุกขั้น ──")

	do
		local data = freshData()
		data.currency.coins = 1e9
		local expectedSpeed = { 61, 80, 97, 113, 128 } -- docs/data-schema.md §8.8

		for level = 1, Config.Balance.SpeedUpgrade.MAX_LEVEL do
			local costBefore = Config.getSpeedUpgradeCost(data.speedLevel)
			local coinsBefore = data.currency.coins
			local ok, reason = simulateBuySpeedUpgrade(data)
			check(`ซื้อขั้น {level} สำเร็จ`, ok, true)
			check(`ซื้อขั้น {level} reason เป็น nil`, reason, nil)
			check(`speedLevel ขยับเป็น {level}`, data.speedLevel, level)
			check(`หักเงินขั้น {level} ตรงราคา`, data.currency.coins, coinsBefore - (costBefore :: number))
			near(`WalkSpeed หลังซื้อขั้น {level} ตรงตาราง §8.8`, Config.getWalkSpeed(data.speedLevel), expectedSpeed[level], 0.5)
		end
	end

	----------------------------------------------------------------------------
	-- ซื้อความเร็ว: เงินไม่พอ
	----------------------------------------------------------------------------
	print("── ซื้อความเร็ว: เงินไม่พอ → ปฏิเสธ ไม่แตะเงิน/ขั้นเลย ──")

	do
		local data = freshData()
		data.currency.coins = 1
		local ok, reason = simulateBuySpeedUpgrade(data)
		check("ปฏิเสธเพราะเงินไม่พอ", ok, false)
		check("เหตุผลคือเงินไม่พอ", reason, "funds")
		check("speedLevel ไม่ขยับ", data.speedLevel, 0)
		check("เงินไม่ถูกหัก", data.currency.coins, 1)
	end

	----------------------------------------------------------------------------
	-- ซื้อความเร็ว: ติดเพดาน 5 ขั้นถาวร (§8.8 ห้ามขยาย) + จำลอง exploit ยิงซ้ำหลังติดเพดาน
	----------------------------------------------------------------------------
	print("── ซื้อความเร็ว: ติดเพดาน 5 ขั้น → ปฏิเสธแม้เงินไม่จำกัด + กันยิงซ้ำ ──")

	do
		local data = freshData()
		data.currency.coins = 1e18
		for _ = 1, Config.Balance.SpeedUpgrade.MAX_LEVEL do
			simulateBuySpeedUpgrade(data)
		end
		check("ซื้อครบเพดานแล้ว speedLevel = 5", data.speedLevel, Config.Balance.SpeedUpgrade.MAX_LEVEL)

		local ok, reason = simulateBuySpeedUpgrade(data)
		check("ซื้อขั้นที่ 6 ถูกปฏิเสธ (ไม่มีขั้นที่ 6 — ตัดสินใจถาวร)", ok, false)
		check("เหตุผลคือติดเพดาน", reason, "cap")

		local coinsBeforeSpam = data.currency.coins
		for _ = 1, 50 do
			simulateBuySpeedUpgrade(data)
		end
		check(
			"ยิงคำขอซ้ำ 50 ครั้งหลังติดเพดาน — speedLevel ไม่ขยับ",
			data.speedLevel,
			Config.Balance.SpeedUpgrade.MAX_LEVEL
		)
		check("ยิงคำขอซ้ำ 50 ครั้งหลังติดเพดาน — เงินไม่ถูกหักเพิ่มเลย", data.currency.coins, coinsBeforeSpam)
	end

	----------------------------------------------------------------------------
	-- damageLevel / speedLevel เป็นของบัญชี ต้องรอดทั้ง encode/decode และ (โดย invariant)
	-- รอดการตาย/relog เพราะไม่มีที่ไหนในสคีมาผูกค่าพวกนี้ไว้กับ Character/Humanoid เลย
	----------------------------------------------------------------------------
	print("── damageLevel/speedLevel เป็นของบัญชี: roundtrip encode/decode ไม่หาย ──")

	do
		local data = freshData()
		data.currency.coins = 1e9
		for _ = 1, 3 do
			simulateBuyDamageUpgrade(data)
		end
		for _ = 1, 2 do
			simulateBuySpeedUpgrade(data)
		end
		check("ก่อนเซฟ damageLevel = 3", data.damageLevel, 3)
		check("ก่อนเซฟ speedLevel = 2", data.speedLevel, 2)

		PlayerData.sanitizeForSave(data) -- ต้องไม่ throw (encode ได้ตามกฎ §9.3)
		local back = Json.decode(PlayerData.encode(data))

		check("decode กลับมา damageLevel ยังเป็น 3 (แม่ตายไปก็ไม่เสียการลงทุนนี้)", back.damageLevel, 3)
		check("decode กลับมา speedLevel ยังเป็น 2 (ตัวคูณเป็นของบัญชี ไม่ใช่ของตัวละคร)", back.speedLevel, 2)

		-- ⚠️ นี่คือ invariant ที่ทำให้ "ตายแล้วเกิดใหม่ WalkSpeed ไม่รีเซ็ตกลับ 32" เป็นจริงได้:
		-- speedLevel ไม่ได้ผูกกับ Character/Humanoid เลย มันอยู่ใน PlayerData ที่รอดทุกการตาย/relog
		-- เพราะงั้น EggService.applyWalkSpeed(player) ที่อ่านค่านี้ทุกครั้งที่ CharacterAdded
		-- (Main.server.lua) จะคำนวณ WalkSpeed ตัวเดิมเป๊ะเสมอไม่ว่าจะตายกี่รอบ — ส่วนที่ Humanoid
		-- จริงเปลี่ยนค่าตามหรือไม่ ต้องยืนยันด้วยตาใน Studio เท่านั้น (ไม่มี Humanoid นอก Roblox)
		check(
			"getWalkSpeed คำนวณจาก speedLevel ที่ persist ไว้ล้วน ๆ ไม่มี state ชั่วคราวอื่นมาปน",
			Config.getWalkSpeed(back.speedLevel),
			Config.getWalkSpeed(2)
		)
	end
end
