--!strict
-- egg-army-game :: ป้ายอัปเกรดบนแมพ + จุดเปิดร้านขายแม่ (UI-2) + จุดเปิดแท่นอัญเชิญ (UI-3)
--
-- ตัวป้าย (เสา + แผ่นไม้) server สร้างใน MapBuilder.buildMapSigns — ไฟล์นี้ติดของที่เป็น "ของแต่ละคน":
--   · SurfaceGui (อยู่ใน PlayerGui · Adornee = แผ่นป้าย) โชว์เลเวล/ราคาของ**ผู้เล่นที่มองอยู่**
--     ห้ามเขียนค่าของใครลงป้ายฝั่ง server — คนอื่นจะเห็นเลขของคนนั้นไปด้วย
--   · ProximityPrompt (กด E · มือถือขึ้นเป็นปุ่มให้แตะ) สร้างฝั่ง client → กดแล้วยิง remote ซื้อเดิม
-- ⚠️ ป้ายค่าวิ่ง/อัปคอก server สร้างไว้ทุกคอก แต่ **เครื่องเราแสดงเฉพาะของคอกตัวเอง** (Attribute Config.PEN_INDEX_ATTRIBUTE)
--   คอกคนอื่น + คอกที่ยังไม่มีเจ้าของ: ซ่อนทั้งป้าย (syncVisibility) ไม่มีจุดกด · ป้ายชื่อ "คอก N" ไม่ถูกแตะ
--   ค่าวิ่งเป็นของบัญชีก็จริง แต่ให้ซื้อที่คอกตัวเองที่เดียวกันงง
-- ⚠️ client ไม่ตัดสินอะไร: ราคา/เพดานอ่านจาก sync · server ตรวจเงิน/เพดานซ้ำเองทุกครั้ง
-- 5C: ร้านกระบอง = แผง WeaponStallIndex (ป้าย "ซื้ออาวุธ") — จุดกด E ที่เคาน์เตอร์ → WeaponShopWindow · เดินห่างแล้วปิดเอง
-- UI-3: แท่นอัญเชิญ (server สร้างใน MapBuilder · Config.SUMMON_PEDESTAL_NAME) — จุดกด E **ค้าง** ที่แกนเรืองแสง
--   เปิดหน้าต่างอัญเชิญ (SummonWindow.lua) · เดินออกห่างเกิน SummonPedestal.CloseDistance แล้วปิดเอง
--   5B-fix: แท่นอยู่ในเลน (สนามรบ) · ข้อความบนจุดกดสลับ "อัญเชิญ" ↔ "ปิดอัญเชิญ" ตาม summonEnabled จาก sync

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local MapSigns = {}

export type SignKind = "damage" | "speed" | "pen"
export type Tone = "price" | "poor" | "max" | "capped" | "dim"
export type SignView = { title: string, level: string, detail: string, tone: Tone }

export type Actions = {
	buy: (kind: SignKind) -> (),
	openSellShop: () -> (),
	closeSellShop: () -> (),
	isSellShopOpen: () -> boolean,
	-- 5C: ร้านกระบอง (แผง "ซื้ออาวุธ") — เปิด/ปิดหน้าต่าง WeaponShopWindow
	openWeaponShop: () -> (),
	closeWeaponShop: () -> (),
	isWeaponShopOpen: () -> boolean,
	openSummon: () -> (),
	closeSummon: () -> (),
	isSummonOpen: () -> boolean,
	-- ⚠️ UI-fix รอบ 1: กด E ค้างที่แท่นตอน**กำลังอัญเชิญอยู่** = หยุดอัญเชิญทันที ไม่เปิดหน้าต่าง
	-- (ทางลัดเพิ่มเติม — ปุ่ม "หยุดอัญเชิญ" ในหน้าต่างเดิมยังอยู่เผื่อเปิดหน้าต่างค้างไว้อยู่แล้ว)
	stopSummon: () -> (),
}

type Sign = {
	kind: SignKind,
	penIndex: number?, -- nil = ป้ายดาเมจ (จุดเดียวใช้ร่วมกัน)
	name: string,
	gui: SurfaceGui,
	titleLabel: TextLabel,
	levelLabel: TextLabel,
	detailLabel: TextLabel,
	board: BasePart?,
	model: Model?, -- เสา + แผ่นป้าย (ของ server) — ซ่อนในเครื่องเราถ้าไม่ใช่คอกตัวเอง
	prompt: ProximityPrompt?,
}

