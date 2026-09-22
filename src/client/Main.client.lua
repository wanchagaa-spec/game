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

local gui = Instance.new("ScreenGui")
gui.Name = "EggFarmDebugUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
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
	button.Size = UDim2.new(1, 0, 0, 30)
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

local placeButton = makeButton("PlaceEgg", 1, "เอาไข่ฟองแรกเข้าสวนฟัก")
local toBagButton = makeButton("ToBag", 2, "ย้ายแม่ตัวแรกในคอก → กระเป๋า")
local toPenButton = makeButton("ToPen", 3, "ย้ายแม่ตัวแรกในกระเป๋า → คอก")

-- ⚠️ ลิสต์ทั้งหมด (ไข่ในกระเป๋า/สวนฟัก/คอก/กระเป๋าแม่) รวมอยู่ใน ScrollingFrame เดียว
-- แทนที่จะแยกกล่อง scroll ซ้อนกันหลายอัน (scroll ซ้อน scroll ใช้งานสับสน เลื่อนผิดกล่อง)
-- ⚠️ UIFlexItem(Fill) ให้กินพื้นที่ที่เหลือทั้งหมดหลังหักปุ่ม/ผลลัพธ์ — ไม่ต้องคำนวณความสูงเอง
-- (Size เต็ม 1,0,1,0 ที่ตั้งไว้เป็นแค่ fallback เผื่อ UIFlexItem ใช้ไม่ได้บนเอนจินเก่ามาก)
local scrollArea = Instance.new("ScrollingFrame")
scrollArea.Name = "List"
scrollArea.LayoutOrder = 4
scrollArea.Size = UDim2.new(1, 0, 1, 0)
scrollArea.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
scrollArea.BackgroundTransparency = 0.2
scrollArea.BorderSizePixel = 0
scrollArea.ScrollBarThickness = 6
scrollArea.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollArea.Parent = body

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 6)
scrollCorner.Parent = scrollArea

local scrollPadding = Instance.new("UIPadding")
scrollPadding.PaddingTop = UDim.new(0, 4)
scrollPadding.PaddingBottom = UDim.new(0, 4)
scrollPadding.PaddingLeft = UDim.new(0, 6)
scrollPadding.PaddingRight = UDim.new(0, 6)
scrollPadding.Parent = scrollArea

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 2)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scrollArea

local scrollFlex = Instance.new("UIFlexItem")
scrollFlex.FlexMode = Enum.UIFlexMode.Fill
scrollFlex.Parent = scrollArea

local resultLabel = Instance.new("TextLabel")
resultLabel.Name = "Result"
resultLabel.LayoutOrder = 5
resultLabel.Size = UDim2.new(1, 0, 0, 32)
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
-- แถวในลิสต์ — การ์ดกะทัดรัด: ชื่อ+น้ำหนัก+คลาสในบรรทัดเดียว ไม่กินพื้นที่แนวตั้งเยอะ
--------------------------------------------------------------------------------

local rowOrder = 0

local function addSectionHeader(text: string)
	rowOrder += 1
	local label = Instance.new("TextLabel")
	label.Name = "Row"
	label.LayoutOrder = rowOrder
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.TextColor3 = DIM
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 13
	label.Font = Enum.Font.SourceSansBold
	label.Text = text
	label.Parent = scrollArea
end

local function addRow(text: string)
	rowOrder += 1
	local label = Instance.new("TextLabel")
	label.Name = "Row"
	label.LayoutOrder = rowOrder
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.TextColor3 = FG
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextSize = 13
	label.Font = Enum.Font.SourceSans
	label.Text = text
	label.Parent = scrollArea
end

-- ล้างแถวเก่าก่อนสร้างใหม่ทุกครั้งที่ sync มา — เหลือแค่ UIPadding/UIListLayout/UIFlexItem ไว้
-- (ตัวที่เป็นแถวข้อมูลทั้งหมดตั้งชื่อ "Row" และเป็น TextLabel เท่านั้น กรองแบบนี้พอ)
local function clearRows()
	for _, child in scrollArea:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	rowOrder = 0
end

--------------------------------------------------------------------------------
-- สถานะล่าสุดที่ server ส่งมา (ไว้ให้ปุ่มอ้างอิง)
--------------------------------------------------------------------------------

-- ⚠️ เก็บ **id ประจำฟอง** ไม่ใช่ตำแหน่งในลิสต์
-- ตำแหน่งเลื่อนได้ทุกครั้งที่มีไข่ถูกเอาออกจากกระเป๋า id ไม่เลื่อน
local firstHeldId: number? = nil
local firstPenUid: string? = nil
local firstBagUid: string? = nil

