local addonName, ns = ...

local DamageMeterLogic = {}
ns.DamageMeterLogic = DamageMeterLogic

local L = DamageMeterLogic

L.MAX_WINDOWS = 5
L.MAX_SEGMENTS = 20
L.HOME_DEFAULTS = { "DamageDone", "HealingDone", "Interrupts", "Deaths" }

local TYPE_LABELS = {
	DamageDone = "Damage Done",
	Dps = "DPS",
	HealingDone = "Healing Done",
	Hps = "HPS",
	Absorbs = "Absorbs",
	Interrupts = "Interrupts",
	Dispels = "Dispels",
	DamageTaken = "Damage Taken",
	AvoidableDamageTaken = "Avoidable Damage Taken",
	Deaths = "Deaths",
	EnemyDamageTaken = "Enemy Damage Taken",
}

local TYPE_ICONS = {
	DamageDone = "damage",
	Dps = "damage",
	HealingDone = "healing",
	Hps = "healing",
	Absorbs = "healing",
	Interrupts = "interrupt",
	Dispels = "dispel",
	DamageTaken = "taken",
	AvoidableDamageTaken = "avoidable",
	Deaths = "deaths",
	EnemyDamageTaken = "enemyTaken",
}

local RATE_TYPES = { Dps = true, Hps = true }
local COUNT_TYPES = { Interrupts = true, Dispels = true }

local MENU_GROUPS = {
	{ label = "Damage", keys = { "DamageDone", "Dps", "DamageTaken", "AvoidableDamageTaken", "EnemyDamageTaken" } },
	{ label = "Healing", keys = { "HealingDone", "Hps", "Absorbs" } },
	{ label = "Actions", keys = { "Interrupts", "Dispels", "Deaths" } },
}

L.NUMBER_FORMATS = { [0] = "DPS", [1] = "Damage", [2] = "Damage (DPS)", [3] = "Damage | DPS" }

local function isNumber(v, isSecret)
	return type(v) == "number" and not (isSecret and isSecret(v))
end

function L.EnumKey(tbl, key)
	if type(tbl) == "table" and type(key) == "string" then
		return tbl[key]
	end
	return nil
end

function L.IconCoords(coords, zoom)
	if coords == nil then
		return nil
	end
	local l, r, t, b = coords[1], coords[2], coords[3], coords[4]
	return l + (r - l) * zoom, r - (r - l) * zoom, t + (b - t) * zoom, b - (b - t) * zoom
end

function L.ShortName(name)
	if type(name) ~= "string" then
		return nil
	end
	return name:match("^[^-]+")
end

function L.TypeLabel(key)
	if key == nil then
		return "None"
	end
	local known = TYPE_LABELS[key]
	if known then
		return known
	end
	return (key:gsub("(%l)(%u)", "%1 %2"))
end

function L.TypeIcon(key)
	return TYPE_ICONS[key] or "damage"
end

function L.Title(typeKey, isOverall)
	local label = L.TypeLabel(typeKey)
	if isOverall then
		return "Overall " .. label
	end
	return label
end

function L.TypeList(enum)
	if type(enum) ~= "table" then
		return {}
	end

	local keys = {}
	for k, v in pairs(enum) do
		if type(k) == "string" and type(v) == "number" then
			table.insert(keys, k)
		end
	end
	table.sort(keys, function(a, b)
		return enum[a] < enum[b]
	end)
	return keys
end

function L.TypeKind(key)
	if RATE_TYPES[key] then
		return "rate"
	end
	if COUNT_TYPES[key] then
		return "count"
	end
	if key == "Deaths" then
		return "deaths"
	end
	return "amount"
end

function L.BarField(kind)
	if kind == "rate" then
		return "amountPerSecond"
	end
	return "totalAmount"
end

function L.MenuGroups(list)
	list = list or {}

	local present = {}
	for _, key in ipairs(list) do
		present[key] = true
	end

	local groups = {}
	local grouped = {}
	for _, group in ipairs(MENU_GROUPS) do
		local keys = {}
		for _, key in ipairs(group.keys) do
			if present[key] then
				table.insert(keys, key)
				grouped[key] = true
			end
		end
		if #keys > 0 then
			table.insert(groups, { label = group.label, keys = keys })
		end
	end

	local other = {}
	for _, key in ipairs(list) do
		if not grouped[key] then
			table.insert(other, key)
		end
	end
	if #other > 0 then
		table.insert(groups, { label = "Other", keys = other })
	end

	return groups
