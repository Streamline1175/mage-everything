-- MageEverything: out-of-combat reminders you can click to fix.
-- Each reminder is a secure button, so clicking it casts the spell. Secure
-- buttons may only be changed out of combat, so the row is rebuilt only then
-- and hidden the moment combat starts.
local _, ME = ...
local Rem = ME:NewModule("Reminders")
local FX = ME.FX

local root
local buttons = {}
local SIZE = 38
local GEMS = { 8008, 8007, 5513, 5514 } -- Mana Ruby, Citrine, Jade, Agate
local GEM_SPELLS = { "ConjureManaRuby", "ConjureManaCitrine", "ConjureManaJade", "ConjureManaAgate" }

local function itemCount(id)
	local n = C_Item and C_Item.GetItemCount and ME.Try(C_Item.GetItemCount, id)
	return ME.Plain(n, 0) or 0
end

-- Conjured water, one item per Conjure Water rank (Forever 1.60.1 data).
local WATER = { 5350, 2288, 2136, 3772, 8077, 8078, 8079, 231778 }

local function waterCount()
	local total = 0
	for _, id in ipairs(WATER) do total = total + itemCount(id) end
	return total
end

local function manaFraction()
	local cur, max = ME.Plain(UnitPower("player", 0)), ME.Plain(UnitPowerMax("player", 0))
	if cur and max and max > 0 then return cur / max end
end

-- Returns a list of { key, label, unit, clickable }.
-- Conjured food, one item per Conjure Food rank.
local FOOD = { 5349, 1113, 1114, 1487, 8075, 8076, 22895 }

-- Highest-rank item from a list that is in the bags.
local function bestItem(ids)
	for i = #ids, 1, -1 do
		if itemCount(ids[i]) > 0 then return ids[i] end
	end
end

local function healthFraction()
	local cur, max = ME.Plain(UnitHealth("player")), ME.Plain(UnitHealthMax("player"))
	if cur and max and max > 0 then return cur / max end
end

