describe("ChatLogic", function()
	local L

	before_each(function()
		local ns = {}
		assert(loadfile("MerrinxUI/Modules/ChatLogic.lua"))("MerrinxUI", ns)
		L = ns.ChatLogic
	end)

	local function link(url)
		return "|cff66bfff|Haddon:MerrinxUI:url:" .. url .. "|h[" .. url .. "]|h|r"
	end

	describe("IsURL", function()
		it("accepts scheme, www and ip forms", function()
			assert.is_true(L.IsURL("https://example.com"))
			assert.is_true(L.IsURL("ftp://host/file"))
			assert.is_true(L.IsURL("www.wowhead.com/item=1"))
			assert.is_true(L.IsURL("127.0.0.1:8080"))
			assert.is_true(L.IsURL("10.0.0.1/status"))
		end)

		it("rejects words, versions and bare schemes", function()
			assert.is_false(L.IsURL("hello"))
			assert.is_false(L.IsURL("1.15.4.1"))
			assert.is_false(L.IsURL("https://"))
			assert.is_false(L.IsURL("www.x"))
			assert.is_false(L.IsURL(""))
			assert.is_false(L.IsURL(nil))
		end)
	end)

	describe("WrapURLs", function()
		it("wraps a url and counts it", function()
			local text, count = L.WrapURLs("see https://example.com/a?b=1 now", "66bfff")
			assert.are.equal("see " .. link("https://example.com/a?b=1") .. " now", text)
			assert.are.equal(1, count)
		end)

		it("keeps surrounding punctuation outside the link", function()
			local text, count = L.WrapURLs("(www.example.com).", "66bfff")
			assert.are.equal("(" .. link("www.example.com") .. ").", text)
			assert.are.equal(1, count)
		end)

		it("wraps several urls", function()
			local _, count = L.WrapURLs("http://a.io and www.b.com", "66bfff")
			assert.are.equal(2, count)
		end)

		it("leaves existing hyperlinks and escapes alone", function()
			local item = "|cffa335ee|Hitem:19019::::::::60:::::|h[http://not.a.url]|h|r"
			local text, count = L.WrapURLs(item .. " http://x.io", "66bfff")
			assert.are.equal(item .. " " .. link("http://x.io"), text)
			assert.are.equal(1, count)
		end)

		it("returns the original text when nothing matches", function()
			local original = "no links || here"
			local text, count = L.WrapURLs(original, "66bfff")
			assert.are.equal(original, text)
			assert.are.equal(0, count)
		end)
	end)

	describe("ParseLink", function()
		it("returns the url of our links only", function()
			assert.are.equal("https://a.io/x:y", L.ParseLink("addon:MerrinxUI:url:https://a.io/x:y"))
			assert.is_nil(L.ParseLink("addon:MerrinxUI:url:"))
			assert.is_nil(L.ParseLink("addon:Other:url:https://a.io"))
			assert.is_nil(L.ParseLink("item:19019"))
			assert.is_nil(L.ParseLink(nil))
		end)

		it("round-trips WrapURLs output", function()
			local text = L.WrapURLs("https://a.io/p", "66bfff")
			local data = text:match("|H(.-)|h")
			assert.are.equal("https://a.io/p", L.ParseLink(data))
		end)
	end)

	describe("PlainText", function()
		it("strips colours, textures and atlases and keeps link text", function()
			local text = "|cffff0000Red|r |TInterface\\Icons\\X:0|t|A:atlas:0:0|a|Hplayer:Bob|h[Bob]|h: hi"
			assert.are.equal("Red [Bob]: hi", L.PlainText(text))
		end)

		it("unescapes pipes and masks battle.net names", function()
			assert.are.equal("a | b ?", L.PlainText("a || b |Kq12|k"))
		end)
	end)

	describe("FadeTarget", function()
		it("fades only when enabled and idle long enough", function()
			assert.are.equal(1, L.FadeTarget(false, 10, 3, 0))
			assert.are.equal(1, L.FadeTarget(true, 2.9, 3, 0))
			assert.are.equal(0.2, L.FadeTarget(true, 3, 3, 0.2))
		end)
	end)

	describe("Approach", function()
		it("steps toward the target without overshooting", function()
			assert.are.equal(0.5, L.Approach(0, 1, 0.5))
			assert.are.equal(1, L.Approach(0.8, 1, 0.5))
			assert.are.equal(0.3, L.Approach(1, 0.3, 0.9))
			assert.are.equal(0.5, L.Approach(1, 0, 0.5))
		end)
	end)
end)