local TITLES: { [string]: string } = {
	damage = "⚔️ อัปดาเมจ",
	speed = "👟 อัปความเร็ว",
	pen = "🏠 อัปคอก",
}

local TONE_COLORS: { [string]: Color3 } = {
	price = Color3.fromRGB(255, 220, 90),
	poor = Color3.fromRGB(255, 85, 85), -- เงินไม่พอ
	max = Color3.fromRGB(120, 235, 120),
	capped = Color3.fromRGB(255, 170, 70),
	dim = Color3.fromRGB(205, 205, 205),
}

local PIXELS_PER_STUD = 40
local SIGN_GUI_MAX_DISTANCE = 150
local CLOSE_POLL_SECONDS = 0.25
local SELL_COUNTER_NAME = "Counter" -- ชิ้นเคาน์เตอร์ของแผงร้าน (MapBuilder.buildShop)

local actions: Actions
local signs: { Sign } = {}
local lastPayload: any = nil
-- จุดกด E ที่แท่นอัญเชิญ (ติดทีหลังเบื้องหลัง — nil จนกว่าแท่นจะโหลดถึง)
local summonPrompt: ProximityPrompt? = nil

-- 5B-fix (ผู้ใช้สั่ง): ข้อความบนจุดกด E ของแท่นตามสถานะอัญเชิญจาก sync — กำลังอัญเชิญ = "ปิดอัญเชิญ" (กดแล้วหยุด) ·
-- ไม่ได้อัญเชิญ = "อัญเชิญ" (กดแล้วเปิดหน้าต่าง) · ตรงกับสิ่งที่ Triggered ทำจริง (UI-fix รอบ 1)
function MapSigns.getSummonActionText(summonEnabled: boolean?): string
	return if summonEnabled then "ปิดอัญเชิญ" else "อัญเชิญ"
end

local function refreshSummonPrompt()
	if summonPrompt then
		summonPrompt.ActionText = MapSigns.getSummonActionText(lastPayload and lastPayload.summonEnabled)
	end
end

--------------------------------------------------------------------------------
-- ข้อความบนป้าย — ฟังก์ชันล้วน ไม่แตะ Instance (เทสต์นอก Studio ได้ · tools/check-ui-smoke.py)
--------------------------------------------------------------------------------

-- payload = FarmStateSync ล่าสุด (nil = ยังไม่มา) · ป้ายคอกคนอื่นไม่แสดงเลย จึงไม่มีข้อความของกรณีนั้น
function MapSigns.describe(kind: SignKind, payload: any): SignView
	local title = TITLES[kind]
	if not payload then
		return { title = title, level = "", detail = "กำลังโหลด...", tone = "dim" }
	end

	-- ⚠️ ราคา nil = ซื้อต่อไม่ได้ (server คิดมาให้แล้วใน sync) — ไม่คิดเพดานเองฝั่งนี้
	local level: number
	local cost: number?
	if kind == "damage" then
		level, cost = payload.damageLevel, payload.damageUpgradeCost
	elseif kind == "speed" then
		level, cost = payload.speedLevel, payload.speedUpgradeCost
	else
		level, cost = payload.penLevel, payload.penUpgradeCost
	end
	local levelText = `Lv. {level}`

	if cost == nil then
		-- ดาเมจมีสองแบบ: ชนเพดานของด่านนี้ (พังด่านถัดไปแล้วซื้อต่อได้) กับซื้อครบทั้งเกมแล้ว (MAX)
		if kind == "damage" and level < Config.Balance.DamageUpgrade.MAX_LEVEL then
			return { title = title, level = levelText, detail = "เต็มแล้ว — พังด่านถัดไปเพื่อปลดล็อก", tone = "capped" }
		end
		return { title = title, level = levelText, detail = "MAX", tone = "max" }
	end

	local tone: Tone = if (payload.coins or 0) < cost then "poor" else "price"
	return { title = title, level = levelText, detail = `฿{UiKit.formatShort(cost)}`, tone = tone }
end

--------------------------------------------------------------------------------
-- ป้ายแต่ละอัน
--------------------------------------------------------------------------------

