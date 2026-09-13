--!strict
-- egg-army-game :: Client entry point
--
-- Phase 0: โครงเปล่า ยังไม่มี UI จริง
--
-- ที่นี่คือจุดรวมของ UI ทั้งหมดฝั่ง client
-- ของที่จะมาอยู่ในโฟลเดอร์นี้ตามแผนเฟส:
--
--   Phase 1 — UI ฟาร์มไข่ (จุดวางไข่, ตัวนับเวลาฟัก)
--   Phase 2 — UI คลังทหาร และหน้าจัดทีม
--   Phase 3 — UI สนามรบ (สถานะ HP, ผลการรบ)
--   Phase 4 — UI shop ไข่ และหน้าอัปเกรด
--   Phase 5 — polish: sound, VFX, notification
--
-- client มีหน้าที่ "แสดงผล + ส่งคำสั่ง" เท่านั้น
-- ห้ามตัดสินผลลัพธ์ของเกมเอง (กัน exploit) — ให้ server เป็นคนตัดสินเสมอ

print("[egg-army-game] client booted")
