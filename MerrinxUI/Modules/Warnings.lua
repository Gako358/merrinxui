local addonName, ns = ...

local L = ns.WarningLogic
local FontLogic = ns.FontLogic

local Warnings = ns.addon:NewModule("Warnings", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = true,
		font = FontLogic.GLOBAL,
		fontSize = 16,
		warnings = {},
		thresholds = {},
		position = { point = "CENTER", x = 0, y = 200 },
	},
}

local function sameKeys(a, b)
	if #a ~= #b then
		return false
	end
	for i, key in ipairs(a) do
		if b[i] ~= key then
			return false
		end
	end
	return true
end

function Warnings:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Warnings", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	local _, class = UnitClass("player")
	self.class = class
	self.warnings = L.ForClass(class)
	self.active = {}
	self.activeKeys = {}

	local frame = CreateFrame("Frame", addonName .. "Warnings", UIParent)
	frame:SetSize(120, 24)
	frame:Hide()
	self.frame = frame

	local text = frame:CreateFontString(nil, "OVERLAY")
	text:SetPoint("CENTER")
	self.text = text

	ns.Mover:Register(frame, "Warnings", function()
		return self.db.profile.position
	end)
end

function Warnings:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Update")
	self:RegisterEvent("PLAYER_UPDATE_RESTING", "Update")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "Update")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "Update")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "Render")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")
	ns.Mover:Apply(self.frame)
	self:Layout()
	self:Update()
end

function Warnings:OnDisable()
	self.frame:Hide()
end

function Warnings:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			ns.Mover:Apply(self.frame)
			self:Layout()
			self:Update()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function Warnings:OnMediaChanged(_, mediatype, key)
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", self.db.profile.font)) then
		self:Layout()
	end
end

function Warnings:Layout()
	local p = self.db.profile
	ns.Media:SetFont(self.text, p.font, p.fontSize, "OUTLINE")
	self:Render()
end

function Warnings:Read()
	local function item(slot)
		local id = GetInventoryItemID("player", slot)
		if id == nil then
			return nil
		end
		local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
		return classID, subClassID
	end

	local weaponClass, weaponSubclass = item(L.RANGED_SLOT)
	local ammoClass, ammoSubclass = item(L.AMMO_SLOT)
	local ammoId = GetInventoryItemID("player", L.AMMO_SLOT)
	local ammoCount = (ammoId ~= nil) and GetInventoryItemCount("player", L.AMMO_SLOT) or 0

	return {
		resting = IsResting() == true,
		weaponClass = weaponClass,
		weaponSubclass = weaponSubclass,
		ammoClass = ammoClass,
		ammoSubclass = ammoSubclass,
		ammoCount = ammoCount,
	}
end

function Warnings:Update()
	if not self:IsEnabled() then
		return
	end

	self.reading = self:Read()
	local active = L.Active(self.warnings, self.reading, self.db.profile)

	local keys = {}
	for _, entry in ipairs(active) do
		keys[#keys + 1] = entry.warning.key
	end
	if not sameKeys(keys, self.activeKeys) then
		self.activeKeys = keys
		ns.Debug:Log("Warnings", "active", unpack(keys, 1, #keys))
	end

	self.active = active
	self:Render()
end

function Warnings:Shown()
	local preview = ns.Mover:IsUnlocked()
	if preview then
		return L.Preview(self.warnings, self.db.profile), preview
	end
	return self.active, preview
end

function Warnings:Render()
	if not self:IsEnabled() then
		return
	end

	local list = self:Shown()
	if #list == 0 then
		self.frame:Hide()
		return
	end

	local lines = {}
	for _, entry in ipairs(list) do
		lines[#lines + 1] = L.Format(entry.warning, entry.count)
	end
	self.text:SetText(table.concat(lines, "\n"))
	self.text:SetTextColor(1, 0.3, 0.25)

	local w = self.text:GetStringWidth()
	local h = self.text:GetStringHeight()
	self.frame:SetSize(math.max(120, w + 8), math.max(24, h + 4))
	self.frame:Show()
end

function Warnings:GetTabOptions()
	local w = self
	local function get(key)
		return function()
			return w.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			w.db.profile[key] = value
			w:Refresh()
		end
	end

	local args = {
		enabled = {
			type = "toggle",
			name = "Enabled",
			order = 1,
			desc = "Shows warnings such as low ammo in rested areas",
			get = get("enabled"),
			set = set("enabled"),
		},
		font = {
			type = "select",
			name = "Font",
			order = 2,
			dialogControl = "LSM30_Font",
			values = function()
				return ns.Media:Values("font", w.db.profile.font)
			end,
			get = get("font"),
			set = set("font"),
		},
		fontSize = {
			type = "range",
			name = "Font size",
			order = 3,
			min = 8,
			max = 32,
			step = 1,
			get = get("fontSize"),
			set = set("fontSize"),
		},
		warningsHeader = { type = "header", name = "Warnings", order = 10 },
	}

	if #self.warnings == 0 then
		args.none = { type = "description", order = 11, name = "Your class has no warnings yet." }
	end

	for i, warning in ipairs(self.warnings) do
		local key = warning.key
		args["warning_" .. key] = {
			type = "toggle",
			name = warning.name,
			order = 10 + 2 * i - 1,
			get = function()
				return (L.Settings(warning, w.db.profile))
			end,
			set = function(_, value)
				if type(w.db.profile.warnings) ~= "table" then
					w.db.profile.warnings = {}
				end
				w.db.profile.warnings[key] = value
				w:Refresh()
			end,
		}
		args["threshold_" .. key] = {
			type = "range",
			name = warning.name .. " below",
			order = 10 + 2 * i,
			min = 1,
			max = 4000,
			step = 1,
			bigStep = 50,
			get = function()
				local _, threshold = L.Settings(warning, w.db.profile)
				return threshold
			end,
			set = function(_, value)
				if type(w.db.profile.thresholds) ~= "table" then
					w.db.profile.thresholds = {}
				end
				w.db.profile.thresholds[key] = value
				w:Refresh()
			end,
			disabled = function()
				return not (L.Settings(warning, w.db.profile))
			end,
		}
	end

	return { type = "group", name = "Warnings", args = args }
end

function Warnings:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, fn in pairs({
					IsResting = IsResting,
					GetInventoryItemID = GetInventoryItemID,
					GetInventoryItemCount = GetInventoryItemCount,
					["C_Item.GetItemInfoInstant"] = C_Item and C_Item.GetItemInfoInstant,
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
			name = "reading",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local reading = self:Read()
				return "INFO",
					self.class,
					reading.resting,
					reading.weaponClass,
					reading.weaponSubclass,
					reading.ammoClass,
					reading.ammoSubclass,
					reading.ammoCount
			end,
		},
		{
			name = "warnings",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local out = {}
				for _, entry in ipairs(self.active) do
					out[#out + 1] = entry.warning.key .. "=" .. tostring(entry.count)
				end
				if #out == 0 then
					return "INFO", self.class, "none"
				end
				return "INFO", unpack(out, 1, #out)
			end,
		},
		{
			name = "frame",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local list = self:Shown()
				local shown = self.frame:IsShown()
				local expected = #list > 0
				return (shown == expected) and "PASS" or "FAIL", shown, #list
			end,
		},
	}
end
