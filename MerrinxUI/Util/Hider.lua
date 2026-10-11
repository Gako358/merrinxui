local addonName, ns = ...

local Hider = {}
ns.Hider = Hider

local parent = CreateFrame("Frame", "MerrinxUIHiddenParent", UIParent)
parent:Hide()
Hider.parent = parent

local hidden = setmetatable({}, { __mode = "k" })

-- Writing frame.isShownExternal taints the key for Edit Mode's own writes to
-- it. Inserting dead hash-part keys forces a rehash that drops per-slot
-- taint tracking, so loop until the key reports secure again. Bounded far
-- above any frame table's hash size in case a client's taint semantics differ.
local PURGE_BOUND = 65536
local PURGE_START_SLOT = 1000

local function purgeIsShownExternal(frame)
	frame.isShownExternal = nil
	local slot = PURGE_START_SLOT
	for _ = 1, PURGE_BOUND do
		if issecurevariable(frame, "isShownExternal") then
			return
		end
		if frame[slot] == nil then
			frame[slot] = nil
		end
		slot = slot + 1
	end
	ns.addon:Print("HideBlizzard: could not purge isShownExternal taint on " .. (frame:GetName() or "unnamed frame"))
end

local function applyHide(frame, unregisterEvents)
	if frame.system then
		purgeIsShownExternal(frame)
	end
	if unregisterEvents then
		frame:UnregisterAllEvents()
	end
	if frame.HideBase then
		frame:HideBase()
	else
		frame:Hide()
	end
	frame:SetParent(parent)
	hidden[frame] = true
end

function Hider:Hide(frame, unregisterEvents)
	if frame == nil then
		return false
	end
	if hidden[frame] then
		return true
	end

	if frame:IsProtected() and InCombatLockdown() then
		return ns.Combat:Run(frame, function()
			applyHide(frame, unregisterEvents)
		end)
	end

	applyHide(frame, unregisterEvents)
	return true
end
