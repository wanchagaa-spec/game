--!strict
-- egg-army-game :: โมเดลทหารฝ่ายเรา/ฝ่ายรับระหว่างการรบ (Phase 3B-1 — ภาพประกอบ ยังไม่ polish)
--
-- ⚠️ **โมเดลที่เห็นเป็นภาพประกอบ ไม่ใช่ตัวแทนจริงของ damage** — CombatService (3A) คำนวณ
-- damage เป็นก้อนรวมต่อ tick ไม่มีแนวคิด "ทหารตัวที่ 47 ตีตอนไหน" การเดิน/สปอนของโมเดลที่นี่
-- จึงเป็นแค่ simulation ฝั่ง client ล้วน ๆ ไม่ผูกกับ event การตีจริงจาก server แบบ 1:1 —
-- แค่ทำให้ "รู้สึกสอดคล้อง" กับอัตราปล่อยจริง (Config.getReleaseRate) เท่านั้น
--
-- ⚠️ **ห้ามใช้ Humanoid** — เหตุผลเดียวกับ PenService (แม่เดินในคอก): ทหารเต็มจอ (สูงสุด
-- MAX_VISIBLE_UNITS ต่อฝ่าย) × ผู้เล่นเต็มเซิร์ฟ = Humanoid หลักร้อยตัว หนักเกินไปมาก
-- ใช้โมเดลคนบล็อก ๆ ประกอบจาก Part (หัว-ลำตัว-แขน-ขา แบบ Roblox classic) แล้วขยับทั้งก้อน
-- ด้วย Model:PivotTo() แทน — เหมือนหลักการเดียวกับ CFrame lerp ที่ PenService ใช้กับตัวแม่
--
-- ⚠️ แสดงเฉพาะทหารของผู้เล่นคนนั้นเอง (FarmStateSync ยิงหาเจ้าของข้อมูลเท่านั้นอยู่แล้ว
-- จึงไม่ต้องกรองเพิ่ม) และวาดฝั่ง client เท่านั้นด้วยเหตุผลเดียวกับ WallRenderer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
-- ⚠️ Phase 3B-2: เอฟเฟกต์ตอนทหารฝ่ายรับตาย (แทนที่จะ pop หายเฉย ๆ) — ดูเหตุผล require
-- แบบ WaitForChild เดียวกับที่ Main.client.lua ใช้กับไฟล์นี้เอง (StarterPlayerScripts
-- ก็อปมาเป็น PlayerScripts ช้ากว่าที่สคริปต์นี้เริ่มทำงาน)
local CombatEffects = require(script.Parent:WaitForChild("CombatEffects"))

local TroopRenderer = {}

local MAP = Config.MapDimensions
local COMBAT = Config.Balance.Combat

-- ⚠️ ใช้ค่าเดียวกับที่ Config.getVisibleUnitCount() สมมติไว้แล้ว (WALK_SECONDS_TO_WALL = 30)
-- ไม่งั้นจำนวนโมเดลที่ "ควรจะ" ลอยอยู่พร้อมกันตามสูตรนั้น กับที่ TroopRenderer สปอนจริง
-- จะคนละตัวเลขกัน — เดินด้วยเวลาคงที่ ไม่ใช่ความเร็วคงที่ (ระยะทางต่างกันมากตามด่านที่ตีอยู่
-- ด่าน 2 ห่างจากจุดปล่อยแค่ ~180 studs ด่าน 9 ห่างเกือบ 1,600 studs) — ยอมรับว่าความเร็วที่เห็น
-- จะไม่เท่ากันทุกด่าน เพราะเป็นแค่ simulation ไม่ใช่ของจริง (ดูคอมเมนต์หัวไฟล์)
local WALK_SECONDS = COMBAT.WALK_SECONDS_TO_WALL

-- ⚠️ Phase 3B-2: sync เดียวลดจำนวนโมเดลได้มากสุดถึง MAX_VISIBLE_UNITS ตัวพร้อมกัน (เช่น สต็อกใหญ่
-- ปล่อยรวดเดียวจบทั้งด่าน) — เล่นเอฟเฟกต์ตายจริงแค่ไม่กี่ตัวแรกต่อรอบ sync พอ ไม่งั้นเกิด
-- ParticleEmitter เป็นร้อยตัวพร้อมกันในเฟรมเดียว ("ต้องเบา" ตามที่สั่ง) ตัวที่เหลือยัง pop หายปกติ
local DEATH_EFFECT_CAP_PER_UPDATE = 12

