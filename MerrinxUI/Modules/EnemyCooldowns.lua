local addonName, ns = ...

local L = ns.EnemyCooldownLogic

local EnemyCooldowns = ns.addon:NewModule("EnemyCooldowns", "AceEvent-3.0")

local FALLBACK_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"
local LAYOUT_SPACING = 2
local TICK_INTERVAL = 0.5

local defaults = {
	profile = {
		enabled = true,
		iconSize = 20,
		maxIcons = 4,
		anchor = "TOP",
		x = 0,
		y = 2,
	},
}

local function IsNameplateUnit(unit)
	return type(unit) == "string" and unit:match("^nameplate") ~= nil
end

local function ResolveSpellName(spellID)
	local name = C_Spell.GetSpellName(spellID)
	if issecretvalue(name) then
		return nil
	end
	return name
end

function EnemyCooldowns:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("EnemyCooldowns", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	self.state = {}
	self.units = {}
	self.unitPlate = {}
	self.containers = setmetatable({}, { __mode = "k" })
end

function EnemyCooldowns:OnEnable()
	if not self.index then
		self.index = L.BuildIndex(L.SPELLS, ResolveSpellName)
	end

	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnUnitAdded")
	self:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnUnitRemoved")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")

	self.ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
		self:OnTick()
	end)

	self:RescanPlates()
end

function EnemyCooldowns:RescanPlates()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		self:HandleUnit(plate.unitToken)
	end
end

function EnemyCooldowns:OnDisable()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end

	for key in pairs(self.state) do
		self.state[key] = nil
	end
	for unit in pairs(self.units) do
		self.units[unit] = nil
	end
	for unit in pairs(self.unitPlate) do
		self.unitPlate[unit] = nil
	end
	for _, container in pairs(self.containers) do
		container:Hide()
	end
end

function EnemyCooldowns:Refresh()
	if self.db.profile.enabled then
		self:Enable()
		for unit in pairs(self.units) do
			self:Render(unit)
		end
	else
		self:Disable()
	end
end

function EnemyCooldowns:ClearUnit(unit)
	local plate = self.unitPlate[unit]
	if plate then
		local container = self.containers[plate]
		if container then
			container:Hide()
		end
	end
	self.units[unit] = nil
	self.unitPlate[unit] = nil
end

function EnemyCooldowns:HandleUnit(unit)
	if not IsNameplateUnit(unit) then
		return
	end

	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end

	if plate:IsForbidden() then
		if ns.Debug:IsActive() then
			local forbiddenIsPlayer = UnitIsPlayer(unit)
			local forbiddenCanAttack = UnitCanAttack("player", unit)
			if
				not issecretvalue(forbiddenIsPlayer)
				and not issecretvalue(forbiddenCanAttack)
				and forbiddenIsPlayer == true
				and forbiddenCanAttack == true
			then
				ns.Debug:Log("EnemyCooldowns", "skip", unit, "forbidden")
			end
		end
		return
	end

	local isPlayer = UnitIsPlayer(unit)
	local canAttack = UnitCanAttack("player", unit)
	if issecretvalue(isPlayer) or issecretvalue(canAttack) then
		local wasTracked = self.units[unit] ~= nil
		self:ClearUnit(unit)
		if wasTracked then
			ns.Debug:Log("EnemyCooldowns", "skip", unit, "secret flags")
		end
		return
	end
	if not (isPlayer == true and canAttack == true) then
		self:ClearUnit(unit)
		return
	end

	local guid = UnitGUID(unit)
	if issecretvalue(guid) then
		local wasTracked = self.units[unit] ~= nil
		self:ClearUnit(unit)
		if wasTracked then
			ns.Debug:Log("EnemyCooldowns", "skip", unit, "secret guid")
		end
		return
	end
	if guid == nil then
		self:ClearUnit(unit)
		return
	end

	local isNewTrack = self.units[unit] == nil
	self.units[unit] = guid
	self.unitPlate[unit] = plate
	if isNewTrack then
		ns.Debug:Log("EnemyCooldowns", "track", unit)
	end
	self:Render(unit)
end

function EnemyCooldowns:OnUnitAdded(_, unit)
	self:HandleUnit(unit)
end

function EnemyCooldowns:OnUnitFaction(_, unit)
	self:HandleUnit(unit)
end

function EnemyCooldowns:OnUnitRemoved(_, unit)
	self:ClearUnit(unit)
end

function EnemyCooldowns:OnSpellcastSucceeded(_, unit, _, spellID)
	local key = self.units[unit]
	if not key or issecretvalue(spellID) then
		return
	end

	local name = ResolveSpellName(spellID)
	local entry = L.Lookup(self.index, spellID, name)
	if not entry then
		return
	end

	L.Record(self.state, key, entry, GetTime())
	ns.Debug:Log("EnemyCooldowns", "hit", unit, spellID, name, entry.cd)
	self:Render(unit)
