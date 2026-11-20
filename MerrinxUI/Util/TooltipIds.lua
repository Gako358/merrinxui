local addonName, ns = ...

local L = ns.TooltipIdLogic

local KINDS = { "Item", "Spell", "UnitAura" }
local hooked, missing = {}, {}

local function post(kind)
	return function(tooltip, data)
		if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
			return
		end
		if type(data) ~= "table" then
			return
		end
		local label, text = L.Line(kind, data.id, issecretvalue)
		if label == nil then
			return
		end
		local a = ns.Theme.color.accent
		tooltip:AddDoubleLine(label, text, a[1], a[2], a[3], 1, 1, 1)
	end
end

local guardOk = type(TooltipDataProcessor) == "table"
	and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
	and type(Enum) == "table"
	and type(Enum.TooltipDataType) == "table"

if guardOk then
	for _, kind in ipairs(KINDS) do
		local value = Enum.TooltipDataType[kind]
		if value ~= nil then
			TooltipDataProcessor.AddTooltipPostCall(value, post(kind))
			table.insert(hooked, kind)
		else
			table.insert(missing, kind)
		end
	end
end

ns.Debug:RegisterChecks("TooltipIds", function()
	return {
		{
			name = "hooks",
			run = function()
				if not guardOk then
					return "FAIL", "TooltipDataProcessor"
				end
				if #missing == 0 and #hooked == #KINDS then
					return "PASS", unpack(hooked, 1, #hooked)
				end
				return "FAIL", unpack(missing, 1, #missing)
			end,
		},
	}
end)
