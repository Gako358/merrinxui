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

	describe("Snap", function()
		local function rect(left, top, w, h)
			return { left = left, right = left + w, top = top, bottom = top - h }
		end

		it("leaves a rect alone when nothing is within the threshold", function()
			local dx, dy, gx, gy = ns.MoverLogic.Snap(rect(100, 700, 50, 20), {}, 1000, 800, 6)
			assert.are.same({ 0, 0 }, { dx, dy })
			assert.is_nil(gx)
			assert.is_nil(gy)
		end)

		it("snaps the center to the screen center", function()
			local dx, dy, gx, gy = ns.MoverLogic.Snap(rect(472, 413, 50, 20), {}, 1000, 800, 6)
			assert.are.same({ 3, -3, 500, 400 }, { dx, dy, gx, gy })
		end)

		it("aligns a frame's center line with another frame on the same horizontal", function()
			local player = rect(200, 300, 200, 40)
			local dx, dy, gx, gy = ns.MoverLogic.Snap(rect(700, 313, 200, 60), { player }, 2000, 1200, 6)
			assert.are.same({ 0, -3 }, { dx, dy })
			assert.is_nil(gx)
			assert.are.equal(280, gy)
		end)

		it("snaps edges to edges on the vertical", function()
			local other = rect(300, 500, 120, 30)
			local dx, _, gx = ns.MoverLogic.Snap(rect(302, 200, 80, 30), { other }, 2000, 1200, 6)
			assert.are.same({ -2, 300 }, { dx, gx })
		end)

		it("mirrors another frame's center across the screen center", function()
			local player = rect(300, 500, 200, 40)
			local dx, _, gx = ns.MoverLogic.Snap(rect(1503, 900, 200, 40), { player }, 2000, 1200, 6)
			assert.are.same({ -3, 1600 }, { dx, gx })
		end)

		it("prefers the nearest line", function()
			local a = rect(141, 600, 50, 20)
			local b = rect(200, 600, 60, 20)
			local dx = ns.MoverLogic.Snap(rect(196, 300, 50, 20), { a, b }, 2000, 1200, 6)
			assert.are.equal(4, dx)
		end)
	end)

	describe("GridLines", function()
		it("starts at the center and steps outward", function()
			assert.are.same({ 50, 18, 82 }, ns.MoverLogic.GridLines(100, 32))
		end)
	end)

	describe("ParseOffset", function()
		it("reads trimmed numbers", function()
			assert.are.equal(-12.5, ns.MoverLogic.ParseOffset(" -12.5 ", 500))
		end)

		it("clamps to the limit", function()
			assert.are.equal(500, ns.MoverLogic.ParseOffset("9000", 500))
			assert.are.equal(-500, ns.MoverLogic.ParseOffset("-9000", 500))
		end)

		it("rejects text and infinities", function()
			assert.is_nil(ns.MoverLogic.ParseOffset("abc", 500))
			assert.is_nil(ns.MoverLogic.ParseOffset("1e999", 500))
			assert.is_nil(ns.MoverLogic.ParseOffset(nil, 500))
		end)
	end)

	describe("FormatOffset", function()
		it("rounds to whole units", function()
			assert.are.equal("-3, 101", ns.MoverLogic.FormatOffset(-3.4, 100.6))
		end)
	end)
end)
