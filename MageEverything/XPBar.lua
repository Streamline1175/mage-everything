-- MageEverything: spec-themed experience bar.
-- Layers (bottom to top): background, rested overlay, pending quest XP,
-- current XP with a spec gradient, spark, tick marks, animated effects.
-- XP values are never hidden by the client, so all the maths is exact.
local _, ME = ...
local XP = ME:NewModule("XPBar")
local FX = ME.FX

local root, restedBar, questBar, xpBar, spark, text, emblem, ring, shine, flash, ember, levelText
local session = { start = 0, gained = 0, kills = 0, killXP = 0, lastXP = nil, lastMax = nil, window = {} }
local WINDOW = 600 -- seconds of history used for the XP/hour estimate

local AMBIENT = {
	-- pulse duration, shine interval (seconds)
	ARCANE = { 1.6, 7 }, FIRE = { 0.35, 11 }, FROST = { 2.4, 9 }, NONE = { 2.0, 12 },
}

local function maxLevel()
	local m = GetMaxPlayerLevel and ME.Try(GetMaxPlayerLevel)
	if type(m) == "number" and m > 0 then return m end
	return 60
end

local function atCap()
	if IsXPUserDisabled and ME.Bool(ME.Try(IsXPUserDisabled)) then return true end
	return (UnitLevel("player") or 1) >= maxLevel()
end

local function questXP()
	if not (ME.db.xp.showQuestXP and C_QuestLog and C_QuestLog.GetNumQuestLogEntries and GetQuestLogRewardXP) then
		return 0
	end
	local total = 0
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and info.questID
			and ME.Bool(ME.Try(C_QuestLog.ReadyForTurnIn, info.questID)) then
			total = total + (ME.Try(GetQuestLogRewardXP, info.questID) or 0)
		end
	end
	return total
end

local function rate()
	local now = GetTime()
	local w = session.window
	while w[1] and now - w[1][1] > WINDOW do table.remove(w, 1) end
	local sum = 0
	for i = 1, #w do sum = sum + w[i][2] end
	local span = math.min(WINDOW, now - session.start)
	if span < 30 or sum <= 0 then return 0 end
	return sum / span * 3600
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function layer(level, alpha)
	local sb = CreateFrame("StatusBar", nil, root)
	sb:SetAllPoints(root)
	sb:SetFrameLevel(root:GetFrameLevel() + level)
	sb:SetStatusBarTexture(FX.BAR)
	sb:SetAlpha(alpha or 1)
	return sb
end

local function build()
	local db = ME.db.xp
	root = CreateFrame("Frame", "MageEverythingXPBar", UIParent)
	root:SetSize(db.width, db.height)
	ME:MakeMovable(root, "xp", "XP bar", "BOTTOM", 0, 6, true)

	local bg = root:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -2, 2)
	bg:SetPoint("BOTTOMRIGHT", 2, -2)
	bg:SetColorTexture(0, 0, 0, 0.8)
	root.border = FX.Border(root, 1, 0.3, 0.3, 0.3, 1)

	restedBar = layer(1, 0.35)
	questBar = layer(2, 0.55)
	xpBar = layer(3, 1)

	-- Ambient glow on the fill (speed set per spec).
	ember = xpBar:CreateTexture(nil, "ARTWORK", nil, 2)
	ember:SetTexture(FX.WHITE)
	ember:SetBlendMode("ADD")
	ember:SetAllPoints(xpBar:GetStatusBarTexture())
	ember:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.35))
	ember.pulse = FX.Pulse(ember, 0.9, 0.15, 1.6)

	spark = xpBar:CreateTexture(nil, "OVERLAY")
	spark:SetTexture(FX.SPARK)
	spark:SetBlendMode("ADD")
	spark:SetSize(20, db.height * 2.4)
	spark:SetPoint("CENTER", xpBar:GetStatusBarTexture(), "RIGHT", 0, 0)

	-- Tick marks every 10%.
	local over = CreateFrame("Frame", nil, root)
	over:SetAllPoints(root)
	over:SetFrameLevel(root:GetFrameLevel() + 6)
	root.ticks = {}
	for i = 1, 9 do
		local t = over:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0, 0, 0, 0.55)
		t:SetWidth(1)
		root.ticks[i] = t
	end

	shine = FX.Shine(over)

	flash = over:CreateTexture(nil, "OVERLAY")
	flash:SetAllPoints(root)
	flash:SetColorTexture(1, 1, 1, 1)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	local fg = flash:CreateAnimationGroup()
	local fa = fg:CreateAnimation("Alpha")
	fa:SetFromAlpha(0.9); fa:SetToAlpha(0); fa:SetDuration(1.1); fa:SetSmoothing("OUT")
	flash.anim = fg

	text = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER", root, "CENTER", 0, 0)
	text:SetShadowOffset(1, -1)

	-- Spec emblem on the left end.
	emblem = CreateFrame("Frame", nil, root)
	emblem:SetSize(db.height + 18, db.height + 18)
	emblem:SetPoint("RIGHT", root, "LEFT", -6, 0)
	emblem:SetFrameLevel(root:GetFrameLevel() + 7)
	ring = FX.Ring(emblem, (db.height + 18) * 1.9, 18)
	ring:SetAlpha(0.6)
	local ebg = emblem:CreateTexture(nil, "BORDER")
	ebg:SetPoint("TOPLEFT", -1, 1)
	ebg:SetPoint("BOTTOMRIGHT", 1, -1)
	ebg:SetColorTexture(0, 0, 0, 1)
	emblem.icon = emblem:CreateTexture(nil, "ARTWORK")
	emblem.icon:SetAllPoints()
	emblem.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	emblem.pop = FX.Pop(emblem, 1.8, 0.3)

	levelText = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	levelText:SetPoint("LEFT", root, "RIGHT", 6, 0)

	-- Tooltip with the full breakdown.
	root:EnableMouse(true)
	root:SetScript("OnEnter", function() XP:Tooltip() end)
	root:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function XP:ApplySettings()
	if not root then return end
	local db = ME.db.xp
	root:SetSize(db.width, db.height)
	for i, t in ipairs(root.ticks) do
		t:ClearAllPoints()
		t:SetPoint("TOP", root, "TOPLEFT", db.width * i / 10, 0)
		t:SetPoint("BOTTOM", root, "BOTTOMLEFT", db.width * i / 10, 0)
	end
	text:SetShown(db.showText)
	root:SetShown(db.enabled)
	self:ApplyTheme()
	self:Update()
