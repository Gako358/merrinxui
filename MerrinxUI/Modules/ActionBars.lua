local addonName, ns = ...

local L = ns.ActionBarLogic

BINDING_HEADER_MERRINXUI = "MerrinxUI"
BINDING_NAME_MERRINXUI_TOGGLEBARS = "Toggle action bars"

local ActionBars = ns.addon:NewModule("ActionBars", "AceEvent-3.0")

local defaults = { profile = { enabled = false, bars = {} } }
for b = 1, 8 do
	defaults.profile.bars[b] = {
		enabled = b <= 3,
		perRow = 12,
		size = 36,
		spacing = 2,
		position = L.DefaultPosition(b),
		opacity = 100,
		mouseover = false,
		hideInCombat = false,
		keyToggle = false,
	}
end

function ActionBars:OnInitialize()
	self.db = ns.addon.db:RegisterNamespace("ActionBars", defaults)
	self:SetEnabledState(self.db.profile.enabled)
	self.headers = {}
	self.buttons = {}
	self.bindingOwner = CreateFrame("Frame")
	self.bindingApplies = 0
	self.alphas = {}
	self.visDrivers = {}
	self.fader = CreateFrame("Frame")
	self.fader:Hide()
	self.fader:SetScript("OnUpdate", function()
		self:UpdateAlphas()
	end)
end

function ActionBars:OnEnable()
	self:RegisterEvent("UPDATE_BINDINGS", "OnUpdateBindings")
	self:RegisterMessage("MERRINXUI_LOCK_CHANGED", "UpdateAlphas")
	self:QueueApply()
end

function ActionBars:OnUpdateBindings()
	ns.Combat:Run("ActionBars:Bindings", function()
		self:ApplyBindings()
	end)
end

function ActionBars:OnDisable()
	self:QueueApply()
end

function ActionBars:QueueApply()
	if not ns.Combat:Run("ActionBars:Apply", function()
		self:Apply()
	end) then
		ns.Debug:Log("ActionBars", "queued")
	end
end

function ActionBars:Refresh()
	if self.db.profile.enabled then
		if self:IsEnabled() then
			self:QueueApply()
		else
			self:Enable()
		end
	else
		self:Disable()
	end
end

function ActionBars:CreateBar(b)
	local h = CreateFrame("Frame", "MerrinxUIBar" .. b, UIParent, "SecureHandlerStateTemplate")
	self.headers[b] = h

	if b == 1 then
		h:SetAttribute("_onstate-page", [[ self:ChildUpdate("actionpage", newstate) ]])
	end

	h:SetAttribute(
		"_onstate-vis",
		[[
		if newstate == "show" and not self:GetAttribute("userhidden") then
			self:Show()
		else
			self:Hide()
		end
	]]
	)

	local buttons = {}
	self.buttons[b] = buttons
	for i = 1, 12 do
		local button = CreateFrame(
			"CheckButton",
			"MerrinxUIBar" .. b .. "Button" .. i,
			h,
			"ActionBarButtonTemplate, SecureActionButtonTemplate"
		)
		button:SetAttribute("type", "action")
		button:SetAttribute("index", i)
		if b == 1 then
			button:SetAttribute(
				"_childupdate-actionpage",
				[[ self:SetAttribute("action", (tonumber(message) - 1) * 12 + self:GetAttribute("index")) ]]
			)
		end
		button:RegisterForClicks("AnyUp", "AnyDown")
		buttons[i] = button
		self.native = self.native or button:GetWidth()
	end

	self:LayoutBar(b)
	ns.Mover:Register(h, "Bar " .. b, function()
		return self.db.profile.bars[b].position
	end)

	return h
end

function ActionBars:LayoutBar(b)
	local profile = self.db.profile.bars[b]
	local h = self.headers[b]
	local scale, positions, width, height =
		L.BarGeometry(12, profile.perRow, profile.size, profile.spacing, self.native)

	h:SetSize(width, height)

	local buttons = self.buttons[b]
	for i = 1, 12 do
		local button = buttons[i]
		local pos = positions[i]
		button:SetScale(scale)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", h, "TOPLEFT", pos.x, pos.y)
	end
end

