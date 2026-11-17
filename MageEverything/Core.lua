-- MageEverything: core namespace, saved variables, event bus, shared helpers.
local ADDON, ME = ...
_G.MageEverything = ME

ME.name = ADDON
ME.version = "1.7.0"
ME.modules = {}

---------------------------------------------------------------------------
-- Secret-value helpers
-- The WoW Forever client (interface 16001) uses the modern "secret values"
-- model: in combat many API returns are opaque values that may be passed to
-- widgets but must never be compared, added or branched on in addon code.
-- Every read of a possibly-secret value goes through these helpers.
---------------------------------------------------------------------------
local issecretvalue = issecretvalue or function() return false end
ME.issecret = issecretvalue

-- Returns v when it is a normal value, or `fallback` when it is nil/secret.
function ME.Plain(v, fallback)
	if issecretvalue(v) then return fallback end
	if v == nil then return fallback end
	return v
end

-- Boolean read that treats secret/nil as `fallback` (default false).
function ME.Bool(v, fallback)
	if issecretvalue(v) then return fallback or false end
	return v and true or false
end

-- pcall wrapper returning nil on error (APIs that may not exist or may refuse).
function ME.Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
	return nil
end

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
ME.defaults = {
	enabled = true,
	locked = true,
	specOverride = "AUTO", -- AUTO / ARCANE / FIRE / FROST
	hud = {
		enabled = true, scale = 1.0, alphaOOC = 0.55, showQueue = true, showReason = true,
		showKeybind = true, showBars = true, showRing = true, onlyWithTarget = true,
		aoeThreshold = 3, useBlizzardAssist = false, useWand = true, fireballFiller = false,
		wandFinish = true, wandFinishAt = 0.2, sheepTimer = true, markSheep = true, frostInstant = true,
	},
	reaction = { enabled = true, nova = true, counterspell = true, shields = true, evocation = true,
		polymorph = true, gem = true, magicWard = true },
	panic = { enabled = true, health = 0.35, mana = 0.20 },
	cooldowns = { enabled = true, scale = 1.0 },
	alerts = { enabled = true, sound = true, scale = 1.0, herbs = true },
	xp = {
		enabled = true, hideBlizzard = true, width = 520, height = 20, showText = true, showDetail = true,
		showQuestXP = true, effects = true,
	},
	reminders = { enabled = true, intellect = true, armor = true, conjure = true, gem = true, drink = true, drinkAt = 0.45,
		eat = true, eatAt = 0.6, cannibalize = true, healWindow = 30, wand = true, curse = true, trainer = true, nameplates = true },
	portals = { enabled = true },
	qol = { sellJunk = true, autoRepair = true, nodeIcons = false, nodeRange = 20,
		nodeFX = true, nodeFXSize = 36, nodeFXObjectsOnly = true, nodeFXSound = false },
	reagents = { warn = true, warnBelow = 1, autoBuy = false, keepFree = 2,
		stock = { teleport = 5, portal = 5, powder = 10, feather = 10 } },
	pos = {},
}

local function applyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			applyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

---------------------------------------------------------------------------
-- Event bus
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
ME.eventFrame = frame

