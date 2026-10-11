local addonName, ns = ...

local NameplateLogic = ns.NameplateLogic

local Nameplates = ns.addon:NewModule("Nameplates", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = false,
		width = 130,
		height = 10,
		nameSize = 10,
		castBar = true,
	},
}

local FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local SHIELD_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Small-Shield"
local CAST_BAR_HEIGHT = 8
local CAST_BAR_GAP = 2
local CAST_SHIELD_SIZE = 14

local CAST_EVENTS = {
	UNIT_SPELLCAST_START = "OnCastStart",
	UNIT_SPELLCAST_DELAYED = "OnCastStart",
	UNIT_SPELLCAST_CHANNEL_START = "OnChannelStart",
	UNIT_SPELLCAST_CHANNEL_UPDATE = "OnChannelStart",
	UNIT_SPELLCAST_STOP = "OnCastStop",
	UNIT_SPELLCAST_FAILED = "OnCastStop",
	UNIT_SPELLCAST_INTERRUPTED = "OnCastStop",
	UNIT_SPELLCAST_CHANNEL_STOP = "OnChannelStop",
	UNIT_SPELLCAST_INTERRUPTIBLE = "OnInterruptibleChanged",
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = "OnInterruptibleChanged",
}

function Nameplates:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Nameplates", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	self.units = {}
	self.unitPlates = {}
	self.plateFrames = setmetatable({}, { __mode = "k" })
	self.castMode = {}
	self.castEventsOn = false
end

function Nameplates:OnEnable()
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnUnitAdded")
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnUnitRemoved")
	self:RegisterEvent("UNIT_HEALTH", "OnUnitHealth")
	self:RegisterEvent("UNIT_MAXHEALTH", "OnUnitHealth")
	self:RegisterEvent("UNIT_NAME_UPDATE", "OnUnitNameUpdate")
	self:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")

	self:SetCastEventsEnabled(self.db.profile.castBar)

	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken
		if unit then
			self.units[unit] = true
			self:StyleUnit(unit)
		end
	end
end

function Nameplates:OnDisable()
	self:SetCastEventsEnabled(false)

	for _, frame in pairs(self.plateFrames) do
		frame:Hide()
	end
	for _, plate in pairs(self.unitPlates) do
		if plate.UnitFrame then
			plate.UnitFrame:SetAlpha(1)
		end
	end

	self.units = {}
	self.unitPlates = {}
	self.castMode = {}
end

function Nameplates:Refresh()
	if self.db.profile.enabled then
		self:Enable()
		self:SetCastEventsEnabled(self.db.profile.castBar)
		for _, frame in pairs(self.plateFrames) do
			self:ApplySize(frame)
		end
	else
		self:Disable()
	end
end

function Nameplates:OnUnitAdded(_, unit)
	self.units[unit] = true
	self:StyleUnit(unit)
end

function Nameplates:OnUnitRemoved(_, unit)
	self.units[unit] = nil
	self:UnstyleUnit(unit)
end

function Nameplates:OnUnitHealth(_, unit)
	if not self.units[unit] then
		return
	end
	local plate = self.unitPlates[unit]
	local frame = plate and self.plateFrames[plate]
	if frame then
		self:UpdateHealth(unit, frame)
	end
end

function Nameplates:OnUnitNameUpdate(_, unit)
	if not self.units[unit] then
		return
	end
	local plate = self.unitPlates[unit]
	local frame = plate and self.plateFrames[plate]
	if frame then
		self:UpdateName(unit, frame)
	end
end

function Nameplates:OnUnitFaction(_, unit)
	if not self.units[unit] then
		return
	end
	-- duels flip hostility on an already-shown plate
	self:StyleUnit(unit)
end

function Nameplates:OnTargetChanged()
	for unit, plate in pairs(self.unitPlates) do
		local frame = self.plateFrames[plate]
		if frame then
			self:UpdateHighlight(unit, frame)
		end
	end
end

