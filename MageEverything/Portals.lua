-- MageEverything: teleport / portal menu.
-- Left-click a city to teleport, right-click to open a portal. Buttons are
-- secure (the click casts the spell), so the menu is only built, shown and
-- hidden out of combat.
local _, ME = ...
local Portals = ME:NewModule("Portals")
local FX = ME.FX

local root
local rows = {}

local function known(def)
	local id, name = ME.Spells.ResolveDef(def)
	return id, name
end

function Portals:Rebuild()
	if not root or InCombatLockdown() then return end
	local n = 0
	for _, city in ipairs(ME.Spells.PORTALS) do
		local tpID, tpName = known(city.tp)
		local poID, poName = known(city.portal)
		if tpID or poID then
			n = n + 1
			local b = rows[n]
			if not b then
				b = CreateFrame("Button", "MageEverythingPortal" .. n, root, "SecureActionButtonTemplate")
				b:SetSize(170, 26)
				b:RegisterForClicks("AnyUp", "AnyDown")
				b.icon = b:CreateTexture(nil, "ARTWORK")
				b.icon:SetSize(22, 22)
				b.icon:SetPoint("LEFT", 2, 0)
				b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
				local hl = b:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				hl:SetColorTexture(1, 1, 1, 0.12)
				b:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:AddLine(self.city)
					GameTooltip:AddLine(self.tp and "Left-click: Teleport" or "Teleport not learned", 1, 1, 1)
					GameTooltip:AddLine(self.po and "Right-click: Portal" or "Portal not learned", 1, 1, 1)
					GameTooltip:Show()
				end)
				b:SetScript("OnLeave", function() GameTooltip:Hide() end)
				rows[n] = b
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", root, "TOPLEFT", 6, -26 - (n - 1) * 28)
			b.city, b.tp, b.po = city.city, tpID, poID
			b.text:SetText(city.city .. (poID and "" or " |cff888888(teleport)|r"))
			local iconID = tpID or poID
			local tex = iconID and ME.Try(C_Spell.GetSpellTexture, iconID)
			b.icon:SetTexture(tex or "Interface\\Icons\\Spell_Arcane_PortalDalaran")
			b:SetAttribute("type1", tpID and "spell" or nil)
			b:SetAttribute("spell1", tpID)
			b:SetAttribute("type2", poID and "spell" or nil)
			b:SetAttribute("spell2", poID)
			b:Show()
		end
	end
	for i = n + 1, #rows do rows[i]:Hide() end
	root.empty:SetShown(n == 0)
	root:SetHeight(math.max(60, 34 + n * 28))
end

function Portals:Toggle()
	if not root then return end
	if InCombatLockdown() then
		ME:Print("The portal menu can't be opened in combat.")
		return
	end
	if root:IsShown() then
		root:Hide()
	else
		self:Rebuild()
		root:Show()
	end
end

function Portals:OnLogin()
	root = CreateFrame("Frame", "MageEverythingPortals", UIParent)
	root:SetSize(182, 60)
	root:SetFrameStrata("HIGH")
	ME:MakeMovable(root, "portals", "Portals", "CENTER", 320, 0)
	local bg = root:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.04, 0.05, 0.1, 0.92)
	FX.Border(root, 1, 0.41, 0.8, 0.94, 1)
	local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -7)
	title:SetText("Teleports & Portals")
	root.empty = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	root.empty:SetPoint("TOP", 0, -32)
	root.empty:SetText("No teleports learned yet")
	root:Hide()

	-- Close automatically when combat starts (fires just before lockdown).
	ME:On("PLAYER_REGEN_DISABLED", function() root:Hide() end)
	ME:Listen("SPELLS_UPDATED", function()
		if root:IsShown() then Portals:Rebuild() end
	end)
end
