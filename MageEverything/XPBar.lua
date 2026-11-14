-- MageEverything: spec-themed experience bar.
--
-- Layers (bottom to top): background, rested overlay, pending quest XP,
-- current XP with a spec gradient, energy flowing through the fill, an orb
-- at the leading edge, tick marks, drifting motes, text.
-- XP values are never hidden by the client, so all the maths is exact.
local _, ME = ...
local XP = ME:NewModule("XPBar")
local FX = ME.FX

local STAR = "Interface\\Cooldown\\star4"

local root, restedBar, questBar, xpBar, fillClip, over, fxFrame
local text, plateL, plateR, detail, emblem, rings, shine, flash, orb
local waves, motes, gains = {}, {}, {}
local session = { start = 0, gained = 0, kills = 0, killXP = 0, lastXP = nil, lastMax = nil, window = {}, recent = {} }
local RECENT_KILLS = 10 -- kills averaged for the "kills to level" estimate
local WINDOW = 600 -- seconds of history used for the XP/hour estimate
local fraction = 0  -- filled share of the bar, for placing effects
local demoXP        -- { cur, max, rested, quest } while demo mode runs

-- Per-tree character of the effects.
--   wave: seconds for energy to cross the bar     mote: seconds between motes
--   rise: pixels a mote travels (negative falls)  life: mote lifetime
--   breathe: glow pulse seconds                   shine: seconds between sweeps
local STYLE = {
	ARCANE = { wave = 3.2, mote = 0.45, rise = 26,  life = 2.2, breathe = 1.8, shine = 7,  spin = 6 },
	FIRE   = { wave = 1.6, mote = 0.22, rise = 34,  life = 1.2, breathe = 0.5, shine = 10, spin = 3 },
	FROST  = { wave = 4.6, mote = 0.55, rise = -20, life = 3.0, breathe = 2.6, shine = 9,  spin = 10 },
	NONE   = { wave = 3.6, mote = 0.70, rise = 22,  life = 2.2, breathe = 2.2, shine = 12, spin = 8 },
}
local function style() return STYLE[ME.spec] or STYLE.NONE end

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

-- Kills left at the pace of the last few kills. Uses each kill's base XP
-- (without the rested bonus) and then applies the rested pool properly:
-- while rested lasts a kill is worth double, afterwards single.
local function killsToLevel(remaining, rested)
	local n = #session.recent
	if n == 0 then return nil end
	local sum = 0
	for i = 1, n do sum = sum + session.recent[i] end
	local base = sum / n
	if base <= 0 then return nil end
	local restedKills = math.floor((rested or 0) / base)
	if remaining <= restedKills * 2 * base then
		return math.ceil(remaining / (2 * base)), base
	end
	return restedKills + math.ceil((remaining - restedKills * 2 * base) / base), base
end

