-- MageEverything: spell catalogue and runtime resolution.
--
-- WoW Forever has spell ranks (each rank has its own spell ID) and several
-- new mage spells whose IDs differ from older clients. Nothing here trusts a
-- hard-coded ID: every spell is resolved against the player's spellbook by
-- name (using the IDs below only to obtain the localised name), and the
-- highest known rank wins.
local _, ME = ...
local Spells = ME:NewModule("Spells")

-- key = { English name, candidate IDs (rank 1 / known variants) }
-- IDs checked against the datamined tables for Forever build 1.60.1.70938.
local DEFS = {
	-- Nukes
	Fireball        = { "Fireball", 133 },
	Frostbolt       = { "Frostbolt", 116 },
	FrostfireBolt   = { "Frostfire Bolt", 401502 },
	ArcaneMissiles  = { "Arcane Missiles", 5143 },
	ArcaneBlast     = { "Arcane Blast", 400574 },
	ArcaneWrath     = { "Arcane Wrath", 1326079 },
	Pyroblast       = { "Pyroblast", 11366 },
	Scorch          = { "Scorch", 2948 },
	FireBlast       = { "Fire Blast", 2136 },
	IceLance        = { "Ice Lance", 1312002, 400640 },
	Shoot           = { "Shoot", 5019 },
	-- AoE
	ArcaneExplosion = { "Arcane Explosion", 1449 },
	Blizzard        = { "Blizzard", 10 },
	Flamestrike     = { "Flamestrike", 2120 },
	ConeOfCold      = { "Cone of Cold", 120 },
	BlastWave       = { "Blast Wave", 11113 },
	FrostNova       = { "Frost Nova", 122 },
	-- Cooldowns
	Combustion      = { "Combustion", 11129 },
	ArcanePower     = { "Arcane Power", 12042 },
	PresenceOfMind  = { "Presence of Mind", 12043 },
	ColdSnap        = { "Cold Snap", 12472 },
	Evocation       = { "Evocation", 12051 },
	-- Defence / utility
	IceBarrier      = { "Ice Barrier", 11426 },
	IceBlock        = { "Ice Block", 11958 },
	ManaShield      = { "Mana Shield", 1463 },
	FireWard        = { "Fire Ward", 543 },
	FrostWard       = { "Frost Ward", 6143 },
	Blink           = { "Blink", 1953 },
	Counterspell    = { "Counterspell", 2139 },
	Polymorph       = { "Polymorph", 118 },
	-- (the Pig and Turtle variants share the name "Polymorph" in this client)
	PolymorphCow    = { "Polymorph: Cow", 28270 },
	RemoveCurse     = { "Remove Lesser Curse", 475 },
	SlowFall        = { "Slow Fall", 130 },
	-- Buffs
	ArcaneIntellect = { "Arcane Intellect", 1459 },
	ArcaneBrilliance = { "Arcane Brilliance", 23028 },
	FrostArmor      = { "Frost Armor", 168 },
	IceArmor        = { "Ice Armor", 7302 },
	MageArmor       = { "Mage Armor", 6117 },
	DampenMagic     = { "Dampen Magic", 604 },
	AmplifyMagic    = { "Amplify Magic", 1008 },
	-- Conjures
	ConjureWater    = { "Conjure Water", 5504 },
	ConjureFood     = { "Conjure Food", 587 },
	ConjureManaAgate   = { "Conjure Mana Agate", 759 },
	ConjureManaJade    = { "Conjure Mana Jade", 3552 },
	ConjureManaCitrine = { "Conjure Mana Citrine", 10053 },
	ConjureManaRuby    = { "Conjure Mana Ruby", 10054 },
	-- Racial
	Cannibalize     = { "Cannibalize", 20577 },
	-- Forever additions
	Study           = { "Study", 1302508 },
	ComprehendScroll = { "Comprehend Scroll", 1296017 },
	-- Proc auras (buff IDs from the Forever 1.60.1 data; the talents that
	-- grant them are 400588 / 400647 / 400624 and share the same names).
	Clearcasting    = { "Clearcasting", 12536 },
	MissileBarrage  = { "Missile Barrage", 400589 },
	FingersOfFrost  = { "Fingers of Frost", 400669 },
	HeatingUp       = { "Heating Up", 400625 },
}
Spells.DEFS = DEFS

-- Teleports / portals (resolved by name like everything else).
Spells.PORTALS = {
	{ city = "Stormwind",     faction = "Alliance", tp = { "Teleport: Stormwind", 3561 },     portal = { "Portal: Stormwind", 10059 } },
	{ city = "Ironforge",     faction = "Alliance", tp = { "Teleport: Ironforge", 3562 },     portal = { "Portal: Ironforge", 11416 } },
	{ city = "Darnassus",     faction = "Alliance", tp = { "Teleport: Darnassus", 3565 },     portal = { "Portal: Darnassus", 11419 } },
	{ city = "Orgrimmar",     faction = "Horde",    tp = { "Teleport: Orgrimmar", 3567 },     portal = { "Portal: Orgrimmar", 11417 } },
	{ city = "Undercity",     faction = "Horde",    tp = { "Teleport: Undercity", 3563 },     portal = { "Portal: Undercity", 11418 } },
	{ city = "Thunder Bluff", faction = "Horde",    tp = { "Teleport: Thunder Bluff", 3566 }, portal = { "Portal: Thunder Bluff", 11420 } },
	{ city = "Dalaran",       faction = "Both",     tp = { "Teleport: Dalaran", 1297659 } }, -- no mage portal exists
}