local OUR_COLOR = Color3.fromRGB(70, 200, 90)
local DEFENDER_COLOR = Color3.fromRGB(150, 45, 45)

-- ทรงคน blockout แบบคลาสสิก (หัว-ลำตัว-แขน-ขา) — ตัวเลขล้วนเรื่อง "หน้าตา" ไม่กระทบกติกา
-- เก็บเป็นค่าคงที่ท้องถิ่นแบบเดียวกับ WALL_COLOR ใน WallRenderer.lua ไม่ต้องขึ้น Config
-- (คนละเรื่องกับ Config.MapDimensions.Blockout ที่ผูกกับตารางน้ำหนัก/tier ของไข่-แม่)
local LIMB_SIZE = Vector3.new(1, 2, 1)
local TORSO_SIZE = Vector3.new(2, 2, 1)
local HEAD_SIZE = Vector3.new(1.2, 1.2, 1.2)

-- ความสูงจากพื้น (Y=0) ของจุดศูนย์กลางแต่ละชิ้น — ขาวางแตะพื้นพอดี
local LEG_CENTER_Y = LIMB_SIZE.Y / 2
local TORSO_CENTER_Y = LIMB_SIZE.Y + TORSO_SIZE.Y / 2
local HEAD_CENTER_Y = LIMB_SIZE.Y + TORSO_SIZE.Y + HEAD_SIZE.Y / 2

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

local function ensureSubFolder(name: string): Folder
	local parent = ensureFolder()
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

--------------------------------------------------------------------------------
-- โมเดลคน blockout — ประกอบครั้งเดียว วางที่ (0, y, 0) แล้วประกาศ pivot ที่จุดแตะพื้น (0,0,0)
-- เพื่อให้ PivotTo(cframe) ในภายหลังย้ายทั้งก้อนโดยให้ "เท้า" ไปอยู่ตรง cframe เป๊ะ
-- (ไม่ใช่ default pivot ที่อิง PrimaryPart ซึ่งจะเอาลำตัวไปวางตรงจุดนั้นแทน แล้วขาจมพื้น)
--------------------------------------------------------------------------------

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
		p.CastShadow = false -- ⚠️ สูงสุด ~240 ตัวต่อคน × 6 ชิ้น/ตัว — ปิดเงากันภาระเรนเดอร์
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
	head.Shape = Enum.PartType.Ball -- ⚠️ Shape=Ball ต้องตั้งขนาดเท่ากันทั้งสามแกน (กฎเดียวกับไข่)

	part("ArmL", LIMB_SIZE, -(TORSO_SIZE.X / 2 + LIMB_SIZE.X / 2), TORSO_CENTER_Y)
	part("ArmR", LIMB_SIZE, TORSO_SIZE.X / 2 + LIMB_SIZE.X / 2, TORSO_CENTER_Y)
	part("LegL", LIMB_SIZE, -LIMB_SIZE.X / 2, LEG_CENTER_Y)
	part("LegR", LIMB_SIZE, LIMB_SIZE.X / 2, LEG_CENTER_Y)

	-- ประกาศ pivot ที่จุดแตะพื้น (world origin ตอนสร้าง = (0,0,0)) โดยไม่ขยับชิ้นไหนเลย
	model.WorldPivot = CFrame.new(0, 0, 0)

	return model
end

--------------------------------------------------------------------------------
-- ด่านที่กำลังตี → ตำแหน่ง X เป้าหมาย (กำแพง หรือปลายช่วงด่านถ้าด่านนั้นไม่มีกำแพง เช่นด่าน 1)
--------------------------------------------------------------------------------

local function getStageTargetX(stage: number): number
	local wallX = Config.getWallX(stage)
	if wallX then
		return wallX
	end
	return Config.getStageStartX(stage) + MAP.Lane.LengthPerStage
end

