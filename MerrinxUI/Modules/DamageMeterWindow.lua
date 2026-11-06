local addonName, ns = ...

local L = ns.DamageMeterLogic
local D = ns.DamageMeterData
local Menu = ns.DamageMeterMenu
local Tooltip = ns.DamageMeterTooltip
local MoverLogic = ns.MoverLogic

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local POOL = 40
local MIN_W, MIN_H = 150, 50
local SNAP = 6
local ICON_ALPHA, ICON_HOVER_ALPHA = 0.4, 0.9
local CARD_H, CARD_GAP, CARD_PAD = 26, 4, 8

local Window = {}
ns.DamageMeterWindow = Window
Window.__index = Window

local function hex(text, r, g, b)
	local hr, hg, hb = L.ParseHex(text)
	if hr then
		return hr, hg, hb
	end
	return r, g, b
end

local function cursor(frame)
	local x, y = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	return x / scale, y / scale
end

local function rectOf(frame, left, top)
	left = left or frame:GetLeft() or 0
	top = top or frame:GetTop() or 0
	return { left = left, right = left + frame:GetWidth(), top = top, bottom = top - frame:GetHeight() }
end

local function setFont(fs, profile, size)
	ns.Media:SetFont(fs, profile.font, size, "")
end

function Window:Profile()
	return self.dm.db.profile
end

function Window:DB()
	return self.dm:WindowDB(self.idx)
end

local function makeRow(w, parent, isSpell)
	local bar = {}
	bar.row = CreateFrame("Button", nil, parent)
	bar.row:RegisterForClicks("AnyUp")
	bar.bg = bar.row:CreateTexture(nil, "BACKGROUND", nil, -8)
	bar.bg:SetAllPoints(bar.row)
	bar.icon = bar.row:CreateTexture(nil, "ARTWORK")
	bar.icon:SetPoint("LEFT", bar.row, "LEFT", 0, 0)
	bar.fill = CreateFrame("StatusBar", nil, bar.row)
	bar.fill:SetStatusBarTexture(TEXTURE)
	bar.fill:SetMinMaxValues(0, 1)
	local text = CreateFrame("Frame", nil, bar.row)
	text:SetAllPoints(bar.fill)
	text:SetFrameLevel(bar.fill:GetFrameLevel() + 4)
	bar.text = text
	bar.pos = text:CreateFontString(nil, "OVERLAY")
	bar.pos:SetShadowOffset(1, -1)
	bar.label = text:CreateFontString(nil, "OVERLAY")
	bar.label:SetJustifyH("LEFT")
	bar.label:SetWordWrap(false)
	bar.label:SetShadowOffset(1, -1)
	bar.amount = text:CreateFontString(nil, "OVERLAY")
	bar.amount:SetJustifyH("RIGHT")
	bar.amount:SetShadowOffset(1, -1)
	bar.hl = text:CreateTexture(nil, "BACKGROUND")
	bar.hl:SetAllPoints(bar.row)
	bar.hl:SetColorTexture(1, 1, 1, 0.08)
	bar.hl:Hide()
	bar.marker = text:CreateTexture(nil, "OVERLAY")
	bar.marker:SetPoint("TOPLEFT", bar.fill, "TOPLEFT", 0, 0)
	bar.marker:SetPoint("BOTTOMLEFT", bar.fill, "BOTTOMLEFT", 0, 0)
	bar.marker:SetWidth(2)
	bar.marker:SetColorTexture(1, 1, 1, 0.9)
	bar.marker:Hide()

	if isSpell then
		bar.row:SetScript("OnClick", function()
			w:CloseSource()
		end)
		bar.row:SetScript("OnEnter", function(self)
			D.ShowSpellTooltip(self, bar.spellID, w:Profile())
		end)
		bar.row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	else
		bar.row:SetScript("OnClick", function(_, button)
			if button == "LeftButton" then
				w:OnRowClick(bar)
			elseif button == "RightButton" then
				w:ShowHome()
			end
		end)
		bar.row:SetScript("OnEnter", function(self)
			bar.hl:Show()
			w:StartHover()
			if bar.src then
				Tooltip:Show(self, w.frame, w.view, bar.src, w:Profile())
			end
		end)
		bar.row:SetScript("OnLeave", function()
			bar.hl:Hide()
			Tooltip:Hide()
		end)
	end
	bar.row:Hide()
	return bar
end

local function styleRow(bar, profile, barH, texture, withPos)
	bar.row:SetHeight(barH)
	if bar.texture ~= texture then
		bar.fill:SetStatusBarTexture(texture)
		bar.texture = texture
	end
	bar.fill:GetStatusBarTexture():SetAlpha(1)
	bar.fill:SetAlpha(profile.barOpacity / 100)
	setFont(bar.pos, profile, profile.leftFontSize)
	setFont(bar.label, profile, profile.leftFontSize)
	setFont(bar.amount, profile, profile.rightFontSize)
	bar.pos:ClearAllPoints()
	bar.label:ClearAllPoints()
	bar.amount:ClearAllPoints()
	local lx, ly = profile.leftTextOffsetX, profile.leftTextOffsetY
	bar.pos:SetPoint("LEFT", bar.text, "LEFT", 3 + lx, ly)
	if withPos then
		bar.label:SetPoint("LEFT", bar.pos, "RIGHT", 2, 0)
	else
		bar.label:SetPoint("LEFT", bar.text, "LEFT", 3 + lx, ly)
	end
	bar.amount:SetPoint("RIGHT", bar.text, "RIGHT", -3 + profile.rightTextOffsetX, profile.rightTextOffsetY)
	bar.label:SetPoint("RIGHT", bar.amount, "LEFT", -4, 0)
	local br, bg, bb = hex(profile.barBgColor, 0, 0, 0)
	bar.bgColor = { br, bg, bb, profile.barBgOpacity / 100 }
	bar.bg:SetColorTexture(br, bg, bb, profile.barBgOpacity / 100)
	if profile.barBorderSize > 0 then
		if not bar.border then
			bar.border = CreateFrame("Frame", nil, bar.row, "BackdropTemplate")
			bar.border:SetAllPoints(bar.row)
			bar.border:SetFrameLevel(bar.row:GetFrameLevel() + 3)
		end
		bar.border:SetBackdrop({ edgeFile = TEXTURE, edgeSize = profile.barBorderSize })
		bar.border:SetBackdropBorderColor(hex(profile.barBorderColor, 0, 0, 0))
		bar.border:Show()
	elseif bar.border then
		bar.border:Hide()
	end
end

