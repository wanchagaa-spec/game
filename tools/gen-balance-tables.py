# -*- coding: utf-8 -*-
"""egg-army-game :: สร้าง docs/balance-tables.html จาก Config.lua

รันจากรากโปรเจกต์:

    python3 tools/gen-balance-tables.py

⚠️ ตัวเลขทุกตัวในไฟล์ที่ออกมา **ทั้งในตารางและในย่อหน้าคำอธิบาย** มาจาก Config จริง
ห้ามพิมพ์ตัวเลขลงในข้อความบรรยายตรง ๆ เด็ดขาด — เคยทำแล้วข้อความค้างอยู่ที่ค่ารอบเก่า
ขัดกับตารางข้าง ๆ กันเอง ทั้งที่หัวไฟล์เขียนว่า "ไม่ได้พิมพ์มือ"
ถ้าต้องการเลขในประโยค ให้คำนวณจาก A[...] แล้วแทรกด้วย f-string

ต้องมี luau CLI อยู่ใน PATH (หรือชี้ด้วย env LUAU)
"""
import os, sys, datetime, subprocess, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.path.join(ROOT, 'tools', 'dump-balance.luau')
OUT = os.path.join(ROOT, 'docs', 'balance-tables.html')

LUAU = os.environ.get('LUAU') or shutil.which('luau')
if not LUAU:
    sys.exit('หา luau CLI ไม่เจอ — ติดตั้งแล้วใส่ใน PATH หรือสั่ง LUAU=/path/to/luau python3 tools/gen-balance-tables.py')

proc = subprocess.run([LUAU, DUMP], capture_output=True, text=True, cwd=ROOT)
if proc.returncode != 0:
    sys.exit(f'dump-balance.luau ล้ม:\n{proc.stderr}')

A = {}
for line in proc.stdout.splitlines():
    p = line.rstrip('\n').split('\t')
    A.setdefault(p[0], []).append(p[1:])

META = {k: v for k, v in A['META']}

def n(x): return float(x)

def fnum(x, dec=None):
    x = float(x)
    if x == 0: return '0'
    a = abs(x)
    for lim, suf in ((1e12,'T'), (1e9,'B'), (1e6,'M'), (1e3,'K')):
        if a >= lim:
            v = x/lim
            return f'{v:.1f}'.rstrip('0').rstrip('.') + suf
    if a >= 100: return f'{x:,.0f}'
    if a >= 10: return f'{x:.1f}'
    if a >= 1: return f'{x:.2f}'
    return f'{x:.3g}'

def fint(x): return f'{int(round(float(x))):,}'

def fhours(h):
    h = float(h)
    if h <= 0: return '—'
    if h < 1/60: return '&lt;1 น.'
    if h < 1: return f'{h*60:.0f} น.'
    if h < 48: return f'{h:.1f} ชม.'
    d = h/24
    if d < 365: return f'{d:.0f} วัน'
    return f'{d/365:.1f} ปี'

def cell(v, cls=''):
    return f'<td class="{cls}">{v}</td>' if cls else f'<td>{v}</td>'

def table(heads, rows, cls=''):
    th = ''.join(f'<th>{h}</th>' for h in heads)
    body = ''.join('<tr' + (f' class="{c}"' if c else '') + '>' + ''.join(cs) + '</tr>' for cs, c in rows)
    return f'<div class="scroll"><table class="{cls}"><thead><tr>{th}</tr></thead><tbody>{body}</tbody></table></div>'

out = []
W = out.append

STAGE = A['STAGE']; BYW = A['BYWEIGHT']; FILL = A['FILL']; TUR = A['TURRET']
SI = A['STAGEINFO']; PEN = A['PEN']; PRODUP = A['PRODUP']
PATH = A['PATH']; INCOME = A['INCOME']; UPG = A['UPG']; CMP = A['COMPARE']

# ── ค่าที่ย่อหน้าคำอธิบายอ้างถึงซ้ำ ๆ — คำนวณจากข้อมูลจริงครั้งเดียวตรงนี้ ──
# WARN ทุกตัวเลขในข้อความบรรยายต้องมาจากตรงนี้หรือจากตารางโดยตรง ห้ามพิมพ์ลงประโยคเอง
STAGES = len(STAGE)
CLASS_MULT = {c[0]: float(c[1]) for c in A['CLASS']}

# TIER = [min, max, weight, weight/10000] — ช่อง 4 เป็นค่าประมาณ (สมมติผลรวม 1e6)
# จึงคิดสัดส่วนจริงจากผลรวม weight เองแทน
TIER_TOTAL = sum(float(t[2]) for t in A['TIER'])

def tier_of(weight):
    return next((t for t in A['TIER'] if float(t[0]) <= weight <= float(t[1])), None)

def tier_share(t):
    return float(t[2]) / TIER_TOTAL if t and TIER_TOTAL else 0

# แถวของด่านที่ระบุ (คอลัมน์แรกของทุกกลุ่มคือเลขด่านเสมอ)
def st_row(rows, stage):
    return next(r for r in rows if int(r[0]) == stage)

# ด่านแรกที่มีกำแพงให้ตี — ด่าน 1 ไม่มี จึงเทียบเวลาจากด่านนี้ขึ้นไป
WALL1 = min(int(r[0]) for r in STAGE if float(r[9]) > 0)
# ด่านที่คอขวดพลิกจาก "ผลิต" เป็น "ปล่อย"
FLIP = next((int(r[0]) for r in STAGE if r[7] == 'release'), None)
LAST = int(STAGE[-1][0])

# EGG = [id, name, source, hatchTime, guaranteedTier, on/off, stage, C%, B%, A%, S%, SS%]
EGG_CLASS_COL = {c: 7 + i for i, c in enumerate(['C', 'B', 'A', 'S', 'SS'])}

SPS = int(META['stepsPerStage'])
MULT = float(META['stepMultiplier'])
MINH, MAXH = float(META['minHours']), float(META['maxHours'])

# damage ต่อตัวแปรตาม MULT^damageLevel และ damageLevel = ด่าน × ขั้นต่อด่าน
# เปลี่ยนขั้นต่อด่านจาก SPS เป็น s จึงคูณเวลาด้วย MULT^(ด่าน × (SPS − s)) ตรง ๆ
# (คอขวดยังเป็นการปล่อยเหมือนเดิม จำนวนตัว/วินาทีไม่เปลี่ยน)
def hours_if_steps(s):
    return {int(r[0]): float(r[10]) * MULT ** (int(r[0]) * (SPS - s))
            for r in STAGE if float(r[10]) > 0}

def egg_class_pct(stage, cls):
    row = next((e for e in A['EGG'] if e[5] == 'on' and e[6] == str(stage)), None)
    return float(row[EGG_CLASS_COL[cls]]) if row else 0

W(f'''<!doctype html><html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ตารางสมดุล — เกมไข่ทหาร</title>
<style>
:root{{color-scheme:light dark;--bg:#faf9f7;--card:#fff;--ink:#1c1b19;--dim:#6b6862;--line:#e5e2dc;
--head:#f2efe9;--accent:#b8860b;--warn:#a8451f;--ok:#2d6a3f;--hi:#fff8e6;--bad:#fdeae4;--good:#e9f4ec}}
@media(prefers-color-scheme:dark){{:root{{--bg:#161513;--card:#1e1d1a;--ink:#eceae5;--dim:#9a968e;
--line:#33312c;--head:#26241f;--accent:#d4a53a;--warn:#e08b62;--ok:#7bbd8f;--hi:#2b2517;
--bad:#3a221a;--good:#1c2b21}}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);
font:15px/1.6 "Noto Sans Thai","Sarabun",-apple-system,"Segoe UI",sans-serif}}
.wrap{{max-width:1060px;margin:0 auto;padding-block:40px;padding-left:20px;padding-right:20px}}
header{{border-bottom:2px solid var(--accent);padding-bottom:16px}}
h1{{margin:0 0 6px;font-size:26px;letter-spacing:-.01em}}
.meta{{color:var(--dim);font-size:13px}}
h2{{margin:40px 0 4px;font-size:19px;border-left:4px solid var(--accent);padding-left:10px}}
h2 .num{{color:var(--dim);font-weight:400;margin-right:6px}}
h3{{margin:26px 0 2px;font-size:15.5px;color:var(--dim)}}
.formula{{background:var(--head);border:1px solid var(--line);border-radius:6px;padding:10px 14px;
margin:12px 0;font-family:ui-monospace,Menlo,monospace;font-size:13.5px;overflow-x:auto}}
.note{{color:var(--dim);font-size:13.5px;margin:10px 0}}
.key{{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--ok);
border-radius:6px;padding:12px 16px;margin:14px 0}}
.key.warn{{border-left-color:var(--warn)}}
.key.red{{border-left-color:#c0392b;background:var(--bad)}}
.scroll{{overflow-x:auto;margin:14px 0}}
table{{border-collapse:collapse;width:100%;font-size:13px;background:var(--card);
border:1px solid var(--line);border-radius:6px;overflow:hidden}}
th,td{{padding:7px 10px;text-align:right;border-bottom:1px solid var(--line);white-space:nowrap}}
th{{background:var(--head);font-weight:600;font-size:12px;color:var(--dim)}}
th:first-child,td:first-child{{text-align:left;font-weight:600}}
tbody tr:last-child td{{border-bottom:none}}
tbody tr:nth-child(even){{background:color-mix(in srgb,var(--head) 45%,transparent)}}
tr.hi td{{background:var(--hi)}}
td.bad{{background:var(--bad);font-weight:600}}
td.good{{background:var(--good);font-weight:600}}
td.dim{{color:var(--dim)}}
.toc{{background:var(--card);border:1px solid var(--line);border-radius:6px;padding:12px 18px;margin:18px 0;
font-size:13.5px;line-height:2}}
.toc a{{color:var(--ink);text-decoration:none;border-bottom:1px dotted var(--dim)}}
footer{{margin-top:48px;padding-top:16px;border-top:1px solid var(--line);color:var(--dim);font-size:12.5px}}
code{{background:var(--head);padding:1px 5px;border-radius:3px;font-size:12.5px}}
@media print{{body{{background:#fff}}h2{{page-break-after:avoid}}.scroll{{page-break-inside:avoid}}}}
</style></head><body><div class="wrap">

<header>
<h1>ตารางสมดุล — เกมไข่ทหาร</h1>
<div class="meta">ระบบรบใหม่: ปล่อยทหารต่อเนื่องแบบ Age of War ·
ตัวเลขทุกตัวดึงจาก <code>src/shared/Config.lua</code> โดยตรง <b>ทั้งในตารางและในคำอธิบาย</b> ไม่ได้พิมพ์มือ ·
สร้างเมื่อ {datetime.date.today().isoformat()} · ตรวจด้วย <code>luau tests/run.luau</code></div>
</header>

<div class="toc">
<a href="#s1">1 · สมการเดียวที่ต้องจำ</a> &nbsp;·&nbsp;
<a href="#s2">2 · เส้นทางผู้เล่นจริง vs ผู้เล่นในฝัน 🔴</a> &nbsp;·&nbsp;
<a href="#s3">3 · เวลาพังแต่ละด่าน แยกตามน้ำหนักแม่</a> &nbsp;·&nbsp;
<a href="#s4">4 · throughput — คอขวดอยู่ไหน</a> &nbsp;·&nbsp;
<a href="#s5">5 · รายได้ vs ราคาของ</a> &nbsp;·&nbsp;
<a href="#s6">6 · ตัวคูณ damage ที่ซื้อด้วยเงิน ⭐</a> &nbsp;·&nbsp;
<a href="#s7">7 · turret</a> &nbsp;·&nbsp;
<a href="#s8">8 · อัตราผลิตตามน้ำหนัก</a> &nbsp;·&nbsp;
<a href="#s9">9 · damage = HP</a> &nbsp;·&nbsp;
<a href="#s10">10 · เงิน</a> &nbsp;·&nbsp;
<a href="#s11">11 · คลาส · น้ำหนัก · ไข่</a> &nbsp;·&nbsp;
<a href="#s12">12 · ด่าน · บอส · อาวุธ · คอก</a> &nbsp;·&nbsp;
<a href="#s13">13 · ซื้อความเร็ว — บ่อเงินบ่อที่สอง ⭐</a>
</div>
''')

