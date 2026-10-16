local addonName, ns = ...

local FontLogic = ns.FontLogic
local LSM = LibStub("LibSharedMedia-3.0")

local Media = ns.addon:NewModule("Media", "AceEvent-3.0")
ns.Media = Media

Media.registrations = {
	font = { seen = 0, stored = 0, duplicate = 0, rejected = {} },
	statusbar = { seen = 0, stored = 0, duplicate = 0, rejected = {} },
}
Media.folders = {}

local function isKnown(path)
	if type(C_UIFileAsset) ~= "table" or type(C_UIFileAsset.IsKnownFile) ~= "function" then
		return nil
	end
	return C_UIFileAsset.IsKnownFile(path) and true or false
end

local function onRegister(_, mediatype, key, data)
	if type(mediatype) ~= "string" or type(key) ~= "string" or data == nil then
		return
	end

	local mt = mediatype:lower()
	local stats = Media.registrations[mt]
	if not stats then
		return
	end

	stats.seen = stats.seen + 1
	if type(data) == "string" then
		local folder = FontLogic.AddonFolder(data)
		if folder ~= nil then
			Media.folders[folder] = true
		end
	end

	local hash = LSM:HashTable(mt)
	local cur = hash and hash[key]
	if cur == data then
		stats.stored = stats.stored + 1
		stats.rejected[key] = nil
	elseif cur ~= nil then
		stats.duplicate = stats.duplicate + 1
	elseif stats.rejected[key] == nil then
		local isString = type(data) == "string"
		local canonical = isString and FontLogic.CanonicalAddOnsPath(data)
		stats.rejected[key] = {
			path = data,
			known = isString and isKnown(data),
			canonicalKnown = canonical and isKnown(canonical),
		}
	end
end

hooksecurefunc(LSM, "Register", onRegister)
Media.hookedRegister = LSM.Register

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
	self.controls = {}
	self.probeSeen = {}

	local frame = CreateFrame("Frame", addonName .. "MediaProbe", UIParent)
	frame:Hide()
	self.fontProbe = frame:CreateFontString()
	self.textureProbe = frame:CreateTexture()
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
		if not self.controls.font then
			local function probe(path)
				return self.fontProbe:SetFont(path, 12, "") and true or false
			end
			self.controls.font = {
				good = probe(LSM:Fetch("font", FontLogic.DEFAULT)),
				missing = probe("Interface\\AddOns\\MerrinxUI\\no-such-file.ttf"),
			}
		end
		isUsable = function(path)
			local ok = self.fontProbe:SetFont(path, 12, "") and true or false
			local seen = self.probeSeen[path]
			if not seen then
				seen = {}
				self.probeSeen[path] = seen
			end
			seen[ok and "ok" or "fail"] = true
			return ok
		end
	elseif mediatype == "statusbar" and not self.controls.statusbar then
		local good = self.textureProbe:SetTexture("Interface\\Buttons\\WHITE8X8") and true or false
		local missing = self.textureProbe:SetTexture("Interface\\AddOns\\MerrinxUI\\no-such-file.tga") and true or false
		self.textureProbe:SetTexture(nil)
		self.controls.statusbar = { good = good, missing = missing }
	end

	local stats = Media.registrations[mediatype]
	if stats then
		for _, entry in pairs(stats.rejected) do
			if type(entry.path) == "string" then
				if mediatype == "font" then
					entry.usable = self.fontProbe:SetFont(entry.path, 12, "") and true or false
				elseif mediatype == "statusbar" then
					entry.usable = self.textureProbe:SetTexture(entry.path) and true or false
					self.textureProbe:SetTexture(nil)
				end
			end
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

local function registrationCounts(mt)
	local stats = Media.registrations[mt]
	local rejectedCount, rejectedKnown, rejectedCanonicalKnown, probed, probedUsable = 0, 0, 0, 0, 0
	local keys = {}
	for key, entry in pairs(stats.rejected) do
		rejectedCount = rejectedCount + 1
		keys[#keys + 1] = key
		if entry.known == true then
			rejectedKnown = rejectedKnown + 1
		end
		if entry.canonicalKnown == true then
			rejectedCanonicalKnown = rejectedCanonicalKnown + 1
		end
		if entry.usable ~= nil then
			probed = probed + 1
		end
		if entry.usable == true then
			probedUsable = probedUsable + 1
		end
	end
	table.sort(keys)
	return stats.seen,
		stats.stored,
		stats.duplicate,
		rejectedCount,
		rejectedKnown,
		rejectedCanonicalKnown,
		probed,
		probedUsable,
		stats.rejected[keys[1]] and stats.rejected[keys[1]].path
end

local function probeControl(control)
	if control == nil then
		return "not probed"
	end
	return control.good, control.missing
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
		{
			name = "lsm",
			run = function()
				local _, minor = LibStub:GetLibrary("LibSharedMedia-3.0", true)
				local apiType
				if type(C_UIFileAsset) == "table" then
					apiType = type(C_UIFileAsset.IsKnownFile)
				else
					apiType = "no C_UIFileAsset"
				end
				return "INFO", minor, apiType, LSM.Register == Media.hookedRegister
			end,
		},
		{
			name = "media addons",
			run = function()
				local names = {}
				for folder in pairs(Media.folders) do
					names[#names + 1] = folder
				end
				table.sort(names)
				return "INFO", #names, unpack(names, 1, #names)
			end,
		},
		{
			name = "font registrations",
			run = function()
				return "INFO", registrationCounts("font")
			end,
		},
		{
			name = "font probe control",
			run = function()
				return "INFO", probeControl(self.controls.font)
			end,
		},
		{
			name = "statusbar registrations",
			run = function()
				return "INFO", registrationCounts("statusbar")
			end,
		},
		{
			name = "texture probe control",
			run = function()
				return "INFO", probeControl(self.controls.statusbar)
			end,
		},
		{
			name = "addon fonts",
			run = function()
				local hash = LSM:HashTable("font")
				local total, probedOk, probedFailed, flaky, unusable = 0, 0, 0, 0, 0
				local failedKeys = {}
				if hash then
					for key, path in pairs(hash) do
						if FontLogic.IsAddonPath(path) then
							total = total + 1
							local seen = self.probeSeen[path]
							local ok = seen and seen.ok
							local fail = seen and seen.fail
							if ok then
								probedOk = probedOk + 1
							end
							if fail then
								probedFailed = probedFailed + 1
								failedKeys[#failedKeys + 1] = key
							end
							if ok and fail then
								flaky = flaky + 1
							end
							if self.unusableFonts[path] then
								unusable = unusable + 1
							end
						end
					end
				end
				table.sort(failedKeys)
				return "INFO", total, probedOk, probedFailed, flaky, unusable, failedKeys[1]
			end,
		},
	}
end
