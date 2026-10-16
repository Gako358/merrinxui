local addonName, ns = ...

ns.ProfessionData = ns.ProfessionData or {}

ns.ProfessionData[182] = {
	name = "Herbalism",
	skillLine = 182,
	kind = "gather",
	routeEnd = 300,
	steps = {
		{
			from = 1,
			to = 70,
			name = "Peacebloom, Silverleaf, Earthroot",
			zones = { "Elwynn Forest", "Teldrassil", "Dun Morogh", "Durotar", "Mulgore", "Tirisfal Glades" },
			note = "Earthroot from 15",
		},
		{
			from = 70,
			to = 115,
			name = "Mageroyal, Briarthorn, Stranglekelp",
			zones = { "Loch Modan", "Darkshore", "The Barrens", "Silverpine Forest" },
		},
		{
			from = 115,
			to = 170,
			name = "Bruiseweed, Wild Steelbloom, Kingsblood",
			zones = { "Hillsbrad Foothills", "Wetlands", "Stonetalon Mountains" },
			note = "Liferoot from 150",
		},
		{
			from = 170,
			to = 205,
			name = "Fadeleaf, Goldthorn, Khadgar's Whisker",
			zones = { "Stranglethorn Vale", "Arathi Highlands" },
		},
		{
			from = 205,
			to = 230,
			name = "Firebloom, Purple Lotus",
			zones = { "Tanaris", "Searing Gorge" },
		},
		{
			from = 230,
			to = 270,
			name = "Sungrass, Gromsblood, Golden Sansam",
			zones = { "The Hinterlands" },
			note = "Gromsblood from 250, Golden Sansam from 260",
		},
		{
			from = 270,
			to = 300,
			name = "Dreamfoil, Mountain Silversage, Plaguebloom",
			zones = { "Felwood" },
			note = "Silversage from 280, Plaguebloom from 285, Icecap from 290",
		},
	},
}
