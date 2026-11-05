describe("EnemySpotterLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/EnemySpotterLogic.lua"))("MerrinxUI", ns)
		L = ns.EnemySpotterLogic
	end)

	it("normalizes names: trims, strips the realm, capitalizes, rejects junk", function()
		assert.are.equal("Gankalot", L.DisplayName("  gANKALOT  "))
		assert.are.equal("Gankalot", L.DisplayName("Gankalot-Nightslayer"))
		assert.are.equal("gankalot", L.Key("GANKALOT-Realm"))
		assert.is_nil(L.DisplayName(""))
		assert.is_nil(L.DisplayName("   "))
		assert.is_nil(L.DisplayName("two words"))
		assert.is_nil(L.DisplayName("-Realm"))
		assert.is_nil(L.Key(nil))
		assert.is_nil(L.Key(42))
	end)

	it("adds, finds and removes kill list entries case-insensitively", function()
		local list = {}
		assert.are.same({ "gankalot", true }, { L.Add(list, "gankalot", 100) })
		assert.are.same({ "gankalot", false }, { L.Add(list, "GANKALOT", 200) })
		assert.are.same({ nil, false }, { L.Add(list, " ", 200) })
		assert.are.same({ name = "Gankalot", added = 100 }, list.gankalot)
		assert.are.equal(list.gankalot, L.Find(list, "Gankalot-Realm"))
		assert.is_nil(L.Find(list, "Other"))
		assert.is_false(L.Remove(list, "Other"))
		assert.is_true(L.Remove(list, "gANKalot"))
		assert.are.same({}, list)
	end)

	it("sorts the kill list by key", function()
		local list = {}
		L.Add(list, "Zed", 1)
		L.Add(list, "abe", 1)
		local sorted = L.Sorted(list)
		assert.are.same({ "abe", "zed" }, { sorted[1].key, sorted[2].key })
		assert.are.equal("Abe", sorted[1].entry.name)
	end)

	it("spots players: new on first sight or after expiry, refresh otherwise", function()
		local nearby = {}
		local entry, isNew, key = L.Spot(nearby, { name = "Rogue", class = "ROGUE", level = 60 }, 10, 60)
		assert.is_true(isNew)
		assert.are.equal("rogue", key)
		assert.are.same({ name = "Rogue", firstSeen = 10, lastSeen = 10, class = "ROGUE", level = 60 }, entry)

		entry, isNew = L.Spot(nearby, { name = "rogue" }, 50, 60)
		assert.is_false(isNew)
		assert.are.same({ name = "Rogue", firstSeen = 10, lastSeen = 50, class = "ROGUE", level = 60 }, entry)

		entry, isNew = L.Spot(nearby, { name = "Rogue", level = 61 }, 200, 60)
		assert.is_true(isNew)
		assert.are.same({ name = "Rogue", firstSeen = 200, lastSeen = 200, level = 61 }, entry)

		assert.are.same({ nil, false }, { L.Spot(nearby, { name = nil }, 1, 60) })
	end)

	it("prunes entries not seen within the expiry", function()
		local nearby = {
			a = { name = "A", lastSeen = 0 },
			b = { name = "B", lastSeen = 50 },
		}
		assert.are.equal(1, L.Prune(nearby, 100, 60))
		assert.is_nil(nearby.a)
		assert.is_not_nil(nearby.b)
	end)

	it("orders rows kill-on-sight first, then most recent, then name", function()
		local nearby = {
			a = { name = "A", lastSeen = 10 },
			b = { name = "B", lastSeen = 30 },
			c = { name = "C", lastSeen = 30 },
			k = { name = "K", lastSeen = 1 },
		}
		local rows = L.Rows(nearby, function(key)
			return key == "k"
		end)
		local keys = {}
		for i, row in ipairs(rows) do
			keys[i] = row.key
		end
		assert.are.same({ "k", "b", "c", "a" }, keys)
		assert.is_true(rows[1].kos)
		assert.is_false(rows[2].kos)
	end)

	it("formats elapsed time compactly", function()
		assert.are.equal("now", L.Ago(0))
		assert.are.equal("now", L.Ago(nil))
		assert.are.equal("12s", L.Ago(12))
		assert.are.equal("3m", L.Ago(200))
		assert.are.equal("2h", L.Ago(7300))
		assert.are.equal("4d", L.Ago(4 * 86400 + 5))
	end)

	it("formats level and detail text", function()
		assert.are.equal("60", L.LevelText(60))
		assert.are.equal("??", L.LevelText(-1))
		assert.are.equal("", L.LevelText(0))
		assert.are.equal("", L.LevelText(nil))
		assert.are.equal("60 Rogue", L.Detail(60, "Rogue"))
		assert.are.equal("Rogue", L.Detail(nil, "Rogue"))
		assert.are.equal("??", L.Detail(-1, nil))
	end)

	it("clamps the scroll offset", function()
		assert.are.equal(0, L.ClampOffset(5, 3, 8))
		assert.are.equal(2, L.ClampOffset(5, 10, 8))
		assert.are.equal(0, L.ClampOffset(-1, 10, 8))
		assert.are.equal(1, L.ClampOffset(1, 10, 8))
	end)
end)
