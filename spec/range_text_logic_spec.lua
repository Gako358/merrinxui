describe("RangeTextLogic", function()
	local ns

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/RangeTextLogic.lua"))("MerrinxUI", ns)
	end)

	local CLASSES = {
		DRUID = true,
		HUNTER = true,
		MAGE = true,
		PALADIN = true,
		PRIEST = true,
		ROGUE = true,
		SHAMAN = true,
		WARLOCK = true,
		WARRIOR = true,
	}

	it("defines exactly the nine class defaults, each a positive integer", function()
		local count = 0
		for classFile, spellId in pairs(ns.RangeTextLogic.DEFAULT_SPELLS) do
			assert.is_true(CLASSES[classFile])
			assert.is_number(spellId)
			assert.is_true(spellId > 0)
			count = count + 1
		end
		assert.are.equal(9, count)
	end)

	describe("NormalizeSpell", function()
		it("passes through a positive integer", function()
			assert.are.equal(133, ns.RangeTextLogic.NormalizeSpell(133))
		end)

		it("parses a numeric string", function()
			assert.are.equal(133, ns.RangeTextLogic.NormalizeSpell("133"))
		end)

		it("trims a spell name", function()
			assert.are.equal("Fireball", ns.RangeTextLogic.NormalizeSpell("  Fireball "))
		end)

		it("rejects empty, whitespace, zero, negative, fractional, nil and tables", function()
			assert.is_nil(ns.RangeTextLogic.NormalizeSpell(""))
			assert.is_nil(ns.RangeTextLogic.NormalizeSpell("   "))
			assert.is_nil(ns.RangeTextLogic.NormalizeSpell(0))
			assert.is_nil(ns.RangeTextLogic.NormalizeSpell(-5))
			assert.is_nil(ns.RangeTextLogic.NormalizeSpell(1.5))
			assert.is_nil(ns.RangeTextLogic.NormalizeSpell(nil))
			assert.is_nil(ns.RangeTextLogic.NormalizeSpell({}))
		end)
	end)

	describe("ResolveSpell", function()
		it("falls back to the class default for a blank value", function()
			assert.are.equal(133, ns.RangeTextLogic.ResolveSpell(" ", "MAGE"))
		end)

		it("keeps a configured spell name", function()
			assert.are.equal("Frostbolt", ns.RangeTextLogic.ResolveSpell("Frostbolt", "MAGE"))
		end)

		it("resolves to nil for a class with no default", function()
			assert.is_nil(ns.RangeTextLogic.ResolveSpell("", "UNKNOWN"))
		end)

		it("resolves every class default when the spell is empty", function()
			for classFile, spellId in pairs(ns.RangeTextLogic.DEFAULT_SPELLS) do
				assert.are.equal(spellId, ns.RangeTextLogic.ResolveSpell("", classFile))
			end
		end)
	end)

	describe("Classify", function()
		it("maps true, false and nil to states", function()
			assert.are.equal("in", ns.RangeTextLogic.Classify(true))
			assert.are.equal("out", ns.RangeTextLogic.Classify(false))
			assert.are.equal("unknown", ns.RangeTextLogic.Classify(nil))
		end)
	end)

	describe("Color", function()
		it("returns the expected rgb per state", function()
			assert.are.same({ 0, 1, 0 }, { ns.RangeTextLogic.Color("in") })
			assert.are.same({ 1, 0, 0 }, { ns.RangeTextLogic.Color("out") })
			assert.are.same({ 1, 1, 1 }, { ns.RangeTextLogic.Color("unknown") })
		end)
	end)

	describe("FormatRange", function()
		it("formats the known cases", function()
			assert.are.equal("20 - 25", ns.RangeTextLogic.FormatRange(20, 25))
			assert.are.equal("0 - 5", ns.RangeTextLogic.FormatRange(0, 5))
			assert.are.equal("40+", ns.RangeTextLogic.FormatRange(40, nil))
			assert.are.equal("?", ns.RangeTextLogic.FormatRange(nil, nil))
		end)
	end)
end)
