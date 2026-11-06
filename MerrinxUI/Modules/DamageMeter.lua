local addonName, ns = ...

local L = ns.DamageMeterLogic
local D = ns.DamageMeterData
local Window = ns.DamageMeterWindow
local Timer = ns.DamageMeterTimer
local Menu = ns.DamageMeterMenu
local Tooltip = ns.DamageMeterTooltip
local MoverLogic = ns.MoverLogic

BINDING_NAME_MERRINXUI_DM_TOGGLE = "Show/hide damage meter windows"
BINDING_NAME_MERRINXUI_DM_RESET = "Reset damage meter data"

local DamageMeter = ns.addon:NewModule("DamageMeter", "AceEvent-3.0")

local REFRESH_FLOOR, REFRESH_HARD_FLOOR = 0.5, 0.2
local FEIGN_DEATH = 5384
local GAP = 10

local defaults = {
	profile = {
		enabled = false,
		visibility = "always",
		refreshRate = 1,
		unsafeRefreshRate = false,
		showPinnedSelf = false,
		showPlayerMarker = false,
		hideResetButton = false,
		bgColor = "000000",
		bgOpacity = 75,
		windowBorderSize = 0,
		windowBorderColor = "000000",
		hdrHeight = 22,
		hdrOpacity = 100,
		hdrColor = "1B1B1B",
		hdrBottomBorder = 0,
		hdrBottomBorderColor = "000000",
		hdrIconSize = 18,
		iconColorUseAccent = false,
		hdrMouseoverIcons = false,
		hdrFontSize = 11,
		hdrTextUseAccent = true,
		hdrTextColor = "FFFFFF",
		hdrTextOffsetX = 0,
		hdrTextOffsetY = 0,
		font = "Arial Narrow",
		barTexture = "Solid",
		barHeight = 18,
		barSpacing = 2,
		barColorMode = "class",
		barColor = "598CCC",
		barOpacity = 100,
		iconStyle = "spec",
		iconZoom = 6,
		barBgColor = "000000",
		barBgOpacity = 0,
		barBgUseClassColor = false,
		barBorderSize = 0,
		barBorderColor = "000000",
		numberFormat = 2,
		hideNumbers = false,
		leftFontSize = 11,
		rightFontSize = 11,
		leftTextColorMode = "custom",
		leftTextColor = "FFFFFF",
		rightTextColorMode = "custom",
		rightTextColor = "FFFFFF",
		leftTextOffsetX = 0,
		leftTextOffsetY = 0,
		rightTextOffsetX = 0,
		rightTextOffsetY = 0,
		showHoverTooltip = true,
		breakdownBgOpacity = 95,
		breakdownTexture = "match",
		hoverScale = 100,
		breakdownAnchor = "row",
		moreSpells = false,
		showSpellTooltips = true,
		standaloneTimer = false,
		timerSize = 26,
		timerDecimal = false,
		timerColorMode = "custom",
		timerColor = "FFFFFF",
		timerAlign = "CENTER",
		timerWidth = 80,
		timerHeight = 36,
		timerBgColor = "000000",
		timerBgOpacity = 0,
		timerBorderSize = 0,
		timerBorderColor = "000000",
		timerStrata = "HIGH",
		timerShowOOC = false,
		timerDesatOOC = false,
		timerAnchor = "free",
		timerLocked = false,
		timerPosition = { point = "CENTER", x = 0, y = 200 },
		toggleIncludeTimer = false,
		toggleIncludeSpellHistory = false,
		windowCount = 1,
	},
}

local WINDOW_DEFAULTS = {
	width = 300,
	height = 200,
	type = "DamageDone",
	session = "Current",
	locked = false,
	snapDisabled = false,
	hideTimer = false,
	autoCurrentOnCombat = false,
	syncSegments = false,
	hideInDungeon = false,
	hideInRaid = false,
	hideInPvP = false,
	hideOutOfInstance = false,
}

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end

