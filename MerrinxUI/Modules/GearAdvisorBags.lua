local addonName, ns = ...

local L = ns.GearAdvisorLogic

local Bags = {}
ns.GearAdvisorBags = Bags

local markers = setmetatable({}, { __mode = "k" })
local hooked = {}
local upgradeCache = {}
local owner = nil

local function ensureMarker(button)
	local marker = markers[button]
	if marker then
		return marker
	end

	marker = button:CreateTexture(nil, "OVERLAY", nil, 7)
	marker:SetSize(14, 14)
	marker:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
	marker:SetTexture(ns.Media:Icon("open"))
	marker:SetVertexColor(0.3, 1, 0.3)
	marker:Hide()
	markers[button] = marker
	return marker
end

local function isUpgrade(link)
	local cached = upgradeCache[link]
	if cached ~= nil then
		return cached
	end

	local result = owner:Evaluate(link)
	local upgrade = L.IsUpgrade(result)
	if result ~= nil then
		upgradeCache[link] = upgrade
	end
	return upgrade
end

local function updateButton(button)
	local marker = ensureMarker(button)
	marker:Hide()

	if not owner or not owner:IsEnabled() or not owner.db.profile.bags then
		return
	end
	if button:IsProtected() then
		return
	end

	local link = C_Container.GetContainerItemLink(button:GetBagID(), button:GetID())
	if link == nil or issecretvalue(link) then
		return
	end

	if isUpgrade(link) then
		marker:Show()
	end
end

local function updateFrame(frame)
	for _, button in frame:EnumerateValidItems() do
		updateButton(button)
	end
end

local function hookFrame(frame)
	if frame == nil or hooked[frame] then
		return
	end
	hooked[frame] = true
	hooksecurefunc(frame, "UpdateItems", updateFrame)
end

local function hookAllFrames()
	if type(ContainerFrameUtil_EnumerateContainerFrames) == "function" then
		for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
			hookFrame(frame)
		end
	end
	hookFrame(ContainerFrameCombinedBags)
end

function Bags:Enable(mod)
	owner = mod
	hookAllFrames()
	self:Update()
end

function Bags:Disable()
	owner = nil
	for frame in pairs(hooked) do
		if frame:IsShown() then
			for _, button in frame:EnumerateValidItems() do
				local marker = markers[button]
				if marker then
					marker:Hide()
				end
			end
		end
	end
end

function Bags:Update()
	wipe(upgradeCache)
	for frame in pairs(hooked) do
		if frame:IsShown() then
			updateFrame(frame)
		end
	end
end

function Bags:CountMarkers()
	local shown, protectedSkips = 0, 0
	for frame in pairs(hooked) do
		if frame:IsShown() then
			for _, button in frame:EnumerateValidItems() do
				if button:IsProtected() then
					protectedSkips = protectedSkips + 1
				elseif markers[button] and markers[button]:IsShown() then
					shown = shown + 1
				end
			end
		end
	end
	return shown, protectedSkips
end

ns.Debug:RegisterChecks("GearAdvisor", function()
	return {
		{
			name = "bag apis",
			run = function()
				local missing = {}
				if type(ContainerFrameUtil_EnumerateContainerFrames) ~= "function" then
					table.insert(missing, "ContainerFrameUtil_EnumerateContainerFrames")
				end
				if type(C_Container) ~= "table" or type(C_Container.GetContainerItemLink) ~= "function" then
					table.insert(missing, "C_Container.GetContainerItemLink")
				end
				if type(hooksecurefunc) ~= "function" then
					table.insert(missing, "hooksecurefunc")
				end
				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end

				local count = 0
				for _ in pairs(hooked) do
					count = count + 1
				end
				return "PASS", count, type(ContainerFrameCombinedBags)
			end,
		},
		{
			name = "bag markers",
			run = function()
				local gearAdvisor = ns.addon:GetModule("GearAdvisor", true)
				if not gearAdvisor or not gearAdvisor:IsEnabled() then
					return "SKIP", "module disabled"
				end
				local shown, protectedSkips = Bags:CountMarkers()
				return "INFO", shown, protectedSkips
			end,
		},
	}
end)
