local addonName, ns = ...

local EnemyCooldownLogic = {}
ns.EnemyCooldownLogic = EnemyCooldownLogic

local L = EnemyCooldownLogic

L.CATEGORIES = { interrupt = true, defensive = true, cc = true, racial = true }

-- D-18 curated table; every ID and cooldown UNVERIFIED pending the S11 probe paste.
-- Shaman's Nature's Swiftness (16188) is kept; the druid's (17116) is left out (R-16: same name).
L.SPELLS = {
	{ id = 6552, class = "WARRIOR", category = "interrupt", cd = 10 },
	{ id = 72, class = "WARRIOR", category = "interrupt", cd = 12 },
	{ id = 5246, class = "WARRIOR", category = "cc", cd = 180 },
	{ id = 18499, class = "WARRIOR", category = "defensive", cd = 30 },
	{ id = 1766, class = "ROGUE", category = "interrupt", cd = 10 },
	{ id = 408, class = "ROGUE", category = "cc", cd = 20 },
	{ id = 2094, class = "ROGUE", category = "cc", cd = 300 },
	{ id = 1856, class = "ROGUE", category = "defensive", cd = 300 },
	{ id = 5277, class = "ROGUE", category = "defensive", cd = 300 },
	{ id = 2139, class = "MAGE", category = "interrupt", cd = 30 },
	{ id = 1953, class = "MAGE", category = "defensive", cd = 15 },
	{ id = 11958, class = "MAGE", category = "defensive", cd = 300 },
	{ id = 122, class = "MAGE", category = "cc", cd = 25 },
	{ id = 8122, class = "PRIEST", category = "cc", cd = 30 },
	{ id = 15487, class = "PRIEST", category = "interrupt", cd = 45 },
	{ id = 6346, class = "PRIEST", category = "defensive", cd = 30 },
	{ id = 853, class = "PALADIN", category = "cc", cd = 60 },
	{ id = 642, class = "PALADIN", category = "defensive", cd = 300 },
	{ id = 1022, class = "PALADIN", category = "defensive", cd = 300 },
	{ id = 633, class = "PALADIN", category = "defensive", cd = 3600 },
	{ id = 6789, class = "WARLOCK", category = "cc", cd = 120 },
	{ id = 5484, class = "WARLOCK", category = "cc", cd = 40 },
	{ id = 8042, class = "SHAMAN", category = "interrupt", cd = 6 },
	{ id = 8177, class = "SHAMAN", category = "defensive", cd = 15 },
	{ id = 16188, class = "SHAMAN", category = "defensive", cd = 180 },
	{ id = 19503, class = "HUNTER", category = "cc", cd = 30 },
	{ id = 1499, class = "HUNTER", category = "cc", cd = 15 },
	{ id = 19263, class = "HUNTER", category = "defensive", cd = 300 },
	{ id = 5384, class = "HUNTER", category = "defensive", cd = 30 },
	{ id = 5211, class = "DRUID", category = "cc", cd = 60 },
	{ id = 16979, class = "DRUID", category = "interrupt", cd = 15 },
	{ id = 22812, class = "DRUID", category = "defensive", cd = 60 },
	{ id = 29166, class = "DRUID", category = "defensive", cd = 360 },
	{ id = 7744, class = "ANY", category = "racial", cd = 120 },
	{ id = 20589, class = "ANY", category = "racial", cd = 60 },
	{ id = 20594, class = "ANY", category = "racial", cd = 180 },
	{ id = 20549, class = "ANY", category = "racial", cd = 120 },
	{ id = 20554, class = "ANY", category = "racial", cd = 180 },
	{ id = 5579, class = "ANY", category = "racial", cd = 300 },
	{ id = 23273, class = "ANY", category = "racial", cd = 300 },
	{ id = 23274, class = "ANY", category = "racial", cd = 300 },
	{ id = 23276, class = "ANY", category = "racial", cd = 300 },
	{ id = 23277, class = "ANY", category = "racial", cd = 300 },
}

function L.BuildIndex(spells, getName)
	local index = { byId = {}, byName = {} }
	for _, entry in ipairs(spells) do
		index.byId[entry.id] = entry
		local name = getName(entry.id)
		if type(name) == "string" and index.byName[name] == nil then
			index.byName[name] = entry
		end
	end
	return index
end

function L.Lookup(index, spellID, name)
	return index.byId[spellID] or (name ~= nil and index.byName[name]) or nil
end

function L.Record(state, key, entry, now)
	local bucket = state[key]
	if not bucket then
		bucket = {}
		state[key] = bucket
	end
	bucket[entry.id] = { entry = entry, start = now, expires = now + entry.cd }
end

function L.Prune(state, now)
	local changed = {}
	for key, bucket in pairs(state) do
		local removed = false
		for id, rec in pairs(bucket) do
			if rec.expires <= now then
				bucket[id] = nil
				removed = true
			end
		end
		if removed then
			changed[key] = true
			if next(bucket) == nil then
				state[key] = nil
			end
		end
	end
	return changed
end

function L.Active(state, key, now, maxIcons)
	if maxIcons < 1 then
		return {}
	end

	local bucket = state[key]
	if not bucket then
		return {}
	end

	local list = {}
	for _, rec in pairs(bucket) do
		if rec.expires > now then
			list[#list + 1] = rec
		end
	end

	table.sort(list, function(a, b)
		if a.expires ~= b.expires then
			return a.expires < b.expires
		end
		return a.entry.id < b.entry.id
	end)

	local result = {}
	for i = 1, math.min(maxIcons, #list) do
		result[i] = list[i]
	end
	return result
end

function L.Layout(anchor, i, n, size, spacing, ox, oy)
	local step = size + spacing
	if anchor == "BOTTOM" then
		return "TOP", "BOTTOM", (i - 1) * step - ((n - 1) * step) / 2 + ox, oy
	elseif anchor == "RIGHT" then
		return "LEFT", "RIGHT", (i - 1) * step + ox, oy
	elseif anchor == "LEFT" then
		return "RIGHT", "LEFT", -(i - 1) * step + ox, oy
	else
		return "BOTTOM", "TOP", (i - 1) * step - ((n - 1) * step) / 2 + ox, oy
	end
end