function DamageMeter:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("DamageMeter", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.types = L.TypeList(Enum.DamageMeterType)
	self.windows = {}
	self.parked = {}
	self.frozen = 0
	self.stamps = {}
	self.feign = {}
	self.ticks = 0
	Timer:Init(self)
end

-- Profiles from before multi-window kept one window's settings at the top
-- level; they seed window 1 once.
function DamageMeter:Migrate()
	local p = self.db.profile
	if p.windows then
		return
	end
	p.windows = {}
	local first = self:WindowDB(1)
	if type(p.metric) == "string" then
		first.type = p.metric
	end
	if p.session == "Current" or p.session == "Overall" then
		first.session = p.session
	end
	if type(p.width) == "number" then
		first.width = p.width
	end
	if type(p.position) == "table" then
		first.position = copy(p.position)
	end
	if type(p.headerOpacity) == "number" then
		p.hdrOpacity = p.headerOpacity
	end
	p.metric, p.session, p.width, p.position, p.headerOpacity = nil, nil, nil, nil, nil
	p.rows, p.rowHeight, p.fontSize = nil, nil, nil
end

function DamageMeter:WindowDB(idx)
	local p = self.db.profile
	p.windows = p.windows or {}
	local wdb = p.windows[idx]
	if not wdb then
		wdb = {}
		p.windows[idx] = wdb
	end
	for k, v in pairs(WINDOW_DEFAULTS) do
		if wdb[k] == nil then
			wdb[k] = copy(v)
		end
	end
	if type(wdb.position) ~= "table" then
		wdb.position = { point = "CENTER", x = 400 - (idx - 1) * 20, y = -200 + (idx - 1) * 20 }
	end
	return wdb
end

function DamageMeter:ResolveType(key)
	return L.ResolveType(self.types, key, "DamageDone")
end

function DamageMeter:Bookmarks(write)
	local p = self.db.profile
	if p.bookmarks then
		return p.bookmarks
	end
	local list = copy(L.HOME_DEFAULTS)
	if write then
		p.bookmarks = list
	end
	return list
end

function DamageMeter:OnEnable()
	ns.Combat:Run("DamageMeter:Ensure", function()
		ns.addon:GetModule("HideBlizzard"):Ensure("damageMeter")
	end)
	self:Migrate()

	self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", "OnSessionUpdated")
	self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", "OnSessionUpdated")
	self:RegisterEvent("DAMAGE_METER_RESET", "OnMeterReset")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
	self:RegisterEvent("ENCOUNTER_START", "OnCombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZone")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZone")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcast")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "UpdateVisibility")

	self.inCombat = InCombatLockdown() == true
	self:SyncWindows()
	self:LayoutAll()
	self:UpdateVisibility()
	if self.inCombat then
		self:StartTicker()
	end
	self.shown = true
end

function DamageMeter:OnDisable()
	self:StopTicker()
	for _, w in ipairs(self.windows) do
		w.frame:Hide()
	end
	Timer:Update()
	Menu:Hide()
	Tooltip:Hide()
	if self.shown then
		ns.addon:Print("DamageMeter: /reload restores Blizzard's damage meter")
		self.shown = false
	end
end

function DamageMeter:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:Migrate()
			self:SyncWindows()
			self:LayoutAll()
			self:UpdateVisibility()
			if self.ticker then
				self:StartTicker()
			end
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function DamageMeter:AcquireWindow(idx)
	local w = table.remove(self.parked)
	if w then
		w:Unpark(idx)
	else
		w = Window.New(self, idx)
	end
	self.windows[idx] = w
	return w
end

-- A profile switch can bring a different window count.
function DamageMeter:SyncWindows()
	local count = math.max(1, math.min(L.MAX_WINDOWS, self.db.profile.windowCount))
	if self.syncedProfile == self.db.profile and #self.windows == count then
		return
	end
	self.syncedProfile = self.db.profile
	while #self.windows > count do
		local w = table.remove(self.windows)
		w:Park()
		table.insert(self.parked, w)
	end
	for i = 1, #self.windows do
		ns.Mover:Unregister(self.windows[i].frame)
		self.windows[i]:Unpark(i)
	end
	for i = #self.windows + 1, count do
		self:AcquireWindow(i)
	end
end

function DamageMeter:LayoutAll()
	for _, w in ipairs(self.windows) do
		w:Layout()
	end
	for _, w in ipairs(self.windows) do
		w:LayoutButtons()
		w:Refresh()
	end
	Timer:Layout()
end

function DamageMeter:RefreshAll()
	for _, w in ipairs(self.windows) do
		w:Refresh()
	end
end

function DamageMeter:UpdateVisibility()
	if not self:IsEnabled() then
		return
	end
	local _, instType = IsInInstance()
	local inGroup = IsInGroup() == true
	for _, w in ipairs(self.windows) do
		w.frame:SetShown(w:ShouldShow(instType, self.inCombat, inGroup))
	end
	Timer:Layout()
	self:SendMessage("MERRINXUI_DM_TOGGLED", self.toggleHidden and self.db.profile.toggleIncludeSpellHistory)
