local addonName, ns = ...

local ActionBarLogic = {}
ns.ActionBarLogic = ActionBarLogic

local L = ActionBarLogic

L.PAGES = { 1, 6, 5, 3, 4, 13, 14, 15 }
L.PET_BAR = 9
L.BAR_COUNT = 9

function L.ButtonCount(bar)
	if bar == L.PET_BAR then
		return 10
	end
	return 12
end

function L.Slot(page, i)
	return (page - 1) * 12 + i
end

local PAGING_MIDDLE = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
local PAGING_DEFAULT_BONUS = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "
local PAGING_TAIL = "[bonusbar:5] 11; 1"

local FORM_PAGES = { [768] = 7, [5487] = 9, [9634] = 9, [24858] = 10 }

function L.FormPage(spellID, stealthed)
	local page = FORM_PAGES[spellID]
	if page == nil then
		return nil
	end
	if spellID == 768 and stealthed then
		return 8
	end
	return page
end

function L.FormClauses(classFile, spellIDs)
	if classFile ~= "DRUID" or type(spellIDs) ~= "table" then
		return nil
	end

	local clauses
	for i = 1, #spellIDs do
		local page = L.FormPage(spellIDs[i], false)
		if page ~= nil then
			clauses = clauses or ""
			local stealthPage = L.FormPage(spellIDs[i], true)
			if stealthPage ~= page then
				clauses = clauses .. string.format("[form:%d,stealth] %d; ", i, stealthPage)
			end
			clauses = clauses .. string.format("[form:%d] %d; ", i, page)
		end
	end
	return clauses
end

function L.PagingDriver(o, v, t, formClauses)
	local prefix = ""
	if o ~= nil and v ~= nil and t ~= nil then
		prefix = string.format("[overridebar] %d; [vehicleui] %d; [possessbar] %d; [shapeshift] %d; ", o, v, v, t)
	end
	return prefix .. PAGING_MIDDLE .. (formClauses or "") .. PAGING_DEFAULT_BONUS .. PAGING_TAIL
end

local function clampPerRow(perRow, n)
	if perRow < 1 then
		return 1
	elseif perRow > n then
		return n
	end
	return perRow
end

function L.Layout(n, perRow, size, spacing)
	perRow = clampPerRow(perRow, n)
	local rows = math.ceil(n / perRow)
	local step = size + spacing

	local positions = {}
	for i = 1, n do
		positions[i] = {
			x = ((i - 1) % perRow) * step,
			y = -math.floor((i - 1) / perRow) * step,
		}
	end

	local width = perRow * size + (perRow - 1) * spacing
	local height = rows * size + (rows - 1) * spacing
	return positions, width, height
end

function L.BarGeometry(n, perRow, size, spacing, native)
	local scale = size / native
	local positions = L.Layout(n, perRow, native, spacing * native / size)
	local _, width, height = L.Layout(n, perRow, size, spacing)
	return scale, positions, width, height
end

function L.DefaultPosition(b)
	return { point = "CENTER", x = 0, y = -300 + (b - 1) * 40 }
end

function L.ExpectedPage(barPage, offset, formPage)
	if barPage > 1 then
		return barPage
	elseif formPage ~= nil then
		return formPage
	elseif offset > 0 then
		return 6 + offset
	end
	return 1
end

function L.BindingPrefix(bar)
	if bar == 1 then
		return "ACTIONBUTTON"
	elseif bar >= 2 and bar <= 8 then
		return "MULTIACTIONBAR" .. (bar - 1) .. "BUTTON"
	elseif bar == L.PET_BAR then
		return "BONUSACTIONBUTTON"
	end
	return nil
end

function L.VisibilityDriver(b, hideInCombat)
	if b == L.PET_BAR then
		if hideInCombat then
			return "[overridebar][vehicleui][petbattle] hide; [combat] hide; [pet] show; hide"
		end
		return "[overridebar][vehicleui][petbattle] hide; [pet] show; hide"
	end
	if b == 1 then
		if hideInCombat then
			return "[overridebar][vehicleui][petbattle] hide; [combat] hide; show"
		end
		return "[overridebar][vehicleui][petbattle] hide; show"
	end
	if hideInCombat then
		return "[combat] hide; show"
	end
	return "show"
end

function L.BarAlpha(opacity, mouseover, hovered, unlocked)
	if mouseover and not hovered and not unlocked then
		return 0
	end
	return opacity / 100
end
