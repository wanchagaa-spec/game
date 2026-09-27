--!strict
-- egg-army-game :: ปุ่มขวา (ไข่ / เท้า) + แผงที่เปิดแทนคอลัมน์ปุ่ม — UI-1
--
-- แผงไข่: ไข่ที่กำลังฟัก + แถบเวลา นับถอยหลังทุกวินาทีฝั่ง client จาก remaining ที่ server ส่งมา
--   ⚠️ ฟักเสร็จแล้ว server ย้ายแม่เข้าคอก (หรือกระเป๋าถ้าคอกเต็ม) **เองอัตโนมัติ** ไม่มีปุ่มเก็บ
--   (EggService.processReadyHatchSlots · ห้ามเปลี่ยน logic การฟัก) · ค้างเฉพาะตอนคอก+กระเป๋าเต็มพร้อมกัน
--   (stuck — ข้อ D) → แถวขึ้น "เสร็จ — รอที่ว่าง" และจุดแดงบนปุ่มไข่นับจำนวนนี้
--   ปุ่ม ▶ / "เติบโตทั้งหมด" = เร่งฟักด้วย Robux (UI-5) → รอบนี้**แสดงแต่กดไม่ได้**
-- แผงเท้า: แม่ในคอก X/Y · "สวมใส่ที่ดีที่สุด" (AutoFillPenRequest) · "ถอดออก" = ย้ายเข้ากระเป๋า (ระบบย้ายเดิม)
--
-- ⚠️ แถวถูกใช้ซ้ำตาม key (ช่องสวนฟัก / uid ของแม่) ไม่สร้างใหม่ทุก sync — รูป ViewportFrame ของแม่ไม่ถูกสร้างซ้ำ
-- และตำแหน่งเลื่อนในรายการคงอยู่

local UiKit = require(script.Parent:WaitForChild("UiKit"))

local SidePanels = {}

export type Actions = {
	unequip: (uid: string) -> (),
	equipBest: () -> (),
	-- UI-5: ปุ่มหัวแผงไข่ "เติบโตทั้งหมด" — พรอมต์ซื้อ Robux แล้วเร่งไข่ที่กำลังฟัก**ทุกฟอง**ให้เสร็จทันที
	-- (เลือก "เร่งทั้งหมด" แทน "เร่งฟองที่เลือก" — ดูเหตุผลที่ EggService.rushAllHatching)
	rushHatching: () -> (),
}

type PanelName = "eggs" | "paw"

type HatchRow = { frame: Frame, icon: Frame, fill: Frame, timeLabel: TextLabel }
type PenRow = { frame: Frame, icon: Frame, nameLabel: TextLabel, unequipButton: TextButton }

-- ⚠️ สัดส่วนวัดจากภาพต้นแบบ (จอ 2000×921) — ดู docs/ui-overhaul-plan.md §3
local BUTTON_SIZE = UDim2.fromScale(0.043, 0.093)
local BUTTON_RIGHT_MARGIN = 0.056
local EGG_BUTTON_TOP = 0.328
local PAW_BUTTON_TOP = 0.454
local PANEL_POSITION = UDim2.fromScale(0.774, 0.418)
local PANEL_SIZE = UDim2.fromScale(0.17, 0.315)
local ROW_HEIGHT_RATIO = 0.27 -- ของความสูงรายการ (≈ 3 แถวเห็นพร้อมกันตามต้นแบบ)

local EGG_BUTTON_COLOR = Color3.fromRGB(225, 55, 55)
local PAW_BUTTON_COLOR = Color3.fromRGB(245, 140, 55)
local PANEL_COLOR = Color3.fromRGB(32, 32, 32)
local HEADER_COLOR = Color3.fromRGB(232, 214, 178)
local HEADER_TEXT_COLOR = Color3.fromRGB(80, 50, 20)
local ROW_COLOR = Color3.fromRGB(46, 46, 46)
local PROGRESS_BG_COLOR = Color3.fromRGB(22, 22, 22)
local PROGRESS_FILL_COLOR = Color3.fromRGB(95, 205, 70)
local EQUIP_COLOR = Color3.fromRGB(85, 200, 70)
local UNEQUIP_COLOR = Color3.fromRGB(215, 55, 55)
local DONE_TEXT_COLOR = Color3.fromRGB(255, 230, 120)

