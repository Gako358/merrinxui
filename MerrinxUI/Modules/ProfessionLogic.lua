local addonName, ns = ...

local L = {}
ns.ProfessionLogic = L

L.ORDER = { 171, 164, 333, 202, 165, 197, 185, 129, 356, 182, 186, 393 }

L.TIERS = {
	{ name = "Apprentice", skill = 0, level = 5, cap = 75 },
	{ name = "Journeyman", skill = 50, level = 10, cap = 150 },
	{ name = "Expert", skill = 125, level = 20, cap = 225 },
	{ name = "Artisan", skill = 200, level = 35, cap = 300 },
}

local TOP_KEYS = {
	name = true,
	skillLine = true,
	kind = true,
	source = true,
	routeEnd = true,
	train = true,
	steps = true,
}
local STEP_KEYS = {
	from = true,
	to = true,
	name = true,
	count = true,
	mats = true,
	zones = true,
	alt = true,
	note = true,
}
local TRAIN_ENTRY_KEYS = { how = true, text = true, skill = true, level = true }

local function isInteger(v)
	return type(v) == "number" and v == math.floor(v)
end

local function isPositiveInteger(v)
	return isInteger(v) and v > 0
end

local function isNonEmptyString(v)
	return type(v) == "string" and v ~= ""
end

local function isInOrder(skillLine)
	for _, id in ipairs(L.ORDER) do
		if id == skillLine then
			return true
		end
	end
	return false
end

function L.Tiers(data)
	local tiers = {}
	for i, tier in ipairs(L.TIERS) do
		tiers[i] = {
			index = i,
			name = tier.name,
			skill = tier.skill,
			level = tier.level,
			cap = tier.cap,
			how = "trainer",
			text = nil,
		}
	end

	if data and data.kind == "gather" then
		tiers[1].level = 1
	end

	if data and data.train then
		for i, override in pairs(data.train) do
			local tier = tiers[i]
			if tier then
				if override.how ~= nil then
					tier.how = override.how
				end
				if override.text ~= nil then
					tier.text = override.text
				end
				if override.skill ~= nil then
					tier.skill = override.skill
				end
				if override.level ~= nil then
					tier.level = override.level
				end
			end
		end
	end

	return tiers
end

function L.TierIndex(tiers, maxRank)
	local index = 0
	for i, tier in ipairs(tiers) do
		if tier.cap <= maxRank then
			index = i
		end
	end
	return index
end

function L.NextTraining(tiers, rank, maxRank, level)
	local index = L.TierIndex(tiers, maxRank)
	if index >= #tiers then
		return nil
	end

	local tier = tiers[index + 1]
	local t = {}
	for k, v in pairs(tier) do
		t[k] = v
	end

	t.skillOk = rank >= tier.skill
	t.levelOk = level >= tier.level
	t.capped = maxRank > 0 and rank >= maxRank

	if not t.skillOk then
		t.state = "needSkill"
	elseif not t.levelOk then
		t.state = "needLevel"
	elseif tier.index == 1 then
		t.state = "learn"
	else
		t.state = "train"
	end

	return t
end

function L.TrainingText(t)
	if t == nil then
		return "All ranks trained"
	end

	if t.state == "needSkill" then
		return t.name .. " at skill " .. t.skill
	elseif t.state == "needLevel" then
		return t.name .. " at level " .. t.level
	end

	local detail = t.text and (t.how == "trainer" and t.text or t.how .. " " .. t.text) or t.how
	local verb = t.state == "learn" and "Learn" or "Train"
	local result = verb .. " " .. t.name .. ": " .. detail
	if t.capped then
		result = result .. " - capped"
	end
	return result
end

function L.CurrentStep(steps, rank)
	for i, step in ipairs(steps) do
		if rank < step.to then
			return i
		end
	end
	return nil
end

function L.FormatStep(step)
	local s = step.from .. "-" .. step.to .. " " .. step.name
	if step.count then
		s = s .. " x" .. step.count
	end
	return s
end

