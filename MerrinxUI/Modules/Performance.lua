local addonName, ns = ...

local L = ns.PerformanceLogic
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local PAGE = "Performance"
local WINDOW = 5
local TICK = 1
local REFRESH = 1
local MEMORY_INTERVAL = 30
local TOP_ADDONS = 10
local VALUE = "|cffffffff"

local Performance = ns.addon:NewModule("Performance", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = false,
		rows = 10,
	},
}

local groups = {}
local wrapped = {}
local depth = 0
local clock = debugprofilestop

local function finish(stats, start, ...)
	L.Record(stats, clock() - start)
	depth = 0
	return ...
end

-- Only the outermost MerrinxUI call is timed, so work is charged once, to the module that started it.
local function wrap(stats, fn)
	return function(...)
		if depth > 0 then
			return fn(...)
		end
		depth = 1
		local start = clock()
		return finish(stats, start, fn(...))
	end
end

local mixinSources = { (LibStub("AceEvent-3.0")), (LibStub("AceConsole-3.0")) }

local function isMixin(key, value)
	if value == ns.addon[key] then
		return true
	end
	for _, lib in ipairs(mixinSources) do
		if value == lib[key] then
			return true
		end
	end
	return false
end

local function cover(label, tbl)
	if type(tbl) ~= "table" then
		return
	end
	local stats = groups[label] or L.NewStats()
	groups[label] = stats
	for key, value in pairs(tbl) do
		if type(value) == "function" and type(key) == "string" and key:sub(1, 2) ~= "__" then
			if not isMixin(key, value) then
				local wrapper = wrap(stats, value)
				tbl[key] = wrapper
				wrapped[#wrapped + 1] = { tbl = tbl, key = key, orig = value, wrapper = wrapper }
			end
		end
	end
end

local function plain(value)
	if type(value) ~= "number" or issecretvalue(value) then
		return nil
	end
	return value
end

local function profilerOn()
	return type(C_AddOnProfiler) == "table"
		and type(C_AddOnProfiler.IsEnabled) == "function"
		and type(C_AddOnProfiler.GetAddOnMetric) == "function"
		and type(Enum) == "table"
		and type(Enum.AddOnProfilerMetric) == "table"
		and C_AddOnProfiler.IsEnabled() == true
end

local function metric(name, key)
	return plain(C_AddOnProfiler.GetAddOnMetric(name, Enum.AddOnProfilerMetric[key]))
end

local function value(text)
	return VALUE .. text .. "|r"
end

function Performance:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Performance", defaults)
	for _, key in ipairs({ "moduleTiming", "interval", "font", "fontSize", "bgOpacity", "position" }) do
		self.db.profile[key] = nil
	end
	self:SetEnabledState(self.db.profile.enabled)
	self.memScans = 0
	self.addonCpu, self.addonMemory = {}, {}
end

function Performance:OnEnable()
	self:Instrument()
	self.lastRoll = GetTime()
	self.ticker = C_Timer.NewTicker(TICK, function()
		-- A timed call that raised never reached finish(); this bounds the untimed stretch to one tick.
		depth = 0
		self:Roll()
	end)
end

function Performance:OnDisable()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	self:Restore()
end

function Performance:Refresh()
	if self.db.profile.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function Performance:Instrument()
	if #wrapped > 0 or type(clock) ~= "function" then
		return
	end
	for name, module in ns.addon:IterateModules() do
		cover(name, module)
	end
	cover("Mover", ns.Mover)
	cover("Combat", ns.Combat)
	cover("Hider", ns.Hider)
	cover("Options", ns.OptionsWindow)
	for _, part in ipairs({ "Data", "Window", "Menu", "Tooltip", "Timer" }) do
		cover("DamageMeter", ns["DamageMeter" .. part])
	end
	for _, part in ipairs({ "Window", "Scanner" }) do
		cover("Auctioneer", ns["Auctioneer" .. part])
	end
	ns.Debug:Log("Performance", "instrumented", #wrapped)
end

function Performance:Restore()
	local kept = 0
	for i = #wrapped, 1, -1 do
		local w = wrapped[i]
		if w.tbl[w.key] == w.wrapper then
			w.tbl[w.key] = w.orig
		else
			kept = kept + 1
		end
		wrapped[i] = nil
	end
	depth = 0
	if kept > 0 then
		ns.Debug:Log("Performance", "restore kept", kept)
	end
end

function Performance:Roll()
	local now = GetTime()
	local dt = now - (self.lastRoll or now)
	self.lastRoll = now
	if dt > 0 then
		for _, stats in pairs(groups) do
			L.Roll(stats, dt, WINDOW)
		end
	end
end

function Performance:ResetStats()
	for _, stats in pairs(groups) do
		L.Reset(stats)
	end
end

function Performance:Sample()
	local now = GetTime()
	self.lastSample = now
	self.fps = plain(GetFramerate())
	local _, _, home, world = GetNetStats()
	self.home, self.world = plain(home), plain(world)
	self.lua = collectgarbage("count")

	self.profiler = profilerOn()
	local cpu = {}
	if self.profiler then
		self.cpu = metric(addonName, "RecentAverageTime")
		self.cpuPeak = metric(addonName, "PeakTime")
		self.overall = type(C_AddOnProfiler.GetOverallMetric) == "function"
				and plain(C_AddOnProfiler.GetOverallMetric(Enum.AddOnProfilerMetric.RecentAverageTime))
			or nil
	else
		self.cpu, self.cpuPeak, self.overall = nil, nil, nil
	end

	-- UpdateAddOnMemoryUsage walks every loaded addon, so it runs rarely and never in combat.
	local scanMemory = not InCombatLockdown() and (self.lastMemScan == nil or now - self.lastMemScan >= MEMORY_INTERVAL)
	if scanMemory then
		self.lastMemScan = now
		self.memScans = self.memScans + 1
		UpdateAddOnMemoryUsage()
		self.memory = plain(GetAddOnMemoryUsage(addonName))
	end

	local memory = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		if C_AddOns.IsAddOnLoaded(i) then
			local name = C_AddOns.GetAddOnInfo(i)
			if self.profiler then
				cpu[#cpu + 1] = { name = name, value = metric(name, "RecentAverageTime") }
			end
			if scanMemory then
				memory[#memory + 1] = { name = name, value = plain(GetAddOnMemoryUsage(i)) }
			end
		end
	end
	self.addonCpu = L.SortAddOns(cpu, TOP_ADDONS)
	if scanMemory then
		self.addonMemory = L.SortAddOns(memory, TOP_ADDONS)
	end
end

-- The page is plain text, so it is re-rendered once a second for as long as it stays open.
function Performance:Live()
	local now = GetTime()
	if self.lastSample == nil or now - self.lastSample >= REFRESH * 0.5 then
		self:Sample()
	end
	if self.refreshPending then
		return
	end
	self.refreshPending = true
	C_Timer.After(REFRESH, function()
		self.refreshPending = false
		if ns.OptionsWindow:CurrentTab() == PAGE then
			AceConfigRegistry:NotifyChange("MerrinxUI")
		end
	end)
end

function Performance:OverviewText()
	self:Live()
	local fps = self.fps or 0
	local lines = {
		"FPS  " .. value(string.format("%.0f", fps)),
	}
	if self.home and self.world then
		lines[#lines + 1] = "Latency  " .. value(string.format("%d ms home, %d ms world", self.home, self.world))
	end
	if self.profiler then
		lines[#lines + 1] = "MerrinxUI CPU  "
			.. value(
				string.format(
					"%s per frame (%.1f%% of a frame), peak %s",
					L.FormatMs(self.cpu),
					L.FrameShare(self.cpu, fps),
					L.FormatMs(self.cpuPeak)
				)
			)
		if self.overall then
			lines[#lines + 1] = "Share of all addon CPU  "
				.. value(string.format("%.0f%%", L.Share(self.cpu, self.overall)))
		end
	else
		lines[#lines + 1] = "MerrinxUI CPU  " .. value("the client's addon profiler is off")
	end
	lines[#lines + 1] = "MerrinxUI memory  "
		.. value(self.memory and L.FormatMemory(self.memory) or "after combat")
		.. "    Lua total  "
		.. value(L.FormatMemory(self.lua))
	return table.concat(lines, "\n")
end

function Performance:ModulesText()
	if not self:IsEnabled() then
		return "Turn on Time each module to see which modules use the most CPU."
	end
	local total = L.Sum(groups)
	local lines = {}
	for _, row in ipairs(L.Top(groups, self.db.profile.rows)) do
		if row.calls > 0 then
			lines[#lines + 1] = row.name
				.. "  "
				.. value(
					string.format(
						"%.2f ms/s (%.0f%%), %d calls, peak %s",
						row.rate,
						L.Share(row.rate, total),
						row.calls,
						L.FormatMs(row.peak)
					)
				)
		end
	end
	if #lines == 0 then
		return "No module work recorded yet."
	end
	return "ms of CPU per second over the last " .. WINDOW .. " seconds.\n" .. table.concat(lines, "\n")
end

local function listText(entries, format)
	if #entries == 0 then
		return "Nothing recorded yet."
	end
	local lines = {}
	for i, e in ipairs(entries) do
		lines[i] = e.name .. "  " .. value(format(e.value))
	end
	return table.concat(lines, "\n")
end

function Performance:GetTabOptions()
	local pf = self
	return {
		type = "group",
		name = PAGE,
		args = {
			enabled = {
				type = "toggle",
				name = "Time each module",
				order = 1,
				desc = "Measures how long each MerrinxUI module runs. Adds a small cost of its own while on.",
				get = function()
					return pf.db.profile.enabled
				end,
				set = function(_, v)
					pf.db.profile.enabled = v
					pf:Refresh()
				end,
			},
			rows = {
				type = "range",
				name = "Modules shown",
				order = 2,
				min = 1,
				max = 20,
				step = 1,
				get = function()
					return pf.db.profile.rows
				end,
				set = function(_, v)
					pf.db.profile.rows = v
				end,
			},
			reset = {
				type = "execute",
				name = "Reset module times",
				order = 3,
				func = function()
					pf:ResetStats()
				end,
			},
			overviewHeader = { type = "header", name = "Overview", order = 10 },
			overview = {
				type = "description",
				order = 11,
				name = function()
					return pf:OverviewText()
				end,
			},
			modulesHeader = { type = "header", name = "Modules", order = 20 },
			modules = {
				type = "description",
				order = 21,
				name = function()
					return pf:ModulesText()
				end,
			},
			cpuHeader = { type = "header", name = "Top addons by CPU per frame", order = 30 },
			cpu = {
				type = "description",
				order = 31,
				name = function()
					pf:Live()
					if not pf.profiler then
						return "The client's addon profiler is off."
					end
					return listText(pf.addonCpu, L.FormatMs)
				end,
			},
			memoryHeader = { type = "header", name = "Top addons by memory", order = 40 },
			memory = {
				type = "description",
				order = 41,
				name = function()
					pf:Live()
					return listText(pf.addonMemory, L.FormatMemory)
						.. "\nRefreshed at most every "
						.. MEMORY_INTERVAL
						.. " seconds, never in combat."
				end,
			},
		},
	}
end

function Performance:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				for name, fn in pairs({
					GetFramerate = GetFramerate,
					GetNetStats = GetNetStats,
					debugprofilestop = debugprofilestop,
					UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage,
					GetAddOnMemoryUsage = GetAddOnMemoryUsage,
					["C_AddOns.GetNumAddOns"] = C_AddOns and C_AddOns.GetNumAddOns,
					["C_AddOns.IsAddOnLoaded"] = C_AddOns and C_AddOns.IsAddOnLoaded,
					["C_AddOns.GetAddOnInfo"] = C_AddOns and C_AddOns.GetAddOnInfo,
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
			name = "profiler",
			run = function()
				if type(C_AddOnProfiler) ~= "table" then
					return "INFO", "no C_AddOnProfiler"
				end
				return "INFO", profilerOn(), self.cpu, self.cpuPeak, self.overall
			end,
		},
		{
			name = "sample",
			run = function()
				if self.lastSample == nil then
					return "SKIP", "page not opened"
				end
				local ok = type(self.fps) == "number" and type(self.lua) == "number"
				return ok and "PASS" or "FAIL",
					self.fps,
					self.home,
					self.world,
					self.memory,
					self.lua,
					self.memScans,
					#self.addonCpu,
					#self.addonMemory
			end,
		},
		{
			name = "instrumentation",
			run = function(ctx)
				if ctx.enabled == false then
					return #wrapped == 0 and "PASS" or "FAIL", "off", #wrapped
				end
				local intact = 0
				for _, w in ipairs(wrapped) do
					if w.tbl[w.key] == w.wrapper then
						intact = intact + 1
					end
				end
				local groupCount = 0
				for _ in pairs(groups) do
					groupCount = groupCount + 1
				end
				return (#wrapped > 0 and intact == #wrapped) and "PASS" or "FAIL", intact, #wrapped, groupCount, depth
			end,
		},
		{
			name = "top modules",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local out = {}
				for _, row in ipairs(L.Top(groups, 8)) do
					out[#out + 1] = string.format("%s=%.2f/%.0f/%d", row.name, row.rate, row.total, row.calls)
				end
				return "INFO", unpack(out, 1, #out)
			end,
		},
	}
end
