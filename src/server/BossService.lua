--!strict
-- egg-army-game :: วงจรกลางวัน/กลางคืน + บอสตัวเดียวของเซิร์ฟเวอร์ (Phase 5A)
--
-- ══ กติกา (ผู้ใช้ยืนยันแล้ว) ══
--   รอบละ DAY + NIGHT วินาที (Config.Balance.BossCycle · 9 + 1 นาที) วนตลอด · เซิร์ฟเปิดใหม่เริ่มต้นกลางวันเสมอ
--   กลางคืน: วาปทุกคนมาหน้าป้อม · กำแพงกั้นขึ้น (กันเฉพาะผู้เล่น) · บอสเกิด — ตัวเก่ายังไม่ตาย = ฟื้น HP เต็ม
--   กลางวัน: กำแพงกั้นหาย เข้าไปตีบอสได้ทั้งวัน · บอสตายแล้วหายไปจนคืนถัดไป
--   ตีบอส = อาวุธ (Tool) ที่ server ใส่ Backpack ให้ · ถือ/เก็บอัตโนมัติตามเขตบอส (Backpack เดิมของ Roblox ปิดอยู่)
--   ⚠️ ระบบ personal combat ของ Phase 4 **ยังไม่มีในโค้ด** — รอบนี้ทำขั้นต่ำเท่าที่ต้องใช้ตีบอส (ผู้ใช้เลือก)
--     ดาเมจ = Config.getWeaponDamage(weaponLevel) ตัวเดิม · ยังไม่มี PvP · บอสตีกลับปิดไว้ใน config
--   บันทึกว่าใครทำดาเมจบอสตัวนี้เท่าไร (damageBy) ให้ 5B แบ่งเงิน · **ยังไม่แจกรางวัลใดๆ**
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
}

local function cycleConfig()
	return Config.Balance.BossCycle
end

function BossService.newState(now: number): State
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
	}
end

-- บอสเกิด (ต้นกลางคืน) — ตัวเก่ายังไม่ตาย = ฟื้น HP เต็ม · บันทึกดาเมจเริ่มใหม่
-- ⚠️ ไม่ล้าง lockedUsers — ปลดล็อกได้ทางเดียวคือฆ่าบอส
local function spawnBoss(state: State, at: number)
	state.bossAlive = true
	state.bossMaxHp = cycleConfig().BOSS_HP
	state.bossHp = state.bossMaxHp
	state.bossSpawnedAt = at
	state.bossDiedAt = nil
	state.damageBy = {}
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
	return `{phaseText} (คืนที่ {state.cycle}) · เหลือ {math.ceil(BossService.getRemaining(state, now))} วิ · {bossText}`
		.. ` · ผู้ทำดาเมจ: {if #parts > 0 then table.concat(parts, ", ") else "-"} · ล็อกอัญเชิญ {locked} คน`
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

local BARRIER_NIGHT_TRANSPARENCY = 0.35
local WORLD_TICK = 0.25 -- วินาที — จังหวะเช็คเปลี่ยน phase · ถือ/เก็บอาวุธ · บอสตีกลับ

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

function BossService.start()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local Workspace = game:GetService("Workspace")
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	local DataService = require(ServerScriptService.DataService)

	serverNow = function()
		return Workspace:GetServerTimeNow()
	end
	local state = BossService.newState(serverNow())
	current = state

	local notify = Remotes.waitFor(Config.RemoteNames.BOSS_EVENT_NOTIFY)

	-- ของในโลก — MapBuilder.buildBossArena สร้างไว้แล้ว (Main เรียก MapBuilder.build ก่อน start)
	local arena = Workspace:WaitForChild("Map"):WaitForChild(Config.BOSS_ARENA_NAME)
	local barrier = arena:WaitForChild(Config.BOSS_BARRIER_NAME) :: BasePart
	local boss = arena:WaitForChild(Config.BOSS_MODEL_NAME) :: Model
	local hpFill = boss:FindFirstChild("HpFill", true) :: Frame?
	local hpText = boss:FindFirstChild("HpText", true) :: TextLabel?

	-- สถานะที่ client อ่าน (ทุกคนเห็นค่าเดียวกัน) — Attribute ของ Folder นี้ replicate ให้เอง
	local stateFolder = Instance.new("Folder")
	stateFolder.Name = Config.BOSS_STATE_FOLDER
	stateFolder.Parent = ReplicatedStorage

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
	end

	-- ต้นกลางคืน: วาปทุกคนที่มีตัวละครอยู่มาหน้าป้อม (คนที่เข้าเกม/เกิดใหม่ระหว่างคืนเกิดตามปกติ ไม่วาป)
	local function gatherEveryone()
		local index = 0
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and humanoid and root and humanoid.Health > 0 then
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
				gatherEveryone()
			end
			notify:FireAllClients(kind)
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

	onBossKilled = function()
		publish()
		notify:FireAllClients("killed")
		-- ⚠️ รอบนี้ยังไม่แจกรางวัล (5B) — log รายชื่อผู้ทำดาเมจไว้ตรวจ
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
		local distance = BossService.horizontalDistance(root.Position, Config.getBossArenaCenter())
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
	-- ⚠️ ไม่ล้าง lockedUsers ตอนออกเกม — ออกแล้วเข้าเซิร์ฟเดิมยังล็อกอยู่ (ตั้งใจ · กันออก-เข้าเพื่อหลุดล็อก)
	Players.PlayerRemoving:Connect(function(player: Player)
		state.lastAttackAt[player.UserId] = nil
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
		for _, userId in BossService.pickCounterTargets(state, Config.getBossArenaCenter(), positions) do
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

-- ข้ามไปต้นกลางคืนทันที: วาปทุกคนมาหน้าป้อม · กำแพงกั้นขึ้น · บอสเกิด/ฟื้น HP เต็ม · นับ 59 → 0 ใหม่
function BossService.debugBossNight(): string
	local state = requireState()
	applyEvents(BossService.forcePhase(state, "night", serverNow()))
	return BossService.describe(state, serverNow())
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
