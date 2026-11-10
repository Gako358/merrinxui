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
		it("has unique positive integer ids, a valid class and cd", function()
			local seen = {}
			for _, entry in ipairs(L.SPELLS) do
				assert.is_number(entry.id)
				assert.is_true(entry.id > 0)
				assert.are.equal(entry.id, math.floor(entry.id))
				assert.is_nil(seen[entry.id])
				seen[entry.id] = true

				assert.is_true(entry.class == "ANY" or CLASSES[entry.class] == true)
				assert.is_nil(entry.category)

				assert.is_number(entry.cd)
				assert.is_true(entry.cd > 0)
				assert.are.equal(entry.cd, math.floor(entry.cd))
			end
		end)

		it("includes Psychic Scream at a 30 s cooldown", function()
			local found
			for _, entry in ipairs(L.SPELLS) do
				if entry.id == 8122 then
					found = entry
				end
			end
			assert.is_not_nil(found)
			assert.are.equal(30, found.cd)
		end)
	end)

	describe("BuildIndex/Lookup", function()
		local kick = { id = 1766, class = "ROGUE", cd = 10 }
		local cs = { id = 2139, class = "MAGE", cd = 30 }
		local van = { id = 1856, class = "ROGUE", cd = 300 }
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
			local a = { id = 1, class = "ANY", cd = 60 }
			local b = { id = 2, class = "ANY", cd = 60 }
			local dupIdx = L.BuildIndex({ a, b }, function()
				return "X"
			end)
			assert.are.equal(a, dupIdx.byName.X)
		end)
	end)

	describe("Record/Active/Prune", function()
		local kick = { id = 1766, class = "ROGUE", cd = 10 }
		local van = { id = 1856, class = "ROGUE", cd = 300 }
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
			local a = { id = 5, class = "ANY", cd = 10 }
			local b = { id = 3, class = "ANY", cd = 10 }
			L.Record(st, "G", a, 100)
			L.Record(st, "G", b, 100)
			local active = L.Active(st, "G", 105, 4)
			assert.are.equal(b, active[1].entry)
			assert.are.equal(a, active[2].entry)
		end)

		it("filters by the selected table before sort and cap", function()
			L.Record(st, "G", kick, 100)
			L.Record(st, "G", van, 100)

			local active = L.Active(st, "G", 105, 4, { [1766] = true })
			assert.are.equal(1, #active)
			assert.are.equal(kick, active[1].entry)

			assert.are.same({}, L.Active(st, "G", 105, 4, {}))

			-- kick (1766) expires first and would win a cap of 1 if the cap ran before the
			-- selected-table filter; only van (1856) is selected here, so a cap-first
			-- implementation would cap to kick and then filter it away, returning nothing.
			active = L.Active(st, "G", 105, 1, { [1856] = true })
			assert.are.equal(1, #active)
			assert.are.equal(van, active[1].entry)

			active = L.Active(st, "G", 105, 4, nil)
			assert.are.equal(2, #active)
		end)
	end)

	describe("IdentityKey", function()
		local SECRET = {}
		local function isSecret(v)
			return v == SECRET
		end

		it("prefers guid, then name(-realm), then unit", function()
			assert.are.same(
				{ "guid:Player-1-0A", "guid" },
				{ L.IdentityKey("Player-1-0A", "Bob", nil, "nameplate1", isSecret) }
			)
			assert.are.same({ "name:Bob", "name" }, { L.IdentityKey(SECRET, "Bob", nil, "nameplate1", isSecret) })
			assert.are.same(
				{ "name:Bob-Stormrage", "name" },
				{ L.IdentityKey(SECRET, "Bob", "Stormrage", "nameplate1", isSecret) }
			)
			assert.are.same({ "name:Bob", "name" }, { L.IdentityKey(SECRET, "Bob", "", "nameplate1", isSecret) })
			assert.are.same({ "name:Bob", "name" }, { L.IdentityKey(SECRET, "Bob", SECRET, "nameplate1", isSecret) })
			assert.are.same(
				{ "unit:nameplate3", "unit" },
				{ L.IdentityKey(SECRET, SECRET, nil, "nameplate3", isSecret) }
			)
			assert.are.same({ "unit:nameplate3", "unit" }, { L.IdentityKey(nil, nil, nil, "nameplate3", isSecret) })
			assert.are.same({ "unit:nameplate3", "unit" }, { L.IdentityKey(nil, "", nil, "nameplate3", isSecret) })
		end)

		it("checks isSecret before any type() or comparison", function()
			-- type() cannot be intercepted, but an implementation that swaps the order to
			-- `type(v) == "string" and not isSecret(v)` short-circuits on a non-string table
			-- without ever calling isSecret(v); the erroring metamethods also catch any
			-- comparison/concat/length/index of the value that happens before isSecret runs.
			local function secretSentinel()
				return setmetatable({}, {
					__eq = function()
						error("compared secret value before isSecret check")
					end,
					__concat = function()
						error("concatenated secret value before isSecret check")
					end,
					__len = function()
						error("took length of secret value before isSecret check")
					end,
					__index = function()
						error("indexed into secret value before isSecret check")
					end,
				})
			end

			local function trackingIsSecret(checked)
				return function(v)
					if v ~= nil then
						checked[v] = true
					end
					return type(v) == "table"
				end
			end

			local guidChecked = {}
			local secretGuid = secretSentinel()
			L.IdentityKey(secretGuid, "Bob", nil, "nameplate1", trackingIsSecret(guidChecked))
			assert.is_true(guidChecked[secretGuid])

			local nameChecked = {}
			local secretName = secretSentinel()
			L.IdentityKey(nil, secretName, nil, "nameplate1", trackingIsSecret(nameChecked))
			assert.is_true(nameChecked[secretName])

			local realmChecked = {}
			local secretRealm = secretSentinel()
			L.IdentityKey(nil, "Bob", secretRealm, "nameplate1", trackingIsSecret(realmChecked))
			assert.is_true(realmChecked[secretRealm])
		end)
	end)

	describe("ClassLabel", function()
		it("labels classes and the racial fallback", function()
			assert.are.equal("Priest", L.ClassLabel("PRIEST"))
			assert.are.equal("Warlock", L.ClassLabel("WARLOCK"))
			assert.are.equal("Racial", L.ClassLabel("ANY"))
		end)
	end)

	describe("IconOffset/RowWidth", function()
		it("matches the documented formulas", function()
			assert.are.equal(2, L.IconOffset(1, 20, 2, 2))
			assert.are.equal(46, L.IconOffset(3, 20, 2, 2))

			assert.are.equal(0, L.RowWidth(0, 20, 2, 2))
			assert.are.equal(22, L.RowWidth(1, 20, 2, 2))
			assert.are.equal(66, L.RowWidth(3, 20, 2, 2))
		end)
	end)

	describe("Audit", function()
		it("reports unresolved, duplicate, mismatched and unknown-cd ids", function()
			local spells = { { id = 1, cd = 10 }, { id = 2, cd = 20 }, { id = 3, cd = 30 } }
			local names = { [1] = "A", [2] = "A" }
			local base = { [1] = 10000, [2] = 5000 }
			local result = L.Audit(spells, function(id)
				return names[id]
			end, function(id)
				return base[id]
			end)
			assert.are.same({
				unresolved = { 3 },
				duplicates = { 2 },
				mismatched = { { id = 2, expected = 20000, actual = 5000 } },
				unknownCd = { 3 },
			}, result)
		end)

		it("returns all four lists empty for no spells", function()
			local result = L.Audit({}, function()
				return nil
			end, function()
				return nil
			end)
			assert.are.same({ unresolved = {}, duplicates = {}, mismatched = {}, unknownCd = {} }, result)
		end)

		it("reports every id as unknownCd when getBaseCooldownMs always returns nil", function()
			local spells = { { id = 1, cd = 10 }, { id = 2, cd = 20 }, { id = 3, cd = 30 } }
			local names = { [1] = "A", [2] = "B", [3] = "C" }
			local result = L.Audit(spells, function(id)
				return names[id]
			end, function()
				return nil
			end)
			assert.are.same({ unresolved = {}, duplicates = {}, mismatched = {}, unknownCd = { 1, 2, 3 } }, result)
		end)
	end)
end)
