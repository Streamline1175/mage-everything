-- MageEverything: Herbalism tracker.
--
-- /mage herbs opens a window with:
--   * your Herbalism skill bar, and the next training rank if you are capped,
--   * a card for the next herb you can unlock and how far away it is,
--   * a vertical timeline of every herb node with the skill it needs, its
--     skill-up colour for you right now, and how many you have gathered,
--   * counts of Forever's rare extras (Frilled Lichen, Rosecap, ...).
--
-- Node skill levels and colours are from the Forever 1.60.1 game data and
-- the Warcraft Wiki's Forever herbalism table (Forever moved the yellow ->
-- green point 15 skill later than Classic). Counts come from your own loot
-- messages, from the moment this version is installed.
local _, ME = ...
local Herbs = ME:NewModule("Herbs")
local FX = ME.FX

local HERBALISM = { [182] = true, [2944] = true } -- skill line, and Forever's child line

-- { item ID, English name, orange (required), yellow, green, grey, where }
local NODES = {
	{ 2447,  "Peacebloom",          1,   25,  65,  100, "Open ground, starting zones" },
	{ 765,   "Silverleaf",          1,   25,  65,  100, "By trees, starting zones" },
	{ 2449,  "Earthroot",           15,  40,  80,  115, "Hills and cliffs, levels 1-10" },
	{ 785,   "Mageroyal",           50,  75,  115, 150, "Open ground, levels 10-25" },
	{ 2450,  "Briarthorn",          70,  95,  135, 170, "By trees, levels 10-25" },
	{ 3820,  "Stranglekelp",        85,  110, 150, 185, "Underwater, levels 25-45" },
	{ 2453,  "Bruiseweed",          100, 125, 165, 200, "Buildings and hills, levels 25-45" },
	{ 3355,  "Wild Steelbloom",     115, 140, 180, 215, "Hills and cliffs, levels 25-45" },
	{ 3369,  "Grave Moss",          120, 145, 185, 220, "Crypts and graveyards" },
	{ 3356,  "Kingsblood",          125, 150, 190, 225, "Open ground, levels 25+" },
	{ 3357,  "Liferoot",            150, 175, 215, 250, "Near water, levels 25+" },
	{ 3818,  "Fadeleaf",            160, 185, 225, 260, "By trees, levels 35+" },
	{ 3821,  "Goldthorn",           170, 195, 235, 270, "Hills and cliffs, levels 35+" },
	{ 3358,  "Khadgar's Whisker",   185, 210, 250, 285, "By trees, levels 35+" },
	{ 3819,  "Wintersbite",         195, 220, 260, 295, "Alterac Mountains" },
	{ 4625,  "Firebloom",           205, 230, 270, 305, "Badlands, Blasted Lands, Searing Gorge, Tanaris" },
	{ 8831,  "Purple Lotus",        210, 235, 275, 310, "Near ruins, levels 35+" },
	{ 8836,  "Arthas' Tears",       220, 245, 285, 320, "Plaguelands, Felwood" },
	{ 8838,  "Sungrass",            230, 255, 295, 330, "Open ground, levels 35+" },
	{ 8839,  "Blindweed",           235, 260, 300, 335, "Swamp of Sorrows, Un'Goro Crater" },
	{ 8845,  "Ghost Mushroom",      245, 270, 310, 345, "Caves, The Hinterlands" },
	{ 8846,  "Gromsblood",          250, 275, 315, 350, "Ashenvale, Blasted Lands, Desolace, Felwood" },
	{ 13464, "Golden Sansam",       260, 285, 325, 360, "Open ground, levels 45+" },
	{ 13463, "Dreamfoil",           270, 290, 340, 370, "Open ground, levels 45+" },
	{ 13465, "Mountain Silversage", 280, 305, 345, 380, "Hills and cliffs, levels 45+" },
	{ 13466, "Plaguebloom",         285, 310, 350, 385, "Plaguelands, Felwood" },
	{ 13467, "Icecap",              290, 315, 355, 390, "Winterspring" },
	{ 13468, "Black Lotus",         300, 325, 365, 400, "Burning Steppes, Plaguelands, Silithus, Winterspring" },
}

