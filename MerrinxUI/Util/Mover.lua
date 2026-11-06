local addonName, ns = ...

local MoverLogic = ns.MoverLogic

local Mover = {}
ns.Mover = Mover

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local GRID = 32
local SNAP = 6
local DRAG_START = 3

local isUnlocked = false
local entries = {} -- frame -> { frame, label, getPosition, onMoved, overlay, coords, dragging, hovered }
local active, selected
local grid, guides, editor

local function accent()
	local c = ns.Theme.color.accent
	return c[1], c[2], c[3]
end

local function cursor()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	return x / scale, y / scale
end

-- The overlay is a UIParent child, so a scaled frame needs its size converted.
local function visualSize(frame)
	local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return frame:GetWidth() * ratio, frame:GetHeight() * ratio
end

local function offsetOf(entry)
	local cx, cy = entry.overlay:GetCenter()
	if not cx then
		return nil
	end
	local frameScale = entry.frame:GetEffectiveScale()
	local overlayScale = entry.overlay:GetEffectiveScale()
	cx = cx * overlayScale / frameScale
	cy = cy * overlayScale / frameScale
	return MoverLogic.CenterOffset(
		cx,
		cy,
		frameScale,
		UIParent:GetWidth(),
		UIParent:GetHeight(),
		UIParent:GetEffectiveScale()
	)
end

local function savePosition(entry)
	local x, y = offsetOf(entry)
	if not x then
		return
	end
	local pos = entry.getPosition()
	pos.point = pos.point or "CENTER"
	pos.x = x
	pos.y = y
end

local function vline(tex, parent, x)
	tex:ClearAllPoints()
	tex:SetPoint("TOP", parent, "TOPLEFT", x, 0)
	tex:SetPoint("BOTTOM", parent, "BOTTOMLEFT", x, 0)
	tex:SetWidth(1)
end

local function hline(tex, parent, y)
	tex:ClearAllPoints()
	tex:SetPoint("LEFT", parent, "BOTTOMLEFT", 0, y)
	tex:SetPoint("RIGHT", parent, "BOTTOMRIGHT", 0, y)
	tex:SetHeight(1)
end

local function showGrid()
	if not grid then
		grid = CreateFrame("Frame", nil, UIParent)
		grid:SetFrameStrata("BACKGROUND")
		grid:SetAllPoints(UIParent)
		grid.lines = {}
	end
	for _, tex in ipairs(grid.lines) do
		tex:Hide()
	end
	local r, g, b = accent()
	local n = 0
	local function draw(place, pos, isCenter)
		n = n + 1
		local tex = grid.lines[n]
		if not tex then
			tex = grid:CreateTexture(nil, "BACKGROUND")
			grid.lines[n] = tex
		end
		place(tex, grid, pos)
		if isCenter then
			tex:SetColorTexture(r, g, b, 0.6)
		else
			tex:SetColorTexture(1, 1, 1, 0.12)
		end
		tex:Show()
	end
	for i, x in ipairs(MoverLogic.GridLines(UIParent:GetWidth(), GRID)) do
		draw(vline, x, i == 1)
	end
	for i, y in ipairs(MoverLogic.GridLines(UIParent:GetHeight(), GRID)) do
		draw(hline, y, i == 1)
	end
	grid:Show()
end

local function showGuides(gx, gy)
	if not guides then
		guides = CreateFrame("Frame", nil, UIParent)
		guides:SetFrameStrata("FULLSCREEN_DIALOG")
		guides:SetAllPoints(UIParent)
		guides.x = guides:CreateTexture(nil, "OVERLAY")
		guides.y = guides:CreateTexture(nil, "OVERLAY")
	end
	local r, g, b = accent()
	for axis, at in pairs({ x = gx, y = gy }) do
		local tex = guides[axis]
		tex:SetColorTexture(r, g, b, 0.9)
		if axis == "x" then
			vline(tex, guides, at)
		else
			hline(tex, guides, at)
		end
		tex:Show()
	end
	guides.x:SetShown(gx ~= nil)
	guides.y:SetShown(gy ~= nil)
	guides:Show()
end

local function hideGuides()
	if guides then
		guides:Hide()
	end
end

local function round(v)
	return math.floor((v or 0) + 0.5)
