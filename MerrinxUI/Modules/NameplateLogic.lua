local addonName, ns = ...

local NameplateLogic = {}
ns.NameplateLogic = NameplateLogic

function NameplateLogic.Color(reaction, isPlayer, classFile, tapDenied, classColors)
	if tapDenied then
		return 0.5, 0.5, 0.5
	end

	if isPlayer and classColors and classColors[classFile] then
		local color = classColors[classFile]
		return color.r, color.g, color.b
	end

	if reaction == nil or reaction <= 3 then
		return 1, 0, 0
	elseif reaction == 4 then
		return 1, 1, 0
	end
	return 0, 1, 0
end

function NameplateLogic.FormatValue(mode, numberText, percent)
	if mode == "percent" then
		return string.format("%.0f%%", percent)
	elseif mode == "number" then
		return numberText
	elseif mode == "both" then
		return string.format("%s (%.0f%%)", numberText, percent)
	end
	return nil
end

local POWER_COLORS = {
	MANA = { 0, 0.55, 1 },
	RAGE = { 0.9, 0.1, 0.1 },
	ENERGY = { 1, 0.85, 0.1 },
	FOCUS = { 1, 0.5, 0.25 },
}

function NameplateLogic.PowerColor(token)
	local color = POWER_COLORS[token]
	if color then
		return color[1], color[2], color[3]
	end
	return 0.5, 0.5, 0.5
end

function NameplateLogic.DebuffLayout(anchor, i, n, size, spacing)
	local step = size + spacing
	local x = (i - 1) * step - ((n - 1) * step) / 2

	if anchor == "BOTTOM" then
		return "TOP", "BOTTOM", x, -spacing
	elseif anchor == "RIGHT" then
		return "LEFT", "RIGHT", spacing + (i - 1) * step, 0
	elseif anchor == "LEFT" then
		return "RIGHT", "LEFT", -spacing - (i - 1) * step, 0
	end
	return "BOTTOM", "TOP", x, spacing
end
