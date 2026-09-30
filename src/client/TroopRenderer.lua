--!strict
-- egg-army-game :: สนามรบ 6 ต่อ 6 (5E-1 — ภาพชั่วคราวพอให้ทดสอบใน Studio · โมเดลจริงทำ 5E-2)
--
-- ⚠️ วาดตาม **สถานะจริงจาก server** (payload.battle ใน FarmStateSync ~1 ครั้ง/วิ) ไม่จำลองอะไรเองแล้ว
--   ช่อง 1..6 ฝั่งเรา (ช่อง 1 = หน้าสุด · ช่อง 6 = หลังสุด ที่แม่ยืน) ยืนตรงข้ามศัตรูช่องเดียวกัน
--   **เดินทัพ** (ผู้ใช้สั่ง · server จับเวลาจริง `battle.line/marchFrom/marchRemaining`):
--     ลงสนามจากสนามว่าง → กองทัพเราเดินออกจากแท่นอัญเชิญ + ศัตรูเดินออกจากหน้ากำแพงพร้อมกัน เจอกันกึ่งกลางเลน
--     (Config.getBattleMeetX · นอกระยะป้อม) · ศัตรูหมด → เดินต่อไปตีกำแพง · ศัตรูหมดตั้งแต่แรก → เดินจากแท่นถึงกำแพงเลย
--   ตัวใหญ่ใหญ่กว่า · แถบเลือดเหนือหัวทุกตัว · ป้อม = กล่องบนกำแพง + เส้นยิง **เฉพาะตอนกองทัพเดินถึงกำแพงแล้ว** (`turretFiring`)
-- ⚠️ ไม่ตัดสินอะไรเลย (server เป็นเจ้าของทุกอย่าง) · ตัวไหน "ใหม่" ดูจากเลือดที่เพิ่มขึ้น/ชนิดเปลี่ยน
--
-- ⚠️ **ห้ามใช้ Humanoid** — โมเดลคนบล็อก ๆ ประกอบจาก Part ขยับทั้งก้อนด้วย Model:PivotTo()
-- ⚠️ ทหารบนจอสูงสุด 12 ตัว (6 + 6) + ป้อม 1 — เบากว่าเดิมมาก (เดิมสูงสุด 120 ต่อฝ่าย)
-- ⚠️ แสดงเฉพาะของผู้เล่นคนนั้นเอง (FarmStateSync ยิงหาเจ้าของข้อมูลเท่านั้น) · วาดฝั่ง client เหมือน WallRenderer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CombatEffects = require(script.Parent:WaitForChild("CombatEffects"))

local TroopRenderer = {}

local MAP = Config.MapDimensions
local COMBAT = Config.Balance.Combat
local SLOTS = COMBAT.FIELD_SLOTS

-- สี/ขนาด/ระยะ — เรื่องหน้าตาล้วน ไม่กระทบกติกา (ค่าคงที่ท้องถิ่นแบบ WALL_COLOR ใน WallRenderer)
local CHILD_COLOR = Color3.fromRGB(70, 200, 90)
local MOTHER_COLOR = Color3.fromRGB(245, 195, 60)
local ENEMY_COLOR = Color3.fromRGB(170, 45, 45)
local BIG_ENEMY_SCALE = 1.7
local MOTHER_SCALE = 1.25
local ENEMY_LINE_GAP = 10 -- แถวศัตรู (ยังไม่เดินออกมา) ห่างจากกำแพง
local LINE_GAP = 9 -- แถวเราห่างจากแถวศัตรูตอนเจอกันกึ่งกลาง (ข้างละครึ่งจากจุดกึ่งกลาง)
local RANK_STEP = 1.5 -- ช่องหลัง ๆ ถอยหลังนิดหน่อย (แม่ยืนหลังสุด)
local WALL_ATTACK_GAP = 6 -- ถึงกำแพงแล้ว ทหารเรายืนห่างกำแพงเท่านี้
local MOVE_LERP_PER_SECOND = 6
local MARCH_LERP_PER_SECOND = 20 -- ระหว่างเดินทัพเป้าเลื่อนทุกเฟรม → ตามให้ทัน (ห่างเป้า ≈ ความเร็ว ÷ ค่านี้)
local MARCH_BOB_SPEED = 12
local MARCH_BOB_HEIGHT = 0.35
local SWING_SPEED = 9
local SWING_DISTANCE = 0.6
local HP_BAR_WIDTH = 3.2
local HP_BAR_HEIGHT = 0.35
local HP_OUR_COLOR = Color3.fromRGB(80, 220, 110)
local HP_ENEMY_COLOR = Color3.fromRGB(235, 70, 70)
local TURRET_COLOR = Color3.fromRGB(60, 62, 70)
local SHOT_COLOR = Color3.fromRGB(255, 170, 60)
local SHOT_SECONDS = 0.2

