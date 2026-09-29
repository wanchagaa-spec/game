--!strict
-- egg-army-game :: เครื่องยนต์คำนวณรบฝั่ง server
--
-- ══ 5E-1 รบแบบชุด (ผู้ใช้ยืนยัน · docs/data-schema.md §7.13) ══ แทนระบบ "ปล่อยต่อเนื่องแล้วตีครั้งเดียวหาย" เดิม
-- สนามมี 6 ช่องต่อฝ่าย (Config.Balance.Combat.FIELD_SLOTS) · ช่อง 1 = หน้าสุด · ช่อง MOTHER_SLOT = หลังสุด (แม่ยืน)
--   ฝั่งเรา: แม่ 1 (ลำดับ battleRoster) + ลูก 5 (ลำดับ releaseOrder) · ตายแล้วตัวถัดไปลงช่องเดิม
--     แม่หมด = ลูก 6 · ลูกหมด = แม่หลายตัว · เลือด = พลังฐาน · ดาเมจ/วิ = พลังเต็ม × อัตราปล่อย ÷ 6
--   ฝั่งศัตรู: ใหญ่ 1 (ช่อง 1) + เล็ก 5 · ตายแล้วตัวชนิดเดียวกันลงช่องเดิมจนหมดจำนวนของด่าน
--   ทหารเราตีศัตรูช่องเดียวกัน (ไม่มี = ตัวหน้าสุด) · ศัตรูทั้งหมดรุมทหารเราตัวหน้าสุด · ป้อมยิงตัวหน้าสุด
--   ศัตรูหมดแล้วค่อยตีกำแพงได้ · ป้อมยิงทั้งสองช่วง
-- รวมพล (ค3): สนามว่าง → รอพร้อมปล่อยครบ GATHER_SIZE ก่อน (ไม่มีทางถึง = ปล่อยเท่าที่มี) · ระหว่างสู้เติมทีละตัว
--
-- ⚠️ คำนวณแบบเหตุการณ์ต่อเนื่อง (เวลาจริง ไม่ใช่ขั้นเวลาตายตัว) — ผลแน่นอน ไม่สุ่ม · ไม่มีเศษเวลาหาย
-- ⚠️ ลูกบนสนาม **ยังนับอยู่ในกองของตัวเอง** (data.children) จนกว่าจะตาย → หักทีละตัวตอนตาย
--   ออกเกม/ปิดอัญเชิญ/กำแพงพัง/ติดล็อกบอส = ล้างสนาม ลูกที่รอด "กลับกอง" เองโดยไม่ต้องคืน (ไม่มีทางหายตอนเซฟ)
-- ⚠️ ศัตรูที่บาดเจ็บอยู่ใน meta (memory) · stageProgress ยังเก็บ HP รวมเหมือนเดิม (ไม่แตะ schema)
--   meta หาย (ออกเกม/เซิร์ฟใหม่/debug ตั้งค่า) = สร้างแถวศัตรูใหม่จาก HP รวม (buildEnemyState) · HP รวม + เงินตรงเป๊ะ
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

export type EnemyUnit = {
	kind: "big" | "small",
	hp: number,
	maxHp: number,
	dps: number,
}

export type EnemyState = {
	stage: number,
	field: { [number]: EnemyUnit }, -- ช่อง 1..FIELD_SLOTS (ช่องว่าง = nil)
	bigQueue: number, -- ตัวใหญ่ที่ยังไม่ลงสนาม
	smallQueue: number,
	knownDefenders: number, -- defendersRemaining ที่สถานะนี้ตรงอยู่ (ไม่ตรง = มีคนแก้จากข้างนอก → สร้างใหม่)
}

