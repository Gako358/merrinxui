local addonName, ns = ...

local L = ns.SpellTrainingLogic
local Theme = ns.Theme

local WIDTH = 300
local HEADER_HEIGHT = 22
local ROW_HEIGHT = 16
local ICON_SIZE = 14
local PADDING = 6
local SCROLL_STEP = 3
local LEVEL_WIDTH = 22
local FONT_KEY = ns.FontLogic.GLOBAL
local TITLE_SIZE = 11
local ROW_SIZE = 11

local COLOR = {
	available = { 0.4, 0.9, 0.4, 1 },
	missing = { 1, 0.6, 0.2, 1 },
	soon = { 0.4, 0.8, 1, 1 },
	later = { 0.9, 0.35, 0.35, 1 },
}

local function known(id)
	return C_SpellBook.IsSpellInSpellBook(id, Enum.SpellBookSpellBank.Player, false) == true
		or C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Player) == true
end

local panel, book, title, emptyFS
local rowPool = {}
local lines = {}
local offset = 0
local level
local token, model, modelError
local pending = {}
local failed = {}
local refreshScheduled = false
local attached = false
local attachError

local function setTextColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4])
end

local function ensureModel()
	if model ~= nil or modelError ~= nil then
		return model
	end

	token = select(2, UnitClass("player"))
	local classData = ns.SpellTrainingData and ns.SpellTrainingData[token]
	ns.SpellTrainingData = nil
	if classData == nil then
		modelError = "no data " .. tostring(token)
		return nil
	end

	local ok, err = L.Validate(classData, token)
	if not ok then
		modelError = err
		return nil
	end

	model = L.Build(classData, UnitFactionGroup("player"), select(3, UnitRace("player")))
	return model
end

local function visibleRows()
	local height = panel:GetHeight()
	return math.max(0, math.floor((height - HEADER_HEIGHT - PADDING) / ROW_HEIGHT))
end

local function applyHeaderLine(row, line)
	row.spellId = nil
	row.levelFS:Hide()
	row.icon:Hide()

	row.nameFS:ClearAllPoints()
	row.nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.nameFS:SetPoint("RIGHT", row.costFS, "LEFT", -4, 0)
	row.nameFS:SetText(line.label .. " (" .. line.count .. ")")
	setTextColor(row.nameFS, COLOR[line.key] or Theme.color.text)

	row.costFS:SetText(C_CurrencyInfo.GetCoinTextureString(line.total))
	setTextColor(row.costFS, Theme.color.text)
end

local function applySpellLine(row, line)
	local entry = line.entry
	row.spellId = entry.id
	row.levelFS:Show()
	row.icon:Show()
	row.levelFS:SetText(tostring(entry.level))
	setTextColor(row.levelFS, Theme.color.textDim)

	row.nameFS:ClearAllPoints()
	row.nameFS:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.nameFS:SetPoint("RIGHT", row.costFS, "LEFT", -4, 0)

	if C_Spell.IsSpellDataCached(entry.id) == false then
		if not failed[entry.id] then
			pending[entry.id] = true
			C_Spell.RequestLoadSpellData(entry.id)
		end
		row.icon:SetTexture(nil)
		row.nameFS:SetText("Spell " .. entry.id)
		setTextColor(row.nameFS, Theme.color.textDim)
	else
		row.icon:SetTexture(C_Spell.GetSpellTexture(entry.id))
		local name = C_Spell.GetSpellName(entry.id) or ("Spell " .. entry.id)
		if type(C_Spell.GetSpellSubtext) == "function" then
			local subtext = C_Spell.GetSpellSubtext(entry.id)
			if type(subtext) == "string" and subtext ~= "" then
				name = name .. " (" .. subtext .. ")"
			end
		end
		row.nameFS:SetText(name)
		setTextColor(row.nameFS, Theme.color.text)
	end

	row.costFS:SetText(C_CurrencyInfo.GetCoinTextureString(entry.cost))
	setTextColor(row.costFS, Theme.color.text)
end

