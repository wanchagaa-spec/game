# Phase 1.5 — รายการงานรื้อโค้ด Phase 1 ให้ตรงดีไซน์ใหม่

> **เอกสารนี้เป็นรายการงานเท่านั้น ยังไม่ได้ลงมือรื้อ**
> โค้ดใน `src/server` และ `src/client` ยังเป็นของเดิมทั้งหมด
> ทำจริงตอนสั่ง Phase 1.5

## ทำไมต้องรื้อ

Phase 1 เขียนตามกลไกเก่า ซึ่งต่างจากดีไซน์ปัจจุบันในสามเรื่องหลัก:

| | กลไกเก่า (โค้ดปัจจุบัน) | ดีไซน์ใหม่ |
|---|---|---|
| **ฟักไข่แล้วได้อะไร** | ทหาร 1 ตัวจาก `hatchTable` (recruit/archer/…) ไม่มีน้ำหนัก | **ตัวแม่** = ตัวละคร (12 ตัว 5 คลาส) + น้ำหนักที่**ล็อกมาตั้งแต่ตอนเป็นไข่แล้ว** (ตอนฟักสุ่มแค่ตัวละคร) |
| **ไข่มาจากไหน** | ผู้เล่นกดปุ่มวางไข่ได้เลย มี `price` เตรียมไว้ให้ซื้อด้วยเงินในเกม | ไข่ปกติ**แย่งจากรังบอสเท่านั้น** · ไข่ตำนาน**ซื้อด้วย Robux เท่านั้น** ซื้อด้วยเงินในเกมไม่ได้เลย |
| **ที่เก็บ** | `plot` มี 4 ช่องวางไข่ · คลังทหารเป็น array เดียว | **คอก** (แม่ที่ผลิต) + **กระเป๋า** (แม่ที่ไม่ผลิต 100 ตัว) + **สวนฟัก** 50 ฟอง |

`Config.lua` อัปเดตให้ตรงดีไซน์ใหม่ครบแล้ว **โค้ดที่เหลือยังตามไม่ทัน**

---

## 1. `src/server/EggService.lua` — รื้อหนักสุด

### ต้องแก้

| ตอนนี้ | เปลี่ยนเป็น | เหตุผล |
|---|---|---|
| `rollUnit(egg)` → คืน `unitId` จาก `egg.hatchTable` | `rollMother(egg, stage)` → คืน `{ charId, weight }` ใช้ `Config.rollCharacter()` + `Config.rollMotherWeight(rng, stage)` | สองค่านี้แทนที่ `unitId` เดิมทั้งหมด |
| `type UnitRecord = { uid: number, unitId, obtainedAt }` | `type Mother = { uid: string, charId, weight, statuses, lastProducedAt, obtainedAt, locked }` | uid เป็น **global string** แล้ว (`Config.makeUid`) และต้องมีฟิลด์ครบตาม `docs/data-schema.md` §3 |
| `state.units` เป็น array เดียว | `state.mothersInPen` + `state.mothersInBag` แยกสองอาเรย์ | โค้ด settle การผลิตต้องวนเฉพาะแม่ในคอก แยกโครงไว้ทำให้ลืมกรองไม่ได้ |
| `state.nextUid` เริ่มที่ 1 ต่อผู้เล่น | ยังเป็นตัวนับต่อผู้เล่น แต่ uid เต็ม = `Config.makeUid(player.UserId, nextUid)` | รองรับการเทรดแม่ |
| **`os.clock()` ทุกจุด** (บรรทัด 124, 219, 330 และใน `EggSlot.hatchAt`) | **`os.time()`** | `os.clock()` รีเซ็ตทุกครั้งที่เซิร์ฟเวอร์ใหม่ เซฟลง DataStore ไม่ได้ |
| `EggSlot` 4 ช่องตาม `Config.Farm.EGG_SLOTS_PER_PLAYER` | สวนฟัก `Config.Hatchery.MAX_EGGS` = 50 ช่อง | ดีไซน์ใหม่ |
| `EggService.placeEgg()` — client ขอวางไข่จาก `eggId` ตรง ๆ | ต้องอ้าง**ไข่ฟองที่มีอยู่จริงใน `heldEggs`** ด้วย index ไม่ใช่ `eggId` (ไข่ชนิดเดียวกันน้ำหนักต่างกันได้) แล้วย้ายทั้งฟอง (`eggId` + `weight`) เข้าสวน | ตอนนี้ขอไข่ชนิดไหนก็ได้ฟรี = ช่องโหว่ |
| `EggService.getUnits()` | `getMothersInPen()` / `getMothersInBag()` | ชื่อเดิมสื่อผิดแล้ว |
| `hatch()` ยิง `EggHatched` ด้วย `{ unitId, unitName, rarity }` | `{ charId, charName, class, weight }` | payload เปลี่ยน — ดู §4 |