end

-- A group with one type is a plain entry, as the Healing entry is when the
-- client offers only HealingDone.
function L.TypeMenu(list, current)
	local items = {}
	for _, group in ipairs(L.MenuGroups(list)) do
		if #group.keys == 1 then
			local key = group.keys[1]
			table.insert(items, { key = key, text = L.TypeLabel(key), isActive = key == current })
		else
			local children, active = {}, false
			for _, key in ipairs(group.keys) do
				table.insert(children, { key = key, text = L.TypeLabel(key), isActive = key == current })
				active = active or key == current
			end
			table.insert(items, { text = group.label, isActive = active, children = children })
		end
	end
	return items
end

function L.ResolveType(list, key, fallback)
	list = list or {}

	local present = {}
	for _, k in ipairs(list) do
		present[k] = true
	end

	if present[key] then
		return key
	end
	if present[fallback] then
		return fallback
	end
	return list[1]
end

function L.FormatTimer(seconds, isSecret)
	if not isNumber(seconds, isSecret) or seconds < 0 then
		return "0:00"
	end
	return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

function L.FormatTimerDecimal(seconds, isSecret)
	if not isNumber(seconds, isSecret) or seconds < 0 then
		return "0:00.0"
	end
	return string.format(
		"%d:%02d.%d",
		math.floor(seconds / 60),
		math.floor(seconds % 60),
		math.floor((seconds * 10) % 10)
	)
end

-- Secret values pass to fmt untouched; only a readable per-second value is
-- clamped, since long Overall sessions can drop it below 1.
function L.FormatValue(numFmt, total, perSec, fmt, isSecret)
	if isNumber(perSec, isSecret) and perSec < 1 then
		perSec = 1
	end
	if numFmt == 0 then
		return fmt(perSec)
	end
	if numFmt == 2 and perSec ~= nil then
		return string.format("%s (%s)", fmt(total), fmt(perSec))
	end
	if numFmt == 3 and perSec ~= nil then
		return string.format("%s | %s", fmt(total), fmt(perSec))
	end
	return fmt(total)
end

function L.ValueText(kind, numFmt, total, perSec, fmt, isSecret)
	if kind == "rate" then
		return fmt(perSec)
	end
	if kind == "count" then
		return fmt(total)
	end
	if kind == "deaths" then
		return ""
	end
	return L.FormatValue(numFmt, total, perSec, fmt, isSecret)
end

