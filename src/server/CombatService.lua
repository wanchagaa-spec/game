--!strict
-- egg-army-game :: เครื่องยนต์คำนวณรบฝั่ง server (Phase 3A — ไม่มีภาพ/UI)
--
-- ปล่อยทหาร (ลูกจากคลัง) ต่อเนื่องตามอัตราของด่านที่กำลังตี → สะสม damage →
-- ตีทหารฝ่ายรับก่อน (defendersRemaining) แล้วส่วนเกินไหลไปตีกำแพงในตาเดียวกัน
-- (wallHpRemaining) → จ่ายเงินตามสัดส่วน HP ทหารฝ่ายรับ (ไม่รวมกำแพง) ที่ลดไป
--
-- ⚠️ ปล่อยเฉพาะตอนออนไลน์เท่านั้น — ต่างจาก ProductionService ที่มี offline settlement
-- ปิดเกม/ออกเกมแล้วหยุดสู้ทันที ไม่มี catch-up ย้อนหลัง (docs/data-schema.md §7.1)
-- เพราะงั้นฟังก์ชันหลักในไฟล์นี้ไม่ต้องพึ่ง os.time()/timestamp แบบ ProductionService เลย —
-- รับ elapsedSeconds ตรง ๆ จาก loop ที่เรียก (CombatService.start()) ทำให้เทสต์เรียกตรง ๆ
-- ได้เลยโดยไม่ต้องปลอมนาฬิกา
--
-- ⚠️ ยังไม่ทำในเฟสนี้ (ดู CLAUDE.md/ไม่ทำ turret/ระบบรบด้วยตัวเอง/ส่งแม่ไปรบ/บอส):
-- damage ในนี้จึงไหลทางเดียว (กองทัพเรา → ทหารฝ่ายรับ/กำแพง) ไม่มีความเสียหายย้อนกลับใส่เรา
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
-- ⚠️ ไม่มี offline catch-up ให้ระบบนี้อยู่แล้ว จึงไม่จำเป็นต้องเซฟเศษที่สะสมไว้เลย
-- เสียเศษไม่ถึง 1 หน่วย/1 เหรียญตอนออกเกมถือว่ายอมรับได้ (เทียบไม่ได้กับตัวเลขที่เล่นจริง)
-- และ "ไม่มี offline progress" ก็เป็นกติกาที่ตั้งใจอยู่แล้วด้วย

export type CombatMeta = {
	releaseCarry: number, -- เศษจำนวนหน่วยที่ยังไม่ถึง 1 ตัว สะสมข้ามรอบ tick (กัน rate เศษหายตอนปัดเศษทุกรอบ)
	coinCarry: number, -- เศษเหรียญที่ยังไม่ถึง 1 เหรียญ สะสมข้ามรอบ tick ด้วยเหตุผลเดียวกัน
	unitsSinceProgress: number, -- ใช้กับ auto-pause (§7.6) — รีเซ็ตทุกครั้งที่ตีแล้ว HP ลดจริง
	lastTickClock: number?, -- os.clock() ของ tick ก่อนหน้า ใช้เฉพาะใน loop จริง (ไม่ใช้ในเทสต์)
}

local combatMeta: { [number]: CombatMeta } = {}

function CombatService.newMeta(): CombatMeta
	return { releaseCarry = 0, coinCarry = 0, unitsSinceProgress = 0, lastTickClock = nil }
end

function CombatService.getOrCreateMeta(userId: number): CombatMeta
	local meta = combatMeta[userId]
	if not meta then
		meta = CombatService.newMeta()
		combatMeta[userId] = meta
	end
	return meta
end

function CombatService.clearMeta(userId: number)
	combatMeta[userId] = nil
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

-- กองใน data.children ที่ยังไม่เคยอยู่ใน releaseOrder (เพิ่งผลิตครั้งแรก) → ต่อท้ายอัตโนมัติ
-- ⚠️ ไม่ลบ key ออกจาก releaseOrder แม้กองนั้นจะว่างแล้ว (เผื่อผลิตเพิ่มมาเติมทีหลัง
-- จะได้กลับมาอยู่คิวเดิมโดยไม่ต้องจัดใหม่)
function CombatService.reconcileReleaseOrder(data: Data)
	local present: { [string]: boolean } = {}
	for _, key in data.releaseOrder do
		present[key] = true
	end
	for key in data.children do
		if not present[key] then
			table.insert(data.releaseOrder, key)
			present[key] = true
		end
	end
end

