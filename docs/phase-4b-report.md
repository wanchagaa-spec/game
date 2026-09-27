# Phase 4B — ปุ่มล็อกแม่ + แจ้งแม่ตายใน popup ผ่านด่าน

> ✅ **เสร็จและทดสอบใน Studio แล้ว ผ่านครบ** (§4) · ไม่แตะ schema (ยัง v3)
> Commit: `1c4088b` (4B หลัก) · `606e0a7` (การ์ดที่เลือกเข้มขึ้น) · `2bc73ba` (สะพาน debug) · `7ab1941` (บันทึกผล)

---

## 1. ทำอะไรบ้าง

| งาน | จุดที่แก้ |
|---|---|
| remote ใหม่ `ToggleMotherLockRequest(uid)` สลับ `locked` ของแม่ในคอก/กระเป๋าของตัวเอง ตอบกลับทาง `ActionResult` | `Config.RemoteNames` · `Remotes` · `EggService.toggleMotherLock` |
| **ล็อกกันขาย** (ของใหม่) — ตรวจ**ก่อน**ถอดแม่ออกจากกระเป๋า | `EggService.sellMother` |
| ล็อกกันส่งไปรบ — **ไม่ได้แก้** ใช้ของเดิมจาก 3C-1 | `CombatService.handleSendMotherToBattle` |
| UI: ปุ่ม 🔒 ล็อก / 🔓 ปลดล็อก (แท็บคอก+กระเป๋า) · ป้าย 🔒 บนการ์ด · ปุ่มขาย/ส่งไปรบเป็นสีเทาเมื่อล็อก · "ขายทั้งหมด" ข้ามตัวที่ล็อก | `Main.client.lua` |
| `StageClearedNotify(stage, eggCount, deathCount)` — เพิ่มจำนวนแม่ที่ตาย · ยิงเมื่อมีไข่**หรือ**แม่ตาย | `CombatService.shouldNotifyStageCleared` · `EggService.grantStageClearBonus` |
| ข้อความ popup 4 กรณีอยู่ที่เดียว · มีแม่ตาย = ขอบแดง | `Config.formatStageClearedMessage` · `Main.client.lua` |
| การ์ดที่เลือกอยู่: พื้นเข้ม 50% + ตัวอักษรขาว + ขอบขาว 3px | `Main.client.lua` (`createCard`) |
| สะพาน debug `ServerStorage.EggServiceDebug` (Studio เท่านั้น) | `Main.server.lua` · `docs/debug-commands.md` |

## 2. จุดที่ต่างจากโจทย์ (ทักท้วงไว้ตอนส่งงาน)

- `killRoster` นับจำนวนแม่ตาย**ก่อน**ล้าง roster อยู่แล้ว → ส่งต่อค่า `mothersLost` เดิม ไม่ได้แก้ `killRoster`
- `StageClearedNotify` ยิงจาก `EggService` ไม่ใช่ `Main.server.lua` (Main แค่ส่งฟังก์ชันเข้าไป)
- **จุดเดียวที่แตะ logic ของ 4A:** เงื่อนไขยิง popup `ไข่ > 0` → `ไข่ > 0 หรือ แม่ตาย > 0`
- ข้อจำกัดที่ยอมรับ: กระเป๋าไข่เต็ม**พร้อมกับ**มีแม่ตาย → popup บอกแค่แม่ตาย ไม่บอกว่ากระเป๋าเต็ม

## 3. ปัญหาที่เจอระหว่างทดสอบ + วิธีแก้

