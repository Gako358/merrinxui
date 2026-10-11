describe("EnemyCooldownLogic", function()
	local ns, L

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/EnemyCooldownLogic.lua"))("MerrinxUI", ns)
		L = ns.EnemyCooldownLogic
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

	describe("SPELLS", function()
		it("has unique positive integer ids, a valid class, category and cd", function()
			local seen = {}
			for _, entry in ipairs(L.SPELLS) do
				assert.is_number(entry.id)
				assert.is_true(entry.id > 0)
				assert.are.equal(entry.id, math.floor(entry.id))
				assert.is_nil(seen[entry.id])
				seen[entry.id] = true

				assert.is_true(entry.class == "ANY" or CLASSES[entry.class] == true)
				assert.is_true(L.CATEGORIES[entry.category] == true)

				assert.is_number(entry.cd)
				assert.is_true(entry.cd > 0)
				assert.are.equal(entry.cd, math.floor(entry.cd))
			end
		end)
	end)

	describe("BuildIndex/Lookup", function()
		local kick = { id = 1766, class = "ROGUE", category = "interrupt", cd = 10 }
		local cs = { id = 2139, class = "MAGE", category = "interrupt", cd = 30 }
		local van = { id = 1856, class = "ROGUE", category = "defensive", cd = 300 }
		local names = { [1766] = "Kick", [1856] = "Vanish" }
		local idx

		before_each(function()
			idx = L.BuildIndex({ kick, cs, van }, function(id)
				return names[id]
			end)
		end)

		it("matches by id first, then by name", function()
			assert.are.equal(kick, L.Lookup(idx, 1766, "Kick"))
			assert.are.equal(kick, L.Lookup(idx, 1769, "Kick"))
			assert.are.equal(cs, L.Lookup(idx, 2139, nil))
			assert.is_nil(L.Lookup(idx, 9, "Fireball"))
			assert.is_nil(L.Lookup(idx, 9, nil))
		end)

		it("keeps the first entry on a duplicate name", function()
			local a = { id = 1, class = "ANY", category = "racial", cd = 60 }
			local b = { id = 2, class = "ANY", category = "racial", cd = 60 }
			local dupIdx = L.BuildIndex({ a, b }, function()
				return "X"
			end)
			assert.are.equal(a, dupIdx.byName.X)
		end)
	end)

	describe("Record/Active/Prune", function()
		local kick = { id = 1766, class = "ROGUE", category = "interrupt", cd = 10 }
		local van = { id = 1856, class = "ROGUE", category = "defensive", cd = 300 }
		local st

		before_each(function()
			st = {}
		end)

		it("walks through the recast and prune sequence", function()
			L.Record(st, "G", kick, 100)
			local active = L.Active(st, "G", 105, 4)
			assert.are.equal(1, #active)
			assert.are.equal(kick, active[1].entry)
			assert.are.equal(100, active[1].start)
			assert.are.equal(110, active[1].expires)

			L.Record(st, "G", van, 101)
			active = L.Active(st, "G", 105, 4)
			assert.are.equal(2, #active)
			assert.are.equal(kick, active[1].entry)
			assert.are.equal(van, active[2].entry)

			local capped = L.Active(st, "G", 105, 1)
			assert.are.equal(1, #capped)
			assert.are.equal(kick, capped[1].entry)
			assert.are.same({}, L.Active(st, "G", 105, 0))

			active = L.Active(st, "G", 110, 4)
			assert.are.equal(1, #active)
			assert.are.equal(van, active[1].entry)

			assert.are.same({}, L.Active(st, "none", 105, 4))

			L.Record(st, "G", kick, 108)
			assert.are.equal(118, st.G[kick.id].expires)
			active = L.Active(st, "G", 109, 4)
			assert.are.equal(2, #active)
			local kickCount, kickExpires = 0, nil
			for _, rec in ipairs(active) do
				if rec.entry == kick then
					kickCount = kickCount + 1
					kickExpires = rec.expires
				end
			end
			assert.are.equal(1, kickCount)
			assert.are.equal(118, kickExpires)

			local changed = L.Prune(st, 118)
			assert.are.same({ G = true }, changed)
			assert.is_not_nil(st.G)
			active = L.Active(st, "G", 118, 4)
			assert.are.equal(1, #active)
			assert.are.equal(van, active[1].entry)

			changed = L.Prune(st, 401)
			assert.are.same({ G = true }, changed)
			assert.is_nil(st.G)

			changed = L.Prune(st, 500)
			assert.are.same({}, changed)
		end)

		it("orders equal expires by entry id ascending", function()
			local a = { id = 5, class = "ANY", category = "racial", cd = 10 }
			local b = { id = 3, class = "ANY", category = "racial", cd = 10 }
			L.Record(st, "G", a, 100)
			L.Record(st, "G", b, 100)
			local active = L.Active(st, "G", 105, 4)
			assert.are.equal(b, active[1].entry)
			assert.are.equal(a, active[2].entry)
		end)
	end)

	describe("Layout", function()
		it("matches the documented formulas", function()
			assert.are.same({ "BOTTOM", "TOP", -22, 4 }, { L.Layout("TOP", 1, 3, 20, 2, 0, 4) })
			assert.are.same({ "BOTTOM", "TOP", 0, 4 }, { L.Layout("TOP", 2, 3, 20, 2, 0, 4) })
			assert.are.same({ "BOTTOM", "TOP", 22, 4 }, { L.Layout("TOP", 3, 3, 20, 2, 0, 4) })
			assert.are.same({ "BOTTOM", "TOP", 0, 0 }, { L.Layout("TOP", 1, 1, 20, 2, 0, 0) })
			assert.are.same({ "LEFT", "RIGHT", 27, 0 }, { L.Layout("RIGHT", 2, 3, 20, 2, 5, 0) })
			assert.are.same({ "RIGHT", "LEFT", -49, 0 }, { L.Layout("LEFT", 3, 3, 20, 2, -5, 0) })
			assert.are.same({ L.Layout("TOP", 1, 3, 20, 2, 0, 4) }, { L.Layout("bogus", 1, 3, 20, 2, 0, 4) })
		end)
	end)
end)
