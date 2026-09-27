--!strict
-- egg-army-game :: หน้าต่างกระเป๋า 3 แท็บ (สัตว์เลี้ยง · ไข่ · ไอเทม) — UI-1
--
-- ตำแหน่ง/สี/การจัดวางตามภาพต้นแบบ (docs/ui-overhaul-plan.md §3) · ข้อมูลอ่านจาก FarmStateSync ล้วน ๆ
-- ⚠️ client ไม่ตัดสินอะไรเอง: ปุ่มทุกปุ่มแค่ยิงคำขอผ่าน actions (Main.client.lua ต่อ remote ให้)
-- การตรวจล็อก/คอกเต็ม/roster เต็มฝั่งนี้เป็นแค่การปิดปุ่มให้ผู้เล่นรู้เร็ว ๆ — server ตรวจซ้ำเสมอ
--
-- ⚠️ ประสิทธิภาพ: แม่มีได้ ~100+ ตัว ห้ามสร้าง ViewportFrame ทุกใบพร้อมกัน
-- ใช้ "virtual grid" — สร้างการ์ดเท่าที่มองเห็น (+1 แถวกันขอบ) เป็น pool แล้วใช้ซ้ำตอนเลื่อน
-- การ์ดแต่ละใบวาดรูปใหม่เฉพาะตอนตัวละครเปลี่ยน (UiKit.setPortrait เช็ค attribute) ไม่ใช่ทุก sync

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local BagWindow = {}

export type Actions = {
	moveMother: (uid: string, target: string) -> (),
	toggleLock: (uid: string) -> (),
	sendToBattle: (mother: any) -> (),
	placeEgg: (heldEggId: number) -> (),
	notify: (text: string, ok: boolean) -> (),
	isRosterFull: () -> boolean,
}

type Tab = "pets" | "eggs" | "items"

type EggStack = {
	eggId: string,
	eggName: string,
	weight: number,
	weightText: string,
	ids: { number },
}

type Item = {
	key: string,
	kind: "mother" | "egg",
	name: string,
	mother: any?,
	inPen: boolean,
	egg: EggStack?,
}

type Card = {
	button: TextButton,
	portrait: Frame,
	nameLabel: TextLabel,
	lockBadge: TextLabel,
	penTag: TextLabel,
	countTag: TextLabel,
	selectedStroke: UIStroke,
	item: Item?,
}

-- ⚠️ สัดส่วนวัดจากภาพต้นแบบ (จอ 2000×921) — ดู docs/ui-overhaul-plan.md §3
local WINDOW_POSITION = UDim2.fromScale(0.235, 0.28)
local WINDOW_SIZE = UDim2.fromScale(0.484, 0.518)
local TAB_COLUMN_WIDTH = 0.088 -- ของความกว้างหน้าต่าง
local CONTENT_LEFT = 0.096
local COLUMNS = 5
local CARD_GAP_RATIO = 0.018 -- ของความกว้างตาราง

local CONTENT_COLOR = Color3.fromRGB(62, 84, 52)
local TAB_COLOR = Color3.fromRGB(52, 58, 50)
local CARD_COLOR = Color3.fromRGB(38, 40, 36)
local CARD_SELECTED_COLOR = Color3.fromRGB(72, 92, 64)
local PEN_TAG_COLOR = Color3.fromRGB(80, 185, 90)
local LOCK_COLOR = Color3.fromRGB(120, 110, 170)
local MOVE_COLOR = Color3.fromRGB(60, 150, 230)
local TEMP_COLOR = Color3.fromRGB(205, 140, 55)
local BATTLE_COLOR = Color3.fromRGB(200, 60, 60)

local actions: Actions
local window: Frame
local tabButtons: { [Tab]: TextButton } = {}
local capacityLabel: TextLabel
local searchBox: TextBox
local scroll: ScrollingFrame
local emptyLabel: TextLabel
local detail: Frame
local detailPortrait: Frame
local detailTitle: TextLabel
local detailInfo: TextLabel
local detailButtons: { TextButton } = {}
local detailHandlers: { (() -> ())? } = {}

