--!strict
-- egg-army-game :: Client entry point
--
-- UI-1 (จัดหน้าจอใหม่ · แผน 5 รอบอยู่ใน docs/ui-overhaul-plan.md) — ไฟล์นี้ "ต่อสาย" เป็นหลัก:
--   Hotbar     — ช่องถือของล่างจอ (มือถือ 5 · PC 10)
--   BagWindow  — หน้าต่างกระเป๋า 3 แท็บ (สัตว์เลี้ยง · ไข่ · ไอเทม) + หน้ารายละเอียด
--   SidePanels — ปุ่มขวา (ไข่ / เท้า) + แผงไข่ที่กำลังฟัก / แม่ในคอก
--   MapSigns   — UI-2: ป้ายอัปดาเมจ/ค่าวิ่ง/อัปคอกบนแมพ (กด E) + จุดเปิดร้านขายแม่
--   SellWindow — UI-2: หน้าต่างร้านขายแม่ (ติ๊กหลายตัว + กล่องยืนยันครั้งเดียว)
--   SummonWindow — UI-3: หน้าต่างแท่นอัญเชิญ (แท็บแม่/ลูก · ติ๊กเรียงลำดับ · ส่งไปรบ/หยุดอัญเชิญ)
--   IndexWindow — UI-4: หน้าต่างดัชนี (แท็บคลาส · เคยได้ = รูป / ยังไม่ได้ = เงา · จุดแดงบนปุ่มเมื่อได้ตัวใหม่)
--   RobuxShopWindow — UI-5: ร้านค้า Robux (ไข่ตำนาน · ทะลุเพดานดาเมจ/ความเร็ว · เร่งฟักไข่ทั้งหมด)
--   WeaponShopWindow — 5C: ร้านกระบอง 10 ขั้น (กด E ที่แผง "ซื้ออาวุธ" · ซื้อได้แค่ขั้นถัดไป)
--   ที่เหลืออยู่ในไฟล์นี้: ปุ่มกระเป๋าแถบบน · ปุ่มร้านค้า · ปุ่มดัชนี · เลเวลมุมล่างซ้าย ·
--   ข้อความแจ้งผล (toast) · HUD การรบ · popup ผ่านด่าน
--
-- ⚠️ UI-3: แผง TEMP (อัญเชิญ + กองลูก) · กล่องยืนยันส่งแม่ทีละตัว · แผงจัดคิวปล่อยใกล้จุดปล่อย **ลบแล้ว**
--   ทั้งหมดย้ายไปอยู่ในหน้าต่างแท่นอัญเชิญ (SummonWindow · เปิดด้วย E ค้างที่แท่นปากเลน)
--
-- ⚠️ UI-5: หน้าต่าง "เร็วๆ นี้" (placeholder ของปุ่มร้านค้า) **ลบแล้ว** แทนที่ด้วย RobuxShopWindow จริง
-- การซื้อทุกอย่างในหน้าต่างนี้ยิง MarketplaceService:PromptProductPurchase ตรง ๆ (ไม่ใช่ FireServer) —
-- server เข้ามาเกี่ยวตอน ProcessReceipt เท่านั้น (ดู EggService.processReceipt)
--
-- client ไม่ตัดสินอะไรเองเลย: กดปุ่ม = ส่งคำขอไป server แล้วรอฟังผลกลับมา
-- ตัวเลขที่เห็นบนจอเป็นค่าที่ server ส่งมา (นับถอยหลังเวลาฟักเองระหว่างรอบ sync เท่านั้น)

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
-- ⚠️ ใช้ WaitForChild ไม่ใช่ `script.Parent.WallRenderer` ตรง ๆ
-- StarterPlayerScripts ถูก copy ไปเป็น PlayerScripts ตอนผู้เล่นเข้าเกม
-- และของข้างในไม่ได้มาถึงพร้อมกันเสมอ — สคริปต์นี้เริ่มทำงานได้ก่อนพี่น้องของมันจะมาครบ
-- อ้างตรง ๆ แล้วเจอจังหวะนั้น = client พังตั้งแต่บรรทัดแรก UI ไม่ขึ้นเลยสักอย่าง
local WallRenderer = require(script.Parent:WaitForChild("WallRenderer"))
local TroopRenderer = require(script.Parent:WaitForChild("TroopRenderer"))
-- ⚠️ Phase 3B-2: เลขความเสียหายลอย + burst ตอนกระทบ — client-only visual ล้วน ๆ
local CombatEffects = require(script.Parent:WaitForChild("CombatEffects"))
-- UI-1
local UiKit = require(script.Parent:WaitForChild("UiKit"))
local Hotbar = require(script.Parent:WaitForChild("Hotbar"))
local HealthBar = require(script.Parent:WaitForChild("HealthBar"))
local BagWindow = require(script.Parent:WaitForChild("BagWindow"))
local SidePanels = require(script.Parent:WaitForChild("SidePanels"))
-- UI-2
local MapSigns = require(script.Parent:WaitForChild("MapSigns"))
local SellWindow = require(script.Parent:WaitForChild("SellWindow"))
-- UI-3
local SummonWindow = require(script.Parent:WaitForChild("SummonWindow"))
-- UI-4
local IndexWindow = require(script.Parent:WaitForChild("IndexWindow"))
-- UI-5
local RobuxShopWindow = require(script.Parent:WaitForChild("RobuxShopWindow"))
-- 5C: ร้านกระบอง 10 ขั้น (เปิดจากจุดกด E ที่แผง "ซื้ออาวุธ")
local WeaponShopWindow = require(script.Parent:WaitForChild("WeaponShopWindow"))
-- Phase 5A: ตัวเลขนับถอยหลังบนกำแพงกั้นบอส (อ่านสถานะจาก Attribute ที่ server ตั้ง ไม่ผ่าน FarmStateSync)
local BossHud = require(script.Parent:WaitForChild("BossHud"))
-- ท้องฟ้ากลางคืน: กลางคืนของวงจรบอส = พระจันทร์ + มืดลง (Lighting ของเครื่องตัวเอง · ภาพล้วน)
local NightSky = require(script.Parent:WaitForChild("NightSky"))

