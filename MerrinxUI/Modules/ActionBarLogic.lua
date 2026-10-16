local addonName, ns = ...

local ActionBarLogic = {}
ns.ActionBarLogic = ActionBarLogic

local L = ActionBarLogic

L.PAGES = { 1, 6, 5, 3, 4, 13, 14, 15 }

function L.Slot(page, i)
	return (page - 1) * 12 + i
end

local PAGING_TAIL = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
	.. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1"

function L.PagingDriver(o, v, t)
	if o ~= nil and v ~= nil and t ~= nil then
		return string.format("[overridebar] %d; [vehicleui] %d; [possessbar] %d; [shapeshift] %d; ", o, v, v, t)
			.. PAGING_TAIL
	end
	return PAGING_TAIL
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

function L.ExpectedPage(barPage, offset)
	if barPage > 1 then
		return barPage
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
	end
	return nil
end

function L.VisibilityDriver(b, hideInCombat)
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
