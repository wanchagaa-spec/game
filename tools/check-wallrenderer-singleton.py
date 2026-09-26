# -*- coding: utf-8 -*-
"""หาว่า WallRenderer ทนต่อการถูก require มา "คนละ ModuleScript instance" ไหม

    python3 tools/check-wallrenderer-singleton.py

ทำไมต้องมี: StarterPlayerScripts ถูก copy เป็น PlayerScripts ตอนผู้เล่นเข้าเกม
ทำให้มี ModuleScript ของ WallRenderer อย่างน้อย 2 instance อยู่จริงเสมอ — ตัวต้นฉบับใน
StarterPlayerScripts กับตัวที่ถูกก็อปมาที่ Main.client.lua require จริง (คนละ closure
คนละ `folder`/`currentProgress` กันคนละชุด) ถ้ามีใครสั่ง `require(...).setWallProgress(n)`
จากคนละ path (เช่น จาก command bar ที่ชี้ไปที่ StarterPlayerScripts ต้นฉบับตามที่ Explorer
โชว์ให้เห็นง่ายที่สุด) จะได้ log ว่าเปลี่ยนค่าสำเร็จ แต่กำแพงจริงที่ผู้เล่นยืนชนอยู่
(สร้างจาก instance ที่ Main.client.lua ใช้ตอนบูต) ไม่ถูกแตะเลยแม้แต่นิดเดียว

เคยเกิดมาแล้ว: `WallRenderer.setWallProgress(3)` รันสำเร็จ ไม่มี error, log ยืนยัน
"wallProgress = 3 · วาดกำแพง 6 ด่าน" แต่เดินชนกำแพงด่าน 2 เหมือนเดิมทุกอย่าง ไม่มีอะไรเปลี่ยน

⚠️ วิธีทำงาน: โหลดซอร์สจริงของ WallRenderer.lua ด้วย `loadstring` **สองรอบแยกกัน**
(จำลองสอง ModuleScript instance) แต่ให้ทั้งคู่ใช้ Workspace ปลอมก้อนเดียวกัน (เหมือน Roblox
จริงที่ Workspace เป็น service เดียวของทั้งเกม ไม่ได้ถูกก็อปตาม StarterPlayerScripts ไปด้วย)
แล้วเรียก instance แรก `.start()` (จำลองเกมบูตจริง) กับ instance ที่สอง `.setWallProgress(3)`
(จำลองคำสั่งจาก command bar ที่หลุดไปคนละ instance) — ถ้ากำแพงด่าน 2 ที่ instance แรกสร้างไว้
ยังชนอยู่หลังเรียก แปลว่าบั๊กเกิดจริง
"""
import os, re, subprocess, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAU = os.environ.get('LUAU') or shutil.which('luau')
if not LUAU:
    sys.exit('หา luau CLI ไม่เจอ — ติดตั้งแล้วใส่ใน PATH หรือสั่ง LUAU=/path/to/luau python3 ...')

