describe("MouseCircleLogic", function()
	local ns

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/MouseCircleLogic.lua"))("MerrinxUI", ns)
	end)

	it("defines exactly thin/normal/thick styles mapped to ring icon keys", function()
		assert.are.same({
			thin = "ringThin",
			normal = "ringNormal",
			thick = "ringThick",
		}, ns.MouseCircleLogic.STYLES)
	end)

	it("defines display names for the same style keys", function()
		assert.are.same({
			thin = "Thin",
			normal = "Normal",
			thick = "Thick",
		}, ns.MouseCircleLogic.STYLE_NAMES)
	end)

	describe("Style", function()
		it("passes through a known style", function()
			assert.are.equal("thin", ns.MouseCircleLogic.Style("thin"))
		end)

		it("falls back to normal for an unknown style", function()
			assert.are.equal("normal", ns.MouseCircleLogic.Style("bogus"))
		end)

		it("falls back to normal for nil", function()
			assert.are.equal("normal", ns.MouseCircleLogic.Style(nil))
		end)
	end)

	describe("Color", function()
		it("uses the class colour when classColor is on and the class is known", function()
			local profile = { classColor = true, color = { r = 0.05, g = 0.82, b = 0.62 } }
			local classColors = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
			assert.are.same({ 0.25, 0.78, 0.92 }, { ns.MouseCircleLogic.Color(profile, "MAGE", classColors) })
		end)

		it("falls back to the custom colour when the class is missing", function()
			local profile = { classColor = true, color = { r = 0.05, g = 0.82, b = 0.62 } }
			local classColors = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
			assert.are.same({ 0.05, 0.82, 0.62 }, { ns.MouseCircleLogic.Color(profile, "WARRIOR", classColors) })
		end)

		it("falls back to the custom colour when the class colour table is nil", function()
			local profile = { classColor = true, color = { r = 0.05, g = 0.82, b = 0.62 } }
			assert.are.same({ 0.05, 0.82, 0.62 }, { ns.MouseCircleLogic.Color(profile, "MAGE", nil) })
		end)

		it("uses the custom colour when classColor is off even if an entry exists", function()
			local profile = { classColor = false, color = { r = 0.05, g = 0.82, b = 0.62 } }
			local classColors = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
			assert.are.same({ 0.05, 0.82, 0.62 }, { ns.MouseCircleLogic.Color(profile, "MAGE", classColors) })
		end)
	end)

	describe("Anchor", function()
		it("maps a cursor position through the UI scale", function()
			assert.are.same({ 1563, 782 }, { ns.MouseCircleLogic.Anchor(1000.4, 500.6, 0.64) })
		end)

		it("is a no-op at scale 1", function()
			assert.are.same({ 10, 10 }, { ns.MouseCircleLogic.Anchor(10, 10, 1) })
		end)
	end)

	describe("Alpha", function()
		it("converts a percent to a fraction", function()
			assert.are.equal(0.8, ns.MouseCircleLogic.Alpha(80))
		end)

		it("clamps above 100", function()
			assert.are.equal(1, ns.MouseCircleLogic.Alpha(150))
		end)

		it("clamps below 0", function()
			assert.are.equal(0, ns.MouseCircleLogic.Alpha(-5))
		end)
	end)
end)
