# คำสั่ง debug — ทดสอบ Phase 2B ใน Studio

⚠️ **ทั้งหมดนี้เป็นเครื่องมือทดสอบเท่านั้น ไม่ใช่ฟีเจอร์ในเกม** ไม่มี UI ไม่มี RemoteEvent
เรียกได้จาก **command bar ฝั่ง server** ใน Studio เท่านั้น (View → Command Bar หรือ `Ctrl+Alt+;` )
ต้องรันจาก Server Script (Studio → Command Bar ทำงานเป็น server context ได้ถ้าเลือก
"Server" ในเมนู dropdown ของ command bar)

### ⚠️ วิธีเรียกจาก Command Bar — ใช้สะพาน `ServerStorage.EggServiceDebug` ไม่ใช่ `require`

`require(game.ServerScriptService.EggService)` จาก Command Bar ได้โมดูล**อีกชุดหนึ่ง**ที่แยกแคชจากสคริปต์ของเกม
→ DataService ชุดนั้นไม่มีข้อมูลผู้เล่น → ทุกคำสั่งตอบ `ยังไม่มีข้อมูลผู้เล่น` (เจอจริงตอนทดสอบ Phase 4B)
จึงมี BindableFunction `ServerStorage.EggServiceDebug` (สร้างใน `Main.server.lua` **เฉพาะใน Studio**)
เรียก `EggService.debug*` ของตัวที่เกมใช้อยู่จริง — แปลงคำสั่งในเอกสารนี้แบบนี้:

```lua
-- ในเอกสาร:            EggService.debugSetStageProgress(player, 2, 0, 1)
-- พิมพ์ใน Command Bar:
game.ServerStorage.EggServiceDebug:Invoke("debugSetStageProgress", game.Players:GetPlayers()[1], 2, 0, 1)
```

- ชื่อฟังก์ชันเป็น string ตัวแรก ที่เหลือส่งต่อตามลำดับเดิม · ค่าที่ฟังก์ชันคืนมา `Invoke` คืนให้ด้วย
- เรียกได้เฉพาะชื่อที่ขึ้นต้นด้วย `debug` · Command Bar ต้องอยู่ฝั่ง **Server** (Test → Current: Server)
- ตัวแปร `local` ไม่ค้างข้ามการกด Enter แต่ละครั้ง ให้เขียนแต่ละคำสั่งให้จบในบรรทัดเดียว

ตัวอย่างข้างล่างยังเขียนแบบเดิม (`EggService.debugX(player, ...)`) เพื่อให้อ่านง่าย — ตอนใช้จริงแปลงตามข้างบน

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
EggService.debugGrantMother(player, 1500, nil, "bag")            -- แม่เล็ก ๆ สุ่มคลาสเอง (เหมือนฟักปกติ)
```

- `destination` ต้องเป็น `"pen"` หรือ `"bag"` เท่านั้น
- ⚠️ **ถ้า `destination = "pen"` แต่คอกเต็ม → ปฏิเสธตรง ๆ ไม่ fallback ไปกระเป๋าเงียบ ๆ**
  (เจตนา: กันไม่ให้เทสต์ "คอกเต็มพอดี" ที่ตั้งใจตั้งไว้เพี้ยนไปโดยไม่รู้ตัว)
- `weight` ต้องเป็นจำนวนเต็มบวก (ปัดเศษให้อัตโนมัติด้วย `math.floor` — น้ำหนักแม่ต้องเป็น
  จำนวนเต็มเสมอเพราะเป็นส่วนหนึ่งของ stack key)
- `charId` ต้องมีอยู่จริงใน `Config.Characters` (ดูรายชื่อในตาราง §ด้านล่าง) **หรือส่ง `nil`
  ให้สุ่มคลาสเอง** ผ่าน `Config.rollCharacter()` ตัวเดียวกับตอนฟักไข่ปกติ (อิงตารางคลาสของ
  `egg_stage1` เป็นค่าอ้างอิง — เครื่องมือนี้ไม่ผูกกับด่านไหนอยู่แล้ว)
  ⚠️ เคยพัง: ส่ง `nil` แล้วโดน `"ไม่มีตัวละคร \"nil\""` เพราะโค้ดเดิมเอา `nil` ไปค้นหาตรง ๆ
  ไม่มี branch สุ่มให้ — แก้แล้ว
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

⚠️ **ตั้งแล้วไม่แตะ `data.stageProgress` เลย** — ภาพกำแพงที่ `WallRenderer` วาดฝั่ง client
(รวมรอยแตก 5 ระดับจาก 3B-2) อ่านจาก `data.stageProgress` เท่านั้น ไม่ใช่จาก `wallProgress`
ตัวนี้ ตั้งค่านี้แล้วกำแพงในเกมจะยังดูไม่พัง ต้องดูผลจาก**สูตรเงิน/เพดาน damage upgrade**
ที่เปลี่ยนไปเท่านั้น · อยากทดสอบภาพกำแพงตรง ๆ ใช้ `EggService.debugSetStageProgress` ข้างล่าง
แทน (ตั้ง `stageProgress` ตรง ๆ แล้วให้ `wallProgress` sync ตามจริงให้เอง)
⚠️ ตั้งค่านี้ทิ้งไว้เฉย ๆ = `stageProgress` กับ `wallProgress` เพี้ยนไปจากกันชั่วคราว จนกว่าจะ
ตีด่านใหม่จริงจนแซงค่าที่ตั้งไว้ (หรือเรียก `debugResetAll` ล้างทั้งคู่กลับเป็นค่าเริ่มต้น)

- `n` ถูก clamp อยู่ในช่วง `1..Config.Balance.Stage.COUNT` (1–9) เสมอ — ใส่ 0 หรือติดลบ
  จะได้ 1, ใส่เกิน 9 จะได้ 9
- print ค่าก่อน/หลังเสมอ

### `EggService.debugSetStageProgress(player, stage, defendersRemaining, wallHpRemaining)`

ตั้งค่าความคืบหน้าของด่านหนึ่งตรง ๆ ข้ามการตีจริงทั้งหมด — ใช้ทดสอบ**ภาพกำแพงแตก 5 ระดับ +
เลขความเสียหายลอย** (Phase 3B-2) โดยไม่ต้องตีทหารฝ่ายรับนับพันล้าน HP จริงในด่านสูง ๆ

```lua
-- ด่าน 5 เหลือทหารฝ่ายรับ 0 แต่กำแพงเหลือ 25% ของ HP เต็ม — ดูรอยแตกระดับ 4 (25-1%)
local wallHpFull = Config.getStageWallHp(5)
EggService.debugSetStageProgress(player, 5, 0, math.floor(wallHpFull * 0.25))

