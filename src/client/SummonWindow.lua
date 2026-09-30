--!strict
-- egg-army-game :: หน้าต่างแท่นอัญเชิญ — UI-3 (กด E ค้างที่แท่นอัญเชิญปากเลน · MapSigns.lua)
--
-- สองแท็บ แม่ / ลูก · ติ๊กได้หลายรายการ · เลขบนการ์ด = ลำดับในรอบวน (เอาออกแล้วตัวหลังเลื่อนขึ้น)
-- ⚠️ 5E-1b: **เลขลำดับใช้ร่วมกันทั้งสองแท็บ** (ติ๊กแม่เป็น 1 แล้วไปติ๊กกองลูกได้ 2 …) = รอบวนปล่อยของแถวเดียว
--   server ปล่อยทีละตัวตามรอบวน 1,2,…,N,1,2,… (กองลูก = ทีละตัวจากกองนั้น · แม่ = ออกได้ทีละครั้ง)
--   ใต้รายการมีตัวอย่างลำดับวนสั้น ๆ ("ลำดับ: หมู → แม่ลิง → ม้า → …")
--   ลูก: ติ๊กกอง = อยู่ในรอบวน · **กองที่ไม่ติ๊กไม่ถูกปล่อย** (CombatService · UI-3)
--        กองที่หมดแต่แม่ในคอกผลิตเติมอยู่ = การ์ด "รอผลิต"
--        ยังไม่เคยติ๊กกองไหน (releaseOrder ว่าง) → เปิดมา**ติ๊กทุกกองไว้ก่อน** เรียงพลังต่อตัวมาก → น้อย (ผู้เล่นเอาออกเองได้)
--   แม่: เฉพาะแม่ในกระเป๋า (แม่ในคอกไม่แสดงเลย) · ล็อก = ติ๊กไม่ได้
--        แม่ในสนาม (roster) อยู่บนสุด ติดป้าย "ในสนาม" · **อยู่ในรอบวนเสมอ** มีเลขลำดับ แต่เอาติ๊กออกไม่ได้ (ดึงกลับไม่ได้)
--        ติ๊กได้ไม่เกินที่ว่างใน roster (MAX_BATTLE_MOTHERS − ในสนาม) · ไม่มีด่านให้ส่ง = บอกเหตุผล + ติ๊กไม่ได้
--        แม่ในกระเป๋าที่ติ๊กไว้ไม่จำข้ามการเปิดหน้าต่าง (ส่งแม่ = ตายถาวร ห้ามมีของค้างติ๊กที่ลืมไปแล้ว)
--   เปิดใหม่ = ลำดับจาก server (releaseCycle ใน sync) · ⚠️ ตำแหน่งแม่ในรอบวน server จำใน memory (ไม่แตะ schema) —
--        ออกเกม/เซิร์ฟใหม่ แม่ไปต่อท้ายรอบวน
-- "ส่งไปรบ": มีแม่ใหม่ = กล่องยืนยันครั้งเดียว → ส่งแม่ (ชุดเดียว) → ตั้งลำดับรวม → เปิดอัญเชิญ
--            ไม่มีแม่ใหม่ = ตั้งลำดับรวม + เปิดอัญเชิญเลย ไม่ถาม · รอบวนว่าง = ปุ่มปิด
-- "หยุดอัญเชิญ" โชว์เฉพาะตอนอัญเชิญอยู่
-- ⚠️ client ไม่ตัดสินอะไร: การปิดติ๊กเป็นแค่บอกผู้เล่นเร็ว ๆ — server ตรวจทุกตัวซ้ำ (SendMothersToBattleBatchRequest)
-- ⚠️ virtual grid แบบเดียวกับ BagWindow/SellWindow — ห้ามสร้าง ViewportFrame ทุกใบพร้อมกัน

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiKit = require(script.Parent:WaitForChild("UiKit"))

local SummonWindow = {}

export type Actions = {
	-- ⚠️ Main ต่อ remote ให้ · หน้าต่างนี้เรียกตามลำดับ แม่ → ลำดับลูก → เปิดอัญเชิญ เสมอ
	sendMothers: (uids: { string }) -> (),
	-- 5E-1b: ลำดับรวม (stack key + uid แม่ปนกัน) — SetReleaseOrderRequest signature เดิม
	setReleaseOrder: (order: { string }) -> (),
	setSummonEnabled: (enabled: boolean) -> (),
	notify: (text: string, ok: boolean) -> (),
}

export type Tab = "mothers" | "children"

type Item = {
	key: string, -- uid (แม่) · stack key (ลูก)
	charId: string,
	class: string,
	charName: string,
	weightText: string,
	statuses: { string },
	inField: boolean, -- แม่ใน battleRoster
	locked: boolean,
	count: number, -- ลูก: จำนวนในกอง (0 = รอผลิต)
	power: number?, -- ลูก: พลังต่อตัว (server คิดมาให้)
}

type Card = {
	button: TextButton,
	portrait: Frame,
	nameLabel: TextLabel,
	infoLabel: TextLabel,
	orderBadge: TextLabel,
	lockBadge: TextLabel,
	fieldTag: TextLabel,
	shade: Frame,
	selectedStroke: UIStroke,
	item: Item?,
}

