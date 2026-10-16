local addonName, ns = ...

local NameplateLogic = ns.NameplateLogic
local FontLogic = ns.FontLogic

local Nameplates = ns.addon:NewModule("Nameplates", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = false,
		width = 130,
		height = 10,
		nameSize = 10,
		font = FontLogic.GLOBAL,
		barTexture = FontLogic.GLOBAL,
		bgOpacity = 80,
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
		debuffX = 0,
		debuffY = 0,
		levelText = true,
		cc = true,
		ccSize = 26,
		ccMax = 2,
	},
}

local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local SHIELD_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Small-Shield"
local CAST_BAR_HEIGHT = 8
local CAST_BAR_GAP = 2
local CAST_SHIELD_SIZE = 14
local POWER_BAR_GAP = 1
local DEBUFF_SPACING = 2
local DEBUFF_GROUP = "debuffs"
local CC_GROUP = "cc"
local DEBUFF_COUNT_SIZE = 10
local LEVEL_GAP = 2

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

local LEVEL_EVENTS = {
	UNIT_LEVEL = "OnUnitLevel",
	UNIT_CLASSIFICATION_CHANGED = "OnUnitLevel",
	PLAYER_LEVEL_UP = "OnPlayerLevelUp",
}

local reapplyingAlpha = false

local function ZeroOwnedAlpha(unitFrame)
	if reapplyingAlpha or not Nameplates.ownedUnitFrames[unitFrame] then
		return false
	end
	reapplyingAlpha = true
	unitFrame:SetAlpha(0)
	reapplyingAlpha = false
	return true
end

local function OnUnitFrameSetAlpha(unitFrame)
	if ZeroOwnedAlpha(unitFrame) then
		Nameplates.alphaResets = Nameplates.alphaResets + 1
	end
end

local function OnUnitFrameSetAlphaFromBoolean(unitFrame)
	if ZeroOwnedAlpha(unitFrame) then
		Nameplates.alphaBoolResets = Nameplates.alphaBoolResets + 1
	end
end

function Nameplates:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Nameplates", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	self.units = {}
	self.unitPlates = {}
	self.plateFrames = setmetatable({}, { __mode = "k" })
	self.castMode = {}
	self.castEventsOn = false
	self.hookedUnitFrames = setmetatable({}, { __mode = "k" })
	self.ownedUnitFrames = setmetatable({}, { __mode = "k" })
	self.alphaResets = 0
	self.alphaBoolResets = 0
	self.debuffContainersInCombat = 0
	self.debuffResizePending = false
end

function Nameplates:OnEnable()
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnUnitAdded")
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnUnitRemoved")
	self:RegisterEvent("UNIT_HEALTH", "OnUnitHealth")
	self:RegisterEvent("UNIT_MAXHEALTH", "OnUnitHealth")
	self:RegisterEvent("UNIT_NAME_UPDATE", "OnUnitNameUpdate")
	self:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")

	self:SetCastEventsEnabled(self.db.profile.castBar)
	self:SetEventsEnabled(POWER_EVENTS, self.db.profile.powerBar)
	self:SetEventsEnabled(AURA_EVENTS, self.db.profile.debuffs or self.db.profile.cc)
	self:SetEventsEnabled(LEVEL_EVENTS, self.db.profile.levelText)

	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.unitToken
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
			self.ownedUnitFrames[plate.UnitFrame] = nil
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
		self:SetEventsEnabled(AURA_EVENTS, self.db.profile.debuffs or self.db.profile.cc)
		self:SetEventsEnabled(LEVEL_EVENTS, self.db.profile.levelText)
		for _, frame in pairs(self.plateFrames) do
			self:ApplySize(frame)
		end
		self:ApplyCountFonts()
		for unit, plate in pairs(self.unitPlates) do
			local frame = self.plateFrames[plate]
			if frame then
				self:UpdateHealth(unit, frame)
				self:UpdateLevel(unit, frame)
				self:UpdatePower(unit, frame)
				self:UpdateDebuffs(unit, frame)
				self:UpdateCC(unit, frame)
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

function Nameplates:OnUnitLevel(_, unit)
	if not self.units[unit] then
		return
	end
	local plate = self.unitPlates[unit]
	local frame = plate and self.plateFrames[plate]
	if frame then
		self:UpdateLevel(unit, frame)
	end
end

function Nameplates:OnPlayerLevelUp()
	for unit, plate in pairs(self.unitPlates) do
		local frame = self.plateFrames[plate]
		if frame then
			self:UpdateLevel(unit, frame)
		end
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

