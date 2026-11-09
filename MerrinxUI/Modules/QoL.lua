local addonName, ns = ...

local QoL = ns.addon:NewModule("QoL")

local TABS = { "Performance", "LayerHop" }

function QoL:GetOptions()
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
				return "PASS", #present
			end,
		},
	}
end