export type CombatMeta = {
	coinCarry: number, -- เศษเหรียญที่ยังไม่ถึง 1 เหรียญ สะสมข้ามรอบ tick
	lastTickClock: number?, -- os.clock() ของ tick ก่อนหน้า ใช้เฉพาะใน loop จริง (ไม่ใช้ในเทสต์)
	field: { [number]: OurUnit }, -- ทหารเราช่อง 1..FIELD_SLOTS (ช่องว่าง = nil)
	enemy: EnemyState?,
	turretClock: number, -- วินาทีที่สะสมตั้งแต่นัดล่าสุด
	deathsSinceProgress: number, -- auto-pause: ทหารเราตายติดกันโดยที่ HP ฝั่งตรงข้ามไม่ลดเลย
	gathering: boolean, -- กำลังรวมพล (สนามว่าง · รอให้ครบ GATHER_SIZE)
	lastTurretShots: number, -- นัดที่ป้อมยิงใน tick ล่าสุด (ภาพเท่านั้น)
	lastTurretTarget: number?, -- ช่องที่โดนนัดล่าสุด (ภาพเท่านั้น)
}

local combatMeta: { [number]: CombatMeta } = {}

-- ป้อมเปิด/ปิดทั้งเซิร์ฟ — debugTurret(false) ใช้ทดสอบใน Studio เท่านั้น (ค่าเริ่มต้นเปิดเสมอ)
local turretEnabled = true

