local addonName, ns = ...

local L = ns.OptionsLogic
local Theme = ns.Theme
local appName = "MerrinxUI"
local OPTIONS_UI_NAME = "MerrinxUI-1.0"

local CONTENT_W = Theme.geometry.width - Theme.geometry.sidebar
local CONTENT_H = Theme.geometry.height - Theme.geometry.header - Theme.geometry.footer
local LABEL_W = CONTENT_W - 2 * Theme.geometry.pad - Theme.geometry.control - 10

local W = {}
ns.OptionsWindow = W

local frame, sidebarList, contentScroll, contentChild, footerLabel, pageLabel
local dropdownOverlay, dropdownScroll, dropdownChild
local confirmOverlay, confirmDim, confirmMessage

local pools = {}

local root
local pages = {}
local currentPageIndex = 1
local contentScrollOffset = 0
local footerErrorText
local confirmState

local renderBlockers = {}
local focusedEdit
local pendingRenderAfterBlock = false
local renderScheduled = false

local escVariant = "none"
local fontUsed
local windowFont
local configCallbackRegistered = false
local previewFailed = {}

local function isRenderBlocked()
	return next(renderBlockers) ~= nil
end

local function setColor(tex, color)
	tex:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function setTextColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4])
end

-- Forever (A-20) is assumed to ship Fonts\ARIALN.TTF; fall back to the
-- stock FRIZQT font when SetFont reports failure so text stays readable.
local function setFont(fs, size, flags)
	flags = flags or ""
	if windowFont and fs:SetFont(windowFont, size, flags) then
		fontUsed = windowFont
	elseif fs:SetFont(Theme.font, size, flags) then
		fontUsed = Theme.font
	else
		fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags)
		fontUsed = "Fonts\\FRIZQT__.TTF"
	end
end

local function isFontSelect(path)
	return L.Member(root, path, "dialogControl") == "LSM30_Font"
end

local function isStatusbarSelect(path)
	return L.Member(root, path, "dialogControl") == "LSM30_Statusbar"
end

local function setPreviewFont(fs, key)
	local path = ns.Media:Fetch("font", key)
	if path and fs:SetFont(path, Theme.size.value, "") then
		return
	end
	previewFailed[key] = true
	setFont(fs, Theme.size.value)
end

-- RegisterGameMenuEscHandler from addon code taints the Esc chain.
local function installEsc(win)
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "MerrinxUIOptionsFrame")
		escVariant = "special"
		if win.SetDontSavePosition then
			win:SetDontSavePosition(true)
		end
	else
		escVariant = "none"
	end
end

