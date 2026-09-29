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
-- ══ 5B: จุดกด E ค้างที่ไข่บอส ══ ติดกับ Part ไข่ของ server (Workspace.Map.BossArena.BossEggs.BossEgg{ห้อง}_{i})
--   ⚠️ สร้างผ่าน UiKit.prompt() เท่านั้น (OnePerButton — ไข่วางชิดกัน ขึ้นเฉพาะฟองที่ใกล้สุด)
--   เปิดเฉพาะ: บอส**ห้องนั้น**ตายแล้ว (Attribute BossAlive{ห้อง} = false · 5B-2) + ฟองนั้น Status = "resting"
--   + ตัวเองไม่ได้ถือไข่อยู่ (Attribute บน Player) · กดครบเวลาแล้วยิงแค่ "ฟองที่ i" — server ตัดสินทุกอย่างเอง
--   (ห้องไหน server ดูจากตำแหน่งตัวละครเอง · client ปิด prompt เพื่อ UX เท่านั้น)
-- ══ 5B-2: server จับเวลากดค้างเอง ══ prompt เป็นของ client → server ไม่เห็นการกดค้าง
--   จึงยิง BossEggHoldRequest(i, true) ตอนเริ่มกด (PromptButtonHoldBegan) · (i, false) ตอนปล่อย (PromptButtonHoldEnded)
--   server จดเวลาของตัวเองแล้วเทียบตอนหยิบ — ยิงหยิบตรง ๆ โดยไม่กดค้างครบ = ถูกปฏิเสธ
-- ══ 5C: เลขดาเมจเด้งเหนือบอสตอนโดน ══ เทียบ Attribute BossHp{ห้อง} (server ตั้งทุกครั้งที่ตีโดน) กับค่าก่อนหน้า
--   ลดลง = มีคนตีโดน → onBossHit(ห้อง, ดาเมจ) (Main วาดเลขลอยด้วย CombatEffects) · เพิ่มขึ้น (บอสเกิด/ฟื้นกลางคืน) = ไม่เด้ง
--   ภาพล้วน ไม่ตัดสินอะไร · ตีโดนหลายครั้งในรอบ replicate เดียวกัน = รวมเป็นเลขเดียว (ยอมรับ · แบบเดียวกับ CombatEffects)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local BossHud = {}

export type BossState = {
	phase: string?,
	phaseEndsAt: number?,
	-- 5B-2: บอสแต่ละห้องยังอยู่ไหม (ห้อง → Attribute BossAlive{ห้อง}) · ไม่มีค่า = ยังไม่รู้ (ถือว่ายังหยิบไม่ได้)
	bossAlive: { [number]: boolean? }?,
}

local RENDER_INTERVAL = 0.2
-- ⚠️ 5B-fix (ผู้ใช้สั่ง "ขยายตัวเลขขึ้น 4 เท่า"): TextScaled ของ Roblox **ตันที่ 100 px** ไม่ว่ากรอบจะใหญ่แค่ไหน
--   เดิม 20 px/stud → ตัวเลขสูงได้แค่ 100 px = 5 studs (กรอบ Count สูง 20 studs แต่ตัวอักษรตันก่อน)
--   ลดเหลือ 5 px/stud → 100 px = 20 studs = **ใหญ่ขึ้น 4 เท่า** เต็มกรอบ Count (ครึ่งความสูงกำแพงกั้น 40)
--   คำบรรยายไม่ตันเพดาน จึงขนาดเท่าเดิมตามกรอบ (แค่ความคมลดลงเล็กน้อย)
local PIXELS_PER_STUD = 5
local COUNT_COLOR = Color3.fromRGB(190, 30, 40) -- แดงเข้มบนกำแพงขาว
local CAPTION_COLOR = Color3.fromRGB(40, 40, 55) -- เทาเข้มเกือบดำ
local STROKE_COLOR = Color3.fromRGB(255, 255, 255) -- ขอบขาวบาง ๆ ให้ตัวเลขแยกจากเงาบนผิวกำแพง

local state: BossState = {}
local surface: SurfaceGui? = nil
local countLabel: TextLabel? = nil

-- 5B: จุดกด E ที่ไข่บอส (Part ไข่ → ห้อง + prompt) · carrying = ตัวเองถือไข่บอสอยู่
-- 5B-2: ไข่มีทุกห้อง (9 × 6) → key เป็น Part ไม่ใช่ index (index ซ้ำกันข้ามห้อง)
type EggPrompt = { part: BasePart, room: number, prompt: ProximityPrompt }
local eggPrompts: { [BasePart]: EggPrompt } = {}
local carrying = false
-- 5C: HP ล่าสุดที่เห็นของบอสแต่ละห้อง (เทียบหาดาเมจที่เพิ่งโดน)
local lastBossHp: { [number]: number } = {}

-- 5C: HP บอสห้องนี้เปลี่ยน → คืนดาเมจที่เพิ่งโดน (ลดลงจากค่าก่อนหน้า) · ค่าแรก/เพิ่มขึ้น/ค่าแปลก = nil (ไม่เด้งเลข)
function BossHud.onBossHpChanged(room: number, hp: any): number?
	if type(hp) ~= "number" or hp ~= hp then
		return nil
	end
	local before = lastBossHp[room]
	lastBossHp[room] = hp
	if before ~= nil and hp < before then
		return before - hp
	end
	return nil
