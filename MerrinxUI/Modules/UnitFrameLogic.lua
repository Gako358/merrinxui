local addonName, ns = ...

local UnitFrameLogic = {}
ns.UnitFrameLogic = UnitFrameLogic

local L = UnitFrameLogic

L.UNITS = { "player", "target", "targettarget", "focus", "pet" }

L.LABELS = {
	player = "Player",
	target = "Target",
	targettarget = "Target of Target",
	focus = "Focus",
	pet = "Pet",
}

-- Units the client sends no unit events for; they are polled.
L.POLLED = { targettarget = true }

-- Heights of the stacked bars inside a frame of fixed height: the health bar
-- takes what the power bar and the druid mana bar leave, each below a 1px gap.
function L.BarHeights(height, powerHeight, manaHeight, showMana)
	local power = math.max(0, math.min(powerHeight, height - 4))
	local slot = 0
	if showMana and manaHeight > 0 then
		slot = math.min(manaHeight, math.max(0, height - power - 6)) + 1
	end
	local gap = power > 0 and 1 or 0
	local health = height - power - gap - slot
	return health, power, slot
end

function L.ShowDruidMana(enabled, class, powerType, manaType)
	if not enabled or class ~= "DRUID" or powerType == nil then
		return false
	end
	return powerType ~= manaType
end

-- Units owning a unit event; "target" also drives the target-of-target.
function L.EventUnits(unit)
	if unit == "target" then
		return { "target", "targettarget" }
	end
	return { unit }
end

function L.Watched(unit)
	return unit ~= "player"
end

-- UnitGetIncomingHeals returns nil with no heals in flight; a secret value is
-- passed through untouched because only the status bar may read it.
function L.Amount(value, isSecret)
	if isSecret(value) or value ~= nil then
		return value
	end
	return 0
end