function Nameplates:OnMediaChanged(_, mediatype, key)
	local profile = self.db.profile
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", profile.font)) then
		for _, frame in pairs(self.plateFrames) do
			self:ApplySize(frame)
		end
		self:ApplyCountFonts()
	elseif mediatype == "statusbar" and (key == nil or key == ns.Media:Resolve("statusbar", profile.barTexture)) then
		for _, frame in pairs(self.plateFrames) do
			self:ApplySize(frame)
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
	if frame and frame.debuffs and self.db.profile.debuffs then
		frame.debuffs:UpdateAllAuras()
	end
	if frame and frame.cc and self.db.profile.cc then
		frame.cc:UpdateAllAuras()
	end
	if self.debuffResizePending then
		self:ApplyPendingDebuffResize()
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

	local unitFrame = plate.UnitFrame
	if unitFrame then
		if not self.hookedUnitFrames[unitFrame] then
			hooksecurefunc(unitFrame, "SetAlpha", OnUnitFrameSetAlpha)
			if type(unitFrame.SetAlphaFromBoolean) == "function" then
				hooksecurefunc(unitFrame, "SetAlphaFromBoolean", OnUnitFrameSetAlphaFromBoolean)
			end
			self.hookedUnitFrames[unitFrame] = true
		end
		self.ownedUnitFrames[unitFrame] = nil
		unitFrame:SetAlpha(0)
		self.ownedUnitFrames[unitFrame] = true
	end

	self:ApplySize(frame)
	frame:Show()
	self:UpdateHealth(unit, frame)
	self:UpdateName(unit, frame)
	self:UpdateLevel(unit, frame)
	self:UpdateColor(unit, frame)
	self:UpdateHighlight(unit, frame)
	self:SyncCastBar(unit, frame)
	self:UpdatePower(unit, frame)
	self:UpdateDebuffs(unit, frame)
	self:UpdateCC(unit, frame)

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
		self.ownedUnitFrames[plate.UnitFrame] = nil
		plate.UnitFrame:SetAlpha(1)
	end

	local frame = self.plateFrames[plate]
	if frame then
		frame:Hide()
		frame.castBar:Hide()
	end
end

-- CustomAuraButtonTemplate has no size or regions; the container only fills in what we register here
local initializedDebuffButtons = setmetatable({}, { __mode = "k" })

local function InitializeDebuffButton(button, size)
	if initializedDebuffButtons[button] then
		return
	end

	button:SetSize(size, size)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	button:SetIcon(icon)

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints(button)
	button:SetDurationCooldown(cooldown)

	local countOverlay = CreateFrame("Frame", nil, button)
	countOverlay:SetAllPoints(button)
	countOverlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)

	local count = countOverlay:CreateFontString(nil, "OVERLAY")
	count:SetPoint("BOTTOMRIGHT", button)
	initializedDebuffButtons[button] = count
	ns.Media:SetFont(count, Nameplates.db.profile.font, DEBUFF_COUNT_SIZE, "OUTLINE")
	button:SetApplicationCount(count)
end

local function ResizeAuraButtons(container, group, size)
	if C_Secrets.ShouldAurasBeSecret() then
		return
	end
	for i = 1, container:GetAuraGroupFrameCount(group) do
		container:GetAuraGroupFrame(group, i):SetSize(size, size)
	end
end

function Nameplates:ApplyCountFonts()
	if C_Secrets.ShouldAurasBeSecret() then
		self.debuffResizePending = true
		ns.Combat:Run("Nameplates:debuffSize", function()
			self:ApplyPendingDebuffResize()
		end)
		return
	end
	for _, count in pairs(initializedDebuffButtons) do
		ns.Media:SetFont(count, self.db.profile.font, DEBUFF_COUNT_SIZE, "OUTLINE")
	end
end

function Nameplates:ApplyPendingDebuffResize()
	if not self.debuffResizePending or C_Secrets.ShouldAurasBeSecret() then
		return
	end
	for _, plateFrame in pairs(self.plateFrames) do
		if plateFrame.debuffs then
			ResizeAuraButtons(plateFrame.debuffs, DEBUFF_GROUP, self.db.profile.debuffSize)
		end
		if plateFrame.cc then
			ResizeAuraButtons(plateFrame.cc, CC_GROUP, self.db.profile.ccSize)
		end
	end
	self:ApplyCountFonts()
	self.debuffResizePending = false
end