-- ดึงทหาร `unitsToRelease` ตัวจากหัวคิว ข้ามกองที่ว่าง (count<=0/ไม่มี) โดยไม่ลบออกจากลำดับ
-- คืน (unitsActuallyReleased, totalPower) — totalPower ผ่าน Config.computeBattlePower() ต่อหน่วย
-- (รวมตัวคูณ damageLevel ที่ซื้อด้วยเงินไว้แล้ว) ตามน้ำหนักลูก+ตัวละคร+สถานะของกองนั้น ๆ
-- ⚠️ ถ้าทุกกองในลำดับว่างหมด (count=0) ไม่ error แค่คืน (0, 0) เฉย ๆ
function CombatService.releaseFromQueue(data: Data, unitsToRelease: number): (number, number)
	if unitsToRelease <= 0 then
		return 0, 0
	end

	local remaining = unitsToRelease
	local totalReleased = 0
	local totalPower = 0

	for _, key in data.releaseOrder do
		if remaining <= 0 then
			break
		end

		local available = data.children[key]
		if available and available > 0 then
			local charId, motherWeight, statuses = Config.parseStackKey(key)
			-- key เพี้ยน (ไม่น่าเกิดเพราะสร้างจาก Config.makeStackKey() เท่านั้น) → ข้ามเงียบ ๆ
			if charId and motherWeight then
				local take = math.min(available, remaining)
				local childWeight = Config.getChildWeight(motherWeight, statuses)
				local power = Config.computeBattlePower(childWeight, charId, statuses, data.damageLevel)

				totalReleased += take
				totalPower += take * power
				remaining -= take

				local newCount = available - take
				if newCount > 0 then
					data.children[key] = newCount
				else
					data.children[key] = nil
				end
			end
		end
	end

	return totalReleased, totalPower
end

--------------------------------------------------------------------------------
-- battleRoster — แม่ที่ส่งไปรบ (Phase 3C-1)
--------------------------------------------------------------------------------
-- ⚠️ แม่หนึ่งตัวอยู่ได้ที่เดียว: ส่งไปรบ = ย้ายออกจาก mothersInBag มาไว้ data.battleRoster
-- ย้อนกลับไม่ได้ · ตายหมดพร้อมกันตอนด่านที่กำลังตีพัง (killRoster) · ไม่มี HP รายตัวในเฟสนี้
-- (วิสัยทัศน์ HP รายตัวอยู่ใน docs/combat-hp-vision.md — ไม่ใช่เงื่อนไขของเฟสนี้)

-- damage/วินาทีของแม่ทั้ง roster — แม่แต่ละตัวตีวินาทีละครั้ง แรงเท่าพลังของตัวเอง
-- ใช้ Config.computeBattlePower ตัวเดียวกับลูก (รวมตัวคูณคลาส/สถานะ/damageLevel แล้ว)
-- ลูกหนัก 1% ของแม่ → แรง 10% ของแม่ → แม่ 1 ตัว = ปล่อยลูก 10 ตัวต่อวินาที
function CombatService.getRosterDps(data: Data): number
	local total = 0
	for _, mother in data.battleRoster do
		total += Config.computeBattlePower(mother.weight, mother.charId, mother.statuses, data.damageLevel)
	end
	return total
end

-- คืน (ok, message) — message เป็นภาษาไทยพร้อมโชว์ผู้เล่นทาง ActionResult ทั้งกรณีสำเร็จ/ล้มเหลว
-- ⚠️ ด่านสุดท้ายของการตรวจ — client ตรวจ roster เต็มก่อนเองก็จริง แต่ห้ามเชื่อ client
function CombatService.handleSendMotherToBattle(data: Data, rawUid: unknown): (boolean, string)
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

	local stage = CombatService.getActiveStage(data)
	if not stage then
		return false, "ผ่านครบทุกด่านแล้ว ไม่มีด่านให้ส่งแม่ไปรบ"
	end
	-- ⚠️ ด่านที่ไม่มีศัตรูเลย (ด่าน 1) นับว่า "พัง" ตั้งแต่ตาแรกที่แตะ → แม่จะตายฟรีทันที
	if Config.getStageTotalHp(stage) <= 0 then
		return false, `ด่าน {stage} ไม่มีศัตรูให้ตี — เปิดอัญเชิญให้ผ่านด่านนี้ไปก่อน`
	end

	local mother = table.remove(data.mothersInBag, bagIndex)
	table.insert(data.battleRoster, mother)
	return true, `ส่งแม่ไปรบแล้ว (roster {#data.battleRoster}/{maxMothers})`
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
-- tick หลัก — เรียกทุกครั้งที่ผู้เล่นออนไลน์ (loop จริงอยู่ใน CombatService.start())
--------------------------------------------------------------------------------

