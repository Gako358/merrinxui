local addonName, ns = ...

local L = {}
ns.ZoneInfoLogic = L

L.FISH_MIN = { [25] = 1, [75] = 1, [150] = 55, [225] = 130, [300] = 205, [425] = 330 }

L.ZONES = {
	[1411] = { name = "Durotar", low = 1, high = 10, fish = 25 },
	[1412] = { name = "Mulgore", low = 1, high = 10, fish = 25 },
	[1413] = { name = "The Barrens", low = 10, high = 25, fish = 75 },
	[1416] = { name = "Alterac Mountains", low = 30, high = 40, fish = 225 },
	[1417] = { name = "Arathi Highlands", low = 30, high = 40, fish = 225 },
	[1418] = { name = "Badlands", low = 35, high = 45 },
	[1419] = { name = "Blasted Lands", low = 45, high = 55 },
	[1420] = { name = "Tirisfal Glades", low = 1, high = 10, fish = 25 },
	[1421] = { name = "Silverpine Forest", low = 10, high = 20, fish = 75 },
	[1422] = { name = "Western Plaguelands", low = 51, high = 58, fish = 300 },
	[1423] = { name = "Eastern Plaguelands", low = 53, high = 60, fish = 425 },
	[1424] = { name = "Hillsbrad Foothills", low = 20, high = 30, fish = 150 },
	[1425] = { name = "The Hinterlands", low = 40, high = 50, fish = 300 },
	[1426] = { name = "Dun Morogh", low = 1, high = 10, fish = 25 },
	[1427] = { name = "Searing Gorge", low = 43, high = 50 },
	[1428] = { name = "Burning Steppes", low = 50, high = 58 },
	[1429] = { name = "Elwynn Forest", low = 1, high = 10, fish = 25 },
	[1430] = { name = "Deadwind Pass", low = 55, high = 60, fish = 425 },
	[1431] = { name = "Duskwood", low = 18, high = 30, fish = 150 },
	[1432] = { name = "Loch Modan", low = 10, high = 20, fish = 75 },
	[1433] = { name = "Redridge Mountains", low = 15, high = 25, fish = 150 },
	[1434] = { name = "Stranglethorn Vale", low = 30, high = 45, fish = 225 },
	[1435] = { name = "Swamp of Sorrows", low = 35, high = 45, fish = 225 },
	[1436] = { name = "Westfall", low = 10, high = 20, fish = 75 },
	[1437] = { name = "Wetlands", low = 20, high = 30, fish = 150 },
	[1438] = { name = "Teldrassil", low = 1, high = 10, fish = 25 },
	[1439] = { name = "Darkshore", low = 10, high = 20, fish = 75 },
	[1440] = { name = "Ashenvale", low = 18, high = 30, fish = 150 },
	[1441] = { name = "Thousand Needles", low = 25, high = 35, fish = 225 },
	[1442] = { name = "Stonetalon Mountains", low = 15, high = 27, fish = 150 },
	[1443] = { name = "Desolace", low = 30, high = 40, fish = 225 },
	[1444] = { name = "Feralas", low = 40, high = 50, fish = 300 },
	[1445] = { name = "Dustwallow Marsh", low = 35, high = 45, fish = 225 },
	[1446] = { name = "Tanaris", low = 40, high = 50, fish = 300 },
	[1447] = { name = "Azshara", low = 45, high = 55, fish = 300 },
	[1448] = { name = "Felwood", low = 48, high = 55, fish = 300 },
	[1449] = { name = "Un'Goro Crater", low = 48, high = 55, fish = 300 },
	[1450] = { name = "Moonglade", low = 55, high = 60, fish = 300 },
	[1451] = { name = "Silithus", low = 55, high = 60 },
	[1452] = { name = "Winterspring", low = 55, high = 60, fish = 425 },
	[1453] = { name = "Stormwind City", fish = 75 },
	[1454] = { name = "Orgrimmar", fish = 75 },
	[1455] = { name = "Ironforge", fish = 75 },
	[1456] = { name = "Thunder Bluff", fish = 75 },
	[1457] = { name = "Darnassus", fish = 75 },
	[1458] = { name = "Undercity", fish = 75 },
	[2482] = { name = "Mount Hyjal", low = 55, high = 60 },
	[2521] = { name = "Zephras Isle", low = 1, high = 12 },
	[2548] = { name = "Riverglades", low = 35, high = 45 },
	[2652] = { name = "Shen'dralas", low = 35, high = 45 },
}

function L.Info(id)
	if type(id) ~= "number" then
		return nil
	end
	return L.ZONES[id]
end

function L.Difficulty(level, low, high)
	if level == nil or low == nil or high == nil then
		return nil
	end
	if level < low then
		return "hard"
	end
	if level > high then
		return "easy"
	end
	return "even"
end

function L.LevelText(entry)
	if entry == nil or entry.low == nil then
		return nil
	end
	return string.format("Level %d-%d", entry.low, entry.high)
end

function L.FishingText(entry)
	if entry == nil or entry.fish == nil then
		return nil
	end
	local min = L.FISH_MIN[entry.fish]
	if min == nil then
		return nil
	end
	return string.format("Fishing: %d (no escapes: %d)", min, entry.fish)
end

function L.Resolve(shown, hovered)
	if L.ZONES[hovered] ~= nil then
		return hovered
	end
	if L.ZONES[shown] ~= nil then
		return shown
	end
	return nil
end
