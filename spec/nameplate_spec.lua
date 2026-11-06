describe("NameplateLogic", function()
	local ns

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/NameplateLogic.lua"))("MerrinxUI", ns)
	end)

	describe("PlateColor", function()
		local classColors = {
			MAGE = { r = 0.25, g = 0.78, b = 0.92 },
			WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
		}
		local HOSTILE = { 0.8, 0.137, 0.137 }
		local NEUTRAL = { 0.81, 0.72, 0.19 }
		local FRIENDLY = { 0.314, 0.8, 0.408 }
		local TAPPED = { 0.5, 0.5, 0.5 }

		local function color(state, colors)
			return { ns.NameplateLogic.PlateColor(state, colors) }
		end

		it("is grey when tap-denied, regardless of other inputs", function()
			assert.are.same(
				TAPPED,
				color({
					tapDenied = true,
					isPlayer = true,
					classFile = "MAGE",
					reaction = 5,
					threatRole = "dps",
					threat = 3,
					threatShared = true,
				}, classColors)
			)
			assert.are.same(TAPPED, color({ tapDenied = true }, nil))
		end)

		it("uses the class colour for a player with a known class", function()
			assert.are.same(
				{ 0.25, 0.78, 0.92 },
				color(
					{ isPlayer = true, classFile = "MAGE", reaction = 2, inCombat = false, darkenOOC = true },
					classColors
				)
			)
		end)

		it("falls back to reaction for a player with an unknown, nil class or no class table", function()
			assert.are.same(HOSTILE, color({ isPlayer = true, classFile = "DRUID", reaction = 2 }, classColors))
			assert.are.same(FRIENDLY, color({ isPlayer = true, reaction = 5 }, classColors))
			assert.are.same(NEUTRAL, color({ isPlayer = true, classFile = "MAGE", reaction = 4 }, nil))
		end)

		it("colours neutral units hostile once they are in combat", function()
			assert.are.same(NEUTRAL, color({ reaction = 4, inCombat = false }))
			assert.are.same(NEUTRAL, color({ reaction = 4 }))
			assert.are.same(HOSTILE, color({ reaction = 4, inCombat = true, darkenOOC = true }))
		end)

		it("colours friendly reactions green and everything else hostile", function()
			assert.are.same(FRIENDLY, color({ reaction = 5 }))
			assert.are.same(FRIENDLY, color({ reaction = 8 }))
			assert.are.same(HOSTILE, color({ reaction = 1 }))
			assert.are.same(HOSTILE, color({ reaction = 3 }))
			assert.are.same(HOSTILE, color({}))
		end)

		it("darkens hostile units that are not known to be in combat when darkenOOC is on", function()
			local dark = color({ reaction = 2, inCombat = false, darkenOOC = true })
			assert.are.near(0.48, dark[1], 1e-9)
			assert.are.near(0.0822, dark[2], 1e-9)
			assert.are.near(0.0822, dark[3], 1e-9)
			assert.are.same(dark, color({ reaction = 2, darkenOOC = true }))
			assert.are.same(HOSTILE, color({ reaction = 2, inCombat = true, darkenOOC = true }))
			assert.are.same(HOSTILE, color({ reaction = 2, inCombat = false, darkenOOC = false }))
		end)

		it("lets threat colours win over class and reaction colours", function()
			assert.are.same(
				{ 1, 0.5, 0 },
				color({
					isPlayer = true,
					classFile = "MAGE",
					reaction = 2,
					threatRole = "dps",
					threat = 3,
					threatShared = true,
				}, classColors)
			)
			assert.are.same({ 1, 0.22, 0.17 }, color({ reaction = 4, threatRole = "tank", threat = 0 }))
		end)

		it("keeps the normal colour when threat gives no override", function()
			assert.are.same(HOSTILE, color({ reaction = 2, inCombat = true, threatRole = "tank", threat = 3 }))
			assert.are.same(HOSTILE, color({ reaction = 2, inCombat = true, threatRole = "dps", threat = 3 }))
		end)
	end)

	describe("ThreatRole", function()
		it("returns an explicit setting unchanged", function()
			assert.are.equal("tank", ns.NameplateLogic.ThreatRole("tank", "DAMAGER"))
			assert.are.equal("dps", ns.NameplateLogic.ThreatRole("dps", "TANK"))
		end)

		it("follows the assigned group role on auto", function()
			assert.are.equal("tank", ns.NameplateLogic.ThreatRole("auto", "TANK"))
			assert.are.equal("dps", ns.NameplateLogic.ThreatRole("auto", "HEALER"))
			assert.are.equal("dps", ns.NameplateLogic.ThreatRole("auto", "NONE"))
			assert.are.equal("dps", ns.NameplateLogic.ThreatRole("auto", nil))
		end)
	end)

	describe("ThreatColorKey", function()
		local key = function(...)
			return ns.NameplateLogic.ThreatColorKey(...)
		end

		it("returns nil without a numeric threat status", function()
			assert.is_nil(key("tank", nil, true, false))
			assert.is_nil(key("dps", "3", true, false))
		end)

		it("warns a tank that is losing or lacks aggro", function()
			assert.is_nil(key("tank", 3, false, false))
			assert.are.equal("tankLosingAggro", key("tank", 2, false, false))
			assert.are.equal("tankNoAggro", key("tank", 1, false, false))
			assert.are.equal("tankNoAggro", key("tank", 0, true, false))
			assert.are.equal("offTankAggro", key("tank", 0, true, true))
			assert.are.equal("tankLosingAggro", key("tank", 2, true, true))
		end)

		it("warns a damage dealer with or near aggro only when threat is shared", function()
			assert.are.equal("dpsHasAggro", key("dps", 3, true, false))
			assert.are.equal("dpsNearAggro", key("dps", 2, true, false))
			assert.is_nil(key("dps", 1, true, false))
			assert.is_nil(key("dps", 0, true, false))
			assert.is_nil(key("dps", 3, false, false))
		end)

		it("names a colour defined in COLORS for every key it returns", function()
			for _, k in ipairs({ "tankLosingAggro", "tankNoAggro", "offTankAggro", "dpsHasAggro", "dpsNearAggro" }) do
				assert.are.equal(3, #ns.NameplateLogic.COLORS[k])
			end
		end)
	end)

	describe("ClassificationAtlas", function()
		it("maps elite, boss and rare classifications to Blizzard atlases", function()
			assert.are.equal("nameplates-icon-elite-gold", ns.NameplateLogic.ClassificationAtlas("elite"))
			assert.are.equal("nameplates-icon-elite-gold", ns.NameplateLogic.ClassificationAtlas("worldboss"))
			assert.are.equal("nameplates-icon-elite-silver", ns.NameplateLogic.ClassificationAtlas("rareelite"))
			assert.are.equal(
				"UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
				ns.NameplateLogic.ClassificationAtlas("rare")
			)
		end)

		it("returns nil for ordinary or unknown classifications", function()
			assert.is_nil(ns.NameplateLogic.ClassificationAtlas("normal"))
			assert.is_nil(ns.NameplateLogic.ClassificationAtlas("trivial"))
			assert.is_nil(ns.NameplateLogic.ClassificationAtlas("minus"))
			assert.is_nil(ns.NameplateLogic.ClassificationAtlas(nil))
		end)
	end)

	describe("MarkerLayout", function()
		it("places the marker in each supported position", function()
			assert.are.same({ "BOTTOMRIGHT", "TOPRIGHT", 0, 2 }, { ns.NameplateLogic.MarkerLayout("TOPRIGHT", 2) })
			assert.are.same({ "BOTTOMLEFT", "TOPLEFT", 0, 2 }, { ns.NameplateLogic.MarkerLayout("TOPLEFT", 2) })
			assert.are.same({ "RIGHT", "LEFT", -2, 0 }, { ns.NameplateLogic.MarkerLayout("LEFT", 2) })
			assert.are.same({ "LEFT", "RIGHT", 2, 0 }, { ns.NameplateLogic.MarkerLayout("RIGHT", 2) })
		end)

		it("returns nil for NONE or unknown positions", function()
			assert.is_nil(ns.NameplateLogic.MarkerLayout("NONE", 2))
			assert.is_nil(ns.NameplateLogic.MarkerLayout(nil, 2))
		end)
	end)

	describe("ExecuteOffset", function()
		it("scales the percentage to the bar width", function()
			assert.are.equal(39, ns.NameplateLogic.ExecuteOffset(130, 30))
			assert.are.equal(0, ns.NameplateLogic.ExecuteOffset(130, 0))
			assert.are.equal(130, ns.NameplateLogic.ExecuteOffset(130, 100))
		end)

		it("clamps the percentage to 0-100", function()
			assert.are.equal(0, ns.NameplateLogic.ExecuteOffset(130, -10))
			assert.are.equal(130, ns.NameplateLogic.ExecuteOffset(130, 150))
		end)
	end)

	describe("GLOW_PIECES", function()
		local function words(point)
			return point:match("TOP") or point:match("BOTTOM"), point:match("LEFT") or point:match("RIGHT")
		end

		it("samples the glow's centre on every side that faces the bar", function()
			local edge = { LEFT = 1, RIGHT = 2, TOP = 3, BOTTOM = 4 }
			assert.are.equal(8, #ns.NameplateLogic.GLOW_PIECES)
			for _, piece in ipairs(ns.NameplateLogic.GLOW_PIECES) do
				for _, pair in ipairs(piece.points) do
					local pv, ph = words(pair[1])
					local bv, bh = words(pair[2])
					if pv ~= bv then
						assert.are.equal(0.5, piece.coords[edge[pv]])
					end
					if ph ~= bh then
						assert.are.equal(0.5, piece.coords[edge[ph]])
					end
				end
			end
		end)
	end)

	describe("BorderMode", function()
		it("reads none, thin and shadow from the toggle and the style", function()
			assert.are.equal("none", ns.NameplateLogic.BorderMode(false, "shadow"))
			assert.are.equal("thin", ns.NameplateLogic.BorderMode(true, nil))
			assert.are.equal("shadow", ns.NameplateLogic.BorderMode(true, "shadow"))
		end)

		it("round-trips through BorderSetting", function()
			for mode in pairs(ns.NameplateLogic.BORDER_MODES) do
				assert.are.equal(mode, ns.NameplateLogic.BorderMode(ns.NameplateLogic.BorderSetting(mode)))
			end
		end)
	end)

	describe("CastIconSize", function()
		it("spans the health bar, the gap and the cast bar", function()
			assert.are.equal(20, ns.NameplateLogic.CastIconSize(10, nil, 1, 2, 8))
		end)

		it("includes the power bar when it is shown", function()
			assert.are.equal(25, ns.NameplateLogic.CastIconSize(10, 4, 1, 2, 8))
		end)
	end)

	describe("FormatValue", function()
		it("formats percent", function()
			assert.are.equal("73%", ns.NameplateLogic.FormatValue("percent", "12.3K", 73.4))
			assert.are.equal("0%", ns.NameplateLogic.FormatValue("percent", "x", 0))
			assert.are.equal("100%", ns.NameplateLogic.FormatValue("percent", "x", 100))
		end)

		it("formats number", function()
			assert.are.equal("850", ns.NameplateLogic.FormatValue("number", "850", 12))
		end)

		it("formats both", function()
			assert.are.equal("12.3K (73%)", ns.NameplateLogic.FormatValue("both", "12.3K", 73.4))
		end)

		it("returns nil for none or unknown modes", function()
			assert.is_nil(ns.NameplateLogic.FormatValue("none", "12.3K", 73.4))
			assert.is_nil(ns.NameplateLogic.FormatValue("bogus", "12.3K", 73.4))
		end)
	end)

	describe("PowerColor", function()
		it("returns the fixed colour for each known power token", function()
			assert.are.same({ 0, 0.55, 1 }, { ns.NameplateLogic.PowerColor("MANA") })
			assert.are.same({ 0.9, 0.1, 0.1 }, { ns.NameplateLogic.PowerColor("RAGE") })
			assert.are.same({ 1, 0.85, 0.1 }, { ns.NameplateLogic.PowerColor("ENERGY") })
			assert.are.same({ 1, 0.5, 0.25 }, { ns.NameplateLogic.PowerColor("FOCUS") })
		end)

		it("falls back to grey for nil or unknown tokens", function()
			assert.are.same({ 0.5, 0.5, 0.5 }, { ns.NameplateLogic.PowerColor(nil) })
			assert.are.same({ 0.5, 0.5, 0.5 }, { ns.NameplateLogic.PowerColor("RUNIC_POWER") })
		end)
	end)

	describe("DebuffLayout", function()
		it("lays out TOP anchored icons centred above the plate", function()
			assert.are.same({ "BOTTOM", "TOP", -20, 2 }, { ns.NameplateLogic.DebuffLayout("TOP", 1, 3, 18, 2) })
			assert.are.same({ "BOTTOM", "TOP", 0, 2 }, { ns.NameplateLogic.DebuffLayout("TOP", 2, 3, 18, 2) })
			assert.are.same({ "BOTTOM", "TOP", 20, 2 }, { ns.NameplateLogic.DebuffLayout("TOP", 3, 3, 18, 2) })
			assert.are.same({ "BOTTOM", "TOP", 0, 2 }, { ns.NameplateLogic.DebuffLayout("TOP", 1, 1, 18, 2) })
		end)

		it("lays out BOTTOM anchored icons below the plate", function()
			assert.are.same({ "TOP", "BOTTOM", 0, -2 }, { ns.NameplateLogic.DebuffLayout("BOTTOM", 2, 3, 18, 2) })
		end)

		it("lays out RIGHT anchored icons growing rightward", function()
			assert.are.same({ "LEFT", "RIGHT", 22, 0 }, { ns.NameplateLogic.DebuffLayout("RIGHT", 2, 3, 18, 2) })
		end)

		it("lays out LEFT anchored icons growing leftward", function()
			assert.are.same({ "RIGHT", "LEFT", -42, 0 }, { ns.NameplateLogic.DebuffLayout("LEFT", 3, 3, 18, 2) })
		end)

		it("falls back to TOP layout for unknown anchors", function()
			assert.are.same(
				{ ns.NameplateLogic.DebuffLayout("TOP", 1, 3, 18, 2) },
				{ ns.NameplateLogic.DebuffLayout("bogus", 1, 3, 18, 2) }
			)
		end)
	end)

	describe("DebuffFilter/CC_FILTER", function()
		it("builds filter strings per ccSeparate and matches the CC_FILTER literal", function()
			assert.are.equal("HARMFUL|PLAYER", ns.NameplateLogic.DebuffFilter(true, false))
			assert.are.equal("HARMFUL", ns.NameplateLogic.DebuffFilter(false, false))
			assert.are.equal("HARMFUL|PLAYER|!CROWD_CONTROL", ns.NameplateLogic.DebuffFilter(true, true))
			assert.are.equal("HARMFUL|!CROWD_CONTROL", ns.NameplateLogic.DebuffFilter(false, true))
			assert.are.equal("HARMFUL|CROWD_CONTROL", ns.NameplateLogic.CC_FILTER)
		end)
	end)

	describe("LevelText/LevelColor", function()
		it("formats the level with a classification suffix", function()
			assert.are.equal("10", ns.NameplateLogic.LevelText(10, "normal"))
			assert.are.equal("10+", ns.NameplateLogic.LevelText(10, "elite"))
			assert.are.equal("10r", ns.NameplateLogic.LevelText(10, "rare"))
			assert.are.equal("10r+", ns.NameplateLogic.LevelText(10, "rareelite"))
			assert.are.equal("??", ns.NameplateLogic.LevelText(-1, "elite"))
			assert.are.equal("??", ns.NameplateLogic.LevelText(63, "worldboss"))
			assert.are.equal("12", ns.NameplateLogic.LevelText(12, "trivial"))
			assert.are.equal("12", ns.NameplateLogic.LevelText(12, "minus"))
			assert.is_nil(ns.NameplateLogic.LevelText(nil, "normal"))
			assert.is_nil(ns.NameplateLogic.LevelText(0, "normal"))
		end)

		it("colours by classification, falling back to a provided colour table", function()
			assert.are.same({ 1, 0, 0 }, { ns.NameplateLogic.LevelColor(-1, "normal", nil) })
			assert.are.same(
				{ 1, 0, 0 },
				{ ns.NameplateLogic.LevelColor(60, "worldboss", { r = 0.5, g = 0.5, b = 0.5 }) }
			)
			assert.are.same(
				{ 0.25, 0.75, 0.25 },
				{ ns.NameplateLogic.LevelColor(10, "normal", { r = 0.25, g = 0.75, b = 0.25 }) }
			)
			assert.are.same({ 1, 1, 1 }, { ns.NameplateLogic.LevelColor(10, "normal", nil) })
			assert.are.same({ 1, 1, 1 }, { ns.NameplateLogic.LevelColor(10, "normal", "x") })
		end)
	end)
end)