| ปัญหา | สาเหตุ | แก้ |
|---|---|---|
| ปุ่มล็อกไม่ขึ้นใน Studio | Studio รัน `main` ที่ยังไม่ได้ merge 4B | merge (ไม่ใช่บั๊ก) |
| เลือกการ์ดแล้วดูไม่ออกว่าเลือกตัวไหน | ขอบขาว 2px แทบมองไม่เห็นบนการ์ดสีอ่อน | พื้นเข้มขึ้น + ตัวอักษรขาว (`606e0a7`) |
| วางคำสั่ง debug ในช่องคำสั่ง F9 → error 2 ครั้ง ไม่มีผล | ไม่ได้ดูข้อความ error | เปลี่ยนไปใช้ Command Bar ของ Studio |
| Command Bar ตอบ "ยังไม่มีข้อมูลผู้เล่น" ทั้งที่เกมยัง autosave ปกติ | `require` จาก Command Bar ได้ EggService/DataService **อีกชุด** ที่แคชว่าง | สะพาน BindableFunction เรียกตัวที่เกมใช้จริง (`2bc73ba`) |
| `EggServiceDebug is not a valid member` | Studio ยังรัน `main` ก่อน merge สะพาน (ยืนยันจาก log `Main:218` แทน `Main:242`) | merge + กด Play ใหม่ |

วิธีเรียกคำสั่ง debug ตอนนี้:
```lua
game.ServerStorage.EggServiceDebug:Invoke("debugSetStageProgress", game.Players:GetPlayers()[1], 2, 0, 1)
```

## 4. ผลทดสอบ

**อัตโนมัติ** (`tools/check-all.py` ผ่านครบ 7/7)
- `tests/run.luau` 1135 → **1160** (+25): ข้อความ 4 กรณี · เงื่อนไขยิง popup · tick จริงนับแม่ตายก่อนล้าง roster · ล็อกยังกันส่งไปรบ
- `check-pen-mother-economy.py` 59 → **106** (+47): toggle + sync · ย้ายคอก↔กระเป๋าได้ · uid ปลอม/ของคนอื่น/แม่ใน roster ถูกปฏิเสธ · ขายตัวที่ล็อกไม่ได้ → ปลดล็อกแล้วขายได้ · ส่งไปรบตัวที่ล็อกไม่ได้ · payload 3 ค่า
- ลองลบจุดตรวจล็อกตอนขายออก → เทสต์ตก 4 เคสทันที (คืนโค้ดแล้ว)

**Studio** (ผู้เล่นทดสอบเอง)

| ทดสอบ | ผล |
|---|---|
| ล็อกแม่ → ขาย/ส่งไปรบไม่ได้ · ปลดล็อกแล้วทำได้ | ✅ |
| popup "ได้รับไข่ฟรี 1 ฟอง • เสียแม่ในสนามรบ 3 ตัว" | ✅ |
| popup "เสียแม่ในสนามรบ 2 ตัว" (ด่านเคยได้รางวัลแล้ว) | ✅ |
| ด่านพังโดยไม่มีไข่และไม่มีแม่ตาย → ไม่มี popup | ✅ |

## 5. ยังค้าง / ข้อจำกัด

| เรื่อง | สถานะ |
|---|---|
| สะพาน debug เรียกได้แค่ `EggService.debug*` | คำสั่งเก่าแบบ `require(...).grantEgg` ใน `tests/README.md` · `docs/phase-1.5-rework.md` · หัว `Main.client.lua` ยังเป็นแบบเก่า → จะเจอ "ยังไม่มีข้อมูลผู้เล่น" เหมือนกัน |
| popup กรณีกระเป๋าไข่เต็ม + แม่ตาย | ไม่บอกว่ากระเป๋าเต็ม (ต้องเพิ่ม arg ที่ 4 ถ้าจะแยก) |
| แม่ใน roster ล็อกไม่ได้ | ตั้งใจ (ส่งไปแล้วดึงกลับไม่ได้อยู่แล้ว) |
| ปุ่ม "ขายที่เลือก / ขายทั้งหมด" | ยังเป็น TEMP — ของจริงต้องย้ายไประบบร้านค้า |
| การ์ดที่เลือกเข้มขึ้น | ใช้งานอยู่ระหว่างทดสอบ แต่ยังไม่ได้รายงานผลแยก |
| error ในช่องคำสั่ง F9 | ยังไม่รู้สาเหตุ (ไม่ได้ดูข้อความ) — ใช้ Command Bar แทน |
| งานค้างเดิม | Max Players 60 → 6 ใน Game Settings · `startingEggs` TEMP = 100 ต้องคืนเป็น 1 ก่อน publish · เช็คลิสต์ Studio ของ 1.5 / 3B |