local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local placeEggRequest = Remotes.waitFor(Config.RemoteNames.PLACE_EGG_IN_HATCHERY_REQUEST)
local moveMotherRequest = Remotes.waitFor(Config.RemoteNames.MOVE_MOTHER_REQUEST)
local upgradePenRequest = Remotes.waitFor(Config.RemoteNames.UPGRADE_PEN_REQUEST)
-- ⚠️ UI-2: ร้านขายแม่ขายเป็นชุดด้วย remote เดียว · SellMotherRequest (ทีละตัว) ยังอยู่ฝั่ง server แต่ client ไม่ใช้แล้ว
local sellMothersBatchRequest = Remotes.waitFor(Config.RemoteNames.SELL_MOTHERS_BATCH_REQUEST)
local autoFillPenRequest = Remotes.waitFor(Config.RemoteNames.AUTO_FILL_PEN_REQUEST)
local eggHatched = Remotes.waitFor(Config.RemoteNames.EGG_HATCHED)
local farmStateSync = Remotes.waitFor(Config.RemoteNames.FARM_STATE_SYNC)
-- ⚠️ server ส่งผลลัพธ์ (สำเร็จ/ล้มเหลว + เหตุผล) ของคำขอด้านบนกลับมาทางนี้
-- ก่อนหน้านี้ผลลัพธ์ไปโผล่แค่ print ใน server console เท่านั้น ผู้เล่นไม่เห็นอะไรเลย
local actionResult = Remotes.waitFor(Config.RemoteNames.ACTION_RESULT)
-- ⚠️ UI-3: ยิงจากหน้าต่างแท่นอัญเชิญเท่านั้น — ลำดับปล่อย = กองลูกที่ติ๊ก (กองที่ไม่ติ๊กไม่ถูกปล่อย)
local setReleaseOrderRequest = Remotes.waitFor(Config.RemoteNames.SET_RELEASE_ORDER_REQUEST)
local setSummonEnabledRequest = Remotes.waitFor(Config.RemoteNames.SET_SUMMON_ENABLED_REQUEST)
-- ⚠️ UI-2: ซื้อดาเมจ/ความเร็ว/อัปคอก ยิงจากป้ายบนแมพ (MapSigns · กด E) — remote เดิม server ตรวจเหมือนเดิม
local buyDamageUpgradeRequest = Remotes.waitFor(Config.RemoteNames.BUY_DAMAGE_UPGRADE_REQUEST)
local buySpeedUpgradeRequest = Remotes.waitFor(Config.RemoteNames.BUY_SPEED_UPGRADE_REQUEST)
-- ⚠️ UI-3: ส่งแม่ในกระเป๋าลง battleRoster เป็นชุด — ยิงได้**หลังกดยืนยันในหน้าต่างอัญเชิญเท่านั้น**
-- server ตรวจทุกตัวซ้ำเอง (อยู่ในกระเป๋าจริงไหม · lock · roster เต็ม · มีด่านให้ตี) ผลสรุปกลับทาง actionResult
-- · SendMotherToBattleRequest (ทีละตัว) ยังอยู่ฝั่ง server แต่ client ไม่ใช้แล้ว
local sendMothersToBattleBatchRequest = Remotes.waitFor(Config.RemoteNames.SEND_MOTHERS_TO_BATTLE_BATCH_REQUEST)
-- ⚠️ Phase 4A: server แจ้งเองตอนกำแพงด่านพัง (ไม่ได้มาจากปุ่ม) — ยิงครั้งเดียว ไม่อยู่ใน sync
-- Phase 4B: payload (stage, eggCount, deathCount) — รวมแจ้งแม่ในสนามรบที่ตายไว้ใน popup เดียวกัน
local stageClearedNotify = Remotes.waitFor(Config.RemoteNames.STAGE_CLEARED_NOTIFY)
-- ⚠️ Phase 4B: สลับล็อกแม่ (คอก/กระเป๋า) — ล็อกแล้วขาย/ส่งไปรบไม่ได้ · server ตรวจซ้ำเองทั้งสองทาง
local toggleMotherLockRequest = Remotes.waitFor(Config.RemoteNames.TOGGLE_MOTHER_LOCK_REQUEST)
-- ⚠️ Phase 5A: server แจ้งทุกคนเอง ("night" / "day" / "killed") — ข้อความจริงอยู่ที่ Config.formatBossEventMessage
local bossEventNotify = Remotes.waitFor(Config.RemoteNames.BOSS_EVENT_NOTIFY)
-- ⚠️ 5B: หยิบไข่บอส — ส่ง index ของฟองที่กด E ค้าง (BossHud ติดจุดกด) · ผลกลับมาทาง bossEventNotify
local pickUpBossEggRequest = Remotes.waitFor(Config.RemoteNames.PICK_UP_BOSS_EGG_REQUEST)
-- ⚠️ 5B-2: บอก server ว่าเริ่มกด/ปล่อย E ที่ไข่บอส — server จับเวลากดค้างเอง (ยิงหยิบตรง ๆ โดยไม่กดค้างครบ = ถูกปฏิเสธ)
local bossEggHoldRequest = Remotes.waitFor(Config.RemoteNames.BOSS_EGG_HOLD_REQUEST)
-- ⚠️ 5C: ซื้อกระบองขั้นถัดไป — **ไม่ส่งเลขขั้น** (server ซื้อขั้นถัดไปเอง ตรวจเงิน/เพดานเอง) · ผลกลับทาง actionResult
local buyClubTierRequest = Remotes.waitFor(Config.RemoteNames.BUY_CLUB_TIER_REQUEST)

--------------------------------------------------------------------------------
-- สี / ค่าคงที่
--------------------------------------------------------------------------------

local BG = Color3.fromRGB(28, 30, 36)
local FG = Color3.fromRGB(240, 240, 240)
local ACCENT = Color3.fromRGB(90, 160, 235)
local SUCCESS_COLOR = Color3.fromRGB(140, 220, 140)
local ERROR_COLOR = Color3.fromRGB(235, 130, 130)
-- ⚠️ สีเสี่ยง (แดง) เฉพาะการกระทำที่ทำให้แม่ตายถาวรได้
local BATTLE_RISK_COLOR = Color3.fromRGB(200, 60, 60)
local MAX_BATTLE_MOTHERS = Config.Balance.Combat.MAX_BATTLE_MOTHERS

-- ⚠️ สัดส่วนวัดจากภาพต้นแบบ (มือถือแนวนอน 2000×921) ของจอเต็ม — ดู docs/ui-overhaul-plan.md §3
local LEFT_BUTTON_X = 0.054
local LEFT_BUTTON_SIZE = UDim2.fromScale(0.098, 0.085)
local SHOP_BUTTON_Y = 0.377
local INDEX_BUTTON_Y = 0.472
local LEVEL_LABEL_X = 0.052
local LEVEL_LABEL_WIDTH = 0.16
local LEVEL_LABEL_HEIGHT = 0.065
local SPEED_LEVEL_Y = 0.85
local DAMAGE_LEVEL_Y = 0.93
local HOTBAR_SIDE_GAP = 0.007
-- ปุ่มกระเป๋าแถบบน — เทียบกับปุ่มของ Roblox (ปุ่มแชท ฯลฯ): ปุ่ม 44 ห่างขอบบน 12 ในแถบสูง 58
-- ⚠️ กึ่งกลางแนวตั้งของปุ่ม Roblox = 34/58 ของแถบ **ไม่ใช่กึ่งกลางแถบ (29/58)** — เดิมใช้กึ่งกลางแถบ
--   ปุ่มเลยลอยสูงกว่าปุ่มแชทนิดหน่อย (ผลทดสอบ Studio) · เก็บเป็นสัดส่วน แถบสูงไม่เท่ากันก็ยังตรงกัน
local TOPBAR_BUTTON_CENTER = 34 / 58
-- ขนาด = ใหญ่กว่าปุ่มของ Roblox (44/58) นิดหน่อย
local TOPBAR_BUTTON_FILL = 48 / 58
local TOPBAR_FALLBACK_HEIGHT = 58
local TOPBAR_GAP = 4
local TOAST_SECONDS = 4
-- ยอดเงิน: 52 เท่าเดิมบนจอสูง · จอเตี้ย (มือถือ) ย่อตามความสูงจอ
local COIN_TEXT_MAX = 52
local COIN_TEXT_HEIGHT_RATIO = 0.075
-- ⚠️ UI-fix รอบ 1: ดันเงินขึ้นชิดขอบบนสุดเท่าที่ทำได้ (ยอมรับได้ถ้าทับ/ชิดแถบเพลเยอร์ลิสต์
-- หรือปุ่ม Robux ของ Roblox เอง — ตัดสินใจแล้วว่าไม่ต้องเผื่อระยะห่างจาก topbar เหมือนของอื่น)
-- ⚠️ ตั้งใจไม่ใช้ getTopbarBottom()/topGap แบบของอื่นในไฟล์นี้ — นั่นคือระยะที่ "เผื่อ" ไม่ให้ชนแถบบน
local COIN_TOP_MARGIN = 2
-- ระยะห่างจากขอบจอ (ขวา/ล่าง) และใต้แถบบนของ Roblox (สัดส่วนความสูงจอ · 4–10 px)
local HUD_EDGE_MARGIN = 16
local HUD_TOP_GAP_RATIO = 0.012
-- หลอดเลือดการรบกว้าง 45% ของจอ (สั่งมา 40–50%) · ยอดเงินต้องอยู่ขวาของขอบหลอดห่าง COIN_BARS_GAP
local COMBAT_BAR_WIDTH = 0.45
local COIN_BARS_GAP = 12
-- สถิติการรบมุมขวาล่าง (ตัวหนังสือชิดขวา): มือถือกว้าง 30% ของจอ · ห่างขอบบนของปุ่มกระโดด
local COMBAT_STATS_WIDTH = 0.3
local JUMP_BUTTON_GAP = 8

