local addonName, ns = ...

local L = ns.BuffReminderLogic
local FontLogic = ns.FontLogic

local TICK = 1
local SPACING = 4
local FALLBACK_TEXTURE = 134400

local BuffReminders = ns.addon:NewModule("BuffReminders", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = true,
		lowMinutes = 3,
		hideInCombat = true,
		iconSize = 36,
		font = FontLogic.GLOBAL,
		fontSize = 12,
		sound = "None",
		buffs = {},
		position = { point = "CENTER", x = 0, y = 120 },
	},
	char = {
		castLine = {},
	},
}

local function isKnown(id)
	if type(C_SpellBook) ~= "table" then
		return false
	end
	if type(C_SpellBook.IsSpellKnown) == "function" and C_SpellBook.IsSpellKnown(id) == true then
		return true
	end
	return type(C_SpellBook.IsSpellInSpellBook) == "function"
		and type(Enum.SpellBookSpellBank) == "table"
		and C_SpellBook.IsSpellInSpellBook(id, Enum.SpellBookSpellBank.Player, false) == true
end

local function aurasSecret()
	return type(C_Secrets) == "table"
		and type(C_Secrets.ShouldAurasBeSecret) == "function"
		and C_Secrets.ShouldAurasBeSecret() == true
end

-- Returns the aura of the line, nil when it is not on the player, or false when it cannot be read.
local function readLine(line)
	local name = C_Spell.GetSpellName(line[1])
	if type(name) ~= "string" or issecretvalue(name) then
		return false
	end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
	if not ok or issecretvalue(aura) then
		return false
	end
	if aura and (issecretvalue(aura.duration) or issecretvalue(aura.expirationTime)) then
		return false
	end
	return aura
end

local function spellName(id)
	local name = C_Spell.GetSpellName(id)
	if type(name) == "string" and not issecretvalue(name) then
		return name
	end
	return nil
end

local function showTooltip(owner)
	if owner.spellID then
		GameTooltip:SetOwner(owner, "ANCHOR_TOP")
		GameTooltip:SetSpellByID(owner.spellID)
		GameTooltip:Show()
	end
end

local function hideTooltip()
	GameTooltip:Hide()
end

function BuffReminders:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("BuffReminders", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	local _, class = UnitClass("player")
	self.class = class
	self.buffs = L.ForClass(class)
	self.known = {}
	self.states = {}
	self.announced = {}
	self.remaining = {}
	self.icons = {}
	self.clicks = {}
	self.clicksPending = false
	self.reads = 0
	self.unreadable = 0

	self.events = CreateFrame("Frame")
	self.events:SetScript("OnEvent", function()
		self:Update()
	end)
	self:Build()
end

function BuffReminders:OnEnable()
	self.events:RegisterUnitEvent("UNIT_AURA", "player")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnSpellsChanged")
	self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "Update")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "Update")
	self:RegisterEvent("PLAYER_DEAD", "Update")
	self:RegisterEvent("PLAYER_ALIVE", "Update")
	self:RegisterEvent("PLAYER_UNGHOST", "Update")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "Render")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")
	self.ticker = C_Timer.NewTicker(TICK, function()
		self:Update()
	end)
	ns.Mover:Apply(self.frame)
	self:OnSpellsChanged()
end

function BuffReminders:OnDisable()
	self.events:UnregisterAllEvents()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	self.frame:Hide()
	self:QueueClicks()
end

function BuffReminders:Refresh()
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

function BuffReminders:OnMediaChanged(_, mediatype, key)
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", self.db.profile.font)) then
		self:Layout()
	end
end

function BuffReminders:OnSpellsChanged()
	for _, buff in ipairs(self.buffs) do
		self.known[buff.key] = L.Known(buff, isKnown)
	end
	self:Layout()
	self:Update()
end

function BuffReminders:Watched(buff)
	local on = self.db.profile.buffs[buff.key]
	if on == nil then
		on = not buff.off
	end
	return on and self.known[buff.key] == true
end