end

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

-- 5B: เปิด/ปิดจุดกด E ของไข่ทุกฟองตามสถานะล่าสุด · 5B-2: ดูบอส**ห้องของฟองนั้น**
-- ⚠️ 5B-fix (ผู้ใช้สั่ง "ให้ผู้เล่นลุ้น"): ไม่โชว์น้ำหนักบน prompt — server ก็ไม่ส่งน้ำหนักมาแล้ว (เห็นแค่ขนาดไข่)
function BossHud.refreshEggPrompts()
	local alive = state.bossAlive or {}
	for _, entry in eggPrompts do
		local bossDead = alive[entry.room] == false
		local status = entry.part:GetAttribute("Status")
		entry.prompt.Enabled = bossDead and status == "resting" and not carrying
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
-- 5B-2: onHold(index, holding) = บอก server ว่าเริ่มกด/ปล่อย (server จับเวลาเอง) · Attribute Room บอกห้องของฟองนี้
function BossHud.attachEggPrompt(
	part: BasePart,
	onPick: (index: number) -> (),
	onHold: ((index: number, holding: boolean) -> ())?
)
	local index = part:GetAttribute("Index")
	local room = part:GetAttribute("Room")
	if type(index) ~= "number" or type(room) ~= "number" or eggPrompts[part] ~= nil then
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
	if onHold then
		prompt.PromptButtonHoldBegan:Connect(function()
			onHold(index, true)
		end)
		prompt.PromptButtonHoldEnded:Connect(function()
			onHold(index, false)
		end)
	end
	prompt.Triggered:Connect(function()
		onPick(index)
	end)
	prompt.Parent = part
	eggPrompts[part] = { part = part, room = room, prompt = prompt }
	part:GetAttributeChangedSignal("Status"):Connect(BossHud.refreshEggPrompts)
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
-- onPickEgg(index) = ยิง PickUpBossEggRequest (5B) · onHoldEgg(index, holding) = ยิง BossEggHoldRequest (5B-2)
-- 5C: onBossHit(ห้อง, ดาเมจ) = เด้งเลขดาเมจเหนือบอสห้องนั้น (optional — ไม่ส่ง = ไม่เด้ง)
function BossHud.start(
	playerGui: Instance,
	onPickEgg: (index: number) -> (),
	onHoldEgg: (index: number, holding: boolean) -> (),
	onBossHit: ((room: number, damage: number) -> ())?
)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(Config.BOSS_STATE_FOLDER)
		local arena = Workspace:WaitForChild("Map"):WaitForChild(Config.BOSS_ARENA_NAME)
		local barrier = arena:WaitForChild(Config.BOSS_BARRIER_NAME) :: BasePart
		BossHud.attach(playerGui, barrier)

		-- 5B: จุดกด E ที่ไข่บอส (Part อยู่ตลอด server แค่ซ่อน/โชว์) + สถานะ "ถือไข่อยู่" ของตัวเอง
		local eggFolder = arena:WaitForChild(Config.BOSS_EGG_FOLDER)
		local function tryAttach(child: Instance)
			if child:IsA("BasePart") then
				BossHud.attachEggPrompt(child, onPickEgg, onHoldEgg)
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
			local alive: { [number]: boolean? } = {}
			for room = 1, Config.Balance.Stage.COUNT do
				local value = folder:GetAttribute(Config.getBossStateAttribute("BossAlive", room))
				alive[room] = if type(value) == "boolean" then value else nil
			end
			BossHud.setState({
				phase = folder:GetAttribute("Phase"),
				phaseEndsAt = folder:GetAttribute("PhaseEndsAt"),
				bossAlive = alive,
			})
		end
		readState()
		-- 5C: จำ HP ตั้งต้นของทุกห้อง (ค่าแรกไม่เด้งเลข)
		for room = 1, Config.Balance.Stage.COUNT do
			BossHud.onBossHpChanged(room, folder:GetAttribute(Config.getBossStateAttribute("BossHp", room)))
		end
		-- อ่านใหม่เฉพาะค่าที่ใช้จริง (phase · เวลา · บอสห้องไหนตาย) — HP เปลี่ยนทุกครั้งที่มีคนตี ไม่ต้องไล่ 54 ฟองใหม่
		folder.AttributeChanged:Connect(function(name: string)
			if name == "Phase" or name == "PhaseEndsAt" or string.sub(name, 1, #"BossAlive") == "BossAlive" then
				readState()
				return
			end
			-- 5C: HP ห้องไหนลด → เด้งเลขดาเมจเหนือบอสห้องนั้น ("BossHp3" · ไม่ใช่ "BossMaxHp3")
			local room = tonumber(string.match(name, "^BossHp(%d+)$"))
			if room then
				local damage = BossHud.onBossHpChanged(room, folder:GetAttribute(name))
				if damage and onBossHit then
					onBossHit(room, damage)
				end
			end
		end)

		while true do
			BossHud.render(Workspace:GetServerTimeNow())
			task.wait(RENDER_INTERVAL)
		end
	end)
end

return BossHud