-- Extra herbs that come from nodes rather than having their own.
local EXTRAS = {
	{ 2452,   "Swiftthistle",   "Sometimes in Mageroyal and Briarthorn" },
	{ 8153,   "Wildvine",       "Sometimes in Purple Lotus" },
	{ 249399, "Frilled Lichen", "Scarce: Earthroot to Kingsblood (not Grave Moss)" },
	{ 249424, "Rosecap",        "Scarce: Liferoot to Purple Lotus" },
	{ 249274, "Stranglevine",   "Scarce: Sungrass to Icecap" },
	{ 248823, "Marefoil",       "Endgame herb" },
	{ 248821, "Demonsage",      "Endgame herb" },
	{ 248822, "Death Lotus",    "Mount Hyjal, with Enchant Gloves - Lotus Claw" },
	{ 19726,  "Bloodvine",      "Zul'Gurub, with a Blood Scythe" },
	{ 268415, "Commonplace Herb Seeds", "Herb nodes (for camping)" },
	{ 268416, "Uncommon Herb Seeds",    "Herb nodes (for camping)" },
	{ 268417, "Unusual Herb Seeds",     "Herb nodes (for camping)" },
	{ 268418, "Scarce Herb Seeds",      "Herb nodes (for camping)" },
}

-- Training ranks: the cap you have -> what to learn next (Classic rules,
-- which the wiki says Forever keeps).
local RANKS = {
	[75]  = { "Journeyman", 50, 10, 150 },
	[150] = { "Expert", 125, 20, 225 },
	[225] = { "Artisan", 200, 35, 300 },
}

local TRACKED = {}
for _, n in ipairs(NODES) do TRACKED[n[1]] = true end
for _, e in ipairs(EXTRAS) do TRACKED[e[1]] = true end

local COLOR = {
	orange = { 1, 0.5, 0.25, "Guaranteed skill-up" },
	yellow = { 1, 0.9, 0.2, "Likely skill-up" },
	green  = { 0.25, 0.85, 0.3, "Unlikely skill-up" },
	grey   = { 0.55, 0.55, 0.55, "No skill-ups" },
	locked = { 0.45, 0.45, 0.6, "Locked" },
}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
-- Herbalism skill: rank, cap (nil when not learned).
function Herbs:Skill()
	if GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 2 do
			local idx = list[i]
			if idx then
				local _, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
				if HERBALISM[skillLine] then return ME.Plain(rank, 0), ME.Plain(maxRank, 0) end
			end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
			if not isHeader and name == "Herbalism" then return rank, maxRank end
		end
	end
	return nil
end

local function colorFor(node, skill)
	if not skill or skill < node[3] then return "locked" end
	if skill >= node[6] then return "grey" end
	if skill >= node[5] then return "green" end
	if skill >= node[4] then return "yellow" end
	return "orange"
end

local function counts()
	local root = ME.root
	root.herbs = root.herbs or {}
	local key = ME.charKey or "?"
	root.herbs[key] = root.herbs[key] or {}
	return root.herbs[key]
end

local function itemName(id, fallback)
	local n = C_Item and C_Item.GetItemNameByID and ME.Try(C_Item.GetItemNameByID, id)
	return (type(n) == "string" and n ~= "") and n or fallback
end

local function itemIcon(id)
	local t = C_Item and C_Item.GetItemIconByID and ME.Try(C_Item.GetItemIconByID, id)
	return t or "Interface\\Icons\\INV_Misc_Herb_01"
end

-- The next herb you cannot gather yet, or nil when all are unlocked.
local function nextNode(skill)
	for _, n in ipairs(NODES) do
		if (skill or 0) < n[3] then return n end
	end
end

---------------------------------------------------------------------------
-- Loot counting
---------------------------------------------------------------------------
local function toPattern(fmt)
	if type(fmt) ~= "string" then return nil end
	local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
	p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. p .. "$"
end

