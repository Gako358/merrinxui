local addonName, ns = ...

local FontLogic = {}
ns.FontLogic = FontLogic

FontLogic.DEFAULT = "Friz Quadrata TT"
FontLogic.GLOBAL = "*"

function FontLogic.IsPath(value)
	if type(value) ~= "string" then
		return false
	end
	return value:find("[\\/]") ~= nil
end

function FontLogic.Resolve(key, globalKey)
	if key == nil or key == FontLogic.GLOBAL then
		return globalKey
	end
	return key
end

function FontLogic.Values(hash, isUsable, keep, globalLabel)
	local values = {}
	if hash ~= nil then
		for key, path in pairs(hash) do
			if isUsable == nil or key == keep or isUsable(path) then
				values[key] = key
			end
		end
	end
	if globalLabel ~= nil then
		values[FontLogic.GLOBAL] = globalLabel
	end
	return values
end

local function normalize(path)
	return path:lower():gsub("/", "\\")
end

function FontLogic.Migrate(value, hash, default)
	if type(value) ~= "string" or value == "" then
		return default
	end
	if not FontLogic.IsPath(value) then
		return value
	end
	if hash == nil then
		return default
	end

	local target = normalize(value)
	local match
	for key, path in pairs(hash) do
		if type(path) == "string" and normalize(path) == target then
			if match == nil then
				match = key
			elseif key == default or match == default then
				match = default
			elseif key < match then
				match = key
			end
		end
	end

	return match or default
end
