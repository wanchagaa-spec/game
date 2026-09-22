--!strict
-- egg-army-game :: Client entry point
--
-- Phase 1.5: แผงเทสต์เท่านั้น ยังไม่ใช่ UI จริง
-- UI จริง (สองแถบแม่/ลูก + กล่องยืนยัน + % ความคืบหน้า) อยู่ Phase 3
--
-- ⚠️ **ไม่มีปุ่มวางไข่แล้ว** — ไข่ซื้อ/สร้างเองไม่ได้ ต้องแย่งจากบอส (Phase 5)
-- ระหว่างที่ยังไม่มีบอส ใช้คำสั่งฝั่ง server ใน command bar แจกไข่เพื่อทดสอบ:
--     require(game.ServerScriptService.EggService).grantEgg(game.Players.<ชื่อ>, "egg_stage1")
--
-- client ไม่ตัดสินอะไรเองเลย: กดปุ่ม = ส่งคำขอไป server แล้วรอฟังผลกลับมา
-- เวลาที่เห็นบนจอเป็นแค่ค่าที่ server ส่งมา ไม่ได้นับเอง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
-- ⚠️ ใช้ WaitForChild ไม่ใช่ `script.Parent.WallRenderer` ตรง ๆ
-- StarterPlayerScripts ถูก copy ไปเป็น PlayerScripts ตอนผู้เล่นเข้าเกม
-- และของข้างในไม่ได้มาถึงพร้อมกันเสมอ — สคริปต์นี้เริ่มทำงานได้ก่อนพี่น้องของมันจะมาครบ
-- อ้างตรง ๆ แล้วเจอจังหวะนั้น = client พังตั้งแต่บรรทัดแรก UI ไม่ขึ้นเลยสักอย่าง
local WallRenderer = require(script.Parent:WaitForChild("WallRenderer"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local placeEggRequest = Remotes.waitFor(Config.RemoteNames.PLACE_EGG_IN_HATCHERY_REQUEST)
local moveMotherRequest = Remotes.waitFor(Config.RemoteNames.MOVE_MOTHER_REQUEST)
local eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
local farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)

--------------------------------------------------------------------------------
-- สร้าง UI
--------------------------------------------------------------------------------

-- ⚠️ Phase 1.5–2B: ยังเป็นแผงเทสต์ ไม่ใช่ UI จริง (Phase 3 ค่อยทำ UI จริงแบบมีไอคอนสัตว์)
-- แต่ต้อง "ใช้งานได้จริงระหว่างทดสอบ" — ย่อ/ขยายได้ + รายการ scroll ได้ + ไม่บังจอเกิน ~40%
-- (เคยเป็นกล่องข้อความเต็มจอความสูงคงที่ พอแม่/ไข่เยอะขึ้นบังแมพจนมองไม่เห็นอะไรเลย)

local BG = Color3.fromRGB(28, 30, 36)
local FG = Color3.fromRGB(240, 240, 240)
local DIM = Color3.fromRGB(160, 165, 175)
local ACCENT = Color3.fromRGB(90, 160, 235)

local HEADER_HEIGHT = 36
local TAB_BAR_HEIGHT = 32
local ACTION_BUTTON_HEIGHT = 30
local RESULT_HEIGHT = 32
local BODY_GAP = 6
-- ⚠️ ผลรวมความสูงของทุกอย่างใน body ยกเว้น gridScroll — ใช้คำนวณ gridScroll.Size ตรง ๆ
-- แทน UIFlexItem (FlexMode=Fill) ที่เคยใช้ — บนไคลเอนต์จริงบางเครื่องมันไม่ทำงาน
-- แล้ว gridScroll ตกกลับไปใช้ fallback Size เต็ม 100% ซ้อนทับพี่น้องตัวอื่นจน body ล้นทะลุแผง
local FIXED_STACK_HEIGHT = TAB_BAR_HEIGHT + ACTION_BUTTON_HEIGHT + RESULT_HEIGHT + BODY_GAP * 3

local gui = Instance.new("ScreenGui")
gui.Name = "EggFarmDebugUI"
gui.ResetOnSpawn = false
-- ⚠️ true เคยทำให้แผงวาดทับ/อยู่ใต้ไอคอนระบบของ Roblox บนแถบบนสุด (report/chat/mic ฯลฯ)
-- ซ่อนแถบหัวไปครึ่งหนึ่งจนกดปุ่มย่อ/ขยายไม่โดน — false ให้ Roblox เว้น inset ให้เองอัตโนมัติ
gui.IgnoreGuiInset = false
gui.Parent = playerGui

-- ⚠️ ขนาดเป็น scale ไม่ใช่ pixel ตายตัว — กันแผงบังจอเกิน ~40% บนมือถือจอเล็ก
-- UISizeConstraint คุมอีกชั้นกันจอใหญ่มาก (4K/ultrawide) ไม่ให้แผงขยายใหญ่เกินเหตุ
-- ⚠️ MinSize.Y ตั้งต่ำมาก (แค่กันค่าติดลบ) ไม่ใช่ 200+ เพราะตอนย่อแผงเหลือแค่แถบหัว (HEADER_HEIGHT)
-- ถ้าตั้ง MinSize.Y สูงกว่านั้น UISizeConstraint จะดันความสูงตอนย่อกลับขึ้นมาเอง ย่อไม่ได้จริง
local EXPANDED_SIZE = UDim2.fromScale(0.36, 0.4)
local COLLAPSED_SIZE = UDim2.new(0.36, 0, 0, HEADER_HEIGHT)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = EXPANDED_SIZE
panel.Position = UDim2.new(0, 16, 0, 16)
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(220, 4)
sizeConstraint.MaxSize = Vector2.new(420, 560)
sizeConstraint.Parent = panel

-- ⚠️ กันเนื้อหาล้นออกนอกกรอบแผง (เคยเกิดจริง — ดูคอมเมนต์ FIXED_STACK_HEIGHT ด้านบน)
panel.ClipsDescendants = true

--------------------------------------------------------------------------------
-- แถบหัว: ชื่อ + ปุ่มย่อ/ขยาย (กดแล้วเหลือแค่แถบนี้ ไม่บังจอ)
--------------------------------------------------------------------------------

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
header.BackgroundTransparency = 1
header.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.TextColor3 = FG
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextTruncate = Enum.TextTruncate.AtEnd
title.TextSize = 16
title.Font = Enum.Font.SourceSansBold
title.Text = "ฟาร์มไข่ (เทสต์)"
title.Parent = header

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "Toggle"
toggleButton.Size = UDim2.new(0, 28, 0, 28)
toggleButton.Position = UDim2.new(1, -34, 0.5, -14)
toggleButton.BackgroundColor3 = ACCENT
toggleButton.BorderSizePixel = 0
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextSize = 16
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.Text = "▾"
toggleButton.AutoButtonColor = true
toggleButton.Parent = header

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggleButton

--------------------------------------------------------------------------------
-- ตัวแผง: ปุ่มคำสั่ง + ลิสต์ scroll ได้ + ผลล่าสุด — ซ่อนได้ทั้งก้อนตอนย่อ
--------------------------------------------------------------------------------

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.new(0, 0, 0, HEADER_HEIGHT)
body.Size = UDim2.new(1, 0, 1, -HEADER_HEIGHT)
body.BackgroundTransparency = 1
body.Parent = panel

local bodyPadding = Instance.new("UIPadding")
bodyPadding.PaddingLeft = UDim.new(0, 10)
bodyPadding.PaddingRight = UDim.new(0, 10)
bodyPadding.PaddingBottom = UDim.new(0, 10)
bodyPadding.Parent = body

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.Padding = UDim.new(0, 6)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Parent = body

local function makeButton(name: string, order: number, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, ACTION_BUTTON_HEIGHT)
	button.BackgroundColor3 = ACCENT
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 14
	button.Font = Enum.Font.SourceSansBold
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = body

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button

	return button
end

--------------------------------------------------------------------------------
-- แถบแท็บ: แม่ / ไข่ — เลือกดูรายตัว/รายฟองแยกกันคนละแท็บ
--------------------------------------------------------------------------------

local TAB_ACTIVE_COLOR = ACCENT
local TAB_INACTIVE_COLOR = Color3.fromRGB(50, 54, 62)

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.LayoutOrder = 1
tabBar.Size = UDim2.new(1, 0, 0, TAB_BAR_HEIGHT)
tabBar.BackgroundTransparency = 1
tabBar.Parent = body

local tabBarLayout = Instance.new("UIListLayout")
tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
tabBarLayout.Padding = UDim.new(0, 6)
tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabBarLayout.Parent = tabBar

local function makeTabButton(name: string, order: number, text: string): TextButton
	local tabButton = Instance.new("TextButton")
	tabButton.Name = name
	tabButton.LayoutOrder = order
	-- ⚠️ -3/-3 หักกันพอดีกับ Padding=6 ของ tabBarLayout ให้ปุ่มสองอันเต็มความกว้าง tabBar
	-- ไม่เหลือ/ไม่ขาด (เลขคงที่ ผูกกับ Padding ด้านบน ถ้าแก้ Padding ต้องแก้คู่กัน)
	tabButton.Size = UDim2.new(0.5, -3, 1, 0)
	tabButton.BackgroundColor3 = TAB_INACTIVE_COLOR
	tabButton.BorderSizePixel = 0
	tabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	tabButton.TextSize = 14
	tabButton.Font = Enum.Font.SourceSansBold
	tabButton.Text = text
	tabButton.AutoButtonColor = true
	tabButton.Parent = tabBar

	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 6)
	tabCorner.Parent = tabButton

	return tabButton
