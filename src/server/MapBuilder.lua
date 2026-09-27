--!strict
-- egg-army-game :: สร้างแมพทั้งใบด้วยโค้ด (blockout)
--
-- ⚠️ **แมพต้องสร้างจากสคริปต์เท่านั้น ห้ามปั้นโมเดลใน Studio แล้ว export**
-- Rojo sync ได้แค่ไฟล์สคริปต์ ของที่ปั้นมือจะไปอยู่ในไฟล์ .rbxl ซึ่งแก้ผ่าน repo ไม่ได้
-- และปรับตัวเลขทีต้องปั้นใหม่ทุกครั้ง — ตรงนี้แก้ Config แล้ว generate ใหม่ได้ทันที
--
-- ⚠️ **ทุกพิกัดมาจาก Config.MapDimensions ผ่าน Config.get*() ห้าม hardcode ตัวเลขในไฟล์นี้**
-- ยกเว้นค่าที่เป็น "หน้าตา" ล้วน ๆ (สี · วัสดุ) ซึ่งไม่กระทบกติกาเกมหรือการชน
--
-- ══ รูปทรง ══
--   ลานหญ้าเปิดโล่งบนแท่นลอย **ไม่มีกำแพงล้อมรอบแมพ**
--   มีกำแพงสองข้างทางเฉพาะใน **เลนรบ** ที่เดียว
--   ขอบแมพกันตกด้วย **กำแพงหิน** (Material = Rock, Transparency = 0, CanCollide = true)
--
--   ร้านค้า (แผงเล็ก 2 จุด) → ลานคอก 6 แปลง 2×3 → เลนรบ 9 ด่าน
--
-- ══ สิ่งที่ไฟล์นี้สร้าง (server · ทุกคนเห็นเหมือนกัน) ══
--   ลานหญ้า + คอก 6 แปลงพร้อมรั้วไม้เตี้ย · แผงร้านค้า · เลนรบพร้อมกำแพงสองข้าง
--   ห้องบอส 1 ห้องต่อด่าน พร้อมจุดวางไข่ · กำแพงใสกันตกขอบแมพ
--   ป้ายอัปเกรดบนแมพ (UI-2) — **ตัวป้ายเปล่า ๆ** ข้อความ + จุดกด E ติดฝั่ง client (src/client/MapSigns.lua)
--
-- ══ สิ่งที่ไฟล์นี้ **ไม่** สร้าง ══
--   กำแพงกั้นด่าน · ทหารฝ่ายรับ · กองทัพผู้เล่น → **วาดฝั่ง client**
--   บอกับไข่ในรัง → ของจริงบน server แต่เป็นงาน Phase 5 (ตรงนี้ทำแค่ที่วาง)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local MAP = Config.MapDimensions
local DIM = Config.MapDimensions

--------------------------------------------------------------------------------
-- หน้าตา (ไม่กระทบกติกา)
--------------------------------------------------------------------------------

local COLORS = {
	grass = Color3.fromRGB(116, 158, 88),
	grassAlt = Color3.fromRGB(104, 146, 78),
	fence = Color3.fromRGB(146, 104, 62),
	lane = Color3.fromRGB(176, 158, 126),
	laneWall = Color3.fromRGB(122, 116, 106),
	pedestalBase = Color3.fromRGB(92, 96, 110), -- หินเทาอมฟ้า
	pedestalGlow = Color3.fromRGB(120, 200, 255), -- แกนเรืองแสง + แสง + อนุภาค
	bossFloor = Color3.fromRGB(150, 122, 94),
	bossEgg = Color3.fromRGB(230, 218, 190),
	stall = Color3.fromRGB(158, 112, 76),
	stallRoof = Color3.fromRGB(190, 92, 78),
	marker = Color3.fromRGB(86, 74, 58),
	spawn = Color3.fromRGB(230, 200, 120),
	sign = Color3.fromRGB(196, 158, 112),
	boundary = Color3.fromRGB(118, 112, 104), -- หินเทาอมน้ำตาล ให้ธีมใกล้เคียง WALL_COLOR ใน WallRenderer.lua
	-- ⚠️ UI-fix รอบ 1: สีตกแต่งผิวกำแพงขอบแมพ (ดู decorateBoundaryWall) — หน้าตาล้วน ๆ ไม่กระทบขนาด/การชน
	boundaryDamp = Color3.fromRGB(80, 76, 70), -- แถบคราบชื้นเข้มด้านล่างกำแพง
	moss = Color3.fromRGB(90, 118, 62), -- หย่อมมอส/เถาวัลย์
}

local FLOOR_THICKNESS = 2

--------------------------------------------------------------------------------
-- ตัวช่วยสร้าง Part
--------------------------------------------------------------------------------

-- position = "จุดบนพื้น" ฟังก์ชันยกขึ้นครึ่งความสูงให้เอง · anchored ทุกตัว
local function makePart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = Vector3.new(position.X, position.Y + size.Y / 2, position.Z)
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

