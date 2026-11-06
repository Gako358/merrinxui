local addonName, ns = ...

local L = ns.CastBarLogic
local FontLogic = ns.FontLogic

local CastBars = ns.addon:NewModule("CastBars", "AceEvent-3.0")

local SHIELD_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Small-Shield"
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local CAST_COLOR = { 0.9, 0.6, 0.1 }
local UNINTERRUPTIBLE_COLOR = { 0.45, 0.45, 0.45 }
local INTERRUPTED_COLOR = { 0.8, 0, 0 }
local SWING_COLORS = {
	main = { 0.85, 0.85, 0.85 },
	off = { 0.55, 0.6, 0.95 },
	ranged = { 0.45, 0.8, 0.4 },
}
local INTERRUPTED_HOLD = 1
local INTERRUPTED_TEXT = "Interrupted"
local TEXT_INTERVAL = 0.1
local ICON_GAP = 1
local SWING_GAP = 2

-- Forever's own swing API (Blizzard_SwingTimer); addons have no combat log.
local SWING_API = C_SwingTimer ~= nil and Enum.PlayerSwingType ~= nil
local SWING_KEYS = {}
if SWING_API then
	SWING_KEYS[Enum.PlayerSwingType.MainHand] = "main"
	SWING_KEYS[Enum.PlayerSwingType.OffHand] = "off"
	SWING_KEYS[Enum.PlayerSwingType.Ranged] = "ranged"
end

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

local function unitDefaults(enabled, width, height, x, y)
	return {
		enabled = enabled,
		width = width,
		height = height,
		icon = true,
		timeText = true,
		position = { point = "CENTER", x = x, y = y },
	}
end

local defaults = {
	profile = {
		enabled = false,
		font = FontLogic.GLOBAL,
		barTexture = FontLogic.GLOBAL,
		fontSize = 11,
		bgOpacity = 60,
		units = {
			player = unitDefaults(true, 260, 22, 0, -240),
			target = unitDefaults(true, 220, 18, 280, -240),
			focus = unitDefaults(false, 180, 16, -280, -120),
		},
		swing = {
			enabled = true,
			width = 200,
			height = 8,
			offHand = true,
			ranged = true,
			timeText = false,
			position = { point = "CENTER", x = 0, y = -275 },
		},
	},
}

local function isSecret(v)
	return issecretvalue(v) == true
end

-- A secret duration can't be nil-checked, so the NeverSecret castBarID
-- return stands in for it.
local function isCasting(unit)
	local d = UnitCastingDuration(unit)
	if not isSecret(d) then
		return d ~= nil
	end
	local castBarID = select(10, UnitCastingInfo(unit))
	return not isSecret(castBarID) and castBarID ~= nil
end

local function isChanneling(unit)
	local d = UnitChannelDuration(unit)
	if not isSecret(d) then
		return d ~= nil
	end
	local castBarID = select(11, UnitChannelInfo(unit))
	return not isSecret(castBarID) and castBarID ~= nil
end

function CastBars:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("CastBars", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.bars = {}
	self.canSwing = { main = true, off = false, ranged = false }
	self.swingKeys = {}
end

function CastBars:OnEnable()
	self:Build()
	for event, handler in pairs(CAST_EVENTS) do
		self:RegisterEvent(event, handler)
	end
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", "OnFocusChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombat")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombat")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "UpdateSwingVisibility")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "Layout")
	if SWING_API then
		self:RegisterEvent("PLAYER_SWING", "OnSwing")
		self:RegisterEvent("UNIT_ATTACK_SPEED", "OnAttackSpeed")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "RefreshSwingSlots")
	end
	self.inCombat = InCombatLockdown() == true
	self:ApplyBlizzard()
	self:Layout()
	self:RefreshSwingSlots()
	self:SyncAll()
end

function CastBars:OnDisable()
	for _, bar in pairs(self.bars) do
		self:HideCast(bar)
		bar.frame:Hide()
	end
	if self.swing then
		self.swing.frame:Hide()
	end
	if self.blizzHidden then
		ns.addon:Print("CastBars: /reload restores Blizzard's cast bar")
	end
