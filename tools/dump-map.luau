--!nocheck
-- egg-army-game :: พิมพ์ผังแมพกับเวลาเดิน เพื่อประเมินขนาดโดยไม่ต้องเปิด Studio
--
--     luau tools/dump-map.luau
--
-- ใช้ตอนอยากรู้ว่า "แมพใหญ่ไปไหม" — ปรับค่าใน Config.MapDimensions แล้วรันใหม่ เห็นผลทันที
-- ตัวเลขทุกตัวคำนวณจาก Config จริง ไม่ได้พิมพ์มือ (เหมือน tools/gen-balance-tables.py)
--
-- ⚠️ เวลาเดินเป็นแค่ "เดินตรงไม่หยุด" ที่ Config.MapDimensions.Player.WalkSpeed
-- ของจริงจะช้ากว่านี้เพราะมีเลี้ยว มีกระโดด และมีหยุดดูของ

local Config = require("../src/shared/Config")

local MAP = Config.Map
local DIM = Config.MapDimensions
local SPEED = DIM.Player.WalkSpeed

local function secs(distance: number): string
	local t = distance / SPEED
	if t < 60 then
		return string.format("%.1f วิ", t)
	end
	return string.format("%.1f นาที", t / 60)
end

local function line(char: string)
	print(string.rep(char, 72))
end

line("═")
print("ผังแมพ — egg-army-game")
print(string.format("ความเร็ววิ่งผู้เล่น %d studs/วินาที (ค่าเริ่มต้นของ Roblox = 16)", SPEED))
line("═")

--------------------------------------------------------------------------------
-- โซนหลัก (แกน X ซ้าย→ขวา · แกน Z คือความลึก)
--------------------------------------------------------------------------------

local shop = Config.getShopCenter()
local yardLeft = Config.getPenYardLeftX()
local yardRight = Config.getPenYardRightX()
local laneStart = Config.getLaneStartX()
local laneEnd = Config.getLaneEndX()
local laneLength = Config.getLaneLength()
local plazaMinX = Config.getPlazaMinX()
local plazaMaxX = Config.getPlazaMaxX()
local plazaHalfDepth = Config.getPlazaHalfDepth()
local spawn = Config.getSpawnPoint()

local yardW = Config.getPenYardWidth()
local yardD = Config.getPenYardDepth()
local plazaW = plazaMaxX - plazaMinX
local plazaD = plazaHalfDepth * 2

print("")
print("── โซน ──")
print(string.format("  แผงร้านค้า    X = %7.1f        (%d แผง · แผงละ %.0f x %.0f)",
	shop.X, MAP.SHOP_STALL_COUNT, MAP.SHOP_STALL_SIZE.X, MAP.SHOP_STALL_SIZE.Z))
print(string.format("  ลานคอก        X = %7.1f .. %-7.1f   %.0f x %.0f studs (%d แปลง %dx%d · แปลงละ %.0f x %.0f)",
	yardLeft, yardRight, yardW, yardD,
	Config.World.MAX_PENS, MAP.PEN_ROWS, MAP.PEN_PER_ROW, MAP.PEN_PLOT_SIZE.X, MAP.PEN_PLOT_SIZE.Z))
print(string.format("  ลานหญ้ารวม    X = %7.1f .. %-7.1f   %.0f x %.0f studs (รวมแผงร้าน)",
	plazaMinX, plazaMaxX, plazaW, plazaD))
print(string.format("  จุดเกิดกลาง   X = %7.1f", spawn.X))
print(string.format("  เลนรบ         X = %7.1f .. %-7.1f   ยาว %.0f · กว้าง %.0f · %d ด่าน ด่านละ %.0f",
	laneStart, laneEnd, laneLength, MAP.LANE_WIDTH, Config.Stage.COUNT, MAP.LANE_LENGTH_PER_STAGE))

--------------------------------------------------------------------------------
-- ขนาดแมพทั้งใบ — กรอบที่กำแพงใสล้อมไว้
--------------------------------------------------------------------------------

-- ⚠️ พื้นลานรวม BOUNDARY_MARGIN ไว้แล้ว (getPlazaMinX / getPlazaHalfDepth)
-- กำแพงใสวางถอยเข้ามาจากขอบพื้นเท่ากับ margin → นอกกำแพงเป็นหญ้าที่เห็นแต่เดินไม่ถึง
local margin = MAP.BOUNDARY_MARGIN
local mapMinX = plazaMinX
local mapMaxX = laneEnd
local mapHalfZ = math.max(plazaHalfDepth, Config.getLaneHalfWidthAt(laneEnd), MAP.NEST_SIZE.Z / 2)