end

local function fillEditor()
	if not editor or not selected then
		return
	end
	local pos = selected.getPosition()
	for _, box in ipairs(editor.boxes) do
		if not box:HasFocus() then
			box:SetText(tostring(round(pos[box.axis])))
		end
	end
end

local function updateCoords(entry)
	if entry.dragging then
		return
	end
	if entry.hovered or selected == entry then
		local pos = entry.getPosition()
		entry.coords:SetText(MoverLogic.FormatOffset(pos.x, pos.y))
		entry.coords:Show()
	else
		entry.coords:Hide()
	end
end

local function moved(entry)
	if entry.onMoved then
		entry.onMoved()
	end
	updateCoords(entry)
	if selected == entry then
		fillEditor()
	end
end

local function commit(box)
	local entry = selected
	if not entry then
		return
	end
	local ratio = UIParent:GetEffectiveScale() / entry.frame:GetEffectiveScale()
	local half = (box.axis == "x" and UIParent:GetWidth() or UIParent:GetHeight()) / 2
	local value = MoverLogic.ParseOffset(box:GetText(), half * ratio)
	if not value then
		return
	end
	local pos = entry.getPosition()
	pos.point = pos.point or "CENTER"
	pos[box.axis] = value
	Mover:Apply(entry.frame)
	ns.Debug:Log("Mover", "set", entry.label, box.axis, value)
	moved(entry)
end

local function buildEditor()
	if editor then
		return
	end
	local T = ns.Theme
	editor = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	editor:SetFrameStrata("TOOLTIP")
	editor:SetFrameLevel(500)
	editor:SetClampedToScreen(true)
	editor:SetSize(184, 56)
	editor:SetBackdrop({ bgFile = TEXTURE, edgeFile = TEXTURE, edgeSize = 1 })
	editor:SetBackdropColor(unpack(T.color.bg))
	editor:SetBackdropBorderColor(unpack(T.color.fieldBorder))
	editor:EnableMouse(true)
	editor:Hide()

	editor.title = editor:CreateFontString(nil, "OVERLAY")
	editor.title:SetFont(T.font, T.size.desc, "")
	editor.title:SetTextColor(unpack(T.color.textDim))
	editor.title:SetPoint("TOPLEFT", editor, "TOPLEFT", 8, -6)
	editor.title:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -8, -6)
	editor.title:SetJustifyH("LEFT")
	editor.title:SetWordWrap(false)

	editor.boxes = {}
	for i, axis in ipairs({ "x", "y" }) do
		local label = editor:CreateFontString(nil, "OVERLAY")
		label:SetFont(T.font, T.size.value, "")
		label:SetTextColor(unpack(T.color.text))
		label:SetText(axis:upper())
		label:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 8 + (i - 1) * 88, 12)

		local box = CreateFrame("EditBox", nil, editor)
		box:SetAutoFocus(false)
		box:SetSize(64, 20)
		box:SetPoint("LEFT", label, "RIGHT", 6, 0)
		box:SetFont(T.font, T.size.value, "")
		box:SetTextColor(unpack(T.color.text))
		box:SetTextInsets(4, 4, 0, 0)
		box.axis = axis
		local bg = box:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(unpack(T.color.field))

		box:SetScript("OnEditFocusGained", function(self)
			self:HighlightText()
		end)
		box:SetScript("OnEditFocusLost", function(self)
			self:HighlightText(0, 0)
			fillEditor()
		end)
		box:SetScript("OnEnterPressed", function(self)
			commit(self)
			self:ClearFocus()
		end)
		box:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
		end)
		box:SetScript("OnTabPressed", function(self)
			commit(self)
			editor.boxes[3 - i]:SetFocus()
		end)
		editor.boxes[i] = box
	end
end

local function paintBorder(entry)
	if selected == entry then
		entry.overlay:SetBackdropBorderColor(1, 1, 1, 1)
	else
		entry.overlay:SetBackdropBorderColor(0, 0.5, 1, 1)
	end
end

