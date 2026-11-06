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
end)
