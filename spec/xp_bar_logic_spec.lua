describe("XPBarLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/XPBarLogic.lua"))("MerrinxUI", ns)
		L = ns.XPBarLogic
	end)

	it("QuestXP sums completed quests only", function()
		local count, total = L.QuestXP({
			{ complete = true, xp = 450 },
			{ complete = false, xp = 900 },
			{ complete = true, xp = 0 },
			{ complete = true, xp = nil },
			{ complete = true, xp = 300 },
		})
		assert.are.same({ 2, 750 }, { count, total })
		assert.are.same({ 0, 0 }, { L.QuestXP({}) })
	end)

	it("Fill stops at the end of the level", function()
		assert.are.equal(700, L.Fill(500, 1000, 200))
		assert.are.equal(1000, L.Fill(900, 1000, 450))
		assert.are.equal(500, L.Fill(500, 1000, nil))
	end)

	it("Percent guards an empty level", function()
		assert.are.equal(25, L.Percent(250, 1000))
		assert.are.equal(0, L.Percent(5, 0))
	end)

	it("Text shows progress, quest XP, the level up and rested XP", function()
		local fmt = tostring
		assert.are.equal("250 / 1000 (25.0%)", L.Text(250, 1000, 0, 0, fmt))
		assert.are.equal("250 / 1000 (25.0%)  +300 quests (30.0%)  +100 rested", L.Text(250, 1000, 100, 300, fmt))
		assert.are.equal("800 / 1000 (80.0%)  +200 quests (20.0%) level up", L.Text(800, 1000, 0, 200, fmt))
	end)

	it("AtMax compares the level with the cap", function()
		assert.is_true(L.AtMax(60, 60))
		assert.is_false(L.AtMax(59, 60))
		assert.is_false(L.AtMax(60, nil))
		assert.is_false(L.AtMax(60, 0))
	end)

	it("NewRate starts an empty tracker at now", function()
		assert.are.same({ start = 42, samples = {} }, L.NewRate(42))
	end)

	it("Track records XP gains, counts level wraps in full and prunes the window", function()
		local r = L.NewRate(0)
		L.Track(r, 100, 1000, 0, 600)
		assert.are.equal(0, #r.samples)
		assert.are.equal(100, r.lastCur)
		assert.are.equal(1000, r.lastMax)

		L.Track(r, 100, 1000, 10, 600)
		assert.are.equal(0, #r.samples)

		L.Track(r, 250, 1000, 20, 600)
		assert.are.same({ { t = 20, xp = 150 } }, r.samples)

		local wrapEqualMax = L.NewRate(0)
		L.Track(wrapEqualMax, 250, 1000, 0, 600)
		L.Track(wrapEqualMax, 200, 1000, 30, 600)
		assert.are.same({ { t = 30, xp = 950 } }, wrapEqualMax.samples)

		local wrapLowerCur = L.NewRate(0)
		L.Track(wrapLowerCur, 900, 1000, 0, 600)
		L.Track(wrapLowerCur, 50, 1200, 10, 600)
		assert.are.same({ { t = 10, xp = 150 } }, wrapLowerCur.samples)

		local wrapHigherCur = L.NewRate(0)
		L.Track(wrapHigherCur, 100, 1000, 0, 600)
		L.Track(wrapHigherCur, 600, 1200, 10, 600)
		assert.are.same({ { t = 10, xp = 1500 } }, wrapHigherCur.samples)

		local ignoredRead = L.NewRate(0)
		L.Track(ignoredRead, 100, 1000, 0, 600)
		L.Track(ignoredRead, 0, 1, 5, 600)
		assert.are.equal(0, #ignoredRead.samples)
		L.Track(ignoredRead, 300, 1000, 10, 600)
		assert.are.same({ { t = 10, xp = 200 } }, ignoredRead.samples)

		local pruned = L.NewRate(0)
		L.Track(pruned, 0, 1000, 0, 600)
		L.Track(pruned, 50, 1000, 100, 600)
		L.Track(pruned, 80, 1000, 700, 600)
		assert.are.same({ { t = 700, xp = 30 } }, pruned.samples)
	end)

	it("PerSecond averages tracked XP across the window, clamped by minSpan", function()
		assert.are.equal(10, L.PerSecond({ start = 0, samples = { { t = 10, xp = 600 } } }, 30, 600, 60))
		assert.are.equal(2, L.PerSecond({ start = 0, samples = { { t = 1000, xp = 1200 } } }, 1200, 600, 60))
		assert.are.equal(0, L.PerSecond({ start = 0, samples = { { t = 100, xp = 500 } } }, 800, 600, 60))
		assert.are.equal(0, L.PerSecond(L.NewRate(0), 100, 600, 60))
	end)

	it("TimeToLevel divides remaining XP by the current rate", function()
		assert.are.equal(60, L.TimeToLevel(600, 10))
		assert.is_nil(L.TimeToLevel(0, 10))
		assert.is_nil(L.TimeToLevel(-5, 10))
		assert.is_nil(L.TimeToLevel(600, 0))
	end)

	it("FormatDuration renders minutes under an hour and hours otherwise", function()
		assert.are.equal("<1m", L.FormatDuration(0))
		assert.are.equal("<1m", L.FormatDuration(59))
		assert.are.equal("1m", L.FormatDuration(60))
		assert.are.equal("59m", L.FormatDuration(3599))
		assert.are.equal("1h 00m", L.FormatDuration(3600))
		assert.are.equal("1h 01m", L.FormatDuration(3661))
	end)
end)