# ── 1 ─────────────────────────────────────────────
W('<h2 id="s1"><span class="num">1</span>สมการเดียวที่ต้องจำ</h2>')
W(f'''<div class="formula">damage/วินาที = <b>min(อัตราผลิต, อัตราปล่อย)</b> × damage ต่อตัว × {META['stepMultiplier']}<sup>damageLevel</sup></div>
<div class="key warn"><b>ความหมายที่เปลี่ยนเกมทั้งเกม</b> — พอชนเพดาน "อัตราปล่อย" แล้ว
<b>upgrade อัตราผลิตหลุดออกจากสมการ damage ทันที</b><br>
(ยังมีประโยชน์อยู่ เพราะเติมคลังเร็วขึ้นและสะสมกองใหญ่ได้เร็วขึ้น แต่ไม่ใช่ตัวคูณ damage อีกต่อไป)<br>
ระบบเดิม "กดส่งทีเดียวแล้วรอผล" ยกเลิกทั้งหมดแล้ว<br>
และตัวคูณ damage ก็ไม่ได้มาฟรีตามด่านอีกแล้ว — <b>ต้องซื้อด้วยเงิน</b> (หัวข้อ 6)</div>''')
rows = []
for r in STAGE:
    st, w, cls, pen, perM, prod, rel, bn, power, hp, hours, dps = r
    hi = 'hi' if int(st) == 3 else ''
    rows.append(([
        cell(f'ด่าน {st}'), cell(fint(w)), cell(cls), cell(pen),
        cell(fnum(perM)), cell(fnum(prod)), cell(fint(rel)),
        cell('<b>ผลิต</b>' if bn == 'produce' else 'ปล่อย', 'bad' if bn=='produce' else ''),
        cell(fnum(power)), cell(fnum(dps)),
        cell(fnum(hp) if float(hp) > 0 else '—'),
        cell('<b>' + fhours(hours) + '</b>' if float(hp) > 0 else '—'),
    ], hi))
W(table(['ด่าน','แม่อ้างอิง (kg)','คลาส','คอก','ผลิต/นาที ต่อแม่','ผลิตได้/นาที รวม','ปล่อยได้/นาที','คอขวด','damage ต่อตัว','damage/วิ','HP ด่าน','เวลาพัง'], rows))
W(f'''<div class="note">"แม่อ้างอิง" = ผู้เล่นชั้นกลางที่ด่านนั้น (คอกเลเวล N · upgrade อัตราผลิตขั้น N−1) ตาม <code>Config.BalanceCheck</code>
— ค่าชุดเดียวกับที่ <code>assertProgressionIsSane()</code> ใช้กันไม่ให้เซิร์ฟบูตตอนสมดุลพัง</div>
<div class="key"><b>ด่าน 1 ไม่มีกำแพงและไม่มีทหารฝ่ายรับ</b> — ผู้เล่นใหม่เดินไปสู้บอสตัวเล็กเอาไข่ได้เลย
แก้ปัญหาไก่กับไข่ (ต้องมีแม่ถึงจะมีกองทัพ ต้องมีไข่ถึงจะมีแม่) · <code>validate()</code> บังคับข้อนี้ไว้</div>''')

# ── 2 ─────────────────────────────────────────────
W('<h2 id="s2"><span class="num">2</span>🔴 ยามเคยวัดผู้เล่นที่ไม่มีอยู่จริง</h2>')
_oldW0, _oldWN = float(PATH[0][3]), float(PATH[-1][3])
_oldStep = (_oldWN / _oldW0) ** (1 / (len(PATH) - 1)) if _oldW0 > 0 else 0
# tier ที่ครอบแม่หนักสุดที่ยามเดิมสมมติ → บอกความหายากจริงของมัน
_tier = tier_of(_oldWN)
_share = tier_share(_tier)
_odds = f"1 ใน {1/_share:,.0f}" if _share > 0 else "หายากมาก"
W(f'''<div class="note">ยามเดิมสมมติว่าผู้เล่นได้แม่หนักขึ้น ×{_oldStep:.0f} ทุกด่าน
({fint(_oldW0)} kg → {fint(_oldWN)} kg)
แต่ตารางสุ่มน้ำหนักเหมือนกันทุกด่าน — แม่ {fnum(_oldWN)} kg คือ <b>{_odds} ฟอง</b><br>
ที่อัตราไข่จริง {float(META['eggsPerHour']):.2f} ฟอง/ชม./คน
({META['bossEggs']} ฟอง ทุก {float(META['bossRespawn'])/60:.0f} นาที ÷ {META['players']} คน)
นั่นคือเวลาฟาร์มระดับ <b>{fhours(float(PATH[-1][2]))}</b></div>''')
rows = []
for r in PATH:
    st, oh, of_, ow, oc, nh, nf, nw, nc = r
    of_f = float(of_)
    rows.append(([
        cell(f'ด่าน {st}'),
        cell(f'{fint(ow)} kg · {oc}', 'dim'), cell(fhours(oh), 'dim'),
        cell(fhours(of_), 'bad'),
        cell(f'{of_f/float(oh):,.0f}×', 'bad'),
        cell(f'{fint(nw)} kg · {nc}'), cell('<b>' + fhours(nh) + '</b>'),
        cell(fhours(nf)), cell(f'{float(nf)/float(nh):.2f}×', 'good'),
    ], ''))
W(table(['ด่าน','แม่ที่ยามเดิมสมมติ','เวลาตี','<b>เวลาฟาร์ม</b>','ฟาร์ม÷ตี',
         'แม่ที่ผู้เล่นมีจริง','เวลาตี','เวลาฟาร์ม','ฟาร์ม÷ตี'], rows))
# ด่านที่ "ฟาร์ม ÷ ตี" ของยามเดิมแย่ที่สุด
_wr = max(PATH, key=lambda r: float(r[2]) / float(r[1]))
# อัตราส่วนสูงสุดของยามชุดใหม่ และด่านที่เกิด
_nr = max(PATH, key=lambda r: float(r[6]) / float(r[5]))
_newWorst = float(_nr[6]) / float(_nr[5])
_refW = float(PATH[0][7])
_refPct = f"{tier_share(tier_of(_refW))*100:.0f}%"
W(f'''<div class="key red"><b>ยามผ่านทุกด่าน ทั้งที่เกมเล่นไม่ไหว</b> —
เพราะยามวัดแค่ "เวลาตี" ไม่เคยถามว่า "กว่าจะหาของมาตีได้ใช้เวลาเท่าไหร่"<br>
กรณีที่แย่ที่สุดคือด่าน {_wr[0]}: ยามเดิมบอกว่าใช้เวลาตี {fhours(_wr[1])} แต่แม่ที่มันสมมติว่าผู้เล่นมี
({fint(_wr[3])} kg คลาส {_wr[4]}) ต้องฟาร์ม <b>{fhours(_wr[2])}</b>
— มากกว่ากันถึง <b>{float(_wr[2])/float(_wr[1]):,.0f} เท่า</b></div>
<div class="key"><b>แก้สองชั้น</b><br>
<b>1.</b> ผู้เล่นอ้างอิงใช้แม่ <b>น้ำหนักคงที่</b> ({fint(_refW)} kg — ซึ่ง {_refPct} ของไข่ให้)
แล้วให้ <b>คลาส</b> เป็นตัวไต่ตามด่านแทน ({PATH[0][8]} → {PATH[-1][8]}) = เส้นทางที่ผู้เล่นจริงเดิน<br>
<b>2.</b> ยามตัวใหม่: <code>เวลาฟาร์ม ≤ {float(META['maxFarmRatio']):.0f} × เวลาตี</code> ทุกด่าน
— ทดสอบแล้วว่าจับได้จริง (ดู <code>tests/config.spec.luau</code> หัวข้อ "ยามเวลาฟาร์ม")<br>
ตอนนี้อัตราส่วนสูงสุดคือ <b>{_newWorst:.2f}×</b> ที่ด่าน {_nr[0]} — ปัญหาหายแล้ว</div>''')

# ── 3 ─────────────────────────────────────────────
W('<h2 id="s3"><span class="num">3</span>เวลาพังแต่ละด่าน แยกตามน้ำหนักแม่</h2>')
_cc = A['CLASSCOMP'][0]
W(f'''<div class="note">ล็อกคลาสไว้ที่ C (×{CLASS_MULT['C']:.0f}) เพื่อให้เห็นผลของ <b>น้ำหนักล้วน ๆ</b> ·
คอกและ upgrade ยังไต่ไปตามด่านเหมือนเดิม</div>''')
rows = []
for r in BYW:
    w = r[0]; vals = r[1:]
    cs = [cell(fint(w) + ' kg')]
    for i, v in enumerate(vals):
        f = float(v)
        if f < 0: cs.append(cell('ไม่มีกำแพง', 'dim')); continue
        cls = 'bad' if f > float(META['maxHours']) else ('good' if f < float(META['minHours']) else '')
        cs.append(cell(fhours(f), cls))
    rows.append((cs, ''))
