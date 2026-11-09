local addonName, ns = ...

local AL = ns.AuctioneerLogic
local TL = ns.AuctioneerTradeLogic
local Theme = ns.Theme

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local WIDTH = 560
local PAD = 8
local HEADER_HEIGHT = 24
local TAB_HEIGHT = 22
local SUMMARY_HEIGHT = 20
local COLUMN_HEIGHT = 20
local FOOTER_HEIGHT = 20
local ROWS = 16
local MAX_COLS = 6

local EMPTY_NO_DATA = "No scan yet. Open the Auction House and press Scan."
local EMPTY_TAB = "Nothing here."
local EMPTY_LEDGER = "No trades recorded yet. Visit a mailbox after buying or selling."
local TOOLTIP_HINT = "Click to search the Auction House"

local TABS = {
	{ key = "deals", label = "Buy" },
	{ key = "sell", label = "Sell" },
	{ key = "ledger", label = "Ledger" },
	{ key = "movers", label = "Movers" },
	{ key = "hot", label = "Hot" },
	{ key = "avoid", label = "Avoid" },
}

local COLUMNS = {
	deals = {
		{ title = "Item", width = 214, align = "LEFT" },
		{ title = "Qty", width = 46, align = "RIGHT" },
		{ title = "Pay up to", width = 74, align = "RIGHT" },
		{ title = "Sell at", width = 74, align = "RIGHT" },
		{ title = "Profit", width = 74, align = "RIGHT" },
		{ title = "Type", width = 62, align = "RIGHT" },
	},
	sell = {
		{ title = "Item", width = 200, align = "LEFT" },
		{ title = "Qty", width = 44, align = "RIGHT" },
		{ title = "Post at", width = 74, align = "RIGHT" },
		{ title = "Value", width = 80, align = "RIGHT" },
		{ title = "Profit", width = 74, align = "RIGHT" },
		{ title = "Action", width = 72, align = "RIGHT" },
	},
	ledger = {
		{ title = "Item", width = 200, align = "LEFT" },
		{ title = "Held", width = 44, align = "RIGHT" },
		{ title = "Avg cost", width = 76, align = "RIGHT" },
		{ title = "Market", width = 76, align = "RIGHT" },
		{ title = "Unrealised", width = 74, align = "RIGHT" },
		{ title = "Realised", width = 74, align = "RIGHT" },
	},
	movers = {
		{ title = "Item", width = 314, align = "LEFT" },
		{ title = "Now", width = 80, align = "RIGHT" },
		{ title = "Usual", width = 80, align = "RIGHT" },
		{ title = "Change", width = 70, align = "RIGHT" },
	},
	hot = {
		{ title = "Item", width = 234, align = "LEFT" },
		{ title = "Sold/day", width = 70, align = "RIGHT" },
		{ title = "Price", width = 80, align = "RIGHT" },
		{ title = "Per day", width = 90, align = "RIGHT" },
		{ title = "Listed", width = 70, align = "RIGHT" },
	},
	avoid = {
		{ title = "Item", width = 150, align = "LEFT" },
		{ title = "Price", width = 70, align = "RIGHT" },
		{ title = "Listed", width = 60, align = "RIGHT" },
		{ title = "Why", width = 264, align = "LEFT" },
	},
}

local Window = {}
ns.AuctioneerWindow = Window

local function setColor(tex, color)
	tex:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function setTextColor(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4])
end

local function createButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent)
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	setColor(bg, Theme.color.button)

	local fs = button:CreateFontString(nil, "OVERLAY")
	fs:SetAllPoints()
	fs:SetJustifyH("CENTER")
	setTextColor(fs, Theme.color.text)
	button.text = fs
	button.label = text

	button:SetScript("OnEnter", function()
		setColor(bg, Theme.color.buttonHover)
	end)
	button:SetScript("OnLeave", function()
		setColor(bg, Theme.color.button)
	end)
	button:SetScript("OnClick", onClick)
	return button
end

local function setButtonFont(button, font, size)
	ns.Media:SetFont(button.text, font, size, "")
	button.text:SetText(button.label)
end

local function itemName(row)
	local name = row.name or ("Item " .. row.itemID)
	return (name:gsub("|", "||"))
end

local function itemColor(row)
	if Window.hasQualityColor and type(row.quality) == "number" then
		local r, g, b = C_Item.GetItemQualityColor(row.quality)
		if r then
			return r, g, b
		end
	end
	local t = Theme.color.text
	return t[1], t[2], t[3]
end

local function cell(text, color)
	return { text = text, r = color[1], g = color[2], b = color[3] }
