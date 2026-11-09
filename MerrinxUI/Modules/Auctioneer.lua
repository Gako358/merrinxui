local addonName, ns = ...

local SL, AL, Scanner, Window = ns.AuctioneerScanLogic, ns.AuctioneerLogic, ns.AuctioneerScanner, ns.AuctioneerWindow

local Auctioneer = ns.addon:NewModule("Auctioneer", "AceEvent-3.0")

local defaults = {
	profile = {
		enabled = true,
		openWithAH = true,
		retentionDays = 14,
		discount = 30,
		minProfit = 50,
		cut = 5,
		font = "*",
		fontSize = 12,
		tab = "deals",
		position = { point = "CENTER", x = 0, y = 0 },
	},
	global = { lastReplicate = 0 },
	factionrealm = { lastScan = 0, lastRows = 0, items = {} },
}

local SCAN_FAIL_MESSAGES = {
	unavailable = "this client has no full Auction House scan.",
	busy = "a scan is already running.",
	timeout = "the server did not answer. It allows one full scan every 15 minutes, try again later.",
	closed = "scan stopped because the Auction House closed.",
	empty = "the scan returned no auctions.",
}

local function plain(v)
	if issecretvalue(v) then
		return nil
	end
	return v
end

function Auctioneer:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("Auctioneer", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.ahOpen = false
	self.ingestMs = 0

	Window:Create({
		getProfile = function()
			return self.db.profile
		end,
		onScan = function()
			self:Scan()
		end,
		onSearch = function(itemID)
			self:SearchItem(itemID)
		end,
	})
end

function Auctioneer:OnEnable()
	self:RegisterEvent("AUCTION_HOUSE_SHOW", "OnAuctionHouseShow")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED", "OnAuctionHouseClosed")
	self:RegisterMessage("MERRINXUI_MEDIA_CHANGED", "OnMediaChanged")
	Window:Layout()
end

function Auctioneer:OnDisable()
	Scanner:Abort("disabled")
	self.ahOpen = false
	Window:Hide()
end

function Auctioneer:Refresh()
	if self.db.profile.enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function Auctioneer:OnMediaChanged()
	Window:Layout()
end

function Auctioneer:Say(text)
	ns.addon:Print("Auctioneer: " .. text)
end

function Auctioneer:CanScan()
	return self:IsEnabled() and self.ahOpen == true and Scanner:State() == "idle"
end

function Auctioneer:IsAuctionHouseOpen()
	return self.ahOpen == true
end

function Auctioneer:OnAuctionHouseShow()
	self.ahOpen = true
	if self.db.profile.openWithAH then
		self:Recompute()
		Window:SetStatus(self:StatusText())
		Window:Show()
	end
	Window:SetScanEnabled(self:CanScan(), "Scan")
end

function Auctioneer:OnAuctionHouseClosed()
	self.ahOpen = false
	Scanner:Abort("closed")
	if self.db.profile.openWithAH then
		Window:Hide()
	end
	Window:SetScanEnabled(false, "Scan")
end

function Auctioneer:Toggle()
	if not self:IsEnabled() then
		self:Say("turned off in /mui > Auctioneer.")
		return
	end
	if Window:IsShown() then
		Window:Hide()
	else
		if not self.results then
			self:Recompute()
		end
		Window:SetStatus(self:StatusText())
		Window:Show()
	end
end

function Auctioneer:OnScanFail(reason)
	Window:SetScanEnabled(self:CanScan(), "Scan")
	Window:SetStatus(self:StatusText())
	local message = SCAN_FAIL_MESSAGES[reason]
	if message then
		self:Say(message)
	end
end

function Auctioneer:Scan()
	if not self:IsEnabled() then
		return
	end
	if not self.ahOpen then
		self:Say("open the Auction House first.")
		return
	end

	local throttle = SL.ThrottleLeft(time(), self.db.global.lastReplicate)
	if throttle > 0 then
		self:Say(
			"the server allows one full scan every 15 minutes, try again in " .. AL.FormatDuration(throttle) .. "."
		)
		return
	end

	local ok, reason = Scanner:Start({
		onProgress = function(read, total)
			Window:SetStatus(string.format("Scanning %d/%d", read, total))
		end,
		onDone = function(result)
			self:Ingest(result, time())
		end,
		onFail = function(failReason)
			self:OnScanFail(failReason)
		end,
	})

	if ok then
		self.db.global.lastReplicate = time()
		Window:SetScanEnabled(false, "Scanning")
	else
		self:OnScanFail(reason)
	end
end

function Auctioneer:Ingest(result, now)
	local profile = self.db.profile
	local realm = self.db.factionrealm
	local items = realm.items

	local startMs = debugprofilestop()
	local gap = realm.lastScan > 0 and (now - realm.lastScan) or nil
	local day = SL.Day(now)
	local keep = profile.retentionDays

	local function mergeItem(itemID, summary, listed)
		local item = items[itemID]
		if not item then
			item = { n = nil, q = nil, v = nil, h = "", s = nil }
			items[itemID] = item
		end

		local prev = SL.UnpackSnapshot(item.s)
		local cur = listed and summary.buckets or {}
		local removed = SL.EstimateRemoved(prev, cur, gap)
		local hist = SL.UnpackHistory(item.h)

		if listed then
			SL.MergeScan(hist, day, { min = summary.min, med = summary.med, qty = summary.qty, sold = removed })
		elseif next(prev) ~= nil then
			SL.MergeScan(hist, day, { min = 0, med = 0, qty = 0, sold = removed })
		end

		SL.Prune(hist, day, keep)

		if #hist == 0 and not listed then
			items[itemID] = nil
			return
		end

		item.h = SL.PackHistory(hist)
		item.s = listed and SL.PackSnapshot(cur) or nil

		if listed then
			item.n = summary.name or item.n
			item.q = summary.quality or item.q
		end

		if listed and (item.v == nil or item.n == nil) then
			local name, _, quality, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemID)
			item.n = item.n or plain(name)
			item.q = item.q or plain(quality)
			item.v = item.v or plain(sellPrice)
		end
	end

	local itemCount = 0
	for itemID, summary in pairs(result.summaries) do
		itemCount = itemCount + 1
		mergeItem(itemID, summary, true)
	end

	for itemID in pairs(items) do
		if not result.summaries[itemID] then
			mergeItem(itemID, nil, false)
		end
	end

	realm.lastScan = now
	realm.lastRows = result.rows

	self.ingestMs = debugprofilestop() - startMs

	self:Say(string.format("scanned %d auctions of %d items.", result.rows, itemCount))

	self:Recompute()
	Window:SetScanEnabled(self:CanScan(), "Scan")
	Window:SetStatus(self:StatusText())

	if ns.OptionsWindow:CurrentPage() == "Auctioneer" then
		LibStub("AceConfigRegistry-3.0"):NotifyChange("MerrinxUI")
	end
