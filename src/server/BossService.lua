--!strict
-- egg-army-game :: วงจรกลางวัน/กลางคืน + บอสตัวเดียวของเซิร์ฟเวอร์ (Phase 5A)
--
-- ══ กติกา (ผู้ใช้ยืนยันแล้ว) ══
--   รอบละ DAY + NIGHT วินาที (Config.Balance.BossCycle · 9 + 1 นาที) วนตลอด · เซิร์ฟเปิดใหม่เริ่มต้นกลางวันเสมอ
--   กลางคืน: วาปคนที่อยู่ในสนามรบมาหน้าป้อม (5B-fix — คนในคอก/ลานอยู่ที่เดิม) · กำแพงกั้นขึ้น (กันเฉพาะผู้เล่น) · บอสเกิด — ตัวเก่ายังไม่ตาย = ฟื้น HP เต็ม
--   กลางวัน: กำแพงกั้นหาย เข้าไปตีบอสได้ทั้งวัน · บอสตายแล้วหายไปจนคืนถัดไป
--   ตีบอส = อาวุธ (Tool) ที่ server ใส่ Backpack ให้ · ถือ/เก็บอัตโนมัติตามเขตบอส (Backpack เดิมของ Roblox ปิดอยู่)
--   ⚠️ ระบบ personal combat ของ Phase 4 **ยังไม่มีในโค้ด** — รอบนี้ทำขั้นต่ำเท่าที่ต้องใช้ตีบอส (ผู้ใช้เลือก)
--     ดาเมจ = Config.getWeaponDamage(weaponLevel) ตัวเดิม · ยังไม่มี PvP · บอสตีกลับปิดไว้ใน config
--   บันทึกว่าใครทำดาเมจบอสตัวนี้เท่าไร (damageBy) — 5B ใช้แบ่งเงิน
--
-- ══ 5B: ไข่บอส + แบ่งเงิน (ผู้ใช้ยืนยันแล้ว · แผนเต็ม docs/boss-plan.md) ══
--   ต้นกลางคืน บอสเกิดพร้อมไข่ EGGS_PER_NIGHT ฟอง **สุ่มน้ำหนักทันที** (Config.rollMotherWeightForEgg ตัวเดิม) ขนาดไข่บอกน้ำหนัก
--     ไข่หนักเกิน HEAVY_EGG_ALERT_KG → ประกาศทั้งเซิร์ฟ · ไข่ชุดเก่า (ที่วางอยู่/ที่ใครถืออยู่) หายหมด แทนด้วยชุดใหม่
--   หยิบได้ **หลังบอสตายเท่านั้น** · ใครก็ได้ที่อยู่ในห้อง (ไม่ต้องเคยตี) · ถือได้ทีละฟอง · ไม่ช้าลง
--   ถือกลับถึงเซฟโซน (ลานกลาง) → เข้ากระเป๋าไข่ทันที (EggService.grantBossEgg = ทางเพิ่มไข่เดิม) · เต็ม = ถือค้างไว้
--   ออกเกม/ตายระหว่างถือ → ไข่กลับจุดเดิม หยิบใหม่ได้
--   บอสตาย → เงินก้อนเดียว KILL_REWARD แบ่งเท่ากัน (ปัดลง) ให้คนที่ทำดาเมจ ≥ BOSS_REWARD_MIN_DAMAGE **และยังอยู่ในห้อง**
--   ⚠️ server เป็นเจ้าของทุกสถานะ (ฟองไหนว่าง · ใครถือ · ระยะตอนหยิบ · ตำแหน่งตอนเข้าเซฟโซน) · client ส่งแค่ "กดฟองที่ i"
--
-- ══ ล็อกอัญเชิญ ══ ทหารของใครพังกำแพงด่านของตัวเองเสร็จขณะบอสยังมีชีวิต → คนนั้นอัญเชิญต่อไม่ได้จนกว่าบอสตาย
--   เก็บใน memory ของเซิร์ฟ (lockedUsers · ผู้ใช้เลือก — **ไม่แตะ schema**) · ออกแล้วเข้าเซิร์ฟเดิมยังล็อกอยู่
--   ปลดได้ทางเดียว = บอสตาย (บอสไม่ตายข้ามคืน → ฟื้น HP เต็ม แต่ล็อกยังอยู่) · ตัวตัดสินอยู่ที่
--   CombatService.shouldBossLock (ด่านที่มีกำแพงจริงเท่านั้น) · CombatService.start ต่อสายผ่าน getGate()
--
-- ⚠️ ของทุกอย่างในไฟล์นี้ **ไม่เซฟ DataStore** — เวลากลางของเซิร์ฟ ไม่ผูกกับข้อมูลผู้เล่น
-- ⚠️ require สองทางเหมือน CombatService — ฟังก์ชันสถานะ (newState/step/applyDamage/...) เป็น Luau ล้วน
--   tests/boss.spec.luau เรียกตรงได้โดยส่ง `now` เอง · ของที่แตะ Roblox อยู่ใน start() เท่านั้น
local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") else nil
local Config = (if Shared then require(Shared.Config) else require("../shared/Config")) :: any

local BossService = {}

export type Phase = "day" | "night"

-- 5B: ไข่บอส 1 ฟอง · index = จุดวาง Config.getBossCycleEggSpot(index)
--   "resting" = วางอยู่ในห้อง (หยิบได้เมื่อบอสตาย) · "carried" = มีคนถือ · "gone" = เก็บเข้ากระเป๋าแล้ว
export type EggStatus = "resting" | "carried" | "gone"
export type BossEgg = {
	index: number,
	eggId: string,
	weight: number, -- kg จำนวนเต็ม — สุ่มตอนบอสเกิด ห้ามสุ่มใหม่
	status: EggStatus,
	carrier: number?, -- userId ของคนที่ถืออยู่ (status = "carried")
}

-- ตัวสุ่ม (Roblox Random หรือ stub ในเทสต์ที่มี NextInteger)
export type Rng = { NextInteger: (self: any, min: number, max: number) -> number }