local function newPool(create)
	local free, active = {}, {}
	local pool = {}

	function pool.acquire()
		local item = table.remove(free)
		if not item then
			item = create()
		end
		active[#active + 1] = item
		item:Show()
		return item
	end

	function pool.releaseAll()
		local released = active
		active = {}
		for i = 1, #released do
			local item = released[i]
			item:Hide()
			item:ClearAllPoints()
			free[#free + 1] = item
		end
	end

	return pool
end

local function errorText(err)
	if type(err) == "string" then
		return err
	end
	return "error"
end

local function setFooterError(err)
	footerErrorText = errorText(err)
	if footerLabel then
		footerLabel:SetText(footerErrorText)
	end
end

local function clearFooterError()
	footerErrorText = nil
	if footerLabel then
		footerLabel:SetText("")
	end
end

local function commonInfo(path)
	local okName, name = pcall(L.Value, root, path, "name", appName)
	if not okName or type(name) ~= "string" then
		name = ""
	end
	local okDesc, desc = pcall(L.Value, root, path, "desc", appName)
	if not okDesc or type(desc) ~= "string" then
		desc = nil
	end
	return name, desc
end

local function isRowDisabled(path)
	local ok, disabled = pcall(L.IsDisabled, root, path, appName)
	if not ok then
		return true
	end
	return disabled == true
end

local function applyBase(row, name, desc, disabled)
	row.label:SetText(name)
	if desc then
		row.desc:SetText(desc)
		row.desc:Show()
	else
		row.desc:Hide()
	end
	if disabled then
		row:SetAlpha(Theme.disabledAlpha)
	else
		row:SetAlpha(1)
	end
end

local function displayLabel(v)
	if type(v) == "string" then
		return v
	end
	return ""
end

local requestRender, blockRender, unblockRender
local withConfirm, openConfirm, closeConfirm
local openDropdown, closeDropdown
local renderRow, renderSidebar, renderContentRows, clearContentRows, renderNow, switchToPage

function requestRender()
	if renderScheduled then
		return
	end
	renderScheduled = true
	C_Timer.After(0, function()
		renderScheduled = false
		if not frame or not frame:IsShown() then
			return
		end
		if isRenderBlocked() then
			pendingRenderAfterBlock = true
			return
		end
		renderNow()
	end)
end

function blockRender(widget)
	renderBlockers[widget] = true
end

function unblockRender(widget)
	renderBlockers[widget] = nil
	if not isRenderBlocked() and pendingRenderAfterBlock then
		pendingRenderAfterBlock = false
		requestRender()
	end
end

local function clearRenderBlocks()
	if focusedEdit then
		local edit = focusedEdit
		focusedEdit = nil
		edit:ClearFocus()
	end
	for widget in pairs(renderBlockers) do
		renderBlockers[widget] = nil
	end
	pendingRenderAfterBlock = false
end

local function closeCleanup()
	clearRenderBlocks()
	closeDropdown()
	closeConfirm()
end

local function newRowBase()
	local row = CreateFrame("Frame", nil, contentChild)
	row:SetHeight(Theme.geometry.row)

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	row.bg = bg

	local label = row:CreateFontString(nil, "OVERLAY")
	setFont(label, Theme.size.label)
	label:SetPoint("TOPLEFT", row, "TOPLEFT", Theme.geometry.pad, -4)
	label:SetWidth(LABEL_W)
	label:SetJustifyH("LEFT")
	setTextColor(label, Theme.color.text)
	row.label = label

	local desc = row:CreateFontString(nil, "OVERLAY")
	setFont(desc, Theme.size.desc)
	desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
	desc:SetWidth(LABEL_W)
	desc:SetJustifyH("LEFT")
	setTextColor(desc, Theme.color.textDim)
	row.desc = desc

	return row
end

local function createNavRow()
	local row = CreateFrame("Button", nil, sidebarList)
	row:SetSize(Theme.geometry.sidebar, Theme.geometry.navRow)

	local hoverBg = row:CreateTexture(nil, "BACKGROUND")
	hoverBg:SetAllPoints()
	setColor(hoverBg, Theme.color.hover)
	hoverBg:Hide()
	row.hoverBg = hoverBg

	local activeBar = row:CreateTexture(nil, "ARTWORK")
	activeBar:SetPoint("TOPLEFT")
	activeBar:SetPoint("BOTTOMLEFT")
	activeBar:SetWidth(Theme.geometry.activeBar)
	setColor(activeBar, Theme.color.accent)
	activeBar:Hide()
	row.activeBar = activeBar

	local label = row:CreateFontString(nil, "OVERLAY")
	setFont(label, Theme.size.nav)
	label:SetPoint("LEFT", row, "LEFT", Theme.geometry.pad, 0)
	setTextColor(label, Theme.color.text)
	row.label = label

	row:SetScript("OnEnter", function()
		hoverBg:Show()
	end)
	row:SetScript("OnLeave", function()
		if not row.isActive then
			hoverBg:Hide()
		end
	end)
	row:SetScript("OnClick", function()
		if row.onClick then
			row.onClick()
		end
	end)

	return row
end

local function createToggleRow()
	local row = newRowBase()

	local switch = CreateFrame("Button", nil, row)
	switch:SetSize(Theme.geometry.switchW, Theme.geometry.switchH)
	switch:SetPoint("RIGHT", row, "RIGHT", -Theme.geometry.pad, 0)

	local track = switch:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	switch.track = track

	local knob = switch:CreateTexture(nil, "OVERLAY")
	knob:SetSize(Theme.geometry.knob, Theme.geometry.knob)
	setColor(knob, Theme.color.knob)
	switch.knob = knob

	switch:SetScript("OnClick", function()
		if row.onToggle then
			row.onToggle()
		end
	end)

	row.switch = switch
	return row
end

local function createRangeRow()
	local row = newRowBase()

	local valueText = row:CreateFontString(nil, "OVERLAY")
	setFont(valueText, Theme.size.value)
	valueText:SetPoint("RIGHT", row, "RIGHT", -Theme.geometry.pad, 0)
	valueText:SetWidth(50)
	valueText:SetJustifyH("RIGHT")
	setTextColor(valueText, Theme.color.text)
	row.valueText = valueText

	local slider = CreateFrame("Slider", nil, row)
	slider:SetOrientation("HORIZONTAL")
	slider:SetHeight(Theme.geometry.thumb)
	slider:SetWidth(Theme.geometry.control - 58)
	slider:SetPoint("RIGHT", valueText, "LEFT", -8, 0)
	slider:SetObeyStepOnDrag(true)
	slider:EnableMouseWheel(false)

	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(Theme.geometry.trackH)
	setColor(track, Theme.color.track)

	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(Theme.geometry.thumb, Theme.geometry.thumb)
	setColor(thumb, Theme.color.knob)
	slider:SetThumbTexture(thumb)

	slider:SetScript("OnValueChanged", function(_, v, userInput)
		if row.onValueChanged then
			row.onValueChanged(v, userInput)
		end
	end)
	slider:SetScript("OnMouseDown", function(self)
		blockRender(self)
	end)
	slider:SetScript("OnMouseUp", function(self)
		unblockRender(self)
		requestRender()
	end)

	row.slider = slider
	return row
end

local function createSelectRow()
	local row = newRowBase()

	local button = CreateFrame("Button", nil, row)
	button:SetSize(Theme.geometry.control, Theme.geometry.field)
	button:SetPoint("RIGHT", row, "RIGHT", -Theme.geometry.pad, 0)

	local buttonBg = button:CreateTexture(nil, "BACKGROUND")
	buttonBg:SetAllPoints()
	setColor(buttonBg, Theme.color.field)

	local text = button:CreateFontString(nil, "OVERLAY")
	setFont(text, Theme.size.value)
	text:SetPoint("LEFT", button, "LEFT", 6, 0)
	text:SetJustifyH("LEFT")
	setTextColor(text, Theme.color.text)
	button.text = text

	button:SetScript("OnClick", function()
		if row.onOpen then
			row.onOpen()
		end
	end)

	row.button = button
	return row
end

local function createInputRow()
	local row = newRowBase()

	local edit = CreateFrame("EditBox", nil, row)
	edit:SetAutoFocus(false)
	edit:SetSize(Theme.geometry.control, Theme.geometry.field)
	edit:SetPoint("RIGHT", row, "RIGHT", -Theme.geometry.pad, 0)
	setFont(edit, Theme.size.value)
	edit:SetTextInsets(6, 6, 0, 0)

	local editBg = edit:CreateTexture(nil, "BACKGROUND")
	editBg:SetAllPoints()
	setColor(editBg, Theme.color.field)

	edit:SetScript("OnEnterPressed", function(self)
		row.committing = true
		if row.onSubmit then
			row.onSubmit(self:GetText())
		end
		self:ClearFocus()
	end)
	edit:SetScript("OnEscapePressed", function(self)
		self:SetText(row.originalText or "")
		self:ClearFocus()
	end)
	edit:SetScript("OnEditFocusGained", function(self)
		focusedEdit = self
		blockRender(self)
	end)
	edit:SetScript("OnEditFocusLost", function(self)
		if not row.committing then
			self:SetText(row.originalText or "")
		end
		row.committing = false
		if focusedEdit == self then
			focusedEdit = nil
		end
		unblockRender(self)
	end)

	row.edit = edit
	return row
end

local function createExecuteRow()
	local row = newRowBase()

	local button = CreateFrame("Button", nil, row)
	button:SetSize(Theme.geometry.control, Theme.geometry.field)
	button:SetPoint("RIGHT", row, "RIGHT", -Theme.geometry.pad, 0)

	local buttonBg = button:CreateTexture(nil, "BACKGROUND")
	buttonBg:SetAllPoints()
	setColor(buttonBg, Theme.color.button)

	local text = button:CreateFontString(nil, "OVERLAY")
	setFont(text, Theme.size.value)
	text:SetAllPoints()
	text:SetJustifyH("CENTER")
	setTextColor(text, Theme.color.text)
	button.text = text

	button:SetScript("OnEnter", function()
		setColor(buttonBg, Theme.color.buttonHover)
	end)
	button:SetScript("OnLeave", function()
		setColor(buttonBg, Theme.color.button)
	end)
	button:SetScript("OnClick", function()
		if row.onExecute then
			row.onExecute()
		end
	end)

	row.button = button
	return row
end

local function createDescriptionRow()
	local row = CreateFrame("Frame", nil, contentChild)
	row:SetHeight(Theme.geometry.row)

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	row.bg = bg

	local text = row:CreateFontString(nil, "OVERLAY")
	setFont(text, Theme.size.desc)
	text:SetPoint("TOPLEFT", row, "TOPLEFT", Theme.geometry.pad, 0)
	text:SetWidth(CONTENT_W - 2 * Theme.geometry.pad)
	text:SetJustifyH("LEFT")
	setTextColor(text, Theme.color.textDim)
	row.text = text

	return row
end

local function createSectionRow()
	local row = CreateFrame("Frame", nil, contentChild)
	row:SetHeight(Theme.geometry.row)

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	row.bg = bg

	local text = row:CreateFontString(nil, "OVERLAY")
	setFont(text, Theme.size.section)
	text:SetPoint("TOPLEFT", row, "TOPLEFT", Theme.geometry.pad, 0)
	text:SetWidth(CONTENT_W - 2 * Theme.geometry.pad)
	text:SetJustifyH("LEFT")
	setTextColor(text, Theme.color.section)
	row.text = text

	return row
end

local function createUnsupportedRow()
	local row = CreateFrame("Frame", nil, contentChild)
	row:SetHeight(Theme.geometry.row)

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	row.bg = bg

	local text = row:CreateFontString(nil, "OVERLAY")
	setFont(text, Theme.size.label)
	text:SetPoint("TOPLEFT", row, "TOPLEFT", Theme.geometry.pad, 0)
	text:SetWidth(CONTENT_W - 2 * Theme.geometry.pad)
	text:SetJustifyH("LEFT")
	setTextColor(text, Theme.color.textDim)
	row.text = text

	return row
end

local function createDropItem()
	local item = CreateFrame("Button", nil, dropdownChild)

	local bg = item:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	setColor(bg, Theme.color.button)
	item.bg = bg

	local preview = item:CreateTexture(nil, "ARTWORK")
	preview:SetPoint("TOPLEFT", item, "TOPLEFT", 1, -1)
	preview:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -1, 1)
	preview:SetVertexColor(0.5, 0.5, 0.5)
	preview:Hide()
	item.preview = preview

	local text = item:CreateFontString(nil, "OVERLAY")
	setFont(text, Theme.size.value)
	text:SetPoint("LEFT", item, "LEFT", 6, 0)
	text:SetJustifyH("LEFT")
	setTextColor(text, Theme.color.text)
	item.text = text

	item:SetScript("OnEnter", function()
		setColor(bg, Theme.color.buttonHover)
		preview:SetVertexColor(0.8, 0.8, 0.8)
	end)
	item:SetScript("OnLeave", function()
		setColor(bg, Theme.color.button)
		preview:SetVertexColor(0.5, 0.5, 0.5)
	end)
	item:SetScript("OnClick", function()
		if item.onClick then
			item.onClick()
		end
	end)

	return item
end

local function configureToggle(row, path)
	local name, desc = commonInfo(path)
	local disabled = isRowDisabled(path)
	applyBase(row, name, desc, disabled)

	if disabled then
		row.switch:Disable()
	else
		row.switch:Enable()
	end

	local ok, value = pcall(L.Value, root, path, "get", appName)
	local on = ok and value == true
	setColor(row.switch.track, on and Theme.color.switchOn or Theme.color.switchOff)

	row.switch.knob:ClearAllPoints()
	if on then
		row.switch.knob:SetPoint("RIGHT", row.switch, "RIGHT", -2, 0)
	else
		row.switch.knob:SetPoint("LEFT", row.switch, "LEFT", 2, 0)
	end

	row.onToggle = function()
		local okGet, current = pcall(L.Value, root, path, "get", appName)
		if not okGet then
			setFooterError(current)
			return
		end
		local okSet, err = pcall(L.Value, root, path, "set", appName, not current)
		if okSet then
			clearFooterError()
			requestRender()
		else
			setFooterError(err)
		end
	end
end

local function configureRange(row, path)
	local name, desc = commonInfo(path)
	local disabled = isRowDisabled(path)
	applyBase(row, name, desc, disabled)

	local okMin, min = pcall(L.Value, root, path, "min", appName)
	if not okMin or type(min) ~= "number" then
		min = 0
	end
	local okMax, max = pcall(L.Value, root, path, "max", appName)
	if not okMax or type(max) ~= "number" then
		max = 100
	end
	local okStep, step = pcall(L.Value, root, path, "step", appName)
	if not okStep or type(step) ~= "number" or step <= 0 then
		step = nil
	end

	row.slider:SetMinMaxValues(min, max)
	row.slider:SetValueStep(step or 1)

	if disabled then
		row.slider:Disable()
	else
		row.slider:Enable()
	end

	local ok, value = pcall(L.Value, root, path, "get", appName)
	if not ok or type(value) ~= "number" then
		value = min
	end
	value = L.SnapRange(value, min, max, step)

	row.slider:SetValue(value)
	row.valueText:SetText(L.FormatNumber(value))
	row.path = path
	row.min = min
	row.max = max
	row.step = step
	row.lastValue = value

	row.onValueChanged = function(v, userInput)
		if not userInput then
			return
		end
		local snapped = L.SnapRange(v, row.min, row.max, row.step)
		row.valueText:SetText(L.FormatNumber(snapped))
		if snapped ~= row.lastValue then
			row.lastValue = snapped
			local okSet, err = pcall(L.Value, root, row.path, "set", appName, snapped)
			if okSet then
				clearFooterError()
			else
				setFooterError(err)
			end
		end
	end
end

local function configureSelect(row, path)
	local name, desc = commonInfo(path)
	local disabled = isRowDisabled(path)
	applyBase(row, name, desc, disabled)

	if disabled then
		row.button:Disable()
	else
		row.button:Enable()
	end

	local okValues, values = pcall(L.Value, root, path, "values", appName)
	if not okValues or type(values) ~= "table" then
		values = {}
	end

	local okGet, current = pcall(L.Value, root, path, "get", appName)
	if okGet and current ~= false then
		row.button.text:SetText(displayLabel(values[current]))
	else
		row.button.text:SetText("")
	end

	if okGet and type(current) == "string" and isFontSelect(path) then
		setPreviewFont(row.button.text, current)
	else
		setFont(row.button.text, Theme.size.value)
	end

	row.onOpen = function()
		openDropdown(row.button, path, values)
	end
end

local function configureInput(row, path)
	local name, desc = commonInfo(path)
	local disabled = isRowDisabled(path)
	applyBase(row, name, desc, disabled)

	if disabled then
		row.edit:Disable()
	else
		row.edit:Enable()
	end

	local okGet, value = pcall(L.Value, root, path, "get", appName)
	local text = (okGet and type(value) == "string") and value or ""
	row.originalText = text
	row.committing = false
	row.edit:SetText(text)

	row.onSubmit = function(inputText)
		local usage = L.Member(root, path, "usage")
		local validate = L.Member(root, path, "validate")
		local hasValidate = type(validate) == "function" or type(validate) == "string"
		local valid, msg = true, nil

		if hasValidate then
			local okValidate, resolved = pcall(L.Value, root, path, "validate", appName, inputText)
			if not okValidate then
				setFooterError(resolved)
				return
			end
			valid, msg = L.CheckValidate(resolved, name, usage)
		end

		if not valid then
			setFooterError(msg)
			return
		end

		local okSet, err = pcall(L.Value, root, path, "set", appName, inputText)
		if okSet then
			clearFooterError()
			row.originalText = inputText
			requestRender()
		else
			setFooterError(err)
		end
	end
end

local function configureExecute(row, path)
	local name, desc = commonInfo(path)
	local disabled = isRowDisabled(path)
	applyBase(row, name, desc, disabled)
	row.button.text:SetText(name)

	if disabled then
		row.button:Disable()
	else
		row.button:Enable()
	end

	row.onExecute = function()
		withConfirm(path, nil, function()
			local okFunc, err = pcall(L.Value, root, path, "func", appName)
			if okFunc then
				clearFooterError()
				requestRender()
			else
				setFooterError(err)
			end
		end)
	end
end

local function configureDescription(row, path)
	local name = commonInfo(path)
	row.text:SetText(name)
end

local function configureSection(row, path)
	local name = commonInfo(path)
	row.text:SetText(name)
end

local function configureUnsupported(row, path, kind)
	local name = commonInfo(path)
	local node = L.Node(root, path)
	local optionType = node and node.type or kind
	if type(optionType) ~= "string" then
		optionType = "?"
	end
	row.text:SetText("Unsupported option: " .. name .. " (" .. optionType .. ")")
end

function withConfirm(path, value, action)
	local okConfirm, confirmRaw
	if value == nil then
		okConfirm, confirmRaw = pcall(L.Value, root, path, "confirm", appName)
	else
		okConfirm, confirmRaw = pcall(L.Value, root, path, "confirm", appName, value)
	end
	if not okConfirm then
		setFooterError(confirmRaw)
		return
	end

	local confirmTextRaw = L.Member(root, path, "confirmText")
	if type(confirmTextRaw) ~= "string" then
		confirmTextRaw = nil
	end

	local name, desc = commonInfo(path)
	local needed, text = L.ConfirmText(confirmRaw, confirmTextRaw, name, desc)
	if needed then
		openConfirm(text, action)
	else
		action()
	end
end

function openConfirm(text, action)
	closeDropdown()
	confirmState = { onConfirm = action }
	confirmMessage:SetText(text or "")
	confirmDim:Show()
	confirmOverlay:Show()
end

function closeConfirm()
	confirmState = nil
	if confirmOverlay then
		confirmOverlay:Hide()
	end
	if confirmDim then
		confirmDim:Hide()
	end
end

function openDropdown(anchor, path, values)
	closeDropdown()

	local okKeys, keys = pcall(L.SortedValues, values)
	if not okKeys or type(keys) ~= "table" then
		keys = {}
	end

	local count = #keys
	local visible = math.min(count, Theme.geometry.dropMax)
	if visible < 1 then
		visible = 1
	end
	local listHeight = visible * Theme.geometry.dropItem

	dropdownOverlay:ClearAllPoints()
	dropdownOverlay:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	dropdownOverlay:SetSize(Theme.geometry.control, listHeight)
	dropdownChild:SetSize(Theme.geometry.control, math.max(count, 1) * Theme.geometry.dropItem)
	dropdownScroll:SetVerticalScroll(0)

	local fontList = isFontSelect(path)
	local statusbarList = isStatusbarSelect(path)

	for i, key in ipairs(keys) do
		local item = pools.dropItem.acquire()
		item:SetSize(Theme.geometry.control, Theme.geometry.dropItem)
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", dropdownChild, "TOPLEFT", 0, -(i - 1) * Theme.geometry.dropItem)
		if fontList then
			setPreviewFont(item.text, key)
		else
			setFont(item.text, Theme.size.value)
		end
		item.preview:SetVertexColor(0.5, 0.5, 0.5)
		if statusbarList then
			item.preview:SetTexture(ns.Media:Fetch("statusbar", key))
			item.preview:Show()
		else
			item.preview:Hide()
		end
		item.text:SetText(displayLabel(values[key]))
		item.onClick = function()
			closeDropdown()
			withConfirm(path, key, function()
				local okSet, err = pcall(L.Value, root, path, "set", appName, key)
				if okSet then
					clearFooterError()
				else
					setFooterError(err)
				end
				requestRender()
			end)
		end
	end

	dropdownOverlay:Show()
end

function closeDropdown()
	if dropdownOverlay then
		dropdownOverlay:Hide()
	end
	if pools.dropItem then
		pools.dropItem.releaseAll()
	end
end

function renderRow(rowSpec, offset, visibleIndex)
	local kind = rowSpec.kind
	local path = rowSpec.path
	local row

	if kind == "toggle" then
		row = pools.toggle.acquire()
		configureToggle(row, path)
	elseif kind == "range" then
		row = pools.range.acquire()
		configureRange(row, path)
	elseif kind == "select" then
		row = pools.select.acquire()
		configureSelect(row, path)
	elseif kind == "input" then
		row = pools.input.acquire()
		configureInput(row, path)
	elseif kind == "execute" then
		row = pools.execute.acquire()
		configureExecute(row, path)
	elseif kind == "description" then
		row = pools.description.acquire()
		configureDescription(row, path)
	elseif kind == "section" or kind == "header" then
		row = pools.section.acquire()
		configureSection(row, path)
	else
		row = pools.unsupported.acquire()
		configureUnsupported(row, path, kind)
	end

	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 0, -offset)
	row:SetPoint("TOPRIGHT", contentChild, "TOPRIGHT", 0, -offset)

	if kind == "section" or kind == "header" then
		row.bg:Hide()
	else
		row.bg:Show()
		if visibleIndex % 2 == 1 then
			setColor(row.bg, Theme.color.rowA)
		else
			setColor(row.bg, Theme.color.rowB)
		end
	end
