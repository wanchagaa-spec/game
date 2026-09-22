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
local upgradePenRequest = Remotes.waitFor(Config.RemoteNames.UPGRADE_PEN_REQUEST)
local sellMotherRequest = Remotes.waitFor(Config.RemoteNames.SELL_MOTHER_REQUEST)
local autoFillPenRequest = Remotes.waitFor(Config.RemoteNames.AUTO_FILL_PEN_REQUEST)
local eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
local farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)
-- ⚠️ server ส่งผลลัพธ์ (สำเร็จ/ล้มเหลว + เหตุผล) ของคำขอด้านบนกลับมาทางนี้
-- ก่อนหน้านี้ผลลัพธ์ไปโผล่แค่ print ใน server console เท่านั้น ผู้เล่นไม่เห็นอะไรเลย
local actionResult = Remotes.waitFor(Config.RemoteNames.ACTION_RESULT)

--------------------------------------------------------------------------------
-- สร้าง UI
--------------------------------------------------------------------------------

-- ⚠️ Phase 1.5–2B: ยังเป็นแผงเทสต์ ไม่ใช่ UI จริง (Phase 3 ค่อยทำ UI จริงแบบมีไอคอนสัตว์)
-- แต่ต้อง "ใช้งานได้จริงระหว่างทดสอบ" — ย่อ/ขยายได้ + รายการ scroll ได้ + ขยายแล้วอ่าน/กดสบาย
-- (เคยเป็นกล่องข้อความเต็มจอความสูงคงที่ พอแม่/ไข่เยอะขึ้นบังแมพจนมองไม่เห็นอะไรเลย)

local BG = Color3.fromRGB(28, 30, 36)
local FG = Color3.fromRGB(240, 240, 240)
local DIM = Color3.fromRGB(160, 165, 175)
local ACCENT = Color3.fromRGB(90, 160, 235)
local SUCCESS_COLOR = Color3.fromRGB(140, 220, 140)
local ERROR_COLOR = Color3.fromRGB(235, 130, 130)
-- ⚠️ สีเตือน (ส้ม) เฉพาะปุ่ม "ทดสอบชั่วคราว" ให้ดูต่างจากปุ่มปกติชัดเจน เพราะเป็นปุ่มที่ทำสิ่งที่
-- ย้อนกลับไม่ได้ (ขายแม่) และของจริงต้องย้ายไปร้านค้า ไม่ใช่ตรงนี้
local TEMP_BUTTON_COLOR = Color3.fromRGB(200, 140, 60)
local DISABLED_ACTION_COLOR = Color3.fromRGB(70, 74, 82)

local HEADER_HEIGHT = 36
local TAB_BAR_HEIGHT = 32
local UPGRADE_BUTTON_HEIGHT = 26
local ACTION_BUTTON_HEIGHT = 30
local RESULT_HEIGHT = 32
local BODY_GAP = 6
-- ⚠️ ผลรวมความสูงของทุกอย่างใน body ยกเว้น gridScroll — ใช้คำนวณ gridScroll.Size ตรง ๆ
-- แทน UIFlexItem (FlexMode=Fill) ที่เคยใช้ — บนไคลเอนต์จริงบางเครื่องมันไม่ทำงาน
-- แล้ว gridScroll ตกกลับไปใช้ fallback Size เต็ม 100% ซ้อนทับพี่น้องตัวอื่นจน body ล้นทะลุแผง
-- ⚠️ body มี 4 ชิ้นคงที่ (tabBar, upgradePenButton, actionButton, resultLabel) + gridScroll
-- เว้นวรรคด้วย BODY_GAP 4 ครั้ง (ระหว่างแต่ละคู่ในทั้งหมด 5 ชิ้น) — แก้จำนวนแถวแล้วต้องแก้เลข 4 นี้ด้วย
-- (ปุ่มขาย/จัดแม่อัตโนมัติย้ายเข้าไปเป็นแถวข้างในแท็บ "กระเป๋า" แทน ไม่ใช่แถวคงที่นอกกริดอีกต่อไป)
local FIXED_STACK_HEIGHT = TAB_BAR_HEIGHT + UPGRADE_BUTTON_HEIGHT + ACTION_BUTTON_HEIGHT + RESULT_HEIGHT + BODY_GAP * 4

