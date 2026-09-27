--!strict
-- egg-army-game :: หน้าต่างร้านขายแม่ — UI-2 (เปิดจากจุดกด E ที่แผงร้านหลังแมพ · MapSigns.lua)
--
-- ขายได้เฉพาะ**แม่ในกระเป๋า** — กติกาเดิมของ EggService.sellMother (แม่ในคอกต้องถอดออกก่อน)
-- ติ๊กได้หลายตัว → "ขายที่เลือก" → กล่องยืนยันครั้งเดียว (จำนวน + ราคารวม) → ยิง remote ขายเดิมทีละ uid
-- ⚠️ ราคาอ่านจาก sync (mother.sellPrice = Config.getMotherSellPrice ฝั่ง server) — client ไม่คิดราคาเอง
-- ⚠️ แม่ที่ล็อก: การ์ดสีเทา + 🔒 ติ๊กไม่ได้ · server ตรวจล็อกซ้ำเองอยู่แล้ว
-- ⚠️ virtual grid แบบเดียวกับ BagWindow — กระเป๋าจุ 100 ตัว ห้ามสร้าง ViewportFrame ทุกใบพร้อมกัน

local UiKit = require(script.Parent:WaitForChild("UiKit"))

local SellWindow = {}

export type Actions = {
	sellMother: (uid: string) -> (),
	notify: (text: string, ok: boolean) -> (),
}

type Card = {
	button: TextButton,
	portrait: Frame,
	nameLabel: TextLabel,
	priceLabel: TextLabel,
	lockBadge: TextLabel,
	checkBadge: TextLabel,
	lockShade: Frame,
	selectedStroke: UIStroke,
	mother: any?,
}

-- ⚠️ ตำแหน่ง/ขนาดเดียวกับหน้าต่างกระเป๋า (docs/ui-overhaul-plan.md §3) — เปิดได้ทีละหน้าต่างอยู่แล้ว
local WINDOW_POSITION = UDim2.fromScale(0.235, 0.28)
local WINDOW_SIZE = UDim2.fromScale(0.484, 0.518)
local COLUMNS = 5
local CARD_GAP_RATIO = 0.018 -- ของความกว้างตาราง
local CARD_HEIGHT_RATIO = 1.22 -- การ์ดสูงกว่ากว้าง: แถบราคาขายอยู่ใต้ชื่อ

local CONTENT_COLOR = Color3.fromRGB(62, 84, 52)
local CARD_COLOR = Color3.fromRGB(38, 40, 36)
local CARD_SELECTED_COLOR = Color3.fromRGB(72, 92, 64)
local CARD_LOCKED_COLOR = Color3.fromRGB(70, 70, 70)
local SELECTED_COLOR = Color3.fromRGB(90, 220, 90)
local LOCK_COLOR = Color3.fromRGB(120, 110, 170)
local PRICE_COLOR = Color3.fromRGB(255, 220, 90)
local SELL_COLOR = Color3.fromRGB(220, 120, 40)
local SELECT_ALL_COLOR = Color3.fromRGB(60, 150, 230)
local CANCEL_COLOR = Color3.fromRGB(90, 90, 90)

local actions: Actions
local window: Frame
local scroll: ScrollingFrame
local infoLabel: TextLabel
local emptyLabel: TextLabel
local selectAllButton: TextButton
local sellButton: TextButton
local confirm: Frame
local confirmText: TextLabel

local lastPayload: any = nil
local mothers: { any } = {} -- แม่ในกระเป๋า เรียงแล้ว (ที่ไม่ล็อกก่อน · ถูกก่อน)
local pool: { Card } = {}
-- ⚠️ เก็บ uid ไม่ใช่ตำแหน่ง — ลิสต์เปลี่ยนลำดับได้ทุก sync
local selected: { [string]: boolean } = {}

--------------------------------------------------------------------------------
-- ข้อมูล
--------------------------------------------------------------------------------

local function priceOf(mother: any): number
	return mother.sellPrice or 0
end

