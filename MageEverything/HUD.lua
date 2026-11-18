-- MageEverything: the next-spell HUD.
--
--     [sheep]    [low health]    [wand]      status badges, each in its own column
--                 SITUATION
--   [reaction]    [ MAIN ]    [next][next]
--        Spell - why it is suggested            one line, full width
--        Reaction spell: why                    one line, full width
--              health / mana bars
local _, ME = ...
local HUD = ME:NewModule("HUD")
local FX = ME.FX
local S = ME.state

---------------------------------------------------------------------------
-- Keybind lookup: which key casts a given spell?
---------------------------------------------------------------------------
local BARS = {
	{ 1, "ACTIONBUTTON" }, { 61, "MULTIACTIONBAR1BUTTON" }, { 49, "MULTIACTIONBAR2BUTTON" },
	{ 25, "MULTIACTIONBAR3BUTTON" }, { 37, "MULTIACTIONBAR4BUTTON" }, { 145, "MULTIACTIONBAR5BUTTON" },
	{ 157, "MULTIACTIONBAR6BUTTON" }, { 169, "MULTIACTIONBAR7BUTTON" },
}
local binds = {}

local function shortKey(k)
	k = k:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
	k = k:gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("BUTTON", "M")
	k = k:gsub("NUMPAD", "N"):gsub("SPACE", "Spc")
	return k
end

local function rebuildBinds()
	wipe(binds)
	for _, bar in ipairs(BARS) do
		for i = 1, 12 do
			local slot = bar[1] + i - 1
			local kind, id = ME.Try(GetActionInfo, slot)
			local name
			if kind == "spell" and id then
				name = ME.Spells.SpellName(id)
			elseif kind == "macro" and id and GetMacroSpell then
				local spellID = ME.Try(GetMacroSpell, id)
				name = spellID and ME.Spells.SpellName(spellID)
			end
			if kind == "item" and id then name = "item:" .. id end
			if name and not binds[name] then
				local key = GetBindingKey(bar[2] .. i)
				if key then binds[name] = shortKey(key) end
			end
		end
	end
end

function ME.Keybind(key)
	if ME.ItemID(key) then return binds[key] end
	return binds[ME.SpellLabel(key)]
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local root, main, queue, react, panicFrame, bars, lowMana, wand, ward
local healthCurve, manaCurve, wandCurve

local function makeSlot(parent, size)
	local icon = FX.Icon(parent, size)
	icon.border = FX.Border(icon, 1, 0, 0, 0, 1)
	icon.glow = FX.Glow(icon)
	icon.pop = FX.Pop(icon, 1.45, 0.16)
	local kb = icon.top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	kb:SetPoint("TOPRIGHT", -1, -2)
	kb:SetTextColor(1, 1, 1)
	icon.keybind = kb
	return icon
end

local function stepCurve(threshold)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local c = C_CurveUtil.CreateCurve()
	if Enum.LuaCurveType and c.SetType then c:SetType(Enum.LuaCurveType.Step) end
	c:AddPoint(0, 1)
	c:AddPoint(threshold, 0)
	c:AddPoint(1, 0)
	return c
end

function HUD:BuildCurves()
	healthCurve = stepCurve(ME.db.panic.health)
	manaCurve = stepCurve(ME.db.panic.mana)
	wandCurve = stepCurve(ME.db.hud.wandFinishAt or 0.2)
end

