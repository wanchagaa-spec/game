--!strict
-- egg-army-game :: ระบบคอก (จองพื้นที่ + แสดงแม่ + สวนฟัก)
--
-- ⚠️ เปลี่ยนชื่อจาก PlotService ตอน Phase 1.5 — "plot" เป็นคำของกลไกเก่า
-- ดีไซน์ใหม่เรียกพื้นที่ของผู้เล่นว่า **คอก**
--
-- หน้าที่: สร้างพื้นที่ในโลก แล้วจองให้ผู้เล่นคนละ 1 คอก
-- ผู้เล่นออก → คืนคอกให้คนถัดไปใช้ต่อ
--
-- คอก 1 ช่องประกอบด้วย:
--   - ที่วาง **แม่** ตาม Config.getPenCapacity(penLevel) — ความจุโตตามเลเวล
--   - **สวนฟัก** Config.Hatchery.MAX_EGGS ช่อง (แยกจากที่วางแม่)
--
-- Phase 1.5: ยังเป็นแค่แผ่นพื้นกับแท่น ยังไม่มีของตกแต่ง (Phase 5 ค่อย polish)
-- ตัวโลกทั้งหมดสร้างด้วยโค้ด เพราะ place ที่ build จาก Rojo ไม่มี Baseplate มาให้

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local PenService = {}

export type Pen = {
	index: number, -- เลขคอก 1..MAX_PENS
	model: Model, -- Model ที่รวมทุกอย่างของคอกนี้
	base: Part, -- แผ่นพื้น
	motherStands: { Part }, -- ที่วางแม่ เรียงตามลำดับในคอก (สร้างไว้เท่าความจุสูงสุด)
	hatchPads: { Part }, -- แท่นฟักไข่ เรียงตาม slotIndex 1..MAX_EGGS
	label: TextLabel, -- ป้ายบอกเจ้าของ (ไว้ดูตอนเทสต์)
	ownerUserId: number?, -- nil = ว่าง
}

local WORLD = Config.World
local MAX_PEN_CAPACITY = Config.getPenCapacity(Config.Pen.MAX_LEVEL)
local HATCHERY_SLOTS = Config.Hatchery.MAX_EGGS

local pens: { Pen } = {}
local penByUserId: { [number]: Pen } = {}
local built = false

local EMPTY_LABEL = "ว่าง"
local STAND_SIZE = Vector3.new(4, 1, 4)
local PAD_SIZE = Vector3.new(3, 0.6, 3)
local HATCH_COLUMNS = 10

--------------------------------------------------------------------------------
-- สร้างโลก
--------------------------------------------------------------------------------