function Window.New(dm, idx)
	local w = setmetatable({}, Window)
	w.dm = dm
	w.idx = idx
	local wdb = dm:WindowDB(idx)
	w.view = { session = wdb.session, sessionID = nil, type = dm:ResolveType(wdb.type) }
	w.locked = wdb.locked
	w.rows = {}
	w.spellRows = {}
	w.cards = {}
	w.buttons = {}
	w.scroll = 0
	w.scrollMax = 0
	w.srcScrollMax = 0

	local frame = CreateFrame("Frame", "MerrinxUIDamageMeter" .. idx, UIParent, "BackdropTemplate")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	w.frame = frame

	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetPoint("BOTTOMRIGHT")

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetFrameLevel(frame:GetFrameLevel() + 5)
	header:EnableMouse(true)
	w.header = header
	frame.bg:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	header.bg:SetAllPoints()
	header.line = header:CreateTexture(nil, "OVERLAY", nil, 7)
	header.line:SetPoint("BOTTOMLEFT")
	header.line:SetPoint("BOTTOMRIGHT")

	w.title = header:CreateFontString(nil, "OVERLAY")
	w.title:SetJustifyH("LEFT")
	w.title:SetWordWrap(false)
	w.timer = header:CreateFontString(nil, "OVERLAY")
	w.timer:SetTextColor(1, 1, 1, 0.7)
	w.timer:SetPoint("LEFT", w.title, "RIGHT", 4, 0)
	w.measure = header:CreateFontString(nil, "OVERLAY")
	w.measure:Hide()

	w:BuildButtons()
	w:BuildContent()
	w:BuildSource()
	w:BuildGrips()
	w:BuildDrag()

	frame:SetScript("OnShow", function()
		w:Refresh()
		dm:ReviveTicker()
	end)
	frame:HookScript("OnEnter", function()
		w:StartHover()
	end)

	ns.Mover:Register(frame, "Damage Meter " .. idx, function()
		return dm:WindowDB(w.idx).position
	end)
	return w
end

function Window:IconColor()
	local p = self:Profile()
	if p.iconColorUseAccent then
		return D.AccentRGB()
	end
	return 1, 1, 1
end