local activeTab: Tab = "pets"
local lastPayload: any = nil
local items: { Item } = {}
local pool: { Card } = {}
-- ⚠️ เก็บ key (uid ของแม่ / ชนิด+น้ำหนักของไข่) ไม่ใช่ตำแหน่ง — ลิสต์เปลี่ยนลำดับได้ทุก sync
local selectedKey: string? = nil

--------------------------------------------------------------------------------
-- ข้อมูล → รายการการ์ด
--------------------------------------------------------------------------------

local function matchesSearch(name: string): boolean
	local query = string.lower(searchBox.Text)
	if query == "" then
		return true
	end
	return string.find(string.lower(name), query, 1, true) ~= nil
end

local function sortedMothers(list: { any }): { any }
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		local ca, cb = a.coinsPerMinute or 0, b.coinsPerMinute or 0
		if ca ~= cb then
			return ca > cb
		end
		return a.uid < b.uid
	end)
	return sorted
end

-- ⚠️ ไข่สแต็คตาม "ชนิด + น้ำหนัก" (hotbar-design.md §3) — ไข่ชนิดเดียวกันน้ำหนักต่างกันเป็นคนละของ
-- ฟองในกองเดียวกันเหมือนกันทุกประการ วางฟองไหนก็ได้ (ใช้ id ฟองแรกของกอง)
local function groupEggs(held: { any }): { EggStack }
	local byKey: { [string]: EggStack } = {}
	local order: { EggStack } = {}
	for _, egg in held do
		local key = `{egg.eggId}|{egg.weight}`
		local stack = byKey[key]
		if not stack then
			local created: EggStack = {
				eggId = egg.eggId,
				eggName = egg.eggName,
				weight = egg.weight,
				weightText = egg.weightText,
				ids = {},
			}
			byKey[key] = created
			table.insert(order, created)
			stack = created
		end
		table.insert((stack :: EggStack).ids, egg.id)
	end
	-- หนักก่อน · น้ำหนักเท่ากัน = ไข่ด่านสูงก่อน (โอกาสได้คลาสดีกว่า) · ไข่ไม่ผูกด่าน (ตำนาน) นับเป็น 0
	local function stageOf(eggId: string): number
		local eggType = Config.getEgg(eggId)
		return if eggType and eggType.stage then eggType.stage else 0
	end
	table.sort(order, function(a, b)
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		local sa, sb = stageOf(a.eggId), stageOf(b.eggId)
		if sa ~= sb then
			return sa > sb
		end
		return a.eggId < b.eggId
	end)
	return order
end

local function buildItems()
	table.clear(items)
	if not lastPayload then
		return
	end
	if activeTab == "pets" then
		-- ⚠️ แม่ในคอกขึ้นด้วย (ป้าย "คอก" เรียงก่อน) — ไม่งั้นล็อกแม่ในคอกไม่ได้ (Phase 4B)
		for _, mother in sortedMothers(lastPayload.mothersInPen) do
			if matchesSearch(mother.charName) then
				table.insert(items, { key = mother.uid, kind = "mother", name = mother.charName, mother = mother, inPen = true })
			end
		end
		for _, mother in sortedMothers(lastPayload.mothersInBag) do
			if matchesSearch(mother.charName) then
				table.insert(items, { key = mother.uid, kind = "mother", name = mother.charName, mother = mother, inPen = false })
			end
		end
	elseif activeTab == "eggs" then
		for _, stack in groupEggs(lastPayload.heldEggs) do
			if matchesSearch(stack.eggName) then
				table.insert(items, {
					key = `{stack.eggId}|{stack.weight}`,
					kind = "egg",
					name = stack.eggName,
					inPen = false,
					egg = stack,
				})
			end
		end
	end
end

local function findItem(key: string?): Item?
	if not key then
		return nil
	end
	for _, item in items do
		if item.key == key then
			return item
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- การ์ด (pool ใช้ซ้ำ)
--------------------------------------------------------------------------------

local renderDetail: () -> ()
local layoutGrid: () -> ()