end

function renderSidebar()
	pools.nav.releaseAll()

	local heights = {}
	for i = 1, #pages do
		heights[i] = Theme.geometry.navRow
	end
	local offsets = L.Stack(heights, Theme.geometry.gap)

	for i, page in ipairs(pages) do
		local row = pools.nav.acquire()
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", sidebarList, "TOPLEFT", 0, -offsets[i])
		row:SetPoint("TOPRIGHT", sidebarList, "TOPRIGHT", 0, -offsets[i])
		row.label:SetText(page.label or "")

		local active = i == currentPageIndex
		row.isActive = active
		row.activeBar:SetShown(active)
		row.hoverBg:SetShown(active)
		row.onClick = function()
			switchToPage(i)
		end
	end
end

local function releaseContentRows()
	clearRenderBlocks()
	pools.toggle.releaseAll()
	pools.range.releaseAll()
	pools.select.releaseAll()
	pools.input.releaseAll()
	pools.execute.releaseAll()
	pools.description.releaseAll()
	pools.section.releaseAll()
	pools.unsupported.releaseAll()
	closeDropdown()
end

function renderContentRows(page)
	local okRows, rowList = pcall(L.Flatten, root, page.path, appName, page.leavesOnly)
	if not okRows or type(rowList) ~= "table" then
		setFooterError(rowList)
		rowList = {}
	end

	releaseContentRows()

	local heights = {}
	for i = 1, #rowList do
		heights[i] = Theme.geometry.row
	end
	local offsets, total = L.Stack(heights, Theme.geometry.gap)
	contentChild:SetHeight(math.max(total, CONTENT_H))

	for i, rowSpec in ipairs(rowList) do
		local ok, err = pcall(renderRow, rowSpec, offsets[i], i)
		if not ok then
			setFooterError(err)
		end
	end

	local maxOffset = math.max(0, total - CONTENT_H)
	if contentScrollOffset > maxOffset then
		contentScrollOffset = maxOffset
	end
	contentScroll:SetVerticalScroll(contentScrollOffset)