local function createPen(index: number, parent: Folder): Pen
	-- คอกเรียงกันเป็นแถวตามแกน X
	local origin = WORLD.PEN_ORIGIN + Vector3.new((index - 1) * WORLD.PEN_SPACING, 0, 0)

	local model = Instance.new("Model")
	model.Name = `Pen{index}`

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = WORLD.PEN_SIZE
	base.Position = origin
	base.Anchored = true
	base.Material = Enum.Material.Grass
	base.Color = Color3.fromRGB(86, 130, 70)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	-- ป้ายลอยเหนือคอก บอกว่าใครเป็นเจ้าของ
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OwnerTag"
	billboard.Size = UDim2.fromScale(12, 2)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = base

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = `คอก {index} — {EMPTY_LABEL}`
	label.Parent = billboard

	----------------------------------------------------------------------------
	-- ที่วางแม่ — ครึ่งหน้าของคอก
	----------------------------------------------------------------------------
	-- สร้างไว้เท่าความจุสูงสุด แล้วซ่อนตัวที่เกินเลเวลปัจจุบัน
	-- (ถูกกว่าการสร้าง/ลบ Part ทุกครั้งที่อัปเกรด)
	local standsFolder = Instance.new("Folder")
	standsFolder.Name = "MotherStands"
	standsFolder.Parent = model

	local motherStands: { Part } = {}
	local standColumns = 5
	local standSpacingX = WORLD.PEN_SIZE.X / (standColumns + 1)

	for slot = 1, MAX_PEN_CAPACITY do
		local column = (slot - 1) % standColumns
		local row = math.floor((slot - 1) / standColumns)

		local stand = Instance.new("Part")
		stand.Name = `Stand{slot}`
		stand.Size = STAND_SIZE
		stand.Position = origin
			+ Vector3.new(
				-WORLD.PEN_SIZE.X * 0.5 + standSpacingX * (column + 1),
				WORLD.PEN_SIZE.Y * 0.5 + STAND_SIZE.Y * 0.5,
				-WORLD.PEN_SIZE.Z * 0.5 + 6 + row * 6
			)
		stand.Anchored = true
		stand.Material = Enum.Material.WoodPlanks
		stand.Color = Color3.fromRGB(150, 120, 85)
		stand.TopSurface = Enum.SurfaceType.Smooth
		stand.Parent = standsFolder
		motherStands[slot] = stand
	end

	----------------------------------------------------------------------------
	-- สวนฟัก — ครึ่งหลังของคอก เรียงเป็นตาราง
	----------------------------------------------------------------------------
	local hatchFolder = Instance.new("Folder")
	hatchFolder.Name = "Hatchery"
	hatchFolder.Parent = model

	local hatchPads: { Part } = {}
	local rows = math.ceil(HATCHERY_SLOTS / HATCH_COLUMNS)
	local padSpacingX = WORLD.PEN_SIZE.X / (HATCH_COLUMNS + 1)
	local hatchStartZ = WORLD.PEN_SIZE.Z * 0.5 - 4 - (rows - 1) * 3.5

	for slotIndex = 1, HATCHERY_SLOTS do
		local column = (slotIndex - 1) % HATCH_COLUMNS
		local row = math.floor((slotIndex - 1) / HATCH_COLUMNS)

		local pad = Instance.new("Part")
		pad.Name = `Slot{slotIndex}`
		pad.Size = PAD_SIZE
		pad.Position = origin
			+ Vector3.new(
				-WORLD.PEN_SIZE.X * 0.5 + padSpacingX * (column + 1),
				WORLD.PEN_SIZE.Y * 0.5 + PAD_SIZE.Y * 0.5,
				hatchStartZ + row * 3.5
			)
		pad.Anchored = true
		pad.Material = Enum.Material.Slate
		pad.Color = Color3.fromRGB(120, 110, 100)
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.Parent = hatchFolder
		hatchPads[slotIndex] = pad
	end

	model.PrimaryPart = base
	model.Parent = parent

	local pen: Pen = {
		index = index,
		model = model,
		base = base,
		motherStands = motherStands,
		hatchPads = hatchPads,
		label = label,
		ownerUserId = nil,
	}

	PenService.applyCapacity(pen, Config.getPenCapacity(1))
	return pen
end

-- สร้างคอกทั้งหมด + จุดเกิด เรียกครั้งเดียวตอน server บูต
function PenService.buildWorld()
	if built then
		return
	end
	built = true

	local folder = Instance.new("Folder")
	folder.Name = "Pens"
	folder.Parent = Workspace

	for index = 1, WORLD.MAX_PENS do
		pens[index] = createPen(index, folder)
	end

	-- จุดเกิดผู้เล่น วางไว้หน้าแถวคอก
	-- ถ้าไม่มีอันนี้ผู้เล่นจะเกิดกลางอากาศแล้วตกตลอด เพราะ place ที่ build มาไม่มีพื้น
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PenSpawn"
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.Position = WORLD.PEN_ORIGIN
		+ Vector3.new((WORLD.MAX_PENS - 1) * WORLD.PEN_SPACING * 0.5, 3, WORLD.PEN_SIZE.Z * 0.5 + 20)
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(230, 230, 230)
	spawn.Parent = Workspace
end

--------------------------------------------------------------------------------
-- ความจุคอกตามเลเวล
--------------------------------------------------------------------------------

-- ซ่อนที่วางแม่ที่เกินความจุปัจจุบัน — เรียกตอนอัปเกรดคอก (Phase 2)
function PenService.applyCapacity(pen: Pen, capacity: number)
	for slot, stand in pen.motherStands do
		local usable = slot <= capacity
		stand.Transparency = if usable then 0 else 1
		stand.CanCollide = usable
	end
end

--------------------------------------------------------------------------------
-- แสดงไข่ในสวนฟัก
--------------------------------------------------------------------------------

function PenService.showEgg(player: Player, slotIndex: number, egg: Config.EggType)
	local pad = PenService.getHatchPad(player, slotIndex)
	if not pad then
		return
	end

	local old = pad:FindFirstChild("Egg")
	if old then
		old:Destroy()
	end

	local part = Instance.new("Part")
	part.Name = "Egg"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.Position = pad.Position + Vector3.new(0, 1.6, 0)
	part.Color = egg.color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.Parent = pad
end

function PenService.hideEgg(player: Player, slotIndex: number)
	local pad = PenService.getHatchPad(player, slotIndex)
	if not pad then
		return
	end
	local egg = pad:FindFirstChild("Egg")
	if egg then
		egg:Destroy()
	end
