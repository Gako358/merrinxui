local addonName, ns = ...

local L = ns.ChatLogic
local FontLogic = ns.FontLogic
local AceGUI = LibStub("AceGUI-3.0")

local Chat = ns.addon:NewModule("Chat", "AceEvent-3.0")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BORDER_COLOR = { 0, 0, 0, 0.9 }
local URL_HEX = "66bfff"
local FADE_DELAY = 3
local FADE_RATE = 2
-- Blizzard's own hover test for chat frames reaches this far up, over the tab row.
local HOVER_TOP = 28
local TAB_LINE_INSET = 6
local TAB_LINE_Y = 2
local EDIT_INSET_X = 2
local EDIT_INSET_Y = 5
local COPY_SIZE = 16

local TAB_ART = {
	"Left",
	"Middle",
	"Right",
	"ActiveLeft",
	"ActiveRight",
	"HighlightLeft",
	"HighlightMiddle",
	"HighlightRight",
}
local EDIT_ART = { "Left", "Right", "Mid" }
local EDIT_FOCUS_ART = { "focusLeft", "focusMid", "focusRight" }
local EDIT_TEXT = { "header", "headerSuffix", "languageHeader", "prompt", "NewcomerHint" }

local URL_EVENTS = {
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_COMMUNITIES_CHANNEL",
}

local defaults = {
	profile = {
		enabled = false,
		font = FontLogic.GLOBAL,
		bgOpacity = 50,
		fade = true,
		fadeOpacity = 0,
		urls = true,
		copyButton = true,
	},
}

-- Blizzard's filter registry skips callbacks whose arguments are secret.
local function urlFilter(_, _, msg, ...)
	if issecretvalue(msg) or type(msg) ~= "string" then
		return false
	end
	local wrapped, count = L.WrapURLs(msg, URL_HEX)
	if count == 0 then
		return false
	end
	Chat.urlLinks = Chat.urlLinks + count
	return false, wrapped, ...
end

local function newBox(owner, anchor, x1, y1, x2, y2)
	local bg = owner:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetPoint("TOPLEFT", anchor, "TOPLEFT", x1, y1)
	bg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x2, y2)
	local regions = { bg }
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = owner:CreateTexture(nil, "BACKGROUND", nil, -7)
		edge:SetColorTexture(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], BORDER_COLOR[4])
		if side == "TOP" or side == "BOTTOM" then
			edge:SetPoint(side .. "LEFT", bg)
			edge:SetPoint(side .. "RIGHT", bg)
			edge:SetHeight(1)
		else
			edge:SetPoint("TOP" .. side, bg)
			edge:SetPoint("BOTTOM" .. side, bg)
			edge:SetWidth(1)
		end
		regions[#regions + 1] = edge
	end
	return { bg = bg, regions = regions }
end

local function paintBox(box, opacity)
	box.bg:SetColorTexture(0, 0, 0, opacity / 100)
end

local function setBoxAlpha(box, alpha)
	for _, region in ipairs(box.regions) do
		region:SetAlpha(alpha)
	end
end

local function setFace(object, path)
	local _, size, flags = object:GetFont()
	if size then
		object:SetFont(path, size, flags or "")
	end
end

-- Only widget methods touch Blizzard's chat objects: no Lua fields, no hooks and
-- no Show/Hide on frames with scripts, so the secure message handler stays untainted.
function Chat:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Chat", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.skins = {}
	self.knownFrames = 0
	self.urlLinks = 0
	self.urlFilterOn = false

	local driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", function(_, elapsed)
		self:Tick(elapsed)
	end)
	self.driver = driver
end

function Chat:OnEnable()
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")
	EventRegistry:RegisterCallback("SetItemRef", self.OnItemRef, self)
	self:SkinAll()
	self:Apply()
	self.driver:Show()
end

function Chat:OnDisable()
	self.driver:Hide()
	self:SetURLFilter(false)
	EventRegistry:UnregisterCallback("SetItemRef", self)
	for _, skin in pairs(self.skins) do
		setBoxAlpha(skin.panel, 0)
		if skin.edit then
			setBoxAlpha(skin.edit, 0)
		end
		skin.copy:Hide()
	end
	if next(self.skins) then
		ns.addon:Print("Chat: /reload restores Blizzard's chat style")
	end
end

