-- MageEverything: core namespace, saved variables, event bus, shared helpers.
local ADDON, ME = ...
_G.MageEverything = ME

ME.name = ADDON
ME.version = "1.1.0"
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
	},
	reaction = { enabled = true, nova = true, counterspell = true, shields = true, evocation = true },
	panic = { enabled = true, health = 0.35, mana = 0.20 },
	cooldowns = { enabled = true, scale = 1.0 },
	alerts = { enabled = true, sound = true, scale = 1.0 },
	xp = {
		enabled = true, hideBlizzard = true, width = 520, height = 16, showText = true,
		showQuestXP = true, effects = true,
	},
	reminders = { enabled = true, intellect = true, armor = true, conjure = true, gem = true, drink = true, drinkAt = 0.45 },
	portals = { enabled = true },
	qol = { sellJunk = true, autoRepair = true },
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
	local p = self.db.pos[key]
	f:ClearAllPoints()
	if p then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint(point or "CENTER", UIParent, point or "CENTER", x or 0, y or 0)
	end
end

-- Adds a drag handle shown only while frames are unlocked.
function ME:MakeMovable(f, key, label, point, x, y)
	f.meDefault = { point or "CENTER", x or 0, y or 0 }
	self:RestorePosition(f, key, point, x, y)
	f:SetMovable(true)
	f:SetClampedToScreen(true)

	local h = CreateFrame("Frame", nil, f)
	h:SetAllPoints(f)
	h:SetFrameStrata("DIALOG")
	h:EnableMouse(true)
	h:RegisterForDrag("LeftButton")
	local bg = h:CreateTexture(nil, "OVERLAY")
	bg:SetAllPoints()
	bg:SetColorTexture(0.2, 0.7, 1, 0.35)
	local txt = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	txt:SetPoint("CENTER")
	txt:SetText(label or key)
	h:SetScript("OnDragStart", function() f:StartMoving() end)
	h:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local p, _, rp, px, py = f:GetPoint(1)
		ME.db.pos[key] = { p, rp, px, py }
	end)
	h:Hide()
	f.meHandle = h
	f.meKey = key
	self.movers[#self.movers + 1] = f
end

function ME:SetLocked(locked)
	self.db.locked = locked
	for _, f in ipairs(self.movers) do
		f.meHandle:SetShown(not locked)
	end
	self:Fire("LOCK_CHANGED", locked)
	self:Print(locked and "Frames locked." or "Frames unlocked - drag the blue boxes, then /mage lock.")
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
ME:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	MageEverythingDB = MageEverythingDB or {}
	applyDefaults(MageEverythingDB, ME.defaults)
	ME.db = MageEverythingDB
end)

ME:On("PLAYER_LOGIN", function()
	local _, class = UnitClass("player")
	ME.isMage = (class == "MAGE")
	if not ME.isMage then
		-- Class addon: stay completely inert on other classes.
		return
	end
	if not ME.db.enabled then
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
	ME:Fire("READY")
	ME:Print(("v%s loaded. /mage for options."):format(ME.version))
end)
