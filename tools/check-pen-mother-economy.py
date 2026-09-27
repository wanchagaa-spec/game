# -*- coding: utf-8 -*-
"""ทดสอบ Phase 2B-2: อัปเกรดคอก + ขายแม่ + ข้อ D (คอก/กระเป๋าเต็มพร้อมกัน)

    python3 tools/check-pen-mother-economy.py

⚠️ วิธีทำงาน: เหมือน tools/check-egg-placement-validation.py เป๊ะ — โหลดซอร์สจริงของ
EggService.lua ด้วย loadstring แล้วเรียก EggService.start() จริง เพื่อดักจับ callback
ที่ผูกกับ UpgradePenRequest/SellMotherRequest ตัวจริง ยิงเข้า callback ตรง ๆ ไม่ใช่เรียก
EggService.upgradePen()/sellMother() ลอย ๆ

Config / PlayerData / DataService เป็นของจริงทั้งหมด มีแค่ PenService/Remotes/Random/
ProductionService ที่เป็นของปลอม (เหตุผลเดียวกับ check-egg-placement-validation.py)

⚠️ EggService.lua ไม่มีนาฬิกาปลอมให้ inject (ไม่เหมือน DataService/ProductionService)
เทสต์เรื่องแม่ที่ค้างในสวนฟัก (ข้อ D) จึงตั้ง data.hatching[...] ให้ hatchAt เป็นอดีตตรง ๆ
แล้วจำลอง "เข้าเกมใหม่" (EggService.onPlayerAdded ซ้ำ) เพื่อกระตุ้น processReadyHatchSlots
แทนการรอเวลาฟักจริง (สั้นสุดตอนนี้คือ 1 นาที ยาวสุด 62.4 ชม. — รอจริงไม่ไหว)
"""
import os, subprocess, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAU = os.environ.get('LUAU') or shutil.which('luau')
if not LUAU:
    sys.exit('หา luau CLI ไม่เจอ — ติดตั้งแล้วใส่ใน PATH หรือสั่ง LUAU=/path/to/luau python3 ...')

STUB = '''--!nocheck
local Config = require("./src/shared/Config")
local PlayerData = require("./src/shared/PlayerData")
local DataService = require("./src/server/DataService")
-- ⚠️ ของจริง (ไม่ใช่ของปลอม) — CombatService เป็น Luau ล้วน tests/combat.spec ก็โหลดตัวจริง
-- EggService เรียก buildSyncFields / handleSendMotherToBattle ของมันตรง ๆ (Phase 3A+)
local CombatService = require("./src/server/CombatService")

-- fake PenService — ไม่ใช่สิ่งที่เทสต์ชุดนี้สนใจ ให้ผ่านเสมอ + ไม่ทำอะไรจริง
local FakePenService = {}
function FakePenService.getPen(_player)
\treturn true
end
function FakePenService.showEgg(_player, _slotIndex, _eggType, _weight) end
function FakePenService.hideEgg(_player, _slotIndex) end
function FakePenService.refreshMothers(_player, _mothers) end

-- fake ProductionService — EggService require ตรง ๆ (moveMother เรียก settleMother)
-- ไม่ใช่สิ่งที่เทสต์ชุดนี้สนใจ
local FakeProductionService = {}
function FakeProductionService.settleMother(_data, _mother, _online)
\treturn 0, 0, false
end
function FakeProductionService.settleAllInPen(_data, _online)
\treturn 0, 0, false
end

-- fake Remotes — จับ callback ที่ EggService.start() ผูกไว้จริง ๆ
-- + จำ FireClient ครั้งล่าสุดของแต่ละ remote (ต่อผู้เล่น) ไว้ตรวจสิ่งที่ส่งกลับไปหา client (Phase 4B)
local capturedHandlers = {}
local lastFired = {} -- [remoteName][userId] = table.pack(...args ไม่รวม player)
local fireCounts = {} -- [remoteName][userId] = จำนวนครั้งที่ FireClient (UI-2: sync ครั้งเดียวต่อชุด)
local FakeRemotes = {}
function FakeRemotes.waitFor(name)
\tlocal remote = {}
\tremote.OnServerEvent = {
\t\tConnect = function(_self, fn)
\t\t\tcapturedHandlers[name] = fn
\t\t\treturn { Disconnect = function() end }
\t\tend,
\t}
\tremote.FireClient = function(_self, player, ...)
\t\tlastFired[name] = lastFired[name] or {}
\t\tlastFired[name][player.UserId] = table.pack(...)
\t\tfireCounts[name] = fireCounts[name] or {}
\t\tfireCounts[name][player.UserId] = (fireCounts[name][player.UserId] or 0) + 1
\tend
\treturn remote
end

local function firedTo(player, remoteName)
\treturn (lastFired[remoteName] or {})[player.UserId]
end

local function fireCount(player, remoteName)
\treturn (fireCounts[remoteName] or {})[player.UserId] or 0
end

-- luau CLI ไม่มี Random ของ Roblox จริง (ดูคอมเมนต์เดียวกันใน tests/config.spec.luau)
local FakeRandom = {
\tnew = function()
\t\treturn { NextInteger = function(_self, lo, hi) return math.random(lo, hi) end }
\tend,
}

local __env = {
\tConfig = Config,
\tPlayerData = PlayerData,
\tRemotes = FakeRemotes,
\tDataService = DataService,
\tPenService = FakePenService,
\tProductionService = FakeProductionService,
\tCombatService = CombatService,
\tPlayers = {},
\tRandom = FakeRandom,
\twarn = print,
\ttask = { spawn = function() end, wait = function() end },
}

'''

PRELUDE = '''
local __env = ...
local Config = __env.Config
local PlayerData = __env.PlayerData
local Remotes = __env.Remotes
local DataService = __env.DataService
local PenService = __env.PenService
local ProductionService = __env.ProductionService
local CombatService = __env.CombatService
local Players = __env.Players
local Random = __env.Random
local warn = __env.warn
local task = __env.task
'''