local function ownPenIndex(): number?
	local value = Players.LocalPlayer:GetAttribute(Config.PEN_INDEX_ATTRIBUTE)
	return if type(value) == "number" then value else nil
end

local function isOwn(sign: Sign): boolean
	return sign.penIndex == nil or sign.penIndex == ownPenIndex()
end

-- หน้าป้ายที่หันไปทาง facing (แผ่นป้ายวางตรงแกนเสมอ — MapBuilder.buildMapSign)
local function faceFor(facing: Vector3): Enum.NormalId
	if facing.X > 0.5 then
		return Enum.NormalId.Right
	elseif facing.X < -0.5 then
		return Enum.NormalId.Left
	elseif facing.Z > 0.5 then
		return Enum.NormalId.Back
	end
	return Enum.NormalId.Front
end

local function render()
	for _, sign in signs do
		local view = MapSigns.describe(sign.kind, lastPayload)
		sign.titleLabel.Text = view.title
		sign.levelLabel.Text = view.level
		sign.levelLabel.Visible = view.level ~= ""
		sign.detailLabel.Text = view.detail
		sign.detailLabel.TextColor3 = TONE_COLORS[view.tone]
	end
end

-- จุดกด E ติดเฉพาะป้ายที่กดได้ (ดาเมจ + ป้ายของคอกตัวเอง) · คอกคนอื่นไม่มีปุ่มให้กด
local function syncPrompt(sign: Sign)
	local wanted = isOwn(sign) and sign.board ~= nil
	if wanted and not sign.prompt then
		-- กดครั้งเดียวซื้อ 1 ขั้น · กดซ้ำได้ต่อเนื่อง (ไม่ต้องกดค้าง) · ใกล้ป้ายอื่นขึ้นเฉพาะอันที่ใกล้สุด (UiKit.prompt)
		local prompt = UiKit.prompt({
			Name = "UpgradePrompt",
			ActionText = "อัปเกรด",
			ObjectText = TITLES[sign.kind],
			MaxActivationDistance = Config.MapDimensions.MapSign.PromptDistance,
		})
		prompt.Triggered:Connect(function()
			actions.buy(sign.kind)
		end)
		prompt.Parent = sign.board
		sign.prompt = prompt
	elseif not wanted and sign.prompt then
		sign.prompt:Destroy()
		sign.prompt = nil
	end
end

-- ⚠️ UI-2 (ผลทดสอบ Studio): ป้ายค่าวิ่ง/อัปคอกของคอกอื่น (รวมคอกที่ยังไม่มีเจ้าของ) **ไม่แสดงเลย** ในเครื่องเรา
-- ซ่อนด้วย LocalTransparencyModifier (มีผลเฉพาะเครื่องนี้ ไม่ replicate) + ปิด SurfaceGui · จุดกดถอดใน syncPrompt
-- ป้ายชื่อ "คอก N" อยู่คนละโมเดล (MapBuilder.buildPenSign) ไม่ถูกแตะ — ยังเห็นทุกคอก
local function syncVisibility(sign: Sign)
	local shown = isOwn(sign)
	sign.gui.Enabled = shown
	local model = sign.model
	if model then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if shown then 0 else 1
			end
		end
	end
end

-- จองคอก / ย้ายคอก / ล้างตอนออก (Attribute เปลี่ยน) → ป้าย + จุดกดตามคอกใหม่
local function refreshOwnership()
	for _, sign in signs do
		syncVisibility(sign)
		syncPrompt(sign)
	end
	render()
end

