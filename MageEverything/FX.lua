-- MageEverything: self-contained visual effects (no library dependencies).
local _, ME = ...
local FX = {}
ME.FX = FX

local WHITE = "Interface\\Buttons\\WHITE8x8"
FX.WHITE = WHITE
FX.BAR = "Interface\\TargetingFrame\\UI-StatusBar"
FX.SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"

-- Spec themes: colour pairs used across the HUD and XP bar.
FX.themes = {
	ARCANE = { name = "Arcane", r = 0.72, g = 0.45, b = 1.00, r2 = 0.42, g2 = 0.22, b2 = 0.95, icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
	FIRE   = { name = "Fire",   r = 1.00, g = 0.55, b = 0.10, r2 = 0.85, g2 = 0.15, b2 = 0.05, icon = "Interface\\Icons\\Spell_Fire_FireBolt02" },
	FROST  = { name = "Frost",  r = 0.45, g = 0.85, b = 1.00, r2 = 0.15, g2 = 0.45, b2 = 0.95, icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
	NONE   = { name = "Apprentice", r = 0.41, g = 0.80, b = 0.94, r2 = 0.25, g2 = 0.50, b2 = 0.80, icon = "Interface\\Icons\\INV_Staff_13" },
}
function FX.Theme()
	return FX.themes[ME.spec or "NONE"] or FX.themes.NONE
end

-- Atlases differ between clients; only use one when the client really has it.
function FX.HasAtlas(name)
	if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
	local ok, info = pcall(C_Texture.GetAtlasInfo, name)
	return ok and info ~= nil
end

function FX.SetAtlasOr(tex, atlas, fallbackTexture)
	if atlas and FX.HasAtlas(atlas) then
		tex:SetAtlas(atlas)
		return true
	end
	if fallbackTexture then tex:SetTexture(fallbackTexture) end
	return false
end

-- 1px border made of four textures. Returns a table with :SetColor.
function FX.Border(parent, size, r, g, b, a)
	size = size or 1
	local t = {}
	for i = 1, 4 do
		local tex = parent:CreateTexture(nil, "OVERLAY")
		tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
		t[i] = tex
	end
	t[1]:SetPoint("TOPLEFT", -size, size);    t[1]:SetPoint("TOPRIGHT", size, size);     t[1]:SetHeight(size)
	t[2]:SetPoint("BOTTOMLEFT", -size, -size); t[2]:SetPoint("BOTTOMRIGHT", size, -size); t[2]:SetHeight(size)
	t[3]:SetPoint("TOPLEFT", -size, size);    t[3]:SetPoint("BOTTOMLEFT", -size, -size); t[3]:SetWidth(size)
	t[4]:SetPoint("TOPRIGHT", size, size);    t[4]:SetPoint("BOTTOMRIGHT", size, -size); t[4]:SetWidth(size)
	function t:SetColor(cr, cg, cb, ca)
		for i = 1, 4 do self[i]:SetColorTexture(cr, cg, cb, ca or 1) end
	end
	return t
end

-- Looping alpha pulse on a region. Returns the animation group.
function FX.Pulse(region, from, to, duration)
	local ag = region:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(from or 1)
	a:SetToAlpha(to or 0.3)
	a:SetDuration(duration or 0.6)
	a:SetSmoothing("IN_OUT")
	return ag
end

-- One-shot "pop": scale down from large while fading in.
function FX.Pop(frame, scale, duration)
	local ag = frame:CreateAnimationGroup()
	local s = ag:CreateAnimation("Scale")
	s:SetScaleFrom(scale or 1.5, scale or 1.5)
	s:SetScaleTo(1, 1)
	s:SetOrigin("CENTER", 0, 0)
	s:SetDuration(duration or 0.18)
	s:SetSmoothing("OUT")
	return ag
end

-- One-shot horizontal shake.
function FX.Shake(frame)
	local ag = frame:CreateAnimationGroup()
	for i, dx in ipairs({ -6, 12, -10, 8, -4 }) do
		local t = ag:CreateAnimation("Translation")
		t:SetOffset(dx, 0)
		t:SetDuration(0.04)
		t:SetOrder(i)
	end
	return ag
end

-- Slowly rotating additive ring behind an icon.
function FX.Ring(parent, size, seconds)
	local ring = parent:CreateTexture(nil, "BACKGROUND")
	ring:SetSize(size, size)
	ring:SetPoint("CENTER")
	ring:SetBlendMode("ADD")
	if not FX.SetAtlasOr(ring, "UF-Arcane-MagicCirc", nil) then
		if not FX.SetAtlasOr(ring, "Artifacts-MageArcane-BG-rune", nil) then
			ring:SetTexture("Interface\\Cooldown\\star4")
		end
	end
	local ag = ring:CreateAnimationGroup()
	ag:SetLooping("REPEAT")
	local r = ag:CreateAnimation("Rotation")
	r:SetDegrees(-360)
	r:SetDuration(seconds or 12)
	ag:Play()
	ring.spin = ag
	return ring
end

-- Shine that sweeps across a bar, clipped to the bar by a mask.
function FX.Shine(bar)
	local shine = bar:CreateTexture(nil, "OVERLAY")
	shine:SetTexture(WHITE)
	shine:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.55))
	shine:SetBlendMode("ADD")
	shine:SetPoint("TOP", bar, "TOP")
	shine:SetPoint("BOTTOM", bar, "BOTTOM")
	shine:SetWidth(60)
	shine:SetPoint("LEFT", bar, "LEFT", -60, 0)
	shine:SetAlpha(0)
	if bar.CreateMaskTexture then
		local m = bar:CreateMaskTexture()
		m:SetAllPoints(bar)
		m:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		shine:AddMaskTexture(m)
	end
	local ag = shine:CreateAnimationGroup()
	local fadeIn = ag:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.05); fadeIn:SetOrder(1)
	local tr = ag:CreateAnimation("Translation")
	tr:SetDuration(0.7); tr:SetSmoothing("IN_OUT"); tr:SetOrder(1)
	local fadeOut = ag:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.1); fadeOut:SetOrder(2)
	shine.Play = function()
		tr:SetOffset(bar:GetWidth() + 60, 0)
		ag:Stop()
		ag:Play()
	end
	return shine
