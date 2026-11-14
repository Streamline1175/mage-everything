-- MageEverything: WeakAuras-style proc banners.
-- An icon and label pop in above the character, shimmer, float and fade.
local _, ME = ...
local Alerts = ME:NewModule("Alerts")
local FX = ME.FX

local root
local pool, active = {}, {}

local function soundKit(name, fallbackID)
	return (SOUNDKIT and SOUNDKIT[name]) or fallbackID
end

local function create()
	local f = CreateFrame("Frame", nil, root)
	f:SetSize(260, 44)

	local icon = FX.Icon(f, 40)
	icon:SetPoint("LEFT", 0, 0)
	icon.cd:Hide()
	icon.border = FX.Border(icon, 2, 1, 1, 1, 1)
	f.icon = icon

	local glow = f:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture("Interface\\Cooldown\\star4")
	glow:SetBlendMode("ADD")
	glow:SetSize(120, 120)
	glow:SetPoint("CENTER", icon, "CENTER")
	f.glow = glow
	local spin = glow:CreateAnimationGroup()
	spin:SetLooping("REPEAT")
	local rot = spin:CreateAnimation("Rotation")
	rot:SetDegrees(360); rot:SetDuration(4)
	f.spin = spin

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetPoint("LEFT", icon, "RIGHT", 10, 6)
	f.text = text
	local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -1)
	f.sub = sub

	-- Pop in, hold, float up and fade out.
	local ag = f:CreateAnimationGroup()
	local s = ag:CreateAnimation("Scale")
	s:SetScaleFrom(1.7, 1.7); s:SetScaleTo(1, 1); s:SetOrigin("CENTER", 0, 0)
	s:SetDuration(0.18); s:SetSmoothing("OUT"); s:SetOrder(1)
	local a1 = ag:CreateAnimation("Alpha")
	a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.12); a1:SetOrder(1)
	local hold = ag:CreateAnimation("Alpha")
	hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(1.6); hold:SetOrder(2)
	local up = ag:CreateAnimation("Translation")
	up:SetOffset(0, 36); up:SetDuration(0.6); up:SetSmoothing("IN"); up:SetOrder(3)
	local a2 = ag:CreateAnimation("Alpha")
	a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.6); a2:SetOrder(3)
	ag:SetScript("OnFinished", function()
		f:Hide()
		f.spin:Stop()
		for i, x in ipairs(active) do
			if x == f then table.remove(active, i) break end
		end
		pool[#pool + 1] = f
		Alerts:Restack()
	end)
	f.anim = ag
	return f
end

function Alerts:Restack()
	for i, f in ipairs(active) do
		f:ClearAllPoints()
		f:SetPoint("BOTTOM", root, "BOTTOM", 0, (i - 1) * 50)
	end
end

-- Show a banner. `id` de-duplicates: a banner already on screen is restarted.
function Alerts:Show(id, icon, title, subtitle, r, g, b, sound)
	if not root or not ME.db.alerts.enabled then return end
	local f
	for _, x in ipairs(active) do
		if x.id == id then f = x break end
	end
	if not f then
		f = table.remove(pool) or create()
		active[#active + 1] = f
	end
	f.id = id
	f.icon.tex:SetTexture(icon)
	f.icon.border:SetColor(r, g, b, 1)
	f.glow:SetVertexColor(r, g, b, 0.9)
	f.text:SetText(title)
	f.text:SetTextColor(r, g, b)
	f.sub:SetText(subtitle or "")
	f:Show()
	f.anim:Stop()
	f.anim:Play()
	f.spin:Play()
	self:Restack()
	if sound and ME.db.alerts.sound then
		pcall(PlaySound, sound, "Master")
	end
end

local PROC_TEXT = {
	ArcaneMissiles = { "MISSILE BARRAGE", "Arcane Missiles - free and fast", "ARCANE" },
	IceLance       = { "FINGERS OF FROST", "Ice Lance now", "FROST" },
	Pyroblast      = { "HEATING UP", "Pyroblast now", "FIRE" },
}

local function themeColor(school)
	local t = FX.themes[school] or FX.Theme()
	return t.r, t.g, t.b
end

function Alerts:ApplySettings()
	if root then root:SetScale(ME.db.alerts.scale or 1) end
end

function Alerts:OnLogin()
	root = CreateFrame("Frame", "MageEverythingAlerts", UIParent)
	root:SetSize(260, 50)
	ME:MakeMovable(root, "alerts", "Proc alerts", "CENTER", 0, 150)
	self:ApplySettings()

	local procSound = soundKit("UI_70_ARTIFACT_FORGE_TRAIT_GOLD_TRAIT", 54125)

	-- Blizzard's proc-glow event.
	ME:Listen("OVERLAY", function(key, shown)
		if not shown then return end
		local p = PROC_TEXT[key]
		local r, g, b = themeColor(p and p[3])
		Alerts:Show("overlay" .. key, ME.SpellIcon(key), p and p[1] or ME.SpellLabel(key):upper(),
			p and p[2] or "Proc - use it now", r, g, b, procSound)
	end)

	-- Procs inferred from the player's own casts.
	ME:Listen("MEM_PROC", function(name)
		if name == "Frozen" then
			if ME.Known("IceLance") or ME.spec == "FROST" then
				local r, g, b = themeColor("FROST")
				Alerts:Show("frozen", ME.SpellIcon("FrostNova"), "FROZEN", "Shatter window", r, g, b)
			end
		elseif name == "HeatingUp" and not ME.state.overlay.Pyroblast then
			local r, g, b = themeColor("FIRE")
			Alerts:Show("overlayPyroblast", ME.SpellIcon("Pyroblast"), "HEATING UP", "Pyroblast now", r, g, b, procSound)
		elseif name == "ArcaneBlast4" then
			local r, g, b = themeColor("ARCANE")
			Alerts:Show("ab4", ME.SpellIcon("ArcaneBlast"), "ARCANE BLAST x4", "Full power - watch your mana", r, g, b)
		end
	end)

	-- Clearcasting has no button glow on some builds; catch it from auras
	-- whenever they are readable.
	local hadCC = false
	ME:On("UNIT_AURA", function(unit)
		if unit ~= "player" then return end
		local has = ME.HasBuff("Clearcasting") == true
		if has and not hadCC then
			local r, g, b = themeColor("ARCANE")
			Alerts:Show("clearcast", ME.SpellIcon("Clearcasting"), "CLEARCASTING", "Next spell is free", r, g, b, procSound)
		end
		hadCC = has
	end)

	ME:On("PLAYER_LEVEL_UP", function(level)
		local t = FX.Theme()
		Alerts:Show("levelup", t.icon, "LEVEL " .. tostring(level), t.name .. " Mage", 1, 0.82, 0.1)
	end)

	ME:Listen("NEW_SPELL", function(key)
		local t = FX.Theme()
		Alerts:Show("new" .. key, ME.SpellIcon(key), "NEW SPELL", ME.SpellLabel(key), t.r, t.g, t.b)
	end)
end