function CombatService.newMeta(): CombatMeta
	return {
		coinCarry = 0,
		lastTickClock = nil,
		field = {},
		enemy = nil,
		turretClock = 0,
		deathsSinceProgress = 0,
		gathering = false,
		lastTurretShots = 0,
		lastTurretTarget = nil,
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
-- 5E-1 สนามรบ — ศัตรู
--------------------------------------------------------------------------------

local EPSILON = 1e-9
-- ⚠️ กันลูปเหตุการณ์ยาวผิดปกติ (ค่าจริงไม่กี่สิบเหตุการณ์ต่อวินาที) · ชนแล้ว tick นั้นหยุดตรงนั้น ไม่พัง
local MAX_EVENTS_PER_TICK = 20000

local function slotCount(): number
	return Config.Balance.Combat.FIELD_SLOTS
end

-- ช่องของศัตรูแต่ละชนิด: ใหญ่ = ช่อง 1..nb (หน้าสุด) · เล็ก = ช่องที่เหลือ
local function enemySlotRange(kind: "big" | "small"): (number, number)
	local nb = Config.Balance.Combat.ENEMY_BIG_PER_GROUP
	if kind == "big" then
		return 1, nb
	end
	return nb + 1, slotCount()
end

local function newEnemy(kind: "big" | "small", stats: any, hp: number?): EnemyUnit
	local maxHp = if kind == "big" then stats.bigHp else stats.smallHp
	return {
		kind = kind,
		hp = hp or maxHp,
		maxHp = maxHp,
		dps = if kind == "big" then stats.bigDps else stats.smallDps,
	}
end

-- สร้างแถวศัตรูจาก HP ทหารฝ่ายรับที่เหลือ (stageProgress) — ใช้ตอนเริ่มด่าน / meta หาย / มีคนแก้ค่าจากข้างนอก
-- แบ่ง HP ที่ตีไปแล้วระหว่างตัวใหญ่/เล็กตามสัดส่วนเลือดของแต่ละชนิด (แบบแผนปกติ: ทุกช่องโดนเท่ากัน → หมดพร้อมกัน)
-- แผลรวมไว้ที่ตัวแรกของแต่ละชนิด · เลือดรวมตรงกับที่เหลือเป๊ะ (เงินจ่ายตาม HP ที่ลด จึงไม่มีได้ซ้ำ/หาย)
function CombatService.buildEnemyState(stage: number, defendersRemaining: number): EnemyState
	local state: EnemyState = {
		stage = stage,
		field = {},
		bigQueue = 0,
		smallQueue = 0,
		knownDefenders = defendersRemaining,
	}
	local stats = Config.getStageEnemyStats(stage)
	if stats.totalHp <= 0 or defendersRemaining <= 0 then
		return state
	end
	local remaining = math.min(defendersRemaining, stats.totalHp)
	local bigTotal = stats.bigCount * stats.bigHp
	local bigRemaining = remaining * bigTotal / stats.totalHp
	local smallRemaining = remaining - bigRemaining

	local function place(kind: "big" | "small", kindRemaining: number, unitHp: number): number
		if kindRemaining <= unitHp * EPSILON then
			return 0
		end
		local full = math.floor(kindRemaining / unitHp + EPSILON)
		local partial = kindRemaining - full * unitHp
		if partial <= unitHp * EPSILON then
			partial = 0
		end
		local first, last = enemySlotRange(kind)
		local slot = first
		if partial > 0 then
			state.field[slot] = newEnemy(kind, stats, partial)
			slot += 1
		end
		while slot <= last and full > 0 do
			state.field[slot] = newEnemy(kind, stats)
			full -= 1
			slot += 1
		end
		return full
	end

	state.bigQueue = place("big", bigRemaining, stats.bigHp)
	state.smallQueue = place("small", smallRemaining, stats.smallHp)
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

local function frontEnemySlot(enemy: EnemyState): number?
	for slot = 1, slotCount() do
		if enemy.field[slot] then
			return slot
		end
	end
	return nil
end

local function enemyQueueOf(enemy: EnemyState, kind: "big" | "small"): number
	return if kind == "big" then enemy.bigQueue else enemy.smallQueue
end

local function setEnemyQueue(enemy: EnemyState, kind: "big" | "small", value: number)
	if kind == "big" then
		enemy.bigQueue = value
	else
		enemy.smallQueue = value
	end
end

-- ศัตรูที่เหลือทั้งหมด (บนสนาม + รอลง) — HUD "เหลือศัตรูกี่ตัว"
function CombatService.countEnemies(enemy: EnemyState?): (number, number)
	if not enemy then
		return 0, 0
	end
	local big, small = enemy.bigQueue, enemy.smallQueue
	for slot = 1, slotCount() do
		local unit = enemy.field[slot]
		if unit then
			if unit.kind == "big" then
				big += 1
			else
				small += 1
			end
		end
	end
	return big, small
end

--------------------------------------------------------------------------------
-- 5E-1 สนามรบ — ฝั่งเรา
--------------------------------------------------------------------------------

-- ลูกบนสนามต่อกอง (ยังนับอยู่ใน data.children) · client/sync ใช้หักออกจากจำนวนที่ "พร้อมปล่อย"
function CombatService.getReservedChildren(meta: CombatMeta?): { [string]: number }
	local reserved: { [string]: number } = {}
	if not meta then
		return reserved
	end
	for slot = 1, slotCount() do
		local unit = meta.field[slot]
		if unit and unit.kind == "child" and unit.key then
			reserved[unit.key] = (reserved[unit.key] or 0) + 1
		end
	end
	return reserved
end

local function motherOnField(meta: CombatMeta, uid: string): boolean
	for slot = 1, slotCount() do
		local unit = meta.field[slot]
		if unit and unit.kind == "mother" and unit.uid == uid then
			return true
		end
	end
	return false
end

-- จำนวนทหารที่พร้อมลงสนาม = ลูกในกองที่ติ๊ก (ไม่นับตัวที่อยู่บนสนามแล้ว) + แม่ใน roster ที่ยังไม่ลงสนาม
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
		if not motherOnField(meta, mother.uid) then
			total += 1
		end
	end
	return total
end

-- (ค3) คลังมีทางถึง GATHER_SIZE ไหม = มีกองที่ติ๊กไว้ที่แม่ในคอกยังผลิตเติมอยู่ (กองยังไม่เต็มเพดาน)
-- ไม่มี = ปล่อยเท่าที่มี (แม่ใน roster เพิ่มเองไม่ได้ ผู้เล่นต้องส่งเอง)
function CombatService.canReachGather(data: Data): boolean
	local producing: { [string]: boolean } = {}
	for _, mother in data.mothersInPen do
		producing[Config.makeStackKey(mother.charId, mother.weight, mother.statuses)] = true
	end
	local cap = Config.getStackCap()
	for _, key in data.releaseOrder do
		if producing[key] and (data.children[key] or 0) < cap then
			return true
		end
	end
	return false
end

local function makeChildUnit(data: Data, stage: number, key: string): OurUnit?
	local charId, motherWeight, statuses = Config.parseStackKey(key)
	if not charId or not motherWeight then
		return nil -- key เพี้ยน (ไม่น่าเกิด — ผ่าน makeStackKey เท่านั้น) → ข้าม
	end
	local weight = Config.getChildWeight(motherWeight, statuses)
	local hp = Config.getUnitHp(weight, charId, statuses)
	return {
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

local function nextChild(data: Data, meta: CombatMeta, stage: number): OurUnit?
	local reserved = CombatService.getReservedChildren(meta)
	for _, key in data.releaseOrder do
		local count = data.children[key]
		if count and math.floor(count) - (reserved[key] or 0) >= 1 then
			local unit = makeChildUnit(data, stage, key)
			if unit then
				return unit
			end
		end
	end
	return nil
end

local function nextMother(data: Data, meta: CombatMeta, stage: number): OurUnit?
	for _, mother in data.battleRoster do
		if not motherOnField(meta, mother.uid) then
			return makeMotherUnit(data, stage, mother)
		end
	end
	return nil
end

local function fieldIsEmpty(meta: CombatMeta): boolean
	for slot = 1, slotCount() do
		if meta.field[slot] then
			return false
		end
	end
	return true
end

-- เติมช่องว่างตามกติกา — คืนจำนวนที่ลงสนามรอบนี้
-- ช่องแม่ (หลังสุด) ← แม่ก่อน · ช่องอื่น ← ลูกก่อน · ลูกหมด → แม่ลงช่องอื่น · แม่หมด → ลูกลงช่องแม่
function CombatService.fillField(data: Data, meta: CombatMeta, stage: number): number
	local combat = Config.Balance.Combat
	if fieldIsEmpty(meta) then
		local available = CombatService.countAvailable(data, meta)
		if available <= 0 then
			meta.gathering = false
			return 0
		end
		if available < combat.GATHER_SIZE and CombatService.canReachGather(data) then
			meta.gathering = true
			return 0
		end
	end
	meta.gathering = false

	local slots, motherSlot = combat.FIELD_SLOTS, combat.MOTHER_SLOT
	local placed = 0
	local function put(slot: number, unit: OurUnit?): boolean
		if unit then
			meta.field[slot] = unit
			placed += 1
			return true
		end
		return false
	end

	if not meta.field[motherSlot] then
		put(motherSlot, nextMother(data, meta, stage))
	end
	for slot = 1, slots do
		if slot ~= motherSlot and not meta.field[slot] then
			put(slot, nextChild(data, meta, stage))
		end
	end
	for slot = 1, slots do
		if slot ~= motherSlot and not meta.field[slot] then
			put(slot, nextMother(data, meta, stage))
		end
	end
	if not meta.field[motherSlot] then
		put(motherSlot, nextChild(data, meta, stage))
	end
	return placed
end

-- ล้างสนามฝั่งเรา — ลูกที่รอดกลับกองเอง (ไม่เคยถูกหัก) · แม่ที่รอดยังอยู่ใน roster
-- ศัตรูไม่ถูกแตะ (บาดเจ็บค้างไว้รอรอบหน้า)
function CombatService.clearField(meta: CombatMeta)
	table.clear(meta.field)
	meta.gathering = false
end

-- ตัดทหารบนสนามที่ของจริงหายไปแล้ว (debug ล้างคลัง · แม่ถูกย้ายออกจาก roster ทางอื่น) + อัปเดตดาเมจตามขั้นอัปล่าสุด
local function refreshField(data: Data, meta: CombatMeta, stage: number)
	local reserved: { [string]: number } = {}
	local inRoster: { [string]: boolean } = {}
	for _, mother in data.battleRoster do
		inRoster[mother.uid] = true
	end
	for slot = 1, slotCount() do
		local unit = meta.field[slot]
		if unit then
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
			else
				meta.field[slot] = nil
			end
		end
	end
end

local function frontOurSlot(meta: CombatMeta): number?
	for slot = 1, slotCount() do
		if meta.field[slot] then
			return slot
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- tick หลัก — เรียกทุกครั้งที่ผู้เล่นออนไลน์ (loop จริงอยู่ใน CombatService.start())
--------------------------------------------------------------------------------

export type TickResult = {
	unitsReleased: number, -- ทหารที่ลงสนามใน tick นี้ (ลูก + แม่)
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

-- เวลาที่เร็วที่สุดที่ศัตรูชนิดหนึ่งอาจมีช่องว่างลง (ต่ำกว่านี้รับประกันว่ายังเต็ม) — ใช้เลือกจังหวะเหตุการณ์
-- คิวยังมี: ต้องตายอย่างน้อย คิว+1 ตัวก่อนช่องจะว่าง → ขั้นต่ำ = เลือดตัวที่น้อยสุด + ตัวเต็มที่ต้องฆ่าเพิ่ม
-- คิวหมด: ตัวไหนตายก่อนก็ว่างเลย → เวลาตายจริงของแต่ละช่อง
local function enemyKindEventTime(enemy: EnemyState, kind: "big" | "small", incoming: { [number]: number }): number
	local first, last = enemySlotRange(kind)
	local queue = enemyQueueOf(enemy, kind)
	local best = math.huge
	local minHp, totalRate, hitSlots, unitHp = math.huge, 0, 0, 0
	for slot = first, last do
		local unit = enemy.field[slot]
		local rate = incoming[slot] or 0
		if unit and rate > 0 then
			if queue <= 0 then
				best = math.min(best, unit.hp / rate)
			else
				minHp = math.min(minHp, unit.hp)
				totalRate += rate
				hitSlots += 1
				unitHp = unit.maxHp
			end
		end
	end
	if queue > 0 and totalRate > 0 then
		best = (minHp + math.max(0, queue + 1 - hitSlots) * unitHp) / totalRate
	end
	return best
end

-- ใส่ดาเมจ `amount` ให้ศัตรูช่อง slot — ตายแล้วตัวชนิดเดียวกันลงแทน (ดาเมจที่เหลือไหลเข้าตัวใหม่ในช่องเดิม)
-- คืน (HP ที่ลดจริง, จำนวนที่ตาย)
local function damageEnemySlot(enemy: EnemyState, slot: number, amount: number): (number, number)
	local unit = enemy.field[slot]
	if not unit or amount <= 0 then
		return 0, 0
	end
	if amount < unit.hp - unit.maxHp * EPSILON then
		unit.hp -= amount
		return amount, 0
	end
	local dealt = unit.hp
	local left = amount - unit.hp
	local killed = 1
	local kind: "big" | "small" = if unit.kind == "big" then "big" else "small"
	local queue = enemyQueueOf(enemy, kind)
	local unitHp = unit.maxHp
	-- ตัวที่ลงแทนแล้วตายทั้งตัวในรอบเดียวกัน (ผู้เล่นแรงมาก) — คิดรวดเดียว ไม่วนทีละตัว
	local fullKills = math.min(math.floor(left / unitHp + EPSILON), queue)
	dealt += fullKills * unitHp
	left = math.max(0, left - fullKills * unitHp)
	killed += fullKills
	queue -= fullKills
	if queue > 0 then
		queue -= 1
		unit.hp = unitHp - left
		dealt += left
		if unit.hp <= unitHp * EPSILON then
			-- เศษทศนิยมพอดีตัว = ตายด้วย (ไม่ทิ้งตัวเลือด 0 ไว้บนสนาม)
			killed += 1
			if queue > 0 then
				queue -= 1
				unit.hp = unitHp
			else
				enemy.field[slot] = nil
			end
		end
	else
		enemy.field[slot] = nil -- ชนิดนี้หมดแล้ว ช่องว่าง (ดาเมจที่เหลือเล็กน้อยทิ้งไป — เกิดครั้งเดียวต่อชนิดต่อด่าน)
	end
	setEnemyQueue(enemy, kind, queue)
	return dealt, killed
end

-- เดินสนามรบไป `seconds` วินาที (เหตุการณ์ต่อเนื่อง) · ด่านต้องเริ่มแล้วและยังไม่พัง
local function runBattle(data: Data, meta: CombatMeta, stage: number, seconds: number, result: TickResult)
	local combat = Config.Balance.Combat
	local slots = combat.FIELD_SLOTS
	local progress = data.stageProgress[stage] :: StageProgress
	local turretDps = if turretEnabled then Config.getStageTurretDps(stage) else 0
	local shotPeriod = 1 / combat.TURRET_SHOTS_PER_SECOND
	local shotDamage = turretDps * shotPeriod
	local wallTotal = Config.getStageWallHp(stage)
	local enemy = ensureEnemyState(meta, data, stage)

	refreshField(data, meta, stage)
	result.unitsReleased += CombatService.fillField(data, meta, stage)

	local incoming: { [number]: number } = {}
	local t = 0
	local events = 0
	while t < seconds - EPSILON do
		events += 1
		if events > MAX_EVENTS_PER_TICK then
			warn(`[CombatService] เหตุการณ์เกิน {MAX_EVENTS_PER_TICK} ใน tick เดียว (ด่าน {stage}) — หยุด tick นี้ไว้ก่อน`)
			break
		end

		-- อัตราดาเมจตอนนี้
		table.clear(incoming)
		local enemyFront = frontEnemySlot(enemy)
		local wallRate = 0
		for slot = 1, slots do
			local unit = meta.field[slot]
			if unit then
				if enemyFront then
					local target = if enemy.field[slot] then slot else enemyFront
					incoming[target] = (incoming[target] or 0) + unit.dps
				elseif progress.wallHpRemaining > 0 then
					wallRate += unit.dps
				end
			end
		end
		local ourFront = frontOurSlot(meta)
		local enemyDps = 0
		if ourFront then
			for slot = 1, slots do
				local foe = enemy.field[slot]
				if foe then
					enemyDps += foe.dps
				end
			end
		end

		-- เหตุการณ์ถัดไป
		local dt = seconds - t
		if turretDps > 0 then
			dt = math.min(dt, math.max(0, shotPeriod - meta.turretClock))
		end
		dt = math.min(dt, enemyKindEventTime(enemy, "big", incoming), enemyKindEventTime(enemy, "small", incoming))
		if ourFront and enemyDps > 0 then
			dt = math.min(dt, meta.field[ourFront].hp / enemyDps)
		end
		local wallEvent = false
		if wallRate > 0 then
			local wallTime = progress.wallHpRemaining / wallRate
			if wallTime <= dt then
				dt = wallTime
				wallEvent = true
			end
		end
		dt = math.max(0, dt)

		-- เดินเวลา
		t += dt
		meta.turretClock += dt
		local enemyDealt = 0
		for slot = 1, slots do
			local rate = incoming[slot]
			if rate and rate > 0 and dt > 0 then
				local dealt, killed = damageEnemySlot(enemy, slot, rate * dt)
				enemyDealt += dealt
				result.enemiesKilled += killed
			end
		end
		if ourFront and enemyDps > 0 then
			meta.field[ourFront].hp -= enemyDps * dt
		end

		-- บัญชี HP + เงิน (ตัวเดิม applyDamageToStage) · ⚠️ ช่วงศัตรูห้ามล้นไปกำแพง
		local progressMade = 0
		if enemyDealt > 0 and progress.defendersRemaining > 0 then
			local amount = math.min(enemyDealt, progress.defendersRemaining)
			local toDefenders, _, coins = CombatService.applyDamageToStage(data, meta, stage, amount)
			progressMade += toDefenders
			result.coinsEarned += coins
		end
		-- ศัตรูหมดทั้งด่าน → ปิดบัญชีเศษทศนิยมให้ HP ทหารฝ่ายรับเป็น 0 เป๊ะ (เงินครบตามรวม)
		if not frontEnemySlot(enemy) and enemy.bigQueue <= 0 and enemy.smallQueue <= 0 and progress.defendersRemaining > 0 then
			local toDefenders, _, coins = CombatService.applyDamageToStage(data, meta, stage, progress.defendersRemaining)
			progressMade += toDefenders
			result.coinsEarned += coins
		end
		if wallRate > 0 and dt > 0 then
			local amount = wallRate * dt
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

		-- ป้อมยิง (ตัวหน้าสุด · นัดเดียวต่อเป้า ส่วนเกินทิ้ง)
		if turretDps > 0 and meta.turretClock >= shotPeriod - EPSILON then
			meta.turretClock = math.max(0, meta.turretClock - shotPeriod)
			local target = frontOurSlot(meta)
			if target then
				meta.field[target].hp -= shotDamage
				result.turretShots += 1
				meta.lastTurretTarget = target
			end
		end

		-- ทหารเราตาย → ออกจากสนาม (ลูกหักกอง · แม่ตายถาวร)
		for slot = 1, slots do
			local unit = meta.field[slot]
			if unit and unit.hp <= unit.maxHp * EPSILON then
				meta.field[slot] = nil
				killOurUnit(data, unit, result)
				meta.deathsSinceProgress += 1
			end
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

		result.unitsReleased += CombatService.fillField(data, meta, stage)
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

-- คืน releaseOrder ใหม่ถ้า rawOrder ทั้งชุดผ่านกฎ (ทุก key ถูกต้องรูปแบบ + ไม่ซ้ำ + ไม่ยาวเกิน
-- เพดานจำนวนกองสูงสุด) — คืน nil ถ้ามีจุดใดจุดหนึ่งผิด (ผู้เรียกปฏิเสธคำขอทั้งชุดเงียบ ๆ ตามที่
-- ออกแบบไว้ ไม่ apply บางส่วน)
function CombatService.validateReleaseOrder(rawOrder: unknown): { string }?
	if type(rawOrder) ~= "table" then
		return nil
	end
	local order = rawOrder :: { [number]: unknown }

	local length = #order
	if length > Config.Inventory.MAX_CHILD_STACKS then
		return nil
	end

	local cleaned: { string } = table.create(length)
	local seen: { [string]: boolean } = {}

	for index = 1, length do
		local key = order[index]
		if not isValidStackKey(key) then
			return nil
		end
		local keyString = key :: string
		if seen[keyString] then
			return nil
		end
		seen[keyString] = true
		cleaned[index] = keyString
	end

	return cleaned
end

function CombatService.handleSetReleaseOrder(data: Data, rawOrder: unknown): boolean
	local cleaned = CombatService.validateReleaseOrder(rawOrder)
	if not cleaned then
		return false
	end
	data.releaseOrder = cleaned
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

-- 5E-1: สนามรบสำหรับภาพชั่วคราว + HUD — ทหารเรา/ศัตรูรายช่อง (list มี slot กำกับ · ช่องว่างไม่ส่ง)
-- ⚠️ client แค่แสดง · ตัวเลขทั้งหมดมาจากสถานะจริงของ server
local function buildBattleView(data: Data, meta: CombatMeta?, stage: number?)
	local view = {
		stage = stage,
		phase = "idle", -- "enemies" | "wall" | "idle"
		gathering = false,
		available = 0, -- ทหารพร้อมลงสนาม (ลูกในกองที่ติ๊ก + แม่ใน roster ที่ยังไม่ลง)
		gatherTarget = Config.Balance.Combat.GATHER_SIZE,
		our = {},
		enemies = {},
		bigLeft = 0,
		smallLeft = 0,
		bigTotal = 0,
		smallTotal = 0,
		turretActive = false,
		turretShots = 0,
		turretTarget = nil :: number?,
	}
	if not stage then
		return view
	end
	local stats = Config.getStageEnemyStats(stage)
	view.bigTotal = stats.bigCount
	view.smallTotal = stats.smallCount
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
	view.gathering = meta.gathering
	view.available = CombatService.countAvailable(data, meta)
	view.turretShots = meta.lastTurretShots
	view.turretTarget = meta.lastTurretTarget
	for slot = 1, slotCount() do
		local unit = meta.field[slot]
		if unit then
			local character = Config.getCharacter(unit.charId)
			table.insert(view.our, {
				slot = slot,
				kind = unit.kind,
				charId = unit.charId,
				class = if character then character.class else "?",
				hp = unit.hp,
				maxHp = unit.maxHp,
			})
		end
	end
	if enemy and enemy.stage == stage then
		for slot = 1, slotCount() do
			local foe = enemy.field[slot]
			if foe then
				table.insert(view.enemies, { slot = slot, kind = foe.kind, hp = foe.hp, maxHp = foe.maxHp })
			end
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
		-- 5E-1: สนามรบ 6 ต่อ 6 + รวมพล + ป้อม (ภาพชั่วคราว/HUD/หน้าต่างอัญเชิญ "กำลังรวมพล 7/12")
		battle = buildBattleView(data, meta, CombatService.getActiveStage(data)),
	}
end

--------------------------------------------------------------------------------
-- debug (Studio) — เรียกผ่าน EggService.debugBattleStatus / debugTurret
--------------------------------------------------------------------------------

-- สนามทั้ง 12 ช่อง + เลือด + คิวที่เหลือ เป็นข้อความหลายบรรทัด
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
	local reserved = CombatService.getReservedChildren(meta)
	for slot = 1, slotCount() do
		local unit = if meta then meta.field[slot] else nil
		local text = "ว่าง"
		if unit then
			text = string.format(
				"%s %s เลือด %.4g/%.4g ดาเมจ %.4g/วิ",
				if unit.kind == "mother" then "แม่" else "ลูก",
				unit.charId,
				unit.hp,
				unit.maxHp,
				unit.dps
			)
		end
		local foe = if meta and meta.enemy and meta.enemy.stage == stage then meta.enemy.field[slot] else nil
		local foeText = "ว่าง"
		if foe then
			foeText = string.format(
				"%s เลือด %.4g/%.4g ดาเมจ %.4g/วิ",
				if foe.kind == "big" then "ใหญ่" else "เล็ก",
				foe.hp,
				foe.maxHp,
				foe.dps
			)
		end
		table.insert(lines, `ช่อง {slot}: เรา [{text}]  vs  ศัตรู [{foeText}]`)
	end
	local big, small = CombatService.countEnemies(if meta then meta.enemy else nil)
	local enemyQueueText = if meta and meta.enemy
		then `ศัตรูรอลง: ใหญ่ {meta.enemy.bigQueue} · เล็ก {meta.enemy.smallQueue} (เหลือรวม ใหญ่ {big} · เล็ก {small})`
		else "ศัตรูรอลง: (ยังไม่ได้สร้างแถว — สร้างตอน tick แรกที่อัญเชิญ)"
	table.insert(lines, enemyQueueText)
	local queueParts = {}
	for _, key in data.releaseOrder do
		local count = data.children[key] or 0
		table.insert(queueParts, `{key}={math.max(0, count - (reserved[key] or 0))}`)
	end
	table.insert(lines, `คิวลูก (ติ๊กไว้ · ไม่นับตัวบนสนาม): {if #queueParts > 0 then table.concat(queueParts, ", ") else "-"}`)
	local rosterParts = {}
	for _, mother in data.battleRoster do
		local onField = meta ~= nil and motherOnField(meta, mother.uid)
		table.insert(rosterParts, `{mother.uid}{if onField then "(บนสนาม)" else ""}`)
	end
	table.insert(lines, `คิวแม่ (roster): {if #rosterParts > 0 then table.concat(rosterParts, ", ") else "-"}`)
	if meta then
		table.insert(
			lines,
			`พร้อมลง {CombatService.countAvailable(data, meta)} · รวมพล {if meta.gathering then "กำลังรอ" else "ไม่"}`
				.. ` (เป้า {Config.Balance.Combat.GATHER_SIZE}) · ตายติดกันไม่คืบหน้า {meta.deathsSinceProgress}/{Config.Balance.Combat.AUTO_PAUSE_AFTER_DEATHS}`
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
			CombatService.handleSetReleaseOrder(data, rawOrder)
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