end

local function itemCell(row)
	local r, g, b = itemColor(row)
	return { text = itemName(row), r = r, g = g, b = b }
end

local function profitColor(value)
	if type(value) ~= "number" then
		return Theme.color.text
	elseif value > 0 then
		return Theme.color.accent
	elseif value < 0 then
		return Theme.color.error
	end
	return Theme.color.text
end

local function dealsCells(row)
	local kind
	if row.kind == "vendor" then
		kind = "Vendor"
	elseif row.rateKnown then
		kind = "Flip"
	else
		kind = "Flip?"
	end
	return {
		itemCell(row),
		cell(tostring(row.qty), Theme.color.text),
		cell(AL.FormatMoney(row.unitMax), Theme.color.text),
		cell(AL.FormatMoney(row.sellUnit), Theme.color.text),
		cell(AL.FormatMoney(row.profit), Theme.color.text),
		cell(kind, Theme.color.text),
	}
end

local function sellCells(row)
	return {
		itemCell(row),
		cell(tostring(row.qty), Theme.color.text),
		cell(AL.FormatMoney(row.price), Theme.color.text),
		cell(AL.FormatMoney(row.value), Theme.color.text),
		cell(AL.FormatMoney(row.profit), profitColor(row.profit)),
		cell(TL.ADVICE[row.advice] or row.advice, Theme.color.text),
	}
end

local function ledgerCells(row)
	return {
		itemCell(row),
		cell(tostring(row.held), Theme.color.text),
		cell(AL.FormatMoney(row.unitCost), Theme.color.text),
		cell(AL.FormatMoney(row.market), Theme.color.text),
		cell(AL.FormatMoney(row.unrealised), profitColor(row.unrealised)),
		cell(AL.FormatMoney(row.realised), profitColor(row.realised)),
	}
end

local function moversCells(row)
	local changeColor = Theme.color.text
	if type(row.change) == "number" then
		if row.change > 0 then
			changeColor = Theme.color.accent
		elseif row.change < 0 then
			changeColor = Theme.color.error
		end
	end
	return {
		itemCell(row),
		cell(AL.FormatMoney(row.cur), Theme.color.text),
		cell(AL.FormatMoney(row.ref), Theme.color.text),
		cell(AL.FormatPercent(row.change), changeColor),
	}
end

local function hotCells(row)
	return {
		itemCell(row),
		cell(string.format("%.1f", row.soldPerDay), Theme.color.text),
		cell(AL.FormatMoney(row.market), Theme.color.text),
		cell(AL.FormatMoney(row.volume), Theme.color.text),
		cell(tostring(row.qty), Theme.color.text),
	}
end

local function avoidCells(row)
	local parts = {}
	for _, code in ipairs(row.reasons) do
		table.insert(parts, AL.REASONS[code] or code)
	end
	return {
		itemCell(row),
		cell(AL.FormatMoney(row.market), Theme.color.text),
		cell(tostring(row.qty), Theme.color.text),
		cell(table.concat(parts, ", "), Theme.color.text),
	}
end

local ROW_CELLS = {
	deals = dealsCells,
	sell = sellCells,
	ledger = ledgerCells,
	movers = moversCells,
	hot = hotCells,
	avoid = avoidCells,
}

function Window:Create(opts)
	if self.frame then
		return
	end

	self.opts = opts
	self.offset = 0
	self.data = nil
	self.hasQualityColor = type(C_Item) == "table" and type(C_Item.GetItemQualityColor) == "function"

	local frame = CreateFrame("Frame", "MerrinxUIAuctioneer", UIParent, "BackdropTemplate")
	frame:Hide()
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({ edgeFile = TEXTURE, edgeSize = 1 })
	local border = Theme.color.border
	frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		self:Scroll(-delta)
	end)
	self.frame = frame

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	setColor(bg, Theme.color.bg)
	self.bg = bg

	self:CreateHeader()
	self:CreateTabs()
	self:CreateSummary()
	self:CreateColumnHeaders()
	self:CreateRows()
	self:CreateFooter()

	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "MerrinxUIAuctioneer")
	end

	ns.Mover:Register(frame, "Auctioneer", function()
		return opts.getProfile().position
	end)
end

