local addonName, ns = ...

ns.GearAdvisorData = {
	SPECS = {
		WARRIOR = {
			{
				key = "arms",
				name = "Arms",
				weights = {
					str = 1.0,
					agi = 0.6,
					sta = 0.4,
					ap = 0.5,
					crit = 12,
					hit = 10,
					armor = 0.01,
					meleeDps = 3.0,
				},
			},
			{
				key = "fury",
				name = "Fury",
				weights = {
					str = 1.0,
					agi = 0.6,
					sta = 0.4,
					ap = 0.5,
					crit = 13,
					hit = 12,
					armor = 0.01,
					meleeDps = 2.5,
				},
			},
			{
				key = "protection",
				name = "Protection",
				weights = {
					str = 0.6,
					agi = 0.5,
					sta = 1.0,
					ap = 0.3,
					hit = 6,
					def = 1.0,
					armor = 0.05,
					block = 0.3,
					dodge = 10,
					parry = 9,
					meleeDps = 1.5,
				},
			},
		},
		PALADIN = {
			{
				key = "holy",
				name = "Holy",
				weights = {
					str = 0.2,
					sta = 0.4,
					int = 1.0,
					spi = 0.4,
					healing = 0.6,
					spellDamage = 0.3,
					mp5 = 1.5,
					crit = 6,
				},
			},
			{
				key = "protection",
				name = "Protection",
				weights = {
					str = 0.6,
					sta = 1.0,
					int = 0.3,
					def = 1.0,
					armor = 0.05,
					block = 0.4,
					spellDamage = 0.4,
					meleeDps = 1.5,
				},
			},
			{
				key = "retribution",
				name = "Retribution",
				weights = {
					str = 1.0,
					agi = 0.4,
					sta = 0.4,
					int = 0.3,
					ap = 0.5,
					crit = 10,
					hit = 9,
					spellDamage = 0.3,
					meleeDps = 3.0,
				},
			},
		},
		HUNTER = {
			{
				key = "beastMastery",
				name = "Beast Mastery",
				weights = {
					str = 0.1,
					agi = 1.0,
					sta = 0.4,
					int = 0.3,
					ap = 0.5,
					rap = 0.45,
					crit = 10,
					hit = 10,
					meleeDps = 0.3,
					rangedDps = 3.0,
				},
			},
			{
				key = "marksmanship",
				name = "Marksmanship",
				weights = {
					str = 0.1,
					agi = 1.0,
					sta = 0.35,
					int = 0.3,
					ap = 0.5,
					rap = 0.45,
					crit = 12,
					hit = 11,
					meleeDps = 0.3,
					rangedDps = 3.5,
				},
			},
			{
				key = "survival",
				name = "Survival",
				weights = {
					str = 0.1,
					agi = 1.1,
					sta = 0.4,
					int = 0.3,
					ap = 0.45,
					rap = 0.4,
					crit = 12,
					hit = 10,
					meleeDps = 0.5,
					rangedDps = 3.0,
				},
			},
		},
		ROGUE = {
			{
				key = "assassination",
				name = "Assassination",
				weights = {
					str = 0.55,
					agi = 1.0,
					sta = 0.35,
					ap = 0.5,
					crit = 12,
					hit = 12,
					meleeDps = 2.5,
					rangedDps = 0.1,
				},
			},
			{
				key = "combat",
				name = "Combat",
				weights = {
					str = 0.55,
					agi = 1.0,
					sta = 0.35,
					ap = 0.5,
					crit = 11,
					hit = 14,
					meleeDps = 3.0,
					rangedDps = 0.1,
				},
			},
			{
				key = "subtlety",
				name = "Subtlety",
				weights = {
					str = 0.55,
					agi = 1.0,
					sta = 0.4,
					ap = 0.5,
					crit = 11,
					hit = 11,
					meleeDps = 2.5,
					rangedDps = 0.1,
				},
			},
		},
		PRIEST = {
			{
				key = "discipline",
				name = "Discipline",
				weights = {
					sta = 0.5,
					int = 1.0,
					spi = 0.7,
					spellDamage = 0.8,
					healing = 0.4,
					mp5 = 1.5,
					crit = 6,
					rangedDps = 1.0,
				},
			},
			{
				key = "holy",
				name = "Holy",
				weights = {
					sta = 0.4,
					int = 0.9,
					spi = 0.8,
					spellDamage = 0.4,
					healing = 0.8,
					mp5 = 1.8,
					crit = 6,
					rangedDps = 0.8,
				},
			},
			{
				key = "shadow",
				name = "Shadow",
				weights = {
					sta = 0.6,
					int = 0.8,
					spi = 1.0,
					spellDamage = 1.0,
					mp5 = 1.0,
					crit = 4,
					hit = 8,
					rangedDps = 1.0,
				},
			},
		},
		SHAMAN = {
			{
				key = "elemental",
				name = "Elemental",
				weights = {
					sta = 0.5,
					int = 1.0,
					spi = 0.3,
					spellDamage = 1.0,
					mp5 = 1.2,
					crit = 10,
					hit = 8,
					meleeDps = 0.5,
				},
			},
			{
				key = "enhancement",
				name = "Enhancement",
				weights = {
					str = 1.0,
					agi = 0.6,
					sta = 0.4,
					int = 0.3,
					ap = 0.5,
					crit = 10,
					hit = 9,
					meleeDps = 3.5,
				},
			},
			{
				key = "restoration",
				name = "Restoration",
				weights = {
					sta = 0.4,
					int = 1.0,
					spi = 0.4,
					spellDamage = 0.3,
					healing = 0.8,
					mp5 = 2.0,
					crit = 6,
					meleeDps = 0.3,
				},
			},
		},
		MAGE = {
			{
				key = "arcane",
				name = "Arcane",
				weights = {
					sta = 0.5,
					int = 1.0,
					spi = 0.6,
					spellDamage = 0.9,
					mp5 = 1.2,
					crit = 8,
					hit = 8,
					rangedDps = 1.0,
				},
			},
			{
				key = "fire",
				name = "Fire",
				weights = {
					sta = 0.5,
					int = 0.8,
					spi = 0.4,
					spellDamage = 1.0,
					mp5 = 1.0,
					crit = 10,
					hit = 10,
					rangedDps = 1.0,
				},
			},
			{
				key = "frost",
				name = "Frost",
				weights = {
					sta = 0.6,
					int = 0.8,
					spi = 0.5,
					spellDamage = 1.0,
					mp5 = 1.0,
					crit = 8,
					hit = 10,
					rangedDps = 1.0,
				},
			},
		},
		WARLOCK = {
			{
				key = "affliction",
				name = "Affliction",
				weights = {
					sta = 0.8,
					int = 0.6,
					spi = 0.7,
					spellDamage = 1.0,
					mp5 = 0.8,
					crit = 4,
					hit = 10,
					rangedDps = 1.0,
				},
			},
			{
				key = "demonology",
				name = "Demonology",
				weights = {
					sta = 1.0,
					int = 0.6,
					spi = 0.6,
					spellDamage = 0.9,
					mp5 = 0.8,
					crit = 4,
					hit = 9,
					rangedDps = 1.0,
				},
			},
			{
				key = "destruction",
				name = "Destruction",
				weights = {
					sta = 0.7,
					int = 0.7,
					spi = 0.4,
					spellDamage = 1.0,
					mp5 = 0.8,
					crit = 8,
					hit = 10,
					rangedDps = 1.0,
				},
			},
		},
		DRUID = {
			{
				key = "balance",
				name = "Balance",
				weights = {
					sta = 0.5,
					int = 1.0,
					spi = 0.5,
					spellDamage = 1.0,
					mp5 = 1.2,
					crit = 8,
					hit = 8,
					meleeDps = 0.2,
				},
			},
			{
				key = "feral",
				name = "Feral",
				weights = {
					str = 1.0,
					agi = 1.0,
					sta = 0.6,
					ap = 0.5,
					crit = 10,
					hit = 10,
					armor = 0.03,
					dodge = 6,
				},
			},
			{
				key = "restoration",
				name = "Restoration",
				weights = {
					sta = 0.4,
					int = 1.0,
					spi = 0.6,
					spellDamage = 0.3,
					healing = 0.8,
					mp5 = 1.8,
					crit = 6,
				},
			},
		},
	},
}

ns.Debug:RegisterChecks("GearAdvisor", function()
	return {
		{
			name = "specs",
			run = function()
				local SPECS = ns.GearAdvisorData.SPECS
				local ok, err = ns.GearAdvisorLogic.ValidateSpecs(SPECS)
				if not ok then
					return "FAIL", err
				end
				local count = 0
				for _, specs in pairs(SPECS) do
					count = count + #specs
				end
				if count == 27 then
					return "PASS", count
				end
				return "FAIL", "count " .. count
			end,
		},
	}
end)
