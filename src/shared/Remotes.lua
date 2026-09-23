--!strict
-- egg-army-game :: ตัวจัดการ RemoteEvent
--
-- ⚠️ โครงหลัก: ชื่อ RemoteEvent อยู่ใน Config.RemoteNames
-- ไฟล์นี้ทำแค่ "สร้าง" (ฝั่ง server) กับ "รอหา" (ฝั่ง client) ไม่มี logic เกม
--
-- RemoteEvent ถูกสร้างตอน runtime แทนที่จะประกาศใน default.project.json
-- เพื่อไม่ให้ต้องแตะไฟล์ mapping ทุกครั้งที่เพิ่ม remote ใหม่

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local Remotes = {}

local NAMES = Config.RemoteNames

-- รายชื่อ RemoteEvent ทั้งหมดที่ server ต้องสร้างตอนบูต
local EVENT_NAMES: { string } = {
	NAMES.PLACE_EGG_IN_HATCHERY_REQUEST,
	NAMES.MOVE_MOTHER_REQUEST,
	NAMES.UPGRADE_PEN_REQUEST,
	NAMES.SELL_MOTHER_REQUEST,
	NAMES.EGG_HATCHED,
	NAMES.FARM_STATE_SYNC,
	NAMES.ACTION_RESULT,
	NAMES.AUTO_FILL_PEN_REQUEST,
	NAMES.SET_RELEASE_ORDER_REQUEST,
	NAMES.SET_SUMMON_ENABLED_REQUEST,
	NAMES.BUY_DAMAGE_UPGRADE_REQUEST,
	NAMES.BUY_SPEED_UPGRADE_REQUEST,
}

-- เรียกจากฝั่ง server ตอนบูตเท่านั้น สร้าง Folder + RemoteEvent ให้ครบ
-- เรียกซ้ำได้ ของที่มีอยู่แล้วจะไม่ถูกสร้างซ้ำ
function Remotes.setupServer(): Folder
	local folder = ReplicatedStorage:FindFirstChild(NAMES.FOLDER)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = NAMES.FOLDER
		created.Parent = ReplicatedStorage
		folder = created
	end

	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end

	return folder :: Folder
end

-- ดึง RemoteEvent มาใช้ ใช้ได้ทั้งสองฝั่ง
-- ฝั่ง client จะรอจนกว่า server จะสร้างเสร็จ (ปกติไม่เกินเสี้ยววินาที)
function Remotes.waitFor(name: string, timeout: number?): RemoteEvent
	local wait = timeout or 20

	local folder = ReplicatedStorage:WaitForChild(NAMES.FOLDER, wait)
	assert(folder, `Remotes: หา Folder "{NAMES.FOLDER}" ใน ReplicatedStorage ไม่เจอใน {wait} วินาที`)

	local event = folder:WaitForChild(name, wait)
	assert(event, `Remotes: หา RemoteEvent "{name}" ไม่เจอใน {wait} วินาที`)
	assert(event:IsA("RemoteEvent"), `Remotes: "{name}" ไม่ใช่ RemoteEvent (เป็น {event.ClassName})`)

	return event
end

return Remotes
