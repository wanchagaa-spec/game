--!strict
-- egg-army-game :: วงจรกลางวัน/กลางคืน + บอสทุกห้อง (Phase 5A → 5B → 5B-2)
--
-- ══ กติกา (ผู้ใช้ยืนยันแล้ว) ══
--   รอบละ DAY + NIGHT วินาที (Config.Balance.BossCycle · 9 + 1 นาที) วนตลอด · เซิร์ฟเปิดใหม่เริ่มต้นกลางวันเสมอ
--   กลางคืน: วาปคนที่อยู่ในสนามรบมาหน้าป้อม (5B-fix — คนในคอก/ลานอยู่ที่เดิม) · กำแพงกั้นชิ้นเดียวที่ปากเลนขึ้น (กันเฉพาะผู้เล่น)
--     · **บอสทั้ง 9 ห้องเกิดพร้อมกัน** (5B-2) — ตัวที่ยังไม่ตาย = ฟื้น HP เต็ม · ไข่ทุกห้องรีเซ็ตเป็น 6 ฟองใหม่
--   กลางวัน: กำแพงกั้นหาย แต่ละคนวิ่งไปห้องที่ตัวเองมีสิทธิ์ · บอสห้องไหนตายแล้วหายไปจนคืนถัดไป
--   ตีบอส = อาวุธ (Tool) ที่ server ใส่ Backpack ให้ · ถือ/เก็บอัตโนมัติตามห้องบอสที่มีสิทธิ์ (Backpack เดิมของ Roblox ปิดอยู่)
--   ⚠️ ระบบ personal combat ของ Phase 4 **ยังไม่มีในโค้ด** — รอบนี้ทำขั้นต่ำเท่าที่ต้องใช้ตีบอส (ผู้ใช้เลือก)
--     ดาเมจ = Config.getWeaponDamage(weaponLevel) ตัวเดิม · ยังไม่มี PvP · บอสตีกลับปิดไว้ใน config
--
-- ══ 5B-2: บอสทุกห้อง (ผู้ใช้ยืนยันแล้ว · แผนเต็ม docs/boss-plan.md) ══
--   ห้อง N = ช่วงเลนหลังกำแพงด่าน N ถึงกำแพงด่าน N+1 (Config.getStageRoomRangeX) · ห้อง 1 = ปากเลน → กำแพงด่าน 2
--   แต่ละห้องมี HP (Config.getBossHp) / บันทึกดาเมจ / สถานะตาย-เป็น / ไข่ 6 ฟอง (ชนิด Config.getBossEggId(N)) ของตัวเอง
--   ⚠️ **สิทธิ์ตรวจจากความคืบหน้า ไม่ใช่แค่ตำแหน่ง** (Config.canAccessBossRoom · wallProgress):
--     ตีบอส/หยิบไข่ห้อง N ได้เมื่อ พังกำแพงด่าน N แล้ว (ห้อง 1 ทุกคน) **และ** ยืนอยู่ในห้อง N (Config.getStageRoomAt)
--     คนที่ไปไกลกว่ามีสิทธิ์ทุกห้องที่ผ่านมาแล้ว · กำแพงด่านเป็นของ client → ตำแหน่งปลอมได้ ความคืบหน้าปลอมไม่ได้
--   เงินห้อง N = Config.getBossKillReward(N) แบ่งเท่ากัน (ปัดลง) ให้คนที่ทำดาเมจบอสห้อง N **และยังอยู่ในห้อง N ตอนบอสตาย**
--   หยิบไข่: server จับเวลากดค้างเอง (beginHold → pickUpEgg ≥ EGG_PICKUP_HOLD_SECONDS − EGG_PICKUP_HOLD_TOLERANCE)
--
-- ══ 5B: ไข่บอส ══
--   ต้นกลางคืน บอสเกิดพร้อมไข่ EGGS_PER_NIGHT ฟอง **สุ่มน้ำหนักทันที** (Config.rollMotherWeightForEgg ตัวเดิม) ขนาดไข่บอกน้ำหนัก
--     ไข่หนักเกิน HEAVY_EGG_ALERT_KG → ประกาศทั้งเซิร์ฟ (5B-2: ทุกห้องรวมข้อความเดียว) · ไข่ชุดเก่า (ที่วาง/ที่ถือ) หายหมด
--   หยิบได้ **หลังบอสห้องนั้นตายเท่านั้น** · ใครก็ได้ที่มีสิทธิ์และอยู่ในห้อง (ไม่ต้องเคยตี) · ถือได้ทีละฟอง (รวมทุกห้อง) · ไม่ช้าลง
--   ถือกลับถึงเซฟโซน (ลานกลาง) → เข้ากระเป๋าไข่ทันที (EggService.grantBossEgg = ทางเพิ่มไข่เดิม) · เต็ม = ถือค้างไว้
--   ออกเกม/ตายระหว่างถือ → ไข่กลับจุดเดิม หยิบใหม่ได้
--   ⚠️ server เป็นเจ้าของทุกสถานะ (ฟองไหนว่าง · ใครถือ · ระยะตอนหยิบ · ตำแหน่งตอนเข้าเซฟโซน) · client ส่งแค่ "กดฟองที่ i"
--
-- ══ ล็อกอัญเชิญ (5B-2: ผูกห้อง) ══ ทหารของใครพังกำแพงด่าน N ขณะบอสห้อง N ยังมีชีวิต → คนนั้นอัญเชิญต่อไม่ได้
--   จนกว่าบอสห้อง N ตาย (บอสห้องอื่นไม่เกี่ยว) · เก็บใน memory ของเซิร์ฟ (lockedUsers[userId] = ห้อง · **ไม่แตะ schema**)
--   ออกแล้วเข้าเซิร์ฟเดิมยังล็อกอยู่ · บอสไม่ตายข้ามคืน → ฟื้น HP เต็ม แต่ล็อกยังอยู่ · ตัวตัดสินอยู่ที่
--   CombatService.shouldBossLock (ด่านที่มีกำแพงจริงเท่านั้น) · CombatService.start ต่อสายผ่าน getGate()
--
-- ⚠️ ของทุกอย่างในไฟล์นี้ **ไม่เซฟ DataStore** — เวลากลางของเซิร์ฟ ไม่ผูกกับข้อมูลผู้เล่น
-- ⚠️ require สองทางเหมือน CombatService — ฟังก์ชันสถานะ (newState/step/applyDamage/...) เป็น Luau ล้วน
--   tests/boss.spec.luau เรียกตรงได้โดยส่ง `now` เอง · ของที่แตะ Roblox อยู่ใน start() เท่านั้น
local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") else nil
local Config = (if Shared then require(Shared.Config) else require("../shared/Config")) :: any

local BossService = {}

export type Phase = "day" | "night"

