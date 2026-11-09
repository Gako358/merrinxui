local addonName, ns = ...

local AuctioneerLogic = {}
ns.AuctioneerLogic = AuctioneerLogic

local L = AuctioneerLogic

L.MARKET_DAYS = 7
L.MIN_DAYS = 3
L.MOVER_PCT = 20
L.MAX_CV = 0.5
L.OVERSUPPLY = 2
L.MIN_VALUE = 100
L.HOT_MIN_SOLD = 1
L.FALL_PCT = 10
L.MAX_ROWS = 200

L.REASON_ORDER = { "volatile", "falling", "oversupply", "no_sales" }
L.REASONS = {
	volatile = "Price swings a lot",
	falling = "Price falling",
	oversupply = "Flooded",
	no_sales = "Not selling",
}

function L.Median(values)
	local n = #values
	if n == 0 then
		return nil
	end
	local sorted = {}
	for i = 1, n do
		sorted[i] = values[i]
	end
	table.sort(sorted)
	if n % 2 == 1 then
		return sorted[(n + 1) / 2]
	end
	return math.floor((sorted[n / 2] + sorted[n / 2 + 1]) / 2)
end

local function mean(values)
	local sum = 0
	for _, v in ipairs(values) do
		sum = sum + v
	end
	return sum / #values
end