-- ⚠️ ตำแหน่ง/ขนาดเดียวกับหน้าต่างกระเป๋า (docs/ui-overhaul-plan.md §3) — เปิดได้ทีละหน้าต่างอยู่แล้ว
local WINDOW_POSITION = UDim2.fromScale(0.235, 0.28)
local WINDOW_SIZE = UDim2.fromScale(0.484, 0.518)
local TAB_COLUMN_WIDTH = 0.088 -- ของความกว้างหน้าต่าง
local CONTENT_LEFT = 0.096
local COLUMNS = 5
local CARD_GAP_RATIO = 0.018 -- ของความกว้างตาราง
local CARD_HEIGHT_RATIO = 1.22 -- การ์ดสูงกว่ากว้าง: บรรทัดจำนวน/พลังอยู่ใต้ชื่อ
local MAX_BATTLE_MOTHERS = Config.Balance.Combat.MAX_BATTLE_MOTHERS

local CONTENT_COLOR = Color3.fromRGB(46, 52, 84)
local TAB_COLOR = Color3.fromRGB(44, 48, 70)
local CARD_COLOR = Color3.fromRGB(34, 36, 48)
local CARD_SELECTED_COLOR = Color3.fromRGB(58, 72, 110)
local CARD_DISABLED_COLOR = Color3.fromRGB(70, 70, 70)
local SELECTED_COLOR = Color3.fromRGB(120, 200, 255)
local LOCK_COLOR = Color3.fromRGB(120, 110, 170)
local FIELD_COLOR = Color3.fromRGB(200, 60, 60)
local INFO_COLOR = Color3.fromRGB(255, 220, 90)
local HINT_COLOR = Color3.fromRGB(205, 210, 225)
local WARN_COLOR = Color3.fromRGB(255, 110, 110)
local SEND_COLOR = Color3.fromRGB(200, 60, 60)
local STOP_COLOR = Color3.fromRGB(90, 90, 90)
local CANCEL_COLOR = Color3.fromRGB(90, 90, 90)

local actions: Actions
local window: Frame
local tabButtons: { [Tab]: TextButton } = {}
local scroll: ScrollingFrame
local statusLabel: TextLabel
local noticeLabel: TextLabel
local emptyLabel: TextLabel
local sendButton: TextButton
local stopButton: TextButton
local confirm: Frame
local confirmText: TextLabel

local lastPayload: any = nil
local activeTab: Tab = "children"
local items: { Item } = {}
local pool: { Card } = {}
local previewLabel: TextLabel
-- 5E-1b: รอบวนรวมสองแท็บ (หัว = ปล่อยก่อน) · เก็บ uid/stack key ไม่ใช่ตำแหน่ง — ลิสต์เปลี่ยนลำดับได้ทุก sync
type Entry = { kind: "mother" | "child", key: string }
local order: { Entry } = {}
local PREVIEW_ITEMS = 6

local function orderIndex(key: string): number?
	for index, entry in order do
		if entry.key == key then
			return index
		end
	end
	return nil
end

local function countKind(kind: "mother" | "child"): number
	local count = 0
	for _, entry in order do
		if entry.kind == kind then
			count += 1
		end
	end
	return count
end

