local addonName, ns = ...

local MouseCircleLogic = {}
ns.MouseCircleLogic = MouseCircleLogic

MouseCircleLogic.STYLES = {
	thin = "ringThin",
	normal = "ringNormal",
	thick = "ringThick",
}

MouseCircleLogic.STYLE_NAMES = {
	thin = "Thin",
	normal = "Normal",
	thick = "Thick",
}

function MouseCircleLogic.Style(s)
	if MouseCircleLogic.STYLES[s] ~= nil then
		return s
	end
	return "normal"
end

function MouseCircleLogic.Color(profile, classFile, classColors)
	local entry = classColors and classFile and classColors[classFile]
	if profile.classColor and entry then
		return entry.r, entry.g, entry.b
	end
	local c = profile.color
	return c.r, c.g, c.b
end

function MouseCircleLogic.Anchor(rawX, rawY, scale)
	return math.floor(rawX / scale + 0.5), math.floor(rawY / scale + 0.5)
end

function MouseCircleLogic.Alpha(opacity)
	local a = opacity / 100
	if a < 0 then
		return 0
	elseif a > 1 then
		return 1
	end
	return a
end