function Window:MakeButton(key, icon, tip, onClick)
	local w = self
	local btn = CreateFrame("Button", nil, self.header)
	btn:SetFrameLevel(self.header:GetFrameLevel() + 2)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints()
	btn.icon:SetTexture(ns.Media:Icon(icon))
	btn.key = key
	local function paint(alpha)
		local r, g, b = w:IconColor()
		btn.icon:SetVertexColor(r, g, b, alpha)
	end
	btn.paint = paint
	paint(ICON_ALPHA)
	btn:SetScript("OnEnter", function(owner)
		paint(btn.dim and ICON_ALPHA * 0.5 or ICON_HOVER_ALPHA)
		w:StartHover()
		if not Menu:IsOpenFor(owner) then
			GameTooltip:SetOwner(owner, "ANCHOR_TOP")
			GameTooltip:SetText(btn.tip or tip, 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function()
		paint(btn.dim and ICON_ALPHA * 0.5 or ICON_ALPHA)
		GameTooltip:Hide()
	end)
	btn:SetScript("OnClick", function(owner)
		GameTooltip:Hide()
		onClick(owner)
	end)
	self.buttons[key] = btn
	return btn
end

function Window:BuildButtons()
	local w = self
	self:MakeButton("settings", "settings", "Settings", function(btn)
		w:OpenSettingsMenu(btn)
	end)
	self:MakeButton("segment", "segment", "Select Segment", function(btn)
		w:OpenSegmentMenu(btn)
	end)
	self:MakeButton("mode", L.TypeIcon(self.view.type), "Switch Meter Type", function(btn)
		w:OpenTypeMenu(btn)
	end)
	self:MakeButton("reset", "reset", "Reset Data", function()
		w.dm:ResetData()
	end)
	if self.idx == 1 then
		self:MakeButton("window", "open", "New Window", function()
			w.dm:NewWindow(w)
		end)
	else
		self:MakeButton("window", "close", "Close Window", function()
			if not w.locked then
				w.dm:CloseWindow(w)
			end
		end)
	end
	self.order = { "settings", "segment", "mode", "reset", "window" }
end

function Window:VisibleButtons()
	local p = self:Profile()
	local list = {}
	for _, key in ipairs(self.order) do
		if not (key == "reset" and p.hideResetButton) then
			table.insert(list, self.buttons[key])
		end
	end
	return list
end

function Window:LayoutButtons()
	local p = self:Profile()
	local size = p.hdrIconSize
	local pad = 2
	for _, btn in pairs(self.buttons) do
		btn:Hide()
	end
	local x = -pad
	for _, btn in ipairs(self:VisibleButtons()) do
		btn:SetSize(size, size)
		btn:ClearAllPoints()
		btn:SetPoint("RIGHT", self.header, "RIGHT", x, 0)
		btn:SetShown(not p.hdrMouseoverIcons or self.hovered == true)
		btn.paint(btn.dim and ICON_ALPHA * 0.5 or ICON_ALPHA)
		x = x - size - pad
	end
	local window = self.buttons.window
	if self.idx == 1 then
		window.dim = #self.dm.windows >= L.MAX_WINDOWS
		window.tip = window.dim and ("You may only have " .. L.MAX_WINDOWS .. " windows active") or "New Window"
	else
		window.dim = self.locked
		window.tip = self.locked and "Unlock Window to Close" or "Close Window"
	end
	window.paint(window.dim and ICON_ALPHA * 0.5 or ICON_ALPHA)
end

function Window:BuildContent()
	local w = self
	local frame = self.frame

	local catcher = CreateFrame("Button", nil, frame)
	catcher:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT")
	catcher:SetPoint("BOTTOMRIGHT")
	catcher:SetFrameLevel(frame:GetFrameLevel() + 1)
	catcher:RegisterForClicks("RightButtonUp")
	catcher:SetScript("OnClick", function()
		w:ShowHome()
	end)
	catcher:HookScript("OnEnter", function()
		w:StartHover()
	end)

	local viewport = CreateFrame("ScrollFrame", nil, frame)
	viewport:SetFrameLevel(frame:GetFrameLevel() + 2)
	self.viewport = viewport
	local content = CreateFrame("Frame", nil, viewport)
	content:SetSize(1, 1)
	viewport:SetScrollChild(content)
	self.content = content
	viewport:SetScript("OnSizeChanged", function(_, width)
		if width and width > 0 then
			content:SetWidth(width)
		end
		if w.session then
			w:Paint(w.session)
		end
	end)
	viewport:EnableMouseWheel(true)
	viewport:SetScript("OnMouseWheel", function(_, delta)
		local p = w:Profile()
		local stride = p.barHeight + p.barSpacing
		w.scroll = L.WheelScroll(viewport:GetVerticalScroll() or 0, delta, stride, w.scrollMax)
		viewport:SetVerticalScroll(w.scroll)
		if w.session then
			w:Paint(w.session)
		end
	end)
	viewport:HookScript("OnEnter", function()
		w:StartHover()
	end)

	for i = 1, POOL do
		self.rows[i] = makeRow(self, content, false)
	end
	self.sticky = makeRow(self, frame, false)
	self.sticky.row:SetFrameLevel(frame:GetFrameLevel() + 8)
	self.stickyLine = frame:CreateTexture(nil, "OVERLAY", nil, 6)
	self.stickyLine:SetHeight(1)
	self.stickyLine:SetColorTexture(0, 0, 0, 1)
	self.stickyLine:Hide()
end

function Window:BuildSource()
	local w = self
	local pane = CreateFrame("Frame", nil, self.frame)
	pane:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT")
	pane:SetPoint("BOTTOMRIGHT")
	pane:SetFrameLevel(self.frame:GetFrameLevel() + 20)
	pane:EnableMouse(true)
	pane:Hide()
	pane.bg = pane:CreateTexture(nil, "BACKGROUND")
	pane.bg:SetAllPoints()
	pane:SetScript("OnMouseDown", function()
		w:CloseSource()
	end)
	self.sourcePane = pane

	local viewport = CreateFrame("ScrollFrame", nil, pane)
	viewport:SetAllPoints()
	local content = CreateFrame("Frame", nil, viewport)
	content:SetSize(1, 1)
	viewport:SetScrollChild(content)
	viewport:SetScript("OnSizeChanged", function(_, width)
		content:SetWidth(width)
	end)
	viewport:EnableMouseWheel(true)
	viewport:SetScript("OnMouseWheel", function(_, delta)
		local p = w:Profile()
		local step = (p.barHeight + p.barSpacing) * 2
		local value = (viewport:GetVerticalScroll() or 0) - delta * step
		viewport:SetVerticalScroll(math.max(0, math.min(w.srcScrollMax, value)))
	end)
	self.srcViewport = viewport
	self.srcContent = content

	pane.message = content:CreateFontString(nil, "OVERLAY")
	pane.message:SetPoint("TOP", content, "TOP", 0, -12)
	pane.message:SetTextColor(1, 1, 1, 0.7)
	pane.divider = content:CreateTexture(nil, "ARTWORK")
	pane.divider:SetHeight(1)
	pane.divider:SetColorTexture(1, 1, 1, 0.15)
	pane.targets = content:CreateFontString(nil, "OVERLAY")
	pane.targets:SetTextColor(0.6, 0.6, 0.6, 1)
	pane.targets:SetText("Targets")
end

function Window:BuildGrips()
	local w = self
	local frame = self.frame

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 30)
	grip.icon = grip:CreateTexture(nil, "ARTWORK")
	grip.icon:SetAllPoints()
	grip.icon:SetTexture(ns.Media:Icon("resize"))
	grip:SetAlpha(0)
	self.grip = grip

	local lock = CreateFrame("Button", nil, frame)
	lock:SetSize(14, 14)
	lock:SetFrameLevel(frame:GetFrameLevel() + 31)
	lock.icon = lock:CreateTexture(nil, "ARTWORK")
	lock.icon:SetAllPoints()
	lock:SetAlpha(0)
	self.lock = lock

	lock:SetScript("OnEnter", function(owner)
		owner:SetAlpha(0.7)
		GameTooltip:SetOwner(owner, "ANCHOR_TOP")
		GameTooltip:SetText(w.locked and "Locked" or "Unlocked", 1, 1, 1)
		GameTooltip:Show()
	end)
	lock:SetScript("OnLeave", function(owner)
		owner:SetAlpha(w.hovered and 0.3 or 0)
		GameTooltip:Hide()
	end)
	lock:SetScript("OnClick", function(owner)
		w.locked = not w.locked
		w:DB().locked = w.locked
		w:UpdateLock()
		GameTooltip:SetOwner(owner, "ANCHOR_TOP")
		GameTooltip:SetText(w.locked and "Locked" or "Unlocked", 1, 1, 1)
		GameTooltip:Show()
		ns.Debug:Log("DamageMeter", "lock", w.idx, w.locked)
	end)
	grip:SetScript("OnEnter", function(owner)
		if not w.locked then
			owner:SetAlpha(0.7)
		end
		w:StartHover()
	end)
	grip:SetScript("OnLeave", function(owner)
		owner:SetAlpha((w.hovered and not w.locked) and 0.3 or 0)
	end)

	local sizer = CreateFrame("Frame")
	sizer:Hide()
	sizer:SetScript("OnUpdate", function()
		local x, y = cursor(frame)
		local dx, dy = x - w.sizeStart.x, w.sizeStart.y - y
		local newW, newH = w.sizeStart.w + dx, w.sizeStart.h + dy
		if IsShiftKeyDown() then
			w.sizeAxis = w.sizeAxis or (math.abs(dx) >= math.abs(dy) and "w" or "h")
			if w.sizeAxis == "w" then
				newH = w.sizeStart.h
			else
				newW = w.sizeStart.w
			end
		else
			w.sizeAxis = nil
		end
		newW, newH = math.max(MIN_W, newW), math.max(MIN_H, newH)
		local near = not w:DB().snapDisabled and w:ClosestWindow()
		if near then
			newW = L.SnapSize(newW, near.frame:GetWidth(), SNAP)
			newH = L.SnapSize(newH, near.frame:GetHeight(), SNAP)
		end
		newW = math.min(newW, math.max(MIN_W, (UIParent:GetRight() or newW) - w.sizeStart.left))
		newH = math.min(newH, math.max(MIN_H, w.sizeStart.top - (UIParent:GetBottom() or 0)))
		frame:SetSize(newW, newH)
	end)
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" or w.locked then
			return
		end
		local left, top = frame:GetLeft(), frame:GetTop()
		if not left then
			return
		end
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		local x, y = cursor(frame)
		w.sizeStart = { x = x, y = y, w = frame:GetWidth(), h = frame:GetHeight(), left = left, top = top }
		w.sizeAxis = nil
		sizer:Show()
	end)
	grip:SetScript("OnMouseUp", function()
		if not sizer:IsShown() then
			return
		end
		sizer:Hide()
		local wdb = w:DB()
		wdb.width = math.floor(frame:GetWidth() + 0.5)
		wdb.height = math.floor(frame:GetHeight() + 0.5)
		w:SavePosition()
		ns.Debug:Log("DamageMeter", "resize", w.idx, wdb.width, wdb.height)
	end)
	self:UpdateLock()
end

function Window:UpdateLock()
	self.lock.icon:SetTexture(ns.Media:Icon(self.locked and "locked" or "unlocked"))
	self.lock:ClearAllPoints()
	if self.locked then
		self.lock:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -3, 3)
		self.grip:SetAlpha(0)
	else
		self.lock:SetPoint("RIGHT", self.grip, "LEFT", -2, 0)
	end
	self.lock:SetAlpha(self.hovered and 0.3 or 0)
	if not self.locked then
		self.grip:SetAlpha(self.hovered and 0.3 or 0)
	end
	self:LayoutButtons()
end

function Window:SavePosition()
	local frame = self.frame
	local cx, cy = frame:GetCenter()
	if not cx then
		return
	end
	local pos = self:DB().position
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