end

local motherTabButton = makeTabButton("MotherTab", 1, "แม่")
local eggTabButton = makeTabButton("EggTab", 2, "ไข่")

local actionButton = makeButton("Action", 2, "กำลังโหลด...")

local DISABLED_ACTION_COLOR = Color3.fromRGB(70, 74, 82)

local function setActionButton(text: string, enabled: boolean)
	actionButton.Text = text
	actionButton.Active = enabled
	actionButton.AutoButtonColor = enabled
	actionButton.BackgroundColor3 = if enabled then ACCENT else DISABLED_ACTION_COLOR
end

-- ⚠️ กริดของแม่/ไข่ (ไข่ในกระเป๋า/สวนฟัก/คอก/กระเป๋าแม่) รวมอยู่ใน ScrollingFrame เดียวต่อแท็บ
-- แทนที่จะแยกกล่อง scroll ซ้อนกันหลายอัน (scroll ซ้อน scroll ใช้งานสับสน เลื่อนผิดกล่อง)
-- ⚠️ Size คำนวณจาก FIXED_STACK_HEIGHT ตรง ๆ (ดูคอมเมนต์ตอนประกาศค่าคงที่ด้านบนของไฟล์)
-- ไม่ใช้ UIFlexItem อีกต่อไป เพราะมันคือสาเหตุที่เนื้อหาเคยล้นทะลุแผงจริงในเกม
local gridScroll = Instance.new("ScrollingFrame")
gridScroll.Name = "Grid"
gridScroll.LayoutOrder = 3
gridScroll.Size = UDim2.new(1, 0, 1, -FIXED_STACK_HEIGHT)
gridScroll.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
gridScroll.BackgroundTransparency = 0.2
gridScroll.BorderSizePixel = 0
gridScroll.ScrollBarThickness = 6
gridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
gridScroll.Parent = body