--------------------------------------------------------------------------------
-- ทหารฝ่ายเรา — สปอนที่จุดปล่อย เดินเข้าไปหาด่านที่กำลังตี
--
-- ⚠️ ถ้ามีทหารฝ่ายรับ "ยืนรอ" อยู่ (idle ใน defenderModels) ตอนสปอน จะดึงมาเดินออกมาพบกันกึ่งกลาง
-- เลนแทนที่จะเดินยาวไปกำแพงตรง ๆ — ทั้งคู่หายไปตอนถึงจุดชน (ดูรายละเอียดที่ spawnOurTroop
-- และ updateOurTroops) ถ้าไม่มีทหารฝ่ายรับเหลือให้ดึง (targetCount = 0 หรือดึงไปหมดแล้วชั่วคราว)
-- เดินยาวไปกำแพงเลยเหมือน 3B-1 เดิม ไม่มีอะไรผิดปกติ — เป็นพฤติกรรมที่ตั้งใจ
--------------------------------------------------------------------------------

type OurTroop = {
	model: Model,
	from: Vector3,
	to: Vector3,
	spawnedAt: number, -- os.clock()
	-- ⚠️ ทหารฝ่ายรับที่ถูกดึงมาเดินออกมาชนคู่กับทหารตัวนี้ (nil = ไม่มีคู่ เดินยาวไปกำแพงเลย)
	-- เดิน/หายไปพร้อมกันโดยใช้ alpha เดียวกับทหารเรา (ดู updateOurTroops) ไม่ต้องมี array
	-- ติดตามแยกต่างหาก
	pairedDefender: Model?,
	defenderFrom: Vector3?, -- ตำแหน่งยืนเดิมของ pairedDefender ก่อนถูกดึงออกมาเดิน
}

local ourTroops: { OurTroop } = {}
local spawnCarry = 0

-- ⚠️ ประกาศล่วงหน้าตรงนี้ (แทนที่จะประกาศในหัวข้อ "ทหารฝ่ายรับ" ข้างล่างเหมือนเดิม) เพราะ
-- spawnOurTroop ต้องดึงโมเดลจากพูลนี้มาจับคู่เดินออกมาชน — รายละเอียดวิธีใช้อยู่ในหัวข้อ
-- "ทหารฝ่ายรับ" ตามเดิม ย้ายมาแค่จุดประกาศตัวแปรเท่านั้น
local defenderModels: { Model } = {}
local lastDefenderStage: number? = nil

local function totalStockpile(payload: any): number
	local total = 0
	for _, stack in payload.children do
		total += stack.count
	end
	return total
end

local function spawnOurTroop(stage: number)
	local oursFolder = ensureSubFolder("Ours")

	local startX = Config.getLaneStartX() + MAP.Lane.ReleasePadSize.X / 2
	-- ⚠️ เว้นขอบจากผนังเลนทั้งสองข้างกันโมเดลโผล่ทะลุกำแพงข้างเลน
	local laneHalf = math.max(MAP.Lane.Width / 2 - 6, 1)
	local z = (math.random() * 2 - 1) * laneHalf

	local wallX = getStageTargetX(stage)
	local from = Vector3.new(startX, 0, z)
	local to = Vector3.new(wallX, 0, z)

	-- ⚠️ ดึงทหารฝ่ายรับที่ยืนรออยู่ (ถ้ามี) ออกจากพูล defenderModels มาเดินออกมาชนกึ่งกลางเลน
	-- — ดึงออกจากพูลเดิม ไม่ใช่สร้างเพิ่ม ไม่งั้นจำนวนที่โชว์รวมกันจะเกินสัดส่วน defendersRemaining
	-- จริง พูลที่พร่องไปจะถูกเติมกลับเองในรอบ sync ถัดไปถ้า targetCount ยังไม่ถึง 0 (updateDefenders)
	local pairedDefender: Model? = nil
	local defenderFrom: Vector3? = nil
	if #defenderModels > 0 then
		local defenderModel = table.remove(defenderModels)
		if defenderModel then
			pairedDefender = defenderModel
			defenderFrom = defenderModel:GetPivot().Position
			-- ⚠️ จุด "ชนกัน" กึ่งกลางระหว่าง release pad กับกำแพงด่านที่กำลังตี — ปรับตามความยาว
			-- เลนจริงของด่านนั้นเองเพราะ wallX เปลี่ยนไปตามด่าน (ด่าน 2 ใกล้กว่าด่าน 9 มาก)
			to = Vector3.new((startX + wallX) / 2, 0, z)
		end
	end

	local model = buildPersonModel(OUR_COLOR, "Troop")
	model.Parent = oursFolder
	model:PivotTo(CFrame.new(from))

	table.insert(ourTroops, {
		model = model,
		from = from,
		to = to,
		spawnedAt = os.clock(),
		pairedDefender = pairedDefender,
		defenderFrom = defenderFrom,
	})