function ActionBars:Apply()
	local profile = self.db.profile
	local enabledCount = 0
	for b = 1, 8 do
		if profile.bars[b].enabled then
			enabledCount = enabledCount + 1
		end
	end

	if self:IsEnabled() then
		ns.addon:GetModule("HideBlizzard"):Ensure("actionBars")
		self.applied = true

		if not self.toggle then
			local t = CreateFrame("Button", "MerrinxUIBarToggle", UIParent, "SecureHandlerClickTemplate")
			t:RegisterForClicks("AnyDown")
			t:SetAttribute(
				"_onclick",
				[[
				local hidden = not self:GetAttribute("barshidden")
				self:SetAttribute("barshidden", hidden)
				for b = 1, 8 do
					local h = self:GetFrameRef("bar" .. b)
					if h and h:GetAttribute("keytoggle") then
						h:SetAttribute("userhidden", hidden)
						if h:GetAttribute("state-vis") == "show" and not hidden then
							h:Show()
						else
							h:Hide()
						end
					end
				end
			]]
			)
			self.toggle = t
		end
		local barsHidden = self.toggle:GetAttribute("barshidden") == true

		for b = 1, 8 do
			local barProfile = profile.bars[b]
			if barProfile.enabled then
				local h = self.headers[b]
				if not h then
					h = self:CreateBar(b)
				end
				self:LayoutBar(b)

				if b == 1 then
					local o, v, t =
						C_ActionBar.GetOverrideBarIndex(),
						C_ActionBar.GetVehicleBarIndex(),
						C_ActionBar.GetTempShapeshiftBarIndex()
					if issecretvalue(o) or issecretvalue(v) or issecretvalue(t) then
						o, v, t = nil, nil, nil
					end
					self.pagingDriver = L.PagingDriver(o, v, t)
					RegisterStateDriver(h, "page", self.pagingDriver)
				else
					local buttons = self.buttons[b]
					for i = 1, 12 do
						buttons[i]:SetAttribute("action", L.Slot(L.PAGES[b], i))
					end
				end

				self.toggle:SetFrameRef("bar" .. b, h)
				h:SetAttribute("keytoggle", barProfile.keyToggle)
				h:SetAttribute("userhidden", barProfile.keyToggle and barsHidden)
				self.visDrivers[b] = L.VisibilityDriver(b, barProfile.hideInCombat)
				RegisterStateDriver(h, "vis", self.visDrivers[b])
				if h:GetAttribute("state-vis") == "show" and not h:GetAttribute("userhidden") then
					h:Show()
				else
					h:Hide()
				end

				ns.Mover:Apply(h)
			end
		end

		for b = 1, 8 do
			if not profile.bars[b].enabled then
				local h = self.headers[b]
				if h then
					UnregisterStateDriver(h, "page")
					UnregisterStateDriver(h, "vis")
					h:SetAttribute("keytoggle", false)
					self.visDrivers[b] = nil
					h:Hide()
					if b == 1 then
						self.pagingDriver = nil
					end
				end
			end
		end

		local anyMouseover = false
		for b = 1, 8 do
			if profile.bars[b].enabled and profile.bars[b].mouseover then
				anyMouseover = true
				break
			end
		end
		if anyMouseover then
			self.fader:Show()
		else
			self.fader:Hide()
		end
		self:UpdateAlphas()

		if not self.petBattleOwner then
			local pb = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
			pb:SetAttribute(
				"_onstate-petbattle",
				[[
				self:ClearBindings()
				if newstate == "1" then
					for i = 1, 12 do
						local command = "ACTIONBUTTON" .. i
						for k = 1, select("#", GetBindingKey(command)) do
							self:SetBinding(true, (select(k, GetBindingKey(command))), command)
						end
					end
				end
			]]
			)
			self.petBattleOwner = pb
		end
		RegisterStateDriver(self.petBattleOwner, "petbattle", "[petbattle] 1; 0")

		self:ApplyBindings()
	else
		for b = 1, 8 do
			local h = self.headers[b]
			if h then
				UnregisterStateDriver(h, "page")
				UnregisterStateDriver(h, "vis")
				h:SetAttribute("keytoggle", false)
				self.visDrivers[b] = nil
				h:Hide()
				if b == 1 then
					self.pagingDriver = nil
				end
			end
		end
		self.fader:Hide()

		ClearOverrideBindings(self.bindingOwner)

		if self.petBattleOwner then
			UnregisterStateDriver(self.petBattleOwner, "petbattle")
			self.petBattleOwner:SetAttribute("state-petbattle", "0")
		end

		if self.applied then
			ns.addon:Print("ActionBars: /reload restores Blizzard action bars")
			self.applied = false
		end
	end

	ns.Debug:Log("ActionBars", "apply", enabledCount)