local gridCorner = Instance.new("UICorner")
gridCorner.CornerRadius = UDim.new(0, 6)
gridCorner.Parent = gridScroll

local gridPadding = Instance.new("UIPadding")
gridPadding.PaddingTop = UDim.new(0, 4)
gridPadding.PaddingBottom = UDim.new(0, 4)
gridPadding.PaddingLeft = UDim.new(0, 6)
gridPadding.PaddingRight = UDim.new(0, 6)
gridPadding.Parent = gridScroll

local gridLayout = Instance.new("UIListLayout")
gridLayout.Padding = UDim.new(0, 4)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = gridScroll

local resultLabel = Instance.new("TextLabel")
resultLabel.Name = "Result"
resultLabel.LayoutOrder = 4
resultLabel.Size = UDim2.new(1, 0, 0, RESULT_HEIGHT)
resultLabel.BackgroundTransparency = 1
resultLabel.TextColor3 = DIM
resultLabel.TextXAlignment = Enum.TextXAlignment.Left
resultLabel.TextYAlignment = Enum.TextYAlignment.Top
resultLabel.TextWrapped = true
resultLabel.TextSize = 13
resultLabel.Font = Enum.Font.SourceSans
resultLabel.Text = "ยังไม่ได้ฟักอะไร"
resultLabel.Parent = body

--------------------------------------------------------------------------------
-- ย่อ/ขยายแผง
--------------------------------------------------------------------------------

local collapsed = false

local function applyCollapsedState()
	body.Visible = not collapsed
	panel.Size = if collapsed then COLLAPSED_SIZE else EXPANDED_SIZE
	toggleButton.Text = if collapsed then "▸" else "▾"
