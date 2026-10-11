local addonName, ns = ...

local GML = {}
ns.GameMenuLogic = GML

function GML.Plan(buttons, targetText)
	if targetText == nil then
		return nil
	end

	local targetIndex, targetY
	for i, b in ipairs(buttons) do
		if b.y ~= nil and b.text == targetText and (targetY == nil or b.y > targetY) then
			targetIndex, targetY = i, b.y
		end
	end

	if targetIndex == nil then
		return nil
	end

	local shift = {}
	for i, b in ipairs(buttons) do
		if b.y ~= nil and b.y <= targetY then
			table.insert(shift, i)
		end
	end

	return targetIndex, shift
end
