local addonName, ns = ...

local L = ns.SpellHistoryLogic
local DL = ns.DamageMeterLogic

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local POOL = 40
local HEADER_H = 22
local MIN_W = 150
local STOPPED = { 0.859, 0.255, 0.255 }

local SpellHistory = ns.addon:NewModule("SpellHistory", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = false,
		iconEnabled = false,
		barEnabled = false,
		growDirection = "LEFT",
		iconSize = 36,
		iconZoom = 8,
		iconSpacing = 1,
		iconCount = 5,
		iconOpacity = 100,
		iconFadeTime = 0,
		maxBars = 5,
		barHeight = 20,
		barWidth = 300,
		hideTopBar = false,
		barLocked = false,
		barTexture = "match",
		barColorMode = "custom",
		barColor = "4C907E",
		barOpacity = 100,
		textSize = 11,
		textColorMode = "custom",
		textColor = "FFFFFF",
		bgOpacity = 25,
		iconHideInDungeon = false,
		iconHideInRaid = false,
		iconHideInPvP = false,
		iconHideOutOfInstance = false,
		barHideInDungeon = false,
		barHideInRaid = false,
		barHideInPvP = false,
		barHideOutOfInstance = false,
		iconPosition = { point = "CENTER", x = 0, y = -150 },
		barPosition = { point = "CENTER", x = -300, y = -150 },
	},
}

local function isSecret(v)
	return issecretvalue(v) == true
end

local function hex(text, r, g, b)
	local hr, hg, hb = DL.ParseHex(text)
	if hr then
		return hr, hg, hb
	end
	return r, g, b
end

function SpellHistory:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("SpellHistory", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.history = {}
	self.pending = {}
	self.targets = {}
	self.icons = {}
	self.bars = {}
	self.scroll = 0
	self.combatEnd = 0
	self.pushes = 0
end

function SpellHistory:OnEnable()
	for _, event in ipairs({
		"UNIT_SPELLCAST_SENT",
		"UNIT_SPELLCAST_START",
		"UNIT_SPELLCAST_SUCCEEDED",
		"UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_FAILED_QUIET",
		"UNIT_SPELLCAST_INTERRUPTED",
		"UNIT_SPELLCAST_STOP",
		"UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_STOP",
	}) do
		self:RegisterEvent(event, "OnSpellEvent")
	end
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombat")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombat")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Apply")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "Apply")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "Apply")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "Apply")
	self:RegisterMessage("MERRINXUI_DM_TOGGLED", "OnToggled")
	self:Apply()
	self.fadeTicker = C_Timer.NewTicker(0.5, function()
		if self.db.profile.iconEnabled and self.db.profile.iconFadeTime > 0 then
			self:RefreshIcons()
		end
	end)
end

function SpellHistory:OnDisable()
	if self.fadeTicker then
		self.fadeTicker:Cancel()
		self.fadeTicker = nil
	end
	if self.strip then
		self.strip:Hide()
	end
	if self.window then
		self.window:Hide()
	end
end

function SpellHistory:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:Apply()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function SpellHistory:OnToggled(_, hidden)
	self.toggleHidden = hidden == true
	self:Apply()
end

function SpellHistory:OnCombat(event)
	if event == "PLAYER_REGEN_ENABLED" then
		self.combatEnd = GetTime()
	end
	self:RefreshIcons()
end

local function hiddenBy(p, prefix)
	if ns.Mover:IsUnlocked() then
		return false
	end
	local _, instType = IsInInstance()
	return DL.InstanceHidden({
		hideInDungeon = p[prefix .. "HideInDungeon"],
		hideInRaid = p[prefix .. "HideInRaid"],
		hideInPvP = p[prefix .. "HideInPvP"],
		hideOutOfInstance = p[prefix .. "HideOutOfInstance"],
	}, instType, false)
end

function SpellHistory:Apply()
	if not self:IsEnabled() then
		return
	end
	local p = self.db.profile
	if p.iconEnabled and not self.toggleHidden and not hiddenBy(p, "icon") then
		self:BuildStrip()
		self.strip:Show()
		self:RefreshIcons()
	elseif self.strip then
		self.strip:Hide()
	end
	if p.barEnabled and not self.toggleHidden and not hiddenBy(p, "bar") then
		self:BuildWindow()
		self:LayoutWindow()
		self.window:Show()
		self:RefreshBars()
	elseif self.window then
		self.window:Hide()
	end
