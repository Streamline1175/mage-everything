-- MageEverything: priority engine.
--
-- Produces, several times a second:
--   * a main queue (best spell now + the next two),
--   * a "reaction" (interrupt / root / shield / mana recovery) shown beside it,
--   * the best emergency defensive for the low-health alert.
-- Each tree has its own priority list; below level 10 (no talents) a simple
-- leveling list is used. All conditions use combat-readable data (see State).
local _, ME = ...
local Rotation = ME:NewModule("Rotation")
local S = ME.state

local out, oom, situation

local function add(key, reason, glow, once)
	if #out >= 3 or not key or not ME.Known(key) then return false end
	for i = 1, #out do
		if out[i].key == key then return false end
	end
	local ready, why = ME.Ready(key)
	if not ready then
		if why == "mana" then oom = true end
		return false
	end
	if once and S.casting == key then return false end
	out[#out + 1] = { key = key, reason = reason, glow = glow }
	return true
end

local function aoe()
	return S.enemies >= (ME.db.hud.aoeThreshold or 3)
end

-- Worth spending a long cooldown: elites, or several enemies at once.
local function bigFight()
	return S.inCombat and (S.targetElite or S.enemies >= 2)
end

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------
local function fillerOrWand(filler, reason)
	local before = oom
	oom = false
	local ok = add(filler, reason)
	local fillerOOM = oom
	oom = before or oom
	if not ok and fillerOOM and ME.db.hud.useWand then
		add("Shoot", "Out of mana - wand")
	end
	return ok
end

local function movingInstants()
	if not S.moving then return end
	if ME.Proc("FingersOfFrost") or ME.Proc("Frozen") then add("IceLance", "Moving - shatter", true) end
	add("FireBlast", "Moving - instant")
	add("IceLance", "Moving - instant")
	if S.aggro then add("ConeOfCold", "Moving - cone") end
	if aoe() then add("ArcaneExplosion", "Moving - AoE") end
end

---------------------------------------------------------------------------
-- Frost
---------------------------------------------------------------------------
local function frost()
	if not S.inCombat then
		situation = "OPENER"
		add("Frostbolt", "Open at max range")
	end
	if ME.Proc("FingersOfFrost") then
		situation = "SHATTER"
		add("IceLance", "Fingers of Frost", true)
	end
	if ME.Proc("Frozen") then
		situation = "SHATTER"
		if not add("IceLance", "Frozen - shatter", true) then
			if not S.moving then add("Frostbolt", "Frozen - shatter crit", true) end
		end
	end
	if aoe() then
		situation = "AOE x" .. S.enemies
		add("ConeOfCold", "AoE - cone")
		if not S.moving then add("Blizzard", "AoE - channel") end
		add("ArcaneExplosion", "AoE - point blank")
	end
	if ME.Proc("MissileBarrage") and not S.moving then
		add("ArcaneMissiles", "Missile Barrage", true)
	end
	movingInstants()
	-- Ice Lance and Fire Blast share a cooldown: before Ice Lance exists,
	-- Fire Blast is simply free instant damage.
	if not ME.Known("IceLance") then add("FireBlast", "Instant damage") end
	fillerOrWand("Frostbolt", "Filler")
	if not ME.Known("Frostbolt") then fillerOrWand("Fireball", "Filler") end
end

---------------------------------------------------------------------------
-- Fire
---------------------------------------------------------------------------
local function fire()
	local filler = ME.Known("FrostfireBolt") and "FrostfireBolt" or "Fireball"
	if not S.inCombat then
		situation = "OPENER"
		if not add("Pyroblast", "Opener - long cast", false, true) then
			add(filler, "Opener")
		end
	end
	if ME.Proc("HeatingUp") then
		situation = "PROC"
		add("Pyroblast", "Heating Up x3", true)
	end
	if aoe() then
		situation = "AOE x" .. S.enemies
		if not S.moving then add("Flamestrike", "AoE") end
		add("BlastWave", "AoE - point blank")
		add("ConeOfCold", "AoE - cone")
		add("ArcaneExplosion", "AoE - point blank")
	end
	if ME.Proc("MissileBarrage") and not S.moving then
		add("ArcaneMissiles", "Missile Barrage", true)
	end
	if bigFight() then
		if add("Combustion", "Burst") then situation = "BURST" end
	end
	if S.inCombat then
		local n = ME.HeatingUpStacks()
		add("FireBlast", n >= 2 and "Heating Up -> 3" or "Build Heating Up")
	end
	if S.targetElite and not S.moving and ME.ScorchStacks() < 5 then
		add("Scorch", ("Fire Vulnerability %d/5"):format(ME.ScorchStacks()))
	end
	movingInstants()
	if S.moving then add("Scorch", "Short cast") end
	fillerOrWand(filler, "Filler")
end

---------------------------------------------------------------------------
-- Arcane
---------------------------------------------------------------------------
local function arcane()
	local filler = ME.FirstKnown("ArcaneBlast", "Frostbolt", "Fireball")
	if not S.inCombat then
		situation = "OPENER"
		if not add("ArcaneWrath", "Opener", false, true) then add(filler, "Opener") end
	end
	if (ME.Proc("MissileBarrage") or ME.Proc("Clearcasting")) and not S.moving then
		situation = "PROC"
		add("ArcaneMissiles", ME.Proc("MissileBarrage") and "Missile Barrage" or "Clearcasting - free", true)
	end
	if aoe() then
		situation = "AOE x" .. S.enemies
		add("ArcaneExplosion", "AoE - point blank")
		add("ConeOfCold", "AoE - cone")
		if not S.moving then add("Blizzard", "AoE - channel") end
	end
	if bigFight() then
		if add("ArcanePower", "Burst") then situation = "BURST" end
	end
	if ME.Remembered("PoM") then
		if not add("ArcaneWrath", "Presence of Mind - instant", true) then
			add("Pyroblast", "Presence of Mind - instant", true)
		end
	elseif S.inCombat and (ME.Ready("ArcaneWrath") or ME.Ready("Pyroblast")) then
		add("PresenceOfMind", "Instant next cast")
	end
	if not S.moving then add("ArcaneWrath", "On cooldown") end
	movingInstants()
	if filler == "ArcaneBlast" then
		local n = ME.ArcaneBlastStacks()
		fillerOrWand("ArcaneBlast", n >= 4 and "Arcane Blast x4" or ("Arcane Blast %d/4"):format(n))
		-- Stacks multiply the mana cost: when Blast is unaffordable, dump with Missiles.
		if oom and not S.moving then add("ArcaneMissiles", "Low mana - cheaper") end
	else
		fillerOrWand(filler, "Filler")
	end
end

---------------------------------------------------------------------------
-- Levels 1-9 (no talents yet)
---------------------------------------------------------------------------
local function apprentice()
	local filler = ME.FirstKnown("Frostbolt", "Fireball")
	if not S.inCombat then
		situation = "OPENER"
		add(filler, "Open at max range")
	end
	if aoe() then
		situation = "AOE x" .. S.enemies
		add("ArcaneExplosion", "AoE - point blank")
	end
	add("FireBlast", "Instant damage")
	movingInstants()
	fillerOrWand(filler, "Filler")
end

local LISTS = { FROST = frost, FIRE = fire, ARCANE = arcane, NONE = apprentice }

---------------------------------------------------------------------------
-- Reactions
---------------------------------------------------------------------------
local function reaction()
	local r = ME.db.reaction
	if not r.enabled or not S.hasTarget then return nil end
	if r.counterspell and S.targetCasting and ME.Ready("Counterspell") then
		return { key = "Counterspell", reason = "Interrupt!", glow = true }
	end
	if not S.inCombat then return nil end
	if r.nova and S.aggro and not ME.Proc("Frozen") and ME.Ready("FrostNova")
		and (ME.spec == "FROST" or S.enemies >= 2 or S.targetElite) then
		return { key = "FrostNova", reason = "Root, then step back" }
	end
	if r.shields then
		if not ME.Remembered("IceBarrier") and ME.HasBuff("IceBarrier") ~= true and ME.Ready("IceBarrier") then
			return { key = "IceBarrier", reason = "Shield" }
		end
		if S.aggro and (S.targetElite or S.enemies >= 3) and not ME.Known("IceBarrier")
			and not ME.Remembered("ManaShield") and ME.HasBuff("ManaShield") ~= true and ME.Ready("ManaShield") then
			return { key = "ManaShield", reason = "Shield" }
		end
	end
	if r.evocation and oom and ME.Ready("Evocation") then
		return { key = "Evocation", reason = "Out of mana" }
	end
	return nil
end

-- Best emergency button for the low-health alert (shown via a health curve).
local function panic()
	if ME.Ready("IceBarrier") and not ME.Remembered("IceBarrier") then return "IceBarrier" end
	if ME.Ready("IceBlock") then return "IceBlock" end
	if ME.Ready("FrostNova") and S.aggro then return "FrostNova" end
	if ME.Ready("ManaShield") and not ME.Remembered("ManaShield") then return "ManaShield" end
	if ME.Ready("Blink") then return "Blink" end
	return ME.FirstKnown("IceBlock", "IceBarrier", "ManaShield", "FrostNova", "Blink")
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------
local result = { queue = {}, reaction = nil, panic = nil, situation = "", oom = false }

function Rotation:Build()
	ME.State:Refresh()
	out, oom, situation = {}, false, S.inCombat and "COMBAT" or ""

	if S.hasTarget then
		-- Never suggest clipping a channel the player has just started.
		if S.channeling and ME.Known(S.channeling) then
			out[1] = { key = S.channeling, reason = "Channelling - don't clip" }
		end

		-- Optional: Blizzard's own assistant, on clients that offer it.
		local used = false
		if ME.db.hud.useBlizzardAssist and C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
			local id = ME.Try(C_AssistedCombat.GetNextCastSpell, false)
			local key = id and ME.KeyForSpell(id)
			if key then
				used = add(key, "Blizzard assistant")
			end
		end
		if not used then
			local list = LISTS[ME.spec] or apprentice
			list()
		end
	end

	result.queue = out
	result.oom = oom
	result.situation = (oom and #out > 0 and out[1].key == "Shoot") and "OOM" or situation
	result.reaction = reaction()
	result.panic = panic()
	return result
end
