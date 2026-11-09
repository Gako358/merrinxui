describe("Core", function()
	local ns, addon

	before_each(function()
		ns = {
			Theme = {},
			Media = {},
			Mover = {},
			Debug = {},
			OptionsWindow = {},
		}
		rawset(_G, "LibStub", function()
			return {
				NewAddon = function()
					return {}
				end,
			}
		end)
		assert(loadfile("MerrinxUI/Core.lua"))("MerrinxUI", ns)
		addon = ns.addon
	end)

	after_each(function()
		rawset(_G, "LibStub", nil)
	end)

	describe("GetPluginAPI", function()
		it("returns version 1 with the live host objects", function()
			local api = addon:GetPluginAPI(1)
			assert.are.equal(1, api.version)
			assert.are.equal(ns.Theme, api.Theme)
			assert.are.equal(ns.Media, api.Media)
			assert.are.equal(ns.Mover, api.Mover)
			assert.are.equal(ns.Debug, api.Debug)
			assert.are.equal(ns.OptionsWindow, api.OptionsWindow)
		end)

		it("returns nil for any other version", function()
			assert.is_nil(addon:GetPluginAPI(2))
		end)
	end)

	describe("RegisterSlash and SlashCommand", function()
		it("dispatches a registered verb with the trimmed, lowercased remainder", function()
			local received
			addon:RegisterSlash("zz", function(arg)
				received = arg
			end)
			addon:SlashCommand("ZZ  Foo Bar ")
			assert.are.equal("foo bar", received)
		end)

		it("errors when the verb is already registered", function()
			addon:RegisterSlash("zz", function() end)
			local ok = pcall(addon.RegisterSlash, addon, "zz", function() end)
			assert.is_false(ok)
		end)

		it("errors on a reserved verb", function()
			local ok = pcall(addon.RegisterSlash, addon, "debug", function() end)
			assert.is_false(ok)
		end)

		it("errors on an invalid verb", function()
			local ok = pcall(addon.RegisterSlash, addon, "Bad!", function() end)
			assert.is_false(ok)
		end)

		it("errors when the handler is not a function", function()
			local ok = pcall(addon.RegisterSlash, addon, "ok", 42)
			assert.is_false(ok)
		end)

		it("falls back to OpenOptions for an unregistered verb", function()
			local opened = false
			addon.OpenOptions = function()
				opened = true
			end
			addon:SlashCommand("hop")
			assert.is_true(opened)
		end)
	end)
end)
