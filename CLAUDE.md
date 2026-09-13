# CLAUDE.md — เกมไข่ทหาร (Roblox)

## ภาษา
ตอบเป็น **ภาษาไทย** เสมอ ทั้งคำอธิบาย สรุป และคำถามกลับ
(comment ในโค้ดใช้ไทยได้ ชื่อตัวแปร/ฟังก์ชันใช้อังกฤษตามมาตรฐาน Luau)
สไตล์: ตรงประเด็น กระชับ ไม่ต้องเกริ่นยาว

## โปรเจกต์นี้คืออะไร
เกม Roblox แนวผสม: **เก็บ/ฟักไข่ → ได้ทหาร → เก็บในฟาร์ม → ปล่อยทหารไปตีฐานศัตรู**
(loop คล้าย Age of War ผสมกับระบบสะสมแบบ pet simulator)

Core loop:
วางไข่ → ฟักได้ทหาร → เก็บเข้าคลัง → จัดทีม → ส่งไปรบ → ชนะได้ currency → ซื้อไข่เพิ่ม/อัปเกรด → วนซ้ำ

## Stack & เครื่องมือ
- **Roblox Studio** — เปิดไฟล์ place ที่ build จาก Rojo
- **Rojo** — sync โค้ดในโฟลเดอร์นี้เข้า Studio (Claude Code แก้ที่ไฟล์ .lua ในโฟลเดอร์นี้เท่านั้น)
- **Luau** — ภาษาสคริปต์
- **DataStore** — บันทึกข้อมูลผู้เล่น

คำสั่งที่ใช้บ่อย:
```
rojo serve          # dev server ให้ Studio plugin เชื่อม
rojo build -o game.rbxl   # build ไฟล์ place
```

## โครงสร้างโฟลเดอร์
```
src/
  server/   → ServerScriptService (logic ฟักไข่, คลังทหาร, combat, DataStore)
    Main.server.lua      → ServerScriptService.Main (entry point, ต่อสายอย่างเดียว)
    PlotService.lua      → จอง/คืน farm plot + สร้างโลก
    EggService.lua       → วางไข่ จับเวลา ฟัก สุ่มทหาร คลังทหาร (memory)
  client/   → StarterPlayerScripts (UI ทั้งหมด)
    Main.client.lua      → StarterPlayerScripts.Main (entry point)
  shared/   → ReplicatedStorage.Shared (config, constants, type ที่ใช้ร่วมกัน)
    init.lua             → ตัว Shared เองเป็น ModuleScript (เป็นแค่ฝา)
    Config.lua           → ⚠️ โครงหลัก: ตารางไข่/ทหาร ค่าตั้งฟาร์ม ชื่อ RemoteEvent
    Remotes.lua          → สร้าง/รอหา RemoteEvent
default.project.json   → mapping ของ Rojo
```

⚠️ **ห้ามวาง `init.server.lua` / `init.client.lua` ที่รากของ `src/server` หรือ `src/client`**
ไฟล์ init จะเปลี่ยน "ตัวโฟลเดอร์" ให้เป็น Script ทำให้ `ServerScriptService` /
`StarterPlayerScripts` ไม่ใช่ service อีกต่อไป → เกมพัง
entry script ใช้ชื่อ `Main.server.lua` / `Main.client.lua` เท่านั้น

## แผนพัฒนาเป็นเฟส
ทำทีละเฟส **อย่าข้ามไปทำเฟสถัดไปเองถ้ายังไม่สั่ง**

- **Phase 0** — โครงโปรเจกต์ + Rojo + README + .gitignore ✅
- **Phase 1** — ระบบไข่ & ฟาร์ม (data model ไข่, จุดวางไข่, ตัวจับเวลาฟัก, สุ่มผลทหาร) ✅
- **Phase 2** — คลังทหาร & DataStore (บันทึกทหาร/ไข่/currency, UI คลัง, จัดทีม)
- **Phase 3** — สนามรบ auto-battle (เริ่มจาก PvE ฐานบอทก่อน, ระบบ HP/damage/target)
- **Phase 4** — เศรษฐกิจ & progression (รางวัลชนะ, shop ไข่, อัปเกรดทหาร)
- **Phase 5** — polish (sound, VFX, daily reward, leaderboard, notification)
- **Phase 6** — ทดสอบหลายผู้เล่น + publish

## กฎการทำงาน

### ใช้ skill `confirm-core-changes` เสมอ
ก่อนแก้/ลบ/เปลี่ยนชื่อ/รื้อ "โครงหลัก" ให้ทวนก่อนแล้วรอยืนยัน โครงหลักของโปรเจกต์นี้คือ:
- `default.project.json` (mapping ของ Rojo — พังแล้ว sync ไม่ได้ทั้งโปรเจกต์)
- **schema ของ DataStore** — ชื่อ key, โครงสร้างข้อมูลผู้เล่นที่บันทึกไปแล้ว
- **config กลางใน `src/shared`** — ตาราง rarity ไข่, ค่าสถิติทหาร, สูตร currency
- **RemoteEvent / RemoteFunction** — ชื่อและ signature ที่ client-server ตกลงกัน
- โครงโฟลเดอร์ `src/server|client|shared` และการแตก/รวมไฟล์
- อะไรก็ตามที่ทำให้ข้อมูลผู้เล่นเดิมอ่านไม่ออก

ไม่ต้องทวนเมื่อ: แก้สี/ข้อความ/UI เล็กน้อย, แก้บั๊ก scope แคบ, เพิ่มฟีเจอร์แยกอิสระ, หรือผู้ใช้บอกว่า "ทำเลย"

### กฎอื่น
- **อย่าแก้ไฟล์ `.rbxl` / `.rbxlx` โดยตรง** — เป็น binary ที่ build ออกมา แก้ที่ source เท่านั้น
- **server-authoritative** — การฟักไข่, สุ่มผล, คำนวณ combat, ให้ currency ต้องทำฝั่ง server ทั้งหมด ห้าม client ตัดสิน (กัน exploit)
- validate ทุก input ที่มาจาก client เสมอ
- ไม่ต้องเขียนโค้ดล่วงหน้าให้เฟสถัดไป ทำเฉพาะที่สั่ง
- commit เป็นก้อนย่อยตามงานที่ทำเสร็จ ข้อความ commit ภาษาอังกฤษสั้น ๆ

## สถานะปัจจุบัน
Phase 1 เสร็จแล้ว (อัปเดตบรรทัดนี้เมื่อจบแต่ละเฟส)

ค้างไว้ให้ Phase 2:
- คลังทหารกับสถานะไข่อยู่ใน memory ฝั่ง server ผู้เล่นออกเกม = ข้อมูลหาย ยังไม่มี DataStore
- `price` ของไข่มีใน Config แล้วแต่ยังไม่หักจริง (ระบบ currency อยู่ Phase 4)
- ไข่ที่ฟักค้างอยู่ตอนผู้เล่นออก ยังไม่ได้เก็บเวลาไว้ฟักต่อ
- UI ฝั่ง client เป็นแผงเทสต์ชั่วคราว ยังไม่ใช่ UI จริง
