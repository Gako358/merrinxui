local addonName, ns = ...

local PerformanceLogic = {}
ns.PerformanceLogic = PerformanceLogic

local L = PerformanceLogic

function L.NewStats()
	return { total = 0, calls = 0, peak = 0, bucket = 0, ring = {}, ringDt = {}, pos = 0 }
end

function L.Reset(s)
	s.total, s.calls, s.peak, s.bucket, s.pos = 0, 0, 0, 0, 0
	s.ring, s.ringDt = {}, {}
end

function L.Record(s, ms)
	s.total = s.total + ms
	s.calls = s.calls + 1
	s.bucket = s.bucket + ms
	if ms > s.peak then
		s.peak = ms
	end
end

-- Closes the open bucket as one sample of dt seconds; the window keeps the last size samples.
function L.Roll(s, dt, size)
	local pos = s.pos % size + 1
	s.ring[pos] = s.bucket
	s.ringDt[pos] = dt
	s.pos = pos
	s.bucket = 0
	for i = size + 1, #s.ring do
		s.ring[i], s.ringDt[i] = nil, nil
	end
end

-- Milliseconds of work per second of play over the window.
function L.Rate(s)
	local ms, dt = 0, 0
	for i, v in pairs(s.ring) do
		ms = ms + v
		dt = dt + s.ringDt[i]
	end
	if dt <= 0 then
		return 0
	end
	return ms / dt
end

function L.Top(statsByName, n)
	local list = {}
	for name, s in pairs(statsByName) do
		list[#list + 1] = { name = name, rate = L.Rate(s), total = s.total, peak = s.peak, calls = s.calls }
	end
	table.sort(list, function(a, b)
		if a.rate ~= b.rate then
			return a.rate > b.rate
		end
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.name < b.name
	end)
	for i = n + 1, #list do
		list[i] = nil
	end
	return list
end

function L.Sum(statsByName)
	local rate, total = 0, 0
	for _, s in pairs(statsByName) do
		rate = rate + L.Rate(s)
		total = total + s.total
	end
	return rate, total
end

function L.FrameShare(msPerFrame, fps)
	if type(msPerFrame) ~= "number" or type(fps) ~= "number" or fps <= 0 then
		return 0
	end
	return msPerFrame / (1000 / fps) * 100
end

function L.Share(part, whole)
	if type(part) ~= "number" or type(whole) ~= "number" or whole <= 0 then
		return 0
	end
	return part / whole * 100
end

function L.FormatMemory(kb)
	if type(kb) ~= "number" then
		return "?"
	end
	if kb >= 1024 then
		return string.format("%.2f MB", kb / 1024)
	end
	return string.format("%.0f KB", kb)
end

function L.FormatMs(ms)
	if type(ms) ~= "number" then
		return "?"
	end
	if ms < 10 then
		return string.format("%.3f ms", ms)
	end
	return string.format("%.2f ms", ms)
end

-- entries: { { name = string, value = number } }
function L.SortAddOns(entries, n)
	local list = {}
	for _, e in ipairs(entries) do
		if type(e.value) == "number" and e.value > 0 then
			list[#list + 1] = e
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.name < b.name
	end)
	for i = n + 1, #list do
		list[i] = nil
	end
	return list
end
