local addonName, ns = ...

local RangeTextLogic = ns.RangeTextLogic

local RangeText = ns.addon:NewModule("RangeText", "AceEvent-3.0")

local function traceState(self, state)
	if state ~= self.lastTraceState then
		ns.Debug:Log("RangeText", "state", state)
		self.lastTraceState = state
	end
end

local defaults = {
	profile = {
		enabled = true,
		spell = "",
		font = "Fonts\\FRIZQT__.TTF",
		fontSize = 18,
		outline = "OUTLINE",
		position = { point = "CENTER", x = 0, y = -150 },
	},
}

local UPDATE_INTERVAL = 0.1

function RangeText:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("RangeText", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	local frame = CreateFrame("Frame", addonName .. "RangeText", UIParent)
	frame:SetSize(120, 24)
	frame:Hide()
	self.frame = frame

	local fsMain = frame:CreateFontString(nil, "OVERLAY")
	fsMain:SetPoint("CENTER")
	self.fsMain = fsMain

	local fsOut = frame:CreateFontString(nil, "OVERLAY")
	fsOut:SetPoint("CENTER")
	self.fsOut = fsOut

	ns.Mover:Register(frame, "Range", function()
		return self.db.profile.position
	end)

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= UPDATE_INTERVAL then
			elapsed = 0
			self:Update()
		end
	end)
end

function RangeText:OnEnable()
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "Update")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "Update")
	self:ApplyFont()
	ns.Mover:Apply(self.frame)
	self:Update()
end

function RangeText:OnDisable()
	self.frame:Hide()
end

function RangeText:ApplyFont()
	local profile = self.db.profile
	local ok = self.fsMain:SetFont(profile.font, profile.fontSize, profile.outline)
	if ok then
		self.fsOut:SetFont(profile.font, profile.fontSize, profile.outline)
		self.lastGoodFont = profile.font
		self.reportedBadFont = nil
		return
	end

	local fallback = self.lastGoodFont or defaults.profile.font
	self.fsMain:SetFont(fallback, profile.fontSize, profile.outline)
	self.fsOut:SetFont(fallback, profile.fontSize, profile.outline)
	if self.reportedBadFont ~= profile.font then
		self.reportedBadFont = profile.font
		ns.addon:Print("RangeText: invalid font path '" .. tostring(profile.font) .. "', falling back to " .. fallback)
	end
end

function RangeText:Refresh()
	if self.db.profile.enabled then
		self:Enable()
		self:ApplyFont()
		ns.Mover:Apply(self.frame)
		self:Update()
	else
		self:Disable()
	end
end

function RangeText:Update()
	if not self:IsEnabled() then
		return
	end

	if not UnitExists("target") and not ns.Mover:IsUnlocked() then
		self.frame:Hide()
		traceState(self, "none")
		return
	end
	self.frame:Show()

	local min, max = LibStub("LibRangeCheck-3.0"):GetRange("target")
	local text = RangeTextLogic.FormatRange(min, max)

	local _, classFile = UnitClass("player")
	local spell = RangeTextLogic.ResolveSpell(self.db.profile.spell, classFile)

	if spell == nil then
		self.fsOut:Hide()
		self.fsMain:Show()
		self.fsMain:SetAlpha(1)
		self.fsMain:SetText(text)
		self.fsMain:SetTextColor(1, 1, 1, 1)
		traceState(self, "unknown")
		return
	end

	local r = C_Spell.IsSpellInRange(spell, "target")

	if issecretvalue(r) then
		self.fsMain:SetText(text)
		self.fsOut:SetText(text)
		self.fsMain:Show()
		self.fsOut:Show()
		self.fsMain:SetTextColor(0, 1, 0, 1)
		self.fsOut:SetTextColor(1, 0, 0, 1)
		self.fsMain:SetAlphaFromBoolean(r, 1, 0)
		self.fsOut:SetAlphaFromBoolean(r, 0, 1)
		traceState(self, "secret")
	else
		self.fsOut:Hide()
		self.fsMain:Show()
		self.fsMain:SetAlpha(1)
		self.fsMain:SetText(text)
		local state = RangeTextLogic.Classify(r)
		local cr, cg, cb = RangeTextLogic.Color(state)
		self.fsMain:SetTextColor(cr, cg, cb, 1)
		traceState(self, state)
	end
