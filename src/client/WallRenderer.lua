--!strict
-- egg-army-game :: วาดกำแพงฝั่ง client
--
-- ⚠️ **กำแพงต้องวาดฝั่ง client เท่านั้น ห้ามสร้างบน server**
--
-- เหตุผล: ผู้เล่นทุกคนใช้ **เลนรบเส้นเดียวกัน** แต่แต่ละคนพังกำแพงมาถึงคนละด่าน
-- ถ้าสร้างกำแพงบน server จะมีกำแพงชุดเดียวให้ทุกคน ซึ่งแยกไม่ได้ว่าใครผ่านแล้วบ้าง
--
-- ผลพลอยได้ที่ **ตั้งใจ**: การชนก็แยกกันเองอัตโนมัติ
-- คนที่พังด่าน 3 แล้วเดินผ่านจุดนั้นได้ ส่วนคนที่ยังไม่พังเดินชน — ทั้งที่ยืนที่เดียวกัน
-- ไม่ต้องเขียนโค้ดเช็คสิทธิ์เพิ่มเลย เพราะ Part ฝั่ง client ชนเฉพาะเจ้าของเครื่อง
--
-- ⚠️ **ผลข้างเคียงที่ยอมรับแล้ว ไม่ต้องแก้**: จะเห็นคนอื่นเดินทะลุกำแพงที่ตัวเองยังพังไม่ได้
-- บันทึกไว้ใน docs/map-layout.md แล้ว
--
-- ══ Phase 3B-1 ══
-- ⚠️ เดิม (blockout) อ่าน wallProgress จาก Config.Balance.NewPlayer ค่าคงที่ ไม่เคยรับค่าจริง
-- จากเซิร์ฟเวอร์เลย — ตอนนี้รับ `stageProgress` จริงจาก FarmStateSync (CombatService 3A ใส่ไว้ใน
-- payload ผ่าน CombatService.buildSyncFields) ทุกครั้งที่ sync มาใหม่ ผ่าน setStageProgress()
-- (Main.client.lua เรียกจาก farmStateSync.OnClientEvent) ด่านที่ "พังเรียบร้อย"
-- (defendersRemaining=0 และ wallHpRemaining=0 → entry.cleared=true) กำแพงหายไป
--
-- ทหารฝ่ายรับกับกองทัพของผู้เล่นเองวาดฝั่ง client ด้วยเหตุผลเดียวกัน (เห็นเฉพาะของตัวเอง)
-- อยู่ที่ src/client/TroopRenderer.lua (Phase 3B-1)
--
-- ══ Phase 3B-2 ══
-- กำแพงที่ "ยังไม่พังเรียบร้อย" ตอนนี้แตกเป็น 5 ระดับตาม wallHpRemaining/wallHpTotal ที่เหลือ
-- (blockout: คล้ำสี + เพิ่มเส้นรอยร้าวทีละขั้น ไม่มีโมเดล/texture รอยร้าวจริง) รายละเอียดอยู่
-- ตรงตาราง WALL_TIER_* ด้านล่าง — อัปเดตเฉพาะด่านที่ข้าม threshold เท่านั้น ไม่ rebuild ทั้งชุด
-- ทุก sync อีกต่อไป (ประหยัด work ฝั่ง client)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local WallRenderer = {}

local MAP = Config.MapDimensions

local WALL_COLOR = Color3.fromRGB(126, 116, 104)
local WALL_TOP_COLOR = Color3.fromRGB(154, 142, 126)
local CRACK_COLOR = Color3.fromRGB(28, 24, 20)

-- ══ Phase 3B-2: กำแพงแตกตาม % HP ที่เหลือ (blockout — คล้ำสี + เส้นรอยร้าวเพิ่มทีละขั้น) ══
-- 5 ระดับตาม wallHpRemaining/wallHpTotal: 100-76% / 75-51% / 50-26% / 25-1% / 0% (หายไปเลย
-- เหมือนเดิม — ระดับ 0% ไม่มีโมเดลให้วาดต่อ จึงมีแค่ tier 1-4 ในตารางข้างล่าง)
local WALL_TIER_DARKEN = { [1] = 0, [2] = 0.2, [3] = 0.4, [4] = 0.6 } -- ยิ่งเลขมากยิ่งคล้ำ
local WALL_TIER_CRACKS = { [1] = 0, [2] = 2, [3] = 4, [4] = 6 } -- ยิ่ง HP น้อยยิ่งมีเส้นเยอะ

