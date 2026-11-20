local addonName, ns = ...

local L = ns.ZoneInfoLogic
local Theme = ns.Theme

local TOP_OFFSET = -48
local UPDATE_INTERVAL = 0.05
local FONT_KEY = ns.FontLogic.GLOBAL
local LEVEL_SIZE = 14
local FISH_SIZE = 12

local COLOR = {
	hard = { 1, 0.35, 0.35, 1 },
	even = { 1, 0.82, 0, 1 },
	easy = { 0.4, 0.9, 0.4, 1 },
}

local overlay, levelFS, fishFS, scroll
local attached = false
local attachError
local cachedId, cachedLevel

local function setTextColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4])
end

local function applyFonts()
	ns.Media:SetFont(levelFS, FONT_KEY, LEVEL_SIZE, "OUTLINE")
	ns.Media:SetFont(fishFS, FONT_KEY, FISH_SIZE, "OUTLINE")
end

local function update()
	local shown = WorldMapFrame:GetMapID()
	local hovered = nil
	if shown ~= nil and scroll:IsMouseOver() then
		local x, y = scroll:GetNormalizedCursorPosition()
		local info = C_Map.GetMapInfoAtPosition(shown, x, y)
		hovered = info and info.mapID
	end

	local id = L.Resolve(shown, hovered)
	local level = UnitLevel("player")
	if id == cachedId and level == cachedLevel then
		return
	end
	cachedId = id
	cachedLevel = level

	local entry = L.Info(id)
	local levelText = L.LevelText(entry)
	local fishText = L.FishingText(entry)

	if levelText ~= nil then
		levelFS:SetText(levelText)
		setTextColor(levelFS, COLOR[L.Difficulty(level, entry.low, entry.high)])
		levelFS:Show()
	else
		levelFS:SetText("")
		levelFS:Hide()
	end

	if fishText ~= nil then
		fishFS:SetText(fishText)
		setTextColor(fishFS, Theme.color.text)
		fishFS:Show()
	else
		fishFS:SetText("")
		fishFS:Hide()
	end

	fishFS:ClearAllPoints()
	if levelText ~= nil then
		fishFS:SetPoint("TOP", levelFS, "BOTTOM", 0, -2)
	else
		fishFS:SetPoint("TOP", overlay, "TOP", 0, 0)
	end
end

local function attach()
	if WorldMapFrame == nil then
		attachError = "WorldMapFrame missing"
		return
	end
	scroll = WorldMapFrame.ScrollContainer
	if scroll == nil then
		attachError = "WorldMapFrame.ScrollContainer missing"
		return
	end
	if type(WorldMapFrame.GetMapID) ~= "function" then
		attachError = "WorldMapFrame.GetMapID missing"
		return
	end
	if type(scroll.GetNormalizedCursorPosition) ~= "function" then
		attachError = "ScrollContainer.GetNormalizedCursorPosition missing"
		return
	end

	overlay = CreateFrame("Frame", "MerrinxUIZoneInfo", scroll)
	overlay:SetSize(400, 40)
	overlay:SetPoint("TOP", scroll, "TOP", 0, TOP_OFFSET)
	overlay:EnableMouse(false)
	overlay:SetFrameLevel(scroll:GetFrameLevel() + 500)

	levelFS = overlay:CreateFontString(nil, "OVERLAY")
	levelFS:SetPoint("TOP", overlay, "TOP", 0, 0)
	levelFS:SetJustifyH("CENTER")
	levelFS:Hide()

	fishFS = overlay:CreateFontString(nil, "OVERLAY")
	fishFS:SetJustifyH("CENTER")
	fishFS:Hide()

	applyFonts()

	overlay:SetScript("OnShow", function()
		cachedId = nil
		cachedLevel = nil
		applyFonts()
	end)

	local elapsed = 0
	overlay:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= UPDATE_INTERVAL then
			elapsed = 0
			update()
		end
	end)

	attached = true
end

-- Blizzard_WorldMap is already loaded when this chunk runs, so attaching
-- immediately would precede Media:OnInitialize and its db.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	events:UnregisterEvent("PLAYER_LOGIN")
	if type(EventUtil) == "table" and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", attach)
	end
end)

ns.Debug:RegisterChecks("ZoneInfo", function()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function check(name, fn)
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end

				check("EventUtil.ContinueOnAddOnLoaded", type(EventUtil) == "table" and EventUtil.ContinueOnAddOnLoaded)
				check("C_Map.GetMapInfo", type(C_Map) == "table" and C_Map.GetMapInfo)
				check("C_Map.GetMapInfoAtPosition", type(C_Map) == "table" and C_Map.GetMapInfoAtPosition)
				check("UnitLevel", UnitLevel)

				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "overlay",
			run = function()
				if not attached then
					if attachError ~= nil then
						return "FAIL", attachError
					end
					return "SKIP", "not attached"
				end

				if not WorldMapFrame:IsShown() then
					return "INFO", "map closed"
				end

				local idText = cachedId ~= nil and tostring(cachedId) or "none"
				return "PASS", idText, L.LevelText(L.Info(cachedId))
			end,
		},
		{
			name = "data",
			run = function()
				local bad = {}
				local count = 0
				local locale = GetLocale()
				for id, entry in pairs(L.ZONES) do
					count = count + 1
					local info = C_Map.GetMapInfo(id)
					if info == nil or (locale == "enUS" and info.name ~= entry.name) then
						if #bad < 5 then
							table.insert(bad, id)
						end
					end
				end

				if #bad > 0 then
					return "FAIL", unpack(bad, 1, #bad)
				end

				if locale == "enUS" then
					return "PASS", count
				end
				return "PASS", count, "names unchecked"
			end,
		},
	}
end)