local function hex(t) return ("%02x%02x%02x"):format(t.r * 255, t.g * 255, t.b * 255) end

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
local function outlined(parent, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	local path = GameFontNormal and GameFontNormal.GetFont and GameFontNormal:GetFont()
	fs:SetFont(type(path) == "string" and path or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
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

local function spinner(tex, seconds, direction)
	local ag = tex:CreateAnimationGroup()
	ag:SetLooping("REPEAT")
	local r = ag:CreateAnimation("Rotation")
	r:SetDegrees(360 * (direction or 1))
	r:SetDuration(seconds)
	tex.spin, tex.spinAnim = ag, r
	return ag
end

local function build()
	local db = ME.db.xp
	root = CreateFrame("Frame", "MageEverythingXPBar", UIParent)
	root:SetSize(db.width, db.height)
	ME:MakeMovable(root, "xp", "XP bar", "BOTTOM", 0, 6, true)

	local bg = root:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -2, 2)
	bg:SetPoint("BOTTOMRIGHT", 2, -2)
	bg:SetColorTexture(0.01, 0.01, 0.03, 0.88)
	root.border = FX.Border(root, 1, 0.3, 0.3, 0.3, 1)

	restedBar = layer(1, 0.35)
	questBar = layer(2, 0.55)
	xpBar = layer(3, 1)
	-- A flat, bright fill texture so the spec gradient is not dulled.
	xpBar:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
	local fill = xpBar:GetStatusBarTexture()

	-- Energy flowing through the fill: soft bands of light travel left to
	-- right, clipped to the filled part of the bar.
	fillClip = CreateFrame("Frame", nil, xpBar)
	fillClip:SetAllPoints(fill)
	fillClip:SetFrameLevel(xpBar:GetFrameLevel() + 1)
	if fillClip.SetClipsChildren then fillClip:SetClipsChildren(true) end
	for i = 1, 3 do
		local w = fillClip:CreateTexture(nil, "ARTWORK")
		w:SetTexture(FX.SPARK)
		w:SetBlendMode("ADD")
		w:SetAlpha(i == 1 and 0.55 or 0.3)
		local ag = w:CreateAnimationGroup()
		ag:SetLooping("REPEAT")
		local tr = ag:CreateAnimation("Translation")
		w.anim, w.move = ag, tr
		waves[i] = w
	end
	-- Slow sheen across the top half of the fill.
	local sheen = fillClip:CreateTexture(nil, "ARTWORK", nil, 1)
	sheen:SetTexture(FX.WHITE)
	sheen:SetBlendMode("ADD")
	sheen:SetPoint("TOPLEFT", fill, "TOPLEFT")
	sheen:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
	sheen:SetHeight(math.max(2, db.height * 0.45))
	sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.10))
	root.sheen = sheen
	root.sheenPulse = FX.Pulse(sheen, 1, 0.35, 1.8)

	-- Overlay frame for ticks, shine, orb and text.
	over = CreateFrame("Frame", nil, root)
	over:SetAllPoints(root)
	over:SetFrameLevel(root:GetFrameLevel() + 6)
	root.ticks = {}
	for i = 1, 9 do
		local t = over:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(0, 0, 0, 0.5)
		t:SetWidth(1)
		root.ticks[i] = t
	end

	shine = FX.Shine(over)

	-- Orb at the leading edge: two counter-rotating stars and a pulsing core.
	orb = CreateFrame("Frame", nil, over)
	orb:SetSize(8, 8)
	orb:SetPoint("CENTER", fill, "RIGHT", 0, 0)
	orb.a = orb:CreateTexture(nil, "OVERLAY")
	orb.a:SetTexture(STAR); orb.a:SetBlendMode("ADD"); orb.a:SetPoint("CENTER")
	orb.b = orb:CreateTexture(nil, "OVERLAY")
	orb.b:SetTexture(STAR); orb.b:SetBlendMode("ADD"); orb.b:SetPoint("CENTER"); orb.b:SetAlpha(0.7)
	orb.core = orb:CreateTexture(nil, "OVERLAY", nil, 1)
	orb.core:SetTexture(FX.SPARK); orb.core:SetBlendMode("ADD"); orb.core:SetPoint("CENTER")
	spinner(orb.a, 6, 1)
	spinner(orb.b, 9, -1)
	orb.pulse = FX.Pulse(orb.core, 1, 0.45, 0.7)
	orb.pop = FX.Pop(orb, 2.4, 0.35)
	-- The leading-edge orb is switched off (it was distracting); the frame
	-- stays so the code that positions effects around it keeps working.
	orb:Hide()

	flash = over:CreateTexture(nil, "OVERLAY", nil, 2)
	flash:SetAllPoints(root)
	flash:SetColorTexture(1, 1, 1, 1)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	local fg = flash:CreateAnimationGroup()
	local fa = fg:CreateAnimation("Alpha")
	fa:SetFromAlpha(0.9); fa:SetToAlpha(0); fa:SetDuration(1.1); fa:SetSmoothing("OUT")
	flash.anim = fg

	-- Text on its own frame above every effect, with a dark plate behind it
	-- that fades out to both sides so it reads over any fill colour.
	local textFrame = CreateFrame("Frame", nil, root)
	textFrame:SetAllPoints(root)
	textFrame:SetFrameLevel(root:GetFrameLevel() + 12)
	plateL = textFrame:CreateTexture(nil, "ARTWORK")
	plateL:SetTexture(FX.WHITE)
	plateL:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.42))
	plateL:SetPoint("TOP", root, "TOP", 0, 0)
	plateL:SetPoint("BOTTOM", root, "BOTTOM", 0, 0)
	plateL:SetPoint("RIGHT", root, "CENTER", 0, 0)
	plateR = textFrame:CreateTexture(nil, "ARTWORK")
	plateR:SetTexture(FX.WHITE)
	plateR:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.42), CreateColor(0, 0, 0, 0))
	plateR:SetPoint("TOP", root, "TOP", 0, 0)
	plateR:SetPoint("BOTTOM", root, "BOTTOM", 0, 0)
	plateR:SetPoint("LEFT", root, "CENTER", 0, 0)

	text = outlined(textFrame, 12)
	text:SetPoint("CENTER", root, "CENTER", 0, 0)
	detail = outlined(textFrame, 11)
	detail:SetPoint("BOTTOM", root, "TOP", 0, 7)

	-- Motes drift off the filled part of the bar; floating "+XP" numbers.
	fxFrame = CreateFrame("Frame", nil, root)
	fxFrame:SetAllPoints(root)
	fxFrame:SetFrameLevel(root:GetFrameLevel() + 9)
	for i = 1, 14 do
		local m = fxFrame:CreateTexture(nil, "OVERLAY")
		m:SetTexture(STAR)
		m:SetBlendMode("ADD")
		m:SetAlpha(0)
		local ag = m:CreateAnimationGroup()
		local tr = ag:CreateAnimation("Translation")
		tr:SetSmoothing("OUT")
		local a1 = ag:CreateAnimation("Alpha")
		a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.3)
		local a2 = ag:CreateAnimation("Alpha")
		a2:SetFromAlpha(1); a2:SetToAlpha(0)
		local rot = ag:CreateAnimation("Rotation")
		m.anim, m.move, m.fadeOut, m.rot = ag, tr, a2, rot
		motes[i] = m
	end
	for i = 1, 4 do
		local g = outlined(textFrame, 13)
		g:SetAlpha(0)
		local ag = g:CreateAnimationGroup()
		local tr = ag:CreateAnimation("Translation")
		tr:SetOffset(0, 30); tr:SetDuration(1.6); tr:SetSmoothing("OUT")
		local a1 = ag:CreateAnimation("Alpha")
		a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.15)
		local a2 = ag:CreateAnimation("Alpha")
		a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetStartDelay(0.9); a2:SetDuration(0.7)
		g.anim = ag
		gains[i] = g
	end

	-- Spec emblem on the left end with two counter-rotating rings.
	emblem = CreateFrame("Frame", nil, root)
	emblem:SetFrameLevel(root:GetFrameLevel() + 7)
	rings = { FX.Ring(emblem, 60, 18), FX.Ring(emblem, 44, 11) }
	rings[1]:SetAlpha(0.6)
	rings[2]:SetAlpha(0.4)
	rings[2].spin:Stop()
	spinner(rings[2], 11, 1):Play()
	local ebg = emblem:CreateTexture(nil, "BORDER")
	ebg:SetPoint("TOPLEFT", -1, 1)
	ebg:SetPoint("BOTTOMRIGHT", 1, -1)
	ebg:SetColorTexture(0, 0, 0, 1)
	emblem.icon = emblem:CreateTexture(nil, "ARTWORK")
	emblem.icon:SetAllPoints()
	emblem.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	emblem.border = FX.Border(emblem, 1, 1, 1, 1, 1)
	emblem.pop = FX.Pop(emblem, 1.8, 0.3)

	-- Tooltip with the full breakdown.
	root:SetScript("OnEnter", function() XP:Tooltip() end)
	root:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------
