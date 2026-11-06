local addonName, ns = ...

local L = ns.DamageMeterLogic
local Accent = ns.Theme.color.accent

local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local MELEE_ICON = 135274
local ENEMY_COLOR = { 0xDD / 255, 0x31 / 255, 0x31 / 255 }
local HEAL_COLOR = { 0.10, 0.50, 0.10 }
local HURT_COLOR = { 0.60, 0.08, 0.08 }

local D = {}
ns.DamageMeterData = D

D.ENEMY_COLOR = ENEMY_COLOR

local function isSecret(v)
	return issecretvalue(v) == true
end
D.IsSecret = isSecret

local function plain(v)
	if isSecret(v) then
		return nil
	end
	return v
end
D.Plain = plain

function D.Abbrev(n)
	if n == nil then
		return "0"
	end
	return AbbreviateLargeNumbers(n)
end

function D.SessionType(name)
	return L.EnumKey(Enum.DamageMeterSessionType, name)
end

function D.TypeValue(key)
	return L.EnumKey(Enum.DamageMeterType, key)
end

-- view: { session = "Current" | "Overall", sessionID = number | nil, type = key }
function D.Session(view, typeKey)
	local typeValue = D.TypeValue(typeKey or view.type)
	if typeValue == nil then
		return nil
	end
	if view.sessionID then
		local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, view.sessionID, typeValue)
		return ok and s or nil
	end
	local sessionType = D.SessionType(view.session)
	if sessionType == nil then
		return nil
	end
	return C_DamageMeter.GetCombatSessionFromType(sessionType, typeValue)
end

function D.Source(view, guid, cid, typeKey)
	local typeValue = D.TypeValue(typeKey or view.type)
	if typeValue == nil then
		return nil
	end
	local ok, data
	if view.sessionID then
		ok, data = pcall(C_DamageMeter.GetCombatSessionSourceFromID, view.sessionID, typeValue, guid, cid)
	else
		local sessionType = D.SessionType(view.session)
		if sessionType == nil then
			return nil
		end
		ok, data = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, typeValue, guid, cid)
	end
	return ok and data or nil
end

function D.Segments()
	local mapped = {}
	for _, entry in ipairs(C_DamageMeter.GetAvailableCombatSessions() or {}) do
		table.insert(mapped, {
			sessionID = plain(entry.sessionID),
			name = plain(entry.name),
			durationSeconds = plain(entry.durationSeconds),
		})
	end
	return mapped
end

function D.SegmentDuration(sessionID)
	for _, entry in ipairs(D.Segments()) do
		if entry.sessionID == sessionID then
			return entry.durationSeconds
		end
	end
	return nil
end

function D.SessionDuration(sessionName)
	local sessionType = D.SessionType(sessionName)
	if sessionType == nil or type(C_DamageMeter.GetSessionDurationSeconds) ~= "function" then
		return nil
	end
	local d = C_DamageMeter.GetSessionDurationSeconds(sessionType)
	if type(d) == "number" and not isSecret(d) then
		return d
	end
	return nil
end

function D.ViewDuration(view)
	if view.sessionID then
		return D.SegmentDuration(view.sessionID)
	end
	return D.SessionDuration(view.session)
end

function D.IsOwn(src)
	local own = src and src.isLocalPlayer
	if own == nil or isSecret(own) then
		return false
	end
	return own == true
end

function D.ClassColor(class)
	if class == nil or isSecret(class) then
		return nil
	end
	local c = RAID_CLASS_COLORS[class]
	if c then
		return c.r, c.g, c.b
	end
	return nil
end

function D.AccentRGB()
	return Accent[1], Accent[2], Accent[3]
end

function D.DisplayName(name)
	if name == nil then
		return "Unknown"
	end
	if isSecret(name) then
		return name
	end
	return L.ShortName(name) or name
end

-- In combat a group row's guid is secret, while its class and spec icon stay
-- readable. Out of combat the Overall session's sources are banked by
-- "CLASS:specIcon"; a key two sources share is banked false (ambiguous).
-- Only inside a party instance, where the group is small enough for the key
-- to be unique.
local keyGuid = {}

local function allyZone()
	local _, instType = IsInInstance()
	return instType == "party"
end