end

function clearContentRows()
	releaseContentRows()

	contentChild:SetHeight(CONTENT_H)
	contentScrollOffset = 0
	contentScroll:SetVerticalScroll(0)
end

function renderNow()
	if not frame then
		return
	end

	local okRoot, result = pcall(function()
		return LibStub("AceConfigRegistry-3.0"):GetOptionsTable(appName, "dialog", OPTIONS_UI_NAME)
	end)
	if not okRoot or type(result) ~= "table" then
		setFooterError(result)
		return
	end
	root = result

	local okPages, newPages = pcall(L.Pages, root, appName)
	if not okPages or type(newPages) ~= "table" then
		setFooterError(newPages)
		newPages = {}
	end
	pages = newPages

	if currentPageIndex > #pages or currentPageIndex < 1 then
		currentPageIndex = 1
	end

	renderSidebar()

	local page = pages[currentPageIndex]
	if page then
		pageLabel:SetText(page.label or "")
		renderContentRows(page)
	else
		pageLabel:SetText("")
		clearContentRows()
	end
end

function switchToPage(index)
	if index == currentPageIndex then
		return
	end
	currentPageIndex = index
	contentScrollOffset = 0
	closeDropdown()
	closeConfirm()
	clearFooterError()
	renderNow()
end

local function buildHeader(win)
	local header = CreateFrame("Frame", nil, win)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(Theme.geometry.header)
	header:EnableMouse(true)

	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	setColor(headerBg, Theme.color.header)

	header:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			win:StartMoving()
		end
	end)
	header:SetScript("OnMouseUp", function()
		win:StopMovingOrSizing()
	end)

	local titleLabel = header:CreateFontString(nil, "OVERLAY")
	setFont(titleLabel, Theme.size.title)
	titleLabel:SetPoint("LEFT", header, "LEFT", Theme.geometry.pad, 0)
	titleLabel:SetText("MerrinxUI")
	setTextColor(titleLabel, Theme.color.accent)

	pageLabel = header:CreateFontString(nil, "OVERLAY")
	setFont(pageLabel, Theme.size.label)
	pageLabel:SetPoint("LEFT", titleLabel, "RIGHT", 10, 0)
	setTextColor(pageLabel, Theme.color.textDim)

	local closeButton = CreateFrame("Button", nil, header)
	closeButton:SetSize(28, 28)
	closeButton:SetPoint("RIGHT", header, "RIGHT", -Theme.geometry.pad, 0)

	local closeLabel = closeButton:CreateFontString(nil, "OVERLAY")
	setFont(closeLabel, Theme.size.title)
	closeLabel:SetAllPoints()
	closeLabel:SetJustifyH("CENTER")
	closeLabel:SetText("x")
	setTextColor(closeLabel, Theme.color.text)

	closeButton:SetScript("OnClick", function()
		W:Close()
	end)