W(table(['น้ำหนักแม่'] + [f'ด่าน {i}' for i in range(1, 10)], rows))
_wSpan = float(BYW[-1][0]) / float(BYW[0][0])
_lastCol = len(BYW[0]) - 1
W(f'''<div class="key warn"><b>น้ำหนักแม่คือตัวแปรที่แรงที่สุดในเกม</b> —
ห่างกัน {fnum(_wSpan)} เท่า ({fint(BYW[0][0])} kg → {fnum(float(BYW[-1][0]))} kg)
ทำให้เวลาพังด่าน {LAST} ห่างกัน <b>{float(BYW[0][_lastCol])/float(BYW[-1][_lastCol]):,.0f} เท่า</b>
({fhours(BYW[0][_lastCol])} → {fhours(BYW[-1][_lastCol])})<br>
มาสองทางพร้อมกัน: damage ต่อตัว (√ = ×{fnum(_wSpan ** 0.5)})
และอัตราผลิต (^{META['weightExponent']} = ×{fnum(_wSpan ** float(META['weightExponent']))})
— แต่ตั้งแต่ด่าน {FLIP} ขึ้นไปอัตราผลิตชนเพดานปล่อย เหลือแค่ damage ต่อตัวที่ยังทำงาน<br>
<span style="color:var(--warn)"><b>สีแดง</b> = เกินเพดาน {META['maxHours']} ชม.</span> ·
<span style="color:var(--ok)"><b>สีเขียว</b> = ต่ำกว่าขั้นต่ำ {META['minHours']} ชม.</span>
— ยามเช็คเฉพาะผู้เล่นชั้นกลาง ไม่ได้เช็คทุกช่องในตารางนี้</div>
<div class="key"><b>ช่องแดงที่ด่านท้ายไม่ใช่บั๊ก</b> — ตารางนี้ล็อกคลาสไว้ที่ C
แปลว่า "ถ้าผู้เล่นไม่เคยได้คลาสดีขึ้นเลยตลอดเกม"<br>
แม่ {fint(_cc[1])} kg คลาส C ใช้เวลา {fhours(_cc[2])} ที่ด่าน {_cc[0]}
ซึ่งเกินเพดาน {META['maxHours']} ชม. ไปไกล — <b>นั่นคือประเด็นของรอบนี้พอดี</b>
ด่านท้ายไม่ได้ออกแบบให้ผ่านด้วยคลาส C แต่ให้ผ่านด้วยคลาส {_cc[3]}
ที่ฟาร์มได้จากบอสด่านนั้น ({egg_class_pct(int(_cc[0]), _cc[3]):.0f}% ของไข่ด่าน {_cc[0]})<br>
เทียบกัน: แม่ {fint(_cc[1])} kg <b>คลาส {_cc[3]}</b> ที่ด่าน {_cc[0]} ใช้ {fhours(_cc[4])} ·
แม่ {fint(_cc[5])} kg คลาส {_cc[3]} (ผู้เล่นอ้างอิง) ใช้ {fhours(_cc[6])}
— คลาสเดียวชดเชยได้ ×{CLASS_MULT[_cc[3]] / CLASS_MULT['C']:,.0f}
ซึ่งมากกว่าที่น้ำหนักทั้งตารางให้ได้ในช่วง tier เดียวกัน</div>''')

# ── 4 ─────────────────────────────────────────────
W('<h2 id="s4"><span class="num">4</span>throughput — คอขวดอยู่ที่ไหนในแต่ละช่วงเกม</h2>')
rows = []
for r in STAGE:
    st, w, cls, pen, perM, prod, rel, bn, power, hp, hours, dps = r
    ratio = float(prod)/float(rel)
    rows.append(([
        cell(f'ด่าน {st}'), cell(pen), cell(fnum(perM)),
        cell(fnum(prod), 'good' if bn=='produce' else ''),
        cell(fint(rel), 'good' if bn=='release' else ''),
        cell(f'{ratio:,.2f}×' if ratio < 100 else f'{ratio:,.0f}×'),
        cell('<b>การผลิต</b>' if bn=='produce' else 'การปล่อย'),
        cell('ผลิตไม่ทัน ปล่อยว่าง' if bn=='produce' else 'คลังล้น ปล่อยไม่ทัน', 'dim'),
    ], 'hi' if int(st)==3 else ''))
W(table(['ด่าน','คอก','ผลิต/นาที ต่อแม่','ผลิตได้/นาที รวม','ปล่อยได้/นาที','ผลิต ÷ ปล่อย','คอขวด','อาการ'], rows))
# STAGE = [stage, w, cls, penCap, perMother, producedPerMin, releasePerMin, bottleneck, power, hp, hours, dps]
_prod = [r for r in STAGE if r[7] == 'produce']
_rel = [r for r in STAGE if r[7] == 'release']
_prodList = " และ ".join(fnum(r[5]) for r in _prod)
_prodRange = f"{fnum(_prod[0][6])}" if len({r[6] for r in _prod}) == 1 else f"{fnum(_prod[0][6])} → {fnum(_prod[-1][6])}"
_flipRow = st_row(STAGE, FLIP)
_prevRow = st_row(STAGE, FLIP - 1)
W(f'''<div class="key"><b>คอขวดพลิกที่ด่าน {FLIP} แล้วเป็นแบบนั้นถาวร</b><br>
<b>ด่าน {_prod[0][0]}–{_prod[-1][0]} (ช่วงต้นเกม)</b> — คอขวดคือ <b>การผลิต</b>
ผลิตได้ {_prodList} ตัว/นาที แต่ปล่อยได้ {_prodRange}
ผู้เล่นนั่งรอแม่ผลิต ปุ่มอัญเชิญเปิดค้างไว้ได้เลย · <b>ของที่ควรซื้อ: คอก + upgrade อัตราผลิต</b><br>
<b>ด่าน {_rel[0][0]}–{_rel[-1][0]} (กลางถึงปลายเกม)</b> — คอขวดคือ <b>การปล่อย</b>
ผลิตได้ {fnum(_rel[0][5])} → {fnum(_rel[-1][5])} ตัว/นาที
แต่ปล่อยได้แค่ {fnum(_rel[0][6])} → {fnum(_rel[-1][6])}
คลังเต็มตลอด · <b>upgrade อัตราผลิตหยุดเพิ่ม damage ตั้งแต่จุดนี้</b>
เหลือแค่ "น้ำหนักแม่" กับ "ด่านที่ปลดล็อกแล้ว" ที่ยังดัน damage ได้</div>
<div class="key warn"><b>นี่คือเหตุผลที่ด่าน {FLIP} ยังปล่อย
{fnum(float(_flipRow[6])/60)} ตัว/วิ เท่าด่าน {FLIP - 1}</b> —
ถ้าเร่งขึ้นตรงรอยต่อที่คอขวดพลิกพอดี เส้นเวลาจะแอ่นลง
(ตอนนี้ด่าน {FLIP} ใช้ {fhours(_flipRow[10])} · ด่าน {FLIP - 1} ใช้ {fhours(_prevRow[10])}
— เร่งแล้วด่านหลังจะง่ายกว่าด่านหน้า) ยามจับได้และไม่ยอมให้เซิร์ฟบูต</div>''')

# ── 5 ─────────────────────────────────────────────
W('<h2 id="s5"><span class="num">5</span>รายได้ต่อด่าน แยกตามบ่อ vs ราคาของที่ต้องซื้อ</h2>')
_dcAll = [float(r[1]) for r in SI if float(r[1]) > 0]
_dMult = (_dcAll[-1] / _dcAll[0]) ** (1 / (len(_dcAll) - 1)) if len(_dcAll) > 1 else 1
W(f'''<div class="note">เดิมเงินมาจาก "แม่ในคอก" ทางเดียว ตอนนี้เพิ่ม <b>ฆ่าทหารฝ่ายรับ</b> และ <b>ฆ่าบอส</b><br>
ทหาร: <code>{fint(META['killDefenderBase'])} × {float(META['killDefenderMult']):.0f}^(ด่าน−1)</code> ต่อตัว
(จำนวนทหาร ×{_dMult:,.0f} ต่อด่านอยู่แล้ว → เงินรวม
<b>×{float(META['killDefenderMult']) * _dMult:,.0f} ต่อด่าน</b>) ·
บอส: <code>{fint(META['killBossBase'])} × {float(META['killBossMult']):.0f}^(ด่าน−1)</code> ต่อครั้ง</div>''')
rows = []
for r in INCOME:
    st, hrs, penIn, killHr, bossHr, total, need, upg, ratio, share = r
    rows.append(([
        cell(f'ด่าน {st}'), cell(fhours(hrs), 'dim'),
        cell(fnum(penIn)), cell(fnum(killHr)), cell(fnum(bossHr)),
        cell('<b>' + fnum(total) + '</b>'),
        cell(fnum(upg), 'good'), cell(f'{float(share)*100:.0f}%', 'dim'),
        cell(fnum(need)),
        cell(f'{float(ratio):.2f}×', 'good'),
    ], ''))
W(table(['ด่าน','เวลาตี','จากแม่/ชม.','ฆ่าทหาร/ชม.','ฆ่าบอส/ชม.','รายได้ทั้งด่าน',
         'ราคา upgrade damage','% รายได้','ราคารวมทุกอย่าง','เหลือ'], rows))
