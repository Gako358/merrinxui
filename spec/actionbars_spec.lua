describe("ActionBarLogic", function()
	local ns, L

	before_each(function()
		ns = {}
		assert(loadfile("MerrinxUI/Modules/ActionBarLogic.lua"))("MerrinxUI", ns)
		L = ns.ActionBarLogic
	end)

	it("PAGES holds the per-bar base page", function()
		assert.are.same({ 1, 6, 5, 3, 4, 13, 14, 15 }, L.PAGES)
	end)

	it("Slot maps page and index to an action slot", function()
		assert.are.equal(1, L.Slot(1, 1))
		assert.are.equal(61, L.Slot(6, 1))
		assert.are.equal(73, L.Slot(7, 1))
		assert.are.equal(180, L.Slot(15, 12))
	end)

	it("PagingDriver fills the override, vehicle and shapeshift indices, or omits them when unknown", function()
		local tail = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
			.. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1"

		local expected = "[overridebar] 18; [vehicleui] 16; [possessbar] 16; [shapeshift] 17; " .. tail
		assert.are.equal(expected, L.PagingDriver(18, 16, 17))

		assert.are.equal(tail, L.PagingDriver(nil, nil, nil))
		assert.are.equal(tail, L.PagingDriver(18, nil, 17))
	end)

	it("Layout fills a single row", function()
		local positions, width, height = L.Layout(12, 12, 36, 2)
		assert.are.equal(454, width)
		assert.are.equal(36, height)
		assert.are.same({ x = 418, y = 0 }, positions[12])
	end)

	it("Layout wraps into multiple rows", function()
		local positions, width, height = L.Layout(12, 5, 36, 2)
		assert.are.equal(188, width)
		assert.are.equal(112, height)
		assert.are.same({ x = 0, y = -38 }, positions[6])
		assert.are.same({ x = 0, y = -76 }, positions[11])
		assert.are.same({ x = 38, y = -76 }, positions[12])
	end)

	it("Layout fills a single column", function()
		local positions, width, height = L.Layout(12, 1, 36, 2)
		assert.are.equal(36, width)
		assert.are.equal(454, height)
		assert.are.same({ x = 0, y = -418 }, positions[12])
	end)

	it("Layout clamps perRow to [1, n]", function()
		assert.are.same({ L.Layout(12, 1, 36, 2) }, { L.Layout(12, 0, 36, 2) })
		assert.are.same({ L.Layout(12, 12, 36, 2) }, { L.Layout(12, 20, 36, 2) })
	end)

	it("BarGeometry scales buttons from the native size and sizes the header in screen units", function()
		local scale, positions, width, height = L.BarGeometry(12, 12, 36, 2, 45)
		assert.near(0.8, scale, 1e-9)
		assert.are.equal(454, width)
		assert.are.equal(36, height)
		assert.near(47.5, positions[2].x, 1e-9)
		assert.near(38, positions[2].x * scale, 1e-9)

		local _, _, width2, height2 = L.BarGeometry(12, 5, 36, 2, 45)
		assert.are.equal(188, width2)
		assert.are.equal(112, height2)
	end)

	it("DefaultPosition stacks bars 40 px apart below centre", function()
		assert.are.same({ point = "CENTER", x = 0, y = -300 }, L.DefaultPosition(1))
		assert.are.same({ point = "CENTER", x = 0, y = -220 }, L.DefaultPosition(3))
		assert.are.same({ point = "CENTER", x = 0, y = -20 }, L.DefaultPosition(8))
	end)

	it("ExpectedPage prefers the bar page, then the bonus offset, then 1", function()
		assert.are.equal(1, L.ExpectedPage(1, 0))
		assert.are.equal(2, L.ExpectedPage(2, 0))
		assert.are.equal(7, L.ExpectedPage(1, 1))
		assert.are.equal(10, L.ExpectedPage(1, 4))
		assert.are.equal(3, L.ExpectedPage(3, 2))
		assert.are.equal(11, L.ExpectedPage(1, 5))
	end)

	it("BindingPrefix maps bar number to a Blizzard binding prefix", function()
		assert.are.equal("ACTIONBUTTON", L.BindingPrefix(1))
		assert.are.equal("MULTIACTIONBAR1BUTTON", L.BindingPrefix(2))
		assert.are.equal("MULTIACTIONBAR4BUTTON", L.BindingPrefix(5))
		assert.are.equal("MULTIACTIONBAR5BUTTON", L.BindingPrefix(6))
		assert.are.equal("MULTIACTIONBAR7BUTTON", L.BindingPrefix(8))
		assert.are.equal("BONUSACTIONBUTTON", L.BindingPrefix(9))
		assert.is_nil(L.BindingPrefix(0))
		assert.is_nil(L.BindingPrefix(10))
	end)

	it("ButtonCount gives the pet bar 10 buttons and every other bar 12", function()
		assert.are.equal(9, L.PET_BAR)
		assert.are.equal(9, L.BAR_COUNT)
		assert.are.equal(12, L.ButtonCount(1))
		assert.are.equal(12, L.ButtonCount(8))
		assert.are.equal(10, L.ButtonCount(9))
	end)

	it("VisibilityDriver shows the pet bar only with a pet, outside override/vehicle/pet battle", function()
		assert.are.equal("[overridebar][vehicleui][petbattle] hide; [pet] show; hide", L.VisibilityDriver(9, false))
		assert.are.equal(
			"[overridebar][vehicleui][petbattle] hide; [combat] hide; [pet] show; hide",
			L.VisibilityDriver(9, true)
		)
	end)

	it("VisibilityDriver keeps bar 1's override/vehicle/pet-battle hide and adds [combat] on request", function()
		assert.are.equal("[overridebar][vehicleui][petbattle] hide; show", L.VisibilityDriver(1, false))
		assert.are.equal("[overridebar][vehicleui][petbattle] hide; [combat] hide; show", L.VisibilityDriver(1, true))
		assert.are.equal("show", L.VisibilityDriver(2, false))
		assert.are.equal("[combat] hide; show", L.VisibilityDriver(8, true))
	end)

	it("BarAlpha is opacity/100 unless mouseover hides an unhovered bar while locked", function()
		assert.are.equal(1, L.BarAlpha(100, false, false, false))
		assert.are.equal(0.5, L.BarAlpha(50, false, false, false))
		assert.are.equal(0, L.BarAlpha(0, false, true, false))
		assert.are.equal(0, L.BarAlpha(50, true, false, false))
		assert.are.equal(0.5, L.BarAlpha(50, true, true, false))
		assert.are.equal(0.5, L.BarAlpha(50, true, false, true))
	end)

	it("FormPage maps druid form spellIDs to pages, stealth only matters for cat", function()
		assert.are.equal(7, L.FormPage(768, false))
		assert.are.equal(8, L.FormPage(768, true))
		assert.are.equal(9, L.FormPage(5487))
		assert.are.equal(9, L.FormPage(5487, true))
		assert.are.equal(9, L.FormPage(9634))
		assert.are.equal(10, L.FormPage(24858))
		assert.is_nil(L.FormPage(783))
		assert.is_nil(L.FormPage(1066))
		assert.is_nil(L.FormPage(nil))
	end)

	it("FormClauses builds per-form macro clauses for druids, with a stealth clause only when it differs", function()
		assert.are.equal(
			"[form:1] 9; [form:3,stealth] 8; [form:3] 7; ",
			L.FormClauses("DRUID", { 5487, 1066, 768, 783 })
		)
		assert.are.equal(
			"[form:1] 9; [form:3,stealth] 8; [form:3] 7; [form:5] 10; ",
			L.FormClauses("DRUID", { 9634, 1066, 768, 783, 24858 })
		)
		assert.are.equal("[form:1,stealth] 8; [form:1] 7; [form:2] 9; ", L.FormClauses("DRUID", { 768, 5487 }))
	end)

	it("FormClauses returns nil for non-druids, nil input, or no mapped forms", function()
		assert.is_nil(L.FormClauses("WARRIOR", { 2457, 71 }))
		assert.is_nil(L.FormClauses("ROGUE", { 1784 }))
		assert.is_nil(L.FormClauses(nil, { 768 }))
		assert.is_nil(L.FormClauses("DRUID", nil))
		assert.is_nil(L.FormClauses("DRUID", {}))
		assert.is_nil(L.FormClauses("DRUID", { 1066, 783 }))
	end)

	it("PagingDriver splices in form clauses before [bonusbar:5], and nil clauses keep today's output", function()
		local clauses = L.FormClauses("DRUID", { 5487, 1066, 768, 783 })
		local expected = "[overridebar] 33; [vehicleui] 31; [possessbar] 31; [shapeshift] 32; "
			.. "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
			.. "[form:1] 9; [form:3,stealth] 8; [form:3] 7; "
			.. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1"
		assert.are.equal(expected, L.PagingDriver(33, 31, 32, clauses))

		local tail = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
			.. "[form:1] 9; [form:3,stealth] 8; [form:3] 7; "
			.. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1"
		assert.are.equal(tail, L.PagingDriver(nil, nil, nil, clauses))

		assert.are.equal(L.PagingDriver(18, 16, 17), L.PagingDriver(18, 16, 17, nil))
	end)

	it("ExpectedPage prefers the bar page, then the form page, then the bonus offset, then 1", function()
		assert.are.equal(7, L.ExpectedPage(1, 0, 7))
		assert.are.equal(8, L.ExpectedPage(1, 0, 8))
		assert.are.equal(9, L.ExpectedPage(1, 3, 9))
		assert.are.equal(1, L.ExpectedPage(1, 1, 1))
		assert.are.equal(2, L.ExpectedPage(2, 0, 7))
		assert.are.equal(7, L.ExpectedPage(1, 1, nil))
		assert.are.equal(11, L.ExpectedPage(1, 5, nil))
	end)

	it("BindingButton returns Keybind for bars 1-8 and LeftButton for the pet bar", function()
		assert.are.equal("Keybind", L.BindingButton(1))
		assert.are.equal("Keybind", L.BindingButton(8))
		assert.are.equal("LeftButton", L.BindingButton(9))
	end)

	local function run(params, body, held, ...)
		local fn = assert(loadstring("local " .. params .. " = ...\n" .. body))
		setfenv(fn, {
			IsModifiedClick = function(name)
				assert.are.equal("PICKUPACTION", name)
				return held
			end,
		})
		return fn(...)
	end

	local function newSelf()
		return {
			writes = {},
			SetAttribute = function(s, k, v)
				table.insert(s.writes, { k, v })
			end,
		}
	end

	it("CLICK_GUARD_PRE remaps the Keybind virtual button without writing the attribute", function()
		for _, held in ipairs({ true, false }) do
			local self = newSelf()
			local result = run("self, button, down", L.CLICK_GUARD_PRE, held, self, "Keybind", true)
			assert.are.equal("LeftButton", result)
			assert.are.equal(0, #self.writes)
		end
	end)

	it("CLICK_GUARD_PRE guards a modified LeftButton click on both press and release", function()
		for _, down in ipairs({ true, false }) do
			local self = newSelf()
			local r1, r2 = run("self, button, down", L.CLICK_GUARD_PRE, true, self, "LeftButton", down)
			assert.are.equal(1, #self.writes)
			assert.are.equal("useOnKeyDown", self.writes[1][1])
			assert.are.equal(false, self.writes[1][2])
			assert.is_nil(r1)
			assert.are.equal("guard", r2)
		end
	end)

	it("CLICK_GUARD_PRE does nothing when the click is not modified", function()
		local self = newSelf()
		assert.are.equal(0, select("#", run("self, button, down", L.CLICK_GUARD_PRE, false, self, "LeftButton", true)))
		assert.are.equal(0, #self.writes)
	end)

	it("CLICK_GUARD_POST resets useOnKeyDown to nil", function()
		local self = newSelf()
		run("self, message, button, down", L.CLICK_GUARD_POST, nil, self, "guard", "LeftButton", true)
		assert.are.equal(1, #self.writes)
		assert.are.equal("useOnKeyDown", self.writes[1][1])
		assert.is_nil(self.writes[1][2])
	end)
end)