end

function XP:ApplyTheme(animate)
	if not root then return end
	local t = FX.Theme()
	local fill = xpBar:GetStatusBarTexture()
	fill:SetVertexColor(1, 1, 1)
	fill:SetGradient("HORIZONTAL", CreateColor(t.r2, t.g2, t.b2, 1), CreateColor(t.r, t.g, t.b, 1))
	restedBar:SetStatusBarColor(t.r, t.g, t.b)
	questBar:SetStatusBarColor(1, 0.85, 0.2)
	spark:SetVertexColor(t.r, t.g, t.b)
	ring:SetVertexColor(t.r, t.g, t.b)
	root.border:SetColor(t.r2 * 0.8, t.g2 * 0.8, t.b2 * 0.8, 1)
	emblem.icon:SetTexture(t.icon)
	levelText:SetTextColor(t.r, t.g, t.b)

	local amb = AMBIENT[ME.spec] or AMBIENT.NONE
	ember.pulse:Stop()
	if ME.db.xp.effects then
		ember:Show()
		ember.pulse = FX.Pulse(ember, 0.9, 0.15, amb[1])
		ember.pulse:Play()
	else
		ember:Hide()
	end
	if animate then
		emblem.pop:Stop(); emblem.pop:Play()
		if ME.db.xp.effects then shine.Play() end
	end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
