-- MageEverything: reagent check and optional restocking.
--
-- Reagents per spell come from the Forever 1.60.1 game tables:
--   Rune of Teleportation (17031) - every Teleport
--   Rune of Portals       (17032) - every Portal
--   Arcane Powder         (17020) - Arcane Brilliance
--   Light Feather         (17056) - Slow Fall and Study
-- A reminder shows when one you need has run out. Buying at vendors is off
-- unless enabled in the options, and then only tops each reagent up to its
-- own limit while enough bag slots stay free.
local _, ME = ...
local Reagents = ME:NewModule("Reagents")

local LIST = {
	{ id = 17031, key = "teleport", name = "Rune of Teleportation", use = "Teleports" },
	{ id = 17032, key = "portal",   name = "Rune of Portals",       use = "Portals" },
	{ id = 17020, key = "powder",   name = "Arcane Powder",         use = "Arcane Brilliance" },
	{ id = 17056, key = "feather",  name = "Light Feather",         use = "Slow Fall and Study" },
}
Reagents.LIST = LIST

local needed = {} -- key -> true when the player knows a spell that uses it

local function refreshNeeded()
	wipe(needed)
	for _, city in ipairs(ME.Spells.PORTALS) do
		if city.tp and ME.Spells.ResolveDef(city.tp) then needed.teleport = true end
		if city.portal and ME.Spells.ResolveDef(city.portal) then needed.portal = true end
	end
	if ME.Known("ArcaneBrilliance") then needed.powder = true end
	if ME.Known("SlowFall") or ME.Known("Study") then needed.feather = true end
end

local function count(id)
	local n = C_Item and C_Item.GetItemCount and ME.Try(C_Item.GetItemCount, id)
	return ME.Plain(n, 0) or 0
end

local function label(r)
	local n = C_Item and C_Item.GetItemNameByID and ME.Try(C_Item.GetItemNameByID, r.id)
	return type(n) == "string" and n or r.name
end

-- Reagents the player needs and has run low on: { reagent, have }.
function Reagents:Low()
	local db = ME.db.reagents
	local list = {}
	for _, r in ipairs(LIST) do
		if needed[r.key] then
			local have = count(r.id)
			if have < (db.warnBelow or 1) then list[#list + 1] = { reagent = r, have = have, name = label(r) } end
		end
	end
	return list
end

local function freeBagSlots()
	local free = 0
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then return 0 end
	for bag = 0, 4 do
		local n, bagType = C_Container.GetContainerNumFreeSlots(bag)
		-- Only general-purpose bags (type 0) can hold reagents.
		if type(n) == "number" and (bagType == nil or bagType == 0) then free = free + n end
	end
	return free
end

local function money(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		local s = ME.Try(C_CurrencyInfo.GetCoinTextureString, copper)
		if s then return s end
	end
	return ("%dg %ds %dc"):format(copper / 10000, (copper % 10000) / 100, copper % 100)
end

-- Tops each needed reagent up to its limit from the open vendor.
function Reagents:Restock()
	local db = ME.db.reagents
	if not (GetMerchantNumItems and GetMerchantItemID and BuyMerchantItem) then return end
	local byID = {}
	for _, r in ipairs(LIST) do byID[r.id] = r end

	-- Bag slots that may be used: free slots minus the ones to keep empty.
	local spareSlots = math.max(0, freeBagSlots() - (db.keepFree or 0))
	local gold = GetMoney() or 0
	local bought, spent, skipped = {}, 0, {}

	for i = 1, GetMerchantNumItems() do
		local r = byID[GetMerchantItemID(i)]
		if r and needed[r.key] then
			local have = count(r.id)
			local want = (db.stock[r.key] or 0) - have
			if want > 0 then
				local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and ME.Try(C_MerchantFrame.GetItemInfo, i)
				local price = (info and info.price) or 0
				local batch = (info and info.stackCount and info.stackCount > 0) and info.stackCount or 1
				local maxStack = (C_Item.GetItemMaxStackSizeByID and ME.Try(C_Item.GetItemMaxStackSizeByID, r.id)) or 20
				if type(maxStack) ~= "number" or maxStack < 1 then maxStack = 20 end

				-- Room: what fits in a partly filled stack, plus whole spare slots.
				local partial = (maxStack - (have % maxStack)) % maxStack
				local room = partial + spareSlots * maxStack
				local unit = price / batch
				local affordable = unit > 0 and math.floor(gold / unit) or want
				local stock = (info and info.numAvailable and info.numAvailable >= 0) and info.numAvailable * batch or want
				local n = math.min(want, room, affordable, stock)
				n = math.floor(n / batch) * batch

				if n > 0 then
					local perBuy = math.max(1, (GetMerchantItemMaxStack and GetMerchantItemMaxStack(i)) or batch)
					local left = n
					while left > 0 do
						local q = math.min(left, perBuy)
						if batch > 1 then
							BuyMerchantItem(i, 1) -- sold in fixed bundles
							left = left - batch
						else
							BuyMerchantItem(i, q)
							left = left - q
						end
					end
					local cost = unit * n
					gold, spent = gold - cost, spent + cost
					spareSlots = spareSlots - math.ceil(math.max(0, n - partial) / maxStack)
					bought[#bought + 1] = ("%d %s"):format(n, label(r))
				end
				if n < want then
					local why = (room < want) and "bag space" or (affordable < want and "not enough money" or "vendor stock")
					skipped[#skipped + 1] = ("%s (%s)"):format(label(r), why)
				end
			end
		end
	end
	if #bought > 0 then
		ME:Print(("Restocked %s for %s."):format(table.concat(bought, ", "), money(spent)))
	end
	if #skipped > 0 then
		ME:Print("Could not fully restock: " .. table.concat(skipped, ", ") .. ".")
	end
end

function Reagents:OnLogin()
	refreshNeeded()
	ME:Listen("SPELLS_UPDATED", refreshNeeded)
	ME:On("MERCHANT_SHOW", function()
		if ME.db.reagents.autoBuy then
			local ok, err = pcall(Reagents.Restock, Reagents)
			if not ok then ME:Error("restock", err) end
		end
	end)
end