-- แผ่นพื้น: ห้อยลงใต้ Y=0 เพื่อให้ผิวบนอยู่ที่ 0 พอดี ของที่วางบนพื้นจะได้ไม่ลอย
local function makeFloor(name: string, sizeX: number, sizeZ: number, centerX: number, centerZ: number, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(sizeX, FLOOR_THICKNESS, sizeZ)
	part.Position = Vector3.new(centerX, -FLOOR_THICKNESS / 2, centerZ)
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.Grass
	part.Parent = parent
	return part
end

local function makeLabel(text: string, width: number, adornee: BasePart, heightOffset: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(width, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, heightOffset, 0)
	gui.MaxDistance = 500
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
	base: Part,
	center: Vector3,
	label: TextLabel,
}

export type BossRoom = {
	stage: number,
	model: Model,
	center: Vector3,
	eggSpots: { Part },
}

local root: Folder? = nil
local penPlots: { PenPlot } = {}
local bossRooms: { BossRoom } = {}
local spawnPads: { SpawnLocation } = {}
local built = false

--------------------------------------------------------------------------------
-- โซน 1 — ลานหญ้า + คอก
--------------------------------------------------------------------------------

-- ══ รั้วไม้เตี้ยรอบแปลง ══ **แค่บอกขอบเขต ไม่ใช่กำแพงกันทาง**
--
-- ⚠️ `CanCollide = false` ทุกชิ้น — ผู้เล่นและแม่เดินทะลุได้
-- รั้วไม่ได้ทำหน้าที่กันอะไรเลย จึงไม่อยู่ใต้กฎความหนา-ความเร็ว (ดู Config.validate)
-- **แม่ยังเดินอยู่แค่ในคอกเหมือนเดิม** เพราะขอบเขตสุ่มเดินอ่านจากพิกัดคอก ไม่ได้อ่านจากรั้ว
--
-- รูปทรง: เสาเล็ก ๆ ทุก FENCE_POST_SPACING + คานแนวนอน FENCE_RAIL_COUNT ชั้น
-- (แบบรั้วไม้ฟาร์มปกติ ไม่ใช่แท่งทึบยาวชิ้นเดียว)

local function fencePart(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local part = makePart(name, size, position, COLORS.fence, parent)
	part.Material = Enum.Material.Wood
	part.CanCollide = false -- ⚠️ ทะลุได้ตั้งใจ
	part.CastShadow = false
	return part
end

-- รั้วหนึ่งช่วง: เสา + คาน ทอดจาก `from` ถึง `to` ตามแกนที่เลือก
-- alongX = true → ทอดตามแกน X ที่ Z คงที่ · false → ทอดตามแกน Z ที่ X คงที่
local function fenceRun(
	parent: Instance,
	name: string,
	from: number,
	to: number,
	fixed: number,
	alongX: boolean
)
	local length = to - from
	if length <= 0 then
		return
	end

	local h = MAP.Pen.FenceHeight
	local t = MAP.Pen.FenceThickness

	local function place(partName: string, along: number, thick: number, height: number, y: number)
		local size = if alongX
			then Vector3.new(along, height, thick)
			else Vector3.new(thick, height, along)
		local center = (from + to) / 2
		local position = if alongX then Vector3.new(center, y, fixed) else Vector3.new(fixed, y, center)
		fencePart(parent, partName, size, position)
	end

	-- คานแนวนอน — ไล่ความสูงเท่า ๆ กันจากบนลงล่าง ไม่ติดพื้น
	local rails = MAP.Pen.FenceRailCount
	local railHeight = h / (rails * 2 + 1)
	for rail = 1, rails do
		local y = h * (rail / (rails + 1)) - railHeight / 2
		place(`{name}Rail{rail}`, length, t * 0.6, railHeight, y)
	end

	-- เสา — หัวท้ายเสมอ แล้วแทรกตาม FENCE_POST_SPACING
	local spans = math.max(1, math.floor(length / MAP.Pen.FencePostSpacing))
	for post = 0, spans do
		local offset = from + length * (post / spans)
		local size = Vector3.new(t, h, t)
		local position = if alongX then Vector3.new(offset, 0, fixed) else Vector3.new(fixed, 0, offset)
		fencePart(parent, `{name}Post{post}`, size, position)
	end
end

-- รั้วครบสี่ด้านของแปลง · ด้านที่หันเข้าทางเดินกลางเว้นช่องประตูไว้ตรงกลาง
local function buildFence(plot: Model, index: number, center: Vector3, sizeX: number, sizeZ: number)
	local halfX, halfZ = sizeX / 2, sizeZ / 2
	local left, right = center.X - halfX, center.X + halfX
	local back, front = center.Z - halfZ, center.Z + halfZ

	-- ประตูหันเข้าทางเดินกลาง: แถวบน (Z > 0) หันลง · แถวล่าง (Z < 0) หันขึ้น
	-- ⚠️ แนวประตูมาจาก Config.getPenGateLine — ป้ายชื่อ/ป้ายอัปเกรด (UI-2) อ่านค่าเดียวกัน
	local gateZ = Config.getPenGateLine(index)
	local farZ = if center.Z > 0 then front else back

	-- ด้านตรงข้ามประตู + สองด้านข้าง = รั้วเต็มไม่มีช่อง
	fenceRun(plot, "FenceFar", left, right, farZ, true)
	fenceRun(plot, "FenceLeft", back, front, left, false)
	fenceRun(plot, "FenceRight", back, front, right, false)

	-- ด้านประตู: แบ่งเป็นสองช่วง เว้นช่องกลางกว้าง PEN_GATE_WIDTH
	local gateHalf = MAP.Pen.GateWidth / 2
	fenceRun(plot, "FenceGateA", left, center.X - gateHalf, gateZ, true)
	fenceRun(plot, "FenceGateB", center.X + gateHalf, right, gateZ, true)
end

-- ป้ายชื่อคอก — **ปักข้างประตู ไม่ใช่กลางประตู** (กันเดินชน)
-- ปักบนหญ้าด้านนอกคอก ใกล้ประตู · ยกสูงให้อ่านได้จากมุมกล้องผู้เล่นทั่วไป
-- ⚠️ ตำแหน่งมาจาก Config.getPenNameSignSpot — ป้ายอัปเกรดข้างประตู (UI-2) เว้นระยะจากจุดนี้
local function buildPenSign(plot: Model, index: number): TextLabel
	local spot = Config.getPenNameSignSpot(index)
	local signX, signZ = spot.X, spot.Z

	local postHeight = MAP.Pen.SignPostHeight
	local post = fencePart(
		plot,
		`Sign{index}Post`,
		Vector3.new(MAP.Pen.FenceThickness * 1.5, postHeight, MAP.Pen.FenceThickness * 1.5),
		Vector3.new(signX, 0, signZ)
	)
	post.Material = Enum.Material.Wood

	local board = makePart(
		`Sign{index}Board`,
		MAP.Pen.SignSize,
		Vector3.new(signX, postHeight, signZ),
		COLORS.sign,
		plot
	)
	board.Material = Enum.Material.WoodPlanks
	board.CanCollide = false
	board.CastShadow = false

	return makeLabel(`คอก {index}`, 220, board, MAP.Pen.SignSize.Y)
end

function MapBuilder.buildPlaza(parent: Folder)
	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = parent

	-- พื้นหญ้าผืนเดียวคลุมทั้งลาน (รวมแถบแผงร้านทางซ้าย)
	local minX = Config.getPlazaMinX()
	local maxX = Config.getPlazaMaxX()
	local halfDepth = Config.getPlazaHalfDepth()
	makeFloor("GrassFloor", maxX - minX, halfDepth * 2, (minX + maxX) / 2, 0, COLORS.grass, plaza)

	-- ══ พื้นหญ้าปีกฝั่งตะวันออก ══ รองรับกำแพงใสที่ดันออกจากขอบคอก (Config.getEastBoundaryX())
	-- เพื่อไม่ให้รั้วคอกคอลัมน์ขวาสุดซ้อนกับกำแพง (ดู MapBuilder.buildBoundary)
	-- ⚠️ ครอบคลุมเฉพาะช่วง Z ที่อยู่นอกเลนรบ (|Z| > laneHalf) เท่านั้น — ช่วง Z ของเลนเอง
	-- มี LaneFloor ต่อจาก GrassFloor อยู่แล้วที่ X เดิม (getPlazaMaxX) ถ้าพื้นปีกคลุมมาถึง
	-- ตรงนั้นด้วยจะกลายเป็นพื้นสองผืนซ้อนกันที่ Z เดียวกัน = ภาพกระพริบ (z-fighting)
	-- เหมือนบั๊กที่เคยแก้ตรงห้องบอสมาแล้ว
	local eastFloorEndX = Config.getEastFloorEdgeX()
	local eastWingSizeX = eastFloorEndX - maxX
	local eastWingCenterX = (maxX + eastFloorEndX) / 2
	local laneHalf = MAP.Lane.Width / 2
	local eastWingSizeZ = halfDepth - laneHalf
	local eastWingCenterZ = (laneHalf + halfDepth) / 2
	makeFloor("EastWingUpper", eastWingSizeX, eastWingSizeZ, eastWingCenterX, eastWingCenterZ, COLORS.grass, plaza)
	makeFloor("EastWingLower", eastWingSizeX, eastWingSizeZ, eastWingCenterX, -eastWingCenterZ, COLORS.grass, plaza)

	-- ⚠️ **ไม่มี Part ของทางเดินกลางแล้ว** — ลบทิ้งตอนไล่บั๊กภาพกระพริบ
	-- มันเคยเป็นแถบเทาที่อ่านเป็น "ถนน" แล้วถูกเปลี่ยนเป็นหญ้าให้กลืนกับพื้น
	-- พอสีและวัสดุเหมือนพื้นเป๊ะ มันก็ไม่เหลืออะไรให้ดูอีก — เป็นแค่แผ่นบาง ๆ
	-- วางทาบอยู่บนพื้นหญ้าเฉย ๆ คอยกวนสายตาด้วยการกระพริบ
	-- ความกว้างทางเดิน (`Pen.RowGap`) ยังคุมระยะห่างสองแถวคอกอยู่เหมือนเดิม
	-- เพราะตำแหน่งคอกมาจาก `Config.getPenPlotCenter()` ไม่ได้มาจาก Part นี้

	-- ══ คอก 6 แปลง ══ พื้นในคอกเป็นหญ้าทั้งหมด **ไม่มีแปลงหรือช่องตาราง**
	local pens = Instance.new("Folder")
	pens.Name = "Pens"
	pens.Parent = plaza

	local sizeX = MAP.Pen.Size.X
	local sizeZ = MAP.Pen.Size.Y

	for index = 1, Config.World.MAX_PENS do
		local center = Config.getPenPlotCenter(index)

		local model = Instance.new("Model")
		model.Name = `Plot{index}`
		model.Parent = pens

		-- แผ่นบาง ๆ ทับบนหญ้า ไว้แยกสีให้เห็นว่าคอกไหนเป็นของใคร
		local shade = if index % 2 == 0 then COLORS.grassAlt else COLORS.grass
		local base = makePart("Base", Vector3.new(sizeX, MAP.Pen.FloorThickness, sizeZ), center, shade, model)
		base.Material = Enum.Material.Grass
		base.CanCollide = false
		model.PrimaryPart = base

		buildFence(model, index, center, sizeX, sizeZ)
		local label = buildPenSign(model, index)

		penPlots[index] = { index = index, model = model, base = base, center = center, label = label }
	end
end

--------------------------------------------------------------------------------
-- โซน 2 — ร้านค้า (แผงเล็ก ๆ ที่ขอบลาน ไม่ใช่อาคารใหญ่)
--------------------------------------------------------------------------------

function MapBuilder.buildShop(parent: Folder)
	local shop = Instance.new("Folder")
	shop.Name = "Shop"
	shop.Parent = parent

	local sizeX = MAP.Shop.StallSize.X
	local sizeZ = MAP.Shop.StallSize.Y
	local h = MAP.Shop.StallHeight

	for index = 1, MAP.Shop.StallCount do
		local center = Config.getShopStallCenter(index)

		local model = Instance.new("Model")
		model.Name = `Stall{index}`
		model.Parent = shop

		-- เคาน์เตอร์เตี้ย + หลังคา — เป็นแค่ฉาก ของจริงคือ UI
		local counter = makePart("Counter", Vector3.new(sizeX, h * 0.4, sizeZ), center, COLORS.stall, model)
		counter.Material = Enum.Material.WoodPlanks
		model.PrimaryPart = counter

		local roof = makePart(
			"Roof",
			Vector3.new(sizeX + 2, 0.6, sizeZ + 2),
			Vector3.new(center.X, h, center.Z),
			COLORS.stallRoof,
			model
		)
		roof.CanCollide = false

		-- ⚠️ UI-2: แผง SellStallIndex = ร้านขายแม่ (เดิม "ขายของ · ซื้อไข่" — เงินในเกมซื้อไข่ไม่ได้ จึงเปลี่ยนป้าย)
		-- client ติดจุดกด E ที่ Counter ของแผงนี้ (src/client/MapSigns.lua) → Persistent ให้หาเจอเสมอ
		local isSellShop = index == MAP.MapSign.SellStallIndex
		if isSellShop then
			model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end
		makeLabel(if isSellShop then "ร้านขายแม่" else "ซื้ออาวุธ", 220, counter, h * 0.4 + 3)
	end

	-- ⚠️ **ไม่มีแท่นวาปแล้ว** (เอาออกรอบซื้อความเร็ว)
	-- ผู้เล่นเดินไปเองทุกที่ · ปัญหาระยะทางแก้ด้วย Config.Balance.SpeedUpgrade แทน
	-- และไม่มีแท่นวาปไปรังบอสด้วย — วาปไปรังได้เมื่อไหร่ การแย่งไข่ก็หมดความหมาย
	--
	-- ⚠️ UI-2: อัปเกรด (ดาเมจ · ความเร็ว · คอก) ย้ายจากปุ่มติดตัวไปเป็น**ป้ายบนแมพ กด E** (buildMapSigns)
	-- แผงร้านเหลือ ร้านขายแม่ (แผง SellStallIndex) · ซื้ออาวุธ (Phase 5)
end

--------------------------------------------------------------------------------
-- ป้ายอัปเกรดบนแมพ (UI-2) — แผ่นไม้บนเสา สไตล์เดียวกับป้ายชื่อคอก
--------------------------------------------------------------------------------
-- ⚠️ server สร้าง**แค่ตัวป้าย** (ทุกคนเห็นเหมือนกัน) · ข้อความเลเวล/ราคา + จุดกด E ติดฝั่ง client
-- เพราะแต่ละคนเห็นค่าของตัวเอง และกดได้เฉพาะป้ายของคอกตัวเอง (src/client/MapSigns.lua)
-- ตำแหน่งทั้งหมดมาจาก Config (getDamageSignSpot · getPenUpgradeSignSpot) — client ใช้ชื่อโมเดลชุดเดียวกัน

local function buildMapSign(parent: Instance, name: string, ground: Vector3, facing: Vector3)
	local model = Instance.new("Model")
	model.Name = name
	-- ⚠️ Persistent: client ติด SurfaceGui + ProximityPrompt ไว้กับแผ่นป้าย ถ้าเปิด StreamingEnabled
	-- แล้วป้ายถูก stream ออก ของที่ client ติดไว้จะหายตามไปด้วย
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = parent

	local sign = MAP.MapSign
	local postThickness = MAP.Pen.FenceThickness * 1.5
	local post = fencePart(model, "Post", Vector3.new(postThickness, sign.PostHeight, postThickness), ground)
	post.Material = Enum.Material.Wood

	-- แผ่นป้ายหันหน้าตาม facing: หันตามแกน Z → กว้างตามแกน X · หันตามแกน X → กว้างตามแกน Z
	local size = if math.abs(facing.X) > 0.5
		then Vector3.new(sign.BoardSize.Z, sign.BoardSize.Y, sign.BoardSize.X)
		else sign.BoardSize
	local board = makePart("Board", size, Vector3.new(ground.X, sign.PostHeight, ground.Z), COLORS.sign, model)
	board.Material = Enum.Material.WoodPlanks
	board.CanCollide = false
	board.CastShadow = false
	model.PrimaryPart = board
end

function MapBuilder.buildMapSigns(parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = Config.MAP_SIGN_FOLDER
	folder.Parent = parent

	local damageSpot, damageFacing = Config.getDamageSignSpot()
	buildMapSign(folder, Config.getMapSignName("damage"), damageSpot, damageFacing)

	-- ป้ายค่าวิ่ง + อัปคอก **ทุกคอก** (คอกของคนอื่น client ไม่ติดจุดกด E ให้)
	for index = 1, Config.World.MAX_PENS do
		-- ⚠️ ต้องประกาศชนิดของ kind เอง — ไม่งั้น Luau ขยาย "speed" | "pen" เป็น string แล้วส่งเข้าฟังก์ชันไม่ได้
		local kinds: { Config.PenSignKind } = Config.getPenSignKinds()
		for kindIndex = 1, #kinds do
			local kind: Config.PenSignKind = kinds[kindIndex]
			local spot, facing = Config.getPenUpgradeSignSpot(index, kind)
			buildMapSign(folder, Config.getMapSignName(kind, index), spot, facing)
		end
	end
end

--------------------------------------------------------------------------------
-- โซน 3 — เลนรบ (ที่เดียวในแมพที่มีกำแพงสองข้างทาง)
--------------------------------------------------------------------------------

-- กำแพงข้างเลนหนึ่งชิ้น ยาวตามแกน X ที่ระยะ Z ที่กำหนด
local function laneWallPiece(parent: Folder, name: string, fromX: number, toX: number, z: number)
	local length = toX - fromX
	if length <= 0 then
		return
	end
	local part = makePart(
		name,
		Vector3.new(length, MAP.Lane.WallHeight, MAP.Lane.WallThickness),
		Vector3.new((fromX + toX) / 2, 0, z),
		COLORS.laneWall,
		parent
	)
	part.Material = Enum.Material.Slate
	part.CanCollide = true
end

-- ชิ้นเชื่อมตอนกำแพงเดินเป็นขั้น (ขวางตามแกน Z)
local function laneWallJog(parent: Folder, name: string, x: number, fromZ: number, toZ: number)
	local width = math.abs(toZ - fromZ)
	if width <= 0 then
		return
	end
	local part = makePart(
		name,
		Vector3.new(MAP.Lane.WallThickness, MAP.Lane.WallHeight, width),
		Vector3.new(x, 0, (fromZ + toZ) / 2),
		COLORS.laneWall,
		parent
	)
	part.Material = Enum.Material.Slate
	part.CanCollide = true
end

-- ══ แท่นอัญเชิญ (UI-3) ══ จานหินกลมเรืองแสงกลางปากเลน · ทหาร (ภาพ) โผล่ที่กึ่งกลางแท่นแล้วเดินเข้าเลน
-- ⚠️ ภาพล้วน — การรบไม่อ่านพิกัดแท่น (Config.getSummonPedestalCenter) · CanCollide = false เดินทับได้ ไม่บังทางเข้าเลน
-- ⚠️ Persistent: client ติดจุดกด E (UiKit.prompt · กดค้าง) ที่ชิ้นแกน ถ้าเปิด StreamingEnabled แล้วแท่นถูก
--   stream ออก จุดกดจะหายตามไปด้วย (เหตุผลเดียวกับป้ายบนแมพ)
-- Part ทรงกระบอกของ Roblox วางแกนตาม X → หมุน 90° รอบแกน Z ให้แกนตั้งขึ้น (ขนาด = สูง × กว้าง × กว้าง)
local function makeDisc(name: string, diameter: number, height: number, bottomY: number, color: Color3, parent: Instance): Part
	local center = Config.getSummonPedestalCenter()
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = CFrame.new(center.X, bottomY + height / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildSummonPedestal(parent: Instance)
	local spec = MAP.SummonPedestal
	local center = Config.getSummonPedestalCenter()

	local model = Instance.new("Model")
	model.Name = Config.SUMMON_PEDESTAL_NAME
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = parent

	local base = makeDisc("Base", spec.Diameter, spec.BaseHeight, 0, COLORS.pedestalBase, model)
	base.Material = Enum.Material.Slate

	local core = makeDisc(
		Config.SUMMON_PEDESTAL_CORE,
		spec.CoreDiameter,
		spec.CoreHeight,
		spec.BaseHeight,
		COLORS.pedestalGlow,
		model
	)
	core.Material = Enum.Material.Neon

	local light = Instance.new("PointLight")
	light.Color = COLORS.pedestalGlow
	light.Range = spec.LightRange
	light.Brightness = 2
	light.Parent = core

	-- อนุภาคลอยขึ้นช้า ๆ — ติดกับแผ่นใสไม่หมุน (ด้านบน = ขึ้นฟ้าจริง) แทนแกนที่หมุนไปแล้ว
	local aura = makePart(
		"Aura",
		Vector3.new(spec.CoreDiameter * 0.8, 0.1, spec.CoreDiameter * 0.8),
		Vector3.new(center.X, spec.BaseHeight + spec.CoreHeight, center.Z),
		COLORS.pedestalGlow,
		model
	)
	aura.Transparency = 1
	aura.CanCollide = false
	aura.CanQuery = false
	aura.CanTouch = false

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Rise"
	particles.EmissionDirection = Enum.NormalId.Top
	particles.Color = ColorSequence.new(COLORS.pedestalGlow)
	particles.LightEmission = 1
	particles.Rate = 8
	particles.Lifetime = NumberRange.new(2, 3)
	particles.Speed = NumberRange.new(1.5, 2.5)
	particles.SpreadAngle = Vector2.new(8, 8)
	particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	particles.Parent = aura

	makeLabel("แท่นอัญเชิญ", 220, core, 6)
end

function MapBuilder.buildBattleLane(parent: Folder)
	local lane = Instance.new("Folder")
	lane.Name = "BattleLane"
	lane.Parent = parent

	local startX = Config.getLaneStartX()
	local endX = Config.getLaneEndX()

	-- ══ พื้นเลน ══ **สร้างเป็นช่วง ๆ เว้นตรงห้องบอส**
	--
	-- ⚠️ เดิมเป็นแผ่นเดียวยาวตลอดเลน แล้วพื้นห้องบอส (80 x 80) มาวางทับ
	-- ผิวบนของทั้งสองแผ่นอยู่ที่ Y = 0 เท่ากันเป๊ะ = **ระนาบเดียวกัน 9 จุด รวม 43,200 ตร.studs**
	-- การ์ดจอเลือกไม่ได้ว่าจะวาดแผ่นไหนทับ → ภาพกระพริบสลับไปมาตามมุมกล้อง (z-fighting)
	--
	-- แก้ด้วยการ "ไม่วาดซ้อน" ไม่ใช่ขยับความสูงหนีกัน
	-- ขยับความสูงแปลว่ามีขั้นให้สะดุด และของที่วางบนพื้นจะลอยหรือจม
	-- ห้องบอสกว้างกว่าเลนอยู่แล้ว (80 > 60) ช่วงที่เว้นไว้จึงถูกพื้นห้องบอสคลุมเต็มพอดี
	-- ⚠️ ชื่อ floorCursor ไม่ใช่ cursor เฉย ๆ เพราะตัวสร้างกำแพงข้างล่างมี cursor ของตัวเอง
	local roomHalfSpan = MAP.BossRoom.Size.X / 2
	local floorCursor = startX

	local function laneSegment(fromX: number, toX: number, index: number)
		if toX - fromX <= 0 then
			return
		end
		makeFloor(`LaneFloor{index}`, toX - fromX, MAP.Lane.Width, (fromX + toX) / 2, 0, COLORS.lane, lane)
	end

	for stage = 1, Config.Balance.Stage.COUNT do
		local center = Config.getBossNestCenter(stage)
		laneSegment(floorCursor, center.X - roomHalfSpan, stage)
		floorCursor = math.max(floorCursor, center.X + roomHalfSpan)
	end
	laneSegment(floorCursor, endX, Config.Balance.Stage.COUNT + 1)

	-- ══ กำแพงสองข้างทาง ══ เดินเป็นขั้นตรงห้องบอสที่กว้างกว่าเลน
	local walls = Instance.new("Folder")
	walls.Name = "SideWalls"
	walls.Parent = lane

	local laneHalf = MAP.Lane.Width / 2
	local roomHalfZ = MAP.BossRoom.Size.Y / 2
	local roomHalfX = MAP.BossRoom.Size.X / 2

	-- ⚠️ UI-2: กำแพงข้างเริ่มเสมอกำแพงขอบแมพฝั่งตะวันออก (Config.getLaneWallStartX) ไม่ใช่ต้นเลน —
	-- เดิมยื่นเข้าลานเกินแนวกำแพงขอบแมพทั้งสองฝั่งปากเลน · พื้นเลน/จุดปล่อยทหารยังเริ่มที่ต้นเลนเหมือนเดิม
	-- ⚠️ UI-fix รอบ 1: getLaneWallStartX() ขยับจากผิวด้านใน → ผิวด้านนอกของกำแพงขอบแมพแล้ว
	-- (กันซ้อนทับกำแพงขอบแมพเต็มความหนา = z-fighting ตรงมุมปากเลน — ดูคอมเมนต์ที่ตัวฟังก์ชันใน Config.lua)
	local wallStartX = Config.getLaneWallStartX()
	for _, sign in { 1, -1 } do
		local side = if sign == 1 then "North" else "South"
		local cursor = wallStartX

		for stage = 1, Config.Balance.Stage.COUNT do
			local room = Config.getBossNestCenter(stage)
			local roomStart = room.X - roomHalfX
			local roomEnd = room.X + roomHalfX

			-- ช่วงปกติก่อนถึงห้อง
			laneWallPiece(walls, `Wall{side}_S{stage}_A`, cursor, roomStart, sign * laneHalf)

			if roomHalfZ > laneHalf then
				-- ผายออก: ขั้นเข้า → ยาวตามห้อง → ขั้นกลับ
				laneWallJog(walls, `Jog{side}_S{stage}_In`, roomStart, sign * laneHalf, sign * roomHalfZ)
				laneWallPiece(walls, `Wall{side}_S{stage}_Room`, roomStart, roomEnd, sign * roomHalfZ)
				laneWallJog(walls, `Jog{side}_S{stage}_Out`, roomEnd, sign * roomHalfZ, sign * laneHalf)
			else
				laneWallPiece(walls, `Wall{side}_S{stage}_Room`, roomStart, roomEnd, sign * laneHalf)
			end

			cursor = roomEnd
		end

		-- หางเลนหลังห้องสุดท้าย
		laneWallPiece(walls, `Wall{side}_Tail`, cursor, endX, sign * laneHalf)
	end

	-- ปิดปลายเลน กันเดินตกท้ายแมพ
	local cap = makePart(
		"LaneEndCap",
		Vector3.new(MAP.Lane.WallThickness, MAP.Lane.WallHeight, MAP.Lane.Width),
		Vector3.new(endX, 0, 0),
		COLORS.laneWall,
		lane
	)
	cap.Material = Enum.Material.Slate

	-- ⚠️ UI-3: แท่นอัญเชิญแทนแท่นปล่อยทหารสี่เหลี่ยมเดิม (buildSummonPedestal) · ทหาร (ภาพ) ยังโผล่ที่ปากเลนจุดเดิม
	buildSummonPedestal(parent)

	-- เส้นบอกรอยต่อด่าน — ⚠️ **เครื่องหมายเฉย ๆ ไม่ใช่กำแพง** กำแพงจริงวาดฝั่ง client
	local markers = Instance.new("Folder")
	markers.Name = "StageMarkers"
	markers.Parent = lane

	for stage = 1, Config.Balance.Stage.COUNT do
		local marker = makePart(
			`StageMarker{stage}`,
			Vector3.new(1.5, 0.3, MAP.Lane.Width),
			Vector3.new(Config.getStageStartX(stage), 0, 0),
			COLORS.marker,
			markers
		)
		marker.CanCollide = false
		makeLabel(`ด่าน {stage}`, 160, marker, 6)
	end
end

--------------------------------------------------------------------------------
-- โซน 4 — ห้องบอส (หลังกำแพงของแต่ละด่าน)
--------------------------------------------------------------------------------

function MapBuilder.buildBossRooms(parent: Folder)
	local rooms = Instance.new("Folder")
	rooms.Name = "BossRooms"
	rooms.Parent = parent

	for stage = 1, Config.Balance.Stage.COUNT do
		local center = Config.getBossNestCenter(stage)

		local model = Instance.new("Model")
		model.Name = `Room{stage}`
		model.Parent = rooms

		local base = makeFloor(
			"Floor",
			MAP.BossRoom.Size.X,
			MAP.BossRoom.Size.Y,
			center.X,
			center.Z,
			COLORS.bossFloor,
			model
		)
		base.Material = Enum.Material.Ground
		model.PrimaryPart = base

		-- ด่าน 1 ไม่มีกำแพงกั้น → เดินเข้าได้ตั้งแต่เข้าเกมครั้งแรก
		local gated = if Config.getWallX(stage) then "หลังกำแพง" else "เข้าได้เลย"
		makeLabel(`รังบอสด่าน {stage} · {gated}`, 280, base, 10)

		local spots: { Part } = {}
		for i = 1, Config.Balance.Boss.EGGS_PER_SPAWN do
			local spot = makePart(
				`EggSpot{i}`,
				MAP.BossRoom.EggPadSize,
				Config.getBossEggSpot(stage, i),
				COLORS.bossEgg,
				model
			)
			spot.CanCollide = false
			spots[i] = spot
		end

		bossRooms[stage] = { stage = stage, model = model, center = center, eggSpots = spots }
	end
end

--------------------------------------------------------------------------------
-- โซน 4b — ลานบอสกลาง (Phase 5A) · บอสตัวเดียวของเซิร์ฟ + กำแพงกั้นกลางคืน
--------------------------------------------------------------------------------
-- ⚠️ อยู่ในห้องบอสของด่าน BossArena.Stage (ด่าน 1 — ด่านเดียวที่ไม่มีกำแพง ทุกคนเดินถึง · validate() บังคับ)
-- ที่นี่สร้าง "ของ" อย่างเดียว · เปิด/ปิดกำแพงกั้น · ซ่อน/โชว์บอส · อัปเดตแถบ HP = BossService
-- กำแพงกั้น **ชิ้นเดียวของ server** ชนได้เฉพาะกลางคืน (BossService ตั้ง CanCollide) — ทหารไม่โดนเพราะทหารเป็นภาพ
--   ฝั่ง client (Anchored + CanCollide = false ขยับด้วย PivotTo) และการรบคิดเป็นตัวเลข ไม่มีอะไรในเลนที่ใช้ฟิสิกส์
--   นอกจากตัวผู้เล่น → ใช้ CanCollide ธรรมดาก็ "กันเฉพาะผู้เล่น" แล้ว ไม่ต้องมี CollisionGroup
-- ⚠️ Persistent: client ติดตัวเลขนับถอยหลังไว้ที่ผิวกำแพงกั้น (เหตุผลเดียวกับแท่นอัญเชิญ/ป้ายบนแมพ)
local BOSS_ARENA_COLORS = {
	barrier = Color3.fromRGB(255, 90, 70),
	bossBody = Color3.fromRGB(92, 58, 120),
	bossHead = Color3.fromRGB(120, 76, 150),
	bossEye = Color3.fromRGB(255, 220, 90),
	hpBack = Color3.fromRGB(30, 30, 30),
	hpFill = Color3.fromRGB(215, 60, 60),
}

function MapBuilder.buildBossArena(parent: Folder)
	local arenaDim = MAP.BossArena
	local model = Instance.new("Model")
	model.Name = Config.BOSS_ARENA_NAME
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = parent

	-- กำแพงกั้นกลางคืน — เริ่มแบบกลางวัน (มองไม่เห็น · ไม่ชน) BossService สลับเองตาม phase
	local barrierSize = Config.getBossBarrierSize()
	local barrier = makePart(
		Config.BOSS_BARRIER_NAME,
		barrierSize,
		Vector3.new(Config.getBossBarrierX(), 0, 0),
		BOSS_ARENA_COLORS.barrier,
		model
	)
	barrier.Material = Enum.Material.ForceField
	barrier.Transparency = 1
	barrier.CanCollide = false
	barrier.CanQuery = false
	barrier.CastShadow = false

	-- ตัวบอส (blockout กล่อง ไม่ใช้ Humanoid) — BossService ถอดออกจากโลกตอนไม่มีชีวิต
	local boss = Instance.new("Model")
	boss.Name = Config.BOSS_MODEL_NAME
	boss.Parent = model
	local center = Config.getBossArenaCenter()
	local size = arenaDim.BossSize
	local bodyHeight = size.Y * 0.7
	local body = makePart("Body", Vector3.new(size.X, bodyHeight, size.Z), center, BOSS_ARENA_COLORS.bossBody, boss)
	body.Material = Enum.Material.Slate
	local headSize = size.Y - bodyHeight
	local head = makePart(
		"Head",
		Vector3.new(size.X * 0.7, headSize, size.Z * 0.7),
		Vector3.new(center.X, bodyHeight, center.Z),
		BOSS_ARENA_COLORS.bossHead,
		boss
	)
	head.Material = Enum.Material.Slate
	-- ตา 2 ข้างหันไปทางกำแพงกั้น (−X) ให้รู้ว่าบอสหันหน้าไปทางไหน
	for _, side in { -1, 1 } do
		local eye = makePart(
			"Eye",
			Vector3.new(0.4, headSize * 0.25, headSize * 0.25),
			Vector3.new(center.X - size.X * 0.35 - 0.2, bodyHeight + headSize * 0.45, center.Z + side * size.Z * 0.18),
			BOSS_ARENA_COLORS.bossEye,
			boss
		)
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
	end
	boss.PrimaryPart = body

	-- แถบ HP เหนือหัว — ของ server ทุกคนเห็นค่าเดียวกัน (BossService อัปเดต HpFill/HpText)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HpBar"
	gui.Size = UDim2.fromOffset(260, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, headSize + 3, 0)
	gui.MaxDistance = 300
	gui.Adornee = head
	gui.Parent = head
	local back = Instance.new("Frame")
	back.Name = "HpBack"
	back.Size = UDim2.fromScale(1, 0.45)
	back.Position = UDim2.fromScale(0, 0.55)
	back.BackgroundColor3 = BOSS_ARENA_COLORS.hpBack
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "HpFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BOSS_ARENA_COLORS.hpFill
	fill.BorderSizePixel = 0
	fill.Parent = back
	local text = Instance.new("TextLabel")
	text.Name = "HpText"
	text.Size = UDim2.fromScale(1, 0.55)
	text.BackgroundTransparency = 1
	text.Text = "บอส"
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.3
	text.Parent = gui
end

--------------------------------------------------------------------------------
-- โซน 5 — กำแพงใสกันตกขอบแมพ
--------------------------------------------------------------------------------

-- ⚠️ แมพเป็นแท่นลอย ผู้เล่นตกขอบได้ ยิ่งวิ่งเร็วยิ่งตกง่าย
-- **ไม่ใช้วิธี "ตกแล้วเกิดใหม่"** เพราะน่ารำคาญตอนกำลังฟาร์ม → กั้นไว้ตั้งแต่แรก
-- ⚠️ กั้นเฉพาะรอบ **ลานคอก** เพราะเลนรบมีกำแพงทึบสองข้างอยู่แล้ว
-- และต้องเว้นช่องฝั่งที่ต่อกับเลน ไม่งั้นเดินออกไปรบไม่ได้

-- ⚠️ UI-fix รอบ 1: ตกแต่งผิวกำแพงหินขอบแมพให้มีมิติ (หน้าตาล้วน ๆ ไม่แตะขนาด/ตำแหน่ง/CanCollide ของกำแพงจริงเลย)
-- เลือกวิธี "Part แปะเยื้องผิว" แทน SurfaceAppearance/Decal/Texture เพราะสามวิธีนั้นต้องมี asset รูปภาพ
-- ที่อัปโหลดขึ้น Roblox ไว้แล้ว (เหมือนข้อจำกัดเดียวกับโมเดล mesh ในคอก — repo นี้ยังไม่มี asset แบบนั้น
-- และสร้างจากสคริปต์ตรง ๆ ไม่ได้) ส่วน `Material = Rock` ที่กำแพงใช้อยู่แล้วมีลายผิวขรุขระแบบ built-in
-- ของ Roblox ให้ฟรีโดยไม่ต้องมี asset — ของที่เพิ่มตรงนี้คือมิติ/สีที่ engine material เดียวให้ไม่ได้
-- · แถบคราบชื้นเข้มด้านล่าง + หย่อมมอส/เถาวัลย์ 3 จุดต่อผืน เยื้องออกจากผิวจริง `DECOR_EPSILON`
--   กัน z-fighting (หลักการเดียวกับ getLaneWallStartX ด้านบน) · CanCollide = false ทั้งคู่ (ของประดับ ไม่ใช่กำแพง)
-- · ตำแหน่งหย่อมมอสคงที่ (ไม่สุ่ม) กันสองผู้เล่นเห็นไม่ตรงกัน แม้เรื่องนี้ไม่กระทบกติกาเกม
local DECOR_EPSILON = 0.05
local MOSS_FRACTIONS = { 0.18, 0.47, 0.79 } -- ตำแหน่งตามสัดส่วนความยาวกำแพง ไม่เท่ากันให้ดูเป็นธรรมชาติ

local function decorateBoundaryWall(size: Vector3, position: Vector3, normal: Vector3, folder: Instance)
	local lengthAlongX = normal.Z ~= 0 -- normal ชี้ตามแกน Z (North/South) → ตัวกำแพงยาวไปตามแกน X
	local wallLength = if lengthAlongX then size.X else size.Z
	local wallHeight = size.Y
	local thickness = if lengthAlongX then size.Z else size.X

	local faceOffset = thickness / 2 + DECOR_EPSILON
	local faceX = position.X + normal.X * faceOffset
	local faceZ = position.Z + normal.Z * faceOffset

	-- แถบคราบชื้นเข้ม สูงประมาณ 28% ของกำแพง วิ่งเกือบเต็มความยาว (เว้นขอบเล็กน้อยกันโผล่พ้นมุม)
	local bandHeight = wallHeight * 0.28
	local bandSize = if lengthAlongX
		then Vector3.new(wallLength * 0.94, bandHeight, 0.08)
		else Vector3.new(0.08, bandHeight, wallLength * 0.94)
	local band = makePart("WeatherBand", bandSize, Vector3.new(faceX, 0, faceZ), COLORS.boundaryDamp, folder)
	band.Material = Enum.Material.Rock
	band.CanCollide = false
	band.CastShadow = false

	-- หย่อมมอส/เถาวัลย์ กระจายตาม MOSS_FRACTIONS สูงไม่เท่ากันสลับกันไปให้ดูเป็นธรรมชาติ
	for i, frac in MOSS_FRACTIONS do
		local along = (frac - 0.5) * wallLength
		local mossHeight = wallHeight * (0.16 + (i % 2) * 0.08)
		local mossWidth = wallLength * 0.05
		local mossSize = if lengthAlongX
			then Vector3.new(mossWidth, mossHeight, 0.06)
			else Vector3.new(0.06, mossHeight, mossWidth)
		local mossX = if lengthAlongX then faceX + along else faceX
		local mossZ = if lengthAlongX then faceZ else faceZ + along
		local moss = makePart("Moss", mossSize, Vector3.new(mossX, 0, mossZ), COLORS.moss, folder)
		moss.Material = Enum.Material.LeafyGrass
		moss.CanCollide = false
		moss.CastShadow = false
	end
end

function MapBuilder.buildBoundary(parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "Boundary"
	folder.Parent = parent

	local h = MAP.Boundary.Height
	local t = MAP.Boundary.Thickness
	local margin = MAP.Boundary.Margin

	local minX = Config.getPlazaMinX() + margin
	-- ⚠️ ไม่ใช้ getPlazaMaxX() ตรง ๆ — จุดนั้นชนกับขอบคอกคอลัมน์ขวาสุดพอดี (รั้วไม้ก็วาง
	-- อยู่ตรงนั้นเป๊ะ) ใช้ Config.getEastBoundaryX() แทนซึ่งดันออกมาอีก Shop.Gap studs
	-- ให้ได้ระยะห่างจากรั้วเท่ากับฝั่ง North/South · MapBuilder.buildPlaza ต่อพื้นหญ้าปีก
	-- รองรับพื้นที่ที่ขยายออกมาไว้แล้ว (คนละช่วง Z กับเลน จึงไม่ทับพื้นเลน)
	local maxX = Config.getEastBoundaryX()
	local halfZ = Config.getPlazaHalfDepth() - margin
	local laneHalf = MAP.Lane.Width / 2

	-- ⚠️ เดิมกำแพงใส (Transparency=1) กันตกเฉย ๆ มองไม่เห็น — เปลี่ยนเป็นกำแพงหินที่มองเห็น
	-- ได้จริงตามที่ขอ **ขนาด/ตำแหน่ง/ความหนาไม่แตะเลย** (ยังผูกกับ Config.getMinWallThickness()
	-- เหมือนเดิมทุกประการ) เปลี่ยนแค่ Material/สี/Transparency ซึ่งเป็นเรื่อง "หน้าตา" ล้วน ๆ
	-- ไม่กระทบการชน — CanCollide ยังคง true เหมือนเดิม
	-- ⚠️ CastShadow เดิมปิดไว้เพราะของที่มองไม่เห็นแล้วมีเงาจะดูเป็นบั๊ก (เงาลอยมาจากอากาศ)
	-- ตอนนี้เป็นกำแพงทึบจริงแล้ว ปล่อยให้ทอดเงาตามปกติ (ค่า default ของ Part) ถึงจะดูเป็นกำแพงหินจริง
	-- innerNormal = ทิศตั้งฉากที่ชี้เข้าหาลาน (ฝั่งที่ผู้เล่นเดินเห็น) — ใช้ตกแต่งผิวด้านที่มีคนมองเท่านั้น
	local function stoneWall(name: string, size: Vector3, position: Vector3, innerNormal: Vector3)
		local part = makePart(name, size, position, COLORS.boundary, folder)
		part.Material = Enum.Material.Rock
		part.Transparency = 0
		part.CanCollide = true
		decorateBoundaryWall(size, position, innerNormal, folder)
	end

	-- ซ้าย · หน้า · หลัง
	stoneWall("West", Vector3.new(t, h, halfZ * 2), Vector3.new(minX, 0, 0), Vector3.new(1, 0, 0))
	stoneWall("North", Vector3.new(maxX - minX, h, t), Vector3.new((minX + maxX) / 2, 0, halfZ), Vector3.new(0, 0, -1))
	stoneWall("South", Vector3.new(maxX - minX, h, t), Vector3.new((minX + maxX) / 2, 0, -halfZ), Vector3.new(0, 0, 1))

	-- ฝั่งขวาแบ่งเป็นสองชิ้น เว้นช่องกลางไว้ให้เดินเข้าเลนรบ
	local gapHalf = laneHalf
	stoneWall(
		"EastUpper",
		Vector3.new(t, h, halfZ - gapHalf),
		Vector3.new(maxX, 0, (halfZ + gapHalf) / 2),
		Vector3.new(-1, 0, 0)
	)
	stoneWall(
		"EastLower",
		Vector3.new(t, h, halfZ - gapHalf),
		Vector3.new(maxX, 0, -(halfZ + gapHalf) / 2),
		Vector3.new(-1, 0, 0)
	)
end

--------------------------------------------------------------------------------
-- ประกอบทั้งแมพ
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- จุดเกิดผู้เล่น — หนึ่งจุดต่อคอก
--------------------------------------------------------------------------------
-- ⚠️ ผู้เล่นต้องเกิด**ใกล้คอกตัวเอง** ไม่ใช่กลางลานแล้ววิ่งข้ามไปหา
-- ลานกว้างขึ้นมากหลังขยายแมพ เกิดผิดมุมแล้วต้องวิ่งหลายวินาทีทุกครั้งที่ตาย
--
-- ทำเป็น SpawnLocation จริง (ไม่ใช่ย้ายตัวละครเองตอน CharacterAdded) เพราะ
--   · Roblox วางตัวละครให้ตั้งแต่เฟรมแรก ไม่มีอาการ "โผล่กลางลานแล้ววาร์ป"
--   · ใช้ได้กับการเกิดใหม่หลังตายด้วย โดยไม่ต้องต่อ event เพิ่ม
-- Main ผูกผู้เล่นกับจุดของตัวเองด้วย `player.RespawnLocation` หลังจองคอกเสร็จ
--
-- Neutral = true เพราะเกมนี้ไม่มีทีม · ใครยังไม่ได้คอก (ระหว่างจอง) จะได้จุดใดจุดหนึ่ง
-- ในลาน ซึ่งยังอยู่บนพื้นเสมอ ไม่ตกเหว
function MapBuilder.buildSpawns(parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "Spawns"
	folder.Parent = parent

	for index = 1, Config.World.MAX_PENS do
		local point = Config.getSpawnPointForPen(index)
		local pad = Instance.new("SpawnLocation")
		pad.Name = `Spawn{index}`
		pad.Size = MAP.Player.SpawnPadSize
		pad.Position = Vector3.new(point.X, point.Y + MAP.Player.SpawnPadSize.Y / 2, point.Z)
		pad.Anchored = true
		pad.CanCollide = false -- ไม่ให้สะดุดตอนเดินผ่าน
		pad.Neutral = true
		pad.Duration = 0 -- ไม่ต้องมี ForceField ตอนเกิด
		-- ⚠️ ซ่อนแผ่นสี่เหลี่ยมของ SpawnLocation ให้กลืนกับพื้นหญ้า — Transparency ไม่กระทบ
		-- การทำงานเป็นจุดเกิดเลย (ตำแหน่ง/CanCollide/Neutral ยังเหมือนเดิมทุกอย่าง)
		-- พื้นที่ตรงนี้มี GrassFloor ผืนใหญ่ของ buildPlaza() ครอบคลุมอยู่แล้วพอดี
		-- ไม่ต้องวางแผ่นหญ้าเพิ่ม
		pad.Transparency = 1
		pad.Color = COLORS.spawn
		pad.Material = Enum.Material.SmoothPlastic
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.Parent = folder

		spawnPads[index] = pad
	end
end

-- ⚠️ ของที่ต้องเก็บไว้เสมอ — ลบแล้วเอนจินสร้างใหม่ให้ แต่ระหว่างนั้นภาพและกล้องพัง
local KEEP_IN_WORKSPACE: { [string]: boolean } = {
	Terrain = true,
	Camera = true,
}

-- ล้างของที่ไม่ใช่ของเราออกจาก Workspace ก่อนสร้างแมพ
--
-- ⚠️ ทำไมต้องมี: ไฟล์ place ที่เคยสร้างจาก template ของ Studio จะมี **Baseplate**
-- (พื้นเทา 512 x 512) กับ SpawnLocation ติดมาด้วย ของพวกนั้นไม่ได้หายไปไหน
-- ตอน MapBuilder สร้างแมพ เพราะเราแค่ "เพิ่ม" โฟลเดอร์เข้าไป ไม่เคยลบอะไรเลย
-- ผลคือเห็นพื้นเทาโผล่รอบขอบแมพที่เราสร้าง
--
-- ⚠️ แมพทั้งใบมาจากสคริปต์ 100% (กฎในCLAUDE.md) ดังนั้น **ทุกอย่างใน Workspace
-- ที่ไม่ใช่ของเราคือของหลงเหลือ** ล้างได้อย่างปลอดภัย และควรล้างด้วย
-- ไม่งั้นไฟล์ place ของแต่ละคนจะมีของติดมาไม่เท่ากันแล้วเห็นภาพคนละแบบ
local function clearForeignObjects()
	local removed: { string } = {}

	for _, child in Workspace:GetChildren() do
		-- ข้ามตัวละครผู้เล่น เผื่อมีใครเข้ามาก่อนแมพสร้างเสร็จ
		local isCharacter = child:FindFirstChildOfClass("Humanoid") ~= nil
		if not KEEP_IN_WORKSPACE[child.ClassName] and not isCharacter then
			table.insert(removed, `{child.Name} ({child.ClassName})`)
			child:Destroy()
		end
	end

	if #removed > 0 then
		print(`[MapBuilder] ล้างของเดิมใน Workspace {#removed} ชิ้น: {table.concat(removed, ", ")}`)
	end
end

function MapBuilder.build()
	if built then
		return
	end
	built = true

	clearForeignObjects()

	local folder = Instance.new("Folder")
	folder.Name = "Map"
	folder.Parent = Workspace
	root = folder

	MapBuilder.buildPlaza(folder)
	MapBuilder.buildShop(folder)
	MapBuilder.buildBattleLane(folder)
	MapBuilder.buildBossRooms(folder)
	MapBuilder.buildBossArena(folder)
	MapBuilder.buildBoundary(folder)
	MapBuilder.buildMapSigns(folder)

	MapBuilder.buildSpawns(folder)

	print(
		`[MapBuilder] สร้างแมพแล้ว — คอก {Config.World.MAX_PENS} แปลง ({MAP.Pen.Size.X}x{MAP.Pen.Size.Y}) · `
			.. `เลนยาว {Config.getLaneLength()} studs · ห้องบอส {Config.Balance.Stage.COUNT} ห้อง · `
			.. `วิ่ง {DIM.Player.WalkSpeed} studs/วิ`
	)
end

--------------------------------------------------------------------------------
-- ให้โมดูลอื่นอ้างถึงของในแมพ (ไม่ต้องคำนวณพิกัดเอง)
--------------------------------------------------------------------------------

function MapBuilder.getPenPlot(index: number): PenPlot?
	return penPlots[index]
end

function MapBuilder.getBossRoom(stage: number): BossRoom?
	return bossRooms[stage]
end

-- จุดเกิดของคอกหมายเลข index — Main เอาไปตั้ง player.RespawnLocation
function MapBuilder.getSpawnLocation(index: number): SpawnLocation?
	return spawnPads[index]
end

function MapBuilder.getRoot(): Folder?
	return root
end

return MapBuilder