-- พังทั้งด่าน 5 เลย — กำแพงหายไป + wallProgress ขยับตามจริงให้เอง
EggService.debugSetStageProgress(player, 5, 0, 0)
```

- `stage` ถูก clamp อยู่ในช่วง `1..Config.Balance.Stage.COUNT` (1–9) เสมอ (กันดัชนีหลุด
  array ยาวคงที่ 9 ช่องของ `stageProgress`)
- `defendersRemaining`/`wallHpRemaining` **ไม่ validate กับ HP เต็มของด่านนั้นเลย** (ตั้งเกินจริง
  ก็ได้ เป็นเครื่องมือ Studio-only เหมือน `debugSetWallProgress`) — clamp แค่ไม่ให้ติดลบ
- ⚠️ **ถ้าตั้งเป็น "พังทั้งด่าน" (`defendersRemaining=0` และ `wallHpRemaining=0`)** จะเรียก
  `CombatService.recomputeWallProgress(data)` ต่อท้ายให้เอง — `wallProgress` (เงิน + เพดาน
  damage upgrade) จะ sync ตามจริงทันที ไม่ต้องตั้ง `wallProgress` แยกเองอีกที
- print ค่าที่ตั้ง + `wallProgress` ก่อน/หลังเสมอ
- ⚠️ **ตั้ง "พังทั้งด่าน" ตรง ๆ ไม่ได้ไข่รางวัลผ่านด่าน (Phase 4A)** — รางวัลผูกกับจังหวะที่ด่าน
  เพิ่งพังใน `CombatService.tick` เท่านั้น · อยากทดสอบรางวัล ให้เหลือกำแพง 1 HP แล้วเปิดอัญเชิญให้ตีจริง:
  ```lua
  EggService.debugSetStageProgress(player, 2, 0, 1)  -- ตาถัดไปที่มี damage → ด่าน 2 พัง → popup + ไข่ 1 ฟอง
  ```
- **Phase 4B — popup รวมไข่ + แม่ตาย:** ส่งแม่ไปรบก่อน (UI-3: แท่นอัญเชิญปากเลน → แท็บแม่ → ส่งไปรบ) แล้วค่อยเหลือกำแพง 1 HP
  → popup เดียว "ผ่านด่าน N สำเร็จ! ได้รับไข่ฟรี X ฟอง • เสียแม่ในสนามรบ Y ตัว" (ขอบแดง)
  · ด่านที่เคยได้รางวัลแล้ว (ธง `stageClearBonusGranted` = true) ตั้ง HP กลับมาแล้วพังซ้ำพร้อมแม่ในสนาม
  → "ผ่านด่าน N สำเร็จ! เสียแม่ในสนามรบ Y ตัว" · พังซ้ำโดยไม่มีแม่ในสนาม → ไม่มี popup (ตั้งใจ)
- **5E-1b:** ตั้งค่าแล้วแถวศัตรูสร้างใหม่จาก HP ที่ตั้งเอง (tick ถัดไป) · เหลือกำแพง 1 HP ต้องมีทหารในแถวก่อนถึงจะพัง
  (ลูกในกองที่ติ๊ก หรือแม่ใน roster · ไม่มีรวมพลแล้ว — ปล่อยตัวแรกทันที แล้วเดินทัพจากแท่นไปกำแพง)

### `EggService.debugBattleStatus(player)` (5E-1 · 5E-1b)

พิมพ์สองแถว + รอบวนปล่อยลง Output (และคืนข้อความเดียวกัน) — ตัวอย่างจริงจากเครื่องยนต์ (ด่าน 3 · รอบวน ลิง → แม่ → หมู):

```
ด่าน 3 · อัญเชิญ เปิด · ป้อม เปิด
HP ทหารฝ่ายรับ 90831/100000 · HP กำแพง 50000/50000
แนวรบ: สู้ศัตรูกึ่งกลางเลน (นอกระยะป้อม)
แถวเรา (10/10 · หน้าสุดก่อน): 1.แม่ wukong 1014/1018 · 2.ลูก pig 3.464/3.464 · 3.ลูก monkey 2.236/2.236 · … · 10.ลูก monkey 2.236/2.236
  ตัวหน้าสุดตี 4679/วิ
