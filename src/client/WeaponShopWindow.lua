--!strict
-- egg-army-game :: หน้าต่างร้านกระบอง — Phase 5C (เปิดจากจุดกด E ที่แผง "ซื้ออาวุธ" หลังแมพ · MapSigns.lua)
--
-- 10 แถว = กระบอง 10 ขั้น: ขั้น · ชื่อ · รูปกระบองเล็ก · ดาเมจ/ครั้ง · ราคา · สถานะ
--   · ขั้นที่มีแล้ว (≤ ขั้นปัจจุบัน) = ✔ มีแล้ว
--   · ขั้นถัดไป = ปุ่ม "ซื้อ" **สีเขียว** (มาตรฐานทั้งเกม: ซื้อ = เขียว · ขาย = แดง) · ราคา**สีแดง**ถ้าเงินไม่พอ
--   · ขั้นที่ไกลกว่านั้น = เห็นได้แต่เป็นสีเทา + "ซื้อขั้นก่อนหน้าก่อน" (ซื้อเรียงขั้นเท่านั้น)
-- ⚠️ client ไม่ตัดสินอะไร: ปุ่มซื้อยิง BuyClubTierRequest **ไม่มีพารามิเตอร์** (server ซื้อขั้นถัดไปเอง ตรวจเงิน/เพดานเอง)
--   ขั้นปัจจุบัน/เงินอ่านจาก sync (clubTier · coins) · ดาเมจ/ราคา/ชื่อ/สี อ่านจาก Config ชุดเดียวกับ server
-- ⚠️ มีแค่ 10 แถว → สร้างครบทุกแถวครั้งเดียว (ไม่ต้อง virtual grid แบบกระเป๋า) · รูปกระบองเป็น Frame 2D (ไม่ใช่ ViewportFrame)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local WeaponShopWindow = {}

export type Actions = {
	buyNext: () -> (),
	notify: (text: string, ok: boolean) -> (),
}

export type RowState = "owned" | "next" | "locked"
export type RowView = {
	state: RowState,
	tier: number,
	name: string,
	damageText: string,
	priceText: string,
	priceTone: "free" | "owned" | "price" | "poor" | "dim",
	actionText: string,
}

type Row = {
	tier: number,
	frame: Frame,
	tierLabel: TextLabel,
	icon: Frame,
	nameLabel: TextLabel,
	damageLabel: TextLabel,
	priceLabel: TextLabel,
	statusLabel: TextLabel,
	buyButton: TextButton,
	shade: Frame,
}

-- ⚠️ ตำแหน่ง/ขนาดเดียวกับร้านขายแม่ (เปิดได้ทีละหน้าต่างอยู่แล้ว)
local WINDOW_POSITION = UDim2.fromScale(0.235, 0.28)
local WINDOW_SIZE = UDim2.fromScale(0.484, 0.518)
local VISIBLE_ROWS = 5 -- แถวที่เห็นพร้อมกันในกรอบเลื่อน (ที่เหลือเลื่อนดู)
local ROW_GAP = 6 -- px

local CONTENT_COLOR = Color3.fromRGB(70, 62, 48)
local ROW_COLOR = Color3.fromRGB(38, 36, 32)
local ROW_NEXT_COLOR = Color3.fromRGB(46, 70, 44)
local OWNED_COLOR = Color3.fromRGB(120, 220, 120)
local PRICE_COLOR = Color3.fromRGB(255, 220, 90)
local POOR_COLOR = Color3.fromRGB(235, 70, 70)
local DIM_TEXT_COLOR = Color3.fromRGB(150, 150, 150)
-- ⚠️ UI-fix รอบ 1: มาตรฐานสีทั้งเกม — ปุ่มซื้อ = โทนเขียว (ร้านขายแม่ = แดง)
local BUY_COLOR = Color3.fromRGB(60, 170, 75)
local LOCKED_TEXT = "ซื้อขั้นก่อนหน้าก่อน"

local actions: Actions
local window: Frame
local scroll: ScrollingFrame
local infoLabel: TextLabel
local rows: { Row } = {}
local lastPayload: any = nil

--------------------------------------------------------------------------------
-- ข้อมูล (pure — เทสต์ smoke เรียกตรง)
--------------------------------------------------------------------------------

