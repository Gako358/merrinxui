local addonName, ns = ...

local EnemyCooldownLogic = {}
ns.EnemyCooldownLogic = EnemyCooldownLogic

local L = EnemyCooldownLogic

L.SPELLS = {
	{ id = 5246, class = "WARRIOR", cd = 180 },
	{ id = 12809, class = "WARRIOR", cd = 45 },
	{ id = 20252, class = "WARRIOR", cd = 30 },
	{ id = 408, class = "ROGUE", cd = 20 },
	{ id = 1776, class = "ROGUE", cd = 10 },
	{ id = 2094, class = "ROGUE", cd = 300 },
	{ id = 122, class = "MAGE", cd = 25 },
	{ id = 8122, class = "PRIEST", cd = 30 },
	{ id = 15487, class = "PRIEST", cd = 45 },
	{ id = 853, class = "PALADIN", cd = 60 },
	{ id = 20066, class = "PALADIN", cd = 60 },
	{ id = 6789, class = "WARLOCK", cd = 120 },
	{ id = 5484, class = "WARLOCK", cd = 40 },
	{ id = 19503, class = "HUNTER", cd = 30 },
	{ id = 1499, class = "HUNTER", cd = 15 },
	{ id = 19386, class = "HUNTER", cd = 120 },
	{ id = 19577, class = "HUNTER", cd = 60 },
	{ id = 5211, class = "DRUID", cd = 60 },
	{ id = 16979, class = "DRUID", cd = 15 },
	{ id = 20549, class = "ANY", cd = 120 },
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

function L.Active(state, key, now, maxIcons, selected)
	if maxIcons < 1 then
		return {}
	end

	local bucket = state[key]
	if not bucket then
		return {}
	end

	local list = {}
	for _, rec in pairs(bucket) do
		if rec.expires > now and (selected == nil or selected[rec.entry.id] == true) then
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

local CLASS_LABELS = {
	DRUID = "Druid",
	HUNTER = "Hunter",
	MAGE = "Mage",
	PALADIN = "Paladin",
	PRIEST = "Priest",
	ROGUE = "Rogue",
	SHAMAN = "Shaman",
	WARLOCK = "Warlock",
	WARRIOR = "Warrior",
	ANY = "Racial",
}

function L.ClassLabel(class)
	return CLASS_LABELS[class]
end

function L.IdentityKey(guid, name, realm, unit, isSecret)
	if not isSecret(guid) and type(guid) == "string" and guid ~= "" then
		return "guid:" .. guid, "guid"
	end

	if not isSecret(name) and type(name) == "string" and name ~= "" then
		local key = "name:" .. name
		if not isSecret(realm) and type(realm) == "string" and realm ~= "" then
			key = key .. "-" .. realm
		end
		return key, "name"
	end

	return "unit:" .. unit, "unit"
end

function L.IconOffset(i, size, spacing, gap)
	return gap + (i - 1) * (size + spacing)
end

function L.RowWidth(n, size, spacing, gap)
	if n <= 0 then
		return 0
	end
	return gap + n * size + (n - 1) * spacing
end

function L.Audit(spells, getName, getBaseCooldownMs)
	local unresolved = {}
	local duplicates = {}
	local mismatched = {}
	local unknownCd = {}
	local seenNames = {}

	for _, entry in ipairs(spells) do
		local name = getName(entry.id)
		if name == nil then
			table.insert(unresolved, entry.id)
		elseif seenNames[name] then
			table.insert(duplicates, entry.id)
		else
			seenNames[name] = true
		end

		local actual = getBaseCooldownMs(entry.id)
		if actual == nil then
			table.insert(unknownCd, entry.id)
		else
			local expected = entry.cd * 1000
			if actual ~= expected then
				table.insert(mismatched, { id = entry.id, expected = expected, actual = actual })
			end
		end
	end

	return { unresolved = unresolved, duplicates = duplicates, mismatched = mismatched, unknownCd = unknownCd }
end
