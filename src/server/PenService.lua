--!strict
-- egg-army-game :: ระบบคอก (จองแปลง + แสดงแม่ที่เดินได้ + วางไข่)
--
-- หน้าที่: จองคอกให้ผู้เล่นคนละ 1 แปลง แล้ววาดแม่กับไข่ลงในแปลงนั้น
-- ผู้เล่นออก → คืนแปลงให้คนถัดไปใช้ต่อ
--
-- ⚠️ **ตัวแปลงในโลกสร้างโดย MapBuilder ไม่ใช่ไฟล์นี้** ไฟล์นี้แค่จองกับวาดของลงไป
--
-- ══ กติกาการวางของในคอก (เปลี่ยนจาก Phase 1.5) ══
--   พื้นที่เปิดโล่ง **ไม่มีช่องตาราง** — แม่และไข่วางตรงไหนก็ได้ในขอบเขตแปลง
--   แม่ **เดินไปมาได้** สุ่มจุดหมายในคอกแล้วเดินไปหา
--
-- ⚠️ **ห้ามใช้ Humanoid กับตัวแม่**
-- แม่เต็มคอก × ผู้เล่นเต็มเซิร์ฟ = Humanoid หลักร้อยตัว ซึ่งหนักเกินไปมาก
-- ใช้ CFrame lerp ธรรมดาแทน (ดู updateWander)
--
-- ⚠️ **ห้ามเซฟตำแหน่งแม่/ไข่ลง DataStore** — สุ่มใหม่ทุกครั้งที่เข้าเกม
-- ตำแหน่งไม่มีความหมายเชิงเกม (แม่เดินไปมาอยู่แล้ว) และการเซฟตำแหน่งของแม่ทุกตัว
-- บวกไข่อีกเป็นหมื่นฟอง จะกินโควต้า DataStore ฟรี ๆ โดยไม่ได้อะไรกลับมา

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local MapBuilder = require(ServerScriptService.MapBuilder)

local PenService = {}

local MAP = Config.MapDimensions

export type Pen = {
	index: number, -- เลขแปลง 1..MAX_PENS
	plot: MapBuilder.PenPlot, -- แปลงในโลกที่ MapBuilder สร้างไว้
	mothersFolder: Folder, -- แม่ที่กำลังแสดงอยู่
	eggsFolder: Folder, -- ไข่ที่กำลังฟักอยู่
	ownerUserId: number?, -- nil = ว่าง
}

-- แม่ 1 ตัวที่กำลังเดินอยู่ในคอก
type Roamer = {
	part: Part,
	origin: Vector3, -- กึ่งกลางแปลงที่แม่ตัวนี้อยู่
	from: Vector3,
	to: Vector3,
	startedAt: number, -- os.clock() ตอนเริ่มเดินรอบนี้
	duration: number, -- ใช้เวลาเดินกี่วินาที
	waitUntil: number, -- os.clock() ที่จะออกเดินรอบถัดไป
}

local pens: { Pen } = {}
local penByUserId: { [number]: Pen } = {}
local roamers: { Roamer } = {}
local built = false
local wanderConnection: RBXScriptConnection? = nil

local rng = Random.new()

local EMPTY_LABEL = "ว่าง"

--------------------------------------------------------------------------------
-- ขอบเขตที่วางของได้ในแปลง
--------------------------------------------------------------------------------

-- ครึ่งความกว้าง/ลึกที่ของยังอยู่ในรั้ว (หักขอบกันชนแล้ว)
-- validate() บังคับว่า PEN_EDGE_MARGIN เล็กกว่าครึ่งด้านสั้นสุดเสมอ ค่านี้จึงเป็นบวกแน่นอน
local function innerHalfExtents(): (number, number)
	local size = MAP.Pen.Size
	local margin = MAP.Pen.EdgeMargin
	return size.X / 2 - margin, size.Y / 2 - margin
end

-- สุ่มจุดบนพื้นภายในแปลง
local function randomPointInPen(center: Vector3): Vector3
	local halfX, halfZ = innerHalfExtents()
	return Vector3.new(
		center.X + rng:NextNumber(-halfX, halfX),
		center.Y,
		center.Z + rng:NextNumber(-halfZ, halfZ)
	)
end

--------------------------------------------------------------------------------
-- แม่เดินไปมา — CFrame lerp ไม่ใช่ Humanoid
--------------------------------------------------------------------------------