function Window:ClosestWindow(left, top)
	local others, list = {}, {}
	for _, other in ipairs(self.dm.windows) do
		if other ~= self and other.frame:IsShown() and other.frame:GetLeft() then
			table.insert(others, rectOf(other.frame))
			table.insert(list, other)
		end
	end
	local i = L.Closest(rectOf(self.frame, left, top), others)
	return i and list[i]
end

function Window:BuildDrag()
	local w = self
	local frame = self.frame
	local header = self.header
	local dragger = CreateFrame("Frame")
	dragger:Hide()
	dragger:SetScript("OnUpdate", function(owner)
		if not IsMouseButtonDown("LeftButton") then
			owner:Hide()
			w:SavePosition()
			return
		end
		local x, y = cursor(frame)
		local left = w.dragStart.left + (x - w.dragStart.x)
		local top = w.dragStart.top + (y - w.dragStart.y)
		local near = not w:DB().snapDisabled and w:ClosestWindow(left, top)
		if near then
			left, top = L.SnapPosition(left, top, frame:GetWidth(), frame:GetHeight(), rectOf(near.frame), SNAP)
		end
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end)
	header:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" or w.locked or ns.Mover:IsUnlocked() then
			return
		end
		local left, top = frame:GetLeft(), frame:GetTop()
		if not left then
			return
		end
		local x, y = cursor(frame)
		w.dragStart = { x = x, y = y, left = left, top = top }
		dragger:Show()
	end)
	header:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and not dragger:IsShown() then
			w:ToggleHome()
		elseif button == "LeftButton" and dragger:IsShown() then
			dragger:Hide()
			w:SavePosition()
		end
	end)
	header:HookScript("OnEnter", function()
		w:StartHover()
	end)
end

function Window:StartHover()
	if self.hoverTicker then
		return
	end
	local w = self
	local function poll()
		local over = w.frame:IsVisible() and (w.frame:IsMouseOver() or w.grip:IsMouseOver() or w.lock:IsMouseOver())
		if over ~= w.hovered then
			w.hovered = over
			if not w.grip:IsMouseOver() then
				w.grip:SetAlpha((over and not w.locked) and 0.3 or 0)
			end
			if not w.lock:IsMouseOver() then
				w.lock:SetAlpha(over and 0.3 or 0)
			end
			if w:Profile().hdrMouseoverIcons then
				w:LayoutButtons()
				w:FitTitle()
			end
		end
		if not over and w.hoverTicker then
			w.hoverTicker:Cancel()
			w.hoverTicker = nil
		end
	end
	self.hoverTicker = C_Timer.NewTicker(0.1, poll)
	poll()
end

function Window:Layout()
	local p = self:Profile()
	local wdb = self:DB()
	local frame = self.frame

	frame:SetSize(math.max(MIN_W, wdb.width), math.max(MIN_H, wdb.height))
	ns.Mover:Apply(frame)

	local r, g, b = hex(p.bgColor, 0, 0, 0)
	frame.bg:SetColorTexture(r, g, b, p.bgOpacity / 100)
	self.sourcePane.bg:SetColorTexture(r, g, b, math.max(p.bgOpacity, 75) / 100)
	if p.windowBorderSize > 0 then
		frame:SetBackdrop({ edgeFile = TEXTURE, edgeSize = p.windowBorderSize })
		frame:SetBackdropBorderColor(hex(p.windowBorderColor, 0, 0, 0))
	else
		frame:SetBackdrop(nil)
	end

	local header = self.header
	header:SetHeight(p.hdrHeight)
	local hr, hg, hb = hex(p.hdrColor, 0x1B / 255, 0x1B / 255, 0x1B / 255)
	header.bg:SetColorTexture(hr, hg, hb, p.hdrOpacity / 100)
	header.line:SetHeight(math.max(p.hdrBottomBorder, 1))
	header.line:SetColorTexture(hex(p.hdrBottomBorderColor, 0, 0, 0))
	header.line:SetShown(p.hdrBottomBorder > 0)
	setFont(self.title, p, p.hdrFontSize)
	setFont(self.timer, p, p.hdrFontSize)
	setFont(self.measure, p, p.hdrFontSize)
	self.title:ClearAllPoints()
	self.title:SetPoint("LEFT", header, "LEFT", 6 + p.hdrTextOffsetX, p.hdrTextOffsetY)
	local tr, tg, tb = hex(p.hdrTextColor, 1, 1, 1)
	if p.hdrTextUseAccent then
		tr, tg, tb = D.AccentRGB()
	end
	self.title:SetTextColor(tr, tg, tb, 1)
	self.timer:SetShown(not wdb.hideTimer)
	self:LayoutButtons()

	local texture = ns.Media:Fetch("statusbar", p.barTexture) or TEXTURE
	for _, bar in ipairs(self.rows) do
		styleRow(bar, p, p.barHeight, texture, true)
		bar.cache = nil
		bar.slot = nil
	end
	styleRow(self.sticky, p, p.barHeight, texture, true)
	self.sticky.cache = nil
	local srcTexture = p.breakdownTexture == "match" and texture
		or ns.Media:Fetch("statusbar", p.breakdownTexture)
		or texture
	for _, bar in ipairs(self.spellRows) do
		styleRow(bar, p, p.barHeight, srcTexture, false)
	end
	self.srcTexture = srcTexture
	setFont(self.sourcePane.message, p, p.leftFontSize)
	setFont(self.sourcePane.targets, p, math.max(8, p.leftFontSize - 1))
	self:ResetViewport()
	if self.homeShown then
		self:RefreshHome()
	end
end

function Window:ResetViewport(pinnedTop, pinnedBottom)
	self.viewport:ClearAllPoints()
	self.viewport:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -(pinnedTop or 0))
	self.viewport:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, pinnedBottom or 0)
end

function Window:SetIcon()
	self.buttons.mode.icon:SetTexture(ns.Media:Icon(L.TypeIcon(self.view.type)))
end

function Window:FitTitle()
	local p = self:Profile()
	local full = self.fullTitle or ""
	local n = #self:VisibleButtons()
	if p.hdrMouseoverIcons and not self.hovered then
		n = 0
	end
	local timerW = self.timer:IsShown() and (self.timer:GetStringWidth() + 4) or 0
	local avail = (self.frame:GetWidth() or 0) - n * (p.hdrIconSize + 2) - 12 - p.hdrTextOffsetX - timerW
	local measure = self.measure
	self.title:SetText(L.FitText(full, math.max(1, avail), function(s)
		measure:SetText(s)
		return measure:GetStringWidth()
	end))
end

function Window:CurrentDuration()
	local view = self.view
	if view.sessionID then
		return D.SegmentDuration(view.sessionID)
	end
	if view.session == "Current" then
		return self.dm:CurrentDuration()
	end
	return nil
end

function Window:UpdateTimer()
	if not self.timer:IsShown() then
		return
	end
	local view = self.view
	local text = ""
	if view.sessionID or view.session == "Current" then
		text = "(" .. L.FormatTimer(self:CurrentDuration()) .. ")"
	end
	if text ~= self.timerText then
		self.timerText = text
		self.timer:SetText(text)
		self:FitTitle()
	end
