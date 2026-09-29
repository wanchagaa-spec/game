--!strict
-- egg-army-game :: ท้องฟ้ากลางคืน — กลางคืนของวงจรบอสเปลี่ยนฟ้าเป็นพระจันทร์ + มืดลง (ผู้ใช้สั่ง)
--
-- ⚠️ ภาพล้วนฝั่ง client — Lighting ที่ client แก้ไม่ replicate (แต่ละเครื่องปรับของตัวเอง) · ไม่แตะการตัดสินใด ๆ ของ server
-- อ่าน Phase จาก Attribute ของ ReplicatedStorage[Config.BOSS_STATE_FOLDER] (ตัวเดียวกับ BossHud) → ทุกคนมืด/สว่างพร้อมกัน
-- ค่ากลางวัน = ค่าที่อ่านจาก Lighting ตอนเริ่ม (server ไม่เคยแก้ Lighting) → เช้ากลับค่าเดิมเป๊ะ · ค่ากลางคืนอยู่ที่ Config.NightSky
-- เวลาในวัน (ClockTime) เดินไปข้างหน้าเสมอ: กลางวัน → ตกดิน → เที่ยงคืน · เช้า = เที่ยงคืน → รุ่งเช้า → เวลากลางวันเดิม (ไม่ย้อน)
-- พระจันทร์: มี Sky อยู่แล้ว = ขยายดวงจันทร์ชั่วคราว (เช้าคืนขนาดเดิม) · ไม่มี Sky = สร้างชั่วคราวตอนกลางคืน (เช้าลบทิ้ง)
-- ตัวเลขนับถอยหลังบนกำแพงกั้น (BossHud) ตั้ง LightInfluence = 0 ไว้แล้ว → มืดแค่ไหนก็อ่านออก

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local NightSky = {}

export type SkyValues = {
	clockTime: number,
	brightness: number,
	exposure: number,
	ambient: Color3,
	outdoorAmbient: Color3,
}

local CREATED_SKY_NAME = "NightSkyMoon" -- Sky ที่สร้างเองตอนกลางคืน (ไม่มี Sky เดิมในเกม)

local lighting: Instance? = nil
local dayValues: SkyValues? = nil
local current: SkyValues? = nil -- ค่าที่ใส่ Lighting ล่าสุด (จุดเริ่มของการเปลี่ยนรอบถัดไป)
local fromValues: SkyValues? = nil
local toValues: SkyValues? = nil
local transitionStart = 0
local transitionSeconds = 0
local transitionDone = true
local phase: string? = nil
local createdSky: Instance? = nil
local originalMoonSize: number? = nil

-- อ่านค่าปัจจุบันของ Lighting (ใช้จำค่ากลางวันตอนเริ่ม)
function NightSky.read(target: any): SkyValues
	return {
		clockTime = target.ClockTime,
		brightness = target.Brightness,
		exposure = target.ExposureCompensation,
		ambient = target.Ambient,
		outdoorAmbient = target.OutdoorAmbient,
	}
end

function NightSky.write(target: any, values: SkyValues)
	target.ClockTime = values.clockTime
	target.Brightness = values.brightness
	target.ExposureCompensation = values.exposure
	target.Ambient = values.ambient
	target.OutdoorAmbient = values.outdoorAmbient
end

-- ค่ากลางคืน — คิดจากค่ากลางวันที่อ่านไว้ (ความสว่าง × สเกล · exposure + offset) + สี ambient แสงจันทร์จาก Config
function NightSky.nightValues(day: SkyValues): SkyValues
	local sky = Config.NightSky
	return {
		clockTime = sky.CLOCK_TIME,
		brightness = day.brightness * sky.BRIGHTNESS_SCALE,
		exposure = day.exposure + sky.EXPOSURE_OFFSET,
		ambient = sky.AMBIENT,
		outdoorAmbient = sky.OUTDOOR_AMBIENT,
	}
end

-- เวลาในวันระหว่างเปลี่ยน — เดินไปข้างหน้าเสมอ (from → to ผ่านเที่ยงคืนได้) · t 0..1 · คืนค่า 0 ≤ x < 24
function NightSky.forwardClock(from: number, to: number, t: number): number
	local distance = (to - from) % 24
	return (from + distance * t) % 24
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(lerp(a.R, b.R, t), lerp(a.G, b.G, t), lerp(a.B, b.B, t))
end