### เก็บไว้ได้

- โครง `placeEgg()` ที่ validate ทีละชั้น (ชนิดข้อมูล → ช่วงค่า → สถานะ) — ใช้ได้ต่อ แค่เปลี่ยนเงื่อนไข
- ลูป tick เดียวที่ทั้งเช็คการฟักและ sync — โครงถูกแล้ว
- `showEgg()` / `hideEgg()` — ยังต้องมีโมเดลไข่บนแท่น

---

## 2. `src/server/PlotService.lua` → `PenService.lua`

### ต้องแก้

| ตอนนี้ | เปลี่ยนเป็น |
|---|---|
| ชื่อไฟล์ `PlotService` | `PenService` — "plot" เป็นคำของกลไกเก่า ดีไซน์ใหม่เรียก **คอก** |
| `Config.Farm.EGG_SLOTS_PER_PLAYER` = 4 แท่นวางไข่ต่อ plot | คอกมีที่วาง**แม่** ตาม `Config.getPenCapacity(penLevel)` = 5–19 ตัว + สวนฟักแยกอีก 50 ช่อง |
| ความจุคงที่ | ความจุ**เปลี่ยนตามเลเวลคอก** → ต้องสร้าง/ซ่อนที่วางเพิ่มตอนอัปเกรด |
| `assign()` / `release()` จอง plot ทั้งก้อน | ยังต้องมี แต่ต้องเพิ่ม `addMotherToPen()` / `moveToBag()` / `sellMother()` |
| แสดงก้อนไข่บนแท่น | ต้องแสดง**โมเดลตัวแม่**ในคอก พร้อมป้ายชื่อตัวละคร + น้ำหนัก (`Config.formatWeight`) |

### เก็บไว้ได้

- `buildWorld()` + `SpawnLocation` — ยังจำเป็น (place ที่ build จาก Rojo ไม่มีพื้น)
- กลไกจอง/คืนพื้นที่ต่อผู้เล่น — โครงถูก
- `clearVisuals()` ตอนผู้เล่นออก

---

## 3. `src/client/Main.client.lua` — เขียนใหม่ทั้งแผง

ตอนนี้เป็นแผงเทสต์: ปุ่ม "วางไข่ธรรมดา" + สถานะ 4 ช่อง + ข้อความผลฟัก

ปุ่มวางไข่ต้องหายไปก่อนเป็นอันดับแรก เพราะ**ไข่ซื้อ/สร้างเองไม่ได้แล้ว** ต้องแย่งจากบอส

Phase 1.5 ทำแค่แผงเทสต์ที่โชว์: แม่ในคอก (ตัวละคร + น้ำหนัก) · แม่ในกระเป๋า · สวนฟัก
UI จริง (สองแถบแม่/ลูก + กล่องยืนยัน) อยู่ Phase 3

---

## 4. RemoteEvent ที่ต้องเปลี่ยน signature

⚠️ ทั้งสามตัวเป็น**โครงหลัก** ตาม CLAUDE.md — เปลี่ยนแล้วต้องแก้ทั้งสองฝั่งพร้อมกัน

