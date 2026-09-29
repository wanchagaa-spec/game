# -*- coding: utf-8 -*-
"""ป้ายตัวหนังสือลอย (BillboardGui) ต้องกำหนดขนาดเป็น studs ในโลก ไม่ใช่พิกเซลบนจอ

    python3 tools/check-billboard-world-size.py

ทำไมต้องมี (ผลทดสอบ Studio หลัง 5B-2): ป้ายลอย/หลอด HP บอสเคยตั้ง `Size = UDim2.fromOffset(กว้าง, สูง)`
→ BillboardGui ขนาดเป็น "พิกเซลบนจอ" คงที่ ไม่ว่าจะอยู่ใกล้หรือไกล → ยิ่งเดินออกไกล ป้ายยิ่งดูใหญ่เทียบกับโลก
(ผู้ใช้: "ยิ่งวิ่งออกไกลยิ่งขยาย เหมือนฟิคขนาดไว้กับหน้าจอ") · ของ BillboardGui ส่วน Scale ของ UDim2 = studs
→ ต้องใช้ `UDim2.fromScale(กว้างstuds, สูงstuds)` หรือ `UDim2.new(x, 0, y, 0)` เท่านั้น

ตรวจแบบข้อความ: ทุกบรรทัด `local <ชื่อ> = Instance.new("BillboardGui")` ใน src/ → หา `<ชื่อ>.Size = ...` ในบรรทัดถัด ๆ ไป
แล้วตกถ้าเป็น `UDim2.fromOffset(` หรือ `UDim2.new(` ที่ส่วน Offset ไม่ใช่ 0 · ไม่เจอบรรทัดตั้ง Size เลยก็ตก (ค่าเริ่มต้นของ
Roblox เป็นพิกเซล 0×0 = ป้ายไม่ขึ้น) · ยกเว้นทั้งบรรทัดด้วย `-- billboard-size: ok` ถ้าจำเป็นจริง ๆ
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CREATE = re.compile(r'local\s+(\w+)\s*=\s*Instance\.new\("BillboardGui"\)')
LOOKAHEAD = 12

passed, failed = 0, 0
problems = []
for dirpath, _dirs, files in os.walk(os.path.join(ROOT, 'src')):
    for name in sorted(files):
        if not name.endswith(('.lua', '.luau')):
            continue
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, ROOT)
        lines = open(path, encoding='utf-8').read().split('\n')
        for i, line in enumerate(lines):
            m = CREATE.search(line)
            if not m or line.strip().startswith('--'):
                continue
            var = m.group(1)
            size_line = None
            for j in range(i + 1, min(len(lines), i + 1 + LOOKAHEAD)):
                if re.search(rf'\b{re.escape(var)}\.Size\s*=', lines[j]):
                    size_line = (j, lines[j])
                    break
            if size_line is None:
                failed += 1
                problems.append(f'{rel}:{i + 1}: BillboardGui "{var}" ไม่ได้ตั้ง Size ภายใน {LOOKAHEAD} บรรทัด')
                continue
            j, text = size_line
            if 'billboard-size: ok' in text:
                passed += 1
                continue
            code = text.split('--', 1)[0]
            bad = 'UDim2.fromOffset(' in code
            new_call = re.search(r'UDim2\.new\(([^)]*)\)', code)
            if new_call:
                parts = [p.strip() for p in new_call.group(1).split(',')]
                if len(parts) == 4 and (parts[1] not in ('0', '0.0') or parts[3] not in ('0', '0.0')):
                    bad = True
            if bad:
                failed += 1
                problems.append(f'{rel}:{j + 1}: ป้ายลอยใช้ขนาดพิกเซล (ขยายตามระยะ) — ใช้ UDim2.fromScale(studs, studs) แทน: {text.strip()}')
            else:
                passed += 1

for problem in problems:
    print(f'  ✗ {problem}')
print(f'=== ผ่าน {passed} / ตก {failed} ===')
sys.exit(1 if failed else 0)
