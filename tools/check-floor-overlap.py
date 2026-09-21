# -*- coding: utf-8 -*-
"""หาคู่แผ่นพื้นที่ "ผิวบนอยู่ระนาบเดียวกันและพื้นที่ทับกัน" ใน MapBuilder

    python3 tools/check-floor-overlap.py

ทำไมต้องมี: สองแผ่นที่ผิวบนอยู่ที่ Y เดียวกันเป๊ะและทับกัน การ์ดจอเลือกไม่ได้ว่าจะวาดแผ่นไหน
ทับ ภาพจึงกระพริบสลับไปมาตามมุมกล้อง (z-fighting) — มองจากโค้ดไม่เห็นเลย ต้องวัดพิกัดจริง

เคยเกิดมาแล้ว: พื้นเลนเป็นแผ่นเดียวยาวตลอด แล้วพื้นห้องบอส 9 ห้องวางทับ
รวม 43,200 ตร.studs กระพริบทั้งเลน

⚠️ วิธีทำงาน: ประกอบสตั๊บ Roblox ขั้นต่ำ + ซอร์สจริงของ MapBuilder เป็นไฟล์ชั่วคราว
แล้วรันด้วย luau เก็บ Part ทุกชิ้นที่มันสร้าง — **ไม่ได้อ่านพิกัดจากที่อื่น ตัวเลขมาจากโค้ดจริง**
ถ้า MapBuilder เริ่มใช้ API ของ Roblox ตัวใหม่ สตั๊บจะพัง ซึ่งตั้งใจ — เป็นสัญญาณให้มาเติม
"""
import os, re, subprocess, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAU = os.environ.get('LUAU') or shutil.which('luau')
if not LUAU:
    sys.exit('หา luau CLI ไม่เจอ — ติดตั้งแล้วใส่ใน PATH หรือสั่ง LUAU=/path/to/luau python3 ...')

STUB = '''--!nocheck
local __created = {}
local function __v3(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end
local Vector3 = { new = __v3 }
local Color3 = { fromRGB = function() return { __color = true } end }
local UDim2 = { fromOffset = function() return {} end, fromScale = function() return {} end, new = function() return {} end }
local UDim = { new = function() return {} end }
local CFrame = { new = function() return { __cf = true } end }
local Enum = setmetatable({}, { __index = function()
\treturn setmetatable({}, { __index = function() return { __enum = true } end })
end })
local Instance = {}
function Instance.new(className)
\tlocal obj = {
\t\tClassName = className, Name = className,
\t\tSize = __v3(0, 0, 0), Position = __v3(0, 0, 0),
\t}
\tobj.Destroy = function() end
\tobj.GetChildren = function() return {} end
\tobj.FindFirstChildOfClass = function() return nil end
\tobj.PivotTo = function() end
\tif className == "Part" or className == "SpawnLocation" then
\t\ttable.insert(__created, obj)
\tend
\treturn obj
end
local __WS = { GetChildren = function() return {} end }

'''

CHECK = '''

MapBuilder.build()

-- เก็บเฉพาะแผ่นแนวราบที่คนมองเห็น: บาง (Y เล็ก) และกว้างพอจะเป็นพื้น
local slabs = {}
for _, p in __created do
\tif p.Size.Y <= 2.5 and p.Size.X >= 5 and p.Size.Z >= 5 then
\t\ttable.insert(slabs, {
\t\t\tname = p.Name,
\t\t\ttop = p.Position.Y + p.Size.Y / 2,
\t\t\tx1 = p.Position.X - p.Size.X / 2, x2 = p.Position.X + p.Size.X / 2,
\t\t\tz1 = p.Position.Z - p.Size.Z / 2, z2 = p.Position.Z + p.Size.Z / 2,
\t\t})
\tend
end

print(string.format("แผ่นแนวราบที่ตรวจ: %d ชิ้น", #slabs))

local clashes, area = 0, 0
for i = 1, #slabs do
\tfor j = i + 1, #slabs do
\t\tlocal a, b = slabs[i], slabs[j]
\t\tif math.abs(a.top - b.top) < 0.001 then
\t\t\tlocal ox = math.min(a.x2, b.x2) - math.max(a.x1, b.x1)
\t\t\tlocal oz = math.min(a.z2, b.z2) - math.max(a.z1, b.z1)
\t\t\tif ox > 0.001 and oz > 0.001 then
\t\t\t\tclashes += 1
\t\t\t\tarea += ox * oz
\t\t\t\tprint(string.format("  ระนาบชนกัน: %s | %s ที่ Y=%.2f ทับ %.0f x %.0f studs",
\t\t\t\t\ta.name, b.name, a.top, ox, oz))
\t\t\tend
\t\tend
\tend
end

print("")
if clashes == 0 then
\tprint("ไม่มีคู่แผ่นไหนผิวบนอยู่ระนาบเดียวกันและทับกัน")
else
\tprint(string.format("เจอ %d คู่ รวม %.0f ตร.studs", clashes, area))
end
print(string.format("CLASHES=%d", clashes))
'''


def build_harness() -> str:
    src = open(os.path.join(ROOT, 'src/server/MapBuilder.lua'), encoding='utf-8').read()
    src = src.replace('local ReplicatedStorage = game:GetService("ReplicatedStorage")', '')
    src = src.replace('local Workspace = game:GetService("Workspace")', 'local Workspace = __WS')
    src = src.replace('local Config = require(ReplicatedStorage.Shared.Config)',
                      'local Config = require("./src/shared/Config")')
    src = src.replace('--!strict', '--!nocheck')
    src = re.sub(r'\nreturn MapBuilder\s*$', '\n', src)
    return STUB + src + CHECK


harness = os.path.join(ROOT, '.floor-overlap-check.luau')
with open(harness, 'w', encoding='utf-8') as f:
    f.write(build_harness())

try:
    proc = subprocess.run([LUAU, harness], capture_output=True, text=True, cwd=ROOT)
finally:
    os.remove(harness)

if proc.returncode != 0:
    print(proc.stdout)
    sys.exit(f'รันสตั๊บไม่ผ่าน — MapBuilder อาจใช้ API ของ Roblox ตัวใหม่ที่สตั๊บยังไม่รู้จัก:\n{proc.stderr}')

marker = re.search(r'^CLASHES=(\d+)$', proc.stdout, re.M)
if not marker:
    print(proc.stdout)
    sys.exit('สตั๊บไม่ได้พ่นบรรทัดสรุป — ผลลัพธ์เชื่อไม่ได้')

# ตัดบรรทัดสำหรับเครื่องออกก่อนพิมพ์ให้คนอ่าน
print('\n'.join(l for l in proc.stdout.rstrip().split('\n') if not l.startswith('CLASHES=')))
sys.exit(1 if int(marker.group(1)) > 0 else 0)