CHECK = '''

local EggService = loadstring(__EGGSERVICE_SOURCE, "EggService")(__env)
EggService.start()

local upgradePenHandler = capturedHandlers[Config.RemoteNames.UPGRADE_PEN_REQUEST]
local sellMotherHandler = capturedHandlers[Config.RemoteNames.SELL_MOTHER_REQUEST]
local autoFillPenHandler = capturedHandlers[Config.RemoteNames.AUTO_FILL_PEN_REQUEST]
local toggleLockHandler = capturedHandlers[Config.RemoteNames.TOGGLE_MOTHER_LOCK_REQUEST]
local sendToBattleHandler = capturedHandlers[Config.RemoteNames.SEND_MOTHER_TO_BATTLE_REQUEST]
local moveMotherHandler = capturedHandlers[Config.RemoteNames.MOVE_MOTHER_REQUEST]
assert(toggleLockHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ ToggleMotherLockRequest")
assert(sendToBattleHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ SendMotherToBattleRequest")
assert(moveMotherHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ MoveMotherRequest")
assert(upgradePenHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ UpgradePenRequest")
assert(sellMotherHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ SellMotherRequest")
assert(autoFillPenHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ AutoFillPenRequest")

local fakeStore = { data = {} }
function fakeStore.UpdateAsync(_self, key, transform)
\tlocal result = transform(fakeStore.data[key])
\tif result ~= nil then
\t\tfakeStore.data[key] = result
\tend
\treturn result
end
function fakeStore.GetAsync(_self, key)
\treturn fakeStore.data[key]
end

DataService.injectForTests({
\tstore = fakeStore,
\tsleep = function() end,
\tnow = function() return os.time() end,
\tjobId = function() return "test-job" end,
})

--------------------------------------------------------------------------------
-- mini harness เหมือน tests/run.luau
--------------------------------------------------------------------------------

local passCount, failCount = 0, 0
-- รองรับสองรูปแบบ: check(label, boolean) ตรง ๆ กับ check(label, got, want) แบบเทียบค่า
-- (want ไม่ใส่มา = ถือว่าอยากได้ true) ต้องรองรับทั้งคู่เพราะไฟล์นี้ใช้ปนกันทั้งสองแบบ
local function check(label, got, want)
\tif want == nil then
\t\twant = true
\tend
\tlocal ok = got == want
\tif ok then
\t\tpassCount += 1
\t\tprint(`  ✓ {label}`)
\telse
\t\tfailCount += 1
\t\tprint(`  ✗ {label}: ได้ "{tostring(got)}" ต้องการ "{tostring(want)}"`)
\tend
end

local nextUserId = 800001
local function freshPlayer(tag)
\tlocal userId = nextUserId
\tnextUserId += 1
\tlocal player = { UserId = userId, Name = tag }
\tlocal okAdd = EggService.onPlayerAdded(player)
\tassert(okAdd, `เซ็ตอัพเทสต์ผิด — onPlayerAdded ของ {tag} ล้ม`)
\treturn player, DataService.getCached(userId)
end

-- แม่จำลอง — charId/weight/statuses กำหนดเองได้ ที่เหลือใช้ค่ากลาง ๆ
local function makeMother(uid, charId, weight, extra)
\tlocal mother = {
\t\tuid = uid,
\t\tcharId = charId,
\t\tweight = weight,
\t\tstatuses = {},
\t\tobtainedAt = os.time(),
\t\tlocked = false,
\t}
\tif extra then
\t\tfor k, v in extra do
\t\t\tmother[k] = v
\t\tend
\tend
\treturn mother
end

-- เติมคอก/กระเป๋าให้เต็มพอดีตามความจุปัจจุบัน (ล้างของเดิมทิ้งก่อนเสมอ)
local function fillPenAndBag(data)
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\tlocal penCap = Config.getPenCapacity(data.penLevel)
\tfor i = 1, penCap do
\t\ttable.insert(data.mothersInPen, makeMother(`filler-pen-{i}`, "monkey", 100, { lastProducedAt = os.time() }))
\tend
\tfor i = 1, Config.Balance.Bag.CAPACITY do
\t\ttable.insert(data.mothersInBag, makeMother(`filler-bag-{i}`, "monkey", 100))
\tend
\treturn penCap, Config.Balance.Bag.CAPACITY
end

--------------------------------------------------------------------------------
-- 1) อัปเกรดคอก
--------------------------------------------------------------------------------

print("\\n━━ อัปเกรดคอก: เงินพอ → สำเร็จ ━━")
do
\tlocal player, data = freshPlayer("PenUp1")
\tlocal cost = Config.getPenUpgradeCost(data.penLevel)
\tdata.currency.coins = cost -- พอดีเป๊ะ
\tlocal startLevel = data.penLevel
\tlocal startCap = Config.getPenCapacity(data.penLevel)

\tlocal ok = pcall(upgradePenHandler, player)
\tcheck("ไม่ error/crash", ok)
\tcheck("เลเวลคอกขึ้น 1 ขั้น", data.penLevel, startLevel + 1)
\tcheck("เงินถูกหักเต็มจำนวนราคา", data.currency.coins, 0)
\tcheck("ความจุคอกเพิ่มขึ้นทันที (อ่านสดจาก penLevel)", Config.getPenCapacity(data.penLevel) > startCap, true)
end

print("\\n━━ อัปเกรดคอก: เงินไม่พอ → ปฏิเสธ ไม่หักเงินไม่ขึ้นเลเวล ━━")
do
\tlocal player, data = freshPlayer("PenUp2")
\tlocal cost = Config.getPenUpgradeCost(data.penLevel)
\tdata.currency.coins = cost - 1 -- ขาดไป 1
\tlocal startLevel = data.penLevel

\tlocal ok = pcall(upgradePenHandler, player)
\tcheck("ไม่ error/crash", ok)
\tcheck("เลเวลไม่ขึ้น", data.penLevel, startLevel)
\tcheck("เงินไม่ถูกหัก", data.currency.coins, cost - 1)
end

print("\\n━━ อัปเกรดคอก: เลเวลเต็มเพดานแล้ว → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("PenUp3")
\tdata.penLevel = Config.Balance.Pen.MAX_LEVEL
\tdata.currency.coins = 999999999999999

\tlocal ok = pcall(upgradePenHandler, player)
\tcheck("ไม่ error/crash", ok)
\tcheck("เลเวลยังอยู่ที่เพดาน ไม่ทะลุ", data.penLevel, Config.Balance.Pen.MAX_LEVEL)
end

--------------------------------------------------------------------------------
-- 2) ขายแม่
--------------------------------------------------------------------------------

print("\\n━━ ขายแม่: ราคาคำนวณถูกตามสูตร Config.getMotherSellPrice ━━")
do
\tlocal player, data = freshPlayer("Sell1")
\ttable.clear(data.mothersInBag)
\ttable.insert(data.mothersInBag, makeMother("sell-target", "wukong", 1500))
\tdata.currency.coins = 0

\tlocal expectedPrice = Config.getMotherSellPrice(1500, data.wallProgress, {})
\tlocal ok = pcall(sellMotherHandler, player, "sell-target")
\tcheck("ไม่ error/crash", ok)
\tcheck("เงินเข้าตรงตามสูตรราคาขาย", data.currency.coins, expectedPrice)
\tcheck("แม่ถูกลบออกจากกระเป๋าถาวร", #data.mothersInBag, 0)
end

print("\\n━━ ขายแม่: ขายจากกระเป๋าได้ ━━")
do
\tlocal player, data = freshPlayer("Sell2")
\ttable.clear(data.mothersInBag)
\ttable.insert(data.mothersInBag, makeMother("bag-mother", "monkey", 200))
\tlocal ok = pcall(sellMotherHandler, player, "bag-mother")
\tcheck("ไม่ error/crash", ok)
\tcheck("ขายจากกระเป๋าสำเร็จ", #data.mothersInBag, 0)
end

print("\\n━━ ขายแม่: ขายจากคอกไม่ได้ (ต้องย้ายออกมาก่อน) ━━")
do
\tlocal player, data = freshPlayer("Sell3")
\ttable.clear(data.mothersInPen)
\ttable.insert(data.mothersInPen, makeMother("pen-mother", "monkey", 300, { lastProducedAt = os.time() }))
\tlocal coinsBefore = data.currency.coins

\tlocal ok = pcall(sellMotherHandler, player, "pen-mother")
\tcheck("ไม่ error/crash", ok)
\tcheck("แม่ในคอกไม่ถูกขาย ยังอยู่ครบ", #data.mothersInPen, 1)
\tcheck("เงินไม่เปลี่ยน", data.currency.coins, coinsBefore)
end

print("\\n━━ ขายแม่: id ปลอม (ไม่มีอยู่จริง) → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("Sell4")
\tlocal coinsBefore = data.currency.coins
\tlocal ok = pcall(sellMotherHandler, player, "ไม่มีจริง-99999")
\tcheck("ไม่ error/crash", ok)
\tcheck("เงินไม่เปลี่ยน", data.currency.coins, coinsBefore)
end

print("\\n━━ ขายแม่: uid ของผู้เล่นอีกคน → ปฏิเสธ (กัน exploit ข้ามบัญชี) ━━")
do
\tlocal playerA, dataA = freshPlayer("Sell5A")
\ttable.clear(dataA.mothersInBag)
\ttable.insert(dataA.mothersInBag, makeMother("owned-by-a", "wukong", 5000))

\tlocal playerB, dataB = freshPlayer("Sell5B")
\tlocal coinsBeforeB = dataB.currency.coins

\tlocal ok = pcall(sellMotherHandler, playerB, "owned-by-a")
\tcheck("ไม่ error/crash", ok)
\tcheck("B ขายแม่ของ A ไม่ได้ เงิน B ไม่เปลี่ยน", dataB.currency.coins, coinsBeforeB)
\tcheck("แม่ของ A ไม่ถูกแตะเลย ยังอยู่ที่ A", #dataA.mothersInBag, 1)
end

print("\\n━━ ขายแม่: exploit — remote ไม่มีพารามิเตอร์ราคาให้ client ส่งมาเองเลย ━━")
do
\t-- SellMotherRequest(motherUid) รับแค่ uid ตัวเดียว ราคาคำนวณฝั่ง server ล้วน ๆ จาก
\t-- Config.getMotherSellPrice() — ไม่มีช่องพารามิเตอร์ให้ client "ส่งราคาที่อยากได้" มาได้เลย
\t-- ต่อให้ยิง extra argument เข้ามาก็ถูกเพิกเฉย (handler อ่านแค่ rawUid ตัวเดียว)
\tlocal player, data = freshPlayer("Sell6")
\ttable.clear(data.mothersInBag)
\ttable.insert(data.mothersInBag, makeMother("cheap-mother", "monkey", 100))
\tdata.currency.coins = 0 -- ล้างเงินเริ่มต้นของผู้เล่นใหม่ (500) ให้เทียบราคาขายตรง ๆ ได้
\tlocal correctPrice = Config.getMotherSellPrice(100, data.wallProgress, {})

\tlocal ok = pcall(sellMotherHandler, player, "cheap-mother", 999999999) -- แถม arg ราคาปลอมมา
\tcheck("ไม่ error/crash", ok)
\tcheck("เงินได้ตามราคาจริงจาก server เท่านั้น ไม่ใช่ตัวเลขปลอมที่แถมมา", data.currency.coins, correctPrice)
end

--------------------------------------------------------------------------------
-- 2.5) ล็อกแม่ (Phase 4B) — กันขาย + กันส่งไปรบ · ไม่กันย้ายคอก↔กระเป๋า
--------------------------------------------------------------------------------

local ACTION_RESULT = Config.RemoteNames.ACTION_RESULT
local FARM_STATE_SYNC = Config.RemoteNames.FARM_STATE_SYNC

local function findIn(list, uid)
\tfor _, m in list do
\t\tif m.uid == uid then
\t\t\treturn m
\t\tend
\tend
\treturn nil
end

print("\\n━━ ล็อกแม่: toggle ในกระเป๋า → locked สลับ + ตอบ ActionResult + sync ส่ง locked ━━")
do
\tlocal player, data = freshPlayer("Lock1")
\ttable.clear(data.mothersInBag)
\ttable.insert(data.mothersInBag, makeMother("lock-bag", "monkey", 200))

\tlocal ok = pcall(toggleLockHandler, player, "lock-bag")
\tcheck("ไม่ error/crash", ok)
\tcheck("ล็อกแล้ว locked = true", data.mothersInBag[1].locked, true)
\tlocal result = firedTo(player, ACTION_RESULT)
\tcheck("ActionResult ok = true", result and result[1], true)
\tcheck("ActionResult บอกว่าล็อกแล้ว", result ~= nil and string.find(result[2], "ล็อกแม่แล้ว", 1, true) ~= nil, true)
\tlocal payload = firedTo(player, FARM_STATE_SYNC)
\tlocal synced = payload and findIn(payload[1].mothersInBag, "lock-bag")
\tcheck("sync ส่ง locked = true ให้ client", synced and synced.locked, true)

\tpcall(toggleLockHandler, player, "lock-bag")
\tcheck("กดอีกครั้ง → ปลดล็อก locked = false", data.mothersInBag[1].locked, false)
\tresult = firedTo(player, ACTION_RESULT)
\tcheck("ActionResult บอกว่าปลดล็อกแล้ว", result ~= nil and string.find(result[2], "ปลดล็อกแม่แล้ว", 1, true) ~= nil, true)
\tpayload = firedTo(player, FARM_STATE_SYNC)
\tsynced = payload and findIn(payload[1].mothersInBag, "lock-bag")
\tcheck("sync ส่ง locked = false ให้ client", synced ~= nil and synced.locked, false)
end

print("\\n━━ ล็อกแม่: แม่ในคอกล็อกได้ · ย้ายคอก↔กระเป๋าไม่โดนกัน และล็อกติดตัวไปด้วย ━━")
do
\tlocal player, data = freshPlayer("Lock2")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\ttable.insert(data.mothersInPen, makeMother("lock-pen", "monkey", 300, { lastProducedAt = os.time() }))

\tpcall(toggleLockHandler, player, "lock-pen")
\tcheck("แม่ในคอกล็อกได้", data.mothersInPen[1].locked, true)

\tlocal ok = pcall(moveMotherHandler, player, "lock-pen", "bag")
\tcheck("ไม่ error/crash", ok)
\tcheck("ล็อกอยู่ก็ย้ายคอก → กระเป๋าได้", #data.mothersInBag, 1)
\tcheck("  ล็อกติดตัวไปด้วย", data.mothersInBag[1].locked, true)
\tpcall(moveMotherHandler, player, "lock-pen", "pen")
\tcheck("ล็อกอยู่ก็ย้ายกระเป๋า → คอกได้", #data.mothersInPen, 1)
\tcheck("  ล็อกยังติดตัว", data.mothersInPen[1].locked, true)
end

print("\\n━━ ล็อกแม่: uid ปลอม/ของคนอื่น/ไม่ใช่ string/แม่ใน roster → ปฏิเสธ ไม่แตะอะไร ━━")
do
\tlocal playerA, dataA = freshPlayer("Lock3A")
\ttable.clear(dataA.mothersInBag)
\ttable.insert(dataA.mothersInBag, makeMother("owned-by-3a", "monkey", 100))
\ttable.insert(dataA.battleRoster, makeMother("in-roster-3a", "monkey", 100))
\tlocal playerB = freshPlayer("Lock3B")

\tlocal ok = pcall(toggleLockHandler, playerB, "owned-by-3a")
\tcheck("ไม่ error/crash", ok)
\tcheck("B ล็อกแม่ของ A ไม่ได้", dataA.mothersInBag[1].locked, false)
\tcheck("  B ได้ ActionResult ปฏิเสธ", firedTo(playerB, ACTION_RESULT)[1], false)

\tpcall(toggleLockHandler, playerA, "ไม่มีจริง-1")
\tcheck("uid ปลอม → ปฏิเสธ", firedTo(playerA, ACTION_RESULT)[1], false)
\tpcall(toggleLockHandler, playerA, 12345)
\tcheck("uid ไม่ใช่ string → ปฏิเสธ", firedTo(playerA, ACTION_RESULT)[1], false)
\tpcall(toggleLockHandler, playerA, "in-roster-3a")
\tcheck("แม่ใน roster → ปฏิเสธ", firedTo(playerA, ACTION_RESULT)[1], false)
\tcheck("  แม่ใน roster ไม่ถูกแตะ", dataA.battleRoster[1].locked, false)
end

print("\\n━━ ล็อกแม่: ขายแม่ที่ล็อก → ปฏิเสธ · ปลดล็อกแล้วขายได้ ━━")
do
\tlocal player, data = freshPlayer("Lock4")
\ttable.clear(data.mothersInBag)
\ttable.insert(data.mothersInBag, makeMother("locked-sell", "wukong", 1500, { locked = true }))
\tdata.currency.coins = 0

\tlocal ok = pcall(sellMotherHandler, player, "locked-sell")
\tcheck("ไม่ error/crash", ok)
\tcheck("แม่ที่ล็อกไม่ถูกขาย ยังอยู่ในกระเป๋า", #data.mothersInBag, 1)
\tcheck("  เงินไม่เปลี่ยน", data.currency.coins, 0)
\tlocal result = firedTo(player, ACTION_RESULT)
\tcheck("  ActionResult ok = false", result[1], false)
\tcheck("  ข้อความตามโจทย์", result[2], "แม่ตัวนี้ถูกล็อกไว้ ขายไม่ได้")

\tpcall(toggleLockHandler, player, "locked-sell")
\tcheck("ปลดล็อกแล้ว", data.mothersInBag[1].locked, false)
\tlocal expectedPrice = Config.getMotherSellPrice(1500, data.wallProgress, {})
\tpcall(sellMotherHandler, player, "locked-sell")
\tcheck("ปลดล็อกแล้วขายได้ แม่หายจากกระเป๋า", #data.mothersInBag, 0)
\tcheck("  ได้เงินตามสูตรราคาขาย", data.currency.coins, expectedPrice)
\tcheck("  ActionResult ok = true", firedTo(player, ACTION_RESULT)[1], true)
end

print("\\n━━ ล็อกแม่: ส่งแม่ที่ล็อกไปรบ → ยังโดนปฏิเสธ · ปลดล็อกแล้วส่งได้ ━━")
do
\tlocal player, data = freshPlayer("Lock5")
\t-- ด่าน 1 พังแล้ว กำลังตีด่าน 2 (ด่าน 1 ไม่มีศัตรู ส่งแม่ไม่ได้อยู่แล้ว)
\tdata.stageProgress[1] = { defendersRemaining = 0, wallHpRemaining = 0 }
\tCombatService.ensureStageStarted(data, 2)
\ttable.clear(data.mothersInBag)
\ttable.clear(data.battleRoster)
\ttable.insert(data.mothersInBag, makeMother("locked-send", "monkey", 500, { locked = true }))

\tlocal ok = pcall(sendToBattleHandler, player, "locked-send")
\tcheck("ไม่ error/crash", ok)
\tcheck("แม่ที่ล็อกไม่ถูกส่ง ยังอยู่ในกระเป๋า", #data.mothersInBag, 1)
\tcheck("  roster ว่าง", #data.battleRoster, 0)
\tlocal result = firedTo(player, ACTION_RESULT)
\tcheck("  ActionResult ok = false", result[1], false)
\tcheck("  ข้อความเดิมของ 3C-1", result[2], "แม่ตัวนี้ถูกล็อกไว้ ส่งไปรบไม่ได้")

\tpcall(toggleLockHandler, player, "locked-send")
\tpcall(sendToBattleHandler, player, "locked-send")
\tcheck("ปลดล็อกแล้วส่งได้ → เข้า roster", #data.battleRoster, 1)
\tcheck("  ออกจากกระเป๋า", #data.mothersInBag, 0)
end

--------------------------------------------------------------------------------
-- 2.6) popup ผ่านด่าน (Phase 4B) — payload (stage, eggCount, deathCount)
--------------------------------------------------------------------------------

local STAGE_CLEARED_NOTIFY = Config.RemoteNames.STAGE_CLEARED_NOTIFY

print("\\n━━ popup ผ่านด่าน: ส่ง (ด่าน, ไข่ที่แจกได้จริง, แม่ที่ตาย) ครบ 3 ค่า ━━")
do
\tlocal player, data = freshPlayer("Notify1")
\tlocal eggsBefore = #data.heldEggs.items
\tEggService.grantStageClearBonus(player, 4, 2, 3)
\tlocal fired = firedTo(player, STAGE_CLEARED_NOTIFY)
\tcheck("ไข่ + แม่ตาย: ยิงมา 3 ค่า", fired and fired.n, 3)
\tcheck("  ด่าน", fired[1], 4)
\tcheck("  ไข่", fired[2], 2)
\tcheck("  แม่ตาย", fired[3], 3)
\tcheck("  ไข่เข้ากระเป๋าจริง 2 ฟอง", #data.heldEggs.items - eggsBefore, 2)

\teggsBefore = #data.heldEggs.items
\tEggService.grantStageClearBonus(player, 2, 0, 5)
\tfired = firedTo(player, STAGE_CLEARED_NOTIFY)
\tcheck("แม่ตายอย่างเดียว: ไข่ 0", fired[2], 0)
\tcheck("  แม่ตาย 5", fired[3], 5)
\tcheck("  ไม่มีไข่เข้ากระเป๋า", #data.heldEggs.items - eggsBefore, 0)

\tEggService.grantStageClearBonus(player, 3, 1, 0)
\tfired = firedTo(player, STAGE_CLEARED_NOTIFY)
\tcheck("ไข่อย่างเดียว: ไข่ 1", fired[2], 1)
\tcheck("  แม่ตาย 0", fired[3], 0)
end

--------------------------------------------------------------------------------
-- 3) ข้อ D — คอกเต็ม + กระเป๋าเต็มพร้อมกัน
--------------------------------------------------------------------------------

print("\\n━━ ข้อ D: ไข่ครบเวลาฟักตอนคอก+กระเป๋าเต็มพร้อมกัน → ค้างไว้ ไม่หาย ━━")
do
\tlocal player, data = freshPlayer("StuckD1")
\tlocal penCap, bagCap = fillPenAndBag(data)
\ttable.clear(data.heldEggs.items)

\t-- ไข่ที่ครบเวลาฟักไปแล้ว (hatchAt เป็นอดีต) ตั้งตรง ๆ ข้ามการรอเวลาจริง
\tdata.hatching[1] = {
\t\teggId = "egg_stage1",
\t\tweight = 500,
\t\tcharId = "wukong",
\t\tstartedAt = os.time() - 100,
\t\thatchAt = os.time() - 10,
\t}

\t-- จำลอง "เข้าเกมใหม่" เพื่อกระตุ้น processReadyHatchSlots (แบบเดียวกับ Case 7 ใน
\t-- check-egg-placement-validation.py) — ต้อง save ก่อน ไม่งั้น loadAsync รอบสองจะได้
\t-- ข้อมูลจาก store ซึ่งยังไม่มีการมิวเทตที่เพิ่งทำตรง ๆ
\tDataService.saveAsync(player.UserId, false)
\tlocal rejoinOk = EggService.onPlayerAdded(player)
\tcheck("จำลองเข้าเกมใหม่สำเร็จ", rejoinOk)
\tdata = DataService.getCached(player.UserId)

\tcheck("คอกไม่โตขึ้น (แม่ไม่ถูกสร้าง)", #data.mothersInPen, penCap)
\tcheck("กระเป๋าไม่โตขึ้น (แม่ไม่ถูกสร้าง)", #data.mothersInBag, bagCap)
\tcheck("ไข่ยังค้างอยู่ในสวนฟัก ไม่หายไปไหน", type(data.hatching[1]), "table")
\tif type(data.hatching[1]) == "table" then
\t\tcheck("น้ำหนักของไข่ที่ค้างยังตรง", data.hatching[1].weight, 500)
\t\tcheck("charId ของไข่ที่ค้างยังตรง", data.hatching[1].charId, "wukong")
\tend

\t-- ขายแม่ในกระเป๋า 1 ตัว เปิดที่ว่าง → ต้องย้ายแม่ที่ค้างไว้เข้ามาอัตโนมัติทันที
\tlocal soldOk = pcall(sellMotherHandler, player, "filler-bag-1")
\tcheck("ขายแม่เปิดที่ว่างสำเร็จ", soldOk)
\tdata = DataService.getCached(player.UserId)

\tcheck("แม่ที่ค้างถูกย้ายเข้ามาอัตโนมัติทันที (สวนฟักว่างแล้ว ไม่ต้องรอ tick)", data.hatching[1], false)
\tcheck("กระเป๋ามีจำนวนเท่าเดิม (ขายไป 1 ได้แม่ใหม่มาแทน 1)", #data.mothersInBag, bagCap)

\tlocal foundStuckMother = false
\tfor _, m in data.mothersInBag do
\t\tif m.charId == "wukong" and m.weight == 500 then
\t\t\tfoundStuckMother = true
\t\tend
\tend
\tcheck("แม่ที่ค้างไว้ปรากฏในกระเป๋าจริง (ครบทั้งน้ำหนักและตัวละคร)", foundStuckMother, true)
end

print("\\n━━ ข้อ D: หลายฟองค้างพร้อมกัน → ย้ายเข้าตามลำดับ hatchAt น้อยสุดก่อน ━━")
do
\tlocal player, data = freshPlayer("StuckD2")
\tlocal penCap, bagCap = fillPenAndBag(data)
\ttable.clear(data.heldEggs.items)

\t-- สามฟองค้างพร้อมกัน คนละ hatchAt — เรียงจงใจให้เลขช่อง (slotIndex) ไม่ตรงกับลำดับเวลา
\t-- slot 5 เสร็จก่อนสุด (hatchAt น้อยสุด) แต่เลขช่องมากสุด — ถ้าโค้ดวิ่งตาม slotIndex ตรง ๆ
\t-- โดยไม่เรียงตาม hatchAt จะได้คิวผิด
\tdata.hatching[3] = {
\t\teggId = "egg_stage1", weight = 700, charId = "horse",
\t\tstartedAt = os.time() - 50, hatchAt = os.time() - 5, -- เสร็จล่าสุด (ช้าสุด)
\t}
\tdata.hatching[5] = {
\t\teggId = "egg_stage1", weight = 600, charId = "pig",
\t\tstartedAt = os.time() - 200, hatchAt = os.time() - 50, -- เสร็จก่อนสุด (เร็วสุด)
\t}
\tdata.hatching[7] = {
\t\teggId = "egg_stage1", weight = 800, charId = "fish",
\t\tstartedAt = os.time() - 150, hatchAt = os.time() - 20, -- เสร็จตรงกลาง
\t}

\tDataService.saveAsync(player.UserId, false)
\tEggService.onPlayerAdded(player)
\tdata = DataService.getCached(player.UserId)

\tcheck("ทั้งสามฟองยังค้างอยู่ครบ (คอก+กระเป๋าเต็ม)", (function()
\t\treturn type(data.hatching[3]) == "table"
\t\t\tand type(data.hatching[5]) == "table"
\t\t\tand type(data.hatching[7]) == "table"
\tend)(), true)

\t-- เปิดที่ว่างแค่ 1 ที่ (ขาย 1 ตัว) → ต้องได้ตัวที่ hatchAt น้อยสุด (pig, slot 5) เข้าก่อน
\tpcall(sellMotherHandler, player, "filler-bag-2")
\tdata = DataService.getCached(player.UserId)

\tcheck("ตัวที่ hatchAt น้อยสุด (slot 5, pig) ถูกย้ายเข้าก่อน", data.hatching[5], false)
\tcheck("ตัวที่เหลือ (slot 3, horse) ยังค้างอยู่ (ที่ว่างเปิดแค่ 1)", type(data.hatching[3]), "table")
\tcheck("ตัวที่เหลือ (slot 7, fish) ยังค้างอยู่ (ที่ว่างเปิดแค่ 1)", type(data.hatching[7]), "table")

\tlocal foundPig = false
\tfor _, m in data.mothersInBag do
\t\tif m.charId == "pig" and m.weight == 600 then
\t\t\tfoundPig = true
\t\tend
\tend
\tcheck("แม่ตัวที่ถูกย้ายเข้าคือ pig (ตัวที่ฟักเสร็จก่อนจริง) ไม่ใช่ตัวอื่น", foundPig, true)

\t-- เปิดที่ว่างอีก 1 ที่ → ต้องได้ตัวถัดไปตามลำดับ (fish, slot 7 — hatchAt น้อยกว่า horse)
\tpcall(sellMotherHandler, player, "filler-bag-3")
\tdata = DataService.getCached(player.UserId)
\tcheck("เปิดที่ว่างรอบสอง → ตัวถัดไปตามคิว (slot 7, fish) ถูกย้ายเข้า", data.hatching[7], false)
\tcheck("ตัวสุดท้าย (slot 3, horse) ยังค้างอยู่จนกว่าจะมีที่ว่างอีก", type(data.hatching[3]), "table")
end

print("\\n━━ ข้อ D: sync payload บอก stuckHatchCount ถูกต้อง ━━")
do
\tlocal player, data = freshPlayer("StuckD3")
\tlocal penCap, bagCap = fillPenAndBag(data)
\ttable.clear(data.heldEggs.items)

\tdata.hatching[10] = {
\t\teggId = "egg_stage1", weight = 900, charId = "monkey",
\t\tstartedAt = os.time() - 50, hatchAt = os.time() - 5,
\t}
\tdata.hatching[11] = {
\t\teggId = "egg_stage1", weight = 950, charId = "monkey",
\t\tstartedAt = os.time() - 40, hatchAt = os.time() - 3,
\t}
\t-- ฟองนี้ยังไม่ครบเวลา ไม่ควรถูกนับเป็น stuck
\tdata.hatching[12] = {
\t\teggId = "egg_stage1", weight = 100, charId = "monkey",
\t\tstartedAt = os.time(), hatchAt = os.time() + 999,
\t}

\tDataService.saveAsync(player.UserId, false)
\tEggService.onPlayerAdded(player)
\tdata = DataService.getCached(player.UserId)

\t-- เรียก sync ตรง ๆ ไม่ได้ผลลัพธ์กลับมา (FireClient เป็น no-op) จึงตรวจผ่านสถานะ hatching แทน
\t-- (payload ที่แท้จริงคำนวณจาก data ชุดเดียวกันนี้เป๊ะ — ตรวจ data ก็เท่ากับตรวจ payload)
\tlocal stuckCount = 0
\tfor i = 1, Config.Balance.Hatchery.MAX_SLOTS do
\t\tlocal slot = data.hatching[i]
\t\tif type(slot) == "table" and os.time() >= slot.hatchAt then
\t\t\tstuckCount += 1
\t\tend
\tend
\tcheck("มีของค้างครบ 2 ฟองตามที่ตั้งไว้ (ฟองที่ยังไม่ครบเวลาไม่ถูกนับ)", stuckCount, 2)
end

--------------------------------------------------------------------------------
-- 4) จัดแม่เข้าคอกอัตโนมัติ (AutoFillPenRequest)
--------------------------------------------------------------------------------

print("\\n━━ จัดแม่เข้าคอกอัตโนมัติ: เลือกรายได้/นาทีสูงสุดก่อน เติมจนเต็มช่องว่าง ━━")
do
\tlocal player, data = freshPlayer("AutoFill1")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\tlocal penCap = Config.getPenCapacity(data.penLevel)
\t-- เว้นที่ว่างในคอกไว้ 2 ช่อง ที่เหลือเติมแม่เดิมไปก่อน (ต้องไม่ถูกเตะออก)
\tfor i = 1, penCap - 2 do
\t\ttable.insert(data.mothersInPen, makeMother(`existing-pen-{i}`, "monkey", 100, { lastProducedAt = os.time() }))
\tend
\t-- กระเป๋ามีแม่ 3 ตัว น้ำหนักต่างกันชัดเจน (รายได้/นาทีแปรตาม sqrt น้ำหนัก คลาสไม่มีผล)
\ttable.insert(data.mothersInBag, makeMother("low", "monkey", 100))
\ttable.insert(data.mothersInBag, makeMother("mid", "monkey", 10000))
\ttable.insert(data.mothersInBag, makeMother("high", "monkey", 1000000))

\tlocal ok = pcall(autoFillPenHandler, player)
\tcheck("ไม่ error/crash", ok)
\tcheck("คอกเต็มพอดี (เติมแค่ 2 ช่องว่างที่มี)", #data.mothersInPen, penCap)
\tcheck("กระเป๋าเหลือ 1 ตัว (ตัวที่แย่ที่สุดที่เหลือที่ไม่พอ)", #data.mothersInBag, 1)
\tcheck("ตัวที่เหลือในกระเป๋าคือ \\"low\\" (รายได้ต่ำสุด)", data.mothersInBag[1].uid, "low")

\tlocal penUids = {}
\tfor _, m in data.mothersInPen do
\t\tpenUids[m.uid] = true
\tend
\tcheck("\\"high\\" (รายได้สูงสุด) ถูกย้ายเข้าคอก", penUids["high"], true)
\tcheck("\\"mid\\" ถูกย้ายเข้าคอกด้วย (ที่ว่างพอสำหรับ 2 ตัว)", penUids["mid"], true)
\tcheck("\\"low\\" ไม่ถูกย้าย (แย่ที่สุด เหลือที่ไม่พอ)", penUids["low"] == nil, true)

\tlocal allOriginalStillThere = true
\tfor i = 1, penCap - 2 do
\t\tif not penUids[`existing-pen-{i}`] then
\t\t\tallOriginalStillThere = false
\t\tend
\tend
\tcheck("แม่เดิมในคอกทั้งหมดยังอยู่ครบ ไม่มีตัวไหนถูกเตะออก", allOriginalStillThere, true)
end

print("\\n━━ จัดแม่เข้าคอกอัตโนมัติ: คอกเต็มแล้ว → ปฏิเสธ ไม่มีอะไรเปลี่ยน ━━")
do
\tlocal player, data = freshPlayer("AutoFill2")
\tfillPenAndBag(data) -- เติมคอก+กระเป๋าให้เต็มพอดีตามความจุปัจจุบัน
\tlocal penCountBefore, bagCountBefore = #data.mothersInPen, #data.mothersInBag
\tlocal ok = pcall(autoFillPenHandler, player)
\tcheck("ไม่ error/crash", ok)
\tcheck("คอกไม่เปลี่ยน", #data.mothersInPen, penCountBefore)
\tcheck("กระเป๋าไม่เปลี่ยน", #data.mothersInBag, bagCountBefore)
end

print("\\n━━ จัดแม่เข้าคอกอัตโนมัติ: กระเป๋าว่างเปล่า → ไม่มีอะไรเกิดขึ้น ━━")
do
\tlocal player, data = freshPlayer("AutoFill3")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\ttable.insert(data.mothersInPen, makeMother("solo-pen", "monkey", 100, { lastProducedAt = os.time() }))
\tlocal ok = pcall(autoFillPenHandler, player)
\tcheck("ไม่ error/crash", ok)
\tcheck("คอกไม่เปลี่ยน (ยังมีแค่ 1 ตัวเดิม)", #data.mothersInPen, 1)
\tcheck("กระเป๋ายังว่างเปล่า", #data.mothersInBag, 0)
end

print("\\n━━ จัดแม่เข้าคอกอัตโนมัติ: กระเป๋ามีน้อยกว่าที่ว่าง → ย้ายหมดทุกตัว กระเป๋าว่าง ━━")
do
\tlocal player, data = freshPlayer("AutoFill4")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\ttable.insert(data.mothersInBag, makeMother("only1", "monkey", 500))
\ttable.insert(data.mothersInBag, makeMother("only2", "monkey", 800))
\tlocal ok = pcall(autoFillPenHandler, player)
\tcheck("ไม่ error/crash", ok)
\tcheck("คอกได้แม่ทั้งสองตัว", #data.mothersInPen, 2)
\tcheck("กระเป๋าว่างเปล่าหลังจากนั้น (ที่ว่างเหลือเยอะกว่าที่มี)", #data.mothersInBag, 0)
end

-- ⚠️ UI-1: "สวมใส่ที่ดีที่สุด" สลับตัวอ่อนในคอกออกได้แล้ว (เดิมเติมแค่ช่องว่าง)
local function uidSet(list)
\tlocal set = {}
\tfor _, m in list do
\t\tset[m.uid] = (set[m.uid] or 0) + 1
\tend
\treturn set
end

local function allUnique(data)
\tlocal seen = {}
\tfor _, list in { data.mothersInPen, data.mothersInBag, data.battleRoster } do
\t\tfor _, m in list do
\t\t\tif seen[m.uid] then
\t\t\t\treturn false
\t\t\tend
\t\t\tseen[m.uid] = true
\t\tend
\tend
\treturn true
end

print("\\n━━ สวมใส่ที่ดีที่สุด: คอกเต็มด้วยตัวอ่อน → สลับตัวเก่งจากกระเป๋าเข้า ตัวอ่อนออก ━━")
do
\tlocal player, data = freshPlayer("EquipBest1")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\tlocal penCap = Config.getPenCapacity(data.penLevel)
\tfor i = 1, penCap do
\t\ttable.insert(data.mothersInPen, makeMother(`pen-weak-{i}`, "monkey", 100, { lastProducedAt = os.time() }))
\tend
\ttable.insert(data.mothersInBag, makeMother("bag-strong-1", "monkey", 1000000))
\ttable.insert(data.mothersInBag, makeMother("bag-strong-2", "pig", 50000))
\ttable.insert(data.mothersInBag, makeMother("bag-weakest", "fish", 50))
\tlocal total = #data.mothersInPen + #data.mothersInBag

\tlocal ok, reason, summary = EggService.autoFillPen(player)
\tcheck("สำเร็จ", ok)
\tcheck("  สลับเข้า 2 ตัว", summary and summary.movedIn, 2)
\tcheck("  สลับออก 2 ตัว", summary and summary.movedOut, 2)
\tcheck("คอกยังเต็มพอดี", #data.mothersInPen, penCap)
\tlocal pen = uidSet(data.mothersInPen)
\tcheck("  ตัวเก่งสุดเข้าคอก", pen["bag-strong-1"], 1)
\tcheck("  ตัวเก่งอันดับสองเข้าคอก", pen["bag-strong-2"], 1)
\tcheck("  ตัวอ่อนสุดในกระเป๋าไม่ถูกดึงเข้า", pen["bag-weakest"] == nil, true)
\tlocal bag = uidSet(data.mothersInBag)
\tcheck(`  ตัวอ่อนในคอก 2 ตัวท้าย (เรียง uid) ออกไปกระเป๋า`, bag[`pen-weak-{penCap}`] == 1 and bag[`pen-weak-{penCap - 1}`] == 1, true)
\tcheck("ไม่มีแม่หาย (จำนวนรวมเท่าเดิม)", #data.mothersInPen + #data.mothersInBag, total)
\tcheck("ไม่มีแม่ซ้ำ", allUnique(data), true)
\tcheck("แม่ที่ออกจากคอกไม่มีเวลาผลิตค้าง (settle แล้ว)", data.mothersInBag[#data.mothersInBag].lastProducedAt == nil, true)
\tlocal strong = nil
\tfor _, m in data.mothersInPen do
\t\tif m.uid == "bag-strong-1" then
\t\t\tstrong = m
\t\tend
\tend
\tcheck("แม่ที่เข้าคอกเริ่มนับเวลาผลิต", strong ~= nil and type(strong.lastProducedAt) == "number", true)
\tlocal result = firedTo(player, ACTION_RESULT)
\tcheck("ActionResult ไม่ได้ยิงจากการเรียกตรง (ยิงเฉพาะผ่าน remote)", result == nil or result[2] ~= nil, true)

\tlocal ok2, _, summary2 = EggService.autoFillPen(player)
\tcheck("กดซ้ำรอบสอง → สำเร็จแต่ไม่มีอะไรเปลี่ยน", ok2 and summary2 and summary2.movedIn == 0 and summary2.movedOut == 0, true)
\tcheck("  คอกชุดเดิม", uidSet(data.mothersInPen)["bag-strong-1"], 1)
\tpcall(autoFillPenHandler, player)
\tcheck("  ผ่าน remote: ตอบว่าไม่มีอะไรเปลี่ยน", firedTo(player, ACTION_RESULT)[2], "คอกมีแม่ที่ดีที่สุดครบแล้ว ไม่มีอะไรเปลี่ยน")
end

print("\\n━━ สวมใส่ที่ดีที่สุด: กระเป๋าเต็มพอดี → สลับได้ กระเป๋าไม่ล้น ━━")
do
\tlocal player, data = freshPlayer("EquipBest2")
\tlocal penCap, bagCap = fillPenAndBag(data)
\tfor i = 1, 3 do
\t\tdata.mothersInBag[i] = makeMother(`full-bag-strong-{i}`, "wukong", 100000 * i)
\tend
\tlocal total = #data.mothersInPen + #data.mothersInBag

\tlocal ok, _, summary = EggService.autoFillPen(player)
\tcheck("สำเร็จ", ok)
\tcheck("  สลับเข้า 3 ตัว", summary and summary.movedIn, 3)
\tcheck("กระเป๋ายังเท่าความจุพอดี (ไม่ล้น)", #data.mothersInBag, bagCap)
\tcheck("คอกเต็มพอดี", #data.mothersInPen, penCap)
\tlocal pen = uidSet(data.mothersInPen)
\tcheck("  ตัวเก่งทั้ง 3 อยู่ในคอก", pen["full-bag-strong-1"] == 1 and pen["full-bag-strong-2"] == 1 and pen["full-bag-strong-3"] == 1, true)
\tcheck("ไม่มีแม่หาย", #data.mothersInPen + #data.mothersInBag, total)
\tcheck("ไม่มีแม่ซ้ำ", allUnique(data), true)
end

print("\\n━━ สวมใส่ที่ดีที่สุด: แม่ที่ล็อกถูกสลับได้ · แม่ใน roster ไม่ถูกแตะ ━━")
do
\tlocal player, data = freshPlayer("EquipBest3")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\ttable.clear(data.battleRoster)
\tlocal penCap = Config.getPenCapacity(data.penLevel)
\tfor i = 1, penCap do
\t\ttable.insert(data.mothersInPen, makeMother(`locked-weak-{i}`, "monkey", 100, { lastProducedAt = os.time(), locked = true }))
\tend
\ttable.insert(data.mothersInBag, makeMother("unlocked-strong", "monkey", 900000))
\ttable.insert(data.battleRoster, makeMother("roster-giant", "yulai", 100000000))

\tlocal ok, _, summary = EggService.autoFillPen(player)
\tcheck("สำเร็จ", ok)
\tcheck("  สลับ 1 คู่", summary and summary.movedIn == 1 and summary.movedOut == 1, true)
\tcheck("ตัวที่ออกไปยังล็อกอยู่ (ล็อกไม่กันการย้าย แต่ติดตัวไปด้วย)", data.mothersInBag[1].locked, true)
\tcheck("แม่ใน roster ยังอยู่ใน roster", #data.battleRoster, 1)
\tcheck("  ไม่ถูกดึงเข้าคอก", uidSet(data.mothersInPen)["roster-giant"] == nil, true)
\tcheck("ไม่มีแม่ซ้ำ", allUnique(data), true)
end

print("\\n━━ สวมใส่ที่ดีที่สุด: ไม่มีแม่เลย → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("EquipBest4")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\tlocal ok, reason = EggService.autoFillPen(player)
\tcheck("ปฏิเสธ", ok, false)
\tcheck("  เหตุผล", reason, "ไม่มีแม่ให้จัด")
end

'''

