describe("AuctioneerLogic", function()
	local L
	local TODAY = 20260

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/AuctioneerLogic.lua"))("MerrinxUI", ns)
		L = ns.AuctioneerLogic
	end)

	local itemA = {
		itemID = 1,
		history = {
			{ day = 20253, min = 450, med = 500, qty = 10, sold = 0, obs = 0, scans = 1 },
			{ day = 20254, min = 90, med = 100, qty = 40, sold = 4, obs = 1, scans = 1 },
			{ day = 20255, min = 0, med = 0, qty = 20, sold = 0, obs = 1, scans = 1 },
			{ day = 20258, min = 110, med = 120, qty = 30, sold = 6, obs = 2, scans = 2 },
			{ day = 20259, min = 100, med = 110, qty = 30, sold = 0, obs = 0, scans = 1 },
			{ day = 20260, min = 85, med = 90, qty = 75, sold = 2, obs = 1, scans = 1 },
		},
		listings = { { buyout = 450, count = 5, n = 15 } },
	}

	local itemB = {
		itemID = 2,
		history = {
			{ day = 20257, min = 1000, med = 1000, qty = 10, sold = 0, obs = 0, scans = 1 },
			{ day = 20258, min = 1000, med = 1000, qty = 10, sold = 0, obs = 0, scans = 1 },
			{ day = 20259, min = 1000, med = 1000, qty = 10, sold = 0, obs = 0, scans = 1 },
			{ day = 20260, min = 1500, med = 1500, qty = 10, sold = 0, obs = 0, scans = 1 },
		},
		listings = { { buyout = 1500, count = 1, n = 10 } },
	}

	local itemC = {
		itemID = 3,
		history = {
			{ day = 20258, min = 900, med = 1000, qty = 10, sold = 5, obs = 1, scans = 1 },
			{ day = 20259, min = 900, med = 1000, qty = 10, sold = 5, obs = 1, scans = 1 },
			{ day = 20260, min = 900, med = 1000, qty = 10, sold = 5, obs = 1, scans = 1 },
		},
		listings = {
			{ buyout = 600, count = 1, n = 2 },
			{ buyout = 6500, count = 10, n = 1 },
			{ buyout = 800, count = 1, n = 5 },
		},
	}

	local itemD = {
		itemID = 4,
		vendor = 50,
		history = {},
		listings = {
			{ buyout = 30, count = 1, n = 4 },
			{ buyout = 200, count = 5, n = 1 },
			{ buyout = 60, count = 1, n = 1 },
		},
	}

	local itemE = {
		itemID = 5,
		history = {
			{ day = 20258, min = 100, med = 100, qty = 10, sold = 0, obs = 1, scans = 1 },
			{ day = 20259, min = 300, med = 300, qty = 10, sold = 0, obs = 1, scans = 1 },
			{ day = 20260, min = 100, med = 100, qty = 10, sold = 0, obs = 1, scans = 1 },
		},
		listings = { { buyout = 100, count = 1, n = 10 } },
	}

	local settings = { discount = 0.30, cut = 0.05, minProfit = 100 }

	describe("Stats", function()
		it("computes fixture A (falling and flooded)", function()
			local stats = L.Stats(itemA, TODAY)
			assert.are.equal(105, stats.market)
			assert.are.equal(4, stats.days)
			assert.near(0.1065, stats.cv, 1e-4)
			assert.are.equal(90, stats.cur)
			assert.are.equal(110, stats.ref)
			assert.are.equal(3, stats.refDays)
			assert.near(-18.18, stats.change, 0.01)
			assert.are.equal(75, stats.qty)
			assert.are.equal(90, stats.min)
			assert.near(2.5, stats.supply, 1e-4)
			assert.are.equal(4, stats.obsDays)
			assert.are.equal(3, stats.soldPerDay)
			assert.is_true(stats.falling)
		end)

		it("computes fixture B (a steady riser)", function()
			local stats = L.Stats(itemB, TODAY)
			assert.are.equal(1000, stats.market)
			assert.near(50, stats.change, 0.01)
			assert.near(1, stats.supply, 1e-4)
			assert.is_nil(stats.soldPerDay)
			assert.near(0.1925, stats.cv, 1e-4)
		end)

		it("computes fixture C (stable, selling well)", function()
			local stats = L.Stats(itemC, TODAY)
			assert.are.equal(1000, stats.market)
			assert.near(0, stats.cv, 1e-9)
			assert.near(0, stats.change, 0.01)
			assert.near(1.7, stats.supply, 1e-4)
			assert.are.equal(5, stats.soldPerDay)
		end)

		it("computes fixture D (no history, vendor only)", function()
			local stats = L.Stats(itemD, TODAY)
			assert.is_nil(stats.market)
			assert.is_nil(stats.cv)
			assert.is_nil(stats.change)
			assert.is_nil(stats.supply)
			assert.is_nil(stats.soldPerDay)
			assert.are.equal(10, stats.qty)
			assert.are.equal(30, stats.min)
		end)

		it("computes fixture E (volatile, not selling)", function()
			local stats = L.Stats(itemE, TODAY)
			assert.are.equal(100, stats.market)
			assert.near(0.5657, stats.cv, 1e-4)
			assert.near(-50, stats.change, 0.01)
			assert.are.equal(0, stats.soldPerDay)
		end)
	end)

	describe("AvoidReasons", function()
		it("flags falling and oversupply for fixture A", function()
			assert.are.same({ "falling", "oversupply" }, L.AvoidReasons(L.Stats(itemA, TODAY)))
		end)

		it("flags nothing for fixtures B, C and D", function()
			assert.are.same({}, L.AvoidReasons(L.Stats(itemB, TODAY)))
			assert.are.same({}, L.AvoidReasons(L.Stats(itemC, TODAY)))
			assert.are.same({}, L.AvoidReasons(L.Stats(itemD, TODAY)))
		end)

		it("flags volatile and no_sales for fixture E", function()
			assert.are.same({ "volatile", "no_sales" }, L.AvoidReasons(L.Stats(itemE, TODAY)))
		end)
	end)

	describe("FindDeal", function()
		it("refuses a flip on an avoid-flagged item with no vendor price", function()
			assert.is_nil(L.FindDeal(itemA, L.Stats(itemA, TODAY), settings))
		end)

		it("refuses a flip whose listings are above the discounted target", function()
			assert.is_nil(L.FindDeal(itemB, L.Stats(itemB, TODAY), settings))
		end)

		it("finds a flip deal for fixture C above its minimum profit", function()
			local stats = L.Stats(itemC, TODAY)
			local deal = L.FindDeal(itemC, stats, { discount = 0.30, cut = 0.05, minProfit = 3000 })
			assert.are.same({
				kind = "flip",
				itemID = 3,
				name = nil,
				quality = nil,
				qty = 12,
				cost = 7700,
				unitMax = 650,
				sellUnit = 1000,
				profit = 3700,
				margin = 48,
				soldPerDay = 5,
			}, deal)
		end)

		it("drops the fixture C deal once minProfit rises past its profit", function()
			local stats = L.Stats(itemC, TODAY)
			assert.is_nil(L.FindDeal(itemC, stats, { discount = 0.30, cut = 0.05, minProfit = 4000 }))
		end)

		it("finds a vendor deal for fixture D", function()
			local stats = L.Stats(itemD, TODAY)
			local deal = L.FindDeal(itemD, stats, { discount = 0.30, cut = 0.05, minProfit = 100 })
			assert.are.same({
				kind = "vendor",
				itemID = 4,
				name = nil,
				quality = nil,
				qty = 9,
				cost = 320,
				unitMax = 40,
				sellUnit = 50,
				profit = 130,
				margin = 40,
				soldPerDay = nil,
			}, deal)
		end)

		it("refuses a flip on the volatile, not-selling fixture E", function()
			assert.is_nil(L.FindDeal(itemE, L.Stats(itemE, TODAY), settings))
		end)
	end)

	describe("Analyze", function()
		local result

		before_each(function()
			result = L.Analyze({ itemA, itemB, itemC, itemD, itemE }, TODAY, settings)
		end)

		it("lists deals sorted by profit, descending", function()
			assert.are.equal(2, #result.deals)
			assert.are.equal(3, result.deals[1].itemID)
			assert.are.equal("flip", result.deals[1].kind)
			assert.are.equal(4, result.deals[2].itemID)
			assert.are.equal("vendor", result.deals[2].kind)
		end)

		it("lists movers by |change| descending, ties broken by itemID", function()
			assert.are.equal(2, #result.movers)
			assert.are.equal(2, result.movers[1].itemID)
			assert.are.equal(5, result.movers[2].itemID)
			assert.near(50, result.movers[1].change, 0.01)
			assert.near(-50, result.movers[2].change, 0.01)
		end)

		it("lists hot items by copper volume, descending", function()
			assert.are.equal(2, #result.hot)
			assert.are.equal(3, result.hot[1].itemID)
			assert.are.equal(5000, result.hot[1].volume)
			assert.are.equal(1, result.hot[2].itemID)
			assert.are.equal(315, result.hot[2].volume)
		end)

		it("lists avoid items by reason count then market, descending", function()
			assert.are.equal(2, #result.avoid)
			assert.are.equal(1, result.avoid[1].itemID)
			assert.are.equal(5, result.avoid[2].itemID)
		end)
	end)

	describe("Median", function()
		it("takes the middle of an odd list", function()
			assert.are.equal(2, L.Median({ 3, 1, 2 }))
		end)

		it("floors the average of the middle pair of an even list", function()
			assert.are.equal(105, L.Median({ 90, 100, 110, 120 }))
			assert.are.equal(100, L.Median({ 101, 100 }))
		end)

		it("is nil for an empty list", function()
			assert.is_nil(L.Median({}))
		end)
	end)

	describe("FormatMoney", function()
		it("formats copper into gold, silver and copper", function()
			assert.are.equal("0c", L.FormatMoney(0))
			assert.are.equal("5c", L.FormatMoney(5))
			assert.are.equal("5s", L.FormatMoney(500))
			assert.are.equal("1g 2s 3c", L.FormatMoney(10203))
			assert.are.equal("1g", L.FormatMoney(10000))
			assert.are.equal("123g 45s", L.FormatMoney(1234500))
		end)

		it("prefixes a minus sign and floors fractional and negative amounts", function()
			assert.are.equal("-1g 2s 3c", L.FormatMoney(-10203))
			assert.are.equal("1g 2s 3c", L.FormatMoney(10203.9))
		end)

		it("is a dash for nil", function()
			assert.are.equal("-", L.FormatMoney(nil))
		end)
	end)

	describe("FormatPercent", function()
		it("rounds half away from zero and signs the result", function()
			assert.are.equal("+12%", L.FormatPercent(12.4))
			assert.are.equal("-18%", L.FormatPercent(-18.18))
			assert.are.equal("0%", L.FormatPercent(0))
			assert.are.equal("0%", L.FormatPercent(0.4))
			assert.are.equal("0%", L.FormatPercent(-0.4))
			assert.are.equal("+13%", L.FormatPercent(12.5))
			assert.are.equal("-13%", L.FormatPercent(-12.5))
		end)

		it("is a dash for nil", function()
			assert.are.equal("-", L.FormatPercent(nil))
		end)
	end)

	describe("FormatDuration", function()
		it("formats seconds, minutes, hours and days", function()
			assert.are.equal("45s", L.FormatDuration(45))
			assert.are.equal("12m", L.FormatDuration(720))
			assert.are.equal("2h 5m", L.FormatDuration(7500))
			assert.are.equal("2h", L.FormatDuration(7200))
			assert.are.equal("3d 4h", L.FormatDuration(273600))
		end)

		it("is 0s for zero or negative durations", function()
			assert.are.equal("0s", L.FormatDuration(0))
			assert.are.equal("0s", L.FormatDuration(-5))
		end)
	end)
end)
