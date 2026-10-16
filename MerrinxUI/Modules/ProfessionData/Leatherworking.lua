local addonName, ns = ...

ns.ProfessionData = ns.ProfessionData or {}

ns.ProfessionData[165] = {
	name = "Leatherworking",
	skillLine = 165,
	kind = "craft",
	source = "https://www.wow-professions.com/forever/leatherworking-leveling-guide",
	routeEnd = 225,
	train = {
		[4] = {
			how = "trainer",
			text = "Hahrana Ironhide (Feralas) or Drakk Stonehand (Hinterlands)",
		},
	},
	steps = {
		{
			from = 1,
			to = 30,
			name = "Light Leather",
			count = 33,
			mats = { { name = "Ruined Leather Scraps", count = 100 } },
			alt = "Light Armor Kit (1 Light Leather each)",
			note = "Yellow at 20",
		},
		{
			from = 30,
			to = 55,
			name = "Cured Light Hide",
			count = 27,
			mats = {
				{ name = "Light Hide", count = 27 },
				{ name = "Salt", count = 27 },
			},
			note = "Keep 24 for Light Leather Pants at 100",
		},
		{
			from = 55,
			to = 75,
			name = "Embossed Leather Gloves",
			count = 21,
			mats = {
				{ name = "Light Leather", count = 63 },
				{ name = "Coarse Thread", count = 42 },
			},
		},
		{
			from = 75,
			to = 80,
			name = "Medium Leather",
			count = 8,
			mats = { { name = "Light Leather", count = 32 } },
		},
		{
			from = 80,
			to = 90,
			name = "Cured Medium Hide",
			count = 10,
			mats = {
				{ name = "Medium Hide", count = 10 },
				{ name = "Salt", count = 10 },
			},
			note = "Keep them for Dark Leather Belts at 115",
		},
		{
			from = 90,
			to = 100,
			name = "Fine Leather Belt",
			count = 19,
			mats = {
				{ name = "Light Leather", count = 114 },
				{ name = "Coarse Thread", count = 38 },
			},
			note = "Keep 10 for Dark Leather Belts at 115",
		},
		{
			from = 100,
			to = 115,
			name = "Light Leather Pants",
			count = 24,
			mats = {
				{ name = "Light Leather", count = 240 },
				{ name = "Cured Light Hide", count = 24 },
				{ name = "Fine Thread", count = 24 },
			},
		},
		{
			from = 115,
			to = 125,
			name = "Dark Leather Belt",
			count = 10,
			mats = {
				{ name = "Fine Leather Belt", count = 10 },
				{ name = "Cured Medium Hide", count = 10 },
				{ name = "Fine Thread", count = 20 },
				{ name = "Gray Dye", count = 10 },
			},
		},
		{
			from = 125,
			to = 130,
			name = "Heavy Leather",
			count = 7,
			mats = { { name = "Medium Leather", count = 35 } },
		},
		{
			from = 130,
			to = 140,
			name = "Cured Heavy Hide",
			count = 20,
			mats = {
				{ name = "Heavy Hide", count = 20 },
				{ name = "Salt", count = 60 },
			},
			alt = "30 Hillman's Leather Gloves for 130-155 (420 Medium Leather, 120 Fine Thread)",
		},
		{
			from = 140,
			to = 155,
			name = "Hillman's Leather Gloves",
			count = 20,
			mats = {
				{ name = "Medium Leather", count = 280 },
				{ name = "Fine Thread", count = 80 },
			},
		},
		{
			from = 155,
			to = 165,
			name = "Barbaric Shoulders",
			count = 10,
			mats = {
				{ name = "Heavy Leather", count = 80 },
				{ name = "Cured Heavy Hide", count = 10 },
				{ name = "Fine Thread", count = 20 },
			},
			note = "Pattern: Jandia (Thousand Needles), Keena or Hammon Karwn (Arathi), Lardan (Ashenvale)",
		},
		{
			from = 165,
			to = 175,
			name = "Guardian Gloves",
			count = 10,
			mats = {
				{ name = "Heavy Leather", count = 40 },
				{ name = "Cured Heavy Hide", count = 10 },
				{ name = "Silken Thread", count = 10 },
			},
			alt = "5 Barbaric Harness (70 Heavy Leather, 10 Fine Thread, 5 Iron Buckle)",
		},
		{
			from = 175,
			to = 195,
			name = "Guardian Gloves",
			count = 26,
			mats = {
				{ name = "Heavy Leather", count = 104 },
				{ name = "Cured Heavy Hide", count = 26 },
				{ name = "Silken Thread", count = 26 },
			},
		},
		{
			from = 195,
			to = 210,
			name = "Nightscape Headband",
			count = 21,
			mats = {
				{ name = "Thick Leather", count = 105 },
				{ name = "Silken Thread", count = 42 },
			},
		},
		{
			from = 210,
			to = 225,
			name = "Nightscape Pants",
			count = 15,
			mats = {
				{ name = "Thick Leather", count = 210 },
				{ name = "Silken Thread", count = 60 },
			},
			note = "Taught only by Hahrana Ironhide (Feralas) and Drakk Stonehand (Hinterlands)",
		},
	},
}
