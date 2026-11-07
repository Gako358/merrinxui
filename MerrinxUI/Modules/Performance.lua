local addonName, ns = ...

local L = ns.PerformanceLogic
local FontLogic = ns.FontLogic
local C = ns.Theme.color

local WINDOW = 5
local MEMORY_INTERVAL = 30
local TOOLTIP_ADDONS = 10
local WIDTH = 260
local PAD = 6
local LINE_GAP = 2

local Performance = ns.addon:NewModule("Performance", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = false,
		moduleTiming = true,
		rows = 8,
		interval = 1,
		font = FontLogic.GLOBAL,
		fontSize = 11,
		bgOpacity = 60,
		position = { point = "CENTER", x = 400, y = 0 },
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

local mixinSources = { LibStub("AceEvent-3.0"), LibStub("AceConsole-3.0") }

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

local function profilerOn()
	return type(C_AddOnProfiler) == "table"
		and type(C_AddOnProfiler.IsEnabled) == "function"
		and type(C_AddOnProfiler.GetAddOnMetric) == "function"
		and type(Enum) == "table"
		and type(Enum.AddOnProfilerMetric) == "table"
		and C_AddOnProfiler.IsEnabled() == true
end

local function plain(value)
	if type(value) ~= "number" or issecretvalue(value) then
		return nil
	end
	return value
end

local function metric(name, key)
	return plain(C_AddOnProfiler.GetAddOnMetric(name, Enum.AddOnProfilerMetric[key]))
end

function Performance:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Performance", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.lines = {}
	self.memScans = 0
	self.lastMemScan = nil
	self.lastSample = nil
	self:Build()
end

function Performance:OnEnable()
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "Render")
	if self.db.profile.moduleTiming then
		self:Instrument()
	end
	self:StartTicker()
	self:Layout()
	ns.Mover:Apply(self.frame)
	self:Sample()
	self.frame:Show()
end

function Performance:OnDisable()
	self:StopTicker()
	self:Restore()
	self.frame:Hide()
end

function Performance:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			if self.db.profile.moduleTiming then
				self:Instrument()
			else
				self:Restore()
			end
			self:StartTicker()
			self:Layout()
			ns.Mover:Apply(self.frame)
			self:Render()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function Performance:OnMediaChanged(_, mediatype, key)
	if mediatype == "font" and (key == nil or key == ns.Media:Resolve("font", self.db.profile.font)) then
		self:Layout()
	end
end

function Performance:StartTicker()
	self:StopTicker()
	self.ticker = C_Timer.NewTicker(self.db.profile.interval, function()
		-- A timed call that raised never reached finish(); this bounds the untimed stretch to one interval.
		depth = 0
		self:Sample()
	end)
end

function Performance:StopTicker()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
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
	self.lastSample = GetTime()
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

function Performance:ResetStats()
	for _, stats in pairs(groups) do
		L.Reset(stats)
	end
	self:Render()
end

function Performance:Sample()
	local now = GetTime()
	local dt = self.lastSample and (now - self.lastSample) or self.db.profile.interval
	self.lastSample = now
	if dt > 0 then
		for _, stats in pairs(groups) do
			L.Roll(stats, dt, WINDOW)
		end
	end

	self.fps = plain(GetFramerate())
	local _, _, home, world = GetNetStats()
	self.home, self.world = plain(home), plain(world)
	self.lua = collectgarbage("count")

	self.profiler = profilerOn()
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
	if not InCombatLockdown() and (self.lastMemScan == nil or now - self.lastMemScan >= MEMORY_INTERVAL) then
		self.lastMemScan = now
		self.memScans = self.memScans + 1
		UpdateAddOnMemoryUsage()
		self.memory = GetAddOnMemoryUsage(addonName)
	end

	self:Render()
end