end

local function spellInfo(spellID)
	if spellID == nil or isSecret(spellID) then
		return nil
	end
	local info = C_Spell.GetSpellInfo(spellID)
	if not info then
		return nil
	end
	return info.name, info.iconID
end

local function knownSpell(spellID)
	if IsPlayerSpell(spellID) then
		return true
	end
	return IsSpellKnownOrOverridesKnown ~= nil and IsSpellKnownOrOverridesKnown(spellID) == true
end

function SpellHistory:Push(entry)
	L.Push(self.history, entry)
	self.pushes = self.pushes + 1
	self:RefreshViews()
end

function SpellHistory:FinishPending(castGUID, status)
	local entry = castGUID and self.pending[castGUID]
	if not entry then
		return
	end
	L.Finish(entry, status, GetTime())
	self.pending[castGUID] = nil
	self.targets[castGUID] = nil
	self:RefreshViews()
end

function SpellHistory:OnSpellEvent(event, unit, ...)
	if unit ~= "player" then
		return
	end
	if event == "UNIT_SPELLCAST_SENT" then
		local target, castGUID = ...
		if castGUID and not isSecret(castGUID) and target then
			self.targets[castGUID] = target
		end
		return
	end

	local castGUID, spellID = ...
	if isSecret(castGUID) or isSecret(spellID) then
		return
	end
	local now = GetTime()
	if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
		local channel = event == "UNIT_SPELLCAST_CHANNEL_START"
		local info = channel and UnitChannelInfo or UnitCastingInfo
		local name, _, _, startMS, endMS = info("player")
		if not name or isSecret(name) or isSecret(startMS) or isSecret(endMS) then
			return
		end
		local _, icon = spellInfo(spellID)
		local entry = {
			spellID = spellID,
			spellName = name,
			icon = icon,
			target = castGUID and self.targets[castGUID],
			startTime = (startMS or 0) / 1000,
			endTime = (endMS or 0) / 1000,
			status = channel and "channeling" or "casting",
			time = now,
		}
		if channel then
			self.channelSpell = spellID
		end
		if castGUID then
			self.pending[castGUID] = entry
		end
		self:Push(entry)
		self:StartAnimation()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if castGUID and self.pending[castGUID] then
			if self.pending[castGUID].status == "casting" then
				self:FinishPending(castGUID, "success")
			end
			return
		end
		if spellID == nil or spellID == self.channelSpell or not knownSpell(spellID) then
			return
		end
		for i = 1, math.min(#self.history, 5) do
			local e = self.history[i]
			if e.spellID == spellID and L.IsStopped(e.status) and now - (e.endTime or 0) < 0.5 then
				e.status, e.fill = "success", nil
				self:RefreshViews()
				return
			end
		end
		local name, icon = spellInfo(spellID)
		if not name then
			return
		end
		self:Push({
			spellID = spellID,
			spellName = name,
			icon = icon,
			target = castGUID and self.targets[castGUID],
			startTime = now,
			endTime = now,
			status = "success",
			isInstant = true,
			time = now,
		})
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
		self:FinishPending(castGUID, "failed")
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		self:FinishPending(castGUID, "interrupted")
	elseif event == "UNIT_SPELLCAST_STOP" then
		local entry = castGUID and self.pending[castGUID]
		if entry and entry.status == "casting" then
			C_Timer.After(0, function()
				if self.pending[castGUID] == entry and entry.status == "casting" then
					self:FinishPending(castGUID, "failed")
				end
			end)
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		self.channelSpell = nil
		if castGUID then
			self.targets[castGUID] = nil
			self:FinishPending(castGUID, "success")
		end
	end
	if castGUID and not self.pending[castGUID] and event ~= "UNIT_SPELLCAST_START" then
		self.targets[castGUID] = nil
	end
end

function SpellHistory:RefreshViews()
	self:RefreshIcons()
	self:RefreshBars()
end

function SpellHistory:BuildStrip()
	if self.strip then
		return
	end
	local strip = CreateFrame("Frame", "MerrinxUISpellHistoryIcons", UIParent)
	strip:SetMovable(true)
	strip:SetClampedToScreen(true)
	strip:EnableMouse(true)
	strip:RegisterForDrag("LeftButton")
	strip:SetScript("OnDragStart", function(frame)
		if IsShiftKeyDown() then
			frame:StartMoving()
		end
	end)
	strip:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		self:SaveCenter(frame, self.db.profile.iconPosition)
	end)
	self.strip = strip
	ns.Mover:Register(strip, "Spell History Icons", function()
		return self.db.profile.iconPosition
	end)
