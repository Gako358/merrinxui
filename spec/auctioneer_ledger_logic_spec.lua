describe("AuctioneerLedgerLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/AuctioneerLedgerLogic.lua"))("MerrinxUI", ns)
		L = ns.AuctioneerLedgerLogic
	end)

	local K1 = "buyer|Linen Cloth|Bob|2000|2000|0|0|20"
	local K2 = "seller|Copper Ore|Ann|5000|5000|100|250|5"

	local function inv1()
		return {
			type = "buyer",
			item = "Linen Cloth",
			player = "Bob",
			bid = 2000,
			buyout = 2000,
			deposit = 0,
			consignment = 0,
			count = 20,
			daysLeft = 29.5,
		}
	end

	local function inv2()
		return {
			type = "seller",
			item = "Copper Ore",
			player = "Ann",
			bid = 5000,
			buyout = 5000,
			deposit = 100,
			consignment = 250,
			count = 5,
			daysLeft = 30,
		}
	end

	local function inv3()
		return {
			type = "buyer",
			item = "Copper Bar",
			player = nil,
			bid = 600,
			buyout = 600,
			deposit = 0,
			consignment = 0,
			count = 10,
			daysLeft = 30,
		}
	end

	describe("InvoiceKey", function()
		it("D10: joins fields with |, defaulting a nil player to empty", function()
			assert.are.equal("buyer|Copper Bar||600|600|0|0|10", L.InvoiceKey(inv3()))
		end)
	end)

	describe("Diff", function()
		it("D1 to D3: fresh invoices become seen entries that survive reopens and temporary absence", function()
			local seen = {}
			local temp = inv2()
			temp.type = "seller_temp_invoice"
			local bad = inv1()
			bad.count = nil

			local fresh, skipped, drift = L.Diff({ inv1(), inv2(), temp, bad }, seen, 1000000)
			assert.are.equal(2, #fresh)
			assert.are.equal("buyer", fresh[1].type)
			assert.are.equal(3548800, fresh[1].e)
			assert.are.equal(K1, fresh[1].k)
			assert.are.equal("seller", fresh[2].type)
			assert.are.equal(3592000, fresh[2].e)
			assert.are.equal(K2, fresh[2].k)
			assert.are.equal(1, skipped)
			assert.are.equal(0, drift)
			assert.are.same({ { k = K1, e = 3548800 }, { k = K2, e = 3592000 } }, seen)

			fresh, skipped, drift = L.Diff({ inv1(), inv2(), bad }, seen, 1000600)
			assert.are.same({}, fresh)
			assert.are.equal(1, skipped)
			assert.are.equal(600, drift)
			assert.are.equal(2, #seen)

			fresh = L.Diff({ inv2() }, seen, 1000000)
			assert.are.same({}, fresh)
			fresh = L.Diff({ inv1(), inv2() }, seen, 1000000)
			assert.are.same({}, fresh)
		end)

		it("D4: two identical fresh invoices in one inbox both become separate entries", function()
			local seen = {}
			local fresh = L.Diff({ inv1(), inv1() }, seen, 1000000)
			assert.are.equal(2, #fresh)
			assert.are.equal(2, #seen)
		end)

		it("D5: a duplicate only matches the one existing seen entry once", function()
			local seen = { { k = K1, e = 3548800 } }
			local fresh = L.Diff({ inv1(), inv1() }, seen, 1000000)
			assert.are.equal(1, #fresh)
			assert.are.equal(2, #seen)
		end)

		it("D6: a gap beyond the tolerance does not match", function()
			local seen = { { k = K1, e = 3548800 } }
			local late = inv1()
			late.daysLeft = 29.75
			local fresh = L.Diff({ late }, seen, 1000000)
			assert.are.equal(1, #fresh)
		end)

		it("D7: pruning drops a seen entry exactly at the tolerance boundary", function()
			local seen = { { k = K1, e = 3548800 }, { k = K2, e = 3592000 } }
			L.Diff({}, seen, 3552401)
			assert.are.same({ { k = K2, e = 3592000 } }, seen)
		end)

		it("D8: invoices of other types are ignored, not skipped", function()
			local temp = inv2()
			temp.type = "seller_temp_invoice"
			local other = inv1()
			other.type = nil
			local seen = {}
			local fresh, skipped = L.Diff({ temp, other }, seen, 1000000)
			assert.are.same({}, fresh)
			assert.are.equal(0, skipped)
		end)

		it("D9: the nearest seen entry wins when two are within tolerance", function()
			local seen = { { k = K1, e = 3545800 }, { k = K1, e = 3549800 } }
			local fresh, _, drift = L.Diff({ inv1() }, seen, 1000000)
			assert.are.same({}, fresh)
			assert.are.equal(1000, drift)
		end)
	end)

	describe("Record", function()
		it("R1: records fresh buyer and seller invoices into an empty book", function()
			local seen = {}
			local fresh = L.Diff({ inv1(), inv2() }, seen, 1000000)
			local book = { lots = {}, sales = {} }
			local buys, sells = L.Record(book, fresh, 1000000)
			assert.are.equal(1, buys)
			assert.are.equal(1, sells)
			assert.are.same({ { t = 1000000, qty = 20, cost = 2000 } }, book.lots["Linen Cloth"])
			assert.are.same({ { t = 1000000, item = "Copper Ore", qty = 5, net = 4750, cost = 0 } }, book.sales)
		end)
	end)

	describe("Apply", function()
		it("F1 to F8: takes FIFO cost basis across whole and partial lots", function()
			local book = { lots = {}, sales = {} }

			L.Apply(book, { t = 100, kind = "buy", item = "Ore", qty = 10, amount = 1000 })
			L.Apply(book, { t = 200, kind = "buy", item = "Ore", qty = 10, amount = 1500 })
			L.Apply(book, { t = 300, kind = "sell", item = "Ore", qty = 15, amount = 3000 })
			assert.are.same({ { t = 200, qty = 5, cost = 750 } }, book.lots.Ore)
			assert.are.same({ t = 300, item = "Ore", qty = 15, net = 3000, cost = 1750 }, book.sales[#book.sales])

			L.Apply(book, { t = 400, kind = "sell", item = "Ore", qty = 8, amount = 2000 })
			assert.is_nil(book.lots.Ore)
			assert.are.same({ t = 400, item = "Ore", qty = 8, net = 2000, cost = 750 }, book.sales[#book.sales])

			L.Apply(book, { t = 500, kind = "sell", item = "Herb", qty = 3, amount = 600 })
			assert.are.same({ t = 500, item = "Herb", qty = 3, net = 600, cost = 0 }, book.sales[#book.sales])

			L.Apply(book, { t = 600, kind = "buy", item = "Silk", qty = 3, amount = 100 })
			L.Apply(book, { t = 700, kind = "sell", item = "Silk", qty = 1, amount = 50 })
			assert.are.same({ { t = 600, qty = 2, cost = 67 } }, book.lots.Silk)
			assert.are.same({ t = 700, item = "Silk", qty = 1, net = 50, cost = 33 }, book.sales[#book.sales])

			L.Apply(book, { t = 800, kind = "sell", item = "Silk", qty = 2, amount = 100 })
			assert.is_nil(book.lots.Silk)
			assert.are.same({ t = 800, item = "Silk", qty = 2, net = 100, cost = 67 }, book.sales[#book.sales])
		end)
	end)

	describe("Prune", function()
		it("PR1: drops sales and lots at or before the 30-day cutoff, and empty lot lists", function()
			local book = {
				lots = {
					Old = { { t = 864000, qty = 1, cost = 1 } },
					New = { { t = 864001, qty = 2, cost = 2 } },
					Mix = { { t = 864000, qty = 1, cost = 1 }, { t = 864001, qty = 1, cost = 1 } },
				},
				sales = {
					{ t = 864000, item = "A", qty = 1, net = 1, cost = 0 },
					{ t = 864001, item = "B", qty = 1, net = 1, cost = 0 },
				},
			}

			L.Prune(book, 3456000)

			assert.is_nil(book.lots.Old)
			assert.are.same({ { t = 864001, qty = 2, cost = 2 } }, book.lots.New)
			assert.are.same({ { t = 864001, qty = 1, cost = 1 } }, book.lots.Mix)
			assert.are.same({ { t = 864001, item = "B", qty = 1, net = 1, cost = 0 } }, book.sales)
		end)
	end)

	describe("Realised and Portfolio", function()
		it("PF1: builds per-item rows with FIFO cost basis, unrealised and realised profit", function()
			local book = {
				lots = {
					Silk = { { t = 3024000, qty = 4, cost = 400 } },
					Wool = { { t = 3283200, qty = 10, cost = 300 }, { t = 3369600, qty = 10, cost = 500 } },
					Rune = { { t = 3452400, qty = 1, cost = 10 } },
				},
				sales = {
					{ t = 3452400, item = "Ore", qty = 15, net = 3000, cost = 1750 },
					{ t = 3196800, item = "Ore", qty = 8, net = 2000, cost = 750 },
					{ t = 2592000, item = "Silk", qty = 1, net = 50, cost = 100 },
					{ t = 777600, item = "Silk", qty = 1, net = 999, cost = 0 },
					{ t = 777600, item = "Gold Bar", qty = 1, net = 500, cost = 0 },
				},
			}
			local lookup = {
				Silk = { itemID = 4306, quality = 1, market = 150 },
				Wool = { itemID = 2592, quality = 1, market = 60 },
				Ore = { itemID = 2770, quality = nil, market = 200 },
			}
			local now = 3456000

			assert.are.same({ [1] = 1250, [7] = 2500, [30] = 2450 }, L.Realised(book, now))

			local p = L.Portfolio(book, lookup, 5, now)
			assert.are.equal(4, #p.rows)
			assert.are.equal(1210, p.cost)
			assert.are.equal(510, p.unrealised)
			assert.are.same({ [1] = 1250, [7] = 2500, [30] = 2450 }, p.realised)

			local names = {}
			for i, row in ipairs(p.rows) do
				names[i] = row.name
			end
			assert.are.same({ "Ore", "Wool", "Silk", "Rune" }, names)

			assert.are.same({
				name = "Ore",
				itemID = 2770,
				quality = nil,
				held = 0,
				cost = 0,
				unitCost = nil,
				market = 200,
				unrealised = nil,
				realised = 2500,
			}, p.rows[1])
			assert.are.same({
				name = "Wool",
				itemID = 2592,
				quality = 1,
				held = 20,
				cost = 800,
				unitCost = 40,
				market = 60,
				unrealised = 340,
				realised = 0,
			}, p.rows[2])
			assert.are.same({
				name = "Silk",
				itemID = 4306,
				quality = 1,
				held = 4,
				cost = 400,
				unitCost = 100,
				market = 150,
				unrealised = 170,
				realised = -50,
			}, p.rows[3])
			assert.are.same({
				name = "Rune",
				itemID = nil,
				quality = nil,
				held = 1,
				cost = 10,
				unitCost = 10,
				market = nil,
				unrealised = nil,
				realised = 0,
			}, p.rows[4])
		end)
	end)
end)