-- ⚠️ ปิดกระเป๋ามาตรฐานของ Roblox — ช่องถือของของเกมมาแทน (Hotbar)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
-- ⚠️ 5D: ปิดแถบเลือด + จอแดงของ Roblox — แถบเลือดของเกม (HealthBar เหนือ hotbar) + จอแดงวาบมาแทน (กันซ้อนสองชุด)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local lastPayload: any = nil

--------------------------------------------------------------------------------
-- ScreenGui สองชั้น
--------------------------------------------------------------------------------
-- `gui` (ของเดิม · IgnoreGuiInset = false): ว่างแล้ว — เหลือเป็นฐาน DisplayOrder ของ popup ผ่านด่าน
-- `hud` (UI-1 · IgnoreGuiInset = true): ทุกอย่างที่วางตามสัดส่วนของจอเต็มจากภาพต้นแบบ + ปุ่มแถบบน
-- (TopbarInset เป็นพิกัดของจอเต็ม จึงต้องอยู่ใน ScreenGui ที่ไม่เว้น inset)

local gui = Instance.new("ScreenGui")
gui.Name = "EggFarmDebugUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = playerGui

local hud = Instance.new("ScreenGui")
hud.Name = "MainHud"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
-- ⚠️ ZIndex เทียบเฉพาะพี่น้องกัน (ไม่ขึ้นกับค่า default ของ engine) — หน้ารายละเอียด/toast อยู่บนของที่อยู่ระดับเดียวกัน
hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hud.DisplayOrder = gui.DisplayOrder + 1
hud.Parent = playerGui

-- ⚠️ ใส่ comma คั่นหลักพันเอง (ไม่มีให้ในตัวภาษา) — เฉพาะจำนวนเต็ม ไม่ต้องรองรับทศนิยม เพราะ
-- currency.coins ทั้งเกมเป็นจำนวนเต็มเสมอ (math.floor ตอนคำนวณราคาทุกจุด) — ข้อ 4: โชว์เต็ม ไม่ย่อ
local function formatCommaNumber(value: number): string
	local sign = if value < 0 then "-" else ""
	local intPart = string.format("%d", math.abs(math.floor(value)))
	local reversed = string.reverse(intPart)
	local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
	local formatted = string.reverse(grouped)
	formatted = string.gsub(formatted, "^,", "")
	return sign .. formatted
end

--------------------------------------------------------------------------------
-- ตำแหน่งที่อิงแถบบนของ Roblox
--------------------------------------------------------------------------------
-- ⚠️ อ่านจาก GuiService.TopbarInset (พิกัดจอเต็ม) เท่านั้น ห้ามกะเลขตายตัว — แถบสูงไม่เท่ากันระหว่าง PC/มือถือ
-- แถบบนถูกปิด (Height = 0) = ใช้ค่าสำรอง

local function getTopbarHeight(): number
	local inset = GuiService.TopbarInset
	return if inset.Height > 0 then inset.Height else TOPBAR_FALLBACK_HEIGHT
end

local function getTopbarBottom(): number
	local inset = GuiService.TopbarInset
	return if inset.Height > 0 then inset.Max.Y else TOPBAR_FALLBACK_HEIGHT
end

-- ขนาด pixel ที่แปรตามความสูงจอ มีพื้น/เพดาน (มือถือแนวนอน ≈ 389 หน่วย · PC ≈ 900–1,080)
local function scaledPixels(viewportY: number, ratio: number, minValue: number, maxValue: number): number
	return math.floor(math.clamp(viewportY * ratio, minValue, maxValue) + 0.5)
end

--------------------------------------------------------------------------------
-- ยอดเงิน — มุมขวาบน ใต้แถบปุ่มของ Roblox
--------------------------------------------------------------------------------
-- ⚠️ UI-1 (แก้ตามผลทดสอบ Studio): ย้ายจากมุมขวาล่าง (เหนือ Hotbar) มามุมขวาบน · ตำแหน่งตั้งใน layoutHud()
-- · ขอบบน = **ใต้** TopbarInset (ไม่อยู่ในแถบบน) · สูงไม่เกิน ~7.5% ของจอ → ไม่ถึงปุ่มไข่ (บน 32.8%)
-- · กว้างได้แค่ถึงขอบขวาของหลอดเลือด (+ช่องว่าง) — เลขยาวย่อตัวอักษรลงเอง (TextScaled) ไม่ล้นไปทับหลอด
-- ⚠️ ก่อน UI-1 เคยวางมุมขวาบนแล้วชน UI ของ Roblox (ป้ายชื่อผู้เล่น + ยอด Robux) — ถ้ายังชนอยู่
--   (เช่น รายชื่อผู้เล่นที่เปิดด้วย Tab บน PC) ดู docs/ui-overhaul-plan.md §4
-- ไม่มีกล่อง/พื้นหลัง มีเงาเส้นขอบ (TextStroke) แทน กันอ่านไม่ออกตอนพื้นหลังเป็นท้องฟ้า/หญ้าสว่าง

local coinLabel = Instance.new("TextLabel")
coinLabel.Name = "CoinLabel"
coinLabel.AnchorPoint = Vector2.new(1, 0)
coinLabel.BackgroundTransparency = 1
coinLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
coinLabel.TextXAlignment = Enum.TextXAlignment.Right
coinLabel.TextYAlignment = Enum.TextYAlignment.Top
coinLabel.TextScaled = true
coinLabel.Font = Enum.Font.SourceSansBold
coinLabel.TextStrokeTransparency = 0.4
coinLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
coinLabel.Text = "-"
coinLabel.Parent = hud

local coinTextLimit = Instance.new("UITextSizeConstraint")
coinTextLimit.MaxTextSize = COIN_TEXT_MAX
coinTextLimit.Parent = coinLabel

--------------------------------------------------------------------------------
-- ข้อความแจ้งผล (toast) — แทนบรรทัดผลลัพธ์ในแผงเทสต์เดิม
--------------------------------------------------------------------------------
-- ผลของทุกคำขอ (ActionResult) + ฟักเสร็จ + ข้อความเตือนฝั่ง client · หายเองใน TOAST_SECONDS วินาที
-- ตำแหน่งตั้งใน layoutHud(): ใต้หลอดเลือดตอนเปิดอัญเชิญ · ใต้แถบบนตอนปิด

local toast = UiKit.label({
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.085),
	Size = UDim2.fromScale(0.46, 0.055),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20),
	BackgroundTransparency = 0.25,
	TextWrapped = true,
	Visible = false,
	ZIndex = 20,
})
UiKit.corner(toast, UDim.new(0.3, 0))
UiKit.textStroke(toast, 1)
UiKit.maxTextSize(toast, 22)
local toastPadding = Instance.new("UIPadding")
toastPadding.PaddingLeft = UDim.new(0, 10)
toastPadding.PaddingRight = UDim.new(0, 10)
toastPadding.PaddingTop = UDim.new(0, 3)
toastPadding.PaddingBottom = UDim.new(0, 3)
toastPadding.Parent = toast
toast.Parent = hud

local toastSerial = 0