end

function ActionBars:ApplyBindings()
	if self.applyingBindings then
		return
	end
	self.applyingBindings = true

	ClearOverrideBindings(self.bindingOwner)

	local count = 0
	if self:IsEnabled() then
		local profile = self.db.profile
		for b = 1, 8 do
			if profile.bars[b].enabled and self.headers[b] then
				local prefix = L.BindingPrefix(b)
				for i = 1, 12 do
					local buttonName = "MerrinxUIBar" .. b .. "Button" .. i
					for _, key in ipairs({ GetBindingKey(prefix .. i) }) do
						SetOverrideBindingClick(self.bindingOwner, false, key, buttonName, "LeftButton")
						count = count + 1
					end
				end
			end
		end

		if self.toggle then
			for _, key in ipairs({ GetBindingKey("MERRINXUI_TOGGLEBARS") }) do
				SetOverrideBindingClick(self.bindingOwner, false, key, "MerrinxUIBarToggle", "LeftButton")
			end
		end
	end

	self.applyingBindings = nil
	self.bindingApplies = self.bindingApplies + 1
	ns.Debug:Log("ActionBars", "bindings", count)
end

function ActionBars:UpdateAlphas()
	local unlocked = ns.Mover:IsUnlocked()
	for b = 1, 8 do
		local h = self.headers[b]
		local p = self.db.profile.bars[b]
		if h and p.enabled then
			local over = h:IsMouseOver()
			if issecretvalue(over) then
				over = true
			end
			local alpha = L.BarAlpha(p.opacity, p.mouseover, over, unlocked)
			if alpha ~= self.alphas[b] then
				h:SetAlpha(alpha)
				self.alphas[b] = alpha
			end
		end
	end
end

function ActionBars:GetOptions()
	local function barDisabled(b)
		return function()
			return not self.db.profile.bars[b].enabled
		end
	end

	local function barGroup(b)
		return {
			type = "group",
			name = "Bar " .. b,
			order = 10 + b,
			args = {
				enabled = {
					type = "toggle",
					name = "Enabled",
					order = 1,
					get = function()
						return self.db.profile.bars[b].enabled
					end,
					set = function(_, value)
						self.db.profile.bars[b].enabled = value
						self:Refresh()
					end,
				},
				perRow = {
					type = "range",
					name = "Per row",
					order = 2,
					min = 1,
					max = 12,
					step = 1,
					disabled = barDisabled(b),
					get = function()
						return self.db.profile.bars[b].perRow
					end,
					set = function(_, value)
						self.db.profile.bars[b].perRow = value
						self:Refresh()
					end,
				},
				size = {
					type = "range",
					name = "Size",
					order = 3,
					min = 16,
					max = 64,
					step = 1,
					disabled = barDisabled(b),
					get = function()
						return self.db.profile.bars[b].size
					end,
					set = function(_, value)
						self.db.profile.bars[b].size = value
						self:Refresh()
					end,
				},
				spacing = {
					type = "range",
					name = "Spacing",
					order = 4,
					min = 0,
					max = 10,
					step = 1,
					disabled = barDisabled(b),
					get = function()
						return self.db.profile.bars[b].spacing
					end,
					set = function(_, value)
						self.db.profile.bars[b].spacing = value
						self:Refresh()
					end,
				},
				opacity = {
					type = "range",
					name = "Opacity",
					order = 5,
					min = 0,
					max = 100,
					step = 5,
					disabled = barDisabled(b),
					get = function()
						return self.db.profile.bars[b].opacity
					end,
					set = function(_, value)
						self.db.profile.bars[b].opacity = value
						self:Refresh()
					end,
				},
				mouseover = {
					type = "toggle",
					name = "Show on mouseover",
					order = 6,
					disabled = barDisabled(b),
					get = function()
						return self.db.profile.bars[b].mouseover
					end,
					set = function(_, value)
						self.db.profile.bars[b].mouseover = value
						self:Refresh()
					end,
				},
				hideInCombat = {
					type = "toggle",
					name = "Hide in combat",
					order = 7,
					disabled = barDisabled(b),
					get = function()
						return self.db.profile.bars[b].hideInCombat
					end,
					set = function(_, value)
						self.db.profile.bars[b].hideInCombat = value
						self:Refresh()
					end,
				},
				keyToggle = {
					type = "toggle",
					name = "Hide with key toggle",
					order = 8,
					desc = "Bind the key under Key Bindings > AddOns > MerrinxUI.",
					disabled = barDisabled(b),
					get = function()
						return self.db.profile.bars[b].keyToggle
					end,
					set = function(_, value)
						self.db.profile.bars[b].keyToggle = value
						self:Refresh()
					end,
				},
			},
		}
	end

	local args = {
		enabled = {
			type = "toggle",
			name = "Enabled",
			order = 1,
			desc = "Hides Blizzard's action bars. /reload restores them after turning this off.",
			get = function()
				return self.db.profile.enabled
			end,
			set = function(_, value)
				self.db.profile.enabled = value
				self:Refresh()
			end,
		},
	}
	for b = 1, 8 do
		args["bar" .. b] = barGroup(b)
	end

	return {
		type = "group",
		name = "ActionBars",
		args = args,
	}