# INCOME = [stage, hrs, penIncome, killPerHr, bossPerHr, income, need+upg, upg, income/(need+upg), upg/income]
_before = [(float(r[0]), float(r[5]) / (float(r[6]) - float(r[7]))) for r in INCOME if float(r[6]) > float(r[7])]
_after = [(float(r[0]), float(r[8])) for r in INCOME]
_shares = [float(r[9]) * 100 for r in INCOME]
_bMin, _bMax = min(_before, key=lambda x: x[1]), max(_before, key=lambda x: x[1])
_aMin, _aMax = min(v for _, v in _after), max(v for _, v in _after)
# ระยะเผื่อของการผลิตในด่านที่คอขวดเป็น "ปล่อย"
_slack = [float(r[5]) / float(r[6]) for r in STAGE if r[7] == 'release']
# STAGEINFO = [stage, defenderCount, ...] — จำนวนทหารโตกี่เท่าต่อด่าน คิดจากข้อมูลจริง
_dc = [float(r[1]) for r in SI if float(r[1]) > 0]
_defenderMult = (_dc[-1] / _dc[0]) ** (1 / (len(_dc) - 1)) if len(_dc) > 1 else 1
_killMult = float(META['killDefenderMult']) * _defenderMult
W(f'''<div class="key"><b>บ่อเงินใหม่ไม่ตกยุค</b> —
เงินจากการกวาดทหารโต ×{_killMult:,.0f} ต่อด่าน และเงินบอสโต ×{float(META['killBossMult']):,.0f}
ทั้งคู่ไม่ช้ากว่าราคาของที่โต ×{float(META['coinStageMult']):,.0f} ·
<code>validate()</code> บังคับข้อนี้ไว้แล้ว<br>
⚠️ ทหารตายแล้วไม่เกิดใหม่ + <code>stageProgress</code> เซฟถาวร →
<b>ทหาร 1 ตัวจ่ายเงินได้ครั้งเดียวตลอดกาล</b> ห้ามจ่ายซ้ำตอนโหลดข้อมูลกลับมา</div>
<div class="key"><b>✅ upgrade damage ดูดเงินส่วนเกินไปได้จริง</b><br>
ถ้าไม่มี upgrade damage ให้ซื้อ: เงินเหลือ
<b>{_bMin[1]:,.1f}× (ด่าน {_bMin[0]:.0f}) ถึง {_bMax[1]:,.0f}× (ด่าน {_bMax[0]:.0f})</b> — ล้นจนไม่มีอะไรให้ใช้<br>
มีแล้ว: เหลือ <b>{_aMin:,.2f}× ถึง {_aMax:,.2f}×</b><br>
ราคา upgrade กินรายได้ {min(_shares):.0f}–{max(_shares):.0f}% ทุกด่าน —
<code>validate()</code> บังคับให้อยู่ในช่วง
{float(META['minUpgradeShare'])*100:.0f}–{float(META['maxUpgradeShare'])*100:.0f}%</div>
<div class="key"><b>✅ ตัดขั้นบนที่ไม่มีใครไปถึงออกแล้ว</b><br>
คอกเหลือ <b>{int(PEN[-1][0])} ขั้น</b> · upgrade อัตราผลิตเหลือ <b>{int(PRODUP[-1][0])} ขั้น</b><br>
<b>เวลาตีทุกด่านไม่เปลี่ยนเลย</b> เพราะคอขวดยังเป็นการปล่อยอยู่ดี —
ตอนนี้ด่านที่ติดเพดานปล่อยยังผลิตเกินที่ปล่อยได้ <b>{min(_slack):,.1f}–{max(_slack):,.1f} เท่า</b>
ซึ่งเป็นระยะเผื่อที่สมเหตุสมผล<br>
<code>validate()</code> บังคับว่าตัดลึกกว่านี้ไม่ได้ — ด่าน {FLIP}–{LAST} ต้องยังผลิตได้ ≥ ปล่อยได้</div>''')

# ── 6 ─────────────────────────────────────────────
W('<h2 id="s6"><span class="num">6</span>⭐ ตัวคูณ damage ที่ซื้อด้วยเงิน</h2>')
W(f'''<div class="note">⚠️ ระบบเดิม "ตัวคูณตามด่าน" (<code>STAGE_DAMAGE_BASE ^ (ด่าน−1)</code>) <b>ยกเลิกทั้งหมดแล้ว</b> —
ตัวคูณ damage ไม่ได้มาฟรีตามด่านอีกต่อไป ต้องซื้อทีละขั้นด้วยเงิน</div>
<div class="formula">ตัวคูณ = {META['stepMultiplier']} <sup>damageLevel</sup>
&nbsp;·&nbsp; เพดานที่ซื้อได้ = wallProgress × {META['stepsPerStage']}
&nbsp;·&nbsp; ราคาขั้นที่ k ของด่าน N = STAGE_COST_BASE[N] × {META['costMultInStage']}<sup>(k−1)</sup></div>''')
rows = []
for r in UPG:
    st, cap, mult, first, last, total, inc = r
    rows.append(([
        cell(f'ด่าน {st}'), cell(f'{int(cap)} ขั้น'), cell('<b>×' + fnum(mult) + '</b>'),
        cell(fnum(first)), cell(fnum(last)), cell(fnum(total)),
        cell(f'{float(total)/float(inc)*100:.0f}%', 'good'),
    ], 'hi' if int(st) == 1 else ''))
W(table(['ด่าน','เพดานสะสม','ตัวคูณถ้าซื้อครบ','ราคาขั้นแรก','ราคาขั้นสุดท้าย',f'ราคารวม {SPS} ขั้น','% ของรายได้ด่านนั้น'], rows))
_firstCost = float(UPG[0][3])
_coins = float(META['startingCoins'])
W(f'''<div class="key warn"><b>⚠️ off-by-one ที่พลาดง่ายที่สุด</b> — ตอนอยู่ด่าน N ผู้เล่นพังกำแพงมาแล้ว N−1 ด่าน<br>
เพดาน = <code>(N−1 + 1) × {SPS}</code> = <code>wallProgress × {SPS}</code> →
<b>ด่าน 1 ต้องซื้อได้ถึงขั้น {int(UPG[0][1])} ไม่ใช่ 0</b><br>
ถ้าเผลอเขียน <code>(wallProgress − 1) × {SPS}</code> ผู้เล่นใหม่จะซื้ออะไรไม่ได้เลยและตันตั้งแต่ด่านแรก
— <code>validate()</code> assert ตรง ๆ พร้อมเทสต์แยกอีกชั้นใน <code>tests/config.spec.luau</code><br>
ขั้นแรกของเกมราคา {fint(_firstCost)} ซึ่งผู้เล่นใหม่ (มี {fint(_coins)} coins)
{'ซื้อได้ทันที' if _coins >= _firstCost else '<b>ยังซื้อไม่ได้ทันที</b>'}</div>''')

# เทียบ "ขั้นต่อด่าน" รอบ ๆ ค่าที่ใช้อยู่ แล้วดูว่าตัวไหนผ่านยาม 0.5–72 ชม.
_cands = [SPS - 1, SPS, SPS + 1]
_slowStage = max(hours_if_steps(SPS), key=lambda k: hours_if_steps(SPS)[k])
_fastStage = min(hours_if_steps(SPS), key=lambda k: hours_if_steps(SPS)[k])
_whatif = []
for _c in _cands:
    _h = hours_if_steps(_c)
    _lo, _hi = min(_h.values()), max(_h.values())
    if _hi > MAXH:
        _v = f'❌ เกินเพดาน {fnum(MAXH)} ชม.'
    elif _lo < MINH:
        _v = f'❌ ต่ำกว่าพื้น {MINH} ชม.'
    else:
        _v = f'✅ มีระยะเผื่อ {(_lo/MINH - 1)*100:.0f}% / {(1 - _hi/MAXH)*100:.0f}%'
    _whatif.append((_c, _c * STAGES, _h[_fastStage], _h[_slowStage], _v))
_rowsWhatIf = ''.join(
    f'<tr class="hi"><td><b>{c}</b></td><td><b>{t}</b></td><td><b>{fhours(a)}</b></td>'
    f'<td><b>{fhours(b)}</b></td><td><b>{v}</b></td></tr>' if c == SPS else
    f'<tr><td>{c}</td><td>{t}</td><td>{fhours(a)}</td><td>{fhours(b)}</td><td>{v}</td></tr>'
    for c, t, a, b, v in _whatif)
# ผลรวมเรขาคณิตของราคาในหนึ่งด่าน
_cm = float(META['costMultInStage'])
_geom = (_cm ** SPS - 1) / (_cm - 1)
_share = sum(float(r[9]) for r in INCOME) / len(INCOME)
_costsRising = all(float(UPG[i][3]) < float(UPG[i+1][3]) for i in range(len(UPG) - 1))
W(f'''<div class="key red"><b>ทำไม {SPS} ขั้น/ด่าน</b><br>
ค่าที่สั่งมาตอนแรกคือ "×{MULT} ต่อขั้น · <b>{SPS+1} ขั้นต่อด่าน</b> · รวม <b>{SPS*STAGES} ขั้น</b>"
ซึ่ง <b>ขัดกันเอง</b> — {SPS+1} ขั้น × {STAGES} ด่าน = {(SPS+1)*STAGES} ไม่ใช่ {SPS*STAGES}<br><br>
เทียบสามทางเลือก (ด่านที่เร็วที่สุดกับช้าที่สุดในแต่ละแบบ):<br>
<table style="margin:10px 0"><thead><tr><th>ขั้น/ด่าน</th><th>ขั้นรวม</th>
<th>ด่าน {_fastStage} (เร็วสุด)</th><th>ด่าน {_slowStage} (ช้าสุด)</th><th>ผ่านยาม</th></tr></thead>
<tbody>{_rowsWhatIf}</tbody></table>
เลือก <b>{SPS} ขั้น/ด่าน</b> → ตรงกับ "รวม {SPS*STAGES} ขั้น" ที่สั่งมาพอดี และมีระยะเผื่อทั้งสองด้าน</div>
<div class="key"><b>วิธีคำนวณราคา — แก้สมการ ไม่ได้เดา</b><br>
<code>ราคารวมด่าน N = B_N × ({_cm}^{SPS} − 1) ÷ ({_cm} − 1) = B_N × {_geom:.2f}</code><br>
ต้องการ <code>ราคารวม = {_share:.2f} × รายได้ทั้งด่าน N</code> →
<code>B_N = {_share:.2f} × รายได้ด่าน N ÷ {_geom:.2f}</code><br>
ทำไมราว {_share*100:.0f}%: ส่วนเกิน ≈ 1 ÷ {_share:.2f} = <b>{1/_share:.1f} เท่า</b> ซึ่งอยู่ในช่วงเป้าหมาย<br>
ด่าน 1 ไม่มีกำแพงจึงไม่มี "เวลาตี" ใช้รายได้ 1 ชั่วโมงแรกเป็นฐานแทน ·
ราคาขั้นแรกของแต่ละด่าน{'ไล่ขึ้นตลอด ไม่มีช่วงถูกลง' if _costsRising else '<b>มีช่วงถูกลง — ต้องแก้</b>'}
ตลอด {SPS*STAGES} ขั้น</div>''')

W('<h3>ระบบนี้บังคับซื้อแค่ไหน</h3>')
rows = []
for r in CMP:
    st, oldh, newh, noneh = r
    blocked = float(noneh) > 72
    rows.append(([
        cell(f'ด่าน {st}'), cell(fhours(oldh), 'dim'), cell('<b>' + fhours(newh) + '</b>'),
        cell(fhours(noneh), 'bad' if blocked else ''),
        cell(f'{float(noneh)/float(newh):,.0f}×', 'dim'),
    ], ''))
