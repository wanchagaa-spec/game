# คำสั่ง debug — ทดสอบ Phase 2B ใน Studio

⚠️ **ทั้งหมดนี้เป็นเครื่องมือทดสอบเท่านั้น ไม่ใช่ฟีเจอร์ในเกม** ไม่มี UI ไม่มี RemoteEvent
เรียกได้จาก **command bar ฝั่ง server** ใน Studio เท่านั้น (View → Command Bar หรือ `Ctrl+Alt+;` )
ต้องรันจาก Server Script (Studio → Command Bar ทำงานเป็น server context ได้ถ้าเลือก
"Server" ในเมนู dropdown ของ command bar)

ทุกคำสั่งเริ่มด้วยการ require ตัวโมดูลก่อนเสมอ:

```lua
local EggService = require(game.ServerScriptService.EggService)
local player = game.Players.<ชื่อผู้เล่น>  -- หรือ game.Players:GetPlayers()[1]
```

ทุกคำสั่งที่ **แก้ข้อมูล** เซฟลง DataStore ทันทีผ่าน `DataService.saveAsync` (ไม่รอ autosave 60 วิ)
ยกเว้น `debugSnapshot` ที่เป็น read-only ล้วน ๆ ไม่มีอะไรให้เซฟ

---

## ทำไมต้องมีชุดนี้

การสุ่มธรรมชาติทดสอบ tier น้ำหนักสูง ๆ ไม่ได้จริงในเวลาที่มี — tier 7 (100,000,000 kg)
ออกแค่ **1 ในล้านฟอง** ต่อให้ฟาร์มทั้งวันก็ไม่การันตีว่าจะเจอ คำสั่งชุดนี้เปิดทางกำหนดค่าตรง ๆ
เพื่อทดสอบระบบขนาดโมเดล/เวลาฟัก/ผลิต/ขาย ให้ครบทุก tier โดยไม่ต้องพึ่งดวง

---

## รายการคำสั่ง

### `EggService.debugGrantMother(player, weight, charId, destination)`

สร้างแม่ **ตรง ๆ ข้ามขั้นตอนฟักทั้งหมด** — ใช้ทดสอบขนาดโมเดล/ราคาขาย/ความจุคอกทุก tier

```lua
EggService.debugGrantMother(player, 100000000, "yulai", "pen")  -- แม่ tier 7 คลาส SS เข้าคอกทันที
EggService.debugGrantMother(player, 1500, "wukong", "bag")       -- แม่เล็ก ๆ เข้ากระเป๋า
```

- `destination` ต้องเป็น `"pen"` หรือ `"bag"` เท่านั้น
- ⚠️ **ถ้า `destination = "pen"` แต่คอกเต็ม → ปฏิเสธตรง ๆ ไม่ fallback ไปกระเป๋าเงียบ ๆ**
  (เจตนา: กันไม่ให้เทสต์ "คอกเต็มพอดี" ที่ตั้งใจตั้งไว้เพี้ยนไปโดยไม่รู้ตัว)
- `weight` ต้องเป็นจำนวนเต็มบวก (ปัดเศษให้อัตโนมัติด้วย `math.floor` — น้ำหนักแม่ต้องเป็น
  จำนวนเต็มเสมอเพราะเป็นส่วนหนึ่งของ stack key)
- `charId` ต้องมีอยู่จริงใน `Config.Characters` (ดูรายชื่อในตาราง §ด้านล่าง)
- คืนค่า `(boolean, string?)` — `true` = สำเร็จ, `false, เหตุผล` = ถูกปฏิเสธ
- print สรุปเสมอไม่ว่าสำเร็จหรือไม่

### `EggService.debugGrantEggWithWeight(player, eggId, weightOverride)`

วางไข่ลงกระเป๋าโดย**บังคับน้ำหนัก** ข้าม RNG ของ `Config.rollMotherWeightForEgg`
**ยังคงสุ่มตัวละครตามตารางคลาสของ `eggId` นั้นตามปกติ**ตอนวางไข่ลงสวนฟัก (ไม่ได้บังคับคลาส)