end

local function buildSidebar(win)
	sidebarList = CreateFrame("Frame", nil, win)
	sidebarList:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -Theme.geometry.header)
	sidebarList:SetSize(Theme.geometry.sidebar, CONTENT_H)

	local sidebarBg = sidebarList:CreateTexture(nil, "BACKGROUND")
	sidebarBg:SetAllPoints()
	setColor(sidebarBg, Theme.color.sidebar)

	pools.nav = newPool(createNavRow)
end

local function buildContent(win)
	contentScroll = CreateFrame("ScrollFrame", nil, win)
	contentScroll:SetPoint("TOPLEFT", sidebarList, "TOPRIGHT", 0, 0)
	contentScroll:SetSize(CONTENT_W, CONTENT_H)
	contentScroll:EnableMouseWheel(true)

	contentChild = CreateFrame("Frame", nil, contentScroll)
	contentChild:SetSize(CONTENT_W, CONTENT_H)
	contentScroll:SetScrollChild(contentChild)

	contentScroll:SetScript("OnMouseWheel", function(_, delta)
		local offset =
			L.Scroll(contentScrollOffset, delta, Theme.geometry.scrollStep, contentChild:GetHeight(), CONTENT_H)
		contentScrollOffset = offset
		contentScroll:SetVerticalScroll(offset)
	end)

	pools.toggle = newPool(createToggleRow)
	pools.range = newPool(createRangeRow)
	pools.select = newPool(createSelectRow)
	pools.input = newPool(createInputRow)
	pools.execute = newPool(createExecuteRow)
	pools.description = newPool(createDescriptionRow)
	pools.section = newPool(createSectionRow)
	pools.unsupported = newPool(createUnsupportedRow)