export type State = {
	phase: Phase,
	phaseEndsAt: number, -- เวลา server (workspace:GetServerTimeNow) ที่ phase นี้จบ — client นับถอยหลังจากค่านี้
	cycle: number, -- นับคืน (เพิ่มทุกครั้งที่เข้ากลางคืน)
	bossAlive: boolean,
	bossHp: number,
	bossMaxHp: number,
	bossSpawnedAt: number?,
	bossDiedAt: number?,
	-- ⚠️ ใครทำดาเมจใส่บอส "ตัวนี้" ไปเท่าไร (userId → ดาเมจที่เข้าจริง) — ล้างตอนบอสเกิดตัวใหม่เท่านั้น
	-- บอสตายแล้วยังเก็บไว้จนคืนถัดไป (5B อ่านตอนแบ่งเงิน)
	damageBy: { [number]: number },
	lockedUsers: { [number]: boolean },
	lastAttackAt: { [number]: number },
	-- ══ 5B ══ ไม่เซฟ DataStore (เซิร์ฟปิด = ไข่ในห้อง/ไข่ที่ถือหายไปด้วย — ตั้งใจ)
	eggs: { BossEgg }, -- ไข่ชุดของบอสตัวปัจจุบัน (ว่างจนกว่าจะถึงคืนแรก)
	carrying: { [number]: number }, -- userId → index ของไข่ที่ถืออยู่ (ถือได้ทีละฟอง)
	lostCarriers: { number }, -- คนที่ถือไข่อยู่ตอนไข่ชุดใหม่เกิด (ไข่ที่ถือหาย) — runtime แจ้งแล้วล้าง
	rng: Rng,
}

local function cycleConfig()
	return Config.Balance.BossCycle
end

-- ตัวสุ่มสำรองเมื่อไม่ได้ส่งมา (เทสต์ส่ง stub เอง · start() ส่ง Random.new() ของ Roblox)
local function fallbackRng(): Rng
	return {
		NextInteger = function(_self: any, min: number, max: number): number
			return math.random(min, max)
		end,
	}
end

function BossService.newState(now: number, rng: Rng?): State
	return {
		phase = "day",
		phaseEndsAt = now + cycleConfig().DAY_SECONDS,
		cycle = 0,
		bossAlive = false, -- เซิร์ฟเปิดใหม่ = ต้นกลางวัน ยังไม่มีบอสจนคืนแรก
		bossHp = 0,
		bossMaxHp = cycleConfig().BOSS_HP,
		bossSpawnedAt = nil,
		bossDiedAt = nil,
		damageBy = {},
		lockedUsers = {},
		lastAttackAt = {},
		eggs = {},
		carrying = {},
		lostCarriers = {},
		rng = rng or fallbackRng(),
	}
end

-- ไข่ชุดใหม่ของบอสตัวที่เพิ่งเกิด — **สุ่มน้ำหนักทันที** ด้วยตัวสุ่มเดิมของเกม (Config.rollMotherWeightForEgg)
-- ⚠️ ไข่ชุดเก่าหายหมด รวมฟองที่มีคนถืออยู่ (คนถือถูกจดใน lostCarriers ให้ runtime แจ้ง)
local function spawnEggs(state: State)
	local cfg = cycleConfig()
	local lost: { number } = {}
	for userId in state.carrying do
		table.insert(lost, userId)
	end
	table.sort(lost)
	state.lostCarriers = lost
	table.clear(state.carrying)

	local eggs: { BossEgg } = {}
	for index = 1, cfg.EGGS_PER_NIGHT do
		local weight = Config.rollMotherWeightForEgg(cfg.EGG_ID, state.rng)
		assert(weight, `BossService: สุ่มน้ำหนักไข่ "{cfg.EGG_ID}" ไม่ได้ (validate() ควรกันไว้แล้ว)`)
		eggs[index] = { index = index, eggId = cfg.EGG_ID, weight = weight, status = "resting", carrier = nil }
	end
	state.eggs = eggs
end

-- บอสเกิด (ต้นกลางคืน) — ตัวเก่ายังไม่ตาย = ฟื้น HP เต็ม · บันทึกดาเมจเริ่มใหม่ · ไข่ชุดใหม่ (5B)
-- ⚠️ ไม่ล้าง lockedUsers — ปลดล็อกได้ทางเดียวคือฆ่าบอส
local function spawnBoss(state: State, at: number)
	state.bossAlive = true
	state.bossMaxHp = cycleConfig().BOSS_HP
	state.bossHp = state.bossMaxHp
	state.bossSpawnedAt = at
	state.bossDiedAt = nil
	state.damageBy = {}
	spawnEggs(state)
end

local function enterNight(state: State, at: number)
	state.phase = "night"
	state.phaseEndsAt = at + cycleConfig().NIGHT_SECONDS
	state.cycle += 1
	spawnBoss(state, at)
end

local function enterDay(state: State, at: number)
	state.phase = "day"
	state.phaseEndsAt = at + cycleConfig().DAY_SECONDS
end

-- เดินเวลาให้ทันปัจจุบัน · คืนเหตุการณ์ตามลำดับ ("night" / "day")
-- ⚠️ เปลี่ยน phase ตรงจังหวะ phaseEndsAt เดิม (ไม่ใช่ now) → รอบไม่เลื่อนแม้ลูปหน่วง
-- ⚠️ เซิร์ฟค้างนานเกินหนึ่งรอบ (หยุดใน debugger ฯลฯ) → ข้ามรอบที่เลยไปทั้งก้อน เหลือเหตุการณ์ไม่เกิน 2 อัน
--   (ไม่งั้นวาป/แจ้งเตือนรัวเป็นสิบครั้งในเฟรมเดียว)
function BossService.step(state: State, now: number): { string }
	local events: { string } = {}
	local cycleSeconds = Config.getBossCycleSeconds()
	local overdue = now - state.phaseEndsAt
	if overdue >= cycleSeconds then
		local skipped = math.floor(overdue / cycleSeconds)
		state.phaseEndsAt += skipped * cycleSeconds
		state.cycle += skipped
	end
	while now >= state.phaseEndsAt do
		local at = state.phaseEndsAt
		if state.phase == "day" then
			enterNight(state, at)
			table.insert(events, "night")
		else
			enterDay(state, at)
			table.insert(events, "day")
		end
	end
	return events
end

-- บังคับเข้า phase ทันที (คำสั่ง debug) — นับเวลาของ phase นั้นใหม่จาก now
function BossService.forcePhase(state: State, phase: Phase, now: number): { string }
	if phase == "night" then
		enterNight(state, now)
	else
		enterDay(state, now)
	end
	return { phase }
end

function BossService.getRemaining(state: State, now: number): number
	return math.max(0, state.phaseEndsAt - now)
end