```lua
EggService.debugGrantEggWithWeight(player, "egg_stage5", 100000000)  -- ไข่ tier 7 พอดี
EggService.debugGrantEggWithWeight(player, "egg_stage1", 500000)     -- ไข่ tier 4
```

ใช้ทดสอบว่า **ขนาดโมเดลไข่** (`Config.getEggVisualSize`) และ **เวลาฟัก**
(`Config.getHatchSeconds` — ขึ้นกับน้ำหนัก + คลาสที่สุ่มได้ตอนวาง) คำนวณถูกทุก tier
วางแล้วเรียก `EggService.placeEgg(player, eggId, nil)` ต่อเพื่อดูผลจริง

- `eggId` ต้องมีอยู่จริงและ `enabled = true` (ห้ามใช้ `egg_common`/`egg_rare` ที่ปิดแล้ว)
- คืนค่า `(boolean, string?)` เหมือนกัน

### `EggService.debugSetWallProgress(player, n)`

ตั้งค่า `wallProgress` **ฝั่ง server** ตรง ๆ — ใช้ทดสอบสูตรเงิน (`Config.getCoinsPerMinute`)
และเพดาน damage upgrade ที่ผูกกับด่านที่พังกำแพงได้แล้ว

```lua
EggService.debugSetWallProgress(player, 7)  -- จำลองว่าพังกำแพงถึงด่าน 7 แล้ว
```

⚠️ **คนละตัวกับกำแพงที่ `WallRenderer` วาดฝั่ง client** — ตั้งค่านี้แล้วกำแพงในเกมจะยังดูไม่พัง
(client ยังไม่ได้รับค่านี้ผ่าน sync ในเฟสนี้) ต้องดูผลจาก**สูตรเงิน**ที่เปลี่ยนไป ไม่ใช่จากภาพกำแพง

- `n` ถูก clamp อยู่ในช่วง `1..Config.Balance.Stage.COUNT` (1–9) เสมอ — ใส่ 0 หรือติดลบ
  จะได้ 1, ใส่เกิน 9 จะได้ 9
- print ค่าก่อน/หลังเสมอ

### `EggService.debugSetCurrency(player, coins)`

ตั้งค่า `currency.coins` ตรง ๆ — ใช้ทดสอบอัปเกรดคอก/ขายแม่โดยไม่ต้องรอสะสมเงินจริง

```lua
EggService.debugSetCurrency(player, 1000000000)  -- พอสำหรับอัปคอกทุกขั้น
```

- แตะแค่ `coins` ไม่แตะ `gems` (คนละบ่อ)
- ค่าติดลบถูก clamp เป็น 0
- print ค่าก่อน/หลังเสมอ

### `EggService.debugSnapshot(player)`

พิมพ์ข้อมูลสำคัญทั้งหมดของผู้เล่นแบบอ่านง่าย **read-only ไม่แก้อะไรเลย**

```lua
EggService.debugSnapshot(player)
```

พิมพ์: เงิน (coins/gems) · คอก (เลเวล/ความจุ) + wallProgress · รายการแม่ในคอก
(uid + charId + น้ำหนัก) · รายการแม่ในกระเป๋า (เหมือนกัน) · จำนวนไข่ในกระเป๋า ·
สวนฟักทุกช่องที่ไม่ว่าง (บอกด้วยว่าช่องไหน "ค้างรอที่ว่าง" ตามข้อ D)

**ใช้หา `uid` จริงของแม่** เพื่อเอาไปทดสอบต่อ เช่น:

```lua
-- ดู uid ก่อน
EggService.debugSnapshot(player)
-- เอา uid ที่เห็นไปทดสอบขาย/ย้าย (เรียกผ่านฟังก์ชันตรง ๆ ได้เลย ไม่ต้องผ่าน RemoteEvent)
EggService.sellMother(player, "1234567-3")
EggService.moveMother(player, "1234567-3", "pen")
```

---

## ตัวอย่าง flow ทดสอบครบทุก tier