end

function CastBars:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:ApplyBlizzard()
			self:Layout()
			self:SyncAll()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function CastBars:ApplyBlizzard()
	if not self.db.profile.units.player.enabled then
		return
	end
	self.blizzHidden = true
	ns.Combat:Run("CastBars:Blizzard", function()
		ns.addon:GetModule("HideBlizzard"):Ensure("castBar")
	end)
end

function CastBars:Build()
	if self.swing then
		return
	end
	for _, unit in ipairs(L.UNITS) do
		self.bars[unit] = self:CreateCastBar(unit)
	end
	self:CreateSwing()
end

function CastBars:CreateCastBar(unit)
	local frame = CreateFrame("Frame", addonName .. "CastBar_" .. unit, UIParent)
	frame:Hide()

	local cast = CreateFrame("Frame", nil, frame)
	cast:SetAllPoints()
	cast:Hide()

	local icon = cast:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT")
	icon:SetPoint("BOTTOMLEFT")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local status = CreateFrame("StatusBar", nil, cast)
	local bg = status:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()

	local tint = status:CreateTexture(nil, "ARTWORK", nil, 6)
	tint:SetColorTexture(UNINTERRUPTIBLE_COLOR[1], UNINTERRUPTIBLE_COLOR[2], UNINTERRUPTIBLE_COLOR[3], 1)
	tint:SetAlpha(0)

	local flash = status:CreateTexture(nil, "ARTWORK", nil, 7)
	flash:SetAllPoints()
	flash:SetColorTexture(INTERRUPTED_COLOR[1], INTERRUPTED_COLOR[2], INTERRUPTED_COLOR[3], 1)
	flash:SetAlpha(0)

	local spark = status:CreateTexture(nil, "OVERLAY")
	spark:SetTexture(SPARK_TEXTURE)
	spark:SetBlendMode("ADD")

	local shield = status:CreateTexture(nil, "OVERLAY")
	shield:SetTexture(SHIELD_TEXTURE)
	shield:SetPoint("CENTER", status, "LEFT", 0, 0)
	shield:SetAlpha(0)

	local time = status:CreateFontString(nil, "OVERLAY")
	time:SetPoint("RIGHT", status, "RIGHT", -4, 0)
	local text = status:CreateFontString(nil, "OVERLAY")
	text:SetPoint("LEFT", status, "LEFT", 4, 0)
	text:SetPoint("RIGHT", time, "LEFT", -4, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)

	local bar = {
		unit = unit,
		frame = frame,
		cast = cast,
		icon = icon,
		status = status,
		bg = bg,
		tint = tint,
		flash = flash,
		spark = spark,
		shield = shield,
		time = time,
		text = text,
	}

	local elapsed = 0
	cast:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= TEXT_INTERVAL then
			elapsed = 0
			self:UpdateTime(bar)
		end
	end)

	ns.Mover:Register(frame, "Cast Bar " .. L.LABELS[unit], function()
		return self.db.profile.units[unit].position
	end)
	return bar
end

function CastBars:CreateSwing()
	local frame = CreateFrame("Frame", addonName .. "SwingTimer", UIParent)
	frame:Hide()
	local rows = {}
	for _, key in ipairs(L.SWINGS) do
		local status = CreateFrame("StatusBar", nil, frame)
		status:SetMinMaxValues(0, 1)
		status:Hide()
		local bg = status:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		local time = status:CreateFontString(nil, "OVERLAY")
		time:SetPoint("RIGHT", status, "RIGHT", -2, 0)
		rows[key] = { key = key, status = status, bg = bg, time = time }
	end
	frame:SetScript("OnUpdate", function()
		self:UpdateSwing()
	end)
	self.swing = { frame = frame, rows = rows }
	ns.Mover:Register(frame, "Swing Timer", function()
		return self.db.profile.swing.position
	end)
end

-- A new statusbar texture may come with a new fill region.
local function anchorFill(bar)
	local fill = bar.status:GetStatusBarTexture()
	bar.spark:ClearAllPoints()
	bar.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
	bar.tint:ClearAllPoints()
	bar.tint:SetAllPoints(fill)
end