local function pickNextTrip(roamer: Roamer, now: number)
	local target = randomPointInPen(roamer.origin)
	local from = roamer.part.Position
	local distance = (Vector3.new(target.X, from.Y, target.Z) - from).Magnitude

	roamer.from = from
	roamer.to = Vector3.new(target.X, from.Y, target.Z)
	roamer.startedAt = now
	-- ระยะ ÷ ความเร็ว = เวลาที่ใช้ · กันหาร 0 ตอนสุ่มได้จุดเดิมเป๊ะ
	roamer.duration = math.max(distance / MAP.Wander.Speed, 0.05)
end

local function updateWander()
	local now = os.clock()

	for _, roamer in roamers do
		local part = roamer.part
		if part.Parent == nil then
			continue -- ถูกเก็บไปแล้ว รอบถัดไปจะถูกกวาดออกจากตาราง
		end

		if now < roamer.waitUntil then
			continue -- ยืนพักอยู่
		end

		local elapsed = now - roamer.startedAt
		local alpha = math.clamp(elapsed / roamer.duration, 0, 1)
		local position = roamer.from:Lerp(roamer.to, alpha)

		-- หันหน้าไปทางที่เดิน ให้ดูมีชีวิตขึ้นโดยไม่ต้องมี Humanoid
		local direction = roamer.to - roamer.from
		if direction.Magnitude > 0.01 then
			part.CFrame = CFrame.lookAt(position, position + direction.Unit)
		else
			part.Position = position
		end

		if alpha >= 1 then
			-- ถึงแล้ว หยุดพักสักครู่ค่อยออกเดินใหม่
			roamer.waitUntil = now + rng:NextNumber(MAP.Wander.PauseMin, MAP.Wander.PauseMax)
			pickNextTrip(roamer, roamer.waitUntil)
		end
	end
end

-- ลูปเดียวคุมแม่ทุกตัวในเซิร์ฟเวอร์ ไม่ใช่ลูปต่อตัว
local function startWanderLoop()
	if wanderConnection then
		return
	end
	local accumulated = 0
	wanderConnection = RunService.Heartbeat:Connect(function(delta)
		accumulated += delta
		if accumulated < MAP.Wander.Tick then
			return
		end
		accumulated = 0
		updateWander()
	end)
end

local function dropRoamersUnder(folder: Folder)
	for index = #roamers, 1, -1 do
		if roamers[index].part:IsDescendantOf(folder) then
			table.remove(roamers, index)
		end
	end
end

--------------------------------------------------------------------------------
-- สร้างโลก
--------------------------------------------------------------------------------

function PenService.buildWorld()
	if built then
		return
	end
	built = true

	MapBuilder.build()

	for index = 1, Config.World.MAX_PENS do
		local plot = MapBuilder.getPenPlot(index)
		assert(plot, `PenService: MapBuilder ไม่ได้สร้างคอกแปลง {index}`)

		local mothersFolder = Instance.new("Folder")
		mothersFolder.Name = "Mothers"
		mothersFolder.Parent = plot.model

		local eggsFolder = Instance.new("Folder")
		eggsFolder.Name = "Eggs"
		eggsFolder.Parent = plot.model

		pens[index] = {
			index = index,
			plot = plot,
			mothersFolder = mothersFolder,
			eggsFolder = eggsFolder,
			ownerUserId = nil,
		}
	end

	startWanderLoop()
	print(`[PenService] พร้อมใช้ {#pens} คอก`)
end

--------------------------------------------------------------------------------
-- ไข่ในคอก — วางตรงไหนก็ได้ ไม่มีแท่นเป็นช่อง ๆ
--------------------------------------------------------------------------------

local function findEgg(pen: Pen, slotIndex: number): Part?
	return pen.eggsFolder:FindFirstChild(`Egg{slotIndex}`) :: Part?
end

function PenService.showEgg(player: Player, slotIndex: number, egg: Config.EggType)
	local pen = penByUserId[player.UserId]
	if not pen then
		return
	end

	-- วางซ้ำช่องเดิม = เก็บอันเก่าทิ้งก่อน ไม่งั้นจะซ้อนกัน
	local existing = findEgg(pen, slotIndex)
	if existing then
		existing:Destroy()
	end

	local spot = randomPointInPen(pen.plot.center)
	local size = MAP.Blockout.EggSize

	local part = Instance.new("Part")
	part.Name = `Egg{slotIndex}`
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Position = Vector3.new(spot.X, spot.Y + MAP.Pen.FloorThickness + size.Y / 2, spot.Z)
	part.Color = egg.color
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = pen.eggsFolder
end

function PenService.hideEgg(player: Player, slotIndex: number)
	local pen = penByUserId[player.UserId]
	if not pen then
		return
	end
	local part = findEgg(pen, slotIndex)
	if part then
		part:Destroy()
	end