local function restartWaves()
	local db = ME.db.xp
	local st = style()
	local band = math.max(70, db.width * 0.22)
	for i, w in ipairs(waves) do
		w.anim:Stop()
		w:ClearAllPoints()
		w:SetSize(band, db.height * 2.6)
		w:SetPoint("CENTER", root, "LEFT", -band, 0)
		w.move:SetOffset(db.width + band * 2, 0)
		w.move:SetDuration(st.wave * (1 + (i - 1) * 0.37))
		w.move:SetStartDelay((i - 1) * st.wave * 0.31)
		if db.effects then
			w:Show()
			w.anim:Play()
		else
			w:Hide()
		end
	end
end

local nextMote = 1
-- Launch one mote from `x` pixels along the bar (random within the fill when nil).
local function emitMote(x, burst)
	if not root:IsShown() then return end
	local db = ME.db.xp
	local st, t = style(), FX.Theme()
	local m = motes[nextMote]
	nextMote = nextMote % #motes + 1
	if m.anim:IsPlaying() then
		if not burst then return end
		m.anim:Stop()
	end
	local filled = math.max(8, db.width * fraction)
	x = x or (math.random() * filled)
	local size = burst and math.random(10, 18) or math.random(6, 12)
	local life = st.life * (0.7 + math.random() * 0.6) * (burst and 0.7 or 1)
	local dy = st.rise * (0.6 + math.random() * 0.8) * (burst and 1.5 or 1)
	local dx = (math.random() - 0.5) * (burst and 70 or 22)
	m:ClearAllPoints()
	m:SetSize(size, size)
	m:SetPoint("CENTER", root, st.rise < 0 and "TOPLEFT" or "BOTTOMLEFT", x, st.rise < 0 and 2 or (db.height * 0.5))
	-- Mostly the spec colour, with the odd white-hot one.
	if math.random() < 0.25 then m:SetVertexColor(1, 1, 1) else m:SetVertexColor(t.r, t.g, t.b) end
	m.move:SetOffset(dx, dy)
	m.move:SetDuration(life)
	m.fadeOut:SetStartDelay(life * 0.45)
	m.fadeOut:SetDuration(life * 0.55)
	m.rot:SetDegrees((math.random() < 0.5 and -1 or 1) * 180)
	m.rot:SetDuration(life)
	m.anim:Play()