local function CreateAuraContainer(frame, group, filter, maxCount, size)
	local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
	-- parsing and layout run from a run-when-visible OnUpdate, which needs a rect; layout replaces this size
	container:SetPoint("CENTER", frame, "CENTER")
	container:SetSize(1, 1)
	container:Hide()
	container:AddAuraGroup(group, filter, {
		maxFrameCount = maxCount,
		initializeFrame = function(button)
			local liveSize = (group == CC_GROUP) and Nameplates.db.profile.ccSize or Nameplates.db.profile.debuffSize
			InitializeDebuffButton(button, liveSize)
		end,
		layout = {
			elementWidth = size,
			elementHeight = size,
			elementSpacing = DEBUFF_SPACING,
		},
	})
	return container
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
	bg:SetVertexColor(0.1, 0.1, 0.1, 1)

	local healthText = healthBar:CreateFontString(nil, "OVERLAY")
	healthText:SetPoint("CENTER", healthBar)

	local levelText = frame:CreateFontString(nil, "OVERLAY")
	levelText:SetPoint("LEFT", healthBar, "RIGHT", LEVEL_GAP, 0)

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
	powerBg:SetVertexColor(0.1, 0.1, 0.1, 1)

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
	castBg:SetVertexColor(0.1, 0.1, 0.1, 1)

	local castText = castBar:CreateFontString(nil, "OVERLAY")
	castText:SetPoint("CENTER", castBar)

	local castShield = castBar:CreateTexture(nil, "OVERLAY")
	castShield:SetTexture(SHIELD_TEXTURE)
	castShield:SetSize(CAST_SHIELD_SIZE, CAST_SHIELD_SIZE)
	castShield:SetPoint("LEFT", castBar, "LEFT", 0, 0)
	castShield:SetAlpha(0)

	frame.healthBar = healthBar
	frame.healthBg = bg
	frame.healthText = healthText
	frame.levelText = levelText
	frame.highlight = highlight
	frame.nameText = nameText
	frame.powerBar = powerBar
	frame.powerBg = powerBg
	frame.powerText = powerText
	frame.castBar = castBar
	frame.castBg = castBg
	frame.castText = castText
	frame.castShield = castShield

	local profile = self.db.profile
	local ok, debuffs = pcall(
		CreateAuraContainer,
		frame,
		DEBUFF_GROUP,
		NameplateLogic.DebuffFilter(profile.debuffsMineOnly, profile.cc),
		profile.debuffMax,
		profile.debuffSize
	)
	if ok then
		frame.debuffs = debuffs
		if InCombatLockdown() then
			self.debuffContainersInCombat = self.debuffContainersInCombat + 1
		end
	elseif self.debuffContainerError == nil then
		self.debuffContainerError = debuffs
	end

	local ccOk, cc =
		pcall(CreateAuraContainer, frame, CC_GROUP, NameplateLogic.CC_FILTER, profile.ccMax, profile.ccSize)
	if ccOk then
		frame.cc = cc
		if InCombatLockdown() then
			self.debuffContainersInCombat = self.debuffContainersInCombat + 1
		end
	elseif self.ccContainerError == nil then
		self.ccContainerError = cc
	end

	return frame
end

function Nameplates:ApplySize(frame)
	local profile = self.db.profile
	frame:SetSize(profile.width, profile.height)
	frame.healthBg:SetAlpha(profile.bgOpacity / 100)
	frame.powerBg:SetAlpha(profile.bgOpacity / 100)
	frame.castBg:SetAlpha(profile.bgOpacity / 100)
	local _, namePath = ns.Media:SetFont(frame.nameText, profile.font, profile.nameSize, "OUTLINE")
	self.appliedFont = namePath
	ns.Media:SetFont(frame.healthText, profile.font, profile.nameSize - 1, "OUTLINE")
	ns.Media:SetFont(frame.levelText, profile.font, profile.nameSize - 1, "OUTLINE")
	ns.Media:SetFont(frame.powerText, profile.font, profile.nameSize - 1, "OUTLINE")
	ns.Media:SetFont(frame.castText, profile.font, profile.nameSize - 1, "OUTLINE")
	frame.powerBar:SetHeight(profile.powerHeight)

	local castAnchor = profile.powerBar and frame.powerBar or frame.healthBar
	frame.castBar:ClearAllPoints()
	frame.castBar:SetPoint("TOPLEFT", castAnchor, "BOTTOMLEFT", 0, -CAST_BAR_GAP)
	frame.castBar:SetPoint("TOPRIGHT", castAnchor, "BOTTOMRIGHT", 0, -CAST_BAR_GAP)

	-- SetStatusBarTexture replaces the bar's texture object and resets its vertex colour, so
	-- only touch the bars when the resolved path actually changes, and restore colours after
	local barPath = ns.Media:Fetch("statusbar", profile.barTexture) or BAR_TEXTURE
	if barPath ~= frame.barPath then
		local hr, hg, hb = frame.healthBar:GetStatusBarColor()
		local pr, pg, pb = frame.powerBar:GetStatusBarColor()

		barPath = ns.Media:SetStatusBarTexture(frame.healthBar, profile.barTexture)
		ns.Media:SetStatusBarTexture(frame.powerBar, profile.barTexture)
		ns.Media:SetStatusBarTexture(frame.castBar, profile.barTexture)

		frame.healthBar:SetStatusBarColor(hr, hg, hb)
		frame.powerBar:SetStatusBarColor(pr, pg, pb)
		frame.castBar:SetStatusBarColor(0.9, 0.6, 0.1)

		frame.barPath = barPath
	end
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

