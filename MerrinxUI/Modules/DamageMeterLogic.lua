local addonName, ns = ...

local DamageMeterLogic = {}
ns.DamageMeterLogic = DamageMeterLogic

local L = DamageMeterLogic

local METRIC = { DamageDone = "Damage Done", HealingDone = "Healing Done" }

function L.Title(session, metric)
	return (METRIC[metric] or metric) .. " - " .. session
end

function L.VisibleRows(count, rows)
	return math.max(0, math.min(count, rows))
end

function L.WindowHeight(rows, rowHeight, spacing, headerHeight)
	return headerHeight + rows * rowHeight + math.max(rows - 1, 0) * spacing
end

function L.EnumKey(tbl, key)
	if type(tbl) == "table" and type(key) == "string" then
		return tbl[key]
	end
	return nil
end

function L.IconCoords(coords, zoom)
	if coords == nil then
		return nil
	end
	local l, r, t, b = coords[1], coords[2], coords[3], coords[4]
	return l + (r - l) * zoom, r - (r - l) * zoom, t + (b - t) * zoom, b - (b - t) * zoom
end

function L.ShortName(name)
	if type(name) ~= "string" then
		return nil
	end
	return name:match("^[^-]+")
end

function L.Toggle(value, a, b)
	if value == a then
		return b
	end
	return a
end
