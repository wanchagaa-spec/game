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

local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MotherModels = require(ReplicatedStorage.Shared.MotherModels)
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
-- ⚠️ visual เป็น Part (กล่องสีเดิม) หรือ Model (โมเดล mesh ที่ import มา — ดู Character.modelAssetId ·
-- หรือโมเดลที่ประกอบจาก Part ในโค้ด — ดู MotherModels) ก็ได้ ทั้งคู่เป็น PVInstance จึงใช้ PivotTo/GetPivot ร่วมกันได้
type Roamer = {
	visual: Model | BasePart,
	origin: Vector3, -- กึ่งกลางแปลงที่แม่ตัวนี้อยู่
	from: Vector3, -- ⚠️ Y = baseY เสมอ (ระดับยืนบนพื้น) — ท่าขยับขึ้นลงบวกทีหลังตอนวาด ไม่สะสมเข้าตำแหน่ง
	to: Vector3,
	baseY: number, -- Y ของ pivot ตอนยืนบนพื้นพอดี
	-- ท่าขยับของโมเดลที่ประกอบจาก Part: "float" ลอยขึ้นลงตลอด (ปลา · rig เล่นอนิเมชันซ้อนไปด้วย) ·
	-- "hop" กระเด้งตอนเดิน (แบบที่ไม่มี rig — ตอนนี้ไม่มีตัวไหนใช้) · "animated"/nil = ไม่ขยับเอง
	motion: MotherModels.Motion?,
	hover: number, -- float: ลอยเหนือพื้นเท่านี้ (studs)
	bob: number, -- ระยะขยับ (studs) — hop: กระเด้งสูงสุด · float: ขึ้นลง ±
	bobRate: number, -- hop: ก้าวต่อวินาที · float: รอบต่อวินาที
	phase: number, -- สุ่มจังหวะเริ่ม ไม่ให้ทุกตัวขยับพร้อมกันเป๊ะ
	startedAt: number, -- os.clock() ตอนเริ่มเดินรอบนี้
	duration: number, -- ใช้เวลาเดินกี่วินาที
	waitUntil: number, -- os.clock() ที่จะออกเดินรอบถัดไป
	-- อนิเมชันตามท่า (walk/idle/sit) — nil = ไม่มีอนิเมชัน (กล่องสี หรือตัวละครที่ไม่ได้ใส่ไว้)
	tracks: { [string]: AnimationTrack }?,
	pose: string?, -- ท่าที่ขอล่าสุด (กันสั่งเล่นซ้ำทุก tick)
	playing: AnimationTrack?, -- ท่าที่เล่นอยู่จริง (อาจเป็นท่าสำรอง ถ้าท่าที่ขอไม่มี)
	stops: number, -- นับจำนวนครั้งที่หยุดพัก ไว้วนท่าพัก (restPoses)
	restPoses: { string }, -- ท่าพักที่ตัวนี้มีจริง เรียงตาม REST_POSE_ORDER (ว่าง = ไม่มีอนิเมชัน)
	speed: number, -- studs/วิ (กล่องสี = MAP.Wander.Speed · โมเดล mesh = โตตามขนาดตัว)
	animSpeed: number, -- ความเร็วเล่นอนิเมชัน (1 = ปกติ · ตัวใหญ่เล่นช้าลง ก้าวยาวขึ้น)
	walkAnimScale: number, -- คูณเพิ่มเฉพาะท่าเดิน (rig R6: อนิเมชันเดินของ Roblox ตั้งมาเร็วกว่าแม่เดินมาก · MotherModels.walkAnimSpeed)
	trackConnections: { RBXScriptConnection }, -- เล่นซ้ำตอนท่าจบ — ตัดทิ้งตอนเก็บแม่
	inset: number, -- ระยะเว้นจากขอบคอก = ครึ่งความกว้างตัว กันตัวใหญ่ยื่นทะลุรั้ว
}

-- เวลาเฟดตอนเปลี่ยนท่า — สั้นพอไม่ให้ท่าเดินค้างตอนหยุด แต่ไม่กระตุกเปลี่ยนทันที
local POSE_FADE_SECONDS = 0.25

-- ลำดับวนท่าตอนหยุดพัก — ตัวละครไหนไม่มีท่าไหนก็ข้ามไป
-- (กอริลลาเดิม = ยืน→นั่ง · rig คน = ยืน→เหวี่ยงแขน · rig สัตว์สี่ขา/ปลา = ยืนอย่างเดียว · มีครบ = ยืน→นั่ง→ต่อย)
local REST_POSE_ORDER = { "idle", "sit", "punch" }

local function getRestPoses(tracks: { [string]: AnimationTrack }?): { string }
	local poses = {}
	if tracks then
		for _, pose in REST_POSE_ORDER do
			if tracks[pose] then
				table.insert(poses, pose)
			end
		end
	end
	return poses
end

local function poseSpeed(roamer: Roamer, track: AnimationTrack): number
	local tracks = roamer.tracks
	return roamer.animSpeed * (if tracks and track == tracks.walk then roamer.walkAnimScale else 1)
end

-- เปลี่ยนท่า — ขาดท่าที่ขอ (เช่นไม่ได้ใส่ sit) ใช้ท่ายืนพักแทน · ท่าเดินไม่มีท่าสำรอง
-- ⚠️ ตั้ง roamer.playing เป็นท่าใหม่**ก่อน**สั่งหยุดท่าเก่า — ตัวเล่นซ้ำ (watchTrackEnds) เห็นว่าท่าเก่าไม่ใช่ท่าปัจจุบันแล้วจะไม่เล่นกลับ
local function playPose(roamer: Roamer, pose: string)
	local tracks = roamer.tracks
	if tracks == nil or roamer.pose == pose then
		return
	end
	roamer.pose = pose

	local nextTrack = tracks[pose] or (if pose ~= "walk" then tracks.idle else nil)
	if nextTrack == roamer.playing then
		return
	end
	local previous = roamer.playing
	roamer.playing = nextTrack
	if previous then
		previous:Stop(POSE_FADE_SECONDS)
	end
	if nextTrack then
		nextTrack:Play(POSE_FADE_SECONDS, 1, poseSpeed(roamer, nextTrack))
	end
