--!strict
-- egg-army-game :: ตัวเลขนับถอยหลังบนกำแพงกั้นบอส (Phase 5A)
--
-- กลางคืน 59 → 0 บนผิวหน้ากำแพงกั้น (ฝั่งลานคอก −X) · กลางวันซ่อน (กำแพงกั้นก็หายไปแล้ว)
-- ⚠️ server เป็นเจ้าของ phase/เวลา — อ่านจาก Attribute ของ ReplicatedStorage[Config.BOSS_STATE_FOLDER]
--   (PhaseEndsAt เป็นเวลา server) แล้วเทียบกับ workspace:GetServerTimeNow() ของเครื่องตัวเอง
--   = ทุกคนเห็นเลขเดียวกันโดยไม่ต้อง sync ทุกวินาที · client ไม่ตัดสินอะไรเลย แค่แสดงผล
-- ⚠️ SurfaceGui อยู่ใน PlayerGui (Adornee = กำแพงกั้น) แบบเดียวกับป้ายบนแมพ (MapSigns) — กำแพงกั้นเป็น
--   ของ server ที่อยู่ตลอด (กลางวันแค่โปร่งใส/ไม่ชน) ตัวเลขจึงติดชิ้นเดิมได้เสมอ
-- เลขคำนวณที่ Config.getBossCountdownValue ที่เดียว (เทสต์นอก Studio ได้)

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
local COUNT_COLOR = Color3.fromRGB(255, 235, 120)

local state: BossState = {}
local surface: SurfaceGui? = nil
local countLabel: TextLabel? = nil

-- สร้างตัวเลขติดผิวหน้ากำแพงกั้น — เรียกครั้งเดียว (เทสต์เรียกตรงด้วยกำแพงปลอม)
function BossHud.attach(playerGui: Instance, barrier: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BossBarrierCountdown"
	gui.Adornee = barrier
	gui.Face = Enum.NormalId.Left -- ผิว −X = ฝั่งที่ผู้เล่นยืนรอหน้าป้อม
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
	UiKit.textStroke(count, 6)
	count.Parent = gui

	local caption = UiKit.label({
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(0.9, 0.12),
		Text = "🌙 บอสตื่นแล้ว — กำแพงเปิดตอนเช้า",
	})
	UiKit.textStroke(caption, 3)
	caption.Parent = gui

	surface = gui
	countLabel = count
end

function BossHud.setState(newState: BossState)
	state = newState
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
function BossHud.start(playerGui: Instance)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(Config.BOSS_STATE_FOLDER)
		local arena = Workspace:WaitForChild("Map"):WaitForChild(Config.BOSS_ARENA_NAME)
		local barrier = arena:WaitForChild(Config.BOSS_BARRIER_NAME) :: BasePart
		BossHud.attach(playerGui, barrier)

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