-- Oldest first, newest last: the menu opens upward, so the newest segment
-- sits next to Current and Overall at the bottom.
function L.Segments(list, max)
	list = list or {}

	local filtered = {}
	for _, entry in ipairs(list) do
		if type(entry) == "table" and type(entry.sessionID) == "number" then
			table.insert(filtered, entry)
		end
	end
	table.sort(filtered, function(a, b)
		return a.sessionID < b.sessionID
	end)

	local result = {}
	for i = math.max(1, #filtered - max + 1), #filtered do
		local entry = filtered[i]
		local name = (type(entry.name) == "string" and entry.name ~= "") and entry.name or "Combat"
		table.insert(result, {
			sessionID = entry.sessionID,
			label = name,
			duration = L.FormatTimer(entry.durationSeconds),
		})
	end
	return result
end

function L.HomeTypes(bookmarks, offered)
	local out = {}
	for i, key in ipairs(bookmarks or {}) do
		if offered[key] then
			table.insert(out, { index = i, key = key })
		end
	end
	return out
end

function L.AddableTypes(bookmarks, list)
	local pinned = {}
	for _, key in ipairs(bookmarks or {}) do
		pinned[key] = true
	end
	local out = {}
	for _, key in ipairs(list or {}) do
		if not pinned[key] then
			table.insert(out, key)
		end
	end
	table.sort(out, function(a, b)
		return L.TypeLabel(a) < L.TypeLabel(b)
	end)
	return out
end

-- Returns nil when any amount is secret: a percentage needs Lua arithmetic.
function L.Total(amounts, isSecret)
	local total = 0
	for _, v in ipairs(amounts) do
		if not isNumber(v, isSecret) then
			return nil
		end
		total = total + v
	end
	return total
end

function L.PercentText(amount, total)
	if type(total) ~= "number" or total <= 0 then
		return nil
	end
	return string.format("%.1f%%", amount / total * 100)
end

-- entries: { name, class, specIcon, amount, perSec, isPet, isMob }. A secret
-- name or amount anywhere means the engine order is kept and nothing merges.
function L.AggregateAttackers(entries, duration, isSecret)
	local secret = false
	for _, e in ipairs(entries) do
		if e.name ~= nil and isSecret and (isSecret(e.name) or isSecret(e.amount)) then
			secret = true
		end
	end

	local out = {}
	if secret then
		for _, e in ipairs(entries) do
			if e.name ~= nil then
				table.insert(out, {
					name = e.name,
					class = e.class,
					specIcon = e.specIcon,
					total = e.amount,
					perSec = e.perSec,
					isPet = e.isPet,
					isMob = e.isMob,
				})
			end
		end
		return out, true
	end

	local byName = {}
	for _, e in ipairs(entries) do
		if e.name ~= nil then
			local p = byName[e.name]
			if p then
				p.total = p.total + (e.amount or 0)
			else
				p = {
					name = e.name,
					class = e.class,
					specIcon = e.specIcon,
					total = e.amount or 0,
					isPet = e.isPet,
					isMob = e.isMob,
				}
				byName[e.name] = p
				table.insert(out, p)
			end
		end
	end
	for _, p in ipairs(out) do
		if type(duration) == "number" and duration > 0 then
			p.perSec = p.total / duration
		end
	end
	table.sort(out, function(a, b)
		return a.total > b.total
	end)
	return out, false
end

-- enemies: { { key, name, attackers = { { name, amount } } } } with readable
-- values only. Returns playerName -> targets sorted by damage.
function L.TargetsByPlayer(enemies, duration)
	local byPlayer, names = {}, {}
	for _, enemy in ipairs(enemies) do
		names[enemy.key] = enemy.name
		for _, a in ipairs(enemy.attackers or {}) do
			if a.amount and a.amount > 0 then
				local t = byPlayer[a.name]
				if not t then
					t = {}
					byPlayer[a.name] = t
				end
				t[enemy.key] = (t[enemy.key] or 0) + a.amount
			end
		end
	end

	local map = {}
	for player, targets in pairs(byPlayer) do
		local list = {}
		for key, total in pairs(targets) do
			local perSec
			if type(duration) == "number" and duration > 0 then
				perSec = total / duration
			end
			table.insert(list, { key = key, name = names[key], total = total, perSec = perSec })
		end
		table.sort(list, function(a, b)
			if a.total ~= b.total then
				return a.total > b.total
			end
			return tostring(a.key) < tostring(b.key)
		end)
		map[player] = list
	end
	return map
end

function L.Top(list, n)
	local out = {}
	for i = 1, math.min(n, #(list or {})) do
		out[i] = list[i]
	end
	return out
end

local HEAL_EVENTS = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }

-- events arrive newest first; rows come back oldest first with the readable
-- facts worked out. Secret fields stay on the row for the engine sinks.
function L.RecapRows(events, maxHP, isSecret, maxRows)
	local rows = {}
	local n = #events
	local count = math.min(n, maxRows or n)
	local deathTime = events[1] and events[1].timestamp
	if not isNumber(deathTime, isSecret) then
		deathTime = nil
	end
	for i = count, 1, -1 do
		local ev = events[i]
		local evType = ev.event
		if not (type(evType) == "string" and not (isSecret and isSecret(evType))) then
			evType = ""
		end
		local isHeal = HEAL_EVENTS[evType] == true
		local row = {
			spellID = ev.spellId,
			spellName = ev.spellName,
			amount = ev.amount,
			overkill = ev.overkill,
			currentHP = ev.currentHP,
			isHeal = isHeal,
			isFatal = i == 1 and not isHeal,
		}
		local nameSecret = isSecret and isSecret(ev.spellName)
		if not nameSecret and (type(ev.spellName) ~= "string" or ev.spellName == "") then
			if isHeal then
				row.spellName = "Heal"
			elseif evType == "SWING_DAMAGE" then
				row.spellName = "Melee"
			else
				row.spellName = "Unknown"
			end
		end
		if deathTime and isNumber(ev.timestamp, isSecret) then
			row.before = deathTime - ev.timestamp
		end
		if isNumber(ev.currentHP, isSecret) and isNumber(maxHP, isSecret) and maxHP > 0 then
			row.hpPct = math.max(0, math.min(1, ev.currentHP / maxHP))
		end
		table.insert(rows, row)
	end
	return rows
end

function L.InstanceHidden(rules, instType, inDelve)
	if rules.hideInDungeon and instType == "party" then
		return true
	end
	if rules.hideInRaid and instType == "raid" then
		return true
	end
	if rules.hideInDelve and inDelve then
		return true
	end
	if rules.hideInPvP and (instType == "pvp" or instType == "arena") then
		return true
	end
	if rules.hideOutOfInstance and (instType == "none" or instType == nil) then
		return true
	end
	return false
end

-- rect: { left, right, top, bottom } in UIParent coordinates (y up).
function L.RectGap(a, b)
	local gx, gy = 0, 0
	if a.right < b.left then
		gx = b.left - a.right
	elseif a.left > b.right then
		gx = a.left - b.right
	end
	if a.bottom > b.top then
		gy = a.bottom - b.top
	elseif a.top < b.bottom then
		gy = b.bottom - a.top
	end
	return math.sqrt(gx * gx + gy * gy)
end

function L.Closest(rect, others)
	local best, bestDist
	for i, o in ipairs(others) do
		local d = L.RectGap(rect, o)
		if not bestDist or d < bestDist then
			best, bestDist = i, d
		end
	end
	return best
end

local function snapAxis(pos, size, lo, hi, thresh)
	local best, bestDist = pos, thresh + 1
	for _, candidate in ipairs({ lo, hi - size, hi, lo - size }) do
		local d = math.abs(pos - candidate)
		if d < bestDist then
			best, bestDist = candidate, d
		end
	end
	if bestDist <= thresh then
		return best
	end
	return pos
end

-- Left/top of a window being dragged, snapped to the edges of another window.
function L.SnapPosition(left, top, w, h, other, thresh)
	local snappedLeft = snapAxis(left, w, other.left, other.right, thresh)
	local bottom = snapAxis(top - h, h, other.bottom, other.top, thresh)
	return snappedLeft, bottom + h
end

function L.SnapSize(value, otherValue, thresh)
	if otherValue and math.abs(value - otherValue) <= thresh then
		return otherValue
	end
	return value
end

local DOCK_SIDES = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true }

