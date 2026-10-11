describe("DebugLogic", function()
	local ns
	local L
	local S = {}
	local isS = function(v)
		return v == S
	end

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Debug/DebugLogic.lua"))("MerrinxUI", ns)
		L = ns.DebugLogic
	end)

	describe("Describe", function()
		it("marks a secret value", function()
			assert.are.equal("<secret>", L.Describe(S, isS))
		end)

		it("renders nil, false and a number literally", function()
			assert.are.equal("nil", L.Describe(nil, isS))
			assert.are.equal("false", L.Describe(false, isS))
			assert.are.equal("1.5", L.Describe(1.5, isS))
		end)

		it("renders a table as its type name", function()
			assert.are.equal("table", L.Describe({}, isS))
		end)

		it("replaces newlines with spaces and doubles pipes", function()
			assert.are.equal("a||cffb c", L.Describe("a|cffb\nc", isS))
		end)

		it("cuts a long string to MAX_PART chars plus an ellipsis", function()
			local result = L.Describe(string.rep("x", 300), isS)
			assert.are.equal(string.rep("x", 200) .. "...", result)
		end)
	end)

	describe("Join", function()
		it("describes each part up to n, keeping nil gaps", function()
			assert.are.equal("1 nil <secret>", L.Join({ 1, nil, S }, 3, isS))
		end)
	end)

	describe("FormatLine", function()
		it("formats a timestamped source line", function()
			assert.are.equal(
				"[12:00:01] EnemyCooldowns: hit 2139 Counterspell",
				L.FormatLine("12:00:01", "EnemyCooldowns", "hit 2139 Counterspell")
			)
		end)

		it("cuts a long line to MAX_LINE chars", function()
			local line = L.FormatLine("12:00:01", "Source", string.rep("x", 1000))
			assert.are.equal(400, #line)
		end)
	end)

	describe("Push", function()
		it("drops the oldest line when one over cap", function()
			local log = { "a", "b" }
			local removed = L.Push(log, "c", 2)
			assert.are.same({ "b", "c" }, log)
			assert.are.equal(1, removed)
		end)

		it("drops every oldest line needed when far over cap", function()
			local log = { "a", "b", "c", "d" }
			local removed = L.Push(log, "e", 2)
			assert.are.same({ "d", "e" }, log)
			assert.are.equal(3, removed)
		end)
	end)

	describe("Flatten", function()
		it("sorts keys and flattens one level of nested tables", function()
			assert.are.equal(
				"a=x b=1 position.point=CENTER position.x=0",
				L.Flatten({ b = 1, a = "x", position = { x = 0, point = "CENTER" } }, isS)
			)
		end)

		it("marks a secret value", function()
			assert.are.equal("k=<secret>", L.Flatten({ k = S }, isS))
		end)

		it("renders a two-level nested table as its type name", function()
			assert.are.equal("k.sub=table", L.Flatten({ k = { sub = { x = 1 } } }, isS))
		end)
	end)

	describe("RunCheck", function()
		it("returns name, status and the raw values joined into detail", function()
			local r = L.RunCheck({
				name = "x",
				run = function()
					return "PASS", 133, "Fireball"
				end,
			}, {}, isS)
			assert.are.same({ name = "x", status = "PASS", detail = "133 Fireball" }, r)
		end)

		it("fails with the thrown message when run throws", function()
			local r = L.RunCheck({
				name = "x",
				run = function()
					error("boom")
				end,
			}, {}, isS)
			assert.are.equal("FAIL", r.status)
			assert.is_true(r.detail:find("^error: ") ~= nil)
			assert.is_true(r.detail:find("boom", 1, true) ~= nil)
		end)

		it("fails with a secret-safe message when the thrown value is secret", function()
			local r = L.RunCheck({
				name = "x",
				run = function()
					error(S)
				end,
			}, {}, isS)
			assert.are.same({ name = "x", status = "FAIL", detail = "error: <secret>" }, r)
		end)

		it("fails on an unrecognised status string", function()
			local r = L.RunCheck({
				name = "x",
				run = function()
					return "OK"
				end,
			}, {}, isS)
			assert.are.same({ name = "x", status = "FAIL", detail = "invalid status: OK" }, r)
		end)

		it("fails on a secret status", function()
			local r = L.RunCheck({
				name = "x",
				run = function()
					return S
				end,
			}, {}, isS)
			assert.are.same({ name = "x", status = "FAIL", detail = "invalid status: <secret>" }, r)
		end)

		it("fails on a malformed check", function()
			local r = L.RunCheck("x", {}, isS)
			assert.are.equal("FAIL", r.status)
			assert.are.equal("malformed check", r.detail)
		end)

		it("fails on a nil status", function()
			local r = L.RunCheck({
				name = "x",
				run = function()
					return nil
				end,
			}, {}, isS)
			assert.are.same({ name = "x", status = "FAIL", detail = "invalid status: nil" }, r)
		end)

		it("escapes a pipe in the check name", function()
			local r = L.RunCheck({
				name = "a|b",
				run = function()
					return "PASS"
				end,
			}, {}, isS)
			assert.are.equal("a||b", r.name)
		end)

		it("joins trailing nil raw values into the detail", function()
			local r = L.RunCheck({
				name = "x",
				run = function()
					return "INFO", 1, nil
				end,
			}, {}, isS)
			assert.are.same({ name = "x", status = "INFO", detail = "1 nil" }, r)
		end)
	end)

	describe("RunChecks", function()
		it("returns an empty array for nil checks", function()
			assert.are.same({}, L.RunChecks("RangeText", nil, {}, isS))
		end)
	end)

	describe("RunSource", function()
		it("fails with the thrown message when the provider throws", function()
			local results = L.RunSource("Mover", function()
				error("bad index")
			end, {}, isS)
			assert.are.equal(1, #results)
			assert.are.equal("Mover", results[1].source)
			assert.are.equal("checks", results[1].name)
			assert.are.equal("FAIL", results[1].status)
			assert.is_true(results[1].detail:find("bad index", 1, true) ~= nil)
		end)

		it("fails when the provider doesn't return a table", function()
			local results = L.RunSource("Mover", function()
				return 5
			end, {}, isS)
			assert.are.same({ { source = "Mover", name = "checks", status = "FAIL", detail = "not a table" } }, results)
		end)

		it("runs the provider's checks", function()
			local results = L.RunSource("Mover", function()
				return { {
					name = "a",
					run = function()
						return "INFO", true
					end,
				} }
			end, {}, isS)
			assert.are.same({ { source = "Mover", name = "a", status = "INFO", detail = "true" } }, results)
		end)

		it("escapes a pipe in the source", function()
			local results = L.RunSource("M|x", function()
				return { {
					name = "a",
					run = function()
						return "PASS"
					end,
				} }
			end, {}, isS)
			assert.are.equal("M||x", results[1].source)
		end)
	end)

	describe("FormatResult", function()
		it("formats a result with a detail", function()
			assert.are.equal(
				"FAIL EnemyCooldowns/spell table: mismatched 6346 180000 30000",
				L.FormatResult({
					status = "FAIL",
					source = "EnemyCooldowns",
					name = "spell table",
					detail = "mismatched 6346 180000 30000",
				})
			)
		end)

		it("omits the colon when the detail is empty", function()
			assert.are.equal(
				"PASS RangeText/spell",
				L.FormatResult({ status = "PASS", source = "RangeText", name = "spell", detail = "" })
			)
		end)
	end)

	describe("Summary", function()
		it("counts results by status", function()
			local text, counts = L.Summary({ { status = "PASS" }, { status = "PASS" }, { status = "FAIL" } })
			assert.are.equal("3 checks: 2 PASS, 1 FAIL, 0 SKIP, 0 INFO", text)
			assert.are.same({ PASS = 2, FAIL = 1, SKIP = 0, INFO = 0, total = 3 }, counts)
		end)
	end)

	describe("SortSources", function()
		it("puts Debug first then sorts the rest alphabetically", function()
			local sorted = L.SortSources({ "RangeText", "Debug", "EnemyCooldowns" })
			assert.are.same({ "Debug", "EnemyCooldowns", "RangeText" }, sorted)
		end)
	end)
end)
