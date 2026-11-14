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
		debuffTimerSize = 8,
		debuffMax = 4,
		debuffX = 0,
		debuffY = 0,
		levelText = true,
		cc = true,
		ccSize = 26,
		ccMax = 2,
		enemyCooldowns = true,
		enemyCooldownSize = 20,
		enemyCooldownMax = 4,
		enemyCooldownSpells = {},
		raidMarkerPos = "TOPRIGHT",
		raidMarkerSize = 20,
		classificationIcon = true,
		targetScale = 100,
		nonTargetAlpha = 100,
		border = true,
		borderStyle = "thin",
		borderSize = 1,
		borderColor = "111111",
		targetStyle = "glow",
		targetColor = "66BFFF",
		castHeight = 8,
		darkenOOC = true,
		executeLine = false,
		executePercent = 30,
		castIcon = true,
		castSpark = true,
		castUninterruptible = true,
		castInterruptFlash = true,
		threatColors = true,
		threatRole = "auto",
		threatText = true,
		comboPoints = true,
	},
}

local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local SHIELD_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Small-Shield"
local CAST_BAR_GAP = 2
local POWER_BAR_GAP = 1
local DEBUFF_SPACING = 2
local DEBUFF_GROUP = "debuffs"
local CC_GROUP = "cc"
local DEBUFF_COUNT_SIZE = 10
local LEVEL_GAP = 2
local RAID_TARGET_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local MARKER_GAP = 2
local THREAT_GAP = 2
local CLASSIFICATION_SIZE = 14
local CLASSIFICATION_GAP = 2
local TARGET_HIGHLIGHT_WIDTH = 2
local BORDER_COLOR = { 0.067, 0.067, 0.067 }
local TARGET_COLOR = { 0.4, 0.749, 1 }
local TARGET_GLOW_REACH = 7
local TARGET_WASH_ALPHA = 0.25
local SHADOW_ALPHA = 0.8
local CAST_SHIELD_PAD = 6
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local SPARK_WIDTH = 12
local CAST_ICON_GAP = 1
local CAST_COLOR = { 0.9, 0.6, 0.1 }
local UNINTERRUPTIBLE_COLOR = { 0.45, 0.45, 0.45 }
local INTERRUPTED_COLOR = { 0.8, 0, 0 }
local INTERRUPTED_HOLD = 1
local INTERRUPTED_TEXT = "Interrupted"
local COMBO_MAX = 5
local COMBO_SIZE = 8
local COMBO_GAP = 2
local COMBO_COLOR = { 1, 0.8, 0.1 }