-- The side of other that rect sits flush against, sharing some of that edge.
-- offset is rect's left (TOP/BOTTOM) or top (LEFT/RIGHT) relative to other's.
function L.DockSide(rect, other, tol)
	local alongX = rect.left < other.right and rect.right > other.left
	local alongY = rect.bottom < other.top and rect.top > other.bottom
	if alongX and math.abs(rect.top - other.bottom) <= tol then
		return "BOTTOM", rect.left - other.left
	end
	if alongX and math.abs(rect.bottom - other.top) <= tol then
		return "TOP", rect.left - other.left
	end
	if alongY and math.abs(rect.left - other.right) <= tol then
		return "RIGHT", rect.top - other.top
	end
	if alongY and math.abs(rect.right - other.left) <= tol then
		return "LEFT", rect.top - other.top
	end
	return nil
end

-- A window dropped onto another docks to the side it needs to move least to
-- clear; nil when the two don't overlap.
function L.DropDock(rect, other)
	if rect.left >= other.right or rect.right <= other.left or rect.bottom >= other.top or rect.top <= other.bottom then
		return nil
	end
	local best, bestMove
	for _, c in ipairs({
		{ "BOTTOM", rect.top - other.bottom },
		{ "TOP", other.top - rect.bottom },
		{ "RIGHT", other.right - rect.left },
		{ "LEFT", rect.right - other.left },
	}) do
		if not bestMove or c[2] < bestMove then
			best, bestMove = c[1], c[2]
		end
	end
	if best == "BOTTOM" or best == "TOP" then
		return best, rect.left - other.left
	end
	return best, rect.top - other.top