end

function SpellHistory:SaveCenter(frame, pos)
	local cx, cy = frame:GetCenter()
	if not cx then
		return
	end
	local x, y = ns.MoverLogic.CenterOffset(
		cx,
		cy,
		frame:GetEffectiveScale(),
		UIParent:GetWidth(),
		UIParent:GetHeight(),
		UIParent:GetEffectiveScale()
	)
	pos.point, pos.x, pos.y = "CENTER", x, y
	ns.Mover:Apply(frame)
end

function SpellHistory:RefreshIcons()
	local strip = self.strip
	if not strip or not strip:IsShown() then
		return
	end
	local p = self.db.profile
	strip:SetSize(p.iconSize, p.iconSize)
	ns.Mover:Apply(strip)
	local zoom = p.iconZoom / 100
	local now = GetTime()
	local inCombat = InCombatLockdown()
	for i = 1, p.iconCount do
		local tex = self.icons[i]
		if not tex then
			tex = strip:CreateTexture(nil, "ARTWORK")
			self.icons[i] = tex
		end
		local entry = self.history[i]
		if entry and entry.icon and L.IconVisible(entry.time, self.combatEnd, now, p.iconFadeTime, inCombat) then
			local x, y = L.IconOffset(i, p.iconSize, p.iconSpacing, p.growDirection)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", strip, "CENTER", x, y)
			tex:SetSize(p.iconSize, p.iconSize)
			tex:SetTexture(entry.icon)
			tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
			tex:SetAlpha(p.iconOpacity / 100)
			tex:SetDesaturated(L.IsStopped(entry.status))
			tex:Show()
		else
			tex:Hide()
		end
	end
	for i = p.iconCount + 1, #self.icons do
		self.icons[i]:Hide()
	end
end

function SpellHistory:MeterProfile()
	local dm = ns.addon:GetModule("DamageMeter", true)
	return dm and dm.db.profile
end