end

function Window:DeathTime(src)
	local t = src.deathTimeSeconds
	if type(t) == "number" and not D.IsSecret(t) then
		return L.FormatTimer(t)
	end
	return self.dm:DeathStamp(src.deathRecapID, self.view)
end

function Window:Sources(session)
	local sources = session and session.combatSources or {}
	if self.view.type ~= "Deaths" then
		return sources
	end
	local out = {}
	for i = #sources, 1, -1 do
		local s = sources[i]
		local id = s.deathRecapID
		if id ~= nil and not D.IsSecret(id) and id > 0 and not self.dm:IsFeigned(s.sourceGUID) then
			table.insert(out, s)
		end
	end
	return out
end

function Window:PaintRow(bar, src, rank, ctx)
	local p = ctx.profile
	local class = D.Plain(src.classFilename)
	local specIcon = D.Plain(src.specIconID)
	local cache = bar.cache or {}
	bar.cache = cache

	if cache.class ~= class or cache.spec ~= specIcon or cache.rank ~= rank then
		cache.class, cache.spec, cache.rank = class, specIcon, rank
		local offset = D.ApplyIcon(bar.icon, class, specIcon, ctx.barH, p)
		bar.fill:ClearAllPoints()
		bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", offset, 0)
		bar.fill:SetPoint("BOTTOMRIGHT", bar.row, "BOTTOMRIGHT", 0, 0)
		bar.pos:SetText(p.hideNumbers and "" or (rank .. "."))

		local cr, cg, cb = D.ClassColor(class)
		if p.barColorMode == "accent" then
			cr, cg, cb = D.AccentRGB()
		elseif p.barColorMode == "custom" then
			cr, cg, cb = hex(p.barColor, 0.35, 0.55, 0.8)
		elseif not cr then
			if ctx.typeKey == "EnemyDamageTaken" then
				cr, cg, cb = D.ENEMY_COLOR[1], D.ENEMY_COLOR[2], D.ENEMY_COLOR[3]
			else
				cr, cg, cb = 0.5, 0.5, 0.5
			end
		end
		bar.fill:SetStatusBarColor(cr, cg, cb)

		local lr, lg, lb = hex(p.leftTextColor, 1, 1, 1)
		if p.leftTextColorMode == "class" then
			lr, lg, lb = D.ClassColor(class)
			lr, lg, lb = lr or 1, lg or 1, lb or 1
		end
		bar.label:SetTextColor(lr, lg, lb)
		bar.pos:SetTextColor(lr, lg, lb)

		local ar, ag, ab = hex(p.rightTextColor, 1, 1, 1)
		if p.rightTextColorMode == "class" then
			ar, ag, ab = D.ClassColor(class)
			ar, ag, ab = ar or 1, ag or 1, ab or 1
		elseif p.rightTextColorMode == "gradient" then
			ar, ag, ab = L.ValueGradient(rank, ctx.count)
		end
		bar.amount:SetTextColor(ar, ag, ab)

		local bgr, bgg, bgb = D.ClassColor(class)
		if p.barBgUseClassColor and bgr then
			bar.bg:SetColorTexture(bgr, bgg, bgb, p.barBgOpacity / 100)
		else
			bar.bg:SetColorTexture(unpack(bar.bgColor))
		end
	end

	if ctx.typeKey == "Deaths" then
		bar.fill:SetMinMaxValues(0, 1)
		bar.fill:SetValue(1)
	else
		bar.fill:SetMinMaxValues(0, ctx.max)
		bar.fill:SetValue(src[ctx.field] or 0)
	end

	bar.label:SetText(D.DisplayName(src.name))
	if ctx.typeKey == "Deaths" then
		bar.amount:SetText(ctx.isOverall and "" or self:DeathTime(src))
	else
		bar.amount:SetText(
			L.ValueText(ctx.kind, p.numberFormat, src.totalAmount, src.amountPerSecond, D.Abbrev, D.IsSecret)
		)
	end
	bar.marker:SetShown(p.showPlayerMarker and D.IsOwn(src))
	bar.src = src
end

function Window:Refresh()
	if not self.frame:IsVisible() then
		self.pending = true
		return
	end
	self.pending = false
	local session = D.Session(self.view)
	self:Paint(session)
end

function Window:Paint(session)
	if not self.frame:IsVisible() then
		self.pending = true
		return
	end
	if self.painting then
		return
	end
	self.painting = true
	self:PaintNow(session)
	self.painting = false
end

function Window:PaintNow(session)
	self.session = session
	local p = self:Profile()
	local sources = self:Sources(session)
	local count = math.min(#sources, POOL)
	local barH = p.barHeight
	local stride = barH + p.barSpacing
	local kind = L.TypeKind(self.view.type)
	local field = L.BarField(kind)
	local ctx = {
		profile = p,
		barH = barH,
		count = count,
		kind = kind,
		field = field,
		typeKey = self.view.type,
		max = sources[1] and sources[1][field] or 1,
		isOverall = not self.view.sessionID and self.view.session == "Overall",
	}
	self.sources = sources

	self.content:SetHeight(math.max(10, count * stride))
	self:UpdateSticky(sources, ctx, stride)
	local viewH = self.viewport:GetHeight() or 0
	if viewH <= 0 then
		viewH = count * stride
	end
	self.scroll, self.scrollMax = L.ClampScroll(self.viewport:GetVerticalScroll() or 0, count * stride, viewH)
	self.viewport:SetVerticalScroll(self.scroll)
	local first = math.floor(self.scroll / stride) + 1
	local last = math.min(count, math.ceil((self.scroll + viewH) / stride))

	for i = 1, POOL do
		local bar = self.rows[i]
		if i <= count then
			if bar.slot ~= i then
				bar.slot = i
				bar.row:ClearAllPoints()
				bar.row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * stride)
				bar.row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -(i - 1) * stride)
			end
			bar.row:Show()
			if i >= first and i <= last then
				self:PaintRow(bar, sources[i], i, ctx)
			end
		else
			bar.row:Hide()
			bar.src = nil
			bar.cache = nil
		end
	end

	self.fullTitle = L.Title(self.view.type, ctx.isOverall)
	self.timerText = nil
	self:UpdateTimer()
	self:FitTitle()

	if self.sourceOpen then
		self:RefreshSource()
	end
	self.paints = (self.paints or 0) + 1
end

