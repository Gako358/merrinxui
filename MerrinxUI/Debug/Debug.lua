local addonName, ns = ...

local DebugLogic = ns.DebugLogic
local AceGUI = LibStub("AceGUI-3.0")

local TOC_INTERFACE = 16001

local registeredChecks = {}
local logFrame, logEdit

local Debug = ns.addon:NewModule("Debug")
ns.Debug = Debug

local function append(source, text)
	DebugLogic.Push(Debug.db.global.log, DebugLogic.FormatLine(date("%H:%M:%S"), source, text), DebugLogic.CAP)
end

local function buildCtx(base, enabled)
	local ctx = {}
	for k, v in pairs(base) do
		ctx[k] = v
	end
	ctx.enabled = enabled
	return ctx
end

local function environment()
	local version = (type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function")
			and C_AddOns.GetAddOnMetadata(addonName, "Version")
		or nil
	local gameVersion, build, buildDate, interface = GetBuildInfo()
	local _, classFile = UnitClass("player")
	return version, gameVersion, build, buildDate, interface, classFile, GetLocale()
end

function Debug:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Debug", { global = { enabled = false } })
	self.db.global.log = self.db.global.log or {}
end

function Debug:OnEnable()
	if self:IsActive() then
		self:Log("Debug", "session", environment())
	end
end

function Debug:IsActive()
	return self.db ~= nil and self.db.global.enabled == true
end

function Debug:SetActive(value)
	value = not not value

	if value then
		self.db.global.enabled = true
		self:Log("Debug", "debug on")
	else
		self:Log("Debug", "debug off")
		self.db.global.enabled = false
	end

	ns.addon:Print(value and "debug mode on" or "debug mode off")
	LibStub("AceConfigRegistry-3.0"):NotifyChange("MerrinxUI")
end

function Debug:Log(source, ...)
	if not self:IsActive() then
		return
	end
	append(source, DebugLogic.Join({ ... }, select("#", ...), issecretvalue))
end

function Debug:RegisterChecks(source, provider)
	registeredChecks[source] = registeredChecks[source] or {}
	table.insert(registeredChecks[source], provider)
end

function Debug:RunTests()
	if not self:IsActive() then
		ns.addon:Print("debug mode is off (/mui debug on)")
		return nil
	end

	local version, gameVersion, build, buildDate, interface, classFile, locale = environment()
	self:Log(
		"Debug",
		"test run",
		version,
		gameVersion,
		build,
		buildDate,
		interface,
		classFile,
		locale,
		"combat",
		InCombatLockdown()
	)

	local ctx = { inCombat = InCombatLockdown(), hasTarget = UnitExists("target") }

	local sources = {}
	local seen = {}
	for name in ns.addon:IterateModules() do
		if not seen[name] then
			seen[name] = true
			table.insert(sources, name)
		end
	end
	for source in pairs(registeredChecks) do
		if not seen[source] then
			seen[source] = true
			table.insert(sources, source)
		end
	end
	sources = DebugLogic.SortSources(sources)

	local results = {}

	for _, name in ipairs(sources) do
		local module = ns.addon:GetModule(name, true)

		if name ~= "Debug" and module and module.db and module.db.profile then
			local profile = module.db.profile
			table.insert(results, {
				source = name,
				name = "settings",
				status = "INFO",
				detail = DebugLogic.Flatten(profile, issecretvalue),
			})
			if profile.enabled ~= nil then
				table.insert(results, {
					source = name,
					name = "enabled state",
					status = (module:IsEnabled() == (profile.enabled == true)) and "PASS" or "FAIL",
					detail = DebugLogic.Join({ module:IsEnabled(), profile.enabled }, 2, issecretvalue),
				})
			end
		end

		if module and type(module.GetDebugChecks) == "function" then
			local moduleResults = DebugLogic.RunSource(name, function()
				return module:GetDebugChecks()
			end, buildCtx(ctx, module:IsEnabled()), issecretvalue)
			for _, r in ipairs(moduleResults) do
				table.insert(results, r)
			end
		end

		local providers = registeredChecks[name]
		if providers then
			local providerCtx = buildCtx(ctx, nil)
			for _, provider in ipairs(providers) do
				local providerResults = DebugLogic.RunSource(name, provider, providerCtx, issecretvalue)
				for _, r in ipairs(providerResults) do
					table.insert(results, r)
				end
			end
		end
	end

	for _, r in ipairs(results) do
		append("Debug", DebugLogic.FormatResult(r))
	end

	local summaryText = DebugLogic.Summary(results)
	append("Debug", summaryText)

	ns.addon:Print(summaryText)
	local failCount = 0
	for _, r in ipairs(results) do
		if r.status == "FAIL" and failCount < 10 then
			failCount = failCount + 1
			ns.addon:Print(DebugLogic.FormatResult(r))
		end
	end

	self:ShowLog()

	return results
end

function Debug:ShowLog()
	if not logFrame then
		logFrame = AceGUI:Create("Frame")
		logFrame:SetTitle("MerrinxUI log")
		logFrame:SetLayout("Fill")
		logFrame:SetCallback("OnClose", function(widget)
			AceGUI:Release(widget)
			logFrame = nil
			logEdit = nil
		end)

		logEdit = AceGUI:Create("MultiLineEditBox")
		logEdit:SetLabel("")
		logEdit:DisableButton(true)
		logFrame:AddChild(logEdit)
	end

	local log = self.db.global.log
	logFrame:SetStatusText(#log .. "/" .. DebugLogic.CAP .. " lines")
	logEdit:SetText(table.concat(log, "\n"))
	logEdit:SetFocus()
	logEdit:HighlightText()
	logFrame.frame:Raise()
end

function Debug:ClearLog()
	self.db.global.log = {}
end

function Debug:Slash(verb, arg)
	if verb == "debug" and arg == "" then
		self:SetActive(not self:IsActive())
	elseif verb == "debug" and arg == "on" then
		self:SetActive(true)
	elseif verb == "debug" and arg == "off" then
		self:SetActive(false)
	elseif verb == "test" then
		self:RunTests()
	elseif verb == "log" then
		self:ShowLog()
	else
		ns.addon:Print("usage: /mui debug, /mui debug on, /mui debug off, /mui test, /mui log")
	end
end

function Debug:GetDebugChecks()
	local checks = {
		{
			name = "version",
			run = function()
				if type(C_AddOns) ~= "table" or type(C_AddOns.GetAddOnMetadata) ~= "function" then
					return "FAIL", "C_AddOns missing"
				end
				return "INFO", C_AddOns.GetAddOnMetadata(addonName, "Version")
			end,
		},
		{
			name = "interface",
			run = function()
				local toc = select(4, GetBuildInfo())
				if issecretvalue(toc) then
					return "INFO", toc
				end
				if toc ~= TOC_INTERFACE then
					return "FAIL", toc, TOC_INTERFACE, "update ## Interface"
				end
				return "PASS", toc, TOC_INTERFACE
			end,
		},
		{
			name = "game version",
			run = function()
				return "INFO", GetBuildInfo()
			end,
		},
		{
			name = "secret api",
			run = function()
				return (type(issecretvalue) == "function") and "PASS" or "FAIL"
			end,
		},
		{
			name = "libraries",
			run = function()
				local names = {
					"CallbackHandler-1.0",
					"AceAddon-3.0",
					"AceEvent-3.0",
					"AceConsole-3.0",
					"AceDB-3.0",
					"AceDBOptions-3.0",
					"AceGUI-3.0",
					"AceConfig-3.0",
					"AceConfigRegistry-3.0",
					"AceConfigDialog-3.0",
					"AceConfigCmd-3.0",
					"LibRangeCheck-3.0",
					"LibSharedMedia-3.0",
				}
				local missing = {}
				local count = 0
				for _, libName in ipairs(names) do
					if LibStub(libName, true) then
						count = count + 1
					else
						table.insert(missing, libName)
					end
				end
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "INFO", count
			end,
		},
		{
			name = "slash",
			run = function()
				local mui = SlashCmdList.ACECONSOLE_MUI
				local merrinxui = SlashCmdList.ACECONSOLE_MERRINXUI
				return (type(mui) == "function" and type(merrinxui) == "function") and "PASS" or "FAIL"
			end,
		},
		{
			name = "options",
			run = function()
				local options = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("MerrinxUI", "dialog", "MerrinxUI-1.0")
				if type(options) ~= "table" or type(options.args) ~= "table" then
					return "FAIL", "no options table"
				end

				local args = options.args
				if not args.unlock or not args.profiles then
					return "FAIL", "missing unlock or profiles"
				end

				for moduleName, module in ns.addon:IterateModules() do
					if type(module.GetOptions) == "function" and not args[moduleName] then
						return "FAIL", "missing node for " .. moduleName
					end
				end

				return "PASS"
			end,
		},
		{
			name = "profile",
			run = function()
				local _, count = ns.addon.db:GetProfiles()
				local scope = (ns.addon.db:GetCurrentProfile() == "Default") and "shared" or "per-character"
				return "INFO", count, scope
			end,
		},
		{
			name = "log",
			run = function()
				return "INFO", #self.db.global.log, DebugLogic.CAP
			end,
		},
	}

	local moduleNames = {}
	for name in ns.addon:IterateModules() do
		table.insert(moduleNames, name)
	end
	table.sort(moduleNames)

	for _, name in ipairs(moduleNames) do
		table.insert(checks, {
			name = "coverage " .. name,
			run = function()
				local module = ns.addon:GetModule(name, true)
				return (module and type(module.GetDebugChecks) == "function") and "PASS" or "FAIL"
			end,
		})
	end

	return checks
end

function Debug:GetOptions()
	return {
		type = "group",
		name = "Debug",
		order = 1000,
		args = {
			active = {
				type = "toggle",
				name = "Debug mode",
				order = 1,
				get = function()
					return self:IsActive()
				end,
				set = function(_, value)
					self:SetActive(value)
				end,
			},
			run = {
				type = "execute",
				name = "Run tests",
				order = 2,
				disabled = function()
					return not self:IsActive()
				end,
				func = function()
					self:RunTests()
				end,
			},
			show = {
				type = "execute",
				name = "Show log",
				order = 3,
				func = function()
					self:ShowLog()
				end,
			},
			clear = {
				type = "execute",
				name = "Clear log",
				order = 4,
				confirm = true,
				func = function()
					self:ClearLog()
				end,
			},
			info = {
				type = "description",
				name = function()
					return "Log: " .. #self.db.global.log .. "/" .. DebugLogic.CAP .. " lines"
				end,
				order = 5,
			},
		},
	}
end
