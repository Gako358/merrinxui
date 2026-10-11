local addonName, ns = ...

local HideBlizzardLogic = {}
ns.HideBlizzardLogic = HideBlizzardLogic

HideBlizzardLogic.GROUPS = {
	{ key = "bags", frames = { "BagsBar" } },
	{ key = "micro", frames = { "MicroMenuContainer", "MicroMenu" } },
	{ key = "xp", frames = { "StatusTrackingBarManager" }, unregisterEvents = true },
	{
		key = "actionBars",
		frames = {
			"MainActionBar",
			"MultiBarBottomLeft",
			"MultiBarBottomRight",
			"MultiBarRight",
			"MultiBarLeft",
			"MultiBar5",
			"MultiBar6",
			"MultiBar7",
		},
	},
	{ key = "damageMeter", frames = {} },
}

local VALID_KEYS = {}
for _, group in ipairs(HideBlizzardLogic.GROUPS) do
	VALID_KEYS[group.key] = true
end

function HideBlizzardLogic.Groups(profile, forced)
	local set = {}

	if profile and profile.enabled then
		for _, group in ipairs(HideBlizzardLogic.GROUPS) do
			if profile[group.key] == true then
				set[group.key] = true
			end
		end
	end

	if forced then
		for key in pairs(forced) do
			if VALID_KEYS[key] then
				set[key] = true
			end
		end
	end

	local result = {}
	for key in pairs(set) do
		table.insert(result, key)
	end
	table.sort(result)
	return result
end

function HideBlizzardLogic.MeterCVar(wantHidden, current, owned)
	if wantHidden then
		if current == "1" then
			return "0", true
		end
		return nil, owned
	end

	if owned then
		return "1", false
	end
	return nil, false
end
