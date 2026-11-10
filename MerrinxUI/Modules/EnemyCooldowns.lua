local addonName, ns = ...

local L = ns.EnemyCooldownLogic

local EnemyCooldowns = {}
ns.EnemyCooldowns = EnemyCooldowns

local ICON_GAP = 2
local ICON_SPACING = 2
local TICK_INTERVAL = 0.5
local FALLBACK_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"

local function ResolveSpellName(spellID)
	local name = C_Spell.GetSpellName(spellID)
	if issecretvalue(name) then
		return nil
	end
	return name
end

local function DropState(self, entry)
	if entry.kind == "unit" then
		self.state[entry.key] = nil
	end
end

local function ClampCooldownSize(size)
	if type(size) ~= "number" then
		return 20
	end
	if size < 12 then
		return 12
	elseif size > 40 then
		return 40
	end
	return size
end

function EnemyCooldowns:Init(module)
	self.module = module
	self.state = {}
	self.units = {}
	self.containers = setmetatable({}, { __mode = "k" })
	self.index = nil
	self.ticker = nil
	self.active = false
	self.seen = 0
	self.secret = 0
	self.unselected = 0
	self.hits = 0

	self.events = CreateFrame("Frame")
	self.events:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			self:OnSpellcastSucceeded(...)
		elseif event == "PLAYER_ENTERING_WORLD" then
			self:OnEnteringWorld()
		end
	end)
end

function EnemyCooldowns:SetActive(active)
	active = not not active
	if self.active == active then
		return
	end
	self.active = active

	if active then
		if not self.index then
			self.index = L.BuildIndex(L.SPELLS, ResolveSpellName)
		end
		self.events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
	else
		self.events:UnregisterAllEvents()
		self:StopTicker()
		for key in pairs(self.state) do
			self.state[key] = nil
		end
		for unit in pairs(self.units) do
			self.units[unit] = nil
		end
		self.seen = 0
		self.secret = 0
		self.unselected = 0
		self.hits = 0
		for _, container in pairs(self.containers) do
			for _, icon in ipairs(container.icons) do
				icon:Hide()
			end
			container:Hide()
		end
	end

	ns.Debug:Log("EnemyCooldowns", "active", active)
end

function EnemyCooldowns:GetContainer(frame)
	local container = frame.enemyCooldowns
	if not container then
		container = CreateFrame("Frame", nil, frame)
		container.icons = {}
		frame.enemyCooldowns = container
		self.containers[frame] = container
	end

	local profile = self.module.db.profile
	container:ClearAllPoints()
	container:SetPoint("LEFT", profile.levelText and frame.levelText or frame, "RIGHT", 0, 0)
	container:SetHeight(ClampCooldownSize(profile.enemyCooldownSize))
	return container
end

function EnemyCooldowns:GetIcon(container, i)
	local icon = container.icons[i]
	if not icon then
		icon = CreateFrame("Frame", nil, container)

		local texture = icon:CreateTexture(nil, "ARTWORK")
		texture:SetAllPoints(icon)
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon.texture = texture

		local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
		cooldown:SetAllPoints(icon)
		icon.cooldown = cooldown

		container.icons[i] = icon
	end
	return icon
end

function EnemyCooldowns:RenderFrame(frame, key)
	local profile = self.module.db.profile
	local container = self:GetContainer(frame)
	local records = key and L.Active(self.state, key, GetTime(), profile.enemyCooldownMax, profile.enemyCooldownSpells)
		or {}
	local n = #records
	local size = ClampCooldownSize(profile.enemyCooldownSize)

	container:SetWidth(L.RowWidth(n, size, ICON_SPACING, ICON_GAP))
	container:Show()

	for i = 1, n do
		local rec = records[i]
		local icon = self:GetIcon(container, i)
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		icon:SetPoint("LEFT", container, "LEFT", L.IconOffset(i, size, ICON_SPACING, ICON_GAP), 0)

		local texture = C_Spell.GetSpellTexture(rec.entry.id)
		if issecretvalue(texture) or not texture then
			texture = FALLBACK_TEXTURE
		end
		icon.texture:SetTexture(texture)
		icon.cooldown:SetCooldown(rec.start, rec.entry.cd)
		icon:Show()
	end

	for i = n + 1, #container.icons do
		container.icons[i]:Hide()
	end
end

function EnemyCooldowns:Render(unit)
	local entry = self.units[unit]
	if entry then
		self:RenderFrame(entry.frame, entry.key)
	end
end

function EnemyCooldowns:RenderAll()
	for unit in pairs(self.units) do
		self:Render(unit)
	end