function SpellHistory:BuildWindow()
	if self.window then
		return
	end
	local win = CreateFrame("Frame", "MerrinxUISpellHistory", UIParent)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win.bg = win:CreateTexture(nil, "BACKGROUND")
	win.bg:SetAllPoints()
	local header = CreateFrame("Frame", nil, win)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_H)
	header:EnableMouse(true)
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	header.bg:SetAllPoints()
	header.title = header:CreateFontString(nil, "OVERLAY")
	header.title:SetPoint("LEFT", header, "LEFT", 6, 0)
	header.title:SetText("Spell History")
	header:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and not self.db.profile.barLocked and not ns.Mover:IsUnlocked() then
			win:StartMoving()
		end
	end)
	header:SetScript("OnMouseUp", function()
		win:StopMovingOrSizing()
		self:SaveCenter(win, self.db.profile.barPosition)
	end)
	win.header = header

	local function button(icon, x)
		local btn = CreateFrame("Button", nil, header)
		btn:SetSize(16, 16)
		btn:SetPoint("RIGHT", header, "RIGHT", x, 0)
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetAllPoints()
		btn.icon:SetTexture(ns.Media:Icon(icon))
		btn.icon:SetVertexColor(1, 1, 1, 0.4)
		btn:SetScript("OnEnter", function()
			btn.icon:SetVertexColor(1, 1, 1, 0.9)
		end)
		btn:SetScript("OnLeave", function()
			btn.icon:SetVertexColor(1, 1, 1, 0.4)
		end)
		return btn
	end
	win.settings = button("settings", -3)
	win.settings:SetScript("OnClick", function()
		ns.OptionsWindow:OpenPage("SpellHistory")
	end)
	win.lock = button("unlocked", -22)
	win.lock:SetScript("OnClick", function()
		local p = self.db.profile
		p.barLocked = not p.barLocked
		self:LayoutWindow()
	end)
	win.width = button("width", -41)
	local sizer = CreateFrame("Frame")
	sizer:Hide()
	sizer:SetScript("OnUpdate", function()
		local x = GetCursorPosition() / win:GetEffectiveScale()
		win:SetWidth(math.max(MIN_W, win.sizeStartW + (x - win.sizeStartX)))
	end)
	win.width:SetScript("OnMouseDown", function(_, btn)
		if btn ~= "LeftButton" or self.db.profile.barLocked then
			return
		end
		local left, top = win:GetLeft(), win:GetTop()
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		win.sizeStartX = GetCursorPosition() / win:GetEffectiveScale()
		win.sizeStartW = win:GetWidth()
		sizer:Show()
	end)
	win.width:SetScript("OnMouseUp", function()
		if sizer:IsShown() then
			sizer:Hide()
			self.db.profile.barWidth = math.floor(win:GetWidth() + 0.5)
			self:SaveCenter(win, self.db.profile.barPosition)
		end
	end)

	local content = CreateFrame("Frame", nil, win)
	content:SetPoint("BOTTOMRIGHT")
	content:EnableMouseWheel(true)
	content:SetScript("OnMouseWheel", function(_, delta)
		self.scroll = L.ClampScroll(self.scroll - delta, #self.history, self.slots or 1)
		self:RefreshBars()
	end)
	win.content = content
	self.window = win

	self.animator = CreateFrame("Frame")
	self.animator:Hide()
	self.animator:SetScript("OnUpdate", function(frame)
		if not next(self.pending) or not win:IsVisible() then
			frame:Hide()
			return
		end
		self:RefreshBars()
	end)

	ns.Mover:Register(win, "Spell History", function()
		return self.db.profile.barPosition
	end)
end

function SpellHistory:StartAnimation()
	if self.animator and self.window and self.window:IsVisible() then
		self.animator:Show()
	end
end

function SpellHistory:LayoutWindow()
	local win = self.window
	local p = self.db.profile
	local mp = self:MeterProfile() or {}
	local font = mp.font or "Arial Narrow"
	local spacing = mp.barSpacing or 2
	local headerH = p.hideTopBar and 0 or HEADER_H
	win.header:SetShown(not p.hideTopBar)
	win.content:ClearAllPoints()
	win.content:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -headerH)
	win.content:SetPoint("BOTTOMRIGHT")
	win:SetSize(math.max(MIN_W, p.barWidth), headerH + p.maxBars * (p.barHeight + spacing))
	ns.Mover:Apply(win)
	win.bg:SetColorTexture(0, 0, 0, p.bgOpacity / 100)
	local hr, hg, hb = hex(mp.hdrColor, 0x1B / 255, 0x1B / 255, 0x1B / 255)
	win.header.bg:SetColorTexture(hr, hg, hb, (mp.hdrOpacity or 100) / 100)
	ns.Media:SetFont(win.header.title, font, mp.hdrFontSize or 11, "")
	local accent = ns.Theme.color.accent
	win.header.title:SetTextColor(accent[1], accent[2], accent[3], 1)
	win.lock.icon:SetTexture(ns.Media:Icon(p.barLocked and "locked" or "unlocked"))

	local key = p.barTexture == "match" and (mp.barTexture or "Solid") or p.barTexture
	local texture = ns.Media:Fetch("statusbar", key) or TEXTURE
	for i = 1, POOL do
		local bar = self.bars[i]
		if not bar then
			bar = {}
			bar.row = CreateFrame("Frame", nil, win.content)
			bar.icon = bar.row:CreateTexture(nil, "ARTWORK")
			bar.icon:SetPoint("LEFT")
			bar.fill = CreateFrame("StatusBar", nil, bar.row)
			bar.fill:SetMinMaxValues(0, 1)
			bar.fill:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT")
			bar.fill:SetPoint("BOTTOMRIGHT")
			local text = CreateFrame("Frame", nil, bar.row)
			text:SetAllPoints(bar.fill)
			text:SetFrameLevel(bar.fill:GetFrameLevel() + 2)
			bar.label = text:CreateFontString(nil, "OVERLAY")
			bar.label:SetPoint("LEFT", text, "LEFT", 3, 0)
			bar.label:SetJustifyH("LEFT")
			bar.label:SetWordWrap(false)
			bar.right = text:CreateFontString(nil, "OVERLAY")
			bar.right:SetPoint("RIGHT", text, "RIGHT", -3, 0)
			bar.label:SetPoint("RIGHT", bar.right, "LEFT", -4, 0)
			self.bars[i] = bar
		end
		bar.row:ClearAllPoints()
		bar.row:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * (p.barHeight + spacing))
		bar.row:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", 0, -(i - 1) * (p.barHeight + spacing))
		bar.row:SetHeight(p.barHeight)
		bar.icon:SetSize(p.barHeight, p.barHeight)
		local zoom = p.iconZoom / 100
		bar.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
		bar.fill:SetStatusBarTexture(texture)
		ns.Media:SetFont(bar.label, font, p.textSize, "")
		ns.Media:SetFont(bar.right, font, p.textSize, "")
		local tr, tg, tb = hex(p.textColor, 1, 1, 1)
		if p.textColorMode == "accent" then
			tr, tg, tb = accent[1], accent[2], accent[3]
		end
		bar.label:SetTextColor(tr, tg, tb, 1)
		bar.right:SetTextColor(tr, tg, tb, 1)
	end
	self.slots = p.maxBars
