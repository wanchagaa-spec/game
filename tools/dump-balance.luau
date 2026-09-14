--!nocheck
-- egg-army-game :: พ่นตัวเลขสมดุลทุกตัวออกมาเป็น TSV ทาง stdout
--
-- ไม่ได้ใช้เอง — เป็นขั้นแรกของ tools/gen-balance-tables.py
-- แยกเป็นคนละไฟล์เพราะ **ตัวเลขต้องมาจาก Config จริง ไม่ใช่พิมพ์ซ้ำในฝั่ง Python**
--
-- รูปแบบ: <คีย์กลุ่ม>\t<ค่า1>\t<ค่า2>...  บรรทัดละแถว
--
-- ลองดูเฉย ๆ ได้ด้วย:  luau tools/dump-balance.luau | head

local Config = require("../src/shared/Config")

-- ⚠️ ใช้ select("#") ไม่ใช่ `for _, v in {...}`
-- เพราะถ้ามีค่าไหนเป็น nil อาเรย์จะมีรูแล้ววนหยุดกลางทาง → field หายเงียบ ๆ
-- เคยเกิดจริงตอนเปลี่ยนชื่อค่าใน Config แล้ว dump พ่นแถวสั้นออกมาโดยไม่มีใครรู้
local function row(...)
	local count = select("#", ...)
	local p = table.create(count)
	for i = 1, count do
		local v = select(i, ...)
		assert(v ~= nil, `dump: ค่าที่ {i} ของแถว "{tostring((select(1, ...)))}" เป็น nil — ชื่อค่าใน Config เปลี่ยนไปแล้วหรือเปล่า`)
		p[i] = tostring(v)
	end
	print(table.concat(p, "\t"))
end
local function classChar(c) for id, ch in Config.Characters do if ch.class == c then return id end end return nil end
local check = Config.BalanceCheck
local CLASSES = { "C", "B", "A", "S", "SS" }
local WEIGHTS = { 100, 1000, 10000, 100000, 1000000, 10000000, 100000000 }

row("META", "stepMultiplier", Config.DamageUpgrade.STEP_MULTIPLIER)
row("META", "stepsPerStage", Config.DamageUpgrade.STEPS_PER_STAGE)
row("META", "maxLevel", Config.DamageUpgrade.MAX_LEVEL)
row("META", "weightExponent", Config.Production.WEIGHT_EXPONENT)
row("META", "stackCap", Config.Production.STACK_CAP)
row("META", "tollCeiling", Config.BalanceCheck.TURRET_TOLL_CEILING)
row("META", "onlinePerMinute", Config.Production.ONLINE_PER_MINUTE)
row("META", "offlineRatio", Config.Production.OFFLINE_RATE_RATIO)
row("META", "offlineCapHours", Config.Production.OFFLINE_CAP_SECONDS / 3600)
row("META", "minHours", check.MIN_HOURS_PER_STAGE)
row("META", "maxHours", check.MAX_HOURS_PER_STAGE)
row("META", "childRatio", Config.Weight.CHILD_RATIO)
row("META", "damageFormula", Config.Damage.ACTIVE_FORMULA)
row("META", "coinBase", Config.Economy.BASE_PER_MINUTE)
row("META", "coinStageMult", Config.Economy.STAGE_MULTIPLIER)
row("META", "sellMinutes", Config.Economy.SELL_MOTHER_MINUTES)
row("META", "autoPause", Config.Combat.AUTO_PAUSE_AFTER_UNITS)
row("META", "maxVisible", Config.Combat.MAX_VISIBLE_UNITS)
row("META", "walkSeconds", Config.Combat.WALK_SECONDS_TO_WALL)
row("META", "bagCapacity", Config.Bag.CAPACITY)
row("META", "maxSsOverS", Config.BalanceCheck.MAX_SS_OVER_S_RATIO)
row("META", "costMultInStage", Config.DamageUpgrade.COST_MULTIPLIER_IN_STAGE)
row("META", "startingCoins", Config.NewPlayer.coins)
row("META", "stageCount", Config.Stage.COUNT)
row("META", "killDefenderBase", Config.Economy.KILL_DEFENDER_BASE)
row("META", "killBossBase", Config.Economy.KILL_BOSS_BASE)
row("META", "killDefenderMult", Config.Economy.KILL_DEFENDER_MULTIPLIER)
row("META", "killBossMult", Config.Economy.KILL_BOSS_MULTIPLIER)
row("META", "minUpgradeShare", Config.BalanceCheck.MIN_UPGRADE_SHARE)
row("META", "maxUpgradeShare", Config.BalanceCheck.MAX_UPGRADE_SHARE)
row("META", "eggsPerHour", Config.getEggsPerHour())
row("META", "bossEggs", Config.Boss.EGGS_PER_SPAWN)
row("META", "bossRespawn", Config.Boss.RESPAWN_SECONDS)
row("META", "players", Config.BalanceCheck.PLAYERS_PER_SERVER)
row("META", "maxFarmRatio", Config.BalanceCheck.MAX_FARM_TO_CLEAR_RATIO)
row("META", "eggBagCapacity", Config.Hatchery.BAG_CAPACITY)
row("META", "hatcherySlots", Config.Hatchery.MAX_SLOTS)

