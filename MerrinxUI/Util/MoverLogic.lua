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

local function closest(best, value, line, thresh)
	local dist = math.abs(line - value)
	if dist <= thresh and (not best or dist < best.dist) then
		return { dist = dist, delta = line - value, line = line }
	end
	return best
end

-- rect and others: { left, right, top, bottom } in UIParent units (y up).
-- Each axis snaps on its own to the nearest line within thresh: another
-- rect's edges or center, the screen center, or the mirror of another rect's
-- center across the screen center (a player/target pair). Returns the deltas
-- to add to rect and the snapped line per axis (nil when that axis is free).
function MoverLogic.Snap(rect, others, screenW, screenH, thresh)
	local cx = (rect.left + rect.right) / 2
	local cy = (rect.top + rect.bottom) / 2
	local bestX = closest(nil, cx, screenW / 2, thresh)
	local bestY = closest(nil, cy, screenH / 2, thresh)
	for _, o in ipairs(others) do
		local ocx = (o.left + o.right) / 2
		local ocy = (o.top + o.bottom) / 2
		for _, value in ipairs({ rect.left, cx, rect.right }) do
			for _, line in ipairs({ o.left, ocx, o.right }) do
				bestX = closest(bestX, value, line, thresh)
			end
		end
		for _, value in ipairs({ rect.top, cy, rect.bottom }) do
			for _, line in ipairs({ o.top, ocy, o.bottom }) do
				bestY = closest(bestY, value, line, thresh)
			end
		end
		bestX = closest(bestX, cx, screenW - ocx, thresh)
	end
	return bestX and bestX.delta or 0, bestY and bestY.delta or 0, bestX and bestX.line, bestY and bestY.line
end

-- Line positions from the screen center outward, so the center is always a line.
function MoverLogic.GridLines(size, spacing)
	local center = size / 2
	local lines = { center }
	local offset = spacing
	while offset <= center do
		table.insert(lines, center - offset)
		table.insert(lines, center + offset)
		offset = offset + spacing
	end
	return lines
end

-- Typed offsets are clamped to limit so a frame can't be sent off screen.
function MoverLogic.ParseOffset(text, limit)
	local value = tonumber(type(text) == "string" and text:match("^%s*(.-)%s*$") or nil)
	if not value or value ~= value or math.abs(value) == math.huge then
		return nil
	end
	return math.max(-limit, math.min(limit, value))
end

function MoverLogic.FormatOffset(x, y)
	return string.format("%d, %d", math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5))
end