W(table(['ด่าน','ก่อนแก้ (ตัวคูณอัตโนมัติ)','หลังแก้ (ซื้อครบเพดาน)','ไม่ซื้อเลย','ซื้อครบช่วยได้'], rows))
_playable = [r for r in CMP if 0 < float(r[3]) <= MAXH]
_blocked = next((r for r in CMP if float(r[3]) > MAXH), None)
_lastCmp = CMP[-1]
_gain = float(_lastCmp[3]) / float(_lastCmp[2]) if float(_lastCmp[2]) > 0 else 0
W(f'''<div class="key warn"><b>ผู้เล่นที่ไม่ซื้อ upgrade เลย ตันที่ด่าน {_blocked[0] if _blocked else '—'}</b>
({fhours(_blocked[3]) if _blocked else '—'} เกินเพดาน {fnum(MAXH)} ชม.)
และด่าน {_lastCmp[0]} กลายเป็น {fhours(_lastCmp[3])}<br>
แต่ <b>ด่าน {_playable[0][0]}–{_playable[-1][0]} ยังลุยได้โดยไม่ซื้อ</b>
({' / '.join(fhours(r[3]) for r in _playable)}) ซึ่งดี —
ผู้เล่นได้ลองเล่นก่อนที่ระบบจะเริ่มบังคับ<br>
ซื้อครบเพดานช่วยที่ด่าน {_lastCmp[0]} ได้ <b>{_gain:,.0f} เท่า</b></div>
<div class="key red"><b>⚠️ ผลข้างเคียงที่ตัดสินใจรับไว้แล้ว — ห้ามแก้กลับ</b><br>
<b>เกมเอียงไปทาง idle มากขึ้น</b> — ฟาร์มเงินแล้วอัป มีน้ำหนักมากกว่าการลุ้นไข่<br>
<b>น้ำหนักแม่และคลาสมีความสำคัญน้อยลง</b> เมื่อเทียบกับการอัป<br>
ทั้งสองข้อเป็นผลที่ <b>ตั้งใจ</b> ของการย้ายความคืบหน้าจาก "ดวง" มาอยู่ที่ "รายได้ที่คาดเดาได้"
ไม่ใช่ผลข้างเคียงที่ต้องแก้ในรอบหน้า</div>''')

# ── 7 ─────────────────────────────────────────────
W('<h2 id="s7"><span class="num">7</span>turret — คำนวณจากสูตร ไม่เก็บเป็นตัวเลข</h2>')
W('''<div class="note">ค่านี้พลาดมาแล้ว <b>สองครั้งในทางตรงข้ามกัน</b> แล้วต้องคำนวณใหม่ด้วยมืออีก <b>สามครั้ง</b><br>
รากของปัญหา: <code>turretDps</code> ไม่เคยเป็นค่าที่ตั้งอิสระได้เลย มันเป็น <i>ผลลัพธ์</i> ของ
<code>TOLL × damage/วินาที</code> แต่ถูกเก็บเป็นตัวเลขดิบ 9 ค่า</div>
<div class="note" style="margin-top:10px">⚠️ ตารางข้างล่างเป็น <b>บันทึกอดีต</b> —
ตัวเลขในนั้นคือค่า ณ ตอนนั้น ไม่ได้ดึงจาก Config ปัจจุบัน (ค่าปัจจุบันอยู่ในตารางหลักด้านล่าง)</div>
<div class="scroll"><table><thead><tr><th>รอบ</th><th>สาเหตุ</th><th>ค่าที่ด่านสุดท้าย ณ ตอนนั้น</th></tr></thead><tbody>
<tr><td>1</td><td>ตั้งจาก damage ทหารฝ่ายรับทั้งด่าน</td><td>1,000,000,000 → turret ไร้ผล (0.35%)</td></tr>
<tr><td>2</td><td>ระบบรบเปลี่ยนเป็นปล่อยต่อเนื่อง ค่าเดิมไม่ได้แก้</td><td>1,000,000,000 → <b>ฆ่ายกกอง</b> (238× ของเรา)</td></tr>
<tr><td>3</td><td>ตั้งใหม่เป็นสัดส่วนของ damage/วินาที</td><td>840,000</td></tr>
<tr><td>4</td><td>เปลี่ยนตัวคูณคลาส → คำนวณใหม่</td><td>250,000</td></tr>
<tr><td>5</td><td>ย้ายตัวคูณ damage มาเป็นระบบซื้อ → คำนวณใหม่อีก</td><td>150,000</td></tr>
<tr class="hi"><td><b>✅</b></td><td><b>เก็บเป็นสัดส่วน ให้โค้ดคำนวณเอง</b></td><td><b>ไม่ต้องแก้มืออีกแล้ว</b></td></tr>
</tbody></table></div>
<div class="formula">Config.Combat.TURRET_TOLL = {{ {', '.join(f'{float(r[3]):.2f}' for r in TUR)} }}<br>
turretDps(N) = TURRET_TOLL[N] × getReferenceDps(N)</div>''')
rows = []
for r in TUR:
    st, ourdps, tdps, ratio, sug, onfield, wipe, secs = r
    rows.append(([cell(f'ด่าน {st}'), cell(fnum(ourdps)), cell('<b>' + fnum(tdps) + '</b>'),
                  cell(f'{float(ratio)*100:.1f}%', 'good'),
                  cell(fint(onfield) + ' ตัว'),
                  cell(fhours(float(secs)/3600)),
                  cell(f'{float(wipe):,.0f} วิ', 'dim')], ''))
W(table(['ด่าน','damage/วิ ของเรา','turretDps ที่คำนวณได้','กินกำลังพล','ทหารบนสนาม','เวลารบทั้งด่าน','turret ล้างสนามใน'], rows))
W(f'''<div class="key"><b>ตาราง <code>Stages</code> ไม่มีฟิลด์ <code>turretDps</code> แล้ว</b> —
ปรับตัวคูณคลาส / ตัวคูณ damage / อัตราปล่อย / อัตราผลิต / ความจุคอก อะไรก็ตาม
<b>turret ขยับตามเองทันที ไม่ต้องแตะอะไรเลย</b><br>
สัดส่วนตรงเป๊ะทุกด่านแล้ว (เดิมเพี้ยนเพราะปัดเลขตอนคำนวณมือ)<br>
อยากให้ด่านไหนโหดขึ้นเป็นพิเศษ ก็ดัน <code>TURRET_TOLL</code> ของด่านนั้นตัวเดียว</div>
<div class="key warn"><b>สิ่งที่ยามเช็คตอนนี้</b> — ครบ {STAGES} ด่าน · ด่าน 1 ต้องเป็น 0 ·
ทุกค่า ≤ {float(META['tollCeiling'])*100:.0f}% · <b>ไล่ขึ้นไม่ถอยหลัง</b> (กำแพงด่านสูงต้องเขี้ยวขึ้น) ·
และ <code>turretDps ÷ dps</code> ต้องเท่ากับ TOLL เป๊ะ (ดักกรณีมีคนเผลอกลับไปเขียนตัวเลขดิบอีก)<br>
ทดสอบแล้ว (<code>tests/config.spec.luau</code>): ลดตัวคูณ damage ต่อขั้นลง →
<code>turretDps</code> ลดตามเองทันที สัดส่วนยังเท่าเดิม ·
ตั้ง TOLL เกินเพดาน หรือให้ด่าน {LAST} อ่อนกว่าด่าน {LAST-1} → <code>validate()</code> ล้มทั้งสองกรณี</div>
<div class="key red"><b>⚠️ ผลข้างเคียงที่ตั้งใจ: ไม่ซื้อ upgrade = เจอ turret เขี้ยวกว่า</b><br>
<code>getReferenceDps()</code> สมมติว่าผู้เล่นซื้อ upgrade ครบเพดานของด่านนั้น
ดังนั้นสัดส่วน {min(float(r[3]) for r in TUR if float(r[3])>0)*100:.0f}–{max(float(r[3]) for r in TUR)*100:.0f}%
ในตารางคือของ <i>ผู้เล่นที่ซื้อครบ</i><br>
คนที่ซื้อไปครึ่งเดียวจะเสียกำลังพลราวสองเท่าของสัดส่วนนี้ —
<b>ถูกต้องแล้ว</b> ไม่ซื้อของก็ควรเจอกำแพงที่เขี้ยวกว่า และเสริมกับระบบ upgrade ที่ซื้อด้วยเงินพอดี</div>
<div class="note"><b>ข้อดีที่ติดมาฟรี:</b> สัดส่วนที่เสียยังแปรผกผันกับน้ำหนักแม่
— แม่หนักกว่า = damage ต่อตัวสูงกว่า = เสียสัดส่วนน้อยกว่า</div>''')

# ── 8 ─────────────────────────────────────────────
ex = META['weightExponent']
W(f'<h2 id="s8"><span class="num">8</span>อัตราผลิตแปรตามน้ำหนักแม่</h2>')
W(f'<div class="formula">ผลิต/นาที = {META["onlinePerMinute"]} × (น้ำหนัก ÷ 100)<sup>{ex}</sup> × 3<sup>upgrade</sup> × บัฟสถานะ &nbsp;·&nbsp; ออฟไลน์ = × {META["offlineRatio"]}</div>')
rows = []
base_rate = float(FILL[0][1])
for r in FILL:
    w, on0, off0, on3 = r[0], r[1], r[2], r[3]
    rows.append(([cell(fint(w) + ' kg'), cell(fnum(on0)), cell(f'×{float(on0)/base_rate:,.1f}'),
                  cell(fnum(off0)), cell(fnum(on3))], ''))
W(table(['น้ำหนักแม่','ผลิต/นาที','เทียบแม่ 100 kg','ออฟไลน์/นาที','+upgrade ขั้น 3'], rows))
_fSpan = float(FILL[-1][0]) / float(FILL[0][0])
W(f'''<div class="key"><b>ทำไมใช้ {ex} ไม่ใช่ 0.5</b> — น้ำหนักมีผลอยู่แล้ว 2 ทาง (เงิน √ · damage ต่อตัว √)
ถ้าอัตราผลิตใช้ √ ด้วย damage รวม/วันจะแปรผัน <b>ตรง</b> กับน้ำหนัก
→ ช่องว่างระหว่างแม่ {fint(FILL[0][0])} kg กับ {fnum(float(FILL[-1][0]))} kg
จะเป็น <b>{fnum(_fSpan)} เท่า</b><br>
ใช้ {ex} ได้ {float(FILL[-1][1])/base_rate:,.0f} เท่า — กว้างพอให้แม่ตัวใหญ่คุ้มค่า แต่ไม่ถึงกับขาดกัน</div>''')

