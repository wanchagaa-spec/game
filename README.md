# egg-army-game

เกม Roblox แนวผสม: **แย่งไข่จากบอส → ฟักได้ตัวแม่ → วางในคอก → แม่ผลิตลูก → ปล่อยลูกไปพังกำแพงด่านถัดไป**
(loop คล้าย Age of War ผสมระบบสะสมแบบ pet simulator)

รายละเอียดแผนพัฒนา กฎการทำงาน และสถานะปัจจุบัน อยู่ใน [`CLAUDE.md`](./CLAUDE.md)

---

## Workflow แบบสองเครื่อง

โปรเจกต์นี้แยกเป็นสองฝั่ง **"เครื่องเขียนโค้ด" กับ "เครื่องเปิด Studio"** โดยมี GitHub เป็นตัวกลาง
เหตุผล: Roblox Studio รันบน Linux sandbox ไม่ได้ แต่การเขียน source แก้ได้ทุกที่

```
┌─────────────────────────┐         ┌──────────────┐         ┌─────────────────────────┐
│ Claude Code on the web  │  push   │              │  pull   │ เครื่องที่บ้าน (Win/Mac) │
│ (Linux sandbox)         │ ──────► │    GitHub    │ ──────► │                         │
│                         │         │              │         │  rojo build / rojo serve│
│ แก้ไฟล์ .lua + config    │         │              │         │  → Roblox Studio        │
└─────────────────────────┘         └──────────────┘         └─────────────────────────┘
```

### ฝั่งที่ 1 — เขียนโค้ด (Claude Code on the web)

ทำที่นี่: แก้ไฟล์ `.lua` ใน `src/`, แก้ `default.project.json`, เขียนเอกสาร
จบแล้ว commit + push ขึ้น branch บน GitHub

**ทำไม่ได้ที่นี่:** เปิด Studio, ทดสอบเกมจริง, แก้ไฟล์ `.rbxl` (เป็น binary ที่ build ออกมา — แก้ที่ source เท่านั้น)

### ฝั่งที่ 2 — รันจริง (เครื่องที่บ้าน)

ครั้งแรกต้องติดตั้ง Rojo ก่อน แล้วหลังจากนั้นเลือกได้ 2 โหมด

#### โหมด A — build เป็นไฟล์ place (เหมาะกับการเปิดดูรอบเดียว)

```bash
git pull
rojo build -o game.rbxl
```

แล้วเปิด `game.rbxl` ด้วย Roblox Studio (ดับเบิลคลิก หรือ File → Open)

> `game.rbxl` อยู่ใน `.gitignore` — **ไม่ต้อง commit** เพราะ build ใหม่ได้เสมอจาก source
> ถ้าแก้โค้ดเพิ่ม ต้อง build ใหม่แล้วเปิดใหม่ ไฟล์ที่เปิดค้างไว้จะไม่อัปเดตเอง

#### โหมด B — rojo serve + plugin (เหมาะกับการพัฒนาต่อเนื่อง แนะนำ)

```bash
git pull
rojo serve
```

จากนั้นใน Studio:

1. ติดตั้ง Rojo plugin (Studio → Plugins → Manage Plugins → หา "Rojo") — ทำครั้งเดียว
2. เปิด place ที่จะใช้ (ครั้งแรกใช้ `rojo build -o game.rbxl` สร้างก่อนได้)
3. กดปุ่ม Rojo ใน toolbar → **Connect** (ค่าเริ่มต้น `localhost:34872`)

พอเชื่อมแล้ว **แก้ไฟล์ `.lua` ในโฟลเดอร์นี้แล้ว Studio จะอัปเดตให้ทันที** ไม่ต้อง build ใหม่

> ทิศทางการ sync เป็นแบบ **โฟลเดอร์ → Studio** ทางเดียว
> ถ้าไปแก้สคริปต์ใน Studio ตรง ๆ ของจะถูกเขียนทับ — ให้แก้ที่ไฟล์ในโฟลเดอร์นี้เสมอ
> ส่วนที่ต้องปั้นใน Studio จริง ๆ (โมเดล แผนที่ แสง) ทำใน Studio ได้ตามปกติ เพราะ Rojo แตะเฉพาะ path ที่ระบุใน `default.project.json`

### ติดตั้ง Rojo (ทำครั้งเดียวที่เครื่องบ้าน)

เลือกวิธีใดวิธีหนึ่ง:

```bash
# ผ่าน Aftman (แนะนำ — ล็อกเวอร์ชันต่อโปรเจกต์ได้)
aftman add rojo-rbx/rojo

# หรือผ่าน Cargo
cargo install rojo

# หรือโหลด binary สำเร็จรูปจาก https://github.com/rojo-rbx/rojo/releases
```

