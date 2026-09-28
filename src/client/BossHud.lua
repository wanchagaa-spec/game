--!strict
-- egg-army-game :: ตัวเลขนับถอยหลังบนกำแพงกั้นบอส (Phase 5A)
--
-- กลางคืน 59 → 0 บนผิวหน้ากำแพงกั้น (ฝั่งลานกลาง −X) · กลางวันซ่อน (กำแพงกั้นก็หายไปแล้ว)
-- ⚠️ 5B: กำแพงกั้นย้ายไปปิดช่องทางเข้าเลน (X 157.5–162.5 · 60 × 40) และเป็น**สีขาวทึบ** → ตัวเลข/คำบรรยายใช้สีเข้ม
--   (เดิมเหลืองบนกำแพงแดงโปร่ง — บนพื้นขาวอ่านไม่ออก) · ผิว −X ยังเป็นฝั่งที่ผู้เล่นยืนรอ (หน้าป้อมฝั่งลาน)
-- ⚠️ server เป็นเจ้าของ phase/เวลา — อ่านจาก Attribute ของ ReplicatedStorage[Config.BOSS_STATE_FOLDER]
--   (PhaseEndsAt เป็นเวลา server) แล้วเทียบกับ workspace:GetServerTimeNow() ของเครื่องตัวเอง
--   = ทุกคนเห็นเลขเดียวกันโดยไม่ต้อง sync ทุกวินาที · client ไม่ตัดสินอะไรเลย แค่แสดงผล
-- ⚠️ SurfaceGui อยู่ใน PlayerGui (Adornee = กำแพงกั้น) แบบเดียวกับป้ายบนแมพ (MapSigns) — กำแพงกั้นเป็น
--   ของ server ที่อยู่ตลอด (กลางวันแค่โปร่งใส/ไม่ชน) ตัวเลขจึงติดชิ้นเดิมได้เสมอ
-- เลขคำนวณที่ Config.getBossCountdownValue ที่เดียว (เทสต์นอก Studio ได้)
--
-- ══ 5B: จุดกด E ค้างที่ไข่บอส ══ ติดกับ Part ไข่ของ server (Workspace.Map.BossArena.BossEggs.BossEgg{i})
--   ⚠️ สร้างผ่าน UiKit.prompt() เท่านั้น (OnePerButton — ไข่วางชิดกัน ขึ้นเฉพาะฟองที่ใกล้สุด)
--   เปิดเฉพาะ: บอสตายแล้ว (Attribute BossAlive = false) + ฟองนั้น Status = "resting" + ตัวเองไม่ได้ถือไข่อยู่
--   (Attribute บน Player) · กดครบเวลาแล้วยิงแค่ "ฟองที่ i" — server ตัดสินทุกอย่างเอง (client ปิด prompt เพื่อ UX เท่านั้น)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local BossHud = {}

export type BossState = {
	phase: string?,
	phaseEndsAt: number?,
	bossAlive: boolean?,
}

local RENDER_INTERVAL = 0.2
local PIXELS_PER_STUD = 20
local COUNT_COLOR = Color3.fromRGB(190, 30, 40) -- แดงเข้มบนกำแพงขาว
local CAPTION_COLOR = Color3.fromRGB(40, 40, 55) -- เทาเข้มเกือบดำ
local STROKE_COLOR = Color3.fromRGB(255, 255, 255) -- ขอบขาวบาง ๆ ให้ตัวเลขแยกจากเงาบนผิวกำแพง

local state: BossState = {}
local surface: SurfaceGui? = nil
local countLabel: TextLabel? = nil

-- 5B: จุดกด E ที่ไข่บอส (index → Part ไข่ + prompt) · carrying = ตัวเองถือไข่บอสอยู่
type EggPrompt = { part: BasePart, prompt: ProximityPrompt }
local eggPrompts: { [number]: EggPrompt } = {}
local carrying = false