function L.Lines(step)
	local lines = {}

	if step.mats then
		local parts = {}
		for _, m in ipairs(step.mats) do
			parts[#parts + 1] = m.count .. " " .. m.name
		end
		lines[#lines + 1] = "Mats: " .. table.concat(parts, ", ")
	end

	if step.zones then
		lines[#lines + 1] = "Zones: " .. table.concat(step.zones, ", ")
	end

	if step.alt then
		lines[#lines + 1] = "Alt: " .. step.alt
	end

	if step.note then
		lines[#lines + 1] = step.note
	end

	return lines
end

function L.Validate(data)
	local name = (type(data) == "table" and isNonEmptyString(data.name)) and data.name or "?"

	local function fail(msg)
		return false, name .. ": " .. msg
	end

	local function stepFail(i, msg)
		return false, name .. " step " .. i .. ": " .. msg
	end

	if type(data) ~= "table" then
		return fail("must be a table")
	end

	for k in pairs(data) do
		if not TOP_KEYS[k] then
			return fail("unknown key " .. tostring(k))
		end
	end

	if not isNonEmptyString(data.name) then
		return fail("name must be a non-empty string")
	end

	if not isInOrder(data.skillLine) then
		return fail("skillLine must be one of ORDER")
	end

	if data.kind ~= "craft" and data.kind ~= "gather" and data.kind ~= "secondary" then
		return fail("kind must be craft, gather or secondary")
	end

	if data.source ~= nil and type(data.source) ~= "string" then
		return fail("source must be a string")
	end

	if not isInteger(data.routeEnd) or data.routeEnd < 2 or data.routeEnd > 300 then
		return fail("routeEnd must be an integer between 2 and 300")
	end

	if type(data.steps) ~= "table" or #data.steps == 0 then
		return fail("steps must be a non-empty list")
	end

	local prevTo = nil
	for i, step in ipairs(data.steps) do
		if type(step) ~= "table" then
			return stepFail(i, "must be a table")
		end

		for k in pairs(step) do
			if not STEP_KEYS[k] then
				return stepFail(i, "unknown key " .. tostring(k))
			end
		end

		if i == 1 and step.from ~= 1 then
			return stepFail(i, "from must be 1")
		end

		if not isInteger(step.from) or not isInteger(step.to) or step.from >= step.to then
			return stepFail(i, "from/to must be integers with from < to")
		end

		if prevTo ~= nil and step.from ~= prevTo then
			return stepFail(i, "from must continue from the previous step's to")
		end

		if not isNonEmptyString(step.name) then
			return stepFail(i, "name must be a non-empty string")
		end

		if step.count ~= nil and not isPositiveInteger(step.count) then
			return stepFail(i, "count must be a positive integer")
		end

		if step.mats ~= nil then
			if type(step.mats) ~= "table" then
				return stepFail(i, "mats must be a list")
			end
			for _, m in ipairs(step.mats) do
				if type(m) ~= "table" or not isNonEmptyString(m.name) or not isPositiveInteger(m.count) then
					return stepFail(i, "mats entries need a name and a positive count")
				end
			end
		end

		if step.zones ~= nil then
			if type(step.zones) ~= "table" then
				return stepFail(i, "zones must be a list")
			end
			for _, z in ipairs(step.zones) do
				if type(z) ~= "string" then
					return stepFail(i, "zones entries must be strings")
				end
			end
		end

		if step.alt ~= nil and type(step.alt) ~= "string" then
			return stepFail(i, "alt must be a string")
		end

		if step.note ~= nil and type(step.note) ~= "string" then
			return stepFail(i, "note must be a string")
		end

		prevTo = step.to
	end

	if data.steps[#data.steps].to ~= data.routeEnd then
		return fail("the last step must end at routeEnd")
	end

	if data.train ~= nil then
		if type(data.train) ~= "table" then
			return fail("train must be a table")
		end
		for k, entry in pairs(data.train) do
			if k ~= 1 and k ~= 2 and k ~= 3 and k ~= 4 then
				return fail("unknown key " .. tostring(k))
			end
			if type(entry) ~= "table" then
				return fail("train entries must be tables")
			end
			for ek in pairs(entry) do
				if not TRAIN_ENTRY_KEYS[ek] then
					return fail("unknown key " .. tostring(ek))
				end
			end
			if entry.how ~= "trainer" and entry.how ~= "book" and entry.how ~= "quest" then
				return fail("train how must be trainer, book or quest")
			end
			if entry.text ~= nil and type(entry.text) ~= "string" then
				return fail("train text must be a string")
			end
			if entry.skill ~= nil and not isInteger(entry.skill) then
				return fail("train skill must be an integer")
			end
			if entry.level ~= nil and not isInteger(entry.level) then
				return fail("train level must be an integer")
			end
		end
	end

	return true
end
