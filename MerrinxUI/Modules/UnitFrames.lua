local addonName, ns = ...

local L = ns.UnitFrameLogic
local NL = ns.NameplateLogic

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MANA = Enum.PowerType.Mana
local MANA_COLOR = { 0, 0.55, 1 }
local HEAL_COLOR = { 0.2, 0.9, 0.3, 0.5 }
local ABSORB_COLOR = { 0.85, 0.95, 1, 0.5 }
local COST_COLOR = { 1, 1, 1, 0.4 }
local PVP_BADGES = {
	Horde = { "PvP", 0.9, 0.2, 0.2 },
	Alliance = { "PvP", 0.25, 0.55, 1 },
	FFA = { "FFA", 1, 0.6, 0 },
}

local UnitFrames = ns.addon:NewModule("UnitFrames", "AceEvent-3.0")

local function unitDefaults(width, height, powerHeight, x, y)
	return {
		enabled = true,
		width = width,
		height = height,
		powerHeight = powerHeight,
		position = { point = "CENTER", x = x, y = y },
	}
end

local defaults = {
	profile = {
		enabled = false,
		font = "Arial Narrow",
		barTexture = "Solid",
		fontSize = 12,
		healthText = "percent",
		powerText = "none",
		classColor = true,
		bgOpacity = 60,
		druidMana = true,
		druidManaHeight = 4,
		druidManaText = false,
		incomingHeals = true,
		absorbs = true,
		spellCost = true,
		pvpFlag = true,
		units = {
			player = unitDefaults(220, 44, 8, -280, -180),
			target = unitDefaults(220, 44, 8, 280, -180),
			targettarget = unitDefaults(120, 24, 0, 450, -210),
			focus = unitDefaults(180, 34, 6, -280, -60),
			pet = unitDefaults(120, 24, 4, -420, -210),
		},
	},
}

local function isSecret(v)
	return issecretvalue(v) == true
end

function UnitFrames:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("UnitFrames", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.frames = {}
	self.manaShown = false
	self.castCost = 0
	self.updates = 0
	self.tooltips = 0
	local _, class = UnitClass("player")
	self.class = class
end

function UnitFrames:OnEnable()
	ns.Combat:Run("UnitFrames:Enable", function()
		ns.addon:GetModule("HideBlizzard"):Ensure("unitFrames")
		self:Build()
		self:Layout()
		self:UpdateAll()
	end)
	for _, event in ipairs({
		"UNIT_HEALTH",
		"UNIT_MAXHEALTH",
		"UNIT_POWER_UPDATE",
		"UNIT_POWER_FREQUENT",
		"UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER",
		"UNIT_NAME_UPDATE",
		"UNIT_FACTION",
		"PLAYER_FLAGS_CHANGED",
	}) do
		self:RegisterEvent(event, "OnUnitEvent")
	end
	self:RegisterEvent("UNIT_HEAL_PREDICTION", "OnPredictionEvent")
	self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "OnPredictionEvent")
	self:RegisterEvent("UNIT_SPELLCAST_START", "OnCastStart")
	for _, event in ipairs({
		"UNIT_SPELLCAST_STOP",
		"UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED",
		"UNIT_SPELLCAST_SUCCEEDED",
	}) do
		self:RegisterEvent(event, "OnCastEnd")
	end
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateAll")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", "UpdateAll")
	self:RegisterEvent("UNIT_PET", "UpdateAll")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAll")
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "UpdateDruidMana")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")
	self.poller = C_Timer.NewTicker(0.2, function()
		for unit in pairs(L.POLLED) do
			self:UpdateUnit(unit)
		end
	end)
end

function UnitFrames:OnDisable()
	if self.poller then
		self.poller:Cancel()
		self.poller = nil
	end
	ns.Combat:Run("UnitFrames:Disable", function()
		for unit, frame in pairs(self.frames) do
			if L.Watched(unit) then
				UnregisterUnitWatch(frame)
			end
			frame:Hide()
		end
	end)
	ns.addon:Print("UnitFrames: /reload restores Blizzard's unit frames")
