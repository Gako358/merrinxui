local addonName, ns = ...

local AuctioneerLedgerLogic = {}
ns.AuctioneerLedgerLogic = AuctioneerLedgerLogic

local L = AuctioneerLedgerLogic

L.DAY = 86400
L.KEEP_DAYS = 30
L.MATCH_TOL = 3600
L.WINDOWS = { 1, 7, 30 }

local function isNonEmptyString(v)
	return type(v) == "string" and v ~= ""
end

local function isIntAtLeast(v, min)
	return type(v) == "number" and v >= min and v == math.floor(v)
end

function L.InvoiceKey(inv)
	return string.format(
		"%s|%s|%s|%d|%d|%d|%d|%d",
		inv.type,
		inv.item,
		inv.player or "",
		inv.bid,
		inv.buyout,
		inv.deposit,
		inv.consignment,
		inv.count
	)
end

function L.Diff(inbox, seen, now)
	local i = #seen
	while i >= 1 do
		if seen[i].e < now - L.MATCH_TOL then
			table.remove(seen, i)
		end
		i = i - 1
	end

	local used = {}
	local fresh, skipped, drift = {}, 0, 0

	for _, entry in ipairs(inbox) do
		if entry.type == "buyer" or entry.type == "seller" then
			local valid = isNonEmptyString(entry.item)
				and (entry.player == nil or type(entry.player) == "string")
				and isIntAtLeast(entry.bid, 0)
				and isIntAtLeast(entry.buyout, 0)
				and isIntAtLeast(entry.deposit, 0)
				and isIntAtLeast(entry.consignment, 0)
				and isIntAtLeast(entry.count, 1)
				and type(entry.daysLeft) == "number"
				and entry.daysLeft >= 0

			if valid then
				local inv = {
					type = entry.type,
					item = entry.item,
					player = entry.player or "",
					bid = entry.bid,
					buyout = entry.buyout,
					deposit = entry.deposit,
					consignment = entry.consignment,
					count = entry.count,
					e = now + math.floor(entry.daysLeft * L.DAY),
				}
				inv.k = L.InvoiceKey(inv)

				local match, bestDiff = nil, nil
				for _, s in ipairs(seen) do
					if not used[s] and s.k == inv.k then
						local diff = math.abs(inv.e - s.e)
						if diff <= L.MATCH_TOL and (bestDiff == nil or diff < bestDiff) then
							match, bestDiff = s, diff
						end
					end
				end

				if match then
					used[match] = true
					drift = math.max(drift, bestDiff)
				else
					fresh[#fresh + 1] = inv
					local newEntry = { k = inv.k, e = inv.e }
					seen[#seen + 1] = newEntry
					used[newEntry] = true
				end
			else
				skipped = skipped + 1
			end
		end
	end

	return fresh, skipped, drift
end

function L.Apply(book, tx)
	if tx.kind == "buy" then
		local lots = book.lots[tx.item]
		if not lots then
			lots = {}
			book.lots[tx.item] = lots
		end
		lots[#lots + 1] = { t = tx.t, qty = tx.qty, cost = tx.amount }
	else
		local remaining = tx.qty
		local basis = 0
		local lots = book.lots[tx.item]
		if lots then
			while remaining > 0 and #lots > 0 do
				local lot = lots[1]
				if lot.qty <= remaining then
					basis = basis + lot.cost
					remaining = remaining - lot.qty
					table.remove(lots, 1)
				else
					local take = remaining
					local part = math.floor(lot.cost * take / lot.qty)
					basis = basis + part
					lot.qty = lot.qty - take
					lot.cost = lot.cost - part
					remaining = 0
				end
			end
			if #lots == 0 then
				book.lots[tx.item] = nil
			end
		end
		local sales = book.sales
		sales[#sales + 1] = { t = tx.t, item = tx.item, qty = tx.qty, net = tx.amount, cost = basis }
	end
	return book
end

function L.Record(book, fresh, now)
	local buys, sells = 0, 0
	for _, inv in ipairs(fresh) do
		if inv.type == "buyer" then
			L.Apply(book, { t = now, kind = "buy", item = inv.item, qty = inv.count, amount = inv.bid })
			buys = buys + 1
		elseif inv.type == "seller" then
			L.Apply(
				book,
				{ t = now, kind = "sell", item = inv.item, qty = inv.count, amount = inv.bid - inv.consignment }
			)
			sells = sells + 1
		end
	end
	return buys, sells
end

function L.Prune(book, now)
	local cutoff = now - L.KEEP_DAYS * L.DAY

	for item, lots in pairs(book.lots) do
		local i = 1
		while i <= #lots do
			if lots[i].t <= cutoff then
				table.remove(lots, i)
			else
				i = i + 1
			end
		end
		if #lots == 0 then
			book.lots[item] = nil
		end
	end

	local sales = book.sales
	local i = 1
	while i <= #sales do
		if sales[i].t <= cutoff then
			table.remove(sales, i)
		else
			i = i + 1
		end
	end

	return book
end

function L.Realised(book, now)
	local result = {}
	for _, d in ipairs(L.WINDOWS) do
		local sum = 0
		for _, sale in ipairs(book.sales) do
			if sale.t > now - d * L.DAY then
				sum = sum + (sale.net - sale.cost)
			end
		end
		result[d] = sum
	end
	return result
end

function L.Portfolio(book, lookup, cutPct, now)
	local cutoff30 = now - 30 * L.DAY
	local names, present = {}, {}

	for name in pairs(book.lots) do
		if not present[name] then
			present[name] = true
			names[#names + 1] = name
		end
	end
	for _, sale in ipairs(book.sales) do
		if sale.t > cutoff30 and not present[sale.item] then
			present[sale.item] = true
			names[#names + 1] = sale.item
		end
	end

	local rows = {}
	for _, name in ipairs(names) do
		local lots = book.lots[name]
		local held, cost = 0, 0
		if lots then
			for _, lot in ipairs(lots) do
				held = held + lot.qty
				cost = cost + lot.cost
			end
		end

		local info = lookup[name]
		local market = info and info.market

		local realised = 0
		for _, sale in ipairs(book.sales) do
			if sale.item == name and sale.t > cutoff30 then
				realised = realised + (sale.net - sale.cost)
			end
		end

		rows[#rows + 1] = {
			name = name,
			itemID = info and info.itemID,
			quality = info and info.quality,
			held = held,
			cost = cost,
			unitCost = held > 0 and math.ceil(cost / held) or nil,
			market = market,
			unrealised = (held > 0 and market) and (math.floor(market * held * (100 - cutPct) / 100) - cost) or nil,
			realised = realised,
		}
	end

	table.sort(rows, function(a, b)
		local av = a.realised + (a.unrealised or 0)
		local bv = b.realised + (b.unrealised or 0)
		if av ~= bv then
			return av > bv
		end
		return a.name < b.name
	end)

	local cost, unrealised = 0, 0
	for _, row in ipairs(rows) do
		cost = cost + row.cost
		if row.unrealised ~= nil then
			unrealised = unrealised + row.unrealised
		end
	end

	return { rows = rows, cost = cost, unrealised = unrealised, realised = L.Realised(book, now) }
end
