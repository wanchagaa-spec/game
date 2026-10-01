--!strict
-- egg-army-game :: สนามรบสองแถว (5E-1b — ภาพชั่วคราวพอให้ทดสอบใน Studio · โมเดลจริงทำ 5E-2)
--
-- ⚠️ วาดตาม **สถานะจริงจาก server** (payload.battle ใน FarmStateSync ~1 ครั้ง/วิ) ไม่จำลองอะไรเอง
--   แถวเรา + แถวศัตรู ฝั่งละไม่เกิน LINE_LENGTH (10) ตัว เดินเรียงเดี่ยวกลางเลน **ช่องว่างระหว่างตัวเท่ากัน** (UNIT_GAP)
--   **ตัวหน้าสุดของสองฝั่งยืนปะทะกัน** (ขยับฟันเฉพาะสองตัวนี้) · ตัวอื่นเดินตามรอคิว · ตัวหน้าตาย = ทั้งแถวเดินขยับขึ้นเอง
--   **ทะยอยออกจากแท่นทีละตัว** (ผู้ใช้สั่ง): แถวเริ่มเดินทัพ = ตัวหน้าออกก่อน ตัวถัดไปโผล่จากแท่นเมื่อตัวหน้าเดินพ้นไปหนึ่งช่อง
--     (ภาพล้วน · server ใส่ 10 ตัวเข้าแถวพร้อมกัน แต่ตีแค่ตัวหน้าสุด → ผลรบเท่ากัน) · ตัวที่ต่อท้ายระหว่างสู้ = โผล่หลังท้ายแถวหนึ่งช่องแล้วเดินเข้าที่
--   **เดินด้วยความเร็วคงที่** = ARMY_MARCH_SPEED (ความเร็วเดินทัพของ server ตัวเดียวกัน) + เร่งตามทันถ้าค้างไกล (ไม่ใช่ lerp ที่พุ่งตอนแรก)
--   ตามตัวด้วย `id` จาก server (เรา = เลขประจำตัวตอนปล่อย · ศัตรู = ตัวที่เท่าไรของด่าน) ไม่ใช่ตำแหน่ง
--   **เดินทัพ** (ผู้ใช้สั่ง · server จับเวลาจริง `battle.line/marchFrom/marchRemaining`):
--     แถวว่างแล้วปล่อยใหม่ → แถวเราเดินออกจากแท่นอัญเชิญ + แถวศัตรูเดินออกจากหน้ากำแพงพร้อมกัน เจอกันกึ่งกลางเลน
--     (Config.getBattleMeetX · นอกระยะป้อม) · ศัตรูหมด → เดินต่อไปตีกำแพง · ศัตรูหมดตั้งแต่แรก → เดินจากแท่นถึงกำแพงเลย
--   ตัวใหญ่ใหญ่กว่า · แถบเลือดเหนือหัวทุกตัว · ป้อม = กล่องบนกำแพง + เส้นยิง **เฉพาะตอนแถวเราเดินถึงกำแพงแล้ว** (`turretFiring`)
-- ⚠️ ไม่ตัดสินอะไรเลย (server เป็นเจ้าของทุกอย่าง)
--
-- ⚠️ **ห้ามใช้ Humanoid** — โมเดลคนบล็อก ๆ ประกอบจาก Part ขยับทั้งก้อนด้วย Model:PivotTo()
-- ⚠️ ทหารบนจอสูงสุด 20 ตัว (10 + 10) + ป้อม 1
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
local LINE_LENGTH = Config.Balance.Combat.LINE_LENGTH

