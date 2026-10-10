local addonName, ns = ...

local MerrinxUI = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
ns.addon = MerrinxUI

function MerrinxUI:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("MerrinxUIDB", { profile = {}, global = {} }, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshModules")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshModules")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshModules")

	self:RegisterChatCommand("mui", "SlashCommand")
	self:RegisterChatCommand("merrinxui", "SlashCommand")
end

function MerrinxUI:OnEnable()
	local root = {
		type = "group",
		name = "MerrinxUI",
		childGroups = "tree",
		args = {
			profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db),
		},
	}
	root.args.profiles.order = 100

	for name, module in self:IterateModules() do
		if module.GetOptions then
			root.args[name] = module:GetOptions()
		end
	end

	LibStub("AceConfig-3.0"):RegisterOptionsTable("MerrinxUI", root)
end

function MerrinxUI:RefreshModules()
	for _, module in self:IterateModules() do
		if module.Refresh then
			module:Refresh()
		end
	end
end

function MerrinxUI.SlashCommand()
	LibStub("AceConfigDialog-3.0"):Open("MerrinxUI")
end