end

local function burstAtOrb(n)
	local x = ME.db.xp.width * fraction
	for _ = 1, n do emitMote(x, true) end
	orb.pop:Stop()
	orb.pop:Play()
end

local nextGain = 1
local function floatGain(amount)
	local g = gains[nextGain]
	nextGain = nextGain % #gains + 1
	local t = FX.Theme()
	g.anim:Stop()
	g:ClearAllPoints()
	g:SetPoint("BOTTOM", root, "TOPLEFT", math.max(30, ME.db.xp.width * fraction), 4)
	g:SetText(("+%s XP"):format(ME.Comma(amount)))
	g:SetTextColor(math.min(1, t.r + 0.25), math.min(1, t.g + 0.25), math.min(1, t.b + 0.25))
	g.anim:Play()
end

---------------------------------------------------------------------------
-- Settings and theme
---------------------------------------------------------------------------
function XP:ApplySettings()
	if not root then return end
	local db = ME.db.xp
	root:SetSize(db.width, db.height)
	for i, t in ipairs(root.ticks) do
		t:ClearAllPoints()
		t:SetPoint("TOP", root, "TOPLEFT", db.width * i / 10, 0)
		t:SetPoint("BOTTOM", root, "BOTTOMLEFT", db.width * i / 10, 0)
	end
	local e = db.height + 20
	emblem:SetSize(e, e)
	emblem:ClearAllPoints()
	emblem:SetPoint("RIGHT", root, "LEFT", -8, 0)
	rings[1]:SetSize(e * 2.0, e * 2.0)
	rings[2]:SetSize(e * 1.5, e * 1.5)
	local o = db.height * 2.2
	orb.a:SetSize(o, o)
	orb.b:SetSize(o * 0.75, o * 0.75)
	orb.core:SetSize(o * 0.9, o * 1.5)
	root.sheen:SetHeight(math.max(2, db.height * 0.45))

	text:SetShown(db.showText)
	plateL:SetShown(db.showText)
	plateR:SetShown(db.showText)
	detail:SetShown(db.showText and db.showDetail)
	root:SetShown(db.enabled)
	self:ApplyTheme()
	self:Update()
end

