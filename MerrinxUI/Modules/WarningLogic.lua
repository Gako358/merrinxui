local addonName, ns = ...

local WarningLogic = {}
ns.WarningLogic = WarningLogic

local L = WarningLogic

L.RANGED_SLOT = 18
L.AMMO_SLOT = 0
L.WEAPON = 2
L.PROJECTILE = 6
L.ARROW = 2
L.BULLET = 3
L.BOW = 2
L.GUN = 3
L.CROSSBOW = 18

L.CONJURED_FOOD = { 5349, 1113, 1114, 1487, 8075, 8076 }
L.CONJURED_WATER = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 }

L.WARNINGS = {
	HUNTER = {
		{
			key = "arrows",
			name = "Arrows",
			kind = "ammo",
			rested = true,
			threshold = 200,
			max = 4000,
			ammo = L.ARROW,
			weapons = { [L.BOW] = true, [L.CROSSBOW] = true },
		},
		{
			key = "bullets",
			name = "Bullets",
			kind = "ammo",
			rested = true,
			threshold = 200,
			max = 4000,
			ammo = L.BULLET,
			weapons = { [L.GUN] = true },
		},
	},
	MAGE = {
		{
			key = "conjuredFood",
			name = "Conjured food",
			kind = "items",
			outOfCombat = true,
			threshold = 20,
			max = 200,
			items = L.CONJURED_FOOD,
		},
		{
			key = "conjuredWater",
			name = "Conjured water",
			kind = "items",
			outOfCombat = true,
			threshold = 20,
			max = 200,
			items = L.CONJURED_WATER,
		},
	},
}

L.EVALUATORS = {}

function L.EVALUATORS.ammo(warning, reading)
	local needed = reading.weaponClass == L.WEAPON and warning.weapons[reading.weaponSubclass] == true
	local count = 0
	if
		reading.ammoClass == L.PROJECTILE
		and reading.ammoSubclass == warning.ammo
		and type(reading.ammoCount) == "number"
	then
		count = math.max(0, reading.ammoCount)
	end
	return needed, count
end

function L.EVALUATORS.items(warning, reading)
	local itemCounts = type(reading.itemCounts) == "table" and reading.itemCounts or {}
	local count = 0
	for _, id in ipairs(warning.items) do
		local v = itemCounts[id]
		if type(v) == "number" then
			count = count + math.max(0, v)
		end
	end
	return true, count
end

function L.ForClass(class)
	return L.WARNINGS[class] or {}
end

function L.ItemIds(warnings)
	local out = {}
	local seen = {}
	for _, warning in ipairs(warnings) do
		if warning.items then
			for _, id in ipairs(warning.items) do
				if not seen[id] then
					seen[id] = true
					out[#out + 1] = id
				end
			end
		end
	end
	return out
end

function L.Settings(warning, profile)
	local warnings = type(profile.warnings) == "table" and profile.warnings or {}
	local enabled = warnings[warning.key] ~= false
	local threshold = warning.threshold
	local thresholds = type(profile.thresholds) == "table" and profile.thresholds or {}
	if type(thresholds[warning.key]) == "number" then
		threshold = thresholds[warning.key]
	end
	return enabled, threshold
end

function L.Evaluate(warning, reading, threshold)
	local evaluator = L.EVALUATORS[warning.kind]
	if not evaluator then
		return false, nil
	end
	if warning.rested and not reading.resting then
		return false, nil
	end
	if warning.outOfCombat and reading.inCombat then
		return false, nil
	end
	local needed, count = evaluator(warning, reading)
	if not needed then
		return false, nil
	end
	return count < threshold, count
end

function L.Active(warnings, reading, profile)
	local out = {}
	for _, warning in ipairs(warnings) do
		local enabled, threshold = L.Settings(warning, profile)
		if enabled then
			local active, count = L.Evaluate(warning, reading, threshold)
			if active then
				out[#out + 1] = { warning = warning, count = count }
			end
		end
	end
	return out
end

function L.Preview(warnings, profile)
	local out = {}
	for _, warning in ipairs(warnings) do
		local enabled, threshold = L.Settings(warning, profile)
		if enabled then
			out[#out + 1] = { warning = warning, count = threshold }
		end
	end
	return out
end

function L.Format(warning, count)
	return "Low " .. warning.name:lower() .. ": " .. count
end