-- 5B: ไข่บอส 1 ฟอง · (room, index) = จุดวาง Config.getBossEggSpot(room, index)
--   "resting" = วางอยู่ในห้อง (หยิบได้เมื่อบอสห้องนั้นตาย) · "carried" = มีคนถือ · "gone" = เก็บเข้ากระเป๋าแล้ว
export type EggStatus = "resting" | "carried" | "gone"
export type BossEgg = {
	room: number, -- 5B-2: ห้องที่ไข่ฟองนี้อยู่
	index: number,
	eggId: string, -- = Config.getBossEggId(room)
	weight: number, -- kg จำนวนเต็ม — สุ่มตอนบอสเกิด ห้ามสุ่มใหม่
	status: EggStatus,
	carrier: number?, -- userId ของคนที่ถืออยู่ (status = "carried")
}

-- 5B-2: สถานะของห้องบอส 1 ห้อง (บอส 1 ตัว + ไข่ชุดของมัน)
export type Room = {
	room: number,
	bossAlive: boolean,
	bossHp: number,
	bossMaxHp: number,
	bossSpawnedAt: number?,
	bossDiedAt: number?,
	-- ⚠️ ใครทำดาเมจใส่บอสห้องนี้ "ตัวนี้" ไปเท่าไร (userId → ดาเมจที่เข้าจริง) — ล้างตอนบอสตัวใหม่เกิดเท่านั้น
	-- บอสตายแล้วยังเก็บไว้จนคืนถัดไป (อ่านตอนแบ่งเงิน)
	damageBy: { [number]: number },
	eggs: { BossEgg }, -- ไข่ชุดของบอสตัวปัจจุบัน (ว่างจนกว่าจะถึงคืนแรก)
}

-- ไข่ที่ถืออยู่ชี้ไปที่ (ห้อง, ฟอง) · 5B-2: จังหวะเริ่มกดค้างที่ server จดไว้
export type EggRef = { room: number, index: number }
export type Hold = { room: number, index: number, beganAt: number }

-- ตัวสุ่ม (Roblox Random หรือ stub ในเทสต์ที่มี NextInteger)
export type Rng = { NextInteger: (self: any, min: number, max: number) -> number }

export type State = {
	phase: Phase,
	phaseEndsAt: number, -- เวลา server (workspace:GetServerTimeNow) ที่ phase นี้จบ — client นับถอยหลังจากค่านี้
	cycle: number, -- นับคืน (เพิ่มทุกครั้งที่เข้ากลางคืน)
	rooms: { Room }, -- 5B-2: ห้อง 1..Stage.COUNT
	-- 5B-2: userId → ห้องที่ทำให้ติดล็อก (ปลดเมื่อบอสห้องนั้นตายเท่านั้น)
	lockedUsers: { [number]: number },
	lastAttackAt: { [number]: number },
	-- ══ 5B ══ ไม่เซฟ DataStore (เซิร์ฟปิด = ไข่ในห้อง/ไข่ที่ถือหายไปด้วย — ตั้งใจ)
	carrying: { [number]: EggRef }, -- userId → ไข่ที่ถืออยู่ (ถือได้ทีละฟอง รวมทุกห้อง)
	holds: { [number]: Hold }, -- 5B-2: userId → จังหวะเริ่มกดค้างล่าสุด (เวลา server)
	lostCarriers: { number }, -- คนที่ถือไข่อยู่ตอนไข่ชุดใหม่เกิด (ไข่ที่ถือหาย) — runtime แจ้งแล้วล้าง
	rng: Rng,
}

local function cycleConfig()
	return Config.Balance.BossCycle
end

local function roomCount(): number
	return Config.Balance.Stage.COUNT
end

-- เลขห้องถูกต้องไหม (จำนวนเต็ม 1..Stage.COUNT) — ค่าจาก client/คำสั่ง debug ต้องผ่านตัวนี้ก่อนใช้เสมอ
function BossService.isValidRoom(room: any): boolean
	return type(room) == "number" and room == room and room % 1 == 0 and room >= 1 and room <= roomCount()
end

local function isValidEggIndex(index: any): boolean
	return type(index) == "number"
		and index == index
		and index % 1 == 0
		and index >= 1
		and index <= cycleConfig().EGGS_PER_NIGHT
end

-- ตัวสุ่มสำรองเมื่อไม่ได้ส่งมา (เทสต์ส่ง stub เอง · start() ส่ง Random.new() ของ Roblox)
local function fallbackRng(): Rng
	return {
		NextInteger = function(_self: any, min: number, max: number): number
			return math.random(min, max)
		end,
	}
end

local function newRoom(room: number): Room
	return {
		room = room,
		bossAlive = false, -- เซิร์ฟเปิดใหม่ = ต้นกลางวัน ยังไม่มีบอสจนคืนแรก
		bossHp = 0,
		bossMaxHp = Config.getBossHp(room),
		bossSpawnedAt = nil,
		bossDiedAt = nil,
		damageBy = {},
		eggs = {},
	}
end

function BossService.newState(now: number, rng: Rng?): State
	local rooms: { Room } = {}
	for room = 1, roomCount() do
		rooms[room] = newRoom(room)
	end
	return {
		phase = "day",
		phaseEndsAt = now + cycleConfig().DAY_SECONDS,
		cycle = 0,
		rooms = rooms,
		lockedUsers = {},
		lastAttackAt = {},
		carrying = {},
		holds = {},
		lostCarriers = {},
		rng = rng or fallbackRng(),
	}
end

-- ห้องบอสตามเลขห้อง (nil = เลขห้องแปลก)
function BossService.getRoom(state: State, room: any): Room?
	if not BossService.isValidRoom(room) then
		return nil
	end
	return state.rooms[room]
end

-- ไข่ชุดใหม่ของบอสห้องนี้ — **สุ่มน้ำหนักทันที** ด้วยตัวสุ่มเดิมของเกม (Config.rollMotherWeightForEgg)
-- ชนิดไข่ = ไข่รายด่านของห้องนั้น (Config.getBossEggId · egg_stageN) — ตารางคลาสไข่รายด่านเดิม ไม่มีตารางใหม่
local function spawnEggs(state: State, roomState: Room)
	local eggId = Config.getBossEggId(roomState.room)
	local eggs: { BossEgg } = {}
	for index = 1, cycleConfig().EGGS_PER_NIGHT do
		local weight = Config.rollMotherWeightForEgg(eggId, state.rng)
		assert(weight, `BossService: สุ่มน้ำหนักไข่ "{eggId}" ไม่ได้ (validate() ควรกันไว้แล้ว)`)
		eggs[index] = { room = roomState.room, index = index, eggId = eggId, weight = weight, status = "resting", carrier = nil }
	end
	roomState.eggs = eggs
end