```lua
local EggService = require(game.ServerScriptService.EggService)
local player = game.Players:GetPlayers()[1]

-- ให้เงินพออัปคอกทุกขั้นก่อน
EggService.debugSetCurrency(player, 1e18)

-- ไล่ทดสอบขนาดโมเดล + เวลาฟักทุก tier (คลาส C เป็น baseline)
local tiers = {100, 5000, 50000, 500000, 5000000, 50000000, 100000000}
for _, w in tiers do
	EggService.debugGrantEggWithWeight(player, "egg_stage1", w)
end
-- แล้วเข้าเกมไปกดวางไข่ทีละฟอง ดูขนาด + เวลานับถอยหลังในสวนฟัก

-- ทดสอบขนาด/ราคาขายของแม่ทุก tier โดยข้ามการฟักไปเลย
for _, w in tiers do
	EggService.debugGrantMother(player, w, "monkey", "bag")
end
EggService.debugSnapshot(player)  -- ดู uid แล้วลองขายทีละตัว

-- ทดสอบสูตรเงินที่ผูกกับ wallProgress
EggService.debugSetWallProgress(player, 9)
EggService.debugGrantMother(player, 1000000, "wukong", "pen")
-- รอ production tick (Config.Balance.Production.TICK_INTERVAL วิ) แล้วดู currency.coins ขึ้น

-- ทดสอบข้อ D (คอก+กระเป๋าเต็มพร้อมกัน) — ดู docs/data-schema.md §5.5 สำหรับ flow เต็ม
```

---

## ตาราง tier น้ำหนัก (อ้างอิงตอนเรียกคำสั่ง)

| tier | ช่วงน้ำหนัก (kg) | ตัวอย่างค่าที่ใช้ทดสอบ |
|---:|---|---:|
| 1 | 100–999 | 100 |
| 2 | 1,000–9,999 | 5,000 |
| 3 | 10,000–99,999 | 50,000 |
| 4 | 100,000–999,999 | 500,000 |
| 5 | 1,000,000–9,999,999 | 5,000,000 |
| 6 | 10,000,000–99,999,999 | 50,000,000 |
| 7 | 100,000,000 (คงที่) | 100,000,000 |

## ตัวละครที่ใช้ได้ (charId)

| charId | ชื่อ | คลาส |
|---|---|---|
| `yulai` | องค์ยูไล | SS |
| `guanyin` | พระแม่กวนอิม | S |
| `jade_emperor` | เง็กเซียนฮ่องเต้ | S |
| `tang` | พระถังซัมจั๋ง | A |
| `wukong` | ซุนหงอคง | A |
| `bajie` | ตือโป๊ยก่าย | B |
| `wujing` | ซัวเจ๋ง | B |
| `dragon_horse` | ม้าขาวมังกร | B |
| `monkey` | ลิง | C |
| `pig` | หมู | C |
| `horse` | ม้า | C |
| `fish` | ปลา | C |

---

## ของเดิมที่มีอยู่แล้ว (Phase 1.5–2A)

- `EggService.grantEgg(player, eggId)` — แจกไข่ (สุ่มน้ำหนักจริงตามตาราง ไม่บังคับ)
- `EggService.debugFillHatchery(player)` — วางไข่ในกระเป๋าลงสวนฟักจนเต็ม/หมด
- `EggService.debugClearBag(player)` — ล้างแม่+ไข่ในกระเป๋า (ไม่แตะคอก/สวนฟัก)
- `EggService.debugResetAll(player)` — ล้างทุกอย่าง (คอก/กระเป๋า/สวนฟัก) เหมือนเริ่มใหม่

## ทดสอบอัตโนมัตินอก Studio

ชุดคำสั่งข้างบนมีชุดทดสอบอัตโนมัติคู่กันแล้วที่ `tools/check-debug-commands.py`
(รันด้วย `python3 tools/check-debug-commands.py`) ครอบคลุมทุกกรณีปกติ + กรณีปฏิเสธ
ของทั้ง 5 ฟังก์ชันใหม่ — ดูเป็นตัวอย่างการเรียกใช้เพิ่มเติมได้ถ้าคำอธิบายข้างบนไม่ชัดพอ
