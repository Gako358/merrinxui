local addonName, ns = ...

local EnemySpotterLogic = {}
ns.EnemySpotterLogic = EnemySpotterLogic

local L = EnemySpotterLogic

function L.DisplayName(name)
	if type(name) ~= "string" then
		return nil
	end
	local base = name:match("^%s*([^%-]*)"):match("^(.-)%s*$")
	if base == "" or base:find("%s") then
		return nil
	end
	return base:sub(1, 1):upper() .. base:sub(2):lower()
end

function L.Key(name)
	local display = L.DisplayName(name)
	return display and display:lower()
end

function L.Add(list, name, now)
	local key = L.Key(name)
	if key == nil then
		return nil, false
	end
	if list[key] then
		return key, false
	end
	list[key] = { name = L.DisplayName(name), added = now }
	return key, true
end

function L.Remove(list, name)
	local key = L.Key(name)
	if key == nil or list[key] == nil then
		return false
	end
	list[key] = nil
	return true
end

function L.Find(list, name)
	local key = L.Key(name)
	return key and list[key]
end

function L.Sorted(list)
	local result = {}
	for key, entry in pairs(list) do
		result[#result + 1] = { key = key, entry = entry }
	end
	table.sort(result, function(a, b)
		return a.key < b.key
	end)
	return result
end

function L.Spot(nearby, info, now, expire)
	local key = L.Key(info.name)
	if key == nil then
		return nil, false
	end

	local entry = nearby[key]
	local isNew = entry == nil or now - entry.lastSeen > expire
	if isNew then
		entry = { name = L.DisplayName(info.name), firstSeen = now }
		nearby[key] = entry
	end
	entry.lastSeen = now
	for field, value in pairs(info) do
		if field ~= "name" then
			entry[field] = value
		end
	end
	return entry, isNew, key
end

function L.Prune(nearby, now, expire)
	local removed = 0
	for key, entry in pairs(nearby) do
		if now - entry.lastSeen > expire then
			nearby[key] = nil
			removed = removed + 1
		end
	end
	return removed
end

function L.Rows(nearby, isKos)
	local rows = {}
	for key, entry in pairs(nearby) do
		rows[#rows + 1] = { key = key, entry = entry, kos = isKos(key) == true }
	end
	table.sort(rows, function(a, b)
		if a.kos ~= b.kos then
			return a.kos
		end
		if a.entry.lastSeen ~= b.entry.lastSeen then
			return a.entry.lastSeen > b.entry.lastSeen
		end
		return a.key < b.key
	end)
	return rows
end

function L.Ago(seconds)
	if type(seconds) ~= "number" or seconds < 5 then
		return "now"
	elseif seconds < 60 then
		return string.format("%ds", seconds)
	elseif seconds < 3600 then
		return string.format("%dm", seconds / 60)
	elseif seconds < 86400 then
		return string.format("%dh", seconds / 3600)
	end
	return string.format("%dd", seconds / 86400)
end

function L.LevelText(level)
	if type(level) ~= "number" then
		return ""
	elseif level < 0 then
		return "??"
	elseif level == 0 then
		return ""
	end
	return tostring(level)
end

function L.Detail(level, className)
	local parts = {}
	local levelText = L.LevelText(level)
	if levelText ~= "" then
		parts[#parts + 1] = levelText
	end
	if type(className) == "string" and className ~= "" then
		parts[#parts + 1] = className
	end
	return table.concat(parts, " ")
end

function L.ClampOffset(offset, count, rows)
	return math.max(0, math.min(offset, count - rows))
end