end

-- Proc glow around an icon frame. Uses Blizzard's flipbook when the client
-- has it, otherwise a pulsing additive border. Returns a frame with
-- :Start(r,g,b) / :Stop().
function FX.Glow(parent)
	local f = CreateFrame("Frame", nil, parent)
	local w, h = parent:GetSize()
	f:SetPoint("TOPLEFT", -w * 0.2, h * 0.2)
	f:SetPoint("BOTTOMRIGHT", w * 0.2, -h * 0.2)
	f:SetFrameLevel(parent:GetFrameLevel() + 5)
	f:Hide()

	local tex = f:CreateTexture(nil, "OVERLAY")
	local ag
	if FX.HasAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook") then
		tex:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
		tex:SetAllPoints()
		ag = tex:CreateAnimationGroup()
		ag:SetLooping("REPEAT")
		local fb = ag:CreateAnimation("FlipBook")
		fb:SetDuration(1)
		fb:SetFlipBookRows(6)
		fb:SetFlipBookColumns(5)
		fb:SetFlipBookFrames(30)
		fb:SetFlipBookFrameWidth(0)
		fb:SetFlipBookFrameHeight(0)
	else
		tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		tex:SetBlendMode("ADD")
		tex:SetPoint("TOPLEFT", -w * 0.25, h * 0.25)
		tex:SetPoint("BOTTOMRIGHT", w * 0.25, -h * 0.25)
		ag = FX.Pulse(tex, 1, 0.25, 0.45)
	end

	function f:Start(r, g, b)
		if r then
			tex:SetDesaturated(true)
			tex:SetVertexColor(r, g, b)
		else
			tex:SetDesaturated(false)
			tex:SetVertexColor(1, 1, 1)
		end
		if not self:IsShown() then
			self:Show()
			ag:Play()
		end
	end
	function f:Stop()
		if self:IsShown() then
			ag:Stop()
			self:Hide()
		end
	end
	return f
end

-- Standard square icon: texture, dark border, cooldown swipe, optional text.
function FX.Icon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", 1, -1)
	bg:SetColorTexture(0, 0, 0, 0.9)
	f.bg = bg

	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.tex = tex

	local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.7) end
	f.cd = cd

	-- Text lives on its own frame so it draws above the cooldown swipe.
	local top = CreateFrame("Frame", nil, f)
	top:SetAllPoints()
	top:SetFrameLevel(cd:GetFrameLevel() + 2)
	f.top = top
	return f
end

-- Feed a spell's cooldown to an icon's swipe without touching the numbers.
-- Duration objects are the only cooldown input addons may use in combat.
function FX.SetSpellCooldown(icon, spellID, ignoreGCD)
	local cd = icon.cd
	if not spellID then pcall(cd.Clear, cd) return end
	if C_Spell.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
		local ok, d = pcall(C_Spell.GetSpellCooldownDuration, spellID, ignoreGCD and true or false)
		if ok and d then
			if pcall(cd.SetCooldownFromDurationObject, cd, d, true) then return end
		end
	end
	-- Fallback for when the numbers are readable (out of combat).
	local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
	if ok and info and not ME.issecret(info.startTime) and not ME.issecret(info.duration) then
		if info.duration and info.duration > 0 then
			pcall(cd.SetCooldown, cd, info.startTime, info.duration)
		else
			pcall(cd.Clear, cd)
		end
	end
end