local function DebuffAnchorFrame(frame, profile)
	local anchor = profile.debuffAnchor
	local relativeTo
	if anchor == "BOTTOM" then
		if profile.castBar then
			relativeTo = frame.castBar
		elseif profile.powerBar then
			relativeTo = frame.powerBar
		else
			relativeTo = frame.healthBar
		end
	elseif anchor == "RIGHT" then
		relativeTo = profile.levelText and frame.levelText or frame
	elseif anchor == "LEFT" then
		relativeTo = (profile.cc and frame.cc) or frame
	else
		relativeTo = frame.nameText
	end
	return relativeTo
end

function Nameplates:UpdateDebuffs(unit, frame)
	local debuffs = frame.debuffs
	if not debuffs then
		return
	end
	local profile = self.db.profile
	if not profile.debuffs then
		debuffs:Hide()
		return
	end

	local anchor = profile.debuffAnchor
	local relativeTo = DebuffAnchorFrame(frame, profile)
	local filter = NameplateLogic.DebuffFilter(profile.debuffsMineOnly, profile.cc and frame.cc ~= nil)

	local point, relPoint, x, y = NameplateLogic.DebuffLayout(anchor, 1, 1, profile.debuffSize, DEBUFF_SPACING)
	debuffs:ClearAllPoints()
	debuffs:SetPoint(point, relativeTo, relPoint, x + profile.debuffX, y + profile.debuffY)
	debuffs:SetAuraGroupFilterString(DEBUFF_GROUP, filter)
	debuffs:SetAuraGroupMaxFrameCount(DEBUFF_GROUP, profile.debuffMax)
	debuffs:SetAuraGroupLayout(DEBUFF_GROUP, {
		elementWidth = profile.debuffSize,
		elementHeight = profile.debuffSize,
		elementSpacing = DEBUFF_SPACING,
	})
	debuffs:SetUnit(unit)
	debuffs:UpdateAllAuras()
	debuffs:Show()

	-- buttons deny tainted access while auras are secret, so the resize is retried until auras stop being secret
	if C_Secrets.ShouldAurasBeSecret() then
		self.debuffResizePending = true
		ns.Combat:Run("Nameplates:debuffSize", function()
			self:ApplyPendingDebuffResize()
		end)
	else
		ResizeAuraButtons(debuffs, DEBUFF_GROUP, profile.debuffSize)
		self:ApplyPendingDebuffResize()
	end
end

function Nameplates:UpdateCC(unit, frame)
	local cc = frame.cc
	if not cc then
		return
	end
	local profile = self.db.profile
	if not profile.cc then
		cc:Hide()
		return
	end

	local point, relPoint, x, y = NameplateLogic.DebuffLayout("LEFT", 1, 1, profile.ccSize, DEBUFF_SPACING)
	cc:ClearAllPoints()
	cc:SetPoint(point, frame, relPoint, x, y)
	cc:SetAuraGroupFilterString(CC_GROUP, NameplateLogic.CC_FILTER)
	cc:SetAuraGroupMaxFrameCount(CC_GROUP, profile.ccMax)
	cc:SetAuraGroupLayout(CC_GROUP, {
		elementWidth = profile.ccSize,
		elementHeight = profile.ccSize,
		elementSpacing = DEBUFF_SPACING,
	})
	cc:SetUnit(unit)
	cc:UpdateAllAuras()
	cc:Show()

	-- buttons deny tainted access while auras are secret, so the resize is retried until auras stop being secret
	if C_Secrets.ShouldAurasBeSecret() then
		self.debuffResizePending = true
		ns.Combat:Run("Nameplates:debuffSize", function()
			self:ApplyPendingDebuffResize()
		end)
	else
		ResizeAuraButtons(cc, CC_GROUP, profile.ccSize)
		self:ApplyPendingDebuffResize()
	end
end

function Nameplates:UpdateName(unit, frame)
	frame.nameText:SetText(UnitName(unit))
end

