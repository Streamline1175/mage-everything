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

-- Fire Blast and Ice Lance share one 8 s cooldown, so only ever queue one.
local function quickInstant(reason, preferLance)
	local first, second = "FireBlast", "IceLance"
	if preferLance then first, second = second, first end
	if not add(first, reason) then add(second, reason) end
end

local function movingInstants()
	if not S.moving then return end
	local frozen = ME.Proc("FingersOfFrost") or ME.Proc("Frozen")
	if frozen then
		add("IceLance", "Moving - shatter", true)
	end
	quickInstant("Moving - instant", ME.spec == "FROST")
	if S.aggro then add("ConeOfCold", "Moving - cone") end
	if aoe() then add("ArcaneExplosion", "Moving - AoE") end
end

local function justCast(key, within)
	return S.casting == key or (S.lastCast == key and GetTime() - S.lastCastTime < (within or 2))
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
		-- Two charges: Frostbolt first, Ice Lance right behind it, so both
		-- hit a "frozen" target. Lance straight away only when moving.
		if S.moving or justCast("Frostbolt") then
			add("IceLance", "Fingers of Frost", true)
		else
			add("Frostbolt", "Fingers of Frost - then Ice Lance", true)
			add("IceLance", "Fingers of Frost", true)
		end
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
	-- Winter's Chill (deep Frost) makes Cone of Cold worth it on one target.
	local chill = ME.TalentRank(11180, (ME.specPoints.FROST or 0) >= 26 and 1 or 0) -- Winter's Chill
	if chill > 0 and ME.WintersChill() >= 5 and S.aggro then
		add("ConeOfCold", "Winter's Chill x5")
	end
	if ME.Proc("MissileBarrage") and not S.moving then
		add("ArcaneMissiles", "Missile Barrage", true)
	end
	movingInstants()
	if not ME.Known("IceLance") then
		-- Before Ice Lance exists, Fire Blast is simply free instant damage.
		add("FireBlast", "Instant damage")
	elseif S.inCombat and ME.db.hud.frostInstant and not ME.Proc("Frozen") then
		-- Ice Lance and Fire Blast share an 8 s cooldown. Keep it for the
		-- shatter window while Frost Nova is available; once Nova is on
		-- cooldown (or not learned) there is no window coming, so spend it.
		-- Fire Blast hits harder than Ice Lance on a target that is not frozen.
		if not ME.Known("FrostNova") or ME.OnCooldown("FrostNova") then
			if S.aggro then
				quickInstant("Enemy on you - instant", false)
			else
				quickInstant("Instant damage", false)
			end
		end
	end
	fillerOrWand("Frostbolt", "Filler")
	if not ME.Known("Frostbolt") then fillerOrWand("Fireball", "Filler") end
end

---------------------------------------------------------------------------
-- Fire
---------------------------------------------------------------------------
local function fire()
	local filler = "Fireball"
	if ME.Known("FrostfireBolt") and not ME.db.hud.fireballFiller then filler = "FrostfireBolt" end
	if not S.inCombat then
		situation = "OPENER"
		if not add("Pyroblast", "Opener - long cast", false, true) then
			add(filler, "Opener")
		end
	end
	-- Three stacks make Pyroblast a 1.5 s cast (not an instant).
	if ME.Proc("HeatingUp") and not S.moving then
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
	-- Fire Vulnerability on targets that live long enough: build to 5, then
	-- refresh before it runs out.
	-- (only with Improved Scorch, which is what applies the debuff)
	if S.targetElite and S.inCombat and not S.moving and ME.TalentRank(11095, 1) > 0 then
		local n = ME.ScorchStacks()
		if n < 5 then
			add("Scorch", ("Fire Vulnerability %d/5"):format(n))
		elseif ME.ScorchRemaining() < 6 then
			add("Scorch", "Refresh Fire Vulnerability")
		end
	end
	if S.inCombat then
		local n = ME.HeatingUpStacks()
		add("FireBlast", n >= 2 and "Heating Up -> 3" or "Build Heating Up")
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
	local stacks = ME.ArcaneBlastStacks()
	if not S.inCombat then
		situation = "OPENER"
		if not add("ArcaneWrath", "Opener", false, true) then add(filler, "Opener") end
	end
	if not S.moving then
		if ME.Proc("MissileBarrage") then
			situation = "PROC"
			add("ArcaneMissiles", "Missile Barrage", true)
		elseif ME.Proc("Clearcasting") then
			-- Spend the free cast on the most expensive spell available.
			situation = "PROC"
			if not add("ArcaneWrath", "Clearcasting - free", true) then
				if stacks >= 2 then
					add("ArcaneBlast", "Clearcasting - free", true)
				else
					add("ArcaneMissiles", "Clearcasting - free", true)
				end
			end
		end
	end
	if aoe() then
		situation = "AOE x" .. S.enemies
		add("ArcaneExplosion", "AoE - point blank")
		add("ConeOfCold", "AoE - cone")
		if not S.moving then add("Blizzard", "AoE - channel") end
	end
	local burning = false
	if bigFight() then
		if add("ArcanePower", "Burst") then situation = "BURST" end
		burning = ME.Remembered("ArcanePower") or S.targetElite
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
		-- Each stack doubles Blast's cost: outside burst, stop at 3 and let
		-- the buff fall off (it lasts 18 s from the first cast).
		if stacks >= 3 and not burning and not S.moving then
			add("ArcaneMissiles", "Let Arcane Blast drop")
			add(ME.FirstKnown("Frostbolt", "Fireball"), "Let Arcane Blast drop")
		end
		fillerOrWand("ArcaneBlast", ("Arcane Blast %d/4"):format(stacks))
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
local function barrierDown()
	return not ME.Remembered("IceBarrier") and ME.HasBuff("IceBarrier") ~= true and ME.Ready("IceBarrier")
