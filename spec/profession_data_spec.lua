describe("profession data", function()
	local DATA = {
		{ path = "MerrinxUI/Modules/ProfessionData/Alchemy.lua", skillLine = 171, routeEnd = 290 },
		{ path = "MerrinxUI/Modules/ProfessionData/Blacksmithing.lua", skillLine = 164, routeEnd = 225 },
		{ path = "MerrinxUI/Modules/ProfessionData/Enchanting.lua", skillLine = 333, routeEnd = 300 },
		{ path = "MerrinxUI/Modules/ProfessionData/Engineering.lua", skillLine = 202, routeEnd = 300 },
		{ path = "MerrinxUI/Modules/ProfessionData/Leatherworking.lua", skillLine = 165, routeEnd = 225 },
		{ path = "MerrinxUI/Modules/ProfessionData/Tailoring.lua", skillLine = 197, routeEnd = 225 },
		{ path = "MerrinxUI/Modules/ProfessionData/Cooking.lua", skillLine = 185, routeEnd = 300 },
		{ path = "MerrinxUI/Modules/ProfessionData/FirstAid.lua", skillLine = 129, routeEnd = 300 },
		{ path = "MerrinxUI/Modules/ProfessionData/Fishing.lua", skillLine = 356, routeEnd = 300 },
		{ path = "MerrinxUI/Modules/ProfessionData/Herbalism.lua", skillLine = 182, routeEnd = 300 },
		{ path = "MerrinxUI/Modules/ProfessionData/Mining.lua", skillLine = 186, routeEnd = 300 },
		{ path = "MerrinxUI/Modules/ProfessionData/Skinning.lua", skillLine = 393, routeEnd = 300 },
	}

	local ns, L

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/ProfessionLogic.lua"))("MerrinxUI", ns)
		L = ns.ProfessionLogic
		for _, entry in ipairs(DATA) do
			assert(loadfile(entry.path))("MerrinxUI", ns)
		end
	end)

	it("validates every data file with ProfessionLogic.Validate", function()
		for _, entry in ipairs(DATA) do
			local data = ns.ProfessionData[entry.skillLine]
			local ok, err = L.Validate(data)
			if not ok then
				print(entry.path .. ": " .. tostring(err))
			end
			assert.is_true(ok)
		end
	end)

	it("has a skillLine set equal to ProfessionLogic.ORDER", function()
		local order = {}
		for _, id in ipairs(L.ORDER) do
			order[id] = true
		end

		local keys = {}
		for id in pairs(ns.ProfessionData) do
			keys[id] = true
		end

		for id in pairs(order) do
			assert.is_true(keys[id] == true, "missing skillLine " .. id)
		end
		for id in pairs(keys) do
			assert.is_true(order[id] == true, "unexpected skillLine " .. id)
		end
	end)

	it("matches the schema's routeEnd for every profession", function()
		for _, entry in ipairs(DATA) do
			local data = ns.ProfessionData[entry.skillLine]
			assert.are.equal(entry.routeEnd, data.routeEnd)
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

		for _, entry in ipairs(DATA) do
			local tocPath = entry.path:sub(("MerrinxUI/"):len() + 1):gsub("/", "\\")
			assert.is_true(tocPaths[tocPath] == true, "missing from TOC: " .. tocPath)
		end
	end)
end)