function Nameplates:UpdateLevel(unit, frame)
	if not self.db.profile.levelText then
		frame.levelText:SetText(nil)
		return
	end

	local level = UnitEffectiveLevel(unit)
	local classification = UnitClassification(unit)
	if issecretvalue(level) then
		level = nil
	end
	if issecretvalue(classification) then
		classification = nil
	end

	local color = nil
	if type(level) == "number" and level > 0 then
		color = GetCreatureDifficultyColor(level)
	end

	frame.levelText:SetTextColor(NameplateLogic.LevelColor(level, classification, color))
	frame.levelText:SetText(NameplateLogic.LevelText(level, classification))
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
			debuffX = {
				type = "range",
				name = "Debuff X offset",
				order = 16,
				min = -100,
				max = 100,
				step = 1,
				get = function()
					return self.db.profile.debuffX
				end,
				set = function(_, value)
					self.db.profile.debuffX = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.debuffs
				end,
			},
			debuffY = {
				type = "range",
				name = "Debuff Y offset",
				order = 17,
				min = -100,
				max = 100,
				step = 1,
				get = function()
					return self.db.profile.debuffY
				end,
				set = function(_, value)
					self.db.profile.debuffY = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.debuffs
				end,
			},
			cc = {
				type = "toggle",
				name = "CC icons",
				order = 18,
				get = function()
					return self.db.profile.cc
				end,
				set = function(_, value)
					self.db.profile.cc = value
					self:Refresh()
				end,
			},
			ccSize = {
				type = "range",
				name = "CC icon size",
				order = 19,
				min = 10,
				max = 48,
				step = 1,
				get = function()
					return self.db.profile.ccSize
				end,
				set = function(_, value)
					self.db.profile.ccSize = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.cc
				end,
			},
			ccMax = {
				type = "range",
				name = "Max CC icons",
				order = 20,
				min = 1,
				max = 4,
				step = 1,
				get = function()
					return self.db.profile.ccMax
				end,
				set = function(_, value)
					self.db.profile.ccMax = value
					self:Refresh()
				end,
				disabled = function()
					return not self.db.profile.cc
				end,
			},
			levelText = {
				type = "toggle",
				name = "Show level",
				order = 15,
				get = function()
					return self.db.profile.levelText
				end,
				set = function(_, value)
					self.db.profile.levelText = value
					self:Refresh()
				end,
			},
			font = {
				type = "select",
				name = "Font",
				order = 21,
				dialogControl = "LSM30_Font",
				values = function()
					return ns.Media:Values("font", self.db.profile.font)
				end,
				get = function()
					return self.db.profile.font
				end,
				set = function(_, value)
					self.db.profile.font = value
					self:Refresh()
				end,
			},
			barTexture = {
				type = "select",
				name = "Bar texture",
				order = 22,
				dialogControl = "LSM30_Statusbar",
				values = function()
					return ns.Media:Values("statusbar", self.db.profile.barTexture)
				end,
				get = function()
					return self.db.profile.barTexture
				end,
				set = function(_, value)
					self.db.profile.barTexture = value
					self:Refresh()
				end,
			},
			bgOpacity = {
				type = "range",
				name = "Background opacity",
				order = 23,
				min = 0,
				max = 100,
				step = 5,
				get = function()
					return self.db.profile.bgOpacity
				end,
				set = function(_, value)
					self.db.profile.bgOpacity = value
					self:Refresh()
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

	local function normalizePath(path)
		if type(path) ~= "string" then
			return path
		end
		return path:lower():gsub("/", "\\")
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
					"C_Secrets.ShouldAurasBeSecret",
					"UnitHealthPercent",
					"UnitPowerPercent",
					"CurveConstants.ScaleTo100",
					"AbbreviateNumbers",
					"Enum.StatusBarInterpolation",
					"Enum.StatusBarTimerDirection",
					"UnitEffectiveLevel",
					"UnitClassification",
					"GetCreatureDifficultyColor",
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
					local unit = plate.unitToken
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
			name = "plate tokens",
			run = function()
				local plates, resolved, frameUnit, forbidden = 0, 0, 0, 0
				for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
					if plate:IsForbidden() then
						forbidden = forbidden + 1
					else
						plates = plates + 1
						local unit = plate.unitToken
						if unit and C_NamePlate.GetNamePlateForUnit(unit) == plate then
							resolved = resolved + 1
						end
						if plate.UnitFrame and plate.UnitFrame.unit then
							frameUnit = frameUnit + 1
						end
					end
				end
				if plates == 0 then
					return "SKIP", "no plates"
				end
				return (resolved == plates) and "PASS" or "FAIL", plates, resolved, frameUnit, forbidden
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
					return (ok and "PASS" or "FAIL"),
						width,
						height,
						nameSize,
						"alpha secret",
						self.hookedUnitFrames[plate.UnitFrame] == true,
						self.ownedUnitFrames[plate.UnitFrame] == true,
						self.alphaResets,
						self.alphaBoolResets
				end

				ok = ok and alpha == 0
				return ok and "PASS" or "FAIL",
					width,
					height,
					nameSize,
					alpha,
					self.hookedUnitFrames[plate.UnitFrame] == true,
					self.ownedUnitFrames[plate.UnitFrame] == true,
					self.alphaResets,
					self.alphaBoolResets
			end,
		},
		{
			name = "blizzard auras",
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

				local unitFrame = plate.UnitFrame
				local auras = unitFrame and unitFrame.AurasFrame
				if not auras then
					return "SKIP", "no AurasFrame"
				end

				local isChild = auras:GetParent() == unitFrame
				local visible = auras:IsVisible()
				local alpha = auras:GetEffectiveAlpha()
				if issecretvalue(alpha) or issecretvalue(visible) then
					return "INFO", isChild, "secret"
				end
				return (alpha == 0 or not visible) and "PASS" or "FAIL", isChild, alpha, visible
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
				local ptOk, point, relativeTo, relativePoint, x, y = readPoint(frame.castBar)
				if not ptOk then
					return "SKIP", "restricted geometry"
				end

				local ok = point == "TOPLEFT"
					and relativeTo == expectedAnchor
					and relativePoint == "BOTTOMLEFT"
					and not issecretvalue(x)
					and not issecretvalue(y)
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
				local token = plate and plate.unitToken
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
			name = "level",
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

				if not self.db.profile.levelText then
					local text = frame.levelText:GetText()
					return (text == nil or text == "") and "PASS" or "FAIL", false
				end

				local text = frame.levelText:GetText()
				if issecretvalue(text) then
					return "INFO", "secret"
				end

				local unit = "target"
				local level = UnitEffectiveLevel(unit)
				local classification = UnitClassification(unit)
				if issecretvalue(level) then
					level = nil
				end
				if issecretvalue(classification) then
					classification = nil
				end

				local color = nil
				if type(level) == "number" and level > 0 then
					color = GetCreatureDifficultyColor(level)
				end

				local expected = NameplateLogic.LevelText(level, classification)
				local er, eg, eb = NameplateLogic.LevelColor(level, classification, color)
				local cr, cg, cb = frame.levelText:GetTextColor()

				local textOk = text == expected or (expected == nil and (text == nil or text == ""))
				local ok = textOk
					and math.abs(cr - er) <= 0.01
					and math.abs(cg - eg) <= 0.01
					and math.abs(cb - eb) <= 0.01

				local pointsRestricted = false
				local ptOk, point, relTo, relPoint, x, y = readPoint(frame.levelText)
				if not ptOk then
					pointsRestricted = true
				elseif
					point ~= "LEFT"
					or relTo ~= frame.healthBar
					or relPoint ~= "RIGHT"
					or issecretvalue(x)
					or issecretvalue(y)
					or math.abs(x - LEVEL_GAP) > 0.5
					or math.abs(y) > 0.5
				then
					ok = false
				end

				if pointsRestricted then
					return ok and "PASS" or "FAIL",
						text,
						expected,
						level,
						classification,
						cr,
						cg,
						cb,
						er,
						eg,
						eb,
						"points restricted"
				end
				return ok and "PASS" or "FAIL", text, expected, level, classification, cr, cg, cb, er, eg, eb
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
				if not frame.debuffs then
					return "FAIL", "no container", self.debuffContainerError
				end

				local debuffs = frame.debuffs
				local profile = self.db.profile
				local shown = debuffs:IsShown() == true

				local anchor = profile.debuffAnchor
				local relativeTo = DebuffAnchorFrame(frame, profile)

				local ok = shown
				local pointsRestricted = false
				local ptOk, point, relTo, relPoint, x, y = readPoint(debuffs)
				if not ptOk then
					pointsRestricted = true
				else
					local expPoint, expRelPoint, expX, expY =
						NameplateLogic.DebuffLayout(anchor, 1, 1, profile.debuffSize, DEBUFF_SPACING)
					expX = expX + profile.debuffX
					expY = expY + profile.debuffY
					if
						point ~= expPoint
						or relTo ~= relativeTo
						or relPoint ~= expRelPoint
						or issecretvalue(x)
						or issecretvalue(y)
						or math.abs(x - expX) > 0.5
						or math.abs(y - expY) > 0.5
					then
						ok = false
					end
				end

				local mineCount, allCount = "auras secret", "auras secret"
				if not C_Secrets.ShouldAurasBeSecret() then
					local mine = C_UnitAuras.GetUnitAuras("target", "HARMFUL|PLAYER")
					local all = C_UnitAuras.GetUnitAuras("target", "HARMFUL")
					mineCount = mine and #mine or 0
					allCount = all and #all or 0
				end

				if pointsRestricted then
					return ok and "PASS" or "FAIL", shown, mineCount, allCount, "points restricted"
				end
				return ok and "PASS" or "FAIL", shown, mineCount, allCount
			end,
		},
		{
			name = "debuff icons",
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
				if not self.db.profile.debuffs then
					return "SKIP", "debuffs off"
				end
				if not frame.debuffs then
					return "SKIP", "no container"
				end

				local debuffs = frame.debuffs
				local profile = self.db.profile
				local owned = debuffs:GetAuraGroupFrameCount(DEBUFF_GROUP)
				local unit = debuffs:GetUnit()
				local bound = not issecretvalue(owned)
					and owned > 0
					and not issecretvalue(unit)
					and unit == plate.unitToken
				local protected = debuffs:IsProtected()

				local sizeRead, width, height = pcall(debuffs.GetSize, debuffs)
				if not sizeRead or issecretvalue(width) or issecretvalue(height) then
					return bound and "INFO" or "FAIL",
						sizeRead and "size secret" or "size restricted",
						owned,
						bound,
						protected,
						self.debuffContainersInCombat
				end

				local size = profile.debuffSize
				local count = 0
				if width > 1.5 or height > 1.5 then
					count = math.floor((width + DEBUFF_SPACING) / (size + DEBUFF_SPACING) + 0.5)
				end
				local ok = bound and count <= profile.debuffMax
				if count > 0 then
					ok = ok
						and math.abs(height - size) <= 0.5
						and math.abs(width - (count * size + (count - 1) * DEBUFF_SPACING)) <= 0.5
				end

				local status = ok and "PASS" or "FAIL"
				local expected = "auras secret"
				if C_Secrets.ShouldAurasBeSecret() then
					if ok then
						status = "INFO"
					end
				else
					local auras = C_UnitAuras.GetUnitAuras(
						"target",
						NameplateLogic.DebuffFilter(profile.debuffsMineOnly, profile.cc and frame.cc ~= nil)
					)
					expected = math.min(auras and #auras or 0, profile.debuffMax)
					if count ~= expected then
						status = "FAIL"
					end
				end
				return status, count, width, height, expected, owned, bound, protected, self.debuffContainersInCombat
			end,
		},
		{
			name = "cc",
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
				if not self.db.profile.cc then
					return "SKIP", "cc off"
				end
				if not frame.cc then
					return "FAIL", "no container", self.ccContainerError
				end

				local cc = frame.cc
				local shown = cc:IsShown() == true

				local ok = shown
				local pointsRestricted = false
				local ptOk, point, relTo, relPoint, x, y = readPoint(cc)
				if not ptOk then
					pointsRestricted = true
				elseif
					point ~= "RIGHT"
					or relTo ~= frame
					or relPoint ~= "LEFT"
					or issecretvalue(x)
					or issecretvalue(y)
					or math.abs(x - -2) > 0.5
					or math.abs(y) > 0.5
				then
					ok = false
				end

				local ccCount = "auras secret"
				if not C_Secrets.ShouldAurasBeSecret() then
					local auras = C_UnitAuras.GetUnitAuras("target", NameplateLogic.CC_FILTER)
					ccCount = auras and #auras or 0
				end

				if pointsRestricted then
					return ok and "PASS" or "FAIL", shown, ccCount, "points restricted"
				end
				return ok and "PASS" or "FAIL", shown, ccCount
			end,
		},
		{
			name = "cc icons",
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
				if not self.db.profile.cc then
					return "SKIP", "cc off"
				end
				if not frame.cc then
					return "SKIP", "no container"
				end

				local cc = frame.cc
				local profile = self.db.profile
				local owned = cc:GetAuraGroupFrameCount(CC_GROUP)
				local unit = cc:GetUnit()
				local bound = not issecretvalue(owned)
					and owned > 0
					and not issecretvalue(unit)
					and unit == plate.unitToken
				local protected = cc:IsProtected()

				local sizeRead, width, height = pcall(cc.GetSize, cc)
				if not sizeRead or issecretvalue(width) or issecretvalue(height) then
					return bound and "INFO" or "FAIL",
						sizeRead and "size secret" or "size restricted",
						owned,
						bound,
						protected
				end

				local size = profile.ccSize
				local count = 0
				if width > 1.5 or height > 1.5 then
					count = math.floor((width + DEBUFF_SPACING) / (size + DEBUFF_SPACING) + 0.5)
				end
				local ok = bound and count <= profile.ccMax
				if count > 0 then
					ok = ok
						and math.abs(height - size) <= 0.5
						and math.abs(width - (count * size + (count - 1) * DEBUFF_SPACING)) <= 0.5
				end

				local status = ok and "PASS" or "FAIL"
				local expected = "auras secret"
				if C_Secrets.ShouldAurasBeSecret() then
					if ok then
						status = "INFO"
					end
				else
					local auras = C_UnitAuras.GetUnitAuras("target", NameplateLogic.CC_FILTER)
					expected = math.min(auras and #auras or 0, profile.ccMax)
					if count ~= expected then
						status = "FAIL"
					end
				end
				return status, count, width, height, expected, owned, bound, protected
			end,
		},
		{
			name = "cc filters",
			run = function(ctx)
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end
				if C_Secrets.ShouldAurasBeSecret() then
					return "SKIP", "auras secret"
				end

				local filters = {
					"HARMFUL|PLAYER",
					"HARMFUL|PLAYER|CROWD_CONTROL",
					"HARMFUL|PLAYER|!CROWD_CONTROL",
					"HARMFUL",
					"HARMFUL|CROWD_CONTROL",
					"HARMFUL|!CROWD_CONTROL",
				}

				local counts = {}
				local hadError = false
				for i, filter in ipairs(filters) do
					local ok, result = pcall(C_UnitAuras.GetUnitAuras, "target", filter)
					if ok then
						counts[i] = result and #result or 0
					else
						counts[i] = result
						hadError = true
					end
				end

				local function sumOk(all, a, b)
					return type(all) == "number" and type(a) == "number" and type(b) == "number" and all == a + b
				end

				local ok = not hadError
					and sumOk(counts[1], counts[2], counts[3])
					and sumOk(counts[4], counts[5], counts[6])

				return ok and "PASS" or "FAIL", counts[1], counts[2], counts[3], counts[4], counts[5], counts[6]
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

				local aurasSecret = C_Secrets.ShouldAurasBeSecret()
				local mineAura, allAura = nil, nil
				local mineIconSecret, mineDurationSecret, mineCountSecret = false, false, false
				local allIconSecret, allDurationSecret, allCountSecret = false, false, false
				if not aurasSecret then
					local mine = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|PLAYER")
					mineAura = mine and mine[1]
					if mineAura then
						mineIconSecret = issecretvalue(mineAura.icon)
						mineDurationSecret = issecretvalue(C_UnitAuras.GetAuraDuration(unit, mineAura.auraInstanceID))
						mineCountSecret =
							issecretvalue(C_UnitAuras.GetAuraApplicationDisplayCount(unit, mineAura.auraInstanceID))
					end
				end

				if not aurasSecret then
					local all = C_UnitAuras.GetUnitAuras(unit, "HARMFUL")
					allAura = all and all[1]
					if allAura then
						allIconSecret = issecretvalue(allAura.icon)
						allDurationSecret = issecretvalue(C_UnitAuras.GetAuraDuration(unit, allAura.auraInstanceID))
						allCountSecret =
							issecretvalue(C_UnitAuras.GetAuraApplicationDisplayCount(unit, allAura.auraInstanceID))
					end
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
					allCountSecret,
					aurasSecret
			end,
		},
		{
			name = "media",
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
				local path = frame.nameText:GetFont()
				local expected = ns.Media:FontPath(profile.font)
				local ok = normalizePath(path) == normalizePath(self.appliedFont)
					and normalizePath(path) == normalizePath(expected)

				return ok and "PASS" or "FAIL",
					path,
					self.appliedFont,
					expected,
					frame.healthBar:GetStatusBarTexture():GetTexture(),
					ns.Media:Resolve("statusbar", profile.barTexture),
					frame.barPath
			end,
		},
		{
			name = "background",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local frame
				for _, plateFrame in pairs(self.plateFrames) do
					if plateFrame:IsShown() then
						frame = plateFrame
						break
					end
				end
				if not frame then
					return "SKIP", "no plates"
				end

				local healthAlpha = frame.healthBg:GetAlpha()
				local powerAlpha = frame.powerBg:GetAlpha()
				local castAlpha = frame.castBg:GetAlpha()

				if issecretvalue(healthAlpha) or issecretvalue(powerAlpha) or issecretvalue(castAlpha) then
					return "INFO", "secret"
				end

				local expected = self.db.profile.bgOpacity / 100
				local ok = math.abs(healthAlpha - expected) <= 0.01
					and math.abs(powerAlpha - expected) <= 0.01
					and math.abs(castAlpha - expected) <= 0.01

				return ok and "PASS" or "FAIL", healthAlpha, powerAlpha, castAlpha
			end,
		},
	}
end
