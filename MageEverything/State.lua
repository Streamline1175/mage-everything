-- MageEverything: combat state built only from data addons may read in combat.
--
-- Readable in combat: whether a spell is usable / on cooldown, proc glow
-- events, the player's own casts, unit existence / hostility / combat flags,
-- threat status. Not readable: health, mana, aura contents, the combat log.
-- Where the game hides something, this module remembers it from the player's
-- own casts instead (for example "Frost Nova was cast 3s ago, so the pack is
-- frozen").
local _, ME = ...
local State = ME:NewModule("State")
local Plain, Bool, Try, issecret = ME.Plain, ME.Bool, ME.Try, ME.issecret

local S = {
	inCombat = false, enemies = 0, hasTarget = false, targetElite = false,
	aggro = false, moving = false, casting = nil, channeling = nil,
	targetCasting = false, overlay = {}, lastCast = nil, lastCastTime = 0,
	abStacks = 0, abExpire = 0, huStacks = 0, huExpire = 0,
	scorchStacks = 0, scorchExpire = 0, frozenExpire = 0, frozenHits = 0,
	wcStacks = 0, wcExpire = 0, sheepStart = 0, sheepDur = 0, sheepBrokeAt = 0, focusCasting = false, addsAt = 0,
}
ME.state = S

local mem = {} -- remembered effect -> expiry time

-- Session counters for /mage diag: which signals has the client delivered?
local seen = { casts = 0, unknown = {}, glows = 0, targetCasts = 0, focusCasts = 0, auraEvents = 0 }
ME.seen = seen

-- true when enemy nameplates are switched off (nil if it cannot be told).
function ME.EnemyNameplatesOff()
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	local v = get and ME.Try(get, "nameplateShowEnemies")
	if v == nil or ME.issecret(v) then return nil end
	return tostring(v) == "0"
end

local function now() return GetTime() end

function ME.Remember(name, seconds) mem[name] = now() + seconds end
function ME.Forget(name) mem[name] = nil end
function ME.Remembered(name)
	local t = mem[name]
	return t ~= nil and now() < t
end

---------------------------------------------------------------------------
-- Auras (readable out of combat; in combat only for never-secret auras)
---------------------------------------------------------------------------
-- Returns: true (present), false (known absent), nil (hidden by the client),
-- plus the aura table when present.
function ME.HasBuff(key)
	local def = ME.Spells.DEFS[key]
	if not def then return false end
	local UA = C_UnitAuras
	if UA then
		local id = ME.Spell(key)
		if id and UA.GetPlayerAuraBySpellID then
			local aura = Try(UA.GetPlayerAuraBySpellID, id)
			if type(aura) == "table" then return true, aura end
		end
		for i = 2, #def do
			if UA.GetPlayerAuraBySpellID then
				local aura = Try(UA.GetPlayerAuraBySpellID, def[i])
				if type(aura) == "table" then return true, aura end
			end
		end
		if UA.GetAuraDataBySpellName then
			local aura = Try(UA.GetAuraDataBySpellName, "player", ME.SpellLabel(key), "HELPFUL")
			if type(aura) == "table" then return true, aura end
		end
	end
	if ME.AurasHidden() then return nil end
	return false
end

function ME.AurasHidden()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then
		local v = Try(C_Secrets.ShouldAurasBeSecret)
		if v ~= nil and not issecret(v) then return v and true or false end
	end
	-- No predicate available: assume hidden whenever we are in combat.
	return S.inCombat
end

-- Stack count of a readable aura, or nil.
local function stacksOf(aura)
	local n = aura and aura.applications
	if n == nil or issecret(n) then return nil end
	return n
end

---------------------------------------------------------------------------
-- Spell readiness
---------------------------------------------------------------------------
-- Returns ready(bool), reason ("mana" | "cooldown" | "unknown" | "unusable").
function ME.Ready(key)
	local id = ME.Spell(key)
	if not id then return false, "unknown" end
	local usable, noMana = C_Spell.IsSpellUsable(id)
	if not Bool(usable) then
		return false, Bool(noMana) and "mana" or "unusable"
	end
	local cd = Try(C_Spell.GetSpellCooldown, id)
	if cd then
		local active = cd.isActive
		if active ~= nil and not issecret(active) then
			-- isActive / isOnGCD are never secret: usable for logic in combat.
			if active and not Bool(cd.isOnGCD) then return false, "cooldown" end
		else
			local dur = Plain(cd.duration)
			if dur and dur > 1.6 then return false, "cooldown" end
		end
	end
	return true
end

function ME.OnCooldown(key)
	local _, why = ME.Ready(key)
	return why == "cooldown"
end

function ME.OutOfMana(key)
	local _, why = ME.Ready(key)
	return why == "mana"
end

-- true / false / nil (no target or not applicable)
function ME.InRange(key)
	local id = ME.Spell(key)
	if not id or not S.hasTarget then return nil end
	local r = Try(C_Spell.IsSpellInRange, id, "target")
	if r == nil or issecret(r) then return nil end
	return r and true or false
end

---------------------------------------------------------------------------
-- Procs
-- Auras are hidden in combat and this build has no proc-glow data, so procs
-- are also read from two things that stay visible: a spell's current mana
-- cost (Clearcasting / Missile Barrage make spells free; Arcane Blast stacks
-- double its cost) and its current cast time (Heating Up shortens Pyroblast).
---------------------------------------------------------------------------
local function manaCost(key)
	local id = ME.Spell(key)
	if not id or not C_Spell.GetSpellPowerCost then return nil end
	local costs = Try(C_Spell.GetSpellPowerCost, id)
	if type(costs) ~= "table" then return nil end
	for _, c in ipairs(costs) do
		local kind = Plain(c.type)
		if kind == nil or kind == 0 then return Plain(c.cost) end
	end
	return nil
end
ME.ManaCost = manaCost

local function castTime(key)
	local id = ME.Spell(key)
	if not id or not C_Spell.GetSpellInfo then return nil end
	local info = Try(C_Spell.GetSpellInfo, id)
	return type(info) == "table" and Plain(info.castTime) or nil
end

-- Is mana below `fraction` of maximum? Mana itself is hidden, but maximum
-- mana, each spell's cost and "not enough mana for this spell" are not, so
-- an unaffordable spell that costs no more than the threshold proves it.
-- Returns true (definitely below), false (not shown to be below), or nil
-- when this cannot be worked out. The second value is the highest share of
-- maximum mana this method can detect (the dearest spell under the threshold).
function ME.ManaBelow(fraction)
	local max = Plain(UnitPowerMax("player", 0))
	if not max or max <= 0 then return nil end
	local limit, best, any = fraction * max, 0, false
	for key in pairs(ME.Spells.DEFS) do
		local id = ME.Spell(key)
		local cost = id and manaCost(key)
		if cost and cost > 0 then
			any = true
			if cost <= limit then
				if cost > best then best = cost end
				local _, noMana = C_Spell.IsSpellUsable(id)
				if Bool(noMana) then return true, cost / max end
			end
		end
	end
	if not any or best == 0 then return nil end
	return false, best / max
end

-- Clearcasting: the next damage spell is free, so every nuke costs 0.
local function clearcastByCost()
	local key = ME.FirstKnown("Frostbolt", "Fireball")
	local c = key and manaCost(key)
	return c ~= nil and c == 0
end

local pyroBase = 0
-- Heating Up stacks from Pyroblast's cast time (each stack removes 25%).
local function heatingUpByCastTime()
	if ME.Remembered("PoM") then return nil end
	local ct = castTime("Pyroblast")
	if not ct or ct <= 0 then return nil end
	if ct > pyroBase then pyroBase = ct end
	if pyroBase <= 0 then return nil end
	return math.floor((1 - ct / pyroBase) * 4 + 0.5)
end

local abBase
-- Arcane Blast stacks from its mana cost (+100% per stack).
local function arcaneBlastByCost()
	local c = manaCost("ArcaneBlast")
	if not c or c <= 0 then return nil end
	if ME.Remembered("ArcanePower") then c = c / 1.3 end
	if not abBase or c < abBase then abBase = c end
	return math.max(0, math.min(4, math.floor(c / abBase + 0.5) - 1))
end

-- Talents that make each proc possible (Forever 1.60.1 data).
local PROC_TALENT = { Clearcasting = 11213, MissileBarrage = 400588, FingersOfFrost = 400647, HeatingUp = 400624 }

function ME.Proc(name)
	local talent = PROC_TALENT[name]
	if talent and ME.TalentRank(talent, 1) == 0 then return false end
	if name == "Clearcasting" then
		return ME.HasBuff("Clearcasting") == true or clearcastByCost()
	elseif name == "MissileBarrage" then
		if S.overlay.ArcaneMissiles or ME.HasBuff("MissileBarrage") == true then return true end
		-- Free Arcane Missiles while other spells still cost mana.
		local c = manaCost("ArcaneMissiles")
		return c ~= nil and c == 0 and not clearcastByCost()
	elseif name == "FingersOfFrost" then
		return S.overlay.IceLance or ME.HasBuff("FingersOfFrost") == true
	elseif name == "HeatingUp" then
		return ME.HeatingUpStacks() >= 3
	elseif name == "Frozen" then
		return S.frozenHits > 0 and now() < S.frozenExpire
	end
	return false
end

function ME.ArcaneBlastStacks()
	local byCost = arcaneBlastByCost()
	if byCost then return byCost end
	return now() < S.abExpire and S.abStacks or 0
end

function ME.HeatingUpStacks()
	-- Heating Up is a Fire talent: without it there are no stacks at all.
	if ME.TalentRank(400624, 1) == 0 then return 0 end
	if S.overlay.Pyroblast then return 3 end
	local has, aura = ME.HasBuff("HeatingUp")
	local n = has and stacksOf(aura)
	if n then return n end
	local byCast = heatingUpByCastTime()
	if byCast then return byCast end
	-- Lower bound from Fire Blast casts (crits add more, unseen).
	return now() < S.huExpire and S.huStacks or 0
end

function ME.ScorchStacks()
	return now() < S.scorchExpire and S.scorchStacks or 0
end
function ME.ScorchRemaining()
	return math.max(0, S.scorchExpire - now())
end

-- Winter's Chill: Frostbolts stack it on the target (5 max, 15 s) and the
-- next Cone of Cold spends it.
function ME.WintersChill()
	return now() < S.wcExpire and S.wcStacks or 0
end

---------------------------------------------------------------------------
-- Polymorph, wand, mana gem
---------------------------------------------------------------------------
local SHEEP_SECONDS = { [118] = 20, [12824] = 30, [12825] = 40, [12826] = 50 }

-- Seconds left on the player's last Polymorph. The debuff itself is hidden,
-- so this is a timer from the cast, ended early when a break is detected
-- (see the sheep tracking below).
function ME.SheepRemaining()
	return math.max(0, S.sheepStart + S.sheepDur - now())
end

-- Sheep tracking. The sheeped enemy is followed by its nameplate unit, and
-- the timer is ended as soon as any of these is seen:
--   * you land a damaging spell while targeting it,
--   * it starts casting,
--   * it picks a target again (a polymorphed enemy has none),
--   * it dies or its nameplate goes away.
local function endSheep(broke, why)
	if S.sheepDur == 0 then return end
	S.sheepStart, S.sheepDur, S.sheepUnit, S.sheepSignal = 0, 0, nil, nil
	if broke then
		S.sheepBrokeAt = now()
		S.sheepBrokeWhy = why
		ME:Fire("SHEEP_BROKE", why)
	else
		ME:Fire("SHEEP_ENDED")
	end
end
ME.EndSheep = endSheep

local function nameplateFor(token)
	if not Bool(UnitExists(token)) then return nil end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if Bool(UnitExists(unit)) and Bool(UnitIsUnit(unit, token)) then return unit end
	end
end

local function sheepAlive(unit)
	return unit and Bool(UnitExists(unit)) and not Bool(UnitIsDead(unit))
end

-- Set by the re-sheep button just before it casts (see SheepButton.lua).
ME.resheepClickAt, ME.resheepMode = 0, nil

local function startSheep(duration)
	local t = now()
	local unit
	if t - ME.resheepClickAt < 1.5 then
		-- Cast from the re-sheep button: it went to the focus, or to the
		-- enemy that was sheeped before.
		if ME.resheepMode == "focus" then unit = nameplateFor("focus") end
		if not unit and sheepAlive(S.lastSheepUnit) then unit = S.lastSheepUnit end
	end
	-- Otherwise the enemy targeted when the cast began.
	unit = unit or S.castTargetPlate or nameplateFor("target")
	S.sheepStart, S.sheepDur = t, duration
	S.sheepUnit, S.lastSheepUnit = unit, unit
	S.sheepSignal, S.sheepCalibrateAt, S.sheepTargetSince = nil, t + 1, nil
	ME:Fire("SHEEP", duration)
end

local function watchSheep()
	local unit = S.sheepUnit
	if not unit or S.sheepDur == 0 then return end
	if now() >= S.sheepStart + S.sheepDur then return end
	if not Bool(UnitExists(unit)) or Bool(UnitIsDead(unit)) then
		endSheep(false)
		return
	end
	local hasTarget = Bool(UnitExists(unit .. "target"))
	if S.sheepSignal == nil then
		-- One second after the cast: a sheeped enemy should have no target.
		-- If it still shows one, this signal cannot be trusted for this sheep.
		if now() >= S.sheepCalibrateAt then S.sheepSignal = not hasTarget end
	elseif S.sheepSignal and hasTarget then
		-- Must hold for a full second: a flicker is not a broken sheep.
		S.sheepTargetSince = S.sheepTargetSince or now()
		if now() - S.sheepTargetSince >= 1.0 then endSheep(true, "it is attacking again") end
	else
		S.sheepTargetSince = nil
	end
end

local rangedSlot
function ME.HasWand()
	if rangedSlot == nil then
		rangedSlot = (GetInventorySlotInfo and Try(GetInventorySlotInfo, "RANGEDSLOT")) or 18
	end
	return GetInventoryItemID("player", rangedSlot) ~= nil
end

-- Is the target a spellcaster? Its power type is readable: casters use
-- mana. A cast seen from it this fight also counts.
function ME.TargetIsCaster()
	if not S.hasTarget then return false end
	if S.targetIsCaster then return true end
	local pType = Plain(Try(UnitPowerType, "target"))
	return pType == 0
end

local HEALERS = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
-- A healing class in the group (Amplify Magic boosts their heals on you).
function ME.HealerInGroup()
	if not (IsInGroup and IsInGroup()) then return false end
	local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
	for i = 1, (GetNumGroupMembers() or 0) do
		local _, class = UnitClass(prefix .. i)
		if HEALERS[Plain(class)] then return true end
	end
	return false
end

-- Cannibalize needs a humanoid or undead corpse within 5 yards. Returns
-- true / false, or nil when the corpse type is hidden from addons.
local CANNIBAL_TYPES = { [6] = true, [7] = true } -- creature type IDs: Undead, Humanoid
function ME.CannibalizeCorpse()
	if not (Bool(UnitExists("target")) and Bool(UnitIsDead("target"))) then return false end
	local hidden = false
	if not Bool(UnitIsPlayer("target")) then -- player corpses always qualify
		local _, typeID = Try(UnitCreatureType, "target")
		typeID = Plain(typeID)
		if typeID ~= nil and not CANNIBAL_TYPES[typeID] then return false end
		hidden = (typeID == nil)
		S.corpseTypeHidden = hidden
	end
	-- Range: the spell's own check if it answers, otherwise the ~10 yard check.
	local id = ME.Spell("Cannibalize")
	local r = id and Plain(Try(C_Spell.IsSpellInRange, id, "target"))
	if r == nil then r = Plain(Try(CheckInteractDistance, "target", 3)) end
	if r == false then return false end
	if hidden then return nil end
	return true
end

local GEMS = { 8008, 8007, 5513, 5514 } -- Mana Ruby, Citrine, Jade, Agate
-- Best mana gem in the bags that is off cooldown, as an "item:<id>" key.
function ME.ReadyManaGem()
	if not (C_Item and C_Item.GetItemCount) then return nil end
	for _, id in ipairs(GEMS) do
		local n = Plain(Try(C_Item.GetItemCount, id), 0) or 0
		if n > 0 then
			local start, dur = Try(C_Item.GetItemCooldown, id)
			start, dur = Plain(start), Plain(dur)
			-- Unreadable cooldown: assume ready rather than hide the option.
			if not (start and dur and dur > 1.6 and start + dur > now()) then
				return "item:" .. id
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- World scan (target, enemy count, threat, movement)
---------------------------------------------------------------------------
local function hostile(unit)
	return Bool(UnitExists(unit)) and Bool(UnitCanAttack("player", unit)) and not Bool(UnitIsDead(unit))
end

local WATCHED = { "MissileBarrage", "Clearcasting", "FingersOfFrost", "HeatingUp" }
local procState = {}

local lastScan = 0
function State:Refresh(force)
	local t = now()
	if not force and t - lastScan < 0.2 then return end
	lastScan = t

	S.inCombat = Bool(UnitAffectingCombat("player"))
	S.hasTarget = hostile("target")
	S.moving = (Plain(GetUnitSpeed("player"), 0) or 0) > 0

	if S.hasTarget then
		local c = Plain(UnitClassification("target"), "normal")
		S.targetElite = (c == "elite" or c == "worldboss" or c == "rareelite")
		local threat = Plain(Try(UnitThreatSituation, "player", "target"))
		S.aggro = threat ~= nil and threat >= 2
	else
		S.targetElite, S.aggro = false, false
	end

	-- Enemies = hostile nameplates that are in combat (the target counts once).
	local n, targetCounted = 0, false
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if hostile(unit) and Bool(UnitAffectingCombat(unit)) then
			n = n + 1
			if Bool(UnitIsUnit(unit, "target")) then targetCounted = true end
		end
	end
	if S.hasTarget and not targetCounted and (n == 0 or S.inCombat) then
		n = math.max(n, 1)
	end
	if n >= 2 and S.enemies < 2 then S.addsAt = t end -- a second enemy just joined
	watchSheep()
	S.enemies = n

	-- Announce procs as they appear (drives the banners).
	for i = 1, #WATCHED do
		local name = WATCHED[i]
		local on = ME.Proc(name) and true or false
		if on ~= (procState[name] or false) then
			procState[name] = on
			ME:Fire("PROC", name, on)
		end
	end
end

---------------------------------------------------------------------------
-- Cast tracking
---------------------------------------------------------------------------
local DAMAGE = {
	Fireball = true, Frostbolt = true, FrostfireBolt = true, ArcaneBlast = true, ArcaneWrath = true,
	Pyroblast = true, Scorch = true, FireBlast = true, IceLance = true, ConeOfCold = true,
	ArcaneExplosion = true, BlastWave = true, Flamestrike = true,
}
-- Spells that damage only the current target (used to spot a broken sheep).
local SINGLE_TARGET = { Fireball = true, Frostbolt = true, FrostfireBolt = true, ArcaneBlast = true,
	ArcaneWrath = true, Pyroblast = true, Scorch = true, FireBlast = true, IceLance = true,
	ArcaneMissiles = true, Shoot = true }
local CAST_TIME = { Fireball = true, Frostbolt = true, FrostfireBolt = true, ArcaneBlast = true,
	ArcaneWrath = true, Pyroblast = true, Scorch = true, Flamestrike = true, Polymorph = true }

local BUFF_MEMORY = {
	ArcaneIntellect = { "Intellect", 3600 }, ArcaneBrilliance = { "Intellect", 3600 },
	FrostArmor = { "Armor", 1800 }, IceArmor = { "Armor", 1800 }, MageArmor = { "Armor", 1800 },
	IceBarrier = { "IceBarrier", 60 }, ManaShield = { "ManaShield", 60 },
	ArcanePower = { "ArcanePower", 15 },
	-- Presence of Mind has no duration: it lasts until the next cast-time spell.
	PresenceOfMind = { "PoM", 600 }, Evocation = { "Evocation", 8 },
	DampenMagic = { "Dampen", 600 }, AmplifyMagic = { "Amplify", 600 },
}

local function onPlayerCast(key)
	local t = now()
	S.lastCast, S.lastCastTime = key, t

	local b = BUFF_MEMORY[key]
	if b then ME.Remember(b[1], b[2]) end
	-- Dampen and Amplify Magic replace each other.
	if key == "DampenMagic" then ME.Forget("Amplify") elseif key == "AmplifyMagic" then ME.Forget("Dampen") end

	if key:find("^Polymorph") then
		local id = ME.Spell(key)
		startSheep((id and SHEEP_SECONDS[id]) or 50)
	elseif SINGLE_TARGET[key] and S.sheepUnit and S.sheepDur > 0 then
		-- Any damage breaks Polymorph. What counts is the target when the cast
		-- began (you may have tabbed away mid-cast); instants use the target now.
		local onSheep
		if S.castStartKey == key and now() - S.castStartAt < 10 then
			onSheep = S.castOnSheep
		else
			onSheep = Bool(UnitIsUnit("target", S.sheepUnit))
		end
		if onSheep then endSheep(true, "you hit it") end
	end
	S.castStartKey = nil
	if key == "FrostNova" then
		-- Frost Nova reaches about 10 yards; a target further away is not frozen.
		local near = S.hasTarget and Plain(Try(CheckInteractDistance, "target", 3))
		if near == nil and S.hasTarget then near = S.aggro end
		if near then
			-- Damage can break the root, so allow a single shatter spell.
			S.frozenExpire, S.frozenHits = t + 8, 1
			ME:Fire("MEM_PROC", "Frozen")
		else
			S.frozenHits = 0
		end
	elseif DAMAGE[key] and S.frozenHits > 0 then
		-- Damage breaks the root: allow a couple of shatter casts, then stop.
		S.frozenHits = S.frozenHits - 1
	end

	if key == "ArcaneBlast" then
		-- The buff lasts 18 s from its first application and is not refreshed.
		local live = t < S.abExpire and S.abStacks or 0
		if live == 0 then S.abExpire = t + 18 end
		S.abStacks = math.min(4, live + 1)
		if S.abStacks == 4 then ME:Fire("MEM_PROC", "ArcaneBlast4") end
	end
	if key == "FireBlast" then
		local before = t < S.huExpire and S.huStacks or 0
		S.huStacks = math.min(3, before + 1)
		S.huExpire = t + 20
	elseif key == "Pyroblast" then
		S.huStacks = 0
	end
	if key == "Frostbolt" then
		S.wcStacks = math.min(5, ME.WintersChill() + 1)
		S.wcExpire = t + 15
	elseif key == "ConeOfCold" then
		S.wcStacks = 0
	end
	if key == "Scorch" then
		S.scorchStacks = math.min(5, ME.ScorchStacks() + 1)
		S.scorchExpire = t + 30
	end
	if CAST_TIME[key] and ME.Remembered("PoM") and key ~= "PresenceOfMind" then
		ME.Forget("PoM")
	end
	ME:Fire("PLAYER_CAST", key)
end

function State:OnLogin()
	ME:On("PLAYER_REGEN_DISABLED", function()
		S.inCombat = true
		ME:Fire("COMBAT", true)
	end)
	ME:On("PLAYER_REGEN_ENABLED", function()
		S.inCombat = false
		S.targetCasting, S.focusCasting = false, false
		ME:Fire("COMBAT", false)
	end)

	ME:On("PLAYER_TARGET_CHANGED", function()
		S.targetCasting, S.targetIsCaster = false, false
		S.scorchStacks, S.wcStacks, S.frozenHits = 0, 0, 0
		State:Refresh(true)
		ME:Fire("TARGET")
	end)

	ME:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
		if unit == "player" then
			local key = ME.KeyForSpell(spellID)
			seen.casts = seen.casts + 1
			if key then
				onPlayerCast(key)
			elseif not issecret(spellID) then
				-- Casts the addon has no entry for (shown by /mage diag).
				local name = ME.Spells.SpellName(spellID) or "?"
				seen.unknown[name .. " (" .. tostring(spellID) .. ")"] = true
			end
			if not S.channeling then S.casting = nil end
		elseif unit == "target" then
			S.targetCasting = false
		elseif unit == "focus" then
			S.focusCasting = false
		end
	end)
	ME:On("UNIT_SPELLCAST_START", function(unit, _, spellID)
		if unit == S.sheepUnit and unit ~= nil then
			endSheep(true, "it started casting")
		end
		if unit == "player" then
			S.casting = ME.KeyForSpell(spellID) or "?"
			-- Remember what was targeted as the cast began.
			S.castStartKey, S.castStartAt = S.casting, now()
			S.castOnSheep = S.sheepUnit ~= nil and Bool(UnitIsUnit("target", S.sheepUnit))
			S.castTargetPlate = (S.casting:find("^Polymorph")) and nameplateFor("target") or nil
		elseif unit == "target" then
			S.targetCasting = true
			S.targetIsCaster = true
			seen.targetCasts = seen.targetCasts + 1
		elseif unit == "focus" then
			S.focusCasting = true
			seen.focusCasts = seen.focusCasts + 1
		end
	end)
	ME:On("UNIT_AURA", function(unit)
		if unit ~= "player" then return end
		seen.auraEvents = seen.auraEvents + 1
		-- Out of combat buffs are readable: carry Dampen / Amplify into the
		-- next fight (where they are hidden) as remembered timers.
		for key, mem in pairs({ DampenMagic = "Dampen", AmplifyMagic = "Amplify" }) do
			local has, aura = ME.HasBuff(key)
			if has == true then
				local left = aura and Plain(aura.expirationTime)
				left = (left and left > 0) and (left - now()) or 600
				ME.Remember(mem, math.max(1, left))
			elseif has == false then
				ME.Forget(mem)
			end
		end
	end)
	ME:On("PLAYER_FOCUS_CHANGED", function() S.focusCasting = false end)
	-- The sheep's nameplate went away: it died or is out of sight.
	ME:On("NAME_PLATE_UNIT_REMOVED", function(unit)
		if unit ~= nil and unit == S.sheepUnit then endSheep(false) end
	end)
	ME:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
		if unit == "player" then
			S.channeling = ME.KeyForSpell(spellID) or "?"
			S.casting = S.channeling
			S.castStartKey, S.castStartAt = S.channeling, now()
			S.castOnSheep = S.sheepUnit ~= nil and Bool(UnitIsUnit("target", S.sheepUnit))
		elseif unit == "target" then
			S.targetCasting = true
		elseif unit == "focus" then
			S.focusCasting = true
		end
	end)
	local function stop(unit)
		if unit == "player" then
			S.casting, S.channeling = nil, nil
		elseif unit == "target" then
			S.targetCasting = false
		elseif unit == "focus" then
			S.focusCasting = false
		end
	end
	for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
		"UNIT_SPELLCAST_CHANNEL_STOP" }) do
		ME:On(e, stop)
	end

	-- Proc glows: Blizzard tells the UI which button to light up; that event
	-- carries a plain spell ID and is the most reliable proc signal in combat.
	ME:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(spellID)
		seen.glows = seen.glows + 1
		local key = ME.KeyForSpell(spellID)
		if key and not S.overlay[key] then
			S.overlay[key] = true
			ME:Fire("OVERLAY", key, true)
		end
	end)
	ME:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(spellID)
		local key = ME.KeyForSpell(spellID)
		if key and S.overlay[key] then
			S.overlay[key] = nil
			ME:Fire("OVERLAY", key, false)
		end
	end)
	ME:On("PLAYER_DEAD", function()
		wipe(S.overlay)
		S.abStacks, S.huStacks, S.scorchStacks, S.frozenHits, S.wcStacks = 0, 0, 0, 0, 0
		for k in pairs(mem) do mem[k] = nil end
	end)

	-- Baselines for the cost / cast-time readings change with level and rank.
	ME:Listen("SPELLS_UPDATED", function() abBase, pyroBase = nil, 0 end)

	self:Refresh(true)
	-- Keep state (and proc banners) current even when the HUD is hidden.
	C_Timer.NewTicker(0.2, function()
		local ok, err = pcall(State.Refresh, State)
		if not ok then ME:Error("State", err) end
	end)
end
