describe("DamageMeterLogic", function()
	local ns

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/DamageMeterLogic.lua"))("MerrinxUI", ns)
	end)

	it("Title combines the type label and session label", function()
		assert.are.equal("Damage Done - Current", ns.DamageMeterLogic.Title("Current", "DamageDone"))
		assert.are.equal("DPS - Hogger (1:05)", ns.DamageMeterLogic.Title("Hogger (1:05)", "Dps"))
		assert.are.equal("Threat - Overall", ns.DamageMeterLogic.Title("Overall", "Threat"))
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

	it("TypeList returns enum string keys sorted by value, else empty", function()
		local enum = {
			DamageDone = 0,
			Dps = 1,
			HealingDone = 2,
			Hps = 3,
			Absorbs = 4,
			Interrupts = 5,
			Dispels = 6,
			DamageTaken = 7,
			AvoidableDamageTaken = 8,
			Deaths = 9,
			EnemyDamageTaken = 10,
		}
		assert.are.same({
			"DamageDone",
			"Dps",
			"HealingDone",
			"Hps",
			"Absorbs",
			"Interrupts",
			"Dispels",
			"DamageTaken",
			"AvoidableDamageTaken",
			"Deaths",
			"EnemyDamageTaken",
		}, ns.DamageMeterLogic.TypeList(enum))
		assert.are.same({}, ns.DamageMeterLogic.TypeList(nil))
		assert.are.same({}, ns.DamageMeterLogic.TypeList({ [1] = 2, Foo = "x" }))
	end)

	it("TypeLabel maps known types, humanizes unknown ones, else None", function()
		assert.are.equal("DPS", ns.DamageMeterLogic.TypeLabel("Dps"))
		assert.are.equal("Avoidable Damage Taken", ns.DamageMeterLogic.TypeLabel("AvoidableDamageTaken"))
		assert.are.equal("Foo Bar Baz", ns.DamageMeterLogic.TypeLabel("FooBarBaz"))
		assert.are.equal("None", ns.DamageMeterLogic.TypeLabel(nil))
	end)

	it("TypeKind classifies a type key as rate, count, deaths or amount", function()
		assert.are.equal("rate", ns.DamageMeterLogic.TypeKind("Dps"))
		assert.are.equal("rate", ns.DamageMeterLogic.TypeKind("Hps"))
		assert.are.equal("count", ns.DamageMeterLogic.TypeKind("Interrupts"))
		assert.are.equal("count", ns.DamageMeterLogic.TypeKind("Dispels"))
		assert.are.equal("deaths", ns.DamageMeterLogic.TypeKind("Deaths"))
		assert.are.equal("amount", ns.DamageMeterLogic.TypeKind("DamageDone"))
		assert.are.equal("amount", ns.DamageMeterLogic.TypeKind("Absorbs"))
		assert.are.equal("amount", ns.DamageMeterLogic.TypeKind("Threat"))
	end)

	it("BarField picks the per-second field for rate kinds, else the total", function()
		assert.are.equal("amountPerSecond", ns.DamageMeterLogic.BarField("rate"))
		assert.are.equal("totalAmount", ns.DamageMeterLogic.BarField("amount"))
		assert.are.equal("totalAmount", ns.DamageMeterLogic.BarField("count"))
		assert.are.equal("totalAmount", ns.DamageMeterLogic.BarField("deaths"))
	end)

	it("MenuGroups groups a full type list into the fixed Damage/Healing/Actions order", function()
		local list = {
			"DamageDone",
			"Dps",
			"HealingDone",
			"Hps",
			"Absorbs",
			"Interrupts",
			"Dispels",
			"DamageTaken",
			"AvoidableDamageTaken",
			"Deaths",
			"EnemyDamageTaken",
		}
		local groups = ns.DamageMeterLogic.MenuGroups(list)
		assert.are.equal(3, #groups)
		assert.are.same({
			label = "Damage",
			keys = { "DamageDone", "Dps", "DamageTaken", "AvoidableDamageTaken", "EnemyDamageTaken" },
		}, groups[1])
		assert.are.same({ label = "Healing", keys = { "HealingDone", "Hps", "Absorbs" } }, groups[2])
		assert.are.same({ label = "Actions", keys = { "Interrupts", "Dispels", "Deaths" } }, groups[3])
	end)

	it("MenuGroups collects unknown keys into a trailing Other group", function()
		local groups = ns.DamageMeterLogic.MenuGroups({ "DamageDone", "HealingDone", "Interrupts", "Threat" })
		assert.are.equal(4, #groups)
		assert.are.same({ label = "Damage", keys = { "DamageDone" } }, groups[1])
		assert.are.same({ label = "Healing", keys = { "HealingDone" } }, groups[2])
		assert.are.same({ label = "Actions", keys = { "Interrupts" } }, groups[3])
		assert.are.same({ label = "Other", keys = { "Threat" } }, groups[4])

		local onlyOther = ns.DamageMeterLogic.MenuGroups({ "Threat" })
		assert.are.equal(1, #onlyOther)
		assert.are.same({ label = "Other", keys = { "Threat" } }, onlyOther[1])

		assert.are.same({}, ns.DamageMeterLogic.MenuGroups({}))
	end)

	it("ResolveType prefers the key, then the fallback, then the first entry, else nil", function()
		local list3 = { "DamageDone", "Dps", "HealingDone" }
		assert.are.equal("Dps", ns.DamageMeterLogic.ResolveType(list3, "Dps", "DamageDone"))
		assert.are.equal("DamageDone", ns.DamageMeterLogic.ResolveType(list3, "Bogus", "DamageDone"))
		assert.are.equal("HealingDone", ns.DamageMeterLogic.ResolveType({ "HealingDone" }, "Bogus", "DamageDone"))
		assert.is_nil(ns.DamageMeterLogic.ResolveType({}, "Dps", "DamageDone"))
	end)

	it("ValueText formats by kind using the given number formatter", function()
		local fmt = function(v)
			return "<" .. v .. ">"
		end
		assert.are.equal("<1500> (<300>)", ns.DamageMeterLogic.ValueText("amount", 1500, 300, fmt))
		assert.are.equal("<300>", ns.DamageMeterLogic.ValueText("rate", 1500, 300, fmt))
		assert.are.equal("<1500>", ns.DamageMeterLogic.ValueText("count", 1500, 300, fmt))
		assert.are.equal("", ns.DamageMeterLogic.ValueText("deaths", 1500, 300, fmt))
	end)

	it("SegmentLabel defaults the name to Combat and appends a minute:second duration", function()
		assert.are.equal("Hogger (1:05)", ns.DamageMeterLogic.SegmentLabel("Hogger", 65))
		assert.are.equal("Combat (0:42)", ns.DamageMeterLogic.SegmentLabel(nil, 42.7))
		assert.are.equal("Combat", ns.DamageMeterLogic.SegmentLabel("", nil))
		assert.are.equal("Ragnaros (60:00)", ns.DamageMeterLogic.SegmentLabel("Ragnaros", 3600))
	end)

	it("Segments drops entries without a numeric sessionID, sorts descending, and caps the count", function()
		local list = {
			{ sessionID = 3, name = "A", durationSeconds = 10 },
			{ sessionID = 5 },
			{ name = "X" },
			{ sessionID = 4, name = "B", durationSeconds = 70 },
		}
		assert.are.same({
			{ sessionID = 5, label = "Combat" },
			{ sessionID = 4, label = "B (1:10)" },
		}, ns.DamageMeterLogic.Segments(list, 2))
	end)
end)
