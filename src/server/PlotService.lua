--!strict
-- egg-army-game :: ระบบจอง farm plot
--
-- หน้าที่: สร้างพื้นที่ฟาร์มในโลก แล้วจองให้ผู้เล่นคนละ 1 ช่อง
-- ผู้เล่นออก → คืน plot ให้คนถัดไปใช้ต่อ
--
-- Phase 1: plot เป็นแค่แผ่นพื้นกับแท่นวางไข่ ยังไม่มีของตกแต่ง (Phase 5 ค่อย polish)
-- ตัวโลกทั้งหมดสร้างด้วยโค้ด เพราะ place ที่ build จาก Rojo ไม่มี Baseplate มาให้

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local PlotService = {}

export type Plot = {
	index: number, -- เลข plot 1..MAX_PLOTS
	model: Model, -- Model ที่รวมทุกอย่างของ plot นี้
	base: Part, -- แผ่นพื้น
	pads: { Part }, -- แท่นวางไข่ เรียงตาม slotIndex 1..EGG_SLOTS_PER_PLAYER
	label: TextLabel, -- ป้ายบอกเจ้าของ (ไว้ดูตอนเทสต์)
	ownerUserId: number?, -- nil = ว่าง
}

local FARM = Config.Farm

local plots: { Plot } = {}
local plotByUserId: { [number]: Plot } = {}
local built = false

local EMPTY_LABEL = "ว่าง"
local PAD_SIZE = Vector3.new(6, 1, 6)

--------------------------------------------------------------------------------
-- สร้างโลก
--------------------------------------------------------------------------------

local function createPlot(index: number, parent: Folder): Plot
	-- plot เรียงกันเป็นแถวตามแกน X
	local origin = FARM.PLOT_ORIGIN + Vector3.new((index - 1) * FARM.PLOT_SPACING, 0, 0)

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = FARM.PLOT_SIZE
	base.Position = origin
	base.Anchored = true
	base.Material = Enum.Material.Grass
	base.Color = Color3.fromRGB(86, 130, 70)
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	-- ป้ายลอยเหนือ plot บอกว่าใครเป็นเจ้าของ
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OwnerTag"
	billboard.Size = UDim2.fromScale(12, 2)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = base

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = `Plot {index} — {EMPTY_LABEL}`
	label.Parent = billboard

	-- แท่นวางไข่ เรียงเป็นแถวตามแกน Z บนแผ่นพื้น
	local slotsFolder = Instance.new("Folder")
	slotsFolder.Name = "Slots"
	slotsFolder.Parent = model

	local slotCount = FARM.EGG_SLOTS_PER_PLAYER
	local spacing = FARM.PLOT_SIZE.Z / (slotCount + 1)
	local pads: { Part } = {}

	for slotIndex = 1, slotCount do
		local pad = Instance.new("Part")
		pad.Name = `Slot{slotIndex}`
		pad.Size = PAD_SIZE
		pad.Position = origin
			+ Vector3.new(0, FARM.PLOT_SIZE.Y * 0.5 + PAD_SIZE.Y * 0.5, -FARM.PLOT_SIZE.Z * 0.5 + spacing * slotIndex)
		pad.Anchored = true
		pad.Material = Enum.Material.Slate
		pad.Color = Color3.fromRGB(120, 110, 100)
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.Parent = slotsFolder
		pads[slotIndex] = pad
	end

	model.PrimaryPart = base
	model.Parent = parent

	return {
		index = index,
		model = model,
		base = base,
		pads = pads,
		label = label,
		ownerUserId = nil,
	}
end

-- สร้างฟาร์มทั้งหมด + จุดเกิด เรียกครั้งเดียวตอน server บูต
function PlotService.buildWorld()
	if built then
		return
	end
	built = true

	local farms = Instance.new("Folder")
	farms.Name = "Farms"
	farms.Parent = Workspace

	for index = 1, FARM.MAX_PLOTS do
		plots[index] = createPlot(index, farms)
	end

	-- จุดเกิดผู้เล่น วางไว้หน้าแถว plot
	-- ถ้าไม่มีอันนี้ผู้เล่นจะเกิดกลางอากาศแล้วตกตลอด เพราะ place ที่ build มาไม่มีพื้น
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "FarmSpawn"
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.Position = FARM.PLOT_ORIGIN
		+ Vector3.new((FARM.MAX_PLOTS - 1) * FARM.PLOT_SPACING * 0.5, 3, FARM.PLOT_SIZE.Z * 0.5 + 16)
	spawn.Anchored = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(230, 230, 230)
	spawn.Parent = Workspace
end

--------------------------------------------------------------------------------
-- จอง / คืน plot
--------------------------------------------------------------------------------

local function setOwnerLabel(plot: Plot, text: string)
	plot.label.Text = `Plot {plot.index} — {text}`
end

-- ลบก้อนไข่ที่ค้างอยู่บนแท่นทุกช่อง (ใช้ตอนคืน plot)
function PlotService.clearVisuals(plot: Plot)
	for _, pad in plot.pads do
		local egg = pad:FindFirstChild("Egg")
		if egg then
			egg:Destroy()
		end
	end
end

-- จอง plot ว่างให้ผู้เล่น คืน nil ถ้าเต็ม
function PlotService.assign(player: Player): Plot?
	local existing = plotByUserId[player.UserId]
	if existing then
		return existing
	end

	for _, plot in plots do
		if plot.ownerUserId == nil then
			plot.ownerUserId = player.UserId
			plotByUserId[player.UserId] = plot
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			setOwnerLabel(plot, player.DisplayName)
			return plot
		end
	end

	return nil
end

-- คืน plot ให้คนถัดไป พร้อมล้างของบนแท่น
function PlotService.release(player: Player)
	local plot = plotByUserId[player.UserId]
	if not plot then
		return
	end

	PlotService.clearVisuals(plot)
	plot.ownerUserId = nil
	plot.model:SetAttribute("OwnerUserId", nil)
	setOwnerLabel(plot, EMPTY_LABEL)
	plotByUserId[player.UserId] = nil
end

function PlotService.getPlot(player: Player): Plot?
	return plotByUserId[player.UserId]
end

-- คืนแท่นวางไข่ของช่องที่ระบุ คืน nil ถ้าผู้เล่นยังไม่มี plot หรือ slotIndex เกินช่วง
function PlotService.getPad(player: Player, slotIndex: number): Part?
	local plot = plotByUserId[player.UserId]
	if not plot then
		return nil
	end
	return plot.pads[slotIndex]
end

function PlotService.getFreeCount(): number
	local free = 0
	for _, plot in plots do
		if plot.ownerUserId == nil then
			free += 1
		end
	end
	return free
end

return PlotService
