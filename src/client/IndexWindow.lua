--!strict
-- egg-army-game :: หน้าต่างดัชนี (สมุดสะสมแม่) — UI-4 (เปิดจากปุ่ม 📖 ดัชนี ด้านซ้าย)
--
-- 1 ช่อง = 1 ตัวละคร · คอลัมน์แท็บซ้าย = คลาส เรียงธรรมดา → หายากสุด (C B A S SS · Config.getIndexClasses)
--   ในแท็บเรียงตาม Config.CharacterOrder · ทุกคลาสมีแท็บแม้ยังไม่ได้สักตัว · แท็บบอก "C 2/4"
-- เคยได้ = รูป + ชื่อ + คลาส · ยังไม่เคยได้ = เงาดำ (โมเดลเดียวกันทาดำ · UiKit.setPortrait silhouette) + "???"
-- ข้อมูล "เคยได้" มาจาก sync (`discovered` = PlayerData.discovered ฝั่ง server · ขาย/ตายแล้วยังนับ)
--   charId ที่ไม่มีใน Config แล้ว → ข้ามไปเฉย ๆ ไม่นับ ไม่พัง
-- กดการ์ด → แผงเล็ก: ชื่อ · คลาส · ตัวคูณคลาส · "ตอนนี้มี N ตัว" (นับจากคอก + กระเป๋า + roster ใน sync) · เงา = "ยังไม่เคยได้"
-- จุดแดงบนปุ่มดัชนี: ได้ตัวละครใหม่ครั้งแรกระหว่างเล่น → ขึ้นจนกว่าจะเปิดดัชนี (จำใน client เท่านั้น ไม่เซฟ)
-- ⚠️ virtual grid แบบเดียวกับ BagWindow — ห้ามสร้าง ViewportFrame ทุกช่องพร้อมกัน
-- ⚠️ client ไม่ตัดสินอะไร: แค่แสดงสิ่งที่ server บันทึกไว้

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local IndexWindow = {}

type Entry = {
	charId: string,
	name: string,
	class: string,
	discovered: boolean,
}

type Card = {
	button: TextButton,
	portrait: Frame,
	nameLabel: TextLabel,
	classLabel: TextLabel,
	classStroke: UIStroke,
	entry: Entry?,
}

-- ⚠️ ตำแหน่ง/ขนาดเดียวกับหน้าต่างกระเป๋า (docs/ui-overhaul-plan.md §3) — เปิดได้ทีละหน้าต่างอยู่แล้ว
local WINDOW_POSITION = UDim2.fromScale(0.235, 0.28)
local WINDOW_SIZE = UDim2.fromScale(0.484, 0.518)
local TAB_COLUMN_WIDTH = 0.088 -- ของความกว้างหน้าต่าง
local CONTENT_LEFT = 0.096
local TAB_STEP = 0.19 -- ระยะแท็บต่อแท็บ (ของความสูงหน้าต่าง) — 5 คลาสพอดีคอลัมน์ (5 × 0.19 < 1)
local COLUMNS = 5
local CARD_GAP_RATIO = 0.018 -- ของความกว้างตาราง
local CARD_HEIGHT_RATIO = 1.22 -- การ์ดสูงกว่ากว้าง: บรรทัดคลาสอยู่ใต้ชื่อ

local CONTENT_COLOR = Color3.fromRGB(70, 58, 44)
local TAB_COLOR = Color3.fromRGB(58, 50, 40)
local CARD_COLOR = Color3.fromRGB(38, 36, 34)
local CARD_SELECTED_COLOR = Color3.fromRGB(78, 70, 56)
local NEW_BADGE_COLOR = Color3.fromRGB(235, 45, 45)
local HINT_COLOR = Color3.fromRGB(225, 215, 195)

local window: Frame
local tabButtons: { [string]: TextButton } = {}
local scroll: ScrollingFrame
local totalLabel: TextLabel
local detail: Frame
local detailPortrait: Frame
local detailTitle: TextLabel
local detailInfo: TextLabel

local lastPayload: any = nil
local classes: { string } = Config.getIndexClasses()
local activeClass: string = classes[1]
local entries: { Entry } = {}
local pool: { Card } = {}
local selectedCharId: string? = nil

