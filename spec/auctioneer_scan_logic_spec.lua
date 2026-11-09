describe("AuctioneerScanLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/AuctioneerScanLogic.lua"))("MerrinxUI", ns)
		L = ns.AuctioneerScanLogic
	end)

	describe("Day", function()
		it("floors seconds to a UTC day", function()
			assert.are.equal(20250, L.Day(1749600000))
			assert.are.equal(20250, L.Day(1749686399))
			assert.are.equal(20251, L.Day(1749686400))
		end)

		it("returns nil for a non-number", function()
			assert.is_nil(L.Day("x"))
		end)
	end)

	describe("ThrottleLeft", function()
		it("is 0 when there is no previous call or the throttle has elapsed", function()
			assert.are.equal(0, L.ThrottleLeft(1000, 0))
			assert.are.equal(0, L.ThrottleLeft(1000, nil))
			assert.are.equal(0, L.ThrottleLeft(1300, 400))
		end)

		it("returns the seconds left, capped at 900", function()
			assert.are.equal(300, L.ThrottleLeft(1000, 400))
			assert.are.equal(900, L.ThrottleLeft(1000, 1500))
		end)
	end)

	describe("WeightedMedian", function()
		it("returns the first unit where cumulative quantity reaches half the total", function()
			assert.are.equal(500, L.WeightedMedian({ { 100, 1 }, { 120, 1 }, { 500, 10 } }))
			assert.are.equal(100, L.WeightedMedian({ { 100, 5 }, { 200, 5 } }))
		end)

		it("returns nil for no entries", function()
			assert.is_nil(L.WeightedMedian({}))
		end)
	end)

	describe("NewAccumulator, AddRow and Finish", function()
		it("builds per-item summaries, skipping invalid rows", function()
			local acc = L.NewAccumulator()
			assert.is_true(
				L.AddRow(acc, { itemID = 2589, name = "Linen Cloth", quality = 1, count = 20, buyout = 2000, band = 3 })
			)
			assert.is_true(
				L.AddRow(acc, { itemID = 2589, name = "Linen Cloth", quality = 1, count = 5, buyout = 600, band = 2 })
			)
			assert.is_true(
				L.AddRow(acc, { itemID = 2589, name = nil, quality = 1, count = 20, buyout = 2000, band = 1 })
			)
			assert.is_false(L.AddRow(acc, { itemID = 2589, count = 1, buyout = 0, band = 3 }))
			assert.is_false(L.AddRow(acc, { itemID = nil }))
			assert.is_true(
				L.AddRow(
					acc,
					{ itemID = 118, name = "Minor Healing Potion", quality = 1, count = 1, buyout = 95, band = 0 }
				)
			)

			assert.are.equal(6, acc.rows)
			assert.are.equal(2, acc.skipped)

			local summaries, rows, skipped = L.Finish(acc)
			assert.are.equal(6, rows)
			assert.are.equal(2, skipped)

			local cloth = summaries[2589]
			assert.are.equal("Linen Cloth", cloth.name)
			assert.are.equal(1, cloth.quality)
			assert.are.equal(3, cloth.auctions)
			assert.are.equal(45, cloth.qty)
			assert.are.equal(100, cloth.min)
			assert.are.equal(100, cloth.med)
			assert.are.same({ 0, 1, 0, 1 }, cloth.buckets["2000,20"])
			assert.are.same({ 0, 0, 1, 0 }, cloth.buckets["600,5"])

			local potion = summaries[118]
			assert.are.equal(1, potion.auctions)
			assert.are.equal(1, potion.qty)
			assert.are.equal(95, potion.min)
			assert.are.equal(95, potion.med)
			assert.are.same({ 1, 0, 0, 0 }, potion.buckets["95,1"])
		end)

		it("floors the unit price", function()
			local acc = L.NewAccumulator()
			L.AddRow(acc, { itemID = 1, count = 10, buyout = 1001, band = 0 })
			local summaries = L.Finish(acc)
			assert.are.equal(100, summaries[1].min)
		end)
	end)

	describe("BucketKey", function()
		it("joins buyout and count with a comma", function()
			assert.are.equal("2000,20", L.BucketKey(2000, 20))
		end)
	end)

	describe("PackSnapshot and UnpackSnapshot", function()
		it("packs buckets in canonical unit order and round-trips", function()
			local buckets = { ["2000,20"] = { 0, 1, 0, 1 }, ["600,5"] = { 0, 0, 1, 0 } }
			local packed = L.PackSnapshot(buckets)
			assert.are.equal("2000,20,0,1,0,1;600,5,0,0,1,0", packed)
			assert.are.same(buckets, L.UnpackSnapshot(packed))
		end)

		it("skips malformed entries and sums duplicate keys", function()
			assert.are.same({ ["95,1"] = { 1, 0, 0, 0 } }, L.UnpackSnapshot("abc;95,1,1,0,0,0;5,0,1,0,0,0"))
			assert.are.same({ ["95,1"] = { 1, 2, 0, 0 } }, L.UnpackSnapshot("95,1,1,0,0,0;95,1,0,2,0,0"))
		end)

		it('returns {} for nil or empty, and "" for {}', function()
			assert.are.same({}, L.UnpackSnapshot(nil))
			assert.are.same({}, L.UnpackSnapshot(""))
			assert.are.equal("", L.PackSnapshot({}))
		end)
	end)

	describe("Listings", function()
		it("lists buckets in canonical order with summed counts", function()
			local buckets = { ["2000,20"] = { 0, 1, 0, 1 }, ["600,5"] = { 0, 0, 1, 0 } }
			assert.are.same(
				{ { 2000, 20, 2 }, { 600, 5, 1 } },
				(function()
					local listings = L.Listings(buckets)
					local out = {}
					for i, listing in ipairs(listings) do
						out[i] = { listing.buyout, listing.count, listing.n }
					end
					return out
				end)()
			)
		end)
	end)

	describe("EstimateRemoved", function()
		local prev, cur

		before_each(function()
			prev = { ["1000,10"] = { 0, 1, 2, 0 }, ["95,1"] = { 3, 0, 0, 0 } }
			cur = { ["1000,10"] = { 0, 0, 1, 0 } }
		end)

		it("sums removed units beyond what could have expired in the gap", function()
			assert.are.equal(20, L.EstimateRemoved(prev, cur, 1200))
			assert.are.equal(10, L.EstimateRemoved(prev, cur, 3600))
		end)

		it("returns nil for an unusable gap or an empty previous snapshot", function()
			assert.is_nil(L.EstimateRemoved(prev, cur, nil))
			assert.is_nil(L.EstimateRemoved(prev, cur, 50000))
			assert.is_nil(L.EstimateRemoved({}, cur, 1200))
		end)

		it("returns 0 when nothing disappeared", function()
			assert.are.equal(0, L.EstimateRemoved(prev, prev, 1200))
		end)
	end)

	describe("UnpackHistory and PackHistory", function()
		it("round-trips a history string exactly", function()
			local s = "20250,95,120,340,12,2,3;20251,90,118,300,5,1,1"
			local records = L.UnpackHistory(s)
			assert.are.equal(s, L.PackHistory(records))
		end)

		it("skips malformed records and sorts by day", function()
			local records = L.UnpackHistory("20251,1,1,1,0,0,1;garbage;20250,2,2,2,0,0,1")
			assert.are.equal(2, #records)
			assert.are.equal(20250, records[1].day)
			assert.are.equal(20251, records[2].day)
		end)

		it("keeps the later occurrence of a duplicate day", function()
			local records = L.UnpackHistory("20250,1,1,1,0,0,1;20250,2,2,2,0,0,2")
			assert.are.equal(1, #records)
			assert.are.equal(2, records[1].min)
			assert.are.equal(2, records[1].scans)
		end)

		it('returns {} for nil or empty, and "" for {}', function()
			assert.are.same({}, L.UnpackHistory(nil))
			assert.are.same({}, L.UnpackHistory(""))
			assert.are.equal("", L.PackHistory({}))
		end)
	end)

	describe("MergeScan", function()
		it("inserts a new record for an unseen day", function()
			local records = L.MergeScan({}, 20251, { min = 90, med = 118, qty = 300, sold = nil })
			assert.are.same({ { day = 20251, min = 90, med = 118, qty = 300, sold = 0, obs = 0, scans = 1 } }, records)
		end)

		it("updates an existing day's record on a later scan", function()
			local records = L.MergeScan({}, 20251, { min = 90, med = 118, qty = 300, sold = nil })
			records = L.MergeScan(records, 20251, { min = 80, med = 110, qty = 250, sold = 7 })
			local rec = records[1]
			assert.are.equal(80, rec.min)
			assert.are.equal(110, rec.med)
			assert.are.equal(250, rec.qty)
			assert.are.equal(7, rec.sold)
			assert.are.equal(1, rec.obs)
			assert.are.equal(2, rec.scans)

			records = L.MergeScan(records, 20251, { min = 0, med = 0, qty = 0, sold = 3 })
			rec = records[1]
			assert.are.equal(80, rec.min)
			assert.are.equal(110, rec.med)
			assert.are.equal(0, rec.qty)
			assert.are.equal(10, rec.sold)
			assert.are.equal(2, rec.obs)
			assert.are.equal(3, rec.scans)
		end)

		it("keeps records sorted when merging an earlier day", function()
			local records = L.MergeScan({}, 20251, { min = 1, med = 1, qty = 1, sold = nil })
			records = L.MergeScan(records, 20250, { min = 1, med = 1, qty = 1, sold = nil })
			assert.are.same({ 20250, 20251 }, { records[1].day, records[2].day })
		end)
	end)

	describe("Prune", function()
		it("keeps only records newer than today - keepDays", function()
			local records = {
				{ day = 20240, min = 1, med = 1, qty = 1, sold = 0, obs = 0, scans = 1 },
				{ day = 20247, min = 1, med = 1, qty = 1, sold = 0, obs = 0, scans = 1 },
				{ day = 20260, min = 1, med = 1, qty = 1, sold = 0, obs = 0, scans = 1 },
			}
			records = L.Prune(records, 20260, 14)
			assert.are.same({ 20247, 20260 }, { records[1].day, records[2].day })
		end)
	end)
end)
