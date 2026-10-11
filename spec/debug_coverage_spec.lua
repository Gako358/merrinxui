describe("debug coverage", function()
	local EXEMPT = {
		["MerrinxUI/Core.lua"] = true,
		["MerrinxUI/Debug/DebugLogic.lua"] = true,
		["MerrinxUI/Util/CombatQueue.lua"] = true,
		["MerrinxUI/Options/Theme.lua"] = true,
	}

	local function isExempt(path)
		return EXEMPT[path] == true or path:find("Logic%.lua$") ~= nil
	end

	local function readFile(path)
		local f = assert(io.open(path, "r"))
		local content = f:read("*a")
		f:close()
		return content
	end

	local function tocLuaPaths()
		local content = readFile("MerrinxUI/MerrinxUI.toc"):gsub("\r", "")

		local paths = {}
		for line in content:gmatch("[^\n]+") do
			local trimmed = line:match("^%s*(.-)%s*$")
			if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" and trimmed:match("%.lua$") then
				table.insert(paths, "MerrinxUI/" .. (trimmed:gsub("\\", "/")))
			end
		end
		return paths
	end

	local paths = tocLuaPaths()

	it("gives every non-exempt TOC file a GetDebugChecks or RegisterChecks", function()
		local offenders = {}
		for _, path in ipairs(paths) do
			if not isExempt(path) then
				local src = readFile(path)
				local hasModule = src:find(":NewModule(", 1, true) ~= nil
					and src:find("function%s+[%w_]+:GetDebugChecks%(") ~= nil
				local hasProvider = src:find("ns.Debug:RegisterChecks(", 1, true) ~= nil
				if not (hasModule or hasProvider) then
					table.insert(offenders, path)
				end
			end
		end

		assert.is_true(#offenders == 0, "missing debug coverage: " .. table.concat(offenders, ", "))
	end)

	it("finds at least 5 files that call :NewModule(", function()
		local count = 0
		for _, path in ipairs(paths) do
			if readFile(path):find(":NewModule(", 1, true) then
				count = count + 1
			end
		end

		assert.is_true(count >= 5)
	end)

	it("puts Debug/Debug.lua before the first Util/ file", function()
		local debugIndex, utilIndex
		for i, path in ipairs(paths) do
			if path == "MerrinxUI/Debug/Debug.lua" and not debugIndex then
				debugIndex = i
			end
			if path:find("^MerrinxUI/Util/") and not utilIndex then
				utilIndex = i
			end
		end

		assert.is_not_nil(debugIndex)
		assert.is_not_nil(utilIndex)
		assert.is_true(debugIndex < utilIndex)
	end)
end)
