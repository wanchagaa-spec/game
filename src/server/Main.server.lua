--!strict
-- egg-army-game :: Server entry point
--
-- หน้าที่ของไฟล์นี้คือ "ต่อสาย" อย่างเดียว logic จริงอยู่ในโมดูลแต่ละตัว
--   MapBuilder — สร้างแมพทั้งใบด้วยโค้ด (ลานคอก · เลนรบ · รังบอส · ร้านค้า)
--   PenService — จองคอกให้ผู้เล่น + วาดแม่ที่เดินได้และไข่ลงในคอกนั้น
--   EggService — สร้างไข่ (พร้อมน้ำหนัก) จับเวลา ฟักเป็นตัวแม่ เข้าคอก/กระเป๋า
--   DataService — อ่าน/เขียน PlayerData ลง DataStore (จุดเดียวในโปรเจกต์ที่แตะ DataStore)
--
-- Phase 2A: ข้อมูลเซฟลง DataStore แล้ว ออกเกมแล้วเข้าใหม่ของยังอยู่

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local MapBuilder = require(ServerScriptService.MapBuilder)
local DataService = require(ServerScriptService.DataService)
local PenService = require(ServerScriptService.PenService)
local EggService = require(ServerScriptService.EggService)
local ProductionService = require(ServerScriptService.ProductionService)
local CombatService = require(ServerScriptService.CombatService)

-- ⚠️ กันตัวละครเกิดก่อนแมพสร้างเสร็จ
-- แมพทั้งใบ generate ตอน server start ดังนั้น**ก่อนหน้านั้นโลกว่างเปล่า ไม่มีพื้นเลย**
-- ถ้าปล่อยให้เกิดเอง ตัวละครจะโผล่มาแล้วร่วงลงเหวทันที (ไม่มี Baseplate ให้ตก)
-- ปิดไว้ก่อน แล้วเปิดคืนหลังสร้างแมพเสร็จ
Players.CharacterAutoLoads = false

-- เช็คตาราง Config ก่อนอย่างอื่น พิมพ์ผิดตรงไหนจะได้รู้ตั้งแต่ตอนบูต
-- ⚠️ ถ้าตรงนี้ล้ม สคริปต์จะหยุดโดยที่ CharacterAutoLoads ยังเป็น false = ไม่มีใครเกิด
-- ซึ่งตั้งใจ — config พังแล้วไม่ควรให้ใครเข้าไปเล่น
--
-- ⚠️ แต่ **อาการที่เห็นคือ "ท้องฟ้าว่างเปล่า"** ซึ่งไม่ได้บอกอะไรเลยว่าเกิดอะไรขึ้น
-- (ไม่มีพื้น เพราะ MapBuilder ไม่ถูกเรียก · ไม่มีตัวละคร เพราะ CharacterAutoLoads ยัง false)
-- เคยเสียเวลาไล่หาสาเหตุมาแล้ว จึงพิมพ์ป้ายบอกให้ชัดก่อนปล่อย error ต่อ
-- หมายเหตุ: ห่อด้วย closure ที่ประกาศค่าคืนไว้ เพราะ `Config.validate()` ไม่คืนอะไร
-- แล้ว typechecker จะมองว่า pcall ให้ค่ากลับมาค่าเดียว รับ configErr ไม่ได้
local configOk, configErr = pcall(function(): string?
	Config.validate()
	return nil
end)
if not configOk then
	warn("════════════════════════════════════════════════════════════")
	warn("[Main] ❌ Config.validate() ไม่ผ่าน — แมพจะไม่ถูกสร้าง และตัวละครจะไม่เกิด")
	warn("[Main]    อาการที่เห็นในเกม: ท้องฟ้าว่างเปล่า ไม่มีพื้น ไม่มีตัวละคร")
	warn(`[Main]    สาเหตุ: {configErr}`)
	warn("════════════════════════════════════════════════════════════")
	error(configErr, 0)
end

-- ⚠️ ยามตัวที่สอง: ข้อมูลผู้เล่นที่ **เต็มทุกเพดานพร้อมกัน** ต้องยังอยู่ในลิมิต DataStore
-- แยกจาก Config.validate() เพราะ Config require PlayerData ไม่ได้ (จะวน require กลับมาหากัน)
--
-- ⚠️ ยามตัวนี้จับสิ่งที่ตาคนมองไม่เห็น: เพดานหนึ่งตัวขึ้น แล้วข้อมูลทะลุ 4 MB
-- ซึ่งอาการคือ **เซฟล้มเงียบ ๆ เฉพาะผู้เล่นที่สะสมเยอะ** = คนที่เล่นนานที่สุดเสียของก่อน
local dataOk, dataErr = pcall(function(): string?
	local bytes = PlayerData.validate()
	print(`[Main] ข้อมูลผู้เล่นที่เต็มทุกเพดาน = {bytes} ไบต์ (เพดานที่ตั้งไว้ {Config.DataStore.MAX_PLAYER_DATA_BYTES})`)
	return nil
end)
if not dataOk then
	warn("════════════════════════════════════════════════════════════")
	warn("[Main] ❌ PlayerData.validate() ไม่ผ่าน — เพดานที่ตั้งไว้ทำให้ข้อมูลเซฟไม่ลง")
	warn(`[Main]    สาเหตุ: {dataErr}`)
	warn("════════════════════════════════════════════════════════════")
	error(dataErr, 0)
