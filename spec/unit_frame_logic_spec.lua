describe("UnitFrameLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/UnitFrameLogic.lua"))("MerrinxUI", ns)
		L = ns.UnitFrameLogic
	end)

	it("BarHeights keeps the frame height and gives the health bar the rest", function()
		assert.are.same({ 35, 8, 0 }, { L.BarHeights(44, 8, 4, false) })
		assert.are.same({ 30, 8, 5 }, { L.BarHeights(44, 8, 4, true) })
		assert.are.same({ 24, 0, 0 }, { L.BarHeights(24, 0, 4, false) })
		assert.are.same({ 19, 0, 5 }, { L.BarHeights(24, 0, 4, true) })
	end)

	it("BarHeights clamps oversized bars so the health bar keeps a few pixels", function()
		local health, power, slot = L.BarHeights(20, 40, 40, true)
		assert.are.equal(16, power)
		assert.is_true(health >= 0)
		assert.are.equal(20, health + power + slot + 1)
	end)

	it("ShowDruidMana shows only for an enabled druid off mana", function()
		assert.is_true(L.ShowDruidMana(true, "DRUID", 3, 0))
		assert.is_false(L.ShowDruidMana(true, "DRUID", 0, 0))
		assert.is_false(L.ShowDruidMana(false, "DRUID", 3, 0))
		assert.is_false(L.ShowDruidMana(true, "MAGE", 3, 0))
		assert.is_false(L.ShowDruidMana(true, "DRUID", nil, 0))
	end)

	it("EventUnits fans target events out to the target of target", function()
		assert.are.same({ "target", "targettarget" }, L.EventUnits("target"))
		assert.are.same({ "focus" }, L.EventUnits("focus"))
	end)

	it("Watched is every unit but the player", function()
		assert.is_false(L.Watched("player"))
		assert.is_true(L.Watched("pet"))
	end)

	it("Amount turns nil into 0 and passes numbers and secrets through", function()
		local secret = {}
		local function isSecret(v)
			return v == secret
		end
		assert.are.equal(0, L.Amount(nil, isSecret))
		assert.are.equal(1200, L.Amount(1200, isSecret))
		assert.are.equal(secret, L.Amount(secret, isSecret))
	end)
end)
