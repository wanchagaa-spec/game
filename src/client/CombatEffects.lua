--!strict
-- egg-army-game :: เอฟเฟกต์การรบฝั่ง client (Phase 3B-2) — เลขความเสียหายลอย + burst ตอนกระทบ/ตาย
--
-- ⚠️ client-only visual ล้วน ๆ ไม่กระทบกติกาเกมแม้แต่นิดเดียว — CombatService (3A) ยังคง
-- คำนวณ damage เป็นก้อนรวมต่อ sync tick เหมือนเดิมทุกประการ ไฟล์นี้แค่ "แปลผลต่าง" ระหว่างสอง
-- sync ให้เห็นเป็นภาพ — ไม่มี event "ทหารตัวไหนตีตอนไหน" จาก server จริง ๆ (เหตุผลเดียวกับที่
-- อธิบายไว้หัว TroopRenderer.lua) เลขลอยที่เห็นจึงเป็น **ก้อนรวมต่อรอบ sync** ไม่ใช่เลขแยก
-- ต่อทหารแต่ละตัว
--
-- ใช้จาก:
--   Main.client.lua  → CombatEffects.onSync(payload) ทุกครั้งที่ FarmStateSync มาใหม่
--                       (เทียบ defendersRemaining/wallHpRemaining ของ "ด่านที่กำลังตี" เท่านั้น)
--   TroopRenderer.lua → CombatEffects.onDefenderDeath(position) ตอนโมเดลทหารฝ่ายรับถูกทำลาย
--                       (แทนที่จะ pop หายเฉย ๆ)

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local CombatEffects = {}

local MAP = Config.MapDimensions

local DEFENDER_HIT_COLOR = Color3.fromRGB(255, 140, 60) -- ส้ม: ตี "ทหารฝ่ายรับ"
local WALL_HIT_COLOR = Color3.fromRGB(255, 90, 90) -- แดง: ตี "กำแพง"
local DEATH_EFFECT_COLOR = Color3.fromRGB(210, 70, 70)

local FLOAT_DURATION = 0.9 -- วินาที ก่อนเลขลอยจางหายหมด
local FLOAT_RISE = 4 -- studs ที่เลขลอยขึ้นตลอดช่วง FLOAT_DURATION
local BURST_LIFETIME = 0.6 -- วินาทีก่อน anchor ของ burst ถูกทำลาย (เผื่อเวลาให้อนุภาคจางหมดจริง)

--------------------------------------------------------------------------------
-- ย่อเลขสไตล์เดียวกับ Config.formatWeight (K/M/B) — กันตัวเลขความเสียหายรกจอตอน sync ถี่
-- แต่ damage ต่อรอบน้อย (ใช้ style เดียวกับที่มีอยู่แล้วในโปรเจกต์ตามที่สั่ง ไม่ทำสูตรย่อใหม่)
--------------------------------------------------------------------------------
local function formatDamage(amount: number): string
	return Config.formatWeight(amount)
end

--------------------------------------------------------------------------------
-- anchor ใช้ร่วมกันทั้งเลขลอยและ burst — Part เล็กจิ๋วมองไม่เห็น ทำลายตัวเองสั้น ๆ เสมอ
--------------------------------------------------------------------------------
local function makeAnchor(position: Vector3): Part
	local anchor = Instance.new("Part")
	anchor.Name = "CombatEffectAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	return anchor
end

--------------------------------------------------------------------------------
-- เลขลอย — BillboardGui ธรรมดา ลอยขึ้น + จางหาย แล้วทำลายตัวเอง (เบามาก ไม่มี state ค้าง)
--------------------------------------------------------------------------------
function CombatEffects.floatingText(position: Vector3, text: string, color: Color3)
	local anchor = makeAnchor(position)

	local baseOffset = Vector3.new(math.random() * 2 - 1, 2, math.random() * 2 - 1)

	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatingDamage"
	gui.Size = UDim2.fromOffset(160, 44)
	gui.StudsOffsetWorldSpace = baseOffset
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	gui.Adornee = anchor
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui

	local riseTween = TweenService:Create(
		gui,
		TweenInfo.new(FLOAT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = baseOffset + Vector3.new(0, FLOAT_RISE, 0) }
	)
	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(FLOAT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	riseTween:Play()
	fadeTween:Play()

	Debris:AddItem(anchor, FLOAT_DURATION + 0.1)
end

--------------------------------------------------------------------------------
-- burst — ParticleEmitter มาตรฐานของ Roblox ยิงครั้งเดียวด้วย :Emit() (Rate=0 กันปล่อยต่อเนื่อง)
-- แล้วทำลาย anchor ทิ้งสั้น ๆ เสมอ กันเอฟเฟกต์ค้างจอตอนตีถี่ ๆ ต่อเนื่องยาว
--------------------------------------------------------------------------------
function CombatEffects.burst(position: Vector3, color: Color3)
	local anchor = makeAnchor(position)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.2, 0.35)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0 -- ยิงเองด้วย :Emit() เท่านั้น ไม่ปล่อยต่อเนื่องเป็นสาย
	emitter.Parent = anchor

	emitter:Emit(10)

	Debris:AddItem(anchor, BURST_LIFETIME)
