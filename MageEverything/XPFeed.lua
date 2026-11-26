-- MageEverything: live XP log.
--
-- A small scrollable window listing every XP gain: when, how much, what it
-- came from (the mob, the quest, the place discovered, gathering, other),
-- the rested part and its share of the level. The latest 18 (adjustable)
-- are shown; the mouse wheel scrolls back through older ones. The log is
-- saved per character, so it survives logging out.
--
-- The game's XP total is the source of truth: every change in it becomes a
-- line. The label comes from the message that explains it (kill, quest hand
-- in, discovery) when one arrives; anything unexplained is "Gathering" right
-- after a herb / ore pick, otherwise "Other".
local _, ME = ...
local Feed = ME:NewModule("XPFeed")
local FX = ME.FX

local MAX_KEPT = 5000
local ROW_H = 16
local ICONS = {
	kill    = "Interface\\Icons\\Ability_Warrior_Rampage",
	quest   = "Interface\\GossipFrame\\ActiveQuestIcon",
	explore = "Interface\\Icons\\INV_Misc_Map_01",
	gather  = "Interface\\Icons\\INV_Misc_Herb_07",
	other   = "Interface\\Icons\\INV_Misc_Note_01",
}
local KIND_NAME = { kill = "Kills", quest = "Quests", explore = "Exploration", gather = "Gathering", other = "Other" }

local root, rows = nil, {}
local entries = {}       -- this character's saved log, newest last
local offset = 0         -- how many entries scrolled back from the newest
local pending = {}       -- explained gains waiting to be matched to XP changes
local lastXP, lastMax
local lastGatherAt = 0
local totals = { kill = 0, quest = 0, explore = 0, gather = 0, other = 0 }
local questTitle = {}

---------------------------------------------------------------------------
-- Message parsing (localised formats when the client has them)
---------------------------------------------------------------------------
local function toPattern(fmt, fallback)
	if type(fmt) ~= "string" then return fallback end
	local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
	p = p:gsub("%%%%?s", "(.-)"):gsub("%%%%?d", "(%%d+)")
	return p
end

local KILL = toPattern(_G.COMBATLOG_XPGAIN_FIRSTPERSON, "(.-) dies, you gain (%d+) experience")
local EXPLORE = toPattern(_G.ERR_ZONE_EXPLORED_XP, "Discovered (.-): (%d+) experience gained")

local function restedPart(text)
	local r = text:match("%+(%d+) exp Rested") or text:match("%((%d+)[^%d]*[Rr]ested")
	return tonumber(r) or 0
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function lines() return ME.db.xpfeed.lines or 18 end

local function build()
	root = CreateFrame("Frame", "MageEverythingXPFeed", UIParent)
	root:SetClampedToScreen(true)
	ME:MakeMovable(root, "xpfeed", "XP log", "BOTTOMRIGHT", -330, 40)
	-- Drag it any time.
	root:EnableMouse(true)
	root:RegisterForDrag("LeftButton")
	root:SetScript("OnDragStart", function(self) self:StartMoving() end)
	root:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint(1)
		if p then ME.db.pos.xpfeed = { p, rp, x, y } end
	end)
	local bg = root:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.02, 0.05, 0.7)
	root.border = FX.Border(root, 1, 0.3, 0.3, 0.4, 1)

	root.title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	root.title:SetPoint("TOPLEFT", 6, -4)
	root.title:SetText("XP log")
	root.total = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	root.total:SetPoint("TOPRIGHT", -8, -4)
	root.total:SetJustifyH("RIGHT")

	-- Scroll position marker on the right edge.
	root.track = root:CreateTexture(nil, "ARTWORK")
	root.track:SetColorTexture(1, 1, 1, 0.08)
	root.track:SetWidth(3)
	root.track:SetPoint("TOPRIGHT", -2, -20)
	root.track:SetPoint("BOTTOMRIGHT", -2, 4)
	root.thumb = root:CreateTexture(nil, "OVERLAY")
	root.thumb:SetColorTexture(0.6, 0.8, 1, 0.6)
	root.thumb:SetWidth(3)

	root.back = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	root.back:SetPoint("BOTTOMRIGHT", -8, 4)

	root:EnableMouseWheel(true)
	root:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #entries - lines())
		offset = math.max(0, math.min(maxOffset, offset + (delta > 0 and 3 or -3)))
		Feed:Render()
	end)
	root:SetScript("OnEnter", function() Feed:Tooltip() end)
	root:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ensureRows()
	local n = lines()
	root:SetSize(300, 24 + n * ROW_H + 14)
	for i = 1, math.max(n, #rows) do
		local r = rows[i]
		if not r and i <= n then
			r = CreateFrame("Frame", nil, root)
			r:SetSize(288, ROW_H)
			r.time = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			r.time:SetPoint("LEFT", 0, 0)
			r.time:SetWidth(34)
			r.time:SetJustifyH("LEFT")
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(13, 13)
			r.icon:SetPoint("LEFT", r.time, "RIGHT", 2, 0)
			r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			r.amount = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			r.amount:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
			r.amount:SetWidth(52)
			r.amount:SetJustifyH("LEFT")
			r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			r.label:SetPoint("LEFT", r.amount, "RIGHT", 2, 0)
			r.label:SetWidth(180)
			r.label:SetJustifyH("LEFT")
			r.label:SetWordWrap(false)
			r.pop = FX.Pop(r, 1.2, 0.18)
			rows[i] = r
		end
		if r then
			r:ClearAllPoints()
			-- Newest at the bottom.
			r:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 6, 14 + (i - 1) * ROW_H)
			r:SetShown(i <= n)
		end
	end