local gui = Instance.new("ScreenGui")
gui.Name = "EggFarmDebugUI"
gui.ResetOnSpawn = false
-- ⚠️ true เคยทำให้แผงวาดทับ/อยู่ใต้ไอคอนระบบของ Roblox บนแถบบนสุด (report/chat/mic ฯลฯ)
-- ซ่อนแถบหัวไปครึ่งหนึ่งจนกดปุ่มย่อ/ขยายไม่โดน — false ให้ Roblox เว้น inset ให้เองอัตโนมัติ
gui.IgnoreGuiInset = false
gui.Parent = playerGui

--------------------------------------------------------------------------------
-- ยอดเงินมุมล่างขวา — อยู่นอกแผงที่ย่อ/ปิดได้ ต้องเห็นตลอดเวลา เป็นลูกของ `gui` ตรง ๆ
-- ไม่ใช่ของ `panel` ที่ย่อได้ (panel.Visible ไม่กระทบตัวนี้เลย)
--
-- ⚠️⚠️ เคยวางไว้มุมขวาบนก่อน แล้วชนกับ UI ของ Roblox เอง (ป้ายชื่อผู้เล่น + ยอด Robux ที่
-- Roblox วาดต่อกันเป็นชุดในมุมนั้น กินพื้นที่มากกว่าแค่ไอคอนระบบที่ IgnoreGuiInset คำนวณให้)
-- ย้ายไปกึ่งกลางบนแทน แต่จุดนั้นเอาไว้ใส่ของอย่างอื่นแล้ว จึงย้ายมา**มุมล่างขวา**แทน — Roblox
-- ไม่วาง UI ระบบไว้แถวนี้เลย ปลอดภัยจากปัญหาชนกันแบบเดียวกัน
-- ⚠️ ขนาดใหญ่ขึ้นอีก ×2 จากรอบก่อน (กล่อง 280×36 → 560×72 · ตัวอักษร 26 → 52) ตามที่ขอ
-- ไม่มีกล่อง/พื้นหลัง (BackgroundTransparency = 1) มีเงาเส้นขอบ (TextStroke) แทน กันอ่านไม่ออก
-- ตอนพื้นหลังเป็นท้องฟ้า/หญ้าสว่าง
--------------------------------------------------------------------------------

local coinLabel = Instance.new("TextLabel")
coinLabel.Name = "CoinLabel"
coinLabel.AnchorPoint = Vector2.new(1, 1)
coinLabel.Position = UDim2.new(1, -16, 1, -16)
coinLabel.Size = UDim2.new(0, 560, 0, 72)
coinLabel.BackgroundTransparency = 1
coinLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
coinLabel.TextXAlignment = Enum.TextXAlignment.Right
coinLabel.TextSize = 52
coinLabel.Font = Enum.Font.SourceSansBold
coinLabel.TextStrokeTransparency = 0.4
coinLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
coinLabel.Text = "-"
coinLabel.Parent = gui

-- ⚠️ ใส่ comma คั่นหลักพันเอง (ไม่มีให้ในตัวภาษา) — เฉพาะจำนวนเต็ม ไม่ต้องรองรับทศนิยม เพราะ
-- currency.coins ทั้งเกมเป็นจำนวนเต็มเสมอ (math.floor ตอนคำนวณราคาทุกจุด) — ข้อ 4: โชว์เต็ม ไม่ย่อ
local function formatCommaNumber(value: number): string
	local sign = if value < 0 then "-" else ""
	local intPart = string.format("%d", math.abs(math.floor(value)))
	local reversed = string.reverse(intPart)
	local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
	local formatted = string.reverse(grouped)
	formatted = string.gsub(formatted, "^,", "")
	return sign .. formatted
end