end

--------------------------------------------------------------------------------
-- แม่ในคอก
--------------------------------------------------------------------------------

local CLASS_COLORS: { [string]: Color3 } = {
	SS = Color3.fromRGB(240, 185, 60),
	S = Color3.fromRGB(190, 110, 235),
	A = Color3.fromRGB(230, 110, 90),
	B = Color3.fromRGB(120, 215, 180),
	C = Color3.fromRGB(200, 200, 190),
}

-- วาดแม่ในคอกใหม่ทั้งชุด (เรียกทุกครั้งที่รายชื่อแม่เปลี่ยน)
-- ⚠️ ตำแหน่งสุ่มใหม่ทุกครั้ง ไม่ได้จำของเดิม ตามกฎ "ห้ามเซฟตำแหน่ง"
function PenService.refreshMothers(player: Player, mothers: { any })
	local pen = penByUserId[player.UserId]
	if not pen then
		return
	end

	dropRoamersUnder(pen.mothersFolder)
	pen.mothersFolder:ClearAllChildren()

	local now = os.clock()
	local size = MAP.Blockout.MotherSize
	local floorTop = MAP.Pen.FloorThickness

	for _, mother in mothers do
		local character = Config.getCharacter(mother.charId)
		local class = if character then character.class else "C"

		local spot = randomPointInPen(pen.plot.center)

		local part = Instance.new("Part")
		part.Name = mother.uid
		part.Size = size
		part.Position = Vector3.new(spot.X, spot.Y + floorTop + size.Y / 2, spot.Z)
		part.Color = CLASS_COLORS[class] or CLASS_COLORS.C
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = pen.mothersFolder

		local gui = Instance.new("BillboardGui")
		gui.Name = "Tag"
		gui.Size = UDim2.fromOffset(170, 38)
		gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1.6, 0)
		gui.MaxDistance = 120
		gui.Adornee = part
		gui.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.4
		label.TextScaled = true
		label.Font = Enum.Font.SourceSansBold
		label.Text = `{if character then character.name else mother.charId} ({class})\n{Config.formatWeight(mother.weight)}`
		label.Parent = gui

		local roamer: Roamer = {
			part = part,
			origin = pen.plot.center,
			from = part.Position,
			to = part.Position,
			startedAt = now,
			duration = 0.05,
			-- กระจายเวลาออกเดินครั้งแรก ไม่งั้นแม่ทุกตัวจะขยับพร้อมกันเป๊ะ ดูเป็นหุ่นยนต์
			waitUntil = now + rng:NextNumber(0, MAP.Wander.PauseMax),
		}
		pickNextTrip(roamer, roamer.waitUntil)
		table.insert(roamers, roamer)
	end
end

function PenService.clearVisuals(pen: Pen)
	dropRoamersUnder(pen.mothersFolder)
	pen.mothersFolder:ClearAllChildren()
	pen.eggsFolder:ClearAllChildren()
	pen.plot.label.Text = `คอก {pen.index} · {EMPTY_LABEL}`
end

--------------------------------------------------------------------------------
-- จอง / คืนคอก
--------------------------------------------------------------------------------

function PenService.assign(player: Player): Pen?
	if penByUserId[player.UserId] then
		return penByUserId[player.UserId]
	end

	for _, pen in pens do
		if pen.ownerUserId == nil then
			pen.ownerUserId = player.UserId
			penByUserId[player.UserId] = pen
			pen.plot.label.Text = `คอก {pen.index} · {player.DisplayName}`
			return pen
		end
	end

	-- ไม่ควรเกิด เพราะ MAX_PENS = PLAYERS_PER_SERVER และ validate() บังคับไว้
	return nil
end

function PenService.release(player: Player)
	local pen = penByUserId[player.UserId]
	if not pen then
		return
	end
	PenService.clearVisuals(pen)
	pen.ownerUserId = nil
	penByUserId[player.UserId] = nil
end

function PenService.getPen(player: Player): Pen?
	return penByUserId[player.UserId]
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

-- จำนวนแม่ที่กำลังเดินอยู่ทั้งเซิร์ฟ — ไว้ดูตอนเทสต์ว่าไม่มีตัวค้าง
function PenService.getRoamerCount(): number
	return #roamers
end

-- ⚠️ ไม่ต่อ Players.PlayerRemoving ที่นี่ — Main.server.lua เป็นคนต่อสายให้
-- ต่อสองที่แล้วลำดับจะกลายเป็นเรื่องบังเอิญ (EggService ต้องเซฟก่อนคอกถูกคืน)

return PenService
