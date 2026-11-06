local addonName, ns = ...

local Accent = ns.Theme.color.accent

local ITEM_H = 22
local HEADER_H = 20
local SEP_H = 7
local MIN_W = 100
local FONT_SIZE = 11
local HL_ALPHA = 0.08

local Menu = {}
ns.DamageMeterMenu = Menu

local root, sub, anchor, fontKey

local function setFont(fs, size)
	ns.Media:SetFont(fs, fontKey or "Arial Narrow", size or FONT_SIZE, "")
end

local function makePanel(level)
	local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetFrameLevel(200 + level * 10)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	f:SetBackdropColor(0.067, 0.067, 0.067, 0.95)
	f:SetBackdropBorderColor(1, 1, 1, 0.18)
	f.pool = {}
	f:Hide()
	return f
end

local function ensureRow(menu, i)
	local row = menu.pool[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, menu)
	row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.hl:SetAllPoints()
	row.label = row:CreateFontString(nil, "OVERLAY")
	row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.arrow = row:CreateTexture(nil, "ARTWORK")
	row.arrow:SetTexture(ns.Media:Icon("arrow"))
	row.arrow:SetSize(14, 14)
	row.arrow:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.timer = row:CreateFontString(nil, "OVERLAY")
	row.timer:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.timer:SetJustifyH("RIGHT")
	row.sep = row:CreateTexture(nil, "ARTWORK")
	row.sep:SetHeight(1)
	row.sep:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.sep:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.sep:SetColorTexture(1, 1, 1, 0.12)

	local box = CreateFrame("EditBox", nil, row)
	box:SetSize(50, 18)
	box:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(5)
	box:SetJustifyH("CENTER")
	box:SetTextColor(1, 1, 1, 0.9)
	local boxBg = box:CreateTexture(nil, "BACKGROUND")
	boxBg:SetAllPoints()
	boxBg:SetColorTexture(0, 0, 0, 0.4)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	row.box = box

	menu.pool[i] = row
	return row
end

