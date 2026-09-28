# -*- coding: utf-8 -*-
"""ห้ามมีโค้ดอ่าน `Config.Balance.Boss` ชุดเก่า (Phase 5B ลบทิ้งแล้ว)

    python3 tools/check-no-legacy-boss.py

ทำไมต้องมี: `Balance.Boss` (ดีไซน์ "บอสด่านละตัว รีเกิด 5 นาที · ไข่ 5 ฟอง") ถูกลบใน 5B
ค่าที่ยังใช้ย้ายไป `Config.Balance.BossCycle` แล้ว (ดูคอมเมนต์ที่ตัวกลุ่มใน Config.lua)
ใครอ่านชุดเก่าอีก = ได้ nil ตอนรัน (พังเฉพาะตอนเรียกจริง — เทสต์ที่ไม่ผ่านบรรทัดนั้นจับไม่ได้)
`validate()` กันการ *เติมกลับ* แล้ว สคริปต์นี้กันการ *อ่าน* ทั้ง src/ · tests/ · tools/*.luau

ตรวจแบบข้อความล้วน: `Balance.Boss` ที่ **ไม่ได้** ตามด้วยตัวอักษร/ตัวเลข/ขีดล่าง
(`Balance.BossCycle` ผ่าน · `Balance.Boss.X` / `Balance.Boss[` / `Balance.Boss)` ตก)
ยกเว้นบรรทัดคอมเมนต์ล้วน (`--` นำหน้า) และข้อความใน string ของคำอธิบาย/ข้อความ error
ที่พูดถึงชื่อกลุ่มเก่าโดยตั้งใจ — ใส่ `-- legacy-boss: ok` ท้ายบรรทัดนั้น
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATTERN = re.compile(r'Balance\.Boss(?![A-Za-z0-9_])')
TARGETS = [('src', ('.lua', '.luau')), ('tests', ('.luau', '.lua')), ('tools', ('.luau',))]

passed, failed = 0, 0
hits = []
for folder, exts in TARGETS:
    base = os.path.join(ROOT, folder)
    for dirpath, _dirs, files in os.walk(base):
        for name in sorted(files):
            if not name.endswith(exts):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            with open(path, encoding='utf-8') as f:
                for lineno, line in enumerate(f, 1):
                    stripped = line.strip()
                    if stripped.startswith('--') or 'legacy-boss: ok' in line:
                        continue
                    # ตัดคอมเมนต์ท้ายบรรทัดก่อนค้น (คอมเมนต์อธิบายการย้ายค่าพูดถึงชื่อเก่าได้)
                    code = line.split('--', 1)[0]
                    if PATTERN.search(code):
                        hits.append(f'{rel}:{lineno}: {stripped}')

print('━━ ห้ามอ่าน Config.Balance.Boss ชุดเก่า (ลบใน 5B · ค่าที่ยังใช้อยู่ใน Balance.BossCycle) ━━')
if hits:
    for hit in hits:
        print(f'  ✗ {hit}')
    failed += len(hits)
else:
    print('  ✓ ไม่มีโค้ดใน src/ · tests/ · tools/*.luau อ่าน Balance.Boss ชุดเก่า')
    passed += 1

print(f'\n=== ผ่าน {passed} / ตก {failed} ===')
sys.exit(1 if failed else 0)
