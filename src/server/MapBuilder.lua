--!strict
-- egg-army-game :: สร้างแมพทั้งใบด้วยโค้ด (blockout)
--
-- ⚠️ **แมพต้องสร้างจากสคริปต์เท่านั้น ห้ามปั้นโมเดลใน Studio แล้ว export**
-- Rojo sync ได้แค่ไฟล์สคริปต์ ของที่ปั้นมือจะไปอยู่ในไฟล์ .rbxl ซึ่งแก้ผ่าน repo ไม่ได้
-- และปรับตัวเลขทีต้องปั้นใหม่ทุกครั้ง — ตรงนี้แก้ Config แล้ว generate ใหม่ได้ทันที
--
-- ⚠️ **ทุกพิกัดมาจาก Config.Map / Config.get*() ห้าม hardcode ตัวเลขในไฟล์นี้**
-- ยกเว้นค่าที่เป็น "หน้าตา" ล้วน ๆ (สี · ความหนาเส้น) ซึ่งไม่กระทบกติกาเกม
--
-- ══ สิ่งที่ไฟล์นี้สร้าง (server · ทุกคนเห็นเหมือนกัน) ══
--   ลานคอก   — 6 แปลง 2 แถว หันหน้าเข้าหากัน + ทางเดินกลาง
--   เลนรบ    — เลนเดียวใช้ร่วมกัน ทอดยาวผ่าน 9 ด่าน + แท่นปล่อยทหารที่ต้นเลน
--   รังบอส   — 1 รังต่อด่าน อยู่หลังกำแพงของด่านนั้น พร้อมจุดวางไข่ 5 จุด
--   ร้านค้า  — อาคารฉาก + แท่นวาป (ของจริงคือ UI)
--
-- ══ สิ่งที่ไฟล์นี้ **ไม่** สร้าง ══
--   กำแพง · ทหารฝ่ายรับ · กองทัพของผู้เล่น → **วาดฝั่ง client** (src/client/WallRenderer.lua)
--   เพราะแต่ละคนพังกำแพงคนละด่านแต่ยืนบนเลนเดียวกัน ถ้าสร้างบน server จะแยกกันไม่ได้
--   บอสกับไข่ในรัง → เป็นของจริงบน server แต่เป็นงาน Phase 5 (ตรงนี้ทำแค่ที่วาง)
--
-- Phase blockout: หน้าตากล่อง ๆ ขอแค่รูปร่างพื้นที่ชัดและปรับตัวเลขแล้วขยับตามได้

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local MAP = Config.Map

--------------------------------------------------------------------------------
-- สี (หน้าตาล้วน ๆ ไม่กระทบกติกา)
--------------------------------------------------------------------------------

local COLORS = {
	penFloor = Color3.fromRGB(118, 154, 92),
	penFloorAlt = Color3.fromRGB(104, 140, 82),
	fence = Color3.fromRGB(142, 106, 68),
	walkway = Color3.fromRGB(196, 184, 158),
	lane = Color3.fromRGB(168, 150, 120),
	laneEdge = Color3.fromRGB(120, 104, 80),
	releasePad = Color3.fromRGB(92, 150, 214),
	nest = Color3.fromRGB(150, 124, 96),
	nestEgg = Color3.fromRGB(226, 214, 186),
	shopFloor = Color3.fromRGB(180, 168, 150),
	shopWall = Color3.fromRGB(148, 116, 86),
	teleport = Color3.fromRGB(206, 148, 72),
	marker = Color3.fromRGB(90, 78, 62),
}

--------------------------------------------------------------------------------
-- ตัวช่วยสร้าง Part
--------------------------------------------------------------------------------

