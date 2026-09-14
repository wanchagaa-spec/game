--!nocheck
-- egg-army-game :: พิมพ์ผังแมพกับเวลาเดิน เพื่อประเมินขนาดโดยไม่ต้องเปิด Studio
--
--     luau tools/dump-map.luau
--
-- ใช้ตอนอยากรู้ว่า "แมพยาวไปไหม" — ปรับค่าใน Config.Map แล้วรันใหม่ เห็นผลทันที
-- ตัวเลขทุกตัวคำนวณจาก Config จริง ไม่ได้พิมพ์มือ (เหมือน tools/gen-balance-tables.py)
--
-- ⚠️ เวลาเดินเป็นแค่ "เดินตรงไม่หยุด" ที่ Config.Map.WALK_SPEED_REFERENCE
-- ของจริงจะช้ากว่านี้เพราะมีเลี้ยว มีกระโดด และมีหยุดดูของ

local Config = require("../src/shared/Config")

local MAP = Config.Map
local SPEED = MAP.WALK_SPEED_REFERENCE

local function secs(distance: number): string
	local t = distance / SPEED
	if t < 60 then
		return string.format("%.0f วิ", t)
	end
	return string.format("%.1f นาที", t / 60)
end

local function line(char: string)
	print(string.rep(char, 66))
end

line("═")
print("ผังแมพ — egg-army-game")
print(string.format("ความเร็วเดินอ้างอิง %d studs/วินาที (ค่าเริ่มต้นของ Roblox)", SPEED))
line("═")

--------------------------------------------------------------------------------
-- โซนหลัก
--------------------------------------------------------------------------------

local shop = Config.getShopCenter()
local yardRight = Config.getPenYardRightX()
local laneStart = Config.getLaneStartX()
local laneEnd = laneStart + Config.getLaneLength()
local spawn = Config.getSpawnPoint()

print("")
print("── โซน (แกน X ซ้าย→ขวา) ──")
print(string.format("  ร้านค้า       กึ่งกลาง X = %7.0f   (กว้าง %.0f)", shop.X, MAP.SHOP_SIZE.X))
print(string.format("  ลานคอก        X = %7.0f .. %.0f   (กว้าง %.0f · %d แปลง %dx%d)",
	-yardRight, yardRight, Config.getPenYardWidth(), Config.World.MAX_PENS, MAP.PEN_ROWS, MAP.PEN_PER_ROW))
print(string.format("  จุดเกิด        X = %7.0f", spawn.X))
print(string.format("  เลนรบ         X = %7.0f .. %.0f   (ยาว %.0f · %d ด่าน ด่านละ %.0f)",
	laneStart, laneEnd, Config.getLaneLength(), Config.Stage.COUNT, MAP.LANE_LENGTH_PER_STAGE))

--------------------------------------------------------------------------------
-- เวลาเดิน — ตัวเลขที่ใช้ตัดสินว่า "ยาวไปไหม"
--------------------------------------------------------------------------------

print("")
print("── เวลาเดิน (เดินตรงไม่หยุด) ──")

local nest1 = Config.getBossNestCenter(1).X
local nestLast = Config.getBossNestCenter(Config.Stage.COUNT).X

local trips = {
	{ "จุดเกิด → ร้านค้า", math.abs(spawn.X - shop.X) },
	{ "จุดเกิด → ต้นเลนรบ", math.abs(laneStart - spawn.X) },
	{ "ร้านค้า → ต้นเลนรบ", math.abs(laneStart - shop.X) },
	{ "ต้นเลน → รังบอสด่าน 1", math.abs(nest1 - laneStart) },
	{ "ข้ามหนึ่งด่าน", MAP.LANE_LENGTH_PER_STAGE },
	{ `ต้นเลน → รังบอสด่าน {Config.Stage.COUNT}`, math.abs(nestLast - laneStart) },
	{ "ร้านค้า → ปลายเลน (สุดแมพ)", math.abs(laneEnd - shop.X) },
}

for _, trip in trips do
	print(string.format("  %-30s %7.0f studs   %s", trip[1], trip[2], secs(trip[2])))
end

--------------------------------------------------------------------------------
-- รายด่าน
--------------------------------------------------------------------------------

print("")
print("── รายด่าน ──")
print("  ด่าน │ ช่วง X          │ กำแพง  │ รังบอส │ เดินจากต้นเลนถึงรัง")
line("─")
for stage = 1, Config.Stage.COUNT do
	local startX = Config.getStageStartX(stage)
	local endX = startX + MAP.LANE_LENGTH_PER_STAGE
	local wallX = Config.getWallX(stage)
	local nestX = Config.getBossNestCenter(stage).X
	print(string.format("   %2d  │ %6.0f .. %-6.0f │ %6s │ %6.0f │ %s",
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
print(string.format("  ขนาดแปลง %.0f x %.0f · ทางเดินกลางกว้าง %.0f · ขอบกันชน %.0f",
	MAP.PEN_PLOT_SIZE.X, MAP.PEN_PLOT_SIZE.Z, MAP.WALKWAY_WIDTH, MAP.PEN_EDGE_MARGIN))

local halfX = MAP.PEN_PLOT_SIZE.X / 2 - MAP.PEN_EDGE_MARGIN
local halfZ = MAP.PEN_PLOT_SIZE.Z / 2 - MAP.PEN_EDGE_MARGIN
print(string.format("  พื้นที่ที่แม่เดินได้จริง %.0f x %.0f studs", halfX * 2, halfZ * 2))
print(string.format("  แม่เดินข้ามคอกด้านยาวใช้ %s (ที่ %.0f studs/วิ)",
	secs(halfX * 2 / MAP.WANDER_SPEED * SPEED), MAP.WANDER_SPEED))

print("")
line("═")
print("ปรับค่าที่ Config.Map แล้วรันใหม่เพื่อเทียบ — ไม่ต้องเปิด Studio")
line("═")
