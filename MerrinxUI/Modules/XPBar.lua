local addonName, ns = ...

local L = ns.XPBarLogic
local FontLogic = ns.FontLogic

local XPBar = ns.addon:NewModule("XPBar", "AceEvent-3.0")

local XP_COLOR = { 0.58, 0.0, 0.55 }
local RESTED_STATE_COLOR = { 0.0, 0.39, 0.88 }
local RESTED_COLOR = { 0.25, 0.5, 1, 0.45 }
local QUEST_COLOR = { 1, 0.78, 0.2, 0.7 }

local defaults = {
	profile = {
		enabled = false,
		width = 520,
		height = 14,
		font = FontLogic.GLOBAL,
		barTexture = FontLogic.GLOBAL,
		fontSize = 11,
		bgOpacity = 60,
		showText = true,
		questXP = true,
		rested = true,
		position = { point = "CENTER", x = 0, y = -360 },
	},
}

local function isSecret(v)
	return issecretvalue(v) == true
end

local function newLayer(parent, level)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetAllPoints()
	bar:SetMinMaxValues(0, 1)
	bar:SetFrameLevel(parent:GetFrameLevel() + level)
	return bar
end

function XPBar:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("XPBar", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.questCount, self.questXP = 0, 0
	self.scans = 0
end

function XPBar:OnEnable()
	self:Build()
	for _, event in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_ENTERING_WORLD" }) do
		self:RegisterEvent(event, "Update")
	end
	self:RegisterEvent("ENABLE_XP_GAIN", "Update")
	self:RegisterEvent("DISABLE_XP_GAIN", "Update")
	self:RegisterEvent("QUEST_LOG_UPDATE", "RequestScan")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "Update")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "Layout")
	ns.Combat:Run("XPBar:Blizzard", function()
		ns.addon:GetModule("HideBlizzard"):Ensure("xp")
	end)
	self:Layout()
	self:ScanQuests()
	self:Update()
end

function XPBar:OnDisable()
	if self.frame then
		self.frame:Hide()
	end
	ns.addon:Print("XPBar: /reload restores Blizzard's XP bar")
end

function XPBar:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:Layout()
			self:ScanQuests()
			self:Update()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function XPBar:Build()
	if self.frame then
		return
	end
	local frame = CreateFrame("Frame", addonName .. "XPBar", UIParent, "BackdropTemplate")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	frame:SetBackdropBorderColor(0, 0, 0, 1)
	self.frame = frame

	self.bg = frame:CreateTexture(nil, "BACKGROUND")
	self.bg:SetPoint("TOPLEFT", 1, -1)
	self.bg:SetPoint("BOTTOMRIGHT", -1, 1)

	self.restedBar = newLayer(frame, 1)
	self.questBar = newLayer(frame, 2)
	self.xpBar = newLayer(frame, 3)
	for _, bar in ipairs({ self.restedBar, self.questBar, self.xpBar }) do
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", 1, -1)
		bar:SetPoint("BOTTOMRIGHT", -1, 1)
	end

	local textFrame = CreateFrame("Frame", nil, frame)
	textFrame:SetAllPoints()
	textFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
	self.text = textFrame:CreateFontString(nil, "OVERLAY")
	self.text:SetPoint("CENTER")
	self.text:SetWordWrap(false)

	frame:SetScript("OnEnter", function(owner)
		self:ShowTooltip(owner)
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	ns.Mover:Register(frame, "XP Bar", function()
		return self.db.profile.position
	end)
end

function XPBar:Layout()
	if not self.frame then
		return
	end
	local p = self.db.profile
	self.frame:SetSize(p.width, p.height)
	ns.Mover:Apply(self.frame)
	self.bg:SetColorTexture(0, 0, 0, p.bgOpacity / 100)
	for _, bar in ipairs({ self.restedBar, self.questBar, self.xpBar }) do
		ns.Media:SetStatusBarTexture(bar, p.barTexture)
	end
	self.restedBar:SetStatusBarColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3], RESTED_COLOR[4])
	self.questBar:SetStatusBarColor(QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3], QUEST_COLOR[4])
	ns.Media:SetFont(self.text, p.font, p.fontSize, "OUTLINE")
	self.text:SetWidth(p.width - 8)
	self.text:SetShown(p.showText)
	self:Update()