function XP:Update()
	if not root or not root:IsShown() then return end
	local t = FX.Theme()
	local level = UnitLevel("player") or 1
	levelText:SetText(tostring(level))

	if atCap() then
		for _, b in ipairs({ restedBar, questBar }) do
			b:SetMinMaxValues(0, 1); b:SetValue(0)
		end
		xpBar:SetMinMaxValues(0, 1)
		xpBar:SetValue(1)
		spark:Hide()
		text:SetText(("Level %d %s Mage"):format(level, t.name))
		return
	end

	local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
	if max <= 0 then max = 1 end
	local rested = GetXPExhaustion() or 0
	local quest = questXP()
	local smooth = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil

	restedBar:SetMinMaxValues(0, max)
	restedBar:SetValue(math.min(max, cur + rested))
	questBar:SetMinMaxValues(0, max)
	questBar:SetValue(quest > 0 and math.min(max, cur + quest) or 0)
	xpBar:SetMinMaxValues(0, max)
	if smooth then xpBar:SetValue(cur, smooth) else xpBar:SetValue(cur) end
	spark:SetShown(cur > 0)

	local parts = { ("%s / %s  (%.1f%%)"):format(ME.Comma(cur), ME.Comma(max), cur / max * 100) }
	if rested > 0 then parts[#parts + 1] = ("|cff7fd4ff+%d%% rested|r"):format(rested / max * 100 + 0.5) end
	if quest > 0 then parts[#parts + 1] = ("|cffffd933+%s quests|r"):format(ME.Short(quest)) end
	local perHour = rate()
	if perHour > 0 then
		parts[#parts + 1] = ("%s/h"):format(ME.Short(perHour))
		parts[#parts + 1] = ME.Duration((max - cur) / perHour * 3600) .. " to level"
	end
	if session.kills > 0 then
		local avg = session.killXP / session.kills
		if avg > 0 then parts[#parts + 1] = ("~%d kills"):format(math.ceil((max - cur) / avg)) end
	end
	text:SetText(table.concat(parts, "   "))
end

function XP:Tooltip()
	local t = FX.Theme()
	GameTooltip:SetOwner(root, "ANCHOR_TOP")
	GameTooltip:AddLine(t.name .. " Mage", t.r, t.g, t.b)
	local p = ME.specPoints
	GameTooltip:AddDoubleLine("Talents (Arcane / Fire / Frost)", ("%d / %d / %d"):format(p.ARCANE, p.FIRE, p.FROST), 1, 1, 1, 1, 1, 1)
	if not atCap() then
		local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
		local rested = GetXPExhaustion() or 0
		GameTooltip:AddDoubleLine("Experience", ("%s / %s"):format(ME.Comma(cur), ME.Comma(max)), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Remaining", ME.Comma(max - cur), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Rested", ME.Comma(rested), 1, 1, 1, 0.5, 0.83, 1)
		GameTooltip:AddDoubleLine("Completed quests in log", ME.Comma(questXP()), 1, 1, 1, 1, 0.85, 0.2)
		local perHour = rate()
		GameTooltip:AddDoubleLine("XP per hour", perHour > 0 and ME.Comma(perHour) or "--", 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Time to level", perHour > 0 and ME.Duration((max - cur) / perHour * 3600) or "--", 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Session XP", ME.Comma(session.gained), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Session kills", tostring(session.kills), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Session time", ME.Duration(GetTime() - session.start), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine("Shift-drag to move", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function onXP()
	local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
	if session.lastXP then
		local gained = cur - session.lastXP
		if gained < 0 then gained = gained + (session.lastMax or 0) end -- levelled up
		if gained > 0 then
			session.gained = session.gained + gained
			table.insert(session.window, { GetTime(), gained })
			if ME.db.xp.effects then shine.Play() end
		end
	end
	session.lastXP, session.lastMax = cur, max
	XP:Update()
end

local function hideBlizzardBar()
	local m = _G.StatusTrackingBarManager
	if not m then return end
	-- Same approach as ElvUI: stop its events and park it on a hidden parent.
	local hidden = CreateFrame("Frame")
	hidden:Hide()
	pcall(function()
		m:UnregisterAllEvents()
		m:SetParent(hidden)
		m:Hide()
	end)
end

function XP:OnLogin()
	session.start = GetTime()
	build()
	if ME.db.xp.enabled and ME.db.xp.hideBlizzard then hideBlizzardBar() end
	self:ApplySettings()
	onXP()

	ME:On("PLAYER_XP_UPDATE", onXP)
	ME:On("UPDATE_EXHAUSTION", function() XP:Update() end)
	ME:On("PLAYER_UPDATE_RESTING", function() XP:Update() end)
	ME:On("QUEST_LOG_UPDATE", function() XP:Update() end)
	ME:On("PLAYER_ENTERING_WORLD", function() XP:Update() end)
	ME:On("PLAYER_LEVEL_UP", function()
		if ME.db.xp.effects then
			flash.anim:Stop(); flash.anim:Play()
			emblem.pop:Stop(); emblem.pop:Play()
		end
		C_Timer.After(0.5, function() XP:Update() end)
	end)
	-- Kill XP arrives as a chat line; the first number in it is the amount.
	ME:On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
		if type(msg) ~= "string" or ME.issecret(msg) then return end
		local n = tonumber((msg:gsub("[,%.]", "")):match("(%d+)"))
		if n and n > 0 then
			session.kills = session.kills + 1
			session.killXP = session.killXP + n
		end
	end)
	ME:Listen("SPEC_CHANGED", function() XP:ApplyTheme(true); XP:Update() end)

	-- Refresh rate text, and play the per-spec ambient shine.
	C_Timer.NewTicker(10, function() XP:Update() end)
	local sinceShine = 0
	C_Timer.NewTicker(1, function()
		if not (root:IsShown() and ME.db.xp.effects) then return end
		sinceShine = sinceShine + 1
		local amb = AMBIENT[ME.spec] or AMBIENT.NONE
		if sinceShine >= amb[2] then
			sinceShine = 0
			shine.Play()
		end
	end)
end
