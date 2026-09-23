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
-- (defendersRemaining=0 และ wallHpRemaining=0 → entry.cleared=true) กำแพงหายไป ด่านที่ยังไม่ผ่าน
-- กำแพงยังเต็ม (ยังไม่ทำรอยร้าวตาม % ในเฟสนี้ — เป็น 3B-2)
--
-- ทหารฝ่ายรับกับกองทัพของผู้เล่นเองวาดฝั่ง client ด้วยเหตุผลเดียวกัน (เห็นเฉพาะของตัวเอง)
-- อยู่ที่ src/client/TroopRenderer.lua (Phase 3B-1)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local WallRenderer = {}

local MAP = Config.MapDimensions

local WALL_COLOR = Color3.fromRGB(126, 116, 104)
local WALL_TOP_COLOR = Color3.fromRGB(154, 142, 126)

local folder: Folder? = nil

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

local function buildWall(stage: number, parent: Folder)
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
	body.Color = WALL_COLOR
	body.Anchored = true
	body.CanCollide = true -- ← จุดที่ทำให้ "คนที่ยังไม่พังเดินชน" ทำงานเอง
	body.Material = Enum.Material.Slate
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model
	model.PrimaryPart = body

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

-- วาดใหม่ทั้งชุดตาม stageProgress ปัจจุบัน
-- กำแพงของด่านที่ **ยังไม่พังเรียบร้อย** เท่านั้นที่ต้องมี ด่านที่พังแล้วไม่ต้องวาด
function WallRenderer.render()
	local parent = ensureFolder()
	parent:ClearAllChildren()

	local built = 0
	for stage = 1, Config.Balance.Stage.COUNT do
		if not isStageCleared(currentStageProgress[stage]) then
			buildWall(stage, parent)
			built += 1
		end
	end

	print(`[WallRenderer] วาดกำแพง {built} ด่าน (ที่ยังพังไม่ได้)`)
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