end

function UnitFrames:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			ns.Combat:Run("UnitFrames:Layout", function()
				self:Layout()
				self:UpdateAll()
			end)
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function UnitFrames:OnMediaChanged()
	self:Refresh()
end

local function newBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	return bar
end

local function newText(parent, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetJustifyH(justify)
	fs:SetWordWrap(false)
	fs:SetShadowOffset(1, -1)
	return fs
end

function UnitFrames:Build()
	for _, unit in ipairs(L.UNITS) do
		if not self.frames[unit] then
			local frame = CreateFrame("Button", "MerrinxUIUnitFrame_" .. unit, UIParent, "SecureUnitButtonTemplate")
			frame:SetAttribute("unit", unit)
			frame:SetAttribute("*type1", "target")
			frame:SetAttribute("*type2", "togglemenu")
			frame:RegisterForClicks("AnyUp")
			frame.unit = unit

			frame.bg = frame:CreateTexture(nil, "BACKGROUND")
			frame.bg:SetAllPoints()
			frame.health = newBar(frame)
			frame.power = newBar(frame)
			frame.slot = CreateFrame("Frame", nil, frame)
			frame.mana = newBar(frame.slot)

			frame.health:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
			frame.health:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
			frame.slot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
			frame.slot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
			frame.power:SetPoint("BOTTOMLEFT", frame.slot, "TOPLEFT", 0, 0)
			frame.power:SetPoint("BOTTOMRIGHT", frame.slot, "TOPRIGHT", 0, 0)
			frame.mana:SetPoint("BOTTOMLEFT", frame.slot, "BOTTOMLEFT", 0, 0)
			frame.mana:SetPoint("BOTTOMRIGHT", frame.slot, "BOTTOMRIGHT", 0, 0)
			frame.mana:SetStatusBarColor(MANA_COLOR[1], MANA_COLOR[2], MANA_COLOR[3])

			if unit == "player" then
				-- The heal bar starts where the health fill ends; clipping cuts
				-- overheal without arithmetic on possibly secret values.
				frame.health:SetClipsChildren(true)
				local fill = frame.health:GetStatusBarTexture()
				frame.heal = CreateFrame("StatusBar", nil, frame.health)
				frame.heal:SetMinMaxValues(0, 1)
				frame.heal:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
				frame.heal:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
				frame.absorb = CreateFrame("StatusBar", nil, frame.health)
				frame.absorb:SetMinMaxValues(0, 1)
				frame.absorb:SetReverseFill(true)
				frame.absorb:SetAllPoints(frame.health)

				-- Overlays the end of the power fill, the part the cast will spend.
				frame.power:SetClipsChildren(true)
				local powerFill = frame.power:GetStatusBarTexture()
				frame.cost = CreateFrame("StatusBar", nil, frame.power)
				frame.cost:SetMinMaxValues(0, 1)
				frame.cost:SetValue(0)
				frame.cost:SetReverseFill(true)
				frame.cost:SetPoint("TOPRIGHT", powerFill, "TOPRIGHT", 0, 0)
				frame.cost:SetPoint("BOTTOMRIGHT", powerFill, "BOTTOMRIGHT", 0, 0)
			end

			local text = CreateFrame("Frame", nil, frame)
			text:SetAllPoints()
			text:SetFrameLevel(frame:GetFrameLevel() + 5)
			frame.name = newText(text, "LEFT")
			frame.name:SetPoint("LEFT", frame.health, "LEFT", 4, 0)
			frame.healthText = newText(text, "RIGHT")
			frame.healthText:SetPoint("RIGHT", frame.health, "RIGHT", -4, 0)
			frame.name:SetPoint("RIGHT", frame.healthText, "LEFT", -4, 0)
			frame.powerText = newText(text, "CENTER")
			frame.powerText:SetPoint("CENTER", frame.power, "CENTER", 0, 0)
			frame.manaText = newText(text, "CENTER")
			frame.manaText:SetPoint("CENTER", frame.mana, "CENTER", 0, 0)
			if unit == "player" then
				frame.pvp = newText(text, "LEFT")
				frame.pvp:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 1, 2)
				frame.pvp:Hide()
			end

			frame:HookScript("OnShow", function()
				self:UpdateUnit(unit)
			end)
			frame:HookScript("OnEnter", function(owner)
				self:ShowTooltip(owner)
			end)
			frame:HookScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			if L.Watched(unit) then
				RegisterUnitWatch(frame)
			end
			self.frames[unit] = frame
			ns.Mover:Register(frame, "Unit Frame " .. L.LABELS[unit], function()
				return self.db.profile.units[unit].position
			end)
		end
	end
