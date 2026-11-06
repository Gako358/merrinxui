describe("DamageMeterLogic", function()
	local L

	local FULL = {
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

	local function secretSet(...)
		local set = {}
		for i = 1, select("#", ...) do
			set[select(i, ...)] = true
		end
		return function(v)
			return set[v] == true
		end
	end

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/DamageMeterLogic.lua"))("MerrinxUI", ns)
		L = ns.DamageMeterLogic
	end)

	it("Title is the type label, prefixed with Overall for the Overall session", function()
		assert.are.equal("Damage Done", L.Title("DamageDone", false))
		assert.are.equal("Overall DPS", L.Title("Dps", true))
	end)

	it("EnumKey reads a string key from a table, else nil", function()
		local tbl = { Overall = 0, Current = 1 }
		assert.are.equal(0, L.EnumKey(tbl, "Overall"))
		assert.is_nil(L.EnumKey(tbl, "Bogus"))
		assert.is_nil(L.EnumKey(nil, "Current"))
		assert.is_nil(L.EnumKey(tbl, 1))
	end)

	it("IconCoords zooms the coordinate rectangle inward, or passes through nil", function()
		local l, r, t, b = L.IconCoords({ 0, 1, 0, 1 }, 0.06)
		assert.are.equal(0.06, l)
		assert.are.equal(0.94, r)
		assert.are.equal(0.06, t)
		assert.are.equal(0.94, b)
		assert.is_nil(L.IconCoords(nil, 0.06))
	end)

	it("ShortName strips a realm suffix, else passes through or nil", function()
		assert.are.equal("Merrinx", L.ShortName("Merrinx-Firemaw"))
		assert.are.equal("Merrinx", L.ShortName("Merrinx"))
		assert.is_nil(L.ShortName(nil))
	end)

	it("TypeList returns enum string keys sorted by value, else empty", function()
		local enum = {}
		for i, key in ipairs(FULL) do
			enum[key] = i - 1
		end
		assert.are.same(FULL, L.TypeList(enum))
		assert.are.same({}, L.TypeList(nil))
		assert.are.same({}, L.TypeList({ [1] = 2, Foo = "x" }))
	end)

	it("TypeLabel maps known types, humanizes unknown ones, else None", function()
		assert.are.equal("DPS", L.TypeLabel("Dps"))
		assert.are.equal("Avoidable Damage Taken", L.TypeLabel("AvoidableDamageTaken"))
		assert.are.equal("Foo Bar Baz", L.TypeLabel("FooBarBaz"))
		assert.are.equal("None", L.TypeLabel(nil))
	end)

	it("TypeIcon maps types to icon names with a damage fallback", function()
		assert.are.equal("deaths", L.TypeIcon("Deaths"))
		assert.are.equal("enemyTaken", L.TypeIcon("EnemyDamageTaken"))
		assert.are.equal("damage", L.TypeIcon("Threat"))
	end)

	it("TypeKind and BarField classify types", function()
		assert.are.equal("rate", L.TypeKind("Dps"))
		assert.are.equal("count", L.TypeKind("Dispels"))
		assert.are.equal("deaths", L.TypeKind("Deaths"))
		assert.are.equal("amount", L.TypeKind("DamageDone"))
		assert.are.equal("amountPerSecond", L.BarField("rate"))
		assert.are.equal("totalAmount", L.BarField("amount"))
	end)

	it("MenuGroups groups types into Damage/Healing/Actions plus Other", function()
		local groups = L.MenuGroups(FULL)
		assert.are.equal(3, #groups)
		assert.are.same({ "HealingDone", "Hps", "Absorbs" }, groups[2].keys)
		local mixed = L.MenuGroups({ "DamageDone", "Threat" })
		assert.are.same({ label = "Other", keys = { "Threat" } }, mixed[2])
		assert.are.same({}, L.MenuGroups({}))
	end)

	it("TypeMenu nests multi-type groups and flattens single-type ones", function()
		local items = L.TypeMenu({ "DamageDone", "DamageTaken", "HealingDone", "Deaths" }, "DamageTaken")
		assert.are.equal(3, #items)
		assert.are.equal("Damage", items[1].text)
		assert.is_true(items[1].isActive)
		assert.are.same({ key = "DamageDone", text = "Damage Done", isActive = false }, items[1].children[1])
		assert.is_true(items[1].children[2].isActive)
		assert.are.same({ key = "HealingDone", text = "Healing Done", isActive = false }, items[2])
		assert.are.same({ key = "Deaths", text = "Deaths", isActive = false }, items[3])
	end)

	it("ResolveType prefers the key, then the fallback, then the first entry", function()
		local list = { "DamageDone", "Dps", "HealingDone" }
		assert.are.equal("Dps", L.ResolveType(list, "Dps", "DamageDone"))
		assert.are.equal("DamageDone", L.ResolveType(list, "Bogus", "DamageDone"))
		assert.are.equal("HealingDone", L.ResolveType({ "HealingDone" }, "Bogus", "DamageDone"))
		assert.is_nil(L.ResolveType({}, "Dps", "DamageDone"))
	end)

	it("FormatTimer and FormatTimerDecimal format minutes and seconds, 0 for unreadable", function()
		assert.are.equal("1:05", L.FormatTimer(65.9))
		assert.are.equal("60:00", L.FormatTimer(3600))
		assert.are.equal("0:00", L.FormatTimer(nil))
		assert.are.equal("0:00", L.FormatTimer(12, secretSet(12)))
		assert.are.equal("1:05.4", L.FormatTimerDecimal(65.45))
		assert.are.equal("0:00.0", L.FormatTimerDecimal("x"))
	end)

	it("FormatValue follows the number format and clamps a readable rate to 1", function()
		local fmt = function(v)
			return "<" .. tostring(v) .. ">"
		end
		assert.are.equal("<300>", L.FormatValue(0, 1500, 300, fmt))
		assert.are.equal("<1500>", L.FormatValue(1, 1500, 300, fmt))
		assert.are.equal("<1500> (<300>)", L.FormatValue(2, 1500, 300, fmt))
		assert.are.equal("<1500> | <300>", L.FormatValue(3, 1500, 300, fmt))
		assert.are.equal("<1500> (<1>)", L.FormatValue(2, 1500, 0.2, fmt))
		assert.are.equal("<1500>", L.FormatValue(2, 1500, nil, fmt))
		assert.are.equal("<1500> (<0.2>)", L.FormatValue(2, 1500, 0.2, fmt, secretSet(0.2)))
	end)

	it("ValueText picks a text per kind", function()
		local fmt = function(v)
			return "<" .. v .. ">"
		end
		assert.are.equal("<300>", L.ValueText("rate", 2, 1500, 300, fmt))
		assert.are.equal("<1500>", L.ValueText("count", 2, 1500, 300, fmt))
		assert.are.equal("", L.ValueText("deaths", 2, 1500, 300, fmt))
		assert.are.equal("<1500> (<300>)", L.ValueText("amount", 2, 1500, 300, fmt))
	end)

	it("Segments drops entries without a numeric id, keeps the newest max, oldest first", function()
		local list = {
			{ sessionID = 5, durationSeconds = 10 },
			{ sessionID = 3, name = "A", durationSeconds = 10 },
			{ name = "X" },
			{ sessionID = 4, name = "B", durationSeconds = 70 },
		}
		assert.are.same({
			{ sessionID = 4, label = "B", duration = "1:10" },
			{ sessionID = 5, label = "Combat", duration = "0:10" },
		}, L.Segments(list, 2))
	end)

	it("HomeTypes keeps saved indices of offered bookmarks; AddableTypes lists the rest by label", function()
		local offered = { DamageDone = true, Deaths = true, HealingDone = true }
		assert.are.same(
			{ { index = 1, key = "DamageDone" }, { index = 3, key = "Deaths" } },
			L.HomeTypes({ "DamageDone", "Threat", "Deaths" }, offered)
		)
		assert.are.same(
			{ "AvoidableDamageTaken", "HealingDone" },
			L.AddableTypes({ "DamageDone" }, { "HealingDone", "DamageDone", "AvoidableDamageTaken" })
		)
	end)

	it("Total sums readable amounts and refuses secrets; PercentText formats a share", function()
		assert.are.equal(30, L.Total({ 10, 20 }))
		assert.is_nil(L.Total({ 10, 20 }, secretSet(20)))
		assert.are.equal("33.3%", L.PercentText(10, 30))
		assert.is_nil(L.PercentText(10, 0))
	end)

	it("AggregateAttackers merges by name and sorts when readable", function()
		local rows, secret = L.AggregateAttackers({
			{ name = "A", amount = 10, class = "MAGE" },
			{ name = "B", amount = 25 },
			{ name = "A", amount = 20 },
		}, 10)
		assert.is_false(secret)
		assert.are.equal(2, #rows)
		assert.are.equal("A", rows[1].name)
		assert.are.equal(30, rows[1].total)
		assert.are.equal(3, rows[1].perSec)
		assert.are.equal("MAGE", rows[1].class)
	end)

	it("AggregateAttackers passes entries through in order when any value is secret", function()
		local rows, secret = L.AggregateAttackers({
			{ name = "A", amount = 10, perSec = 1 },
			{ name = "A", amount = "s" },
		}, 10, secretSet("s"))
		assert.is_true(secret)
		assert.are.equal(2, #rows)
		assert.are.equal("s", rows[2].total)
	end)

	it("TargetsByPlayer builds sorted per-player target lists; Top trims", function()
		local map = L.TargetsByPlayer({
			{ key = 1, name = "Hogger", attackers = { { name = "Me", amount = 50 }, { name = "You", amount = 5 } } },
			{ key = 2, name = "Rat", attackers = { { name = "Me", amount = 80 }, { name = "Me", amount = 0 } } },
		}, 10)
		assert.are.equal(2, #map.Me)
		assert.are.same({ key = 2, name = "Rat", total = 80, perSec = 8 }, map.Me[1])
		assert.are.equal("Hogger", map.You[1].name)
		assert.are.equal(1, #L.Top(map.Me, 1))
	end)

	it("RecapRows orders oldest first and works out heal, fatal, time and HP", function()
		local rows = L.RecapRows({
			{
				event = "SPELL_DAMAGE",
				spellName = "Fireball",
				timestamp = 10,
				currentHP = 0,
				amount = 50,
				overkill = 5,
			},
			{ event = "SPELL_HEAL", timestamp = 9, currentHP = 60, amount = 10 },
			{ event = "SWING_DAMAGE", timestamp = 8, currentHP = 50, amount = 20 },
		}, 100)
		assert.are.equal(3, #rows)
		assert.are.equal("Melee", rows[1].spellName)
		assert.are.equal(2, rows[1].before)
		assert.are.equal(0.5, rows[1].hpPct)
		assert.are.equal("Heal", rows[2].spellName)
		assert.is_true(rows[2].isHeal)
		assert.is_true(rows[3].isFatal)
		assert.are.equal("Fireball", rows[3].spellName)
	end)

	it("RecapRows keeps secret names and skips arithmetic on secrets", function()
		local rows = L.RecapRows({ { spellName = "s", timestamp = "s", currentHP = 1 } }, "s", secretSet("s"))
		assert.are.equal("s", rows[1].spellName)
		assert.is_nil(rows[1].before)
		assert.is_nil(rows[1].hpPct)
	end)

	it("RecapRows limits rows to the newest maxRows events", function()
		local rows = L.RecapRows({ { timestamp = 3 }, { timestamp = 2 }, { timestamp = 1 } }, 1, nil, 2)
		assert.are.equal(2, #rows)
		assert.are.equal(1, rows[1].before)
	end)

	it("InstanceHidden applies each rule to its instance type", function()
		assert.is_true(L.InstanceHidden({ hideInDungeon = true }, "party"))
		assert.is_false(L.InstanceHidden({ hideInDungeon = true }, "raid"))
		assert.is_true(L.InstanceHidden({ hideInPvP = true }, "arena"))
		assert.is_true(L.InstanceHidden({ hideOutOfInstance = true }, "none"))
		assert.is_true(L.InstanceHidden({ hideInDelve = true }, "scenario", true))
		assert.is_false(L.InstanceHidden({}, "party"))
	end)

	it("Closest picks the nearest rect by edge gap", function()
		local me = { left = 0, right = 10, top = 10, bottom = 0 }
		local others = {
			{ left = 100, right = 110, top = 10, bottom = 0 },
			{ left = 12, right = 20, top = 10, bottom = 0 },
		}
		assert.are.equal(2, L.Closest(me, others))
		assert.is_nil(L.Closest(me, {}))
	end)

	it("SnapPosition snaps edges within the threshold", function()
		local other = { left = 100, right = 200, top = 500, bottom = 400 }
		local left, top = L.SnapPosition(203, 395, 100, 50, other, 6)
		assert.are.equal(200, left)
		assert.are.equal(400, top)
		local l2, t2 = L.SnapPosition(300, 100, 100, 50, other, 6)
		assert.are.equal(300, l2)
		assert.are.equal(100, t2)
		assert.are.equal(150, L.SnapSize(147, 150, 6))
		assert.are.equal(140, L.SnapSize(140, 150, 6))
	end)

	it("NewWindowTop places above, else below when off screen", function()
		assert.are.equal(320, L.NewWindowTop(200, 50, 110, 10, 1000))
		assert.are.equal(40, L.NewWindowTop(950, 50, 110, 10, 1000))
	end)

	it("ClampScroll and WheelScroll keep the view on the row grid", function()
		assert.are.same({ 50, 50 }, { L.ClampScroll(80, 150, 100) })
		assert.are.same({ 0, 0 }, { L.ClampScroll(10, 50, 100) })
		assert.are.equal(40, L.WheelScroll(0, -1, 20, 100))
		assert.are.equal(0, L.WheelScroll(21, 1, 20, 100))
		assert.are.equal(100, L.WheelScroll(90, -1, 20, 100))
	end)

	it("StickyPin pins only when the player's row is out of view", function()
		assert.is_nil(L.StickyPin(2, 20, 18, 0, 100))
		assert.are.equal("bottom", L.StickyPin(10, 20, 18, 0, 100))
		assert.are.equal("top", L.StickyPin(1, 20, 18, 40, 100))
	end)

	it("ValueGradient runs green to red", function()
		assert.are.same({ 0, 1, 0 }, { L.ValueGradient(1, 3) })
		assert.are.same({ 1, 1, 0 }, { L.ValueGradient(2, 3) })
		assert.are.same({ 1, 0, 0 }, { L.ValueGradient(3, 3) })
		assert.are.same({ 0, 1, 0 }, { L.ValueGradient(1, 1) })
	end)

	it("ParseHex and ToHex round-trip colours", function()
		local r, g, b = L.ParseHex("#FF8000")
		assert.are.equal(1, r)
		assert.near(128 / 255, g, 1e-9)
		assert.are.equal(0, b)
		assert.is_nil(L.ParseHex("zzz"))
		assert.are.equal("FF8000", L.ToHex(1, 128 / 255, 0))
	end)

	it("FitText trims whole characters until it fits", function()
		local measure = function(s)
			return #s
		end
		assert.are.equal("Damage", L.FitText("Damage", 10, measure))
		assert.are.equal("Dama...", L.FitText("Damage Done", 7, measure))
		assert.are.equal("D\195\169...", L.FitText("D\195\169gats", 6, measure))
	end)

	it("TimerAnchor maps corners and returns nil for free", function()
		assert.are.same({ "BOTTOMLEFT", "TOPLEFT" }, { L.TimerAnchor("topleft") })
		assert.is_nil(L.TimerAnchor("free"))
	end)
end)