-- สี/ขนาด/ระยะ — เรื่องหน้าตาล้วน ไม่กระทบกติกา (ค่าคงที่ท้องถิ่นแบบ WALL_COLOR ใน WallRenderer)
local CHILD_COLOR = Color3.fromRGB(70, 200, 90)
local MOTHER_COLOR = Color3.fromRGB(245, 195, 60)
local ENEMY_COLOR = Color3.fromRGB(170, 45, 45)
local BIG_ENEMY_SCALE = 1.7
local MOTHER_SCALE = 1.25
local ENEMY_WALL_GAP = 5 -- แถวศัตรู (ยังไม่เดินออกมา): ตัวท้ายแถวยืนห่างกำแพงเท่านี้
local CLASH_GAP = 4 -- ตัวหน้าสุดสองฝั่งห่างกันเท่านี้ตอนปะทะกึ่งกลาง (ข้างละครึ่งจากจุดกึ่งกลาง)
local UNIT_GAP = 5 -- ช่องว่างระหว่างตัว (ขอบถึงขอบ) เท่ากันทุกคู่ · ตัวใหญ่กินที่ตามความหนาตัวเอง
local WALL_ATTACK_GAP = 4 -- ถึงกำแพงแล้ว ตัวหน้าสุดของเรายืนห่างกำแพงเท่านี้
-- เดินด้วยความเร็วเดียวกับเดินทัพของ server (ตัวหน้าสุดถึงแนวรบพร้อม server) · ค้างห่างเป้า = เร่งเพิ่มตามระยะ (ตามทันเอง)
local WALK_SPEED = Config.Balance.Combat.ARMY_MARCH_SPEED
local CATCH_UP_PER_SECOND = 1.5 -- studs/วิ ที่เร่งเพิ่มต่อระยะค้าง 1 stud
local ARRIVE_EPSILON = 0.05
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
local UNIT_DEPTH = HEAD_SIZE.Z -- ความหนาตามแนวแถว (หัวหนาสุด) — ระยะจุดกึ่งกลางถึงกัน = UNIT_GAP + ความหนาเฉลี่ย

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
	scale: number,
	pos: number, -- ตำแหน่งในแถวตอนนี้ (1 = หน้าสุด)
	x: number, -- ตำแหน่งบนพื้นตามแนวเลน (ไม่รวมท่าเด้ง/ฟัน) · เดินเข้าหาเป้าด้วยความเร็วคงที่
	visible: boolean, -- ยังไม่โผล่จากแท่นอัญเชิญ = false (ทะยอยออกทีละตัว)
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

-- ⚠️ ยังไม่โผล่ (visible = false) = ยังไม่ใส่ลงโลก · stepSide ใส่ให้ตอนถึงคิวออกจากแท่น
local function newUnit(kind: string, pos: number, isEnemy: boolean, x: number, visible: boolean): Unit
	local color = if isEnemy then ENEMY_COLOR elseif kind == "mother" then MOTHER_COLOR else CHILD_COLOR
	local scale = if kind == "big" then BIG_ENEMY_SCALE elseif kind == "mother" then MOTHER_SCALE else 1
	local model = buildPersonModel(color, if isEnemy then "Enemy" else "Troop")
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	model.Parent = if visible then ensureFolder() else nil
	return {
		model = model,
		fill = attachHpBar(model, if isEnemy then HP_ENEMY_COLOR else HP_OUR_COLOR, scale),
		kind = kind,
		hp = math.huge,
		scale = scale,
		pos = pos,
		x = x,
		visible = visible,
	}
end

local function removeUnit(unit: Unit, withEffect: boolean)
	if withEffect and unit.visible and unit.model.Parent then
		CombatEffects.onDefenderDeath(Vector3.new(unit.x, MODEL_HEIGHT * unit.scale / 2, 0))
	end
	unit.model:Destroy()
end

--------------------------------------------------------------------------------
-- ตำแหน่งในแถว
--------------------------------------------------------------------------------

local function scaleOf(kind: string): number
	return if kind == "big" then BIG_ENEMY_SCALE elseif kind == "mother" then MOTHER_SCALE else 1
end

-- ระยะจุดกึ่งกลางถึงจุดกึ่งกลางของสองตัวที่ติดกัน = ช่องว่างเท่ากันทุกคู่ + ความหนาเฉลี่ยของสองตัว (ตัวใหญ่หนากว่า)
local function spacingBetween(previousScale: number, currentScale: number): number
	return UNIT_GAP + UNIT_DEPTH * (previousScale + currentScale) / 2
