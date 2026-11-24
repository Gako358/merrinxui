local addonName, ns = ...

local L = ns.LootRollLogic
local FontLogic = ns.FontLogic
local MoverLogic = ns.MoverLogic
local C = ns.Theme.color

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local CLASS_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local HEADER_HEIGHT = 24
local STATUS_HEIGHT = 18
local ROW_HEIGHT = 18
local TOP_RESERVED = HEADER_HEIGHT + STATUS_HEIGHT + 4
local LINGER = 8
local TICK_INTERVAL = 1
local MIN_W, MIN_H = 200, 120
local MAX_W, MAX_H = 480, 800

local STATE_COLOR = {
	[L.STATE.NEED_MAIN] = { 0.2, 0.9, 0.3 },
	[L.STATE.NEED_OFF] = { 0.2, 0.9, 0.3 },
	[L.STATE.TRANSMOG] = { 0.65, 0.4, 0.95 },
	[L.STATE.GREED] = { 0.95, 0.75, 0.2 },
}

local LootRolls = ns.addon:NewModule("LootRolls", "AceEvent-3.0")

local defaults = {
	profile = {
		width = 260,
		height = 230,
		fontSize = 12,
		font = FontLogic.GLOBAL,
		position = { point = "CENTER", x = 0, y = -200 },
	},
}

local function setColor(tex, color)
	tex:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function setTextColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4])
end

local function classColor(class)
	local color = class and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return C.text[1], C.text[2], C.text[3]
end

local function setClassIcon(texture, class)
	local coords = class and CLASS_ICON_TCOORDS[class]
	if coords then
		texture:SetTexture(CLASS_TEXTURE)
		texture:SetTexCoord(ns.DamageMeterLogic.IconCoords(coords, 0.06))
		texture:Show()
	else
		texture:Hide()
	end
end

local function createButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent)
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	setColor(bg, C.button)

	local fs = button:CreateFontString(nil, "OVERLAY")
	fs:SetAllPoints()
	fs:SetJustifyH("CENTER")
	setTextColor(fs, C.text)
	fs:SetText(text)
	button.text = fs
	button.label = text

	button:SetScript("OnEnter", function()
		setColor(bg, C.buttonHover)
	end)
	button:SetScript("OnLeave", function()
		setColor(bg, C.button)
	end)
	button:SetScript("OnClick", onClick)
	return button
end

local function setButtonFont(button, font, size)
	ns.Media:SetFont(button.text, font, size, "")
	button.text:SetText(button.label)
end

local function cursor(frame)
	local x, y = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	return x / scale, y / scale
end

