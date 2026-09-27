# -*- coding: utf-8 -*-
"""Smoke test ของ UI ฝั่ง client (UI-1): Hotbar · BagWindow · SidePanels · UiKit

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

MODULES = ['UiKit', 'Hotbar', 'BagWindow', 'SidePanels']

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
		__propSignals = {},
		Activated = newSignal(),
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
local services = {
	UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = newSignal() },
	Workspace = { CurrentCamera = camera },
	ReplicatedStorage = newInstance("ReplicatedStorage"),
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
		damageLevel = 7,
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
		sellMother = record("sellMother"),
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
	check("  ปุ่มขาย TEMP มีราคา", string.find(findDescendant(detail, "Action3").Text, "TEMP", 1, true) ~= nil)
	findDescendant(detail, "Action4").Activated:Fire()
	check("  ส่งไปรบ → เปิดกล่องยืนยัน (sendToBattle ได้ตัวแม่)", lastCall().name == "sendToBattle" and lastCall().args[1].uid == "1-123", true)

	-- แม่ในกระเป๋าที่ล็อก → ปุ่มขาย/ส่งรบถูกปิด กดแล้วแค่แจ้งเตือน
	payload.mothersInBag[23].locked = true
	BagWindow.setPayload(payload)
	check("ล็อกแล้ว: ปุ่มขายถูกปิด", findDescendant(detail, "Action3").AutoButtonColor, false)
	local before = #calls
	findDescendant(detail, "Action3").Activated:Fire()
	check("  กดขายตอนล็อก → notify ไม่ใช่ sellMother", lastCall().name == "notify" and #calls == before + 1, true)
	findDescendant(detail, "Action4").Activated:Fire()
	check("  กดส่งรบตอนล็อก → notify", lastCall().name, "notify")
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
	check("  ไม่มีปุ่มขาย", findDescendant(detail, "Action3").Visible, false)
	check("  ไม่มีปุ่มส่งรบ", findDescendant(detail, "Action4").Visible, false)
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