end

local function buildFooter(win)
	local footerFrame = CreateFrame("Frame", nil, win)
	footerFrame:SetPoint("BOTTOMLEFT")
	footerFrame:SetPoint("BOTTOMRIGHT")
	footerFrame:SetHeight(Theme.geometry.footer)

	local footerBg = footerFrame:CreateTexture(nil, "BACKGROUND")
	footerBg:SetAllPoints()
	setColor(footerBg, Theme.color.header)

	footerLabel = footerFrame:CreateFontString(nil, "OVERLAY")
	setFont(footerLabel, Theme.size.desc)
	footerLabel:SetPoint("LEFT", footerFrame, "LEFT", Theme.geometry.pad, 0)
	setTextColor(footerLabel, Theme.color.error)
end

local function buildDropdown(win)
	dropdownOverlay = CreateFrame("Frame", nil, win)
	dropdownOverlay:SetFrameLevel(win:GetFrameLevel() + 20)
	dropdownOverlay:Hide()

	local dropdownBg = dropdownOverlay:CreateTexture(nil, "BACKGROUND")
	dropdownBg:SetAllPoints()
	setColor(dropdownBg, Theme.color.field)

	dropdownScroll = CreateFrame("ScrollFrame", nil, dropdownOverlay)
	dropdownScroll:SetAllPoints()
	dropdownScroll:EnableMouseWheel(true)
	dropdownScroll:SetScript("OnMouseWheel", function(_, delta)
		local offset = dropdownScroll:GetVerticalScroll()
		local newOffset =
			L.Scroll(offset, delta, Theme.geometry.dropItem, dropdownChild:GetHeight(), dropdownScroll:GetHeight())
		dropdownScroll:SetVerticalScroll(newOffset)
	end)

	dropdownChild = CreateFrame("Frame", nil, dropdownScroll)
	dropdownScroll:SetScrollChild(dropdownChild)

	pools.dropItem = newPool(createDropItem)