-- ค่าระหว่างทาง (t 0 = from · 1 = to) · เวลาในวันเดินหน้า ค่าอื่นไล่เส้นตรง
function NightSky.mix(from: SkyValues, to: SkyValues, t: number): SkyValues
	return {
		clockTime = NightSky.forwardClock(from.clockTime, to.clockTime, t),
		brightness = lerp(from.brightness, to.brightness, t),
		exposure = lerp(from.exposure, to.exposure, t),
		ambient = lerpColor(from.ambient, to.ambient, t),
		outdoorAmbient = lerpColor(from.outdoorAmbient, to.outdoorAmbient, t),
	}
end

-- เร่งช่วงต้น-ผ่อนช่วงท้าย (smoothstep) — ฟ้าไม่เปลี่ยนกระตุกตอนเริ่ม/จบ
local function ease(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- พระจันทร์: กลางคืน = ขยาย (หรือสร้าง Sky ชั่วคราว) · กลางวัน = คืนสภาพเดิม
local function setMoon(night: boolean)
	local target = lighting
	if not target then
		return
	end
	local sky = target:FindFirstChildOfClass("Sky")
	if night then
		if not sky then
			local created = Instance.new("Sky")
			created.Name = CREATED_SKY_NAME
			created.Parent = target
			createdSky = created
			sky = created
		elseif sky ~= createdSky and originalMoonSize == nil then
			originalMoonSize = (sky :: any).MoonAngularSize
		end
		(sky :: any).MoonAngularSize = Config.NightSky.MOON_ANGULAR_SIZE
	else
		if createdSky then
			createdSky:Destroy()
			createdSky = nil
		elseif sky and originalMoonSize ~= nil then
			(sky :: any).MoonAngularSize = originalMoonSize
		end
		originalMoonSize = nil
	end
end

-- เริ่มใช้กับ Lighting นี้ (จำค่ากลางวันไว้) — เรียกก่อน setPhase/step
function NightSky.attach(target: any)
	lighting = target
	dayValues = NightSky.read(target)
	current = dayValues
	fromValues, toValues = nil, nil
	transitionDone = true
	phase = "day"
	createdSky = nil
	originalMoonSize = nil
end

-- ตั้ง phase ใหม่ ("day" | "night" · อื่น ๆ = กลางวัน) · instant = ใส่ค่าทันที (เข้าเกมกลางคืน) · คืน true ถ้าเปลี่ยนจริง
function NightSky.setPhase(newPhase: any, now: number, instant: boolean?): boolean
	local day = dayValues
	if not lighting or not day then
		return false
	end
	local night = newPhase == "night"
	local normalized = if night then "night" else "day"
	if normalized == phase then
		return false
	end
	phase = normalized
	if night then
		setMoon(true)
	end
	fromValues = current or day
	toValues = if night then NightSky.nightValues(day) else day
	transitionStart = now
	transitionSeconds = if instant then 0 else Config.NightSky.TRANSITION_SECONDS
	transitionDone = false
	NightSky.step(now)
	return true
end

-- เดินการเปลี่ยนฟ้าไปถึงเวลา now · คืนความคืบหน้า 0..1 (1 = ถึงปลายทางแล้ว / ไม่มีอะไรต้องทำ)
function NightSky.step(now: number): number
	local target = lighting
	local from, to = fromValues, toValues
	if transitionDone or not target or not from or not to then
		return 1
	end
	local progress = if transitionSeconds <= 0 then 1 else math.clamp((now - transitionStart) / transitionSeconds, 0, 1)
	local values = if progress >= 1 then to else NightSky.mix(from, to, ease(progress))
	NightSky.write(target, values)
	current = values
	if progress >= 1 then
		transitionDone = true
		if phase == "day" then
			setMoon(false) -- สว่างเต็มแล้วค่อยคืนขนาดพระจันทร์ (ระหว่างรุ่งเช้ายังเห็นดวงใหญ่อยู่)
		end
	end
	return progress
end

function NightSky.getPhase(): string?
	return phase
end

-- ต่อสายของจริง (Main.client.lua) — รอ BossState จาก server เบื้องหลัง ไม่บล็อกสคริปต์หลัก
function NightSky.start()
	task.spawn(function()
		local Lighting = game:GetService("Lighting")
		NightSky.attach(Lighting)
		local folder = ReplicatedStorage:WaitForChild(Config.BOSS_STATE_FOLDER)
		-- เข้าเกมตอนกลางคืน = มืดทันที (ไม่ค่อย ๆ มืดหลังเข้ามาแล้ว)
		NightSky.setPhase(folder:GetAttribute("Phase"), os.clock(), true)
		folder:GetAttributeChangedSignal("Phase"):Connect(function()
			NightSky.setPhase(folder:GetAttribute("Phase"), os.clock())
		end)
		while true do
			task.wait()
			NightSky.step(os.clock())
		end
	end)
end

return NightSky
