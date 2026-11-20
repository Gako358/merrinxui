describe("TooltipIdLogic", function()
	local ns, L
	local never, SECRET, isSecret

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Util/TooltipIdLogic.lua"))("MerrinxUI", ns)
		L = ns.TooltipIdLogic

		never = function()
			return false
		end
		SECRET = {}
		isSecret = function(v)
			return v == SECRET
		end
	end)

	it("exposes the item, spell and aura labels", function()
		assert.are.same({ Item = "Item ID", Spell = "Spell ID", UnitAura = "Spell ID" }, L.LABELS)
	end)

	it("formats an item id", function()
		local label, text = L.Line("Item", 19019, never)
		assert.are.equal("Item ID", label)
		assert.are.equal("19019", text)
	end)

	it("formats a spell id", function()
		local label, text = L.Line("Spell", 133, never)
		assert.are.equal("Spell ID", label)
		assert.are.equal("133", text)
	end)

	it("formats a unit aura id as a spell id", function()
		local label, text = L.Line("UnitAura", 1459, never)
		assert.are.equal("Spell ID", label)
		assert.are.equal("1459", text)
	end)

	it("rejects an unknown kind", function()
		assert.is_nil(L.Line("Macro", 5, never))
		assert.is_nil(L.Line(nil, 5, never))
	end)

	it("rejects a nil id", function()
		assert.is_nil(L.Line("Spell", nil, never))
	end)

	it("rejects a secret id without raising, checked before any compare", function()
		assert.is_nil(L.Line("Spell", SECRET, isSecret))
	end)

	it("rejects a non-number, non-positive or non-integer id", function()
		assert.is_nil(L.Line("Item", 0, never))
		assert.is_nil(L.Line("Item", -1, never))
		assert.is_nil(L.Line("Item", 1.5, never))
		assert.is_nil(L.Line("Item", "123", never))
	end)
end)
