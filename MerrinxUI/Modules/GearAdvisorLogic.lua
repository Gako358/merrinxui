local addonName, ns = ...

local GearAdvisorLogic = {}
ns.GearAdvisorLogic = GearAdvisorLogic

local L = GearAdvisorLogic

L.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

L.STATS = {
	"str",
	"agi",
	"sta",
	"int",
	"spi",
	"ap",
	"rap",
	"crit",
	"hit",
	"spellDamage",
	"healing",
	"mp5",
	"def",
	"armor",
	"block",
	"dodge",
	"parry",
	"dps",
}

L.WEIGHT_KEYS = {
	"str",
	"agi",
	"sta",
	"int",
	"spi",
	"ap",
	"rap",
	"crit",
	"hit",
	"spellDamage",
	"healing",
	"mp5",
	"def",
	"armor",
	"block",
	"dodge",
	"parry",
	"meleeDps",
	"rangedDps",
}

L.STAT_RULES = {
	{ key = "str", sources = { "ITEM_MOD_STRENGTH_SHORT" } },
	{ key = "agi", sources = { "ITEM_MOD_AGILITY_SHORT" } },
	{ key = "sta", sources = { "ITEM_MOD_STAMINA_SHORT" } },
	{ key = "int", sources = { "ITEM_MOD_INTELLECT_SHORT" } },
	{ key = "spi", sources = { "ITEM_MOD_SPIRIT_SHORT" } },
	{ key = "ap", sources = { "ITEM_MOD_ATTACK_POWER_SHORT" } },
	{ key = "rap", sources = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" } },
	{ key = "crit", sources = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT" }, combine = "max" },
	{ key = "hit", sources = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT" }, combine = "max" },
	{
		key = "spellDamage",
		sources = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
		combine = "sum",
	},
	{
		key = "healing",
		sources = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
		combine = "sum",
	},
	{ key = "mp5", sources = { "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT" }, combine = "max" },
	{ key = "def", sources = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" } },
	{ key = "armor", sources = { "RESISTANCE0_NAME" } },
	{ key = "block", sources = { "ITEM_MOD_BLOCK_VALUE_SHORT" } },
	{ key = "dodge", sources = { "ITEM_MOD_DODGE_RATING_SHORT" } },
	{ key = "parry", sources = { "ITEM_MOD_PARRY_RATING_SHORT" } },
	{ key = "dps", sources = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" } },
}

L.SLOTS = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 },
	INVTYPE_RELIC = { 18 },
}

L.EQUIPPED_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

L.PROFICIENCY = {
	WARRIOR = {
		armor = { { level = 1, max = 3 }, { level = 40, max = 4 } },
		shield = true,
		dualWield = true,
		weapons = {
			[0] = true,
			[1] = true,
			[2] = true,
			[3] = true,
			[4] = true,
			[5] = true,
			[6] = true,
			[7] = true,
			[8] = true,
			[10] = true,
			[13] = true,
			[15] = true,
			[16] = true,
			[18] = true,
		},
	},
	PALADIN = {
		armor = { { level = 1, max = 3 }, { level = 40, max = 4 } },
		shield = true,
		dualWield = false,
		relic = 7,
		weapons = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true },
	},
	HUNTER = {
		armor = { { level = 1, max = 2 }, { level = 40, max = 3 } },
		shield = false,
		dualWield = true,
		weapons = {
			[0] = true,
			[1] = true,
			[2] = true,
			[3] = true,
			[6] = true,
			[7] = true,
			[8] = true,
			[10] = true,
			[13] = true,
			[15] = true,
			[16] = true,
			[18] = true,
		},
	},
	ROGUE = {
		armor = { { level = 1, max = 2 } },
		shield = false,
		dualWield = true,
		weapons = { [2] = true, [3] = true, [4] = true, [7] = true, [13] = true, [15] = true, [16] = true, [18] = true },
	},
	PRIEST = {
		armor = { { level = 1, max = 1 } },
		shield = false,
		dualWield = false,
		weapons = { [4] = true, [10] = true, [15] = true, [19] = true },
	},
	SHAMAN = {
		armor = { { level = 1, max = 2 }, { level = 40, max = 3 } },
		shield = true,
		dualWield = false,
		relic = 9,
		weapons = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
	},
	MAGE = {
		armor = { { level = 1, max = 1 } },
		shield = false,
		dualWield = false,
		weapons = { [7] = true, [10] = true, [15] = true, [19] = true },
	},
	WARLOCK = {
		armor = { { level = 1, max = 1 } },
		shield = false,
		dualWield = false,
		weapons = { [7] = true, [10] = true, [15] = true, [19] = true },
	},
	DRUID = {
		armor = { { level = 1, max = 2 } },
		shield = false,
		dualWield = false,
		relic = 8,
		weapons = { [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
	},
}

local CLASS_SET = {}
for _, class in ipairs(L.CLASSES) do
	CLASS_SET[class] = true
end

local WEIGHT_KEY_SET = {}
for _, key in ipairs(L.WEIGHT_KEYS) do
	WEIGHT_KEY_SET[key] = true
end

local MELEE_EQUIP_LOCS = {
	INVTYPE_WEAPON = true,
	INVTYPE_WEAPONMAINHAND = true,
	INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_2HWEAPON = true,
}

local RANGED_EQUIP_LOCS = {
	INVTYPE_RANGED = true,
	INVTYPE_RANGEDRIGHT = true,
	INVTYPE_THROWN = true,
}

local TWO_HAND_BLOCKED_EQUIP_LOCS = {
	INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_SHIELD = true,
	INVTYPE_HOLDABLE = true,
}

local function round(x)
	return math.floor(x + 0.5)
end

function L.Normalize(raw, isSecret)
	if type(raw) ~= "table" then
		return nil
	end
	if type(isSecret) == "function" then
		for k, v in pairs(raw) do
			if isSecret(k) or isSecret(v) then
				return nil
			end
		end
	end

	local stats = {}
	for _, rule in ipairs(L.STAT_RULES) do
		local value
		if rule.combine == "max" then
			for _, source in ipairs(rule.sources) do
				local v = raw[source]
				if type(v) == "number" and (value == nil or v > value) then
					value = v
				end
			end
		elseif rule.combine == "sum" then
			for _, source in ipairs(rule.sources) do
				local v = raw[source]
				if type(v) == "number" then
					value = (value or 0) + v
				end
			end
		else
			local v = raw[rule.sources[1]]
			if type(v) == "number" then
				value = v
			end
		end
		if value ~= nil then
			stats[rule.key] = value
		end
	end
	return stats
end

local function statValue(t, key)
	if type(t) == "table" and type(t[key]) == "number" then
		return t[key]
	end
	return 0
end

function L.Score(stats, weights, equipLoc)
	local total = 0
	for _, stat in ipairs(L.STATS) do
		if stat ~= "dps" then
			total = total + statValue(weights, stat) * statValue(stats, stat)
		end
	end
	local dps = statValue(stats, "dps")
	if MELEE_EQUIP_LOCS[equipLoc] then
		total = total + statValue(weights, "meleeDps") * dps
	elseif RANGED_EQUIP_LOCS[equipLoc] then
		total = total + statValue(weights, "rangedDps") * dps
	end
	return total
end

function L.CanUse(class, level, classID, subClassID, equipLoc)
	if not CLASS_SET[class] then
		return false
	end
	if not L.SLOTS[equipLoc] then
		return false
	end
	local prof = L.PROFICIENCY[class]

	if classID == 4 then
		if
			equipLoc == "INVTYPE_CLOAK"
			or equipLoc == "INVTYPE_NECK"
			or equipLoc == "INVTYPE_FINGER"
			or equipLoc == "INVTYPE_TRINKET"
			or equipLoc == "INVTYPE_HOLDABLE"
		then
			return true
		end
		if subClassID == 0 then
			return true
		end
		if subClassID == 6 then
			return prof.shield == true
		end
		if equipLoc == "INVTYPE_RELIC" then
			return prof.relic ~= nil and subClassID == prof.relic
		end
		if subClassID >= 1 and subClassID <= 4 then
			local max = 0
			for _, entry in ipairs(prof.armor) do
				if entry.level <= level then
					max = entry.max
				end
			end
			return subClassID <= max
		end
		return false
	elseif classID == 2 then
		local ok = prof.weapons[subClassID] == true
		if equipLoc == "INVTYPE_WEAPONOFFHAND" then
			return ok and prof.dualWield == true
		end
		return ok
	end
	return true
end

function L.Evaluate(candidate, equipped, weights, ctx)
	if type(candidate) ~= "table" or type(candidate.stats) ~= "table" then
		return nil
	end
	local equipLoc = candidate.equipLoc
	local slots = L.SLOTS[equipLoc]
	if not slots then
		return nil
	end
	equipped = equipped or {}

	local twoHanded = false
	if TWO_HAND_BLOCKED_EQUIP_LOCS[equipLoc] then
		local mainHand = equipped[16]
		twoHanded = mainHand ~= nil and mainHand.equipLoc == "INVTYPE_2HWEAPON"
	end

	local score = L.Score(candidate.stats, weights, equipLoc)

	local slot = slots[1]
	local baseline

	if twoHanded then
		baseline = nil
	elseif equipLoc == "INVTYPE_2HWEAPON" then
		local mh, oh = equipped[16], equipped[17]
		baseline = L.Score(mh and mh.stats, weights, mh and mh.equipLoc)
			+ L.Score(oh and oh.stats, weights, oh and oh.equipLoc)
		slot = 16
	elseif #slots > 1 then
		local bestSlot, bestScore
		for _, s in ipairs(slots) do
			local e = equipped[s]
			local sc = e and L.Score(e.stats, weights, e.equipLoc) or 0
			if bestScore == nil or sc < bestScore then
				bestScore, bestSlot = sc, s
			end
		end
		slot, baseline = bestSlot, bestScore
	else
		local e = equipped[slot]
		baseline = e and L.Score(e.stats, weights, e.equipLoc) or 0
	end

	local delta, percent
	if not twoHanded then
		delta = score - baseline
		percent = baseline > 0 and (delta / baseline * 100) or nil
	end

	local isEquipped = false
	if candidate.link ~= nil then
		for _, s in ipairs(slots) do
			local e = equipped[s]
			if e and e.link == candidate.link then
				isEquipped = true
				break
			end
		end
	end

	local levelOk
	if candidate.minLevel ~= nil then
		levelOk = candidate.minLevel <= ctx.level
	end

	return {
		slot = slot,
		usable = L.CanUse(ctx.class, ctx.level, candidate.classID, candidate.subClassID, equipLoc),
		levelOk = levelOk,
		equipped = isEquipped,
		twoHanded = twoHanded,
		score = score,
		baseline = baseline,
		delta = delta,
		percent = percent,
		minLevel = candidate.minLevel,
	}
end

function L.IsUpgrade(result)
	return result ~= nil
		and result.usable == true
		and result.levelOk == true
		and not result.equipped
		and not result.twoHanded
		and type(result.delta) == "number"
		and result.delta > 0
end

function L.FormatDelta(result)
	local text, kind
	if not result.usable then
		text, kind = "Cannot use", "unusable"
	elseif result.equipped then
		text, kind = "Equipped", "equipped"
	elseif result.twoHanded then
		text, kind = "2H equipped", "blocked"
	elseif math.abs(result.delta) < 0.005 then
		text, kind = "=", "same"
	elseif result.percent == nil and result.delta > 0 then
		text, kind = string.format("+%.1f new", result.delta), "new"
	else
		kind = result.delta >= 0 and "up" or "down"
		text = string.format("%+d%%", round(result.percent or 0))
	end
	if result.levelOk == false then
		text = text .. " (lvl " .. result.minLevel .. ")"
	end
	return text, kind
end

function L.ValidateSpecs(specs)
	if type(specs) ~= "table" then
		return false, "specs must be a table"
	end

	for class in pairs(specs) do
		if not CLASS_SET[class] then
			return false, "unknown class: " .. tostring(class)
		end
	end

	for _, class in ipairs(L.CLASSES) do
		local list = specs[class]
		if type(list) ~= "table" or #list == 0 then
			return false, "missing specs for " .. class
		end
		local seenKeys = {}
		for _, spec in ipairs(list) do
			if type(spec.key) ~= "string" or spec.key == "" then
				return false, "invalid key in " .. class
			end
			if seenKeys[spec.key] then
				return false, "duplicate key " .. spec.key .. " in " .. class
			end
			seenKeys[spec.key] = true
			if type(spec.name) ~= "string" or spec.name == "" then
				return false, "invalid name in " .. class
			end
			if type(spec.weights) ~= "table" then
				return false, "invalid weights in " .. class
			end
			local hasPositive = false
			for key, value in pairs(spec.weights) do
				if not WEIGHT_KEY_SET[key] then
					return false, "unknown weight key " .. tostring(key) .. " in " .. class
				end
				if type(value) ~= "number" or value < 0 then
					return false, "invalid weight value for " .. tostring(key) .. " in " .. class
				end
				if value > 0 then
					hasPositive = true
				end
			end
			if not hasPositive then
				return false, "no positive weight in " .. class
			end
		end
	end

	return true
end

function L.SpecByKey(list, key)
	if type(list) ~= "table" or key == nil then
		return nil
	end
	for _, spec in ipairs(list) do
		if spec.key == key then
			return spec
		end
	end
	return nil
end
