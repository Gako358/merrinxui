local addonName, ns = ...

local FontLogic = ns.FontLogic
local LSM = LibStub("LibSharedMedia-3.0")

local Media = ns.addon:NewModule("Media", "AceEvent-3.0")
ns.Media = Media

local defaults = {
	profile = {
		font = "Friz Quadrata TT",
		statusbar = "Solid",
		optionsFont = "Arial Narrow",
	},
}

function Media:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Media", defaults)
	self.unusableFonts = {}
	self.reportedBadFonts = {}

	local frame = CreateFrame("Frame", addonName .. "MediaProbe", UIParent)
	frame:Hide()
	self.fontProbe = frame:CreateFontString()
end

function Media:OnEnable()
	LSM.RegisterCallback(self, "LibSharedMedia_Registered", "OnMediaRegistered")
end

function Media:OnMediaRegistered(_, mediatype, key)
	if mediatype == "font" or mediatype == "statusbar" then
		self:SendMessage("MERRINXUI_MEDIA_CHANGED", mediatype, key)
	end
end

function Media:GlobalKey(mediatype)
	if mediatype == "font" then
		return self.db.profile.font
	end
	return self.db.profile.statusbar
end

function Media:Resolve(mediatype, key)
	return FontLogic.Resolve(key, self:GlobalKey(mediatype))
end

function Media:Fetch(mediatype, key)
	return LSM:Fetch(mediatype, self:Resolve(mediatype, key), true)
end

function Media:FontPath(key)
	local path = self:Fetch("font", key)
	if path == nil or self.unusableFonts[path] then
		return LSM:Fetch("font", FontLogic.DEFAULT)
	end
	return path
end

function Media:SetFont(fs, key, size, flags)
	local resolved = self:Resolve("font", key)
	local path = self:Fetch("font", key)
	if path and fs:SetFont(path, size, flags) then
		return true, path
	end

	if path then
		self.unusableFonts[path] = true
	end

	local fallback = LSM:Fetch("font", FontLogic.DEFAULT)
	fs:SetFont(fallback, size, flags)

	if not self.reportedBadFonts[resolved] then
		self.reportedBadFonts[resolved] = true
		ns.addon:Print("font '" .. tostring(resolved) .. "' is unavailable, falling back to " .. tostring(fallback))
	end

	return false, fallback
end

function Media:SetStatusBarTexture(bar, key)
	local path = self:Fetch("statusbar", key) or LSM:Fetch("statusbar", "Solid", true) or "Interface\\Buttons\\WHITE8X8"
	bar:SetStatusBarTexture(path)
	return path
end

function Media:Values(mediatype, keep, noGlobal)
	local isUsable
	if mediatype == "font" then
		isUsable = function(path)
			return self.fontProbe:SetFont(path, 12, "")
		end
	end
	local globalLabel
	if not noGlobal then
		globalLabel = "Use global (" .. self:GlobalKey(mediatype) .. ")"
	end
	return FontLogic.Values(LSM:HashTable(mediatype), isUsable, keep, globalLabel)
end

function Media:GetOptions()
	return {
		type = "group",
		name = "Media",
		order = 1,
		args = {
			font = {
				type = "select",
				name = "Global font",
				order = 1,
				dialogControl = "LSM30_Font",
				values = function()
					return self:Values("font", self.db.profile.font, true)
				end,
				get = function()
					return self.db.profile.font
				end,
				set = function(_, value)
					self.db.profile.font = value
					self:SendMessage("MERRINXUI_MEDIA_CHANGED", "font", nil)
					ns.Debug:Log("Media", "global", "font", value)
				end,
			},
			statusbar = {
				type = "select",
				name = "Global bar texture",
				order = 2,
				dialogControl = "LSM30_Statusbar",
				values = function()
					return self:Values("statusbar", self.db.profile.statusbar, true)
				end,
				get = function()
					return self.db.profile.statusbar
				end,
				set = function(_, value)
					self.db.profile.statusbar = value
					self:SendMessage("MERRINXUI_MEDIA_CHANGED", "statusbar", nil)
					ns.Debug:Log("Media", "global", "statusbar", value)
				end,
			},
			optionsFont = {
				type = "select",
				name = "Options window font",
				order = 3,
				dialogControl = "LSM30_Font",
				desc = "Applies after /reload",
				values = function()
					return self:Values("font", self.db.profile.optionsFont)
				end,
				get = function()
					return self.db.profile.optionsFont
				end,
				set = function(_, value)
					self.db.profile.optionsFont = value
				end,
			},
		},
	}
end

function Media:GetDebugChecks()
	return {
		{
			name = "fonts",
			run = function()
				local unusable = 0
				for _ in pairs(self.unusableFonts) do
					unusable = unusable + 1
				end
				return "INFO", #LSM:List("font"), unusable
			end,
		},
		{
			name = "statusbars",
			run = function()
				return "INFO", #LSM:List("statusbar")
			end,
		},
		{
			name = "global font",
			run = function()
				local path = self:Fetch("font", "*")
				local ok = path ~= nil and not self.unusableFonts[path]
				return ok and "PASS" or "FAIL", self:Resolve("font", "*"), path
			end,
		},
		{
			name = "global statusbar",
			run = function()
				local path = self:Fetch("statusbar", "*")
				return (path ~= nil) and "PASS" or "FAIL", self:Resolve("statusbar", "*"), path
			end,
		},
		{
			name = "options font",
			run = function()
				local key = self.db.profile.optionsFont
				return "INFO", key, self:FontPath(key)
			end,
		},
	}
end