local function makeTag(name: string, color: Color3, anchorX: number): TextLabel
	local tag = UiKit.label({
		Name = name,
		AnchorPoint = Vector2.new(anchorX, 0),
		Position = UDim2.fromScale(if anchorX == 0 then 0.04 else 0.96, 0.04),
		Size = UDim2.fromScale(0.4, 0.17),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		FontFace = UiKit.FONT_HEAVY,
		ZIndex = 3,
		Visible = false,
	})
	UiKit.corner(tag, UDim.new(0.3, 0))
	UiKit.textStroke(tag, 1)
	return tag
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
	local selectedStroke = UiKit.border(button, UiKit.WHITE, 3)
	selectedStroke.Enabled = false

	local portrait = UiKit.frame({
		Name = "PortraitHolder",
		Position = UDim2.fromScale(0.08, 0.04),
		Size = UDim2.fromScale(0.84, 0.64),
		BackgroundTransparency = 1,
	})
	portrait.Parent = button

	local nameLabel = UiKit.label({
		Name = "NameLabel",
		Position = UDim2.fromScale(0.04, 0.68),
		Size = UDim2.fromScale(0.92, 0.3),
		TextWrapped = true,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(nameLabel, 1.5)
	UiKit.maxTextSize(nameLabel, 18)
	nameLabel.Parent = button

	local lockBadge = makeTag("LockBadge", LOCK_COLOR, 1)
	lockBadge.Text = "🔒"
	lockBadge.Size = UDim2.fromScale(0.22, 0.2)
	lockBadge.Parent = button

	local penTag = makeTag("PenTag", PEN_TAG_COLOR, 0)
	penTag.Text = "คอก"
	penTag.Parent = button

	local countTag = makeTag("CountTag", Color3.fromRGB(40, 40, 40), 1)
	countTag.Parent = button

	local card: Card = {
		button = button,
		portrait = portrait,
		nameLabel = nameLabel,
		lockBadge = lockBadge,
		penTag = penTag,
		countTag = countTag,
		selectedStroke = selectedStroke,
		item = nil,
	}

	button.Activated:Connect(function()
		local item = card.item
		if not item then
			return
		end
		-- กดการ์ดเดิมซ้ำ = ปิดหน้ารายละเอียด
		selectedKey = if selectedKey == item.key then nil else item.key
		renderDetail()
		layoutGrid()
	end)

	button.Parent = scroll
	return card
end

local function bindCard(card: Card, item: Item)
	card.item = item
	local selected = item.key == selectedKey
	card.button.BackgroundColor3 = if selected then CARD_SELECTED_COLOR else CARD_COLOR
	card.selectedStroke.Enabled = selected

	if item.kind == "mother" and item.mother then
		local mother = item.mother
		UiKit.setPortrait(card.portrait, mother.charId, mother.class)
		card.nameLabel.Text = `{mother.charName}\n({mother.weightText}kg)`
		card.lockBadge.Visible = mother.locked == true
		card.penTag.Visible = item.inPen
		card.countTag.Visible = false
	elseif item.egg then
		local egg = item.egg
		UiKit.setEggIcon(card.portrait, egg.eggId)
		card.nameLabel.Text = `{egg.eggName}\n({egg.weightText}kg)`
		card.lockBadge.Visible = false
		card.penTag.Visible = false
		card.countTag.Text = `×{#egg.ids}`
		card.countTag.Visible = true
	end
end

-- ⚠️ virtual grid: วางการ์ดเท่าที่มองเห็น + 1 แถว · เลื่อน = ย้ายการ์ดใน pool ไปผูกกับรายการใหม่
-- ไม่แตะ CanvasPosition เลย → ตำแหน่งเลื่อนเดิมคงอยู่ตอน sync ใหม่เข้ามา (บั๊กเลื่อนกลับบนสุดไม่กลับมา)
layoutGrid = function()
	local width = scroll.AbsoluteSize.X - scroll.ScrollBarThickness
	local height = scroll.AbsoluteSize.Y
	if width <= 0 or height <= 0 then
		return -- ยังไม่ได้วาง (หน้าต่างปิดอยู่) — จะเรียกซ้ำเองตอนขนาดเปลี่ยน/เปิดหน้าต่าง
	end

	local gap = width * CARD_GAP_RATIO
	local cardSize = (width - gap * (COLUMNS + 1)) / COLUMNS
	local rowHeight = cardSize + gap
	local rows = math.ceil(#items / COLUMNS)
	scroll.CanvasSize = UDim2.fromOffset(0, rows * rowHeight + gap)

	local visibleRows = math.ceil(height / rowHeight) + 1
	-- ⚠️ clamp แถวแรกไว้ในช่วงที่มีของ — ตอนรายการหดลง (ค้นหา/ขาย) CanvasPosition อาจยังค้างค่าเก่า
	-- เกินขอบ canvas ใหม่อยู่ชั่วขณะ ถ้าไม่ clamp ตารางจะว่างเปล่าจนกว่า Roblox จะดันตำแหน่งกลับ
	local maxFirstRow = math.max(0, rows - visibleRows + 1)
	local firstRow = math.clamp(math.floor(scroll.CanvasPosition.Y / rowHeight), 0, maxFirstRow)
	local needed = visibleRows * COLUMNS
	while #pool < needed do
		table.insert(pool, createCard())
	end

	for slotIndex, card in pool do
		local itemIndex = firstRow * COLUMNS + slotIndex
		local item = if slotIndex <= needed then items[itemIndex] else nil
		if item then
			local row = (itemIndex - 1) // COLUMNS
			local column = (itemIndex - 1) % COLUMNS
			card.button.Size = UDim2.fromOffset(cardSize, cardSize)
			card.button.Position = UDim2.fromOffset(gap + column * rowHeight, gap + row * rowHeight)
			bindCard(card, item)
			card.button.Visible = true
		else
			card.item = nil
			card.button.Visible = false
		end
	end

	emptyLabel.Visible = #items == 0
	if #items == 0 then
		if activeTab == "items" then
			emptyLabel.Text = "ยังไม่มีไอเทม"
		elseif searchBox.Text ~= "" then
			emptyLabel.Text = `ไม่พบ "{searchBox.Text}"`
		elseif activeTab == "pets" then
			emptyLabel.Text = "ยังไม่มีแม่ — ฟักไข่ก่อน"
		else
			emptyLabel.Text = "ยังไม่มีไข่"
		end
	end
end

--------------------------------------------------------------------------------
-- หน้ารายละเอียด (แม่ / ไข่)
--------------------------------------------------------------------------------

local function setDetailButton(index: number, text: string?, color: Color3, enabled: boolean, handler: (() -> ())?)
	local button = detailButtons[index]
	if not text then
		button.Visible = false
		detailHandlers[index] = nil
		return
	end
	button.Visible = true
	button.Text = text
	button.BackgroundColor3 = if enabled then color else UiKit.DISABLED
	button.AutoButtonColor = enabled
	detailHandlers[index] = handler
end

local function renderMotherDetail(item: Item)
	local mother = item.mother
	local payload = lastPayload
	UiKit.setPortrait(detailPortrait, mother.charId, mother.class)
	detailTitle.Text = mother.charName

	local classInfo = Config.CharacterClasses[mother.class]
	local multiplier = if classInfo then ` · ×{classInfo.multiplier}` else ""
	local where = if item.inPen then "คอก (กำลังผลิต)" else "กระเป๋า"
	detailInfo.Text = `คลาส {mother.class}{multiplier}\nน้ำหนัก {mother.weightText} kg\n`
		.. `เงิน/นาที {UiKit.formatShort(mother.coinsPerMinute or 0)}\nอยู่ที่: {where}`

	local locked = mother.locked == true
	setDetailButton(1, if locked then "🔓 ปลดล็อก" else "🔒 ล็อก", LOCK_COLOR, true, function()
		actions.toggleLock(mother.uid)
	end)

	if item.inPen then
		local bagFull = #payload.mothersInBag >= payload.bagCapacity
		setDetailButton(
			2,
			if bagFull then "กระเป๋าเต็ม ย้ายออกไม่ได้" else "ย้ายออกจากคอก → กระเป๋า",
			MOVE_COLOR,
			not bagFull,
			if bagFull then nil else function()
				actions.moveMother(mother.uid, "bag")
			end
		)
		-- ส่งไปรบได้เฉพาะแม่ในกระเป๋า (กฎเดิม — กันส่งตัวที่กำลังผลิต)
		setDetailButton(3, nil, BATTLE_COLOR, false, nil)
		setDetailButton(4, nil, BATTLE_COLOR, false, nil)
		return
	end

	local penFull = #payload.mothersInPen >= payload.penCapacity
	setDetailButton(
		2,
		if penFull then "คอกเต็ม (ใช้ 🐾 สวมใส่ที่ดีที่สุด)" else "ย้ายเข้าคอก",
		MOVE_COLOR,
		not penFull,
		if penFull then nil else function()
			actions.moveMother(mother.uid, "pen")
		end
	)

	-- ⚠️ TEMP: ปุ่มส่งไปรบอยู่ตรงนี้ชั่วคราว — ย้ายไปแท่นอัญเชิญใน UI-3
	-- (ปุ่มขายย้ายไปร้านขายแม่หลังแมพแล้วใน UI-2 · SellWindow.lua)
	setDetailButton(4, nil, BATTLE_COLOR, false, nil)
	if locked then
		setDetailButton(3, "ส่งไปรบไม่ได้ — ล็อกอยู่ (TEMP)", BATTLE_COLOR, false, function()
			actions.notify(`แม่ตัวนี้ถูกล็อกไว้ ส่งไปรบไม่ได้ — กด "🔓 ปลดล็อก" ก่อน`, false)
		end)
		return
	end
	if actions.isRosterFull() then
		setDetailButton(3, "ส่งไปรบไม่ได้ — roster เต็ม (TEMP)", BATTLE_COLOR, false, function()
			actions.notify("roster เต็มแล้ว", false)
		end)
	else
		-- ปุ่มนี้**แค่เปิดกล่องยืนยันเดิม** (Phase 3C-2) ไม่ยิง remote ตรง ๆ
		setDetailButton(3, "ส่งไปรบ (TEMP)", BATTLE_COLOR, true, function()
			actions.sendToBattle(mother)
		end)
	end
end

local function renderEggDetail(item: Item)
	local egg = item.egg :: EggStack
	local payload = lastPayload
	UiKit.setEggIcon(detailPortrait, egg.eggId)
	detailTitle.Text = egg.eggName
	detailInfo.Text = `น้ำหนัก {egg.weightText} kg\nจำนวน ×{#egg.ids}\n`
		.. `สวนฟัก {payload.hatchingCount}/{payload.hatcherySize}\nคลาสสุ่มตอนวางลงสวนฟัก`

	local hatcheryFull = payload.hatchingCount >= payload.hatcherySize
	setDetailButton(
		1,
		if hatcheryFull then "สวนฟักเต็ม" else "วางลงสวนฟัก",
		MOVE_COLOR,
		not hatcheryFull,
		if hatcheryFull then nil else function()
			-- ⚠️ ส่ง id ประจำฟอง (ฟองแรกของกอง) ไม่ใช่ชนิดไข่/ตำแหน่ง — ทุกฟองในกองเหมือนกัน
			actions.placeEgg(egg.ids[1])
		end
	)
	setDetailButton(2, nil, MOVE_COLOR, false, nil)
	setDetailButton(3, nil, TEMP_COLOR, false, nil)
	setDetailButton(4, nil, BATTLE_COLOR, false, nil)
end

renderDetail = function()
	local item = findItem(selectedKey)
	if not item or not lastPayload then
		selectedKey = nil
		detail.Visible = false
		return
	end
	detail.Visible = true
	if item.kind == "mother" then
		renderMotherDetail(item)
	else
		renderEggDetail(item)
	end
end

--------------------------------------------------------------------------------
-- ส่วนหัว / แท็บ
--------------------------------------------------------------------------------

local function updateCapacity()
	if not lastPayload then
		capacityLabel.Text = ""
		return
	end
	local payload = lastPayload
	if activeTab == "pets" then
		capacityLabel.Text = `แม่ในกระเป๋า: {#payload.mothersInBag}/{payload.bagCapacity}`
			.. ` · ในคอก: {#payload.mothersInPen}/{payload.penCapacity}`
	elseif activeTab == "eggs" then
		local shown = if payload.heldCount > payload.heldShown
			then ` (แสดง {payload.heldShown} ฟองแรก)`
			else ""
		capacityLabel.Text = `ไข่: {payload.heldCount}/{payload.bagSize}{shown}`
	else
		capacityLabel.Text = "ไอเทม: 0"
	end
end

local function refreshAll()
	buildItems()
	updateCapacity()
	renderDetail()
	layoutGrid()
end

local function setTab(tab: Tab)
	activeTab = tab
	selectedKey = nil
	for name, button in tabButtons do
		local stroke = button:FindFirstChild("Selected")
		if stroke then
			(stroke :: UIStroke).Enabled = name == tab
		end
	end
	scroll.CanvasPosition = Vector2.zero
	refreshAll()
end

local function makeTabButton(tab: Tab, order: number, icon: string, caption: string)
	local button = UiKit.button({
		Name = `Tab_{tab}`,
		Position = UDim2.new(0, 0, (order - 1) * 0.19, 0),
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
	stroke.Enabled = tab == activeTab

	local captionLabel = UiKit.label({
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.9, 0.24),
		Text = caption,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(captionLabel, 1)
	captionLabel.Parent = button

	local iconLabel = UiKit.label({
		Position = UDim2.fromScale(0.15, 0.3),
		Size = UDim2.fromScale(0.7, 0.62),
		Text = icon,
	})
	iconLabel.Parent = button

	button.Activated:Connect(function()
		setTab(tab)
	end)
	tabButtons[tab] = button
	return button
end

--------------------------------------------------------------------------------
-- สร้างหน้าต่าง
--------------------------------------------------------------------------------

function BagWindow.create(parent: ScreenGui, windowActions: Actions)
	actions = windowActions

	window = UiKit.frame({
		Name = "BagWindow",
		Position = WINDOW_POSITION,
		Size = WINDOW_SIZE,
		BackgroundTransparency = 1,
		Visible = false,
	})
	window.Parent = parent

	-- คอลัมน์แท็บด้านซ้าย
	local tabColumn = UiKit.frame({
		Name = "Tabs",
		Size = UDim2.fromScale(TAB_COLUMN_WIDTH, 1),
		BackgroundTransparency = 1,
	})
	tabColumn.Parent = window
	makeTabButton("pets", 1, "🐾", "สัตว์เลี้ยง").Parent = tabColumn
	makeTabButton("eggs", 2, "🥚", "ไข่").Parent = tabColumn
	makeTabButton("items", 3, "🎒", "ไอเทม").Parent = tabColumn

	-- พื้นที่เนื้อหา: พื้นเขียวเข้มโปร่งแสง
	local content = UiKit.frame({
		Name = "Content",
		Position = UDim2.fromScale(CONTENT_LEFT, 0),
		Size = UDim2.fromScale(1 - CONTENT_LEFT, 1),
		BackgroundColor3 = CONTENT_COLOR,
		BackgroundTransparency = 0.2,
	})
	UiKit.corner(content, UDim.new(0.03, 0))
	content.Parent = window

	local title = UiKit.label({
		Position = UDim2.fromScale(0.02, 0.025),
		Size = UDim2.fromScale(0.55, 0.085),
		Text = "ไอเทมทั้งหมด",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(225, 230, 220),
		FontFace = UiKit.FONT_HEAVY,
	})
	title.Parent = content

	capacityLabel = UiKit.label({
		Position = UDim2.fromScale(0.02, 0.11),
		Size = UDim2.fromScale(0.62, 0.06),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.WHITE,
	})
	UiKit.textStroke(capacityLabel, 1)
	capacityLabel.Parent = content

	searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.Position = UDim2.fromScale(0.64, 0.03)
	searchBox.Size = UDim2.fromScale(0.28, 0.085)
	searchBox.BackgroundColor3 = Color3.fromRGB(40, 52, 36)
	searchBox.BackgroundTransparency = 0.1
	searchBox.BorderSizePixel = 0
	searchBox.TextColor3 = UiKit.WHITE
	searchBox.PlaceholderText = "ค้นหา"
	searchBox.PlaceholderColor3 = Color3.fromRGB(150, 160, 145)
	searchBox.FontFace = UiKit.FONT_BOLD
	searchBox.TextScaled = true
	searchBox.ClearTextOnFocus = false
	searchBox.Text = ""
	UiKit.corner(searchBox, UDim.new(0.25, 0))
	UiKit.padding(searchBox, 0.06)
	searchBox.Parent = content

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
		BagWindow.close()
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

	emptyLabel = UiKit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.8, 0.1),
		TextColor3 = Color3.fromRGB(215, 225, 205),
		Visible = false,
	})
	UiKit.textStroke(emptyLabel, 1)
	emptyLabel.Parent = content

	-- หน้ารายละเอียด: ทับด้านขวาของพื้นที่เนื้อหา
	detail = UiKit.frame({
		Name = "Detail",
		Position = UDim2.fromScale(0.6, 0.02),
		Size = UDim2.fromScale(0.385, 0.96),
		BackgroundColor3 = Color3.fromRGB(24, 30, 22),
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 5,
	})
	UiKit.corner(detail, UDim.new(0.04, 0))
	UiKit.border(detail, UiKit.BLACK, 2)
	detail.Parent = content

	detailPortrait = UiKit.frame({
		Name = "PortraitHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(0.5, 0.28),
		BackgroundTransparency = 1,
		ZIndex = 6,
	})
	local portraitAspect = Instance.new("UIAspectRatioConstraint")
	portraitAspect.AspectRatio = 1
	portraitAspect.Parent = detailPortrait
	detailPortrait.Parent = detail

	detailTitle = UiKit.label({
		Position = UDim2.fromScale(0.05, 0.32),
		Size = UDim2.fromScale(0.9, 0.08),
		FontFace = UiKit.FONT_HEAVY,
		ZIndex = 6,
	})
	UiKit.textStroke(detailTitle, 1.5)
	detailTitle.Parent = detail

	detailInfo = UiKit.label({
		Position = UDim2.fromScale(0.07, 0.41),
		Size = UDim2.fromScale(0.86, 0.2),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(220, 225, 215),
		ZIndex = 6,
	})
	UiKit.maxTextSize(detailInfo, 18)
	detailInfo.Parent = detail

	for index = 1, 4 do
		local button = UiKit.button({
			Name = `Action{index}`,
			Position = UDim2.fromScale(0.06, 0.63 + (index - 1) * 0.09),
			Size = UDim2.fromScale(0.88, 0.078),
			BackgroundColor3 = MOVE_COLOR,
			Visible = false,
			ZIndex = 6,
		})
		UiKit.corner(button, UDim.new(0.25, 0))
		UiKit.textStroke(button, 1)
		UiKit.maxTextSize(button, 18)
		UiKit.padding(button, 0.08)
		button.Activated:Connect(function()
			local handler = detailHandlers[index]
			if handler then
				handler()
			end
		end)
		button.Parent = detail
		detailButtons[index] = button
	end

	local detailClose = UiKit.button({
		Name = "CloseDetail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.015),
		Size = UDim2.fromScale(0.12, 0.07),
		BackgroundColor3 = Color3.fromRGB(80, 80, 80),
		Text = "✕",
		ZIndex = 7,
	})
	UiKit.corner(detailClose, UDim.new(0.3, 0))
	detailClose.Parent = detail
	detailClose.Activated:Connect(function()
		selectedKey = nil
		renderDetail()
		layoutGrid()
	end)

	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(layoutGrid)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid)
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		selectedKey = nil
		refreshAll()
	end)
end

function BagWindow.setPayload(payload: any)
	lastPayload = payload
	if window.Visible then
		refreshAll()
	end
end

function BagWindow.isOpen(): boolean
	return window.Visible
end

function BagWindow.open()
	window.Visible = true
	refreshAll()
end

function BagWindow.close()
	window.Visible = false
	selectedKey = nil
	detail.Visible = false
end

return BagWindow