end

function EnemyCooldowns:Attach(unit, frame)
	if not self.active then
		if frame.enemyCooldowns then
			frame.enemyCooldowns:Hide()
		end
		return
	end

	self:GetContainer(frame)

	local isPlayer = UnitIsPlayer(unit)
	if not issecretvalue(isPlayer) and isPlayer == false then
		local entry = self.units[unit]
		if entry then
			DropState(self, entry)
			self.units[unit] = nil
		end
		self:RenderFrame(frame, nil)
		return
	end

	local guid = UnitGUID(unit)
	local name, realm = UnitName(unit)
	local key, kind = L.IdentityKey(guid, name, realm, unit, issecretvalue)

	local previous = self.units[unit]
	if previous and previous.kind == "unit" and previous.key ~= key then
		self.state[previous.key] = nil
	end

	self.units[unit] = { key = key, kind = kind, frame = frame, secretSpellLogged = false }

	local playerState = issecretvalue(isPlayer) and "secret" or "player"
	local identitySecret = nil
	local castingSecret = nil
	if type(C_Secrets) == "table" then
		if type(C_Secrets.ShouldUnitIdentityBeSecret) == "function" then
			identitySecret = C_Secrets.ShouldUnitIdentityBeSecret(unit)
		end
		if type(C_Secrets.ShouldUnitSpellCastingBeSecret) == "function" then
			castingSecret = C_Secrets.ShouldUnitSpellCastingBeSecret(unit)
		end
	end
	ns.Debug:Log("EnemyCooldowns", "track", unit, kind, playerState, identitySecret, castingSecret)

	self:Render(unit)
end

function EnemyCooldowns:Detach(unit)
	local entry = self.units[unit]
	if not entry then
		return
	end

	DropState(self, entry)
	self.units[unit] = nil
	self:RenderFrame(entry.frame, nil)
end

function EnemyCooldowns:Anchor(frame)
	local profile = self.module.db.profile
	if profile.enemyCooldowns ~= true then
		return nil
	end
	return frame.enemyCooldowns
end

function EnemyCooldowns:StartTicker()
	if self.ticker then
		return
	end
	self.ticker = C_Timer.NewTicker(TICK_INTERVAL, function()
		self:OnTick()
	end)
	ns.Debug:Log("EnemyCooldowns", "ticker", "on")
end

function EnemyCooldowns:StopTicker()
	if not self.ticker then
		return
	end
	self.ticker:Cancel()
	self.ticker = nil
	ns.Debug:Log("EnemyCooldowns", "ticker", "off")
end

function EnemyCooldowns:OnTick()
	local changed = L.Prune(self.state, GetTime())
	for unit, entry in pairs(self.units) do
		if changed[entry.key] then
			self:Render(unit)
		end
	end
	if next(self.state) == nil then
		self:StopTicker()
	end
end

function EnemyCooldowns:OnSpellcastSucceeded(unit, _, spellID)
	local entry = self.units[unit]
	if not entry then
		return
	end
	self.seen = self.seen + 1

	if issecretvalue(spellID) then
		self.secret = self.secret + 1
		if not entry.secretSpellLogged then
			entry.secretSpellLogged = true
			ns.Debug:Log("EnemyCooldowns", "secret spell", unit)
		end
		return
	end

	local name = ResolveSpellName(spellID)
	local spellEntry = L.Lookup(self.index, spellID, name)
	if not spellEntry then
		return
	end

	local profile = self.module.db.profile
	if profile.enemyCooldownSpells[spellEntry.id] ~= true then
		self.unselected = self.unselected + 1
		return
	end

	L.Record(self.state, entry.key, spellEntry, GetTime())
	self.hits = self.hits + 1
	ns.Debug:Log("EnemyCooldowns", "hit", unit, spellID, name, spellEntry.id, spellEntry.cd)
	self:StartTicker()
	self:Render(unit)
end

function EnemyCooldowns:OnEnteringWorld()
	for key in pairs(self.state) do
		self.state[key] = nil
	end
	self:StopTicker()
	ns.Debug:Log("EnemyCooldowns", "reset")

	local reattach = {}
	for unit, entry in pairs(self.units) do
		reattach[unit] = entry.frame
	end
	for unit, frame in pairs(reattach) do
		self:Attach(unit, frame)
	end
end

