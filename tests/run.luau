--!nocheck
-- egg-army-game :: ตัวรันเทสต์
--
-- รันด้วยคำสั่งเดียวจากรากโปรเจกต์:
--
--     luau tests/run.luau
--
-- ไม่ต้องเปิด Roblox Studio ไม่ต้อง build อะไรก่อน ไม่ต้องใช้ Python
-- ออก exit code 1 เมื่อมีเทสต์ตก จึงเอาไปต่อ CI ได้ตรง ๆ
--
-- ⚠️ Config.lua โหลดในนี้ได้เพราะมันเช็ค Color3 / Vector3 แล้ว fallback เอง
-- (ดูบล็อก "ทำให้ไฟล์นี้โหลดได้นอก Roblox" ที่หัว Config.lua)
-- ถ้าวันไหนมีคนใส่ API ของ Roblox ตัวใหม่ลง Config ตรง ๆ ไฟล์นี้จะพังทันที
-- ซึ่งตั้งใจ — เป็นสัญญาณว่าต้องเพิ่ม fallback ให้ตัวนั้นด้วย
--
-- สิ่งที่เทสต์ชุดนี้ตรวจไม่ได้ (ต้องเปิด Studio เอง) อยู่ใน tests/README.md

local Config = require("../src/shared/Config")

--------------------------------------------------------------------------------
-- harness
--------------------------------------------------------------------------------

local t = {
	pass = 0,
	fail = 0,
	failures = {},
}

local function record(ok: boolean, message: string)
	if ok then
		t.pass += 1
	else
		t.fail += 1
		table.insert(t.failures, message)
		print(`  ✗ {message}`)
	end
end

-- เทียบตรง ๆ ด้วย == ใช้กับ string / number ที่ลงตัว / boolean / nil
function t.check(label: string, got: any, want: any)
	record(got == want, `{label}: ได้ "{tostring(got)}" ต้องการ "{tostring(want)}"`)
end

-- เทียบแบบมีค่าคลาดเคลื่อน ใช้กับผลคำนวณทศนิยมและผลสุ่ม
function t.near(label: string, got: number, want: number, tol: number)
	record(math.abs(got - want) <= tol, `{label}: ได้ {got} ต้องการ ~{want} (±{tol})`)
end

--------------------------------------------------------------------------------
-- รันทุกชุด
--------------------------------------------------------------------------------

-- เพิ่มชุดใหม่ = เพิ่มไฟล์ .spec.luau แล้วต่อท้ายตารางนี้
-- แต่ละชุดเป็นฟังก์ชันที่รับ (t, Config)
local suites: { { name: string, run: (any, any) -> () } } = {
	{ name = "Config", run = require("./config.spec") },
	{ name = "PlayerData + DataService", run = require("./playerdata.spec") },
	{ name = "ProductionService", run = require("./production.spec") },
}

local startedAt = os.clock()

for _, suite in suites do
	print(`\n━━ ชุด: {suite.name} ━━`)
	suite.run(t, Config)
end

local elapsed = os.clock() - startedAt

--------------------------------------------------------------------------------
-- สรุปผล
--------------------------------------------------------------------------------

print(string.format("\n=== ผ่าน %d / ตก %d  (%.1f วินาที) ===", t.pass, t.fail, elapsed))

if t.fail > 0 then
	print("\nรายการที่ตก:")
	for i, message in t.failures do
		print(`  {i}. {message}`)
	end
	-- error() ทำให้ luau CLI ออกด้วย exit code 1
	error(`มีเทสต์ตก {t.fail} เคส`, 0)
end
