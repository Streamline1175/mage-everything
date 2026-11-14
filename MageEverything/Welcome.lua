-- MageEverything: welcome / setup guide.
-- Opens on first install (or after saved settings are wiped) and once after
-- each update. Reopen any time with /mage welcome.
local ADDON, ME = ...
local Welcome = ME:NewModule("Welcome")
local FX = ME.FX

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ME.LOGO = MEDIA .. "Logo"

-- Shown on the first page after an update. Newest first.
local CHANGES = {
	["1.1.1"] = {
		"Frames can now be moved from the game's Edit Mode: open it and drag the blue boxes.",
		"Shift-drag the XP bar to move it at any time.",
		"Drag handles are larger, so the thin XP bar is easy to grab.",
	},
	["1.1.0"] = {
		"New logo and this welcome guide.",
		"Spell data matched to the Forever 1.60.1 game tables.",
		"Procs read from mana cost and cast time, which stay visible in combat.",
		"Rotation fixes for Heating Up, Arcane Blast, Fingers of Frost and Winter's Chill.",
	},
}

local W, H = 600, 440
local frame, pages, pageIndex, firstRun = nil, {}, 1, false

---------------------------------------------------------------------------
-- Small widget helpers
---------------------------------------------------------------------------
local function text(parent, font, str, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if str then fs:SetText(str) end
	if r then fs:SetTextColor(r, g, b) end
	return fs
end

local function button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 110, 24)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

-- Checkbox bound to a settings table entry.
local function checkbox(parent, label, tbl, key, onChange)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(260, 22)
	local box = b:CreateTexture(nil, "BACKGROUND")
	box:SetSize(18, 18)
	box:SetPoint("LEFT", 0, 0)
	box:SetColorTexture(0.05, 0.06, 0.12, 1)
	local edge = b:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT", box, -1, 1)
	edge:SetPoint("BOTTOMRIGHT", box, 1, -1)
	edge:SetColorTexture(0.41, 0.8, 0.94, 0.9)
	box:SetDrawLayer("ARTWORK")
	local mark = b:CreateTexture(nil, "OVERLAY")
	mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	mark:SetSize(22, 22)
	mark:SetPoint("CENTER", box, "CENTER", 0, 0)
	local fs = text(b, "GameFontHighlight", label)
	fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)
	function b:Refresh() mark:SetShown(tbl[key] and true or false) end
	b:SetScript("OnClick", function(self)
		tbl[key] = not tbl[key]
		self:Refresh()
		if onChange then onChange() end
	end)
	b:Refresh()
	return b
end

local function applyAll()
	for _, m in ipairs(ME.modules) do
		if m.ApplySettings then pcall(m.ApplySettings, m) end
	end
	if ME.Reminders then ME.Reminders:Update() end
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function newPage(title)
	local p = CreateFrame("Frame", nil, frame)
	p:SetPoint("TOPLEFT", 28, -132)
	p:SetPoint("BOTTOMRIGHT", -28, 52)
	p.title = title
	p:Hide()
	pages[#pages + 1] = p
	return p
end

local function paragraph(p, str, anchor, gap, font, r, g, b)
	local fs = text(p, font or "GameFontHighlight", str, r, g, b)
	fs:SetWidth(W - 56)
	fs:SetSpacing(3)
	if anchor then
		fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 10))
	else
		fs:SetPoint("TOPLEFT", 0, 0)
	end
	return fs
end

