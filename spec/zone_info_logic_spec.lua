describe("ZoneInfoLogic", function()
	local ns, L

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/ZoneInfoLogic.lua"))("MerrinxUI", ns)
		L = ns.ZoneInfoLogic
	end)

	describe("Info", function()
		it("returns the same table as L.ZONES for a known id", function()
			assert.are.equal(L.ZONES[1429], L.Info(1429))
		end)

		it("returns nil for an excluded id", function()
			assert.is_nil(L.Info(1414))
		end)

		it("returns nil for an unknown id", function()
			assert.is_nil(L.Info(9999))
		end)

		it("returns nil for nil", function()
			assert.is_nil(L.Info(nil))
		end)

		it("returns nil for a string id", function()
			assert.is_nil(L.Info("1429"))
		end)
	end)

	describe("Difficulty", function()
		it("returns even inside and at the bounds of the range", function()
			assert.are.equal("even", L.Difficulty(5, 1, 10))
			assert.are.equal("even", L.Difficulty(1, 1, 10))
			assert.are.equal("even", L.Difficulty(10, 1, 10))
			assert.are.equal("even", L.Difficulty(60, 55, 60))
		end)

		it("returns easy above the range", function()
			assert.are.equal("easy", L.Difficulty(11, 1, 10))
			assert.are.equal("easy", L.Difficulty(60, 1, 10))
		end)

		it("returns hard below the range", function()
			assert.are.equal("hard", L.Difficulty(54, 55, 60))
			assert.are.equal("hard", L.Difficulty(1, 10, 20))
		end)

		it("returns nil when any argument is nil", function()
			assert.is_nil(L.Difficulty(nil, 1, 10))
			assert.is_nil(L.Difficulty(30, nil, nil))
		end)
	end)

	describe("LevelText", function()
		it("formats a low-high range", function()
			assert.are.equal("Level 1-10", L.LevelText({ name = "X", low = 1, high = 10 }))
		end)

		it("formats a zone table entry", function()
			assert.are.equal("Level 55-60", L.LevelText(L.ZONES[2482]))
		end)

		it("returns nil when low is missing", function()
			assert.is_nil(L.LevelText({ name = "X", fish = 75 }))
		end)

		it("returns nil for nil", function()
			assert.is_nil(L.LevelText(nil))
		end)
	end)

	describe("FishingText", function()
		it("formats a tier 150 entry", function()
			assert.are.equal("Fishing: 55 (no escapes: 150)", L.FishingText({ fish = 150 }))
		end)

		it("formats a tier 25 entry", function()
			assert.are.equal("Fishing: 1 (no escapes: 25)", L.FishingText({ fish = 25 }))
		end)

		it("formats a zone table entry", function()
			assert.are.equal("Fishing: 1 (no escapes: 75)", L.FishingText(L.ZONES[1432]))
		end)

		it("returns nil for an unknown fish tier", function()
			assert.is_nil(L.FishingText({ fish = 999 }))
		end)

		it("returns nil when fish is missing", function()
			assert.is_nil(L.FishingText({}))
		end)

		it("returns nil for nil", function()
			assert.is_nil(L.FishingText(nil))
		end)
	end)

	describe("Resolve", function()
		it("prefers hovered when it resolves", function()
			assert.are.equal(1429, L.Resolve(1414, 1429))
			assert.are.equal(1429, L.Resolve(1429, 1429))
			assert.are.equal(1429, L.Resolve(1429, nil))
			assert.are.equal(1429, L.Resolve(1429, 9999))
		end)

		it("falls back to shown when hovered does not resolve", function()
			assert.are.equal(1453, L.Resolve(1429, 1453))
		end)

		it("returns nil when neither resolves", function()
			assert.is_nil(L.Resolve(1414, nil))
			assert.is_nil(L.Resolve(1414, 1414))
			assert.is_nil(L.Resolve(1414, 9999))
			assert.is_nil(L.Resolve(nil, nil))
		end)
	end)

	describe("ZONES table invariants", function()
		local EXPECTED_IDS = {
			1411,
			1412,
			1413,
			1416,
			1417,
			1418,
			1419,
			1420,
			1421,
			1422,
			1423,
			1424,
			1425,
			1426,
			1427,
			1428,
			1429,
			1430,
			1431,
			1432,
			1433,
			1434,
			1435,
			1436,
			1437,
			1438,
			1439,
			1440,
			1441,
			1442,
			1443,
			1444,
			1445,
			1446,
			1447,
			1448,
			1449,
			1450,
			1451,
			1452,
			1453,
			1454,
			1455,
			1456,
			1457,
			1458,
			2482,
			2521,
			2548,
			2652,
		}

		local CAPITAL_IDS = { 1453, 1454, 1455, 1456, 1457, 1458 }

		local function isInteger(v)
			return type(v) == "number" and v == math.floor(v)
		end

		it("has exactly 50 entries with the exact key set", function()
			local count = 0
			for id in pairs(L.ZONES) do
				count = count + 1
				assert.is_true(isInteger(id))
			end
			assert.are.equal(50, count)
			assert.are.equal(50, #EXPECTED_IDS)

			for _, id in ipairs(EXPECTED_IDS) do
				assert.is_not_nil(L.ZONES[id], "missing id " .. id)
			end
		end)

		it("excludes 1414 and 1415", function()
			assert.is_nil(L.ZONES[1414])
			assert.is_nil(L.ZONES[1415])
		end)

		it("gives every entry a non-empty string name", function()
			for id, entry in pairs(L.ZONES) do
				assert.are.equal("string", type(entry.name), "id " .. id)
				assert.is_true(#entry.name > 0, "id " .. id)
			end
		end)

		it("gives exactly the capitals nil low and high, and the rest a valid range", function()
			local capitalSet = {}
			for _, id in ipairs(CAPITAL_IDS) do
				capitalSet[id] = true
			end

			for id, entry in pairs(L.ZONES) do
				if capitalSet[id] then
					assert.is_nil(entry.low, "id " .. id)
					assert.is_nil(entry.high, "id " .. id)
				else
					assert.is_true(isInteger(entry.low), "id " .. id)
					assert.is_true(isInteger(entry.high), "id " .. id)
					assert.is_true(entry.low >= 1, "id " .. id)
					assert.is_true(entry.low < entry.high, "id " .. id)
					assert.is_true(entry.high <= 60, "id " .. id)
				end
			end
		end)

		it("gives fish a nil value or a valid FISH_MIN key, with every key used at least once", function()
			local usedKeys = {}
			for id, entry in pairs(L.ZONES) do
				if entry.fish ~= nil then
					assert.is_not_nil(L.FISH_MIN[entry.fish], "id " .. id)
					usedKeys[entry.fish] = true
				end
			end
			for key in pairs(L.FISH_MIN) do
				assert.is_true(usedKeys[key], "unused FISH_MIN key " .. key)
			end
		end)

		it("has no fields other than name, low, high and fish", function()
			local allowed = { name = true, low = true, high = true, fish = true }
			for id, entry in pairs(L.ZONES) do
				for k in pairs(entry) do
					assert.is_true(allowed[k], "id " .. id .. " unknown field " .. tostring(k))
				end
			end
		end)

		it("matches a spot row exactly", function()
			assert.are.same({ name = "Dun Morogh", low = 1, high = 10, fish = 25 }, L.ZONES[1426])
		end)

		it("has no fish for Badlands", function()
			assert.is_nil(L.ZONES[1418].fish)
		end)
	end)
end)
