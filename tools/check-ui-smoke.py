# -*- coding: utf-8 -*-
"""Smoke test ของ UI ฝั่ง client (UI-1 · UI-2): Hotbar · BagWindow · SidePanels · UiKit · SellWindow · MapSigns

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

MODULES = ['UiKit', 'Hotbar', 'BagWindow', 'SidePanels', 'SellWindow', 'MapSigns']

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
local Vector3 = { new = function(x, y, z) return typed("Vector3", { X = x or 0, Y = y or 0, Z = z or 0 }) end }
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
local CFrame = { lookAt = function(a, b) return typed("CFrame", { a = a, b = b }) end }
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
		sendToBattle = record("sendToBattle"),
		placeEgg = record("placeEgg"),
		notify = record("notify"),
		isRosterFull = function() return false end,
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
	-- UI-2: ปุ่มขาย (TEMP) ย้ายไปร้านขายแม่หลังแมพแล้ว → ส่งไปรบขยับขึ้นมาช่อง 3
	local anySell = false
	for index = 1, 4 do
		local button = findDescendant(detail, `Action{index}`)
		if button.Visible and string.find(button.Text, "ขาย", 1, true) then
			anySell = true
		end
	end
	check("  ไม่มีปุ่มขายในหน้ารายละเอียดแล้ว (UI-2)", anySell, false)
	check("  ปุ่ม 3 = ส่งไปรบ (TEMP)", findDescendant(detail, "Action3").Text, "ส่งไปรบ (TEMP)")
	check("  ปุ่ม 4 ซ่อน", findDescendant(detail, "Action4").Visible, false)
	findDescendant(detail, "Action3").Activated:Fire()
	check("  ส่งไปรบ → เปิดกล่องยืนยัน (sendToBattle ได้ตัวแม่)", lastCall().name == "sendToBattle" and lastCall().args[1].uid == "1-123", true)

	-- แม่ในกระเป๋าที่ล็อก → ปุ่มส่งรบถูกปิด กดแล้วแค่แจ้งเตือน
	payload.mothersInBag[23].locked = true
	BagWindow.setPayload(payload)
	check("ล็อกแล้ว: ปุ่มส่งรบถูกปิด", findDescendant(detail, "Action3").AutoButtonColor, false)
	local before = #calls
	findDescendant(detail, "Action3").Activated:Fire()
	check("  กดส่งรบตอนล็อก → notify ไม่ใช่ sendToBattle", lastCall().name == "notify" and #calls == before + 1, true)
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
	SidePanels.create(gui, { unequip = record("unequip"), equipBest = record("equipBest") })
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

	localPlayer:SetAttribute(Config.PEN_INDEX_ATTRIBUTE, 2)
	local playerGui = newInstance("PlayerGui")
	local shopOpen = false
	local signActions = {
		buy = record("buy"),
		openSellShop = function()
			shopOpen = true
		end,
		closeSellShop = record("closeSellShop"),
		isSellShopOpen = function()
			return shopOpen
		end,
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
end

print(string.format("\n=== ผ่าน %d / ตก %d ===", passCount, failCount))
if failCount > 0 then
	error(`มีเทสต์ตก {failCount} เคส`, 0)
end
'''


def module_source(name: str) -> str:
    path = os.path.join(ROOT, 'src', 'client', f'{name}.lua')
    src = open(path, encoding='utf-8').read()
    if not src.startswith('--!strict'):
        sys.exit(f'harness ตามซอร์สไม่ทัน: {name}.lua ไม่ได้ขึ้นต้นด้วย --!strict')
    return src.replace('--!strict', '--!nocheck' + PRELUDE, 1)


def build_harness() -> str:
    loads = []
    for name in MODULES:
        src = module_source(name)
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