end

--------------------------------------------------------------------------------
-- แสดงแม่ในคอก
--------------------------------------------------------------------------------

local CLASS_COLORS: { [string]: Color3 } = {
	SS = Color3.fromRGB(240, 185, 60),
	S = Color3.fromRGB(190, 110, 235),
	A = Color3.fromRGB(90, 160, 235),
	B = Color3.fromRGB(120, 200, 130),
	C = Color3.fromRGB(200, 200, 195),
}

local function clearStand(stand: Part)
	local existing = stand:FindFirstChild("Mother")
	if existing then
		existing:Destroy()
	end
	local tag = stand:FindFirstChild("MotherTag")
	if tag then
		tag:Destroy()
	end
end

-- วาดแม่ทุกตัวในคอกใหม่ทั้งชุด
-- ⚠️ รับ list มาจาก EggService เพื่อไม่ให้ PenService ต้องรู้เรื่อง state ของผู้เล่น
function PenService.refreshMothers(player: Player, mothers: { any })
	local pen = penByUserId[player.UserId]
	if not pen then
		return
	end

	for slot, stand in pen.motherStands do
		clearStand(stand)

		local mother = mothers[slot]
		if mother then
			local character = Config.getCharacter(mother.charId)
			local class = if character then character.class else "C"

			local body = Instance.new("Part")
			body.Name = "Mother"
			body.Size = Vector3.new(2.4, 2.4, 2.4)
			body.Position = stand.Position + Vector3.new(0, 1.9, 0)
			body.Color = CLASS_COLORS[class] or CLASS_COLORS.C
			body.Material = Enum.Material.SmoothPlastic
			body.Anchored = true
			body.CanCollide = false
			body.Parent = stand

			local billboard = Instance.new("BillboardGui")
			billboard.Name = "MotherTag"
			billboard.Size = UDim2.fromScale(8, 2)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
			billboard.AlwaysOnTop = true
			billboard.Parent = stand

			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.TextScaled = true
			text.TextColor3 = Color3.fromRGB(255, 255, 255)
			text.TextStrokeTransparency = 0.4
			text.Text = `{if character then character.name else mother.charId} ({class})\n{Config.formatWeight(mother.weight)}`
			text.Parent = billboard
		end
	end
end

--------------------------------------------------------------------------------
-- จอง / คืนคอก
--------------------------------------------------------------------------------

local function setOwnerLabel(pen: Pen, text: string)
	pen.label.Text = `คอก {pen.index} — {text}`
end

-- ลบของที่ค้างอยู่บนแท่นทุกช่อง (ใช้ตอนคืนคอก)
function PenService.clearVisuals(pen: Pen)
	for _, pad in pen.hatchPads do
		local egg = pad:FindFirstChild("Egg")
		if egg then
			egg:Destroy()
		end
	end
	for _, stand in pen.motherStands do
		clearStand(stand)
	end
end

-- จองคอกว่างให้ผู้เล่น คืน nil ถ้าเต็ม
function PenService.assign(player: Player): Pen?
	local existing = penByUserId[player.UserId]
	if existing then
		return existing
	end

	for _, pen in pens do
		if pen.ownerUserId == nil then
			pen.ownerUserId = player.UserId
			penByUserId[player.UserId] = pen
			pen.model:SetAttribute("OwnerUserId", player.UserId)
			setOwnerLabel(pen, player.DisplayName)
			return pen
		end
	end

	return nil
end

-- คืนคอกให้คนถัดไป พร้อมล้างของบนแท่น
function PenService.release(player: Player)
	local pen = penByUserId[player.UserId]
	if not pen then
		return
	end

	PenService.clearVisuals(pen)
	PenService.applyCapacity(pen, Config.getPenCapacity(1))
	pen.ownerUserId = nil
	pen.model:SetAttribute("OwnerUserId", nil)
	setOwnerLabel(pen, EMPTY_LABEL)
	penByUserId[player.UserId] = nil
end

function PenService.getPen(player: Player): Pen?
	return penByUserId[player.UserId]
end

-- คืนแท่นฟักของช่องที่ระบุ คืน nil ถ้าผู้เล่นยังไม่มีคอก หรือ slotIndex เกินช่วง
function PenService.getHatchPad(player: Player, slotIndex: number): Part?
	local pen = penByUserId[player.UserId]
	if not pen then
		return nil
	end
	return pen.hatchPads[slotIndex]
end

function PenService.getFreeCount(): number
	local free = 0
	for _, pen in pens do
		if pen.ownerUserId == nil then
			free += 1
		end
	end
	return free
end

return PenService
