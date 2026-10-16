local addonName, ns = ...

local L = ns.ProfessionLogic

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local Theme = ns.Theme
local ACCENT = Theme.color.accent
local DIM = Theme.color.textDim
local TEXT = Theme.color.text

local Professions = ns.addon:NewModule("Professions", "AceEvent-3.0")

local WIDTH = 300
local HEADER_HEIGHT = 22
local BODY_LINES = 14

local defaults = {
	profile = {
		enabled = false,
		fontSize = 12,
		font = "*",
		bgOpacity = 75,
		headerOpacity = 100,
		position = { point = "CENTER", x = -400, y = 0 },
	},
	char = {
		selected = nil,
	},
}

local function skillInfo(id)
	if type(C_SkillInfo) ~= "table" or type(C_SkillInfo.GetSkillLineInfoByID) ~= "function" then
		return nil
	end

	local info = C_SkillInfo.GetSkillLineInfoByID(id)
	if type(info) ~= "table" then
		return nil
	end

	if issecretvalue(info.rank) or issecretvalue(info.maxRank) then
		return { secret = true }
	end

	if not info.maxRank or info.maxRank == 0 then
		return nil
	end

	return { rank = info.rank, maxRank = info.maxRank }
end

local function inOrder(id)
	for _, v in ipairs(L.ORDER) do
		if v == id then
			return true
		end
	end
	return false
end

function Professions:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Professions", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	local frame = CreateFrame("Frame", "MerrinxUIProfessions", UIParent)
	frame:Hide()
	self.frame = frame

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(TEXTURE)
	bg:SetVertexColor(0, 0, 0, 1)
	self.bg = bg

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT")
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT")

	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	headerBg:SetTexture(TEXTURE)
	headerBg:SetVertexColor(27 / 255, 27 / 255, 27 / 255, 1)
	self.headerBg = headerBg

	local title = header:CreateFontString(nil, "OVERLAY")
	title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], ACCENT[4])
	self.title = title

	local menuButton = CreateFrame("Button", nil, header)
	menuButton:SetSize(HEADER_HEIGHT, HEADER_HEIGHT)
	menuButton:SetPoint("RIGHT", header, "RIGHT", -2, 0)
	local menuText = menuButton:CreateFontString(nil, "OVERLAY")
	menuText:SetAllPoints()
	menuText:SetJustifyH("CENTER")
	menuText:SetTextColor(1, 1, 1, 1)
	menuButton.text = menuText
	menuButton:SetScript("OnEnter", function()
		menuText:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], ACCENT[4])
	end)
	menuButton:SetScript("OnLeave", function()
		menuText:SetTextColor(1, 1, 1, 1)
	end)
	menuButton:SetScript("OnClick", function()
		self:OpenMenu(menuButton)
	end)
	self.menuButton = menuButton

	title:SetPoint("LEFT", header, "LEFT", 4, 0)
	title:SetPoint("RIGHT", menuButton, "LEFT", -2, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)

	self.lines = {}
	for i = 1, BODY_LINES do
		local line = CreateFrame("Frame", nil, frame)
		line:EnableMouse(true)

		local fs = line:CreateFontString(nil, "OVERLAY")
		fs:SetPoint("LEFT", line, "LEFT", 0, 0)
		fs:SetPoint("RIGHT", line, "RIGHT", 0, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		line.fs = fs

		line:SetScript("OnEnter", function()
			local step = line.step
			if not step then
				return
			end
			local stepLines = L.Lines(step)
			if #stepLines == 0 then
				return
			end
			GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
			GameTooltip:SetText(L.FormatStep(step))
			for _, text in ipairs(stepLines) do
				GameTooltip:AddLine(text, 1, 1, 1, true)
			end
			GameTooltip:Show()
		end)
		line:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		self.lines[i] = line
	end

	local footer = frame:CreateFontString(nil, "OVERLAY")
	footer:SetJustifyH("LEFT")
	footer:SetWordWrap(false)
	footer:SetTextColor(DIM[1], DIM[2], DIM[3], DIM[4])
	self.footer = footer

	ns.Mover:Register(frame, "Profession Guide", function()
		return self.db.profile.position
	end)
end

function Professions:OnEnable()
	self:RegisterEvent("SKILL_LINES_CHANGED", "Redraw")
	self:RegisterEvent("PLAYER_LEVEL_UP", "OnLevelUp")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")

	self.level = UnitLevel("player")

	self:Layout()
	ns.Mover:Apply(self.frame)
	self.frame:Show()
	self:Redraw()
end

function Professions:OnDisable()
	self.frame:Hide()
end

function Professions:OnLevelUp(_, level)
	if type(level) == "number" then
		self.level = level
	end
	self:Redraw()
end

function Professions:OnMediaChanged(_, mediatype, key)
	local profile = self.db.profile
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", profile.font)) then
		self:Layout()
		self:Redraw()
	end
end

function Professions:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:Layout()
			ns.Mover:Apply(self.frame)
			self:Redraw()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function Professions:Layout()
	local profile = self.db.profile
	local frame = self.frame

	local lineHeight = profile.fontSize + 4
	local footerSize = math.max(8, profile.fontSize - 2)
	local footerHeight = footerSize + 6

	frame:SetSize(WIDTH, HEADER_HEIGHT + lineHeight * BODY_LINES + footerHeight)

	self.bg:SetAlpha(profile.bgOpacity / 100)
	self.headerBg:SetAlpha(profile.headerOpacity / 100)

	ns.Media:SetFont(self.title, profile.font, 11, "")
	ns.Media:SetFont(self.menuButton.text, profile.font, 11, "")
	self.menuButton.text:SetText("P")

	for i, line in ipairs(self.lines) do
		ns.Media:SetFont(line.fs, profile.font, profile.fontSize, "")
		line:SetSize(WIDTH - 12, lineHeight)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(HEADER_HEIGHT + (i - 1) * lineHeight))
	end

	ns.Media:SetFont(self.footer, profile.font, footerSize, "")
	self.footer:ClearAllPoints()
	self.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 4)
	self.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4)