end

toggleButton.Activated:Connect(applyCollapsedState)

--------------------------------------------------------------------------------
-- การ์ดในกริด — สีตามคลาส (ชุดเดียวกับ PenService ที่วาดแม่ในโลกจริง เพื่อให้ตรงกัน)
--------------------------------------------------------------------------------

local CLASS_COLORS: { [string]: Color3 } = {
	SS = Color3.fromRGB(240, 185, 60),
	S = Color3.fromRGB(190, 110, 235),
	A = Color3.fromRGB(230, 110, 90),
	B = Color3.fromRGB(120, 215, 180),
	C = Color3.fromRGB(200, 200, 190),
}

local EGG_CARD_COLOR = Color3.fromRGB(210, 205, 190)

local CARD_SIZE = 72
local CARD_GAP = 6

type CardSpec = {
	title: string,
	subtitle: string,
	color: Color3,
	selected: boolean,
	onClick: () -> (),
}

local function createCard(spec: CardSpec, parent: Instance, layoutOrder: number): TextButton
	local card = Instance.new("TextButton")
	card.Name = "Card"
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.new(0, CARD_SIZE, 0, CARD_SIZE)
	card.BackgroundColor3 = spec.color
	card.BorderSizePixel = 0
	card.AutoButtonColor = true
	card.Text = ""
	card.Parent = parent

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 6)
	cardCorner.Parent = card

	if spec.selected then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 2
		stroke.Parent = card
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -6, 1, -6)
	label.Position = UDim2.new(0, 3, 0, 3)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(30, 30, 30)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.Text = `{spec.title}\n{spec.subtitle}`
	label.Parent = card

	-- ⚠️ TextScaled ทำให้ตัวอักษรโตได้ไม่จำกัด (ชื่อสั้น) — ล็อกเพดานไว้กันตัวใหญ่เกินการ์ด
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 14
	textConstraint.Parent = label

	card.Activated:Connect(spec.onClick)

	return card
end

local rowOrder = 0

local function addInfoRow(text: string, emphasized: boolean?)
	rowOrder += 1
	local label = Instance.new("TextLabel")
	label.Name = "Row"
	label.LayoutOrder = rowOrder
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.TextColor3 = if emphasized then DIM else FG
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextSize = 13
	label.Font = if emphasized then Enum.Font.SourceSansBold else Enum.Font.SourceSans
	label.Text = text
	label.Parent = gridScroll
end

-- ⚠️ คำนวณจำนวนคอลัมน์สดจากความกว้างจริงของ gridScroll (AbsoluteSize) ไม่ hardcode
-- รองรับทั้งจอมือถือเล็กและจอกว้าง — AbsoluteSize อาจยังเป็น 0 ก่อน layout รอบแรกเสร็จ
-- จึงมี fallback กันหารด้วยค่าติดลบ/ศูนย์
local function computeColumns(): number
	local availableWidth = gridScroll.AbsoluteSize.X - gridPadding.PaddingLeft.Offset - gridPadding.PaddingRight.Offset - gridScroll.ScrollBarThickness
	if availableWidth <= 0 then
		availableWidth = 220
	end
	return math.max(1, math.floor((availableWidth + CARD_GAP) / (CARD_SIZE + CARD_GAP)))
end

-- ⚠️ ไม่ใช้ UIGridLayout ตรง ๆ เพราะต้องแทรกหัวข้อความกว้างเต็มแถวปนกับกริดที่ wrap ได้
-- (UIGridLayout ไม่รองรับ "span ทุกคอลัมน์" ให้ label เดียว) จึงห่อการ์ดเป็นแถว ๆ เอง
-- แล้ววาง "GridRow" (Frame ธรรมดา) แต่ละแถวเข้า UIListLayout แนวตั้งเดิมของ gridScroll แทน
local function addCardGrid(cards: { CardSpec })
	if #cards == 0 then
		return
	end
	local columns = computeColumns()
	local index = 1
	while index <= #cards do
		rowOrder += 1
		local row = Instance.new("Frame")
		row.Name = "GridRow"
		row.LayoutOrder = rowOrder
		row.Size = UDim2.new(1, 0, 0, CARD_SIZE)
		row.BackgroundTransparency = 1
		row.Parent = gridScroll

		for col = 0, columns - 1 do
			local card = cards[index]
			if not card then
				break
			end
			local cardFrame = createCard(card, row, col + 1)
			cardFrame.Position = UDim2.new(0, col * (CARD_SIZE + CARD_GAP), 0, 0)
			index += 1
		end
	end
