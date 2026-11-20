describe("SpellTrainingLogic", function()
	local ns, L

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/SpellTrainingLogic.lua"))("MerrinxUI", ns)
		L = ns.SpellTrainingLogic
	end)

	local function worked()
		return {
			spellsByLevel = {
				[1] = { { id = 10, cost = 10 } },
				[4] = { { id = 11, cost = 100, requiredIds = { 10 } }, { id = 20, cost = 100, faction = "Horde" } },
				[6] = { { id = 12, cost = 200, requiredIds = { 11 } } },
				[8] = { { id = 13, cost = 300, requiredTalentId = 99 } },
				[10] = { { id = 14, cost = 500, requiredIds = { 71 } } },
			},
			overriddenGroups = { { 10, 11, 12 } },
		}
	end

	local function knownSet(ids)
		local set = {}
		for _, id in ipairs(ids) do
			set[id] = true
		end
		return function(id)
			return set[id] == true
		end
	end

	it("exposes CLASSES, SOON_LEVELS and CATEGORIES", function()
		assert.are.same(
			{ "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" },
			L.CLASSES
		)
		assert.are.equal(2, L.SOON_LEVELS)
		assert.are.same({
			{ key = "available", label = "Available now" },
			{ key = "missing", label = "Missing requirements" },
			{ key = "soon", label = "Next levels" },
			{ key = "later", label = "Later" },
		}, L.CATEGORIES)
	end)

	describe("Validate", function()
		it("accepts the worked example", function()
			assert.is_true(L.Validate(worked(), "MAGE"))
		end)

		it("accepts a minimal valid table", function()
			assert.is_true(L.Validate({ spellsByLevel = { [1] = { { id = 1, cost = 0 } } } }, "MAGE"))
		end)

		it("rejects an unknown data key", function()
			local data = worked()
			data.extra = true
			local ok, err = L.Validate(data, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: unknown key extra", err)
		end)

		it("rejects an empty spellsByLevel", function()
			local ok, err = L.Validate({ spellsByLevel = {} }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: spellsByLevel must be a non-empty table", err)
		end)

		it("rejects level 0", function()
			local ok, err = L.Validate({ spellsByLevel = { [0] = { { id = 1, cost = 0 } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 0: must be an integer between 1 and 60", err)
		end)

		it("rejects level 61", function()
			local ok, err = L.Validate({ spellsByLevel = { [61] = { { id = 1, cost = 0 } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 61: must be an integer between 1 and 60", err)
		end)

		it("rejects a non-integer level", function()
			local ok, err = L.Validate({ spellsByLevel = { [1.5] = { { id = 1, cost = 0 } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1.5: must be an integer between 1 and 60", err)
		end)

		it("rejects an empty level array", function()
			local ok, err = L.Validate({ spellsByLevel = { [1] = {} } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1: must be a non-empty array", err)
		end)

		it("rejects an unknown entry key", function()
			local ok, err = L.Validate({ spellsByLevel = { [1] = { { id = 1, cost = 0, bogus = true } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1 #1: unknown key bogus", err)
		end)

		it("rejects a negative cost", function()
			local ok, err = L.Validate({ spellsByLevel = { [1] = { { id = 1, cost = -1 } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1 #1: cost must be an integer >= 0", err)
		end)

		it("rejects a non-integer id", function()
			local ok, err = L.Validate({ spellsByLevel = { [1] = { { id = 1.5, cost = 0 } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1 #1: id must be a positive integer", err)
		end)

		it("rejects an empty requiredIds", function()
			local ok, err = L.Validate({ spellsByLevel = { [1] = { { id = 1, cost = 0, requiredIds = {} } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1 #1: requiredIds must be a non-empty array", err)
		end)

		it("rejects a bad faction", function()
			local ok, err =
				L.Validate({ spellsByLevel = { [1] = { { id = 1, cost = 0, faction = "Scourge" } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1 #1: faction must be Alliance or Horde", err)
		end)

		it("rejects a non-number race", function()
			local ok, err = L.Validate({ spellsByLevel = { [1] = { { id = 1, cost = 0, race = "x" } } } }, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1 #1: race must be a positive integer", err)
		end)

		it("rejects a malformed skills item with an extra key", function()
			local ok, err = L.Validate({
				spellsByLevel = { [1] = { { id = 1, cost = 0, skills = { { skill = 40, level = 1, extra = 1 } } } } },
			}, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 1 #1: skills entries must have exactly skill and level", err)
		end)

		it("rejects a duplicate id", function()
			local ok, err = L.Validate({
				spellsByLevel = {
					[1] = { { id = 1, cost = 0 } },
					[2] = { { id = 1, cost = 0 } },
				},
			}, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: level 2 #1: duplicate id 1", err)
		end)

		it("rejects a bad group", function()
			local ok, err = L.Validate({
				spellsByLevel = { [1] = { { id = 1, cost = 0 } } },
				overriddenGroups = { {} },
			}, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: group 1: must be a non-empty array", err)
		end)

		it("rejects the same id in two groups", function()
			local ok, err = L.Validate({
				spellsByLevel = { [1] = { { id = 1, cost = 0 } } },
				overriddenGroups = { { 1, 2 }, { 3, 1 } },
			}, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: group 2: id 1 in more than one group", err)
		end)

		it("rejects the same id twice within one group", function()
			local ok, err = L.Validate({
				spellsByLevel = { [1] = { { id = 1, cost = 0 } } },
				overriddenGroups = { { 1, 1 } },
			}, "MAGE")
			assert.is_false(ok)
			assert.are.equal("MAGE: group 1: id 1 in more than one group", err)
		end)
	end)

	describe("Build", function()
		it("filters by faction and race, keeping nil as a wildcard", function()
			local model = L.Build(worked(), "Alliance", 1)
			local ids = {}
			for _, e in ipairs(model.entries) do
				ids[#ids + 1] = e.id
			end
			assert.are.same({ 10, 11, 12, 13, 14 }, ids)
		end)

		it("keeps an entry whose faction matches", function()
			local model = L.Build(worked(), "Horde", 1)
			local found = false
			for _, e in ipairs(model.entries) do
				if e.id == 20 then
					found = true
				end
			end
			assert.is_true(found)
		end)

		it("keeps an entry whose race matches and drops a mismatched one", function()
			local data = {
				spellsByLevel = {
					[1] = { { id = 1, cost = 0, race = 3 }, { id = 2, cost = 0, race = 5 } },
				},
			}
			local model = L.Build(data, "Alliance", 3)
			assert.are.equal(1, #model.entries)
			assert.are.equal(1, model.entries[1].id)
		end)

		it("sorts entries by level then id ascending", function()
			local data = {
				spellsByLevel = {
					[2] = { { id = 5, cost = 0 }, { id = 1, cost = 0 } },
					[1] = { { id = 9, cost = 0 } },
				},
			}
			local model = L.Build(data, "Alliance", 1)
			local ids = {}
			for _, e in ipairs(model.entries) do
				ids[#ids + 1] = e.id
			end
			assert.are.same({ 9, 1, 5 }, ids)
		end)

		it("does not copy skills into built entries", function()
			local data = {
				spellsByLevel = { [1] = { { id = 1, cost = 0, skills = { { skill = 40, level = 1 } } } } },
			}
			local model = L.Build(data, "Alliance", 1)
			assert.is_nil(model.entries[1].skills)
		end)

		it("builds chains mapping every id in a group to the shared group array", function()
			local model = L.Build(worked(), "Alliance", 1)
			assert.are.equal(model.chains[10], model.chains[11])
			assert.are.equal(model.chains[11], model.chains[12])
			assert.are.same({ 10, 11, 12 }, model.chains[10])
		end)

		it("shares the requiredIds reference without mutating it", function()
			local data = worked()
			local model = L.Build(data, "Alliance", 1)
			for _, e in ipairs(model.entries) do
				if e.id == 11 then
					assert.are.equal(data.spellsByLevel[4][1].requiredIds, e.requiredIds)
				end
			end
		end)
	end)

	describe("IsKnown", function()
		local model

		before_each(function()
			model = L.Build({
				spellsByLevel = {
					[1] = { { id = 10, cost = 0 }, { id = 11, cost = 0 }, { id = 12, cost = 0 } },
				},
				overriddenGroups = { { 10, 11, 12 } },
			}, "Alliance", 1)
		end)

		it("is known directly", function()
			assert.is_true(L.IsKnown(model, 11, knownSet({ 11 })))
		end)

		it("implies the lower ranks are known when a higher rank is known", function()
			assert.is_true(L.IsKnown(model, 10, knownSet({ 12 })))
		end)

		it("does not imply the higher ranks are known from a lower rank", function()
			assert.is_false(L.IsKnown(model, 12, knownSet({ 10 })))
		end)

		it("returns false for an id outside any chain and not known", function()
			assert.is_false(L.IsKnown(model, 999, knownSet({})))
		end)

		it("treats a non-true known() result as not known", function()
			assert.is_false(L.IsKnown(model, 11, function()
				return "x"
			end))
			assert.is_false(L.IsKnown(model, 11, function()
				return nil
			end))
		end)
	end)

	describe("Categorize", function()
		it("matches the worked example at level 4, knowing 11", function()
			local model = L.Build(worked(), "Alliance", 1)
			local groups = L.Categorize(model, 4, knownSet({ 11 }))
			assert.are.equal(2, #groups)
			assert.are.equal("soon", groups[1].key)
			assert.are.equal(1, groups[1].count)
			assert.are.equal(200, groups[1].total)
			assert.are.equal("later", groups[2].key)
			assert.are.equal(1, groups[2].count)
			assert.are.equal(500, groups[2].total)
		end)

		it("matches the worked example at level 4, knowing nothing", function()
			local model = L.Build(worked(), "Alliance", 1)
			local groups = L.Categorize(model, 4, knownSet({}))
			local byKey = {}
			for _, g in ipairs(groups) do
				byKey[g.key] = g
			end
			assert.are.equal(10, byKey.available.entries[1].id)
			assert.are.equal(11, byKey.missing.entries[1].id)
			assert.are.equal(12, byKey.soon.entries[1].id)
			assert.are.equal(14, byKey.later.entries[1].id)
		end)

		it("matches the worked example at level 10", function()
			local model = L.Build(worked(), "Alliance", 1)
			local groups = L.Categorize(model, 10, knownSet({ 12 }))
			assert.are.equal(1, #groups)
			assert.are.equal("missing", groups[1].key)
			assert.are.equal(14, groups[1].entries[1].id)

			groups = L.Categorize(model, 10, knownSet({ 12, 71 }))
			assert.are.equal(1, #groups)
			assert.are.equal("available", groups[1].key)
			assert.are.equal(14, groups[1].entries[1].id)
		end)

		it("includes a talent-gated spell as available once its talent is known", function()
			local model = L.Build(worked(), "Alliance", 1)
			local groups = L.Categorize(model, 8, knownSet({ 99 }))
			local found = false
			for _, g in ipairs(groups) do
				if g.key == "available" then
					for _, e in ipairs(g.entries) do
						if e.id == 13 then
							found = true
						end
					end
				end
			end
			assert.is_true(found)
		end)

		it("follows L.CATEGORIES order and omits empty groups", function()
			local data = {
				spellsByLevel = {
					[1] = { { id = 1, cost = 5 } },
					[2] = { { id = 2, cost = 5 } },
				},
			}
			local model = L.Build(data, "Alliance", 1)
			local groups = L.Categorize(model, 60, knownSet({}))
			assert.are.equal(1, #groups)
			assert.are.equal("available", groups[1].key)
		end)

		it("treats level + SOON_LEVELS as soon and level + SOON_LEVELS + 1 as later", function()
			local data = {
				spellsByLevel = {
					[7] = { { id = 1, cost = 1 } },
					[8] = { { id = 2, cost = 1 } },
				},
			}
			local model = L.Build(data, "Alliance", 1)
			local groups = L.Categorize(model, 5, knownSet({}))
			local byKey = {}
			for _, g in ipairs(groups) do
				byKey[g.key] = g
			end
			assert.are.equal(1, byKey.soon.entries[1].id)
			assert.are.equal(2, byKey.later.entries[1].id)
		end)

		it("sums cost into total and keeps model order within a group", function()
			local data = {
				spellsByLevel = {
					[1] = { { id = 1, cost = 10 }, { id = 2, cost = 20 } },
				},
			}
			local model = L.Build(data, "Alliance", 1)
			local groups = L.Categorize(model, 60, knownSet({}))
			assert.are.equal(2, groups[1].count)
			assert.are.equal(30, groups[1].total)
			assert.are.equal(1, groups[1].entries[1].id)
			assert.are.equal(2, groups[1].entries[2].id)
		end)

		it("satisfies a requiredIds lower chain rank via IsKnown when a higher rank is known", function()
			local data = worked()
			table.insert(data.spellsByLevel[6], { id = 30, cost = 50, requiredIds = { 10 } })
			local model = L.Build(data, "Alliance", 1)
			local groups = L.Categorize(model, 6, knownSet({ 12 }))
			local byKey = {}
			for _, g in ipairs(groups) do
				byKey[g.key] = g
			end
			assert.are.equal(1, byKey.available.count)
			assert.are.equal(30, byKey.available.entries[1].id)
		end)

		it("does not hide a talent-gated entry when only a higher rank of the talent's chain is known", function()
			local data = worked()
			table.insert(data.spellsByLevel[6], { id = 40, cost = 75, requiredTalentId = 10 })
			local model = L.Build(data, "Alliance", 1)
			local groups = L.Categorize(model, 6, knownSet({ 12 }))
			local found = false
			for _, g in ipairs(groups) do
				for _, e in ipairs(g.entries) do
					if e.id == 40 then
						found = true
					end
				end
			end
			assert.is_true(found)
		end)

		it("hides a talent-gated entry when nothing in the talent's chain is known", function()
			local data = worked()
			table.insert(data.spellsByLevel[6], { id = 40, cost = 75, requiredTalentId = 10 })
			local model = L.Build(data, "Alliance", 1)
			local groups = L.Categorize(model, 6, knownSet({}))
			local found = false
			for _, g in ipairs(groups) do
				for _, e in ipairs(g.entries) do
					if e.id == 40 then
						found = true
					end
				end
			end
			assert.is_false(found)
		end)
	end)

	describe("Lines", function()
		it("turns groups into a header line followed by one spell line per entry", function()
			local groups = {
				{
					key = "available",
					label = "Available now",
					count = 2,
					total = 30,
					entries = { { id = 1 }, { id = 2 } },
				},
			}
			local lines = L.Lines(groups)
			assert.are.equal(3, #lines)
			assert.are.same(
				{ kind = "header", key = "available", label = "Available now", count = 2, total = 30 },
				lines[1]
			)
			assert.are.same({ kind = "spell", key = "available", entry = { id = 1 } }, lines[2])
			assert.are.same({ kind = "spell", key = "available", entry = { id = 2 } }, lines[3])
		end)

		it("returns an empty list for no groups", function()
			assert.are.same({}, L.Lines({}))
		end)
	end)

	describe("ClampOffset", function()
		it("clamps a negative offset to 0", function()
			assert.are.equal(0, L.ClampOffset(-5, 10, 3))
		end)

		it("clamps an offset past the end", function()
			assert.are.equal(7, L.ClampOffset(100, 10, 3))
		end)

		it("clamps to 0 when count is less than rows", function()
			assert.are.equal(0, L.ClampOffset(5, 2, 3))
		end)

		it("keeps an offset that fits exactly", function()
			assert.are.equal(4, L.ClampOffset(4, 10, 3))
		end)
	end)
end)