-- A curse on the player (auras are readable out of combat).
local function cursed()
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
	for i = 1, 40 do
		local aura = ME.Try(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
		if type(aura) ~= "table" then break end
		if ME.Plain(aura.dispelName) == "Curse" then return true end
	end
	return false
end

-- Returns a list of reminders. Each has: key (spell key for the icon),
-- label, and one of: nothing (click casts the spell), item = id (click uses
-- the item), info = true (not clickable). `tip` adds tooltip lines.
local function evaluate()
	local db = ME.db.reminders
	local list = {}
	if not db.enabled then return list end
	if ME.demo then
		-- Samples only: marked as info so clicking them does nothing.
		for _, s in ipairs({ { "ArcaneIntellect", "Intellect" }, { "IceArmor", "Armor" }, { "ConjureWater", "Water" },
			{ "ConjureManaRuby", "Mana gem" }, { "ConjureFood", "Eat" }, { "Polymorph", "Trainer (3)", "Interface\\Icons\\INV_Misc_Book_09" } }) do
			list[#list + 1] = { key = s[1], label = s[2], icon = s[3], info = true }
		end
		return list
	end

	if db.curse and ME.Known("RemoveCurse") and cursed() then
		list[#list + 1] = { key = "RemoveCurse", label = "Curse", unit = "player" }
	end
	if db.intellect and ME.HasBuff("ArcaneIntellect") == false and ME.HasBuff("ArcaneBrilliance") == false then
		local key = ME.FirstKnown("ArcaneIntellect")
		if key then list[#list + 1] = { key = key, label = "Intellect", unit = "player" } end
	end
	if db.armor and ME.HasBuff("IceArmor") == false and ME.HasBuff("FrostArmor") == false
		and ME.HasBuff("MageArmor") == false then
		local key = ME.FirstKnown("IceArmor", "FrostArmor", "MageArmor")
		if key then list[#list + 1] = { key = key, label = "Armor" } end
	end

	local water, food = bestItem(WATER), bestItem(FOOD)
	if db.conjure then
		if not water and ME.Known("ConjureWater") then list[#list + 1] = { key = "ConjureWater", label = "Water" } end
		if not food and ME.Known("ConjureFood") then list[#list + 1] = { key = "ConjureFood", label = "Food" } end
	end
	if db.gem then
		local have = false
		for _, id in ipairs(GEMS) do
			if itemCount(id) > 0 then have = true break end
		end
		local key = ME.FirstKnown(unpack(GEM_SPELLS))
		if key and not have then list[#list + 1] = { key = key, label = "Mana gem" } end
	end

	-- Drink / eat: click to use the best conjured water or food.
	local mounted = ME.Bool(IsMounted())
	if db.drink and water and not mounted then
		local f = manaFraction()
		if f and f < db.drinkAt then
			list[#list + 1] = { key = "ConjureWater", label = "Drink", item = water, tip = { "Click to drink." } }
		end
	end
	if db.eat and food and not mounted then
		local f = healthFraction()
		if f and f < db.eatAt then
			list[#list + 1] = { key = "ConjureFood", label = "Eat", item = food, tip = { "Click to eat." } }
		end
	end

	if db.wand and (UnitLevel("player") or 1) >= 5 and not ME.HasWand() then
		list[#list + 1] = { key = "Shoot", label = "No wand", info = true, icon = "Interface\\Icons\\INV_Wand_01",
			tip = { "No wand equipped.", "A wand finishes low enemies for free and keeps you fighting when out of mana." } }
	end

	if db.trainer and ME.Training then
		local missing = ME.Training:Missing()
		if #missing > 0 then
			local tip = { "Available at the mage trainer:" }
			for i = 1, math.min(#missing, 12) do
				tip[#tip + 1] = (missing[i].isNew and "|cff55ff55New:|r " or "") .. ME.Training:Describe(missing[i])
			end
			if #missing > 12 then tip[#tip + 1] = ("...and %d more"):format(#missing - 12) end
			list[#list + 1] = { key = "Polymorph", label = ("Trainer (%d)"):format(#missing), info = true,
				icon = "Interface\\Icons\\INV_Misc_Book_09", tip = tip }
		end
	end
	return list
end

local function acquire(i)
	local b = buttons[i]
	if b then return b end
	b = CreateFrame("Button", "MageEverythingReminder" .. i, root, "SecureActionButtonTemplate")
	b:SetSize(SIZE, SIZE)
	b:SetPoint("LEFT", root, "LEFT", (i - 1) * (SIZE + 6), 0)
	b:RegisterForClicks("AnyUp", "AnyDown")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -2, 2)
	bg:SetPoint("BOTTOMRIGHT", 2, -2)
	bg:SetColorTexture(1, 0.82, 0.1, 0.9)
	b.pulse = FX.Pulse(bg, 1, 0.25, 0.7)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(self.title or "")
		if ME.demo then
			GameTooltip:AddLine("Sample reminder (demo mode).", 1, 1, 1)
		elseif self.tipLines then
			for _, line in ipairs(self.tipLines) do GameTooltip:AddLine(line, 1, 1, 1, true) end
		else
			GameTooltip:AddLine("Click to cast.", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:Hide()
	buttons[i] = b
	return b
end

function Rem:Update()
	if not root or InCombatLockdown() then return end
	local resting = ME.Bool(UnitIsDeadOrGhost("player")) or ME.Bool(UnitOnTaxi("player"))
	local list = resting and {} or evaluate()
	for i, item in ipairs(list) do
		local b = acquire(i)
		b.info = item.info
		b.tipLines = item.tip
		b.title = item.item and item.label or (item.info and item.label or ME.SpellLabel(item.key))
		b.tex:SetTexture(item.icon or (item.item and ME.SpellIcon("item:" .. item.item)) or ME.SpellIcon(item.key))
		b.label:SetText(item.label)
		-- Secure attributes: exactly one action (spell, item or none).
		b:SetAttribute("spell", nil)
		b:SetAttribute("item", nil)
		b:SetAttribute("unit", nil)
		if item.info then
			b:SetAttribute("type", nil)
		elseif item.item then
			b:SetAttribute("type", "item")
			b:SetAttribute("item", "item:" .. item.item)
		else
			b:SetAttribute("type", "spell")
			b:SetAttribute("spell", ME.Spell(item.key))
			b:SetAttribute("unit", item.unit)
		end
		b:Show()
		if not b.pulse:IsPlaying() then b.pulse:Play() end
	end
	for i = #list + 1, #buttons do
		buttons[i]:Hide()
		buttons[i].pulse:Stop()
	end
	root:SetWidth(math.max(SIZE, #list * (SIZE + 6) - 6))
end

function Rem:OnLogin()
	root = CreateFrame("Frame", "MageEverythingReminders", UIParent)
	root:SetSize(SIZE, SIZE)
	ME:MakeMovable(root, "reminders", "Reminders", "CENTER", 0, 230)

	local pending
	local function queue()
		if pending then return end
		pending = true
		C_Timer.After(0.4, function()
			pending = false
			Rem:Update()
		end)
	end

	-- Hide before combat lockdown begins (this event fires just before it).
	ME:On("PLAYER_REGEN_DISABLED", function()
		for _, b in ipairs(buttons) do b:Hide() end
	end)
	ME:On("PLAYER_REGEN_ENABLED", queue)
	ME:On("UNIT_AURA", function(unit) if unit == "player" then queue() end end)
	ME:On("BAG_UPDATE_DELAYED", queue)
	ME:On("PLAYER_ENTERING_WORLD", queue)
	ME:On("PLAYER_ALIVE", queue)
	ME:On("PLAYER_UNGHOST", queue)
	ME:Listen("SPELLS_UPDATED", queue)
	ME:Listen("DEMO", function(on, fromCombat)
		if fromCombat then
			for _, b in ipairs(buttons) do b:Hide() end
		else
			Rem:Update()
		end
	end)
	ME:On("PLAYER_EQUIPMENT_CHANGED", queue)
	ME:On("PLAYER_LEVEL_UP", queue)
	C_Timer.NewTicker(3, queue) -- health / mana levels for the eat and drink buttons
	queue()
end