function Nameplates:StyleUnit(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or plate:IsForbidden() then
		return
	end

	local canAttack = UnitCanAttack("player", unit)
	if issecretvalue(canAttack) or canAttack ~= true then
		self:UnstyleUnit(unit)
		return
	end

	self.unitPlates[unit] = plate

	local frame = self.plateFrames[plate]
	if not frame then
		frame = self:CreateStyledFrame(plate)
		self.plateFrames[plate] = frame
	end

	if plate.UnitFrame then
		plate.UnitFrame:SetAlpha(0)
	end

	self:ApplySize(frame)
	frame:Show()
	self:UpdateHealth(unit, frame)
	self:UpdateName(unit, frame)
	self:UpdateColor(unit, frame)
	self:UpdateHighlight(unit, frame)
	self:SyncCastBar(unit, frame)
end

function Nameplates:UnstyleUnit(unit)
	local plate = self.unitPlates[unit]
	self.unitPlates[unit] = nil
	self.castMode[unit] = nil

	if not plate then
		return
	end

	if plate.UnitFrame then
		plate.UnitFrame:SetAlpha(1)
	end

	local frame = self.plateFrames[plate]
	if frame then
		frame:Hide()
		frame.castBar:Hide()
	end
end

function Nameplates:CreateStyledFrame(plate)
	local frame = CreateFrame("Frame", nil, plate)
	frame:SetPoint("CENTER", plate, "CENTER")
	frame:Hide()

	local healthBar = CreateFrame("StatusBar", nil, frame)
	healthBar:SetAllPoints(frame)
	healthBar:SetStatusBarTexture(BAR_TEXTURE)
	healthBar:SetMinMaxValues(0, 1)

	local bg = healthBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(healthBar)
	bg:SetTexture(BAR_TEXTURE)
	bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)

	local highlight = frame:CreateTexture(nil, "OVERLAY")
	highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
	highlight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
	highlight:SetTexture(BAR_TEXTURE)
	highlight:SetVertexColor(1, 1, 1, 0.5)
	highlight:SetAlpha(0)

	local nameText = frame:CreateFontString(nil, "OVERLAY")
	nameText:SetPoint("BOTTOM", frame, "TOP", 0, 2)

	local castBar = CreateFrame("StatusBar", nil, frame)
	castBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, -CAST_BAR_GAP)
	castBar:SetPoint("TOPRIGHT", healthBar, "BOTTOMRIGHT", 0, -CAST_BAR_GAP)
	castBar:SetHeight(CAST_BAR_HEIGHT)
	castBar:SetStatusBarTexture(BAR_TEXTURE)
	castBar:SetStatusBarColor(0.9, 0.6, 0.1)
	castBar:Hide()

	local castBg = castBar:CreateTexture(nil, "BACKGROUND")
	castBg:SetAllPoints(castBar)
	castBg:SetTexture(BAR_TEXTURE)
	castBg:SetVertexColor(0.1, 0.1, 0.1, 0.8)

	local castText = castBar:CreateFontString(nil, "OVERLAY")
	castText:SetPoint("CENTER", castBar)

	local castShield = castBar:CreateTexture(nil, "OVERLAY")
	castShield:SetTexture(SHIELD_TEXTURE)
	castShield:SetSize(CAST_SHIELD_SIZE, CAST_SHIELD_SIZE)
	castShield:SetPoint("LEFT", castBar, "LEFT", 0, 0)
	castShield:SetAlpha(0)

	frame.healthBar = healthBar
	frame.highlight = highlight
	frame.nameText = nameText
	frame.castBar = castBar
	frame.castText = castText
	frame.castShield = castShield

	return frame
end

function Nameplates:ApplySize(frame)
	local profile = self.db.profile
	frame:SetSize(profile.width, profile.height)
	frame.nameText:SetFont(FONT, profile.nameSize, "OUTLINE")
	frame.castText:SetFont(FONT, profile.nameSize - 1, "OUTLINE")
end

function Nameplates:UpdateHealth(unit, frame)
	frame.healthBar:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.healthBar:SetValue(UnitHealth(unit))
end

function Nameplates:UpdateName(unit, frame)
	frame.nameText:SetText(UnitName(unit))
end

function Nameplates:UpdateColor(unit, frame)
	local reaction = UnitReaction(unit, "player")
	local isPlayer = UnitIsPlayer(unit)
	local classFile = select(2, UnitClass(unit))
	local tapDenied = UnitIsTapDenied(unit)

	if issecretvalue(reaction) then
		reaction = nil
	end
	if issecretvalue(isPlayer) then
		isPlayer = nil
	end
	if issecretvalue(classFile) then
		classFile = nil
	end
	if issecretvalue(tapDenied) then
		tapDenied = nil
	end

	local r, g, b = NameplateLogic.Color(reaction, isPlayer, classFile, tapDenied, RAID_CLASS_COLORS)
	frame.healthBar:SetStatusBarColor(r, g, b)
end

function Nameplates:UpdateHighlight(unit, frame)
	local isTarget = UnitIsUnit(unit, "target")
	if issecretvalue(isTarget) then
		frame.highlight:SetAlphaFromBoolean(isTarget, 1, 0)
	else
		frame.highlight:SetAlpha(isTarget and 1 or 0)
	end
end

function Nameplates:GetCastFrame(unit)
	if not self.units[unit] then
		return nil
	end
	local plate = self.unitPlates[unit]
	return plate and self.plateFrames[plate]
end

function Nameplates:ApplyShield(frame, notInterruptible)
	local shield = frame.castShield
	if issecretvalue(notInterruptible) then
		shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
	else
		shield:SetAlpha(notInterruptible and 1 or 0)
	end
end

function Nameplates:HideCastBar(unit, frame)
	self.castMode[unit] = nil
	frame.castBar:Hide()
end