local function createSign(parent: Instance, kind: SignKind, penIndex: number?, facing: Vector3): Sign
	local name = Config.getMapSignName(kind, penIndex)

	local gui = Instance.new("SurfaceGui")
	gui.Name = `Sign_{name}`
	gui.ResetOnSpawn = false
	gui.Face = faceFor(facing)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.MaxDistance = SIGN_GUI_MAX_DISTANCE
	gui.ClipsDescendants = true

	local titleLabel = UiKit.label({
		Name = "Title",
		Position = UDim2.fromScale(0.05, 0.05),
		Size = UDim2.fromScale(0.9, 0.3),
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(titleLabel, 2)
	titleLabel.Parent = gui

	local levelLabel = UiKit.label({
		Name = "Level",
		Position = UDim2.fromScale(0.05, 0.37),
		Size = UDim2.fromScale(0.9, 0.26),
		FontFace = UiKit.FONT_HEAVY_ITALIC,
	})
	UiKit.textStroke(levelLabel, 2)
	levelLabel.Parent = gui

	local detailLabel = UiKit.label({
		Name = "Detail",
		Position = UDim2.fromScale(0.05, 0.66),
		Size = UDim2.fromScale(0.9, 0.29),
		FontFace = UiKit.FONT_HEAVY,
		TextWrapped = true,
	})
	UiKit.textStroke(detailLabel, 2)
	detailLabel.Parent = gui

	gui.Parent = parent

	local sign: Sign = {
		kind = kind,
		penIndex = penIndex,
		name = name,
		gui = gui,
		titleLabel = titleLabel,
		levelLabel = levelLabel,
		detailLabel = detailLabel,
		board = nil,
		model = nil,
		prompt = nil,
	}
	table.insert(signs, sign)
	syncVisibility(sign)
	return sign
end

-- ⚠️ แผ่นป้ายเป็นของ server — client รอให้ replicate มาก่อน (โมเดลป้ายตั้ง Persistent ไว้แล้ว
-- ถ้าเปิด StreamingEnabled ก็ไม่ถูก stream ออก) · ไม่ yield ใน start()
local function attachBoard(sign: Sign)
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local folder = map and map:WaitForChild(Config.MAP_SIGN_FOLDER)
		local model = folder and folder:WaitForChild(sign.name)
		local board = model and model:WaitForChild("Board")
		if board and board:IsA("BasePart") and model and model:IsA("Model") then
			sign.board = board
			sign.model = model
			sign.gui.Adornee = board
			syncVisibility(sign)
			syncPrompt(sign)
		end
	end)
end

--------------------------------------------------------------------------------
-- ร้านขายแม่ — จุดกด E ที่เคาน์เตอร์แผงร้าน + เดินออกห่างแล้วปิดหน้าต่างเอง
--------------------------------------------------------------------------------

local function attachSellShop()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local shop = map and map:WaitForChild("Shop")
		local stall = shop and shop:WaitForChild(`Stall{Config.MapDimensions.MapSign.SellStallIndex}`)
		local counter = stall and stall:WaitForChild(SELL_COUNTER_NAME)
		if not (counter and counter:IsA("BasePart")) then
			return
		end
		local prompt = UiKit.prompt({
			Name = "SellShopPrompt",
			ActionText = "เปิดร้าน",
			ObjectText = "ร้านขายแม่",
			MaxActivationDistance = Config.MapDimensions.MapSign.SellPromptDistance,
		})
		prompt.Triggered:Connect(function()
			actions.openSellShop()
		end)
		prompt.Parent = counter
	end)
end

-- 5C: ร้านกระบอง — จุดกด E ที่เคาน์เตอร์แผง WeaponStallIndex (ป้าย "ซื้ออาวุธ") แบบเดียวกับร้านขายแม่
local function attachWeaponShop()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local shop = map and map:WaitForChild("Shop")
		local stall = shop and shop:WaitForChild(`Stall{Config.MapDimensions.MapSign.WeaponStallIndex}`)
		local counter = stall and stall:WaitForChild(SELL_COUNTER_NAME)
		if not (counter and counter:IsA("BasePart")) then
			return
		end
		local prompt = UiKit.prompt({
			Name = "WeaponShopPrompt",
			ActionText = "เปิดร้าน",
			ObjectText = "ร้านกระบอง",
			MaxActivationDistance = Config.MapDimensions.MapSign.WeaponPromptDistance,
		})
		prompt.Triggered:Connect(function()
			actions.openWeaponShop()
		end)
		prompt.Parent = counter
	end)
end

