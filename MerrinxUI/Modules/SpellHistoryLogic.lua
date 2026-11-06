local addonName, ns = ...

local SpellHistoryLogic = {}
ns.SpellHistoryLogic = SpellHistoryLogic

local L = SpellHistoryLogic

L.MAX_HISTORY = 80

local OUTCOME_TEXT = {
	failed = "|cffdb4141Failed|r",
	interrupted = "|cffdb4141Interrupted|r",
}

function L.Push(history, entry, max)
	table.insert(history, 1, entry)
	for i = #history, (max or L.MAX_HISTORY) + 1, -1 do
		history[i] = nil
	end
	return history
end

function L.IsActive(entry)
	return entry.status == "casting" or entry.status == "channeling"
end

function L.IsStopped(status)
	return status == "failed" or status == "interrupted"
end

-- 0..1; channels drain, casts fill. A finished entry keeps the fill it had
-- when it stopped, or 1.
function L.Progress(entry, now)
	if entry.fill then
		return entry.fill
	end
	if L.IsActive(entry) then
		local dur = (entry.endTime or 0) - (entry.startTime or 0)
		if dur <= 0 then
			return 1
		end
		local p
		if entry.status == "channeling" then
			p = (entry.endTime - now) / dur
		else
			p = (now - entry.startTime) / dur
		end
		return math.max(0, math.min(1, p))
	end
	return 1
end

function L.Finish(entry, status, now)
	if L.IsStopped(status) and L.IsActive(entry) then
		entry.fill = L.Progress(entry, now)
	end
	entry.status = status
	if entry.startTime then
		entry.castDuration = now - entry.startTime
	end
	entry.endTime = now
	return entry
end

function L.CastTimeText(entry, now)
	if entry.isInstant then
		return ""
	end
	if L.IsActive(entry) then
		local elapsed = now - (entry.startTime or now)
		if elapsed > 0 then
			return string.format("%.1f", elapsed)
		end
		return ""
	end
	if entry.castDuration and entry.castDuration > 0 then
		return string.format("%.1fs", entry.castDuration)
	end
	return ""
end

-- target: a plain name (realm stripped by shorten) or nil; a secret target
-- can't be concatenated, so the caller shows it on its own (secretTarget).
function L.RightText(entry, now, target)
	local cast = L.CastTimeText(entry, now)
	local right = OUTCOME_TEXT[entry.status] or (target ~= "" and target) or nil
	if cast ~= "" and right then
		return cast .. "  " .. right
	end
	if cast ~= "" then
		return cast
	end
	return right or ""
end

-- Offset of icon i (1 = newest) from the strip's anchor.
function L.IconOffset(i, size, spacing, direction)
	local d = (i - 1) * (size + spacing)
	if direction == "LEFT" then
		return -d, 0
	elseif direction == "RIGHT" then
		return d, 0
	elseif direction == "UP" then
		return 0, d
	end
	return 0, -d
end

-- Out of combat an icon fades fadeTime seconds after it was cast or after
-- the last combat ended, whichever is later; 0 never fades.
function L.IconVisible(entryTime, combatEnd, now, fadeTime, inCombat)
	if fadeTime <= 0 or inCombat then
		return true
	end
	return now - math.max(entryTime, combatEnd or 0) < fadeTime
end

function L.ClampScroll(scroll, total, slots)
	return math.max(0, math.min(scroll, math.max(0, total - slots)))
end
