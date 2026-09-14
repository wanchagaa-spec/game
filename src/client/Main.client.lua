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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local placeEggRequest = Remotes.waitFor(Config.RemoteNames.PLACE_EGG_IN_HATCHERY_REQUEST)
local moveMotherRequest = Remotes.waitFor(Config.RemoteNames.MOVE_MOTHER_REQUEST)
local eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
local farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)

--------------------------------------------------------------------------------
-- สร้าง UI
--------------------------------------------------------------------------------

local BG = Color3.fromRGB(28, 30, 36)
local FG = Color3.fromRGB(240, 240, 240)
local DIM = Color3.fromRGB(160, 165, 175)
local ACCENT = Color3.fromRGB(90, 160, 235)

local gui = Instance.new("ScreenGui")
gui.Name = "EggFarmDebugUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(360, 420)
panel.Position = UDim2.new(0, 16, 0, 16)
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = panel

local function makeLabel(name: string, order: number, height: number, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.TextColor3 = FG
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextSize = 14
	label.Font = Enum.Font.SourceSans
	label.Text = text
	label.RichText = false
	label.Parent = panel
	return label
end

local function makeButton(name: string, order: number, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 32)
	button.BackgroundColor3 = ACCENT
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 15
	button.Font = Enum.Font.SourceSansBold
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = panel

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button

	return button
end

local title = makeLabel("Title", 1, 22, "ฟาร์มไข่ (Phase 1.5 — เทสต์)")
title.TextSize = 18
title.Font = Enum.Font.SourceSansBold

local heldLabel = makeLabel("HeldEggs", 2, 72, "กำลังเชื่อมต่อ...")
local placeButton = makeButton("PlaceEgg", 3, "เอาไข่ฟองแรกเข้าสวนฟัก")
local hatchingLabel = makeLabel("Hatching", 4, 72, "สวนฟัก: -")
local penLabel = makeLabel("Pen", 5, 74, "คอก: -")
local bagLabel = makeLabel("Bag", 6, 40, "กระเป๋า: -")

local toBagButton = makeButton("ToBag", 7, "ย้ายแม่ตัวแรกในคอก → กระเป๋า")
local toPenButton = makeButton("ToPen", 8, "ย้ายแม่ตัวแรกในกระเป๋า → คอก")

local resultLabel = makeLabel("Result", 9, 40, "ยังไม่ได้ฟักอะไร")
resultLabel.TextWrapped = true
resultLabel.TextColor3 = DIM

--------------------------------------------------------------------------------
-- สถานะล่าสุดที่ server ส่งมา (ไว้ให้ปุ่มอ้างอิง)
--------------------------------------------------------------------------------

local firstHeldIndex: number? = nil
local firstPenUid: string? = nil
local firstBagUid: string? = nil

--------------------------------------------------------------------------------
-- ต่อสาย
--------------------------------------------------------------------------------

placeButton.Activated:Connect(function()
	if not firstHeldIndex then
		return
	end
	-- ⚠️ ส่ง "ตำแหน่งไข่ใน heldEggs" ไม่ใช่ชนิดไข่
	-- ไข่ชนิดเดียวกันน้ำหนักต่างกันได้ ระบุด้วยชนิดไม่ได้
	placeEggRequest:FireServer(firstHeldIndex)
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
	-- ── ไข่ในกระเป๋า ──
	-- ⚠️ จุดที่ดูออกว่ากฎ "น้ำหนักมาก่อน" ทำงานถูก: ไข่โชว์น้ำหนักตั้งแต่ยังไม่ฟัก
	firstHeldIndex = nil
	local heldLines = {}
	-- ⚠️ กระเป๋าไข่กับสวนฟักยาวไม่เท่ากันได้แล้ว ใช้ขนาดของใครของมัน
	for index = 1, payload.bagSize do
		local egg = payload.heldEggs[index]
		if egg and egg.occupied then
			if not firstHeldIndex then
				firstHeldIndex = index
			end
			if #heldLines < 3 then
				table.insert(heldLines, `  [{index}] {egg.eggName} — {egg.weightText}`)
			end
		end
	end
	if #heldLines == 0 then
		heldLabel.Text = `ไข่ในกระเป๋า: ไม่มี (0/{payload.bagSize})\n  (แจกด้วยคำสั่ง server: EggService.grantEgg)`
	else
		local more = payload.heldCount - #heldLines
		heldLabel.Text = `ไข่ในกระเป๋า: {payload.heldCount}/{payload.bagSize} ฟอง\n`
			.. table.concat(heldLines, "\n")
			.. (if more > 0 then `\n  ...อีก {more} ฟอง` else "")
	end
	placeButton.Text = if firstHeldIndex then "เอาไข่ฟองแรกเข้าสวนฟัก" else "ไม่มีไข่ให้วาง"

	-- ── สวนฟัก ──
	local hatchLines = {}
	for index = 1, payload.hatcherySize do
		local slot = payload.hatching[index]
		if slot and slot.occupied and #hatchLines < 3 then
			table.insert(
				hatchLines,
				`  [{index}] {slot.eggName} {slot.weightText} — เหลือ {math.ceil(slot.remaining)} วิ`
			)
		end
	end
	if #hatchLines == 0 then
		hatchingLabel.Text = `สวนฟัก: ว่าง (0/{payload.hatcherySize})`
	else
		local more = payload.hatchingCount - #hatchLines
		hatchingLabel.Text = `สวนฟัก: {payload.hatchingCount}/{payload.hatcherySize}\n`
			.. table.concat(hatchLines, "\n")
			.. (if more > 0 then `\n  ...อีก {more} ฟอง` else "")
	end

	-- ── แม่ในคอก ──
	firstPenUid = nil
	local penLines = {}
	for _, mother in payload.mothersInPen do
		if not firstPenUid then
			firstPenUid = mother.uid
		end
		if #penLines < 3 then
			table.insert(penLines, `  {mother.charName} ({mother.class}) {mother.weightText}`)
		end
	end
	penLabel.Text = `คอก: {#payload.mothersInPen}/{payload.penCapacity} ตัว`
		.. (if #penLines > 0 then "\n" .. table.concat(penLines, "\n") else "\n  (ว่าง)")

	-- ── แม่ในกระเป๋า ──
	firstBagUid = nil
	for _, mother in payload.mothersInBag do
		firstBagUid = mother.uid
		break
	end
	bagLabel.Text = `กระเป๋า: {#payload.mothersInBag}/{payload.bagCapacity} ตัว`
		.. (if firstBagUid then `\n  ตัวแรก: {payload.mothersInBag[1].charName} {payload.mothersInBag[1].weightText}` else "")
end)

eggHatched.OnClientEvent:Connect(function(payload)
	local place = if payload.placedIn == "pen" then "เข้าคอก" else "เข้ากระเป๋า"
	resultLabel.Text = `ฟักช่อง {payload.slotIndex} ได้ {payload.charName} ({payload.class}) {payload.weightText} → {place}`
	print(`[Client] ฟักได้ {payload.charName} คลาส {payload.class} น้ำหนัก {payload.weightText}`)
end)

print("[egg-army-game] client พร้อมแล้ว (Phase 1.5)")