local function rosterSet(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, mother in (if lastPayload then lastPayload.battleRoster else nil) or {} do
		set[mother.uid] = true
	end
	return set
end

-- แม่ในกระเป๋าที่ติ๊กไว้ (= จะส่งไปรบตอนกดส่ง) เรียงตามรอบวน
local function newMotherUids(): { string }
	local inRoster = rosterSet()
	local uids: { string } = {}
	for _, entry in order do
		if entry.kind == "mother" and not inRoster[entry.key] then
			table.insert(uids, entry.key)
		end
	end
	return uids
end

--------------------------------------------------------------------------------
-- ข้อมูล
--------------------------------------------------------------------------------

local function rosterCount(): number
	return if lastPayload then #(lastPayload.battleRoster or {}) else 0
end

-- ที่ว่างใน roster ตอนนี้ (ยังไม่หักที่ติ๊กไว้)
local function freeSlots(): number
	return math.max(0, MAX_BATTLE_MOTHERS - rosterCount())
end

-- เหตุผลที่ส่งแม่ไปรบไม่ได้ทั้งแท็บ (server คิดมาให้ใน sync — ข้อความเดียวกับที่ใช้ปฏิเสธจริง) · nil = ส่งได้
local function stageBlockReason(): string?
	return if lastPayload then lastPayload.sendStageBlockReason else nil
end

-- Phase 5A: เปิดอัญเชิญไม่ได้ตอนนี้เพราะอะไร (nil = ได้) — ตอนนี้มีเหตุเดียว: ล็อกเพราะบอส
-- ⚠️ server ตัดสิน (FarmStateSync.summonBlockReason) และปฏิเสธคำขอเองอยู่แล้ว · ตรงนี้แค่ปิดปุ่ม + บอกเหตุผล
local function summonBlockReason(): string?
	return if lastPayload then lastPayload.summonBlockReason else nil
end

local function classRank(class: string): number
	local info = Config.CharacterClasses[class]
	return if info then info.multiplier else 0
end

local function statusText(statuses: { string }): string
	if #statuses == 0 then
		return ""
	end
	local names: { string } = {}
	for _, statusId in statuses do
		local status = Config.getStatus(statusId)
		table.insert(names, if status then status.name else statusId)
	end
	return ` · {table.concat(names, ",")}`
end

local function motherItem(mother: any, inField: boolean): Item
	return {
		key = mother.uid,
		charId = mother.charId,
		class = mother.class or "?",
		charName = mother.charName or mother.charId,
		weightText = mother.weightText or tostring(mother.weight),
		statuses = mother.statuses or {},
		inField = inField,
		locked = mother.locked == true,
		count = 1,
		power = nil,
	}
end

local function stackItem(stack: any): Item
	return {
		key = stack.key,
		charId = stack.charId or "",
		class = stack.class or "?",
		charName = stack.charName or "?",
		weightText = stack.weightText or "?",
		statuses = stack.statuses or {},
		inField = false,
		locked = false,
		count = stack.count or 0,
		power = stack.power,
	}
end

local function buildItems(tab: Tab): { Item }
	local list: { Item } = {}
	local payload = lastPayload
	if not payload then
		return list
	end
	if tab == "mothers" then
		-- แม่ในสนามอยู่บนสุด (ลำดับเดิมของ roster) · แม่ในกระเป๋า: แรงก่อน (คลาสสูง → หนัก) · แม่ในคอกไม่แสดง
		for _, mother in payload.battleRoster or {} do
			table.insert(list, motherItem(mother, true))
		end
		local bag: { Item } = {}
		for _, mother in payload.mothersInBag or {} do
			table.insert(bag, motherItem(mother, false))
		end
		local weights: { [string]: number } = {}
		for _, mother in payload.mothersInBag or {} do
			weights[mother.uid] = mother.weight or 0
		end
		table.sort(bag, function(a: Item, b: Item)
			if classRank(a.class) ~= classRank(b.class) then
				return classRank(a.class) > classRank(b.class)
			end
			if weights[a.key] ~= weights[b.key] then
				return weights[a.key] > weights[b.key]
			end
			return a.key < b.key
		end)
		for _, item in bag do
			table.insert(list, item)
		end
	else
		-- ทุกกองที่มีของ + กองที่ติ๊กไว้แต่หมดชั่วคราว (waitingStacks) · แรงต่อตัวมากก่อน
		for _, stack in payload.children or {} do
			table.insert(list, stackItem(stack))
		end
		for _, stack in payload.waitingStacks or {} do
			table.insert(list, stackItem(stack))
		end
		table.sort(list, function(a: Item, b: Item)
			local pa, pb = a.power or 0, b.power or 0
			if pa ~= pb then
				return pa > pb
			end
			return a.key < b.key
		end)
	end
	return list
end

local function findItem(list: { Item }, key: string): Item?
	for _, item in list do
		if item.key == key then
			return item
		end
	end
	return nil
end

-- แม่ตัวนี้ติ๊กได้ไหม (ไม่นับเพดาน roster — เช็คแยกตอนติ๊กเพิ่ม)
local function motherTickable(item: Item): boolean
	return not item.inField and not item.locked and stageBlockReason() == nil
end

-- ตัดที่ติ๊กไว้แต่ใช้ไม่ได้แล้วทิ้ง (ส่ง/ขาย/ย้ายไปแล้ว · ถูกล็อกทีหลัง · ด่านหมด · roster เต็มจากที่อื่น · แม่ในสนามตาย)
-- แม่ในสนามที่ยังไม่อยู่ในรอบวน (ส่งจากที่อื่น) ต่อท้ายให้ — server ก็ต่อท้ายแบบเดียวกัน (อยู่ในรอบวนเสมอ)
local function pruneTicks()
	local mothers = buildItems("mothers")
	local stacks = buildItems("children")
	local kept: { Entry } = {}
	local newMothers = 0
	for _, entry in order do
		if entry.kind == "mother" then
			local item = findItem(mothers, entry.key)
			if item and item.inField then
				table.insert(kept, entry)
			elseif item and motherTickable(item) and newMothers < freeSlots() then
				newMothers += 1
				table.insert(kept, entry)
			end
		elseif findItem(stacks, entry.key) then
			table.insert(kept, entry)
		end
	end
	order = kept
	for _, item in mothers do
		if item.inField and not orderIndex(item.key) then
			table.insert(order, { kind = "mother", key = item.key })
		end
	end
end

-- รายการที่ติ๊กของแท็บนั้น เรียงตามรอบวน (สำเนา) — หัว = ปล่อยก่อน
function SummonWindow.getTicks(tab: Tab): { string }
	local kind = if tab == "mothers" then "mother" else "child"
	local keys: { string } = {}
	for _, entry in order do
		if entry.kind == kind then
			table.insert(keys, entry.key)
		end
	end
	return keys
end

-- รอบวนรวมสองแท็บ (สำเนา) — เลขบนการ์ด = ตำแหน่งในรายการนี้
function SummonWindow.getOrder(): { string }
	local keys: { string } = {}
	for _, entry in order do
		table.insert(keys, entry.key)
	end
	return keys
end

-- ตัวอย่างลำดับวนสั้น ๆ ใต้รายการ: "ลำดับ: หมู → แม่ลิง → ม้า → …"
local function previewText(): string
	if #order == 0 then
		return "ลำดับ: (ยังไม่ได้ติ๊ก)"
	end
	local mothers = buildItems("mothers")
	local stacks = buildItems("children")
	local names: { string } = {}
	for index, entry in order do
		if index > PREVIEW_ITEMS then
			break
		end
		local item = if entry.kind == "mother" then findItem(mothers, entry.key) else findItem(stacks, entry.key)
		local name = if item then item.charName else "?"
		table.insert(names, if entry.kind == "mother" then `แม่{name}` else name)
	end
	local more = if #order > PREVIEW_ITEMS then " → …" else ""
	return `ลำดับ: {table.concat(names, " → ")}{more} → วนกลับตัวแรก`
end
SummonWindow.getPreviewText = previewText

--------------------------------------------------------------------------------
-- การ์ด (pool ใช้ซ้ำ)
--------------------------------------------------------------------------------

local layoutGrid: () -> ()
local refreshHeader: () -> ()

local function toggleItem(item: Item)
	if activeTab == "mothers" and item.inField then
		-- แม่ในสนามอยู่ในรอบวนเสมอ — เอาติ๊กออก = ดึงกลับ ซึ่งทำไม่ได้
		actions.notify("แม่ตัวนี้อยู่ในสนามรบแล้ว — อยู่ในรอบวนเสมอ ดึงกลับไม่ได้", false)
		return
	end
	local index = orderIndex(item.key)
	if index then
		-- เอาออก → ตัวที่อยู่หลังเลื่อนขึ้นเองทั้งสองแท็บ (ลำดับ = ตำแหน่งในอาเรย์)
		table.remove(order, index)
	else
		if activeTab == "mothers" then
			if item.locked then
				actions.notify("แม่ตัวนี้ล็อกอยู่ ส่งไปรบไม่ได้ — ปลดล็อกในกระเป๋าก่อน", false)
				return
			end
			local reason = stageBlockReason()
			if reason then
				actions.notify(reason, false)
				return
			end
			if #newMotherUids() >= freeSlots() then
				actions.notify(`ส่งแม่ได้อีก {freeSlots()} ตัว (ในสนาม {rosterCount()}/{MAX_BATTLE_MOTHERS})`, false)
				return
			end
		end
		table.insert(order, { kind = if activeTab == "mothers" then "mother" else "child", key = item.key })
	end
	layoutGrid()
	refreshHeader()
end

local function createCard(): Card
	local button = UiKit.button({
		Name = "Card",
		BackgroundColor3 = CARD_COLOR,
		BackgroundTransparency = 0.1,
		AutoButtonColor = true,
		Visible = false,
	})
	UiKit.corner(button, UDim.new(0.08, 0))
	local selectedStroke = UiKit.border(button, SELECTED_COLOR, 3)
	selectedStroke.Enabled = false

	local portrait = UiKit.frame({
		Name = "PortraitHolder",
		Position = UDim2.fromScale(0.08, 0.03),
		Size = UDim2.fromScale(0.84, 0.52),
		BackgroundTransparency = 1,
	})
	portrait.Parent = button

	local nameLabel = UiKit.label({
		Name = "NameLabel",
		Position = UDim2.fromScale(0.04, 0.56),
		Size = UDim2.fromScale(0.92, 0.24),
		TextWrapped = true,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(nameLabel, 1.5)
	UiKit.maxTextSize(nameLabel, 18)
	nameLabel.Parent = button

	-- ลูก: จำนวน · พลังต่อตัว · แม่: คลาส
	local infoLabel = UiKit.label({
		Name = "InfoLabel",
		Position = UDim2.fromScale(0.04, 0.81),
		Size = UDim2.fromScale(0.92, 0.16),
		TextColor3 = INFO_COLOR,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(infoLabel, 1.5)
	infoLabel.Parent = button

	-- ติ๊กไม่ได้ (ล็อก · ในสนาม · ไม่มีด่านให้ส่ง): ทาเทาทับทั้งใบ
	local shade = UiKit.frame({
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiKit.BLACK,
		BackgroundTransparency = 0.45,
		ZIndex = 4,
		Visible = false,
	})
	UiKit.corner(shade, UDim.new(0.08, 0))
	shade.Parent = button

	local lockBadge = UiKit.label({
		Name = "LockBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.96, 0.03),
		Size = UDim2.fromScale(0.24, 0.17),
		BackgroundColor3 = LOCK_COLOR,
		BackgroundTransparency = 0,
		Text = "🔒",
		ZIndex = 5,
		Visible = false,
	})
	UiKit.corner(lockBadge, UDim.new(0.3, 0))
	lockBadge.Parent = button

	local fieldTag = UiKit.label({
		Name = "FieldTag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.8, 0.15),
		BackgroundColor3 = FIELD_COLOR,
		BackgroundTransparency = 0,
		FontFace = UiKit.FONT_HEAVY,
		Text = "ในสนาม",
		ZIndex = 5,
		Visible = false,
	})
	UiKit.corner(fieldTag, UDim.new(0.3, 0))
	UiKit.textStroke(fieldTag, 1)
	fieldTag.Parent = button

	-- เลขลำดับที่ติ๊ก (1, 2, 3, …)
	local orderBadge = UiKit.label({
		Name = "OrderBadge",
		Position = UDim2.fromScale(0.04, 0.03),
		Size = UDim2.fromScale(0.24, 0.17),
		BackgroundColor3 = SELECTED_COLOR,
		BackgroundTransparency = 0,
		FontFace = UiKit.FONT_HEAVY,
		TextColor3 = UiKit.BLACK,
		Text = "",
		ZIndex = 5,
		Visible = false,
	})
	UiKit.corner(orderBadge, UDim.new(0.3, 0))
	orderBadge.Parent = button

	local card: Card = {
		button = button,
		portrait = portrait,
		nameLabel = nameLabel,
		infoLabel = infoLabel,
		orderBadge = orderBadge,
		lockBadge = lockBadge,
		fieldTag = fieldTag,
		shade = shade,
		selectedStroke = selectedStroke,
		item = nil,
	}

	button.Activated:Connect(function()
		if card.item then
			toggleItem(card.item)
		end
	end)

	button.Parent = scroll
	return card
end

local function bindCard(card: Card, item: Item)
	card.item = item
	local position = orderIndex(item.key)
	-- แม่ในสนาม: ทาเทา (ดึงกลับไม่ได้) แต่ยังโชว์เลขลำดับในรอบวน
	local disabled = activeTab == "mothers" and not item.inField and not motherTickable(item)
	card.button.BackgroundColor3 = if disabled
		then CARD_DISABLED_COLOR
		elseif position then CARD_SELECTED_COLOR
		else CARD_COLOR
	card.selectedStroke.Enabled = position ~= nil
	card.orderBadge.Visible = position ~= nil
	card.orderBadge.Text = if position then tostring(position) else ""
	card.lockBadge.Visible = item.locked
	card.fieldTag.Visible = item.inField
	card.shade.Visible = disabled or (activeTab == "mothers" and item.inField)
	UiKit.setPortrait(card.portrait, item.charId, item.class)
	card.nameLabel.Text = `{item.charName}{statusText(item.statuses)}\n({item.weightText}kg)`
	if activeTab == "mothers" then
		card.infoLabel.Text = `คลาส {item.class}`
	else
		local power = `⚔️{UiKit.formatShort(item.power or 0)}`
		card.infoLabel.Text = if item.count > 0
			then `×{UiKit.formatShort(item.count)} · {power}`
			else `รอผลิต · {power}`
	end
end

-- ⚠️ virtual grid: วางการ์ดเท่าที่มองเห็น + 1 แถว · เลื่อน = ผูกการ์ดใน pool กับรายการใหม่
layoutGrid = function()
	local width = scroll.AbsoluteSize.X - scroll.ScrollBarThickness
	local height = scroll.AbsoluteSize.Y
	if width <= 0 or height <= 0 then
		return -- หน้าต่างยังปิดอยู่ — จะเรียกซ้ำเองตอนขนาดเปลี่ยน/เปิดหน้าต่าง
	end

	local gap = width * CARD_GAP_RATIO
	local cardWidth = (width - gap * (COLUMNS + 1)) / COLUMNS
	local cardHeight = cardWidth * CARD_HEIGHT_RATIO
	local rowHeight = cardHeight + gap
	local rows = math.ceil(#items / COLUMNS)
	scroll.CanvasSize = UDim2.fromOffset(0, rows * rowHeight + gap)

	local visibleRows = math.ceil(height / rowHeight) + 1
	local maxFirstRow = math.max(0, rows - visibleRows + 1)
	local firstRow = math.clamp(math.floor(scroll.CanvasPosition.Y / rowHeight), 0, maxFirstRow)
	local needed = visibleRows * COLUMNS
	while #pool < needed do
		table.insert(pool, createCard())
	end

	for slotIndex, card in pool do
		local itemIndex = firstRow * COLUMNS + slotIndex
		local item = if slotIndex <= needed then items[itemIndex] else nil
		if item then
			local row = (itemIndex - 1) // COLUMNS
			local column = (itemIndex - 1) % COLUMNS
			card.button.Size = UDim2.fromOffset(cardWidth, cardHeight)
			card.button.Position = UDim2.fromOffset(gap + column * (cardWidth + gap), gap + row * rowHeight)
			bindCard(card, item)
			card.button.Visible = true
		else
			card.item = nil
			card.button.Visible = false
		end
	end

	emptyLabel.Visible = #items == 0
	emptyLabel.Text = if activeTab == "mothers"
		then "ไม่มีแม่ในกระเป๋า — แม่ในคอกส่งไปรบไม่ได้ ถอดเข้ากระเป๋าก่อน (แผง 🐾)"
		else "ยังไม่มีลูก — แม่ในคอกผลิตลูกให้อัตโนมัติ"
end

--------------------------------------------------------------------------------
-- ส่วนหัว · แถบล่าง · กล่องยืนยัน
--------------------------------------------------------------------------------

local function setButton(button: TextButton, text: string, color: Color3, enabled: boolean)
	button.Text = text
	button.BackgroundColor3 = if enabled then color else UiKit.DISABLED
	button.AutoButtonColor = enabled
end

local function refreshConfirm()
	local mothers = #newMotherUids()
	if mothers == 0 then
		-- แม่ที่ติ๊กหลุดหมดระหว่างเปิดกล่อง (ส่ง/ล็อกจากที่อื่น · ด่านหมด) → ไม่มีอะไรให้ยืนยันแล้ว
		confirm.Visible = false
		return
	end
	local children = countKind("child")
	local childLine = if children > 0
		then `ลูก {children} กอง ปล่อยทีละตัวตามรอบวนที่ติ๊ก`
		else "ไม่ได้ติ๊กลูก — ลูกจะไม่ถูกปล่อย"
	-- 5E-1 (ผู้ใช้สั่ง): แม่ลงสนามจริงแล้ว โดนศัตรู/ป้อมฆ่าระหว่างรบได้ + ที่รอดตายหมดตอนด่านพัง (กติกาเดิม)
	confirmText.Text = `ส่งแม่ {mothers} ตัว — แม่อาจตายถาวรระหว่างรบ (โดนศัตรู/ป้อมยิง)`
		.. ` และแม่ที่เหลือทั้งหมดจะตายถาวรทันทีที่ด่านที่กำลังตีพัง ดึงกลับไม่ได้\n\n{childLine}`
end

refreshHeader = function()
	local payload = lastPayload
	if not payload then
		statusLabel.Text = "กำลังโหลด..."
		noticeLabel.Text = ""
		setButton(sendButton, "ส่งไปรบ", SEND_COLOR, false)
		stopButton.Visible = false
		return
	end

	local summoning = payload.summonEnabled == true
	local stage = if payload.activeStage then `ด่าน {payload.activeStage}` else "ผ่านครบทุกด่านแล้ว"
	-- 5E-1b: แถวเดียว (ไม่มีรวมพลแล้ว) · จำนวนในแถวมาจาก server (payload.battle)
	local battle = payload.battle
	local lineText = if summoning and battle and battle.our
		then ` · แถว {#battle.our}/{battle.lineLength or Config.Balance.Combat.LINE_LENGTH}`
		else ""
	local summonText = if summoning then "🟢 กำลังอัญเชิญ" else "⏸ หยุดอยู่"
	statusLabel.Text = `{summonText}{lineText} · ด่านที่กำลังตี: {stage}`
		.. ` · แม่ในสนามรบ {rosterCount()}/{MAX_BATTLE_MOTHERS}`

	-- ⚠️ Phase 5A: รวมเหตุผลทุกข้อที่บล็อกอยู่ (ไม่แทนที่กัน) — ล็อกบอสขึ้นก่อนเพราะเป็นตัวที่ห้ามกดส่งจริง
	local blocked = summonBlockReason()
	local warnings: { string } = {}
	if blocked then
		table.insert(warnings, blocked)
	end
	if payload.combatAutoPaused then
		table.insert(warnings, "ตีไม่เข้า — หยุดปล่อยอัตโนมัติ · กดส่งไปรบเพื่อเริ่มใหม่")
	end
	if activeTab == "mothers" then
		local reason = stageBlockReason()
		if reason then
			-- server ใส่เหตุผลล็อกบอสใน sendStageBlockReason ด้วย (ส่งแม่ไม่ได้) — ไม่ต้องขึ้นซ้ำสองรอบ
			if reason ~= blocked then
				table.insert(warnings, reason)
			end
		elseif freeSlots() == 0 then
			table.insert(warnings, `roster เต็มแล้ว ({rosterCount()}/{MAX_BATTLE_MOTHERS})`)
		end
	end
	if #warnings > 0 then
		noticeLabel.Text = `⚠️ {table.concat(warnings, " · ")}`
		noticeLabel.TextColor3 = WARN_COLOR
	elseif activeTab == "mothers" then
		noticeLabel.Text = `ติ๊กได้อีก {freeSlots() - #newMotherUids()} ตัว · เลข = ลำดับในรอบวน (ร่วมกับแท็บลูก) · แม่ในคอกไม่แสดง`
		noticeLabel.TextColor3 = HINT_COLOR
	else
		noticeLabel.Text = "ติ๊กกองที่จะปล่อย · เลข = ลำดับในรอบวน (ร่วมกับแท็บแม่) · กองที่ไม่ติ๊กจะไม่ถูกปล่อย"
		noticeLabel.TextColor3 = HINT_COLOR
	end
	previewLabel.Text = previewText()

	local mothers, children = countKind("mother"), countKind("child")
	if blocked then
		setButton(sendButton, "🔒 ส่งไปรบไม่ได้ — กำจัดบอสก่อน", SEND_COLOR, false)
		confirm.Visible = false -- ล็อกเข้ามาตอนกล่องยืนยันเปิดอยู่ → ปิดทิ้ง (กดยืนยันไปก็ไม่มีผล)
	else
		setButton(
			sendButton,
			if mothers + children > 0 then `⚔️ ส่งไปรบ (แม่ {mothers} · ลูก {children} กอง)` else "ส่งไปรบ (ยังไม่ได้ติ๊ก)",
			SEND_COLOR,
			mothers + children > 0
		)
	end
	stopButton.Visible = summoning
	if confirm.Visible then
		refreshConfirm()
	end
end

local function refreshAll()
	pruneTicks()
	items = buildItems(activeTab)
	layoutGrid()
	refreshHeader()
end

-- ⚠️ ลำดับยิงตายตัว: แม่ใหม่ (ถ้ามี · ชุดเดียว) → ลำดับรวม → เปิดอัญเชิญ — server รับตามลำดับที่ยิง
-- (แม่ต้องเข้า roster ก่อน ลำดับรวมถึงอ้าง uid ได้) · ส่งแม่ไม่ได้สักตัวก็ยังตั้งลำดับ + เปิดอัญเชิญ (server ตัด uid ที่ไม่อยู่ใน roster เอง)
local function fire()
	local uids = newMotherUids()
	local keys = SummonWindow.getOrder()
	if #uids > 0 then
		actions.sendMothers(uids)
	end
	actions.setReleaseOrder(keys)
	actions.setSummonEnabled(true)
	layoutGrid()
	refreshHeader()
end

local function onSend()
	if #order == 0 or summonBlockReason() then
		return
	end
	if #newMotherUids() > 0 then
		confirm.Visible = true
		refreshConfirm()
		return
	end
	fire() -- ไม่มีแม่ใหม่ ไม่ต้องยืนยัน (ไม่มีอะไรตายถาวรเพิ่ม)
end

local function onConfirm()
	confirm.Visible = false
	if #newMotherUids() == 0 or summonBlockReason() then
		return
	end
	fire()
end

--------------------------------------------------------------------------------
-- แท็บ
--------------------------------------------------------------------------------

function SummonWindow.setTab(tab: Tab)
	activeTab = tab
	for name, button in tabButtons do
		local stroke = button:FindFirstChild("Selected")
		if stroke then
			(stroke :: UIStroke).Enabled = name == tab
		end
	end
	scroll.CanvasPosition = Vector2.zero
	refreshAll()
end

local function makeTabButton(tab: Tab, order: number, icon: string, caption: string): TextButton
	local button = UiKit.button({
		Name = `Tab_{tab}`,
		Position = UDim2.new(0, 0, (order - 1) * 0.19, 0),
		Size = UDim2.fromScale(1, 0.17),
		BackgroundColor3 = TAB_COLOR,
		BackgroundTransparency = 0.15,
		Text = "",
	})
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = button
	UiKit.corner(button, UDim.new(0.14, 0))
	local stroke = UiKit.border(button, UiKit.WHITE, 3)
	stroke.Name = "Selected"
	stroke.Enabled = tab == activeTab

	local captionLabel = UiKit.label({
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.9, 0.24),
		Text = caption,
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(captionLabel, 1)
	captionLabel.Parent = button

	local iconLabel = UiKit.label({
		Position = UDim2.fromScale(0.15, 0.3),
		Size = UDim2.fromScale(0.7, 0.62),
		Text = icon,
	})
	iconLabel.Parent = button

	button.Activated:Connect(function()
		SummonWindow.setTab(tab)
	end)
	tabButtons[tab] = button
	return button
end

--------------------------------------------------------------------------------
-- สร้างหน้าต่าง
--------------------------------------------------------------------------------

local function makeButton(name: string, position: UDim2, size: UDim2, color: Color3, text: string): TextButton
	local button = UiKit.button({
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = color,
		Text = text,
	})
	UiKit.corner(button, UDim.new(0.25, 0))
	UiKit.textStroke(button, 1)
	UiKit.maxTextSize(button, 22)
	UiKit.padding(button, 0.08)
	return button
end

local function makeHeaderLabel(name: string, y: number, color: Color3): TextLabel
	local label = UiKit.label({
		Name = name,
		Position = UDim2.fromScale(0.02, y),
		Size = UDim2.fromScale(0.96, 0.055),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
	})
	UiKit.textStroke(label, 1)
	return label
end

function SummonWindow.create(parent: ScreenGui, windowActions: Actions)
	actions = windowActions

	window = UiKit.frame({
		Name = "SummonWindow",
		Position = WINDOW_POSITION,
		Size = WINDOW_SIZE,
		BackgroundTransparency = 1,
		Visible = false,
	})
	window.Parent = parent

	-- คอลัมน์แท็บด้านซ้าย (แบบหน้าต่างกระเป๋า)
	local tabColumn = UiKit.frame({
		Name = "Tabs",
		Size = UDim2.fromScale(TAB_COLUMN_WIDTH, 1),
		BackgroundTransparency = 1,
	})
	tabColumn.Parent = window
	makeTabButton("mothers", 1, "👑", "แม่").Parent = tabColumn
	makeTabButton("children", 2, "🐣", "ลูก").Parent = tabColumn

	local content = UiKit.frame({
		Name = "Content",
		Position = UDim2.fromScale(CONTENT_LEFT, 0),
		Size = UDim2.fromScale(1 - CONTENT_LEFT, 1),
		BackgroundColor3 = CONTENT_COLOR,
		BackgroundTransparency = 0.2,
	})
	UiKit.corner(content, UDim.new(0.03, 0))
	UiKit.border(content, UiKit.BLACK, 2)
	content.Parent = window

	local title = UiKit.label({
		Position = UDim2.fromScale(0.02, 0.025),
		Size = UDim2.fromScale(0.55, 0.075),
		Text = "✨ แท่นอัญเชิญ",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(170, 215, 255),
		FontFace = UiKit.FONT_HEAVY,
	})
	UiKit.textStroke(title, 1.5)
	title.Parent = content

	local closeButton = UiKit.button({
		Name = "Close",
		Position = UDim2.fromScale(0.935, 0.03),
		Size = UDim2.fromScale(0.05, 0.085),
		BackgroundColor3 = Color3.fromRGB(200, 60, 60),
		Text = "✕",
	})
	UiKit.corner(closeButton, UDim.new(0.25, 0))
	UiKit.textStroke(closeButton, 1)
	closeButton.Parent = content
	closeButton.Activated:Connect(function()
		SummonWindow.close()
	end)

	statusLabel = makeHeaderLabel("Status", 0.105, UiKit.WHITE)
	statusLabel.Parent = content
	noticeLabel = makeHeaderLabel("Notice", 0.16, HINT_COLOR)
	noticeLabel.Parent = content

	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Position = UDim2.fromScale(0.015, 0.22)
	scroll.Size = UDim2.fromScale(0.97, 0.58)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = content

	-- 5E-1b: ตัวอย่างลำดับวน (แม่ + กองลูกรวมกัน) ใต้รายการ
	previewLabel = makeHeaderLabel("Preview", 0.808, INFO_COLOR)
	previewLabel.TextTruncate = Enum.TextTruncate.AtEnd
	previewLabel.Parent = content

	emptyLabel = UiKit.label({
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.85, 0.1),
		TextColor3 = HINT_COLOR,
		TextWrapped = true,
		Visible = false,
	})
	UiKit.textStroke(emptyLabel, 1)
	emptyLabel.Parent = content

	stopButton = makeButton("Stop", UDim2.fromScale(0.02, 0.87), UDim2.fromScale(0.3, 0.1), STOP_COLOR, "⏹ หยุดอัญเชิญ")
	stopButton.Visible = false
	stopButton.Parent = content
	stopButton.Activated:Connect(function()
		actions.setSummonEnabled(false)
	end)

	sendButton = makeButton("Send", UDim2.fromScale(0.34, 0.87), UDim2.fromScale(0.64, 0.1), SEND_COLOR, "ส่งไปรบ")
	sendButton.Parent = content
	sendButton.Activated:Connect(onSend)

	-- กล่องยืนยันส่งแม่ — ทับทั้งพื้นที่เนื้อหา กันกดการ์ด/ปุ่มข้างหลังระหว่างถาม
	confirm = UiKit.frame({
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiKit.BLACK,
		BackgroundTransparency = 0.4,
		Active = true,
		ZIndex = 10,
		Visible = false,
	})
	UiKit.corner(confirm, UDim.new(0.03, 0))
	confirm.Parent = content

	local box = UiKit.frame({
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.66, 0.66),
		BackgroundColor3 = Color3.fromRGB(28, 30, 36),
		ZIndex = 11,
	})
	UiKit.corner(box, UDim.new(0.06, 0))
	UiKit.border(box, SEND_COLOR, 3)
	box.Parent = confirm

	confirmText = UiKit.label({
		Name = "Text",
		Position = UDim2.fromScale(0.06, 0.06),
		Size = UDim2.fromScale(0.88, 0.58),
		TextWrapped = true,
		FontFace = UiKit.FONT_HEAVY,
		ZIndex = 12,
	})
	UiKit.maxTextSize(confirmText, 24)
	confirmText.Parent = box

	local confirmYes =
		makeButton("ConfirmSend", UDim2.fromScale(0.06, 0.7), UDim2.fromScale(0.42, 0.22), SEND_COLOR, "ยืนยันส่งรบ")
	confirmYes.ZIndex = 12
	confirmYes.Parent = box
	confirmYes.Activated:Connect(onConfirm)

	local confirmNo =
		makeButton("ConfirmCancel", UDim2.fromScale(0.52, 0.7), UDim2.fromScale(0.42, 0.22), CANCEL_COLOR, "ยกเลิก")
	confirmNo.ZIndex = 12
	confirmNo.Parent = box
	confirmNo.Activated:Connect(function()
		-- ยกเลิก = แค่ปิดกล่อง ไม่ส่งอะไรไป server · ที่ติ๊กไว้ยังอยู่
		confirm.Visible = false
	end)

	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(layoutGrid)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutGrid)
end

function SummonWindow.setPayload(payload: any)
	lastPayload = payload
	if window.Visible then
		refreshAll()
	end
end

function SummonWindow.isOpen(): boolean
	return window.Visible
end

-- ค่าเริ่มต้นตอนยังไม่เคยติ๊กลูกเลย (releaseOrder ว่าง) = ทุกกองที่มีของ เรียงพลังต่อตัวมาก → น้อย
-- (buildItems เรียงแบบนี้อยู่แล้ว) · ⚠️ แค่ติ๊กในหน้าต่าง ยังไม่ส่งอะไร จนกว่าผู้เล่นจะกด "ส่งไปรบ" เอง
local function defaultChildTicks(): { string }
	local keys: { string } = {}
	for _, item in buildItems("children") do
		if item.count > 0 then -- กอง "รอผลิต" มาจากลำดับเดิมเท่านั้น ลำดับว่างจึงไม่ควรมี (กันไว้อีกชั้น)
			table.insert(keys, item.key)
		end
	end
	return keys
end

-- เปิด = รอบวนล่าสุดจาก server (releaseCycle ใน sync · แม่ในสนาม + กองที่ติ๊ก ตามลำดับเดิม)
-- ยังไม่เคยติ๊กกองไหน (releaseOrder ว่าง) = ติ๊กทุกกองไว้ก่อน (เรียงพลัง) ตามด้วยแม่ในสนาม · แม่ในกระเป๋าเริ่มไม่ติ๊กเสมอ
-- ⚠️ "ว่าง" รวมกรณีผู้เล่นเคยส่งลำดับที่ไม่มีกองลูกเอง — แยกไม่ได้โดยไม่แตะ schema ·
--   เปิดครั้งถัดไปจึงติ๊กทุกกองให้อีกรอบ (กล่องยืนยัน/ปุ่มส่งบอกจำนวนกองที่จะปล่อยก่อนส่งเสมอ)
function SummonWindow.open()
	window.Visible = true
	confirm.Visible = false
	table.clear(order)
	local payload = lastPayload
	local released = if payload then payload.releaseOrder or {} else {}
	local cycle = if payload then payload.releaseCycle or {} else {}
	if #released == 0 then
		for _, key in defaultChildTicks() do
			table.insert(order, { kind = "child", key = key })
		end
	end
	for _, item in cycle do
		if (item.kind == "child" or item.kind == "mother") and type(item.id) == "string" and not orderIndex(item.id) then
			table.insert(order, { kind = item.kind, key = item.id })
		end
	end
	scroll.CanvasPosition = Vector2.zero
	refreshAll() -- pruneTicks ตัดกองที่ไม่ได้แสดง (หมดแล้วไม่มีแม่ผลิตเติม) ทิ้ง + ต่อท้ายแม่ในสนามที่ขาด
end

-- ปิด = ล้างที่ติ๊กไว้ทั้งหมด + ปิดกล่องยืนยัน (ลำดับกลับมาจาก releaseCycle ตอนเปิดใหม่)
function SummonWindow.close()
	window.Visible = false
	confirm.Visible = false
	table.clear(order)
end

return SummonWindow