local patterns
local function lootPatterns()
	if patterns then return patterns end
	patterns = {}
	-- Multiple first, so "x5" is not swallowed by the single pattern.
	for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
		local p = toPattern(_G[g])
		if p then patterns[#patterns + 1] = p end
	end
	if #patterns == 0 then patterns = { "^You receive loot: (.+)x(%d+)%.$", "^You receive loot: (.+)%.$" } end
	return patterns
end

local function onLoot(text)
	if type(text) ~= "string" or ME.issecret(text) then return end
	for _, p in ipairs(lootPatterns()) do
		local link, qty = text:match(p)
		if link then
			local id = tonumber(link:match("item:(%d+)"))
			if id and TRACKED[id] then
				local c = counts()
				c[id] = (c[id] or 0) + (tonumber(qty) or 1)
				Herbs:Refresh()
			end
			return
		end
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local win, skillBar, nextCard, rows, extraRows, scrollChild
local W, ROW = 380, 30

local function text(parent, font, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	if r then fs:SetTextColor(r, g, b) end
	return fs
end

local function bar(parent, width, height)
	local sb = CreateFrame("StatusBar", nil, parent)
	sb:SetSize(width, height)
	sb:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
	local bg = sb:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", 1, -1)
	bg:SetColorTexture(0, 0, 0, 0.8)
	sb.text = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sb.text:SetPoint("CENTER")
	return sb
end

local function build()
	win = CreateFrame("Frame", "MageEverythingHerbs", UIParent)
	win:SetSize(W, 560)
	win:SetFrameStrata("HIGH")
	win:SetClampedToScreen(true)
	ME:MakeMovable(win, "herbs", "Herbalism", "RIGHT", -60, 40)
	-- Drag the window by its title area.
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint(1)
		if p then ME.db.pos.herbs = { p, rp, x, y } end
	end)
	if UISpecialFrames then table.insert(UISpecialFrames, "MageEverythingHerbs") end
	local bg = win:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.03, 0.05, 0.04, 0.95)
	FX.Border(win, 1, 0.35, 0.8, 0.45, 1)

	local icon = win:CreateTexture(nil, "ARTWORK")
	icon:SetSize(34, 34)
	icon:SetPoint("TOPLEFT", 12, -10)
	icon:SetTexture("Interface\\Icons\\Spell_Nature_NatureTouchGrow")
	local title = text(win, "GameFontNormalLarge", 0.5, 1, 0.55)
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
	title:SetText("Herbalism")
	win.subtitle = text(win, "GameFontHighlightSmall", 0.75, 0.75, 0.75)
	win.subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	-- Skill bar with a marker for every herb unlock along it.
	skillBar = bar(win, W - 24, 16)
	skillBar:SetPoint("TOPLEFT", 12, -54)
	skillBar:SetStatusBarColor(0.3, 0.85, 0.4)
	skillBar.marks = {}
	for i, n in ipairs(NODES) do
		local m = skillBar:CreateTexture(nil, "OVERLAY")
		m:SetColorTexture(1, 1, 1, 0.35)
		m:SetSize(1, 16)
		m:SetPoint("LEFT", skillBar, "LEFT", (W - 24) * n[3] / 300, 0)
		skillBar.marks[i] = m
	end
	win.rankText = text(win, "GameFontHighlightSmall")
	win.rankText:SetPoint("TOPLEFT", skillBar, "BOTTOMLEFT", 0, -4)
	win.rankText:SetWidth(W - 24)

	-- Next unlock card.
	nextCard = CreateFrame("Frame", nil, win)
	nextCard:SetSize(W - 24, 52)
	nextCard:SetPoint("TOPLEFT", skillBar, "BOTTOMLEFT", 0, -22)
	local cbg = nextCard:CreateTexture(nil, "BACKGROUND")
	cbg:SetAllPoints()
	cbg:SetColorTexture(0.12, 0.2, 0.13, 0.9)
	nextCard.icon = nextCard:CreateTexture(nil, "ARTWORK")
	nextCard.icon:SetSize(36, 36)
	nextCard.icon:SetPoint("LEFT", 8, 0)
	nextCard.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	nextCard.title = text(nextCard, "GameFontNormal")
	nextCard.title:SetPoint("TOPLEFT", nextCard.icon, "TOPRIGHT", 10, -1)
	nextCard.bar = bar(nextCard, W - 90, 12)
	nextCard.bar:SetPoint("BOTTOMLEFT", nextCard.icon, "BOTTOMRIGHT", 10, 1)
	nextCard.bar:SetStatusBarColor(1, 0.75, 0.25)

	-- Scrolling timeline.
	local scroll = CreateFrame("ScrollFrame", "MageEverythingHerbsScroll", win, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", nextCard, "BOTTOMLEFT", 0, -10)
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 12)
	scrollChild = CreateFrame("Frame", nil, scroll)
	scrollChild:SetSize(W - 50, (#NODES + #EXTRAS + 2) * ROW)
	scroll:SetScrollChild(scrollChild)

	-- The timeline's spine.
	local spine = scrollChild:CreateTexture(nil, "BACKGROUND")
	spine:SetColorTexture(0.35, 0.8, 0.45, 0.35)
	spine:SetWidth(2)
	spine:SetPoint("TOPLEFT", 13, -ROW / 2)
	spine:SetHeight((#NODES - 1) * ROW)

	local function makeRow(i, y, isExtra)
		local r = CreateFrame("Frame", nil, scrollChild)
		r:SetSize(W - 50, ROW)
		r:SetPoint("TOPLEFT", 0, y)
		if not isExtra then
			r.dot = r:CreateTexture(nil, "ARTWORK")
			r.dot:SetSize(10, 10)
			r.dot:SetPoint("LEFT", 9, 0)
			r.dot:SetTexture(FX.WHITE)
		end
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(22, 22)
		r.icon:SetPoint("LEFT", isExtra and 4 or 26, 0)
		r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		r.name = text(r, "GameFontHighlightSmall")
		r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
		r.info = text(r, "GameFontDisableSmall")
		r.info:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, -1)
		r.info:SetWidth(isExtra and 260 or 220)
		r.info:SetWordWrap(false)
		r.count = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		r.count:SetPoint("RIGHT", -4, 0)
		r.count:SetJustifyH("RIGHT")
		r.bar = bar(r, 70, 6)
		r.bar:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
		r.bar:SetStatusBarColor(1, 0.75, 0.25)
		r.bar.text:SetText("")
		r:EnableMouse(true)
		r:SetScript("OnEnter", function(self)
			if not self.tip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			for li, line in ipairs(self.tip) do
				if li == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
			end
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return r
	end

	rows, extraRows = {}, {}
	for i = 1, #NODES do rows[i] = makeRow(i, -(i - 1) * ROW) end
	local header = text(scrollChild, "GameFontNormal", 0.5, 1, 0.55)
	header:SetPoint("TOPLEFT", 4, -(#NODES) * ROW - 8)
	header:SetText("Extras and rare herbs")
	for i = 1, #EXTRAS do
		extraRows[i] = makeRow(i, -(#NODES + 1) * ROW - (i - 1) * ROW, true)
	end
	win:Hide()
end

---------------------------------------------------------------------------
-- Mini tracker: a small always-on bar with the next herb to unlock.
-- Drag it anywhere; click it to open the full window.
---------------------------------------------------------------------------
local mini

local function buildMini()
	mini = CreateFrame("Button", "MageEverythingHerbMini", UIParent)
	mini:SetSize(200, 30)
	mini:SetClampedToScreen(true)
	ME:MakeMovable(mini, "herbmini", "Herb tracker", "TOPRIGHT", -220, -230)
	mini:RegisterForDrag("LeftButton")
	mini:RegisterForClicks("LeftButtonUp")
	mini:SetScript("OnDragStart", function(self) self:StartMoving() end)
	mini:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint(1)
		if p then ME.db.pos.herbmini = { p, rp, x, y } end
	end)
	mini:SetScript("OnClick", function() Herbs:Toggle() end)

	local bg = mini:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.05, 0.03, 0.75)
	mini.border = FX.Border(mini, 1, 0.25, 0.6, 0.32, 1)
	mini.icon = mini:CreateTexture(nil, "ARTWORK")
	mini.icon:SetSize(26, 26)
	mini.icon:SetPoint("LEFT", 2, 0)
	mini.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	mini.name = mini:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mini.name:SetPoint("TOPLEFT", mini.icon, "TOPRIGHT", 5, -1)
	mini.name:SetPoint("RIGHT", -4, 0)
	mini.name:SetJustifyH("LEFT")
	mini.name:SetWordWrap(false)
	mini.bar = bar(mini, 164, 9)
	mini.bar:SetPoint("BOTTOMLEFT", mini.icon, "BOTTOMRIGHT", 5, 1)
	mini.bar:SetPoint("RIGHT", -4, 0)
	mini.bar:SetStatusBarColor(1, 0.75, 0.25)
	mini.bar.text:SetFontObject("GameFontHighlightSmall")
	mini.bar.text:SetScale(0.85)
	mini.shine = FX.Shine(mini.bar)

	mini:SetScript("OnEnter", function(self)
		local skill, cap = Herbs:Skill()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Herbalism", 0.5, 1, 0.55)
		if skill then
			GameTooltip:AddDoubleLine("Skill", ("%d / %d"):format(skill, cap), 1, 1, 1, 1, 1, 1)
			-- Which herbs give skill-ups right now.
			local best = {}
			for _, n in ipairs(NODES) do
				local state = colorFor(n, skill)
				if state == "orange" or state == "yellow" then
					local col = COLOR[state]
					best[#best + 1] = { itemName(n[1], n[2]), col }
				end
			end
			if #best > 0 then
				GameTooltip:AddLine("Skill-ups from:", 1, 0.82, 0)
				for _, b in ipairs(best) do GameTooltip:AddLine("  " .. b[1], b[2][1], b[2][2], b[2][3]) end
			end
		end
		GameTooltip:AddLine("Drag to move. Click for the full tracker.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
	mini:Hide()
end

local lastNext
function Herbs:RefreshMini()
	if not mini then return end
	local skill, cap = self:Skill()
	if not ME.db.herbs.mini or not skill then
		mini:Hide()
		return
	end
	local nxt = nextNode(skill)
	if nxt then
		local prev = 0
		for _, n in ipairs(NODES) do if n[3] < nxt[3] then prev = n[3] end end
		mini.icon:SetTexture(itemIcon(nxt[1]))
		mini.icon:SetDesaturated(true)
		mini.name:SetText(("Next: |cffffffff%s|r  |cff999999(%d)|r"):format(itemName(nxt[1], nxt[2]), nxt[3]))
		mini.bar:SetMinMaxValues(prev, nxt[3])
		mini.bar:SetValue(skill)
		local need = nxt[3] - skill
		if cap and nxt[3] > cap and RANKS[cap] then
			mini.bar.text:SetText(("%d to go - train %s"):format(need, RANKS[cap][1]))
			mini.bar:SetStatusBarColor(1, 0.45, 0.25)
		else
			mini.bar.text:SetText(("%d / %d  -  %d to go"):format(skill, nxt[3], need))
			mini.bar:SetStatusBarColor(1, 0.75, 0.25)
		end
		if lastNext and lastNext ~= nxt[1] then mini.shine.Play() end
		lastNext = nxt[1]
	else
		mini.icon:SetTexture(itemIcon(13468))
		mini.icon:SetDesaturated(false)
		mini.name:SetText("|cff59ff73Every herb unlocked|r")
		mini.bar:SetMinMaxValues(0, 300)
		mini.bar:SetValue(skill)
		mini.bar.text:SetText(("%d / %d"):format(skill, cap or 300))
	end
	mini:SetScale(ME.db.herbs.miniScale or 1)
	mini:Show()
end

function Herbs:ApplySettings()
	self:RefreshMini()
end

function Herbs:Refresh()
	self:RefreshMini()
	if not win or not win:IsShown() then return end
	local skill, cap = self:Skill()
	local c = counts()
	local total = 0
	for _, n in ipairs(NODES) do total = total + (c[n[1]] or 0) end

	if not skill then
		win.subtitle:SetText("Herbalism is not learned on this character")
	else
		win.subtitle:SetText(("Skill %d / %d   -   %s herbs gathered"):format(skill, cap, ME.Comma(total)))
	end
	skillBar:SetMinMaxValues(0, 300)
	skillBar:SetValue(skill or 0)
	skillBar.text:SetText(skill and ("%d / %d"):format(skill, cap) or "--")

	-- Training rank.
	local rank = cap and RANKS[cap]
	if rank and skill and skill >= cap - 10 then
		local lvl = UnitLevel("player") or 1
		win.rankText:SetText(("|cffffd100Train %s Herbalism|r (cap %d): needs skill %d and level %d%s"):format(
			rank[1], rank[4], rank[2], rank[3], lvl >= rank[3] and " - |cff59ff73you can train it now|r" or ""))
	elseif cap and cap > 0 then
		win.rankText:SetText(("Training cap: %d"):format(cap))
	else
		win.rankText:SetText("Learn Herbalism from a trainer in any capital city.")
	end

	-- Next unlock.
	local nxt = nextNode(skill)
	if nxt then
		local prev = 0
		for _, n in ipairs(NODES) do if n[3] < nxt[3] then prev = n[3] end end
		nextCard.icon:SetTexture(itemIcon(nxt[1]))
		local need = nxt[3] - (skill or 0)
		local capNote = (cap and nxt[3] > cap) and ("  |cffff8040(needs " .. (RANKS[cap] and RANKS[cap][1] or "higher") .. " training)|r") or ""
		nextCard.title:SetText(("Next: |cffffffff%s|r at skill %d%s"):format(itemName(nxt[1], nxt[2]), nxt[3], capNote))
		nextCard.bar:SetMinMaxValues(prev, nxt[3])
		nextCard.bar:SetValue(skill or 0)
		nextCard.bar.text:SetText(("%d point%s to go"):format(need, need == 1 and "" or "s"))
	else
		nextCard.icon:SetTexture(itemIcon(13468))
		nextCard.title:SetText("|cff59ff73Every herb unlocked|r")
		nextCard.bar:SetMinMaxValues(0, 1)
		nextCard.bar:SetValue(1)
		nextCard.bar.text:SetText("")
	end

	-- Timeline.
	for i, n in ipairs(NODES) do
		local r = rows[i]
		local state = colorFor(n, skill)
		local col = COLOR[state]
		r.icon:SetTexture(itemIcon(n[1]))
		r.icon:SetDesaturated(state == "locked")
		r.dot:SetVertexColor(col[1], col[2], col[3])
		r.name:SetText(("%s  |cff%02x%02x%02x%d|r"):format(itemName(n[1], n[2]), col[1] * 255, col[2] * 255, col[3] * 255, n[3]))
		r.name:SetTextColor(state == "locked" and 0.6 or 1, state == "locked" and 0.6 or 1, state == "locked" and 0.6 or 1)
		if state == "locked" then
			local need = n[3] - (skill or 0)
			local capNote = (cap and n[3] > cap) and " - needs training" or ""
			r.info:SetText(("%d to go%s"):format(need, capNote))
			r.bar:Show()
			r.bar:SetMinMaxValues(0, n[3])
			r.bar:SetValue(skill or 0)
		else
			local nextStep = (state == "orange" and n[4]) or (state == "yellow" and n[5]) or (state == "green" and n[6]) or nil
			r.info:SetText(col[4] .. (nextStep and (" until " .. nextStep) or ""))
			r.bar:Hide()
		end
		local got = c[n[1]] or 0
		r.count:SetText(got > 0 and ("x" .. ME.Comma(got)) or "|cff666666-|r")
		r.tip = { itemName(n[1], n[2]),
			("Orange %d   Yellow %d   Green %d   Grey %d"):format(n[3], n[4], n[5], n[6]),
			n[7], ("Gathered: %d"):format(got) }
	end
	for i, e in ipairs(EXTRAS) do
		local r = extraRows[i]
		r.icon:SetTexture(itemIcon(e[1]))
		r.name:SetText(itemName(e[1], e[2]))
		r.info:SetText(e[3])
		r.bar:Hide()
		local got = c[e[1]] or 0
		r.count:SetText(got > 0 and ("x" .. ME.Comma(got)) or "|cff666666-|r")
		r.tip = { itemName(e[1], e[2]), e[3], ("Gathered: %d"):format(got) }
	end
end

function Herbs:Toggle()
	if not win then build() end
	if win:IsShown() then win:Hide() else win:Show(); self:Refresh() end
end

function Herbs:OnLogin()
	buildMini()
	-- The skill list can arrive a moment after login.
	C_Timer.After(2, function() Herbs:RefreshMini() end)
	ME:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() Herbs:RefreshMini() end) end)
	ME:On("CHAT_MSG_LOOT", onLoot)
	-- Banner when a skill-up unlocks a new herb.
	local last = self:Skill()
	local function skillChanged()
		local now = Herbs:Skill()
		if now and last and now > last and ME.db.alerts.herbs ~= false then
			for _, n in ipairs(NODES) do
				if n[3] > last and n[3] <= now and n[3] > 1 and ME.Alerts then
					ME.Alerts:Show("herb" .. n[1], itemIcon(n[1]), "NEW HERB", ("You can now gather %s"):format(itemName(n[1], n[2])), 0.35, 1, 0.45)
				end
			end
		end
		last = now or last
		Herbs:Refresh()
	end
	ME:On("SKILL_LINES_CHANGED", skillChanged)
	ME:On("CHAT_MSG_SKILL", skillChanged)
	ME:On("TRADE_SKILL_LIST_UPDATE", skillChanged)
end