local function getWallTier(ratio: number): number
	if ratio > 0.75 then
		return 1
	elseif ratio > 0.50 then
		return 2
	elseif ratio > 0.25 then
		return 3
	else
		return 4
	end
end

-- สัดส่วน wallHpRemaining/wallHpTotal ของด่านนั้น — 1 (เต็ม) ถ้ายังไม่เคยแตะหรือข้อมูลไม่ครบ
local function getWallRatio(entry: any): number
	if type(entry) ~= "table" or entry.started ~= true then
		return 1
	end
	local total = entry.wallHpTotal
	if type(total) ~= "number" or total <= 0 then
		return 1
	end
	return math.clamp(entry.wallHpRemaining / total, 0, 1)
end

local folder: Folder? = nil

-- ⚠️ เก็บ "เลเวลที่วาดอยู่จริงตอนนี้" แยกจาก currentStageProgress (ค่าดิบจาก server)
-- ต่างกันเมื่อไหร่ค่อย rebuild โมเดลด่านนั้นจริง ๆ — เลเวลเดิมไม่ต้องแตะอะไรเลย (ประหยัด work
-- ฝั่ง client ตามที่สั่ง ไม่ใช่คำนวณ/สร้าง Part ใหม่ทุก sync) · nil = ไม่มีโมเดลอยู่ตอนนี้
local builtTier: { [number]: number? } = {}

-- ⚠️ ก่อน sync ครั้งแรกมาถึง ยังไม่รู้ค่าจริงจากเซิร์ฟ — สมมติว่ายังไม่พังด่านไหนเลย (ทุกด่าน
-- ยังเป็น false เหมือนผู้เล่นใหม่) ปลอดภัยกว่าสมมติว่าพังไปแล้ว: กำแพงเกินโผล่มาก่อนแล้วหายไป
-- ทีหลังตอน sync จริงมาถึง ดูดีกว่ากำแพงขาดหายไปก่อนแล้วโผล่ขึ้นมาทีหลัง
local currentStageProgress: { any } = {}
for stage = 1, Config.Balance.Stage.COUNT do
	currentStageProgress[stage] = false
end

-- ด่านนั้น "พังเรียบร้อย" ไหม จาก entry ที่ CombatService.buildSyncFields ส่งมาใน payload
-- ⚠️ entry เป็นได้สามแบบ: `false` ทั้งก้อน (ยังไม่เคยแตะ) · `{started = false}` (รูปแบบเดียวกัน
-- คนละที่มา) · `{started = true, cleared = boolean, ...}` (ค่าจริงจาก stageProgress ที่เริ่มแล้ว)
local function isStageCleared(entry: any): boolean
	if type(entry) ~= "table" then
		return false
	end
	if entry.started ~= true then
		return false
	end
	return entry.cleared == true
end

--------------------------------------------------------------------------------
-- วาด
--------------------------------------------------------------------------------

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end

	-- ⚠️ ต้องหา "LocalWalls" ที่มีอยู่แล้วใน Workspace ก่อนเสมอ ห้ามสร้างใหม่ตรง ๆ
	-- StarterPlayerScripts ถูก copy เป็น PlayerScripts ตอนเข้าเกม → มี ModuleScript
	-- WallRenderer อย่างน้อย 2 instance ที่ต่างคนต่างมี `folder`/`currentStageProgress` ของตัวเอง
	-- (ตัวต้นฉบับใน StarterPlayerScripts กับตัวที่ก็อปมาใน PlayerScripts ที่ Main.client.lua
	-- require จริง) ถ้า instance ไหนสร้างโฟลเดอร์ใหม่ทิ้งไว้โดยไม่เช็คของเดิมก่อน
	-- จะเกิดโฟลเดอร์ "LocalWalls" ซ้อนกันสองใบใน Workspace เดียวกัน — ใบที่ผู้เล่นยืนชนอยู่จริง
	-- (สร้างจาก instance ที่ Main.client.lua เรียกตอนบูต) ไม่ถูกแตะเลยแม้แต่นิดเดียว
	-- ต่อให้เรียก setWallProgress จาก instance ไหนก็ตาม (เช่น จาก command bar ที่ require
	-- ผ่านคนละ path) เพราะ Workspace เป็น service เดียวจริงของทั้งเกม การหาโฟลเดอร์เดิมด้วยชื่อ
	-- ทำให้ทุก instance ลงเอยที่ Part ชุดเดียวกันเสมอ
	local existing = Workspace:FindFirstChild("LocalWalls")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = "LocalWalls"
	-- อยู่ใน Workspace ของเครื่องนี้เท่านั้น server ไม่รู้จักและ replicate ไปหาใครไม่ได้
	created.Parent = Workspace
	folder = created
	return created