-- บอสทุกห้องเกิด (ต้นกลางคืน) — ตัวเก่ายังไม่ตาย = ฟื้น HP เต็ม · บันทึกดาเมจเริ่มใหม่ · ไข่ชุดใหม่ทุกห้อง
-- ⚠️ ไข่ที่มีคนถืออยู่หายหมด (คนถือถูกจดใน lostCarriers ให้ runtime แจ้ง) · การกดค้างที่ค้างอยู่ถูกล้าง
-- ⚠️ ไม่ล้าง lockedUsers — ปลดล็อกได้ทางเดียวคือฆ่าบอสห้องนั้น
local function spawnAllBosses(state: State, at: number)
	local lost: { number } = {}
	for userId in state.carrying do
		table.insert(lost, userId)
	end
	table.sort(lost)
	state.lostCarriers = lost
	table.clear(state.carrying)
	table.clear(state.holds)

	for _, roomState in state.rooms do
		roomState.bossAlive = true
		roomState.bossMaxHp = Config.getBossHp(roomState.room)
		roomState.bossHp = roomState.bossMaxHp
		roomState.bossSpawnedAt = at
		roomState.bossDiedAt = nil
		roomState.damageBy = {}
		spawnEggs(state, roomState)
	end
end

local function enterNight(state: State, at: number)
	state.phase = "night"
	state.phaseEndsAt = at + cycleConfig().NIGHT_SECONDS
	state.cycle += 1
	spawnAllBosses(state, at)
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

-- ทำดาเมจใส่บอสห้องนั้น · คืน (ดาเมจที่เข้าจริง, ครั้งนี้ฆ่าได้ไหม)
-- ⚠️ ตีได้เฉพาะกลางวันที่บอสห้องนั้นยังมีชีวิต (กลางคืนมีกำแพงกั้นอยู่แล้ว แต่ server เช็คเองอีกชั้น)
-- ⚠️ ดาเมจเกิน HP ที่เหลือ = นับแค่ที่เข้าจริง (บันทึกผู้ทำดาเมจรวมกันได้ไม่เกิน HP เต็ม)
-- ⚠️ ไม่ตรวจสิทธิ์/ระยะ — ผู้เรียก (tryAttack) ตรวจก่อนแล้ว · คำสั่ง debug เรียกตรงได้
-- บอสห้องนี้ตาย = ปลดล็อกอัญเชิญ **เฉพาะคนที่ติดล็อกเพราะห้องนี้** (5B-2 · ห้องอื่นไม่เกี่ยว)
function BossService.applyDamage(state: State, room: number, userId: number, amount: number, now: number): (number, boolean)
	local roomState = BossService.getRoom(state, room)
	if roomState == nil or state.phase ~= "day" or not roomState.bossAlive or amount <= 0 then
		return 0, false
	end
	local dealt = math.min(amount, roomState.bossHp)
	roomState.bossHp -= dealt
	roomState.damageBy[userId] = (roomState.damageBy[userId] or 0) + dealt
	if roomState.bossHp <= 0 then
		roomState.bossHp = 0
		roomState.bossAlive = false
		roomState.bossDiedAt = now
		for lockedUserId, lockedRoom in state.lockedUsers do
			if lockedRoom == room then
				state.lockedUsers[lockedUserId] = nil
			end
		end
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
-- room = ห้องที่ยืนอยู่ (Config.getStageRoomAt จากตำแหน่งที่ server เห็น · nil = ไม่อยู่ห้องไหน)
-- wallProgress = ความคืบหน้าของคนตี (PlayerData) — ⚠️ 5B-2 ตรวจสิทธิ์จากตัวนี้ ไม่ใช่แค่ตำแหน่ง
-- ผล: "ok" · "night" (ยังไม่เช้า) · "noroom" (ไม่อยู่ห้องบอส) · "noaccess" (ยังพังกำแพงไม่ถึงห้องนี้)
--     · "dead" (บอสห้องนี้ตายแล้ว) · "cooldown" (ฟันถี่เกิน) · "range" (อยู่ไกลเกิน)
-- ⚠️ server ตัดสินทั้งหมด — distance วัดจากตำแหน่งตัวละครที่ server เห็นถึงบอสห้องนั้น ไม่รับค่าจาก client
function BossService.tryAttack(
	state: State,
	userId: number,
	now: number,
	room: number?,
	distance: number,
	weaponLevel: number,
	wallProgress: number?
): (string, number, boolean)
	if state.phase ~= "day" then
		return "night", 0, false
	end
	local roomState = BossService.getRoom(state, room)
	if roomState == nil then
		return "noroom", 0, false
	end
	if not Config.canAccessBossRoom(wallProgress, roomState.room) then
		return "noaccess", 0, false
	end
	if not roomState.bossAlive then
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
	local dealt, killed = BossService.applyDamage(state, roomState.room, userId, Config.getWeaponDamage(weaponLevel), now)
	return "ok", dealt, killed
end

-- ล็อกอัญเชิญเพราะบอสห้องนี้ — ได้เฉพาะตอนบอสห้องนั้นยังมีชีวิต (ตายแล้วพังกำแพงได้ตามปกติ) · คืน true ถ้าติดล็อก
-- ติดล็อกอยู่แล้ว (ห้องเดิม/ห้องอื่น) = คงห้องเดิมไว้ (ปกติไม่เกิด — ติดล็อกแล้วทหารหยุด พังกำแพงต่อไม่ได้)
function BossService.lockUser(state: State, userId: number, room: number): boolean
	local roomState = BossService.getRoom(state, room)
	if roomState == nil or not roomState.bossAlive then
		return false
	end
	if state.lockedUsers[userId] == nil then
		state.lockedUsers[userId] = room
	end
	return true
end

function BossService.isUserLocked(state: State, userId: number): boolean
	return state.lockedUsers[userId] ~= nil
end

-- ห้องที่ทำให้คนนี้ติดล็อก (nil = ไม่ติด)
function BossService.getLockedRoom(state: State, userId: number): number?
	return state.lockedUsers[userId]
end

export type Contribution = { userId: number, damage: number }

-- ผู้ทำดาเมจบอสห้องนี้ตัวนี้ เรียงมาก → น้อย (เท่ากัน = userId น้อยก่อน ให้ผลคงที่) — ใช้แบ่งเงิน
function BossService.getContributors(state: State, room: number): { Contribution }
	local list: { Contribution } = {}
	local roomState = BossService.getRoom(state, room)
	if roomState == nil then
		return list
	end
	for userId, damage in roomState.damageBy do
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

-- บอสห้องนี้ตีกลับ (ปิดไว้ใน config) — คืน userId ของทุกคนในระยะ · positions = { [userId] = ตำแหน่งตัวละคร }
function BossService.pickCounterTargets(state: State, room: number, positions: { [number]: Vector3 }): { number }
	local cfg = cycleConfig()
	local targets: { number } = {}
	local roomState = BossService.getRoom(state, room)
	if not cfg.BOSS_ATTACK_ENABLED or state.phase ~= "day" or roomState == nil or not roomState.bossAlive then
		return targets
	end
	local bossPosition = Config.getBossCornerCenter(room)
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

-- 5B-2: เวลากดค้างขั้นต่ำที่ server ยอมรับ (เผื่อ network jitter ตาม EGG_PICKUP_HOLD_TOLERANCE)
function BossService.getRequiredHoldSeconds(): number
	local cfg = cycleConfig()
	return cfg.EGG_PICKUP_HOLD_SECONDS - cfg.EGG_PICKUP_HOLD_TOLERANCE
