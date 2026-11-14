-- MageEverything: trainer data and reminders.
-- Generated from the Forever 1.60.1.70938 game tables: for each spell, the
-- level and spell ID of every rank sold by the mage trainer.
local _, ME = ...
local Training = ME:NewModule("Training")

-- { name, { level, spellID, level, spellID, ... }, talent = true (ranks need the talent), faction = "Alliance"/"Horde" }
local SPELLS = {
	{ "Arcane Intellect", { 1, 1459, 14, 1460, 28, 1461, 42, 10156, 56, 10157 } },
	{ "Fireball", { 1, 133, 6, 143, 12, 145, 18, 3140, 24, 8400, 30, 8401, 36, 8402, 42, 10148, 48, 10149, 54, 10150, 60, 10151 } },
	{ "Frost Armor", { 1, 168, 10, 7300, 20, 7301 } },
	{ "Conjure Water", { 4, 5504, 10, 5505, 20, 5506, 30, 6127, 40, 10138, 50, 10139, 60, 10140 } },
	{ "Frostbolt", { 4, 116, 8, 205, 14, 837, 20, 7322, 26, 8406, 32, 8407, 38, 8408, 44, 10179, 50, 10180, 56, 10181 } },
	{ "Conjure Food", { 6, 587, 12, 597, 22, 990, 32, 6129, 42, 10144, 52, 10145, 60, 28612 } },
	{ "Fire Blast", { 6, 2136, 14, 2137, 22, 2138, 30, 8412, 38, 8413, 46, 10197, 54, 10199 } },
	{ "Arcane Missiles", { 8, 5143, 16, 5144, 24, 5145, 32, 8416, 40, 8417, 48, 10211, 56, 10212 } },
	{ "Polymorph", { 8, 118, 20, 12824, 40, 12825, 60, 12826 } },
	{ "Frost Nova", { 10, 122, 26, 865, 40, 6131, 54, 10230 } },
	{ "Dampen Magic", { 12, 604, 24, 8450, 36, 8451, 48, 10173, 60, 10174 } },
	{ "Slow Fall", { 12, 130 } },
	{ "Arcane Explosion", { 14, 1449, 22, 8437, 30, 8438, 38, 8439, 46, 10201, 54, 10202 } },
	{ "Flamestrike", { 16, 2120, 24, 2121, 32, 8422, 40, 8423, 48, 10215, 56, 10216 } },
	{ "Amplify Magic", { 18, 1008, 30, 8455, 42, 10169, 54, 10170 } },
	{ "Remove Lesser Curse", { 18, 475 } },
	{ "Arcane Blast", { 20, 400574, 30, 1239696, 40, 1239697, 50, 1239699, 60, 1239700 }, talent = true },
	{ "Blink", { 20, 1953 } },
	{ "Blizzard", { 20, 10, 28, 6141, 36, 8427, 44, 10185, 52, 10186, 60, 10187 } },
	{ "Evocation", { 20, 12051 } },
	{ "Fire Ward", { 20, 543, 30, 8457, 40, 8458, 50, 10223, 60, 10225 } },
	{ "Ice Lance", { 20, 1312002, 28, 400640, 34, 1240044, 42, 1240045, 48, 1240046, 56, 1240047 }, talent = true },
	{ "Mana Shield", { 20, 1463, 28, 8494, 36, 8495, 44, 10191, 52, 10192, 60, 10193 } },
	{ "Pyroblast", { 20, 11366, 24, 12505, 30, 12522, 36, 12523, 42, 12524, 48, 12525, 54, 12526, 60, 18809 }, talent = true },
	{ "Teleport: Ironforge", { 20, 3562 }, faction = "Alliance" },
	{ "Teleport: Orgrimmar", { 20, 3567 }, faction = "Horde" },
	{ "Teleport: Stormwind", { 20, 3561 }, faction = "Alliance" },
	{ "Teleport: Undercity", { 20, 3563 }, faction = "Horde" },
	{ "Frost Ward", { 22, 6143, 32, 8461, 42, 8462, 52, 10177, 60, 28609 } },
	{ "Scorch", { 22, 2948, 28, 8444, 34, 8445, 40, 8446, 46, 10205, 52, 10206, 58, 10207 } },
	{ "Counterspell", { 24, 2139 } },
	{ "Arcane Wrath", { 25, 1326079, 36, 1326080, 48, 1326081, 60, 1326082 }, talent = true },
	{ "Cone of Cold", { 26, 120, 34, 8492, 42, 10159, 50, 10160, 58, 10161 } },
	{ "Conjure Mana Agate", { 28, 759 } },
	{ "Blast Wave", { 30, 11113, 36, 13018, 44, 13019, 52, 13020, 60, 13021 }, talent = true },
	{ "Ice Armor", { 30, 7302, 40, 7320, 50, 10219, 60, 10220 } },
	{ "Teleport: Darnassus", { 30, 3565 }, faction = "Alliance" },
	{ "Teleport: Thunder Bluff", { 30, 3566 }, faction = "Horde" },
	{ "Mage Armor", { 34, 6117, 46, 22782, 58, 22783 } },
	{ "Conjure Mana Jade", { 38, 3552 } },
	{ "Frostfire Bolt", { 40, 401502, 50, 1237312, 60, 1237313 } },
	{ "Ice Barrier", { 40, 11426, 46, 13031, 52, 13032, 58, 13033 }, talent = true },
	{ "Portal: Ironforge", { 40, 11416 }, faction = "Alliance" },
	{ "Portal: Orgrimmar", { 40, 11417 }, faction = "Horde" },
	{ "Portal: Stormwind", { 40, 10059 }, faction = "Alliance" },
	{ "Portal: Undercity", { 40, 11418 }, faction = "Horde" },
	{ "Conjure Mana Citrine", { 48, 10053 } },
	{ "Portal: Darnassus", { 50, 11419 }, faction = "Alliance" },
	{ "Portal: Thunder Bluff", { 50, 11420 }, faction = "Horde" },
	{ "Teleport: Dalaran", { 50, 1297659 } },
	{ "Arcane Brilliance", { 56, 23028 } },
	{ "Conjure Mana Ruby", { 58, 10054 } },
}