function Window:CreateHeader()
	local frame = self.frame
	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT")
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
	self.header = header

	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	setColor(headerBg, Theme.color.header)
	self.headerBg = headerBg

	local close = createButton(header, "x", function()
		self:Hide()
	end)
	close:SetPoint("RIGHT", header, "RIGHT", -4, 0)
	close:HookScript("OnEnter", function()
		setTextColor(close.text, Theme.color.error)
	end)
	close:HookScript("OnLeave", function()
		setTextColor(close.text, Theme.color.text)
	end)
	self.closeButton = close

	local scan = createButton(header, "Scan", function()
		self.opts.onScan()
	end)
	scan:SetPoint("RIGHT", close, "LEFT", -4, 0)
	self.scanButton = scan

	local title = header:CreateFontString(nil, "OVERLAY")
	title:SetPoint("LEFT", header, "LEFT", PAD, 0)
	title:SetPoint("RIGHT", scan, "LEFT", -6, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	title.text = "Auctioneer"
	setTextColor(title, Theme.color.text)
	self.title = title
end

function Window:CreateTabs()
	local frame = self.frame
	local tabBar = CreateFrame("Frame", nil, frame)
	tabBar:SetHeight(TAB_HEIGHT)
	tabBar:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT")
	tabBar:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT")
	self.tabBar = tabBar

	self.tabs = {}
	local prev
	for _, def in ipairs(TABS) do
		local tab = CreateFrame("Button", nil, tabBar)
		tab:SetHeight(TAB_HEIGHT)
		tab.key = def.key

		local label = tab:CreateFontString(nil, "OVERLAY")
		label:SetPoint("CENTER", tab, "CENTER", 0, 1)
		label.text = def.label
		tab.label = label

		local accentBar = tab:CreateTexture(nil, "ARTWORK")
		accentBar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT")
		accentBar:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT")
		accentBar:SetHeight(Theme.geometry.activeBar)
		setColor(accentBar, Theme.color.accent)
		tab.accentBar = accentBar

		tab:SetScript("OnClick", function()
			self:SetTab(def.key)
		end)

		if prev then
			tab:SetPoint("LEFT", prev, "RIGHT", 0, 0)
		else
			tab:SetPoint("LEFT", tabBar, "LEFT", PAD, 0)
		end
		prev = tab
		self.tabs[def.key] = tab
	end
end

function Window:CreateSummary()
	local frame = CreateFrame("Frame", nil, self.frame)
	frame:SetHeight(SUMMARY_HEIGHT)
	frame:SetPoint("TOPLEFT", self.tabBar, "BOTTOMLEFT")
	frame:SetPoint("TOPRIGHT", self.tabBar, "BOTTOMRIGHT")
	self.summaryBar = frame

	local text = frame:CreateFontString(nil, "OVERLAY")
	text:SetPoint("LEFT", frame, "LEFT", PAD, 0)
	text:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	setTextColor(text, Theme.color.textDim)
	self.summaryText = text
end

function Window:CreateColumnHeaders()
	local header = CreateFrame("Frame", nil, self.frame)
	header:SetHeight(COLUMN_HEIGHT)
	header:SetPoint("TOPLEFT", self.summaryBar, "BOTTOMLEFT")
	header:SetPoint("TOPRIGHT", self.summaryBar, "BOTTOMRIGHT")
	self.columnHeader = header

	self.columnLabels = {}
	for i = 1, MAX_COLS do
		local fs = header:CreateFontString(nil, "OVERLAY")
		setTextColor(fs, Theme.color.textDim)
		fs:SetWordWrap(false)
		self.columnLabels[i] = fs
	end
end

function Window:CreateRows()
	self.rows = {}
	for i = 1, ROWS do
		self.rows[i] = self:CreateRow(i)
	end
end

function Window:CreateRow(i)
	local row = CreateFrame("Button", nil, self.frame)

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	setColor(bg, (i % 2 == 1) and Theme.color.rowA or Theme.color.rowB)
	row.bg = bg

	local hover = row:CreateTexture(nil, "BORDER")
	hover:SetAllPoints()
	setColor(hover, Theme.color.hover)
	hover:Hide()
	row.hover = hover

	row.cells = {}
	for c = 1, MAX_COLS do
		local fs = row:CreateFontString(nil, "OVERLAY")
		fs:SetWordWrap(false)
		row.cells[c] = fs
	end

	row:SetScript("OnEnter", function()
		hover:Show()
		self:ShowTooltip(row)
	end)
	row:SetScript("OnLeave", function()
		hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function()
		if row.itemID then
			self.opts.onSearch(row.itemID)
		end
	end)

	row:Hide()
	return row
end

function Window:CreateFooter()
	local status = self.frame:CreateFontString(nil, "OVERLAY")
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)
	setTextColor(status, Theme.color.textDim)
	self.status = status

	local empty = self.frame:CreateFontString(nil, "OVERLAY")
	empty:SetJustifyH("CENTER")
	empty:SetWordWrap(true)
	setTextColor(empty, Theme.color.textDim)
	self.empty = empty