end

function SpellHistory:BarColor()
	local p = self.db.profile
	if p.barColorMode == "class" then
		local _, class = UnitClass("player")
		local c = class and RAID_CLASS_COLORS[class]
		if c then
			return c.r, c.g, c.b
		end
	elseif p.barColorMode == "accent" then
		local a = ns.Theme.color.accent
		return a[1], a[2], a[3]
	end
	return hex(p.barColor, 0.298, 0.565, 0.494)
end

function SpellHistory:RefreshBars()
	local win = self.window
	if not win or not win:IsVisible() then
		return
	end
	local p = self.db.profile
	local now = GetTime()
	local slots = self.slots or p.maxBars
	self.scroll = L.ClampScroll(self.scroll, #self.history, slots)
	local r, g, b = self:BarColor()
	for i = 1, POOL do
		local bar = self.bars[i]
		local entry = self.history[self.scroll + i]
		if bar and i <= slots and entry then
			if entry.icon then
				bar.icon:SetTexture(entry.icon)
				bar.icon:Show()
			else
				bar.icon:Hide()
			end
			bar.label:SetText(entry.spellName or "?")
			if L.IsStopped(entry.status) then
				bar.fill:SetStatusBarColor(STOPPED[1], STOPPED[2], STOPPED[3], p.barOpacity / 100)
			else
				bar.fill:SetStatusBarColor(r, g, b, p.barOpacity / 100)
			end
			bar.fill:SetValue(L.Progress(entry, now))
			local target = entry.target
			if target and isSecret(target) then
				bar.right:SetText(target)
			else
				bar.right:SetText(L.RightText(entry, now, target and DL.ShortName(target)))
			end
			bar.row:Show()
		elseif bar then
			bar.row:Hide()
		end
	end
end

local function hideRules(prefix, order)
	local names = {
		{ "HideInDungeon", "Hide in Dungeons" },
		{ "HideInRaid", "Hide in Raids" },
		{ "HideInPvP", "Hide in PvP" },
		{ "HideOutOfInstance", "Hide out of Instances" },
	}
	local args = {}
	for i, pair in ipairs(names) do
		args[prefix .. pair[1]] = { key = prefix .. pair[1], name = pair[2], order = order + i }
	end
	return args
end

function SpellHistory:GetOptions()
	local sh = self
	local function get(key)
		return function()
			return sh.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			sh.db.profile[key] = value
			sh:Refresh()
		end
	end
	local function toggle(key, name, order, desc)
		return { type = "toggle", name = name, desc = desc, order = order, get = get(key), set = set(key) }
	end
	local function range(key, name, order, min, max, step)
		return {
			type = "range",
			name = name,
			order = order,
			min = min,
			max = max,
			step = step,
			get = get(key),
			set = set(key),
		}
	end
	local function choice(key, name, order, values)
		return { type = "select", name = name, order = order, values = values, get = get(key), set = set(key) }
	end
	local function colorInput(key, name, order)
		return {
			type = "input",
			name = name,
			desc = "RRGGBB",
			order = order,
			validate = function(_, value)
				return DL.ParseHex(value) ~= nil or "Enter a colour as RRGGBB"
			end,
			get = get(key),
			set = function(_, value)
				sh.db.profile[key] = DL.ToHex(DL.ParseHex(value))
				sh:Refresh()
			end,
		}
	end

	local icon = {
		iconEnabled = toggle(
			"iconEnabled",
			"Enable Icon History",
			1,
			"A movable strip of recent spell icons. Shift-drag to reposition."
		),
		growDirection = choice("growDirection", "Grow Direction", 2, {
			LEFT = "Left",
			RIGHT = "Right",
			UP = "Up",
			DOWN = "Down",
		}),
		iconSize = range("iconSize", "Icon Size", 3, 16, 64, 1),
		iconCount = range("iconCount", "Max Icons", 4, 1, 20, 1),
		iconZoom = range("iconZoom", "Zoom", 5, 0, 20, 1),
		iconSpacing = range("iconSpacing", "Icon Spacing", 6, 0, 10, 1),
		iconOpacity = range("iconOpacity", "Opacity", 7, 0, 100, 5),
		iconFadeTime = range("iconFadeTime", "Fade-Out Time", 8, 0, 60, 1),
	}
	icon.iconFadeTime.desc = "Seconds after which icons fade out. The timer pauses in combat. 0 = never."
	for k, rule in pairs(hideRules("icon", 10)) do
		icon[k] = toggle(rule.key, rule.name, rule.order)
	end

	local bar = {
		barEnabled = toggle("barEnabled", "Enable Bar History", 1, "A window with your spell casts as bars"),
		bgOpacity = range("bgOpacity", "Background Opacity", 2, 0, 100, 5),
		hideTopBar = toggle("hideTopBar", "Hide Top Bar", 3),
		barHeight = range("barHeight", "Bar Height", 4, 10, 40, 1),
		maxBars = range("maxBars", "Max Bars", 5, 1, 20, 1),
		barTexture = {
			type = "select",
			name = "Bar Texture",
			order = 6,
			dialogControl = "LSM30_Statusbar",
			values = function()
				local values = ns.Media:Values("statusbar", sh.db.profile.barTexture)
				values.match = "Match Damage Meter"
				return values
			end,
			get = get("barTexture"),
			set = set("barTexture"),
		},
		textSize = range("textSize", "Text Size", 7, 8, 18, 1),
		textColorMode = choice("textColorMode", "Text Color", 8, { custom = "Custom", accent = "Accent" }),
		textColor = colorInput("textColor", "Custom Text Color", 9),
		barColorMode = choice("barColorMode", "Bar Color", 10, {
			custom = "Custom",
			class = "Class",
			accent = "Accent",
		}),
		barColor = colorInput("barColor", "Custom Bar Color", 11),
		barOpacity = range("barOpacity", "Opacity", 12, 0, 100, 5),
		barLocked = toggle("barLocked", "Lock Window", 13),
	}
	for k, rule in pairs(hideRules("bar", 20)) do
		bar[k] = toggle(rule.key, rule.name, rule.order)
	end

	return {
		type = "group",
		name = "SpellHistory",
		args = {
			enabled = toggle("enabled", "Enabled", 1),
			icons = { type = "group", name = "Icon History", order = 10, inline = true, args = icon },
			bars = { type = "group", name = "Bar History", order = 20, inline = true, args = bar },
		},
	}
end

function SpellHistory:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, fn in pairs({
					UnitCastingInfo = UnitCastingInfo,
					UnitChannelInfo = UnitChannelInfo,
					IsPlayerSpell = IsPlayerSpell,
					GetSpellInfo = C_Spell.GetSpellInfo,
				}) do
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end
				table.sort(missing)
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS", IsSpellKnownOrOverridesKnown ~= nil
			end,
		},
		{
			name = "history",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local pending = 0
				for _ in pairs(self.pending) do
					pending = pending + 1
				end
				local top = self.history[1]
				return "INFO", #self.history, pending, self.pushes, top and top.status or "none"
			end,
		},
		{
			name = "icons",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local p = self.db.profile
				local shown = self.strip ~= nil and self.strip:IsShown()
				if not p.iconEnabled then
					return shown and "FAIL" or "PASS", "off"
				end
				local visible = 0
				for _, tex in ipairs(self.icons) do
					if tex:IsShown() then
						visible = visible + 1
					end
				end
				return (visible <= p.iconCount) and "PASS" or "FAIL", shown, visible, p.iconCount
			end,
		},
		{
			name = "bars",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local p = self.db.profile
				local shown = self.window ~= nil and self.window:IsShown()
				if not p.barEnabled then
					return shown and "FAIL" or "PASS", "off"
				end
				local rows = 0
				for _, bar in ipairs(self.bars) do
					if bar.row:IsShown() then
						rows = rows + 1
					end
				end
				local expected = shown and math.min(p.maxBars, #self.history - self.scroll) or 0
				return (rows == expected) and "PASS" or "FAIL", shown, rows, expected
			end,
		},
	}
end