-- ⚠️ ขนาดเป็น scale ไม่ใช่ pixel ตายตัว — MaxSize คุมอีกชั้นกันจอใหญ่มาก (4K/ultrawide)
-- ไม่ให้แผงขยายใหญ่เกินเหตุ (ยกขึ้นมากตามข้อ 5 — ตอนนี้ปุ่มย่อกดปิดได้จริงแล้ว ไม่ต้องกลัวบังจอ)
-- ⚠️ MinSize.Y ตั้งต่ำมาก (แค่กันค่าติดลบ) ไม่ใช่ 200+ เพราะตอนย่อแผงเหลือแค่แถบหัว (HEADER_HEIGHT)
-- ถ้าตั้ง MinSize.Y สูงกว่านั้น UISizeConstraint จะดันความสูงตอนย่อกลับขึ้นมาเอง ย่อไม่ได้จริง
local EXPANDED_SIZE = UDim2.fromScale(0.7, 0.8)
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
sizeConstraint.MaxSize = Vector2.new(1000, 800)
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
bodyLayout.Padding = UDim.new(0, BODY_GAP)
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

-- ⚠️ ใช้คำนวณความกว้างปุ่มที่แบ่งเท่า ๆ กันในแถบแท็บ โดยไม่ hardcode เลขชดเชย — offset ต้องหัก
-- ส่วนที่ padding ระหว่างปุ่มกินไปให้พอดี ผลรวม scale ของทุกปุ่ม = 1.0 เสมอ และผลรวม offset
-- ของทุกปุ่ม = -(gap รวมทั้งหมด) เสมอ
local function equalSplitOffset(count: number, gap: number): number
	return -(gap * (count - 1) / count)
end

--------------------------------------------------------------------------------
-- แถบแท็บ: คอก / กระเป๋า / ไข่ / ลูก
-- ⚠️ เดิมแท็บ "แม่" รวมคอก+กระเป๋าไว้ด้วยกัน (แยกแค่หัวข้อภายใน) แยกเป็นคนละแท็บจริงตามที่ขอ
--------------------------------------------------------------------------------

local TAB_ACTIVE_COLOR = ACCENT
local TAB_INACTIVE_COLOR = Color3.fromRGB(50, 54, 62)
local TAB_COUNT = 4
local TAB_GAP = 6

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.LayoutOrder = 1
tabBar.Size = UDim2.new(1, 0, 0, TAB_BAR_HEIGHT)
tabBar.BackgroundTransparency = 1
tabBar.Parent = body

local tabBarLayout = Instance.new("UIListLayout")
tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
tabBarLayout.Padding = UDim.new(0, TAB_GAP)
tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabBarLayout.Parent = tabBar

local TAB_BUTTON_OFFSET = equalSplitOffset(TAB_COUNT, TAB_GAP)

local function makeTabButton(name: string, order: number, text: string): TextButton
	local tabButton = Instance.new("TextButton")
	tabButton.Name = name
	tabButton.LayoutOrder = order
	-- ⚠️ คำนวณจาก TAB_COUNT/TAB_GAP ด้านบน ไม่ hardcode — เพิ่ม/ลดแท็บทีหลังไม่ต้องมานั่งคิดเลขใหม่
	tabButton.Size = UDim2.new(1 / TAB_COUNT, TAB_BUTTON_OFFSET, 1, 0)
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

local penTabButton = makeTabButton("PenTab", 1, "คอก")
local bagTabButton = makeTabButton("BagTab", 2, "กระเป๋า")
local eggTabButton = makeTabButton("EggTab", 3, "ไข่")
local childrenTabButton = makeTabButton("ChildrenTab", 4, "ลูก")

--------------------------------------------------------------------------------
-- ปุ่มอัปเกรดคอก — อยู่ตลอด ไม่ขึ้นกับแท็บ/การเลือก เพราะเป็นค่าของบัญชี ไม่ใช่ของแม่ตัวไหน
--------------------------------------------------------------------------------

local upgradePenButton = makeButton("UpgradePen", 2, "กำลังโหลด...")
upgradePenButton.Size = UDim2.new(1, 0, 0, UPGRADE_BUTTON_HEIGHT)
upgradePenButton.TextSize = 12

local actionButton = makeButton("Action", 3, "กำลังโหลด...")

