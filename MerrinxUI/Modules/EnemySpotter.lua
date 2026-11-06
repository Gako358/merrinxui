local addonName, ns = ...

local L = ns.EnemySpotterLogic
local C = ns.Theme.color

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local CLASS_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local HEADER_HEIGHT = 26
local BODY_PAD = 2
local TICK_INTERVAL = 1
local SOUND_THROTTLE = 2
local BANNER_HOLD = 3
local BANNER_FADE = 0.6
local TABS = { { id = "nearby", label = "Nearby" }, { id = "kos", label = "Kill list" } }
local SOURCES = { "nameplate", "target", "mouseover" }

local EnemySpotter = ns.addon:NewModule("EnemySpotter", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = true,
		width = 240,
		rows = 8,
		rowHeight = 20,
		fontSize = 12,
		font = "*",
		bgOpacity = 75,
		headerOpacity = 100,
		expire = 60,
		pauseInPvp = true,
		enemySound = "MerrinxUI Blip",
		kosSound = "MerrinxUI Alert",
		kosBanner = true,
		kosChat = true,
		tab = "nearby",
		position = { point = "CENTER", x = -400, y = 200 },
		bannerPosition = { point = "CENTER", x = 0, y = 220 },
	},
	global = {
		killList = {},
	},
}

local function setColor(tex, color)
	tex:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function setTextColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4])
end

local function hex(r, g, b)
	return string.format(
		"%02x%02x%02x",
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

local function classColor(class)
	local color = class and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return C.text[1], C.text[2], C.text[3]
end

local function coloredName(name, class)
	return "|cff" .. hex(classColor(class)) .. name .. "|r"
end

local function levelColor(level)
	local color
	if type(level) == "number" and level > 0 then
		color = GetCreatureDifficultyColor(level)
	end
	return ns.NameplateLogic.LevelColor(level, nil, color)
end

local function ReadEnemy(unit)
	if type(unit) ~= "string" then
		return nil
	end

	local exists = UnitExists(unit)
	if issecretvalue(exists) then
		return nil, "secret"
	end
	if not exists then
		return nil
	end

	local isPlayer = UnitIsPlayer(unit)
	local canAttack = UnitCanAttack("player", unit)
	local isEnemy = UnitIsEnemy("player", unit)
	if issecretvalue(isPlayer) or issecretvalue(canAttack) or issecretvalue(isEnemy) then
		return nil, "secret"
	end
	if isPlayer ~= true or not (canAttack == true or isEnemy == true) then
		return nil
	end

	local name = UnitName(unit)
	if issecretvalue(name) then
		return nil, "secret"
	end
	if type(name) ~= "string" or name == UNKNOWNOBJECT then
		return nil
	end

	local className, class = UnitClass(unit)
	local level = UnitLevel(unit)
	if issecretvalue(className) then
		className = nil
	end
	if issecretvalue(class) then
		class = nil
	end
	if issecretvalue(level) then
		level = nil
	end

	return { name = name, class = class, className = className, level = level }
end

function EnemySpotter:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("EnemySpotter", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	self.killList = self.db.global.killList
	self.nearby = {}
	self.rows = {}
	self.offset = { nearby = 0, kos = 0 }
	self.stats = { nameplate = 0, target = 0, mouseover = 0, secret = 0, alerts = 0, kosAlerts = 0 }

	self:CreateWindow()
	self:CreateBanner()
end

function EnemySpotter:OnEnable()
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnNamePlateAdded")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "OnMouseover")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")

	self.ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
		self:OnTick()
	end)

	self:UpdatePaused()
	self:Layout()
	ns.Mover:Apply(self.frame)
	ns.Mover:Apply(self.banner)
	self.frame:Show()
	self:Rescan()
	self:Redraw()
end

function EnemySpotter:OnDisable()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	for key in pairs(self.nearby) do
		self.nearby[key] = nil
	end
	self.bannerFade:Stop()
	self.banner:Hide()
	self.frame:Hide()
end

function EnemySpotter:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:UpdatePaused()
			self:Layout()
			ns.Mover:Apply(self.frame)
			ns.Mover:Apply(self.banner)
			self:Redraw()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function EnemySpotter:OnMediaChanged(_, mediatype, key)
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", self.db.profile.font)) then
		self:Layout()
		self:Redraw()
	end
end

function EnemySpotter:UpdatePaused()
	local _, instanceType = IsInInstance()
	if issecretvalue(instanceType) then
		instanceType = nil
	end
	local paused = self.db.profile.pauseInPvp and (instanceType == "pvp" or instanceType == "arena") or false
	if paused ~= self.paused then
		self.paused = paused
		ns.Debug:Log("EnemySpotter", "paused", paused)
	end
end

function EnemySpotter:OnNamePlateAdded(_, unit)
	self:Spot(unit, "nameplate")
end

function EnemySpotter:OnTargetChanged()
	self:Spot("target", "target")
end

function EnemySpotter:OnMouseover()
	self:Spot("mouseover", "mouseover")
end

