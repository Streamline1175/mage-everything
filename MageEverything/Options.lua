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
	check(db.xp, "showQuestXP", "Show XP from completed quests", "Gold overlay for quests ready to hand in.")
	check(db.xp, "effects", "XP bar animations", nil)
	slider(db.xp, "width", "XP bar width", nil, 200, 1200, 10, "%d")
	slider(db.xp, "height", "XP bar height", nil, 8, 32, 1, "%d")

	check(db.reminders, "enabled", "Clickable reminders", "Out-of-combat buttons for missing buffs and supplies.")
	check(db.reminders, "intellect", "Remind: Arcane Intellect", nil)
	check(db.reminders, "armor", "Remind: armor spell", nil)
	check(db.reminders, "conjure", "Remind: conjure water", nil)
	check(db.reminders, "gem", "Remind: mana gem", nil)
	check(db.reminders, "drink", "Remind: drink when low on mana", nil)

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

function Options:Diagnose()
	local p = print
	p("|cff69ccf0Mage Everything diagnostics|r")
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
	print("  /mage diag - show what the client lets the addon read")
	print("  /mage welcome - setup guide")
	print("  /mage on | off - enable or disable the addon (then /reload)")
end

local function slash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local cmd, arg = msg:match("^(%S+)%s*(.*)$")
	if msg == "on" or msg == "off" then
		MageEverythingDB.enabled = (msg == "on")
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
	elseif msg == "welcome" or msg == "guide" or msg == "setup" then
		ME.Welcome:Toggle()
	elseif msg == "diag" or msg == "debug" then
		Options:Diagnose()
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