end

function Auctioneer:Recompute()
	if not self:IsEnabled() then
		self.results = nil
		return
	end

	local profile = self.db.profile
	local realm = self.db.factionrealm
	local today = SL.Day(realm.lastScan)

	local list = {}
	for itemID, item in pairs(realm.items) do
		list[#list + 1] = {
			itemID = itemID,
			name = item.n,
			quality = item.q,
			vendor = item.v,
			history = SL.UnpackHistory(item.h),
			listings = SL.Listings(SL.UnpackSnapshot(item.s)),
		}
	end

	self.results = AL.Analyze(list, today, {
		discount = profile.discount / 100,
		cut = profile.cut / 100,
		minProfit = profile.minProfit * 100,
	})

	Window:SetData(realm.lastScan > 0 and self.results or nil)
end

function Auctioneer:SearchItem(itemID)
	local item = self.db.factionrealm.items[itemID]
	local name = plain((item and item.n) or C_Item.GetItemInfo(itemID))
	if type(name) ~= "string" then
		self:Say("item name not loaded yet, try again in a moment.")
		return
	end

	if not self.ahOpen then
		self:Say("open the Auction House to search for " .. name .. ".")
		return
	end

	local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	if not bar or type(bar.SetSearchText) ~= "function" or type(bar.StartSearch) ~= "function" then
		self:Say("can't search the Auction House on this client.")
		return
	end

	bar:SetSearchText(name)
	bar:StartSearch()
	ns.Debug:Log("Auctioneer", "search", itemID)
end

function Auctioneer:StatusText()
	local realm = self.db.factionrealm
	if realm.lastScan <= 0 then
		return "No scan yet"
	end

	local n = 0
	for _ in pairs(realm.items) do
		n = n + 1
	end

	return string.format(
		"Last scan %s ago, %d auctions, %d items",
		AL.FormatDuration(time() - realm.lastScan),
		realm.lastRows,
		n
	)
end

