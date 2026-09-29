--!strict
-- egg-army-game :: หน้าต่างร้านค้า Robux — UI-5 (เปิดจากปุ่ม 🛒 ร้านค้า ด้านซ้าย · แทนหน้า "เร็วๆ นี้" เดิม)
--
-- ⚠️ คนละอันกับร้านขายอาวุธเดิม (แผงหลังแมพ · Phase 5 ยังไม่เขียน) และคนละอันกับป้ายอัปเกรด
-- เงินในเกม (UI-2 · MapSigns) — ที่นี่ซื้อด้วย **Robux** เท่านั้น ทุกอย่างผ่าน
-- `MarketplaceService:PromptProductPurchase` แล้วรอผลกลับทาง sync (server เป็นคนให้ของจริง
-- ผ่าน ProcessReceipt — ดู EggService.processReceipt) หน้าต่างนี้ไม่ตัดสินอะไรเอง แค่พรอมต์ซื้อ
--
-- เลย์เอาต์: **ก้อนเดียวเลื่อนยาว** (ไม่ใช่แท็บ) — เลือกแบบนี้เพราะมีแค่ 4 การ์ดทั้งหมด (ไข่ตำนาน ·
-- ทะลุเพดานดาเมจ · ทะลุเพดานความเร็ว · เร่งฟักไข่) แท็บจะเกินความจำเป็นสำหรับรายการสั้นขนาดนี้
-- และการ์ดแต่ละใบหน้าตาไม่เหมือนกัน (ไข่มีไอคอนไข่ · ทะลุเพดานมีเลข "Lv. Robux N" · เร่ง�ฟักมีเงื่อนไขเปิด/ปิด)
-- ไม่ใช่ grid ของสิ่งเดียวกันซ้ำ ๆ แบบดัชนี/กระเป๋า จึงไม่ใช้ virtual grid (4 การ์ดตายตัว ไม่มีจำนวนไม่จำกัด)
--
-- ⚠️ ราคาโชว์จริงดึงจาก `MarketplaceService:GetProductInfo()` เท่านั้น (Config ไม่เก็บราคา Robux —
-- ดู docs/data-schema.md §8.7) แคชผลไว้ต่อ productId กันยิง network ซ้ำทุกครั้งที่เปิดหน้าต่าง
--
-- ⚠️ ปุ่ม "เร่งฟักไข่ทั้งหมด" ในนี้ทำงานเดียวกับปุ่ม "เติบโตทั้งหมด" ในแผงไข่ (SidePanels · UI-1)
-- ทั้งสองยิง MarketplaceService productId เดียวกัน (robux_hatch_rush) — เป็นแค่ทางลัดคนละจุด ไม่ใช่ logic คนละชุด

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local RobuxShopWindow = {}

export type Actions = {
	-- ⚠️ **ไม่ใช่ RemoteEvent** — ยิงตรงไปหา Roblox Marketplace ฝั่ง client (server ไม่เกี่ยวกับ
	-- ขั้นตอนนี้เลย จนกว่าจะถึง ProcessReceipt) เก็บเป็น action เดียวกับโมดูลอื่นเพื่อไม่ให้ปนกับ
	-- FireServer โดยไม่ตั้งใจ และเผื่อวันหนึ่งอยากดักจับ/บันทึกฝั่ง client ก่อนพรอมต์จริง
	buyProduct: (productId: number) -> (),
}

-- ⚠️ ตำแหน่ง/ขนาดเดียวกับหน้าต่างกระเป๋า/ดัชนี (docs/ui-overhaul-plan.md §3) — เปิดได้ทีละหน้าต่างอยู่แล้ว
local WINDOW_POSITION = UDim2.fromScale(0.235, 0.28)
local WINDOW_SIZE = UDim2.fromScale(0.484, 0.518)

local CONTENT_COLOR = Color3.fromRGB(40, 46, 58)
local CARD_COLOR = Color3.fromRGB(30, 34, 44)
local ACCENT_COLOR = Color3.fromRGB(255, 225, 150)
local HINT_COLOR = Color3.fromRGB(200, 210, 225)
local BUY_COLOR = Color3.fromRGB(80, 200, 120)
local PRICE_COLOR = Color3.fromRGB(140, 235, 255)