local function createRow()
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_HEIGHT)
	row:EnableMouse(true)

	local levelFS = row:CreateFontString(nil, "OVERLAY")
	levelFS:SetPoint("LEFT", row, "LEFT", 0, 0)
	levelFS:SetWidth(LEVEL_WIDTH)
	levelFS:SetJustifyH("RIGHT")
	row.levelFS = levelFS

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("LEFT", levelFS, "RIGHT", 2, 0)
	row.icon = icon

	local costFS = row:CreateFontString(nil, "OVERLAY")
	costFS:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	costFS:SetJustifyH("RIGHT")
	row.costFS = costFS

	local nameFS = row:CreateFontString(nil, "OVERLAY")
	nameFS:SetJustifyH("LEFT")
	nameFS:SetWordWrap(false)
	row.nameFS = nameFS

	row:SetScript("OnEnter", function()
		if row.spellId ~= nil then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetSpellByID(row.spellId)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return row
end

local function renderRows()
	local _, fontPath = ns.Media:SetFont(title, FONT_KEY, TITLE_SIZE, "")
	ns.Media:SetFont(emptyFS, FONT_KEY, ROW_SIZE, "")

	local rowsVisible = visibleRows()
	local shown = math.max(0, math.min(rowsVisible, #lines - offset))

	for i = 1, shown do
		local line = lines[offset + i]
		local row = rowPool[i]
		if row == nil then
			row = createRow()
			rowPool[i] = row
		end

		row:ClearAllPoints()
		local y = -(HEADER_HEIGHT + PADDING + (i - 1) * ROW_HEIGHT)
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, y)
		row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING, y)

		if row.fontPath ~= fontPath then
			ns.Media:SetFont(row.levelFS, FONT_KEY, ROW_SIZE, "")
			ns.Media:SetFont(row.nameFS, FONT_KEY, ROW_SIZE, "")
			ns.Media:SetFont(row.costFS, FONT_KEY, ROW_SIZE, "")
			row.fontPath = fontPath
		end

		if line.kind == "header" then
			applyHeaderLine(row, line)
		else
			applySpellLine(row, line)
		end

		row:Show()
	end

	for i = shown + 1, #rowPool do
		rowPool[i]:Hide()
	end

	emptyFS:SetShown(#lines == 0)
end

local function refresh()
	if panel == nil then
		return
	end

	local m = ensureModel()
	if m == nil then
		lines = {}
		panel:Hide()
		return
	end

	lines = L.Lines(L.Categorize(m, level or UnitLevel("player"), known))
	offset = L.ClampOffset(offset, #lines, visibleRows())
	renderRows()
end

local function runScheduledRefresh()
	refreshScheduled = false
	if panel ~= nil and panel:IsVisible() then
		refresh()
	end
end

local function scheduleRefresh()
	if refreshScheduled then
		return
	end
	refreshScheduled = true
	C_Timer.After(0, runScheduledRefresh)
end

local function relayout()
	offset = L.ClampOffset(offset, #lines, visibleRows())
	renderRows()
end

local function onMouseWheel(_, delta)
	offset = L.ClampOffset(offset - delta * SCROLL_STEP, #lines, visibleRows())
	renderRows()
end

local function attach()
	book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
	if book == nil then
		attachError = "PlayerSpellsFrame.SpellBookFrame missing"
		return
	end

	panel = CreateFrame("Frame", "MerrinxUISpellTraining", PlayerSpellsFrame)
	panel:SetWidth(WIDTH)
	panel:SetPoint("TOPLEFT", PlayerSpellsFrame, "TOPRIGHT", 2, 0)
	panel:SetPoint("BOTTOMLEFT", PlayerSpellsFrame, "BOTTOMRIGHT", 2, 0)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)

	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(Theme.color.bg[1], Theme.color.bg[2], Theme.color.bg[3], Theme.color.bg[4])

	title = panel:CreateFontString(nil, "OVERLAY")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -PADDING)
	title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING, -PADDING)
	title:SetJustifyH("LEFT")
	ns.Media:SetFont(title, FONT_KEY, TITLE_SIZE, "")
	title:SetText("What's Training")
	setTextColor(title, Theme.color.accent)

	emptyFS = panel:CreateFontString(nil, "OVERLAY")
	emptyFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -(HEADER_HEIGHT + PADDING))
	emptyFS:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING, -(HEADER_HEIGHT + PADDING))
	emptyFS:SetJustifyH("LEFT")
	ns.Media:SetFont(emptyFS, FONT_KEY, ROW_SIZE, "")
	setTextColor(emptyFS, Theme.color.textDim)
	emptyFS:SetText("Nothing left to train")
	emptyFS:Hide()

	panel:SetScript("OnMouseWheel", onMouseWheel)
	panel:SetScript("OnShow", refresh)
	panel:SetScript("OnSizeChanged", relayout)

	book:HookScript("OnShow", function()
		panel:SetShown(true)
	end)
	book:HookScript("OnHide", function()
		panel:SetShown(false)
	end)

	attached = true
	panel:SetShown(book:IsShown())
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		events:UnregisterEvent("PLAYER_LOGIN")
		ensureModel()
	elseif event == "PLAYER_LEVEL_UP" then
		local newLevel = ...
		if type(newLevel) == "number" then
			level = newLevel
		end
		if panel ~= nil and panel:IsVisible() then
			scheduleRefresh()
		end
	elseif event == "SPELLS_CHANGED" then
		if panel ~= nil and panel:IsVisible() then
			scheduleRefresh()
		end
	elseif event == "SPELL_DATA_LOAD_RESULT" then
		local id, success = ...
		if pending[id] then
			pending[id] = nil
			if success == true then
				scheduleRefresh()
			else
				failed[id] = true
			end
		end
	end
