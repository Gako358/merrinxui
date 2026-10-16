local addonName, ns = ...

local CooldownVoiceLogic = {}
ns.CooldownVoiceLogic = CooldownVoiceLogic

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