end

local function createDialogButton(parent, xOffset, text, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(100, 28)
	button:SetPoint("BOTTOM", parent, "BOTTOM", xOffset, 16)

	local buttonBg = button:CreateTexture(nil, "BACKGROUND")
	buttonBg:SetAllPoints()
	setColor(buttonBg, Theme.color.button)

	local label = button:CreateFontString(nil, "OVERLAY")
	setFont(label, Theme.size.value)
	label:SetAllPoints()
	label:SetJustifyH("CENTER")
	label:SetText(text)
	setTextColor(label, Theme.color.text)

	button:SetScript("OnEnter", function()
		setColor(buttonBg, Theme.color.buttonHover)
	end)
	button:SetScript("OnLeave", function()
		setColor(buttonBg, Theme.color.button)
	end)
	button:SetScript("OnClick", onClick)

	return button
end

local function buildConfirm(win)
	confirmDim = CreateFrame("Frame", nil, win)
	confirmDim:SetAllPoints()
	confirmDim:SetFrameLevel(win:GetFrameLevel() + 29)
	confirmDim:EnableMouse(true)
	confirmDim:EnableMouseWheel(true)
	confirmDim:SetScript("OnMouseWheel", function() end)
	confirmDim:Hide()

	local dimTex = confirmDim:CreateTexture(nil, "BACKGROUND")
	dimTex:SetAllPoints()
	setColor(dimTex, Theme.color.overlay)

	confirmOverlay = CreateFrame("Frame", nil, win)
	confirmOverlay:SetSize(Theme.geometry.confirmW, Theme.geometry.confirmH)
	confirmOverlay:SetPoint("CENTER")
	confirmOverlay:SetFrameLevel(win:GetFrameLevel() + 30)
	confirmOverlay:Hide()

	local confirmBg = confirmOverlay:CreateTexture(nil, "BACKGROUND")
	confirmBg:SetAllPoints()
	setColor(confirmBg, Theme.color.header)

	confirmMessage = confirmOverlay:CreateFontString(nil, "OVERLAY")
	setFont(confirmMessage, Theme.size.desc)
	confirmMessage:SetPoint("TOP", confirmOverlay, "TOP", 0, -16)
	confirmMessage:SetWidth(Theme.geometry.confirmW - 32)
	confirmMessage:SetJustifyH("CENTER")
	setTextColor(confirmMessage, Theme.color.textDim)

	createDialogButton(confirmOverlay, 60, "Confirm", function()
		local action = confirmState and confirmState.onConfirm
		closeConfirm()
		if action then
			action()
		end
	end)

	createDialogButton(confirmOverlay, -60, "Cancel", function()
		closeConfirm()
	end)
end

local function build()
	windowFont = ns.Media:FontPath(ns.Media.db.profile.optionsFont)

	frame = CreateFrame("Frame", "MerrinxUIOptionsFrame", UIParent)
	frame:SetSize(Theme.geometry.width, Theme.geometry.height)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetScript("OnHide", closeCleanup)
	frame:Hide()

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	setColor(bg, Theme.color.bg)

	buildHeader(frame)
	buildSidebar(frame)
	buildContent(frame)
	buildFooter(frame)
	buildDropdown(frame)
	buildConfirm(frame)

	installEsc(frame)

	LibStub("AceConfigRegistry-3.0").RegisterCallback(W, "ConfigTableChange", "OnConfigTableChange")
	configCallbackRegistered = true
end

function W:Open()
	if not frame then
		build()
	end
	frame:Show()
	frame:Raise()
	closeDropdown()
	closeConfirm()
	renderNow()
end

function W:Close()
	if frame then
		frame:Hide()
	end
end

function W:IsShown()
	return frame ~= nil and frame:IsShown() == true
end

function W:OnConfigTableChange(_, changedAppName)
	if changedAppName == appName and frame and frame:IsShown() then
		requestRender()
	end
end

ns.Debug:RegisterChecks("OptionsWindow", function()
	return {
		{
			name = "built",
			run = function()
				return "INFO", frame ~= nil
			end,
		},
		{
			name = "esc",
			run = function()
				if not frame then
					return "SKIP", "not built"
				end
				if escVariant == "special" then
					return "PASS"
				end
				return "FAIL", "esc unavailable"
			end,
		},
		{
			name = "font",
			run = function()
				if not frame then
					return "SKIP", "not built"
				end
				if fontUsed == windowFont then
					return "PASS", fontUsed, windowFont
				end
				return "INFO", "fallback", fontUsed, windowFont
			end,
		},
		{
			name = "font preview",
			run = function()
				local failed = {}
				for key in pairs(previewFailed) do
					failed[#failed + 1] = key
				end
				table.sort(failed)
				return "INFO", #failed, unpack(failed, 1, #failed)
			end,
		},
		{
			name = "config callback",
			run = function()
				if not frame then
					return "SKIP", "not built"
				end
				return configCallbackRegistered and "PASS" or "FAIL"
			end,
		},
		{
			name = "pages",
			run = function()
				local label
				if pages[currentPageIndex] then
					label = pages[currentPageIndex].label
				end
				return "INFO", #pages, label
			end,
		},
		{
			name = "shown",
			run = function()
				return "INFO", frame ~= nil and frame:IsShown() == true
			end,
		},
	}
end)