function EnemySpotter:OnEnteringWorld()
	for key in pairs(self.nearby) do
		self.nearby[key] = nil
	end
	self:UpdatePaused()
	self:Rescan()
	self:Redraw()
end

function EnemySpotter:Rescan()
	if self.paused then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		self:Spot(plate.unitToken, "nameplate")
	end
	self:Spot("target", "target")
end

function EnemySpotter:OnTick()
	self:Rescan()
	L.Prune(self.nearby, GetTime(), self.db.profile.expire)
	self:Redraw()
end

function EnemySpotter:Spot(unit, source)
	if self.paused then
		return
	end

	local info, reason = ReadEnemy(unit)
	if not info then
		if reason == "secret" then
			self.stats.secret = self.stats.secret + 1
		end
		return
	end

	local entry, isNew, key = L.Spot(self.nearby, info, GetTime(), self.db.profile.expire)
	if not entry then
		return
	end

	local kos = self.killList[key]
	if kos then
		kos.class = info.class or kos.class
		kos.lastSeen = time()
	end

	if isNew then
		self.stats[source] = self.stats[source] + 1
		ns.Debug:Log("EnemySpotter", "spot", source, kos and "kos" or "enemy")
		self:Alert(entry, kos ~= nil)
		self:RequestRedraw()
	end
end

function EnemySpotter:Alert(entry, kos)
	local profile = self.db.profile
	local now = GetTime()

	if kos then
		self.stats.kosAlerts = self.stats.kosAlerts + 1
		self.lastSound = now
		ns.Media:PlaySound(profile.kosSound)
		if profile.kosBanner then
			self:ShowBanner(entry)
		end
		if profile.kosChat then
			local detail = L.Detail(entry.level, entry.className)
			ns.addon:Print(
				"|cff"
					.. hex(C.error[1], C.error[2], C.error[3])
					.. "Kill on sight:|r "
					.. coloredName(entry.name, entry.class)
					.. ((detail ~= "") and (" (" .. detail .. ")") or "")
			)
		end
		return
	end

	self.stats.alerts = self.stats.alerts + 1
	if now - (self.lastSound or -SOUND_THROTTLE) >= SOUND_THROTTLE then
		self.lastSound = now
		ns.Media:PlaySound(profile.enemySound)
	end
end

function EnemySpotter:KosCount()
	local count = 0
	for _ in pairs(self.killList) do
		count = count + 1
	end
	return count
end

function EnemySpotter:KillListChanged()
	self:RequestRedraw()
	LibStub("AceConfigRegistry-3.0"):NotifyChange("MerrinxUI")
end

function EnemySpotter:AddKos(name)
	local key, added = L.Add(self.killList, name, time())
	if key == nil then
		ns.addon:Print("Kill list: enter a single player name")
		return false
	end

	local entry = self.killList[key]
	if added then
		local near = self.nearby[key]
		if near then
			entry.class = near.class
			entry.lastSeen = time()
		end
		ns.addon:Print("Added " .. coloredName(entry.name, entry.class) .. " to the kill list")
		ns.Debug:Log("EnemySpotter", "kos add", self:KosCount())
	else
		ns.addon:Print(entry.name .. " is already on the kill list")
	end
	self:KillListChanged()
	return added
end

function EnemySpotter:RemoveKos(name)
	local display = L.DisplayName(name)
	if not L.Remove(self.killList, name) then
		ns.addon:Print((display or tostring(name)) .. " is not on the kill list")
		return false
	end
	ns.addon:Print("Removed " .. display .. " from the kill list")
	ns.Debug:Log("EnemySpotter", "kos remove", self:KosCount())
	self:KillListChanged()
	return true
end

function EnemySpotter:AddTargetKos()
	local isPlayer = UnitIsPlayer("target")
	local name = UnitName("target")
	if issecretvalue(isPlayer) or issecretvalue(name) then
		ns.addon:Print("Kill list: the target can't be read right now")
		return false
	end
	if isPlayer ~= true or type(name) ~= "string" or UnitIsUnit("target", "player") then
		ns.addon:Print("Kill list: target a player first")
		return false
	end
	return self:AddKos(name)
end

function EnemySpotter:Slash(arg)
	local remove = arg:match("^remove%s+(.+)$")
	if remove then
		self:RemoveKos(remove)
	elseif arg == "" then
		self:AddTargetKos()
	else
		self:AddKos(arg)
	end
end

