local addonName, ns = ...

ns.ProfessionData = ns.ProfessionData or {}

ns.ProfessionData[356] = {
	name = "Fishing",
	skillLine = 356,
	kind = "secondary",
	source = "https://www.wow-professions.com/forever/fishing-leveling-guide",
	routeEnd = 300,
	train = {
		[3] = { how = "book", text = "Expert Fishing - The Bass and You (Old Man Heming, Booty Bay)" },
		[4] = { how = "quest", skill = 225, text = "Nat Pagle, Angler Extreme (Nat Pagle, Dustwallow Marsh)" },
	},
	steps = {
		{
			from = 1,
			to = 75,
			name = "Fish in a starting zone",
			note = "Fishing Pole and Shiny Bauble from the Fishing Supply vendor",
			zones = {
				"Dun Morogh",
				"Durotar",
				"Elwynn Forest",
				"Mulgore",
				"Teldrassil",
				"Tirisfal Glades",
				"Zephras Isle",
			},
		},
		{
			from = 75,
			to = 150,
			name = "Fish in a capital city or nearby zone",
			note = "Nightcrawlers from 50 if fish escape",
			zones = {
				"Darnassus",
				"Stormwind",
				"Orgrimmar",
				"Undercity",
				"Thunder Bluff",
				"The Barrens",
				"Darkshore",
				"Ironforge",
				"Loch Modan",
				"Silverpine Forest",
				"Westfall",
			},
		},
		{
			from = 150,
			to = 225,
			name = "Fish in Dustwallow Marsh",
			note = "Bright Baubles from Old Man Heming, Booty Bay",
			zones = {
				"Dustwallow Marsh",
				"Alterac Mountains",
				"Arathi Highlands",
				"Desolace",
				"Stranglethorn Vale",
				"Swamp of Sorrows",
				"Thousand Needles",
			},
		},
		{
			from = 225,
			to = 300,
			name = "Fish in a high-level zone",
			note = "Use Bright Baubles or fish escape",
			zones = {
				"Felwood",
				"Feralas",
				"The Hinterlands",
				"Tanaris",
				"Un'Goro Crater",
				"Western Plaguelands",
			},
		},
	},
}
