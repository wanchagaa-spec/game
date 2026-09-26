--!nocheck
-- egg-army-game :: ชุดเทสต์ของ PlayerData + DataService (Phase 2A)
--
-- ⚠️ ทำไมชุดนี้ถึงจำเป็น: ความผิดพลาดของ DataStore **ไม่มี error ให้จับ**
-- เซฟล้ม → ไม่มีใครรู้ → ผู้เล่นรู้ตัวอีกทีตอนเข้าเกมใหม่แล้วของหาย
-- และ autosave ทำงานตอนคนออกจากเกม ซึ่งเป็นจังหวะที่ไม่มีใครนั่งดู log อยู่
--
-- ทุกอย่างที่นี่รันด้วย luau CLI ไม่ต้องเปิด Studio
-- DataService รับ store ปลอม นาฬิกาปลอม และ sleep ปลอมเข้าไปได้ (injectForTests)
--
-- ⚠️ --!nocheck โดยตั้งใจ เหมือน config.spec — store ปลอมไม่ตรงกับ type ของ DataStore จริง

local PlayerData = require("../src/shared/PlayerData")
local DataService = require("../src/server/DataService")
local Json = require("./jsonlite")

return function(t, Config)
	local check, near = t.check, t.near

	----------------------------------------------------------------------------
	-- กระเป๋าไข่โครงใหม่
	----------------------------------------------------------------------------
	-- ⚠️ โครงเดิมเป็นอาเรย์ยาวคงที่ที่เติม false จนครบความจุ
	-- พอความจุขึ้นเป็น 10,000 แปลว่าเขียน false หมื่นตัวลง DataStore ทุกครั้งที่เซฟ
	print("── กระเป๋าไข่: เก็บเฉพาะฟองที่มีจริง + id ประจำฟอง ──")

	local bag = { nextEggId = 1, items = {} }

	local a = PlayerData.addHeldEgg(bag, "egg_stage1", 320)
	local b = PlayerData.addHeldEgg(bag, "egg_stage3", 48000)
	local c = PlayerData.addHeldEgg(bag, "egg_stage1", 150)

	check("ไข่ฟองแรกได้ id 1", a.id, 1)
	check("ไข่ฟองที่สองได้ id 2", b.id, 2)
	check("ไข่ฟองที่สามได้ id 3", c.id, 3)
	check("ตัวนับเดินไปที่ 4", bag.nextEggId, 4)
	check("มีไข่ 3 ฟอง", #bag.items, 3)
	check("น้ำหนักติดมากับฟอง", b.weight, 48000)
	check("ชนิดไข่ติดมากับฟอง", b.eggId, "egg_stage3")

	local index, found = PlayerData.findHeldEgg(bag, 2)
	check("หาเจอด้วย id", found.eggId, "egg_stage3")
	check("บอกตำแหน่งปัจจุบันด้วย", index, 2)
	check("หา id ที่ไม่มี = nil", (PlayerData.findHeldEgg(bag, 999)), nil)

	----------------------------------------------------------------------------
	-- ⚠️ เคสที่โครงเดิมพัง: ไข่ฟักเสร็จคั่นจังหวะตอนผู้เล่นกำลังกดวาง
	----------------------------------------------------------------------------
	-- โครงเดิม client ส่ง "ตำแหน่งในอาเรย์" มา พอฟองที่อยู่ก่อนหน้าถูกเอาออก
	-- ทั้งแถวเลื่อนขึ้นหนึ่งช่อง → ตำแหน่งที่ client เห็นตอนกด ชี้ไปที่ไข่คนละฟอง
	-- สวนฟัก 50 ช่องทำให้มีไข่ฟักเสร็จบ่อยมาก นี่ไม่ใช่เคสทฤษฎี
	print("── race condition: ลบฟองกลางแล้วตำแหน่งเลื่อน ──")

	-- client เห็น [1]=A(id1) [2]=B(id2) [3]=C(id3) แล้วตั้งใจจะวาง C
	local targetId = c.id
	local positionClientSaw = 3

	-- ระหว่างนั้น A ถูกเอาออก (ฟักเสร็จ/ถูกวางไปก่อน)
	PlayerData.removeHeldEgg(bag, a.id)

	check("เหลือ 2 ฟอง", #bag.items, 2)
	check("ตำแหน่งที่ client เห็นตอนนี้ว่างแล้ว", bag.items[positionClientSaw], nil)

	-- โครงใหม่: อ้างด้วย id → ยังได้ฟองที่ตั้งใจเสมอ
	local _, stillC = PlayerData.findHeldEgg(bag, targetId)
	check("อ้างด้วย id ยังได้ฟองเดิม", stillC.id, targetId)
	check("และเป็นฟองที่น้ำหนักถูกต้อง", stillC.weight, 150)

	-- ตำแหน่งของ C เลื่อนจาก 3 มาเป็น 2 จริง ๆ — นี่คือสิ่งที่เคยทำให้พัง
	local newIndex = PlayerData.findHeldEgg(bag, targetId)
	check("ตำแหน่งของมันเลื่อนจริง (3 → 2)", newIndex, 2)

	-- ⚠️ id ห้ามถูกใช้ซ้ำ แม้ฟองเดิมจะถูกลบไปแล้ว
	local d = PlayerData.addHeldEgg(bag, "egg_stage2", 700)
	check("ฟองใหม่ได้ id 4 ไม่ใช่ 1 ที่ว่างอยู่", d.id, 4)
	check("ตัวนับไม่เคยถอยหลัง", bag.nextEggId, 5)

	check("ลบ id ที่ไม่มี = nil", PlayerData.removeHeldEgg(bag, 999), nil)
	check("ลบของไม่มีแล้วจำนวนไม่เปลี่ยน", #bag.items, 3)

	-- เต็มกระเป๋าแล้วต้องเติมไม่ได้
	local full = { nextEggId = 1, items = {} }
	for _ = 1, Config.Balance.Hatchery.BAG_CAPACITY do
		PlayerData.addHeldEgg(full, "egg_stage1", 100)
	end
	check("กระเป๋าเต็มที่ความจุพอดี", #full.items, Config.Balance.Hatchery.BAG_CAPACITY)
	check("เต็มแล้วเติมไม่ได้", PlayerData.addHeldEgg(full, "egg_stage1", 100), nil)

	-- normalize ต้องดันตัวนับขึ้นถ้าข้อมูลเพี้ยนจนต่ำกว่า id ที่ใช้ไปแล้ว
	-- ⚠️ ถ้าไม่ดัน ไข่สองฟองจะได้ id เดียวกัน แล้ว findHeldEgg จะชี้ผิดฟอง
	local broken = PlayerData.createNew()
	broken.heldEggs = { nextEggId = 2, items = { { id = 9, eggId = "egg_stage1", weight = 100 } } }
	PlayerData.normalize(broken)
	check("ตัวนับถูกดันให้สูงกว่า id ที่ใช้แล้ว", broken.heldEggs.nextEggId, 10)

	----------------------------------------------------------------------------
	-- ผู้เล่นใหม่
	----------------------------------------------------------------------------
	print("── ผู้เล่นใหม่ ──")
	local fresh = PlayerData.createNew()
	check("schemaVersion ตรงกับ Config", fresh.schemaVersion, Config.SCHEMA_VERSION)
	check("เงินเริ่มต้นมาจาก Config", fresh.currency.coins, Config.Balance.NewPlayer.coins)
	-- ⚠️ ต้องเป็น 1 ไม่ใช่ 0 — ถ้าเป็น 0 เพดาน upgrade damage จะเป็น 0 แล้วผู้เล่นใหม่ตันทันที
	check("wallProgress เริ่มที่ 1 ไม่ใช่ 0", fresh.wallProgress, 1)
	check("ซื้อ damage ได้ตั้งแต่เข้าเกม", Config.getMaxDamageLevel(fresh.wallProgress) > 0, true)
	check("คอกเริ่มที่ Lv1", fresh.penLevel, 1)
	check("สวนฟักยาวเท่า MAX_SLOTS", #fresh.hatching, Config.Balance.Hatchery.MAX_SLOTS)
	check("ทุกช่องสวนฟักเป็น false", fresh.hatching[1], false)
	check("stageProgress ยาว 9 ช่อง", #fresh.stageProgress, Config.Balance.Stage.COUNT)
	check("กระเป๋าไข่เริ่มว่าง", #fresh.heldEggs.items, 0)
	check("ตัวนับไข่เริ่มที่ 1", fresh.heldEggs.nextEggId, 1)

	----------------------------------------------------------------------------
	-- กฎ encode (docs/data-schema.md §9.3)
	----------------------------------------------------------------------------
	-- ⚠️ ยามชุดนี้ต้อง "จับได้จริง" ไม่ใช่ผ่านเพราะไม่มีอะไรให้จับ
	print("── กฎ encode: ยามต้องจับของที่เซฟไม่ได้ ──")

	local function saveRejects(mutate): boolean
		local data = PlayerData.createNew()
		mutate(data)
		return not (pcall(PlayerData.sanitizeForSave, data))
	end

	check("ข้อมูลผู้เล่นใหม่ผ่านกฎ", (pcall(PlayerData.sanitizeForSave, PlayerData.createNew())), true)
	check("อาเรย์มีรู → ล้ม", saveRejects(function(d) d.stageProgress = { [2] = { defendersRemaining = 1, wallHpRemaining = 1 } } end), true)
	check("ผสม key ตัวเลขกับ string → ล้ม", saveRejects(function(d) d.children = { "a", key = 1 } end), true)
	check("NaN → ล้ม", saveRejects(function(d) d.currency.coins = 0 / 0 end), true)
	check("inf → ล้ม", saveRejects(function(d) d.currency.coins = math.huge end), true)
	check("จำนวนเต็มเกิน 2^53 → ล้ม", saveRejects(function(d) d.currency.coins = 2 ^ 54 end), true)
	check("function หลุดเข้ามา → ล้ม", saveRejects(function(d) d.stats.oops = function() end end), true)
	check("ตารางอ้างวนกลับตัวเอง → ล้ม", saveRejects(function(d) d.stats.loop = d.stats end), true)

	----------------------------------------------------------------------------
	-- roundtrip
	----------------------------------------------------------------------------
	-- ⚠️ encode ด้วยโค้ด production · decode ด้วยตัวแยกในเทสต์
	-- ถ้าใช้ของชุดเดียวกันสองทาง ความผิดที่หักล้างกันเองจะมองไม่เห็น
	print("── roundtrip: encode → decode ได้ค่าเดิม ──")

	local sample = PlayerData.createNew()
	sample.currency.coins = 123456
	sample.nextUid = 7
	sample.children[Config.makeStackKey("wukong", 1500, { "gold", "silver" })] = 482000
	sample.mothersInPen[1] = {
		uid = Config.makeUid(1234567, 1),
		charId = "wukong",
		weight = 1500,
		statuses = { "gold" },
		lastProducedAt = 1757740000,
		obtainedAt = 1757700000,
		locked = false,
	}
	sample.hatching[3] = { eggId = "egg_stage3", weight = 48000, charId = "wukong", startedAt = 100, hatchAt = 190 }
	-- ⚠️ ช่องที่ไม่มี charId จำลองข้อมูลเก่าจากก่อนเพิ่มฟิลด์นี้ (Phase: เวลาฟักตามน้ำหนัก+คลาส)
	-- ต้อง roundtrip ได้โดยไม่พัง (EggService.hatch() มี fallback สุ่มใหม่ให้กรณีนี้)
	sample.hatching[5] = { eggId = "egg_stage1", weight = 500, startedAt = 50, hatchAt = 110 }
	sample.stageProgress[4] = { defendersRemaining = 4500, wallHpRemaining = 50000 }
	PlayerData.addHeldEgg(sample.heldEggs, "egg_stage1", 320)
	PlayerData.addHeldEgg(sample.heldEggs, "egg_stage9", 100000000)

	local back = Json.decode(PlayerData.encode(sample))

	check("เงินกลับมาครบ", back.currency.coins, 123456)
	check("nextUid กลับมาครบ", back.nextUid, 7)
	check("uid ยังเป็น string", type(back.mothersInPen[1].uid), "string")
	check("uid ตรงตัว", back.mothersInPen[1].uid, "1234567-1")
	check("น้ำหนักแม่ตรงตัว", back.mothersInPen[1].weight, 1500)
	check("สถานะของแม่กลับมาครบ", back.mothersInPen[1].statuses[1], "gold")
	check("stack key ที่มี | และ , อ่านกลับได้", back.children["wukong|1500|gold,silver"], 482000)
	-- ⚠️ ช่องว่างเป็น false ไม่ใช่ nil จึงยังนับความยาวได้ถูกหลัง decode
	check("สวนฟักยังยาวเท่าเดิม", #back.hatching, Config.Balance.Hatchery.MAX_SLOTS)
	check("ช่องว่างยังเป็น false", back.hatching[1], false)
	check("ไข่ที่ฟักอยู่กลับมาถูกช่อง", back.hatching[3].eggId, "egg_stage3")
	check("น้ำหนักไข่ที่ฟังอยู่ตรงตัว", back.hatching[3].weight, 48000)
	check("charId ที่สุ่มไว้ตอนวางไข่กลับมาครบ", back.hatching[3].charId, "wukong")
	check("ช่องแบบเก่าที่ไม่มี charId ก็ roundtrip ได้ปกติ (ไม่พัง)", back.hatching[5].eggId, "egg_stage1")
	check("ช่องแบบเก่า charId ยังเป็น nil เหมือนเดิม (ไม่ถูกเติมค่าแปลก ๆ ให้)", back.hatching[5].charId, nil)
	check("stageProgress กลับมาถูกช่อง", back.stageProgress[4].defendersRemaining, 4500)
	check("กระเป๋าไข่กลับมาครบจำนวน", #back.heldEggs.items, 2)
	check("id ของไข่กลับมาครบ", back.heldEggs.items[2].id, 2)
	check("น้ำหนักไข่ tier สูงสุดไม่ถูกปัด", back.heldEggs.items[2].weight, 100000000)
	check("ตัวนับไข่กลับมาครบ", back.heldEggs.nextEggId, 3)

	----------------------------------------------------------------------------
	-- ขนาดข้อมูล
	----------------------------------------------------------------------------
	print("── ขนาดข้อมูลตอนเต็มทุกเพดาน ──")

	local worst = PlayerData.buildWorstCase()
	local bytes = PlayerData.estimateBytes(worst)
	local limit = Config.DataStore.MAX_PLAYER_DATA_BYTES

	print(`   เต็มทุกเพดาน = {bytes} ไบต์ ({string.format("%.2f", bytes / 1048576)} MB) · `
		.. `เพดานที่ตั้งไว้ {string.format("%.0f", limit / 1048576)} MB · ลิมิตจริงของ Roblox 4 MB`)
	print(`   ผู้เล่นใหม่ = {PlayerData.estimateBytes(PlayerData.createNew())} ไบต์`)

	check("ข้อมูลเต็มเพดานยังต่ำกว่าเพดานที่ตั้งไว้", bytes < limit, true)
	check("และต่ำกว่าลิมิตจริงของ Roblox", bytes < 4 * 1024 * 1024, true)
	check("ข้อมูลเต็มเพดานยังผ่านกฎ encode", (pcall(PlayerData.sanitizeForSave, worst)), true)
	check("PlayerData.validate() ผ่าน", (pcall(PlayerData.validate)), true)

	-- ⚠️ ยามต้องจับได้จริง: ดันเพดานกระเป๋าไข่ขึ้นจนข้อมูลทะลุ แล้วยามต้องล้ม
	-- 60,000 ฟองพอให้ทะลุ 3 MB (ไข่ฟองละ ~55 ไบต์) และสร้างเสร็จในเสี้ยววินาที
	-- ⚠️ อย่าตั้งให้ใหญ่เกินจำเป็น — เคยตั้ง 5,000,000 แล้วชุดเทสต์ทั้งชุดช้าจาก 1 วิ เป็น 2 นาที
	local savedCapacity = Config.Balance.Hatchery.BAG_CAPACITY
	Config.Balance.Hatchery.BAG_CAPACITY = 60000
	check("เพดานที่ทำให้ข้อมูลทะลุ → validate ล้ม", (pcall(PlayerData.validate)), false)
	Config.Balance.Hatchery.BAG_CAPACITY = savedCapacity
	check("คืนค่าแล้วผ่านเหมือนเดิม", (pcall(PlayerData.validate)), true)

	----------------------------------------------------------------------------
	-- session lock
	----------------------------------------------------------------------------
	print("── session lock ──")

	local ttl = Config.DataStore.SESSION_LOCK_SECONDS
	check("ไม่มี lock = ว่าง", PlayerData.isLockActive(nil, 1000), false)
	check("lock เพิ่งตั้ง = ยังถือ", PlayerData.isLockActive({ jobId = "x", placeId = 1, at = 1000 }, 1000), true)
	check("lock อายุน้อยกว่าเพดาน = ยังถือ", PlayerData.isLockActive({ jobId = "x", placeId = 1, at = 1000 }, 1000 + ttl - 1), true)
	check("lock หมดอายุพอดี = ปล่อย", PlayerData.isLockActive({ jobId = "x", placeId = 1, at = 1000 }, 1000 + ttl), false)
	-- ⚠️ นาฬิกาของสองเซิร์ฟเวอร์ไม่ตรงกันเป๊ะ lock ที่ดูมาจากอนาคตต้องนับว่ายังถืออยู่
	check("lock จากอนาคต (นาฬิกาเหลื่อม) = ยังถือ", PlayerData.isLockActive({ jobId = "x", placeId = 1, at = 2000 }, 1000), true)

	----------------------------------------------------------------------------
	-- migration
	----------------------------------------------------------------------------
	print("── migration ──")

	local current = PlayerData.createNew()
	check("เวอร์ชันปัจจุบันผ่านฉลุย", (select(1, PlayerData.migrate(current))) ~= nil, true)

	-- ⚠️ ข้อมูลใหม่กว่าโค้ด = เซิร์ฟเวอร์ถูก rollback · เซฟทับเมื่อไหร่ของหายถาวร
	local fromFuture = PlayerData.createNew()
	fromFuture.schemaVersion = Config.SCHEMA_VERSION + 1
	local migrated, err = PlayerData.migrate(fromFuture)
	check("ข้อมูลจากเวอร์ชันใหม่กว่า → ปฏิเสธ", migrated, nil)
	check("และบอกเหตุผลมาด้วย", type(err), "string")

	-- ข้อมูลยุคก่อนมี schemaVersion ให้ถือว่าเป็น v1
	local ancient = PlayerData.createNew()
	ancient.schemaVersion = nil
	check("ไม่มี schemaVersion → ถือว่า v1", (select(1, PlayerData.migrate(ancient))) ~= nil, true)

	-- v1 → v2 (Phase 3C-1): เซฟยุค v1 ไม่มี battleRoster เลย ต้องได้ roster ว่างหลัง migrate
	-- ⚠️ นี่คือ migration แรกของโปรเจกต์ — พลาด = โหลดไม่ขึ้น = ผู้เล่นโดนเตะออก
	local savedV1 = PlayerData.createNew()
	savedV1.schemaVersion = 1
	savedV1.battleRoster = nil
	table.insert(savedV1.mothersInBag, {
		uid = "777-1", charId = "monkey", weight = 500, statuses = {}, obtainedAt = 0, locked = false,
	})
	local v2, v2Err = PlayerData.migrate(savedV1)
	check("v1 → v2 สำเร็จ", v2Err, nil)
	check("  schemaVersion ขึ้นเป็นปัจจุบัน", v2 and v2.schemaVersion, Config.SCHEMA_VERSION)
	check("  ได้ battleRoster เป็นตาราง", v2 and type(v2.battleRoster), "table")
	check("  battleRoster เริ่มว่าง", v2 and #v2.battleRoster, 0)
	check("  แม่ในกระเป๋าเดิมไม่ถูกแตะ", v2 and v2.mothersInBag[1].uid, "777-1")

	-- idempotent: ถ้ามี roster อยู่แล้ว (เช่น migrate ซ้ำ) ห้ามทับของเดิม
	local alreadyHasRoster = PlayerData.createNew()
	alreadyHasRoster.schemaVersion = 1
	alreadyHasRoster.battleRoster = { { uid = "777-2", charId = "monkey", weight = 100, statuses = {}, obtainedAt = 0, locked = false } }
	local kept = PlayerData.migrate(alreadyHasRoster)
	check("migration ไม่ทับ roster ที่มีอยู่แล้ว", kept and #kept.battleRoster, 1)
	check("v1 ไล่ถึงปัจจุบันได้ธงรางวัลผ่านด่านด้วย (ผ่าน v2 → v3)", v2 and #v2.stageClearBonusGranted, 9)

	-- v2 → v3 (Phase 4A): เซฟยุค v2 ไม่มี stageClearBonusGranted → ได้ false ทั้ง 9 ช่อง
	local savedV2 = PlayerData.createNew()
	savedV2.schemaVersion = 2
	savedV2.stageClearBonusGranted = nil
	local v3, v3Err = PlayerData.migrate(savedV2)
	check("v2 → v3 สำเร็จ", v3Err, nil)
	check("  schemaVersion = 3", v3 and v3.schemaVersion, 3)
	local allFalse = true
	for index = 1, 9 do
		if v3 and v3.stageClearBonusGranted[index] ~= false then
			allFalse = false
		end
	end
	check("  ธง 9 ช่องเป็น false ทั้งหมด", allFalse, true)

	-- idempotent: มีธงอยู่แล้ว (migrate ซ้ำ) ห้ามทับ
	local alreadyHasFlags = PlayerData.createNew()
	alreadyHasFlags.schemaVersion = 2
	alreadyHasFlags.stageClearBonusGranted[2] = true
	local keptFlags = PlayerData.migrate(alreadyHasFlags)
	check("migration ไม่ทับธงที่มีอยู่แล้ว", keptFlags and keptFlags.stageClearBonusGranted[2], true)
	check("migration v2→v3 รันซ้ำตรง ๆ ได้ผลเดิม", PlayerData.MIGRATIONS[2](keptFlags).stageClearBonusGranted[2], true)

	-- normalize เติมช่องที่ขาดให้ครบ 9 เป็น false
	local shortFlags = PlayerData.createNew()
	shortFlags.stageClearBonusGranted = { true, false }
	PlayerData.normalize(shortFlags)
	check("normalize เติมธงให้ครบ 9 ช่อง", #shortFlags.stageClearBonusGranted, 9)
	check("  ช่องที่เติมเป็น false", shortFlags.stageClearBonusGranted[9], false)
	check("  ไม่ทับช่องเดิม", shortFlags.stageClearBonusGranted[1], true)

	-- normalize ต้องเติมฟิลด์ที่ขาดโดยไม่ทับของเดิม
	local partial = PlayerData.createNew()
	partial.currency.coins = 999
	partial.stats = nil
	partial.summonEnabled = nil
	PlayerData.normalize(partial)
	check("เติมฟิลด์ที่ขาดให้", type(partial.stats), "table")
	check("เติม summonEnabled ให้", partial.summonEnabled, true)
	check("ไม่ทับค่าที่ผู้เล่นมีอยู่", partial.currency.coins, 999)

	----------------------------------------------------------------------------
	-- DataService: retry
	----------------------------------------------------------------------------
	print("── retry: ล้มแล้วลองใหม่ ──")

	local slept = {}
	local clock = 1000
	local function makeStore()
		local store = { data = {}, updateCalls = 0, failUpdates = 0 }
		function store.UpdateAsync(_self, key, transform)
			store.updateCalls += 1
			if store.failUpdates > 0 then
				store.failUpdates -= 1
				error("DataStore ล่ม (จำลอง)", 0)
			end
			local result = transform(store.data[key])
			if result ~= nil then
				store.data[key] = result
			end
			return result
		end
		function store.GetAsync(_self, key)
			return store.data[key]
		end
		return store
	end

	local store = makeStore()
	DataService.injectForTests({
		store = store,
		sleep = function(seconds) table.insert(slept, seconds) end,
		now = function() return clock end,
		jobId = function() return "server-A" end,
	})

	-- ล้ม 2 ครั้งแล้วสำเร็จครั้งที่ 3
	local tries = 0
	local ok, result, attempts = DataService.retryAsync("ทดสอบ", function()
		tries += 1
		if tries < 3 then
			error("ล้มจำลอง", 0)
		end
	end)
	check("ล้ม 2 ครั้ง แล้วสำเร็จครั้งที่ 3", ok, true)
	check("ลองไป 3 ครั้ง", attempts, 3)
	check("หน่วง 2 รอบ", #slept, 2)
	-- ⚠️ ครั้งแรกต้องยิงทันที ไม่หน่วง ไม่งั้นทุกคนรอฟรี ๆ ทั้งที่ปกติสำเร็จตั้งแต่ครั้งแรก
	check("หน่วงครั้งแรก = RETRY_BASE_DELAY", slept[1], Config.DataStore.RETRY_BASE_DELAY)
	check("หน่วงครั้งถัดไปคูณสอง", slept[2], Config.DataStore.RETRY_BASE_DELAY * 2)

	-- ล้มครบทุกครั้ง → คืน false ให้ระดับบนจัดการ (ไม่ throw ออกไปเอง)
	slept = {}
	local failOk, failErr, failAttempts = DataService.retryAsync("ทดสอบล้มหมด", function()
		error("ล้มจำลอง", 0)
	end)
	check("ล้มครบ 3 ครั้ง → ไม่สำเร็จ", failOk, false)
	check("ลองครบตามที่ตั้งไว้", failAttempts, Config.DataStore.RETRY_COUNT)
	check("คืนข้อความบอกสาเหตุ", type(failErr), "string")

	-- ⚠️ deadline: ตอน BindToClose มีงบแค่ 30 วินาที ห้ามเริ่มรอบที่รอไม่ทัน
	slept = {}
	local deadlineOk = DataService.retryAsync("ทดสอบ deadline", function()
		error("ล้มจำลอง", 0)
	end, clock + 1)
	check("เหลือเวลาไม่พอ → ไม่เริ่มรอบถัดไป", deadlineOk, false)
	check("และไม่หน่วงเลย", #slept, 0)

	----------------------------------------------------------------------------
	-- DataService: โหลดและเซฟ
	----------------------------------------------------------------------------
	print("── โหลด/เซฟ: ผู้เล่นใหม่และผู้เล่นเก่า ──")

	store = makeStore()
	slept = {}
	DataService.injectForTests({
		store = store,
		sleep = function(seconds) table.insert(slept, seconds) end,
		now = function() return clock end,
		jobId = function() return "server-A" end,
	})

	local USER = 1234567
	local loaded, loadErr, isNew = DataService.loadAsync(USER)
	check("ผู้เล่นใหม่โหลดได้", loaded ~= nil, true)
	check("ไม่มี error", loadErr, nil)
	-- ⚠️ ธงนี้คือสิ่งเดียวที่กันไม่ให้แจกไข่เริ่มต้นซ้ำทุกล็อกอิน
	check("บอกว่าเป็นผู้เล่นใหม่", isNew, true)
	check("ตั้ง session lock ให้แล้ว", loaded.sessionLock.jobId, "server-A")
	check("เก็บเข้าแคชแล้ว", DataService.getCached(USER) ~= nil, true)

	-- แก้ข้อมูลแล้วเซฟ
	loaded.currency.coins = 777
	PlayerData.addHeldEgg(loaded.heldEggs, "egg_stage1", 4321)
	local saveOk = DataService.saveAsync(USER, true)
	check("เซฟสำเร็จ", saveOk, true)
	check("ปลดแคชหลังปลด lock", DataService.getCached(USER), nil)
	-- ⚠️ ต้องปลด lock ตอนออกเกม ไม่งั้นเข้าใหม่ไม่ได้จนกว่าจะหมดอายุ 5 นาที
	check("lock ถูกปลดแล้ว", store.data["player_" .. USER].sessionLock, nil)

	-- โหลดกลับมาต้องได้ของเดิม และต้องไม่ใช่ผู้เล่นใหม่แล้ว
	local again, _, againIsNew = DataService.loadAsync(USER)
	check("โหลดกลับมาได้", again ~= nil, true)
	check("ไม่ใช่ผู้เล่นใหม่แล้ว", againIsNew, false)
	check("เงินยังอยู่", again.currency.coins, 777)
	check("ไข่ยังอยู่", #again.heldEggs.items, 1)
	check("น้ำหนักไข่ยังตรง", again.heldEggs.items[1].weight, 4321)
	check("id ไข่ยังตรง", again.heldEggs.items[1].id, 1)

	----------------------------------------------------------------------------
	-- DataService: session lock ของเซิร์ฟเวอร์อื่น
	----------------------------------------------------------------------------
	print("── session lock: เซิร์ฟเวอร์อื่นถืออยู่ ──")

	-- ตอนนี้ server-A ถือ lock อยู่ (เพิ่งโหลด) · ให้ server-B ลองโหลดบ้าง
	DataService.injectForTests({
		store = store,
		sleep = function(seconds) table.insert(slept, seconds) end,
		now = function() return clock end,
		jobId = function() return "server-B" end,
	})

	local blocked, blockedErr = DataService.loadAsync(USER)
	check("lock ยังสด → ปฏิเสธการโหลด", blocked, nil)
	check("บอกผู้เล่นว่าใช้งานอยู่ที่อื่น", blockedErr, DataService.LOCKED_MESSAGE)
	-- ⚠️ ข้อสำคัญ: ปฏิเสธแล้วต้อง **ไม่แตะข้อมูลเดิมเลย**
	check("ข้อมูลเดิมไม่ถูกแตะ", store.data["player_" .. USER].currency.coins, 777)
	check("lock ยังเป็นของ server-A", store.data["player_" .. USER].sessionLock.jobId, "server-A")

	-- เลยเวลาหมดอายุแล้ว server-B ต้องเข้าได้ (เซิร์ฟเวอร์เดิมดับไปจริง)
	clock += Config.DataStore.SESSION_LOCK_SECONDS + 1
	local takeover, takeoverErr = DataService.loadAsync(USER)
	check("lock หมดอายุ → เข้าได้", takeover ~= nil, true)
	check("ไม่มี error", takeoverErr, nil)
	check("lock เปลี่ยนมือเป็น server-B", store.data["player_" .. USER].sessionLock.jobId, "server-B")
	check("ข้อมูลเดิมยังอยู่ครบ", takeover.currency.coins, 777)

	----------------------------------------------------------------------------
	-- DataService: ข้อมูลจากเวอร์ชันใหม่กว่า
	----------------------------------------------------------------------------
	print("── ข้อมูลจากเวอร์ชันใหม่กว่า: ห้ามเซฟทับ ──")

	store.data["player_9999"] = PlayerData.createNew()
	store.data["player_9999"].schemaVersion = Config.SCHEMA_VERSION + 5
	store.data["player_9999"].currency.coins = 424242

	local future, futureErr = DataService.loadAsync(9999)
	check("ปฏิเสธการโหลด", future, nil)
	check("บอกเหตุผลว่าเป็นข้อมูลเวอร์ชันใหม่กว่า", futureErr ~= nil and futureErr:find("ใหม่กว่า") ~= nil, true)
	check("ไม่เขียนทับข้อมูลเลย", store.data["player_9999"].currency.coins, 424242)
	check("เวอร์ชันของข้อมูลไม่ถูกแตะ", store.data["player_9999"].schemaVersion, Config.SCHEMA_VERSION + 5)

	----------------------------------------------------------------------------
	-- DataService: โหลดล้มจริง ๆ
	----------------------------------------------------------------------------
	print("── โหลดล้มครบทุกครั้ง ──")

	store.failUpdates = Config.DataStore.RETRY_COUNT
	local deadLoad, deadErr = DataService.loadAsync(555)
	check("โหลดไม่ได้ → คืน nil", deadLoad, nil)
	-- ⚠️ ข้อความนี้ต้องบอกผู้เล่นว่าข้อมูลปลอดภัย ไม่งั้นเขาจะคิดว่าของหายแล้วเลิกเล่น
	check("ใช้ข้อความมาตรฐาน", deadErr, DataService.LOAD_FAILED_MESSAGE)
	check("ไม่มีอะไรเข้าแคช", DataService.getCached(555), nil)
	-- ⚠️ ไม่มีข้อมูลในแคช = เซฟไม่ได้ (กันเขียนข้อมูลเปล่าทับของจริง)
	check("เซฟไม่ได้เพราะไม่มีข้อมูลในมือ", (DataService.saveAsync(555, true)), false)

	----------------------------------------------------------------------------
	-- DataService: เซฟแล้วถูกแย่ง lock
	----------------------------------------------------------------------------
	print("── เซฟตอนที่เซิร์ฟเวอร์อื่นแย่ง lock ไปแล้ว ──")

	store.failUpdates = 0
	local STOLEN = 777777
	local mine = DataService.loadAsync(STOLEN)
	check("โหลดได้ก่อน", mine ~= nil, true)
	mine.currency.coins = 111

	-- เซิร์ฟเวอร์อื่นแย่ง lock ไประหว่างที่เราถือข้อมูลอยู่
	store.data["player_" .. STOLEN].sessionLock = { jobId = "server-C", placeId = 1, at = clock }
	store.data["player_" .. STOLEN].currency.coins = 999

	local stolenOk, stolenErr = DataService.saveAsync(STOLEN, true)
	check("ไม่เซฟทับงานของเซิร์ฟเวอร์อื่น", stolenOk, false)
	check("บอกเหตุผล", type(stolenErr), "string")
	check("ข้อมูลของเซิร์ฟเวอร์อื่นไม่ถูกแตะ", store.data["player_" .. STOLEN].currency.coins, 999)

	----------------------------------------------------------------------------
	-- การกระจายรอบ autosave
	----------------------------------------------------------------------------
	print("── autosave stagger ──")

	local stagger = Config.DataStore.AUTOSAVE_STAGGER
	check("คนแรกไม่ถูกเลื่อน", DataService.autosaveOffset(1), 0)
	check("คนที่สองเลื่อนหนึ่งช่วง", DataService.autosaveOffset(2), stagger)
	-- ⚠️ คนสุดท้ายต้องยังอยู่ในรอบเดียวกัน ไม่งั้นเขาจะเซฟห่างกว่าคนอื่นหนึ่งรอบเต็มตลอดไป
	local lastOffset = DataService.autosaveOffset(Config.World.MAX_PENS)
	check("คนสุดท้ายยังอยู่ในรอบเดียวกัน", lastOffset < Config.DataStore.AUTOSAVE_INTERVAL, true)
	print(`   คนที่ 1 เลื่อน 0 วิ · คนที่ {Config.World.MAX_PENS} เลื่อน {lastOffset} วิ · รอบละ {Config.DataStore.AUTOSAVE_INTERVAL} วิ`)

	check("key ของ DataStore ไม่ยาวเกิน 50 ตัวอักษร", #DataService.keyFor(99999999999999) <= 50, true)

	----------------------------------------------------------------------------
	-- 🔴 บั๊กที่เคยทำข้อมูลผู้เล่นหายจริง: ฟักเสร็จแล้วแม่หาย ไข่กลับมาค้าง
	----------------------------------------------------------------------------
	-- อาการที่เจอในเกมจริง (แอป Roblox ไม่ใช่ Studio):
	--   ฟักไข่ได้แม่ → เห็นแม่ในคอกชัด ๆ → รอเกิน 1 นาที → ออกจากเกม → เข้าใหม่
	--   → แม่หายไป มีไข่ **น้ำหนักเท่าเดิมเป๊ะ** กลับมาค้างอยู่ในสวนฟักแทน
	--
	-- สาเหตุ: `saveAsync` เคยตอบว่า "กำลังเซฟอยู่แล้ว" แล้วไม่ทำอะไรเลย
	-- ซึ่งถูกสำหรับ autosave แต่ผิดมหันต์สำหรับเซฟรอบสุดท้ายตอนผู้เล่นออกจากเกม
	--
	-- ⚠️ เทสต์นี้ต้องใช้ store ที่ **ค้างได้** เพราะบั๊กอยู่ที่จังหวะล้วน ๆ
	-- store แบบทำงานจบในบรรทัดเดียว (ที่ใช้ในเทสต์ข้างบน) จับบั๊กนี้ไม่ได้เลย
	print("── บั๊กเซฟซ้อน: ฟักเสร็จตอน autosave ค้าง แล้วออกจากเกม ──")

	local function deepCopy(value)
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for key, child in value do
			out[key] = deepCopy(child)
		end
		return out
	end

	-- UpdateAsync ของ Roblox ค้างสองช่วง: ดึงค่าปัจจุบัน แล้วค่อยเขียนกลับ
	-- ⚠️ Roblox แปลงค่าที่ transform คืนมาเป็น JSON **ทันทีที่ transform จบ**
	-- = snapshot ถูกตรึงไว้ตรงนั้น สิ่งที่แก้หลังจากนั้นไม่เข้าไปในรอบนี้แล้ว
	local pending: thread? = nil
	local slowStore = { data = {} }
	function slowStore.UpdateAsync(_self, key, transform)
		pending = coroutine.running()
		coroutine.yield() -- ช่วงดึงค่าปัจจุบัน
		local result = transform(slowStore.data[key])
		local frozen = if result ~= nil then deepCopy(result) else nil
		coroutine.yield() -- ช่วงเขียนกลับ
		if frozen ~= nil then
			slowStore.data[key] = frozen
		end
		return result
	end
	function slowStore.GetAsync(_self, key)
		return slowStore.data[key]
	end

	local slowClock = 2000000
	DataService.injectForTests({
		store = slowStore,
		-- `task.wait` จริงคืนคิวให้ thread อื่นเดินต่อ — จำลองด้วยการปลุกรอบที่ค้างอยู่
		sleep = function()
			if pending and coroutine.status(pending) == "suspended" then
				coroutine.resume(pending)
			end
		end,
		now = function() return slowClock end,
		jobId = function() return "server-A" end,
	})

	local HATCH_USER = 5551234
	local hatchKey = "player_" .. HATCH_USER

	local function pump(...)
		for _, thread in { ... } do
			if coroutine.status(thread) == "suspended" then
				coroutine.resume(thread)
			end
		end
	end

	-- เข้าเกม
	local joinCo = coroutine.create(function() DataService.loadAsync(HATCH_USER) end)
	coroutine.resume(joinCo)
	for _ = 1, 6 do
		pump(pending :: any, joinCo)
	end

	local live = DataService.getCached(HATCH_USER)
	check("โหลดข้อมูลเข้าแคชแล้ว", live ~= nil, true)

	-- วางไข่ 224 kg เข้าสวนฟัก (น้ำหนักเดียวกับที่เจอในเกมจริง)
	live.hatching[1] = { eggId = "egg_stage1", weight = 224, startedAt = slowClock, hatchAt = slowClock + 30 }

	-- ══ autosave เริ่มทำงาน แล้วค้างอยู่กลางทาง ══
	slowClock += 60
	local autoCo = coroutine.create(function() DataService.saveAsync(HATCH_USER, false) end)
	coroutine.resume(autoCo) -- ค้างที่ช่วงดึงค่า
	coroutine.resume(pending :: any) -- transform ทำงาน (snapshot = ก่อนฟัก) แล้วค้างที่ช่วงเขียน

	-- ══ ไข่ฟักเสร็จระหว่างนั้น — ลูป sync เป็นคนละ thread ══
	local hatched = live.hatching[1]
	live.hatching[1] = false
	table.insert(live.mothersInPen, {
		uid = Config.makeUid(HATCH_USER, live.nextUid),
		charId = "horse",
		weight = hatched.weight,
		statuses = {},
		obtainedAt = slowClock,
		locked = false,
		lastProducedAt = slowClock,
	})
	live.nextUid += 1
	check("ในหน่วยความจำ: แม่เข้าคอกแล้ว", #live.mothersInPen, 1)
	check("ในหน่วยความจำ: สวนฟักว่างแล้ว", live.hatching[1], false)

	-- ══ ผู้เล่นกด Leave ระหว่างที่ autosave ยังค้าง ══
	local leaveCo = coroutine.create(function() DataService.saveAsync(HATCH_USER, true) end)
	coroutine.resume(leaveCo)
	for _ = 1, 40 do
		pump(pending :: any, autoCo, leaveCo)
	end
	DataService.forget(HATCH_USER)

	-- ══ สิ่งที่อยู่ใน DataStore จริงหลังผู้เล่นออกไปแล้ว ══
	local onDisk = slowStore.data[hatchKey]
	check("เซฟรอบสุดท้ายเขียนจริง ไม่ถูกข้าม", onDisk ~= nil, true)
	-- ⚠️ สามข้อนี้คืออาการที่ผู้เล่นเจอ ถ้าข้อไหนตก แปลว่าบั๊กกลับมาแล้ว
	check("แม่ยังอยู่ในคอก (ไม่หายไป)", #onDisk.mothersInPen, 1)
	-- ⚠️ อ่านแบบกันพัง เพื่อให้ตอนบั๊กกลับมา เทสต์ "ตก" พร้อมรายงานครบทุกข้อ
	-- ไม่ใช่ error กลางคันจนข้ออื่นไม่ได้รัน (เคยเป็นแบบนั้นตอนเขียนเทสต์นี้ครั้งแรก)
	local savedMother = onDisk.mothersInPen[1]
	check("น้ำหนักแม่ตรงกับไข่ที่ฟัก", if savedMother then savedMother.weight else nil, 224)
	check("ไม่มีไข่ค้างในสวนฟัก", onDisk.hatching[1], false)
	-- ⚠️ ผลพวงข้อที่สอง: lock ที่ไม่ถูกปลดทำให้เข้าเกมใหม่ไม่ได้นานถึง 5 นาที
	check("session lock ถูกปลดแล้ว", onDisk.sessionLock, nil)

	-- โหลดกลับมาต้องได้สถานะหลังฟัก ไม่ใช่ก่อนฟัก
	local afterCo = coroutine.create(function() DataService.loadAsync(HATCH_USER) end)
	coroutine.resume(afterCo)
	for _ = 1, 8 do
		pump(pending :: any, afterCo)
	end
	local rejoined = DataService.getCached(HATCH_USER)
	check("เข้าใหม่แล้วแม่ยังอยู่", if rejoined then #rejoined.mothersInPen else -1, 1)
	check("เข้าใหม่แล้วไม่มีไข่ค้าง", if rejoined then rejoined.hatching[1] else nil, false)

	-- ⚠️ autosave (ไม่ใช่รอบสุดท้าย) ยังข้ามได้เหมือนเดิม — รอบที่ค้างอยู่เขียนข้อมูลชุดเดียวกัน

	----------------------------------------------------------------------------
	-- 🔴 บั๊กพี่น้องกัน: ผู้เล่นคนสุดท้ายออก → เซิร์ฟปิดทับเซฟที่ยังไม่จบ
	----------------------------------------------------------------------------
	-- ลำดับเหตุการณ์ตอนคนสุดท้ายกด Leave:
	--   1. PlayerRemoving ยิง → เซฟรอบสุดท้ายเริ่ม แล้วค้างอยู่ใน UpdateAsync
	--   2. Roblox เริ่มปิดเซิร์ฟ → BindToClose ยิง
	--   3. ถึงตอนนี้ `Players:GetPlayers()` **ว่างไปแล้ว**
	--
	-- โค้ดเดิมไล่จากรายชื่อผู้เล่น เจอว่าง แล้ว return ทันที
	-- → เซิร์ฟตายทับเซฟที่ยังวิ่งอยู่ → ได้อาการเดียวกับบั๊กข้างบนเป๊ะ (แม่หาย ไข่กลับมา)
	print("── ปิดเซิร์ฟตอนคนสุดท้ายเพิ่งออก ──")

	local closeStore = { data = {} }
	function closeStore.UpdateAsync(_self, key, transform)
		local result = transform(closeStore.data[key])
		if result ~= nil then
			closeStore.data[key] = deepCopy(result)
		end
		return result
	end
	function closeStore.GetAsync(_self, key)
		return closeStore.data[key]
	end

	DataService.injectForTests({
		store = closeStore,
		sleep = function() end,
		now = function() return 3000000 end,
		jobId = function() return "server-A" end,
	})

	local LAST_USER = 4242424
	DataService.loadAsync(LAST_USER)

	-- ⚠️ นี่คือหัวใจ: ผู้เล่นออกจากเกมไปแล้ว (ไม่อยู่ใน Players:GetPlayers() อีกต่อไป)
	-- แต่ข้อมูลยังค้างอยู่ในแคชเพราะเซฟรอบสุดท้ายยังไม่จบ
	local toSave = DataService.pendingOnClose()
	check("ตอนปิดเซิร์ฟยังเห็นคนที่ออกไปแล้วแต่เซฟไม่จบ", #toSave, 1)
	check("และเป็นคนที่ถูกต้อง", toSave[1], LAST_USER)

	-- เซฟจบแล้วต้องไม่เหลือใครให้ทำอีก
	DataService.saveAsync(LAST_USER, true)
	check("เซฟจบแล้วไม่เหลือใครค้าง", #DataService.pendingOnClose(), 0)
end