function Nameplates:HideAllCastBars()
	for unit in pairs(self.castMode) do
		self.castMode[unit] = nil
	end
	for _, frame in pairs(self.plateFrames) do
		frame.castBar:Hide()
	end
end

function Nameplates:SetCastEventsEnabled(enable)
	if enable == self.castEventsOn then
		return
	end

	for event, handler in pairs(CAST_EVENTS) do
		if enable then
			self:RegisterEvent(event, handler)
		else
			self:UnregisterEvent(event)
		end
	end
	self.castEventsOn = enable

	if enable then
		for unit, plate in pairs(self.unitPlates) do
			local frame = self.plateFrames[plate]
			if frame then
				self:SyncCastBar(unit, frame)
			end
		end
	else
		self:HideAllCastBars()
	end
end

-- UnitCastingDuration/UnitChannelDuration may be secret; their nil-ness tells
-- us whether a cast is active, but secrets can't be nil-checked directly, so
-- fall back to the NeverSecret castBarID return when the duration itself is secret.
function Nameplates:IsCasting(unit)
	local d = UnitCastingDuration(unit)
	if not issecretvalue(d) then
		return d ~= nil
	end
	local castBarID = select(10, UnitCastingInfo(unit))
	if not issecretvalue(castBarID) then
		return castBarID ~= nil
	end
	return false
end

function Nameplates:IsChanneling(unit)
	local d = UnitChannelDuration(unit)
	if not issecretvalue(d) then
		return d ~= nil
	end
	local castBarID = select(11, UnitChannelInfo(unit))
	if not issecretvalue(castBarID) then
		return castBarID ~= nil
	end
	return false
end

function Nameplates:SyncCastBar(unit, frame)
	if not self.db.profile.castBar then
		self:HideCastBar(unit, frame)
		return
	end

	if self:IsCasting(unit) then
		self:OnCastStart(nil, unit)
		return
	end
	if self:IsChanneling(unit) then
		self:OnChannelStart(nil, unit)
		return
	end
	self:HideCastBar(unit, frame)
end

function Nameplates:OnCastStart(_, unit)
	local frame = self:GetCastFrame(unit)
	if not frame then
		return
	end

	self.castMode[unit] = "cast"
	local d = UnitCastingDuration(unit)
	frame.castBar:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
	frame.castBar:Show()

	local name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
	frame.castText:SetText(name)
	self:ApplyShield(frame, notInterruptible)
end

function Nameplates:OnChannelStart(_, unit)
	local frame = self:GetCastFrame(unit)
	if not frame then
		return
	end

	self.castMode[unit] = "channel"
	local d = UnitChannelDuration(unit)
	frame.castBar:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
	frame.castBar:Show()

	local name, _, _, _, _, _, notInterruptible = UnitChannelInfo(unit)
	frame.castText:SetText(name)
	self:ApplyShield(frame, notInterruptible)
end

function Nameplates:OnCastStop(_, unit)
	local frame = self:GetCastFrame(unit)
	if not frame then
		return
	end
	if self.castMode[unit] == "cast" then
		self:HideCastBar(unit, frame)
	end
end

function Nameplates:OnChannelStop(_, unit)
	local frame = self:GetCastFrame(unit)
	if not frame then
		return
	end
	if self.castMode[unit] == "channel" then
		self:HideCastBar(unit, frame)
	end
end

function Nameplates:OnInterruptibleChanged(_, unit)
	local frame = self:GetCastFrame(unit)
	if not frame then
		return
	end

	local mode = self.castMode[unit]
	if mode == "cast" then
		local _, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
		self:ApplyShield(frame, notInterruptible)
	elseif mode == "channel" then
		local _, _, _, _, _, _, notInterruptible = UnitChannelInfo(unit)
		self:ApplyShield(frame, notInterruptible)
	end
end

function Nameplates:GetOptions()
	return {
		type = "group",
		name = "Nameplates",
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
			width = {
				type = "range",
				name = "Width",
				order = 2,
				min = 60,
				max = 250,
				step = 1,
				get = function()
					return self.db.profile.width
				end,
				set = function(_, value)
					self.db.profile.width = value
					self:Refresh()
				end,
			},
			height = {
				type = "range",
				name = "Height",
				order = 3,
				min = 4,
				max = 30,
				step = 1,
				get = function()
					return self.db.profile.height
				end,
				set = function(_, value)
					self.db.profile.height = value
					self:Refresh()
				end,
			},
			nameSize = {
				type = "range",
				name = "Name size",
				order = 4,
				min = 6,
				max = 20,
				step = 1,
				get = function()
					return self.db.profile.nameSize
				end,
				set = function(_, value)
					self.db.profile.nameSize = value
					self:Refresh()
				end,
			},
			castBar = {
				type = "toggle",
				name = "Cast bar",
				order = 5,
				get = function()
					return self.db.profile.castBar
				end,
				set = function(_, value)
					self.db.profile.castBar = value
					self:Refresh()
				end,
			},
		},
	}
end
