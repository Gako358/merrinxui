local addonName, ns = ...

local L = ns.GearAdvisorLogic
local Theme = ns.Theme
local ACCENT = Theme.color.accent
local TEXT = Theme.color.text
local TEXT_DIM = Theme.color.textDim

local UP_COLOR = { 0.3, 1, 0.3 }
local DOWN_COLOR = { 1, 0.3, 0.25 }

local GearAdvisor = ns.addon:NewModule("GearAdvisor", "AceEvent-3.0")

local defaults = {
	profile = { enabled = false, tooltip = true, bags = true },
	char = { spec = nil },
}

local tooltipHooked = false

local function readLink(link)
	if link == nil then
		return "empty"
	end
	if issecretvalue(link) then
		return "secret"
	end

	local name, _, _, _, minLevel = C_Item.GetItemInfo(link)
	if name == nil then
		return "uncached"
	end

	local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
	local stats = L.Normalize(C_Item.GetItemStats(link), issecretvalue)
	return {
		link = link,
		stats = stats,
		equipLoc = equipLoc,
		classID = classID,
		subClassID = subClassID,
		minLevel = minLevel,
	}
end

local function candidate(link)
	local info = readLink(link)
	if type(info) ~= "table" then
		return nil
	end
	return info
end

local function OnTooltipPostCall(tooltip, _)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
		return
	end
	if not GearAdvisor:IsEnabled() or not GearAdvisor.db.profile.tooltip then
		return
	end
	if #GearAdvisor.specs == 0 then
		return
	end

	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	if link == nil or issecretvalue(link) then
		return
	end

	local item = candidate(link)
	if item == nil then
		return
	end

	local equipped = GearAdvisor:Equipped()
	if equipped == nil then
		return
	end

	local ctx = { class = GearAdvisor.class, level = GearAdvisor.level }
	local probe = L.Evaluate(item, equipped, GearAdvisor.specs[1].weights, ctx)
	if probe == nil or not probe.usable or probe.equipped then
		return
	end

	tooltip:AddLine("Upgrade", ACCENT[1], ACCENT[2], ACCENT[3])

	local selected = GearAdvisor:SelectedSpec()
	for _, spec in ipairs(GearAdvisor.specs) do
		local result = L.Evaluate(item, equipped, spec.weights, ctx)
		local text, kind = L.FormatDelta(result)

		local lr, lg, lb
		if selected and spec.key == selected.key then
			lr, lg, lb = ACCENT[1], ACCENT[2], ACCENT[3]
		else
			lr, lg, lb = TEXT[1], TEXT[2], TEXT[3]
		end

		local rr, rg, rb
		if kind == "up" or kind == "new" then
			rr, rg, rb = UP_COLOR[1], UP_COLOR[2], UP_COLOR[3]
		elseif kind == "down" then
			rr, rg, rb = DOWN_COLOR[1], DOWN_COLOR[2], DOWN_COLOR[3]
		else
			rr, rg, rb = TEXT_DIM[1], TEXT_DIM[2], TEXT_DIM[3]
		end

		tooltip:AddDoubleLine(spec.name, text, lr, lg, lb, rr, rg, rb)
	end
end

function GearAdvisor:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("GearAdvisor", defaults)
	self:SetEnabledState(self.db.profile.enabled)

	local _, class = UnitClass("player")
	self.class = class
	self.specs = ns.GearAdvisorData.SPECS[class] or {}
	self.level = UnitLevel("player")
	self.dirty = true
end

function GearAdvisor:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Invalidate")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "Invalidate")
	self:RegisterEvent("PLAYER_LEVEL_UP", "OnLevelUp")

	if
		not tooltipHooked
		and type(TooltipDataProcessor) == "table"
		and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
		and type(Enum.TooltipDataType) == "table"
		and Enum.TooltipDataType.Item ~= nil
	then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipPostCall)
		tooltipHooked = true
	end

	self.dirty = true
	self.level = UnitLevel("player")

	if self.db.profile.bags then
		ns.GearAdvisorBags:Enable(self)
	end
end

function GearAdvisor:OnLevelUp(_, level)
	if type(level) == "number" then
		self.level = level
	end
	self:Invalidate()
end

function GearAdvisor:OnDisable()
	ns.GearAdvisorBags:Disable()
end

function GearAdvisor:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			if self.db.profile.bags then
				ns.GearAdvisorBags:Enable(self)
			else
				ns.GearAdvisorBags:Disable()
			end
			self:Invalidate()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function GearAdvisor:Invalidate()
	self.dirty = true
	ns.GearAdvisorBags:Update()
end

function GearAdvisor:SelectedSpec()
	return L.SpecByKey(self.specs, self.db.char.spec)
end