function Auctioneer:GetOptions()
	return {
		type = "group",
		name = "Auctioneer",
		args = {
			enabled = {
				type = "toggle",
				name = "Enabled",
				order = 1,
				get = function()
					return self.db.profile.enabled
				end,
				set = function(_, value)
					self.db.profile.enabled = value
					self:Refresh()
				end,
			},
			openWithAH = {
				type = "toggle",
				name = "Open with the Auction House",
				order = 2,
				get = function()
					return self.db.profile.openWithAH
				end,
				set = function(_, value)
					self.db.profile.openWithAH = value
				end,
			},
			show = {
				type = "execute",
				name = "Show window",
				order = 3,
				func = function()
					self:Toggle()
				end,
			},
			scan = {
				type = "execute",
				name = "Scan now",
				order = 4,
				disabled = function()
					return not self:CanScan()
				end,
				func = function()
					self:Scan()
				end,
			},
			dealsHeader = { type = "header", name = "Deals", order = 10 },
			discount = {
				type = "range",
				name = "Buy below market by (%)",
				order = 11,
				min = 10,
				max = 80,
				step = 5,
				get = function()
					return self.db.profile.discount
				end,
				set = function(_, value)
					self.db.profile.discount = value
					self:Recompute()
				end,
			},
			minProfit = {
				type = "range",
				name = "Minimum profit (silver)",
				order = 12,
				min = 0,
				max = 10000,
				step = 10,
				get = function()
					return self.db.profile.minProfit
				end,
				set = function(_, value)
					self.db.profile.minProfit = value
					self:Recompute()
				end,
			},
			cut = {
				type = "range",
				name = "Auction House cut (%)",
				order = 13,
				min = 0,
				max = 15,
				step = 1,
				get = function()
					return self.db.profile.cut
				end,
				set = function(_, value)
					self.db.profile.cut = value
					self:Recompute()
				end,
			},
			windowHeader = { type = "header", name = "Window", order = 20 },
			font = {
				type = "select",
				name = "Font",
				order = 21,
				dialogControl = "LSM30_Font",
				values = function()
					return ns.Media:Values("font", self.db.profile.font)
				end,
				get = function()
					return self.db.profile.font
				end,
				set = function(_, value)
					self.db.profile.font = value
					Window:Layout()
				end,
			},
			fontSize = {
				type = "range",
				name = "Font size",
				order = 22,
				min = 8,
				max = 20,
				step = 1,
				get = function()
					return self.db.profile.fontSize
				end,
				set = function(_, value)
					self.db.profile.fontSize = value
					Window:Layout()
				end,
			},
			dataHeader = { type = "header", name = "Data", order = 30 },
			retentionDays = {
				type = "range",
				name = "Keep price history (days)",
				order = 31,
				min = 3,
				max = 30,
				step = 1,
				get = function()
					return self.db.profile.retentionDays
				end,
				set = function(_, value)
					self.db.profile.retentionDays = value
				end,
			},
			status = {
				type = "description",
				order = 32,
				name = function()
					return self:StatusText()
				end,
			},
			clear = {
				type = "execute",
				name = "Clear price data",
				order = 33,
				confirm = true,
				func = function()
					local realm = self.db.factionrealm
					realm.items = {}
					realm.lastScan = 0
					realm.lastRows = 0
					self:Recompute()
				end,
			},
		},
	}
end

function Auctioneer:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function checkFn(apiName, fn)
					if type(fn) ~= "function" then
						table.insert(missing, apiName)
					end
				end

				local ah = type(C_AuctionHouse) == "table" and C_AuctionHouse or {}
				checkFn("C_AuctionHouse.ReplicateItems", ah.ReplicateItems)
				checkFn("C_AuctionHouse.GetNumReplicateItems", ah.GetNumReplicateItems)
				checkFn("C_AuctionHouse.GetReplicateItemInfo", ah.GetReplicateItemInfo)
				checkFn("C_AuctionHouse.GetReplicateItemTimeLeft", ah.GetReplicateItemTimeLeft)

				local item = type(C_Item) == "table" and C_Item or {}
				checkFn("C_Item.GetItemInfo", item.GetItemInfo)
				checkFn("C_Item.GetItemQualityColor", item.GetItemQualityColor)
				checkFn("GameTooltip.SetItemByID", GameTooltip and GameTooltip.SetItemByID)

				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "search api",
			run = function()
				if type(AuctionHouseFrame) ~= "table" then
					return "SKIP", "auction house not loaded"
				end

				local bar = AuctionHouseFrame.SearchBar
				if
					type(bar) ~= "table"
					or type(bar.SetSearchText) ~= "function"
					or type(bar.StartSearch) ~= "function"
				then
					return "FAIL", "search bar unavailable"
				end
				return "PASS"
			end,
		},
		{
			name = "money format",
			run = function()
				local text = AL.FormatMoney(10203)
				if text == "1g 2s 3c" then
					return "PASS"
				end
				return "FAIL", text
			end,
		},
		{
			name = "data",
			run = function()
				local realm = self.db.factionrealm
				local count, bytes = 0, 0
				for _, item in pairs(realm.items) do
					count = count + 1
					bytes = bytes + #(item.h or "") + #(item.s or "")
				end
				local age = realm.lastScan > 0 and (time() - realm.lastScan) or nil
				return "INFO", count, age, realm.lastRows, bytes, self.ingestMs
			end,
		},
		{
			name = "throttle",
			run = function()
				return "INFO", SL.ThrottleLeft(time(), self.db.global.lastReplicate)
			end,
		},
		{
			name = "auction house",
			run = function()
				return "INFO", self.ahOpen == true, Scanner:State()
			end,
		},
	}
end
