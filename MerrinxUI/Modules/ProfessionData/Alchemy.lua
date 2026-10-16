local addonName, ns = ...

ns.ProfessionData = ns.ProfessionData or {}

ns.ProfessionData[171] = {
	name = "Alchemy",
	skillLine = 171,
	kind = "craft",
	source = "https://www.wow-professions.com/forever/alchemy-leveling-guide",
	routeEnd = 290,
	train = {
		[3] = {
			how = "trainer",
			text = "Doctor Herbert Halsey (Undercity) or Ainethil (Darnassus)",
		},
		[4] = {
			how = "trainer",
			text = "Rogvar (Stonard) or Kylanna Windwhisper (Feathermoon Stronghold)",
		},
	},
	steps = {
		{
			from = 1,
			to = 10,
			name = "Minor Arcane Elixir",
			count = 9,
			mats = {
				{ name = "Peacebloom", count = 9 },
				{ name = "Empty Vial", count = 9 },
			},
			alt = "9 Elixir of Minor Force (9 Silverleaf, 9 Empty Vial)",
			note = "Vials from Alchemy Supply or Trade Supply vendors",
		},
		{
			from = 10,
			to = 55,
			name = "Elixir of Minor Defense",
			count = 45,
			mats = {
				{ name = "Silverleaf", count = 45 },
				{ name = "Peacebloom", count = 45 },
				{ name = "Empty Vial", count = 45 },
			},
		},
		{
			from = 55,
			to = 65,
			name = "Minor Mana Potion",
			count = 10,
			mats = {
				{ name = "Mageroyal", count = 10 },
				{ name = "Peacebloom", count = 10 },
				{ name = "Empty Vial", count = 10 },
			},
		},
		{
			from = 65,
			to = 90,
			name = "Elixir of Minor Fortitude",
			count = 27,
			mats = {
				{ name = "Earthroot", count = 54 },
				{ name = "Peacebloom", count = 27 },
				{ name = "Empty Vial", count = 27 },
			},
			note = "Yellow at 80",
		},
		{
			from = 90,
			to = 120,
			name = "Elixir of Wisdom",
			count = 30,
			mats = {
				{ name = "Mageroyal", count = 30 },
				{ name = "Briarthorn", count = 60 },
				{ name = "Empty Vial", count = 30 },
			},
			note = "Tailors: keep them for Gloves of Meditation",
		},
		{
			from = 120,
			to = 130,
			name = "Lesser Mana Potion",
			count = 10,
			mats = {
				{ name = "Mageroyal", count = 10 },
				{ name = "Stranglekelp", count = 10 },
				{ name = "Empty Vial", count = 10 },
			},
		},
		{
			from = 130,
			to = 150,
			name = "Fire Oil",
			count = 20,
			mats = {
				{ name = "Firefin Snapper", count = 40 },
				{ name = "Empty Vial", count = 20 },
			},
			alt = "20 Lesser Mana Potion (20 Mageroyal, 20 Stranglekelp, 20 Empty Vial)",
			note = "2 oils per craft; keep 30 for Elixir of Fire Power",
		},
		{
			from = 150,
			to = 165,
			name = "Elixir of Fire Power",
			count = 15,
			mats = {
				{ name = "Fire Oil", count = 30 },
				{ name = "Kingsblood", count = 15 },
				{ name = "Leaded Vial", count = 15 },
			},
			alt = "22 Lesser Mana Potion",
		},
		{
			from = 165,
			to = 195,
			name = "Mana Potion",
			count = 36,
			mats = {
				{ name = "Stranglekelp", count = 36 },
				{ name = "Kingsblood", count = 36 },
				{ name = "Leaded Vial", count = 36 },
			},
		},
		{
			from = 195,
			to = 225,
			name = "Nature Protection Potion",
			count = 36,
			mats = {
				{ name = "Liferoot", count = 36 },
				{ name = "Stranglekelp", count = 36 },
				{ name = "Leaded Vial", count = 36 },
			},
			note = "Recipe: Bronk or Logannas (Feralas), Glyx Brewright (STV), " .. "Alchemist Pestlezugg (Tanaris)",
		},
		{
			from = 225,
			to = 230,
			name = "Nature Protection Potion",
			count = 12,
			mats = {
				{ name = "Liferoot", count = 12 },
				{ name = "Stranglekelp", count = 12 },
				{ name = "Leaded Vial", count = 12 },
			},
			note = "Untested on beta",
		},
		{
			from = 230,
			to = 265,
			name = "Draught of Detect Undead",
			count = 45,
			mats = {
				{ name = "Arthas' Tears", count = 45 },
				{ name = "Crystal Vial", count = 45 },
			},
			note = "Yellow from 245",
		},
		{
			from = 265,
			to = 275,
			name = "Superior Mana Potion",
			count = 10,
			mats = {
				{ name = "Sungrass", count = 20 },
				{ name = "Blindweed", count = 20 },
				{ name = "Crystal Vial", count = 10 },
			},
			note = "Recipe: Algernon (Undercity) or Ulthir (Darnassus)",
		},
		{
			from = 275,
			to = 290,
			name = "Superior Mana Potion",
			count = 20,
			mats = {
				{ name = "Sungrass", count = 40 },
				{ name = "Blindweed", count = 40 },
				{ name = "Crystal Vial", count = 20 },
			},
			alt = "17 Elixir of Greater Defense or 27 Elixir of Shadow Power",
			note = "Pick the cheapest",
		},
	},
}