local CAST_EVENTS = {
	UNIT_SPELLCAST_START = "OnCastStart",
	UNIT_SPELLCAST_DELAYED = "OnCastStart",
	UNIT_SPELLCAST_CHANNEL_START = "OnChannelStart",
	UNIT_SPELLCAST_CHANNEL_UPDATE = "OnChannelStart",
	UNIT_SPELLCAST_STOP = "OnCastStop",
	UNIT_SPELLCAST_FAILED = "OnCastStop",
	UNIT_SPELLCAST_INTERRUPTED = "OnCastInterrupted",
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

local THREAT_EVENTS = {
	UNIT_THREAT_LIST_UPDATE = "OnUnitThreat",
	UNIT_THREAT_SITUATION_UPDATE = "OnUnitThreat",
	GROUP_ROSTER_UPDATE = "OnColorContextChanged",
	PLAYER_ROLES_ASSIGNED = "OnColorContextChanged",
	UNIT_PET = "OnColorContextChanged",
}

local function Plain(value)
	if issecretvalue(value) then
		return nil
	end
	return value
end

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
	self.threatEvents = { UNIT_THREAT_LIST_UPDATE = 0, UNIT_THREAT_SITUATION_UPDATE = 0, styled = 0 }

	self.comboClass = NameplateLogic.UsesComboPoints(select(2, UnitClass("player")))
	self.comboEvents = CreateFrame("Frame")
	self.comboEvents:SetScript("OnEvent", function(_, _, _, powerType)
		local token = Plain(powerType)
		if token == nil or token == "COMBO_POINTS" then
			self:UpdateComboPoints()
		end
	end)

	ns.EnemyCooldowns:Init(self)
end

function Nameplates:ComboActive()
	return self.db.profile.comboPoints and self.comboClass
end

function Nameplates:SetComboEventsEnabled(enable)
	if enable then
		self.comboEvents:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	else
		self.comboEvents:UnregisterAllEvents()
	end
end

function Nameplates:OnEnable()
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnUnitAdded")
	self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnUnitRemoved")
	self:RegisterEvent("UNIT_HEALTH", "OnUnitHealth")
	self:RegisterEvent("UNIT_MAXHEALTH", "OnUnitHealth")
	self:RegisterEvent("UNIT_NAME_UPDATE", "OnUnitNameUpdate")
	self:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
	self:RegisterEvent("RAID_TARGET_UPDATE", "OnRaidTargetUpdate")
	self:RegisterEvent("UNIT_FLAGS", "OnUnitFlags")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")

	self:SetCastEventsEnabled(self.db.profile.castBar)
	self:SetEventsEnabled(POWER_EVENTS, self.db.profile.powerBar)
	self:SetEventsEnabled(AURA_EVENTS, self.db.profile.debuffs or self.db.profile.cc)
	self:SetEventsEnabled(LEVEL_EVENTS, self.db.profile.levelText or self.db.profile.classificationIcon)
	self:SetEventsEnabled(THREAT_EVENTS, self.db.profile.threatColors or self.db.profile.threatText)
	self:SetComboEventsEnabled(self:ComboActive())
	ns.EnemyCooldowns:SetActive(self.db.profile.enemyCooldowns)

	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.unitToken
		if unit then
			self.units[unit] = true
			self:StyleUnit(unit)
		end
	end
end

function Nameplates:OnDisable()
	ns.EnemyCooldowns:SetActive(false)
	self:SetCastEventsEnabled(false)
	self:SetComboEventsEnabled(false)

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
		self:SetEventsEnabled(LEVEL_EVENTS, self.db.profile.levelText or self.db.profile.classificationIcon)
		self:SetEventsEnabled(THREAT_EVENTS, self.db.profile.threatColors or self.db.profile.threatText)
		self:SetComboEventsEnabled(self:ComboActive())
		ns.EnemyCooldowns:SetActive(self.db.profile.enemyCooldowns)
		for _, frame in pairs(self.plateFrames) do
			self:ApplySize(frame)
		end
		self:ApplyCountFonts()
		for unit, plate in pairs(self.unitPlates) do
			local frame = self.plateFrames[plate]
			if frame then
				self:UpdateHealth(unit, frame)
				self:UpdateColor(unit, frame)
				self:UpdateHighlight(unit, frame)
				self:UpdateTargetState(unit, frame)
				ns.EnemyCooldowns:Attach(unit, frame)
				self:UpdateMarkers(unit, frame)
				self:UpdateThreat(unit, frame)
				self:UpdateLevel(unit, frame)
				self:UpdatePower(unit, frame)
				self:UpdateDebuffs(unit, frame)
				self:UpdateCC(unit, frame)
			end
		end
		self:UpdateComboPoints()
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
		self:UpdateMarkers(unit, frame)
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
			self:UpdateTargetState(unit, frame)
		end
	end
	self:UpdateComboPoints()
end

function Nameplates:OnRaidTargetUpdate()
	for unit, plate in pairs(self.unitPlates) do
		local frame = self.plateFrames[plate]
		if frame then
			self:UpdateMarkers(unit, frame)
		end
	end
end

function Nameplates:OnUnitFlags(_, unit)
	local frame = self:GetCastFrame(unit)
	if frame then
		self:UpdateColor(unit, frame)
	end
end

function Nameplates:OnUnitThreat(event, unit)
	self.threatEvents[event] = self.threatEvents[event] + 1
	self.threatLastUnit = unit
	local frame = self:GetCastFrame(unit)
	if frame then
		self.threatEvents.styled = self.threatEvents.styled + 1
		self:UpdateColor(unit, frame)
		self:UpdateThreat(unit, frame)
	else
		self:OnColorContextChanged()
	end
end

function Nameplates:OnColorContextChanged()
	for unit, plate in pairs(self.unitPlates) do
		local frame = self.plateFrames[plate]
		if frame then
			self:UpdateColor(unit, frame)
			self:UpdateThreat(unit, frame)
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
	ns.EnemyCooldowns:Attach(unit, frame)
	self:UpdateColor(unit, frame)
	self:UpdateHighlight(unit, frame)
	self:UpdateTargetState(unit, frame)
	self:UpdateMarkers(unit, frame)
	self:UpdateThreat(unit, frame)
	self:SyncCastBar(unit, frame)
	self:UpdatePower(unit, frame)
	self:UpdateDebuffs(unit, frame)
	self:UpdateCC(unit, frame)
	self:UpdateComboPoints()

	if isNewPlate and ns.Debug:IsActive() then
		local isPlayer = UnitIsPlayer(unit)
		if not issecretvalue(isPlayer) and isPlayer == true then
			ns.Debug:Log("Nameplates", "style", unit)
		end
	end
end

function Nameplates:UnstyleUnit(unit)
	ns.EnemyCooldowns:Detach(unit)
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
local debuffTimerTexts = setmetatable({}, { __mode = "k" })

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

	local timer = cooldown:GetCountdownFontString()
	if timer then
		debuffTimerTexts[button] = timer
		ns.Media:SetFont(timer, Nameplates.db.profile.font, Nameplates.db.profile.debuffTimerSize, "OUTLINE")
	end

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
	local profile = self.db.profile
	for button, count in pairs(initializedDebuffButtons) do
		ns.Media:SetFont(count, profile.font, DEBUFF_COUNT_SIZE, "OUTLINE")
		local timer = debuffTimerTexts[button]
		if timer then
			ns.Media:SetFont(timer, profile.font, profile.debuffTimerSize, "OUTLINE")
		end
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

local function hexColor(text, fallback)
	local r, g, b = ns.DamageMeterLogic.ParseHex(text)
	if r then
		return r, g, b
	end
	return fallback[1], fallback[2], fallback[3]
end

-- Parent-level BACKGROUND textures, so the glow sits behind the health bar child.
local function createGlow(parent, bar, sublevel)
	local pieces = {}
	local path = ns.Media:Icon("glow")
	for i, spec in ipairs(NameplateLogic.GLOW_PIECES) do
		local tex = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel)
		tex:SetTexture(path)
		tex:SetTexCoord(spec.coords[1], spec.coords[2], spec.coords[3], spec.coords[4])
		for _, pair in ipairs(spec.points) do
			tex:SetPoint(pair[1], bar, pair[2], 0, 0)
		end
		pieces[i] = tex
	end
	return pieces
end

local function styleGlow(pieces, reach, r, g, b, a, blend)
	for i, spec in ipairs(NameplateLogic.GLOW_PIECES) do
		local tex = pieces[i]
		if spec.size == "corner" then
			tex:SetSize(reach, reach)
		elseif spec.size == "height" then
			tex:SetHeight(reach)
		else
			tex:SetWidth(reach)
		end
		tex:SetVertexColor(r, g, b, a)
		tex:SetBlendMode(blend)
	end
end

local function createEdges(bar, sublevel)
	local edges = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		edges[side] = bar:CreateTexture(nil, "OVERLAY", nil, sublevel)
	end
	return edges
end