end

function XPBar:Hidden()
	local maxLevel = GetMaxLevelForPlayerExpansion()
	return L.AtMax(UnitLevel("player"), maxLevel) or IsXPUserDisabled() == true
end

-- A burst of QUEST_LOG_UPDATE events costs one scan.
function XPBar:RequestScan()
	if self.scanPending then
		return
	end
	self.scanPending = true
	C_Timer.After(0, function()
		self.scanPending = false
		if self:IsEnabled() then
			self:ScanQuests()
			self:Update()
		end
	end)
end

function XPBar:ScanQuests()
	local entries = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local questID = C_QuestLog.GetQuestIDForLogIndex(i)
		if type(questID) == "number" and questID > 0 and C_QuestLog.IsComplete(questID) then
			entries[#entries + 1] = { complete = true, xp = GetQuestLogRewardXP(questID) }
		end
	end
	self.questCount, self.questXP = L.QuestXP(entries)
	self.scans = self.scans + 1
end

function XPBar:Values()
	local cur, max = UnitXP("player"), UnitXPMax("player")
	local rested = GetXPExhaustion() or 0
	if isSecret(cur) or isSecret(max) or isSecret(rested) then
		return nil
	end
	return cur, math.max(1, max), rested
end

function XPBar:Update()
	local frame = self.frame
	if not frame or not self:IsEnabled() then
		return
	end
	local p = self.db.profile
	local hidden = self:Hidden()
	frame:SetShown(ns.Mover:IsUnlocked() or not hidden)
	if hidden then
		return
	end

	local cur, max, rested = self:Values()
	if not cur then
		return
	end
	local quest = p.questXP and self.questXP or 0
	local restedShown = p.rested and rested or 0

	for _, bar in ipairs({ self.restedBar, self.questBar, self.xpBar }) do
		bar:SetMinMaxValues(0, max)
	end
	self.xpBar:SetValue(cur)
	self.questBar:SetValue(L.Fill(cur, max, quest))
	self.restedBar:SetValue(L.Fill(cur, max, restedShown))
	self.questBar:SetShown(quest > 0)
	self.restedBar:SetShown(restedShown > 0)
	local c = rested > 0 and RESTED_STATE_COLOR or XP_COLOR
	self.xpBar:SetStatusBarColor(c[1], c[2], c[3])

	if p.showText then
		self.text:SetText(L.Text(cur, max, restedShown, quest, BreakUpLargeNumbers))
	end
end

function XPBar:ShowTooltip(owner)
	local cur, max, rested = self:Values()
	if not cur or self:Hidden() then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:SetText("Experience", 1, 1, 1)
	GameTooltip:AddDoubleLine("Level", tostring(UnitLevel("player")), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(
		"XP",
		string.format("%s / %s (%.1f%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(max), L.Percent(cur, max)),
		1,
		1,
		1,
		1,
		1,
		1
	)
	GameTooltip:AddDoubleLine("Remaining", BreakUpLargeNumbers(max - cur), 1, 1, 1, 1, 1, 1)
	if rested > 0 then
		GameTooltip:AddDoubleLine("Rested", "+" .. BreakUpLargeNumbers(rested), 1, 1, 1, 0.4, 0.6, 1)
	end
	if self.questCount > 0 then
		GameTooltip:AddDoubleLine(
			"Completed quests (" .. self.questCount .. ")",
			string.format("+%s (%.1f%%)", BreakUpLargeNumbers(self.questXP), L.Percent(self.questXP, max)),
			1,
			1,
			1,
			QUEST_COLOR[1],
			QUEST_COLOR[2],
			QUEST_COLOR[3]
		)
		if cur + self.questXP >= max then
			GameTooltip:AddLine("Turning them in levels you up", QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3])
		end
	end
	GameTooltip:Show()
end

function XPBar:GetTabOptions()
	local xb = self
	local function get(key)
		return function()
			return xb.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			xb.db.profile[key] = value
			xb:Refresh()
		end
	end
	local function toggle(key, name, order, desc)
		return { type = "toggle", name = name, desc = desc, order = order, get = get(key), set = set(key) }
	end
	local function range(key, name, order, min, max, step)
		return {
			type = "range",
			name = name,
			order = order,
			min = min,
			max = max,
			step = step,
			get = get(key),
			set = set(key),
		}
	end
	return {
		type = "group",
		name = "XPBar",
		args = {
			enabled = toggle("enabled", "Enabled", 1, "Also hides Blizzard's XP bar until /reload"),
			width = range("width", "Width", 2, 100, 1600, 1),
			height = range("height", "Height", 3, 4, 40, 1),
			font = {
				type = "select",
				name = "Font",
				order = 4,
				dialogControl = "LSM30_Font",
				values = function()
					return ns.Media:Values("font", xb.db.profile.font)
				end,
				get = get("font"),
				set = set("font"),
			},
			barTexture = {
				type = "select",
				name = "Bar texture",
				order = 5,
				dialogControl = "LSM30_Statusbar",
				values = function()
					return ns.Media:Values("statusbar", xb.db.profile.barTexture)
				end,
				get = get("barTexture"),
				set = set("barTexture"),
			},
			fontSize = range("fontSize", "Font size", 6, 8, 20, 1),
			bgOpacity = range("bgOpacity", "Background opacity", 7, 0, 100, 5),
			showText = toggle("showText", "Text", 8),
			questXP = toggle(
				"questXP",
				"Completed quest XP",
				9,
				"Shows how far the XP of the quests ready to turn in takes the bar"
			),
			rested = toggle("rested", "Rested XP", 10),
		},
	}
end

function XPBar:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, fn in pairs({
					UnitXP = UnitXP,
					UnitXPMax = UnitXPMax,
					GetXPExhaustion = GetXPExhaustion,
					GetQuestLogRewardXP = GetQuestLogRewardXP,
					GetMaxLevelForPlayerExpansion = GetMaxLevelForPlayerExpansion,
					IsXPUserDisabled = IsXPUserDisabled,
					BreakUpLargeNumbers = BreakUpLargeNumbers,
					["C_QuestLog.GetNumQuestLogEntries"] = C_QuestLog and C_QuestLog.GetNumQuestLogEntries,
					["C_QuestLog.GetQuestIDForLogIndex"] = C_QuestLog and C_QuestLog.GetQuestIDForLogIndex,
					["C_QuestLog.IsComplete"] = C_QuestLog and C_QuestLog.IsComplete,
				}) do
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end
				table.sort(missing)
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "visibility",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local expected = ns.Mover:IsUnlocked() or not self:Hidden()
				local shown = self.frame ~= nil and self.frame:IsShown()
				return (shown == expected) and "PASS" or "FAIL",
					shown,
					UnitLevel("player"),
					GetMaxLevelForPlayerExpansion()
			end,
		},
		{
			name = "values",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if self:Hidden() then
					return "SKIP", "max level or XP off"
				end
				local cur, max = self:Values()
				if not cur then
					return "INFO", "secret"
				end
				local _, barMax = self.xpBar:GetMinMaxValues()
				local value = self.xpBar:GetValue()
				local ok = math.abs(value - cur) <= 0.5 and math.abs(barMax - max) <= 0.5
				return ok and "PASS" or "FAIL", value, cur, barMax, max
			end,
		},
		{
			name = "quest xp",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return "INFO", self.questCount, self.questXP, self.scans
			end,
		},
		{
			name = "blizzard xp bar",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local blizz = _G.StatusTrackingBarManager
				if not blizz then
					return "INFO", "missing"
				end
				return (not blizz:IsVisible()) and "PASS" or "FAIL"
			end,
		},
	}
end
