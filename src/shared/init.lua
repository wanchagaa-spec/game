--!strict
-- egg-army-game :: Shared config / constants
--
-- ModuleScript ตัวนี้ถูก map ไปที่ ReplicatedStorage.Shared
-- ทั้ง server และ client require ตัวเดียวกันนี้ เพื่อไม่ให้ค่าคงที่หลุดออกจากกัน
--
-- Phase 0: โครงเปล่า ยังไม่ใส่ค่าจริง
--
-- ของที่จะมาอยู่ในนี้ตามแผนเฟส:
--   - ตาราง rarity ของไข่ และอัตราการสุ่ม
--   - ค่าสถิติทหารแต่ละชนิด (HP, damage, speed)
--   - สูตรคำนวณ currency และรางวัล
--   - ชื่อ RemoteEvent / RemoteFunction ที่ client-server ตกลงกัน
--   - type definitions ที่ใช้ร่วมกัน
--
-- หมายเหตุ: ของในไฟล์นี้ถือเป็น "โครงหลัก" ของโปรเจกต์
-- การแก้ค่าที่ผู้เล่นเดิมพึ่งพาอยู่ต้องทวนก่อนเสมอ

local Shared = {}

Shared.GAME_NAME = "egg-army-game"

return Shared
