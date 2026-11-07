describe("PerformanceLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/PerformanceLogic.lua"))("MerrinxUI", ns)
		L = ns.PerformanceLogic
	end)

	it("Record accumulates totals, calls, peak and the open bucket", function()
		local s = L.NewStats()
		L.Record(s, 2)
		L.Record(s, 5)
		L.Record(s, 1)
		assert.are.equal(8, s.total)
		assert.are.equal(3, s.calls)
		assert.are.equal(5, s.peak)
		assert.are.equal(8, s.bucket)
	end)

	it("Rate is ms per second over the rolled window", function()
		local s = L.NewStats()
		assert.are.equal(0, L.Rate(s))
		L.Record(s, 10)
		L.Roll(s, 1, 3)
		assert.are.equal(0, s.bucket)
		assert.are.equal(10, L.Rate(s))
		L.Record(s, 2)
		L.Roll(s, 1, 3)
		assert.are.equal(6, L.Rate(s))
	end)

	it("Roll drops samples older than the window", function()
		local s = L.NewStats()
		for _, ms in ipairs({ 30, 0, 0, 3 }) do
			L.Record(s, ms)
			L.Roll(s, 1, 3)
		end
		assert.are.equal(1, L.Rate(s))
	end)

	it("Reset clears everything", function()
		local s = L.NewStats()
		L.Record(s, 4)
		L.Roll(s, 1, 3)
		L.Reset(s)
		assert.are.same(L.NewStats(), s)
	end)

	it("Top sorts by rate, then total, then name, and caps the count", function()
		local stats = {}
		for name, v in pairs({ A = { 1, 1 }, B = { 5, 5 }, C = { 0, 9 }, D = { 0, 9 } }) do
			local s = L.NewStats()
			L.Record(s, v[1])
			L.Roll(s, 1, 5)
			s.total = v[2]
			stats[name] = s
		end
		local top = L.Top(stats, 3)
		assert.are.same({ "B", "A", "C" }, { top[1].name, top[2].name, top[3].name })
		assert.are.equal(5, top[1].rate)
		assert.are.equal(4, #L.Top(stats, 10))
	end)

	it("Sum adds rates and totals", function()
		local a, b = L.NewStats(), L.NewStats()
		L.Record(a, 2)
		L.Record(b, 3)
		L.Roll(a, 1, 5)
		L.Roll(b, 1, 5)
		local rate, total = L.Sum({ a = a, b = b })
		assert.are.same({ 5, 5 }, { rate, total })
	end)

	it("FrameShare is the part of one frame the time takes", function()
		assert.are.equal(50, L.FrameShare(10, 50))
		assert.are.equal(0, L.FrameShare(10, 0))
		assert.are.equal(0, L.FrameShare(nil, 60))
	end)

	it("Share guards a zero whole", function()
		assert.are.equal(25, L.Share(1, 4))
		assert.are.equal(0, L.Share(1, 0))
	end)

	it("FormatMemory picks KB or MB", function()
		assert.are.equal("512 KB", L.FormatMemory(512))
		assert.are.equal("1.50 MB", L.FormatMemory(1536))
		assert.are.equal("?", L.FormatMemory(nil))
	end)

	it("FormatMs keeps small values readable", function()
		assert.are.equal("0.125 ms", L.FormatMs(0.125))
		assert.are.equal("12.50 ms", L.FormatMs(12.5))
		assert.are.equal("?", L.FormatMs(nil))
	end)

	it("SortAddOns orders by value and drops zeroes", function()
		local list =
			L.SortAddOns({ { name = "a", value = 1 }, { name = "b", value = 0 }, { name = "c", value = 3 } }, 5)
		assert.are.same({ "c", "a" }, { list[1].name, list[2].name })
		assert.are.equal(2, #list)
	end)
end)
