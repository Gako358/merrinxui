local addonName, ns = ...

local CastBarLogic = {}
ns.CastBarLogic = CastBarLogic

local L = CastBarLogic

L.UNITS = { "player", "target", "focus" }

L.LABELS = {
	player = "Player",
	target = "Target",
	focus = "Focus",
}

L.SWINGS = { "main", "off", "ranged" }

L.SWING_LABELS = {
	main = "Main Hand",
	off = "Off Hand",
	ranged = "Ranged",
}

-- A stop, failure or interrupt belongs to the shown cast unless both GUIDs are
-- readable and differ: pressing another spell mid-cast fails that one only.
function L.SameCast(current, incoming, isSecret)
	if isSecret(current) or isSecret(incoming) or current == nil or incoming == nil then
		return true
	end
	return current == incoming
end

-- Speeds from UnitAttackSpeed; a secret speed is unknown (nil), not "no weapon".
function L.CanSwing(off, ranged, isSecret)
	local function slot(speed)
		if isSecret(speed) then
			return nil
		end
		return type(speed) == "number" and speed > 0
	end
	return { main = true, off = slot(off), ranged = slot(ranged) }
end

-- known: slot -> true/false/nil; an unknown slot keeps the answer seen last.
function L.MergeSwing(known, fresh)
	local out = {}
	for _, key in ipairs(L.SWINGS) do
		if fresh[key] == nil then
			out[key] = known[key] == true
		else
			out[key] = fresh[key]
		end
	end
	return out
end

function L.SwingRows(options, canSwing)
	local rows = {}
	for _, key in ipairs(L.SWINGS) do
		if canSwing[key] and (key == "main" or options[key]) then
			table.insert(rows, key)
		end
	end
	return rows
end

function L.StackHeight(rows, rowH, gap)
	local n = math.max(1, rows)
	return n * rowH + (n - 1) * gap
end

-- Fill fraction and seconds left of a swing that started at start.
function L.SwingProgress(start, duration, now)
	if not start or not duration or duration <= 0 then
		return 1, 0
	end
	local elapsed = math.max(0, math.min(duration, now - start))
	return elapsed / duration, duration - elapsed
end
