--!strict
-- egg-army-game :: อ่าน/เขียน PlayerData ลง DataStore
--
-- ⚠️ ไฟล์นี้คือจุดเดียวในโปรเจกต์ที่แตะ DataStore ได้ ที่อื่นห้ามเรียกเอง
-- และ **client ห้ามแตะเด็ดขาด** — ไม่มี RemoteEvent ตัวไหนพาถึงไฟล์นี้ได้
--
-- ⚠️ ความผิดพลาดของ DataStore **เงียบกว่าบั๊กทั่วไป**: เซฟล้ม → ไม่มี error ให้เห็น →
-- ผู้เล่นรู้ตัวอีกทีตอนเข้าเกมใหม่แล้วของหาย กติกาสามข้อที่ตามมาจากเรื่องนี้:
--
--   1. **UpdateAsync ทุก path ห้ามใช้ SetAsync** — SetAsync เขียนทับโดยไม่ดูของเดิม
--      สองเซิร์ฟเวอร์ที่ถือข้อมูลคนเดียวกันจะทับกันเงียบ ๆ
--   2. **session lock** — กันไม่ให้มีสองเซิร์ฟเวอร์ถือข้อมูลคนเดียวกันตั้งแต่แรก
--   3. **โหลดไม่สำเร็จ = เตะออก ห้ามเล่นแบบไม่มีข้อมูล** (เหตุผลเต็มที่ LOAD_FAILED_MESSAGE)
--
-- ⚠️ require แบบสองทางเหมือน Config เพื่อให้ชุดเทสต์ที่รันด้วย luau CLI โหลดไฟล์นี้ได้
-- service ของ Roblox ทั้งหมดจึงต้องดึงแบบ lazy ห้ามดึงตอน require

local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") else nil

