describe("WarningLogic", function()
	local L
	local R, P

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/WarningLogic.lua"))("MerrinxUI", ns)
		L = ns.WarningLogic

		R = { resting = true, weaponClass = 2, weaponSubclass = 2, ammoClass = 6, ammoSubclass = 2, ammoCount = 120 }
		P = { warnings = {}, thresholds = {} }
	end)

	local function findKey(warnings, key)
		for _, warning in ipairs(warnings) do
			if warning.key == key then
				return warning
			end
		end
		return nil
	end

	it("S1: ForClass returns the registry list per class, and empty for unknown or nil", function()
		local keys = {}
		for _, warning in ipairs(L.ForClass("HUNTER")) do
			keys[warning.key] = true
		end
		assert.is_true(keys.arrows)
		assert.is_true(keys.bullets)

		local mageKeys = {}
		for _, warning in ipairs(L.ForClass("MAGE")) do
			mageKeys[#mageKeys + 1] = warning.key
		end
		assert.are.same({ "conjuredFood", "conjuredWater" }, mageKeys)

		assert.are.same({}, L.ForClass("WARRIOR"))
		assert.are.same({}, L.ForClass(nil))
	end)

	it("S2: every registry entry is well-formed for its kind", function()
		local seen = {}
		for class, list in pairs(L.WARNINGS) do
			for _, warning in ipairs(list) do
				assert.is_nil(seen[warning.key], warning.key)
				seen[warning.key] = class
				assert.is_true(type(warning.name) == "string" and #warning.name > 0, warning.key)
				assert.is_true(warning.threshold > 0, warning.key)
				assert.is_true(
					type(warning.max) == "number"
						and warning.max == math.floor(warning.max)
						and warning.max >= warning.threshold,
					warning.key
				)
				assert.is_function(L.EVALUATORS[warning.kind], warning.key)

				if warning.kind == "ammo" then
					assert.is_true(type(warning.ammo) == "number", warning.key)
					local hasWeapon = false
					for _ in pairs(warning.weapons) do
						hasWeapon = true
					end
					assert.is_true(hasWeapon, warning.key)
				elseif warning.kind == "items" then
					assert.is_true(type(warning.items) == "table" and #warning.items > 0, warning.key)
					for _, id in ipairs(warning.items) do
						assert.is_true(type(id) == "number" and id > 0 and id == math.floor(id), warning.key)
					end
				end
			end
		end
	end)

	it("S3: Evaluate is active when the equipped ammo is below the threshold", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		assert.are.same({ true, 120 }, { L.Evaluate(A, R, 200) })
	end)

	it("S4: Evaluate is strict, so a count equal to the threshold is inactive", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		R.ammoCount = 200
		assert.are.same({ false, 200 }, { L.Evaluate(A, R, 200) })
	end)

	it("S5: Evaluate is inactive when not resting", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		R.resting = false
		assert.are.same({ false, nil }, { L.Evaluate(A, R, 200) })
	end)

	it("S6: a crossbow counts for arrows the same as a bow", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		R.weaponSubclass = 18
		assert.are.same({ true, 120 }, { L.Evaluate(A, R, 200) })
	end)

	it("S7: a gun with bullets is active for bullets and inactive for arrows", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		local B = findKey(L.ForClass("HUNTER"), "bullets")
		R.weaponSubclass = 3
		R.ammoSubclass = 3
		R.ammoCount = 50
		assert.are.same({ true, 50 }, { L.Evaluate(B, R, 200) })
		assert.are.same({ false, nil }, { L.Evaluate(A, R, 200) })
	end)

	it("S8: a bow with bullets equipped counts arrows as 0", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		R.ammoSubclass = 3
		R.ammoCount = 500
		assert.are.same({ true, 0 }, { L.Evaluate(A, R, 200) })
	end)

	it("S9: a bow with no ammo fields counts arrows as 0", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		R.ammoClass, R.ammoSubclass, R.ammoCount = nil, nil, nil
		assert.are.same({ true, 0 }, { L.Evaluate(A, R, 200) })
	end)

	it("S10: thrown, wands and no ranged weapon never warn", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		local B = findKey(L.ForClass("HUNTER"), "bullets")
		for _, weaponSubclass in ipairs({ 16, 19 }) do
			R.weaponSubclass = weaponSubclass
			assert.are.same({ false, nil }, { L.Evaluate(A, R, 200) })
			assert.are.same({ false, nil }, { L.Evaluate(B, R, 200) })
		end
		R.weaponSubclass = nil
		assert.are.same({ false, nil }, { L.Evaluate(A, R, 200) })
		assert.are.same({ false, nil }, { L.Evaluate(B, R, 200) })
		R.weaponSubclass = 2
		R.weaponClass = 4
		assert.are.same({ false, nil }, { L.Evaluate(A, R, 200) })
		assert.are.same({ false, nil }, { L.Evaluate(B, R, 200) })
		R.weaponClass = nil
		assert.are.same({ false, nil }, { L.Evaluate(A, R, 200) })
		assert.are.same({ false, nil }, { L.Evaluate(B, R, 200) })
	end)

	it("S11: Evaluate is inactive for an unknown kind", function()
		assert.are.same({ false, nil }, { L.Evaluate({ kind = "nope" }, R, 200) })
	end)

	it("S12: Settings honours the toggle and the threshold override", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")

		P.warnings.arrows = false
		assert.are.same({ false, 200 }, { L.Settings(A, P) })

		P.warnings.arrows = nil
		P.thresholds.arrows = 500
		assert.are.same({ true, 500 }, { L.Settings(A, P) })

		P.thresholds.arrows = "x"
		assert.are.same({ true, 200 }, { L.Settings(A, P) })

		assert.are.same({ true, 200 }, { L.Settings(A, {}) })
	end)

	it("S12b: Settings does not raise when warnings or thresholds are not tables", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		assert.are.same({ true, 200 }, { L.Settings(A, { warnings = 5, thresholds = true }) })
	end)

	it("S13: Active returns exactly the active entries for the base reading", function()
		local active = L.Active(L.ForClass("HUNTER"), R, P)
		assert.are.equal(1, #active)
		assert.are.equal("arrows", active[1].warning.key)
		assert.are.equal(120, active[1].count)
	end)

	it("S13b: Active does not raise when warnings or thresholds are not tables", function()
		local active = L.Active(L.ForClass("HUNTER"), R, { warnings = 5, thresholds = true })
		assert.are.equal(1, #active)
		assert.are.equal("arrows", active[1].warning.key)
		assert.are.equal(120, active[1].count)
	end)

	it("S14: Active is empty when the warning is disabled", function()
		P.warnings.arrows = false
		assert.are.same({}, L.Active(L.ForClass("HUNTER"), R, P))
	end)

	it("S15: Active is empty when the threshold is below the count", function()
		P.thresholds.arrows = 100
		assert.are.same({}, L.Active(L.ForClass("HUNTER"), R, P))
	end)

	it("S16: Active does not mutate its inputs", function()
		local reading =
			{ resting = true, weaponClass = 2, weaponSubclass = 2, ammoClass = 6, ammoSubclass = 2, ammoCount = 120 }
		local profile = { warnings = {}, thresholds = {} }
		L.Active(L.ForClass("HUNTER"), reading, profile)
		assert.are.same(
			{ resting = true, weaponClass = 2, weaponSubclass = 2, ammoClass = 6, ammoSubclass = 2, ammoCount = 120 },
			reading
		)
		assert.are.same({ warnings = {}, thresholds = {} }, profile)
	end)

	it("S16b: Active for MAGE does not mutate its inputs", function()
		local reading = { resting = false, inCombat = false, itemCounts = { [8079] = 5 } }
		local profile = { warnings = {}, thresholds = {} }
		L.Active(L.ForClass("MAGE"), reading, profile)
		assert.are.same({ resting = false, inCombat = false, itemCounts = { [8079] = 5 } }, reading)
		assert.are.same({ warnings = {}, thresholds = {} }, profile)
	end)

	it("S19: Evaluate is active for conjured water below the threshold regardless of resting", function()
		local W = findKey(L.ForClass("MAGE"), "conjuredWater")
		local reading = { resting = false, inCombat = false, itemCounts = { [8079] = 5 } }
		assert.are.same({ true, 5 }, { L.Evaluate(W, reading, 20) })
	end)

	it("S20: Evaluate sums every conjured rank in itemCounts", function()
		local W = findKey(L.ForClass("MAGE"), "conjuredWater")
		local reading = { resting = false, inCombat = false, itemCounts = { [8077] = 3, [8079] = 4 } }
		assert.are.same({ true, 7 }, { L.Evaluate(W, reading, 20) })
	end)

	it("S21: Evaluate is strict for conjured items, so a count equal to the threshold is inactive", function()
		local W = findKey(L.ForClass("MAGE"), "conjuredWater")
		local reading = { resting = false, inCombat = false, itemCounts = { [8079] = 20 } }
		assert.are.same({ false, 20 }, { L.Evaluate(W, reading, 20) })
	end)

	it("S22: Evaluate is inactive while in combat", function()
		local W = findKey(L.ForClass("MAGE"), "conjuredWater")
		local reading = { resting = false, inCombat = true, itemCounts = { [8079] = 5 } }
		assert.are.same({ false, nil }, { L.Evaluate(W, reading, 20) })
	end)

	it("S23: Evaluate treats a missing or malformed itemCounts as zero, ignoring bad entries", function()
		local W = findKey(L.ForClass("MAGE"), "conjuredWater")
		assert.are.same({ true, 0 }, { L.Evaluate(W, { resting = false, inCombat = false }, 20) })
		assert.are.same({ true, 0 }, { L.Evaluate(W, { resting = false, inCombat = false, itemCounts = false }, 20) })
		assert.are.same(
			{ true, 0 },
			{ L.Evaluate(W, { resting = false, inCombat = false, itemCounts = { [8079] = "x" } }, 20) }
		)
		assert.are.same(
			{ true, 0 },
			{ L.Evaluate(W, { resting = false, inCombat = false, itemCounts = { [8079] = -5 } }, 20) }
		)
	end)

	it("S24: Evaluate for conjured food ignores conjured water ids", function()
		local F = findKey(L.ForClass("MAGE"), "conjuredFood")
		local reading = { resting = false, inCombat = false, itemCounts = { [8079] = 40 } }
		assert.are.same({ true, 0 }, { L.Evaluate(F, reading, 20) })
	end)

	it("S25: Evaluate for ammo warnings is unaffected by inCombat", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		R.inCombat = true
		assert.are.same({ true, 120 }, { L.Evaluate(A, R, 200) })
	end)

	it("S26: ItemIds collects unique item ids in first-seen order", function()
		local expected = {}
		for _, id in ipairs(L.CONJURED_FOOD) do
			expected[#expected + 1] = id
		end
		for _, id in ipairs(L.CONJURED_WATER) do
			expected[#expected + 1] = id
		end
		assert.are.same(expected, L.ItemIds(L.ForClass("MAGE")))
		assert.are.same({}, L.ItemIds(L.ForClass("HUNTER")))
		assert.are.same({ 1, 2, 3 }, L.ItemIds({ { items = { 1, 2 } }, { items = { 2, 3 } }, { key = "x" } }))
	end)

	it("S27: Active for MAGE honours per-warning toggles and threshold overrides", function()
		local reading = { resting = false, inCombat = false, itemCounts = { [5349] = 5, [5350] = 5 } }
		local profile = { warnings = {}, thresholds = {} }
		local active = L.Active(L.ForClass("MAGE"), reading, profile)
		assert.are.equal(2, #active)

		profile.warnings.conjuredWater = false
		active = L.Active(L.ForClass("MAGE"), reading, profile)
		assert.are.equal(1, #active)
		assert.are.equal("conjuredFood", active[1].warning.key)

		profile.warnings.conjuredWater = nil
		profile.thresholds.conjuredFood = 3
		active = L.Active(L.ForClass("MAGE"), reading, profile)
		assert.are.equal(1, #active)
		assert.are.equal("conjuredWater", active[1].warning.key)
	end)

	it("S28: Format renders conjured food and water warning lines", function()
		local F = findKey(L.ForClass("MAGE"), "conjuredFood")
		local W = findKey(L.ForClass("MAGE"), "conjuredWater")
		assert.are.equal("Low conjured food: 5", L.Format(F, 5))
		assert.are.equal("Low conjured water: 0", L.Format(W, 0))
	end)

	it("S17: Preview returns every enabled entry at its threshold", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		local preview =
			L.Preview(L.ForClass("HUNTER"), { warnings = { bullets = false }, thresholds = { arrows = 300 } })
		assert.are.same({ { warning = A, count = 300 } }, preview)
	end)

	it("S18: Format renders the warning line", function()
		local A = findKey(L.ForClass("HUNTER"), "arrows")
		local B = findKey(L.ForClass("HUNTER"), "bullets")
		assert.are.equal("Low arrows: 120", L.Format(A, 120))
		assert.are.equal("Low bullets: 0", L.Format(B, 0))
	end)
end)
