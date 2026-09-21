# -*- coding: utf-8 -*-
"""ยิงตรงเข้า path จริงของ PlaceEggInHatcheryRequest ด้วย payload ผิดปกติ

    python3 tools/check-egg-placement-validation.py

ทำไมต้องมี: docs/phase-1.5-rework.md §8 เคยมีเช็คลิสต์ "validate heldIndex ครบ 5 กรณี"
ตั้งแต่ก่อน Phase 2A แต่ `heldIndex` ไม่มีในโค้ดแล้ว — Phase 2A เปลี่ยนกลไกจากตำแหน่ง (index)
เป็น id ประจำฟอง (eggId) ทั้งหมด ไฟล์นี้แทนที่เช็คลิสต์เก่าด้วยเทสต์อัตโนมัติจริงสำหรับ eggId

⚠️ วิธีทำงาน: โหลดซอร์สจริงของ EggService.lua ด้วย loadstring (แบบเดียวกับ
check-wallrenderer-singleton.py) แล้วเรียก EggService.start() จริง เพื่อดักจับ callback
ที่ผูกกับ `placeEggRequest.OnServerEvent:Connect(...)` ตัวจริง — เทสต์ยิงเข้า callback
ตัวนั้นตรง ๆ ไม่ได้เรียก EggService.placeEgg() ลอย ๆ เพื่อให้มั่นใจว่าถ้าใครแก้ remote handler
ทีหลังแล้วลืมเรียก validate เทสต์ชุดนี้จะจับได้ทันที

DataService / PlayerData / Config เป็นของจริงทั้งหมด (require ตรง ๆ ได้อยู่แล้วแบบเดียวกับ
tests/playerdata.spec.luau) มีแค่ PenService กับ Remotes ที่เป็นของปลอม เพราะ EggService.placeEgg
แตะแค่ PenService.getPen/showEgg ซึ่งไม่ใช่สิ่งที่เทสต์ชุดนี้ต้องการยืนยัน
"""
import os, re, subprocess, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAU = os.environ.get('LUAU') or shutil.which('luau')
if not LUAU:
    sys.exit('หา luau CLI ไม่เจอ — ติดตั้งแล้วใส่ใน PATH หรือสั่ง LUAU=/path/to/luau python3 ...')

# require ของจริง (เหมือน tests/playerdata.spec.luau) + fake PenService/Remotes ที่จับ callback
STUB = '''--!nocheck
local Config = require("./src/shared/Config")
local PlayerData = require("./src/shared/PlayerData")
local DataService = require("./src/server/DataService")

-- fake PenService — EggService.placeEgg แตะแค่ getPen (ต้องมีคอก) กับ showEgg (วาดไข่ในคอก)
-- ไม่ใช่สิ่งที่เทสต์ชุดนี้สนใจ ให้ผ่านเสมอ + ไม่ทำอะไรจริง
local FakePenService = {}
function FakePenService.getPen(_player)
\treturn true
end
function FakePenService.showEgg(_player, _slotIndex, _eggType) end
function FakePenService.hideEgg(_player, _slotIndex) end
function FakePenService.refreshMothers(_player, _mothers) end

-- fake Remotes — จุดสำคัญ: ต้องจับ callback ที่ EggService.start() ผูกไว้จริง ๆ
-- เพื่อยิงเข้า callback ตัวนั้นตรง ๆ ไม่ใช่เรียก EggService.placeEgg() legacy
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
-- EggService.lua เรียก Random.new() ตรง ๆ ตอนโหลดโมดูล ต้องมีของปลอมรองรับ
-- rollMotherWeight/rollCharacter ใช้แค่ NextInteger เท่านั้น (grep แล้ว)
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
\tPlayers = {},
\tRandom = FakeRandom,
\twarn = print, -- warn ไม่มีใน luau CLI (ดูคอมเมนต์เดียวกันใน DataService.lua)
\ttask = { spawn = function() end, wait = function() end }, -- ห้ามให้ลูปพื้นหลังทำงานจริงในเทสต์
}

'''

# --!strict ตัวจริงเปลี่ยนเป็น --!nocheck + prelude ที่แกะ __env ออกมาเป็น local ชื่อเดิมทุกตัว
PRELUDE = '''
local __env = ...
local Config = __env.Config
local PlayerData = __env.PlayerData
local Remotes = __env.Remotes
local DataService = __env.DataService
local PenService = __env.PenService
local Players = __env.Players
local Random = __env.Random
local warn = __env.warn
local task = __env.task
'''