local function showToast(text: string, ok: boolean)
	toastSerial += 1
	local serial = toastSerial
	toast.Text = text
	toast.TextColor3 = if ok then SUCCESS_COLOR else ERROR_COLOR
	toast.Visible = true
	task.delay(TOAST_SECONDS, function()
		if toastSerial == serial then
			toast.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- HUD สถานะการรบ — ⚠️ โชว์เฉพาะตอนเปิดอัญเชิญ (ดู updateCombatHud)
--------------------------------------------------------------------------------
-- UI-1 (แก้ตามผลทดสอบ Studio): ไม่มีกล่องพื้นหลังแล้ว แยกเป็นสองชิ้น ตำแหน่งตั้งใน layoutHud()
--   กึ่งกลางบน ใต้แถบปุ่มของ Roblox: "กำลังตีด่าน N" + หลอดทหารฝ่ายรับ (ฟ้า) + หลอดกำแพง (แดง)
--   มุมขวาล่าง (มือถือ: เหนือปุ่มกระโดด): ทหารรวมในคลัง + แม่ในสนามรบ X/10 (ตัดรายชื่อแม่ออกแล้ว)
-- ⚠️ หลอดกำแพงโชว์คู่กับหลอดทหารฝ่ายรับตลอด (เต็ม 100% ถ้ายังไม่โดนตี) ให้เห็นเป้าหมายถัดไปล่วงหน้า
--   ค่าที่แสดงอ่านจาก stageProgress ของ payload.activeStage เหมือนเดิมทุกประการ

local DEFENDER_BAR_COLOR = Color3.fromRGB(70, 170, 255)
local WALL_BAR_COLOR = Color3.fromRGB(225, 55, 55)
local COMBAT_BAR_BG_COLOR = Color3.fromRGB(20, 20, 24)

local combatBars = UiKit.frame({
	Name = "CombatBars",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Visible = false,
})
combatBars.Parent = hud

local combatStageLabel = UiKit.label({
	Name = "Stage",
	FontFace = UiKit.FONT_HEAVY,
	Text = "-",
})
UiKit.textStroke(combatStageLabel, 1.5)
combatStageLabel.Parent = combatBars

-- หลอด = พื้นเข้ม + ส่วนเติม + ข้อความ % ในหลอด · คืน handle ไว้แก้ค่าซ้ำทุก sync (ไม่สร้าง Instance ใหม่)
local function makeHudBar(name: string, fillColor: Color3): (Frame, Frame, TextLabel)
	local bar = UiKit.frame({
		Name = name,
		BackgroundColor3 = COMBAT_BAR_BG_COLOR,
		BackgroundTransparency = 0.35,
	})
	UiKit.corner(bar, UDim.new(0.35, 0))
	UiKit.border(bar, UiKit.BLACK, 1.5)
	bar.Parent = combatBars

	local fill = UiKit.frame({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fillColor,
	})
	UiKit.corner(fill, UDim.new(0.35, 0))
	fill.Parent = bar

	local text = UiKit.label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})
	UiKit.textStroke(text, 1.5)
	local textPadding = Instance.new("UIPadding")
	textPadding.PaddingTop = UDim.new(0.12, 0)
	textPadding.PaddingBottom = UDim.new(0.12, 0)
	textPadding.Parent = text
	text.Parent = bar

	return bar, fill, text
end

local defendersBar, defendersHudFill, defendersHudText = makeHudBar("DefendersBar", DEFENDER_BAR_COLOR)
local wallBar, wallHudFill, wallHudText = makeHudBar("WallBar", WALL_BAR_COLOR)

local function setHudBar(fill: Frame, text: TextLabel, label: string, ratio: number)
	local clamped = math.clamp(ratio, 0, 1)
	fill.Size = UDim2.new(clamped, 0, 1, 0)
	text.Text = `{label}: {math.floor(clamped * 100)}%`
end

local combatStats = UiKit.frame({
	Name = "CombatStats",
	AnchorPoint = Vector2.new(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
})
combatStats.Parent = hud

local function makeStatLabel(name: string): TextLabel
	local label = UiKit.label({
		Name = name,
		FontFace = UiKit.FONT_HEAVY,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "-",
	})
	UiKit.textStroke(label, 1.5)
	label.Parent = combatStats
	return label
end

local combatStockpileLabel = makeStatLabel("Stockpile")
-- ⚠️ Phase 3C-2: แม่ใน battleRoster — อ่านจาก sync ล้วน ๆ (ไม่นับเอง) · ด่านที่กำลังตีพัง = ตายทั้งหมด
local combatRosterLabel = makeStatLabel("Roster")

-- ⚠️ ปุ่มกระโดดของ Roblox บนมือถืออยู่มุมขวาล่าง — สถิติการรบต้องยกขึ้นไปอยู่เหนือปุ่ม
-- อ่านตำแหน่งจริงจาก TouchGui (ขนาด/ตำแหน่งปุ่มเปลี่ยนตามขนาดจอ) · คืน "ระยะจากขอบล่างจอถึงขอบบนของปุ่ม"
-- · nil = ไม่มีปุ่มกระโดด (PC) · วัดเทียบกับ ScreenGui ของปุ่มเอง ขอบล่างจอเป็นจุดเดียวกันทุก ScreenGui
--   จึงไม่ต้องสนว่า TouchGui เว้น inset แถบบนหรือไม่
local function getJumpButtonClearance(): number?
	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not touchGui or not touchGui:IsA("ScreenGui") or not touchGui.Enabled then
		return nil
	end
	local controlFrame = touchGui:FindFirstChild("TouchControlFrame")
	if not controlFrame or not controlFrame:IsA("GuiObject") or not controlFrame.Visible then
		return nil
	end
	local jumpButton = controlFrame:FindFirstChild("JumpButton")
	if not jumpButton or not jumpButton:IsA("GuiObject") or not jumpButton.Visible then
		return nil
	end
	local topInGui = jumpButton.AbsolutePosition.Y - touchGui.AbsolutePosition.Y
	return touchGui.AbsoluteSize.Y - topInGui
end

-- ⚠️ จัดตำแหน่ง ยอดเงิน · หลอดเลือด · สถิติการรบ · toast ตามขนาดจอ + แถบบนของ Roblox
-- เรียกตอนเริ่ม · ขนาดจอเปลี่ยน · TopbarInset เปลี่ยน · ทุก sync (ปุ่มกระโดดโผล่/ขยับได้ระหว่างเกม)
local function layoutHud()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	local topGap = scaledPixels(viewport.Y, HUD_TOP_GAP_RATIO, 4, 10)
	local top = getTopbarBottom() + topGap

	-- หลอดเลือด: กึ่งกลางบน เรียงบนลงล่าง ชื่อด่าน → ทหารฝ่ายรับ → กำแพง
	local stageHeight = scaledPixels(viewport.Y, 0.032, 12, 24)
	local barHeight = scaledPixels(viewport.Y, 0.036, 14, 28)
	local rowGap = scaledPixels(viewport.Y, 0.005, 2, 6)
	local barsHeight = stageHeight + 2 * (rowGap + barHeight)
	combatBars.Position = UDim2.new(0.5, 0, 0, top)
	combatBars.Size = UDim2.new(COMBAT_BAR_WIDTH, 0, 0, barsHeight)
	combatStageLabel.Size = UDim2.new(1, 0, 0, stageHeight)
	defendersBar.Position = UDim2.fromOffset(0, stageHeight + rowGap)
	defendersBar.Size = UDim2.new(1, 0, 0, barHeight)
	wallBar.Position = UDim2.fromOffset(0, stageHeight + 2 * rowGap + barHeight)
	wallBar.Size = UDim2.new(1, 0, 0, barHeight)

	-- ยอดเงิน: มุมขวาบน · 52 บนจอสูง จอเตี้ย (มือถือ) ย่อตามความสูงจอ · กว้างได้ถึงขอบขวาของหลอดเท่านั้น
	local coinHeight = math.floor(math.min(COIN_TEXT_MAX, viewport.Y * COIN_TEXT_HEIGHT_RATIO))
	local barsRight = viewport.X * (0.5 + COMBAT_BAR_WIDTH / 2)
	coinTextLimit.MaxTextSize = coinHeight
	coinLabel.Size = UDim2.fromOffset(
		math.max(0, viewport.X - HUD_EDGE_MARGIN - barsRight - COIN_BARS_GAP),
		math.floor(coinHeight * 1.25)
	)
	coinLabel.Position = UDim2.new(1, -HUD_EDGE_MARGIN, 0, COIN_TOP_MARGIN)

	-- toast: ใต้หลอดเลือดตอนเปิดอัญเชิญ · ใต้แถบบนตอนปิด
	local toastTop = if combatBars.Visible then top + barsHeight + topGap else top
	toast.Position = UDim2.new(0.5, 0, 0, toastTop)

	-- สถิติการรบ: มุมขวาล่าง
	-- · มือถือ: ยกขึ้นเหนือปุ่มกระโดด (พ้นแถบ Hotbar แล้ว) → กว้างได้ COMBAT_STATS_WIDTH
	-- · PC: อยู่แถบเดียวกับ Hotbar → กว้างได้เท่าที่ Hotbar เว้นไว้ฝั่งขวา (สมมาตรกับบล็อกเลเวลฝั่งซ้าย)
	--   ข้อความยาวกว่านั้นย่อตัวอักษรลงเอง (TextScaled) ไม่ล้นไปทับช่องขวาสุดของ Hotbar
	local lineHeight = scaledPixels(viewport.Y, 0.034, 13, 24)
	local jumpClearance = getJumpButtonClearance()
	local statsWidth = if jumpClearance
		then viewport.X * COMBAT_STATS_WIDTH
		else viewport.X * (LEVEL_LABEL_X + LEVEL_LABEL_WIDTH) - HUD_EDGE_MARGIN
	local bottomOffset = if jumpClearance then jumpClearance + JUMP_BUTTON_GAP else HUD_EDGE_MARGIN
	combatStats.Size = UDim2.fromOffset(math.max(0, statsWidth), lineHeight * 2)
	combatStats.Position = UDim2.new(1, -HUD_EDGE_MARGIN, 1, -bottomOffset)
	combatStockpileLabel.Size = UDim2.new(1, 0, 0, lineHeight)
	combatRosterLabel.Position = UDim2.fromOffset(0, lineHeight)
	combatRosterLabel.Size = UDim2.new(1, 0, 0, lineHeight)
end

layoutHud()
do
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutHud)
	end