local function placeEdges(edges, bar, size)
	edges.top:ClearAllPoints()
	edges.top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -size, 0)
	edges.top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", size, 0)
	edges.top:SetHeight(size)
	edges.bottom:ClearAllPoints()
	edges.bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -size, 0)
	edges.bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", size, 0)
	edges.bottom:SetHeight(size)
	edges.left:ClearAllPoints()
	edges.left:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 0)
	edges.left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, 0)
	edges.left:SetWidth(size)
	edges.right:ClearAllPoints()
	edges.right:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 0)
	edges.right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, 0)
	edges.right:SetWidth(size)
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
	highlight:SetTexture(BAR_TEXTURE)
	highlight:SetAlpha(0)

	local border = createEdges(healthBar, 0)
	local shadow = createGlow(frame, healthBar, -8)
	local targetGlow = createGlow(frame, healthBar, -7)
	local targetEdges = createEdges(healthBar, 7)
	local targetWash = healthBar:CreateTexture(nil, "OVERLAY", nil, 6)
	targetWash:SetAllPoints(healthBar)

	local executeLine = healthBar:CreateTexture(nil, "OVERLAY")
	executeLine:SetColorTexture(1, 1, 1, 0.9)
	executeLine:SetWidth(1)

	local raidMarker = healthBar:CreateTexture(nil, "OVERLAY")
	raidMarker:SetTexture(RAID_TARGET_TEXTURE)
	raidMarker:Hide()

	local classification = healthBar:CreateTexture(nil, "OVERLAY")
	classification:SetSize(CLASSIFICATION_SIZE, CLASSIFICATION_SIZE)
	classification:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 0, CLASSIFICATION_GAP)
	classification:Hide()

	local nameText = frame:CreateFontString(nil, "OVERLAY")
	nameText:SetPoint("BOTTOM", frame, "TOP", 0, 2)

	local threatText = healthBar:CreateFontString(nil, "OVERLAY")
	threatText:SetPoint("RIGHT", healthBar, "RIGHT", -THREAT_GAP, 0)
	threatText:Hide()

	local comboRow = CreateFrame("Frame", nil, frame)
	comboRow:SetPoint("BOTTOM", nameText, "TOP", 0, COMBO_GAP)
	comboRow:SetSize(COMBO_MAX * COMBO_SIZE + (COMBO_MAX - 1) * COMBO_GAP, COMBO_SIZE)
	comboRow:Hide()

	local comboPips, comboBgs = {}, {}
	for i = 1, COMBO_MAX do
		local pip = CreateFrame("StatusBar", nil, comboRow)
		pip:SetSize(COMBO_SIZE, COMBO_SIZE)
		pip:SetPoint("LEFT", comboRow, "LEFT", (i - 1) * (COMBO_SIZE + COMBO_GAP), 0)
		pip:SetStatusBarTexture(BAR_TEXTURE)
		-- each pip spans one point, so SetValue fills it without comparing a possibly secret count
		pip:SetMinMaxValues(i - 1, i)
		local pipBg = pip:CreateTexture(nil, "BACKGROUND")
		pipBg:SetAllPoints(pip)
		pipBg:SetTexture(BAR_TEXTURE)
		pipBg:SetVertexColor(0.1, 0.1, 0.1, 1)
		comboPips[i] = pip
		comboBgs[i] = pipBg
	end

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
	castBar:SetStatusBarTexture(BAR_TEXTURE)
	castBar:SetStatusBarColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
	castBar:Hide()

	local castBg = castBar:CreateTexture(nil, "BACKGROUND")
	castBg:SetAllPoints(castBar)
	castBg:SetTexture(BAR_TEXTURE)
	castBg:SetVertexColor(0.1, 0.1, 0.1, 1)

	local castUninterruptible = castBar:CreateTexture(nil, "ARTWORK", nil, 6)
	castUninterruptible:SetColorTexture(UNINTERRUPTIBLE_COLOR[1], UNINTERRUPTIBLE_COLOR[2], UNINTERRUPTIBLE_COLOR[3], 1)
	castUninterruptible:SetAlpha(0)

	local castFlash = castBar:CreateTexture(nil, "ARTWORK", nil, 7)
	castFlash:SetAllPoints(castBar)
	castFlash:SetColorTexture(INTERRUPTED_COLOR[1], INTERRUPTED_COLOR[2], INTERRUPTED_COLOR[3], 1)
	castFlash:SetAlpha(0)

	local castSpark = castBar:CreateTexture(nil, "OVERLAY")
	castSpark:SetTexture(SPARK_TEXTURE)
	castSpark:SetBlendMode("ADD")

	local castIcon = castBar:CreateTexture(nil, "ARTWORK")
	castIcon:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMLEFT", -CAST_ICON_GAP, 0)
	castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local castText = castBar:CreateFontString(nil, "OVERLAY")
	castText:SetPoint("CENTER", castBar)

	local castShield = castBar:CreateTexture(nil, "OVERLAY")
	castShield:SetTexture(SHIELD_TEXTURE)
	castShield:SetPoint("LEFT", castBar, "LEFT", 0, 0)
	castShield:SetAlpha(0)

	frame.healthBar = healthBar
	frame.healthBg = bg
	frame.healthText = healthText
	frame.levelText = levelText
	frame.highlight = highlight
	frame.border = border
	frame.shadow = shadow
	frame.targetGlow = targetGlow
	frame.targetEdges = targetEdges
	frame.targetWash = targetWash
	frame.targetParts = {
		glow = targetGlow,
		border = { targetEdges.top, targetEdges.bottom, targetEdges.left, targetEdges.right },
		highlight = { targetWash },
		outline = { highlight },
	}
	for _, parts in pairs(frame.targetParts) do
		for _, tex in ipairs(parts) do
			tex:SetAlpha(0)
		end
	end
	frame.executeLine = executeLine
	frame.raidMarker = raidMarker
	frame.classification = classification
	frame.nameText = nameText
	frame.threatText = threatText
	frame.comboRow = comboRow
	frame.comboPips = comboPips
	frame.comboBgs = comboBgs
	frame.powerBar = powerBar
	frame.powerBg = powerBg
	frame.powerText = powerText
	frame.castBar = castBar
	frame.castBg = castBg
	frame.castUninterruptible = castUninterruptible
	frame.castFlash = castFlash
	frame.castSpark = castSpark
	frame.castIcon = castIcon
	frame.castText = castText
	frame.castShield = castShield
	self:AnchorCastFill(frame)

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
	for _, pipBg in ipairs(frame.comboBgs) do
		pipBg:SetAlpha(profile.bgOpacity / 100)
	end
	local _, namePath = ns.Media:SetFont(frame.nameText, profile.font, profile.nameSize, "OUTLINE")
	self.appliedFont = namePath
	ns.Media:SetFont(frame.healthText, profile.font, profile.nameSize - 1, "OUTLINE")
	ns.Media:SetFont(frame.levelText, profile.font, profile.nameSize - 1, "OUTLINE")
	ns.Media:SetFont(frame.threatText, profile.font, profile.nameSize - 1, "OUTLINE")
	ns.Media:SetFont(frame.powerText, profile.font, profile.nameSize - 1, "OUTLINE")
	ns.Media:SetFont(frame.castText, profile.font, profile.nameSize - 1, "OUTLINE")
	frame.powerBar:SetHeight(profile.powerHeight)

	local castAnchor = profile.powerBar and frame.powerBar or frame.healthBar
	frame.castBar:ClearAllPoints()
	frame.castBar:SetPoint("TOPLEFT", castAnchor, "BOTTOMLEFT", 0, -CAST_BAR_GAP)
	frame.castBar:SetPoint("TOPRIGHT", castAnchor, "BOTTOMRIGHT", 0, -CAST_BAR_GAP)
	frame.castBar:SetHeight(profile.castHeight)
	frame.castSpark:SetSize(SPARK_WIDTH, profile.castHeight * 2)
	frame.castShield:SetSize(profile.castHeight + CAST_SHIELD_PAD, profile.castHeight + CAST_SHIELD_PAD)

	local iconSize = NameplateLogic.CastIconSize(
		profile.height,
		profile.powerBar and profile.powerHeight or nil,
		POWER_BAR_GAP,
		CAST_BAR_GAP,
		profile.castHeight
	)
	frame.castIcon:SetSize(iconSize, iconSize)
	frame.castIcon:SetShown(profile.castIcon)
	frame.castSpark:SetShown(profile.castSpark)

	self:ApplyBorder(frame)

	frame.executeLine:ClearAllPoints()
	local executeX = NameplateLogic.ExecuteOffset(profile.width, profile.executePercent)
	frame.executeLine:SetPoint("TOP", frame.healthBar, "TOPLEFT", executeX, 0)
	frame.executeLine:SetPoint("BOTTOM", frame.healthBar, "BOTTOMLEFT", executeX, 0)
	frame.executeLine:SetShown(profile.executeLine)

	-- SetStatusBarTexture replaces the bar's texture object and resets its vertex colour, so
	-- only touch the bars when the resolved path actually changes, and restore colours after
	local barPath = ns.Media:Fetch("statusbar", profile.barTexture) or BAR_TEXTURE
	if barPath ~= frame.barPath then
		local hr, hg, hb = frame.healthBar:GetStatusBarColor()
		local pr, pg, pb = frame.powerBar:GetStatusBarColor()

		barPath = ns.Media:SetStatusBarTexture(frame.healthBar, profile.barTexture)
		ns.Media:SetStatusBarTexture(frame.powerBar, profile.barTexture)
		ns.Media:SetStatusBarTexture(frame.castBar, profile.barTexture)
		for _, pip in ipairs(frame.comboPips) do
			ns.Media:SetStatusBarTexture(pip, profile.barTexture)
			pip:SetStatusBarColor(COMBO_COLOR[1], COMBO_COLOR[2], COMBO_COLOR[3])
		end

		frame.healthBar:SetStatusBarColor(hr, hg, hb)
		frame.powerBar:SetStatusBarColor(pr, pg, pb)
		frame.castBar:SetStatusBarColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
		self:AnchorCastFill(frame)

		frame.barPath = barPath
	end