local function build()
	root = CreateFrame("Frame", "MageEverythingHUD", UIParent)
	root:SetSize(320, 196)
	ME:MakeMovable(root, "hud", "Mage HUD", "CENTER", 0, -150)

	-- Main suggestion
	main = makeSlot(root, 60)
	main:SetPoint("TOP", root, "TOP", 0, -80)
	if ME.db.hud.showRing then
		main.ring = FX.Ring(main, 90, 14)
		main.ring:SetAlpha(0.4)
	end

	local sit = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sit:SetPoint("BOTTOM", main, "TOP", 0, 3)
	main.situation = sit

	local reason = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	reason:SetPoint("TOP", main, "BOTTOM", 0, -6)
	reason:SetWidth(316)
	reason:SetWordWrap(false)
	reason:SetJustifyH("CENTER")
	main.reason = reason

	-- Next two
	queue = {}
	for i = 1, 2 do
		local q = makeSlot(root, 34)
		q:SetPoint("LEFT", i == 1 and main or queue[i - 1], "RIGHT", i == 1 and 10 or 4, 0)
		q:SetAlpha(0.8)
		queue[i] = q
	end

	-- Reaction (interrupt / root / shield / evocation)
	react = makeSlot(root, 42)
	react:SetPoint("RIGHT", main, "LEFT", -12, 0)
	local rl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	-- The reaction's text gets its own full-width line under the reason, so
	-- it can never run into the icons or the reason text.
	rl:SetPoint("TOP", main, "BOTTOM", 0, -21)
	rl:SetWidth(316)
	rl:SetWordWrap(false)
	rl:SetJustifyH("CENTER")
	rl:SetTextColor(1, 0.82, 0.2)
	react.label = rl
	react.shake = FX.Shake(react)
	react:Hide()

	-- (The Polymorph timer is its own clickable button: SheepButton.lua.)

	-- Magic ward badge: which of Dampen / Amplify Magic suits this target.
	ward = CreateFrame("Frame", nil, root)
	ward:SetSize(40, 40)
	ward:SetPoint("TOP", root, "TOP", -84, -15)
	ward.icon = makeSlot(ward, 34)
	ward.icon:SetPoint("CENTER")
	ward.icon.cd:Hide()
	ward.label = ward:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	ward.label:SetPoint("BOTTOM", ward.icon, "TOP", 0, 2)
	ward.check = ward.icon.top:CreateTexture(nil, "OVERLAY")
	ward.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	ward.check:SetSize(22, 22)
	ward.check:SetPoint("BOTTOMRIGHT", 4, -4)
	ward.pulse = FX.Pulse(ward.icon, 1, 0.4, 0.5)
	ward:Hide()

	-- Wand finisher: fades in when the target is nearly dead (shown by a
	-- health curve, like the low-health alert), to save mana on the kill.
	wand = CreateFrame("Frame", nil, root)
	wand:SetSize(40, 40)
	wand:SetPoint("TOP", root, "TOP", 84, -15)
	wand:SetAlpha(0)
	wand.icon = makeSlot(wand, 34)
	wand.icon:SetPoint("CENTER")
	wand.icon.cd:Hide()
	wand.icon.tex:SetTexture(ME.SpellIcon("Shoot"))
	wand.icon.border:SetColor(0.9, 0.8, 0.3, 1)
	local wl = wand:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	wl:SetPoint("BOTTOM", wand.icon, "TOP", 0, 2)
	wl:SetText("Wand finish")

	-- Low-health alert. Its visibility is an alpha value computed by the
	-- client from a health curve, so it works while health itself is hidden.
	panicFrame = CreateFrame("Frame", nil, root)
	panicFrame:SetSize(40, 40)
	panicFrame:SetPoint("TOP", root, "TOP", 0, -15)
	panicFrame:SetAlpha(0)
	local pi = makeSlot(panicFrame, 34)
	pi:SetPoint("CENTER")
	pi.border:SetColor(1, 0.1, 0.1, 1)
	local pg = panicFrame:CreateTexture(nil, "BACKGROUND")
	pg:SetPoint("TOPLEFT", -5, 5)
	pg:SetPoint("BOTTOMRIGHT", 5, -5)
	pg:SetColorTexture(1, 0, 0, 0.35)
	FX.Pulse(pg, 1, 0.2, 0.35):Play()
	local pt = panicFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pt:SetPoint("BOTTOM", panicFrame, "TOP", 0, 3)
	pt:SetText("|cffff3030LOW HEALTH|r")
	panicFrame.icon = pi

	-- Health / mana bars (status bars accept hidden values directly).
	bars = CreateFrame("Frame", nil, root)
	bars:SetSize(150, 11)
	bars:SetPoint("TOP", main, "BOTTOM", 0, -38)
	local function bar(r, g, b, y)
		local sb = CreateFrame("StatusBar", nil, bars)
		sb:SetSize(150, 4)
		sb:SetPoint("TOP", 0, y)
		sb:SetStatusBarTexture(FX.BAR)
		sb:SetStatusBarColor(r, g, b)
		local bg = sb:CreateTexture(nil, "BACKGROUND")
		bg:SetPoint("TOPLEFT", -1, 1)
		bg:SetPoint("BOTTOMRIGHT", 1, -1)
		bg:SetColorTexture(0, 0, 0, 0.75)
		return sb
	end
	bars.health = bar(0.2, 0.85, 0.3, 0)
	bars.mana = bar(0.25, 0.5, 1, -6)

	lowMana = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lowMana:SetPoint("TOP", bars, "BOTTOM", 0, -2)
	lowMana:SetText("|cff66aaffLOW MANA|r")
	lowMana:SetAlpha(0)

	HUD:BuildCurves()
	HUD:ApplyTheme()
	HUD:ApplySettings()
