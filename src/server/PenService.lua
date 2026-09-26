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
-- ⚠️ visual เป็น Part (กล่องสีเดิม) หรือ Model (โมเดล mesh ที่ import มา — ดู
-- Character.modelAssetId) ก็ได้ ทั้งคู่เป็น PVInstance จึงใช้ PivotTo/GetPivot ร่วมกันได้
type Roamer = {
	visual: Model | BasePart,
	origin: Vector3, -- กึ่งกลางแปลงที่แม่ตัวนี้อยู่
	from: Vector3,
	to: Vector3,
	startedAt: number, -- os.clock() ตอนเริ่มเดินรอบนี้
	duration: number, -- ใช้เวลาเดินกี่วินาที
	waitUntil: number, -- os.clock() ที่จะออกเดินรอบถัดไป
	-- อนิเมชันตามท่า (walk/idle/sit) — nil = ไม่มีอนิเมชัน (กล่องสี หรือตัวละครที่ไม่ได้ใส่ไว้)
	tracks: { [string]: AnimationTrack }?,
	pose: string?, -- ท่าที่ขอล่าสุด (กันสั่งเล่นซ้ำทุก tick)
	playing: AnimationTrack?, -- ท่าที่เล่นอยู่จริง (อาจเป็นท่าสำรอง ถ้าท่าที่ขอไม่มี)
	stops: number, -- นับจำนวนครั้งที่หยุดพัก ไว้สลับ ยืนพัก/นั่ง
	speed: number, -- studs/วิ (กล่องสี = MAP.Wander.Speed · โมเดล mesh = โตตามขนาดตัว)
	animSpeed: number, -- ความเร็วเล่นอนิเมชัน (1 = ปกติ · ตัวใหญ่เล่นช้าลง ก้าวยาวขึ้น)
	inset: number, -- ระยะเว้นจากขอบคอก = ครึ่งความกว้างตัว กันตัวใหญ่ยื่นทะลุรั้ว
}

-- เวลาเฟดตอนเปลี่ยนท่า — สั้นพอไม่ให้ท่าเดินค้างตอนหยุด แต่ไม่กระตุกเปลี่ยนทันที
local POSE_FADE_SECONDS = 0.25

-- เปลี่ยนท่า — ขาดท่าที่ขอ (เช่นไม่ได้ใส่ sit) ใช้ท่ายืนพักแทน · ท่าเดินไม่มีท่าสำรอง
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
	if roamer.playing then
		roamer.playing:Stop(POSE_FADE_SECONDS)
	end
	if nextTrack then
		nextTrack:Play(POSE_FADE_SECONDS, 1, roamer.animSpeed)
	end
	roamer.playing = nextTrack
end

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
	local from = roamer.visual:GetPivot().Position
	local distance = (Vector3.new(target.X, from.Y, target.Z) - from).Magnitude

	roamer.from = from
	roamer.to = Vector3.new(target.X, from.Y, target.Z)
	roamer.startedAt = now
	-- ระยะ ÷ ความเร็ว = เวลาที่ใช้ · กันหาร 0 ตอนสุ่มได้จุดเดิมเป๊ะ
	roamer.duration = math.max(distance / roamer.speed, 0.05)
end

local function updateWander()
	local now = os.clock()

	for _, roamer in roamers do
		local visual = roamer.visual
		if visual.Parent == nil then
			continue -- ถูกเก็บไปแล้ว รอบถัดไปจะถูกกวาดออกจากตาราง
		end

		if now < roamer.waitUntil then
			continue -- ยืนพักอยู่ (ท่ายืน/นั่งตั้งไว้แล้วตอนถึงจุดหมาย)
		end

		playPose(roamer, "walk")

		local elapsed = now - roamer.startedAt
		local alpha = math.clamp(elapsed / roamer.duration, 0, 1)
		local position = roamer.from:Lerp(roamer.to, alpha)

		-- หันหน้าไปทางที่เดิน ให้ดูมีชีวิตขึ้นโดยไม่ต้องมี Humanoid
		local direction = roamer.to - roamer.from
		if direction.Magnitude > 0.01 then
			visual:PivotTo(CFrame.lookAt(position, position + direction.Unit))
		else
			-- ยังไม่มีทิศทางเดิน (เพิ่งสปอน) — ขยับตำแหน่งอย่างเดียว คงการหันหน้าเดิมไว้
			visual:PivotTo(visual:GetPivot().Rotation + position)
		end

		if alpha >= 1 then
			-- ถึงแล้ว หยุดพักสักครู่ค่อยออกเดินใหม่ · สลับท่า ยืนพัก → นั่ง → ยืนพัก ...
			roamer.stops += 1
			playPose(roamer, if roamer.stops % 2 == 0 then "sit" else "idle")
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
		if roamers[index].visual:IsDescendantOf(folder) then
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
			print(`[PenService] โหลด modelAssetId {assetId} สำเร็จ — วาดคอกใหม่`)
			redrawPensUsing(assetId)
		else
			failedMeshAssets[assetId] = true
		end
	end)
	return nil
