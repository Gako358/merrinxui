local addonName, ns = ...

local L = ns.DamageMeterLogic

local FONT = "Fonts\\ARIALN.TTF"
local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local Accent = ns.Theme.color.accent

local DamageMeter = ns.addon:NewModule("DamageMeter", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = false,
		session = "Current",
		metric = "DamageDone",
		rows = 8,
		width = 220,
		rowHeight = 18,
		fontSize = 11,
		position = { point = "CENTER", x = 400, y = -200 },
	},
}

local HEADER_HEIGHT = 22
local ROW_SPACING = 2

local function sessionLabel(session)
	if session == "Current" then
		return "C"
	end
	return "O"
end

local function metricLabel(metric)
	if metric == "DamageDone" then
		return "D"
	end
	return "H"
end

function DamageMeter:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("DamageMeter", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.rows = {}

	local frame = CreateFrame("Frame", "MerrinxUIDamageMeter", UIParent)
	frame:Hide()
	self.frame = frame

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(TEXTURE)
	bg:SetVertexColor(0, 0, 0, 1)
	bg:SetAlpha(0.75)

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT")
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT")

	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	headerBg:SetTexture(TEXTURE)
	headerBg:SetVertexColor(27 / 255, 27 / 255, 27 / 255, 1)

	local title = header:CreateFontString(nil, "OVERLAY")
	title:SetFont(FONT, 11, "")
	title:SetTextColor(Accent[1], Accent[2], Accent[3], Accent[4])
	title:SetPoint("LEFT", header, "LEFT", 4, 0)
	self.title = title

	local function makeButton(text)
		local button = CreateFrame("Button", nil, header)
		button:SetSize(HEADER_HEIGHT, HEADER_HEIGHT)
		local fs = button:CreateFontString(nil, "OVERLAY")
		fs:SetFont(FONT, 11, "")
		fs:SetAllPoints()
		fs:SetJustifyH("CENTER")
		fs:SetTextColor(1, 1, 1, 1)
		fs:SetText(text)
		button.text = fs
		button:SetScript("OnEnter", function()
			fs:SetTextColor(Accent[1], Accent[2], Accent[3], Accent[4])
		end)
		button:SetScript("OnLeave", function()
			fs:SetTextColor(1, 1, 1, 1)
		end)
		return button
	end

	local resetButton = makeButton("R")
	resetButton:SetPoint("RIGHT", header, "RIGHT", -2, 0)
	resetButton:SetScript("OnClick", function()
		C_DamageMeter.ResetAllCombatSessions()
		ns.Debug:Log("DamageMeter", "reset")
		self:Redraw()
	end)

	local metricButton = makeButton(metricLabel(self.db.profile.metric))
	metricButton:SetPoint("RIGHT", resetButton, "LEFT", 0, 0)
	metricButton:SetScript("OnClick", function()
		local profile = self.db.profile
		profile.metric = L.Toggle(profile.metric, "DamageDone", "HealingDone")
		ns.Debug:Log("DamageMeter", "metric", profile.metric)
		self:Redraw()
	end)
	self.metricButton = metricButton

	local sessionButton = makeButton(sessionLabel(self.db.profile.session))
	sessionButton:SetPoint("RIGHT", metricButton, "LEFT", 0, 0)
	sessionButton:SetScript("OnClick", function()
		local profile = self.db.profile
		profile.session = L.Toggle(profile.session, "Current", "Overall")
		ns.Debug:Log("DamageMeter", "session", profile.session)
		self:Redraw()
	end)
	self.sessionButton = sessionButton

	ns.Mover:Register(frame, "Damage Meter", function()
		return self.db.profile.position
	end)
end

function DamageMeter:OnEnable()
	ns.Combat:Run("DamageMeter:Ensure", function()
		ns.addon:GetModule("HideBlizzard"):Ensure("damageMeter")
	end)

	self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", "RequestRedraw")
	self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", "RequestRedraw")
	self:RegisterEvent("DAMAGE_METER_RESET", "RequestRedraw")

	self:Layout()
	ns.Mover:Apply(self.frame)
	self.frame:Show()
	self.shown = true
	self:Redraw()
end

function DamageMeter:OnDisable()
	self.frame:Hide()
	if self.shown then
		ns.addon:Print("DamageMeter: /reload restores Blizzard's damage meter")
		self.shown = false
	end
end

function DamageMeter:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:Layout()
			ns.Mover:Apply(self.frame)
			self:Redraw()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function DamageMeter:RequestRedraw()
	if self.redrawPending then
		return
	end
	self.redrawPending = true
	C_Timer.After(1, function()
		self.redrawPending = false
		if self:IsEnabled() then
			self:Redraw()
		end
	end)
end

function DamageMeter:GetRow(i)
	local row = self.rows[i]
	if row then
		return row
	end

	row = CreateFrame("Frame", nil, self.frame)

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon = icon

	local bar = CreateFrame("StatusBar", nil, row)
	bar:SetStatusBarTexture(TEXTURE)
	bar:GetStatusBarTexture():SetAlpha(1)
	bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 2, 0)
	bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	row.bar = bar

	local left = bar:CreateFontString(nil, "OVERLAY")
	left:SetPoint("LEFT", bar, "LEFT", 4, 0)
	left:SetShadowOffset(1, -1)
	row.left = left

	local right = bar:CreateFontString(nil, "OVERLAY")
	right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	right:SetShadowOffset(1, -1)
	row.right = right

	self.rows[i] = row
	return row