end

-- ล้างเนื้อหาเก่าก่อนเรนเดอร์ใหม่ทุกครั้ง (สลับแท็บ/เลือกของ/sync มาใหม่) เหลือแค่
-- UIPadding/UIListLayout ของ gridScroll ไว้ — แถวข้อมูลทั้งหมดตั้งชื่อ "Row"/"GridRow" เท่านั้น
local function clearGrid()
	for _, child in gridScroll:GetChildren() do
		if child.Name == "Row" or child.Name == "GridRow" then
			child:Destroy()
		end
	end
	rowOrder = 0
end

--------------------------------------------------------------------------------
-- สถานะที่เลือกอยู่ + ข้อมูลล่าสุดจาก server
--------------------------------------------------------------------------------

local activeTab: "mothers" | "eggs" = "mothers"
-- ⚠️ เก็บ uid/id ประจำตัว ไม่ใช่ตำแหน่งในลิสต์ — ลิสต์เลื่อนได้ทุกครั้งที่มีของเข้า/ออก
local selectedMotherUid: string? = nil
local selectedHeldEggId: number? = nil
-- ⚠️ ต้องรู้ว่าแม่ที่เลือกอยู่ตอนนี้อยู่คอกหรือกระเป๋า ถึงจะรู้ว่าปุ่มย้ายต้องยิงไปทางไหน
local motherLocationByUid: { [string]: "pen" | "bag" } = {}
local lastPayload: any = nil

-- ⚠️ forward-declare: onClick ของการ์ดใน renderMothersTab/renderEggsTab เรียก renderActiveTab
-- ตอนถูกกด (ไม่ใช่ตอนถูกสร้าง) จึงอ้างถึงตัวแปรนี้ก่อนที่ฟังก์ชันจริงจะถูกเซ็ตได้ตราบใดที่
-- ประกาศ local ไว้ก่อน — ห้ามใช้ `function renderActiveTab()` เฉย ๆ เพราะจะกลายเป็น global
-- ซึ่งขัดกับ --!strict
--
-- ⚠️ รับ `preserveScroll` เพราะ farmStateSync ยิงมาหาเราถี่มาก (ทุก WORLD.SYNC_INTERVAL
-- วินาที = ทุก 1 วิ ดู EggService.lua) ทุกครั้งที่ sync มาเราต้อง clearGrid()+สร้างการ์ดใหม่ทั้งชุด
-- (ไม่มี diff เฉพาะรายการที่เปลี่ยน) ถ้าไม่เก็บ/คืนตำแหน่ง scroll เอง ScrollingFrame จะเด้ง
-- กลับขึ้นบนสุดทุกครั้งที่ sync มา ระหว่างที่ผู้เล่นกำลังเลื่อนดูไข่/แม่อยู่พอดี — ค่า default
-- (ไม่ส่ง argument มา) คือ "เก็บตำแหน่งเดิมไว้" เพราะ caller ส่วนใหญ่ (sync, กดเลือกการ์ด)
-- อยากให้ยังอยู่ตำแหน่งเดิม มีแค่ตอนสลับแท็บเท่านั้นที่ส่ง false ให้เลื่อนกลับขึ้นบนสุด
-- (คนละลิสต์กันแล้ว ควรเริ่มดูจากบนสุดใหม่)
local renderActiveTab: (boolean?) -> ()

local function renderMothersTab()
	if not lastPayload then
		return
	end

	motherLocationByUid = {}
	local cards: { CardSpec } = {}

	for _, mother in lastPayload.mothersInPen do
		motherLocationByUid[mother.uid] = "pen"
		table.insert(cards, {
			title = mother.charName,
			subtitle = `{mother.weightText} · คอก`,
			color = CLASS_COLORS[mother.class] or CLASS_COLORS.C,
			selected = mother.uid == selectedMotherUid,
			onClick = function()
				selectedMotherUid = mother.uid
				renderActiveTab()
			end,
		})
	end

	for _, mother in lastPayload.mothersInBag do
		motherLocationByUid[mother.uid] = "bag"
		table.insert(cards, {
			title = mother.charName,
			subtitle = `{mother.weightText} · กระเป๋า`,
			color = CLASS_COLORS[mother.class] or CLASS_COLORS.C,
			selected = mother.uid == selectedMotherUid,
			onClick = function()
				selectedMotherUid = mother.uid
				renderActiveTab()
			end,
		})
	end

	addInfoRow(`คอก {#lastPayload.mothersInPen}/{lastPayload.penCapacity} · กระเป๋า {#lastPayload.mothersInBag}/{lastPayload.bagCapacity}`, true)
	if #cards == 0 then
		addInfoRow("  (ยังไม่มีแม่ — ฟักไข่ก่อน)")
	else
		addCardGrid(cards)
	end