local function spellName(id)
	return ME.Spells.SpellName(id)
end

-- Index of the highest rank the player has, 0 when the spell is not known,
-- nil when it cannot be told (unknown variant in the spellbook).
local function knownRank(entry)
	local ranks = entry[2]
	local name = spellName(ranks[2]) or entry[1]
	local bookID = ME.Spells.BookID(name)
	if bookID then
		for i = 2, #ranks, 2 do
			if ranks[i] == bookID then return i / 2 end
		end
		return nil
	end
	local best = 0
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		for i = 2, #ranks, 2 do
			if ME.Bool(ME.Try(C_SpellBook.IsSpellKnown, ranks[i])) then best = i / 2 end
		end
	end
	return best
end

-- Spells or ranks the trainer would sell at the player's level that are not
-- learned yet. Returns a list of { name, rank, level, isNew }.
function Training:Missing()
	local level = UnitLevel("player") or 1
	local faction = UnitFactionGroup and ME.Plain(UnitFactionGroup("player")) or nil
	local list = {}
	for _, entry in ipairs(SPELLS) do
		if not entry.faction or entry.faction == faction then
			local ranks = entry[2]
			local available = 0
			for i = 1, #ranks, 2 do
				if ranks[i] <= level then available = (i + 1) / 2 end
			end
			if available > 0 then
				local have = knownRank(entry)
				-- Talent spells: only their higher ranks, and only with the talent.
				if have and have < available and not (entry.talent and have == 0) then
					list[#list + 1] = { name = spellName(ranks[2]) or entry[1], rank = available,
						level = ranks[available * 2 - 1], isNew = (have == 0), ranks = #ranks / 2 }
				end
			end
		end
	end
	return list
end

-- What becomes trainable exactly at `level` (for the level-up banner).
function Training:AtLevel(level)
	local faction = UnitFactionGroup and ME.Plain(UnitFactionGroup("player")) or nil
	local names = {}
	for _, entry in ipairs(SPELLS) do
		if not entry.faction or entry.faction == faction then
			local ranks = entry[2]
			for i = 1, #ranks, 2 do
				if ranks[i] == level then
					local rank = (i + 1) / 2
					local known = knownRank(entry)
					if not (entry.talent and (known == 0 or known == nil)) then
						names[#names + 1] = (spellName(ranks[2]) or entry[1]) .. (rank > 1 and (" (Rank " .. rank .. ")") or "")
					end
				end
			end
		end
	end
	return names
end

function Training:Describe(item)
	if item.ranks > 1 then return ("%s (Rank %d, level %d)"):format(item.name, item.rank, item.level) end
	return ("%s (level %d)"):format(item.name, item.level)
end

function Training:OnLogin()
	ME:On("PLAYER_LEVEL_UP", function(level)
		if not ME.db.reminders.trainer or type(level) ~= "number" then return end
		-- The spellbook updates a moment after the level-up event.
		C_Timer.After(1.5, function()
			local names = Training:AtLevel(level)
			if #names == 0 then return end
			ME:Print(("Level %d - new at the mage trainer: %s"):format(level, table.concat(names, ", ")))
			if ME.Alerts then
				local t = ME.FX.Theme()
				ME.Alerts:Show("trainer", "Interface\\Icons\\INV_Misc_Book_09", "VISIT YOUR TRAINER",
					("%d new spell%s or rank%s"):format(#names, #names == 1 and "" or "s", #names == 1 and "" or "s"), t.r, t.g, t.b)
			end
		end)
	end)
end
