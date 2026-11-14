-- MageEverything: talent-tree ("spec") detection.
--
-- WoW Forever gives every class a single specialisation whose talent frame
-- contains three classic trees. Blizzard's own talent UI reads the points per
-- tree through C_Traits group currencies; this does the same and names the
-- tree with the most points as the played spec.
local _, ME = ...
local Spec = ME:NewModule("Spec")

ME.spec = "NONE"
ME.specPoints = { ARCANE = 0, FIRE = 0, FROST = 0 }

local ORDER = { "ARCANE", "FIRE", "FROST" }

local function activeConfigID()
	local SI = C_SpecializationInfo
	if SI and SI.GetActiveSpecGroup and SI.GetCombatConfigIDForSpecGroup then
		local group = ME.Try(SI.GetActiveSpecGroup)
		local id = group and ME.Try(SI.GetCombatConfigIDForSpecGroup, group)
		if id then return id end
	end
	if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
		return ME.Try(C_ClassTalents.GetActiveConfigID)
	end
end

local function schoolFor(info, index)
	local n = (info.displayName or ""):lower()
	if n:find("arcane") then return "ARCANE" end
	if n:find("fire") then return "FIRE" end
	if n:find("frost") then return "FROST" end
	return ORDER[index]
end

local function readPoints()
	local points = { ARCANE = 0, FIRE = 0, FROST = 0 }
	if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then
		return points, false
	end
	local configID = activeConfigID()
	if not configID then return points, false end
	local config = ME.Try(C_Traits.GetConfigInfo, configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	if not treeID then return points, false end
	local display = ME.Try(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
	if type(display) ~= "table" or #display == 0 then return points, false end

	table.sort(display, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
	local groupIDs, schoolByGroup = {}, {}
	for i, info in ipairs(display) do
		groupIDs[#groupIDs + 1] = info.groupID
		schoolByGroup[info.groupID] = schoolFor(info, i)
	end
	local currencies = ME.Try(C_Traits.GetGroupCurrencyInfo, configID, groupIDs)
	if type(currencies) ~= "table" then return points, false end
	for _, g in ipairs(currencies) do
		local school = schoolByGroup[g.traitNodeGroupID]
		local c = g.currencyInfos and g.currencyInfos[1]
		if school and c and type(c.spent) == "number" then
			points[school] = points[school] + c.spent
		end
	end
	return points, true
end

function Spec:Update()
	local points, ok = readPoints()
	ME.specPoints = points
	ME.specDetected = ok

	local best, bestPts = "NONE", 0
	for _, s in ipairs(ORDER) do
		if points[s] > bestPts then best, bestPts = s, points[s] end
	end
	local override = ME.db.specOverride
	if override and override ~= "AUTO" then best = override end

	if best ~= ME.spec then
		ME.spec = best
		ME:Fire("SPEC_CHANGED", best)
	end
end

function Spec:OnLogin()
	self:Update()
	local pending
	local function queue()
		if pending then return end
		pending = true
		C_Timer.After(0.5, function()
			pending = false
			Spec:Update()
		end)
	end
	for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
		"TRAIT_TREE_CURRENCY_INFO_UPDATED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP" }) do
		ME:On(e, queue)
	end
end