end

-- ⚠️ ถึงจุดชน (หรือถึงกำแพงถ้าไม่มีคู่) แล้วทำลาย pairedDefender ไปด้วยเงียบ ๆ ไม่มี burst —
-- จำลองว่าปะทะกันตาย ต่างจาก pattern เดิมใน 3B-2 (CombatEffects.onDefenderDeath) ที่ใช้กับกรณี
-- defendersRemaining ลดจริงจาก sync เท่านั้น ไม่ใช่กรณีจำลองการชนแบบ visual ล้วน ๆ นี้
local function destroyTroopPair(troop: OurTroop)
	troop.model:Destroy()
	if troop.pairedDefender and troop.pairedDefender.Parent then
		troop.pairedDefender:Destroy()
	end
end

local function updateOurTroops()
	local now = os.clock()
	for index = #ourTroops, 1, -1 do
		local troop = ourTroops[index]
		if troop.model.Parent == nil then
			if troop.pairedDefender and troop.pairedDefender.Parent then
				troop.pairedDefender:Destroy()
			end
			table.remove(ourTroops, index)
			continue
		end

		local alpha = (now - troop.spawnedAt) / WALK_SECONDS
		if alpha >= 1 then
			destroyTroopPair(troop)
			table.remove(ourTroops, index)
		else
			local position = troop.from:Lerp(troop.to, alpha)
			local direction = troop.to - troop.from
			local cf = if direction.Magnitude > 0.01
				then CFrame.lookAt(position, position + direction.Unit)
				else CFrame.new(position)
			troop.model:PivotTo(cf)

			-- ⚠️ ใช้ alpha เดียวกับทหารเรา — เดินจากจุดยืนเดิมมาบรรจบที่จุดชนเดียวกันพอดี
			-- ทั้งสองฝั่งถึงพร้อมกันเป๊ะ (alpha=1 พร้อมกัน) โดยไม่ต้องเช็คระยะห่างจริงเลย
			if troop.pairedDefender and troop.defenderFrom and troop.pairedDefender.Parent then
				local defenderPosition = troop.defenderFrom:Lerp(troop.to, alpha)
				local defenderDirection = troop.to - troop.defenderFrom
				local defenderCf = if defenderDirection.Magnitude > 0.01
					then CFrame.lookAt(defenderPosition, defenderPosition + defenderDirection.Unit)
					else CFrame.new(defenderPosition)
				troop.pairedDefender:PivotTo(defenderCf)
			end
		end
	end
end

-- อัตราสปอน ≈ อัตราปล่อยจริงของด่าน (ไม่ต้องเป๊ะ — ดูคอมเมนต์หัวไฟล์) หยุดสปอนถ้า:
-- ปิดปุ่มอัญเชิญ · ไม่มีด่านให้ตี (ผ่านครบแล้ว) · คลังว่างเปล่า · โมเดลชนเพดาน MAX_VISIBLE_UNITS
local function updateSpawning(payload: any?, delta: number)
	if not payload then
		return
	end
	if not payload.summonEnabled then
		return
	end
	local stage = payload.activeStage
	if not stage then
		return
	end
	if totalStockpile(payload) <= 0 then
		return
	end

	local rate = Config.getReleaseRate(stage)
	spawnCarry += rate * delta
	while spawnCarry >= 1 do
		spawnCarry -= 1
		if #ourTroops < COMBAT.MAX_VISIBLE_UNITS then
			spawnOurTroop(stage)
		end
	end
end

--------------------------------------------------------------------------------
-- ทหารฝ่ายรับ — พูล "ยืนรอ" หน้ากำแพงด่านที่กำลังถูกตี จำนวนในพูลลดตามสัดส่วน defendersRemaining
--
-- ⚠️ ตัวที่ยืนรออยู่ในพูลนี้ (defenderModels — ประกาศไว้ก่อน spawnOurTroop ข้างบนแล้ว) อาจถูก
-- spawnOurTroop ดึงออกไปเดินออกมาชนกับทหารเราได้ตลอดเวลา (ดูหัวข้อ "ทหารฝ่ายเรา") จำนวนที่
-- พร่องไปจากการดึงจะถูกเติมกลับเองที่นี่ในรอบ sync ถัดไป ตราบใดที่ targetCount (คำนวณจาก
-- defendersRemaining จริง) ยังไม่ถึง 0 — ไม่ต้องมี logic พิเศษเพิ่มสำหรับกรณีนี้เลย
--------------------------------------------------------------------------------

