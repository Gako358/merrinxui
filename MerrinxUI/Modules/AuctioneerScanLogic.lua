local addonName, ns = ...

local AuctioneerScanLogic = {}
ns.AuctioneerScanLogic = AuctioneerScanLogic

local L = AuctioneerScanLogic

L.THROTTLE = 900
L.MAX_GAP = 43200
L.BAND_LOWER = { [0] = 0, [1] = 1800, [2] = 7200, [3] = 43200 }

local function isPositiveInt(n)
	return type(n) == "number" and n >= 1 and n % 1 == 0
end

local function parseBucketKey(key)
	local buyout, count = key:match("^(%d+),(%d+)$")
	return tonumber(buyout), tonumber(count)
end

-- Canonical bucket order: unit ascending via cross multiplication (avoids float division), then count, then buyout.
local function compareBuckets(a, b)
	local cross = a.buyout * b.count - b.buyout * a.count
	if cross ~= 0 then
		return cross < 0
	end
	if a.count ~= b.count then
		return a.count < b.count
	end
	return a.buyout < b.buyout
end

function L.Day(t)
	if type(t) ~= "number" then
		return nil
	end
	return math.floor(t / 86400)
end

function L.ThrottleLeft(now, last)
	if not last or last == 0 or now - last >= L.THROTTLE then
		return 0
	end
	return math.min(L.THROTTLE, L.THROTTLE - (now - last))
end

function L.NewAccumulator()
	return { rows = 0, skipped = 0, items = {} }
end