export type TickResult = {
	unitsReleased: number,
	damageDealt: number,
	coinsEarned: number,
	stageCleared: boolean,
	autoPaused: boolean,
	mothersLost: number, -- แม่ใน roster ที่ตายในตานี้ (ด่านพัง) — 0 ถ้าด่านยังไม่พัง
	clearedStage: number?, -- ด่านที่เพิ่งพังในตานี้ (nil ถ้าไม่มี)
	bonusEggs: number, -- ไข่ฟรีที่ต้องแจก (Phase 4A) — 0 ถ้าไม่มีด่านพัง หรือเคยได้รางวัลด่านนี้แล้ว
}

local EMPTY_RESULT: TickResult = {
	unitsReleased = 0,
	damageDealt = 0,
	coinsEarned = 0,
	stageCleared = false,
	autoPaused = false,
	mothersLost = 0,
	clearedStage = nil,
	bonusEggs = 0,
}

-- auto-pause (§7.6): กันทหารถูกป้อนเข้าเครื่องบดหายถาวรโดยไม่ได้ damage เลย
-- นับจาก HP ที่ลดจริง (progressMade) ไม่ใช่จาก damage ที่ "พยายาม" ทำ — สองค่านี้ต่างกัน
-- เฉพาะตอนด่านเคลียร์ไปแล้วเท่านั้น (แยกเป็นฟังก์ชันของตัวเองให้เทสต์เรียกตรง ๆ ได้โดยไม่ต้อง
-- พึ่ง getActiveStage เลือกด่านให้ถูกจังหวะ)
-- ⚠️ ในเฟสนี้ (ยังไม่มี turret) เส้นทาง progressMade<=0 แทบไม่มีวันเกิดจริง เพราะ
-- Config.computeBattlePower มีพื้น minDamage บวก ๆ เสมอ — ใส่ไว้เป็นตาข่ายกันไว้ก่อนตามที่
-- ออกแบบ ให้ turret ในเฟสหลังเสียบเข้ามาได้โดยไม่ต้องแก้จุดนี้อีก
-- คืน true ถ้าการเรียกครั้งนี้ทำให้ auto-pause ทำงาน (ปิด summonEnabled ไปแล้ว)
function CombatService.registerProgress(data: Data, meta: CombatMeta, unitsReleased: number, progressMade: number): boolean
	if unitsReleased <= 0 then
		return false
	end

	if progressMade > 0 then
		meta.unitsSinceProgress = 0
		return false
	end

	meta.unitsSinceProgress += unitsReleased
	if meta.unitsSinceProgress >= Config.Balance.Combat.AUTO_PAUSE_AFTER_UNITS then
		data.summonEnabled = false
		data.combatAutoPaused = true
		meta.unitsSinceProgress = 0
		return true
	end

	return false
end

-- ⚠️ ไม่มี offline catch-up: ฟังก์ชันนี้รับ elapsedSeconds ตรง ๆ ไม่อ่าน os.time()/os.clock() เอง
-- ปิดเกม/ออกเกม = ไม่มีใครเรียกฟังก์ชันนี้ = ไม่มีอะไรคืบหน้า (ตรงข้ามกับ ProductionService ที่มี
-- offline settlement) — แค่ไม่เรียกก็พอ ไม่ต้องมี flag พิเศษกันไว้
function CombatService.tick(data: Data, meta: CombatMeta, elapsedSeconds: number): TickResult
	if not data.summonEnabled or elapsedSeconds <= 0 then
		return EMPTY_RESULT
	end

	local stage = CombatService.getActiveStage(data)
	if not stage then
		return EMPTY_RESULT -- ผ่านครบทุกด่านแล้ว ไม่มีอะไรให้ตีต่อ
	end

	CombatService.ensureStageStarted(data, stage)
	CombatService.reconcileReleaseOrder(data)

	local rate = Config.getReleaseRate(stage)
	local budget = meta.releaseCarry + rate * elapsedSeconds
	local unitsToRelease = math.floor(budget)
	meta.releaseCarry = budget - unitsToRelease

	local unitsReleased, childDamage = CombatService.releaseFromQueue(data, unitsToRelease)
	-- แม่ใน roster ตีต่อเนื่องทุกวินาที ไม่ผ่านคิวปล่อย (ไม่นับเป็น "หน่วยที่ปล่อย" ของ auto-pause)
	-- ⚠️ ตีเฉพาะตอนเปิดอัญเชิญ — ปิดอัญเชิญแล้ว return ตั้งแต่บรรทัดแรก แม่หยุดรอ ไม่ตาย ไม่ตี
	local damageDealt = childDamage + CombatService.getRosterDps(data) * elapsedSeconds

	local coinsEarned = 0
	local stageCleared = false
	local progressMade = 0
	local mothersLost = 0
	local bonusEggs = 0

	if damageDealt > 0 then
		local dmgToDefenders, dmgToWall, coins, cleared =
			CombatService.applyDamageToStage(data, meta, stage, damageDealt)
		coinsEarned = coins
		stageCleared = cleared
		progressMade = dmgToDefenders + dmgToWall

		-- ⚠️ อัปเดตทันทีในตาที่พังใหม่ ไม่ต้องรอ tick ถัดไป — ระบบเงิน/เพดานอัปเกรดที่ผูกกับ
		-- wallProgress (เช่น Config.getCoinsPerMinute/getMaxDamageLevel) จะได้ใช้ค่าล่าสุดทันที
		if stageCleared then
			CombatService.recomputeWallProgress(data)
			-- ⚠️ แม่ทั้ง roster ตายถาวรพร้อมกันทันทีที่ด่านที่กำลังตีพัง
			mothersLost = CombatService.killRoster(data, stage)
			-- ⚠️ Phase 4A: รางวัลผูกกับจังหวะนี้ (เพิ่งพัง) ไม่ใช่กับสถานะ "พังอยู่" — ดู claimStageClearBonus
			bonusEggs = CombatService.claimStageClearBonus(data, stage)
		end
	end

	local autoPaused = CombatService.registerProgress(data, meta, unitsReleased, progressMade)

	return {
		unitsReleased = unitsReleased,
		damageDealt = damageDealt,
		coinsEarned = coinsEarned,
		stageCleared = stageCleared,
		autoPaused = autoPaused,
		mothersLost = mothersLost,
		clearedStage = if stageCleared then stage else nil,
		bonusEggs = bonusEggs,
	}
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