end
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutHud)

-- ⚠️ เรียกทุกครั้งที่ sync มาใหม่ — ผลรวมทหารในคลัง = ผลรวม count ของทุกกองใน lastPayload.children
local function updateCombatHud()
	if not lastPayload then
		return
	end

	-- ⚠️ UI-1: โชว์เฉพาะตอนเปิดอัญเชิญ — ปิดอัญเชิญ (รวมถึง auto-pause) = ซ่อนทั้งหลอดและสถิติ
	local visible = lastPayload.summonEnabled == true
	combatBars.Visible = visible
	combatStats.Visible = visible

	local activeStage = lastPayload.activeStage
	if not activeStage then
		combatStageLabel.Text = "ผ่านครบทุกด่านแล้ว!"
		setHudBar(defendersHudFill, defendersHudText, "ทหารฝ่ายรับ", 0)
		setHudBar(wallHudFill, wallHudText, "กำแพง", 0)
	else
		-- 5E-1: รวมพล (ค3) ขึ้นต่อท้ายชื่อด่าน · ตัวเลขทั้งหมดมาจาก server (payload.battle)
		local battle = lastPayload.battle
		local gatherText = if battle and battle.gathering
			then ` · ⏳ กำลังรวมพล {battle.available}/{battle.gatherTarget}`
			else ""
		combatStageLabel.Text = `กำลังตีด่าน {activeStage}{gatherText}`

		local info = lastPayload.stageProgress[activeStage]
		local defendersRatio = 1
		local wallRatio = 1
		local wallHp = if info.started then info.wallHpRemaining else nil
		if info.started then
			defendersRatio = if info.defendersTotal > 0 then info.defendersRemaining / info.defendersTotal else 0
			wallRatio = if info.wallHpTotal > 0 then info.wallHpRemaining / info.wallHpTotal else 1
		end

		-- 5E-1: หลอดศัตรูบอก "เหลือกี่ตัว" (ใหญ่ + เล็ก) · หลอดกำแพงบอกเลือดที่เหลือ
		local enemiesLeft = if battle then (battle.bigLeft or 0) + (battle.smallLeft or 0) else nil
		setHudBar(defendersHudFill, defendersHudText, "ศัตรู", defendersRatio)
		if enemiesLeft then
			defendersHudText.Text = `ศัตรูเหลือ {formatCommaNumber(enemiesLeft)} ตัว · {math.floor(math.clamp(defendersRatio, 0, 1) * 100)}%`
		end
		setHudBar(wallHudFill, wallHudText, "กำแพง", wallRatio)
		if wallHp then
			wallHudText.Text = `กำแพง {formatCommaNumber(math.ceil(wallHp))} HP · {math.floor(math.clamp(wallRatio, 0, 1) * 100)}%`
		end
	end

	local totalStock = 0
	for _, stack in lastPayload.children do
		totalStock += stack.count
	end
	-- 5E-1: ลูกที่ยืนอยู่บนสนามไม่นับ (server หักออกจากจำนวนในกองให้แล้ว)
	combatStockpileLabel.Text = `ทหารรวมในคลัง: {formatCommaNumber(totalStock)} ตัว`

	local roster = lastPayload.battleRoster or {}
	combatRosterLabel.Text = `แม่ในสนามรบ: {#roster}/{MAX_BATTLE_MOTHERS}`

	-- ตำแหน่ง toast ขึ้นกับว่าหลอดโชว์ไหม · ปุ่มกระโดดบนมือถือโผล่/ขยับได้ระหว่างเกม → จัดใหม่ทุก sync
	layoutHud()
end

--------------------------------------------------------------------------------
-- จัดการหน้าต่างกลางจอ — เปิดได้ทีละอัน (กระเป๋า · ร้านค้า Robux · ดัชนี · ร้านขายแม่ · แท่นอัญเชิญ)
-- ⚠️ UI-5: หน้าต่าง "เร็วๆ นี้" (placeholder ของร้านค้า) ปิดไปแล้ว — แทนที่ด้วย RobuxShopWindow จริง
--------------------------------------------------------------------------------

type WindowName = "bag" | "shop" | "index" | "sell" | "summon" | "weapon"

local function isWindowOpen(name: WindowName): boolean
	if name == "bag" then
		return BagWindow.isOpen()
	elseif name == "sell" then
		return SellWindow.isOpen()
	elseif name == "summon" then
		return SummonWindow.isOpen()
	elseif name == "index" then
		return IndexWindow.isOpen()
	elseif name == "shop" then
		return RobuxShopWindow.isOpen()
	elseif name == "weapon" then
		return WeaponShopWindow.isOpen()
	end
	return false
end

local function closeAllWindows()
	BagWindow.close()
	SellWindow.close()
	SummonWindow.close()
	IndexWindow.close()
	RobuxShopWindow.close()
	WeaponShopWindow.close()
end

-- กดปุ่มเดิมซ้ำ = ปิด · กดปุ่มอื่น = ปิดอันเก่าแล้วเปิดอันใหม่
local function toggleWindow(name: WindowName)
	local wasOpen = isWindowOpen(name)
	closeAllWindows()
	if wasOpen then
		return
	end
	if name == "bag" then
		BagWindow.open()
	elseif name == "sell" then
		SellWindow.open()
	elseif name == "summon" then
		SummonWindow.open()
	elseif name == "index" then
		IndexWindow.open() -- ล้างจุดแดงบนปุ่มดัชนีด้วย
	elseif name == "shop" then
		RobuxShopWindow.open()
	elseif name == "weapon" then
		WeaponShopWindow.open()
	end
