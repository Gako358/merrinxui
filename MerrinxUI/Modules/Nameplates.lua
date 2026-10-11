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
		healthText = "percent",
		powerBar = false,
		powerHeight = 4,
		powerText = "none",
		debuffs = true,
		debuffsMineOnly = true,
		debuffAnchor = "TOP",
		debuffSize = 18,
		debuffMax = 4,
	},
}

local FONT = "Fonts\\FRIZQT__.TTF"
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local SHIELD_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Small-Shield"
local CAST_BAR_HEIGHT = 8
local CAST_BAR_GAP = 2
local CAST_SHIELD_SIZE = 14
local POWER_BAR_GAP = 1
local DEBUFF_SPACING = 2
local DEBUFF_COUNT_SIZE = 10

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

local POWER_EVENTS = {
	UNIT_POWER_UPDATE = "OnUnitPower",
	UNIT_MAXPOWER = "OnUnitPower",
	UNIT_DISPLAYPOWER = "OnUnitPower",
}

local AURA_EVENTS = {
	UNIT_AURA = "OnUnitAura",
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
	self:SetEventsEnabled(POWER_EVENTS, self.db.profile.powerBar)
	self:SetEventsEnabled(AURA_EVENTS, self.db.profile.debuffs)

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
		self:SetEventsEnabled(POWER_EVENTS, self.db.profile.powerBar)
		self:SetEventsEnabled(AURA_EVENTS, self.db.profile.debuffs)
		for _, frame in pairs(self.plateFrames) do
			self:ApplySize(frame)
		end
		for unit, plate in pairs(self.unitPlates) do
			local frame = self.plateFrames[plate]
			if frame then
				self:UpdateHealth(unit, frame)
				self:UpdatePower(unit, frame)
				self:UpdateDebuffs(unit, frame)
			end
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

function Nameplates:OnUnitPower(_, unit)
	local frame = self:GetCastFrame(unit)
	if frame then
		self:UpdatePower(unit, frame)
	end
end

function Nameplates:OnUnitAura(_, unit)
	local frame = self:GetCastFrame(unit)
	if frame then
		self:UpdateDebuffs(unit, frame)
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

	local isNewPlate = self.unitPlates[unit] == nil
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
	self:UpdatePower(unit, frame)
	self:UpdateDebuffs(unit, frame)

	if isNewPlate and ns.Debug:IsActive() then
		local isPlayer = UnitIsPlayer(unit)
		if not issecretvalue(isPlayer) and isPlayer == true then
			ns.Debug:Log("Nameplates", "style", unit)
		end
	end
end

function Nameplates:UnstyleUnit(unit)
	local plate = self.unitPlates[unit]
	self.unitPlates[unit] = nil
	self.castMode[unit] = nil

	if not plate then
		return
	end

	if ns.Debug:IsActive() then
		local isPlayer = UnitIsPlayer(unit)
		if not issecretvalue(isPlayer) and isPlayer == true then
			ns.Debug:Log("Nameplates", "unstyle", unit)
		end
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

	local healthText = healthBar:CreateFontString(nil, "OVERLAY")
	healthText:SetPoint("CENTER", healthBar)

	local highlight = frame:CreateTexture(nil, "OVERLAY")
	highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
	highlight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
	highlight:SetTexture(BAR_TEXTURE)
	highlight:SetVertexColor(1, 1, 1, 0.5)
	highlight:SetAlpha(0)

	local nameText = frame:CreateFontString(nil, "OVERLAY")
	nameText:SetPoint("BOTTOM", frame, "TOP", 0, 2)

	local powerBar = CreateFrame("StatusBar", nil, frame)
	powerBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, -POWER_BAR_GAP)
	powerBar:SetPoint("TOPRIGHT", healthBar, "BOTTOMRIGHT", 0, -POWER_BAR_GAP)
	powerBar:SetStatusBarTexture(BAR_TEXTURE)
	powerBar:SetMinMaxValues(0, 1)
	powerBar:Hide()

	local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
	powerBg:SetAllPoints(powerBar)
	powerBg:SetTexture(BAR_TEXTURE)
	powerBg:SetVertexColor(0.1, 0.1, 0.1, 0.8)

	local powerText = powerBar:CreateFontString(nil, "OVERLAY")
	powerText:SetPoint("RIGHT", powerBar, "RIGHT", -2, 0)

	local castBar = CreateFrame("StatusBar", nil, frame)
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
	frame.healthText = healthText
	frame.highlight = highlight
	frame.nameText = nameText
	frame.powerBar = powerBar
	frame.powerText = powerText
	frame.castBar = castBar
	frame.castText = castText
	frame.castShield = castShield
	frame.debuffIcons = {}

	return frame