end

function UnitFrames:ShowTooltip(owner)
	if not UnitExists(owner.unit) then
		return
	end
	if type(GameTooltip_SetDefaultAnchor) == "function" then
		GameTooltip_SetDefaultAnchor(GameTooltip, owner)
	else
		GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
	end
	GameTooltip:SetUnit(owner.unit)
	GameTooltip:Show()
	self.tooltips = self.tooltips + 1
end

-- Size, fonts and textures; protected, so out of combat only.
function UnitFrames:Layout()
	local p = self.db.profile
	local texture = ns.Media:Fetch("statusbar", p.barTexture) or TEXTURE
	for unit, frame in pairs(self.frames) do
		local u = p.units[unit]
		frame:SetSize(u.width, u.height)
		ns.Mover:Apply(frame)
		frame.bg:SetColorTexture(0, 0, 0, p.bgOpacity / 100)
		for _, bar in ipairs({ frame.health, frame.power, frame.mana }) do
			bar:SetStatusBarTexture(texture)
			bar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
		end
		if frame.heal then
			frame.heal:SetStatusBarTexture(texture)
			frame.heal:SetStatusBarColor(unpack(HEAL_COLOR))
			frame.heal:SetWidth(u.width - 2)
			frame.heal:SetShown(p.incomingHeals)
			frame.absorb:SetStatusBarTexture(texture)
			frame.absorb:SetStatusBarColor(unpack(ABSORB_COLOR))
			frame.absorb:SetShown(p.absorbs)
			frame.cost:SetStatusBarTexture(texture)
			frame.cost:SetStatusBarColor(unpack(COST_COLOR))
			frame.cost:SetWidth(u.width - 2)
			frame.cost:SetShown(p.spellCost)
		end
		ns.Media:SetFont(frame.name, p.font, p.fontSize, "")
		ns.Media:SetFont(frame.healthText, p.font, p.fontSize, "")
		ns.Media:SetFont(frame.powerText, p.font, math.max(8, p.fontSize - 2), "")
		ns.Media:SetFont(frame.manaText, p.font, math.max(8, p.fontSize - 3), "")
		if frame.pvp then
			ns.Media:SetFont(frame.pvp, p.font, math.max(8, p.fontSize - 2), "")
		end
		if L.Watched(unit) then
			if u.enabled then
				RegisterUnitWatch(frame)
			else
				UnregisterUnitWatch(frame)
				frame:Hide()
			end
		else
			frame:SetShown(u.enabled)
		end
		self:LayoutBars(unit)
	end
end

-- Only non-protected children change here, so it also runs in combat when a
-- druid shifts form.
function UnitFrames:LayoutBars(unit)
	local frame = self.frames[unit]
	local p = self.db.profile
	local u = p.units[unit]
	local showMana = unit == "player" and self.manaShown
	local health, power, slot = L.BarHeights(u.height - 2, u.powerHeight, p.druidManaHeight, showMana)
	frame.health:SetHeight(math.max(1, health))
	frame.power:SetHeight(math.max(0.001, power))
	frame.power:SetShown(power > 0)
	frame.slot:SetHeight(math.max(0.001, slot))
	frame.mana:SetHeight(math.max(0.001, slot - 1))
	frame.slot:SetShown(slot > 0)
	frame.manaText:SetShown(showMana and p.druidManaText)