function ME:On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		-- Some events may not exist on every build; never let that break loading.
		pcall(frame.RegisterEvent, frame, event)
	end
	list[#list + 1] = fn
end

-- Internal (non-game) messages between modules.
local messages = {}
function ME:Listen(msg, fn)
	messages[msg] = messages[msg] or {}
	table.insert(messages[msg], fn)
end
function ME:Fire(msg, ...)
	local list = messages[msg]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then ME:Error(msg, err) end
	end
end

local errorsSeen = {}
function ME:Error(where, err)
	local key = tostring(where) .. tostring(err)
	if errorsSeen[key] then return end
	errorsSeen[key] = true
	ME.lastError = key
	if ME.db and ME.db.debug then
		print("|cffff5555MageEverything error|r", where, err)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then ME:Error(event, err) end
	end
end)

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
function ME:NewModule(name)
	local m = { name = name }
	self.modules[#self.modules + 1] = m
	self[name] = m
	return m
end

function ME:Print(...)
	print("|cff69ccf0Mage Everything|r:", ...)
end

---------------------------------------------------------------------------
-- After-combat queue (for anything touching secure frames)
---------------------------------------------------------------------------
local afterCombat = {}
function ME:AfterCombat(fn)
	if InCombatLockdown() then
		afterCombat[#afterCombat + 1] = fn
	else
		fn()
	end
end
ME:On("PLAYER_REGEN_ENABLED", function()
	if #afterCombat == 0 then return end
	local list = afterCombat
	afterCombat = {}
	for i = 1, #list do
		local ok, err = pcall(list[i])
		if not ok then ME:Error("AfterCombat", err) end
	end
end)

---------------------------------------------------------------------------
-- Movable frames
---------------------------------------------------------------------------
ME.movers = {}

function ME:RestorePosition(f, key, point, x, y)
	if InCombatLockdown() and f:IsProtected() then return end
	local p = self.db.pos[key]
	f:ClearAllPoints()
	if p then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint(point or "CENTER", UIParent, point or "CENTER", x or 0, y or 0)
	end
end

local function savePosition(f)
	f:StopMovingOrSizing()
	local p, _, rp, px, py = f:GetPoint(1)
	if p then ME.db.pos[f.meKey] = { p, rp, px, py } end
end

-- Makes a frame movable three ways:
--   * /mage unlock shows a blue drag handle over it,
--   * the game's Edit Mode shows the same handles while it is open,
--   * with `shiftDrag`, Shift+drag on the frame itself works at any time.
function ME:MakeMovable(f, key, label, point, x, y, shiftDrag)
	f.meDefault = { point or "CENTER", x or 0, y or 0 }
	f.meKey = key
	self:RestorePosition(f, key, point, x, y)
	f:SetMovable(true)
	f:SetClampedToScreen(true)

	-- The handle is padded so thin frames (the XP bar) are easy to grab.
	local h = CreateFrame("Frame", nil, f)
	h:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 10)
	h:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -10)
	h:SetFrameStrata("DIALOG")
	h:SetFrameLevel(100)
	h:EnableMouse(true)
	h:RegisterForDrag("LeftButton")
	-- Light tint and an outline, so the content underneath stays visible.
	local bg = h:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.2, 0.7, 1, 0.16)
	if ME.FX then ME.FX.Border(h, 1, 0.3, 0.8, 1, 0.9) end
	local tab = h:CreateTexture(nil, "ARTWORK")
	tab:SetColorTexture(0.05, 0.25, 0.45, 0.95)
	local txt = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	txt:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 4, 3)
	txt:SetText((label or key) .. " - drag")
	tab:SetPoint("TOPLEFT", txt, "TOPLEFT", -4, 2)
	tab:SetPoint("BOTTOMRIGHT", txt, "BOTTOMRIGHT", 4, -2)
	h:SetScript("OnDragStart", function()
		-- Secure buttons (the sheep button) cannot be moved during a fight.
		if InCombatLockdown() and f:IsProtected() then return end
		f:StartMoving()
	end)
	h:SetScript("OnDragStop", function() savePosition(f) end)
	h:SetScript("OnMouseUp", function() savePosition(f) end)
	h:Hide()
	f.meHandle = h

	if shiftDrag then
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", function(self)
			if IsShiftKeyDown() then
				self.meDragging = true
				self:StartMoving()
			end
		end)
		f:SetScript("OnDragStop", function(self)
			if self.meDragging then
				self.meDragging = nil
				savePosition(self)
			end
		end)
	end
	self.movers[#self.movers + 1] = f
end

function ME:SetLocked(locked, silent)
	self.db.locked = locked
	for _, f in ipairs(self.movers) do
		f.meHandle:SetShown(not locked)
	end
	self:Fire("LOCK_CHANGED", locked)
	if not silent then
		self:Print(locked and "Frames locked." or "Frames unlocked - drag the blue boxes, then /mage lock.")
	end
end

-- Follow the game's Edit Mode: handles appear while it is open.
local unlockedByEditMode = false
function ME:HookEditMode()
	if not (EventRegistry and EventRegistry.RegisterCallback) then return end
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		if ME.active and ME.db.locked then
			unlockedByEditMode = true
			ME:SetLocked(false, true)
		end
	end, ME)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		if ME.active and unlockedByEditMode then
			unlockedByEditMode = false
			ME:SetLocked(true, true)
		end
	end, ME)
