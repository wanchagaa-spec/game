--!strict
-- egg-army-game :: ชุดเครื่องมือสร้าง UI ที่ใช้ร่วมกันฝั่ง client (UI-1)
--
-- ของที่หลายโมดูลใช้ซ้ำ: ฟอนต์ · สีตามคลาส · มุมโค้ง/ขอบ · ข้อความขอบดำ · รูปตัวละคร/ไข่ · ตัวจัดรูปแบบตัวเลข
-- ⚠️ รูปตัวละครทำเองจากโมเดลของเกมเราเท่านั้น (ViewportFrame) — ห้ามอ้าง asset ของเกมอื่น
-- (ดู docs/ui-overhaul-plan.md)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local UiKit = {}

local FONT_FAMILY = "rbxasset://fonts/families/BuilderSans.json"
UiKit.FONT_BOLD = Font.new(FONT_FAMILY, Enum.FontWeight.Bold)
UiKit.FONT_HEAVY = Font.new(FONT_FAMILY, Enum.FontWeight.ExtraBold)
-- ⚠️ ตัวเอียงขึ้นกับว่าฟอนต์มีแบบเอียงไหม — ไม่มีก็แสดงตัวตรง (ไม่ error)
UiKit.FONT_HEAVY_ITALIC = Font.new(FONT_FAMILY, Enum.FontWeight.ExtraBold, Enum.FontStyle.Italic)

UiKit.WHITE = Color3.fromRGB(255, 255, 255)
UiKit.BLACK = Color3.fromRGB(0, 0, 0)
UiKit.DISABLED = Color3.fromRGB(110, 110, 110)
UiKit.SILHOUETTE = Color3.fromRGB(12, 12, 14) -- เงาดำของตัวที่ยังไม่เคยได้ (ดัชนี UI-4)

-- ชุดเดียวกับ PenService ที่วาดแม่ในโลกจริง (กล่องสี) เพื่อให้ตรงกัน
UiKit.CLASS_COLORS = {
	SS = Color3.fromRGB(240, 185, 60),
	S = Color3.fromRGB(190, 110, 235),
	A = Color3.fromRGB(230, 110, 90),
	B = Color3.fromRGB(120, 215, 180),
	C = Color3.fromRGB(200, 200, 190),
} :: { [string]: Color3 }

-- Folder ที่ PenService (server) ใส่สำเนาโมเดลตัวละครไว้ให้วาดรูป — ชื่อต้องตรงกับฝั่ง server
local PORTRAIT_TEMPLATE_FOLDER = "MotherModelTemplates"

--------------------------------------------------------------------------------
-- ตัวช่วยสร้าง Instance
--------------------------------------------------------------------------------

local function apply(instance: Instance, props: { [string]: any }?)
	if props then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
end

