local addonName, ns = ...

local LootRollLogic = {}
ns.LootRollLogic = LootRollLogic

local L = LootRollLogic

L.STATE = { NEED_MAIN = 0, NEED_OFF = 1, TRANSMOG = 2, GREED = 3, NO_ROLL = 4, PASS = 5 }
L.RANK = { [0] = 1, [1] = 2, [2] = 3, [3] = 4, [5] = 5, [4] = 6 }
L.MAX_PREVIEW = 40
L.API = { "GetAllEncounterInfos", "GetSortedDropsForEncounter", "GetSortedInfoForDrop", "GetLootHistoryTime" }

local LABELS = {
	[0] = { "Need", "MS" },
	[1] = { "Need", "OS" },
	[2] = { "Transmog", nil },
	[3] = { "Greed", nil },
	[4] = { "Choosing", nil },
	[5] = { "Pass", nil },
}

local function isSecretValue(isSecret, v)
	return isSecret ~= nil and isSecret(v)
end

local function secretString(isSecret, v)
	if isSecretValue(isSecret, v) or type(v) ~= "string" then
		return nil
	end
	return v
end

local function secretNumber(isSecret, v)
	if isSecretValue(isSecret, v) or type(v) ~= "number" then
		return nil
	end
	return v
end

local function secretBoolean(isSecret, v)
	if isSecretValue(isSecret, v) then
		return false
	end
	return v == true
end