local actions: Actions
local buttonColumn: Frame
local eggBadge: TextLabel
-- ⚠️ คีย์เป็น string ธรรมดา ("eggs" / "paw") — ตาราง { [PanelName]: T } ทำให้ .eggs/.paw ใช้ไม่ได้ใน strict mode
local panels: { [string]: Frame } = {}
local lists: { [string]: ScrollingFrame } = {}
local emptyLabels: { [string]: TextLabel } = {}
local pawTitle: TextLabel
local eggHeaderButton: TextButton
local openPanel: PanelName? = nil

local hatchRows: { [number]: HatchRow } = {}
local penRows: { [string]: PenRow } = {}
local lastPayload: any = nil
-- เวลาที่รับ sync ล่าสุด (os.clock) — นับถอยหลังเองระหว่างรอบ sync
local receivedAt = 0

local function rowHeight(name: string): number
	return math.max(24, lists[name].AbsoluteSize.Y * ROW_HEIGHT_RATIO)
end

--------------------------------------------------------------------------------
-- ปุ่มขวา
--------------------------------------------------------------------------------

local function makeSideButton(name: string, top: number, color: Color3, icon: string): TextButton
	local button = UiKit.button({
		Name = name,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1 - BUTTON_RIGHT_MARGIN, top),
		Size = BUTTON_SIZE,
		BackgroundColor3 = color,
		Text = "",
	})
	-- ⚠️ 4.3% × 9.3% เป็นจัตุรัสเฉพาะจอ 2000×921 — บังคับจัตุรัสจากความสูงให้ทุกจอ
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = button
	UiKit.corner(button, UDim.new(0.16, 0))
	UiKit.border(button, UiKit.BLACK, 4)

	local iconLabel = UiKit.label({
		Position = UDim2.fromScale(0.12, 0.12),
		Size = UDim2.fromScale(0.76, 0.76),
		Text = icon,
	})
	iconLabel.Parent = button
	button.Parent = buttonColumn
	return button
end

--------------------------------------------------------------------------------
-- แผง
--------------------------------------------------------------------------------

local function setOpenPanel(name: PanelName?)
	openPanel = name
	for panelName, panel in panels do
		panel.Visible = panelName == name
	end
	-- ⚠️ แผงมาแทนที่คอลัมน์ปุ่ม — เปิดแผง = ซ่อนปุ่ม · ปิดด้วยแถบแดง ">" แล้วปุ่มกลับมา
	buttonColumn.Visible = name == nil
	if name then
		SidePanels.refresh()
	end
end

local function makePanel(name: PanelName, title: string, headerButtonText: string, headerButtonColor: Color3, headerEnabled: boolean): (Frame, TextLabel, TextButton)
	local panel = UiKit.frame({
		Name = `{name}Panel`,
		Position = PANEL_POSITION,
		Size = PANEL_SIZE,
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	UiKit.corner(panel, UDim.new(0.04, 0))
	UiKit.border(panel, UiKit.BLACK, 3)

	local header = UiKit.frame({
		Name = "Header",
		Size = UDim2.fromScale(1, 0.17),
		BackgroundColor3 = HEADER_COLOR,
	})
	UiKit.corner(header, UDim.new(0.2, 0))
	header.Parent = panel

	local titleLabel = UiKit.label({
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.52, 0.8),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = HEADER_TEXT_COLOR,
		FontFace = UiKit.FONT_HEAVY,
	})
	titleLabel.Parent = header

	local headerButton = UiKit.button({
		Name = "HeaderButton",
		Position = UDim2.fromScale(0.58, 0.12),
		Size = UDim2.fromScale(0.4, 0.76),
		BackgroundColor3 = if headerEnabled then headerButtonColor else UiKit.DISABLED,
		AutoButtonColor = headerEnabled,
		Text = headerButtonText,
	})
	UiKit.corner(headerButton, UDim.new(0.25, 0))
	UiKit.border(headerButton, UiKit.BLACK, 2)
	UiKit.textStroke(headerButton, 1)
	UiKit.padding(headerButton, 0.08)
	headerButton.Parent = header

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromScale(0.03, 0.2)
	list.Size = UDim2.fromScale(0.94, 0.77)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local empty = UiKit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.9, 0.16),
		TextColor3 = Color3.fromRGB(210, 210, 210),
		TextWrapped = true,
		Visible = false,
	})
	empty.Parent = panel

	-- แถบแดง ">" ติดขอบซ้ายของแผง: กดแล้วปิดแผง คืนคอลัมน์ปุ่ม
	local closeTab = UiKit.button({
		Name = "CloseTab",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -4, 0.45, 0),
		Size = UDim2.fromScale(0.14, 0.16),
		BackgroundColor3 = Color3.fromRGB(215, 35, 35),
		Text = ">",
	})
	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = 1
	closeAspect.Parent = closeTab
	UiKit.corner(closeTab, UDim.new(0.15, 0))
	UiKit.border(closeTab, UiKit.BLACK, 3)
	UiKit.textStroke(closeTab, 1.5)
	closeTab.Parent = panel
	closeTab.Activated:Connect(function()
		setOpenPanel(nil)
	end)

	panels[name] = panel
	lists[name] = list
	emptyLabels[name] = empty
	return panel, titleLabel, headerButton