end

function Window:ApplyColumns()
	local profile = self.opts.getProfile()
	local columns = COLUMNS[profile.tab] or COLUMNS.deals
	self.columns = columns

	local x = PAD
	for i = 1, MAX_COLS do
		local def = columns[i]
		local label = self.columnLabels[i]
		if def then
			label:SetText(def.title)
			label:SetJustifyH(def.align)
			label:ClearAllPoints()
			label:SetPoint("TOPLEFT", self.columnHeader, "TOPLEFT", x, 0)
			label:SetSize(def.width, COLUMN_HEIGHT)
			label:Show()
			x = x + def.width
		else
			label:Hide()
		end
	end

	for _, row in ipairs(self.rows) do
		local rx = PAD
		for c = 1, MAX_COLS do
			local def = columns[c]
			local fs = row.cells[c]
			if def then
				fs:ClearAllPoints()
				fs:SetPoint("LEFT", row, "LEFT", rx, 0)
				fs:SetWidth(def.width)
				fs:SetJustifyH(def.align)
				fs:Show()
				rx = rx + def.width
			else
				fs:Hide()
			end
		end
	end
end

function Window:Layout()
	local profile = self.opts.getProfile()
	local frame = self.frame
	local rowHeight = profile.fontSize + 6

	frame:SetSize(WIDTH, HEADER_HEIGHT + TAB_HEIGHT + SUMMARY_HEIGHT + COLUMN_HEIGHT + rowHeight * ROWS + FOOTER_HEIGHT)

	ns.Media:SetFont(self.title, profile.font, profile.fontSize, "")
	self.title:SetText(self.title.text)

	setButtonFont(self.scanButton, profile.font, profile.fontSize)
	self.scanButton:SetSize(self.scanButton.text:GetStringWidth() + 16, HEADER_HEIGHT - 4)

	setButtonFont(self.closeButton, profile.font, profile.fontSize)
	self.closeButton:SetSize(HEADER_HEIGHT - 4, HEADER_HEIGHT - 4)

	for _, def in ipairs(TABS) do
		local tab = self.tabs[def.key]
		ns.Media:SetFont(tab.label, profile.font, profile.fontSize, "")
		tab.label:SetText(tab.label.text)
		tab:SetWidth(tab.label:GetStringWidth() + 16)
	end

	ns.Media:SetFont(self.summaryText, profile.font, profile.fontSize, "")

	for i = 1, MAX_COLS do
		ns.Media:SetFont(self.columnLabels[i], profile.font, profile.fontSize, "")
	end

	for _, row in ipairs(self.rows) do
		row:SetSize(WIDTH, rowHeight)
		for c = 1, MAX_COLS do
			ns.Media:SetFont(row.cells[c], profile.font, profile.fontSize, "")
		end
	end

	self:ApplyColumns()

	for i, row in ipairs(self.rows) do
		row:ClearAllPoints()
		row:SetPoint(
			"TOPLEFT",
			frame,
			"TOPLEFT",
			0,
			-(HEADER_HEIGHT + TAB_HEIGHT + SUMMARY_HEIGHT + COLUMN_HEIGHT + (i - 1) * rowHeight)
		)
	end

	ns.Media:SetFont(self.status, profile.font, profile.fontSize, "")
	self.status:ClearAllPoints()
	self.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 4)
	self.status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 4)
	self.status:SetText(self.pendingStatus or "")

	ns.Media:SetFont(self.empty, profile.font, profile.fontSize, "")
	self.empty:ClearAllPoints()
	self.empty:SetPoint(
		"TOPLEFT",
		frame,
		"TOPLEFT",
		PAD,
		-(HEADER_HEIGHT + TAB_HEIGHT + SUMMARY_HEIGHT + COLUMN_HEIGHT + 6)
	)
	self.empty:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, 0)

	self.fontsReady = true
	self:RedrawTabs()
	self:RedrawRows()

	ns.Mover:Apply(frame)
end

function Window:RedrawTabs()
	local profile = self.opts.getProfile()
	for key, tab in pairs(self.tabs) do
		local active = profile.tab == key
		tab.accentBar:SetShown(active)
		setTextColor(tab.label, active and Theme.color.text or Theme.color.textDim)
	end
end

function Window:CurrentList()
	local profile = self.opts.getProfile()
	local data = self.data
	return (data and data[profile.tab]) or {}
end