-- ⚠️ โพลระยะแทน Heartbeat — แค่ปิดหน้าต่าง ไม่ต้องละเอียดระดับเฟรม
-- ใช้ร่วมกันทั้งร้านขายแม่และแท่นอัญเชิญ: หน้าต่างเปิดอยู่ + ยืนห่างจากจุด (แนวราบ) เกิน limit → ปิด
local function watchDistance(spot: Vector3, limit: number, isOpen: () -> boolean, close: () -> ())
	task.spawn(function()
		while true do
			task.wait(CLOSE_POLL_SECONDS)
			if isOpen() then
				local character = Players.LocalPlayer.Character
				local root = character and character.PrimaryPart
				local far = true
				if root then
					local offset = Vector3.new(root.Position.X - spot.X, 0, root.Position.Z - spot.Z)
					far = offset.Magnitude > limit
				end
				if far then
					close()
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- แท่นอัญเชิญ (UI-3) — จุดกด E ค้างที่แกนเรืองแสง
--------------------------------------------------------------------------------

local function attachSummonPedestal()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local pedestal = map and map:WaitForChild(Config.SUMMON_PEDESTAL_NAME)
		local core = pedestal and pedestal:WaitForChild(Config.SUMMON_PEDESTAL_CORE)
		if not (core and core:IsA("BasePart")) then
			return
		end
		local spec = Config.MapDimensions.SummonPedestal
		-- ⚠️ ผ่าน UiKit.prompt เท่านั้น (บังคับ OnePerButton — tools/check-prompt-exclusivity.py) · กดค้าง ไม่ใช่กดครั้งเดียว
		local prompt = UiKit.prompt({
			Name = "SummonPrompt",
			ActionText = MapSigns.getSummonActionText(lastPayload and lastPayload.summonEnabled),
			ObjectText = "แท่นอัญเชิญ",
			HoldDuration = spec.PromptHoldSeconds,
			MaxActivationDistance = spec.PromptDistance,
		})
		summonPrompt = prompt
		-- ⚠️ UI-fix รอบ 1: กำลังอัญเชิญอยู่แล้ว → กด E ค้างซ้ำ = หยุดทันที ไม่เปิดหน้าต่าง
		-- (lastPayload.summonEnabled มาจาก sync ล่าสุด — client ไม่ตัดสินเอง แค่เลือกยิง remote ไหน)
		prompt.Triggered:Connect(function()
			if lastPayload and lastPayload.summonEnabled then
				actions.stopSummon()
			else
				actions.openSummon()
			end
		end)
		prompt.Parent = core
	end)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- parent = PlayerGui (SurfaceGui ต้องอยู่ใน PlayerGui ถึงจะรับข้อความรายคนได้)
function MapSigns.start(parent: Instance, signActions: Actions)
	actions = signActions

	local _, damageFacing = Config.getDamageSignSpot()
	createSign(parent, "damage", nil, damageFacing)
	for index = 1, Config.World.MAX_PENS do
		-- ⚠️ ต้องประกาศชนิดของ kind เอง — ไม่งั้น Luau ขยาย "speed" | "pen" เป็น string แล้วส่งเข้าฟังก์ชันไม่ได้
		local kinds: { Config.PenSignKind } = Config.getPenSignKinds()
		for kindIndex = 1, #kinds do
			local kind: Config.PenSignKind = kinds[kindIndex]
			local _, facing = Config.getPenUpgradeSignSpot(index, kind)
			createSign(parent, kind, index, facing)
		end
	end
	render()

	for _, sign in signs do
		attachBoard(sign)
	end
	attachSellShop()
	watchDistance(
		Config.getSellShopSpot(),
		Config.MapDimensions.MapSign.SellCloseDistance,
		actions.isSellShopOpen,
		actions.closeSellShop
	)
	attachWeaponShop()
	watchDistance(
		Config.getWeaponShopSpot(),
		Config.MapDimensions.MapSign.WeaponCloseDistance,
		actions.isWeaponShopOpen,
		actions.closeWeaponShop
	)
	attachSummonPedestal()
	watchDistance(
		Config.getSummonPedestalCenter(),
		Config.MapDimensions.SummonPedestal.CloseDistance,
		actions.isSummonOpen,
		actions.closeSummon
	)

	-- จองคอกเสร็จหลังเข้าเกม (หรือย้ายคอก) → ย้ายจุดกดไปป้ายของคอกใหม่
	Players.LocalPlayer:GetAttributeChangedSignal(Config.PEN_INDEX_ATTRIBUTE):Connect(refreshOwnership)
end

-- ⚠️ เรียกทุก sync — ซื้อแล้ว server sync ทันที ป้ายจึงเปลี่ยนเลขทันที
function MapSigns.setPayload(payload: any)
	lastPayload = payload
	render()
	refreshSummonPrompt()
end

return MapSigns
