--!strict
-- egg-army-game :: ช่องถือของ (Hotbar) ด้านล่างจอ — UI-1
--
-- รอบนี้**ช่องเปล่าเท่านั้น** (ยังไม่มีของ) — ของจริง (อาวุธ/ไข่/แม่/ไอเทม) มาตาม docs/hotbar-design.md
-- ⚠️ แต่ละช่องจะเป็น "ทางลัดชี้ไปที่ของในกระเป๋า" ไม่ใช่ที่เก็บของใหม่ (hotbar-design.md §2)
--
-- มือถือ 5 ช่อง · PC 10 ช่อง (มือถือ = TouchEnabled และไม่มีคีย์บอร์ด) ตัดสินตอนเริ่มและตอนขนาดจอเปลี่ยน
-- PC กดเลข 1–9, 0 เลือกช่อง · กดช่องเดิมซ้ำ = ยกเลิกเลือก (แบบกระเป๋ามาตรฐานของ Roblox)

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UiKit = require(script.Parent:WaitForChild("UiKit"))

local Hotbar = {}

-- ⚠️ สัดส่วนวัดจากภาพต้นแบบ (มือถือแนวนอน 2000×921) — ดู docs/ui-overhaul-plan.md §3
local SLOT_HEIGHT_SCALE = 0.17 -- ของความสูงจอ
local BOTTOM_MARGIN_SCALE = 0.015 -- ของความสูงจอ
local GAP_SCALE = 0.007 -- ของความกว้างจอ
local MOBILE_SLOTS = 5
local PC_SLOTS = 10
local SLOT_COLOR = Color3.fromRGB(58, 58, 58) -- #3A3A3A
local SLOT_TRANSPARENCY = 0.4

local KEY_TO_SLOT: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

local container: Frame
local slots: { TextButton } = {}
local selectedIndex: number? = nil
-- ความกว้าง (pixel) ที่ต้องเว้นไว้ทั้งสองข้างของแถบ — ไม่ให้ทับเลเวลมุมล่างซ้าย/สถิติการรบมุมล่างขวา (PC)
local getReservedSide: () -> number = function()
	return 0
end

local function isMobile(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function refreshHighlight()
	for index, slot in slots do
		local stroke = slot:FindFirstChild("Selected")
		if stroke then
			(stroke :: UIStroke).Enabled = index == selectedIndex
		end
	end
end

local function select(index: number)
	if index > #slots then
		return
	end
	selectedIndex = if selectedIndex == index then nil else index
	refreshHighlight()
end

local function buildSlot(index: number, showNumber: boolean): TextButton
	local slot = UiKit.button({
		Name = `Slot{index}`,
		BackgroundColor3 = SLOT_COLOR,
		BackgroundTransparency = SLOT_TRANSPARENCY,
		AutoButtonColor = true,
	})
	UiKit.corner(slot, UDim.new(0.1, 0))

	-- ไฮไลต์ช่องที่เลือก = ขอบสีรุ้ง (hotbar-design.md §1)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Selected"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = UiKit.WHITE
	stroke.Enabled = false
	local rainbow = Instance.new("UIGradient")
	rainbow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 120)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 170, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 110, 255)),
	})
	rainbow.Parent = stroke
	stroke.Parent = slot

	if showNumber then
		local number = UiKit.label({
			Name = "Number",
			Position = UDim2.fromScale(0.06, 0.04),
			Size = UDim2.fromScale(0.3, 0.26),
			Text = if index == 10 then "0" else tostring(index),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(220, 220, 220),
		})
		UiKit.textStroke(number, 1.5)
		number.Parent = slot
	end

	slot.Activated:Connect(function()
		select(index)
	end)
	slot.Parent = container
	return slot
end

-- สร้างช่องใหม่ตามอุปกรณ์ + วางขนาด/ตำแหน่ง (pixel) จากขนาดจอปัจจุบัน
function Hotbar.relayout()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local count = if isMobile() then MOBILE_SLOTS else PC_SLOTS

	if #slots ~= count then
		for _, slot in slots do
			slot:Destroy()
		end
		table.clear(slots)
		if selectedIndex and selectedIndex > count then
			selectedIndex = nil
		end
		for index = 1, count do
			table.insert(slots, buildSlot(index, count == PC_SLOTS))
		end
		refreshHighlight()
	end

	local gap = viewport.X * GAP_SCALE
	local slotSize = viewport.Y * SLOT_HEIGHT_SCALE
	-- ⚠️ ย่อช่องลงถ้ากว้างเกินที่ว่างตรงกลาง (PC 10 ช่องบนจอ 16:9 กว้างเกินจอ + ต้องไม่ทับของมุมล่างสองฝั่ง)
	local available = viewport.X - 2 * getReservedSide()
	local total = count * slotSize + (count - 1) * gap
	if total > available and available > 0 then
		slotSize = math.max(8, (available - (count - 1) * gap) / count)
		total = count * slotSize + (count - 1) * gap
	end

	container.Size = UDim2.fromOffset(total, slotSize)
	container.Position = UDim2.new(0.5, 0, 1 - BOTTOM_MARGIN_SCALE, 0)
	for index, slot in slots do
		slot.Size = UDim2.fromOffset(slotSize, slotSize)
		slot.Position = UDim2.fromOffset((index - 1) * (slotSize + gap), 0)
	end
end

-- 5D: กรอบของแถบ (แถบเลือดเกาะเหนือกรอบนี้) — เรียกหลัง create
function Hotbar.getFrame(): Frame
	return container
end

function Hotbar.create(parent: ScreenGui, reservedSide: () -> number)
	getReservedSide = reservedSide

	container = UiKit.frame({
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
	})
	container.Parent = parent

	Hotbar.relayout()

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(Hotbar.relayout)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- ⚠️ gameProcessed = กำลังพิมพ์ในแชต/ช่องค้นหา — เลขที่พิมพ์ต้องไม่ไปเลือกช่อง
		if gameProcessed then
			return
		end
		local index = KEY_TO_SLOT[input.KeyCode]
		if index then
			select(index)
		end
	end)
end

return Hotbar