-- ทำดาเมจใส่บอส · คืน (ดาเมจที่เข้าจริง, ครั้งนี้ฆ่าได้ไหม)
-- ⚠️ ตีได้เฉพาะกลางวันที่บอสยังมีชีวิต (กลางคืนมีกำแพงกั้นอยู่แล้ว แต่ server เช็คเองอีกชั้น)
-- ⚠️ ดาเมจเกิน HP ที่เหลือ = นับแค่ที่เข้าจริง (บันทึกผู้ทำดาเมจรวมกันได้ไม่เกิน HP เต็ม)
-- บอสตาย = ปลดล็อกอัญเชิญ **ทุกคน** ทันที
function BossService.applyDamage(state: State, userId: number, amount: number, now: number): (number, boolean)
	if state.phase ~= "day" or not state.bossAlive or amount <= 0 then
		return 0, false
	end
	local dealt = math.min(amount, state.bossHp)
	state.bossHp -= dealt
	state.damageBy[userId] = (state.damageBy[userId] or 0) + dealt
	if state.bossHp <= 0 then
		state.bossHp = 0
		state.bossAlive = false
		state.bossDiedAt = now
		table.clear(state.lockedUsers)
		return dealt, true
	end
	return dealt, false
end

-- ระยะแนวราบ (XZ) — บอสสูง ผู้เล่นยืนพื้น จึงไม่นับแกน Y
function BossService.horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- ผู้เล่นฟันบอสหนึ่งครั้ง (Tool.Activated ที่ server) · คืน (ผล, ดาเมจที่เข้า, ฆ่าได้ไหม)
-- ผล: "ok" · "night" (ยังไม่เช้า) · "dead" (ไม่มีบอส) · "cooldown" (ฟันถี่เกิน) · "range" (อยู่ไกลเกิน)
-- ⚠️ server ตัดสินทั้งหมด — distance วัดจากตำแหน่งตัวละครที่ server เห็น ไม่รับค่าจาก client
function BossService.tryAttack(
	state: State,
	userId: number,
	now: number,
	distance: number,
	weaponLevel: number
): (string, number, boolean)
	if state.phase ~= "day" then
		return "night", 0, false
	end
	if not state.bossAlive then
		return "dead", 0, false
	end
	local cfg = cycleConfig()
	local last = state.lastAttackAt[userId]
	if last and now - last < cfg.PLAYER_ATTACK_COOLDOWN then
		return "cooldown", 0, false
	end
	if distance > cfg.PLAYER_ATTACK_RANGE then
		return "range", 0, false
	end
	state.lastAttackAt[userId] = now
	local dealt, killed = BossService.applyDamage(state, userId, Config.getWeaponDamage(weaponLevel), now)
	return "ok", dealt, killed
end

-- ล็อกอัญเชิญ — ได้เฉพาะตอนบอสยังมีชีวิต (บอสตายแล้วพังกำแพงได้ตามปกติ) · คืน true ถ้าล็อกจริง
function BossService.lockUser(state: State, userId: number): boolean
	if not state.bossAlive then
		return false
	end
	state.lockedUsers[userId] = true
	return true
end

function BossService.isUserLocked(state: State, userId: number): boolean
	return state.lockedUsers[userId] == true
end

export type Contribution = { userId: number, damage: number }

-- ผู้ทำดาเมจบอสตัวนี้ เรียงมาก → น้อย (เท่ากัน = userId น้อยก่อน ให้ผลคงที่) — 5B ใช้แบ่งเงิน
function BossService.getContributors(state: State): { Contribution }
	local list: { Contribution } = {}
	for userId, damage in state.damageBy do
		if damage > 0 then
			table.insert(list, { userId = userId, damage = damage })
		end
	end
	table.sort(list, function(a, b)
		if a.damage ~= b.damage then
			return a.damage > b.damage
		end
		return a.userId < b.userId
	end)
	return list
end

-- บอสตีกลับ (ปิดไว้ใน config) — คืน userId ของทุกคนในระยะ · positions = { [userId] = ตำแหน่งตัวละคร }
function BossService.pickCounterTargets(state: State, bossPosition: Vector3, positions: { [number]: Vector3 }): { number }
	local cfg = cycleConfig()
	local targets: { number } = {}
	if not cfg.BOSS_ATTACK_ENABLED or state.phase ~= "day" or not state.bossAlive then
		return targets
	end
	for userId, position in positions do
		if BossService.horizontalDistance(position, bossPosition) <= cfg.BOSS_ATTACK_RANGE then
			table.insert(targets, userId)
		end
	end
	table.sort(targets)
	return targets
end

--------------------------------------------------------------------------------
-- 5B: ไข่บอส — ฟังก์ชันสถานะล้วน (ไม่แตะ Roblox · เทสต์เรียกตรงได้)
--------------------------------------------------------------------------------

-- หยิบไข่ฟองที่ index · คืน (ผล, ไข่ที่หยิบได้)
-- ผล: "ok" · "invalid" (index ไม่ใช่จำนวนเต็มในช่วง — ทิ้งเงียบ ๆ) · "alive" (บอสยังไม่ตาย) · "carrying" (ถืออยู่แล้ว 1 ฟอง)
--     · "taken" (ฟองนั้นไม่อยู่แล้ว / ยังไม่มีไข่) · "range" (ไม่อยู่ในห้อง หรือไกลกว่า EggPickupRange)
-- ⚠️ distance / inRoom มาจากตำแหน่งตัวละครที่ server เห็นเท่านั้น (runtime วัดเอง) — ไม่รับจาก client
function BossService.pickUpEgg(
	state: State,
	userId: number,
	index: any,
	distance: number,
	inRoom: boolean
): (string, BossEgg?)
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > cycleConfig().EGGS_PER_NIGHT then
		return "invalid", nil
	end
	if state.bossAlive then
		return "alive", nil
	end
	if state.carrying[userId] ~= nil then
		return "carrying", nil
	end
	local egg = state.eggs[index]
	if egg == nil or egg.status ~= "resting" then
		return "taken", nil
	end
	if not inRoom or distance > Config.MapDimensions.BossArena.EggPickupRange then
		return "range", nil
	end
	egg.status = "carried"
	egg.carrier = userId
	state.carrying[userId] = index
	return "ok", egg
end

-- 5B-fix (ผู้ใช้สั่ง): ต้นกลางคืนวาปมาหน้าป้อม**เฉพาะคนที่อยู่ในสนามรบ** (นอกเซฟโซน) — คนในคอก/ลานอยู่ที่เดิม
-- ⚠️ position = ตำแหน่งตัวละครที่ server เห็น
function BossService.shouldGatherAtNight(position: Vector3): boolean
	return not Config.isInSafeZone(position)
end

-- ไข่ที่คนนี้ถืออยู่ (nil = ไม่ได้ถือ)
function BossService.getCarriedEgg(state: State, userId: number): BossEgg?
	local index = state.carrying[userId]
	return if index then state.eggs[index] else nil
end