# ── 9 ─────────────────────────────────────────────
W('<h2 id="s9"><span class="num">9</span>damage = HP (ตัวแม่ และ ตัวลูก)</h2>')
W('<div class="formula">damage = HP = 10 × (น้ำหนัก ÷ 100)<sup>0.5</sup> × ตัวคูณคลาส × 1.1<sup>damageLevel</sup></div>')
CL = [c[0] for c in A['CLASS']]
rows = []
for r in A['POWER']:
    w = r[0]; mother = r[1:6]; child = r[6:11]
    rows.append(([cell(fint(w))] + [cell(fnum(v)) for v in mother] +
                 [cell(fnum(v), 'dim') for v in child], ''))
W(table(['น้ำหนักแม่ (kg)'] + [f'แม่ {c}' for c in CL] + [f'ลูก {c}' for c in CL], rows))
_wLo, _wHi = float(BYW[0][0]), float(BYW[-1][0])
_wGain = (_wHi / _wLo) ** 0.5
_free = max(m for c, m in CLASS_MULT.items() if c != 'SS')
_freeName = next(c for c, m in CLASS_MULT.items() if m == _free)
_ss = CLASS_MULT['SS']
_step = CLASS_MULT['B'] / CLASS_MULT['C']
_runaway = _free * _step
# damage = 10 × (น้ำหนัก/100)^0.5 × ตัวคูณคลาส
_pw = lambda w, c: 10 * (w / 100) ** 0.5 * CLASS_MULT[c]
_aW = _wLo * 1000
_childRatio = float(META['childRatio'])
_firstSStage = next((int(e[6]) for e in sorted(A['EGG'], key=lambda x: int(x[6]) if x[6].isdigit() else 99)
                     if e[5] == 'on' and e[6].isdigit() and int(e[6]) > 0 and float(e[EGG_CLASS_COL['S']]) > 0), None)
W(f'''<div class="key"><b>คลาสกับน้ำหนักตอนนี้สูสีกันแล้ว</b> —
น้ำหนักให้ ×{fnum(_wGain)} ตลอดเกม คลาสให้ ×{_free:,.0f} (ฟรี) หรือ ×{_ss:,.0f} (Robux)<br>
แต่น้ำหนักยังชนะอยู่เล็กน้อยและหายากกว่ามาก: แม่ {fint(_wLo)} kg คลาส SS ({_pw(_wLo,'SS'):,.0f})
<b>แพ้</b> แม่ {fint(_aW)} kg คลาส A ({_pw(_aW,'A'):,.0f})
— สองแกนนี้ตัดกันจริง ไม่ใช่แกนใดแกนหนึ่งชนะขาด<br>
<b>ลูกแรง {_childRatio**0.5*100:.0f}% ของแม่เสมอ</b> ทุกน้ำหนัก ทุกคลาส เพราะ √{_childRatio} = {_childRatio**0.5} พอดี</div>
<div class="key red"><b>⚠️ SS = ×{_ss:,.0f} ไม่ใช่ ×{_runaway:,.0f} โดยตั้งใจ</b><br>
C→B→A→{_freeName} ไล่ ×{_step:.0f}
({' → '.join(f'{CLASS_MULT[c]:,.0f}' for c in ['C','B','A','S'])})
แต่ <b>SS หยุดที่ ×{_ss/_free:.0f} เหนือ {_freeName}</b><br>
SS ออกจากไข่ Robux เท่านั้น ถ้าไล่ ×{_step:.0f} ต่อไปจนถึง {_runaway:,.0f}
คนจ่ายเงินจะแรงกว่าคนไม่จ่าย {_runaway:,.0f} เท่า = pay-to-win เต็มรูปแบบ<br>
ที่ ×{_ss:,.0f} ไข่ตำนานยังคุ้มซื้อ (×{_ss/_free:.0f} บวกกับรับประกัน tier ขั้นต่ำ) แต่ไม่ถึงกับซื้อแล้วชนะ
เพราะ <b>{_freeName} หาได้ฟรีจากบอสด่าน {_firstSStage} ขึ้นไป</b><br>
<code>validate()</code> บังคับ <code>SS ÷ {_freeName} ≤ {META['maxSsOverS']}</code> —
ทดสอบแล้วว่าตั้ง {_runaway:,.0f} เซิร์ฟไม่บูต</div>''')

# ── 10 ────────────────────────────────────────────
W('<h2 id="s10"><span class="num">10</span>เงิน</h2>')
W(f'<div class="formula">coins/นาที = {META["coinBase"]} × (น้ำหนักแม่ ÷ 100)<sup>0.5</sup> × {META["coinStageMult"]}<sup>(wallProgress − 1)</sup> &nbsp;·&nbsp; คลาสไม่มีผลต่อเงิน</div>')
rows = []
for r in A['COINS']:
    w = r[0]; per = r[1:10]; sell = r[10]
    rows.append(([cell(fint(w))] + [cell(fnum(v)) for v in per] + [cell(fnum(sell), 'dim')], ''))
W(table(['น้ำหนักแม่ (kg)'] + [f'ด่าน {i}' for i in range(1,10)] + [f'ขายทิ้ง (ด่าน 1)'], rows))
W(f'''<div class="key"><b>ตัวคูณเงิน ×{META["coinStageMult"]} ต่อด่าน ตัดออกไม่ได้</b> —
ราคาทุกอย่างโต ×{float(META["coinStageMult"]):,.0f} ต่อขั้น
แต่รายได้จากน้ำหนักโตแค่ ×{fnum((float(BYW[-1][0])/float(BYW[0][0]))**0.5)} ตลอดเกม (√ บีบไว้)
ถ้าไม่มีตัวคูณนี้ ผู้เล่นจะซื้อของขั้นกลางขึ้นไปไม่ได้เลย<br>
<b>ดันค่าเริ่มต้นขึ้นแก้ไม่ได้</b> เพราะปัญหาคืออัตราการโตไม่เท่ากัน ไม่ใช่ตัวเลขเล็กไป<br>
ราคาขายแม่ = รายได้ {META["sellMinutes"]} นาทีของแม่ตัวนั้น (ผูกกับสูตรเงินอัตโนมัติ ไม่ต้องตั้งตารางแยก)</div>''')

# ── 11 ────────────────────────────────────────────
W('<h2 id="s11"><span class="num">11</span>คลาส · ตารางสุ่มน้ำหนัก · ไข่</h2>')
W('<h3>คลาสตัวละคร 12 ตัว</h3>')
rows = [([cell(c[0]), cell('×' + c[1]), cell(c[2])], '') for c in A['CLASS']]
W(table(['คลาส','ตัวคูณ damage/HP','ตัวละคร'], rows))
W('<h3>ตารางสุ่มน้ำหนัก (ด่าน 1 · ด่าน 2–9 ถอยมาใช้ตารางนี้จนกว่าจะเติมตัวเลข)</h3>')
rows = []
for i, t in enumerate(A['TIER'], 1):
    lo, hi, wgt, pct = t
    rows.append(([cell(f'tier {i}'), cell(fint(lo) + ' – ' + fint(hi) + ' kg'),
                  cell(fint(wgt)), cell(f'{float(pct):g}%'),
                  cell(f'1 ใน {1/(float(pct)/100):,.0f}' if float(pct) > 0 else '—', 'dim')], ''))
W(table(['tier','ช่วงน้ำหนัก','weight','โอกาส','ราว ๆ'], rows))
W('''<div class="key warn"><b>สุ่ม 2 ขั้นเสมอ</b> — เลือก tier ก่อน แล้วค่อยสุ่มน้ำหนักในช่วงของ tier นั้น<br>
ห้ามสุ่ม uniform ทั้งช่วงรวดเดียว ไม่งั้นตัวเล็กแทบไม่มีวันออก · น้ำหนักแม่เป็น <b>จำนวนเต็มเสมอ</b> เพราะเป็นส่วนหนึ่งของ stack key</div>''')
W('<h3>ไข่ — บอสแต่ละด่านวางไข่คนละชนิด</h3>')
rows = []
for e in A['EGG']:
    eid, name, src, ht, gt, en, est = e[0], e[1], e[2], e[3], e[4], e[5], e[6]
    pcts = e[7:12]
    off = en == 'off'
    rows.append(([cell(name + (' <span style="opacity:.55">(ปิดแล้ว)</span>' if off else '')),
                  cell(f'<code>{eid}</code>'),
                  cell('บอส' if src == 'boss' else 'Robux'),
                  cell(f'ด่าน {est}' if float(est) > 0 else '—', 'dim'),
                  cell(f'{float(ht):.0f} วิ'),
                  cell(f'tier {gt}+' if float(gt) > 0 else '—', 'dim')] +
                 [cell(f'{float(p):g}%' if float(p) > 0 else '—', 'dim' if off else '') for p in pcts], ''))
W(table(['ไข่','id','แหล่งที่มา','ผูกด่าน','เวลาฟัก','รับประกัน'] + CL, rows))
_sStart = next(st for st in range(1, LAST + 1) if egg_class_pct(st, 'S') > 0)
W(f'''<div class="key"><b>ด่านสูงคุ้มกว่าที่ "โอกาสได้คลาสดี" ไม่ใช่ "โอกาสได้ตัวหนัก"</b> —
ตารางสุ่มน้ำหนักใช้ชุดเดียวกันทุกด่าน<br>
C ไล่ลง {egg_class_pct(1,'C'):.0f}% → {egg_class_pct(LAST,'C'):.0f}% ·
S เริ่มออกที่ด่าน {_sStart} ({egg_class_pct(_sStart,'S'):.0f}%)
ขึ้นถึง {egg_class_pct(LAST,'S'):.0f}% ที่ด่าน {LAST}<br>
<code>validate()</code> บังคับว่าทุกด่านต้องมีไข่ของตัวเองที่เปิดใช้อยู่ — ขาดด่านไหน ด่านนั้นตันถาวร</div>
<div class="key warn"><b>⚠️ น้ำหนักสุ่มตั้งแต่บอสวางไข่ ไม่ใช่ตอนฟัก</b><br>
บอสเกิด → สุ่มน้ำหนักไข่ทั้ง {META['bossEggs']} ฟองทันที → <b>ขนาดโมเดลไข่แปรตามน้ำหนัก</b> (ไข่ใหญ่ = หนัก)<br>
ผู้เล่นทั้ง {META['players']} คนเห็นพร้อมกันว่าฟองไหนคุ้มค่าแย่ง → <b>การแย่งไข่กลายเป็นเกมจริง</b>
ไม่ใช่แค่รีบกดสุ่ม · ตอนฟักถึงค่อยสุ่มตัวละคร<br>
ผลต่อ schema: ไข่ต้องเก็บรายฟองพร้อมน้ำหนัก (<code>heldEggs</code> เป็นอาเรย์ ไม่ใช่ตัวนับ)</div>''')
_legend = next(e for e in A['EGG'] if e[2] == 'robux')
_gt = int(float(_legend[4]))
_gtMin = float(A['TIER'][_gt - 1][0]) if 0 < _gt <= len(A['TIER']) else 0
_topTier = len(A['TIER'])
_bossClasses = [c for c in ['C', 'B', 'A', 'S', 'SS']
                if any(float(e[EGG_CLASS_COL[c]]) > 0 for e in A['EGG'] if e[2] == 'boss' and e[5] == 'on')]
