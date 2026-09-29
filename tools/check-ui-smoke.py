# -*- coding: utf-8 -*-
"""Smoke test ของ UI ฝั่ง client (UI-1 · UI-2 · UI-3 · UI-4 · UI-5 · Phase 5A · 5C · 5D): Hotbar · BagWindow · SidePanels · UiKit · SellWindow
· MapSigns · SummonWindow · IndexWindow · RobuxShopWindow · BossHud · WeaponShopWindow · HealthBar · NightSky

    python3 tools/check-ui-smoke.py

⚠️ วิธีทำงาน: โหลดซอร์สจริงของโมดูล UI ด้วย loadstring แล้วรันกับ "Roblox จำลอง" (Instance/UDim2/Enum
ปลอมแบบเก็บค่าเฉย ๆ) — **ไม่ได้ตรวจหน้าตา/ตำแหน่งบนจอ** (ต้องดูใน Studio) ตรวจแค่ว่า:
  · สร้าง UI + รับ sync payload หน้าตาเหมือนของ server จริง แล้ว**ไม่ error** (error ใน handler ของ sync
    = UI ทั้งจอหยุดอัปเดตในเกมจริง — type check จับเคสแบบนี้ไม่ได้)
  · ปุ่มยิง action ที่ถูกตัวพร้อมค่าที่ถูก (uid / id ประจำฟองไข่) · ปุ่มที่ต้องปิดถูกปิดจริง
Config เป็นของจริง (require ตรง) ส่วน Roblox API เป็นของปลอมทั้งหมด
"""
import os, subprocess, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAU = os.environ.get('LUAU') or shutil.which('luau')
if not LUAU:
    sys.exit('หา luau CLI ไม่เจอ — ติดตั้งแล้วใส่ใน PATH หรือสั่ง LUAU=/path/to/luau python3 ...')

MODULES = ['UiKit', 'Hotbar', 'BagWindow', 'SidePanels', 'SellWindow', 'MapSigns', 'SummonWindow', 'IndexWindow', 'RobuxShopWindow', 'BossHud', 'WeaponShopWindow', 'HealthBar', 'NightSky']

MOCK = r'''--!nocheck
local Config = require("./src/shared/Config")

local passCount, failCount = 0, 0
local function check(label, got, want)
	if want == nil then
		want = true
	end
	if got == want then
		passCount += 1
		print(`  ✓ {label}`)
	else
		failCount += 1
		print(`  ✗ {label}: ได้ "{tostring(got)}" ต้องการ "{tostring(want)}"`)
	end
end

--------------------------------------------------------------------------------
-- datatypes ปลอม
--------------------------------------------------------------------------------
local function typed(kind, t)
	return setmetatable(t, { __type = kind })
end
local function mockTypeof(v)
	local mt = getmetatable(v)
	if type(v) == "table" and mt and mt.__type then
		return mt.__type
	end
	return type(v)
end

local Vector2 = {}
function Vector2.new(x, y)
	return typed("Vector2", { X = x or 0, Y = y or 0 })
end
Vector2.zero = Vector2.new(0, 0)
-- Vector3 บวก/คูณเลขได้ + Magnitude — พอสำหรับ UiKit.setPortrait วางกล้องใน ViewportFrame (UI-4 เงาโมเดล)
local Vector3Meta = { __type = "Vector3" }
local Vector3 = {}
function Vector3.new(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	return setmetatable({ X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) }, Vector3Meta)
end
Vector3Meta.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3Meta.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
local UDim = { new = function(s, o) return typed("UDim", { Scale = s or 0, Offset = o or 0 }) end }
local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return typed("UDim2", { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) })
end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
local Color3 = {
	new = function(r, g, b) return typed("Color3", { R = r, G = g, B = b }) end,
	fromRGB = function(r, g, b) return typed("Color3", { R = r / 255, G = g / 255, B = b / 255 }) end,
}
local Font = { new = function(family, weight, style) return typed("Font", { Family = family, Weight = weight, Style = style }) end }
local ColorSequence = { new = function(k) return typed("ColorSequence", { Keypoints = k }) end }
local ColorSequenceKeypoint = { new = function(t, c) return typed("ColorSequenceKeypoint", { Time = t, Value = c }) end }
-- CFrame: lookAt (กล้องรูปตัวละคร) + new/Angles/คูณกัน (MotherModels.build ประกอบโมเดลจาก Part) — เก็บค่า ไม่คำนวณจริง
local CFrameMeta = { __type = "CFrame" }
CFrameMeta.__mul = function(a, _b) return a end
CFrameMeta.__index = { Inverse = function(self) return self end } -- Weld.C0 ของ rig (MotherModels.build)
local CFrame = {
	lookAt = function(a, b) return setmetatable({ a = a, b = b, Position = a }, CFrameMeta) end,
	new = function(x, y, z) return setmetatable({ Position = Vector3.new(x, y, z) }, CFrameMeta) end,
	Angles = function(rx, ry, rz) return setmetatable({ rx = rx, ry = ry, rz = rz }, CFrameMeta) end,
}
local Enum = setmetatable({}, {
	__index = function(_, enumName)
		return setmetatable({}, { __index = function(_, item) return `Enum.{enumName}.{item}` end })
	end,
})

--------------------------------------------------------------------------------
-- signal / Instance ปลอม
--------------------------------------------------------------------------------
local function newSignal()
	local signal = { handlers = {} }
	function signal:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
	end
	function signal:Fire(...)
		for _, handler in self.handlers do
			handler(...)
		end
	end
	return signal
end

local DEFAULTS = {
	Visible = true,
	Text = "",
	CanvasPosition = Vector2.zero,
	AbsoluteSize = Vector2.new(800, 400),
	AutoButtonColor = true,
	Active = false,
}

local Methods = {}
local InstanceMeta = {}

local function newInstance(className)
	local object = {
		__class = className,
		__props = { Name = className },
		__children = {},
		__attrs = {},
		__attrSignals = {},
		__propSignals = {},
		Activated = newSignal(),
		Triggered = newSignal(), -- ProximityPrompt
		PromptButtonHoldBegan = newSignal(), -- ProximityPrompt (5B-2: ไข่บอสบอก server ว่าเริ่มกดค้าง)
		PromptButtonHoldEnded = newSignal(),
	}
	return setmetatable(object, InstanceMeta)
end

InstanceMeta.__type = "Instance"
InstanceMeta.__index = function(self, key)
	local method = Methods[key]
	if method then
		return method
	end
	local value = rawget(self, "__props")[key]
	if value ~= nil then
		return value
	end
	for _, child in rawget(self, "__children") do
		if child.Name == key then
			return child
		end
	end
	return DEFAULTS[key]
end
InstanceMeta.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key == "Parent" then
		local old = props.Parent
		if old then
			local siblings = rawget(old, "__children")
			for index, child in siblings do
				if child == self then
					table.remove(siblings, index)
					break
				end
			end
		end
		if value then
			table.insert(rawget(value, "__children"), self)
		end
	end
	props[key] = value
	local signal = rawget(self, "__propSignals")[key]
	if signal then
		signal:Fire()
	end
end

function Methods.GetChildren(self)
	return table.clone(rawget(self, "__children"))
end
function Methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in rawget(node, "__children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function Methods.FindFirstChild(self, name)
	for _, child in rawget(self, "__children") do
		if child.Name == name then
			return child
		end
	end
	return nil
end
Methods.WaitForChild = Methods.FindFirstChild
function Methods.FindFirstChildOfClass(self, className)
	for _, child in rawget(self, "__children") do
		if rawget(child, "__class") == className then
			return child
		end
	end
	return nil
end
-- โมเดลตัวละคร (เทมเพลตใน ReplicatedStorage.MotherModelTemplates) — พอให้ UiKit.setPortrait สร้าง ViewportFrame ได้
function Methods.Clone(self)
	local copy = newInstance(rawget(self, "__class"))
	for key, value in rawget(self, "__props") do
		if key ~= "Parent" then
			rawget(copy, "__props")[key] = value
		end
	end
	for _, child in rawget(self, "__children") do
		child:Clone().Parent = copy
	end
	return copy
end
function Methods.GetBoundingBox(_self)
	return typed("CFrame", { Position = Vector3.new(0, 2, 0) }), Vector3.new(2, 4, 2)
end
function Methods.GetPivot(_self)
	return typed("CFrame", { Position = Vector3.new(0, 0, 0), LookVector = Vector3.new(0, 0, -1), RightVector = Vector3.new(1, 0, 0) })
end
function Methods.IsA(self, className)
	local own = rawget(self, "__class")
	if own == className then
		return true
	end
	if className == "GuiObject" or className == "GuiBase2d" then
		return own == "Frame" or own == "TextLabel" or own == "TextButton" or own == "TextBox"
			or own == "ScrollingFrame" or own == "ViewportFrame"
	end
	if className == "BasePart" then
		return own == "Part"
	end
	return false
end
function Methods.Destroy(self)
	self.Parent = nil
	rawset(self, "__destroyed", true)
end
function Methods.GetPropertyChangedSignal(self, prop)
	local signals = rawget(self, "__propSignals")
	signals[prop] = signals[prop] or newSignal()
	return signals[prop]
end
function Methods.SetAttribute(self, name, value)
	rawget(self, "__attrs")[name] = value
	local signal = rawget(self, "__attrSignals")[name]
	if signal then
		signal:Fire()
	end
end
function Methods.GetAttributeChangedSignal(self, name)
	local signals = rawget(self, "__attrSignals")
	signals[name] = signals[name] or newSignal()
	return signals[name]
end
function Methods.GetAttribute(self, name)
	return rawget(self, "__attrs")[name]
end

local Instance = { new = newInstance }

local function descendants(root, out)
	out = out or {}
	for _, child in rawget(root, "__children") do
		table.insert(out, child)
		descendants(child, out)
	end
	return out
end
local function findDescendant(root, name)
	for _, d in descendants(root) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- บริการปลอม
--------------------------------------------------------------------------------
local camera = newInstance("Camera")
camera.ViewportSize = Vector2.new(1920, 1080)
local workspaceMock = newInstance("Workspace")
workspaceMock.CurrentCamera = camera
local localPlayer = newInstance("Player")
local services = {
	UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = newSignal() },
	Workspace = workspaceMock,
	ReplicatedStorage = newInstance("ReplicatedStorage"),
	Players = { LocalPlayer = localPlayer },
	-- UI-5: RobuxShopWindow ดึงราคาแสดงผลผ่านตัวนี้ (ไม่ได้ยิงซื้อจริงจากในโมดูล — นั่นอยู่ที่ actions.buyProduct)
	MarketplaceService = {
		GetProductInfo = function(_, productId, infoType)
			return { PriceInRobux = 1 }
		end,
	},
}
local sharedFolder = newInstance("Folder")
sharedFolder.Name = "Shared"
sharedFolder.Parent = services.ReplicatedStorage
local configMarker = newInstance("ModuleScript")
configMarker.Name = "Config"
configMarker.Parent = sharedFolder

local game = { GetService = function(_, name) return services[name] or error(`ไม่มีบริการปลอม {name}`) end }

local loaded = {}
local clientFolder = newInstance("Folder")
local function mockRequire(target)
	if target == configMarker then
		return Config
	end
	local module = loaded[target.Name]
	if module == nil then
		error(`mock require: ยังไม่ได้โหลด {target.Name}`)
	end
	return module
end

local task = {
	spawn = function() end,
	delay = function() end,
	wait = function() end,
	defer = function() end,
}

local __env = {
	game = game,
	require = mockRequire,
	Instance = Instance,
	UDim = UDim,
	UDim2 = UDim2,
	Vector2 = Vector2,
	Vector3 = Vector3,
	Color3 = Color3,
	Font = Font,
	Enum = Enum,
	ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	CFrame = CFrame,
	task = task,
	typeof = mockTypeof,
}

local function loadModule(name, source)
	local marker = newInstance("ModuleScript")
	marker.Name = name
	marker.Parent = clientFolder
	__env.script = { Parent = clientFolder }
	local chunk = loadstring(source, name)
	loaded[name] = chunk(__env)
end
'''

PRELUDE = '''
local __env = ...
local game = __env.game
local script = __env.script
local require = __env.require
local Instance = __env.Instance
local UDim = __env.UDim
local UDim2 = __env.UDim2
local Vector2 = __env.Vector2
local Vector3 = __env.Vector3
local Color3 = __env.Color3
local Font = __env.Font
local Enum = __env.Enum
local ColorSequence = __env.ColorSequence
local ColorSequenceKeypoint = __env.ColorSequenceKeypoint
local CFrame = __env.CFrame
local task = __env.task
local typeof = __env.typeof
'''