function EnemyCooldowns:AddOptions(args)
	local module = self.module

	local function disabledUnlessActive()
		return module.db.profile.enemyCooldowns ~= true
	end

	args.enemyCooldownsHeader = { type = "header", name = "Enemy cooldowns", order = 70 }
	args.enemyCooldowns = {
		type = "toggle",
		name = "Enemy cooldowns",
		desc = "After an enemy player casts a ticked spell, shows its cooldown to the right of their plate.",
		order = 71,
		get = function()
			return module.db.profile.enemyCooldowns
		end,
		set = function(_, value)
			module.db.profile.enemyCooldowns = value
			module:Refresh()
		end,
	}
	args.enemyCooldownSize = {
		type = "range",
		name = "Cooldown icon size",
		order = 72,
		min = 12,
		max = 40,
		step = 1,
		disabled = disabledUnlessActive,
		get = function()
			return module.db.profile.enemyCooldownSize
		end,
		set = function(_, value)
			module.db.profile.enemyCooldownSize = value
			module:Refresh()
		end,
	}
	args.enemyCooldownMax = {
		type = "range",
		name = "Max cooldown icons",
		order = 73,
		min = 1,
		max = 8,
		step = 1,
		disabled = disabledUnlessActive,
		get = function()
			return module.db.profile.enemyCooldownMax
		end,
		set = function(_, value)
			module.db.profile.enemyCooldownMax = value
			module:Refresh()
		end,
	}
	args.enemyCooldownSpellsHeader = {
		type = "header",
		name = "Tracked spells",
		order = 74,
		disabled = disabledUnlessActive,
	}

	for i, spell in ipairs(L.SPELLS) do
		args["enemyCooldownSpell_" .. spell.id] = {
			type = "toggle",
			order = 74 + i,
			disabled = disabledUnlessActive,
			name = function()
				local name = ResolveSpellName(spell.id) or tostring(spell.id)
				return name .. " (" .. L.ClassLabel(spell.class) .. ")"
			end,
			desc = function()
				return string.format("%d s cooldown", spell.cd)
			end,
			get = function()
				return module.db.profile.enemyCooldownSpells[spell.id] == true
			end,
			set = function(_, value)
				module.db.profile.enemyCooldownSpells[spell.id] = value or nil
				self:RenderAll()
			end,
		}
	end
end