local function popStdDev(values, avg)
	local sum = 0
	for _, v in ipairs(values) do
		sum = sum + (v - avg) ^ 2
	end
	return math.sqrt(sum / #values)
end

function L.Stats(item, today)
	local window, priced = {}, {}
	for _, rec in ipairs(item.history or {}) do
		if today - L.MARKET_DAYS < rec.day and rec.day <= today then
			window[#window + 1] = rec
			if rec.med > 0 then
				priced[#priced + 1] = rec
			end
		end
	end
	table.sort(window, function(a, b)
		return a.day < b.day
	end)
	table.sort(priced, function(a, b)
		return a.day < b.day
	end)

	local pricedMeds = {}
	for _, rec in ipairs(priced) do
		pricedMeds[#pricedMeds + 1] = rec.med
	end
	local days = #priced

	local cv = nil
	if days >= 2 then
		local avg = mean(pricedMeds)
		cv = popStdDev(pricedMeds, avg) / avg
	end

	local cur = nil
	for _, rec in ipairs(window) do
		if rec.day == today and rec.med > 0 then
			cur = rec.med
		end
	end

	local refValues = {}
	for _, rec in ipairs(priced) do
		if rec.day < today then
			refValues[#refValues + 1] = rec.med
		end
	end
	local ref = L.Median(refValues)
	local refDays = #refValues

	local change = nil
	if cur ~= nil and ref ~= nil and refDays >= 2 then
		change = (cur - ref) * 100 / ref
	end

	local qty, minUnit = 0, nil
	for _, listing in ipairs(item.listings or {}) do
		qty = qty + listing.count * listing.n
		local unit = math.floor(listing.buyout / listing.count)
		if minUnit == nil or unit < minUnit then
			minUnit = unit
		end
	end

	local priorCount, priorQty = 0, 0
	for _, rec in ipairs(window) do
		if rec.day < today then
			priorCount = priorCount + 1
			priorQty = priorQty + rec.qty
		end
	end
	local supply = nil
	if priorCount >= 2 then
		local meanQty = priorQty / priorCount
		if meanQty > 0 then
			supply = qty / meanQty
		end
	end

	local obsDays, sumSold = 0, 0
	for _, rec in ipairs(window) do
		if rec.obs > 0 then
			obsDays = obsDays + 1
		end
		sumSold = sumSold + rec.sold
	end
	local soldPerDay = obsDays > 0 and (sumSold / obsDays) or nil

	local falling = false
	if days >= 3 then
		local p1, p2, p3 = priced[days - 2].med, priced[days - 1].med, priced[days].med
		falling = p1 > p2 and p2 > p3 and (p1 - p3) * 100 / p1 >= L.FALL_PCT
	end

	return {
		market = L.Median(pricedMeds),
		days = days,
		cv = cv,
		cur = cur,
		ref = ref,
		refDays = refDays,
		change = change,
		qty = qty,
		min = minUnit,
		supply = supply,
		obsDays = obsDays,
		soldPerDay = soldPerDay,
		falling = falling,
	}
end

function L.AvoidReasons(stats)
	local reasons = {}
	if stats.qty > 0 and stats.market ~= nil and stats.market >= L.MIN_VALUE then
		if stats.cv ~= nil and stats.days >= L.MIN_DAYS and stats.cv >= L.MAX_CV then
			reasons[#reasons + 1] = "volatile"
		end
		if stats.falling then
			reasons[#reasons + 1] = "falling"
		end
		if stats.supply ~= nil and stats.supply >= L.OVERSUPPLY then
			reasons[#reasons + 1] = "oversupply"
		end
		if stats.obsDays >= L.MIN_DAYS and stats.soldPerDay == 0 then
			reasons[#reasons + 1] = "no_sales"
		end
	end
	return reasons
end

local function listingLess(a, b)
	local ac, bc = a.buyout * b.count, b.buyout * a.count
	if ac ~= bc then
		return ac < bc
	end
	if a.count ~= b.count then
		return a.count < b.count
	end
	return a.buyout < b.buyout
end

local function takeListings(listings, qualifies)
	local qty, cost, unitMax = 0, 0, nil
	local taken = {}
	for _, listing in ipairs(listings or {}) do
		if qualifies(listing) then
			qty = qty + listing.count * listing.n
			cost = cost + listing.buyout * listing.n
			local unit = math.floor(listing.buyout / listing.count)
			if unitMax == nil or unit > unitMax then
				unitMax = unit
			end
			taken[#taken + 1] = { buyout = listing.buyout, count = listing.count, n = listing.n }
		end
	end
	table.sort(taken, listingLess)
	return qty, cost, unitMax, taken
end

function L.FindDeal(item, stats, settings)
	local best = nil

	if
		stats.market ~= nil
		and stats.days >= L.MIN_DAYS
		and stats.market >= L.MIN_VALUE
		and #L.AvoidReasons(stats) == 0
	then
		local target = math.floor(stats.market * (1 - settings.discount))
		local net = math.floor(stats.market * (1 - settings.cut))
		local qty, cost, unitMax, listings = takeListings(item.listings, function(listing)
			return listing.buyout <= target * listing.count
		end)
		local profit = qty * net - cost
		if qty > 0 and profit > 0 and profit >= settings.minProfit then
			best = {
				kind = "flip",
				itemID = item.itemID,
				name = item.name,
				quality = item.quality,
				qty = qty,
				cost = cost,
				unitMax = unitMax,
				sellUnit = stats.market,
				profit = profit,
				margin = math.floor(profit * 100 / cost),
				soldPerDay = stats.soldPerDay,
				net = net,
				listings = listings,
			}
		end
	end

	if item.vendor ~= nil and item.vendor > 0 then
		local vendor = item.vendor
		local qty, cost, unitMax, listings = takeListings(item.listings, function(listing)
			return listing.buyout < vendor * listing.count
		end)
		local profit = vendor * qty - cost
		if qty > 0 and profit > 0 and profit >= settings.minProfit then
			if best == nil or profit >= best.profit then
				best = {
					kind = "vendor",
					itemID = item.itemID,
					name = item.name,
					quality = item.quality,
					qty = qty,
					cost = cost,
					unitMax = unitMax,
					sellUnit = vendor,
					profit = profit,
					margin = math.floor(profit * 100 / cost),
					soldPerDay = stats.soldPerDay,
					net = vendor,
					listings = listings,
				}
			end
		end
	end

	return best
end

local function byItemID(a, b)
	return a.itemID < b.itemID
end

local function cap(list)
	if #list <= L.MAX_ROWS then
		return list
	end
	local trimmed = {}
	for i = 1, L.MAX_ROWS do
		trimmed[i] = list[i]
	end
	return trimmed
end

function L.Analyze(items, today, settings)
	local deals, movers, hot, avoid, prices = {}, {}, {}, {}, {}

	for _, item in ipairs(items) do
		local stats = L.Stats(item, today)

		prices[item.itemID] = {
			name = item.name,
			quality = item.quality,
			market = stats.market,
			min = stats.min,
			vendor = item.vendor,
		}

		local deal = L.FindDeal(item, stats, settings)
		if deal then
			deals[#deals + 1] = deal
		end

		local isMover = stats.change ~= nil
			and math.abs(stats.change) >= L.MOVER_PCT
			and stats.market ~= nil
			and stats.market >= L.MIN_VALUE
		if isMover then
			movers[#movers + 1] = {
				itemID = item.itemID,
				name = item.name,
				quality = item.quality,
				change = stats.change,
				cur = stats.cur,
				ref = stats.ref,
				qty = stats.qty,
			}
		end

		local isHot = stats.soldPerDay ~= nil
			and stats.soldPerDay >= L.HOT_MIN_SOLD
			and stats.market ~= nil
			and stats.market >= L.MIN_VALUE
		if isHot then
			hot[#hot + 1] = {
				itemID = item.itemID,
				name = item.name,
				quality = item.quality,
				soldPerDay = stats.soldPerDay,
				market = stats.market,
				volume = math.floor(stats.soldPerDay * stats.market),
				qty = stats.qty,
			}
		end

		local reasons = L.AvoidReasons(stats)
		if #reasons > 0 then
			avoid[#avoid + 1] = {
				itemID = item.itemID,
				name = item.name,
				quality = item.quality,
				reasons = reasons,
				market = stats.market,
				qty = stats.qty,
				cv = stats.cv,
				supply = stats.supply,
				change = stats.change,
			}
		end
	end

	table.sort(deals, function(a, b)
		if a.profit ~= b.profit then
			return a.profit > b.profit
		end
		return byItemID(a, b)
	end)

	table.sort(movers, function(a, b)
		local ac, bc = math.abs(a.change), math.abs(b.change)
		if ac ~= bc then
			return ac > bc
		end
		return byItemID(a, b)
	end)

	table.sort(hot, function(a, b)
		if a.volume ~= b.volume then
			return a.volume > b.volume
		end
		return byItemID(a, b)
	end)

	table.sort(avoid, function(a, b)
		if #a.reasons ~= #b.reasons then
			return #a.reasons > #b.reasons
		end
		if a.market ~= b.market then
			return a.market > b.market
		end
		return byItemID(a, b)
	end)

	return {
		deals = cap(deals),
		movers = cap(movers),
		hot = cap(hot),
		avoid = cap(avoid),
		prices = prices,
	}
end

function L.FormatMoney(copper)
	if type(copper) ~= "number" then
		return "-"
	end
	local negative = copper < 0
	local n = math.floor(math.abs(copper))
	if n == 0 then
		return "0c"
	end
	local gold = math.floor(n / 10000)
	local silver = math.floor(n % 10000 / 100)
	local c = n % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = gold .. "g"
	end
	if silver > 0 then
		parts[#parts + 1] = silver .. "s"
	end
	if c > 0 then
		parts[#parts + 1] = c .. "c"
	end
	local text = table.concat(parts, " ")
	return negative and ("-" .. text) or text
end

function L.FormatPercent(p)
	if type(p) ~= "number" then
		return "-"
	end
	local rounded = p >= 0 and math.floor(p + 0.5) or -math.floor(-p + 0.5)
	if rounded == 0 then
		return "0%"
	elseif rounded > 0 then
		return "+" .. rounded .. "%"
	end
	return rounded .. "%"
end

function L.FormatDuration(s)
	if type(s) ~= "number" or s <= 0 then
		return "0s"
	end
	s = math.floor(s)
	if s < 60 then
		return s .. "s"
	elseif s < 3600 then
		return math.floor(s / 60) .. "m"
	elseif s < 86400 then
		local h = math.floor(s / 3600)
		local m = math.floor((s % 3600) / 60)
		return m > 0 and (h .. "h " .. m .. "m") or (h .. "h")
	end
	local d = math.floor(s / 86400)
	local h = math.floor((s % 86400) / 3600)
	return h > 0 and (d .. "d " .. h .. "h") or (d .. "d")
end