function D.Snapshot()
	if InCombatLockdown() or not allyZone() then
		return
	end
	local ok, s = pcall(
		C_DamageMeter.GetCombatSessionFromType,
		Enum.DamageMeterSessionType.Overall,
		Enum.DamageMeterType.DamageDone
	)
	if not ok or not s or not s.combatSources then
		return
	end
	for _, src in ipairs(s.combatSources) do
		local g, cls, icon = src.sourceGUID, src.classFilename, src.specIconID
		if
			type(g) == "string"
			and type(cls) == "string"
			and type(icon) == "number"
			and not (isSecret(g) or isSecret(cls) or isSecret(icon))
		then
			local key = cls .. ":" .. icon
			if keyGuid[key] ~= nil and keyGuid[key] ~= g then
				keyGuid[key] = false
			else
				keyGuid[key] = g
			end
		end
	end
end

function D.WipeSnapshot()
	wipe(keyGuid)
end

function D.SnapshotSize()
	local n = 0
	for _ in pairs(keyGuid) do
		n = n + 1
	end
	return n
end

function D.GroupGUID(src)
	if not src or not allyZone() then
		return nil
	end
	local cls, icon = src.classFilename, src.specIconID
	if type(cls) ~= "string" or type(icon) ~= "number" or isSecret(cls) or isSecret(icon) then
		return nil
	end
	return keyGuid[cls .. ":" .. icon] or nil
end

function D.HasRecap(src)
	local id = src and src.deathRecapID
	if id == nil or isSecret(id) or id <= 0 or type(C_DeathRecap) ~= "table" then
		return false
	end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents, id)
	return ok and type(events) == "table" and #events > 0
end

-- The guid/creature pair a breakdown fetch may pass, or nil when the row
-- stays unreadable until combat ends.
function D.FetchIDs(src, typeKey)
	if not src then
		return nil
	end
	local guid, cid = src.sourceGUID, src.sourceCreatureID
	if guid == nil and cid == nil then
		return nil
	end
	if typeKey == "Deaths" then
		return guid, cid
	end
	if isSecret(guid) or isSecret(cid) then
		if D.IsOwn(src) then
			return UnitGUID("player"), nil
		end
		local g = D.GroupGUID(src)
		if g then
			return g, nil
		end
		return nil
	end
	return guid, cid
end

function D.SpellIcon(spellID)
	if spellID == nil then
		return nil
	end
	local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
	if ok and type(tex) ~= "nil" then
		return tex
	end
	return nil
end

function D.SpellName(spellID)
	if spellID == nil then
		return nil
	end
	local ok, name = pcall(C_Spell.GetSpellName, spellID)
	if ok and type(name) ~= "nil" then
		return name
	end
	return nil
end

-- Paints the source's class or spec icon; returns the width it takes.
function D.ApplyIcon(tex, class, specIcon, size, profile)
	local style = profile.iconStyle
	local zoom = (profile.iconZoom or 6) / 100
	if style == "none" or class == nil or isSecret(class) or class == "" then
		tex:Hide()
		return 0
	end
	if style == "spec" and type(specIcon) == "number" and not isSecret(specIcon) and specIcon ~= 0 then
		tex:SetTexture(specIcon)
		tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
	else
		local coords = CLASS_ICON_TCOORDS[class]
		if not coords then
			tex:Hide()
			return 0
		end
		tex:SetTexture(CLASS_ICONS)
		tex:SetTexCoord(L.IconCoords(coords, zoom))
	end
	tex:SetSize(size, size)
	tex:Show()
	return size
end

local targetsCache = {}

function D.WipeTargets()
	wipe(targetsCache)
end

local function viewKey(view)
	return tostring(view.session) .. "|" .. tostring(view.sessionID)
end

local function playerTargets(view, rawName)
	if rawName == nil or isSecret(rawName) or InCombatLockdown() then
		return nil
	end
	local key = viewKey(view)
	if targetsCache.key ~= key then
		targetsCache.key = key
		targetsCache.map = nil
		local session = D.Session(view, "EnemyDamageTaken")
		local enemies = {}
		for i, enemy in ipairs(session and session.combatSources or {}) do
			local cid = plain(enemy.sourceCreatureID)
			local data = D.Source(view, enemy.sourceGUID, enemy.sourceCreatureID, "EnemyDamageTaken")
			local attackers = {}
			for _, spell in ipairs(data and data.combatSpells or {}) do
				local det = spell.combatSpellDetails
				local name = det and plain(det.unitName)
				local amount = plain(spell.totalAmount)
				if type(name) == "string" and type(amount) == "number" then
					table.insert(attackers, { name = name, amount = amount })
				end
			end
			table.insert(enemies, { key = cid or i, name = plain(enemy.name) or "Unknown", attackers = attackers })
		end
		targetsCache.map = L.TargetsByPlayer(enemies, D.ViewDuration(view))
	end
	local list = targetsCache.map and targetsCache.map[rawName]
	if not list or #list == 0 then
		return nil
	end
	return L.Top(list, 3)