CHECK = '''

local EggService = loadstring(__EGGSERVICE_SOURCE, "EggService")(__env)
EggService.start()

local placeEggHandler = capturedHandlers[Config.RemoteNames.PLACE_EGG_IN_HATCHERY_REQUEST]
assert(placeEggHandler, "เซ็ตอัพเทสต์ผิด — EggService.start() ไม่ผูก callback ให้ PlaceEggInHatcheryRequest")

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
local function check(label, ok)
\tif ok then
\t\tpassCount += 1
\t\tprint(`  ✓ {label}`)
\telse
\t\tfailCount += 1
\t\tprint(`  ✗ {label}`)
\tend
end

local HATCH_SLOTS = Config.Balance.Hatchery.MAX_SLOTS

local nextUserId = 900001
local function freshPlayer(tag)
\tlocal userId = nextUserId
\tnextUserId += 1
\tlocal player = { UserId = userId, Name = tag }
\tlocal okAdd = EggService.onPlayerAdded(player)
\tassert(okAdd, `เซ็ตอัพเทสต์ผิด — onPlayerAdded ของ {tag} ล้ม`)
\treturn player, DataService.getCached(userId)
end

-- แจกไข่ที่รู้ id แน่นอน (ไม่พึ่ง startingEggs ที่ผู้เล่นใหม่ได้อัตโนมัติ)
local function grantKnownEgg(player)
\tlocal okGrant = EggService.grantEgg(player, "egg_stage1")
\tassert(okGrant, "เซ็ตอัพเทสต์ผิด — grantEgg ล้ม")
\tlocal data = DataService.getCached(player.UserId)
\tlocal newest = data.heldEggs.items[#data.heldEggs.items]
\treturn newest.id
end

local function countHatchingSlots(data)
\tlocal n = 0
\tfor i = 1, HATCH_SLOTS do
\t\tif type(data.hatching[i]) == "table" then
\t\t\tn += 1
\t\tend
\tend
\treturn n
end

local function snapshot(data)
\treturn { held = #data.heldEggs.items, hatching = countHatchingSlots(data) }
end

local function sameSnapshot(a, b)
\treturn a.held == b.held and a.hatching == b.hatching
end

local function fireAndCheckRejected(label, player, data, rawEggId, rawSlotIndex)
\tlocal before = snapshot(data)
\tlocal pOk = pcall(placeEggHandler, player, rawEggId, rawSlotIndex)
\tcheck(`{label}: ไม่ error/crash`, pOk)
\tlocal after = snapshot(data)
\tcheck(`{label}: ข้อมูลไม่เปลี่ยน (ปฏิเสธเงียบ ๆ)`, sameSnapshot(before, after))
end

print("\\n━━ กรณีที่ 1: eggId = 0 ━━")
do
\tlocal player, data = freshPlayer("Case1")
\tgrantKnownEgg(player)
\tfireAndCheckRejected("eggId=0", player, data, 0, nil)
end

print("\\n━━ กรณีที่ 2: eggId ไม่เคยมีอยู่จริง (999999) ━━")
do
\tlocal player, data = freshPlayer("Case2")
\tgrantKnownEgg(player)
\tfireAndCheckRejected("eggId=999999", player, data, 999999, nil)
end

print("\\n━━ กรณีที่ 3: eggId เป็นทศนิยม (3.5) ━━")
do
\tlocal player, data = freshPlayer("Case3")
\tgrantKnownEgg(player)
\tfireAndCheckRejected("eggId=3.5", player, data, 3.5, nil)
end

print('\\n━━ กรณีที่ 4: eggId เป็น string ("abc") ━━')
do
\tlocal player, data = freshPlayer("Case4")
\tgrantKnownEgg(player)
\tfireAndCheckRejected('eggId="abc"', player, data, "abc", nil)
end

print("\\n━━ กรณีที่ 5: eggId = nil (ไม่ส่งอะไรเลย) ━━")
do
\tlocal player, data = freshPlayer("Case5")
\tgrantKnownEgg(player)
\tfireAndCheckRejected("eggId=nil", player, data, nil, nil)
end

print("\\n━━ กรณีที่ 6: eggId ติดลบ (-5) ━━")
do
\tlocal player, data = freshPlayer("Case6")
\tgrantKnownEgg(player)
\tfireAndCheckRejected("eggId=-5", player, data, -5, nil)
end

print("\\n━━ กรณีที่ 7: id เคยมีจริงแต่ถูกใช้ไปแล้ว (ใช้ซ้ำ) ━━")
do
\tlocal player, data = freshPlayer("Case7")
\tlocal eggId = grantKnownEgg(player)

\tlocal before1 = snapshot(data)
\tlocal pOk1 = pcall(placeEggHandler, player, eggId, nil)
\tcheck("รอบแรก: ไม่ error/crash", pOk1)
\tlocal after1 = snapshot(data)
\tcheck(
\t\t"รอบแรก: วางสำเร็จจริง (กระเป๋าลด 1 · สวนฟักเพิ่ม 1)",
\t\tafter1.held == before1.held - 1 and after1.hatching == before1.hatching + 1
\t)

\t-- เซฟแล้วจำลอง "เข้าเกมใหม่" — แค่รีเซ็ตนาฬิกากันสแปม (REQUEST_COOLDOWN 0.25 วิ ที่ os.time()
\t-- ความละเอียดวินาทีจะบล็อกยิงรัวสองครั้งติดกันในเทสต์เดียว) ไม่ใช่ช่องโหว่ที่ทำให้ id กลับมาใช้ได้
\tlocal saveOk = DataService.saveAsync(player.UserId, false)
\tcheck("เซฟหลังวางรอบแรกสำเร็จ", saveOk)
\tlocal rejoinOk = EggService.onPlayerAdded(player)
\tcheck("จำลองเข้าเกมใหม่สำเร็จ", rejoinOk)
\tdata = DataService.getCached(player.UserId)

\tlocal before2 = snapshot(data)
\tlocal pOk2 = pcall(placeEggHandler, player, eggId, nil)
\tcheck("รอบสอง (ใช้ id เดิมซ้ำ): ไม่ error/crash", pOk2)
\tlocal after2 = snapshot(data)
\tcheck("รอบสอง: ถูกปฏิเสธ ไม่มีอะไรเปลี่ยนอีก (id ไม่ถูก reuse)", sameSnapshot(before2, after2))
end

print("\\n━━ กรณีที่ 8: eggId ของผู้เล่นอีกคน (กัน exploit ข้าม account) ━━")
do
\tlocal playerA, dataA = freshPlayer("Case8A")
\tlocal eggIdOfA = grantKnownEgg(playerA)

\tlocal playerB, dataB = freshPlayer("Case8B")
\t-- ล้างกระเป๋า B ให้ชัวร์ว่าไม่มี id ชนกับของตัวเองโดยบังเอิญ (ผู้เล่นใหม่ได้ไข่เริ่มต้นด้วย
\t-- และ id เริ่มนับจาก 1 เหมือนกันทุกคน — ถ้าไม่ล้าง B อาจมี id เดียวกับ A เป็นของตัวเองจริง ๆ)
\ttable.clear(dataB.heldEggs.items)

\tlocal beforeA, beforeB = snapshot(dataA), snapshot(dataB)
\tlocal pOk = pcall(placeEggHandler, playerB, eggIdOfA, nil)
\tcheck("B ใช้ id ของ A: ไม่ error/crash", pOk)
\tlocal afterA, afterB = snapshot(dataA), snapshot(dataB)
\tcheck("B ใช้ id ของ A: กระเป๋า B ไม่เปลี่ยน (ถูกปฏิเสธ)", sameSnapshot(beforeB, afterB))
\tcheck("B ใช้ id ของ A: กระเป๋า A ไม่ถูกแตะเลย (ไข่ยังอยู่ที่เจ้าของ)", sameSnapshot(beforeA, afterA))
end

print("\\n━━ กรณีสุขภาพดี (control): eggId ที่ถูกต้องต้องผ่านจริง ━━")
do
\tlocal player, data = freshPlayer("CaseHappy")
\tlocal eggId = grantKnownEgg(player)
\tlocal before = snapshot(data)
\tlocal pOk = pcall(placeEggHandler, player, eggId, nil)
\tcheck("ไม่ error/crash", pOk)
\tlocal after = snapshot(data)
\tcheck(
\t\t"วางสำเร็จจริง (พิสูจน์ว่าเช็ค 'ข้อมูลไม่เปลี่ยน' ของ 8 กรณีข้างบนเชื่อถือได้ ไม่ใช่ false negative)",
\t\tafter.held == before.held - 1 and after.hatching == before.hatching + 1
\t)
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
    src = src.replace('--!strict', '--!nocheck' + PRELUDE)

    escaped = src.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    check = CHECK.replace('__EGGSERVICE_SOURCE', f'"{escaped}"')
    return STUB + check


harness = os.path.join(ROOT, '.egg-placement-check.luau')
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
