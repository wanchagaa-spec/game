# -*- coding: utf-8 -*-
"""รันการตรวจทั้งหมดของโปรเจกต์ในคำสั่งเดียว แล้วพิมพ์ตารางผลรวม

    python3 tools/check-all.py

รันตามลำดับ:
  1. `luau tests/run.luau`        — ชุดเทสต์หลัก
  2. `tools/check-*.py` ทุกตัว      — หาเองด้วย glob ไม่ hardcode รายชื่อ (ตัวใหม่ถูกนับเองอัตโนมัติ)

⚠️ ทำไมต้องมีไฟล์นี้: เคยรายงานผิดว่าสคริปต์ตรวจผ่าน ทั้งที่ตกมาตั้งแต่ Phase 3A เพราะอ่านผลด้วย
shell แบบ `python3 x.py; echo "$(basename x)=$?"` — `$(...)` รันก่อนและทับ `$?` เป็น 0 เสมอ
ไฟล์นี้อ่าน exit code ตรงจาก `subprocess.run(...).returncode` ไม่ผ่าน shell เลย
**รายงานผลจากตารางที่ไฟล์นี้พิมพ์เท่านั้น** อย่าอ่านผลจากการรันแยกทีละไฟล์เอง

สคริปต์ที่ตั้งใจให้ "แจ้งข้อมูลให้คนตรวจด้วยตา" ไม่ได้ตัดสินผ่าน/ตก (เช่น check-hardcoded-numbers
ที่ exit 0 เสมอ) ใส่บรรทัด `# check-all: advisory` ไว้ในไฟล์ — ตารางจะแสดงเป็น "ข้อมูล" แทน "ผ่าน"
จะได้ไม่เข้าใจผิดว่าตรวจแล้วผ่าน (แต่ถ้าสคริปต์นั้นพังเอง exit ≠ 0 ก็ยังนับว่าตก)

exit code ของไฟล์นี้: 0 = ทุกอย่างผ่าน · 1 = มีอย่างน้อยหนึ่งตัวตก
"""
import glob, os, re, shutil, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAU = os.environ.get('LUAU') or shutil.which('luau')
ADVISORY_MARKER = '# check-all: advisory'
COUNT_PATTERN = re.compile(r'ผ่าน\s+(\d+)\s*/\s*ตก\s+(\d+)')
TAIL_LINES = 25

try:
    sys.stdout.reconfigure(encoding='utf-8')  # คอนโซล Windows บางเครื่องพิมพ์ภาษาไทยไม่ได้
except (AttributeError, ValueError):
    pass


def is_advisory(path: str) -> bool:
    with open(path, encoding='utf-8') as f:
        return ADVISORY_MARKER in f.read()


def run(name: str, argv: list, advisory: bool = False) -> dict:
    env = dict(os.environ, PYTHONIOENCODING='utf-8')
    started = time.monotonic()
    try:
        proc = subprocess.run(argv, cwd=ROOT, capture_output=True, env=env, timeout=600)
        output = (proc.stdout + proc.stderr).decode('utf-8', errors='replace')
        code = proc.returncode
    except FileNotFoundError as err:
        output, code = f'รันไม่ได้: {err}', 127
    except subprocess.TimeoutExpired:
        output, code = 'เกินเวลา 600 วินาที', 124
    elapsed = time.monotonic() - started

    counts = COUNT_PATTERN.findall(output)
    lines = [l.strip() for l in output.splitlines() if l.strip()]
    return {
        'name': name,
        'code': code,
        'advisory': advisory,
        'cases': f'{counts[-1][0]}/{counts[-1][1]}' if counts else '-',
        'summary': lines[-1] if lines else '(ไม่มี output)',
        'tail': lines[-TAIL_LINES:],
        'seconds': elapsed,
    }


def status_of(result: dict) -> str:
    if result['code'] != 0:
        return 'ตก'
    return 'ข้อมูล' if result['advisory'] else 'ผ่าน'


def main() -> int:
    results = []

    if LUAU:
        results.append(run('tests/run.luau', [LUAU, 'tests/run.luau']))
    else:
        results.append({
            'name': 'tests/run.luau', 'code': 127, 'advisory': False, 'cases': '-',
            'summary': 'หา luau CLI ไม่เจอ — ใส่ใน PATH หรือตั้ง LUAU=/path/to/luau',
            'tail': [], 'seconds': 0.0,
        })

    for path in sorted(glob.glob(os.path.join(ROOT, 'tools', 'check-*.py'))):
        if os.path.abspath(path) == os.path.abspath(__file__):
            continue
        name = os.path.relpath(path, ROOT).replace(os.sep, '/')
        results.append(run(name, [sys.executable, path], advisory=is_advisory(path)))

    failed = [r for r in results if r['code'] != 0]

    for r in failed:
        print(f'\n━━ ตก: {r["name"]} (exit {r["code"]}) — {TAIL_LINES} บรรทัดท้าย ━━')
        for line in r['tail']:
            print(f'  {line}')

    name_width = max(len(r['name']) for r in results)
    print('\n━━ สรุป tools/check-all.py ━━')
    print(f'{"ไฟล์".ljust(name_width)}  สถานะ   exit  เคส (ผ่าน/ตก)  เวลา   สรุปท้าย')
    for r in results:
        summary = r['summary'] if len(r['summary']) <= 70 else r['summary'][:67] + '...'
        print(f'{r["name"].ljust(name_width)}  {status_of(r).ljust(6)}  {str(r["code"]).rjust(4)}  '
              f'{r["cases"].rjust(13)}  {r["seconds"]:5.1f}s  {summary}')

    passed = sum(1 for r in results if r['code'] == 0)
    print(f'\nรวม {len(results)} รายการ · exit 0 = {passed} · ตก = {len(failed)}')
    if failed:
        print('❌ มีรายการตก — ห้าม commit/รายงานว่าผ่าน')
        return 1
    print('✅ ผ่านทั้งหมด')
    return 0


if __name__ == '__main__':
    sys.exit(main())
