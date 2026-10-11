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

ns.Debug:RegisterChecks("Combat", function()
	return {
		{
			name = "queue",
			run = function(ctx)
				local count = #queue.order
				if count > 0 and not ctx.inCombat then
					return "FAIL", count
				end
				return "INFO", count
			end,
		},
	}
end)