end

function DamageMeter:Layout()
	local profile = self.db.profile
	local frame = self.frame

	frame:SetSize(profile.width, L.WindowHeight(profile.rows, profile.rowHeight, ROW_SPACING, HEADER_HEIGHT))

	for i = 1, profile.rows do
		local row = self:GetRow(i)
		row:SetSize(profile.width, profile.rowHeight)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(HEADER_HEIGHT + (i - 1) * (profile.rowHeight + ROW_SPACING)))

		row.icon:SetSize(profile.rowHeight, profile.rowHeight)
		row.left:SetFont(FONT, profile.fontSize, "")
		row.left:SetTextColor(1, 1, 1, 1)
		row.right:SetFont(FONT, profile.fontSize, "")
		row.right:SetTextColor(1, 1, 1, 1)

		row:Show()
	end

	for i = profile.rows + 1, #self.rows do
		self.rows[i]:Hide()
	end
end

function DamageMeter:Redraw()
	if not self:IsEnabled() then
		return
	end

	local profile = self.db.profile
	local sessionKey = L.EnumKey(Enum.DamageMeterSessionType, profile.session)
	local metricKey = L.EnumKey(Enum.DamageMeterType, profile.metric)

	local src
	if sessionKey ~= nil and metricKey ~= nil then
		local session = C_DamageMeter.GetCombatSessionFromType(sessionKey, metricKey)
		src = session and session.combatSources or {}
	else
		src = {}
	end

	self.lastCount = #src
	local n = L.VisibleRows(#src, profile.rows)

	self.title:SetText(L.Title(profile.session, profile.metric))
	self.metricButton.text:SetText(metricLabel(profile.metric))
	self.sessionButton.text:SetText(sessionLabel(profile.session))

	for i = 1, n do
		local s = src[i]
		local row = self:GetRow(i)
		row:Show()

		row.bar:SetMinMaxValues(0, src[1].totalAmount)
		row.bar:SetValue(s.totalAmount)

		row.right:SetText(
			string.format("%s (%s)", AbbreviateNumbers(s.totalAmount), AbbreviateNumbers(s.amountPerSecond))
		)
		if issecretvalue(s.name) then
			row.left:SetText(s.name)
		else
			row.left:SetText(L.ShortName(s.name))
		end

		local c = s.classFilename
		local secretClass = issecretvalue(c)
		local classColor = (not secretClass) and RAID_CLASS_COLORS[c]
		if classColor then
			row.bar:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
		else
			row.bar:SetStatusBarColor(Accent[1], Accent[2], Accent[3])
		end

		local coords = (not secretClass) and CLASS_ICON_TCOORDS[c]
		if coords then
			row.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
			row.icon:SetTexCoord(L.IconCoords(coords, 0.06))
			row.icon:Show()
		else
			row.icon:Hide()
		end
	end

	for i = n + 1, #self.rows do
		self.rows[i]:Hide()
	end

	self.redraws = (self.redraws or 0) + 1
end

function DamageMeter:GetOptions()
	return {
		type = "group",
		name = "DamageMeter",
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
			session = {
				type = "select",
				name = "Session",
				order = 2,
				values = {
					Current = "Current",
					Overall = "Overall",
				},
				get = function()
					return self.db.profile.session
				end,
				set = function(_, value)
					self.db.profile.session = value
					self:Refresh()
				end,
			},
			metric = {
				type = "select",
				name = "Metric",
				order = 3,
				values = {
					DamageDone = "Damage Done",
					HealingDone = "Healing Done",
				},
				get = function()
					return self.db.profile.metric
				end,
				set = function(_, value)
					self.db.profile.metric = value
					self:Refresh()
				end,
			},
			rows = {
				type = "range",
				name = "Rows",
				order = 4,
				min = 1,
				max = 40,
				step = 1,
				get = function()
					return self.db.profile.rows
				end,
				set = function(_, value)
					self.db.profile.rows = value
					self:Refresh()
				end,
			},
			width = {
				type = "range",
				name = "Width",
				order = 5,
				min = 120,
				max = 600,
				step = 1,
				get = function()
					return self.db.profile.width
				end,
				set = function(_, value)
					self.db.profile.width = value
					self:Refresh()
				end,
			},
			rowHeight = {
				type = "range",
				name = "Row height",
				order = 6,
				min = 12,
				max = 40,
				step = 1,
				get = function()
					return self.db.profile.rowHeight
				end,
				set = function(_, value)
					self.db.profile.rowHeight = value
					self:Refresh()
				end,
			},
			fontSize = {
				type = "range",
				name = "Font size",
				order = 7,
				min = 8,
				max = 24,
				step = 1,
				get = function()
					return self.db.profile.fontSize
				end,
				set = function(_, value)
					self.db.profile.fontSize = value
					self:Refresh()
				end,
			},
			reset = {
				type = "execute",
				name = "Reset",
				order = 8,
				confirm = true,
				func = function()
					C_DamageMeter.ResetAllCombatSessions()
					ns.Debug:Log("DamageMeter", "reset")
					self:Redraw()
				end,
			},
		},
	}
