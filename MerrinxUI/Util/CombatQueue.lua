local addonName, ns = ...

local CombatQueue = {}
ns.CombatQueue = CombatQueue

local Queue = {}
local mt = { __index = Queue }

function CombatQueue.New()
	return setmetatable({ order = {}, byKey = {} }, mt)
end

function Queue:Push(key, fn)
	if self.byKey[key] == nil then
		table.insert(self.order, key)
	end
	self.byKey[key] = fn
end

-- Snapshot the pending entries before running them, so a Push made by a
-- drained fn lands in the next Drain rather than extending this one.
function Queue:Drain()
	local order, byKey = self.order, self.byKey
	self.order, self.byKey = {}, {}

	for _, key in ipairs(order) do
		local fn = byKey[key]
		if fn then
			fn()
		end
	end
end
