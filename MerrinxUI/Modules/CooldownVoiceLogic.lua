local addonName, ns = ...

local CooldownVoiceLogic = {}
ns.CooldownVoiceLogic = CooldownVoiceLogic

-- First-rank spell IDs of each class's spells with a cooldown worth announcing; ranks share it.
CooldownVoiceLogic.CLASS_SPELLS = {
	DRUID = {
		22812,
		5211,
		1850,
		5229,
		22842,
		6795,
		16914,
		29166,
		16689,
		17116,
		20484,
		18562,
		740,
		5209,
		16979,
		5215,
		8998,
	},
	WARRIOR = {
		2687,
		18499,
		100,
		20252,
		12292,
		1719,
		20230,
		871,
		12975,
		1161,
		5246,
		6552,
		72,
		676,
		12294,
		23881,
		2565,
		12328,
		7384,
		6572,
		355,
		694,
		1680,
		12809,
	},
	MAGE = {
		1953,
		2139,
		122,
		120,
		2136,
		12051,
		11958,
		12472,
		11426,
		12043,
		12042,
		11129,
		11113,
		543,
		6143,
	},
	PRIEST = { 8122, 586, 13908, 14751, 10060, 15487, 6346, 8092 },
	ROGUE = {
		2983,
		5277,
		1856,
		1766,
		1776,
		408,
		2094,
		1784,
		13750,
		13877,
		14177,
		14185,
		14183,
		14278,
		14251,
		1725,
	},
	HUNTER = {
		3045,
		19434,
		2643,
		3044,
		5116,
		781,
		5384,
		1499,
		13809,
		13795,
		13813,
		19263,
		19577,
		19574,
		19503,
		19306,
		19386,
		1495,
		19801,
		1543,
	},
	WARLOCK = { 6789, 5484, 18288, 17877, 17962, 6353, 18708, 6229, 1122, 603 },
	PALADIN = {
		642,
		498,
		1022,
		1044,
		633,
		853,
		24275,
		20271,
		26573,
		879,
		20473,
		20216,
		2812,
		20066,
		2878,
	},
	SHAMAN = {
		8042,
		8056,
		8050,
		8177,
		2484,
		5730,
		1535,
		16190,
		16188,
		16166,
		17364,
		20608,
		556,
		421,
	},
}

function CooldownVoiceLogic.ClassSpells(class)
	return CooldownVoiceLogic.CLASS_SPELLS[class] or {}
end

-- Tokens for ResolveSpells: the names of the ticked class spells (in list order), then the extra tokens.
function CooldownVoiceLogic.Tokens(classSpells, selected, nameOf, extra)
	local tokens, seen = {}, {}
	local function add(token)
		if token ~= nil and not seen[token] then
			seen[token] = true
			table.insert(tokens, token)
		end
	end
	for _, id in ipairs(classSpells) do
		if selected[id] then
			add(nameOf(id))
		end
	end
	for _, token in ipairs(extra) do
		add(token)
	end
	return tokens
end

function CooldownVoiceLogic.ParseList(text, normalize)
	local tokens = {}
	if type(text) ~= "string" then
		return tokens
	end

	local seen = {}
	for part in (text .. ","):gmatch("([^,]*),") do
		local value = normalize(part)
		if value ~= nil and not seen[value] then
			seen[value] = true
			table.insert(tokens, value)
		end
	end
	return tokens
end

function CooldownVoiceLogic.ResolveSpells(tokens, getInfo)
	local tracked = {}
	local unknown = {}
	local seenIds = {}

	for _, token in ipairs(tokens) do
		local id, name = getInfo(token)
		if id == nil then
			table.insert(unknown, token)
		elseif not seenIds[id] then
			seenIds[id] = true
			table.insert(tracked, { id = id, name = name or tostring(id) })
		end
	end

	return { tracked = tracked, unknown = unknown }
end

function CooldownVoiceLogic.Step(prev, obs)
	if obs == "cooling" then
		return "cooling", false
	elseif obs == "ready" then
		return "ready", prev == "cooling"
	end
	return prev, false
end

function CooldownVoiceLogic.AnyCooling(states)
	for _, state in pairs(states) do
		if state == "cooling" then
			return true
		end
	end
	return false
end

function CooldownVoiceLogic.Message(names)
	if #names == 0 then
		return nil
	end
	return table.concat(names, ", ") .. " ready"
end

function CooldownVoiceLogic.ResolveVoice(stored, voices)
	if stored ~= nil then
		for _, voice in ipairs(voices) do
			if voice.voiceID == stored then
				return stored
			end
		end
	end
	if voices[1] then
		return voices[1].voiceID
	end
	return nil
end
