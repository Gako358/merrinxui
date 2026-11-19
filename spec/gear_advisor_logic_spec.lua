describe("GearAdvisorLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/GearAdvisorLogic.lua"))("MerrinxUI", ns)
		L = ns.GearAdvisorLogic
	end)

	describe("Normalize", function()
		it("picks single-source stats by their literal raw key", function()
			assert.are.same(
				{ str = 5, sta = 3, armor = 120 },
				L.Normalize({ ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 120 })
			)
		end)

		it("combines crit sources with max", function()
			assert.are.same(
				{ crit = 1 },
				L.Normalize({ ITEM_MOD_CRIT_RATING_SHORT = 1, ITEM_MOD_CRIT_MELEE_RATING_SHORT = 1 })
			)
		end)

		it("adds spell power into both spellDamage and healing, while the dedicated keys stay separate", function()
			assert.are.same(
				{ spellDamage = 10, healing = 22 },
				L.Normalize({ ITEM_MOD_SPELL_POWER_SHORT = 10, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 12 })
			)
		end)

		it("returns nil for a non-table or secret input, and {} for unrecognised keys", function()
			assert.is_nil(L.Normalize(nil))
			assert.is_nil(L.Normalize({ ITEM_MOD_STRENGTH_SHORT = 1 }, function()
				return true
			end))
			assert.are.same({}, L.Normalize({ FOO = 1 }))
		end)
	end)

	describe("Score", function()
		it("adds the matching dps weight by equip location", function()
			local stats = { str = 10, dps = 20 }
			local weights = { str = 1, meleeDps = 2, rangedDps = 5 }
			assert.are.equal(50, L.Score(stats, weights, "INVTYPE_2HWEAPON"))
			assert.are.equal(110, L.Score(stats, weights, "INVTYPE_RANGED"))
			assert.are.equal(10, L.Score(stats, weights, "INVTYPE_HEAD"))
		end)
	end)

	describe("CanUse", function()
		it("is false for these class/level/subclass combinations", function()
			assert.is_false(L.CanUse("MAGE", 30, 4, 4, "INVTYPE_CHEST"))
			assert.is_false(L.CanUse("WARRIOR", 39, 4, 4, "INVTYPE_CHEST"))
			assert.is_false(L.CanUse("PRIEST", 10, 2, 8, "INVTYPE_2HWEAPON"))
			assert.is_false(L.CanUse("ROGUE", 20, 4, 6, "INVTYPE_SHIELD"))
			assert.is_false(L.CanUse("SHAMAN", 20, 2, 4, "INVTYPE_WEAPONOFFHAND"))
			assert.is_false(L.CanUse("DRUID", 20, 4, 7, "INVTYPE_RELIC"))
			assert.is_false(L.CanUse("NOPE", 1, 4, 1, "INVTYPE_HEAD"))
		end)

		it("is true for these class/level/subclass combinations", function()
			assert.is_true(L.CanUse("MAGE", 30, 4, 1, "INVTYPE_CLOAK"))
			assert.is_true(L.CanUse("WARRIOR", 40, 4, 4, "INVTYPE_CHEST"))
			assert.is_true(L.CanUse("PRIEST", 10, 2, 19, "INVTYPE_RANGEDRIGHT"))
			assert.is_true(L.CanUse("PALADIN", 20, 4, 6, "INVTYPE_SHIELD"))
			assert.is_true(L.CanUse("ROGUE", 20, 2, 15, "INVTYPE_WEAPONOFFHAND"))
			assert.is_true(L.CanUse("PALADIN", 20, 4, 7, "INVTYPE_RELIC"))
		end)
	end)

	describe("Evaluate / IsUpgrade / FormatDelta", function()
		local ctx

		before_each(function()
			ctx = { class = "WARRIOR", level = 60 }
		end)

		it("picks the weaker empty ring slot as baseline and reports a new upgrade", function()
			local equipped = { [11] = { link = "ring1", stats = { str = 10 }, equipLoc = "INVTYPE_FINGER" } }
			local candidate = { link = "ring2", stats = { str = 15 }, equipLoc = "INVTYPE_FINGER" }
			local weights = { str = 1 }
			local result = L.Evaluate(candidate, equipped, weights, ctx)
			assert.are.equal(0, result.baseline)
			assert.are.equal(12, result.slot)
			assert.is_nil(result.percent)
			assert.are.same({ "+15.0 new", "new" }, { L.FormatDelta(result) })
		end)

		it("picks the weaker scored ring slot and reports a percentage upgrade", function()
			local equipped = {
				[11] = { link = "ring1", stats = { str = 10 }, equipLoc = "INVTYPE_FINGER" },
				[12] = { link = "ring2", stats = { str = 20 }, equipLoc = "INVTYPE_FINGER" },
			}
			local candidate = { link = "ring3", stats = { str = 15 }, equipLoc = "INVTYPE_FINGER" }
			local weights = { str = 1 }
			local result = L.Evaluate(candidate, equipped, weights, ctx)
			assert.are.equal(11, result.slot)
			assert.are.equal(5, result.delta)
			assert.are.equal(50, result.percent)
			assert.are.same({ "+50%", "up" }, { L.FormatDelta(result) })
			result.usable, result.levelOk = true, true
			assert.is_true(L.IsUpgrade(result))
		end)

		it("sums main hand and off hand for a two-hander baseline", function()
			local equipped = {
				[16] = { link = "mh", stats = { str = 10 }, equipLoc = "INVTYPE_WEAPON" },
				[17] = { link = "oh", stats = { str = 15 }, equipLoc = "INVTYPE_WEAPONOFFHAND" },
			}
			local candidate = { link = "2h", stats = { str = 30 }, equipLoc = "INVTYPE_2HWEAPON" }
			local weights = { str = 1 }
			local result = L.Evaluate(candidate, equipped, weights, ctx)
			assert.are.equal(25, result.baseline)
			assert.are.equal(5, result.delta)
			assert.are.equal(20, result.percent)
		end)

		it("blocks an off-hand/shield/holdable candidate when a two-hander is equipped", function()
			local equipped = { [16] = { link = "2h", stats = {}, equipLoc = "INVTYPE_2HWEAPON" } }
			local candidate = { link = "shield", stats = { armor = 5 }, equipLoc = "INVTYPE_SHIELD" }
			local result = L.Evaluate(candidate, equipped, {}, ctx)
			assert.is_true(result.twoHanded)
			assert.is_false(L.IsUpgrade(result))
			local _, kind = L.FormatDelta(result)
			assert.are.equal("blocked", kind)
		end)

		it("marks the candidate as equipped when its link matches a compared slot", function()
			local equipped = { [11] = { link = "ring1", stats = { str = 10 }, equipLoc = "INVTYPE_FINGER" } }
			local candidate = { link = "ring1", stats = { str = 10 }, equipLoc = "INVTYPE_FINGER" }
			local result = L.Evaluate(candidate, equipped, { str = 1 }, ctx)
			assert.is_true(result.equipped)
			local _, kind = L.FormatDelta(result)
			assert.are.equal("equipped", kind)
		end)

		it("appends the required level to FormatDelta text and blocks IsUpgrade when levelOk is false", function()
			local candidate = { link = "x", stats = { str = 10 }, equipLoc = "INVTYPE_HEAD", minLevel = 25 }
			local result = L.Evaluate(candidate, {}, { str = 1 }, { class = "WARRIOR", level = 20 })
			assert.is_false(result.levelOk)
			assert.is_false(L.IsUpgrade(result))
			local text = L.FormatDelta(result)
			assert.is_true(text:sub(-#" (lvl 25)") == " (lvl 25)")
		end)

		it("rounds a negative percent down and reports it as a decrease", function()
			local result = { usable = true, equipped = false, twoHanded = false, delta = -1, percent = -5.6 }
			assert.are.same({ "-6%", "down" }, { L.FormatDelta(result) })
		end)

		it("reports an unchanged score as same", function()
			local result = { usable = true, equipped = false, twoHanded = false, delta = 0, percent = 0 }
			assert.are.same({ "=", "same" }, { L.FormatDelta(result) })
		end)

		it("returns nil for an unscoreable or statless candidate", function()
			assert.is_nil(L.Evaluate({ stats = {}, equipLoc = "INVTYPE_BODY" }, {}, {}, ctx))
			assert.is_nil(L.Evaluate({ stats = {}, equipLoc = "" }, {}, {}, ctx))
			assert.is_nil(L.Evaluate({ stats = {}, equipLoc = nil }, {}, {}, ctx))
			assert.is_nil(L.Evaluate({ stats = nil, equipLoc = "INVTYPE_HEAD" }, {}, {}, ctx))
		end)
	end)

	describe("ValidateSpecs", function()
		local function validFixture()
			local specs = {}
			for _, class in ipairs(L.CLASSES) do
				specs[class] = { { key = "a", name = "A", weights = { str = 1 } } }
			end
			return specs
		end

		it("is true for a valid 9-class fixture", function()
			assert.is_true(L.ValidateSpecs(validFixture()))
		end)

		it("is false for an unknown weight key", function()
			local specs = validFixture()
			specs.WARRIOR[1].weights = { nope = 1 }
			assert.is_false(L.ValidateSpecs(specs))
		end)

		it("is false for a negative weight", function()
			local specs = validFixture()
			specs.WARRIOR[1].weights = { str = -1 }
			assert.is_false(L.ValidateSpecs(specs))
		end)

		it("is false for all-zero weights", function()
			local specs = validFixture()
			specs.WARRIOR[1].weights = { str = 0 }
			assert.is_false(L.ValidateSpecs(specs))
		end)

		it("is false for a duplicate key within a class", function()
			local specs = validFixture()
			specs.WARRIOR[2] = { key = "a", name = "B", weights = { str = 1 } }
			assert.is_false(L.ValidateSpecs(specs))
		end)

		it("is false for a missing class", function()
			local specs = validFixture()
			specs.WARRIOR = nil
			assert.is_false(L.ValidateSpecs(specs))
		end)

		it("is false for an unknown class token", function()
			local specs = validFixture()
			specs.NOPE = { { key = "a", name = "A", weights = { str = 1 } } }
			assert.is_false(L.ValidateSpecs(specs))
		end)
	end)

	describe("SpecByKey", function()
		it("finds a spec by key, and returns nil for an unknown key or nil key", function()
			local list = { { key = "fury", name = "Fury" }, { key = "arms", name = "Arms" } }
			assert.are.equal(list[1], L.SpecByKey(list, "fury"))
			assert.is_nil(L.SpecByKey(list, "nope"))
			assert.is_nil(L.SpecByKey(list, nil))
		end)
	end)
end)
