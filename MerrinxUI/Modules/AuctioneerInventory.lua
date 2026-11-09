local addonName, ns = ...

local LL = ns.AuctioneerLedgerLogic

local function plain(v)
	if issecretvalue(v) then
		return nil
	end
	return v
end

local Inventory = {}
ns.AuctioneerInventory = Inventory

local lastBags, lastInbox, lastSync
local maxDrift = 0

function Inventory:ReadBags()
	if
		type(C_Container) ~= "table"
		or type(C_Container.GetContainerNumSlots) ~= "function"
		or type(C_Container.GetContainerItemInfo) ~= "function"
	then
		return nil
	end

	local byItem = {}
	local order = {}
	local slots, bound = 0, 0

	for bag = 0, 4 do
		local numSlots = plain(C_Container.GetContainerNumSlots(bag)) or 0
		for slot = 1, numSlots do
			slots = slots + 1
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				local itemID = plain(info.itemID)
				local stackCount = plain(info.stackCount)
				local isBound = plain(info.isBound)
				local itemName = plain(info.itemName)
				local quality = plain(info.quality)
				if isBound == true then
					bound = bound + 1
				elseif type(itemID) == "number" and type(stackCount) == "number" and stackCount >= 1 then
					local entry = byItem[itemID]
					if not entry then
						entry = {
							itemID = itemID,
							name = type(itemName) == "string" and itemName ~= "" and itemName or nil,
							quality = type(quality) == "number" and quality >= 0 and quality or nil,
							count = 0,
						}
						byItem[itemID] = entry
						table.insert(order, entry)
					end
					entry.count = entry.count + stackCount
				end
			end
		end
	end

	lastBags = { slots = slots, items = #order, bound = bound }
	return order
end

function Inventory:ReadInbox()
	if
		type(GetInboxNumItems) ~= "function"
		or type(GetInboxHeaderInfo) ~= "function"
		or type(GetInboxInvoiceInfo) ~= "function"
	then
		return nil
	end

	local n = plain(GetInboxNumItems()) or 0
	local list = {}
	local noCount = 0

	for i = 1, n do
		local invoiceType, itemName, playerName, bid, buyout, deposit, consignment, _, _, _, count =
			GetInboxInvoiceInfo(i)
		invoiceType = plain(invoiceType)
		if invoiceType == "buyer" or invoiceType == "seller" then
			local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(i)
			local entry = {
				type = invoiceType,
				item = plain(itemName),
				player = plain(playerName),
				bid = plain(bid),
				buyout = plain(buyout),
				deposit = plain(deposit),
				consignment = plain(consignment),
				count = plain(count),
				daysLeft = plain(daysLeft),
			}
			if type(entry.count) ~= "number" or entry.count < 1 then
				noCount = noCount + 1
			end
			table.insert(list, entry)
		end
	end

	lastInbox = { mails = n, invoices = #list, noCount = noCount }
	return list
end

function Inventory:SyncMail(book, seen, now)
	local inbox = self:ReadInbox()
	if inbox == nil then
		return nil
	end

	local fresh, skipped, drift = LL.Diff(inbox, seen, now)
	local buys, sells = LL.Record(book, fresh, now)
	LL.Prune(book, now)

	lastSync = { fresh = #fresh, skipped = skipped, drift = drift }
	maxDrift = math.max(maxDrift, drift)

	return buys, sells
end

ns.Debug:RegisterChecks("Auctioneer", function()
	return {
		{
			name = "mail api",
			run = function()
				local missing = {}
				if type(GetInboxNumItems) ~= "function" then
					table.insert(missing, "GetInboxNumItems")
				end
				if type(GetInboxHeaderInfo) ~= "function" then
					table.insert(missing, "GetInboxHeaderInfo")
				end
				if type(GetInboxInvoiceInfo) ~= "function" then
					table.insert(missing, "GetInboxInvoiceInfo")
				end
				if #missing > 0 then
					return "FAIL", table.concat(missing, ", ")
				end
				return "PASS"
			end,
		},
		{
			name = "bags api",
			run = function()
				local missing = {}
				if type(C_Container) ~= "table" or type(C_Container.GetContainerNumSlots) ~= "function" then
					table.insert(missing, "C_Container.GetContainerNumSlots")
				end
				if type(C_Container) ~= "table" or type(C_Container.GetContainerItemInfo) ~= "function" then
					table.insert(missing, "C_Container.GetContainerItemInfo")
				end
				if #missing > 0 then
					return "FAIL", table.concat(missing, ", ")
				end
				return "PASS"
			end,
		},
		{
			name = "inbox",
			run = function()
				if not lastInbox then
					return "SKIP", "mailbox not opened yet"
				end
				if lastInbox.invoices > 0 and lastInbox.noCount == lastInbox.invoices then
					return "FAIL", "invoice count missing"
				end
				return "INFO", lastInbox.mails, lastInbox.invoices, lastInbox.noCount
			end,
		},
		{
			name = "mail sync",
			run = function()
				if not lastSync then
					return "SKIP", "no sync yet"
				end
				return "INFO", lastSync.fresh, lastSync.skipped, lastSync.drift, maxDrift
			end,
		},
		{
			name = "bags",
			run = function()
				if not lastBags then
					return "SKIP", "no read yet"
				end
				return "INFO", lastBags.slots, lastBags.items, lastBags.bound
			end,
		},
	}
end)
