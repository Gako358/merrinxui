describe("GearAdvisorData", function()
	local ns, SPECS
	local registered

	local WEIGHT_KEYS = {
		"str",
		"agi",
		"sta",
		"int",
		"spi",
		"ap",
		"rap",
		"crit",
		"hit",
		"spellDamage",
		"healing",
		"mp5",
		"def",
		"armor",
		"block",
		"dodge",
		"parry",
		"meleeDps",
		"rangedDps",
	}

	local EXPECTED = {
		WARRIOR = {
			{ key = "arms", name = "Arms" },
			{ key = "fury", name = "Fury" },
			{ key = "protection", name = "Protection" },
		},
		PALADIN = {
			{ key = "holy", name = "Holy" },
			{ key = "protection", name = "Protection" },
			{ key = "retribution", name = "Retribution" },
		},
		HUNTER = {
			{ key = "beastMastery", name = "Beast Mastery" },
			{ key = "marksmanship", name = "Marksmanship" },
			{ key = "survival", name = "Survival" },
		},
		ROGUE = {
			{ key = "assassination", name = "Assassination" },
			{ key = "combat", name = "Combat" },
			{ key = "subtlety", name = "Subtlety" },
		},
		PRIEST = {
			{ key = "discipline", name = "Discipline" },
			{ key = "holy", name = "Holy" },
			{ key = "shadow", name = "Shadow" },
		},
		SHAMAN = {
			{ key = "elemental", name = "Elemental" },
			{ key = "enhancement", name = "Enhancement" },
			{ key = "restoration", name = "Restoration" },
		},
		MAGE = {
			{ key = "arcane", name = "Arcane" },
			{ key = "fire", name = "Fire" },
			{ key = "frost", name = "Frost" },
		},
		WARLOCK = {
			{ key = "affliction", name = "Affliction" },
			{ key = "demonology", name = "Demonology" },
			{ key = "destruction", name = "Destruction" },
		},
		DRUID = {
			{ key = "balance", name = "Balance" },
			{ key = "feral", name = "Feral" },
			{ key = "restoration", name = "Restoration" },
		},
	}

	before_each(function()
		registered = {}
		ns = {
			Debug = {
				RegisterChecks = function(_, source, provider)
					registered[#registered + 1] = { source = source, provider = provider }
				end,
			},
		}
		assert(loadfile("MerrinxUI/Modules/GearAdvisorData.lua"))("MerrinxUI", ns)
		SPECS = ns.GearAdvisorData.SPECS
	end)

	local function weightKeySet()
		local set = {}
		for _, key in ipairs(WEIGHT_KEYS) do
			set[key] = true
		end
		return set
	end

	it("has exactly the 9 class tokens", function()
		local classes = {}
		for class in pairs(SPECS) do
			classes[#classes + 1] = class
		end
		table.sort(classes)
		local expected = {}
		for class in pairs(EXPECTED) do
			expected[#expected + 1] = class
		end
		table.sort(expected)
		assert.are.same(expected, classes)
	end)

	it("lists exactly the expected keys in order with non-empty names, per class", function()
		for class, specs in pairs(EXPECTED) do
			local actual = SPECS[class]
			assert.are.equal(#specs, #actual, class)
			for i, expected in ipairs(specs) do
				assert.are.equal(expected.key, actual[i].key, class .. "[" .. i .. "].key")
				assert.are.equal(expected.name, actual[i].name, class .. "[" .. i .. "].name")
				assert.is_true(#actual[i].name > 0)
			end
		end
	end)

	it("keeps weight keys within WEIGHT_KEYS, with numbers >= 0 and at least one > 0", function()
		local allowed = weightKeySet()
		for class, specs in pairs(SPECS) do
			for _, spec in ipairs(specs) do
				local hasPositive = false
				for key, value in pairs(spec.weights) do
					assert.is_true(allowed[key] ~= nil, class .. "." .. spec.key .. "." .. key)
					assert.is_true(type(value) == "number" and value >= 0, class .. "." .. spec.key .. "." .. key)
					if value > 0 then
						hasPositive = true
					end
				end
				assert.is_true(hasPositive, class .. "." .. spec.key .. " has no positive weight")
			end
		end
	end)

	it("has 27 specs in total", function()
		local count = 0
		for _, specs in pairs(SPECS) do
			count = count + #specs
		end
		assert.are.equal(27, count)
	end)

	it("matches spot values", function()
		assert.are.equal(13, SPECS.WARRIOR[2].weights.crit)
		assert.are.equal(6, SPECS.DRUID[2].weights.dodge)
	end)

	it("registers exactly one provider with source GearAdvisor", function()
		assert.are.equal(1, #registered)
		assert.are.equal("GearAdvisor", registered[1].source)
	end)
end)
