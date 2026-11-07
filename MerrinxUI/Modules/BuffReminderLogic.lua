local addonName, ns = ...

local BuffReminderLogic = {}
ns.BuffReminderLogic = BuffReminderLogic

local L = BuffReminderLogic

-- lines: every spell that satisfies the buff, one list of ranks (lowest first) per spell name.
-- Auras are matched by the name of each line's first rank, which covers every rank of that line.
-- off: starts disabled.
L.BUFFS = {
	DRUID = {
		{
			key = "mark",
			lines = { { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, { 21849, 21850 } },
		},
		{ key = "thorns", lines = { { 467, 782, 1075, 8914, 9756, 9910 } } },
		{ key = "omen", lines = { { 16864 } }, off = true },
	},
	PRIEST = {
		{
			key = "fortitude",
			lines = { { 1243, 1244, 1245, 2791, 10937, 10938 }, { 21562, 21564 } },
		},
		{ key = "innerFire", lines = { { 588, 7128, 602, 1006, 10951, 10952 } } },
		{ key = "divineSpirit", lines = { { 14752, 14818, 14819, 27841 }, { 27681 } } },
	},
	MAGE = {
		{ key = "intellect", lines = { { 1459, 1460, 1461, 10156, 10157 }, { 23028 } } },
		{
			key = "mageArmor",
			lines = { { 168, 7300, 7301 }, { 7302, 7320, 10219, 10220 }, { 6117, 22782, 22783 } },
		},
	},
	WARRIOR = {
		{ key = "battleShout", lines = { { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } } },
	},
	PALADIN = {
		{
			key = "blessing",
			lines = {
				{ 19740, 19834, 19835, 19836, 19837, 19838, 25291 },
				{ 19742, 19850, 19852, 19853, 19854, 25290 },
				{ 20217 },
				{ 1038 },
				{ 19977, 19978, 19979 },
				{ 25782, 25916 },
				{ 25894, 25918 },
				{ 25898 },
				{ 25895 },
				{ 25890 },
			},
		},
	},
	WARLOCK = {
		{ key = "demonArmor", lines = { { 687, 696 }, { 706, 1086, 11733, 11734, 11735 } } },
	},
	SHAMAN = {
		{ key = "lightningShield", lines = { { 324, 325, 905, 945, 8134, 10431, 10432 } } },
	},
	HUNTER = {
		{
			key = "aspect",
			lines = {
				{ 13165, 14318, 14319, 14320, 14321, 14322, 25296 },
				{ 13163 },
				{ 5118 },
				{ 13159 },
				{ 20043, 20190 },
				{ 13161 },
			},
		},
		{ key = "trueshot", lines = { { 19506, 20905, 20906 } }, off = true },
	},
}

function L.ForClass(class)
	return L.BUFFS[class] or {}
end

function L.Known(buff, isKnown)
	for _, line in ipairs(buff.lines) do
		for _, id in ipairs(line) do
			if isKnown(id) then
				return true
			end
		end
	end
	return false
end

-- aura: the aura data of one line, or nil when that line is not on the player.
function L.Status(aura, now, lowSeconds)
	if aura == nil then
		return "missing", 0
	end
	local duration, expires = aura.duration, aura.expirationTime
	if type(duration) ~= "number" or type(expires) ~= "number" or duration <= 0 or expires <= 0 then
		return "ok", nil
	end
	local remaining = math.max(0, expires - now)
	if remaining <= lowSeconds then
		return "low", remaining
	end
	return "ok", remaining
end

local RANK = { ok = 3, low = 2, missing = 1 }

-- states: { { state, remaining } } of the lines of one buff.
function L.Best(states)
	local bestState, bestRemaining = "missing", 0
	for _, s in ipairs(states) do
		local state, remaining = s[1], s[2]
		if RANK[state] > RANK[bestState] then
			bestState, bestRemaining = state, remaining
		elseif state == bestState and state ~= "missing" then
			if remaining == nil or (bestRemaining ~= nil and remaining > bestRemaining) then
				bestRemaining = remaining
			end
		end
	end
	return bestState, bestRemaining
end

function L.FormatTime(seconds)
	if type(seconds) ~= "number" then
		return ""
	end
	seconds = math.floor(seconds + 0.5)
	if seconds >= 60 then
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end
	return seconds .. "s"
end

-- Keys whose state just became missing or low.
function L.Alerts(prev, cur)
	local out = {}
	for key, state in pairs(cur) do
		if state ~= "ok" and prev[key] ~= state and not (state == "low" and prev[key] == "missing") then
			out[#out + 1] = key
		end
	end
	return out
end
