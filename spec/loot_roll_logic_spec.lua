describe("LootRollLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/LootRollLogic.lua"))("MerrinxUI", ns)
		L = ns.LootRollLogic
	end)

	local function makeSecret()
		local SECRET = {}
		local function isSecret(v)
			return v == SECRET
		end
		return SECRET, isSecret
	end

	it("LR1: Label/tag for every state, and an unknown state gives Choosing", function()
		local expected = {
			[0] = { "Need", "MS" },
			[1] = { "Need", "OS" },
			[2] = { "Transmog", nil },
			[3] = { "Greed", nil },
			[4] = { "Choosing", nil },
			[5] = { "Pass", nil },
		}
		for state, labelTag in pairs(expected) do
			local label, tag = L.Label(state)
			assert.are.equal(labelTag[1], label, state)
			assert.are.equal(labelTag[2], tag, state)
		end
		local label, tag = L.Label(99)
		assert.are.equal("Choosing", label)
		assert.is_nil(tag)
	end)

	it("LR2: ReadRoll maps the fields; a non-table gives nil", function()
		local roll = L.ReadRoll({
			playerName = "A",
			playerGUID = "g1",
			playerClass = "MAGE",
			isSelf = true,
			state = 2,
			isWinner = true,
			roll = 50,
		})
		assert.are.same(
			{ name = "A", guid = "g1", class = "MAGE", state = 2, roll = 50, isWinner = true, isSelf = true },
			roll
		)
		assert.is_nil(L.ReadRoll("x"))
		assert.is_nil(L.ReadRoll(nil))
	end)

	it("LR3: a secret name/roll/state gives nil/nil/NO_ROLL; secret isWinner/isSelf gives false", function()
		local SECRET, isSecret = makeSecret()
		local roll = L.ReadRoll({
			playerName = SECRET,
			playerGUID = "g",
			playerClass = "WARRIOR",
			state = SECRET,
			roll = SECRET,
			isWinner = false,
			isSelf = false,
		}, isSecret)
		assert.is_nil(roll.name)
		assert.is_nil(roll.roll)
		assert.are.equal(L.STATE.NO_ROLL, roll.state)
		assert.are.equal("g", roll.guid)
		assert.are.equal("WARRIOR", roll.class)

		local roll2 = L.ReadRoll({ playerGUID = SECRET, playerClass = SECRET, state = 0 }, isSecret)
		assert.is_nil(roll2.guid)
		assert.is_nil(roll2.class)

		local secretTrue = true
		local function isSecretBool(v)
			return isSecret(v) or v == secretTrue
		end
		local info3 = { playerGUID = "g", state = 0, isWinner = secretTrue, isSelf = secretTrue }
		local ok, roll3 = pcall(L.ReadRoll, info3, isSecretBool)
		assert.is_true(ok)
		assert.is_false(roll3.isWinner)
		assert.is_false(roll3.isSelf)
	end)

	it("LR4: ReadDrop key, chosen/total, winner from info.winner, and the isWinner fallback", function()
		local info = {
			lootListID = 7,
			rollInfos = {
				{ playerName = "A", state = 0, roll = 10, isWinner = false },
				{ playerName = "B", state = 5, isWinner = false },
			},
			winner = { playerName = "A", state = 0, roll = 10, isWinner = true },
		}
		local drop = L.ReadDrop(3, info)
		assert.are.equal("3:7", drop.key)
		assert.are.equal(2, drop.chosen)
		assert.are.equal(2, drop.total)
		assert.are.equal("A", drop.winner.name)
		assert.are.equal(10, drop.winner.roll)

		local info2 = {
			lootListID = 1,
			rollInfos = {
				{ playerName = "C", state = 1, roll = 5, isWinner = false },
				{ playerName = "D", state = 1, roll = 20, isWinner = true },
			},
		}
		local drop2 = L.ReadDrop(9, info2)
		assert.are.equal("D", drop2.winner.name)
		assert.are.equal(20, drop2.winner.roll)
	end)

	it("LR5: a secret or missing lootListID or encounterID gives nil, and a secret allPassed becomes false", function()
		local SECRET, isSecret = makeSecret()
		assert.is_nil(L.ReadDrop(nil, { lootListID = 1 }))
		assert.is_nil(L.ReadDrop(5, {}))
		assert.is_nil(L.ReadDrop(SECRET, { lootListID = 1 }, isSecret))
		assert.is_nil(L.ReadDrop(5, { lootListID = SECRET }, isSecret))

		local secretTrue = true
		local function isSecretBool(v)
			return isSecret(v) or v == secretTrue
		end
		local ok, drop = pcall(L.ReadDrop, 5, { lootListID = 1, allPassed = secretTrue }, isSecretBool)
		assert.is_true(ok)
		assert.is_false(drop.allPassed)
	end)

	it("LR6: SortRolls orders by rank, then roll descending (nil last), then name, deterministically", function()
		local rolls = {
			{ name = "B", state = L.STATE.NEED_MAIN, roll = 50 },
			{ name = "A", state = L.STATE.NEED_MAIN, roll = 80 },
			{ name = "Z", state = L.STATE.NEED_MAIN, roll = nil },
			{ name = "C", state = L.STATE.NEED_OFF, roll = 10 },
			{ name = "D", state = L.STATE.PASS, roll = nil },
			{ name = "E", state = L.STATE.NO_ROLL, roll = nil },
		}
		L.SortRolls(rolls)
		local names = {}
		for _, roll in ipairs(rolls) do
			names[#names + 1] = roll.name
		end
		assert.are.same({ "A", "B", "Z", "C", "D", "E" }, names)

		local tied = {
			{ name = "Charlie", state = L.STATE.GREED, roll = nil },
			{ name = "Alice", state = L.STATE.GREED, roll = nil },
			{ name = "Bob", state = L.STATE.GREED, roll = nil },
		}
		L.SortRolls(tied)
		local tiedNames = {}
		for _, roll in ipairs(tied) do
			tiedNames[#tiedNames + 1] = roll.name
		end
		assert.are.same({ "Alice", "Bob", "Charlie" }, tiedNames)

		L.SortRolls(tied)
		local tiedAgain = {}
		for _, roll in ipairs(tied) do
			tiedAgain[#tiedAgain + 1] = roll.name
		end
		assert.are.same(tiedNames, tiedAgain)
	end)

	it("LR7: IsResolved for winner, for allPassed, and for neither", function()
		assert.is_true(L.IsResolved({ winner = { name = "A" }, allPassed = false }))
		assert.is_true(L.IsResolved({ winner = nil, allPassed = true }))
		assert.is_false(L.IsResolved({ winner = nil, allPassed = false }))
	end)

	it(
		"LR8: IsActive boundary: now == startTime + duration is inactive; nil times stay active until resolved",
		function()
			local drop = { winner = nil, allPassed = false, startTime = 100, duration = 10 }
			assert.is_true(L.IsActive(drop, 109))
			assert.is_false(L.IsActive(drop, 110))

			local noTimes = { winner = nil, allPassed = false, startTime = nil, duration = nil }
			assert.is_true(L.IsActive(noTimes, 999999))

			local resolved = { winner = { name = "A" }, allPassed = false, startTime = nil, duration = nil }
			assert.is_false(L.IsActive(resolved, 1))
		end
	)

	it("LR9: Build ordering and the active subset", function()
		local raw = {
			{
				encounterID = 1,
				drops = {
					{ lootListID = 1, startTime = 100, duration = 10 },
					{
						lootListID = 2,
						startTime = 200,
						duration = 10,
						winner = { playerName = "W", state = 0, roll = 5, isWinner = true },
					},
				},
			},
			{
				encounterID = 2,
				drops = {
					{ lootListID = 1, startTime = 150, duration = 100 },
				},
			},
		}
		local state = L.Build(raw, nil, 105)
		assert.are.equal(3, #state.drops)
		assert.are.equal("1:2", state.drops[1].key)
		assert.are.equal("2:1", state.drops[2].key)
		assert.are.equal("1:1", state.drops[3].key)

		assert.are.equal(2, #state.active)
		assert.are.equal("2:1", state.active[1].key)
		assert.are.equal("1:1", state.active[2].key)
	end)

	it("LR10: Build honours excluded", function()
		local raw = {
			{
				encounterID = 1,
				drops = {
					{ lootListID = 1 },
					{ lootListID = 2 },
				},
			},
		}
		local state = L.Build(raw, { ["1:2"] = true }, nil)
		assert.are.equal(1, state.total)
		assert.are.equal("1:1", state.drops[1].key)
	end)

	it("LR11: wins are keyed by guid, with name fallback", function()
		local raw = {
			{
				encounterID = 1,
				drops = {
					{
						lootListID = 1,
						winner = { playerGUID = "g-1", playerName = "X", state = 0, roll = 10, isWinner = true },
					},
					{ lootListID = 2, winner = { playerName = "Y", state = 0, roll = 20, isWinner = true } },
				},
			},
		}
		local state = L.Build(raw, nil, nil)
		assert.are.equal(1, state.wins["g-1"])
		assert.are.equal(1, state.wins["name:Y"])
	end)

	it("LR12: WinCount excludes the drop's own win", function()
		local raw = {
			{
				encounterID = 1,
				drops = {
					{ lootListID = 1, winner = { playerGUID = "g-1", state = 0, roll = 10, isWinner = true } },
					{ lootListID = 2, winner = { playerGUID = "g-1", state = 0, roll = 20, isWinner = true } },
					{ lootListID = 3 },
				},
			},
		}
		local state = L.Build(raw, nil, nil)
		local dropA, dropC
		for _, drop in ipairs(state.drops) do
			if drop.key == "1:1" then
				dropA = drop
			elseif drop.key == "1:3" then
				dropC = drop
			end
		end
		assert.are.equal(1, L.WinCount(state, dropA, { guid = "g-1" }))
		assert.are.equal(2, L.WinCount(state, dropC, { guid = "g-1" }))
	end)

	it("LR13: CountText for 0, nil and 3", function()
		assert.are.equal("", L.CountText(0))
		assert.are.equal("", L.CountText(nil))
		assert.are.equal("(*3)", L.CountText(3))
	end)

	it("LR14: Snapshot keeps resolved drops and excludes an unresolved one", function()
		local raw = {
			{
				encounterID = 5,
				drops = {
					{ lootListID = 1, winner = { playerName = "A", state = 0, roll = 10, isWinner = true } },
					{ lootListID = 2, allPassed = true },
				},
			},
			{ encounterID = 6, drops = { { lootListID = 1 } } },
		}
		local keys = L.Snapshot(raw)
		assert.is_true(keys["5:1"])
		assert.is_true(keys["5:2"])
		assert.is_nil(keys["6:1"])
		assert.is_nil(keys["7:1"])
	end)

	it("LR15: ShouldReset matrix (same ID, new ID, none/pvp types, nil ID)", function()
		assert.is_false(L.ShouldReset(1, 1, "party"))
		assert.is_true(L.ShouldReset(1, 2, "party"))
		assert.is_true(L.ShouldReset(1, 2, "raid"))
		assert.is_false(L.ShouldReset(1, 2, "none"))
		assert.is_false(L.ShouldReset(1, 2, "pvp"))
		assert.is_false(L.ShouldReset(1, nil, "party"))
		assert.is_true(L.ShouldReset(nil, 5, "raid"))
	end)

	it("LR16: Visible matrix", function()
		assert.is_true(L.Visible({ preview = true }))
		assert.is_true(L.Visible({ pinned = true }))
		assert.is_true(L.Visible({ inGroup = true, active = 1 }))
		assert.is_true(L.Visible({ inGroup = true, lingering = true }))
		assert.is_false(L.Visible({ inGroup = true, active = 0, lingering = false }))
		assert.is_false(L.Visible({ inGroup = false, active = 1 }))
		assert.is_false(L.Visible({ inGroup = true, dismissed = true, active = 1 }))
		assert.is_false(L.Visible({}))
	end)

	it("LR17: ParseSlash", function()
		local action, n = L.ParseSlash("")
		assert.are.equal("toggle", action)
		assert.is_nil(n)

		action, n = L.ParseSlash("test")
		assert.are.equal("test", action)
		assert.are.equal(40, n)

		action, n = L.ParseSlash("test 5")
		assert.are.equal("test", action)
		assert.are.equal(5, n)

		action, n = L.ParseSlash("test 99")
		assert.are.equal("test", action)
		assert.are.equal(40, n)

		action, n = L.ParseSlash("test 0")
		assert.are.equal("test", action)
		assert.are.equal(1, n)

		action = L.ParseSlash("foo")
		assert.are.equal("usage", action)
	end)

	it("LR18: Preview sizes, determinism, one active and two resolved drops", function()
		local p5 = L.Preview(5)
		assert.are.equal(3, #p5.drops)
		assert.are.equal(1, #p5.active)
		assert.are.equal(5, p5.active[1].total)
		assert.are.equal(5, #p5.active[1].rolls)
		assert.are.equal("Player2", p5.drops[2].winner.name)
		assert.are.equal("Player3", p5.drops[3].winner.name)
		assert.are.equal(1, p5.wins["name:Player2"])
		assert.are.equal(1, p5.wins["name:Player3"])

		assert.are.same(p5, L.Preview(5))

		local p40 = L.Preview(40)
		assert.are.equal(40, p40.active[1].total)
		assert.are.equal(40, #p40.active[1].rolls)
	end)

	it("LR19: nil or empty raw gives an empty state", function()
		assert.are.same({ drops = {}, active = {}, wins = {}, total = 0 }, L.Build(nil, nil, nil))
		assert.are.same({ drops = {}, active = {}, wins = {}, total = 0 }, L.Build({}, nil, nil))
	end)

	it("LR20: HasApi with nil, partial and full stub tables", function()
		local ok, missing = L.HasApi(nil)
		assert.is_false(ok)
		assert.are.same(L.API, missing)

		local partial = { GetAllEncounterInfos = function() end, GetSortedDropsForEncounter = function() end }
		local ok2, missing2 = L.HasApi(partial)
		assert.is_false(ok2)
		assert.are.same({ "GetSortedInfoForDrop", "GetLootHistoryTime" }, missing2)

		local full = {}
		for _, name in ipairs(L.API) do
			full[name] = function() end
		end
		local ok3, missing3 = L.HasApi(full)
		assert.is_true(ok3)
		assert.are.same({}, missing3)
	end)

	it("LR21: EnumMatches with correct, wrong and nil enums", function()
		local correct = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
		assert.is_true(L.EnumMatches(correct))

		local wrong = { NeedMainSpec = 1, NeedOffSpec = 0, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
		assert.is_false(L.EnumMatches(wrong))

		assert.is_false(L.EnumMatches(nil))
	end)

	it("LR22: Status for rolling, won, won with no name/roll, and all passed", function()
		local rolling = { winner = nil, allPassed = false, chosen = 2, total = 5 }
		assert.are.equal("Rolling 2/5", L.Status(rolling))

		local won = { winner = { name = "A", roll = 87 }, allPassed = false, chosen = 5, total = 5 }
		assert.are.equal("Won by A 87", L.Status(won))

		local wonUnknown = { winner = { name = nil, roll = nil }, allPassed = false, chosen = 1, total = 1 }
		assert.are.equal("Won by ? -", L.Status(wonUnknown))

		local passed = { winner = nil, allPassed = true, chosen = 0, total = 3 }
		assert.are.equal("All passed", L.Status(passed))
	end)

	it("LR23: DropKey prefers lootListKey, with no fallthrough when it is present but invalid", function()
		local SECRET, isSecret = makeSecret()
		assert.are.equal(4, L.DropKey({ lootListKey = 4 }))
		assert.are.equal(7, L.DropKey({ lootListID = 7 }))
		assert.are.equal(4, L.DropKey({ lootListKey = 4, lootListID = 7 }))
		assert.is_nil(L.DropKey({ lootListKey = SECRET, lootListID = 7 }, isSecret))
		assert.is_nil(L.DropKey({ lootListKey = "4", lootListID = 7 }))
		assert.is_nil(L.DropKey({}))
		assert.is_nil(L.DropKey("x"))
	end)

	it("LR24: ReadDrop/Build/Snapshot use lootListKey as the drop identifier", function()
		local drop = L.ReadDrop(3, { lootListKey = 7 })
		assert.are.equal("3:7", drop.key)
		assert.are.equal(7, drop.lootListID)

		local raw = {
			{
				encounterID = 1,
				drops = {
					{ lootListKey = 1, startTime = 100, duration = 10 },
					{ lootListKey = 2, winner = { playerName = "W", state = 0, roll = 5, isWinner = true } },
				},
			},
		}
		local state = L.Build(raw, nil, 105)
		assert.are.equal(2, #state.drops)
		assert.are.equal(1, #state.active)
		assert.are.equal("1:1", state.active[1].key)

		local keys = L.Snapshot(raw)
		assert.are.same({ ["1:2"] = true }, keys)
	end)

	it("LR25: ItemID extracts the numeric item ID from a hyperlink", function()
		assert.are.equal(19019, L.ItemID("\124cffa335ee\124Hitem:19019:0:0\124h[x]\124h\124r"))
		assert.are.equal(5, L.ItemID("item:5"))
		assert.is_nil(L.ItemID(nil))
		assert.is_nil(L.ItemID("nope"))
		assert.is_nil(L.ItemID(42))
	end)

	it("LR26: MatchRoll prefers an exact link match over a same-item-ID match", function()
		local drops = {
			{ key = "1:2", link = "item:5:2" },
			{ key = "1:1", link = "item:5:1" },
		}
		local roll = { link = "item:5:1", known = {} }
		assert.are.equal("1:1", L.MatchRoll(drops, roll))
	end)

	it("LR27: MatchRoll respects known and resolved status", function()
		local resolved = { key = "1:1", link = "item:5", winner = { name = "A" } }
		local roll = { link = "item:5", known = { ["1:1"] = true } }
		assert.is_nil(L.MatchRoll({ resolved }, roll))

		roll.known = {}
		assert.are.equal("1:1", L.MatchRoll({ resolved }, roll))

		local unresolved = { key = "1:2", link = "item:5:9" }
		assert.are.equal("1:2", L.MatchRoll({ unresolved, resolved }, roll))
	end)

	it("LR28: MatchRoll handles a nil roll link, claimed drops, and ties on the oldest drop", function()
		local drop = { key = "1:1", link = "item:5" }
		assert.is_nil(L.MatchRoll({ drop }, { link = nil, known = {} }))
		assert.is_nil(L.MatchRoll({ drop }, { link = "item:5", known = {} }, { ["1:1"] = true }))

		local a = { key = "1:2", link = "item:5" }
		local b = { key = "1:1", link = "item:5" }
		assert.are.equal("1:1", L.MatchRoll({ a, b }, { link = "item:5", known = {} }))
	end)

	it("LR29: PairRolls keeps valid pairs, fills the rest deterministically, and does not mutate inputs", function()
		local drops = {
			{ key = "1:2", link = "item:5" },
			{ key = "1:1", link = "item:5" },
		}
		local state = { drops = drops }
		local rolls = {
			[10] = { link = "item:5", known = {} },
			[11] = { link = "item:5", known = {} },
		}

		assert.are.same({ [10] = "1:1", [11] = "1:2" }, L.PairRolls(state, rolls, {}))

		local pairs1 = { [11] = "1:1" }
		assert.are.same({ [10] = "1:2", [11] = "1:1" }, L.PairRolls(state, rolls, pairs1))

		local pairs2 = { [11] = "9:9", [12] = "1:1" }
		assert.are.same({ [10] = "1:1", [11] = "1:2" }, L.PairRolls(state, rolls, pairs2))

		assert.are.same({ [11] = "9:9", [12] = "1:1" }, pairs2)
		assert.are.same({
			[10] = { link = "item:5", known = {} },
			[11] = { link = "item:5", known = {} },
		}, rolls)
	end)

	it("LR30: PairRolls matches against resolved drops that are not yet known", function()
		local emptyState = { drops = {} }
		assert.are.same({}, L.PairRolls(emptyState, { [1] = { link = "item:5", known = {} } }, {}))

		local unresolved = { drops = { { key = "1:1", link = "item:5" } } }
		assert.are.same({ [1] = "1:1" }, L.PairRolls(unresolved, { [1] = { link = "item:5", known = {} } }, {}))

		local resolved = { drops = { { key = "1:1", link = "item:5", winner = { name = "A" } } } }
		assert.are.same({ [1] = "1:1" }, L.PairRolls(resolved, { [1] = { link = "item:5", known = {} } }, {}))
	end)

	it("LR31: WithPending prepends pending rolls in descending rollID order and does not mutate state", function()
		local raw = { { encounterID = 1, drops = { { lootListID = 1 } } } }
		local state = L.Build(raw, nil, nil)
		local rolls = {
			[3] = { link = "item:3", known = {} },
			[5] = { link = nil, known = {} },
			[7] = { link = "item:7", known = {} },
		}
		local pairs = { [7] = "1:1" }

		local result = L.WithPending(state, rolls, pairs)

		assert.are.same(
			{ "roll:5", "roll:3", "1:1" },
			{ result.drops[1].key, result.drops[2].key, result.drops[3].key }
		)
		assert.are.same(
			{ "roll:5", "roll:3", "1:1" },
			{ result.active[1].key, result.active[2].key, result.active[3].key }
		)
		assert.are.same({
			key = "roll:5",
			rollID = 5,
			pending = true,
			encounterID = nil,
			lootListID = nil,
			link = nil,
			startTime = nil,
			duration = nil,
			allPassed = false,
			winner = nil,
			rolls = {},
			chosen = 0,
			total = 0,
		}, result.drops[1])
		assert.is_true(rawequal(result.wins, state.wins))
		assert.are.equal(3, result.total)
		assert.are.equal(1, #state.drops)
	end)

	it("LR32: a pending drop reports Rolling and counts as active", function()
		local pending = {
			key = "roll:5",
			rollID = 5,
			pending = true,
			winner = nil,
			allPassed = false,
			chosen = 0,
			total = 0,
		}
		assert.are.equal("Rolling", L.Status(pending))
		assert.is_true(L.IsActive(pending, 1e9))
		assert.is_true(L.Visible({ inGroup = true, active = 1 }))
	end)

	it("LR33: PruneRolls drops only entries whose expiresAt has passed", function()
		local rolls = { [1] = { expiresAt = 100 }, [2] = {}, [3] = { expiresAt = 200 } }
		local result = L.PruneRolls(rolls, 100)
		local keys = {}
		for id in pairs(result) do
			keys[#keys + 1] = id
		end
		table.sort(keys)
		assert.are.same({ 2, 3 }, keys)
		assert.is_true(rawequal(result[2], rolls[2]))
		assert.is_true(rawequal(result[3], rolls[3]))

		local count = 0
		for _ in pairs(rolls) do
			count = count + 1
		end
		assert.are.equal(3, count)
	end)
end)