end

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

-- ⚠️ property ตัวเลขของ Roblox เก็บเป็น float 32 บิต — ค่าที่อ่านกลับมาไม่ตรงกับเลขใน Config เป๊ะ
-- (เช่น JumpHeight 7.2 อ่านได้ 7.19999980926514) เทียบด้วย `~=` ตรง ๆ แล้วเตือนผิดทุกครั้งที่บูต
-- จึงเทียบแบบยอมคลาดเล็กน้อย — ห่างจริง ๆ (เช่น 6.37 กับ 7.2) ยังเตือนเหมือนเดิม
local FLOAT_TOLERANCE = 1e-3

local function differs(actual: number, expected: number): boolean
	return math.abs(actual - expected) > FLOAT_TOLERANCE
end

-- ⚠️ ความเร็ว**ฐาน**ของผู้เล่นต้องตรงกับ Config.MapDimensions.Player.WalkSpeed
-- ตั้งไว้ที่ StarterPlayer.CharacterWalkSpeed ใน default.project.json (ไม่ได้ตั้งตอน CharacterAdded)
-- เพราะ Roblox ใส่ค่าให้ตั้งแต่ตอนสร้าง Humanoid = ไม่ต้องต่อ event สำหรับค่าฐานที่ไม่เปลี่ยน
-- และแก้ได้จาก Studio โดยไม่ต้องรันเกม = ลองค่าใหม่ง่าย
-- แต่ **เช็คซ้ำตอนบูต** ด้วยเหตุผลเดียวกับ MaxPlayers: ค่านี้แก้จาก Studio ทับไฟล์ได้
-- และถ้ามันไม่ตรง ตัวเลขเวลาเดินทุกตัวที่ประเมินขนาดแมพไว้จะผิดหมดโดยไม่มีใครรู้
--
-- ⚠️ ตัวคูณจาก `speedLevel` ที่ซื้อด้วยเงิน (§8.8) เป็นคนละชั้นกับค่าฐานนี้ — ต่างจากค่าฐาน
-- ตัวคูณนี้**ต้องตั้งซ้ำทุกครั้งที่ CharacterAdded** เพราะ Humanoid ใหม่ทุกตัวรีเซ็ตกลับไปที่ค่า
-- ฐานของ StarterPlayer เสมอ (ดู `EggService.applyWalkSpeed` + hook ท้ายไฟล์นี้)
if differs(StarterPlayer.CharacterWalkSpeed, Config.MapDimensions.Player.WalkSpeed) then
	warn(
		`[Main] ⚠️ CharacterWalkSpeed = {StarterPlayer.CharacterWalkSpeed} แต่ Config ตั้งไว้ `
			.. `{Config.MapDimensions.Player.WalkSpeed} — เวลาเดินข้ามแมพจะไม่ตรงกับที่ออกแบบไว้ · `
			.. `แก้ที่ default.project.json`
	)
end

-- ⚠️ ความสูงกระโดดต้องตรงกับ Config.MapDimensions.Player.JumpHeight ด้วย
-- เพราะ `validate()` ใช้ค่านั้นตัดสินว่ากำแพงใสขอบแมพสูงพอกันกระโดดข้ามไหม
--
-- ⚠️ **ต้องเช็ค UseJumpPower ด้วย ไม่ใช่เช็คแค่ตัวเลข** — Roblox มีสองโหมด
-- ถ้า UseJumpPower ยังเป็น true ค่า JumpHeight จะถูกเพิกเฉยทั้งค่า
-- แล้วความสูงจริงจะมาจาก JumpPower แทน (50 → ราว 6.37 studs)
-- ซึ่งเป็นสภาพที่โปรเจกต์นี้เคยอยู่: Config เขียน 7 แต่ของจริง 6.37 และไม่มีใครรู้
if StarterPlayer.CharacterUseJumpPower then
	warn(
		`[Main] ⚠️ CharacterUseJumpPower = true — ค่า CharacterJumpHeight ถูกเพิกเฉย `
			.. `ความสูงกระโดดจริงมาจาก JumpPower ({StarterPlayer.CharacterJumpPower}) แทน · `
			.. `แก้ที่ default.project.json`
	)
elseif differs(StarterPlayer.CharacterJumpHeight, Config.MapDimensions.Player.JumpHeight) then
	warn(
		`[Main] ⚠️ CharacterJumpHeight = {StarterPlayer.CharacterJumpHeight} แต่ Config ตั้งไว้ `
			.. `{Config.MapDimensions.Player.JumpHeight} — เกณฑ์ความสูงกำแพงใสจะคำนวณจากค่าที่ไม่ตรงกับของจริง · `
			.. `แก้ที่ default.project.json`
	)