แถวศัตรู (หน้าสุด = ตัวที่ 252/2724): 1.ใหญ่ 82.08/110.1 · 2.เล็ก 22.03/22.03 · … · 7.ใหญ่ 110.1/110.1 · … · 10.เล็ก 22.03/22.03
  ตัวหน้าสุดตี 3.727/วิ · เหลือ ใหญ่ 413 · เล็ก 2060
รอบวน (▶ = ตัวถัดไป): 1.ลูก monkey|500| เหลือ 33 · ▶2.แม่ 1234-5 (อยู่ในแถว) · 3.ลูก pig|1200| เหลือ 0
พร้อมปล่อย 33 · ตายติดกันไม่คืบหน้า 0/30
```

- แถวเรา: ตัวที่ 1 = หน้าสุด (ตัวเดียวที่ตี/โดนตี) · ≤ `LINE_LENGTH` (10) · เลือด = ที่เหลือ/เต็ม
- แถวศัตรู: 10 ตัวหน้าสุด · "ตัวที่ i/ทั้งหมด" = ลำดับตายตัวของด่าน (วน เล็ก 5 → ใหญ่ 1) · มีแผลได้แค่ตัวหน้าสุด
- รอบวน: รายการที่ติ๊ก (กองลูก + แม่ใน roster) · **▶ = รายการที่จะปล่อยตัวถัดไป** (อยู่ในแถวแล้ว/กองหมด = จะถูกข้าม) ·
  "เหลือ" หักตัวที่อยู่ในแถวออกแล้ว (ลูกในแถวยังนับอยู่ในกองจนกว่าจะตาย)
- ยังไม่เคยเปิดอัญเชิญในเซสชันนี้ = ยังไม่มีแถวศัตรู (สร้างตอน tick แรก)
- บรรทัด "แนวรบ" (เดินทัพ): `แถวว่าง` · `เดินทัพ pedestal → middle เหลือ 2.8/4.5 วิ` · `สู้ศัตรูกึ่งกลางเลน (นอกระยะป้อม)` · `ถึงกำแพงแล้ว (ป้อมยิง)`

```lua
game.ServerStorage.EggServiceDebug:Invoke("debugBattleStatus", game.Players:GetPlayers()[1])
```

### `EggService.debugTurret(on/off)` (5E-1)

เปิด/ปิดป้อมบนกำแพง **ทั้งเซิร์ฟ** (ไม่เซฟ · เซิร์ฟใหม่ = เปิดเสมอ) — ใช้เทียบว่าการตาย/เวลาตีเปลี่ยนตามป้อมจริง
รับได้ทั้งแบบไม่มี player และแบบสะพานปกติ:

```lua
game.ServerStorage.EggServiceDebug:Invoke("debugTurret", false)
game.ServerStorage.EggServiceDebug:Invoke("debugTurret", game.Players:GetPlayers()[1], true)
```

- ค่าที่ไม่ใช่ `true`/`false` = ปฏิเสธ (คืนข้อความบอกวิธีใช้)
- ปิดแล้ว HUD/ภาพไม่มีกล่องป้อม + เส้นยิง · `debugBattleStatus` บรรทัดแรกบอก "ป้อม ปิด (debug)"

### `EggService.debugSetCurrency(player, coins)`

ตั้งค่า `currency.coins` ตรง ๆ — ใช้ทดสอบอัปเกรดคอก/ขายแม่โดยไม่ต้องรอสะสมเงินจริง

```lua
EggService.debugSetCurrency(player, 1000000000)  -- พอสำหรับอัปคอกทุกขั้น
```

- แตะแค่ `coins` ไม่แตะ `gems` (คนละบ่อ)
- ค่าติดลบถูก clamp เป็น 0
- print ค่าก่อน/หลังเสมอ

### `EggService.debugSetWeaponTier(player, tier)` (5C)

ตั้งขั้นกระบองตรง ๆ **ไม่หักเงิน** — ทดสอบดาเมจ/หน้าตากระบองแต่ละขั้น หรือทดสอบร้านจากขั้นกลาง ๆ

```lua
game.ServerStorage.EggServiceDebug:Invoke("debugSetWeaponTier", game.Players:GetPlayers()[1], 5)
--> "debugSetWeaponTier: <ชื่อ> กระบอง 1 → 5 (กระบองเหล็ก · ดาเมจ 3000/ครั้ง) · ..."
```

- รับจำนวนเต็ม 1–10 เท่านั้น · ค่าอื่น (0 · 11 · 2.5 · "5") = ปฏิเสธ คืนข้อความ ไม่แตะข้อมูล
- ตั้งลดลงได้ (ทดสอบซื้อซ้ำ) · sync ทันที (หน้าต่างร้านอัปเดต) · กระบองในมือประกอบใหม่เองภายใน 0.25 วิ (BossService เทียบขั้นทุก tick)
- `debugResetAll` คืนกระบองเป็นขั้น 1 ด้วย

### `EggService.debugSimulateReceipt(player, productKey, purchaseId)`

⚠️ **UI-5** — จำลอง `MarketplaceService.ProcessReceipt` โดยไม่ต้องมี Robux จริง ไม่ต้อง publish จริง
เรียก `EggService.processReceipt` **ตัวเดียวกับที่ผูกไว้กับ `MarketplaceService.ProcessReceipt` จริง**
(ไม่ใช่โค้ดทดสอบแยกชุด) จึงทดสอบ idempotency ได้ตรง ๆ ผ่าน command bar

```lua
-- ซื้อไข่ตำนานครั้งแรก
EggService.debugSimulateReceipt(player, "legendary_egg", "test-purchase-1")
-- "PurchaseGranted"

