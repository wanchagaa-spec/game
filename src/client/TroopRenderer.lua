--!strict
-- egg-army-game :: สนามรบ 6 ต่อ 6 (5E-1 — ภาพชั่วคราวพอให้ทดสอบใน Studio · โมเดลจริงทำ 5E-2)
--
-- ⚠️ วาดตาม **สถานะจริงจาก server** (payload.battle ใน FarmStateSync ~1 ครั้ง/วิ) ไม่จำลองอะไรเองแล้ว
--   ช่อง 1..6 ฝั่งเรา (ช่อง 1 = หน้าสุด · ช่อง 6 = หลังสุด ที่แม่ยืน) ยืนตรงข้ามศัตรูช่องเดียวกัน
--   ศัตรูยืนแถวหน้ากำแพงด่านที่กำลังตี · ตัวใหญ่ใหญ่กว่า · ศัตรูหมด = ทหารเราเดินเข้าไปตีกำแพง
--   แถบเลือดเหนือหัวทุกตัว · ป้อม = กล่องบนกำแพง + เส้นยิงสั้น ๆ ไปที่ตัวที่โดน
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
local ENEMY_LINE_GAP = 10 -- แถวศัตรูห่างจากกำแพง
local LINE_GAP = 9 -- แถวเราห่างจากแถวศัตรู
local RANK_STEP = 1.5 -- ช่องหลัง ๆ ถอยหลังนิดหน่อย (แม่ยืนหลังสุด)
local WALL_ATTACK_GAP = 6 -- ศัตรูหมดแล้ว ทหารเรายืนห่างกำแพงเท่านี้
local MOVE_LERP_PER_SECOND = 6
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

local function newUnit(kind: string, target: CFrame, isEnemy: boolean): Unit
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

local function ourTarget(slot: number, wallX: number, enemiesPresent: boolean): CFrame
	local enemyX = wallX - ENEMY_LINE_GAP
	local frontX = if enemiesPresent then enemyX - LINE_GAP else wallX - WALL_ATTACK_GAP
	local x = frontX - (slot - 1) * RANK_STEP
	return facing(Vector3.new(x, 0, slotZ(slot, x)), wallX + 100)
end

local function enemyTarget(slot: number, wallX: number): CFrame
	local x = wallX - ENEMY_LINE_GAP
	return facing(Vector3.new(x, 0, slotZ(slot, x)), wallX - 100)
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
local fighting = false

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
			local current: Unit = existing or newUnit(entry.kind, target, isEnemy)
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
		fighting = false
		return
	end
	local wall = wallX :: number

	-- ปิดอัญเชิญ = ทหารเรากลับคลัง (ไม่ใช่ตาย) → เก็บเงียบ ๆ ไม่มีเอฟเฟกต์ · ศัตรูบาดเจ็บยังยืนรอ
	if not payload.summonEnabled then
		clearSide(ours, false)
	end
	local enemyEntries = battle.enemies or {}
	syncSide(enemies, enemyEntries, true, function(slot: number): CFrame
		return enemyTarget(slot, wall)
	end)
	local enemiesPresent = #enemyEntries > 0
	if payload.summonEnabled then
		syncSide(ours, battle.our or {}, false, function(slot: number): CFrame
			return ourTarget(slot, wall, enemiesPresent)
		end)
	end
	fighting = next(ours) ~= nil

	if battle.turretActive then
		ensureTurret(wall)
		local target = if battle.turretShots and battle.turretShots > 0 and battle.turretTarget
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
-- เฟรม — เลื่อนเข้าช่อง + ท่าฟันเล็ก ๆ ตอนกำลังสู้ (ภาพล้วน)
--------------------------------------------------------------------------------

local function stepSide(side: { [number]: Unit }, alpha: number, swing: number)
	for slot, unit in side do
		if unit.model.Parent then
			-- พุ่งไปข้างหน้า (−Z ของโมเดล = ทิศที่หันอยู่) เป็นจังหวะ ๆ ตอนกำลังสู้
			local lunge = if fighting then math.max(0, math.sin(swing + slot * 1.3)) * SWING_DISTANCE else 0
			local goal = unit.target * CFrame.new(0, 0, -lunge)
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
		local alpha = math.clamp(delta * MOVE_LERP_PER_SECOND, 0, 1)
		local swing = os.clock() * SWING_SPEED
		stepSide(ours, alpha, swing)
		stepSide(enemies, alpha, swing)
	end)
end

return TroopRenderer
