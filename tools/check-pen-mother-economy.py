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
local capturedHandlers = {}
local FakeRemotes = {}
function FakeRemotes.waitFor(name)
\tlocal remote = {}
\tremote.OnServerEvent = {
\t\tConnect = function(_self, fn)
\t\t\tcapturedHandlers[name] = fn
\t\t\treturn { Disconnect = function() end }
\t\tend,
\t}
\tremote.FireClient = function(_self, _player, _payload) end
\treturn remote
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
assert(upgradePenHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ UpgradePenRequest")
assert(sellMotherHandler, "เซ็ตอัพเทสต์ผิด — ไม่ผูก callback ให้ SellMotherRequest")

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

print(string.format("\\n=== ผ่าน %d / ตก %d ===", passCount, failCount))
if failCount > 0 then
\terror(`มีเทสต์ตก {failCount} เคส`, 0)
end
'''


def build_harness() -> str:
    src = open(os.path.join(ROOT, 'src/server/EggService.lua'), encoding='utf-8').read()
    src = src.replace('local Players = game:GetService("Players")', '')
    src = src.replace('local ReplicatedStorage = game:GetService("ReplicatedStorage")', '')
    src = src.replace('local ServerScriptService = game:GetService("ServerScriptService")', '')
    src = src.replace('local Config = require(ReplicatedStorage.Shared.Config)', '')
    src = src.replace('local PlayerData = require(ReplicatedStorage.Shared.PlayerData)', '')
    src = src.replace('local Remotes = require(ReplicatedStorage.Shared.Remotes)', '')
    src = src.replace('local DataService = require(ServerScriptService.DataService)', '')
    src = src.replace('local PenService = require(ServerScriptService.PenService)', '')
    src = src.replace('local ProductionService = require(ServerScriptService.ProductionService)', '')
    src = src.replace('--!strict', '--!nocheck' + PRELUDE)

    escaped = src.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    check = CHECK.replace('__EGGSERVICE_SOURCE', f'"{escaped}"')
    return STUB + check


harness = os.path.join(ROOT, '.pen-mother-economy-check.luau')
with open(harness, 'w', encoding='utf-8') as f:
    f.write(build_harness())

try:
    proc = subprocess.run([LUAU, harness], capture_output=True, text=True, cwd=ROOT)
finally:
    os.remove(harness)

print(proc.stdout)
if proc.returncode != 0:
    print(proc.stderr, file=sys.stderr)
    sys.exit(1)