end

function DamageMeter:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function checkFn(name, fn)
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end
				local function checkTbl(name, tbl)
					if type(tbl) ~= "table" then
						table.insert(missing, name)
					end
				end

				local cdm = type(C_DamageMeter) == "table" and C_DamageMeter or {}
				checkFn("C_DamageMeter.GetCombatSessionFromType", cdm.GetCombatSessionFromType)
				checkFn("C_DamageMeter.ResetAllCombatSessions", cdm.ResetAllCombatSessions)
				checkFn("C_DamageMeter.IsDamageMeterAvailable", cdm.IsDamageMeterAvailable)
				checkTbl("Enum.DamageMeterSessionType", type(Enum) == "table" and Enum.DamageMeterSessionType)
				checkTbl("Enum.DamageMeterType", type(Enum) == "table" and Enum.DamageMeterType)
				checkFn("AbbreviateNumbers", AbbreviateNumbers)
				checkTbl("CLASS_ICON_TCOORDS", CLASS_ICON_TCOORDS)
				checkTbl("RAID_CLASS_COLORS", RAID_CLASS_COLORS)

				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "available",
			run = function()
				if type(C_DamageMeter) ~= "table" or type(C_DamageMeter.IsDamageMeterAvailable) ~= "function" then
					return "INFO", "missing api"
				end
				local available, reason = C_DamageMeter.IsDamageMeterAvailable()
				return "INFO", available, reason
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
			name = "window",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local profile = self.db.profile
				local w, h = self.frame:GetWidth(), self.frame:GetHeight()
				local expectedH = L.WindowHeight(profile.rows, profile.rowHeight, ROW_SPACING, HEADER_HEIGHT)
				local ok = self.frame:IsShown()
					and math.abs(w - profile.width) <= 0.5
					and math.abs(h - expectedH) <= 0.5
				return ok and "PASS" or "FAIL", w, h
			end,
		},
		{
			name = "title",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local text = self.title:GetText()
				if issecretvalue(text) then
					return "INFO", "secret"
				end

				local expected = L.Title(self.db.profile.session, self.db.profile.metric)
				return (text == expected) and "PASS" or "FAIL", text, expected
			end,
		},
		{
			name = "session",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local profile = self.db.profile
				local sessionKey = L.EnumKey(Enum.DamageMeterSessionType, profile.session)
				local metricKey = L.EnumKey(Enum.DamageMeterType, profile.metric)
				if sessionKey == nil or metricKey == nil then
					return "INFO", profile.session, profile.metric, sessionKey, metricKey, 0
				end

				local session = C_DamageMeter.GetCombatSessionFromType(sessionKey, metricKey)
				local src = session and session.combatSources or {}
				local count = #src
				if count == 0 then
					return "SKIP", "no data"
				end

				local s = src[1]
				return "INFO",
					profile.session,
					profile.metric,
					sessionKey,
					metricKey,
					count,
					issecretvalue(s.totalAmount),
					issecretvalue(s.name),
					issecretvalue(s.classFilename)
			end,
		},
		{
			name = "rows",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local shown = 0
				for _, row in ipairs(self.rows) do
					if row:IsShown() then
						shown = shown + 1
					end
				end

				local expected = L.VisibleRows(self.lastCount or 0, self.db.profile.rows)
				return (shown == expected) and "PASS" or "FAIL", shown, expected
			end,
		},
		{
			name = "sorted",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local profile = self.db.profile
				local sessionKey = L.EnumKey(Enum.DamageMeterSessionType, profile.session)
				local metricKey = L.EnumKey(Enum.DamageMeterType, profile.metric)
				if sessionKey == nil or metricKey == nil then
					return "SKIP", "no data"
				end

				local session = C_DamageMeter.GetCombatSessionFromType(sessionKey, metricKey)
				local src = session and session.combatSources or {}
				local n = L.VisibleRows(#src, profile.rows)
				if n < 2 then
					return "SKIP", "too few sources"
				end

				for i = 1, n do
					if issecretvalue(src[i].totalAmount) then
						return "INFO", "secret"
					end
				end

				for i = 2, n do
					if src[i].totalAmount > src[i - 1].totalAmount then
						return "FAIL", i
					end
				end
				return "PASS"
			end,
		},
		{
			name = "font",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local path, size = self.title:GetFont()
				local ok = type(path) == "string"
					and path:lower() == "fonts\\arialn.ttf"
					and math.floor(size + 0.5) == 11

				local row = self.rows[1]
				if ok and row then
					local _, rowSize = row.left:GetFont()
					ok = math.floor(rowSize + 0.5) == self.db.profile.fontSize
				end

				return ok and "PASS" or "FAIL", path, size
			end,
		},
		{
			name = "redraw",
			run = function()
				return "INFO", self.redraws, self.redrawPending
			end,
		},
	}
end