end

local function renderEggsTab()
	if not lastPayload then
		return
	end

	-- ⚠️ จุดที่ดูออกว่ากฎ "น้ำหนักมาก่อน" ทำงานถูก: ไข่โชว์น้ำหนักตั้งแต่ยังไม่ฟัก
	--
	-- ⚠️ `payload.heldEggs` เป็น **อาเรย์แน่นของไข่ที่มีจริง** ไม่ใช่อาเรย์ยาวเท่าความจุแล้ว
	-- กระเป๋าจุ 10,000 ฟอง — server ส่งมาให้แค่ส่วนแรกเท่าที่ UI แสดงจริง (heldShown/heldCount)
	-- และแต่ละฟองมี `id` ประจำตัว **ซึ่งเป็นสิ่งเดียวที่ส่งกลับไปหา server ได้**
	local cards: { CardSpec } = {}
	for _, egg in lastPayload.heldEggs do
		table.insert(cards, {
			title = egg.eggName,
			subtitle = `#{egg.id} · {egg.weightText}`,
			color = EGG_CARD_COLOR,
			selected = egg.id == selectedHeldEggId,
			onClick = function()
				selectedHeldEggId = egg.id
				renderActiveTab()
			end,
		})
	end

	addInfoRow(`ไข่ในกระเป๋า: {lastPayload.heldCount}/{lastPayload.bagSize}`, true)
	if #cards == 0 then
		addInfoRow("  (ไม่มี — แจกด้วยคำสั่ง server: EggService.grantEgg)")
	else
		addCardGrid(cards)
		local more = lastPayload.heldCount - #lastPayload.heldEggs
		if more > 0 then
			addInfoRow(`  ...อีก {more} ฟอง (server ยังไม่ส่งมา กันบวมเน็ต)`)
		end
	end

	-- ⚠️ slot.stuck = ครบเวลาฟักแล้วแต่คอก+กระเป๋าเต็มพร้อมกัน (ข้อ D) รอที่ว่างอยู่
	addInfoRow(`สวนฟัก: {lastPayload.hatchingCount}/{lastPayload.hatcherySize}`, true)
	local anyHatching = false
	for index = 1, lastPayload.hatcherySize do
		local slot = lastPayload.hatching[index]
		if slot and slot.occupied then
			anyHatching = true
			local status = if slot.stuck then "ค้าง (รอที่ว่าง)" else `เหลือ {math.ceil(slot.remaining)} วิ`
			addInfoRow(`  [{index}] {slot.eggName} {slot.weightText} — {status}`)
		end
	end
	if not anyHatching then
		addInfoRow("  (ว่าง)")
	end
end

local function updateActionButton()
	if activeTab == "mothers" then
		if selectedMotherUid and motherLocationByUid[selectedMotherUid] then
			local destination = if motherLocationByUid[selectedMotherUid] == "pen" then "กระเป๋า" else "คอก"
			setActionButton(`ย้ายแม่ที่เลือก → {destination}`, true)
		else
			selectedMotherUid = nil
			setActionButton("เลือกแม่ในกริดก่อน", false)
		end
	else
		if selectedHeldEggId then
			setActionButton(`วางไข่ #{selectedHeldEggId} ลงสวนฟัก`, true)
		else
			setActionButton("เลือกไข่ในกริดก่อน", false)
		end
	end
end

