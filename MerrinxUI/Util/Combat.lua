local addonName, ns = ...

local Combat = {}
ns.Combat = Combat

local queue = ns.CombatQueue.New()

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
	queue:Drain()
end)

function Combat:Run(key, fn)
	if not InCombatLockdown() then
		fn()
		return true
	end
	queue:Push(key, fn)
	return false
end