-- Part แบบ anchored ทุกตัวในแมพนี้ ไม่มีอะไรตกได้
local function makePart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	-- position ที่รับเข้ามาคือ "จุดบนพื้น" จึงยกขึ้นครึ่งความสูงเอง
	part.Position = Vector3.new(position.X, position.Y + size.Y / 2, position.Z)
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function makeLabel(text: string, size: Vector2, adornee: BasePart, heightOffset: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, heightOffset, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 400
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Text = text
	label.Parent = gui
	return label
end

--------------------------------------------------------------------------------
-- สถานะ
--------------------------------------------------------------------------------

export type PenPlot = {
	index: number,
	model: Model,
	base: Part, -- แผ่นพื้น ใช้หาขอบเขตที่แม่เดินได้
	center: Vector3, -- จุดบนพื้น กึ่งกลางแปลง
	label: TextLabel, -- ป้ายบอกเจ้าของ
}

export type BossNest = {
	stage: number,
	model: Model,
	center: Vector3,
	eggSpots: { Part }, -- จุดวางไข่ เรียง 1..Boss.EGGS_PER_SPAWN
}

local root: Folder? = nil
local penPlots: { PenPlot } = {}
local bossNests: { BossNest } = {}
local releasePad: Part? = nil
local built = false

--------------------------------------------------------------------------------
-- โซน 1 — ลานคอก
--------------------------------------------------------------------------------

-- รั้วรอบแปลง 4 ด้าน ทำให้เห็นชัดว่าคอกใครถึงไหน
local function buildFence(plot: Model, center: Vector3, size: Vector3)
	local map = MAP
	local h = map.FENCE_HEIGHT
	local t = map.FENCE_THICKNESS

	local sides = {
		{ name = "FenceNorth", size = Vector3.new(size.X, h, t), offset = Vector3.new(0, 0, size.Z / 2) },
		{ name = "FenceSouth", size = Vector3.new(size.X, h, t), offset = Vector3.new(0, 0, -size.Z / 2) },
		{ name = "FenceEast", size = Vector3.new(t, h, size.Z), offset = Vector3.new(size.X / 2, 0, 0) },
		{ name = "FenceWest", size = Vector3.new(t, h, size.Z), offset = Vector3.new(-size.X / 2, 0, 0) },
	}
	for _, side in sides do
		local part = makePart(side.name, side.size, center + side.offset, COLORS.fence, plot)
		part.CanCollide = true
	end
end

function MapBuilder.buildPenYard(parent: Folder)
	local map = MAP
	local yard = Instance.new("Folder")
	yard.Name = "PenYard"
	yard.Parent = parent

	for index = 1, Config.World.MAX_PENS do
		local center = Config.getPenPlotCenter(index)
		local size = map.PEN_PLOT_SIZE

		local model = Instance.new("Model")
		model.Name = `Plot{index}`
		model.Parent = yard

		-- ⚠️ พื้นเปิดโล่ง **ไม่แบ่งเป็นช่องตาราง** แม่เดินอิสระ ไข่วางตรงไหนก็ได้
		local shade = if index % 2 == 0 then COLORS.penFloorAlt else COLORS.penFloor
		local base = makePart("Base", size, center, shade, model)
		model.PrimaryPart = base

		buildFence(model, center, size)

		local label = makeLabel(`คอก {index}`, Vector2.new(180, 44), base, size.Y / 2 + 6)

		penPlots[index] = {
			index = index,
			model = model,
			base = base,
			center = center,
			label = label,
		}
	end

	-- ทางเดินกลาง เชื่อมร้านค้า (ซ้าย) กับต้นเลนรบ (ขวา)
	local walkLength = Config.getPenYardWidth() + map.SHOP_GAP * 2 + map.LANE_START_GAP * 2
	makePart(
		"Walkway",
		Vector3.new(walkLength, 1, map.WALKWAY_WIDTH),
		Vector3.new(0, 0, 0),
		COLORS.walkway,
		yard
	)
end

--------------------------------------------------------------------------------
-- โซน 2 — เลนรบ
--------------------------------------------------------------------------------

function MapBuilder.buildBattleLane(parent: Folder)
	local map = MAP
	local lane = Instance.new("Folder")
	lane.Name = "BattleLane"
	lane.Parent = parent

	local startX = Config.getLaneStartX()
	local length = Config.getLaneLength()

	-- ⚠️ เลนเดียว ทุกคนใช้ร่วมกัน — กำแพงของแต่ละคนอยู่คนละด่านแต่ยืนบนเลนนี้เหมือนกัน
	makePart(
		"LaneFloor",
		Vector3.new(length, 1, map.LANE_WIDTH),
		Vector3.new(startX + length / 2, 0, 0),
		COLORS.lane,
		lane
	)

	-- ขอบเลนสองข้าง กันเดินหลุดออกนอกเลน
	for _, sign in { 1, -1 } do
		local edge = makePart(
			if sign == 1 then "LaneEdgeNorth" else "LaneEdgeSouth",
			Vector3.new(length, map.FENCE_HEIGHT, map.FENCE_THICKNESS),
			Vector3.new(startX + length / 2, 0, sign * map.LANE_WIDTH / 2),
			COLORS.laneEdge,
			lane
		)
		edge.CanCollide = true
	end

	-- ⚠️ แท่นปล่อยทหารอยู่ที่ต้นเลน — ทหารโผล่ที่นี่เลย ไม่ต้องเดินมาจากคอก
	local pad = makePart(
		"ReleasePad",
		map.RELEASE_PAD_SIZE,
		Vector3.new(startX + map.RELEASE_PAD_SIZE.X / 2, 1, 0),
		COLORS.releasePad,
		lane
	)
	makeLabel("จุดปล่อยทหาร", Vector2.new(200, 44), pad, map.RELEASE_PAD_SIZE.Y / 2 + 5)
	releasePad = pad

	-- เส้นบอกรอยต่อของด่าน วางบนพื้นเพื่อให้เห็นว่าด่านไหนถึงไหน
	-- ⚠️ เป็น**เครื่องหมายเฉย ๆ ไม่ใช่กำแพง** กำแพงจริงวาดฝั่ง client
	local markers = Instance.new("Folder")
	markers.Name = "StageMarkers"
	markers.Parent = lane

	for stage = 1, Config.Stage.COUNT do
		local marker = makePart(
			`StageMarker{stage}`,
			Vector3.new(1, 0.2, map.LANE_WIDTH),
			Vector3.new(Config.getStageStartX(stage), 1, 0),
			COLORS.marker,
			markers
		)
		marker.CanCollide = false
		makeLabel(`ด่าน {stage}`, Vector2.new(140, 36), marker, 4)
	end
end

--------------------------------------------------------------------------------
-- โซน 3 — รังบอส
--------------------------------------------------------------------------------

function MapBuilder.buildBossNests(parent: Folder)
	local map = MAP
	local nests = Instance.new("Folder")
	nests.Name = "BossNests"
	nests.Parent = parent

	for stage = 1, Config.Stage.COUNT do
		local center = Config.getBossNestCenter(stage)

		local model = Instance.new("Model")
		model.Name = `Nest{stage}`
		model.Parent = nests

		local base = makePart("Base", map.NEST_SIZE, center, COLORS.nest, model)
		model.PrimaryPart = base

		-- ด่าน 1 ไม่มีกำแพง → เข้าได้ตั้งแต่เข้าเกมครั้งแรก บอกไว้บนป้ายเลย
		local gated = if Config.getWallX(stage) then "หลังกำแพง" else "เข้าได้เลย"
		makeLabel(`รังบอสด่าน {stage} · {gated}`, Vector2.new(230, 44), base, map.NEST_SIZE.Y / 2 + 7)

		local spots: { Part } = {}
		for i = 1, Config.Boss.EGGS_PER_SPAWN do
			local spot = makePart(
				`EggSpot{i}`,
				map.NEST_EGG_PAD_SIZE,
				Config.getBossEggSpot(stage, i),
				COLORS.nestEgg,
				model
			)
			spot.CanCollide = false
			spots[i] = spot
		end

		bossNests[stage] = { stage = stage, model = model, center = center, eggSpots = spots }
	end
end

--------------------------------------------------------------------------------
-- โซน 4 — ร้านค้า
--------------------------------------------------------------------------------

function MapBuilder.buildShop(parent: Folder)
	local map = MAP
	local shop = Instance.new("Folder")
	shop.Name = "Shop"
	shop.Parent = parent

	local center = Config.getShopCenter()
	local size = map.SHOP_SIZE

	local floor = makePart("Floor", size, center, COLORS.shopFloor, shop)

	-- ผนังสามด้าน เปิดด้านที่หันเข้าลานคอก (+X) ให้เดินเข้าได้
	local h = map.SHOP_WALL_HEIGHT
	local t = map.FENCE_THICKNESS * 4
	local walls = {
		{ name = "WallWest", size = Vector3.new(t, h, size.Z), offset = Vector3.new(-size.X / 2, 0, 0) },
		{ name = "WallNorth", size = Vector3.new(size.X, h, t), offset = Vector3.new(0, 0, size.Z / 2) },
		{ name = "WallSouth", size = Vector3.new(size.X, h, t), offset = Vector3.new(0, 0, -size.Z / 2) },
	}
	for _, wall in walls do
		local part = makePart(wall.name, wall.size, center + wall.offset, COLORS.shopWall, shop)
		part.CanCollide = true
	end

	makeLabel("ร้านค้า · ขายของ / ซื้อไข่ / ซื้ออาวุธ", Vector2.new(280, 44), floor, h + 2)

	-- ⚠️ แท่นวาปสองอัน: อันหนึ่งที่ร้าน อีกอันกลางทางเดิน
	-- **อัปเกรดไม่ต้องเดินมาที่นี่** — มีปุ่มติดตัวเปิดได้ทุกที่
	-- (ตัวคูณ damage มี 72 ขั้น ถ้าต้องเดินทุกครั้งจะน่ารำคาญมาก)
	local shopPad = makePart(
		"TeleportPadShop",
		map.TELEPORT_PAD_SIZE,
		Vector3.new(center.X + size.X / 2 - map.TELEPORT_PAD_SIZE.X, 1, 0),
		COLORS.teleport,
		shop
	)
	shopPad.CanCollide = false
	makeLabel("วาปกลับลานคอก", Vector2.new(190, 36), shopPad, 4)

	local yardPad = makePart(
		"TeleportPadYard",
		map.TELEPORT_PAD_SIZE,
		Vector3.new(-Config.getPenYardRightX() - map.TELEPORT_PAD_SIZE.X, 1, 0),
		COLORS.teleport,
		parent
	)
	yardPad.CanCollide = false
	makeLabel("วาปไปร้านค้า", Vector2.new(190, 36), yardPad, 4)
end

--------------------------------------------------------------------------------
-- ประกอบทั้งแมพ
--------------------------------------------------------------------------------

function MapBuilder.build()
	if built then
		return
	end
	built = true

	local folder = Instance.new("Folder")
	folder.Name = "Map"
	folder.Parent = Workspace
	root = folder

	MapBuilder.buildShop(folder)
	MapBuilder.buildPenYard(folder)
	MapBuilder.buildBattleLane(folder)
	MapBuilder.buildBossNests(folder)

	-- จุดเกิด กลางทางเดิน ให้เห็นทั้งร้าน (ซ้าย) และเลนรบ (ขวา) ตั้งแต่วินาทีแรก
	local spawnPoint = Config.getSpawnPoint()
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(spawnPoint.X, spawnPoint.Y + 1.5, spawnPoint.Z)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Color = Color3.fromRGB(230, 200, 120)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder

	print(
		`[MapBuilder] สร้างแมพแล้ว — คอก {Config.World.MAX_PENS} แปลง · `
			.. `เลนยาว {Config.getLaneLength()} studs · รังบอส {Config.Stage.COUNT} รัง`
	)
end

--------------------------------------------------------------------------------
-- ให้โมดูลอื่นอ้างถึงของในแมพ (ไม่ต้องคำนวณพิกัดเอง)
--------------------------------------------------------------------------------

function MapBuilder.getPenPlot(index: number): PenPlot?
	return penPlots[index]
end

function MapBuilder.getBossNest(stage: number): BossNest?
	return bossNests[stage]
end

function MapBuilder.getReleasePad(): Part?
	return releasePad
end

function MapBuilder.getRoot(): Folder?
	return root
end

return MapBuilder