function EnemySpotter:CreateWindow()
	local frame = CreateFrame("Frame", "MerrinxUIEnemySpotter", UIParent, "BackdropTemplate")
	frame:Hide()
	frame:SetClampedToScreen(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		self:Scroll(-delta)
	end)
	frame:SetBackdrop({ edgeFile = TEXTURE, edgeSize = 1 })
	frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], C.border[4])
	self.frame = frame

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 1)
	self.bg = bg

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT")
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT")

	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	headerBg:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
	self.headerBg = headerBg

	local divider = header:CreateTexture(nil, "BORDER")
	divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
	divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
	divider:SetHeight(1)
	setColor(divider, C.border)

	local alertDot = header:CreateTexture(nil, "ARTWORK")
	alertDot:SetSize(6, 6)
	alertDot:SetPoint("RIGHT", header, "RIGHT", -10, 0)
	setColor(alertDot, C.error)
	alertDot:Hide()
	self.alertDot = alertDot

	local pulse = alertDot:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local pulseAlpha = pulse:CreateAnimation("Alpha")
	pulseAlpha:SetFromAlpha(1)
	pulseAlpha:SetToAlpha(0.2)
	pulseAlpha:SetDuration(0.6)
	self.alertPulse = pulse

	self.tabs = {}
	local prev
	for _, def in ipairs(TABS) do
		local id = def.id
		local tab = CreateFrame("Button", nil, header)
		tab:SetHeight(HEADER_HEIGHT)
		tab.id = id

		local label = tab:CreateFontString(nil, "OVERLAY")
		label:SetPoint("CENTER", tab, "CENTER", 0, 1)
		tab.label = label

		local underline = tab:CreateTexture(nil, "ARTWORK")
		underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, 0)
		underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 0)
		underline:SetHeight(2)
		setColor(underline, C.accent)
		tab.underline = underline

		tab:SetScript("OnClick", function()
			self:SelectTab(id)
		end)
		tab:SetScript("OnEnter", function()
			setTextColor(label, C.text)
		end)
		tab:SetScript("OnLeave", function()
			setTextColor(label, (self.db.profile.tab == id) and C.text or C.textDim)
		end)

		if prev then
			tab:SetPoint("LEFT", prev, "RIGHT", 0, 0)
		else
			tab:SetPoint("LEFT", header, "LEFT", 4, 0)
		end
		prev = tab
		self.tabs[id] = tab
	end

	self:CreateInput()

	local empty = frame:CreateFontString(nil, "OVERLAY")
	empty:SetJustifyH("CENTER")
	setTextColor(empty, C.textDim)
	self.empty = empty

	ns.Mover:Register(frame, "Enemy Spotter", function()
		return self.db.profile.position
	end)
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

function EnemySpotter:CreateInput()
	local input = CreateFrame("Frame", nil, self.frame)
	self.input = input

	local targetButton = createButton(input, "Target", function()
		self:AddTargetKos()
	end)
	targetButton:SetPoint("TOPRIGHT", input, "TOPRIGHT", -4, -2)
	targetButton:SetPoint("BOTTOMRIGHT", input, "BOTTOMRIGHT", -4, 2)
	input.targetButton = targetButton

	local addButton = createButton(input, "Add", nil)
	addButton:SetPoint("TOPRIGHT", targetButton, "TOPLEFT", -3, 0)
	addButton:SetPoint("BOTTOMRIGHT", targetButton, "BOTTOMLEFT", -3, 0)
	input.addButton = addButton

	local edit = CreateFrame("EditBox", nil, input)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(48)
	edit:SetTextInsets(6, 6, 0, 0)
	edit:SetPoint("TOPLEFT", input, "TOPLEFT", 4, -2)
	edit:SetPoint("BOTTOMRIGHT", addButton, "BOTTOMLEFT", -3, 0)
	input.edit = edit

	local editBg = edit:CreateTexture(nil, "BACKGROUND")
	editBg:SetAllPoints()
	setColor(editBg, C.field)

	local editLine = edit:CreateTexture(nil, "BORDER")
	editLine:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT")
	editLine:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT")
	editLine:SetHeight(1)
	setColor(editLine, C.fieldBorder)

	local placeholder = edit:CreateFontString(nil, "OVERLAY")
	placeholder:SetPoint("LEFT", edit, "LEFT", 6, 0)
	setTextColor(placeholder, C.textDim)
	input.placeholder = placeholder

	local function submit()
		local text = edit:GetText()
		if text ~= "" and self:AddKos(text) then
			edit:SetText("")
		end
		edit:ClearFocus()
	end
	addButton:SetScript("OnClick", submit)

	edit:SetScript("OnEnterPressed", submit)
	edit:SetScript("OnEscapePressed", function()
		edit:SetText("")
		edit:ClearFocus()
	end)
	edit:SetScript("OnTextChanged", function()
		placeholder:SetShown(edit:GetText() == "")
	end)
	edit:SetScript("OnEditFocusGained", function()
		setColor(editLine, C.accent)
	end)
	edit:SetScript("OnEditFocusLost", function()
		setColor(editLine, C.fieldBorder)
	end)
end

