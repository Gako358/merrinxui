local addonName, ns = ...

local MoverLogic = {}
ns.MoverLogic = MoverLogic

-- cx/cy must already be in the target frame's own coordinate units
-- (frameEffScale), i.e. the caller's frame, not some other frame sharing the
-- screen. Returns the SetPoint("CENTER", parent, "CENTER", x, y) offset for
-- that frame; the parent center is scaled into the frame's units via
-- parentEffScale/frameEffScale.
function MoverLogic.CenterOffset(cx, cy, frameEffScale, parentW, parentH, parentEffScale)
	local ratio = parentEffScale / frameEffScale
	local x = cx - (parentW / 2) * ratio
	local y = cy - (parentH / 2) * ratio
	return x, y
end