for _, c in CLASSES do
	local names = {}
	for _, ch in Config.Characters do if ch.class == c then table.insert(names, ch.name) end end
	table.sort(names)
	row("CLASS", c, Config.CharacterClasses[c].multiplier, table.concat(names, " · "))
end

for _, w in WEIGHTS do
	local v = { "POWER", w }
	for _, c in CLASSES do table.insert(v, Config.computePower(w, classChar(c))) end
	for _, c in CLASSES do table.insert(v, Config.computePower(Config.getChildWeight(w), classChar(c))) end
	row(table.unpack(v))
end

for _, w in WEIGHTS do
	local v = { "COINS", w }
	for stage = 1, 9 do table.insert(v, Config.getCoinsPerMinute(w, stage)) end
	table.insert(v, Config.getMotherSellPrice(w, 1))
	row(table.unpack(v))
end

for _, t in Config.StageWeightTiers[1] do
	row("TIER", t.min, t.max, t.weight, t.weight / 10000)
end

local EGG_IDS = {}
for st = 1, 9 do table.insert(EGG_IDS, Config.getBossEggId(st)) end
table.insert(EGG_IDS, "egg_legendary")
table.insert(EGG_IDS, "egg_common")
table.insert(EGG_IDS, "egg_rare")
for _, id in EGG_IDS do
	local e = Config.getEgg(id)
	local pool = Config.EggCharacterPools[id]
	local parts = {}
	for _, c in CLASSES do
		local pct = 0
		if pool then for _, entry in pool do if entry.class == c then pct = entry.weight end end end
		table.insert(parts, pct / Config.CLASS_ROLL_MAX * 100)
	end
	row("EGG", id, e.name, e.source, e.hatchTime, e.guaranteedTier or 0,
		if e.enabled then "on" else "off", e.stage or 0, table.unpack(parts))
end

for stage = 1, 9 do
	row("STAGEINFO", stage, Config.getStageDefenderCount(stage), Config.getStageDefenderHp(stage),
		Config.getStageWallHp(stage), Config.getStageTotalHp(stage), Config.getStageTurretDps(stage),
		Config.getBossHp(stage), Config.getWeaponDamage(stage), Config.getReleaseRate(stage),
		Config.getArmyDamageMultiplier(Config.getMaxDamageLevel(stage)), Config.getVisibleUnitCount(stage))
end

for lvl = 1, Config.Pen.MAX_LEVEL do
	row("PEN", lvl, Config.getPenCapacity(lvl), Config.getPenUpgradeCost(lvl) or 0)
end
for lvl = 0, Config.Production.UPGRADE_MAX_LEVEL do
	row("PRODUP", lvl, Config.getProductionMultiplier(lvl), Config.getProductionUpgradeCost(lvl) or 0)
end

-- ── ตารางหลักต่อด่าน (ผู้เล่นชั้นกลาง) ──
for stage = 1, 9 do
	local w = check.REFERENCE_WEIGHT[stage]
	local cls = check.REFERENCE_CLASS[stage]
	local penCap = Config.getPenCapacity(stage)
	local perMother = Config.getProductionPerMinute(w, nil, stage - 1, true)
	local producedPerMin = penCap * perMother
	local releasePerMin = Config.getReleaseRate(stage) * 60
	local eff = math.min(producedPerMin, releasePerMin)
	local power = Config.computeBattlePower(Config.getChildWeight(w), classChar(cls), nil, Config.getMaxDamageLevel(stage))
	local hp = Config.getStageTotalHp(stage)
	local hours = Config.getReferenceClearHours(stage)
	row("STAGE", stage, w, cls, penCap, perMother, producedPerMin, releasePerMin,
		if producedPerMin < releasePerMin then "produce" else "release",
		power, hp, hours, eff / 60 * power)
