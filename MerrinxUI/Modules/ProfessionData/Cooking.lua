local addonName, ns = ...

ns.ProfessionData = ns.ProfessionData or {}

ns.ProfessionData[185] = {
	name = "Cooking",
	skillLine = 185,
	kind = "secondary",
	source = "https://www.wow-professions.com/forever/cooking-leveling-guide",
	routeEnd = 300,
	train = {
		[3] = { how = "book", text = "Expert Cookbook (Wulan, Desolace or Shandrina, Ashenvale)" },
		[4] = { how = "quest", skill = 225, text = "Clamlette Surprise (Dirge Quikcleave, Gadgetzan)" },
	},
	steps = {
		{
			from = 1,
			to = 50,
			name = "Charred Wolf Meat",
			count = 55,
			alt = "Or Roasted Boar Meat, Herb Baked Egg, Brilliant Smallfish, Slitherskin Mackerel",
			note = "Campfire: Simple Wood and Flint and Tinder from a vendor",
		},
		{
			from = 50,
			to = 100,
			name = "Longjaw Mud Snapper",
			count = 55,
			mats = { { name = "Raw Longjaw Mud Snapper", count = 55 } },
			alt = "Or Rainbow Fin Albacore, Smoked Bear Meat, Boiled Clams, Coyote Steak, Strider Stew",
		},
		{
			from = 100,
			to = 130,
			name = "Bristle Whisker Catfish",
			alt = "Or Crab Cake, Dry Pork Ribs, Cooked Crab Claw",
			note = "Buy extra catfish; more are needed at 130-150",
		},
		{
			from = 130,
			to = 150,
			name = "Bristle Whisker Catfish",
			alt = "Or Curiously Tasty Omelet, Goblin Deviled Clams, Hot Lion Chops",
		},
		{
			from = 150,
			to = 175,
			name = "Curiously Tasty Omelet",
			count = 25,
			mats = { { name = "Raptor Egg", count = 25 }, { name = "Hot Spices", count = 25 } },
			alt = "Or Hot Lion Chops",
			note = "Recipe: Kendor Kabonka (Stormwind), Keena (Arathi), Zargh (Barrens); yellow from 170",
		},
		{
			from = 175,
			to = 225,
			name = "Mithril Headed Trout",
			count = 50,
			alt = "Or Roast Raptor, Soothing Turtle Bisque (quest, Hillsbrad)",
			note = "Recipe: Wik'Tar (Ashenvale) or Hammon Karwn (Arathi); yellow from 215",
		},
		{
			from = 225,
			to = 275,
			name = "Spotted Yellowtail",
			count = 65,
			mats = { { name = "Raw Spotted Yellowtail", count = 65 } },
			alt = "Or Filet of Redgill, Undermine Clam Chowder, Monster Omelet, Tender Wolf Steak",
			note = "Recipes from Gikkix (Tanaris)",
		},
		{
			from = 275,
			to = 300,
			name = "Poached Sunscale Salmon",
			count = 35,
			alt = "Or Nightfin Soup, or 15 Smoked Desert Dumplings (quest, Silithus)",
			note = "Recipes from Gikkix (Tanaris); yellow from 290",
		},
	},
}