end

local function makeRow(name: PanelName): (Frame, Frame)
	local row = UiKit.frame({
		Name = "Row",
		Size = UDim2.new(1, -6, 0, rowHeight(name)),
		BackgroundColor3 = ROW_COLOR,
		BackgroundTransparency = 0.05,
	})
	UiKit.corner(row, UDim.new(0.14, 0))
	local icon = UiKit.frame({
		Name = "Icon",
		Position = UDim2.fromScale(0.02, 0.08),
		Size = UDim2.fromScale(0.84, 0.84),
		BackgroundTransparency = 1,
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = icon
	icon.Parent = row
	row.Parent = lists[name]
	return row, icon
end

local function getHatchRow(slotIndex: number): HatchRow
	local existing = hatchRows[slotIndex]
	if existing then
		return existing
	end
	local frame, icon = makeRow("eggs")

	local bar = UiKit.frame({
		Name = "Bar",
		Position = UDim2.fromScale(0.2, 0.22),
		Size = UDim2.fromScale(0.58, 0.56),
		BackgroundColor3 = PROGRESS_BG_COLOR,
		ClipsDescendants = true,
	})
	UiKit.corner(bar, UDim.new(0.25, 0))
	bar.Parent = frame
	local fill = UiKit.frame({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = PROGRESS_FILL_COLOR,
	})
	UiKit.corner(fill, UDim.new(0.25, 0))
	fill.Parent = bar
	local timeLabel = UiKit.label({
		Size = UDim2.fromScale(1, 1),
		FontFace = UiKit.FONT_HEAVY,
		ZIndex = 2,
	})
	UiKit.textStroke(timeLabel, 1.5)
	timeLabel.Parent = bar

	-- ⚠️ UI-5: เร่งฟักเป็นปุ่มเดียวที่หัวแผง ("เติบโตทั้งหมด" — เร่ง**ทุกฟอง**พร้อมกัน)
	-- ไม่มีปุ่มเร่งรายฟองแล้ว (ตัดสินใจแล้วว่า implement ง่ายกว่า — ดู EggService.rushAllHatching)

	local row: HatchRow = { frame = frame, icon = icon, fill = fill, timeLabel = timeLabel }
	hatchRows[slotIndex] = row
	return row
end

local function getPenRow(uid: string): PenRow
	local existing = penRows[uid]
	if existing then
		return existing
	end
	local frame, icon = makeRow("paw")

	local nameLabel = UiKit.label({
		Position = UDim2.fromScale(0.2, 0.06),
		Size = UDim2.fromScale(0.5, 0.88),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(nameLabel, 1)
	UiKit.maxTextSize(nameLabel, 16)
	nameLabel.Parent = frame

	local unequipButton = UiKit.button({
		Name = "Unequip",
		Position = UDim2.fromScale(0.72, 0.18),
		Size = UDim2.fromScale(0.26, 0.64),
		BackgroundColor3 = UNEQUIP_COLOR,
		Text = "ถอดออก",
	})
	UiKit.corner(unequipButton, UDim.new(0.2, 0))
	UiKit.border(unequipButton, UiKit.BLACK, 2)
	UiKit.textStroke(unequipButton, 1)
	UiKit.padding(unequipButton, 0.1)
	unequipButton.Parent = frame
	unequipButton.Activated:Connect(function()
		if unequipButton.AutoButtonColor then
			actions.unequip(uid)
		end
	end)

	local row: PenRow = { frame = frame, icon = icon, nameLabel = nameLabel, unequipButton = unequipButton }
	penRows[uid] = row
	return row
end

--------------------------------------------------------------------------------
-- วาดข้อมูล
--------------------------------------------------------------------------------

-- เวลานับถอยหลังของแต่ละช่อง — อัปเดตทุกวินาทีจาก remaining ที่ sync ส่งมา ไม่ต้องรอ sync รอบใหม่
local function updateHatchTimers()
	if not lastPayload then
		return
	end
	local elapsed = os.clock() - receivedAt
	for slotIndex, row in hatchRows do
		local slot = lastPayload.hatching[slotIndex]
		if slot and slot.occupied then
			local remaining = math.max(0, slot.remaining - elapsed)
			local total = math.max(1, slot.total)
			if slot.stuck or remaining <= 0 then
				row.fill.Size = UDim2.fromScale(1, 1)
				row.timeLabel.Text = if slot.stuck then "เสร็จ — รอที่ว่าง" else "เสร็จ"
				row.timeLabel.TextColor3 = DONE_TEXT_COLOR
			else
				row.fill.Size = UDim2.fromScale(math.clamp(1 - remaining / total, 0, 1), 1)
				row.timeLabel.Text = UiKit.formatDuration(remaining)
				row.timeLabel.TextColor3 = UiKit.WHITE
			end
		end
	end
end

local function refreshEggs()
	local payload = lastPayload
	local occupied: { number } = {}
	for index = 1, payload.hatcherySize do
		local slot = payload.hatching[index]
		if slot and slot.occupied then
			table.insert(occupied, index)
		end
	end
	-- เสร็จก่อนอยู่บน
	table.sort(occupied, function(a, b)
		return payload.hatching[a].remaining < payload.hatching[b].remaining
	end)

	local keep: { [number]: boolean } = {}
	for order, slotIndex in occupied do
		local slot = payload.hatching[slotIndex]
		local row = getHatchRow(slotIndex)
		row.frame.LayoutOrder = order
		row.frame.Size = UDim2.new(1, -6, 0, rowHeight("eggs"))
		UiKit.setEggIcon(row.icon, slot.eggId)
		keep[slotIndex] = true
	end
	for slotIndex, row in hatchRows do
		if not keep[slotIndex] then
			row.frame:Destroy()
			hatchRows[slotIndex] = nil
		end
	end
	emptyLabels.eggs.Text = "ไม่มีไข่ที่กำลังฟัก — วางไข่จากกระเป๋า 🎒 แท็บไข่"
	emptyLabels.eggs.Visible = #occupied == 0

	-- UI-5: ปิดปุ่ม "เติบโตทั้งหมด" ตอนไม่มีไข่ให้เร่งเลย — กันเผลอซื้อ Robux ไปแล้วไม่มีผลอะไรเลย
	local canRush = #occupied > 0
	eggHeaderButton.BackgroundColor3 = if canRush then EQUIP_COLOR else UiKit.DISABLED
	eggHeaderButton.AutoButtonColor = canRush
	updateHatchTimers()
end

local function refreshPaw()
	local payload = lastPayload
	pawTitle.Text = `{#payload.mothersInPen}/{payload.penCapacity} Active`

	local sorted = table.clone(payload.mothersInPen)
	table.sort(sorted, function(a: any, b: any)
		local ca, cb = a.coinsPerMinute or 0, b.coinsPerMinute or 0
		if ca ~= cb then
			return ca > cb
		end
		return a.uid < b.uid
	end)

	local bagFull = #payload.mothersInBag >= payload.bagCapacity
	local keep: { [string]: boolean } = {}
	for order, mother in sorted do
		local row = getPenRow(mother.uid)
		row.frame.LayoutOrder = order
		row.frame.Size = UDim2.new(1, -6, 0, rowHeight("paw"))
		UiKit.setPortrait(row.icon, mother.charId, mother.class)
		local lock = if mother.locked then "🔒 " else ""
		row.nameLabel.Text = `{lock}{mother.charName} {mother.weightText}kg\n({UiKit.formatShort(mother.coinsPerMinute or 0)}/นาที)`
		row.unequipButton.Text = if bagFull then "กระเป๋าเต็ม" else "ถอดออก"
		row.unequipButton.BackgroundColor3 = if bagFull then UiKit.DISABLED else UNEQUIP_COLOR
		row.unequipButton.AutoButtonColor = not bagFull
		keep[mother.uid] = true
	end
	for uid, row in penRows do
		if not keep[uid] then
			row.frame:Destroy()
			penRows[uid] = nil
		end
	end
	emptyLabels.paw.Text = "ยังไม่มีแม่ในคอก"
	emptyLabels.paw.Visible = #sorted == 0
end

function SidePanels.refresh()
	if not lastPayload then
		return
	end
	if openPanel == "eggs" then
		refreshEggs()
	elseif openPanel == "paw" then
		refreshPaw()
	end
end

--------------------------------------------------------------------------------
-- สร้าง / ต่อข้อมูล
--------------------------------------------------------------------------------

function SidePanels.create(parent: ScreenGui, panelActions: Actions)
	actions = panelActions

	buttonColumn = UiKit.frame({
		Name = "SideButtons",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	buttonColumn.Parent = parent

	local eggButton = makeSideButton("EggButton", EGG_BUTTON_TOP, EGG_BUTTON_COLOR, "🥚")
	local pawButton = makeSideButton("PawButton", PAW_BUTTON_TOP, PAW_BUTTON_COLOR, "🐾")

	-- จุดแดงตัวเลข = ไข่ที่ฟักเสร็จแล้วแต่ค้าง (คอก+กระเป๋าเต็ม) — ฟักเสร็จปกติเข้าคอก/กระเป๋าเองอยู่แล้ว
	eggBadge = UiKit.label({
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.06, 0.06),
		Size = UDim2.fromScale(0.38, 0.38),
		BackgroundColor3 = Color3.fromRGB(230, 30, 30),
		BackgroundTransparency = 0,
		FontFace = UiKit.FONT_HEAVY,
		ZIndex = 3,
		Visible = false,
	})
	UiKit.corner(eggBadge, UDim.new(0.5, 0))
	UiKit.border(eggBadge, UiKit.BLACK, 2)
	eggBadge.Parent = eggButton

	-- ⚠️ buttonColumn เป็น Frame โปร่งใสเต็มจอ แต่ไม่ Active จึงไม่กินคลิก — กดทะลุไปโลก/ปุ่มอื่นได้ตามปกติ
	eggButton.Activated:Connect(function()
		setOpenPanel("eggs")
	end)
	pawButton.Activated:Connect(function()
		setOpenPanel("paw")
	end)

	-- UI-5: ปุ่มหัวแผงไข่ตอนนี้ทำงานจริง (พรอมต์ซื้อ Robux เร่งฟักทุกฟอง) — เริ่มเปิดไว้เสมอ
	-- แล้วปิด/เปิดจริงตามว่ามีไข่กำลังฟักอยู่ไหมใน refreshEggs() (กันซื้อไปแล้วไม่มีผล)
	local eggPanel
	eggPanel, _, eggHeaderButton = makePanel("eggs", "ไข่ที่กำลังฟัก", "เติบโตทั้งหมด", EQUIP_COLOR, true)
	eggPanel.Parent = parent
	eggHeaderButton.Activated:Connect(function()
		if eggHeaderButton.AutoButtonColor then
			actions.rushHatching()
		end
	end)

	local pawPanel, title, equipButton = makePanel("paw", "0/0 Active", "สวมใส่ที่ดีที่สุด", EQUIP_COLOR, true)
	pawTitle = title
	pawPanel.Parent = parent
	equipButton.Activated:Connect(function()
		actions.equipBest()
	end)

	for name, list in lists do
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local height = rowHeight(name)
			for _, child in list:GetChildren() do
				if child:IsA("Frame") and child.Name == "Row" then
					child.Size = UDim2.new(1, -6, 0, height)
				end
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			if openPanel == "eggs" then
				updateHatchTimers()
			end
		end
	end)
end

function SidePanels.setPayload(payload: any)
	lastPayload = payload
	receivedAt = os.clock()
	local stuck = payload.stuckHatchCount or 0
	eggBadge.Text = tostring(stuck)
	eggBadge.Visible = stuck > 0
	SidePanels.refresh()
end

function SidePanels.close()
	setOpenPanel(nil)
end

return SidePanels