# ══ สตั๊บ Instance ที่มี parent/child จริง (ไม่ใช่แค่เก็บ flat list เหมือนตัวตรวจพื้น) ══
# ต้องมีจริงเพราะเทสต์นี้ต้องพิสูจน์ว่า instance สองตัวมองเห็น/แก้ Part ตัวเดียวกันหรือคนละตัว
STUB = '''--!nocheck
local function newInstance(className)
\tlocal raw = { ClassName = className, Name = className, _children = {}, _parent = nil }
\tlocal obj = {}
\tlocal mt = {}
\tmt.__index = function(_, k)
\t\tif k == "Parent" then
\t\t\treturn raw._parent
\t\tend
\t\treturn raw[k]
\tend
\tmt.__newindex = function(_, k, v)
\t\tif k == "Parent" then
\t\t\tif raw._parent then
\t\t\t\tlocal siblings = raw._parent._children
\t\t\t\tfor i, c in siblings do
\t\t\t\t\tif c == obj then
\t\t\t\t\t\ttable.remove(siblings, i)
\t\t\t\t\t\tbreak
\t\t\t\t\tend
\t\t\t\tend
\t\t\tend
\t\t\traw._parent = v
\t\t\tif v then
\t\t\t\ttable.insert(v._children, obj)
\t\t\tend
\t\telse
\t\t\traw[k] = v
\t\tend
\tend
\tsetmetatable(obj, mt)

\traw.GetChildren = function()
\t\tlocal out = {}
\t\tfor _, c in raw._children do
\t\t\ttable.insert(out, c)
\t\tend
\t\treturn out
\tend
\traw.FindFirstChild = function(_, name)
\t\tfor _, c in raw._children do
\t\t\tif c.Name == name then
\t\t\t\treturn c
\t\t\tend
\t\tend
\t\treturn nil
\tend
\traw.FindFirstChildOfClass = function(_, cls)
\t\tfor _, c in raw._children do
\t\t\tif c.ClassName == cls then
\t\t\t\treturn c
\t\t\tend
\t\tend
\t\treturn nil
\tend
\traw.IsA = function(_, cls)
\t\treturn raw.ClassName == cls
\tend
\traw.ClearAllChildren = function()
\t\tfor _, c in raw._children do
\t\t\tc.Parent = nil
\t\tend
\t\traw._children = {}
\tend
\traw.Destroy = function()
\t\tobj.Parent = nil
\tend
\traw.PivotTo = function() end
\t-- WallRenderer เก็บเลเวลกำแพงที่วาดอยู่เป็น Attribute บนโมเดล (แก้บั๊ก builtTier แยกต่อ instance)
\traw._attributes = {}
\traw.SetAttribute = function(_, key, value)
\t\traw._attributes[key] = value
\tend
\traw.GetAttribute = function(_, key)
\t\treturn raw._attributes[key]
\tend

\treturn obj
end

local function __v3(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end
local Vector3 = { new = __v3 }
-- ⚠️ Phase 3B-2 เริ่มใช้ `Color3.new` และ `color:Lerp(...)` (กำแพงคล้ำลงตามเลเวลความเสียหาย)
-- สตั๊บเดิมมีแค่ fromRGB คืนตารางเปล่า → WallRenderer พังตั้งแต่สร้างกำแพงก้อนแรก (เงียบมาตั้งแต่ 1fdea01)
local function __color()
\treturn { __color = true, Lerp = function(_self, _goal, _alpha) return __color() end }
end
local Color3 = { fromRGB = function() return __color() end, new = function() return __color() end }
local UDim2 = {
\tfromOffset = function() return {} end,
\tfromScale = function() return {} end,
\tnew = function() return {} end,
}
local CFrame = { new = function() return { __cf = true } end }
local Enum = setmetatable({}, { __index = function()
\treturn setmetatable({}, { __index = function() return { __enum = true } end })
end })

local Instance = {}
function Instance.new(className)
\treturn newInstance(className)
end

-- Workspace เป็น singleton จริงของทั้งเกม (เหมือน Roblox จริง) — สร้างครั้งเดียว
-- แชร์ให้ WallRenderer ทั้งสอง "อินสแตนซ์" ในไฟล์นี้ใช้ร่วมกัน
local Workspace = newInstance("Workspace")
local Players = { LocalPlayer = { Name = "TestPlayer" } }

-- loadstring ไม่รองรับ require() ข้างในตัวเอง ("require is not supported in this context")
-- เลย require Config ตรงนี้ (context ปกติ) แล้วส่งเป็น argument (...) ให้ chunk ที่ loadstring มาแทน
local __wrTestConfig = require("./src/shared/Config")

'''

# loadstring() ให้ chunk ใหม่ที่ไม่เห็น local/upvalue ของสคริปต์ที่เรียกมันเลย
# (ไม่ใช่ closure ซ้อนแบบที่ require เห็น Config ปกติ) ต้องส่งของทุกอย่างที่ WallRenderer.lua
# ต้องใช้ผ่าน vararg (...) เป็น "environment table" ก้อนเดียวแทน
PRELUDE = '''
local __env = ...
local Config = __env.Config
local Instance = __env.Instance
local Vector3 = __env.Vector3
local Color3 = __env.Color3
local UDim2 = __env.UDim2
local CFrame = __env.CFrame
local Enum = __env.Enum
local Workspace = __env.Workspace
local Players = __env.Players
'''