local function buildList()
	table.clear(mothers)
	local bag = if lastPayload then lastPayload.mothersInBag else {}
	for _, mother in bag do
		table.insert(mothers, mother)
	end
	-- ที่ไม่ล็อกก่อน (ตัวที่ขายได้) · ราคาถูกก่อน (ตัวที่มักจะขายทิ้ง) · uid ให้ลำดับนิ่ง
	table.sort(mothers, function(a: any, b: any)
		local la, lb = a.locked == true, b.locked == true
		if la ~= lb then
			return not la
		end
		if priceOf(a) ~= priceOf(b) then
			return priceOf(a) < priceOf(b)
		end
		return a.uid < b.uid
	end)

	-- ตัดที่เลือกไว้แต่ขายไปแล้ว / ย้ายออก / ถูกล็อกทีหลัง ทิ้ง
	local still: { [string]: boolean } = {}
	for _, mother in mothers do
		if selected[mother.uid] and mother.locked ~= true then
			still[mother.uid] = true
		end
	end
	selected = still
end

-- (จำนวน, ราคารวม, uid ตามลำดับในลิสต์) ของที่ติ๊กไว้ตอนนี้
function SellWindow.getSelection(): (number, number, { string })
	local uids: { string } = {}
	local total = 0
	for _, mother in mothers do
		if selected[mother.uid] then
			table.insert(uids, mother.uid)
			total += priceOf(mother)
		end
	end
	return #uids, total, uids
end

local function unlockedCount(): number
	local count = 0
	for _, mother in mothers do
		if mother.locked ~= true then
			count += 1
		end
	end
	return count
end

--------------------------------------------------------------------------------
-- การ์ด (pool ใช้ซ้ำ)
--------------------------------------------------------------------------------

local layoutGrid: () -> ()
local refreshFooter: () -> ()

local function toggleMother(mother: any)
	if mother.locked == true then
		actions.notify("แม่ตัวนี้ล็อกอยู่ ขายไม่ได้ — ปลดล็อกในกระเป๋าก่อน", false)
		return
	end
	if selected[mother.uid] then
		selected[mother.uid] = nil
	else
		selected[mother.uid] = true
	end
	layoutGrid()
	refreshFooter()
end