local function readRaw()
	local raw = {}
	local encounters = C_LootHistory.GetAllEncounterInfos()
	if issecretvalue(encounters) or type(encounters) ~= "table" then
		return raw
	end

	for _, encounter in ipairs(encounters) do
		if not issecretvalue(encounter) and type(encounter) == "table" then
			local id = encounter.encounterID
			if type(id) == "number" and not issecretvalue(id) then
				local drops = C_LootHistory.GetSortedDropsForEncounter(id)
				if not issecretvalue(drops) and type(drops) == "table" then
					local list = {}
					for _, drop in ipairs(drops) do
						if not issecretvalue(drop) and type(drop) == "table" then
							local lootListID = drop.lootListID
							if type(lootListID) == "number" and not issecretvalue(lootListID) then
								local info = C_LootHistory.GetSortedInfoForDrop(id, lootListID)
								if not issecretvalue(info) and type(info) == "table" then
									list[#list + 1] = info
								end
							end
						end
					end
					if #list > 0 then
						raw[#raw + 1] = { encounterID = id, drops = list }
					end
				end
			end
		end
	end

	return raw
end

local function selfTestLogic()
	local raw = {
		{
			encounterID = 1,
			drops = {
				{
					lootListID = 1,
					itemHyperlink = "item:1",
					startTime = 100,
					duration = 60,
					allPassed = false,
					winner = nil,
					rollInfos = {
						{
							playerName = "Alice",
							playerGUID = "g1",
							playerClass = "WARRIOR",
							state = 0,
							roll = 90,
							isWinner = true,
						},
						{
							playerName = "Bob",
							playerGUID = "g2",
							playerClass = "ROGUE",
							state = 5,
							roll = nil,
							isWinner = false,
						},
					},
				},
			},
		},
	}
	local noSecret = function()
		return false
	end

	local state = L.Build(raw, {}, 110, noSecret)
	if #state.drops ~= 1 then
		return false, "build"
	end

	local drop = state.drops[1]
	if #drop.rolls ~= 2 then
		return false, "rolls"
	end

	local sorted = L.SortRolls({ drop.rolls[2], drop.rolls[1] })
	if sorted[1].name ~= "Alice" then
		return false, "sort"
	end

	local n = L.WinCount(state, drop, drop.rolls[1])
	if n ~= 0 then
		return false, "wincount"
	end

	local snapshot = L.Snapshot(raw, noSecret)
	if not snapshot["1:1"] then
		return false, "snapshot"
	end

	local secretState = L.Build(raw, {}, 110, function(v)
		return v == 90
	end)
	if secretState.drops[1].rolls[1].roll ~= nil then
		return false, "secret"
	end

	local action, count = L.ParseSlash("test 99")
	if action ~= "test" or count ~= 40 then
		return false, "parseslash"
	end

	local preview = L.Preview(5)
	if #preview.active ~= 1 or #preview.drops ~= 3 then
		return false, "preview"
	end

	return true
end

function LootRolls:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("LootRolls", defaults)

	self.raw = {}
	self.excluded = {}
	self.eventCounts = {}
	self.rowPool = {}
	self.dismissed = false
	self.pinned = false
	self.unlockPreview = false
	self.historyMode = false
	self.pageIndex = 1
	self.historyIndex = 1
	self.scrollOffset = 0
	self.lastActiveCount = 0
	self.lastShown = 0
	self.lastVisible = false
	self.trackedKeys = {}

	self:CreateFrame()

	ns.Mover:Register(self.frame, "Loot rolls", function()
		return self.db.profile.position
	end)

	ns.addon:RegisterSlash("rolls", function(arg)
		self:Slash(arg)
	end)
end

function LootRolls:CreateFrame()
	local frame = CreateFrame("Frame", addonName .. "LootRolls", UIParent, "BackdropTemplate")
	frame:Hide()
	frame:SetClampedToScreen(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		self:Scroll(-delta)
	end)
	frame:SetBackdrop({ bgFile = TEXTURE, edgeFile = TEXTURE, edgeSize = 1 })
	frame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
	frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
	self.frame = frame

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	self.header = header

	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	setColor(headerBg, C.header)

	local divider = header:CreateTexture(nil, "BORDER")
	divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
	divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
	divider:SetHeight(1)
	setColor(divider, C.border)

	local close = createButton(header, "x", function()
		self:OnClose()
	end)
	close:SetSize(HEADER_HEIGHT, HEADER_HEIGHT)
	close:SetPoint("RIGHT", header, "RIGHT")
	self.closeButton = close

	local historyToggle = createButton(header, "Live", function()
		self:ToggleHistory()
	end)
	historyToggle:SetSize(42, HEADER_HEIGHT)
	historyToggle:SetPoint("RIGHT", close, "LEFT", -2, 0)
	self.historyToggle = historyToggle

	local nextButton = createButton(header, ">", function()
		self:Page(1)
	end)
	nextButton:SetSize(16, HEADER_HEIGHT)
	nextButton:SetPoint("RIGHT", historyToggle, "LEFT", -2, 0)
	self.nextButton = nextButton

	local pageText = header:CreateFontString(nil, "OVERLAY")
	pageText:SetPoint("RIGHT", nextButton, "LEFT", -2, 0)
	pageText:SetWidth(32)
	pageText:SetJustifyH("CENTER")
	setTextColor(pageText, C.textDim)
	self.pageText = pageText

	local prevButton = createButton(header, "<", function()
		self:Page(-1)
	end)
	prevButton:SetSize(16, HEADER_HEIGHT)
	prevButton:SetPoint("RIGHT", pageText, "LEFT", -2, 0)
	self.prevButton = prevButton

	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetSize(HEADER_HEIGHT - 6, HEADER_HEIGHT - 6)
	icon:SetPoint("LEFT", header, "LEFT", 4, 0)
	self.icon = icon

	local link = header:CreateFontString(nil, "OVERLAY")
	link:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	link:SetPoint("RIGHT", prevButton, "LEFT", -4, 0)
	link:SetJustifyH("LEFT")
	link:SetWordWrap(false)
	setTextColor(link, C.text)
	self.link = link

	local linkArea = CreateFrame("Frame", nil, header)
	linkArea:SetPoint("TOPLEFT", icon, "TOPLEFT")
	linkArea:SetPoint("BOTTOMRIGHT", prevButton, "BOTTOMLEFT", -4, 0)
	linkArea:EnableMouse(true)
	linkArea:SetScript("OnEnter", function()
		if self.linkHyperlink then
			GameTooltip:SetOwner(linkArea, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.linkHyperlink)
			GameTooltip:Show()
		end
	end)
	linkArea:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local status = frame:CreateFontString(nil, "OVERLAY")
	status:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -2)
	status:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -4, -2)
	status:SetHeight(STATUS_HEIGHT)
	status:SetJustifyH("LEFT")
	setTextColor(status, C.text)
	self.status = status

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	local gripIcon = grip:CreateTexture(nil, "ARTWORK")
	gripIcon:SetAllPoints()
	gripIcon:SetTexture(ns.Media:Icon("resize"))
	grip:SetScript("OnMouseDown", function(_, button)
		self:StartResize(button)
	end)
	grip:SetScript("OnMouseUp", function()
		self:FinishResize()
	end)
	self.grip = grip

	local sizer = CreateFrame("Frame")
	sizer:Hide()
	sizer:SetScript("OnUpdate", function()
		self:UpdateResize()
	end)
	self.sizer = sizer

	self:Layout()
