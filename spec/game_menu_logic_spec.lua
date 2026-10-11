describe("GameMenuLogic", function()
	local ns, L
	local B

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Options/GameMenuLogic.lua"))("MerrinxUI", ns)
		L = ns.GameMenuLogic

		B = {
			{ text = "Options", y = -48 },
			{ text = "Shop", y = -84 },
			{ text = "AddOns", y = -140 },
			{ text = "Edit Mode", y = -176 },
			{ text = "Support", y = -212 },
			{ text = "Macros", y = -248 },
			{ text = "Log Out", y = -304 },
			{ text = "Exit Game", y = -340 },
			{ text = "Return to Game", y = -396 },
		}
	end)

	it("finds AddOns and shifts every entry at or below it", function()
		local idx, shift = L.Plan(B, "AddOns")
		assert.are.equal(3, idx)
		assert.are.same({ 3, 4, 5, 6, 7, 8, 9 }, shift)
	end)

	it("finds AddOns and shifts the same entries when the list is reversed", function()
		local reversed = {}
		for i = #B, 1, -1 do
			table.insert(reversed, B[i])
		end

		local idx, shift = L.Plan(reversed, "AddOns")
		assert.are.equal(7, idx)
		assert.are.same({ 1, 2, 3, 4, 5, 6, 7 }, shift)
	end)

	it("returns nil when the target text isn't present", function()
		assert.is_nil(L.Plan(B, "Nope"))
	end)

	it("returns nil for an empty button list", function()
		assert.is_nil(L.Plan({}, "AddOns"))
	end)

	it("returns nil when the target text is nil", function()
		assert.is_nil(L.Plan(B, nil))
	end)

	it("picks the topmost of two duplicate entries as the target", function()
		local dup = {
			{ text = "Options", y = -48 },
			{ text = "AddOns", y = -500 },
			{ text = "AddOns", y = -140 },
			{ text = "Other", y = -600 },
		}

		local idx = L.Plan(dup, "AddOns")
		assert.are.equal(3, idx)
	end)

	it("never puts an entry without y in shift", function()
		local noY = {
			{ text = "AddOns", y = -100 },
			{ text = "X" },
			{ text = "Y", y = -200 },
		}

		local idx, shift = L.Plan(noY, "AddOns")
		assert.are.equal(1, idx)
		assert.are.same({ 1, 3 }, shift)
	end)
end)