local player = Players.LocalPlayer
local actions: Actions
local window: Frame
local scroll: ScrollingFrame

local lastPayload: any = nil
-- แคชราคา (Robux) ต่อ productId — GetProductInfo เป็น network call ยิงครั้งเดียวพอ
local priceCache: { [number]: number? } = {}
local priceLabels: { [number]: TextLabel } = {}
-- อัปเดตส่วนที่อ่านจาก sync (Lv. Robux N · เพดานความเร็ว · มีไข่ให้เร่งไหม) — ตั้งค่าใน create()
local refreshFromPayload: (() -> ())? = nil

--------------------------------------------------------------------------------
-- ราคา (ดึงจาก Roblox โดยตรง — Config ไม่เก็บราคา Robux ตามกฎ §8.7)
--------------------------------------------------------------------------------

local function fetchPrice(productId: number, label: TextLabel)
	priceLabels[productId] = label
	local cached = priceCache[productId]
	if cached ~= nil then
		label.Text = `💎 {cached}`
		return
	end
	label.Text = "💎 ..."
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		local price = if ok and type(info) == "table" then info.PriceInRobux else nil
		priceCache[productId] = price
		-- ⚠️ label อาจถูกทิ้งไปแล้วถ้าปิดหน้าต่าง/รีสร้างระหว่างรอ — เช็ค label ปัจจุบันตรงกับตอนยิงคำขอไหม
		if priceLabels[productId] == label then
			label.Text = if price then `💎 {price}` else "💎 ?"
		end
	end)
end

--------------------------------------------------------------------------------
-- การ์ด — ตายตัว 4 ใบ ไม่ใช่ virtual grid (ดูเหตุผลหัวไฟล์)
--------------------------------------------------------------------------------

type Card = {
	frame: Frame,
	priceLabel: TextLabel,
	buyButton: TextButton,
	statusLabel: TextLabel,
}

local function makeCard(order: number, icon: string, title: string, description: string): Card
	local frame = UiKit.frame({
		Name = `Card{order}`,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = CARD_COLOR,
		BackgroundTransparency = 0.08,
	})
	UiKit.corner(frame, UDim.new(0.06, 0))
	UiKit.border(frame, UiKit.BLACK, 2)
	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0, 10)
	cardPadding.PaddingBottom = UDim.new(0, 10)
	cardPadding.PaddingLeft = UDim.new(0, 12)
	cardPadding.PaddingRight = UDim.new(0, 12)
	cardPadding.Parent = frame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Position = UDim2.fromScale(0, 0)
	iconLabel.Size = UDim2.fromOffset(48, 48)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = icon
	iconLabel.TextScaled = true
	iconLabel.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.fromOffset(58, 0)
	titleLabel.Size = UDim2.new(1, -180, 0, 22)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = ACCENT_COLOR
	titleLabel.FontFace = UiKit.FONT_HEAVY
	titleLabel.TextSize = 18
	titleLabel.Text = title
	UiKit.textStroke(titleLabel, 1)
	titleLabel.Parent = frame

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Position = UDim2.fromOffset(58, 24)
	descLabel.Size = UDim2.new(1, -180, 0, 36)
	descLabel.BackgroundTransparency = 1
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.TextColor3 = HINT_COLOR
	descLabel.TextSize = 14
	descLabel.Text = description
	descLabel.Parent = frame

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Position = UDim2.fromOffset(58, 62)
	statusLabel.Size = UDim2.new(1, -180, 0, 18)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = PRICE_COLOR
	statusLabel.FontFace = UiKit.FONT_HEAVY
	statusLabel.TextSize = 14
	statusLabel.Text = ""
	statusLabel.Parent = frame

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.AnchorPoint = Vector2.new(1, 0)
	priceLabel.Position = UDim2.new(1, 0, 0, 0)
	priceLabel.Size = UDim2.fromOffset(90, 24)
	priceLabel.BackgroundTransparency = 1
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	priceLabel.TextColor3 = PRICE_COLOR
	priceLabel.FontFace = UiKit.FONT_HEAVY
	priceLabel.TextSize = 18
	priceLabel.Text = "💎 ..."
	UiKit.textStroke(priceLabel, 1)
	priceLabel.Parent = frame

	local buyButton = UiKit.button({
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 28),
		Size = UDim2.fromOffset(90, 32),
		BackgroundColor3 = BUY_COLOR,
		Text = "ซื้อ",
	})
	UiKit.corner(buyButton, UDim.new(0.2, 0))
	UiKit.border(buyButton, UiKit.BLACK, 2)
	UiKit.textStroke(buyButton, 1)
	buyButton.Parent = frame

	-- ⚠️ กำหนดความสูงจริงตายตัว (การ์ดไม่ยืดตาม AutomaticSize ของลูกข้างในเพราะลูกวางด้วย offset ตรง ๆ)
	frame.Size = UDim2.new(1, 0, 0, 84)
	frame.Parent = scroll

	return { frame = frame, priceLabel = priceLabel, buyButton = buyButton, statusLabel = statusLabel }