end

function Nameplates:ApplySize(frame)
	local profile = self.db.profile
	frame:SetSize(profile.width, profile.height)
	frame.nameText:SetFont(FONT, profile.nameSize, "OUTLINE")
	frame.healthText:SetFont(FONT, profile.nameSize - 1, "OUTLINE")
	frame.powerText:SetFont(FONT, profile.nameSize - 1, "OUTLINE")
	frame.castText:SetFont(FONT, profile.nameSize - 1, "OUTLINE")
	frame.powerBar:SetHeight(profile.powerHeight)

	local castAnchor = profile.powerBar and frame.powerBar or frame.healthBar
	frame.castBar:ClearAllPoints()
	frame.castBar:SetPoint("TOPLEFT", castAnchor, "BOTTOMLEFT", 0, -CAST_BAR_GAP)
	frame.castBar:SetPoint("TOPRIGHT", castAnchor, "BOTTOMRIGHT", 0, -CAST_BAR_GAP)
end

function Nameplates:UpdateHealth(unit, frame)
	local health = UnitHealth(unit)
	frame.healthBar:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.healthBar:SetValue(health)
	self:SetValueText(
		frame.healthText,
		self.db.profile.healthText,
		health,
		UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
	)
end

function Nameplates:SetValueText(fs, mode, value, percent)
	fs:SetText(NameplateLogic.FormatValue(mode, AbbreviateNumbers(value), percent))
end

function Nameplates:UpdatePower(unit, frame)
	local profile = self.db.profile
	if not profile.powerBar then
		frame.powerBar:Hide()
		return
	end

	frame.powerBar:SetMinMaxValues(0, UnitPowerMax(unit))
	local power = UnitPower(unit)
	frame.powerBar:SetValue(power)

	local _, token = UnitPowerType(unit)
	if issecretvalue(token) then
		token = nil
	end
	frame.powerBar:SetStatusBarColor(NameplateLogic.PowerColor(token))

	self:SetValueText(
		frame.powerText,
		profile.powerText,
		power,
		UnitPowerPercent(unit, nil, false, CurveConstants.ScaleTo100)
	)
	frame.powerBar:Show()
end

function Nameplates:GetDebuffIcon(frame, i)
	local icon = frame.debuffIcons[i]
	if not icon then
		icon = CreateFrame("Frame", nil, frame)

		local texture = icon:CreateTexture(nil, "ARTWORK")
		texture:SetAllPoints(icon)
		icon.texture = texture

		local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
		cooldown:SetAllPoints(icon)
		icon.cooldown = cooldown

		local countOverlay = CreateFrame("Frame", nil, icon)
		countOverlay:SetAllPoints(icon)
		countOverlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)

		local count = countOverlay:CreateFontString(nil, "OVERLAY")
		count:SetPoint("BOTTOMRIGHT", icon)
		count:SetFont(FONT, DEBUFF_COUNT_SIZE, "OUTLINE")
		icon.count = count

		frame.debuffIcons[i] = icon
	end
	return icon
end