function EnemySpotter:CreateBanner()
	local banner = CreateFrame("Frame", "MerrinxUIEnemySpotterBanner", UIParent, "BackdropTemplate")
	banner:SetSize(320, 46)
	banner:SetFrameStrata("HIGH")
	banner:SetBackdrop({ bgFile = TEXTURE, edgeFile = TEXTURE, edgeSize = 1 })
	banner:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.94)
	banner:SetBackdropBorderColor(C.error[1], C.error[2], C.error[3], 0.5)
	banner:Hide()
	self.banner = banner

	local bar = banner:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("TOPLEFT", banner, "TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 1, 1)
	bar:SetWidth(3)
	setColor(bar, C.error)

	local icon = banner:CreateTexture(nil, "ARTWORK")
	icon:SetSize(30, 30)
	icon:SetPoint("LEFT", banner, "LEFT", 12, 0)
	banner.icon = icon

	local caption = banner:CreateFontString(nil, "OVERLAY")
	caption:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
	setTextColor(caption, C.error)
	banner.caption = caption

	local name = banner:CreateFontString(nil, "OVERLAY")
	name:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 0)
	banner.name = name

	local detail = banner:CreateFontString(nil, "OVERLAY")
	detail:SetPoint("RIGHT", banner, "RIGHT", -12, 0)
	detail:SetJustifyH("RIGHT")
	setTextColor(detail, C.textDim)
	banner.detail = detail

	local fade = banner:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0)
	alpha:SetDuration(BANNER_FADE)
	alpha:SetStartDelay(BANNER_HOLD)
	fade:SetScript("OnFinished", function()
		banner:Hide()
	end)
	self.bannerFade = fade

	ns.Mover:Register(banner, "Kill on sight alert", function()
		return self.db.profile.bannerPosition
	end)
end

function EnemySpotter:SetClassIcon(texture, class)
	local coords = class and CLASS_ICON_TCOORDS[class]
	if coords then
		texture:SetTexture(CLASS_TEXTURE)
		texture:SetTexCoord(ns.DamageMeterLogic.IconCoords(coords, 0.06))
		texture:Show()
	else
		texture:Hide()
	end
end

function EnemySpotter:ShowBanner(entry)
	local banner = self.banner
	local font = self.db.profile.font
	ns.Media:SetFont(banner.caption, font, 10, "")
	ns.Media:SetFont(banner.name, font, 16, "")
	ns.Media:SetFont(banner.detail, font, 12, "")

	banner.caption:SetText("KILL ON SIGHT")
	banner.name:SetText(entry.name)
	banner.name:SetTextColor(classColor(entry.class))
	banner.detail:SetText(L.Detail(entry.level, entry.className))
	self:SetClassIcon(banner.icon, entry.class)

	self.bannerFade:Stop()
	banner:SetAlpha(1)
	banner:Show()
	self.bannerFade:Play()
	self.bannerShown = (self.bannerShown or 0) + 1
end

function EnemySpotter:StyleRow(row)
	local profile = self.db.profile
	local h = profile.rowHeight
	row:SetSize(profile.width - 2, h)
	row.icon:SetSize(h - 6, h - 6)
	row.remove:SetSize(h, h)
	ns.Media:SetFont(row.name, profile.font, profile.fontSize, "")
	ns.Media:SetFont(row.tag, profile.font, math.max(8, profile.fontSize - 3), "")
	ns.Media:SetFont(row.level, profile.font, profile.fontSize - 1, "")
	ns.Media:SetFont(row.ago, profile.font, profile.fontSize - 1, "")
	setButtonFont(row.remove, profile.font, profile.fontSize)
end

function EnemySpotter:GetRow(i)
	local row = self.rows[i]
	if row then
		return row
	end

	row = CreateFrame("Button", nil, self.frame)
	row:RegisterForClicks("RightButtonUp")

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	setColor(bg, (i % 2 == 1) and C.rowA or C.rowB)

	local hover = row:CreateTexture(nil, "BORDER")
	hover:SetAllPoints()
	setColor(hover, C.hover)
	hover:Hide()

	local stripe = row:CreateTexture(nil, "ARTWORK")
	stripe:SetPoint("TOPLEFT", row, "TOPLEFT")
	stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
	stripe:SetWidth(2)
	row.stripe = stripe

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("LEFT", row, "LEFT", 7, 0)
	row.icon = icon

	local name = row:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	row.name = name

	local tag = row:CreateFontString(nil, "OVERLAY")
	tag:SetPoint("LEFT", name, "RIGHT", 5, 0)
	row.tag = tag

	local remove = createButton(row, "x", function()
		if row.key then
			self:RemoveKos(row.key)
		end
	end)
	remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	remove:HookScript("OnEnter", function()
		setTextColor(remove.text, C.error)
	end)
	remove:HookScript("OnLeave", function()
		setTextColor(remove.text, C.textDim)
	end)
	setTextColor(remove.text, C.textDim)
	row.remove = remove

	local ago = row:CreateFontString(nil, "OVERLAY")
	ago:SetJustifyH("RIGHT")
	setTextColor(ago, C.textDim)
	row.ago = ago

	local level = row:CreateFontString(nil, "OVERLAY")
	level:SetJustifyH("RIGHT")
	row.level = level

	row:SetScript("OnEnter", function()
		hover:Show()
		self:ShowRowTooltip(row)
	end)
	row:SetScript("OnLeave", function()
		hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function()
		self:OpenRowMenu(row)
	end)

	self:StyleRow(row)
	self.rows[i] = row
	return row
end