print("")
print("── แมพทั้งใบ (ขอบพื้น) ──")
print(string.format("  X = %.1f .. %.1f · Z = %.1f .. %.1f", mapMinX, mapMaxX, -mapHalfZ, mapHalfZ))
print(string.format("  ขนาดรวม %.0f x %.0f studs", mapMaxX - mapMinX, mapHalfZ * 2))
print(string.format("  กำแพงใส X = %.1f · Z = ±%.1f  (สูง %.0f · กระโดดได้ %.0f · หญ้านอกกำแพง %.0f)",
	plazaMinX + margin, plazaHalfDepth - margin, MAP.BOUNDARY_HEIGHT, DIM.Player.JumpHeight, margin))

--------------------------------------------------------------------------------
-- เวลาเดิน — ตัวเลขที่ใช้ตัดสินว่า "ใหญ่ไปไหม"
--------------------------------------------------------------------------------

print("")
print("── เวลาวิ่ง (วิ่งตรงไม่หยุด) ──")

local nest1 = Config.getBossNestCenter(1).X
local nestLast = Config.getBossNestCenter(Config.Stage.COUNT).X

local trips = {
	{ "ต้นลาน (ขอบซ้าย) → รังบอสด่าน 1", nest1 - plazaMinX },
	{ "จุดเกิด → แผงร้านค้า", math.abs(spawn.X - shop.X) },
	{ "จุดเกิด → ต้นเลนรบ", math.abs(laneStart - spawn.X) },
	{ "ต้นเลน → รังบอสด่าน 1", math.abs(nest1 - laneStart) },
	{ "ข้ามหนึ่งด่าน", MAP.LANE_LENGTH_PER_STAGE },
	{ `ต้นเลน → รังบอสด่าน {Config.Stage.COUNT}`, math.abs(nestLast - laneStart) },
	{ "ขอบซ้ายสุด → ขอบขวาสุด", mapMaxX - mapMinX },
	{ "คอก 1 → คอก 3 (ข้ามลาน)", math.abs(Config.getPenPlotCenter(3).X - Config.getPenPlotCenter(1).X) },
}

for _, trip in trips do
	print(string.format("  %-34s %7.0f studs   %s", trip[1], trip[2], secs(trip[2])))
end

--------------------------------------------------------------------------------
-- รายด่าน
--------------------------------------------------------------------------------

print("")
print("── รายด่าน ──")
print("  ด่าน │ ช่วง X            │ กำแพง  │ รังบอส │ วิ่งจากต้นเลนถึงรัง")
line("─")
for stage = 1, Config.Stage.COUNT do
	local startX = Config.getStageStartX(stage)
	local endX = startX + MAP.LANE_LENGTH_PER_STAGE
	local wallX = Config.getWallX(stage)
	local nestX = Config.getBossNestCenter(stage).X
	print(string.format("   %2d  │ %7.0f .. %-7.0f │ %6s │ %6.0f │ %s",
		stage, startX, endX,
		if wallX then string.format("%.0f", wallX) else "ไม่มี",
		nestX, secs(nestX - laneStart)))
end

--------------------------------------------------------------------------------
-- คอก
--------------------------------------------------------------------------------

print("")
print("── คอก ──")
local parts = {}
for index = 1, Config.World.MAX_PENS do
	local center = Config.getPenPlotCenter(index)
	table.insert(parts, string.format("%d(%.0f, %.0f)", index, center.X, center.Z))
end
print("  กึ่งกลางแต่ละแปลง: " .. table.concat(parts, " · "))
print(string.format("  ขนาดแปลง %.0f x %.0f · ทางเดินกลางกว้าง %.0f · ช่องระหว่างแปลง %.0f · ขอบกันชน %.0f",
	MAP.PEN_PLOT_SIZE.X, MAP.PEN_PLOT_SIZE.Z, MAP.WALKWAY_WIDTH, MAP.PEN_PLOT_GAP, MAP.PEN_EDGE_MARGIN))

local roamX = MAP.PEN_PLOT_SIZE.X - MAP.PEN_EDGE_MARGIN * 2
local roamZ = MAP.PEN_PLOT_SIZE.Z - MAP.PEN_EDGE_MARGIN * 2
local diagonal = math.sqrt(roamX * roamX + roamZ * roamZ)
print(string.format("  พื้นที่ที่แม่เดินได้จริง %.0f x %.0f studs (แนวทแยง %.0f)", roamX, roamZ, diagonal))
print(string.format("  แม่เดินข้ามคอกด้านยาว %.0f studs ใช้ %.1f วิ  ·  มุมถึงมุม %.0f studs ใช้ %.1f วิ   (ที่ %.1f studs/วิ)",
	roamX, roamX / MAP.WANDER_SPEED, diagonal, diagonal / MAP.WANDER_SPEED, MAP.WANDER_SPEED))
print(string.format("  ผู้เล่นวิ่งข้ามคอกมุมถึงมุมใช้ %s", secs(diagonal)))

print("")
line("═")
print("ปรับค่าที่ Config.MapDimensions แล้วรันใหม่เพื่อเทียบ — ไม่ต้องเปิด Studio")
line("═")