function Chat:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:Apply()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function Chat:OnMediaChanged(_, mediatype, key)
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", self.db.profile.font)) then
		self:Apply()
	end
end

function Chat:SkinAll()
	for _, name in ipairs(CHAT_FRAMES) do
		local cf = _G[name]
		if cf and not self.skins[cf] then
			self:Skin(cf)
			if self:IsEnabled() then
				self:ApplySkin(self.skins[cf])
			end
		end
	end
	self.knownFrames = #CHAT_FRAMES
end

function Chat:Skin(cf)
	local name = cf:GetName()
	for _, key in ipairs(CHAT_FRAME_TEXTURES) do
		local region = _G[name .. key]
		if region then
			region:Hide()
		end
	end

	local skin = { frame = cf, idle = 0, alpha = 1 }
	skin.panel = newBox(cf, cf.Background, 0, 0, 0, 0)

	local tab = _G[name .. "Tab"]
	if tab then
		for _, key in ipairs(TAB_ART) do
			if tab[key] then
				tab[key]:SetAlpha(0)
			end
		end
		local line = tab.ActiveMiddle
		if line then
			line:SetTexture(WHITE)
			line:SetBlendMode("BLEND")
			line:ClearAllPoints()
			line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", TAB_LINE_INSET, TAB_LINE_Y)
			line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -TAB_LINE_INSET, TAB_LINE_Y)
			line:SetHeight(2)
		end
		skin.tab = tab
	end

	local eb = cf.editBox
	if eb then
		local ebName = eb:GetName()
		for _, suffix in ipairs(EDIT_ART) do
			local region = ebName and _G[ebName .. suffix]
			if region then
				region:SetAlpha(0)
			end
		end
		for _, key in ipairs(EDIT_FOCUS_ART) do
			if eb[key] then
				eb[key]:SetAlpha(0)
			end
		end
		skin.edit = newBox(eb, eb, EDIT_INSET_X, -EDIT_INSET_Y, -EDIT_INSET_X, EDIT_INSET_Y)
		skin.editBox = eb
	end

	local copy = CreateFrame("Button", nil, cf)
	copy:SetSize(COPY_SIZE, COPY_SIZE)
	copy:SetPoint("BOTTOMRIGHT", skin.panel.bg, "TOPRIGHT", 0, 2)
	local icon = copy:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(ns.Media:Icon("segment"))
	icon:SetVertexColor(1, 1, 1, 0.7)
	copy:SetScript("OnClick", function()
		self:ShowCopy(cf)
	end)
	copy:SetScript("OnEnter", function(owner)
		icon:SetVertexColor(1, 1, 1, 1)
		GameTooltip:SetOwner(owner, "ANCHOR_TOP")
		GameTooltip:SetText("Copy chat")
		GameTooltip:Show()
	end)
	copy:SetScript("OnLeave", function()
		icon:SetVertexColor(1, 1, 1, 0.7)
		GameTooltip:Hide()
	end)
	skin.copy = copy

	self.skins[cf] = skin
	ns.Debug:Log("Chat", "skin", name)
end

function Chat:ApplySkin(skin)
	local p = self.db.profile
	local path = ns.Media:FontPath(p.font)
	setFace(skin.frame, path)
	paintBox(skin.panel, p.bgOpacity)
	if skin.tab then
		setFace(skin.tab:GetFontString(), path)
	end
	if skin.edit then
		paintBox(skin.edit, p.bgOpacity)
		setBoxAlpha(skin.edit, 1)
		setFace(skin.editBox, path)
		for _, key in ipairs(EDIT_TEXT) do
			if skin.editBox[key] then
				setFace(skin.editBox[key], path)
			end
		end
	end
	self:SetSkinAlpha(skin, skin.alpha)
end

function Chat:Apply()
	for _, skin in pairs(self.skins) do
		self:ApplySkin(skin)
	end
	self:SetURLFilter(self.db.profile.urls)
end

function Chat:SetSkinAlpha(skin, alpha)
	setBoxAlpha(skin.panel, alpha)
	skin.copy:SetAlpha(alpha)
	skin.copy:SetShown(self.db.profile.copyButton and alpha > 0.05)
end

function Chat:IsActive(skin)
	if skin.frame:IsMouseOver(HOVER_TOP, -2, -2, 2) then
		return true
	end
	return skin.editBox ~= nil and skin.editBox:HasFocus()
