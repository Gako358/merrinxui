describe("spell training data", function()
	local SNAPSHOT = {
		{
			token = "DRUID",
			path = "MerrinxUI/Modules/SpellTrainingData/Druid.lua",
			count = 184,
			idSum = 18791196,
			costSum = 2060610,
			hasGroups = true,
		},
		{
			token = "HUNTER",
			path = "MerrinxUI/Modules/SpellTrainingData/Hunter.lua",
			count = 169,
			idSum = 15221694,
			costSum = 2226110,
			hasGroups = false,
		},
		{
			token = "MAGE",
			path = "MerrinxUI/Modules/SpellTrainingData/Mage.lua",
			count = 173,
			idSum = 19687730,
			costSum = 2232310,
			hasGroups = false,
		},
		{
			token = "PALADIN",
			path = "MerrinxUI/Modules/SpellTrainingData/Paladin.lua",
			count = 147,
			idSum = 8525059,
			costSum = 2063810,
			hasGroups = true,
		},
		{
			token = "PRIEST",
			path = "MerrinxUI/Modules/SpellTrainingData/Priest.lua",
			count = 203,
			idSum = 36412936,
			costSum = 2769110,
			hasGroups = false,
		},
		{
			token = "ROGUE",
			path = "MerrinxUI/Modules/SpellTrainingData/Rogue.lua",
			count = 112,
			idSum = 11148709,
			costSum = 2219110,
			hasGroups = true,
		},
		{
			token = "SHAMAN",
			path = "MerrinxUI/Modules/SpellTrainingData/Shaman.lua",
			count = 165,
			idSum = 7860532,
			costSum = 2072010,
			hasGroups = false,
		},
		{
			token = "WARLOCK",
			path = "MerrinxUI/Modules/SpellTrainingData/Warlock.lua",
			count = 147,
			idSum = 9546804,
			costSum = 1914410,
			hasGroups = false,
		},
		{
			token = "WARRIOR",
			path = "MerrinxUI/Modules/SpellTrainingData/Warrior.lua",
			count = 101,
			idSum = 3917022,
			costSum = 2048410,
			hasGroups = true,
		},
	}

	local ns, L

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/SpellTrainingLogic.lua"))("MerrinxUI", ns)
		L = ns.SpellTrainingLogic
		for _, entry in ipairs(SNAPSHOT) do
			assert(loadfile(entry.path))("MerrinxUI", ns)
		end
	end)

	it("validates every class's data with SpellTrainingLogic.Validate", function()
		for _, token in ipairs(L.CLASSES) do
			local data = ns.SpellTrainingData[token]
			local ok, err = L.Validate(data, token)
			if not ok then
				print(token .. ": " .. tostring(err))
			end
			assert.is_true(ok)
		end
	end)

	it("has a data key set equal to SpellTrainingLogic.CLASSES", function()
		local classes = {}
		for _, token in ipairs(L.CLASSES) do
			classes[token] = true
		end

		local keys = {}
		for token in pairs(ns.SpellTrainingData) do
			keys[token] = true
		end

		for token in pairs(classes) do
			assert.is_true(keys[token] == true, "missing class " .. token)
		end
		for token in pairs(keys) do
			assert.is_true(classes[token] == true, "unexpected class " .. token)
		end
	end)

	it("matches the upstream snapshot's entry count, id sum and cost sum", function()
		for _, entry in ipairs(SNAPSHOT) do
			local data = ns.SpellTrainingData[entry.token]
			local count, idSum, costSum = 0, 0, 0
			for _, levelEntries in pairs(data.spellsByLevel) do
				for _, e in ipairs(levelEntries) do
					count = count + 1
					idSum = idSum + e.id
					costSum = costSum + e.cost
				end
			end
			assert.are.equal(entry.count, count, entry.token .. " count")
			assert.are.equal(entry.idSum, idSum, entry.token .. " id sum")
			assert.are.equal(entry.costSum, costSum, entry.token .. " cost sum")
		end
	end)

	it("has overriddenGroups exactly for DRUID, PALADIN, ROGUE and WARRIOR", function()
		for _, entry in ipairs(SNAPSHOT) do
			local data = ns.SpellTrainingData[entry.token]
			assert.are.equal(entry.hasGroups, data.overriddenGroups ~= nil, entry.token .. " overriddenGroups presence")
		end
	end)

	it("lists every data file in the TOC", function()
		local f = assert(io.open("MerrinxUI/MerrinxUI.toc", "r"))
		local content = f:read("*a"):gsub("\r", "")
		f:close()

		local tocPaths = {}
		for line in content:gmatch("[^\n]+") do
			local trimmed = line:match("^%s*(.-)%s*$")
			tocPaths[trimmed] = true
		end

		for _, entry in ipairs(SNAPSHOT) do
			local tocPath = entry.path:sub(("MerrinxUI/"):len() + 1):gsub("/", "\\")
			assert.is_true(tocPaths[tocPath] == true, "missing from TOC: " .. tocPath)
		end
	end)
end)
