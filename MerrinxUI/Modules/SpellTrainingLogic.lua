local addonName, ns = ...

local L = {}
ns.SpellTrainingLogic = L

L.CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
L.SOON_LEVELS = 2
L.CATEGORIES = {
	{ key = "available", label = "Available now" },
	{ key = "missing", label = "Missing requirements" },
	{ key = "soon", label = "Next levels" },
	{ key = "later", label = "Later" },
}

local DATA_KEYS = { spellsByLevel = true, overriddenGroups = true }
local ENTRY_KEYS =
	{ id = true, cost = true, requiredIds = true, requiredTalentId = true, faction = true, race = true, skills = true }
local SKILL_ITEM_KEYS = { skill = true, level = true }

local function isInteger(v)
	return type(v) == "number" and v == math.floor(v)
end

local function isPositiveInteger(v)
	return isInteger(v) and v > 0
end

function L.Validate(data, token)
	local function fail(msg)
		return false, token .. ": " .. msg
	end

	if type(data) ~= "table" then
		return fail("data must be a table")
	end

	for k in pairs(data) do
		if not DATA_KEYS[k] then
			return fail("unknown key " .. tostring(k))
		end
	end

	if type(data.spellsByLevel) ~= "table" or next(data.spellsByLevel) == nil then
		return fail("spellsByLevel must be a non-empty table")
	end

	local levels = {}
	for lvl in pairs(data.spellsByLevel) do
		levels[#levels + 1] = lvl
	end
	table.sort(levels)

	local seenIds = {}
	for _, lvl in ipairs(levels) do
		if not isInteger(lvl) or lvl < 1 or lvl > 60 then
			return fail("level " .. tostring(lvl) .. ": must be an integer between 1 and 60")
		end

		local entries = data.spellsByLevel[lvl]
		if type(entries) ~= "table" or #entries == 0 then
			return fail("level " .. lvl .. ": must be a non-empty array")
		end

		for i, entry in ipairs(entries) do
			local function entryFail(msg)
				return fail("level " .. lvl .. " #" .. i .. ": " .. msg)
			end

			if type(entry) ~= "table" then
				return entryFail("must be a table")
			end

			for k in pairs(entry) do
				if not ENTRY_KEYS[k] then
					return entryFail("unknown key " .. tostring(k))
				end
			end

			if not isPositiveInteger(entry.id) then
				return entryFail("id must be a positive integer")
			end

			if not isInteger(entry.cost) or entry.cost < 0 then
				return entryFail("cost must be an integer >= 0")
			end

			if entry.requiredIds ~= nil then
				if type(entry.requiredIds) ~= "table" or #entry.requiredIds == 0 then
					return entryFail("requiredIds must be a non-empty array")
				end
				for _, id in ipairs(entry.requiredIds) do
					if not isPositiveInteger(id) then
						return entryFail("requiredIds entries must be positive integers")
					end
				end
			end

			if entry.requiredTalentId ~= nil and not isPositiveInteger(entry.requiredTalentId) then
				return entryFail("requiredTalentId must be a positive integer")
			end

			if entry.faction ~= nil and entry.faction ~= "Alliance" and entry.faction ~= "Horde" then
				return entryFail("faction must be Alliance or Horde")
			end

			if entry.race ~= nil and not isPositiveInteger(entry.race) then
				return entryFail("race must be a positive integer")
			end

			if entry.skills ~= nil then
				if type(entry.skills) ~= "table" or #entry.skills == 0 then
					return entryFail("skills must be a non-empty array")
				end
				for _, item in ipairs(entry.skills) do
					local skillsOk = type(item) == "table"
					if skillsOk then
						for k in pairs(item) do
							if not SKILL_ITEM_KEYS[k] then
								skillsOk = false
								break
							end
						end
					end
					if skillsOk then
						skillsOk = isPositiveInteger(item.skill) and isInteger(item.level) and item.level >= 0
					end
					if not skillsOk then
						return entryFail("skills entries must have exactly skill and level")
					end
				end
			end

			if seenIds[entry.id] then
				return entryFail("duplicate id " .. entry.id)
			end
			seenIds[entry.id] = true
		end
	end

	if data.overriddenGroups ~= nil then
		if type(data.overriddenGroups) ~= "table" or #data.overriddenGroups == 0 then
			return fail("overriddenGroups must be a non-empty array")
		end

		local seenGroupIds = {}
		for g, group in ipairs(data.overriddenGroups) do
			if type(group) ~= "table" or #group == 0 then
				return fail("group " .. g .. ": must be a non-empty array")
			end
			for _, id in ipairs(group) do
				if not isPositiveInteger(id) then
					return fail("group " .. g .. ": entries must be positive integers")
				end
				if seenGroupIds[id] then
					return fail("group " .. g .. ": id " .. id .. " in more than one group")
				end
				seenGroupIds[id] = true
			end
		end
	end

	return true
end

function L.Build(data, faction, race)
	local entries = {}
	for lvl, levelEntries in pairs(data.spellsByLevel) do
		for _, e in ipairs(levelEntries) do
			if (e.faction == nil or e.faction == faction) and (e.race == nil or e.race == race) then
				entries[#entries + 1] = {
					id = e.id,
					level = lvl,
					cost = e.cost,
					requiredIds = e.requiredIds,
					requiredTalentId = e.requiredTalentId,
				}
			end
		end
	end

	table.sort(entries, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.id < b.id
	end)

	local chains = {}
	if data.overriddenGroups then
		for _, group in ipairs(data.overriddenGroups) do
			for _, id in ipairs(group) do
				chains[id] = group
			end
		end
	end

	return { entries = entries, chains = chains }
end

function L.IsKnown(model, id, known)
	if known(id) == true then
		return true
	end

	local chain = model.chains[id]
	if not chain then
		return false
	end

	local index
	for i, chainId in ipairs(chain) do
		if chainId == id then
			index = i
			break
		end
	end
	if not index then
		return false
	end

	for i = index, #chain do
		if known(chain[i]) == true then
			return true
		end
	end

	return false
end

function L.Categorize(model, level, known)
	local byKey = {}
	for _, cat in ipairs(L.CATEGORIES) do
		byKey[cat.key] = { key = cat.key, label = cat.label, count = 0, total = 0, entries = {} }
	end

	for _, e in ipairs(model.entries) do
		if not L.IsKnown(model, e.id, known) then
			local hiddenByTalent = e.requiredTalentId ~= nil and not L.IsKnown(model, e.requiredTalentId, known)
			if not hiddenByTalent then
				local key
				if e.level > level then
					key = (e.level <= level + L.SOON_LEVELS) and "soon" or "later"
				else
					local allRequired = true
					if e.requiredIds then
						for _, id in ipairs(e.requiredIds) do
							if not L.IsKnown(model, id, known) then
								allRequired = false
								break
							end
						end
					end
					key = allRequired and "available" or "missing"
				end

				local group = byKey[key]
				group.count = group.count + 1
				group.total = group.total + e.cost
				group.entries[#group.entries + 1] = e
			end
		end
	end

	local groups = {}
	for _, cat in ipairs(L.CATEGORIES) do
		local group = byKey[cat.key]
		if group.count > 0 then
			groups[#groups + 1] = group
		end
	end
	return groups
end

function L.Lines(groups)
	local lines = {}
	for _, group in ipairs(groups) do
		lines[#lines + 1] =
			{ kind = "header", key = group.key, label = group.label, count = group.count, total = group.total }
		for _, entry in ipairs(group.entries) do
			lines[#lines + 1] = { kind = "spell", key = group.key, entry = entry }
		end
	end
	return lines
end

function L.ClampOffset(offset, count, rows)
	return math.max(0, math.min(offset, count - rows))
end
