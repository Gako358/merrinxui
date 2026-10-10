describe("MoverLogic", function()
	local ns

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Util/MoverLogic.lua"))("MerrinxUI", ns)
	end)

	describe("CenterOffset", function()
		it("returns zero offsets when already centered", function()
			assert.are.same({ 0, 0 }, { ns.MoverLogic.CenterOffset(500, 400, 1, 1000, 800, 1) })
		end)

		it("accounts for a different frame scale", function()
			assert.are.same({ 0, 0 }, { ns.MoverLogic.CenterOffset(250, 200, 2, 1000, 800, 1) })
		end)

		it("returns a positive x offset when shifted right", function()
			assert.are.same({ 100, 0 }, { ns.MoverLogic.CenterOffset(600, 400, 1, 1000, 800, 1) })
		end)
	end)
end)