end

-- ท่าที่ไม่ได้ตั้งให้วนในตัว asset (เช่นอนิเมชันตั้งต้นบางท่าของ Roblox) เล่นจบแล้วหยุด — จบแล้วยังเป็นท่าปัจจุบัน = เล่นใหม่
-- ⚠️ ไม่ตั้ง AnimationTrack.Looped ฝั่ง server แทน: ค่านั้นไม่ส่งไป client → server วนอยู่คนเดียว ผู้เล่นเห็นท่าค้าง
--   เล่นใหม่จาก server = Animator ส่งการเล่นรอบใหม่ให้ทุก client เอง · ท่าที่วนในตัว asset อยู่แล้ว Stopped ไม่ยิง = ไม่มีผล
local function watchTrackEnds(roamer: Roamer)
	local tracks = roamer.tracks
	if tracks == nil then
		return
	end
	for _, track in tracks do
		table.insert(
			roamer.trackConnections,
			track.Stopped:Connect(function()
				-- Length 0 = asset ยังโหลดไม่ได้/ไม่มีจริง → ไม่เล่นซ้ำ (กันวนเล่น-หยุดรัวทุกเฟรม)
				if roamer.playing == track and roamer.visual.Parent ~= nil and track.Length > 0 then
					track:Play(0, 1, poseSpeed(roamer, track))
				end
			end)
		)
	end
end

local pens: { Pen } = {}
local penByUserId: { [number]: Pen } = {}
local roamers: { Roamer } = {}
local built = false
local wanderConnection: RBXScriptConnection? = nil

local rng = Random.new()

-- ⚠️ ขนาดป้ายชื่อ+น้ำหนักเหนือแม่ในคอก — **studs ในโลก** (กว้าง · สูง · 2 บรรทัด) ไม่ใช่พิกเซลบนจอ
local MOTHER_TAG_SIZE = Vector2.new(8, 2)

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

-- สุ่มจุดบนพื้นภายในแปลง · inset = เว้นจากขอบเพิ่ม (ครึ่งความกว้างของตัวที่จะวาง)
-- ตัวใหญ่กว่าคอกก็แค่ยืนกลางคอก (ไม่ติดลบ)
local function randomPointInPen(center: Vector3, inset: number?): Vector3
	local halfX, halfZ = innerHalfExtents()
	halfX = math.max(halfX - (inset or 0), 0)
	halfZ = math.max(halfZ - (inset or 0), 0)
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
	local target = randomPointInPen(roamer.origin, roamer.inset)
	local pivot = roamer.visual:GetPivot().Position
	-- ⚠️ ใช้ baseY ไม่ใช่ Y ของ pivot ตอนนี้ — ตอนกระเด้ง/ลอย pivot สูงกว่าพื้น ถ้าเอามาใช้ตรง ๆ ตัวจะค่อย ๆ ลอยขึ้นเรื่อย ๆ
	local from = Vector3.new(pivot.X, roamer.baseY, pivot.Z)
	local distance = (Vector3.new(target.X, from.Y, target.Z) - from).Magnitude

	roamer.from = from
	roamer.to = Vector3.new(target.X, from.Y, target.Z)
	roamer.startedAt = now
	-- ระยะ ÷ ความเร็ว = เวลาที่ใช้ · กันหาร 0 ตอนสุ่มได้จุดเดิมเป๊ะ
	roamer.duration = math.max(distance / roamer.speed, 0.05)
end

-- ระยะยกจากพื้นตามท่าขยับ (studs) — moving = กำลังเดินอยู่
local function motionOffset(roamer: Roamer, now: number, moving: boolean): number
	if roamer.motion == "float" then
		return roamer.hover + math.sin((now + roamer.phase) * roamer.bobRate * 2 * math.pi) * roamer.bob
	elseif roamer.motion == "hop" and moving then
		return math.abs(math.sin((now - roamer.startedAt) * roamer.bobRate * math.pi)) * roamer.bob
	end
	return 0
end

