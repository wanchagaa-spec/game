# -*- coding: utf-8 -*-
"""ตรวจว่าชื่อตัวละครเดิมที่เปลี่ยนไปแล้ว ไม่หลงเหลือในข้อความที่ผู้เล่นเห็น (รอบโมเดลตัวละคร)

    python3 tools/check-character-names.py

ผู้ใช้ตัดสิน: `yulai` องค์ยูไล → **ราชาปีศาจวัว** · `guanyin` พระแม่กวนอิม → **องค์หญิงพัดเหล็ก**
charId เดิมคงไว้โดยตั้งใจ (ฝังในข้อมูลที่เซฟแล้ว) — เปลี่ยนแค่ชื่อที่แสดง + โมเดล

กฎที่ตรวจ (อ่านซอร์สตรง ๆ · ตัดคอมเมนต์ Luau ทิ้งก่อน — คอมเมนต์ที่อธิบายการเปลี่ยนชื่อพูดถึงชื่อเดิมได้):
  1. โค้ดใน src/ ไม่มีชื่อเดิม (ยูไล · กวนอิม) ในสตริงใด ๆ
  2. Config ตั้งชื่อใหม่ให้ charId เดิมจริง (yulai / guanyin)
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
OLD_NAMES = ['ยูไล', 'กวนอิม']
NEW_NAMES = {'yulai': 'ราชาปีศาจวัว', 'guanyin': 'องค์หญิงพัดเหล็ก'}

passed, failed = 0, 0


def check(label, ok, detail=''):
    global passed, failed
    if ok:
        passed += 1
        print(f'  ✓ {label}')
    else:
        failed += 1
        print(f'  ✗ {label}' + (f': {detail}' if detail else ''))


def strip_comments(text):
    """ตัดคอมเมนต์ Luau (-- บรรทัด และ --[[ ]] / --[=[ ]=]) ที่ไม่ได้อยู่ในสตริง"""
    out, i, quote = [], 0, None
    while i < len(text):
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == '\\':
                out.append(text[i + 1:i + 2])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in '"\'`':
            quote = ch
            out.append(ch)
            i += 1
            continue
        if text.startswith('--', i):
            block = re.match(r'--\[(=*)\[', text[i:])
            if block:
                end = text.find(']' + block.group(1) + ']', i)
                i = len(text) if end < 0 else end + len(block.group(1)) + 2
            else:
                end = text.find('\n', i)
                i = len(text) if end < 0 else end
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


print('━━ ชื่อตัวละครเดิม (ยูไล · กวนอิม) ไม่เหลือในข้อความที่ผู้เล่นเห็น ━━')

found = []
for folder, _, files in os.walk(SRC):
    for name in sorted(files):
        if not name.endswith('.lua'):
            continue
        path = os.path.join(folder, name)
        code = strip_comments(open(path, encoding='utf-8').read())
        for number, line in enumerate(code.split('\n'), 1):
            for old in OLD_NAMES:
                if old in line:
                    found.append(f'{os.path.relpath(path, ROOT)}:{number} ({old})')
check('โค้ดใน src/ ไม่มีชื่อเดิม (นอกคอมเมนต์)', not found, ', '.join(found))

config = strip_comments(open(os.path.join(SRC, 'shared', 'Config.lua'), encoding='utf-8').read())
for char_id, new_name in NEW_NAMES.items():
    pattern = re.compile(r'\b' + char_id + r'\s*=\s*\{\s*id\s*=\s*"' + char_id + r'"\s*,\s*name\s*=\s*"([^"]*)"')
    match = pattern.search(config)
    check(f'Config: {char_id} (charId เดิม) ชื่อ "{new_name}"', match is not None and match.group(1) == new_name,
          f'ได้ {match.group(1) if match else "หาไม่เจอ"}')

print(f'\n=== ผ่าน {passed} / ตก {failed} ===')
sys.exit(1 if failed else 0)
