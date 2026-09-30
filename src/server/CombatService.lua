--!strict
-- egg-army-game :: เครื่องยนต์คำนวณรบฝั่ง server
--
-- ══ 5E-1b แถวเดียวแบบ Age of War (ผู้ใช้ยืนยัน · docs/data-schema.md §7.13) ══ แทนสนาม 6 ช่อง + รวมพลของ 5E-1
--   ฝั่งเรา: แถวเดียว ยาวไม่เกิน LINE_LENGTH (10) · ปล่อยทีละตัวตาม**รอบวน**ที่ผู้เล่นติ๊ก (แม่ + กองลูกในรอบเดียวกัน)
--     1,2,…,N,1,2,… ต่อท้ายแถว · กองหมด = ข้าม · แม่ออกได้ทีละครั้ง (อยู่ในแถวแล้ว/ตายแล้ว = ข้าม) · ทุกรายการหมด = หยุดปล่อย
--     เลือด = พลังฐาน · ดาเมจ/วิ = พลังเต็ม × อัตราปล่อย
--   ฝั่งศัตรู: แถวเดียว วนตายตัว เล็ก 5 → ใหญ่ 1 (Config.getEnemyKindAt) · ตายเรียงลำดับ
--   **เฉพาะตัวหน้าสุดของแต่ละฝั่งตีกัน** ตัวต่อตัว · ตัวหน้าสุดตาย → ทั้งแถวขยับขึ้น + ปล่อยตัวถัดไปจากรอบวนต่อท้าย
--   ศัตรูหมดแล้วค่อยตีกำแพงได้ (ตัวหน้าสุดตี · ตัวอื่นรอคิว)
-- เดินทัพ (ผู้ใช้สั่ง): แถวว่างแล้วปล่อยใหม่ = เดินจากแท่นอัญเชิญ · ศัตรูเดินออกจากกำแพงพร้อมกัน เจอกันกึ่งกลางเลน (นอกระยะป้อม) ·
--   ศัตรูหมด → เดินต่อไปกำแพง · ระหว่างเดินไม่มีใครตีใคร · **ป้อมยิงเฉพาะตอนเดินถึงกำแพงแล้ว** (ผู้ใช้ยืนยัน 5E-1b)
-- ไม่มีรวมพลแล้ว — ไม่มีการรุม ลูกออกไปทีละตัวก็ทำดาเมจต่อตัวเท่ากัน
--
-- ⚠️ คำนวณแบบเหตุการณ์ต่อเนื่อง (เวลาจริง ไม่ใช่ขั้นเวลาตายตัว) — ผลแน่นอน ไม่สุ่ม · ไม่มีเศษเวลาหาย
-- ⚠️ ลูกในแถว **ยังนับอยู่ในกองของตัวเอง** (data.children) จนกว่าจะตาย → หักทีละตัวตอนตาย
--   ออกเกม/ปิดอัญเชิญ/กำแพงพัง/ติดล็อกบอส = ล้างแถว ลูกที่รอด "กลับกอง" เองโดยไม่ต้องคืน (ไม่มีทางหายตอนเซฟ)
-- ⚠️ ศัตรูบาดเจ็บ (ตัวหน้าสุด) อยู่ใน meta (memory) · stageProgress ยังเก็บ HP รวมเหมือนเดิม (ไม่แตะ schema)
--   meta หาย (ออกเกม/เซิร์ฟใหม่/debug ตั้งค่า) = คำนวณตัวหน้าสุด + เลือดจาก HP รวมได้เป๊ะ (buildEnemyState)
--
-- ⚠️ ปล่อยเฉพาะตอนออนไลน์เท่านั้น — ต่างจาก ProductionService ที่มี offline settlement
-- ปิดเกม/ออกเกมแล้วหยุดสู้ทันที ไม่มี catch-up ย้อนหลัง (docs/data-schema.md §7.1)
-- ฟังก์ชันหลักรับ elapsedSeconds ตรง ๆ จาก loop ที่เรียก (CombatService.start()) ทำให้เทสต์เรียกตรง ๆ
-- ได้เลยโดยไม่ต้องปลอมนาฬิกา
--
-- ⚠️ require แบบสองทางเหมือน ProductionService/DataService เพื่อให้ tests/run.luau
-- require ไฟล์นี้ได้ตรง ๆ โดยไม่ต้องเปิด Studio (โค้ดที่แตะ Roblox API จริงมีแค่ CombatService.start())
local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") else nil
local Config = (if Shared then require(Shared.Config) else require("../shared/Config")) :: any

type Data = any
type StageProgress = { defendersRemaining: number, wallHpRemaining: number }

local CombatService = {}

--------------------------------------------------------------------------------
-- meta ต่อผู้เล่น — ของที่ **ห้ามเซฟ** ตายพร้อมเซสชัน (เหมือน EggService.sessionMeta)
--------------------------------------------------------------------------------
-- สนามทั้งสองฝั่ง + นาฬิกาป้อม + ตัวนับ auto-pause · ไม่มี offline catch-up ให้ระบบนี้อยู่แล้ว
-- ออกเกม = ทหารเราบนสนามกลับกอง (ไม่เคยถูกหักออก) · ศัตรูบาดเจ็บสร้างใหม่จาก HP รวมตอนกลับมา

export type OurUnit = {
	id: number, -- เลขประจำตัวในเซสชัน (ภาพใช้ตามตัวตอนแถวขยับ · ไม่เซฟ)
	kind: "child" | "mother",
	key: string?, -- stack key ของลูก (ตายแล้วหักจากกองนี้ 1 ตัว)
	uid: string?, -- uid ของแม่ (ตายแล้วออกจาก battleRoster)
	charId: string,
	weight: number, -- น้ำหนักของตัวนี้เอง (ลูก = Config.getChildWeight)
	statuses: { string }?,
	hp: number,
	maxHp: number,
	dps: number,
}

-- 5E-1b: แถวศัตรู = ลำดับตายตัวของด่าน (Config.getEnemyKindAt) · เก็บแค่ "ตัวหน้าสุดคือตัวที่เท่าไร + เลือดที่เหลือ"
export type EnemyState = {
	stage: number,
	frontIndex: number, -- ศัตรูตัวหน้าสุด = ตัวที่เท่านี้ของด่าน (1 = ตัวแรก) · เกิน total = หมดแล้ว
	frontHp: number, -- เลือดที่เหลือของตัวหน้าสุด
	total: number, -- จำนวนศัตรูทั้งด่าน
	knownDefenders: number, -- defendersRemaining ที่สถานะนี้ตรงอยู่ (ไม่ตรง = มีคนแก้จากข้างนอก → สร้างใหม่)
	atMiddle: boolean, -- เดินออกมายืนกึ่งกลางเลนแล้ว (ภาพ) — แถวใหม่เริ่มที่กำแพงเสมอ
}

export type CombatMeta = {
	coinCarry: number, -- เศษเหรียญที่ยังไม่ถึง 1 เหรียญ สะสมข้ามรอบ tick
	lastTickClock: number?, -- os.clock() ของ tick ก่อนหน้า ใช้เฉพาะใน loop จริง (ไม่ใช้ในเทสต์)
	line: { OurUnit }, -- 5E-1b: แถวเรา ตัวที่ 1 = หน้าสุด · ยาวไม่เกิน LINE_LENGTH
	enemy: EnemyState?,
	-- 5E-1b รอบวนปล่อย: ลำดับที่ผู้เล่นติ๊ก (stack key + uid แม่ปนกัน) — **จำใน memory เท่านั้น** (ผู้ใช้เลือก · ไม่แตะ schema)
	-- หาย (ออกเกม/เซิร์ฟใหม่) = แม่ใน roster ไปต่อท้ายรอบวน (getReleaseCycle)
	cycleOrder: { string }?,
	cursorId: string?, -- รายการล่าสุดที่ปล่อย (stack key / uid) — ตัวถัดไปปล่อยต่อจากนี้
	cursorIndex: number, -- ตำแหน่งของรายการนั้นในรอบวนตอนปล่อย (0 = ยังไม่เคยปล่อย)
	nextUnitId: number, -- เลขประจำตัวทหารตัวถัดไป (ภาพเท่านั้น)
	turretClock: number, -- วินาทีที่สะสมตั้งแต่นัดล่าสุด
	deathsSinceProgress: number, -- auto-pause: ทหารเราตายติดกันโดยที่ HP ฝั่งตรงข้ามไม่ลดเลย
	lastTurretShots: number, -- นัดที่ป้อมยิงใน tick ล่าสุด (ภาพเท่านั้น)
	lastTurretTarget: number?, -- ตำแหน่งในแถวที่โดนนัดล่าสุด (ภาพเท่านั้น · ป้อมยิงตัวหน้าสุด = 1 เสมอ)
	-- 5E-1 เดินทัพ (ผู้ใช้สั่ง): แถวเราอยู่/กำลังไปที่ไหน · ระหว่างเดินไม่มีใครตีใคร · ป้อมยิงเฉพาะ lineAt = "wall" ที่เดินถึงแล้ว
	lineAt: ("middle" | "wall")?, -- nil = แถวว่าง
	marchFrom: ("pedestal" | "middle" | "wall")?,
	marchRemaining: number, -- วินาทีที่ยังต้องเดิน (0 = ถึงแล้ว)
	marchDuration: number,
}

local combatMeta: { [number]: CombatMeta } = {}

-- ป้อมเปิด/ปิดทั้งเซิร์ฟ — debugTurret(false) ใช้ทดสอบใน Studio เท่านั้น (ค่าเริ่มต้นเปิดเสมอ)
local turretEnabled = true

function CombatService.newMeta(): CombatMeta
	return {
		coinCarry = 0,
		lastTickClock = nil,
		line = {},
		enemy = nil,
		cycleOrder = nil,
		cursorId = nil,
		cursorIndex = 0,
		nextUnitId = 0,
		turretClock = 0,
		deathsSinceProgress = 0,
		lastTurretShots = 0,
		lastTurretTarget = nil,
		lineAt = nil,
		marchFrom = nil,
		marchRemaining = 0,
		marchDuration = 0,
	}
end

function CombatService.getOrCreateMeta(userId: number): CombatMeta
	local meta = combatMeta[userId]
	if not meta then
		meta = CombatService.newMeta()
		combatMeta[userId] = meta
	end
	return meta
end

-- meta ที่มีอยู่แล้ว (ไม่สร้างใหม่) — sync ใช้แสดงสนาม
function CombatService.getMeta(userId: number): CombatMeta?
	return combatMeta[userId]
end

function CombatService.clearMeta(userId: number)
	combatMeta[userId] = nil
end

function CombatService.setTurretEnabled(enabled: boolean)
	turretEnabled = enabled == true
end

function CombatService.isTurretEnabled(): boolean
	return turretEnabled
end

--------------------------------------------------------------------------------
-- ด่านที่กำลังตี — ตีเรียงลำดับด่านเท่านั้น ห้ามข้ามด่าน
--------------------------------------------------------------------------------

-- ด่านแรกที่ยังตีไม่จบ (ยังไม่เคยเริ่ม หรือเริ่มแล้วแต่ยังมี HP เหลือ)
-- คืน nil เมื่อผ่านครบทุกด่านแล้ว (defendersRemaining=0 และ wallHpRemaining=0 ทั้ง 9 ด่าน)
function CombatService.getActiveStage(data: Data): number?
	for stage = 1, Config.Balance.Stage.COUNT do
		local progress = data.stageProgress[stage]
		-- ⚠️ ใช้ type() ไม่ใช่ ~= false — Luau ขยาย `X | false` เป็น `X | boolean`
		-- ทำให้เทียบกับ false แล้วไม่แคบลง (แบบเดียวกับ EggService.buildSyncPayload)
		if type(progress) ~= "table" then
			return stage
		end
		if progress.defendersRemaining > 0 or progress.wallHpRemaining > 0 then
			return stage
		end
	end
	return nil