ns.Debug:RegisterChecks("Nameplates", function()
	local module = EnemyCooldowns.module

	local function unavailable()
		return module == nil or not module:IsEnabled()
	end

	local function AuditBaseCooldownMs(id)
		if type(GetSpellBaseCooldown) ~= "function" then
			return nil
		end
		local ms = GetSpellBaseCooldown(id)
		if issecretvalue(ms) then
			return nil
		end
		return ms
	end

	local audit = L.Audit(L.SPELLS, ResolveSpellName, AuditBaseCooldownMs)

	local function readPoint(region)
		if type(region.IsAnchoringRestricted) == "function" then
			local restricted = region:IsAnchoringRestricted()
			if issecretvalue(restricted) or restricted then
				return false
			end
		end
		local ok, p, rel, rp, x, y = pcall(region.GetPoint, region, 1)
		if not ok then
			return false
		end
		return true, p, rel, rp, x, y
	end

	local checks = {
		{
			name = "enemy cooldown spells",
			run = function()
				if unavailable() then
					return "SKIP", "module disabled"
				end
				if #audit.unresolved > 0 or #audit.duplicates > 0 or #audit.mismatched > 0 then
					local parts = {}
					if #audit.unresolved > 0 then
						table.insert(parts, "unresolved")
						for _, id in ipairs(audit.unresolved) do
							table.insert(parts, id)
						end
					end
					if #audit.duplicates > 0 then
						table.insert(parts, "duplicates")
						for _, id in ipairs(audit.duplicates) do
							table.insert(parts, id)
						end
					end
					if #audit.mismatched > 0 then
						table.insert(parts, "mismatched")
						for _, m in ipairs(audit.mismatched) do
							table.insert(parts, m.id)
							table.insert(parts, m.expected)
							table.insert(parts, m.actual)
						end
					end
					return "FAIL", unpack(parts, 1, #parts)
				end
				return "PASS", #L.SPELLS
			end,
		},
		{
			name = "enemy cooldown base cds",
			run = function()
				if unavailable() then
					return "SKIP", "module disabled"
				end
				if type(GetSpellBaseCooldown) ~= "function" then
					return "SKIP", "GetSpellBaseCooldown missing"
				end
				if #audit.unknownCd > 0 then
					return "INFO", "unknown", unpack(audit.unknownCd, 1, #audit.unknownCd)
				end
				return "PASS"
			end,
		},
		{
			name = "enemy cooldown state",
			run = function()
				if unavailable() then
					return "SKIP", "module disabled"
				end
				local tracked, guidKeys, nameKeys, unitKeys = 0, 0, 0, 0
				for _, entry in pairs(EnemyCooldowns.units) do
					tracked = tracked + 1
					if entry.kind == "guid" then
						guidKeys = guidKeys + 1
					elseif entry.kind == "name" then
						nameKeys = nameKeys + 1
					else
						unitKeys = unitKeys + 1
					end
				end
				local stateKeys = 0
				for _ in pairs(EnemyCooldowns.state) do
					stateKeys = stateKeys + 1
				end
				local ticked = 0
				for _ in pairs(module.db.profile.enemyCooldownSpells) do
					ticked = ticked + 1
				end
				return "INFO", EnemyCooldowns.active, ticked, tracked, guidKeys, nameKeys, unitKeys, stateKeys
			end,
		},
		{
			name = "enemy cooldown events",
			run = function()
				if unavailable() then
					return "SKIP", "module disabled"
				end
				return "INFO",
					EnemyCooldowns.seen,
					EnemyCooldowns.secret,
					EnemyCooldowns.unselected,
					EnemyCooldowns.hits
			end,
		},
		{
			name = "enemy cooldown ticker",
			run = function()
				if unavailable() or not EnemyCooldowns.active then
					return "SKIP", "inactive"
				end
				local running = EnemyCooldowns.ticker ~= nil
				local hasState = next(EnemyCooldowns.state) ~= nil
				return (running == hasState) and "PASS" or "FAIL", running, hasState
			end,
		},
	}

	local units = {}
	for unit in pairs(EnemyCooldowns.units) do
		table.insert(units, unit)
	end
	table.sort(units)

	for _, unit in ipairs(units) do
		table.insert(checks, {
			name = "enemy cooldown icons " .. unit,
			run = function()
				if unavailable() then
					return "SKIP", "module disabled"
				end
				local entry = EnemyCooldowns.units[unit]
				if not entry then
					return "SKIP", "not tracked"
				end
				local container = entry.frame.enemyCooldowns
				if not container then
					return "SKIP", "no container"
				end

				local now = GetTime()
				local bucket = EnemyCooldowns.state[entry.key]
				if bucket then
					for _, rec in pairs(bucket) do
						if rec.expires >= now - 2 * TICK_INTERVAL and rec.expires <= now then
							return "SKIP", "expiring"
						end
					end
				end

				local profile = module.db.profile
				local size = ClampCooldownSize(profile.enemyCooldownSize)
				local records = L.Active(
					EnemyCooldowns.state,
					entry.key,
					now,
					profile.enemyCooldownMax,
					profile.enemyCooldownSpells
				)
				local n = #records

				local shown = 0
				for _, icon in ipairs(container.icons) do
					if icon:IsShown() then
						shown = shown + 1
					end
				end

				local ok = shown == n
				local pointsRestricted = false
				for i = 1, n do
					local icon = container.icons[i]
					if not icon or not icon:IsShown() then
						ok = false
						break
					end

					if math.abs(icon:GetWidth() - size) > 0.5 then
						ok = false
						break
					end

					local ptOk, point, relativeTo, relativePoint, x, y = readPoint(icon)
					if not ptOk then
						pointsRestricted = true
					else
						local expectedX = L.IconOffset(i, size, ICON_SPACING, ICON_GAP)
						if
							point ~= "LEFT"
							or relativeTo ~= container
							or relativePoint ~= "LEFT"
							or issecretvalue(x)
							or issecretvalue(y)
							or math.abs(x - expectedX) > 0.5
							or math.abs(y) > 0.5
						then
							ok = false
							break
						end
					end
				end

				if pointsRestricted then
					return ok and "PASS" or "FAIL", shown, n, "points restricted"
				end
				return ok and "PASS" or "FAIL", shown, n
			end,
		})
	end

	table.insert(checks, {
		name = "enemy cooldown containers",
		run = function()
			if unavailable() then
				return "SKIP", "module disabled"
			end

			local trackedFrames = {}
			for _, entry in pairs(EnemyCooldowns.units) do
				trackedFrames[entry.frame] = true
			end

			for frame, container in pairs(EnemyCooldowns.containers) do
				if container:GetParent() ~= frame then
					return "FAIL", "parent mismatch"
				end
				if not trackedFrames[frame] then
					local shown = 0
					for _, icon in ipairs(container.icons) do
						if icon:IsShown() then
							shown = shown + 1
						end
					end
					if shown > 0 then
						return "FAIL", "foreign icons"
					end
				end
			end

			return "PASS"
		end,
	})

	return checks
end)