local function toggleSelect(entry)
	local prev = selected
	selected = (prev ~= entry) and entry or nil
	if prev then
		paintBorder(prev)
		updateCoords(prev)
	end
	if not selected then
		if editor then
			for _, box in ipairs(editor.boxes) do
				box:ClearFocus()
			end
			editor:Hide()
		end
		return
	end
	buildEditor()
	editor.title:SetText(entry.label)
	editor:ClearAllPoints()
	editor:SetPoint("TOP", entry.overlay, "BOTTOM", 0, -4)
	fillEditor()
	editor:Show()
	paintBorder(entry)
	updateCoords(entry)
end

local function otherRects(entry)
	local list = {}
	for _, other in pairs(entries) do
		if other ~= entry and other.overlay:IsShown() then
			local left, bottom, w, h = other.overlay:GetRect()
			if left then
				table.insert(list, { left = left, right = left + w, top = bottom + h, bottom = bottom })
			end
		end
	end
	return list
end

local driver = CreateFrame("Frame")
driver:Hide()

local function finishDrag(entry)
	driver:Hide()
	active = nil
	hideGuides()
	if not entry.dragging then
		return false
	end
	entry.dragging = false
	savePosition(entry)
	Mover:Apply(entry.frame)
	ns.Debug:Log("Mover", "drag", entry.label)
	moved(entry)
	return true
end

local function release(entry)
	if not finishDrag(entry) then
		toggleSelect(entry)
	end
end

driver:SetScript("OnUpdate", function()
	local entry = active
	if not entry then
		driver:Hide()
		return
	end
	if not IsMouseButtonDown("LeftButton") then
		release(entry)
		return
	end
	local x, y = cursor()
	local dx, dy = x - entry.start.x, y - entry.start.y
	if not entry.dragging then
		if math.abs(dx) < DRAG_START and math.abs(dy) < DRAG_START then
			return
		end
		entry.dragging = true
	end
	if IsShiftKeyDown() then
		entry.axis = entry.axis or (math.abs(dx) >= math.abs(dy) and "x" or "y")
		if entry.axis == "x" then
			dy = 0
		else
			dx = 0
		end
	else
		entry.axis = nil
	end

	local overlay = entry.overlay
	local w, h = overlay:GetSize()
	local cx, cy = entry.start.cx + dx, entry.start.cy + dy
	local rect = { left = cx - w / 2, right = cx + w / 2, top = cy + h / 2, bottom = cy - h / 2 }
	local sx, sy, gx, gy = MoverLogic.Snap(rect, otherRects(entry), UIParent:GetWidth(), UIParent:GetHeight(), SNAP)
	if entry.axis == "x" then
		sy, gy = 0, nil
	elseif entry.axis == "y" then
		sx, gx = 0, nil
	end
	overlay:ClearAllPoints()
	overlay:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx + sx, cy + sy)
	showGuides(gx, gy)
	entry.coords:SetText(MoverLogic.FormatOffset(offsetOf(entry)))
	entry.coords:Show()
end)

local function createOverlay(entry)
	local overlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	overlay:SetFrameStrata("TOOLTIP")
	local w, h = visualSize(entry.frame)
	overlay:SetSize(w > 0 and w or 120, h > 0 and h or 20)
	overlay:SetPoint("CENTER", entry.frame, "CENTER", 0, 0)
	overlay:SetBackdrop({
		bgFile = TEXTURE,
		edgeFile = TEXTURE,
		edgeSize = 1,
	})
	overlay:SetBackdropColor(0, 0.5, 1, 0.3)
	overlay:SetBackdropBorderColor(0, 0.5, 1, 1)
	overlay:EnableMouse(true)
	overlay:Hide()

	local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetAllPoints()
	text:SetText(entry.label)

	local coords = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	coords:SetPoint("BOTTOMLEFT", overlay, "TOPLEFT", 0, 2)
	coords:Hide()
	entry.coords = coords

	overlay:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		local x, y = cursor()
		local cx, cy = overlay:GetCenter()
		if not cx then
			return
		end
		entry.start = { x = x, y = y, cx = cx, cy = cy }
		entry.axis = nil
		active = entry
		driver:Show()
	end)
	overlay:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" and active == entry then
			release(entry)
		end
	end)
	overlay:SetScript("OnEnter", function()
		entry.hovered = true
		updateCoords(entry)
	end)
	overlay:SetScript("OnLeave", function()
		entry.hovered = false
		updateCoords(entry)
	end)

	return overlay
