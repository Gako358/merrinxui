local addonName, ns = ...

local NameplateLogic = {}
ns.NameplateLogic = NameplateLogic

function NameplateLogic.Color(reaction, isPlayer, classFile, tapDenied, classColors)
	if tapDenied then
		return 0.5, 0.5, 0.5
	end

	if isPlayer and classColors and classColors[classFile] then
		local color = classColors[classFile]
		return color.r, color.g, color.b
	end

	if reaction == nil or reaction <= 3 then
		return 1, 0, 0
	elseif reaction == 4 then
		return 1, 1, 0
	end
	return 0, 1, 0
end