function Nameplates:UpdateDebuffs(unit, frame)
	local profile = self.db.profile
	if not profile.debuffs then
		for _, icon in pairs(frame.debuffIcons) do
			icon:Hide()
		end
		return
	end

	local filter = profile.debuffsMineOnly and "HARMFUL|PLAYER" or "HARMFUL"
	local auras = C_UnitAuras.GetUnitAuras(unit, filter, profile.debuffMax)
	local n = math.min(#auras, profile.debuffMax)

	local anchor = profile.debuffAnchor
	local relativeTo = frame
	if anchor == "BOTTOM" then
		if profile.castBar then
			relativeTo = frame.castBar
		elseif profile.powerBar then
			relativeTo = frame.powerBar
		else
			relativeTo = frame.healthBar
		end
	elseif anchor ~= "LEFT" and anchor ~= "RIGHT" then
		relativeTo = frame.nameText
	end

	for i = 1, n do
		local aura = auras[i]
		local icon = self:GetDebuffIcon(frame, i)
		icon:SetSize(profile.debuffSize, profile.debuffSize)

		local point, relPoint, x, y = NameplateLogic.DebuffLayout(anchor, i, n, profile.debuffSize, DEBUFF_SPACING)
		icon:ClearAllPoints()
		icon:SetPoint(point, relativeTo, relPoint, x, y)

		icon.texture:SetTexture(aura.icon)

		local duration = C_UnitAuras.GetAuraDuration(unit, aura.auraInstanceID)
		if issecretvalue(duration) or duration then
			icon.cooldown:SetCooldownFromDurationObject(duration, true)
		else
			icon.cooldown:Clear()
		end

		icon.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, aura.auraInstanceID))
		icon:Show()
	end

	for i = n + 1, #frame.debuffIcons do
		frame.debuffIcons[i]:Hide()
	end
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

	ns.Debug:Log("Nameplates", "cast events", enable)

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

function Nameplates:SetEventsEnabled(events, enable)
	for event, handler in pairs(events) do
		if enable then
			self:RegisterEvent(event, handler)
		else
			self:UnregisterEvent(event)
		end
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

function Nameplates:OnCastStart(event, unit)
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

	if event == "UNIT_SPELLCAST_START" and ns.Debug:IsActive() then
		local isTarget = UnitIsUnit(unit, "target")
		if not issecretvalue(isTarget) and isTarget == true then
			ns.Debug:Log("Nameplates", "cast", unit, self.castMode[unit])
		end
	end
end

function Nameplates:OnChannelStart(event, unit)
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

	if event == "UNIT_SPELLCAST_CHANNEL_START" and ns.Debug:IsActive() then
		local isTarget = UnitIsUnit(unit, "target")
		if not issecretvalue(isTarget) and isTarget == true then
			ns.Debug:Log("Nameplates", "cast", unit, self.castMode[unit])
		end
	end
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
			healthText = {
				type = "select",
				name = "Health text",
				order = 6,
				values = {
					none = "None",
					percent = "Percent",
					number = "Number",
					both = "Number and percent",
				},
				get = function()
					return self.db.profile.healthText
				end,
				set = function(_, value)
					self.db.profile.healthText = value
					self:Refresh()
				end,
			},
			powerBar = {
				type = "toggle",
				name = "Power bar",
				order = 7,
				get = function()
					return self.db.profile.powerBar
				end,
				set = function(_, value)
					self.db.profile.powerBar = value
					self:Refresh()
				end,
			},
			powerHeight = {
				type = "range",
				name = "Power bar height",
				order = 8,
				min = 2,
				max = 10,
				step = 1,
				get = function()
					return self.db.profile.powerHeight
				end,
				set = function(_, value)
					self.db.profile.powerHeight = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.powerBar
				end,
			},
			powerText = {
				type = "select",
				name = "Power text",
				order = 9,
				values = {
					none = "None",
					percent = "Percent",
					number = "Number",
					both = "Number and percent",
				},
				get = function()
					return self.db.profile.powerText
				end,
				set = function(_, value)
					self.db.profile.powerText = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.powerBar
				end,
			},
			debuffs = {
				type = "toggle",
				name = "Debuffs",
				order = 10,
				get = function()
					return self.db.profile.debuffs
				end,
				set = function(_, value)
					self.db.profile.debuffs = value
					self:Refresh()
				end,
			},
			debuffsMineOnly = {
				type = "toggle",
				name = "Only my debuffs",
				order = 11,
				get = function()
					return self.db.profile.debuffsMineOnly
				end,
				set = function(_, value)
					self.db.profile.debuffsMineOnly = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.debuffs
				end,
			},
			debuffAnchor = {
				type = "select",
				name = "Debuff anchor",
				order = 12,
				values = {
					TOP = "Top",
					BOTTOM = "Bottom",
					LEFT = "Left",
					RIGHT = "Right",
				},
				get = function()
					return self.db.profile.debuffAnchor
				end,
				set = function(_, value)
					self.db.profile.debuffAnchor = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.debuffs
				end,
			},
			debuffSize = {
				type = "range",
				name = "Debuff size",
				order = 13,
				min = 10,
				max = 40,
				step = 1,
				get = function()
					return self.db.profile.debuffSize
				end,
				set = function(_, value)
					self.db.profile.debuffSize = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.debuffs
				end,
			},
			debuffMax = {
				type = "range",
				name = "Max debuffs",
				order = 14,
				min = 1,
				max = 8,
				step = 1,
				get = function()
					return self.db.profile.debuffMax
				end,
				set = function(_, value)
					self.db.profile.debuffMax = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.debuffs
				end,
			},
		},
	}
