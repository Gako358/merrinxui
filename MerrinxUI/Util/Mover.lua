local addonName, ns = ...

local MoverLogic = ns.MoverLogic

local Mover = {}
ns.Mover = Mover

local isUnlocked = false
local entries = {} -- frame -> { label, getPosition, overlay, dragging, savePosition }

local function createOverlay(frame, label)
	local overlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	overlay:SetFrameStrata("TOOLTIP")
	local w = frame:GetWidth()
	local h = frame:GetHeight()
	overlay:SetSize(w > 0 and w or 120, h > 0 and h or 20)
	overlay:SetPoint("CENTER", frame, "CENTER", 0, 0)
	overlay:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	overlay:SetBackdropColor(0, 0.5, 1, 0.3)
	overlay:SetBackdropBorderColor(0, 0.5, 1, 1)
	overlay:EnableMouse(true)
	overlay:SetMovable(true)
	overlay:RegisterForDrag("LeftButton")
	overlay:Hide()

	local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetAllPoints()
	text:SetText(label)

	return overlay
end

function Mover:Register(frame, label, getPosition)
	if entries[frame] then
		return
	end

	local overlay = createOverlay(frame, label)
	local entry = { label = label, getPosition = getPosition, overlay = overlay, dragging = false }

	local function savePosition()
		local cx, cy = overlay:GetCenter()
		if not cx then
			return
		end
		local pos = getPosition()
		local frameScale = frame:GetEffectiveScale()
		local overlayScale = overlay:GetEffectiveScale()
		local parentScale = UIParent:GetEffectiveScale()
		cx = cx * overlayScale / frameScale
		cy = cy * overlayScale / frameScale
		local x, y = MoverLogic.CenterOffset(cx, cy, frameScale, UIParent:GetWidth(), UIParent:GetHeight(), parentScale)
		pos.point = pos.point or "CENTER"
		pos.x = x
		pos.y = y
	end
	entry.savePosition = savePosition

	overlay:SetScript("OnDragStart", function()
		entry.dragging = true
		overlay:StartMoving()
	end)
	overlay:SetScript("OnDragStop", function()
		overlay:StopMovingOrSizing()
		entry.dragging = false
		savePosition()
		Mover:Apply(frame)
	end)

	entries[frame] = entry

	if isUnlocked then
		overlay:Show()
	end
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

	local overlay = entry.overlay
	local w, h = frame:GetWidth(), frame:GetHeight()
	if w > 0 and h > 0 then
		overlay:SetSize(w, h)
	end
	overlay:ClearAllPoints()
	overlay:SetPoint("CENTER", frame, "CENTER", 0, 0)

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

	isUnlocked = value
	ns.Debug:Log("Mover", "unlocked", value)

	for _, entry in pairs(entries) do
		if isUnlocked then
			entry.overlay:Show()
		else
			entry.overlay:Hide()
		end
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
	for frame, entry in pairs(entries) do
		if entry.dragging then
			entry.overlay:StopMovingOrSizing()
			entry.dragging = false
			entry.savePosition()
			Mover:Apply(frame)
		end
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