function Performance:Build()
	local frame = CreateFrame("Frame", addonName .. "Performance", UIParent, "BackdropTemplate")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	frame:SetBackdropBorderColor(0, 0, 0, 1)
	self.frame = frame

	self.bg = frame:CreateTexture(nil, "BACKGROUND")
	self.bg:SetPoint("TOPLEFT", 1, -1)
	self.bg:SetPoint("BOTTOMRIGHT", -1, 1)

	frame:SetScript("OnEnter", function(owner)
		self:ShowTooltip(owner)
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	ns.Mover:Register(frame, "Performance", function()
		return self.db.profile.position
	end)
end

function Performance:Line(i)
	local line = self.lines[i]
	if line then
		return line
	end
	local left = self.frame:CreateFontString(nil, "OVERLAY")
	local right = self.frame:CreateFontString(nil, "OVERLAY")
	left:SetJustifyH("LEFT")
	right:SetJustifyH("RIGHT")
	left:SetWordWrap(false)
	right:SetWordWrap(false)
	line = { left = left, right = right }
	self.lines[i] = line
	self:StyleLine(line, i)
	return line
end

function Performance:StyleLine(line, i)
	local p = self.db.profile
	ns.Media:SetFont(line.left, p.font, p.fontSize, "")
	ns.Media:SetFont(line.right, p.font, p.fontSize, "")
	local y = -PAD - (i - 1) * (p.fontSize + LINE_GAP)
	line.left:ClearAllPoints()
	line.right:ClearAllPoints()
	line.left:SetPoint("TOPLEFT", PAD, y)
	line.right:SetPoint("TOPRIGHT", -PAD, y)
	line.left:SetWidth(WIDTH * 0.45)
	line.right:SetWidth(WIDTH * 0.55 - PAD * 2)
end

function Performance:Layout()
	local p = self.db.profile
	self.bg:SetColorTexture(0, 0, 0, p.bgOpacity / 100)
	for i, line in ipairs(self.lines) do
		self:StyleLine(line, i)
	end
	self:Render()
end

local function setLine(line, label, value, dim)
	local color = dim and C.textDim or C.text
	line.left:SetText(label)
	line.right:SetText(value)
	line.left:SetTextColor(color[1], color[2], color[3], color[4])
	line.right:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])
	line.left:Show()
	line.right:Show()
end