function CastBars:Layout()
	if not self.swing then
		return
	end
	local p = self.db.profile
	for unit, bar in pairs(self.bars) do
		local u = p.units[unit]
		bar.frame:SetSize(u.width, u.height)
		ns.Mover:Apply(bar.frame)

		bar.icon:SetSize(u.height, u.height)
		bar.icon:SetShown(u.icon)
		bar.status:ClearAllPoints()
		bar.status:SetPoint("TOPRIGHT")
		bar.status:SetPoint("BOTTOMRIGHT")
		if u.icon then
			bar.status:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", ICON_GAP, 0)
			bar.status:SetPoint("BOTTOMLEFT", bar.icon, "BOTTOMRIGHT", ICON_GAP, 0)
		else
			bar.status:SetPoint("TOPLEFT")
			bar.status:SetPoint("BOTTOMLEFT")
		end

		ns.Media:SetStatusBarTexture(bar.status, p.barTexture)
		bar.status:SetStatusBarColor(CAST_COLOR[1], CAST_COLOR[2], CAST_COLOR[3])
		anchorFill(bar)
		bar.bg:SetColorTexture(0, 0, 0, p.bgOpacity / 100)
		bar.spark:SetSize(12, u.height * 2)
		bar.shield:SetSize(u.height * 1.6, u.height * 1.6)
		ns.Media:SetFont(bar.text, p.font, p.fontSize, "OUTLINE")
		ns.Media:SetFont(bar.time, p.font, p.fontSize, "OUTLINE")
		bar.time:SetShown(u.timeText)

		bar.frame:SetShown(u.enabled)
		if not u.enabled then
			self:HideCast(bar)
		end
	end
	self:LayoutSwing()
end

function CastBars:ActiveBar(unit)
	local bar = self.bars[unit]
	if bar and self:IsEnabled() and self.db.profile.units[unit].enabled then
		return bar
	end
	return nil
end

function CastBars:SyncAll()
	for _, unit in ipairs(L.UNITS) do
		self:Sync(unit)
	end
end

function CastBars:Sync(unit)
	local bar = self.bars[unit]
	if not bar then
		return
	end
	if not self:ActiveBar(unit) or not UnitExists(unit) then
		self:HideCast(bar)
	elseif isCasting(unit) then
		self:OnCastStart(nil, unit)
	elseif isChanneling(unit) then
		self:OnChannelStart(nil, unit)
	else
		self:HideCast(bar)
	end
end

function CastBars:OnTargetChanged()
	self:Sync("target")
end

function CastBars:OnFocusChanged()
	self:Sync("focus")
end

function CastBars:OnEnteringWorld()
	self:SyncAll()
	self:RefreshSwingSlots()
end

function CastBars:ApplyShield(bar, notInterruptible)
	if isSecret(notInterruptible) then
		bar.shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
		bar.tint:SetAlphaFromBoolean(notInterruptible, 1, 0)
	else
		bar.shield:SetAlpha(notInterruptible and 1 or 0)
		bar.tint:SetAlpha(notInterruptible and 1 or 0)
	end
end

function CastBars:ShowCast(bar, name, texture, notInterruptible)
	bar.token = (bar.token or 0) + 1
	bar.flash:SetAlpha(0)
	bar.spark:Show()
	bar.icon:SetTexture(texture)
	bar.text:SetText(name)
	bar.time:SetText("")
	if bar.unit == "player" then
		self:ApplyShield(bar, false)
	else
		self:ApplyShield(bar, notInterruptible)
	end
	bar.cast:Show()
	self:UpdateTime(bar)
end

function CastBars:HideCast(bar)
	bar.mode = nil
	bar.duration = nil
	bar.castGUID = nil
	bar.cast:Hide()
end

-- The engine accepts the secret durations of other units' casts here.
function CastBars:UpdateTime(bar)
	if bar.duration and bar.time:IsShown() then
		bar.time:SetFormattedText("%.1f", bar.duration:GetRemainingDuration())
	end
end