ตรวจว่าใช้ได้: `rojo --version` (โปรเจกต์นี้ตรวจสอบด้วย Rojo 7.7.0)

---

## โครงสร้างโฟลเดอร์

```
egg-army-game/
├── default.project.json    ← mapping ของ Rojo (โครงหลัก แก้แล้วกระทบทั้งโปรเจกต์)
├── CLAUDE.md               ← บรีฟโปรเจกต์ แผนเฟส กฎการทำงาน
├── README.md               ← ไฟล์นี้
├── .gitignore              ← กัน build output หลุดขึ้น repo
├── src/
│   ├── server/             → ServerScriptService
│   ├── client/             → StarterPlayer.StarterPlayerScripts
│   └── shared/             → ReplicatedStorage.Shared
├── tests/                  ← ชุดเทสต์ Config (รันด้วย luau CLI ไม่ต้องใช้ Studio)
└── tools/                  ← สคริปต์สร้างตารางสมดุลเป็น HTML
```

### แต่ละส่วนทำอะไร

| โฟลเดอร์ | ปลายทางใน Roblox | หน้าที่ |
|---|---|---|
| `src/server/` | `ServerScriptService` | logic ทั้งหมดที่เชื่อถือได้ — สร้าง/ฟักไข่, สุ่มผล, คอก + กระเป๋า, คำนวณ combat, ให้ currency, DataStore |
| `src/client/` | `StarterPlayer.StarterPlayerScripts` | UI ทั้งหมด — หน้าคอก, กระเป๋า, สวนฟัก, จัดทีม, shop, สนามรบ |
| `src/shared/` | `ReplicatedStorage.Shared` | ของที่สองฝั่งใช้ร่วมกัน — ตัวละคร/คลาส, tier น้ำหนัก, ตารางคลาสของไข่, สูตร damage/เงิน, ชื่อ Remote, type |

**server-authoritative:** การสร้างไข่ ฟักไข่ สุ่มผล คำนวณ combat และการให้ currency ต้องทำฝั่ง server ทั้งหมด
client มีหน้าที่แสดงผลกับส่งคำสั่งเท่านั้น และทุก input จาก client ต้อง validate ก่อนใช้เสมอ (กัน exploit)

### กฎการตั้งชื่อไฟล์ (Rojo)

| ชื่อไฟล์ | กลายเป็น |
|---|---|
| `Foo.lua` | `ModuleScript` ชื่อ `Foo` |
| `Foo.server.lua` | `Script` ชื่อ `Foo` |
| `Foo.client.lua` | `LocalScript` ชื่อ `Foo` |
| `init.lua` ในโฟลเดอร์ | ทำให้ **ตัวโฟลเดอร์เอง** กลายเป็น `ModuleScript` |

⚠️ **อย่าวาง `init.server.lua` / `init.client.lua` ไว้ที่รากของ `src/server` หรือ `src/client`**
เพราะจะทำให้ `ServerScriptService` / `StarterPlayerScripts` กลายเป็น Script แทนที่จะเป็น service แล้วเกมพัง
entry script จึงตั้งชื่อว่า `Main.server.lua` และ `Main.client.lua`
(ส่วน `src/shared/init.lua` ตั้งใจให้เป็นแบบนั้น เพื่อให้ `Shared` เป็น ModuleScript ที่ require ได้ตรง ๆ)

---

## รอบการทำงานปกติ

```bash
# --- เครื่องที่บ้าน ---
git pull                    # ดึงโค้ดที่เขียนจาก web มา
rojo serve                  # เปิดค้างไว้ แล้ว Connect จาก Studio
# ทดสอบในเกม เจอบั๊กก็แจ้งกลับไปให้แก้ที่ฝั่ง web

# --- ถ้าจะแก้เองที่เครื่องบ้าน ---
git add -A && git commit -m "fix: ..." && git push
```

## รันเทสต์

```bash
luau tests/run.luau
```

คำสั่งเดียวจบ **ไม่ต้องเปิด Studio ไม่ต้อง build ก่อน** — ผ่านหมดจะจบด้วย
`=== ผ่าน 365 / ตก 0 ===` และ exit code 0 · มีเทสต์ตกจะพิมพ์รายการที่ตกแล้ว exit 1