end

function Chat:Tick(elapsed)
	if #CHAT_FRAMES ~= self.knownFrames then
		self:SkinAll()
	end
	local p = self.db.profile
	local low = p.fadeOpacity / 100
	for cf, skin in pairs(self.skins) do
		if cf:IsVisible() then
			skin.idle = self:IsActive(skin) and 0 or skin.idle + elapsed
			local target = L.FadeTarget(p.fade, skin.idle, FADE_DELAY, low)
			if skin.alpha ~= target then
				skin.alpha = L.Approach(skin.alpha, target, elapsed * FADE_RATE)
				self:SetSkinAlpha(skin, skin.alpha)
			end
		end
	end
end

function Chat:SetURLFilter(on)
	on = on == true
	if on == self.urlFilterOn then
		return
	end
	for _, event in ipairs(URL_EVENTS) do
		if on then
			ChatFrameUtil.AddMessageEventFilter(event, urlFilter)
		else
			ChatFrameUtil.RemoveMessageEventFilter(event, urlFilter)
		end
	end
	self.urlFilterOn = on
	ns.Debug:Log("Chat", "url filter", on)
end

function Chat:OnItemRef(link)
	local url = L.ParseLink(link)
	if url and self:IsEnabled() then
		self:ShowURL(url)
	end
end

function Chat:ShowURL(url)
	if self.urlFrame then
		AceGUI:Release(self.urlFrame)
	end
	local frame = AceGUI:Create("Frame")
	frame:SetTitle("Link")
	frame:SetLayout("Fill")
	frame:SetWidth(460)
	frame:SetHeight(110)
	frame:SetStatusText("Ctrl+C to copy")
	frame:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		self.urlFrame = nil
	end)
	self.urlFrame = frame

	local edit = AceGUI:Create("EditBox")
	edit:SetLabel("")
	edit:DisableButton(true)
	edit:SetText(url)
	frame:AddChild(edit)
	edit:SetFocus()
	edit:HighlightText()
end