end

function Professions:Selected()
	local selected = self.db.char.selected
	if selected and inOrder(selected) and ns.ProfessionData[selected] then
		return selected
	end

	for _, id in ipairs(L.ORDER) do
		local info = skillInfo(id)
		if info and not info.secret and info.maxRank and info.maxRank > 0 then
			return id
		end
	end

	return 171
end

function Professions:Select(id)
	self.db.char.selected = id
	self.selectedId = id
	ns.Debug:Log("Professions", "select", id)
	self:Redraw()
end

function Professions:OpenMenu(button)
	MenuUtil.CreateContextMenu(button, function(_, root)
		for _, id in ipairs(L.ORDER) do
			local data = ns.ProfessionData[id]
			local name = (data and data.name) or tostring(id)
			local info = skillInfo(id)

			local label = name
			if info then
				if info.secret then
					label = label .. " ?/?"
				else
					label = label .. " " .. info.rank .. "/" .. info.maxRank
				end
			end

			root:CreateRadio(label, function()
				return self.selectedId == id
			end, function()
				self:Select(id)
			end)
		end
	end)
end

function Professions:Redraw()
	local id = self:Selected()
	self.selectedId = id

	local data = ns.ProfessionData[id]
	self.title:SetText((data and data.name) or tostring(id))

	local texts, colors, steps = {}, {}, {}
	local function put(i, text, color, step)
		texts[i] = text
		colors[i] = color
		steps[i] = step
	end

	if type(C_SkillInfo) ~= "table" or type(C_SkillInfo.GetSkillLineInfoByID) ~= "function" then
		put(1, "Skill API unavailable")
	else
		local info = skillInfo(id)

		if info and info.secret then
			put(1, "?/?")
		else
			local rank = (info and info.rank) or 0
			local maxRank = (info and info.maxRank) or 0
			local tiers = data and L.Tiers(data) or nil
			local tierIdx = tiers and L.TierIndex(tiers, maxRank) or 0
			local tierName = tierIdx > 0 and tiers[tierIdx].name or nil

			if tierName then
				put(1, rank .. "/" .. maxRank .. " " .. tierName)
			else
				put(1, "Not learned")
			end

			if tiers then
				local training = L.NextTraining(tiers, rank, maxRank, self.level or 0)
				put(2, L.TrainingText(training), DIM)

				local stepIdx = data.steps and L.CurrentStep(data.steps, rank)
				local n = 2
				if not stepIdx then
					n = n + 1
					if data.routeEnd >= 300 then
						put(n, "Max skill reached")
					else
						put(n, "Guide ends at " .. data.routeEnd)
					end
				else
					for i = stepIdx, #data.steps do
						if n >= BODY_LINES then
							break
						end
						n = n + 1
						local step = data.steps[i]
						if i == stepIdx then
							put(n, L.FormatStep(step), ACCENT)
							for _, text in ipairs(L.Lines(step)) do
								if n >= BODY_LINES then
									break
								end
								n = n + 1
								put(n, text, DIM)
							end
						else
							put(n, L.FormatStep(step), DIM, step)
						end
					end
				end
			end
		end
	end

	for i = 1, BODY_LINES do
		local line = self.lines[i]
		line.fs:SetText(texts[i] or "")
		local c = colors[i] or TEXT
		line.fs:SetTextColor(c[1], c[2], c[3], c[4])
		line.step = steps[i]
	end

	self.footer:SetText((data and data.source) and "Route: wow-professions.com" or "Route: MerrinxUI")