function CombatService.handleSetSummonEnabled(data: Data, meta: CombatMeta, rawEnabled: unknown): boolean
	if type(rawEnabled) ~= "boolean" then
		return false
	end
	data.summonEnabled = rawEnabled
	if rawEnabled then
		-- ผู้เล่นกดเปิดเอง = รับทราบแจ้งเตือน auto-pause แล้ว เริ่มนับใหม่
		data.combatAutoPaused = false
		meta.unitsSinceProgress = 0
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

function CombatService.buildSyncFields(data: Data)
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
	local battleRoster = table.create(#data.battleRoster)
	for _, mother in data.battleRoster do
		table.insert(battleRoster, {
			uid = mother.uid,
			charId = mother.charId,
			weight = mother.weight,
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
	}
end

--------------------------------------------------------------------------------
-- ต่อสาย Roblox จริง (RemoteEvent + loop) — เรียกจาก Main.server.lua เท่านั้น
--------------------------------------------------------------------------------
-- ⚠️ require ของจริงทั้งหมดอยู่ *ในตัวฟังก์ชัน* ไม่ใช่ระดับโมดูล เหมือน ProductionService.start()
-- เพื่อให้ require ไฟล์นี้จาก tests/run.luau (นอก Roblox) ได้โดยไม่พังตั้งแต่โหลด

-- `onStageCleared(player, stage, eggCount)` = EggService.grantStageClearBonus (Main.server.lua ส่งเข้ามา)
-- ⚠️ inject แทน require EggService ตรง ๆ กัน circular require (EggService require ไฟล์นี้อยู่แล้ว)
-- แบบเดียวกับ ProductionService.start(EggService.sync)
function CombatService.start(onStageCleared: (Player, number, number) -> ())
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	local DataService = require(ServerScriptService.DataService)

	local setReleaseOrderRequest = Remotes.waitFor(Config.RemoteNames.SET_RELEASE_ORDER_REQUEST)
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
			CombatService.handleSetSummonEnabled(data, CombatService.getOrCreateMeta(player.UserId), rawEnabled)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CombatService.clearMeta(player.UserId)
	end)

	-- ⚠️ ลูปเดียวคุมทั้งการปล่อย+ตี ความละเอียด = Config.World.SYNC_INTERVAL (ค่าเดียวกับ
	-- ลูป sync ของ EggService) ใช้ os.clock() วัด elapsed จริงระหว่างรอบ กัน drift จาก
	-- task.wait() ที่ไม่เป๊ะ 1 วินาทีเป๊ะทุกรอบ (ตัวนับเศษ meta.releaseCarry รับส่วนที่เหลือไว้)
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
					local result = CombatService.tick(data, meta, elapsed)
					if result.clearedStage and result.bonusEggs > 0 then
						-- ⚠️ pcall: แจกไข่พังเมื่อไหร่ต้องไม่ลากลูปรบของทั้งเซิร์ฟตายไปด้วย (ธงติดไปแล้ว — log ไว้ตามแก้)
						local clearedStage, bonusEggs = result.clearedStage, result.bonusEggs
						local ok, err = pcall(function(): string?
							onStageCleared(player, clearedStage, bonusEggs)
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
