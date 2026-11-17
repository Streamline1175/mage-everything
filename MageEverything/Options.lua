-- MageEverything: settings panel, slash commands, diagnostics.
local ADDON, ME = ...
local Options = ME:NewModule("Options")

local category

local function apply()
	for _, m in ipairs(ME.modules) do
		if m.ApplySettings then pcall(m.ApplySettings, m) end
	end
	if ME.HUD and ME.HUD.BuildCurves then ME.HUD:BuildCurves() end
	if ME.Reminders then ME.Reminders:Update() end
	if ME.Cooldowns then ME.Cooldowns:Layout() end
end

local function buildPanel()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
	category = Settings.RegisterVerticalLayoutCategory("Mage Everything")
	local n = 0

	local function check(tbl, key, label, tip)
		n = n + 1
		local setting = Settings.RegisterAddOnSetting(category, "MageEverything_" .. n, key, tbl,
			Settings.VarType.Boolean, label, ME.defaults and tbl[key] and true or false)
		setting:SetValueChangedCallback(apply)
		Settings.CreateCheckbox(category, setting, tip)
	end
	local function slider(tbl, key, label, tip, min, max, step, fmt)
		n = n + 1
		local setting = Settings.RegisterAddOnSetting(category, "MageEverything_" .. n, key, tbl,
			Settings.VarType.Number, label, tbl[key])
		setting:SetValueChangedCallback(apply)
		local opts = Settings.CreateSliderOptions(min, max, step)
		if opts.SetLabelFormatter and MinimalSliderWithSteppersMixin then
			opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
				return fmt and fmt:format(v) or tostring(v)
			end)
		end
		Settings.CreateSlider(category, setting, opts, tip)
	end

	local db = ME.db
	check(db.hud, "enabled", "Next-spell HUD", "Show the spell suggestion display.")
	check(db.hud, "showQueue", "Show the next two spells", "Smaller icons to the right of the main suggestion.")
	check(db.hud, "showReason", "Show the reason text", "A short explanation under the main icon.")
	check(db.hud, "showKeybind", "Show keybinds on icons", "Print the key that casts the suggested spell.")
	check(db.hud, "showBars", "Show health and mana bars", "Thin bars under the HUD.")
	check(db.hud, "showRing", "Animated rune ring", "Rotating ring behind the main icon.")
	check(db.hud, "onlyWithTarget", "Only with an enemy targeted", "Hide suggestions when nothing hostile is targeted.")
	check(db.hud, "useWand", "Suggest the wand when out of mana", "Falls back to Shoot when the filler is unaffordable.")
	check(db.hud, "frostInstant", "Frost: use Fire Blast / Ice Lance between Frost Novas",
		"They share a cooldown. On: spent as instant damage whenever Frost Nova is on cooldown. Off: saved strictly for frozen targets.")
	check(db.hud, "fireballFiller", "Fire: Fireball filler instead of Frostfire Bolt",
		"Frostfire Bolt is the default filler once learned. Deep Fire builds may prefer Fireball.")
	check(db.hud, "useBlizzardAssist", "Prefer Blizzard's assistant when offered",
		"Uses the game's own rotation assistant if this client provides one. WoW Forever currently does not.")
	slider(db.hud, "scale", "HUD scale", nil, 0.6, 2, 0.05, "%.2f")
	slider(db.hud, "alphaOOC", "HUD opacity out of combat", nil, 0, 1, 0.05, "%.2f")
	slider(db.hud, "aoeThreshold", "Enemies for AoE", "Switch to area spells at this many enemies in combat.", 2, 6, 1, "%d")

	check(db.reaction, "enabled", "Reaction icon", "Interrupts, roots, shields and Evocation beside the main icon.")
	check(db.reaction, "counterspell", "Reaction: Counterspell", "When your target starts casting.")
	check(db.reaction, "nova", "Reaction: Frost Nova", "When an enemy has turned on you.")
	check(db.reaction, "shields", "Reaction: Ice Barrier / Mana Shield", nil)
	check(db.reaction, "evocation", "Reaction: Evocation", "When the filler spell is unaffordable.")
	check(db.reaction, "gem", "Reaction: mana gem", "Suggested before Evocation when out of mana.")
	check(db.reaction, "polymorph", "Reaction: Polymorph", "Sheep the add when a second enemy joins, and re-sheep before the timer ends.")
	check(db.hud, "markSheep", "Mark the remembered sheep with a moon",
		"The 'Polymorph target and remember it' keybind also puts a moon marker on it.")
	check(db.reaction, "magicWard", "Reaction: Dampen / Amplify Magic before a pull",
		"Dampen against casters. Amplify only in a group with a healer, against enemies that do not cast.")
	check(db.hud, "sheepTimer", "Polymorph timer", "Countdown from your own Polymorph cast. Ends early when the sheep is seen to break or die.")
	check(db.hud, "wandFinish", "Wand finisher badge", "Shows when your target is nearly dead, to save mana on the kill.")
	slider(db.hud, "wandFinishAt", "Wand finisher threshold", "Target health at which the wand badge appears.", 0.05, 0.5, 0.05, "%.2f")

	check(db.panic, "enabled", "Low health and low mana alerts", "Shown by the client from thresholds, even while values are hidden.")
	slider(db.panic, "health", "Low health threshold", nil, 0.1, 0.7, 0.05, "%.2f")
	slider(db.panic, "mana", "Low mana threshold", nil, 0.05, 0.6, 0.05, "%.2f")

	check(db.cooldowns, "enabled", "Cooldown row", "Icons for your main cooldowns.")
	slider(db.cooldowns, "scale", "Cooldown row scale", nil, 0.6, 2, 0.05, "%.2f")

	check(db.alerts, "enabled", "Proc banners", "Animated banners for procs, level-ups and new spells.")
	check(db.alerts, "sound", "Proc sound", nil)
	slider(db.alerts, "scale", "Banner scale", nil, 0.6, 2, 0.05, "%.2f")

	check(db.xp, "enabled", "Mage experience bar", "Spec-themed XP bar.")
	check(db.xp, "hideBlizzard", "Hide the default XP bar (needs /reload)", "Also hides the default reputation bar.")
	check(db.xp, "showText", "XP bar text", nil)
	check(db.xp, "showDetail", "XP bar details line", "Rested, XP per hour, time to level and kills, above the bar.")
	check(db.xp, "showQuestXP", "Show XP from completed quests", "Gold overlay for quests ready to hand in.")
	check(db.xp, "effects", "XP bar animations", nil)
	slider(db.xp, "width", "XP bar width", nil, 200, 1200, 10, "%d")
	slider(db.xp, "height", "XP bar height", nil, 8, 32, 1, "%d")

	check(db.reminders, "enabled", "Clickable reminders", "Out-of-combat buttons for missing buffs and supplies.")
	check(db.reminders, "intellect", "Remind: Arcane Intellect", nil)
	check(db.reminders, "armor", "Remind: armor spell", nil)
	check(db.reminders, "conjure", "Remind: conjure water and food", nil)
	check(db.reminders, "gem", "Remind: mana gem", nil)
	check(db.reminders, "drink", "Button: drink",
		"Appears when mana is low. Uses your best conjured water. Mana is hidden from addons, so 'low' is detected when you can no longer afford one of your spells that costs less than the threshold.")
	check(db.reminders, "eat", "Button: eat", "Appears when health is low. Uses your best conjured food.")
	check(db.reminders, "cannibalize", "Button: Cannibalize (Undead)", "Appears when health is low and Cannibalize is off cooldown.")
	slider(db.reminders, "drinkAt", "Show Drink below this mana", nil, 0.1, 0.95, 0.05, "%.2f")
	slider(db.reminders, "eatAt", "Show Eat below this health", nil, 0.1, 0.95, 0.05, "%.2f")
	slider(db.reminders, "healWindow", "Offer Eat / Cannibalize for this long after a fight (seconds)",
		"Outside this window the buttons are removed completely, so nothing can be hovered or clicked.", 10, 180, 5, "%d")
	check(db.reminders, "nameplates", "Warn when enemy nameplates are off", "They are needed to count enemies for AoE suggestions.")
	check(db.reminders, "wand", "Remind: no wand equipped", nil)
	check(db.reminders, "curse", "Button: Remove Lesser Curse", "Out of combat only; curses are hidden from addons during a fight.")
	check(db.reminders, "trainer", "Remind: new spells at the trainer", "Also announces them when you level up.")

	check(db.reagents, "warn", "Remind: out of reagents", "Rune of Teleportation, Rune of Portals, Arcane Powder and Light Feather, for spells you know.")
	slider(db.reagents, "warnBelow", "Remind when fewer than", nil, 1, 10, 1, "%d")
	check(db.reagents, "autoBuy", "Buy reagents at vendors automatically",
		"Off by default. Tops each reagent up to its limit below, for spells you know, while enough bag slots stay free.")
	slider(db.reagents.stock, "teleport", "Keep: Rune of Teleportation", nil, 0, 40, 1, "%d")
	slider(db.reagents.stock, "portal", "Keep: Rune of Portals", nil, 0, 40, 1, "%d")
	slider(db.reagents.stock, "powder", "Keep: Arcane Powder", nil, 0, 60, 1, "%d")
	slider(db.reagents.stock, "feather", "Keep: Light Feather", nil, 0, 40, 1, "%d")
	slider(db.reagents, "keepFree", "Bag slots to leave free when buying", "Reagents are not bought into the last few empty slots.", 0, 20, 1, "%d")
	check(db.qol, "nodeIcons", "Show an icon over herbs and ore in front of you",
		"Uses the game's Interact Key system (it also enables the Interact Key). Turning this off restores your previous settings.")
	slider(db.qol, "nodeRange", "Herb / ore icon range (yards)", "How far ahead the game looks for a node to mark.", 5, 30, 1, "%d")
	check(db.qol, "sellJunk", "Sell junk at vendors", nil)
	check(db.qol, "autoRepair", "Repair at vendors", nil)

	Settings.RegisterAddOnCategory(category)
