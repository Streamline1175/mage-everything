-- MageEverything: demo mode.
-- Plays sample content through every section (suggestions, reaction, alerts,
-- cooldowns, proc banners, XP gains, reminders, portal menu) and shows the
-- drag handles, so the layout can be arranged without being in a fight.
-- /mage demo toggles it; it ends by itself when combat starts.
local _, ME = ...
local Demo = ME:NewModule("Demo")
local FX = ME.FX

ME.demo = false

-- Scripted situations the HUD cycles through.
local STEPS = {
	{ situation = "OPENER", panic = "IceBarrier",
		queue = { { key = "Frostbolt", reason = "Open at max range" }, { key = "IceLance" }, { key = "FrostNova" } } },
	{ situation = "SHATTER", panic = "IceBlock",
		queue = { { key = "IceLance", reason = "Frozen - shatter", glow = true }, { key = "Frostbolt" }, { key = "ConeOfCold" } },
		reaction = { key = "FrostNova", reason = "Root, then step back" } },
	{ situation = "PROC", panic = "IceBlock",
		queue = { { key = "Pyroblast", reason = "Heating Up x3", glow = true }, { key = "FireBlast" }, { key = "Scorch" } },
		reaction = { key = "Counterspell", reason = "Interrupt!", glow = true } },
	{ situation = "PROC", panic = "ManaShield",
		queue = { { key = "ArcaneMissiles", reason = "Missile Barrage", glow = true }, { key = "ArcaneBlast" }, { key = "ArcaneWrath" } } },
	{ situation = "AOE x4", panic = "FrostNova",
		queue = { { key = "ConeOfCold", reason = "AoE - cone" }, { key = "Blizzard" }, { key = "ArcaneExplosion" } },
		reaction = { key = "IceBarrier", reason = "Shield" } },
	{ situation = "OOM", panic = "Blink",
		queue = { { key = "Shoot", reason = "Out of mana - wand" }, { key = "Frostbolt" } },
		reaction = { key = "Evocation", reason = "Out of mana" } },
}
local STEP_SECONDS = 2.6

local BANNERS = {
	{ "MissileBarrage", "MISSILE BARRAGE", "Arcane Missiles - free and fast", "ARCANE", "ArcaneMissiles" },
	{ "HeatingUp", "HEATING UP x3", "Pyroblast - 1.5s cast", "FIRE", "Pyroblast" },
	{ "FingersOfFrost", "FINGERS OF FROST", "Frostbolt, then Ice Lance", "FROST", "IceLance" },
	{ "Clearcasting", "CLEARCASTING", "Next damage spell is free", "ARCANE", "Clearcasting" },
	{ "Frozen", "FROZEN", "Shatter window", "FROST", "FrostNova" },
}

local started = 0
local panel, ticker, bannerIndex

-- The HUD asks for this instead of the real rotation while the demo runs.
function Demo:HUDResult()
	local i = math.floor((GetTime() - started) / STEP_SECONDS) % #STEPS + 1
	local s = STEPS[i]
	return { queue = s.queue, reaction = s.reaction, panic = s.panic, situation = s.situation, oom = false }
end

local function buildPanel()
	panel = CreateFrame("Frame", "MageEverythingDemoPanel", UIParent)
	panel:SetSize(430, 64)
	panel:SetPoint("TOP", 0, -90)
	panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.035, 0.04, 0.085, 0.95)
	FX.Border(panel, 1, 0.41, 0.8, 0.94, 1)
	local logo = panel:CreateTexture(nil, "ARTWORK")
	logo:SetSize(48, 48)
	logo:SetPoint("LEFT", 8, 0)
	logo:SetTexture(ME.LOGO)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -2)
	title:SetText("Demo mode")
	local body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	body:SetWidth(250)
	body:SetJustifyH("LEFT")
	body:SetText("Everything is playing sample content. Drag the blue boxes to arrange the sections.")
	local exit = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	exit:SetSize(96, 24)
	exit:SetPoint("RIGHT", -10, 0)
	exit:SetText("Exit demo")
	exit:SetScript("OnClick", function() Demo:Stop() end)
	panel:Hide()
end

function Demo:Start()
	if ME.demo then return end
	if InCombatLockdown() then
		ME:Print("Demo mode can't start in combat.")
		return
	end
	if not panel then buildPanel() end
	ME.demo = true
	started = GetTime()
	bannerIndex = 0
	panel:Show()
	ME:SetLocked(false, true)
	ME:Fire("DEMO", true)

	-- Sample proc banners, one after another.
	ticker = C_Timer.NewTicker(2.2, function()
		if not ME.demo or not ME.Alerts then return end
		bannerIndex = bannerIndex % #BANNERS + 1
		local b = BANNERS[bannerIndex]
		local t = FX.themes[b[4]]
		local sound = (bannerIndex == 1) and ((SOUNDKIT and SOUNDKIT.UI_70_ARTIFACT_FORGE_TRAIT_GOLD_TRAIT) or 54125) or nil
		ME.Alerts:Show("demo" .. b[1], ME.SpellIcon(b[5]), b[2], b[3], t.r, t.g, t.b, sound)
	end)
	ME:Print("Demo mode on. /mage demo (or the Exit button) to stop.")
end

function Demo:Stop(fromCombat)
	if not ME.demo then return end
	ME.demo = false
	if ticker then ticker:Cancel() ticker = nil end
	if panel then panel:Hide() end
	ME:SetLocked(true, true)
	ME:Fire("DEMO", false, fromCombat)
	ME:Print("Demo mode off. Positions saved.")
end

function Demo:Toggle()
	if ME.demo then self:Stop() else self:Start() end
end

function Demo:OnLogin()
	-- Fires just before combat lockdown, so secure frames can still be reset.
	ME:On("PLAYER_REGEN_DISABLED", function()
		if ME.demo then Demo:Stop(true) end
	end)
end
