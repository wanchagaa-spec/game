--!strict
-- egg-army-game :: แถบเลือดผู้เล่น + จอแดงวาบตอนโดนตี — Phase 5D
--
-- ⚠️ ภาพล้วน — เลือดจริงอยู่ที่ Humanoid.Health ฝั่ง server (BossService: บอสฟาด · ฟื้นเลือด · เกิดใหม่) client แค่อ่านมาโชว์
-- แสดงเหนือ hotbar กึ่งกลาง **เฉพาะตอนอยู่ในสนามรบ หรือเลือดไม่เต็ม** (shouldShow) — อยู่ในลานเลือดเต็ม = ซ่อน
--   · เป็นลูกของกรอบ Hotbar → ขยับตามแถบเสมอ ไม่ทับช่อง hotbar และไม่ทับเลเวลมุมล่างซ้าย (กว้างไม่เกินแถบ hotbar)
--   · สไตล์เดียวกับหลอดการรบกึ่งกลางบน (พื้นเข้ม · มุมมน · ขอบดำ · ตัวหนังสือขอบดำ)
-- เลือดลดลง (โดนตี) → จอแดงวาบสั้น ๆ (ของ Roblox เดิมปิดแล้ว — Main ปิด CoreGuiType.Health กันซ้อนกันสองชุด)
-- "สนามรบ" = นอกเซฟโซน (Config.isInSafeZone) ตัวเดียวกับที่ server ใช้ตัดสินฟื้นเลือด/จุดเกิด

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local HealthBar = {}

-- ขนาด/ระยะคิดจากความสูงจอ (แบบเดียวกับ Hotbar) · ความกว้างไม่เกินแถบ hotbar
local BAR_HEIGHT_SCALE = 0.032 -- ของความสูงจอ
local BAR_WIDTH_SCALE = 0.5 -- ของความสูงจอ (ไม่เกินความกว้างแถบ hotbar)
local BAR_GAP_SCALE = 0.012 -- ช่องว่างเหนือ hotbar (ของความสูงจอ)
local BAR_BG_COLOR = Color3.fromRGB(20, 20, 24) -- เดียวกับหลอดการรบ (Main.client COMBAT_BAR_BG_COLOR)
local FILL_HIGH = Color3.fromRGB(90, 215, 90) -- > 50%
local FILL_MID = Color3.fromRGB(240, 170, 50) -- > 25%
local FILL_LOW = Color3.fromRGB(225, 55, 55)
local FLASH_COLOR = Color3.fromRGB(220, 20, 20)
local FLASH_START_TRANSPARENCY = 0.55
local FLASH_SECONDS = 0.35
local WATCH_INTERVAL = 0.2 -- วินาที — เช็คว่าอยู่สนามรบไหม (ตำแหน่งเปลี่ยนตลอด ไม่มี event)

local bar: Frame? = nil
local fill: Frame? = nil
local text: TextLabel? = nil
local flash: Frame? = nil
local anchor: GuiObject? = nil
local lastHealth: number? = nil
local flashSerial = 0

-- แสดงแถบไหม — อยู่ในสนามรบ หรือเลือดไม่เต็ม (รวมตายแล้ว = 0) · เลือดเต็มเป็น 0 (ยังไม่มีตัวละคร) = ซ่อน
function HealthBar.shouldShow(inBattlefield: boolean, health: number, maxHealth: number): boolean
	if maxHealth <= 0 then
		return false
	end
	return inBattlefield or health < maxHealth
end

-- สีส่วนเติมตามสัดส่วนเลือด
function HealthBar.fillColor(ratio: number): Color3
	if ratio > 0.5 then
		return FILL_HIGH
	elseif ratio > 0.25 then
		return FILL_MID
	end
	return FILL_LOW
end

-- วางแถบเหนือกรอบ hotbar (pixel จากขนาดจอ) — เรียกตอนสร้าง + จอเปลี่ยนขนาด + แถบ hotbar เปลี่ยนขนาด
function HealthBar.relayout()
	local camera = Workspace.CurrentCamera
	if not bar or not anchor or not camera then
		return
	end
	local viewportY = camera.ViewportSize.Y
	local hotbarWidth = anchor.Size.X.Offset
	local width = viewportY * BAR_WIDTH_SCALE
	if hotbarWidth > 0 then
		width = math.min(width, hotbarWidth)
	end
	bar.Size = UDim2.fromOffset(width, viewportY * BAR_HEIGHT_SCALE)
	bar.Position = UDim2.new(0.5, 0, 0, -viewportY * BAR_GAP_SCALE)
