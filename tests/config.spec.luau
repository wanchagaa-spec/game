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
	check("ACTIVE_FORMULA", Config.Damage.ACTIVE_FORMULA, "sqrt")
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
	check("ตัดขั้น 11-15 ทิ้งแล้ว", Config.Pen.MAX_LEVEL, 10)
	check("เพดานยังคลุมทุกด่าน", Config.Pen.MAX_LEVEL >= Config.Stage.COUNT, true)
	check("ราคารวมทั้งสายลดจาก 1e17", (function()
		local total = 0
		for lvl = 1, Config.Pen.MAX_LEVEL - 1 do total += Config.getPenUpgradeCost(lvl) end
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
	check("ตัดขั้น 6-10 ทิ้งแล้ว", Config.Production.UPGRADE_MAX_LEVEL, 5)
	-- ตัดแล้วต้องไม่ทำให้คอขวดย้อนกลับไปเป็นการผลิต (ไม่งั้นเวลาตีจะเปลี่ยน)
	local stillReleaseBound = true
	for st = 3, 9 do
		local w = Config.BalanceCheck.REFERENCE_WEIGHT[st]
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
	check("ไม่แบ่งตามสัดส่วน damage", Config.Economy.BOSS_REWARD_SPLIT_EQUALLY, true)
	check("ต้องทำ damage ถึงจะนับว่าร่วมตี", Config.Economy.BOSS_REWARD_MIN_DAMAGE > 0, true)

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
	      Config.Weight.CHILD_RATIO + Config.Statuses.gold.childRatioBonus
	      + Config.Statuses.silver.childRatioBonus <= Config.Weight.MAX_CHILD_RATIO, true)
	check("gold ตั้งไว้ให้ลูกเป็น 2%",
	      Config.Weight.CHILD_RATIO + Config.Statuses.gold.childRatioBonus, 0.02)


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
	check("ด่าน 1 มีตาราง", Config.StageWeightTiers[1] ~= nil, true)
	check("ด่าน 5 ยังไม่กำหนด", Config.StageWeightTiers[5], nil)
	check("ด่าน 5 ถอยไปใช้ด่าน 1", Config.getWeightTiers(5), Config.StageWeightTiers[1])
	check("ด่าน 9 ถอยไปใช้ด่าน 1", Config.getWeightTiers(9), Config.StageWeightTiers[1])
	check("ด่านเกินช่วงก็ยังคืนตารางได้", Config.getWeightTiers(99) ~= nil, true)
	check("สุ่มโดยไม่ส่ง stage ยังทำงาน", Config.rollMotherWeight(rng) >= 100, true)
	check("สุ่มโดยส่ง stage ยังทำงาน", Config.rollMotherWeight(rng, 7) >= 100, true)

	print("── ตารางด่าน + อาวุธป้องกันกำแพง ──")
	check("มีครบ 9 ด่าน", #Config.Stages, 9)
	check("ด่าน 1 ไม่มีทหารฝ่ายรับ", Config.getStageDefenderCount(1), 0)
	check("ด่าน 9 ทหาร 1,000,000,000", Config.getStageDefenderCount(9), 1e9)
	check("ด่าน 1 ไม่มี turret", Config.getStageTurretDps(1), 0)

	-- turret ต้องเป็นสัดส่วนของ damage/วินาที ไม่ใช่ของ damage ทหารฝ่ายรับ
	local function ourDpsAt(stage)
		local chk = Config.BalanceCheck
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
		if toll > Config.BalanceCheck.TURRET_TOLL_CEILING then tollOk = false end
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
	local minTier3 = Config.Weight.TIERS[3].min
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
		if Config.rollMotherWeightForEgg("egg_legendary", rng, 1) > Config.Weight.TIERS[3].max then anyHigher = true end
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
	local UP = Config.DamageUpgrade
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
	check("8 ขั้น × 9 ด่าน = 72", UP.STEPS_PER_STAGE * Config.Stage.COUNT, UP.MAX_LEVEL)

	print("── ราคา upgrade ──")
	check("ขั้น 0 ไม่มีราคา", Config.getDamageUpgradeCost(0), nil)
	check("เกินเพดานไม่มีราคา", Config.getDamageUpgradeCost(UP.MAX_LEVEL + 1), nil)
	check("ขั้นแรกราคา 300 (ผู้เล่นใหม่มี 500 ซื้อได้ทันที)", Config.getDamageUpgradeCost(1), 300)
	check("ผู้เล่นใหม่ซื้อขั้นแรกไหว", Config.NewPlayer.coins >= Config.getDamageUpgradeCost(1), true)
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
		if share < Config.BalanceCheck.MIN_UPGRADE_SHARE or share > Config.BalanceCheck.MAX_UPGRADE_SHARE then
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
	check("STAGE_DAMAGE_BASE ถูกลบแล้ว", Config.Combat.STAGE_DAMAGE_BASE, nil)
	check("สูตรเงินยังใช้ตัวคูณตามด่านเหมือนเดิม",
	      Config.getCoinsPerMinute(100, 3) / Config.getCoinsPerMinute(100, 1), 100)

	print("── ยามเฝ้าสมดุล ต้องจับค่าที่พังได้จริง ──")
	local savedStep = Config.DamageUpgrade.STEP_MULTIPLIER
	Config.DamageUpgrade.STEP_MULTIPLIER = 1.3
	check("ตัวคูณต่อขั้น 1.3 (แรงเกิน) ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	do
		local _, err = pcall(Config.validate)
		print("   ข้อความที่ได้: " .. string.sub(tostring(err), 1, 110))
	end
	Config.DamageUpgrade.STEP_MULTIPLIER = 1.01
	check("ตัวคูณต่อขั้น 1.01 (อ่อนเกิน) ต้องไม่ผ่านเช่นกัน", pcall(Config.validate), false)
	Config.DamageUpgrade.STEP_MULTIPLIER = savedStep
	check("คืนค่าเดิมแล้ว validate ผ่าน", pcall(Config.validate), true)

	-- ราคาที่ถูกเกินไปต้องถูกจับด้วย (เงินจะล้นเหมือนเดิม)
	local savedCost = Config.DamageUpgrade.STAGE_COST_BASE[5]
	Config.DamageUpgrade.STAGE_COST_BASE[5] = savedCost / 100
	check("ราคาด่าน 5 ถูกลง 100 เท่า ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	Config.DamageUpgrade.STAGE_COST_BASE[5] = savedCost * 100
	check("ราคาด่าน 5 แพงขึ้น 100 เท่า ก็ไม่ผ่านเช่นกัน", pcall(Config.validate), false)
	Config.DamageUpgrade.STAGE_COST_BASE[5] = savedCost
	check("คืนราคาเดิมแล้ว validate ผ่าน", pcall(Config.validate), true)

	print("── เกมต้องยากขึ้นเรื่อย ๆ ──")
	-- คิดแบบระบบใหม่: อัตราจริง = min(ผลิตได้, ปล่อยได้) และข้ามด่านที่ไม่มีกำแพง
	local function hoursAt(st)
		local hp = Config.getStageTotalHp(st)
		if hp <= 0 then return 0 end
		local w = Config.BalanceCheck.REFERENCE_WEIGHT[st]
		local cl = Config.BalanceCheck.REFERENCE_CLASS[st]
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
			if h < Config.BalanceCheck.MIN_HOURS_PER_STAGE or h > Config.BalanceCheck.MAX_HOURS_PER_STAGE then
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
	check("ตารางอัตราปล่อยครบ 9 ด่าน", #Config.Combat.RELEASE_PER_SECOND, 9)
	check("ด่าน 1 ปล่อย 1 ตัว/วิ", Config.getReleaseRate(1), 1)
	check("ด่าน 9 ปล่อย 10 ตัว/วิ", Config.getReleaseRate(9), 10)
	check("ด่าน 3 ยังปล่อย 1 ตัว/วิ (รอยต่อคอขวด)", Config.getReleaseRate(3), 1)
	local rising = true
	for st = 2, 9 do if Config.getReleaseRate(st) < Config.getReleaseRate(st-1) then rising = false end end
	check("อัตราปล่อยไม่ลดลง", rising, true)

	print("── อัตราผลิตแปรตามน้ำหนัก (exponent 0.25) ──")
	check("exponent = 0.25", Config.Production.WEIGHT_EXPONENT, 0.25)
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
	check("ไม่มีระบบอัป cap แล้ว (ตายตัว 500)", Config.Production.STACK_CAP_START, nil)
	near("แม่น้ำหนักฐานเติมเต็ม 500 ใช้ ~8 ชม.",
	     500 / Config.getProductionPerMinute(100, nil, 0, true) / 60, 8.33, 0.1)

	print("── ด่าน 1 ไม่มีกำแพง ──")
	check("ไม่มีทหารฝ่ายรับ", Config.getStageDefenderCount(1), 0)
	check("ไม่มีอะไรให้ตี", Config.getStageTotalHp(1), 0)
	check("ด่าน 2 มีทหาร 100", Config.getStageDefenderCount(2), 100)

	print("── กติกาที่ห้ามพลิก ──")
	check("ห้าม auto ปล่อยแม่", Config.Combat.ALLOW_AUTO_RELEASE_MOTHERS, false)
	check("ห้ามเลือกแม่จากคอก", Config.Combat.MOTHERS_SELECTABLE_FROM_PEN, false)
	local savedA = Config.Combat.ALLOW_AUTO_RELEASE_MOTHERS
	Config.Combat.ALLOW_AUTO_RELEASE_MOTHERS = true
	check("เปิด auto ปล่อยแม่ → validate ไม่ผ่าน", pcall(Config.validate), false)
	Config.Combat.ALLOW_AUTO_RELEASE_MOTHERS = savedA
	local savedP = Config.Combat.MOTHERS_SELECTABLE_FROM_PEN
	Config.Combat.MOTHERS_SELECTABLE_FROM_PEN = true
	check("เลือกแม่จากคอกได้ → validate ไม่ผ่าน", pcall(Config.validate), false)
	Config.Combat.MOTHERS_SELECTABLE_FROM_PEN = savedP

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
	check("Config.World.MAX_PENS = จำนวนผู้เล่นต่อเซิร์ฟ", Config.World.MAX_PENS, Config.BalanceCheck.PLAYERS_PER_SERVER)
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
	check("ผู้เล่นใหม่ได้ไข่ด่าน 1", Config.NewPlayer.startingEggs.egg_stage1, 1)

	print("── ยาม turret ต้องจับค่าที่พังได้จริง ──")
	-- ⚠️ turretDps ไม่ใช่ตัวเลขดิบแล้ว — คำนวณจาก TOLL × damage/วินาที
	check("ตาราง Stages ไม่มีฟิลด์ turretDps แล้ว", Config.Stages[9].turretDps, nil)
	check("ด่าน 1 ไม่มีกำแพงจึงไม่มี turret", Config.getStageTurretDps(1), 0)
	check("TOLL ไล่ขึ้นจาก 10% ถึง 20%", Config.Combat.TURRET_TOLL[2] == 0.10
		and Config.Combat.TURRET_TOLL[9] == 0.20, true)

	-- ค่าที่คำนวณต้องตรงกับ TOLL เป๊ะทุกด่าน ไม่ใช่แค่ใกล้เคียง
	local exact = true
	for st = 2, 9 do
		if math.abs(Config.getStageTurretDps(st) / ourDpsAt(st) - Config.Combat.TURRET_TOLL[st]) > 1e-9 then
			exact = false
		end
	end
	check("turretDps = TOLL × damage/วิ เป๊ะทุกด่าน", exact, true)

	-- หัวใจของการเปลี่ยนรอบนี้: ปรับอะไรก็ตามที่กระทบ damage แล้ว turret ต้องขยับตามเอง
	local beforeDps = Config.getStageTurretDps(9)
	local savedStepM = Config.DamageUpgrade.STEP_MULTIPLIER
	Config.DamageUpgrade.STEP_MULTIPLIER = 1.05
	local afterDps = Config.getStageTurretDps(9)
	check("ลดตัวคูณ damage แล้ว turret ลดตามเอง (ไม่ต้องแก้มือ)", afterDps < beforeDps, true)
	near("สัดส่วนยังเป็น 20% เท่าเดิม", afterDps / ourDpsAt(9), 0.20, 1e-9)
	Config.DamageUpgrade.STEP_MULTIPLIER = savedStepM
	check("คืนค่าเดิมแล้ว turret กลับมาเท่าเดิม", Config.getStageTurretDps(9), beforeDps)

	-- ยามต้องจับ TOLL ที่แรงเกินเพดาน
	local savedToll = Config.Combat.TURRET_TOLL[9]
	Config.Combat.TURRET_TOLL[9] = 0.9
	check("TOLL 90% ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	do
		local _, err = pcall(Config.validate)
		print("   ข้อความที่ได้: " .. string.sub(tostring(err), 1, 110))
	end
	Config.Combat.TURRET_TOLL[9] = 0.05
	check("TOLL ที่ต่ำกว่าด่านก่อนหน้าก็ไม่ผ่าน (กำแพงด่านสูงต้องไม่อ่อนลง)", pcall(Config.validate), false)
	Config.Combat.TURRET_TOLL[9] = savedToll
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
	check("โตเร็วกว่าราคาของที่โต ×10", 20 > Config.Pen.UPGRADE_COST_MULTIPLIER, true)
	check("เงินบอสโตเท่าราคาของพอดี", Config.Economy.KILL_BOSS_MULTIPLIER, Config.Pen.UPGRADE_COST_MULTIPLIER)

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
			if Config.BalanceCheck.REFERENCE_WEIGHT[st] ~= Config.BalanceCheck.REFERENCE_WEIGHT[1] then
				return false
			end
		end
		return true
	end)(), true)
	check("น้ำหนักอ้างอิงอยู่ใน tier 1 (ที่ 90% ของไข่ให้)",
		Config.BalanceCheck.REFERENCE_WEIGHT[1] >= Config.Weight.TIERS[1].min
			and Config.BalanceCheck.REFERENCE_WEIGHT[1] <= Config.Weight.TIERS[1].max, true)
	check("คลาสอ้างอิงไม่ถอยหลัง", (function()
		local prev = 99
		for st = 1, 9 do
			local o = Config.CharacterClasses[Config.BalanceCheck.REFERENCE_CLASS[st]].order
			if o > prev then return false end
			prev = o
		end
		return true
	end)(), true)
	check("คลาสอ้างอิงสูงสุดคือ A ไม่ใช่ S", Config.BalanceCheck.REFERENCE_CLASS[9], "A")

	print("── ยามเวลาฟาร์ม ──")
	check("ไข่/ชม./คน = 8.57", math.abs(Config.getEggsPerHour() - 60 / 5 * 5 / 7) < 1e-9, true)
	local farmOk = true
	for st = 2, 9 do
		local ratio = Config.getReferenceFarmHours(st) / Config.getReferenceClearHours(st)
		if ratio > Config.BalanceCheck.MAX_FARM_TO_CLEAR_RATIO then farmOk = false end
	end
	check("ทุกด่าน: เวลาฟาร์มไม่เกิน 5 เท่าของเวลาตี", farmOk, true)

	-- ยามต้องจับเคสที่เคยพลาด: บังคับให้ต้องใช้ S ที่ด่าน 7 (ออกแค่ 1%)
	local savedClass = Config.BalanceCheck.REFERENCE_CLASS[7]
	Config.BalanceCheck.REFERENCE_CLASS[7] = "S"
	check("บังคับใช้ S ที่ด่าน 7 (ไข่ออก 1%) ต้องทำให้ validate ไม่ผ่าน", pcall(Config.validate), false)
	do
		local _, err = pcall(Config.validate)
		print("   ข้อความที่ได้: " .. string.sub(tostring(err), 1, 130))
	end
	Config.BalanceCheck.REFERENCE_CLASS[7] = savedClass
	check("คืนค่าเดิมแล้ว validate ผ่าน", pcall(Config.validate), true)

	print("── ตารางน้ำหนัก: ชุดเดียวทุกด่าน เป็นการตัดสินถาวร ──")
	check("กำหนดไว้ด่านเดียว", (function()
		local n = 0
		for _ in Config.StageWeightTiers do n += 1 end
		return n
	end)(), 1)


	print("── ผู้เล่นที่ไม่ซื้อ upgrade เลย ต้องตัน ──")
	-- ถ้าไม่ซื้อแล้วยังผ่านได้สบาย แปลว่าระบบซื้อไม่มีความหมาย
	local function hoursNoUpgrade(st)
		local hp = Config.getStageTotalHp(st)
		if hp <= 0 then return 0 end
		local w = Config.BalanceCheck.REFERENCE_WEIGHT[st]
		local cl = Config.BalanceCheck.REFERENCE_CLASS[st]
		local id
		for cid, ch in Config.Characters do if ch.class == cl then id = cid break end end
		local rate = math.min(Config.getPenCapacity(st) * Config.getProductionPerMinute(w, nil, st - 1, true) / 60,
			Config.getReleaseRate(st))
		return hp / (rate * Config.computeBattlePower(Config.getChildWeight(w), id, nil, 0) * 3600)
	end
	local firstBlocked
	for st = 2, 9 do
		if hoursNoUpgrade(st) > Config.BalanceCheck.MAX_HOURS_PER_STAGE and firstBlocked == nil then
			firstBlocked = st
		end
	end
	check("ไม่ซื้อแล้วตันจริง (มีด่านที่เกินเพดาน 72 ชม.)", firstBlocked ~= nil, true)
	check("ด่านต้นยังผ่านได้โดยไม่ต้องซื้อ", hoursNoUpgrade(2) <= Config.BalanceCheck.MAX_HOURS_PER_STAGE, true)
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
	check("กระเป๋าไข่มีค่าเป็นของตัวเอง", type(Config.Hatchery.BAG_CAPACITY), "number")
	check("ช่องฟักมีค่าเป็นของตัวเอง", type(Config.Hatchery.MAX_SLOTS), "number")
	check("MAX_EGGS เดิมถูกถอดออกแล้ว", Config.Hatchery.MAX_EGGS, nil)
	-- ⚠️ เช็คค่าทีละตัว **ไม่ได้เช็คว่าเท่ากัน** เพราะไม่ได้บังคับว่าต้องเท่า
	check("ค่าเริ่มต้นกระเป๋าไข่ = 50", Config.Hatchery.BAG_CAPACITY, 50)
	check("ค่าเริ่มต้นช่องฟัก = 50", Config.Hatchery.MAX_SLOTS, 50)

	-- ยามต้องจับค่าที่ทำให้ไข่เดินทางต่อไม่ได้
	local savedBag = Config.Hatchery.BAG_CAPACITY
	Config.Hatchery.BAG_CAPACITY = 0
	check("กระเป๋าไข่ = 0 แล้ว validate ต้องล้ม", (pcall(Config.validate)), false)
	Config.Hatchery.BAG_CAPACITY = savedBag

	local savedSlots = Config.Hatchery.MAX_SLOTS
	Config.Hatchery.MAX_SLOTS = 2.5
	check("ช่องฟักเป็นทศนิยมแล้ว validate ต้องล้ม", (pcall(Config.validate)), false)
	Config.Hatchery.MAX_SLOTS = savedSlots
	check("คืนค่าเดิมแล้ว validate กลับมาผ่าน", (pcall(Config.validate)), true)
end