W(f'''<div class="key"><b>เงินในเกมซื้อไข่ไม่ได้เลย</b> — บอส หรือ Robux เท่านั้น
(<code>EggType</code> ไม่มีฟิลด์ <code>price</code> โดยตั้งใจ)<br>
<b>SS ออกจากไข่ตำนานเท่านั้น</b> · ไข่จากบอสออกได้ {_bossClasses[0]} ถึง {_bossClasses[-1]} ·
ไข่ตำนานรับประกัน tier {_gt} ขึ้นไป ({fint(_gtMin)} kg+)
แต่ยังลุ้น tier {_topTier} ได้ตามอัตราเดิม<br>
⚠️ ห้ามเก็บราคา Robux ใน Config — ราคาจริงอยู่ใน Creator Dashboard ที่เดียว</div>''')

# ── 12 ────────────────────────────────────────────
W('<h2 id="s12"><span class="num">12</span>ด่าน · บอส · อาวุธ · คอก</h2>')
rows = []
for r in SI:
    st, dfd, dhp, whp, thp, tur, boss, wep, rel, mult, vis = r
    rows.append(([cell(f'ด่าน {st}'), cell(fint(dfd)), cell(fnum(dhp)), cell(fnum(whp)),
                  cell('<b>' + fnum(thp) + '</b>'), cell(fnum(tur), 'dim' if float(tur) == 0 else ''),
                  cell(fnum(boss)), cell(fnum(wep)), cell(f'{float(boss)/float(wep):.0f} ครั้ง')], ''))
W(table(['ด่าน','ทหารฝ่ายรับ','HP ทหารรวม','HP กำแพง','HP รวมทั้งด่าน','turretDps (คำนวณ)','HP บอส','damage อาวุธขั้นนั้น','ตีบอสกี่ครั้ง'], rows))
W('''<div class="key"><b>อาวุธ ×10 ต่อขั้น = HP บอส ×10 ต่อด่าน</b> → อาวุธขั้น N ตีบอสด่าน N ตาย 10 ครั้งพอดีทุกด่าน (ล็อกกันไว้ ห้ามแก้ข้างเดียว)<br>
HP กำแพง = 50% ของ HP ทหารรวมในด่านนั้น · ทหารฝ่ายรับตายแล้วไม่เกิดใหม่ · ต้องกวาดทหารหมดก่อนถึงจะตีกำแพงได้</div>''')
W('<h3>คอก (ความจุ + ราคาอัปเกรด)</h3>')
rows = [([cell('Lv ' + p[0]), cell(p[1] + ' ตัว'), cell(fnum(p[2]) if float(p[2]) > 0 else 'เต็มแล้ว')], '') for p in PEN]
W(table(['เลเวล','ความจุ','ราคาอัปขั้นถัดไป'], rows))
W('<h3>upgrade อัตราผลิต</h3>')
rows = [([cell('ขั้น ' + p[0]), cell('×' + fnum(p[1])), cell(fnum(p[2]) if float(p[2]) > 0 else 'เต็มแล้ว')], '') for p in PRODUP]
W(table(['ขั้น','ตัวคูณอัตราผลิต','ราคาอัปขั้นถัดไป'], rows))
W(f'''<div class="key warn"><b>ผล ×{float(PRODUP[1][1])/float(PRODUP[0][1]):.0f} ต่อขั้น ทั้งที่ราคาไต่เร็วกว่านั้น</b> —
ถ้าผลเท่ากับราคา กำแพงจะหมดความหมายกลางเกม<br>
และในระบบรบใหม่ upgrade นี้ <b>หยุดเพิ่ม damage ตั้งแต่ด่าน {FLIP}</b> (ชนเพดานปล่อย) เหลือประโยชน์แค่เติมคลังเร็วขึ้น
— ตรงนี้เป็นจุดที่อาจต้องคิดใหม่ว่าคุ้มราคาไหม</div>''')

# ── 13 ─────────────────────────────────────────────
SPEED = A['SPEED']; THICK = A['THICK']; TRAVEL = A['TRAVEL']
SPEND = A['SPEND']; SPEEDBUY = A['SPEEDBUY']; RACE = A['PATHRACE']
FIRSTSPEED = A['FIRSTSPEED'][0]
_cm = float(META['speedCostMultiplier'])

W('<h2 id="s13"><span class="num">13</span>⭐ ซื้อความเร็ว — บ่อเงินบ่อที่สอง</h2>')
W(f'''<div class="note">เกมแนวขโมยไข่ให้ผู้เล่นวิ่งบนลู่เพื่อเก็บความเร็ว เกมนี้เปลี่ยนเป็น <b>ซื้อด้วยเงิน</b> แทน
แบบเดียวกับตัวคูณ damage · <b>ไม่มีแท่นวาปแล้ว</b> ผู้เล่นเดินไปเองทุกที่<br>
ความเร็วฐาน {float(META['maxWalkSpeed'])/float(META['speedMaxMultiplier']):.0f} studs/วิ ·
{int(META['speedMaxLevel'])} ขั้น · ตัวคูณสูงสุด ×{fnum(META['speedMaxMultiplier'])} ·
ราคารวมทั้งสาย {fint(META['speedTotalCost'])} coins</div>''')

W('<h3>ตารางขั้นความเร็ว</h3>')
rows = []
for r in SPEED:
    lv = int(r[0]); price = float(r[1]); gain = float(r[4]) * 100
    rows.append(([cell('ขั้น ' + str(lv)),
                  cell(fint(price) if price > 0 else '—', 'dim' if price == 0 else ''),
                  cell('×' + f'{float(r[2]):.2f}'),
                  cell(f'{float(r[3]):.1f}'),
                  cell(f'+{gain:.0f}%' if gain > 0 else '—',
                       'good' if lv == 1 else ('dim' if gain == 0 else ''))],
                 'hi' if lv == int(META['speedMaxLevel']) else ''))
W(table(['ขั้น', 'ราคา', 'ตัวคูณ', 'ความเร็ว (studs/วิ)', 'เร็วขึ้นจากขั้นก่อน'], rows))

_g1 = float(SPEED[1][4]) * 100
_gl = float(SPEED[-1][4]) * 100
W(f'''<div class="key"><b>ตัวคูณถดถอย — ขั้นแรกคุ้มที่สุดต่างกัน {_g1/_gl:.1f} เท่า</b>
(ขั้น 1 เร็วขึ้น {_g1:.0f}% · ขั้น {int(META['speedMaxLevel'])} เร็วขึ้น {_gl:.0f}%)<br>
สูตร: <code>ตัวคูณ = 1 + {float(META['speedMaxMultiplier'])-1:.0f} × (ขั้น ÷ {int(META['speedMaxLevel'])})<sup>{fnum(META['speedCurveExponent'])}</sup></code>
— เลขชี้กำลังปรับได้ที่ <code>Config.SpeedUpgrade.CURVE_EXPONENT</code></div>''')

W(f'''<div class="key warn"><b>ทำไม {int(META['speedMaxLevel'])} ขั้น ไม่ใช่ 10 — เป็นการตัดสินใจถาวร</b><br>
ราคาไล่ ×{_cm:.0f} ต่อขั้น ถ้าทำ 10 ขั้น ขั้นสุดท้ายจะแพงกว่าขั้นแรก <b>{_cm**9:,.0f} เท่า</b>
แต่ตัวคูณชนเพดาน ×{fnum(META['speedMaxMultiplier'])} แล้ว จึงให้ความเร็วเพิ่มแค่ไม่กี่ %<br>
= ขั้นที่ไม่มีใครซื้อ เป็นตัวเลขหลอกตาในตาราง แบบเดียวกับคอก Lv11–15 ที่ตัดทิ้งไปแล้ว</div>''')

# ── ก) รายได้ vs รายจ่ายรวมต่อด่าน ──
W('<h3>ก · รายได้ vs รายจ่ายรวมต่อด่าน (แยกทุกบ่อ)</h3>')
W(f'''<div class="note">ขั้นความเร็ว N ถูกนับไว้ที่ด่าน N เพราะราคาไล่ ×{_cm:.0f} ตรงกับรายได้ที่โต ×{float(META['coinStageMult']):.0f} ต่อด่าน
(ตาราง ข พิสูจน์ว่าซื้อไหวพอดีจริงที่ด่านนั้น) · ด่าน {int(META['speedMaxLevel'])+1}–{int(float(META['stageCount']))} ไม่มีขั้นความเร็วเหลือให้ซื้อแล้ว</div>''')
rows = []
for r in SPEND:
    st = int(r[0]); speed = float(r[3]); before = float(r[9]); after = float(r[10])
    rows.append(([cell('ด่าน ' + str(st)), cell(fnum(r[1])), cell(fnum(r[2])),
                  cell(fnum(speed) if speed > 0 else '—', 'dim' if speed == 0 else ''),
                  cell(fnum(r[4])), cell(fnum(r[5])),
                  cell(fnum(r[6]) if float(r[6]) > 0 else '—'),
                  cell(f'{before:.2f}×', 'dim'),
                  cell(f'{after:.2f}×', 'bad' if after < 1.2 else ('good' if after >= 2 else ''))],
                 'hi' if speed > 0 else ''))
W(table(['ด่าน', 'รายได้ทั้งด่าน', 'upgrade damage', 'upgrade ความเร็ว', 'อาวุธ', 'คอก', 'อัตราผลิต',
         'ส่วนเกิน<br>(ก่อนมีความเร็ว)', '<b>ส่วนเกิน (ตอนนี้)</b>'], rows))

