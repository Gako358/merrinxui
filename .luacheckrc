std = "lua51"
max_line_length = 120

exclude_files = {
	"MerrinxUI/Libs",
	"result",
	"result-*",
}

-- D-12 mandates `local addonName, ns = ...` in every file, even pure *Logic.lua
-- files that have no use for addonName; Ace3 callback methods often ignore self.
ignore = {
	"211/addonName",
	"212/self",
}

read_globals = {
	"LibStub",
	"CreateFrame",
	"UIParent",
	"InCombatLockdown",
	"C_Timer",
	"UnitExists",
	"issecretvalue",
	"Enum",
	"GetBuildInfo",
	"hooksecurefunc",
	"C_Spell",
	"UnitClass",
	"C_CVar",
	"issecurevariable",
	"C_NamePlate",
	"UnitHealth",
	"UnitHealthMax",
	"UnitName",
	"UnitIsUnit",
	"UnitReaction",
	"UnitIsPlayer",
	"UnitCanAttack",
	"UnitIsTapDenied",
	"RAID_CLASS_COLORS",
	"UnitCastingInfo",
	"UnitChannelInfo",
	"UnitCastingDuration",
	"UnitChannelDuration",
	"GetTime",
	"UnitGUID",
	"UnitHealthPercent",
	"CurveConstants",
	"UnitPower",
	"UnitPowerMax",
	"UnitPowerPercent",
	"UnitPowerType",
	"AbbreviateNumbers",
	"C_UnitAuras",
	"date",
	"GetLocale",
	"C_AddOns",
	"SlashCmdList",
	"GetSpellBaseCooldown",
	"GameMenuFrame",
	"ADDONS",
	"HideUIPanel",
	"InputUtil",
	"RegisterGameMenuEscHandler",
	"GameMenuEscPriority",
}

files["spec"] = {
	std = "+busted",
}