function EnemySpotter:ShowRowTooltip(row)
	local item = row.item
	if not item then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(item.name, classColor(item.class))
	local detail = L.Detail(item.level, item.className)
	if detail ~= "" then
		GameTooltip:AddLine(detail, 1, 1, 1)
	end
	if item.kos then
		GameTooltip:AddLine("Kill on sight", C.error[1], C.error[2], C.error[3])
	end
	if item.seen then
		GameTooltip:AddLine("Last seen: " .. item.seen, C.textDim[1], C.textDim[2], C.textDim[3])
	end
	GameTooltip:AddLine("Right-click for options", C.textDim[1], C.textDim[2], C.textDim[3])
	GameTooltip:Show()
end

function EnemySpotter:OpenRowMenu(row)
	local item = row.item
	if not item then
		return
	end
	MenuUtil.CreateContextMenu(row, function(_, root)
		if self.killList[item.key] then
			root:CreateButton("Remove from kill list", function()
				self:RemoveKos(item.key)
			end)
		else
			root:CreateButton("Add to kill list", function()
				self:AddKos(item.name)
			end)
		end
	end)
end

function EnemySpotter:SelectTab(id)
	self.db.profile.tab = id
	self.input.edit:ClearFocus()
	ns.Debug:Log("EnemySpotter", "tab", id)
	self:Redraw()
end

function EnemySpotter:Scroll(delta)
	local tab = self.db.profile.tab
	self.offset[tab] = math.max(0, (self.offset[tab] or 0) + delta)
	self:Redraw()
end

function EnemySpotter:Capacity()
	local rows = self.db.profile.rows
	if self.db.profile.tab == "kos" then
		return rows - 1
	end
	return rows
end

function EnemySpotter:WindowHeight()
	local profile = self.db.profile
	return HEADER_HEIGHT + profile.rows * profile.rowHeight + 2 * BODY_PAD
end

function EnemySpotter:Layout()
	local profile = self.db.profile
	local frame = self.frame

	frame:SetSize(profile.width, self:WindowHeight())
	self.bg:SetAlpha(profile.bgOpacity / 100)
	self.headerBg:SetAlpha(profile.headerOpacity / 100)

	for _, tab in pairs(self.tabs) do
		ns.Media:SetFont(tab.label, profile.font, 12, "")
	end

	local input = self.input
	input:ClearAllPoints()
	input:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(HEADER_HEIGHT + BODY_PAD))
	input:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -(HEADER_HEIGHT + BODY_PAD))
	input:SetHeight(profile.rowHeight)
	input.edit:SetFont(ns.Media:FontPath(profile.font), profile.fontSize, "")
	ns.Media:SetFont(input.placeholder, profile.font, profile.fontSize, "")
	input.placeholder:SetText("Add player name...")
	for _, button in ipairs({ input.addButton, input.targetButton }) do
		setButtonFont(button, profile.font, profile.fontSize - 1)
		button:SetWidth(button.text:GetStringWidth() + 14)
	end

	ns.Media:SetFont(self.empty, profile.font, profile.fontSize, "")
	self.empty:ClearAllPoints()
	self.empty:SetPoint("TOP", frame, "TOP", 0, -(HEADER_HEIGHT + BODY_PAD + profile.rowHeight * 2))

	for _, row in ipairs(self.rows) do
		self:StyleRow(row)
	end
end

function EnemySpotter:RequestRedraw()
	if self.redrawPending then
		return
	end
	self.redrawPending = true
	C_Timer.After(0, function()
		self.redrawPending = false
		self:Redraw()
	end)
end

function EnemySpotter:Items(tab)
	local now = GetTime()
	local items = {}

	if tab == "kos" then
		local wallNow = time()
		for _, item in ipairs(L.Sorted(self.killList)) do
			local near = self.nearby[item.key]
			local entry = item.entry
			local seen
			if near then
				seen = L.Ago(now - near.lastSeen)
			elseif entry.lastSeen then
				seen = L.Ago(wallNow - entry.lastSeen)
			end
			items[#items + 1] = {
				key = item.key,
				name = entry.name,
				class = (near and near.class) or entry.class,
				className = near and near.className,
				level = near and near.level,
				kos = true,
				nearby = near ~= nil,
				seen = seen,
				removable = true,
			}
		end
		return items
	end

	for _, row in
		ipairs(L.Rows(self.nearby, function(key)
			return self.killList[key] ~= nil
		end))
	do
		local entry = row.entry
		items[#items + 1] = {
			key = row.key,
			name = entry.name,
			class = entry.class,
			className = entry.className,
			level = entry.level,
			kos = row.kos,
			nearby = true,
			seen = L.Ago(now - entry.lastSeen),
		}
	end
	return items
end

function EnemySpotter:RedrawTabs(nearbyCount, kosNearby)
	local profile = self.db.profile
	local countColor = (kosNearby > 0) and C.error or C.accent
	local counts = {
		nearby = "|cff" .. hex(countColor[1], countColor[2], countColor[3]) .. nearbyCount .. "|r",
		kos = "|cff" .. hex(C.textDim[1], C.textDim[2], C.textDim[3]) .. self:KosCount() .. "|r",
	}

	for _, def in ipairs(TABS) do
		local tab = self.tabs[def.id]
		local active = profile.tab == def.id
		tab.label:SetText(def.label .. "  " .. counts[def.id])
		setTextColor(tab.label, active and C.text or C.textDim)
		tab.underline:SetShown(active)
		tab:SetWidth(tab.label:GetStringWidth() + 16)
	end

	local alerting = kosNearby > 0
	self.alertDot:SetShown(alerting)
	if alerting and not self.alertPulse:IsPlaying() then
		self.alertPulse:Play()
	elseif not alerting and self.alertPulse:IsPlaying() then
		self.alertPulse:Stop()
	end