# UI-2: ขายแม่เป็นชุด (SellMothersBatchRequest) — raw string: แท็บจริง · \n ของ Luau ไม่ต้อง escape สองชั้น
CHECK_BATCH = r'''
--------------------------------------------------------------------------------
-- 2.6) ขายแม่เป็นชุด (UI-2 · SellMothersBatchRequest)
--------------------------------------------------------------------------------

local sellBatchHandler = capturedHandlers[Config.RemoteNames.SELL_MOTHERS_BATCH_REQUEST]
assert(sellBatchHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ SellMothersBatchRequest")

-- ผลล่าสุดที่ส่งกลับทาง ACTION_RESULT → (ok, message)
local function batchResult(player)
	local fired = firedTo(player, Config.RemoteNames.ACTION_RESULT)
	return fired and fired[1], fired and fired[2]
end
local function syncCount(player)
	return fireCount(player, Config.RemoteNames.FARM_STATE_SYNC)
end
local function resultCount(player)
	return fireCount(player, Config.RemoteNames.ACTION_RESULT)
end

-- แม่ชุดเดียวกันใส่ให้หลายผู้เล่นได้ (แต่ละคนมีอาเรย์ของตัวเอง)
local BATCH_MOTHERS = {
	{ "b-1", "wukong", 1500 },
	{ "b-2", "monkey", 100 },
	{ "b-3", "pig", 25000 },
	{ "b-4", "tang", 900 },
}
local function stockBag(data)
	table.clear(data.mothersInBag)
	for _, spec in BATCH_MOTHERS do
		table.insert(data.mothersInBag, makeMother(spec[1], spec[2], spec[3]))
	end
	data.currency.coins = 0
end
local function priceOf(data, weight)
	return Config.getMotherSellPrice(weight, data.wallProgress, {})
end

print("\n━━ ขายเป็นชุด: ยอดรวมตรงกับขายทีละตัว · sync + ข้อความสรุปครั้งเดียว ━━")
do
	local single, singleData = freshPlayer("BatchSingle")
	stockBag(singleData)
	for _, spec in BATCH_MOTHERS do
		pcall(sellMotherHandler, single, spec[1])
	end

	local batch, batchData = freshPlayer("BatchAll")
	stockBag(batchData)
	local syncBefore, resultBefore = syncCount(batch), resultCount(batch)
	local uids = {}
	for _, spec in BATCH_MOTHERS do
		table.insert(uids, spec[1])
	end
	local ok = pcall(sellBatchHandler, batch, uids)
	check("ไม่ error/crash", ok)
	local expected = 0
	for _, spec in BATCH_MOTHERS do
		expected += priceOf(batchData, spec[3])
	end
	check("ขายทีละตัวได้ตามสูตร", singleData.currency.coins, expected)
	check("ขายเป็นชุดได้เงินเท่าขายทีละตัวทุกตัวรวมกัน", batchData.currency.coins, singleData.currency.coins)
	check("กระเป๋าว่าง", #batchData.mothersInBag, 0)
	check("sync ครั้งเดียวต่อชุด (ไม่ใช่ทีละตัว)", syncCount(batch) - syncBefore, 1)
	check("ข้อความสรุปครั้งเดียว", resultCount(batch) - resultBefore, 1)
	local okResult, message = batchResult(batch)
	check("  ผลสำเร็จ", okResult, true)
	check("  ข้อความ = ขายแม่ N ตัว ได้ ฿X", message, `ขายแม่ 4 ตัว ได้ ฿{Config.formatCoins(expected)}`)
end

print("\n━━ ขายเป็นชุด: uid ซ้ำในชุดไม่ได้เงินซ้ำ ━━")
do
	local player, data = freshPlayer("BatchDup")
	stockBag(data)
	local expected = priceOf(data, 1500) + priceOf(data, 100)
	pcall(sellBatchHandler, player, { "b-1", "b-1", "b-2", "b-1" })
	check("ได้เงินของ b-1 + b-2 คนละครั้งเดียว", data.currency.coins, expected)
	check("เหลือในกระเป๋า 2 ตัว", #data.mothersInBag, 2)
	local _, message = batchResult(player)
	check("  ข้อความบอกว่าข้าม 2 ตัว (ตัวซ้ำ)", message, Config.formatSellBatchMessage(2, expected, 2))
end

print("\n━━ ขายเป็นชุด: แม่ล็อก / อยู่ในคอก / ของคนอื่น ถูกข้าม ตัวอื่นขายต่อ ━━")
do
	local _other, otherData = freshPlayer("BatchOther")
	table.clear(otherData.mothersInBag)
	table.insert(otherData.mothersInBag, makeMother("theirs", "wukong", 5000))

	local player, data = freshPlayer("BatchSkip")
	stockBag(data)
	data.mothersInBag[1].locked = true -- b-1
	table.clear(data.mothersInPen)
	table.insert(data.mothersInPen, makeMother("in-pen", "monkey", 300, { lastProducedAt = os.time() }))

	local ok = pcall(sellBatchHandler, player, { "b-1", "in-pen", "theirs", "b-2", "b-3" })
	check("ไม่ error/crash", ok)
	local expected = priceOf(data, 100) + priceOf(data, 25000)
	check("ขายได้เฉพาะ b-2 + b-3", data.currency.coins, expected)
	check("แม่ที่ล็อกยังอยู่ในกระเป๋า", data.mothersInBag[1] ~= nil and data.mothersInBag[1].uid == "b-1")
	check("แม่ในคอกไม่ถูกขาย", #data.mothersInPen, 1)
	check("แม่ของคนอื่นไม่ถูกแตะ", #otherData.mothersInBag, 1)
	local okResult, message = batchResult(player)
	check("  ผลสำเร็จ (ขายได้บางตัว)", okResult, true)
	check("  ข้อความบอกว่าข้าม 3 ตัว", message, Config.formatSellBatchMessage(2, expected, 3))
end

print("\n━━ ขายเป็นชุด: ขายไม่ได้สักตัว → ผลไม่สำเร็จ เงินไม่เปลี่ยน ━━")
do
	local player, data = freshPlayer("BatchNone")
	stockBag(data)
	for _, m in data.mothersInBag do
		m.locked = true
	end
	pcall(sellBatchHandler, player, { "b-1", "b-2" })
	check("เงินไม่เปลี่ยน", data.currency.coins, 0)
	check("แม่อยู่ครบ", #data.mothersInBag, #BATCH_MOTHERS)
	local okResult, message = batchResult(player)
	check("  ผลไม่สำเร็จ", okResult, false)
	check("  ข้อความ", message, "ขายไม่ได้สักตัว · ข้าม 2 ตัว (ล็อก / ไม่อยู่ในกระเป๋า / ซ้ำ)")
end

print("\n━━ ขายเป็นชุด: เกินความจุกระเป๋า → ปฏิเสธทั้งชุด ━━")
do
	local player, data = freshPlayer("BatchOver")
	stockBag(data)
	local uids = { "b-1", "b-2" }
	for i = 1, Config.Balance.Bag.CAPACITY - 1 do
		table.insert(uids, `ghost-{i}`)
	end
	local syncBefore = syncCount(player)
	pcall(sellBatchHandler, player, uids)
	check("ส่งมา 101 ตัว (> ความจุ 100)", #uids, Config.Balance.Bag.CAPACITY + 1)
	check("ไม่ขายสักตัว แม้ b-1/b-2 จะขายได้", #data.mothersInBag, #BATCH_MOTHERS)
	check("เงินไม่เปลี่ยน", data.currency.coins, 0)
	check("ปฏิเสธแล้วไม่ sync", syncCount(player) - syncBefore, 0)
	local okResult = batchResult(player)
	check("  ผลไม่สำเร็จ", okResult, false)

	local exact = {}
	for i = 1, Config.Balance.Bag.CAPACITY do
		table.insert(exact, if i <= 2 then `b-{i}` else `ghost-{i}`)
	end
	pcall(sellBatchHandler, player, exact)
	check("ส่งมาพอดีความจุ → รับ (ขาย b-1/b-2 · ข้ามที่เหลือ)", #data.mothersInBag, #BATCH_MOTHERS - 2)
end

print("\n━━ ขายเป็นชุด: ข้อมูลขยะ → ปฏิเสธทั้งชุด ไม่ขายสักตัว ━━")
do
	local player, data = freshPlayer("BatchJunk")
	local junk = {
		{ "string", "b-1" },
		{ "number", 42 },
		{ "nil", nil },
		{ "boolean", true },
		{ "array ว่าง", {} },
		{ "key เป็น string", { a = "b-1" } },
		{ "array ปน key string", { "b-1", extra = "b-2" } },
		{ "มีรู", { [1] = "b-1", [3] = "b-2" } },
		{ "สมาชิกเป็นตัวเลข", { "b-1", 5 } },
		{ "สมาชิกเป็น table", { "b-1", { "b-2" } } },
		{ "key ทศนิยม", { [1] = "b-1", [1.5] = "b-2" } },
	}
	for _, case in junk do
		stockBag(data)
		local ok = pcall(sellBatchHandler, player, case[2])
		check(`{case[1]}: ไม่ error/crash`, ok)
		check(`  {case[1]}: ไม่ขายสักตัว`, #data.mothersInBag == #BATCH_MOTHERS and data.currency.coins == 0)
		local okResult = batchResult(player)
		check(`  {case[1]}: ผลไม่สำเร็จ`, okResult, false)
	end
end

'''