end

--------------------------------------------------------------------------------
-- สร้างหน้าต่าง
--------------------------------------------------------------------------------

function RobuxShopWindow.create(parent: ScreenGui, windowActions: Actions)
	actions = windowActions

	window = UiKit.frame({
		Name = "RobuxShopWindow",
		Position = WINDOW_POSITION,
		Size = WINDOW_SIZE,
		BackgroundColor3 = CONTENT_COLOR,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	UiKit.corner(window, UDim.new(0.03, 0))
	UiKit.border(window, UiKit.BLACK, 2)
	window.Parent = parent

	local title = UiKit.label({
		Position = UDim2.fromScale(0.03, 0.025),
		Size = UDim2.fromScale(0.6, 0.075),
		Text = "💎 ร้านค้า Robux",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = ACCENT_COLOR,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(title, 1.5)
	title.Parent = window

	local closeButton = UiKit.button({
		Name = "Close",
		Position = UDim2.fromScale(0.9, 0.025),
		Size = UDim2.fromScale(0.07, 0.075),
		BackgroundColor3 = Color3.fromRGB(200, 60, 60),
		Text = "✕",
	})
	UiKit.corner(closeButton, UDim.new(0.25, 0))
	UiKit.textStroke(closeButton, 1)
	closeButton.Parent = window
	closeButton.Activated:Connect(function()
		RobuxShopWindow.close()
	end)

	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromScale(0.03, 0.12)
	scroll.Size = UDim2.fromScale(0.94, 0.85)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = window
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	----------------------------------------------------------------------------
	-- ส่วน 1: ไข่ตำนาน
	----------------------------------------------------------------------------
	local eggProduct = Config.getDeveloperProduct("legendary_egg")
	if eggProduct then
		local card = makeCard(1, "🥚", eggProduct.name, eggProduct.description)
		fetchPrice(eggProduct.productId, card.priceLabel)
		card.statusLabel.Text = "ฟักผ่านสวนฟักปกติ (ต้องมีที่ว่างในกระเป๋าไข่)"
		card.buyButton.Activated:Connect(function()
			actions.buyProduct(eggProduct.productId)
		end)
	end

	----------------------------------------------------------------------------
	-- ส่วน 2: ทะลุเพดาน (ดาเมจ + ความเร็ว)
	----------------------------------------------------------------------------
	local dmgProduct = Config.getRobuxProduct("robux_damage_step")
	local dmgCard: Card?
	if dmgProduct then
		dmgCard = makeCard(2, "⚔️", dmgProduct.name, dmgProduct.description)
		fetchPrice(dmgProduct.productId, (dmgCard :: Card).priceLabel)
		;(dmgCard :: Card).buyButton.Activated:Connect(function()
			actions.buyProduct(dmgProduct.productId)
		end)
	end

	local spdProduct = Config.getRobuxProduct("robux_speed_step")
	local spdCard: Card?
	if spdProduct then
		spdCard = makeCard(3, "👟", spdProduct.name, spdProduct.description)
		fetchPrice(spdProduct.productId, (spdCard :: Card).priceLabel)
		;(spdCard :: Card).buyButton.Activated:Connect(function()
			-- ⚠️ ถึงเพดานความปลอดภัยแล้ว (ปิดใน refresh() ข้างล่าง) → ไม่ยิงซื้อซ้ำ กันเสีย Robux ฟรี
			if (spdCard :: Card).buyButton.AutoButtonColor then
				actions.buyProduct(spdProduct.productId)
			end
		end)
	end

	----------------------------------------------------------------------------
	-- ส่วน 3: เร่งฟักไข่ทั้งหมด
	----------------------------------------------------------------------------
	local rushProduct = Config.getRobuxProduct("robux_hatch_rush")
	local rushCard: Card?
	if rushProduct then
		rushCard = makeCard(4, "⏩", rushProduct.name, rushProduct.description)
		fetchPrice(rushProduct.productId, (rushCard :: Card).priceLabel)
		;(rushCard :: Card).buyButton.Activated:Connect(function()
			if (rushCard :: Card).buyButton.AutoButtonColor then
				actions.buyProduct(rushProduct.productId)
			end
		end)
	end

	----------------------------------------------------------------------------
	-- อัปเดตส่วนที่ต้องอ่านจาก sync (Lv. Robux N · เพดานความเร็ว · มีไข่ให้เร่งไหม)
	----------------------------------------------------------------------------
	local function refresh()
		local payload = lastPayload
		if not payload then
			return
		end

		if dmgCard then
			(dmgCard :: Card).statusLabel.Text = `Lv. Robux {payload.robuxDamageBonus or 0} — ไม่มีเพดาน`
		end

		if spdCard then
			-- ⚠️ ถึงเพดานความปลอดภัยของแมพแล้ว (Config.getRobuxSpeedHardCap — ผูกกับความหนากำแพงที่สร้างไว้จริง)
			-- → ปิดปุ่มซื้อ กันเสีย Robux ไปแบบไม่ได้อะไรเลย (ตัวเลขจริงยัง clamp ที่ server อยู่ดี
			-- นี่แค่กันเสียเงินฟรี ไม่ใช่ตัวตัดสินหลัก)
			local atCap = (payload.walkSpeed or 0) >= (payload.robuxSpeedHardCap or math.huge) - 0.01
			local c = spdCard :: Card
			c.statusLabel.Text = if atCap
				then `Lv. Robux {payload.robuxSpeedBonus or 0} — ถึงเพดานความปลอดภัยของแมพแล้ว`
				else `Lv. Robux {payload.robuxSpeedBonus or 0} (ความเร็วจริง {math.floor(payload.walkSpeed or 0)})`
			c.buyButton.BackgroundColor3 = if atCap then UiKit.DISABLED else BUY_COLOR
			c.buyButton.AutoButtonColor = not atCap
		end

		if rushCard then
			local canRush = (payload.hatchingCount or 0) > 0
			local c = rushCard :: Card
			c.statusLabel.Text = if canRush
				then `มีไข่กำลังฟัก {payload.hatchingCount} ฟอง — เร่งได้ทันที`
				else "ไม่มีไข่กำลังฟักอยู่ตอนนี้"
			c.buyButton.BackgroundColor3 = if canRush then BUY_COLOR else UiKit.DISABLED
			c.buyButton.AutoButtonColor = canRush
		end
	end

	refreshFromPayload = refresh
end

function RobuxShopWindow.setPayload(payload: any)
	lastPayload = payload
	if window.Visible and refreshFromPayload then
		refreshFromPayload()
	end
end

function RobuxShopWindow.isOpen(): boolean
	return window.Visible
end

function RobuxShopWindow.open()
	window.Visible = true
	if refreshFromPayload then
		refreshFromPayload()
	end
end

function RobuxShopWindow.close()
	window.Visible = false
end

return RobuxShopWindow