end

function LootRolls:OnEnable()
	self.hasApi = L.HasApi(C_LootHistory)

	self:RegisterEvent("START_LOOT_ROLL", "OnTrigger")
	self:RegisterEvent("LOOT_ROLLS_COMPLETE", "OnTrigger")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnTrigger")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnTrigger")
	if self.hasApi then
		self:RegisterEvent("LOOT_HISTORY_UPDATE_DROP", "OnTrigger")
		self:RegisterEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", "OnTrigger")
		self:RegisterEvent("LOOT_HISTORY_CLEAR_HISTORY", "OnTrigger")
	end
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "OnLockChanged")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")

	ns.Mover:Apply(self.frame)
	self:Layout()
	self:RequestRebuild()
end

function LootRolls:OnDisable()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	self.frame:Hide()
end

function LootRolls:Refresh()
	ns.Mover:Apply(self.frame)
	self:Layout()
	self:Render()
end

function LootRolls:OnMediaChanged(_, mediatype, key)
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", self.db.profile.font)) then
		self:Layout()
	end
end

function LootRolls:OnLockChanged(_, unlocked)
	self.unlockPreview = unlocked == true
	self:Render()
end

function LootRolls:OnTrigger(event)
	self.eventCounts[event] = (self.eventCounts[event] or 0) + 1
	if event == "PLAYER_ENTERING_WORLD" then
		self.pendingReset = true
	end
	self:RequestRebuild()
end

function LootRolls:RequestRebuild()
	if self.rebuildPending then
		return
	end
	self.rebuildPending = true
	C_Timer.After(0, function()
		self.rebuildPending = false
		self:Rebuild()
	end)
end

function LootRolls:CheckInstanceReset(raw)
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if issecretvalue(instanceType) then
		instanceType = nil
	end
	if issecretvalue(instanceID) then
		instanceID = nil
	end

	if L.ShouldReset(self.prevInstanceID, instanceID, instanceType) then
		self.excluded = L.Snapshot(raw, issecretvalue)
		self.dismissed = false
		self.pageIndex = 1
		self.historyIndex = 1
		self.trackedKeys = {}
		ns.Debug:Log("LootRolls", "reset", instanceID, instanceType)
	end

	if instanceType == "party" or instanceType == "raid" then
		self.prevInstanceID = instanceID
	end
