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
		assert.is_nil(L.BindingPrefix(0))
		assert.is_nil(L.BindingPrefix(9))
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
end)
