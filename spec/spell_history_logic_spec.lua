describe("SpellHistoryLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/SpellHistoryLogic.lua"))("MerrinxUI", ns)
		L = ns.SpellHistoryLogic
	end)

	it("Push puts the newest first and trims to max", function()
		local h = {}
		L.Push(h, "a", 2)
		L.Push(h, "b", 2)
		L.Push(h, "c", 2)
		assert.are.same({ "c", "b" }, h)
	end)

	it("Progress fills casts, drains channels and holds finished fills", function()
		assert.are.equal(0.5, L.Progress({ status = "casting", startTime = 0, endTime = 2 }, 1))
		assert.are.equal(0.25, L.Progress({ status = "channeling", startTime = 0, endTime = 4 }, 3))
		assert.are.equal(1, L.Progress({ status = "casting", startTime = 0, endTime = 0 }, 1))
		assert.are.equal(0.3, L.Progress({ status = "failed", fill = 0.3 }, 1))
		assert.are.equal(1, L.Progress({ status = "success" }, 1))
	end)

	it("Finish records duration and freezes the fill only for stopped casts", function()
		local e = L.Finish({ status = "casting", startTime = 0, endTime = 4 }, "interrupted", 1)
		assert.are.equal(0.25, e.fill)
		assert.are.equal(1, e.castDuration)
		local s = L.Finish({ status = "casting", startTime = 0, endTime = 2 }, "success", 2)
		assert.is_nil(s.fill)
		assert.are.equal("success", s.status)
	end)

	it("CastTimeText counts up while casting and shows the total afterwards", function()
		assert.are.equal("", L.CastTimeText({ isInstant = true }, 5))
		assert.are.equal("1.5", L.CastTimeText({ status = "casting", startTime = 1 }, 2.5))
		assert.are.equal("2.0s", L.CastTimeText({ status = "success", castDuration = 2 }, 9))
		assert.are.equal("", L.CastTimeText({ status = "success", castDuration = 0 }, 9))
	end)

	it("RightText joins cast time with the outcome or target", function()
		assert.are.equal(
			"1.0s  |cffdb4141Interrupted|r",
			L.RightText({ status = "interrupted", castDuration = 1 }, 5, "Hogger")
		)
		assert.are.equal("Hogger", L.RightText({ status = "success", isInstant = true }, 5, "Hogger"))
		assert.are.equal("", L.RightText({ status = "success", isInstant = true }, 5, nil))
		assert.are.equal("2.0s", L.RightText({ status = "success", castDuration = 2 }, 5, ""))
	end)

	it("IconOffset steps away from the anchor in the grow direction", function()
		assert.are.same({ -74, 0 }, { L.IconOffset(3, 36, 1, "LEFT") })
		assert.are.same({ 37, 0 }, { L.IconOffset(2, 36, 1, "RIGHT") })
		assert.are.same({ 0, 37 }, { L.IconOffset(2, 36, 1, "UP") })
		assert.are.same({ 0, -37 }, { L.IconOffset(2, 36, 1, "DOWN") })
	end)

	it("IconVisible fades after the later of cast time and combat end, never in combat", function()
		assert.is_true(L.IconVisible(0, 0, 100, 0, false))
		assert.is_true(L.IconVisible(0, 0, 100, 5, true))
		assert.is_false(L.IconVisible(0, 0, 10, 5, false))
		assert.is_true(L.IconVisible(0, 8, 10, 5, false))
	end)

	it("ClampScroll keeps the scroll inside the history", function()
		assert.are.equal(0, L.ClampScroll(-1, 10, 5))
		assert.are.equal(5, L.ClampScroll(9, 10, 5))
		assert.are.equal(0, L.ClampScroll(3, 2, 5))
	end)
end)