function GearAdvisor:Equipped()
	if not self.dirty and self.equipped ~= nil then
		return self.equipped
	end

	local equipped = {}
	for _, slot in ipairs(L.EQUIPPED_SLOTS) do
		local info = readLink(GetInventoryItemLink("player", slot))
		if info == "uncached" or info == "secret" then
			return nil
		end
		if type(info) == "table" then
			if info.stats == nil then
				return nil
			end
			equipped[slot] = { link = info.link, stats = info.stats, equipLoc = info.equipLoc }
		end
	end

	self.equipped = equipped
	self.dirty = false
	return equipped
end

function GearAdvisor:Evaluate(link, specKey)
	local spec
	if specKey ~= nil then
		spec = L.SpecByKey(self.specs, specKey)
	else
		spec = self:SelectedSpec()
	end
	if spec == nil then
		return nil
	end

	local item = candidate(link)
	if item == nil then
		return nil
	end

	local equipped = self:Equipped()
	if equipped == nil then
		return nil
	end

	return L.Evaluate(item, equipped, spec.weights, { class = self.class, level = self.level })
end

function GearAdvisor:GetTabOptions()
	local function get(key)
		return function()
			return self.db.profile[key]
		end
	end
	local function set(key)
		return function(_, value)
			self.db.profile[key] = value
			self:Refresh()
		end
	end

	return {
		type = "group",
		name = "Gear",
		args = {
			enabled = {
				type = "toggle",
				name = "Enabled",
				order = 1,
				get = get("enabled"),
				set = set("enabled"),
			},
			spec = {
				type = "select",
				name = "Spec",
				order = 2,
				values = function()
					local values = {}
					for _, spec in ipairs(self.specs) do
						values[spec.key] = spec.name
					end
					return values
				end,
				disabled = function()
					return #self.specs == 0
				end,
				get = function()
					return self.db.char.spec
				end,
				set = function(_, value)
					self.db.char.spec = value
					self:Invalidate()
				end,
			},
			tooltip = {
				type = "toggle",
				name = "Tooltip",
				order = 3,
				get = get("tooltip"),
				set = set("tooltip"),
			},
			bags = {
				type = "toggle",
				name = "Bag markers",
				order = 4,
				get = get("bags"),
				set = set("bags"),
			},
			note = {
				type = "description",
				order = 5,
				name = "Scores use MerrinxUI's own leveling stat weights. WoW: Forever can't detect your talent spec, "
					.. "so pick it here.",
			},
		},
	}
end

function GearAdvisor:GetDebugChecks()
	return {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function check(name, ok)
					if not ok then
						table.insert(missing, name)
					end
				end

				check(
					"TooltipDataProcessor.AddTooltipPostCall",
					type(TooltipDataProcessor) == "table"
						and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
				)
				check(
					"TooltipUtil.GetDisplayedItem",
					type(TooltipUtil) == "table" and type(TooltipUtil.GetDisplayedItem) == "function"
				)
				check("C_Item.GetItemStats", type(C_Item) == "table" and type(C_Item.GetItemStats) == "function")
				check("C_Item.GetItemInfo", type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function")
				check(
					"C_Item.GetItemInfoInstant",
					type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function"
				)
				check("GetInventoryItemLink", type(GetInventoryItemLink) == "function")
				check(
					"Enum.TooltipDataType.Item",
					type(Enum) == "table"
						and type(Enum.TooltipDataType) == "table"
						and type(Enum.TooltipDataType.Item) == "number"
				)

				table.sort(missing)
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "tooltip",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return tooltipHooked and "PASS" or "FAIL"
			end,
		},
		{
			name = "spec",
			run = function()
				return "INFO", self.class, self.db.char.spec or "unset", self.level
			end,
		},
		{
			name = "equipped",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local equipped = self:Equipped()
				local count = 0
				if equipped then
					for _ in pairs(equipped) do
						count = count + 1
					end
				end

				local totalScore = 0
				local spec = self:SelectedSpec()
				if equipped and spec then
					for _, item in pairs(equipped) do
						totalScore = totalScore + L.Score(item.stats, spec.weights, item.equipLoc)
					end
				end

				return "INFO", count, self.dirty, totalScore
			end,
		},
		{
			name = "raw stats",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local parts = {}
				for _, slot in ipairs({ 5, 16 }) do
					local link = GetInventoryItemLink("player", slot)
					if link ~= nil and not issecretvalue(link) then
						local raw = C_Item.GetItemStats(link)
						if type(raw) == "table" then
							for key, value in pairs(raw) do
								if not issecretvalue(key) and not issecretvalue(value) then
									table.insert(parts, slot .. ":" .. key .. "=" .. tostring(value))
								end
							end
						end
					end
				end

				if #parts == 0 then
					return "INFO", "none"
				end
				return "INFO", unpack(parts, 1, #parts)
			end,
		},
	}
end
