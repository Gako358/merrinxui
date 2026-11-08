local addonName, ns = ...

local NameplateLogic = {}
ns.NameplateLogic = NameplateLogic

local COLORS = {
	hostile = { 0.8, 0.137, 0.137 },
	neutral = { 0.81, 0.72, 0.19 },
	friendly = { 0.314, 0.8, 0.408 },
	tapped = { 0.5, 0.5, 0.5 },
	tankLosingAggro = { 0.81, 0.72, 0.19 },
	tankNoAggro = { 1, 0.22, 0.17 },
	offTankAggro = { 0.188, 0.761, 0.812 },
	dpsHasAggro = { 1, 0.5, 0 },
	dpsNearAggro = { 0.81, 0.72, 0.19 },
}
NameplateLogic.COLORS = COLORS

local DARKEN_FACTOR = 0.6

function NameplateLogic.ThreatRole(setting, assignedRole)
	if setting == "tank" or setting == "dps" then
		return setting
	end
	return assignedRole == "TANK" and "tank" or "dps"
end

-- status is UnitThreatSituation's 0-3; a tank holding aggro gets no override so the mob keeps its normal colour
function NameplateLogic.ThreatColorKey(role, status, shared, offTank)
	if type(status) ~= "number" then
		return nil
	end
	if role == "tank" then
		if status >= 3 then
			return nil
		elseif status >= 2 then
			return "tankLosingAggro"
		end
		return offTank and "offTankAggro" or "tankNoAggro"
	end
	if not shared then
		return nil
	end
	if status >= 3 then
		return "dpsHasAggro"
	elseif status >= 2 then
		return "dpsNearAggro"
	end
	return nil
end

local function rgb(color)
	return color[1], color[2], color[3]
end

function NameplateLogic.PlateColor(state, classColors)
	if state.tapDenied then
		return rgb(COLORS.tapped)
	end

	local threatKey = NameplateLogic.ThreatColorKey(state.threatRole, state.threat, state.threatShared, state.offTank)
	if threatKey then
		return rgb(COLORS[threatKey])
	end

	local classColor = state.isPlayer and classColors and state.classFile and classColors[state.classFile]
	if classColor then
		return classColor.r, classColor.g, classColor.b
	end

	local reaction = state.reaction
	if reaction == 4 then
		return rgb(state.inCombat == true and COLORS.hostile or COLORS.neutral)
	elseif reaction ~= nil and reaction >= 5 then
		return rgb(COLORS.friendly)
	end

	local r, g, b = rgb(COLORS.hostile)
	if state.darkenOOC and state.inCombat ~= true then
		return r * DARKEN_FACTOR, g * DARKEN_FACTOR, b * DARKEN_FACTOR
	end
	return r, g, b
end

local CLASSIFICATION_ATLAS = {
	elite = "nameplates-icon-elite-gold",
	worldboss = "nameplates-icon-elite-gold",
	rareelite = "nameplates-icon-elite-silver",
	rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
}

function NameplateLogic.ClassificationAtlas(classification)
	return CLASSIFICATION_ATLAS[classification]
end

function NameplateLogic.MarkerLayout(position, gap)
	if position == "TOPRIGHT" then
		return "BOTTOMRIGHT", "TOPRIGHT", 0, gap
	elseif position == "TOPLEFT" then
		return "BOTTOMLEFT", "TOPLEFT", 0, gap
	elseif position == "LEFT" then
		return "RIGHT", "LEFT", -gap, 0
	elseif position == "RIGHT" then
		return "LEFT", "RIGHT", gap, 0
	end
	return nil
end

function NameplateLogic.ExecuteOffset(width, percent)
	return width * math.max(0, math.min(100, percent)) / 100
end

-- Eight pieces around a bar cut from a square glow whose centre touches the
-- bar: corners take a quadrant, edges a thin strip through the centre.
-- points: { piecePoint, barPoint }; size: which dimension is the glow's reach.
NameplateLogic.GLOW_PIECES = {
	{ size = "corner", points = { { "BOTTOMRIGHT", "TOPLEFT" } }, coords = { 0, 0.5, 0, 0.5 } },
	{ size = "corner", points = { { "BOTTOMLEFT", "TOPRIGHT" } }, coords = { 0.5, 1, 0, 0.5 } },
	{ size = "corner", points = { { "TOPRIGHT", "BOTTOMLEFT" } }, coords = { 0, 0.5, 0.5, 1 } },
	{ size = "corner", points = { { "TOPLEFT", "BOTTOMRIGHT" } }, coords = { 0.5, 1, 0.5, 1 } },
	{
		size = "height",
		points = { { "BOTTOMLEFT", "TOPLEFT" }, { "BOTTOMRIGHT", "TOPRIGHT" } },
		coords = { 0.49, 0.51, 0, 0.5 },
	},
	{
		size = "height",
		points = { { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } },
		coords = { 0.49, 0.51, 0.5, 1 },
	},
	{
		size = "width",
		points = { { "TOPRIGHT", "TOPLEFT" }, { "BOTTOMRIGHT", "BOTTOMLEFT" } },
		coords = { 0, 0.5, 0.49, 0.51 },
	},
	{
		size = "width",
		points = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } },
		coords = { 0.5, 1, 0.49, 0.51 },
	},
}

NameplateLogic.TARGET_STYLES = {
	glow = "Glow",
	border = "Border",
	highlight = "Highlight",
	outline = "Outline",
	none = "None",
}

NameplateLogic.BORDER_MODES = { none = "None", thin = "Thin", shadow = "Shadow" }

-- The Border option is a view over the border toggle and the border style.
function NameplateLogic.BorderMode(border, style)
	if not border then
		return "none"
	end
	return style == "shadow" and "shadow" or "thin"
end

function NameplateLogic.BorderSetting(mode)
	if mode == "none" then
		return false, nil
	end
	return true, mode == "shadow" and "shadow" or "thin"
end

function NameplateLogic.CastIconSize(healthHeight, powerHeight, powerGap, castGap, castHeight)
	local size = healthHeight + castGap + castHeight
	if powerHeight then
		size = size + powerGap + powerHeight
	end
	return size
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

function NameplateLogic.LevelText(level, classification)
	if level == nil or level == 0 then
		return nil
	end
	if level == -1 or classification == "worldboss" then
		return "??"
	end

	local suffix = ""
	if classification == "elite" then
		suffix = "+"
	elseif classification == "rare" then
		suffix = "r"
	elseif classification == "rareelite" then
		suffix = "r+"
	end
	return tostring(level) .. suffix
end

function NameplateLogic.LevelColor(level, classification, color)
	if level == -1 or classification == "worldboss" then
		return 1, 0, 0
	end
	if type(color) == "table" and type(color.r) == "number" then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

local COMBO_CLASSES = { ROGUE = true, DRUID = true }

function NameplateLogic.UsesComboPoints(classFile)
	return COMBO_CLASSES[classFile] == true
end

NameplateLogic.CC_FILTER = "HARMFUL|CROWD_CONTROL"

function NameplateLogic.DebuffFilter(mineOnly, ccSeparate)
	local filter = mineOnly and "HARMFUL|PLAYER" or "HARMFUL"
	if ccSeparate then
		filter = filter .. "|!CROWD_CONTROL"
	end
	return filter
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
