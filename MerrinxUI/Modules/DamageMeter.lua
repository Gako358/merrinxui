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
		font = "Arial Narrow",
		barTexture = "Solid",
		position = { point = "CENTER", x = 400, y = -200 },
	},
}

local HEADER_HEIGHT = 22
local ROW_SPACING = 2

local function sessionIndicator(hasSegment, session)
	if hasSegment then
		return "S"
	end
	if session == "Current" then
		return "C"
	end
	return "O"
end

local function segmentExpired(segmentID)
	local readable = false
	for _, entry in ipairs(C_DamageMeter.GetAvailableCombatSessions() or {}) do
		if not issecretvalue(entry.sessionID) then
			if entry.sessionID == segmentID then
				return false
			end
			readable = true
		end
	end
	return readable
end

function DamageMeter:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("DamageMeter", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.rows = {}
	self.types = L.TypeList(Enum.DamageMeterType)

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
	self.resetButton = resetButton

	local typeButton = makeButton("T")
	typeButton:SetPoint("RIGHT", resetButton, "LEFT", 0, 0)
	typeButton:SetScript("OnClick", function()
		self:OpenTypeMenu(typeButton)
	end)
	self.typeButton = typeButton

	local sessionButton = makeButton("C")
	sessionButton:SetPoint("RIGHT", typeButton, "LEFT", 0, 0)
	sessionButton:SetScript("OnClick", function()
		self:OpenSessionMenu(sessionButton)
	end)
	self.sessionButton = sessionButton

	title:SetPoint("LEFT", header, "LEFT", 4, 0)
	title:SetPoint("RIGHT", sessionButton, "LEFT", -2, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)

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
	self:RegisterEvent("DAMAGE_METER_RESET", "OnMeterReset")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")

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

function DamageMeter:OnMediaChanged(_, mediatype, key)
	local profile = self.db.profile
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", profile.font)) then
		self:Layout()
		self:Redraw()
	elseif mediatype == "statusbar" and (key == nil or key == ns.Media:Resolve("statusbar", profile.barTexture)) then
		self:Layout()
		self:Redraw()
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

function DamageMeter:OnMeterReset()
	if self.segmentID then
		self.segmentID = nil
		self.segmentLabel = nil
		ns.Debug:Log("DamageMeter", "segment", "none")
	end
	self:RequestRedraw()
end

function DamageMeter:CurrentType()
	return L.ResolveType(self.types, self.db.profile.metric, "DamageDone")
end

function DamageMeter:SessionLabel()
	return self.segmentLabel or self.db.profile.session
end

function DamageMeter:ReadSession(typeKey)
	local value = Enum.DamageMeterType[typeKey]
	if value == nil then
		return nil
	end

	if self.segmentID then
		return C_DamageMeter.GetCombatSessionFromID(self.segmentID, value)
	end

	local sessionKey = L.EnumKey(Enum.DamageMeterSessionType, self.db.profile.session)
	if sessionKey == nil then
		return nil
	end
	return C_DamageMeter.GetCombatSessionFromType(sessionKey, value)
end

function DamageMeter:SelectType(key)
	self.db.profile.metric = key
	ns.Debug:Log("DamageMeter", "type", key)
	self:Refresh()
end

function DamageMeter:SelectSession(s)
	self.segmentID = nil
	self.segmentLabel = nil
	self.db.profile.session = s
	ns.Debug:Log("DamageMeter", "session", s)
	self:Refresh()
end

function DamageMeter:SelectSegment(id, label)
	self.segmentID = id
	self.segmentLabel = label
	ns.Debug:Log("DamageMeter", "segment", id)
	self:Refresh()
end

function DamageMeter:OpenTypeMenu(button)
	MenuUtil.CreateContextMenu(button, function(_, root)
		for _, group in ipairs(L.MenuGroups(self.types)) do
			local sub = root:CreateButton(group.label)
			for _, key in ipairs(group.keys) do
				sub:CreateRadio(L.TypeLabel(key), function()
					return self:CurrentType() == key
				end, function()
					self:SelectType(key)
				end)
			end
		end
	end)
end

function DamageMeter:OpenSessionMenu(button)
	local raw = C_DamageMeter.GetAvailableCombatSessions() or {}
	local mapped = {}
	for _, entry in ipairs(raw) do
		local sessionID
		if issecretvalue(entry.sessionID) then
			sessionID = nil
		else
			sessionID = entry.sessionID
		end

		local name
		if issecretvalue(entry.name) then
			name = nil
		else
			name = entry.name
		end

		local durationSeconds
		if issecretvalue(entry.durationSeconds) then
			durationSeconds = nil
		else
			durationSeconds = entry.durationSeconds
		end

		table.insert(mapped, { sessionID = sessionID, name = name, durationSeconds = durationSeconds })
	end

	local segments = L.Segments(mapped, 20)

	MenuUtil.CreateContextMenu(button, function(_, root)
		for _, segment in ipairs(segments) do
			root:CreateRadio(segment.label, function()
				return self.segmentID == segment.sessionID
			end, function()
				self:SelectSegment(segment.sessionID, segment.label)
			end)
		end

		if #segments > 0 then
			root:CreateDivider()
		end

		root:CreateRadio("Current", function()
			return self.segmentID == nil and self.db.profile.session == "Current"
		end, function()
			self:SelectSession("Current")
		end)
		root:CreateRadio("Overall", function()
			return self.segmentID == nil and self.db.profile.session == "Overall"
		end, function()
			self:SelectSession("Overall")
		end)
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

	ns.Media:SetFont(self.title, profile.font, 11, "")
	ns.Media:SetFont(self.resetButton.text, profile.font, 11, "")
	ns.Media:SetFont(self.typeButton.text, profile.font, 11, "")
	ns.Media:SetFont(self.sessionButton.text, profile.font, 11, "")

	for i = 1, profile.rows do
		local row = self:GetRow(i)
		row:SetSize(profile.width, profile.rowHeight)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(HEADER_HEIGHT + (i - 1) * (profile.rowHeight + ROW_SPACING)))

		row.icon:SetSize(profile.rowHeight, profile.rowHeight)
		ns.Media:SetFont(row.left, profile.font, profile.fontSize, "")
		row.left:SetTextColor(1, 1, 1, 1)
		ns.Media:SetFont(row.right, profile.font, profile.fontSize, "")
		row.right:SetTextColor(1, 1, 1, 1)

		-- SetStatusBarTexture replaces the bar's texture object and resets its alpha, so
		-- only touch it when the resolved path actually changes, and restore alpha after
		local barPath = ns.Media:Fetch("statusbar", profile.barTexture) or TEXTURE
		if barPath ~= row.barPath then
			row.barPath = ns.Media:SetStatusBarTexture(row.bar, profile.barTexture)
			row.bar:GetStatusBarTexture():SetAlpha(1)
		end

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
	local t = self:CurrentType()
	local session
	if not (self.segmentID and segmentExpired(self.segmentID)) then
		session = self:ReadSession(t)
	end

	if self.segmentID and session == nil then
		self.segmentID = nil
		self.segmentLabel = nil
		ns.Debug:Log("DamageMeter", "segment", "none")
		session = self:ReadSession(t)
	end

	local src = session and session.combatSources or {}
	local kind = L.TypeKind(t)
	local field = L.BarField(kind)

	self.lastCount = #src
	local n = L.VisibleRows(#src, profile.rows)

	self.title:SetText(L.Title(self:SessionLabel(), t))
	self.sessionButton.text:SetText(sessionIndicator(self.segmentID ~= nil, profile.session))

	for i = 1, n do
		local s = src[i]
		local row = self:GetRow(i)
		row:Show()

		row.bar:SetMinMaxValues(0, src[1][field])
		row.bar:SetValue(s[field])

		row.right:SetText(L.ValueText(kind, s.totalAmount, s.amountPerSecond, AbbreviateNumbers))
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
					self:SelectSession(value)
				end,
			},
			metric = {
				type = "select",
				name = "Meter type",
				order = 3,
				values = function()
					local values = {}
					for _, key in ipairs(self.types) do
						values[key] = L.TypeLabel(key)
					end
					return values
				end,
				get = function()
					return self:CurrentType()
				end,
				set = function(_, value)
					self:SelectType(value)
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
			font = {
				type = "select",
				name = "Font",
				order = 8,
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
				order = 9,
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
			reset = {
				type = "execute",
				name = "Reset",
				order = 10,
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

local function normalizePath(path)
	if type(path) ~= "string" then
		return path
	end
	return path:lower():gsub("/", "\\")
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
				local menuUtil = type(MenuUtil) == "table" and MenuUtil or {}
				checkFn("C_DamageMeter.GetCombatSessionFromType", cdm.GetCombatSessionFromType)
				checkFn("C_DamageMeter.GetAvailableCombatSessions", cdm.GetAvailableCombatSessions)
				checkFn("C_DamageMeter.GetCombatSessionFromID", cdm.GetCombatSessionFromID)
				checkFn("C_DamageMeter.ResetAllCombatSessions", cdm.ResetAllCombatSessions)
				checkFn("C_DamageMeter.IsDamageMeterAvailable", cdm.IsDamageMeterAvailable)
				checkTbl("Enum.DamageMeterSessionType", type(Enum) == "table" and Enum.DamageMeterSessionType)
				checkTbl("Enum.DamageMeterType", type(Enum) == "table" and Enum.DamageMeterType)
				checkFn("AbbreviateNumbers", AbbreviateNumbers)
				checkTbl("CLASS_ICON_TCOORDS", CLASS_ICON_TCOORDS)
				checkTbl("RAID_CLASS_COLORS", RAID_CLASS_COLORS)
				checkFn("MenuUtil.CreateContextMenu", menuUtil.CreateContextMenu)

				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "types",
			run = function()
				local list = L.TypeList(Enum.DamageMeterType)
				if #list == 0 then
					return "FAIL", "no types"
				end

				local groups = L.MenuGroups(list)
				local grouped, other = 0, 0
				for _, group in ipairs(groups) do
					if group.label == "Other" then
						other = other + #group.keys
					else
						grouped = grouped + #group.keys
					end
				end

				return "PASS", #list, grouped, other, table.concat(list, " ")
			end,
		},
		{
			name = "type",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local profile = self.db.profile
				local stored = false
				for _, key in ipairs(self.types) do
					if key == profile.metric then
						stored = true
						break
					end
				end

				if stored then
					return "PASS", profile.metric, Enum.DamageMeterType[profile.metric], L.TypeKind(profile.metric)
				end
				return "INFO", "fallback", profile.metric, self:CurrentType()
			end,
		},
		{
			name = "type counts",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local parts = {}
				for _, key in ipairs(self.types) do
					local s = self:ReadSession(key)
					local n = #(s and s.combatSources or {})
					local text
					if issecretvalue(n) then
						text = "?"
					else
						text = tostring(n)
					end
					table.insert(parts, key .. "=" .. text)
				end

				return "INFO", table.concat(parts, " ")
			end,
		},
		{
			name = "segments",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local raw = C_DamageMeter.GetAvailableCombatSessions() or {}
				local count = #raw
				local secretNames = 0
				for _, entry in ipairs(raw) do
					if issecretvalue(entry.name) then
						secretNames = secretNames + 1
					end
				end

				local readable = false
				local present = false
				for _, entry in ipairs(raw) do
					if not issecretvalue(entry.sessionID) then
						readable = true
						if entry.sessionID == self.segmentID then
							present = true
							break
						end
					end
				end

				if self.segmentID and not readable then
					return "INFO", "secret", count, secretNames, self.segmentID
				end

				if self.segmentID and not present then
					return "FAIL", "stale", self.segmentID, count
				end

				return "INFO", count, secretNames, self.segmentID or "none", present
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
				local available, reason = C_DamageMeter.IsDamageMeterAvailable()
				return "INFO", available, reason
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

				local expected = L.Title(self:SessionLabel(), self:CurrentType())
				local ok = text == expected

				if self.segmentID then
					return ok and "PASS" or "FAIL", "segment", self.segmentID
				end
				return ok and "PASS" or "FAIL", text, expected
			end,
		},
		{
			name = "session",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local profile = self.db.profile
				local typeKey = self:CurrentType()
				local session = self:ReadSession(typeKey)
				local src = session and session.combatSources or {}
				local count = #src

				local label = self.segmentID and "segment" or profile.session
				local sessionValue = self.segmentID or L.EnumKey(Enum.DamageMeterSessionType, profile.session)
				local typeValue = Enum.DamageMeterType[typeKey]

				local s = src[1]
				local secretAmount, secretName, secretClass = false, false, false
				if s then
					if issecretvalue(s.totalAmount) then
						secretAmount = true
					end
					if issecretvalue(s.name) then
						secretName = true
					end
					if issecretvalue(s.classFilename) then
						secretClass = true
					end
				end

				return "INFO", label, typeKey, sessionValue, typeValue, count, secretAmount, secretName, secretClass
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

				local t = self:CurrentType()
				local kind = L.TypeKind(t)
				if kind == "deaths" then
					return "SKIP", "unordered type"
				end

				local session = self:ReadSession(t)
				local src = session and session.combatSources or {}
				local n = L.VisibleRows(#src, self.db.profile.rows)
				if n < 2 then
					return "SKIP", "too few sources"
				end

				local field = L.BarField(kind)
				for i = 1, n do
					if issecretvalue(src[i][field]) then
						return "INFO", "secret"
					end
				end

				for i = 2, n do
					if src[i][field] > src[i - 1][field] then
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

				local profile = self.db.profile
				local resolved = ns.Media:Resolve("font", profile.font)
				local expected = normalizePath(ns.Media:FontPath(profile.font))

				local path, size = self.title:GetFont()
				local ok = type(path) == "string" and normalizePath(path) == expected and math.floor(size + 0.5) == 11

				local row = self.rows[1]
				if ok and row then
					local _, rowSize = row.left:GetFont()
					ok = math.floor(rowSize + 0.5) == profile.fontSize
				end

				local barTexture = row and row.bar:GetStatusBarTexture()

				return ok and "PASS" or "FAIL",
					path,
					size,
					resolved,
					barTexture and barTexture:GetTexture(),
					ns.Media:Resolve("statusbar", profile.barTexture),
					row and row.barPath
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
