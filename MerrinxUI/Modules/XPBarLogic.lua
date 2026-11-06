local addonName, ns = ...

local XPBarLogic = {}
ns.XPBarLogic = XPBarLogic

local L = XPBarLogic

-- entries: { { complete = bool, xp = number|nil } } from the quest log.
function L.QuestXP(entries)
	local count, total = 0, 0
	for _, e in ipairs(entries) do
		if e.complete and type(e.xp) == "number" and e.xp > 0 then
			count = count + 1
			total = total + e.xp
		end
	end
	return count, total
end

function L.Fill(cur, max, extra)
	return math.min(cur + (extra or 0), max)
end

function L.Percent(value, max)
	if max <= 0 then
		return 0
	end
	return value / max * 100
end

-- fmt formats a whole number for display (BreakUpLargeNumbers in game).
function L.Text(cur, max, rested, quest, fmt)
	local text = string.format("%s / %s (%.1f%%)", fmt(cur), fmt(max), L.Percent(cur, max))
	if quest > 0 then
		text = text .. string.format("  +%s quests (%.1f%%)", fmt(quest), L.Percent(quest, max))
		if cur + quest >= max then
			text = text .. " level up"
		end
	end
	if rested > 0 then
		text = text .. string.format("  +%s rested", fmt(rested))
	end
	return text
end

function L.AtMax(level, maxLevel)
	return type(level) == "number" and type(maxLevel) == "number" and maxLevel > 0 and level >= maxLevel
end