end

function LootRolls:ManageLinger(state)
	local now = GetTime()
	local activeCount = #state.active

	local activeKeys = {}
	for _, drop in ipairs(state.active) do
		activeKeys[drop.key] = true
		self.trackedKeys[drop.key] = true
		if not (self.lastActiveKeys and self.lastActiveKeys[drop.key]) then
			self.dismissed = false
		end
	end
	self.lastActiveKeys = activeKeys

	if activeCount ~= self.lastActiveCount then
		ns.Debug:Log("LootRolls", "active", activeCount)
		self.lastActiveCount = activeCount
	end

	if activeCount > 0 then
		self.lingerUntil = nil
	elseif self.lingerUntil == nil and self.hadActive then
		self.lingerUntil = now + LINGER
	end
	self.hadActive = activeCount > 0

	if self.lingerUntil ~= nil and now >= self.lingerUntil then
		self.lingerUntil = nil
	end
	self.lingering = self.lingerUntil ~= nil

	if activeCount == 0 and not self.lingering then
		self.trackedKeys = {}
	end

	local needTicker = activeCount > 0 or self.lingering
	if needTicker and (not self.ticker or self.ticker:IsCancelled()) then
		self.ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
			self:RequestRebuild()
		end)
	elseif not needTicker and self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
end

function LootRolls:Rebuild()
	local raw = self.hasApi and readRaw() or {}
	self.raw = raw

	if self.pendingReset then
		self.pendingReset = false
		self:CheckInstanceReset(raw)
	end

	local now = self.hasApi and C_LootHistory.GetLootHistoryTime() or nil
	if issecretvalue(now) then
		now = nil
	end

	self.state = L.Build(raw, self.excluded, now, issecretvalue)
	self:ManageLinger(self.state)
	self:Render()
end

function LootRolls:ToggleHistory()
	self.historyMode = not self.historyMode
	ns.Debug:Log("LootRolls", "history", self.historyMode)
	self:Render()
end

function LootRolls:Page(delta)
	if self.historyMode then
		self.historyIndex = (self.historyIndex or 1) + delta
	else
		self.pageIndex = (self.pageIndex or 1) + delta
	end
	self:Render()
end

function LootRolls:Scroll(delta)
	self.scrollOffset = math.max(0, (self.scrollOffset or 0) + delta)
	self:Render()
end

function LootRolls:OnClose()
	self.pinned = false
	self.testCount = nil
	self.dismissed = true
	ns.Debug:Log("LootRolls", "close")
	self:Render()
end

function LootRolls:Slash(arg)
	local action, n = L.ParseSlash(arg)
	if action == "toggle" then
		self.pinned = not self.pinned
		ns.Debug:Log("LootRolls", "slash", "pinned", self.pinned)
		self:Render()
	elseif action == "test" then
		self.testCount = n
		self.dismissed = false
		ns.Debug:Log("LootRolls", "slash", "test", n)
		self:Render()
	else
		ns.addon:Print("usage: /mui rolls, /mui rolls test [n]")
	end
end

function LootRolls:Layout()
	local profile = self.db.profile
	self.frame:SetSize(profile.width, profile.height)
	ns.Media:SetFont(self.link, profile.font, profile.fontSize, "")
	ns.Media:SetFont(self.status, profile.font, profile.fontSize, "")
	ns.Media:SetFont(self.pageText, profile.font, math.max(8, profile.fontSize - 1), "")
	setButtonFont(self.closeButton, profile.font, profile.fontSize)
	setButtonFont(self.historyToggle, profile.font, math.max(8, profile.fontSize - 1))
	setButtonFont(self.prevButton, profile.font, profile.fontSize)
	setButtonFont(self.nextButton, profile.font, profile.fontSize)
	for _, row in ipairs(self.rowPool) do
		self:StyleRow(row)
	end
end