CHECK = '''

-- โหลด WallRenderer.lua "คนละชุด" จำลองการถูก require จากคนละ ModuleScript instance
-- (เช่น StarterPlayerScripts ต้นฉบับ ปะทะ PlayerScripts ที่ถูกก็อปตอนเข้าเกมจริง)
local __env = {
\tConfig = __wrTestConfig,
\tInstance = Instance,
\tVector3 = Vector3,
\tColor3 = Color3,
\tUDim2 = UDim2,
\tCFrame = CFrame,
\tEnum = Enum,
\tWorkspace = Workspace,
\tPlayers = Players,
}

local chunkA = loadstring(__WALLRENDERER_SOURCE, "WallRenderer#A")
local chunkB = loadstring(__WALLRENDERER_SOURCE, "WallRenderer#B")
local RendererA = chunkA(__env)
local RendererB = chunkB(__env)

local function findWallModel(stage)
\tfor _, child in Workspace:GetChildren() do
\t\tif child.ClassName == "Folder" and child.Name == "LocalWalls" then
\t\t\tlocal model = child:FindFirstChild(`Wall{stage}`)
\t\t\tif model then
\t\t\t\treturn model
\t\t\tend
\t\tend
\tend
\treturn nil
end

local function wallIsSolid(stage)
\tlocal model = findWallModel(stage)
\tif not model then
\t\treturn false
\tend
\tlocal body = model:FindFirstChild("Body")
\treturn body ~= nil and body.CanCollide == true
end

-- ⚠️ WallRenderer ไม่มี getWallProgress() แล้วตั้งแต่ Phase 3B-1 (7b02706) — เก็บ stageProgress แทน
-- คำนวณ "พังถึงด่านไหน" จาก getStageProgress() เอง (ด่านแรกที่ยังไม่ cleared) ใช้แค่พิมพ์ประกอบ
-- ⚠️ ตัวตัดสินผล (RESULT) ยังเป็นกำแพงด่าน 2 ที่ผู้เล่นชนจริงเหมือนเดิมทุกอย่าง ไม่ได้ผ่อนเงื่อนไข
local function wallProgressOf(renderer)
\tlocal progress = renderer.getStageProgress() or {}
\tfor stage = 1, __wrTestConfig.Balance.Stage.COUNT do
\t\tlocal info = progress[stage]
\t\tif not (type(info) == "table" and info.cleared) then
\t\t\treturn stage
\t\tend
\tend
\treturn __wrTestConfig.Balance.Stage.COUNT
end

-- 1) RendererA คือของจริงที่ Main.client.lua เรียกตอนเกมบูต (wallProgress ค่าเริ่มต้น = 1)
RendererA.start()
print(string.format("หลัง RendererA.start(): กำแพงด่าน 2 ชนอยู่ไหม = %s", tostring(wallIsSolid(2))))
assert(wallIsSolid(2), "เซ็ตอัพเทสต์ผิด — ต้องมีกำแพงด่าน 2 ตั้งแต่แรก")

-- 2) จำลองผู้ใช้พิมพ์คำสั่งใน command bar โดยได้ ModuleScript "คนละอินสแตนซ์"
RendererB.setWallProgress(3)
print(string.format("RendererB พังถึงด่าน = %d (ควรเป็น 3)", wallProgressOf(RendererB)))
print(string.format(
\t"RendererA พังถึงด่าน = %d (ค่าในหน่วยความจำของ instance หลัก ไม่เปลี่ยนเป็นเรื่องปกติ — ตัวตัดสินคือกำแพงจริงข้างล่าง)",
\twallProgressOf(RendererA)
))

local stillSolidAfter = wallIsSolid(2)
print(string.format(
\t"หลัง RendererB.setWallProgress(3): กำแพงด่าน 2 (ของจริงที่ผู้เล่นชน) ยังชนอยู่ไหม = %s",
\ttostring(stillSolidAfter)
))

local wall4Solid = wallIsSolid(4)
print(string.format("กำแพงด่าน 4 ยังชนอยู่ไหม (ควรเป็น true เสมอ เพราะ 4 > 3) = %s", tostring(wall4Solid)))

-- ⚠️ ตัดสินจากสองข้อ: ด่าน 2 ที่ผู้เล่นชนจริงต้องหาย (บั๊กเดิม) และด่าน 4 ที่ยังไม่พังต้องยังชนอยู่
-- (กันการแก้เกินจนลบกำแพงทิ้งหมด — เดิมข้อหลังแค่พิมพ์ดู ไม่ได้นับเป็นผล)
print(string.format("RESULT=%s", if stillSolidAfter or not wall4Solid then "BUG" else "FIXED"))
'''