-- ตัวละครที่เคยได้ตาม sync ล่าสุด · known = ชุดก่อนหน้า ใช้จับ "ได้ตัวใหม่" (nil = ยังไม่เคยมี sync — ชุดแรกไม่นับว่าใหม่)
local discoveredSet: { [string]: boolean } = {}
local knownDiscovered: { [string]: boolean }? = nil
local hasNew = false
local badges: { GuiObject } = {}

--------------------------------------------------------------------------------
-- ข้อมูล
--------------------------------------------------------------------------------

local function buildEntries(classId: string): { Entry }
	local list: { Entry } = {}
	for _, charId in Config.getIndexCharacters(classId) do
		local character = Config.getCharacter(charId)
		if character then
			table.insert(list, {
				charId = charId,
				name = character.name,
				class = character.class,
				discovered = discoveredSet[charId] == true,
			})
		end
	end
	return list
end

-- (เก็บแล้ว, ทั้งหมด) ของคลาสนั้น · classId = nil = ทุกคลาสรวมกัน
-- ⚠️ นับเฉพาะตัวละครที่มีใน Config (ดัชนี) — charId แปลกใน discovered ไม่ทำให้ "เก็บแล้ว" เกิน "ทั้งหมด"
function IndexWindow.getProgress(classId: string?): (number, number)
	local got, total = 0, 0
	for _, id in classes do
		if classId == nil or classId == id then
			for _, charId in Config.getIndexCharacters(id) do
				total += 1
				if discoveredSet[charId] then
					got += 1
				end
			end
		end
	end
	return got, total
end

-- แม่ตัวละครนี้ที่มีอยู่ตอนนี้ (คอก + กระเป๋า + roster) — ขาย/ตายไปแล้วไม่นับ
function IndexWindow.ownedCount(charId: string): number
	local payload = lastPayload
	if not payload then
		return 0
	end
	local count = 0
	for _, list in { payload.mothersInPen or {}, payload.mothersInBag or {}, payload.battleRoster or {} } do
		for _, mother in list do
			if mother.charId == charId then
				count += 1
			end
		end
	end
	return count
end

function IndexWindow.hasNewDiscovery(): boolean
	return hasNew
end

local function refreshBadges()
	for _, badge in badges do
		badge.Visible = hasNew
	end
end

--------------------------------------------------------------------------------
-- การ์ด (pool ใช้ซ้ำ)
--------------------------------------------------------------------------------

local layoutGrid: () -> ()
local renderDetail: () -> ()