CHECK = r'''
__LOAD_MODULES__

local Hotbar = loaded.Hotbar
local BagWindow = loaded.BagWindow
local SidePanels = loaded.SidePanels
local UiKit = loaded.UiKit

-- payload หน้าตาเหมือน EggService.buildSyncPayload จริง (เฉพาะฟิลด์ที่ UI ใช้)
local function mother(uid, charId, weight, locked, cpm)
	local character = Config.getCharacter(charId)
	return {
		uid = uid,
		charId = charId,
		charName = character.name,
		class = character.class,
		weight = weight,
		weightText = Config.formatWeight(weight),
		locked = locked,
		coinsPerMinute = cpm,
		-- ⚠️ ราคาขายมาจาก server (Config.getMotherSellPrice) — ในเทสต์ตั้ง 30 × cpm ให้คิดยอดรวมง่าย
		sellPrice = cpm * 30,
	}
end

local function makePayload()
	local hatching = {}
	for index = 1, 50 do
		hatching[index] = { occupied = false }
	end
	hatching[3] = { occupied = true, eggId = "egg_stage2", eggName = "ไข่ด่าน 2", weight = 500, weightText = "500", remaining = 3600, total = 7200, stuck = false }
	hatching[7] = { occupied = true, eggId = "egg_stage1", eggName = "ไข่ด่าน 1", weight = 100, weightText = "100", remaining = 0, total = 60, stuck = true }
	local held = {}
	for id = 1, 12 do
		table.insert(held, {
			id = id,
			eggId = if id <= 8 then "egg_stage1" else "egg_stage3",
			eggName = if id <= 8 then "ไข่ด่าน 1" else "ไข่ด่าน 3",
			weight = if id <= 5 then 300 else 900,
			weightText = if id <= 5 then "300" else "900",
		})
	end
	local bag = {}
	for index = 1, 23 do
		table.insert(bag, mother(`1-{100 + index}`, if index % 2 == 0 then "pig" else "monkey", 100 * index, index == 1, index))
	end
	return {
		mothersInPen = { mother("1-1", "wukong", 50000, false, 50), mother("1-2", "horse", 800, true, 9) },
		mothersInBag = bag,
		penCapacity = 5,
		bagCapacity = 100,
		heldEggs = held,
		heldCount = 12,
		heldShown = 12,
		bagSize = 10000,
		hatching = hatching,
		hatchingCount = 2,
		hatcherySize = 50,
		stuckHatchCount = 1,
		battleRoster = {},
		coins = 12345,
		speedLevel = 2,
		speedUpgradeCost = 100000,
		damageLevel = 7,
		damageUpgradeCost = 5000,
		penLevel = 3,
		penUpgradeCost = 10000,
	}
end

local gui = Instance.new("ScreenGui")

print("\n━━ Hotbar: PC 10 ช่อง · ย่อให้พอดีที่ว่าง ━━")
do
	Hotbar.create(gui, function() return 400 end)
	local bar = findDescendant(gui, "Hotbar")
	check("สร้างแถบ Hotbar", bar ~= nil)
	local slots = 0
	for _, child in bar:GetChildren() do
		if string.sub(child.Name, 1, 4) == "Slot" then
			slots += 1
		end
	end
	check("PC = 10 ช่อง", slots, 10)
	check("กว้างไม่เกินที่ว่าง (1920 − 2×400)", bar.Size.X.Offset <= 1920 - 800 + 0.001)
	services.UserInputService.TouchEnabled = true
	services.UserInputService.KeyboardEnabled = false
	Hotbar.relayout()
	slots = 0
	for _, child in bar:GetChildren() do
		if string.sub(child.Name, 1, 4) == "Slot" then
			slots += 1
		end
	end
	check("มือถือ = 5 ช่อง", slots, 5)
	services.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Two }, false)
	check("กดเลข 2 → ช่อง 2 ถูกเลือก", findDescendant(bar.Slot2, "Selected").Enabled, true)
	services.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Two }, true)
	check("พิมพ์ในแชต (gameProcessed) ไม่เปลี่ยนการเลือก", findDescendant(bar.Slot2, "Selected").Enabled, true)
end

local calls = {}
local function record(name)
	return function(...)
		table.insert(calls, { name = name, args = table.pack(...) })
	end
end
local function lastCall()
	return calls[#calls]
end

print("\n━━ BagWindow: สร้าง + sync + เปิด ━━")
local payload = makePayload()
do
	BagWindow.create(gui, {
		moveMother = record("moveMother"),
		toggleLock = record("toggleLock"),
		placeEgg = record("placeEgg"),
		notify = record("notify"),
	})
	local ok = pcall(BagWindow.setPayload, payload)
	check("setPayload ตอนหน้าต่างปิดไม่ error", ok)
	ok = pcall(BagWindow.open)
	check("เปิดหน้าต่างไม่ error", ok)
	check("isOpen", BagWindow.isOpen())
end

local window = findDescendant(gui, "BagWindow")
local grid = findDescendant(window, "Grid")
local function visibleCards()
	local cards = {}
	for _, child in grid:GetChildren() do
		if child.Name == "Card" and child.Visible then
			table.insert(cards, child)
		end
	end
	return cards
end

print("\n━━ BagWindow: แท็บสัตว์เลี้ยง (virtual grid) ━━")
do
	local cards = visibleCards()
	check("มีการ์ดโชว์", #cards > 0)
	check("ไม่สร้างการ์ดครบ 25 ใบพร้อมกัน (สร้างเท่าที่เห็น)", #grid:GetChildren() < 25)
	local firstCard = cards[1]
	check("การ์ดแรก = แม่ในคอกรายได้สูงสุด (ป้ายคอก)", findDescendant(firstCard, "PenTag").Visible, true)
	check("  ชื่อ + น้ำหนัก", string.find(findDescendant(firstCard, "NameLabel").Text, "ซุนหงอคง", 1, true) ~= nil)
	local lockedPen = cards[2]
	check("แม่ที่ล็อกมีป้าย 🔒", findDescendant(lockedPen, "LockBadge").Visible, true)
	check("รูปตัวละคร (ไม่มีโมเดล = กล่องสี)", findDescendant(firstCard, "Portrait") ~= nil)

	grid.CanvasPosition = Vector2.new(0, 10000)
	check("เลื่อนลงสุดแล้วยังไม่ error และมีการ์ด", #visibleCards() > 0)
	grid.CanvasPosition = Vector2.zero
end

print("\n━━ BagWindow: หน้ารายละเอียดแม่ในกระเป๋า ━━")
do
	-- การ์ดใบที่ 3 = แม่ในกระเป๋ารายได้สูงสุด (index 23)
	local card = visibleCards()[3]
	card.Activated:Fire()
	local detail = findDescendant(window, "Detail")
	check("กดการ์ด → หน้ารายละเอียดเปิด", detail.Visible, true)
	check("  ปุ่ม 1 = ล็อก", findDescendant(detail, "Action1").Text, "🔒 ล็อก")
	findDescendant(detail, "Action1").Activated:Fire()
	check("  กดล็อก → toggleLock(uid)", lastCall().name == "toggleLock" and lastCall().args[1] == "1-123", true)
	check("  ปุ่มย้ายเข้าคอก (คอกไม่เต็ม)", findDescendant(detail, "Action2").Text, "ย้ายเข้าคอก")
	findDescendant(detail, "Action2").Activated:Fire()
	check("  กดย้าย → moveMother(uid, pen)", lastCall().name == "moveMother" and lastCall().args[2] == "pen", true)
	-- UI-2: ปุ่มขาย (TEMP) ย้ายไปร้านขายแม่แล้ว · UI-3: ปุ่มส่งไปรบ (TEMP) ย้ายไปแท่นอัญเชิญแล้ว
	local anySell, anyBattle = false, false
	for index = 1, 4 do
		local button = findDescendant(detail, `Action{index}`)
		if button.Visible and string.find(button.Text, "ขาย", 1, true) then
			anySell = true
		end
		if button.Visible and string.find(button.Text, "รบ", 1, true) then
			anyBattle = true
		end
	end
	check("  ไม่มีปุ่มขายในหน้ารายละเอียดแล้ว (UI-2)", anySell, false)
	check("  ไม่มีปุ่มส่งไปรบในหน้ารายละเอียดแล้ว (UI-3)", anyBattle, false)
	check("  ปุ่ม 3 ซ่อน", findDescendant(detail, "Action3").Visible, false)
	check("  ปุ่ม 4 ซ่อน", findDescendant(detail, "Action4").Visible, false)

	-- แม่ในกระเป๋าที่ล็อก → ปุ่ม 1 เป็นปลดล็อก · ยังไม่มีปุ่มส่งรบ
	payload.mothersInBag[23].locked = true
	BagWindow.setPayload(payload)
	check("ล็อกแล้ว: ปุ่ม 1 = ปลดล็อก", findDescendant(detail, "Action1").Text, "🔓 ปลดล็อก")
	check("  ไม่มีปุ่มส่งรบ", findDescendant(detail, "Action3").Visible, false)
	payload.mothersInBag[23].locked = false

	-- คอกเต็ม → ปุ่มย้ายเข้าคอกถูกปิด
	payload.penCapacity = 2
	BagWindow.setPayload(payload)
	check("คอกเต็ม: ปุ่มย้ายเข้าคอกถูกปิด", findDescendant(detail, "Action2").AutoButtonColor, false)
	payload.penCapacity = 5

	-- แม่หายจาก payload (ขาย/ส่งไปแล้ว) → หน้ารายละเอียดปิดเอง
	table.remove(payload.mothersInBag, 23)
	BagWindow.setPayload(payload)
	check("แม่หายจาก sync → หน้ารายละเอียดปิด", detail.Visible, false)
end

print("\n━━ BagWindow: แม่ในคอก → ย้ายออก ไม่มีปุ่มขาย/ส่งรบ ━━")
do
	visibleCards()[1].Activated:Fire()
	local detail = findDescendant(window, "Detail")
	check("ปุ่มย้ายออกจากคอก", findDescendant(detail, "Action2").Text, "ย้ายออกจากคอก → กระเป๋า")
	findDescendant(detail, "Action2").Activated:Fire()
	check("  → moveMother(uid, bag)", lastCall().name == "moveMother" and lastCall().args[1] == "1-1" and lastCall().args[2] == "bag", true)
	check("  ไม่มีปุ่มส่งรบ", findDescendant(detail, "Action3").Visible, false)
	check("  ไม่มีปุ่มที่ 4", findDescendant(detail, "Action4").Visible, false)
end

print("\n━━ BagWindow: แท็บไข่ (สแต็คตามชนิด+น้ำหนัก) ━━")
do
	findDescendant(window, "Tab_eggs").Activated:Fire()
	local cards = visibleCards()
	check("ไข่ 12 ฟองรวมเป็น 3 กอง", #cards, 3)
	check("กองแรก = หนักสุด ×4", findDescendant(cards[1], "CountTag").Text, "×4")
	cards[1].Activated:Fire()
	local detail = findDescendant(window, "Detail")
	check("กดกองไข่ → หน้ารายละเอียด", detail.Visible, true)
	findDescendant(detail, "Action1").Activated:Fire()
	check("  วางลงสวนฟัก → placeEgg(id ฟองแรกของกอง)", lastCall().name == "placeEgg" and lastCall().args[1] == 9, true)
	payload.hatchingCount = 50
	BagWindow.setPayload(payload)
	check("สวนฟักเต็ม → ปุ่มวางถูกปิด", findDescendant(detail, "Action1").AutoButtonColor, false)
	payload.hatchingCount = 2
end

print("\n━━ BagWindow: ค้นหา + แท็บไอเทม ━━")
do
	findDescendant(window, "Tab_pets").Activated:Fire()
	local search = findDescendant(window, "Search")
	search.Text = "หมู"
	local cards = visibleCards()
	local allPig = #cards > 0
	for _, card in cards do
		if not string.find(findDescendant(card, "NameLabel").Text, "หมู", 1, true) then
			allPig = false
		end
	end
	check("ค้นหา \"หมู\" → เหลือแต่หมู", allPig)
	search.Text = "ไม่มีชื่อนี้"
	check("ค้นหาไม่เจอ → ไม่มีการ์ด", #visibleCards(), 0)
	search.Text = ""
	findDescendant(window, "Tab_items").Activated:Fire()
	check("แท็บไอเทม: ไม่มีการ์ด", #visibleCards(), 0)
	BagWindow.close()
	check("ปิดหน้าต่าง", BagWindow.isOpen(), false)
end

print("\n━━ SidePanels: ปุ่มขวา + แผงไข่ ━━")
do
	SidePanels.create(gui, { unequip = record("unequip"), equipBest = record("equipBest"), rushHatching = record("rushHatching") })
	local ok = pcall(SidePanels.setPayload, payload)
	check("setPayload ไม่ error", ok)
	local badge = findDescendant(findDescendant(gui, "EggButton"), "Badge")
	check("จุดแดง = ไข่ที่ฟักเสร็จแต่ค้าง 1 ฟอง", badge.Visible == true and badge.Text == "1", true)
	findDescendant(gui, "EggButton").Activated:Fire()
	local eggPanel = findDescendant(gui, "eggsPanel")
	check("เปิดแผงไข่", eggPanel.Visible, true)
	check("  คอลัมน์ปุ่มถูกซ่อน", findDescendant(gui, "SideButtons").Visible, false)
	local rows = {}
	for _, child in findDescendant(eggPanel, "List"):GetChildren() do
		if child.Name == "Row" then
			table.insert(rows, child)
		end
	end
	check("  แถวละฟองที่กำลังฟัก (2)", #rows, 2)
	local texts = {}
	for _, row in rows do
		for _, d in descendants(row) do
			if d.__class == "TextLabel" and d.Text ~= "" then
				texts[d.Text] = true
			end
		end
	end
	check("  ฟองที่ค้าง → \"เสร็จ — รอที่ว่าง\"", texts["เสร็จ — รอที่ว่าง"] == true)
	check("  ฟองที่กำลังฟัก → เวลาเหลือ 1h 0m", texts["1h 0m"] == true)

	-- UI-5: ปุ่ม "เติบโตทั้งหมด" — มีไข่กำลังฟัง (2 ฟอง) → เปิดใช้งาน กดแล้วเรียก rushHatching
	local growAllButton = findDescendant(eggPanel, "HeaderButton")
	check("มีไข่กำลังฟัก → ปุ่ม \"เติบโตทั้งหมด\" เปิดใช้งาน", growAllButton.AutoButtonColor, true)
	growAllButton.Activated:Fire()
	check("กด \"เติบโตทั้งหมด\" → เรียก rushHatching", lastCall().name, "rushHatching")

	-- ไม่มีไข่กำลังฟักเลย → ปุ่มถูกปิด กดแล้วไม่เรียกอะไร
	payload.hatching[3] = { occupied = false }
	payload.hatching[7] = { occupied = false }
	SidePanels.setPayload(payload)
	check("ไม่มีไข่กำลังฟักเลย → ปุ่มถูกปิด", growAllButton.AutoButtonColor, false)
	local beforeRush = #calls
	growAllButton.Activated:Fire()
	check("  กดปุ่มที่ปิดแล้ว → ไม่เรียก rushHatching ซ้ำ", #calls, beforeRush)
	-- คืนสภาพให้เทสต์ถัดไปที่อ้าง hatchingCount=2 ยังใช้ payload เดิมได้
	payload.hatching[3] = { occupied = true, eggId = "egg_stage2", eggName = "ไข่ด่าน 2", weight = 500, weightText = "500", remaining = 3600, total = 7200, stuck = false }
	payload.hatching[7] = { occupied = true, eggId = "egg_stage1", eggName = "ไข่ด่าน 1", weight = 100, weightText = "100", remaining = 0, total = 60, stuck = true }
	SidePanels.setPayload(payload)

	findDescendant(eggPanel, "CloseTab").Activated:Fire()
	check("กด \">\" → ปิดแผง ปุ่มกลับมา", eggPanel.Visible == false and findDescendant(gui, "SideButtons").Visible == true, true)
end

print("\n━━ SidePanels: แผงเท้า ━━")
do
	findDescendant(gui, "PawButton").Activated:Fire()
	local pawPanel = findDescendant(gui, "pawPanel")
	check("เปิดแผงเท้า", pawPanel.Visible, true)
	local headerTitle = nil
	for _, child in findDescendant(pawPanel, "Header"):GetChildren() do
		if child.__class == "TextLabel" then
			headerTitle = child
		end
	end
	check("หัวแผง = แม่ในคอก/ความจุ", headerTitle and headerTitle.Text, "2/5 Active")
	findDescendant(pawPanel, "HeaderButton").Activated:Fire()
	check("สวมใส่ที่ดีที่สุด → equipBest", lastCall().name, "equipBest")
	local unequip = findDescendant(pawPanel, "Unequip")
	unequip.Activated:Fire()
	check("ถอดออก → unequip(uid)", lastCall().name == "unequip" and type(lastCall().args[1]) == "string", true)

	payload.mothersInBag = {}
	for index = 1, 100 do
		table.insert(payload.mothersInBag, mother(`9-{index}`, "fish", 100, false, 1))
	end
	SidePanels.setPayload(payload)
	local before = #calls
	findDescendant(pawPanel, "Unequip").Activated:Fire()
	check("กระเป๋าเต็ม → ปุ่มถอดออกไม่ยิงอะไร", #calls, before)
	check("  ข้อความ \"กระเป๋าเต็ม\"", findDescendant(pawPanel, "Unequip").Text, "กระเป๋าเต็ม")
	payload.mothersInPen = {}
	local ok = pcall(SidePanels.setPayload, payload)
	check("คอกว่าง → แถวถูกลบ ไม่ error", ok and findDescendant(pawPanel, "Row") == nil, true)
end

print("\n━━ UiKit: รูปแบบตัวเลข/เวลา ━━")
do
	check("formatShort 1234 → 1.2K", UiKit.formatShort(1234), "1.2K")
	check("formatShort 5000000 → 5M", UiKit.formatShort(5000000), "5M")
	check("formatShort 950 → 950", UiKit.formatShort(950), "950")
	check("formatDuration 8580 → 2h 23m", UiKit.formatDuration(8580), "2h 23m")
	check("formatDuration 303 → 5m 03s", UiKit.formatDuration(303), "5m 03s")
	check("formatDuration 45 → 45s", UiKit.formatDuration(45), "45s")
	check("formatComma 1234567 → 1,234,567", UiKit.formatComma(1234567), "1,234,567")
	check("formatComma 950 → 950", UiKit.formatComma(950), "950")
	check("formatComma 100000 → 100,000", UiKit.formatComma(100000), "100,000")
end

print("\n━━ SellWindow: ร้านขายแม่ (UI-2) ━━")
do
	local SellWindow = loaded.SellWindow
	local shopPayload = makePayload()
	SellWindow.create(gui, { sellMothers = record("sellMothers"), notify = record("notify") })
	check("setPayload ตอนหน้าต่างปิดไม่ error", pcall(SellWindow.setPayload, shopPayload))
	check("เปิดหน้าต่างไม่ error", pcall(SellWindow.open))
	check("isOpen", SellWindow.isOpen())

	local sellWindow = findDescendant(gui, "SellWindow")
	local sellGrid = findDescendant(sellWindow, "Grid")
	local sellButton = findDescendant(sellWindow, "Sell")
	local selectAll = findDescendant(sellWindow, "SelectAll")
	local confirm = findDescendant(sellWindow, "Confirm")
	local function cards()
		local list = {}
		for _, child in sellGrid:GetChildren() do
			if child.Name == "Card" and child.Visible then
				table.insert(list, child)
			end
		end
		return list
	end
	-- ⚠️ UI-2: ขายเป็นชุด — คืนรายการ "ชุด" ที่ยิง (แต่ละชุด = array ของ uid)
	local function sellCalls(fromIndex)
		local batches = {}
		for index = fromIndex + 1, #calls do
			if calls[index].name == "sellMothers" then
				table.insert(batches, calls[index].args[1])
			end
		end
		return batches
	end

	-- ขายได้เฉพาะแม่ในกระเป๋า — แม่ในคอก (ซุนหงอคง/ม้า) ไม่ขึ้นเลย
	local penShown = false
	for _, card in cards() do
		if string.find(findDescendant(card, "NameLabel").Text, "ซุนหงอคง", 1, true) then
			penShown = true
		end
	end
	check("แม่ในคอกไม่ขึ้นในร้าน", penShown, false)
	check("ไม่สร้างการ์ดครบ 23 ใบพร้อมกัน (virtual grid)", #sellGrid:GetChildren() < 23)
	-- เรียง: ที่ไม่ล็อกก่อน · ถูกก่อน → ใบแรก = 1-102 (ราคา 60)
	local list = cards()
	check("การ์ดแรก = ถูกสุดที่ไม่ล็อก · ราคาใต้การ์ด ฿60", findDescendant(list[1], "PriceLabel").Text, "฿60")
	check("ยังไม่เลือก → ปุ่มขายถูกปิด", sellButton.AutoButtonColor, false)

	-- ติ๊ก 3 ใบแล้วเอาใบกลางออก → เหลือ 1-102 (60) + 1-104 (120)
	list[1].Activated:Fire()
	list[2].Activated:Fire()
	list[3].Activated:Fire()
	check("ติ๊ก 3 ใบ → เครื่องหมาย ✓ บนการ์ด", findDescendant(cards()[2], "CheckBadge").Visible, true)
	cards()[2].Activated:Fire()
	check("กดซ้ำ = เอาออก", findDescendant(cards()[2], "CheckBadge").Visible, false)
	local count, total, uids = SellWindow.getSelection()
	check("เลือก 2 ตัว", count, 2)
	check("ยอดรวม = 60 + 120", total, 180)
	check("ปุ่มขายบอกจำนวน + ยอดรวม", sellButton.Text, "ขายที่เลือก (2 ตัว · รวม ฿180)")

	-- แม่ที่ล็อก (1-101) อยู่ท้ายลิสต์ → เลื่อนลงไปหา
	sellGrid.CanvasPosition = Vector2.new(0, 10000)
	local lockedCard = nil
	for _, card in cards() do
		if findDescendant(card, "LockBadge").Visible then
			lockedCard = card
		end
	end
	check("แม่ที่ล็อกมี 🔒 + ทาเทา", lockedCard ~= nil and findDescendant(lockedCard, "LockShade").Visible == true, true)
	local before = #calls
	lockedCard.Activated:Fire()
	check("  กดแม่ที่ล็อก → แจ้งเตือน ไม่ถูกติ๊ก", lastCall().name == "notify" and #calls == before + 1, true)
	check("  จำนวนที่เลือกยังเท่าเดิม", (SellWindow.getSelection()), 2)
	sellGrid.CanvasPosition = Vector2.zero

	-- ขาย → กล่องยืนยัน → ยกเลิก = ไม่ยิงอะไร
	before = #calls
	sellButton.Activated:Fire()
	check("กดขาย → กล่องยืนยันขึ้น", confirm.Visible, true)
	local confirmText = findDescendant(confirm, "Text").Text
	check("  กล่องบอกจำนวน + ยอดรวม", string.find(confirmText, "ขายแม่ 2 ตัว", 1, true) ~= nil
		and string.find(confirmText, "฿180", 1, true) ~= nil, true)
	findDescendant(confirm, "ConfirmCancel").Activated:Fire()
	check("  ยกเลิก → กล่องปิด ไม่ยิง remote", confirm.Visible == false and #sellCalls(before) == 0, true)
	check("  ยกเลิกแล้วที่ติ๊กไว้ยังอยู่", (SellWindow.getSelection()), 2)

	-- ยืนยัน → ยิง remote ขายเป็นชุดครั้งเดียว ด้วย uid ที่เลือกเท่านั้น
	sellButton.Activated:Fire()
	findDescendant(confirm, "ConfirmSell").Activated:Fire()
	local batches = sellCalls(before)
	check("ยืนยัน → ยิงขายเป็นชุดครั้งเดียว", #batches, 1)
	local sold = batches[1] or {}
	check("  ชุดมี 2 uid", #sold, 2)
	check("  uid ตรงกับที่เลือกเท่านั้น", sold[1] == "1-102" and sold[2] == "1-104", true)
	check("  ขายแล้วล้างที่เลือก", (SellWindow.getSelection()), 0)

	-- เลือกทั้งหมดที่ไม่ได้ล็อก → 22 ตัว · ตัวที่ล็อกไม่ติด
	selectAll.Activated:Fire()
	count, total, uids = SellWindow.getSelection()
	local hasLocked = false
	for _, uid in uids do
		if uid == "1-101" then
			hasLocked = true
		end
	end
	check("เลือกทั้งหมดที่ไม่ได้ล็อก → 22 ตัว", count, 22)
	check("  ไม่มีตัวที่ล็อก", hasLocked, false)
	check("  ยอดรวม = 30 × (2 + … + 23)", total, 8250)
	check("  ปุ่มขายโชว์ยอดรวมเต็มหลัก", sellButton.Text, "ขายที่เลือก (22 ตัว · รวม ฿8,250)")
	check("  ปุ่มกลายเป็นยกเลิกทั้งหมด", selectAll.Text, "ยกเลิกที่เลือกทั้งหมด")

	-- ⚠️ UI-fix รอบ 1: มาตรฐานสีทั้งเกม — ปุ่มขาย = โทนแดง (R เด่นกว่า G และ B)
	-- เช็คเชิงโครงสร้าง (โทนสี ไม่ปักค่า RGB ตรง ๆ) กันเทสต์เปราะถ้าปรับเฉดทีหลัง
	local sellColor = sellButton.BackgroundColor3
	check("ปุ่มขาย = โทนแดง (R > G และ R > B)", sellColor.R > sellColor.G and sellColor.R > sellColor.B, true)
	local confirmSellColor = findDescendant(confirm, "ConfirmSell").BackgroundColor3
	check("ปุ่มยืนยันขาย = โทนแดงเช่นกัน", confirmSellColor.R > confirmSellColor.G and confirmSellColor.R > confirmSellColor.B, true)

	-- sync ใหม่: ตัวที่เลือกถูกขาย/ล็อกจากที่อื่น → หลุดจากที่เลือกเอง
	table.remove(shopPayload.mothersInBag, 2) -- 1-102
	shopPayload.mothersInBag[2].locked = true -- 1-103
	SellWindow.setPayload(shopPayload)
	count = SellWindow.getSelection()
	check("sync: ตัวที่หายไป/ถูกล็อกหลุดจากที่เลือก", count, 20)
	selectAll.Activated:Fire()
	check("กดอีกครั้ง → ยกเลิกทั้งหมด", (SellWindow.getSelection()), 0)

	-- เลือกไว้แล้วปิดหน้าต่าง → เปิดใหม่เริ่มจากว่าง
	cards()[1].Activated:Fire()
	SellWindow.close()
	check("ปิดหน้าต่าง", SellWindow.isOpen(), false)
	SellWindow.open()
	check("เปิดใหม่ → ไม่มีที่ค้างเลือก", (SellWindow.getSelection()), 0)
	SellWindow.close()

	-- กระเป๋าว่าง → ข้อความแนะนำ · ปุ่มถูกปิด
	shopPayload.mothersInBag = {}
	SellWindow.setPayload(shopPayload)
	SellWindow.open()
	check("กระเป๋าว่าง → ข้อความแนะนำ", findDescendant(sellWindow, "Empty").Visible, true)
	check("  ปุ่มเลือกทั้งหมดถูกปิด", selectAll.AutoButtonColor, false)
	SellWindow.close()
end

print("\n━━ MapSigns: ข้อความบนป้าย (ค่าของผู้เล่นที่มองอยู่) ━━")
do
	local MapSigns = loaded.MapSigns
	local p = makePayload()
	local view = MapSigns.describe("damage", p)
	check("ดาเมจ: Lv. 7", view.level, "Lv. 7")
	check("  ราคาขั้นถัดไป ฿5K · เงินพอ = สีปกติ", view.detail == "฿5K" and view.tone == "price", true)
	view = MapSigns.describe("speed", p)
	check("ความเร็ว: เงินไม่พอ → ราคาสีแดง", view.detail == "฿100K" and view.tone == "poor", true)
	view = MapSigns.describe("pen", p)
	check("อัปคอก: Lv. 3 · ฿10K", view.level == "Lv. 3" and view.detail == "฿10K", true)
	p.damageUpgradeCost = nil
	p.damageLevel = 16
	view = MapSigns.describe("damage", p)
	check("ดาเมจชนเพดานด่าน → เต็มแล้ว — พังด่านถัดไป", view.detail, "เต็มแล้ว — พังด่านถัดไปเพื่อปลดล็อก")
	p.damageLevel = Config.Balance.DamageUpgrade.MAX_LEVEL
	check("ดาเมจครบทั้งเกม → MAX", MapSigns.describe("damage", p).detail, "MAX")
	p.speedUpgradeCost = nil
	check("ความเร็วสุดทาง → MAX", MapSigns.describe("speed", p).detail, "MAX")
	p.penUpgradeCost = nil
	check("คอกสุดทาง → MAX", MapSigns.describe("pen", p).detail, "MAX")
	check("ยังไม่มี sync → กำลังโหลด", MapSigns.describe("speed", nil).detail, "กำลังโหลด...")
end

print("\n━━ MapSigns: ติดป้าย + จุดกด E เฉพาะคอกตัวเอง ━━")
do
	local MapSigns = loaded.MapSigns
	-- แมพจำลองตามชื่อที่ MapBuilder ตั้ง (Config.getMapSignName)
	local map = newInstance("Folder")
	map.Name = "Map"
	map.Parent = workspaceMock
	local signFolder = newInstance("Folder")
	signFolder.Name = Config.MAP_SIGN_FOLDER
	signFolder.Parent = map
	local boards = {}
	local posts = {}
	local function addSign(name)
		local model = newInstance("Model")
		model.Name = name
		model.Parent = signFolder
		local post = newInstance("Part")
		post.Name = "Post"
		post.Parent = model
		posts[name] = post
		local board = newInstance("Part")
		board.Name = "Board"
		board.Parent = model
		boards[name] = board
	end
	addSign(Config.getMapSignName("damage"))
	for index = 1, Config.World.MAX_PENS do
		addSign(Config.getMapSignName("speed", index))
		addSign(Config.getMapSignName("pen", index))
	end
	local shopFolder = newInstance("Folder")
	shopFolder.Name = "Shop"
	shopFolder.Parent = map
	local stall = newInstance("Model")
	stall.Name = `Stall{Config.MapDimensions.MapSign.SellStallIndex}`
	stall.Parent = shopFolder
	local counter = newInstance("Part")
	counter.Name = "Counter"
	counter.Parent = stall
	-- 5C: แผงร้านกระบอง (ป้าย "ซื้ออาวุธ" · MapSign.WeaponStallIndex)
	local weaponStall = newInstance("Model")
	weaponStall.Name = `Stall{Config.MapDimensions.MapSign.WeaponStallIndex}`
	weaponStall.Parent = shopFolder
	local weaponCounter = newInstance("Part")
	weaponCounter.Name = "Counter"
	weaponCounter.Parent = weaponStall
	-- UI-3: แท่นอัญเชิญ (MapBuilder.buildSummonPedestal · Config.SUMMON_PEDESTAL_NAME)
	local pedestal = newInstance("Model")
	pedestal.Name = Config.SUMMON_PEDESTAL_NAME
	pedestal.Parent = map
	local pedestalCore = newInstance("Part")
	pedestalCore.Name = Config.SUMMON_PEDESTAL_CORE
	pedestalCore.Parent = pedestal

	localPlayer:SetAttribute(Config.PEN_INDEX_ATTRIBUTE, 2)
	local playerGui = newInstance("PlayerGui")
	local shopOpen = false
	local summonOpen = false
	local weaponOpen = false
	local signActions = {
		openWeaponShop = function()
			weaponOpen = true
		end,
		closeWeaponShop = record("closeWeaponShop"),
		isWeaponShopOpen = function()
			return weaponOpen
		end,
		buy = record("buy"),
		openSellShop = function()
			shopOpen = true
		end,
		closeSellShop = record("closeSellShop"),
		isSellShopOpen = function()
			return shopOpen
		end,
		openSummon = function()
			summonOpen = true
		end,
		closeSummon = record("closeSummon"),
		isSummonOpen = function()
			return summonOpen
		end,
		stopSummon = record("stopSummon"),
	}
	-- ⚠️ task.spawn ของจริงรันทีหลัง — ในเทสต์รันทันที (WaitForChild ปลอม = หาเจอเลย)
	-- ลูปวัดระยะร้านหยุดที่ task.wait ครั้งแรก (โยน error ให้ pcall จับ) ไม่งั้นวนไม่จบ
	local realSpawn, realWait = __env.task.spawn, __env.task.wait
	__env.task.spawn = function(fn, ...)
		pcall(fn, ...)
	end
	__env.task.wait = function()
		error("หยุดลูปในเทสต์")
	end
	local ok, err = pcall(MapSigns.start, playerGui, signActions)
	__env.task.spawn, __env.task.wait = realSpawn, realWait
	check(`start ไม่ error {if ok then "" else tostring(err)}`, ok)

	local guis = 0
	for _, child in playerGui:GetChildren() do
		if child.__class == "SurfaceGui" then
			guis += 1
		end
	end
	check("SurfaceGui 1 + 2 × คอก = 13 อัน (อยู่ใน PlayerGui)", guis, 1 + 2 * Config.World.MAX_PENS)
	local ownGui = findDescendant(playerGui, `Sign_{Config.getMapSignName("speed", 2)}`)
	check("SurfaceGui ชี้ Adornee ไปที่แผ่นป้าย", ownGui.Adornee == boards[Config.getMapSignName("speed", 2)], true)

	local function promptOn(name)
		return findDescendant(boards[name], "UpgradePrompt")
	end
	check("ป้ายดาเมจมีจุดกด E", promptOn(Config.getMapSignName("damage")) ~= nil)
	check("ป้ายค่าวิ่งคอกตัวเอง (2) มีจุดกด", promptOn(Config.getMapSignName("speed", 2)) ~= nil)
	check("ป้ายอัปคอกคอกตัวเอง (2) มีจุดกด", promptOn(Config.getMapSignName("pen", 2)) ~= nil)
	check("ป้ายคอกคนอื่น (1) ไม่มีจุดกด", promptOn(Config.getMapSignName("speed", 1)) == nil
		and promptOn(Config.getMapSignName("pen", 1)) == nil, true)
	local prompt = promptOn(Config.getMapSignName("speed", 2))
	check("  กดครั้งเดียวซื้อ (ไม่ต้องกดค้าง)", prompt.HoldDuration, 0)
	check("  ข้อความปุ่ม \"อัปเกรด\"", prompt.ActionText, "อัปเกรด")
	check("  ขึ้นเฉพาะอันที่ใกล้สุด (OnePerButton)", prompt.Exclusivity, "Enum.ProximityPromptExclusivity.OnePerButton")
	prompt.Triggered:Fire(localPlayer)
	check("  กด E → buy(speed)", lastCall().name == "buy" and lastCall().args[1] == "speed", true)
	promptOn(Config.getMapSignName("damage")).Triggered:Fire(localPlayer)
	check("  ป้ายดาเมจ → buy(damage)", lastCall().args[1], "damage")
	promptOn(Config.getMapSignName("pen", 2)).Triggered:Fire(localPlayer)
	check("  ป้ายอัปคอก → buy(pen)", lastCall().args[1], "pen")

	local p = makePayload()
	MapSigns.setPayload(p)
	check("ป้ายตัวเองโชว์เลเวลของตัวเอง", findDescendant(ownGui, "Level").Text, "Lv. 2")
	-- ⚠️ UI-2 (ผลทดสอบ Studio): ป้ายคอกอื่นไม่แสดงเลย — ซ่อนทั้งเสา แผ่นป้าย และข้อความ ในเครื่องเรา
	local function signShown(kind, index)
		local name = Config.getMapSignName(kind, index)
		local gui = findDescendant(playerGui, `Sign_{name}`)
		local hidden = (boards[name].LocalTransparencyModifier or 0) == 1 and (posts[name].LocalTransparencyModifier or 0) == 1
		local visible = (boards[name].LocalTransparencyModifier or 0) == 0 and (posts[name].LocalTransparencyModifier or 0) == 0
		if gui.Enabled == false and hidden then
			return false
		elseif gui.Enabled ~= false and visible then
			return true
		end
		return "ครึ่ง ๆ" -- ซ่อนไม่ครบทุกชิ้น
	end
	check("ป้ายคอกตัวเอง (2) แสดงครบ", signShown("speed", 2) == true and signShown("pen", 2) == true, true)
	local othersHidden = true
	for index = 1, Config.World.MAX_PENS do
		if index ~= 2 and (signShown("speed", index) ~= false or signShown("pen", index) ~= false) then
			othersHidden = false
		end
	end
	check("ป้ายคอกอื่นทุกคอก (รวมที่ไม่มีเจ้าของ) ซ่อนหมด — เสา แผ่น ข้อความ", othersHidden, true)
	local damageGui = findDescendant(playerGui, `Sign_{Config.getMapSignName("damage")}`)
	check("ป้ายดาเมจแสดงเสมอ", damageGui.Enabled ~= false and (boards[Config.getMapSignName("damage")].LocalTransparencyModifier or 0) == 0, true)

	-- ย้ายคอก (จองใหม่) → จุดกดย้ายตาม
	localPlayer:SetAttribute(Config.PEN_INDEX_ATTRIBUTE, 5)
	check("ย้ายเป็นคอก 5 → ป้ายคอก 2 ไม่มีจุดกดแล้ว", promptOn(Config.getMapSignName("speed", 2)) == nil, true)
	check("  ป้ายคอก 5 มีจุดกด", promptOn(Config.getMapSignName("pen", 5)) ~= nil)
	check("  ป้ายคอก 2 ถูกซ่อน · คอก 5 แสดง", signShown("speed", 2) == false and signShown("speed", 5) == true, true)

	-- ออกจากคอก (Attribute ถูกล้าง) → ไม่เห็นป้ายค่าวิ่ง/อัปคอกของคอกไหนเลย · ป้ายดาเมจยังอยู่
	localPlayer:SetAttribute(Config.PEN_INDEX_ATTRIBUTE, nil)
	local anyShown = false
	for index = 1, Config.World.MAX_PENS do
		if signShown("speed", index) ~= false or signShown("pen", index) ~= false then
			anyShown = true
		end
	end
	check("ไม่มีคอก → ป้ายค่าวิ่ง/อัปคอกซ่อนหมด", anyShown, false)
	check("  ป้ายดาเมจยังแสดง · ยังมีจุดกด", damageGui.Enabled ~= false and promptOn(Config.getMapSignName("damage")) ~= nil, true)
	localPlayer:SetAttribute(Config.PEN_INDEX_ATTRIBUTE, 5)

	local sellPrompt = findDescendant(counter, "SellShopPrompt")
	check("แผงร้านขายแม่มีจุดกด E", sellPrompt ~= nil)
	check("  ขึ้นเฉพาะอันที่ใกล้สุด (OnePerButton)", sellPrompt.Exclusivity, "Enum.ProximityPromptExclusivity.OnePerButton")
	-- UiKit.prompt: props ส่ง Exclusivity อื่นมาก็ทับไม่ได้
	local forced = UiKit.prompt({ Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow, ActionText = "ทดสอบ" })
	check("UiKit.prompt: props ทับ Exclusivity ไม่ได้", forced.Exclusivity, "Enum.ProximityPromptExclusivity.OnePerButton")
	check("  props อื่นยังใช้ได้", forced.ActionText, "ทดสอบ")
	sellPrompt.Triggered:Fire(localPlayer)
	check("  กด E → เปิดร้าน", shopOpen, true)

	-- 5C: ร้านกระบอง — จุดกด E ที่เคาน์เตอร์แผง "ซื้ออาวุธ" (UiKit.prompt · OnePerButton)
	local weaponPrompt = findDescendant(weaponCounter, "WeaponShopPrompt")
	check("แผงร้านกระบอง (ซื้ออาวุธ) มีจุดกด E", weaponPrompt ~= nil)
	check("  ชื่อร้าน \"ร้านกระบอง\"", weaponPrompt.ObjectText, "ร้านกระบอง")
	check("  ขึ้นเฉพาะอันที่ใกล้สุด (OnePerButton)", weaponPrompt.Exclusivity, "Enum.ProximityPromptExclusivity.OnePerButton")
	check("  ไม่ติดซ้ำบนเคาน์เตอร์ร้านขายแม่", findDescendant(counter, "WeaponShopPrompt") == nil)
	check("  กดครั้งเดียวเปิด (ไม่ต้องกดค้าง)", weaponPrompt.HoldDuration or 0, 0)
	weaponPrompt.Triggered:Fire(localPlayer)
	check("  กด E → เปิดร้านกระบอง", weaponOpen, true)

	-- UI-3: แท่นอัญเชิญ — กด E ค้าง (ไม่ใช่กดครั้งเดียว) · ผ่าน UiKit.prompt (OnePerButton)
	local summonPrompt = findDescendant(pedestalCore, "SummonPrompt")
	check("แท่นอัญเชิญมีจุดกด E (ติดที่แกนเรืองแสง)", summonPrompt ~= nil)
	check("  กดค้าง 0.5 วินาที", summonPrompt.HoldDuration, Config.MapDimensions.SummonPedestal.PromptHoldSeconds)
	check("  ขึ้นเฉพาะอันที่ใกล้สุด (OnePerButton)", summonPrompt.Exclusivity, "Enum.ProximityPromptExclusivity.OnePerButton")
	check("  ระยะกดตาม Config", summonPrompt.MaxActivationDistance, Config.MapDimensions.SummonPedestal.PromptDistance)
	summonPrompt.Triggered:Fire(localPlayer)
	check("  กด E ค้าง → เปิดหน้าต่างอัญเชิญ", summonOpen, true)

	-- ⚠️ UI-fix รอบ 1: กำลังอัญเชิญอยู่แล้ว → กด E ค้างซ้ำ = หยุดทันที ไม่เปิดหน้าต่างซ้ำ
	local beforeStopCalls = #calls
	p.summonEnabled = true
	MapSigns.setPayload(p)
	check("  5B-fix: กำลังอัญเชิญ → ข้อความบนจุดกด = \"ปิดอัญเชิญ\"", summonPrompt.ActionText, "ปิดอัญเชิญ")
	summonPrompt.Triggered:Fire(localPlayer)
	check("  กำลังอัญเชิญอยู่ → กด E ค้างซ้ำ → เรียก stopSummon", lastCall().name, "stopSummon")
	check("  ไม่เรียก openSummon ซ้ำ", #calls, beforeStopCalls + 1)

	-- หยุดแล้ว (summonEnabled กลับเป็น false ตาม sync ถัดไป) → กด E ค้างเปิดหน้าต่างได้ตามปกติอีกครั้ง
	summonOpen = false
	p.summonEnabled = false
	MapSigns.setPayload(p)
	check("  5B-fix: หยุดแล้ว → ข้อความกลับเป็น \"อัญเชิญ\" เหมือนเดิม", summonPrompt.ActionText, "อัญเชิญ")
	summonPrompt.Triggered:Fire(localPlayer)
	check("  หยุดแล้ว → กด E ค้างเปิดหน้าต่างได้ตามปกติ", summonOpen, true)

	-- ⚠️ Phase 5A: ติดล็อกบอส (server ปิดอัญเชิญให้แล้ว) → กด E ค้างแค่เปิดหน้าต่าง (ที่ปุ่มส่งถูกปิด) ไม่เริ่มอัญเชิญเอง
	summonOpen = false
	p.summonEnabled = false
	p.summonBlockReason = Config.BOSS_LOCK_MESSAGE
	MapSigns.setPayload(p)
	local beforeLocked = #calls
	summonPrompt.Triggered:Fire(localPlayer)
	check("  ติดล็อกบอส → กด E ค้างแค่เปิดหน้าต่าง", summonOpen, true)
	check("  ไม่ยิงคำสั่งอัญเชิญ/หยุดใด ๆ", #calls, beforeLocked)
	p.summonBlockReason = nil
end

print("\n━━ SummonWindow: หน้าต่างแท่นอัญเชิญ (UI-3) ━━")
do
	local SummonWindow = loaded.SummonWindow
	local sp = makePayload()
	local function stack(charId, motherWeight, count, power)
		local character = Config.getCharacter(charId)
		return {
			key = Config.makeStackKey(charId, motherWeight, {}),
			charId = charId,
			charName = character.name,
			class = character.class,
			weight = motherWeight,
			weightText = Config.formatWeight(Config.getChildWeight(motherWeight)),
			statuses = {},
			count = count,
			power = power,
		}
	end
	local sA = stack("wukong", 50000, 120, 900)
	local sB = stack("monkey", 100, 40, 1)
	local sC = stack("pig", 800, 7, 30)
	local sW = stack("horse", 800, 0, 20) -- ติ๊กไว้แต่หมด · แม่ในคอกผลิตเติมอยู่
	sp.children = { sA, sB, sC }
	sp.waitingStacks = { sW }
	sp.releaseOrder = { sB.key, sW.key, sA.key }
	sp.summonEnabled = false
	sp.combatAutoPaused = false
	sp.activeStage = 3
	sp.sendStageBlockReason = nil
	-- แม่ในสนามแล้ว 7 ตัว → ที่ว่าง 3
	local roster = {}
	for index = 1, 7 do
		local m = mother(`9-{index}`, "tang", 1000, false, 1)
		m.statuses = {}
		table.insert(roster, m)
	end
	sp.battleRoster = roster

	local summonCalls = {}
	local function recordSummon(name)
		return function(...)
			table.insert(summonCalls, { name = name, args = table.pack(...) })
		end
	end
	SummonWindow.create(gui, {
		sendMothers = recordSummon("sendMothers"),
		setReleaseOrder = recordSummon("setReleaseOrder"),
		setSummonEnabled = recordSummon("setSummonEnabled"),
		notify = recordSummon("notify"),
	})
	check("setPayload ตอนหน้าต่างปิดไม่ error", pcall(SummonWindow.setPayload, sp))
	check("เปิดหน้าต่างไม่ error", pcall(SummonWindow.open))
	check("isOpen", SummonWindow.isOpen())

	local win = findDescendant(gui, "SummonWindow")
	local grid2 = findDescendant(win, "Grid")
	local sendButton = findDescendant(win, "Send")
	local stopButton = findDescendant(win, "Stop")
	local confirm = findDescendant(win, "Confirm")
	local notice = findDescendant(win, "Notice")
	local function cards()
		local list = {}
		for _, child in grid2:GetChildren() do
			if child.Name == "Card" and child.Visible then
				table.insert(list, child)
			end
		end
		return list
	end
	local function cardFor(text)
		for _, card in cards() do
			if string.find(findDescendant(card, "NameLabel").Text, text, 1, true) then
				return card
			end
		end
		return nil
	end
	local function badge(card)
		local b = findDescendant(card, "OrderBadge")
		return if b.Visible then b.Text else ""
	end
	local function joined(list)
		return table.concat(list, ",")
	end
	local function callNames(fromIndex)
		local names = {}
		for index = fromIndex + 1, #summonCalls do
			table.insert(names, summonCalls[index].name)
		end
		return table.concat(names, ",")
	end

	-- ── แท็บลูก (เปิดครั้งแรก = แท็บลูก) ──
	check("แท็บลูก: ทุกกอง + กองรอผลิต = 4 ใบ", #cards(), 4)
	check("เปิดมา = ติ๊กตาม releaseOrder ล่าสุด", joined(SummonWindow.getTicks("children")), joined({ sB.key, sW.key, sA.key }))
	check("  เลขบนการ์ด: ลิง = 1", badge(cardFor(sB.charName)), "1")
	check("  กองรอผลิต = 2 · มีคำว่ารอผลิต", badge(cardFor(sW.charName)) == "2"
		and string.find(findDescendant(cardFor(sW.charName), "InfoLabel").Text, "รอผลิต", 1, true) ~= nil, true)
	check("  ซุนหงอคง = 3", badge(cardFor(sA.charName)), "3")
	check("  กองที่ไม่ได้ติ๊ก (หมู) ไม่มีเลข", badge(cardFor(sC.charName)), "")
	check("  การ์ดโชว์จำนวน + พลังต่อตัว", string.find(findDescendant(cardFor(sA.charName), "InfoLabel").Text, "×120", 1, true) ~= nil
		and string.find(findDescendant(cardFor(sA.charName), "InfoLabel").Text, "⚔️900", 1, true) ~= nil, true)
	check("  ข้อความบอกว่ากองที่ไม่ติ๊กไม่ถูกปล่อย", string.find(notice.Text, "ไม่ถูกปล่อย", 1, true) ~= nil)
	check("หยุดอยู่ → ไม่มีปุ่มหยุดอัญเชิญ", stopButton.Visible, false)

	-- เอากองลำดับ 1 ออก → ตัวหลังเลื่อนขึ้น · ติ๊กหมูเพิ่ม → ต่อท้าย
	cardFor(sB.charName).Activated:Fire()
	check("เอาลิง (1) ออก → กองรอผลิตเลื่อนเป็น 1", badge(cardFor(sW.charName)), "1")
	check("  ซุนหงอคงเลื่อนเป็น 2", badge(cardFor(sA.charName)), "2")
	cardFor(sC.charName).Activated:Fire()
	check("ติ๊กหมูเพิ่ม → ได้เลข 3", badge(cardFor(sC.charName)), "3")
	check("  ลำดับ = รอผลิต, ซุนหงอคง, หมู", joined(SummonWindow.getTicks("children")), joined({ sW.key, sA.key, sC.key }))

	-- ติ๊กแค่ลูก → ส่งไปรบ = ไม่มีกล่องยืนยัน · ตั้งลำดับ แล้วเปิดอัญเชิญ
	local before = #summonCalls
	sendButton.Activated:Fire()
	check("ติ๊กแค่ลูก → ไม่มีกล่องยืนยัน", confirm.Visible, false)
	check("  ยิง ตั้งลำดับ → เปิดอัญเชิญ (ไม่ส่งแม่)", callNames(before), "setReleaseOrder,setSummonEnabled")
	check("  ลำดับที่ส่ง = ที่ติ๊ก", joined(summonCalls[before + 1].args[1]), joined({ sW.key, sA.key, sC.key }))
	check("  เปิดอัญเชิญ = true", summonCalls[before + 2].args[1], true)

	-- ── แท็บแม่ ──
	findDescendant(win, "Tab_mothers").Activated:Fire()
	local motherCards = cards()
	check("แท็บแม่: แม่ในสนามอยู่บนสุด ติดป้ายในสนาม", findDescendant(motherCards[1], "FieldTag").Visible, true)
	local penShown = cardFor("ซุนหงอคง") ~= nil
	check("  แม่ในคอกไม่แสดง", penShown, false)
	before = #summonCalls
	motherCards[1].Activated:Fire()
	check("  กดแม่ในสนาม → แจ้งเตือน ไม่ติ๊ก", callNames(before) == "notify" and #SummonWindow.getTicks("mothers") == 0, true)

	-- แม่ในกระเป๋า: หลังแม่ในสนาม 7 ตัว · เรียงคลาสสูง/หนักก่อน · ตัวที่ล็อก (1-101) ติ๊กไม่ได้
	grid2.CanvasPosition = Vector2.new(0, 10000)
	local lockedCard = nil
	for _, card in cards() do
		if findDescendant(card, "LockBadge").Visible then
			lockedCard = card
		end
	end
	check("แม่ที่ล็อกมี 🔒 + ทาเทา", lockedCard ~= nil and findDescendant(lockedCard, "Shade").Visible == true, true)
	before = #summonCalls
	lockedCard.Activated:Fire()
	check("  กดแม่ที่ล็อก → แจ้งเตือน ไม่ติ๊ก", callNames(before) == "notify" and #SummonWindow.getTicks("mothers") == 0, true)
	grid2.CanvasPosition = Vector2.zero

	-- ที่ว่าง 3 ตัว (ในสนาม 7/10): ติ๊ก 4 ตัว → ตัวที่ 4 ไม่ติด
	local bagCards = {}
	for _, card in cards() do
		if not findDescendant(card, "FieldTag").Visible and not findDescendant(card, "LockBadge").Visible then
			table.insert(bagCards, card)
		end
	end
	check("มีแม่ในกระเป๋าให้ติ๊กอย่างน้อย 4 ใบบนจอ", #bagCards >= 4)
	bagCards[1].Activated:Fire()
	bagCards[2].Activated:Fire()
	bagCards[3].Activated:Fire()
	before = #summonCalls
	bagCards[4].Activated:Fire()
	check("ติ๊กเกินที่ว่างใน roster (3) → ไม่ติด + แจ้งเตือน", #SummonWindow.getTicks("mothers") == 3 and callNames(before) == "notify", true)
	check("  เลขบนการ์ด 1 · 2 · 3", badge(bagCards[1]) .. badge(bagCards[2]) .. badge(bagCards[3]), "123")
	local firstThree = SummonWindow.getTicks("mothers")
	bagCards[1].Activated:Fire()
	check("เอาตัวที่ 1 ออก → ที่เหลือเลื่อนเป็น 1 · 2", badge(bagCards[2]) .. badge(bagCards[3]), "12")
	bagCards[4].Activated:Fire()
	check("  ตอนนี้ติ๊กตัวที่ 4 ได้แล้ว (เลข 3)", badge(bagCards[4]), "3")
	local motherTicks = SummonWindow.getTicks("mothers")
	check("  ลำดับแม่ = 2, 3, 4", joined(motherTicks), joined({ firstThree[2], firstThree[3], motherTicks[3] }))
	check("  ลำดับแยกจากแท็บลูก (ลูกยังเหมือนเดิม)", joined(SummonWindow.getTicks("children")), joined({ sW.key, sA.key, sC.key }))

	-- ส่งไปรบ (มีแม่) → กล่องยืนยัน → ยกเลิก = ไม่ยิงอะไร
	before = #summonCalls
	sendButton.Activated:Fire()
	check("มีแม่ → กล่องยืนยันขึ้น", confirm.Visible, true)
	local confirmTextNow = findDescendant(confirm, "Text").Text
	check("  บอกจำนวน + ตายถาวร + ดึงกลับไม่ได้", string.find(confirmTextNow, "ส่งแม่ 3 ตัว", 1, true) ~= nil
		and string.find(confirmTextNow, "ตายถาวร", 1, true) ~= nil
		and string.find(confirmTextNow, "ดึงกลับไม่ได้", 1, true) ~= nil, true)
	findDescendant(confirm, "ConfirmCancel").Activated:Fire()
	check("  ยกเลิก → กล่องปิด ไม่ยิงอะไรเลย", confirm.Visible == false and #summonCalls == before, true)
	check("  ยกเลิกแล้วที่ติ๊กไว้ยังอยู่", #SummonWindow.getTicks("mothers"), 3)

	-- ยืนยัน → ส่งแม่ → ตั้งลำดับ → เปิดอัญเชิญ (ตามลำดับนี้เท่านั้น)
	sendButton.Activated:Fire()
	findDescendant(confirm, "ConfirmSend").Activated:Fire()
	check("ยืนยัน → ยิง ส่งแม่ → ตั้งลำดับ → เปิดอัญเชิญ", callNames(before), "sendMothers,setReleaseOrder,setSummonEnabled")
	check("  แม่ที่ส่ง = ที่ติ๊กตามลำดับ", joined(summonCalls[before + 1].args[1]), joined(motherTicks))
	check("  ลำดับลูกที่ส่ง = ที่ติ๊กไว้ในแท็บลูก", joined(summonCalls[before + 2].args[1]), joined({ sW.key, sA.key, sC.key }))
	check("  ส่งแล้วล้างที่ติ๊กแม่", #SummonWindow.getTicks("mothers"), 0)
	check("ไม่ได้ติ๊กอะไรในแท็บแม่ แต่ลูกยังติ๊กอยู่ → ปุ่มส่งยังกดได้", sendButton.AutoButtonColor, true)

	-- กำลังอัญเชิญ → ปุ่มหยุดโผล่ · กดแล้วปิดอัญเชิญ
	sp.summonEnabled = true
	SummonWindow.setPayload(sp)
	check("กำลังอัญเชิญ → ปุ่มหยุดอัญเชิญโผล่", stopButton.Visible, true)
	before = #summonCalls
	stopButton.Activated:Fire()
	check("  กดหยุด → setSummonEnabled(false)", callNames(before) == "setSummonEnabled" and summonCalls[before + 1].args[1] == false, true)

	-- auto-pause → เตือนในหัวหน้าต่าง
	sp.combatAutoPaused = true
	SummonWindow.setPayload(sp)
	check("auto-pause → เตือนตีไม่เข้า", string.find(notice.Text, "ตีไม่เข้า", 1, true) ~= nil)
	sp.combatAutoPaused = false

	-- ไม่มีด่านให้ส่ง → บอกเหตุผล · ติ๊กแม่ไม่ได้
	sp.sendStageBlockReason = "ผ่านครบทุกด่านแล้ว ไม่มีด่านให้ส่งแม่ไปรบ"
	SummonWindow.setPayload(sp)
	check("ไม่มีด่าน → โชว์เหตุผลในหัวแท็บแม่", string.find(notice.Text, "ผ่านครบทุกด่านแล้ว", 1, true) ~= nil)
	bagCards = {}
	for _, card in cards() do
		if not findDescendant(card, "FieldTag").Visible and not findDescendant(card, "LockBadge").Visible then
			table.insert(bagCards, card)
		end
	end
	check("  การ์ดแม่ในกระเป๋าทาเทา", findDescendant(bagCards[1], "Shade").Visible, true)
	before = #summonCalls
	bagCards[1].Activated:Fire()
	check("  กดแล้วแจ้งเหตุผล ไม่ติ๊ก", callNames(before) == "notify" and #SummonWindow.getTicks("mothers") == 0, true)
	sp.sendStageBlockReason = nil

	-- ⚠️ Phase 5A: ล็อกอัญเชิญเพราะบอส — ปุ่มส่งไปรบกดไม่ได้ + ข้อความ · รวมกับ auto-pause (ไม่แทนที่)
	-- server ใส่ข้อความล็อกทั้ง summonBlockReason และ sendStageBlockReason (ส่งแม่ไม่ได้ด้วย)
	sp.summonEnabled = false
	sp.summonBlockReason = Config.BOSS_LOCK_MESSAGE
	sp.sendStageBlockReason = Config.BOSS_LOCK_MESSAGE
	sp.combatAutoPaused = true
	SummonWindow.setPayload(sp)
	findDescendant(win, "Tab_children").Activated:Fire()
	check("ล็อกบอส → ปุ่มส่งไปรบถูกปิด", sendButton.AutoButtonColor, false)
	check("  ปุ่มบอกว่าติดล็อก", string.find(sendButton.Text, "กำจัดบอสก่อน", 1, true) ~= nil)
	check("  ข้อความล็อกในหัวหน้าต่าง", string.find(notice.Text, Config.BOSS_LOCK_MESSAGE, 1, true) ~= nil)
	check("  รวมกับคำเตือน auto-pause (ไม่แทนที่กัน)", string.find(notice.Text, "ตีไม่เข้า", 1, true) ~= nil)
	before = #summonCalls
	sendButton.Activated:Fire()
	check("  กดส่งแล้วไม่ยิงอะไรเลย (ไม่เปิดอัญเชิญ)", #summonCalls, before)
	findDescendant(win, "Tab_mothers").Activated:Fire()
	local _, lockCount = string.gsub(notice.Text, Config.BOSS_LOCK_MESSAGE, "")
	check("  แท็บแม่: ข้อความล็อกขึ้นครั้งเดียว (ไม่ซ้ำกับเหตุผลส่งแม่)", lockCount, 1)
	-- บอสตาย → server ล้างเหตุผล → ปุ่มกลับเป็นปกติ
	sp.summonBlockReason = nil
	sp.sendStageBlockReason = nil
	sp.combatAutoPaused = false
	SummonWindow.setPayload(sp)
	findDescendant(win, "Tab_children").Activated:Fire()
	check("ปลดล็อก → ปุ่มไม่ติดล็อกแล้ว", string.find(sendButton.Text, "กำจัดบอสก่อน", 1, true) == nil)
	check("  ข้อความล็อกหายไป", string.find(notice.Text, Config.BOSS_LOCK_MESSAGE, 1, true) == nil)

	-- ลำดับปล่อยว่าง (ไม่เคยติ๊ก) → เปิดมาติ๊กทุกกองไว้ก่อน เรียงพลังต่อตัวมาก → น้อย
	SummonWindow.close()
	sp.releaseOrder = {}
	sp.waitingStacks = {} -- server ส่งกองรอผลิตเฉพาะที่อยู่ในลำดับ — ลำดับว่างจึงไม่มี
	SummonWindow.setPayload(sp)
	SummonWindow.open()
	findDescendant(win, "Tab_children").Activated:Fire()
	check("ลำดับว่าง → ติ๊กทุกกองที่มีของ เรียงพลังมาก→น้อย (ซุนหงอคง 900 · หมู 30 · ลิง 1)",
		joined(SummonWindow.getTicks("children")), joined({ sA.key, sC.key, sB.key }))
	check("  ม้า (กองที่ไม่มีของ) ไม่อยู่ในค่าเริ่มต้น", table.find(SummonWindow.getTicks("children"), sW.key) == nil, true)
	check("  เลขบนการ์ด 1 · 2 · 3", badge(cardFor(sA.charName)) .. badge(cardFor(sC.charName)) .. badge(cardFor(sB.charName)), "123")
	before = #summonCalls
	check("  ยังไม่ยิงอะไรจนกว่าจะกดส่ง", #summonCalls, before)
	cardFor(sC.charName).Activated:Fire()
	check("  เอาติ๊กออกเองได้ (หมูออก → ลิงเลื่อนเป็น 2)", badge(cardFor(sB.charName)), "2")
	sendButton.Activated:Fire()
	check("  กดส่ง = ส่งลำดับที่เหลือ", joined(summonCalls[before + 1].args[1]), joined({ sA.key, sB.key }))

	-- ไม่มีอะไรให้ติ๊กเลย (ลำดับว่าง + ไม่มีกอง) → ปุ่มส่งถูกปิด กดแล้วไม่ยิง
	SummonWindow.close()
	local savedChildren = sp.children
	sp.children = {}
	sp.waitingStacks = {}
	SummonWindow.setPayload(sp)
	SummonWindow.open()
	check("ไม่ติ๊กอะไร → ปุ่มส่งไปรบถูกปิด", sendButton.AutoButtonColor, false)
	before = #summonCalls
	sendButton.Activated:Fire()
	check("  กดแล้วไม่ยิงอะไร", #summonCalls, before)
	sp.children = savedChildren
	sp.waitingStacks = { sW }

	-- ปิดแล้วเปิดใหม่: ติ๊กแม่ไม่ค้าง · ติ๊กลูกกลับมาตาม releaseOrder
	sp.releaseOrder = { sC.key, sA.key }
	SummonWindow.setPayload(sp)
	findDescendant(win, "Tab_mothers").Activated:Fire()
	for _, card in cards() do
		if not findDescendant(card, "FieldTag").Visible and not findDescendant(card, "LockBadge").Visible then
			card.Activated:Fire()
			break
		end
	end
	check("ติ๊กแม่ไว้ 1 ตัว", #SummonWindow.getTicks("mothers"), 1)
	SummonWindow.close()
	SummonWindow.open()
	check("เปิดใหม่ → ไม่มีแม่ค้างติ๊ก", #SummonWindow.getTicks("mothers"), 0)
	check("  ลูกติ๊กตาม releaseOrder ล่าสุด", joined(SummonWindow.getTicks("children")), joined({ sC.key, sA.key }))

	-- กองในลำดับที่ไม่ได้แสดง (หมด + ไม่มีแม่ผลิตเติม) → ไม่ติ๊ก
	SummonWindow.close()
	sp.releaseOrder = { "ghost|123|", sA.key }
	SummonWindow.setPayload(sp)
	SummonWindow.open()
	check("กองที่หายไปแล้วหลุดจากติ๊ก", joined(SummonWindow.getTicks("children")), sA.key)
	SummonWindow.close()
	check("ปิดหน้าต่าง", SummonWindow.isOpen(), false)
end

print("\n━━ IndexWindow: ดัชนี (UI-4) ━━")
do
	local IndexWindow = loaded.IndexWindow
	local ip = makePayload()
	-- ในคอก: ซุนหงอคง + ม้า · กระเป๋า: ลิง/หมู 23 ตัว · roster: ลิง 1 ตัว
	ip.battleRoster = { mother("9-1", "monkey", 100, false, 1) }
	ip.discovered = { "horse", "monkey", "pig", "wukong", "ghost_char" } -- ghost_char = ตัวละครที่ถูกลบจาก Config
	IndexWindow.create(gui)
	local fakeIndexButton = Instance.new("TextButton")
	local badge = IndexWindow.attachBadge(fakeIndexButton)
	check("setPayload ตอนหน้าต่างปิดไม่ error", pcall(IndexWindow.setPayload, ip))
	check("sync ชุดแรกหลังเข้าเกม → ไม่มีจุดแดง", badge.Visible, false)
	check("เปิดหน้าต่างไม่ error", pcall(IndexWindow.open))

	local win = findDescendant(gui, "IndexWindow")
	local grid = findDescendant(win, "Grid")
	local function cards()
		local list = {}
		for _, child in grid:GetChildren() do
			if child.Name == "Card" and child.Visible then
				table.insert(list, child)
			end
		end
		return list
	end
	local function portraitOf(card)
		return findDescendant(findDescendant(card, "PortraitHolder"), "Portrait")
	end

	check("หัว: เก็บแล้ว 4/12 (charId แปลกไม่นับ)", findDescendant(win, "Total").Text, "เก็บแล้ว 4/12")
	local tabOrder = {}
	for _, classId in Config.getIndexClasses() do
		local tab = findDescendant(win, `Tab_{classId}`)
		table.insert(tabOrder, if tab then findDescendant(tab, "Caption").Text else `ไม่มีแท็บ {classId}`)
	end
	check("แท็บคลาสครบ 5 แท็บ ธรรมดา → หายาก พร้อมตัวเลข (คลาสที่ยังไม่ได้ก็มีแท็บ)",
		table.concat(tabOrder, " | "), "C 3/4 | B 0/3 | A 1/2 | S 0/2 | SS 0/1")

	-- แท็บแรก = C: ลิง หมู ม้า (เคยได้) · ปลา (ยังไม่ได้)
	local list = cards()
	check("แท็บ C มี 4 ช่อง (1 ช่อง = 1 ตัวละคร)", #list, 4)
	check("  เรียงตาม Config: ลิง หมู ม้า ???", `{findDescendant(list[1], "NameLabel").Text} {findDescendant(list[2], "NameLabel").Text} {findDescendant(list[3], "NameLabel").Text} {findDescendant(list[4], "NameLabel").Text}`, "ลิง หมู ม้า ???")
	check("  เคยได้ = รูปสีตามคลาส", portraitOf(list[1]).BackgroundColor3, UiKit.CLASS_COLORS.C)
	check("  เคยได้ = บอกคลาส", findDescendant(list[1], "ClassLabel").Text, "คลาส C")
	check("  ยังไม่ได้ = เงาดำ", portraitOf(list[4]).BackgroundColor3, UiKit.SILHOUETTE)
	check("  ยังไม่ได้ = ไม่บอกคลาสในรูป (?)", findDescendant(portraitOf(list[4]), "TextLabel").Text, "?")
	check("  ยังไม่ได้ = ไม่บอกคลาสใต้ชื่อ", findDescendant(list[4], "ClassLabel").Text, "")
	check("  ขอบการ์ดสีตามคลาส (ทั้งเคยได้และเงา)", findDescendant(list[4], "ClassBorder").Color, UiKit.CLASS_COLORS.C)

	-- กดการ์ดที่เคยได้ → แผงเล็ก
	local detail = findDescendant(win, "Detail")
	list[1].Activated:Fire()
	check("กดการ์ดลิง → แผงรายละเอียดขึ้น", detail.Visible, true)
	check("  ชื่อ", findDescendant(detail, "Title").Text, "ลิง")
	local info = findDescendant(detail, "Info").Text
	local monkeysNow = 1 -- roster
	for _, m in ip.mothersInBag do
		if m.charId == "monkey" then
			monkeysNow += 1
		end
	end
	check("  คลาส + ตัวคูณ + ตอนนี้มี N ตัว (คอก+กระเป๋า+roster)", info, `คลาส C · ×1\nตอนนี้มี {monkeysNow} ตัว`)
	list[4].Activated:Fire()
	check("กดการ์ดเงา → ยังไม่เคยได้", findDescendant(detail, "Info").Text, "ยังไม่เคยได้")
	check("  ชื่อเป็น ???", findDescendant(detail, "Title").Text, "???")
	list[4].Activated:Fire()
	check("กดซ้ำ → ปิดแผง", detail.Visible, false)

	-- แท็บ A: ซุนหงอคงเคยได้ · ขาย/ตายหมดแล้วก็ยังนับ (ตอนนี้มี 0 ตัว)
	findDescendant(win, "Tab_A").Activated:Fire()
	list = cards()
	check("แท็บ A มี 2 ช่อง", #list, 2)
	check("  พระถัง = ???", findDescendant(list[1], "NameLabel").Text, "???")
	check("  ซุนหงอคง เคยได้", findDescendant(list[2], "NameLabel").Text, "ซุนหงอคง")
	ip.mothersInPen = {}
	IndexWindow.setPayload(ip)
	list[2].Activated:Fire()
	check("  ไม่มีเหลือแล้ว (ขาย/ตาย) → ยังอยู่ในดัชนี · ตอนนี้มี 0 ตัว", findDescendant(detail, "Info").Text, "คลาส A · ×36\nตอนนี้มี 0 ตัว")
	check("ไม่สร้างการ์ดเกินจำนวนช่องที่มี (virtual grid)", #grid:GetChildren() <= 4, true)

	-- จุดแดง: ได้ตัวใหม่ระหว่างเล่น (หน้าต่างปิด) → ขึ้น · เปิดดัชนี → หาย
	IndexWindow.close()
	table.insert(ip.discovered, "fish")
	IndexWindow.setPayload(ip)
	check("ได้ตัวละครใหม่ (ปลา) → จุดแดงขึ้น", badge.Visible, true)
	check("  hasNewDiscovery", IndexWindow.hasNewDiscovery(), true)
	check("  ตัวเลขอัปเดต", findDescendant(win, "Total").Text, "เก็บแล้ว 5/12")
	IndexWindow.open()
	check("เปิดดัชนี → จุดแดงหาย", badge.Visible, false)
	IndexWindow.close()
	IndexWindow.setPayload(ip)
	check("sync ชุดเดิมซ้ำ → ไม่ขึ้นใหม่", badge.Visible, false)
	table.insert(ip.discovered, "ghost_two")
	IndexWindow.setPayload(ip)
	check("charId ที่ไม่มีใน Config → ไม่ขึ้นจุดแดง", badge.Visible, false)
	IndexWindow.open()
	table.insert(ip.discovered, "tang")
	IndexWindow.setPayload(ip)
	check("ได้ตัวใหม่ตอนเปิดดัชนีอยู่ → ไม่ขึ้นจุดแดง (เห็นอยู่แล้ว)", badge.Visible, false)
	IndexWindow.close()
end

print("\n━━ IndexWindow: เงาของตัวที่มีโมเดลจริง (ViewportFrame ทาดำ) ━━")
do
	-- ⚠️ ท้ายไฟล์โดยตั้งใจ — ใส่เทมเพลตโมเดลแล้วทุกหน้าต่างที่วาดลิงจะใช้ ViewportFrame
	local IndexWindow = loaded.IndexWindow
	local templates = Instance.new("Folder")
	templates.Name = "MotherModelTemplates"
	templates.Parent = services.ReplicatedStorage
	local monkeyModel = Instance.new("Model")
	monkeyModel.Name = Config.getMotherTemplateName("monkey")
	monkeyModel.Parent = templates

	local ip = makePayload()
	ip.discovered = { "pig" } -- ลิงยังไม่เคยได้
	IndexWindow.setPayload(ip)
	IndexWindow.open()
	IndexWindow.setTab("C")
	local win = findDescendant(gui, "IndexWindow")
	local grid = findDescendant(win, "Grid")
	local monkeyCard = nil
	for _, child in grid:GetChildren() do
		if child.Name == "Card" and child.Visible and monkeyCard == nil then
			monkeyCard = child -- ลิงอยู่ช่องแรกของคลาส C
		end
	end
	local portrait = findDescendant(findDescendant(monkeyCard, "PortraitHolder"), "Portrait")
	check("ลิงมีโมเดล → วาดด้วย ViewportFrame", portrait and portrait.__class, "ViewportFrame")
	check("  ยังไม่เคยได้ → ทาดำทั้งภาพ (ImageColor3 = ดำ)", portrait and portrait.ImageColor3, UiKit.BLACK)
	check("  ชื่อ ???", findDescendant(monkeyCard, "NameLabel").Text, "???")

	table.insert(ip.discovered, "monkey")
	IndexWindow.setPayload(ip)
	portrait = findDescendant(findDescendant(monkeyCard, "PortraitHolder"), "Portrait")
	check("ได้ลิงแล้ว → วาดใหม่เป็นรูปสี (ไม่ทาดำ)", portrait and portrait.ImageColor3 ~= UiKit.BLACK, true)
	check("  ชื่อ ลิง", findDescendant(monkeyCard, "NameLabel").Text, "ลิง")
	IndexWindow.close()
end

print("\n━━ โมเดลตัวละครประกอบจาก Part (12 ตัว · ทุกตัว rig R6): ประกอบได้ · ชิ้นไม่ชน · การ์ดจัดกรอบไม่ล้น · เงาดำทำงาน ━━")
do
	local MotherModels = loaded.MotherModels
	local IndexWindow = loaded.IndexWindow
	local templates = findDescendant(services.ReplicatedStorage, "MotherModelTemplates")
	-- ลิงตัวเก่า (Model เปล่าจากส่วนเงาลิงข้างบน) ออกก่อน — ใส่ของจริงที่ประกอบจาก Part แทน
	local oldMonkey = findDescendant(templates, "monkey")
	if oldMonkey then
		oldMonkey:Destroy()
	end
	local built, rigs = 0, 0
	local allParts, badParts, primaries = 0, 0, 0
	for _, charId in Config.CharacterOrder do
		if MotherModels.hasBlueprint(charId) then
			local ok, model = pcall(MotherModels.build, charId)
			if ok and model then
				built += 1
				local count = 0
				local isRig = MotherModels.getBlueprint(charId).rig ~= nil
				for _, part in model:GetChildren() do
					count += 1
					-- ไม่มี rig: ทุกชิ้น Anchored · rig: Anchored แค่ HumanoidRootPart (ชิ้นอื่นขยับตามข้อต่อ)
					local wantAnchored = not isRig or part.Name == "HumanoidRootPart"
					if part.CanCollide ~= false or part.Anchored ~= wantAnchored or part.Massless ~= true
						or part.CanTouch ~= false or part.CanQuery ~= false then
						badParts += 1
					end
				end
				if isRig then
					rigs += 1
					-- ข้อต่อ R6 6 ตัว (ชื่อ + ชิ้นตรง rig R6) · ชิ้นตกแต่งทุกชิ้นมี Weld
					local motors, welds, wrong = {}, 0, 0
					for _, part in model:GetChildren() do
						for _, child in part:GetChildren() do
							if child.__class == "Motor6D" then
								motors[child.Name] = `{child.Part0.Name}>{child.Part1.Name}`
							elseif child.__class == "Weld" then
								welds += 1
								if child.Part1 ~= part or child.Part0 == nil then
									wrong += 1
								end
							end
						end
					end
					check(`  {charId}: Motor6D ตรง R6 ครบ 6 ตัว`, motors.RootJoint == "HumanoidRootPart>Torso"
						and motors.Neck == "Torso>Head"
						and motors["Right Shoulder"] == "Torso>Right Arm" and motors["Left Shoulder"] == "Torso>Left Arm"
						and motors["Right Hip"] == "Torso>Right Leg" and motors["Left Hip"] == "Torso>Left Leg", true)
					check(`  {charId}: ชิ้นตกแต่ง {welds} ชิ้นมี Weld ติดชิ้น rig ครบ`, welds == count - #MotherModels.R6_PARTS and wrong == 0, true)
					check(`  {charId}: PrimaryPart = HumanoidRootPart (ใส)`, model.PrimaryPart and model.PrimaryPart.Name == "HumanoidRootPart"
						and model.PrimaryPart.Transparency == 1, true)
				end
				allParts += count
				if model.PrimaryPart ~= nil and model.PrimaryPart.Parent == model then
					primaries += 1
				end
				check(`{charId}: ประกอบได้ {count} ชิ้น (≤ {MotherModels.PART_LIMIT}) · ตรงกับแบบ`,
					count <= MotherModels.PART_LIMIT and count == MotherModels.getPartCount(charId), true)
				model.Name = Config.getMotherTemplateName(charId)
				model.Parent = templates
			else
				check(`{charId}: ประกอบโมเดลไม่ error`, false, true)
			end
		end
	end
	check("ประกอบได้ครบ 12 ตัว (ลิงด้วย)", built, 12)
	check("  เป็น rig R6 ครบ 12 ตัว (Motor6D + Weld · เล่นอนิเมชันของ Roblox)", rigs, 12)
	check("  ทุกชิ้น CanCollide/CanTouch/CanQuery ปิด · Massless · Anchored ตามแบบ (rig = แค่ราก)", badParts, 0)
	check("  ทุกตัวมี PrimaryPart อยู่ในโมเดล", primaries, 12)
	check("  charId ไม่มีแบบ → คืน nil (ใช้กล่องสีสำรอง)", MotherModels.build("ghost_char") == nil, true)

	-- การ์ดจัดกรอบไม่ล้น: ฉายมุม 8 มุมของกล่องล้อมรอบจริงของแต่ละตัวผ่านกล้องของ UiKit (มุมเฉียง 3/4) → ต้องอยู่ในมุมมองทุกมุม
	local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
	local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
	local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
	local function unit(a) local l = math.sqrt(dot(a, a)) return { a[1] / l, a[2] / l, a[3] / l } end
	local halfTan = math.tan(math.rad(UiKit.PORTRAIT_FOV / 2))
	local worstFill, worstId = 0, nil
	for _, charId in MotherModels.listCharIds() do
		local lo, hi, size = MotherModels.getBounds(charId)
		local direction, distance = UiKit.getPortraitCamera(Vector3.new(size[1], size[2], size[3]), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0))
		local center = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
		local eye = { center[1] + direction.X * distance, center[2] + direction.Y * distance, center[3] + direction.Z * distance }
		local forward = unit(sub(center, eye))
		local right = unit(cross(forward, { 0, 1, 0 }))
		local up = cross(right, forward)
		local fill = 0
		for _, cx in { lo[1], hi[1] } do
			for _, cy in { lo[2], hi[2] } do
				for _, cz in { lo[3], hi[3] } do
					local rel = sub({ cx, cy, cz }, eye)
					local depth = dot(rel, forward)
					fill = math.max(fill, math.abs(dot(rel, right)) / (depth * halfTan), math.abs(dot(rel, up)) / (depth * halfTan))
				end
			end
		end
		check(`  {charId}: กรอบการ์ดใช้ {string.format("%.0f", fill * 100)}% (ไม่ล้น ≤ 100%)`, fill <= 1, true)
		if fill > worstFill then
			worstFill, worstId = fill, charId
		end
	end
	print(`   แน่นสุด {worstId} {string.format("%.0f", worstFill * 100)}% ของกรอบ`)

	-- เงาดำในดัชนี: องค์หญิงพัดเหล็ก (S) ยังไม่เคยได้ = ViewportFrame ทาดำ · ได้แล้ว = สี
	local ip = makePayload()
	ip.discovered = { "jade_emperor" }
	IndexWindow.setPayload(ip)
	IndexWindow.open()
	IndexWindow.setTab("S")
	local win = findDescendant(gui, "IndexWindow")
	local grid = findDescendant(win, "Grid")
	local fanCard = nil
	for _, child in grid:GetChildren() do
		if child.Name == "Card" and child.Visible and fanCard == nil then
			fanCard = child -- องค์หญิงพัดเหล็ก (guanyin) อยู่ช่องแรกของคลาส S
		end
	end
	local portrait = findDescendant(findDescendant(fanCard, "PortraitHolder"), "Portrait")
	check("องค์หญิงพัดเหล็กมีโมเดล → วาดด้วย ViewportFrame", portrait and portrait.__class, "ViewportFrame")
	check("  ยังไม่เคยได้ → ทาดำ (เงา)", portrait and portrait.ImageColor3, UiKit.BLACK)
	check("  ชื่อ ???", findDescendant(fanCard, "NameLabel").Text, "???")
	table.insert(ip.discovered, "guanyin")
	IndexWindow.setPayload(ip)
	portrait = findDescendant(findDescendant(fanCard, "PortraitHolder"), "Portrait")
	check("ได้แล้ว → รูปสี · ชื่อใหม่", portrait and portrait.ImageColor3 ~= UiKit.BLACK
		and findDescendant(fanCard, "NameLabel").Text == "องค์หญิงพัดเหล็ก", true)
	IndexWindow.close()
end

print("\n━━ RobuxShopWindow: ร้านค้า Robux (UI-5) ━━")
do
	local RobuxShopWindow = loaded.RobuxShopWindow
	local bought = {}
	local shopActions = {
		buyProduct = function(productId)
			table.insert(bought, productId)
		end,
	}

	-- fetchPrice() ยิง task.spawn (no-op โดย default ในฮาร์เนสนี้) — บังคับให้รันจริงตอน create()
	-- เพื่อทดสอบว่าราคาที่ดึงจาก GetProductInfo จำลอง (1 Robux) ไปโผล่ในป้ายราคาจริง
	local realSpawn = __env.task.spawn
	__env.task.spawn = function(fn, ...)
		pcall(fn, ...)
	end
	RobuxShopWindow.create(gui, shopActions)
	__env.task.spawn = realSpawn

	local win = findDescendant(gui, "RobuxShopWindow")
	check("สร้างหน้าต่างได้", win ~= nil)

	local sp = makePayload()
	sp.robuxDamageBonus = 3
	sp.robuxSpeedBonus = 1
	sp.walkSpeed = 140
	sp.robuxSpeedHardCap = 150
	sp.hatchingCount = 2
	check("setPayload ตอนหน้าต่างปิดไม่ error", pcall(RobuxShopWindow.setPayload, sp))
	check("เปิดหน้าต่างไม่ error", pcall(RobuxShopWindow.open))

	local eggCard = findDescendant(win, "Card1")
	local dmgCard = findDescendant(win, "Card2")
	local spdCard = findDescendant(win, "Card3")
	local rushCard = findDescendant(win, "Card4")
	check("มีการ์ดครบ 4 ใบ (ไข่ตำนาน · ดาเมจ · ความเร็ว · เร่งฟัก)",
		eggCard ~= nil and dmgCard ~= nil and spdCard ~= nil and rushCard ~= nil, true)

	-- ⚠️ UI-fix รอบ 1: มาตรฐานสีทั้งเกม — ปุ่มซื้อทุกใบ = โทนเขียว (G เด่นกว่า R และ B)
	for _, card in { eggCard, dmgCard, spdCard, rushCard } do
		local buyColor = findDescendant(card, "Buy").BackgroundColor3
		check("ปุ่มซื้อ = โทนเขียว (G > R และ G > B)", buyColor.G > buyColor.R and buyColor.G > buyColor.B, true)
	end

	check("ราคาไข่ตำนานดึงจาก GetProductInfo จำลอง (1 Robux)", findDescendant(eggCard, "Price").Text, "💎 1")
	findDescendant(eggCard, "Buy").Activated:Fire()
	check("กดซื้อไข่ตำนาน → เรียก buyProduct(productId ของ legendary_egg)",
		bought[#bought], Config.getDeveloperProduct("legendary_egg").productId)

	check("การ์ดดาเมจ: โชว์ Lv. Robux ปัจจุบัน + ไม่มีเพดาน", findDescendant(dmgCard, "Status").Text, "Lv. Robux 3 — ไม่มีเพดาน")
	findDescendant(dmgCard, "Buy").Activated:Fire()
	check("กดซื้อดาเมจ → เรียก buyProduct(productId ของ robux_damage_step)",
		bought[#bought], Config.getRobuxProduct("robux_damage_step").productId)

	check("การ์ดความเร็ว: ยังไม่ถึงเพดาน → โชว์ความเร็วจริง", findDescendant(spdCard, "Status").Text, "Lv. Robux 1 (ความเร็วจริง 140)")
	check("  ปุ่มซื้อยังเปิดอยู่", findDescendant(spdCard, "Buy").AutoButtonColor, true)
	findDescendant(spdCard, "Buy").Activated:Fire()
	check("  กดซื้อความเร็ว → เรียก buyProduct(productId ของ robux_speed_step)",
		bought[#bought], Config.getRobuxProduct("robux_speed_step").productId)

	-- ถึงเพดานความปลอดภัยของแมพแล้ว (walkSpeed >= robuxSpeedHardCap) → ปิดปุ่ม กันเสีย Robux ฟรี
	sp.walkSpeed = 150
	RobuxShopWindow.setPayload(sp)
	check("ถึงเพดานความปลอดภัยแล้ว → ข้อความเตือน", findDescendant(spdCard, "Status").Text, "Lv. Robux 1 — ถึงเพดานความปลอดภัยของแมพแล้ว")
	check("  ปุ่มซื้อถูกปิด", findDescendant(spdCard, "Buy").AutoButtonColor, false)
	local boughtBefore = #bought
	findDescendant(spdCard, "Buy").Activated:Fire()
	check("  กดปุ่มที่ปิดแล้ว → ไม่เรียก buyProduct ซ้ำ", #bought, boughtBefore)

	check("การ์ดเร่งฟัก: มีไข่กำลังฟัก 2 ฟอง → เปิดใช้งาน", findDescendant(rushCard, "Buy").AutoButtonColor, true)
	findDescendant(rushCard, "Buy").Activated:Fire()
	check("กดเร่งฟัก → เรียก buyProduct(productId ของ robux_hatch_rush)",
		bought[#bought], Config.getRobuxProduct("robux_hatch_rush").productId)

	-- ไม่มีไข่กำลังฟักเลย → ปิดปุ่มเร่งฟัก กันซื้อไปแล้วไม่มีผลอะไรเลย
	sp.hatchingCount = 0
	RobuxShopWindow.setPayload(sp)
	check("ไม่มีไข่กำลังฟักเลย → ปุ่มเร่งฟักถูกปิด", findDescendant(rushCard, "Buy").AutoButtonColor, false)
	boughtBefore = #bought
	findDescendant(rushCard, "Buy").Activated:Fire()
	check("  กดปุ่มที่ปิดแล้ว → ไม่เรียก buyProduct ซ้ำ", #bought, boughtBefore)

	RobuxShopWindow.close()
	check("ปิดหน้าต่าง", RobuxShopWindow.isOpen(), false)
end

print("\n━━ WeaponShopWindow: ร้านกระบอง 10 ขั้น (Phase 5C) ━━")
do
	local WeaponShopWindow = loaded.WeaponShopWindow
	local shopPayload = makePayload()
	shopPayload.clubTier = 3
	shopPayload.clubMaxTier = Config.Balance.Weapon.MAX_LEVEL
	shopPayload.coins = Config.getClubPrice(4) - 1 -- ขาดอีก 1 ถึงจะซื้อขั้น 4 ได้
	WeaponShopWindow.create(gui, { buyNext = record("buyNext"), notify = record("notify") })
	check("setPayload ตอนหน้าต่างปิดไม่ error", pcall(WeaponShopWindow.setPayload, shopPayload))
	check("เปิดหน้าต่างไม่ error", pcall(WeaponShopWindow.open))
	check("isOpen", WeaponShopWindow.isOpen())
	local win = findDescendant(gui, "WeaponShopWindow")
	local rowCount = 0
	for tier = 1, 20 do
		if findDescendant(win, `ClubRow{tier}`) then
			rowCount += 1
		end
	end
	check("มีครบ 10 แถว", rowCount, 10)

	-- ══ 3 สถานะของแถว ══
	local function rowPart(tier, name)
		return findDescendant(findDescendant(win, `ClubRow{tier}`), name)
	end
	local ownedOk, lockedOk = true, true
	for tier = 1, 3 do
		if WeaponShopWindow.getRowState(tier) ~= "owned" or rowPart(tier, "Status").Text ~= "✔ มีแล้ว"
			or rowPart(tier, "Buy").Visible or rowPart(tier, "LockedShade").Visible then
			ownedOk = false
		end
	end
	check("สถานะ 1 — ขั้น 1–3 (มีแล้ว): ✔ มีแล้ว · ไม่มีปุ่มซื้อ · ไม่มีม่านเทา", ownedOk)
	check("สถานะ 2 — ขั้น 4 (ถัดไป): ปุ่มซื้อโผล่", WeaponShopWindow.getRowState(4) == "next" and rowPart(4, "Buy").Visible, true)
	local buyColor = rowPart(4, "Buy").BackgroundColor3
	check("  ปุ่มซื้อสีเขียว (มาตรฐาน ซื้อ = เขียว)", buyColor.G > buyColor.R and buyColor.G > buyColor.B, true)
	check("  ไม่มีม่านเทา", rowPart(4, "LockedShade").Visible, false)
	for tier = 5, 10 do
		if WeaponShopWindow.getRowState(tier) ~= "locked" or rowPart(tier, "Status").Text ~= "ซื้อขั้นก่อนหน้าก่อน"
			or rowPart(tier, "Buy").Visible or not rowPart(tier, "LockedShade").Visible then
			lockedOk = false
		end
	end
	check("สถานะ 3 — ขั้น 5–10 (ล็อก): เห็นแต่เทา + \"ซื้อขั้นก่อนหน้าก่อน\" · ไม่มีปุ่มซื้อ", lockedOk)

	-- ══ ราคาแดงเมื่อเงินไม่พอ ══
	local price4 = rowPart(4, "Price")
	check("เงินไม่พอ → ราคาขั้นถัดไปสีแดง", price4.TextColor3.R > 0.8 and price4.TextColor3.G < 0.4, true)
	check("  describeRow บอก poor", WeaponShopWindow.describeRow(4, shopPayload).priceTone, "poor")
	check("  ราคาแสดงจาก Config", price4.Text, `฿{UiKit.formatShort(Config.getClubPrice(4))}`)
	shopPayload.coins = Config.getClubPrice(4)
	WeaponShopWindow.setPayload(shopPayload)
	check("เงินพอดี → ราคาไม่แดง (สีทอง)", price4.TextColor3.R > 0.9 and price4.TextColor3.G > 0.8, true)
	check("  describeRow บอก price", WeaponShopWindow.describeRow(4, shopPayload).priceTone, "price")
	check("ขั้น 1 ราคา \"ฟรี\"", rowPart(1, "Price").Text, "ฟรี")
	check("ดาเมจขั้น 5 จาก Config", rowPart(5, "Damage").Text, `⚔ {UiKit.formatShort(Config.getClubDamage(5))} / ครั้ง`)
	check("ชื่อขั้น 1", rowPart(1, "ClubName").Text, Config.getClubVisual(1).name)
	check("มีรูปกระบองเล็ก (หัว + ด้าม)", rowPart(9, "Head") ~= nil and rowPart(9, "Handle") ~= nil, true)

	-- ══ กดซื้อ = ยิง action ไม่มีพารามิเตอร์ (server ซื้อขั้นถัดไปเอง) ══
	rowPart(4, "Buy").Activated:Fire()
	check("กดซื้อ → buyNext()", lastCall().name, "buyNext")
	check("  ไม่ส่งเลขขั้น", lastCall().args.n, 0)
	shopPayload.clubTier = 4
	WeaponShopWindow.setPayload(shopPayload)
	check("sync หลังซื้อ → ขั้น 4 มีแล้ว · ขั้น 5 ถัดไป · ขั้น 6 ล็อก",
		WeaponShopWindow.getRowState(4) == "owned" and WeaponShopWindow.getRowState(5) == "next"
			and WeaponShopWindow.getRowState(6) == "locked", true)

	-- ══ ขอบ ══
	shopPayload.clubTier = Config.Balance.Weapon.MAX_LEVEL
	WeaponShopWindow.setPayload(shopPayload)
	local anyNotOwned = false
	for tier = 1, 10 do
		if WeaponShopWindow.getRowState(tier) ~= "owned" then
			anyNotOwned = true
		end
	end
	check("ขั้น 10 แล้ว → ทุกแถวมีแล้ว ไม่มีปุ่มซื้อ", anyNotOwned, false)
	shopPayload.clubTier = 99
	check("clubTier แปลก (99) ไม่ error · ถือเป็นขั้น 10", pcall(WeaponShopWindow.setPayload, shopPayload)
		and WeaponShopWindow.getRowState(10) == "owned", true)
	shopPayload.clubTier = nil
	check("ไม่มี clubTier → ถือว่าขั้น 1 (ขั้น 2 = ถัดไป)", pcall(WeaponShopWindow.setPayload, shopPayload)
		and WeaponShopWindow.getRowState(1) == "owned" and WeaponShopWindow.getRowState(2) == "next", true)
	check("describeRow ก่อนมี sync ไม่ error", (pcall(WeaponShopWindow.describeRow, 3, nil)))
	WeaponShopWindow.close()
	check("ปิดหน้าต่าง", WeaponShopWindow.isOpen(), false)
end

print("\n━━ BossHud: เลขดาเมจเด้งเหนือบอส (Phase 5C · เทียบ HP ห้องนั้นกับค่าก่อนหน้า) ━━")
do
	local BossHud = loaded.BossHud
	check("ค่าแรกของห้อง → ไม่เด้ง", BossHud.onBossHpChanged(3, 10000) == nil)
	check("HP ลด 30 → เด้ง 30", BossHud.onBossHpChanged(3, 9970), 30)
	check("HP ลดอีก 60 (ตีสองคนในรอบเดียว) → เด้ง 60", BossHud.onBossHpChanged(3, 9910), 60)
	check("HP เพิ่ม (บอสเกิด/ฟื้นกลางคืน) → ไม่เด้ง", BossHud.onBossHpChanged(3, 10000) == nil)
	check("ห้องอื่นแยกกัน (ค่าแรกของห้อง 4) → ไม่เด้ง", BossHud.onBossHpChanged(4, 100000) == nil)
	check("ตีตาย (HP → 0) → เด้งส่วนที่เหลือ", BossHud.onBossHpChanged(3, 0), 10000)
	check("ค่าแปลก → ไม่เด้ง ไม่ error", BossHud.onBossHpChanged(3, "x") == nil)
end

print("\n━━ BossHud: ตัวเลขนับถอยหลังบนกำแพงกั้นบอส (Phase 5A) ━━")
do
	local BossHud = loaded.BossHud
	local barrier = newInstance("Part")
	barrier.Name = Config.BOSS_BARRIER_NAME
	local hudGui = newInstance("PlayerGui")
	check("ติดตัวเลขกับกำแพงกั้นไม่ error", pcall(BossHud.attach, hudGui, barrier))
	local surface = findDescendant(hudGui, "BossBarrierCountdown")
	local count = findDescendant(hudGui, "Count")
	check("  SurfaceGui ติดกำแพงกั้น (Adornee)", surface and surface.Adornee == barrier, true)
	check("  อยู่ผิวหน้า −X (ฝั่งที่ผู้เล่นยืนรอ)", surface and surface.Face, "Enum.NormalId.Left")

	local night = Config.Balance.BossCycle.NIGHT_SECONDS
	local endsAt = 10000
	BossHud.setState({ phase = "night", phaseEndsAt = endsAt, bossAlive = {} })
	BossHud.render(endsAt - night)
	check("กลางคืนวินาทีแรก → โชว์ 59", count.Text, "59")
	check("  แผ่นตัวเลขเปิดอยู่", surface.Enabled, true)
	BossHud.render(endsAt - 30.5)
	check("กลางคืนเหลือ 30.5 วิ → 30", count.Text, "30")
	BossHud.render(endsAt - 0.4)
	check("วินาทีสุดท้าย → 0", count.Text, "0")
	BossHud.render(endsAt + 2)
	check("เลยเวลาไปแล้ว (รอ server เปลี่ยน phase) → ค้าง 0 ไม่ติดลบ", count.Text, "0")

	BossHud.setState({ phase = "day", phaseEndsAt = endsAt + 540, bossAlive = {} })
	BossHud.render(endsAt + 3)
	check("กลางวัน → ซ่อนตัวเลข", surface.Enabled, false)

	BossHud.setState({ phase = "night", phaseEndsAt = endsAt + 1200, bossAlive = {} })
	BossHud.render(endsAt + 1200 - night)
	check("คืนถัดไป → โชว์ 59 ใหม่", count.Text .. tostring(surface.Enabled), "59true")

	BossHud.setState({})
	check("ยังไม่ได้สถานะจาก server → ไม่ error และไม่โชว์", pcall(BossHud.render, 0) and surface.Enabled == false, true)
end

print("\n━━ BossHud: จุดกด E ค้างที่ไข่บอส (Phase 5B · 5B-2 ทุกห้อง + บอก server จังหวะกดค้าง) ━━")
do
	local BossHud = loaded.BossHud
	local picked = {}
	local holds = {}
	local eggs = {}
	local function onPick(i)
		table.insert(picked, i)
	end
	local function onHold(i, holding)
		table.insert(holds, `{i}:{tostring(holding)}`)
	end
	-- ห้อง 1 ครบ 6 ฟอง (ชื่อ/Attribute ตามที่ MapBuilder สร้าง)
	for index = 1, Config.Balance.BossCycle.EGGS_PER_NIGHT do
		local part = newInstance("Part")
		part.Name = Config.getBossEggPartName(1, index)
		part:SetAttribute("Room", 1)
		part:SetAttribute("Index", index)
		part:SetAttribute("Status", "none")
		eggs[index] = part
		check(`ติดจุดกดที่ไข่ห้อง 1 ฟอง {index} ไม่ error`, pcall(BossHud.attachEggPrompt, part, onPick, onHold))
	end
	-- 5B-2: ห้อง 2 ฟองที่ 1 — index ซ้ำกับห้อง 1 ต้องติดได้แยกกัน
	local room2Egg = newInstance("Part")
	room2Egg.Name = Config.getBossEggPartName(2, 1)
	room2Egg:SetAttribute("Room", 2)
	room2Egg:SetAttribute("Index", 1)
	room2Egg:SetAttribute("Status", "none")
	check("ติดจุดกดที่ไข่ห้อง 2 ฟอง 1 (index ซ้ำห้อง 1) ไม่ error", pcall(BossHud.attachEggPrompt, room2Egg, onPick, onHold))
	local room2Prompt = findDescendant(room2Egg, "PickUpBossEgg")
	check("  ไข่ห้อง 2 มีจุดกดของตัวเอง", room2Prompt ~= nil, true)
	local noRoom = newInstance("Part")
	noRoom:SetAttribute("Index", 1)
	BossHud.attachEggPrompt(noRoom, onPick, onHold)
	check("  Part ไม่มี Attribute Room → ไม่ติด", findDescendant(noRoom, "PickUpBossEgg") == nil, true)

	local prompt1 = findDescendant(eggs[1], "PickUpBossEgg")
	check("  prompt อยู่ใต้ Part ไข่", prompt1 ~= nil, true)
	check("  สร้างผ่าน UiKit.prompt (OnePerButton)", prompt1 and prompt1.Exclusivity, "Enum.ProximityPromptExclusivity.OnePerButton")
	check("  กดค้างตาม EGG_PICKUP_HOLD_SECONDS", prompt1 and prompt1.HoldDuration, Config.Balance.BossCycle.EGG_PICKUP_HOLD_SECONDS)
	check("  ระยะกดตาม EggPromptDistance", prompt1 and prompt1.MaxActivationDistance, Config.MapDimensions.BossArena.EggPromptDistance)
	BossHud.attachEggPrompt(eggs[1], onPick, onHold)
	local count = 0
	for _, child in rawget(eggs[1], "__children") do
		if child.Name == "PickUpBossEgg" then
			count += 1
		end
	end
	check("  ติดซ้ำฟองเดิม → ไม่เพิ่ม prompt", count, 1)

	-- ไข่ชุดใหม่ขึ้นห้อง (กลางคืน · บอสอยู่) → เห็นไข่แต่ยังไม่มีจุดกด
	for _, part in eggs do
		part:SetAttribute("Status", "resting")
	end
	room2Egg:SetAttribute("Status", "resting")
	BossHud.setState({ phase = "night", phaseEndsAt = 100, bossAlive = { [1] = true, [2] = true } })
	check("บอสยังอยู่ → จุดกดปิด (เห็นไข่ แต่หยิบไม่ได้)", prompt1.Enabled, false)
	-- 5B-fix (ผู้ใช้สั่ง "ให้ผู้เล่นลุ้น"): ไม่โชว์น้ำหนักบน prompt
	check("  ชื่อบน prompt ไม่บอกน้ำหนัก", prompt1.ObjectText, "ไข่บอส")
	BossHud.setState({ phase = "day", phaseEndsAt = 700, bossAlive = { [1] = false, [2] = true } })
	check("บอสห้อง 1 ตายแล้ว → จุดกดห้อง 1 เปิด", prompt1.Enabled, true)
	check("  บอสห้อง 2 ยังอยู่ → จุดกดห้อง 2 ยังปิด (5B-2 แยกห้อง)", room2Prompt.Enabled, false)
	BossHud.setState({ phase = "day", phaseEndsAt = 700, bossAlive = {} })
	check("  ยังไม่รู้สถานะบอส (ไม่มี Attribute) → ปิดไว้ก่อน", prompt1.Enabled, false)
	BossHud.setState({ phase = "day", phaseEndsAt = 700, bossAlive = { [1] = false, [2] = true } })

	-- 5B-2: บอก server ว่าเริ่มกด/ปล่อย (server จับเวลาเอง)
	prompt1.PromptButtonHoldBegan:Fire()
	prompt1.PromptButtonHoldEnded:Fire()
	check("เริ่มกด/ปล่อย → บอก server 'ฟองที่ 1' true แล้ว false", table.concat(holds, ","), "1:true,1:false")
	prompt1.Triggered:Fire()
	check("กดครบเวลา → ยิงคำขอหยิบ 'ฟองที่ 1' เท่านั้น", table.concat(picked, ","), "1")

	eggs[1]:SetAttribute("Status", "carried")
	check("ฟองที่มีคนถือ → จุดกดปิด", prompt1.Enabled, false)
	local prompt2 = findDescendant(eggs[2], "PickUpBossEgg")
	check("  ฟองอื่นยังเปิด", prompt2.Enabled, true)
	BossHud.setCarrying(true)
	check("ตัวเองถือไข่อยู่ → ปิดจุดกดทุกฟอง (ถือทีละฟอง)", prompt2.Enabled, false)
	BossHud.setCarrying(false)
	check("  วางลง/ส่งแล้ว → เปิดกลับ", prompt2.Enabled, true)
	eggs[2]:SetAttribute("Status", "gone")
	check("ฟองที่เก็บไปแล้ว → จุดกดปิด", prompt2.Enabled, false)
	BossHud.setState({ phase = "night", phaseEndsAt = 1300, bossAlive = { [1] = true, [2] = true } })
	local anyOpen = false
	for _, part in eggs do
		local prompt = findDescendant(part, "PickUpBossEgg")
		if prompt and prompt.Enabled then
			anyOpen = true
		end
	end
	check("คืนถัดไป (บอสเกิดใหม่) → จุดกดปิดทุกฟอง", anyOpen, false)
end

print("\n━━ HealthBar: แถบเลือดเหนือ hotbar · ขึ้นเฉพาะในสนามรบหรือเลือดไม่เต็ม · จอแดงวาบตอนโดนตี (Phase 5D) ━━")
do
	local HealthBar = loaded.HealthBar
	check("ในลาน เลือดเต็ม → ซ่อน", HealthBar.shouldShow(false, 100, 100), false)
	check("ในสนามรบ เลือดเต็ม → ขึ้น", HealthBar.shouldShow(true, 100, 100), true)
	check("ในลาน เลือดไม่เต็ม → ขึ้น", HealthBar.shouldShow(false, 60, 100), true)
	check("ในสนามรบ เลือดไม่เต็ม → ขึ้น", HealthBar.shouldShow(true, 60, 100), true)
	check("ตายแล้ว (0) → ขึ้น", HealthBar.shouldShow(false, 0, 100), true)
	check("ยังไม่มีตัวละคร (เลือดเต็ม 0) → ซ่อน", HealthBar.shouldShow(true, 0, 0), false)

	local hudGui = Instance.new("ScreenGui")
	local hotbarFrame = Hotbar.getFrame()
	check("Hotbar.getFrame คืนกรอบแถบ", hotbarFrame ~= nil and hotbarFrame.Name == "Hotbar", true)
	check("สร้างแถบเลือดไม่ error", (pcall(HealthBar.create, hudGui, hotbarFrame)))
	local bar = findDescendant(hotbarFrame, "HealthBar")
	check("แถบเลือดเป็นลูกของกรอบ hotbar (ขยับตามแถบ · ไม่ทับช่อง)", bar ~= nil and bar.Parent == hotbarFrame, true)
	check("  วางเหนือแถบ (ขอบล่างของแถบเลือดอยู่เหนือขอบบน hotbar)", bar.AnchorPoint.Y == 1 and bar.Position.Y.Scale == 0
		and bar.Position.Y.Offset < 0, true)
	check("  กว้างไม่เกินแถบ hotbar (ไม่ล้นไปทับเลเวลมุมล่างซ้าย)", bar.Size.X.Offset <= hotbarFrame.Size.X.Offset + 0.001, true)
	check("  เริ่มต้นซ่อน", bar.Visible, false)
	local flash = findDescendant(hudGui, "HitFlash")
	check("จอแดงวาบอยู่ใน ScreenGui เต็มจอ", flash ~= nil and flash.Size.X.Scale == 1 and flash.Size.Y.Scale == 1, true)

	check("เลือดเต็มในลาน → ไม่วาบ", HealthBar.update(100, 100, false), false)
	check("  แถบซ่อน", bar.Visible, false)
	HealthBar.update(100, 100, true)
	check("เดินเข้าสนามรบ → แถบขึ้น", bar.Visible, true)
	check("โดนตี 100 → 80 → จอแดงวาบ", HealthBar.update(80, 100, true), true)
	check("  จอแดงโผล่", flash.Visible, true)
	check("  ข้อความเลือด", findDescendant(bar, "Text").Text, "❤ 80 / 100")
	check("  ส่วนเติม 80%", findDescendant(bar, "Fill").Size.X.Scale, 0.8)
	check("เลือดเท่าเดิม → ไม่วาบซ้ำ", HealthBar.update(80, 100, true), false)
	check("ฟื้นเลือด (80 → 100) → ไม่วาบ", HealthBar.update(100, 100, true), false)
	HealthBar.update(100, 100, false)
	check("กลับเข้าลานเลือดเต็ม → แถบซ่อน", bar.Visible, false)
	HealthBar.update(40, 100, false)
	check("เลือดไม่เต็มแม้อยู่ในลาน → แถบยังขึ้น", bar.Visible, true)
	check("เลือดน้อย (20%) → สีแดง", HealthBar.fillColor(0.2) == HealthBar.fillColor(0.1) and HealthBar.fillColor(0.2) ~= HealthBar.fillColor(0.9), true)
	HealthBar.resetTracking()
	check("เกิดใหม่ (เลือดเต็ม) → ไม่นับเป็นโดนตี", HealthBar.update(100, 100, false), false)
	check("relayout ซ้ำไม่ error", (pcall(HealthBar.relayout)))
end

print("\n━━ NightSky: กลางคืน = พระจันทร์ + มืดลง · เช้ากลับค่าเดิม · เวลาในวันเดินหน้าเสมอ ━━")
do
	local NightSky = loaded.NightSky
	local sky = Config.NightSky
	check("เวลาเดินหน้า 14 → 0 ครึ่งทาง = 19 (ตกดิน ไม่ย้อนผ่านเช้า)", NightSky.forwardClock(14, 0, 0.5), 19)
	check("เวลาเดินหน้า 0 → 14 ครึ่งทาง = 7 (รุ่งเช้า ไม่ย้อน)", NightSky.forwardClock(0, 14, 0.5), 7)
	check("  ปลายทางพอดี = 0", NightSky.forwardClock(14, 0, 1), 0)

	local lighting = Instance.new("Lighting")
	local dayAmbient = Color3.fromRGB(70, 70, 70)
	local dayOutdoor = Color3.fromRGB(128, 128, 128)
	lighting.ClockTime = 14
	lighting.Brightness = 2
	lighting.ExposureCompensation = 0
	lighting.Ambient = dayAmbient
	lighting.OutdoorAmbient = dayOutdoor
	NightSky.attach(lighting)
	check("เริ่มกลางวัน: ไม่มี Sky ที่สร้างเอง", lighting:FindFirstChildOfClass("Sky") == nil, true)
	check("  phase เดิม (day) → ไม่เปลี่ยน", NightSky.setPhase("day", 0), false)
	check("  phase แปลก (nil) = กลางวัน → ไม่เปลี่ยน", NightSky.setPhase(nil, 0), false)
	check("เข้ากลางคืน → เปลี่ยน", NightSky.setPhase("night", 100), true)
	local moonSky = lighting:FindFirstChildOfClass("Sky")
	check("  สร้าง Sky ชั่วคราว · พระจันทร์ใหญ่ขึ้น", moonSky and moonSky.MoonAngularSize, sky.MOON_ANGULAR_SIZE)
	check("  ยังไม่ทันเปลี่ยน (t = 0) = ค่ากลางวัน", lighting.ClockTime, 14)
	NightSky.step(100 + sky.TRANSITION_SECONDS / 2)
	check("  ครึ่งทาง: ช่วงตกดิน (เวลา 14 → 24)", lighting.ClockTime > 14 and lighting.ClockTime < 24, true)
	check("  ครึ่งทาง: มืดลงแล้วแต่ยังไม่สุด", lighting.Brightness < 2 and lighting.Brightness > 2 * sky.BRIGHTNESS_SCALE, true)
	check("  ครบเวลา → เสร็จ", NightSky.step(100 + sky.TRANSITION_SECONDS), 1)
	check("  เที่ยงคืน (เห็นพระจันทร์)", lighting.ClockTime, sky.CLOCK_TIME)
	check("  ความสว่าง = กลางวัน × สเกล", lighting.Brightness, 2 * sky.BRIGHTNESS_SCALE)
	check("  exposure ลดลงตาม offset", lighting.ExposureCompensation, sky.EXPOSURE_OFFSET)
	check("  สี ambient แสงจันทร์", lighting.Ambient == sky.AMBIENT and lighting.OutdoorAmbient == sky.OUTDOOR_AMBIENT, true)
	check("  กลางคืนซ้ำ → ไม่เปลี่ยน", NightSky.setPhase("night", 150), false)

	check("เข้ากลางวัน → เปลี่ยน", NightSky.setPhase("day", 200), true)
	NightSky.step(200 + sky.TRANSITION_SECONDS / 2)
	check("  ครึ่งทาง: รุ่งเช้า (เวลา 0 → 14 เดินหน้า)", lighting.ClockTime > 0 and lighting.ClockTime < 14, true)
	check("  ระหว่างรุ่งเช้ายังเห็นพระจันทร์ (Sky ยังอยู่)", lighting:FindFirstChildOfClass("Sky") ~= nil, true)
	NightSky.step(200 + sky.TRANSITION_SECONDS)
	check("  กลับเวลากลางวันเดิม", lighting.ClockTime, 14)
	check("  ความสว่างเดิม", lighting.Brightness, 2)
	check("  exposure เดิม", lighting.ExposureCompensation, 0)
	check("  สี ambient เดิม", lighting.Ambient == dayAmbient and lighting.OutdoorAmbient == dayOutdoor, true)
	check("  ลบ Sky ที่สร้างเองแล้ว", lighting:FindFirstChildOfClass("Sky") == nil, true)

	-- เกมมี Sky อยู่แล้ว: ขยายพระจันทร์ชั่วคราว · เช้าคืนขนาดเดิม · ไม่สร้าง/ไม่ลบ Sky
	local lighting2 = Instance.new("Lighting")
	lighting2.ClockTime = 12
	lighting2.Brightness = 3
	lighting2.ExposureCompensation = 0.2
	lighting2.Ambient = dayAmbient
	lighting2.OutdoorAmbient = dayOutdoor
	local ownSky = Instance.new("Sky")
	ownSky.MoonAngularSize = 11
	ownSky.Parent = lighting2
	NightSky.attach(lighting2)
	check("เข้าเกมตอนกลางคืน (instant) → มืดทันที", NightSky.setPhase("night", 0, true) and lighting2.ClockTime == sky.CLOCK_TIME, true)
	check("  ใช้ Sky เดิม ขยายพระจันทร์ (ไม่สร้างเพิ่ม)", #lighting2:GetChildren() == 1 and ownSky.MoonAngularSize == sky.MOON_ANGULAR_SIZE, true)
	NightSky.setPhase("day", 10)
	NightSky.step(10 + sky.TRANSITION_SECONDS)
	check("  เช้า: พระจันทร์คืนขนาดเดิม · Sky เดิมยังอยู่", ownSky.MoonAngularSize == 11 and ownSky.Parent == lighting2, true)
	check("  ความสว่าง/exposure กลับค่าเดิมของเกมนี้", lighting2.Brightness == 3 and lighting2.ExposureCompensation == 0.2, true)
end

print(string.format("\n=== ผ่าน %d / ตก %d ===", passCount, failCount))
if failCount > 0 then
	error(`มีเทสต์ตก {failCount} เคส`, 0)
end
'''


