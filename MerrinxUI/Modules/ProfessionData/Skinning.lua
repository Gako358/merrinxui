local addonName, ns = ...

ns.ProfessionData = ns.ProfessionData or {}

ns.ProfessionData[393] = {
	name = "Skinning",
	skillLine = 393,
	kind = "gather",
	routeEnd = 300,
	steps = {
		{
			from = 1,
			to = 75,
			name = "Skin beasts up to level 17",
			zones = { "Dun Morogh", "Elwynn Forest", "Durotar", "Mulgore", "Loch Modan", "The Barrens" },
		},
		{
			from = 75,
			to = 115,
			name = "Skin beasts level 17-23",
			zones = { "Wetlands", "The Barrens" },
		},
		{
			from = 115,
			to = 155,
			name = "Skin beasts level 23-31",
			zones = { "Wetlands", "Stonetalon Mountains" },
			note = "Learn Expert at 125",
		},
		{
			from = 155,
			to = 205,
			name = "Skin beasts level 31-41",
			zones = { "Arathi Highlands", "Stranglethorn Vale" },
			note = "Raptors in Arathi Highlands",
		},
		{
			from = 205,
			to = 250,
			name = "Skin beasts level 41-50",
			zones = { "Tanaris", "Feralas" },
		},
		{
			from = 250,
			to = 300,
			name = "Skin beasts level 50-60",
			zones = { "Un'Goro Crater", "Winterspring", "Burning Steppes", "Eastern Plaguelands" },
		},
	},
}