local function showTip(owner, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(text, 1, 1, 1, 1, true)
	GameTooltip:Show()
end

local function itemWidth(menu, items)
	if not menu.measure then
		menu.measure = menu:CreateFontString(nil, "OVERLAY")
		menu.measure:Hide()
	end
	setFont(menu.measure)
	local maxW = 0
	for _, item in ipairs(items) do
		if type(item) == "table" and item.text then
			menu.measure:SetText(item.text .. (item.timerText and ("  " .. item.timerText) or ""))
			maxW = math.max(maxW, menu.measure:GetStringWidth() or 0)
		end
	end
	return math.max(MIN_W, maxW + (items.hasInput and 80 or 50))
end

local layout

local function openChild(row, item, dismiss)
	sub = sub or makePanel(1)
	layout(sub, item.children, dismiss, true)
	sub:ClearAllPoints()
	local right = row:GetRight()
	if right and (right + sub:GetWidth()) > (UIParent:GetRight() or 0) then
		sub:SetPoint("TOPRIGHT", row, "TOPLEFT", 0, 0)
	else
		sub:SetPoint("TOPLEFT", row, "TOPRIGHT", 0, 0)
	end
	sub:Show()
end

function layout(menu, items, dismiss, isChild)
	for _, row in ipairs(menu.pool) do
		row:Hide()
	end
	for _, item in ipairs(items) do
		if type(item) == "table" and item.isInput then
			items.hasInput = true
		end
	end
	local w = itemWidth(menu, items)
	local y = 0
	for i, item in ipairs(items) do
		local row = ensureRow(menu, i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -y)
		row.sep:Hide()
		row.arrow:Hide()
		row.box:Hide()
		row.timer:SetText("")
		row.hl:SetColorTexture(1, 1, 1, 0)
		row:SetScript("OnEnter", nil)
		row:SetScript("OnLeave", nil)
		row:SetScript("OnClick", nil)
		setFont(row.label)
		setFont(row.timer)
		setFont(row.box, 10)
		row.label:SetPoint("RIGHT", row, "RIGHT", -18, 0)

		local h
		if item == "---" then
			h = SEP_H
			row.label:SetText("")
			row.sep:Show()
			row:EnableMouse(false)
		elseif item.isHeader then
			h = HEADER_H
			row.label:SetText(item.text)
			row.label:SetTextColor(1, 0.82, 0, 1)
			row:EnableMouse(false)
		elseif item.isInput then
			h = ITEM_H
			row.label:SetText(item.text)
			row.label:SetTextColor(1, 1, 1, 1)
			row:EnableMouse(false)
			row.box:Show()
			row.box:SetNumber(item.getValue and item.getValue() or 0)
			row.box:SetScript("OnEnterPressed", function(self)
				local value = math.max(item.min or 1, math.floor(self:GetNumber() + 0.5))
				self:SetNumber(value)
				if item.setValue then
					item.setValue(value)
				end
				self:ClearFocus()
			end)
		else
			h = item.compact and (ITEM_H - 2) or ITEM_H
			row.label:SetText(item.text or "")
			row:EnableMouse(true)
			if item.timerText then
				row.timer:SetText(item.timerText)
				row.timer:SetTextColor(Accent[1], Accent[2], Accent[3], 0.9)
				row.label:SetPoint("RIGHT", row.timer, "LEFT", -6, 0)
			end
			local disabled = item.isDisabled and item.isDisabled()
			if item.children then
				row.arrow:SetVertexColor(1, 1, 1, disabled and 0.2 or 0.75)
				row.arrow:Show()
			end
			if disabled then
				row.label:SetTextColor(0.4, 0.4, 0.4, 0.5)
				row:SetScript("OnEnter", function()
					if not isChild and sub then
						sub:Hide()
					end
				end)
			else
				local active = item.isActive
				local function paint(hover)
					if active or hover then
						row.label:SetTextColor(Accent[1], Accent[2], Accent[3], 1)
						row.hl:SetColorTexture(1, 1, 1, HL_ALPHA)
					else
						row.label:SetTextColor(1, 1, 1, 1)
						row.hl:SetColorTexture(1, 1, 1, 0)
					end
				end
				paint(false)
				row:SetScript("OnEnter", function(self)
					paint(true)
					if item.tooltip then
						showTip(self, item.tooltip)
					end
					if item.children then
						openChild(self, item, dismiss)
					elseif not isChild and sub then
						sub:Hide()
					end
				end)
				row:SetScript("OnLeave", function()
					GameTooltip:Hide()
					paint(false)
				end)
				row:SetScript("OnClick", function()
					if item.children then
						return
					end
					if item.onClick then
						item.onClick()
					end
					dismiss()
				end)
			end
		end
		row:SetSize(w, h)
		row:Show()
		y = y + h
	end
	menu:SetSize(w, y)
end

local function ensureRoot()
	if root then
		return
	end
	root = makePanel(0)
	local acc = 0
	root:SetScript("OnUpdate", function(self, dt)
		acc = acc + dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local over = self:IsMouseOver()
			or (sub and sub:IsShown() and sub:IsMouseOver())
			or (anchor and anchor:IsMouseOver())
		if not over and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
			self:Hide()
		end
	end)
	root:SetScript("OnHide", function()
		if sub then
			sub:Hide()
		end
		anchor = nil
		GameTooltip:Hide()
	end)
	root:RegisterEvent("PLAYER_REGEN_DISABLED")
	root:SetScript("OnEvent", function(self)
		self:Hide()
	end)
end

-- anchorFrame nil opens at the cursor; the same anchor clicked again closes.
function Menu:Show(items, anchorFrame, font)
	ensureRoot()
	if anchorFrame and root:IsShown() and anchor == anchorFrame then
		root:Hide()
		return
	end
	fontKey = font
	local function dismiss()
		root:Hide()
	end
	layout(root, items, dismiss, false)
	root:ClearAllPoints()
	if anchorFrame then
		root:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
	else
		local scale = root:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
	end
	anchor = anchorFrame
	root:Show()
end

function Menu:Hide()
	if root then
		root:Hide()
	end
end

function Menu:IsOpenFor(anchorFrame)
	return root ~= nil and root:IsShown() and anchor == anchorFrame
end

ns.Debug:RegisterChecks("DamageMeter", function()
	return {
		{
			name = "menu",
			run = function(ctx)
				local shown = root ~= nil and root:IsShown()
				if shown and ctx.inCombat then
					return "FAIL", "open in combat"
				end
				return "INFO", root ~= nil, shown, root and #root.pool or 0
			end,
		},
	}
end)
