describe("CastBarLogic", function()
	local L

	local function never()
		return false
	end

	local function secretSet(...)
		local set = {}
		for i = 1, select("#", ...) do
			set[select(i, ...)] = true
		end
		return function(v)
			return set[v] == true
		end
	end

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/CastBarLogic.lua"))("MerrinxUI", ns)
		L = ns.CastBarLogic
	end)

	it("SameCast rejects only a readable, different cast", function()
		assert.is_true(L.SameCast("Cast-1", "Cast-1", never))
		assert.is_false(L.SameCast("Cast-1", "Cast-2", never))
		assert.is_true(L.SameCast(nil, "Cast-2", never))
		assert.is_true(L.SameCast("Cast-1", nil, never))
		assert.is_true(L.SameCast("Cast-1", "S", secretSet("S")))
	end)

	it("CanSwing reads positive speeds and keeps secret ones unknown", function()
		assert.are.same({ main = true, off = true, ranged = false }, L.CanSwing(1.8, nil, never))
		local can = L.CanSwing("S", 0, secretSet("S"))
		assert.is_nil(can.off)
		assert.is_false(can.ranged)
	end)

	it("MergeSwing keeps the last answer for an unknown slot", function()
		local merged = L.MergeSwing({ off = true, ranged = false }, { main = true, off = nil, ranged = true })
		assert.are.same({ main = true, off = true, ranged = true }, merged)
		assert.are.same({ main = true, off = false, ranged = false }, L.MergeSwing({}, { main = true }))
	end)

	it("SwingRows lists main hand, then the enabled slots that can swing", function()
		local can = { main = true, off = true, ranged = true }
		assert.are.same({ "main", "off", "ranged" }, L.SwingRows({ off = true, ranged = true }, can))
		assert.are.same({ "main", "ranged" }, L.SwingRows({ off = false, ranged = true }, can))
		assert.are.same({ "main" }, L.SwingRows({ off = true, ranged = true }, { main = true, off = false }))
	end)

	it("StackHeight stacks rows with gaps and never collapses below one row", function()
		assert.are.equal(28, L.StackHeight(3, 8, 2))
		assert.are.equal(8, L.StackHeight(0, 8, 2))
	end)

	it("SwingProgress clamps to the swing", function()
		assert.are.same({ 0.5, 1 }, { L.SwingProgress(10, 2, 11) })
		assert.are.same({ 1, 0 }, { L.SwingProgress(10, 2, 15) })
		assert.are.same({ 0, 2 }, { L.SwingProgress(10, 2, 9) })
		assert.are.same({ 1, 0 }, { L.SwingProgress(nil, 2, 9) })
	end)
end)