function CastBars:OnCastStart(event, unit, castGUID)
	local bar = self:ActiveBar(unit)
	if not bar then
		return
	end
	local d = UnitCastingDuration(unit)
	if not isSecret(d) and d == nil then
		return
	end
	local name, _, texture, _, _, _, castID, notInterruptible = UnitCastingInfo(unit)
	bar.mode = "cast"
	if isSecret(castGUID) or castGUID ~= nil then
		bar.castGUID = castGUID
	else
		bar.castGUID = castID
	end
	bar.duration = d
	bar.status:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
	self:ShowCast(bar, name, texture, notInterruptible)
	if event == "UNIT_SPELLCAST_START" and unit == "player" then
		ns.Debug:Log("CastBars", "cast", unit)
	end
end

function CastBars:OnChannelStart(event, unit, castGUID)
	local bar = self:ActiveBar(unit)
	if not bar then
		return
	end
	local d = UnitChannelDuration(unit)
	if not isSecret(d) and d == nil then
		return
	end
	local name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(unit)
	bar.mode = "channel"
	bar.castGUID = castGUID
	bar.duration = d
	bar.status:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
	self:ShowCast(bar, name, texture, notInterruptible)
	if event == "UNIT_SPELLCAST_CHANNEL_START" and unit == "player" then
		ns.Debug:Log("CastBars", "channel", unit)
	end
end

function CastBars:OnCastStop(_, unit, castGUID)
	local bar = self.bars[unit]
	if bar and bar.mode == "cast" and L.SameCast(bar.castGUID, castGUID, isSecret) then
		self:HideCast(bar)
	end
end

function CastBars:OnChannelStop(_, unit, castGUID)
	local bar = self.bars[unit]
	if bar and bar.mode == "channel" and L.SameCast(bar.castGUID, castGUID, isSecret) then
		self:HideCast(bar)
	end
end

function CastBars:OnCastInterrupted(_, unit, castGUID)
	local bar = self:ActiveBar(unit)
	if not bar or not L.SameCast(bar.castGUID, castGUID, isSecret) then
		return
	end
	bar.mode = "interrupted"
	bar.duration = nil
	bar.castGUID = nil
	local token = (bar.token or 0) + 1
	bar.token = token
	bar.flash:SetAlpha(1)
	bar.spark:Hide()
	bar.shield:SetAlpha(0)
	bar.tint:SetAlpha(0)
	bar.text:SetText(INTERRUPTED_TEXT)
	bar.time:SetText("")
	bar.cast:Show()
	C_Timer.After(INTERRUPTED_HOLD, function()
		if bar.token == token and bar.mode == "interrupted" then
			self:HideCast(bar)
		end
	end)
end

function CastBars:OnInterruptibleChanged(_, unit)
	local bar = self.bars[unit]
	if not bar or unit == "player" then
		return
	end
	if bar.mode == "cast" then
		local _, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
		self:ApplyShield(bar, notInterruptible)
	elseif bar.mode == "channel" then
		local _, _, _, _, _, _, notInterruptible = UnitChannelInfo(unit)
		self:ApplyShield(bar, notInterruptible)
	end
end