function LootRolls:StyleRow(row)
	local profile = self.db.profile
	row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
	ns.Media:SetFont(row.name, profile.font, profile.fontSize, "")
	ns.Media:SetFont(row.count, profile.font, math.max(8, profile.fontSize - 2), "")
	ns.Media:SetFont(row.choice, profile.font, profile.fontSize, "")
	ns.Media:SetFont(row.tag, profile.font, math.max(8, profile.fontSize - 3), "")
	ns.Media:SetFont(row.roll, profile.font, profile.fontSize, "")
	setTextColor(row.count, C.textDim)
end

function LootRolls:GetRow(i)
	local row = self.rowPool[i]
	if row then
		return row
	end

	row = CreateFrame("Frame", nil, self.frame)
	row:SetHeight(ROW_HEIGHT)

	local winBg = row:CreateTexture(nil, "BACKGROUND")
	winBg:SetAllPoints()
	setColor(winBg, C.accent)
	winBg:SetAlpha(0.12)
	winBg:Hide()
	row.winBg = winBg

	local stripe = row:CreateTexture(nil, "ARTWORK")
	stripe:SetPoint("TOPLEFT", row, "TOPLEFT")
	stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
	stripe:SetWidth(2)
	setColor(stripe, C.accent)
	stripe:Hide()
	row.stripe = stripe

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.icon = icon

	local name = row:CreateFontString(nil, "OVERLAY")
	name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	row.name = name

	local count = row:CreateFontString(nil, "OVERLAY")
	count:SetPoint("LEFT", name, "RIGHT", 2, 0)
	row.count = count

	local roll = row:CreateFontString(nil, "OVERLAY")
	roll:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	roll:SetJustifyH("RIGHT")
	setTextColor(roll, C.text)
	row.roll = roll

	local tag = row:CreateFontString(nil, "OVERLAY")
	tag:SetPoint("RIGHT", roll, "LEFT", -4, 0)
	setTextColor(tag, C.textDim)
	row.tag = tag

	local choice = row:CreateFontString(nil, "OVERLAY")
	choice:SetPoint("RIGHT", tag, "LEFT", -4, 0)
	row.choice = choice

	self:StyleRow(row)
	self.rowPool[i] = row
	return row
end

function LootRolls:FillRow(row, roll, drop, state)
	local r, g, b = classColor(roll.class)
	setClassIcon(row.icon, roll.class)
	row.name:SetText(roll.name or "?")
	row.name:SetTextColor(r, g, b)

	row.count:SetText(L.CountText(L.WinCount(state, drop, roll)))

	local label, tag = L.Label(roll.state)
	row.choice:SetText(label)
	local color = STATE_COLOR[roll.state]
	if color then
		row.choice:SetTextColor(color[1], color[2], color[3])
	else
		row.choice:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
	end
	row.tag:SetText(tag or "")

	row.roll:SetText(roll.roll and tostring(roll.roll) or "")

	local isWinner = roll.isWinner == true
	if not isWinner and drop and drop.winner then
		local key = L.PlayerKey(roll)
		isWinner = key ~= nil and key == L.PlayerKey(drop.winner)
	end
	row.stripe:SetShown(isWinner)
	row.winBg:SetShown(isWinner)
end

function LootRolls:StartResize(button)
	if button ~= "LeftButton" then
		return
	end
	local frame = self.frame
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	local x, y = cursor(frame)
	self.resizeStart = { x = x, y = y, w = frame:GetWidth(), h = frame:GetHeight() }
	self.sizer:Show()
end

function LootRolls:UpdateResize()
	local frame = self.frame
	local start = self.resizeStart
	local x, y = cursor(frame)
	local dx, dy = x - start.x, start.y - y
	local w = math.max(MIN_W, math.min(MAX_W, start.w + dx))
	local h = math.max(MIN_H, math.min(MAX_H, start.h + dy))
	frame:SetSize(w, h)
end