-- เข้ากระเป๋าสำเร็จแล้ว → ไข่ฟองนั้นหมดไป · คืนไข่ที่ส่งถึง (nil = ไม่ได้ถืออะไร — เรียกซ้ำไม่ได้ไข่ซ้ำ)
-- ⚠️ runtime เรียก **หลัง** EggService.grantBossEgg สำเร็จเท่านั้น (เต็ม = ยังถือค้างไว้)
function BossService.completeDelivery(state: State, userId: number): BossEgg?
	local egg = BossService.getCarriedEgg(state, userId)
	state.carrying[userId] = nil
	if egg == nil then
		return nil
	end
	egg.status = "gone"
	egg.carrier = nil
	return egg
end

-- ส่งไข่ที่ถือเข้ากระเป๋า **ถ้าอยู่ในเซฟโซน** · grant(eggId, weight) = ทางเพิ่มไข่เดิม (runtime ส่ง EggService.grantBossEgg)
-- คืน (ผล, ไข่): "none" (ไม่ได้ถือ) · "outside" (ยังไม่ถึงเซฟโซน) · "full" (เข้ากระเป๋าไม่ได้ — ยังถือค้างไว้) ·
--   "delivered" (เข้ากระเป๋าแล้ว ไข่ฟองนั้นหมดไป — เรียกซ้ำได้ "none" = ได้ไข่ครั้งเดียวพอดี)
-- ⚠️ position = ตำแหน่งตัวละครที่ server เห็น
function BossService.tryDeliver(
	state: State,
	userId: number,
	position: Vector3,
	grant: (eggId: string, weight: number) -> boolean
): (string, BossEgg?)
	local egg = BossService.getCarriedEgg(state, userId)
	if egg == nil then
		return "none", nil
	end
	if not Config.isInSafeZone(position) then
		return "outside", egg
	end
	if not grant(egg.eggId, egg.weight) then
		return "full", egg
	end
	BossService.completeDelivery(state, userId)
	return "delivered", egg
end

-- ทิ้งไข่ที่ถือ (ออกเกม / ตาย) → กลับไปวางที่จุดเดิม หยิบใหม่ได้ · คืนไข่ฟองนั้น
function BossService.dropCarriedEgg(state: State, userId: number): BossEgg?
	local egg = BossService.getCarriedEgg(state, userId)
	state.carrying[userId] = nil
	if egg == nil then
		return nil
	end
	egg.status = "resting"
	egg.carrier = nil
	return egg
end

-- น้ำหนักไข่ฟองที่หนักที่สุดในชุดนี้ **ถ้าเกิน** HEAVY_EGG_ALERT_KG (มากกว่า ไม่ใช่เท่ากับ) · ไม่เกิน = nil (ไม่ประกาศ)
function BossService.getHeavyEggAlert(state: State): number?
	local heaviest: number? = nil
	for _, egg in state.eggs do
		if heaviest == nil or egg.weight > heaviest then
			heaviest = egg.weight
		end
	end
	if heaviest and heaviest > cycleConfig().HEAVY_EGG_ALERT_KG then
		return heaviest
	end
	return nil
end

-- คนที่ได้ส่วนแบ่งเงินบอสตัวนี้: ทำดาเมจ ≥ Economy.BOSS_REWARD_MIN_DAMAGE **และ** isPresent(userId) = ยังอยู่ในห้องตอนบอสตาย
-- (runtime ส่ง isPresent ที่เช็คตำแหน่งตัวละครจริง — ออกเกมแล้ว/อยู่นอกห้อง = false) · เรียงตาม userId ให้ผลคงที่
function BossService.getRewardRecipients(state: State, isPresent: (userId: number) -> boolean): { number }
	local minDamage = Config.Balance.Economy.BOSS_REWARD_MIN_DAMAGE
	local recipients: { number } = {}
	for userId, damage in state.damageBy do
		if damage >= minDamage and isPresent(userId) then
			table.insert(recipients, userId)
		end
	end
	table.sort(recipients)
	return recipients
end

-- ส่วนแบ่งต่อคน = ปัดลง (total ÷ count) · ไม่มีใคร = 0 · รวมทุกคนแล้วไม่เกิน total เสมอ (ไม่สร้างเงินจากการปัด)
function BossService.splitReward(total: number, count: number): number
	if count <= 0 or total <= 0 then
		return 0
	end
	return math.floor(total / count)
end