local function buildPages()
	-- 1. Welcome / what's new -----------------------------------------------
	local p = newPage("Welcome")
	p.body = paragraph(p, "")
	p.OnShow = function(self)
		local lines = {}
		if firstRun then
			lines[#lines + 1] = "Your mage companion for WoW Forever is installed."
			lines[#lines + 1] = ""
			lines[#lines + 1] = "|cff69ccf0What it does|r"
			lines[#lines + 1] = "  - Shows the best spell to press next, with its keybind and the reason"
			lines[#lines + 1] = "  - Warns you to interrupt, root, shield or recover mana"
			lines[#lines + 1] = "  - Pops a banner when a proc is ready"
			lines[#lines + 1] = "  - Tracks your cooldowns and flashes them when they return"
			lines[#lines + 1] = "  - Replaces the XP bar with one themed to your talent tree"
			lines[#lines + 1] = "  - Reminds you about buffs, water and mana gems out of combat"
			lines[#lines + 1] = ""
			lines[#lines + 1] = "The next few pages take about a minute."
		else
			lines[#lines + 1] = ("Updated to version |cff69ccf0%s|r."):format(ME.version)
			lines[#lines + 1] = ""
			lines[#lines + 1] = "|cff69ccf0What's new|r"
			for _, line in ipairs(CHANGES[ME.version] or { "Maintenance update." }) do
				lines[#lines + 1] = "  - " .. line
			end
			lines[#lines + 1] = ""
			lines[#lines + 1] = "Your settings and frame positions were kept. Page through for a refresher, or close this window."
		end
		self.body:SetText(table.concat(lines, "\n"))
	end

	-- 2. Your mage ------------------------------------------------------------
	p = newPage("Your mage")
	local specPage = p
	p.body = paragraph(p, "")
	local label = paragraph(p, "Rotation used:", p.body, 16, "GameFontNormal")
	local specButtons = {}
	local function refreshSpec()
		for _, b in ipairs(specButtons) do
			local on = (ME.db.specOverride or "AUTO") == b.value
			b:SetAlpha(on and 1 or 0.55)
			if on then b:LockHighlight() else b:UnlockHighlight() end
		end
	end
	for i, v in ipairs({ "AUTO", "ARCANE", "FIRE", "FROST" }) do
		local b = button(p, v == "AUTO" and "Automatic" or FX.themes[v].name, 104, function()
			ME.db.specOverride = v
			ME.Spec:Update()
			refreshSpec()
			specPage:OnShow()
		end)
		b.value = v
		b:SetPoint("TOPLEFT", label, "BOTTOMLEFT", (i - 1) * 110, -8)
		specButtons[i] = b
	end
	p.OnShow = function(self)
		local t = FX.Theme()
		local pts = ME.specPoints
		local known = 0
		for key in pairs(ME.Spells.DEFS) do
			if ME.Known(key) then known = known + 1 end
		end
		local lines = {
			("Level |cffffffff%d|r mage, playing |cff%02x%02x%02x%s|r."):format(UnitLevel("player") or 1,
				t.r * 255, t.g * 255, t.b * 255, t.name),
			("Talent points:  Arcane |cffb873ff%d|r   Fire |cffff8c1a%d|r   Frost |cff73d9ff%d|r"):format(
				pts.ARCANE, pts.FIRE, pts.FROST),
			("Spells recognised in your spellbook: |cffffffff%d|r"):format(known),
			"",
			"The rotation follows the tree with the most points, and switches by itself when you respec. "
				.. "Before your first talent point it uses a simple leveling list.",
		}
		if not ME.specDetected then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "|cffffaa33Talent points could not be read on this client - pick a tree below.|r"
		end
		self.body:SetText(table.concat(lines, "\n"))
		refreshSpec()
	end

	-- 3. Reading the display ----------------------------------------------------
	p = newPage("Reading the display")
	local demo = CreateFrame("Frame", nil, p)
	demo:SetSize(W - 56, 78)
	demo:SetPoint("TOPLEFT", 0, 0)
	local function demoIcon(size, key, x, caption, r, g, b)
		local icon = FX.Icon(demo, size)
		icon.cd:Hide()
		icon:SetPoint("LEFT", demo, "LEFT", x, 8)
		icon.tex:SetTexture(ME.SpellIcon(key))
		FX.Border(icon, 1, r or 0, g or 0, b or 0, 1)
		local fs = text(demo, "GameFontNormalSmall", caption, r or 1, g or 0.82, b or 0)
		fs:SetPoint("TOP", icon, "BOTTOM", 0, -3)
		return icon
	end
	demoIcon(38, "Counterspell", 60, "Reaction", 1, 0.82, 0.2)
	local mainIcon = demoIcon(54, "Frostbolt", 150, "Cast now", 0.45, 0.85, 1)
	FX.Glow(mainIcon):Start()
	demoIcon(32, "FireBlast", 250, "Next")
	demoIcon(32, "FrostNova", 292, "Then")
	demoIcon(38, "IceBlock", 400, "Low health", 1, 0.2, 0.2)
	paragraph(p, table.concat({
		"|cff73d9ffCast now|r - the big icon. The corner shows your keybind; the line under it says why. "
			.. "It glows for a proc and turns red when the target is out of range.",
		"|cffffffffNext / Then|r - what is likely to follow, so you can plan a step ahead.",
		"|cffffd133Reaction|r - appears only when needed: Counterspell, Frost Nova, Ice Barrier, Cold Snap, Evocation.",
		"|cffff4040Low health|r - a pulsing icon with your best defensive when health drops under the threshold.",
		"Below the display sit thin health and mana bars and the cooldown row. Proc banners appear above your character.",
	}, "\n"), demo, 12)

	-- 4. Quick setup ---------------------------------------------------------------
	p = newPage("Quick setup")
	local intro = paragraph(p, "Choose what to show. Everything here can be changed later with |cff69ccf0/mage|r.")
	local db = ME.db
	local items = {
		{ "Next-spell display", db.hud, "enabled" },
		{ "Cooldown row", db.cooldowns, "enabled" },
		{ "Proc banners", db.alerts, "enabled" },
		{ "Proc sound", db.alerts, "sound" },
		{ "Mage experience bar", db.xp, "enabled" },
		{ "Hide the default XP bar (needs /reload)", db.xp, "hideBlizzard" },
		{ "Clickable reminders", db.reminders, "enabled" },
		{ "Low health / mana alerts", db.panic, "enabled" },
		{ "Sell junk at vendors", db.qol, "sellJunk" },
		{ "Repair at vendors", db.qol, "autoRepair" },
	}
	p.checks = {}
	for i, it in ipairs(items) do
		local c = checkbox(p, it[1], it[2], it[3], applyAll)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		c:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", col * 275, -12 - row * 26)
		p.checks[i] = c
	end
	local move = button(p, "Move the frames", 150, function()
		Welcome:Close()
		ME:SetLocked(false)
	end)
	move:SetPoint("BOTTOMLEFT", 0, 4)
	local moveHint = text(p, "GameFontDisableSmall", "Closes this guide and unlocks everything for dragging. Type /mage lock when done. Edit Mode shows the same handles.")
	moveHint:SetPoint("LEFT", move, "RIGHT", 10, 0)
	moveHint:SetWidth(360)
	p.OnShow = function(self)
		for _, c in ipairs(self.checks) do c:Refresh() end
	end

	-- 5. Good to know ---------------------------------------------------------------
	p = newPage("Good to know")
	paragraph(p, table.concat({
		"|cff69ccf0Commands|r",
		"  /mage                   options",
		"  /mage unlock  |  lock   move the frames (or open Edit Mode; Shift-drag the XP bar)",
		"  /mage portals           teleport and portal menu",
		"  /mage spec fire         force a rotation (auto, arcane, fire, frost)",
		"  /mage diag              show what the game lets the addon read",
		"  /mage welcome           this guide",
		"",
		"|cff69ccf0What the game allows|r",
		"  - No addon may press buttons for you: the display shows the key, you press it.",
		"  - In combat the game hides exact health, mana and buffs from addons. Suggestions use what "
			.. "stays visible - cooldowns, spell costs, cast times and your own casts - so a few things "
			.. "(Fingers of Frost, whether a root broke early) can be missed.",
		"",
		"If a suggestion looks wrong, run |cff69ccf0/mage diag|r in and out of combat and compare.",
	}, "\n"))
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function showPage(i)
	pageIndex = math.max(1, math.min(#pages, i))
	for n, p in ipairs(pages) do p:SetShown(n == pageIndex) end
	local p = pages[pageIndex]
	if p.OnShow then
		local ok, err = pcall(p.OnShow, p)
		if not ok then ME:Error("welcome page", err) end
	end
	frame.pageTitle:SetText(p.title)
	frame.back:SetEnabled(pageIndex > 1)
	frame.next:SetText(pageIndex == #pages and "Finish" or "Next")
	for n, dot in ipairs(frame.dots) do
		local t = FX.Theme()
		if n == pageIndex then dot:SetColorTexture(t.r, t.g, t.b, 1) else dot:SetColorTexture(1, 1, 1, 0.2) end
	end
end

local function build()
	frame = CreateFrame("Frame", "MageEverythingWelcome", UIParent)
	frame:SetSize(W, H)
	frame:SetPoint("CENTER", 0, 40)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	if UISpecialFrames then table.insert(UISpecialFrames, "MageEverythingWelcome") end -- Escape closes

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.035, 0.04, 0.085, 0.97)
	frame.border = FX.Border(frame, 1, 0.41, 0.8, 0.94, 1)

	-- Header band with a three-school gradient line under it.
	local band = frame:CreateTexture(nil, "BORDER")
	band:SetPoint("TOPLEFT")
	band:SetPoint("TOPRIGHT")
	band:SetHeight(112)
	band:SetColorTexture(1, 1, 1, 1)
	band:SetGradient("VERTICAL", CreateColor(0.04, 0.05, 0.1, 0), CreateColor(0.16, 0.1, 0.3, 0.9))
	local schools = { FX.themes.ARCANE, FX.themes.FIRE, FX.themes.FROST }
	for i, t in ipairs(schools) do
		local line = frame:CreateTexture(nil, "ARTWORK")
		line:SetHeight(2)
		line:SetWidth(W / 3)
		line:SetPoint("TOPLEFT", (i - 1) * W / 3, -112)
		line:SetColorTexture(t.r, t.g, t.b, 1)
	end

	-- Logo with a slow ring behind it and a pop on open.
	local logoHolder = CreateFrame("Frame", nil, frame)
	logoHolder:SetSize(92, 92)
	logoHolder:SetPoint("TOPLEFT", 22, -10)
	local ring = FX.Ring(logoHolder, 150, 24)
	ring:SetAlpha(0.35)
	ring:SetVertexColor(0.6, 0.5, 1)
	local logo = logoHolder:CreateTexture(nil, "ARTWORK")
	logo:SetAllPoints()
	logo:SetTexture(ME.LOGO)
	frame.logoPop = FX.Pop(logoHolder, 1.6, 0.35)
	local sheen = FX.Pulse(ring, 0.45, 0.15, 2.2)
	sheen:Play()

	local title = text(frame, "GameFontNormalHuge", "|cff69ccf0Mage|r Everything")
	title:SetPoint("TOPLEFT", logoHolder, "TOPRIGHT", 18, -16)
	local sub = text(frame, "GameFontHighlight", "")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	frame.subtitle = sub
	frame.pageTitle = text(frame, "GameFontNormalLarge", "")
	frame.pageTitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -30)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() Welcome:Close() end)

	frame.back = button(frame, "Back", 90, function() showPage(pageIndex - 1) end)
	frame.back:SetPoint("BOTTOMLEFT", 24, 16)
	frame.next = button(frame, "Next", 110, function()
		if pageIndex == #pages then Welcome:Close() else showPage(pageIndex + 1) end
	end)
	frame.next:SetPoint("BOTTOMRIGHT", -24, 16)

	buildPages()

	frame.dots = {}
	for i = 1, #pages do
		local dot = frame:CreateTexture(nil, "ARTWORK")
		dot:SetSize(10, 4)
		dot:SetPoint("BOTTOM", frame, "BOTTOM", (i - (#pages + 1) / 2) * 16, 26)
		frame.dots[i] = dot
	end

	-- Closing by any route (button, Escape) records that this version was seen.
	frame:SetScript("OnHide", function() ME.db.seenVersion = ME.version end)
end

function Welcome:Open(asFirstRun)
	if not frame then build() end
	if asFirstRun ~= nil then firstRun = asFirstRun end
	frame.subtitle:SetText(firstRun and "Welcome - let's get you set up" or ("Version " .. ME.version))
	showPage(1)
	frame:Show()
	frame.logoPop:Stop()
	frame.logoPop:Play()
end

function Welcome:Close()
	if frame then frame:Hide() end
end

function Welcome:Toggle()
	if frame and frame:IsShown() then self:Close() else self:Open() end
end

function Welcome:OnLogin()
	local seen = ME.db.seenVersion
	if seen == ME.version then return end
	firstRun = (seen == nil)
	-- Wait for the world (and talent / spellbook data) before opening, and
	-- never open on top of a fight.
	C_Timer.After(2, function()
		if InCombatLockdown() then
			ME:AfterCombat(function() Welcome:Open(firstRun) end)
		else
			Welcome:Open(firstRun)
		end
	end)
end