end

local function spellRows(data, maxRows, classColor)
	local spells = data and data.combatSpells
	if not spells or #spells == 0 then
		return nil
	end
	local amounts = {}
	for i, spell in ipairs(spells) do
		local amount = spell.totalAmount
		if amount == nil or (not isSecret(amount) and type(amount) ~= "number") then
			amount = 0
		end
		amounts[i] = amount
	end
	local total = L.Total(amounts, isSecret)
	local rows = {}
	for i = 1, math.min(#spells, maxRows) do
		local spell = spells[i]
		local amount = amounts[i]
		local text = D.Abbrev(amount)
		local pct = total and L.PercentText(amount, total)
		if pct then
			text = text .. "  " .. pct
		end
		table.insert(rows, {
			icon = D.SpellIcon(spell.spellID),
			label = D.SpellName(spell.spellID) or spell.creatureName or "Unknown",
			amount = text,
			value = amount,
			max = amounts[1],
			color = classColor,
			spellID = plain(spell.spellID),
		})
	end
	return rows
end

local function recapRows(src, maxRows)
	local id = src.deathRecapID
	if id == nil or isSecret(id) or id <= 0 then
		return nil
	end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents, id)
	if not ok or type(events) ~= "table" or #events == 0 then
		return nil
	end
	local maxHP = 1
	local okHP, hp = pcall(C_DeathRecap.GetRecapMaxHealth, id)
	if okHP and hp ~= nil then
		maxHP = hp
	end
	local rows = {}
	for _, r in ipairs(L.RecapRows(events, maxHP, isSecret, maxRows)) do
		local row = {
			icon = D.SpellIcon(r.spellID) or MELEE_ICON,
			color = r.isHeal and HEAL_COLOR or HURT_COLOR,
			spellID = plain(r.spellID),
		}
		if r.before then
			row.labelFormat, row.labelArgs = "-%.1fs %s", { r.before, r.spellName }
		else
			row.labelFormat, row.labelArgs = "%s", { r.spellName }
		end
		if r.hpPct then
			row.value, row.max = r.hpPct, 1
		else
			row.value, row.max = r.currentHP or 0, maxHP
		end
		local pctText = r.hpPct and string.format(" (%.0f%%)", r.hpPct * 100) or ""
		local amount = r.amount or 0
		if isSecret(amount) then
			row.amountFormat, row.amountArgs = "%s%s", { D.Abbrev(amount), pctText }
		else
			local text = (r.isHeal and "+" or "-") .. D.Abbrev(math.abs(amount))
			local overkill = plain(r.overkill)
			if r.isFatal and type(overkill) == "number" and overkill > 0 then
				text = text .. " |cffff3333(" .. D.Abbrev(overkill) .. " overkill)|r"
			end
			row.amount = text .. pctText
		end
		table.insert(rows, row)
	end
	return rows
end