end

-- เส้นรอยร้าว — สุ่มตำแหน่งแต่ fix seed ด้วยเลขด่านเสมอ (Random.new(stage) สร้างใหม่ทุกครั้งที่
-- เรียก แต่ให้ลำดับเลขสุ่มเดิมเป๊ะเพราะ seed เดิม) เปิดเผยทีละ N เส้นตามเลเวล — เลข n ตัวแรก
-- จึงตรงกันทุกเลเวลเสมอ (เลเวลสูงขึ้นแค่ "เพิ่ม" เส้นต่อท้าย ไม่สลับตำแหน่งเส้นเดิมที่มีอยู่แล้ว)
-- → ไม่กระพริบ/ไม่เปลี่ยนตำแหน่งตอน sync ใหม่มาถึงตามที่สั่ง
local function addCracks(model: Model, stage: number, wallX: number, tier: number)
	local count = WALL_TIER_CRACKS[tier] or 0
	if count <= 0 then
		return
	end

	local rng = Random.new(stage)
	local faceX = wallX + MAP.StageWall.Thickness / 2 + 0.06
	local halfWidth = MAP.Lane.Width / 2

	for index = 1, count do
		local length = rng:NextNumber(3, 7)
		local y = rng:NextNumber(1, math.max(MAP.Lane.WallHeight - 1, 1))
		local z = rng:NextNumber(-halfWidth + 2, halfWidth - 2)
		local tilt = rng:NextNumber(-25, 25)

		local crack = Instance.new("Part")
		crack.Name = `Crack{index}`
		crack.Size = Vector3.new(0.18, length, 0.3)
		crack.CFrame = CFrame.new(faceX, y, z) * CFrame.Angles(0, 0, math.rad(tilt))
		crack.Color = CRACK_COLOR
		crack.Material = Enum.Material.SmoothPlastic
		crack.Anchored = true
		crack.CanCollide = false
		crack.CastShadow = false
		crack.Parent = model
	end
end

local function buildWall(stage: number, parent: Folder, tier: number)
	local wallX = Config.getWallX(stage)
	if not wallX then
		return -- ด่านนี้ไม่มีกำแพง (ด่าน 1)
	end

	local model = Instance.new("Model")
	model.Name = `Wall{stage}`
	model.Parent = parent

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(MAP.StageWall.Thickness, MAP.Lane.WallHeight, MAP.Lane.Width)
	body.Position = Vector3.new(wallX, MAP.Lane.WallHeight / 2, 0)
	-- ⚠️ Phase 3B-2: คล้ำลงทีละขั้นตามเลเวลความเสียหาย (tier 1 = สีเดิมเป๊ะ)
	body.Color = WALL_COLOR:Lerp(Color3.new(0, 0, 0), WALL_TIER_DARKEN[tier] or 0)
	body.Anchored = true
	body.CanCollide = true -- ← จุดที่ทำให้ "คนที่ยังไม่พังเดินชน" ทำงานเอง
	body.Material = Enum.Material.Slate
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model
	model.PrimaryPart = body

	addCracks(model, stage, wallX, tier)

	-- ขอบบน ไว้ให้ดูออกว่าเป็นกำแพง ไม่ใช่แค่แท่งทึบ
	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Size = Vector3.new(MAP.StageWall.Thickness + 1.5, 1, MAP.Lane.Width + 1.5)
	cap.Position = Vector3.new(wallX, MAP.Lane.WallHeight + 0.5, 0)
	cap.Color = WALL_TOP_COLOR
	cap.Anchored = true
	cap.CanCollide = true
	cap.Material = Enum.Material.Slate
	cap.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(200, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, MAP.Lane.WallHeight / 2 + 4, 0)
	gui.MaxDistance = 300
	gui.Adornee = body
	gui.Parent = body

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 226, 190)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Text = `กำแพงด่าน {stage}`
	label.Parent = gui