end

-- onMoved runs after the user drags the frame or types a position.
function Mover:Register(frame, label, getPosition, onMoved)
	if entries[frame] then
		return
	end

	local entry = { frame = frame, label = label, getPosition = getPosition, onMoved = onMoved, dragging = false }
	entry.overlay = createOverlay(entry)
	entries[frame] = entry

	if isUnlocked then
		entry.overlay:Show()
	end
end

function Mover:Unregister(frame)
	local entry = entries[frame]
	if not entry then
		return
	end
	if active == entry then
		driver:Hide()
		active = nil
		hideGuides()
	end
	if selected == entry then
		toggleSelect(entry)
	end
	entry.dragging = false
	entry.overlay:Hide()
	entries[frame] = nil
end

function Mover:Apply(frame)
	local entry = entries[frame]
	if not entry then
		return false
	end
	if frame:IsProtected() and InCombatLockdown() then
		return false
	end

	local pos = entry.getPosition()
	local point = pos.point or "CENTER"
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, pos.x or 0, pos.y or 0)

	if entry.dragging then
		return true
	end
	local overlay = entry.overlay
	local w, h = visualSize(frame)
	if w > 0 and h > 0 then
		overlay:SetSize(w, h)
	end
	overlay:ClearAllPoints()
	overlay:SetPoint("CENTER", frame, "CENTER", 0, 0)
	updateCoords(entry)
	if selected == entry then
		fillEditor()
	end

	return true
end

function Mover:SetUnlocked(value)
	value = not not value

	if value == isUnlocked then
		return true
	end

	if value and InCombatLockdown() then
		ns.addon:Print("Cannot unlock frames in combat.")
		return false
	end

	if not value then
		if active then
			finishDrag(active)
		end
		if selected then
			toggleSelect(selected)
		end
	end

	isUnlocked = value
	ns.Debug:Log("Mover", "unlocked", value)

	for _, entry in pairs(entries) do
		entry.hovered = false
		entry.overlay:SetShown(isUnlocked)
		updateCoords(entry)
	end
	if isUnlocked then
		showGrid()
	elseif grid then
		grid:Hide()
	end

	ns.addon:SendMessage("MERRINXUI_LOCK_CHANGED", isUnlocked)
	LibStub("AceConfigRegistry-3.0"):NotifyChange("MerrinxUI")

	return true
end

function Mover:IsUnlocked()
	return isUnlocked
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", function()
	local wasUnlocked = isUnlocked
	if active then
		finishDrag(active)
	end
	Mover:SetUnlocked(false)
	if wasUnlocked then
		ns.Debug:Log("Mover", "relock combat")
	end
end)

ns.Debug:RegisterChecks("Mover", function()
	local checks = {
		{
			name = "unlocked",
			run = function(ctx)
				return (isUnlocked and ctx.inCombat) and "FAIL" or "PASS", isUnlocked
			end,
		},
		{
			name = "grid",
			run = function()
				local shown = grid ~= nil and grid:IsShown()
				return (shown == isUnlocked) and "PASS" or "FAIL", shown, grid and #grid.lines or 0
			end,
		},
	}

	for frame, entry in pairs(entries) do
		local label = entry.label

		table.insert(checks, {
			name = "position " .. label,
			run = function()
				if entry.dragging or frame:GetNumPoints() == 0 then
					return "SKIP"
				end

				local point, rel, relPoint, x, y = frame:GetPoint(1)
				if issecretvalue(x) or issecretvalue(y) then
					return "INFO", "secret"
				end

				local pos = entry.getPosition()
				local expectedPoint = pos.point or "CENTER"
				local expectedX = pos.x or 0
				local expectedY = pos.y or 0

				local ok = point == expectedPoint
					and rel == UIParent
					and relPoint == point
					and math.abs(x - expectedX) <= 0.5
					and math.abs(y - expectedY) <= 0.5
				return ok and "PASS" or "FAIL", point, x, y
			end,
		})

		table.insert(checks, {
			name = "overlay " .. label,
			run = function()
				return (entry.overlay:IsShown() == isUnlocked) and "PASS" or "FAIL"
			end,
		})
	end

	return checks
end)