local function updateWander()
	local now = os.clock()

	for _, roamer in roamers do
		local visual = roamer.visual
		if visual.Parent == nil then
			continue -- ถูกเก็บไปแล้ว รอบถัดไปจะถูกกวาดออกจากตาราง
		end

		if now < roamer.waitUntil then
			-- ยืนพักอยู่ (ท่ายืน/นั่งตั้งไว้แล้วตอนถึงจุดหมาย) · ปลาลอยขึ้นลงต่อแม้หยุดพัก
			if roamer.motion == "float" then
				local pivot = visual:GetPivot()
				visual:PivotTo(pivot.Rotation + Vector3.new(pivot.X, roamer.baseY + motionOffset(roamer, now, false), pivot.Z))
			end
			continue
		end

		playPose(roamer, "walk")

		local elapsed = now - roamer.startedAt
		local alpha = math.clamp(elapsed / roamer.duration, 0, 1)
		local position = roamer.from:Lerp(roamer.to, alpha)
		position += Vector3.new(0, motionOffset(roamer, now, alpha < 1), 0)

		-- หันหน้าไปทางที่เดิน ให้ดูมีชีวิตขึ้นโดยไม่ต้องมี Humanoid
		local direction = roamer.to - roamer.from
		if direction.Magnitude > 0.01 then
			visual:PivotTo(CFrame.lookAt(position, position + direction.Unit))
		else
			-- ยังไม่มีทิศทางเดิน (เพิ่งสปอน) — ขยับตำแหน่งอย่างเดียว คงการหันหน้าเดิมไว้
			visual:PivotTo(visual:GetPivot().Rotation + position)
		end

		if alpha >= 1 then
			-- ถึงแล้ว หยุดพักสักครู่ค่อยออกเดินใหม่ · วนท่าพักที่ตัวนี้มี (ดู REST_POSE_ORDER)
			-- (ตำแหน่งรอบนี้ใช้ offset ของ "ไม่ได้เดิน" แล้ว → กระเด้งจบที่พื้นพอดี)
			roamer.stops += 1
			local restPoses = roamer.restPoses
			if #restPoses > 0 then
				playPose(roamer, restPoses[(roamer.stops - 1) % #restPoses + 1])
			end
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
		local roamer = roamers[index]
		if roamer.visual:IsDescendantOf(folder) then
			roamer.playing = nil -- ท่าที่กำลังเล่นหยุดตามโมเดลที่ถูกลบ — ห้ามเล่นซ้ำ
			for _, connection in roamer.trackConnections do
				connection:Disconnect()
			end
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

-- weight = น้ำหนักของไข่ฟองนี้ (ใช้กำหนดขนาดโมเดล — ไข่ใหญ่ = หนัก, Config.getEggVisualSize)
function PenService.showEgg(player: Player, slotIndex: number, egg: Config.EggType, weight: number)
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
	local size = Config.getEggVisualSize(weight)

	local part = Instance.new("Part")
	part.Name = `Egg{slotIndex}`
	part.Shape = Enum.PartType.Ball
	part.Size = size
	-- ⚠️ ไข่เป็น **ทรงกลม** รัศมีจึงเป็น min(X,Y,Z)/2 ไม่ใช่ Y/2
	-- ใช้ Y/2 เมื่อไหร่ไข่จะลอยเหนือพื้นเท่ากับส่วนต่างของสองค่านั้น
	part.Position =
		Vector3.new(spot.X, Config.getPenRestingY(Config.getBallRadius(size)), spot.Z)
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

-- modelAssetId → โมเดลต้นแบบ (ไม่ได้ parent ไว้ที่ไหน ใช้ clone อย่างเดียว)
local meshTemplates: { [number]: Model } = {}
-- modelAssetId → ความสูงต้นฉบับตอน import (studs) ไว้คำนวณสเกลให้ tier 1 สูง MOTHER_MESH_BASE_HEIGHT
local meshTemplateHeights: { [number]: number } = {}
-- โหลดไม่สำเร็จ ไม่ลองซ้ำจนกว่าเซิร์ฟจะรีสตาร์ท (กันยิงเน็ต + warn ซ้ำทุกครั้งที่ refresh)
local failedMeshAssets: { [number]: boolean } = {}
-- กำลังโหลดอยู่เบื้องหลัง — กันยิง LoadAsset ซ้อนกันหลายรอบกับ asset เดียวกัน
local loadingMeshAssets: { [number]: boolean } = {}
-- รายชื่อแม่ในคอกล่าสุดที่วาดให้แต่ละคน — ไว้วาดคอกใหม่เองตอนโมเดลโหลดเสร็จทีหลัง
local lastMothersByUserId: { [number]: { any } } = {}

-- โหลดนานเกินนี้ = warn ให้รู้ตัว (LoadAsset ไม่มี timeout ในตัว และเคยค้างเงียบ ๆ ไม่ error เลยจริง)
local MESH_LOAD_SLOW_WARN_SECONDS = 15
-- Folder ใน ReplicatedStorage ที่เก็บสำเนาโมเดลให้ client วาดรูป (UI-1) — ชื่อต้องตรงกับ UiKit.lua ฝั่ง client
local PORTRAIT_TEMPLATE_FOLDER = "MotherModelTemplates"

-- ดึง Model asset ที่ publish ขึ้น Roblox ไว้แล้ว (ดู Character.modelAssetId) — **yield** (ยิงเน็ต)
-- เรียกจาก getMeshTemplate ในเธรดเบื้องหลังเท่านั้น ห้ามเรียกตรงจาก refreshMothers
-- ล้มเหลวตรงไหนก็ warn() แล้วคืน nil (asset หลุด/ยังไม่ผ่านการตรวจของ Roblox ไม่ควรทำให้คอกพัง)
local function fetchMeshTemplateAsync(assetId: number): Model?
	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or container == nil then
		-- ⚠️ LoadAsset โหลดได้เฉพาะ **Model** asset ของเจ้าของเกม (บัญชี/กลุ่มเดียวกับที่ publish เกม)
		-- เลข Mesh (MeshId ของ MeshPart) ใช้ไม่ได้
		warn(`[PenService] LoadAsset ล้มเหลวกับ modelAssetId {assetId}: {container} — ใช้กล่องสีแทน`)
		return nil
	end

	local content = container:FindFirstChildWhichIsA("Model") or container:FindFirstChildWhichIsA("BasePart")
	if content == nil then
		warn(`[PenService] modelAssetId {assetId} ไม่มี Model/BasePart อยู่ข้างใน — ใช้กล่องสีแทน`)
		container:Destroy()
		return nil
	end

	local model: Model
	if content:IsA("Model") then
		content.Parent = nil
		model = content
	else
		-- asset เป็น BasePart เดี่ยว ๆ (ไม่ได้ห่อ Model มา) — ห่อเองให้ PivotTo/ScaleTo ใช้ได้
		model = Instance.new("Model")
		content.Parent = model
		model.PrimaryPart = content
	end
	container:Destroy()

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Humanoid") then
			-- ⚠️ กฎ "ห้ามใช้ Humanoid กับตัวแม่" (หัวไฟล์) — Studio บางโหมด import แล้ว rig ให้เอง
			-- AnimationController **เก็บไว้** (เบากว่า Humanoid มาก) ใช้เล่นอนิเมชันกระดูก
			warn(`[PenService] modelAssetId {assetId} มี Humanoid ติดมา — ถอดทิ้ง`)
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			-- เหมือนกล่องสีเดิม: ขยับด้วย PivotTo ล้วน ๆ ห้ามให้ฟิสิกส์ดึงตก และผู้เล่นเดินทะลุได้
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	return model
end

-- วาดคอกใหม่ให้ทุกคนที่มีแม่ใช้ asset นี้อยู่ — เรียกตอนโมเดลโหลดเสร็จทีหลัง
local function redrawPensUsing(assetId: number)
	for userId, mothers in lastMothersByUserId do
		local uses = false
		for _, mother in mothers do
			local character = Config.getCharacter(mother.charId)
			if character and character.modelAssetId == assetId then
				uses = true
				break
			end
		end
		local player = if uses then Players:GetPlayerByUserId(userId) else nil
		if player then
			PenService.refreshMothers(player, mothers)
		end
	end
end

-- UI-1: ส่งสำเนาต้นแบบไปไว้ใน ReplicatedStorage ให้ client เอาไปวาดรูปใน ViewportFrame (กระเป๋า/แผงเท้า)
-- ⚠️ client โหลด asset เองไม่ได้ (InsertService:LoadAsset ใช้ได้เฉพาะ server)
-- ชื่อลูก = Config.getMotherTemplateName(charId): mesh = tostring(assetId) (เดิม) · ประกอบจาก Part = charId
-- เป็นภาพประกอบล้วน ๆ ไม่มีผลกับเกม · ไม่มีสำเนา (ยังโหลดไม่เสร็จ/ไม่มีโมเดล) = client วาดกล่องสีแทน
local function publishPortraitTemplate(name: string, model: Model)
	local folder = ReplicatedStorage:FindFirstChild(PORTRAIT_TEMPLATE_FOLDER)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = PORTRAIT_TEMPLATE_FOLDER
		created.Parent = ReplicatedStorage
		folder = created
	end
	if (folder :: Instance):FindFirstChild(name) then
		return
	end
	local copy = model:Clone()
	copy.Name = name
	copy.Parent = folder
end

-- ⚠️ **ไม่ yield เด็ดขาด** — ครั้งแรกเริ่มโหลดเบื้องหลังแล้วคืน nil ทันที (ผู้เรียกวาดกล่องสีไปก่อน)
-- โหลดเสร็จเมื่อไหร่ค่อยวาดคอกใหม่เองผ่าน redrawPensUsing
-- เหตุผล: LoadAsset เคย**ค้างไม่ return เลย**ในเซิร์ฟจริง ถ้า refreshMothers รอ LoadAsset
-- ทุกอย่างที่เรียก refreshMothers (ย้ายแม่/ขาย/ฟักเข้าคอก) จะค้างตามไปด้วยทั้งหมด
local function getMeshTemplate(assetId: number): Model?
	local cached = meshTemplates[assetId]
	if cached then
		return cached
	end
	if failedMeshAssets[assetId] or loadingMeshAssets[assetId] then
		return nil
	end

	loadingMeshAssets[assetId] = true
	task.delay(MESH_LOAD_SLOW_WARN_SECONDS, function()
		if loadingMeshAssets[assetId] then
			warn(
				`[PenService] modelAssetId {assetId} ยังโหลดไม่เสร็จหลัง {MESH_LOAD_SLOW_WARN_SECONDS} วิ `
					.. `— ระหว่างนี้ใช้กล่องสีไปก่อน (เช็คว่าเป็นเลข Model ของเจ้าของเกมจริงไหม)`
			)
		end
	end)
	task.spawn(function()
		local model = fetchMeshTemplateAsync(assetId)
		loadingMeshAssets[assetId] = nil
		local nativeHeight = if model then select(2, model:GetBoundingBox()).Y else 0
		if model and nativeHeight <= 0 then
			warn(`[PenService] modelAssetId {assetId} สูง 0 studs (ไม่มีชิ้นที่มองเห็น) — ใช้กล่องสีแทน`)
			model = nil
		end
		if model then
			meshTemplates[assetId] = model
			meshTemplateHeights[assetId] = nativeHeight
			publishPortraitTemplate(tostring(assetId), model)
			print(`[PenService] โหลด modelAssetId {assetId} สำเร็จ — วาดคอกใหม่`)
			redrawPensUsing(assetId)
		else
			failedMeshAssets[assetId] = true
		end
	end)
	return nil
end

-- ══ โมเดลที่ประกอบจาก Part ในโค้ด (MotherModels · รอบโมเดลตัวละคร) ══
-- charId → ต้นแบบ (สร้างครั้งเดียว ไม่ yield · ไม่ได้ parent ไว้ที่ไหน ใช้ clone อย่างเดียว)
local partTemplates: { [string]: Model } = {}

-- สร้างต้นแบบ + ส่งสำเนาให้ client วาดรูป (ชื่อ = charId) — nil = charId นี้ไม่มีแบบ
local function getPartTemplate(charId: string): Model?
	local cached = partTemplates[charId]
	if cached then
		return cached
	end
	if not MotherModels.hasBlueprint(charId) then
		return nil
	end
	local ok, model = pcall(MotherModels.build, charId)
	if not ok or model == nil then
		warn(`[PenService] ประกอบโมเดล "{charId}" จาก Part ไม่สำเร็จ: {model} — ใช้กล่องสีแทน`)
		return nil
	end
	partTemplates[charId] = model :: Model
	publishPortraitTemplate(Config.getMotherTemplateName(charId), model :: Model)
	return model
end

-- UI-1: เริ่มโหลดโมเดลของทุกตัวละครที่มี modelAssetId ตั้งแต่เซิร์ฟบูต (เบื้องหลัง ไม่ yield)
-- เดิมโหลดตอนมีแม่ตัวนั้นเข้าคอกครั้งแรกเท่านั้น → แม่ที่อยู่แค่ในกระเป๋าจะไม่มีรูปในกระเป๋าเลย
-- + รอบโมเดลตัวละคร: ประกอบโมเดลจาก Part ของทุกตัวที่มีแบบ (MotherModels) ตั้งแต่บูต — client มีรูปตั้งแต่เข้าเกม
-- เรียกจาก Main.server.lua ต่อจาก buildWorld()
function PenService.preloadModelTemplates()
	for _, problem in MotherModels.validate() do
		warn(`[PenService] แบบโมเดลผิดกติกา: {problem}`)
	end
	for _, character in Config.Characters do
		local assetId = character.modelAssetId
		if character.enabled and assetId then
			getMeshTemplate(assetId)
		elseif character.enabled then
			getPartTemplate(character.id)
		end
	end
end

-- clone จากต้นแบบแล้วสเกลตามน้ำหนักแม่ × คลาส — ไม่ yield
-- nativeHeight = ความสูงต้นฉบับของ mesh (normalize ให้ tier 1 สูง MOTHER_MESH_BASE_HEIGHT) ·
--   nil = โมเดลที่ประกอบจาก Part (ออกแบบเป็น studs จริงที่ tier 1 อยู่แล้ว ไม่ normalize — หมูเตี้ยกว่าคนตามแบบ)
-- คืน (โมเดล, sizeScale) · sizeScale = ใหญ่กว่าขนาด tier 1 คลาส C กี่เท่า (ไว้คิดความเร็วเดิน/ก้าว)
local function buildModelMother(template: Model, weight: number, class: string, nativeHeight: number?, label: string): (Model, number)
	local model = template:Clone()
	local visualScale = Config.Balance.VisualScale

	-- ⚠️ สเกลแบบสัดส่วนเดียวกันทุกแกน (ไม่ยืด/บีบ) ต่างจากกล่องเดิมที่ยืด Vector3 อิสระ 3 แกนได้
	-- เพราะโมเดลจริงยืดแกนเดียวแล้วเสียรูปทันที
	-- ⚠️ mesh เทียบกับความสูงต้นฉบับ ไม่ใช่สเกลดิบ — ไฟล์แต่ละไฟล์ import มาขนาดไม่เท่ากัน
	-- (กอริลลาเคยออกมาเล็กกว่าคนมากทั้งที่สเกล 1:1) ตอนนี้ tier 1 สูง MOTHER_MESH_BASE_HEIGHT เสมอ
	local sizeScale = Config.getVisualScaleMultiplier(weight)
		* visualScale.MOTHER_PEN_SHRINK
		* Config.getMotherClassScale(class)
	local normalize = if nativeHeight and nativeHeight > 0 then visualScale.MOTHER_MESH_BASE_HEIGHT / nativeHeight else 1
	local scale = normalize * sizeScale
	local scaleOk = pcall(function()
		model:ScaleTo(scale)
	end)
	if not scaleOk then
		warn(`[PenService] Model:ScaleTo ล้มเหลวกับ {label} — ใช้ขนาดต้นแบบแทน`)
	end

	return model, sizeScale
end

-- animation id → Animation instance ใช้ซ้ำทุกตัว (ไม่ต้อง parent ไว้ที่ไหน)
local animationObjects: { [number]: Animation } = {}

local function getAnimation(animationId: number): Animation
	local cached = animationObjects[animationId]
	if cached then
		return cached
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{animationId}`
	animationObjects[animationId] = animation
	return animation
end

-- โหลดอนิเมชันทุกท่าให้โมเดลตัวนี้ — ไม่ yield (asset ค่อย ๆ โหลดเองเบื้องหลัง)
-- ⚠️ ต้องเรียก **หลัง** parent โมเดลเข้า Workspace แล้ว (LoadAnimation ใช้กับ Animator นอกเกมไม่ได้)
-- ⚠️ เล่นฝั่ง server ผ่าน Animator ที่ server สร้าง → Roblox ส่งภาพให้ทุก client เอง
local function loadPoseTracks(model: Model, animationIds: Config.CharacterAnimations?): { [string]: AnimationTrack }?
	if animationIds == nil then
		return nil
	end

	local controller: AnimationController
	local existingController = model:FindFirstChildWhichIsA("AnimationController", true)
	if existingController then
		controller = existingController
	else
		controller = Instance.new("AnimationController")
		controller.Parent = model
	end

	local animator: Animator
	local existingAnimator = controller:FindFirstChildWhichIsA("Animator")
	if existingAnimator then
		animator = existingAnimator
	else
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	local tracks: { [string]: AnimationTrack } = {}
	for pose, animationId in animationIds :: { [string]: number } do
		local ok, track = pcall(function()
			return animator:LoadAnimation(getAnimation(animationId))
		end)
		if ok and track then
			-- ⚠️ ไม่ตั้ง track.Looped (ค่านี้ไม่ส่งไป client) — ท่าที่ไม่วนในตัว asset เล่นใหม่เองตอนจบ (watchTrackEnds)
			tracks[pose] = track
		else
			warn(`[PenService] โหลดอนิเมชันท่า {pose} ({animationId}) ไม่สำเร็จ: {track}`)
		end
	end

	return if next(tracks) then tracks else nil
end

-- วาดแม่ในคอกใหม่ทั้งชุด (เรียกทุกครั้งที่รายชื่อแม่เปลี่ยน)
-- ⚠️ ตำแหน่งสุ่มใหม่ทุกครั้ง ไม่ได้จำของเดิม ตามกฎ "ห้ามเซฟตำแหน่ง"
-- ⚠️ ทั้งฟังก์ชัน**ไม่ yield** (โมเดล mesh โหลดเบื้องหลัง ดู getMeshTemplate) การล้าง+สร้างใหม่จึงจบ
-- ในรวดเดียวเสมอ ผู้เรียก (EggService) ไม่ต้องรอเน็ต
function PenService.refreshMothers(player: Player, mothers: { any })
	local pen = penByUserId[player.UserId]
	if not pen then
		return
	end

	-- ⚠️ เก็บ reference ของอาเรย์ตัวจริง (data.mothersInPen) ไว้วาดใหม่ตอนโมเดลโหลดเสร็จ
	lastMothersByUserId[player.UserId] = mothers

	dropRoamersUnder(pen.mothersFolder)
	pen.mothersFolder:ClearAllChildren()

	local now = os.clock()

	for _, mother in mothers do
		local character = Config.getCharacter(mother.charId)
		local class = if character then character.class else "C"

		-- ⚠️ ลำดับ: โมเดล mesh ที่ import มา (Character.modelAssetId) → โมเดลที่ประกอบจาก Part (MotherModels)
		-- → กล่องสีเดิม (ไม่มีทั้งสองแบบ/ยังโหลดไม่เสร็จ) — ต้องมี resting Y ที่ตรงกับรูปทรงจริงของแต่ละแบบ
		-- ⚠️ visualHeight คำนวณแยกต่อสาขา ไม่เรียก GetBoundingBox() รวมท้ายสุด เพราะเมธอดนี้
		-- มีแค่ใน Model ไม่มีใน BasePart (สาขา fallback เป็น Part เดี่ยว ๆ)
		local visual: Model | BasePart
		local visualHeight: number
		local restingY: number
		local tracks: { [string]: AnimationTrack }? = nil
		local speed = MAP.Wander.Speed
		local animSpeed = 1
		local walkAnimScale = 1
		local inset: number
		local spot: Vector3

		local assetId = if character then character.modelAssetId else nil
		-- ยังโหลดไม่เสร็จ/ล้มเหลว = nil → วาดกล่องสีไปก่อน (ไม่ yield)
		local template = if assetId then getMeshTemplate(assetId) else nil
		local nativeHeight: number? = if assetId and template
			then meshTemplateHeights[assetId] or Config.Balance.VisualScale.MOTHER_MESH_BASE_HEIGHT
			else nil
		-- ไม่มี mesh → โมเดลที่ประกอบจาก Part (ถ้ามีแบบ)
		if template == nil then
			template = getPartTemplate(mother.charId)
		end
		local motion: MotherModels.Motion? = if template and nativeHeight == nil
			then template:GetAttribute("Motion") :: MotherModels.Motion?
			else nil

		if template then
			local meshModel, sizeScale =
				buildModelMother(template, mother.weight, class, nativeHeight, if assetId then `modelAssetId {assetId}` else mother.charId)
			-- ครึ่งความสูงจริงหลังสเกลแล้ว (ไม่ใช่ก่อนสเกล) มาจาก bounding box จริงของโมเดลนั้น
			local boxCFrame, boundsSize = meshModel:GetBoundingBox()
			visualHeight = boundsSize.Y
			restingY = Config.getPenRestingY(visualHeight / 2)
			-- เว้นขอบเท่าครึ่งเส้นทแยงพื้น (ตัวหมุนหันไปทางไหนก็ไม่ยื่นทะลุรั้ว)
			inset = Vector2.new(boundsSize.X, boundsSize.Z).Magnitude / 2
			spot = randomPointInPen(pen.plot.center, inset)
			-- ตัวใหญ่ s เท่า: เดินเร็วขึ้น √s + อนิเมชันช้าลง √s → ระยะต่อก้าวโต s เท่า (ไม่ไถล)
			local stride = math.sqrt(sizeScale)
			speed = Config.Balance.VisualScale.MOTHER_MESH_WALK_SPEED * stride
			animSpeed = 1 / stride
			-- ⚠️ pivot ของโมเดลที่ import มาไม่จำเป็นต้องอยู่กลางกล่อง (มักอยู่ที่เท้าหรือจุดกำเนิด
			-- ของไฟล์) — ชดเชยระยะนี้ ไม่งั้นโมเดลลอยหรือจมพื้นเท่ากับระยะห่าง pivot↔กลางกล่อง
			local pivotAboveCenter = meshModel:GetPivot().Y - boxCFrame.Y
			meshModel:PivotTo(CFrame.new(spot.X, restingY + pivotAboveCenter, spot.Z))
			meshModel.Name = mother.uid
			meshModel.Parent = pen.mothersFolder
			-- อนิเมชัน: mesh = Character.animationIds · rig ที่ประกอบจาก Part = อนิเมชันตั้งต้นของ Roblox (MotherModels.getAnimations)
			local animationIds: Config.CharacterAnimations? = if nativeHeight
				then (if character then character.animationIds else nil)
				else MotherModels.getAnimations(mother.charId) :: any
			tracks = loadPoseTracks(meshModel, animationIds)
			local blueprint = if nativeHeight == nil then MotherModels.getBlueprint(mother.charId) else nil
			walkAnimScale = if blueprint and blueprint.walkAnimSpeed then blueprint.walkAnimSpeed else 1
			visual = meshModel
		else
			-- ⚠️ ขนาดต่อตัว ไม่ใช่ค่าคงที่ร่วม — แม่แต่ละตัวหนักไม่เท่ากัน (Config.getMotherVisualSize)
			-- `inPen = true` คูณ MOTHER_PEN_SHRINK (ตอนนี้ 1:1 เท่าขนาดตอนถือ/ส่งรบ)
			local size = Config.getMotherVisualSize(mother.weight, true)
			-- แม่เป็นทรงกล่อง ครึ่งความสูงจึงเป็น Y/2 ตรง ๆ (ต่างจากไข่ที่เป็นทรงกลม)
			visualHeight = size.Y
			restingY = Config.getPenRestingY(visualHeight / 2)
			inset = Vector2.new(size.X, size.Z).Magnitude / 2
			spot = randomPointInPen(pen.plot.center, inset)

			local part = Instance.new("Part")
			part.Name = mother.uid
			part.Size = size
			part.Position = Vector3.new(spot.X, restingY, spot.Z)
			part.Color = CLASS_COLORS[class] or CLASS_COLORS.C
			part.Anchored = true
			part.CanCollide = false
			part.Material = Enum.Material.SmoothPlastic
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Parent = pen.mothersFolder
			visual = part
		end

		-- ⚠️ ขนาดป้ายเป็น **studs ในโลก** (เดิม fromOffset(170, 38) = คงที่บนจอ → ยิ่งถอยออกไกลยิ่งดูใหญ่ · ผลทดสอบ Studio)
		local gui = Instance.new("BillboardGui")
		gui.Name = "Tag"
		gui.Size = UDim2.fromScale(MOTHER_TAG_SIZE.X, MOTHER_TAG_SIZE.Y)
		gui.StudsOffsetWorldSpace = Vector3.new(0, visualHeight / 2 + 1.6, 0)
		gui.MaxDistance = 120
		gui.Adornee = visual
		gui.Parent = visual

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.4
		label.TextScaled = true
		label.Font = Enum.Font.SourceSansBold
		label.Text = `{if character then character.name else mother.charId} ({class})\n{Config.formatWeight(mother.weight)}`
		label.Parent = gui

		local pivotPosition = visual:GetPivot().Position
		-- ท่าขยับของโมเดลที่ประกอบจาก Part (สัดส่วนของความสูงจริง · ตัวใหญ่ก้าวช้าลง √s แบบเดียวกับอนิเมชันลิง)
		local hover, bob, bobRate = 0, 0, 0
		if motion == "float" then
			hover = MotherModels.FLOAT.HOVER_RATIO * visualHeight
			bob = MotherModels.FLOAT.BOB_RATIO * visualHeight
			bobRate = 1 / MotherModels.FLOAT.PERIOD
		elseif motion == "hop" then
			bob = MotherModels.HOP.HEIGHT_RATIO * visualHeight
			bobRate = MotherModels.HOP.STEPS_PER_SECOND * animSpeed
		end
		local roamer: Roamer = {
			visual = visual,
			origin = pen.plot.center,
			from = pivotPosition,
			to = pivotPosition,
			baseY = pivotPosition.Y,
			motion = motion,
			hover = hover,
			bob = bob,
			bobRate = bobRate,
			phase = rng:NextNumber(0, 10),
			startedAt = now,
			duration = 0.05,
			-- กระจายเวลาออกเดินครั้งแรก ไม่งั้นแม่ทุกตัวจะขยับพร้อมกันเป๊ะ ดูเป็นหุ่นยนต์
			waitUntil = now + rng:NextNumber(0, MAP.Wander.PauseMax),
			tracks = tracks,
			pose = nil,
			playing = nil,
			stops = 0,
			restPoses = getRestPoses(tracks),
			speed = speed,
			animSpeed = animSpeed,
			walkAnimScale = walkAnimScale,
			trackConnections = {},
			inset = inset,
		}
		-- เพิ่งเกิด = ยืนรอออกเดินรอบแรก
		watchTrackEnds(roamer)
		playPose(roamer, "idle")
		pickNextTrip(roamer, roamer.waitUntil)
		table.insert(roamers, roamer)
	end
end

function PenService.clearVisuals(pen: Pen)
	dropRoamersUnder(pen.mothersFolder)
	pen.mothersFolder:ClearAllChildren()
	pen.eggsFolder:ClearAllChildren()
	-- ชื่อเจ้าของเขียนอยู่บนป้ายไม้คอก (ไม่ใช่ป้ายลอย) — คืนคอกแล้วกลับเป็น "ว่าง"
	MapBuilder.setPenOwnerName(pen.index, nil)
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
			-- ⚠️ UI-2: client ต้องรู้ว่าคอกไหนเป็นของตัวเอง — ติดจุดกด E เฉพาะป้ายค่าวิ่ง/อัปคอกของคอกนี้
			-- (แค่ซ่อนปุ่มให้ไม่งง · remote ซื้อไม่ได้อ่านค่านี้ ซื้อได้เหมือนเดิมทุกประการ)
			player:SetAttribute(Config.PEN_INDEX_ATTRIBUTE, pen.index)
			MapBuilder.setPenOwnerName(pen.index, player.DisplayName)
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
	player:SetAttribute(Config.PEN_INDEX_ATTRIBUTE, nil)
	lastMothersByUserId[player.UserId] = nil
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

--------------------------------------------------------------------------------
-- คำสั่ง debug: แถวโชว์โมเดลครบทุกตัวละคร (Studio · สะพาน ServerStorage.EggServiceDebug — docs/debug-commands.md)
--------------------------------------------------------------------------------
-- วางกลางทางเดินกลาง (Config.getSpawnPoint) เรียงตามลำดับดัชนี · ขนาด tier 1 (100 kg) × คลาส = ขนาดเดียวกับในคอก
-- หันหน้า −Z · ป้ายชื่อ/คลาส/จำนวนชิ้นตั้งอยู่หน้าเท้า (อ่านจากฝั่ง −Z) · ภาพล้วน ไม่แตะข้อมูลผู้เล่น
-- เรียกซ้ำ = ลบแถวเดิมแล้ววางใหม่ · ตัวที่ไม่มีโมเดล/mesh ยังโหลดไม่เสร็จ = กล่องสีสำรอง (ป้ายบอก)
-- rig ทุกตัววนท่า เดิน → ยืน → เหวี่ยงแขน (เท่าที่มี) ยืนอยู่กับที่ — ไว้ดูอนิเมชันทีละตัว

local SHOWCASE_NAME = "ModelShowcase" -- Folder ใน Workspace
local SHOWCASE_SPACING = 11 -- studs ระหว่างกลางตัว (ราชาปีศาจวัว tier 1 กว้าง ≈ 7.9)
local SHOWCASE_WEIGHT = 100 -- kg = tier 1
local SHOWCASE_SIGN_SIZE = Vector3.new(9, 1.6, 0.3)
-- rig: วนท่าที่ตัวนั้นมี เดิน → ยืน → เหวี่ยงแขน ท่าละกี่วินาที (ดูอนิเมชันครบทุกท่าโดยไม่ต้องรอแม่เดินในคอก)
local SHOWCASE_POSE_ORDER = { "walk", "idle", "punch" }
local SHOWCASE_POSE_SECONDS = 3

function PenService.debugClearShowcase(): (boolean, string?)
	local existing = Workspace:FindFirstChild(SHOWCASE_NAME)
	if existing then
		existing:Destroy()
		print("[PenService] debugClearShowcase: ลบแถวโชว์โมเดลแล้ว")
		return true, nil
	end
	return true, "ไม่มีแถวโชว์โมเดลอยู่"
end

local function countParts(instance: Instance): number
	local count = if instance:IsA("BasePart") then 1 else 0
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function makeShowcaseSign(position: Vector3, lines: string): Part
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Size = SHOWCASE_SIGN_SIZE
	sign.CFrame = CFrame.new(position)
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.CanTouch = false
	sign.Color = Color3.fromRGB(245, 240, 225)
	sign.Material = Enum.Material.SmoothPlastic
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- ด้าน −Z = ฝั่งคนดู
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- อ่านออกแม้กลางคืน
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.TextColor3 = Color3.fromRGB(30, 30, 35)
	label.Text = lines
	label.Parent = gui
	return sign
end

function PenService.debugShowcaseModels(): (boolean, string?)
	PenService.debugClearShowcase()

	local folder = Instance.new("Folder")
	folder.Name = SHOWCASE_NAME
	local center = Config.getSpawnPoint()
	local total = #Config.CharacterOrder
	local summary: { string } = {}
	local animated: { { model: Model, charId: string } } = {}

	for index, charId in Config.CharacterOrder do
		local character = Config.getCharacter(charId)
		if not character then
			continue
		end
		local x = center.X + (index - (total + 1) / 2) * SHOWCASE_SPACING
		local assetId = character.modelAssetId
		local template = if assetId then getMeshTemplate(assetId) else nil
		local nativeHeight: number? = if assetId and template
			then meshTemplateHeights[assetId] or Config.Balance.VisualScale.MOTHER_MESH_BASE_HEIGHT
			else nil
		local kind = if template then "mesh" else "Part"
		if template == nil then
			template = getPartTemplate(charId)
		end

		local visual: Instance
		local depth: number
		local height: number
		if template then
			local model = buildModelMother(template, SHOWCASE_WEIGHT, character.class, nativeHeight, charId)
			local boxCFrame, boxSize = model:GetBoundingBox()
			local pivotAboveCenter = model:GetPivot().Y - boxCFrame.Y
			-- ปลาลอยเหนือพื้นเท่ากับในคอก (โชว์ท่านิ่ง)
			local lift = if model:GetAttribute("Motion") == "float" then MotherModels.FLOAT.HOVER_RATIO * boxSize.Y else 0
			model:PivotTo(CFrame.new(x, Config.getPenRestingY(boxSize.Y / 2) + pivotAboveCenter + lift, center.Z))
			visual = model
			depth, height = boxSize.Z, boxSize.Y
			if nativeHeight == nil and MotherModels.getAnimations(charId) then
				table.insert(animated, { model = model, charId = charId })
				kind = "Part rig R6"
			end
		else
			kind = "กล่องสำรอง"
			local size = Config.getMotherVisualSize(SHOWCASE_WEIGHT, true)
			local part = Instance.new("Part")
			part.Size = size
			part.Position = Vector3.new(x, Config.getPenRestingY(size.Y / 2), center.Z)
			part.Color = CLASS_COLORS[character.class] or CLASS_COLORS.C
			part.Anchored = true
			part.CanCollide = false
			visual = part
			depth, height = size.Z, size.Y
		end
		visual.Name = charId
		visual.Parent = folder

		local parts = countParts(visual)
		local detail = if kind == "Part" then `{parts} ชิ้น`
			elseif kind == "Part rig R6" then `{parts} ชิ้น · rig R6`
			elseif kind == "mesh" then `mesh {parts} ชิ้น`
			else "ยังไม่มีโมเดล/กำลังโหลด"
		local signPosition = Vector3.new(x, SHOWCASE_SIGN_SIZE.Y / 2, center.Z - depth / 2 - 1.2)
		makeShowcaseSign(signPosition, `{character.name}\n{character.class} · {detail}`).Parent = folder
		table.insert(summary, `{character.name} ({character.class}) {kind} {parts} ชิ้น สูง {string.format("%.1f", height)}`)
	end

	folder.Parent = Workspace
	-- rig: วนท่าเดิน → ยืน → เหวี่ยงแขน (เท่าที่ตัวนั้นมี · LoadAnimation ต้องหลังเข้า Workspace) · ท่าไม่วนในตัว = เล่นใหม่ตอนจบ
	-- ท่าเดินใช้ความเร็วเดียวกับในคอกที่ tier 1 (walkAnimSpeed) · ลบ showcase = model หลุดจาก Workspace → ลูปจบเอง
	for _, entry in animated do
		local tracks = loadPoseTracks(entry.model, MotherModels.getAnimations(entry.charId) :: any)
		if not tracks then
			continue
		end
		local blueprint = MotherModels.getBlueprint(entry.charId)
		local walkSpeed = if blueprint and blueprint.walkAnimSpeed then blueprint.walkAnimSpeed else 1
		local function speedOf(track: AnimationTrack): number
			return if track == tracks.walk then walkSpeed else 1
		end
		local model: Model = entry.model
		local function alive(): boolean
			return model.Parent ~= nil
		end
		local current: AnimationTrack? = nil
		for _, track in tracks do
			track.Stopped:Connect(function()
				if track == current and alive() and track.Length > 0 then
					track:Play(0, 1, speedOf(track))
				end
			end)
		end
		task.spawn(function()
			while alive() do
				local played = false
				for _, pose in SHOWCASE_POSE_ORDER do
					local track = tracks[pose]
					if track and alive() then
						local previous = current
						current = track -- ตั้งก่อนหยุดท่าเก่า (ตัวเล่นซ้ำจะไม่ดึงท่าเก่ากลับ)
						if previous then
							previous:Stop(POSE_FADE_SECONDS)
						end
						track:Play(POSE_FADE_SECONDS, 1, speedOf(track))
						played = true
						task.wait(SHOWCASE_POSE_SECONDS)
					end
				end
				if not played then
					break
				end
			end
		end)
	end
	local text = table.concat(summary, " · ")
	print(`[PenService] debugShowcaseModels: วาง {#summary} ตัวที่ทางเดินกลาง (ยืนฝั่ง −Z หันหน้าเข้าหา) — {text}`)
	return true, text
end

-- ⚠️ ไม่ต่อ Players.PlayerRemoving ที่นี่ — Main.server.lua เป็นคนต่อสายให้
-- ต่อสองที่แล้วลำดับจะกลายเป็นเรื่องบังเอิญ (EggService ต้องเซฟก่อนคอกถูกคืน)

return PenService