local function createCard(): Card
	local button = UiKit.button({
		Name = "Card",
		BackgroundColor3 = CARD_COLOR,
		BackgroundTransparency = 0.1,
		AutoButtonColor = true,
		Visible = false,
	})
	UiKit.corner(button, UDim.new(0.08, 0))
	local selectedStroke = UiKit.border(button, SELECTED_COLOR, 3)
	selectedStroke.Enabled = false

	local portrait = UiKit.frame({
		Name = "PortraitHolder",
		Position = UDim2.fromScale(0.08, 0.03),
		Size = UDim2.fromScale(0.84, 0.52),
		BackgroundTransparency = 1,
	})
	portrait.Parent = button

	local nameLabel = UiKit.label({
		Name = "NameLabel",
		Position = UDim2.fromScale(0.04, 0.56),
		Size = UDim2.fromScale(0.92, 0.24),
		TextWrapped = true,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(nameLabel, 1.5)
	UiKit.maxTextSize(nameLabel, 18)
	nameLabel.Parent = button

	-- ราคาขายใต้การ์ด
	local priceLabel = UiKit.label({
		Name = "PriceLabel",
		Position = UDim2.fromScale(0.04, 0.81),
		Size = UDim2.fromScale(0.92, 0.16),
		TextColor3 = PRICE_COLOR,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(priceLabel, 1.5)
	priceLabel.Parent = button

	-- แม่ที่ล็อก: ทาเทาทับทั้งใบ (ติ๊กไม่ได้)
	local lockShade = UiKit.frame({
		Name = "LockShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiKit.BLACK,
		BackgroundTransparency = 0.45,
		ZIndex = 4,
		Visible = false,
	})
	UiKit.corner(lockShade, UDim.new(0.08, 0))
	lockShade.Parent = button

	local lockBadge = UiKit.label({
		Name = "LockBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.96, 0.03),
		Size = UDim2.fromScale(0.24, 0.17),
		BackgroundColor3 = LOCK_COLOR,
		BackgroundTransparency = 0,
		Text = "🔒",
		ZIndex = 5,
		Visible = false,
	})
	UiKit.corner(lockBadge, UDim.new(0.3, 0))
	lockBadge.Parent = button

	local checkBadge = UiKit.label({
		Name = "CheckBadge",
		Position = UDim2.fromScale(0.04, 0.03),
		Size = UDim2.fromScale(0.24, 0.17),
		BackgroundColor3 = SELECTED_COLOR,
		BackgroundTransparency = 0,
		FontFace = UiKit.FONT_HEAVY,
		Text = "✓",
		ZIndex = 5,
		Visible = false,
	})
	UiKit.corner(checkBadge, UDim.new(0.3, 0))
	UiKit.textStroke(checkBadge, 1)
	checkBadge.Parent = button

	local card: Card = {
		button = button,
		portrait = portrait,
		nameLabel = nameLabel,
		priceLabel = priceLabel,
		lockBadge = lockBadge,
		checkBadge = checkBadge,
		lockShade = lockShade,
		selectedStroke = selectedStroke,
		mother = nil,
	}

	button.Activated:Connect(function()
		if card.mother then
			toggleMother(card.mother)
		end
	end)

	button.Parent = scroll
	return card
end

local function bindCard(card: Card, mother: any)
	card.mother = mother
	local locked = mother.locked == true
	local isSelected = selected[mother.uid] == true
	card.button.BackgroundColor3 = if locked
		then CARD_LOCKED_COLOR
		elseif isSelected then CARD_SELECTED_COLOR
		else CARD_COLOR
	card.selectedStroke.Enabled = isSelected
	card.checkBadge.Visible = isSelected
	card.lockBadge.Visible = locked
	card.lockShade.Visible = locked
	UiKit.setPortrait(card.portrait, mother.charId, mother.class)
	card.nameLabel.Text = `{mother.charName}\n({mother.weightText}kg)`
	card.priceLabel.Text = `฿{UiKit.formatShort(priceOf(mother))}`
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
	local rows = math.ceil(#mothers / COLUMNS)
	scroll.CanvasSize = UDim2.fromOffset(0, rows * rowHeight + gap)

	local visibleRows = math.ceil(height / rowHeight) + 1
	-- clamp แถวแรกไว้ในช่วงที่มีของ (รายการหดตอนขาย — CanvasPosition อาจค้างค่าเกินขอบอยู่ชั่วขณะ)
	local maxFirstRow = math.max(0, rows - visibleRows + 1)
	local firstRow = math.clamp(math.floor(scroll.CanvasPosition.Y / rowHeight), 0, maxFirstRow)
	local needed = visibleRows * COLUMNS
	while #pool < needed do
		table.insert(pool, createCard())
	end

	for slotIndex, card in pool do
		local itemIndex = firstRow * COLUMNS + slotIndex
		local mother = if slotIndex <= needed then mothers[itemIndex] else nil
		if mother then
			local row = (itemIndex - 1) // COLUMNS
			local column = (itemIndex - 1) % COLUMNS
			card.button.Size = UDim2.fromOffset(cardWidth, cardHeight)
			card.button.Position = UDim2.fromOffset(gap + column * (cardWidth + gap), gap + row * rowHeight)
			bindCard(card, mother)
			card.button.Visible = true
		else
			card.mother = nil
			card.button.Visible = false
		end
	end

	emptyLabel.Visible = #mothers == 0
end

--------------------------------------------------------------------------------
-- แถบล่าง + กล่องยืนยัน
--------------------------------------------------------------------------------

local function setButton(button: TextButton, text: string, color: Color3, enabled: boolean)
	button.Text = text
	button.BackgroundColor3 = if enabled then color else UiKit.DISABLED
	button.AutoButtonColor = enabled
end

local function refreshConfirm()
	local count, total = SellWindow.getSelection()
	if count == 0 then
		-- ของที่เลือกหายหมดระหว่างเปิดกล่อง (ขาย/ล็อกจากที่อื่น) → ไม่มีอะไรให้ยืนยันแล้ว
		confirm.Visible = false
		return
	end
	confirmText.Text = `ขายแม่ {count} ตัว\nรวม ฿{UiKit.formatComma(total)}\n\nขายแล้วเอาคืนไม่ได้`
end

refreshFooter = function()
	local count, total = SellWindow.getSelection()
	local bagCount = #mothers
	infoLabel.Text = `แม่ในกระเป๋า {bagCount} ตัว · แม่ในคอกขายไม่ได้ ต้องถอดออกก่อน (แผง 🐾)`

	local unlocked = unlockedCount()
	local allSelected = unlocked > 0 and count == unlocked
	setButton(
		selectAllButton,
		if allSelected then "ยกเลิกที่เลือกทั้งหมด" else "เลือกทั้งหมดที่ไม่ได้ล็อก",
		SELECT_ALL_COLOR,
		unlocked > 0
	)
	setButton(
		sellButton,
		if count > 0 then `ขายที่เลือก ({count} ตัว · รวม ฿{UiKit.formatComma(total)})` else "ขายที่เลือก (ยังไม่ได้เลือก)",
		SELL_COLOR,
		count > 0
	)
	if confirm.Visible then
		refreshConfirm()
	end
end

local function refreshAll()
	buildList()
	layoutGrid()
	refreshFooter()
end

local function onSelectAll()
	local unlocked = unlockedCount()
	if unlocked == 0 then
		return
	end
	local count = SellWindow.getSelection()
	if count == unlocked then
		table.clear(selected)
	else
		for _, mother in mothers do
			if mother.locked ~= true then
				selected[mother.uid] = true
			end
		end
	end
	layoutGrid()
	refreshFooter()
end

local function onSell()
	local count = SellWindow.getSelection()
	if count == 0 then
		return
	end
	confirm.Visible = true
	refreshConfirm()
end

-- ⚠️ ยิงเฉพาะ uid ที่ติ๊กอยู่ตอนกดยืนยัน (ตัวที่ล็อก/หายไปแล้วถูกตัดออกตั้งแต่ตอน sync)
local function onConfirm()
	local _, _, uids = SellWindow.getSelection()
	confirm.Visible = false
	table.clear(selected)
	for _, uid in uids do
		actions.sellMother(uid)
	end
	layoutGrid()
	refreshFooter()
end

--------------------------------------------------------------------------------
-- สร้างหน้าต่าง
--------------------------------------------------------------------------------

local function makeButton(name: string, position: UDim2, size: UDim2, color: Color3, text: string): TextButton
	local button = UiKit.button({
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = color,
		Text = text,
	})
	UiKit.corner(button, UDim.new(0.25, 0))
	UiKit.textStroke(button, 1)
	UiKit.maxTextSize(button, 22)
	UiKit.padding(button, 0.08)
	return button
end

function SellWindow.create(parent: ScreenGui, windowActions: Actions)
	actions = windowActions

	window = UiKit.frame({
		Name = "SellWindow",
		Position = WINDOW_POSITION,
		Size = WINDOW_SIZE,
		BackgroundColor3 = CONTENT_COLOR,
		BackgroundTransparency = 0.2,
		Visible = false,
	})
	UiKit.corner(window, UDim.new(0.03, 0))
	UiKit.border(window, UiKit.BLACK, 2)
	window.Parent = parent

	local title = UiKit.label({
		Position = UDim2.fromScale(0.02, 0.025),
		Size = UDim2.fromScale(0.55, 0.085),
		Text = "💰 ร้านขายแม่",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 225, 120),
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(title, 1.5)
	title.Parent = window

	infoLabel = UiKit.label({
		Name = "Info",
		Position = UDim2.fromScale(0.02, 0.11),
		Size = UDim2.fromScale(0.9, 0.06),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UiKit.textStroke(infoLabel, 1)
	infoLabel.Parent = window

	local closeButton = UiKit.button({
		Name = "Close",
		Position = UDim2.fromScale(0.935, 0.03),
		Size = UDim2.fromScale(0.05, 0.085),
		BackgroundColor3 = Color3.fromRGB(200, 60, 60),
		Text = "✕",
	})
	UiKit.corner(closeButton, UDim.new(0.25, 0))
	UiKit.textStroke(closeButton, 1)
	closeButton.Parent = window
	closeButton.Activated:Connect(function()
		SellWindow.close()
	end)

	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Position = UDim2.fromScale(0.015, 0.19)
	scroll.Size = UDim2.fromScale(0.97, 0.66)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = window

	emptyLabel = UiKit.label({
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.1),
		Text = "ไม่มีแม่ในกระเป๋า — แม่ในคอกต้องถอดออกก่อนถึงจะขายได้",
		TextColor3 = Color3.fromRGB(215, 225, 205),
		Visible = false,
	})
	UiKit.textStroke(emptyLabel, 1)
	emptyLabel.Parent = window

	selectAllButton = makeButton(
		"SelectAll",
		UDim2.fromScale(0.02, 0.87),
		UDim2.fromScale(0.34, 0.1),
		SELECT_ALL_COLOR,
		"เลือกทั้งหมดที่ไม่ได้ล็อก"
	)
	selectAllButton.Parent = window
	selectAllButton.Activated:Connect(onSelectAll)

	sellButton = makeButton("Sell", UDim2.fromScale(0.38, 0.87), UDim2.fromScale(0.6, 0.1), SELL_COLOR, "ขายที่เลือก")
	sellButton.Parent = window
	sellButton.Activated:Connect(onSell)

	-- กล่องยืนยัน — ทับทั้งหน้าต่าง กันกดการ์ด/ปุ่มข้างหลังระหว่างถาม
	confirm = UiKit.frame({
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiKit.BLACK,
		BackgroundTransparency = 0.4,
		Active = true,
		ZIndex = 10,
		Visible = false,
	})
	UiKit.corner(confirm, UDim.new(0.03, 0))
	confirm.Parent = window

	local box = UiKit.frame({
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.62),
		BackgroundColor3 = Color3.fromRGB(28, 30, 36),
		ZIndex = 11,
	})
	UiKit.corner(box, UDim.new(0.06, 0))
	UiKit.border(box, SELL_COLOR, 3)
	box.Parent = confirm

	confirmText = UiKit.label({
		Name = "Text",
		Position = UDim2.fromScale(0.06, 0.06),
		Size = UDim2.fromScale(0.88, 0.56),
		TextWrapped = true,
		FontFace = UiKit.FONT_HEAVY,
		ZIndex = 12,
	})
	UiKit.maxTextSize(confirmText, 26)
	confirmText.Parent = box

	local confirmYes =
		makeButton("ConfirmSell", UDim2.fromScale(0.06, 0.7), UDim2.fromScale(0.42, 0.22), SELL_COLOR, "ยืนยันขาย")
	confirmYes.ZIndex = 12
	confirmYes.Parent = box
	confirmYes.Activated:Connect(onConfirm)

	local confirmNo =
		makeButton("ConfirmCancel", UDim2.fromScale(0.52, 0.7), UDim2.fromScale(0.42, 0.22), CANCEL_COLOR, "ยกเลิก")
	confirmNo.ZIndex = 12
	confirmNo.Parent = box
	confirmNo.Activated:Connect(function()
		-- ยกเลิก = แค่ปิดกล่อง ไม่ส่งอะไรไป server · ที่ติ๊กไว้ยังอยู่
		confirm.Visible = false
	end)

	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(layoutGrid)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid)
end

function SellWindow.setPayload(payload: any)
	lastPayload = payload
	if window.Visible then
		refreshAll()
	end
end

function SellWindow.isOpen(): boolean
	return window.Visible
end

function SellWindow.open()
	window.Visible = true
	scroll.CanvasPosition = Vector2.zero
	refreshAll()
end

-- ปิด = ล้างที่ติ๊กไว้ + ปิดกล่องยืนยัน (เปิดใหม่เริ่มจากว่างเสมอ กันขายตัวที่ลืมว่าติ๊กไว้)
function SellWindow.close()
	window.Visible = false
	confirm.Visible = false
	table.clear(selected)
end

return SellWindow
