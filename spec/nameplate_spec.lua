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
end)
