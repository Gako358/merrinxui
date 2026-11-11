describe("Enhance", function()
	local ns, addon, Enhance
	local requested, modules

	before_each(function()
		requested = {}
		modules = {
			Performance = true,
			BuffReminders = true,
			CastBars = true,
			CooldownVoice = true,
			Professions = true,
			RangeText = true,
			SpellHistory = true,
			XPBar = true,
		}

		ns = {}
		addon = {
			NewModule = function(self, name)
				local module = {}
				self[name] = module
				return module
			end,
			GetModule = function(self, name)
				requested[#requested + 1] = name
				if modules[name] then
					return {
						GetTabOptions = function()
							return { type = "group", name = name, args = {} }
						end,
					}
				end
				return nil
			end,
		}
		ns.addon = addon

		assert(loadfile("MerrinxUI/Modules/Enhance.lua"))("MerrinxUI", ns)
		Enhance = addon.Enhance
	end)

	it("returns the Enhance group shape", function()
		local options = Enhance:GetOptions()
		assert.are.equal("Enhance", options.name)
		assert.are.equal("tab", options.childGroups)
		assert.are.equal("group", options.type)
	end)

	it("requests exactly the TABS names in order", function()
		Enhance:GetOptions()
		assert.are.same({
			"Performance",
			"BuffReminders",
			"CastBars",
			"CooldownVoice",
			"Professions",
			"RangeText",
			"SpellHistory",
			"XPBar",
			"LayerHop",
		}, requested)
	end)

	it("orders the 8 present modules by TABS order with LayerHop absent", function()
		local options = Enhance:GetOptions()
		local args = options.args
		local names = {}
		for name in pairs(args) do
			names[#names + 1] = name
		end
		assert.are.equal(8, #names)
		assert.is_nil(args.LayerHop)
		assert.are.equal(1, args.Performance.order)
		assert.are.equal(2, args.BuffReminders.order)
		assert.are.equal(3, args.CastBars.order)
		assert.are.equal(4, args.CooldownVoice.order)
		assert.are.equal(5, args.Professions.order)
		assert.are.equal(6, args.RangeText.order)
		assert.are.equal(7, args.SpellHistory.order)
		assert.are.equal(8, args.XPBar.order)
	end)

	it("orders LayerHop 9th when present", function()
		modules.LayerHop = true
		local options = Enhance:GetOptions()
		assert.are.equal(9, options.args.LayerHop.order)
	end)
end)