end

function Feed:Render(popNewest)
	if not root or not root:IsShown() then return end
	local t = FX.Theme()
	local n, total = lines(), #entries
	for i = 1, n do
		local r = rows[i]
		local e = entries[total - offset - i + 1]
		if e then
			r.time:SetText(date and e.when and date("%H:%M", e.when) or "")
			r.icon:SetTexture(ICONS[e.kind] or ICONS.other)
			r.amount:SetText(("+%s"):format(ME.Comma(e.amount)))
			r.amount:SetTextColor(t.r, t.g, t.b)
			local extra = ""
			if (e.rested or 0) > 0 then extra = extra .. ("  |cff7fd4ff+%s rested|r"):format(ME.Comma(e.rested)) end
			if e.pct and e.pct >= 0.1 then extra = extra .. ("  |cff999999%.1f%%|r"):format(e.pct) end
			r.label:SetText(e.label .. extra)
			r.icon:Show()
			if i == 1 and popNewest and offset == 0 then r.pop:Stop(); r.pop:Play() end
		else
			r.time:SetText("")
			r.amount:SetText("")
			r.label:SetText(i == 1 and total == 0 and "|cff777777XP you gain will be listed here|r" or "")
			r.icon:Hide()
		end
	end
	-- Session total and scroll position.
	local sum = 0
	for _, v in pairs(totals) do sum = sum + v end
	root.total:SetText(sum > 0 and ("session +" .. ME.Comma(sum)) or "")
	local maxOffset = math.max(0, total - n)
	if maxOffset > 0 then
		local h = root.track:GetHeight()
		if not h or h <= 0 or ME.issecret(h) then h = n * ROW_H end
		local th = math.max(8, h * n / total)
		root.thumb:SetHeight(th)
		root.thumb:ClearAllPoints()
		root.thumb:SetPoint("BOTTOMRIGHT", root.track, "BOTTOMRIGHT", 0, (h - th) * offset / maxOffset)
		root.thumb:Show()
		root.track:Show()
	else
		root.thumb:Hide()
		root.track:Hide()
	end
	root.back:SetText(offset > 0 and ("|cffaaaaaa%d newer below - scroll down|r"):format(offset) or "")
end

local function add(amount, kind, label, rested)
	if amount <= 0 then return end
	local max = lastMax or UnitXPMax("player") or 1
	entries[#entries + 1] = { amount = amount, kind = kind, label = label, rested = rested or 0,
		when = time and time() or nil, level = UnitLevel("player"),
		pct = max > 0 and math.floor(amount / max * 1000 + 0.5) / 10 or nil }
	while #entries > MAX_KEPT do table.remove(entries, 1) end
	totals[kind] = (totals[kind] or 0) + amount
	-- If you are reading older lines, keep them in place.
	if offset > 0 then offset = offset + 1 end
	if ME.db.xpfeed.enabled then Feed:Render(true) end
	ME:Fire("XP_FEED", amount, kind, label)
end

function Feed:Entries() return entries end