-- เรียกซ้ำด้วย purchaseId เดิม (จำลอง Roblox retry ใบเสร็จเดิม) → ต้องได้ Granted เหมือนกัน
-- แต่ **ไม่ได้ไข่เพิ่มอีกฟอง** (เช็คด้วย debugSnapshot ก่อน/หลัง)
EggService.debugSimulateReceipt(player, "legendary_egg", "test-purchase-1")
-- "PurchaseGranted" (ของเดิม ไม่ให้ซ้ำ)

-- purchaseId ใหม่ → ให้ของอีกครั้งได้ตามปกติ
EggService.debugSimulateReceipt(player, "legendary_egg", "test-purchase-2")

-- productKey อื่น: "robux_damage_step" · "robux_speed_step" · "robux_hatch_rush"
EggService.debugSimulateReceipt(player, "robux_damage_step", "test-purchase-3")
```

- `productKey` คือ key ใน `Config.DeveloperProducts` หรือ `Config.RobuxProducts` (ไม่ใช่ตัวเลข `productId`)
- คืน string ธรรมดา `"PurchaseGranted"` หรือ `"NotProcessedYet"` (ไม่ใช่ Enum ตรง ๆ — Main.server.lua เป็นคนแปลงเป็น Enum จริงตอนคืนให้ MarketplaceService)
- ถ้าให้ของสำเร็จ ฟังก์ชันนี้ **เซฟจริงลง DataStore ทันที** (เหมือน `ProcessReceipt` จริงทุกประการ — ดู
  `docs/data-schema.md` §8.7) ไม่ใช่แค่แก้ในหน่วยความจำ

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

### `EggService.debugWipeSavedData(player, confirmName)`

🔴 **ลบข้อมูลผู้เล่นออกจาก DataStore แบบถาวร กู้คืนไม่ได้** — ต่างจาก `debugResetAll`
ที่แค่ล้างของในเกม (คอก/กระเป๋า/สวนฟัก) แต่ยัง "เป็นผู้เล่นเก่า" อยู่เสมอ (`isNew` เป็น
`false` ตลอดไปเพราะ key ใน DataStore ยังมีอยู่) ตัวนี้ลบทั้ง key ออกไปเลย ทำให้เข้าเกม
ครั้งถัดไป `isNew = true` จริง ได้ไข่เริ่มต้น (`Config.Balance.NewPlayer.startingEggs`)
และค่าเริ่มต้นทุกอย่างเหมือนผู้เล่นคนใหม่แกะกล่อง — ใช้เมื่อต้องทดสอบ flow "ผู้เล่นใหม่"
ซ้ำหลายรอบโดยไม่ต้องสลับ Roblox account

```lua
EggService.debugWipeSavedData(player, player.Name)  -- ต้องส่งชื่อผู้เล่นเป๊ะ ๆ เพื่อยืนยัน
```

- **อาร์กิวเมนต์ที่ 2 ต้องตรงกับ `player.Name` เป๊ะ ๆ** ไม่งั้นถูกปฏิเสธ (กันเผลอรันคำสั่ง
  ที่ก็อปมาโดยไม่ทันคิด — ไม่มีทาง "เผลอ" ลบข้อมูลโดยไม่ได้พิมพ์ชื่อคนที่จะลบเอง)
- **เตะผู้เล่นออกทันทีหลังลบสำเร็จเสมอ** ไม่ใช่บั๊ก — ต้องเข้าเกมใหม่ถึงจะเห็นผล
  (ข้อมูลของเซสชันปัจจุบันยังค้างอยู่ในหน่วยความจำ ถ้าไม่เตะ autosave รอบถัดไปจะเขียน
  ของเก่ากลับเข้า DataStore ใหม่ทันที ทำให้ลบไปแล้วก็เหมือนไม่ได้ลบ)
- ใช้ได้เฉพาะผู้เล่นที่ยังออนไลน์อยู่ตอนนี้เท่านั้น (ต้องมีข้อมูลอยู่ในแคชของเซิร์ฟเวอร์นี้)
- คืนค่า `(boolean, string?)` — `false, เหตุผล` เกิดได้ถ้าไม่ยืนยันชื่อ หรือ `RemoveAsync`
  ล้มครบ 3 ครั้ง (กรณีหลังผู้เล่นจะไม่ถูกเตะ ข้อมูลเดิมยังอยู่ครบ ลองเรียกใหม่ได้)

---

## คำสั่งบอส + วงจรกลางวัน/กลางคืน + ไข่บอส + บอสฟาด/เลือด (Phase 5A · 5B · 5B-2 · 5D) — อยู่ที่ `BossService`

เรียกผ่าน**สะพานเดียวกัน** (`ServerStorage.EggServiceDebug`) — สะพานหาชื่อใน `EggService` ก่อน ไม่เจอค่อยหาใน `BossService`
ทุกคำสั่งคืน**ข้อความสรุปสถานะ** (phase · เหลือกี่วิ · บอสยังอยู่กี่ห้อง · ล็อกใครเพราะห้องไหน · บรรทัดละห้อง) ให้ดูใน Output ทันที
⚠️ ไม่มีอะไรเซฟลง DataStore — สถานะบอสเป็นของเซิร์ฟ (memory) · คำสั่งพวกนี้วิ่งทางเดียวกับลูปจริง (วาป · กำแพงกั้น · แจ้งเตือน · แบ่งเงิน)
⚠️ **5B-2: บอสมีทุกห้อง (1–9)** — คำสั่งที่เกี่ยวกับห้องรับ**เลขห้องต่อท้าย** · **ไม่ใส่ = ห้อง 1** (เหมือนเดิม) ·
`debugDamageBoss`/`debugKillBoss` **ข้ามสิทธิ์เข้าห้อง + ระยะ** (ไว้ทดสอบห้องไกลโดยไม่ต้องพังกำแพงจริง) แต่ยังต้องกลางวัน + บอสห้องนั้นอยู่ ·
การแบ่งเงินยังตามกติกาจริง (ต้องยืนอยู่ในห้องนั้นถึงได้เงิน)

| คำสั่ง | ทำอะไร |
|---|---|
| `debugBossNight(firstEggKg?, room?)` | ข้ามไป**ต้นกลางคืน**ทันที: วาป**คนที่อยู่ในสนามรบ**มาหน้าป้อม (ฝั่งลาน · 5B-fix — คนในคอก/ลานอยู่ที่เดิม) · กำแพงกั้นปิดปากเลน · **บอสทั้ง 9 ห้องเกิด** (ตัวเก่ายังไม่ตาย = ฟื้น HP เต็ม) · **ไข่ 6 ฟองชุดใหม่ทุกห้อง** (ชุดเก่า + ที่ใครถืออยู่หาย) · นับ 59 → 0 ใหม่ · ใส่ `firstEggKg` (≥ 100) = บังคับน้ำหนักไข่ฟองที่ 1 **ของห้อง `room`** (ไม่ใส่ห้อง = ห้อง 1) **ก่อน**ประกาศ — ทดสอบประกาศไข่หนัก (> 100,000) โดยไม่ต้องรอดวง |
| `debugBossDay()` | ข้ามไป**ต้นกลางวัน**ทันที: กำแพงกั้นหาย เข้าไปตีบอสได้ (บอสห้องไหนตายไปแล้ว = ใช้ `debugBossNight` ก่อน · เปิดเซิร์ฟใหม่มีบอสครบทุกห้องอยู่แล้ว ไม่ต้องสั่งอะไร) |
| `debugDamageBoss(player, amount, room?)` | ทำดาเมจ `amount` ใส่บอส**ห้อง `room`** ในนามผู้เล่นคนนั้น — นับเข้าบันทึกผู้ทำดาเมจห้องนั้นเหมือนตีจริง · ต้องกลางวัน + บอสห้องนั้นยังอยู่ |
| `debugKillBoss(player, room?)` | ฆ่าบอส**ห้อง `room`** ในนามผู้เล่นคนนั้น (ดาเมจเท่า HP ที่เหลือ) → "กำจัดบอสห้อง N แล้ว!" · ปลดล็อกอัญเชิญ**เฉพาะคนที่ติดเพราะห้องนั้น** · ไข่ห้องนั้นหยิบได้ · **จ่ายเงินบอสห้องนั้น**ตามกติกาจริง (`Config.getBossKillReward(ห้อง)` · ต้องยืนอยู่ในห้องนั้นถึงได้) |
| `debugBossStatus()` | ดูสถานะอย่างเดียว ไม่เปลี่ยนอะไร — บรรทัดแรก phase/เวลา/ล็อก · ตามด้วยบรรทัดละห้อง (HP · ผู้ทำดาเมจ · ไข่) |
| `debugBossEggs(room?)` | น้ำหนัก · วาง/ถือ/เก็บแล้ว · ใครถือ ของไข่ + บอกว่าหยิบได้หรือยัง · ใส่ห้อง = ห้องเดียว · **ไม่ใส่ = ทุกห้อง** |
| `debugBossAttack(on)` (5D) | เปิด/ปิด**บอสฟาด**ทั้งเซิร์ฟชั่วคราว · รับ `true/false` · `"on"/"off"` · `1/0` · ปิด = วงแดงที่ง้างค้างหายทันที ไม่มีใครโดน · ไม่แตะ `BossCycle.BOSS_ATTACK_ENABLED` (เซิร์ฟเปิดใหม่กลับเป็นค่าใน Config = เปิด) · ค่าแปลก = ไม่แตะอะไร |
| `debugSetHealth(player, n)` (5D) | ตั้งเลือดผู้เล่น 0–เลือดเต็ม (100) · นับเป็น "เพิ่งโดนตี" → ยังไม่ฟื้นจนไม่โดนตีครบ 10 วิ แล้วฟื้นทีละนิด (20/วิ) · ⚠️ ยืนในเซฟโซน = เต็มทันทีใน 0.25 วิ (กติกา) — ทดสอบฟื้นเลือดให้ยืนในเลน · `0` = ตาย (ในสนามรบ → เกิดหน้าทางเข้าเลน · ในเซฟโซน → คอก) |

```lua
local P1 = game.Players:GetPlayers()[1]
game.ServerStorage.EggServiceDebug:Invoke("debugBossNight")
game.ServerStorage.EggServiceDebug:Invoke("debugBossNight", 152300)      -- ห้อง 1 ไข่ฟองที่ 1 หนัก 152,300 → ประกาศทั้งเซิร์ฟ
game.ServerStorage.EggServiceDebug:Invoke("debugBossNight", 152300, 7)   -- ห้อง 7 → "คืนนี้: ห้อง 7 ไข่ 152,300 กก."
game.ServerStorage.EggServiceDebug:Invoke("debugBossDay")
game.ServerStorage.EggServiceDebug:Invoke("debugDamageBoss", P1, 30)      -- ห้อง 1
game.ServerStorage.EggServiceDebug:Invoke("debugDamageBoss", P1, 300, 3)  -- ห้อง 3
game.ServerStorage.EggServiceDebug:Invoke("debugKillBoss", P1)            -- ห้อง 1
game.ServerStorage.EggServiceDebug:Invoke("debugKillBoss", P1, 5)         -- ห้อง 5
print(game.ServerStorage.EggServiceDebug:Invoke("debugBossStatus"))
print(game.ServerStorage.EggServiceDebug:Invoke("debugBossEggs"))         -- ทุกห้อง
print(game.ServerStorage.EggServiceDebug:Invoke("debugBossEggs", 3))      -- ห้อง 3
print(game.ServerStorage.EggServiceDebug:Invoke("debugBossAttack", false)) -- 5D: ปิดบอสฟาดทั้งเซิร์ฟ (ตีบอสสบาย ๆ)
print(game.ServerStorage.EggServiceDebug:Invoke("debugBossAttack", true))  -- 5D: เปิดกลับ
print(game.ServerStorage.EggServiceDebug:Invoke("debugSetHealth", P1, 40)) -- 5D: เลือด 40 (ไม่โดนตี 10 วิแล้วฟื้นทีละนิด)
print(game.ServerStorage.EggServiceDebug:Invoke("debugSetHealth", P1, 0))  -- 5D: ตายทันที (ทดสอบจุดเกิดใหม่)
```

- อยากเห็นข้อความคืนมา → ห่อด้วย `print(...)` (Output เห็นบรรทัด `[BossService] ...` อยู่แล้วทุกครั้งที่ phase เปลี่ยน/บอสตาย)
- เลขห้องแปลก (0 · 10 · "abc") → คืนข้อความบอกว่าผิด ไม่ทำอะไร
- ทดสอบล็อกอัญเชิญเร็ว ๆ: `debugBossNight` → `debugBossDay` (บอสทุกห้องอยู่) → `debugSetStageProgress(player, 2, 0, 1)`
  (ด่าน 2 เหลือ HP 1) → เปิดอัญเชิญ → ทหารพังกำแพงด่าน 2 → **ติดล็อกเพราะบอสห้อง 2** · `debugKillBoss(P1, 3)` ไม่ปลด ·
  `debugKillBoss(P1, 2)` ปลด · ขั้นตอนเต็มใน `docs/phase5-test-checklist.md` §14
- ~~ยังไม่มีคำสั่งตั้ง `weaponLevel`~~ → 5C: `debugSetWeaponTier(player, ขั้น)` (ข้างบน) · หรือ `debugKillBoss` ข้ามการตีจริง
- 5D: บอสฟาดทำงานเฉพาะ**กลางวัน + บอสห้องนั้นยังอยู่ + มีคนในวงแดง** — ทดสอบ: `debugBossNight` → `debugBossDay` → เดินเข้าใกล้บอสห้อง 1

---

## คำสั่งโมเดลตัวละคร (รอบโมเดลตัวละคร) — `EggService` + `PenService`

สะพานเดียวกัน (`ServerStorage.EggServiceDebug`) — หาชื่อใน `EggService` → `BossService` → `PenService` ตามลำดับ
📄 ขั้นตอนดูโมเดลใน Studio ทั้งชุด: `docs/models-test-checklist.md`

| คำสั่ง | ทำอะไร |
|---|---|
| `debugShowcaseModels()` (PenService) | วางโมเดลครบ 12 ตัวละครเรียงแถว**กลางทางเดินกลาง** (ลำดับดัชนี: ราชาปีศาจวัว → … → ปลา) ขนาด tier 1 (100 kg) × ขนาดคลาส = เท่าที่เห็นในคอก · หันหน้า −Z (ยืนฝั่ง −Z มองเข้าหา) · ป้ายหน้าเท้าบอก**ชื่อ · คลาส · จำนวนชิ้น** · คืนข้อความสรุป (ชื่อ · แบบ Part/mesh/กล่องสำรอง · จำนวนชิ้น · ความสูง) · **เรียกซ้ำ = ลบแถวเดิมแล้ววางใหม่** (ทุกตัวเป็น rig R6 · **วนท่าอยู่กับที่ ท่าละ 3 วิ: เดิน → ยืน → เหวี่ยงแขน** — สัตว์สี่ขา/ปลาไม่มีเหวี่ยงแขน · ไว้ดูอนิเมชันทีละตัว) · ภาพล้วน ไม่แตะข้อมูลผู้เล่น |
| `debugClearShowcase()` (PenService) | ลบแถวโชว์ออก (ไม่มีแถว = คืนข้อความบอก) |
| `debugGrantAllCharacters(player, weight?)` (EggService) | ให้แม่**ครบทุกตัวละคร** ตัวละครละ 1 ตัว เข้า**กระเป๋า** เรียงตามดัชนี · `weight` ไม่ใส่ = 100 kg (tier 1) · ปัดลงเป็นจำนวนเต็ม · ผ่าน `PlayerData.createMother` ทุกตัว (uid + ดัชนีขึ้นครบ) · กระเป๋าว่างไม่พอทั้งชุด = **ปฏิเสธทั้งชุด** (ไม่แจกครึ่ง ๆ · ไม่เปลือง uid) · ไว้ดูโมเดลในการ์ด/ดัชนี/หน้าต่างอัญเชิญ/ร้านขาย แล้วกด "สวมใส่ที่ดีที่สุด" ดูในคอก |

```lua
local P1 = game.Players:GetPlayers()[1]
print(game.ServerStorage.EggServiceDebug:Invoke("debugShowcaseModels"))
game.ServerStorage.EggServiceDebug:Invoke("debugClearShowcase")
game.ServerStorage.EggServiceDebug:Invoke("debugGrantAllCharacters", P1)            -- 100 kg ทุกตัว
game.ServerStorage.EggServiceDebug:Invoke("debugGrantAllCharacters", P1, 100000000) -- tier 7 ทุกตัว (ดูตัวใหญ่สุดในคอก)
```

---

## ตัวอย่าง flow ทดสอบครบทุก tier

⚠️ เขียนแบบ `require` ให้อ่านง่าย — ใน Command Bar ต้องแปลงเป็น `game.ServerStorage.EggServiceDebug:Invoke(...)` ทีละบรรทัด (ดูหัวเอกสาร)

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

## ตัวอย่าง flow ทดสอบ "ผู้เล่นใหม่" ซ้ำ ๆ (onboarding, ไข่เริ่มต้น)

⚠️ เขียนแบบ `require` ให้อ่านง่าย — ใน Command Bar ต้องแปลงเป็น `game.ServerStorage.EggServiceDebug:Invoke(...)` ทีละบรรทัด (ดูหัวเอกสาร)

```lua
local EggService = require(game.ServerScriptService.EggService)
local player = game.Players:GetPlayers()[1]