end

function ME:ResetPositions()
	wipe(self.db.pos)
	for _, f in ipairs(self.movers) do
		local d = f.meDefault
		self:RestorePosition(f, f.meKey, d[1], d[2], d[3])
	end
	self:Print("Positions reset.")
end

---------------------------------------------------------------------------
-- Small utilities
---------------------------------------------------------------------------
function ME.Short(n)
	if n >= 1e6 then return ("%.2fm"):format(n / 1e6) end
	if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

function ME.Comma(n)
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function ME.Duration(sec)
	if not sec or sec ~= sec or sec == math.huge or sec < 0 then return "--" end
	if sec >= 3600 then return ("%dh %02dm"):format(sec / 3600, (sec % 3600) / 60) end
	if sec >= 60 then return ("%dm"):format(sec / 60 + 0.5) end
	return ("%ds"):format(sec)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Profiles: each character gets its own settings (copied from the first
-- character's on first login). /mage profile lists, shares and copies them.
---------------------------------------------------------------------------
local function characterKey()
	local name = UnitName("player")
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
	if type(name) ~= "string" or name == "" or issecretvalue(name) then return nil end
	return name .. "-" .. tostring(realm or "")
end

function ME:SelectProfile()
	local root = self.root
	local key = characterKey()
	if not key then return false end
	self.charKey = key
	local name = root.chars[key]
	if not name or not root.profiles[name] then
		name = key
		if not root.profiles[name] then
			-- New character: start from the original settings if there are any.
			root.profiles[name] = root.profiles.Default and CopyTable(root.profiles.Default) or {}
		end
		root.chars[key] = name
	end
	applyDefaults(root.profiles[name], self.defaults)
	self.db = root.profiles[name]
	self.profileName = name
	return true
end

-- Finds a profile by name, ignoring case.
function ME:FindProfile(name)
	name = (name or ""):lower()
	for n in pairs(self.root.profiles) do
		if n:lower() == name then return n end
	end
end

ME:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	local root = MageEverythingDB
	if type(root) ~= "table" then root = {} end
	if type(root.profiles) ~= "table" then
		-- Older versions kept one flat settings table: keep it as "Default".
		local old = root
		root = { enabled = old.enabled ~= false, profiles = {}, chars = {} }
		old.enabled = nil
		if next(old) then root.profiles.Default = old end
	end
	root.chars = root.chars or {}
	if root.enabled == nil then root.enabled = true end
	MageEverythingDB = root
	ME.root = root
	if not ME:SelectProfile() then
		-- Character name not available yet: use defaults until login.
		ME.db = {}
		applyDefaults(ME.db, ME.defaults)
	end
end)

ME:On("PLAYER_LOGIN", function()
	local _, class = UnitClass("player")
	ME.isMage = (class == "MAGE")
	if not ME.isMage then
		-- Class addon: stay completely inert on other classes.
		return
	end
	if not ME.charKey then ME:SelectProfile() end
	if not ME.root.enabled then
		ME:Print("Disabled. Type /mage on to enable, then /reload.")
		return
	end
	ME.active = true
	for _, m in ipairs(ME.modules) do
		if m.OnLogin then
			local ok, err = pcall(m.OnLogin, m)
			if not ok then
				ME:Error("init " .. m.name, err)
				ME:Print("|cffff5555" .. m.name .. " failed to start:|r", err)
			end
		end
	end
	-- Never start a session with handles left showing.
	ME.db.locked = true
	pcall(ME.HookEditMode, ME)
	ME:Fire("READY")
	ME:Print(("v%s loaded. /mage for options."):format(ME.version))
end)