# UI-3: ส่งแม่ไปรบเป็นชุด (SendMothersToBattleBatchRequest) — ต่อสายจริงผ่าน EggService.start()
CHECK_SEND_BATCH = r'''
--------------------------------------------------------------------------------
-- 2.7) ส่งแม่ไปรบเป็นชุด (UI-3 · SendMothersToBattleBatchRequest)
--------------------------------------------------------------------------------

local sendBatchHandler = capturedHandlers[Config.RemoteNames.SEND_MOTHERS_TO_BATTLE_BATCH_REQUEST]
assert(sendBatchHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ SendMothersToBattleBatchRequest")

-- ผู้เล่นที่ผ่านด่าน 1 (ว่าง) แล้ว กำลังตีด่าน 2 · กระเป๋ามีแม่ s-1..s-n
local function sendReady(tag, count)
	local player, data = freshPlayer(tag)
	data.stageProgress[1] = { defendersRemaining = 0, wallHpRemaining = 0 }
	CombatService.ensureStageStarted(data, 2)
	table.clear(data.mothersInBag)
	table.clear(data.battleRoster)
	for i = 1, count do
		table.insert(data.mothersInBag, makeMother(`s-{i}`, "monkey", 100 * i))
	end
	return player, data
end
local function rosterUids(data)
	local list = {}
	for _, m in data.battleRoster do
		table.insert(list, m.uid)
	end
	return table.concat(list, ",")
end

print("\n━━ ส่งเป็นชุด: ผลเท่ากับส่งทีละตัว · sync + ข้อความสรุปครั้งเดียว ━━")
do
	local single, singleData = sendReady("SendSingle", 4)
	for _, uid in { "s-3", "s-1", "s-4" } do
		pcall(sendToBattleHandler, single, uid)
	end

	local batch, batchData = sendReady("SendBatch", 4)
	local syncBefore, resultBefore = syncCount(batch), resultCount(batch)
	local ok = pcall(sendBatchHandler, batch, { "s-3", "s-1", "s-4" })
	check("ไม่ error/crash", ok)
	check("roster ตรงกับส่งทีละตัว (ลำดับด้วย)", rosterUids(batchData), rosterUids(singleData))
	check("  roster = s-3,s-1,s-4 ตามลำดับที่ส่ง", rosterUids(batchData), "s-3,s-1,s-4")
	check("กระเป๋าเหลือ s-2 เหมือนส่งทีละตัว", batchData.mothersInBag[1] and batchData.mothersInBag[1].uid, "s-2")
	check("sync ครั้งเดียวต่อชุด (ไม่ใช่ทีละตัว)", syncCount(batch) - syncBefore, 1)
	check("ข้อความสรุปครั้งเดียว", resultCount(batch) - resultBefore, 1)
	local okResult, message = batchResult(batch)
	check("  ผลสำเร็จ", okResult, true)
	check("  ข้อความ = ส่งแม่ N ตัวไปรบ (roster X/10)", message, Config.formatSendBatchMessage(3, 3, 0))
end

print("\n━━ ส่งเป็นชุด: ในสนามแล้ว 5 ส่งเพิ่ม 10 → roster ไม่เกิน 10 ━━")
do
	local player, data = sendReady("SendCap", 15)
	local first = {}
	for i = 1, 5 do
		table.insert(first, `s-{i}`)
	end
	pcall(sendBatchHandler, player, first)
	check("ในสนาม 5 ตัว", #data.battleRoster, 5)
	local more = {}
	for i = 6, 15 do
		table.insert(more, `s-{i}`)
	end
	pcall(sendBatchHandler, player, more)
	check("roster = 10 พอดี", #data.battleRoster, Config.Balance.Combat.MAX_BATTLE_MOTHERS)
	check("ตัวที่ล้น 5 ตัวยังอยู่ในกระเป๋า", #data.mothersInBag, 5)
	local _, message = batchResult(player)
	check("  ข้อความบอกส่ง 5 ข้าม 5", message, Config.formatSendBatchMessage(5, 10, 5))
end

print("\n━━ ส่งเป็นชุด: แม่ล็อก / อยู่ในคอก / ของคนอื่น / uid ซ้ำ ถูกข้าม ━━")
do
	local _other, otherData = freshPlayer("SendOther")
	table.clear(otherData.mothersInBag)
	table.insert(otherData.mothersInBag, makeMother("their-mom", "wukong", 5000))

	local player, data = sendReady("SendSkip", 3)
	data.mothersInBag[1].locked = true -- s-1
	table.clear(data.mothersInPen)
	table.insert(data.mothersInPen, makeMother("pen-mom", "monkey", 300, { lastProducedAt = os.time() }))

	local ok = pcall(sendBatchHandler, player, { "s-1", "pen-mom", "their-mom", "s-2", "s-2", "s-3" })
	check("ไม่ error/crash", ok)
	check("roster = s-2,s-3", rosterUids(data), "s-2,s-3")
	check("แม่ล็อกยังอยู่ในกระเป๋า", data.mothersInBag[1] and data.mothersInBag[1].uid, "s-1")
	check("แม่ในคอกยังอยู่ในคอก", #data.mothersInPen, 1)
	check("แม่ของคนอื่นไม่ถูกแตะ", #otherData.mothersInBag, 1)
	local okResult, message = batchResult(player)
	check("  ผลสำเร็จ (ส่งได้บางตัว)", okResult, true)
	check("  ข้อความบอกว่าข้าม 4 ตัว", message, Config.formatSendBatchMessage(2, 2, 4))
end

print("\n━━ ส่งเป็นชุด: ด่านที่กำลังตี HP 0 / ผ่านครบทุกด่าน → ปฏิเสธทั้งชุด ไม่ sync ━━")
do
	local player, data = freshPlayer("SendStage1")
	table.clear(data.mothersInBag)
	table.clear(data.battleRoster)
	table.insert(data.mothersInBag, makeMother("z-1", "monkey", 100))
	local syncBefore = syncCount(player)
	pcall(sendBatchHandler, player, { "z-1" })
	check("ด่าน 1 (HP 0) → ไม่ส่ง", #data.battleRoster, 0)
	check("  ไม่ sync", syncCount(player) - syncBefore, 0)
	local okResult, message = batchResult(player)
	check("  ผลไม่สำเร็จ", okResult, false)
	check("  ข้อความบอกด่าน 1 ไม่มีศัตรู", message, "ด่าน 1 ไม่มีศัตรูให้ตี — เปิดอัญเชิญให้ผ่านด่านนี้ไปก่อน")

	for stage = 1, Config.Balance.Stage.COUNT do
		data.stageProgress[stage] = { defendersRemaining = 0, wallHpRemaining = 0 }
	end
	pcall(sendBatchHandler, player, { "z-1" })
	check("ผ่านครบทุกด่าน → ไม่ส่ง", #data.battleRoster, 0)
	local okAll, messageAll = batchResult(player)
	check("  ผลไม่สำเร็จ", okAll, false)
	check("  ข้อความ", messageAll, "ผ่านครบทุกด่านแล้ว ไม่มีด่านให้ส่งแม่ไปรบ")
end

print("\n━━ sync (UI-3): พลังต่อตัวของกองลูก + กองที่ติ๊กไว้แต่หมด (รอผลิต) ━━")
do
	local player, data = freshPlayer("SyncWaiting")
	table.clear(data.mothersInPen)
	local penMom = makeMother("pen-a", "wukong", 1500, { lastProducedAt = os.time() })
	table.insert(data.mothersInPen, penMom)
	local keyPen = Config.makeStackKey("wukong", 1500, {})
	local keyGone = Config.makeStackKey("pig", 800, {}) -- ไม่มีแม่ผลิตเติมแล้ว
	local keyStock = Config.makeStackKey("monkey", 100, {})
	table.clear(data.children)
	data.children[keyStock] = 12
	data.releaseOrder = { keyPen, keyGone, keyStock }
	data.damageLevel = 3
	EggService.sync(player)
	local payload = firedTo(player, Config.RemoteNames.FARM_STATE_SYNC)[1]
	local waiting = payload.waitingStacks or {}
	check("กองที่ติ๊กไว้ + หมด + แม่ในคอกผลิตเติม → อยู่ใน waitingStacks", #waiting == 1 and waiting[1].key == keyPen, true)
	check("  count = 0", waiting[1] and waiting[1].count, 0)
	check("  กองที่หมดและไม่มีแม่ผลิตเติม → ไม่ส่ง", #waiting, 1)
	local stock = nil
	for _, stack in payload.children do
		if stack.key == keyStock then
			stock = stack
		end
	end
	local expected = Config.computeBattlePower(Config.getChildWeight(100, {}), "monkey", {}, 3)
	check("children มี power = computeBattlePower (รวม damageLevel)", stock and stock.power, expected)
	check("  มี charId ให้วาดรูป", stock and stock.charId, "monkey")
	check("กองที่มีของไม่ซ้ำใน waitingStacks", waiting[1] and waiting[1].key ~= keyStock, true)
	check("ผู้เล่นใหม่ (ด่าน 1 ไม่มีศัตรู) → sync บอกเหตุผลที่ส่งแม่ไม่ได้", payload.sendStageBlockReason,
		"ด่าน 1 ไม่มีศัตรูให้ตี — เปิดอัญเชิญให้ผ่านด่านนี้ไปก่อน")

	table.insert(data.battleRoster, makeMother("field-1", "tang", 900))
	EggService.sync(player)
	local roster = firedTo(player, Config.RemoteNames.FARM_STATE_SYNC)[1].battleRoster
	local character = Config.getCharacter("tang")
	check("battleRoster ใน sync มีชื่อ/คลาส/น้ำหนักพร้อมโชว์", roster[1] and `{roster[1].charName}/{roster[1].class}/{roster[1].weightText}`,
		`{character.name}/{character.class}/{Config.formatWeight(900)}`)
end

print("\n━━ ส่งเป็นชุด: ข้อมูลขยะ → ปฏิเสธทั้งชุด ไม่ส่งสักตัว ━━")
do
	local player, data = sendReady("SendJunk", 2)
	local eleven = {}
	for i = 1, Config.Balance.Combat.MAX_BATTLE_MOTHERS + 1 do
		table.insert(eleven, if i <= 2 then `s-{i}` else `ghost-{i}`)
	end
	local junk = {
		{ "string", "s-1" },
		{ "number", 42 },
		{ "nil", nil },
		{ "array ว่าง", {} },
		{ "key เป็น string", { a = "s-1" } },
		{ "มีรู", { [1] = "s-1", [3] = "s-2" } },
		{ "สมาชิกเป็นตัวเลข", { "s-1", 5 } },
		{ "เกิน 10 ตัว", eleven },
	}
	for _, case in junk do
		local syncBefore = syncCount(player)
		local ok = pcall(sendBatchHandler, player, case[2])
		check(`{case[1]}: ไม่ error/crash`, ok)
		check(`  {case[1]}: ไม่ส่งสักตัว`, #data.battleRoster == 0 and #data.mothersInBag == 2)
		check(`  {case[1]}: ไม่ sync`, syncCount(player) - syncBefore, 0)
		local okResult = batchResult(player)
		check(`  {case[1]}: ผลไม่สำเร็จ`, okResult, false)
	end
end

'''

