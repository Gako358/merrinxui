std = "lua51"
max_line_length = 120

exclude_files = {
	"MerrinxUI/Libs",
	"result",
	"result-*",
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
}

files["spec"] = {
	std = "+busted",
}