local book = {}        -- localised name -> { id = highest-rank spellID, rank = n }
local resolved = {}    -- key -> spellID
local nameToKey = {}   -- localised (and English) name -> key
local localName = {}   -- key -> localised name

local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, id)
		if ok and type(name) == "string" and name ~= "" and not ME.issecret(name) then return name end
	end
end
Spells.SpellName = spellName

local function scanBook()
	wipe(book)
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
	for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
		if line and line.numSpellBookItems then
			local first = (line.itemIndexOffset or 0) + 1
			for slot = first, first + line.numSpellBookItems - 1 do
				local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
				if ok and info and info.spellID and info.name
					and (spellType == nil or info.itemType == spellType)
					and not info.isOffSpec then
					local rank = tonumber((info.subName or ""):match("%d+")) or 0
					local cur = book[info.name]
					-- Later entries / higher ranks replace earlier ones.
					if not cur or rank >= cur.rank then
						book[info.name] = { id = info.spellID, rank = rank, passive = info.isPassive }
					end
				end
			end
		end
	end
end

local function isKnownID(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
		if ok and known then return true end
	end
	if IsPlayerSpell then
		local ok, known = pcall(IsPlayerSpell, id)
		if ok and known then return true end
	end
	return false
end

-- Resolve one definition {englishName, id, id...} to the known spell ID.
local function resolveDef(def)
	local names = { def[1] }
	for i = 2, #def do
		local n = spellName(def[i])
		if n then names[#names + 1] = n end
	end
	for _, n in ipairs(names) do
		local hit = book[n]
		if hit then return hit.id, n, names end
	end
	for i = 2, #def do
		if isKnownID(def[i]) then return def[i], spellName(def[i]) or def[1], names end
	end
	return nil, names[#names], names
end
Spells.ResolveDef = resolveDef

function Spells:Rebuild()
	scanBook()
	local before = self.built and CopyTable(resolved) or nil
	wipe(resolved)
	for key, def in pairs(DEFS) do
		local id, name, names = resolveDef(def)
		resolved[key] = id
		if before and id and not before[key] then
			ME:Fire("NEW_SPELL", key)
		end
		localName[key] = name
		for _, n in ipairs(names) do nameToKey[n] = key end
	end
	-- Only start announcing new spells once the spellbook has loaded.
	if next(book) then self.built = true end
	ME:Fire("SPELLS_UPDATED")
end

-- Highest-rank spell ID the spellbook holds under a (localised) name.
function Spells.BookID(name)
	local hit = book[name]
	return hit and hit.id or nil
end

-- Active spellbook spells the addon has no entry for (for /mage diag).
function Spells.Uncatalogued()
	local list = {}
	for name, hit in pairs(book) do
		if not nameToKey[name] and not hit.passive and hit.id ~= 6603 -- 6603 = Attack
			and not name:find("^Teleport") and not name:find("^Portal") then -- portal menu
			list[#list + 1] = name .. "=" .. tostring(hit.id)
		end
	end
	table.sort(list)
	return list
end

-- Entries may also be items, written "item:<id>" (the mana gem).
local function itemID(key)
	return type(key) == "string" and tonumber(key:match("^item:(%d+)$")) or nil
end
ME.ItemID = itemID

-- Public accessors ---------------------------------------------------------
function ME.Spell(key) return resolved[key] end
function ME.Known(key) return resolved[key] ~= nil end
function ME.SpellLabel(key)
	local item = itemID(key)
	if item then
		local n = C_Item and C_Item.GetItemNameByID and ME.Try(C_Item.GetItemNameByID, item)
		return type(n) == "string" and n or "Item"
	end
	return localName[key] or (DEFS[key] and DEFS[key][1]) or key
end

-- Maps any spell ID (any rank) back to a catalogue key via its name.
function ME.KeyForSpell(spellID)
	if not spellID or ME.issecret(spellID) then return nil end
	local n = spellName(spellID)
	return n and nameToKey[n] or nil
end

function ME.SpellIcon(key)
	local item = itemID(key)
	if item then
		local tex = C_Item and C_Item.GetItemIconByID and ME.Try(C_Item.GetItemIconByID, item)
		return tex or "Interface\\Icons\\INV_Misc_Gem_Ruby_01"
	end
	local id = resolved[key]
	if not id then
		local def = DEFS[key]
		id = def and def[2]
	end
	if id and C_Spell.GetSpellTexture then
		local ok, tex = pcall(C_Spell.GetSpellTexture, id)
		if ok and tex then return tex end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- First known key from a list.
function ME.FirstKnown(...)
	for i = 1, select("#", ...) do
		local k = select(i, ...)
		if resolved[k] then return k end
	end
end

function Spells:OnLogin()
	self:Rebuild()
	local pending
	local function queue()
		if pending then return end
		pending = true
		C_Timer.After(0.3, function()
			pending = false
			Spells:Rebuild()
		end)
	end
	ME:On("SPELLS_CHANGED", queue)
	ME:On("LEARNED_SPELL_IN_SKILL_LINE", queue)
	ME:On("PLAYER_LEVEL_UP", queue)
	ME:On("PLAYER_ENTERING_WORLD", queue)
	-- Talents can grant spells (Ice Lance, Pyroblast, Arcane Blast...).
	ME:On("TRAIT_CONFIG_UPDATED", queue)
	ME:On("PLAYER_TALENT_UPDATE", queue)
	ME:On("ACTIVE_TALENT_GROUP_CHANGED", queue)
	ME:On("TRAIT_TREE_CURRENCY_INFO_UPDATED", queue)
	-- Safety net: the spellbook sometimes settles a moment after the event.
	ME:On("PLAYER_REGEN_ENABLED", queue)
end
