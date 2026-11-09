describe("AuctioneerTradeLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/AuctioneerTradeLogic.lua"))("MerrinxUI", ns)
		L = ns.AuctioneerTradeLogic
	end)

	local function clone(deal, overrides)
		local copy = {}
		for k, v in pairs(deal) do
			copy[k] = v
		end
		for k, v in pairs(overrides or {}) do
			copy[k] = v
		end
		return copy
	end

	local F = {
		kind = "flip",
		itemID = 10,
		name = "Thorium Ore",
		quality = nil,
		qty = 12,
		cost = 680,
		unitMax = 60,
		sellUnit = 106,
		net = 100,
		profit = 520,
		margin = 76,
		soldPerDay = 2,
		listings = {
			{ buyout = 50, count = 1, n = 4 },
			{ buyout = 240, count = 4, n = 2 },
		},
	}

	local U = {
		kind = "flip",
		itemID = 30,
		name = "Black Lotus",
		quality = nil,
		qty = 15,
		cost = 9000,
		unitMax = 600,
		sellUnit = 1053,
		net = 1000,
		profit = 6000,
		margin = 66,
		soldPerDay = nil,
		listings = {
			{ buyout = 3000, count = 5, n = 3 },
		},
	}

	local V = {
		kind = "vendor",
		itemID = 20,
		name = "Light Leather",
		quality = nil,
		qty = 50,
		cost = 1000,
		unitMax = 20,
		sellUnit = 30,
		net = 30,
		profit = 500,
		margin = 50,
		soldPerDay = nil,
		listings = {
			{ buyout = 20, count = 1, n = 50 },
		},
	}

	describe("Plan", function()
		it("P1: splits a 50% item cap across three deals ranked by margin", function()
			local result = L.Plan({ V, F, U }, { budget = 10000, maxShare = 50, sellDays = 3, minProfit = 100 })
			assert.are.same({
				{
					kind = "flip",
					itemID = 10,
					name = "Thorium Ore",
					quality = nil,
					qty = 4,
					auctions = 4,
					cost = 200,
					unitMax = 50,
					sellUnit = 106,
					profit = 200,
					margin = 100,
					soldPerDay = 2,
					rateKnown = true,
				},
				{
					kind = "flip",
					itemID = 30,
					name = "Black Lotus",
					quality = nil,
					qty = 5,
					auctions = 1,
					cost = 3000,
					unitMax = 600,
					sellUnit = 1053,
					profit = 2000,
					margin = 66,
					soldPerDay = nil,
					rateKnown = false,
				},
				{
					kind = "vendor",
					itemID = 20,
					name = "Light Leather",
					quality = nil,
					qty = 50,
					auctions = 50,
					cost = 1000,
					unitMax = 20,
					sellUnit = 30,
					profit = 500,
					margin = 50,
					soldPerDay = nil,
					rateKnown = false,
				},
			}, result.rows)
			assert.are.equal(10000, result.budget)
			assert.are.equal(4200, result.spent)
			assert.are.equal(2700, result.profit)
			assert.are.equal(0, result.unfunded)
		end)

		it("P2: a full-share budget still buys down to the limit", function()
			local result = L.Plan({ V, F, U }, { budget = 3500, maxShare = 100, sellDays = 3, minProfit = 100 })
			assert.are.equal(3, #result.rows)
			assert.are.equal(200, result.rows[1].cost)
			assert.are.equal(3000, result.rows[2].cost)
			assert.are.equal(300, result.rows[3].cost)
			assert.are.equal(15, result.rows[3].qty)
			assert.are.equal(150, result.rows[3].profit)
			assert.are.equal(50, result.rows[3].margin)
			assert.are.equal(3500, result.spent)
			assert.are.equal(2350, result.profit)
			assert.are.equal(0, result.unfunded)
		end)

		it("P3: a minProfit floor drops deals that do not clear it", function()
			local result = L.Plan({ V, F, U }, { budget = 2000, maxShare = 100, sellDays = 3, minProfit = 300 })
			assert.are.equal(1, #result.rows)
			assert.are.equal(20, result.rows[1].itemID)
			assert.are.equal(1000, result.spent)
			assert.are.equal(500, result.profit)
			assert.are.equal(2, result.unfunded)
		end)

		it("P4: a longer sellDays widens the unit cap", function()
			local result = L.Plan({ F }, { budget = 10000, maxShare = 100, sellDays = 5, minProfit = 0 })
			assert.are.equal(1, #result.rows)
			assert.are.same({
				kind = "flip",
				itemID = 10,
				name = "Thorium Ore",
				quality = nil,
				qty = 8,
				auctions = 5,
				cost = 440,
				unitMax = 60,
				sellUnit = 106,
				profit = 360,
				margin = 81,
				soldPerDay = 2,
				rateKnown = true,
			}, result.rows[1])
		end)

		it("P5: a known sell rate of zero buys nothing", function()
			local f0 = clone(F, { soldPerDay = 0 })
			local result = L.Plan({ f0 }, { budget = 10000, maxShare = 100, sellDays = 3, minProfit = 0 })
			assert.are.same({}, result.rows)
			assert.are.equal(1, result.unfunded)
		end)

		it("P6: a zero budget funds nothing", function()
			local result = L.Plan({ F, U, V }, { budget = 0, maxShare = 25, sellDays = 3, minProfit = 0 })
			assert.are.same({}, result.rows)
			assert.are.equal(0, result.spent)
			assert.are.equal(0, result.profit)
			assert.are.equal(3, result.unfunded)
		end)

		it("P7: ties break on itemID without mutating the input order", function()
			local v2 = clone(V, { itemID = 21 })
			local deals = { v2, V }
			local result = L.Plan(deals, { budget = 100000, maxShare = 100, sellDays = 3, minProfit = 0 })
			assert.are.equal(20, result.rows[1].itemID)
			assert.are.equal(21, result.rows[2].itemID)
			assert.are.equal(21, deals[1].itemID)
		end)

		it("P8: held units reduce a known rate cap and zero out an unknown one", function()
			local result = L.Plan({ F, U }, {
				budget = 10000,
				maxShare = 100,
				sellDays = 3,
				minProfit = 0,
				held = { ["Thorium Ore"] = 3, ["Black Lotus"] = 1 },
			})
			assert.are.same({
				{
					kind = "flip",
					itemID = 10,
					name = "Thorium Ore",
					quality = nil,
					qty = 3,
					auctions = 3,
					cost = 150,
					unitMax = 50,
					sellUnit = 106,
					profit = 150,
					margin = 100,
					soldPerDay = 2,
					rateKnown = true,
				},
			}, result.rows)
			assert.are.equal(150, result.spent)
			assert.are.equal(150, result.profit)
			assert.are.equal(1, result.unfunded)
		end)
	end)

	describe("SellPrice", function()
		it("S1: undercuts when min clears the discount floor", function()
			local price, advice, net = L.SellPrice(1000, 900, nil, nil, 5)
			assert.are.equal(899, price)
			assert.are.equal("undercut", advice)
			assert.are.equal(854, net)
		end)

		it("S2: falls back to market when min is below the discount floor", function()
			local price, advice, net = L.SellPrice(1000, 600, nil, nil, 5)
			assert.are.equal(1000, price)
			assert.are.equal("market", advice)
			assert.are.equal(950, net)
		end)

		it("S3: market wins when the cost floor is still under it", function()
			local price, advice, net = L.SellPrice(1000, 900, nil, 900, 5)
			assert.are.equal(1000, price)
			assert.are.equal("market", advice)
			assert.are.equal(950, net)
		end)

		it("S4: undercuts above a cost floor that clears min", function()
			local price, advice, net = L.SellPrice(1000, 1100, nil, 1000, 5)
			assert.are.equal(1099, price)
			assert.are.equal("undercut", advice)
			assert.are.equal(1044, net)
		end)

		it("S4b: posts at the cost floor when min cannot clear it", function()
			local price, advice, net = L.SellPrice(1000, 1000, nil, 1000, 5)
			assert.are.equal(1053, price)
			assert.are.equal("cost", advice)
			assert.are.equal(1000, net)
		end)

		it("S5: posts at vendor when the vendor floor beats market and min", function()
			local price, advice, net = L.SellPrice(100, 100, 98, nil, 5)
			assert.are.equal(98, price)
			assert.are.equal("vendor", advice)
			assert.are.equal(98, net)
		end)

		it("S6: falls back to market with no min at all", function()
			local price, advice, net = L.SellPrice(500, nil, nil, nil, 5)
			assert.are.equal(500, price)
			assert.are.equal("market", advice)
			assert.are.equal(475, net)
		end)

		it("S7: uses min as the reference when market is unknown", function()
			local price, advice, net = L.SellPrice(nil, 200, nil, nil, 5)
			assert.are.equal(199, price)
			assert.are.equal("undercut", advice)
			assert.are.equal(189, net)
		end)

		it("S8: posts at vendor when market and min are both unknown", function()
			local price, advice, net = L.SellPrice(nil, nil, 25, nil, 5)
			assert.are.equal(25, price)
			assert.are.equal("vendor", advice)
			assert.are.equal(25, net)
		end)

		it("S9: has no data when nothing is known", function()
			local price, advice, net = L.SellPrice(nil, nil, nil, nil, 5)
			assert.is_nil(price)
			assert.are.equal("no_data", advice)
			assert.is_nil(net)
		end)

		it("S10: a higher cut percent raises the cost floor", function()
			local price, advice, net = L.SellPrice(1000, 900, nil, 800, 15)
			assert.are.equal(1000, price)
			assert.are.equal("market", advice)
			assert.are.equal(850, net)
		end)

		it("S11: a zero vendor price counts as no vendor price", function()
			local price, advice, net = L.SellPrice(100, 100, 0, nil, 5)
			assert.are.equal(99, price)
			assert.are.equal("undercut", advice)
			assert.are.equal(94, net)
		end)
	end)

	describe("SellRows", function()
		it("SR1: skips bag items with no usable price and sorts the rest by value", function()
			local bag = {
				{ itemID = 1, name = "Linen Cloth", quality = 1, count = 20 },
				{ itemID = 2, name = "Copper Ore", quality = 1, count = 5 },
				{ itemID = 3, name = "Junk", count = 3 },
				{ itemID = 4, name = "Rock", count = 2 },
			}
			local prices = {
				[1] = { market = 100, min = 90, vendor = 10 },
				[2] = { market = 1000, min = 600 },
				[4] = { vendor = 5 },
			}
			local costByName = { ["Copper Ore"] = 900 }
			local rows = L.SellRows(bag, prices, costByName, 5)
			assert.are.same({
				{
					itemID = 2,
					name = "Copper Ore",
					quality = 1,
					qty = 5,
					price = 1000,
					advice = "market",
					net = 950,
					value = 4750,
					cost = 900,
					profit = 250,
				},
				{
					itemID = 1,
					name = "Linen Cloth",
					quality = 1,
					qty = 20,
					price = 89,
					advice = "undercut",
					net = 84,
					value = 1680,
					cost = nil,
					profit = nil,
				},
			}, rows)
		end)
	end)
end)