function XP:ApplyTheme(animate)
	if not root then return end
	local db = ME.db.xp
	local t, st = FX.Theme(), style()
	local fill = xpBar:GetStatusBarTexture()
	fill:SetVertexColor(1, 1, 1)
	fill:SetGradient("HORIZONTAL", CreateColor(t.r2, t.g2, t.b2, 1), CreateColor(t.r, t.g, t.b, 1))
	restedBar:SetStatusBarColor(t.r, t.g, t.b)
	questBar:SetStatusBarColor(1, 0.85, 0.2)
	root.border:SetColor(t.r * 0.7, t.g * 0.7, t.b * 0.7, 1)
	emblem.border:SetColor(t.r, t.g, t.b, 1)
	emblem.icon:SetTexture(t.icon)
	rings[1]:SetVertexColor(t.r, t.g, t.b)
	rings[2]:SetVertexColor(t.r2, t.g2, t.b2)
	orb.a:SetVertexColor(t.r, t.g, t.b)
	orb.b:SetVertexColor(1, 1, 1)
	orb.core:SetVertexColor(t.r, t.g, t.b)
	for _, w in ipairs(waves) do w:SetVertexColor(math.min(1, t.r + 0.3), math.min(1, t.g + 0.3), math.min(1, t.b + 0.3)) end

	-- Restart everything whose speed depends on the tree.
	orb.a.spinAnim:SetDuration(st.spin)
	orb.b.spinAnim:SetDuration(st.spin * 1.5)
	root.sheenPulse:Stop()
	orb.a.spin:Stop(); orb.b.spin:Stop(); orb.pulse:Stop()
	local fxOn = db.effects
	for _, r in ipairs({ root.sheen, orb.a, orb.b }) do r:SetShown(fxOn) end
	fxFrame:SetShown(fxOn)
	if fxOn then
		root.sheenPulse:Play()

	end
	restartWaves()

	if animate then
		emblem.pop:Stop(); emblem.pop:Play()
		if fxOn then
			shine.Play()
			burstAtOrb(8)
		end
	end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
local function setMainText(str)
	text:SetText(str)
	local half = (ME.Plain(text:GetStringWidth(), 0) or 0) / 2 + 36
	plateL:SetWidth(half)
	plateR:SetWidth(half)
end