# โมดูลใน src/shared ที่ต้องใช้ Roblox global ตอนเรียก (ไม่ใช่ตอน require) — โหลดแบบเดียวกับโมดูล client
# รอบโมเดลตัวละคร: MotherModels.build ประกอบโมเดลจาก Part (Instance/CFrame/Enum ของ harness)
SHARED_MODULES = ['MotherModels']


def module_source(name: str, folder: str = 'client') -> str:
    path = os.path.join(ROOT, 'src', folder, f'{name}.lua')
    src = open(path, encoding='utf-8').read()
    if not src.startswith('--!strict'):
        sys.exit(f'harness ตามซอร์สไม่ทัน: {name}.lua ไม่ได้ขึ้นต้นด้วย --!strict')
    return src.replace('--!strict', '--!nocheck' + PRELUDE, 1)


def build_harness() -> str:
    loads = []
    for name, folder in [(n, 'shared') for n in SHARED_MODULES] + [(n, 'client') for n in MODULES]:
        src = module_source(name, folder)
        escaped = src.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
        loads.append(f'loadModule("{name}", "{escaped}")')
    return MOCK + CHECK.replace('__LOAD_MODULES__', '\n'.join(loads))


# ⚠️ ประกอบ harness ให้เสร็จก่อนค่อยเปิดไฟล์ — กันไฟล์ว่างค้างถ้า build_harness() หยุดกลางทาง
harness_source = build_harness()
harness = os.path.join(ROOT, '.ui-smoke-check.luau')
with open(harness, 'w', encoding='utf-8') as f:
    f.write(harness_source)