-- ทรงคน blockout (หัว-ลำตัว-แขน-ขา) · เว้นช่องระหว่างชิ้นให้ตาแยกออก
local LIMB_SIZE = Vector3.new(1, 2, 1)
local TORSO_SIZE = Vector3.new(2, 2, 1)
local HEAD_SIZE = Vector3.new(1.2, 1.2, 1.2)
local LEG_GAP = 0.2
local ARM_GAP = 0.2
local HIP_GAP = 0.2
local LEG_CENTER_Y = LIMB_SIZE.Y / 2
local TORSO_CENTER_Y = LIMB_SIZE.Y + HIP_GAP + TORSO_SIZE.Y / 2
local HEAD_CENTER_Y = LIMB_SIZE.Y + HIP_GAP + TORSO_SIZE.Y + HEAD_SIZE.Y / 2
local MODEL_HEIGHT = HEAD_CENTER_Y + HEAD_SIZE.Y / 2

--------------------------------------------------------------------------------
-- โฟลเดอร์ — แบบเดียวกับ WallRenderer (กัน StarterPlayerScripts→PlayerScripts ก็อปซ้อน)
--------------------------------------------------------------------------------

local folder: Folder? = nil

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local existing = Workspace:FindFirstChild("LocalTroops")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "LocalTroops"
	created.Parent = Workspace
	folder = created
	return created
end

--------------------------------------------------------------------------------
-- โมเดลคน blockout + แถบเลือด
--------------------------------------------------------------------------------

type Unit = {
	model: Model,
	fill: Frame,
	kind: string,
	hp: number,
	target: CFrame,
	scale: number,
	slot: number,
}