end

local function reaction()
	local r = ME.db.reaction
	if not r.enabled or not S.hasTarget then return nil end
	if r.counterspell and S.targetCasting and ME.Ready("Counterspell") then
		return { key = "Counterspell", reason = "Interrupt!", glow = true }
	end
	-- A casting focus: Counterspell needs a focus macro to reach it.
	if r.counterspell and S.focusCasting and ME.Ready("Counterspell")
		and ME.Bool(UnitExists("focus")) and ME.Bool(UnitCanAttack("player", "focus")) then
		return { key = "Counterspell", reason = "Interrupt your FOCUS", glow = true }
	end
	-- Dampen / Amplify Magic before the pull, chosen by the target.
	if not S.inCombat and r.magicWard then
		local ward = ME.MagicWardAdvice()
		if ward then return ward end
	end
	-- Ice Barrier also raises Frost damage, so keep it up from before the pull.
	if r.shields and barrierDown() and (S.inCombat or ME.spec == "FROST") then
		return { key = "IceBarrier", reason = ME.spec == "FROST" and "Shield + Frost damage" or "Shield" }
	end
	if not S.inCombat then return nil end
	if r.nova and S.aggro and not ME.Proc("Frozen") and ME.Ready("FrostNova")
		and (ME.spec == "FROST" or S.enemies >= 2 or S.targetElite) then
		return { key = "FrostNova", reason = "Root, then step back" }
	end
	if r.shields and S.aggro and (S.targetElite or S.enemies >= 3) and not ME.Known("IceBarrier")
		and not ME.Remembered("ManaShield") and ME.HasBuff("ManaShield") ~= true and ME.Ready("ManaShield") then
		return { key = "ManaShield", reason = "Shield" }
	end
	-- Fighting a caster without Dampen Magic.
	if r.magicWard then
		local ward = ME.MagicWardAdvice()
		if ward and ward.key == "DampenMagic" then return ward end
	end
	-- Cold Snap: a hard fight with Frost Nova and Ice Barrier both spent.
	if r.shields and S.aggro and (S.targetElite or S.enemies >= 2) and ME.Ready("ColdSnap")
		and ME.OnCooldown("FrostNova") and (not ME.Known("IceBarrier") or ME.OnCooldown("IceBarrier")) then
		return { key = "ColdSnap", reason = "Reset Frost cooldowns" }
	end
	-- Polymorph: re-sheep before the timer runs out, or sheep the add in the
	-- first seconds after a second enemy joins.
	if r.polymorph and ME.Ready("Polymorph") and not S.moving then
		local left = ME.SheepRemaining()
		if left == 0 and S.enemies >= 2 and GetTime() - S.sheepBrokeAt < 6 then
			return { key = "Polymorph", reason = "Sheep broke - click the Sheep button", glow = true }
		end
		if left > 0 and left < 6 and S.enemies >= 2 then
			return { key = "Polymorph", reason = ("Re-sheep (%ds left)"):format(math.ceil(left)) }
		end
		if left == 0 and S.enemies >= 2 and S.enemies <= 3 and GetTime() - S.addsAt < 8 then
			return { key = "Polymorph", reason = "Sheep the add (not your target)" }
		end
	end
	if oom then
		if r.gem then
			local gem = ME.ReadyManaGem()
			if gem then return { key = gem, reason = "Out of mana - use gem" } end
		end
		if r.evocation and ME.Ready("Evocation") then
			return { key = "Evocation", reason = "Out of mana" }
		end
	end
	return nil
end

-- Dampen Magic lowers magic damage taken (and healing received); Amplify
-- Magic raises both. Solo, Dampen is the one that helps, against casters.
-- In a group with a healer, Amplify helps against enemies that do not cast.
-- What Dampen / Amplify Magic should be on you for the current target:
--   want: "DampenMagic", "AmplifyMagic" or nil (neither helps)
--   have: the one that is up, or nil
--   reason: short explanation
function ME.MagicWardState()
	if not S.hasTarget or not (ME.Known("DampenMagic") or ME.Known("AmplifyMagic")) then return nil end
	local dampen = ME.Remembered("Dampen") or ME.HasBuff("DampenMagic") == true
	local amplify = ME.Remembered("Amplify") or ME.HasBuff("AmplifyMagic") == true
	local st = { have = (dampen and "DampenMagic") or (amplify and "AmplifyMagic") or nil }
	if ME.TargetIsCaster() then
		st.want, st.reason = "DampenMagic", amplify and "Caster - swap Amplify for Dampen" or "Caster - less spell damage"
	elseif ME.HealerInGroup() then
		st.want, st.reason = "AmplifyMagic", "Melee enemy - stronger heals on you"
	else
		st.reason = "Melee enemy - no ward needed solo"
	end
	if st.want and not ME.Known(st.want) then st.want = nil end
	return st
end

-- A suggestion when the wanted ward is missing (nil otherwise).
function ME.MagicWardAdvice()
	local st = ME.MagicWardState()
	if not st or not st.want or st.have == st.want then return nil end
	if st.want == "AmplifyMagic" and st.have then return nil end -- keep an existing Dampen
	if not ME.Ready(st.want) then return nil end
	return { key = st.want, reason = st.reason }
end

-- Best emergency button for the low-health alert (shown via a health curve).
local function panic()
	if ME.Ready("IceBarrier") and not ME.Remembered("IceBarrier") then return "IceBarrier" end
	if ME.Ready("IceBlock") then return "IceBlock" end
	if ME.OnCooldown("IceBlock") and ME.Ready("ColdSnap") then return "ColdSnap" end
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
