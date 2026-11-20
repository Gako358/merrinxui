local addonName, ns = ...

local TooltipIdLogic = {}
ns.TooltipIdLogic = TooltipIdLogic

TooltipIdLogic.LABELS = { Item = "Item ID", Spell = "Spell ID", UnitAura = "Spell ID" }

function TooltipIdLogic.Line(kind, id, isSecret)
	local label = TooltipIdLogic.LABELS[kind]
	if label == nil then
		return nil
	end
	if isSecret(id) then
		return nil
	end
	if type(id) ~= "number" then
		return nil
	end
	if id <= 0 then
		return nil
	end
	if id ~= math.floor(id) then
		return nil
	end
	return label, string.format("%d", id)
end
