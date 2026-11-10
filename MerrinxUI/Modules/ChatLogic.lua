local addonName, ns = ...

local ChatLogic = {}
ns.ChatLogic = ChatLogic

ChatLogic.LINK_PREFIX = "addon:" .. addonName .. ":url:"

-- "||" comes first so an escaped pipe never starts another escape.
local ESCAPES = {
	"||",
	"|H.-|h.-|h",
	"|K.-|k",
	"|T.-|t",
	"|A.-|a",
	"|c%x%x%x%x%x%x%x%x",
	"|r",
	"|n",
}

local URL_PATTERNS = {
	"^%a[%w+.-]*://[^/%s]",
	"^www%.[%w-]+%.%a%a",
	"^%d+%.%d+%.%d+%.%d+:%d",
	"^%d+%.%d+%.%d+%.%d+/",
}

local TOKEN_SPLIT = "^([%(%[{<\"']*)(.-)([%.,;:!%?%)%]}>\"']*)$"

local function nextEscape(text, init)
	local first, last
	for _, pattern in ipairs(ESCAPES) do
		local s, e = text:find(pattern, init)
		if s and (first == nil or s < first) then
			first, last = s, e
		end
	end
	return first, last
end

local function walk(text, plain, escape)
	local out = {}
	local pos = 1
	while true do
		local s, e = nextEscape(text, pos)
		if not s then
			break
		end
		if s > pos then
			out[#out + 1] = plain(text:sub(pos, s - 1))
		end
		out[#out + 1] = escape(text:sub(s, e))
		pos = e + 1
	end
	if pos <= #text then
		out[#out + 1] = plain(text:sub(pos))
	end
	return table.concat(out)
end

local function keep(s)
	return s
end

function ChatLogic.IsURL(text)
	if type(text) ~= "string" or text == "" then
		return false
	end
	for _, pattern in ipairs(URL_PATTERNS) do
		if text:find(pattern) then
			return true
		end
	end
	return false
end

function ChatLogic.Link(url, hex)
	return ("|cff%s|H%s%s|h[%s]|h|r"):format(hex, ChatLogic.LINK_PREFIX, url, url)
end

function ChatLogic.WrapURLs(text, hex)
	local count = 0
	local function plain(segment)
		return (
			segment:gsub("%S+", function(token)
				local lead, core, trail = token:match(TOKEN_SPLIT)
				if ChatLogic.IsURL(core) then
					count = count + 1
					return lead .. ChatLogic.Link(core, hex) .. trail
				end
			end)
		)
	end
	local wrapped = walk(text, plain, keep)
	if count == 0 then
		return text, 0
	end
	return wrapped, count
end

function ChatLogic.ParseLink(link)
	if type(link) ~= "string" then
		return nil
	end
	local prefix = ChatLogic.LINK_PREFIX
	if link:sub(1, #prefix) ~= prefix or #link == #prefix then
		return nil
	end
	return link:sub(#prefix + 1)
end

function ChatLogic.PlainText(text)
	return walk(text, keep, function(escape)
		local head = escape:sub(1, 2)
		if escape == "||" then
			return "|"
		elseif head == "|H" then
			return escape:match("^|H.-|h(.-)|h$")
		elseif head == "|K" then
			return "?"
		elseif head == "|n" then
			return " "
		end
		return ""
	end)
end

function ChatLogic.FadeTarget(fade, idle, delay, low)
	if fade and idle >= delay then
		return low
	end
	return 1
end

function ChatLogic.Approach(current, target, step)
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

ChatLogic.TIMESTAMP_GAME = "blizzard"
ChatLogic.TIMESTAMP_FORMATS = {
	{ value = "blizzard", label = "Game setting" },
	{ value = "none", label = "Off" },
	{ value = "%H:%M ", label = "24-hour (15:04)" },
	{ value = "%H:%M:%S ", label = "24-hour with seconds (15:04:05)" },
	{ value = "%I:%M %p ", label = "12-hour (03:04 PM)" },
	{ value = "%I:%M:%S %p ", label = "12-hour with seconds (03:04:05 PM)" },
}

function ChatLogic.TimestampValues()
	local values = {}
	for _, entry in ipairs(ChatLogic.TIMESTAMP_FORMATS) do
		values[entry.value] = entry.label
	end
	return values
end

function ChatLogic.TimestampCVar(choice, current)
	if choice == ChatLogic.TIMESTAMP_GAME or choice == current then
		return nil
	end
	for _, entry in ipairs(ChatLogic.TIMESTAMP_FORMATS) do
		if entry.value == choice then
			return choice
		end
	end
	return nil
end
