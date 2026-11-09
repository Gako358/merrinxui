local addonName, ns = ...

local AuctioneerTradeLogic = {}
ns.AuctioneerTradeLogic = AuctioneerTradeLogic

local L = AuctioneerTradeLogic

L.FLOOR_PCT = 70
L.UNDERCUT = 1
L.ADVICE = {
	undercut = "Undercut",
	market = "Market",
	cost = "Break even",
	vendor = "Vendor",
	no_data = "No data",
}

local function byMarginProfitItemID(a, b)
	if a.margin ~= b.margin then
		return a.margin > b.margin
	end
	if a.profit ~= b.profit then
		return a.profit > b.profit
	end
	return a.itemID < b.itemID
end

local function walkListings(listings, unitCap, limit)
	local qty, cost, auctions, unitMax = 0, 0, 0, nil
	for _, listing in ipairs(listings) do
		for _ = 1, listing.n do
			if qty + listing.count > unitCap or cost + listing.buyout > limit then
				return qty, cost, auctions, unitMax
			end
			qty = qty + listing.count
			cost = cost + listing.buyout
			auctions = auctions + 1
			unitMax = math.floor(listing.buyout / listing.count)
		end
	end
	return qty, cost, auctions, unitMax
end

local function unitCapFor(deal, settings, held)
	if deal.kind == "vendor" then
		return math.huge
	end
	if deal.soldPerDay == nil then
		return (held > 0 or #deal.listings == 0) and 0 or deal.listings[1].count
	end
	return math.max(0, math.ceil(deal.soldPerDay * settings.sellDays) - held)
end

function L.Plan(deals, settings)
	local order = {}
	for i, deal in ipairs(deals) do
		order[i] = deal
	end
	table.sort(order, byMarginProfitItemID)

	local itemCap = math.floor(settings.budget * settings.maxShare / 100)
	local remaining = settings.budget
	local rows, unfunded, profit = {}, 0, 0

	for _, deal in ipairs(order) do
		local limit = math.min(remaining, itemCap)
		local held = (settings.held and deal.name and settings.held[deal.name]) or 0
		local unitCap = unitCapFor(deal, settings, held)

		local qty, cost, auctions, unitMax = walkListings(deal.listings, unitCap, limit)
		local rowProfit = qty * deal.net - cost
		if qty > 0 and rowProfit > 0 and rowProfit >= settings.minProfit then
			rows[#rows + 1] = {
				kind = deal.kind,
				itemID = deal.itemID,
				name = deal.name,
				quality = deal.quality,
				qty = qty,
				auctions = auctions,
				cost = cost,
				unitMax = unitMax,
				sellUnit = deal.sellUnit,
				profit = rowProfit,
				margin = math.floor(rowProfit * 100 / cost),
				soldPerDay = deal.soldPerDay,
				rateKnown = deal.soldPerDay ~= nil,
			}
			remaining = remaining - cost
			profit = profit + rowProfit
		else
			unfunded = unfunded + 1
		end
	end

	return {
		rows = rows,
		budget = settings.budget,
		spent = settings.budget - remaining,
		profit = profit,
		unfunded = unfunded,
	}
end

function L.SellPrice(market, min, vendor, cost, cutPct)
	if market == nil and min == nil then
		if vendor ~= nil and vendor > 0 then
			return vendor, "vendor", vendor
		end
		return nil, "no_data", nil
	end

	local ref = market or min
	local keep = 100 - cutPct

	local costFloor = cost and math.ceil(cost * 100 / keep) or 0
	local vendorFloor = (vendor and vendor > 0) and math.ceil(vendor * 100 / keep) or 0
	local floor = math.max(math.ceil(ref * L.FLOOR_PCT / 100), costFloor, vendorFloor)

	local price, advice
	if min ~= nil and min - L.UNDERCUT >= floor then
		price, advice = min - L.UNDERCUT, "undercut"
	elseif vendorFloor > ref and vendorFloor >= costFloor then
		price, advice = vendor, "vendor"
	elseif costFloor > ref then
		price, advice = costFloor, "cost"
	else
		price, advice = ref, "market"
	end

	local net = advice == "vendor" and vendor or math.floor(price * keep / 100)
	return price, advice, net
end

function L.SellRows(bag, prices, costByName, cutPct)
	local rows = {}
	for _, item in ipairs(bag) do
		local p = prices[item.itemID]
		if p and (p.market ~= nil or p.min ~= nil) then
			local name = item.name or p.name
			local cost = name and costByName[name] or nil
			local price, advice, net = L.SellPrice(p.market, p.min, p.vendor, cost, cutPct)
			rows[#rows + 1] = {
				itemID = item.itemID,
				name = name,
				quality = item.quality or p.quality,
				qty = item.count,
				price = price,
				advice = advice,
				net = net,
				value = net * item.count,
				cost = cost,
				profit = cost and (net - cost) * item.count or nil,
			}
		end
	end

	table.sort(rows, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.itemID < b.itemID
	end)

	return rows
end
