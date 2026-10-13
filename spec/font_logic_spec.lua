describe("FontLogic", function()
	local ns, L
	local H, D

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Util/FontLogic.lua"))("MerrinxUI", ns)
		L = ns.FontLogic

		H = {
			["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
			["Arial Narrow"] = "Fonts\\ARIALN.TTF",
			Morpheus = "Fonts\\MORPHEUS_CYR.TTF",
		}
		D = "Friz Quadrata TT"
	end)

	it("defines DEFAULT as Friz Quadrata TT", function()
		assert.are.equal("Friz Quadrata TT", L.DEFAULT)
	end)

	it("maps every key of a hash to itself, and nil to an empty table", function()
		assert.are.same({
			["Friz Quadrata TT"] = "Friz Quadrata TT",
			["Arial Narrow"] = "Arial Narrow",
			Morpheus = "Morpheus",
		}, L.Values(H))
		assert.are.same({}, L.Values(nil))
	end)

	it("hides a font whose path the usability predicate rejects", function()
		assert.are.same(
			{
				["Friz Quadrata TT"] = "Friz Quadrata TT",
				["Arial Narrow"] = "Arial Narrow",
			},
			L.Values(H, function(path)
				return path ~= "Fonts\\MORPHEUS_CYR.TTF"
			end)
		)
	end)

	it("keeps the stored key even when the predicate rejects every path", function()
		assert.are.same(
			{ Morpheus = "Morpheus" },
			L.Values(H, function()
				return false
			end, "Morpheus")
		)
	end)

	it("does not add a kept key that isn't present in the hash", function()
		assert.are.same(
			{},
			L.Values(H, function()
				return false
			end, "Expressway")
		)
	end)

	it("recognizes a path by a slash or backslash", function()
		assert.is_true(L.IsPath("Fonts\\FRIZQT__.TTF"))
		assert.is_true(L.IsPath("Interface/AddOns/X/f.ttf"))
		assert.is_false(L.IsPath("Friz Quadrata TT"))
		assert.is_false(L.IsPath(""))
		assert.is_false(L.IsPath(nil))
		assert.is_false(L.IsPath(5))
	end)

	it("keeps a non-path value unchanged, even when it isn't registered", function()
		assert.are.equal("Morpheus", L.Migrate("Morpheus", H, D))
		assert.are.equal("Expressway", L.Migrate("Expressway", H, D))
	end)

	it("migrates a legacy path to its key, case- and separator-insensitive", function()
		assert.are.equal("Arial Narrow", L.Migrate("Fonts\\ARIALN.TTF", H, D))
		assert.are.equal("Arial Narrow", L.Migrate("fonts/arialn.ttf", H, D))
	end)

	it("falls back to default for an unmatched path or an invalid value", function()
		assert.are.equal(D, L.Migrate("Fonts\\NOPE.TTF", H, D))
		assert.are.equal(D, L.Migrate("", H, D))
		assert.are.equal(D, L.Migrate(nil, H, D))
		assert.are.equal(D, L.Migrate(42, H, D))
		assert.are.equal(D, L.Migrate("Fonts\\ARIALN.TTF", nil, D))
	end)

	it("resolves a path shared by several keys to the default or the smallest key", function()
		assert.are.equal("A", L.Migrate("Fonts\\X.TTF", { B = "Fonts\\X.TTF", A = "Fonts\\X.TTF" }, "Z"))
		assert.are.equal("Z", L.Migrate("Fonts\\X.TTF", { B = "Fonts\\X.TTF", Z = "Fonts\\X.TTF" }, "Z"))
	end)

	it("resolves the global token to the global key, and anything else unchanged", function()
		assert.are.equal("*", L.GLOBAL)
		assert.are.equal("Morpheus", L.Resolve("*", "Morpheus"))
		assert.are.equal("Morpheus", L.Resolve(nil, "Morpheus"))
		assert.are.equal("Skurri", L.Resolve("Skurri", "Morpheus"))
	end)

	it("adds a global entry to Values when a label is given, even for a nil hash", function()
		assert.are.same({
			["Friz Quadrata TT"] = "Friz Quadrata TT",
			["Arial Narrow"] = "Arial Narrow",
			Morpheus = "Morpheus",
			["*"] = "Use global (Friz Quadrata TT)",
		}, L.Values(H, nil, nil, "Use global (Friz Quadrata TT)"))
		assert.are.same({ ["*"] = "x" }, L.Values(nil, nil, nil, "x"))
		assert.are.same({
			["Friz Quadrata TT"] = "Friz Quadrata TT",
			["Arial Narrow"] = "Arial Narrow",
			Morpheus = "Morpheus",
		}, L.Values(H))
	end)

	it("migrates the global token through and the global default to the global token", function()
		assert.are.equal("*", L.Migrate("*", H, "Friz Quadrata TT"))
		assert.are.equal("*", L.Migrate("", H, L.GLOBAL))
	end)
end)