function Window:UpdateSticky(sources, ctx, stride)
	local p = ctx.profile
	local sticky, line = self.sticky, self.stickyLine
	local function unpin()
		sticky.row:Hide()
		line:Hide()
		self:ResetViewport()
		self.pinned = nil
	end
	if not p.showPinnedSelf or self.sourceOpen or self.homeShown or self.view.type == "Deaths" then
		unpin()
		return
	end
	local playerIdx
	for i, src in ipairs(sources) do
		if i > POOL then
			break
		end
		if D.IsOwn(src) then
			playerIdx = i
			break
		end
	end
	if not playerIdx then
		unpin()
		return
	end
	local fullH = self.frame:GetHeight() - p.hdrHeight
	local pin = L.StickyPin(playerIdx, stride, ctx.barH, self.viewport:GetVerticalScroll() or 0, fullH)
	if not pin then
		unpin()
		return
	end
	self.pinned = pin
	sticky.row:ClearAllPoints()
	line:ClearAllPoints()
	if pin == "top" then
		sticky.row:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT")
		sticky.row:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT")
		line:SetPoint("TOPLEFT", sticky.row, "BOTTOMLEFT")
		line:SetPoint("TOPRIGHT", sticky.row, "BOTTOMRIGHT")
		self:ResetViewport(ctx.barH + 1, 0)
	else
		sticky.row:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT")
		sticky.row:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT")
		line:SetPoint("BOTTOMLEFT", sticky.row, "TOPLEFT")
		line:SetPoint("BOTTOMRIGHT", sticky.row, "TOPRIGHT")
		self:ResetViewport(0, ctx.barH + 1)
	end
	sticky.row:Show()
	line:Show()
	self:PaintRow(sticky, sources[playerIdx], playerIdx, ctx)
end

function Window:OnRowClick(bar)
	local src = bar.src
	if not src then
		return
	end
	local typeKey = self.view.type
	if typeKey == "Deaths" and not D.HasRecap(src) then
		return
	end
	local guid, cid = D.FetchIDs(src, typeKey)
	if guid == nil and cid == nil then
		return
	end
	self:OpenSource({
		sourceGUID = guid,
		sourceCreatureID = cid,
		name = src.name,
		classFilename = src.classFilename,
		specIconID = src.specIconID,
		deathRecapID = src.deathRecapID,
		isLocalPlayer = src.isLocalPlayer,
	})
end

function Window:OpenSource(src)
	Tooltip:Hide()
	self:HideHome()
	self.source = src
	self.sourceOpen = true
	self.viewport:Hide()
	self.sticky.row:Hide()
	self.stickyLine:Hide()
	self.frame.bg:Hide()
	self.srcViewport:SetVerticalScroll(0)
	self.sourcePane:Show()
	self:RefreshSource()
	ns.Debug:Log("DamageMeter", "breakdown", self.idx, self.view.type)
end

function Window:CloseSource()
	local wasOpen = self.sourceOpen
	self.sourceOpen = false
	self.source = nil
	self.sourcePane:Hide()
	self.viewport:Show()
	self.frame.bg:Show()
	GameTooltip:Hide()
	if wasOpen and self.session then
		self:Paint(self.session)
	end
end

function Window:SpellRow(i)
	local bar = self.spellRows[i]
	if not bar then
		bar = makeRow(self, self.srcContent, true)
		local p = self:Profile()
		styleRow(bar, p, p.barHeight, self.srcTexture or TEXTURE, false)
		self.spellRows[i] = bar
	end
	return bar
end

function Window:RefreshSource()
	if not self.sourceOpen or not self.source then
		return
	end
	if not self.frame:IsVisible() then
		self.pending = true
		return
	end
	local p = self:Profile()
	local pane = self.sourcePane
	local result = D.Breakdown(self.view, self.source, p, POOL)
	local barH = p.barHeight
	local stride = barH + p.barSpacing
	local y = 0
	local used = 0

	if result.message then
		pane.message:SetText(result.message)
		pane.message:Show()
		y = 40
	else
		pane.message:Hide()
	end

	local function paintList(list)
		for _, data in ipairs(list or {}) do
			if used >= POOL then
				return
			end
			used = used + 1
			local bar = self:SpellRow(used)
			bar.row:ClearAllPoints()
			bar.row:SetPoint("TOPLEFT", self.srcContent, "TOPLEFT", 0, -y)
			bar.row:SetPoint("TOPRIGHT", self.srcContent, "TOPRIGHT", 0, -y)
			bar.label:SetTextColor(1, 1, 1)
			bar.amount:SetTextColor(1, 1, 1)
			D.PaintRow(bar, data, barH, p)
			bar.row:Show()
			y = y + stride
		end
	end
	paintList(result.rows)

	if result.targets then
		local divY = y + p.barSpacing * 2
		pane.divider:ClearAllPoints()
		pane.divider:SetPoint("TOPLEFT", self.srcContent, "TOPLEFT", 0, -divY)
		pane.divider:SetPoint("TOPRIGHT", self.srcContent, "TOPRIGHT", 0, -divY)
		pane.divider:Show()
		pane.targets:ClearAllPoints()
		pane.targets:SetPoint("TOPLEFT", self.srcContent, "TOPLEFT", 3, -(divY + 4))
		pane.targets:Show()
		y = divY + 18
		paintList(result.targets)
	else
		pane.divider:Hide()
		pane.targets:Hide()
	end

	for i = used + 1, #self.spellRows do
		self.spellRows[i].row:Hide()
		self.spellRows[i].spellID = nil
	end
	self.srcContent:SetHeight(math.max(10, y))
	local viewH = math.max(1, self.srcViewport:GetHeight() or 1)
	self.srcScrollMax = math.max(0, y - viewH)
end

function Window:SetType(key)
	self.view.type = self.dm:ResolveType(key)
	self:DB().type = self.view.type
	self:CloseSource()
	self:SetIcon()
	for _, bar in ipairs(self.rows) do
		bar.cache = nil
	end
	self:Refresh()
	ns.Debug:Log("DamageMeter", "type", self.idx, self.view.type)
end

function Window:SetSession(session, sessionID)
	if sessionID then
		self.view.sessionID = sessionID
	else
		self.view.session = session
		self.view.sessionID = nil
		self:DB().session = session
	end
	self:CloseSource()
	self:Refresh()
	ns.Debug:Log("DamageMeter", "session", self.idx, session or sessionID)
end

function Window:OpenTypeMenu(btn)
	local w = self
	local function wrap(items)
		for _, item in ipairs(items) do
			if item.children then
				wrap(item.children)
			else
				local key = item.key
				item.onClick = function()
					w:SetType(key)
				end
			end
		end
		return items
	end
	Menu:Show(wrap(L.TypeMenu(self.dm.types, self.view.type)), btn, self:Profile().font)
end

function Window:OpenSegmentMenu(btn)
	local w = self
	local items = {}
	for _, seg in ipairs(L.Segments(D.Segments(), L.MAX_SEGMENTS)) do
		table.insert(items, {
			text = seg.label,
			timerText = seg.duration,
			compact = true,
			isActive = w.view.sessionID == seg.sessionID,
			onClick = function()
				w.dm:SelectSegment(w, nil, seg.sessionID)
			end,
		})
	end
	table.insert(items, "---")
	for _, session in ipairs({ "Current", "Overall" }) do
		table.insert(items, {
			text = session,
			isActive = not w.view.sessionID and w.view.session == session,
			onClick = function()
				w.dm:SelectSegment(w, session, nil)
			end,
		})
	end
	Menu:Show(items, btn, self:Profile().font)