function BuffReminders:Update()
	if not self:IsEnabled() then
		return
	end
	if aurasSecret() then
		self:Render()
		return
	end
	local now = GetTime()
	local low = self.db.profile.lowMinutes * 60
	local states = {}
	for _, buff in ipairs(self.buffs) do
		if self:Watched(buff) then
			local lineStates = {}
			local readable = true
			for lineIndex, line in ipairs(buff.lines) do
				local aura = readLine(line)
				if aura == false then
					readable = false
					break
				end
				if
					type(aura) == "table"
					and not issecretvalue(aura.isFromPlayerOrPlayerPet)
					and aura.isFromPlayerOrPlayerPet == true
				then
					self.db.char.castLine[buff.key] = lineIndex
				end
				lineStates[#lineStates + 1] = { L.Status(aura, now, low) }
			end
			self.reads = self.reads + 1
			if readable then
				states[buff.key], self.remaining[buff.key] = L.Best(lineStates)
			else
				self.unreadable = self.unreadable + 1
				states[buff.key] = self.states[buff.key]
			end
		end
	end

	self.states = states
	-- Alerts compare against what was last on screen, so a buff that dropped while hidden alerts once it shows.
	if not self:Hidden() then
		local alerts = L.Alerts(self.announced, states)
		self.announced = states
		if #alerts > 0 then
			ns.Debug:Log("BuffReminders", "alert", unpack(alerts, 1, #alerts))
			ns.Media:PlaySound(self.db.profile.sound)
		end
	end
	self:Render()
end

function BuffReminders:Build()
	local frame = CreateFrame("Frame", addonName .. "BuffReminders", UIParent)
	frame:SetSize(1, 1)
	frame:Hide()
	self.frame = frame
	ns.Mover:Register(frame, "Buff Reminders", function()
		return self.db.profile.position
	end)
end

function BuffReminders:Icon(i)
	local icon = self.icons[i]
	if icon then
		return icon
	end
	icon = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
	icon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	icon:SetBackdropBorderColor(0, 0, 0, 1)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetPoint("TOPLEFT", 1, -1)
	icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.text = icon:CreateFontString(nil, "OVERLAY")
	icon.text:SetPoint("TOP", icon, "BOTTOM", 0, -2)
	icon:EnableMouse(true)
	icon:SetScript("OnEnter", showTooltip)
	icon:SetScript("OnLeave", hideTooltip)
	self.icons[i] = icon
	self:StyleIcon(icon)
	return icon
end

function BuffReminders:StyleIcon(icon)
	local p = self.db.profile
	icon:SetSize(p.iconSize, p.iconSize)
	ns.Media:SetFont(icon.text, p.font, p.fontSize, "OUTLINE")
end

function BuffReminders:Layout()
	local p = self.db.profile
	for _, icon in ipairs(self.icons) do
		self:StyleIcon(icon)
	end
	self.frame:SetHeight(p.iconSize + p.fontSize + 4)
	self:Render()
end

function BuffReminders:Shown()
	local list = {}
	local preview = ns.Mover:IsUnlocked()
	for _, buff in ipairs(self.buffs) do
		local state = self.states[buff.key]
		if self:Watched(buff) and (preview or state == "missing" or state == "low") then
			list[#list + 1] = buff
		end
	end
	return list, preview
end

function BuffReminders:Hidden()
	if ns.Mover:IsUnlocked() then
		return false
	end
	if UnitIsDeadOrGhost("player") then
		return true
	end
	return self.db.profile.hideInCombat and InCombatLockdown()
end

function BuffReminders:Render()
	if not self:IsEnabled() then
		return
	end
	local list, preview = self:Shown()
	if #list == 0 or self:Hidden() then
		self.frame:Hide()
		self:QueueClicks()
		return
	end
	local size = self.db.profile.iconSize
	for i, buff in ipairs(list) do
		local icon = self:Icon(i)
		local id = self:CastSpell(buff)
		icon.spellID = id
		icon.castName = spellName(id)
		icon.texture:SetTexture(C_Spell.GetSpellTexture(id) or FALLBACK_TEXTURE)
		icon:ClearAllPoints()
		icon:SetPoint("LEFT", self.frame, "LEFT", (i - 1) * (size + SPACING), 0)
		local state = self.states[buff.key]
		if state == "low" then
			icon.text:SetText(L.FormatTime(self.remaining[buff.key]))
			icon.text:SetTextColor(1, 0.82, 0)
			icon.texture:SetDesaturated(false)
		elseif state == "missing" or not preview then
			icon.text:SetText("Missing")
			icon.text:SetTextColor(1, 0.3, 0.25)
			icon.texture:SetDesaturated(true)
		else
			icon.text:SetText("")
			icon.texture:SetDesaturated(false)
		end
		icon:Show()
	end
	for i = #list + 1, #self.icons do
		self.icons[i]:Hide()
	end
	self.frame:SetWidth(#list * size + (#list - 1) * SPACING)
	self.frame:Show()
	self:QueueClicks()
end

function BuffReminders:CastSpell(buff)
	local i = L.CastLine(buff, isKnown, self.db.char.castLine[buff.key])
	return buff.lines[i or 1][1]
end

function BuffReminders:QueueClicks()
	self.clicksPending = not ns.Combat:Run("BuffReminders:Clicks", function()
		self.clicksPending = false
		self:ApplyClicks()
	end)
end

function BuffReminders:ClickTarget(i)
	local icon = self.icons[i]
	if not icon or not icon:IsShown() then
		return nil
	end
	if not self:IsEnabled() or not self.frame:IsShown() or ns.Mover:IsUnlocked() then
		return nil
	end
	return icon.castName
end

function BuffReminders:ClickButton(i)
	local button = self.clicks[i]
	if button then
		return button
	end
	if not self.clickHeader then
		local header = CreateFrame("Frame", addonName .. "BuffRemindersClicks", UIParent)
		header:SetFrameStrata(self.frame:GetFrameStrata())
		RegisterStateDriver(header, "visibility", "[combat] hide; show")
		self.clickHeader = header
	end
	button =
		CreateFrame("Button", addonName .. "BuffRemindersClick" .. i, self.clickHeader, "SecureActionButtonTemplate")
	button:SetAttribute("type", "spell")
	button:SetAttribute("unit", "player")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetFrameLevel(self.frame:GetFrameLevel() + 5)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", hideTooltip)
	button:Hide()
	self.clicks[i] = button
	return button
end

-- Never anchored to the icons: that would make the insecure icon frame protected too.
function BuffReminders:ApplyClicks()
	for i, icon in ipairs(self.icons) do
		local name = self:ClickTarget(i)
		local x, y = icon:GetCenter()
		if x == nil or issecretvalue(x) or issecretvalue(y) then
			name = nil
		end
		if name then
			local button = self:ClickButton(i)
			if button:GetAttribute("spell") ~= name then
				button:SetAttribute("spell", name)
			end
			button.spellID = icon.spellID
			local ratio = icon:GetEffectiveScale() / button:GetEffectiveScale()
			button:ClearAllPoints()
			button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * ratio, y * ratio)
			button:SetSize(icon:GetWidth() * ratio, icon:GetHeight() * ratio)
			button:Show()
		elseif self.clicks[i] then
			self.clicks[i]:Hide()
		end
	end
	for i = #self.icons + 1, #self.clicks do
		if self.clicks[i] then
			self.clicks[i]:Hide()
		end
	end
end

function BuffReminders:GetTabOptions()
	local br = self
	local function get(key)
		return function()
			return br.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			br.db.profile[key] = value
			br:Refresh()
		end
	end
	local function range(key, name, order, min, max, step, desc)
		return {
			type = "range",
			name = name,
			desc = desc,
			order = order,
			min = min,
			max = max,
			step = step,
			get = get(key),
			set = set(key),
		}
	end

	local args = {
		enabled = {
			type = "toggle",
			name = "Enabled",
			order = 1,
			desc = "Shows your class buffs when they are missing or about to run out",
			get = get("enabled"),
			set = set("enabled"),
		},
		hideInCombat = {
			type = "toggle",
			name = "Hide in combat",
			order = 2,
			get = get("hideInCombat"),
			set = set("hideInCombat"),
		},
		lowMinutes = range("lowMinutes", "Warn when less than (min)", 3, 1, 10, 1),
		iconSize = range("iconSize", "Icon size", 4, 16, 64, 1),
		font = {
			type = "select",
			name = "Font",
			order = 5,
			dialogControl = "LSM30_Font",
			values = function()
				return ns.Media:Values("font", br.db.profile.font)
			end,
			get = get("font"),
			set = set("font"),
		},
		fontSize = range("fontSize", "Font size", 6, 8, 20, 1),
		sound = {
			type = "select",
			name = "Alert sound",
			order = 7,
			desc = "Plays when a buff goes missing or starts running low",
			values = function()
				return ns.Media:SoundValues()
			end,
			get = get("sound"),
			set = function(_, value)
				br.db.profile.sound = value
				ns.Media:PlaySound(value)
			end,
		},
		buffsHeader = { type = "header", name = "Buffs", order = 10 },
	}

	if #self.buffs == 0 then
		args.none = { type = "description", order = 11, name = "Your class has no buffs to track." }
	end
	for i, buff in ipairs(self.buffs) do
		local id = buff.lines[1][1]
		args["buff_" .. buff.key] = {
			type = "toggle",
			name = function()
				local name = C_Spell.GetSpellName(id) or buff.key
				if br.known[buff.key] == false then
					return name .. " (not learned)"
				end
				return name
			end,
			order = 10 + i,
			get = function()
				local on = br.db.profile.buffs[buff.key]
				if on == nil then
					return not buff.off
				end
				return on
			end,
			set = function(_, value)
				br.db.profile.buffs[buff.key] = value
				br:Refresh()
			end,
		}
	end

	return { type = "group", name = "BuffReminders", args = args }
end

function BuffReminders:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, fn in pairs({
					["C_UnitAuras.GetAuraDataBySpellName"] = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName,
					["C_SpellBook.IsSpellKnown"] = C_SpellBook and C_SpellBook.IsSpellKnown,
					["C_Spell.GetSpellName"] = C_Spell and C_Spell.GetSpellName,
					["C_Spell.GetSpellTexture"] = C_Spell and C_Spell.GetSpellTexture,
					["C_Secrets.ShouldAurasBeSecret"] = C_Secrets and C_Secrets.ShouldAurasBeSecret,
					UnitIsDeadOrGhost = UnitIsDeadOrGhost,
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
			name = "spells",
			run = function()
				local unresolved = {}
				for _, buff in ipairs(self.buffs) do
					for _, line in ipairs(buff.lines) do
						local name = C_Spell.GetSpellName(line[1])
						if type(name) ~= "string" then
							unresolved[#unresolved + 1] = line[1]
						end
					end
				end
				if #unresolved > 0 then
					return "FAIL", self.class, unpack(unresolved, 1, #unresolved)
				end
				return "PASS", self.class, #self.buffs
			end,
		},
		{
			name = "buffs",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local out = {}
				for _, buff in ipairs(self.buffs) do
					local state = self:Watched(buff) and (self.states[buff.key] or "?") or "off"
					out[#out + 1] = string.format(
						"%s=%s/%s/%s",
						buff.key,
						tostring(self.known[buff.key]),
						state,
						L.FormatTime(self.remaining[buff.key])
					)
				end
				if #out == 0 then
					return "INFO", self.class, "none"
				end
				return "INFO", unpack(out, 1, #out)
			end,
		},
		{
			name = "reads",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return "INFO", self.reads, self.unreadable, aurasSecret()
			end,
		},
		{
			name = "frame",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local list = self:Shown()
				local expected = #list > 0 and not self:Hidden()
				local shown = self.frame:IsShown()
				return (shown == expected) and "PASS" or "FAIL", shown, #list
			end,
		},
		{
			name = "click",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if self.frame:IsProtected() then
					return "FAIL", "frame protected"
				end
				if InCombatLockdown() then
					local spells = {}
					for _, button in ipairs(self.clicks) do
						if button:IsShown() then
							spells[#spells + 1] = button:GetAttribute("spell")
						end
					end
					return "INFO", "combat", #self.clicks, self.clicksPending, unpack(spells, 1, #spells)
				end
				if self.clicksPending then
					return "FAIL"
				end
				if self.clickHeader and not self.clickHeader:IsShown() then
					return "FAIL"
				end
				local shown = {}
				for i = 1, #self.icons do
					local target = self:ClickTarget(i)
					local button = self.clicks[i]
					local buttonShown = button ~= nil and button:IsShown()
					if (target ~= nil) ~= buttonShown then
						return "FAIL"
					end
					if buttonShown then
						if button:GetAttribute("spell") ~= target then
							return "FAIL"
						end
						local icon = self.icons[i]
						local ix, iy = icon:GetCenter()
						local bx, by = button:GetCenter()
						if not (issecretvalue(ix) or issecretvalue(iy) or issecretvalue(bx) or issecretvalue(by)) then
							local iScale = icon:GetEffectiveScale()
							local bScale = button:GetEffectiveScale()
							if math.abs(ix * iScale - bx * bScale) > 1 or math.abs(iy * iScale - by * bScale) > 1 then
								return "FAIL"
							end
						end
						shown[#shown + 1] = target
					end
				end
				return "PASS", #self.clicks, C_CVar.GetCVar("ActionButtonUseKeyDown"), unpack(shown, 1, #shown)
			end,
		},
	}
end