end

-- 5B-2: เริ่มกดค้างที่ไข่ (index) ในห้องที่ยืนอยู่ (room) — server จดเวลาของตัวเอง · คืน true ถ้าจดแล้ว
-- ⚠️ ต้องยืนใกล้ไข่ฟองนั้นตั้งแต่ตอนเริ่ม (กัน "เริ่มจากไกล ๆ แล้วเดินเข้ามาหยิบทันที")
-- ค่าแปลก / ไม่อยู่ห้องไหน / ไกลเกิน = ไม่จด (ไม่ล้างของเดิมด้วย)
function BossService.beginHold(state: State, userId: number, room: any, index: any, distance: number, now: number): boolean
	if not BossService.isValidRoom(room) or not isValidEggIndex(index) then
		return false
	end
	if distance > Config.MapDimensions.BossArena.EggPickupRange then
		return false
	end
	state.holds[userId] = { room = room, index = index, beganAt = now }
	return true
end

-- 5B-2: ปล่อยปุ่ม — ปล่อย**ก่อนครบ**เวลา = ล้างจังหวะเริ่ม (ต้องเริ่มกดใหม่) · ครบแล้วค่อยปล่อย = เก็บไว้ให้คำขอหยิบใช้
-- (ลำดับ HoldEnded/Triggered ฝั่ง client ไม่แน่นอน — ปล่อยตอนครบแล้วต้องไม่ทำให้การหยิบที่ตามมาถูกปฏิเสธ)
function BossService.endHold(state: State, userId: number, now: number)
	local hold = state.holds[userId]
	if hold and now - hold.beganAt < BossService.getRequiredHoldSeconds() then
		state.holds[userId] = nil
	end
end

-- 5B-2: กดค้างที่ไข่ (room, index) นี้ครบเวลาแล้วไหม (วัดด้วยเวลา server ทั้งสองจังหวะ)
function BossService.hasFullHold(state: State, userId: number, room: number, index: number, now: number): boolean
	local hold = state.holds[userId]
	return hold ~= nil
		and hold.room == room
		and hold.index == index
		and now - hold.beganAt >= BossService.getRequiredHoldSeconds()
end

-- หยิบไข่ฟองที่ index ของห้องที่ยืนอยู่ · คืน (ผล, ไข่ที่หยิบได้)
-- room = ห้องที่ยืนอยู่ (Config.getStageRoomAt · nil = ไม่อยู่ห้องไหน) · distance = ระยะถึงจุดไข่ฟองนั้นในห้องนั้น
-- ผล: "ok" · "invalid" (index ไม่ใช่จำนวนเต็มในช่วง — ทิ้งเงียบ ๆ) · "range" (ไม่อยู่ห้องไหน/ไกลกว่า EggPickupRange)
--     · "access" (5B-2 ยังพังกำแพงไม่ถึงห้องนี้) · "alive" (บอสห้องนี้ยังไม่ตาย) · "carrying" (ถืออยู่แล้ว 1 ฟอง)
--     · "taken" (ฟองนั้นไม่อยู่แล้ว / ยังไม่มีไข่) · "hold" (5B-2 กดค้างไม่ครบ — ยิงคำขอตรง ๆ)
-- ⚠️ room / distance / wallProgress / now มาจาก server เท่านั้น (runtime วัดเอง) — ไม่รับจาก client
function BossService.pickUpEgg(
	state: State,
	userId: number,
	room: number?,
	index: any,
	distance: number,
	wallProgress: number?,
	now: number
): (string, BossEgg?)
	if not isValidEggIndex(index) then
		return "invalid", nil
	end
	local roomState = BossService.getRoom(state, room)
	if roomState == nil then
		return "range", nil
	end
	if not Config.canAccessBossRoom(wallProgress, roomState.room) then
		return "access", nil
	end
	if roomState.bossAlive then
		return "alive", nil
	end
	if state.carrying[userId] ~= nil then
		return "carrying", nil
	end
	local egg = roomState.eggs[index]
	if egg == nil or egg.status ~= "resting" then
		return "taken", nil
	end
	if distance > Config.MapDimensions.BossArena.EggPickupRange then
		return "range", nil
	end
	if not BossService.hasFullHold(state, userId, roomState.room, index, now) then
		return "hold", nil
	end
	state.holds[userId] = nil -- ใช้จังหวะกดค้างนี้ไปแล้ว — หยิบฟองถัดไปต้องกดค้างใหม่
	egg.status = "carried"
	egg.carrier = userId
	state.carrying[userId] = { room = roomState.room, index = index }
	return "ok", egg
end

-- 5B-fix (ผู้ใช้สั่ง): ต้นกลางคืนวาปมาหน้าป้อม**เฉพาะคนที่อยู่ในสนามรบ** (นอกเซฟโซน) — คนในคอก/ลานอยู่ที่เดิม
-- ⚠️ position = ตำแหน่งตัวละครที่ server เห็น
function BossService.shouldGatherAtNight(position: Vector3): boolean
	return not Config.isInSafeZone(position)
end

-- ไข่ที่คนนี้ถืออยู่ (nil = ไม่ได้ถือ)
function BossService.getCarriedEgg(state: State, userId: number): BossEgg?
	local ref = state.carrying[userId]
	if ref == nil then
		return nil
	end
	local roomState = state.rooms[ref.room]
	return if roomState then roomState.eggs[ref.index] else nil
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

export type HeavyAlert = { room: number, weight: number }

-- 5B-2: ไข่ที่หนักที่สุดของ**แต่ละห้อง** ที่เกิน HEAVY_EGG_ALERT_KG (มากกว่า ไม่ใช่เท่ากับ) เรียงตามห้อง
-- ว่าง = คืนนี้ไม่มีห้องไหนเกิน (ไม่ประกาศ) · runtime ส่งรายการนี้ก้อนเดียว → ข้อความเดียวรวมทุกห้อง
function BossService.getHeavyEggAlerts(state: State): { HeavyAlert }
	local threshold = cycleConfig().HEAVY_EGG_ALERT_KG
	local alerts: { HeavyAlert } = {}
	for _, roomState in state.rooms do
		local heaviest: number? = nil
		for _, egg in roomState.eggs do
			if heaviest == nil or egg.weight > heaviest then
				heaviest = egg.weight
			end
		end
		if heaviest and heaviest > threshold then
			table.insert(alerts, { room = roomState.room, weight = heaviest })
		end
	end
	return alerts
end