-- ลบข้อมูลเดิมของแอคเคาต์นี้ทิ้งถาวร แล้วเตะออกทันที (ต้องส่งชื่อผู้เล่นเป๊ะ ๆ เพื่อยืนยัน)
EggService.debugWipeSavedData(player, player.Name)
-- ผู้เล่นจะหลุดจากเกม — กด Play ใหม่ (หรือเข้าเซิร์ฟเวอร์ใหม่บนเกมจริง) แล้วดู onPlayerAdded
-- จะเห็น "เป็นผู้เล่นใหม่ — แจกไข่เริ่มต้นแล้ว" ใน log และได้ไข่ตาม NewPlayer.startingEggs จริง
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
| `yulai` | ราชาปีศาจวัว (เดิม "องค์ยูไล" · charId คงเดิม) | SS |
| `guanyin` | องค์หญิงพัดเหล็ก (เดิม "พระแม่กวนอิม" · charId คงเดิม) | S |
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
- `EggService.debugResetAll(player)` — ล้างทุกอย่าง (คอก/กระเป๋า/สวนฟัก/stageProgress/
  wallProgress/ธงรางวัลผ่านด่าน/**กระบองกลับขั้น 1** (5C)) กลับสู่สภาพเริ่มต้นจริง — ใช้ล้างสภาพที่ตั้งเองผ่าน `debugSetWallProgress`
  หรือตีด่านทดสอบค้างไว้ (⚠️ ไม่แตะ `currency` — ล้างแยกด้วย `debugSetCurrency` · และไม่แตะ
  `children`/`releaseOrder` เลย ยังไม่มีคำสั่ง debug สำหรับสองอย่างนี้)

## ทดสอบอัตโนมัตินอก Studio

ชุดคำสั่งข้างบนมีชุดทดสอบอัตโนมัติคู่กันแล้วที่ `tools/check-debug-commands.py`
(รันด้วย `python3 tools/check-debug-commands.py`) ครอบคลุมทุกกรณีปกติ + กรณีปฏิเสธ
ของทั้ง 6 ฟังก์ชันใหม่ (รวม `debugWipeSavedData` — เทสต์ด้วยว่า rejoin หลังลบแล้วได้
`isNew = true` จริง ไข่เริ่มต้นครบตาม `NewPlayer.startingEggs`) — ดูเป็นตัวอย่างการเรียกใช้
เพิ่มเติมได้ถ้าคำอธิบายข้างบนไม่ชัดพอ