-- สถานะแถวของขั้นนี้ จาก sync ล่าสุด · payload nil = ยังไม่รู้ขั้น (ถือว่ามีแค่ขั้นเริ่มต้น)
function WeaponShopWindow.describeRow(tier: number, payload: any): RowView
	local current = Config.clampClubTier(if payload then payload.clubTier else nil)
	local coins = if payload and type(payload.coins) == "number" then payload.coins else 0
	local price = Config.getClubPrice(tier)
	local state: RowState = if tier <= current then "owned" elseif tier == current + 1 then "next" else "locked"

	local priceText = if price <= 0 then "ฟรี" else `฿{UiKit.formatShort(price)}`
	local priceTone: "free" | "owned" | "price" | "poor" | "dim"
	local actionText: string
	if state == "owned" then
		priceTone = if price <= 0 then "free" else "owned"
		actionText = "✔ มีแล้ว"
	elseif state == "next" then
		priceTone = if coins < price then "poor" else "price"
		actionText = "ซื้อ"
	else
		priceTone = "dim"
		actionText = LOCKED_TEXT
	end

	return {
		state = state,
		tier = tier,
		name = Config.getClubVisual(tier).name,
		damageText = `⚔ {UiKit.formatShort(Config.getClubDamage(tier))} / ครั้ง`,
		priceText = priceText,
		priceTone = priceTone,
		actionText = actionText,
	}
end

local function toneColor(tone: string): Color3
	if tone == "poor" then
		return POOR_COLOR
	elseif tone == "dim" then
		return DIM_TEXT_COLOR
	elseif tone == "owned" or tone == "free" then
		return OWNED_COLOR
	end
	return PRICE_COLOR
end

--------------------------------------------------------------------------------
-- รูปกระบองเล็ก 2D — ด้าม (แท่งแคบ) + หัว (ก้อนมน) สีเดียวกับกระบองจริง · ขั้นเรืองแสงมีขอบเรือง
--------------------------------------------------------------------------------

local function drawClubIcon(holder: Frame, tier: number)
	local visual = Config.getClubVisual(tier)
	local maxTier = Config.Balance.Weapon.MAX_LEVEL
	-- โตตามขั้นเหมือนของจริง (ขั้น 1 = 70% ของกรอบ → ขั้นสุดท้าย = 100%)
	local scale = 0.7 + 0.3 * (tier - 1) / math.max(1, maxTier - 1)

	local handle = UiKit.frame({
		Name = "Handle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.14 * scale, 0.62 * scale),
		BackgroundColor3 = visual.handleColor,
		BackgroundTransparency = 0,
	})
	UiKit.corner(handle, UDim.new(0.4, 0))
	handle.Parent = holder

	local head = UiKit.frame({
		Name = "Head",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96 - 0.55 * scale),
		Size = UDim2.fromScale(0.42 * scale, 0.42 * scale),
		BackgroundColor3 = visual.headColor,
		BackgroundTransparency = 0,
	})
	UiKit.corner(head, UDim.new(0.35, 0))
	UiKit.border(head, if visual.glow > 0 then visual.headColor else UiKit.BLACK, if visual.glow > 0 then 3 else 1)
	head.Parent = holder
end

--------------------------------------------------------------------------------
-- แถว
--------------------------------------------------------------------------------

local function makeLabel(parent: Instance, name: string, x: number, width: number, align: Enum.TextXAlignment?): TextLabel
	local label = UiKit.label({
		Name = name,
		Position = UDim2.fromScale(x, 0.12),
		Size = UDim2.fromScale(width, 0.76),
		TextXAlignment = align or Enum.TextXAlignment.Center,
	})
	UiKit.textStroke(label, 1)
	UiKit.maxTextSize(label, 22)
	label.Parent = parent
	return label
end

local function createRow(tier: number): Row
	local frame = UiKit.frame({
		Name = `ClubRow{tier}`,
		BackgroundColor3 = ROW_COLOR,
		BackgroundTransparency = 0.1,
	})
	UiKit.corner(frame, UDim.new(0.15, 0))
	frame.Parent = scroll

	local tierLabel = makeLabel(frame, "Tier", 0.01, 0.1)
	tierLabel.Text = `ขั้น {tier}`
	tierLabel.FontFace = UiKit.FONT_HEAVY

	local icon = UiKit.frame({
		Name = "Icon",
		Position = UDim2.fromScale(0.115, 0.05),
		Size = UDim2.fromScale(0.08, 0.9),
		BackgroundTransparency = 1,
	})
	icon.Parent = frame
	drawClubIcon(icon, tier)

	local nameLabel = makeLabel(frame, "ClubName", 0.21, 0.25, Enum.TextXAlignment.Left)
	local damageLabel = makeLabel(frame, "Damage", 0.46, 0.2)
	local priceLabel = makeLabel(frame, "Price", 0.66, 0.13)
	priceLabel.FontFace = UiKit.FONT_HEAVY

	local statusLabel = makeLabel(frame, "Status", 0.8, 0.19)
	local buyButton = UiKit.button({
		Name = "Buy",
		Position = UDim2.fromScale(0.81, 0.15),
		Size = UDim2.fromScale(0.17, 0.7),
		BackgroundColor3 = BUY_COLOR,
		Text = "ซื้อ",
		Visible = false,
	})
	UiKit.corner(buyButton, UDim.new(0.25, 0))
	UiKit.textStroke(buyButton, 1)
	UiKit.maxTextSize(buyButton, 22)
	buyButton.Parent = frame
	-- ⚠️ ไม่ส่งเลขขั้น — server ซื้อ "ขั้นถัดไป" ของตัวเองเสมอ (กดแถวไหนก็ได้ผลเดียวกัน ปุ่มโผล่แค่แถวถัดไปอยู่แล้ว)
	buyButton.Activated:Connect(function()
		actions.buyNext()
	end)

	-- ม่านเทาทับแถวที่ยังซื้อไม่ได้ (ขั้นที่ไกลกว่าขั้นถัดไป)
	local shade = UiKit.frame({
		Name = "LockedShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiKit.BLACK,
		BackgroundTransparency = 0.45,
		ZIndex = 3,
		Visible = false,
	})
	UiKit.corner(shade, UDim.new(0.15, 0))
	shade.Parent = frame

	return {
		tier = tier,
		frame = frame,
		tierLabel = tierLabel,
		icon = icon,
		nameLabel = nameLabel,
		damageLabel = damageLabel,
		priceLabel = priceLabel,
		statusLabel = statusLabel,
		buyButton = buyButton,
		shade = shade,
	}
