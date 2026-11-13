local addonName, ns = ...

local MouseCircleLogic = ns.MouseCircleLogic

local MouseCircle = ns.addon:NewModule("MouseCircle", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = false,
		size = 48,
		style = "normal",
		classColor = false,
		color = { r = 0.05, g = 0.82, b = 0.62 },
		opacity = 80,
	},
}

function MouseCircle:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("MouseCircle", defaults)
	self:SetEnabledState(self.db.profile.enabled)
end

function MouseCircle:Build()
	if self.frame then
		return
	end
	local frame = CreateFrame("Frame", addonName .. "MouseCircle", UIParent)
	frame:SetFrameStrata("TOOLTIP")
	frame:EnableMouse(false)
	frame:Hide()
	self.frame = frame

	local tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	self.tex = tex

	frame:SetScript("OnUpdate", function()
		self:OnUpdate()
	end)
end

function MouseCircle:OnUpdate()
	local scale = UIParent:GetEffectiveScale()
	local rawX, rawY = GetCursorPosition()
	local x, y = MouseCircleLogic.Anchor(rawX, rawY, scale)
	if x ~= self.lastX or y ~= self.lastY then
		self.lastX, self.lastY = x, y
		self.frame:ClearAllPoints()
		self.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	end
	self.tex:SetShown(not IsMouselooking())
end

function MouseCircle:OnEnable()
	self:Build()
	self.lastX, self.lastY = nil, nil
	self:Apply()
	self.frame:Show()
end

function MouseCircle:OnDisable()
	if self.frame then
		self.frame:Hide()
	end
end

function MouseCircle:Apply()
	local p = self.db.profile
	local style = MouseCircleLogic.Style(p.style)
	local texture = ns.Media:Icon(MouseCircleLogic.STYLES[style])
	self.textureOk = self.tex:SetTexture(texture)
	self.appliedTexture = texture

	local _, classFile = UnitClass("player")
	local r, g, b = MouseCircleLogic.Color(p, classFile, RAID_CLASS_COLORS)
	self.tex:SetVertexColor(r, g, b)

	self.frame:SetAlpha(MouseCircleLogic.Alpha(p.opacity))
	self.frame:SetSize(p.size, p.size)
end

function MouseCircle:Refresh()
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

function MouseCircle:GetTabOptions()
	local mc = self
	local function get(key)
		return function()
			return mc.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			mc.db.profile[key] = value
			mc:Refresh()
		end
	end
	return {
		type = "group",
		name = "MouseCircle",
		args = {
			enabled = {
				type = "toggle",
				name = "Enabled",
				order = 1,
				get = get("enabled"),
				set = set("enabled"),
			},
			size = {
				type = "range",
				name = "Size",
				order = 2,
				min = 16,
				max = 128,
				step = 2,
				get = get("size"),
				set = set("size"),
			},
			style = {
				type = "select",
				name = "Style",
				order = 3,
				values = MouseCircleLogic.STYLE_NAMES,
				get = function()
					return MouseCircleLogic.Style(mc.db.profile.style)
				end,
				set = set("style"),
			},
			classColor = {
				type = "toggle",
				name = "Class colour",
				order = 4,
				get = get("classColor"),
				set = set("classColor"),
			},
			color = {
				type = "color",
				name = "Colour",
				order = 5,
				hasAlpha = false,
				disabled = function()
					return mc.db.profile.classColor
				end,
				get = function()
					local c = mc.db.profile.color
					return c.r, c.g, c.b, 1
				end,
				set = function(_, r, g, b)
					local c = mc.db.profile.color
					c.r, c.g, c.b = r, g, b
					mc:Refresh()
				end,
			},
			opacity = {
				type = "range",
				name = "Opacity",
				order = 6,
				min = 10,
				max = 100,
				step = 5,
				get = get("opacity"),
				set = set("opacity"),
			},
		},
	}
end

function MouseCircle:GetDebugChecks()
	return {
		{
			name = "frame",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local ok = self.frame ~= nil and self.frame:IsShown() and self.frame:GetFrameStrata() == "TOOLTIP"
				return ok and "PASS" or "FAIL"
			end,
		},
		{
			name = "texture",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local p = self.db.profile
				local expected = ns.Media:Icon(MouseCircleLogic.STYLES[MouseCircleLogic.Style(p.style)])
				local ok = self.textureOk and self.appliedTexture == expected
				return ok and "PASS" or "FAIL", self.appliedTexture, expected
			end,
		},
		{
			name = "color",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local p = self.db.profile
				local _, classFile = UnitClass("player")
				local er, eg, eb = MouseCircleLogic.Color(p, classFile, RAID_CLASS_COLORS)
				local r, g, b = self.tex:GetVertexColor()
				local ok = math.abs(r - er) <= 0.01 and math.abs(g - eg) <= 0.01 and math.abs(b - eb) <= 0.01
				return ok and "PASS" or "FAIL", r, g, b, er, eg, eb
			end,
		},
	}
end