end

-- init ด่านที่แตะเป็นครั้งแรก (จาก false) — เรียกซ้ำได้ปลอดภัย (idempotent)
-- ⚠️ defendersRemaining เริ่มจาก Config.getStageDefenderHp() (HP ทหารฝ่ายรับล้วน ๆ)
-- ไม่ใช่ Config.getStageTotalHp() ซึ่งเป็นผลรวมทหาร+กำแพง — ใช้ผิดตัวจะเท่ากับให้กำแพง
-- มี HP ซ้ำสองชั้น (นับใน defendersRemaining ด้วย แล้วก็ยังนับใน wallHpRemaining อีกที)
function CombatService.ensureStageStarted(data: Data, stage: number)
	if type(data.stageProgress[stage]) ~= "table" then
		data.stageProgress[stage] = {
			defendersRemaining = Config.getStageDefenderHp(stage),
			wallHpRemaining = Config.getStageWallHp(stage),
		}
	end
end

--------------------------------------------------------------------------------
-- releaseOrder — คิวปล่อยทหารที่ผู้เล่นจัดลำดับเอง
--------------------------------------------------------------------------------

-- ⚠️ UI-3: **ปล่อยเฉพาะกองที่ผู้เล่นติ๊กไว้** — releaseOrder = กองที่เลือกเรียงตามลำดับติ๊ก
-- กองที่ไม่อยู่ในนี้ไม่ถูกปล่อยเลย (เดิมมี reconcileReleaseOrder ต่อท้ายกองใหม่ให้อัตโนมัติทุก tick
-- = ทุกกองถูกปล่อยหมด · ผู้ใช้ตัดสินให้ตัดทิ้งตอน UI-3) · ไม่แตะ schema (ฟิลด์เดิม ความหมายแคบลง)
-- ⚠️ ไม่ลบ key ออกจาก releaseOrder แม้กองนั้นจะว่างแล้ว (เผื่อผลิตเพิ่มมาเติมทีหลัง
-- จะได้ถูกปล่อยต่อในลำดับเดิมโดยไม่ต้องติ๊กใหม่) · เขียนได้ทางเดียวคือ handleSetReleaseOrder

--------------------------------------------------------------------------------
-- battleRoster — แม่ที่ส่งไปรบ (Phase 3C-1)
--------------------------------------------------------------------------------
-- ⚠️ แม่หนึ่งตัวอยู่ได้ที่เดียว: ส่งไปรบ = ย้ายออกจาก mothersInBag มาไว้ data.battleRoster
-- ย้อนกลับไม่ได้ · ตายหมดพร้อมกันตอนด่านที่กำลังตีพัง (killRoster)
-- 5E-1: แม่ลงสนามทีละตัวตามลำดับ roster (ช่องหลังสุด) · โดนฆ่ากลางสนาม = ตายถาวร ออกจาก roster ทันที

-- ด่านที่กำลังตีรับแม่ได้ไหม · คืนเหตุผลภาษาไทยถ้าไม่ได้ (nil = ส่งได้)
-- ⚠️ ใช้ร่วมกันทั้งส่งทีละตัวและส่งเป็นชุด (UI-3) — client ใช้ข้อความเดียวกันนี้ (ผ่าน sync) บอกว่าทำไมติ๊กแม่ไม่ได้
-- Phase 5A: `bossLocked` = ผู้เล่นคนนี้ติดล็อกอัญเชิญเพราะบอส (BossService) → ส่งแม่ไม่ได้ด้วย (แม่จะไปยืนรอเปล่า ๆ)
--   เช็คท้ายสุด — "ผ่านครบทุกด่าน" บอกความจริงได้ตรงกว่าถ้าเกิดพร้อมกัน · ไม่ส่ง = ค่าเดิมทุกอย่าง (เทสต์เก่าไม่เปลี่ยน)
function CombatService.getSendStageBlockReason(data: Data, bossLocked: boolean?): string?
	local stage = CombatService.getActiveStage(data)
	if not stage then
		return "ผ่านครบทุกด่านแล้ว ไม่มีด่านให้ส่งแม่ไปรบ"
	end
	-- ⚠️ ด่านที่ไม่มีศัตรูเลย (ด่าน 1) นับว่า "พัง" ตั้งแต่ตาแรกที่แตะ → แม่จะตายฟรีทันที
	if Config.getStageTotalHp(stage) <= 0 then
		return `ด่าน {stage} ไม่มีศัตรูให้ตี — เปิดอัญเชิญให้ผ่านด่านนี้ไปก่อน`
	end
	if bossLocked then
		return Config.BOSS_LOCK_MESSAGE
	end
	return nil
end

--------------------------------------------------------------------------------
-- Phase 5A — ล็อกอัญเชิญเพราะบอส (สถานะล็อกเก็บที่ BossService · ตรงนี้แค่กติกาฝั่งการรบ)
--------------------------------------------------------------------------------
-- ⚠️ **ไม่แตะ** การนับผ่านด่าน / รางวัลผ่านด่าน (4A) / แม่ตายตอนด่านพัง — ทั้งหมดเกิดใน tick ไปแล้ว
--   ก่อนล็อกจะถูกตั้ง (CombatService.start ตัดสินล็อกจาก TickResult หลัง tick จบ) ล็อกแค่ "ห้ามเริ่มปล่อยต่อ"
-- ⚠️ รวมกับ auto-pause (ไม่แทนที่): auto-pause ยังตั้ง/ล้างธงของมันเหมือนเดิม · ล็อกบอสบล็อกการเปิดอัญเชิญซ้ำอีกชั้น

-- ด่านที่เพิ่งพังตานี้ควรทำให้ผู้เล่นติดล็อกไหม — เฉพาะด่านที่ **มีกำแพงจริง** + บอสยังมีชีวิต
-- 5B-2: bossAlive = บอส**ห้องของด่านนั้น** (ห้อง N หลังกำแพง N) ยังมีชีวิตไหม — ผู้เรียกถาม gate ด้วยเลขด่านเอง
-- ⚠️ ด่าน 1 ไม่มีกำแพง "พัง" ตั้งแต่ทหารตัวแรก → ไม่ยกเว้น = ผู้เล่นใหม่ติดล็อกตั้งแต่วินาทีแรก
function CombatService.shouldBossLock(clearedStage: number?, bossAlive: boolean): boolean
	return clearedStage ~= nil and bossAlive and Config.getWallX(clearedStage) ~= nil
end

-- ติดล็อก = ปิดอัญเชิญ (ผู้ใช้เลือก: บอสตายแล้วต้องกด "ส่งไปรบ" ใหม่เอง ไม่เดินต่อเอง)
-- ไม่แตะ combatAutoPaused — คำเตือน auto-pause (ถ้ามี) ยังค้างให้เห็นคู่กัน
function CombatService.applyBossLock(data: Data)
	data.summonEnabled = false
end

-- เหตุผลที่เปิดอัญเชิญไม่ได้ตอนนี้ (nil = เปิดได้) · client โชว์ในหน้าต่างอัญเชิญ + ปิดปุ่มส่งไปรบ
function CombatService.getSummonBlockReason(bossLocked: boolean?): string?
	if bossLocked then
		return Config.BOSS_LOCK_MESSAGE
	end
	return nil
end

-- คืน (ok, message) — message เป็นภาษาไทยพร้อมโชว์ผู้เล่นทาง ActionResult ทั้งกรณีสำเร็จ/ล้มเหลว
-- ⚠️ ด่านสุดท้ายของการตรวจ — client ตรวจ roster เต็มก่อนเองก็จริง แต่ห้ามเชื่อ client
function CombatService.handleSendMotherToBattle(data: Data, rawUid: unknown, bossLocked: boolean?): (boolean, string)
	if type(rawUid) ~= "string" then
		return false, "ข้อมูลแม่ไม่ถูกต้อง"
	end

	local bagIndex: number? = nil
	for index, mother in data.mothersInBag do
		if mother.uid == rawUid then
			bagIndex = index
			break
		end
	end
	if not bagIndex then
		-- แม่ในคอก/uid ของคนอื่น/แม่ที่ส่งไปแล้ว ตกมาทางนี้หมด (MOTHERS_SELECTABLE_FROM_PEN = false)
		return false, "ส่งไปรบได้เฉพาะแม่ในกระเป๋าของตัวเองเท่านั้น"
	end
	if data.mothersInBag[bagIndex].locked then
		return false, "แม่ตัวนี้ถูกล็อกไว้ ส่งไปรบไม่ได้"
	end

	local maxMothers = Config.Balance.Combat.MAX_BATTLE_MOTHERS
	if #data.battleRoster >= maxMothers then
		return false, `roster เต็มแล้ว ({#data.battleRoster}/{maxMothers})`
	end

	local stageBlock = CombatService.getSendStageBlockReason(data, bossLocked)
	if stageBlock then
		return false, stageBlock
	end

	local mother = table.remove(data.mothersInBag, bagIndex)
	table.insert(data.battleRoster, mother)
	return true, `ส่งแม่ไปรบแล้ว (roster {#data.battleRoster}/{maxMothers})`
end

export type SendBatchSummary = {
	sent: number,
	skipped: number,
	rosterCount: number,
}