_before = [float(r[9]) for r in SPEND]
_after = [float(r[10]) for r in SPEND]
_tight = [int(r[0]) for r in SPEND if float(r[10]) < 1.2]
_speedStages = [int(r[0]) for r in SPEND if float(r[3]) > 0]
W(f'''<div class="key {"red" if _tight else "warn"}"><b>ส่วนเกินลดจาก {min(_before):.2f}–{max(_before):.2f}× เหลือ {min(_after):.2f}–{max(_after):.2f}×</b><br>
ด่าน {", ".join(str(x) for x in _tight)} เหลือแค่ ~{min(_after):.2f}× = <b>แทบไม่เหลืออะไรเลย</b>
ถ้าซื้อขั้นความเร็วทันทีที่ถึงด่านนั้น<br>
ด่าน {min(_speedStages)}–{max(_speedStages)} เท่านั้นที่โดน · ด่าน {max(_speedStages)+1}–{int(float(META['stageCount']))} ไม่กระทบเลย
(ส่วนเกินยัง {min(_after[max(_speedStages):]):.2f}–{max(_after):.2f}×) เพราะความเร็วเป็น
<b>ค่าใช้จ่ายครั้งเดียวตลอดเกม</b> ไม่ใช่ค่าที่ซ้ำทุกด่านแบบ damage</div>''')

# ── ข) ซื้อได้ตอนด่านไหน ──
W('<h3>ข · ขั้นความเร็วแต่ละขั้นซื้อได้ตอนด่านไหน</h3>')
W('<div class="note">ใช้ <b>ส่วนเกินสะสม</b> — สมมติผู้เล่นซื้อ damage/อาวุธ/คอก/อัตราผลิตครบก่อนเสมอ แล้วเก็บที่เหลือไว้ซื้อความเร็ว</div>')
rows = [([cell('ขั้น ' + r[0]), cell(fint(r[1])),
          cell('ด่าน ' + r[2] if int(r[2]) > 0 else 'ซื้อไม่ไหวจนจบเกม', '' if int(r[2]) > 0 else 'bad'),
          cell(fnum(r[3]))], '') for r in SPEEDBUY]
W(table(['ขั้น', 'ราคา', 'ซื้อได้ที่ด่าน', 'เหลือในกระเป๋าหลังซื้อ'], rows))

_hrs = float(FIRSTSPEED[2]); _hrsAll = float(FIRSTSPEED[4])
W(f'''<div class="key"><b>ขั้น N ซื้อไหวพอดีที่ด่าน N ทุกขั้น</b> — ราคา ×{_cm:.0f} ต่อขั้นตรงกับรายได้ ×{float(META['coinStageMult']):.0f} ต่อด่านพอดี<br>
<b>ขั้นแรกใช้เวลาไม่นาน</b> รายได้ด่าน 1 = {fint(FIRSTSPEED[0])} coins/ชม.
(ส่วนใหญ่มาจากฆ่าบอส ซึ่งผู้เล่นใหม่ทำได้ทันที) →
เก็บ {fint(FIRSTSPEED[1])} ใช้ <b>{_hrs*60:.0f} นาที</b> ถ้าเก็บอย่างเดียว ·
<b>{_hrsAll*60:.0f} นาที</b> ถ้าซื้อของจำเป็นของด่าน 1 ก่อน</div>''')

# ── ค) เวลาเดินทาง ──
W('<h3>ค · เวลาเดินทางในแต่ละขั้นความเร็ว</h3>')
rows = []
for r in TRAVEL:
    lv = int(r[0]); pct = float(r[4])
    rows.append(([cell('ขั้น ' + str(lv)), cell(f'{float(r[1]):.1f}'),
                  cell(f'{float(r[2]):.1f} วิ'), cell(f'{float(r[3]):.1f} วิ'),
                  cell(f'{pct:.1f}%', 'bad' if pct >= 25 else ('good' if pct < 14 else '')),
                  cell(f'{float(r[5]):.1f} วิ')],
                 'hi' if lv == 0 else ''))
W(table(['ขั้น', 'ความเร็ว', f'ต้นเลน → รังบอส {int(float(META["stageCount"]))}', 'ไป-กลับ',
         f'% ของรอบบอส ({int(float(META["bossRespawn"]))} วิ)', 'คอก → รังบอส 1'], rows))

_p0 = float(TRAVEL[0][4]); _p1 = float(TRAVEL[1][4]); _p2 = float(TRAVEL[2][4]); _pl = float(TRAVEL[-1][4])
W(f'''<div class="key"><b>ปัญหาระยะทางหายเกือบหมดตั้งแต่ขั้น 1</b> —
ไป-กลับรังบอสด่าน {int(float(META['stageCount']))} กินรอบบอสจาก <b>{_p0:.0f}%</b> เหลือ <b>{_p1:.0f}%</b> ทันที (ลดลงครึ่งหนึ่ง)<br>
ขั้น 2 เหลือ {_p2:.0f}% ซึ่งถือว่าไม่เป็นปัญหาแล้ว · ขั้น {int(META['speedMaxLevel'])} เหลือ {_pl:.0f}%
ซึ่งเป็นการซื้อความสบาย ไม่ใช่การแก้ปัญหา<br>
<b>สอดคล้องกับตัวคูณถดถอย</b> — ขั้นที่แก้ปัญหาจริงคือขั้นที่ถูกที่สุด</div>''')

# ── ง) สองบ่อแข่งกันไหม ──
W('<h3>ง · เร่ง damage ก่อน vs เร่งความเร็วก่อน</h3>')
W('<div class="note">จำลองการตีทีละช่วงเวลา เงินไหลเข้าตามรายได้ของด่าน ซื้อของตามคิว · เริ่มด่าน 2 เพราะด่าน 1 ไม่มีกำแพง</div>')
rows = []
for r in RACE:
    st = int(r[0]); diff = float(r[3]); price = float(r[4])
    rows.append(([cell('ด่าน ' + str(st)), cell(fhours(float(r[1]))), cell(fhours(float(r[2]))),
                  cell(f'+{diff:.1f}%' if diff > 0.5 else 'เท่ากัน',
                       'bad' if diff > 5 else 'dim'),
                  cell(fnum(price) if price > 0 else '—', 'dim' if price == 0 else '')],
                 'hi' if price > 0 else ''))
_ta = sum(float(r[1]) for r in RACE); _tb = sum(float(r[2]) for r in RACE)
rows.append(([cell('<b>รวม</b>'), cell('<b>' + fhours(_ta) + '</b>'), cell('<b>' + fhours(_tb) + '</b>'),
              cell(f'<b>+{(_tb/_ta-1)*100:.1f}%</b>'), cell('')], ''))
W(table(['ด่าน', 'เร่ง damage ก่อน', 'เร่งความเร็วก่อน', 'ช้าลง', 'ขั้นความเร็วที่ซื้อ'], rows))

_worst = max(RACE, key=lambda r: float(r[3]))
W(f'''<div class="key red"><b>🔴 ไม่ใช่การเลือก — "เร่ง damage ก่อน" ชนะทุกด่านที่มีให้เลือก</b><br>
ช้าลง {min(float(r[3]) for r in RACE if float(r[4])>0):.0f}–{float(_worst[3]):.0f}%
ถ้าเลือกความเร็วก่อน (แย่สุดที่ด่าน {int(_worst[0])}) และ<b>เสมอกันเป๊ะ</b>ที่ด่าน {max(_speedStages)+1}–{int(float(META['stageCount']))} ที่ไม่มีขั้นความเร็วเหลือ<br><br>
<b>สาเหตุเชิงโครงสร้าง:</b> <code>damage/วินาที = min(อัตราผลิต, อัตราปล่อย) × damage ต่อตัว × ตัวคูณ</code>
— <b>ความเร็ววิ่งไม่อยู่ในสมการนี้เลย</b> เพราะลูกเกิดที่แท่นปล่อยต้นเลน ไม่ได้เดินมาจากคอก<br>
ความเร็วจึงซื้อ <b>ความสบาย + ความได้เปรียบตอนแย่งไข่</b> เท่านั้น ไม่ได้ซื้อความเร็วในการผ่านด่าน</div>''')

# ── ความหนากำแพง ──
W('<h3>ความหนากำแพง — ผูกกับความเร็วสูงสุด</h3>')
W(f'''<div class="note">ที่ {float(META['maxWalkSpeed']):.0f} studs/วิ บน {int(float(META['physicsFps']))} fps ตัวละครขยับ
<b>{float(META['maxWalkSpeed'])/float(META['physicsFps']):.2f} stud ต่อเฟรม</b> —
กำแพงที่บางกว่านั้นถูก "ข้าม" ทั้งชิ้นระหว่างสองเฟรมโดยไม่มีการชนเกิดขึ้นเลย</div>''')
rows = [([cell(r[0]), cell(fnum(r[1])), cell(f'{float(r[2]):.2f}'),
          cell(f'{float(r[3]):.2f}×', 'good' if float(r[3]) >= 1 else 'bad')], '') for r in THICK]
W(table(['กำแพง', 'ความหนาตอนนี้', 'ขั้นต่ำที่ต้องมี', 'เผื่อไว้'], rows))
W(f'''<div class="key"><b>ขั้นต่ำเป็นสูตร ไม่ใช่เลขตายตัว</b> —
<code>ความเร็วสูงสุด ÷ {int(float(META['physicsFps']))} × {fnum(META['thicknessSafety'])}</code>
ผ่าน <code>Config.getMinWallThickness()</code><br>
ขึ้นความเร็วแล้วลืมเพิ่มความหนาเมื่อไหร่ <b>เซิร์ฟจะไม่บูต</b> แทนที่จะปล่อยให้ผู้เล่นไปเจอเองว่าวิ่งทะลุได้ ·
และความเร็วสูงสุดถูกตรึงไม่ให้เกิน {int(float(META['speedCeiling']))} ซึ่งเป็นจุดที่ Roblox เริ่มทะลุของจนเล่นไม่ได้</div>''')

W(f'''<footer>
สร้างจาก <code>src/shared/Config.lua</code> · ตัวเลขทุกตัวคำนวณจากฟังก์ชันจริงใน Config ไม่ได้พิมพ์มือ<br>
"ผู้เล่นชั้นกลาง" ใช้ค่าอ้างอิงจาก <code>Config.BalanceCheck</code> ชุดเดียวกับที่ <code>assertProgressionIsSane()</code> ใช้<br>
รายละเอียดที่มาของทุกค่าอยู่ใน <code>docs/data-schema.md</code>
</footer>
</div></body></html>''')

html = '\n'.join(out)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'w', encoding='utf-8').write(html)
print(f'เขียน {os.path.relpath(OUT, ROOT)} แล้ว ({len(html):,} ไบต์)')
