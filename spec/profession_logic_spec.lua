describe("ProfessionLogic", function()
	local ns, L

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/ProfessionLogic.lua"))("MerrinxUI", ns)
		L = ns.ProfessionLogic
	end)

	it("defines ORDER as the 12 skill line IDs", function()
		assert.are.same({ 171, 164, 333, 202, 165, 197, 185, 129, 356, 182, 186, 393 }, L.ORDER)
	end)

	describe("Tiers / TierIndex / NextTraining", function()
		it("gives index 1 needLevel at rank 0, then learn once level is met", function()
			local T = L.Tiers({ kind = "craft" })
			local t = L.NextTraining(T, 0, 0, 1)
			assert.are.equal(1, t.index)
			assert.are.equal("needLevel", t.state)

			t = L.NextTraining(T, 0, 0, 5)
			assert.are.equal("learn", t.state)
		end)

		it("moves through needLevel, train (capped), needSkill and nil", function()
			local T = L.Tiers({ kind = "craft" })

			local t = L.NextTraining(T, 50, 75, 9)
			assert.are.equal(2, t.index)
			assert.are.equal("needLevel", t.state)
			assert.is_false(t.capped)

			t = L.NextTraining(T, 75, 75, 12)
			assert.are.equal("train", t.state)
			assert.is_true(t.capped)

			t = L.NextTraining(T, 110, 150, 15)
			assert.are.equal("needSkill", t.state)

			t = L.NextTraining(T, 210, 300, 40)
			assert.is_nil(t)
		end)

		it("sets gathering Apprentice to level 1", function()
			assert.are.equal(1, L.Tiers({ kind = "gather" })[1].level)
		end)

		it("applies per-tier train overrides without mutating other tiers", function()
			local tiers = L.Tiers({
				kind = "secondary",
				train = { [3] = { how = "book", text = "Expert First Aid - Under Wraps" } },
			})
			assert.are.equal("book", tiers[3].how)
			assert.are.equal("trainer", tiers[2].how)

			tiers = L.Tiers({ kind = "secondary", train = { [4] = { how = "quest", skill = 225 } } })
			assert.are.equal(225, tiers[4].skill)
		end)

		it("computes TierIndex from maxRank", function()
			local T = L.Tiers({ kind = "craft" })
			assert.are.equal(2, L.TierIndex(T, 160))
			assert.are.equal(0, L.TierIndex(T, 0))
		end)
	end)

	describe("CurrentStep", function()
		it("finds the first step whose to is beyond rank, nil past the last", function()
			local steps = {
				{ from = 1, to = 40, name = "A" },
				{ from = 40, to = 65, name = "B" },
				{ from = 65, to = 90, name = "C" },
			}
			assert.are.equal(1, L.CurrentStep(steps, 0))
			assert.are.equal(1, L.CurrentStep(steps, 39))
			assert.are.equal(2, L.CurrentStep(steps, 40))
			assert.are.equal(3, L.CurrentStep(steps, 89))
			assert.is_nil(L.CurrentStep(steps, 90))
		end)
	end)

	describe("TrainingText", function()
		it("formats learn/train detail, skill and level gates, and nil", function()
			assert.are.equal(
				"Train Journeyman: trainer - capped",
				L.TrainingText({ name = "Journeyman", state = "train", how = "trainer", capped = true })
			)
			assert.are.equal(
				"Train Expert: book X",
				L.TrainingText({ name = "Expert", state = "train", how = "book", text = "X" })
			)
			assert.are.equal("Expert at level 20", L.TrainingText({ name = "Expert", state = "needLevel", level = 20 }))
			assert.are.equal("All ranks trained", L.TrainingText(nil))
		end)
	end)

	describe("FormatStep", function()
		it("formats the range and name, with or without a count", function()
			assert.are.equal(
				"65-90 Elixir of Minor Fortitude x27",
				L.FormatStep({ from = 65, to = 90, name = "Elixir of Minor Fortitude", count = 27 })
			)
			assert.are.equal(
				"65-90 Elixir of Minor Fortitude",
				L.FormatStep({ from = 65, to = 90, name = "Elixir of Minor Fortitude" })
			)
		end)
	end)

	describe("Lines", function()
		it("lists mats then the note, skipping absent fields, empty for an empty step", function()
			assert.are.same(
				{
					"Mats: 54 Earthroot, 27 Peacebloom",
					"n",
				},
				L.Lines({
					mats = { { name = "Earthroot", count = 54 }, { name = "Peacebloom", count = 27 } },
					note = "n",
				})
			)
			assert.are.same({}, L.Lines({}))
		end)
	end)

	describe("Validate", function()
		local function validData()
			return {
				name = "Test",
				skillLine = 171,
				kind = "craft",
				routeEnd = 90,
				steps = {
					{ from = 1, to = 40, name = "A" },
					{ from = 40, to = 65, name = "B" },
					{ from = 65, to = 90, name = "C" },
				},
			}
		end

		it("accepts a valid 3-step file", function()
			assert.is_true(L.Validate(validData()))
		end)

		it("rejects a non-contiguous step with a message naming the step", function()
			local data = validData()
			data.steps[2].from = 45
			local ok, err = L.Validate(data)
			assert.is_false(ok)
			assert.is_not_nil(err:find("step 2"))
		end)

		it("rejects an unknown step key", function()
			local data = validData()
			data.steps[2].zone = "Elwynn Forest"
			local ok, err = L.Validate(data)
			assert.is_false(ok)
			assert.is_not_nil(err:find("unknown key zone"))
		end)

		it("rejects a routeEnd that does not match the last step's to", function()
			local data = validData()
			data.routeEnd = 90
			data.steps[3].to = 85
			local ok = L.Validate(data)
			assert.is_false(ok)
		end)

		it("rejects a skillLine outside ORDER", function()
			local data = validData()
			data.skillLine = 1
			local ok = L.Validate(data)
			assert.is_false(ok)
		end)
	end)
end)