# ⚠️ ถอดบรรทัด require/GetService ของ Roblox ออก **แบบต้องเจอจริง** — ถ้าซอร์สเปลี่ยนจนหาไม่เจอ
# ให้พังดัง ๆ ตรงนี้ ไม่ใช่ replace เงียบ ๆ แล้วไปพังเป็น "attempt to ... nil" ใน luau ทีหลัง
# และหลังถอดแล้วต้องไม่เหลือ require/GetService ของ Roblox ในโค้ดเลย (นอกคอมเมนต์)
def strip_roblox_imports(src: str, lines: list, name: str) -> str:
    for line in lines:
        if src.count(line) != 1:
            sys.exit(f'harness ตามซอร์สไม่ทัน: หาบรรทัดนี้ใน {name} ไม่เจอ (หรือเจอซ้ำ) — {line!r}')
        src = src.replace(line, '')
    for raw in src.split('\n'):
        code = raw.split('--', 1)[0]
        if 'require(' in code or 'game:GetService(' in code:
            sys.exit(f'harness ตามซอร์สไม่ทัน: {name} ยังมี require/GetService ที่ harness ไม่ได้เตรียมของให้ — {raw.strip()!r}')
    return src


def build_harness() -> str:
    src = open(os.path.join(ROOT, 'src/client/WallRenderer.lua'), encoding='utf-8').read()
    src = strip_roblox_imports(src, [
        'local Players = game:GetService("Players")',
        'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
        'local Workspace = game:GetService("Workspace")',
        'local Config = require(ReplicatedStorage.Shared.Config)',
    ], 'WallRenderer.lua')
    src = src.replace('--!strict', '--!nocheck' + PRELUDE)
    src = re.sub(r'\nreturn WallRenderer\s*$', '\nreturn WallRenderer\n', src)

    escaped = src.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    check = CHECK.replace('__WALLRENDERER_SOURCE', f'"{escaped}"')
    return STUB + check


# ⚠️ ประกอบ harness ให้เสร็จก่อนค่อยเปิดไฟล์ — ถ้า build_harness() หยุดกลางทาง (ตามซอร์สไม่ทัน)
# จะได้ไม่ทิ้งไฟล์ว่าง .wall-singleton-check.luau ค้างไว้ในโฟลเดอร์โปรเจกต์
harness_source = build_harness()
harness = os.path.join(ROOT, '.wall-singleton-check.luau')
with open(harness, 'w', encoding='utf-8') as f:
    f.write(harness_source)

try:
    proc = subprocess.run([LUAU, harness], capture_output=True, text=True, cwd=ROOT)
finally:
    os.remove(harness)

if proc.returncode != 0:
    print(proc.stdout)
    sys.exit(f'รันสตั๊บไม่ผ่าน — WallRenderer อาจใช้ API ของ Roblox ตัวใหม่ที่สตั๊บยังไม่รู้จัก:\n{proc.stderr}')

print('\n'.join(l for l in proc.stdout.rstrip().split('\n') if not l.startswith('RESULT=')))

if 'RESULT=BUG' in proc.stdout:
    print('\nบั๊กเกิดจริง: setWallProgress บน WallRenderer อีกอินสแตนซ์ ไม่แตะกำแพงที่ผู้เล่นชนอยู่จริง '
          '(ด่าน 2 ยังชน) หรือลบเกินจนกำแพงที่ยังไม่พังหายไปด้วย (ด่าน 4 ไม่ชนแล้ว)')
    sys.exit(1)
elif 'RESULT=FIXED' in proc.stdout:
    print('\nผ่าน: ไม่ว่าจะเรียกจาก instance ไหน กำแพงที่ผู้เล่นชนจริงก็ถูกอัปเดตถูกต้อง')
    sys.exit(0)
else:
    sys.exit('สตั๊บไม่ได้พ่นผลลัพธ์ — ผลลัพธ์เชื่อไม่ได้')
