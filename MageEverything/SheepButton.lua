-- MageEverything: clickable Polymorph timer.
--
-- A secure button (clicking it casts, so it can re-sheep in combat):
--   * counts down from your Polymorph cast,
--   * turns red and says "Re-sheep" when the sheep breaks,
--   * left-click / its keybind: Polymorph your focus if it is a live enemy,
--     otherwise your previous target (the usual "sheep, then tab to the
--     other mob" case), then switch back.
-- A second keybind, "Polymorph target and remember it", sets the target as
-- focus (and marks it with a moon) before casting, which makes re-sheeping
-- exact. Both are under Key Bindings > AddOns > Mage Everything.
local ADDON, ME = ...
local Sheep = ME:NewModule("SheepButton")
local FX = ME.FX
local S = ME.state

BINDING_HEADER_MAGEEVERYTHING = "Mage Everything"
_G["BINDING_NAME_CLICK MageEverythingSheep:LeftButton"] = "Re-sheep (focus, or previous target)"
_G["BINDING_NAME_CLICK MageEverythingSheepFocus:LeftButton"] = "Polymorph target and remember it"

local SIZE = 38
local button, remember
local brokeUntil = 0

local function polyName()
	return ME.SpellLabel("Polymorph")
end

-- Macros are secure attributes, so they are written only out of combat.
local function writeMacros()
	if InCombatLockdown() or not button then return end
	local p = polyName()
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", table.concat({
		"/cast [@focus,harm,nodead] " .. p,
		"/stopmacro [@focus,harm,nodead]",
		"/targetlasttarget",
		"/cast [harm,nodead] " .. p,
		"/targetlasttarget",
	}, "\n"))
	local lines = { "/focus [@target,harm,nodead]" }
	if ME.db.hud.markSheep then lines[#lines + 1] = "/tm 5" end
	lines[#lines + 1] = "/cast " .. p
	remember:SetAttribute("type", "macro")
	remember:SetAttribute("macrotext", table.concat(lines, "\n"))
end

local function bindingText(name)
	local key = GetBindingKey(name)
	if not key then return nil end
	key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
	return key
end

local function build()
	button = CreateFrame("Button", "MageEverythingSheep", UIParent, "SecureActionButtonTemplate")
	button:SetSize(SIZE, SIZE)
	button:RegisterForClicks("AnyUp", "AnyDown")
	ME:MakeMovable(button, "sheep", "Sheep", "CENTER", -84, -84)

	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", 1, -1)
	bg:SetColorTexture(0, 0, 0, 0.9)
	button.tex = button:CreateTexture(nil, "ARTWORK")
	button.tex:SetAllPoints()
	button.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.border = FX.Border(button, 1, 0.9, 0.5, 0.9, 1)
	button.cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cd:SetAllPoints()
	button.cd:SetDrawEdge(false)
	button.cd:SetHideCountdownNumbers(true)
	local top = CreateFrame("Frame", nil, button)
	top:SetAllPoints()
	top:SetFrameLevel(button.cd:GetFrameLevel() + 2)
	button.time = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	button.time:SetPoint("CENTER")
	button.time:SetTextColor(1, 1, 1)
	button.key = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	button.key:SetPoint("TOPRIGHT", -1, -2)
	button.label = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.label:SetPoint("BOTTOM", button, "TOP", 0, 3)
	button.pulse = FX.Pulse(button, 1, 0.35, 0.35)
	local hl = button:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.15)

	-- Note which way the click is about to cast, so the timer can follow it.
	button:HookScript("PreClick", function()
		ME.resheepClickAt = GetTime()
		local focusOK = ME.Bool(UnitExists("focus")) and ME.Bool(UnitCanAttack("player", "focus"))
			and not ME.Bool(UnitIsDead("focus"))
		ME.resheepMode = focusOK and "focus" or "last"
	end)
	button:SetScript("OnEnter", function(self)
		if self:GetAlpha() < 0.05 then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Polymorph")
		GameTooltip:AddLine("Click: re-sheep your focus, or your previous target.", 1, 1, 1, true)
		GameTooltip:AddLine("For an exact re-sheep, sheep with the 'Polymorph target and remember it' keybind (Key Bindings > AddOns).", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetAlpha(0)
	button:Hide()

	-- Keybind-only button: sets focus (and a moon marker), then sheeps.
	remember = CreateFrame("Button", "MageEverythingSheepFocus", UIParent, "SecureActionButtonTemplate")
	remember:SetSize(1, 1)
	remember:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10) -- off screen
	remember:RegisterForClicks("AnyUp", "AnyDown")
	remember:Show()
end

-- Visual state, updated a few times a second (only alpha and children
-- change in combat; showing or hiding a secure button is not allowed then).
local function render()
	if not button then return end
	local db = ME.db.hud
	local left = ME.demo and 23 or ME.SheepRemaining()
	local broke = (not ME.demo) and GetTime() < brokeUntil and S.enemies >= 1
	if not db.sheepTimer or not ME.Known("Polymorph") then
		button:SetAlpha(0)
		return
	end
	if left > 0 then
		button:SetAlpha(1)
		button.time:SetText(("%d"):format(math.ceil(left)))
		button.label:SetText("Sheep")
		if left < 6 then
			button.border:SetColor(1, 0.15, 0.15, 1)
			if not button.pulse:IsPlaying() then button.pulse:Play() end
		else
			button.border:SetColor(0.9, 0.5, 0.9, 1)
			button.pulse:Stop()
		end
	elseif broke then
		button:SetAlpha(1)
		button.time:SetText("!")
		button.label:SetText("|cffff4040Re-sheep|r")
		button.border:SetColor(1, 0.15, 0.15, 1)
		if not button.pulse:IsPlaying() then button.pulse:Play() end
	else
		button.pulse:Stop()
		button:SetAlpha(0)
	end
	button.key:SetText(bindingText("CLICK MageEverythingSheep:LeftButton") or "")
end

function Sheep:OnLogin()
	build()
	button.tex:SetTexture(ME.SpellIcon("Polymorph"))
	writeMacros()

	-- Out of combat the button exists only while a sheep is up; at the start
	-- of a fight it is shown (still invisible) so it can be used during it.
	local function syncShown()
		if InCombatLockdown() then return end
		local want = ME.Known("Polymorph") and ME.db.hud.sheepTimer
			and (ME.SheepRemaining() > 0 or ME.demo or not ME.db.locked)
		button:SetShown(want and true or false)
	end
	ME:On("PLAYER_REGEN_DISABLED", function()
		if ME.Known("Polymorph") and ME.db.hud.sheepTimer then button:Show() end
	end)
	ME:On("PLAYER_REGEN_ENABLED", function()
		brokeUntil = 0
		writeMacros()
		syncShown()
	end)
	ME:Listen("SPELLS_UPDATED", function()
		button.tex:SetTexture(ME.SpellIcon("Polymorph"))
		writeMacros()
		syncShown()
	end)
	ME:Listen("LOCK_CHANGED", syncShown)
	ME:Listen("DEMO", syncShown)
	ME:Listen("SHEEP", function(duration)
		brokeUntil = 0
		pcall(button.cd.SetCooldown, button.cd, GetTime(), duration)
		syncShown()
	end)
	ME:Listen("SHEEP_BROKE", function()
		brokeUntil = GetTime() + 12
		pcall(button.cd.Clear, button.cd)
	end)
	ME:Listen("SHEEP_ENDED", function()
		brokeUntil = 0
		pcall(button.cd.Clear, button.cd)
		syncShown()
	end)
	C_Timer.NewTicker(0.2, function()
		local ok, err = pcall(render)
		if not ok then ME:Error("sheep", err) end
	end)
	syncShown()
end

function Sheep:ApplySettings()
	writeMacros()
end