end

local function bindRow(row: Row)
	local view = WeaponShopWindow.describeRow(row.tier, lastPayload)
	row.nameLabel.Text = view.name
	row.damageLabel.Text = view.damageText
	row.priceLabel.Text = view.priceText
	row.priceLabel.TextColor3 = toneColor(view.priceTone)
	row.frame.BackgroundColor3 = if view.state == "next" then ROW_NEXT_COLOR else ROW_COLOR
	row.buyButton.Visible = view.state == "next"
	row.statusLabel.Visible = view.state ~= "next"
	row.statusLabel.Text = view.actionText
	row.statusLabel.TextColor3 = if view.state == "owned" then OWNED_COLOR else DIM_TEXT_COLOR
	row.shade.Visible = view.state == "locked"
end

local function layoutRows()
	local height = scroll.AbsoluteSize.Y
	local rowHeight = math.max(24, math.floor((height - ROW_GAP) / VISIBLE_ROWS) - ROW_GAP)
	for index, row in rows do
		row.frame.Position = UDim2.new(0, ROW_GAP, 0, ROW_GAP + (index - 1) * (rowHeight + ROW_GAP))
		row.frame.Size = UDim2.new(1, -ROW_GAP * 2 - 6, 0, rowHeight)
	end
	scroll.CanvasSize = UDim2.fromOffset(0, ROW_GAP + #rows * (rowHeight + ROW_GAP))
end

local function refreshInfo()
	local current = Config.clampClubTier(if lastPayload then lastPayload.clubTier else nil)
	infoLabel.Text = `ตอนนี้: ขั้น {current} · {Config.getClubVisual(current).name} · `
		.. `ดาเมจ {UiKit.formatShort(Config.getClubDamage(current))}/ครั้ง  (ป้ายอัปดาเมจไม่มีผลกับกระบอง)`
end

local function refreshAll()
	for _, row in rows do
		bindRow(row)
	end
	refreshInfo()
end

--------------------------------------------------------------------------------
-- สร้างหน้าต่าง
--------------------------------------------------------------------------------

function WeaponShopWindow.create(parent: ScreenGui, windowActions: Actions)
	actions = windowActions

	window = UiKit.frame({
		Name = "WeaponShopWindow",
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
		Text = "🔨 ร้านกระบอง",
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
		WeaponShopWindow.close()
	end)

	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.Position = UDim2.fromScale(0.015, 0.19)
	scroll.Size = UDim2.fromScale(0.97, 0.78)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = window

	table.clear(rows)
	for tier = 1, Config.Balance.Weapon.MAX_LEVEL do
		table.insert(rows, createRow(tier))
	end
	layoutRows()
	refreshAll()

	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutRows)
end

function WeaponShopWindow.setPayload(payload: any)
	lastPayload = payload
	if window.Visible then
		refreshAll()
	end
end

-- สถานะแถวที่วาดอยู่ตอนนี้ (smoke test ตรวจว่าแถวบนจอตรงกับ describeRow)
function WeaponShopWindow.getRowState(tier: number): RowState?
	local row = rows[tier]
	if not row then
		return nil
	end
	if row.buyButton.Visible then
		return "next"
	end
	return if row.shade.Visible then "locked" else "owned"
end

function WeaponShopWindow.isOpen(): boolean
	return window.Visible
end

-- เปิดแล้วเลื่อนให้แถว "ขั้นถัดไป" อยู่ในจอ (ผู้เล่นขั้นสูงไม่ต้องเลื่อนหาเอง)
function WeaponShopWindow.open()
	window.Visible = true
	refreshAll()
	local current = Config.clampClubTier(if lastPayload then lastPayload.clubTier else nil)
	local focus = rows[math.min(current + 1, #rows)]
	scroll.CanvasPosition = Vector2.new(0, math.max(0, focus.frame.Position.Y.Offset - ROW_GAP))
end

function WeaponShopWindow.close()
	window.Visible = false
end

return WeaponShopWindow
