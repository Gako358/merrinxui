describe("DamageMeterLogic", function()
	local ns

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/DamageMeterLogic.lua"))("MerrinxUI", ns)
	end)

	it("Title combines the metric label and session", function()
		assert.are.equal("Damage Done - Current", ns.DamageMeterLogic.Title("Current", "DamageDone"))
		assert.are.equal("Healing Done - Overall", ns.DamageMeterLogic.Title("Overall", "HealingDone"))
	end)

	it("VisibleRows clamps the count between 0 and rows", function()
		assert.are.equal(3, ns.DamageMeterLogic.VisibleRows(3, 8))
		assert.are.equal(8, ns.DamageMeterLogic.VisibleRows(20, 8))
		assert.are.equal(0, ns.DamageMeterLogic.VisibleRows(0, 8))
	end)

	it("WindowHeight sums the header, rows and spacing", function()
		assert.are.equal(180, ns.DamageMeterLogic.WindowHeight(8, 18, 2, 22))
		assert.are.equal(40, ns.DamageMeterLogic.WindowHeight(1, 18, 2, 22))
		assert.are.equal(22, ns.DamageMeterLogic.WindowHeight(0, 18, 2, 22))
	end)

	it("EnumKey reads a string key from a table, else nil", function()
		local tbl = { Overall = 0, Current = 1 }
		assert.are.equal(0, ns.DamageMeterLogic.EnumKey(tbl, "Overall"))
		assert.are.equal(1, ns.DamageMeterLogic.EnumKey(tbl, "Current"))
		assert.is_nil(ns.DamageMeterLogic.EnumKey(tbl, "Bogus"))
		assert.is_nil(ns.DamageMeterLogic.EnumKey(nil, "Current"))
		assert.is_nil(ns.DamageMeterLogic.EnumKey(tbl, 1))
	end)

	it("IconCoords zooms the coordinate rectangle inward, or passes through nil", function()
		local l, r, t, b = ns.DamageMeterLogic.IconCoords({ 0, 1, 0, 1 }, 0.06)
		assert.are.equal(0.06, l)
		assert.are.equal(0.94, r)
		assert.are.equal(0.06, t)
		assert.are.equal(0.94, b)

		local l2, r2, t2, b2 = ns.DamageMeterLogic.IconCoords({ 0, 0.25, 0, 0.25 }, 0.06)
		assert.near(0.015, l2, 1e-9)
		assert.near(0.235, r2, 1e-9)
		assert.near(0.015, t2, 1e-9)
		assert.near(0.235, b2, 1e-9)

		assert.is_nil(ns.DamageMeterLogic.IconCoords(nil, 0.06))
	end)

	it("ShortName strips a realm suffix, else passes through or nil", function()
		assert.are.equal("Merrinx", ns.DamageMeterLogic.ShortName("Merrinx-Firemaw"))
		assert.are.equal("Merrinx", ns.DamageMeterLogic.ShortName("Merrinx"))
		assert.is_nil(ns.DamageMeterLogic.ShortName(nil))
	end)

	it("Toggle swaps between the two given values", function()
		assert.are.equal("Overall", ns.DamageMeterLogic.Toggle("Current", "Current", "Overall"))
		assert.are.equal("Current", ns.DamageMeterLogic.Toggle("Overall", "Current", "Overall"))
		assert.are.equal("Current", ns.DamageMeterLogic.Toggle("x", "Current", "Overall"))
	end)
end)
