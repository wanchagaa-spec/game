--!strict
-- egg-army-game :: Server entry point
--
-- หน้าที่ของไฟล์นี้คือ "ต่อสาย" อย่างเดียว logic จริงอยู่ในโมดูลแต่ละตัว
--   PlotService — จองพื้นที่ฟาร์มให้ผู้เล่น
--   EggService  — วางไข่ จับเวลา ฟัก สุ่มทหาร เก็บเข้าคลัง
--
-- Phase 1: ข้อมูลอยู่ใน memory ทั้งหมด ยังไม่มี DataStore (อยู่ Phase 2)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlotService = require(ServerScriptService.PlotService)
local EggService = require(ServerScriptService.EggService)

-- เช็คตาราง Config ก่อนอย่างอื่น พิมพ์ผิดตรงไหนจะได้รู้ตั้งแต่ตอนบูต
Config.validate()

Remotes.setupServer()
PlotService.buildWorld()
EggService.start()

local function onPlayerAdded(player: Player)
	local plot = PlotService.assign(player)
	if plot then
		print(`[Main] {player.Name} ได้ Plot {plot.index} (เหลือว่าง {PlotService.getFreeCount()})`)
	else
		warn(`[Main] ฟาร์มเต็ม ให้ plot กับ {player.Name} ไม่ได้ — เพิ่ม Config.Farm.MAX_PLOTS ถ้าต้องการรองรับมากกว่านี้`)
	end

	-- ต้องเรียกหลังจอง plot แล้ว เพราะการวางไข่ต้องมีแท่นวางอยู่ก่อน
	EggService.onPlayerAdded(player)
end

local function onPlayerRemoving(player: Player)
	EggService.onPlayerRemoving(player)
	PlotService.release(player)
	print(`[Main] {player.Name} ออกจากเกม คืน plot แล้ว`)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- เผื่อกรณีผู้เล่นเข้ามาก่อนสคริปต์นี้จะรันจบ (เกิดได้ตอนกด Play ใน Studio)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print("[egg-army-game] server พร้อมแล้ว (Phase 1)")