-- แผนจ่ายเงินบอสตัวนี้: (ส่วนแบ่งต่อคน, รายชื่อคนได้) — เงินก้อน BossCycle.KILL_REWARD
function BossService.planReward(state: State, isPresent: (userId: number) -> boolean): (number, { number })
	local recipients = BossService.getRewardRecipients(state, isPresent)
	return BossService.splitReward(cycleConfig().KILL_REWARD, #recipients), recipients
end

-- ข้อความสรุปสถานะ (คำสั่ง debug + log)
function BossService.describe(state: State, now: number): string
	local phaseText = if state.phase == "night" then "กลางคืน" else "กลางวัน"
	local bossText = if state.bossAlive
		then `บอส HP {Config.formatCoins(state.bossHp)}/{Config.formatCoins(state.bossMaxHp)}`
		else "ไม่มีบอส"
	local parts: { string } = {}
	for _, entry in BossService.getContributors(state) do
		table.insert(parts, `{entry.userId}={entry.damage}`)
	end
	local locked = 0
	for _ in state.lockedUsers do
		locked += 1
	end
	local eggParts: { string } = {}
	for _, egg in state.eggs do
		local tag = if egg.status == "carried" then `ถือ:{egg.carrier}` elseif egg.status == "gone" then "เก็บแล้ว" else "วาง"
		table.insert(eggParts, `#{egg.index} {Config.formatCoins(egg.weight)}กก.({tag})`)
	end
	return `{phaseText} (คืนที่ {state.cycle}) · เหลือ {math.ceil(BossService.getRemaining(state, now))} วิ · {bossText}`
		.. ` · ผู้ทำดาเมจ: {if #parts > 0 then table.concat(parts, ", ") else "-"} · ล็อกอัญเชิญ {locked} คน`
		.. ` · ไข่: {if #eggParts > 0 then table.concat(eggParts, " ") else "-"}`
end

--------------------------------------------------------------------------------
-- runtime — สถานะของเซิร์ฟนี้ + ต่อสาย Roblox (Main.server.lua เรียก start() ครั้งเดียว)
--------------------------------------------------------------------------------
-- ⚠️ require ของจริงทั้งหมดอยู่ในตัว start() เหมือน CombatService.start — ไฟล์นี้ require จากเทสต์ได้

local current: State? = nil
local serverNow: () -> number = function()
	return os.clock()
end
-- ให้คำสั่ง debug อัปเดตโลก/แจ้งเตือนผ่านทางเดียวกับลูปจริง (start ตั้งให้)
local applyEvents: (events: { string }) -> () = function(_events) end
local onBossKilled: () -> () = function() end
local refreshWorld: () -> () = function() end
local onUserLocked: (userId: number) -> () = function(_userId) end

-- ⚠️ ก่อน start() ยังไม่มีบอส → ไม่มีใครถูกล็อก (เทสต์ของ CombatService/EggService ไม่ต้องรู้จักไฟล์นี้)
function BossService.isLocked(userId: number): boolean
	return current ~= nil and BossService.isUserLocked(current, userId)
end

function BossService.isBossAlive(): boolean
	return current ~= nil and current.bossAlive
end

-- ล็อกผู้เล่นคนนี้ (CombatService.start เรียกหลัง tick) + แจ้งเขาคนเดียวว่าทำไมทหารหยุด
function BossService.lock(userId: number): boolean
	if current == nil then
		return false
	end
	local wasLocked = BossService.isUserLocked(current, userId)
	local locked = BossService.lockUser(current, userId)
	if locked and not wasLocked then
		onUserLocked(userId)
	end
	return locked
end

export type Gate = {
	isBossAlive: () -> boolean,
	isUserLocked: (userId: number) -> boolean,
	lockUser: (userId: number) -> boolean,
}

-- ตัวกลางที่ CombatService.start รับไป (inject แทน require กัน CombatService ผูกกับไฟล์นี้)
function BossService.getGate(): Gate
	return {
		isBossAlive = BossService.isBossAlive,
		isUserLocked = BossService.isLocked,
		lockUser = BossService.lock,
	}
end

local BARRIER_NIGHT_TRANSPARENCY = 0 -- 5B: ขาวทึบ (เดิม 0.35 โปร่ง)
local WORLD_TICK = 0.25 -- วินาที — จังหวะเช็คเปลี่ยน phase · ถือ/เก็บอาวุธ · บอสตีกลับ · ส่งไข่ที่เซฟโซน
local CARRY_ABOVE_ROOT = 3 -- ไข่ที่ถือลอยเหนือ HumanoidRootPart เท่านี้ + รัศมีไข่ (อยู่เหนือหัวพอดี)
local PICKUP_REQUEST_COOLDOWN = 0.25 -- วินาที — กันยิงคำขอหยิบรัว (server นับเอง)

-- ผลหยิบไข่ → kind ของ BossEventNotify (ข้อความจริงอยู่ที่ Config.formatBossEventMessage)
local PICKUP_FAIL_KIND: { [string]: string } = {
	alive = "pickupAlive",
	carrying = "pickupCarrying",
	taken = "pickupTaken",
	range = "pickupRange",
}

-- ทางเข้ากระเป๋าไข่ของ EggService (inject ผ่าน start — กัน BossService require EggService ตรง ๆ)
export type GrantBossEgg = (player: Player, eggId: string, weight: number) -> (boolean, string?)

local function makeWeapon(): Tool
	local tool = Instance.new("Tool")
	tool.Name = Config.WEAPON_TOOL_NAME
	tool.ToolTip = "อาวุธ — คลิกเพื่อตีบอส"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 4, 0.4) -- blockout ดาบ
	handle.Color = Color3.fromRGB(200, 205, 215)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	return tool
end

