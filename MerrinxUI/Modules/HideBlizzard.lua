local addonName, ns = ...

local HideBlizzardLogic = ns.HideBlizzardLogic

local HideBlizzard = ns.addon:NewModule("HideBlizzard", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = true,
		bags = false,
		micro = false,
		xp = false,
		actionBars = false,
		damageMeter = false,
		unitFrames = false,
		castBar = false,
		swingTimer = false,
	},
	global = {
		meterCVarOwned = false,
		swingCVarOwned = false,
	},
}

-- Both CVars are account-wide, so ownership lives in db.global.
local CVARS = {
	{ group = "damageMeter", cvar = "damageMeterEnabled", owned = "meterCVarOwned", check = "meter cvar" },
	{ group = "swingTimer", cvar = "showSwingTimer", owned = "swingCVarOwned", check = "swing cvar" },
}

local CVAR_GROUPS = {}
for _, entry in ipairs(CVARS) do
	CVAR_GROUPS[entry.group] = true
end

local GROUP_NAMES = {
	bags = "Bags",
	micro = "Micro Menu",
	xp = "XP Bar",
	actionBars = "Action Bars",
	stanceBar = "Stance Bar",
	petBar = "Pet Bar",
	damageMeter = "Damage Meter",
	unitFrames = "Unit Frames",
	castBar = "Cast Bar",
	swingTimer = "Swing Timer",
}

function HideBlizzard:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("HideBlizzard", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.forced = {}
	self.missingWarned = {}
	self.activeGroups = {}
	-- AceAddon never calls OnEnable for a module that starts disabled, so
	-- the CVars still need a login pass to restore a stale owned flag.
	self:RegisterEvent("PLAYER_LOGIN", "ApplyCVars")
end

function HideBlizzard:OnEnable()
	self:ApplyGroups()
	self:ApplyCVars()
end

function HideBlizzard:OnDisable()
	self:ApplyCVars()
end

function HideBlizzard:Refresh()
	local before = self.activeGroups
	local after = self:CurrentGroupSet()

	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:ApplyGroups()
			self:ApplyCVars()
		else
			self:Enable()
		end
	else
		self:Disable()
	end

	self.activeGroups = after
	self:ReportDropped(before, after)
end

function HideBlizzard:Ensure(group)
	self.forced[group] = true
	self:ApplyGroups()
	self:ApplyCVars()
end

function HideBlizzard:CurrentGroupSet()
	local set = {}
	for _, key in ipairs(HideBlizzardLogic.Groups(self.db.profile, self.forced)) do
		set[key] = true
	end
	return set
end

function HideBlizzard:ReportDropped(before, after)
	for _, group in ipairs(HideBlizzardLogic.GROUPS) do
		local key = group.key
		if not CVAR_GROUPS[key] and before[key] and not after[key] then
			ns.addon:Print("HideBlizzard: /reload needed to restore " .. GROUP_NAMES[key])
		end
	end
end

function HideBlizzard:ApplyGroup(group)
	for _, name in ipairs(group.frames) do
		local frame = _G[name]
		if frame then
			local alreadyParented = frame:GetParent() == ns.Hider.parent
			local ok = ns.Hider:Hide(frame, group.unregisterEvents)
			if not alreadyParented then
				ns.Debug:Log("HideBlizzard", "hide", group.key, name, ok)
			end
		elseif not self.missingWarned[name] then
			self.missingWarned[name] = true
			ns.addon:Print("HideBlizzard: " .. name .. " not found")
			ns.Debug:Log("HideBlizzard", "missing", name)
		end
	end
end

function HideBlizzard:ApplyGroups()
	local active = self:CurrentGroupSet()
	for _, group in ipairs(HideBlizzardLogic.GROUPS) do
		if active[group.key] then
			self:ApplyGroup(group)
		end
	end
	self.activeGroups = active
end

function HideBlizzard:ApplyCVars()
	local set = self:CurrentGroupSet()
	for _, entry in ipairs(CVARS) do
		local current = C_CVar.GetCVar(entry.cvar)
		local newValue, newOwned =
			HideBlizzardLogic.MeterCVar(set[entry.group] == true, current, self.db.global[entry.owned])
		if newValue then
			C_CVar.SetCVar(entry.cvar, newValue)
			ns.Debug:Log("HideBlizzard", "cvar", entry.cvar, newValue, newOwned)
		end
		self.db.global[entry.owned] = newOwned
	end
end

function HideBlizzard:GetOptions()
	local function groupToggle(key, order, desc)
		return {
			type = "toggle",
			name = GROUP_NAMES[key],
			order = order,
			desc = desc,
			get = function()
				if self.forced[key] then
					return true
				end
				return self.db.profile[key]
			end,
			set = function(_, value)
				self.db.profile[key] = value
				self:Refresh()
			end,
			disabled = function()
				return self.forced[key] == true
			end,
		}
	end

	return {
		type = "group",
		name = "HideBlizzard",
		args = {
			enabled = {
				type = "toggle",
				name = "Enabled",
				order = 1,
				get = function()
					return self.db.profile.enabled
				end,
				set = function(_, value)
					self.db.profile.enabled = value
					self:Refresh()
				end,
			},
			bags = groupToggle("bags", 2),
			micro = groupToggle("micro", 3),
			xp = groupToggle("xp", 4),
			actionBars = groupToggle(
				"actionBars",
				5,
				"Hides all Blizzard action bars. Without MerrinxUI's action bars enabled, you will have none."
			),
			damageMeter = groupToggle("damageMeter", 6),
			unitFrames = groupToggle("unitFrames", 7),
			castBar = groupToggle("castBar", 8),
			swingTimer = groupToggle(
				"swingTimer",
				9,
				"Turns off Blizzard's swing timer bars (the showSwingTimer setting)."
			),
		},
	}
end

function HideBlizzard:GetDebugChecks()
	local checks = {}
	local set = self:CurrentGroupSet()

	for _, group in ipairs(HideBlizzardLogic.GROUPS) do
		if set[group.key] then
			for _, name in ipairs(group.frames) do
				table.insert(checks, {
					name = "frame " .. name,
					run = function()
						local frame = _G[name]
						if frame == nil then
							return "INFO", "missing"
						end
						return (frame:GetParent() == ns.Hider.parent and not frame:IsVisible()) and "PASS" or "FAIL"
					end,
				})
			end
		end
	end

	for _, group in ipairs(HideBlizzardLogic.GROUPS) do
		if not set[group.key] then
			local stuck = false
			for _, name in ipairs(group.frames) do
				local frame = _G[name]
				if frame and frame:GetParent() == ns.Hider.parent then
					stuck = true
					break
				end
			end
			if stuck then
				table.insert(checks, {
					name = "reload needed " .. group.key,
					run = function()
						return "INFO"
					end,
				})
			end
		end
	end

	for _, entry in ipairs(CVARS) do
		table.insert(checks, {
			name = entry.check,
			run = function()
				local current = C_CVar.GetCVar(entry.cvar)
				if current == nil then
					return "INFO", "missing"
				end
				if set[entry.group] then
					return (current == "0") and "PASS" or "FAIL", current
				end
				return "INFO", current, self.db.global[entry.owned]
			end,
		})
	end

	return checks
end