end

Remotes.setupServer()
DataService.init()
MapBuilder.build()
PenService.buildWorld()
EggService.start()

-- ⚠️ Phase 2B-1: ผลิตลูก + ผลิตเงินจากแม่ในคอก ทำงานเป็น periodic tick แยกจากลูปของ
-- EggService (คนละ interval: Config.Balance.Production.TICK_INTERVAL ไม่ใช่ Config.World.SYNC_INTERVAL)
-- ⚠️ inject EggService.sync เข้าไปแทนที่จะให้ ProductionService require EggService ตรง ๆ
-- กัน circular require (EggService เองก็ require ProductionService ไปเรียก settleMother
-- ตอนย้ายแม่ออกจากคอก)
ProductionService.start(EggService.sync)

-- ⚠️ Phase 3A: เครื่องยนต์คำนวณรบฝั่ง server — ลูปของตัวเอง คนละ loop กับ ProductionService/
-- EggService (อ่าน docs/data-schema.md §7) ต่อ RemoteEvent ของตัวเอง (SetReleaseOrderRequest /
-- SetSummonEnabledRequest) และเซฟผ่าน DataService path เดิม (stageProgress/currency ก็คือ
-- PlayerData fields ธรรมดา ไม่มีระบบเซฟแยก)
-- ⚠️ Phase 4A: inject ตัวแจกไข่รางวัลผ่านด่านเข้าไป (กัน circular require แบบเดียวกับ ProductionService)
CombatService.start(EggService.grantStageClearBonus)

-- ⚠️ ต่อ BindToClose **ก่อน** ปล่อยให้ใครเข้ามาเล่น
-- ถ้าต่อทีหลัง มีช่วงที่เซิร์ฟเวอร์ปิดแล้วไม่มีใครเซฟให้เลย
DataService.bindToClose()
DataService.startAutosave()

-- แมพพร้อมแล้ว มีพื้นให้ยืนแล้ว ค่อยปล่อยให้ตัวละครเกิด
Players.CharacterAutoLoads = true

local function onPlayerAdded(player: Player)
	local pen = PenService.assign(player)
	if pen then
		-- ⚠️ ให้เกิดใกล้คอกตัวเอง ไม่ใช่กลางลานแล้ววิ่งข้ามไปหา
		-- ตั้งก่อน LoadCharacter เสมอ · ใช้กับการเกิดใหม่หลังตายด้วยโดยไม่ต้องต่อ event เพิ่ม
		local spawnPad = MapBuilder.getSpawnLocation(pen.index)
		if spawnPad then
			player.RespawnLocation = spawnPad
			-- เผื่อกรณีตัวละครเกิดไปแล้วก่อนจองคอกเสร็จ (เข้ามาตอน server กำลังบูต)
			local character = player.Character
			if character then
				character:PivotTo(spawnPad.CFrame + Vector3.new(0, Config.MapDimensions.Player.Height, 0))
			end
		end
		print(`[Main] {player.Name} ได้คอก {pen.index} (เหลือว่าง {PenService.getFreeCount()})`)
	else
		warn(`[Main] คอกเต็ม ให้คอกกับ {player.Name} ไม่ได้ — Config.World.MAX_PENS ต้องเท่ากับจำนวนผู้เล่นสูงสุด`)
	end

	-- ⚠️ ต่อก่อนรอโหลดข้อมูลจบ — LoadAsync (DataStore) ช้ากว่า MapBuilder เสร็จมาก
	-- ตัวละครเกิดไปแล้วก่อนข้อมูล speedLevel พร้อมได้ง่าย ๆ ต่อ event ไว้ก่อนกันพลาดจังหวะนั้น
	-- ⚠️ ต้องต่อทุกครั้งที่ตายด้วย ไม่ใช่แค่ตอนเข้าเกม — Roblox รีเซ็ต WalkSpeed กลับเป็นค่า
	-- default ของ StarterPlayer ทุกครั้งที่ Humanoid ใหม่ถูกสร้าง (docs/data-schema.md §8.8)
	player.CharacterAdded:Connect(function()
		EggService.applyWalkSpeed(player)
	end)

	-- ต้องเรียกหลังจองคอกแล้ว เพราะไข่กับแม่ต้องมีคอกให้วางก่อน
	-- ⚠️ คืน false = โหลดข้อมูลไม่สำเร็จและผู้เล่นถูกเตะไปแล้ว — คืนคอกให้คนถัดไปด้วย
	if not EggService.onPlayerAdded(player) then
		PenService.release(player)
		return
	end

	-- เผื่อตัวละครเกิดไปแล้วก่อนข้อมูลโหลดเสร็จ (เข้าคิว CharacterAdded ไปแล้วตอนยังไม่มีข้อมูลให้อ่าน)
	EggService.applyWalkSpeed(player)
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