end

-- อัปเดตตาม stageProgress ปัจจุบัน — ⚠️ Phase 3B-2: **ไม่ ClearAllChildren + rebuild ทั้งชุดอีก
-- ต่อไปแล้ว** เทียบทีละด่านกับ `builtTier` (เลเวลที่วาดอยู่จริงตอนนี้) rebuild เฉพาะด่านที่
-- เลเวลเปลี่ยนจริง (ข้าม threshold ของ % HP หรือเพิ่ง cleared) ด่านที่ยังอยู่เลเวลเดิมข้ามไปเลย
-- ไม่แตะ Part สักชิ้น — ประหยัด work ฝั่ง client ตามที่สั่ง เพราะ sync มาถี่ (~ทุก 1 วิ)
-- แต่ % HP ส่วนใหญ่ไม่ได้ข้าม threshold ทุกรอบ
function WallRenderer.render()
	local parent = ensureFolder()
	local changed = 0

	for stage = 1, Config.Balance.Stage.COUNT do
		local modelName = `Wall{stage}`
		local existingModel = parent:FindFirstChild(modelName)
		local wallX = Config.getWallX(stage)

		if not wallX or isStageCleared(currentStageProgress[stage]) then
			-- ด่านนี้ไม่มีกำแพงจริง (ด่าน 1) หรือพังเรียบร้อยแล้ว → ต้องไม่มีโมเดล
			if builtTier[stage] ~= nil then
				if existingModel then
					existingModel:Destroy()
				end
				builtTier[stage] = nil
				changed += 1
			end
			continue
		end

		local ratio = getWallRatio(currentStageProgress[stage])
		local tier = getWallTier(ratio)

		if builtTier[stage] == tier and existingModel then
			continue -- ยังอยู่เลเวลเดิม ไม่ต้องแตะอะไรเลย
		end

		if existingModel then
			existingModel:Destroy()
		end
		buildWall(stage, parent, tier)
		builtTier[stage] = tier
		changed += 1
	end

	if changed > 0 then
		print(`[WallRenderer] อัปเดตกำแพง {changed} ด่าน (ข้าม threshold ความเสียหาย/พัง)`)
	end
end

-- ⚠️ เรียกทุกครั้งที่ FarmStateSync มาใหม่ (ดู Main.client.lua) — ของจริงจาก server
-- (CombatService 3A ผ่าน CombatService.buildSyncFields) ไม่ใช่ default อีกต่อไป
-- (เคยเป็นบั๊ก: currentProgress อ่านจาก Config.Balance.NewPlayer.wallProgress ค่าคงที่
-- ไม่เคยรับค่าจริงจากเซิร์ฟเวอร์เลย)
function WallRenderer.setStageProgress(stageProgress: { any })
	currentStageProgress = stageProgress
	WallRenderer.render()
end

function WallRenderer.getStageProgress(): { any }
	return currentStageProgress
end

--------------------------------------------------------------------------------
-- ค่าทดสอบ
--------------------------------------------------------------------------------

-- ⚠️ ของเทสต์เท่านั้น — จำลองว่า "พังกำแพงมาถึงด่าน n แล้ว" (ด่าน 1..n-1 พังหมด ที่เหลือยังเต็ม)
-- แปลงเป็นรูปแบบ stageProgress เดียวกับที่ server ส่งมาจริงแล้วเรียก setStageProgress ต่อ
-- ตัวนี้เปลี่ยนแค่สิ่งที่ "เห็นและชน" บนเครื่องนี้ ไม่ได้ให้สิทธิ์อะไรเพิ่มจริง เพราะการตีกำแพง
-- และการให้รางวัลคำนวณฝั่ง server ทั้งหมด (CombatService) — sync รอบถัดไปจะเขียนทับค่านี้เสมอ
function WallRenderer.setWallProgress(value: number)
	local clamped = math.clamp(math.floor(value), 1, Config.Balance.Stage.COUNT)
	local fake = {}
	for stage = 1, Config.Balance.Stage.COUNT do
		fake[stage] = if stage < clamped then { started = true, cleared = true } else { started = false }
	end
	WallRenderer.setStageProgress(fake)
end

function WallRenderer.start()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	WallRenderer.render()
end

return WallRenderer