local function setActionButton(text: string, enabled: boolean)
	actionButton.Text = text
	actionButton.Active = enabled
	actionButton.AutoButtonColor = enabled
	actionButton.BackgroundColor3 = if enabled then ACCENT else DISABLED_ACTION_COLOR
end

-- ⚠️ กริดของคอก/กระเป๋า/ไข่/ลูก รวมอยู่ใน ScrollingFrame เดียวต่อแท็บ แทนที่จะแยกกล่อง scroll
-- ซ้อนกันหลายอัน (scroll ซ้อน scroll ใช้งานสับสน เลื่อนผิดกล่อง)
-- ⚠️ Size คำนวณจาก FIXED_STACK_HEIGHT ตรง ๆ (ดูคอมเมนต์ตอนประกาศค่าคงที่ด้านบนของไฟล์)
-- ไม่ใช้ UIFlexItem อีกต่อไป เพราะมันคือสาเหตุที่เนื้อหาเคยล้นทะลุแผงจริงในเกม
local gridScroll = Instance.new("ScrollingFrame")
gridScroll.Name = "Grid"
gridScroll.LayoutOrder = 4
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
resultLabel.LayoutOrder = 5
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

-- ⚠️⚠️ เคยพลาด: ฟังก์ชันนี้อ่าน `collapsed` มาคำนวณ แต่ไม่เคยสลับค่ามันเลยสักที่
-- กดปุ่มกี่ครั้งก็เลยไม่มีอะไรเกิดขึ้น (ค่ามันค้างที่ false ตลอดกาล) — ต้องสลับค่าก่อนใช้เสมอ
local function applyCollapsedState()
	collapsed = not collapsed
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
-- ⚠️ ไข่ที่กำลังฟักใช้สีคนละชุดจากไข่ในกระเป๋า กันสับสนว่าเป็นคนละสถานะกัน
local HATCH_CARD_COLOR = Color3.fromRGB(235, 200, 140)
local HATCH_STUCK_COLOR = Color3.fromRGB(165, 165, 170)

local CARD_SIZE = 72
local CARD_GAP = 6
local BUTTON_ROW_HEIGHT = 28

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

-- แถวปุ่มกดได้เต็มความกว้าง ใช้กับปุ่มเฉพาะแท็บ (จัดแม่อัตโนมัติ/ขาย) ที่อยู่ในเนื้อหาของแท็บ
-- "กระเป๋า" เท่านั้น แทนที่จะเป็นแถวถาวรนอกกริดที่โผล่ทุกแท็บ — ใช้ชื่อ "Row" เหมือน addInfoRow
-- เพื่อให้ clearGrid() ล้างออกพร้อมกันได้ (เช็คแค่ชื่อ ไม่ได้เช็ค ClassName)
local function addButtonRow(text: string, enabled: boolean, color: Color3, onClick: () -> ())
	rowOrder += 1
	local row = Instance.new("TextButton")
	row.Name = "Row"
	row.LayoutOrder = rowOrder
	row.Size = UDim2.new(1, 0, 0, BUTTON_ROW_HEIGHT)
	row.BackgroundColor3 = if enabled then color else DISABLED_ACTION_COLOR
	row.BorderSizePixel = 0
	row.TextColor3 = Color3.fromRGB(255, 255, 255)
	row.TextSize = 13
	row.TextWrapped = true
	row.Font = Enum.Font.SourceSansBold
	row.Text = text
	row.Active = enabled
	row.AutoButtonColor = enabled
	row.Parent = gridScroll

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	row.Activated:Connect(onClick)
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

local activeTab: "pen" | "bag" | "eggs" | "children" = "pen"
-- ⚠️ เก็บ uid/id ประจำตัว ไม่ใช่ตำแหน่งในลิสต์ — ลิสต์เลื่อนได้ทุกครั้งที่มีของเข้า/ออก
local selectedMotherUid: string? = nil
local selectedHeldEggId: number? = nil
-- ⚠️ คอก/กระเป๋าแยกกันคนละแท็บแล้ว แต่ละแท็บ render แค่ของฝั่งตัวเอง map นี้เลยมีแค่ entry
-- ของแท็บที่กำลังแสดงอยู่จริงเท่านั้น (renderPenTab ใส่แค่ "pen", renderBagTab ใส่แค่ "bag")
-- ใช้ตรวจว่า selectedMotherUid ที่ค้างมาจากแท็บอื่นยังใช้กับแท็บปัจจุบันได้ไหม
local motherLocationByUid: { [string]: "pen" | "bag" } = {}
local lastPayload: any = nil