end

function CombatEffects.onDefenderDeath(position: Vector3)
	CombatEffects.burst(position, DEATH_EFFECT_COLOR)
end

--------------------------------------------------------------------------------
-- ติดตามผลต่างระหว่างสอง sync ของ "ด่านที่กำลังตี" เท่านั้น (ตามที่สั่ง — ไม่ใช่ทุกด่านที่เคยแตะ)
--------------------------------------------------------------------------------

local lastStage: number? = nil
local lastDefendersRemaining: number? = nil
local lastWallHpRemaining: number? = nil

-- ตำแหน่งเอฟเฟกต์ "ตีทหารฝ่ายรับ" — หน้ากำแพงเล็กน้อย (ฝั่งทหารยืนอยู่จริงตาม TroopRenderer)
local function getDefenderEffectPosition(stage: number): Vector3
	local x = Config.getWallX(stage) or (Config.getStageStartX(stage) + MAP.Lane.LengthPerStage)
	local laneHalf = math.max(Config.getLaneHalfWidthAt(x) - 4, 1)
	local z = (math.random() * 2 - 1) * laneHalf
	return Vector3.new(x - 6, MAP.Lane.WallHeight * 0.35, z)
end

-- ตำแหน่งเอฟเฟกต์ "ตีกำแพง" — nil เมื่อด่านนั้นไม่มีกำแพงจริง (ด่าน 1)
local function getWallEffectPosition(stage: number): Vector3?
	local x = Config.getWallX(stage)
	if not x then
		return nil
	end
	local laneHalf = math.max(Config.getLaneHalfWidthAt(x) - 4, 1)
	local z = (math.random() * 2 - 1) * laneHalf
	return Vector3.new(x, MAP.Lane.WallHeight * 0.5, z)
end

-- ⚠️ เรียกทุกครั้งที่ FarmStateSync มาใหม่ (Main.client.lua) — เทียบค่าล่าสุดกับรอบก่อนหน้า
-- เฉพาะของ payload.activeStage เท่านั้น ด่านอื่นไม่ต้องสนใจ (ไม่ได้กำลังถูกตีอยู่)
function CombatEffects.onSync(payload: any)
	local stage = payload.activeStage
	local info = if stage then payload.stageProgress[stage] else nil
	local hasInfo = type(info) == "table" and info.started == true

	if stage ~= lastStage then
		-- ด่านที่กำลังตีเปลี่ยนไป (พังด่านเก่าแล้ว หรือผ่านครบทุกด่าน) — ตั้งฐานใหม่เงียบ ๆ
		-- ไม่โชว์เลขลอย เพราะค่าของด่านเก่ากับด่านใหม่คนละสเกลกัน เทียบตรง ๆ จะได้เลขมั่ว
		lastStage = stage
		lastDefendersRemaining = if hasInfo then info.defendersRemaining else nil
		lastWallHpRemaining = if hasInfo then info.wallHpRemaining else nil
		return
	end

	if not hasInfo then
		return
	end

	if lastDefendersRemaining and info.defendersRemaining < lastDefendersRemaining then
		local dealt = lastDefendersRemaining - info.defendersRemaining
		local pos = getDefenderEffectPosition(stage :: number)
		CombatEffects.floatingText(pos, `-{formatDamage(dealt)}`, DEFENDER_HIT_COLOR)
		CombatEffects.burst(pos, DEFENDER_HIT_COLOR)
	end

	if lastWallHpRemaining and info.wallHpRemaining < lastWallHpRemaining then
		local dealt = lastWallHpRemaining - info.wallHpRemaining
		local pos = getWallEffectPosition(stage :: number)
		if pos then
			CombatEffects.floatingText(pos, `-{formatDamage(dealt)}`, WALL_HIT_COLOR)
			CombatEffects.burst(pos, WALL_HIT_COLOR)
		end
	end

	lastDefendersRemaining = info.defendersRemaining
	lastWallHpRemaining = info.wallHpRemaining
end

return CombatEffects