local function createCard(): Card
	local button = UiKit.button({
		Name = "Card",
		BackgroundColor3 = CARD_COLOR,
		BackgroundTransparency = 0.1,
		AutoButtonColor = true,
		Visible = false,
	})
	UiKit.corner(button, UDim.new(0.08, 0))
	-- ขอบการ์ดสีตามคลาส (ทั้งตัวที่เคยได้และเงา)
	local classStroke = UiKit.border(button, UiKit.CLASS_COLORS.C, 3)
	classStroke.Name = "ClassBorder"

	local portrait = UiKit.frame({
		Name = "PortraitHolder",
		Position = UDim2.fromScale(0.08, 0.04),
		Size = UDim2.fromScale(0.84, 0.56),
		BackgroundTransparency = 1,
	})
	portrait.Parent = button

	local nameLabel = UiKit.label({
		Name = "NameLabel",
		Position = UDim2.fromScale(0.04, 0.62),
		Size = UDim2.fromScale(0.92, 0.2),
		TextWrapped = true,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(nameLabel, 1.5)
	UiKit.maxTextSize(nameLabel, 18)
	nameLabel.Parent = button

	local classLabel = UiKit.label({
		Name = "ClassLabel",
		Position = UDim2.fromScale(0.04, 0.82),
		Size = UDim2.fromScale(0.92, 0.15),
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(classLabel, 1.5)
	classLabel.Parent = button

	local card: Card = {
		button = button,
		portrait = portrait,
		nameLabel = nameLabel,
		classLabel = classLabel,
		classStroke = classStroke,
		entry = nil,
	}

	button.Activated:Connect(function()
		local entry = card.entry
		if not entry then
			return
		end
		-- กดการ์ดเดิมซ้ำ = ปิดแผง
		selectedCharId = if selectedCharId == entry.charId then nil else entry.charId
		renderDetail()
		layoutGrid()
	end)

	button.Parent = scroll
	return card
end

local function bindCard(card: Card, entry: Entry)
	card.entry = entry
	local classColor = UiKit.CLASS_COLORS[entry.class] or UiKit.CLASS_COLORS.C
	card.classStroke.Color = classColor
	card.button.BackgroundColor3 = if selectedCharId == entry.charId then CARD_SELECTED_COLOR else CARD_COLOR
	UiKit.setPortrait(card.portrait, entry.charId, entry.class, not entry.discovered)
	card.nameLabel.Text = if entry.discovered then entry.name else "???"
	card.classLabel.Text = if entry.discovered then `คลาส {entry.class}` else ""
	card.classLabel.TextColor3 = classColor
end

-- ⚠️ virtual grid: วางการ์ดเท่าที่มองเห็น + 1 แถว · เลื่อน = ผูกการ์ดใน pool กับรายการใหม่
layoutGrid = function()
	local width = scroll.AbsoluteSize.X - scroll.ScrollBarThickness
	local height = scroll.AbsoluteSize.Y
	if width <= 0 or height <= 0 then
		return -- หน้าต่างยังปิดอยู่ — จะเรียกซ้ำเองตอนขนาดเปลี่ยน/เปิดหน้าต่าง
	end

	local gap = width * CARD_GAP_RATIO
	local cardWidth = (width - gap * (COLUMNS + 1)) / COLUMNS
	local cardHeight = cardWidth * CARD_HEIGHT_RATIO
	local rowHeight = cardHeight + gap
	local rows = math.ceil(#entries / COLUMNS)
	scroll.CanvasSize = UDim2.fromOffset(0, rows * rowHeight + gap)

	local visibleRows = math.ceil(height / rowHeight) + 1
	local maxFirstRow = math.max(0, rows - visibleRows + 1)
	local firstRow = math.clamp(math.floor(scroll.CanvasPosition.Y / rowHeight), 0, maxFirstRow)
	-- ⚠️ สร้างการ์ดเท่าที่จำเป็นจริง (คลาสใหญ่สุดตอนนี้มี 4 ตัว = ไม่ถึงแถวเดียว)
	local needed = math.min(visibleRows * COLUMNS, #entries)
	while #pool < needed do
		table.insert(pool, createCard())
	end

	for slotIndex, card in pool do
		local itemIndex = firstRow * COLUMNS + slotIndex
		local entry = if slotIndex <= needed then entries[itemIndex] else nil
		if entry then
			local row = (itemIndex - 1) // COLUMNS
			local column = (itemIndex - 1) % COLUMNS
			card.button.Size = UDim2.fromOffset(cardWidth, cardHeight)
			card.button.Position = UDim2.fromOffset(gap + column * (cardWidth + gap), gap + row * rowHeight)
			bindCard(card, entry)
			card.button.Visible = true
		else
			card.entry = nil
			card.button.Visible = false
		end
	end
end

--------------------------------------------------------------------------------
-- แผงรายละเอียด
--------------------------------------------------------------------------------

renderDetail = function()
	local charId = selectedCharId
	local character = if charId then Config.getCharacter(charId) else nil
	if not charId or not character then
		selectedCharId = nil
		detail.Visible = false
		return
	end
	detail.Visible = true
	local found = discoveredSet[charId] == true
	UiKit.setPortrait(detailPortrait, charId, character.class, not found)
	if not found then
		detailTitle.Text = "???"
		detailInfo.Text = "ยังไม่เคยได้"
		return
	end
	detailTitle.Text = character.name
	local classInfo = Config.getCharacterClass(character.class)
	local multiplier = if classInfo then ` · ×{classInfo.multiplier}` else ""
	detailInfo.Text = `คลาส {character.class}{multiplier}\nตอนนี้มี {IndexWindow.ownedCount(charId)} ตัว`
end

--------------------------------------------------------------------------------
-- ส่วนหัว / แท็บ
--------------------------------------------------------------------------------

local function refreshHeader()
	local got, total = IndexWindow.getProgress(nil)
	totalLabel.Text = `เก็บแล้ว {got}/{total}`
	for classId, button in tabButtons do
		local caption = button:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			local classGot, classTotal = IndexWindow.getProgress(classId)
			caption.Text = `{classId} {classGot}/{classTotal}`
		end
	end
end

local function refreshAll()
	entries = buildEntries(activeClass)
	refreshHeader()
	renderDetail()
	layoutGrid()
end

function IndexWindow.setTab(classId: string)
	activeClass = classId
	selectedCharId = nil
	for name, button in tabButtons do
		local stroke = button:FindFirstChild("Selected")
		if stroke then
			(stroke :: UIStroke).Enabled = name == classId
		end
	end
	scroll.CanvasPosition = Vector2.zero
	refreshAll()
end

local function makeTabButton(classId: string, order: number): TextButton
	local classColor = UiKit.CLASS_COLORS[classId] or UiKit.CLASS_COLORS.C
	local button = UiKit.button({
		Name = `Tab_{classId}`,
		Position = UDim2.new(0, 0, (order - 1) * TAB_STEP, 0),
		Size = UDim2.fromScale(1, 0.17),
		BackgroundColor3 = TAB_COLOR,
		BackgroundTransparency = 0.15,
		Text = "",
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = button
	UiKit.corner(button, UDim.new(0.14, 0))
	local stroke = UiKit.border(button, UiKit.WHITE, 3)
	stroke.Name = "Selected"
	stroke.Enabled = classId == activeClass

	-- "C 2/4" — จำนวนเก็บแล้วของคลาสนี้ (อัปเดตทุก sync)
	local caption = UiKit.label({
		Name = "Caption",
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.9, 0.26),
		Text = classId,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(caption, 1)
	caption.Parent = button

	-- ไอคอนคลาส: สี่เหลี่ยมสีคลาส + ตัวอักษร (รูปทรงง่าย ๆ ไม่ใช้ asset)
	local chip = UiKit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromScale(0.56, 0.56),
		BackgroundColor3 = classColor,
	})
	UiKit.corner(chip, UDim.new(0.22, 0))
	UiKit.border(chip, UiKit.BLACK, 2)
	local letter = UiKit.label({
		Size = UDim2.fromScale(1, 1),
		Text = classId,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(letter, 1.5)
	letter.Parent = chip
	chip.Parent = button

	button.Activated:Connect(function()
		IndexWindow.setTab(classId)
	end)
	tabButtons[classId] = button
	return button
end

--------------------------------------------------------------------------------
-- จุดแดงบนปุ่มดัชนี
--------------------------------------------------------------------------------

-- ติดจุดแดง (ชื่อ "NewBadge") ที่มุมขวาบนของปุ่ม · ซ่อนอยู่จนกว่าจะได้ตัวละครใหม่
function IndexWindow.attachBadge(button: GuiObject): Frame
	local badge = UiKit.frame({
		Name = "NewBadge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.95, 0.08),
		Size = UDim2.fromScale(0.2, 0.2),
		BackgroundColor3 = NEW_BADGE_COLOR,
		ZIndex = 10,
		Visible = hasNew,
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = badge
	UiKit.corner(badge, UDim.new(0.5, 0))
	UiKit.border(badge, UiKit.WHITE, 2)
	badge.Parent = button
	table.insert(badges, badge)
	return badge
end

--------------------------------------------------------------------------------
-- สร้างหน้าต่าง
--------------------------------------------------------------------------------

function IndexWindow.create(parent: ScreenGui)
	window = UiKit.frame({
		Name = "IndexWindow",
		Position = WINDOW_POSITION,
		Size = WINDOW_SIZE,
		BackgroundTransparency = 1,
		Visible = false,
	})
	window.Parent = parent

	-- คอลัมน์แท็บซ้าย = คลาส (แบบแท็บกระเป๋า) · 5 คลาสพอดีคอลัมน์
	local tabColumn = UiKit.frame({
		Name = "Tabs",
		Size = UDim2.fromScale(TAB_COLUMN_WIDTH, 1),
		BackgroundTransparency = 1,
	})
	tabColumn.Parent = window
	for order, classId in classes do
		makeTabButton(classId, order).Parent = tabColumn
	end

	local content = UiKit.frame({
		Name = "Content",
		Position = UDim2.fromScale(CONTENT_LEFT, 0),
		Size = UDim2.fromScale(1 - CONTENT_LEFT, 1),
		BackgroundColor3 = CONTENT_COLOR,
		BackgroundTransparency = 0.2,
	})
	UiKit.corner(content, UDim.new(0.03, 0))
	UiKit.border(content, UiKit.BLACK, 2)
	content.Parent = window

	local title = UiKit.label({
		Position = UDim2.fromScale(0.02, 0.025),
		Size = UDim2.fromScale(0.4, 0.085),
		Text = "📖 ดัชนี",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 225, 150),
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(title, 1.5)
	title.Parent = content

	totalLabel = UiKit.label({
		Name = "Total",
		Position = UDim2.fromScale(0.02, 0.11),
		Size = UDim2.fromScale(0.6, 0.06),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = HINT_COLOR,
	})
	UiKit.textStroke(totalLabel, 1)
	totalLabel.Parent = content

	local closeButton = UiKit.button({
		Name = "Close",
		Position = UDim2.fromScale(0.935, 0.03),
		Size = UDim2.fromScale(0.05, 0.085),
		BackgroundColor3 = Color3.fromRGB(200, 60, 60),
		Text = "✕",
	})
	UiKit.corner(closeButton, UDim.new(0.25, 0))
	UiKit.textStroke(closeButton, 1)
	closeButton.Parent = content
	closeButton.Activated:Connect(function()
		IndexWindow.close()
	end)

	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Position = UDim2.fromScale(0.015, 0.19)
	scroll.Size = UDim2.fromScale(0.97, 0.79)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = content

	-- แผงเล็ก: ทับด้านขวาล่างของพื้นที่เนื้อหา
	detail = UiKit.frame({
		Name = "Detail",
		Position = UDim2.fromScale(0.62, 0.3),
		Size = UDim2.fromScale(0.36, 0.66),
		BackgroundColor3 = Color3.fromRGB(30, 26, 22),
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 5,
	})
	UiKit.corner(detail, UDim.new(0.05, 0))
	UiKit.border(detail, UiKit.BLACK, 2)
	detail.Parent = content

	detailPortrait = UiKit.frame({
		Name = "PortraitHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.5, 0.4),
		BackgroundTransparency = 1,
		ZIndex = 6,
	})
	local portraitAspect = Instance.new("UIAspectRatioConstraint")
	portraitAspect.AspectRatio = 1
	portraitAspect.Parent = detailPortrait
	detailPortrait.Parent = detail

	detailTitle = UiKit.label({
		Name = "Title",
		Position = UDim2.fromScale(0.05, 0.48),
		Size = UDim2.fromScale(0.9, 0.14),
		FontFace = UiKit.FONT_HEAVY,
		ZIndex = 6,
	})
	UiKit.textStroke(detailTitle, 1.5)
	detailTitle.Parent = detail

	detailInfo = UiKit.label({
		Name = "Info",
		Position = UDim2.fromScale(0.07, 0.64),
		Size = UDim2.fromScale(0.86, 0.3),
		TextColor3 = HINT_COLOR,
		ZIndex = 6,
	})
	UiKit.maxTextSize(detailInfo, 20)
	detailInfo.Parent = detail

	local detailClose = UiKit.button({
		Name = "CloseDetail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.02),
		Size = UDim2.fromScale(0.14, 0.1),
		BackgroundColor3 = Color3.fromRGB(80, 80, 80),
		Text = "✕",
		ZIndex = 7,
	})
	UiKit.corner(detailClose, UDim.new(0.3, 0))
	detailClose.Parent = detail
	detailClose.Activated:Connect(function()
		selectedCharId = nil
		renderDetail()
		layoutGrid()
	end)

	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(layoutGrid)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid)
	refreshHeader()
end

-- ⚠️ เรียกทุก sync — จับ "ได้ตัวละครใหม่" จากการเทียบกับชุดก่อนหน้า (ชุดแรกหลังเข้าเกมไม่นับว่าใหม่)
function IndexWindow.setPayload(payload: any)
	lastPayload = payload
	local current: { [string]: boolean } = {}
	for _, charId in payload.discovered or {} do
		current[charId] = true
	end
	local known = knownDiscovered
	if known and not window.Visible then
		for charId in current do
			-- charId ที่ไม่มีใน Config ไม่นับเป็นของใหม่ (ไม่มีช่องในดัชนีให้ดู)
			if not known[charId] and Config.getCharacter(charId) then
				hasNew = true
			end
		end
	end
	knownDiscovered = current
	discoveredSet = current
	refreshBadges()
	if window.Visible then
		refreshAll()
	else
		refreshHeader()
	end
end

function IndexWindow.isOpen(): boolean
	return window.Visible
end

-- เปิด = ล้างจุดแดง (เห็นแล้ว)
function IndexWindow.open()
	window.Visible = true
	hasNew = false
	refreshBadges()
	refreshAll()
end

function IndexWindow.close()
	window.Visible = false
	selectedCharId = nil
	detail.Visible = false
end

return IndexWindow