end

--------------------------------------------------------------------------------
-- ปุ่มซ้าย: ร้านค้า · ดัชนี
--------------------------------------------------------------------------------

local function makeLeftButton(name: string, y: number, color: Color3, borderColor: Color3, icon: string, text: string): TextButton
	local button = UiKit.button({
		Name = name,
		Position = UDim2.fromScale(LEFT_BUTTON_X, y),
		Size = LEFT_BUTTON_SIZE,
		BackgroundColor3 = color,
	})
	UiKit.corner(button, UDim.new(0.16, 0))
	UiKit.border(button, borderColor, 3)

	local iconLabel = UiKit.label({
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.3, 0.8),
		Text = icon,
	})
	iconLabel.Parent = button

	local textLabel = UiKit.label({
		Position = UDim2.fromScale(0.34, 0.12),
		Size = UDim2.fromScale(0.62, 0.76),
		Text = text,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(textLabel, 2)
	textLabel.Parent = button

	button.Parent = hud
	return button
end

local shopButton = makeLeftButton("ShopButton", SHOP_BUTTON_Y, Color3.fromRGB(110, 225, 70), Color3.fromRGB(35, 95, 25), "🛒", "ร้านค้า")
local indexButton = makeLeftButton("IndexButton", INDEX_BUTTON_Y, Color3.fromRGB(80, 190, 245), Color3.fromRGB(25, 75, 125), "📖", "ดัชนี")
-- UI-4: หน้าต่างดัชนี + จุดแดงบนปุ่มเมื่อได้ตัวละครใหม่ครั้งแรก (หายเมื่อเปิดดัชนี · จำใน client เท่านั้น)
IndexWindow.create(hud)
IndexWindow.attachBadge(indexButton)

-- ⚠️ UI-5: จุดเดียวที่เรียก PromptProductPurchase — ไม่ใช่ FireServer (server ไม่เกี่ยวจนกว่าจะถึง
-- ProcessReceipt) ใช้ closure เดียวกันทั้งจากหน้าต่างร้านค้าและปุ่ม "เติบโตทั้งหมด" ในแผงไข่ (SidePanels)
local function buyRobuxProduct(productId: number)
	MarketplaceService:PromptProductPurchase(player, productId)
end

RobuxShopWindow.create(hud, {
	buyProduct = buyRobuxProduct,
})

shopButton.Activated:Connect(function()
	toggleWindow("shop")
end)
indexButton.Activated:Connect(function()
	toggleWindow("index")
end)

--------------------------------------------------------------------------------
-- มุมล่างซ้าย: เลเวลความเร็ว + ดาเมจ (ไม่โชว์ค่าจริง)
--------------------------------------------------------------------------------

local function makeLevelLabel(name: string, y: number, color: Color3): TextLabel
	local label = UiKit.label({
		Name = name,
		Position = UDim2.fromScale(LEVEL_LABEL_X, y),
		Size = UDim2.fromScale(LEVEL_LABEL_WIDTH, LEVEL_LABEL_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		FontFace = UiKit.FONT_HEAVY_ITALIC,
		Text = "",
	})
	UiKit.textStroke(label, 3)
	label.Parent = hud
	return label
end

local speedLevelLabel = makeLevelLabel("SpeedLevel", SPEED_LEVEL_Y, Color3.fromRGB(140, 215, 255))
local damageLevelLabel = makeLevelLabel("DamageLevel", DAMAGE_LEVEL_Y, Color3.fromRGB(150, 240, 120))

--------------------------------------------------------------------------------
-- ปุ่มกระเป๋าในแถบบน — ต่อท้ายปุ่มของ Roblox (อ่านจาก GuiService.TopbarInset)
--------------------------------------------------------------------------------
-- ⚠️ ห้ามกะตำแหน่งตายตัว — ปุ่มของ Roblox ยาวไม่เท่ากันระหว่าง PC/มือถือ และเปลี่ยนตามเมนูที่เปิด

local bagTopButton = UiKit.button({
	Name = "BagTopbarButton",
	BackgroundColor3 = Color3.fromRGB(18, 18, 21),
	BackgroundTransparency = 0.35,
	Text = "",
})
UiKit.corner(bagTopButton, UDim.new(0.5, 0))
local bagTopIcon = UiKit.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.62, 0.62),
	Text = "🎒",
})
bagTopIcon.Parent = bagTopButton
bagTopButton.Parent = hud

local function layoutTopbarButton()
	local inset = GuiService.TopbarInset
	local height = getTopbarHeight()
	local size = math.floor(height * TOPBAR_BUTTON_FILL + 0.5)
	-- กึ่งกลางแนวตั้งตรงกับปุ่มของ Roblox (ไม่ใช่กึ่งกลางแถบ) — ดู TOPBAR_BUTTON_CENTER
	local centerY = inset.Min.Y + height * TOPBAR_BUTTON_CENTER
	bagTopButton.Size = UDim2.fromOffset(size, size)
	bagTopButton.Position = UDim2.fromOffset(inset.Min.X + TOPBAR_GAP, math.floor(centerY - size / 2 + 0.5))
end

layoutTopbarButton()
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutTopbarButton)
bagTopButton.Activated:Connect(function()
	toggleWindow("bag")
end)

--------------------------------------------------------------------------------
-- Hotbar · กระเป๋า · แผงขวา
--------------------------------------------------------------------------------

-- ⚠️ ความกว้างที่ Hotbar ต้องเว้นไว้ทั้งสองข้าง = ขอบขวาของบล็อกเลเวลมุมล่างซ้าย + ช่องว่าง
-- (ฝั่งขวาเป็นที่ของสถิติการรบบน PC — layoutHud() ใช้ความกว้างเดียวกันนี้)
-- (คิดจากสัดส่วนล้วน ๆ ไม่อ่าน AbsoluteSize — ใช้ได้ตั้งแต่ก่อน layout รอบแรก)
Hotbar.create(hud, function(): number
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 0
	return (LEVEL_LABEL_X + LEVEL_LABEL_WIDTH + HOTBAR_SIDE_GAP) * width
end)
-- 5D: แถบเลือดเหนือ hotbar (เฉพาะในสนามรบหรือเลือดไม่เต็ม) + จอแดงวาบตอนโดนตี · อ่าน Humanoid ของตัวเองล้วน ๆ
HealthBar.create(hud, Hotbar.getFrame())
HealthBar.start()

BagWindow.create(hud, {
	moveMother = function(uid: string, target: string)
		moveMotherRequest:FireServer(uid, target)
	end,
	toggleLock = function(uid: string)
		toggleMotherLockRequest:FireServer(uid)
	end,
	placeEgg = function(heldEggId: number)
		-- ⚠️ ส่ง **id ประจำฟอง** ไม่ใช่ชนิดไข่ และไม่ใช่ตำแหน่งในลิสต์
		placeEggRequest:FireServer(heldEggId)
	end,
	notify = showToast,
})

SidePanels.create(hud, {
	unequip = function(uid: string)
		moveMotherRequest:FireServer(uid, "bag")
	end,
	equipBest = function()
		autoFillPenRequest:FireServer()
	end,
	-- UI-5: ปุ่ม "เติบโตทั้งหมด" — ทางลัดเดียวกับการ์ด "เร่งฟักไข่ทั้งหมด" ในร้านค้า Robux (productId เดียวกัน)
	rushHatching = function()
		local rushProduct = Config.getRobuxProduct("robux_hatch_rush")
		if rushProduct then
			buyRobuxProduct(rushProduct.productId)
		end
	end,
})

--------------------------------------------------------------------------------
-- UI-2: ร้านขายแม่ + ป้ายอัปเกรดบนแมพ
--------------------------------------------------------------------------------

