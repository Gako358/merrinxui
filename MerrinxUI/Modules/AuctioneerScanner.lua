local addonName, ns = ...

local SL = ns.AuctioneerScanLogic

local CHUNK = 500
local TIMEOUT = 60

local Scanner = {}
ns.AuctioneerScanner = Scanner

local function plain(v)
	if issecretvalue(v) then
		return nil
	end
	return v
end

local eventFrame = CreateFrame("Frame")

local state = "idle"
local generation = 0
local handlers
local acc
local sample
local read, total = 0, 0
local timer

local function reset()
	state = "idle"
	acc = nil
	read, total = 0, 0
	if timer then
		timer:Cancel()
		timer = nil
	end
	eventFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
end

local function onReplicateUpdate()
	if state ~= "waiting" then
		return
	end
	eventFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	if timer then
		timer:Cancel()
		timer = nil
	end
	local gen = generation
	if C_AuctionHouse.GetNumReplicateItems() == 0 then
		generation = generation + 1
		reset()
		if handlers.onFail then
			handlers.onFail("empty")
		end
		return
	end
	state = "reading"
	read = 0
	Scanner:Step(gen)
end

function Scanner:Step(gen)
	if gen ~= generation or state ~= "reading" then
		return
	end
	total = C_AuctionHouse.GetNumReplicateItems()
	local limit = math.min(read + CHUNK, total)
	for i = read, limit - 1 do
		local name, _, count, quality, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
			C_AuctionHouse.GetReplicateItemInfo(i)
		local row = {
			itemID = plain(itemID),
			name = plain(name),
			quality = plain(quality),
			count = plain(count),
			buyout = plain(buyout),
			band = plain(C_AuctionHouse.GetReplicateItemTimeLeft(i)),
		}
		if SL.AddRow(acc, row) and not sample then
			sample = row
		end
	end
	read = limit
	if handlers.onProgress then
		handlers.onProgress(read, total)
	end
	if read >= total then
		local summaries, rows, skipped = SL.Finish(acc)
		local result = { summaries = summaries, rows = rows, skipped = skipped }
		reset()
		if handlers.onDone then
			handlers.onDone(result)
		end
	else
		C_Timer.After(0, function()
			Scanner:Step(gen)
		end)
	end
end

eventFrame:SetScript("OnEvent", onReplicateUpdate)

function Scanner:Start(h)
	if
		type(C_AuctionHouse) ~= "table"
		or type(C_AuctionHouse.ReplicateItems) ~= "function"
		or type(C_AuctionHouse.GetNumReplicateItems) ~= "function"
		or type(C_AuctionHouse.GetReplicateItemInfo) ~= "function"
		or type(C_AuctionHouse.GetReplicateItemTimeLeft) ~= "function"
	then
		return false, "unavailable"
	end
	if state ~= "idle" then
		return false, "busy"
	end
	handlers = h
	acc = SL.NewAccumulator()
	sample = nil
	read, total = 0, 0
	generation = generation + 1
	local gen = generation
	state = "waiting"
	eventFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	C_AuctionHouse.ReplicateItems()
	timer = C_Timer.NewTimer(TIMEOUT, function()
		if gen == generation and state == "waiting" then
			Scanner:Abort("timeout")
		end
	end)
	return true
end

function Scanner:Abort(reason)
	if state == "idle" then
		return
	end
	generation = generation + 1
	reset()
	if handlers and handlers.onFail then
		handlers.onFail(reason)
	end
end

function Scanner:State()
	return state
end

function Scanner:Progress()
	return read, total
end

ns.Debug:RegisterChecks("Auctioneer", function()
	return {
		{
			name = "scanner",
			run = function()
				return "INFO", state, read, total
			end,
		},
		{
			name = "sample",
			run = function()
				if not sample then
					return "SKIP", "no scan yet"
				end
				return "INFO", sample.itemID, sample.count, sample.buyout, sample.band
			end,
		},
	}
end)
