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
local function evaluate()
	local db = ME.db.reminders
	local list = {}
	if not db.enabled then return list end

	if db.intellect and ME.HasBuff("ArcaneIntellect") == false and ME.HasBuff("ArcaneBrilliance") == false then
		local key = ME.FirstKnown("ArcaneIntellect")
		if key then list[#list + 1] = { key = key, label = "Intellect", unit = "player" } end
	end
	if db.armor and ME.HasBuff("IceArmor") == false and ME.HasBuff("FrostArmor") == false
		and ME.HasBuff("MageArmor") == false then
		local key = ME.FirstKnown("IceArmor", "FrostArmor", "MageArmor")
		if key then list[#list + 1] = { key = key, label = "Armor" } end
	end
	if db.conjure and ME.Known("ConjureWater") then
		if waterCount() == 0 then list[#list + 1] = { key = "ConjureWater", label = "Water" } end
	end
	if db.gem then
		local have = false
		for _, id in ipairs(GEMS) do
			if itemCount(id) > 0 then have = true break end
		end
		local key = ME.FirstKnown(unpack(GEM_SPELLS))
		if key and not have then list[#list + 1] = { key = key, label = "Mana gem" } end
	end
	if db.drink then
		local f = manaFraction()
		if f and f < db.drinkAt and not ME.Bool(IsMounted()) then
			list[#list + 1] = { key = "ConjureWater", label = "Drink", info = true, icon = "Interface\\Icons\\INV_Drink_07" }
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
		GameTooltip:AddLine(self.tip or "")
		GameTooltip:AddLine(self.info and "Sit and drink to recover mana." or "Click to cast.", 1, 1, 1)
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
		b.tip = ME.SpellLabel(item.key)
		b.tex:SetTexture(item.icon or ME.SpellIcon(item.key))
		b.label:SetText(item.label)
		if item.info then
			b:SetAttribute("type", nil)
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
	C_Timer.NewTicker(3, queue) -- mana level for the drink reminder
	queue()
end