end

function Options:Open()
	if InCombatLockdown() then
		ME:Print("Options can't be opened in combat.")
		return
	end
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	else
		ME:Print("Settings panel unavailable; use /mage help.")
	end
end

---------------------------------------------------------------------------
-- Diagnostics: prints what this client lets the addon read.
---------------------------------------------------------------------------
local function yn(v)
	if v == nil then return "|cff888888n/a|r" end
	if ME.issecret(v) then return "|cffff5555hidden|r" end
	return v and "|cff55ff55yes|r" or "|cffffaa33no|r"
end

-- Runs kept for the copy window (newest last).
local diagRuns = {}

local function stripColors(str)
	return (str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Options:Diagnose()
	local lines = {}
	local function p(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		local line = table.concat(parts, " ")
		lines[#lines + 1] = line
		print(line)
	end
	p("Mage Everything diagnostics")
	p("  client:", (select(4, GetBuildInfo())), "project:", tostring(WOW_PROJECT_ID),
		"Forever:", yn(WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT))
	p("  spec:", ME.spec, ("(Arcane %d / Fire %d / Frost %d, detected: %s)"):format(
		ME.specPoints.ARCANE, ME.specPoints.FIRE, ME.specPoints.FROST, tostring(ME.specDetected)))
	p("  in combat:", yn(ME.state.inCombat), "enemies:", ME.state.enemies, "aggro:", yn(ME.state.aggro))
	p("  health readable:", yn(not ME.issecret(UnitHealth("player"))),
		"mana readable:", yn(not ME.issecret(UnitPower("player", 0))))
	if C_Secrets then
		p("  auras hidden now:", yn(ME.Try(C_Secrets.ShouldAurasBeSecret)),
			"cooldowns hidden now:", yn(ME.Try(C_Secrets.ShouldCooldownsBeSecret)))
	end
	p("  health curve API:", yn(UnitHealthPercent ~= nil and C_CurveUtil ~= nil),
		"duration objects:", yn(C_Spell.GetSpellCooldownDuration ~= nil))
	if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
		local parts = {}
		for _, key in ipairs({ "Clearcasting", "MissileBarrage", "FingersOfFrost", "HeatingUp" }) do
			local def = ME.Spells.DEFS[key]
			parts[#parts + 1] = key .. " " .. yn(ME.Try(C_Secrets.ShouldSpellAuraBeSecret, def[2]))
		end
		p("  proc auras hidden now:", table.concat(parts, ", "))
	end
	p("  mana cost readable:", yn(ME.ManaCost(ME.FirstKnown("Frostbolt", "Fireball") or "Fireball") ~= nil),
		"Heating Up stacks:", ME.HeatingUpStacks(), "Arcane Blast stacks:", ME.ArcaneBlastStacks(),
		"Winter's Chill:", ME.WintersChill())
	-- Cooldown and cast-time signals the rotation depends on in combat.
	do
		local key = ME.FirstKnown("FireBlast", "FrostNova", "Frostbolt")
		local id = key and ME.Spell(key)
		local cd = id and ME.Try(C_Spell.GetSpellCooldown, id)
		local info = id and ME.Try(C_Spell.GetSpellInfo, id)
		local ready, why = ME.Ready(key or "Frostbolt")
		p(("  %s: on-cooldown flag readable: %s, cast time readable: %s, ready: %s%s"):format(tostring(key),
			yn(cd and cd.isActive ~= nil and not ME.issecret(cd.isActive)),
			yn(info and info.castTime ~= nil and not ME.issecret(info.castTime)),
			tostring(ready), why and (" (" .. why .. ")") or ""))
		p("  wand equipped:", yn(ME.HasWand()), "target casting seen:", yn(ME.state.targetCasting))
		local st = ME.state
		p("  target looks like a caster:", yn(ME.TargetIsCaster()), "healer in group:", yn(ME.HealerInGroup()),
			"corpse usable for Cannibalize:", yn(ME.CannibalizeCorpse()), "corpse type hidden:", yn(st.corpseTypeHidden))
		p(("  sheep: %ds left, following %s, target signal %s, last break: %s"):format(ME.SheepRemaining(),
			tostring(st.sheepUnit or ("nothing (re-sheep uses " .. tostring(st.lastSheepUnit or "previous target") .. ")")),
			st.sheepSignal == nil and "not checked" or (st.sheepSignal and "usable" or "not usable"),
			st.sheepBrokeWhy or "none"))
	end
	-- Talents actually taken (drives talent-specific rotation rules).
	do
		local parts = {}
		for id, rank in pairs(ME.talents or {}) do
			parts[#parts + 1] = (ME.Spells.SpellName(id) or tostring(id)) .. " " .. rank
		end
		table.sort(parts)
		p("  talents read:", yn(ME.talentsRead), #parts > 0 and table.concat(parts, ", ") or "")
	end
	-- Settings and setup that silently change what the addon can do.
	do
		local off = ME.EnemyNameplatesOff()
		p("  enemy nameplates on (needed to count enemies for AoE):", yn(off == nil and nil or not off))
		local unbound = {}
		for _, key in ipairs({ "Frostbolt", "Fireball", "FireBlast", "IceLance", "FrostNova", "ArcaneMissiles", "ArcaneExplosion",
			"ConeOfCold", "Blizzard", "Flamestrike", "Pyroblast", "Scorch", "ArcaneBlast", "ArcaneWrath", "Counterspell",
			"Polymorph", "IceBarrier", "IceBlock", "ManaShield", "Evocation", "Blink", "ColdSnap", "Shoot" }) do
			if ME.Known(key) and not ME.Keybind(key) then unbound[#unbound + 1] = key end
		end
		p("  suggested spells with no keybind found:", #unbound > 0 and table.concat(unbound, ", ") or "none")
		if C_Secrets and C_Secrets.GetPowerTypeSecrecy and C_Secrets.GetSpellAuraSecrecy then
			local names = { [0] = "never hidden", [1] = "always hidden", [2] = "hidden in combat" }
			local function level(v) return names[ME.Plain(v, -1)] or "?" end
			p("  secrecy: mana", level(ME.Try(C_Secrets.GetPowerTypeSecrecy, 0)),
				"| Clearcasting", level(ME.Try(C_Secrets.GetSpellAuraSecrecy, 12536)),
				"| Fingers of Frost", level(ME.Try(C_Secrets.GetSpellAuraSecrecy, 400669)))
		end
	end
	-- What the game has actually sent this session.
	do
		local seen = ME.seen
		p(("  events this session: own casts %d, target casts %d, focus casts %d, aura updates %d, proc glows %d"):format(
			seen.casts, seen.targetCasts, seen.focusCasts, seen.auraEvents, seen.glows))
		local unknown = {}
		for name in pairs(seen.unknown) do unknown[#unknown + 1] = name end
		table.sort(unknown)
		p("  casts the addon does not recognise:", #unknown > 0 and table.concat(unknown, ", ") or "none")
		local extra = ME.Spells.Uncatalogued()
		p("  spellbook spells the addon has no entry for:", #extra > 0 and table.concat(extra, ", ") or "none")
	end
	do
		local low, share = ME.ManaBelow(ME.db.reminders.drinkAt)
		p(("  low-mana check from spell costs: %s (detects mana under about %d%% of maximum)"):format(
			low == nil and "unavailable" or (low and "LOW" or "not low"), (share or 0) * 100))
	end
	local assist = C_AssistedCombat and C_AssistedCombat.IsAvailable and ME.Try(C_AssistedCombat.IsAvailable)
	p("  Blizzard rotation assistant:", yn(assist))
	local known, missing = {}, {}
	for key in pairs(ME.Spells.DEFS) do
		if ME.Known(key) then known[#known + 1] = key .. "=" .. ME.Spell(key) else missing[#missing + 1] = key end
	end
	table.sort(known); table.sort(missing)
	p("  known spells:", table.concat(known, ", "))
	p("  not known:", table.concat(missing, ", "))
	local overlays = {}
	for k in pairs(ME.state.overlay) do overlays[#overlays + 1] = k end
	p("  active proc glows:", #overlays > 0 and table.concat(overlays, ", ") or "none")
	if ME.lastError then p("  last error:", ME.lastError) end
	p("  profile:", tostring(ME.profileName), "version:", ME.version)

	lines[1] = ("== %s, %s =="):format(ME.state.inCombat and "IN COMBAT" or "out of combat", date and date("%H:%M:%S") or "")
	diagRuns[#diagRuns + 1] = stripColors(table.concat(lines, "\n"))
	if #diagRuns > 4 then table.remove(diagRuns, 1) end
	-- Kept in the saved-variables file too (written on logout or /reload).
	ME.root.lastDiag = table.concat(diagRuns, "\n\n")
	if ME.state.inCombat then
		ME:Print("Diagnostics saved. Run /mage diag again after the fight to open the copy window with both runs.")
	else
		Options:ShowCopy(ME.root.lastDiag)
	end
end

-- Window with selectable text: Ctrl+A, Ctrl+C to copy.
local copyFrame
function Options:ShowCopy(str)
	if not copyFrame then
		local f = CreateFrame("Frame", "MageEverythingCopy", UIParent)
		f:SetSize(640, 420)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		if UISpecialFrames then table.insert(UISpecialFrames, "MageEverythingCopy") end
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.035, 0.04, 0.085, 0.97)
		ME.FX.Border(f, 1, 0.41, 0.8, 0.94, 1)
		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 14, -12)
		title:SetText("Diagnostics - press Ctrl+A then Ctrl+C to copy")
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
		local scroll = CreateFrame("ScrollFrame", "MageEverythingCopyScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -40)
		scroll:SetPoint("BOTTOMRIGHT", -34, 14)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject("ChatFontNormal")
		edit:SetWidth(580)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		f.edit = edit
		copyFrame = f
	end
	copyFrame.edit:SetText(str or "")
	copyFrame:Show()
	copyFrame.edit:SetFocus()
	copyFrame.edit:HighlightText()
end


---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function help()
	ME:Print("commands:")
	print("  /mage - open options")
	print("  /mage unlock | lock | reset - move frames")
	print("  /mage portals - teleport and portal menu")
	print("  /mage spec auto|arcane|fire|frost - override spec detection")
	print("  /mage diag - show what the client lets the addon read (opens a window to copy from)")
	print("  /mage profile - per-character settings: list, share, copy, reset")
	print("  /mage demo - play sample content in every section, for arranging the layout")
	print("  /mage rescan - re-read your spellbook and talents now")
	print("  /mage restock - buy reagents up to your limits from the open vendor")
	print("  /mage welcome - setup guide")
	print("  /mage on | off - enable or disable the addon (then /reload)")
end

local function slash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local cmd, arg = msg:match("^(%S+)%s*(.*)$")
	if msg == "on" or msg == "off" then
		ME.root.enabled = (msg == "on")
		ME:Print("Addon " .. (msg == "on" and "enabled" or "disabled") .. ". /reload to apply.")
		return
	end
	if not ME.active then
		ME:Print(ME.isMage and "Disabled. /mage on, then /reload." or "This character is not a mage.")
		return
	end
	if msg == "" or msg == "config" or msg == "options" then
		Options:Open()
	elseif msg == "unlock" then
		ME:SetLocked(false)
	elseif msg == "lock" then
		ME:SetLocked(true)
	elseif msg == "reset" then
		ME:ResetPositions()
	elseif msg == "portals" or msg == "portal" then
		ME.Portals:Toggle()
	elseif msg == "demo" or msg == "test" then
		ME.Demo:Toggle()
	elseif msg == "welcome" or msg == "guide" or msg == "setup" then
		ME.Welcome:Toggle()
	elseif msg == "diag" or msg == "debug" then
		Options:Diagnose()
	elseif msg == "rescan" then
		ME.Spells:Rebuild()
		ME.Spec:Update()
		local n = 0
		for key in pairs(ME.Spells.DEFS) do if ME.Known(key) then n = n + 1 end end
		ME:Print(("Rescanned: %d spells recognised. Ice Lance: %s."):format(n, ME.Known("IceLance") and "known" or "not found"))
	elseif msg == "restock" then
		if MerchantFrame and MerchantFrame:IsShown() then ME.Reagents:Restock() else ME:Print("Open a vendor first.") end
	elseif cmd == "profile" then
		Options:Profile(arg)
	elseif cmd == "spec" then
		local v = arg:upper()
		if v == "AUTO" or v == "ARCANE" or v == "FIRE" or v == "FROST" then
			ME.db.specOverride = v
			ME.Spec:Update()
			ME:Print("Spec: " .. (v == "AUTO" and ("auto (" .. ME.spec .. ")") or v))
		else
			ME:Print("Usage: /mage spec auto|arcane|fire|frost")
		end
	else
		help()
	end
end

-- /mage profile [use|copy <name>] [reset]
function Options:Profile(arg)
	local sub, name = (arg or ""):match("^(%S*)%s*(.-)$")
	local root = ME.root
	if sub == "use" or sub == "copy" then
		local found = ME:FindProfile(name)
		if not found then
			ME:Print("No profile called '" .. name .. "'. Type /mage profile to list them.")
		elseif found == ME.profileName then
			ME:Print("That is already this character's profile.")
		elseif sub == "use" then
			root.chars[ME.charKey] = found
			ME:Print("This character now shares the profile '" .. found .. "'. /reload to apply.")
		else
			root.profiles[ME.profileName] = CopyTable(root.profiles[found])
			ME:Print("Copied '" .. found .. "' into this character's profile. /reload to apply.")
		end
	elseif sub == "reset" then
		root.profiles[ME.profileName] = {}
		ME:Print("Profile reset to defaults. /reload to apply.")
	else
		ME:Print("profiles (this character uses |cff69ccf0" .. tostring(ME.profileName) .. "|r):")
		local names = {}
		for n in pairs(root.profiles) do names[#names + 1] = n end
		table.sort(names)
		for _, n in ipairs(names) do print("  " .. n) end
		print("  /mage profile use <name> - share that profile with this character")
		print("  /mage profile copy <name> - copy its settings into this character's profile")
		print("  /mage profile reset - back to defaults")
	end
end

SLASH_MAGEEVERYTHING1 = "/mage"
SLASH_MAGEEVERYTHING2 = "/mageeverything"
SlashCmdList.MAGEEVERYTHING = slash

-- Addon compartment (minimap dropdown): left-click options, right-click portals.
function MageEverything_OnCompartmentClick(_, button)
	if not ME.active then return end
	if button == "RightButton" then ME.Portals:Toggle() else Options:Open() end
end

function Options:OnLogin()
	local ok, err = pcall(buildPanel)
	if not ok then ME:Error("options", err) end
end