end

function Professions:GetOptions()
	return {
		type = "group",
		name = "Professions",
		args = {
			enabled = {
				type = "toggle",
				name = "Enabled",
				order = 1,
				get = function()
					return self.db.profile.enabled
				end,
				set = function(_, value)
					self.db.profile.enabled = value
					self:Refresh()
				end,
			},
			fontSize = {
				type = "range",
				name = "Font size",
				order = 2,
				min = 8,
				max = 20,
				step = 1,
				get = function()
					return self.db.profile.fontSize
				end,
				set = function(_, value)
					self.db.profile.fontSize = value
					self:Refresh()
				end,
			},
			font = {
				type = "select",
				name = "Font",
				order = 3,
				dialogControl = "LSM30_Font",
				values = function()
					return ns.Media:Values("font", self.db.profile.font)
				end,
				get = function()
					return self.db.profile.font
				end,
				set = function(_, value)
					self.db.profile.font = value
					self:Refresh()
				end,
			},
			bgOpacity = {
				type = "range",
				name = "Background opacity",
				order = 4,
				min = 0,
				max = 100,
				step = 5,
				get = function()
					return self.db.profile.bgOpacity
				end,
				set = function(_, value)
					self.db.profile.bgOpacity = value
					self:Refresh()
				end,
			},
			headerOpacity = {
				type = "range",
				name = "Header opacity",
				order = 5,
				min = 0,
				max = 100,
				step = 5,
				get = function()
					return self.db.profile.headerOpacity
				end,
				set = function(_, value)
					self.db.profile.headerOpacity = value
					self:Refresh()
				end,
			},
		},
	}
end

function Professions:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function checkFn(name, fn)
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end

				local csi = type(C_SkillInfo) == "table" and C_SkillInfo or {}
				local menuUtil = type(MenuUtil) == "table" and MenuUtil or {}
				checkFn("C_SkillInfo.GetSkillLineInfoByID", csi.GetSkillLineInfoByID)
				checkFn("MenuUtil.CreateContextMenu", menuUtil.CreateContextMenu)
				checkFn("UnitLevel", UnitLevel)

				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "data",
			run = function()
				local count = 0
				local firstError
				for _, data in pairs(ns.ProfessionData or {}) do
					local ok, err = L.Validate(data)
					if ok then
						count = count + 1
					elseif not firstError then
						firstError = err
					end
				end

				if count == 12 then
					return "PASS", count
				end
				return "FAIL", firstError or ("count " .. count)
			end,
		},
		{
			name = "skills",
			run = function()
				local parts = {}
				for _, id in ipairs(L.ORDER) do
					local profData = ns.ProfessionData[id]
					local name = (profData and profData.name) or tostring(id)
					local info = skillInfo(id)
					if info then
						if info.secret then
							table.insert(parts, "secret")
						else
							table.insert(parts, name .. " " .. info.rank .. "/" .. info.maxRank)
						end
					end
				end
				return "INFO", table.concat(parts, ", ")
			end,
		},
		{
			name = "guide",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local id = self.selectedId or self:Selected()
				local profData = ns.ProfessionData[id]
				local info = skillInfo(id)

				local stepIdx, trainingText
				if profData and not (info and info.secret) then
					local rank = (info and info.rank) or 0
					local maxRank = (info and info.maxRank) or 0
					local tiers = L.Tiers(profData)
					stepIdx = profData.steps and L.CurrentStep(profData.steps, rank)
					trainingText = L.TrainingText(L.NextTraining(tiers, rank, maxRank, self.level or 0))
				end

				return "INFO", id, stepIdx, trainingText
			end,
		},
		{
			name = "window",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local fs = self.lines[1] and self.lines[1].fs
				local text = fs and fs:GetText()
				local ok = self.frame:IsShown() and type(text) == "string" and text ~= ""
				return ok and "PASS" or "FAIL", text
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
	}
end