end

function L.DockedTopLeft(parent, w, h, side, offset)
	if side == "BOTTOM" then
		return parent.left + offset, parent.bottom
	elseif side == "TOP" then
		return parent.left + offset, parent.top + h
	elseif side == "RIGHT" then
		return parent.right, parent.top + offset
	end
	return parent.left - w, parent.top + offset
end

function L.ValidDock(dock, idx, count)
	return type(dock) == "table"
		and type(dock.to) == "number"
		and dock.to ~= idx
		and dock.to >= 1
		and dock.to <= count
		and DOCK_SIDES[dock.side] == true
		and type(dock.offset) == "number"
end

-- docks: idx -> parent idx. The set of windows docked to idx, directly or
-- through another; a saved cycle can't loop.
function L.Descendants(docks, idx)
	local out, queue = {}, { idx }
	while #queue > 0 do
		local cur = table.remove(queue, 1)
		for child, parent in pairs(docks) do
			if parent == cur and child ~= idx and not out[child] then
				out[child] = true
				table.insert(queue, child)
			end
		end
	end
	return out
end

-- After window removed closes, windows docked to it come loose and higher
-- indices shift down by one.
function L.RemapDock(dock, removed)
	if type(dock) ~= "table" or dock.to == removed then
		return nil
	end
	if type(dock.to) == "number" and dock.to > removed then
		return { to = dock.to - 1, side = dock.side, offset = dock.offset }
	end
	return dock
end

-- Above every window when it fits on screen, else below the lowest one.
function L.NewWindowTop(highestTop, lowestBottom, h, gap, screenTop)
	local top = highestTop + h + gap
	if top > screenTop then
		return lowestBottom - gap
	end
	return top
end

function L.ClampScroll(value, totalH, viewH)
	local max = math.max(0, totalH - viewH)
	return math.max(0, math.min(max, value)), max
end

-- Two rows per wheel notch, landing back on the row grid.
function L.WheelScroll(cur, delta, stride, max)
	local target = (math.floor(cur / stride + 0.5) - delta * 2) * stride
	return math.max(0, math.min(max, target))
end

-- nil when the player's row is fully in view, else the edge it pins to.
function L.StickyPin(playerIdx, stride, barH, scroll, viewH)
	local top = (playerIdx - 1) * stride
	local bottom = top + barH
	if top >= scroll - 1 and bottom <= scroll + viewH + 1 then
		return nil
	end
	if top < scroll then
		return "top"
	end
	return "bottom"
end

function L.ValueGradient(rank, count)
	local t = 0
	if count > 1 then
		t = (rank - 1) / (count - 1)
	end
	if t < 0.5 then
		return t * 2, 1, 0
	end
	return 1, (1 - t) * 2, 0
end

function L.ParseHex(text)
	if type(text) ~= "string" then
		return nil
	end
	local hex = text:match("^%s*#?(%x%x%x%x%x%x)%s*$")
	if not hex then
		return nil
	end
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function L.ToHex(r, g, b)
	local function byte(v)
		return math.max(0, math.min(255, math.floor((v or 0) * 255 + 0.5)))
	end
	return string.format("%02X%02X%02X", byte(r), byte(g), byte(b))
end

-- Drops whole UTF-8 characters until measure(text .. "...") fits.
function L.FitText(full, avail, measure)
	if measure(full) <= avail then
		return full
	end
	local s = full
	while #s > 1 do
		local i = #s
		while i > 1 do
			local b = s:byte(i)
			if b < 0x80 or b >= 0xC0 then
				break
			end
			i = i - 1
		end
		s = s:sub(1, i - 1)
		if measure(s .. "...") <= avail then
			break
		end
	end
	return s .. "..."
end

local TIMER_ANCHORS = {
	topleft = { "BOTTOMLEFT", "TOPLEFT" },
	topright = { "BOTTOMRIGHT", "TOPRIGHT" },
	bottomleft = { "TOPLEFT", "BOTTOMLEFT" },
	bottomright = { "TOPRIGHT", "BOTTOMRIGHT" },
}

function L.TimerAnchor(anchor)
	local pair = TIMER_ANCHORS[anchor]
	if pair then
		return pair[1], pair[2]
	end
	return nil
end