FOOTER = '''
print(string.format("\\n=== ผ่าน %d / ตก %d ===", passCount, failCount))
if failCount > 0 then
\terror(`มีเทสต์ตก {failCount} เคส`, 0)
end
'''


# ⚠️ ถอดบรรทัด require/GetService ของ Roblox ออก **แบบต้องเจอจริง** — ถ้าซอร์สเปลี่ยนจนหาไม่เจอ
# ให้พังดัง ๆ ตรงนี้ ไม่ใช่ replace เงียบ ๆ แล้วไปพังเป็น "attempt to index nil" ใน luau ทีหลัง
# และหลังถอดแล้วต้องไม่เหลือ require/GetService ของ Roblox ในโค้ดเลย (นอกคอมเมนต์) — เคยพังเงียบมา
# นานเพราะ EggService เพิ่ม `require(ServerScriptService.CombatService)` (Phase 3A) แต่ harness ไม่รู้จัก
def strip_roblox_imports(src: str, lines: list, name: str) -> str:
    for line in lines:
        if src.count(line) != 1:
            sys.exit(f'harness ตามซอร์สไม่ทัน: หาบรรทัดนี้ใน {name} ไม่เจอ (หรือเจอซ้ำ) — {line!r}')
        src = src.replace(line, '')
    for number, raw in enumerate(src.split('\n'), 1):
        code = raw.split('--', 1)[0]
        if 'require(' in code or 'game:GetService(' in code:
            sys.exit(f'harness ตามซอร์สไม่ทัน: {name} ยังมี require/GetService ที่ harness ไม่ได้เตรียมของให้ — {raw.strip()!r}')
    return src