| Remote | ตอนนี้ | ต้องเป็น |
|---|---|---|
| `PlaceEggRequest` | `FireServer(eggId, slotIndex?)` — client ขอไข่ชนิดไหนก็ได้ | `FireServer(eggId, slotIndex?)` เหมือนเดิม **แต่ server ต้องเช็ค `heldEggs` ก่อน** · ชื่ออาจเปลี่ยนเป็น `PlaceEggInHatcheryRequest` ให้ตรงความหมาย |
| `EggHatched` | `{ slotIndex, eggId, unitId, unitName, rarity }` | `{ slotIndex, eggId, charId, charName, class, weight, placedIn }` (`placedIn` = "pen" หรือ "bag") · `weight` มาจากตัวไข่ ไม่ได้สุ่มตอนนี้ |
| `FarmStateSync` | `{ slots = {...}, unitCount }` | `{ hatching = {...}, penCount, penCapacity, bagCount, coins }` |

**Remote ที่ต้องเพิ่มใน Phase 1.5** (ยังไม่สร้างในรอบนี้): ย้ายแม่คอก↔กระเป๋า · ขายแม่ · อัปเกรดคอก

---

## 5. ค่าใน Config ที่ตกยุคแล้ว

| ค่า | สถานะ | ทำอะไรกับมัน |
|---|---|---|
| `Config.UnitTypes` (recruit/spearman/archer/knight/mage/dragon_rider) | **ตกยุค** — แทนที่ด้วย `Config.Characters` | ตั้ง `enabled = false` ทุกตัว **อย่าลบ** (กฎ CLAUDE.md: id ที่เคยเซฟไปแล้วห้ามลบ) |
| `EggType.hatchTable` | **ตกยุค** — แทนที่ด้วย `Config.EggCharacterPools` | ปล่อยไว้จนกว่า `EggService.rollUnit()` จะถูกลบ แล้วค่อยตั้ง comment ว่าเลิกใช้ |
| `Config.Rarities` (Common/Rare/Epic/Legendary) | **ตกยุค** — คลาสใหม่คือ SS/S/A/B/C | เลิกใช้พร้อม `UnitTypes` |
| `Config.Farm.EGG_SLOTS_PER_PLAYER` = 4 | **ตกยุค** — สวนฟักคือ `Config.Hatchery.MAX_EGGS` = 50 | เลิกใช้เมื่อ EggService ย้ายไปใช้ Hatchery |
| `Config.Farm.PLOT_SIZE` / `PLOT_SPACING` / `PLOT_ORIGIN` / `MAX_PLOTS` | **ยังใช้ได้** แต่ควรเปลี่ยนชื่อเป็น Pen | เปลี่ยนชื่อพร้อม PenService |
| `Config.DEFAULT_EGG_ID` | **ยังใช้ได้** แต่ความหมายเปลี่ยน — เดิมคือ "ไข่ที่ปุ่มทดสอบใช้" | ใช้เป็นไข่เริ่มต้นของผู้เล่นใหม่แทน · ตอนนี้ชี้ที่ `egg_stage1` แล้ว |
| `egg.hatchTable` (ตารางสุ่ม "ทหาร") | ตายทั้งหมด — ระบบจริงใช้ `Config.rollCharacter()` + น้ำหนักที่ติดมากับไข่ | ไข่ `egg_stage1..9` ยังมี `hatchTable` ค้างไว้ 1 บรรทัดเพื่อให้โค้ด Phase 1 ยังรันได้ ลบทิ้งพร้อม `UnitTypes` ตอนรื้อ |
| `egg_common` / `egg_rare` | `enabled = false` แล้ว ห้ามแจกให้ผู้เล่นอีก | ยัง `getEgg()` ได้ตามกฎ eggId (ห้ามลบ ห้าม reuse) |
| `EggType.price` | **ลบไปแล้วในรอบนี้** | ✅ เสร็จแล้ว |

> **ทั้งหมดนี้ใช้วิธี `enabled = false` ไม่ใช่ลบทิ้ง** เพราะ id พวกนี้อาจอยู่ในข้อมูลผู้เล่นที่เซฟไปแล้ว (ตอนนี้ยังไม่มี DataStore จึงยังปลอดภัย แต่ทำให้ชินไว้ก่อน)