-- ⚠️ ขายเป็นชุดครั้งเดียว (server ตรวจกระเป๋า/ล็อก/คิดราคาเองทุกตัว · ข้อความสรุปกลับทาง toast ครั้งเดียว)
SellWindow.create(hud, {
	sellMothers = function(uids: { string })
		sellMothersBatchRequest:FireServer(uids)
	end,
	notify = showToast,
})

-- 5C: ร้านกระบอง — ปุ่มซื้อยิง remote ไม่มีพารามิเตอร์ (server ซื้อขั้นถัดไปเอง) · ผล "ได้กระบองขั้น N" กลับทาง toast
WeaponShopWindow.create(hud, {
	buyNext = function()
		buyClubTierRequest:FireServer()
	end,
	notify = showToast,
})

--------------------------------------------------------------------------------
-- UI-3: หน้าต่างแท่นอัญเชิญ
--------------------------------------------------------------------------------
-- ⚠️ ลำดับยิงตายตัว (SummonWindow เรียกตามนี้): ส่งแม่เป็นชุด → ตั้งลำดับปล่อยลูก → เปิดอัญเชิญ
-- RemoteEvent ของผู้เล่นคนเดียวถึง server ตามลำดับที่ยิง → แม่เข้า roster ก่อนอัญเชิญเริ่มตีเสมอ
SummonWindow.create(hud, {
	sendMothers = function(uids: { string })
		sendMothersToBattleBatchRequest:FireServer(uids)
	end,
	setReleaseOrder = function(keys: { string })
		setReleaseOrderRequest:FireServer(keys)
	end,
	setSummonEnabled = function(enabled: boolean)
		setSummonEnabledRequest:FireServer(enabled)
	end,
	notify = showToast,
})

-- ⚠️ ป้ายบนแมพยิง remote ซื้อเดิมทั้ง 3 ตัว — ไม่มี logic ซื้อใหม่ · server ตรวจเงิน/เพดานเหมือนเดิม
MapSigns.start(playerGui, {
	buy = function(kind: MapSigns.SignKind)
		if kind == "damage" then
			buyDamageUpgradeRequest:FireServer()
		elseif kind == "speed" then
			buySpeedUpgradeRequest:FireServer()
		else
			upgradePenRequest:FireServer()
		end
	end,
	openSellShop = function()
		if not SellWindow.isOpen() then
			toggleWindow("sell")
		end
	end,
	closeSellShop = function()
		if SellWindow.isOpen() then
			SellWindow.close()
		end
	end,
	isSellShopOpen = SellWindow.isOpen,
	openWeaponShop = function()
		if not WeaponShopWindow.isOpen() then
			toggleWindow("weapon")
		end
	end,
	closeWeaponShop = function()
		if WeaponShopWindow.isOpen() then
			WeaponShopWindow.close()
		end
	end,
	isWeaponShopOpen = WeaponShopWindow.isOpen,
	openSummon = function()
		if not SummonWindow.isOpen() then
			toggleWindow("summon")
		end
	end,
	closeSummon = function()
		if SummonWindow.isOpen() then
			SummonWindow.close()
		end
	end,
	isSummonOpen = SummonWindow.isOpen,
	-- ⚠️ UI-fix รอบ 1: ทางลัดหยุดอัญเชิญจากแท่นโดยตรง — remote เดิมของปุ่ม "หยุดอัญเชิญ" ในหน้าต่าง
	-- ไม่เปิด/แตะหน้าต่างเลย (ปิดอยู่ก็ยังปิดต่อ · เปิดอยู่ก็ไม่ถูกสั่งปิดตาม — sync จะทำให้หน้าต่างอัปเดตเอง)
	stopSummon = function()
		setSummonEnabledRequest:FireServer(false)
	end,
})

--------------------------------------------------------------------------------
-- popup "ผ่านด่านสำเร็จ" (Phase 4A · 4B รวมแจ้งแม่ในสนามรบที่ตายไว้ใน popup เดียวกัน)
--------------------------------------------------------------------------------
-- server แจ้งเอง ไม่มีอะไรให้ยืนยัน · ScreenGui แยก DisplayOrder สูง + ฉากหลังมืดเต็มจอ กันกดโดนปุ่มข้างหลัง
-- ⚠️ มาจาก StageClearedNotify ครั้งเดียวต่อเหตุการณ์ ไม่อ่านจาก sync → resync กี่รอบก็ไม่โผล่ซ้ำ
-- · ถ้าแจ้งมาซ้อนกัน (พังหลายด่านติดกัน) ต่อคิว โชว์ทีละอัน กด "ตกลง" แล้วขึ้นอันถัดไป

local stageClearGui = Instance.new("ScreenGui")
stageClearGui.Name = "StageClearedPopup"
stageClearGui.ResetOnSpawn = false
stageClearGui.IgnoreGuiInset = true
stageClearGui.DisplayOrder = gui.DisplayOrder + 20
stageClearGui.Enabled = false
stageClearGui.Parent = playerGui

local stageClearBackdrop = Instance.new("TextButton")
stageClearBackdrop.Name = "Backdrop"
stageClearBackdrop.Size = UDim2.fromScale(1, 1)
stageClearBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
stageClearBackdrop.BackgroundTransparency = 0.45
stageClearBackdrop.BorderSizePixel = 0
stageClearBackdrop.AutoButtonColor = false
stageClearBackdrop.Text = ""
stageClearBackdrop.Parent = stageClearGui

local stageClearBox = Instance.new("Frame")
stageClearBox.Name = "Dialog"
stageClearBox.AnchorPoint = Vector2.new(0.5, 0.5)
stageClearBox.Position = UDim2.fromScale(0.5, 0.5)
stageClearBox.Size = UDim2.new(0, 340, 0, 0)
stageClearBox.AutomaticSize = Enum.AutomaticSize.Y
stageClearBox.BackgroundColor3 = BG
stageClearBox.BorderSizePixel = 0
stageClearBox.Parent = stageClearGui

local stageClearCorner = Instance.new("UICorner")
stageClearCorner.CornerRadius = UDim.new(0, 10)
stageClearCorner.Parent = stageClearBox

local stageClearStroke = Instance.new("UIStroke")
stageClearStroke.Color = SUCCESS_COLOR
stageClearStroke.Thickness = 2
stageClearStroke.Parent = stageClearBox

local stageClearPadding = Instance.new("UIPadding")
stageClearPadding.PaddingTop = UDim.new(0, 16)
stageClearPadding.PaddingBottom = UDim.new(0, 16)
stageClearPadding.PaddingLeft = UDim.new(0, 16)
stageClearPadding.PaddingRight = UDim.new(0, 16)
stageClearPadding.Parent = stageClearBox

local stageClearLayout = Instance.new("UIListLayout")
stageClearLayout.Padding = UDim.new(0, 10)
stageClearLayout.SortOrder = Enum.SortOrder.LayoutOrder
stageClearLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
stageClearLayout.Parent = stageClearBox

