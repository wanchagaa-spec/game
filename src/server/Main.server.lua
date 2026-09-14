--!strict
-- egg-army-game :: Server entry point
--
-- หน้าที่ของไฟล์นี้คือ "ต่อสาย" อย่างเดียว logic จริงอยู่ในโมดูลแต่ละตัว
--   PenService — จองคอกให้ผู้เล่น + แสดงแม่และสวนฟักในโลก
--   EggService — สร้างไข่ (พร้อมน้ำหนัก) จับเวลา ฟักเป็นตัวแม่ เข้าคอก/กระเป๋า
--
-- Phase 1.5: ข้อมูลอยู่ใน memory ทั้งหมด ยังไม่มี DataStore (อยู่ Phase 2)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PenService = require(ServerScriptService.PenService)
local EggService = require(ServerScriptService.EggService)

-- เช็คตาราง Config ก่อนอย่างอื่น พิมพ์ผิดตรงไหนจะได้รู้ตั้งแต่ตอนบูต
Config.validate()

Remotes.setupServer()
PenService.buildWorld()
EggService.start()

local function onPlayerAdded(player: Player)
	local pen = PenService.assign(player)
	if pen then
		print(`[Main] {player.Name} ได้คอก {pen.index} (เหลือว่าง {PenService.getFreeCount()})`)
	else
		warn(`[Main] คอกเต็ม ให้คอกกับ {player.Name} ไม่ได้ — Config.World.MAX_PENS ต้องเท่ากับจำนวนผู้เล่นสูงสุด`)
	end

	-- ต้องเรียกหลังจองคอกแล้ว เพราะการวางไข่ต้องมีแท่นฟักอยู่ก่อน
	EggService.onPlayerAdded(player)
end

local function onPlayerRemoving(player: Player)
	EggService.onPlayerRemoving(player)
	PenService.release(player)
	print(`[Main] {player.Name} ออกจากเกม คืนคอกแล้ว`)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- เผื่อกรณีผู้เล่นเข้ามาก่อนสคริปต์นี้จะรันจบ (เกิดได้ตอนกด Play ใน Studio)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print("[egg-army-game] server พร้อมแล้ว (Phase 1.5)")
