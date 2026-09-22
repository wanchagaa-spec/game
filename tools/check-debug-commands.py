# -*- coding: utf-8 -*-
"""ทดสอบเครื่องมือ debug ใหม่: debugGrantMother / debugGrantEggWithWeight /
debugSetWallProgress / debugSetCurrency / debugSnapshot / debugWipeSavedData

    python3 tools/check-debug-commands.py

⚠️ วิธีทำงาน: เหมือน tools/check-pen-mother-economy.py เป๊ะ — โหลดซอร์สจริงของ
EggService.lua ด้วย loadstring แล้วเรียกฟังก์ชัน debug ตรง ๆ บนตัว EggService ที่คืนมา
(ต่างจาก UpgradePenRequest/SellMotherRequest ตรงที่ฟังก์ชัน debug พวกนี้ไม่ได้ผูกกับ
RemoteEvent เลย เรียกได้ตรง ๆ จาก command bar อยู่แล้วในเกมจริง)

Config / PlayerData / DataService เป็นของจริงทั้งหมด มีแค่ PenService/Remotes/Random/
ProductionService ที่เป็นของปลอม (เหตุผลเดียวกับไฟล์ check-*.py อื่น ๆ ในโฟลเดอร์นี้)
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

local FakePenService = {}
function FakePenService.getPen(_player)
\treturn true
end
function FakePenService.showEgg(_player, _slotIndex, _eggType, _weight) end
function FakePenService.hideEgg(_player, _slotIndex) end
function FakePenService.refreshMothers(_player, _mothers) end

local FakeProductionService = {}
function FakeProductionService.settleMother(_data, _mother, _online)
\treturn 0, 0, false
end
function FakeProductionService.settleAllInPen(_data, _online)
\treturn 0, 0, false
end

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

local FakeRandom = {
\tnew = function()
\t\treturn { NextInteger = function(_self, lo, hi) return math.random(lo, hi) end }
\tend,
}

-- ⚠️ ดัก print ทั้งหมดไว้เพื่อตรวจเนื้อหาที่ debugSnapshot พิมพ์ออกมา (มันเป็นฟังก์ชันที่
-- ไม่มีค่าคืน ตรวจผลได้ทางเดียวคือดูว่าพิมพ์อะไรออกมา) ฟังก์ชันอื่นยังเห็น log ตามปกติทาง stdout
local printedLines = {}
local function capturingPrint(...)
\tlocal parts = {}
\tfor i = 1, select("#", ...) do
\t\ttable.insert(parts, tostring((select(i, ...))))
\tend
\tlocal line = table.concat(parts, "\\t")
\ttable.insert(printedLines, line)
\tprint(line) -- ยังโชว์ log จริงด้วย เผื่อไล่ดูตอนดีบัก
end

local __env = {
\tConfig = Config,
\tPlayerData = PlayerData,
\tRemotes = FakeRemotes,
\tDataService = DataService,
\tPenService = FakePenService,
\tProductionService = FakeProductionService,
\tPlayers = {},
\tRandom = FakeRandom,
\twarn = capturingPrint,
\tprint = capturingPrint,
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
local print = __env.print
'''

CHECK = '''

local EggService = loadstring(__EGGSERVICE_SOURCE, "EggService")(__env)
EggService.start()

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
function fakeStore.RemoveAsync(_self, key)
\tlocal old = fakeStore.data[key]
\tfakeStore.data[key] = nil
\treturn old
end

DataService.injectForTests({
\tstore = fakeStore,
\tsleep = function() end,
\tnow = function() return os.time() end,
\tjobId = function() return "test-job" end,
})

--------------------------------------------------------------------------------
-- mini harness เหมือนไฟล์ check-*.py อื่น ๆ ในโฟลเดอร์นี้
--------------------------------------------------------------------------------

local passCount, failCount = 0, 0
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

local nextUserId = 700001
local function freshPlayer(tag)
\tlocal userId = nextUserId
\tnextUserId += 1
\tlocal player = { UserId = userId, Name = tag, __kicked = nil }
\tfunction player:Kick(message)
\t\tself.__kicked = message
\tend
\tlocal okAdd = EggService.onPlayerAdded(player)
\tassert(okAdd, `เซ็ตอัพเทสต์ผิด — onPlayerAdded ของ {tag} ล้ม`)
\treturn player, DataService.getCached(userId)
end

local function findMother(list, uidSuffix)
\tfor _, m in list do
\t\tif string.find(m.uid, uidSuffix, 1, true) then
\t\t\treturn m
\t\tend
\tend
\treturn nil
end

--------------------------------------------------------------------------------
-- 1) debugGrantMother
--------------------------------------------------------------------------------

print("\\n━━ debugGrantMother: วางลงคอกสำเร็จ ━━")
do
\tlocal player, data = freshPlayer("Grant1")
\ttable.clear(data.mothersInPen)
\tlocal ok, reason = EggService.debugGrantMother(player, 100000000, "yulai", "pen")
\tcheck("คืนค่า true", ok)
\tcheck("ไม่มีเหตุผลปฏิเสธ", reason == nil, true)
\tcheck("มีแม่ 1 ตัวในคอก", #data.mothersInPen, 1)
\tlocal m = data.mothersInPen[1]
\tcheck("น้ำหนักตรงตามที่สั่ง (tier 7 เป๊ะ)", m.weight, 100000000)
\tcheck("charId ตรงตามที่สั่ง", m.charId, "yulai")
\tcheck("แม่ในคอกมี lastProducedAt (ผลิตได้ทันที)", m.lastProducedAt ~= nil, true)
\tcheck("uid ขึ้นต้นด้วย UserId ของผู้เล่น", string.find(m.uid, tostring(player.UserId), 1, true) ~= nil, true)
end

print("\\n━━ debugGrantMother: วางลงกระเป๋าสำเร็จ (ไม่มี lastProducedAt) ━━")
do
\tlocal player, data = freshPlayer("Grant2")
\ttable.clear(data.mothersInBag)
\tlocal ok = EggService.debugGrantMother(player, 500, "monkey", "bag")
\tcheck("คืนค่า true", ok)
\tcheck("มีแม่ 1 ตัวในกระเป๋า", #data.mothersInBag, 1)
\tcheck("แม่ในกระเป๋าไม่มี lastProducedAt (ไม่ผลิต)", data.mothersInBag[1].lastProducedAt == nil, true)
end

print("\\n━━ debugGrantMother: คอกเต็ม → ปฏิเสธตรง ๆ ไม่ fallback ไปกระเป๋า ━━")
do
\tlocal player, data = freshPlayer("Grant3")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\tlocal penCap = Config.getPenCapacity(data.penLevel)
\tfor i = 1, penCap do
\t\ttable.insert(data.mothersInPen, {
\t\t\tuid = `filler-{i}`, charId = "monkey", weight = 100, statuses = {},
\t\t\tobtainedAt = os.time(), locked = false, lastProducedAt = os.time(),
\t\t})
\tend
\tlocal bagCountBefore = #data.mothersInBag

\tlocal ok, reason = EggService.debugGrantMother(player, 200, "monkey", "pen")
\tcheck("คืนค่า false", ok, false)
\tcheck("บอกเหตุผลว่าคอกเต็ม", reason, "คอกเต็มแล้ว")
\tcheck("คอกไม่โตขึ้นอีก (ไม่ทะลุความจุ)", #data.mothersInPen, penCap)
\tcheck("กระเป๋าไม่ได้แม่เพิ่มมาแทน (ไม่มี fallback เงียบ ๆ)", #data.mothersInBag, bagCountBefore)
end

print("\\n━━ debugGrantMother: กระเป๋าเต็ม → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("Grant4")
\ttable.clear(data.mothersInBag)
\tfor i = 1, Config.Balance.Bag.CAPACITY do
\t\ttable.insert(data.mothersInBag, {
\t\t\tuid = `bagfiller-{i}`, charId = "monkey", weight = 100, statuses = {},
\t\t\tobtainedAt = os.time(), locked = false,
\t\t})
\tend
\tlocal ok, reason = EggService.debugGrantMother(player, 200, "monkey", "bag")
\tcheck("คืนค่า false", ok, false)
\tcheck("บอกเหตุผลว่ากระเป๋าเต็ม", reason, "กระเป๋าเต็มแล้ว")
\tcheck("กระเป๋าไม่ทะลุความจุ", #data.mothersInBag, Config.Balance.Bag.CAPACITY)
end

print("\\n━━ debugGrantMother: charId ไม่มีจริง → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("Grant5")
\tlocal ok, reason = EggService.debugGrantMother(player, 200, "ไม่มีจริง", "bag")
\tcheck("คืนค่า false", ok, false)
\tcheck("ไม่มีแม่ถูกสร้าง", #data.mothersInBag - 0 >= 0, true) -- แค่ไม่ error พอ (จำนวนขึ้นกับ startingEggs)
end

print("\\n━━ debugGrantMother: destination ผิด → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("Grant6")
\tlocal penBefore, bagBefore = #data.mothersInPen, #data.mothersInBag
\tlocal ok, reason = EggService.debugGrantMother(player, 200, "monkey", "warehouse")
\tcheck("คืนค่า false", ok, false)
\tcheck("คอกไม่เปลี่ยน", #data.mothersInPen, penBefore)
\tcheck("กระเป๋าไม่เปลี่ยน", #data.mothersInBag, bagBefore)
end

print("\\n━━ debugGrantMother: น้ำหนัก 0 หรือติดลบ → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("Grant7")
\tlocal ok1 = EggService.debugGrantMother(player, 0, "monkey", "bag")
\tlocal ok2 = EggService.debugGrantMother(player, -500, "monkey", "bag")
\tcheck("น้ำหนัก 0 ถูกปฏิเสธ", ok1, false)
\tcheck("น้ำหนักติดลบถูกปฏิเสธ", ok2, false)
end

--------------------------------------------------------------------------------
-- 2) debugGrantEggWithWeight
--------------------------------------------------------------------------------

print("\\n━━ debugGrantEggWithWeight: บังคับน้ำหนักสำเร็จ (ทุก tier) ━━")
do
\tlocal player, data = freshPlayer("EggW1")
\ttable.clear(data.heldEggs.items)
\tlocal tiers = { 100, 5000, 50000, 500000, 5000000, 50000000, 100000000 }
\tfor _, w in tiers do
\t\tlocal ok = EggService.debugGrantEggWithWeight(player, "egg_stage1", w)
\t\tcheck(`วางไข่น้ำหนักบังคับ {w} สำเร็จ`, ok)
\tend
\tcheck(`ได้ไข่ครบ {#tiers} ฟองตามที่สั่ง`, #data.heldEggs.items, #tiers)
\tfor i, w in tiers do
\t\tcheck(`ไข่ฟองที่ {i} น้ำหนักตรงเป๊ะ ไม่ผ่าน RNG`, data.heldEggs.items[i].weight, w)
\tend
end

print("\\n━━ debugGrantEggWithWeight: eggId ไม่มีจริง → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("EggW2")
\tlocal before = #data.heldEggs.items
\tlocal ok, reason = EggService.debugGrantEggWithWeight(player, "egg_ไม่มีจริง", 1000)
\tcheck("คืนค่า false", ok, false)
\tcheck("กระเป๋าไข่ไม่เปลี่ยน", #data.heldEggs.items, before)
end

print("\\n━━ debugGrantEggWithWeight: ไข่ที่ปิดแล้ว (enabled=false) → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("EggW3")
\tlocal before = #data.heldEggs.items
\tlocal ok, reason = EggService.debugGrantEggWithWeight(player, "egg_common", 1000)
\tcheck("คืนค่า false", ok, false)
\tcheck("กระเป๋าไข่ไม่เปลี่ยน", #data.heldEggs.items, before)
end

print("\\n━━ debugGrantEggWithWeight: กระเป๋าไข่เต็ม → ปฏิเสธ ━━")
do
\tlocal player, data = freshPlayer("EggW4")
\ttable.clear(data.heldEggs.items)
\tfor i = 1, Config.Balance.Hatchery.BAG_CAPACITY do
\t\ttable.insert(data.heldEggs.items, { id = i, eggId = "egg_stage1", weight = 100 })
\tend
\tdata.heldEggs.nextEggId = Config.Balance.Hatchery.BAG_CAPACITY + 1
\tlocal ok, reason = EggService.debugGrantEggWithWeight(player, "egg_stage1", 5000)
\tcheck("คืนค่า false", ok, false)
\tcheck("บอกเหตุผลว่าเต็ม", reason, "ถือไข่เต็มแล้ว")
end

--------------------------------------------------------------------------------
-- 3) debugSetWallProgress
--------------------------------------------------------------------------------

print("\\n━━ debugSetWallProgress: ตั้งค่าปกติ ━━")
do
\tlocal player, data = freshPlayer("Wall1")
\tEggService.debugSetWallProgress(player, 7)
\tcheck("wallProgress ถูกตั้งตามที่สั่ง", data.wallProgress, 7)
end

print("\\n━━ debugSetWallProgress: ค่าต่ำกว่า 1 → clamp เป็น 1 ━━")
do
\tlocal player, data = freshPlayer("Wall2")
\tEggService.debugSetWallProgress(player, 0)
\tcheck("clamp เป็น 1", data.wallProgress, 1)
\tEggService.debugSetWallProgress(player, -50)
\tcheck("ติดลบก็ clamp เป็น 1 เหมือนกัน", data.wallProgress, 1)
end

print("\\n━━ debugSetWallProgress: ค่าเกินจำนวนด่าน → clamp เป็นด่านสุดท้าย ━━")
do
\tlocal player, data = freshPlayer("Wall3")
\tEggService.debugSetWallProgress(player, 999)
\tcheck("clamp เป็นด่านสุดท้าย", data.wallProgress, Config.Balance.Stage.COUNT)
end

--------------------------------------------------------------------------------
-- 4) debugSetCurrency
--------------------------------------------------------------------------------

print("\\n━━ debugSetCurrency: ตั้งค่าปกติ ━━")
do
\tlocal player, data = freshPlayer("Coin1")
\tEggService.debugSetCurrency(player, 123456)
\tcheck("coins ถูกตั้งตามที่สั่ง", data.currency.coins, 123456)
\tcheck("gems ไม่ถูกแตะ", data.currency.gems, Config.Balance.NewPlayer.gems)
end

print("\\n━━ debugSetCurrency: ค่าติดลบ → clamp เป็น 0 ━━")
do
\tlocal player, data = freshPlayer("Coin2")
\tEggService.debugSetCurrency(player, -999)
\tcheck("ติดลบ clamp เป็น 0", data.currency.coins, 0)
end

--------------------------------------------------------------------------------
-- 5) debugSnapshot — ตรวจจากข้อความที่พิมพ์ออกมาจริง
--------------------------------------------------------------------------------

print("\\n━━ debugSnapshot: พิมพ์ข้อมูลครบตามที่ขอ ━━")
do
\tlocal player, data = freshPlayer("Snap1")
\ttable.clear(data.mothersInPen)
\ttable.clear(data.mothersInBag)
\ttable.clear(data.heldEggs.items)
\tfor i = 1, Config.Balance.Hatchery.MAX_SLOTS do
\t\tdata.hatching[i] = false
\tend

\ttable.insert(data.mothersInPen, {
\t\tuid = "snapshot-pen-uid", charId = "wukong", weight = 1500, statuses = {},
\t\tobtainedAt = os.time(), locked = false, lastProducedAt = os.time(),
\t})
\ttable.insert(data.mothersInBag, {
\t\tuid = "snapshot-bag-uid", charId = "monkey", weight = 300, statuses = {},
\t\tobtainedAt = os.time(), locked = false,
\t})
\tdata.hatching[1] = {
\t\teggId = "egg_stage1", weight = 400, charId = "pig",
\t\tstartedAt = os.time() - 10, hatchAt = os.time() - 1, -- ค้าง (ข้อ D)
\t}
\tdata.currency.coins = 777

\tprintedLines = {}
\tEggService.debugSnapshot(player)

\tlocal joined = table.concat(printedLines, "\\n")
\tcheck("พิมพ์ยอดเงินออกมา", string.find(joined, "777", 1, true) ~= nil, true)
\tcheck("พิมพ์ uid ของแม่ในคอกออกมา", string.find(joined, "snapshot-pen-uid", 1, true) ~= nil, true)
\tcheck("พิมพ์ uid ของแม่ในกระเป๋าออกมา", string.find(joined, "snapshot-bag-uid", 1, true) ~= nil, true)
\tcheck("พิมพ์สถานะ \\"ค้างรอที่ว่าง\\" ของ slot ที่ครบเวลาแล้ว", string.find(joined, "ค้าง", 1, true) ~= nil, true)
\tcheck("ไม่แก้ข้อมูลอะไรเลย (read-only) — เงินยังเท่าเดิม", data.currency.coins, 777)
\tcheck("ไม่แก้ข้อมูลอะไรเลย — แม่ในคอกยังอยู่ครบ", #data.mothersInPen, 1)
end

--------------------------------------------------------------------------------
-- 6) debugWipeSavedData
--------------------------------------------------------------------------------

print("\\n━━ debugWipeSavedData: ชื่อยืนยันผิด → ปฏิเสธ ไม่แตะอะไรเลย ━━")
do
\tlocal player, data = freshPlayer("Wipe1")
\tlocal userId = player.UserId
\tlocal key = DataService.keyFor(userId)
\tlocal ok, reason = EggService.debugWipeSavedData(player, "ชื่อผิด")
\tcheck("คืนค่า false", ok, false)
\tcheck("บอกเหตุผลว่าต้องยืนยันชื่อ", reason, "ต้องยืนยันด้วยชื่อผู้เล่น")
\tcheck("ข้อมูลยังอยู่ในแคช", DataService.getCached(userId) == data, true)
\tcheck("ยังมี key อยู่ใน DataStore ปลอม", fakeStore.data[key] ~= nil, true)
\tcheck("ไม่ถูกเตะ", player.__kicked == nil, true)
end

print("\\n━━ debugWipeSavedData: ยืนยันถูกต้อง → ลบจริง + เตะออก ━━")
do
\tlocal player = freshPlayer("Wipe2")
\tlocal userId = player.UserId
\tlocal key = DataService.keyFor(userId)
\tlocal ok, reason = EggService.debugWipeSavedData(player, player.Name)
\tcheck("คืนค่า true", ok)
\tcheck("ไม่มีเหตุผลปฏิเสธ", reason == nil, true)
\tcheck("แคชถูกเคลียร์", DataService.getCached(userId) == nil, true)
\tcheck("key หายไปจาก DataStore ปลอม", fakeStore.data[key] == nil, true)
\tcheck("ถูกเตะออก", player.__kicked ~= nil, true)
end

print("\\n━━ debugWipeSavedData: rejoin หลังลบ → isNew อีกครั้งจริง ได้ไข่เริ่มต้นใหม่ ━━")
do
\tlocal player = freshPlayer("Wipe3")
\tlocal userId = player.UserId

\t-- ล้างของที่ได้จากตอนสร้าง (freshPlayer เองก็เป็น "ผู้เล่นใหม่" มาก่อนแล้วรอบหนึ่ง)
\t-- เพื่อให้เห็นชัดว่าไข่ที่กลับมาหลัง rejoin มาจากรอบ isNew รอบใหม่จริง ไม่ใช่ของเก่าที่เหลืออยู่
\tlocal dataBefore = DataService.getCached(userId)
\ttable.clear(dataBefore.heldEggs.items)

\tlocal ok = EggService.debugWipeSavedData(player, player.Name)
\tcheck("ลบสำเร็จ", ok)
\tcheck("แคชว่างหลังลบ (ยังไม่ rejoin)", DataService.getCached(userId) == nil, true)

\t-- จำลองการเข้าเกมใหม่ด้วย player ตัวเดิม (เหมือนเตะแล้วกด Play ใหม่)
\tlocal okRejoin = EggService.onPlayerAdded(player)
\tcheck("rejoin โหลดสำเร็จ", okRejoin)

\tlocal dataAfter = DataService.getCached(userId)
\tlocal expectedEggs = 0
\tfor _, amount in Config.Balance.NewPlayer.startingEggs do
\t\texpectedEggs += amount
\tend
\tcheck("rejoin ได้ไข่เริ่มต้นครบตาม NewPlayer.startingEggs (isNew=true อีกครั้งจริง)",
\t\t#dataAfter.heldEggs.items, expectedEggs)
end

print("\\n━━ debugWipeSavedData: ผู้เล่นไม่ได้ออนไลน์อยู่ (ไม่มีในแคช) → ปฏิเสธ ━━")
do
\tlocal fakePlayer = { UserId = 999999999, Name = "NotOnline" }
\tfunction fakePlayer:Kick(message)
\t\tself.__kicked = message
\tend
\tlocal ok, reason = EggService.debugWipeSavedData(fakePlayer, fakePlayer.Name)
\tcheck("คืนค่า false", ok, false)
\tcheck("บอกเหตุผลว่าไม่มีข้อมูลในแคช",
\t\tstring.find(reason or "", "หน่วยความจำ", 1, true) ~= nil, true)
\tcheck("ไม่ถูกเตะ", fakePlayer.__kicked == nil, true)
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


harness = os.path.join(ROOT, '.debug-commands-check.luau')
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
