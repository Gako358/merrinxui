local addonName, ns = ...

local L = ns.CooldownVoiceLogic

local CooldownVoice = ns.addon:NewModule("CooldownVoice", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = true,
		spells = "",
		voice = nil,
		rate = 0,
		volume = 100,
	},
}

local function ResolveToken(token)
	local info = C_Spell.GetSpellInfo(token)
	if type(info) ~= "table" then
		return nil
	end

	local id = info.spellID
	if issecretvalue(id) then
		return nil
	end

	local name = info.name
	if issecretvalue(name) then
		name = nil
	end

	return id, name
end

local function ObserveCooldown(info, fromEvent)
	if type(info) ~= "table" then
		return "unknown"
	end

	local isActive = info.isActive
	if not fromEvent then
		return isActive and "busy" or "ready"
	end

	if isActive and info.isOnGCD then
		return "gcd"
	elseif isActive then
		return "cooling"
	end
	return "ready"
end

function CooldownVoice:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("CooldownVoice", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	self.tracked = {}
	self.unknown = {}
	self.states = {}
	self.spoken = 0
end

function CooldownVoice:OnEnable()
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
	self:RegisterEvent("SPELLS_CHANGED", "Resolve")
	self:Resolve()
end

function CooldownVoice:OnDisable()
	self:StopTicker()
	for id in pairs(self.states) do
		self.states[id] = nil
	end
	C_VoiceChat.StopSpeakingText()
end

function CooldownVoice:Refresh()
	if self.db.profile.enabled then
		self:Enable()
		self:Resolve()
	else
		self:Disable()
	end
end

function CooldownVoice:Resolve()
	local tokens = L.ParseList(self.db.profile.spells, ns.RangeTextLogic.NormalizeSpell)
	local resolved = L.ResolveSpells(tokens, ResolveToken)
	self.tracked = resolved.tracked
	self.unknown = resolved.unknown

	local states = {}
	for _, spell in ipairs(self.tracked) do
		states[spell.id] = self.states[spell.id] or "ready"
	end
	self.states = states

	if not L.AnyCooling(self.states) then
		self:StopTicker()
	end

	ns.Debug:Log("CooldownVoice", "resolve", #self.tracked, #self.unknown)
end

function CooldownVoice:StartTicker()
	if self.ticker then
		return
	end
	self.ticker = C_Timer.NewTicker(0.2, function()
		self:Scan(false)
	end)
	ns.Debug:Log("CooldownVoice", "ticker", "on")
end

function CooldownVoice:StopTicker()
	if not self.ticker then
		return
	end
	self.ticker:Cancel()
	self.ticker = nil
	ns.Debug:Log("CooldownVoice", "ticker", "off")
end

function CooldownVoice:Scan(fromEvent)
	local names = {}

	for _, spell in ipairs(self.tracked) do
		local info = C_Spell.GetSpellCooldown(spell.id)
		local obs = ObserveCooldown(info, fromEvent)
		local prev = self.states[spell.id] or "ready"
		local state, announce = L.Step(prev, obs)
		self.states[spell.id] = state

		if announce then
			table.insert(names, spell.name)
			ns.Debug:Log("CooldownVoice", "ready", spell.id, spell.name)
		end
	end

	if #names > 0 then
		self:Speak(L.Message(names))
		self.spoken = self.spoken + #names
	end

	if L.AnyCooling(self.states) then
		self:StartTicker()
	else
		self:StopTicker()
	end
end

function CooldownVoice:OnSpellUpdateCooldown()
	self:Scan(true)
end

function CooldownVoice:Speak(text)
	local voice = L.ResolveVoice(self.db.profile.voice, C_VoiceChat.GetTtsVoices())
	if voice == nil then
		return
	end
	C_VoiceChat.SpeakText(voice, text, self.db.profile.rate, self.db.profile.volume, false)
end

function CooldownVoice:GetOptions()
	return {
		type = "group",
		name = "CooldownVoice",
		args = {
			enabled = {
				type = "toggle",
				name = "Enabled",
				order = 1,
				get = function()
					return self.db.profile.enabled
				end,
				set = function(_, value)
					self.db.profile.enabled = value
					self:Refresh()
				end,
			},
			spells = {
				type = "input",
				name = "Spells",
				order = 2,
				usage = "Comma-separated spell names or IDs",
				desc = function()
					local names = {}
					for _, spell in ipairs(self.tracked) do
						table.insert(names, spell.name)
					end
					local text = "Tracked: " .. ((#names > 0) and table.concat(names, ", ") or "none")
					if #self.unknown > 0 then
						text = text .. "; unresolved: " .. table.concat(self.unknown, ", ")
					end
					return text
				end,
				get = function()
					return self.db.profile.spells
				end,
				set = function(_, value)
					self.db.profile.spells = value
					self:Resolve()
					self:Refresh()
				end,
			},
			voice = {
				type = "select",
				name = "Voice",
				order = 3,
				values = function()
					local values = {}
					local voices = C_VoiceChat.GetTtsVoices()
					if type(voices) == "table" then
						for _, voiceInfo in ipairs(voices) do
							values[voiceInfo.voiceID] = voiceInfo.name
						end
					end
					return values
				end,
				get = function()
					return L.ResolveVoice(self.db.profile.voice, C_VoiceChat.GetTtsVoices())
				end,
				set = function(_, value)
					self.db.profile.voice = value
					self:Refresh()
				end,
			},
			rate = {
				type = "range",
				name = "Rate",
				order = 4,
				min = -10,
				max = 10,
				step = 1,
				get = function()
					return self.db.profile.rate
				end,
				set = function(_, value)
					self.db.profile.rate = value
					self:Refresh()
				end,
			},
			volume = {
				type = "range",
				name = "Volume",
				order = 5,
				min = 0,
				max = 100,
				step = 5,
				get = function()
					return self.db.profile.volume
				end,
				set = function(_, value)
					self.db.profile.volume = value
					self:Refresh()
				end,
			},
			test = {
				type = "execute",
				name = "Test voice",
				order = 6,
				func = function()
					self:Speak("MerrinxUI voice test")
				end,
			},
		},
	}
end

function CooldownVoice:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function check(path, value)
					if type(value) ~= "function" then
						table.insert(missing, path)
					end
				end
				check("C_Spell.GetSpellCooldown", type(C_Spell) == "table" and C_Spell.GetSpellCooldown)
				check("C_Spell.GetSpellInfo", type(C_Spell) == "table" and C_Spell.GetSpellInfo)
				check("C_VoiceChat.SpeakText", type(C_VoiceChat) == "table" and C_VoiceChat.SpeakText)
				check("C_VoiceChat.GetTtsVoices", type(C_VoiceChat) == "table" and C_VoiceChat.GetTtsVoices)
				check("C_VoiceChat.StopSpeakingText", type(C_VoiceChat) == "table" and C_VoiceChat.StopSpeakingText)
				check(
					"C_Secrets.ShouldCooldownsBeSecret",
					type(C_Secrets) == "table" and C_Secrets.ShouldCooldownsBeSecret
				)
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "voices",
			run = function()
				local voices = C_VoiceChat.GetTtsVoices()
				local count = (type(voices) == "table") and #voices or 0
				local resolvedVoice = L.ResolveVoice(self.db.profile.voice, voices or {})
				local storedPresent = false
				if type(voices) == "table" then
					for _, voiceInfo in ipairs(voices) do
						if voiceInfo.voiceID == self.db.profile.voice then
							storedPresent = true
							break
						end
					end
				end
				return (count > 0) and "PASS" or "FAIL", count, resolvedVoice, storedPresent
			end,
		},
		{
			name = "spells",
			run = function()
				if #self.tracked == 0 and #self.unknown == 0 then
					return "SKIP", "no spells"
				end
				if #self.unknown == 0 then
					return "PASS", #self.tracked
				end
				return "INFO", #self.tracked, unpack(self.unknown, 1, #self.unknown)
			end,
		},
		{
			name = "ticker",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local running = self.ticker ~= nil
				local cooling = L.AnyCooling(self.states)
				local coolingCount = 0
				for _, state in pairs(self.states) do
					if state == "cooling" then
						coolingCount = coolingCount + 1
					end
				end
				return (running == cooling) and "PASS" or "FAIL", running, coolingCount
			end,
		},
		{
			name = "cooldown info",
			run = function()
				if #self.tracked == 0 then
					return "SKIP", "no spells"
				end

				local info = C_Spell.GetSpellCooldown(self.tracked[1].id)
				local infoPresent = type(info) == "table"
				local isActive, isOnGCD, startTimeSecret
				if infoPresent then
					isActive = info.isActive
					isOnGCD = info.isOnGCD
					startTimeSecret = issecretvalue(info.startTime)
				end
				return "INFO",
					infoPresent,
					type(isActive),
					isOnGCD,
					startTimeSecret,
					C_Secrets.ShouldCooldownsBeSecret()
			end,
		},
		{
			name = "spoken",
			run = function()
				return "INFO", self.spoken
			end,
		},
	}
end
