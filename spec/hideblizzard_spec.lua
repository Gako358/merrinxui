describe("HideBlizzardLogic", function()
	local ns

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/HideBlizzardLogic.lua"))("MerrinxUI", ns)
	end)

	describe("GROUPS", function()
		local EXPECTED = {
			bags = { "BagsBar" },
			micro = { "MicroMenuContainer", "MicroMenu" },
			xp = { "StatusTrackingBarManager" },
			actionBars = {
				"MainActionBar",
				"MultiBarBottomLeft",
				"MultiBarBottomRight",
				"MultiBarRight",
				"MultiBarLeft",
				"MultiBar5",
				"MultiBar6",
				"MultiBar7",
			},
			damageMeter = {},
		}

		it("has exactly the five known groups with the planned frame names", function()
			local seen = {}
			for _, g in ipairs(ns.HideBlizzardLogic.GROUPS) do
				seen[g.key] = true
				assert.are.same(EXPECTED[g.key], g.frames)
				for _, name in ipairs(g.frames) do
					assert.are_not.equal("MainMenuBar", name)
				end
			end
			local count = 0
			for _ in pairs(seen) do
				count = count + 1
			end
			assert.are.equal(5, count)
		end)

		it("unregisters events only for xp", function()
			for _, g in ipairs(ns.HideBlizzardLogic.GROUPS) do
				if g.key == "xp" then
					assert.is_true(g.unregisterEvents)
				else
					assert.is_falsy(g.unregisterEvents)
				end
			end
		end)
	end)

	describe("Groups", function()
		it("returns the enabled profile groups, sorted and unique", function()
			local profile =
				{ enabled = true, bags = true, micro = false, xp = true, actionBars = false, damageMeter = false }
			assert.are.same({ "bags", "xp" }, ns.HideBlizzardLogic.Groups(profile, nil))
		end)

		it("ignores profile keys when enabled is false, but keeps forced groups", function()
			local profile = { enabled = false, bags = true, micro = true }
			assert.are.same({ "xp" }, ns.HideBlizzardLogic.Groups(profile, { xp = true }))
		end)

		it("unions profile and forced without duplicates", function()
			local profile = { enabled = true, bags = true }
			assert.are.same(
				{ "bags", "damageMeter" },
				ns.HideBlizzardLogic.Groups(profile, { bags = true, damageMeter = true })
			)
		end)

		it("ignores unknown keys in profile and forced", function()
			local profile = { enabled = true, bags = true, notAGroup = true }
			assert.are.same({ "bags" }, ns.HideBlizzardLogic.Groups(profile, { alsoNotAGroup = true }))
		end)

		it("accepts a nil forced table", function()
			local profile = { enabled = true, micro = true }
			assert.are.same({ "micro" }, ns.HideBlizzardLogic.Groups(profile, nil))
		end)
	end)

	describe("MeterCVar", function()
		it("want on, current 1, owned false -> set 0, owned true", function()
			local value, owned = ns.HideBlizzardLogic.MeterCVar(true, "1", false)
			assert.are.equal("0", value)
			assert.is_true(owned)
		end)

		it("want on, current 0, owned false -> no set, owned false", function()
			local value, owned = ns.HideBlizzardLogic.MeterCVar(true, "0", false)
			assert.is_nil(value)
			assert.is_false(owned)
		end)

		it("want on, current 0, owned true -> no set, owned true", function()
			local value, owned = ns.HideBlizzardLogic.MeterCVar(true, "0", true)
			assert.is_nil(value)
			assert.is_true(owned)
		end)

		it("want on, current 1, owned true -> set 0, owned true", function()
			local value, owned = ns.HideBlizzardLogic.MeterCVar(true, "1", true)
			assert.are.equal("0", value)
			assert.is_true(owned)
		end)

		it("want off, owned true -> set 1, owned false", function()
			local value, owned = ns.HideBlizzardLogic.MeterCVar(false, "0", true)
			assert.are.equal("1", value)
			assert.is_false(owned)
		end)

		it("want off, owned false -> no set, owned false", function()
			local value, owned = ns.HideBlizzardLogic.MeterCVar(false, "0", false)
			assert.is_nil(value)
			assert.is_false(owned)
		end)

		it("want on, current nil, owned false -> no set, owned false", function()
			local value, owned = ns.HideBlizzardLogic.MeterCVar(true, nil, false)
			assert.is_nil(value)
			assert.is_false(owned)
		end)
	end)
end)