end

function ActionBars:GetDebugChecks()
	local function readPoint(region)
		if type(region.IsAnchoringRestricted) == "function" then
			local restricted = region:IsAnchoringRestricted()
			if issecretvalue(restricted) or restricted then
				return false
			end
		end
		local ok, p, rel, rp, x, y = pcall(region.GetPoint, region, 1)
		if not ok then
			return false
		end
		return true, p, rel, rp, x, y
	end

	local checks = {
		{
			name = "apis",
			run = function()
				local missing = {}
				local function check(name, fn)
					if type(fn) ~= "function" then
						table.insert(missing, name)
					end
				end

				local cab = type(C_ActionBar) == "table" and C_ActionBar or {}
				check("C_ActionBar.GetOverrideBarIndex", cab.GetOverrideBarIndex)
				check("C_ActionBar.GetVehicleBarIndex", cab.GetVehicleBarIndex)
				check("C_ActionBar.GetTempShapeshiftBarIndex", cab.GetTempShapeshiftBarIndex)
				check("C_ActionBar.GetBonusBarOffset", cab.GetBonusBarOffset)
				check("C_ActionBar.GetActionBarPage", cab.GetActionBarPage)
				check("RegisterStateDriver", RegisterStateDriver)
				check("UnregisterStateDriver", UnregisterStateDriver)
				check("SetOverrideBindingClick", SetOverrideBindingClick)
				check("ClearOverrideBindings", ClearOverrideBindings)
				check("GetBindingKey", GetBindingKey)
				check("GetBindingAction", GetBindingAction)

				if #missing > 0 then
					return "FAIL", unpack(missing, 1, #missing)
				end
				return "PASS"
			end,
		},
		{
			name = "blizzard bars",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				local hb = ns.addon:GetModule("HideBlizzard")
				return (hb.forced.actionBars == true) and "PASS" or "FAIL"
			end,
		},
		{
			name = "bars",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local enabledCount, createdCount = 0, 0
				local ok = true
				for b = 1, 8 do
					local barProfile = self.db.profile.bars[b]
					local h = self.headers[b]
					if h then
						createdCount = createdCount + 1
					end
					if barProfile.enabled then
						enabledCount = enabledCount + 1
						if not h or not self.buttons[b] or #self.buttons[b] ~= 12 then
							ok = false
						end
					elseif h and h:IsShown() then
						ok = false
					end
				end

				return ok and "PASS" or "FAIL", enabledCount, createdCount, self.native
			end,
		},
		{
			name = "paging",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not (self.db.profile.bars[1].enabled and self.headers[1]) then
					return "SKIP", "bar 1 off"
				end

				local h = self.headers[1]
				local rawPage = h:GetAttribute("state-page")
				local offset = C_ActionBar.GetBonusBarOffset()
				local barPage = C_ActionBar.GetActionBarPage()
				if issecretvalue(rawPage) or issecretvalue(offset) or issecretvalue(barPage) then
					return "INFO", "secret"
				end

				local overrideIndex = C_ActionBar.GetOverrideBarIndex()
				local vehicleIndex = C_ActionBar.GetVehicleBarIndex()
				local shapeshiftIndex = C_ActionBar.GetTempShapeshiftBarIndex()
				if issecretvalue(overrideIndex) or issecretvalue(vehicleIndex) or issecretvalue(shapeshiftIndex) then
					return "INFO", "secret"
				end

				local page = tonumber(rawPage)
				if page == overrideIndex or page == vehicleIndex or page == shapeshiftIndex then
					return "INFO", "special"
				end

				local action1 = self.buttons[1][1]:GetAttribute("action")
				if issecretvalue(action1) then
					return "INFO", "secret"
				end

				local ok = page == L.ExpectedPage(barPage, offset) and action1 == L.Slot(page, 1)
				return ok and "PASS" or "FAIL", page, offset, barPage, action1
			end,
		},
		{
			name = "driver",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not (self.db.profile.bars[1].enabled and self.headers[1]) then
					return "SKIP", "bar 1 off"
				end
				return "INFO", self.pagingDriver
			end,
		},
		{
			name = "bindings",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end

				local pb = type(C_PetBattles) == "table" and C_PetBattles or {}
				local inBattle = type(pb.IsInBattle) == "function" and pb.IsInBattle() or false
				if issecretvalue(inBattle) then
					return "INFO", "secret", self.bindingApplies
				end

				local ok, total = 0, 0
				local secret = false
				local firstBadKey, firstBadAction
				for b = 1, 8 do
					if self.db.profile.bars[b].enabled and self.headers[b] then
						local prefix = L.BindingPrefix(b)
						for i = 1, 12 do
							local expected = (b == 1 and inBattle) and ("ACTIONBUTTON" .. i)
								or ("CLICK MerrinxUIBar" .. b .. "Button" .. i .. ":LeftButton")
							for _, key in ipairs({ GetBindingKey(prefix .. i) }) do
								if issecretvalue(key) then
									secret = true
								else
									total = total + 1
									local action = GetBindingAction(key, true)
									if issecretvalue(action) then
										secret = true
									elseif action == expected then
										ok = ok + 1
									elseif not firstBadKey then
										firstBadKey, firstBadAction = key, action
									end
								end
							end
						end
					end
				end

				if secret then
					return "INFO", "secret", self.bindingApplies
				end
				if total == 0 then
					return "INFO", "no keys bound", self.bindingApplies
				end
				if ok == total then
					if inBattle then
						return "PASS", ok, total, self.bindingApplies, "pet battle"
					end
					return "PASS", ok, total, self.bindingApplies
				end
				if inBattle then
					return "FAIL", ok, total, firstBadKey, firstBadAction, self.bindingApplies, "pet battle"
				end
				return "FAIL", ok, total, firstBadKey, firstBadAction, self.bindingApplies
			end,
		},
		{
			name = "pet battle",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				return "INFO",
					(type(C_PetBattles) == "table" and type(C_PetBattles.IsInBattle) == "function"),
					self.petBattleOwner and self.petBattleOwner:GetAttribute("state-petbattle")
			end,
		},
		{
			name = "keydown",
			run = function()
				return "INFO", C_CVar.GetCVar("ActionButtonUseKeyDown")
			end,
		},
		{
			name = "toggle",
			run = function(ctx)
				if ctx.enabled == false then
					return "SKIP", "module disabled"
				end
				if not self.toggle then
					return "FAIL", "no toggle button"
				end

				local barsHidden = self.toggle:GetAttribute("barshidden") == true
				local ok, total = 0, 0
				local secret = false
				for _, key in ipairs({ GetBindingKey("MERRINXUI_TOGGLEBARS") }) do
					if issecretvalue(key) then
						secret = true
					else
						total = total + 1
						local action = GetBindingAction(key, true)
						if issecretvalue(action) then
							secret = true
						elseif action == "CLICK MerrinxUIBarToggle:LeftButton" then
							ok = ok + 1
						end
					end
				end

				if secret then
					return "INFO", "secret"
				end
				if total == 0 then
					return "INFO", "no keys bound", barsHidden
				end
				return (ok == total) and "PASS" or "FAIL", ok, total, barsHidden
			end,
		},
	}

	for b = 1, 8 do
		if self.db.profile.bars[b].enabled and self.headers[b] then
			table.insert(checks, {
				name = "layout " .. b,
				run = function(ctx)
					if ctx.enabled == false then
						return "SKIP", "module disabled"
					end

					local profile = self.db.profile.bars[b]
					local h = self.headers[b]
					local expectedScale, positions, expectedW, expectedH =
						L.BarGeometry(12, profile.perRow, profile.size, profile.spacing, self.native)

					local w, ht = h:GetWidth(), h:GetHeight()
					local ok = math.abs(h:GetScale() - 1) <= 0.001
						and math.abs(w - expectedW) <= 0.5
						and math.abs(ht - expectedH) <= 0.5

					local secret = false
					local pointsRestricted = false
					local buttons = self.buttons[b]
					for i = 1, 12 do
						if math.abs(buttons[i]:GetScale() - expectedScale) > 0.001 then
							ok = false
						end

						local ptOk, point, relativeTo, relativePoint, x, y = readPoint(buttons[i])
						if not ptOk then
							pointsRestricted = true
						elseif
							issecretvalue(point)
							or issecretvalue(relativeTo)
							or issecretvalue(relativePoint)
							or issecretvalue(x)
							or issecretvalue(y)
						then
							secret = true
						else
							local pos = positions[i]
							if
								point ~= "TOPLEFT"
								or relativeTo ~= h
								or relativePoint ~= "TOPLEFT"
								or math.abs(x - pos.x) > 0.5
								or math.abs(y - pos.y) > 0.5
							then
								ok = false
							end
						end
					end

					local detailScale = buttons[1]:GetScale()
					if not ok then
						return "FAIL", detailScale, w, ht
					end
					if secret then
						return "INFO", detailScale, w, ht, "secret"
					end
					if pointsRestricted then
						return "PASS", detailScale, w, ht, "points restricted"
					end
					return "PASS", detailScale, w, ht
				end,
			})

			table.insert(checks, {
				name = "visibility " .. b,
				run = function(ctx)
					if ctx.enabled == false then
						return "SKIP", "module disabled"
					end

					local p = self.db.profile.bars[b]
					local h = self.headers[b]
					local state = h:GetAttribute("state-vis")
					local userhidden = h:GetAttribute("userhidden")
					local shown = h:IsShown()

					if issecretvalue(state) or issecretvalue(userhidden) or issecretvalue(shown) then
						return "INFO", "secret"
					end

					local ok = self.visDrivers[b] == L.VisibilityDriver(b, p.hideInCombat)
						and (h:GetAttribute("keytoggle") == true) == p.keyToggle
						and shown == (state == "show" and not userhidden)

					return ok and "PASS" or "FAIL", state, userhidden == true, shown
				end,
			})

			table.insert(checks, {
				name = "alpha " .. b,
				run = function(ctx)
					if ctx.enabled == false then
						return "SKIP", "module disabled"
					end

					local p = self.db.profile.bars[b]
					local h = self.headers[b]
					local over = h:IsMouseOver()
					local unlocked = ns.Mover:IsUnlocked()
					local alpha = h:GetAlpha()

					if issecretvalue(over) or issecretvalue(unlocked) or issecretvalue(alpha) then
						return "INFO", "secret"
					end

					local expected = L.BarAlpha(p.opacity, p.mouseover, over, unlocked)
					local ok = math.abs(alpha - expected) <= 0.01
					return ok and "PASS" or "FAIL", alpha, expected
				end,
			})
		end
	end

	for b = 2, 8 do
		if self.db.profile.bars[b].enabled and self.headers[b] then
			table.insert(checks, {
				name = "actions " .. b,
				run = function(ctx)
					if ctx.enabled == false then
						return "SKIP", "module disabled"
					end

					local buttons = self.buttons[b]
					local ok = true
					local first, last
					for i = 1, 12 do
						local action = buttons[i]:GetAttribute("action")
						local expected = L.Slot(L.PAGES[b], i)
						if issecretvalue(action) or action ~= expected then
							ok = false
						end
						if i == 1 then
							first = action
						end
						if i == 12 then
							last = action
						end
					end
					return ok and "PASS" or "FAIL", first, last
				end,
			})
		end
	end

	return checks
end