end

function HUD:ApplyTheme()
	if not root then return end
	local t = FX.Theme()
	main.border:SetColor(t.r, t.g, t.b, 1)
	main.situation:SetTextColor(t.r, t.g, t.b)
	if main.ring then main.ring:SetVertexColor(t.r, t.g, t.b) end
end

function HUD:ApplySettings()
	if not root then return end
	local db = ME.db.hud
	root:SetScale(db.scale or 1)
	bars:SetShown(db.showBars)
	main.reason:SetShown(db.showReason)
	if main.ring then main.ring:SetShown(db.showRing) end
	root:SetShown(db.enabled)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
local cdDirty = true

local function setSlot(slot, entry, isMain)
	if not entry then
		if slot.key then
			slot.key = nil
			slot.glow:Stop()
		end
		slot:Hide()
		return
	end
	local changed = slot.key ~= entry.key
	if changed then
		slot.key = entry.key
		slot.tex:SetTexture(ME.SpellIcon(entry.key))
		if ME.db.hud.showKeybind then
			slot.keybind:SetText(ME.Keybind(entry.key) or "")
		else
			slot.keybind:SetText("")
		end
		if isMain and slot:IsShown() then
			slot.pop:Stop()
			slot.pop:Play()
		end
	end
	if changed or cdDirty then
		FX.SetSpellCooldown(slot, ME.Spell(entry.key), false)
	end
	if entry.glow then slot.glow:Start() else slot.glow:Stop() end
	local inRange = ME.InRange(entry.key)
	if inRange == false then
		slot.tex:SetVertexColor(1, 0.3, 0.3)
	else
		slot.tex:SetVertexColor(1, 1, 1)
	end
	slot:Show()
end

local function updateVitals()
	if ME.db.hud.showBars then
		pcall(function()
			bars.health:SetMinMaxValues(0, UnitHealthMax("player"))
			bars.health:SetValue(UnitHealth("player"))
			local mana = Enum.PowerType and Enum.PowerType.Mana or 0
			bars.mana:SetMinMaxValues(0, UnitPowerMax("player", mana))
			bars.mana:SetValue(UnitPower("player", mana))
		end)
	end

	local p = ME.db.panic
	if ME.demo then
		panicFrame:SetAlpha(1)
		lowMana:SetAlpha(1)
		wand:SetAlpha(1)
		return
	end

	-- Wand finisher badge.
	local showWand = ME.db.hud.wandFinish and S.inCombat and S.hasTarget and not S.channeling
		and ME.Known("Shoot") and ME.HasWand()
	if not showWand then
		wand:SetAlpha(0)
	else
		local ok = false
		if wandCurve and UnitHealthPercent then
			ok = pcall(function() wand:SetAlpha(UnitHealthPercent("target", true, wandCurve)) end)
		end
		if not ok then
			local hp, max = ME.Plain(UnitHealth("target")), ME.Plain(UnitHealthMax("target"))
			wand:SetAlpha((hp and max and max > 0 and hp / max <= (ME.db.hud.wandFinishAt or 0.2)) and 1 or 0)
		end
	end
	if not p.enabled or not S.inCombat then
		panicFrame:SetAlpha(0)
		lowMana:SetAlpha(0)
		return
	end
	-- Curve path: the client evaluates the threshold and hands back an alpha.
	local done = false
	if healthCurve and UnitHealthPercent then
		done = pcall(function() panicFrame:SetAlpha(UnitHealthPercent("player", true, healthCurve)) end)
	end
	if not done then
		local hp, max = ME.Plain(UnitHealth("player")), ME.Plain(UnitHealthMax("player"))
		panicFrame:SetAlpha((hp and max and max > 0 and hp / max <= p.health) and 1 or 0)
	end
	done = false
	if manaCurve and UnitPowerPercent then
		local mana = Enum.PowerType and Enum.PowerType.Mana or 0
		done = pcall(function() lowMana:SetAlpha(UnitPowerPercent("player", mana, false, manaCurve)) end)
	end
	if not done then
		local mp, max = ME.Plain(UnitPower("player", 0)), ME.Plain(UnitPowerMax("player", 0))
		lowMana:SetAlpha((mp and max and max > 0 and mp / max <= p.mana) and 1 or 0)
	end
end