function CastBars:LayoutSwing()
	local swing = self.swing
	local p = self.db.profile
	local s = p.swing
	local keys = L.SwingRows({ off = s.offHand, ranged = s.ranged }, self.canSwing)
	swing.frame:SetSize(s.width, L.StackHeight(#keys, s.height, SWING_GAP))
	ns.Mover:Apply(swing.frame)
	for _, row in pairs(swing.rows) do
		row.status:Hide()
	end
	for i, key in ipairs(keys) do
		local row = swing.rows[key]
		local y = -(i - 1) * (s.height + SWING_GAP)
		row.status:ClearAllPoints()
		row.status:SetPoint("TOPLEFT", swing.frame, "TOPLEFT", 0, y)
		row.status:SetPoint("TOPRIGHT", swing.frame, "TOPRIGHT", 0, y)
		row.status:SetHeight(s.height)
		ns.Media:SetStatusBarTexture(row.status, p.barTexture)
		local c = SWING_COLORS[key]
		row.status:SetStatusBarColor(c[1], c[2], c[3])
		row.bg:SetColorTexture(0, 0, 0, p.bgOpacity / 100)
		ns.Media:SetFont(row.time, p.font, p.fontSize, "OUTLINE")
		row.time:SetShown(s.timeText)
		row.status:Show()
	end
	self.swingKeys = keys
	self:UpdateSwing()
	self:UpdateSwingVisibility()
end

function CastBars:UpdateSwingVisibility()
	if not self.swing then
		return
	end
	local s = self.db.profile.swing
	local show = SWING_API
		and self:IsEnabled()
		and s.enabled
		and (ns.Mover:IsUnlocked() or self.inCombat or self.swingLive == true)
	self.swing.frame:SetShown(show == true)
end

function CastBars:UpdateSwing()
	local now = GetTime()
	local live = false
	for _, key in ipairs(self.swingKeys) do
		local row = self.swing.rows[key]
		local fill, left = L.SwingProgress(row.start, row.duration, now)
		row.status:SetValue(fill)
		if left > 0 then
			live = true
			row.time:SetFormattedText("%.1f", left)
		else
			row.time:SetText("")
		end
	end
	if live ~= (self.swingLive == true) then
		self.swingLive = live
		self:UpdateSwingVisibility()
	end
end

function CastBars:OnSwing(_, duration, swingType)
	if isSecret(duration) or isSecret(swingType) then
		return
	end
	local key = SWING_KEYS[swingType]
	if not key or not self.swing then
		return
	end
	local row = self.swing.rows[key]
	row.start = GetTime()
	row.duration = duration
	if not self.canSwing[key] then
		self.canSwing[key] = true
		self:LayoutSwing()
	end
	self.swingLive = true
	self:UpdateSwingVisibility()
end

function CastBars:OnAttackSpeed(_, unit)
	if unit == "player" then
		self:RefreshSwingSlots()
	end
end

function CastBars:RefreshSwingSlots()
	if not SWING_API or not self.swing then
		return
	end
	local _, off, ranged = UnitAttackSpeed("player")
	local merged = L.MergeSwing(self.canSwing, L.CanSwing(off, ranged, isSecret))
	local changed = false
	for _, key in ipairs(L.SWINGS) do
		changed = changed or merged[key] ~= self.canSwing[key]
	end
	self.canSwing = merged
	if changed then
		self:LayoutSwing()
	end
end

function CastBars:OnCombat(event)
	self.inCombat = event == "PLAYER_REGEN_DISABLED"
	self:UpdateSwingVisibility()
end

function CastBars:GetOptions()
	local cb = self
	local function get(key)
		return function()
			return cb.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			cb.db.profile[key] = value
			cb:Refresh()
		end
	end
	local function range(name, order, min, max, step, getter, setter)
		return {
			type = "range",
			name = name,
			order = order,
			min = min,
			max = max,
			step = step,
			get = getter,
			set = setter,
		}
	end

	local args = {
		enabled = { type = "toggle", name = "Enabled", order = 1, get = get("enabled"), set = set("enabled") },
		font = {
			type = "select",
			name = "Font",
			order = 2,
			dialogControl = "LSM30_Font",
			values = function()
				return ns.Media:Values("font", cb.db.profile.font)
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
				return ns.Media:Values("statusbar", cb.db.profile.barTexture)
			end,
			get = get("barTexture"),
			set = set("barTexture"),
		},
		fontSize = range("Font size", 4, 8, 20, 1, get("fontSize"), set("fontSize")),
		bgOpacity = range("Background opacity", 5, 0, 100, 5, get("bgOpacity"), set("bgOpacity")),
	}

	for i, unit in ipairs(L.UNITS) do
		local function uget(key)
			return function()
				return cb.db.profile.units[unit][key]
			end
		end
		local function uset(key)
			return function(_, value)
				cb.db.profile.units[unit][key] = value
				cb:Refresh()
			end
		end
		local desc = unit == "player" and "Showing it hides Blizzard's player cast bar until /reload" or nil
		args[unit] = {
			type = "group",
			name = L.LABELS[unit] .. " Cast Bar",
			order = 10 + i,
			inline = true,
			args = {
				enabled = {
					type = "toggle",
					name = "Show",
					desc = desc,
					order = 1,
					get = uget("enabled"),
					set = uset("enabled"),
				},
				width = range("Width", 2, 60, 500, 1, uget("width"), uset("width")),
				height = range("Height", 3, 8, 50, 1, uget("height"), uset("height")),
				icon = { type = "toggle", name = "Spell icon", order = 4, get = uget("icon"), set = uset("icon") },
				timeText = {
					type = "toggle",
					name = "Time text",
					order = 5,
					get = uget("timeText"),
					set = uset("timeText"),
				},
			},
		}
	end

	local function sget(key)
		return function()
			return cb.db.profile.swing[key]
		end
	end
	local function sset(key)
		return function(_, value)
			cb.db.profile.swing[key] = value
			cb:Refresh()
		end
	end
	args.swing = {
		type = "group",
		name = "Swing Timer",
		order = 20,
		inline = true,
		disabled = function()
			return not SWING_API
		end,
		args = {
			enabled = {
				type = "toggle",
				name = "Show",
				desc = SWING_API and "Shown in combat and while a swing is running"
					or "This client has no swing timer API",
				order = 1,
				get = sget("enabled"),
				set = sset("enabled"),
			},
			width = range("Width", 2, 60, 500, 1, sget("width"), sset("width")),
			height = range("Row height", 3, 2, 30, 1, sget("height"), sset("height")),
			offHand = { type = "toggle", name = "Off hand", order = 4, get = sget("offHand"), set = sset("offHand") },
			ranged = { type = "toggle", name = "Ranged", order = 5, get = sget("ranged"), set = sset("ranged") },
			timeText = {
				type = "toggle",
				name = "Time text",
				order = 6,
				get = sget("timeText"),
				set = sset("timeText"),
			},
		},
	}

	return { type = "group", name = "CastBars", args = args }
end

function CastBars:GetDebugChecks()
	local checks = {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, v in pairs({
					UnitCastingDuration = UnitCastingDuration,
					UnitChannelDuration = UnitChannelDuration,
					StatusBarTimerDirection = Enum.StatusBarTimerDirection,
					StatusBarInterpolation = Enum.StatusBarInterpolation,
				}) do
					if v == nil then
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
			name = "swing api",
			run = function()
				return "INFO", SWING_API, type(UnitAttackSpeed)
			end,
		},
	}

	for _, unit in ipairs(L.UNITS) do
		table.insert(checks, {
			name = "cast " .. unit,
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local bar = self.bars[unit]
				if not bar then
					return "FAIL", "not built"
				end
				local u = self.db.profile.units[unit]
				if bar.frame:IsShown() ~= u.enabled then
					return "FAIL", "frame", bar.frame:IsShown(), u.enabled
				end
				if not u.enabled then
					return "PASS", "off"
				end
				if bar.mode == "interrupted" then
					return "INFO", "interrupted"
				end
				local active = UnitExists(unit) and (isCasting(unit) or isChanneling(unit))
				local shown = bar.cast:IsShown()
				return (shown == active) and "PASS" or "FAIL", bar.mode or "idle", active
			end,
		})
	end

	table.insert(checks, {
		name = "swing",
		run = function(ctx)
			if ctx.enabled == false then
				return "SKIP", "module disabled"
			end
			if not SWING_API then
				return "SKIP", "no swing api"
			end
			local s = self.db.profile.swing
			local expected = s.enabled and (ns.Mover:IsUnlocked() or self.inCombat or self.swingLive == true)
			local shown = self.swing ~= nil and self.swing.frame:IsShown()
			return (shown == (expected == true)) and "PASS" or "FAIL", shown, table.concat(self.swingKeys, " ")
		end,
	})

	table.insert(checks, {
		name = "blizzard cast bar",
		run = function(ctx)
			if ctx.enabled == false then
				return "SKIP", "module disabled"
			end
			if not self.db.profile.units.player.enabled then
				return "SKIP", "player bar off"
			end
			local blizz = _G.PlayerCastingBarFrame
			if not blizz then
				return "INFO", "missing"
			end
			return (not blizz:IsVisible()) and "PASS" or "FAIL"
		end,
	})

	return checks
end
