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
	},
	global = {
		meterCVarOwned = false,
	},
}

local GROUP_NAMES = {
	bags = "Bags",
	micro = "Micro Menu",
	xp = "XP Bar",
	actionBars = "Action Bars",
	damageMeter = "Damage Meter",
}

function HideBlizzard:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("HideBlizzard", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.forced = {}
	self.missingWarned = {}
	self.activeGroups = {}
	-- AceAddon never calls OnEnable for a module that starts disabled, so
	-- the meter CVar still needs a login pass to restore a stale owned flag.
	self:RegisterEvent("PLAYER_LOGIN", "ApplyMeter")
end

function HideBlizzard:OnEnable()
	self:ApplyGroups()
	self:ApplyMeter()
end

function HideBlizzard:OnDisable()
	self:ApplyMeter()
end

function HideBlizzard:Refresh()
	local before = self.activeGroups
	local after = self:CurrentGroupSet()

	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:ApplyGroups()
			self:ApplyMeter()
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
	self:ApplyMeter()
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
		if key ~= "damageMeter" and before[key] and not after[key] then
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

function HideBlizzard:ApplyMeter()
	local wantHidden = self:CurrentGroupSet().damageMeter == true

	local current = C_CVar.GetCVar("damageMeterEnabled")
	local newValue, newOwned = HideBlizzardLogic.MeterCVar(wantHidden, current, self.db.global.meterCVarOwned)
	if newValue then
		C_CVar.SetCVar("damageMeterEnabled", newValue)
		ns.Debug:Log("HideBlizzard", "meter", newValue, newOwned)
	end
	self.db.global.meterCVarOwned = newOwned
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

	table.insert(checks, {
		name = "meter cvar",
		run = function()
			local current = C_CVar.GetCVar("damageMeterEnabled")
			if set.damageMeter then
				return (current == "0") and "PASS" or "FAIL"
			end
			return "INFO", current, self.db.global.meterCVarOwned
		end,
	})

	return checks
end
