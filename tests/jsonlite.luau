--!nocheck
-- egg-army-game :: ตัว decode JSON เล็ก ๆ **สำหรับเทสต์เท่านั้น**
--
-- ⚠️ มีไว้เพื่อให้เทสต์ roundtrip เป็นการทดสอบจริง ไม่ใช่การเช็คตัวเองกับตัวเอง
-- ฝั่ง encode ใช้ `PlayerData.encode` (โค้ด production) ส่วนฝั่ง decode ใช้ไฟล์นี้
-- ถ้าใช้ของชุดเดียวกันทั้งสองทาง ความผิดที่หักล้างกันเองจะมองไม่เห็น
--
-- เลียนพฤติกรรมของ Roblox ตรงจุดที่สำคัญที่สุด:
-- **object key เป็น string เสมอ** — อาเรย์ที่มีรูจึง decode กลับมาเป็น key string
-- ซึ่งคือบั๊กที่ docs/data-schema.md §9.3 เตือนไว้

local Json = {}

local function skipSpace(text: string, index: number): number
	while index <= #text and text:sub(index, index):match("%s") do
		index += 1
	end
	return index
end

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" }

local parseValue

local function parseString(text: string, index: number): (string, number)
	assert(text:sub(index, index) == '"', `jsonlite: คาดว่าเจอ " ที่ตำแหน่ง {index}`)
	index += 1

	local parts = {}
	while true do
		local char = text:sub(index, index)
		assert(char ~= "", "jsonlite: string ไม่จบ")

		if char == '"' then
			return table.concat(parts), index + 1
		elseif char == "\\" then
			local escape = text:sub(index + 1, index + 1)
			if escape == "u" then
				local code = tonumber(text:sub(index + 2, index + 5), 16)
				table.insert(parts, utf8.char(code))
				index += 6
			else
				table.insert(parts, ESCAPES[escape] or escape)
				index += 2
			end
		else
			table.insert(parts, char)
			index += 1
		end
	end
end

local function parseNumber(text: string, index: number): (number, number)
	local finish = index
	while finish <= #text and text:sub(finish, finish):match("[%d%.eE%+%-]") do
		finish += 1
	end
	local value = tonumber(text:sub(index, finish - 1))
	assert(value, `jsonlite: อ่านตัวเลขที่ตำแหน่ง {index} ไม่ออก`)
	return value, finish
end

function parseValue(text: string, index: number): (any, number)
	index = skipSpace(text, index)
	local char = text:sub(index, index)

	if char == "{" then
		local object = {}
		index = skipSpace(text, index + 1)
		if text:sub(index, index) == "}" then
			return object, index + 1
		end
		while true do
			local key
			key, index = parseString(text, skipSpace(text, index))
			index = skipSpace(text, index)
			assert(text:sub(index, index) == ":", `jsonlite: ขาด : ที่ตำแหน่ง {index}`)
			local value
			value, index = parseValue(text, index + 1)
			-- ⚠️ ตรงนี้คือหัวใจ: key ออกมาเป็น string เสมอ ไม่แปลงกลับเป็นตัวเลขให้
			object[key] = value
			index = skipSpace(text, index)
			local next = text:sub(index, index)
			if next == "," then
				index = skipSpace(text, index + 1)
			else
				assert(next == "}", `jsonlite: ขาด } ที่ตำแหน่ง {index}`)
				return object, index + 1
			end
		end
	elseif char == "[" then
		local array = {}
		index = skipSpace(text, index + 1)
		if text:sub(index, index) == "]" then
			return array, index + 1
		end
		while true do
			local value
			value, index = parseValue(text, index)
			table.insert(array, value)
			index = skipSpace(text, index)
			local next = text:sub(index, index)
			if next == "," then
				index += 1
			else
				assert(next == "]", `jsonlite: ขาด ] ที่ตำแหน่ง {index}`)
				return array, index + 1
			end
		end
	elseif char == '"' then
		return parseString(text, index)
	elseif text:sub(index, index + 3) == "true" then
		return true, index + 4
	elseif text:sub(index, index + 4) == "false" then
		return false, index + 5
	elseif text:sub(index, index + 3) == "null" then
		return nil, index + 4
	end

	return parseNumber(text, index)
end

function Json.decode(text: string): any
	local value = parseValue(text, 1)
	return value
end

return Json
