--!strict
-- egg-army-game :: ReplicatedStorage.Shared
--
-- ตัวนี้เป็น ModuleScript ที่ทำหน้าที่เป็น "ฝา" ของโฟลเดอร์ shared เฉย ๆ
-- ของจริงอยู่ในโมดูลลูก require ตรงเข้าไปได้เลย ไม่ต้องผ่านไฟล์นี้:
--
--   ReplicatedStorage.Shared.Config   → ตารางไข่/ทหาร ค่าตั้งฟาร์ม ชื่อ RemoteEvent
--   ReplicatedStorage.Shared.Remotes  → สร้าง/รอหา RemoteEvent
--
-- ตัวอย่าง:
--   local Config = require(ReplicatedStorage.Shared.Config)

local Shared = {}

Shared.GAME_NAME = "egg-army-game"

return Shared