-- ส่งแม่เป็นชุด (UI-3 · SendMothersToBattleBatchRequest) — แท่นอัญเชิญยิงครั้งเดียวแทนทีละตัว
-- ⚠️ ตรวจรูปร่างทั้งชุดก่อน (Config.parseUidList · 1..MAX_BATTLE_MOTHERS ตัว) ไม่ผ่าน = ปฏิเสธทั้งชุด
-- ⚠️ ไม่มีด่านให้ส่ง (ผ่านครบ / ด่านที่กำลังตี HP 0) = ปฏิเสธทั้งชุดด้วยข้อความเดียวกับส่งทีละตัว
-- แต่ละตัวผ่าน handleSendMotherToBattle ตัวเดียวกับส่งทีละตัว (กฎไม่ได้เขียนใหม่) เรียงตามที่ส่งมา
--   ตัวที่ส่งไม่ได้ (ล็อก / ไม่ใช่ของตัวเอง / อยู่ในคอก / roster เต็ม / uid ซ้ำในชุด) ข้าม ส่งตัวถัดไปต่อ
--   → roster ไม่มีวันเกิน MAX_BATTLE_MOTHERS (แกนเดิมเช็คทุกตัว) · ลำดับใน roster = ลำดับที่ส่งมา
-- คืน (ok, reason?, summary?) · summary = nil เฉพาะตอนปฏิเสธทั้งชุด · ไม่ sync (ผู้เรียกทำครั้งเดียว)
function CombatService.handleSendMothersToBattleBatch(
	data: Data,
	rawUids: unknown,
	bossLocked: boolean?
): (boolean, string?, SendBatchSummary?)
	local maxMothers = Config.Balance.Combat.MAX_BATTLE_MOTHERS
	local uids, listError = Config.parseUidList(rawUids, maxMothers)
	if not uids then
		if listError == "empty" then
			return false, "ยังไม่ได้เลือกแม่ที่จะส่งไปรบ", nil
		elseif listError == "too_many" then
			return false, `ส่งแม่ไปรบได้ครั้งละไม่เกิน {maxMothers} ตัว`, nil
		elseif listError == "not_string" then
			return false, "uid ในรายการต้องเป็น string", nil
		end
		return false, "รายการแม่ที่จะส่งไปรบต้องเป็น array", nil
	end

	local stageBlock = CombatService.getSendStageBlockReason(data, bossLocked)
	if stageBlock then
		return false, stageBlock, nil
	end

	local summary: SendBatchSummary = { sent = 0, skipped = 0, rosterCount = #data.battleRoster }
	local seen: { [string]: boolean } = {}
	for _, uid in uids do
		-- ⚠️ uid ซ้ำในชุด = ข้าม (ตัวแรกย้ายเข้า roster ไปแล้ว ตัวที่สองหาในกระเป๋าไม่เจออยู่ดี — นับให้ชัด)
		if seen[uid] then
			summary.skipped += 1
		else
			seen[uid] = true
			local ok = CombatService.handleSendMotherToBattle(data, uid, bossLocked)
			if ok then
				summary.sent += 1
			else
				summary.skipped += 1
			end
		end
	end
	summary.rosterCount = #data.battleRoster

	if summary.sent == 0 then
		return false, "ไม่มีแม่ตัวไหนส่งไปรบได้", summary
	end
	return true, nil, summary
end

-- แม่ทั้ง roster ตายถาวรพร้อมกัน — เรียกตอนด่านที่กำลังตีพังเท่านั้น · คืนจำนวนที่ตาย
-- ⚠️ ด่านที่ไม่มีศัตรูเลย (HP รวม 0) "พัง" ได้ฟรีโดยไม่ได้สู้จริง → ไม่ฆ่า (ตาข่ายกันไว้ชั้นสอง
-- ต่อจากที่ handleSendMotherToBattle ปฏิเสธการส่งตอนด่านแบบนี้อยู่แล้ว)
function CombatService.killRoster(data: Data, clearedStage: number): number
	if Config.getStageTotalHp(clearedStage) <= 0 then
		return 0
	end
	local lost = #data.battleRoster
	if lost > 0 then
		-- uid ของแม่ที่ตายไม่ถูก reuse — nextUid เดินหน้าอย่างเดียวอยู่แล้ว ไม่ต้องทำอะไรเพิ่ม
		table.clear(data.battleRoster)
		data.stats.mothersLost = (data.stats.mothersLost or 0) + lost
	end
	return lost
end

--------------------------------------------------------------------------------
-- รางวัลผ่านด่าน (Phase 4A) — ไข่ฟรีครั้งเดียวต่อด่าน
--------------------------------------------------------------------------------
-- ⚠️ เรียกจาก tick ตรงจังหวะ "ด่านเพิ่งพัง" เท่านั้น **ห้ามเรียกจาก recomputeWallProgress**
-- (ฟังก์ชันนั้นไล่นับด่านที่พังอยู่ทั้งหมดใหม่ทุกครั้ง — ถ้าให้รางวัลตรงนั้น ผู้เล่นเก่าที่ธงเป็น false
-- จะได้ไข่ย้อนหลังทุกด่านที่เคยพัง และ debugSetStageProgress ก็เรียกมันด้วย)
-- ติดธงก่อนคืนค่าเสมอ → เรียกซ้ำกี่ครั้งก็ได้ 0 · ด่านที่ไม่มีอะไรให้ตี (ด่าน 1) ได้ 0 และไม่ติดธง
-- คืน "จำนวนไข่ที่ต้องแจก" — การสร้างไข่จริงอยู่ที่ EggService (ผ่าน grantEgg ตัวเดียวกับไข่ทุกแหล่ง)
function CombatService.claimStageClearBonus(data: Data, clearedStage: number): number
	if Config.getStageTotalHp(clearedStage) <= 0 then
		return 0
	end
	if data.stageClearBonusGranted[clearedStage] == true then
		return 0
	end
	data.stageClearBonusGranted[clearedStage] = true
	return Config.getStageClearBonusEggs(clearedStage)
end

--------------------------------------------------------------------------------
-- ใส่ damage ให้ด่าน — ทหารฝ่ายรับก่อน ส่วนเกินไหลไปกำแพงในตาเดียวกัน
--------------------------------------------------------------------------------

-- เงินรางวัล: ตามสัดส่วน HP ทหารฝ่ายรับ (ไม่รวมกำแพง) ที่ลดไปในตานี้เท่านั้น
-- ⚠️ ยืนยันจาก Config แล้ว: Config.getStageDefenderRewardTotal(stage)
-- = Config.getStageDefenderCount(stage) × Config.getDefenderKillReward(stage)
-- = (Config.getStageDefenderHp(stage) / DEFENDER_HP) × (เงิน/ตัว)
-- ⇒ เงินต่อ HP ทหาร 1 หน่วย = getStageDefenderRewardTotal(stage) ÷ getStageDefenderHp(stage) คงที่
-- ดังนั้น "ลด HP ทหารไป X" ต้องได้เงิน (X ÷ getStageDefenderHp(stage)) × getStageDefenderRewardTotal(stage)
-- **ไม่มีฟังก์ชันรางวัลของกำแพงเลยใน Config** — HP กำแพงที่ลดไปจึงไม่ได้เงินสักบาท (ตั้งใจ)
-- คืน (dmgToDefenders, dmgToWall, coinsEarned, stageCleared)
function CombatService.applyDamageToStage(
	data: Data,
	meta: CombatMeta,
	stage: number,
	damage: number
): (number, number, number, boolean)
	if damage <= 0 then
		return 0, 0, 0, false
	end

	local progress = data.stageProgress[stage] :: StageProgress
	assert(
		type(progress) == "table",
		`CombatService: ด่าน {stage} ยังไม่เริ่ม — ต้องเรียก ensureStageStarted ก่อน`
	)

	local dmgToDefenders = math.min(damage, progress.defendersRemaining)
	progress.defendersRemaining -= dmgToDefenders

	local overflow = damage - dmgToDefenders
	local dmgToWall = math.min(overflow, progress.wallHpRemaining)
	progress.wallHpRemaining -= dmgToWall

	local coinsEarned = 0
	if dmgToDefenders > 0 then
		local defenderHpTotal = Config.getStageDefenderHp(stage)
		local rewardTotal = Config.getStageDefenderRewardTotal(stage)
		local coinBudget = meta.coinCarry + (dmgToDefenders / defenderHpTotal) * rewardTotal
		coinsEarned = math.floor(coinBudget)
		meta.coinCarry = coinBudget - coinsEarned

		if coinsEarned > 0 then
			data.currency.coins += coinsEarned
			data.stats.coinsFromKills += coinsEarned
			data.stats.totalCoinsEarned += coinsEarned
		end
	end

	local stageCleared = progress.defendersRemaining <= 0 and progress.wallHpRemaining <= 0
	return dmgToDefenders, dmgToWall, coinsEarned, stageCleared
end

--------------------------------------------------------------------------------
-- wallProgress — เชื่อมกับ stageProgress ที่ตีผ่านจริง (แพตช์ 3A)
--------------------------------------------------------------------------------
-- ⚠️ `data.wallProgress` (ตัวคูณเงิน `10^(wallProgress-1)` + เพดานซื้อตัวคูณ damage
-- `wallProgress × STEPS_PER_STAGE`) เดิมไม่เคยถูกอัปเดตตอนตีด่านผ่านจริงเลย ค้างที่ค่าเริ่มต้น
-- (Config.Balance.NewPlayer.wallProgress = 1) ตลอดไปแม้กำแพง/ทหารจะหายไปแล้วจริง (stageProgress)
--
-- สูตร: wallProgress = จำนวนด่านที่พังเรียบร้อยติดต่อกันนับจากด่าน 1 (ตีเรียงลำดับเท่านั้น
-- ไม่มีการข้ามด่าน จึงสแกนจากด่าน 1 หยุดที่ด่านแรกที่ยังไม่พังเรียบร้อยได้เลย) ไม่ต่ำกว่า 1 เสมอ
-- (ด่าน 1 ไม่มีกำแพงให้พัง — "พังเรียบร้อย" ของด่าน 1 เกิดฟรีตั้งแต่ตาแรกที่แตะ ไม่ควรนับเป็น
-- ความคืบหน้าเพิ่มเติมเหนือค่าเริ่มต้น พอด่าน 2 ซึ่งมีกำแพงจริงพังตามมา ค่าถึงขยับขึ้นจริง)
-- ⚠️ ห้ามลดค่าลง (math.max กับของเดิม) — ถึงจะไม่มีทางเกิดในโค้ดปกติ (ตีเรียงลำดับ ไม่ถอยหลัง)
-- แต่กันไว้เผื่อ data เพี้ยนมาจากที่อื่น (เช่น debugSetWallProgress ตั้งไว้สูงกว่าความจริงชั่วคราว)
function CombatService.recomputeWallProgress(data: Data)
	local cleared = 0
	for stage = 1, Config.Balance.Stage.COUNT do
		local progress = data.stageProgress[stage]
		if type(progress) == "table" and progress.defendersRemaining <= 0 and progress.wallHpRemaining <= 0 then
			cleared += 1
		else
			break
		end
	end

	local computed = math.min(math.max(1, cleared), Config.Balance.Stage.COUNT)
	if computed > data.wallProgress then
		data.wallProgress = computed
	end
end

--------------------------------------------------------------------------------
-- 5E-1b แถวศัตรู — วนตายตัว เล็ก 5 → ใหญ่ 1 · ตายเรียงลำดับเสมอ (โดนแค่ตัวหน้าสุด)
--------------------------------------------------------------------------------

local EPSILON = 1e-9
-- ⚠️ กันลูปเหตุการณ์ยาวผิดปกติ (ค่าจริงไม่กี่สิบเหตุการณ์ต่อวินาที) · ชนแล้ว tick นั้นหยุดตรงนั้น ไม่พัง
local MAX_EVENTS_PER_TICK = 20000

local function lineLength(): number
	return Config.Balance.Combat.LINE_LENGTH
end

local function enemyUnitHp(stats: any, index: number): number
	return if Config.getEnemyKindAt(index) == "big" then stats.bigHp else stats.smallHp
end

local function enemyUnitDps(stats: any, index: number): number
	return if Config.getEnemyKindAt(index) == "big" then stats.bigDps else stats.smallDps
end

-- สร้างแถวศัตรูจาก HP ทหารฝ่ายรับที่เหลือ (stageProgress) — ใช้ตอนเริ่มด่าน / meta หาย / มีคนแก้ค่าจากข้างนอก
-- ⚠️ ตรงเป๊ะ ไม่ใช่ประมาณ: ศัตรูโดนแค่ตัวหน้าสุดและตายเรียงลำดับ → HP ที่ตีไปแล้ว (รวม − เหลือ) บอกได้เลยว่า
--   ตัวหน้าสุดคือตัวที่เท่าไรและเหลือเลือดเท่าไร (เลือดรวม + เงินตรงกับที่เซฟไว้เสมอ · ไม่แตะ schema)
function CombatService.buildEnemyState(stage: number, defendersRemaining: number): EnemyState
	local stats = Config.getStageEnemyStats(stage)
	local total = stats.bigCount + stats.smallCount
	local state: EnemyState = {
		stage = stage,
		frontIndex = total + 1,
		frontHp = 0,
		total = total,
		knownDefenders = defendersRemaining,
		atMiddle = false,
	}
	if total <= 0 or defendersRemaining <= 0 then
		return state
	end
	local combat = Config.Balance.Combat
	local cycleLength = Config.getEnemyCycleLength()
	local cycleHp = combat.ENEMY_SMALL_PER_GROUP * stats.smallHp + combat.ENEMY_BIG_PER_GROUP * stats.bigHp
	local dealt = math.max(0, stats.totalHp - math.min(defendersRemaining, stats.totalHp))
	local cycles = math.min(math.floor(dealt / cycleHp + EPSILON), stats.cycles)
	local rest = math.max(0, dealt - cycles * cycleHp)
	local index = cycles * cycleLength + 1
	while index <= total do
		local hp = enemyUnitHp(stats, index)
		if rest < hp - hp * EPSILON then
			break
		end
		rest = math.max(0, rest - hp)
		index += 1
	end
	state.frontIndex = index
	state.frontHp = if index <= total then enemyUnitHp(stats, index) - rest else 0
	return state
end

local function ensureEnemyState(meta: CombatMeta, data: Data, stage: number): EnemyState
	local progress = data.stageProgress[stage] :: StageProgress
	local current = meta.enemy
	local tolerance = math.max(1e-6, Config.getStageDefenderHp(stage) * EPSILON)
	if current and current.stage == stage and math.abs(current.knownDefenders - progress.defendersRemaining) <= tolerance then
		return current
	end
	local rebuilt = CombatService.buildEnemyState(stage, progress.defendersRemaining)
	meta.enemy = rebuilt
	return rebuilt
end

local function enemiesRemain(enemy: EnemyState): boolean
	return enemy.frontIndex <= enemy.total
end

-- ศัตรูที่เหลือทั้งหมด (ตัวหน้าสุดถึงตัวสุดท้ายของด่าน) แยกใหญ่/เล็ก — HUD "เหลือศัตรูกี่ตัว"
function CombatService.countEnemies(enemy: EnemyState?): (number, number)
	if not enemy or enemy.frontIndex > enemy.total then
		return 0, 0
	end
	local remaining = enemy.total - enemy.frontIndex + 1
	local big = Config.countEnemyBigUpTo(enemy.total) - Config.countEnemyBigUpTo(enemy.frontIndex - 1)
	return big, remaining - big
end

-- ใส่ดาเมจ `amount` ให้ศัตรูตัวหน้าสุด — ตายแล้วตัวถัดไปในรอบวนขึ้นเป็นหน้าสุด (ดาเมจที่เหลือไหลต่อ)
-- คืน (HP ที่ลดจริง, จำนวนที่ตาย) · ดาเมจเกินตัวสุดท้ายของด่านทิ้งไป
local function damageEnemyFront(enemy: EnemyState, stats: any, amount: number): (number, number)
	local dealt, killed = 0, 0
	while amount > 0 and enemy.frontIndex <= enemy.total do
		local maxHp = enemyUnitHp(stats, enemy.frontIndex)
		if amount < enemy.frontHp - maxHp * EPSILON then
			enemy.frontHp -= amount
			dealt += amount
			return dealt, killed
		end
		dealt += enemy.frontHp
		amount = math.max(0, amount - enemy.frontHp)
		killed += 1
		enemy.frontIndex += 1
		enemy.frontHp = if enemy.frontIndex <= enemy.total then enemyUnitHp(stats, enemy.frontIndex) else 0
	end
	return dealt, killed
end

--------------------------------------------------------------------------------
-- 5E-1b แถวเรา + รอบวนปล่อย (แม่ + กองลูกในรอบเดียวกัน)
--------------------------------------------------------------------------------

-- ลูกในแถวต่อกอง (ยังนับอยู่ใน data.children) · client/sync ใช้หักออกจากจำนวนที่ "พร้อมปล่อย"
function CombatService.getReservedChildren(meta: CombatMeta?): { [string]: number }
	local reserved: { [string]: number } = {}
	if not meta then
		return reserved
	end
	for _, unit in meta.line do
		if unit.kind == "child" and unit.key then
			reserved[unit.key] = (reserved[unit.key] or 0) + 1
		end
	end
	return reserved
end

local function motherInLine(meta: CombatMeta, uid: string): boolean
	for _, unit in meta.line do
		if unit.kind == "mother" and unit.uid == uid then
			return true
		end
	end
	return false
end

export type CycleItem = {
	kind: "child" | "mother",
	id: string, -- stack key (ลูก) / uid (แม่)
}

-- รอบวนที่ใช้ปล่อยจริง — ลำดับที่ผู้เล่นติ๊ก (meta.cycleOrder · แม่ + กองลูกปนกัน · จำใน memory)
-- กรองเหลือเฉพาะกองที่ติ๊กอยู่ (data.releaseOrder) + แม่ที่ยังอยู่ใน roster
-- ของที่ยังไม่อยู่ในลำดับ (ออกเกม/เซิร์ฟใหม่ = memory หาย · ส่งแม่ทางอื่น) ต่อท้าย: กองลูกตาม releaseOrder แล้วแม่ตาม roster
-- ⚠️ ผู้ใช้เลือก (5E-1b): ไม่แตะ schema — releaseOrder ที่เซฟยังเป็นลำดับกองลูกล้วนเหมือนเดิม
function CombatService.getReleaseCycle(data: Data, meta: CombatMeta?): { CycleItem }
	local ticked: { [string]: boolean } = {}
	for _, key in data.releaseOrder do
		ticked[key] = true
	end
	local inRoster: { [string]: boolean } = {}
	for _, mother in data.battleRoster do
		inRoster[mother.uid] = true
	end
	local items: { CycleItem } = {}
	local used: { [string]: boolean } = {}
	local function add(kind: "child" | "mother", id: string)
		if not used[id] then
			used[id] = true
			table.insert(items, { kind = kind, id = id })
		end
	end
	local order = if meta then meta.cycleOrder else nil
	if order then
		for _, id in order do
			if ticked[id] then
				add("child", id)
			elseif inRoster[id] then
				add("mother", id)
			end
		end
	end
	for _, key in data.releaseOrder do
		add("child", key)
	end
	for _, mother in data.battleRoster do
		add("mother", mother.uid)
	end
	return items
end

-- ตำแหน่งในรอบวนที่จะลองปล่อยตัวถัดไป — ต่อจากรายการล่าสุดที่ปล่อย
-- รายการล่าสุดหายไปจากรอบวน (แม่ตาย · เอาติ๊กออก) → ตัวถัดไปเลื่อนมาอยู่ตำแหน่งเดิมพอดี
function CombatService.getCycleStartIndex(cycle: { CycleItem }, meta: CombatMeta): number
	local count = #cycle
	if count == 0 then
		return 1
	end
	if meta.cursorId then
		for index, item in cycle do
			if item.id == meta.cursorId then
				return index % count + 1
			end
		end
	end
	if meta.cursorIndex >= 1 then
		return (meta.cursorIndex - 1) % count + 1
	end
	return 1
end

-- จำนวนที่พร้อมปล่อย = ลูกในกองที่ติ๊ก (ไม่นับตัวในแถว) + แม่ใน roster ที่ยังไม่อยู่ในแถว
function CombatService.countAvailable(data: Data, meta: CombatMeta): number
	local reserved = CombatService.getReservedChildren(meta)
	local total = 0
	for _, key in data.releaseOrder do
		local count = data.children[key]
		if count then
			total += math.max(0, math.floor(count) - (reserved[key] or 0))
		end
	end
	for _, mother in data.battleRoster do
		if not motherInLine(meta, mother.uid) then
			total += 1
		end
	end
	return total
end

local function makeChildUnit(data: Data, stage: number, key: string): OurUnit?
	local charId, motherWeight, statuses = Config.parseStackKey(key)
	if not charId or not motherWeight then
		return nil -- key เพี้ยน (ไม่น่าเกิด — ผ่าน makeStackKey เท่านั้น) → ข้าม
	end
	local weight = Config.getChildWeight(motherWeight, statuses)
	local hp = Config.getUnitHp(weight, charId, statuses)
	return {
		id = 0, -- fillLine แจกเลขจริงตอนปล่อย
		kind = "child",
		key = key,
		uid = nil,
		charId = charId,
		weight = weight,
		statuses = statuses,
		hp = hp,
		maxHp = hp,
		dps = Config.getUnitDps(stage, weight, charId, statuses, data.damageLevel, data.robuxDamageBonus),
	}
end

local function makeMotherUnit(data: Data, stage: number, mother: any): OurUnit
	local hp = Config.getUnitHp(mother.weight, mother.charId, mother.statuses)
	return {
		id = 0, -- fillLine แจกเลขจริงตอนปล่อย
		kind = "mother",
		key = nil,
		uid = mother.uid,
		charId = mother.charId,
		weight = mother.weight,
		statuses = mother.statuses,
		hp = hp,
		maxHp = hp,
		dps = Config.getUnitDps(stage, mother.weight, mother.charId, mother.statuses, data.damageLevel, data.robuxDamageBonus),
	}
end

-- ปล่อยต่อท้ายแถวจนยาว LINE_LENGTH — ทีละตัวตามรอบวน 1,2,…,N,1,2,… · คืนจำนวนที่ปล่อยรอบนี้
--   ถึงคิวกองลูก → ลูก 1 ตัวจากกองนั้น (กองหมด = ข้าม) · ถึงคิวแม่ → แม่ตัวนั้น (อยู่ในแถวแล้ว/ตายแล้ว = ข้าม)
--   วนครบรอบไม่เจออะไรปล่อยได้ = หยุด (แถวที่เหลือสู้ต่อ · ผลิตเพิ่มมาเมื่อไหร่ tick ถัดไปปล่อยต่อเอง)
-- ⚠️ ไม่มีรวมพลแล้ว (5E-1b) — ตัวเดียวก็ออกไปสู้ตัวต่อตัวได้เต็มแรง
function CombatService.fillLine(data: Data, meta: CombatMeta, stage: number): number
	local maxLength = lineLength()
	if #meta.line >= maxLength then
		return 0
	end
	local cycle = CombatService.getReleaseCycle(data, meta)
	local count = #cycle
	if count == 0 then
		return 0
	end
	local reserved = CombatService.getReservedChildren(meta)
	local mothersInLine: { [string]: boolean } = {}
	for _, unit in meta.line do
		if unit.kind == "mother" and unit.uid then
			mothersInLine[unit.uid] = true
		end
	end
	local rosterByUid: { [string]: any } = {}
	for _, mother in data.battleRoster do
		rosterByUid[mother.uid] = mother
	end

	local placed = 0
	while #meta.line < maxLength do
		local start = CombatService.getCycleStartIndex(cycle, meta)
		local released: OurUnit? = nil
		for step = 0, count - 1 do
			local index = (start - 1 + step) % count + 1
			local item = cycle[index]
			local unit: OurUnit? = nil
			if item.kind == "child" then
				local have = data.children[item.id]
				if have and math.floor(have) - (reserved[item.id] or 0) >= 1 then
					unit = makeChildUnit(data, stage, item.id)
				end
			else
				local mother = rosterByUid[item.id]
				if mother and not mothersInLine[item.id] then
					unit = makeMotherUnit(data, stage, mother)
				end
			end
			if unit then
				released = unit
				meta.cursorId = item.id
				meta.cursorIndex = index
				break
			end
		end
		if not released then
			break
		end
		local unit = released :: OurUnit
		meta.nextUnitId += 1
		unit.id = meta.nextUnitId
		table.insert(meta.line, unit)
		if unit.kind == "child" then
			local key = unit.key :: string
			reserved[key] = (reserved[key] or 0) + 1
		else
			mothersInLine[unit.uid :: string] = true
		end
		placed += 1
	end
	return placed
end

-- ล้างแถวเรา — ลูกที่รอดกลับกองเอง (ไม่เคยถูกหัก) · แม่ที่รอดยังอยู่ใน roster
-- ศัตรูไม่ถูกแตะ (บาดเจ็บค้างไว้รอรอบหน้า) · รอบวนจำตำแหน่งเดิมไว้ (ปล่อยต่อจากตัวถัดไป)
function CombatService.clearField(meta: CombatMeta)
	table.clear(meta.line)
	meta.lineAt = nil
	meta.marchFrom = nil
	meta.marchRemaining = 0
	meta.marchDuration = 0
end

-- ตัดทหารในแถวที่ของจริงหายไปแล้ว (debug ล้างคลัง · แม่ถูกย้ายออกจาก roster ทางอื่น) + อัปเดตดาเมจตามขั้นอัปล่าสุด
local function refreshLine(data: Data, meta: CombatMeta, stage: number)
	local reserved: { [string]: number } = {}
	local inRoster: { [string]: boolean } = {}
	for _, mother in data.battleRoster do
		inRoster[mother.uid] = true
	end
	local kept: { OurUnit } = {}
	for _, unit in meta.line do
		local keep = true
		if unit.kind == "child" then
			local key = unit.key :: string
			reserved[key] = (reserved[key] or 0) + 1
			keep = reserved[key] <= math.floor(data.children[key] or 0)
		else
			keep = inRoster[unit.uid :: string] == true
		end
		if keep then
			unit.dps = Config.getUnitDps(stage, unit.weight, unit.charId, unit.statuses, data.damageLevel, data.robuxDamageBonus)
			table.insert(kept, unit)
		end
	end
	if #kept ~= #meta.line then
		table.clear(meta.line)
		for _, unit in kept do
			table.insert(meta.line, unit)
		end
	end
end

--------------------------------------------------------------------------------
-- tick หลัก — เรียกทุกครั้งที่ผู้เล่นออนไลน์ (loop จริงอยู่ใน CombatService.start())
--------------------------------------------------------------------------------

export type TickResult = {
	unitsReleased: number, -- ทหารที่ปล่อยเข้าแถวใน tick นี้ (ลูก + แม่)
	damageDealt: number, -- HP ศัตรู + กำแพงที่ลดจริง
	coinsEarned: number,
	stageCleared: boolean,
	autoPaused: boolean,
	mothersLost: number, -- แม่ใน roster ที่ตายตอนด่านพัง (killRoster) — popup ผ่านด่านใช้ค่านี้
	mothersFallen: number, -- แม่ที่โดนฆ่ากลางสนาม (ตายถาวรเหมือนกัน · ไม่รวมใน mothersLost ข้างบน)
	childrenLost: number, -- ลูกที่ตายใน tick นี้
	enemiesKilled: number,
	turretShots: number,
	clearedStage: number?, -- ด่านที่เพิ่งพังในตานี้ (nil ถ้าไม่มี)
	bonusEggs: number, -- ไข่ฟรีที่ต้องแจก (Phase 4A) — 0 ถ้าไม่มีด่านพัง หรือเคยได้รางวัลด่านนี้แล้ว
}

local function emptyResult(): TickResult
	return {
		unitsReleased = 0,
		damageDealt = 0,
		coinsEarned = 0,
		stageCleared = false,
		autoPaused = false,
		mothersLost = 0,
		mothersFallen = 0,
		childrenLost = 0,
		enemiesKilled = 0,
		turretShots = 0,
		clearedStage = nil,
		bonusEggs = 0,
	}
end

-- ทหารเราตาย — ลูก: หักจากกอง 1 ตัว (+ สถิติ) · แม่: ออกจาก roster ถาวร (+ mothersLost)
local function killOurUnit(data: Data, unit: OurUnit, result: TickResult)
	if unit.kind == "child" then
		local key = unit.key :: string
		local count = (data.children[key] or 0) - 1
		data.children[key] = if count > 0 then count else nil
		data.stats.childrenLost = (data.stats.childrenLost or 0) + 1
		result.childrenLost += 1
	else
		for index, mother in data.battleRoster do
			if mother.uid == unit.uid then
				table.remove(data.battleRoster, index)
				data.stats.mothersLost = (data.stats.mothersLost or 0) + 1
				result.mothersFallen += 1
				break
			end
		end
	end
end

-- เดินสนามรบไป `seconds` วินาที (เหตุการณ์ต่อเนื่อง) · ด่านต้องเริ่มแล้วและยังไม่พัง
-- 5E-1b: ตัวหน้าสุดของเราตีตัวหน้าสุดของศัตรู (หรือกำแพง) · ศัตรูตัวหน้าสุดตีตัวหน้าสุดของเรา · ตัวอื่นรอคิว
local function runBattle(data: Data, meta: CombatMeta, stage: number, seconds: number, result: TickResult)
	local combat = Config.Balance.Combat
	local progress = data.stageProgress[stage] :: StageProgress
	local turretDps = if turretEnabled then Config.getStageTurretDps(stage) else 0
	local shotPeriod = 1 / combat.TURRET_SHOTS_PER_SECOND
	local shotDamage = turretDps * shotPeriod
	local wallTotal = Config.getStageWallHp(stage)
	local stats = Config.getStageEnemyStats(stage)
	local enemy = ensureEnemyState(meta, data, stage)
	local marchHalf = Config.getArmyMarchSeconds(stage)
	local cycleLength = Config.getEnemyCycleLength()
	local ns, nb = combat.ENEMY_SMALL_PER_GROUP, combat.ENEMY_BIG_PER_GROUP
	local cycleHp = ns * stats.smallHp + nb * stats.bigHp
	-- ดาเมจที่ตัวหน้าสุดเราโดนตลอดหนึ่งรอบวนศัตรู × ดาเมจ/วิของเรา (หาร ourDps ทีหลัง = ดาเมจที่โดนจริง)
	local cycleHitWork = ns * stats.smallHp * stats.smallDps + nb * stats.bigHp * stats.bigDps

	local function startMarch(from: "pedestal" | "middle" | "wall", to: "middle" | "wall", duration: number)
		meta.marchFrom = from
		meta.lineAt = to
		meta.marchDuration = duration
		meta.marchRemaining = duration
		meta.turretClock = 0
	end
	-- 5E-1 เดินทัพ: แถวว่าง = ไม่มีแนวรบ · ปล่อยใหม่ = เดินจากแท่น (ศัตรูยังอยู่ → ไปเจอกันกึ่งกลาง · หมดแล้ว → ไปกำแพงเต็มทาง) ·
	-- ศัตรูหมดตอนยืนกึ่งกลาง = เดินต่อไปกำแพง · ศัตรูกลับมาตอนยืนที่กำแพง (debug ตั้งค่า) = ถอยกลับไปกึ่งกลาง
	local function updateLine()
		if #meta.line == 0 then
			meta.lineAt = nil
			meta.marchFrom = nil
			meta.marchRemaining = 0
			return
		end
		if meta.lineAt == nil then
			if enemiesRemain(enemy) then
				startMarch("pedestal", "middle", marchHalf)
			else
				startMarch("pedestal", "wall", marchHalf * 2)
			end
		elseif meta.lineAt == "middle" and meta.marchRemaining <= 0 and not enemiesRemain(enemy) then
			startMarch("middle", "wall", marchHalf)
		elseif meta.lineAt == "wall" and enemiesRemain(enemy) then
			startMarch("wall", "middle", marchHalf)
		end
	end
	local function deploy()
		if #meta.line < combat.LINE_LENGTH then
			result.unitsReleased += CombatService.fillLine(data, meta, stage)
		end
		updateLine()
	end
	-- บัญชี HP ทหารฝ่ายรับ + เงิน (ตัวเดิม applyDamageToStage) · ⚠️ ช่วงศัตรูห้ามล้นไปกำแพง
	local function bookEnemyDamage(dealt: number): number
		local made = 0
		if dealt > 0 and progress.defendersRemaining > 0 then
			local toDefenders, _, coins = CombatService.applyDamageToStage(data, meta, stage, math.min(dealt, progress.defendersRemaining))
			made += toDefenders
			result.coinsEarned += coins
		end
		-- ศัตรูหมดทั้งด่าน → ปิดบัญชีเศษทศนิยมให้ HP ทหารฝ่ายรับเป็น 0 เป๊ะ (เงินครบตามรวม)
		if not enemiesRemain(enemy) and progress.defendersRemaining > 0 then
			local toDefenders, _, coins = CombatService.applyDamageToStage(data, meta, stage, progress.defendersRemaining)
			made += toDefenders
			result.coinsEarned += coins
		end
		return made
	end

	refreshLine(data, meta, stage)
	deploy()

	local t = 0
	local events = 0
	while t < seconds - EPSILON do
		events += 1
		if events > MAX_EVENTS_PER_TICK then
			warn(`[CombatService] เหตุการณ์เกิน {MAX_EVENTS_PER_TICK} ใน tick เดียว (ด่าน {stage}) — หยุด tick นี้ไว้ก่อน`)
			break
		end

		-- อัตราดาเมจตอนนี้ — ⚠️ ระหว่างเดินทัพไม่มีใครตีใคร · สู้ศัตรูกลางเลน (นอกระยะป้อม) · ป้อมยิงเฉพาะตอนเดินถึงกำแพงแล้ว
		updateLine()
		local front = meta.line[1]
		local marching = meta.marchRemaining > 0
		local fightingEnemies = front ~= nil and not marching and meta.lineAt == "middle" and enemiesRemain(enemy)
		local atWall = front ~= nil and not marching and meta.lineAt == "wall"
		local hitWall = atWall and progress.wallHpRemaining > 0
		local ourDps = if front and (fightingEnemies or hitWall) then front.dps else 0
		local enemyDps = if fightingEnemies then enemyUnitDps(stats, enemy.frontIndex) else 0
		local turretActive = turretDps > 0 and atWall

		-- เร่งทีละรอบวนเต็ม: ศัตรูตัวหน้าสุดเป็นตัวแรกของรอบ (เลือดเต็ม) · ตัวหน้าสุดเรารอดครบทุกรอบ · ยังไม่หมดเวลา
		-- (ผู้เล่นแรงมาก ฆ่าหลายพันตัวต่อ tick) — ผลเท่าวนทีละตัวเป๊ะ เพราะตัวหน้าสุดเราไม่ตายระหว่างนั้นและป้อมไม่ยิงช่วงนี้
		if fightingEnemies and ourDps > 0 and front then
			local position = (enemy.frontIndex - 1) % cycleLength
			if position == 0 and enemy.frontHp >= stats.smallHp * (1 - EPSILON) then
				local cycleTime = cycleHp / ourDps
				local hitPerCycle = cycleHitWork / ourDps
				local cyclesLeft = math.floor((enemy.total - enemy.frontIndex + 1) / cycleLength)
				local byTime = math.floor((seconds - t) / cycleTime)
				local bySurvival = if hitPerCycle > 0 then math.floor(front.hp / hitPerCycle - EPSILON) else math.huge
				local cycles = math.min(cyclesLeft, byTime, bySurvival)
				if cycles >= 1 then
					t += cycles * cycleTime
					front.hp -= cycles * hitPerCycle
					enemy.frontIndex += cycles * cycleLength
					enemy.frontHp = if enemy.frontIndex <= enemy.total then enemyUnitHp(stats, enemy.frontIndex) else 0
					result.enemiesKilled += cycles * cycleLength
					local made = bookEnemyDamage(cycles * cycleHp)
					result.damageDealt += made
					if made > 0 then
						meta.deathsSinceProgress = 0
					end
					enemy.knownDefenders = progress.defendersRemaining
					if progress.defendersRemaining <= 0 and progress.wallHpRemaining <= 0 then
						result.stageCleared = true
						break
					end
					continue
				end
			end
		end

		-- เหตุการณ์ถัดไป
		local dt = seconds - t
		if marching then
			dt = math.min(dt, meta.marchRemaining)
		end
		if turretActive then
			dt = math.min(dt, math.max(0, shotPeriod - meta.turretClock))
		end
		if front and enemyDps > 0 then
			dt = math.min(dt, front.hp / enemyDps)
		end
		-- ⚠️ เหตุการณ์ "ตายพอดี" ตัดสินหลังรู้ dt สุดท้ายแล้วเท่านั้น (ตัวหน้าสุดเราตายก่อน = ศัตรูยังไม่ตายรอบนี้)
		local enemyDeath = false
		if fightingEnemies and ourDps > 0 then
			local killTime = enemy.frontHp / ourDps
			if killTime <= dt then
				dt = killTime
				enemyDeath = true
			end
		end
		local wallEvent = false
		if hitWall and ourDps > 0 then
			local wallTime = progress.wallHpRemaining / ourDps
			if wallTime <= dt then
				dt = wallTime
				wallEvent = true
			end
		end
		dt = math.max(0, dt)

		-- เดินเวลา
		t += dt
		if turretActive then
			meta.turretClock += dt
		else
			meta.turretClock = 0 -- นัดแรกมาหลังเดินถึงกำแพงครบรอบยิง
		end
		if marching then
			meta.marchRemaining = math.max(0, meta.marchRemaining - dt)
			if meta.marchRemaining <= EPSILON then
				meta.marchRemaining = 0
				if meta.lineAt == "middle" then
					enemy.atMiddle = true
				end
			end
		end

		local progressMade = 0
		if fightingEnemies and ourDps > 0 then
			local amount = if enemyDeath then enemy.frontHp else ourDps * dt
			local dealt, killed = damageEnemyFront(enemy, stats, amount)
			result.enemiesKilled += killed
			progressMade += bookEnemyDamage(dealt)
		end
		if front and enemyDps > 0 then
			front.hp -= enemyDps * dt
		end
		if hitWall and ourDps > 0 and dt > 0 then
			local amount = ourDps * dt
			if wallEvent or progress.wallHpRemaining - amount <= wallTotal * EPSILON then
				amount = progress.wallHpRemaining
			end
			local _, toWall, coins = CombatService.applyDamageToStage(data, meta, stage, amount)
			progressMade += toWall
			result.coinsEarned += coins
		end
		result.damageDealt += progressMade
		if progressMade > 0 then
			meta.deathsSinceProgress = 0
		end

		-- ป้อมยิงตัวหน้าสุด (นัดเดียวต่อเป้า ส่วนเกินทิ้ง) — เฉพาะตอนแถวเราเดินถึงกำแพงแล้ว
		if turretActive and meta.turretClock >= shotPeriod - EPSILON then
			meta.turretClock = math.max(0, meta.turretClock - shotPeriod)
			local target = meta.line[1]
			if target then
				target.hp -= shotDamage
				result.turretShots += 1
				meta.lastTurretTarget = 1
			end
		end

		-- ตัวหน้าสุดของเราตาย → ออกจากแถว ทั้งแถวขยับขึ้น (ลูกหักกอง · แม่ตายถาวร) · มีแค่ตัวหน้าสุดที่โดนตี
		local head = meta.line[1]
		if head and head.hp <= head.maxHp * EPSILON then
			table.remove(meta.line, 1)
			killOurUnit(data, head, result)
			meta.deathsSinceProgress += 1
		end
		enemy.knownDefenders = progress.defendersRemaining

		if progress.defendersRemaining <= 0 and progress.wallHpRemaining <= 0 then
			result.stageCleared = true
			break
		end

		-- auto-pause: ตายติดกันครบโดยที่ HP ฝั่งตรงข้ามไม่ลดเลย → หยุดปล่อย (ผู้เล่นต้องกดเปิดเอง)
		if meta.deathsSinceProgress >= combat.AUTO_PAUSE_AFTER_DEATHS then
			data.summonEnabled = false
			data.combatAutoPaused = true
			meta.deathsSinceProgress = 0
			CombatService.clearField(meta)
			result.autoPaused = true
			break
		end

		deploy()
	end
end

-- ⚠️ ไม่มี offline catch-up: ฟังก์ชันนี้รับ elapsedSeconds ตรง ๆ ไม่อ่าน os.time()/os.clock() เอง
-- ปิดเกม/ออกเกม = ไม่มีใครเรียกฟังก์ชันนี้ = ไม่มีอะไรคืบหน้า (ตรงข้ามกับ ProductionService ที่มี
-- offline settlement) — แค่ไม่เรียกก็พอ ไม่ต้องมี flag พิเศษกันไว้
function CombatService.tick(data: Data, meta: CombatMeta, elapsedSeconds: number): TickResult
	local result = emptyResult()
	meta.lastTurretShots = 0
	if not data.summonEnabled then
		-- ปิดอัญเชิญ (เอง / auto-pause / ล็อกบอส) = ทหารที่รอดกลับกอง · ศัตรูบาดเจ็บค้างไว้
		CombatService.clearField(meta)
		return result
	end
	if elapsedSeconds <= 0 then
		return result
	end

	local stage = CombatService.getActiveStage(data)
	if not stage then
		CombatService.clearField(meta)
		return result -- ผ่านครบทุกด่านแล้ว ไม่มีอะไรให้ตีต่อ
	end

	CombatService.ensureStageStarted(data, stage)

	-- ด่านที่ไม่มีอะไรให้ตี (ด่าน 1) "พัง" ทันทีที่เปิดอัญเชิญ ไม่ต้องใช้ทหาร (ไม่มีกำแพง → ไม่ติดล็อกบอส · ไม่มีรางวัล)
	if Config.getStageTotalHp(stage) > 0 then
		runBattle(data, meta, stage, math.min(elapsedSeconds, Config.Balance.Combat.MAX_TICK_SECONDS), result)
	else
		result.stageCleared = true
	end
	meta.lastTurretShots = result.turretShots

	if result.stageCleared then
		-- ⚠️ อัปเดตทันทีในตาที่พังใหม่ ไม่ต้องรอ tick ถัดไป — ระบบเงิน/เพดานอัปเกรดที่ผูกกับ
		-- wallProgress (เช่น Config.getCoinsPerMinute/getMaxDamageLevel) จะได้ใช้ค่าล่าสุดทันที
		CombatService.recomputeWallProgress(data)
		-- ⚠️ แม่ทั้ง roster ตายถาวรพร้อมกันทันทีที่ด่านที่กำลังตีพัง (กติกาเดิม ห้ามเปลี่ยน)
		result.mothersLost = CombatService.killRoster(data, stage)
		-- ⚠️ Phase 4A: รางวัลผูกกับจังหวะนี้ (เพิ่งพัง) ไม่ใช่กับสถานะ "พังอยู่" — ดู claimStageClearBonus
		result.bonusEggs = CombatService.claimStageClearBonus(data, stage)
		result.clearedStage = stage
		-- ลูกที่รอดกลับกอง (ไม่เคยถูกหัก) · ด่านถัดไปเริ่มจากสนามว่าง + ศัตรูชุดใหม่
		CombatService.clearField(meta)
		meta.enemy = nil
		meta.turretClock = 0
	end

	return result
end

-- ตานี้ต้องแจ้ง popup "ผ่านด่าน" ไหม (Phase 4B) — ด่านเพิ่งพัง **และ** มีอย่างน้อยหนึ่งอย่างให้บอก:
-- ไข่ฟรีที่ควรได้ (ครั้งแรกที่ด่านพัง) หรือแม่ใน roster ที่ตาย
-- ⚠️ ไม่มีทั้งคู่ (ด่าน 1 · พังซ้ำหลังได้รางวัลแล้วโดยไม่มีแม่ในสนาม) = เงียบ ไม่ขึ้น popup ว่าง ๆ
-- ⚠️ อ่าน mothersLost จาก TickResult ที่ killRoster นับไว้**ก่อน**ล้าง roster แล้ว — ห้ามนับ #battleRoster ตรงนี้
function CombatService.shouldNotifyStageCleared(result: TickResult): boolean
	return result.clearedStage ~= nil and (result.bonusEggs > 0 or result.mothersLost > 0)
end

--------------------------------------------------------------------------------
-- RemoteEvent: SetReleaseOrderRequest / SetSummonEnabledRequest
--------------------------------------------------------------------------------
-- ⚠️ ฟังก์ชัน handle* รับ `data`/`meta` ตรง ๆ (ไม่รับ Player) ตั้งใจให้เทสต์เรียกตรง ๆ ได้
-- โดยไม่ต้องมี Player จริง — ตัวที่ผูกกับ Player อยู่ใน CombatService.start() เท่านั้น

local function isValidStackKey(key: unknown): boolean
	if type(key) ~= "string" then
		return false
	end

	local charId, motherWeight, statuses = Config.parseStackKey(key)
	if not charId or not motherWeight then
		return false
	end
	if not Config.getCharacter(charId) then
		return false
	end
	if motherWeight % 1 ~= 0 or motherWeight <= 0 then
		return false
	end

	-- ⚠️ ต้อง round-trip กลับมาเป็น string เดิมเป๊ะ — กันคั่นแปลก/สถานะเรียงผิด/สถานะซ้ำ
	-- ที่ "หน้าตาคล้าย" stack key แต่ไม่ได้มาจาก Config.makeStackKey() จริง ๆ
	return Config.makeStackKey(charId, motherWeight, statuses) == key
end

-- uid แม่รูปแบบถูกต้อง ("<UserId>-<เลขนับ>") — ไม่ตรวจว่าเป็นของใคร (รอบวนกรองเหลือแม่ใน roster ของตัวเองเอง)
local function isValidMotherUid(value: unknown): boolean
	if type(value) ~= "string" or #value > 40 then
		return false
	end
	local userId, counter = Config.parseUid(value)
	-- round-trip กลับเป็น string เดิมเป๊ะ (กันเลขทศนิยม/ช่องว่าง/เลขนำหน้า 0) · ⚠️ ห้ามเรียก Config.makeUid นอก PlayerData
	return userId ~= nil
		and counter ~= nil
		and userId % 1 == 0
		and counter % 1 == 0
		and string.format("%d%s%d", userId, Config.Uid.SEPARATOR, counter) == value
end

-- ตรวจลำดับรอบวนทั้งชุด (5E-1b · SetReleaseOrderRequest signature เดิม) — สมาชิกแต่ละตัวเป็น stack key หรือ uid แม่ก็ได้
-- (ลำดับรวมแม่ + กองลูก · client เก่าที่ส่ง stack key ล้วนยังใช้ได้) · ไม่ซ้ำ · กองไม่เกิน MAX_CHILD_STACKS · แม่ไม่เกิน MAX_BATTLE_MOTHERS
-- คืน (stack key เรียงตามลำดับ, ลำดับรวมทั้งหมด) · ผิดจุดเดียว = (nil, nil) ผู้เรียกปฏิเสธทั้งชุดเงียบ ๆ ไม่ apply บางส่วน
function CombatService.validateReleaseOrder(rawOrder: unknown): ({ string }?, { string }?)
	if type(rawOrder) ~= "table" then
		return nil, nil
	end
	local order = rawOrder :: { [number]: unknown }

	local length = #order
	if length > Config.Inventory.MAX_CHILD_STACKS + Config.Balance.Combat.MAX_BATTLE_MOTHERS then
		return nil, nil
	end

	local keys: { string } = {}
	local mixed: { string } = table.create(length)
	local seen: { [string]: boolean } = {}
	local mothers = 0

	for index = 1, length do
		local item = order[index]
		if isValidStackKey(item) then
			table.insert(keys, item :: string)
		elseif isValidMotherUid(item) then
			mothers += 1
		else
			return nil, nil
		end
		local itemString = item :: string
		if seen[itemString] then
			return nil, nil
		end
		seen[itemString] = true
		mixed[index] = itemString
	end
	if #keys > Config.Inventory.MAX_CHILD_STACKS or mothers > Config.Balance.Combat.MAX_BATTLE_MOTHERS then
		return nil, nil
	end

	return keys, mixed
end

-- ⚠️ 5E-1b: data.releaseOrder (เซฟ) = กองลูกที่ติ๊กเรียงตามลำดับ **ความหมายเดิม** · ลำดับรวมแม่ + กองลูกเก็บใน meta (memory)
-- ตั้งลำดับใหม่ = เริ่มรอบวนจากรายการแรก (ตัวในแถวที่มีอยู่แล้วอยู่ต่อ ไม่ถูกดึงกลับ)
function CombatService.handleSetReleaseOrder(data: Data, rawOrder: unknown, meta: CombatMeta?): boolean
	local keys, mixed = CombatService.validateReleaseOrder(rawOrder)
	if not keys then
		return false
	end
	data.releaseOrder = keys
	if meta then
		meta.cycleOrder = mixed
		meta.cursorId = nil
		meta.cursorIndex = 0
	end
	return true
end

-- Phase 5A: `bossLocked` = ติดล็อกอัญเชิญเพราะบอส → ขอ **เปิด** ถูกปฏิเสธ (ไม่แตะธง auto-pause ด้วย เพราะไม่ได้เปิดจริง)
-- ขอ **ปิด** ยังได้เสมอ (ปิดซ้ำไม่เสียหาย)
function CombatService.handleSetSummonEnabled(data: Data, meta: CombatMeta, rawEnabled: unknown, bossLocked: boolean?): boolean
	if type(rawEnabled) ~= "boolean" then
		return false
	end
	if rawEnabled and bossLocked then
		return false
	end
	data.summonEnabled = rawEnabled
	if rawEnabled then
		-- ผู้เล่นกดเปิดเอง = รับทราบแจ้งเตือน auto-pause แล้ว เริ่มนับใหม่
		data.combatAutoPaused = false
		meta.deathsSinceProgress = 0
	else
		-- ปิดอัญเชิญ = ทหารที่รอดกลับกองทันที (ไม่รอ tick) · ศัตรูบาดเจ็บค้างไว้
		CombatService.clearField(meta)
	end
	return true
end

--------------------------------------------------------------------------------
-- ฟิลด์ sync — merge เข้า FarmStateSync payload ของ EggService
--------------------------------------------------------------------------------
-- ⚠️ 3A ส่งแค่ข้อมูลดิบ ไม่ทำ client แสดงผล (เป็นงาน 3B) — % ความคืบหน้าคำนวณฝั่ง client
-- เองจาก remaining/total ที่ส่งมาให้ตรงนี้

type StageProgressView = {
	started: boolean,
	defendersRemaining: number?,
	defendersTotal: number?,
	wallHpRemaining: number?,
	wallHpTotal: number?,
	cleared: boolean?,
}

-- 5E-1b: สนามรบสำหรับภาพชั่วคราว + HUD — สองแถว (pos 1 = หน้าสุด) ฝั่งละไม่เกิน LINE_LENGTH ตัว
-- ⚠️ client แค่แสดง · ตัวเลขทั้งหมดมาจากสถานะจริงของ server
local function buildBattleView(data: Data, meta: CombatMeta?, stage: number?)
	local view = {
		stage = stage,
		phase = "idle", -- "enemies" | "wall" | "idle"
		available = 0, -- ทหารพร้อมปล่อย (ลูกในกองที่ติ๊ก + แม่ใน roster ที่ยังไม่อยู่ในแถว)
		lineLength = Config.Balance.Combat.LINE_LENGTH,
		our = {}, -- { pos, id, kind, charId, class, hp, maxHp }
		enemies = {}, -- { pos, id, kind, hp, maxHp } — ตัวหน้าสุดถึง LINE_LENGTH ตัว (ที่เหลือยังไม่แสดง)
		bigLeft = 0,
		smallLeft = 0,
		bigTotal = 0,
		smallTotal = 0,
		turretActive = false,
		turretFiring = false,
		turretShots = 0,
		turretTarget = nil :: number?,
		-- 5E-1 เดินทัพ: แนวรบ "middle" (กึ่งกลางเลน · Config.getBattleMeetX) / "wall" / nil = สนามว่าง
		line = nil :: string?,
		marchFrom = nil :: string?,
		marchRemaining = 0,
		marchDuration = 0,
		enemiesAtMiddle = false,
	}
	if not stage then
		return view
	end
	local stats = Config.getStageEnemyStats(stage)
	view.bigTotal = stats.bigCount
	view.smallTotal = stats.smallCount
	-- ป้อมมีอยู่ในด่านนี้ (วาดกล่องบนกำแพง) · ยิงจริงเฉพาะตอนกองทัพเดินถึงกำแพงแล้ว (turretFiring)
	view.turretActive = turretEnabled and Config.getStageTurretDps(stage) > 0
	local progress = data.stageProgress[stage]
	if type(progress) == "table" then
		view.phase = if progress.defendersRemaining > 0
			then "enemies"
			elseif progress.wallHpRemaining > 0 then "wall"
			else "idle"
	else
		view.phase = if stats.totalHp > 0 then "enemies" else "idle"
		view.bigLeft, view.smallLeft = stats.bigCount, stats.smallCount
	end
	local enemy = if meta then meta.enemy else nil
	if enemy and enemy.stage == stage then
		view.bigLeft, view.smallLeft = CombatService.countEnemies(enemy)
	elseif type(progress) == "table" and progress.defendersRemaining > 0 then
		-- ยังไม่เคยสู้ในเซสชันนี้ — นับจากแถวที่จะสร้างจาก HP รวม (ไม่เก็บไว้ ไม่แตะ meta)
		view.bigLeft, view.smallLeft = CombatService.countEnemies(CombatService.buildEnemyState(stage, progress.defendersRemaining))
	end
	if not meta then
		return view
	end
	view.available = CombatService.countAvailable(data, meta)
	view.line = meta.lineAt
	view.marchFrom = meta.marchFrom
	view.marchRemaining = meta.marchRemaining
	view.marchDuration = meta.marchDuration
	view.enemiesAtMiddle = enemy ~= nil and enemy.stage == stage and enemy.atMiddle
	view.turretFiring = view.turretActive and meta.lineAt == "wall" and meta.marchRemaining <= 0
	view.turretShots = meta.lastTurretShots
	view.turretTarget = meta.lastTurretTarget
	for pos, unit in meta.line do
		local character = Config.getCharacter(unit.charId)
		table.insert(view.our, {
			pos = pos,
			id = unit.id,
			kind = unit.kind,
			charId = unit.charId,
			class = if character then character.class else "?",
			hp = unit.hp,
			maxHp = unit.maxHp,
		})
	end
	if enemy and enemy.stage == stage then
		for pos = 1, Config.Balance.Combat.LINE_LENGTH do
			local index = enemy.frontIndex + pos - 1
			if index > enemy.total then
				break
			end
			local maxHp = enemyUnitHp(stats, index)
			table.insert(view.enemies, {
				pos = pos,
				id = index, -- ตัวที่เท่าไรของด่าน (ตายเรียงลำดับ → ใช้เป็นเลขประจำตัวได้)
				kind = Config.getEnemyKindAt(index),
				hp = if pos == 1 then enemy.frontHp else maxHp,
				maxHp = maxHp,
			})
		end
	end
	return view
end

-- `bossLocked` (Phase 5A) มาจาก BossService ผ่านผู้เรียก (EggService.sync) — ไม่ส่ง = ไม่ล็อก
-- `meta` (5E-1) = สนามรบของผู้เล่นคนนี้ (CombatService.getMeta) — ไม่ส่ง = สนามว่าง
function CombatService.buildSyncFields(data: Data, bossLocked: boolean?, meta: CombatMeta?)
	local stageProgress: { StageProgressView } = table.create(Config.Balance.Stage.COUNT)
	for stage = 1, Config.Balance.Stage.COUNT do
		local progress = data.stageProgress[stage]
		if type(progress) == "table" then
			stageProgress[stage] = {
				started = true,
				defendersRemaining = progress.defendersRemaining,
				defendersTotal = Config.getStageDefenderHp(stage),
				wallHpRemaining = progress.wallHpRemaining,
				wallHpTotal = Config.getStageWallHp(stage),
				cleared = progress.defendersRemaining <= 0 and progress.wallHpRemaining <= 0,
			}
		else
			stageProgress[stage] = { started = false }
		end
	end

	-- แม่ในสนามรบ — ส่งแค่ที่ UI ต้องใช้ (เพดานอ่านจาก Config.Balance.Combat.MAX_BATTLE_MOTHERS ฝั่ง client เอง)
	-- UI-3: + ชื่อ/คลาส/น้ำหนักพร้อมโชว์ ให้การ์ด "ในสนาม" ของหน้าต่างอัญเชิญ (แบบเดียวกับการ์ดกระเป๋า)
	local battleRoster = table.create(#data.battleRoster)
	for _, mother in data.battleRoster do
		local character = Config.getCharacter(mother.charId)
		table.insert(battleRoster, {
			uid = mother.uid,
			charId = mother.charId,
			charName = if character then character.name else mother.charId,
			class = if character then character.class else "?",
			weight = mother.weight,
			weightText = Config.formatWeight(mother.weight),
			statuses = mother.statuses,
		})
	end

	return {
		activeStage = CombatService.getActiveStage(data),
		stageProgress = stageProgress,
		summonEnabled = data.summonEnabled,
		combatAutoPaused = data.combatAutoPaused,
		releaseOrder = data.releaseOrder,
		battleRoster = battleRoster,
		-- UI-3: เหตุผลที่ส่งแม่ไปรบไม่ได้ตอนนี้ (nil = ส่งได้) — ข้อความเดียวกับที่ server ใช้ปฏิเสธจริง
		-- client ใช้โชว์ในแท็บแม่ + ปิดการติ๊ก · ⚠️ แค่ช่วยแสดงผล server ยังตรวจซ้ำทุกคำขอ
		sendStageBlockReason = CombatService.getSendStageBlockReason(data, bossLocked),
		-- Phase 5A: เปิดอัญเชิญไม่ได้เพราะอะไร (nil = ได้) — client ปิดปุ่ม "ส่งไปรบ" + โชว์ข้อความนี้
		-- ⚠️ แค่ช่วยแสดงผล server ปฏิเสธคำขอเปิดเองอยู่แล้ว (handleSetSummonEnabled)
		summonBlockReason = CombatService.getSummonBlockReason(bossLocked),
		bossLocked = bossLocked == true,
		-- 5E-1b: สองแถว + เดินทัพ + ป้อม (ภาพชั่วคราว/HUD)
		battle = buildBattleView(data, meta, CombatService.getActiveStage(data)),
		-- 5E-1b: รอบวนที่ใช้ปล่อยจริง (แม่ + กองลูก) — หน้าต่างอัญเชิญใช้เลขลำดับร่วมสองแท็บ + ตัวอย่างลำดับวน
		releaseCycle = CombatService.getReleaseCycle(data, meta),
	}
end

--------------------------------------------------------------------------------
-- debug (Studio) — เรียกผ่าน EggService.debugBattleStatus / debugTurret
--------------------------------------------------------------------------------

-- สองแถว (ลำดับ ชนิด เลือด) + รอบวน (ตำแหน่งถัดไป) + คิวที่เหลือ เป็นข้อความหลายบรรทัด
function CombatService.describeBattle(data: Data, meta: CombatMeta?): string
	local stage = CombatService.getActiveStage(data)
	local lines = {}
	table.insert(
		lines,
		`ด่าน {stage or "-"} · อัญเชิญ {if data.summonEnabled then "เปิด" else "ปิด"}`
			.. ` · ป้อม {if turretEnabled then "เปิด" else "ปิด (debug)"}`
	)
	if not stage then
		return table.concat(lines, "\n")
	end
	local progress = data.stageProgress[stage]
	if type(progress) == "table" then
		table.insert(
			lines,
			string.format(
				"HP ทหารฝ่ายรับ %.6g/%.6g · HP กำแพง %.6g/%.6g",
				progress.defendersRemaining,
				Config.getStageDefenderHp(stage),
				progress.wallHpRemaining,
				Config.getStageWallHp(stage)
			)
		)
	end
	if meta then
		local lineText = if meta.lineAt == nil
			then "แถวว่าง"
			elseif meta.marchRemaining > 0 then string.format(
				"เดินทัพ %s → %s เหลือ %.1f/%.1f วิ",
				meta.marchFrom or "?",
				meta.lineAt,
				meta.marchRemaining,
				meta.marchDuration
			)
			elseif meta.lineAt == "middle" then "สู้ศัตรูกึ่งกลางเลน (นอกระยะป้อม)"
			else "ถึงกำแพงแล้ว (ป้อมยิง)"
		table.insert(lines, `แนวรบ: {lineText}`)
	end

	-- แถวเรา
	local ourParts = {}
	if meta then
		for pos, unit in meta.line do
			table.insert(
				ourParts,
				string.format(
					"%d.%s %s %.4g/%.4g",
					pos,
					if unit.kind == "mother" then "แม่" else "ลูก",
					unit.charId,
					unit.hp,
					unit.maxHp
				)
			)
		end
	end
	table.insert(
		lines,
		`แถวเรา ({#ourParts}/{Config.Balance.Combat.LINE_LENGTH} · หน้าสุดก่อน): {if #ourParts > 0 then table.concat(ourParts, " · ") else "-"}`
	)
	if meta and meta.line[1] then
		table.insert(lines, string.format("  ตัวหน้าสุดตี %.4g/วิ", meta.line[1].dps))
	end

	-- แถวศัตรู
	local enemy = if meta and meta.enemy and meta.enemy.stage == stage then meta.enemy else nil
	if enemy then
		local stats = Config.getStageEnemyStats(stage)
		local foeParts = {}
		for pos = 1, Config.Balance.Combat.LINE_LENGTH do
			local index = enemy.frontIndex + pos - 1
			if index > enemy.total then
				break
			end
			local maxHp = enemyUnitHp(stats, index)
			local hp = if pos == 1 then enemy.frontHp else maxHp
			table.insert(
				foeParts,
				string.format("%d.%s %.4g/%.4g", pos, if Config.getEnemyKindAt(index) == "big" then "ใหญ่" else "เล็ก", hp, maxHp)
			)
		end
		table.insert(
			lines,
			`แถวศัตรู (หน้าสุด = ตัวที่ {enemy.frontIndex}/{enemy.total}): {if #foeParts > 0 then table.concat(foeParts, " · ") else "-"}`
		)
		if enemiesRemain(enemy) then
			local big, small = CombatService.countEnemies(enemy)
			table.insert(
				lines,
				string.format("  ตัวหน้าสุดตี %.4g/วิ · เหลือ ใหญ่ %d · เล็ก %d", enemyUnitDps(stats, enemy.frontIndex), big, small)
			)
		end
	else
		table.insert(lines, "แถวศัตรู: (ยังไม่ได้สร้าง — สร้างตอน tick แรกที่อัญเชิญ)")
	end

	-- รอบวน
	local cycle = CombatService.getReleaseCycle(data, meta)
	local reserved = CombatService.getReservedChildren(meta)
	local nextIndex = if meta then CombatService.getCycleStartIndex(cycle, meta) else 1
	local cycleParts = {}
	for index, item in cycle do
		local label
		if item.kind == "child" then
			local count = data.children[item.id] or 0
			label = `ลูก {item.id} เหลือ {math.max(0, math.floor(count) - (reserved[item.id] or 0))}`
		else
			local inLine = meta ~= nil and motherInLine(meta, item.id)
			label = `แม่ {item.id}{if inLine then " (อยู่ในแถว)" else ""}`
		end
		table.insert(cycleParts, `{if index == nextIndex then "▶" else ""}{index}.{label}`)
	end
	table.insert(lines, `รอบวน (▶ = ตัวถัดไป): {if #cycleParts > 0 then table.concat(cycleParts, " · ") else "-"}`)
	if meta then
		table.insert(
			lines,
			`พร้อมปล่อย {CombatService.countAvailable(data, meta)}`
				.. ` · ตายติดกันไม่คืบหน้า {meta.deathsSinceProgress}/{Config.Balance.Combat.AUTO_PAUSE_AFTER_DEATHS}`
		)
	end
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- ต่อสาย Roblox จริง (RemoteEvent + loop) — เรียกจาก Main.server.lua เท่านั้น
--------------------------------------------------------------------------------
-- ⚠️ require ของจริงทั้งหมดอยู่ *ในตัวฟังก์ชัน* ไม่ใช่ระดับโมดูล เหมือน ProductionService.start()
-- เพื่อให้ require ไฟล์นี้จาก tests/run.luau (นอก Roblox) ได้โดยไม่พังตั้งแต่โหลด

-- `onStageCleared(player, stage, eggCount, deathCount)` = EggService.grantStageClearBonus (Main.server.lua ส่งเข้ามา)
-- ⚠️ inject แทน require EggService ตรง ๆ กัน circular require (EggService require ไฟล์นี้อยู่แล้ว)
-- แบบเดียวกับ ProductionService.start(EggService.sync)
-- Phase 5A: `bossGate` = BossService.getGate() (inject กัน CombatService ผูกกับ BossService ตรง ๆ)
--   ใช้ตัดสินล็อกหลัง tick · ปฏิเสธเปิดอัญเชิญตอนติดล็อก
-- 5B-2 (ผู้ใช้ยืนยัน): ล็อก**ผูกห้อง** — พังกำแพงด่าน N ขณะบอสห้อง N ยังอยู่ → ล็อกจนบอสห้อง N ตาย (ห้องอื่นไม่เกี่ยว)
type BossGate = {
	isBossAlive: (room: number) -> boolean,
	isUserLocked: (userId: number) -> boolean,
	lockUser: (userId: number, room: number) -> boolean,
}

function CombatService.start(onStageCleared: (Player, number, number, number) -> (), bossGate: BossGate)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	local DataService = require(ServerScriptService.DataService)

	local setReleaseOrderRequest = Remotes.waitFor(Config.RemoteNames.SET_RELEASE_ORDER_REQUEST)
	local actionResult = Remotes.waitFor(Config.RemoteNames.ACTION_RESULT)
	local setSummonEnabledRequest = Remotes.waitFor(Config.RemoteNames.SET_SUMMON_ENABLED_REQUEST)

	setReleaseOrderRequest.OnServerEvent:Connect(function(player: Player, rawOrder: unknown)
		local data = DataService.getCached(player.UserId)
		if data then
			CombatService.handleSetReleaseOrder(data, rawOrder, CombatService.getOrCreateMeta(player.UserId))
		end
	end)

	setSummonEnabledRequest.OnServerEvent:Connect(function(player: Player, rawEnabled: unknown)
		local data = DataService.getCached(player.UserId)
		if data then
			CombatService.handleSetSummonEnabled(
				data,
				CombatService.getOrCreateMeta(player.UserId),
				rawEnabled,
				bossGate.isUserLocked(player.UserId)
			)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CombatService.clearMeta(player.UserId)
	end)

	-- ⚠️ ลูปเดียวคุมทั้งการปล่อย+ตี ความละเอียด = Config.World.SYNC_INTERVAL (ค่าเดียวกับ
	-- ลูป sync ของ EggService) ใช้ os.clock() วัด elapsed จริงระหว่างรอบ กัน drift จาก
	-- task.wait() ที่ไม่เป๊ะ 1 วินาทีเป๊ะทุกรอบ (สนามคิดเป็นเวลาต่อเนื่อง ไม่มีเศษหาย)
	task.spawn(function()
		while true do
			task.wait(Config.World.SYNC_INTERVAL)

			for _, player in Players:GetPlayers() do
				local data = DataService.getCached(player.UserId)
				if data then
					local meta = CombatService.getOrCreateMeta(player.UserId)
					local nowClock = os.clock()
					local elapsed = if meta.lastTickClock
						then nowClock - meta.lastTickClock
						else Config.World.SYNC_INTERVAL
					meta.lastTickClock = nowClock
					-- ⚠️ ตาข่ายชั้นสอง: ติดล็อกอยู่แต่อัญเชิญยังเปิด (ไม่ควรเกิด — เปิดใหม่ถูกปฏิเสธ) = ปิดก่อน tick
					if data.summonEnabled and bossGate.isUserLocked(player.UserId) then
						CombatService.applyBossLock(data)
					end
					local result = CombatService.tick(data, meta, elapsed)
					-- 5E-1: แม่โดนฆ่ากลางสนาม (ตายถาวร) — บอกทันที ไม่รอผ่านด่าน
					if result.mothersFallen > 0 then
						actionResult:FireClient(player, false, Config.formatMotherFallenMessage(result.mothersFallen, #data.battleRoster))
					end
					local clearedStage = result.clearedStage
					-- Phase 5A: พังกำแพงด่านตัวเองเสร็จขณะบอสยังอยู่ → ล็อก + หยุดอัญเชิญ
					-- 5B-2: บอสที่ดูคือ **บอสห้องของด่านที่เพิ่งพัง** (ห้อง N หลังกำแพง N) · ปลดเมื่อบอสห้องนั้นตาย
					-- ⚠️ หลัง tick จบ = ผ่านด่าน/รางวัล 4A/แม่ตาย เกิดครบไปแล้วตามเดิม ล็อกแค่ห้ามปล่อยต่อ
					local bossAlive = clearedStage ~= nil and bossGate.isBossAlive(clearedStage)
					if clearedStage and CombatService.shouldBossLock(clearedStage, bossAlive) then
						bossGate.lockUser(player.UserId, clearedStage)
						CombatService.applyBossLock(data)
						CombatService.clearField(meta)
						print(
							`[CombatService] {player.Name} พังกำแพงด่าน {clearedStage} ขณะบอสห้อง {clearedStage} ยังอยู่`
								.. ` → ล็อกอัญเชิญจนกว่าบอสห้องนั้นตาย`
						)
					end
					if clearedStage and CombatService.shouldNotifyStageCleared(result) then
						-- ⚠️ pcall: แจกไข่พังเมื่อไหร่ต้องไม่ลากลูปรบของทั้งเซิร์ฟตายไปด้วย (ธงติดไปแล้ว — log ไว้ตามแก้)
						local bonusEggs, mothersLost = result.bonusEggs, result.mothersLost
						local ok, err = pcall(function(): string?
							onStageCleared(player, clearedStage, bonusEggs, mothersLost)
							return nil
						end)
						if not ok then
							warn(`[CombatService] แจกรางวัลผ่านด่าน {result.clearedStage} ให้ {player.Name} ไม่สำเร็จ: {err}`)
						end
					end
				end
			end
		end
	end)
end

return CombatService
