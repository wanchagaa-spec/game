# -*- coding: utf-8 -*-
"""รายงานตัวเลขที่พิมพ์มือในย่อหน้าคำอธิบายของ gen-balance-tables.py

    python3 tools/check-hardcoded-numbers.py

ทำไมต้องมี: ตารางในหน้าสมดุลสร้างจาก Config มาตลอด แต่ย่อหน้าคำอธิบายเคยพิมพ์ตัวเลขลงไปตรง ๆ
พอปรับสมดุลรอบถัดไป ตารางขยับแต่ข้อความค้าง กลายเป็นขัดกันเองในหน้าเดียว

⚠️ ตัวนี้ **ไม่ fail อัตโนมัติ** เพราะค่าคงที่เชิงดีไซน์ (เช่น √0.01 = 0.1) ก็ติดมาด้วย
และค่าพวกนั้นพิมพ์ตรง ๆ ได้ เพราะ validate() ตรึงไว้แล้ว — ต้องใช้ตาคนอ่านผลลัพธ์
"""
# check-all: advisory  ← tools/check-all.py แสดงตัวนี้เป็น "ข้อมูล" ไม่ใช่ "ผ่าน" (exit 0 เสมอโดยตั้งใจ)
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, 'tools', 'gen-balance-tables.py')

lines = open(TARGET, encoding='utf-8').read().split('\n')

blocks, inblk, buf, start = [], False, [], 0
for i, l in enumerate(lines, 1):
    if not inblk and re.match(r"W\(f?'''", l):
        inblk, start, buf = True, i, [l]
        if l.rstrip().endswith("''')"):
            inblk = False
            blocks.append((start, '\n'.join(buf)))
        continue
    if inblk:
        buf.append(l)
        if l.rstrip().endswith("''')"):
            inblk = False
            blocks.append((start, '\n'.join(buf)))

found = 0
for start, txt in blocks:
    stripped = re.sub(r'\{[^{}]*\}', '\x00', txt)   # ช่อง f-string = ปลอดภัย
    stripped = re.sub(r'<[^>]*>', ' ', stripped)     # tag HTML
    stripped = re.sub(r'&\w+;', ' ', stripped)       # HTML entity
    nums = re.findall(r'(?<![\w.\x00])\d[\d,\.]*', stripped)
    nums = [n for n in nums if n not in {'1', '2'}]  # "สองทาง" "ข้อ 1" ฯลฯ
    if nums:
        found += len(nums)
        print(f'  บรรทัด {start}: {sorted(set(nums))}')

if found == 0:
    print('✓ ไม่พบตัวเลขพิมพ์มือในย่อหน้าคำอธิบาย')
else:
    print(f'\nพบ {found} ตัว — ตรวจทีละตัวว่าเป็น "ค่าคงที่เชิงดีไซน์" (พิมพ์ได้)')
    print('หรือ "ผลลัพธ์ที่คำนวณได้" (ต้องเปลี่ยนเป็น f-string ที่อ่านจากข้อมูลจริง)')
sys.exit(0)