end

function DamageMeter:ToggleWindows()
	if not self:IsEnabled() then
		return
	end
	self.toggleHidden = not self.toggleHidden
	ns.Debug:Log("DamageMeter", "toggle", self.toggleHidden)
	self:UpdateVisibility()
end

function DamageMeter:ResetData()
	C_DamageMeter.ResetAllCombatSessions()
	self.frozen = 0
	D.WipeTargets()
	ns.Debug:Log("DamageMeter", "reset")
	self:RefreshAll()
end

function DamageMeter:NewWindow(from)
	if #self.windows >= L.MAX_WINDOWS then
		return
	end
	local idx = #self.windows + 1
	local src = from.frame
	local width, height = src:GetWidth(), src:GetHeight()
	local highest, lowest = src:GetTop() or 0, src:GetBottom() or 0
	for _, w in ipairs(self.windows) do
		highest = math.max(highest, w.frame:GetTop() or highest)
		lowest = math.min(lowest, w.frame:GetBottom() or lowest)
	end
	local top = L.NewWindowTop(highest, lowest, height, GAP, UIParent:GetTop() or 0)
	local left = src:GetLeft() or 0
	local wdb = self:WindowDB(idx)
	wdb.width = math.floor(width + 0.5)
	wdb.height = math.floor(height + 0.5)
	local x, y = MoverLogic.CenterOffset(
		left + width / 2,
		top - height / 2,
		src:GetEffectiveScale(),
		UIParent:GetWidth(),
		UIParent:GetHeight(),
		UIParent:GetEffectiveScale()
	)
	wdb.position = { point = "CENTER", x = x, y = y }
	wdb.dock = nil
	self.db.profile.windowCount = idx
	local w = self:AcquireWindow(idx)
	w:Layout()
	for _, other in ipairs(self.windows) do
		other:LayoutButtons()
	end
	self:UpdateVisibility()
	w:ShowHome()
	ns.Debug:Log("DamageMeter", "window", "new", idx)
end

function DamageMeter:CloseWindow(w)
	local idx = w.idx
	if idx == 1 then
		return
	end
	w:Park()
	table.remove(self.windows, idx)
	table.remove(self.db.profile.windows, idx)
	for _, wdb in ipairs(self.db.profile.windows) do
		wdb.dock = L.RemapDock(wdb.dock, idx)
	end
	for i = idx, #self.windows do
		local other = self.windows[i]
		ns.Mover:Unregister(other.frame)
		other:Unpark(i)
	end
	table.insert(self.parked, w)
	self.db.profile.windowCount = #self.windows
	for _, other in ipairs(self.windows) do
		other:LayoutButtons()
	end
	ns.Debug:Log("DamageMeter", "window", "close", idx)
end

