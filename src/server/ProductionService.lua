--!strict
-- egg-army-game :: ผลิตลูก + ผลิตเงินจากแม่ในคอก (Phase 2B-1)
--
-- ⚠️ เฉพาะแม่ใน mothersInPen เท่านั้นที่ผลิต แม่ในกระเป๋าไม่ผลิตอะไรเลย (ไม่มี lastProducedAt)
--
-- ⚠️ สูตรและวิธี settle มาจาก docs/data-schema.md §5 ทั้งหมด ไม่ได้คิดเอง:
--   - อัตราลูก  = Config.getProductionPerMinute(weight, statuses, productionLevel, online)
--   - อัตราเงิน = Config.getCoinsPerMinute(weight, wallProgress, statuses)
--   - คำนวณจาก timestamp (mother.lastProducedAt) ไม่ใช่ loop นับสด — ใช้สูตรเดียวกัน
--     ทั้งออนไลน์และออฟไลน์ ต่างกันแค่ค่า rate (ดูฟังก์ชัน settleMother ด้านล่าง)
--
-- ⚠️ require แบบสองทางเหมือน DataService เพื่อให้ชุดเทสต์ที่รันด้วย luau CLI โหลดไฟล์นี้ได้
-- (settleMother/settleAllInPen ไม่แตะ Roblox API เลยสักตัว มีแค่ start() เท่านั้นที่แตะ)
local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") else nil
local Config = (if Shared then require(Shared.Config) else require("../shared/Config")) :: any

-- ⚠️ PlayerData ถูก require แบบ any เหมือน DataService (เหตุผลเดียวกัน: require สองทาง
-- ทำให้อ้าง type ข้างในตรง ๆ ไม่ได้) โครงจริงของ Data/Mother อยู่ที่ src/shared/PlayerData.lua
type Data = any
type Mother = any

local ProductionService = {}

local Production = Config.Balance.Production

--------------------------------------------------------------------------------
-- นาฬิกา — inject ได้เพื่อเทสต์ (แบบเดียวกับ DataService.injectForTests)
--------------------------------------------------------------------------------

local injectedNow: (() -> number)?

local function now(): number
	if injectedNow then
		return injectedNow()
	end
	return os.time()
end

-- log — inject ได้เพื่อให้เทสต์นับได้ว่าพิมพ์กี่ครั้ง (ไม่ inject = print ปกติ)
local injectedLog: ((string) -> ())?

local function log(message: string)
	if injectedLog then
		injectedLog(message)
	else
		print(message)
	end
end

function ProductionService.injectForTests(fake: { now: (() -> number)?, log: ((string) -> ())? })
	injectedNow = fake.now
	injectedLog = fake.log
end

--------------------------------------------------------------------------------
-- log "คลังลูกเต็ม" — แจ้งครั้งเดียวจนกว่ากองจะลดลงจริง
--------------------------------------------------------------------------------
-- ⚠️ เคยแจ้งตาม "ก่อน settle ยังไม่เต็ม → หลัง settle เต็ม" แล้วพบใน Studio ว่ายังขึ้นทุก 5 วิ:
-- ตอนเปิดอัญเชิญ การรบดึงลูกออกจากกองทุกวินาที กองลดลงนิดหน่อย แล้วแม่เติมกลับถึงเพดานทุกรอบ settle
-- จึงนับว่า "เพิ่งเต็ม" ใหม่ตลอด · แก้เป็นแจ้งครั้งแรกที่เต็ม แล้วเงียบจนกว่ากองจะลดต่ำกว่า
-- FULL_LOG_REARM_RATIO ของเพดาน (ถูกดึงไปรบจนเหลือน้อยจริง) ค่อยแจ้งใหม่ได้อีกครั้ง
-- ⚠️ ค่านี้คุมแค่ log ไม่ใช่ลูกบิดสมดุล จึงไม่อยู่ใน Config.Balance
local FULL_LOG_REARM_RATIO = 0.5