function Performance:Entries()
	local entries = {}
	local function add(label, value, dim)
		entries[#entries + 1] = { label, value, dim }
	end

	local fps = self.fps or 0
	add("FPS", string.format("%.0f", fps))
	if type(self.home) == "number" and type(self.world) == "number" then
		add("Latency", string.format("%d / %d ms", self.home, self.world))
	end
	if self.profiler then
		add("CPU", string.format("%s (%.1f%%)", L.FormatMs(self.cpu), L.FrameShare(self.cpu, fps)), false)
		add("CPU peak", L.FormatMs(self.cpuPeak))
		if self.overall then
			add("Of all addons", string.format("%.0f%%", L.Share(self.cpu, self.overall)))
		end
	else
		add("CPU", "profiler off", true)
	end
	add("Memory", L.FormatMemory(self.memory))
	add("Lua total", L.FormatMemory(self.lua))

	local p = self.db.profile
	if p.moduleTiming and p.rows > 0 and #wrapped > 0 then
		local total = L.Sum(groups)
		add("Module", "ms/s", true)
		for _, row in ipairs(L.Top(groups, p.rows)) do
			add(row.name, string.format("%.2f  %3.0f%%", row.rate, L.Share(row.rate, total)))
		end
	end
	return entries
end

function Performance:Render()
	if not self:IsEnabled() then
		return
	end
	local entries = self:Entries()
	for i, e in ipairs(entries) do
		setLine(self:Line(i), e[1], e[2], e[3])
	end
	for i = #entries + 1, #self.lines do
		self.lines[i].left:Hide()
		self.lines[i].right:Hide()
	end
	local step = self.db.profile.fontSize + LINE_GAP
	self.frame:SetSize(WIDTH, PAD * 2 + #entries * step - LINE_GAP)
	self.frame:Show()
end

function Performance:AddOnLists()
	local cpu, memory = {}, {}
	if type(C_AddOns) ~= "table" or type(C_AddOns.GetNumAddOns) ~= "function" then
		return cpu, memory
	end
	local profiler = profilerOn()
	local now = GetTime()
	if not InCombatLockdown() and (self.lastMemScan == nil or now - self.lastMemScan >= MEMORY_INTERVAL) then
		self.lastMemScan = now
		self.memScans = self.memScans + 1
		UpdateAddOnMemoryUsage()
		self.memory = GetAddOnMemoryUsage(addonName)
	end
	for i = 1, C_AddOns.GetNumAddOns() do
		if C_AddOns.IsAddOnLoaded(i) then
			local name = C_AddOns.GetAddOnInfo(i)
			memory[#memory + 1] = { name = name, value = plain(GetAddOnMemoryUsage(i)) }
			if profiler then
				cpu[#cpu + 1] = { name = name, value = metric(name, "RecentAverageTime") }
			end
		end
	end
	return L.SortAddOns(cpu, TOOLTIP_ADDONS), L.SortAddOns(memory, TOOLTIP_ADDONS)
end

function Performance:ShowTooltip(owner)
	local cpu, memory = self:AddOnLists()
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:SetText("Performance", 1, 1, 1)
	if #cpu > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("CPU per frame", C.accent[1], C.accent[2], C.accent[3])
		for _, e in ipairs(cpu) do
			GameTooltip:AddDoubleLine(e.name, L.FormatMs(e.value), 1, 1, 1, 1, 1, 1)
		end
	elseif not profilerOn() then
		GameTooltip:AddLine("The client's addon profiler is off", 1, 1, 1)
	end
	if #memory > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Memory", C.accent[1], C.accent[2], C.accent[3])
		for _, e in ipairs(memory) do
			GameTooltip:AddDoubleLine(e.name, L.FormatMemory(e.value), 1, 1, 1, 1, 1, 1)
		end
	end
	if self.db.profile.moduleTiming and #wrapped > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Module ms/s: last " .. WINDOW .. " samples. Totals since reset:", 1, 1, 1)
		for _, row in ipairs(L.Top(groups, 20)) do
			if row.calls > 0 then
				GameTooltip:AddDoubleLine(
					row.name,
					string.format("%.0f ms, %d calls, peak %s", row.total, row.calls, L.FormatMs(row.peak)),
					1,
					1,
					1,
					1,
					1,
					1
				)
			end
		end
	end
	GameTooltip:Show()
end

function Performance:GetOptions()
	local pf = self
	local function get(key)
		return function()
			return pf.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			pf.db.profile[key] = value
			pf:Refresh()
		end
	end
	local function range(key, name, order, min, max, step)
		return {
			type = "range",
			name = name,
			order = order,
			min = min,
			max = max,
			step = step,
			get = get(key),
			set = set(key),
		}
	end
	return {
		type = "group",
		name = "Performance",
		args = {
			enabled = {
				type = "toggle",
				name = "Enabled",
				order = 1,
				desc = "FPS, latency, MerrinxUI CPU and memory; hover the panel for the top addons",
				get = get("enabled"),
				set = set("enabled"),
			},
			moduleTiming = {
				type = "toggle",
				name = "Time each module",
				order = 2,
				desc = "Measures how long each MerrinxUI module runs. Adds a small cost of its own while on.",
				get = get("moduleTiming"),
				set = set("moduleTiming"),
			},
			rows = range("rows", "Module rows", 3, 0, 20, 1),
			interval = range("interval", "Update every (s)", 4, 0.5, 5, 0.5),
			font = {
				type = "select",
				name = "Font",
				order = 5,
				dialogControl = "LSM30_Font",
				values = function()
					return ns.Media:Values("font", pf.db.profile.font)
				end,
				get = get("font"),
				set = set("font"),
			},
			fontSize = range("fontSize", "Font size", 6, 8, 20, 1),
			bgOpacity = range("bgOpacity", "Background opacity", 7, 0, 100, 5),
			reset = {
				type = "execute",
				name = "Reset module times",
				order = 8,
				func = function()
					pf:ResetStats()
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
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local ok = type(self.fps) == "number" and type(self.lua) == "number"
				return ok and "PASS" or "FAIL", self.fps, self.home, self.world, self.memory, self.lua, self.memScans
			end,
		},
		{
			name = "instrumentation",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not self.db.profile.moduleTiming then
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
				if ctx.enabled == false or #wrapped == 0 then
					return "SKIP", "not timing"
				end
				local out = {}
				for _, row in ipairs(L.Top(groups, 8)) do
					out[#out + 1] = string.format("%s=%.2f/%.0f/%d", row.name, row.rate, row.total, row.calls)
				end
				return "INFO", unpack(out, 1, #out)
			end,
		},
		{
			name = "panel",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return self.frame:IsShown() and "PASS" or "FAIL", #self.lines, self.frame:GetHeight()
			end,
		},
	}
end