end

function RangeText:GetOptions()
	return {
		type = "group",
		name = "RangeText",
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
			spell = {
				type = "input",
				name = "Spell",
				order = 2,
				desc = function()
					local _, classFile = UnitClass("player")
					local default = RangeTextLogic.DEFAULT_SPELLS[classFile]
					local name = default and C_Spell.GetSpellName(default)
					return "empty = class default (" .. (name or "none") .. ")"
				end,
				get = function()
					return self.db.profile.spell
				end,
				set = function(_, value)
					self.db.profile.spell = value
					self:Update()
				end,
			},
			font = {
				type = "input",
				name = "Font",
				order = 3,
				get = function()
					return self.db.profile.font
				end,
				set = function(_, value)
					self.db.profile.font = value
					self:ApplyFont()
				end,
			},
			fontSize = {
				type = "range",
				name = "Font size",
				order = 4,
				min = 8,
				max = 48,
				step = 1,
				get = function()
					return self.db.profile.fontSize
				end,
				set = function(_, value)
					self.db.profile.fontSize = value
					self:ApplyFont()
				end,
			},
			outline = {
				type = "select",
				name = "Outline",
				order = 5,
				values = {
					[""] = "None",
					OUTLINE = "Outline",
					THICKOUTLINE = "Thick outline",
				},
				get = function()
					return self.db.profile.outline
				end,
				set = function(_, value)
					self.db.profile.outline = value
					self:ApplyFont()
				end,
			},
		},
	}
end

function RangeText:GetDebugChecks()
	return {
		{
			name = "spell",
			run = function()
				local _, classFile = UnitClass("player")
				local resolved = RangeTextLogic.ResolveSpell(self.db.profile.spell, classFile)
				if resolved == nil then
					return "INFO", "yards only"
				end

				local name = C_Spell.GetSpellName(resolved)
				local ok = type(name) == "string" and not issecretvalue(name)
				return ok and "PASS" or "FAIL", resolved, name
			end,
		},
		{
			name = "font",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local profile = self.db.profile
				local _, size, flags = self.fsMain:GetFont()
				flags = flags or ""

				local ok = self.lastGoodFont == profile.font
					and math.floor(size + 0.5) == profile.fontSize
					and flags == profile.outline
				return ok and "PASS" or "FAIL", self.lastGoodFont, size, flags
			end,
		},
		{
			name = "visibility",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local shown = self.frame:IsShown()
				local expected = ctx.hasTarget or ns.Mover:IsUnlocked()
				return (shown == expected) and "PASS" or "FAIL", shown, expected
			end,
		},
		{
			name = "range",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local text = self.fsMain:GetText()
				if issecretvalue(text) then
					return "INFO", "secret"
				end

				local min, max = LibStub("LibRangeCheck-3.0"):GetRange("target")
				if issecretvalue(min) or issecretvalue(max) then
					return "INFO", "secret"
				end

				local expected = RangeTextLogic.FormatRange(min, max)
				return (text == expected) and "PASS" or "FAIL", text, expected
			end,
		},
		{
			name = "in range",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end

				local _, classFile = UnitClass("player")
				local spell = RangeTextLogic.ResolveSpell(self.db.profile.spell, classFile)
				if spell == nil then
					return "INFO", "no spell"
				end

				local r = C_Spell.IsSpellInRange(spell, "target")
				if issecretvalue(r) then
					local shown = self.fsMain:IsShown() and self.fsOut:IsShown()
					return shown and "PASS" or "FAIL", "secret"
				end

				local cr, cg, cb = self.fsMain:GetTextColor()
				local er, eg, eb = RangeTextLogic.Color(RangeTextLogic.Classify(r))
				local ok = math.abs(cr - er) <= 0.01 and math.abs(cg - eg) <= 0.01 and math.abs(cb - eb) <= 0.01
				return ok and "PASS" or "FAIL", r, cr, cg, cb
			end,
		},
	}
end
