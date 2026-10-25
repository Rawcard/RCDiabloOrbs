-- RCDiabloOrbs_TBC.lua
-- Loaded FIRST by the TBC TOC only.
-- Defines TBC-specific versions of the three orb functions.
-- Main RCDiabloOrbs.lua uses "RC32_X = RC32_X or function(...)"
-- so these definitions win and main lua skips its own versions.

-- makeFrameMovable: identical to MoP version - drag works fine in TBC
RC32_makeFrameMovable = function(frame,button)
	local btnString = "LeftButton"
	if button then
		btnString = button
	end
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag(btnString)
	frame:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
end

-- CreateOrb: TBC version
-- Changes from MoP:
--   1. SecureUnitButtonTemplate (SecureActionButtonTemplate doesn't execute in TBC Anniversary)
--   2. *type1 / *type2 wildcard attributes (required by SecureUnitButtonTemplate)
--   3. HIGH strata (PlayerFrame can't be hidden in TBC, HIGH beats it)
--   4. Tooltip built manually (avoids TacoTip/LibClassicInspector crash on SetUnit)
RC32_CreateOrb = function(parent,name,size,fillTexture,galaxyTexture,offsetX,offsetY,relativePoint,monitorFunc)
	local orb
	local images = "Interface\\AddOns\\RCDiabloOrbs\\images\\"
	orb = CreateFrame("Button",name,UIParent,"SecureUnitButtonTemplate")
	orb:SetHeight(size)
	orb:SetWidth(size)
	orb:SetFrameStrata("HIGH")
	orb.bg = orb:CreateTexture(nil,"OVERLAY")
	orb.bg:SetTexture(images .. "orb_gloss3.tga")
	orb.bg:SetAllPoints(orb)
	orb.filling = orb:CreateTexture(nil,"BACKGROUND")
	orb.filling:SetTexture(images..fillTexture)
	orb.filling:SetPoint("BOTTOMLEFT",3,3)
	orb.filling:SetWidth(defaultOrbSize - 6)
	orb.filling:SetHeight(defaultOrbSize - 6)
	orb.filling:SetAlpha(1)
	local orbGlossHolder = CreateFrame("Frame",nil,orb)
	orbGlossHolder:SetAllPoints(orb)
	orbGlossHolder:SetFrameStrata("BACKGROUND")
	local orbGlossOverlay = orbGlossHolder:CreateTexture(nil,"BACKGROUND")
	orbGlossOverlay:SetTexture(images .. "orb_gloss3.tga")
	orbGlossOverlay:SetAllPoints(orbGlossHolder)
	local newRand = math.random(20,50)
	orb.galaxy1 = CreateGalaxy(orb, images..galaxyTexture.."1.tga",newRand,defaultOrbSize-5,0,0)
	newRand = math.random(30,70)
	orb.galaxy2 = CreateGalaxy(orb,images..galaxyTexture.."2.tga", newRand,defaultOrbSize-5,0,0)
	newRand = math.random(18,27)
	orb.galaxy3 = CreateGalaxy(orb,images..galaxyTexture.."3.tga", newRand,defaultOrbSize-5,0,0)
	orb:SetScript("OnUpdate",monitorFunc)
	orb.fontHolder = CreateFrame("FRAME",nil,orb)
	orb.fontHolder:SetFrameStrata("MEDIUM")
	orb.fontHolder:SetAllPoints(orb)
	orb.font1 = orb.fontHolder:CreateFontString(nil, "OVERLAY")
	orb.font1:SetFont(RC32CharacterData.font,28,"THINOUTLINE")
	orb.font1:SetPoint("CENTER",0,15)
	orb.font2 = orb.fontHolder:CreateFontString(nil,"OVERLAY")
	orb.font2:SetFont(RC32CharacterData.font,16,"THINOUTLINE")
	orb.font2:SetPoint("CENTER",0,-5)

	orb:ClearAllPoints()
	orb:SetPoint(relativePoint,nil,relativePoint,offsetX,offsetY)
	orb:Show()
	orb.filling:SetVertexColor(1,1,1,1)

	orb.menu = function(orb) ToggleDropDownMenu(1, 1, PlayerFrameDropDown, "cursor", 0 ,0) end
	orb:RegisterForClicks("AnyUp")
	orb:SetAttribute("unit","player")
	orb:SetAttribute("*type1","target")
	orb:SetAttribute("*type2","togglemenu")
	orb.tooltip = CreateFrame("GameTooltip","PlayerTooltip",nil,"GameTooltipTemplate")
	orb:SetScript("OnEnter", function()
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
		GameTooltip:ClearLines()
		GameTooltip:AddLine(UnitName("player"), 1, 1, 1)
		local guild = GetGuildInfo("player")
		if guild then GameTooltip:AddLine("<"..guild..">", 0.65, 0.65, 1) end
		GameTooltip:AddLine(UnitClass("player"), 0.8, 0.8, 0.8)
		local hp, hpMax = UnitHealth("player"), UnitHealthMax("player")
		if hpMax > 0 then GameTooltip:AddLine("HP: "..hp.." / "..hpMax, 0.2, 1, 0.2) end
		GameTooltip:Show()
	end)
	orb:SetScript("OnLeave",function()
		GameTooltip:Hide()
	end)

	return orb
end

-- CreatePetOrb: TBC version
-- Changes from MoP:
--   1. SecureUnitButtonTemplate
--   2. *type1 / *type2
--   3. RegisterUnitWatch guarded (doesn't exist in TBC)
--   4. Manual tooltip
RC32_CreatePetOrb = function(parent,name,size,offsetX,offsetY,monitorFunc)
	local orb
	local images = "Interface\\AddOns\\RCDiabloOrbs\\images\\"
	orb = CreateFrame("Button",name,parent,"SecureUnitButtonTemplate")
	orb:SetHeight(size)
	orb:SetWidth(size)
	orb:SetFrameStrata("BACKGROUND")
	orb.bg = orb:CreateTexture(nil,"OVERLAY")
	orb.bg:SetTexture(images .. "orb_gloss3.tga")
	orb.bg:SetAllPoints(orb)
	orb.filling1 = orb:CreateTexture(nil,"BACKGROUND")
	orb.filling1:SetTexture(images.."petFilling_health.tga")
	orb.filling1:SetPoint("BOTTOMLEFT",3,0)
	orb.filling1:SetWidth(size / 2 - 3)
	orb.filling1:SetHeight(size - 6)
	orb.filling1:SetAlpha(1)
	orb.filling2 = orb:CreateTexture(nil,"BACKGROUND")
	orb.filling2:SetTexture(images.."petFilling_power.tga")
	orb.filling2:SetPoint("BOTTOMRIGHT",-3,0)
	orb.filling2:SetWidth(size / 2 - 3)
	orb.filling2:SetHeight(size - 6)
	orb.filling2:SetAlpha(1)
	local orbGlossHolder = CreateFrame("Frame",nil,orb)
	orbGlossHolder:SetAllPoints(orb)
	orbGlossHolder:SetFrameStrata("LOW")
	local orbGlossOverlay = orbGlossHolder:CreateTexture(nil,"BACKGROUND")
	orbGlossOverlay:SetTexture(images .. "orb_gloss3.tga")
	orbGlossOverlay:SetAllPoints(orbGlossHolder)

	orb.divider = CreateFrame("Frame",nil,orb)
	orb.divider.texture = orb.divider:CreateTexture(nil,"OVERLAY")
	orb.divider.texture:SetTexture(images.."middleBar.tga")
	orb.divider:SetAllPoints(true)
	orb.divider.texture:SetAllPoints(true)
	orb.galaxy1 = CreateGalaxy(orb, RC32RotationTextureChoices[1].."1.tga",36,size-8,0,0)
	orb.galaxy2 = CreateGalaxy(orb, RC32RotationTextureChoices[1].."2.tga", 22,size-8,0,0)
	orb.galaxy3 = CreateGalaxy(orb, RC32RotationTextureChoices[1].."3.tga", 29,size-8,0,0)
	orb.galaxy1:SetAlpha(0.3)
	orb.galaxy2:SetAlpha(0.3)
	orb.galaxy3:SetAlpha(0.3)

	orb.fontHolder = CreateFrame("FRAME",nil,orb)
	orb.fontHolder:SetFrameStrata("MEDIUM")
	orb.fontHolder:SetAllPoints(orb)
	orb.font1 = orb.fontHolder:CreateFontString(nil, "OVERLAY")
	orb.font1:SetFont(RC32CharacterData.font,14,"THINOUTLINE")
	orb.font1:SetPoint("CENTER",-20,5)
	orb.font1:SetText("100")
	orb.font2 = orb.fontHolder:CreateFontString(nil,"OVERLAY")
	orb.font2:SetFont(RC32CharacterData.font,14,"THINOUTLINE")
	orb.font2:SetPoint("CENTER",20,5)
	orb.font2:SetText("100")
	orb.font3 = orb.fontHolder:CreateFontString(nil, "OVERLAY")
	orb.font3:SetFont(RC32CharacterData.font,9,"THINOUTLINE")
	orb.font3:SetPoint("CENTER",-20,-8)
	orb.font3:SetText("100")
	orb.font4 = orb.fontHolder:CreateFontString(nil,"OVERLAY")
	orb.font4:SetFont(RC32CharacterData.font,9,"THINOUTLINE")
	orb.font4:SetPoint("CENTER",20,-8)
	orb.font4:SetText("100")

	orb:SetScript("OnUpdate",updatePetValues)

	orb:ClearAllPoints()
	orb:SetPoint("CENTER",offsetX,offsetY)
	orb:Show()

	local r, g, b, a = healthOrb.filling:GetVertexColor()
	orb.filling1:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
	r, g, b, a = manaOrb.filling:GetVertexColor()
	orb.filling2:SetVertexColor(r or 1, g or 1, b or 1, a or 1)

	orb.menu = function(self)
		if UnitExists("pet") then
			local listFrame = _G["DropDownList1"]
			if ToggleDropDownMenu and PetFrameDropDown and listFrame and listFrame.numButtons and listFrame.numButtons > 0 then
				ToggleDropDownMenu(1, nil, PetFrameDropDown, "cursor", 0, 0)
			end
		end
	end
	orb:RegisterForClicks("AnyUp")
	orb:SetAttribute("unit","pet")
	orb:SetAttribute("*type1","target")
	orb:SetAttribute("*type2","menu")
	orb.tooltip = CreateFrame("GameTooltip","PetToolTip",nil,"GameTooltipTemplate")
	orb:SetScript("OnEnter", function()
		if not UnitExists("pet") then return end
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
		GameTooltip:ClearLines()
		GameTooltip:AddLine(UnitName("pet"), 1, 1, 1)
		local petType = UnitCreatureFamily("pet")
		if petType then GameTooltip:AddLine(petType, 0.8, 0.8, 0.8) end
		local hp, hpMax = UnitHealth("pet"), UnitHealthMax("pet")
		if hpMax > 0 then GameTooltip:AddLine("HP: "..hp.." / "..hpMax, 0.2, 1, 0.2) end
		GameTooltip:Show()
	end)
	orb:SetScript("OnLeave",function()
		GameTooltip:Hide()
	end)

	-- RegisterUnitWatch was added in Wrath - not available in TBC
	if RegisterUnitWatch then RegisterUnitWatch(orb) end

	return orb
end