function UiKit.frame(props: { [string]: any }?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	apply(frame, props)
	return frame
end

function UiKit.label(props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextColor3 = UiKit.WHITE
	label.FontFace = UiKit.FONT_BOLD
	label.TextScaled = true
	label.Text = ""
	apply(label, props)
	return label
end

function UiKit.button(props: { [string]: any }?): TextButton
	local button = Instance.new("TextButton")
	button.BorderSizePixel = 0
	button.TextColor3 = UiKit.WHITE
	button.FontFace = UiKit.FONT_HEAVY
	button.TextScaled = true
	button.AutoButtonColor = true
	button.Text = ""
	apply(button, props)
	return button
end

-- มุมโค้ง: ตัวเลข = pixel · UDim = ส่งตรง (เช่น UDim.new(0.5, 0) = วงกลม/วงรี)
function UiKit.corner(parent: GuiObject, radius: number | UDim): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius :: number)
	corner.Parent = parent
	return corner
end

-- ขอบรอบกรอบ (ไม่ใช่ขอบตัวอักษร)
function UiKit.border(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

-- ขอบดำรอบตัวอักษร (ตัวขาวขอบดำตามต้นแบบ)
function UiKit.textStroke(parent: TextLabel | TextButton | TextBox, thickness: number, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = color or UiKit.BLACK
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

-- เพดานขนาดตัวอักษรของ TextScaled — ไม่งั้นข้อความสั้นโตล้นกรอบบนจอใหญ่
function UiKit.maxTextSize(parent: TextLabel | TextButton | TextBox, maxSize: number, minSize: number?)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.MinTextSize = minSize or 1
	constraint.Parent = parent
end

-- ══ ProximityPrompt ══ ⚠️ **ทุก prompt ในเกมต้องสร้างผ่านฟังก์ชันนี้** (tools/check-prompt-exclusivity.py ตรวจ)
-- Exclusivity = OnePerButton: ป้าย/จุดกดที่อยู่ใกล้กันขึ้นเฉพาะอันที่ใกล้ที่สุดต่อปุ่ม (UI-2 ตัดสิน · ใช้กับแท่นอัญเชิญ UI-3 ด้วย)
-- ค่าตั้งต้น: กดครั้งเดียว (HoldDuration 0) · ไม่ต้องมองเห็นตรง ๆ (เสาป้ายบังได้) · props ทับค่าอื่นได้ ยกเว้น Exclusivity
function UiKit.prompt(props: { [string]: any }?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	apply(prompt, props)
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	return prompt
end

function UiKit.padding(parent: GuiObject, scale: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(scale, 0)
	padding.PaddingBottom = UDim.new(scale, 0)
	padding.PaddingLeft = UDim.new(scale, 0)
	padding.PaddingRight = UDim.new(scale, 0)
	padding.Parent = parent
end

--------------------------------------------------------------------------------
-- ตัวเลข / เวลา
--------------------------------------------------------------------------------

local SHORT_SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234 → "1.2K" · 5_000_000 → "5M" (ย่อสำหรับที่แคบ — ยอดเงินหลักยังโชว์เต็มตามเดิม)
function UiKit.formatShort(value: number): string
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	local tier = 1
	while n >= 1000 and tier < #SHORT_SUFFIXES do
		n /= 1000
		tier += 1
	end
	local text = if n >= 100 or tier == 1 then string.format("%d", math.floor(n)) else string.format("%.1f", n)
	text = string.gsub(text, "%.0$", "")
	return sign .. text .. SHORT_SUFFIXES[tier]
end

-- 1234567 → "1,234,567" (จำนวนเต็มเต็มหลัก — ใช้ตอนต้องเทียบยอดเงินได้ตรงตัว เช่น ราคารวมที่ร้านขายแม่)
function UiKit.formatComma(value: number): string
	local sign = if value < 0 then "-" else ""
	local digits = string.format("%d", math.abs(math.floor(value)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return sign .. (string.gsub(grouped, "^,", ""))
end

-- วินาที → "2h 23m" · "5m 03s" · "45s"
function UiKit.formatDuration(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local secs = total % 60
	if hours > 0 then
		return `{hours}h {minutes}m`
	elseif minutes > 0 then
		return string.format("%dm %02ds", minutes, secs)
	end
	return `{secs}s`
end

--------------------------------------------------------------------------------
-- รูปตัวละคร / ไข่
--------------------------------------------------------------------------------

-- ต้นแบบโมเดลของตัวละคร — ชื่อจาก Config.getMotherTemplateName (mesh = เลข asset · ประกอบจาก Part = charId)
local function findTemplate(charId: string): Model?
	if not Config.getCharacter(charId) then
		return nil
	end
	local folder = ReplicatedStorage:FindFirstChild(PORTRAIT_TEMPLATE_FOLDER)
	local template = if folder then folder:FindFirstChild(Config.getMotherTemplateName(charId)) else nil
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

-- ══ กล้องรูปตัวละคร ══ มุมเฉียง 3/4 (หันมาทางซ้ายของตัวละคร + เงยลงเล็กน้อย) ให้เห็นทั้งหน้าและลำตัว
-- (หน้าตรงเห็นปลา/ม้าแค่หัว) · ถอยให้ **ทรงกลมล้อมกล่องทั้งก้อนอยู่ในกรอบ** เสมอ → ตัวใหญ่/ยาวแค่ไหนก็ไม่ล้นการ์ด
UiKit.PORTRAIT_FOV = 30 -- องศา (แนวตั้ง · การ์ดเป็นสี่เหลี่ยมจัตุรัส แนวนอนเท่ากัน)
UiKit.PORTRAIT_YAW = 30 -- องศา จากหน้าตรงไปทางซ้ายของตัวละคร
UiKit.PORTRAIT_PITCH = 12 -- องศา มองลงจากด้านบนเล็กน้อย
UiKit.PORTRAIT_PADDING = 1.04 -- เผื่อขอบ

-- ทิศจากกลางตัวไปหากล้อง (หน่วย) + ระยะ — facing/right = LookVector/RightVector ของ pivot โมเดล
-- ⚠️ ระยะ = รัศมีทรงกลมล้อมกล่อง ÷ sin(ครึ่งมุมมอง) (ไม่ใช่ tan — tan ให้ขอบทรงกลมเกินกรอบนิดหนึ่ง)
function UiKit.getPortraitCamera(boxSize: Vector3, facing: Vector3, right: Vector3): (Vector3, number)
	local yaw, pitch = math.rad(UiKit.PORTRAIT_YAW), math.rad(UiKit.PORTRAIT_PITCH)
	local horizontal = facing * math.cos(yaw) + right * -math.sin(yaw)
	local direction = horizontal * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
	local radius = boxSize.Magnitude / 2
	local distance = radius * UiKit.PORTRAIT_PADDING / math.sin(math.rad(UiKit.PORTRAIT_FOV / 2))
	return direction, distance
end

local function clearPortrait(holder: GuiObject)
	for _, child in holder:GetChildren() do
		if child.Name == "Portrait" then
			child:Destroy()
		end
	end
end

-- วาดรูปตัวละครลงใน holder — ⚠️ วาดใหม่เฉพาะตอนตัวละครเปลี่ยน/โมเดลเพิ่งโหลดเสร็จ (เช็คจาก attribute)
-- เรียกซ้ำทุก sync ได้โดยไม่สร้าง ViewportFrame ใหม่ทุกครั้ง
-- มีโมเดล (ReplicatedStorage.MotherModelTemplates) = ViewportFrame · ไม่มี = กล่องสีตามคลาส + ตัวอักษรคลาส
-- silhouette = true (ดัชนี UI-4 · ตัวที่ยังไม่เคยได้): โมเดลเดียวกันทาดำทั้งตัว (ViewportFrame.ImageColor3 = ดำ)
--   · ไม่มีโมเดล = กล่องดำ + "?" (ไม่บอกคลาส)
function UiKit.setPortrait(holder: GuiObject, charId: string, class: string, silhouette: boolean?)
	local template = findTemplate(charId)
	local key = `{charId}:{if template then "model" else "box"}:{if silhouette then "shadow" else "color"}`
	if holder:GetAttribute("PortraitKey") == key then
		return
	end
	holder:SetAttribute("PortraitKey", key)
	clearPortrait(holder)

	if template then
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Portrait"
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.BackgroundTransparency = 1
		viewport.Ambient = Color3.fromRGB(190, 190, 190)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-1, -1, -1)
		if silhouette then
			viewport.ImageColor3 = UiKit.BLACK -- คูณสีทั้งภาพด้วยดำ = เงาดำตามรูปทรงโมเดล
		end

		local model = template:Clone()
		model.Parent = viewport

		-- ⚠️ หันกล้องเข้าหาด้านหน้าของโมเดล (LookVector ของ pivot) แบบเฉียง 3/4 ถอยออกให้พอดีกรอบจากกล่องล้อมรอบ
		local boxCFrame, boxSize = model:GetBoundingBox()
		local camera = Instance.new("Camera")
		camera.FieldOfView = UiKit.PORTRAIT_FOV
		local pivot = model:GetPivot()
		local direction, distance = UiKit.getPortraitCamera(boxSize, pivot.LookVector, pivot.RightVector)
		camera.CFrame = CFrame.lookAt(boxCFrame.Position + direction * distance, boxCFrame.Position)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		viewport.Parent = holder
		return
	end

	local box = UiKit.frame({
		Name = "Portrait",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		BackgroundColor3 = if silhouette then UiKit.SILHOUETTE else (UiKit.CLASS_COLORS[class] or UiKit.CLASS_COLORS.C),
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = box
	UiKit.corner(box, UDim.new(0.18, 0))
	UiKit.border(box, UiKit.BLACK, 2)
	local letter = UiKit.label({
		Size = UDim2.fromScale(1, 1),
		Text = if silhouette then "?" else class,
		TextColor3 = if silhouette then UiKit.DISABLED else UiKit.WHITE,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(letter, 2)
	letter.Parent = box
	box.Parent = holder
end

-- ไข่ = วงรีสีตามชนิดไข่ (EggTypes[eggId].color) — รูปทรงง่าย ๆ ไม่ใช้ asset
function UiKit.setEggIcon(holder: GuiObject, eggId: string)
	local key = `egg:{eggId}`
	if holder:GetAttribute("PortraitKey") == key then
		return
	end
	holder:SetAttribute("PortraitKey", key)
	clearPortrait(holder)

	local eggType = Config.getEgg(eggId)
	local egg = UiKit.frame({
		Name = "Portrait",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.62, 0.82),
		BackgroundColor3 = if eggType and eggType.color then eggType.color else Color3.fromRGB(235, 225, 200),
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.76
	aspect.Parent = egg
	UiKit.corner(egg, UDim.new(0.5, 0))
	UiKit.border(egg, UiKit.BLACK, 2)

	-- จุดแสงสะท้อนเล็ก ๆ ให้ดูเป็นไข่ ไม่ใช่วงรีแบน ๆ
	local shine = UiKit.frame({
		Position = UDim2.fromScale(0.22, 0.16),
		Size = UDim2.fromScale(0.22, 0.18),
		BackgroundColor3 = UiKit.WHITE,
		BackgroundTransparency = 0.45,
	})
	UiKit.corner(shine, UDim.new(0.5, 0))
	shine.Parent = egg
	egg.Parent = holder
end

return UiKit