end

function EnemyCooldowns:OnEnteringWorld()
	ns.Debug:Log("EnemyCooldowns", "reset")
	for key in pairs(self.state) do
		self.state[key] = nil
	end
	for unit in pairs(self.units) do
		self.units[unit] = nil
	end
	for unit in pairs(self.unitPlate) do
		self.unitPlate[unit] = nil
	end
	for _, container in pairs(self.containers) do
		container:Hide()
	end

	self:RescanPlates()
end

function EnemyCooldowns:OnTick()
	local changed = L.Prune(self.state, GetTime())
	for unit, guid in pairs(self.units) do
		if changed[guid] then
			self:Render(unit)
		end
	end
end

function EnemyCooldowns:GetContainer(plate)
	local container = self.containers[plate]
	if not container then
		container = CreateFrame("Frame", nil, plate)
		container:SetAllPoints(plate)
		container:SetFrameLevel(plate:GetFrameLevel() + 10)
		container.icons = {}
		self.containers[plate] = container
	end
	return container
end

function EnemyCooldowns:GetIcon(container, i)
	local icon = container.icons[i]
	if not icon then
		icon = CreateFrame("Frame", nil, container)

		local texture = icon:CreateTexture(nil, "ARTWORK")
		texture:SetAllPoints(icon)
		icon.texture = texture

		local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
		cooldown:SetAllPoints(icon)
		icon.cooldown = cooldown

		container.icons[i] = icon
	end
	return icon
end

function EnemyCooldowns:Render(unit)
	local key = self.units[unit]
	local plate = self.unitPlate[unit]
	if not key or not plate then
		return
	end

	local profile = self.db.profile
	local records = L.Active(self.state, key, GetTime(), profile.maxIcons)
	local container = self:GetContainer(plate)
	container:Show()
	local n = #records

	for i = 1, n do
		local rec = records[i]
		local icon = self:GetIcon(container, i)
		icon:SetSize(profile.iconSize, profile.iconSize)

		local texture = C_Spell.GetSpellTexture(rec.entry.id)
		icon.texture:SetTexture(texture or FALLBACK_TEXTURE)

		local point, relPoint, x, y =
			L.Layout(profile.anchor, i, n, profile.iconSize, LAYOUT_SPACING, profile.x, profile.y)
		icon:ClearAllPoints()
		icon:SetPoint(point, container, relPoint, x, y)
		icon.cooldown:SetCooldown(rec.start, rec.entry.cd)
		icon:Show()
	end

	for i = n + 1, #container.icons do
		container.icons[i]:Hide()
	end
end

function EnemyCooldowns:GetOptions()
	return {
		type = "group",
		name = "EnemyCooldowns",
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
			iconSize = {
				type = "range",
				name = "Icon size",
				order = 2,
				min = 12,
				max = 48,
				step = 1,
				get = function()
					return self.db.profile.iconSize
				end,
				set = function(_, value)
					self.db.profile.iconSize = value
					self:Refresh()
				end,
			},
			maxIcons = {
				type = "range",
				name = "Max icons",
				order = 3,
				min = 1,
				max = 8,
				step = 1,
				get = function()
					return self.db.profile.maxIcons
				end,
				set = function(_, value)
					self.db.profile.maxIcons = value
					self:Refresh()
				end,
			},
			anchor = {
				type = "select",
				name = "Anchor",
				order = 4,
				values = {
					TOP = "Top",
					BOTTOM = "Bottom",
					LEFT = "Left",
					RIGHT = "Right",
				},
				get = function()
					return self.db.profile.anchor
				end,
				set = function(_, value)
					self.db.profile.anchor = value
					self:Refresh()
				end,
			},
			x = {
				type = "range",
				name = "X offset",
				order = 5,
				min = -100,
				max = 100,
				step = 1,
				get = function()
					return self.db.profile.x
				end,
				set = function(_, value)
					self.db.profile.x = value
					self:Refresh()
				end,
			},
			y = {
				type = "range",
				name = "Y offset",
				order = 6,
				min = -100,
				max = 100,
				step = 1,
				get = function()
					return self.db.profile.y
				end,
				set = function(_, value)
					self.db.profile.y = value
					self:Refresh()
				end,
			},
		},
	}
end

