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
		self:HandleUnit(plate.namePlateUnitToken)
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
	if not plate or plate:IsForbidden() then
		return
	end

	local isPlayer = UnitIsPlayer(unit)
	local canAttack = UnitCanAttack("player", unit)
	if issecretvalue(isPlayer) or issecretvalue(canAttack) or not (isPlayer == true and canAttack == true) then
		self:ClearUnit(unit)
		return
	end

	local guid = UnitGUID(unit)
	if issecretvalue(guid) or guid == nil then
		self:ClearUnit(unit)
		return
	end

	self.units[unit] = guid
	self.unitPlate[unit] = plate
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
	self:Render(unit)
end

function EnemyCooldowns:OnEnteringWorld()
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