-- คนที่ได้ส่วนแบ่งเงินบอสห้องนี้: ทำดาเมจ ≥ Economy.BOSS_REWARD_MIN_DAMAGE **และ** isPresent(userId) = ยังอยู่ในห้องนี้ตอนบอสตาย
-- (runtime ส่ง isPresent ที่เช็คตำแหน่งตัวละครจริง — ออกเกมแล้ว/อยู่นอกห้อง = false) · เรียงตาม userId ให้ผลคงที่
function BossService.getRewardRecipients(state: State, room: number, isPresent: (userId: number) -> boolean): { number }
	local minDamage = Config.Balance.Economy.BOSS_REWARD_MIN_DAMAGE
	local recipients: { number } = {}
	local roomState = BossService.getRoom(state, room)
	if roomState == nil then
		return recipients
	end
	for userId, damage in roomState.damageBy do
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

-- แผนจ่ายเงินบอสห้องนี้: (ส่วนแบ่งต่อคน, รายชื่อคนได้, เงินก้อนของห้อง) — ก้อน = Config.getBossKillReward(ห้อง)
function BossService.planReward(state: State, room: number, isPresent: (userId: number) -> boolean): (number, { number }, number)
	local total = if BossService.isValidRoom(room) then Config.getBossKillReward(room) else 0
	local recipients = BossService.getRewardRecipients(state, room, isPresent)
	return BossService.splitReward(total, #recipients), recipients, total
end

-- ข้อความสรุปห้องเดียว (คำสั่ง debug)
function BossService.describeRoom(state: State, room: number): string
	local roomState = BossService.getRoom(state, room)
	if roomState == nil then
		return `ไม่มีห้อง {tostring(room)}`
	end
	local bossText = if roomState.bossAlive
		then `บอส HP {Config.formatCoins(roomState.bossHp)}/{Config.formatCoins(roomState.bossMaxHp)}`
		else "ไม่มีบอส"
	local parts: { string } = {}
	for _, entry in BossService.getContributors(state, room) do
		table.insert(parts, `{entry.userId}={entry.damage}`)
	end
	local eggParts: { string } = {}
	for _, egg in roomState.eggs do
		local tag = if egg.status == "carried" then `ถือ:{egg.carrier}` elseif egg.status == "gone" then "เก็บแล้ว" else "วาง"
		table.insert(eggParts, `#{egg.index} {Config.formatCoins(egg.weight)}กก.({tag})`)
	end
	return `ห้อง {room}: {bossText} · ผู้ทำดาเมจ: {if #parts > 0 then table.concat(parts, ", ") else "-"}`
		.. ` · ไข่ {Config.getBossEggId(room)}: {if #eggParts > 0 then table.concat(eggParts, " ") else "-"}`
end

-- หัวข้อสรุป (phase · เวลา · จำนวนห้องที่บอสยังอยู่ · ล็อก) — log ของลูปจริง
function BossService.describeHeader(state: State, now: number): string
	local phaseText = if state.phase == "night" then "กลางคืน" else "กลางวัน"
	local alive = 0
	for _, roomState in state.rooms do
		if roomState.bossAlive then
			alive += 1
		end
	end
	local lockedParts: { string } = {}
	for userId, room in state.lockedUsers do
		table.insert(lockedParts, `{userId}→ห้อง {room}`)
	end
	table.sort(lockedParts)
	return `{phaseText} (คืนที่ {state.cycle}) · เหลือ {math.ceil(BossService.getRemaining(state, now))} วิ`
		.. ` · บอสยังอยู่ {alive}/{#state.rooms} ห้อง`
		.. ` · ล็อกอัญเชิญ: {if #lockedParts > 0 then table.concat(lockedParts, ", ") else "-"}`
end

-- ข้อความสรุปทุกห้อง (คำสั่ง debug) — บรรทัดแรก = หัวข้อ · บรรทัดละห้อง
function BossService.describe(state: State, now: number): string
	local lines = { BossService.describeHeader(state, now) }
	for room = 1, #state.rooms do
		table.insert(lines, BossService.describeRoom(state, room))
	end
	return table.concat(lines, "\n")
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
local onBossKilled: (room: number) -> () = function(_room) end
local refreshWorld: () -> () = function() end
local onUserLocked: (userId: number, room: number) -> () = function(_userId, _room) end

-- ⚠️ ก่อน start() ยังไม่มีบอส → ไม่มีใครถูกล็อก (เทสต์ของ CombatService/EggService ไม่ต้องรู้จักไฟล์นี้)
function BossService.isLocked(userId: number): boolean
	return current ~= nil and BossService.isUserLocked(current, userId)
end

-- 5B-2: บอสห้องนี้ยังมีชีวิตไหม (ก่อน start = ไม่มีบอสทุกห้อง)
function BossService.isBossAlive(room: number): boolean
	if current == nil then
		return false
	end
	local roomState = BossService.getRoom(current, room)
	return roomState ~= nil and roomState.bossAlive
end

-- ล็อกผู้เล่นคนนี้เพราะบอสห้อง room (CombatService.start เรียกหลัง tick) + แจ้งเขาคนเดียวว่าทำไมทหารหยุด
function BossService.lock(userId: number, room: number): boolean
	if current == nil then
		return false
	end
	local wasLocked = BossService.isUserLocked(current, userId)
	local locked = BossService.lockUser(current, userId, room)
	if locked and not wasLocked then
		onUserLocked(userId, room)
	end
	return locked
end

export type Gate = {
	isBossAlive: (room: number) -> boolean,
	isUserLocked: (userId: number) -> boolean,
	lockUser: (userId: number, room: number) -> boolean,
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
	access = "pickupAccess", -- 5B-2
	hold = "pickupHold", -- 5B-2
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
	local holdRequest = Remotes.waitFor(Config.RemoteNames.BOSS_EGG_HOLD_REQUEST)

	-- ของในโลก — MapBuilder.buildBossArena สร้างไว้แล้ว (Main เรียก MapBuilder.build ก่อน start)
	-- 5B-2: บอส 1 ตัวต่อห้อง (CycleBoss{ห้อง}) · ไข่ 6 ฟองต่อห้อง (BossEgg{ห้อง}_{i}) ในโฟลเดอร์เดียว
	local arena = Workspace:WaitForChild("Map"):WaitForChild(Config.BOSS_ARENA_NAME)
	local barrier = arena:WaitForChild(Config.BOSS_BARRIER_NAME) :: BasePart
	local eggFolder = arena:WaitForChild(Config.BOSS_EGG_FOLDER)
	type BossVisual = { model: Model, hpFill: Frame?, hpText: TextLabel? }
	local bosses: { BossVisual } = {}
	local eggParts: { { BasePart } } = {}
	for room = 1, #state.rooms do
		local model = arena:WaitForChild(Config.getBossModelName(room)) :: Model
		bosses[room] = {
			model = model,
			hpFill = model:FindFirstChild("HpFill", true) :: Frame?,
			hpText = model:FindFirstChild("HpText", true) :: TextLabel?,
		}
		eggParts[room] = {}
		for index = 1, cycleConfig().EGGS_PER_NIGHT do
			eggParts[room][index] = eggFolder:WaitForChild(Config.getBossEggPartName(room, index)) :: BasePart
		end
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

	local function wallProgressOf(player: Player): number?
		local data = DataService.getCached(player.UserId)
		return if data then data.wallProgress else nil
	end

	-- ไข่ในห้อง: ขนาดตามน้ำหนัก · โชว์เฉพาะฟองที่วางอยู่ · Attribute ให้ client ติด/เปิดจุดกด E
	-- ⚠️ 5B-fix (ผู้ใช้สั่ง "ให้ผู้เล่นลุ้น"): **ไม่มีป้ายน้ำหนัก และไม่ส่งน้ำหนักให้ client** (ไม่มี Attribute Weight) —
	--   เห็นแค่ขนาดไข่ · น้ำหนักจริงเฉลยตอนเก็บเข้ากระเป๋า ("delivered") · ประกาศไข่หนักต้นคืนยังอยู่ (บอกแค่ฟองหนักสุดของห้อง)
	local function publishEggs()
		for room, parts in eggParts do
			local roomState = state.rooms[room]
			for index, part in parts do
				local egg = roomState.eggs[index]
				local resting = egg ~= nil and egg.status == "resting"
				if egg then
					local size = Config.getEggVisualSize(egg.weight)
					local spot = Config.getBossEggSpot(room, index)
					part.Size = size
					part.Position = Vector3.new(spot.X, Config.getBallRadius(size), spot.Z)
				end
				part.Transparency = if resting then 0 else 1
				part:SetAttribute("Status", if egg then egg.status else "none")
			end
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
		part.Color = eggParts[egg.room][egg.index].Color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = root.CFrame * CFrame.new(0, CARRY_ABOVE_ROOT + Config.getBallRadius(size), 0)
		part:SetAttribute("Room", egg.room)
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
				and existing:GetAttribute("Room") == egg.room
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

	-- บอสห้องเดียว: Attribute ต่อห้อง + ใส่/ถอดตัวบอส + แถบ HP — ตีโดนแต่ไม่ตายเรียกแค่ตัวนี้ (ไม่ต้องไล่ทั้ง 9 ห้อง + 54 ฟอง)
	local function publishBoss(room: number)
		local roomState = state.rooms[room]
		local visual = bosses[room]
		stateFolder:SetAttribute(Config.getBossStateAttribute("BossAlive", room), roomState.bossAlive)
		stateFolder:SetAttribute(Config.getBossStateAttribute("BossHp", room), roomState.bossHp)
		stateFolder:SetAttribute(Config.getBossStateAttribute("BossMaxHp", room), roomState.bossMaxHp)
		visual.model.Parent = if roomState.bossAlive then arena else nil
		if visual.hpFill then
			visual.hpFill.Size = UDim2.fromScale(if roomState.bossMaxHp > 0 then roomState.bossHp / roomState.bossMaxHp else 0, 1)
		end
		if visual.hpText then
			visual.hpText.Text =
				`บอสห้อง {room}  {Config.formatCoins(roomState.bossHp)} / {Config.formatCoins(roomState.bossMaxHp)}`
		end
	end

	local function publish()
		stateFolder:SetAttribute("Phase", state.phase)
		stateFolder:SetAttribute("PhaseEndsAt", state.phaseEndsAt)
		stateFolder:SetAttribute("Cycle", state.cycle)

		-- กำแพงกั้น: กลางคืนชนได้ + มองเห็น · กลางวันหายไป (ชิ้นเดิมอยู่ตลอด — client ติดตัวเลขนับถอยหลังไว้)
		local night = state.phase == "night"
		barrier.CanCollide = night
		barrier.CanQuery = night
		barrier.Transparency = if night then BARRIER_NIGHT_TRANSPARENCY else 1

		-- 5B-2: บอสทุกห้อง — ไม่มีชีวิต = ถอดออกจากโลก (client ไม่เห็น · ไม่ชน) · เกิด = ใส่กลับ · แถบ HP ของห้องนั้น
		for room in bosses do
			publishBoss(room)
		end

		-- 5B: ไข่ในห้อง + ไข่ที่ถือ
		publishEggs()
		syncCarriedVisuals()
	end

	-- ต้นกลางคืน: วาปคนที่อยู่ในสนามรบมาหน้าป้อม (คนที่เข้าเกม/เกิดใหม่ระหว่างคืนเกิดตามปกติ ไม่วาป)
	-- 5B: หน้าป้อม = ฝั่งลานกลาง หน้ากำแพงกั้นที่ปิดปากเลน (หันหน้า +X เข้าหาตัวเลข)
	-- ⚠️ 5B-fix: **เฉพาะคนที่อยู่ในสนามรบ** (shouldGatherAtNight) — คนในคอก/ลานกลางไม่ถูกวาป ·
	--   จุดยืนนับเฉพาะคนที่ถูกวาป (คนแรกได้จุด 1 · ไม่เว้นจุดให้คนที่อยู่ในลานอยู่แล้ว)
	-- ⚠️ 5B-2 (ผู้ใช้ยืนยัน): ยังวาปมาที่เดียว (ปากเลน) แม้บอสมีทุกห้อง — เช้าแต่ละคนวิ่งไปห้องตัวเอง
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
				-- ⚠️ 5B: ลำดับสำคัญ — ไข่ที่ถือหาย (ภาพ) **ก่อน** วาป · ไข่ชุดใหม่ขึ้นทุกห้องพร้อมบอส
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
				-- 5B-2: ประกาศไข่หนัก (ทั้งเซิร์ฟ) **ข้อความเดียวรวมทุกห้อง** ที่มีไข่เกิน HEAVY_EGG_ALERT_KG · ไม่มี = ไม่ประกาศ
				local heavy = BossService.getHeavyEggAlerts(state)
				if #heavy > 0 then
					notify:FireAllClients("heavy", heavy)
				end
			end
		end
		publish()
		print(`[BossService] {table.concat(events, " → ")} · {BossService.describeHeader(state, serverNow())}`)
	end

	refreshWorld = publish

	onUserLocked = function(userId: number, room: number)
		local player = Players:GetPlayerByUserId(userId)
		if player then
			notify:FireClient(player, "locked", room)
		end
	end

	-- 5B: เงินก้อนเดียวของห้องนั้น แบ่งเท่ากัน (ปัดลง) ให้คนที่ทำดาเมจบอสห้องนั้น + ยังอยู่ในห้องนั้นตอนบอสตาย
	-- หลุดออก/อยู่นอกห้อง = ไม่ได้ · 5B-2: ก้อน = Config.getBossKillReward(ห้อง)
	local function payBossReward(room: number)
		local share, recipients, total = BossService.planReward(state, room, function(userId: number): boolean
			local player = Players:GetPlayerByUserId(userId)
			local root = player and aliveRoot(player)
			return root ~= nil and Config.isInStageRoom(room, root.Position)
		end)
		local paid: { string } = {}
		for _, userId in recipients do
			local player = Players:GetPlayerByUserId(userId)
			local data = DataService.getCached(userId)
			if player and data and share > 0 then
				data.currency.coins += share
				syncPlayer(player)
				notify:FireClient(player, "reward", share, #recipients, room)
				table.insert(paid, player.Name)
			end
		end
		print(
			`[BossService] เงินบอสห้อง {room} {total} แบ่ง {#recipients} คน คนละ {share}`
				.. ` · ได้จริง: {if #paid > 0 then table.concat(paid, ", ") else "-"}`
		)
	end

	onBossKilled = function(room: number)
		publish()
		notify:FireAllClients("killed", room)
		payBossReward(room)
		print(`[BossService] กำจัดบอสห้อง {room} แล้ว · {BossService.describeRoom(state, room)}`)
	end

	-- 5B-2: ห้องไหน = ห้องที่ยืนอยู่ (ตำแหน่งที่ server เห็น) · สิทธิ์ = wallProgress (tryAttack ตรวจ)
	local function onAttack(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local data = DataService.getCached(player.UserId)
		if not humanoid or not root or humanoid.Health <= 0 or not data then
			return
		end
		local room = Config.getStageRoomAt(root.Position)
		-- 5B: บอสยืนมุมห้อง — วัดระยะจากตัวบอสจริงของห้องนั้น (Config.getBossCornerCenter) ไม่ใช่กึ่งกลางห้อง
		local distance = if room
			then BossService.horizontalDistance(root.Position, Config.getBossCornerCenter(room))
			else math.huge
		local result, _, killed = BossService.tryAttack(
			state,
			player.UserId,
			serverNow(),
			room,
			distance,
			data.weaponLevel or 1,
			data.wallProgress
		)
		if result ~= "ok" or room == nil then
			return
		end
		if killed then
			onBossKilled(room)
		else
			publishBoss(room)
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

	-- ระยะจากตัวละครถึงจุดไข่ฟองนั้นในห้องที่ยืนอยู่ (index แปลก / ไม่อยู่ห้องไหน = ไกลสุด)
	local function eggDistance(root: BasePart, room: number?, rawIndex: unknown): number
		if room and type(rawIndex) == "number" and rawIndex % 1 == 0 and rawIndex >= 1 and rawIndex <= cycleConfig().EGGS_PER_NIGHT then
			return BossService.horizontalDistance(root.Position, Config.getBossEggSpot(room, rawIndex))
		end
		return math.huge
	end

	-- ══ 5B-2: จับเวลากดค้าง ══ client บอกจังหวะ "เริ่มกด/ปล่อย" (prompt เป็นของ client) · server จดเวลาของตัวเอง
	-- ห้อง = ห้องที่ยืนอยู่ตอนเริ่มกด · ต้องอยู่ใกล้ไข่ฟองนั้นตั้งแต่ตอนเริ่ม · ค่าแปลก = ทิ้งเงียบ ๆ
	holdRequest.OnServerEvent:Connect(function(player: Player, rawIndex: unknown, rawHolding: unknown)
		if type(rawHolding) ~= "boolean" then
			return
		end
		local userId = player.UserId
		if not rawHolding then
			BossService.endHold(state, userId, serverNow())
			return
		end
		local root = aliveRoot(player)
		if not root then
			return
		end
		local room = Config.getStageRoomAt(root.Position)
		BossService.beginHold(state, userId, room, rawIndex, eggDistance(root, room, rawIndex), serverNow())
	end)

	-- ══ 5B: หยิบไข่ ══ client ส่งแค่ index ของฟองที่กด E · server ตัดสินทุกอย่างเอง
	-- 5B-2: ห้อง = ห้องที่ยืนอยู่ (ตำแหน่งที่ server เห็น) · สิทธิ์ = wallProgress · ต้องกดค้างครบ (เวลา server)
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
		local room = Config.getStageRoomAt(root.Position)
		local result, egg = BossService.pickUpEgg(
			state,
			userId,
			room,
			rawIndex,
			eggDistance(root, room, rawIndex),
			wallProgressOf(player),
			serverNow()
		)
		if result == "ok" and egg then
			bagFullWarned[userId] = nil
			publish()
			-- 5B-fix: ไม่บอกน้ำหนักตอนหยิบ (ให้ลุ้น) — เฉลยตอนเข้ากระเป๋า ("delivered")
			notify:FireClient(player, "picked")
			print(`[BossService] {player.Name} หยิบไข่ห้อง {egg.room} #{egg.index} ({egg.eggId} · {egg.weight} กก.)`)
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
			print(`[BossService] ไข่ห้อง {egg.room} #{egg.index} กลับจุดเดิม ({reason} · userId {userId})`)
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
					print(`[BossService] {player.Name} เก็บไข่ห้อง {egg.room} #{egg.index} ({egg.eggId} · {egg.weight} กก.) เข้ากระเป๋าแล้ว`)
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
		state.holds[player.UserId] = nil
		lastPickupAt[player.UserId] = nil
		-- 5B: ออกเกมระหว่างถือไข่ → ไข่กลับจุดเดิม หยิบใหม่ได้
		dropEgg(player.UserId, "ออกเกม")
	end)

	-- ถือ/เก็บอาวุธอัตโนมัติ: กลางวัน + ยืนในห้องที่มีสิทธิ์ + บอสห้องนั้นยังอยู่ = ถือ · นอกนั้นเก็บ (5B-2)
	local function updateWeapons()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and humanoid and root and humanoid.Health > 0 then
				local room = Config.getStageRoomAt(root.Position)
				local roomState = BossService.getRoom(state, room)
				local shouldHold = state.phase == "day"
					and roomState ~= nil
					and roomState.bossAlive
					and Config.canAccessBossRoom(wallProgressOf(player), roomState.room)
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

	-- บอสตีกลับ (BOSS_ATTACK_ENABLED = false ตอนนี้ — pickCounterTargets คืนว่างเสมอ) · ทุกห้องที่บอสยังอยู่
	local nextCounterAt = 0
	local function counterAttack(now: number)
		if now < nextCounterAt then
			return
		end
		nextCounterAt = now + cycleConfig().BOSS_ATTACK_INTERVAL
		if not cycleConfig().BOSS_ATTACK_ENABLED then
			return
		end
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
		for room = 1, #state.rooms do
			for _, userId in BossService.pickCounterTargets(state, room, positions) do
				humanoids[userId]:TakeDamage(cycleConfig().BOSS_ATTACK_DAMAGE)
			end
		end
	end

	publish()
	print(`[BossService] เริ่มวงจรกลางวัน/กลางคืน · บอส {#state.rooms} ห้อง · {BossService.describeHeader(state, serverNow())}`)

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
-- ⚠️ ใช้ทางเดียวกับลูปจริง (applyEvents / applyDamage / onBossKilled) — ข้ามแค่ระยะ/คูลดาวน์/สิทธิ์เข้าห้อง
--   (ไว้ทดสอบห้องไกล ๆ โดยไม่ต้องพังกำแพงจริง) · กติกา กลางวัน + บอสยังอยู่ ยังบังคับเหมือนตีจริง
-- 5B-2: ทุกคำสั่งที่เกี่ยวกับห้องรับเลขห้อง (ไม่ใส่ = ห้อง 1 เหมือนเดิม)

local function requireState(): State
	assert(current, "BossService ยังไม่ start (ต้องรันในเกมที่กด Play แล้ว)")
	return current :: State
end

-- เลขห้องจากคำสั่ง debug (ไม่ใส่ = ห้อง 1) · คืน (ห้อง, ข้อความผิดพลาด)
local function parseDebugRoom(rawRoom: any): (number?, string?)
	if rawRoom == nil then
		return 1, nil
	end
	local room = tonumber(rawRoom)
	if room == nil or not BossService.isValidRoom(room) then
		return nil, `เลขห้องต้องเป็นจำนวนเต็ม 1–{roomCount()} (ได้ {tostring(rawRoom)})`
	end
	return room, nil
end

-- ข้ามไปต้นกลางคืนทันที: วาปคนในสนามรบมาหน้าป้อม · กำแพงกั้นขึ้น · **บอสทุกห้อง**เกิด/ฟื้น HP เต็ม · นับ 59 → 0 ใหม่ · ไข่ชุดใหม่ทุกห้อง
-- 5B: rawFirstEggKg (ไม่ใส่ได้) = บังคับน้ำหนักไข่ฟองที่ 1 ของห้อง rawRoom (5B-2 · ไม่ใส่ห้อง = ห้อง 1)
--   (kg จำนวนเต็ม ≥ 100) **ก่อน** ประกาศ/โชว์ — ใช้ทดสอบประกาศไข่หนักรวมหลายห้องโดยไม่ต้องรอดวง
--   เช่น debugBossNight(152300, 7) → "คืนนี้: ห้อง 7 ไข่ 152,300 กก." · ไม่ใส่ = สุ่มตามปกติทุกฟอง
function BossService.debugBossNight(rawFirstEggKg: number?, rawRoom: number?): string
	local state = requireState()
	local room, roomError = parseDebugRoom(rawRoom)
	if roomError then
		return roomError
	end
	local events = BossService.forcePhase(state, "night", serverNow())
	local forced = tonumber(rawFirstEggKg)
	local roomState = BossService.getRoom(state, room)
	if forced and roomState and roomState.eggs[1] then
		roomState.eggs[1].weight = math.max(100, math.floor(forced))
	end
	applyEvents(events)
	return BossService.describe(state, serverNow())
end

-- 5B: สถานะไข่บอส (น้ำหนัก · วาง/ถือ/เก็บแล้ว · ใครถือ) · 5B-2: ใส่ห้อง = ห้องเดียว · ไม่ใส่ = ทุกห้อง
function BossService.debugBossEggs(rawRoom: number?): string
	local state = requireState()
	local rooms: { number } = {}
	if rawRoom == nil then
		for room = 1, #state.rooms do
			table.insert(rooms, room)
		end
	else
		local room, roomError = parseDebugRoom(rawRoom)
		if roomError or room == nil then
			return roomError or "เลขห้องไม่ถูกต้อง"
		end
		table.insert(rooms, room)
	end
	local lines: { string } = {}
	for _, room in rooms do
		local roomState = state.rooms[room]
		local phase = if roomState.bossAlive then "บอสยังอยู่ — ยังหยิบไม่ได้" else "บอสไม่อยู่ — หยิบได้ (ถ้าไข่ยังวางอยู่)"
		table.insert(lines, `ห้อง {room} ({Config.getBossEggId(room)}) · {phase}`)
		if #roomState.eggs == 0 then
			table.insert(lines, "  ยังไม่มีไข่ (รอคืนแรก — debugBossNight)")
		end
		for _, egg in roomState.eggs do
			table.insert(
				lines,
				`  #{egg.index} {Config.formatCoins(egg.weight)} กก. · {egg.status}{if egg.carrier then ` (userId {egg.carrier})` else ""}`
			)
		end
	end
	return table.concat(lines, "\n")
end

-- ข้ามไปต้นกลางวันทันที: กำแพงกั้นหาย เข้าไปตีบอสได้ (บอสต้องเกิดก่อน — ใช้ debugBossNight ก่อนถ้ายังไม่มี)
function BossService.debugBossDay(): string
	local state = requireState()
	applyEvents(BossService.forcePhase(state, "day", serverNow()))
	return BossService.describe(state, serverNow())
end

-- ทำดาเมจใส่บอสห้อง rawRoom (ไม่ใส่ = ห้อง 1) ในนามผู้เล่นคนนั้น (นับเข้าบันทึกผู้ทำดาเมจเหมือนตีจริง)
-- กติกาเดิม: กลางวัน + บอสห้องนั้นยังอยู่ · ⚠️ ข้ามสิทธิ์เข้าห้อง/ระยะ (คำสั่งทดสอบ)
function BossService.debugDamageBoss(player: Player, rawAmount: number, rawRoom: number?): string
	local state = requireState()
	local amount = tonumber(rawAmount)
	if not amount or amount <= 0 then
		return "ใส่จำนวนดาเมจเป็นตัวเลขมากกว่า 0 เช่น debugDamageBoss(player, 300) หรือ debugDamageBoss(player, 300, 3)"
	end
	local room, roomError = parseDebugRoom(rawRoom)
	if roomError or room == nil then
		return roomError or "เลขห้องไม่ถูกต้อง"
	end
	if state.phase ~= "day" then
		return "ตีไม่ได้ตอนกลางคืน — ใช้ debugBossDay ก่อน"
	end
	if not state.rooms[room].bossAlive then
		return `ไม่มีบอสห้อง {room} ให้ตี — ใช้ debugBossNight ก่อน (แล้ว debugBossDay)`
	end
	local dealt, killed = BossService.applyDamage(state, room, player.UserId, amount, serverNow())
	if killed then
		onBossKilled(room)
	else
		refreshWorld()
	end
	return `ห้อง {room}: ดาเมจเข้า {dealt}{if killed then " — บอสตาย" else ""} · {BossService.describeRoom(state, room)}`
end

-- ฆ่าบอสห้อง rawRoom (ไม่ใส่ = ห้อง 1) ในนามผู้เล่นคนนั้น (ดาเมจเท่า HP ที่เหลือ) — ปลดล็อกคนที่ติดเพราะห้องนั้น
function BossService.debugKillBoss(player: Player, rawRoom: number?): string
	local state = requireState()
	local room, roomError = parseDebugRoom(rawRoom)
	if roomError or room == nil then
		return roomError or "เลขห้องไม่ถูกต้อง"
	end
	return BossService.debugDamageBoss(player, math.max(1, state.rooms[room].bossHp), room)
end

-- สถานะทุกห้อง (บรรทัดแรก = phase/เวลา/ล็อก · บรรทัดละห้อง)
function BossService.debugBossStatus(): string
	local state = requireState()
	return BossService.describe(state, serverNow())
end

return BossService
