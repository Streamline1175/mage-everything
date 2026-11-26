-- MageEverything: small leveling conveniences at vendors.
local _, ME = ...
local QoL = ME:NewModule("QoL")

local function money(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		local s = ME.Try(C_CurrencyInfo.GetCoinTextureString, copper)
		if s then return s end
	end
	return ("%dg %ds %dc"):format(copper / 10000, (copper % 10000) / 100, copper % 100)
end

function QoL:OnLogin()
	ME:On("MERCHANT_SHOW", function()
		local db = ME.db.qol
		if db.sellJunk and C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
			local n = C_MerchantFrame.GetNumJunkItems and ME.Try(C_MerchantFrame.GetNumJunkItems)
			if n == nil or n > 0 then
				pcall(C_MerchantFrame.SellAllJunkItems)
				if n and n > 0 then ME:Print(("Sold %d junk item(s)."):format(n)) end
			end
		end
		if db.autoRepair and CanMerchantRepair and ME.Bool(CanMerchantRepair()) then
			local cost, canRepair = GetRepairAllCost()
			if canRepair and cost and cost > 0 and cost <= (GetMoney() or 0) then
				RepairAllItems()
				ME:Print("Repaired for " .. money(cost) .. ".")
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Gathering node icons. Addons cannot add effects to herbs or ore in the
-- world, but the game's own "interact" system can float an icon over the
-- herb, ore or object in front of you. This switches that on (and the
-- Interact Key with it), and puts your previous settings back when off.
---------------------------------------------------------------------------
local NODE_CVARS = { "softTargetInteract", "SoftTargetIconGameObject", "SoftTargetIconInteract",
	"SoftTargetLowPriorityIcons", "SoftTargetInteractRange" }

local function getCVar(name)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	return get and ME.Try(get, name)
end
local function setCVar(name, value)
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if set then pcall(set, name, tostring(value)) end
end

function QoL:ApplyNodeIcons()
	local db = ME.db.qol
	if InCombatLockdown() then
		ME:AfterCombat(function() QoL:ApplyNodeIcons() end)
		return
	end
	if db.nodeIcons then
		if not db.savedNodeCVars then
			db.savedNodeCVars = {}
			for _, name in ipairs(NODE_CVARS) do db.savedNodeCVars[name] = getCVar(name) end
		end
		local any = (Enum.SoftTargetEnableFlags and Enum.SoftTargetEnableFlags.Any) or 3
		setCVar("softTargetInteract", any)
		setCVar("SoftTargetIconGameObject", 1)
		setCVar("SoftTargetIconInteract", 1)
		setCVar("SoftTargetLowPriorityIcons", 1)
		setCVar("SoftTargetInteractRange", db.nodeRange or 20)
	elseif db.savedNodeCVars then
		for name, value in pairs(db.savedNodeCVars) do
			if value ~= nil then setCVar(name, value) end
		end
		db.savedNodeCVars = nil
	end
end

function QoL:ApplySettings()
	self:ApplyNodeIcons()
end

-- The values the option wants, for re-checking and for /mage diag.
function QoL:NodeCVarReport()
	local parts = {}
	for _, name in ipairs(NODE_CVARS) do parts[#parts + 1] = name .. "=" .. tostring(getCVar(name)) end
	return table.concat(parts, " ")
end

local login = QoL.OnLogin
function QoL:OnLogin()
	login(self)
	if ME.db.qol.nodeIcons then self:ApplyNodeIcons() end
	-- A patch or the game's options can reset these: put them back while the
	-- option is on.
	ME:On("PLAYER_ENTERING_WORLD", function()
		if ME.db.qol.nodeIcons then QoL:ApplyNodeIcons() end
	end)
	local watched = {}
	for _, n in ipairs(NODE_CVARS) do watched[n:lower()] = true end
	local pending
	ME:On("CVAR_UPDATE", function(name)
		if not ME.db.qol.nodeIcons or type(name) ~= "string" or not watched[name:lower()] or pending then return end
		pending = true
		C_Timer.After(1, function()
			pending = false
			QoL:ApplyNodeIcons()
		end)
	end)
end
