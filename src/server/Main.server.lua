--!strict
-- egg-army-game :: Server entry point
--
-- หน้าที่ของไฟล์นี้คือ "ต่อสาย" อย่างเดียว logic จริงอยู่ในโมดูลแต่ละตัว
--   MapBuilder — สร้างแมพทั้งใบด้วยโค้ด (ลานคอก · เลนรบ · รังบอส · ร้านค้า)
--   PenService — จองคอกให้ผู้เล่น + วาดแม่ที่เดินได้และไข่ลงในคอกนั้น
--   EggService — สร้างไข่ (พร้อมน้ำหนัก) จับเวลา ฟักเป็นตัวแม่ เข้าคอก/กระเป๋า
--
-- Phase 1.5: ข้อมูลอยู่ใน memory ทั้งหมด ยังไม่มี DataStore (อยู่ Phase 2)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapBuilder = require(ServerScriptService.MapBuilder)
local PenService = require(ServerScriptService.PenService)
local EggService = require(ServerScriptService.EggService)

-- ⚠️ กันตัวละครเกิดก่อนแมพสร้างเสร็จ
-- แมพทั้งใบ generate ตอน server start ดังนั้น**ก่อนหน้านั้นโลกว่างเปล่า ไม่มีพื้นเลย**
-- ถ้าปล่อยให้เกิดเอง ตัวละครจะโผล่มาแล้วร่วงลงเหวทันที (ไม่มี Baseplate ให้ตก)
-- ปิดไว้ก่อน แล้วเปิดคืนหลังสร้างแมพเสร็จ
Players.CharacterAutoLoads = false

-- เช็คตาราง Config ก่อนอย่างอื่น พิมพ์ผิดตรงไหนจะได้รู้ตั้งแต่ตอนบูต
-- ⚠️ ถ้าตรงนี้ล้ม สคริปต์จะหยุดโดยที่ CharacterAutoLoads ยังเป็น false = ไม่มีใครเกิด
-- ซึ่งตั้งใจ — config พังแล้วไม่ควรให้ใครเข้าไปเล่น ดูข้อความ assert ใน Output ได้เลย
Config.validate()

-- ⚠️ MaxPlayers ต้องเท่ากับจำนวนคอก ไม่งั้นคนที่เกินมาจะเข้าเกมได้แบบไม่มีคอก
-- ตั้งไว้ใน default.project.json แล้ว แต่ **เช็คซ้ำตอนบูตด้วย**
-- เพราะ MaxPlayers แก้ได้จากหน้า Game Settings บนเว็บ Roblox ซึ่งทับค่าในไฟล์ได้
-- และ repo มองไม่เห็นการแก้ตรงนั้นเลย
if Players.MaxPlayers ~= Config.World.MAX_PENS then
	warn(
		`[Main] ⚠️ MaxPlayers = {Players.MaxPlayers} แต่มีคอก {Config.World.MAX_PENS} แปลง — `
			.. `คนที่เกินมาจะเข้าเกมได้แบบไม่มีคอก · แก้ที่ default.project.json หรือ Game Settings บนเว็บ`
	)
end

Remotes.setupServer()
MapBuilder.build()
PenService.buildWorld()
EggService.start()

-- แมพพร้อมแล้ว มีพื้นให้ยืนแล้ว ค่อยปล่อยให้ตัวละครเกิด
Players.CharacterAutoLoads = true

local function onPlayerAdded(player: Player)
	local pen = PenService.assign(player)
	if pen then
		print(`[Main] {player.Name} ได้คอก {pen.index} (เหลือว่าง {PenService.getFreeCount()})`)
	else
		warn(`[Main] คอกเต็ม ให้คอกกับ {player.Name} ไม่ได้ — Config.World.MAX_PENS ต้องเท่ากับจำนวนผู้เล่นสูงสุด`)
	end

	-- ต้องเรียกหลังจองคอกแล้ว เพราะไข่กับแม่ต้องมีคอกให้วางก่อน
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
-- ⚠️ ต้อง LoadCharacter เองด้วย เพราะตอนเขาเข้ามา CharacterAutoLoads ยังเป็น false
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
	if not player.Character then
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

print(
	`[egg-army-game] server พร้อมแล้ว · แมพ blockout · คอก {Config.World.MAX_PENS} แปลง · `
		.. `เลนยาว {Config.getLaneLength()} studs`
)