end

function Nameplates:GetDebugChecks()
	local function getTargetFrame()
		local plate = C_NamePlate.GetNamePlateForUnit("target")
		local frame = plate and self.plateFrames[plate]
		if not frame or not frame:IsShown() then
			return nil, nil
		end
		return plate, frame
	end

	return {
		{
			name = "apis",
			run = function()
				local paths = {
					"UnitCastingDuration",
					"UnitChannelDuration",
					"C_UnitAuras.GetUnitAuras",
					"C_UnitAuras.GetAuraDuration",
					"C_UnitAuras.GetAuraApplicationDisplayCount",
					"UnitHealthPercent",
					"UnitPowerPercent",
					"CurveConstants.ScaleTo100",
					"AbbreviateNumbers",
					"Enum.StatusBarInterpolation",
					"Enum.StatusBarTimerDirection",
				}

				local missing = {}
				for _, path in ipairs(paths) do
					local obj = _G
					for part in path:gmatch("[^.]+") do
						if type(obj) ~= "table" then
							obj = nil
							break
						end
						obj = obj[part]
					end
					if obj == nil then
						table.insert(missing, path)
					end
				end

				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "styled plates",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local mismatches = 0
				local unknown = 0
				local total = 0

				for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
					local unit = plate.namePlateUnitToken
					if unit then
						total = total + 1
						local canAttack = UnitCanAttack("player", unit)
						local frame = self.plateFrames[plate]
						if issecretvalue(canAttack) then
							unknown = unknown + 1
						elseif canAttack == true and not plate:IsForbidden() then
							if not (frame and frame:IsShown()) then
								mismatches = mismatches + 1
							end
						elseif frame and frame:IsShown() then
							mismatches = mismatches + 1
						end
					end
				end

				return (mismatches == 0) and "PASS" or "FAIL", mismatches, unknown, total
			end,
		},
		{
			name = "target plate",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local plate, frame = getTargetFrame()
				if not frame then
					return "SKIP", "target not styled"
				end

				local profile = self.db.profile
				local width = frame:GetWidth()
				local height = frame:GetHeight()
				local _, nameSize = frame.nameText:GetFont()

				local ok = math.abs(width - profile.width) <= 0.5
					and math.abs(height - profile.height) <= 0.5
					and math.abs(nameSize - profile.nameSize) <= 0.5

				if not plate.UnitFrame then
					return (ok and "PASS" or "FAIL"), width, height, nameSize, "no UnitFrame"
				end

				local alpha = plate.UnitFrame:GetAlpha()
				if issecretvalue(alpha) then
					return (ok and "PASS" or "FAIL"), width, height, nameSize, "alpha secret"
				end

				ok = ok and alpha == 0
				return ok and "PASS" or "FAIL", width, height, nameSize, alpha
			end,
		},
		{
			name = "health colour",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local _, frame = getTargetFrame()
				if not frame then
					return "SKIP", "target not styled"
				end

				local unit = "target"
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

				local er, eg, eb = NameplateLogic.Color(reaction, isPlayer, classFile, tapDenied, RAID_CLASS_COLORS)
				local cr, cg, cb = frame.healthBar:GetStatusBarColor()

				local ok = math.abs(cr - er) <= 0.01 and math.abs(cg - eg) <= 0.01 and math.abs(cb - eb) <= 0.01
				return ok and "PASS" or "FAIL", cr, cg, cb, er, eg, eb
			end,
		},
		{
			name = "highlight",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local mismatches = 0
				local secretCount = 0
				local total = 0

				for unit, plate in pairs(self.unitPlates) do
					local frame = self.plateFrames[plate]
					if frame then
						total = total + 1
						local isTarget = UnitIsUnit(unit, "target")
						local alpha = frame.highlight:GetAlpha()
						if issecretvalue(isTarget) or issecretvalue(alpha) then
							secretCount = secretCount + 1
						else
							local expected = isTarget and 1 or 0
							if math.abs(alpha - expected) > 0.01 then
								mismatches = mismatches + 1
							end
						end
					end
				end

				if total > 0 and secretCount == total then
					return "INFO", mismatches, secretCount, total
				end
				return (mismatches == 0) and "PASS" or "FAIL", mismatches, secretCount, total
			end,
		},
		{
			name = "cast events",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local ok = self.castEventsOn == self.db.profile.castBar
				return ok and "PASS" or "FAIL", self.castEventsOn, self.db.profile.castBar
			end,
		},
		{
			name = "cast anchor",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local _, frame = getTargetFrame()
				if not frame then
					return "SKIP", "target not styled"
				end

				local profile = self.db.profile
				local expectedAnchor = profile.powerBar and frame.powerBar or frame.healthBar
				local point, relativeTo, relativePoint, x, y = frame.castBar:GetPoint(1)

				local ok = point == "TOPLEFT"
					and relativeTo == expectedAnchor
					and relativePoint == "BOTTOMLEFT"
					and math.abs(x) <= 0.5
					and math.abs(y - -CAST_BAR_GAP) <= 0.5

				return ok and "PASS" or "FAIL", point, relativePoint, x, y
			end,
		},
		{
			name = "target cast",
			run = function(ctx)
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local unit = "target"
				local plate = C_NamePlate.GetNamePlateForUnit("target")
				local token = plate and plate.namePlateUnitToken
				local mode = token and self.castMode[token]

				if mode == "cast" then
					local d = UnitCastingDuration(unit)
					local notInterruptible = select(8, UnitCastingInfo(unit))
					return "INFO", mode, issecretvalue(d), issecretvalue(notInterruptible)
				elseif mode == "channel" then
					local d = UnitChannelDuration(unit)
					local notInterruptible = select(7, UnitChannelInfo(unit))
					return "INFO", mode, issecretvalue(d), issecretvalue(notInterruptible)
				end

				return "INFO", "none"
			end,
		},
		{
			name = "health text",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local _, frame = getTargetFrame()
				if not frame then
					return "SKIP", "target not styled"
				end

				if self.db.profile.healthText == "none" then
					local text = frame.healthText:GetText()
					if issecretvalue(text) then
						return "INFO", "secret"
					end
					return (text == nil or text == "") and "PASS" or "FAIL", text
				end

				local shown = frame.healthText:IsShown()
				return shown and "PASS" or "FAIL", issecretvalue(frame.healthText:GetText())
			end,
		},
		{
			name = "power bar",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local _, frame = getTargetFrame()
				if not frame then
					return "SKIP", "target not styled"
				end

				local profile = self.db.profile
				local shown = frame.powerBar:IsShown()
				local ok = shown == profile.powerBar
				if shown then
					ok = ok and math.abs(frame.powerBar:GetHeight() - profile.powerHeight) <= 0.5
				end

				return ok and "PASS" or "FAIL", shown, profile.powerBar
			end,
		},
		{
			name = "power text",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local _, frame = getTargetFrame()
				if not frame then
					return "SKIP", "target not styled"
				end
				if not self.db.profile.powerBar then
					return "SKIP", "power bar off"
				end

				if self.db.profile.powerText == "none" then
					local text = frame.powerText:GetText()
					if issecretvalue(text) then
						return "INFO", "secret"
					end
					return (text == nil or text == "") and "PASS" or "FAIL", text
				end

				local shown = frame.powerText:IsShown()
				return shown and "PASS" or "FAIL", issecretvalue(frame.powerText:GetText())
			end,
		},
		{
			name = "debuffs",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local _, frame = getTargetFrame()
				if not frame then
					return "SKIP", "target not styled"
				end
				if not self.db.profile.debuffs then
					return "SKIP", "debuffs off"
				end

				local profile = self.db.profile
				local shown = 0
				for _, icon in pairs(frame.debuffIcons) do
					if icon:IsShown() then
						shown = shown + 1
					end
				end

				local anchor = profile.debuffAnchor
				local relativeTo = frame
				if anchor == "BOTTOM" then
					if profile.castBar then
						relativeTo = frame.castBar
					elseif profile.powerBar then
						relativeTo = frame.powerBar
					else
						relativeTo = frame.healthBar
					end
				elseif anchor ~= "LEFT" and anchor ~= "RIGHT" then
					relativeTo = frame.nameText
				end

				local n = shown
				local ok = shown <= profile.debuffMax
				for i = 1, shown do
					local icon = frame.debuffIcons[i]
					if not icon or not icon:IsShown() then
						ok = false
						break
					end
					if math.abs(icon:GetWidth() - profile.debuffSize) > 0.5 then
						ok = false
						break
					end

					local point, relTo, relPoint, x, y = icon:GetPoint(1)
					local expPoint, expRelPoint, expX, expY =
						NameplateLogic.DebuffLayout(anchor, i, n, profile.debuffSize, DEBUFF_SPACING)
					if
						point ~= expPoint
						or relTo ~= relativeTo
						or relPoint ~= expRelPoint
						or math.abs(x - expX) > 0.5
						or math.abs(y - expY) > 0.5
					then
						ok = false
						break
					end
				end

				local mine = C_UnitAuras.GetUnitAuras("target", "HARMFUL|PLAYER")
				local all = C_UnitAuras.GetUnitAuras("target", "HARMFUL")

				return ok and "PASS" or "FAIL", shown, mine and #mine or 0, all and #all or 0
			end,
		},
		{
			name = "secret flags",
			run = function(ctx)
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local unit = "target"
				local health = UnitHealth(unit)
				local healthMax = UnitHealthMax(unit)
				local healthPercent = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
				local power = UnitPower(unit)
				local powerMax = UnitPowerMax(unit)
				local powerPercent = UnitPowerPercent(unit, nil, false, CurveConstants.ScaleTo100)
				local _, powerToken = UnitPowerType(unit)
				local reaction = UnitReaction(unit, "player")
				local isTarget = UnitIsUnit(unit, "target")
				local canAttack = UnitCanAttack("player", unit)

				local mine = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|PLAYER")
				local mineAura = mine and mine[1]
				local mineIconSecret, mineDurationSecret, mineCountSecret = false, false, false
				if mineAura then
					mineIconSecret = issecretvalue(mineAura.icon)
					mineDurationSecret = issecretvalue(C_UnitAuras.GetAuraDuration(unit, mineAura.auraInstanceID))
					mineCountSecret =
						issecretvalue(C_UnitAuras.GetAuraApplicationDisplayCount(unit, mineAura.auraInstanceID))
				end

				local all = C_UnitAuras.GetUnitAuras(unit, "HARMFUL")
				local allAura = all and all[1]
				local allIconSecret, allDurationSecret, allCountSecret = false, false, false
				if allAura then
					allIconSecret = issecretvalue(allAura.icon)
					allDurationSecret = issecretvalue(C_UnitAuras.GetAuraDuration(unit, allAura.auraInstanceID))
					allCountSecret =
						issecretvalue(C_UnitAuras.GetAuraApplicationDisplayCount(unit, allAura.auraInstanceID))
				end

				return "INFO",
					issecretvalue(health),
					issecretvalue(healthMax),
					issecretvalue(healthPercent),
					issecretvalue(power),
					issecretvalue(powerMax),
					issecretvalue(powerPercent),
					issecretvalue(powerToken),
					issecretvalue(reaction),
					issecretvalue(isTarget),
					issecretvalue(canAttack),
					mineAura ~= nil,
					mineIconSecret,
					mineDurationSecret,
					mineCountSecret,
					allAura ~= nil,
					allIconSecret,
					allDurationSecret,
					allCountSecret
			end,
		},
	}
end