-- สร้างตัวเลขติดผิวหน้ากำแพงกั้น — เรียกครั้งเดียว (เทสต์เรียกตรงด้วยกำแพงปลอม)
function BossHud.attach(playerGui: Instance, barrier: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BossBarrierCountdown"
	gui.Adornee = barrier
	gui.Face = Enum.NormalId.Left -- ผิว −X = ฝั่งลานกลาง ที่ผู้เล่นยืนรอหน้าป้อม
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = playerGui

	local count = UiKit.label({
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.8, 0.5),
		TextColor3 = COUNT_COLOR,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(count, 4, STROKE_COLOR)
	count.Parent = gui

	local caption = UiKit.label({
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(0.9, 0.12),
		Text = "🌙 บอสตื่นแล้ว — กำแพงเปิดตอนเช้า",
		TextColor3 = CAPTION_COLOR,
	})
	caption.Parent = gui

	surface = gui
	countLabel = count
end

-- 5B: เปิด/ปิดจุดกด E ของไข่ทุกฟองตามสถานะล่าสุด + ชื่อบน prompt = น้ำหนักของฟองนั้น
function BossHud.refreshEggPrompts()
	local bossDead = state.bossAlive == false
	for _, entry in eggPrompts do
		local status = entry.part:GetAttribute("Status")
		local weight = entry.part:GetAttribute("Weight")
		entry.prompt.Enabled = bossDead and status == "resting" and not carrying
		entry.prompt.ObjectText = if type(weight) == "number" and weight > 0
			then `ไข่บอส {Config.formatCoins(weight)} กก.`
			else "ไข่บอส"
	end
end

function BossHud.setState(newState: BossState)
	state = newState
	BossHud.refreshEggPrompts()
end

-- 5B: ตัวเองถือไข่บอสอยู่ไหม (Attribute บน Player ที่ server ตั้ง) — ถืออยู่ = ปิดจุดกดทุกฟอง (ถือได้ทีละฟอง)
function BossHud.setCarrying(value: boolean)
	carrying = value
	BossHud.refreshEggPrompts()
end

-- 5B: ติดจุดกด E ค้างที่ไข่บอส 1 ฟอง · onPick(index) = ยิงคำขอหยิบ (Main ส่ง remote เข้ามา) · ติดซ้ำฟองเดิมไม่ได้
function BossHud.attachEggPrompt(part: BasePart, onPick: (index: number) -> ())
	local index = part:GetAttribute("Index")
	if type(index) ~= "number" or eggPrompts[index] ~= nil then
		return
	end
	local prompt = UiKit.prompt({
		Name = "PickUpBossEgg",
		ActionText = "หยิบไข่บอส",
		ObjectText = "ไข่บอส",
		HoldDuration = Config.Balance.BossCycle.EGG_PICKUP_HOLD_SECONDS,
		MaxActivationDistance = Config.MapDimensions.BossArena.EggPromptDistance,
		Enabled = false,
	})
	prompt.Triggered:Connect(function()
		onPick(index)
	end)
	prompt.Parent = part
	eggPrompts[index] = { part = part, prompt = prompt }
	part:GetAttributeChangedSignal("Status"):Connect(BossHud.refreshEggPrompts)
	part:GetAttributeChangedSignal("Weight"):Connect(BossHud.refreshEggPrompts)
	BossHud.refreshEggPrompts()
end

-- วาดตามเวลา `now` (เวลา server) — กลางคืนโชว์เลข · กลางวันซ่อนทั้งแผ่น
function BossHud.render(now: number)
	local endsAt = state.phaseEndsAt
	local night = state.phase == "night" and type(endsAt) == "number"
	if surface then
		surface.Enabled = night
	end
	if night and countLabel then
		countLabel.Text = tostring(Config.getBossCountdownValue((endsAt :: number) - now))
	end
end

-- ต่อสายของจริง (Main.client.lua) — รอของจาก server เบื้องหลัง ไม่บล็อกสคริปต์หลัก
-- onPickEgg(index) = ยิง PickUpBossEggRequest (5B)
function BossHud.start(playerGui: Instance, onPickEgg: (index: number) -> ())
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(Config.BOSS_STATE_FOLDER)
		local arena = Workspace:WaitForChild("Map"):WaitForChild(Config.BOSS_ARENA_NAME)
		local barrier = arena:WaitForChild(Config.BOSS_BARRIER_NAME) :: BasePart
		BossHud.attach(playerGui, barrier)

		-- 5B: จุดกด E ที่ไข่บอส (Part อยู่ตลอด server แค่ซ่อน/โชว์) + สถานะ "ถือไข่อยู่" ของตัวเอง
		local eggFolder = arena:WaitForChild(Config.BOSS_EGG_FOLDER)
		local function tryAttach(child: Instance)
			if child:IsA("BasePart") then
				BossHud.attachEggPrompt(child, onPickEgg)
			end
		end
		for _, child in eggFolder:GetChildren() do
			tryAttach(child)
		end
		eggFolder.ChildAdded:Connect(tryAttach)
		local localPlayer = Players.LocalPlayer
		local function readCarrying()
			BossHud.setCarrying(localPlayer:GetAttribute(Config.BOSS_EGG_CARRY_ATTRIBUTE) == true)
		end
		readCarrying()
		localPlayer:GetAttributeChangedSignal(Config.BOSS_EGG_CARRY_ATTRIBUTE):Connect(readCarrying)

		local function readState()
			BossHud.setState({
				phase = folder:GetAttribute("Phase"),
				phaseEndsAt = folder:GetAttribute("PhaseEndsAt"),
				bossAlive = folder:GetAttribute("BossAlive"),
			})
		end
		readState()
		folder.AttributeChanged:Connect(readState)

		while true do
			BossHud.render(Workspace:GetServerTimeNow())
			task.wait(RENDER_INTERVAL)
		end
	end)
end

return BossHud