end

-- ── เส้นทางผู้เล่นจริง vs โมเดลเก่า (แม่หนักขึ้นตามด่าน) ──
local OLD_W = { 500, 2000, 8000, 30000, 120000, 500000, 2000000, 8000000, 30000000 }
local OLD_C = { "C", "C", "B", "B", "A", "A", "S", "S", "S" }
local TIERP = { 0.90, 0.09, 0.009, 0.0009, 0.00009, 0.000009, 0.000001 }
local function tierOf(weight)
	for index, t in Config.Weight.TIERS do
		if weight >= t.min and weight <= t.max then return index end
	end
	return 1
end
for stage = 2, 9 do
	local hp = Config.getStageTotalHp(stage)
	-- โมเดลเก่า
	local w, cls = OLD_W[stage], OLD_C[stage]
	local eff = math.min(Config.getPenCapacity(stage) * Config.getProductionPerMinute(w, nil, stage - 1, true) / 60,
		Config.getReleaseRate(stage))
	local oldHours = hp / (eff * Config.computeBattlePower(Config.getChildWeight(w), classChar(cls), nil, Config.getMaxDamageLevel(stage)) * 3600)
	-- เวลาฟาร์มของโมเดลเก่า: ต้องได้ทั้ง tier และคลาส
	local ti = tierOf(w)
	local pt = 0
	for k = ti, #TIERP do pt += TIERP[k] end
	local pool = Config.EggCharacterPools[Config.getBossEggId(stage)]
	local pc = 0
	local wantOrder = Config.CharacterClasses[cls].order
	for _, e in pool do
		if Config.CharacterClasses[e.class].order <= wantOrder then pc += e.weight end
	end
	pc /= Config.CLASS_ROLL_MAX
	local oldFarm = if pc * pt > 0 then (Config.getPenCapacity(stage) / (pc * pt)) / Config.getEggsPerHour() else -1
	row("PATH", stage, oldHours, oldFarm, w, cls,
		Config.getReferenceClearHours(stage), Config.getReferenceFarmHours(stage),
		check.REFERENCE_WEIGHT[stage], check.REFERENCE_CLASS[stage])
end

-- ── รายได้ต่อด่าน แยกตามบ่อ vs ราคาของ ──
for stage = 2, 9 do
	local w = check.REFERENCE_WEIGHT[stage]
	local hrs = Config.getReferenceClearHours(stage)
	local penIncome = Config.getPenCapacity(stage) * Config.getCoinsPerMinute(w, stage) * 60
	local killTotal = Config.getStageDefenderRewardTotal(stage)
	local bossPerHour = (3600 / Config.Boss.RESPAWN_SECONDS) * Config.getBossKillReward(stage)
		/ check.PLAYERS_PER_SERVER
	local total = (penIncome + bossPerHour) * hrs + killTotal
	local need = (Config.getPenUpgradeCost(stage) or 0)
		+ (Config.getProductionUpgradeCost(stage - 1) or 0)
		+ (Config.getWeaponUpgradeCost(stage) or 0)
	local upg = Config.getStageDamageUpgradeTotal(stage)
	row("INCOME", stage, hrs, penIncome, killTotal / hrs, bossPerHour,
		Config.getReferenceStageIncome(stage), need + upg, upg,
		Config.getReferenceStageIncome(stage) / (need + upg),
		upg / Config.getReferenceStageIncome(stage))
end

-- ── เวลาพังแต่ละด่าน แยกตามน้ำหนักแม่ (คลาส C) ──
for _, w in WEIGHTS do
	local v = { "BYWEIGHT", w }
	for stage = 1, 9 do
		local hp = Config.getStageTotalHp(stage)
		if hp <= 0 then table.insert(v, -1) else
			local producedPerSec = Config.getPenCapacity(stage) * Config.getProductionPerMinute(w, nil, stage - 1, true) / 60
			local eff = math.min(producedPerSec, Config.getReleaseRate(stage))
			table.insert(v, hp / (eff * Config.computeBattlePower(Config.getChildWeight(w), classChar("C"), nil, stage) * 3600))
		end
	end
	row(table.unpack(v))
end

