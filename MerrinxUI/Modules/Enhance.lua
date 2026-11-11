local addonName, ns = ...

local Enhance = ns.addon:NewModule("Enhance")

local TABS = {
	"Performance",
	"BuffReminders",
	"CastBars",
	"CooldownVoice",
	"Professions",
	"RangeText",
	"SpellHistory",
	"XPBar",
	"LayerHop",
}

function Enhance:GetOptions()
	local args = {}
	for i, name in ipairs(TABS) do
		local module = ns.addon:GetModule(name, true)
		if module then
			local tab = module:GetTabOptions()
			tab.order = i
			args[name] = tab
		end
	end
	return {
		type = "group",
		name = "Enhance",
		desc = "Quality of life enhancements",
		childGroups = "tab",
		args = args,
	}
end

function Enhance:GetDebugChecks()
	return {
		{
			name = "tabs",
			run = function()
				local options = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("MerrinxUI", "dialog", "MerrinxUI-1.0")
				local node = type(options) == "table" and options.args and options.args.Enhance
				if type(node) ~= "table" or type(node.args) ~= "table" then
					return "FAIL", "no Enhance node"
				end
				local present = {}
				for _, name in ipairs(TABS) do
					if ns.addon:GetModule(name, true) then
						present[#present + 1] = name
					end
				end
				local missing = {}
				for _, name in ipairs(present) do
					if type(node.args[name]) ~= "table" then
						missing[#missing + 1] = name
					end
				end
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				local stale = {}
				for _, name in ipairs(present) do
					if options.args[name] ~= nil then
						stale[#stale + 1] = name
					end
				end
				if #stale > 0 then
					return "FAIL", unpack(stale, 1, #stale)
				end
				return "PASS", #present
			end,
		},
	}
end
