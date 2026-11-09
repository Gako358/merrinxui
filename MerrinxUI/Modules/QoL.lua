local addonName, ns = ...

local QoL = ns.addon:NewModule("QoL")

local TABS = { "Performance", "LayerHop" }

function QoL:GetOptions()
	local args = {}
	for i, name in ipairs(TABS) do
		local tab = ns.addon:GetModule(name):GetTabOptions()
		tab.order = i
		args[name] = tab
	end
	return {
		type = "group",
		name = "QoL",
		desc = "Quality of life",
		childGroups = "tab",
		args = args,
	}
end

function QoL:GetDebugChecks()
	return {
		{
			name = "tabs",
			run = function()
				local options = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("MerrinxUI", "dialog", "MerrinxUI-1.0")
				local node = type(options) == "table" and options.args and options.args.QoL
				if type(node) ~= "table" or type(node.args) ~= "table" then
					return "FAIL", "no QoL node"
				end
				local missing = {}
				for _, name in ipairs(TABS) do
					if type(node.args[name]) ~= "table" then
						missing[#missing + 1] = name
					end
				end
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS", #TABS
			end,
		},
	}
end