local function defenderRatio(payload: any, stage: number): number
	local info = payload.stageProgress[stage]
	if type(info) ~= "table" or info.started ~= true then
		return 1 -- ยังไม่เคยแตะด่านนี้ = ทหารฝ่ายรับเต็มจำนวน
	end
	if info.defendersTotal <= 0 then
		return 0 -- ด่านที่ไม่มีทหารฝ่ายรับเลย (ด่าน 1)
	end
	return info.defendersRemaining / info.defendersTotal
end

local function updateDefenders(payload: any?)
	local stage = if payload then payload.activeStage else nil

	-- ด่านที่กำลังตีเปลี่ยนไป (หรือผ่านครบทุกด่านแล้ว) → เคลียร์ของเก่าทิ้งแล้ววางใหม่ทั้งชุด
	-- (ตำแหน่งผูกกับด่านเดิม ใช้ต่อกับด่านใหม่ไม่ได้) ระหว่างด่านเดิม ปรับแค่ "จำนวน" ไม่ขยับ
	-- ตัวที่เหลืออยู่แล้ว กันโมเดลกระโดดตำแหน่งทุกครั้งที่ sync มา (ทุก ~1 วิ)
	if stage ~= lastDefenderStage then
		for _, model in defenderModels do
			model:Destroy()
		end
		defenderModels = {}
		lastDefenderStage = stage
	end

	local targetCount = 0
	local targetX = 0
	if stage and payload then
		targetCount = math.min(Config.getDisplayModelCount(defenderRatio(payload, stage)), COMBAT.MAX_VISIBLE_UNITS)
		targetX = getStageTargetX(stage)
	end

	local deathEffectsPlayed = 0

	while #defenderModels > targetCount do
		local model = table.remove(defenderModels)
		if model then
			if deathEffectsPlayed < DEATH_EFFECT_CAP_PER_UPDATE then
				-- ⚠️ ตำแหน่งเดิมของโมเดลก่อนทำลาย — ต้องอ่านก่อน Destroy เสมอ
				CombatEffects.onDefenderDeath(model:GetPivot().Position)
				deathEffectsPlayed += 1
			end
			model:Destroy()
		end
	end

	if targetCount > #defenderModels then
		local defendersFolder = ensureSubFolder("Defenders")
		local laneHalf = math.max(Config.getLaneHalfWidthAt(targetX) - 4, 1)
		while #defenderModels < targetCount do
			local model = buildPersonModel(DEFENDER_COLOR, "Defender")
			model.Parent = defendersFolder
			local z = (math.random() * 2 - 1) * laneHalf
			local xJitter = math.random() * 10 - 5
			model:PivotTo(CFrame.new(targetX + xJitter, 0, z))
			table.insert(defenderModels, model)
		end
	end
end

--------------------------------------------------------------------------------
-- ต่อสาย
--------------------------------------------------------------------------------

local currentPayload: any = nil

-- ⚠️ เรียกทุกครั้งที่ FarmStateSync มาใหม่ (ดู Main.client.lua) — อัปเดตพูล "ยืนรอ" ของ
-- ทหารฝ่ายรับทันทีตามจำนวนล่าสุด (ตัวที่ถูกดึงไปเดินออกมาชนแล้วไม่ถูกแตะตรงนี้ — จบเองใน
-- updateOurTroops) ส่วนทหารฝ่ายเราใช้ payload นี้แค่ตัดสินว่าควรสปอนต่อไหม (ดู updateSpawning
-- ที่ทำงานในลูป Heartbeat แยกต่างหาก)
function TroopRenderer.updateFromPayload(payload: any)
	currentPayload = payload
	updateDefenders(payload)
end

function TroopRenderer.start()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	ensureFolder()

	RunService.Heartbeat:Connect(function(delta: number)
		updateSpawning(currentPayload, delta)
		updateOurTroops()
	end)
end

return TroopRenderer