---

## 6. ลำดับการรื้อที่ปลอดภัย

รื้อจาก "ของที่ไม่มีใครพึ่ง" ไปหา "ของที่ทุกอย่างพึ่ง" เพื่อให้ build ผ่านทุกขั้น

```
ขั้น 1  ตัดปุ่มวางไข่ออกจาก Main.client.lua
        → ไม่มีใครยิง PlaceEggRequest อีก เปลี่ยน signature ได้อย่างปลอดภัย

ขั้น 2  เปลี่ยน os.clock() → os.time() ใน EggService
        → แก้จุดเดียว ไม่กระทบ API ทดสอบได้ทันทีว่าไข่ยังฟักตรงเวลา

ขั้น 3  เปลี่ยนผลการฟัก: rollUnit → rollMother
        → EggHatched payload เปลี่ยน แก้ client ให้รับของใหม่พร้อมกัน
        → ตรงนี้ทำให้ "ฟักแล้วได้ตัวแม่" ใช้งานได้จริงเป็นครั้งแรก

ขั้น 4  แยก state.units → mothersInPen + mothersInBag + uid global
        → เปลี่ยนโครงข้อมูลใน memory ยังไม่แตะ DataStore

ขั้น 5  PlotService → PenService: ความจุตามเลเวล + แสดงโมเดลแม่
        → งานใหญ่สุดของฝั่งโลก ทำทีหลังสุดเพราะต้องรู้ว่าแม่หน้าตายังไงก่อน

ขั้น 6  ย้าย 4 ช่องวางไข่ → สวนฟัก 50 ช่อง
        → FarmStateSync payload เปลี่ยน แก้ client พร้อมกัน

ขั้น 7  ตั้ง enabled = false ให้ UnitTypes / Rarities / hatchTable
        → ทำท้ายสุด เพราะก่อนหน้านี้โค้ดยังอ้างอยู่
```

**หลังจบทุกขั้นยังเป็น in-memory ทั้งหมด ยังไม่แตะ DataStore** (นั่นคือ Phase 2)

---

## 7. สิ่งที่ Phase 1.5 **ไม่** ทำ

- ❌ DataStore / การเซฟ (Phase 2)
- ❌ ระบบผลิตลูก (Phase 2)
- ❌ ผลิตเงิน · ขายแม่ · อัปเกรดคอก (Phase 2)
- ❌ กำแพง · กองทัพ · การรบ (Phase 3)
- ❌ บอส · แย่งไข่ (Phase 5) — Phase 1.5 ยังต้องมีวิธีได้ไข่มาแบบชั่วคราวเพื่อทดสอบ
  **เสนอ:** คำสั่งฝั่ง server ใน command bar เท่านั้น ไม่ทำเป็นปุ่มใน UI
  จะได้ไม่ต้องเขียนแล้วลบทิ้งตอน Phase 5
- ❌ Robux / Developer Product (Phase 6)

---

## 8. เช็คลิสต์ก่อนปิด Phase 1.5

- [ ] `rojo build` ผ่าน และ tree ออกมาถูก (`ServerScriptService` ยังเป็น service ไม่ใช่ Script)
- [ ] `luau-lsp analyze` สะอาด
- [ ] เปิดใน Studio แล้วฟักไข่ได้ตัวแม่จริง เห็นชื่อตัวละคร + น้ำหนักในคอก
- [ ] น้ำหนักที่ออกกระจายตามตาราง tier (ลองฟักหลาย ๆ ฟองแล้วดู Output)
- [ ] ย้ายแม่คอก↔กระเป๋าได้ และกระเป๋าเต็ม 100 แล้วเพิ่มไม่ได้
- [ ] ผู้เล่นออกแล้วเข้าใหม่ = ข้อมูลหาย (ถูกต้องสำหรับเฟสนี้ เพราะยังไม่มี DataStore)
- [ ] ไม่มีทางได้ไข่จาก UI ฝั่ง client อีกแล้ว