local function render()
	local db = ME.db.hud
	if ME.Bool(UnitIsDeadOrGhost("player")) or ME.Bool(UnitOnTaxi("player")) then
		root:SetAlpha(0)
		return
	end

	local demo = ME.demo
	local r = demo and ME.Demo:HUDResult() or ME.Rotation:Build()
	local q = r.queue
	local show = #q > 0 and (demo or S.hasTarget or not db.onlyWithTarget)
	root:SetAlpha((S.inCombat or demo) and 1 or db.alphaOOC)

	setSlot(main, show and q[1] or nil, true)
	for i = 1, 2 do
		setSlot(queue[i], (show and db.showQueue) and q[i + 1] or nil)
	end
	if main.ring then main.ring:SetShown(show and db.showRing) end

	if show then
		main.situation:SetText(r.situation or "")
		main.reason:SetText(db.showReason and (ME.SpellLabel(q[1].key) .. " - " .. (q[1].reason or "")) or "")
	else
		main.situation:SetText("")
		main.reason:SetText("")
	end

	-- Reaction slot
	local re = r.reaction
	if re then
		local was = react.key
		setSlot(react, re)
		react.label:SetText(ME.SpellLabel(re.key) .. ": " .. (re.reason or ""))
		if was ~= re.key then
			react.shake:Stop()
			react.shake:Play()
		end
	else
		setSlot(react, nil)
		react.label:SetText("")
	end

	-- Low-health alert icon (visibility handled in updateVitals)
	local pk = r.panic
	if pk and panicFrame.icon.key ~= pk then
		panicFrame.icon.key = pk
		panicFrame.icon.tex:SetTexture(ME.SpellIcon(pk))
		panicFrame.icon.keybind:SetText(ME.Keybind(pk) or "")
	end

	-- Magic ward badge
	local wst = (ME.db.reaction.magicWard and not ME.demo) and ME.MagicWardState() or nil
	if ME.demo then wst = { want = "DampenMagic", reason = "Caster" } end
	if wst then
		local key = wst.want or "DampenMagic"
		if ward.key ~= key then
			ward.key = key
			ward.icon.tex:SetTexture(ME.SpellIcon(key))
			ward.icon.keybind:SetText(ME.Keybind(key) or "")
		end
		local short = (key == "DampenMagic") and "Dampen" or "Amplify"
		if not wst.want then
			-- Neither helps: say so, quietly.
			ward.icon.tex:SetDesaturated(true)
			ward:SetAlpha(0.45)
			ward.check:Hide()
			ward.pulse:Stop()
			ward.label:SetText("|cff999999No ward|r")
			ward.icon.border:SetColor(0.3, 0.3, 0.3, 1)
		elseif wst.have == wst.want then
			ward.icon.tex:SetDesaturated(false)
			ward:SetAlpha(0.8)
			ward.check:Show()
			ward.pulse:Stop()
			ward.label:SetText("|cff59ff73" .. short .. "|r")
			ward.icon.border:SetColor(0.3, 0.9, 0.4, 1)
		else
			ward.icon.tex:SetDesaturated(false)
			ward:SetAlpha(1)
			ward.check:Hide()
			if not ward.pulse:IsPlaying() then ward.pulse:Play() end
			ward.label:SetText("|cffffd100" .. short .. "!|r")
			ward.icon.border:SetColor(1, 0.82, 0.2, 1)
		end
		ward.reason = wst.reason
		ward:Show()
	elseif ward:IsShown() then
		ward.pulse:Stop()
		ward:Hide()
	end

	if wand.icon.kb ~= true then
		wand.icon.keybind:SetText(ME.Keybind("Shoot") or "")
	end

	updateVitals()
	cdDirty = false
end

function HUD:OnLogin()
	build()
	rebuildBinds()

	local elapsed = 0
	root:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then return end
		elapsed = 0
		local ok, err = pcall(render)
		if not ok then ME:Error("HUD", err) end
	end)

	local bindPending
	local function queueBinds()
		if bindPending then return end
		bindPending = true
		C_Timer.After(0.5, function()
			bindPending = false
			rebuildBinds()
			main.key, queue[1].key, queue[2].key, react.key, panicFrame.icon.key = nil, nil, nil, nil, nil
		end)
	end
	ME:On("UPDATE_BINDINGS", queueBinds)
	ME:On("ACTIONBAR_SLOT_CHANGED", queueBinds)
	ME:On("PLAYER_ENTERING_WORLD", queueBinds)
	ME:Listen("SPELLS_UPDATED", queueBinds)

	ME:On("SPELL_UPDATE_COOLDOWN", function() cdDirty = true end)
	ME:Listen("SPEC_CHANGED", function() HUD:ApplyTheme() end)
end
