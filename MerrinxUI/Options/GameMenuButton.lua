local addonName, ns = ...

local btn
local lastLayout

-- Blizzard_GameMenu may be load-on-demand; btn stays nil if so.
if GameMenuFrame then
	btn = CreateFrame("Button", nil, GameMenuFrame, "MainMenuFrameButtonTemplate")
	btn:SetText("MerrinxUI")
	btn:Hide()
	btn:SetScript("OnClick", function()
		if not InCombatLockdown() then
			HideUIPanel(GameMenuFrame)
		end
		ns.addon:OpenOptions()
	end)

	hooksecurefunc(GameMenuFrame, "Layout", function(menu)
		if not (InputUtil and InputUtil.IsGamepadUIEnabled) then
			btn:Hide()
			lastLayout = "no gamepad api"
			return
		end
		if InputUtil.IsGamepadUIEnabled() then
			btn:Hide()
			lastLayout = "gamepad"
			return
		end
		if type(ADDONS) ~= "string" then
			btn:Hide()
			lastLayout = "no addons"
			return
		end

		local list = {}
		local protected = menu:IsProtected()
		for b in menu.buttonPool:EnumerateActive() do
			protected = protected or b:IsProtected()
			local p, rel, rp, x, y = b:GetPoint(1)
			table.insert(list, { button = b, p = p, rel = rel, rp = rp, x = x, y = y, text = b:GetText() })
		end

		if protected then
			btn:Hide()
			lastLayout = "protected"
			return
		end

		local idx, shift = ns.GameMenuLogic.Plan(list, ADDONS)
		if idx == nil then
			btn:Hide()
			lastLayout = "no anchor"
			return
		end

		local target = list[idx]
		local h = target.button:GetHeight()
		btn:SetSize(target.button:GetSize())
		btn:ClearAllPoints()
		btn:SetPoint(target.p, target.rel, target.rp, target.x, target.y)

		for _, i in ipairs(shift) do
			local entry = list[i]
			entry.button:ClearAllPoints()
			entry.button:SetPoint(entry.p, entry.rel, entry.rp, entry.x, entry.y - h)
		end

		menu:SetHeight(menu:GetHeight() + h)
		btn:Show()
		lastLayout = "placed"
	end)
end

ns.Debug:RegisterChecks("GameMenu", function()
	return {
		{
			name = "installed",
			run = function()
				if btn then
					return "PASS"
				end
				return "FAIL", "GameMenuFrame missing at load"
			end,
		},
		{
			name = "load on demand",
			run = function()
				if type(C_AddOns) ~= "table" or type(C_AddOns.IsAddOnLoadOnDemand) ~= "function" then
					return "INFO", "no api"
				end
				local lod = C_AddOns.IsAddOnLoadOnDemand("Blizzard_GameMenu")
				if lod == false then
					return "PASS"
				end
				return "FAIL", lod
			end,
		},
		{
			name = "gamepad",
			run = function()
				if InputUtil and InputUtil.IsGamepadUIEnabled then
					return "INFO", InputUtil.IsGamepadUIEnabled()
				end
				return "INFO", "no api"
			end,
		},
		{
			name = "layout",
			run = function()
				return "INFO", lastLayout
			end,
		},
		{
			name = "button",
			run = function()
				if not btn then
					return "SKIP", "not installed"
				end
				if not (GameMenuFrame and GameMenuFrame:IsShown()) then
					return "SKIP", "menu closed"
				end
				return (btn:IsShown() == (lastLayout == "placed")) and "PASS" or "FAIL"
			end,
		},
	}
end)