renderActiveTab = function(preserveScroll: boolean?)
	local keepScroll = preserveScroll ~= false
	local savedCanvasPosition = gridScroll.CanvasPosition

	clearGrid()
	if activeTab == "mothers" then
		renderMothersTab()
	else
		renderEggsTab()
	end
	updateActionButton()
	motherTabButton.BackgroundColor3 = if activeTab == "mothers" then TAB_ACTIVE_COLOR else TAB_INACTIVE_COLOR
	eggTabButton.BackgroundColor3 = if activeTab == "eggs" then TAB_ACTIVE_COLOR else TAB_INACTIVE_COLOR

	if keepScroll then
		-- ⚠️ AutomaticCanvasSize ยังไม่คำนวณ CanvasSize ใหม่ในเฟรมเดียวกับที่เพิ่ง
		-- Destroy/สร้างการ์ดใหม่ (ยังอิงขนาดเก่าอยู่) ตั้ง CanvasPosition ทันทีเลยเสี่ยงโดน
		-- ปัดกลับเป็น 0 เพราะดูเหมือนเกินขอบเขตของ canvas เก่าที่ยังไม่อัปเดต
		-- เลื่อนไปตั้งใน task.defer (รอให้ layout รอบนี้จบก่อน) กันปัญหานี้
		task.defer(function()
			gridScroll.CanvasPosition = savedCanvasPosition
		end)
	else
		gridScroll.CanvasPosition = Vector2.zero
	end
end

--------------------------------------------------------------------------------
-- ต่อสาย
--------------------------------------------------------------------------------

motherTabButton.Activated:Connect(function()
	activeTab = "mothers"
	renderActiveTab(false)
end)

eggTabButton.Activated:Connect(function()
	activeTab = "eggs"
	renderActiveTab(false)
end)

actionButton.Activated:Connect(function()
	if activeTab == "mothers" then
		if not selectedMotherUid then
			return
		end
		local destination = if motherLocationByUid[selectedMotherUid] == "pen" then "bag" else "pen"
		moveMotherRequest:FireServer(selectedMotherUid, destination)
	else
		if not selectedHeldEggId then
			return
		end
		-- ⚠️ ส่ง **id ประจำฟอง** ไม่ใช่ชนิดไข่ และไม่ใช่ตำแหน่งในลิสต์
		--   · ชนิดไข่ระบุไม่ได้ — ไข่ชนิดเดียวกันน้ำหนักต่างกันได้
		--   · ตำแหน่งระบุไม่ได้ — ไข่ฟักเสร็จคั่นจังหวะแล้วทั้งแถวเลื่อน เราจะวางผิดฟอง
		placeEggRequest:FireServer(selectedHeldEggId)
	end
end)

farmStateSync.OnClientEvent:Connect(function(payload)
	lastPayload = payload

	-- ⚠️ ของที่เลือกไว้อาจหายไปจาก payload ใหม่ (ขาย/ย้าย/ฟักไปแล้ว) — ถ้าไม่ตรวจ
	-- ปุ่มจะยิง action ไปหาของที่ไม่มีอยู่แล้ว ต้องเคลียร์ selection ทิ้งก่อนเรนเดอร์
	if selectedMotherUid then
		local stillExists = false
		for _, mother in payload.mothersInPen do
			if mother.uid == selectedMotherUid then
				stillExists = true
				break
			end
		end
		if not stillExists then
			for _, mother in payload.mothersInBag do
				if mother.uid == selectedMotherUid then
					stillExists = true
					break
				end
			end
		end
		if not stillExists then
			selectedMotherUid = nil
		end
	end

	if selectedHeldEggId then
		local stillExists = false
		for _, egg in payload.heldEggs do
			if egg.id == selectedHeldEggId then
				stillExists = true
				break
			end
		end
		if not stillExists then
			selectedHeldEggId = nil
		end
	end

	renderActiveTab()
end)

eggHatched.OnClientEvent:Connect(function(payload)
	local place = if payload.placedIn == "pen" then "เข้าคอก" else "เข้ากระเป๋า"
	resultLabel.Text = `ฟักช่อง {payload.slotIndex} ได้ {payload.charName} ({payload.class}) {payload.weightText} → {place}`
	print(`[Client] ฟักได้ {payload.charName} คลาส {payload.class} น้ำหนัก {payload.weightText}`)
end)

-- ⚠️ กำแพงวาดฝั่งนี้เท่านั้น — แต่ละคนพังคนละด่านแต่ยืนบนเลนเดียวกัน
-- (เหตุผลเต็มอยู่ใน src/client/WallRenderer.lua และ docs/map-layout.md)
WallRenderer.start()

print(`[egg-army-game] client พร้อมแล้ว · wallProgress ทดสอบ = {WallRenderer.getWallProgress()}`)
print("   เปลี่ยนด่านที่พังแล้วเพื่อทดสอบ: WallRenderer.setWallProgress(n)")
