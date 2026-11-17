-- MageEverything: sparkle effects on the herb / ore interact icon.
--
-- With "Show an icon over herbs and ore" on, the game gives the node in
-- front of you a nameplate carrying a small interact icon. Addons cannot
-- touch the node itself, but they can draw around that nameplate. This adds:
--   * a bigger copy of the icon,
--   * a slowly turning starburst and rune ring behind it,
--   * sparkles drifting up around it,
--   * gold while the node is out of reach, green once you can gather it,
--     with the Interact key shown.
local _, ME = ...
local Nodes = ME:NewModule("Nodes")
local FX = ME.FX

local STAR = "Interface\\Cooldown\\star4"
local fxFrame, icon, burst, ring, glow, label, sparkles = nil, nil, nil, nil, nil, nil, {}
local current -- the nameplate the effects are attached to

local OUT_OF_REACH = { 1, 0.78, 0.25 }
local IN_REACH = { 0.35, 1, 0.45 }

local function enabled()
	local db = ME.db.qol
	return db.nodeIcons and db.nodeFX
end

-- The nameplate frame of the soft-interact target, or nil.
local function softInteractPlate()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	if not ME.Bool(UnitExists("softinteract")) and not ME.Bool(ME.Try(UnitIsGameObject, "softinteract")) then
		return nil
	end
	if ME.db.qol.nodeFXObjectsOnly and not ME.Bool(ME.Try(UnitIsGameObject, "softinteract")) then
		return nil -- an NPC, not a herb / ore / chest
	end
	local plate = ME.Try(C_NamePlate.GetNamePlateForUnit, "softinteract")
	if plate then return plate end
	for i = 1, 60 do
		local unit = "nameplate" .. i
		if ME.Bool(UnitExists(unit)) and ME.Bool(UnitIsUnit(unit, "softinteract")) then
			return ME.Try(C_NamePlate.GetNamePlateForUnit, unit)
		end
	end
end

local function build()
	fxFrame = CreateFrame("Frame", "MageEverythingNodeFX", UIParent)
	fxFrame:SetSize(40, 40)
	fxFrame:SetFrameStrata("BACKGROUND")
	fxFrame:Hide()

	glow = fxFrame:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(FX.SPARK)
	glow:SetBlendMode("ADD")
	glow:SetPoint("CENTER")
	glow.pulse = FX.Pulse(glow, 0.9, 0.35, 0.9)

	burst = fxFrame:CreateTexture(nil, "BORDER")
	burst:SetTexture(STAR)
	burst:SetBlendMode("ADD")
	burst:SetPoint("CENTER")
	local ag = burst:CreateAnimationGroup()
	ag:SetLooping("REPEAT")
	local r = ag:CreateAnimation("Rotation")
	r:SetDegrees(360)
	r:SetDuration(6)
	burst.spin = ag

	ring = FX.Ring(fxFrame, 80, 10)
	ring:SetDrawLayer("BORDER", 1)
	ring:SetAlpha(0.55)

	icon = fxFrame:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER")
	icon.pop = FX.Pop(fxFrame, 1.7, 0.3)

	label = fxFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOP", fxFrame, "BOTTOM", 0, -2)
	label:SetShadowOffset(1, -1)

	for i = 1, 8 do
		local s = fxFrame:CreateTexture(nil, "OVERLAY")
		s:SetTexture(STAR)
		s:SetBlendMode("ADD")
		s:SetAlpha(0)
		local g = s:CreateAnimationGroup()
		local tr = g:CreateAnimation("Translation")
		tr:SetSmoothing("OUT")
		local a1 = g:CreateAnimation("Alpha")
		a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.25)
		local a2 = g:CreateAnimation("Alpha")
		a2:SetFromAlpha(1); a2:SetToAlpha(0)
		local rot = g:CreateAnimation("Rotation")
		s.anim, s.move, s.fade, s.rot = g, tr, a2, rot
		sparkles[i] = s
	end
end

function Nodes:ApplySettings()
	if not fxFrame then return end
	local size = ME.db.qol.nodeFXSize or 36
	fxFrame:SetSize(size, size)
	icon:SetSize(size, size)
	glow:SetSize(size * 2.6, size * 2.6)
	burst:SetSize(size * 2.4, size * 2.4)
	ring:SetSize(size * 2.1, size * 2.1)
	self:Refresh()
