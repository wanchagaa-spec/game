# -*- coding: utf-8 -*-
"""ตรวจว่าแม่ตัวใหม่ทุกตัวเกิดจากจุดกลางจุดเดียว — PlayerData.createMother (UI-4 · ดัชนี)

    python3 tools/check-mother-creation.py

ทำไมต้องมี: ดัชนี (`discovered`) บันทึก "ตัวละครที่เคยได้" ใน PlayerData.createMother ที่เดียว
ถ้าวันหนึ่งมีทางใหม่ที่ให้แม่ (ไข่ตำนาน Phase 6 · เทรด · รางวัลกิจกรรม) แล้วสร้างแม่เองโดยไม่ผ่านจุดนี้
ผู้เล่นจะได้ตัวละครใหม่แต่ดัชนีไม่ขึ้น — มองจากเกมไม่ออกจนมีคนบ่น

กฎที่ตรวจ (อ่านซอร์สตรง ๆ ไม่ต้องรัน luau · ตัดคอมเมนต์ `--` ทิ้งก่อน):
  1. แจก uid (`Config.makeUid(`) ได้เฉพาะใน src/shared/PlayerData.lua (createMother + buildWorstCase ที่เป็นข้อมูลจำลอง)
  2. แก้ตัวนับ `nextUid` (`nextUid +=` / `nextUid =`) ได้เฉพาะใน src/shared/PlayerData.lua
  3. PlayerData.createMother ต้องแจก uid + เลื่อน nextUid + บันทึก discovered ในตัวเอง
  4. ทุกทางที่สร้างแม่ใน server ที่รู้จัก (ฟักไข่ · debugGrantMother) เรียก PlayerData.createMother
เพิ่มทางใหม่ที่สร้างแม่ → เรียก PlayerData.createMother แล้วเติมชื่อฟังก์ชันใน KNOWN_CREATORS
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
PLAYER_DATA = os.path.join('src', 'shared', 'PlayerData.lua')
EGG_SERVICE = os.path.join('src', 'server', 'EggService.lua')
# (ไฟล์, ชื่อฟังก์ชัน) ที่ให้แม่ตัวใหม่ — ทุกตัวต้องเรียก PlayerData.createMother
KNOWN_CREATORS = [
    (EGG_SERVICE, 'local function hatch'),
    (EGG_SERVICE, 'function EggService.debugGrantMother'),
]

MAKE_UID = re.compile(r'(?<!function )Config\.makeUid\(')  # ตัวนิยามใน Config ไม่นับ
NEXT_UID_WRITE = re.compile(r'\bnextUid\s*(\+=|=(?!=))')

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
    with open(path, encoding='utf-8') as f:
        for number, line in enumerate(f, 1):
            yield number, line.split('--', 1)[0]


def function_body(rel, header):
    """ข้อความตั้งแต่บรรทัดหัวฟังก์ชันจนถึง `end` ที่ชิดซ้าย (ฟังก์ชันระดับบนสุดของไฟล์)"""
    with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
        text = f.read()
    start = text.find(header)
    if start < 0:
        return None
    end = text.find('\nend\n', start)
    body = text[start:end if end >= 0 else len(text)]
    return '\n'.join(line.split('--', 1)[0] for line in body.split('\n'))


print('━━ แม่ตัวใหม่ทุกตัวเกิดจาก PlayerData.createMother ที่เดียว (ดัชนี UI-4) ━━')

uid_outside, counter_outside = [], []
for folder, _, files in os.walk(SRC):
    for name in files:
        if not name.endswith('.lua'):
            continue
        path = os.path.join(folder, name)
        rel = os.path.relpath(path, ROOT)
        for number, code in code_lines(path):
            if MAKE_UID.search(code) and rel != PLAYER_DATA:
                uid_outside.append(f'{rel}:{number}')
            if NEXT_UID_WRITE.search(code) and rel != PLAYER_DATA:
                counter_outside.append(f'{rel}:{number}')

check('ไม่มีใครแจก uid (Config.makeUid) นอก PlayerData', not uid_outside,
      'พบที่ ' + ', '.join(uid_outside) + ' — สร้างแม่ผ่าน PlayerData.createMother แทน')
check('ไม่มีใครแก้ nextUid นอก PlayerData', not counter_outside, 'พบที่ ' + ', '.join(counter_outside))

body = function_body(PLAYER_DATA, 'function PlayerData.createMother')
check('มีฟังก์ชัน PlayerData.createMother', body is not None)
if body:
    check('  แจก uid จาก nextUid', 'Config.makeUid(' in body and 'data.nextUid' in body)
    check('  เลื่อน nextUid', 'data.nextUid += 1' in body)
    check('  บันทึกดัชนี (discovered)', 'markDiscovered(' in body or '.discovered[' in body)

for rel, header in KNOWN_CREATORS:
    creator = function_body(rel, header)
    check(f'{header.replace("local function ", "").replace("function ", "")} เรียก PlayerData.createMother',
          creator is not None and 'PlayerData.createMother(' in creator,
          'หาฟังก์ชันไม่เจอ' if creator is None else 'ไม่ได้เรียก')

print(f'\n=== ผ่าน {passed} / ตก {failed} ===')
sys.exit(1 if failed else 0)