-- grantBossEgg = EggService.grantBossEgg (ทางเพิ่มไข่เดิม) · syncPlayer = EggService.sync (ส่งเงิน/ไข่ใหม่ให้ client ทันที)
function BossService.start(grantBossEgg: GrantBossEgg, syncPlayer: (player: Player) -> ())
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local Workspace = game:GetService("Workspace")
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	local DataService = require(ServerScriptService.DataService)

	serverNow = function()
		return Workspace:GetServerTimeNow()
	end
	-- Random ของ Roblox มี NextInteger ตรงกับชนิด Rng (cast กัน type checker มองว่าเป็น userdata คนละชนิด)
	local state = BossService.newState(serverNow(), Random.new() :: any)
	current = state

	local notify = Remotes.waitFor(Config.RemoteNames.BOSS_EVENT_NOTIFY)
	local pickupRequest = Remotes.waitFor(Config.RemoteNames.PICK_UP_BOSS_EGG_REQUEST)

	-- ของในโลก — MapBuilder.buildBossArena สร้างไว้แล้ว (Main เรียก MapBuilder.build ก่อน start)
	local arena = Workspace:WaitForChild("Map"):WaitForChild(Config.BOSS_ARENA_NAME)
	local barrier = arena:WaitForChild(Config.BOSS_BARRIER_NAME) :: BasePart
	local boss = arena:WaitForChild(Config.BOSS_MODEL_NAME) :: Model
	local hpFill = boss:FindFirstChild("HpFill", true) :: Frame?
	local hpText = boss:FindFirstChild("HpText", true) :: TextLabel?
	local eggFolder = arena:WaitForChild(Config.BOSS_EGG_FOLDER)
	local eggParts: { BasePart } = {}
	for index = 1, cycleConfig().EGGS_PER_NIGHT do
		eggParts[index] = eggFolder:WaitForChild(`BossEgg{index}`) :: BasePart
	end

	-- สถานะที่ client อ่าน (ทุกคนเห็นค่าเดียวกัน) — Attribute ของ Folder นี้ replicate ให้เอง
	local stateFolder = Instance.new("Folder")
	stateFolder.Name = Config.BOSS_STATE_FOLDER
	stateFolder.Parent = ReplicatedStorage

	local function aliveRoot(player: Player): BasePart?
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and humanoid.Health > 0 then
			return root
		end
		return nil
	end

	-- ไข่ในห้อง: ขนาดตามน้ำหนัก · โชว์เฉพาะฟองที่วางอยู่ · Attribute ให้ client ติด/เปิดจุดกด E
	-- ⚠️ 5B-fix (ผู้ใช้สั่ง "ให้ผู้เล่นลุ้น"): **ไม่มีป้ายน้ำหนัก และไม่ส่งน้ำหนักให้ client** (ไม่มี Attribute Weight) —
	--   เห็นแค่ขนาดไข่ · น้ำหนักจริงเฉลยตอนเก็บเข้ากระเป๋า ("delivered") · ประกาศไข่หนักต้นคืนยังอยู่ (บอกแค่ฟองหนักสุด)
	local function publishEggs()
		for index, part in eggParts do
			local egg = state.eggs[index]
			local resting = egg ~= nil and egg.status == "resting"
			if egg then
				local size = Config.getEggVisualSize(egg.weight)
				local spot = Config.getBossCycleEggSpot(index)
				part.Size = size
				part.Position = Vector3.new(spot.X, Config.getBallRadius(size), spot.Z)
			end
			part.Transparency = if resting then 0 else 1
			part:SetAttribute("Status", if egg then egg.status else "none")
		end
	end

	-- ไข่ที่ถือ: ลูกบอลเชื่อมกับตัวคนถือ (ของ server ใน character → ทุกคนเห็น) · ไม่มีมวล ไม่ชน = ไม่ช้าลง
	local carriedParts: { [number]: BasePart } = {}
	local function attachCarried(player: Player, egg: BossEgg): BasePart?
		local root = aliveRoot(player)
		local character = player.Character
		if not root or not character then
			return nil
		end
		local size = Config.getEggVisualSize(egg.weight)
		local part = Instance.new("Part")
		part.Name = Config.BOSS_CARRIED_EGG_NAME
		part.Shape = Enum.PartType.Ball
		part.Size = size
		part.Color = eggParts[egg.index].Color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = root.CFrame * CFrame.new(0, CARRY_ABOVE_ROOT + Config.getBallRadius(size), 0)
		part:SetAttribute("Index", egg.index)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = character
		return part
	end

	-- ให้ภาพไข่ที่ถือตรงกับสถานะ (สร้าง/ลบ) + Attribute บน Player ให้ client ปิดจุดกด E ตอนถืออยู่
	local function syncCarriedVisuals()
		for _, player in Players:GetPlayers() do
			local userId = player.UserId
			local egg = BossService.getCarriedEgg(state, userId)
			local existing = carriedParts[userId]
			local valid = existing ~= nil
				and egg ~= nil
				and existing.Parent ~= nil
				and existing.Parent == player.Character
				and existing:GetAttribute("Index") == egg.index
			if not valid then
				if existing then
					existing:Destroy()
					carriedParts[userId] = nil
				end
				if egg then
					carriedParts[userId] = attachCarried(player, egg)
				end
			end
			player:SetAttribute(Config.BOSS_EGG_CARRY_ATTRIBUTE, egg ~= nil)
		end
		-- คนที่ออกไปแล้วแต่ภาพยังค้าง (ปกติ character ถูกลบไปพร้อมกัน — กันไว้)
		for userId, part in carriedParts do
			if Players:GetPlayerByUserId(userId) == nil then
				part:Destroy()
				carriedParts[userId] = nil
			end
		end
	end

	local function publish()
		stateFolder:SetAttribute("Phase", state.phase)
		stateFolder:SetAttribute("PhaseEndsAt", state.phaseEndsAt)
		stateFolder:SetAttribute("BossAlive", state.bossAlive)
		stateFolder:SetAttribute("BossHp", state.bossHp)
		stateFolder:SetAttribute("BossMaxHp", state.bossMaxHp)
		stateFolder:SetAttribute("Cycle", state.cycle)

		-- กำแพงกั้น: กลางคืนชนได้ + มองเห็น · กลางวันหายไป (ชิ้นเดิมอยู่ตลอด — client ติดตัวเลขนับถอยหลังไว้)
		local night = state.phase == "night"
		barrier.CanCollide = night
		barrier.CanQuery = night
		barrier.Transparency = if night then BARRIER_NIGHT_TRANSPARENCY else 1

		-- บอส: ไม่มีชีวิต = ถอดออกจากโลก (client ไม่เห็น · ไม่ชน) · เกิด = ใส่กลับ
		boss.Parent = if state.bossAlive then arena else nil
		if hpFill then
			hpFill.Size = UDim2.fromScale(if state.bossMaxHp > 0 then state.bossHp / state.bossMaxHp else 0, 1)
		end
		if hpText then
			hpText.Text = `บอส  {Config.formatCoins(state.bossHp)} / {Config.formatCoins(state.bossMaxHp)}`
		end

		-- 5B: ไข่ในห้อง + ไข่ที่ถือ
		publishEggs()
		syncCarriedVisuals()
	end

	-- ต้นกลางคืน: วาปคนที่อยู่ในสนามรบมาหน้าป้อม (คนที่เข้าเกม/เกิดใหม่ระหว่างคืนเกิดตามปกติ ไม่วาป)
	-- 5B: หน้าป้อม = ฝั่งลานกลาง หน้ากำแพงกั้นที่ปิดปากเลน (หันหน้า +X เข้าหาตัวเลข)
	-- ⚠️ 5B-fix: **เฉพาะคนที่อยู่ในสนามรบ** (shouldGatherAtNight) — คนในคอก/ลานกลางไม่ถูกวาป ·
	--   จุดยืนนับเฉพาะคนที่ถูกวาป (คนแรกได้จุด 1 · ไม่เว้นจุดให้คนที่อยู่ในลานอยู่แล้ว)
	local function gatherEveryone()
		local index = 0
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if
				character
				and humanoid
				and root
				and humanoid.Health > 0
				and BossService.shouldGatherAtNight(root.Position)
			then
				index += 1
				humanoid:UnequipTools()
				local spot = Config.getBossGatherSpot(index)
				local position = Vector3.new(spot.X, spot.Y + Config.MapDimensions.Player.Height, spot.Z)
				-- หันหน้าเข้ากำแพงกั้น (+X) ให้เห็นตัวเลขนับถอยหลังทันที
				character:PivotTo(CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
			end
		end
	end

	applyEvents = function(events: { string })
		if #events == 0 then
			return
		end
		for _, kind in events do
			if kind == "night" then
				-- ⚠️ 5B: ลำดับสำคัญ — ไข่ที่ถือหาย (ภาพ) **ก่อน** วาป · ไข่ชุดใหม่ขึ้นห้องพร้อมบอส
				publish()
				for _, userId in state.lostCarriers do
					local player = Players:GetPlayerByUserId(userId)
					if player then
						notify:FireClient(player, "eggLost")
					end
				end
				table.clear(state.lostCarriers)
				gatherEveryone()
			end
			notify:FireAllClients(kind)
			if kind == "night" then
				-- ประกาศไข่หนัก (ทั้งเซิร์ฟ) เฉพาะคืนที่มีไข่เกิน HEAVY_EGG_ALERT_KG
				local heavy = BossService.getHeavyEggAlert(state)
				if heavy then
					notify:FireAllClients("heavy", heavy)
				end
			end
		end
		publish()
		print(`[BossService] {table.concat(events, " → ")} · {BossService.describe(state, serverNow())}`)
	end

	refreshWorld = publish

	onUserLocked = function(userId: number)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			notify:FireClient(player, "locked")
		end
	end

	-- 5B: เงินก้อนเดียว แบ่งเท่ากัน (ปัดลง) ให้คนที่ทำดาเมจ + ยังอยู่ในห้องตอนบอสตาย · หลุดออก/อยู่นอกห้อง = ไม่ได้
	local function payBossReward()
		local share, recipients = BossService.planReward(state, function(userId: number): boolean
			local player = Players:GetPlayerByUserId(userId)
			local root = player and aliveRoot(player)
			return root ~= nil and Config.isInBossArena(root.Position)
		end)
		local paid: { string } = {}
		for _, userId in recipients do
			local player = Players:GetPlayerByUserId(userId)
			local data = DataService.getCached(userId)
			if player and data and share > 0 then
				data.currency.coins += share
				syncPlayer(player)
				notify:FireClient(player, "reward", share, #recipients)
				table.insert(paid, player.Name)
			end
		end
		print(
			`[BossService] เงินบอส {cycleConfig().KILL_REWARD} แบ่ง {#recipients} คน คนละ {share}`
				.. ` · ได้จริง: {if #paid > 0 then table.concat(paid, ", ") else "-"}`
		)
	end

	onBossKilled = function()
		publish()
		notify:FireAllClients("killed")
		payBossReward()
		print(`[BossService] กำจัดบอสแล้ว · {BossService.describe(state, serverNow())}`)
	end

	local function onAttack(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local data = DataService.getCached(player.UserId)
		if not humanoid or not root or humanoid.Health <= 0 or not data then
			return
		end
		-- 5B: บอสยืนมุมห้อง — วัดระยะจากตัวบอสจริง (Config.getBossPosition) ไม่ใช่กึ่งกลางห้อง
		local distance = BossService.horizontalDistance(root.Position, Config.getBossPosition())
		local result, _, killed = BossService.tryAttack(state, player.UserId, serverNow(), distance, data.weaponLevel or 1)
		if result ~= "ok" then
			return
		end
		if killed then
			onBossKilled()
		else
			publish()
		end
	end

	-- อาวุธใส่ Backpack ใหม่ทุกครั้งที่เกิด (Backpack ถูกล้างตอนตาย) · Tool.Activated ยิงถึง server เอง
	local function giveWeapon(player: Player)
		local backpack = player:WaitForChild("Backpack", 10)
		if not backpack or backpack:FindFirstChild(Config.WEAPON_TOOL_NAME) then
			return
		end
		local tool = makeWeapon()
		tool.Activated:Connect(function()
			onAttack(player)
		end)
		tool.Parent = backpack
	end

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(giveWeapon, player)
		end)
		if player.Character then
			task.spawn(giveWeapon, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	-- ══ 5B: หยิบไข่ ══ client ส่งแค่ index ของฟองที่กด E · server ตัดสินทุกอย่างเอง (ระยะวัดจากตัวละครที่ server เห็น)
	local lastPickupAt: { [number]: number } = {}
	local bagFullWarned: { [number]: boolean } = {}
	pickupRequest.OnServerEvent:Connect(function(player: Player, rawIndex: unknown)
		local userId = player.UserId
		local clockNow = os.clock()
		if lastPickupAt[userId] and clockNow - lastPickupAt[userId] < PICKUP_REQUEST_COOLDOWN then
			return
		end
		lastPickupAt[userId] = clockNow
		local root = aliveRoot(player)
		if not root then
			return
		end
		local total = cycleConfig().EGGS_PER_NIGHT
		local distance = math.huge
		if type(rawIndex) == "number" and rawIndex % 1 == 0 and rawIndex >= 1 and rawIndex <= total then
			distance = BossService.horizontalDistance(root.Position, Config.getBossCycleEggSpot(rawIndex))
		end
		local result, egg = BossService.pickUpEgg(state, userId, rawIndex, distance, Config.isInBossArena(root.Position))
		if result == "ok" and egg then
			bagFullWarned[userId] = nil
			publish()
			-- 5B-fix: ไม่บอกน้ำหนักตอนหยิบ (ให้ลุ้น) — เฉลยตอนเข้ากระเป๋า ("delivered")
			notify:FireClient(player, "picked")
			print(`[BossService] {player.Name} หยิบไข่ #{egg.index} ({egg.weight} กก.)`)
		elseif PICKUP_FAIL_KIND[result] then
			notify:FireClient(player, PICKUP_FAIL_KIND[result])
		end
	end)

	-- ไข่ที่ถือกลับจุดเดิม (ออกเกม / ตาย / รีเซ็ต) — หยิบใหม่ได้
	local function dropEgg(userId: number, reason: string)
		local egg = BossService.dropCarriedEgg(state, userId)
		bagFullWarned[userId] = nil
		if egg then
			publish()
			print(`[BossService] ไข่ #{egg.index} กลับจุดเดิม ({reason} · userId {userId})`)
		end
	end

	-- ส่งไข่: คนถือที่อยู่ในเซฟโซน (ตำแหน่งที่ server เห็น) → เข้ากระเป๋าผ่าน EggService.grantBossEgg ครั้งเดียว
	-- เต็ม = ยังถือค้างไว้ (แจ้งครั้งเดียวต่อการถือ) · ไม่มีตัวละคร/ตายแล้ว = ไข่กลับจุดเดิม
	local function updateCarriers()
		local carriers: { number } = {}
		for userId in state.carrying do
			table.insert(carriers, userId)
		end
		for _, userId in carriers do
			local player = Players:GetPlayerByUserId(userId)
			local root = player and aliveRoot(player)
			if not player then
				dropEgg(userId, "ออกเกม")
			elseif not root then
				dropEgg(userId, "ตาย/ไม่มีตัวละคร")
			else
				local grantError: string? = nil
				local result, egg = BossService.tryDeliver(state, userId, root.Position, function(eggId: string, weight: number): boolean
					local ok, err = grantBossEgg(player, eggId, weight)
					grantError = err
					return ok
				end)
				if result == "delivered" and egg then
					bagFullWarned[userId] = nil
					publish()
					notify:FireClient(player, "delivered", egg.weight)
					print(`[BossService] {player.Name} เก็บไข่บอส #{egg.index} ({egg.weight} กก.) เข้ากระเป๋าแล้ว`)
				elseif result == "full" and not bagFullWarned[userId] then
					bagFullWarned[userId] = true
					notify:FireClient(player, "bagFull")
					warn(`[BossService] {player.Name} เก็บไข่บอสไม่ได้: {grantError or "-"}`)
				end
			end
		end
	end

	-- ⚠️ ไม่ล้าง lockedUsers ตอนออกเกม — ออกแล้วเข้าเซิร์ฟเดิมยังล็อกอยู่ (ตั้งใจ · กันออก-เข้าเพื่อหลุดล็อก)
	Players.PlayerRemoving:Connect(function(player: Player)
		state.lastAttackAt[player.UserId] = nil
		lastPickupAt[player.UserId] = nil
		-- 5B: ออกเกมระหว่างถือไข่ → ไข่กลับจุดเดิม หยิบใหม่ได้
		dropEgg(player.UserId, "ออกเกม")
	end)

	-- ถือ/เก็บอาวุธอัตโนมัติ: กลางวัน + บอสยังอยู่ + อยู่ในเขตบอส = ถือ · นอกนั้นเก็บ
	local function updateWeapons()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and humanoid and root and humanoid.Health > 0 then
				local shouldHold = state.phase == "day" and state.bossAlive and Config.isInBossArena(root.Position)
				local holding = character:FindFirstChild(Config.WEAPON_TOOL_NAME)
				if shouldHold and not holding then
					local backpack = player:FindFirstChildOfClass("Backpack")
					local tool = backpack and backpack:FindFirstChild(Config.WEAPON_TOOL_NAME)
					if tool and tool:IsA("Tool") then
						humanoid:EquipTool(tool)
					end
				elseif holding and not shouldHold then
					humanoid:UnequipTools()
				end
			end
		end
	end

	-- บอสตีกลับ (BOSS_ATTACK_ENABLED = false ตอนนี้ — pickCounterTargets คืนว่างเสมอ)
	local nextCounterAt = 0
	local function counterAttack(now: number)
		if now < nextCounterAt then
			return
		end
		nextCounterAt = now + cycleConfig().BOSS_ATTACK_INTERVAL
		local positions: { [number]: Vector3 } = {}
		local humanoids: { [number]: Humanoid } = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoid and root and humanoid.Health > 0 then
				positions[player.UserId] = root.Position
				humanoids[player.UserId] = humanoid
			end
		end
		for _, userId in BossService.pickCounterTargets(state, Config.getBossPosition(), positions) do
			humanoids[userId]:TakeDamage(cycleConfig().BOSS_ATTACK_DAMAGE)
		end
	end

	publish()
	print(`[BossService] เริ่มวงจรกลางวัน/กลางคืน · {BossService.describe(state, serverNow())}`)

	task.spawn(function()
		while true do
			task.wait(WORLD_TICK)
			local now = serverNow()
			applyEvents(BossService.step(state, now))
			updateWeapons()
			counterAttack(now)
			updateCarriers()
		end
	end)
end

--------------------------------------------------------------------------------
-- คำสั่ง debug (Studio · เรียกผ่านสะพาน ServerStorage.EggServiceDebug — ดู docs/debug-commands.md)
--------------------------------------------------------------------------------
-- ⚠️ ใช้ทางเดียวกับลูปจริง (applyEvents / applyDamage / onBossKilled) — ไม่มีทางลัดที่ข้ามกติกา

local function requireState(): State
	assert(current, "BossService ยังไม่ start (ต้องรันในเกมที่กด Play แล้ว)")
	return current :: State
end

-- ข้ามไปต้นกลางคืนทันที: วาปคนในสนามรบมาหน้าป้อม · กำแพงกั้นขึ้น · บอสเกิด/ฟื้น HP เต็ม · นับ 59 → 0 ใหม่ · ไข่ชุดใหม่ 6 ฟอง
-- 5B: rawFirstEggKg (ไม่ใส่ได้) = บังคับน้ำหนักไข่ฟองที่ 1 ของชุดใหม่ (kg จำนวนเต็ม ≥ 100) **ก่อน** ประกาศ/โชว์ —
--   ใช้ทดสอบประกาศไข่หนัก (> HEAVY_EGG_ALERT_KG) โดยไม่ต้องรอดวง · ไม่ใส่ = สุ่มตามปกติทุกฟอง
function BossService.debugBossNight(rawFirstEggKg: number?): string
	local state = requireState()
	local events = BossService.forcePhase(state, "night", serverNow())
	local forced = tonumber(rawFirstEggKg)
	if forced and state.eggs[1] then
		state.eggs[1].weight = math.max(100, math.floor(forced))
	end
	applyEvents(events)
	return BossService.describe(state, serverNow())
end

-- 5B: สถานะไข่บอสทุกฟอง (น้ำหนัก · วาง/ถือ/เก็บแล้ว · ใครถือ) — เหมือนท้าย debugBossStatus แต่เน้นไข่
function BossService.debugBossEggs(): string
	local state = requireState()
	local lines: { string } = {}
	for _, egg in state.eggs do
		table.insert(
			lines,
			`#{egg.index} {Config.formatCoins(egg.weight)} กก. · {egg.status}{if egg.carrier then ` (userId {egg.carrier})` else ""}`
		)
	end
	local phase = if state.bossAlive then "บอสยังอยู่ — ยังหยิบไม่ได้" else "บอสไม่อยู่ — หยิบได้ (ถ้าไข่ยังวางอยู่)"
	return `{phase}\n{if #lines > 0 then table.concat(lines, "\n") else "ยังไม่มีไข่ (รอคืนแรก — debugBossNight)"}`
end

-- ข้ามไปต้นกลางวันทันที: กำแพงกั้นหาย เข้าไปตีบอสได้ (บอสต้องเกิดก่อน — ใช้ debugBossNight ก่อนถ้ายังไม่มี)
function BossService.debugBossDay(): string
	local state = requireState()
	applyEvents(BossService.forcePhase(state, "day", serverNow()))
	return BossService.describe(state, serverNow())
end

-- ทำดาเมจใส่บอสในนามผู้เล่นคนนั้น (นับเข้าบันทึกผู้ทำดาเมจเหมือนตีจริง) · กติกาเดิม: กลางวัน + บอสยังอยู่
function BossService.debugDamageBoss(player: Player, rawAmount: number): string
	local state = requireState()
	local amount = tonumber(rawAmount)
	if not amount or amount <= 0 then
		return "ใส่จำนวนดาเมจเป็นตัวเลขมากกว่า 0 เช่น debugDamageBoss(player, 300)"
	end
	if state.phase ~= "day" then
		return "ตีไม่ได้ตอนกลางคืน — ใช้ debugBossDay ก่อน"
	end
	if not state.bossAlive then
		return "ไม่มีบอสให้ตี — ใช้ debugBossNight ก่อน (แล้ว debugBossDay)"
	end
	local dealt, killed = BossService.applyDamage(state, player.UserId, amount, serverNow())
	if killed then
		onBossKilled()
	else
		refreshWorld()
	end
	return `ดาเมจเข้า {dealt}{if killed then " — บอสตาย" else ""} · {BossService.describe(state, serverNow())}`
end

-- ฆ่าบอสในนามผู้เล่นคนนั้น (ดาเมจเท่า HP ที่เหลือ) — ปลดล็อกอัญเชิญทุกคน
function BossService.debugKillBoss(player: Player): string
	local state = requireState()
	return BossService.debugDamageBoss(player, math.max(1, state.bossHp))
end

function BossService.debugBossStatus(): string
	local state = requireState()
	return BossService.describe(state, serverNow())
end

return BossService