function Feed:Tooltip()
	GameTooltip:SetOwner(root, "ANCHOR_TOP")
	GameTooltip:AddLine("XP this session")
	local sum = 0
	for _, k in ipairs({ "kill", "quest", "explore", "gather", "other" }) do
		local v = totals[k] or 0
		sum = sum + v
		if v > 0 then GameTooltip:AddDoubleLine(KIND_NAME[k], ME.Comma(v), 1, 1, 1, 1, 1, 1) end
	end
	GameTooltip:AddDoubleLine("Total", ME.Comma(sum), 1, 0.82, 0, 1, 0.82, 0)
	GameTooltip:AddLine(" ")
	local all = 0
	for _, e in ipairs(entries) do all = all + e.amount end
	GameTooltip:AddDoubleLine("Saved log", ("%d gains, %s XP"):format(#entries, ME.Comma(all)), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Mouse wheel to scroll. Drag to move. /mage xplog clear empties it.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Matching XP changes to their causes
---------------------------------------------------------------------------
local function explain(amount, kind, label, rested)
	pending[#pending + 1] = { amount = amount, kind = kind, label = label, rested = rested or 0, time = GetTime() }
end

-- Called a moment after the XP total changes, once messages have arrived.
local function settle(delta)
	local now = GetTime()
	-- Drop stale explanations that never matched an XP change.
	for i = #pending, 1, -1 do
		if now - pending[i].time > 5 then table.remove(pending, i) end
	end
	while delta > 0 and pending[1] do
		local p = table.remove(pending, 1)
		local amount = math.min(p.amount, delta)
		add(amount, p.kind, p.label, p.rested)
		delta = delta - amount
	end
	if delta > 0 then
		if now - lastGatherAt < 4 then
			add(delta, "gather", "Gathering")
		else
			add(delta, "other", "Other")
		end
	end
end

local function onXPUpdate()
	local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
	if lastXP then
		local delta = cur - lastXP
		if delta < 0 then delta = delta + (lastMax or 0) end -- levelled up
		if delta > 0 then
			-- Messages explaining the gain can arrive just after the change.
			C_Timer.After(0.4, function() settle(delta) end)
		end
	end
	lastXP, lastMax = cur, max
end

function Feed:ApplySettings()
	if not root then return end
	ensureRows()
	root:SetShown(ME.db.xpfeed.enabled)
	root:SetScale(ME.db.xpfeed.scale or 1)
	self:Render()
end

function Feed:Clear()
	wipe(entries)
	offset = 0
	self:Render()
end

function Feed:OnLogin()
	-- This character's saved log.
	local root2 = ME.root
	root2.xplog = root2.xplog or {}
	root2.xplog[ME.charKey or "?"] = root2.xplog[ME.charKey or "?"] or {}
	entries = root2.xplog[ME.charKey or "?"]
	build()
	self:ApplySettings()
	lastXP, lastMax = UnitXP("player"), UnitXPMax("player")

	ME:On("PLAYER_XP_UPDATE", onXPUpdate)
	ME:On("CHAT_MSG_COMBAT_XP_GAIN", function(text)
		if type(text) ~= "string" or ME.issecret(text) then return end
		local mob, amount = text:match(KILL)
		if mob and amount then
			explain(tonumber(amount), "kill", mob, restedPart(text))
			return
		end
		local n = tonumber((text:gsub("[,%.]", "")):match("(%d+)"))
		if n then
			local recentGather = GetTime() - lastGatherAt < 4
			explain(n, recentGather and "gather" or "other", recentGather and "Gathering" or "Experience", restedPart(text))
		end
	end)
	ME:On("CHAT_MSG_SYSTEM", function(text)
		if type(text) ~= "string" or ME.issecret(text) then return end
		local zone, amount = text:match(EXPLORE)
		if zone and amount then explain(tonumber(amount), "explore", "Discovered " .. zone) end
	end)
	-- Quest titles are noted while the quest is still in the log.
	ME:On("QUEST_COMPLETE", function()
		local id = GetQuestID and GetQuestID()
		local title = GetTitleText and GetTitleText()
		if id and title then questTitle[id] = title end
	end)
	ME:On("QUEST_TURNED_IN", function(questID, xpReward)
		if not xpReward or xpReward <= 0 then return end
		local title = questTitle[questID]
			or (C_QuestLog and C_QuestLog.GetTitleForQuestID and ME.Try(C_QuestLog.GetTitleForQuestID, questID))
			or "Quest"
		explain(xpReward, "quest", title)
	end)
	-- Gathering: the herb / ore / skinning casts themselves.
	ME:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
		if unit ~= "player" or ME.issecret(spellID) then return end
		local name = ME.Spells.SpellName(spellID)
		if name and (name:find("Herb") or name:find("Mining") or name:find("Skinning")) then
			lastGatherAt = GetTime()
		end
	end)

	-- Demo mode: a few sample lines.
	ME:Listen("DEMO", function(on)
		if not on then return end
		add(242, "kill", "Defias Pillager", 121)
		add(1150, "quest", "The Defias Brotherhood")
		add(180, "explore", "Discovered Moonbrook")
		add(36, "gather", "Gathering")
	end)
end