end

function UnitFrames:UpdateAll()
	if not self:IsEnabled() then
		return
	end
	self:UpdateDruidMana()
	for unit in pairs(self.frames) do
		self:UpdateUnit(unit)
	end
end

function UnitFrames:OnUnitEvent(event, unit)
	if not self.frames[unit] then
		return
	end
	if
		unit == "player" and (event == "UNIT_DISPLAYPOWER" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER")
	then
		self:UpdateDruidMana()
	end
	for _, u in ipairs(L.EventUnits(unit)) do
		self:UpdateUnit(u)
	end
end

function UnitFrames:HealthColor(unit)
	local p = self.db.profile
	local isPlayer = UnitIsPlayer(unit)
	local _, class = UnitClass(unit)
	local reaction = UnitReaction(unit, "player")
	local tapped = UnitIsTapDenied(unit)
	if isSecret(isPlayer) then
		isPlayer = false
	end
	if isSecret(class) then
		class = nil
	end
	if isSecret(reaction) then
		reaction = nil
	end
	if isSecret(tapped) then
		tapped = false
	end
	if not p.classColor then
		class = nil
	end
	return NL.PlateColor(
		{ reaction = reaction, isPlayer = isPlayer, classFile = class, tapDenied = tapped },
		RAID_CLASS_COLORS
	)
end

function UnitFrames:UpdateUnit(unit)
	local frame = self.frames[unit]
	if not frame or not frame:IsVisible() or not UnitExists(unit) then
		return
	end
	local p = self.db.profile
	self.updates = self.updates + 1

	local health = UnitHealth(unit)
	local maxHealth = UnitHealthMax(unit)
	frame.health:SetMinMaxValues(0, maxHealth)
	frame.health:SetValue(health)
	if frame.heal then
		self:UpdatePrediction(frame, maxHealth)
	end
	frame.health:SetStatusBarColor(self:HealthColor(unit))
	frame.healthText:SetText(
		NL.FormatValue(
			p.healthText,
			AbbreviateNumbers(health),
			UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
		)
	)
	frame.name:SetText(UnitName(unit))
	if frame.pvp then
		self:UpdatePvP(frame)
	end

	if frame.power:IsShown() then
		local power = UnitPower(unit)
		frame.power:SetMinMaxValues(0, UnitPowerMax(unit))
		frame.power:SetValue(power)
		local _, token = UnitPowerType(unit)
		if isSecret(token) then
			token = nil
		end
		frame.power:SetStatusBarColor(NL.PowerColor(token))
		if frame.cost then
			self:UpdateCost()
		end
		frame.powerText:SetText(
			NL.FormatValue(
				p.powerText,
				AbbreviateNumbers(power),
				UnitPowerPercent(unit, nil, false, CurveConstants.ScaleTo100)
			)
		)
	end

	if unit == "player" and self.manaShown then
		local mana = UnitPower("player", MANA)
		frame.mana:SetMinMaxValues(0, UnitPowerMax("player", MANA))
		frame.mana:SetValue(mana)
		if p.druidManaText then
			frame.manaText:SetText(AbbreviateNumbers(mana))
		end
	end
end

function UnitFrames:PvPBadge()
	local isPvP, isFFA, faction = UnitIsPVP("player"), UnitIsPVPFreeForAll("player"), UnitFactionGroup("player")
	if isSecret(isPvP) then
		isPvP = nil
	end
	if isSecret(isFFA) then
		isFFA = nil
	end
	if isSecret(faction) then
		faction = nil
	end
	return L.PvPBadge(isPvP, isFFA, faction)
end

function UnitFrames:UpdatePvP(frame)
	local badge = self.db.profile.pvpFlag and PVP_BADGES[self:PvPBadge()] or nil
	frame.pvp:SetShown(badge ~= nil)
	if badge then
		frame.pvp:SetText(badge[1])
		frame.pvp:SetTextColor(badge[2], badge[3], badge[4])
	end
end

function UnitFrames:UpdatePrediction(frame, maxHealth)
	if frame.heal:IsShown() then
		frame.heal:SetMinMaxValues(0, maxHealth)
		frame.heal:SetValue(L.Amount(UnitGetIncomingHeals("player"), isSecret))
	end
	if frame.absorb:IsShown() then
		frame.absorb:SetMinMaxValues(0, maxHealth)
		frame.absorb:SetValue(L.Amount(UnitGetTotalAbsorbs("player"), isSecret))
	end
end

function UnitFrames:OnPredictionEvent(_, unit)
	local frame = self.frames.player
	if unit ~= "player" or not frame or not frame:IsVisible() then
		return
	end
	self:UpdatePrediction(frame, UnitHealthMax("player"))
end

function UnitFrames:UpdateCost()
	local frame = self.frames.player
	if not frame or not frame.cost:IsShown() or not frame.power:IsVisible() then
		return
	end
	frame.cost:SetMinMaxValues(0, UnitPowerMax("player"))
	frame.cost:SetValue(self.castCost)
end

function UnitFrames:OnCastStart(_, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	local costs = nil
	if not isSecret(spellID) and spellID ~= nil then
		costs = C_Spell.GetSpellPowerCost(spellID)
	end
	self.castGUID = castGUID
	self.castCost = L.SpellCost(costs, UnitPowerType("player"), isSecret)
	self:UpdateCost()
end

function UnitFrames:OnCastEnd(_, unit, castGUID)
	if unit ~= "player" or not ns.CastBarLogic.SameCast(self.castGUID, castGUID, isSecret) then
		return
	end
	self.castGUID = nil
	self.castCost = 0
	self:UpdateCost()
end

function UnitFrames:UpdateDruidMana()
	if not self:IsEnabled() or not self.frames.player then
		return
	end
	local powerType = UnitPowerType("player")
	if isSecret(powerType) then
		return
	end
	local show = L.ShowDruidMana(self.db.profile.druidMana, self.class, powerType, MANA)
	if show ~= self.manaShown then
		self.manaShown = show
		self:LayoutBars("player")
		ns.Debug:Log("UnitFrames", "druid mana", show, powerType)
	end
	self:UpdateUnit("player")
end

function UnitFrames:GetOptions()
	local uf = self
	local function get(key)
		return function()
			return uf.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			uf.db.profile[key] = value
			uf:Refresh()
		end
	end
	local textModes = { none = "None", percent = "Percent", number = "Number", both = "Both" }
	local args = {
		enabled = { type = "toggle", name = "Enabled", order = 1, get = get("enabled"), set = set("enabled") },
		font = {
			type = "select",
			name = "Font",
			order = 2,
			dialogControl = "LSM30_Font",
			values = function()
				return ns.Media:Values("font", uf.db.profile.font)
			end,
			get = get("font"),
			set = set("font"),
		},
		barTexture = {
			type = "select",
			name = "Bar texture",
			order = 3,
			dialogControl = "LSM30_Statusbar",
			values = function()
				return ns.Media:Values("statusbar", uf.db.profile.barTexture)
			end,
			get = get("barTexture"),
			set = set("barTexture"),
		},
		fontSize = {
			type = "range",
			name = "Font size",
			order = 4,
			min = 8,
			max = 20,
			step = 1,
			get = get("fontSize"),
			set = set("fontSize"),
		},
		healthText = {
			type = "select",
			name = "Health text",
			order = 5,
			values = textModes,
			get = get("healthText"),
			set = set("healthText"),
		},
		powerText = {
			type = "select",
			name = "Power text",
			order = 6,
			values = textModes,
			get = get("powerText"),
			set = set("powerText"),
		},
		classColor = {
			type = "toggle",
			name = "Class colored health",
			order = 7,
			get = get("classColor"),
			set = set("classColor"),
		},
		bgOpacity = {
			type = "range",
			name = "Background opacity",
			order = 8,
			min = 0,
			max = 100,
			step = 5,
			get = get("bgOpacity"),
			set = set("bgOpacity"),
		},
		druid = {
			type = "group",
			name = "Druid Mana",
			order = 20,
			inline = true,
			args = {
				druidMana = {
					type = "toggle",
					name = "Mana bar in cat and bear form",
					desc = "Shows your mana under the power bar while a form uses rage or energy",
					order = 1,
					get = get("druidMana"),
					set = function(_, value)
						uf.db.profile.druidMana = value
						uf.manaShown = nil
						uf:Refresh()
					end,
				},
				druidManaHeight = {
					type = "range",
					name = "Mana bar height",
					order = 2,
					min = 2,
					max = 12,
					step = 1,
					get = get("druidManaHeight"),
					set = set("druidManaHeight"),
				},
				druidManaText = {
					type = "toggle",
					name = "Mana text",
					order = 3,
					get = get("druidManaText"),
					set = set("druidManaText"),
				},
			},
		},
		prediction = {
			type = "group",
			name = "Player Health",
			order = 21,
			inline = true,
			args = {
				incomingHeals = {
					type = "toggle",
					name = "Incoming heals",
					desc = "Shows heals being cast on you after the health fill",
					order = 1,
					get = get("incomingHeals"),
					set = set("incomingHeals"),
				},
				absorbs = {
					type = "toggle",
					name = "Shields",
					desc = "Shows absorb shields on you from the right end of the health bar",
					order = 2,
					get = get("absorbs"),
					set = set("absorbs"),
				},
				pvpFlag = {
					type = "toggle",
					name = "PvP flag",
					desc = "Shows PvP or FFA above the player frame while you are flagged",
					order = 3,
					get = get("pvpFlag"),
					set = set("pvpFlag"),
				},
			},
		},
		cost = {
			type = "group",
			name = "Player Power",
			order = 22,
			inline = true,
			args = {
				spellCost = {
					type = "toggle",
					name = "Spell cost",
					desc = "Highlights the power the spell you are casting will spend at the end of the power fill",
					order = 1,
					get = get("spellCost"),
					set = set("spellCost"),
				},
			},
		},
	}
	for i, unit in ipairs(L.UNITS) do
		local function uget(key)
			return function()
				return uf.db.profile.units[unit][key]
			end
		end
		local function uset(key)
			return function(_, value)
				uf.db.profile.units[unit][key] = value
				uf:Refresh()
			end
		end
		local function urange(key, name, order, min, max)
			return {
				type = "range",
				name = name,
				order = order,
				min = min,
				max = max,
				step = 1,
				get = uget(key),
				set = uset(key),
			}
		end
		args[unit] = {
			type = "group",
			name = L.LABELS[unit],
			order = 30 + i,
			inline = true,
			args = {
				enabled = { type = "toggle", name = "Show", order = 1, get = uget("enabled"), set = uset("enabled") },
				width = urange("width", "Width", 2, 60, 400),
				height = urange("height", "Height", 3, 14, 100),
				powerHeight = urange("powerHeight", "Power bar height", 4, 0, 30),
			},
		}
	end
	return { type = "group", name = "UnitFrames", args = args }
end

function UnitFrames:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, fn in pairs({
					RegisterUnitWatch = RegisterUnitWatch,
					UnregisterUnitWatch = UnregisterUnitWatch,
					UnitHealthPercent = UnitHealthPercent,
					UnitPowerPercent = UnitPowerPercent,
					AbbreviateNumbers = AbbreviateNumbers,
					UnitGetIncomingHeals = UnitGetIncomingHeals,
					UnitGetTotalAbsorbs = UnitGetTotalAbsorbs,
					["C_Spell.GetSpellPowerCost"] = C_Spell and C_Spell.GetSpellPowerCost,
					UnitIsPVP = UnitIsPVP,
					UnitIsPVPFreeForAll = UnitIsPVPFreeForAll,
					UnitFactionGroup = UnitFactionGroup,
				}) do
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end
				table.sort(missing)
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "frames",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local built = 0
				for _ in pairs(self.frames) do
					built = built + 1
				end
				return (built == #L.UNITS) and "PASS" or "FAIL", built, self.updates
			end,
		},
		{
			name = "tooltip",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local missing = {}
				for unit, frame in pairs(self.frames) do
					if not frame:GetScript("OnEnter") then
						missing[#missing + 1] = unit
					end
				end
				table.sort(missing)
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS", self.tooltips, type(GameTooltip_SetDefaultAnchor)
			end,
		},
		{
			name = "blizzard frames",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local visible = {}
				for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame" }) do
					local f = _G[name]
					if f and f:IsVisible() then
						table.insert(visible, name)
					end
				end
				return (#visible == 0) and "PASS" or "FAIL", unpack(visible, 1, #visible)
			end,
		},
		{
			name = "player size",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local frame = self.frames.player
				if not frame then
					return "FAIL", "missing"
				end
				local u = self.db.profile.units.player
				local w, h = frame:GetWidth(), frame:GetHeight()
				local ok = math.abs(w - u.width) <= 0.5 and math.abs(h - u.height) <= 0.5
				return ok and "PASS" or "FAIL", w, h
			end,
		},
		{
			name = "druid mana",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if self.class ~= "DRUID" then
					return "SKIP", "not a druid"
				end
				local frame = self.frames.player
				local powerType = UnitPowerType("player")
				if isSecret(powerType) then
					return "INFO", "secret"
				end
				local expected = L.ShowDruidMana(self.db.profile.druidMana, self.class, powerType, MANA)
				local shown = frame ~= nil and frame.slot:IsShown()
				return (shown == expected) and "PASS" or "FAIL", powerType, shown, expected
			end,
		},
		{
			name = "heal prediction",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local frame = self.frames.player
				if not frame or not frame.heal then
					return "FAIL", "missing"
				end
				local p = self.db.profile
				local ok = frame.heal:IsShown() == p.incomingHeals and frame.absorb:IsShown() == p.absorbs
				local heal = UnitGetIncomingHeals("player")
				local absorb = UnitGetTotalAbsorbs("player")
				return ok and "PASS" or "FAIL",
					frame.heal:IsShown(),
					frame.absorb:IsShown(),
					isSecret(heal) and "secret" or heal,
					isSecret(absorb) and "secret" or absorb
			end,
		},
		{
			name = "pvp flag",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local frame = self.frames.player
				if not frame or not frame.pvp then
					return "FAIL", "missing"
				end
				if not frame:IsVisible() then
					return "SKIP", "player frame hidden"
				end
				local badge = self:PvPBadge()
				local expected = self.db.profile.pvpFlag and badge ~= nil
				local shown = frame.pvp:IsShown()
				return (shown == expected) and "PASS" or "FAIL", shown, badge or "none"
			end,
		},
		{
			name = "spell cost",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local frame = self.frames.player
				if not frame or not frame.cost then
					return "FAIL", "missing"
				end
				local ok = frame.cost:IsShown() == self.db.profile.spellCost
				return ok and "PASS" or "FAIL",
					frame.cost:IsShown(),
					isSecret(self.castCost) and "secret" or self.castCost
			end,
		},
	}
end