local function buildPersonModel(color: Color3, name: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local function part(partName: string, size: Vector3, x: number, y: number): Part
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = size
		p.Color = color
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Position = Vector3.new(x, y, 0)
		p.Parent = model
		return p
	end

	local torso = part("Torso", TORSO_SIZE, 0, TORSO_CENTER_Y)
	model.PrimaryPart = torso
	local head = part("Head", HEAD_SIZE, 0, HEAD_CENTER_Y)
	head.Shape = Enum.PartType.Ball -- ⚠️ Shape=Ball ต้องตั้งขนาดเท่ากันทั้งสามแกน
	part("ArmL", LIMB_SIZE, -(TORSO_SIZE.X / 2 + ARM_GAP + LIMB_SIZE.X / 2), TORSO_CENTER_Y)
	part("ArmR", LIMB_SIZE, TORSO_SIZE.X / 2 + ARM_GAP + LIMB_SIZE.X / 2, TORSO_CENTER_Y)
	part("LegL", LIMB_SIZE, -(LEG_GAP / 2 + LIMB_SIZE.X / 2), LEG_CENTER_Y)
	part("LegR", LIMB_SIZE, LEG_GAP / 2 + LIMB_SIZE.X / 2, LEG_CENTER_Y)
	-- pivot ที่จุดแตะพื้น → PivotTo วาง "เท้า" ตรงจุดเป๊ะ
	model.WorldPivot = CFrame.new(0, 0, 0)
	return model
end

-- แถบเลือดเหนือหัว — ⚠️ ขนาดเป็น studs ในโลก (fromScale) ไม่ใช่พิกเซล (tools/check-billboard-world-size.py)
local function attachHpBar(model: Model, color: Color3, scale: number): Frame
	local head = model:FindFirstChild("Head") :: BasePart
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(HP_BAR_WIDTH * scale, HP_BAR_HEIGHT * scale)
	billboard.Name = "HpBar"
	billboard.StudsOffsetWorldSpace = Vector3.new(0, (HEAD_SIZE.Y / 2 + 0.8) * scale, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Adornee = head
	billboard.Parent = model

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	return fill
end

local function newUnit(kind: string, slot: number, target: CFrame, isEnemy: boolean): Unit
	local color = if isEnemy then ENEMY_COLOR elseif kind == "mother" then MOTHER_COLOR else CHILD_COLOR
	local scale = if kind == "big" then BIG_ENEMY_SCALE elseif kind == "mother" then MOTHER_SCALE else 1
	local model = buildPersonModel(color, if isEnemy then "Enemy" else "Troop")
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	model.Parent = ensureFolder()
	-- ตัวใหม่เดินเข้าช่องจากด้านหลังแถวของตัวเอง (+Z ของโมเดล = ด้านหลัง · ภาพล้วน)
	model:PivotTo(target * CFrame.new(0, 0, 4))
	return {
		model = model,
		fill = attachHpBar(model, if isEnemy then HP_ENEMY_COLOR else HP_OUR_COLOR, scale),
		kind = kind,
		hp = math.huge,
		target = target,
		scale = scale,
		slot = slot,
	}
end

local function removeUnit(unit: Unit, withEffect: boolean)
	if withEffect and unit.model.Parent then
		CombatEffects.onDefenderDeath(unit.model:GetPivot().Position + Vector3.new(0, MODEL_HEIGHT * unit.scale / 2, 0))
	end
	unit.model:Destroy()
end

--------------------------------------------------------------------------------
-- ตำแหน่งช่อง
--------------------------------------------------------------------------------

local function slotZ(slot: number, x: number): number
	local laneHalf = math.max(Config.getLaneHalfWidthAt(x) - 6, 1)
	local spacing = math.min(8, laneHalf * 2 / math.max(SLOTS - 1, 1))
	return (slot - (SLOTS + 1) / 2) * spacing
end

-- หันหน้าไปทาง +X (ฝั่งเรา) / −X (ศัตรู) — CFrame.lookAt มองตามแกน −Z ของโมเดล
local function facing(position: Vector3, towardX: number): CFrame
	return CFrame.lookAt(position, Vector3.new(towardX, position.Y, position.Z))
end

-- แนวรบล่าสุดจาก server + เวลาที่ได้รับ (เดินทัพต่อเองระหว่างรอ sync ถัดไป ~1 วิ · sync ใหม่แก้ให้ตรงเสมอ)
local line = {
	wall = 0,
	pedestalX = 0,
	meetX = 0,
	at = nil :: string?, -- "middle" | "wall" | nil (สนามว่าง)
	from = nil :: string?, -- "pedestal" | "middle" | "wall"
	remaining = 0,
	duration = 0,
	receivedAt = 0,
	enemiesAtMiddle = false,
}

local function marchRemainingNow(): number
	return math.max(0, line.remaining - (os.clock() - line.receivedAt))
end

local function isMarching(): boolean
	return line.at ~= nil and line.duration > 0 and marchRemainingNow() > 0
end

local function marchProgress(): number
	if line.duration <= 0 then
		return 1
	end
	return 1 - marchRemainingNow() / line.duration
end

-- หน้าแถวของเราที่แต่ละจุด (แท่นอัญเชิญ · กึ่งกลางเลน · หน้ากำแพง)
local function ourAnchorX(where: string?): number
	if where == "pedestal" then
		return line.pedestalX
	elseif where == "middle" then
		return line.meetX - LINE_GAP / 2
	end
	return line.wall - WALL_ATTACK_GAP
end

local function ourFrontX(): number
	local goal = ourAnchorX(line.at)
	if line.from == nil or not isMarching() then
		return goal
	end
	local start = ourAnchorX(line.from)
	return start + (goal - start) * marchProgress()
end

-- ศัตรู: ยืนหน้ากำแพงจนกว่ากองทัพเราจะเดินออกมา → เดินออกมาพร้อมกันไปเจอกันกึ่งกลาง → ยืนกึ่งกลางต่อ
local function enemyFrontX(): number
	local home = line.wall - ENEMY_LINE_GAP
	local middle = line.meetX + LINE_GAP / 2
	if line.enemiesAtMiddle then
		return middle
	end
	if line.at == "middle" and isMarching() then
		return home + (middle - home) * marchProgress()
	end
	return home
end

local function ourTarget(slot: number): CFrame
	local x = ourFrontX() - (slot - 1) * RANK_STEP
	return facing(Vector3.new(x, 0, slotZ(slot, x)), line.wall + 100)
end

local function enemyTarget(slot: number): CFrame
	local x = enemyFrontX() + (if slot == 1 then 0 else RANK_STEP)
	return facing(Vector3.new(x, 0, slotZ(slot, x)), line.wall - 1000)
end

--------------------------------------------------------------------------------
-- ป้อมบนกำแพง
--------------------------------------------------------------------------------

local turret: Model? = nil

local function ensureTurret(wallX: number)
	local current = turret
	if not current or not current.Parent then
		local model = Instance.new("Model")
		model.Name = "Turret"
		local base = Instance.new("Part")
		base.Name = "Base"
		base.Size = Vector3.new(5, 3, 5)
		base.Color = TURRET_COLOR
		base.Material = Enum.Material.Metal
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.Parent = model
		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Size = Vector3.new(4, 1, 1)
		barrel.Color = TURRET_COLOR
		barrel.Material = Enum.Material.Metal
		barrel.Anchored = true
		barrel.CanCollide = false
		barrel.CanQuery = false
		barrel.CanTouch = false
		barrel.Parent = model
		model.PrimaryPart = base
		model.Parent = ensureFolder()
		current = model
		turret = model
	end
	local model = current :: Model
	local baseY = MAP.Lane.WallHeight + 1.5
	local base = model:FindFirstChild("Base") :: BasePart
	local barrel = model:FindFirstChild("Barrel") :: BasePart
	base.CFrame = CFrame.new(wallX, baseY, 0)
	barrel.CFrame = CFrame.new(wallX - 3, baseY + 0.5, 0)
end

local function removeTurret()
	if turret then
		turret:Destroy()
		turret = nil
	end
end

local function drawShot(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	if distance < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "TurretShot"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = SHOT_COLOR
	beam.Size = Vector3.new(0.3, 0.3, distance)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = ensureFolder()
	Debris:AddItem(beam, SHOT_SECONDS)
end

--------------------------------------------------------------------------------
-- อัปเดตจาก sync
--------------------------------------------------------------------------------

local ours: { [number]: Unit } = {}
local enemies: { [number]: Unit } = {}

local function clearSide(side: { [number]: Unit }, withEffect: boolean)
	for slot, unit in side do
		removeUnit(unit, withEffect)
		side[slot] = nil
	end
end

-- entries = รายการจาก server ({ slot, kind, hp, maxHp }) · ตัวใหม่ = ชนิดเปลี่ยนหรือเลือดเพิ่มขึ้น (ตัวเก่าตาย ตัวใหม่ลงแทน)
local function syncSide(side: { [number]: Unit }, entries: { any }, isEnemy: boolean, targetOf: (number) -> CFrame)
	local seen: { [number]: boolean } = {}
	for _, entry in entries do
		local slot = entry.slot
		if type(slot) == "number" and slot >= 1 and slot <= SLOTS then
			seen[slot] = true
			local target = targetOf(slot)
			local existing: Unit? = side[slot]
			if existing and (existing.kind ~= entry.kind or entry.hp > existing.hp + 1e-6) then
				removeUnit(existing, true)
				existing = nil
			end
			local current: Unit = existing or newUnit(entry.kind, slot, target, isEnemy)
			side[slot] = current
			current.target = target
			current.hp = entry.hp
			local ratio = if entry.maxHp > 0 then math.clamp(entry.hp / entry.maxHp, 0, 1) else 0
			current.fill.Size = UDim2.fromScale(ratio, 1)
		end
	end
	for slot, unit in side do
		if not seen[slot] then
			removeUnit(unit, true)
			side[slot] = nil
		end
	end
end

-- ⚠️ เรียกทุกครั้งที่ FarmStateSync มาใหม่ (Main.client.lua)
function TroopRenderer.updateFromPayload(payload: any)
	local battle = payload and payload.battle
	local stage = battle and battle.stage
	local wallX = if stage then Config.getWallX(stage) else nil
	if not battle or not stage or not wallX then
		-- ไม่มีด่านที่มีกำแพงให้ตี (ด่าน 1 / ผ่านครบ) → เก็บทุกอย่าง
		clearSide(ours, false)
		clearSide(enemies, false)
		removeTurret()
		line.at = nil
		return
	end
	local wall = wallX :: number
	line.wall = wall
	line.pedestalX = Config.getSummonPedestalCenter().X
	line.meetX = Config.getBattleMeetX(stage) or (line.pedestalX + wall) / 2
	line.at = if payload.summonEnabled and (battle.line == "middle" or battle.line == "wall") then battle.line else nil
	line.from = if type(battle.marchFrom) == "string" then battle.marchFrom else nil
	line.remaining = if type(battle.marchRemaining) == "number" then battle.marchRemaining else 0
	line.duration = if type(battle.marchDuration) == "number" then battle.marchDuration else 0
	line.receivedAt = os.clock()
	line.enemiesAtMiddle = battle.enemiesAtMiddle == true

	-- ปิดอัญเชิญ = ทหารเรากลับคลัง (ไม่ใช่ตาย) → เก็บเงียบ ๆ ไม่มีเอฟเฟกต์ · ศัตรูบาดเจ็บยังยืนรอ
	if not payload.summonEnabled then
		clearSide(ours, false)
	end
	syncSide(enemies, battle.enemies or {}, true, enemyTarget)
	if payload.summonEnabled then
		-- ตัวใหม่ตอนเพิ่งเริ่มเดินทัพ = โผล่ที่แท่นอัญเชิญ (หน้าแถว ณ ตอนนี้) · ตัวที่ลงแทนระหว่างสู้ = โผล่หลังแถวแล้วเดินเข้าช่อง
		syncSide(ours, battle.our or {}, false, ourTarget)
	end

	-- ป้อมตั้งอยู่บนกำแพงเสมอ · ยิงเฉพาะตอนกองทัพเดินถึงกำแพงแล้ว (สู้กันกึ่งกลาง = นอกระยะ)
	if battle.turretActive then
		ensureTurret(wall)
		local target = if battle.turretFiring and battle.turretShots and battle.turretShots > 0 and battle.turretTarget
			then ours[battle.turretTarget]
			else nil
		if target then
			-- ปลายกระบอกป้อม (ตำแหน่งเดียวกับ Barrel ใน ensureTurret) → กลางตัวที่โดน
			local muzzle = Vector3.new(wall - 5, MAP.Lane.WallHeight + 2, 0)
			drawShot(muzzle, target.model:GetPivot().Position + Vector3.new(0, MODEL_HEIGHT * target.scale * 0.6, 0))
		end
	else
		removeTurret()
	end
end

--------------------------------------------------------------------------------
-- เฟรม — เดินทัพ (เป้าเลื่อนทุกเฟรม) · เลื่อนเข้าช่อง · ท่าฟันเล็ก ๆ ตอนกำลังสู้ (ภาพล้วน)
--------------------------------------------------------------------------------

-- side = ฝั่งไหน · walking = ฝั่งนี้กำลังเดินอยู่ · fighting = ฝั่งนี้กำลังตี (ศัตรูตรงหน้า/กำแพง)
local function stepSide(side: { [number]: Unit }, targetOf: (number) -> CFrame, delta: number, walking: boolean, fighting: boolean)
	local alpha = math.clamp(delta * (if walking then MARCH_LERP_PER_SECOND else MOVE_LERP_PER_SECOND), 0, 1)
	local clock = os.clock()
	for slot, unit in side do
		if unit.model.Parent then
			unit.target = targetOf(unit.slot)
			-- เดิน = เด้งขึ้นลงเล็กน้อย · สู้ = พุ่งไปข้างหน้า (−Z ของโมเดล = ทิศที่หันอยู่) เป็นจังหวะ ๆ
			local bob = if walking then math.abs(math.sin(clock * MARCH_BOB_SPEED + slot)) * MARCH_BOB_HEIGHT else 0
			local lunge = if fighting then math.max(0, math.sin(clock * SWING_SPEED + slot * 1.3)) * SWING_DISTANCE else 0
			local goal = unit.target * CFrame.new(0, bob, -lunge)
			local current = unit.model:GetPivot()
			unit.model:PivotTo(current:Lerp(goal, alpha))
		end
	end
end

function TroopRenderer.start()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	ensureFolder()
	RunService.Heartbeat:Connect(function(delta: number)
		local marching = isMarching()
		local enemiesWalking = marching and line.at == "middle" and not line.enemiesAtMiddle
		local oursFighting = line.at ~= nil and not marching and (line.at == "wall" or next(enemies) ~= nil)
		stepSide(ours, ourTarget, delta, marching, oursFighting)
		stepSide(enemies, enemyTarget, delta, enemiesWalking, oursFighting and line.at == "middle")
	end)
end

return TroopRenderer