-- ⚠️ forward-declare: onClick ของการ์ดใน renderPenTab/renderBagTab/renderEggsTab เรียก
-- renderActiveTab ตอนถูกกด (ไม่ใช่ตอนถูกสร้าง) จึงอ้างถึงตัวแปรนี้ก่อนที่ฟังก์ชันจริงจะถูกเซ็ต
-- ได้ตราบใดที่ประกาศ local ไว้ก่อน — ห้ามใช้ `function renderActiveTab()` เฉย ๆ เพราะจะกลายเป็น
-- global ซึ่งขัดกับ --!strict
--
-- ⚠️ รับ `preserveScroll` เพราะ farmStateSync ยิงมาหาเราถี่มาก (ทุก WORLD.SYNC_INTERVAL
-- วินาที = ทุก 1 วิ ดู EggService.lua) ทุกครั้งที่ sync มาเราต้อง clearGrid()+สร้างการ์ดใหม่ทั้งชุด
-- (ไม่มี diff เฉพาะรายการที่เปลี่ยน) ถ้าไม่เก็บ/คืนตำแหน่ง scroll เอง ScrollingFrame จะเด้ง
-- กลับขึ้นบนสุดทุกครั้งที่ sync มา ระหว่างที่ผู้เล่นกำลังเลื่อนดูไข่/แม่อยู่พอดี — ค่า default
-- (ไม่ส่ง argument มา) คือ "เก็บตำแหน่งเดิมไว้" เพราะ caller ส่วนใหญ่ (sync, กดเลือกการ์ด)
-- อยากให้ยังอยู่ตำแหน่งเดิม มีแค่ตอนสลับแท็บเท่านั้นที่ส่ง false ให้เลื่อนกลับขึ้นบนสุด
-- (คนละลิสต์กันแล้ว ควรเริ่มดูจากบนสุดใหม่)
local renderActiveTab: (boolean?) -> ()

local function renderPenTab()
	if not lastPayload then
		return
	end

	motherLocationByUid = {}
	local cards: { CardSpec } = {}

	for _, mother in lastPayload.mothersInPen do
		motherLocationByUid[mother.uid] = "pen"
		table.insert(cards, {
			title = mother.charName,
			subtitle = mother.weightText,
			color = CLASS_COLORS[mother.class] or CLASS_COLORS.C,
			selected = mother.uid == selectedMotherUid,
			onClick = function()
				selectedMotherUid = mother.uid
				renderActiveTab()
			end,
		})
	end

	addInfoRow(`คอก {#lastPayload.mothersInPen}/{lastPayload.penCapacity}`, true)
	if #cards == 0 then
		addInfoRow("  (ยังไม่มีแม่ — ฟักไข่ก่อน หรือกด \"จัดแม่เข้าคอกอัตโนมัติ\" ในแท็บกระเป๋า)")
	else
		addCardGrid(cards)
	end
end

