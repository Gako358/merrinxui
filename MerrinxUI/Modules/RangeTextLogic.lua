local addonName, ns = ...

local RangeTextLogic = {}
ns.RangeTextLogic = RangeTextLogic

RangeTextLogic.DEFAULT_SPELLS = {
	DRUID = 5176,
	HUNTER = 75,
	MAGE = 133,
	PALADIN = 20271,
	PRIEST = 585,
	ROGUE = 1752,
	SHAMAN = 403,
	WARLOCK = 686,
	WARRIOR = 78,
}

function RangeTextLogic.NormalizeSpell(v)
	local t = type(v)
	if t == "number" then
		if v > 0 and v == math.floor(v) then
			return v
		end
		return nil
	elseif t == "string" then
		local trimmed = v:match("^%s*(.-)%s*$")
		if trimmed == "" then
			return nil
		end
		local n = tonumber(trimmed)
		if n ~= nil then
			if n > 0 and n == math.floor(n) then
				return n
			end
			return nil
		end
		return trimmed
	end
	return nil
end

function RangeTextLogic.ResolveSpell(configured, classFile)
	local resolved = RangeTextLogic.NormalizeSpell(configured)
	if resolved ~= nil then
		return resolved
	end
	return RangeTextLogic.DEFAULT_SPELLS[classFile]
end

function RangeTextLogic.Classify(r)
	if r == true then
		return "in"
	elseif r == false then
		return "out"
	end
	return "unknown"
end

function RangeTextLogic.Color(state)
	if state == "in" then
		return 0, 1, 0
	elseif state == "out" then
		return 1, 0, 0
	end
	return 1, 1, 1
end

function RangeTextLogic.FormatRange(min, max)
	if min == nil then
		return "?"
	end
	if max == nil then
		return min .. "+"
	end
	return min .. " - " .. max
end
