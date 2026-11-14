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
	wcStacks = 0, wcExpire = 0, sheepStart = 0, sheepDur = 0, focusCasting = false, addsAt = 0,
}
ME.state = S

local mem = {} -- remembered effect -> expiry time

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

function ME.Proc(name)
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

-- Seconds left on the player's last Polymorph (a timer from the cast: the
-- debuff itself is hidden, so an early break cannot be seen).
function ME.SheepRemaining()
	return math.max(0, S.sheepStart + S.sheepDur - now())
end

local rangedSlot
function ME.HasWand()
	if rangedSlot == nil then
		rangedSlot = (GetInventorySlotInfo and Try(GetInventorySlotInfo, "RANGEDSLOT")) or 18
	end
	return GetInventoryItemID("player", rangedSlot) ~= nil
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
local CAST_TIME = { Fireball = true, Frostbolt = true, FrostfireBolt = true, ArcaneBlast = true,
	ArcaneWrath = true, Pyroblast = true, Scorch = true, Flamestrike = true, Polymorph = true }

local BUFF_MEMORY = {
	ArcaneIntellect = { "Intellect", 3600 }, ArcaneBrilliance = { "Intellect", 3600 },
	FrostArmor = { "Armor", 1800 }, IceArmor = { "Armor", 1800 }, MageArmor = { "Armor", 1800 },
	IceBarrier = { "IceBarrier", 60 }, ManaShield = { "ManaShield", 60 },
	ArcanePower = { "ArcanePower", 15 },
	-- Presence of Mind has no duration: it lasts until the next cast-time spell.
	PresenceOfMind = { "PoM", 600 }, Evocation = { "Evocation", 8 },
}

local function onPlayerCast(key)
	local t = now()
	S.lastCast, S.lastCastTime = key, t

	local b = BUFF_MEMORY[key]
	if b then ME.Remember(b[1], b[2]) end

	if key:find("^Polymorph") then
		local id = ME.Spell(key)
		S.sheepStart, S.sheepDur = t, (id and SHEEP_SECONDS[id]) or 50
		ME:Fire("SHEEP", S.sheepDur)
	end
	if key == "FrostNova" then
		S.frozenExpire, S.frozenHits = t + 8, 2
		ME:Fire("MEM_PROC", "Frozen")
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
		S.targetCasting = false
		S.scorchStacks, S.wcStacks = 0, 0
		State:Refresh(true)
		ME:Fire("TARGET")
	end)

	ME:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
		if unit == "player" then
			local key = ME.KeyForSpell(spellID)
			if key then onPlayerCast(key) end
			if not S.channeling then S.casting = nil end
		elseif unit == "target" then
			S.targetCasting = false
		elseif unit == "focus" then
			S.focusCasting = false
		end
	end)
	ME:On("UNIT_SPELLCAST_START", function(unit, _, spellID)
		if unit == "player" then
			S.casting = ME.KeyForSpell(spellID) or "?"
		elseif unit == "target" then
			S.targetCasting = true
		elseif unit == "focus" then
			S.focusCasting = true
		end
	end)
	ME:On("PLAYER_FOCUS_CHANGED", function() S.focusCasting = false end)
	ME:On("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
		if unit == "player" then
			S.channeling = ME.KeyForSpell(spellID) or "?"
			S.casting = S.channeling
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