end

function EnemySpotter:Redraw()
	if not self:IsEnabled() then
		return
	end

	local profile = self.db.profile
	local tab = profile.tab
	local items = self:Items(tab)

	local nearbyCount, kosNearby = 0, 0
	for key in pairs(self.nearby) do
		nearbyCount = nearbyCount + 1
		if self.killList[key] then
			kosNearby = kosNearby + 1
		end
	end
	self:RedrawTabs(nearbyCount, kosNearby)

	local isKosTab = tab == "kos"
	self.input:SetShown(isKosTab)

	local capacity = self:Capacity()
	local offset = L.ClampOffset(self.offset[tab] or 0, #items, capacity)
	self.offset[tab] = offset
	local shown = math.max(0, math.min(capacity, #items - offset))
	local top = HEADER_HEIGHT + BODY_PAD + (isKosTab and profile.rowHeight or 0)

	for i = 1, shown do
		local item = items[offset + i]
		local row = self:GetRow(i)
		row.item = item
		row.key = item.key
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 1, -(top + (i - 1) * profile.rowHeight))

		local r, g, b = classColor(item.class)
		if item.kos and item.nearby then
			setColor(row.stripe, C.error)
		elseif item.kos then
			row.stripe:SetColorTexture(C.error[1], C.error[2], C.error[3], 0.35)
		else
			row.stripe:SetColorTexture(r, g, b, 1)
		end

		self:SetClassIcon(row.icon, item.class)
		row.name:ClearAllPoints()
		if row.icon:IsShown() then
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
		else
			row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
		end
		row.name:SetText(item.name)
		row.name:SetTextColor(r, g, b)

		if isKosTab and item.nearby then
			row.tag:SetText("NEARBY")
			setTextColor(row.tag, C.error)
		elseif not isKosTab and item.kos then
			row.tag:SetText("KOS")
			setTextColor(row.tag, C.error)
		else
			row.tag:SetText("")
		end

		row.remove:SetShown(item.removable == true)
		row.ago:ClearAllPoints()
		if item.removable then
			row.ago:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
		else
			row.ago:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		end
		row.ago:SetText(item.seen or (isKosTab and "never" or ""))

		row.level:ClearAllPoints()
		row.level:SetPoint("RIGHT", row.ago, "LEFT", -8, 0)
		row.level:SetText(L.LevelText(item.level))
		row.level:SetTextColor(levelColor(item.level))

		row:Show()
	end

	for i = shown + 1, #self.rows do
		self.rows[i].item = nil
		self.rows[i].key = nil
		self.rows[i]:Hide()
	end

	if #items == 0 then
		if isKosTab then
			self.empty:SetText("Kill list is empty")
		elseif self.paused then
			self.empty:SetText("Paused in battlegrounds and arenas")
		else
			self.empty:SetText("No enemies nearby")
		end
		self.empty:Show()
	else
		self.empty:Hide()
	end

	self.lastItems = #items
	self.lastShown = shown
end

function EnemySpotter:TestAlert()
	local _, class = UnitClass("player")
	local level = UnitLevel("player")
	if issecretvalue(class) then
		class = nil
	end
	if issecretvalue(level) then
		level = nil
	end
	local entry = { name = "Testplayer", class = class, level = level }
	ns.Media:PlaySound(self.db.profile.kosSound)
	self:ShowBanner(entry)
end

function EnemySpotter:GetOptions()
	local function option(key, extra)
		extra.get = extra.get or function()
			return self.db.profile[key]
		end
		extra.set = extra.set or function(_, value)
			self.db.profile[key] = value
			self:Refresh()
		end
		return extra
	end

	local function soundOption(key, name, order)
		return option(key, {
			type = "select",
			name = name,
			order = order,
			values = function()
				return ns.Media:SoundValues()
			end,
			set = function(_, value)
				self.db.profile[key] = value
				ns.Media:PlaySound(value)
			end,
		})
	end

	return {
		type = "group",
		name = "EnemySpotter",
		args = {
			enabled = option("enabled", { type = "toggle", name = "Enabled", order = 1 }),
			windowHeader = { type = "header", name = "Window", order = 2 },
			width = option("width", { type = "range", name = "Width", order = 3, min = 160, max = 400, step = 1 }),
			rows = option("rows", { type = "range", name = "Rows", order = 4, min = 3, max = 20, step = 1 }),
			rowHeight = option(
				"rowHeight",
				{ type = "range", name = "Row height", order = 5, min = 16, max = 32, step = 1 }
			),
			fontSize = option(
				"fontSize",
				{ type = "range", name = "Font size", order = 6, min = 9, max = 20, step = 1 }
			),
			font = option("font", {
				type = "select",
				name = "Font",
				order = 7,
				dialogControl = "LSM30_Font",
				values = function()
					return ns.Media:Values("font", self.db.profile.font)
				end,
			}),
			bgOpacity = option(
				"bgOpacity",
				{ type = "range", name = "Background opacity", order = 8, min = 0, max = 100, step = 5 }
			),
			headerOpacity = option(
				"headerOpacity",
				{ type = "range", name = "Header opacity", order = 9, min = 0, max = 100, step = 5 }
			),
			detectionHeader = { type = "header", name = "Detection", order = 10 },
			expire = option("expire", {
				type = "range",
				name = "Forget after (seconds)",
				desc = "An enemy leaves the Nearby list after this long without being seen",
				order = 11,
				min = 10,
				max = 600,
				step = 10,
			}),
			pauseInPvp = option("pauseInPvp", {
				type = "toggle",
				name = "Pause in battlegrounds and arenas",
				order = 12,
			}),
			enemySound = soundOption("enemySound", "Enemy sound", 13),
			kosHeader = { type = "header", name = "Kill on sight", order = 20 },
			kosSound = soundOption("kosSound", "Kill on sight sound", 21),
			kosBanner = option("kosBanner", { type = "toggle", name = "Show alert banner", order = 22 }),
			kosChat = option("kosChat", { type = "toggle", name = "Print to chat", order = 23 }),
			testAlert = {
				type = "execute",
				name = "Test alert",
				order = 24,
				func = function()
					self:TestAlert()
				end,
			},
			addKos = {
				type = "input",
				name = "Add player",
				desc = "Type a player name and press Enter",
				order = 25,
				get = function()
					return ""
				end,
				set = function(_, value)
					if value ~= "" then
						self:AddKos(value)
					end
				end,
			},
			addTarget = {
				type = "execute",
				name = "Add target",
				order = 26,
				func = function()
					self:AddTargetKos()
				end,
			},
			removeKos = {
				type = "select",
				name = "Remove player",
				order = 27,
				values = function()
					local values = {}
					for key, entry in pairs(self.killList) do
						values[key] = entry.name
					end
					return values
				end,
				get = function()
					return nil
				end,
				set = function(_, value)
					self:RemoveKos(value)
				end,
			},
			kosInfo = {
				type = "description",
				order = 28,
				name = function()
					return "Kill list: "
						.. self:KosCount()
						.. " players, shared by all characters. Also: /mui kos (target), /mui kos <name>,"
						.. " /mui kos remove <name>."
				end,
			},
		},
	}
end

local function selfTestLogic()
	local list = {}
	local key, added = L.Add(list, "  tESTER-Realm ", 1)
	if key ~= "tester" or not added or list.tester.name ~= "Tester" then
		return false, "add"
	end
	if L.Find(list, "TESTER") ~= list.tester then
		return false, "find"
	end

	local nearby = {}
	local _, isNew = L.Spot(nearby, { name = "Tester", class = "ROGUE", level = 60 }, 100, 60)
	local _, isRefresh = L.Spot(nearby, { name = "tester" }, 150, 60)
	local _, isExpired = L.Spot(nearby, { name = "Tester" }, 300, 60)
	if not isNew or isRefresh or not isExpired or nearby.tester.class ~= "ROGUE" then
		return false, "spot"
	end

	L.Spot(nearby, { name = "Other" }, 310, 60)
	local rows = L.Rows(nearby, function(k)
		return list[k] ~= nil
	end)
	if rows[1].key ~= "tester" or not rows[1].kos then
		return false, "rows"
	end
	if L.Prune(nearby, 1000, 60) ~= 2 then
		return false, "prune"
	end
	if not L.Remove(list, "Tester") or next(list) ~= nil then
		return false, "remove"
	end
	return true
end

function EnemySpotter:GetDebugChecks()
	local function running(ctx)
		if ctx.enabled == false then
			return "SKIP", "module disabled"
		end
		if self.paused then
			return "SKIP", "paused"
		end
		return nil
	end

	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function check(path, value)
					if type(value) ~= "function" then
						table.insert(missing, path)
					end
				end
				check("C_NamePlate.GetNamePlates", type(C_NamePlate) == "table" and C_NamePlate.GetNamePlates)
				check("UnitIsEnemy", UnitIsEnemy)
				check("UnitCanAttack", UnitCanAttack)
				check("UnitIsPlayer", UnitIsPlayer)
				check("UnitName", UnitName)
				check("UnitClass", UnitClass)
				check("UnitLevel", UnitLevel)
				check("IsInInstance", IsInInstance)
				check("GetCreatureDifficultyColor", GetCreatureDifficultyColor)
				check("MenuUtil.CreateContextMenu", type(MenuUtil) == "table" and MenuUtil.CreateContextMenu)
				check("time", time)
				if type(CLASS_ICON_TCOORDS) ~= "table" then
					table.insert(missing, "CLASS_ICON_TCOORDS")
				end
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
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
			name = "kill list",
			run = function()
				local count, withClass, seen, badKeys = 0, 0, 0, 0
				for key, entry in pairs(self.killList) do
					count = count + 1
					if entry.class then
						withClass = withClass + 1
					end
					if entry.lastSeen then
						seen = seen + 1
					end
					if type(entry.name) ~= "string" or L.Key(entry.name) ~= key then
						badKeys = badKeys + 1
					end
				end
				if badKeys > 0 then
					return "FAIL", "bad keys", badKeys, count
				end
				return "PASS", count, withClass, seen
			end,
		},
		{
			name = "paused",
			run = function()
				local _, instanceType = IsInInstance()
				return "INFO", self.paused, instanceType, self.db.profile.pauseInPvp
			end,
		},
		{
			name = "ticker",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return (self.ticker and not self.ticker:IsCancelled()) and "PASS" or "FAIL"
			end,
		},
		{
			name = "detections",
			run = function()
				local parts = {}
				for _, source in ipairs(SOURCES) do
					table.insert(parts, source .. "=" .. self.stats[source])
				end
				return "INFO",
					table.concat(parts, " "),
					"secret=" .. self.stats.secret,
					"alerts=" .. self.stats.alerts,
					"kos=" .. self.stats.kosAlerts,
					"banners=" .. (self.bannerShown or 0)
			end,
		},
		{
			name = "nearby",
			run = function(ctx)
				local skip, reason = running(ctx)
				if skip then
					return skip, reason
				end
				local now = GetTime()
				local count, kos, stale = 0, 0, 0
				for key, entry in pairs(self.nearby) do
					count = count + 1
					if self.killList[key] then
						kos = kos + 1
					end
					if now - entry.lastSeen > self.db.profile.expire + 2 * TICK_INTERVAL then
						stale = stale + 1
					end
				end
				if stale > 0 then
					return "FAIL", "stale", stale, count
				end
				return "PASS", count, kos
			end,
		},
		{
			name = "plates",
			run = function(ctx)
				local skip, reason = running(ctx)
				if skip then
					return skip, reason
				end
				local plates, enemies, tracked, secret = 0, 0, 0, 0
				for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
					plates = plates + 1
					local info, why = ReadEnemy(plate.unitToken)
					if info then
						enemies = enemies + 1
						if self.nearby[L.Key(info.name)] then
							tracked = tracked + 1
						end
					elseif why == "secret" then
						secret = secret + 1
					end
				end
				if enemies == 0 then
					return "SKIP", "no enemy player plates", plates, secret
				end
				return (tracked == enemies) and "PASS" or "FAIL", plates, enemies, tracked, secret
			end,
		},
		{
			name = "target",
			run = function(ctx)
				local skip, reason = running(ctx)
				if skip then
					return skip, reason
				end
				if not ctx.hasTarget then
					return "SKIP", "no target"
				end
				local info, why = ReadEnemy("target")
				if why == "secret" then
					return "INFO", "secret"
				end
				if not info then
					return "SKIP", "target is not an enemy player"
				end
				local key = L.Key(info.name)
				local entry = self.nearby[key]
				local kos = self.killList[key] ~= nil
				local shown = false
				for _, row in ipairs(self.rows) do
					if row:IsShown() and row.key == key then
						shown = true
					end
				end
				return entry and "PASS" or "FAIL", "tracked", entry ~= nil, "kos", kos, "row", shown, info.class
			end,
		},
		{
			name = "window",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local profile = self.db.profile
				local w, h = self.frame:GetWidth(), self.frame:GetHeight()
				local ok = self.frame:IsShown()
					and math.abs(w - profile.width) <= 0.5
					and math.abs(h - self:WindowHeight()) <= 0.5
				return ok and "PASS" or "FAIL", profile.tab, w, h
			end,
		},
		{
			name = "rows",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local visible = 0
				for _, row in ipairs(self.rows) do
					if row:IsShown() then
						visible = visible + 1
					end
				end
				local expected = self.lastShown or 0
				local ok = visible == expected and expected <= self:Capacity()
				return ok and "PASS" or "FAIL", visible, expected, self.lastItems
			end,
		},
		{
			name = "background",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local profile = self.db.profile
				local bgAlpha = self.bg:GetAlpha()
				local headerAlpha = self.headerBg:GetAlpha()
				if issecretvalue(bgAlpha) or issecretvalue(headerAlpha) then
					return "INFO", "secret"
				end
				local ok = math.abs(bgAlpha - profile.bgOpacity / 100) <= 0.01
					and math.abs(headerAlpha - profile.headerOpacity / 100) <= 0.01
				return ok and "PASS" or "FAIL", bgAlpha, headerAlpha
			end,
		},
		{
			name = "sounds",
			run = function()
				local profile = self.db.profile
				return "INFO",
					profile.enemySound,
					ns.Media:SoundPath(profile.enemySound),
					profile.kosSound,
					ns.Media:SoundPath(profile.kosSound)
			end,
		},
		{
			name = "banner",
			run = function()
				return "INFO", self.banner:IsShown(), self.bannerFade:IsPlaying(), self.db.profile.kosBanner
			end,
		},
	}
end
