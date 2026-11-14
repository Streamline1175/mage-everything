-- MageEverything: cooldown row for the mage toolkit.
-- Swipes are driven by duration objects (allowed in combat); the "ready"
-- flash uses the never-secret isActive flag.
local _, ME = ...
local CDs = ME:NewModule("Cooldowns")
local FX = ME.FX

local TRACKED = {
	"FrostNova", "FireBlast", "IceLance", "ConeOfCold", "BlastWave", "ArcaneWrath",
	"Counterspell", "Blink", "IceBarrier", "IceBlock", "ColdSnap",
	"Combustion", "ArcanePower", "PresenceOfMind", "Evocation",
}

local root
local icons = {}
local SIZE, GAP = 28, 3

local function acquire(i)
	local icon = icons[i]
	if icon then return icon end
	icon = FX.Icon(root, SIZE)
	icon.border = FX.Border(icon, 1, 0, 0, 0, 1)
	icon.pop = FX.Pop(icon, 1.6, 0.25)
	local flash = icon.top:CreateTexture(nil, "OVERLAY")
	flash:SetAllPoints()
	flash:SetColorTexture(1, 1, 1, 1)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	local ag = flash:CreateAnimationGroup()
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(0.8); a:SetToAlpha(0); a:SetDuration(0.45)
	icon.flash = ag
	icons[i] = icon
	return icon
end

function CDs:Layout()
	if not root then return end
	local n = 0
	local seenShared = false
	for _, key in ipairs(TRACKED) do
		local show = ME.Known(key)
		-- Fire Blast and Ice Lance share one cooldown: show a single icon.
		if show and (key == "FireBlast" or key == "IceLance") then
			if seenShared then show = false end
			seenShared = seenShared or show
		end
		if show then
			n = n + 1
			local icon = acquire(n)
			icon.key = key
			icon.wasActive = nil
			icon.tex:SetTexture(ME.SpellIcon(key))
			icon:ClearAllPoints()
			icon:SetPoint("LEFT", root, "LEFT", (n - 1) * (SIZE + GAP), 0)
			icon:Show()
		end
	end
	for i = n + 1, #icons do icons[i]:Hide() end
	root:SetWidth(math.max(SIZE, n * (SIZE + GAP) - GAP))
	root.count = n
	self:Update()
end

function CDs:Update()
	if not root or not root:IsShown() then return end
	local theme = FX.Theme()
	for i = 1, root.count or 0 do
		local icon = icons[i]
		local id = ME.Spell(icon.key)
		if id then
			FX.SetSpellCooldown(icon, id, true)
			local cd = ME.Try(C_Spell.GetSpellCooldown, id)
			local active = false
			if cd then
				local a = cd.isActive
				if a ~= nil and not ME.issecret(a) then
					active = a and not ME.Bool(cd.isOnGCD)
				else
					local d = ME.Plain(cd.duration)
					active = d ~= nil and d > 1.6
				end
			end
			icon.tex:SetDesaturated(active)
			icon:SetAlpha(active and 0.75 or 1)
			if icon.wasActive and not active then
				-- Came off cooldown: flash and pop.
				icon.border:SetColor(theme.r, theme.g, theme.b, 1)
				icon.pop:Stop(); icon.pop:Play()
				icon.flash:Stop(); icon.flash:Play()
			elseif active then
				icon.border:SetColor(0, 0, 0, 1)
			end
			icon.wasActive = active
		end
	end
end

function CDs:ApplySettings()
	if not root then return end
	root:SetScale(ME.db.cooldowns.scale or 1)
	root:SetShown(ME.db.cooldowns.enabled)
end

function CDs:OnLogin()
	root = CreateFrame("Frame", "MageEverythingCooldowns", UIParent)
	root:SetSize(SIZE, SIZE)
	ME:MakeMovable(root, "cooldowns", "Cooldowns", "CENTER", 0, -262)
	self:ApplySettings()
	self:Layout()

	ME:Listen("SPELLS_UPDATED", function() CDs:Layout() end)
	ME:On("SPELL_UPDATE_COOLDOWN", function() CDs:Update() end)
	ME:On("SPELL_UPDATE_USABLE", function() CDs:Update() end)
	-- Catch cooldowns ending between events.
	C_Timer.NewTicker(0.25, function() CDs:Update() end)
end