-- ── เทียบ "น้ำหนัก vs คลาส" ที่ด่านสุดท้าย ──
-- ย่อหน้าคำอธิบายหัวข้อ 3 ต้องยกตัวอย่างว่าคลาสชดเชยน้ำหนักได้แค่ไหน
-- ถ้าไม่พ่นออกมาตรงนี้ ฝั่ง Python จะต้องเดาสูตรเอง แล้วก็จะเพี้ยนอีก
do
	local last = Config.Stage.COUNT
	local function hoursAt(w: number, cls: string): number
		local hp = Config.getStageTotalHp(last)
		if hp <= 0 then return -1 end
		local producedPerSec = Config.getPenCapacity(last) * Config.getProductionPerMinute(w, nil, last - 1, true) / 60
		local eff = math.min(producedPerSec, Config.getReleaseRate(last))
		local power = Config.computeBattlePower(Config.getChildWeight(w), classChar(cls), nil, last)
		return hp / (eff * power * 3600)
	end
	local lightest = WEIGHTS[1]
	local refW = check.REFERENCE_WEIGHT[last]
	local refC = check.REFERENCE_CLASS[last]
	-- CLASSCOMP: ด่าน · น้ำหนักเบาสุด · คลาสC · คลาสอ้างอิง · น้ำหนักอ้างอิง+คลาสอ้างอิง
	row("CLASSCOMP", last, lightest, hoursAt(lightest, "C"), refC, hoursAt(lightest, refC), refW, hoursAt(refW, refC))
end

-- ── เวลาเติมคลัง ──
for _, w in WEIGHTS do
	local on0 = Config.getProductionPerMinute(w, nil, 0, true)
	local off0 = Config.getProductionPerMinute(w, nil, 0, false)
	local on3 = Config.getProductionPerMinute(w, nil, 3, true)
	row("FILL", w, on0, off0, on3,
		Config.Production.STACK_CAP / 2 / on0 / 60,
		Config.Production.STACK_CAP / on0 / 60,
		Config.Production.STACK_CAP / off0 / 60,
		Config.Production.STACK_CAP / on3 / 60)
end

-- ── turret ──
for stage = 2, 9 do
	local w = check.REFERENCE_WEIGHT[stage]
	local penCap = Config.getPenCapacity(stage)
	local eff = math.min(penCap * Config.getProductionPerMinute(w, nil, stage - 1, true) / 60, Config.getReleaseRate(stage))
	local power = Config.computeBattlePower(Config.getChildWeight(w), classChar(check.REFERENCE_CLASS[stage]), nil, Config.getMaxDamageLevel(stage))
	local ourDps = eff * power
	local t = Config.getStageTurretDps(stage)
	local onField = math.min(Config.getReleaseRate(stage) * Config.Combat.WALK_SECONDS_TO_WALL, 1e9)
	row("TURRET", stage, ourDps, t, t / ourDps, 0.1 * ourDps, onField, onField * power / t,
		Config.getStageTotalHp(stage) / ourDps)
end

-- ── ตาราง upgrade damage ต่อด่าน ──
for stage = 1, 9 do
	local cap = Config.getMaxDamageLevel(stage)
	local first = (stage - 1) * Config.DamageUpgrade.STEPS_PER_STAGE + 1
	row("UPG", stage, cap, Config.getArmyDamageMultiplier(cap),
		Config.getDamageUpgradeCost(first), Config.getDamageUpgradeCost(cap),
		Config.getStageDamageUpgradeTotal(stage), Config.getReferenceStageIncome(stage))
end

-- ── ก่อนแก้ (ตัวคูณอัตโนมัติ) vs หลังแก้ (ซื้อครบ) vs ไม่ซื้อเลย ──
for stage = 2, 9 do
	local w = check.REFERENCE_WEIGHT[stage]
	local cid = classChar(check.REFERENCE_CLASS[stage])
	local hp = Config.getStageTotalHp(stage)
	local eff = math.min(Config.getPenCapacity(stage) * Config.getProductionPerMinute(w, nil, stage - 1, true) / 60,
		Config.getReleaseRate(stage))
	local basePower = Config.computePower(Config.getChildWeight(w), cid)
	local oldH = hp / (eff * basePower * 2.5 ^ (stage - 1) * 3600)
	local newH = Config.getReferenceClearHours(stage)
	local noneH = hp / (eff * basePower * 3600)
	row("COMPARE", stage, oldH, newH, noneH)
end