try:
    proc = subprocess.run([LUAU, harness], capture_output=True, text=True, cwd=ROOT)
finally:
    os.remove(harness)

print(proc.stdout)
if proc.returncode != 0:
    print(proc.stderr, file=sys.stderr)
    sys.exit(1)

# ══ 5D: ต่อสายใน Main.client.lua (ตรวจซอร์ส — harness ไม่ได้รัน Main) ══
main_src = open(os.path.join(ROOT, 'src', 'client', 'Main.client.lua'), encoding='utf-8').read()
static_checks = [
    ('Main สร้างแถบเลือดเหนือ hotbar (HealthBar.create(hud, Hotbar.getFrame()))', 'HealthBar.create(hud, Hotbar.getFrame())' in main_src),
    ('Main ต่อแถบเลือดกับตัวละคร (HealthBar.start())', 'HealthBar.start()' in main_src),
    ('Main ปิดแถบเลือด/จอแดงของ Roblox (CoreGuiType.Health) กันซ้อนสองชุด', 'SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)' in main_src),
    ('Main เปิดท้องฟ้ากลางคืน (NightSky.start())', 'NightSky.start()' in main_src),
]
static_fail = 0
for label, ok in static_checks:
    print(f'  {"✓" if ok else "✗"} {label}')
    if not ok:
        static_fail += 1
if static_fail:
    sys.exit(f'ต่อสาย HealthBar/NightSky ใน Main.client.lua ไม่ครบ {static_fail} ข้อ')