end

-- clone จากต้นแบบแล้วสเกลตามน้ำหนักแม่ — ไม่ yield
-- คืน (โมเดล, sizeScale) · sizeScale = ใหญ่กว่าขนาด tier 1 กี่เท่า (ไว้คิดความเร็วเดิน/ก้าว)
local function buildMeshMother(template: Model, weight: number, assetId: number): (Model, number)
	local model = template:Clone()
	local visualScale = Config.Balance.VisualScale

	-- ⚠️ สเกลแบบสัดส่วนเดียวกันทุกแกน (ไม่ยืด/บีบ) ต่างจากกล่องเดิมที่ยืด Vector3 อิสระ 3 แกนได้
	-- เพราะโมเดล mesh จริงยืดแกนเดียวแล้วเสียรูปทันที
	-- ⚠️ เทียบกับความสูงต้นฉบับ ไม่ใช่สเกลดิบ — ไฟล์แต่ละไฟล์ import มาขนาดไม่เท่ากัน
	-- (กอริลลาเคยออกมาเล็กกว่าคนมากทั้งที่สเกล 1:1) ตอนนี้ tier 1 สูง MOTHER_MESH_BASE_HEIGHT เสมอ
	local sizeScale = Config.getVisualScaleMultiplier(weight) * visualScale.MOTHER_PEN_SHRINK
	local nativeHeight = meshTemplateHeights[assetId] or visualScale.MOTHER_MESH_BASE_HEIGHT
	local scale = visualScale.MOTHER_MESH_BASE_HEIGHT / nativeHeight * sizeScale
	local scaleOk = pcall(function()
		model:ScaleTo(scale)
	end)
	if not scaleOk then
		warn(`[PenService] Model:ScaleTo ล้มเหลวกับ modelAssetId {assetId} — ใช้ขนาดต้นฉบับที่ import มาแทน`)
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
			-- ⚠️ ค่านี้ไม่ส่งไป client — ท่าที่ publish มาแบบไม่วนจะเล่นรอบเดียวแล้วค้างบนจอผู้เล่น
			-- ต้องเปิด Loop ตอน publish ใน Animation Editor ด้วย
			track.Looped = true
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

		-- ⚠️ ลองใช้โมเดล mesh ที่ import มาก่อน (Character.modelAssetId) ล้มเหลว/ไม่มี
		-- ค่อยตกกลับไปกล่องสีเดิม — ต้องมี resting Y ที่ตรงกับรูปทรงจริงของแต่ละแบบ
		-- ⚠️ visualHeight คำนวณแยกต่อสาขา ไม่เรียก GetBoundingBox() รวมท้ายสุด เพราะเมธอดนี้
		-- มีแค่ใน Model ไม่มีใน BasePart (สาขา fallback เป็น Part เดี่ยว ๆ)
		local visual: Model | BasePart
		local visualHeight: number
		local restingY: number
		local tracks: { [string]: AnimationTrack }? = nil
		local speed = MAP.Wander.Speed
		local animSpeed = 1
		local inset: number
		local spot: Vector3

		local assetId = if character then character.modelAssetId else nil
		-- ยังโหลดไม่เสร็จ/ล้มเหลว = nil → วาดกล่องสีไปก่อน (ไม่ yield)
		local template = if assetId then getMeshTemplate(assetId) else nil

		if assetId and template then
			local meshModel, sizeScale = buildMeshMother(template, mother.weight, assetId)
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
			tracks = loadPoseTracks(meshModel, if character then character.animationIds else nil)
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

		local gui = Instance.new("BillboardGui")
		gui.Name = "Tag"
		gui.Size = UDim2.fromOffset(170, 38)
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
		local roamer: Roamer = {
			visual = visual,
			origin = pen.plot.center,
			from = pivotPosition,
			to = pivotPosition,
			startedAt = now,
			duration = 0.05,
			-- กระจายเวลาออกเดินครั้งแรก ไม่งั้นแม่ทุกตัวจะขยับพร้อมกันเป๊ะ ดูเป็นหุ่นยนต์
			waitUntil = now + rng:NextNumber(0, MAP.Wander.PauseMax),
			tracks = tracks,
			pose = nil,
			playing = nil,
			stops = 0,
			speed = speed,
			animSpeed = animSpeed,
			inset = inset,
		}
		-- เพิ่งเกิด = ยืนรอออกเดินรอบแรก
		playPose(roamer, "idle")
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

-- ⚠️ ไม่ต่อ Players.PlayerRemoving ที่นี่ — Main.server.lua เป็นคนต่อสายให้
-- ต่อสองที่แล้วลำดับจะกลายเป็นเรื่องบังเอิญ (EggService ต้องเซฟก่อนคอกถูกคืน)

return PenService
