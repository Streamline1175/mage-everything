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

-- Individual talents: spell ID of the talent -> ranks taken.
ME.talents = {}
ME.talentsRead = false

local function readTalents()
	local talents = {}
	if not (C_Traits and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo and C_Traits.GetEntryInfo
		and C_Traits.GetDefinitionInfo and C_Traits.GetConfigInfo) then
		return talents, false
	end
	local configID = activeConfigID()
	local config = configID and ME.Try(C_Traits.GetConfigInfo, configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	local nodes = treeID and ME.Try(C_Traits.GetTreeNodes, treeID)
	if type(nodes) ~= "table" or #nodes == 0 then return talents, false end
	for _, nodeID in ipairs(nodes) do
		local node = ME.Try(C_Traits.GetNodeInfo, configID, nodeID)
		local rank = node and (node.activeRank or node.currentRank) or 0
		local entryID = node and ((node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1]))
		if type(rank) == "number" and rank > 0 and entryID then
			local entry = ME.Try(C_Traits.GetEntryInfo, configID, entryID)
			local def = entry and entry.definitionID and ME.Try(C_Traits.GetDefinitionInfo, entry.definitionID)
			if def and def.spellID then talents[def.spellID] = rank end
		end
	end
	return talents, true
end

-- Ranks in a talent (by its spell ID). When talents cannot be read on this
-- client, returns `fallback` so callers can use a points-based guess.
function ME.TalentRank(spellID, fallback)
	if not ME.talentsRead then return fallback or 0 end
	return ME.talents[spellID] or 0
end

function Spec:Update()
	ME.talents, ME.talentsRead = readTalents()
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
