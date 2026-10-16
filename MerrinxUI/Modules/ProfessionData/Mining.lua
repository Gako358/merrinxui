local addonName, ns = ...

ns.ProfessionData = ns.ProfessionData or {}

ns.ProfessionData[186] = {
	name = "Mining",
	skillLine = 186,
	kind = "gather",
	routeEnd = 300,
	steps = {
		{
			from = 1,
			to = 65,
			name = "Copper Vein",
			zones = { "Dun Morogh", "Elwynn Forest", "Darkshore", "Durotar", "Mulgore", "Tirisfal Glades" },
		},
		{
			from = 65,
			to = 125,
			name = "Tin Vein",
			zones = { "Redridge Mountains", "Ashenvale", "The Barrens", "Hillsbrad Foothills" },
			note = "Silver Vein from 75",
		},
		{
			from = 125,
			to = 175,
			name = "Iron Deposit",
			zones = { "Arathi Highlands", "Desolace", "Thousand Needles" },
			note = "Gold Vein from 155",
		},
		{
			from = 175,
			to = 245,
			name = "Mithril Deposit",
			zones = { "The Hinterlands", "Tanaris" },
			note = "Truesilver Deposit from 230",
		},
		{
			from = 245,
			to = 300,
			name = "Small Thorium Vein",
			zones = { "Un'Goro Crater", "Felwood", "Burning Steppes", "Winterspring", "Eastern Plaguelands" },
			note = "Rich Thorium Vein from 275",
		},
	},
}