function LootRolls:FinishResize()
	if not self.sizer:IsShown() then
		return
	end
	self.sizer:Hide()

	local frame = self.frame
	local profile = self.db.profile
	profile.width = math.floor(frame:GetWidth() + 0.5)
	profile.height = math.floor(frame:GetHeight() + 0.5)

	local cx, cy = frame:GetCenter()
	if cx then
		local x, y = MoverLogic.CenterOffset(
			cx,
			cy,
			frame:GetEffectiveScale(),
			UIParent:GetWidth(),
			UIParent:GetHeight(),
			UIParent:GetEffectiveScale()
		)
		profile.position.x = x
		profile.position.y = y
	end

	ns.Mover:Apply(frame)
	ns.Debug:Log("LootRolls", "resize", profile.width, profile.height)
	self:Render()
end

function LootRolls:Render()
	local state = self.state or { drops = {}, active = {}, wins = {}, total = 0 }
	local inRaid = IsInRaid()
	if issecretvalue(inRaid) then
		inRaid = false
	end
	local previewCount = self.testCount or (self.unlockPreview and (inRaid and 40 or 5) or nil)
	local previewing = previewCount ~= nil
	local renderState = previewing and L.Preview(previewCount) or state

	local inGroup = IsInGroup()
	if issecretvalue(inGroup) then
		inGroup = false
	end

	local visible = L.Visible({
		preview = previewing,
		pinned = self.pinned,
		dismissed = self.dismissed,
		inGroup = inGroup == true,
		active = #state.active,
		lingering = self.lingering == true,
	})
	self.lastVisible = visible

	if not visible then
		self.frame:Hide()
		for _, row in ipairs(self.rowPool) do
			row:Hide()
		end
		self.lastShown = 0
		return
	end
	self.frame:Show()

	local list
	if self.historyMode then
		list = renderState.drops
	elseif previewing then
		list = renderState.active
	else
		list = {}
		for _, drop in ipairs(renderState.drops) do
			if self.trackedKeys[drop.key] then
				list[#list + 1] = drop
			end
		end
	end
	local count = #list
	local index
	if self.historyMode then
		index = math.max(1, math.min(self.historyIndex or 1, math.max(1, count)))
		self.historyIndex = index
	else
		index = math.max(1, math.min(self.pageIndex or 1, math.max(1, count)))
		self.pageIndex = index
	end
	local drop = list[index]

	self.pageText:SetText((count > 0) and (index .. "/" .. count) or "0/0")
	self.historyToggle.label = self.historyMode and "History" or "Live"
	setButtonFont(self.historyToggle, self.db.profile.font, math.max(8, self.db.profile.fontSize - 1))

	if drop and drop.link then
		local _, _, _, _, icon = C_Item.GetItemInfoInstant(drop.link)
		if icon then
			self.icon:SetTexture(icon)
			self.icon:Show()
		else
			self.icon:Hide()
		end
		self.link:SetText(drop.link)
		self.linkHyperlink = drop.link
	else
		self.icon:Hide()
		self.link:SetText(previewing and "Preview" or "")
		self.linkHyperlink = nil
	end

	self.status:SetText(drop and L.Status(drop) or "")

	local rows = drop and drop.rolls or {}
	local profile = self.db.profile
	local capacity = math.max(0, math.floor((profile.height - TOP_RESERVED) / ROW_HEIGHT))
	local offset = math.max(0, math.min(self.scrollOffset or 0, math.max(0, #rows - capacity)))
	self.scrollOffset = offset

	local shown = math.max(0, math.min(capacity, #rows - offset))
	for i = 1, shown do
		local row = self:GetRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 1, -(TOP_RESERVED + (i - 1) * ROW_HEIGHT))
		row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -1, -(TOP_RESERVED + (i - 1) * ROW_HEIGHT))
		self:FillRow(row, rows[offset + i], drop, renderState)
		row:Show()
	end
	for i = shown + 1, #self.rowPool do
		self.rowPool[i]:Hide()
	end

	self.lastShown = shown
end

function LootRolls:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local hasApi, missingApi = L.HasApi(C_LootHistory)
				local missing = {}
				if not hasApi then
					for _, name in ipairs(missingApi) do
						table.insert(missing, "C_LootHistory." .. name)
					end
				end
				if type(GetInstanceInfo) ~= "function" then
					table.insert(missing, "GetInstanceInfo")
				end
				if type(IsInGroup) ~= "function" then
					table.insert(missing, "IsInGroup")
				end
				if type(IsInRaid) ~= "function" then
					table.insert(missing, "IsInRaid")
				end
				if type(C_Item) ~= "table" or type(C_Item.GetItemInfoInstant) ~= "function" then
					table.insert(missing, "C_Item.GetItemInfoInstant")
				end
				if type(CLASS_ICON_TCOORDS) ~= "table" then
					table.insert(missing, "CLASS_ICON_TCOORDS")
				end
				if type(RAID_CLASS_COLORS) ~= "table" then
					table.insert(missing, "RAID_CLASS_COLORS")
				end
				local legacy = type(C_LootHistory) == "table" and type(C_LootHistory.GetItem) == "function"
				if #missing > 0 then
					return "FAIL", "legacy=" .. tostring(legacy), unpack(missing, 1, #missing)
				end
				return "PASS", "legacy=" .. tostring(legacy)
			end,
		},
		{
			name = "enum",
			run = function()
				if type(Enum) ~= "table" or type(Enum.EncounterLootDropRollState) ~= "table" then
					return "FAIL", "Enum.EncounterLootDropRollState missing"
				end
				if not L.EnumMatches(Enum.EncounterLootDropRollState) then
					return "FAIL", "mismatch"
				end
				return "PASS"
			end,
		},
		{
			name = "logic",
			run = function()
				local ok, failed = selfTestLogic()
				return ok and "PASS" or "FAIL", failed
			end,
		},
		{
			name = "group",
			run = function()
				local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
				if issecretvalue(instanceType) then
					instanceType = "secret"
				end
				if issecretvalue(instanceID) then
					instanceID = "secret"
				end
				return "INFO", IsInGroup(), IsInRaid(), GetNumGroupMembers(), instanceID, instanceType
			end,
		},
		{
			name = "history",
			run = function()
				if not self.hasApi then
					return "SKIP", "C_LootHistory missing"
				end
				local state = self.state or { drops = {}, active = {} }
				local excludedCount = 0
				for _ in pairs(self.excluded or {}) do
					excludedCount = excludedCount + 1
				end
				local latest = state.drops[1]
				local now = C_LootHistory.GetLootHistoryTime()
				if issecretvalue(now) then
					now = "secret"
				end
				return "INFO",
					#(self.raw or {}),
					#state.drops,
					#state.active,
					excludedCount,
					now,
					latest and latest.startTime or nil,
					latest and latest.duration or nil
			end,
		},
		{
			name = "events",
			run = function()
				local names = {}
				for name in pairs(self.eventCounts) do
					table.insert(names, name)
				end
				table.sort(names)
				if #names == 0 then
					return "INFO", "none"
				end
				local parts = {}
				for _, name in ipairs(names) do
					table.insert(parts, name .. "=" .. self.eventCounts[name])
				end
				return "INFO", unpack(parts, 1, #parts)
			end,
		},
		{
			name = "frame",
			run = function()
				local profile = self.db.profile
				local capacity = math.max(0, math.floor((profile.height - TOP_RESERVED) / ROW_HEIGHT))
				local visibleRows = 0
				for _, row in ipairs(self.rowPool) do
					if row:IsShown() then
						visibleRows = visibleRows + 1
					end
				end
				local expected = self.lastShown or 0
				local ok = self.frame:IsShown() == (self.lastVisible == true)
					and visibleRows == expected
					and expected <= capacity
				return ok and "PASS" or "FAIL", self.frame:IsShown(), self.lastVisible, visibleRows, expected, capacity
			end,
		},
		{
			name = "size",
			run = function()
				local profile = self.db.profile
				local w, h = self.frame:GetWidth(), self.frame:GetHeight()
				if issecretvalue(w) or issecretvalue(h) then
					return "INFO", "secret"
				end
				local ok = math.abs(w - profile.width) <= 0.5 and math.abs(h - profile.height) <= 0.5
				return ok and "PASS" or "FAIL", w, h, profile.width, profile.height
			end,
		},
	}
end
