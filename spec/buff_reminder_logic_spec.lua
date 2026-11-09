describe("BuffReminderLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/BuffReminderLogic.lua"))("MerrinxUI", ns)
		L = ns.BuffReminderLogic
	end)

	it("lists Mark of the Wild and Thorns for druids", function()
		local keys = {}
		for _, buff in ipairs(L.ForClass("DRUID")) do
			keys[buff.key] = true
		end
		assert.is_true(keys.mark)
		assert.is_true(keys.thorns)
		assert.are.same({}, L.ForClass("NOPE"))
	end)

	it("gives every buff a unique key and at least one spell", function()
		local seen = {}
		for class, list in pairs(L.BUFFS) do
			for _, buff in ipairs(list) do
				assert.is_nil(seen[buff.key], buff.key)
				seen[buff.key] = class
				assert.is_true(#buff.lines > 0 and #buff.lines[1] > 0, buff.key)
			end
		end
	end)

	it("Known accepts any rank of any line", function()
		local buff = { lines = { { 1, 2 }, { 9 } } }
		assert.is_true(L.Known(buff, function(id)
			return id == 2
		end))
		assert.is_true(L.Known(buff, function(id)
			return id == 9
		end))
		assert.is_false(L.Known(buff, function()
			return false
		end))
	end)

	it("Status reads missing, low and ok", function()
		assert.are.same({ "missing", 0 }, { L.Status(nil, 100, 60) })
		assert.are.same({ "ok", nil }, { L.Status({ duration = 0, expirationTime = 0 }, 100, 60) })
		assert.are.same({ "low", 30 }, { L.Status({ duration = 600, expirationTime = 130 }, 100, 60) })
		assert.are.same({ "ok", 500 }, { L.Status({ duration = 600, expirationTime = 600 }, 100, 60) })
	end)

	it("Best prefers ok, then the longest remaining time", function()
		assert.are.same({ "ok", nil }, { L.Best({ { "missing", 0 }, { "ok", nil } }) })
		assert.are.same({ "low", 40 }, { L.Best({ { "low", 10 }, { "low", 40 }, { "missing", 0 } }) })
		assert.are.same({ "ok", 900 }, { L.Best({ { "ok", 300 }, { "ok", 900 } }) })
		assert.are.same({ "missing", 0 }, { L.Best({}) })
	end)

	it("FormatTime shows minutes and seconds", function()
		assert.are.equal("2:05", L.FormatTime(125))
		assert.are.equal("45s", L.FormatTime(45.4))
		assert.are.equal("", L.FormatTime(nil))
	end)

	it("Alerts returns keys that just turned missing or low", function()
		local prev = { mark = "ok", thorns = "low", omen = "missing" }
		local cur = { mark = "low", thorns = "missing", omen = "missing", new = "missing", fine = "ok" }
		local alerts = L.Alerts(prev, cur)
		table.sort(alerts)
		assert.are.same({ "mark", "new", "thorns" }, alerts)
	end)

	it("CastLine prefers the preferred line when it is known", function()
		local buff = { lines = { { 1, 2 }, { 5 }, { 9 } } }
		local isKnown = function(id)
			return id == 5 or id == 9
		end
		assert.are.equal(3, L.CastLine(buff, isKnown, 3))
	end)

	it("CastLine falls back to the first known line when the preferred one is unknown", function()
		local buff = { lines = { { 1, 2 }, { 5 }, { 9 } } }
		local isKnown = function(id)
			return id == 5 or id == 9
		end
		assert.are.equal(2, L.CastLine(buff, isKnown, 1))
	end)

	it("CastLine falls back to the first known line when there is no preferred line", function()
		local buff = { lines = { { 1, 2 }, { 5 }, { 9 } } }
		local isKnown = function(id)
			return id == 5 or id == 9
		end
		assert.are.equal(2, L.CastLine(buff, isKnown, nil))
	end)

	it("CastLine falls back to the first known line when the preferred line does not exist", function()
		local buff = { lines = { { 1, 2 }, { 5 }, { 9 } } }
		local isKnown = function(id)
			return id == 5 or id == 9
		end
		assert.are.equal(2, L.CastLine(buff, isKnown, 7))
	end)

	it("CastLine returns nil when nothing is known", function()
		local buff = { lines = { { 1, 2 }, { 5 }, { 9 } } }
		assert.is_nil(L.CastLine(buff, function()
			return false
		end, nil))
	end)

	it("CastLine resolves the druid mark data to its first line", function()
		local buff
		for _, b in ipairs(L.ForClass("DRUID")) do
			if b.key == "mark" then
				buff = b
			end
		end
		assert.is_not_nil(buff)
		local isKnown = function(id)
			return id == 1126 or id == 21849
		end
		assert.are.equal(1, L.CastLine(buff, isKnown, nil))
	end)
end)