end

-- the spark and the uninterruptible tint follow the fill texture, which SetStatusBarTexture replaces
function Nameplates:AnchorCastFill(frame)
	local fill = frame.castBar:GetStatusBarTexture()
	frame.castSpark:ClearAllPoints()
	frame.castSpark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
	frame.castUninterruptible:ClearAllPoints()
	frame.castUninterruptible:SetAllPoints(fill)
end

function Nameplates:ApplyBorder(frame)
	local profile = self.db.profile
	local size = profile.borderSize
	local bar = frame.healthBar
	local mode = NameplateLogic.BorderMode(profile.border, profile.borderStyle)
	local br, bg, bb = hexColor(profile.borderColor, BORDER_COLOR)

	placeEdges(frame.border, bar, size)
	for _, edge in pairs(frame.border) do
		edge:SetColorTexture(br, bg, bb, 1)
		edge:SetShown(mode == "thin")
	end
	styleGlow(frame.shadow, 2 + 2 * size, br, bg, bb, SHADOW_ALPHA, "BLEND")
	for _, tex in ipairs(frame.shadow) do
		tex:SetShown(mode == "shadow")
	end

	local tr, tg, tb = hexColor(profile.targetColor, TARGET_COLOR)
	styleGlow(frame.targetGlow, TARGET_GLOW_REACH, tr, tg, tb, 1, "ADD")
	placeEdges(frame.targetEdges, bar, size)
	for _, edge in pairs(frame.targetEdges) do
		edge:SetColorTexture(tr, tg, tb, 1)
	end
	frame.targetWash:SetColorTexture(tr, tg, tb, TARGET_WASH_ALPHA)
	frame.highlight:SetVertexColor(tr, tg, tb, 0.5)

	local outset = (mode == "thin" and size or 0) + TARGET_HIGHLIGHT_WIDTH
	frame.highlight:ClearAllPoints()
	frame.highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", -outset, outset)
	frame.highlight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", outset, -outset)
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
		relativeTo = ns.EnemyCooldowns:Anchor(frame) or (profile.levelText and frame.levelText or frame)
	elseif anchor == "LEFT" then
		relativeTo = (profile.cc and frame.cc) or frame
	elseif Nameplates:ComboActive() then
		relativeTo = frame.comboRow
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