--------------------------------------------------------------------------------
-- ต่อสาย
--------------------------------------------------------------------------------

placeButton.Activated:Connect(function()
	if not firstHeldId then
		return
	end
	-- ⚠️ ส่ง **id ประจำฟอง** ไม่ใช่ชนิดไข่ และไม่ใช่ตำแหน่งในลิสต์
	--   · ชนิดไข่ระบุไม่ได้ — ไข่ชนิดเดียวกันน้ำหนักต่างกันได้
	--   · ตำแหน่งระบุไม่ได้ — ไข่ฟักเสร็จคั่นจังหวะแล้วทั้งแถวเลื่อน เราจะวางผิดฟอง
	placeEggRequest:FireServer(firstHeldId)
end)

toBagButton.Activated:Connect(function()
	if firstPenUid then
		moveMotherRequest:FireServer(firstPenUid, "bag")
	end
end)

toPenButton.Activated:Connect(function()
	if firstBagUid then
		moveMotherRequest:FireServer(firstBagUid, "pen")
	end
end)

farmStateSync.OnClientEvent:Connect(function(payload)
	clearRows()

	-- ── ไข่ในกระเป๋า ──
	-- ⚠️ จุดที่ดูออกว่ากฎ "น้ำหนักมาก่อน" ทำงานถูก: ไข่โชว์น้ำหนักตั้งแต่ยังไม่ฟัก
	--
	-- ⚠️ `payload.heldEggs` เป็น **อาเรย์แน่นของไข่ที่มีจริง** ไม่ใช่อาเรย์ยาวเท่าความจุแล้ว
	-- กระเป๋าจุ 10,000 ฟอง — server ส่งมาให้แค่ส่วนแรกเท่าที่ UI แสดงจริง (heldShown/heldCount)
	-- และแต่ละฟองมี `id` ประจำตัว **ซึ่งเป็นสิ่งเดียวที่ส่งกลับไปหา server ได้**
	firstHeldId = nil
	addSectionHeader(`ไข่ในกระเป๋า: {payload.heldCount}/{payload.bagSize}`)
	if #payload.heldEggs == 0 then
		addRow("  (ไม่มี — แจกด้วยคำสั่ง server: EggService.grantEgg)")
	else
		for _, egg in payload.heldEggs do
			if not firstHeldId then
				firstHeldId = egg.id
			end
			addRow(`  #{egg.id} {egg.eggName} — {egg.weightText}`)
		end
		local more = payload.heldCount - #payload.heldEggs
		if more > 0 then
			addRow(`  ...อีก {more} ฟอง (server ยังไม่ส่งมา กันบวมเน็ต)`)
		end
	end
	placeButton.Text = if firstHeldId then "เอาไข่ฟองแรกเข้าสวนฟัก" else "ไม่มีไข่ให้วาง"

	-- ── สวนฟัก ──
	-- ⚠️ slot.stuck = ครบเวลาฟักแล้วแต่คอก+กระเป๋าเต็มพร้อมกัน (ข้อ D) รอที่ว่างอยู่
	addSectionHeader(`สวนฟัก: {payload.hatchingCount}/{payload.hatcherySize}`)
	local anyHatching = false
	for index = 1, payload.hatcherySize do
		local slot = payload.hatching[index]
		if slot and slot.occupied then
			anyHatching = true
			local status = if slot.stuck then "ค้าง (รอที่ว่าง)" else `เหลือ {math.ceil(slot.remaining)} วิ`
			addRow(`  [{index}] {slot.eggName} {slot.weightText} — {status}`)
		end
	end
	if not anyHatching then
		addRow("  (ว่าง)")
	end

	-- ── แม่ในคอก ──
	firstPenUid = nil
	addSectionHeader(`คอก: {#payload.mothersInPen}/{payload.penCapacity} ตัว`)
	if #payload.mothersInPen == 0 then
		addRow("  (ว่าง)")
	else
		for _, mother in payload.mothersInPen do
			if not firstPenUid then
				firstPenUid = mother.uid
			end
			addRow(`  {mother.charName} ({mother.class}) {mother.weightText}`)
		end
	end

	-- ── แม่ในกระเป๋า ──
	firstBagUid = nil
	addSectionHeader(`กระเป๋า: {#payload.mothersInBag}/{payload.bagCapacity} ตัว`)
	if #payload.mothersInBag == 0 then
		addRow("  (ว่าง)")
	else
		for _, mother in payload.mothersInBag do
			if not firstBagUid then
				firstBagUid = mother.uid
			end
			addRow(`  {mother.charName} ({mother.class}) {mother.weightText}`)
		end
	end
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