function L.AddRow(acc, row)
	acc.rows = acc.rows + 1
	local itemID, count, buyout = row.itemID, row.count, row.buyout
	if not (isPositiveInt(itemID) and isPositiveInt(count) and isPositiveInt(buyout)) then
		acc.skipped = acc.skipped + 1
		return false
	end
	local band = row.band
	if type(band) ~= "number" or band < 0 or band > 3 then
		band = 0
	end

	local item = acc.items[itemID]
	if not item then
		item =
			{ itemID = itemID, name = nil, quality = nil, auctions = 0, qty = 0, min = nil, entries = {}, buckets = {} }
		acc.items[itemID] = item
	end
	if item.name == nil and type(row.name) == "string" then
		item.name = row.name
	end
	if item.quality == nil and type(row.quality) == "number" then
		item.quality = row.quality
	end

	local unit = math.floor(buyout / count)
	item.auctions = item.auctions + 1
	item.qty = item.qty + count
	if item.min == nil or unit < item.min then
		item.min = unit
	end
	item.entries[#item.entries + 1] = { unit, count }

	local key = L.BucketKey(buyout, count)
	local bucket = item.buckets[key]
	if not bucket then
		bucket = { 0, 0, 0, 0 }
		item.buckets[key] = bucket
	end
	bucket[band + 1] = bucket[band + 1] + 1
	return true
end

function L.Finish(acc)
	local summaries = {}
	for itemID, item in pairs(acc.items) do
		summaries[itemID] = {
			itemID = itemID,
			name = item.name,
			quality = item.quality,
			auctions = item.auctions,
			qty = item.qty,
			min = item.min,
			med = L.WeightedMedian(item.entries),
			buckets = item.buckets,
		}
	end
	return summaries, acc.rows, acc.skipped
end

function L.BucketKey(buyout, count)
	return buyout .. "," .. count
end

function L.WeightedMedian(entries)
	if #entries == 0 then
		return nil
	end
	local sorted = {}
	for i, entry in ipairs(entries) do
		sorted[i] = entry
	end
	table.sort(sorted, function(a, b)
		return a[1] < b[1]
	end)

	local total = 0
	for _, entry in ipairs(sorted) do
		total = total + entry[2]
	end
	local threshold = math.ceil(total / 2)

	local cumulative = 0
	for _, entry in ipairs(sorted) do
		cumulative = cumulative + entry[2]
		if cumulative >= threshold then
			return entry[1]
		end
	end
	return nil
end

function L.PackSnapshot(buckets)
	local list = {}
	for key, counts in pairs(buckets) do
		local buyout, count = parseBucketKey(key)
		list[#list + 1] = { buyout = buyout, count = count, counts = counts }
	end
	table.sort(list, compareBuckets)

	local parts = {}
	for i, b in ipairs(list) do
		parts[i] =
			string.format("%d,%d,%d,%d,%d,%d", b.buyout, b.count, b.counts[1], b.counts[2], b.counts[3], b.counts[4])
	end
	return table.concat(parts, ";")
end

function L.UnpackSnapshot(s)
	local buckets = {}
	if s == nil or s == "" then
		return buckets
	end
	for part in s:gmatch("[^;]+") do
		local buyout, count, n0, n1, n2, n3 = part:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$")
		if buyout then
			buyout, count = tonumber(buyout), tonumber(count)
			n0, n1, n2, n3 = tonumber(n0), tonumber(n1), tonumber(n2), tonumber(n3)
			if buyout >= 1 and count >= 1 and n0 + n1 + n2 + n3 >= 1 then
				local key = L.BucketKey(buyout, count)
				local existing = buckets[key]
				if existing then
					existing[1], existing[2], existing[3], existing[4] =
						existing[1] + n0, existing[2] + n1, existing[3] + n2, existing[4] + n3
				else
					buckets[key] = { n0, n1, n2, n3 }
				end
			end
		end
	end
	return buckets
end

function L.Listings(buckets)
	local list = {}
	for key, counts in pairs(buckets) do
		local buyout, count = parseBucketKey(key)
		list[#list + 1] = { buyout = buyout, count = count, n = counts[1] + counts[2] + counts[3] + counts[4] }
	end
	table.sort(list, compareBuckets)
	return list
end

function L.EstimateRemoved(prev, cur, gap)
	if type(gap) ~= "number" or gap < 0 or gap > L.MAX_GAP or next(prev) == nil then
		return nil
	end
	local removedUnits = 0
	for key, prevCounts in pairs(prev) do
		local p = prevCounts[1] + prevCounts[2] + prevCounts[3] + prevCounts[4]
		local curCounts = cur[key]
		local c = curCounts and (curCounts[1] + curCounts[2] + curCounts[3] + curCounts[4]) or 0
		local disappeared = math.max(0, p - c)

		local expirable = 0
		for band = 0, 3 do
			if L.BAND_LOWER[band] < gap then
				expirable = expirable + prevCounts[band + 1]
			end
		end

		local _, count = parseBucketKey(key)
		removedUnits = removedUnits + math.max(0, disappeared - expirable) * count
	end
	return removedUnits
end

function L.UnpackHistory(s)
	if s == nil or s == "" then
		return {}
	end
	local byDay, order = {}, {}
	for part in s:gmatch("[^;]+") do
		local day, min, med, qty, sold, obs, scans = part:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$")
		if day then
			day, min, med, qty, sold, obs, scans =
				tonumber(day),
				tonumber(min),
				tonumber(med),
				tonumber(qty),
				tonumber(sold),
				tonumber(obs),
				tonumber(scans)
			if scans >= 1 then
				if byDay[day] == nil then
					order[#order + 1] = day
				end
				byDay[day] = { day = day, min = min, med = med, qty = qty, sold = sold, obs = obs, scans = scans }
			end
		end
	end
	table.sort(order)
	local records = {}
	for i, day in ipairs(order) do
		records[i] = byDay[day]
	end
	return records
end

function L.PackHistory(records)
	local parts = {}
	for i, rec in ipairs(records) do
		parts[i] =
			string.format("%d,%d,%d,%d,%d,%d,%d", rec.day, rec.min, rec.med, rec.qty, rec.sold, rec.obs, rec.scans)
	end
	return table.concat(parts, ";")
end

function L.MergeScan(records, day, scan)
	for _, rec in ipairs(records) do
		if rec.day == day then
			rec.scans = rec.scans + 1
			if scan.qty > 0 then
				rec.med = scan.med
				rec.min = (rec.min == 0) and scan.min or math.min(rec.min, scan.min)
			end
			rec.qty = scan.qty
			if scan.sold ~= nil then
				rec.sold = rec.sold + scan.sold
				rec.obs = rec.obs + 1
			end
			return records
		end
	end

	local rec = {
		day = day,
		min = scan.min,
		med = scan.med,
		qty = scan.qty,
		sold = scan.sold or 0,
		obs = scan.sold and 1 or 0,
		scans = 1,
	}
	local index = #records + 1
	for i, existing in ipairs(records) do
		if existing.day > day then
			index = i
			break
		end
	end
	table.insert(records, index, rec)
	return records
end

function L.Prune(records, today, keepDays)
	local threshold = today - keepDays
	local write = 0
	for read = 1, #records do
		local rec = records[read]
		if rec.day > threshold then
			write = write + 1
			records[write] = rec
		end
	end
	for i = #records, write + 1, -1 do
		records[i] = nil
	end
	return records
end