local Config = (if Shared then require(Shared.Config) else require("../shared/Config")) :: any
local PlayerData = (if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")) :: any

-- ⚠️ PlayerData ถูก cast เป็น any (เพราะ require สองทาง) จึงอ้าง type ข้างในไม่ได้
-- โครงจริงของ Data อยู่ที่ src/shared/PlayerData.lua — ที่นี่สนใจแค่ว่ามันเป็นตารางที่ encode ได้
type Data = any

local DataService = {}

local DS = Config.DataStore

-- ⚠️ `warn` เป็น global ของ Roblox — ไม่มีตอนรันด้วย luau CLI ในชุดเทสต์
-- ไม่มี fallback แล้วเทสต์ที่จำลอง "DataStore ล่ม" จะพังตรงบรรทัดที่เตือน แทนที่จะวัด retry
local logWarn: (...any) -> () = (warn :: any) or print

-- ข้อความตอนโหลดไม่สำเร็จ
--
-- ⚠️ **ห้ามมีโหมด guest ที่ปล่อยให้เล่นต่อด้วยข้อมูลเปล่า**
-- ถ้าปล่อยเล่นต่อ รอบ autosave ถัดไปจะเขียนข้อมูลเปล่าทับของจริงที่ยังอยู่ดี ๆ ใน DataStore
-- = ผู้เล่นเสียของถาวรเพราะ DataStore แค่กระตุกชั่วคราว
-- เตะออกแล้วให้เข้าใหม่เจ็บน้อยกว่ามาก และข้อมูลยังปลอดภัยครบ
local LOAD_FAILED_MESSAGE = "โหลดข้อมูลไม่ได้ ลองเข้าใหม่ในอีกสักครู่ — ข้อมูลของคุณปลอดภัย"
local LOCKED_MESSAGE = "ข้อมูลของคุณกำลังใช้งานอยู่ที่เซิร์ฟเวอร์อื่น รอสักครู่แล้วลองใหม่"
local FUTURE_SCHEMA_MESSAGE = "ข้อมูลของคุณมาจากเกมเวอร์ชันใหม่กว่านี้ — เซิร์ฟเวอร์นี้จะไม่แตะข้อมูลของคุณ"

DataService.LOAD_FAILED_MESSAGE = LOAD_FAILED_MESSAGE
DataService.LOCKED_MESSAGE = LOCKED_MESSAGE
DataService.FUTURE_SCHEMA_MESSAGE = FUTURE_SCHEMA_MESSAGE

--------------------------------------------------------------------------------
-- ของที่ต่อกับโลกภายนอก — เปลี่ยนได้ในเทสต์
--------------------------------------------------------------------------------

-- ⚠️ ทั้งสี่ตัวนี้คือ "รอยต่อ" ที่ทำให้ตรรกะ retry กับ session lock ทดสอบได้จริง
-- ถ้าเรียก DataStoreService / task.wait / os.time ตรง ๆ ในโค้ด จะทดสอบได้แค่ใน Studio
-- ซึ่งแปลว่าจะไม่มีใครทดสอบมันเลย
local store: any = nil
local sleep: (number) -> () = function(seconds)
	if task then
		task.wait(seconds)
	end
end
local now: () -> number = os.time
local sessionJobId: () -> string = function()
	return if game then game.JobId else "offline"
end
local sessionPlaceId: () -> number = function()
	return if game then game.PlaceId else 0
end

-- ข้อมูลที่ถืออยู่ในหน่วยความจำของเซิร์ฟเวอร์นี้
-- ⚠️ ถือได้เพราะ session lock รับประกันว่าไม่มีเซิร์ฟเวอร์อื่นถือชุดเดียวกันอยู่
local cache: { [number]: Data } = {}

-- กันเซฟซ้อนของผู้เล่นคนเดียวกัน (autosave ชนกับตอนออกเกม)
local saving: { [number]: boolean } = {}

-- ⚠️ log ให้เห็น "อะไรถูกเขียนลงไปจริง" ไม่ใช่แค่ "เซฟสำเร็จ"
-- บั๊กข้อมูลหายรอบก่อนใช้เวลาไล่นาน เพราะ log บอกแค่ว่าเซฟผ่าน
-- แต่ไม่บอกว่าสิ่งที่เซฟมีแม่กี่ตัว
local function describe(data: Data): string
	local hatching = 0
	for _, slot in data.hatching do
		if type(slot) == "table" then
			hatching += 1
		end
	end
	return `แม่ในคอก {#data.mothersInPen} · กระเป๋า {#data.mothersInBag} · `
		.. `ไข่ฟัก {hatching} · ไข่ในกระเป๋า {#data.heldEggs.items}`
end

--------------------------------------------------------------------------------
-- ตั้งค่า
--------------------------------------------------------------------------------

-- ⚠️ เลือก store ด้วย RunService:IsStudio() ไม่ใช่ธงที่ต้องสลับมือ
-- ธงที่ต้องสลับมือมีวันลืมสลับ แล้ววันนั้นคือวันที่เทสต์เขียนทับข้อมูลผู้เล่นจริง
function DataService.storeName(): string
	if game and game:GetService("RunService"):IsStudio() then
		return DS.DEV_NAME
	end
	return DS.NAME
end

function DataService.keyFor(userId: number): string
	return DS.KEY_PREFIX .. tostring(userId)
end

function DataService.init()
	if store then
		return
	end
	store = game:GetService("DataStoreService"):GetDataStore(DataService.storeName())
	print(`[DataService] ใช้ DataStore "{DataService.storeName()}"`)
end

-- รอยต่อสำหรับเทสต์: ยัด store ปลอม นาฬิกาปลอม และ sleep ที่ไม่หน่วงจริงเข้ามา
function DataService.injectForTests(fake: {
	store: any,
	sleep: ((number) -> ())?,
	now: (() -> number)?,
	jobId: (() -> string)?,
})
	store = fake.store
	if fake.sleep then
		sleep = fake.sleep
	end
	if fake.now then
		now = fake.now
	end
	if fake.jobId then
		sessionJobId = fake.jobId
	end
	cache = {}
	saving = {}
end

function DataService.getCached(userId: number): Data?
	return cache[userId]
end

--------------------------------------------------------------------------------
-- retry
--------------------------------------------------------------------------------

-- ⚠️ ครั้งแรกยิงทันที ไม่หน่วง — หน่วงเฉพาะ "ก่อนลองซ้ำ" (2 → 4 → 8)
-- ถ้าหน่วงตั้งแต่ครั้งแรก ผู้เล่นทุกคนจะรอ 2 วินาทีฟรี ๆ ทั้งที่ปกติสำเร็จตั้งแต่ครั้งแรก
--
-- `deadline` เป็น os.time() ที่ห้ามเกิน (ใช้ตอน BindToClose ซึ่งมีงบแค่ 30 วินาที)
-- คืน (ok, ผลลัพธ์หรือข้อความ error, จำนวนครั้งที่ลอง)
-- ⚠️ `fn` ไม่คืนค่า — ผลลัพธ์ส่งออกทาง upvalue ของผู้เรียก
-- ถ้าให้มันคืนค่า typechecker จะอนุมานชนิดไม่ได้เวลาผู้เรียกไม่ได้คืนอะไร
function DataService.retryAsync(label: string, fn: () -> (), deadline: number?): (boolean, any, number)
	local attempts = DS.RETRY_COUNT
	local delay = DS.RETRY_BASE_DELAY
	local lastError: any = nil

	for attempt = 1, attempts do
		if attempt > 1 then
			-- ⚠️ เหลือเวลาไม่พอสำหรับรอบถัดไป ก็อย่าเริ่ม — ดีกว่าถูกตัดกลาง UpdateAsync
			if deadline and now() + delay >= deadline then
				return false, `{label}: หมดเวลาก่อนลองซ้ำครั้งที่ {attempt} ({tostring(lastError)})`, attempt - 1
			end
			sleep(delay)
			delay *= 2
		end

		-- cast เพราะ `fn` ประกาศว่าไม่คืนค่า แต่ pcall คืน (ok, error) เสมอเวลาล้ม
		local ok, result = pcall(fn :: () -> any)
		if ok then
			return true, result, attempt
		end

		lastError = result
		logWarn(`[DataService] {label} ล้มครั้งที่ {attempt}/{attempts}: {tostring(result)}`)
	end

	return false, `{label}: ล้มครบ {attempts} ครั้ง ({tostring(lastError)})`, attempts
end

--------------------------------------------------------------------------------
-- โหลด
--------------------------------------------------------------------------------

-- คืน (data, err, isNew)
--   data ไม่ nil  → โหลดสำเร็จ ตั้ง session lock ให้แล้ว
--   data เป็น nil → err คือข้อความที่เอาไปเตะผู้เล่นได้เลย
--
-- ⚠️ ใช้ UpdateAsync ไม่ใช่ GetAsync เพราะต้อง "อ่านแล้วตั้ง lock" ให้เป็นก้าวเดียว
-- ถ้าอ่านก่อนแล้วค่อยเขียน lock ทีหลัง จะมีช่องให้สองเซิร์ฟเวอร์อ่านเจอ "ไม่มี lock" พร้อมกัน
function DataService.loadAsync(userId: number): (Data?, string?, boolean)
	local key = DataService.keyFor(userId)
	local myJobId = sessionJobId()

	local rejected: string? = nil
	local isNew = false
	local loaded: Data? = nil

	local ok, err = DataService.retryAsync(`โหลดข้อมูลของ {userId}`, function()
		rejected = nil
		isNew = false
		loaded = nil

		store:UpdateAsync(key, function(stored: Data?): Data?
			if stored == nil then
				isNew = true
				local fresh = PlayerData.createNew()
				fresh.sessionLock = { jobId = myJobId, placeId = sessionPlaceId(), at = now() }
				loaded = fresh
				return fresh
			end

			-- ⚠️ lock ของเซิร์ฟเวอร์อื่นที่ยังไม่หมดอายุ = ห้ามแตะ
			-- คืน nil เพื่อยกเลิกการเขียนทั้งก้อน ข้อมูลเดิมไม่ถูกแตะเลย
			local lock = stored.sessionLock
			if lock and lock.jobId ~= myJobId and PlayerData.isLockActive(lock, now()) then
				rejected = LOCKED_MESSAGE
				return nil
			end

			local migrated, migrateErr = PlayerData.migrate(stored)
			if not migrated then
				-- ⚠️ ข้อมูลใหม่กว่าโค้ด = ห้ามเซฟทับ ยกเลิกการเขียนแล้วเตะออก
				rejected = `{FUTURE_SCHEMA_MESSAGE} ({migrateErr})`
				return nil
			end

			local data = PlayerData.normalize(migrated)
			data.sessionLock = { jobId = myJobId, placeId = sessionPlaceId(), at = now() }
			-- ⚠️ เก็บผลจากในตัว transform เลย **ห้ามยิง GetAsync ตามไปอ่านซ้ำ**
			-- อ่านซ้ำ = เปลือง request หนึ่งครั้งต่อการเข้าเกมหนึ่งครั้ง
			-- และเปิดช่องให้เซิร์ฟเวอร์อื่นเขียนแทรกระหว่างสองคำสั่ง แล้วเราอ่านได้ของคนอื่น
			loaded = data
			return data
		end)
	end)

	if rejected then
		return nil, rejected, false
	end
	if not ok then
		logWarn(`[DataService] {err}`)
		return nil, LOAD_FAILED_MESSAGE, false
	end

	if loaded == nil then
		logWarn(`[DataService] UpdateAsync ของ {userId} สำเร็จแต่ไม่ได้ข้อมูลกลับมา`)
		return nil, LOAD_FAILED_MESSAGE, false
	end

	cache[userId] = loaded
	print(`[DataService] โหลด {userId} สำเร็จ · {if isNew then "ผู้เล่นใหม่" else "ผู้เล่นเก่า"} · {describe(loaded)}`)
	return loaded, nil, isNew
end

--------------------------------------------------------------------------------
-- เซฟ
--------------------------------------------------------------------------------

-- `releaseLock = true` ตอนผู้เล่นออกจากเกม — ปลด lock เพื่อให้เข้าเซิร์ฟเวอร์อื่นได้ทันที
-- ⚠️ **ต้องปลดเสมอ** ไม่งั้นผู้เล่นเข้าเกมใหม่ไม่ได้จนกว่า lock จะหมดอายุ 5 นาที
function DataService.saveAsync(userId: number, releaseLock: boolean, deadline: number?): (boolean, string?)
	local data = cache[userId]
	if not data then
		return false, "ไม่มีข้อมูลในหน่วยความจำ (โหลดไม่สำเร็จตั้งแต่แรก?)"
	end

	-- ⚠️⚠️ รอบเซฟซ้อนกัน — จุดนี้เคยทำข้อมูลผู้เล่นหายจริงมาแล้ว
	--
	-- เดิมเขียนว่า "ถ้ากำลังเซฟอยู่ ก็ไม่ต้องทำอะไร" ซึ่งถูกสำหรับ autosave
	-- แต่ **ผิดมหันต์สำหรับเซฟรอบสุดท้าย** ตอนผู้เล่นออกจากเกม:
	--
	--   t+60.0  autosave เริ่ม · UpdateAsync ค้างระหว่างยิงข้ามเน็ต
	--   t+60.2  transform ทำงาน → Roblox ตรึง snapshot ไว้ ณ วินาทีนั้น (ยังไม่ฟัก)
	--   t+60.5  ไข่ฟักเสร็จ → แม่เข้าคอก (อยู่ในหน่วยความจำเท่านั้น)
	--   t+60.6  ผู้เล่นกด Leave → เซฟรอบสุดท้ายเห็น saving[] เป็น true → **ไม่ทำอะไรเลย**
	--   t+60.7  forget() ทิ้งข้อมูลในหน่วยความจำ
	--   t+60.8  autosave เขียน snapshot เก่าลง DataStore
	--   → แม่หายไป ไข่กลับมาค้างในสวนฟัก และ session lock ไม่ถูกปลด
	--
	-- เซฟรอบสุดท้ายจึงต้อง **รอ** รอบก่อนหน้าให้จบ แล้วค่อยเขียนทับด้วยของจริง
	-- ส่วน autosave ข้ามได้ตามเดิม เพราะรอบที่ค้างอยู่ก็เขียนข้อมูลชุดเดียวกัน
	local isFinalSave = releaseLock
	if saving[userId] then
		if not isFinalSave then
			return false, "กำลังเซฟอยู่แล้ว"
		end

		local waited = 0
		while saving[userId] do
			if deadline and now() >= deadline then
				logWarn(`[DataService] {userId} หมดเวลารอรอบเซฟก่อนหน้าตอนปิดเซิร์ฟ`)
				return false, "หมดเวลารอรอบเซฟก่อนหน้า"
			end
			if waited >= DS.SAVE_WAIT_LIMIT then
				-- ⚠️ ค้างนานขนาดนี้แปลว่า thread ที่เซฟอยู่ตายกลางคัน
				-- ยอมเขียนทับดีกว่าปล่อยให้ข้อมูลหาย — ของในมือใหม่กว่าเสมอ
				logWarn(`[DataService] {userId} รอรอบเซฟก่อนหน้าเกิน {DS.SAVE_WAIT_LIMIT} วิ — เซฟทับเลย`)
				break
			end
			sleep(DS.SAVE_WAIT_STEP)
			waited += DS.SAVE_WAIT_STEP
		end
	end
	saving[userId] = true

	local key = DataService.keyFor(userId)
	local myJobId = sessionJobId()

	data.lastSaveAt = now()
	data.stats.lastSeenAt = now()

	-- ⚠️ ตรวจกฎ encode ก่อนยิงเข้า DataStore เสมอ
	-- ผิดกฎแล้วปล่อยผ่าน = ข้อมูลกลับมาไม่เหมือนเดิมโดยไม่มี error ให้จับ
	local cleanOk, cleanErr = pcall(PlayerData.sanitizeForSave, data)
	if not cleanOk then
		saving[userId] = nil
		logWarn(`[DataService] ข้อมูลของ {userId} ผิดกฎ encode ไม่เซฟ: {tostring(cleanErr)}`)
		return false, tostring(cleanErr)
	end

	local stolen = false
	local ok, err = DataService.retryAsync(`เซฟข้อมูลของ {userId}`, function()
		stolen = false
		store:UpdateAsync(key, function(stored: Data?): Data?
			-- ⚠️ เซิร์ฟเวอร์อื่นแย่ง lock ไปแล้ว (เกิดได้ถ้าเราค้างนานจน lock หมดอายุ)
			-- เขียนทับตอนนี้ = ทับงานที่เขาทำอยู่ ต้องยอมทิ้งของเราแทน
			if stored and stored.sessionLock and stored.sessionLock.jobId ~= myJobId then
				if PlayerData.isLockActive(stored.sessionLock, now()) then
					stolen = true
					return nil
				end
			end

			if releaseLock then
				data.sessionLock = nil
			else
				data.sessionLock = { jobId = myJobId, placeId = sessionPlaceId(), at = now() }
			end
			return data
		end)
	end, deadline)

	saving[userId] = nil

	if stolen then
		logWarn(`[DataService] {userId} ถูกเซิร์ฟเวอร์อื่นถือ lock ไปแล้ว ไม่เซฟทับ`)
		return false, "เซิร์ฟเวอร์อื่นถือข้อมูลอยู่"
	end
	if not ok then
		logWarn(`[DataService] {err}`)
		return false, tostring(err)
	end

	print(
		`[DataService] เซฟ {userId} สำเร็จ · {if releaseLock then "รอบสุดท้าย (ปลด lock)" else "autosave"} · `
			.. describe(data)
	)

	if releaseLock then
		cache[userId] = nil
	end
	return true, nil
end

function DataService.forget(userId: number)
	cache[userId] = nil
	saving[userId] = nil
end

--------------------------------------------------------------------------------
-- autosave
--------------------------------------------------------------------------------

-- ⚠️ กระจายรอบเซฟของแต่ละคนไม่ให้ตรงกัน
-- 6 คนที่เข้าพร้อมกันจะเซฟพร้อมกันทุกนาทีถ้าไม่กระจาย = งบเขียนพีคเป็นก้อน
-- ใช้ (ลำดับ - 1) × STAGGER → คนแรก 0 วิ คนที่ 6 = 50 วิ ยังอยู่ในรอบ 60 วิ
function DataService.autosaveOffset(index: number): number
	return (index - 1) * DS.AUTOSAVE_STAGGER
end

function DataService.startAutosave()
	local Players = game:GetService("Players")

	task.spawn(function()
		while true do
			task.wait(DS.AUTOSAVE_INTERVAL)

			for index, player in Players:GetPlayers() do
				if cache[player.UserId] then
					task.spawn(function()
						task.wait(DataService.autosaveOffset(index))
						if cache[player.UserId] then
							DataService.saveAsync(player.UserId, false)
						end
					end)
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- ปิดเซิร์ฟเวอร์
--------------------------------------------------------------------------------

-- ⚠️ Roblox ให้เวลา 30 วินาทีแล้วปิดทิ้งไม่ว่าจะเซฟเสร็จหรือไม่
-- เซฟทุกคน **พร้อมกัน** ไม่ใช่ไล่ทีละคน — ไล่ทีละคนที่ 6 คนอาจไม่ทันคนท้าย ๆ
-- ใครบ้างที่ยังมีข้อมูลค้างและต้องเซฟก่อนเซิร์ฟปิด
--
-- ⚠️⚠️ อ่านจาก **แคช** ไม่ใช่ `Players:GetPlayers()` — นี่คือความต่างที่ทำข้อมูลหาย
-- ตอนผู้เล่นคนสุดท้ายกด Leave ลำดับเหตุการณ์คือ:
--   1. PlayerRemoving ยิง → เซฟรอบสุดท้ายเริ่ม แล้วค้างอยู่ใน UpdateAsync
--   2. Roblox เริ่มปิดเซิร์ฟ → BindToClose ยิง
--   3. ถึงตอนนี้ `Players:GetPlayers()` **ว่างไปแล้ว**
-- โค้ดเดิมเจอว่างแล้ว return ทันที → เซิร์ฟตายทับเซฟที่ยังวิ่งอยู่
-- = ได้อาการเดียวกับบั๊กเซฟซ้อนเป๊ะ (ของที่ได้มาหลัง autosave รอบสุดท้ายหายหมด)
function DataService.pendingOnClose(): { number }
	local pending: { number } = {}
	for userId in cache do
		table.insert(pending, userId)
	end
	return pending
end

function DataService.saveAllOnClose()
	local deadline = now() + DS.BIND_TO_CLOSE_SECONDS

	-- ⚠️ `saveAsync` ที่ releaseLock = true จะรอรอบที่ค้างอยู่ให้จบเองแล้วเขียนทับ
	-- จึงเรียกซ้ำได้ปลอดภัย ไม่ต้องกลัวไปแย่งกับรอบที่กำลังวิ่ง
	local pending = DataService.pendingOnClose()
	if #pending == 0 then
		return
	end

	print(`[DataService] เซิร์ฟเวอร์กำลังปิด — ยังมีข้อมูลค้าง {#pending} คน`)

	local remaining = #pending
	for _, userId in pending do
		task.spawn(function()
			-- เซฟรอบสุดท้ายของเขาอาจจบไปแล้วระหว่างนี้ — แคชว่างแล้วก็ไม่ต้องทำอะไร
			if cache[userId] then
				DataService.saveAsync(userId, true, deadline)
			end
			remaining -= 1
		end)
	end

	while remaining > 0 and now() < deadline do
		task.wait(0.2)
	end

	if remaining > 0 then
		logWarn(`[DataService] ปิดเซิร์ฟเวอร์โดยที่ยังเซฟไม่เสร็จ {remaining} คน`)
	else
		print("[DataService] เซฟครบทุกคนแล้ว")
	end
end

function DataService.bindToClose()
	game:BindToClose(function()
		DataService.saveAllOnClose()
	end)
end

return DataService
