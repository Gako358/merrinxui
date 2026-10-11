describe("OptionsLogic", function()
	local ns, L
	local H, H2, t, root

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Options/OptionsLogic.lua"))("MerrinxUI", ns)
		L = ns.OptionsLogic

		H = {
			Get = function(self, info)
				return self == H and info.arg
			end,
		}
		H2 = {}
		t = { type = "toggle", arg = "common" }
		root = { type = "group", handler = H, args = { g = { type = "group", name = "G", args = { t = t } } } }
	end)

	describe("Node, Member, Handler, Info", function()
		it("walks args by path; empty path is the root; a missing key is nil", function()
			assert.are.equal(t, L.Node(root, { "g", "t" }))
			assert.is_nil(L.Node(root, { "x" }))
			assert.are.equal(root, L.Node(root, {}))
		end)

		it("fills info with the path, appName, options, handler, option, type, arg and uiType", function()
			local info = L.Info(root, { "g", "t" }, "MerrinxUI")
			assert.are.equal("g", info[1])
			assert.are.equal("t", info[2])
			assert.are.equal("MerrinxUI", info[0])
			assert.are.equal(root, info.options)
			assert.are.equal(H, info.handler)
			assert.are.equal(t, info.option)
			assert.are.equal("toggle", info.type)
			assert.are.equal("common", info.arg)
			assert.are.equal("dialog", info.uiType)
		end)

		it("resolves the nearest handler, overridden deeper in the path", function()
			assert.are.equal(H, L.Handler(root, { "g", "t" }))
			root.args.g.handler = H2
			assert.are.equal(H2, L.Handler(root, { "g", "t" }))
			t.handler = H
			assert.are.equal(H, L.Handler(root, { "g", "t" }))
		end)

		it("keeps the parent handler when a deeper node sets handler = false", function()
			root.args.g.handler = H2
			t.handler = false
			assert.are.equal(H2, L.Handler(root, { "g", "t" }))
		end)

		it("inherits get down the path but doesn't inherit name", function()
			local f = function() end
			root.get = f
			assert.are.equal(f, L.Member(root, { "g", "t" }, "get"))
			t.get = false
			assert.are.equal(false, L.Member(root, { "g", "t" }, "get"))
			root.args.g.disabled = true
			assert.is_true(L.IsDisabled(root, { "g", "t" }, "MerrinxUI"))
			assert.is_nil(L.Member(root, { "g", "t" }, "name"))
		end)
	end)

	describe("Value", function()
		it("calls a method named by a string member", function()
			t.get = "Get"
			assert.are.equal("common", L.Value(root, { "g", "t" }, "get", "MerrinxUI"))
		end)

		it("errors with the missing method name when the handler lacks it", function()
			t.get = "Nope"
			local ok, err = pcall(L.Value, root, { "g", "t" }, "get", "MerrinxUI")
			assert.is_false(ok)
			assert.is_not_nil(err:find("Method Nope", 1, true))
		end)

		it("treats a string name member as a literal", function()
			t.name = "Get"
			assert.are.equal("Get", L.Value(root, { "g", "t" }, "name", "MerrinxUI"))
		end)

		it("calls a function member with info", function()
			t.get = function(info)
				return info[#info]
			end
			assert.are.equal("t", L.Value(root, { "g", "t" }, "get", "MerrinxUI"))
		end)

		it("passes extra arguments through to a function member", function()
			local seen
			t.set = function(_, v)
				seen = v
			end
			L.Value(root, { "g", "t" }, "set", "MerrinxUI", 42)
			assert.are.equal(42, seen)
		end)

		it("resolves a values string through the handler", function()
			t.values = "Get"
			assert.are.equal("common", L.Value(root, { "g", "t" }, "values", "MerrinxUI"))
		end)

		it("returns a literal boolean member unchanged", function()
			t.get = false
			assert.are.equal(false, L.Value(root, { "g", "t" }, "get", "MerrinxUI"))
		end)
	end)

	describe("Sorted", function()
		it("orders by order ascending, negatives last, ties by upper(name)", function()
			local sortRoot = {
				type = "group",
				args = {
					b = { order = 2, name = "B" },
					a = { order = 1, name = "A" },
					c = { order = 2, name = "a" },
					z = { name = "Z" },
					n = { order = -1, name = "N" },
					m = { order = -2, name = "M" },
				},
			}
			assert.are.same({ "a", "c", "b", "z", "m", "n" }, L.Sorted(sortRoot, {}, "MerrinxUI"))
		end)

		it("breaks a same order, same name tie by key", function()
			local tieRoot = {
				type = "group",
				args = {
					k2 = { order = 1, name = "X" },
					k1 = { order = 1, name = "X" },
				},
			}
			assert.are.same({ "k1", "k2" }, L.Sorted(tieRoot, {}, "MerrinxUI"))
		end)
	end)

	describe("IsHidden", function()
		it("prefers dialogHidden over hidden", function()
			local hroot = { type = "group", args = { x = { type = "toggle", hidden = false, dialogHidden = true } } }
			assert.is_true(L.IsHidden(hroot, { "x" }, "MerrinxUI"))
		end)

		it("prefers guiHidden over hidden when dialogHidden is absent", function()
			local hroot = { type = "group", args = { x = { type = "toggle", hidden = true, guiHidden = false } } }
			assert.is_false(L.IsHidden(hroot, { "x" }, "MerrinxUI"))
		end)

		it("falls back to a function hidden member, called with info", function()
			local hroot = {
				type = "group",
				args = {
					x = {
						type = "toggle",
						arg = "common",
						hidden = function(info)
							return info.option.arg == "common"
						end,
					},
				},
			}
			assert.is_true(L.IsHidden(hroot, { "x" }, "MerrinxUI"))
		end)

		it("coerces a truthy non-boolean hidden member to true", function()
			local hroot = { type = "group", args = { x = { type = "toggle", hidden = 1 } } }
			assert.is_true(L.IsHidden(hroot, { "x" }, "MerrinxUI"))
		end)
	end)

	describe("Pages", function()
		it("puts General first when the root has a visible non-group arg, then groups by Sorted", function()
			local coreRoot = {
				type = "group",
				args = {
					unlock = { type = "toggle", order = 1 },
					RangeText = { type = "group", name = "RangeText", args = {} },
					profiles = { type = "group", name = "Profiles", order = -1, args = {} },
				},
			}
			assert.are.same({
				{ label = "General", path = {}, leavesOnly = true },
				{ label = "RangeText", path = { "RangeText" } },
				{ label = "Profiles", path = { "profiles" } },
			}, L.Pages(coreRoot, "MerrinxUI"))
		end)

		it("has no General page when the root has only groups", function()
			local groupsOnlyRoot = {
				type = "group",
				args = {
					RangeText = { type = "group", name = "RangeText", args = {} },
					profiles = { type = "group", name = "Profiles", args = {} },
				},
			}
			local pages = L.Pages(groupsOnlyRoot, "MerrinxUI")
			assert.are.equal(2, #pages)
			assert.is_not.equal("General", pages[1].label)
		end)

		it("leaves out a hidden group", function()
			local hiddenGroupRoot = {
				type = "group",
				args = {
					RangeText = { type = "group", name = "RangeText", hidden = true, args = {} },
					profiles = { type = "group", name = "Profiles", args = {} },
				},
			}
			local pages = L.Pages(hiddenGroupRoot, "MerrinxUI")
			assert.are.equal(1, #pages)
			assert.are.equal("Profiles", pages[1].label)
		end)
	end)

	describe("Flatten", function()
		local P

		before_each(function()
			P = {
				type = "group",
				args = {
					a = { type = "toggle", order = 1 },
					g = { type = "group", name = "Sub", order = 2, args = { x = { type = "range" } } },
					h = { type = "toggle", order = 3, hidden = true },
					d = { type = "description", order = 4 },
					e = { type = "group", order = 5, args = { q = { type = "toggle", hidden = true } } },
					c = { type = "color", order = 6 },
				},
			}
		end)

		it("flattens leaves and visible nested sections, dropping empty sections", function()
			local pageRoot = { type = "group", args = { P = P } }
			assert.are.same({
				{ kind = "toggle", path = { "P", "a" }, depth = 0 },
				{ kind = "section", path = { "P", "g" }, depth = 0 },
				{ kind = "range", path = { "P", "g", "x" }, depth = 1 },
				{ kind = "description", path = { "P", "d" }, depth = 0 },
				{ kind = "unsupported", path = { "P", "c" }, depth = 0 },
			}, L.Flatten(pageRoot, { "P" }, "MerrinxUI", false))
		end)

		it("drops nested groups entirely when leavesOnly is true", function()
			local pageRoot = { type = "group", args = { P = P } }
			assert.are.same({
				{ kind = "toggle", path = { "P", "a" }, depth = 0 },
				{ kind = "description", path = { "P", "d" }, depth = 0 },
				{ kind = "unsupported", path = { "P", "c" }, depth = 0 },
			}, L.Flatten(pageRoot, { "P" }, "MerrinxUI", true))
		end)
	end)

	describe("SortedValues", function()
		it("sorts non-numeric keys by tostring", function()
			assert.are.same(
				{ "", "OUTLINE", "THICKOUTLINE" },
				L.SortedValues({ [""] = "None", OUTLINE = 1, THICKOUTLINE = 1 })
			)
		end)

		it("sorts numeric and numeric-string keys together by numeric value", function()
			assert.are.same({ 2, "3", 10 }, L.SortedValues({ [10] = 1, [2] = 1, ["3"] = 1 }))
		end)
	end)

	describe("SnapRange", function()
		it("snaps and clamps against the known cases", function()
			assert.are.equal(17, L.SnapRange(17.4, 8, 48, 1))
			assert.are.equal(18, L.SnapRange(17.5, 8, 48, 1))
			assert.are.equal(8, L.SnapRange(3, 8, 48, 1))
			assert.are.equal(48, L.SnapRange(60, 8, 48, 1))
			assert.near(0.25, L.SnapRange(0.26, 0, 1, 0.05), 1e-9)
			assert.are.equal(5, L.SnapRange(5))
			assert.are.equal(100, L.SnapRange(150))
			assert.are.equal(0, L.SnapRange(-3))
			assert.are.equal(7, L.SnapRange(7, 0, 10, 0))
		end)
	end)

	describe("FormatNumber", function()
		it("formats with trailing zeros and the decimal point trimmed", function()
			assert.are.equal("18", L.FormatNumber(18))
			assert.are.equal("0.25", L.FormatNumber(0.25))
			assert.are.equal("0.5", L.FormatNumber(0.5))
			assert.are.equal("-3", L.FormatNumber(-3))
		end)
	end)

	describe("CheckValidate", function()
		it("validates against the known cases", function()
			local ok = L.CheckValidate(true, "New", "u")
			assert.is_true(ok)

			ok = L.CheckValidate(1, "New")
			assert.is_true(ok)

			local msg
			ok, msg = L.CheckValidate(false, "New", "too long")
			assert.is_false(ok)
			assert.are.equal("New: too long", msg)

			ok, msg = L.CheckValidate(nil, "New")
			assert.is_false(ok)
			assert.are.equal("New: Invalid Value", msg)

			ok, msg = L.CheckValidate("bad", "New", "u")
			assert.is_false(ok)
			assert.are.equal("bad", msg)
		end)

		it("treats a non-string name as empty", function()
			local ok, msg = L.CheckValidate(nil, nil)
			assert.is_false(ok)
			assert.are.equal(": Invalid Value", msg)
		end)
	end)

	describe("ConfirmText", function()
		it("resolves the confirmation text against the known cases", function()
			local needed, text = L.ConfirmText(true, "Sure?", "Delete")
			assert.is_true(needed)
			assert.are.equal("Sure?", text)

			needed, text = L.ConfirmText(true, nil, "Reset Profile", "Reset the current profile")
			assert.is_true(needed)
			assert.are.equal("Reset Profile - Reset the current profile", text)

			needed, text = L.ConfirmText(true, nil, "X", nil)
			assert.is_true(needed)
			assert.are.equal("X", text)

			needed, text = L.ConfirmText("Really?", nil, "X")
			assert.is_true(needed)
			assert.are.equal("Really?", text)

			needed = L.ConfirmText(false, "Sure?", "X")
			assert.is_false(needed)

			needed = L.ConfirmText(nil)
			assert.is_false(needed)
		end)

		it("doesn't confirm for a truthy non-boolean, non-string confirm", function()
			local needed = L.ConfirmText(1, nil, "X")
			assert.is_false(needed)
		end)

		it("treats a nil name as empty when building the default confirm text", function()
			local needed, text = L.ConfirmText(true, nil, nil, "D")
			assert.is_true(needed)
			assert.are.equal(" - D", text)
		end)
	end)

	describe("Scroll", function()
		it("clamps the offset against the known cases", function()
			assert.are.equal(40, L.Scroll(0, -1, 40, 1000, 500))
			assert.are.equal(500, L.Scroll(480, -1, 40, 1000, 500))
			assert.are.equal(0, L.Scroll(20, 1, 40, 1000, 500))
			assert.are.equal(0, L.Scroll(0, -1, 40, 300, 500))
		end)
	end)

	describe("Stack", function()
		it("offsets each height by the running total plus gap", function()
			local offsets, total = L.Stack({ 38, 20, 38 }, 2)
			assert.are.same({ 0, 40, 62 }, offsets)
			assert.are.equal(100, total)
		end)

		it("returns no offsets and a zero total for an empty list", function()
			local offsets, total = L.Stack({}, 2)
			assert.are.same({}, offsets)
			assert.are.equal(0, total)
		end)
	end)
end)

describe("Theme", function()
	local ns, Theme

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Options/Theme.lua"))("MerrinxUI", ns)
		Theme = ns.Theme
	end)

	it("has colours as 4 numbers in [0,1] and positive integer geometry, consistent with the window size", function()
		for name, c in pairs(Theme.color) do
			assert.are.equal(4, #c, name)
			for _, component in ipairs(c) do
				assert.is_number(component)
				assert.is_true(component >= 0 and component <= 1, name)
			end
		end

		for name, v in pairs(Theme.geometry) do
			assert.is_number(v, name)
			assert.are.equal(0, v % 1, name)
			assert.is_true(v > 0, name)
		end

		local g = Theme.geometry
		assert.is_true(g.sidebar + 3 * g.pad + g.control < g.width)
		assert.is_true(g.header + g.footer + 4 * g.row < g.height)
	end)
end)