function Chat:CopyLines(cf)
	local lines, skipped = {}, 0
	for i = 1, cf:GetNumMessages() do
		local text = cf:GetMessageInfo(i)
		if issecretvalue(text) then
			skipped = skipped + 1
		elseif type(text) == "string" then
			lines[#lines + 1] = L.PlainText(text)
		end
	end
	return lines, skipped
end

function Chat:ShowCopy(cf)
	cf = cf or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
	local lines, skipped = self:CopyLines(cf)

	if not self.copyFrame then
		local frame = AceGUI:Create("Frame")
		frame:SetLayout("Fill")
		frame:SetCallback("OnClose", function(widget)
			AceGUI:Release(widget)
			self.copyFrame = nil
			self.copyEdit = nil
		end)
		local edit = AceGUI:Create("MultiLineEditBox")
		edit:SetLabel("")
		edit:DisableButton(true)
		frame:AddChild(edit)
		self.copyFrame, self.copyEdit = frame, edit
	end

	local status = #lines .. " lines"
	if skipped > 0 then
		status = status .. ", " .. skipped .. " hidden (secret)"
	end
	self.copyFrame:SetTitle("Copy chat")
	self.copyFrame:SetStatusText(status)
	self.copyEdit:SetText(table.concat(lines, "\n"))
	self.copyEdit:SetFocus()
	self.copyEdit:HighlightText()
	self.copyFrame.frame:Raise()
	ns.Debug:Log("Chat", "copy", #lines, skipped)
end

function Chat:GetOptions()
	local chat = self
	local function get(key)
		return function()
			return chat.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			chat.db.profile[key] = value
			chat:Refresh()
		end
	end
	local function toggle(key, name, order, desc)
		return { type = "toggle", name = name, desc = desc, order = order, get = get(key), set = set(key) }
	end
	local function range(key, name, order)
		return {
			type = "range",
			name = name,
			order = order,
			min = 0,
			max = 100,
			step = 5,
			get = get(key),
			set = set(key),
		}
	end

	local fadeOpacity = range("fadeOpacity", "Idle background opacity", 5)
	fadeOpacity.disabled = function()
		return not chat.db.profile.fade
	end

	return {
		type = "group",
		name = "Chat",
		args = {
			enabled = toggle("enabled", "Enabled", 1, "Turning it off needs /reload to restore Blizzard's chat style"),
			font = {
				type = "select",
				name = "Font",
				desc = "The size stays the one set per chat window in Blizzard's tab menu",
				order = 2,
				dialogControl = "LSM30_Font",
				values = function()
					return ns.Media:Values("font", chat.db.profile.font)
				end,
				get = get("font"),
				set = set("font"),
			},
			bgOpacity = range("bgOpacity", "Background opacity", 3),
			fade = toggle(
				"fade",
				"Fade when idle",
				4,
				"Fades the background and copy button while the mouse is away and you are not typing"
			),
			fadeOpacity = fadeOpacity,
			urls = toggle("urls", "Clickable links", 6, "Turns web addresses in chat into links you can copy"),
			copyButton = toggle("copyButton", "Copy button", 7, "Also available as /mui copy"),
		},
	}
end

function Chat:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, v in pairs({
					["ChatFrameUtil.AddMessageEventFilter"] = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter,
					["ChatFrameUtil.RemoveMessageEventFilter"] = ChatFrameUtil
						and ChatFrameUtil.RemoveMessageEventFilter,
					["EventRegistry.RegisterCallback"] = EventRegistry and EventRegistry.RegisterCallback,
					CHAT_FRAMES = CHAT_FRAMES,
					CHAT_FRAME_TEXTURES = CHAT_FRAME_TEXTURES,
				}) do
					if v == nil then
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
			name = "frames",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local count = 0
				for _ in pairs(self.skins) do
					count = count + 1
				end
				return (count == #CHAT_FRAMES) and "PASS" or "FAIL", count, #CHAT_FRAMES
			end,
		},
		{
			name = "blizzard art",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local shown = {}
				for cf in pairs(self.skins) do
					local name = cf:GetName()
					for _, key in ipairs(CHAT_FRAME_TEXTURES) do
						local region = _G[name .. key]
						if region and region:IsShown() then
							shown[#shown + 1] = name .. key
						end
					end
				end
				table.sort(shown)
				if #shown > 0 then
					return "FAIL", #shown, shown[1]
				end
				return "PASS"
			end,
		},
		{
			name = "panel",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local skin = self.skins[DEFAULT_CHAT_FRAME]
				if not skin then
					return "FAIL", "not skinned"
				end
				local width, height = skin.panel.bg:GetSize()
				local ok = width > 0 and height > 0
				return ok and "PASS" or "FAIL", width, height, skin.alpha, skin.idle
			end,
		},
		{
			name = "font",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local expected = ns.Media:FontPath(self.db.profile.font)
				local path, size = DEFAULT_CHAT_FRAME:GetFont()
				local ebPath = DEFAULT_CHAT_FRAME.editBox and DEFAULT_CHAT_FRAME.editBox:GetFont()
				local ok = path == expected and ebPath == expected
				return ok and "PASS" or "FAIL", path, size, ebPath, ns.Media:Resolve("font", self.db.profile.font)
			end,
		},
		{
			name = "edit box",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local eb = DEFAULT_CHAT_FRAME.editBox
				if not eb then
					return "INFO", "missing"
				end
				local visible = {}
				for _, suffix in ipairs(EDIT_ART) do
					local region = _G[eb:GetName() .. suffix]
					if region and region:GetAlpha() > 0 then
						visible[#visible + 1] = suffix
					end
				end
				for _, key in ipairs(EDIT_FOCUS_ART) do
					if eb[key] and eb[key]:GetAlpha() > 0 then
						visible[#visible + 1] = key
					end
				end
				return (#visible == 0) and "PASS" or "FAIL", eb:IsShown(), unpack(visible)
			end,
		},
		{
			name = "url filter",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local _, count = L.WrapURLs("see https://example.com", URL_HEX)
				local ok = self.urlFilterOn == (self.db.profile.urls == true) and count == 1
				return ok and "PASS" or "FAIL", self.urlFilterOn, count, self.urlLinks
			end,
		},
		{
			name = "copy",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local lines, skipped = self:CopyLines(DEFAULT_CHAT_FRAME)
				return "INFO", #lines, skipped, DEFAULT_CHAT_FRAME:GetNumMessages()
			end,
		},
	}
end
