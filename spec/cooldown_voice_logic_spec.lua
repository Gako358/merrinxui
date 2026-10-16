describe("CooldownVoiceLogic", function()
	local ns, L, NormalizeSpell

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/RangeTextLogic.lua"))("MerrinxUI", ns)
		assert(loadfile("MerrinxUI/Modules/CooldownVoiceLogic.lua"))("MerrinxUI", ns)
		L = ns.CooldownVoiceLogic
		NormalizeSpell = ns.RangeTextLogic.NormalizeSpell
	end)

	it("splits on commas, normalizes, drops nils and duplicates, keeps order", function()
		assert.are.same(
			{ "Fireball", 122, "Frost Nova" },
			L.ParseList("Fireball, 122 ,, Frost Nova, 122, 0, 1.5", NormalizeSpell)
		)
		assert.are.same({}, L.ParseList("", NormalizeSpell))
	end)

	it("resolves tokens into tracked spells and unknown tokens, dropping duplicate ids", function()
		local info = {
			Fireball = { 133, "Fireball" },
			[122] = { 122, "Frost Nova" },
			[133] = { 133, "Fireball" },
		}
		local function getInfo(token)
			local entry = info[token]
			if not entry then
				return nil
			end
			return entry[1], entry[2]
		end

		local result = L.ResolveSpells({ "Fireball", 122, "Nope", 133 }, getInfo)
		assert.are.same({
			tracked = { { id = 133, name = "Fireball" }, { id = 122, name = "Frost Nova" } },
			unknown = { "Nope" },
		}, result)
	end)

	it("transitions ready/cooling per observation", function()
		assert.are.same({ "cooling", false }, { L.Step("ready", "cooling") })
		assert.are.same({ "ready", false }, { L.Step("ready", "gcd") })
		assert.are.same({ "cooling", false }, { L.Step("cooling", "gcd") })
		assert.are.same({ "cooling", false }, { L.Step("cooling", "busy") })
		assert.are.same({ "ready", true }, { L.Step("cooling", "ready") })
		assert.are.same({ "ready", false }, { L.Step("ready", "ready") })
		assert.are.same({ "cooling", false }, { L.Step("cooling", "unknown") })
		assert.are.same({ "ready", false }, { L.Step("ready", "busy") })
	end)

	it("reports whether any state is cooling", function()
		assert.is_false(L.AnyCooling({}))
		assert.is_true(L.AnyCooling({ [1] = "ready", [2] = "cooling" }))
	end)

	it("formats the ready message for 0, 1 or more names", function()
		assert.is_nil(L.Message({}))
		assert.are.equal("A ready", L.Message({ "A" }))
		assert.are.equal("A, B ready", L.Message({ "A", "B" }))
	end)

	it("resolves the stored voice when present, else the first voice, else nil", function()
		assert.are.equal(5, L.ResolveVoice(5, { { voiceID = 2 }, { voiceID = 5 } }))
		assert.are.equal(2, L.ResolveVoice(9, { { voiceID = 2 } }))
		assert.is_nil(L.ResolveVoice(nil, {}))
	end)
end)