end

local function playFlash()
	local overlay = flash
	if not overlay then
		return
	end
	flashSerial += 1
	local serial = flashSerial
	overlay.BackgroundTransparency = FLASH_START_TRANSPARENCY
	overlay.Visible = true
	local ok, TweenService = pcall(function()
		return game:GetService("TweenService")
	end)
	if ok and TweenService then
		(TweenService :: TweenService)
			:Create(overlay, TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			})
			:Play()
	end
	task.delay(FLASH_SECONDS, function()
		if flashSerial == serial then
			overlay.Visible = false
		end
	end)
end

-- อัปเดตแถบจากค่าเลือดปัจจุบัน · คืน true ถ้าจอแดงวาบ (เลือดลดจากครั้งก่อน · ตัวละครเดิม)
function HealthBar.update(health: number, maxHealth: number, inBattlefield: boolean): boolean
	local flashed = lastHealth ~= nil and health < (lastHealth :: number) and health >= 0
	lastHealth = health
	if bar and fill and text then
		bar.Visible = HealthBar.shouldShow(inBattlefield, health, maxHealth)
		local ratio = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = HealthBar.fillColor(ratio)
		text.Text = `❤ {math.ceil(math.max(0, health))} / {math.floor(maxHealth)}`
	end
	if flashed then
		playFlash()
	end
	return flashed
end

-- ตัวละครใหม่ (เกิดใหม่) — ไม่นับเลือดเต็มตอนเกิดเป็นการ "โดนตี" และไม่เทียบกับค่าตอนตาย
function HealthBar.resetTracking()
	lastHealth = nil
end

-- parent = ScreenGui เต็มจอ (จอแดงวาบ) · hotbarFrame = กรอบของ Hotbar (แถบเลือดเป็นลูกของกรอบนี้)
function HealthBar.create(parent: ScreenGui, hotbarFrame: GuiObject)
	anchor = hotbarFrame

	local frame = UiKit.frame({
		Name = "HealthBar",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = BAR_BG_COLOR,
		BackgroundTransparency = 0.35,
		Visible = false,
	})
	UiKit.corner(frame, UDim.new(0.35, 0))
	UiKit.border(frame, UiKit.BLACK, 1.5)
	frame.Parent = hotbarFrame

	local fillFrame = UiKit.frame({
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = FILL_HIGH,
	})
	UiKit.corner(fillFrame, UDim.new(0.35, 0))
	fillFrame.Parent = frame

	local label = UiKit.label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		FontFace = UiKit.FONT_HEAVY,
		ZIndex = 2,
		Text = "",
	})
	UiKit.textStroke(label, 1.5)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = label
	label.Parent = frame

	-- จอแดงวาบ — เต็มจอ ไม่รับคลิก อยู่ใต้หน้าต่างอื่น ๆ
	local overlay = UiKit.frame({
		Name = "HitFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = FLASH_COLOR,
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		ZIndex = 0,
	})
	overlay.Parent = parent

	bar, fill, text, flash = frame, fillFrame, label, overlay
	HealthBar.relayout()

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(HealthBar.relayout)
	end
	hotbarFrame:GetPropertyChangedSignal("Size"):Connect(HealthBar.relayout)
end

-- ต่อกับตัวละครของผู้เล่นคนนี้ (ทุกครั้งที่เกิด) + เฝ้าว่าอยู่สนามรบไหม
function HealthBar.start()
	local player = Players.LocalPlayer
	local humanoid: Humanoid? = nil
	local root: BasePart? = nil

	local function refresh()
		if humanoid then
			local inBattlefield = root ~= nil and not Config.isInSafeZone((root :: BasePart).Position)
			HealthBar.update(humanoid.Health, humanoid.MaxHealth, inBattlefield)
		elseif bar then
			bar.Visible = false
		end
	end

	local function bind(character: Model)
		HealthBar.resetTracking()
		humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if humanoid then
			(humanoid :: Humanoid).HealthChanged:Connect(refresh)
			;(humanoid :: Humanoid):GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
		end
		refresh()
	end

	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(bind, character)
	end)
	if player.Character then
		task.spawn(bind, player.Character)
	end

	task.spawn(function()
		while true do
			task.wait(WATCH_INTERVAL)
			refresh()
		end
	end)
end

return HealthBar
