local addonName, ns = ...

local L = {}
ns.OptionsLogic = L

L.INHERITED = { set = true, get = true, func = true, confirm = true, validate = true, disabled = true, hidden = true }
L.STRING_LITERAL = { name = true, desc = true, usage = true }
L.SUPPORTED = {
	group = true,
	toggle = true,
	range = true,
	select = true,
	input = true,
	execute = true,
	description = true,
	header = true,
}

local function sub(node, key)
	return node.args and node.args[key]
end

local function extendPath(path, key)
	local out = {}
	for i = 1, #path do
		out[i] = path[i]
	end
	out[#out + 1] = key
	return out
end

local function walkLastNonNil(root, path, name)
	local node = root
	local value = node[name]
	for i = 1, #path do
		node = sub(node, path[i])
		if node == nil then
			break
		end
		if node[name] ~= nil then
			value = node[name]
		end
	end
	return value
end

-- AceConfigDialog only replaces the inherited handler with a truthy one
-- (`group.handler or handler`), so a `handler = false` deeper in the path
-- does not clear the parent's handler.
local function walkLastTruthy(root, path, name)
	local node = root
	local value = node[name]
	for i = 1, #path do
		node = sub(node, path[i])
		if node == nil then
			break
		end
		value = node[name] or value
	end
	return value
end

function L.Node(root, path)
	local node = root
	for i = 1, #path do
		node = node and sub(node, path[i])
	end
	return node
end

function L.Member(root, path, name)
	if not L.INHERITED[name] then
		local node = L.Node(root, path)
		return node and node[name]
	end
	return walkLastNonNil(root, path, name)
end

function L.Handler(root, path)
	return walkLastTruthy(root, path, "handler")
end

function L.Info(root, path, appName)
	local node = L.Node(root, path)
	local info = {}
	for i = 1, #path do
		info[i] = path[i]
	end
	info[0] = appName
	info.options = root
	info.appName = appName
	info.arg = node and node.arg
	info.handler = L.Handler(root, path)
	info.option = node
	info.type = node and node.type
	info.uiType = "dialog"
	info.uiName = appName
	return info
end

function L.Value(root, path, name, appName, ...)
	local raw = L.Member(root, path, name)
	if type(raw) == "function" then
		local info = L.Info(root, path, appName)
		return raw(info, ...)
	elseif type(raw) == "string" and not L.STRING_LITERAL[name] then
		local info = L.Info(root, path, appName)
		local handler = info.handler
		if not (handler and handler[raw]) then
			error("Method " .. raw .. " doesn't exist in handler for " .. name)
		end
		return handler[raw](handler, info, ...)
	else
		return raw
	end
end

function L.Sorted(root, path, appName)
	local node = L.Node(root, path)
	local keys = {}
	if node and node.args then
		for k in pairs(node.args) do
			keys[#keys + 1] = k
		end
	end
	local order, name = {}, {}
	for _, k in ipairs(keys) do
		local childPath = extendPath(path, k)
		order[k] = L.Value(root, childPath, "order", appName) or 100
		name[k] = L.Value(root, childPath, "name", appName)
	end
	table.sort(keys, function(a, b)
		local orderA, orderB = order[a], order[b]
		if orderA ~= orderB then
			if (orderA < 0) ~= (orderB < 0) then
				return orderA >= 0
			end
			return orderA < orderB
		end
		local nameA = (type(name[a]) == "string" and name[a] or ""):upper()
		local nameB = (type(name[b]) == "string" and name[b] or ""):upper()
		if nameA ~= nameB then
			return nameA < nameB
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

function L.IsHidden(root, path, appName)
	local node = L.Node(root, path)
	if node == nil then
		return false
	end
	local hidden = node.dialogHidden
	if hidden == nil then
		hidden = node.guiHidden
	end
	if hidden ~= nil then
		return not not hidden
	end
	return not not L.Value(root, path, "hidden", appName)
end

function L.IsDisabled(root, path, appName)
	local node = L.Node(root, path)
	if node == nil then
		return false
	end
	local disabled = node.dialogDisabled
	if disabled == nil then
		disabled = node.guiDisabled
	end
	if disabled ~= nil then
		return not not disabled
	end
	return not not L.Value(root, path, "disabled", appName)
end

function L.Pages(root, appName)
	local keys = L.Sorted(root, {}, appName)
	local pages = {}
	local hasGeneral = false
	for _, key in ipairs(keys) do
		local path = { key }
		if not L.IsHidden(root, path, appName) and root.args[key].type ~= "group" then
			hasGeneral = true
		end
	end
	if hasGeneral then
		pages[#pages + 1] = { label = "General", path = {}, leavesOnly = true }
	end
	for _, key in ipairs(keys) do
		local path = { key }
		if not L.IsHidden(root, path, appName) and root.args[key].type == "group" then
			pages[#pages + 1] = { label = L.Value(root, path, "name", appName), path = path }
		end
	end
	return pages
end

local function flattenInto(root, path, appName, leavesOnly, depth, rows)
	local node = L.Node(root, path)
	if not node or not node.args then
		return
	end
	local keys = L.Sorted(root, path, appName)
	for _, key in ipairs(keys) do
		local childPath = extendPath(path, key)
		if not L.IsHidden(root, childPath, appName) then
			local kind = node.args[key].type
			if kind == "group" then
				if not leavesOnly then
					local before = #rows
					rows[#rows + 1] = { kind = "section", path = childPath, depth = depth }
					flattenInto(root, childPath, appName, leavesOnly, depth + 1, rows)
					if #rows == before + 1 then
						rows[#rows] = nil
					end
				end
			elseif L.SUPPORTED[kind] then
				rows[#rows + 1] = { kind = kind, path = childPath, depth = depth }
			else
				rows[#rows + 1] = { kind = "unsupported", path = childPath, depth = depth }
			end
		end
	end
end

function L.Flatten(root, path, appName, leavesOnly)
	local rows = {}
	flattenInto(root, path, appName, leavesOnly, 0, rows)
	return rows
end

function L.SortedValues(values)
	local keys = {}
	for k in pairs(values) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		local numA, numB = tonumber(a), tonumber(b)
		if numA and numB then
			return numA < numB
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

function L.SnapRange(v, min, max, step)
	min = min or 0
	max = max or 100
	if step and step > 0 then
		v = math.floor((v - min) / step + 0.5) * step + min
	end
	if v < min then
		v = min
	end
	if v > max then
		v = max
	end
	return v
end

function L.FormatNumber(v)
	local s = string.format("%.2f", v)
	s = s:gsub("0+$", "")
	s = s:gsub("%.$", "")
	return s
end

function L.CheckValidate(result, name, usage)
	name = type(name) == "string" and name or ""
	if result == nil or result == false then
		if usage then
			return false, name .. ": " .. usage
		end
		return false, name .. ": Invalid Value"
	end
	if type(result) == "string" then
		return false, result
	end
	return true
end

function L.ConfirmText(confirm, confirmText, name, desc)
	if type(confirm) == "string" then
		return true, confirm
	end
	if confirm ~= true then
		return false
	end
	if confirmText then
		return true, confirmText
	end
	local text = name or ""
	if desc then
		text = text .. " - " .. desc
	end
	return true, text
end

function L.Scroll(offset, delta, step, contentH, viewH)
	local maxOffset = contentH - viewH
	if maxOffset < 0 then
		maxOffset = 0
	end
	local value = offset - delta * step
	if value < 0 then
		value = 0
	elseif value > maxOffset then
		value = maxOffset
	end
	return value
end

function L.Stack(heights, gap)
	local offsets = {}
	local pos = 0
	for i = 1, #heights do
		offsets[i] = pos
		pos = pos + heights[i] + gap
	end
	local total = 0
	if #heights > 0 then
		total = pos - gap
	end
	return offsets, total
end