function Nameplates:ComboTargetFrame()
	local plate = C_NamePlate.GetNamePlateForUnit("target")
	return plate and self.plateFrames[plate]
end

-- combo points live on the target, so only the target plate shows them; every plate keeps the row's space
function Nameplates:UpdateComboPoints()
	local target = self:ComboActive() and self:ComboTargetFrame()
	for _, frame in pairs(self.plateFrames) do
		if frame ~= target then
			frame.comboRow:Hide()
		end
	end
	if not target then
		return
	end

	local points = GetComboPoints("player", "target")
	for _, pip in ipairs(target.comboPips) do
		pip:SetValue(points)
	end
	target.comboRow:SetShown(issecretvalue(points) or points > 0)
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

local colorState = {}

-- the returned table is reused by every call
function Nameplates:ColorState(unit)
	local profile = self.db.profile
	local state = colorState
	state.reaction = Plain(UnitReaction(unit, "player"))
	state.isPlayer = Plain(UnitIsPlayer(unit))
	state.classFile = Plain(select(2, UnitClass(unit)))
	state.tapDenied = Plain(UnitIsTapDenied(unit))
	state.inCombat = Plain(UnitAffectingCombat(unit))
	state.darkenOOC = profile.darkenOOC
	state.threat = nil
	state.threatRole = nil
	state.threatShared = nil
	state.offTank = nil

	if profile.threatColors then
		state.threat = Plain(UnitThreatSituation("player", unit))
		state.threatRole = NameplateLogic.ThreatRole(profile.threatRole, Plain(UnitGroupRolesAssigned("player")))
		state.threatShared = IsInGroup() or Plain(UnitExists("pet")) == true
		if state.threatRole == "tank" and type(state.threat) == "number" and state.threat < 2 then
			local mobTarget = unit .. "target"
			state.offTank = Plain(UnitExists(mobTarget)) == true
				and Plain(UnitIsUnit(mobTarget, "player")) == false
				and Plain(UnitGroupRolesAssigned(mobTarget)) == "TANK"
		end
	end
	return state
end

function Nameplates:UpdateColor(unit, frame)
	frame.healthBar:SetStatusBarColor(NameplateLogic.PlateColor(self:ColorState(unit), RAID_CLASS_COLORS))
end

function Nameplates:UpdateHighlight(unit, frame)
	local style = self.db.profile.targetStyle
	local isTarget = UnitIsUnit(unit, "target")
	local secret = issecretvalue(isTarget)
	for key, parts in pairs(frame.targetParts) do
		for _, tex in ipairs(parts) do
			if key ~= style then
				tex:SetAlpha(0)
			elseif secret then
				tex:SetAlphaFromBoolean(isTarget, 1, 0)
			else
				tex:SetAlpha(isTarget and 1 or 0)
			end
		end
	end
end

function Nameplates:UpdateTargetState(unit, frame)
	local profile = self.db.profile
	local isTarget = UnitIsUnit(unit, "target")
	local secret = issecretvalue(isTarget)

	frame:SetScale((not secret and isTarget) and profile.targetScale / 100 or 1)

	local fade = profile.nonTargetAlpha / 100
	if fade >= 1 or not UnitExists("target") then
		frame:SetAlpha(1)
	elseif secret then
		frame:SetAlphaFromBoolean(isTarget, 1, fade)
	else
		frame:SetAlpha(isTarget and 1 or fade)
	end
end

-- GetRaidTargetIndex is always secret for addon code; type() can still tell a marker from none
function Nameplates:UpdateMarkers(unit, frame)
	local profile = self.db.profile
	local marker = frame.raidMarker
	local point, relPoint, x, y = NameplateLogic.MarkerLayout(profile.raidMarkerPos, MARKER_GAP)
	local index = point and GetRaidTargetIndex(unit)
	local markerShown = type(index) ~= "nil"

	if markerShown then
		SetRaidTargetIconTexture(marker, index)
		marker:SetSize(profile.raidMarkerSize, profile.raidMarkerSize)
		marker:ClearAllPoints()
		marker:SetPoint(point, self:MarkerAnchor(frame, profile), relPoint, x, y)
		marker:Show()
	else
		marker:Hide()
	end

	local atlas = nil
	if profile.classificationIcon and not (markerShown and profile.raidMarkerPos == "TOPLEFT") then
		atlas = NameplateLogic.ClassificationAtlas(Plain(UnitClassification(unit)))
	end
	if atlas then
		frame.classification:SetAtlas(atlas)
		frame.classification:Show()
	else
		frame.classification:Hide()
	end
end

-- scaledPercentage is nil while the player is not on the unit's threat list
function Nameplates:UpdateThreat(unit, frame)
	local text = frame.threatText
	if not self.db.profile.threatText then
		text:Hide()
		return
	end
	local _, _, percent = UnitDetailedThreatSituation("player", unit)
	if type(percent) ~= "number" then
		text:Hide()
		return
	end
	text:SetText(NameplateLogic.FormatValue("percent", nil, percent))
	text:Show()
end

function Nameplates:MarkerAnchor(frame, profile)
	local position = profile.raidMarkerPos
	if position == "LEFT" then
		return (profile.cc and frame.cc) or frame
	elseif position == "RIGHT" then
		return ns.EnemyCooldowns:Anchor(frame) or (profile.levelText and frame.levelText or frame)
	end
	return frame
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
	local tint = frame.castUninterruptible
	local tintAlpha = self.db.profile.castUninterruptible and 1 or 0
	if issecretvalue(notInterruptible) then
		shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
		tint:SetAlphaFromBoolean(notInterruptible, tintAlpha, 0)
	else
		shield:SetAlpha(notInterruptible and 1 or 0)
		tint:SetAlpha(notInterruptible and tintAlpha or 0)
	end