function EnemyCooldowns:GetDebugChecks()
	local function AuditBaseCooldownMs(id)
		if type(GetSpellBaseCooldown) ~= "function" then
			return nil
		end
		local ms = GetSpellBaseCooldown(id)
		if issecretvalue(ms) then
			return nil
		end
		return ms
	end

	local audit = L.Audit(L.SPELLS, ResolveSpellName, AuditBaseCooldownMs)

	local function readPoint(region)
		if type(region.IsAnchoringRestricted) == "function" then
			local restricted = region:IsAnchoringRestricted()
			if issecretvalue(restricted) or restricted then
				return false
			end
		end
		local ok, p, rel, rp, x, y = pcall(region.GetPoint, region, 1)
		if not ok then
			return false
		end
		return true, p, rel, rp, x, y
	end

	local checks = {
		{
			name = "spell table",
			run = function()
				if #audit.unresolved > 0 or #audit.duplicates > 0 or #audit.mismatched > 0 then
					local parts = {}
					if #audit.unresolved > 0 then
						table.insert(parts, "unresolved")
						for _, id in ipairs(audit.unresolved) do
							table.insert(parts, id)
						end
					end
					if #audit.duplicates > 0 then
						table.insert(parts, "duplicates")
						for _, id in ipairs(audit.duplicates) do
							table.insert(parts, id)
						end
					end
					if #audit.mismatched > 0 then
						table.insert(parts, "mismatched")
						for _, m in ipairs(audit.mismatched) do
							table.insert(parts, m.id)
							table.insert(parts, m.expected)
							table.insert(parts, m.actual)
						end
					end
					return "FAIL", unpack(parts, 1, #parts)
				end
				return "PASS", #L.SPELLS
			end,
		},
		{
			name = "spell cooldowns",
			run = function()
				if type(GetSpellBaseCooldown) ~= "function" then
					return "SKIP", "GetSpellBaseCooldown missing"
				end
				if #audit.unknownCd > 0 then
					return "INFO", "unknown", unpack(audit.unknownCd, 1, #audit.unknownCd)
				end
				return "PASS"
			end,
		},
		{
			name = "index",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return (self.index ~= nil) and "PASS" or "FAIL"
			end,
		},
		{
			name = "ticker",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return (self.ticker and not self.ticker:IsCancelled()) and "PASS" or "FAIL"
			end,
		},
		{
			name = "tracked",
			run = function()
				local unitCount = 0
				for _ in pairs(self.units) do
					unitCount = unitCount + 1
				end
				local stateCount = 0
				for _ in pairs(self.state) do
					stateCount = stateCount + 1
				end
				return "INFO", unitCount, stateCount
			end,
		},
	}

	local units = {}
	for unit in pairs(self.units) do
		table.insert(units, unit)
	end
	table.sort(units)

	for _, unit in ipairs(units) do
		table.insert(checks, {
			name = "icons " .. unit,
			run = function()
				local guid = self.units[unit]
				local plate = self.unitPlate[unit]
				local container = plate and self.containers[plate]
				if not container then
					return "SKIP", "no container"
				end

				local now = GetTime()
				local bucket = self.state[guid]
				if bucket then
					for _, rec in pairs(bucket) do
						if rec.expires >= now - 2 * TICK_INTERVAL and rec.expires <= now then
							return "SKIP", "expiring"
						end
					end
				end

				local profile = self.db.profile
				local n = #L.Active(self.state, guid, now, profile.maxIcons)

				local shown = 0
				for _, icon in ipairs(container.icons) do
					if icon:IsShown() then
						shown = shown + 1
					end
				end

				local ok = shown == n
				local pointsRestricted = false
				for i = 1, n do
					local icon = container.icons[i]
					if not icon or not icon:IsShown() then
						ok = false
						break
					end

					if math.abs(icon:GetWidth() - profile.iconSize) > 0.5 then
						ok = false
						break
					end

					local ptOk, point, relativeTo, relativePoint, x, y = readPoint(icon)
					if not ptOk then
						pointsRestricted = true
					else
						local expPoint, expRelPoint, expX, expY =
							L.Layout(profile.anchor, i, n, profile.iconSize, LAYOUT_SPACING, profile.x, profile.y)
						if
							point ~= expPoint
							or relativeTo ~= container
							or relativePoint ~= expRelPoint
							or issecretvalue(x)
							or issecretvalue(y)
							or math.abs(x - expX) > 0.5
							or math.abs(y - expY) > 0.5
						then
							ok = false
							break
						end
					end
				end

				if pointsRestricted then
					return ok and "PASS" or "FAIL", shown, n, "points restricted"
				end
				return ok and "PASS" or "FAIL", shown, n
			end,
		})

		table.insert(checks, {
			name = "container parent " .. unit,
			run = function()
				local plate = self.unitPlate[unit]
				local container = plate and self.containers[plate]
				if not container then
					return "SKIP", "no container"
				end
				return (container:GetParent() == plate) and "PASS" or "FAIL"
			end,
		})
	end

	table.insert(checks, {
		name = "no foreign icons",
		run = function()
			local plates = {}
			for _, plate in pairs(self.unitPlate) do
				plates[plate] = true
			end

			local foreign = 0
			for plate, container in pairs(self.containers) do
				if container:IsShown() and not plates[plate] then
					foreign = foreign + 1
				end
			end

			if foreign > 0 then
				return "FAIL", foreign
			end
			return "PASS"
		end,
	})

	return checks
end