end

local nextSparkle = 1
local function sparkle()
	local s = sparkles[nextSparkle]
	nextSparkle = nextSparkle % #sparkles + 1
	if s.anim:IsPlaying() then return end
	local size = ME.db.qol.nodeFXSize or 36
	local life = 1.0 + math.random() * 0.8
	local px = (math.random() - 0.5) * size * 1.6
	local d = math.random(6, 11)
	s:ClearAllPoints()
	s:SetSize(d, d)
	s:SetPoint("CENTER", fxFrame, "CENTER", px, (math.random() - 0.3) * size * 0.6)
	local c = fxFrame.inReach and IN_REACH or OUT_OF_REACH
	if math.random() < 0.3 then s:SetVertexColor(1, 1, 1) else s:SetVertexColor(c[1], c[2], c[3]) end
	s.move:SetOffset((math.random() - 0.5) * 14, size * (0.6 + math.random() * 0.6))
	s.move:SetDuration(life)
	s.fade:SetStartDelay(life * 0.5)
	s.fade:SetDuration(life * 0.5)
	s.rot:SetDegrees(math.random() < 0.5 and -180 or 180)
	s.rot:SetDuration(life)
	s.anim:Play()
end

local function setColor(inReach)
	fxFrame.inReach = inReach
	local c = inReach and IN_REACH or OUT_OF_REACH
	glow:SetVertexColor(c[1], c[2], c[3])
	burst:SetVertexColor(c[1], c[2], c[3])
	ring:SetVertexColor(c[1], c[2], c[3])
	if inReach then
		local key = GetBindingKey("INTERACTTARGET")
		label:SetText(key and ("|cff59ff73Press " .. key .. "|r") or "|cff59ff73In reach|r")
	else
		label:SetText("")
	end
end

function Nodes:Detach()
	current = nil
	if fxFrame then
		burst.spin:Stop()
		glow.pulse:Stop()
		fxFrame:Hide()
	end
end

function Nodes:Attach(plate)
	-- Anchored (not parented) to the game's nameplate, so nothing of ours
	-- runs inside Blizzard's frame.
	local uf = rawget(plate, "UnitFrame")
	local target = (type(uf) == "table" and type(rawget(uf, "SoftTargetFrame")) == "table") and uf.SoftTargetFrame or plate
	fxFrame:ClearAllPoints()
	fxFrame:SetPoint("CENTER", target, "CENTER", 0, 0)
	if not ME.Try(SetUnitCursorTexture, icon, "softinteract", nil, true) then
		icon:SetTexture("Interface\\Icons\\INV_Misc_Flower_02")
	end
	if current ~= plate then
		icon.pop:Stop()
		icon.pop:Play()
		if ME.db.qol.nodeFXSound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 878, "SFX") end
	end
	current = plate
	fxFrame:Show()
	if not burst.spin:IsPlaying() then burst.spin:Play() end
	if not glow.pulse:IsPlaying() then glow.pulse:Play() end
end

function Nodes:Refresh()
	if not fxFrame then return end
	if not enabled() then self:Detach() return end
	local plate = softInteractPlate()
	if not plate then self:Detach() return end
	local ok = pcall(self.Attach, self, plate)
	if not ok then self:Detach() end
end

function Nodes:OnLogin()
	build()
	self:ApplySettings()
	ME:On("PLAYER_SOFT_INTERACT_CHANGED", function() Nodes:Refresh() end)
	ME:On("NAME_PLATE_UNIT_ADDED", function() Nodes:Refresh() end)
	ME:On("NAME_PLATE_UNIT_REMOVED", function() Nodes:Refresh() end)
	local since = 0
	C_Timer.NewTicker(0.15, function()
		if not current or not fxFrame:IsShown() then return end
		-- The nameplate may have been reused or hidden.
		if not current:IsShown() then Nodes:Refresh() return end
		local inReach = ME.Bool(ME.Try(UnitIsInInteractRange, "softinteract"))
		if inReach ~= fxFrame.inReach then setColor(inReach) end
		since = since + 0.15
		if since >= (inReach and 0.15 or 0.3) then
			since = 0
			sparkle()
		end
	end)
	setColor(false)
end
