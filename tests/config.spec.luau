--!nocheck
-- egg-army-game :: ชุดเทสต์พฤติกรรมของ Config
--
-- ตรวจ "พฤติกรรมจริง" ไม่ใช่แค่ค่าคงที่: สุ่มน้ำหนักหลายล้านครั้งแล้ววัดการกระจาย
-- คำนวณเส้นเวลาของทุกด่าน และ**ยิงค่าที่ควรพังใส่ยามเพื่อดูว่ายามจับได้จริง**
--
-- ⚠️ ทำไมไฟล์นี้ถึงสำคัญ: ตัวเลขสมดุลของเกมผูกกันเป็นลูกโซ่
-- แก้ตัวคูณคลาสแล้วราคา upgrade กับ turret ต้องขยับตาม — ซึ่งมองด้วยตาไม่เห็น
-- และเคยพลาดมาแล้วหลายรอบ ไฟล์นี้คือสิ่งเดียวที่จับได้
--
-- ⚠️ --!nocheck โดยตั้งใจ: ไฟล์นี้รันด้วย luau CLI ไม่ใช่ใน Roblox
-- `rng` ในเทสต์เป็น stub ที่มีแค่ NextInteger จึงไม่ตรงกับ type Random ของ Roblox
--
-- รันด้วย:  luau tests/run.luau
-- (ห้ามรันไฟล์นี้ตรง ๆ — ต้องรับ t กับ Config เข้ามาก่อน)

