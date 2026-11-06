local addonName, ns = ...

local D = ns.DamageMeterData
local TEXTURE = "Interface\\Buttons\\WHITE8X8"

local WIDTH = 260
local HEADER_H = 22
local ROW_H = 16
local ROW_GAP = 1
local SPELL_GREY = { 0x33 / 255, 0x33 / 255, 0x33 / 255 }

local Tooltip = {}
ns.DamageMeterTooltip = Tooltip

local frame, rows, targetRows = nil, {}, {}
local stats = { shown = 0, lastRows = 0 }

local function newRow(parent)
	local bar = {}
	bar.row = CreateFrame("Frame", nil, parent)
	bar.row:SetHeight(ROW_H)
	bar.icon = bar.row:CreateTexture(nil, "ARTWORK")
	bar.icon:SetPoint("LEFT", bar.row, "LEFT", 0, 0)
	bar.fill = CreateFrame("StatusBar", nil, bar.row)
	bar.fill:SetStatusBarTexture(TEXTURE)
	local text = CreateFrame("Frame", nil, bar.fill)
	text:SetAllPoints(bar.fill)
	text:SetFrameLevel(bar.fill:GetFrameLevel() + 2)
	bar.label = text:CreateFontString(nil, "OVERLAY")
	bar.label:SetPoint("LEFT", text, "LEFT", 3, 0)
	bar.label:SetJustifyH("LEFT")
	bar.label:SetWordWrap(false)
	bar.amount = text:CreateFontString(nil, "OVERLAY")
	bar.amount:SetPoint("RIGHT", text, "RIGHT", -3, 0)
	bar.amount:SetJustifyH("RIGHT")
	bar.label:SetPoint("RIGHT", bar.amount, "LEFT", -4, 0)
	bar.row:Hide()
	return bar
end

local function ensureFrame()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "MerrinxUIDamageMeterTooltip", UIParent)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	frame.header = frame:CreateTexture(nil, "BORDER")
	frame.header:SetPoint("TOPLEFT")
	frame.header:SetPoint("TOPRIGHT")
	frame.header:SetHeight(HEADER_H)
	frame.title = frame:CreateFontString(nil, "OVERLAY")
	frame.title:SetPoint("LEFT", frame, "TOPLEFT", 6, -HEADER_H / 2)
	frame.title:SetPoint("RIGHT", frame, "TOPRIGHT", -6, -HEADER_H / 2)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)
	frame.message = frame:CreateFontString(nil, "OVERLAY")
	frame.message:SetPoint("TOP", frame, "TOP", 0, -HEADER_H - 8)
	frame.message:SetTextColor(1, 1, 1, 0.7)
	frame.divider = frame:CreateTexture(nil, "ARTWORK")
	frame.divider:SetHeight(1)
	frame.divider:SetColorTexture(1, 1, 1, 0.15)
	frame.targetsLabel = frame:CreateFontString(nil, "OVERLAY")
	frame.targetsLabel:SetTextColor(0.6, 0.6, 0.6, 1)
end

local function rowAt(list, i)
	local bar = list[i]
	if not bar then
		bar = newRow(frame)
		list[i] = bar
	end
	return bar
end

local function style(profile)
	local font = profile.font
	ns.Media:SetFont(frame.title, font, profile.hdrFontSize, "")
	ns.Media:SetFont(frame.message, font, profile.leftFontSize, "")
	ns.Media:SetFont(frame.targetsLabel, font, math.max(8, profile.leftFontSize - 2), "")
	frame.targetsLabel:SetText("Targets")
	frame.bg:SetColorTexture(0, 0, 0, profile.breakdownBgOpacity / 100)
	local hr, hg, hb = ns.DamageMeterLogic.ParseHex(profile.hdrColor)
	frame.header:SetColorTexture(hr or 0.1, hg or 0.1, hb or 0.1, profile.hdrOpacity / 100)
	local tr, tg, tb = ns.DamageMeterLogic.ParseHex(profile.hdrTextColor)
	if profile.hdrTextUseAccent or not tr then
		tr, tg, tb = D.AccentRGB()
	end
	frame.title:SetTextColor(tr, tg, tb, 1)
	frame:SetScale(profile.hoverScale / 100)
end

local function paintList(list, data, y, profile, colorOverride)
	local texture = ns.Media:Fetch(
		"statusbar",
		profile.breakdownTexture == "match" and profile.barTexture or profile.breakdownTexture
	) or TEXTURE
	for i, rowData in ipairs(data or {}) do
		local bar = rowAt(list, i)
		bar.row:ClearAllPoints()
		bar.row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
		bar.row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
		bar.fill:SetStatusBarTexture(texture)
		ns.Media:SetFont(bar.label, profile.font, math.max(8, profile.leftFontSize - 1), "")
		ns.Media:SetFont(bar.amount, profile.font, math.max(8, profile.rightFontSize - 1), "")
		bar.label:SetTextColor(1, 1, 1)
		bar.amount:SetTextColor(1, 1, 1)
		D.PaintRow(bar, rowData, ROW_H, profile, colorOverride)
		bar.row:Show()
		y = y + ROW_H + ROW_GAP
	end
	for i = #(data or {}) + 1, #list do
		list[i].row:Hide()
	end
	return y
end

local function anchorTo(rowFrame, winFrame, mode)
	frame:ClearAllPoints()
	if mode == "center" then
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	elseif mode == "left" and winFrame then
		frame:SetPoint("TOPRIGHT", winFrame, "TOPLEFT", -6, 0)
	elseif mode == "right" and winFrame then
		frame:SetPoint("TOPLEFT", winFrame, "TOPRIGHT", 6, 0)
	else
		frame:SetPoint("BOTTOMRIGHT", rowFrame, "TOPRIGHT", 0, 0)
	end
end

-- view: the window's { session, sessionID, type }; src: the hovered source.
function Tooltip:Show(rowFrame, winFrame, view, src, profile)
	if not profile.showHoverTooltip or not src then
		return
	end
	ensureFrame()
	style(profile)

	local result = D.Breakdown(view, src, profile, profile.moreSpells and 15 or 8)
	local title = result.title
	frame.title:SetFormattedText(title[1], title[2], title[3])

	local y = HEADER_H
	local spellColor = view.type ~= "Deaths" and view.type ~= "EnemyDamageTaken" and SPELL_GREY or nil
	if result.message then
		frame.message:SetText(result.message)
		frame.message:Show()
		y = paintList(rows, nil, y, profile) + 40
	else
		frame.message:Hide()
		y = paintList(rows, result.rows, y, profile, spellColor)
	end

	if result.targets then
		local divY = y + 2
		frame.divider:ClearAllPoints()
		frame.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -divY)
		frame.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -divY)
		frame.divider:Show()
		frame.targetsLabel:ClearAllPoints()
		frame.targetsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -(divY + 4))
		frame.targetsLabel:Show()
		y = paintList(targetRows, result.targets, divY + 16, profile)
	else
		frame.divider:Hide()
		frame.targetsLabel:Hide()
		paintList(targetRows, nil, 0, profile)
	end

	frame:SetSize(WIDTH, y)
	anchorTo(rowFrame, winFrame, profile.breakdownAnchor)
	frame:Show()
	stats.shown = stats.shown + 1
	stats.lastRows = #(result.rows or {})
end

function Tooltip:Hide()
	if frame then
		frame:Hide()
	end
end

ns.Debug:RegisterChecks("DamageMeter", function()
	return {
		{
			name = "hover breakdown",
			run = function()
				return "INFO", frame ~= nil, frame ~= nil and frame:IsShown(), stats.shown, stats.lastRows
			end,
		},
	}
end)
