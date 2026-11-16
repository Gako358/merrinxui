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

	it("S1: ForClass returns the registry list for HUNTER, and empty for unknown or nil", function()
		local keys = {}
		for _, warning in ipairs(L.ForClass("HUNTER")) do
			keys[warning.key] = true
		end
		assert.is_true(keys.arrows)
		assert.is_true(keys.bullets)
		assert.are.same({}, L.ForClass("MAGE"))
		assert.are.same({}, L.ForClass(nil))
	end)

	it(
		"S2: every registry entry has a unique key, a name, a positive threshold, a known evaluator and weapons",
		function()
			local seen = {}
			for class, list in pairs(L.WARNINGS) do
				for _, warning in ipairs(list) do
					assert.is_nil(seen[warning.key], warning.key)
					seen[warning.key] = class
					assert.is_true(type(warning.name) == "string" and #warning.name > 0, warning.key)
					assert.is_true(warning.threshold > 0, warning.key)
					assert.is_function(L.EVALUATORS[warning.kind], warning.key)
					local hasWeapon = false
					for _ in pairs(warning.weapons) do
						hasWeapon = true
					end
					assert.is_true(hasWeapon, warning.key)
				end
			end
		end
	)

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