function DamageMeter:DockOf(idx)
	local dock = self:WindowDB(idx).dock
	if L.ValidDock(dock, idx, #self.windows) then
		return dock
	end
	return nil
end

function DamageMeter:DockedTo(w)
	local docks = {}
	for _, other in ipairs(self.windows) do
		local dock = self:DockOf(other.idx)
		docks[other.idx] = dock and dock.to
	end
	return L.Descendants(docks, w.idx)
end

-- rect is w's rect; during a drag or resize it is ahead of the saved position.
function DamageMeter:FollowDocks(w, rect, save, seen)
	seen = seen or { [w] = true }
	for _, other in ipairs(self.windows) do
		local dock = not seen[other] and self:DockOf(other.idx)
		if dock and dock.to == w.idx then
			seen[other] = true
			local width, height = other.frame:GetWidth(), other.frame:GetHeight()
			local left, top = L.DockedTopLeft(rect, width, height, dock.side, dock.offset)
			other:PlaceAt(left, top, save)
			local childRect = { left = left, right = left + width, top = top, bottom = top - height }
			self:FollowDocks(other, childRect, save, seen)
		end
	end
end

function DamageMeter:SelectSegment(w, session, sessionID)
	local targets = { w }
	if self:WindowDB(w.idx).syncSegments then
		targets = {}
		for _, other in ipairs(self.windows) do
			if self:WindowDB(other.idx).syncSegments then
				table.insert(targets, other)
			end
		end
	end
	for _, target in ipairs(targets) do
		target:SetSession(session, sessionID)
	end
end

function DamageMeter:CurrentDuration()
	if self.inCombat or self.needsFinal then
		local d = D.SessionDuration("Current")
		if d then
			self.frozen = d
			return d
		end
		return self.frozen
	end
	if self.frozen > 0 then
		return self.frozen
	end
	return D.SessionDuration("Current") or 0
end

-- In combat a death's time is secret: it is stamped with the live clock the
-- first time the Current view shows it.
function DamageMeter:DeathStamp(recapID, view)
	if recapID == nil or D.IsSecret(recapID) then
		return "0:00"
	end
	local stamp = self.stamps[recapID]
	if not stamp then
		if not (self.inCombat and not view.sessionID and view.session == "Current") then
			return "0:00"
		end
		stamp = self:CurrentDuration()
		if not stamp or stamp <= 0 then
			return "0:00"
		end
		self.stamps[recapID] = stamp
	end
	return L.FormatTimer(stamp)
end

local function groupUnits()
	local units = { "player" }
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			table.insert(units, "raid" .. i)
		end
	elseif IsInGroup() then
		for i = 1, GetNumGroupMembers() - 1 do
			table.insert(units, "party" .. i)
		end
	end
	return units
end

local function groupInCombat()
	for _, unit in ipairs(groupUnits()) do
		if UnitAffectingCombat(unit) then
			return true
		end
	end
	return false
end

-- A Feign Death leaves a death entry; it is hidden until the hunter is at 0 HP.
function DamageMeter:IsFeigned(guid)
	if guid == nil or D.IsSecret(guid) or not self.feign[guid] then
		return false
	end
	for _, unit in ipairs(groupUnits()) do
		local g = UnitGUID(unit)
		if not D.IsSecret(g) and g == guid then
			local hp = UnitHealth(unit)
			if not D.IsSecret(hp) and hp <= 0 then
				self.feign[guid] = nil
				return false
			end
			return true
		end
	end
	self.feign[guid] = nil
	return false
end

function DamageMeter:OnSpellcast(_, unit, _, spellID)
	if spellID == nil or D.IsSecret(spellID) or spellID ~= FEIGN_DEATH then
		return
	end
	local guid = UnitGUID(unit)
	if guid and not D.IsSecret(guid) then
		self.feign[guid] = true
	end
end

function DamageMeter:RefreshRate()
	local p = self.db.profile
	local floor = p.unsafeRefreshRate and REFRESH_HARD_FLOOR or REFRESH_FLOOR
	return math.max(floor, p.refreshRate)
end

function DamageMeter:StartTicker()
	self:StopTicker()
	self.ticker = C_Timer.NewTicker(self:RefreshRate(), function()
		self:Tick()
	end)
	local interval = (self.db.profile.standaloneTimer and self.db.profile.timerDecimal) and 0.1 or 0.5
	self.clock = C_Timer.NewTicker(interval, function()
		for _, w in ipairs(self.windows) do
			if not w.view.sessionID then
				w:UpdateTimer()
			end
		end
		Timer:Update()
	end)
end

function DamageMeter:StopTicker()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	if self.clock then
		self.clock:Cancel()
		self.clock = nil
	end
end

function DamageMeter:ReviveTicker()
	if (self.inCombat or self.needsFinal) and not self.ticker then
		self:StartTicker()
	end
end

function DamageMeter:Tick()
	self.ticks = self.ticks + 1
	if self.needsFinal then
		local done = not groupInCombat() or (self.regenAt and GetTime() - self.regenAt > 5)
		if done then
			self:FinishCombat()
			return
		end
	elseif not self.inCombat then
		self:StopTicker()
		return
	end
	self:RefreshAll()
end

function DamageMeter:FinishCombat()
	local d = D.SessionDuration("Current")
	if d and d >= self.frozen then
		self.frozen = d
	end
	self.inCombat = false
	self.needsFinal = false
	self:StopTicker()
	self:RefreshAll()
	self:UpdateVisibility()
	Timer:Update()
end

function DamageMeter:OnCombatStart()
	self.inCombat = true
	self.needsFinal = false
	self.frozen = 0
	self.regenAt = nil
	wipe(self.stamps)
	wipe(self.feign)
	D.WipeTargets()
	Menu:Hide()
	for _, w in ipairs(self.windows) do
		local wdb = self:WindowDB(w.idx)
		if w.view.sessionID and wdb.autoCurrentOnCombat then
			w:SetSession("Current", nil)
		end
	end
	self:StartTicker()
	self:UpdateVisibility()
	self:RefreshAll()
end

function DamageMeter:OnCombatEnd()
	self.regenAt = GetTime()
	D.WipeTargets()
	if groupInCombat() then
		self.needsFinal = true
		self:ReviveTicker()
	else
		self:FinishCombat()
	end
	C_Timer.After(0.5, function()
		if self:IsEnabled() and not InCombatLockdown() then
			D.Snapshot()
			self:RefreshAll()
		end
	end)
end

function DamageMeter:OnEncounterEnd(_, _, _, _, _, success)
	if not self.inCombat then
		return
	end
	C_Timer.After(0.5, function()
		if self.inCombat and (success == 1 or not groupInCombat()) and not InCombatLockdown() then
			self:FinishCombat()
		end
	end)
end

function DamageMeter:OnSessionUpdated()
	if self.inCombat or self.needsFinal then
		self:ReviveTicker()
		return
	end
	if self.sessionPending then
		return
	end
	self.sessionPending = true
	C_Timer.After(0.1, function()
		self.sessionPending = false
		D.WipeTargets()
		D.Snapshot()
		if self:IsEnabled() then
			self:RefreshAll()
		end
	end)
end

function DamageMeter:OnMeterReset()
	self.frozen = 0
	D.WipeTargets()
	for _, w in ipairs(self.windows) do
		if w.view.sessionID then
			w.view.sessionID = nil
			w:CloseSource()
		end
		w:Refresh()
	end
end

function DamageMeter:OnZone()
	self.inCombat = UnitAffectingCombat("player") == true
	if self.inCombat then
		self:StartTicker()
	elseif self.ticker and not self.needsFinal then
		self:FinishCombat()
	end
	C_Timer.After(0.5, function()
		if self:IsEnabled() then
			self:UpdateVisibility()
			self:RefreshAll()
		end
	end)
end

function DamageMeter:OnRoster()
	if not InCombatLockdown() then
		D.WipeSnapshot()
		D.Snapshot()
	end
	self:UpdateVisibility()
end

function DamageMeter:OnMediaChanged(_, mediatype, key)
	local p = self.db.profile
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", p.font)) then
		self:LayoutAll()
	elseif mediatype == "statusbar" and (key == nil or key == ns.Media:Resolve("statusbar", p.barTexture)) then
		self:LayoutAll()
	end
end

function DamageMeter:BindingToggle()
	self:ToggleWindows()
end

function DamageMeter:BindingReset()
	if self:IsEnabled() then
		self:ResetData()
	end
end

local function hexValid(_, value)
	if L.ParseHex(value) then
		return true
	end
	return "Enter a colour as RRGGBB"
end

function DamageMeter:GetOptions()
	local dm = self
	local function get(key)
		return function()
			return dm.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			dm.db.profile[key] = value
			dm:Refresh()
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
	local function color(key, name, order)
		return {
			type = "input",
			name = name,
			desc = "RRGGBB",
			order = order,
			validate = hexValid,
			get = get(key),
			set = function(_, value)
				local r, g, b = L.ParseHex(value)
				dm.db.profile[key] = L.ToHex(r, g, b)
				dm:Refresh()
			end,
		}
	end
	local function media(key, name, order, kind, extra)
		return {
			type = "select",
			name = name,
			order = order,
			dialogControl = kind == "font" and "LSM30_Font" or "LSM30_Statusbar",
			values = function()
				local values = ns.Media:Values(kind, dm.db.profile[key])
				if extra then
					for k, v in pairs(extra) do
						values[k] = v
					end
				end
				return values
			end,
			get = get(key),
			set = set(key),
		}
	end
	local function group(name, order, args)
		return { type = "group", name = name, order = order, inline = true, args = args }
	end
	local colorModes = { custom = "Custom", class = "Class" }

	return {
		type = "group",
		name = "DamageMeter",
		args = {
			enabled = toggle("enabled", "Enabled", 1),
			display = group("Display", 10, {
				refreshRate = {
					type = "range",
					name = "Refresh Rate",
					desc = "Seconds between updates in combat. Increase to improve performance.",
					order = 1,
					min = REFRESH_HARD_FLOOR,
					max = 3,
					step = 0.1,
					get = get("refreshRate"),
					set = function(_, value)
						local p = dm.db.profile
						p.refreshRate = p.unsafeRefreshRate and value or math.max(REFRESH_FLOOR, value)
						dm:Refresh()
					end,
				},
				unsafeRefreshRate = toggle(
					"unsafeRefreshRate",
					"Unsafe Refresh Rate",
					2,
					"Allows rates faster than 0.5s. The meters work much harder in combat."
				),
				visibility = choice("visibility", "Visibility", 3, {
					always = "Always",
					combat = "In Combat",
					group = "In Group",
				}),
				showPinnedSelf = toggle(
					"showPinnedSelf",
					"Always Show Player",
					4,
					"Pins your bar to the window when it is not in the visible area"
				),
				showPlayerMarker = toggle(
					"showPlayerMarker",
					"Show Player Marker",
					5,
					"A white stripe on your own bar"
				),
				hideResetButton = toggle("hideResetButton", "Hide Reset Button", 6),
				bgColor = color("bgColor", "Background Color", 7),
				bgOpacity = range("bgOpacity", "Background Opacity", 8, 0, 100, 5),
				windowBorderSize = range("windowBorderSize", "Window Border Size", 9, 0, 4, 1),
				windowBorderColor = color("windowBorderColor", "Window Border Color", 10),
			}),
			header = group("Header", 20, {
				hdrHeight = range("hdrHeight", "Header Height", 1, 14, 40, 1),
				hdrOpacity = range("hdrOpacity", "Opacity", 2, 0, 100, 5),
				hdrColor = color("hdrColor", "Header Color", 3),
				hdrBottomBorder = range("hdrBottomBorder", "Header Bottom Border", 4, 0, 4, 1),
				hdrBottomBorderColor = color("hdrBottomBorderColor", "Bottom Border Color", 5),
				hdrIconSize = range("hdrIconSize", "Icon Size", 6, 10, 32, 1),
				iconColorUseAccent = toggle("iconColorUseAccent", "Accent Icons", 7),
				hdrMouseoverIcons = toggle("hdrMouseoverIcons", "Mouseover Icons", 8),
				hdrFontSize = range("hdrFontSize", "Text Size", 9, 8, 20, 1),
				hdrTextUseAccent = toggle("hdrTextUseAccent", "Accent Title", 10),
				hdrTextColor = color("hdrTextColor", "Title Color", 11),
				hdrTextOffsetX = range("hdrTextOffsetX", "Title X Offset", 12, -20, 20, 1),
				hdrTextOffsetY = range("hdrTextOffsetY", "Title Y Offset", 13, -20, 20, 1),
			}),
			bars = group("Bars", 30, {
				font = media("font", "Font", 1, "font"),
				barTexture = media("barTexture", "Bar Texture", 2, "statusbar"),
				barHeight = range("barHeight", "Bar Height", 3, 8, 40, 1),
				barSpacing = range("barSpacing", "Spacing", 4, 0, 10, 1),
				barColorMode = choice("barColorMode", "Color", 5, {
					class = "Class Color",
					accent = "Accent Color",
					custom = "Custom Color",
				}),
				barColor = color("barColor", "Custom Color", 6),
				barOpacity = range("barOpacity", "Opacity", 7, 0, 100, 5),
				iconStyle = choice("iconStyle", "Icon Style", 8, {
					none = "None",
					spec = "Spec Icons",
					class = "Class Icons",
				}),
				iconZoom = range("iconZoom", "Icon Zoom", 9, 0, 20, 1),
				barBgOpacity = range("barBgOpacity", "Bar Background", 10, 0, 100, 5),
				barBgColor = color("barBgColor", "Bar Background Color", 11),
				barBgUseClassColor = toggle("barBgUseClassColor", "Class Colored Background", 12),
				barBorderSize = range("barBorderSize", "Bar Border Size", 13, 0, 4, 1),
				barBorderColor = color("barBorderColor", "Bar Border Color", 14),
			}),
			barText = group("Bar Text", 40, {
				numberFormat = choice("numberFormat", "Number Format", 1, L.NUMBER_FORMATS),
				hideNumbers = toggle("hideNumbers", "Hide Rank Numbers", 2),
				leftFontSize = range("leftFontSize", "Left Text Size", 3, 8, 18, 1),
				rightFontSize = range("rightFontSize", "Right Text Size", 4, 8, 18, 1),
				leftTextColorMode = choice("leftTextColorMode", "Left Text Color", 5, colorModes),
				leftTextColor = color("leftTextColor", "Left Custom Color", 6),
				rightTextColorMode = choice("rightTextColorMode", "Right Text Color", 7, {
					custom = "Custom",
					class = "Class",
					gradient = "Green to Red",
				}),
				rightTextColor = color("rightTextColor", "Right Custom Color", 8),
				leftTextOffsetX = range("leftTextOffsetX", "Left X Offset", 9, -20, 20, 1),
				leftTextOffsetY = range("leftTextOffsetY", "Left Y Offset", 10, -20, 20, 1),
				rightTextOffsetX = range("rightTextOffsetX", "Right X Offset", 11, -20, 20, 1),
				rightTextOffsetY = range("rightTextOffsetY", "Right Y Offset", 12, -20, 20, 1),
			}),
			breakdown = group("Breakdown", 50, {
				showHoverTooltip = toggle("showHoverTooltip", "Show Breakdown on Hover", 1),
				breakdownBgOpacity = range("breakdownBgOpacity", "Background", 2, 0, 100, 5),
				breakdownTexture = media(
					"breakdownTexture",
					"Bar Texture",
					3,
					"statusbar",
					{ match = "Match Damage Meter" }
				),
				hoverScale = range("hoverScale", "Scale", 4, 80, 150, 1),
				breakdownAnchor = choice("breakdownAnchor", "Anchor", 5, {
					row = "Above Hovered Row",
					center = "Center of Screen",
					left = "Left of Window",
					right = "Right of Window",
				}),
				moreSpells = toggle("moreSpells", "Show More Spells", 6, "Show top 15 entries instead of 8"),
				showSpellTooltips = toggle(
					"showSpellTooltips",
					"Show Spell Tooltips on Hover",
					7,
					"The game's spell tooltip when you hover a spell in a breakdown window"
				),
			}),
			timer = group("Standalone Combat Timer", 60, {
				standaloneTimer = toggle("standaloneTimer", "Standalone Combat Timer", 1),
				timerColorMode = choice("timerColorMode", "Timer Text Color", 2, {
					custom = "Custom",
					accent = "Accent",
				}),
				timerColor = color("timerColor", "Custom Color", 3),
				timerSize = range("timerSize", "Font Size", 4, 10, 40, 1),
				timerAlign = choice(
					"timerAlign",
					"Alignment",
					5,
					{ LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
				),
				timerDecimal = toggle("timerDecimal", "Show Decimal", 6),
				timerWidth = range("timerWidth", "Frame Width", 7, 40, 200, 1),
				timerHeight = range("timerHeight", "Frame Height", 8, 20, 80, 1),
				timerBgColor = color("timerBgColor", "Background Color", 9),
				timerBgOpacity = range("timerBgOpacity", "Background Opacity", 10, 0, 100, 5),
				timerBorderColor = color("timerBorderColor", "Border Color", 11),
				timerBorderSize = range("timerBorderSize", "Border Size", 12, 0, 4, 1),
				timerStrata = choice("timerStrata", "Frame Strata", 13, {
					BACKGROUND = "Background",
					LOW = "Low",
					MEDIUM = "Medium",
					HIGH = "High",
					DIALOG = "Dialog",
				}),
				timerShowOOC = toggle(
					"timerShowOOC",
					"Show Out of Combat",
					14,
					"Keep the timer visible out of combat, showing the last fight's duration"
				),
				timerDesatOOC = toggle("timerDesatOOC", "Desaturate Out of Combat", 15),
				timerAnchor = choice("timerAnchor", "Anchor to Windows", 16, {
					free = "Free Move",
					topleft = "Top Left",
					topright = "Top Right",
					bottomleft = "Bottom Left",
					bottomright = "Bottom Right",
				}),
				timerLocked = toggle(
					"timerLocked",
					"Lock Position & Disable Click",
					17,
					"Click-through; Shift+drag moves the timer while unlocked"
				),
			}),
			extras = group("Extras", 70, {
				keybinds = {
					type = "description",
					name = "Show/Hide Windows and Reset Data keybinds are in Key Bindings > AddOns > MerrinxUI.",
					order = 1,
				},
				toggleIncludeTimer = toggle("toggleIncludeTimer", "Toggle Includes Combat Timer", 2),
				toggleIncludeSpellHistory = toggle("toggleIncludeSpellHistory", "Toggle Includes Spell History", 3),
				reset = {
					type = "execute",
					name = "Reset Data",
					order = 4,
					confirm = true,
					func = function()
						if dm:IsEnabled() then
							dm:ResetData()
						end
					end,
				},
			}),
		},
	}
end

function DamageMeter:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local cdm = type(C_DamageMeter) == "table" and C_DamageMeter or {}
				local fns = {
					"GetCombatSessionFromType",
					"GetAvailableCombatSessions",
					"GetCombatSessionFromID",
					"ResetAllCombatSessions",
					"IsDamageMeterAvailable",
				}
				for _, name in ipairs(fns) do
					if type(cdm[name]) ~= "function" then
						table.insert(missing, "C_DamageMeter." .. name)
					end
				end
				if type(Enum.DamageMeterSessionType) ~= "table" then
					table.insert(missing, "Enum.DamageMeterSessionType")
				end
				if type(Enum.DamageMeterType) ~= "table" then
					table.insert(missing, "Enum.DamageMeterType")
				end
				for name, v in pairs({
					AbbreviateLargeNumbers = AbbreviateLargeNumbers,
					CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS,
					RAID_CLASS_COLORS = RAID_CLASS_COLORS,
				}) do
					if v == nil then
						table.insert(missing, name)
					end
				end
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "types",
			run = function()
				if #self.types == 0 then
					return "FAIL", "no types"
				end
				return "PASS", #self.types, table.concat(self.types, " ")
			end,
		},
		{
			name = "windows",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local count = self.db.profile.windowCount
				local ok = #self.windows == count and count >= 1 and count <= L.MAX_WINDOWS
				return ok and "PASS" or "FAIL", #self.windows, count, #self.parked
			end,
		},
		{
			name = "combat state",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local ticking = self.ticker ~= nil
				local bad = ticking and not (self.inCombat or self.needsFinal)
				return bad and "FAIL" or "INFO", self.inCombat, self.needsFinal, ticking, self.ticks, self:RefreshRate()
			end,
		},
		{
			name = "duration",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return "INFO", L.FormatTimer(self:CurrentDuration()), self.frozen
			end,
		},
		{
			name = "segments",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local raw = C_DamageMeter.GetAvailableCombatSessions() or {}
				local readable = L.Segments(D.Segments(), L.MAX_SEGMENTS)
				return "INFO", #raw, #readable
			end,
		},
		{
			name = "bookmarks",
			run = function()
				local list = self:Bookmarks()
				return "INFO", #list, table.concat(list, " ")
			end,
		},
		{
			name = "visibility",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local _, instType = IsInInstance()
				local inGroup = IsInGroup() == true
				for _, w in ipairs(self.windows) do
					if w.frame:IsShown() ~= w:ShouldShow(instType, self.inCombat, inGroup) then
						return "FAIL", w.idx, instType, self.toggleHidden
					end
				end
				return "PASS", instType, self.toggleHidden == true
			end,
		},
		{
			name = "blizzard meter",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local hb = ns.addon:GetModule("HideBlizzard")
				local cvar = C_CVar.GetCVar("damageMeterEnabled")
				if issecretvalue(cvar) then
					return "INFO", "secret"
				end
				local ok = hb.forced.damageMeter == true and cvar == "0"
				return ok and "PASS" or "FAIL", hb.forced.damageMeter, cvar
			end,
		},
		{
			name = "available",
			run = function()
				if type(C_DamageMeter) ~= "table" or type(C_DamageMeter.IsDamageMeterAvailable) ~= "function" then
					return "INFO", "missing api"
				end
				return "INFO", C_DamageMeter.IsDamageMeterAvailable()
			end,
		},
		{
			name = "font",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local w = self.windows[1]
				if not w then
					return "SKIP", "no window"
				end
				local path, size = w.title:GetFont()
				local expected = ns.Media:FontPath(self.db.profile.font)
				local ok = type(path) == "string"
					and path:lower():gsub("/", "\\") == expected:lower():gsub("/", "\\")
					and math.floor(size + 0.5) == self.db.profile.hdrFontSize
				return ok and "PASS" or "FAIL", path, size, ns.Media:Resolve("font", self.db.profile.font)
			end,
		},
		{
			name = "bindings",
			run = function()
				return "INFO",
					GetBindingKey("MERRINXUI_DM_TOGGLE") or "unbound",
					GetBindingKey("MERRINXUI_DM_RESET") or "unbound"
			end,
		},
	}
end
