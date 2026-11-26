-- MageEverything: live XP feed.
--
-- A short scrolling list beside the XP bar: one line per XP gain, with what
-- it came from (kill, quest, exploration, gathering, other), the amount, the
-- rested bonus part, and its share of the level. Lines fade after a while.
--
-- The game's XP total is the source of truth: every change in it becomes a
-- line. The label comes from the message that explains it (kill, quest hand
-- in, discovery) when one arrives; anything unexplained is "Gathering" right
-- after a herb / ore pick, otherwise "Other".
local _, ME = ...
local Feed = ME:NewModule("XPFeed")
local FX = ME.FX

local LINES = 8
local ICONS = {
	kill    = "Interface\\Icons\\Ability_Warrior_Rampage",
	quest   = "Interface\\GossipFrame\\ActiveQuestIcon",
	explore = "Interface\\Icons\\INV_Misc_Map_01",
	gather  = "Interface\\Icons\\INV_Misc_Herb_07",
	other   = "Interface\\Icons\\INV_Misc_Note_01",
}
local KIND_NAME = { kill = "Kills", quest = "Quests", explore = "Exploration", gather = "Gathering", other = "Other" }

local root, rows = nil, {}
local entries = {}       -- newest last: { amount, kind, label, rested, time, pct }
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
local function build()
	root = CreateFrame("Frame", "MageEverythingXPFeed", UIParent)
	root:SetSize(260, LINES * 18)
	ME:MakeMovable(root, "xpfeed", "XP feed", "BOTTOMRIGHT", -330, 40)
	for i = 1, LINES do
		local r = CreateFrame("Frame", nil, root)
		r:SetSize(260, 18)
		r:SetPoint("BOTTOMLEFT", 0, (i - 1) * 18)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(15, 15)
		r.icon:SetPoint("LEFT", 0, 0)
		r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		r.amount = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		r.amount:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
		r.amount:SetWidth(62)
		r.amount:SetJustifyH("LEFT")
		r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.label:SetPoint("LEFT", r.amount, "RIGHT", 2, 0)
		r.label:SetWidth(190)
		r.label:SetJustifyH("LEFT")
		r.label:SetWordWrap(false)
		r.pop = FX.Pop(r, 1.3, 0.2)
		r:Hide()
		rows[i] = r
	end
	root:EnableMouse(true)
	root:SetScript("OnEnter", function() Feed:Tooltip() end)
	root:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function render(popNewest)
	if not root then return end
	local t = FX.Theme()
	local n = #entries
	for i = 1, LINES do
		local r = rows[i]
		local e = entries[n - i + 1] -- row 1 (bottom) = newest
		if e then
			r.icon:SetTexture(ICONS[e.kind] or ICONS.other)
			r.amount:SetText(("+%s"):format(ME.Comma(e.amount)))
			r.amount:SetTextColor(t.r, t.g, t.b)
			local extra = ""
			if e.rested > 0 then extra = extra .. ("  |cff7fd4ff+%s rested|r"):format(ME.Comma(e.rested)) end
			if e.pct and e.pct >= 0.1 then extra = extra .. ("  |cff999999%.1f%%|r"):format(e.pct) end
			r.label:SetText(e.label .. extra)
			r.born = e.time
			r:SetAlpha(1)
			r:Show()
			if i == 1 and popNewest then r.pop:Stop(); r.pop:Play() end
		else
			r:Hide()
		end
	end
end

local function add(amount, kind, label, rested)
	if amount <= 0 then return end
	local max = lastMax or UnitXPMax("player") or 1
	entries[#entries + 1] = { amount = amount, kind = kind, label = label, rested = rested or 0,
		time = GetTime(), pct = max > 0 and amount / max * 100 or nil }
	while #entries > 50 do table.remove(entries, 1) end
	totals[kind] = (totals[kind] or 0) + amount
	if ME.db.xpfeed.enabled then render(true) end
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
	for i = #entries, math.max(1, #entries - 14), -1 do
		local e = entries[i]
		GameTooltip:AddDoubleLine(e.label, "+" .. ME.Comma(e.amount), 0.8, 0.8, 0.8, 1, 1, 1)
	end
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
	root:SetShown(ME.db.xpfeed.enabled)
	root:SetScale(ME.db.xpfeed.scale or 1)
end

function Feed:OnLogin()
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

	-- Fade old lines.
	C_Timer.NewTicker(0.5, function()
		if not root:IsShown() then return end
		local life = ME.db.xpfeed.fade or 30
		local now = GetTime()
		for _, r in ipairs(rows) do
			if r:IsShown() and r.born then
				local age = now - r.born
				if age > life then
					r:Hide()
				elseif age > life - 5 then
					r:SetAlpha((life - age) / 5)
				end
			end
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