local function makeStageClearText(order: number, textSize: number, font: Enum.Font, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextWrapped = true
	label.TextSize = textSize
	label.Font = font
	label.Text = ""
	label.Parent = stageClearBox
	return label
end

local stageClearTitle = makeStageClearText(1, 22, Enum.Font.SourceSansBold, SUCCESS_COLOR)
local stageClearBody = makeStageClearText(2, 16, Enum.Font.SourceSans, FG)

local stageClearOkButton = Instance.new("TextButton")
stageClearOkButton.Name = "Ok"
stageClearOkButton.LayoutOrder = 3
stageClearOkButton.Size = UDim2.new(0, 140, 0, 36)
stageClearOkButton.BackgroundColor3 = ACCENT
stageClearOkButton.BorderSizePixel = 0
stageClearOkButton.TextColor3 = Color3.fromRGB(255, 255, 255)
stageClearOkButton.TextSize = 16
stageClearOkButton.Font = Enum.Font.SourceSansBold
stageClearOkButton.Text = "ตกลง"
stageClearOkButton.AutoButtonColor = true
stageClearOkButton.Parent = stageClearBox

local stageClearOkCorner = Instance.new("UICorner")
stageClearOkCorner.CornerRadius = UDim.new(0, 6)
stageClearOkCorner.Parent = stageClearOkButton

local stageClearQueue: { { stage: number, eggCount: number, deathCount: number } } = {}

local function showNextStageClear()
	local entry = stageClearQueue[1]
	if not entry then
		stageClearGui.Enabled = false
		return
	end
	-- ⚠️ ข้อความทุกกรณีอยู่ที่ Config.formatStageClearedMessage (เทสต์นอก Studio ได้) — ห้ามต่อ string เองตรงนี้
	local title, body = Config.formatStageClearedMessage(entry.stage, entry.eggCount, entry.deathCount)
	stageClearTitle.Text = title
	stageClearBody.Text = body
	-- มีแม่ตาย = ขอบแดง ให้ต่างจาก popup ข่าวดีล้วน ๆ
	stageClearStroke.Color = if entry.deathCount > 0 then BATTLE_RISK_COLOR else SUCCESS_COLOR
	stageClearGui.Enabled = true
end

stageClearOkButton.Activated:Connect(function()
	table.remove(stageClearQueue, 1)
	showNextStageClear()
end)

stageClearedNotify.OnClientEvent:Connect(function(stage: number, eggCount: number, deathCount: number?)
	table.insert(stageClearQueue, { stage = stage, eggCount = eggCount, deathCount = deathCount or 0 })
	if #stageClearQueue == 1 then
		showNextStageClear()
	end
end)

--------------------------------------------------------------------------------
-- ต่อสาย
--------------------------------------------------------------------------------

farmStateSync.OnClientEvent:Connect(function(payload)
	lastPayload = payload
	coinLabel.Text = formatCommaNumber(payload.coins)
	speedLevelLabel.Text = `👟 Lv. {payload.speedLevel}`
	damageLevelLabel.Text = `⚔️ Lv. {payload.damageLevel}`
	updateCombatHud()
	BagWindow.setPayload(payload)
	SidePanels.setPayload(payload)
	SellWindow.setPayload(payload)
	SummonWindow.setPayload(payload)
	IndexWindow.setPayload(payload)
	RobuxShopWindow.setPayload(payload)
	WeaponShopWindow.setPayload(payload)
	MapSigns.setPayload(payload)

	-- ⚠️ Phase 3B-1: กำแพง (WallRenderer) กับโมเดลทหาร (TroopRenderer) อ่านจากของจริงที่ sync
	-- มานี้เสมอ ไม่ใช่ default อีกต่อไป — อัปเดตทุกครั้งที่ sync มาใหม่ (real-time ตามที่กำลังตีอยู่)
	WallRenderer.setStageProgress(payload.stageProgress)
	-- 5E-1: ภาพสนามรบชั่วคราว — พังเมื่อไหร่ต้องไม่ลากเลขดาเมจลอยข้างล่างหยุดไปด้วย
	local troopsOk, troopsError = pcall(TroopRenderer.updateFromPayload, payload)
	if not troopsOk then
		warn(`[Main] TroopRenderer.updateFromPayload ล้มเหลว: {troopsError}`)
	end
	-- ⚠️ Phase 3B-2: เทียบ defendersRemaining/wallHpRemaining ของด่านที่กำลังตีกับรอบ sync
	-- ก่อนหน้า (state เก็บอยู่ในตัว CombatEffects เอง) แล้วโชว์เลขลอย+burst ถ้ามี damage เกิดขึ้นจริง
	CombatEffects.onSync(payload)
end)

-- ⚠️ ผลลัพธ์ของทุกคำขอ (วางไข่/ย้าย/อัปเกรด/ขาย/สวมใส่ที่ดีที่สุด/ส่งไปรบ/ล็อก) → toast
actionResult.OnClientEvent:Connect(function(ok: boolean, message: string)
	showToast(message, ok)
end)

-- ⚠️ 5B: ตัวเลขต่อท้าย (น้ำหนักไข่ · เงินที่ได้ · จำนวนคนแบ่ง) มาจาก server เสมอ — ที่นี่แค่จัดรูปข้อความ
-- 5B-2: + เลขห้อง ("killed"/"locked" = a · "reward" = c) · "heavy" = รายการ { room, weight } ทุกห้องในข้อความเดียว
-- เหตุการณ์ "ทำไม่สำเร็จ/เสียของ" (หยิบไม่ได้ · กระเป๋าเต็ม · ไข่หาย · ติดล็อก) โชว์สีเตือน
bossEventNotify.OnClientEvent:Connect(function(kind: string, a: any?, b: number?, c: number?)
	local message = Config.formatBossEventMessage(kind, a, b, c)
	if message ~= "" then
		showToast(message, not Config.isBossEventWarning(kind))
	end
end)

eggHatched.OnClientEvent:Connect(function(payload)
	local place = if payload.placedIn == "pen" then "เข้าคอก" else "เข้ากระเป๋า"
	showToast(`🥚 ฟักได้ {payload.charName} ({payload.class}) {payload.weightText} kg → {place}`, true)
	print(`[Client] ฟักได้ {payload.charName} คลาส {payload.class} น้ำหนัก {payload.weightText}`)
end)

-- ⚠️ กำแพงวาดฝั่งนี้เท่านั้น — แต่ละคนพังคนละด่านแต่ยืนบนเลนเดียวกัน
-- (เหตุผลเต็มอยู่ใน src/client/WallRenderer.lua และ docs/map-layout.md)
WallRenderer.start()

-- ⚠️ Phase 3B-1: โมเดลทหารฝ่ายเรา/ฝ่ายรับ วาดฝั่งนี้ด้วยเหตุผลเดียวกัน (ดู TroopRenderer.lua)
TroopRenderer.start()

-- ⚠️ Phase 5A: ตัวเลข 59 → 0 บนกำแพงกั้นกลางคืน (รอของจาก server เบื้องหลัง ไม่บล็อกบรรทัดถัดไป)
-- ⚠️ 5B: + จุดกด E ค้างที่ไข่บอส — ยิงแค่ "ฟองที่ i" · server ตัดสินทุกอย่างเอง (บอสตายไหม · ระยะ · ถืออยู่แล้วไหม)
-- ⚠️ 5B-2: + บอกจังหวะเริ่มกด/ปล่อย (server จับเวลากดค้างเอง) · ห้องไหน server ดูจากตำแหน่งตัวละครเอง
-- ⚠️ 5C: + เลขดาเมจเด้งเหนือบอสตอนโดน (BossHud เทียบ HP ห้องนั้นกับค่าก่อนหน้า · ภาพล้วน)
local BOSS_HIT_COLOR = Color3.fromRGB(255, 235, 90)
BossHud.start(playerGui, function(index: number)
	pickUpBossEggRequest:FireServer(index)
end, function(index: number, holding: boolean)
	bossEggHoldRequest:FireServer(index, holding)
end, function(room: number, damage: number)
	local top = Config.getBossCornerCenter(room) + Vector3.new(0, Config.MapDimensions.BossArena.BossSize.Y, 0)
	CombatEffects.floatingText(top, `-{UiKit.formatShort(damage)}`, BOSS_HIT_COLOR)
end)
-- กลางคืน = เปลี่ยนฟ้าเป็นพระจันทร์ + มืดลง · เช้า = กลับค่าเดิม (อ่าน Phase บน BossState ตัวเดียวกับ BossHud)
NightSky.start()

print("[egg-army-game] client พร้อมแล้ว")
print("   จำลองด่านที่พังแล้วเพื่อทดสอบกำแพง (ค่าจริงจาก sync จะเขียนทับทันที): WallRenderer.setWallProgress(n)")