end

function Window:OpenSettingsMenu(btn)
	local w = self
	local wdb = self:DB()
	local frame = self.frame
	local function toggle(text, key, after, tip)
		return {
			text = text,
			tooltip = tip,
			isActive = wdb[key] == true,
			onClick = function()
				wdb[key] = not wdb[key]
				if after then
					after()
				end
			end,
		}
	end
	local function rulesChanged()
		w.dm:UpdateVisibility()
	end
	local function setSize(width, height)
		local left, top = frame:GetLeft(), frame:GetTop()
		frame:SetSize(width, height)
		if left then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
		wdb.width = math.floor(frame:GetWidth() + 0.5)
		wdb.height = math.floor(frame:GetHeight() + 0.5)
		w:SavePosition()
	end
	local items = {
		toggle("Hide in Dungeons", "hideInDungeon", rulesChanged),
		toggle("Hide in Raids", "hideInRaid", rulesChanged),
		toggle("Hide in PvP", "hideInPvP", rulesChanged),
		toggle("Hide out of Instances", "hideOutOfInstance", rulesChanged),
		"---",
		{
			text = "Width",
			isInput = true,
			min = MIN_W,
			getValue = function()
				return math.floor(frame:GetWidth() + 0.5)
			end,
			setValue = function(v)
				setSize(math.max(MIN_W, v), frame:GetHeight())
			end,
		},
		{
			text = "Height",
			isInput = true,
			min = MIN_H,
			getValue = function()
				return math.floor(frame:GetHeight() + 0.5)
			end,
			setValue = function(v)
				setSize(frame:GetWidth(), math.max(MIN_H, v))
			end,
		},
		{
			text = wdb.snapDisabled and "Enable Snapping" or "Disable Snapping",
			onClick = function()
				wdb.snapDisabled = not wdb.snapDisabled
			end,
		},
		toggle("Hide Timer", "hideTimer", function()
			w:Layout()
			w:Refresh()
		end),
		toggle(
			"Auto Current on Combat",
			"autoCurrentOnCombat",
			nil,
			"Entering combat switches this window back to Current if viewing a past segment"
		),
		toggle("Sync Segment Selection", "syncSegments", nil, "Selecting a segment switches all synced windows to it"),
		{
			text = "Settings",
			onClick = function()
				ns.OptionsWindow:OpenPage("DamageMeter")
			end,
		},
	}
	Menu:Show(items, btn, self:Profile().font)
end

local function makeCard(parent)
	local card = CreateFrame("Button", nil, parent)
	card:SetHeight(CARD_H)
	card:RegisterForClicks("AnyUp")
	card.bg = card:CreateTexture(nil, "BACKGROUND")
	card.bg:SetAllPoints()
	card.accent = card:CreateTexture(nil, "ARTWORK")
	card.accent:SetWidth(2)
	card.accent:SetPoint("TOPLEFT")
	card.accent:SetPoint("BOTTOMLEFT")
	card.icon = card:CreateTexture(nil, "OVERLAY")
	card.icon:SetSize(CARD_H - 6, CARD_H - 6)
	card.icon:SetPoint("LEFT", card, "LEFT", 6, 0)
	card.label = card:CreateFontString(nil, "OVERLAY")
	card.label:SetPoint("LEFT", card.icon, "RIGHT", 5, 0)
	card.label:SetPoint("RIGHT", card, "RIGHT", -22, 0)
	card.label:SetJustifyH("LEFT")
	card.label:SetWordWrap(false)
	card.arrow = card:CreateTexture(nil, "ARTWORK")
	card.arrow:SetTexture(ns.Media:Icon("arrow"))
	card.arrow:SetSize(14, 14)
	card.arrow:SetPoint("RIGHT", card, "RIGHT", -4, 0)
	return card
end

function Window:BuildHome()
	if self.home then
		return
	end
	local w = self
	local home = CreateFrame("Frame", nil, self.frame)
	home:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT")
	home:SetPoint("BOTTOMRIGHT")
	home:SetFrameLevel(self.frame:GetFrameLevel() + 25)
	home:EnableMouse(true)
	home:Hide()
	home.bg = home:CreateTexture(nil, "BACKGROUND")
	home.bg:SetAllPoints()
	home.bg:SetColorTexture(0.03, 0.03, 0.03, 0.95)
	home:SetScript("OnMouseDown", function(_, button)
		if button == "RightButton" then
			w:HideHome()
		end
	end)
	local scroll = CreateFrame("ScrollFrame", nil, home)
	scroll:SetAllPoints()
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnSizeChanged", function(_, width)
		child:SetWidth(width)
		if width and width > 1 and home:IsShown() then
			w:RefreshHome()
		end
	end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		local value = (scroll:GetVerticalScroll() or 0) - delta * 30
		scroll:SetVerticalScroll(math.max(0, math.min(home.scrollMax or 0, value)))
	end)
	home.scroll = scroll
	home.child = child

	local add = CreateFrame("Button", nil, child)
	add:SetHeight(CARD_H)
	add.bg = add:CreateTexture(nil, "BACKGROUND")
	add.bg:SetAllPoints()
	add.bg:SetColorTexture(0.12, 0.12, 0.12, 0.4)
	add.label = add:CreateFontString(nil, "OVERLAY")
	add.label:SetPoint("CENTER")
	add.label:SetTextColor(1, 1, 1, 0.3)
	add:SetScript("OnEnter", function(owner)
		owner.bg:SetColorTexture(0.16, 0.16, 0.16, 0.56)
		owner.label:SetTextColor(1, 1, 1, 0.5)
	end)
	add:SetScript("OnLeave", function(owner)
		owner.bg:SetColorTexture(0.12, 0.12, 0.12, 0.4)
		owner.label:SetTextColor(1, 1, 1, 0.3)
	end)
	add:SetScript("OnClick", function()
		local items = {}
		for _, key in ipairs(L.AddableTypes(w.dm:Bookmarks(), w.dm.types)) do
			table.insert(items, {
				text = L.TypeLabel(key),
				onClick = function()
					table.insert(w.dm:Bookmarks(true), key)
					w:RefreshHome()
				end,
			})
		end
		Menu:Show(items, nil, w:Profile().font)
	end)
	home.add = add
	self.home = home
end