function XP:Update()
	if not root or not root:IsShown() then return end
	local t = FX.Theme()
	local level = UnitLevel("player") or 1

	if atCap() and not demoXP then
		for _, b in ipairs({ restedBar, questBar }) do
			b:SetMinMaxValues(0, 1); b:SetValue(0)
		end
		xpBar:SetMinMaxValues(0, 1)
		xpBar:SetValue(1)
		fraction = 1
		orb:Hide()
		setMainText(("Level %d  |cff%s%s Mage|r"):format(level, hex(t), t.name))
		detail:SetText("")
		return
	end

	local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
	if max <= 0 then max = 1 end
	local rested = GetXPExhaustion() or 0
	local quest = questXP()
	if demoXP then cur, max, rested, quest = demoXP.cur, demoXP.max, demoXP.rested, demoXP.quest end
	local smooth = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
	fraction = cur / max

	restedBar:SetMinMaxValues(0, max)
	restedBar:SetValue(math.min(max, cur + rested))
	questBar:SetMinMaxValues(0, max)
	questBar:SetValue(quest > 0 and math.min(max, cur + quest) or 0)
	xpBar:SetMinMaxValues(0, max)
	if smooth then xpBar:SetValue(cur, smooth) else xpBar:SetValue(cur) end

	setMainText(("|cff%sLevel %d|r   %s / %s   |cff%s%.1f%%|r"):format(
		hex(t), level, ME.Comma(cur), ME.Comma(max), hex(t), cur / max * 100))

	local parts = {}
	-- Only worth showing once it rounds to at least 1% of the level.
	if rested / max >= 0.005 then parts[#parts + 1] = ("|cff9fe0ffRested +%d%%|r"):format(rested / max * 100 + 0.5) end
	if quest > 0 then parts[#parts + 1] = ("|cffffd933Quests +%s|r"):format(ME.Short(quest)) end
	local perHour = demoXP and 14200 or rate()
	if perHour > 0 then
		parts[#parts + 1] = ("%s XP/h"):format(ME.Short(perHour))
		parts[#parts + 1] = ME.Duration((max - cur) / perHour * 3600) .. " to level"
	end
	local kills = demoXP and 18 or killsToLevel(max - cur, rested)
	if kills then parts[#parts + 1] = ("~%d kills"):format(kills) end
	detail:SetText(table.concat(parts, "  |cff666666-|r  "))
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
		local kills, base = killsToLevel(max - cur, rested)
		if kills then
			GameTooltip:AddDoubleLine(("Kills to level (last %d kills)"):format(#session.recent), ("~%d"):format(kills), 1, 1, 1, 1, 1, 1)
			GameTooltip:AddDoubleLine("Average kill XP before rested", ME.Comma(base), 1, 1, 1, 1, 1, 1)
		end
	end
	GameTooltip:AddDoubleLine("Session XP", ME.Comma(session.gained), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Session kills", tostring(session.kills), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Session time", ME.Duration(GetTime() - session.start), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine("Shift-drag to move", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function onXP()
	local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
	local gained = 0
	if session.lastXP then
		gained = cur - session.lastXP
		if gained < 0 then gained = gained + (session.lastMax or 0) end -- levelled up
		if gained > 0 then
			session.gained = session.gained + gained
			table.insert(session.window, { GetTime(), gained })
		end
	end
	session.lastXP, session.lastMax = cur, max
	XP:Update()
	if gained > 0 and ME.db.xp.effects and root:IsShown() then
		shine.Play()
		burstAtOrb(6)
		floatGain(gained)
	end
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
	-- One-time bump for bars saved at the original, thinner default.
	local db = ME.db.xp
	if not db.style2 then
		db.style2 = true
		if db.height == 16 then db.height = 20 end
	end
	build()
	if db.enabled and db.hideBlizzard then hideBlizzardBar() end
	self:ApplySettings()
	onXP()

	ME:On("PLAYER_XP_UPDATE", onXP)
	ME:On("UPDATE_EXHAUSTION", function() XP:Update() end)
	ME:On("PLAYER_UPDATE_RESTING", function() XP:Update() end)
	ME:On("QUEST_LOG_UPDATE", function() XP:Update() end)
	ME:On("PLAYER_ENTERING_WORLD", function() XP:Update() end)
	ME:On("PLAYER_LEVEL_UP", function()
		if ME.db.xp.effects and root:IsShown() then
			flash.anim:Stop(); flash.anim:Play()
			emblem.pop:Stop(); emblem.pop:Play()
			-- A storm of motes along the whole bar.
			local w = ME.db.xp.width
			for i = 1, #motes do emitMote(w * i / #motes, true) end
		end
		C_Timer.After(0.5, function() XP:Update() end)
	end)
	-- Kill XP arrives as a chat line; the first number in it is the amount.
	ME:On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
		if type(msg) ~= "string" or ME.issecret(msg) then return end
		-- "<mob> dies, you gain 120 experience. (+60 exp Rested bonus)":
		-- first number is the total, the second (if any) the rested part.
		local nums = {}
		for d in (msg:gsub("[,%.]", "")):gmatch("%d+") do nums[#nums + 1] = tonumber(d) end
		local total, bonus = nums[1], nums[2] or 0
		if total and total > 0 then
			if bonus >= total then bonus = 0 end
			session.kills = session.kills + 1
			session.killXP = session.killXP + total
			table.insert(session.recent, total - bonus)
			if #session.recent > RECENT_KILLS then table.remove(session.recent, 1) end
			XP:Update()
		end
	end)
	ME:Listen("SPEC_CHANGED", function() XP:ApplyTheme(true); XP:Update() end)

	-- Demo: sample XP gains every couple of seconds, with a level-up when full.
	local demoTicker
	ME:Listen("DEMO", function(on)
		if demoTicker then demoTicker:Cancel() demoTicker = nil end
		if not on then
			demoXP = nil
			XP:Update()
			return
		end
		demoXP = { cur = 6200, max = 21000, rested = 5000, quest = 2400 }
		XP:Update()
		demoTicker = C_Timer.NewTicker(1.8, function()
			if not demoXP or not root:IsShown() then return end
			local gain = math.random(900, 2600)
			demoXP.cur = demoXP.cur + gain
			if demoXP.cur >= demoXP.max then
				demoXP.cur = demoXP.cur - demoXP.max
				flash.anim:Stop(); flash.anim:Play()
				emblem.pop:Stop(); emblem.pop:Play()
				for i = 1, #motes do emitMote(ME.db.xp.width * i / #motes, true) end
			end
			XP:Update()
			if ME.db.xp.effects then
				shine.Play()
				burstAtOrb(6)
				floatGain(gain)
			end
		end)
	end)

	-- Refresh the rate text.
	C_Timer.NewTicker(10, function() XP:Update() end)
	-- Ambient effects: a steady trickle of motes and an occasional sweep.
	local sinceMote, sinceShine = 0, 0
	C_Timer.NewTicker(0.1, function()
		if not (root:IsShown() and ME.db.xp.effects) then return end
		local st = style()
		sinceMote = sinceMote + 0.1
		sinceShine = sinceShine + 0.1
		if sinceMote >= st.mote then
			sinceMote = 0
			emitMote()
		end
		if sinceShine >= st.shine then
			sinceShine = 0
			shine.Play()
		end
	end)
end
