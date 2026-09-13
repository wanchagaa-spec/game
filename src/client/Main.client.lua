--!strict
-- egg-army-game :: Client entry point
--
-- Phase 1: UI ชั่วคราวสำหรับเทสต์ loop เท่านั้น ยังไม่ใช่ UI จริง (Phase 2 ค่อยทำคลัง, Phase 5 ค่อย polish)
-- มีแค่ ปุ่มวางไข่ + สถานะช่องฟัก + ผลที่ฟักได้ล่าสุด
--
-- client ไม่ตัดสินอะไรเองเลย: กดปุ่ม = ส่งคำขอไป server แล้วรอฟังผลกลับมา
-- เวลาที่เห็นบนจอเป็นแค่ค่าที่ server ส่งมา ไม่ได้นับเอง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local placeEggRequest = Remotes.waitFor(Config.RemoteNames.PLACE_EGG_REQUEST)
local eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
local farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)

local defaultEgg = Config.getEgg(Config.DEFAULT_EGG_ID)
assert(defaultEgg, "Client: DEFAULT_EGG_ID ใน Config ชี้ไปที่ไข่ที่ไม่มีอยู่")

--------------------------------------------------------------------------------
-- สร้าง UI
--------------------------------------------------------------------------------

local BG = Color3.fromRGB(28, 30, 36)
local FG = Color3.fromRGB(240, 240, 240)
local ACCENT = Color3.fromRGB(90, 160, 235)

local gui = Instance.new("ScreenGui")
gui.Name = "EggFarmDebugUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(300, 250)
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
	label.TextSize = 15
	label.Font = Enum.Font.SourceSans
	label.Text = text
	label.RichText = false
	label.Parent = panel
	return label
end

local title = makeLabel("Title", 1, 22, "ฟาร์มไข่ (Phase 1 — เทสต์)")
title.TextSize = 18
title.Font = Enum.Font.SourceSansBold

local button = Instance.new("TextButton")
button.Name = "PlaceEggButton"
button.LayoutOrder = 2
button.Size = UDim2.new(1, 0, 0, 36)
button.BackgroundColor3 = ACCENT
button.BorderSizePixel = 0
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.TextSize = 16
button.Font = Enum.Font.SourceSansBold
button.Text = `วาง{defaultEgg.name}`
button.AutoButtonColor = true
button.Parent = panel

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 6)
buttonCorner.Parent = button

local slotsLabel = makeLabel("Slots", 3, 90, "กำลังเชื่อมต่อ...")
local unitsLabel = makeLabel("Units", 4, 20, "ทหารในคลัง: -")
local resultLabel = makeLabel("Result", 5, 44, "ยังไม่ได้ฟักอะไร")
resultLabel.TextWrapped = true

--------------------------------------------------------------------------------
-- ต่อสาย
--------------------------------------------------------------------------------

button.Activated:Connect(function()
	-- ส่งแค่ eggId ปล่อยให้ server เลือกช่องว่างให้เอง
	placeEggRequest:FireServer(Config.DEFAULT_EGG_ID)
end)

farmStateSync.OnClientEvent:Connect(function(payload)
	local lines = {}
	for slotIndex = 1, Config.Farm.EGG_SLOTS_PER_PLAYER do
		local slot = payload.slots[slotIndex]
		if slot and slot.occupied then
			table.insert(lines, `ช่อง {slotIndex}: {slot.eggName} — เหลือ {math.ceil(slot.remaining)} วิ`)
		else
			table.insert(lines, `ช่อง {slotIndex}: ว่าง`)
		end
	end
	slotsLabel.Text = table.concat(lines, "\n")
	unitsLabel.Text = `ทหารในคลัง: {payload.unitCount} ตัว`
end)

eggHatched.OnClientEvent:Connect(function(payload)
	resultLabel.Text = `ฟักช่อง {payload.slotIndex} ได้ {payload.unitName} ({payload.rarity})`
	print(`[Client] ฟักได้ {payload.unitName} rarity {payload.rarity}`)
end)

print("[egg-army-game] client พร้อมแล้ว (Phase 1)")
