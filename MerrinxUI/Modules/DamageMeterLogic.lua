local addonName, ns = ...

local DamageMeterLogic = {}
ns.DamageMeterLogic = DamageMeterLogic

local L = DamageMeterLogic

local TYPE_LABELS = {
	DamageDone = "Damage Done",
	Dps = "DPS",
	HealingDone = "Healing Done",
	Hps = "HPS",
	Absorbs = "Absorbs",
	Interrupts = "Interrupts",
	Dispels = "Dispels",
	DamageTaken = "Damage Taken",
	AvoidableDamageTaken = "Avoidable Damage Taken",
	Deaths = "Deaths",
	EnemyDamageTaken = "Enemy Damage Taken",
}

local RATE_TYPES = { Dps = true, Hps = true }
local COUNT_TYPES = { Interrupts = true, Dispels = true }

local MENU_GROUPS = {
	{ label = "Damage", keys = { "DamageDone", "Dps", "DamageTaken", "AvoidableDamageTaken", "EnemyDamageTaken" } },
	{ label = "Healing", keys = { "HealingDone", "Hps", "Absorbs" } },
	{ label = "Actions", keys = { "Interrupts", "Dispels", "Deaths" } },
}

local function formatDuration(seconds)
	seconds = math.floor(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", minutes, secs)
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

function L.TypeLabel(key)
	if key == nil then
		return "None"
	end
	local known = TYPE_LABELS[key]
	if known then
		return known
	end
	return (key:gsub("(%l)(%u)", "%1 %2"))
end

function L.Title(sessionLabel, typeKey)
	return L.TypeLabel(typeKey) .. " - " .. sessionLabel
end

function L.TypeList(enum)
	if type(enum) ~= "table" then
		return {}
	end

	local keys = {}
	for k, v in pairs(enum) do
		if type(k) == "string" and type(v) == "number" then
			table.insert(keys, k)
		end
	end
	table.sort(keys, function(a, b)
		return enum[a] < enum[b]
	end)
	return keys
end

function L.TypeKind(key)
	if RATE_TYPES[key] then
		return "rate"
	end
	if COUNT_TYPES[key] then
		return "count"
	end
	if key == "Deaths" then
		return "deaths"
	end
	return "amount"
end

function L.BarField(kind)
	if kind == "rate" then
		return "amountPerSecond"
	end
	return "totalAmount"
end

function L.MenuGroups(list)
	list = list or {}

	local present = {}
	for _, key in ipairs(list) do
		present[key] = true
	end

	local groups = {}
	local grouped = {}
	for _, group in ipairs(MENU_GROUPS) do
		local keys = {}
		for _, key in ipairs(group.keys) do
			if present[key] then
				table.insert(keys, key)
				grouped[key] = true
			end
		end
		if #keys > 0 then
			table.insert(groups, { label = group.label, keys = keys })
		end
	end

	local other = {}
	for _, key in ipairs(list) do
		if not grouped[key] then
			table.insert(other, key)
		end
	end
	if #other > 0 then
		table.insert(groups, { label = "Other", keys = other })
	end

	return groups
end

function L.ResolveType(list, key, fallback)
	list = list or {}

	local present = {}
	for _, k in ipairs(list) do
		present[k] = true
	end

	if present[key] then
		return key
	end
	if present[fallback] then
		return fallback
	end
	return list[1]
end

function L.ValueText(kind, total, perSec, fmt)
	if kind == "rate" then
		return fmt(perSec)
	end
	if kind == "count" then
		return fmt(total)
	end
	if kind == "deaths" then
		return ""
	end
	return string.format("%s (%s)", fmt(total), fmt(perSec))
end

function L.SegmentLabel(name, seconds)
	local label = (type(name) == "string" and name ~= "") and name or "Combat"
	if type(seconds) == "number" then
		label = label .. " (" .. formatDuration(seconds) .. ")"
	end
	return label
end

function L.Segments(list, max)
	list = list or {}

	local filtered = {}
	for _, entry in ipairs(list) do
		if type(entry) == "table" and type(entry.sessionID) == "number" then
			table.insert(filtered, entry)
		end
	end
	table.sort(filtered, function(a, b)
		return a.sessionID > b.sessionID
	end)

	local result = {}
	for i = 1, math.min(max, #filtered) do
		local entry = filtered[i]
		table.insert(result, { sessionID = entry.sessionID, label = L.SegmentLabel(entry.name, entry.durationSeconds) })
	end
	return result
end