local function renderBagTab()
	if not lastPayload then
		return
	end

	motherLocationByUid = {}
	local cards: { CardSpec } = {}

	for _, mother in lastPayload.mothersInBag do
		motherLocationByUid[mother.uid] = "bag"
		table.insert(cards, {
			title = mother.charName,
			subtitle = mother.weightText,
			color = CLASS_COLORS[mother.class] or CLASS_COLORS.C,
			selected = mother.uid == selectedMotherUid,
			onClick = function()
				selectedMotherUid = mother.uid
				renderActiveTab()
			end,
		})
	end

	-- ⚠️ ปุ่มถาวร (ไม่ใช่ TEMP): จัดแม่จากกระเป๋าเข้าคอกอัตโนมัติ — server เป็นคนเลือก/ย้ายจริง
	-- ทั้งหมด (AutoFillPenRequest) client แค่กดเรียก ไม่คำนวณว่าตัวไหนดีที่สุดเอง
	local freeSlots = lastPayload.penCapacity - #lastPayload.mothersInPen
	if freeSlots <= 0 then
		addButtonRow("คอกเต็มแล้ว จัดเพิ่มไม่ได้", false, ACCENT, function() end)
	elseif #lastPayload.mothersInBag == 0 then
		addButtonRow("ไม่มีแม่ให้จัด", false, ACCENT, function() end)
	else
		addButtonRow(`จัดแม่เข้าคอกอัตโนมัติ (เหลือที่ว่าง {freeSlots})`, true, ACCENT, function()
			autoFillPenRequest:FireServer()
		end)
	end

	-- ⚠️⚠️ TEMP: ปุ่มขายด่วนสำหรับทดสอบเท่านั้น ไม่ใช่ flow จริงของเกม — ของจริงต้องไปขายที่
	-- ระบบร้านค้า (ยังไม่ได้ทำ) มีไว้แค่ให้เคลียร์กระเป๋าแม่เร็ว ๆ ระหว่างทดสอบระบบอื่นเท่านั้น
	if selectedMotherUid and motherLocationByUid[selectedMotherUid] == "bag" then
		addButtonRow("ขายที่เลือก (TEMP)", true, TEMP_BUTTON_COLOR, function()
			sellMotherRequest:FireServer(selectedMotherUid)
		end)
	else
		addButtonRow("เลือกแม่ด้านล่างเพื่อขาย (TEMP)", false, TEMP_BUTTON_COLOR, function() end)
	end

	if #lastPayload.mothersInBag > 0 then
		addButtonRow(`ขายทั้งหมดในกระเป๋า ({#lastPayload.mothersInBag}) (TEMP)`, true, TEMP_BUTTON_COLOR, function()
			-- ⚠️⚠️ TEMP: วน FireServer ทีละตัวจนครบ — ไม่มีคำขอ "ขายทั้งหมด" แบบ batch ฝั่ง
			-- server เลย (ไม่ต้องมี ของจริงย้ายไปร้านค้าอยู่ดี) server ตัดสินแต่ละคำขอเองอิสระ
			for _, mother in lastPayload.mothersInBag do
				sellMotherRequest:FireServer(mother.uid)
			end
		end)
	else
		addButtonRow("กระเป๋าไม่มีแม่ให้ขาย (TEMP)", false, TEMP_BUTTON_COLOR, function() end)
	end

	addInfoRow(`กระเป๋า {#lastPayload.mothersInBag}/{lastPayload.bagCapacity}`, true)
	if #cards == 0 then
		addInfoRow("  (ว่าง)")
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
	-- กระเป๋าจุตามเพดาน — server ส่งมาให้แค่ส่วนแรกเท่าที่ UI แสดงจริง (heldShown/heldCount)
	-- และแต่ละฟองมี `id` ประจำตัว **ซึ่งเป็นสิ่งเดียวที่ส่งกลับไปหา server ได้**
	local heldCards: { CardSpec } = {}
	for _, egg in lastPayload.heldEggs do
		table.insert(heldCards, {
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
	if #heldCards == 0 then
		addInfoRow("  (ไม่มี — แจกด้วยคำสั่ง server: EggService.grantEgg)")
	else
		addCardGrid(heldCards)
		local more = lastPayload.heldCount - #lastPayload.heldEggs
		if more > 0 then
			addInfoRow(`  ...อีก {more} ฟอง (server ยังไม่ส่งมา กันบวมเน็ต)`)
		end
	end

	-- ⚠️ การ์ดไข่ที่กำลังฟัก — โชว์เวลานับถอยหลังเด่น ๆ ไม่ใช่แค่น้ำหนัก (อัปเดตทุกครั้งที่ sync
	-- มา ~ทุก 1 วิ ไม่ใช่นับสดในเครื่อง client เอง — พอสำหรับทดสอบ) slot.stuck = ครบเวลาฟักแล้ว
	-- แต่คอก+กระเป๋าเต็มพร้อมกัน (ข้อ D) รอที่ว่างอยู่ ใช้สีแยกจากที่กำลังนับถอยหลังปกติ
	local hatchCards: { CardSpec } = {}
	for index = 1, lastPayload.hatcherySize do
		local slot = lastPayload.hatching[index]
		if slot and slot.occupied then
			local status = if slot.stuck then "ค้าง (รอที่ว่าง)" else `เหลือ {math.ceil(slot.remaining)} วิ`
			table.insert(hatchCards, {
				title = slot.eggName,
				subtitle = `{slot.weightText} · {status}`,
				color = if slot.stuck then HATCH_STUCK_COLOR else HATCH_CARD_COLOR,
				selected = false,
				onClick = function() end,
			})
		end
	end

	addInfoRow(`สวนฟัก: {lastPayload.hatchingCount}/{lastPayload.hatcherySize}`, true)
	if #hatchCards == 0 then
		addInfoRow("  (ว่าง)")
	else
		addCardGrid(hatchCards)
	end
end

-- ⚠️ แท็บลูก — ดูอย่างเดียว ไม่มีปุ่มกระทำการ (ปล่อยทหารเป็นงานเฟสหลัง) แค่ไว้เช็คว่ากองลูก
-- (stack) รวมกันถูกต้องไหม — ลูกที่ตัวละคร+น้ำหนัก+สถานะเหมือนกันต้องรวมเป็นกองเดียว
local function renderChildrenTab()
	if not lastPayload then
		return
	end

	local cards: { CardSpec } = {}
	for _, stack in lastPayload.children do
		table.insert(cards, {
			title = stack.charName,
			subtitle = `{stack.weightText} × {stack.count}`,
			color = CLASS_COLORS[stack.class] or CLASS_COLORS.C,
			selected = false,
			onClick = function() end,
		})
	end

	addInfoRow(`กองลูกทั้งหมด: {#lastPayload.children} กอง`, true)
	if #cards == 0 then
		addInfoRow("  (ยังไม่มีลูก — ต้องมีแม่ในคอกก่อนถึงจะเริ่มผลิต)")
	else
		addCardGrid(cards)
	end
end

local function updateActionButton()
	if activeTab == "pen" then
		if selectedMotherUid and motherLocationByUid[selectedMotherUid] == "pen" then
			setActionButton("ย้ายแม่ที่เลือก → กระเป๋า", true)
		else
			selectedMotherUid = nil
			setActionButton("เลือกแม่ในกริดก่อน", false)
		end
	elseif activeTab == "bag" then
		if selectedMotherUid and motherLocationByUid[selectedMotherUid] == "bag" then
			setActionButton("ย้ายแม่ที่เลือก → คอก", true)
		else
			selectedMotherUid = nil
			setActionButton("เลือกแม่ในกริดก่อน", false)
		end
	elseif activeTab == "eggs" then
		if selectedHeldEggId then
			setActionButton(`วางไข่ #{selectedHeldEggId} ลงสวนฟัก`, true)
		else
			setActionButton("เลือกไข่ในกริดก่อน", false)
		end
	else
		setActionButton("แท็บนี้ไว้ดูอย่างเดียว ยังไม่มีปุ่มกระทำการ", false)
	end
end

-- ⚠️ ปุ่มอัปเกรดคอก — ไม่ขึ้นกับแท็บ/การเลือก อ่านตรงจาก payload ล่าสุดเสมอ
-- penUpgradeCost เป็น nil เมื่อคอกเต็มเพดานแล้ว (ดู Config.getPenUpgradeCost)
local function updateUpgradePenButton()
	if not lastPayload then
		return
	end
	if lastPayload.penUpgradeCost then
		upgradePenButton.Text = `อัปเกรดคอก Lv{lastPayload.penLevel} → Lv{lastPayload.penLevel + 1} (฿{formatCommaNumber(lastPayload.penUpgradeCost)})`
		upgradePenButton.Active = true
		upgradePenButton.AutoButtonColor = true
		upgradePenButton.BackgroundColor3 = ACCENT
	else
		upgradePenButton.Text = `คอก Lv{lastPayload.penLevel} (เต็มเพดานแล้ว)`
		upgradePenButton.Active = false
		upgradePenButton.AutoButtonColor = false
		upgradePenButton.BackgroundColor3 = DISABLED_ACTION_COLOR
	end
end

renderActiveTab = function(preserveScroll: boolean?)
	local keepScroll = preserveScroll ~= false
	local savedCanvasPosition = gridScroll.CanvasPosition

	clearGrid()
	if activeTab == "pen" then
		renderPenTab()
	elseif activeTab == "bag" then
		renderBagTab()
	elseif activeTab == "eggs" then
		renderEggsTab()
	else
		renderChildrenTab()
	end
	updateActionButton()
	updateUpgradePenButton()
	penTabButton.BackgroundColor3 = if activeTab == "pen" then TAB_ACTIVE_COLOR else TAB_INACTIVE_COLOR
	bagTabButton.BackgroundColor3 = if activeTab == "bag" then TAB_ACTIVE_COLOR else TAB_INACTIVE_COLOR
	eggTabButton.BackgroundColor3 = if activeTab == "eggs" then TAB_ACTIVE_COLOR else TAB_INACTIVE_COLOR
	childrenTabButton.BackgroundColor3 = if activeTab == "children" then TAB_ACTIVE_COLOR else TAB_INACTIVE_COLOR

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

penTabButton.Activated:Connect(function()
	activeTab = "pen"
	renderActiveTab(false)
end)

bagTabButton.Activated:Connect(function()
	activeTab = "bag"
	renderActiveTab(false)
end)

eggTabButton.Activated:Connect(function()
	activeTab = "eggs"
	renderActiveTab(false)
end)

childrenTabButton.Activated:Connect(function()
	activeTab = "children"
	renderActiveTab(false)
end)

upgradePenButton.Activated:Connect(function()
	upgradePenRequest:FireServer()
end)

actionButton.Activated:Connect(function()
	if activeTab == "pen" then
		if not selectedMotherUid then
			return
		end
		moveMotherRequest:FireServer(selectedMotherUid, "bag")
	elseif activeTab == "bag" then
		if not selectedMotherUid then
			return
		end
		moveMotherRequest:FireServer(selectedMotherUid, "pen")
	elseif activeTab == "eggs" then
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
	coinLabel.Text = formatCommaNumber(payload.coins)

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

-- ⚠️ ผลลัพธ์ของ PlaceEgg/MoveMother/UpgradePen/SellMother/AutoFillPen — ก่อนหน้านี้เห็นแค่ผ่าน
-- print ใน server console เท่านั้น ผู้เล่นไม่เห็นอะไรเลยว่าทำไมกดแล้วไม่มีอะไรเกิดขึ้น
actionResult.OnClientEvent:Connect(function(ok: boolean, message: string)
	resultLabel.Text = message
	resultLabel.TextColor3 = if ok then SUCCESS_COLOR else ERROR_COLOR
end)

eggHatched.OnClientEvent:Connect(function(payload)
	local place = if payload.placedIn == "pen" then "เข้าคอก" else "เข้ากระเป๋า"
	resultLabel.Text = `ฟักช่อง {payload.slotIndex} ได้ {payload.charName} ({payload.class}) {payload.weightText} → {place}`
	resultLabel.TextColor3 = SUCCESS_COLOR
	print(`[Client] ฟักได้ {payload.charName} คลาส {payload.class} น้ำหนัก {payload.weightText}`)
end)

-- ⚠️ กำแพงวาดฝั่งนี้เท่านั้น — แต่ละคนพังคนละด่านแต่ยืนบนเลนเดียวกัน
-- (เหตุผลเต็มอยู่ใน src/client/WallRenderer.lua และ docs/map-layout.md)
WallRenderer.start()

print(`[egg-army-game] client พร้อมแล้ว · wallProgress ทดสอบ = {WallRenderer.getWallProgress()}`)
print("   เปลี่ยนด่านที่พังแล้วเพื่อทดสอบ: WallRenderer.setWallProgress(n)")