function Window:RefreshHome()
	local home = self.home
	if not home or not home:IsShown() then
		return
	end
	local w = self
	local p = self:Profile()
	local totalW = home.scroll:GetWidth()
	if not totalW or totalW < 1 then
		return
	end
	local colW = (totalW - CARD_PAD * 2 - CARD_GAP) / 2
	local ar, ag, ab = D.AccentRGB()
	for _, card in ipairs(self.cards) do
		card:Hide()
	end

	local offered = {}
	for _, key in ipairs(self.dm.types) do
		offered[key] = true
	end
	local bookmarks = self.dm:Bookmarks()
	local entries = L.HomeTypes(bookmarks, offered)
	for n, entry in ipairs(entries) do
		local card = self.cards[n]
		if not card then
			card = makeCard(home.child)
			self.cards[n] = card
		end
		local col = (n - 1) % 2
		local row = math.floor((n - 1) / 2)
		card:ClearAllPoints()
		card:SetPoint(
			"TOPLEFT",
			home.child,
			"TOPLEFT",
			CARD_PAD + col * (colW + CARD_GAP),
			-(6 + row * (CARD_H + CARD_GAP))
		)
		card:SetWidth(colW)
		local active = entry.key == self.view.type
		local function paint(hover)
			local v = hover and 0.18 or 0.12
			card.bg:SetColorTexture(v, v, v, hover and 0.98 or 0.8)
			card.label:SetTextColor(1, 1, 1, (active or hover) and 1 or 0.8)
		end
		paint(false)
		setFont(card.label, p, 11)
		card.label:SetText(L.TypeLabel(entry.key))
		card.icon:SetTexture(ns.Media:Icon(L.TypeIcon(entry.key)))
		card.icon:SetVertexColor(ar, ag, ab, active and 1 or 0.6)
		card.accent:SetColorTexture(ar, ag, ab, 1)
		card.accent:SetShown(active)
		card:SetScript("OnEnter", function()
			paint(true)
		end)
		card:SetScript("OnLeave", function()
			paint(false)
		end)
		card:SetScript("OnClick", function(_, button)
			if button == "MiddleButton" then
				table.remove(w.dm:Bookmarks(true), entry.index)
				w:RefreshHome()
			elseif button == "LeftButton" then
				w:HideHome()
				w:SetType(entry.key)
			end
		end)
		card:Show()
	end

	local rowsUsed = math.ceil(#entries / 2)
	local add = home.add
	if #L.AddableTypes(bookmarks, self.dm.types) > 0 then
		setFont(add.label, p, 11)
		add.label:SetText("+  ADD NEW  (middle click to remove)")
		add:ClearAllPoints()
		add:SetPoint("TOPLEFT", home.child, "TOPLEFT", CARD_PAD, -(6 + rowsUsed * (CARD_H + CARD_GAP)))
		add:SetPoint("TOPRIGHT", home.child, "TOPRIGHT", -CARD_PAD, -(6 + rowsUsed * (CARD_H + CARD_GAP)))
		add:Show()
		rowsUsed = rowsUsed + 1
	else
		add:Hide()
	end
	local contentH = 6 + rowsUsed * (CARD_H + CARD_GAP) + 5
	home.child:SetHeight(math.max(10, contentH))
	home.scrollMax = math.max(0, contentH - home.scroll:GetHeight())
end

function Window:ShowHome()
	self:BuildHome()
	Tooltip:Hide()
	self.homeShown = true
	self.viewport:Hide()
	self.sticky.row:Hide()
	self.stickyLine:Hide()
	self.frame.bg:Hide()
	self.home:Show()
	self:RefreshHome()
end

function Window:HideHome()
	local was = self.homeShown
	self.homeShown = false
	if self.home then
		self.home:Hide()
	end
	if not self.sourceOpen then
		self.viewport:Show()
		self.frame.bg:Show()
	end
	if was and not self.sourceOpen and self.session then
		self:Paint(self.session)
	end
end

function Window:ToggleHome()
	if self.homeShown then
		self:HideHome()
	else
		self:ShowHome()
	end
end

function Window:ShouldShow(instType, inCombat, inGroup)
	local dm = self.dm
	local p = self:Profile()
	if not dm:IsEnabled() or dm.toggleHidden then
		return false
	end
	if ns.Mover:IsUnlocked() then
		return true
	end
	if L.InstanceHidden(self:DB(), instType, false) then
		return false
	end
	if p.visibility == "combat" and not inCombat then
		return false
	end
	if p.visibility == "group" and not inGroup then
		return false
	end
	return true
end

function Window:Park()
	self.frame:Hide()
	Tooltip:Hide()
	if self.hoverTicker then
		self.hoverTicker:Cancel()
		self.hoverTicker = nil
	end
	ns.Mover:Unregister(self.frame)
end

function Window:Unpark(idx)
	local dm = self.dm
	self.idx = idx
	local wdb = dm:WindowDB(idx)
	self.view = { session = wdb.session, sessionID = nil, type = dm:ResolveType(wdb.type) }
	self.locked = wdb.locked
	self:CloseSource()
	self:HideHome()
	self:SetIcon()
	ns.Mover:Register(self.frame, "Damage Meter " .. idx, function()
		return dm:WindowDB(self.idx).position
	end)
	self:UpdateLock()
end

ns.Debug:RegisterChecks("DamageMeter", function()
	local dm = ns.addon:GetModule("DamageMeter", true)
	local checks = {}
	if not dm or not dm.windows then
		return checks
	end
	for _, w in ipairs(dm.windows) do
		local label = "window " .. w.idx
		table.insert(checks, {
			name = label,
			run = function()
				if not dm:IsEnabled() then
					return "SKIP", "module disabled"
				end
				local wdb = w:DB()
				local width, height = w.frame:GetWidth(), w.frame:GetHeight()
				if D.IsSecret(width) or D.IsSecret(height) then
					return "INFO", "secret"
				end
				local ok = math.abs(width - math.max(MIN_W, wdb.width)) <= 0.5
					and math.abs(height - math.max(MIN_H, wdb.height)) <= 0.5
				return ok and "PASS" or "FAIL", w.frame:IsShown(), width, height, w.view.type, w.view.session
			end,
		})
		table.insert(checks, {
			name = label .. " rows",
			run = function()
				if not w.frame:IsVisible() then
					return "SKIP", "hidden"
				end
				local shown = 0
				for _, bar in ipairs(w.rows) do
					if bar.row:IsShown() then
						shown = shown + 1
					end
				end
				local expected = math.min(#(w.sources or {}), POOL)
				return (shown == expected) and "PASS" or "FAIL", shown, expected, w.paints, w.pinned or "none"
			end,
		})
		table.insert(checks, {
			name = label .. " title",
			run = function()
				if not w.frame:IsVisible() then
					return "SKIP", "hidden"
				end
				local text = w.title:GetText()
				if D.IsSecret(text) then
					return "INFO", "secret"
				end
				local expected = L.Title(w.view.type, not w.view.sessionID and w.view.session == "Overall")
				local ok = text == expected or (type(text) == "string" and text:sub(-3) == "...")
				return ok and "PASS" or "FAIL", text, expected, w.timer:GetText()
			end,
		})
		table.insert(checks, {
			name = label .. " panes",
			run = function()
				local bad = (w.sourceOpen and w.viewport:IsShown()) or (w.homeShown and w.viewport:IsShown())
				return bad and "FAIL" or "PASS", w.sourceOpen == true, w.homeShown == true, w.locked == true
			end,
		})
	end
	return checks
end)