def build_harness() -> str:
    src = open(os.path.join(ROOT, 'src/server/EggService.lua'), encoding='utf-8').read()
    src = strip_roblox_imports(src, [
        'local Players = game:GetService("Players")',
        'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
        'local ServerScriptService = game:GetService("ServerScriptService")',
        'local Config = require(ReplicatedStorage.Shared.Config)',
        'local PlayerData = require(ReplicatedStorage.Shared.PlayerData)',
        'local Remotes = require(ReplicatedStorage.Shared.Remotes)',
        'local DataService = require(ServerScriptService.DataService)',
        'local PenService = require(ServerScriptService.PenService)',
        'local ProductionService = require(ServerScriptService.ProductionService)',
        'local CombatService = require(ServerScriptService.CombatService)',
    ], 'EggService.lua')
    src = src.replace('--!strict', '--!nocheck' + PRELUDE)

    escaped = src.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    check = (CHECK + CHECK_BATCH + CHECK_SEND_BATCH + FOOTER).replace('__EGGSERVICE_SOURCE', f'"{escaped}"')
    return STUB + check


# ⚠️ ประกอบ harness ให้เสร็จก่อนค่อยเปิดไฟล์ — ถ้า build_harness() หยุดกลางทาง (ตามซอร์สไม่ทัน)
# จะได้ไม่ทิ้งไฟล์ว่าง .pen-mother-economy-check.luau ค้างไว้ในโฟลเดอร์โปรเจกต์
harness_source = build_harness()
harness = os.path.join(ROOT, '.pen-mother-economy-check.luau')
with open(harness, 'w', encoding='utf-8') as f:
    f.write(harness_source)

try:
    proc = subprocess.run([LUAU, harness], capture_output=True, text=True, cwd=ROOT)
finally:
    os.remove(harness)

print(proc.stdout)
if proc.returncode != 0:
    print(proc.stderr, file=sys.stderr)
    sys.exit(1)