end

function Nameplates:ShowCast(frame, name, texture, notInterruptible)
	frame.castFlash:SetAlpha(0)
	frame.castSpark:SetShown(self.db.profile.castSpark)
	frame.castIcon:SetTexture(texture)
	frame.castText:SetText(name)
	self:ApplyShield(frame, notInterruptible)
	frame.castBar:Show()
end

function Nameplates:OnCastInterrupted(_, unit)
	local frame = self:GetCastFrame(unit)
	if not frame then
		return
	end
	if not self.db.profile.castInterruptFlash then
		self:OnCastStop(nil, unit)
		return
	end

	self.castMode[unit] = "interrupted"
	local token = (frame.interruptToken or 0) + 1
	frame.interruptToken = token

	frame.castFlash:SetAlpha(1)
	frame.castSpark:Hide()
	frame.castShield:SetAlpha(0)
	frame.castUninterruptible:SetAlpha(0)
	frame.castText:SetText(INTERRUPTED_TEXT)
	frame.castBar:Show()

	C_Timer.After(INTERRUPTED_HOLD, function()
		if frame.interruptToken == token and self.castMode[unit] == "interrupted" then
			self:HideCastBar(unit, frame)
		end
	end)
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

	local name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
	self:ShowCast(frame, name, texture, notInterruptible)

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

	local name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(unit)
	self:ShowCast(frame, name, texture, notInterruptible)

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
	local options = {
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
			debuffTimerSize = {
				type = "range",
				name = "Debuff timer size",
				desc = "Countdown numbers on debuff and CC icons.",
				order = 13.5,
				min = 6,
				max = 20,
				step = 1,
				get = function()
					return self.db.profile.debuffTimerSize
				end,
				set = function(_, value)
					self.db.profile.debuffTimerSize = value
					self:Refresh()
				end,
				disabled = function()
					return not (self.db.profile.debuffs or self.db.profile.cc)
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

	local function option(key, spec)
		spec.get = function()
			return self.db.profile[key]
		end
		spec.set = function(_, value)
			self.db.profile[key] = value
			self:Refresh()
		end
		options.args[key] = spec
	end

	local function isOff(key)
		return function()
			return not self.db.profile[key]
		end
	end

	local function castExtraOff()
		return not self.db.profile.castBar
	end

	local function colorInput(order, name, disabled)
		return {
			type = "input",
			name = name,
			desc = "RRGGBB",
			order = order,
			disabled = disabled,
			validate = function(_, value)
				return ns.DamageMeterLogic.ParseHex(value) ~= nil or "Enter a colour as RRGGBB"
			end,
		}
	end

	option("comboPoints", {
		type = "toggle",
		name = "Combo points",
		desc = "Rogues and druids: shows your combo points on the target's plate, between the name and the debuffs.",
		order = 24,
	})

	options.args.markerHeader = { type = "header", name = "Markers", order = 30 }
	option("raidMarkerPos", {
		type = "select",
		name = "Raid marker",
		order = 31,
		values = {
			TOPRIGHT = "Top right",
			TOPLEFT = "Top left",
			LEFT = "Left",
			RIGHT = "Right",
			NONE = "Hidden",
		},
	})
	option("raidMarkerSize", {
		type = "range",
		name = "Raid marker size",
		order = 32,
		min = 10,
		max = 40,
		step = 1,
		disabled = function()
			return self.db.profile.raidMarkerPos == "NONE"
		end,
	})
	option("classificationIcon", { type = "toggle", name = "Elite and rare icon", order = 33 })

	options.args.targetHeader = { type = "header", name = "Target", order = 35 }
	option("targetScale", { type = "range", name = "Target scale (%)", order = 36, min = 100, max = 150, step = 5 })
	option("nonTargetAlpha", {
		type = "range",
		name = "Non-target opacity (%)",
		order = 37,
		min = 20,
		max = 100,
		step = 5,
	})

	option("targetStyle", {
		type = "select",
		name = "Target indicator",
		desc = "Glow: a soft glow behind the plate. Border: the border takes the colour. "
			.. "Highlight: a wash over the bar. Outline: a frame around the plate.",
		order = 38,
		values = NameplateLogic.TARGET_STYLES,
	})
	option(
		"targetColor",
		colorInput(39, "Target colour", function()
			return self.db.profile.targetStyle == "none"
		end)
	)

	options.args.barHeader = { type = "header", name = "Health bar", order = 40 }
	options.args.border = {
		type = "select",
		name = "Border",
		desc = "None: no frame. Thin: a pixel edge. Shadow: a soft dark edge.",
		order = 41,
		values = NameplateLogic.BORDER_MODES,
		get = function()
			return NameplateLogic.BorderMode(self.db.profile.border, self.db.profile.borderStyle)
		end,
		set = function(_, value)
			local profile = self.db.profile
			local style
			profile.border, style = NameplateLogic.BorderSetting(value)
			if style then
				profile.borderStyle = style
			end
			self:Refresh()
		end,
	}
	option("borderSize", {
		type = "range",
		name = "Border size",
		order = 42,
		min = 1,
		max = 3,
		step = 1,
		disabled = isOff("border"),
	})
	option("borderColor", colorInput(43, "Border colour", isOff("border")))
	option("darkenOOC", { type = "toggle", name = "Darken enemies out of combat", order = 44 })
	option("executeLine", { type = "toggle", name = "Execute line", order = 45 })
	option("executePercent", {
		type = "range",
		name = "Execute line health (%)",
		order = 46,
		min = 5,
		max = 90,
		step = 5,
		disabled = isOff("executeLine"),
	})

	options.args.castHeader = { type = "header", name = "Cast bar details", order = 50 }
	option("castIcon", { type = "toggle", name = "Spell icon", order = 51, disabled = castExtraOff })
	option("castSpark", { type = "toggle", name = "Spark", order = 52, disabled = castExtraOff })
	option("castUninterruptible", {
		type = "toggle",
		name = "Grey uninterruptible casts",
		order = 53,
		disabled = castExtraOff,
	})
	option("castInterruptFlash", { type = "toggle", name = "Interrupted flash", order = 54, disabled = castExtraOff })
	option("castHeight", {
		type = "range",
		name = "Cast bar height",
		order = 55,
		min = 4,
		max = 20,
		step = 1,
		disabled = castExtraOff,
	})

	options.args.threatHeader = { type = "header", name = "Threat", order = 60 }
	option("threatColors", { type = "toggle", name = "Threat colours", order = 61 })
	option("threatRole", {
		type = "select",
		name = "Threat role",
		desc = "Auto uses your assigned group role.",
		order = 62,
		values = {
			auto = "Auto",
			tank = "Tank",
			dps = "Damage or healer",
		},
		disabled = isOff("threatColors"),
	})
	option("threatText", {
		type = "toggle",
		name = "Threat percentage",
		desc = "Your threat on the unit, inside the right end of the health bar, while you are on its threat list.",
		order = 63,
	})

	ns.EnemyCooldowns:AddOptions(options.args)

	return options
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

	local function threatDetail(unit)
		local isTanking, status, scaled, raw, value = UnitDetailedThreatSituation("player", unit)
		return "tank",
			type(isTanking),
			isTanking,
			"status",
			type(status),
			status,
			"scaled",
			type(scaled),
			scaled,
			"raw",
			type(raw),
			raw,
			"value",
			type(value),
			value
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
					"GetRaidTargetIndex",
					"SetRaidTargetIconTexture",
					"UnitThreatSituation",
					"UnitDetailedThreatSituation",
					"UnitGroupRolesAssigned",
					"UnitAffectingCombat",
					"GetComboPoints",
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

				local state = self:ColorState("target")
				local er, eg, eb = NameplateLogic.PlateColor(state, RAID_CLASS_COLORS)
				local cr, cg, cb = frame.healthBar:GetStatusBarColor()

				local ok = math.abs(cr - er) <= 0.01 and math.abs(cg - eg) <= 0.01 and math.abs(cb - eb) <= 0.01
				return ok and "PASS" or "FAIL",
					cr,
					cg,
					cb,
					er,
					eg,
					eb,
					state.inCombat,
					state.threat,
					state.threatRole,
					state.threatShared
			end,
		},
		{
			name = "raid marker",
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
				local index = GetRaidTargetIndex("target")
				local hasMarker = type(index) ~= "nil"
				local point, relPoint, expX, expY = NameplateLogic.MarkerLayout(profile.raidMarkerPos, MARKER_GAP)
				local expected = point ~= nil and hasMarker
				local shown = frame.raidMarker:IsShown() == true

				local ok = shown == expected
				if not ok or not shown then
					return ok and "PASS" or "FAIL", shown, hasMarker, profile.raidMarkerPos, issecretvalue(index)
				end

				local ptOk, p, relTo, rp, x, y = readPoint(frame.raidMarker)
				if not ptOk then
					return "PASS", shown, hasMarker, profile.raidMarkerPos, issecretvalue(index), "points restricted"
				end
				ok = p == point
					and relTo == self:MarkerAnchor(frame, profile)
					and rp == relPoint
					and not issecretvalue(x)
					and not issecretvalue(y)
					and math.abs(x - expX) <= 0.5
					and math.abs(y - expY) <= 0.5
				return ok and "PASS" or "FAIL", shown, hasMarker, profile.raidMarkerPos, issecretvalue(index)
			end,
		},
		{
			name = "threat text",
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

				local _, status, percent = UnitDetailedThreatSituation("player", "target")
				local expected = self.db.profile.threatText and type(percent) == "number"
				local shown = frame.threatText:IsShown() == true
				local ok = shown == expected
				local text = frame.threatText:GetText()
				if issecretvalue(percent) or issecretvalue(text) then
					return ok and "INFO" or "FAIL", shown, "secret"
				end
				if shown then
					ok = ok and text == NameplateLogic.FormatValue("percent", nil, percent)
				end

				local ptOk, p, relTo, rp, x, y = readPoint(frame.threatText)
				if ptOk then
					ok = ok
						and p == "RIGHT"
						and relTo == frame.healthBar
						and rp == "RIGHT"
						and not issecretvalue(x)
						and not issecretvalue(y)
						and math.abs(x + THREAT_GAP) <= 0.5
						and math.abs(y) <= 0.5
				end
				return ok and "PASS" or "FAIL", shown, text, percent, Plain(status)
			end,
		},
		{
			name = "threat setup",
			run = function(ctx)
				local profile = self.db.profile
				local counts = self.threatEvents
				local leadApi = "UnitThreatPercentageOfLead"
				return "INFO",
					"text",
					profile.threatText,
					"colors",
					profile.threatColors,
					"role",
					profile.threatRole,
					"events",
					ctx.enabled ~= false and (profile.threatColors or profile.threatText) == true,
					"list",
					counts.UNIT_THREAT_LIST_UPDATE,
					"situation",
					counts.UNIT_THREAT_SITUATION_UPDATE,
					"styled",
					counts.styled,
					"last",
					self.threatLastUnit,
					"scriptErrors",
					C_CVar.GetCVar("scriptErrors"),
					"leadApi",
					type(_G[leadApi])
			end,
		},
		{
			name = "threat target",
			run = function(ctx)
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local leadApi = "UnitThreatPercentageOfLead"
				local lead = _G[leadApi]
				local leadOk, leadValue = "missing", nil
				if type(lead) == "function" then
					leadOk, leadValue = pcall(lead, "player", "target")
				end
				return "INFO", "lead", leadOk, leadValue, threatDetail("target")
			end,
		},
		{
			name = "threat plate",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local plate = C_NamePlate.GetNamePlateForUnit("target")
				if not plate then
					return "SKIP", "no target plate"
				end

				local unit = plate.unitToken
				if not unit then
					return "SKIP", "no unit token"
				end

				local frame = self.plateFrames[plate]
				if not frame then
					return "INFO", "unit", unit, "styled", false, threatDetail(unit)
				end

				local routeOk, routeFrame = pcall(self.GetCastFrame, self, unit)
				local colorOk, colorErr = pcall(self.UpdateColor, self, unit, frame)
				local threatOk, threatErr = pcall(self.UpdateThreat, self, unit, frame)
				local detail = { threatDetail(unit) }
				return "INFO",
					"unit",
					unit,
					"styled",
					true,
					"event",
					routeOk and routeFrame == frame,
					"frame",
					frame:IsShown(),
					"update",
					colorOk,
					threatOk,
					"shown",
					frame.threatText:IsShown(),
					unpack(detail, 1, 15),
					"errors",
					colorErr,
					threatErr
			end,
		},
		{
			name = "classification icon",
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
				local classification = UnitClassification("target")
				if issecretvalue(classification) then
					return "INFO", "secret", frame.classification:IsShown()
				end

				local markerAtIcon = frame.raidMarker:IsShown() and profile.raidMarkerPos == "TOPLEFT"
				local atlas = NameplateLogic.ClassificationAtlas(classification)
				local expected = profile.classificationIcon and not markerAtIcon and atlas ~= nil
				local shown = frame.classification:IsShown() == true
				local ok = shown == expected
				if shown then
					ok = ok and frame.classification:GetAtlas() == atlas
				end
				return ok and "PASS" or "FAIL", shown, classification, atlas
			end,
		},
		{
			name = "target state",
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
				local scale = frame:GetScale()
				local alpha = frame:GetAlpha()
				if
					issecretvalue(scale)
					or issecretvalue(alpha)
					or issecretvalue(UnitIsUnit(plate.unitToken, "target"))
				then
					return "INFO", "secret"
				end

				local ok = math.abs(scale - profile.targetScale / 100) <= 0.01 and math.abs(alpha - 1) <= 0.01
				return ok and "PASS" or "FAIL", scale, alpha, profile.targetScale, profile.nonTargetAlpha
			end,
		},
		{
			name = "cast details",
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
				local mode = self.castMode[plate.unitToken]
				if not mode then
					return "SKIP", "not casting"
				end

				local profile = self.db.profile
				local iconShown = frame.castIcon:IsShown() == true
				local ok = iconShown == profile.castIcon
				if mode == "interrupted" then
					local flash = frame.castFlash:GetAlpha()
					return (ok and not issecretvalue(flash) and flash == 1) and "PASS" or "FAIL", mode, iconShown
				end
				ok = ok and (frame.castSpark:IsShown() == true) == profile.castSpark
				return ok and "PASS" or "FAIL",
					mode,
					iconShown,
					frame.castSpark:IsShown(),
					issecretvalue(frame.castIcon:GetTexture())
			end,
		},
		{
			name = "border style",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local profile = self.db.profile
				local mode = NameplateLogic.BorderMode(profile.border, profile.borderStyle)
				local checked, bad = 0, 0
				for _, frame in pairs(self.plateFrames) do
					if frame:IsShown() then
						checked = checked + 1
						local thin = frame.border.top:IsShown() == true
						local shadow = frame.shadow[1]:IsShown() == true
						if thin ~= (mode == "thin") or shadow ~= (mode == "shadow") then
							bad = bad + 1
						end
					end
				end
				if checked == 0 then
					return "SKIP", "no styled plates", mode
				end
				return (bad == 0) and "PASS" or "FAIL", mode, checked, bad
			end,
		},
		{
			name = "highlight",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local style = self.db.profile.targetStyle
				if style == "none" then
					return "SKIP", "no target indicator"
				end

				local mismatches = 0
				local secretCount = 0
				local total = 0

				for unit, plate in pairs(self.unitPlates) do
					local frame = self.plateFrames[plate]
					if frame then
						total = total + 1
						local isTarget = UnitIsUnit(unit, "target")
						local alpha = frame.targetParts[style][1]:GetAlpha()
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
					return "INFO", style, mismatches, secretCount, total
				end
				return (mismatches == 0) and "PASS" or "FAIL", style, mismatches, secretCount, total
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
			name = "combo points",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not self:ComboActive() then
					return "SKIP", "combo points off or class without combo points"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local _, frame = getTargetFrame()
				if not frame then
					return "SKIP", "target not styled"
				end

				local points = GetComboPoints("player", "target")
				local shown = frame.comboRow:IsShown() == true
				if issecretvalue(points) then
					return shown and "INFO" or "FAIL", "secret", shown
				end

				local ok = shown == (points > 0)
				for i, pip in ipairs(frame.comboPips) do
					local value = pip:GetValue()
					if issecretvalue(value) then
						return ok and "INFO" or "FAIL", points, shown, "pips secret"
					end
					local expected = math.max(i - 1, math.min(i, points))
					ok = ok and math.abs(value - expected) <= 0.01
				end
				return ok and "PASS" or "FAIL", points, shown
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

				local timerPath, timerSize = "no timers", nil
				if C_Secrets.ShouldAurasBeSecret() then
					timerPath = "auras secret"
				else
					local _, timer = next(debuffTimerTexts)
					if timer then
						timerPath, timerSize = timer:GetFont()
						ok = ok
							and normalizePath(timerPath) == normalizePath(expected)
							and math.abs(timerSize - profile.debuffTimerSize) <= 0.5
					end
				end

				return ok and "PASS" or "FAIL",
					path,
					self.appliedFont,
					expected,
					frame.healthBar:GetStatusBarTexture():GetTexture(),
					ns.Media:Resolve("statusbar", profile.barTexture),
					frame.barPath,
					timerPath,
					timerSize,
					profile.debuffTimerSize
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
