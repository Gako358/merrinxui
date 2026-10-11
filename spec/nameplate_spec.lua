describe("NameplateLogic", function()
	local ns

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/NameplateLogic.lua"))("MerrinxUI", ns)
	end)

	describe("Color", function()
		local classColors = {
			MAGE = { r = 0.25, g = 0.78, b = 0.92 },
			WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
		}

		it("is grey when tap-denied, regardless of other inputs", function()
			assert.are.same({ 0.5, 0.5, 0.5 }, { ns.NameplateLogic.Color(5, true, "MAGE", true, classColors) })
			assert.are.same({ 0.5, 0.5, 0.5 }, { ns.NameplateLogic.Color(nil, nil, nil, true, nil) })
		end)

		it("uses the class colour for a player with a known class", function()
			assert.are.same({ 0.25, 0.78, 0.92 }, { ns.NameplateLogic.Color(5, true, "MAGE", false, classColors) })
		end)

		it("falls back to reaction for a player with an unknown or nil class", function()
			assert.are.same({ 1, 0, 0 }, { ns.NameplateLogic.Color(3, true, "DRUID", false, classColors) })
			assert.are.same({ 0, 1, 0 }, { ns.NameplateLogic.Color(5, true, nil, false, classColors) })
		end)

		it("falls back to reaction when classColors is nil", function()
			assert.are.same({ 1, 1, 0 }, { ns.NameplateLogic.Color(4, true, "MAGE", false, nil) })
		end)

		it("colours by reaction when not a player", function()
			assert.are.same({ 1, 0, 0 }, { ns.NameplateLogic.Color(1, false, nil, false, classColors) })
			assert.are.same({ 1, 0, 0 }, { ns.NameplateLogic.Color(3, false, nil, false, classColors) })
			assert.are.same({ 1, 1, 0 }, { ns.NameplateLogic.Color(4, false, nil, false, classColors) })
			assert.are.same({ 0, 1, 0 }, { ns.NameplateLogic.Color(5, false, nil, false, classColors) })
			assert.are.same({ 0, 1, 0 }, { ns.NameplateLogic.Color(8, false, nil, false, classColors) })
		end)

		it("defaults a nil reaction to red", function()
			assert.are.same({ 1, 0, 0 }, { ns.NameplateLogic.Color(nil, false, nil, false, classColors) })
			assert.are.same({ 1, 0, 0 }, { ns.NameplateLogic.Color(nil, nil, nil, nil, nil) })
		end)
	end)

	describe("FormatValue", function()
		it("formats percent", function()
			assert.are.equal("73%", ns.NameplateLogic.FormatValue("percent", "12.3K", 73.4))
			assert.are.equal("0%", ns.NameplateLogic.FormatValue("percent", "x", 0))
			assert.are.equal("100%", ns.NameplateLogic.FormatValue("percent", "x", 100))
		end)

		it("formats number", function()
			assert.are.equal("850", ns.NameplateLogic.FormatValue("number", "850", 12))
		end)

		it("formats both", function()
			assert.are.equal("12.3K (73%)", ns.NameplateLogic.FormatValue("both", "12.3K", 73.4))
		end)

		it("returns nil for none or unknown modes", function()
			assert.is_nil(ns.NameplateLogic.FormatValue("none", "12.3K", 73.4))
			assert.is_nil(ns.NameplateLogic.FormatValue("bogus", "12.3K", 73.4))
		end)
	end)

	describe("PowerColor", function()
		it("returns the fixed colour for each known power token", function()
			assert.are.same({ 0, 0.55, 1 }, { ns.NameplateLogic.PowerColor("MANA") })
			assert.are.same({ 0.9, 0.1, 0.1 }, { ns.NameplateLogic.PowerColor("RAGE") })
			assert.are.same({ 1, 0.85, 0.1 }, { ns.NameplateLogic.PowerColor("ENERGY") })
			assert.are.same({ 1, 0.5, 0.25 }, { ns.NameplateLogic.PowerColor("FOCUS") })
		end)

		it("falls back to grey for nil or unknown tokens", function()
			assert.are.same({ 0.5, 0.5, 0.5 }, { ns.NameplateLogic.PowerColor(nil) })
			assert.are.same({ 0.5, 0.5, 0.5 }, { ns.NameplateLogic.PowerColor("RUNIC_POWER") })
		end)
	end)

	describe("DebuffLayout", function()
		it("lays out TOP anchored icons centred above the plate", function()
			assert.are.same({ "BOTTOM", "TOP", -20, 2 }, { ns.NameplateLogic.DebuffLayout("TOP", 1, 3, 18, 2) })
			assert.are.same({ "BOTTOM", "TOP", 0, 2 }, { ns.NameplateLogic.DebuffLayout("TOP", 2, 3, 18, 2) })
			assert.are.same({ "BOTTOM", "TOP", 20, 2 }, { ns.NameplateLogic.DebuffLayout("TOP", 3, 3, 18, 2) })
			assert.are.same({ "BOTTOM", "TOP", 0, 2 }, { ns.NameplateLogic.DebuffLayout("TOP", 1, 1, 18, 2) })
		end)

		it("lays out BOTTOM anchored icons below the plate", function()
			assert.are.same({ "TOP", "BOTTOM", 0, -2 }, { ns.NameplateLogic.DebuffLayout("BOTTOM", 2, 3, 18, 2) })
		end)

		it("lays out RIGHT anchored icons growing rightward", function()
			assert.are.same({ "LEFT", "RIGHT", 22, 0 }, { ns.NameplateLogic.DebuffLayout("RIGHT", 2, 3, 18, 2) })
		end)

		it("lays out LEFT anchored icons growing leftward", function()
			assert.are.same({ "RIGHT", "LEFT", -42, 0 }, { ns.NameplateLogic.DebuffLayout("LEFT", 3, 3, 18, 2) })
		end)

		it("falls back to TOP layout for unknown anchors", function()
			assert.are.same(
				{ ns.NameplateLogic.DebuffLayout("TOP", 1, 3, 18, 2) },
				{ ns.NameplateLogic.DebuffLayout("bogus", 1, 3, 18, 2) }
			)
		end)
	end)
end)
