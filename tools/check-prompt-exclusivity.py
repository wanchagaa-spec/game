# -*- coding: utf-8 -*-
"""ตรวจว่า ProximityPrompt ทุกอันในเกมแสดงเฉพาะอันที่ใกล้ที่สุด (Exclusivity = OnePerButton)

    python3 tools/check-prompt-exclusivity.py

ทำไมต้องมี (UI-2): ป้ายบนแมพอยู่ใกล้กันได้ (ป้ายค่าวิ่งคอก 3 กับป้ายดาเมจห่าง ~11 studs)
ผู้ใช้ตัดสินว่าทุก prompt ต้องตั้ง Exclusivity = OnePerButton — รวมถึงแท่นอัญเชิญของ UI-3 ที่ยังไม่ได้เขียน
ตั้งมือทีละที่ = วันหนึ่งมีคนลืม จึงบังคับให้ **สร้าง prompt ผ่าน UiKit.prompt() ที่เดียว**

กฎที่ตรวจ (อ่านซอร์สตรง ๆ ไม่ต้องรัน luau):
  1. `Instance.new("ProximityPrompt")` มีได้ใน src/client/UiKit.lua เท่านั้น
  2. UiKit.prompt ตั้ง Exclusivity = OnePerButton **หลัง** apply(props) (props ทับค่านี้ไม่ได้)
  3. ห้ามใช้ Enum.ProximityPromptExclusivity ค่าอื่นที่ไหนเลย · ห้ามตั้ง .Exclusivity นอก UiKit

ถ้าวันหนึ่งต้องสร้าง prompt ฝั่ง server (UiKit เป็นของ client) ให้เพิ่มตัวช่วยฝั่งนั้นที่ตั้ง OnePerButton
แล้วเพิ่มไฟล์นั้นใน ALLOWED_CREATORS พร้อมเหตุผล — อย่าลบกฎนี้ทิ้ง
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
UIKIT = os.path.join('src', 'client', 'UiKit.lua')
ALLOWED_CREATORS = {UIKIT}

CREATE = re.compile(r'Instance\.new\(\s*["\']ProximityPrompt["\']\s*\)')
EXCLUSIVITY_VALUE = re.compile(r'Enum\.ProximityPromptExclusivity\.(\w+)')
EXCLUSIVITY_ASSIGN = re.compile(r'\.Exclusivity\s*=')

passed, failed = 0, 0


def check(label, ok, detail=''):
    global passed, failed
    if ok:
        passed += 1
        print(f'  ✓ {label}')
    else:
        failed += 1
        print(f'  ✗ {label}' + (f': {detail}' if detail else ''))


def code_lines(path):
    """บรรทัดโค้ดพร้อมเลขบรรทัด — ตัดคอมเมนต์ท้ายบรรทัด (--) ทิ้ง ไม่ให้ตัวอย่างในคอมเมนต์นับ"""
    with open(path, encoding='utf-8') as f:
        for number, line in enumerate(f, 1):
            yield number, line.split('--', 1)[0]


print('━━ ProximityPrompt: สร้างที่ UiKit.prompt ที่เดียว · OnePerButton เท่านั้น ━━')

creators, bad_values, stray_assigns = [], [], []
for folder, _, files in os.walk(SRC):
    for name in files:
        if not name.endswith('.lua'):
            continue
        path = os.path.join(folder, name)
        rel = os.path.relpath(path, ROOT)
        for number, code in code_lines(path):
            if CREATE.search(code):
                creators.append((rel, number))
            for value in EXCLUSIVITY_VALUE.findall(code):
                if value != 'OnePerButton':
                    bad_values.append((rel, number, value))
            if EXCLUSIVITY_ASSIGN.search(code) and rel != UIKIT:
                stray_assigns.append((rel, number))

outside = [f'{rel}:{n}' for rel, n in creators if rel not in ALLOWED_CREATORS]
check('สร้าง ProximityPrompt นอก UiKit.prompt ไม่ได้', not outside,
      'พบที่ ' + ', '.join(outside) + ' — ใช้ UiKit.prompt({...}) แทน')
check('UiKit มีจุดสร้าง prompt จริง', any(rel == UIKIT for rel, _ in creators))
check('ไม่มีใครใช้ Exclusivity ค่าอื่นนอกจาก OnePerButton', not bad_values,
      ', '.join(f'{rel}:{n} ({v})' for rel, n, v in bad_values))
check('ไม่มีใครตั้ง .Exclusivity เองนอก UiKit', not stray_assigns,
      ', '.join(f'{rel}:{n}' for rel, n in stray_assigns))

# UiKit.prompt: ต้องตั้ง OnePerButton หลัง apply(prompt, props) — props ทับไม่ได้
with open(os.path.join(ROOT, UIKIT), encoding='utf-8') as f:
    uikit = f.read()
body = re.search(r'function UiKit\.prompt\b(.*?)\nend', uikit, re.S)
check('มีฟังก์ชัน UiKit.prompt', body is not None)
if body:
    text = body.group(1)
    apply_at = text.find('apply(prompt, props)')
    set_at = text.find('prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton')
    check('UiKit.prompt ตั้ง Exclusivity = OnePerButton', set_at >= 0)
    check('  ตั้งหลัง apply(props) — props ส่งค่าอื่นมาทับไม่ได้', apply_at >= 0 and set_at > apply_at)

print(f'\n=== ผ่าน {passed} / ตก {failed} ===')
sys.exit(1 if failed else 0)