function Window:RedrawRows()
	local profile = self.opts.getProfile()
	local list = self:CurrentList()

	self.offset = math.max(0, math.min(self.offset, math.max(0, #list - ROWS)))
	local shown = math.max(0, math.min(ROWS, #list - self.offset))

	local builder = ROW_CELLS[profile.tab] or ROW_CELLS.deals

	for i = 1, shown do
		local row = self.rows[i]
		local data = list[self.offset + i]
		row.itemID = data.itemID
		row.data = data
		local cells = builder(data)
		for c = 1, MAX_COLS do
			local cellDef = cells[c]
			if cellDef then
				local fs = row.cells[c]
				fs:SetText(cellDef.text)
				fs:SetTextColor(cellDef.r, cellDef.g, cellDef.b)
			end
		end
		row:Show()
	end

	for i = shown + 1, #self.rows do
		self.rows[i].itemID = nil
		self.rows[i].data = nil
		self.rows[i]:Hide()
	end

	self.summaryText:SetText((self.data and self.data.summary and self.data.summary[profile.tab]) or "")

	if #list == 0 then
		local emptyText
		if self.data == nil then
			emptyText = EMPTY_NO_DATA
		elseif profile.tab == "ledger" then
			emptyText = EMPTY_LEDGER
		elseif not self.data.scanned then
			emptyText = EMPTY_NO_DATA
		else
			emptyText = EMPTY_TAB
		end
		self.empty:SetText(emptyText)
		self.empty:Show()
	else
		self.empty:Hide()
	end
end

function Window:SetData(view)
	self.data = view
	if self.fontsReady then
		self:RedrawRows()
	end
end

function Window:SetStatus(text)
	self.pendingStatus = text or ""
	if self.fontsReady then
		self.status:SetText(self.pendingStatus)
	end
end

function Window:SetScanEnabled(enabled, label)
	local button = self.scanButton
	button.label = label or button.label or "Scan"
	if enabled then
		button:Enable()
		button:SetAlpha(1)
	else
		button:Disable()
		button:SetAlpha(Theme.disabledAlpha)
	end
	local profile = self.opts.getProfile()
	setButtonFont(button, profile.font, profile.fontSize)
	button:SetSize(button.text:GetStringWidth() + 16, HEADER_HEIGHT - 4)
end

function Window:Show()
	self.frame:Show()
end

function Window:Hide()
	GameTooltip:Hide()
	self.frame:Hide()
end

function Window:Toggle()
	if self.frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function Window:IsShown()
	return self.frame:IsShown() and true or false
end

function Window:SetTab(key)
	local profile = self.opts.getProfile()
	profile.tab = key
	self.offset = 0
	self:ApplyColumns()
	self:RedrawTabs()
	self:RedrawRows()
end

function Window:Scroll(delta)
	local list = self:CurrentList()
	local max = math.max(0, #list - ROWS)
	self.offset = math.max(0, math.min(max, self.offset + delta))
	self:RedrawRows()
end

function Window:ShowTooltip(row)
	local data = row.data
	if not data then
		return
	end

	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")

	if data.itemID then
		GameTooltip:SetItemByID(data.itemID)

		if data.reasons then
			for _, code in ipairs(data.reasons) do
				GameTooltip:AddLine(AL.REASONS[code] or code, 1, 1, 1)
			end
		end

		local profile = self.opts.getProfile()
		if profile.tab == "deals" then
			if data.kind == "flip" and data.rateKnown == false then
				GameTooltip:AddLine("Sell rate unknown, the plan buys one auction to test", 1, 1, 1)
			end
			if data.soldPerDay then
				GameTooltip:AddLine(string.format("Sells about %.1f a day", data.soldPerDay), 1, 1, 1)
			end
		end

		local dim = Theme.color.textDim
		GameTooltip:AddLine(TOOLTIP_HINT, dim[1], dim[2], dim[3])
	else
		GameTooltip:AddLine(itemName(data), 1, 1, 1)
	end

	GameTooltip:Show()
end

ns.Debug:RegisterChecks("Auctioneer", function()
	return {
		{
			name = "window",
			run = function()
				if not Window.frame then
					return "SKIP", "not created"
				end
				local ok = #Window.rows == ROWS
				local profile = Window.opts.getProfile()
				return ok and "PASS" or "FAIL", Window.frame:IsShown(), profile.tab
			end,
		},
		{
			name = "rows",
			run = function()
				if not Window.frame then
					return "SKIP", "not created"
				end
				return "INFO", #Window:CurrentList(), Window.offset
			end,
		},
	}
end)
