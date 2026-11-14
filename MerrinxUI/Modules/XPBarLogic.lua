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

function L.NewRate(now)
	return { start = now, samples = {} }
end

-- cur < lastCur means the level rolled over, so the gain spans the old level's remainder plus the new cur.
local function gain(rate, cur, max)
	local wrap = cur < rate.lastCur or max ~= rate.lastMax
	if wrap then
		return rate.lastMax - rate.lastCur + cur
	end
	return cur - rate.lastCur
end

function L.Track(rate, cur, max, now, window)
	if max <= 1 then
		return
	end
	if rate.lastCur == nil then
		rate.lastCur, rate.lastMax = cur, max
		return
	end
	local xp = gain(rate, cur, max)
	if xp > 0 then
		table.insert(rate.samples, { t = now, xp = xp })
	end
	rate.lastCur, rate.lastMax = cur, max
	local cutoff = now - window
	while rate.samples[1] and rate.samples[1].t <= cutoff do
		table.remove(rate.samples, 1)
	end
end

function L.PerSecond(rate, now, window, minSpan)
	local cutoff = now - window
	local total = 0
	for _, s in ipairs(rate.samples) do
		if s.t > cutoff then
			total = total + s.xp
		end
	end
	local span = math.min(math.max(now - rate.start, minSpan), window)
	return total / span
end

function L.TimeToLevel(remaining, perSecond)
	if remaining <= 0 or perSecond <= 0 then
		return nil
	end
	return remaining / perSecond
end

function L.FormatDuration(seconds)
	if seconds < 60 then
		return "<1m"
	end
	if seconds < 3600 then
		return string.format("%dm", math.floor(seconds / 60))
	end
	return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end