-- [data ของผู้เล่น][stack key] = true เมื่อแจ้งไปแล้ว · อยู่ในหน่วยความจำเท่านั้น ไม่เซฟ
-- ⚠️ weak key: ผู้เล่นออกเกม → data หลุดจากแคช DataService → แถวนี้หายเอง ไม่ต้องล้างเอง
local fullLogged: { [any]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

local function logStackFullOnce(data: Data, mother: Mother, key: string, stackBefore: number, stackAfter: number, stackCap: number)
	local logged = fullLogged[data]
	if not logged then
		logged = {}
		fullLogged[data] = logged
	end

	-- เช็คจาก stackBefore เพราะการรบดึงลูกออก "ระหว่าง" รอบ settle ไม่ใช่ในรอบนี้
	if stackBefore < stackCap * FULL_LOG_REARM_RATIO then
		logged[key] = nil
	end

	if stackAfter >= stackCap and not logged[key] then
		logged[key] = true
		log(`[ProductionService] แม่ {mother.uid} คลังลูก "{key}" เต็ม ({stackCap} ตัว) หยุดผลิตชั่วคราว`)
	end
end

--------------------------------------------------------------------------------
-- settle แม่ 1 ตัว
--------------------------------------------------------------------------------

-- settle การผลิตของแม่ 1 ตัวในคอก (ลูก + เงิน ใช้หน้าต่างเวลาเดียวกัน ไม่แยก timestamp
-- ตามที่ตกลงไว้ — mother.lastProducedAt มีฟิลด์เดียว ไม่ใช่สองฟิลด์แยกกัน)
--
-- คืน (childrenProduced, coinsEarned, hitStackCap)
--
-- ⚠️ แม่ที่ไม่มี lastProducedAt (คือแม่ในกระเป๋า) ต้องไม่ถูกเรียกฟังก์ชันนี้เลย —
-- กันไว้อีกชั้นด้วยการคืน (0, 0, false) เฉย ๆ ถ้าเผลอเรียกผิด แทนที่จะ error
function ProductionService.settleMother(data: Data, mother: Mother, online: boolean): (number, number, boolean)
	if mother.lastProducedAt == nil then
		return 0, 0, false
	end

	local nowValue = now()

	-- ⚠️ เพดานตรงนี้ — คำนวณย้อนได้ไม่เกิน OFFLINE_CAP_SECONDS เสมอ
	-- ไม่ว่า lastProducedAt จะเก่าแค่ไหน (ตัวอย่าง: หายไป 30 ชม. คิดให้แค่ 8 ชม.)
	local windowStart = math.max(mother.lastProducedAt, nowValue - Production.OFFLINE_CAP_SECONDS)
	local elapsed = math.max(0, nowValue - windowStart)
	if elapsed <= 0 then
		return 0, 0, false
	end

	-- ⚠️ ใช้ Config.getProductionPerMinute() เท่านั้น ห้ามคูณเอง — ในนั้นรวม
	-- น้ำหนักแม่^WEIGHT_EXPONENT · ตัวคูณ upgrade · บัฟสถานะ · ตัวคูณออฟไลน์ ครบแล้ว
	local childRatePerSecond = Config.getProductionPerMinute(mother.weight, mother.statuses, data.productionLevel, online)
		/ 60

	local rawChildren = math.floor(elapsed * childRatePerSecond)
	rawChildren = math.min(rawChildren, Production.MAX_PER_SETTLE)

	local key = Config.makeStackKey(mother.charId, mother.weight, mother.statuses)
	local stackCap = Config.getStackCap()
	local stackBefore = data.children[key] or 0
	local capRemaining = math.max(0, stackCap - stackBefore)
	local actualChildren = math.min(rawChildren, capRemaining)
	local hitCap = actualChildren < rawChildren

	-- ⚠️ จุดที่พลาดกันบ่อยที่สุด (docs/data-schema.md §5.2): ต้องเลื่อน lastProducedAt
	-- ไปเท่าที่ "ใช้จริง" (actualChildren/rate) ไม่ใช่ nowValue ตรง ๆ
	-- ไม่งั้นเศษเวลาที่ยังไม่ครบ 1 ตัวจะถูกทิ้งทุกรอบ ตอน tick ถี่ (ทุก 5 วิ) ผู้เล่นจะไม่ได้ลูกเลยสักตัว
	-- และถ้าคลังเต็ม (hitCap) เวลาที่เกินมาจะไม่ถูกนับว่า "ใช้แล้ว" ด้วย เพราะผลิตออกมาจริงไม่ได้
	--
	-- ⚠️ เงินใช้ timeUsed ตัวเดียวกันนี้ (ไม่แยก timestamp ตามที่ตกลงไว้) ผลข้างเคียงที่ยอมรับ:
	-- ถ้าลูกโดนเพดานคลังจำกัดไว้ เงินของรอบนั้นจะคำนวณจากเวลาที่สั้นลงตามไปด้วย (ไม่ใช่ elapsed เต็ม)
	-- เพราะใช้ timestamp เดียวกัน — ไม่ใช่ bug สะสม (ไม่ compound ข้ามรอบ) แค่รอบที่ชนเพดานเงินจะได้น้อยลงด้วย
	local timeUsed = elapsed
	if childRatePerSecond > 0 then
		timeUsed = actualChildren / childRatePerSecond
	end

	local coinRatePerMinute = Config.getCoinsPerMinute(mother.weight, data.wallProgress, mother.statuses)
	if online == false then
		coinRatePerMinute *= Production.OFFLINE_RATE_RATIO
	end
	local coinsEarned = math.floor(timeUsed * coinRatePerMinute / 60)
	coinsEarned = math.min(coinsEarned, Production.MAX_PER_SETTLE)

	if actualChildren > 0 then
		data.children[key] = (data.children[key] or 0) + actualChildren
		data.stats.childrenProduced += actualChildren
	end

	if coinsEarned > 0 then
		data.currency.coins += coinsEarned
		data.stats.totalCoinsEarned += coinsEarned
	end

	mother.lastProducedAt = windowStart + timeUsed

	-- ⚠️ ไม่พิมพ์ทุกรอบที่ hitCap (เคยท่วม console) — ดู logStackFullOnce ข้างบน
	-- ค่า hitCap ที่คืนออกไปยังความหมายเดิม (รอบนี้ผลิตไม่ครบเพราะคลังเต็ม)
	logStackFullOnce(data, mother, key, stackBefore, stackBefore + actualChildren, stackCap)

	return actualChildren, coinsEarned, hitCap
end

-- settle ทุกแม่ใน mothersInPen รวดเดียว — ใช้ตอน login (offline) / logout / tick (online)
-- คืน (childrenรวม, เงินรวม, มีแม่ตัวไหนชนเพดานคลังไหม)
function ProductionService.settleAllInPen(data: Data, online: boolean): (number, number, boolean)
	local totalChildren, totalCoins = 0, 0
	local anyHitCap = false

	for _, mother in data.mothersInPen do
		local children, coins, hitCap = ProductionService.settleMother(data, mother, online)
		totalChildren += children
		totalCoins += coins
		if hitCap then
			anyHitCap = true
		end
	end

	return totalChildren, totalCoins, anyHitCap
end

--------------------------------------------------------------------------------
-- ลูปออนไลน์ — settle ทุก Production.TICK_INTERVAL วิ แล้วเรียก onTick(player) ให้ sync
--------------------------------------------------------------------------------

-- ⚠️ TICK_INTERVAL ไม่กระทบผลลัพธ์เลย (คอมเมนต์ใน Config พูดไว้ตรง ๆ) แค่ความถี่อัปเดต UI
-- ตัวเลขคำนวณจาก mother.lastProducedAt เสมอ ต่อให้เซิร์ฟ lag หรือ tick ห่างกว่าที่ตั้งไว้
-- ผลลัพธ์ก็ยังถูกต้อง เพราะเป็น catch-up จาก timestamp ไม่ใช่การนับสะสมทีละ tick
--
-- onTick ถูก inject เข้ามาแทนที่จะ require EggService ตรง ๆ — กัน circular require
-- (EggService ต้อง require ProductionService.settleMother ไปใช้ตอนย้ายแม่ออกจากคอกด้วย)
function ProductionService.start(onTick: ((Player) -> ())?)
	local Players = game:GetService("Players")
	local ServerScriptService = game:GetService("ServerScriptService")
	local DataService = require(ServerScriptService.DataService)

	task.spawn(function()
		while true do
			task.wait(Production.TICK_INTERVAL)

			for _, player in Players:GetPlayers() do
				local data = DataService.getCached(player.UserId)
				if data then
					ProductionService.settleAllInPen(data, true)
					if onTick then
						onTick(player)
					end
				end
			end
		end
	end)
end

return ProductionService