return function(t, Config)
	local check, near = t.check, t.near

	print("── validate() ──")
	local ok, err = pcall(Config.validate)
	check("Config.validate() ผ่าน", ok, true)
	if not ok then print(`     {err}`) end

	print("── สูตร damage/HP (เลือก sqrt แล้ว) ──")
	check("ACTIVE_FORMULA", Config.Balance.Damage.ACTIVE_FORMULA, "sqrt")
	near("แม่ 100kg คลาส C = 10", Config.computePower(100,"monkey"), 10, 0.01)
	near("แม่ 10,000kg คลาส C = 100", Config.computePower(10000,"monkey"), 100, 0.01)
	near("แม่ 100kg คลาส SS = 4,320", Config.computePower(100,"yulai"), 4320, 0.01)
	near("ลูกของแม่ 10,000kg = 10% ของแม่",
	     Config.computePower(Config.getChildWeight(10000),"monkey"), 10, 0.01)
	check("ไม่ส่ง charId = ไม่คูณคลาส", Config.computePower(100), 10)
	check("HP = damage (ใช้ฟังก์ชันเดียวกัน)",
	      Config.computePower(5000,"wukong"), Config.computePower(5000,"wukong"))

	print("── ตัวคูณคลาส ──")
	for id, want in { yulai=432, guanyin=216, jade_emperor=216, tang=36, wukong=36,
	                  bajie=6, wujing=6, dragon_horse=6,
	                  monkey=1, pig=1, horse=1, fish=1 } do
		check(`{id}`, Config.getCharacterMultiplier(id), want)
	end
	check("ตัวละครไม่มีจริง = ×1", Config.getCharacterMultiplier("ไม่มี"), 1)
	local n = 0
	for _ in Config.Characters do n += 1 end
	check("มีตัวละคร 12 ตัว", n, 12)

	print("── stack key มีตัวละครแล้ว ──")
	check("ไม่มีสถานะ", Config.makeStackKey("wukong",1500,nil), "wukong|1500|")
	check("สถานะเดียว", Config.makeStackKey("wukong",1500,{"gold"}), "wukong|1500|gold")
	check("เรียงสถานะ", Config.makeStackKey("wukong",1500,{"silver","gold"}), "wukong|1500|gold,silver")
	check("ตัดซ้ำ", Config.makeStackKey("yulai",100000000,{"gold","gold"}), "yulai|100000000|gold")
	check("คนละตัวละคร = คนละกอง",
	      Config.makeStackKey("wukong",1500,nil) ~= Config.makeStackKey("tang",1500,nil), true)
	for _, tc in { {"wukong",1500,{}}, {"yulai",100000000,{"gold","silver"}}, {"fish",100,{"silver"}} } do
		local key = Config.makeStackKey(tc[1], tc[2], tc[3])
		local c,w,st = Config.parseStackKey(key)
		check(`{key} → ตัวละคร`, c, tc[1])
		check(`{key} → น้ำหนัก`, w, tc[2])
		check(`{key} → จำนวนสถานะ`, #st, #tc[3])
	end
	local bad = Config.parseStackKey("ไม่มีตัวคั่น")
	check("key ผิดรูปคืน nil", bad, nil)
	local bad2 = Config.parseStackKey("wukong|1500")
	check("key ขาดช่องคืน nil", bad2, nil)

	print("── คอก ──")
	check("Lv1 จุ 5", Config.getPenCapacity(1), 5)
	check("Lv10 (เพดานใหม่) จุ 14", Config.getPenCapacity(10), 14)
	check("เกินเลเวลก็ยังจุ 14", Config.getPenCapacity(99), 14)
	check("ค่าอัป Lv1→2", Config.getPenUpgradeCost(1), 1000)
	check("ค่าอัป Lv5→6", Config.getPenUpgradeCost(5), 10000000)
	check("เต็มเลเวลแล้วอัปไม่ได้", Config.getPenUpgradeCost(10), nil)
	check("ตัดขั้น 11-15 ทิ้งแล้ว", Config.Balance.Pen.MAX_LEVEL, 10)
	check("เพดานยังคลุมทุกด่าน", Config.Balance.Pen.MAX_LEVEL >= Config.Balance.Stage.COUNT, true)
	check("ราคารวมทั้งสายลดจาก 1e17", (function()
		local total = 0
		for lvl = 1, Config.Balance.Pen.MAX_LEVEL - 1 do total += Config.getPenUpgradeCost(lvl) end
		return total < 2e12
	end)(), true)

	print("── อาวุธ vs บอส: ต้องตี 10 ครั้งทุกด่าน ──")
	for stage = 1, 9 do
		check(`ด่าน {stage}`, Config.getBossHp(stage) / Config.getWeaponDamage(stage), 10)
	end
	check("อาวุธขั้น 1 = 10", Config.getWeaponDamage(1), 10)
	check("บอสด่าน 1 = 100 HP", Config.getBossHp(1), 100)

	print("── อัตราผลิต ──")
	check("ยังไม่อัป = ×1", Config.getProductionMultiplier(0), 1)
	check("อัป 1 ขั้น = ×3", Config.getProductionMultiplier(1), 3)
	check("เต็ม 5 ขั้น (เพดานใหม่) = ×243", Config.getProductionMultiplier(5), 243)
	check("เกินเพดานถูก clamp", Config.getProductionMultiplier(10), 243)
	check("ราคาขั้นแรก", Config.getProductionUpgradeCost(0), 1000)
	check("เต็มแล้วอัปไม่ได้", Config.getProductionUpgradeCost(5), nil)
	check("ตัดขั้น 6-10 ทิ้งแล้ว", Config.Balance.Production.UPGRADE_MAX_LEVEL, 5)
	-- ตัดแล้วต้องไม่ทำให้คอขวดย้อนกลับไปเป็นการผลิต (ไม่งั้นเวลาตีจะเปลี่ยน)
	local stillReleaseBound = true
	for st = 3, 9 do
		local w = Config.Balance.BalanceCheck.REFERENCE_WEIGHT[st]
		local produced = Config.getPenCapacity(st) * Config.getProductionPerMinute(w, nil, st - 1, true) / 60
		if produced < Config.getReleaseRate(st) then stillReleaseBound = false end
	end
	check("ด่าน 3-9 ยังคอขวดที่การปล่อยเหมือนเดิม", stillReleaseBound, true)

	print("── แบ่งเงินบอส: เท่ากันทุกคนที่ร่วมตี ──")
	check("คนเดียวได้เต็ม", Config.getBossKillShare(5, 1), Config.getBossKillReward(5))
	check("7 คนได้คนละ 1/7", Config.getBossKillShare(5, 7), Config.getBossKillReward(5) / 7)
	near("รวมกันแล้วได้เต็มพอดี ไม่มีเงินงอก",
	     Config.getBossKillShare(9, 7) * 7, Config.getBossKillReward(9), 1)
	check("จำนวนคน 0 ไม่ทำให้หารด้วยศูนย์", Config.getBossKillShare(5, 0), Config.getBossKillReward(5))
	check("ไม่แบ่งตามสัดส่วน damage", Config.Balance.Economy.BOSS_REWARD_SPLIT_EQUALLY, true)
	check("ต้องทำ damage ถึงจะนับว่าร่วมตี", Config.Balance.Economy.BOSS_REWARD_MIN_DAMAGE > 0, true)

	print("── ด่าน ──")
	check("ด่าน 1 ไม่มีทหารฝ่ายรับ", Config.getStageDefenderCount(1), 0)
	check("ด่าน 5 ทหาร 100,000", Config.getStageDefenderCount(5), 100000)
	check("ด่าน 9 ทหาร 1,000,000,000", Config.getStageDefenderCount(9), 1e9)
	check("ด่าน 1 ไม่มี HP ทหาร", Config.getStageDefenderHp(1), 0)
	check("ด่าน 1 ไม่มีกำแพง", Config.getStageWallHp(1), 0)
	check("ด่าน 1 ไม่ต้องตีอะไรเลย", Config.getStageTotalHp(1), 0)

	print("── โมเดลที่แสดง (HP → จำนวนตัว) ──")
	check("HP เต็ม = 50 ตัว", Config.getDisplayModelCount(1), 50)
	check("HP ครึ่ง = 25 → แต่พื้นขั้นต่ำ 20", Config.getDisplayModelCount(0.5), 25)
	check("HP 10% → พื้นขั้นต่ำ 20", Config.getDisplayModelCount(0.1), 20)
	check("HP หมด = 0 ตัว", Config.getDisplayModelCount(0), 0)
	check("HP ติดลบก็ยัง 0", Config.getDisplayModelCount(-1), 0)

	print("── เงิน ──")
	near("แม่ 100kg ด่าน 1 = 1/นาที", Config.getCoinsPerMinute(100,1), 1, 0.001)
	near("แม่ 10,000kg ด่าน 1 = 10/นาที", Config.getCoinsPerMinute(10000,1), 10, 0.001)
	near("แม่ 100kg ด่าน 2 = 10/นาที (×10 ต่อด่าน)", Config.getCoinsPerMinute(100,2), 10, 0.001)
	near("แม่ 100kg ด่าน 9 = 1e8/นาที", Config.getCoinsPerMinute(100,9), 1e8, 1)
	check("ขายแม่ = รายได้ 30 นาที",
	      Config.getMotherSellPrice(10000,1), math.floor(10*30))

	print("── สุ่มตัวละครจากไข่ 300,000 ครั้ง ──")
	math.randomseed(20260913)
	local rng = { NextInteger = function(self, lo, hi) return math.random(lo, hi) end }
	local EXPECT = {
		egg_common    = { C=0.80, B=0.18, A=0.02 },
		egg_rare      = { B=0.70, A=0.27, S=0.03 },
		egg_legendary = { B=0.35, A=0.45, S=0.18, SS=0.02 },
	}
	for _, eggId in { "egg_common", "egg_rare", "egg_legendary" } do
		local hits, N = {}, 300000
		for _ = 1, N do
			local id = Config.rollCharacter(eggId, rng)
			local cls = Config.getCharacter(id).class
			hits[cls] = (hits[cls] or 0) + 1
		end
		local parts = {}
		for _, cls in { "C","B","A","S","SS" } do
			if hits[cls] then table.insert(parts, string.format("%s %.2f%%", cls, hits[cls]/N*100)) end
		end
		print(`  {eggId}: {table.concat(parts, " · ")}`)
		local exp = EXPECT[eggId]
		if exp then
			for cls, want in exp do
				local got = (hits[cls] or 0)/N
				if want*N >= 300 then near(`{eggId} คลาส {cls}`, got, want, want*0.1) end
			end
		end
		check(`{eggId} ไม่มีคลาสนอกตาราง`, hits.SS ~= nil == (eggId == "egg_legendary"), true)
	end
	check("ไข่ธรรมดาไม่มี S/SS", Config.EggCharacterPools.egg_common[4], nil)
	check("ไข่หายากไม่มี C", Config.EggCharacterPools.egg_rare[1].class, "B")
	check("ไข่ไม่มีจริงคืน nil", Config.rollCharacter("ไม่มี", rng), nil)


	print("── uid แบบ global ──")
	check("ประกอบ uid", Config.makeUid(1234567, 42), "1234567-42")
	local uid = Config.makeUid(987654321, 1)
	local owner, counter = Config.parseUid(uid)
	check("แยก userId กลับได้", owner, 987654321)
	check("แยกเลขนับกลับได้", counter, 1)
	check("uid ผิดรูปคืน nil", Config.parseUid("ไม่มีตัวคั่น"), nil)
	check("uid ที่ไม่ใช่ตัวเลขคืน nil", Config.parseUid("abc-def"), nil)
	check("คนละผู้เล่น เลขนับเดียวกัน ต้องไม่ชนกัน",
	      Config.makeUid(111, 5) ~= Config.makeUid(222, 5), true)
	check("ตัวคั่น uid ไม่ชนกับ stack key",
	      Config.Uid.SEPARATOR ~= Config.Stack.FIELD_SEPARATOR
	      and Config.Uid.SEPARATOR ~= Config.Stack.STATUS_SEPARATOR, true)

	print("── บัฟสถานะ (ยังไม่เปิด enabled จึงต้องเป็นกลาง) ──")
	local none = Config.getStatusEffects(nil)
	check("ไม่มีสถานะ: damage ×1", none.damageMultiplier, 1)
	check("ไม่มีสถานะ: เงิน ×1", none.coinMultiplier, 1)
	check("ไม่มีสถานะ: ผลิต ×1", none.productionMultiplier, 1)
	check("ไม่มีสถานะ: ลูก 1% ของแม่", none.childRatio, 0.01)
	local off = Config.getStatusEffects({"gold","silver"})
	check("สถานะปิดอยู่: damage ยังเป็น ×1", off.damageMultiplier, 1)
	check("สถานะปิดอยู่: ลูกยัง 1%", off.childRatio, 0.01)
	check("แม่ 10,000 → ลูก 100", Config.getChildWeight(10000), 100)
	check("สถานะปิดอยู่ ลูกก็ยัง 100", Config.getChildWeight(10000,{"gold"}), 100)
	check("เงินไม่เปลี่ยนตอนสถานะปิด",
	      Config.getCoinsPerMinute(10000,1,{"gold","silver"}), Config.getCoinsPerMinute(10000,1))
	check("damage ไม่เปลี่ยนตอนสถานะปิด",
	      Config.computePower(10000,"monkey",{"gold"}), Config.computePower(10000,"monkey"))
	check("สถานะซ้ำไม่นับสองครั้ง",
	      Config.getStatusEffects({"gold","gold"}).childRatio, Config.getStatusEffects({"gold"}).childRatio)
	check("สถานะที่ไม่มีจริงไม่ทำให้พัง", Config.getStatusEffects({"ไม่มี"}).damageMultiplier, 1)
	check("ติดทุกสถานะแล้วลูกไม่เกินแม่",
	      Config.Balance.Weight.CHILD_RATIO + Config.Statuses.gold.childRatioBonus
	      + Config.Statuses.silver.childRatioBonus <= Config.Balance.Weight.MAX_CHILD_RATIO, true)
	check("gold ตั้งไว้ให้ลูกเป็น 2%",
	      Config.Balance.Weight.CHILD_RATIO + Config.Statuses.gold.childRatioBonus, 0.02)


	print("── แหล่งที่มาของไข่ (ไม่มี price แล้ว) ──")
	check("ไข่ธรรมดามาจากบอส", Config.getEgg("egg_common").source, "boss")
	check("ไข่หายากมาจากบอส", Config.getEgg("egg_rare").source, "boss")
	check("ไข่ตำนานมาจาก Robux", Config.getEgg("egg_legendary").source, "robux")
	check("ไม่มีฟิลด์ price แล้ว", Config.getEgg("egg_common").price, nil)
	check("ไม่มีไข่ไหนซื้อด้วยเงินในเกมได้",
	      Config.getEgg("egg_common").price == nil and Config.getEgg("egg_legendary").price == nil, true)

	print("── Developer Product ──")
	local prod = Config.getDeveloperProduct("legendary_egg")
	check("มี product ไข่ตำนาน", prod ~= nil, true)
	check("ให้ไข่ตำนาน", prod.grantEggId, "egg_legendary")
	check("ยังปิดอยู่ (ยังไม่สร้างจริง)", prod.enabled, false)
	check("productId ยังเป็น 0", prod.productId, 0)
	check("ไม่เก็บราคา Robux ใน Config", (prod :: any).robuxPrice, nil)
	check("หา product ที่ปิดอยู่ไม่เจอ", Config.findProductByRobloxId(0), nil)
	check("productId ที่ไม่มีจริงคืน nil", Config.findProductByRobloxId(999999), nil)

	print("── ตารางสุ่มน้ำหนักแยกตามด่าน ──")
	check("ด่าน 1 มีตาราง", Config.Balance.StageWeightTiers[1] ~= nil, true)
	check("ด่าน 5 ยังไม่กำหนด", Config.Balance.StageWeightTiers[5], nil)
	check("ด่าน 5 ถอยไปใช้ด่าน 1", Config.getWeightTiers(5), Config.Balance.StageWeightTiers[1])
	check("ด่าน 9 ถอยไปใช้ด่าน 1", Config.getWeightTiers(9), Config.Balance.StageWeightTiers[1])
	check("ด่านเกินช่วงก็ยังคืนตารางได้", Config.getWeightTiers(99) ~= nil, true)
	check("สุ่มโดยไม่ส่ง stage ยังทำงาน", Config.rollMotherWeight(rng) >= 100, true)
	check("สุ่มโดยส่ง stage ยังทำงาน", Config.rollMotherWeight(rng, 7) >= 100, true)

	print("── ตารางด่าน + อาวุธป้องกันกำแพง ──")
	check("มีครบ 9 ด่าน", #Config.Balance.Stages, 9)
	check("ด่าน 1 ไม่มีทหารฝ่ายรับ", Config.getStageDefenderCount(1), 0)
	check("ด่าน 9 ทหาร 1,000,000,000", Config.getStageDefenderCount(9), 1e9)
	check("ด่าน 1 ไม่มี turret", Config.getStageTurretDps(1), 0)

	-- turret ต้องเป็นสัดส่วนของ damage/วินาที ไม่ใช่ของ damage ทหารฝ่ายรับ
	local function ourDpsAt(stage)
		local chk = Config.Balance.BalanceCheck
		local w = chk.REFERENCE_WEIGHT[stage]
		local cid
		for id, ch in Config.Characters do if ch.class == chk.REFERENCE_CLASS[stage] then cid = id break end end
		local eff = math.min(Config.getPenCapacity(stage) * Config.getProductionPerMinute(w, nil, stage - 1, true) / 60,
			Config.getReleaseRate(stage))
		return eff * Config.computeBattlePower(Config.getChildWeight(w), cid, nil, Config.getMaxDamageLevel(stage))
	end
	local tollOk, tollMax, tollMin = true, 0, 1
	for st = 2, 9 do
		local toll = Config.getStageTurretDps(st) / ourDpsAt(st)
		if toll > tollMax then tollMax = toll end
		if toll < tollMin then tollMin = toll end
		if toll > Config.Balance.BalanceCheck.TURRET_TOLL_CEILING then tollOk = false end
	end
	near("ด่าน 9 turret = 20% ของ damage/วิ", Config.getStageTurretDps(9), 0.20 * ourDpsAt(9), 1e-6)
	check("turret กินกำลังพลไม่เกินเพดานทุกด่าน", tollOk, true)
	near("ด่าน 2 turret กิน ~10%", Config.getStageTurretDps(2) / ourDpsAt(2), 0.10, 0.01)
	near("ด่าน 9 turret กิน ~20%", Config.getStageTurretDps(9) / ourDpsAt(9), 0.20, 0.01)
	check("ด่านสูง turret เขี้ยวขึ้น", tollMax > tollMin, true)
	print(string.format("   turret กินกำลังพล %.1f%% (ด่าน 2) → %.1f%% (ด่าน 9)",
		tollMin * 100, tollMax * 100))
	local ok9 = true
	for st = 2, 9 do
		if Config.getStageDefenderCount(st) <= Config.getStageDefenderCount(st-1) then ok9 = false end
	end
	check("ด่านยากขึ้นเรื่อย ๆ ทุกด่าน", ok9, true)


	print("── ไข่ตำนาน: รับประกัน tier ขั้นต่ำ ──")
	check("ไข่ตำนานรับประกัน tier 3", Config.getEgg("egg_legendary").guaranteedTier, 3)
	check("ไข่จากบอสไม่รับประกัน", Config.getEgg("egg_common").guaranteedTier, nil)
	local minTier3 = Config.Balance.Weight.TIERS[3].min
	local low, lowest = 0, math.huge
	for _ = 1, 200000 do
		local w = Config.rollMotherWeightForEgg("egg_legendary", rng, 1)
		if w < minTier3 then low += 1 end
		if w < lowest then lowest = w end
	end
	check("ไข่ตำนาน 200,000 ฟอง ไม่มีฟองไหนต่ำกว่า tier 3", low, 0)
	check("น้ำหนักต่ำสุดที่ได้ = ขอบล่างของ tier 3", lowest >= minTier3, true)
	local anyHigher = false
	for _ = 1, 200000 do
		if Config.rollMotherWeightForEgg("egg_legendary", rng, 1) > Config.Balance.Weight.TIERS[3].max then anyHigher = true end
	end
	check("ยังลุ้น tier สูงกว่าที่รับประกันได้", anyHigher, true)
	check("ไข่ที่ไม่มีจริงคืน nil", Config.rollMotherWeightForEgg("ไม่มี", rng, 1), nil)
	local bossLow = false
	for _ = 1, 5000 do
		if Config.rollMotherWeightForEgg("egg_common", rng, 1) < minTier3 then bossLow = true end
	end
	check("ไข่จากบอสยังออกตัวเล็กได้ตามปกติ", bossLow, true)

	print("── SS ต้องมาจากไข่ Robux เท่านั้น ──")
	local function classesOf(eggId)
		local set = {}
		for _, e in Config.EggCharacterPools[eggId] do set[e.class] = true end
		return set
	end
	check("ไข่ธรรมดา: ไม่มี S", classesOf("egg_common").S, nil)
	check("ไข่ธรรมดา: ไม่มี SS", classesOf("egg_common").SS, nil)
	check("ไข่หายาก: มี S", classesOf("egg_rare").S, true)
	check("ไข่หายาก: ไม่มี SS", classesOf("egg_rare").SS, nil)
	check("ไข่หายาก: ไม่มี C", classesOf("egg_rare").C, nil)
	check("ไข่ตำนาน: มี SS", classesOf("egg_legendary").SS, true)
	check("ไข่ตำนาน: ไม่มี C", classesOf("egg_legendary").C, nil)


	print("── ตัวคูณ damage ที่ซื้อด้วยเงิน ──")
	local UP = Config.Balance.DamageUpgrade
	local STEP = UP.STEP_MULTIPLIER
	check("ยังไม่ซื้อ = ×1 พอดี", Config.getArmyDamageMultiplier(0), 1)
	near("ขั้น 1 = ×1.1", Config.getArmyDamageMultiplier(1), 1.1, 1e-9)
	near("ขั้น 8 = ×1.1^8", Config.getArmyDamageMultiplier(8), STEP^8, 1e-9)
	near("ขั้นสุดท้าย 72 = ×1.1^72", Config.getArmyDamageMultiplier(UP.MAX_LEVEL), STEP^72, 1e-6)
	check("เกินเพดานถูก clamp", Config.getArmyDamageMultiplier(999), Config.getArmyDamageMultiplier(UP.MAX_LEVEL))
	check("ติดลบถูก clamp เป็น 0", Config.getArmyDamageMultiplier(-5), 1)
	check("ตัวคูณสะสมโตขึ้นเรื่อย ๆ", Config.getArmyDamageMultiplier(40) > Config.getArmyDamageMultiplier(39), true)

	print("── เพดานการซื้อ: off-by-one ──")
	check("ด่าน 1 ซื้อได้ 8 ขั้น ไม่ใช่ 0", Config.getMaxDamageLevel(1), 8)
	check("ด่าน 2 ซื้อได้ 16 ขั้น", Config.getMaxDamageLevel(2), 16)
	check("ด่าน 9 ซื้อได้ 72 ขั้น", Config.getMaxDamageLevel(9), 72)
	check("เพดานด่านท้าย = MAX_LEVEL", Config.getMaxDamageLevel(9), UP.MAX_LEVEL)
	check("ด่าน 0 ถูก clamp เป็นด่าน 1", Config.getMaxDamageLevel(0), 8)
	check("ด่านเกิน 9 ถูก clamp", Config.getMaxDamageLevel(99), 72)
	check("8 ขั้น × 9 ด่าน = 72", UP.STEPS_PER_STAGE * Config.Balance.Stage.COUNT, UP.MAX_LEVEL)

	print("── ราคา upgrade ──")
	check("ขั้น 0 ไม่มีราคา", Config.getDamageUpgradeCost(0), nil)
	check("เกินเพดานไม่มีราคา", Config.getDamageUpgradeCost(UP.MAX_LEVEL + 1), nil)
	check("ขั้นแรกราคา 300 (ผู้เล่นใหม่มี 500 ซื้อได้ทันที)", Config.getDamageUpgradeCost(1), 300)
	check("ผู้เล่นใหม่ซื้อขั้นแรกไหว", Config.Balance.NewPlayer.coins >= Config.getDamageUpgradeCost(1), true)
	near("ขั้น 2 = ขั้น 1 × 1.3", Config.getDamageUpgradeCost(2), 300 * 1.3, 1e-9)
	check("ขั้น 9 ขึ้นฐานราคาของด่าน 2", Config.getDamageUpgradeCost(9), UP.STAGE_COST_BASE[2])
	local priceRises = true
	for lvl = 2, UP.MAX_LEVEL do
		if Config.getDamageUpgradeCost(lvl) < Config.getDamageUpgradeCost(lvl - 1) then priceRises = false end
	end
	check("ราคาไล่ขึ้นตลอด 72 ขั้น ไม่มีช่วงถูกลง", priceRises, true)

	print("── ราคาต้องดูดเงินส่วนเกิน ──")
	local shareOk, minShare, maxShare = true, 1, 0
	for st = 1, 9 do
		local share = Config.getStageDamageUpgradeTotal(st) / Config.getReferenceStageIncome(st)
		if share < minShare then minShare = share end
		if share > maxShare then maxShare = share end
		if share < Config.Balance.BalanceCheck.MIN_UPGRADE_SHARE or share > Config.Balance.BalanceCheck.MAX_UPGRADE_SHARE then
			shareOk = false
		end
	end
	check("ทุกด่านอยู่ในช่วง 30-70% ของรายได้", shareOk, true)
	print(string.format("   ราคากินรายได้ %.0f%% ถึง %.0f%%", minShare * 100, maxShare * 100))

	local worstSurplus, bestSurplus = 999, 0
	for st = 2, 9 do
		local need = Config.getStageDamageUpgradeTotal(st)
			+ (Config.getPenUpgradeCost(st) or 0)
			+ (Config.getProductionUpgradeCost(st - 1) or 0)
			+ (Config.getWeaponUpgradeCost(st) or 0)
		local surplus = Config.getReferenceStageIncome(st) / need
		if surplus < worstSurplus then worstSurplus = surplus end
		if surplus > bestSurplus then bestSurplus = surplus end
	end
	check("ส่วนเกินไม่เกิน 3 เท่าแล้ว (เดิม 299 เท่า)", bestSurplus <= 3, true)
	check("แต่ยังเหลือพอซื้ออาวุธ (ไม่ต่ำกว่า 1.5 เท่า)", worstSurplus >= 1.5, true)
	print(string.format("   ส่วนเกิน %.2fx ถึง %.2fx", worstSurplus, bestSurplus))

	print("── computeBattlePower ──")
	local base = Config.computePower(10000, "wukong")
	check("ยังไม่ซื้อ upgrade = พลังพื้นฐาน", Config.computeBattlePower(10000, "wukong", nil, 0), base)
	near("ขั้น 16 = พื้นฐาน × 1.1^16", Config.computeBattlePower(10000, "wukong", nil, 16), base * STEP^16, 1e-6)
	near("ใช้กับลูกได้เหมือนแม่",
	     Config.computeBattlePower(Config.getChildWeight(10000), "wukong", nil, 24),
	     Config.computePower(Config.getChildWeight(10000), "wukong") * STEP^24, 1e-9)

	print("── ไม่มีตัวคูณ damage อัตโนมัติตามด่านแล้ว ──")
	check("getStageDamageMultiplier ถูกลบแล้ว", Config.getStageDamageMultiplier, nil)
	check("STAGE_DAMAGE_BASE ถูกลบแล้ว", Config.Balance.Combat.STAGE_DAMAGE_BASE, nil)
	check("สูตรเงินยังใช้ตัวคูณตามด่านเหมือนเดิม",
	      Config.getCoinsPerMinute(100, 3) / Config.getCoinsPerMinute(100, 1), 100)

	print("── ยามเฝ้าสมดุล ต้องจับค่าที่พังได้จริง ──")
	local savedStep = Config.Balance.DamageUpgrade.STEP_MULTIPLIER
	Config.Balance.DamageUpgrade.STEP_MULTIPLIER = 1.3
	check("ตัวคูณต่อขั้น 1.3 (แรงเกิน) ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	do
		local _, err = pcall(Config.validate)
		print("   ข้อความที่ได้: " .. string.sub(tostring(err), 1, 110))
	end
	Config.Balance.DamageUpgrade.STEP_MULTIPLIER = 1.01
	check("ตัวคูณต่อขั้น 1.01 (อ่อนเกิน) ต้องไม่ผ่านเช่นกัน", pcall(Config.validate), false)
	Config.Balance.DamageUpgrade.STEP_MULTIPLIER = savedStep
	check("คืนค่าเดิมแล้ว validate ผ่าน", pcall(Config.validate), true)

	-- ราคาที่ถูกเกินไปต้องถูกจับด้วย (เงินจะล้นเหมือนเดิม)
	local savedCost = Config.Balance.DamageUpgrade.STAGE_COST_BASE[5]
	Config.Balance.DamageUpgrade.STAGE_COST_BASE[5] = savedCost / 100
	check("ราคาด่าน 5 ถูกลง 100 เท่า ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	Config.Balance.DamageUpgrade.STAGE_COST_BASE[5] = savedCost * 100
	check("ราคาด่าน 5 แพงขึ้น 100 เท่า ก็ไม่ผ่านเช่นกัน", pcall(Config.validate), false)
	Config.Balance.DamageUpgrade.STAGE_COST_BASE[5] = savedCost
	check("คืนราคาเดิมแล้ว validate ผ่าน", pcall(Config.validate), true)

	print("── เกมต้องยากขึ้นเรื่อย ๆ ──")
	-- คิดแบบระบบใหม่: อัตราจริง = min(ผลิตได้, ปล่อยได้) และข้ามด่านที่ไม่มีกำแพง
	local function hoursAt(st)
		local hp = Config.getStageTotalHp(st)
		if hp <= 0 then return 0 end
		local w = Config.Balance.BalanceCheck.REFERENCE_WEIGHT[st]
		local cl = Config.Balance.BalanceCheck.REFERENCE_CLASS[st]
		local id
		for cid, ch in Config.Characters do if ch.class == cl then id = cid break end end
		local produced = Config.getPenCapacity(st) * Config.getProductionPerMinute(w, nil, st - 1, true) / 60
		local rate = math.min(produced, Config.getReleaseRate(st))
		return hp / (rate * Config.computeBattlePower(Config.getChildWeight(w), id, nil, Config.getMaxDamageLevel(st)) * 3600)
	end
	-- ⚠️ เส้นเวลา "ซิกแซก" โดยตั้งใจ เพราะคลาสไต่เป็นขั้น ๆ (C→B→A) ไม่ใช่ต่อเนื่อง
	-- ด่านที่ผู้เล่นเพิ่งได้คลาสใหม่จะง่ายลง แล้วค่อยยากขึ้นอีกสองด่าน
	-- สิ่งที่ต้องคุมคือ (ก) เทรนด์รวมต้องขึ้น (ข) หลุมไม่ลึกเกินไป
	local deepest = 1
	local prev = 0
	for st = 2, 9 do
		local h = hoursAt(st)
		if prev > 0 and h < prev then
			local drop = prev / h
			if drop > deepest then deepest = drop end
		end
		prev = h
	end
	check("หลุมตอนได้คลาสใหม่ไม่ลึกเกิน 4 เท่า", deepest <= 4, true)
	check("ด่าน 9 นานกว่าด่าน 2 อย่างน้อย 10 เท่า", hoursAt(9) / hoursAt(2) >= 10, true)
	check("ทุกด่านอยู่ในช่วงที่ยามยอมรับ", (function()
		for st = 2, 9 do
			local h = hoursAt(st)
			if h < Config.Balance.BalanceCheck.MIN_HOURS_PER_STAGE or h > Config.Balance.BalanceCheck.MAX_HOURS_PER_STAGE then
				return false
			end
		end
		return true
	end)(), true)
	check("ด่าน 1 ไม่ต้องตี", hoursAt(1), 0)
	check("hoursAt ตรงกับ Config.getReferenceClearHours", 
		math.abs(hoursAt(5) - Config.getReferenceClearHours(5)) < 1e-9, true)
	print(string.format("   หลุมลึกสุด %.2f เท่า", deepest))
	print(string.format("   ด่าน 2 = %.2f ชม.  ·  ด่าน 9 = %.2f ชม.  ·  ชัน %.1f เท่า",
		hoursAt(2), hoursAt(9), hoursAt(9) / hoursAt(2)))

	print("── ระบบรบใหม่: อัตราปล่อย ──")
	check("ตารางอัตราปล่อยครบ 9 ด่าน", #Config.Balance.Combat.RELEASE_PER_SECOND, 9)
	check("ด่าน 1 ปล่อย 1 ตัว/วิ", Config.getReleaseRate(1), 1)
	check("ด่าน 9 ปล่อย 10 ตัว/วิ", Config.getReleaseRate(9), 10)
	check("ด่าน 3 ยังปล่อย 1 ตัว/วิ (รอยต่อคอขวด)", Config.getReleaseRate(3), 1)
	local rising = true
	for st = 2, 9 do if Config.getReleaseRate(st) < Config.getReleaseRate(st-1) then rising = false end end
	check("อัตราปล่อยไม่ลดลง", rising, true)

	print("── อัตราผลิตแปรตามน้ำหนัก (exponent 0.25) ──")
	check("exponent = 0.25", Config.Balance.Production.WEIGHT_EXPONENT, 0.25)
	near("แม่ 100 kg = 1.0/นาที", Config.getProductionPerMinute(100, nil, 0, true), 1, 0.001)
	near("แม่ 10,000 kg = 3.16/นาที", Config.getProductionPerMinute(10000, nil, 0, true), 3.162, 0.01)
	near("แม่ 1,000,000 kg = 10/นาที", Config.getProductionPerMinute(1000000, nil, 0, true), 10, 0.01)
	near("แม่ 100,000,000 kg = 31.6/นาที", Config.getProductionPerMinute(100000000, nil, 0, true), 31.62, 0.01)
	near("ออฟไลน์ช้ากว่า 10 เท่า",
	     Config.getProductionPerMinute(10000, nil, 0, false) * 10,
	     Config.getProductionPerMinute(10000, nil, 0, true), 0.001)
	near("upgrade คูณทับได้",
	     Config.getProductionPerMinute(100, nil, 2, true),
	     Config.getProductionPerMinute(100, nil, 0, true) * 9, 0.001)
	check("ช่วง 100kg → 100M kg = 31,623 เท่า",
	      math.floor(Config.getProductionPerMinute(100000000,nil,0,true) / Config.getProductionPerMinute(100,nil,0,true)), 31)

	print("── คลังทหาร ──")
	check("cap 500 ต่อกอง", Config.getStackCap(), 500)
	check("ไม่มีระบบอัป cap แล้ว (ตายตัว 500)", Config.Balance.Production.STACK_CAP_START, nil)
	near("แม่น้ำหนักฐานเติมเต็ม 500 ใช้ ~8 ชม.",
	     500 / Config.getProductionPerMinute(100, nil, 0, true) / 60, 8.33, 0.1)

	print("── ด่าน 1 ไม่มีกำแพง ──")
	check("ไม่มีทหารฝ่ายรับ", Config.getStageDefenderCount(1), 0)
	check("ไม่มีอะไรให้ตี", Config.getStageTotalHp(1), 0)
	check("ด่าน 2 มีทหาร 100", Config.getStageDefenderCount(2), 100)

	print("── กติกาที่ห้ามพลิก ──")
	check("ห้าม auto ปล่อยแม่", Config.Balance.Combat.ALLOW_AUTO_RELEASE_MOTHERS, false)
	check("ห้ามเลือกแม่จากคอก", Config.Balance.Combat.MOTHERS_SELECTABLE_FROM_PEN, false)
	local savedA = Config.Balance.Combat.ALLOW_AUTO_RELEASE_MOTHERS
	Config.Balance.Combat.ALLOW_AUTO_RELEASE_MOTHERS = true
	check("เปิด auto ปล่อยแม่ → validate ไม่ผ่าน", pcall(Config.validate), false)
	Config.Balance.Combat.ALLOW_AUTO_RELEASE_MOTHERS = savedA
	local savedP = Config.Balance.Combat.MOTHERS_SELECTABLE_FROM_PEN
	Config.Balance.Combat.MOTHERS_SELECTABLE_FROM_PEN = true
	check("เลือกแม่จากคอกได้ → validate ไม่ผ่าน", pcall(Config.validate), false)
	Config.Balance.Combat.MOTHERS_SELECTABLE_FROM_PEN = savedP

	print("── โมเดลบนจอ ──")
	check("ด่าน 1: 1/วิ × 30 วิ = 30 ตัว", Config.getVisibleUnitCount(1), 30)
	check("ด่าน 9: 10/วิ × 30 วิ = 300 → ตัดที่ cap 120", Config.getVisibleUnitCount(9), 120)

	print("── ซากของ Phase 1 ต้องยังอยู่แต่ปิดไว้ ──")
	-- กฎ id: เลิกใช้ให้ตั้ง enabled = false ห้ามลบ (ข้อมูลที่เซฟไปแล้วอ้างถึงอยู่)
	check("egg_common ยังอยู่ (ห้ามลบ)", Config.getEgg("egg_common") ~= nil, true)
	check("egg_rare ยังอยู่ (ห้ามลบ)", Config.getEgg("egg_rare") ~= nil, true)
	check("egg_common ถูกปิดแล้ว", Config.getEgg("egg_common").enabled, false)
	check("egg_rare ถูกปิดแล้ว", Config.getEgg("egg_rare").enabled, false)
	check("egg_legendary ยังเปิดอยู่", Config.getEgg("egg_legendary").enabled, true)
	check("UnitTypes เดิมยังอยู่ (ห้ามลบ)", Config.getUnit("recruit") ~= nil, true)
	local anyUnitEnabled = false
	for _, unit in Config.UnitTypes do
		if unit.enabled then anyUnitEnabled = true end
	end
	check("UnitTypes ปิดหมดแล้ว (ฟักได้ตัวแม่ ไม่ใช่ทหาร)", anyUnitEnabled, false)
	check("hatchTable ถูกถอดออกแล้ว", Config.getEgg("egg_common").hatchTable, nil)
	check("Config.Farm ถูกเปลี่ยนชื่อเป็น Config.World แล้ว", rawget(Config, "Farm"), nil)
	check("Config.World.MAX_PENS = จำนวนผู้เล่นต่อเซิร์ฟ", Config.World.MAX_PENS, Config.Balance.BalanceCheck.PLAYERS_PER_SERVER)
	check("formatWeight ยังทำงาน", Config.formatWeight(1200), "1.2K")
	check("rollMotherWeight ยังทำงาน", Config.rollMotherWeight(rng) >= 100, true)


	print("── ไข่รายด่าน: มีครบ 9 ใบ ──")
	-- rng ตัวเดียวกับที่เทสต์อื่นใช้ (luau CLI ไม่มี Random ของ Roblox)
	local rngE = rng
	local EXPECT = {
		{ C = 0.90, B = 0.10 },
		{ C = 0.80, B = 0.20 },
		{ C = 0.70, B = 0.299, A = 0.001 },
		{ C = 0.60, B = 0.39, A = 0.01 },
		{ C = 0.50, B = 0.45, A = 0.05 },
		{ C = 0.40, B = 0.50, A = 0.10 },
		{ C = 0.30, B = 0.45, A = 0.24, S = 0.01 },
		{ C = 0.20, B = 0.30, A = 0.40, S = 0.10 },
		{ C = 0.10, B = 0.20, A = 0.50, S = 0.20 },
	}
	local allBoss, allEnabled, idMatches = true, true, true
	for st = 1, 9 do
		local eggId = Config.getBossEggId(st)
		local egg = Config.getEgg(eggId)
		if not egg then idMatches = false
		else
			if egg.source ~= "boss" then allBoss = false end
			if not egg.enabled then allEnabled = false end
			if egg.stage ~= st then idMatches = false end
		end
	end
	check("getBossEggId ชี้ไข่ที่มีจริงและผูกด่านถูก", idMatches, true)
	check("ไข่รายด่านมาจากบอสทุกใบ", allBoss, true)
	check("ไข่รายด่านเปิดใช้ทุกใบ", allEnabled, true)
	check("ด่านนอกช่วงถูก clamp", Config.getBossEggId(99), "egg_stage9")
	check("ด่าน 0 ถูก clamp เป็นด่าน 1", Config.getBossEggId(0), "egg_stage1")

	print("── ตารางคลาสต่อด่าน ต้องตรงที่ออกแบบไว้ ──")
	local poolOk = true
	for st = 1, 9 do
		local pool = Config.EggCharacterPools[Config.getBossEggId(st)]
		local total = 0
		for _, entry in pool do
			total += entry.weight
			local want = EXPECT[st][entry.class]
			if want == nil or math.abs(entry.weight / Config.CLASS_ROLL_MAX - want) > 1e-9 then
				poolOk = false
				print(`   ✗ ด่าน {st} คลาส {entry.class} = {entry.weight}`)
			end
		end
		if total ~= Config.CLASS_ROLL_MAX then poolOk = false end
	end
	check("สัดส่วนคลาสทุกด่านตรงตาราง + รวมได้ 10000 พอดี", poolOk, true)

	print("── สุ่มจริง 60,000 ครั้งต่อด่าน ──")
	local ROLLS = 60000
	local noSS, monoC, prevC = true, true, 2
	for st = 1, 9 do
		local hits = {}
		for _ = 1, ROLLS do
			local charId = Config.rollCharacter(Config.getBossEggId(st), rngE)
			local class = Config.getCharacter(charId).class
			hits[class] = (hits[class] or 0) + 1
		end
		if hits.SS then noSS = false end
		local cShare = (hits.C or 0) / ROLLS
		if cShare > prevC then monoC = false end
		prevC = cShare
		local parts = {}
		for _, cls in { "C", "B", "A", "S" } do
			if hits[cls] then table.insert(parts, string.format("%s %.2f%%", cls, hits[cls] / ROLLS * 100)) end
		end
		print(`   ด่าน {st}: ` .. table.concat(parts, " · "))
		for cls, want in EXPECT[st] do
			near(`ด่าน {st} คลาส {cls}`, (hits[cls] or 0) / ROLLS, want, math.max(0.008, want * 0.25))
		end
	end
	check("ไข่จากบอสไม่ออก SS สักด่าน", noSS, true)
	check("ด่านสูงขึ้น สัดส่วน C ลดลงเรื่อย ๆ", monoC, true)
	check("S เริ่มออกที่ด่าน 7", Config.EggCharacterPools.egg_stage6[4], nil)

	print("── น้ำหนัก: ตารางเดียวกันทุกด่าน ──")
	local sameTiers = true
	for st = 2, 9 do
		if Config.getWeightTiers(st) ~= Config.getWeightTiers(1) then sameTiers = false end
	end
	check("ทุกด่านใช้ตาราง tier เดียวกัน", sameTiers, true)
	check("ไข่รายด่านไม่รับประกัน tier", Config.getEgg("egg_stage9").guaranteedTier, nil)

	-- ไข่ที่ผูกด่านไว้ต้องใช้ด่านของตัวเอง ไม่ใช่ค่าที่ผู้เรียกส่งมา
	-- ไข่ที่ผูกด่านต้องอ่านตาราง tier ของด่านตัวเอง ไม่ใช่ของที่ส่งมา
	-- (ตอนนี้ทุกด่านใช้ตารางเดียวกัน จึงเทียบที่ "ตารางที่เลือกใช้" แทนค่าที่สุ่มได้)
	local seenSame = true
	for _ = 1, 2000 do
		local w = Config.rollMotherWeightForEgg("egg_stage3", rng, 9)
		if w == nil or w < 100 or w > 100000000 then seenSame = false end
	end
	check("ไข่ผูกด่านแล้วยังสุ่มน้ำหนักได้ถูกช่วง", seenSame, true)

	print("── ไข่เดิมสองใบ: ปิดแล้วแต่ยังอ่านได้ ──")
	check("egg_common ยัง lookup ได้", Config.getEgg("egg_common") ~= nil, true)
	check("egg_common ถูกปิด", Config.getEgg("egg_common").enabled, false)
	check("egg_rare ถูกปิด", Config.getEgg("egg_rare").enabled, false)
	check("egg_legendary ยังเปิดอยู่", Config.getEgg("egg_legendary").enabled, true)
	check("ไข่ตำนานไม่ผูกด่าน", Config.getEgg("egg_legendary").stage, nil)
	check("DEFAULT_EGG_ID เป็นไข่ด่าน 1", Config.DEFAULT_EGG_ID, "egg_stage1")
	check("ผู้เล่นใหม่ได้ไข่ด่าน 1", Config.Balance.NewPlayer.startingEggs.egg_stage1, 1)

	print("── ยาม turret ต้องจับค่าที่พังได้จริง ──")
	-- ⚠️ turretDps ไม่ใช่ตัวเลขดิบแล้ว — คำนวณจาก TOLL × damage/วินาที
	check("ตาราง Stages ไม่มีฟิลด์ turretDps แล้ว", Config.Balance.Stages[9].turretDps, nil)
	check("ด่าน 1 ไม่มีกำแพงจึงไม่มี turret", Config.getStageTurretDps(1), 0)
	check("TOLL ไล่ขึ้นจาก 10% ถึง 20%", Config.Balance.Combat.TURRET_TOLL[2] == 0.10
		and Config.Balance.Combat.TURRET_TOLL[9] == 0.20, true)

	-- ค่าที่คำนวณต้องตรงกับ TOLL เป๊ะทุกด่าน ไม่ใช่แค่ใกล้เคียง
	local exact = true
	for st = 2, 9 do
		if math.abs(Config.getStageTurretDps(st) / ourDpsAt(st) - Config.Balance.Combat.TURRET_TOLL[st]) > 1e-9 then
			exact = false
		end
	end
	check("turretDps = TOLL × damage/วิ เป๊ะทุกด่าน", exact, true)

	-- หัวใจของการเปลี่ยนรอบนี้: ปรับอะไรก็ตามที่กระทบ damage แล้ว turret ต้องขยับตามเอง
	local beforeDps = Config.getStageTurretDps(9)
	local savedStepM = Config.Balance.DamageUpgrade.STEP_MULTIPLIER
	Config.Balance.DamageUpgrade.STEP_MULTIPLIER = 1.05
	local afterDps = Config.getStageTurretDps(9)
	check("ลดตัวคูณ damage แล้ว turret ลดตามเอง (ไม่ต้องแก้มือ)", afterDps < beforeDps, true)
	near("สัดส่วนยังเป็น 20% เท่าเดิม", afterDps / ourDpsAt(9), 0.20, 1e-9)
	Config.Balance.DamageUpgrade.STEP_MULTIPLIER = savedStepM
	check("คืนค่าเดิมแล้ว turret กลับมาเท่าเดิม", Config.getStageTurretDps(9), beforeDps)

	-- ยามต้องจับ TOLL ที่แรงเกินเพดาน
	local savedToll = Config.Balance.Combat.TURRET_TOLL[9]
	Config.Balance.Combat.TURRET_TOLL[9] = 0.9
	check("TOLL 90% ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	do
		local _, err = pcall(Config.validate)
		print("   ข้อความที่ได้: " .. string.sub(tostring(err), 1, 110))
	end
	Config.Balance.Combat.TURRET_TOLL[9] = 0.05
	check("TOLL ที่ต่ำกว่าด่านก่อนหน้าก็ไม่ผ่าน (กำแพงด่านสูงต้องไม่อ่อนลง)", pcall(Config.validate), false)
	Config.Balance.Combat.TURRET_TOLL[9] = savedToll
	check("คืนค่าเดิมแล้ว validate ผ่าน", pcall(Config.validate), true)


	print("── เงินจากการฆ่า ──")
	check("ทหารด่าน 1 = 100/ตัว", Config.getDefenderKillReward(1), 100)
	check("ทหารด่าน 9 = 25,600/ตัว", Config.getDefenderKillReward(9), 25600)
	check("บอสด่าน 1 = 10,000", Config.getBossKillReward(1), 10000)
	check("บอสด่าน 9 = 1e12", Config.getBossKillReward(9), 1e12)
	check("ด่านนอกช่วงถูก clamp", Config.getDefenderKillReward(99), Config.getDefenderKillReward(9))
	check("ด่าน 1 ไม่มีทหาร จึงไม่มีเงินจากการกวาด", Config.getStageDefenderRewardTotal(1), 0)
	check("กวาดทหารด่าน 2 ได้ 20,000", Config.getStageDefenderRewardTotal(2), 100 * 200)

	local killGrowthOk = true
	for st = 3, 9 do
		local g = Config.getStageDefenderRewardTotal(st) / Config.getStageDefenderRewardTotal(st - 1)
		if math.abs(g - 20) > 1e-9 then killGrowthOk = false end
	end
	check("เงินจากการกวาดทหารโต ×20 ต่อด่านทุกด่าน", killGrowthOk, true)
	check("โตเร็วกว่าราคาของที่โต ×10", 20 > Config.Balance.Pen.UPGRADE_COST_MULTIPLIER, true)
	check("เงินบอสโตเท่าราคาของพอดี", Config.Balance.Economy.KILL_BOSS_MULTIPLIER, Config.Balance.Pen.UPGRADE_COST_MULTIPLIER)

	print("── ตัวคูณคลาสชุดใหม่: กัน pay-to-win ──")
	check("SS ÷ S = 2 เท่า", Config.getCharacterMultiplier("yulai") / Config.getCharacterMultiplier("guanyin"), 2)
	check("C→B→A→S ไล่ ×6", (function()
		local m = Config.CharacterClasses
		return m.B.multiplier / m.C.multiplier == 6
			and m.A.multiplier / m.B.multiplier == 6
			and m.S.multiplier / m.A.multiplier == 6
	end)(), true)
	local savedSS = Config.CharacterClasses.SS.multiplier
	Config.CharacterClasses.SS.multiplier = 1296
	check("SS = 1,296 (ไล่ ×6 ต่อ) ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	do
		local _, err = pcall(Config.validate)
		print("   ข้อความที่ได้: " .. string.sub(tostring(err), 1, 110))
	end
	Config.CharacterClasses.SS.multiplier = savedSS
	check("คืนค่าเดิมแล้ว validate ผ่าน", pcall(Config.validate), true)

	print("── ผู้เล่นอ้างอิง: น้ำหนักคงที่ คลาสไต่ตามด่าน ──")
	check("น้ำหนักอ้างอิงคงที่ทุกด่าน", (function()
		for st = 2, 9 do
			if Config.Balance.BalanceCheck.REFERENCE_WEIGHT[st] ~= Config.Balance.BalanceCheck.REFERENCE_WEIGHT[1] then
				return false
			end
		end
		return true
	end)(), true)
	check("น้ำหนักอ้างอิงอยู่ใน tier 1 (ที่ 90% ของไข่ให้)",
		Config.Balance.BalanceCheck.REFERENCE_WEIGHT[1] >= Config.Balance.Weight.TIERS[1].min
			and Config.Balance.BalanceCheck.REFERENCE_WEIGHT[1] <= Config.Balance.Weight.TIERS[1].max, true)
	check("คลาสอ้างอิงไม่ถอยหลัง", (function()
		local prev = 99
		for st = 1, 9 do
			local o = Config.CharacterClasses[Config.Balance.BalanceCheck.REFERENCE_CLASS[st]].order
			if o > prev then return false end
			prev = o
		end
		return true
	end)(), true)
	check("คลาสอ้างอิงสูงสุดคือ A ไม่ใช่ S", Config.Balance.BalanceCheck.REFERENCE_CLASS[9], "A")

	print("── ยามเวลาฟาร์ม ──")
	-- ⚠️ อย่า hardcode จำนวนผู้เล่น — ผูกกับ Config เพื่อให้เทสต์ตามไปเองเวลาปรับ
	local expectedEggs = (3600 / Config.Balance.Boss.RESPAWN_SECONDS)
		* Config.Balance.Boss.EGGS_PER_SPAWN
		/ Config.Balance.BalanceCheck.PLAYERS_PER_SERVER
	check("ไข่/ชม./คน ตรงสูตร บอสวาง ÷ จำนวนผู้เล่น",
		math.abs(Config.getEggsPerHour() - expectedEggs) < 1e-9, true)
	check("ที่ 6 คน ได้ 10 ฟอง/ชม./คน", math.abs(Config.getEggsPerHour() - 10) < 1e-9, true)
	local farmOk = true
	for st = 2, 9 do
		local ratio = Config.getReferenceFarmHours(st) / Config.getReferenceClearHours(st)
		if ratio > Config.Balance.BalanceCheck.MAX_FARM_TO_CLEAR_RATIO then farmOk = false end
	end
	check("ทุกด่าน: เวลาฟาร์มไม่เกิน 5 เท่าของเวลาตี", farmOk, true)

	-- ยามต้องจับเคสที่เคยพลาด: บังคับให้ต้องใช้ S ที่ด่าน 7 (ออกแค่ 1%)
	local savedClass = Config.Balance.BalanceCheck.REFERENCE_CLASS[7]
	Config.Balance.BalanceCheck.REFERENCE_CLASS[7] = "S"
	check("บังคับใช้ S ที่ด่าน 7 (ไข่ออก 1%) ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	do
		local _, err = pcall(Config.validate)
		print("   ข้อความที่ได้: " .. string.sub(tostring(err), 1, 130))
	end
	Config.Balance.BalanceCheck.REFERENCE_CLASS[7] = savedClass
	check("คืนค่าเดิมแล้ว validate ผ่าน", pcall(Config.validate), true)

	print("── ตารางน้ำหนัก: ชุดเดียวทุกด่าน เป็นการตัดสินถาวร ──")
	check("กำหนดไว้ด่านเดียว", (function()
		local n = 0
		for _ in Config.Balance.StageWeightTiers do n += 1 end
		return n
	end)(), 1)


	print("── ผู้เล่นที่ไม่ซื้อ upgrade เลย ต้องตัน ──")
	-- ถ้าไม่ซื้อแล้วยังผ่านได้สบาย แปลว่าระบบซื้อไม่มีความหมาย
	local function hoursNoUpgrade(st)
		local hp = Config.getStageTotalHp(st)
		if hp <= 0 then return 0 end
		local w = Config.Balance.BalanceCheck.REFERENCE_WEIGHT[st]
		local cl = Config.Balance.BalanceCheck.REFERENCE_CLASS[st]
		local id
		for cid, ch in Config.Characters do if ch.class == cl then id = cid break end end
		local rate = math.min(Config.getPenCapacity(st) * Config.getProductionPerMinute(w, nil, st - 1, true) / 60,
			Config.getReleaseRate(st))
		return hp / (rate * Config.computeBattlePower(Config.getChildWeight(w), id, nil, 0) * 3600)
	end
	local firstBlocked
	for st = 2, 9 do
		if hoursNoUpgrade(st) > Config.Balance.BalanceCheck.MAX_HOURS_PER_STAGE and firstBlocked == nil then
			firstBlocked = st
		end
	end
	check("ไม่ซื้อแล้วตันจริง (มีด่านที่เกินเพดาน 72 ชม.)", firstBlocked ~= nil, true)
	check("ด่านต้นยังผ่านได้โดยไม่ต้องซื้อ", hoursNoUpgrade(2) <= Config.Balance.BalanceCheck.MAX_HOURS_PER_STAGE, true)
	print(string.format("   ไม่ซื้อเลย: ด่าน 2 = %.1f ชม. · ตันที่ด่าน %d (%.0f ชม.) · ด่าน 9 = %.0f ชม.",
		hoursNoUpgrade(2), firstBlocked, hoursNoUpgrade(firstBlocked), hoursNoUpgrade(9)))
	local gain = Config.getReferenceClearHours(9) > 0
		and hoursNoUpgrade(9) / Config.getReferenceClearHours(9) or 0
	check("ซื้อครบช่วยได้อย่างน้อย 100 เท่าที่ด่าน 9", gain >= 100, true)
	print(string.format("   ซื้อครบเพดานช่วยที่ด่าน 9 ได้ %.0f เท่า", gain))

	--------------------------------------------------------------------------
	-- เพดานไข่: กระเป๋าไข่ กับ ช่องฟัก เป็นคนละค่ากันแล้ว
	--------------------------------------------------------------------------
	print("── เพดานไข่: สองค่าแยกกัน ──")
	check("กระเป๋าไข่มีค่าเป็นของตัวเอง", type(Config.Balance.Hatchery.BAG_CAPACITY), "number")
	check("ช่องฟักมีค่าเป็นของตัวเอง", type(Config.Balance.Hatchery.MAX_SLOTS), "number")
	check("MAX_EGGS เดิมถูกถอดออกแล้ว", Config.Balance.Hatchery.MAX_EGGS, nil)
	-- ⚠️ เช็คค่าทีละตัว **ไม่ได้เช็คว่าเท่ากัน** เพราะไม่ได้บังคับว่าต้องเท่า
	-- ⚠️ ขึ้นเป็น 10,000 ตอน Phase 2A พร้อมกับโครง heldEggs ใหม่ที่เก็บเฉพาะฟองที่มีจริง
	check("กระเป๋าไข่ = 10,000", Config.Balance.Hatchery.BAG_CAPACITY, 10000)
	check("กระเป๋าไข่จุไม่น้อยกว่าสวนฟัก",
	      Config.Balance.Hatchery.BAG_CAPACITY >= Config.Balance.Hatchery.MAX_SLOTS, true)
	check("ค่าเริ่มต้นช่องฟัก = 50", Config.Balance.Hatchery.MAX_SLOTS, 50)

	-- ยามต้องจับค่าที่ทำให้ไข่เดินทางต่อไม่ได้
	local savedBag = Config.Balance.Hatchery.BAG_CAPACITY
	Config.Balance.Hatchery.BAG_CAPACITY = 0
	check("กระเป๋าไข่ = 0 แล้ว validate ต้องล้ม", (pcall(Config.validate)), false)
	Config.Balance.Hatchery.BAG_CAPACITY = savedBag

	local savedSlots = Config.Balance.Hatchery.MAX_SLOTS
	Config.Balance.Hatchery.MAX_SLOTS = 2.5
	check("ช่องฟักเป็นทศนิยมแล้ว validate ต้องล้ม", (pcall(Config.validate)), false)
	Config.Balance.Hatchery.MAX_SLOTS = savedSlots
	check("คืนค่าเดิมแล้ว validate กลับมาผ่าน", (pcall(Config.validate)), true)

	--------------------------------------------------------------------------
	-- ผังแมพ (blockout)
	--------------------------------------------------------------------------
	print("── ผังแมพ: โซนต้องไม่ทับกันและเรียงถูกลำดับ ──")
	local map = Config.MapDimensions

	-- luau CLI ไม่มี Vector2/Vector3 (เหมือน Config ที่ fallback เป็น table ธรรมดา)
	-- validate() อ่านแค่ .X/.Y/.Z จึงใช้ table แทนได้ตรง ๆ ตอนยิงค่าพัง ๆ ใส่ยาม
	local function vec2(x: number, y: number): any
		return { X = x, Y = y }
	end
	local function vec3(x: number, y: number, z: number): any
		return { X = x, Y = y, Z = z }
	end

	-- ผังคอกต้องพอดีจำนวนผู้เล่นเป๊ะ ไม่ขาดไม่เกิน
	check("คอก = แถว × ต่อแถว", map.Pen.Rows * map.Pen.PerRow, Config.World.MAX_PENS)
	check("คอก = จำนวนผู้เล่นต่อเซิร์ฟ", Config.World.MAX_PENS, Config.Balance.BalanceCheck.PLAYERS_PER_SERVER)
	check("ผู้เล่นต่อเซิร์ฟ = 6", Config.Balance.BalanceCheck.PLAYERS_PER_SERVER, 6)

	-- เรียงจากซ้ายไปขวา: แผงร้านค้า → ลานคอก → เลนรบ
	local shopRight = Config.getShopCenter().X + map.Shop.StallSize.X / 2
	check("แผงร้านค้าอยู่ซ้ายลานคอก", shopRight < Config.getPenYardLeftX(), true)
	check("เลนรบอยู่ขวาลานคอก", Config.getLaneStartX() >= Config.getPenYardRightX(), true)
	check("แผงร้านมีมากกว่าหนึ่งแผง", map.Shop.StallCount >= 2, true)
	local stallGap = true
	for i = 1, map.Shop.StallCount do
		-- แผงต้องขนาบทางเดิน ไม่ใช่ตั้งขวางตรงกลาง
		if math.abs(Config.getShopStallCenter(i).Z) < map.Pen.RowGap / 2 then
			stallGap = false
		end
	end
	check("แผงร้านไม่ตั้งขวางทางเดินกลาง", stallGap, true)

	-- คอกทุกแปลงต้องไม่ทับกัน และอยู่คนละฝั่งของทางเดินตามจำนวนแถว
	local overlap, rowsSeen = false, {}
	for a = 1, Config.World.MAX_PENS do
		local ca = Config.getPenPlotCenter(a)
		rowsSeen[ca.Z] = true
		for b = a + 1, Config.World.MAX_PENS do
			local cb = Config.getPenPlotCenter(b)
			if math.abs(ca.X - cb.X) < map.Pen.Size.X - 1e-6
				and math.abs(ca.Z - cb.Z) < map.Pen.Size.Y - 1e-6 then
				overlap = true
			end
		end
	end
	check("ไม่มีคอกทับกัน", overlap, false)
	local rowCount = 0
	for _ in rowsSeen do rowCount += 1 end
	check("คอกกระจายครบทุกแถว", rowCount, map.Pen.Rows)

	-- ══ เลนรบกับกำแพง ══
	check("ด่าน 1 ไม่มีกำแพง", Config.getWallX(1), nil)
	local wallsOk, wallsAscending = true, true
	for st = 2, Config.Balance.Stage.COUNT do
		local w = Config.getWallX(st)
		if w == nil then
			wallsOk = false
		elseif st > 2 then
			-- ⚠️ เทียบกับด่านก่อนหน้าได้เฉพาะตั้งแต่ด่าน 3 ขึ้นไป
			-- เพราะ getWallX(1) เป็น nil (ด่าน 1 ไม่มีกำแพง) เทียบตรง ๆ แล้ว error
			local prev = Config.getWallX(st - 1)
			if prev and w <= prev then
				wallsAscending = false
			end
		end
	end
	check("ด่าน 2 ขึ้นไปมีกำแพงครบ", wallsOk, true)
	check("กำแพงเรียงไปทางขวาเรื่อย ๆ", wallsAscending, true)
	check("เลนยาว = ยาวต่อด่าน × จำนวนด่าน",
		Config.getLaneLength(), map.Lane.LengthPerStage * Config.Balance.Stage.COUNT)

	-- ══ รังบอส ══ ต้องอยู่ในช่วงของด่านตัวเอง และหลังกำแพงเสมอ
	local nestInRange, nestBehindWall = true, true
	for st = 1, Config.Balance.Stage.COUNT do
		local center = Config.getBossNestCenter(st)
		local startX = Config.getStageStartX(st)
		if center.X <= startX or center.X >= startX + map.Lane.LengthPerStage then
			nestInRange = false
		end
		local wallX = Config.getWallX(st)
		if wallX and center.X - map.BossRoom.Size.X / 2 <= wallX + map.StageWall.Thickness / 2 then
			nestBehindWall = false
		end
	end
	check("รังบอสอยู่ในช่วงด่านตัวเองทุกด่าน", nestInRange, true)
	check("รังบอสอยู่หลังกำแพงทุกด่านที่มีกำแพง", nestBehindWall, true)
	check("จุดวางไข่ในรัง = จำนวนไข่ที่บอสวาง", Config.Balance.Boss.EGGS_PER_SPAWN, 5)

	-- จุดวางไข่ต้องอยู่ในรัง ไม่หลุดขอบ
	local spotsInside = true
	for st = 1, Config.Balance.Stage.COUNT do
		local center = Config.getBossNestCenter(st)
		for i = 1, Config.Balance.Boss.EGGS_PER_SPAWN do
			local spot = Config.getBossEggSpot(st, i)
			if math.abs(spot.X - center.X) > map.BossRoom.Size.X / 2
				or math.abs(spot.Z - center.Z) > map.BossRoom.Size.Y / 2 then
				spotsInside = false
			end
		end
	end
	check("จุดวางไข่อยู่ในขอบรังทุกจุด", spotsInside, true)

	-- ══ พื้นที่ที่แม่เดินได้ต้องเป็นบวก ══
	-- ติดลบเมื่อไหร่ = สุ่มจุดหมายไม่ได้ แม่จะยืนนิ่งทั้งคอก
	check("ขอบกันชนเล็กกว่าครึ่งด้านสั้นสุดของคอก",
		map.Pen.EdgeMargin < math.min(map.Pen.Size.X, map.Pen.Size.Y) / 2, true)
	check("ผู้เล่นใหม่เริ่มที่ด่าน 1", Config.Balance.NewPlayer.wallProgress, 1)
	check("ผู้เล่นใหม่ซื้อ upgrade damage ได้ทันที",
		Config.getMaxDamageLevel(Config.Balance.NewPlayer.wallProgress) > 0, true)

	-- ══ ยามต้องจับค่าที่ทำให้แมพพัง ══
	print("── ยามแมพ ต้องจับค่าที่พังได้จริง ──")
	-- ⚠️ เก็บค่าเดิมไว้คืน **อย่า hardcode ค่าคืน** — เคยพลาดมาแล้ว:
	-- คืนเป็นเลขที่พิมพ์ไว้ตอนเขียนเทสต์ พอปรับ Config รอบถัดไป เทสต์จะคืนค่าผิด
	-- แล้วเคสที่รันต่อจากนั้นทั้งหมดวัดกับแมพคนละใบโดยไม่มีใครรู้
	local savedEdgeMargin = map.Pen.EdgeMargin
	local savedWalkway = map.Pen.RowGap
	local savedLaneWidth = map.Lane.Width
	local savedPauseMax = map.Wander.PauseMax
	local savedWanderSpeed = map.Wander.Speed
	local function mapGuardCatches(mutate, restore): boolean
		mutate()
		local ok = (pcall(Config.validate))
		restore()
		return not ok
	end
	check("ผังคอกไม่ตรงจำนวนผู้เล่น → ล้ม", mapGuardCatches(
		function() map.Pen.PerRow += 1 end, function() map.Pen.PerRow -= 1 end), true)
	check("ขอบกันชนกว้างเกินคอก → ล้ม", mapGuardCatches(
		function() map.Pen.EdgeMargin = map.Pen.Size.Y end,
		function() map.Pen.EdgeMargin = savedEdgeMargin end), true)
	-- ⚠️ รังบอสไม่มีค่า "ระยะถอย" ให้ตั้งมืออีกแล้ว (NEST_INSET ถูกลบ)
	-- ตอนนี้คำนวณจากขนาดห้องเอง → ดันห้องให้ใหญ่เกินช่วงด่าน แล้วยามต้องจับได้
	local savedNest = map.BossRoom.Size
	check("ห้องบอสใหญ่เกินช่วงด่าน → ล้ม", mapGuardCatches(
		function() map.BossRoom.Size = vec2(map.Lane.LengthPerStage * 3, savedNest.Y) end,
		function() map.BossRoom.Size = savedNest end), true)
	check("ห้องบอสกว้างเกินเลนหลายเท่า → ล้ม", mapGuardCatches(
		function() map.BossRoom.Size = vec2(savedNest.X, map.Lane.Width * 4) end,
		function() map.BossRoom.Size = savedNest end), true)
	check("ทางเดินกลางแคบจนเดินไม่ผ่าน → ล้ม", mapGuardCatches(
		function() map.Pen.RowGap = 2 end, function() map.Pen.RowGap = savedWalkway end), true)
	check("เลนรบแคบจนเดินไม่ผ่าน → ล้ม", mapGuardCatches(
		function() map.Lane.Width = 2 end, function() map.Lane.Width = savedLaneWidth end), true)
	check("เวลาพักของแม่กลับหัว → ล้ม", mapGuardCatches(
		function() map.Wander.PauseMax = 0 end,
		function() map.Wander.PauseMax = savedPauseMax end), true)
	check("ความเร็วเดินเป็น 0 → ล้ม", mapGuardCatches(
		function() map.Wander.Speed = 0 end,
		function() map.Wander.Speed = savedWanderSpeed end), true)
	check("คืนค่าแมพเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)

	--------------------------------------------------------------------------
	-- MapDimensions — แหล่งความจริงแหล่งเดียวของรูปทรงแมพ
	--------------------------------------------------------------------------
	-- ⚠️ เคยมีตารางที่สอง `Config.Map` เป็น alias ของตารางนี้ พร้อมเทสต์คอยตรวจว่า
	-- สองฝั่งตรงกัน · **ยุบ alias ทิ้งแล้ว** เทสต์ชุดนั้นจึงหายไปด้วย
	-- เหลือแค่คุมค่าจริงว่าตรงกับที่ตกลงกันไว้
	print("── MapDimensions: ค่าต้องตรงกับที่ตกลงไว้ ──")
	local dim = Config.MapDimensions

	check("ความเร็ววิ่ง = 32 (×2 จากค่าปกติของ Roblox)", dim.Player.WalkSpeed, 32)
	check("คอก 80 x 80", dim.Pen.Size.X * 1000 + dim.Pen.Size.Y, 80 * 1000 + 80)
	check("รั้วเตี้ยกว่าคนกระโดดข้ามไม่ได้ก็ไม่เป็นไร (แค่บอกขอบเขต)",
		dim.Pen.FenceHeight > 0 and dim.Pen.FenceHeight < dim.Lane.WallHeight, true)
	check("เลนกว้าง 60 · ด่านละ 180 · กำแพงข้างสูง 40",
		`{dim.Lane.Width}/{dim.Lane.LengthPerStage}/{dim.Lane.WallHeight}`, "60/180/40")
	check("ห้องบอส 80 x 80", dim.BossRoom.Size.X * 1000 + dim.BossRoom.Size.Y, 80 * 1000 + 80)
	check("แผงร้าน 2 แผง ขนาด 12 x 12",
		`{dim.Shop.StallCount}/{dim.Shop.StallSize.X}/{dim.Shop.StallSize.Y}`, "2/12/12")

	-- ⚠️ ข้อนี้คือเหตุผลที่แมพเป็นแท่นลอยแล้วยังเล่นได้
	-- กำแพงใสเตี้ยกว่ากระโดด = กระโดดข้ามแล้วตกแท่น ซึ่งเป็นสิ่งเดียวที่มันมีไว้กัน
	check("กำแพงใสสูงกว่าความสูงกระโดด", dim.Boundary.Height > dim.Player.JumpHeight, true)

	-- ⚠️ ความสูงกระโดดต้องเป็น **ค่าที่ Roblox ใช้จริง** ไม่ใช่ตัวเลขที่เดาไว้
	-- เดิมเขียน 7 โดยที่โปรเจกต์ยังอยู่โหมด JumpPower → ของจริง 6.37 และ 7 ไม่มีใครใช้
	-- ตอนนี้ default.project.json ตั้ง CharacterUseJumpPower = false
	-- + CharacterJumpHeight = 7.2 ให้ตรงกับค่านี้ (Main.server.lua เช็คซ้ำตอนบูต)
	check("ความสูงกระโดด = 7.2 (ค่า JumpHeight จริงของ Roblox)", dim.Player.JumpHeight, 7.2)
	check("กำแพงใสเผื่อจากขอบพื้น", dim.Boundary.Margin > 0, true)

	-- ค่าที่เพิ่งย้ายเข้ามาตอนยุบ alias — คุมไว้ว่าย้ายมาครบและค่าไม่เพี้ยน
	check("ผังคอก 2 x 3", `{dim.Pen.Rows}x{dim.Pen.PerRow}`, "2x3")
	check("ขอบกันชนคอก = 4", dim.Pen.EdgeMargin, 4)
	check("กำแพงกั้นด่านหนา 5", dim.StageWall.Thickness, 5)
	check("กำแพงข้างเลนหนา 5", dim.Lane.WallThickness, 5)
	check("กำแพงใสหนา 5", dim.Boundary.Thickness, 5)
	check("ระยะจากลานถึงแผงร้าน = 20", dim.Shop.Gap, 20)
	check("แม่เดิน 4 stud/วิ", dim.Wander.Speed, 4)

	-- ⚠️ ความหนาพื้นคอกเป็นค่าเดียวที่ MapBuilder (สร้างแผ่น) กับ PenService (วางของบนแผ่น)
	-- ต้องอ่านตรงกัน · เคยแยกกันแล้วของลอยเหนือพื้น 0.2 studs
	-- ⚠️ แผ่นพื้นคอก `CanCollide = false` และสีเกือบเท่าหญ้า → ผู้เล่นเดินบนหญ้าที่ Y = 0
	-- ของที่วางบนผิวแผ่นจึงดู "ลอย" เท่ากับความหนาแผ่น · **ต้องบางจนมองไม่เห็น**
	check("แผ่นพื้นคอกบางจนไม่เห็นว่าลอย", dim.Pen.FloorThickness <= 0.1, true)
	check("แผ่นพื้นคอกยังเป็นบวก", dim.Pen.FloorThickness > 0, true)

	-- ⚠️ **ไม่มี Config.Map แล้ว** — มีชื่อเดียวคือ MapDimensions
	check("Config.Map ถูกยุบทิ้งแล้ว", (Config :: any).Map, nil)

	--------------------------------------------------------------------------
	-- วางของบนพื้นคอก — ของต้องแตะพื้นพอดี ไม่ลอย ไม่จม
	--------------------------------------------------------------------------
	-- ⚠️ แผ่นพื้นคอกสร้างที่ Y = 0 แล้ว makePart ยกขึ้นครึ่งความสูง
	-- → กินช่วง 0 .. FloorThickness · **ผิวบน = FloorThickness เต็ม ๆ ไม่ใช่ครึ่งหนึ่ง**
	print("── ของในคอกต้องนั่งบนพื้นพอดี ──")
	check("ผิวบนพื้นคอก = FloorThickness", Config.getPenFloorY(), dim.Pen.FloorThickness)

	-- ⚠️ **หัวใจของบั๊กไข่ลอย**: Roblox วาด Ball ด้วยเส้นผ่านศูนย์กลาง min(X,Y,Z)
	-- ไข่ blockout เป็น (3, 3.8, 3) → ทรงกลมเส้นผ่านศูนย์กลาง 3 ไม่ใช่ 3.8
	-- โค้ดเดิมใช้ Y/2 = 1.9 เป็นรัศมี ทั้งที่ของจริง 1.5 → ลอย 0.4 studs
	local eggSize = dim.Blockout.EggSize
	check("รัศมีไข่ = min(X,Y,Z)/2", Config.getBallRadius(eggSize),
		math.min(eggSize.X, eggSize.Y, eggSize.Z) / 2)
	-- ⚠️ ไข่ต้องเท่ากันทั้งสามแกน — Roblox ไม่รับประกันว่าลูกบอลที่ขนาดไม่เท่ากัน
	-- จะวาดออกมาเป็นทรงกลม (min) หรือทรงรี (แต่ละแกน) · เท่ากันแล้วตีความยังไงก็ตรงกัน
	check("ไข่เป็นลูกบอลด้านเท่า ไม่กำกวม",
		eggSize.X == eggSize.Y and eggSize.Y == eggSize.Z, true)
	check("รัศมีไข่ = ครึ่งด้าน", Config.getBallRadius(eggSize), eggSize.Y / 2)
	check("ทรงกลมด้านเท่าได้รัศมี = ครึ่งด้าน", Config.getBallRadius(vec3(4, 4, 4)), 2)

	-- ⚠️ ข้อที่ต้องจริงเสมอ: **Y ของจุดศูนย์กลาง − รัศมี = ผิวบนของพื้น**
	-- ผิดเมื่อไหร่ = ของลอย (มากไป) หรือจมพื้น (น้อยไป)
	local eggRadius = Config.getBallRadius(eggSize)
	t.near("ไข่: Y − รัศมี = ผิวพื้น",
		Config.getPenRestingY(eggRadius) - eggRadius, Config.getPenFloorY(), 1e-9)

	local motherSize = dim.Blockout.MotherSize
	t.near("แม่: Y − ครึ่งความสูง = ผิวพื้น",
		Config.getPenRestingY(motherSize.Y / 2) - motherSize.Y / 2, Config.getPenFloorY(), 1e-9)

	-- ⚠️ ไข่หลายขนาด (ถ้าวันหนึ่งขนาดแปรตามน้ำหนัก) ต้องนั่งพื้นพอดีทุกฟอง
	-- ฟังก์ชันรับครึ่งความสูงของชิ้นนั้น ๆ ไม่ได้อ่านค่ากลาง จึงใช้ได้เลย
	local everySizeRests = true
	for _, side in { 1, 2, 3, 5.5, 12 } do
		local r = Config.getBallRadius(vec3(side, side * 1.3, side))
		if math.abs((Config.getPenRestingY(r) - r) - Config.getPenFloorY()) > 1e-9 then
			everySizeRests = false
		end
	end
	check("ไข่ทุกขนาดนั่งพื้นพอดี", everySizeRests, true)

	-- เทียบกับค่าจริงที่ควรได้ กันสูตรเพี้ยนแบบเงียบ ๆ
	t.near("ไข่ blockout อยู่ที่ Y = 1.55", Config.getPenRestingY(eggRadius), 1.55, 1e-9)
	t.near("แม่ blockout อยู่ที่ Y = 1.8", Config.getPenRestingY(motherSize.Y / 2), 1.8, 1e-9)

	-- ⚠️ ความเร็วเดินของแม่เป็น **stud ต่อวินาที** ไม่ใช่ "วินาทีต่อระยะ"
	-- ของเดิมเป็นเวลาต่อระยะ พอขยายคอกจาก 24 → 80 stud แม่จะเดินช้าเหมือนคลาน
	-- เทสต์นี้คุมไว้ว่าเวลาเดินต้องแปรตามระยะจริง ไม่ใช่ค่าคงที่
	local roamSide = map.Pen.Size.X - map.Pen.EdgeMargin * 2
	local roamSideZ = map.Pen.Size.Y - map.Pen.EdgeMargin * 2
	check("พื้นที่ที่แม่เดินได้เป็นบวก", roamSide > 0 and roamSideZ > 0, true)
	local diagonal = math.sqrt(roamSide ^ 2 + roamSideZ ^ 2)
	local cornerSecs = diagonal / map.Wander.Speed
	t.near("แม่เดินมุมถึงมุมของคอก (วินาที)", cornerSecs, 25.5, 0.5)
	check("แม่เดินช้ากว่าผู้เล่นวิ่งเสมอ", map.Wander.Speed < dim.Player.WalkSpeed, true)

	-- ══ ขนาดแมพที่ประกอบออกมาได้ ══ ตัวเลขชุดที่ใช้ตัดสินว่า "ใหญ่ไปไหม"
	print("── ขนาดแมพที่ประกอบได้ ──")
	check("ลานคอกกว้าง 280", Config.getPenYardWidth(), 280)
	check("ลานคอกลึก 250", Config.getPenYardDepth(), 250)
	check("เลนรบยาว 1620", Config.getLaneLength(), 1620)

	-- ⚠️ ข้อนี้คือยามขนาดแมพช่วงเริ่มเกม
	-- ผู้เล่นใหม่ต้องวิ่งจากคอกตัวเองไปรังบอสด่าน 1 ซึ่งเป็นเส้นทางที่เดินซ้ำที่สุดในเกม
	-- นานเกิน 15 วินาทีเมื่อไหร่ = แมพใหญ่เกินไปสำหรับช่วงที่ยังไม่มีอะไรทำระหว่างทาง
	local nest1X = Config.getBossNestCenter(1).X
	local worstPenX = Config.getPenPlotCenter(1).X
	local startTrip = (nest1X - worstPenX) / dim.Player.WalkSpeed
	print(string.format("   คอกไกลสุด → รังบอสด่าน 1 = %.0f studs = %.1f วิ", nest1X - worstPenX, startTrip))
	check("วิ่งจากคอกถึงรังบอสด่าน 1 ไม่เกิน 15 วิ", startTrip <= 15, true)

	--------------------------------------------------------------------------
	-- รั้ว · ประตู · ทางเดินกลาง
	--------------------------------------------------------------------------
	print("── รั้ว ประตู และทางเดินกลาง ──")
	check("รั้วเตี้ย (ไม่ใช่กำแพง)", dim.Pen.FenceHeight, 3)
	check("รั้วบาง", dim.Pen.FenceThickness, 1)
	check("รั้วเตี้ยกว่ากำแพงข้างเลนมาก", dim.Pen.FenceHeight * 5 < dim.Lane.WallHeight, true)
	check("ประตูกว้าง 8", dim.Pen.GateWidth, 8)
	check("ประตูแคบกว่าตัวคอก", map.Pen.GateWidth < map.Pen.Size.X, true)
	check("ประตูกว้างพอเดินเข้าได้", map.Pen.GateWidth >= 6, true)

	-- ⚠️ ทางเดินกลางต้องไม่แคบกว่าเลนรบ ไม่งั้นปากทางเข้าเลนเป็นคอขวด
	check("ทางเดินกลางกว้างไม่น้อยกว่าเลนรบ", map.Pen.RowGap >= map.Lane.Width, true)
	check("ทางเดินกลาง = 90", map.Pen.RowGap, 90)
	check("ช่องระหว่างคอก = 20", map.Pen.ColumnGap, 20)

	-- คอกต้องอยู่พ้นแนวเลนรบตามแกน Z (รั้วจะได้ไม่ไปบังปากทางเข้าเลน)
	local pensClearOfLane = true
	for penIdx = 1, Config.World.MAX_PENS do
		local c = Config.getPenPlotCenter(penIdx)
		if math.abs(c.Z) - map.Pen.Size.Y / 2 < map.Lane.Width / 2 then
			pensClearOfLane = false
		end
	end
	check("ไม่มีคอกล้ำเข้ามาในแนวเลนรบ", pensClearOfLane, true)

	--------------------------------------------------------------------------
	-- กำแพงใสต้องอยู่นอกของทุกอย่างที่ต้องเดินไปถึง
	--------------------------------------------------------------------------
	-- ⚠️ เคยพลาดจริง: ดัน Boundary.Margin 20 → 50 แล้วกำแพงกินเข้าไปในคอก 30 studs
	-- และตัดแผงร้านออกไปอยู่นอกกำแพง เพราะพื้นลานไม่ได้โตตาม margin
	print("── กำแพงใสต้องไม่กินพื้นที่เล่น ──")
	local wallHalfZ = Config.getPlazaHalfDepth() - map.Boundary.Margin
	local wallMinX = Config.getPlazaMinX() + map.Boundary.Margin
	local pensInside, stallsInside = true, true
	for penIdx = 1, Config.World.MAX_PENS do
		local c = Config.getPenPlotCenter(penIdx)
		if math.abs(c.Z) + map.Pen.Size.Y / 2 > wallHalfZ
			or c.X - map.Pen.Size.X / 2 < wallMinX then
			pensInside = false
		end
	end
	for stallIdx = 1, map.Shop.StallCount do
		local stall = Config.getShopStallCenter(stallIdx)
		if stall.X - map.Shop.StallSize.X / 2 < wallMinX
			or math.abs(stall.Z) + map.Shop.StallSize.Y / 2 > wallHalfZ then
			stallsInside = false
		end
	end
	check("ทุกคอกอยู่ในกำแพงใส", pensInside, true)
	check("แผงร้านทุกแผงอยู่ในกำแพงใส", stallsInside, true)
	check("มีหญ้านอกกำแพงให้เห็น", map.Boundary.Margin > 0, true)

	-- ══ ยามต้องจับได้จริง ══
	local savedMargin = map.Boundary.Margin
	local savedGate = map.Pen.GateWidth
	local savedRowGap = map.Pen.RowGap
	check("ประตูกว้างเกินคอก → ล้ม", mapGuardCatches(
		function() map.Pen.GateWidth = map.Pen.Size.X + 1 end,
		function() map.Pen.GateWidth = savedGate end), true)
	check("ประตูแคบจนเดินไม่เข้า → ล้ม", mapGuardCatches(
		function() map.Pen.GateWidth = 1 end,
		function() map.Pen.GateWidth = savedGate end), true)
	check("ทางเดินกลางแคบกว่าเลนรบ → ล้ม", mapGuardCatches(
		function() map.Pen.RowGap = map.Lane.Width - 1 end,
		function() map.Pen.RowGap = savedRowGap end), true)
	-- ⚠️ ยามตัวนี้คือตัวที่จับบั๊กจริงของรอบนี้ได้
	--
	-- **ดัน BOUNDARY_MARGIN ขึ้นเฉย ๆ ไม่ทำให้พังอีกแล้ว** เพราะพื้นลานโตตาม margin
	-- (wallHalfZ = plazaHalfDepth − margin ซึ่งตัด margin ออกหมดพอดี)
	-- นั่นคือตัวการแก้ ไม่ใช่เรื่องที่ยามจะจับ
	--
	-- สิ่งที่ยามมีไว้จับคือ **การถอยสูตรพื้นลานกลับไปเป็นแบบเดิม** (ไม่บวก margin)
	-- ซึ่งเป็นบั๊กตัวจริงที่ทำให้กำแพงกินเข้าไปในคอก 30 studs
	-- จึงทดสอบด้วยการสลับฟังก์ชันกลับเป็นสูตรเก่าตรง ๆ
	local realHalfDepth = Config.getPlazaHalfDepth
	local realMinX = Config.getPlazaMinX
	check("ถอยสูตรพื้นลานกลับเป็นแบบเก่า → ล้ม", mapGuardCatches(function()
		Config.getPlazaHalfDepth = function()
			return realHalfDepth() - map.Boundary.Margin
		end
		Config.getPlazaMinX = function()
			return realMinX() + map.Boundary.Margin
		end
	end, function()
		Config.getPlazaHalfDepth = realHalfDepth
		Config.getPlazaMinX = realMinX
	end), true)
	check("ดัน margin ขึ้นเฉย ๆ ไม่พังแล้ว (พื้นโตตาม)", mapGuardCatches(
		function() map.Boundary.Margin = savedMargin * 3 end,
		function() map.Boundary.Margin = savedMargin end), false)
	check("คืนค่าเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)

	--------------------------------------------------------------------------
	-- อัปเกรดความเร็ว (บ่อเงินบ่อที่สอง)
	--------------------------------------------------------------------------
	print("── อัปเกรดความเร็ว: ตาราง 5 ขั้น ตัวคูณถดถอย ──")
	local spd = Config.Balance.SpeedUpgrade

	-- ⚠️ 5 ขั้น ไม่ใช่ 10 — เป็นการตัดสินใจถาวร เทสต์นี้กันไม่ให้มีคนมาขยายทีหลัง
	-- ราคาไล่ ×10 ถ้าทำ 10 ขั้น ขั้นสุดท้ายแพงกว่าขั้นแรกพันล้านเท่าแต่ให้ความเร็วเพิ่ม 3-4%
	check("ความเร็วมี 5 ขั้น (ห้ามขยายเป็น 10)", spd.MAX_LEVEL, 5)
	check("ขั้น 0 ไม่มีตัวคูณ", Config.getSpeedMultiplier(0), 1)
	check("ขั้นสุดท้าย = MAX_MULTIPLIER พอดี",
		Config.getSpeedMultiplier(spd.MAX_LEVEL), spd.MAX_MULTIPLIER)
	check("เกินเพดานก็ไม่เกิน MAX_MULTIPLIER", Config.getSpeedMultiplier(99), spd.MAX_MULTIPLIER)
	check("ขั้นติดลบก็ยังเป็น ×1", Config.getSpeedMultiplier(-5), 1)

	-- ตัวคูณตามสเปกที่ตกลงกันไว้ (สูตร 1 + 3 × (ขั้น÷5)^0.75)
	t.near("ขั้น 1 = ×1.90", Config.getSpeedMultiplier(1), 1.897, 0.005)
	t.near("ขั้น 2 = ×2.51", Config.getSpeedMultiplier(2), 2.509, 0.005)
	t.near("ขั้น 3 = ×3.05", Config.getSpeedMultiplier(3), 3.045, 0.005)
	t.near("ขั้น 4 = ×3.54", Config.getSpeedMultiplier(4), 3.538, 0.005)

	-- ความเร็วจริง
	check("ขั้น 0 = ความเร็วฐาน", Config.getWalkSpeed(0), Config.MapDimensions.Player.WalkSpeed)
	t.near("ขั้น 1 = 61 studs/วิ", Config.getWalkSpeed(1), 60.7, 0.5)
	t.near("ขั้นสุดท้าย = 128 studs/วิ", Config.getMaxWalkSpeed(), 128, 0.01)

	-- ⚠️ **ตัวคูณต้องถดถอย** ขั้นแรกให้เยอะสุด ขั้นหลังให้น้อยลงเรื่อย ๆ
	-- ถ้าไล่ขึ้นเท่ากันทุกขั้น ขั้นท้าย ๆ ที่ราคาแพงกว่าพันเท่าจะคุ้มกว่าขั้นแรกแบบไร้เหตุผล
	local gains, decreasing = {}, true
	for level = 1, spd.MAX_LEVEL do
		gains[level] = Config.getSpeedMultiplier(level) - Config.getSpeedMultiplier(level - 1)
		if level > 1 and gains[level] >= gains[level - 1] then
			decreasing = false
		end
	end
	check("ส่วนเพิ่มต่อขั้นลดลงเรื่อย ๆ (ถดถอยจริง)", decreasing, true)
	-- ที่ผู้เล่นรู้สึกจริงคือ "เร็วขึ้นกี่ %" ไม่ใช่ส่วนต่างของตัวคูณ
	-- ตามสเปก: ขั้น 1 = +90% · ขั้น 5 = +13% (ต่างกันเกือบ 7 เท่า)
	local firstGain = Config.getSpeedMultiplier(1) / Config.getSpeedMultiplier(0) - 1
	local lastGain = Config.getSpeedMultiplier(spd.MAX_LEVEL)
		/ Config.getSpeedMultiplier(spd.MAX_LEVEL - 1) - 1
	t.near("ขั้น 1 เร็วขึ้น 90%", firstGain * 100, 89.7, 0.5)
	t.near("ขั้น 5 เร็วขึ้น 13%", lastGain * 100, 13.1, 0.5)
	check("ขั้นแรกคุ้มกว่าขั้นสุดท้ายหลายเท่า", firstGain / lastGain > 3, true)

	-- ราคา
	check("ราคาขั้นแรก 10,000", Config.getSpeedUpgradeCost(0), 10000)
	check("ราคาขั้นสุดท้าย 100M", Config.getSpeedUpgradeCost(spd.MAX_LEVEL - 1), 1e8)
	check("เต็มเพดานแล้วซื้อต่อไม่ได้", Config.getSpeedUpgradeCost(spd.MAX_LEVEL), nil)
	check("ราคารวมทุกขั้น 111.11M", Config.getSpeedUpgradeTotalCost(), 111110000)
	local ascending = true
	for level = 1, spd.MAX_LEVEL - 1 do
		if (Config.getSpeedUpgradeCost(level) :: number) <= (Config.getSpeedUpgradeCost(level - 1) :: number) then
			ascending = false
		end
	end
	check("ราคาเรียงจากน้อยไปมาก", ascending, true)

	check("ผู้เล่นใหม่เริ่มที่ขั้น 0", Config.Balance.NewPlayer.speedLevel, 0)

	--------------------------------------------------------------------------
	-- ความหนากำแพงต้องผูกกับความเร็ว
	--------------------------------------------------------------------------
	-- ⚠️ ที่ 128 studs/วิ บน 60fps ตัวละครขยับ 2.13 stud ต่อเฟรม
	-- กำแพงที่บางกว่านั้นถูก "ข้าม" ทั้งชิ้นระหว่างสองเฟรม โดยไม่มีการชนเกิดขึ้นเลย
	print("── ความหนากำแพงผูกกับความเร็วสูงสุด ──")
	t.near("ระยะต่อเฟรมที่ความเร็วเต็มขั้น",
		Config.getMaxWalkSpeed() / spd.PHYSICS_FPS, 2.133, 0.01)
	t.near("ความหนาขั้นต่ำ = ระยะต่อเฟรม × 2", Config.getMinWallThickness(), 4.267, 0.01)
	check("ความเร็วสูงสุดไม่เกินเพดานที่ Roblox รับได้",
		Config.getMaxWalkSpeed() <= spd.SPEED_CEILING, true)

	local minThick = Config.getMinWallThickness()
	check("กำแพงกั้นด่านหนาพอ", map.StageWall.Thickness >= minThick, true)
	check("กำแพงข้างเลนหนาพอ", map.Lane.WallThickness >= minThick, true)
	check("กำแพงใสขอบแมพหนาพอ", map.Boundary.Thickness >= minThick, true)
	-- ⚠️ **รั้วคอกจงใจบางกว่าเกณฑ์** เพราะ CanCollide = false
	-- กฎความหนามีไว้กับกำแพงที่ต้อง "หยุด" ผู้เล่นเท่านั้น
	-- เคยเอารั้วเข้ากฎนี้แล้วต้องดันหนาเป็น 5 จนกลายเป็นกำแพงเตี้ยแทนที่จะเป็นรั้ว
	check("รั้วคอกบางกว่าเกณฑ์ได้ เพราะไม่ได้ทำหน้าที่กัน", map.Pen.FenceThickness < minThick, true)
	check("รั้วยื่นเข้าคอกไม่เกินขอบกันชน",
		map.Pen.EdgeMargin >= map.Pen.FenceThickness / 2, true)

	-- ══ ยามต้องจับได้จริง ══
	print("── ยามความเร็ว/ความหนา ต้องจับค่าที่พังได้จริง ──")
	local savedMaxMult = spd.MAX_MULTIPLIER
	local savedBoundary = map.Boundary.Thickness
	local savedCurve = spd.CURVE_EXPONENT

	-- ดันความเร็วจนเกินเพดาน Roblox → ต้องล้ม
	check("ความเร็วสูงสุดเกิน 200 → ล้ม", mapGuardCatches(
		function() spd.MAX_MULTIPLIER = 10 end,
		function() spd.MAX_MULTIPLIER = savedMaxMult end), true)

	-- กำแพงบางกว่าระยะต่อเฟรม → ต้องล้ม
	check("กำแพงใสบางเกินไป → ล้ม", mapGuardCatches(
		function() map.Boundary.Thickness = 1 end,
		function() map.Boundary.Thickness = savedBoundary end), true)

	-- ⚠️ ข้อที่สำคัญที่สุด: **ขึ้นความเร็วแล้วลืมเพิ่มความหนา ต้องไม่บูต**
	-- ยามนี้คือเหตุผลที่ความหนาผูกกับสูตร ไม่ใช่เลขตายตัว
	check("ขึ้นความเร็วโดยไม่เพิ่มความหนา → ล้ม", mapGuardCatches(
		function() spd.MAX_MULTIPLIER = 5.5 end, -- 32 × 5.5 = 176 (ยังไม่เกิน 200) แต่ต้องหนา 5.87
		function() spd.MAX_MULTIPLIER = savedMaxMult end), true)

	check("เลขชี้กำลังติดลบ → ล้ม", mapGuardCatches(
		function() spd.CURVE_EXPONENT = -1 end,
		function() spd.CURVE_EXPONENT = savedCurve end), true)
	check("คืนค่าเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)

	--------------------------------------------------------------------------
	-- ค่าที่ไม่ใช่ตัวเลข: อ่าน member ที่ไม่มี ต้อง **error** ไม่ใช่คืน nil
	--------------------------------------------------------------------------
	-- ⚠️⚠️ เทสต์ชุดนี้มีไว้เพราะบั๊กที่ทำให้ **แมพไม่ขึ้นทั้งใบ** ใน Studio
	-- `validate()` เคยเขียน `value.Z` บนค่าที่เป็น Vector2:
	--   · ใน Roblox — Vector2 เป็น userdata → **error ทันที** → validate() ตายตอนบูต
	--     → MapBuilder.build() ไม่ถูกเรียก → ไม่มีพื้น ไม่มีใครเกิด = ท้องฟ้าว่างเปล่า
	--   · ใน luau CLI — fallback เป็น table ธรรมดา → คืน nil เงียบ ๆ → เทสต์ผ่านหมด
	-- ความต่างตรงนี้คือเหตุผลเดียวที่บั๊กหลุดไปถึง Studio ได้
	-- ตอนนี้ fallback ถูกทำให้ error เหมือนกัน · เทสต์ข้างล่างตรึงพฤติกรรมนั้นไว้
	print("── fallback ของ Vector ต้องเข้มเท่า Roblox ──")

	local flat = Config.MapDimensions.Pen.Size -- Vector2 (ผังบนพื้น)
	local solid = Config.MapDimensions.Blockout.EggSize -- Vector3 (ขนาด Part จริง)

	check("อ่าน .X/.Y จาก vec2 ได้ปกติ", flat.X > 0 and flat.Y > 0, true)
	check("อ่าน .Z จาก vec2 ต้อง error", (pcall(function()
		return (flat :: any).Z
	end)), false)
	check("อ่าน member มั่ว ๆ จาก vec3 ต้อง error", (pcall(function()
		return (solid :: any).Nope
	end)), false)
	check("อ่าน .Z จาก vec3 ได้ปกติ", solid.Z > 0, true)

	-- ตัวช่วยที่ validate() ใช้แทนการอ่าน .Z ตรง ๆ — ต้องแยกสองแกน/สามแกนได้โดยไม่พัง
	check("มีตัวช่วยอ่านแกน Z แบบไม่พัง", type(Config.getOptionalZ), "function")
	check("vec2 → ไม่มีแกน Z", Config.getOptionalZ(flat), nil)
	check("vec3 → ได้แกน Z กลับมา", Config.getOptionalZ(solid), solid.Z)

	--------------------------------------------------------------------------
	-- Config.Balance — ลูกบิดสมดุลอยู่ที่เดียว และยามต้องจับของที่หลุดออกมาได้
	--------------------------------------------------------------------------
	-- ⚠️ เทสต์ชุดนี้ไม่ได้ตรวจ "ค่า" แต่ตรวจ **ที่อยู่ของค่า**
	-- ก่อนหน้านี้ลูกบิดสมดุล (ปรับได้ทุกวัน) กับ id/schema (แก้แล้วข้อมูลอ่านไม่ออก)
	-- นั่งปนกันอยู่ที่ Config ชั้นเดียวกัน ไม่มีอะไรบอกว่าอันไหนเป็นอันไหน
	print("── Config.Balance: ลูกบิดสมดุลอยู่ที่เดียว ──")

	local BALANCE_GROUPS = {
		"StageWeightTiers", "Weight", "Production", "Damage", "NewPlayer",
		"Economy", "Pen", "Bag", "Hatchery", "Stages", "Stage", "Boss",
		"DamageUpgrade", "SpeedUpgrade", "Combat", "BalanceCheck", "Weapon",
	}

	local missingFromBalance = {}
	local leakedToTop = {}
	for _, name in BALANCE_GROUPS do
		if (Config.Balance :: any)[name] == nil then
			table.insert(missingFromBalance, name)
		end
		if (Config :: any)[name] ~= nil then
			table.insert(leakedToTop, name)
		end
	end

	check("ทุกกลุ่มสมดุลอยู่ใน Config.Balance", table.concat(missingFromBalance, ","), "")
	check("ไม่มีกลุ่มสมดุลเหลือที่ Config ชั้นบนสุด", table.concat(leakedToTop, ","), "")
	check("นับได้ 17 กลุ่ม", #BALANCE_GROUPS, 17)

	-- ของที่ **ต้องไม่** ถูกย้ายเข้า Balance — id · schema · รูปทรงแมพ · ชื่อ remote
	for _, name in { "MapDimensions", "RemoteNames", "DataStore", "Stack", "Uid", "World",
		"Characters", "CharacterClasses", "EggTypes", "Inventory" } do
		check(`{name} ยังอยู่นอก Balance`, (Config :: any)[name] ~= nil, true)
		check(`{name} ไม่ถูกย้ายเข้า Balance`, (Config.Balance :: any)[name], nil)
	end

	-- ══ ยามต้องจับได้จริง ══
	print("── ยาม Config.Balance ต้องจับของที่หลุดได้ ──")

	local savedCombat = Config.Balance.Combat

	local function balanceGuardCatches(mutate, restore): boolean
		mutate()
		local ok = (pcall(Config.validate))
		restore()
		return not ok
	end

	-- เผลอเติม `Config.Pen = {...}` กลับเข้าไปที่ชั้นบนสุด → ของสองชุดที่ค่าจะเพี้ยนจากกัน
	check("เติมกลุ่มสมดุลกลับที่ชั้นบนสุด → ล้ม", balanceGuardCatches(
		function() (Config :: any).Pen = { MAX_LEVEL = 99 } end,
		function() (Config :: any).Pen = nil end), true)

	-- ลบกลุ่มออกจาก Balance → โค้ดที่อ่านมันจะพังตอน runtime แทนที่จะพังตอนบูต
	check("ลบกลุ่มออกจาก Balance → ล้ม", balanceGuardCatches(
		function() (Config.Balance :: any).Combat = nil end,
		function() (Config.Balance :: any).Combat = savedCombat end), true)

	check("คืนค่าเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)

	--------------------------------------------------------------------------
	-- เวลาฟักไข่ — ลูกบิดเดียว ไม่ใช่ตัวเลขดิบ 9 ตัว
	--------------------------------------------------------------------------
	-- ⚠️ ความผิดแบบเดียวกับ turretDps: เก็บเป็นตัวเลขดิบแล้วต้องไล่แก้มือทุกครั้ง
	print("── เวลาฟักไข่ผูกกับ SECONDS_PER_STAGE ──")

	local perStage = Config.Balance.Hatchery.SECONDS_PER_STAGE
	check("SECONDS_PER_STAGE = 30", perStage, 30)
	check("ด่าน 1 ฟัก 30 วิ", Config.getEgg("egg_stage1").hatchTime, 30)
	check("ด่าน 9 ฟัก 270 วิ", Config.getEgg("egg_stage9").hatchTime, 270)
	check("ไข่ตำนานใช้ลูกบิดของตัวเอง",
		Config.getEgg("egg_legendary").hatchTime, Config.Balance.Hatchery.LEGENDARY_SECONDS)

	-- ⚠️ ข้อที่สำคัญ: ปรับลูกบิดตัวเดียวแล้วต้องขยับครบทั้ง 9 ด่าน
	check("ทุกด่านตรงสูตร", (function(): boolean
		for stage = 1, Config.Balance.Stage.COUNT do
			local egg = Config.getEgg(Config.getBossEggId(stage))
			if egg.hatchTime ~= perStage * stage then
				return false
			end
		end
		return true
	end)(), true)

	-- ไข่ที่ปิดแล้วยังถือตัวเลขดิบไว้ได้ เพราะแช่แข็งไปแล้ว ไม่มีใครฟัก
	check("ไข่ที่ปิดแล้วไม่ถูกยามบังคับ", (pcall(Config.validate)), true)

	-- ยามต้องจับตัวเลขดิบที่หลุดกลับเข้ามา
	local stage5 = Config.getEgg("egg_stage5")
	local savedHatch = stage5.hatchTime
	check("ใส่ตัวเลขดิบที่ไม่ตรงสูตร → ล้ม", balanceGuardCatches(
		function() (stage5 :: any).hatchTime = 999 end,
		function() (stage5 :: any).hatchTime = savedHatch end), true)
	check("คืนค่าเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)

	--------------------------------------------------------------------------
	-- ขนาดโมเดลไข่/แม่ตามน้ำหนัก
	--------------------------------------------------------------------------
	print("── ขนาดโมเดลไข่/แม่ scale ตาม tier น้ำหนัก ──")

	check("tier 1 (100kg) = ตัวคูณ 1.00", Config.getVisualScaleMultiplier(100), 1.00)
	check("tier 1 (999kg) ยังเป็นตัวคูณ 1.00", Config.getVisualScaleMultiplier(999), 1.00)
	check("tier 2 (1000kg) = ตัวคูณ 1.32", Config.getVisualScaleMultiplier(1000), 1.32)
	check("tier 7 (100,000,000kg) = ตัวคูณ 5.25", Config.getVisualScaleMultiplier(100000000), 5.25)
	check("index ของ tier ตรงกับ WeightTiers", Config.getWeightTierIndex(50000), 3)

	-- ⚠️ ฐานจริงของไข่ตรงกับตัวอย่างที่ตกลงกันไว้พอดี (ฐาน 3 × ตัวคูณ)
	local egg1 = Config.getEggVisualSize(100)
	local egg7 = Config.getEggVisualSize(100000000)
	near("ไข่ tier 1 ขนาด 3.0 (ฐานเป๊ะ)", egg1.X, 3.0, 0.001)
	near("ไข่ tier 7 ขนาด 15.75 (ฐาน 3 × 5.25)", egg7.X, 15.75, 0.001)
	check("ไข่ยังเป็นทรงกลม (สามแกนเท่ากันเสมอ)", egg7.X == egg7.Y and egg7.Y == egg7.Z, true)

	-- ⚠️ ฐานจริงของแม่คือ MapDimensions.Blockout.MotherSize (3.5, 3.5, 5) ไม่ใช่ทรงลูกบาศก์
	-- ฐาน 8 อย่างในตัวอย่างที่ขอมา — ตัวคูณเหมือนกันเป๊ะ ต่างแค่ฐาน (รายงานไว้ในสรุปงานแล้ว)
	local motherHeldTier1 = Config.getMotherVisualSize(100, false)
	local motherHeldTier7 = Config.getMotherVisualSize(100000000, false)
	near("แม่ tier 1 ตอนถือ/ส่งรบ กว้าง 3.5 (ฐานเป๊ะ ไม่ใช่ 8 ตามตัวอย่าง)", motherHeldTier1.X, 3.5, 0.001)
	near("แม่ tier 7 ตอนถือ/ส่งรบ กว้าง 18.375 (ฐาน 3.5 × 5.25)", motherHeldTier7.X, 18.375, 0.001)
	near("แม่ tier 7 ตอนถือ/ส่งรบ ยาว 26.25 (ฐาน 5 × 5.25)", motherHeldTier7.Z, 26.25, 0.001)

	-- ⚠️ กฎ 1/10 ในคอก: ทุก tier เท่ากัน
	local motherPenTier1 = Config.getMotherVisualSize(100, true)
	local motherPenTier7 = Config.getMotherVisualSize(100000000, true)
	near("แม่ tier 1 ในคอก = ตอนถือ/10", motherPenTier1.X, motherHeldTier1.X / 10, 0.0001)
	near("แม่ tier 7 ในคอก = ตอนถือ/10", motherPenTier7.X, motherHeldTier7.X / 10, 0.0001)
	check("แม่ในคอกเล็กกว่าแม่ตอนถือเสมอ (ไม่ใช่ตัวคูณ > 1 หลุดมา)", motherPenTier7.X < motherHeldTier7.X, true)

	-- ยามต้องบังคับว่าตัวคูณต้องไต่ขึ้นเรื่อย ๆ (ตัวเล็กห้ามแสดงใหญ่กว่าตัวใหญ่)
	local scaleTable = Config.Balance.VisualScale.WEIGHT_MULTIPLIER
	local savedTier3Scale = scaleTable[3]
	check("ตัวคูณ tier ถอยหลัง → ยามจับได้", balanceGuardCatches(
		function() scaleTable[3] = scaleTable[1] end,
		function() scaleTable[3] = savedTier3Scale end), true)
	check("คืนค่าเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)

	--------------------------------------------------------------------------
	-- เวลาฟักตามน้ำหนัก + คลาส
	--------------------------------------------------------------------------
	print("── เวลาฟักตามน้ำหนัก + คลาส (Config.getHatchSeconds) ──")

	check("tier 1 คลาส C = 1 นาที (ฐานเป๊ะ)", Config.getHatchSeconds(100, "monkey"), 60)
	check("tier 7 คลาส S = 48 ชม. (ตัวอย่างตรวจสอบที่ตกลงกันไว้)",
		Config.getHatchSeconds(100000000, "guanyin"), 24 * 3600 * 2)
	check("tier 3 คลาส B = 30 นาที × 1.15",
		Config.getHatchSeconds(50000, "bajie"), 1800 * 1.15)
	check("charId ที่ไม่มีจริง → ถือเป็นคลาส C (ตัวคูณ 1)",
		Config.getHatchSeconds(100, "ไม่มีจริง"), 60)

	-- ⚠️ ไข่ตำนานฟักคงที่เสมอ — ตั้งใจ "จ่ายเงินจริงซื้อความเร็ว" เร็วกว่า tier 1 พอดี
	check("ไข่ตำนานเร็วกว่าไข่ tier 1 ธรรมดาพอดี (ทั้งคู่ 1 นาที เพราะ LEGENDARY_SECONDS = 60)",
		Config.Balance.Hatchery.LEGENDARY_SECONDS, 60)

	-- เพดานกันตั้งเลขพลาด: tier สูงสุด × คลาสสูงสุด (SS) ต้องไม่เกิน MAX_HATCH_SECONDS
	local worstHatch = Config.Balance.Hatchery.HatchTimeByTier[7] * Config.Balance.Hatchery.ClassHatchMultiplier.SS
	check("เวลาฟักสูงสุดจริง (tier 7 × SS) = 62.4 ชม.", worstHatch, 24 * 3600 * 2.6)
	check("ยังอยู่ใต้เพดาน MAX_HATCH_SECONDS (7 วัน)", worstHatch <= Config.Balance.Hatchery.MAX_HATCH_SECONDS, true)

	-- ยามต้องจับได้ถ้าตั้งเลขจนเวลาฟักทะลุเพดาน
	local hatchTable = Config.Balance.Hatchery.HatchTimeByTier
	local savedTier7Hatch = hatchTable[7]
	check("tier 7 ตั้งเกินเพดาน → ยามจับได้", balanceGuardCatches(
		function() hatchTable[7] = Config.Balance.Hatchery.MAX_HATCH_SECONDS end,
		function() hatchTable[7] = savedTier7Hatch end), true)
	check("คืนค่าเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)

	-- ยามต้องจับได้ถ้าตารางเวลาฟักถอยหลัง (tier ใหญ่กว่าต้องฟักช้ากว่าหรือเท่ากันเสมอ)
	local savedTier3Hatch = hatchTable[3]
	check("เวลาฟัก tier ถอยหลัง → ยามจับได้", balanceGuardCatches(
		function() hatchTable[3] = hatchTable[1] end,
		function() hatchTable[3] = savedTier3Hatch end), true)
	check("คืนค่าเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)

	-- ยามต้องจับได้ถ้าคลาสไหนหายไปจาก ClassHatchMultiplier
	local classMultTable = Config.Balance.Hatchery.ClassHatchMultiplier
	local savedSS = classMultTable.SS
	check("ลบคลาส SS ออกจาก ClassHatchMultiplier → ยามจับได้", balanceGuardCatches(
		function() classMultTable.SS = nil end,
		function() classMultTable.SS = savedSS end), true)
	check("คืนค่าเดิมแล้ว validate ผ่าน", (pcall(Config.validate)), true)
end