end

-- ระยะจากตัวหน้าสุดถึงตัวที่ pos — คิดใหม่ทุก sync จากชนิดในแถว
local ourOffsets: { number } = {}
local enemyOffsets: { number } = {}

local function computeOffsets(entries: { any }): { number }
	local scales: { number } = {}
	for _, entry in entries do
		if type(entry.pos) == "number" and entry.pos >= 1 and entry.pos <= LINE_LENGTH then
			scales[entry.pos] = scaleOf(entry.kind)
		end
	end
	local offsets: { number } = { 0 }
	for pos = 2, LINE_LENGTH do
		offsets[pos] = offsets[pos - 1] + spacingBetween(scales[pos - 1] or 1, scales[pos] or 1)
	end
	return offsets
end

local function offsetAt(offsets: { number }, pos: number): number
	return offsets[pos] or (pos - 1) * spacingBetween(1, 1)
end

-- หันหน้าไปทาง +X (ฝั่งเรา) / −X (ศัตรู) — CFrame.lookAt มองตามแกน −Z ของโมเดล
local function facing(position: Vector3, towardX: number): CFrame
	return CFrame.lookAt(position, Vector3.new(towardX, position.Y, position.Z))
end

-- แนวรบล่าสุดจาก server + เวลาที่ได้รับ (เดินทัพต่อเองระหว่างรอ sync ถัดไป ~1 วิ · sync ใหม่แก้ให้ตรงเสมอ)
local line = {
	stage = nil :: number?,
	wall = 0,
	pedestalX = 0,
	meetX = 0,
	at = nil :: string?, -- "middle" | "wall" | nil (แถวว่าง)
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

-- ตัวหน้าสุดของเราที่แต่ละจุด (แท่นอัญเชิญ · กึ่งกลางเลน · หน้ากำแพง)
local function ourAnchorX(where: string?): number
	if where == "pedestal" then
		return line.pedestalX
	elseif where == "middle" then
		return line.meetX - CLASH_GAP / 2
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

-- ศัตรู: ยืนเรียงหน้ากำแพงจนกว่าแถวเราจะเดินออกมา → เดินออกมาพร้อมกันไปเจอกันกึ่งกลาง → ยืนกึ่งกลางต่อ
local function enemyFrontX(): number
	local home = line.wall - ENEMY_WALL_GAP - offsetAt(enemyOffsets, LINE_LENGTH)
	local middle = line.meetX + CLASH_GAP / 2
	if line.enemiesAtMiddle then
		return middle
	end
	if line.at == "middle" and isMarching() then
		return home + (middle - home) * marchProgress()
	end
	return home
end

-- เป้าบนพื้นของตัวที่ pos (ยังไม่ตัดขอบ) — เรา: ไล่จากตัวหน้าสุดไปทางแท่น · ศัตรู: ไล่ไปทางกำแพง
local function ourTargetX(pos: number): number
	return ourFrontX() - offsetAt(ourOffsets, pos)
end

local function enemyTargetX(pos: number): number
	return enemyFrontX() + offsetAt(enemyOffsets, pos)
end

-- ทหารเราไม่ถอยหลังเลยแท่นอัญเชิญ (ยังไม่ถึงคิวออก = ยังไม่โผล่) · ศัตรูไม่ทะลุผิวกำแพง
local function ourLimitX(x: number): number
	return math.max(x, line.pedestalX)
end

local function enemyLimitX(x: number): number
	return math.min(x, line.wall - MAP.StageWall.Thickness / 2 - 1)
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

local ours: { [number]: Unit } = {} -- key = id จาก server
local enemies: { [number]: Unit } = {}

local function clearSide(side: { [number]: Unit }, withEffect: boolean)
	for id, unit in side do
		removeUnit(unit, withEffect)
		side[id] = nil
	end
end

-- entries = รายการจาก server ({ pos, id, kind, hp, maxHp }) · ตามตัวด้วย id → แถวขยับขึ้นแล้วตัวเดิมเดินเข้าตำแหน่งใหม่เอง
-- ตัวที่หายไป: อยู่หน้าตัวที่รอดคนแรก = ตาย (เอฟเฟกต์ · sync ~1 วิ ตายได้หลายตัวในรอบเดียว) · อยู่หลัง = กลับกอง/ล้างแถว (เงียบ)
-- ตัวใหม่: แถวใหม่ทั้งแถว = ยืนที่เป้าเลย · ต่อท้ายแถวที่มีอยู่ = โผล่หลังเป้าหนึ่งช่อง (ฝั่งที่มันเดินมา) แล้วเดินเข้าที่
-- ⚠️ ทหารเราที่เป้ายังอยู่หลังแท่น = ยังไม่โผล่ (ทะยอยออกทีละตัวใน stepSide)
local function syncSide(side: { [number]: Unit }, entries: { any }, isEnemy: boolean)
	local oldPos: { [number]: number } = {}
	for id, unit in side do
		oldPos[id] = unit.pos
	end
	local joining = next(side) ~= nil
	local seen: { [number]: boolean } = {}
	local firstSurvivorOldPos = math.huge
	for _, entry in entries do
		local id, pos = entry.id, entry.pos
		if type(id) == "number" and type(pos) == "number" and pos >= 1 and pos <= LINE_LENGTH then
			seen[id] = true
			local current: Unit? = side[id]
			if current then
				firstSurvivorOldPos = math.min(firstSurvivorOldPos, oldPos[id] or math.huge)
			else
				local scale = scaleOf(entry.kind)
				local step = if joining then spacingBetween(scale, scale) else 0
				local spawnX, visible
				if isEnemy then
					spawnX = enemyLimitX(enemyTargetX(pos) + step)
					visible = true
				else
					local goal = ourTargetX(pos)
					spawnX = ourLimitX(goal - step)
					visible = goal >= line.pedestalX - ARRIVE_EPSILON
				end
				current = newUnit(entry.kind, pos, isEnemy, spawnX, visible)
				local towardX = if isEnemy then line.wall - 1000 else line.wall + 100
				current.model:PivotTo(facing(Vector3.new(spawnX, 0, 0), towardX))
				side[id] = current
			end
			local unit = current :: Unit
			unit.pos = pos
			unit.hp = entry.hp
			local ratio = if entry.maxHp > 0 then math.clamp(entry.hp / entry.maxHp, 0, 1) else 0
			unit.fill.Size = UDim2.fromScale(ratio, 1)
		end
	end
	for id, unit in side do
		if not seen[id] then
			removeUnit(unit, (oldPos[id] or math.huge) < firstSurvivorOldPos)
			side[id] = nil
		end
	end
end

local function frontOf(side: { [number]: Unit }): Unit?
	for _, unit in side do
		if unit.pos == 1 and unit.visible then
			return unit
		end
	end
	return nil
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
		line.stage = nil
		return
	end
	-- ด่านเปลี่ยน (ด่านเก่าพัง) → เริ่มสองแถวใหม่ (เลขศัตรูของด่านใหม่ซ้ำกับด่านเก่าได้ · ทหารที่รอดกลับกองแล้ว)
	if line.stage ~= stage then
		clearSide(ours, false)
		clearSide(enemies, false)
		line.stage = stage
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

	local enemyEntries = battle.enemies or {}
	local ourEntries = if payload.summonEnabled then battle.our or {} else {}
	enemyOffsets = computeOffsets(enemyEntries)
	ourOffsets = computeOffsets(ourEntries)

	-- ปิดอัญเชิญ = ทหารเรากลับคลัง (ไม่ใช่ตาย) → เก็บเงียบ ๆ ไม่มีเอฟเฟกต์ · ศัตรูบาดเจ็บยังยืนรอ
	if not payload.summonEnabled then
		clearSide(ours, false)
	end
	syncSide(enemies, enemyEntries, true)
	if payload.summonEnabled then
		-- เพิ่งเริ่มเดินทัพ = ตัวหน้าโผล่ที่แท่นอัญเชิญ ตัวอื่นทะยอยโผล่ทีละตัว (stepSide) · ตัวที่ต่อท้ายระหว่างสู้ = โผล่หลังท้ายแถวแล้วเดินเข้าที่
		syncSide(ours, ourEntries, false)
	end

	-- ป้อมตั้งอยู่บนกำแพงเสมอ · ยิงตัวหน้าสุดเฉพาะตอนแถวเราเดินถึงกำแพงแล้ว (สู้กันกึ่งกลาง = นอกระยะ)
	if battle.turretActive then
		ensureTurret(wall)
		local target = if battle.turretFiring and battle.turretShots and battle.turretShots > 0 then frontOf(ours) else nil
		if target then
			-- ปลายกระบอกป้อม (ตำแหน่งเดียวกับ Barrel ใน ensureTurret) → กลางตัวที่โดน
			local muzzle = Vector3.new(wall - 5, MAP.Lane.WallHeight + 2, 0)
			drawShot(muzzle, Vector3.new(target.x, MODEL_HEIGHT * target.scale * 0.6, 0))
		end
	else
		removeTurret()
	end
end

--------------------------------------------------------------------------------
-- เฟรม — เดินด้วยความเร็วคงที่ (เดินทัพ · แถวขยับ) · ทะยอยโผล่จากแท่นทีละตัว · ท่าฟันเฉพาะตัวหน้าสุดที่กำลังปะทะ (ภาพล้วน)
--------------------------------------------------------------------------------

-- fighting = ตัวหน้าสุดของฝั่งนี้กำลังตี (ศัตรูตรงหน้า/กำแพง)
local function stepSide(side: { [number]: Unit }, isEnemy: boolean, delta: number, fighting: boolean)
	local clock = os.clock()
	local towardX = if isEnemy then line.wall - 1000 else line.wall + 100
	for _, unit in side do
		local rawGoal = if isEnemy then enemyTargetX(unit.pos) else ourTargetX(unit.pos)
		local goal = if isEnemy then enemyLimitX(rawGoal) else ourLimitX(rawGoal)
		if not unit.visible then
			-- ถึงคิวออกจากแท่น = เป้าเดินพ้นแท่นแล้ว (ตัวหน้าเดินห่างออกไปหนึ่งช่องพอดี → ระยะห่างเท่ากันตั้งแต่ออก)
			if rawGoal < line.pedestalX - ARRIVE_EPSILON then
				continue
			end
			unit.visible = true
			unit.x = line.pedestalX
			unit.model.Parent = ensureFolder()
		end
		if not unit.model.Parent then
			continue
		end
		local distance = goal - unit.x
		local moving = math.abs(distance) > ARRIVE_EPSILON
		if moving then
			local speed = WALK_SPEED + math.abs(distance) * CATCH_UP_PER_SECOND
			local step = math.min(math.abs(distance), speed * delta)
			unit.x += if distance > 0 then step else -step
		end
		-- เดิน = เด้งขึ้นลงเล็กน้อย · ปะทะ = ตัวหน้าสุดพุ่งไปข้างหน้า (−Z ของโมเดล = ทิศที่หันอยู่) เป็นจังหวะ ๆ
		local bob = if moving then math.abs(math.sin(clock * MARCH_BOB_SPEED + unit.pos)) * MARCH_BOB_HEIGHT else 0
		local lunge = if fighting and unit.pos == 1 and not moving then math.max(0, math.sin(clock * SWING_SPEED)) * SWING_DISTANCE else 0
		local position = Vector3.new(unit.x, 0, 0)
		unit.model:PivotTo(facing(position, towardX) * CFrame.new(0, bob, -lunge))
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
		local oursFighting = line.at ~= nil and not marching and (line.at == "wall" or next(enemies) ~= nil)
		stepSide(ours, false, delta, oursFighting)
		stepSide(enemies, true, delta, oursFighting and line.at == "middle")
	end)
end

return TroopRenderer