end)

if type(EventUtil) == "table" and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
	EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", attach)
end

ns.Debug:RegisterChecks("SpellTraining", function()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function check(name, fn)
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end

				check("EventUtil.ContinueOnAddOnLoaded", type(EventUtil) == "table" and EventUtil.ContinueOnAddOnLoaded)
				check("C_SpellBook.IsSpellKnown", type(C_SpellBook) == "table" and C_SpellBook.IsSpellKnown)
				check("C_SpellBook.IsSpellInSpellBook", type(C_SpellBook) == "table" and C_SpellBook.IsSpellInSpellBook)
				check("C_Spell.GetSpellName", type(C_Spell) == "table" and C_Spell.GetSpellName)
				check("C_Spell.GetSpellSubtext", type(C_Spell) == "table" and C_Spell.GetSpellSubtext)
				check("C_Spell.GetSpellTexture", type(C_Spell) == "table" and C_Spell.GetSpellTexture)
				check("C_Spell.IsSpellDataCached", type(C_Spell) == "table" and C_Spell.IsSpellDataCached)
				check("C_Spell.RequestLoadSpellData", type(C_Spell) == "table" and C_Spell.RequestLoadSpellData)
				check(
					"C_CurrencyInfo.GetCoinTextureString",
					type(C_CurrencyInfo) == "table" and C_CurrencyInfo.GetCoinTextureString
				)
				check("UnitRace", UnitRace)
				check("UnitFactionGroup", UnitFactionGroup)

				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "data",
			run = function()
				local m = ensureModel()
				if m == nil then
					return "FAIL", modelError
				end

				local uncached = 0
				for _, entry in ipairs(m.entries) do
					if C_Spell.IsSpellDataCached(entry.id) == false then
						uncached = uncached + 1
					end
				end

				local failedIds = {}
				for id in pairs(failed) do
					table.insert(failedIds, id)
				end
				table.sort(failedIds)

				local failedCount = #failedIds
				local shown = {}
				for i = 1, math.min(failedCount, 5) do
					shown[i] = failedIds[i]
				end

				local failedText = "failed " .. failedCount
				if #shown > 0 then
					failedText = failedText .. ": " .. table.concat(shown, ", ")
				end

				return "PASS", token, #m.entries, uncached, failedText
			end,
		},
		{
			name = "panel",
			run = function()
				if not attached then
					if attachError ~= nil then
						return "FAIL", attachError
					end
					return "SKIP", "not attached"
				end

				if not book:IsVisible() then
					return "INFO", "book closed"
				end

				return panel:IsVisible() and "PASS" or "FAIL", #lines
			end,
		},
	}
end)