local function attackerRows(data, view, profile, maxRows)
	local spells = data and data.combatSpells
	if not spells or #spells == 0 then
		return nil
	end
	local entries = {}
	for _, spell in ipairs(spells) do
		local det = spell.combatSpellDetails
		if det and det.unitName ~= nil then
			table.insert(entries, {
				name = det.unitName,
				class = plain(det.unitClassFilename),
				specIcon = plain(det.specIconID),
				amount = spell.totalAmount or 0,
				perSec = spell.amountPerSecond,
			})
		end
	end
	local players = L.AggregateAttackers(entries, D.ViewDuration(view), isSecret)
	if #players == 0 then
		return nil
	end
	local rows = {}
	for i = 1, math.min(#players, maxRows) do
		local p = players[i]
		local r, g, b = D.ClassColor(p.class)
		table.insert(rows, {
			class = p.class,
			specIcon = p.specIcon,
			label = D.DisplayName(p.name),
			amount = L.FormatValue(profile.numberFormat, p.total, p.perSec, D.Abbrev, isSecret),
			value = p.total,
			max = players[1].total,
			color = r and { r, g, b } or { D.AccentRGB() },
		})
	end
	return rows
end

-- result: { title, rows, targets, message }
function D.Breakdown(view, src, profile, maxRows)
	local name = D.DisplayName(src and src.name)
	local typeKey = view.type
	if typeKey == "Deaths" then
		local rows = src and recapRows(src, maxRows)
		return {
			title = { "%s's Death Recap", name },
			rows = rows,
			message = not rows and "No death recap available" or nil,
		}
	end

	local title = { "%s's %s Breakdown", name, L.TypeLabel(typeKey) }
	local guid, cid = D.FetchIDs(src, typeKey)
	if guid == nil and cid == nil then
		return { title = title, message = "Detailed information is\nsecret while in combat" }
	end
	local data = D.Source(view, guid, cid)
	if typeKey == "EnemyDamageTaken" then
		local rows = attackerRows(data, view, profile, maxRows)
		return { title = { "%s's Damage Taken Breakdown", name }, rows = rows, message = not rows and "No data" or nil }
	end

	local r, g, b = D.ClassColor(src.classFilename)
	local rows = spellRows(data, maxRows, r and { r, g, b } or { D.AccentRGB() })
	local result = { title = title, rows = rows, message = not rows and "No data" or nil }
	if typeKey == "DamageDone" and rows then
		local targets = playerTargets(view, src.name)
		if targets then
			result.targets = {}
			for _, t in ipairs(targets) do
				table.insert(result.targets, {
					label = t.name,
					amount = L.FormatValue(profile.numberFormat, t.total, t.perSec, D.Abbrev),
					value = t.total,
					max = targets[1].total,
					color = ENEMY_COLOR,
				})
			end
		end
	end
	return result
end

local function setOrFormat(fs, text, fmt, args)
	if args then
		fs:SetFormattedText(fmt, unpack(args, 1, #args))
	else
		fs:SetText(text or "")
	end
end

-- Paints one breakdown row ({ row, fill, icon, label, amount }) from a
-- D.Breakdown row; returns nothing. Colors fall back to the given override.
function D.PaintRow(bar, data, size, profile, colorOverride)
	local offset = 0
	if data.icon then
		bar.icon:SetTexture(data.icon)
		local zoom = (profile.iconZoom or 6) / 100
		bar.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
		bar.icon:SetSize(size, size)
		bar.icon:Show()
		offset = size
	elseif data.class then
		offset = D.ApplyIcon(bar.icon, data.class, data.specIcon, size, profile)
	else
		bar.icon:Hide()
	end
	bar.fill:ClearAllPoints()
	bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", offset, 0)
	bar.fill:SetPoint("BOTTOMRIGHT", bar.row, "BOTTOMRIGHT", 0, 0)
	bar.fill:SetMinMaxValues(0, data.max or 1)
	bar.fill:SetValue(data.value or 0)
	local c = colorOverride or data.color or { D.AccentRGB() }
	bar.fill:SetStatusBarColor(c[1], c[2], c[3])
	setOrFormat(bar.label, data.label, data.labelFormat, data.labelArgs)
	setOrFormat(bar.amount, data.amount, data.amountFormat, data.amountArgs)
	bar.spellID = data.spellID
end

function D.ShowSpellTooltip(owner, spellID, profile)
	if not profile.showSpellTooltips or type(spellID) ~= "number" then
		return
	end
	local name = D.SpellName(spellID)
	if name == nil or isSecret(name) then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -6, 0)
	GameTooltip:SetSpellByID(spellID)
	GameTooltip:Show()
end

ns.Debug:RegisterChecks("DamageMeter", function()
	return {
		{
			name = "breakdown apis",
			run = function()
				local missing = {}
				local cdm = type(C_DamageMeter) == "table" and C_DamageMeter or {}
				local recap = type(C_DeathRecap) == "table" and C_DeathRecap or {}
				for name, fn in pairs({
					GetCombatSessionSourceFromType = cdm.GetCombatSessionSourceFromType,
					GetCombatSessionSourceFromID = cdm.GetCombatSessionSourceFromID,
					GetSessionDurationSeconds = cdm.GetSessionDurationSeconds,
					GetRecapEvents = recap.GetRecapEvents,
					GetRecapMaxHealth = recap.GetRecapMaxHealth,
					GetSpellTexture = C_Spell.GetSpellTexture,
					GetSpellName = C_Spell.GetSpellName,
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
			name = "group resolve",
			run = function()
				return "INFO", allyZone(), D.SnapshotSize()
			end,
		},
		{
			name = "targets cache",
			run = function()
				local n = 0
				for _ in pairs(targetsCache.map or {}) do
					n = n + 1
				end
				return "INFO", targetsCache.key or "none", n
			end,
		},
	}
end)
