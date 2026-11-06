local addonName, ns = ...

local L = ns.DamageMeterLogic
local D = ns.DamageMeterData
local MoverLogic = ns.MoverLogic

local TEXTURE = "Interface\\Buttons\\WHITE8X8"

local Timer = {}
ns.DamageMeterTimer = Timer

local frame, text
local dm

local function profile()
	return dm.db.profile
end

local function savePosition()
	local cx, cy = frame:GetCenter()
	if not cx then
		return
	end
	local pos = profile().timerPosition
	local x, y = MoverLogic.CenterOffset(
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

local function build()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "MerrinxUIDamageMeterTimer", UIParent, "BackdropTemplate")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:Hide()
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	text = frame:CreateFontString(nil, "OVERLAY")
	text:SetAllPoints()
	text:SetShadowOffset(1, -1)
	frame:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() and not profile().timerLocked then
			self.moving = true
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		if self.moving then
			self.moving = false
			self:StopMovingOrSizing()
			local p = profile()
			p.timerAnchor = "free"
			savePosition()
		end
	end)
	ns.Mover:Register(frame, "Combat Timer", function()
		return profile().timerPosition
	end)
end

function Timer:Init(module)
	dm = module
end

function Timer:Layout()
	local p = profile()
	if not p.standaloneTimer then
		if frame then
			frame:Hide()
		end
		return
	end
	build()
	frame:SetSize(p.timerWidth, p.timerHeight)
	frame:SetFrameStrata(p.timerStrata)
	frame:EnableMouse(not p.timerLocked)
	ns.Media:SetFont(text, p.font, p.timerSize, "OUTLINE")
	text:SetJustifyH(p.timerAlign)
	local r, g, b = L.ParseHex(p.timerBgColor)
	frame.bg:SetColorTexture(r or 0, g or 0, b or 0, p.timerBgOpacity / 100)
	if p.timerBorderSize > 0 then
		frame:SetBackdrop({ edgeFile = TEXTURE, edgeSize = p.timerBorderSize })
		local br, bg, bb = L.ParseHex(p.timerBorderColor)
		frame:SetBackdropBorderColor(br or 0, bg or 0, bb or 0)
	else
		frame:SetBackdrop(nil)
	end
	local point, relPoint = L.TimerAnchor(p.timerAnchor)
	local anchorWin = dm.windows[1]
	if point and anchorWin then
		frame:ClearAllPoints()
		frame:SetPoint(point, anchorWin.frame, relPoint, 0, 0)
	else
		ns.Mover:Apply(frame)
	end
	self:Update()
end

function Timer:ShouldShow()
	local p = profile()
	if not p.standaloneTimer or not dm:IsEnabled() then
		return false
	end
	if dm.toggleHidden and p.toggleIncludeTimer then
		return false
	end
	if ns.Mover:IsUnlocked() then
		return true
	end
	return dm.inCombat == true or p.timerShowOOC == true
end

function Timer:Update()
	if not frame then
		return
	end
	local p = profile()
	local show = self:ShouldShow()
	frame:SetShown(show)
	if not show then
		return
	end
	local seconds = dm:CurrentDuration()
	text:SetText(p.timerDecimal and L.FormatTimerDecimal(seconds) or L.FormatTimer(seconds))
	local r, g, b = L.ParseHex(p.timerColor)
	if p.timerColorMode == "accent" or not r then
		r, g, b = D.AccentRGB()
	end
	if p.timerDesatOOC and not dm.inCombat then
		local grey = (r + g + b) / 3
		r, g, b = grey, grey, grey
	end
	text:SetTextColor(r, g, b, 1)
end

function Timer:Frame()
	return frame
end

ns.Debug:RegisterChecks("DamageMeter", function()
	return {
		{
			name = "standalone timer",
			run = function()
				if not dm then
					return "SKIP", "not initialised"
				end
				local expected = Timer:ShouldShow() == true
				local shown = frame ~= nil and frame:IsShown()
				if not profile().standaloneTimer then
					return shown and "FAIL" or "PASS", "off", shown
				end
				return (shown == expected) and "PASS" or "FAIL", shown, expected, text and text:GetText()
			end,
		},
	}
end)