ต้องมี [luau CLI](https://github.com/luau-lang/luau/releases) ก่อน (ไฟล์เดียว ไม่ต้องติดตั้งอะไรเพิ่ม)

**รันทุกครั้งที่แก้ `src/shared/Config.lua`** — ตัวเลขสมดุลในไฟล์นั้นผูกกันเป็นลูกโซ่
แก้ตัวเดียวแล้วอีกหลายตัวต้องขยับตาม ซึ่งมองด้วยตาไม่เห็นและเคยพลาดมาแล้วหลายรอบ

⚠️ เทสต์ชุดนี้ตรวจ **`Config.lua` เท่านั้น** ไม่ได้แตะ `src/server` / `src/client`
รายการที่ยังต้องเปิด Studio ทดสอบเอง อยู่ใน [`tests/README.md`](./tests/README.md)

## สร้างตารางสมดุลใหม่

```bash
python3 tools/gen-balance-tables.py
```

เขียนทับ `docs/balance-tables.html` — เปิดด้วยเบราว์เซอร์ดูเส้นเวลาทุกด่าน ราคาของ turret และที่มาของตัวเลขสมดุล
**ตัวเลขทุกตัวในหน้านั้นมาจาก Config จริง ทั้งในตารางและในคำอธิบาย** ไม่มีพิมพ์มือ
รันใหม่ทุกครั้งหลังปรับสมดุล · รายละเอียดใน [`tools/README.md`](./tools/README.md)

## ดูผังแมพ

```bash
luau tools/dump-map.luau
```

พิมพ์พิกัดทุกโซน ตารางรายด่าน และเวลาเดิน — ใช้ประเมินว่าแมพยาวไปไหมโดยไม่ต้องเปิด Studio
ปรับ `Config.Map` แล้วรันใหม่เพื่อเทียบได้ทันที · ผังเต็มอยู่ใน [`docs/map-layout.md`](./docs/map-layout.md)

## ตรวจว่า config ยังใช้ได้

```bash
rojo build -o game.rbxl && rm game.rbxl
```

ถ้าคำสั่งนี้ผ่านโดยไม่ error แปลว่า `default.project.json` กับโครงไฟล์ยังตรงกันอยู่

## ทดสอบ DataStore (Phase 2A)

⚠️ **DataStore ใช้ใน Studio ไม่ได้จนกว่าจะ publish เกมก่อน** เพราะ Roblox ผูกข้อมูลกับ place id
ที่ยังไม่มีจนกว่าจะอัปโหลด ทำครั้งเดียวจบ:

1. **Publish เกม** — `File → Publish to Roblox As...` ตั้งเป็น **private** ได้ ไม่ต้องเปิดสาธารณะ
2. **เปิดสิทธิ์ API** — `Home → Game Settings → Security → Enable Studio Access to API Services`
   ไม่เปิด = ทุกคำสั่ง DataStore โยน error `403 Forbidden` ตั้งแต่คำสั่งแรก
3. กด Play ได้ตามปกติ

### ⚠️ Studio ใช้ store คนละตัวกับของจริง

`DataService.storeName()` เลือกให้เองด้วย `RunService:IsStudio()`:

| ที่ไหน | store ที่ใช้ |
|---|---|
| Studio | `PlayerData_dev_v1` |
| เซิร์ฟเวอร์จริง | `PlayerData_v1` |

**ไม่มีธงให้สลับมือ** โดยตั้งใจ — ธงที่ต้องสลับมือมีวันลืมสลับ
แล้ววันนั้นคือวันที่การทดสอบเขียนทับข้อมูลของผู้เล่นจริง

### ทดสอบ session lock (ต้องใช้สองหน้าต่าง)

`Test → Clients and Servers → 2 players → Start`
เข้าเกมด้วยบัญชีเดียวกันสองเซิร์ฟเวอร์ไม่ได้ในเครื่องเดียว จึงทดสอบทางอ้อมแทน:

1. เข้าเกม ออกจากเกม แล้วเข้าใหม่ทันที → **ต้องเข้าได้** (ตอนออกปลด lock ให้แล้ว)
2. ปิด Studio ทันทีระหว่างเล่น (จำลองเซิร์ฟเวอร์ดับโดยไม่ได้ปลด lock)
   แล้วเข้าใหม่ → ติด lock ไม่เกิน `SESSION_LOCK_SECONDS` (5 นาที) แล้วเข้าได้เอง

### เช็คว่าเซฟจริง

```
เข้าเกม → ฟักไข่จนได้แม่ → ออกจากเกม → เข้าใหม่
```

แม่ · ไข่ในกระเป๋า · ไข่ที่ค้างอยู่ในสวนฟัก ต้องกลับมาครบ
และ **ต้องไม่ได้ไข่เริ่มต้นแถมมาอีกฟอง** (แจกเฉพาะผู้เล่นใหม่จริง ๆ เท่านั้น)