function L.HasApi(api)
	local missing = {}
	for _, name in ipairs(L.API) do
		if not (api and type(api[name]) == "function") then
			missing[#missing + 1] = name
		end
	end
	return #missing == 0, missing
end

function L.EnumMatches(enum)
	if type(enum) ~= "table" then
		return false
	end
	return enum.NeedMainSpec == L.STATE.NEED_MAIN
		and enum.NeedOffSpec == L.STATE.NEED_OFF
		and enum.Transmog == L.STATE.TRANSMOG
		and enum.Greed == L.STATE.GREED
		and enum.NoRoll == L.STATE.NO_ROLL
		and enum.Pass == L.STATE.PASS
end

function L.Label(state)
	local entry = LABELS[state]
	if not entry then
		return "Choosing", nil
	end
	return entry[1], entry[2]
end

function L.ReadRoll(info, isSecret)
	if type(info) ~= "table" then
		return nil
	end

	local state = info.state
	if isSecretValue(isSecret, state) or type(state) ~= "number" then
		state = L.STATE.NO_ROLL
	end

	return {
		name = secretString(isSecret, info.playerName),
		guid = secretString(isSecret, info.playerGUID),
		class = secretString(isSecret, info.playerClass),
		state = state,
		roll = secretNumber(isSecret, info.roll),
		isWinner = secretBoolean(isSecret, info.isWinner),
		isSelf = secretBoolean(isSecret, info.isSelf),
	}
end

function L.SortRolls(rolls)
	table.sort(rolls, function(a, b)
		local ra = L.RANK[a.state] or L.RANK[L.STATE.NO_ROLL]
		local rb = L.RANK[b.state] or L.RANK[L.STATE.NO_ROLL]
		if ra ~= rb then
			return ra < rb
		end
		if a.roll ~= b.roll then
			if a.roll == nil then
				return false
			end
			if b.roll == nil then
				return true
			end
			return a.roll > b.roll
		end
		if a.name ~= b.name then
			if a.name == nil then
				return false
			end
			if b.name == nil then
				return true
			end
			return a.name < b.name
		end
		return false
	end)
	return rolls
end

function L.ReadDrop(encounterID, info, isSecret)
	if type(info) ~= "table" then
		return nil
	end
	if isSecretValue(isSecret, encounterID) or type(encounterID) ~= "number" then
		return nil
	end
	local lootListID = info.lootListID
	if isSecretValue(isSecret, lootListID) or type(lootListID) ~= "number" then
		return nil
	end

	local rolls = {}
	if type(info.rollInfos) == "table" then
		for _, rollInfo in ipairs(info.rollInfos) do
			local roll = L.ReadRoll(rollInfo, isSecret)
			if roll then
				rolls[#rolls + 1] = roll
			end
		end
	end

	local winner = L.ReadRoll(info.winner, isSecret)
	if not winner then
		for _, roll in ipairs(rolls) do
			if roll.isWinner then
				winner = roll
				break
			end
		end
	end

	L.SortRolls(rolls)

	local chosen = 0
	for _, roll in ipairs(rolls) do
		if roll.state ~= L.STATE.NO_ROLL then
			chosen = chosen + 1
		end
	end

	return {
		key = encounterID .. ":" .. lootListID,
		encounterID = encounterID,
		lootListID = lootListID,
		link = secretString(isSecret, info.itemHyperlink),
		startTime = secretNumber(isSecret, info.startTime),
		duration = secretNumber(isSecret, info.duration),
		allPassed = secretBoolean(isSecret, info.allPassed),
		winner = winner,
		rolls = rolls,
		chosen = chosen,
		total = #rolls,
	}
end

function L.IsResolved(drop)
	return drop.winner ~= nil or drop.allPassed == true
end

function L.IsActive(drop, now)
	if L.IsResolved(drop) then
		return false
	end
	if now == nil or drop.startTime == nil or drop.duration == nil then
		return true
	end
	return now < drop.startTime + drop.duration
end

function L.PlayerKey(roll)
	if not roll then
		return nil
	end
	if roll.guid then
		return roll.guid
	end
	if roll.name then
		return "name:" .. roll.name
	end
	return nil
end

function L.Build(raw, excluded, now, isSecret)
	excluded = excluded or {}
	local drops = {}
	if type(raw) == "table" then
		for _, entry in ipairs(raw) do
			if type(entry) == "table" and type(entry.drops) == "table" then
				for _, info in ipairs(entry.drops) do
					local drop = L.ReadDrop(entry.encounterID, info, isSecret)
					if drop and not excluded[drop.key] then
						drops[#drops + 1] = drop
					end
				end
			end
		end
	end

	table.sort(drops, function(a, b)
		if a.startTime ~= b.startTime then
			if a.startTime == nil then
				return false
			end
			if b.startTime == nil then
				return true
			end
			return a.startTime > b.startTime
		end
		if a.encounterID ~= b.encounterID then
			return a.encounterID > b.encounterID
		end
		return a.lootListID > b.lootListID
	end)

	local active = {}
	for _, drop in ipairs(drops) do
		if L.IsActive(drop, now) then
			active[#active + 1] = drop
		end
	end

	local wins = {}
	for _, drop in ipairs(drops) do
		if drop.winner then
			local key = L.PlayerKey(drop.winner)
			if key then
				wins[key] = (wins[key] or 0) + 1
			end
		end
	end

	return { drops = drops, active = active, wins = wins, total = #drops }
end

function L.Snapshot(raw, isSecret)
	local keys = {}
	if type(raw) == "table" then
		for _, entry in ipairs(raw) do
			if type(entry) == "table" and type(entry.drops) == "table" then
				for _, info in ipairs(entry.drops) do
					local drop = L.ReadDrop(entry.encounterID, info, isSecret)
					if drop and L.IsResolved(drop) then
						keys[drop.key] = true
					end
				end
			end
		end
	end
	return keys
end

function L.WinCount(state, drop, roll)
	local key = L.PlayerKey(roll)
	if not key then
		return 0
	end
	local n = (state and state.wins and state.wins[key]) or 0
	if drop and drop.winner and L.PlayerKey(drop.winner) == key then
		n = n - 1
	end
	return n
end

function L.CountText(n)
	if n == nil or n <= 0 then
		return ""
	end
	return "(*" .. n .. ")"
end

function L.Status(drop)
	if drop.winner then
		return "Won by " .. (drop.winner.name or "?") .. " " .. (drop.winner.roll and tostring(drop.winner.roll) or "-")
	end
	if drop.allPassed then
		return "All passed"
	end
	return "Rolling " .. drop.chosen .. "/" .. drop.total
end

function L.ShouldReset(prevID, instanceID, instanceType)
	if instanceType ~= "party" and instanceType ~= "raid" then
		return false
	end
	if type(instanceID) ~= "number" then
		return false
	end
	return instanceID ~= prevID
end

function L.Visible(s)
	if s.preview or s.pinned then
		return true
	end
	return s.inGroup == true and not s.dismissed and ((s.active or 0) > 0 or s.lingering == true)
end

function L.ParseSlash(arg)
	arg = arg or ""
	if arg == "" then
		return "toggle"
	end
	if arg == "test" then
		return "test", L.MAX_PREVIEW
	end
	local n = arg:match("^test%s+(%d+)$")
	if n then
		n = tonumber(n)
		if n < 1 then
			n = 1
		elseif n > L.MAX_PREVIEW then
			n = L.MAX_PREVIEW
		end
		return "test", n
	end
	return "usage"
end

local PREVIEW_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local PREVIEW_STATES =
	{ L.STATE.NEED_MAIN, L.STATE.NEED_OFF, L.STATE.TRANSMOG, L.STATE.GREED, L.STATE.PASS, L.STATE.NO_ROLL }

local function previewResolvedDrop(key, lootListID, name, roll)
	local winner = {
		name = name,
		guid = nil,
		class = "WARRIOR",
		state = L.STATE.NEED_MAIN,
		roll = roll,
		isWinner = true,
		isSelf = false,
	}
	return {
		key = key,
		encounterID = "preview",
		lootListID = lootListID,
		link = nil,
		startTime = nil,
		duration = nil,
		allPassed = false,
		winner = winner,
		rolls = { winner },
		chosen = 1,
		total = 1,
	}
end

function L.Preview(n)
	n = n or 0
	if n < 0 then
		n = 0
	end

	local rolls = {}
	for i = 1, n do
		local state = PREVIEW_STATES[((i - 1) % 6) + 1]
		local roll = nil
		if state ~= L.STATE.NO_ROLL then
			roll = ((i * 13) % 100) + 1
		end
		rolls[#rolls + 1] = {
			name = "Player" .. i,
			guid = nil,
			class = PREVIEW_CLASSES[((i - 1) % 9) + 1],
			state = state,
			roll = roll,
			isWinner = false,
			isSelf = false,
		}
	end
	L.SortRolls(rolls)

	local chosen = 0
	for _, roll in ipairs(rolls) do
		if roll.state ~= L.STATE.NO_ROLL then
			chosen = chosen + 1
		end
	end

	local active = {
		key = "preview:0",
		encounterID = "preview",
		lootListID = 0,
		link = nil,
		startTime = nil,
		duration = nil,
		allPassed = false,
		winner = nil,
		rolls = rolls,
		chosen = chosen,
		total = n,
	}

	local drop2 = previewResolvedDrop("preview:1", 1, "Player2", 99)
	local drop3 = previewResolvedDrop("preview:2", 2, "Player3", 77)
	local drops = { active, drop2, drop3 }

	local wins = {}
	for _, drop in ipairs(drops) do
		if drop.winner then
			local key = L.PlayerKey(drop.winner)
			if key then
				wins[key] = (wins[key] or 0) + 1
			end
		end
	end

	return { drops = drops, active = { active }, wins = wins, total = #drops }
end
