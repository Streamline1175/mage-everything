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
