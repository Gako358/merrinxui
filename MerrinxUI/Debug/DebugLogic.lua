local addonName, ns = ...

local DebugLogic = {}
ns.DebugLogic = DebugLogic

DebugLogic.CAP = 500
DebugLogic.MAX_LINE = 400
DebugLogic.MAX_PART = 200
DebugLogic.STATUSES = { PASS = true, FAIL = true, SKIP = true, INFO = true }

function DebugLogic.Describe(v, isSecret)
	if isSecret(v) then
		return "<secret>"
	end
	if v == nil then
		return "nil"
	end

	local t = type(v)
	if t == "boolean" then
		return v and "true" or "false"
	end
	if t == "number" then
		return tostring(v)
	end
	if t == "string" then
		local s = v:gsub("[\n\r]", " ")
		s = s:gsub("|", "||")
		if #s > DebugLogic.MAX_PART then
			s = s:sub(1, DebugLogic.MAX_PART) .. "..."
		end
		return s
	end

	return t
end

function DebugLogic.Join(parts, n, isSecret)
	local out = {}
	for i = 1, n do
		out[i] = DebugLogic.Describe(parts[i], isSecret)
	end
	return table.concat(out, " ")
end

function DebugLogic.FormatLine(stamp, source, text)
	local line = "[" .. stamp .. "] " .. source .. ": " .. text
	if #line > DebugLogic.MAX_LINE then
		line = line:sub(1, DebugLogic.MAX_LINE)
	end
	return line
end

function DebugLogic.Push(log, line, cap)
	table.insert(log, line)
	local removed = 0
	while #log > cap do
		table.remove(log, 1)
		removed = removed + 1
	end
	return removed
end

function DebugLogic.Flatten(tbl, isSecret)
	local keys = {}
	for k in pairs(tbl) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local parts = {}
	for _, k in ipairs(keys) do
		local v = tbl[k]
		if type(v) == "table" and not isSecret(v) then
			local subKeys = {}
			for sk in pairs(v) do
				table.insert(subKeys, sk)
			end
			table.sort(subKeys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, sk in ipairs(subKeys) do
				table.insert(parts, k .. "." .. sk .. "=" .. DebugLogic.Describe(v[sk], isSecret))
			end
		else
			table.insert(parts, k .. "=" .. DebugLogic.Describe(v, isSecret))
		end
	end
	return table.concat(parts, " ")
end

local function pack(...)
	return select("#", ...), { ... }
end

function DebugLogic.RunCheck(check, ctx, isSecret)
	if type(check) ~= "table" or type(check.run) ~= "function" then
		return { name = DebugLogic.Describe(check, isSecret), status = "FAIL", detail = "malformed check" }
	end

	local name = DebugLogic.Describe(check.name, isSecret)

	local n, results = pack(pcall(check.run, ctx))
	local ok = results[1]
	if not ok then
		return { name = name, status = "FAIL", detail = "error: " .. DebugLogic.Describe(results[2], isSecret) }
	end

	local status = results[2]
	if isSecret(status) or not DebugLogic.STATUSES[status] then
		return { name = name, status = "FAIL", detail = "invalid status: " .. DebugLogic.Describe(status, isSecret) }
	end

	local rawCount = n - 2
	local raw = {}
	for i = 1, rawCount do
		raw[i] = results[i + 2]
	end

	return { name = name, status = status, detail = DebugLogic.Join(raw, rawCount, isSecret) }
end

function DebugLogic.RunChecks(source, checks, ctx, isSecret)
	local results = {}
	if checks == nil then
		return results
	end
	for _, check in ipairs(checks) do
		local result = DebugLogic.RunCheck(check, ctx, isSecret)
		result.source = DebugLogic.Describe(source, isSecret)
		table.insert(results, result)
	end
	return results
end

function DebugLogic.RunSource(source, provider, ctx, isSecret)
	local ok, checks = pcall(provider)
	if not ok then
		return {
			{
				source = DebugLogic.Describe(source, isSecret),
				name = "checks",
				status = "FAIL",
				detail = "error: " .. DebugLogic.Describe(checks, isSecret),
			},
		}
	end
	if checks ~= nil and type(checks) ~= "table" then
		return {
			{
				source = DebugLogic.Describe(source, isSecret),
				name = "checks",
				status = "FAIL",
				detail = "not a table",
			},
		}
	end
	return DebugLogic.RunChecks(source, checks, ctx, isSecret)
end

function DebugLogic.FormatResult(r)
	local text = r.status .. " " .. r.source .. "/" .. r.name
	if r.detail ~= "" then
		text = text .. ": " .. r.detail
	end
	return text
end

function DebugLogic.Summary(results)
	local counts = { PASS = 0, FAIL = 0, SKIP = 0, INFO = 0, total = 0 }
	for _, r in ipairs(results) do
		counts[r.status] = counts[r.status] + 1
		counts.total = counts.total + 1
	end

	local text = counts.total
		.. " checks: "
		.. counts.PASS
		.. " PASS, "
		.. counts.FAIL
		.. " FAIL, "
		.. counts.SKIP
		.. " SKIP, "
		.. counts.INFO
		.. " INFO"

	return text, counts
end

function DebugLogic.SortSources(names)
	local sorted = {}
	local hasDebug = false
	for _, name in ipairs(names) do
		if name == "Debug" then
			hasDebug = true
		else
			table.insert(sorted, name)
		end
	end
	table.sort(sorted)
	if hasDebug then
		table.insert(sorted, 1, "Debug")
	end
	return sorted
end
