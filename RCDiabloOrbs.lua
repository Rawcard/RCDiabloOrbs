-- Author      : John Rubin - "Mistra50"
-- Create Date : 8/8/2012 9:03:35 PM
-- Mistra's D3Orbs - rewrite of the previous oUF_D3Orbs_LightWeight
-- The orbs originally appeared in the RothUI by "Zork" and permissive use of all assets and code was given by the original author. 
-- The code in this addon has small chunks of the original still within, but the majority has been rewritten to be free of any external API by John Rubin, aka "Mistra"

--Copyright (C) 2012 John Rubin

--Standard DBAD License.  A mix of MIT and please get my permission before you copy this code license.

--Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

--The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
--The above copyright holder is notified of the intent of redistribution prior to the release of said redistribution.

--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

-- Client compatibility -------------------------------------------------------
-- Retail (11.0+) and WoW Forever removed some old spell and aura functions, so
-- rebuild them from the newer C_Spell / C_UnitAuras ones where they're missing.
-- They're locals: other addons never see them.
local GetSpellInfo = GetSpellInfo or function(spell)
	if spell == nil or not (C_Spell and C_Spell.GetSpellInfo) then return nil end
	local info = C_Spell.GetSpellInfo(spell)
	if info then
		return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
	end
end
local GetSpellCooldown = GetSpellCooldown or function(spell)
	if not (C_Spell and C_Spell.GetSpellCooldown) then return 0, 0, 1 end
	local info = C_Spell.GetSpellCooldown(spell)
	if info then
		return info.startTime, info.duration, info.isEnabled and 1 or 0, info.modRate
	end
	return 0, 0, 1
end
local IsUsableSpell = IsUsableSpell or function(spell)
	if C_Spell and C_Spell.IsSpellUsable then
		return C_Spell.IsSpellUsable(spell)
	end
	return false, false
end
local UnitDebuff = UnitDebuff or function(unit, index, filter)
	if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
		local a = C_UnitAuras.GetDebuffDataByIndex(unit, index, filter)
		if a then
			return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime, a.sourceUnit, nil, nil, a.spellId
		end
	end
end

-- Retail and WoW Forever hide some combat values from addons ("secret
-- values"): they can be shown but not compared or used in math. RC32_Secret
-- tells them apart; on other clients it's always false.
function RC32_Secret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end
-- a yes/no answer we can trust (a hidden one counts as "no")
function RC32_True(v)
	return not RC32_Secret(v) and v and true or false
end

-- Version detection and compatibility layer
local _, _, _, tocVersion = GetBuildInfo()
RC32_TOC_VERSION = tocVersion or 0

-- Expansion detection
RC32_IS_VANILLA = RC32_TOC_VERSION < 20000
RC32_IS_TBC = RC32_TOC_VERSION >= 20000 and RC32_TOC_VERSION < 30000
RC32_IS_WRATH = RC32_TOC_VERSION >= 30000 and RC32_TOC_VERSION < 40000
RC32_IS_CATA = RC32_TOC_VERSION >= 40000 and RC32_TOC_VERSION < 50000
RC32_IS_MOP = RC32_TOC_VERSION >= 50000 and RC32_TOC_VERSION < 60000
RC32_IS_MOP_OR_LATER = RC32_TOC_VERSION >= 50000
RC32_IS_CATA_OR_LATER = RC32_TOC_VERSION >= 40000

-- Show the standard Blizzard unit right-click menu
-- Uses MenuUtil on Dragonflight UI, ToggleDropDownMenu on Classic
-- Unit menu system
local RC32_IS_RETAIL = RC32_TOC_VERSION >= 100000

if not ToggleDropDownMenu then
    ToggleDropDownMenu = function() end
end
if not UIDropDownMenu_Initialize then
    UIDropDownMenu_Initialize = function() end
end

-- Create our own player dropdown if Blizzard's was removed (e.g. by ElvUI)
local RC32_PlayerDropDown = nil
local function RC32_GetPlayerDropDown()
    if RC32_PlayerDropDown then return RC32_PlayerDropDown end
    -- Try Blizzard's first
    if PlayerFrameDropDown then
        RC32_PlayerDropDown = PlayerFrameDropDown
        return RC32_PlayerDropDown
    end
    -- Create our own and initialize it with the SELF unit menu
    RC32_PlayerDropDown = CreateFrame("Frame", "RC32PlayerDropDown", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(RC32_PlayerDropDown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        -- Use Blizzard's built-in unit popup initialization if available
        if UnitPopup_ShowMenu then
            UnitPopup_ShowMenu(self, "SELF", "player")
        end
    end, "MENU")
    return RC32_PlayerDropDown
end

local function RC32_ShowUnitMenu(self, unit)
    if not unit then return end

    if RC32_IS_RETAIL and MenuUtil and MenuUtil.CreateContextMenu then
        self.unit = unit
        self.name = UnitName(unit)
        pcall(MenuUtil.CreateContextMenu, self, function(ownerRegion, rootDescription)
            rootDescription:SetTag("MENU_UNIT_SELF")
        end)
        return
    end

    -- MoP Classic: find or create the dropdown
    local dropdown = nil
    if UnitIsUnit(unit, "player") then
        dropdown = RC32_GetPlayerDropDown()
    elseif unit:match("^pet$") and PetFrameDropDown then
        dropdown = PetFrameDropDown
    elseif unit:match("^party(%d+)$") then
        local n = unit:match("%d+")
        dropdown = _G["PartyMemberFrame"..n.."DropDown"] or PartyMemberFrame1DropDown
    end
    if not dropdown then dropdown = PartyMemberFrame1DropDown end
    if dropdown then
        dropdown.unit = unit
        ToggleDropDownMenu(1, nil, dropdown, self, 0, 0)
    end
end


RC32_ADDON_VERSION = "2.1.8.5"

-- Safe dropdown toggle function (fixes ElvUI compatibility issue)
-- ElvUI skinning can interfere with dropdown button creation, causing nil errors
local function RC32_SafeToggleDropDownMenu(level, value, dropDownFrame, anchorName, xOffset, yOffset)
    -- Force Blizzard to create the dropdown frames/buttons if they don't exist
    if UIDropDownMenu_CreateFrames then
        -- This is Blizzard's function to ensure dropdown list frames exist
        local listFrameName = "DropDownList" .. (level or 1)
        local listFrame = _G[listFrameName]
        if listFrame and (listFrame.numButtons == 0 or listFrame.numButtons == nil) then
            -- Call CreateFrames multiple times to ensure buttons are created
            for i = 1, 8 do
                UIDropDownMenu_CreateFrames(level or 1, i)
            end
        end
    end
    
    -- Now safely call the original function
    if ToggleDropDownMenu then
        ToggleDropDownMenu(level, value, dropDownFrame, anchorName, xOffset, yOffset)
    end
end

-- Power type constants - MoP uses numbers, earlier versions use strings
RC32_POWER_MANA = RC32_IS_MOP_OR_LATER and 0 or "MANA"
RC32_POWER_RAGE = RC32_IS_MOP_OR_LATER and 1 or "RAGE"
RC32_POWER_FOCUS = RC32_IS_MOP_OR_LATER and 2 or "FOCUS"
RC32_POWER_ENERGY = RC32_IS_MOP_OR_LATER and 3 or "ENERGY"
RC32_POWER_RUNIC_POWER = RC32_IS_MOP_OR_LATER and 6 or "RUNIC_POWER"
RC32_POWER_SOUL_SHARDS = RC32_IS_CATA_OR_LATER and (RC32_IS_MOP_OR_LATER and 7 or "SOUL_SHARDS") or nil
RC32_POWER_HOLY_POWER = RC32_IS_CATA_OR_LATER and (RC32_IS_MOP_OR_LATER and 9 or "HOLY_POWER") or nil
RC32_POWER_CHI = RC32_IS_MOP_OR_LATER and 12 or nil
-- Shadow Orbs power index differs between the original MoP client and the modern
-- MoP Classic engine, so resolve it from the game's own enum when available.
RC32_POWER_SHADOW_ORBS = RC32_IS_CATA_OR_LATER and (
	(Enum and Enum.PowerType and Enum.PowerType.ShadowOrbs)
	or SPELL_POWER_SHADOW_ORBS
	or (RC32_IS_MOP_OR_LATER and 13 or "SHADOW_ORBS")
) or nil
RC32_POWER_BURNING_EMBERS = RC32_IS_MOP_OR_LATER and 14 or nil
RC32_POWER_DEMONIC_FURY = RC32_IS_MOP_OR_LATER and 15 or nil

-- Safe UnitPower wrapper that handles version differences
local function rawUnitPower(unit, powerType)
	if powerType == nil then
		return UnitPower(unit)
	end
	-- For pre-MoP, if we got a number, don't pass it
	if not RC32_IS_MOP_OR_LATER and type(powerType) == "number" then
		return UnitPower(unit)
	end
	return UnitPower(unit, powerType)
end

local function rawUnitPowerMax(unit, powerType)
	if powerType == nil then
		return UnitPowerMax(unit)
	end
	-- For pre-MoP, if we got a number, don't pass it
	if not RC32_IS_MOP_OR_LATER and type(powerType) == "number" then
		return UnitPowerMax(unit)
	end
	return UnitPowerMax(unit, powerType)
end

-- These always return plain numbers. When Retail / WoW Forever hide the values
-- in combat, the max is the last one seen out of combat and the current value
-- comes from the readable percentage.
local RC32_powerMaxSeen = {}
function RC32_UnitPowerMax(unit, powerType)
	local mx = rawUnitPowerMax(unit, powerType)
	local key = tostring(unit) .. ":" .. tostring(powerType)
	if RC32_Secret(mx) then
		return RC32_powerMaxSeen[key] or 5
	end
	if mx then RC32_powerMaxSeen[key] = mx end
	return mx
end

function RC32_UnitPower(unit, powerType)
	local v = rawUnitPower(unit, powerType)
	if not RC32_Secret(v) then
		return v
	end
	local mx = RC32_UnitPowerMax(unit, powerType) or 5
	local curve = CurveConstants and CurveConstants.ScaleTo100
	local ok, pct = false, nil
	if UnitPowerPercent then
		ok, pct = pcall(UnitPowerPercent, unit, powerType, curve)
	end
	if not ok or type(pct) ~= "number" or RC32_Secret(pct) then
		return 0
	end
	if not curve then pct = pct * 100 end
	return math.floor(pct / 100 * mx + 0.5)
end

-- combo points as a plain number on every client
function RC32_ComboPoints()
	local cp = GetComboPoints and GetComboPoints("player", "target")
	if cp == nil then cp = UnitPower("player", 4) end
	if RC32_Secret(cp) then
		local mx = RC32_powerMaxSeen["player:4"] or 5
		local curve = CurveConstants and CurveConstants.ScaleTo100
		local ok, pct = false, nil
		if UnitPowerPercent then ok, pct = pcall(UnitPowerPercent, "player", 4, curve) end
		if not ok or type(pct) ~= "number" or RC32_Secret(pct) then return 0 end
		if not curve then pct = pct * 100 end
		return math.floor(pct / 100 * mx + 0.5)
	end
	return tonumber(cp) or 0
end

-- Resolve the Shadow Orbs power index at runtime as a safety net: probe known
-- candidates and cache the one that actually reports a max (Shadow spec only).
-- This self-corrects if the hardcoded/enum index is wrong on this client.
local RC32_shadowOrbPT
function RC32_GetShadowOrbPower()
	if RC32_shadowOrbPT ~= nil then return RC32_shadowOrbPT end
	local cands = {}
	if Enum and Enum.PowerType and Enum.PowerType.ShadowOrbs then cands[#cands+1] = Enum.PowerType.ShadowOrbs end
	if SPELL_POWER_SHADOW_ORBS then cands[#cands+1] = SPELL_POWER_SHADOW_ORBS end
	cands[#cands+1] = RC32_POWER_SHADOW_ORBS or 13
	for _, c in ipairs(cands) do
		if type(c) == "number" then
			local mx = UnitPowerMax("player", c)
			if mx and not RC32_Secret(mx) and mx > 0 then
				RC32_shadowOrbPT = c   -- confirmed valid; cache it
				return c
			end
		end
	end
	return cands[1]  -- best guess; not cached, keep re-checking until Shadow spec
end

-- Check if a class exists in this version
function RC32_ClassExists(className)
	if className == "Monk" then
		return RC32_IS_MOP_OR_LATER
	elseif className == "Death Knight" then
		return RC32_TOC_VERSION >= 30000 -- Wrath+
	end
	return true
end

-- Check if a power type is supported
function RC32_PowerTypeSupported(powerType)
	if powerType == RC32_POWER_HOLY_POWER or powerType == RC32_POWER_SOUL_SHARDS or powerType == RC32_POWER_SHADOW_ORBS then
		return RC32_IS_CATA_OR_LATER
	elseif powerType == RC32_POWER_CHI or powerType == RC32_POWER_BURNING_EMBERS or powerType == RC32_POWER_DEMONIC_FURY then
		return RC32_IS_MOP_OR_LATER
	end
	return true
end

--register the addon message prefix
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix("RC32")
end

--variable setup
RC32localizedDisplayName, RC32className, RC32classNumber = UnitClass("player")
local charClassNumber = 0
local playerInVehicle --bool for detecting whether or not a player is in a vehicle
local defaultOrbSize = 150
local orbFillingTexture = "MDO_orb_filling8.tga"
local fillRotationTexture = "orb_fillRotation"
local images = "Interface\\AddOns\\RCDiabloOrbs\\images\\"
local fonts = "Interface\\Addons\\RCDiabloOrbs\\fonts\\"
healthOrb = nil 

-- Safe SetScale: defers execution to escape tainted call chains
-- (e.g. Blizzard's LoadAddOn triggers ADDON_LOADED in a tainted path where
-- SetScale is blocked even though InCombatLockdown() returns false)
local function safeSetScale(frame, scale)
	C_Timer.After(1, function()
		if InCombatLockdown() then
			local f = CreateFrame("Frame")
			f:RegisterEvent("PLAYER_REGEN_ENABLED")
			f:SetScript("OnEvent", function(self)
				self:UnregisterAllEvents()
				frame:SetScale(scale)
			end)
		else
			frame:SetScale(scale)
		end
	end)
end
manaOrb = nil
local vehicleInUse

--smooth animation variables
local lastHealthValue, newHealthValue

--color preset definitions per class and assignment
orbClassColors = {
	[0] = {health = {r = 0.78, g = 0.61, b = 0.43, a= 1}, mana = {r = 0.8, g = 0, b = 0, a= 1}, animation = "SPELLS\\WhiteRadiationFog.m2", name = "Warrior"}, --warrior preset

	[1] = {health = {r = 0.96, g = 0.55, b = 0.73, a = 1},mana = {r = 0.0, g = 0.44, b = 0.87, a = 1}, animation = "SPELLS\\WhiteRadiationFog.m2", name = "Paladin"}, --paladin preset

	[2] = {health = {r = 0.67, g = 0.83, b = 0.45, a = 1},mana = {r = 1.1, g = 0.5, b = 0.25, a = 1}, animation = "SPELLS\\WhiteRadiationFog.m2", name = "Hunter"}, --hunter preset

	[3] = {health = {r = 1.00, g = 0.96, b = 0.41, a = 1},mana = {r = 1.00, g = 0.96, b = 0.41, a = 1}, animation = "SPELLS\\WhiteRadiationFog.m2", name = "Rogue"}, --rogue preset

	[4] = {health = {r = 1.00, g = 1.00, b = 1.00, a = 1},mana = {r = 0.0, g = 0.44, b = 0.87, a = 1}, animation = "SPELLS\\WhiteRadiationFog.m2", name = "Priest"}, --priest preset

	[5] = {health = {r = 0.77, g = 0.12, b = 0.23, a = 1},mana = {r = 0.35, g = 0.9, b = 0.9, a = 1}, animation = "SPELLS\\WhiteRadiationFog.m2", name = "Death Knight"}, --death knight preset

	[6] = {health = {r = 0.0, g = 0.44, b = 0.87, a = 1},mana = {r = 0.0, g = 0.44, b = 0.87, a = 1}, animation = "SPELLS\\WhiteRadiationFog.m2", name = "Shaman"}, -- shaman preset

	[7] = {health = {r = 0.41, g = 0.80, b = 0.94, a = 1},mana = {r = 0.0, g = 0.44, b = 0.87, a = 1},  animation = "SPELLS\\WhiteRadiationFog.m2", name = "Mage"}, --mage preset

	[8] = {health = {r = 0.58, g = 0.51, b = 0.79, a = 1},mana = {r = 0.0, g = 0.44, b = 0.87, a = 1},  animation = "SPELLS\\WhiteRadiationFog.m2", name = "Warlock"}, --warlock preset

	[9] = {health = {r = 0.33, g = 0.54, b = 0.52, a = 1},mana = {r = 1.00, g = 1.00, b = 1.00, a = 1},  animation = "SPELLS\\GreenRadiationFog.m2", name = "Monk"}, --monk preset

	[10] = {health = {r = 1.00, g = 0.49, b = 0.04, a = 1},mana = {r = 0.0, g = 0.44, b = 0.87, a = 1},  animation = "SPELLS\\WhiteRadiationFog.m2", name = "Druid"}, --druid preset

	[11] = {health = {r = 0.64, g = 0.19, b = 0.79, a = 1},mana = {r = 0.79, g = 0.26, b = 0.99, a = 1},  animation = "SPELLS\\GreenRadiationFog.m2", name = "Demon Hunter"}, --demon hunter preset (Retail)

	[12] = {health = {r = 0.20, g = 0.58, b = 0.50, a = 1},mana = {r = 0.0, g = 0.44, b = 0.87, a = 1},  animation = "SPELLS\\WhiteRadiationFog.m2", name = "Evoker"} --evoker preset (Retail)
}

local fontChoices = {
	[0] = "Interface\\AddOns\\RCDiabloOrbs\\fonts\\Of Wildflowers and Wings.ttf",
	[1] = "FONTS\\FRIZQT__.ttf"  
}


local function getClassColor()
	if RC32classNumber and orbClassColors[RC32classNumber - 1] then
		-- the English class name, so class checks work in every client language
		RC32className = orbClassColors[RC32classNumber - 1].name
		return RC32classNumber - 1
	else
		local num = table.getn(orbClassColors)
		for i=0,num,1 do
			if orbClassColors[i].name == UnitClass("player") then
				RC32className = UnitClass("player")
				return i 
			end
		end
		print("Did not find the class.  "..tostring(UnitClass("player")))
		RC32className = RC32className or RC32localizedDisplayName
		return 0
	end
end
charClassNumber = getClassColor()

--load preset RC32CharacterData default in the event existing data cannot be recovered
local Hr,Hg,Hb,Ha = orbClassColors[charClassNumber].health.r, orbClassColors[charClassNumber].health.g, orbClassColors[charClassNumber].health.b, orbClassColors[charClassNumber].health.a
local Mr,Mg,Mb,Ma = orbClassColors[charClassNumber].mana.r, orbClassColors[charClassNumber].mana.g, orbClassColors[charClassNumber].mana.b, orbClassColors[charClassNumber].mana.a

local defaultsTable = {
	--health orb vars
	healthOrb = {show = true, scale = 1,textures = {fill = "MDO_orb_filling2.tga", rotation = "orb_rotation_bubbles"}, orbColor = {r = Hr, g = Hg, b = Hb, a= Ha}, galaxy = {r = Hr, g = Hg, b = Hb, a= Ha}, font1 = {r=1,g=1,b=1,a=1,show = true}, font2 = {r=1,g=1,b=1,a=1,show = true}, formatting = {truncated = true, commaSeparated = false}},

	--mana orb vars
	manaOrb = {show = true, scale = 1, textures = {fill = "MDO_orb_filling2.tga", rotation = "orb_rotation_bubbles"}, orbColor = {r = Mr, g = Mg, b = Mb, a = Ma},galaxy = {r = Mr, g = Mg, b = Mb, a = Ma}, font1 = {r=1,g=1,b=1,a=1,show = true}, font2 = {r=1,g=1,b=1,a=1,show = true}, formatting = {truncated = true, commaSeparated = false}},
	
	--pet orb vars
	petOrb = {scale = 1, enabled = true, showValue = false, showPercentage = true, healthOrb = {r=Hr,g=Hg,b=Hb,a=Ha}, manaOrb={r=Mr,g=Mg,b=Mb,a=Ma}},
	
	--orb fonts
	font = fontChoices[1],
	
	values = {formatted=true},
	
	artwork = {show = true},
	
	powerFrame = {show = true, rotation = 270, maxStackSound = 12},

	combat = {enabled = true, orbColor = {r = 0.8, g = 0, b = 0, a = 1}, galaxy = {r = 0.8, g = 0, b = 0, a = 1}, font1 = {r=1,g=1,b=1,a=1}, font2 = {r=1,g=1,b=1,a=1}},

	druidColors = {
		cat = {orbColor = {r = 1.00, g = 0.96, b = 0.41, a = 1}, galaxy = {r = 1.00, g = 0.96, b = 0.41, a = 1}, font1 = {r=1,g=1,b=1,a=1}, font2 = {r=1,g=1,b=1,a=1}},
		bear = {orbColor = {r = 0.8, g = 0, b = 0, a= 1}, galaxy = {r = 0.8, g = 0, b = 0, a= 1}, font1 = {r=1,g=1,b=1,a=1}, font2 = {r=1,g=1,b=1,a=1}},
		moonkin = {orbColor = {r = 0.0, g = 0.44, b = 0.87, a = 1}, galaxy = {r = 0.0, g = 0.44, b = 0.87, a = 1}, font1 = {r=1,g=1,b=1,a=1}, font2 = {r=1,g=1,b=1,a=1}}, 
		tree = {orbColor = {r = 0.0, g = 0.44, b = 0.87, a = 1}, galaxy = {r = 0.0, g = 0.44, b = 0.87, a = 1}, font1 = {r=1,g=1,b=1,a=1}, font2 = {r=1,g=1,b=1,a=1}}
	},

	defaultPlayerFrame = {show = false}
}

-- Sound options for max stack notification
RC32_MaxStackSounds = {
	{name = "None", id = 0},
	{name = "Power Up", id = 12889},
	{name = "Level Up", id = 888},
	{name = "Ready Check", id = 8960},
	{name = "Raid Warning", id = 8959},
	{name = "PvP Flag", id = 8174},
	{name = "Quest Complete", id = 878},
	{name = "Loot Coin", id = 120},
	{name = "Horn", id = 8457},
	{name = "War Horn", id = 11466},
	{name = "Ding", id = 6674},
	{name = "Bell", id = 5274},
	{name = "Gong", id = 6595},
	{name = "Alarm", id = 8046},
	{name = "Chime", id = 3332},
	{name = "Fanfare", id = 8455},
	{name = "Auction Open", id = 5274},
	{name = "Map Ping", id = 8458},
	{name = "Tell Message", id = 3081},
	{name = "Friend Online", id = 4620},
	{name = "Achievement", id = 12891},
	{name = "Boss Emote", id = 11965},
	{name = "PvP Victory", id = 8454},
	{name = "Humm", id = 6678},
}

local defaultTextures = {
	healthOrb = {fill = "MDO_orb_filling2.tga", rotation = "orb_rotation_bubbles"},
	manaOrb = {fill = "MDO_orb_filling2.tga", rotation = "orb_rotation_bubbles"}
}

RC32FillTextureChoices = {
	[0] = images.. "MDO_orb_filling1.tga",
	[1] = images.. "MDO_orb_filling2.tga",
	[2] = images.. "MDO_orb_filling3.tga",
	[3] = images.. "MDO_orb_filling4.tga",
	[4] = images.. "MDO_orb_filling5.tga",
	[5] = images.. "MDO_orb_filling6.tga",
	[6] = images.. "MDO_orb_filling7.tga",
}

RC32RotationTextureChoices = {
	[0] = images.. "orb_rotation_galaxy",
	[1] = images.. "orb_rotation_bubbles",
	[2] = images.. "orb_rotation_iris"
}

-- Track selected texture indices from dropdowns
RC32SelectedFillIndex = nil
RC32SelectedRotationIndex = nil

-- Texture file names (without path) for saving
RC32FillTextureNames = {
	[0] = "MDO_orb_filling1.tga",
	[1] = "MDO_orb_filling2.tga",
	[2] = "MDO_orb_filling3.tga",
	[3] = "MDO_orb_filling4.tga",
	[4] = "MDO_orb_filling5.tga",
	[5] = "MDO_orb_filling6.tga",
	[6] = "MDO_orb_filling7.tga",
}

RC32RotationTextureNames = {
	[0] = "orb_rotation_galaxy",
	[1] = "orb_rotation_bubbles",
	[2] = "orb_rotation_iris"
}

----------------------------------------------------------Main Data Table for each character -----------------------------------------------------------------
RC32CharacterData = defaultsTable
RC32Textures = defaultTextures
---------------------------------------------------------------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Welcome/Info Popup
---------------------------------------------------------------------------------------------------------------------------------------------------------------
local function CreateWelcomePopup()
	-- Create the main popup frame
	local popup = CreateFrame("Frame", "RC32WelcomePopup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	popup:SetSize(500, 520)
	popup:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
	popup:SetFrameStrata("DIALOG")
	popup:SetMovable(true)
	popup:EnableMouse(true)
	popup:RegisterForDrag("LeftButton")
	popup:SetScript("OnDragStart", popup.StartMoving)
	popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
	popup:SetClampedToScreen(true)
	
	-- Backdrop
	popup:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 }
	})
	
	-- Title
	local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", popup, "TOP", 0, -20)
	title:SetText("|cFFFF6600RC Diablo Orbs|r")
	title:SetFont("Interface\\AddOns\\RCDiabloOrbs\\fonts\\Of Wildflowers and Wings.ttf", 28)
	
	-- Subtitle
	local subtitle = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
	subtitle:SetText("|cFFFFCC00Diablo-Style Health & Mana Orbs for WoW|r")
	
	-- Scrollframe for content
	local scrollFrame = CreateFrame("ScrollFrame", "RC32WelcomeScrollFrame", popup, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -70)
	scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -40, 70)
	
	-- Content frame
	local content = CreateFrame("Frame", nil, scrollFrame)
	content:SetSize(440, 1500)
	scrollFrame:SetScrollChild(content)
	
	-- Info text
	local infoText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	infoText:SetPoint("TOPLEFT", content, "TOPLEFT", 5, 0)
	-- a fixed height: the WoW Forever client can freeze measuring wrapped text
	infoText:SetSize(430, 1490)
	infoText:SetJustifyH("LEFT")
	infoText:SetJustifyV("TOP")
	infoText:SetSpacing(3)
	infoText:SetText(
		"|cFFFFFFFFWelcome to RC Diablo Orbs v" .. RC32_ADDON_VERSION .. "!|r\n\n" ..
		"|cFFFF4444=== WHAT'S NEW (v2.1.8.5) ===|r\n\n" ..
		"|cFF00FF00Works on every WoW client|r\n" ..
		"  • Retail (Midnight), MoP, Cata, Wrath, TBC, Classic Era\n" ..
		"    and WoW Forever\n" ..
		"  • Retail & Forever: orbs keep working in combat, where\n" ..
		"    the game hides exact health and power from addons\n" ..
		"  • Retail: fixed errors at login, Demon Hunter & Evoker\n" ..
		"    colors added, Warlocks use Soul Shards in every spec\n" ..
		"  • Class detection works in every game language\n\n" ..
		"|cFFFF4444=== EARLIER (v1.18) ===|r\n\n" ..
		"|cFF00FF00Battle Rez Panel (NEW!)|r\n" ..
		"  • VuhDo-style raid frame for one-click battle rezzing\n" ..
		"  • 5x5 grid layout (25 players) - configurable via sliders\n" ..
		"  • Class-colored bars with left stripe indicators\n" ..
		"  • Auto-appears when party/raid members die\n" ..
		"  • Tracks your rez spell cooldown and raid charges\n" ..
		"  • Supports: Druid, Death Knight, Warlock\n" ..
		"  • Shift+drag to reposition, clamped to screen\n" ..
		"  • Settings shared account-wide\n" ..
		"  • Type |cFFFFCC00/rcrez|r for commands\n\n" ..
		"|cFF00FF00Settings Profiles|r\n" ..
		"  • Share addon settings across all characters\n" ..
		"  • Save/Load via the Profiles button in menu\n\n" ..
		"|cFF00FF00Enhanced Druid Tooltip|r\n" ..
		"  • Full player info: Title, Guild, Realm, Level/Race/Class\n" ..
		"  • Spec detection via talent tree inspection\n" ..
		"  • Role, Faction, PvP status, Item Level, Zone\n" ..
		"  • Health bar with K/M formatting and percentage\n\n" ..
		"|cFF00FF00Pet Warning Improvements|r\n" ..
		"  • Auto-enabled for Hunters & Warlocks only\n" ..
		"  • DK spec-swap popup asks to enable per spec\n" ..
		"  • X button dismisses and syncs with menu checkbox\n" ..
		"|cFF00FF00Battle Rez Panel Fix|r\n" ..
		"  • Fixed ADDON_ACTION_BLOCKED errors in combat\n" ..
		"  • Panel position now re-applies after combat ends\n\n" ..
		"|cFF00FF00PlayerFrame Fix|r\n" ..
		"  • Fixed blocked PlayerFrame calls when combat\n" ..
		"    started mid-update; now retries after combat\n\n" ..
		"|cFF00FF00Battle Rez Panel|r\n" ..
		"  • Rez count now capped by raid size:\n" ..
		"    10-player = 1, 25-player = 3 (MoP/Cata rules)\n" ..
		"  • Reads live availability from your own rez spell\n" ..
		"  • Out-of-range dead players dim (class colour kept)\n" ..
		"  • Removed skull/coffin box glyphs\n\n" ..
		"|cFF00FF00Power Tracker Fix|r\n" ..
		"  • Fixed Shadow Priest orbs not tracking (power\n" ..
		"    index now resolved from the game, not hardcoded)\n" ..
		"  • Fixed Affliction Soul Shards showing only 1/4\n" ..
		"  • Warlock resource now detected by spec\n" ..
		"    (Soul Shards / Burning Embers / Demonic Fury)\n\n" ..
		"|cFF00FF00Pet Warning|r\n" ..
		"  • Banner shows whenever you're missing a pet\n" ..
		"  • Yes/No dialog now works for all pet classes\n" ..
		"    (Hunter, Warlock, Death Knight)\n" ..
		"  • Dialog only appears at login and spec change\n\n" ..
		"|cFF00FF00Pet Orb Right-Click Menu|r\n" ..
		"  • Right-click the pet orb for a Dismiss Pet menu\n" ..
		"  • Custom menu that works even with ElvUI loaded\n\n" ..
		"|cFF00FF00Bug Fixes|r\n" ..
		"  • Fixed all taint/protected function errors\n" ..
		"  • Fixed orb translucency when changing colors\n" ..
		"  • Safe deferred SetScale to prevent loading errors\n" ..
		"  • Removed TacoTip inspect interference\n\n" ..
		"|cFFFF6600=== FEATURES ===|r\n\n" ..
		"|cFFFFCC00Health & Mana Orbs|r\n" ..
		"  • Large, animated orbs displaying your health and mana\n" ..
		"  • Class-colored by default with full color customization\n" ..
		"  • Multiple fill textures and swirl animations\n" ..
		"  • Adjustable scale for each orb\n" ..
		"  • Show/hide percentage and current values\n\n" ..
		"|cFFFFCC00Pet Orb|r\n" ..
		"  • Combined health/mana orb for your pet\n" ..
		"  • Shows pet health on the left, pet power on the right\n" ..
		"  • Automatically appears when you have an active pet\n" ..
		"  • Can be disabled if not needed\n\n" ..
		"|cFFFFCC00DoT Tracker|r\n" ..
		"  • Tracks your personal debuffs on your current target\n" ..
		"  • Supported classes:\n" ..
		"    |cFFC41F3BDeath Knight|r - Frost Fever, Blood Plague\n" ..
		"    |cFF9482C9Warlock|r - Corruption, Immolate, Agony,\n" ..
		"      Unstable Affliction, Doom\n" ..
		"    |cFFFF7D0AHunter|r - Serpent Sting, Black Arrow\n" ..
		"    |cFFFF7D0ADruid|r - Moonfire, Sunfire, Rake, Rip\n" ..
		"    |cFFFFFFFFPriest|r - Shadow Word: Pain, Vampiric Touch,\n" ..
		"      Devouring Plague\n" ..
		"    |cFF69CCF0Mage|r - Living Bomb, Nether Tempest, Frost Bomb\n" ..
		"    |cFFC79C6EWarrior|r - Rend, Deep Wounds\n" ..
		"    |cFFFFF569Rogue|r - Rupture, Garrote\n" ..
		"    |cFFF58CBAPaladin|r - Censure\n" ..
		"    |cFF0070DEShaman|r - Flame Shock\n" ..
		"    |cFF00FF96Monk|r - Rising Sun Kick\n" ..
		"  • Shift+drag to move  |  /rcdots scale 50-200\n\n" ..
		"|cFFFFCC00Battle Rez Panel|r\n" ..
		"  • One-click battle rezzing for Druids, DKs, Warlocks\n" ..
		"  • Configurable grid: columns, rows, button size\n" ..
		"  • Cooldown timer and raid charge counter\n" ..
		"  • Account-wide settings with options panel\n" ..
		"  • /rcrez test - preview mode  |  /rcrez - help\n\n" ..
		"|cFFFFCC00Combat Color Change|r\n" ..
		"  • Health orb changes color when you enter combat\n" ..
		"  • Visual indicator to know you're in danger!\n" ..
		"  • Can be toggled on/off\n\n" ..
		"|cFFFFCC00Power Tracker|r\n" ..
		"  • Segmented display for combo points, chi, holy power, etc.\n" ..
		"  • Ember-style animated segments\n" ..
		"  • Rotatable and scalable\n" ..
		"  • Optional sound alert when at max stacks\n\n" ..
		"|cFFFFCC00Decorative Artwork|r\n" ..
		"  • Angel and Demon artwork flanking your orbs\n" ..
		"  • Can be shown or hidden\n\n" ..
		"|cFFFF6600=== HOW TO USE ===|r\n\n" ..
		"  • |cFFFFFFFFOpen Menu:|r Click the minimap button or type |cFF00FF00/rc32|r\n" ..
		"  • |cFFFFFFFFMove Orbs:|r Simply drag them with your mouse\n" ..
		"  • |cFFFFFFFFMove DoTs:|r Shift+drag the DoT tracker icons\n" ..
		"  • |cFFFFFFFFMove BRez:|r Shift+drag the Battle Rez panel\n" ..
		"  • |cFFFFFFFFDoT Commands:|r Type |cFF00FF00/rcdots|r for options\n" ..
		"  • |cFFFFFFFFBRez Commands:|r Type |cFF00FF00/rcrez|r for options\n" ..
		"  • |cFFFFFFFFCustomize:|r Click Health/Mana Orb buttons in menu\n" ..
		"  • |cFFFFFFFFProfiles:|r Click Profiles button to share settings\n" ..
		"  • |cFFFFFFFFSave:|r All settings save automatically!\n\n" ..
		"|cFF888888Tip: All frames are movable - just click and drag!|r"
	)
	
	-- "Don't show again" checkbox
	local dontShowCheck = CreateFrame("CheckButton", "RC32DontShowWelcomeCheckButton", popup, "UICheckButtonTemplate")
	dontShowCheck:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 15, 15)
	dontShowCheck.text = dontShowCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	dontShowCheck.text:SetPoint("LEFT", dontShowCheck, "RIGHT", 2, 0)
	dontShowCheck.text:SetText("Don't show this on login")
	dontShowCheck:SetScript("OnClick", function(self)
		if not RC32AccountData then RC32AccountData = {} end
		RC32AccountData.hideWelcomePopup = self:GetChecked()
	end)
	
	-- Close button
	local closeBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	closeBtn:SetSize(100, 25)
	closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 15)
	closeBtn:SetText("Got it!")
	closeBtn:SetScript("OnClick", function()
		popup:Hide()
	end)
	
	-- Open Menu button
	local openMenuBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	openMenuBtn:SetSize(100, 25)
	openMenuBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
	openMenuBtn:SetText("Open Menu")
	openMenuBtn:SetScript("OnClick", function()
		popup:Hide()
		if RC32GUI then
			RC32GUI:Show()
		end
	end)
	
	popup:Hide()
	return popup
end

-- Create the popup (will be available globally)
local RC32WelcomePopup = CreateWelcomePopup()

-- Function to show the welcome popup
function RC32_ShowWelcomePopup()
	if RC32WelcomePopup then
		-- Update checkbox state
		if RC32DontShowWelcomeCheckButton and RC32AccountData then
			RC32DontShowWelcomeCheckButton:SetChecked(RC32AccountData.hideWelcomePopup or false)
		end
		RC32WelcomePopup:Show()
	end
end

-- Function to show popup on login (respects "don't show again" but always shows on new version)
function RC32_ShowWelcomePopupOnLogin()
	if not RC32AccountData then RC32AccountData = {} end
	-- Always show if version changed
	if RC32AccountData.lastSeenVersion ~= RC32_ADDON_VERSION then
		RC32AccountData.lastSeenVersion = RC32_ADDON_VERSION
		RC32AccountData.hideWelcomePopup = false -- Reset the checkbox on new version
		RC32_ShowWelcomePopup()
		return
	end
	if RC32AccountData.hideWelcomePopup then
		return
	end
	RC32_ShowWelcomePopup()
end
---------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Store original PlayerFrame position for restoration
local playerFrameOriginalPoint = nil

-- PlayerFrame is a protected Blizzard frame: EnableMouse/ClearAllPoints/SetPoint
-- on it are blocked in combat. Re-run the whole call once combat drops.
local function retryPlayerFrameAfterCombat(show)
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		handlePlayerFrame(show)
	end)
end

function handlePlayerFrame(show)
	if InCombatLockdown() then
		retryPlayerFrameAfterCombat(show)
		return
	end
	if show then
		-- Restore PlayerFrame visibility (deferred to avoid taint from addon loading)
		C_Timer.After(0, function()
			-- Combat can start during the 1-frame defer, so re-check here.
			if InCombatLockdown() then
				retryPlayerFrameAfterCombat(show)
				return
			end
			PlayerFrame:SetScript("OnEvent", PlayerFrame_OnEvent)
			PlayerFrame:SetAlpha(1)
			PlayerFrame:EnableMouse(true)
			if playerFrameOriginalPoint then
				PlayerFrame:ClearAllPoints()
				PlayerFrame:SetPoint(unpack(playerFrameOriginalPoint))
			end
		end)
	else
		-- Hide PlayerFrame without using protected Hide() function
		-- Save original position first
		if not playerFrameOriginalPoint then
			local point, relativeTo, relativePoint, xOfs, yOfs = PlayerFrame:GetPoint(1)
			if point then
				playerFrameOriginalPoint = {point, relativeTo, relativePoint, xOfs, yOfs}
			end
		end
		C_Timer.After(0, function()
			-- Combat can start during the 1-frame defer, so re-check here.
			if InCombatLockdown() then
				retryPlayerFrameAfterCombat(show)
				return
			end
			PlayerFrame:SetScript("OnEvent", nil)
			PlayerFrame:SetAlpha(0)
			PlayerFrame:EnableMouse(false)
			PlayerFrame:ClearAllPoints()
			PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -9999, 9999)
		end)
	end
end

--hide the player frame by default... we have a pet orb now, so people shouldn't be asking for it anymore.... maybe
--handlePlayerFrame(RC32CharacterData.defaultPlayerFrame.show)


-- Rich tooltip builder - works for any unit ID and version of WoW
-- Adds comprehensive player info: name, title, guild, realm, level/race/class,
-- spec (using talent point distribution for MoP and earlier), role, item level, HP bar
function RC32_BuildRichTooltip(unit)
	if not unit or not UnitExists(unit) then return end
	local isPlayer = UnitIsPlayer(unit)

	-- Format a number with K/M suffixes
	local function shortNum(v)
		if v >= 1000000 then return string.format("%.1fM", v/1000000)
		elseif v >= 1000 then return string.format("%.1fK", v/1000)
		else return tostring(v) end
	end

	-- Name (with title if available)
	local name = UnitName(unit) or "Unknown"
	local title = UnitPVPName and UnitPVPName(unit) or name
	GameTooltip:AddLine(title or name, 1, 1, 1)

	if isPlayer then
		-- Guild + Realm
		local guild, guildRank = GetGuildInfo(unit)
		local _, realm = UnitName(unit)
		if not realm or realm == "" then
			realm = GetRealmName and GetRealmName() or ""
		end
		if guild and realm and realm ~= "" then
			GameTooltip:AddLine("<"..guild.."> ["..realm.."]", 0.65, 0.65, 1)
		elseif guild then
			GameTooltip:AddLine("<"..guild..">", 0.65, 0.65, 1)
		elseif realm and realm ~= "" then
			GameTooltip:AddLine("["..realm.."]", 0.65, 0.65, 1)
		end

		-- Level, Race, Class
		local level = UnitLevel(unit) or 0
		local race = UnitRace and UnitRace(unit) or ""
		local className, classFile = UnitClass(unit)
		local classColor = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
		local cr, cg, cb = 1, 1, 1
		if classColor then cr, cg, cb = classColor.r, classColor.g, classColor.b end
		local levelStr = level > 0 and tostring(level) or "??"
		GameTooltip:AddLine(levelStr.." "..race.." "..(className or ""), cr, cg, cb)

		-- Spec detection: try modern API first, fall back to talent points for older versions
		local specName = nil
		if UnitIsUnit(unit, "player") then
			-- Self: use GetSpecialization if available (MoP+)
			if GetSpecialization and GetSpecializationInfo then
				local specIndex = GetSpecialization()
				if specIndex then
					local _, sName = GetSpecializationInfo(specIndex)
					specName = sName
				end
			end
			-- Fall back: inspect talent tabs and find the one with most points
			if not specName and GetNumTalentTabs and GetTalentTabInfo then
				local best, bestPts = nil, 0
				for i = 1, (GetNumTalentTabs() or 3) do
					local n, _, pts = GetTalentTabInfo(i)
					if n and pts and pts > bestPts then
						best, bestPts = n, pts
					end
				end
				if best and bestPts > 0 then
					specName = best .. " (" .. bestPts .. ")"
				end
			end
		else
			-- Other players: GetInspectSpecialization needs an inspect request (won't block here)
			if GetInspectSpecialization then
				local specID = GetInspectSpecialization(unit)
				if specID and specID > 0 and GetSpecializationInfoByID then
					local _, sName = GetSpecializationInfoByID(specID)
					specName = sName
				end
			end
		end

		-- Role
		local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
		local roleText = nil
		if role == "TANK" then roleText = "Tank"
		elseif role == "HEALER" then roleText = "Healer"
		elseif role == "DAMAGER" then roleText = "Damage"
		end

		if specName then
			GameTooltip:AddDoubleLine("Spec:", specName, 0.8, 0.8, 0.8, 1, 1, 1)
		end
		if roleText then
			GameTooltip:AddDoubleLine("Role:", roleText, 0.8, 0.8, 0.8, 1, 1, 1)
		end

		-- PvP / Faction
		local faction = UnitFactionGroup and UnitFactionGroup(unit)
		if faction then
			local fr, fg, fb = 1, 1, 1
			if faction == "Alliance" then fr, fg, fb = 0.4, 0.5, 1
			elseif faction == "Horde" then fr, fg, fb = 1, 0.3, 0.3 end
			GameTooltip:AddDoubleLine("Faction:", faction, 0.8, 0.8, 0.8, fr, fg, fb)
		end
		if UnitIsPVP and UnitIsPVP(unit) then
			GameTooltip:AddDoubleLine("PvP:", "|cFFFFCC00Enabled|r", 0.8, 0.8, 0.8, 1, 1, 1)
		end

		-- Item Level (self only - GetAverageItemLevel is player-only)
		if UnitIsUnit(unit, "player") and GetAverageItemLevel then
			local overall, equipped = GetAverageItemLevel()
			if equipped and equipped > 0 then
				GameTooltip:AddDoubleLine("Item Level:", string.format("%.2f", equipped), 0.8, 0.8, 0.8, 1, 1, 1)
			end
		end

		-- Zone
		local zone = GetRealZoneText and GetRealZoneText() or nil
		if zone and UnitIsUnit(unit, "player") then
			GameTooltip:AddDoubleLine("Zone:", zone, 0.8, 0.8, 0.8, 0.9, 0.9, 0.7)
		end

		-- Status
		if UnitIsDead and RC32_True(UnitIsDead(unit)) then
			GameTooltip:AddLine("|cFFFF4444Dead|r", 1, 1, 1)
		elseif UnitIsGhost and RC32_True(UnitIsGhost(unit)) then
			GameTooltip:AddLine("|cFFAAAAAAGhost|r", 1, 1, 1)
		elseif UnitIsAFK and RC32_True(UnitIsAFK(unit)) then
			GameTooltip:AddLine("|cFFFFCC00<AFK>|r", 1, 1, 1)
		elseif UnitIsDND and RC32_True(UnitIsDND(unit)) then
			GameTooltip:AddLine("|cFFFFCC00<DND>|r", 1, 1, 1)
		end

	else
		-- NPC
		local classification = UnitClassification and UnitClassification(unit)
		local level = UnitLevel(unit) or 0
		local levelStr = level > 0 and tostring(level) or "??"
		local classText = ""
		if classification == "elite" then classText = " Elite"
		elseif classification == "rare" then classText = " |cFFFFCC00Rare|r"
		elseif classification == "rareelite" then classText = " |cFFFFCC00Rare Elite|r"
		elseif classification == "worldboss" then classText = " |cFFFF4444Boss|r"
		end
		GameTooltip:AddLine(levelStr..classText, 1, 1, 1)
		local creatureType = UnitCreatureType and UnitCreatureType(unit)
		if creatureType then
			GameTooltip:AddDoubleLine("Type:", creatureType, 0.8, 0.8, 0.8, 1, 1, 1)
		end
	end

	-- Health bar with numbers
	local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
	if RC32_Secret(hp) or RC32_Secret(hpMax) then
		-- hidden in combat (Retail / WoW Forever): the bar takes them as they are
		local statusBar = _G["GameTooltipStatusBar"]
		if statusBar then
			statusBar:SetMinMaxValues(0, hpMax)
			statusBar:SetValue(hp)
			statusBar:Show()
			if statusBar.rc32text then statusBar.rc32text:Hide() end
		end
	elseif hpMax and hpMax > 0 then
		GameTooltip:AddLine(" ")
		local statusBar = _G["GameTooltipStatusBar"]
		if statusBar then
			statusBar:SetMinMaxValues(0, hpMax)
			statusBar:SetValue(hp)
			statusBar:Show()
			local hpText = shortNum(hp).." / "..shortNum(hpMax).." ("..math.floor((hp/hpMax)*100).."%)"
			if not statusBar.rc32text then
				statusBar.rc32text = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				statusBar.rc32text:SetPoint("CENTER")
			end
			statusBar.rc32text:SetText(hpText)
			statusBar.rc32text:Show()
		end
	end
end


--function to make any frame object movable
local function makeFrameMovable(frame,button)
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

local function valueFormat(val,petOverride)
	local newVal = val
	if RC32CharacterData.values.formatted == true then
		if val > 1000000 then
			newVal = (floor((val/1000000)*10)/10) .."m"
		elseif val > 99999 then
			newVal = (floor((val/1000)*10)/10) .."k"
		end
	end
	if petOverride then
		if val > 10000 then
			newVal = (floor((val/1000)*10)/10).."k"
		end
	end
	return newVal
end

-- Readable numbers for the orb math. On Retail and WoW Forever the game hides
-- exact health and power in combat (secret values) but still gives a readable
-- percentage, so then the orbs fill from that, on a 0-100 scale. The third
-- value is the real current value (maybe secret) for the number on the orb.
local function RC32_Percent(fn, ...)
	if not fn then return nil end
	local ok, pct = pcall(fn, ...)
	if ok and type(pct) == "number" and not RC32_Secret(pct) then return pct end
	return nil
end
function RC32_ReadHealth(unit)
	local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
	if RC32_Secret(cur) or RC32_Secret(mx) then
		local curve = CurveConstants and CurveConstants.ScaleTo100
		local pct = RC32_Percent(UnitHealthPercent, unit, false, curve)
		if pct and not curve then pct = pct * 100 end
		return pct or 100, 100, cur
	end
	cur, mx = tonumber(cur), tonumber(mx)
	return cur, mx, cur
end
function RC32_ReadPower(unit, powerType)
	local cur, mx
	if powerType then
		cur, mx = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
	else
		cur, mx = UnitPower(unit), UnitPowerMax(unit)
	end
	if RC32_Secret(cur) or RC32_Secret(mx) then
		local curve = CurveConstants and CurveConstants.ScaleTo100
		local pct = RC32_Percent(UnitPowerPercent, unit, powerType or (UnitPowerType and UnitPowerType(unit)), curve)
		if pct and not curve then pct = pct * 100 end
		return pct or 0, 100, cur
	end
	cur, mx = tonumber(cur), tonumber(mx)
	return cur, mx, cur
end
-- the number shown on an orb; a secret value is shown as the game formats it
local function RC32_ValueText(real, value, petOverride)
	if RC32_Secret(real) then
		if AbbreviateNumbers then
			local ok, text = pcall(AbbreviateNumbers, real)
			if ok and text then return text end
		end
		return real -- FontString:SetText accepts a secret value
	end
	return valueFormat(value or 0, petOverride)
end
local function RC32_IsDead(unit)
	local dead = UnitIsDead(unit)
	return not RC32_Secret(dead) and dead and true or false
end
local function RC32_Readable(v, fallback)
	if RC32_Secret(v) or not tonumber(v) then return fallback end
	return v
end

local previousHealthValue = RC32_Readable(UnitHealth("player"), 0)
local lastHealthScale
local function monitorHealth(orb)
	local unitHealthString = "player"
	if vehicleInUse == 1 then
		unitHealthString = "vehicle"
	end
	local currentHealth, maxHealth, realHealth = RC32_ReadHealth(unitHealthString)
	if not maxHealth or maxHealth == 0 then maxHealth = 1 end
	if not currentHealth then currentHealth = 1 end
	-- switching between exact values and percentages (combat on Retail / Forever): jump, don't slide
	if lastHealthScale ~= maxHealth then
		previousHealthValue = currentHealth
		lastHealthScale = maxHealth
	end
	local healthPercentage = currentHealth/maxHealth
	local inverseHealthPercentage = math.abs(healthPercentage - 1)

	local step = 0
	local onePercentHealth = maxHealth / 100

	local newValue = previousHealthValue
	if previousHealthValue < currentHealth then
		step = 1
		if previousHealthValue + (onePercentHealth * step) > currentHealth then
			newValue = currentHealth
		else
			newValue = previousHealthValue + (onePercentHealth * step)
		end
	elseif previousHealthValue > currentHealth then
		step = -1
		if previousHealthValue + (onePercentHealth * step) < currentHealth then
			newValue = currentHealth
		else
			newValue = previousHealthValue + (onePercentHealth * step)
		end
	end
	previousHealthValue = newValue

	local targetTexHeight = (previousHealthValue/maxHealth * orb.filling:GetWidth())
	if targetTexHeight < 1 then targetTexHeight = 1 end
	local newDisplayPercentage = previousHealthValue/maxHealth
	if newDisplayPercentage > 1 then
		newDisplayPercentage = 1
		targetTexHeight = orb.filling:GetWidth()
	end
	local string1 = math.floor(newDisplayPercentage*100)
	if tonumber(string1) == nil then string1 = 0 end
	orb.font1:SetText(string1)

	local string = RC32_ValueText(realHealth, currentHealth)
	orb.font2:SetText(string)

	if RC32_IsDead(unitHealthString) then
		orb.font2:SetText("DEAD :'(")
	end

	orb.filling:SetHeight(targetTexHeight)
	orb.filling:SetTexCoord(0,1,math.abs(newDisplayPercentage - 1),1)
	orb.galaxy1:SetAlpha(newDisplayPercentage)
	orb.galaxy2:SetAlpha(newDisplayPercentage)
	orb.galaxy3:SetAlpha(newDisplayPercentage)
end

local previousPowerValue = RC32_Readable(UnitPower("player"), 0)
local lastPowerScale
local function monitorPower(orb)
	local unitPowerString = "player"
	if vehicleInUse == 1 then
		unitPowerString = "vehicle"
	end
	local currentPower, maxPower, realPower = RC32_ReadPower(unitPowerString)
	if not maxPower or maxPower == 0 then maxPower = 1 end
	if not currentPower then currentPower = 1 end
	if lastPowerScale ~= maxPower then
		previousPowerValue = currentPower
		lastPowerScale = maxPower
	end
	local powerPercentage = currentPower/maxPower
	local inversePowerPercentage = math.abs(powerPercentage - 1)

	local step = 0
	local fillPercentage = 100
	local onePercentPower = maxPower / fillPercentage

	local newValue = previousPowerValue
	if previousPowerValue < currentPower then
		step = 1
		if previousPowerValue + (onePercentPower * step) > currentPower then
			newValue = currentPower
		else
			newValue = previousPowerValue + (onePercentPower * step)
		end
	elseif previousPowerValue > currentPower then
		step = -1
		if previousPowerValue + (onePercentPower * step) < currentPower then
			newValue = currentPower
		else
			newValue = previousPowerValue + (onePercentPower * step)
		end
	end
	previousPowerValue = newValue

	local targetTexHeight = (previousPowerValue/maxPower * orb.filling:GetWidth())
	if targetTexHeight < 1 then targetTexHeight = 1 end
	local newDisplayPercentage = previousPowerValue / maxPower
	if newDisplayPercentage > 1 then
		newDisplayPercentage = 1
		targetTexHeight = orb.filling:GetWidth()
	end
	local string1 = math.floor(newDisplayPercentage*100)
	if tonumber(string1) == nil then string1 = 0 end
	orb.font1:SetText(string1)

	local string = RC32_ValueText(realPower, currentPower)
	orb.font2:SetText(string)

	if RC32_IsDead(unitPowerString) then
		orb.font2:SetText("DEAD :'(")
	end

	orb.filling:SetHeight(targetTexHeight)
	orb.filling:SetTexCoord(0,1,math.abs(newDisplayPercentage-1),1)
	orb.galaxy1:SetAlpha(newDisplayPercentage)
	orb.galaxy2:SetAlpha(newDisplayPercentage)
	orb.galaxy3:SetAlpha(newDisplayPercentage)
end

local previousPetHealth = RC32_Readable(UnitHealth("pet"), 0)
local lastPetHealthScale
local function PetHealthUpdate(orb)
	local unitHealthString = "pet"
	local currentHealth, maxHealth, realHealth = RC32_ReadHealth(unitHealthString)
	if not maxHealth or maxHealth == 0 then maxHealth = 1 end
	if not currentHealth then currentHealth = 0 end
	if lastPetHealthScale ~= maxHealth then
		previousPetHealth = currentHealth
		lastPetHealthScale = maxHealth
	end
	local healthPercentage = currentHealth/maxHealth
	local inverseHealthPercentage = math.abs(healthPercentage - 1)

	local step = 0
	local onePercentHealth = maxHealth / 100

	local newValue = previousPetHealth
	if previousPetHealth < currentHealth then
		step = 1
		if previousPetHealth + (onePercentHealth * step) > currentHealth then
			newValue = currentHealth
		else
			newValue = previousPetHealth + (onePercentHealth * step)
		end
	elseif previousPetHealth > currentHealth then
		step = -1
		if previousPetHealth + (onePercentHealth * step) < currentHealth then
			newValue = currentHealth
		else
			newValue = previousPetHealth + (onePercentHealth * step)
		end
	end
	previousPetHealth = newValue

	local targetTexHeight = (previousPetHealth/maxHealth * (85 * orb:GetScale()))
	if targetTexHeight < 1 then targetTexHeight = 1 end
	local newDisplayPercentage = previousPetHealth/maxHealth
	if newDisplayPercentage > 1 then
		newDisplayPercentage = 0
		targetTexHeight = 1
	end
	local string1 = math.floor(newDisplayPercentage*100)
	if tonumber(string1) == nil then string1 = 0 end
	orb.font1:SetText(string1)
	
	local string = RC32_ValueText(realHealth, currentHealth, true)
	orb.font3:SetText(string)

	orb.filling1:SetHeight(targetTexHeight)
	orb.filling1:SetTexCoord(0,1,math.abs(newDisplayPercentage - 1),1)
	orb.galaxy1:SetAlpha(newDisplayPercentage * 0.2)
	orb.galaxy2:SetAlpha(newDisplayPercentage * 0.2)
	orb.galaxy3:SetAlpha(newDisplayPercentage * 0.2)
end

local previousPetPower = RC32_Readable(UnitPower("pet"), 0)
local lastPetPowerScale
local function PetPowerUpdate(orb)
	local unitPowerString = "pet"
	local currentPower, maxPower, realPower = RC32_ReadPower(unitPowerString)
	if not maxPower or maxPower == 0 then maxPower = 1 end
	if not currentPower then currentPower = 0 end
	if lastPetPowerScale ~= maxPower then
		previousPetPower = currentPower
		lastPetPowerScale = maxPower
	end
	local powerPercentage = currentPower/maxPower
	local inversePowerPercentage = math.abs(powerPercentage - 1)

	local step = 0
	local fillPercentage = 100
	local onePercentPower = maxPower / fillPercentage

	local newValue = previousPetPower
	if previousPetPower < currentPower then
		step = 1
		if previousPetPower + (onePercentPower * step) > currentPower then
			newValue = currentPower
		else
			newValue = previousPetPower + (onePercentPower * step)
		end
	elseif previousPetPower > currentPower then
		step = -1
		if previousPetPower + (onePercentPower * step) < currentPower then
			newValue = currentPower
		else
			newValue = previousPetPower + (onePercentPower * step)
		end
	end
	previousPetPower = newValue

	local targetTexHeight = (previousPetPower/maxPower * (85 * orb:GetScale()))
	if targetTexHeight < 1 then targetTexHeight = 1 end
	local newDisplayPercentage = previousPetPower / maxPower
	if newDisplayPercentage > 1 then
		newDisplayPercentage = 0
		targetTexHeight = 1
	end
	local string1 = math.floor(newDisplayPercentage*100)
	if tonumber(string1) == nil then string1 = 0 end
	orb.font2:SetText(string1)
	
	local string = RC32_ValueText(realPower, currentPower, true)
	orb.font4:SetText(string)	

	orb.filling2:SetHeight(targetTexHeight)
	orb.filling2:SetTexCoord(0,1,math.abs(newDisplayPercentage-1),1)
end

local function updatePetValues(orb)
	PetHealthUpdate(orb)
	PetPowerUpdate(orb)
end

local function CreateGalaxy(orb, file, duration,size,x,y)
	local galaxy = CreateFrame("Frame",nil,orb)
	galaxy:SetHeight(size)
	galaxy:SetWidth(size)
	galaxy:SetPoint("Center",x,y)
	galaxy:SetFrameLevel(4)

	local galTex = galaxy:CreateTexture()
	galTex:SetAllPoints(galaxy)
	galTex:SetTexture(file)
	galTex:SetBlendMode("ADD")
	galTex:SetAlpha(1)
	galaxy.texture = galTex
	
	local animGroup = galaxy:CreateAnimationGroup()
	galaxy.animGroup = animGroup

	local anim1 = galaxy.animGroup:CreateAnimation("Rotation")
	anim1:SetDegrees(360)
	anim1:SetDuration(duration)
	galaxy.animGroup.anim1 = anim1

	animGroup:Play()
	animGroup:SetLooping("REPEAT")
	
	return galaxy
end 

local function CreateGlow(orb)
	local glow = CreateFrame("PlayerModel",nil, orb)
	glow:SetFrameStrata("BACKGROUND")
	glow:SetFrameLevel(5)
	glow:SetAllPoints(orb)
	glow:SetModel(orbClassColors[charClassNumber].animation)
	glow:SetAlpha(1)
	glow:SetScript("OnShow",function()
		glow:SetModel(orbClassColors[charClassNumber].animation)
		glow:SetModelScale(1)
		glow:SetPosition(0,0,0)
	end)
	orb.glow = glow
end

local function menu()
	ToggleDropDownMenu(1, nil,"PlayerFrameDropDown", "cursor", 0, 0)
end

--orb creation experiment
local function CreateOrb(parent,name,size,fillTexture,galaxyTexture,offsetX,offsetY,relativePoint,monitorFunc)
	local orb
	orb = CreateFrame("Button",name,UIParent,"SecureUnitButtonTemplate")
	orb:SetHeight(size)
	orb:SetWidth(size)
	orb:SetFrameStrata("LOW")
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
	orb.fontHolder:SetFrameStrata("LOW")
	orb.fontHolder:SetFrameLevel(orb:GetFrameLevel() + 5)
	orb.fontHolder:SetAllPoints(orb)
	orb.fontHolder:EnableMouse(false)
	orb.font1 = orb.fontHolder:CreateFontString(nil, "OVERLAY")
	orb.font1:SetFont(RC32CharacterData.font,28,"THINOUTLINE")
	orb.font1:SetPoint("CENTER",0,15)
	orb.font2 = orb.fontHolder:CreateFontString(nil,"OVERLAY")
	orb.font2:SetFont(RC32CharacterData.font,16,"THINOUTLINE")
	orb.font2:SetPoint("CENTER",0,-5)
	
	--position defaults
	orb:ClearAllPoints()
	orb:SetPoint(relativePoint,nil,relativePoint,offsetX,offsetY)
	
	--show the orb
	orb:Show()

	--fill the orb with colors! WOO!
	orb.filling:SetVertexColor(1,1,1,1)

	--setup mouseover/click/rightclick events
	-- Mirror RCPartyOrbs exactly: OnLoad first with no menu func, then set type attrs
	orb:SetAttribute("unit","player")
	orb:RegisterForClicks("AnyDown")
	orb.unit = "player"
	SecureUnitButton_OnLoad(orb, "player")
	orb:SetAttribute("type1","target")
	orb:SetAttribute("type2","togglemenu")
	orb.tooltip = CreateFrame("GameTooltip","PlayerTooltip",nil,"GameToolTipTemplate")
	orb:SetScript("OnEnter", function()
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
		if RC32className == "Druid" then
			-- TacoTip/LibClassicInspector crashes on SetUnit for Druids after MoP 5.2
			-- Build a rich tooltip manually to match SetUnit style
			GameTooltip:ClearLines()
			RC32_BuildRichTooltip("player")
			GameTooltip:Show()
		else
			if pcall(GameTooltip.SetUnit, GameTooltip, "player") then
				GameTooltip:Show()
			end
		end
	end)
	orb:SetScript("OnLeave",function()
		GameTooltip:Hide()
	end)


	--place setup the appropriate character events on the health orb
	return orb
end

-- Custom right-click menu for the pet orb.
-- Built from scratch (a plain frame with clickable rows) so it does NOT depend on
-- Blizzard's UIDropDownMenu / PetFrameDropDown, which get tainted/broken when ElvUI
-- is loaded. Same approach we used to get right-click working in RCDiabloUI.
local RC32_petOrbMenu
local function RC32_GetPetOrbMenu()
	if RC32_petOrbMenu then return RC32_petOrbMenu end

	-- Full-screen invisible catcher: any click outside the menu closes it.
	local catcher = CreateFrame("Button", "RC32PetOrbMenuCatcher", UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:EnableMouse(true)
	catcher:RegisterForClicks("AnyUp")
	catcher:Hide()

	local m = CreateFrame("Frame", "RC32PetOrbMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	m:SetFrameStrata("FULLSCREEN_DIALOG")
	m:SetFrameLevel(catcher:GetFrameLevel() + 10)
	m:SetClampedToScreen(true)
	m:SetWidth(136)
	m:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	m:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	m:SetBackdropBorderColor(0.7, 0.6, 0.3, 1)
	m:EnableMouse(true)
	m:Hide()

	catcher:SetScript("OnClick", function() m:Hide() end)
	m:SetScript("OnHide", function() catcher:Hide() end)
	m.catcher = catcher

	m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	m.title:SetPoint("TOP", 0, -8)
	m.title:SetTextColor(1, 0.82, 0)

	-- Helper: build one clickable row.
	local function makeRow(index, label, onClick)
		local b = CreateFrame("Button", nil, m)
		b:SetSize(124, 18)
		b:SetPoint("TOP", m, "TOP", 0, -24 - (index - 1) * 20)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 8, 0)
		b.text:SetText(label)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.18)
		b:SetScript("OnClick", function()
			m:Hide()
			if onClick then onClick() end
		end)
		return b
	end

	makeRow(1, "Dismiss Pet", function()
		if not UnitExists("pet") then return end
		-- PetDismiss() is not a protected function, so this works from a click.
		-- Wrap in pcall in case combat lockdown blocks it on some clients.
		local ok = pcall(PetDismiss)
		if not ok then
			print("|cFF00FF00[RCDiabloOrbs]|r Couldn't dismiss the pet right now (try again out of combat).")
		end
	end)
	makeRow(2, "Cancel", nil)

	-- Height: top pad + title + 2 rows + bottom pad.
	m:SetHeight(24 + 2 * 20 + 8)

	RC32_petOrbMenu = m
	return m
end

-- Toggle the pet-orb menu open/closed, anchored at the cursor.
function RC32_TogglePetOrbMenu()
	local m = RC32_GetPetOrbMenu()
	if m:IsShown() then
		m:Hide()
		return
	end
	if not UnitExists("pet") then return end
	m.title:SetText(UnitName("pet") or "Pet")
	local scale = UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
	m.catcher:Show()
	m:Show()
end

local function CreatePetOrb(parent,name,size,offsetX,offsetY,monitorFunc)
	local orb
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
	-- Don't create glow for pet orb - the PlayerModel can cause white box issues
	-- CreateGlow(orb)
	
	orb.fontHolder = CreateFrame("FRAME",nil,orb)
	orb.fontHolder:SetFrameStrata("LOW")
	orb.fontHolder:SetFrameLevel(orb:GetFrameLevel() + 5)
	orb.fontHolder:SetAllPoints(orb)
	orb.fontHolder:EnableMouse(false)
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
	
	--position defaults
	orb:ClearAllPoints()
	orb:SetPoint("CENTER",offsetX,offsetY)
	
	--show the orb
	orb:Show()

	--fill the orb with colors! WOO!
	local r, g, b, a = healthOrb.filling:GetVertexColor()
	orb.filling1:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
	r, g, b, a = manaOrb.filling:GetVertexColor()
	orb.filling2:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
	
	-- Custom right-click menu for the pet orb (see RC32_GetPetOrbMenu above).
	-- Uses our own frame instead of Blizzard's PetFrameDropDown so it keeps working
	-- when ElvUI is loaded. Left click still targets the pet.
	orb.menu = function(self)
		RC32_TogglePetOrbMenu()
	end
	orb:RegisterForClicks("AnyUp")
	orb:SetAttribute("unit","pet")
	orb:SetAttribute("*type1","target")
	orb:SetAttribute("*type2","menu")
	SecureUnitButton_OnLoad(orb, "pet", orb.menu)
	orb.tooltip = CreateFrame("GameTooltip","PetToolTip",nil,"GameToolTipTemplate")
	orb:SetScript("OnEnter", function()
		if not UnitExists("pet") then return end
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
		if RC32className == "Druid" then
			GameTooltip:ClearLines()
			GameTooltip:AddLine(UnitName("pet"), 1, 1, 1)
			local petType = UnitCreatureFamily("pet")
			if petType then GameTooltip:AddLine(petType, 0.8, 0.8, 0.8) end
			local hp, hpMax = UnitHealth("pet"), UnitHealthMax("pet")
			if not RC32_Secret(hp) and not RC32_Secret(hpMax) and hpMax and hpMax > 0 then GameTooltip:AddLine("HP: "..hp.." / "..hpMax, 0.2, 1, 0.2) end
			GameTooltip:Show()
		else
			if pcall(GameTooltip.SetUnit, GameTooltip, "pet") then
				GameTooltip:Show()
			end
		end
	end)
	orb:SetScript("OnLeave",function()
		GameTooltip:Hide()
	end)
	
	if RegisterUnitWatch then RegisterUnitWatch(orb) end

	--place setup the appropriate character events on the health orb
	return orb
end

local function CreateXMLOrb(parent,name,size,fillTexture,galaxyTexture)
	local orb
	orb = CreateFrame("Button",name,parent,nil)
	orb:SetHeight(size)
	orb:SetWidth(size)
	orb:SetFrameStrata("HIGH")
	orb.bg = orb:CreateTexture(nil,"OVERLAY")
	orb.bg:SetTexture(images .. "orb_gloss3.tga")
	orb.bg:SetAllPoints(orb)
	orb.filling = orb:CreateTexture(nil,"BACKGROUND")
	orb.filling:SetTexture(images..fillTexture)
	orb.filling:SetPoint("BOTTOMLEFT",3,3)
	orb.filling:SetWidth(size - 6)
	orb.filling:SetHeight(size-6)
	orb.filling:SetAlpha(1)
	local orbGlossHolder = CreateFrame("Frame",nil,orb)
	orbGlossHolder:SetAllPoints(orb)
	orbGlossHolder:SetFrameStrata("LOW")
	local orbGlossOverlay = orbGlossHolder:CreateTexture(nil,"BACKGROUND")
	orbGlossOverlay:SetTexture(images .. "orb_gloss3.tga")
	orbGlossOverlay:SetAllPoints(orbGlossHolder)
	local newRand = math.random(20,50)
	orb.galaxy1 = CreateGalaxy(orb, images..galaxyTexture.."1.tga",newRand,size-3,0,0)
	newRand = math.random(30,70)
	orb.galaxy2 = CreateGalaxy(orb,images..galaxyTexture.."2.tga", newRand,size-3,0,0)
	newRand = math.random(18,27)
	orb.galaxy3 = CreateGalaxy(orb,images..galaxyTexture.."3.tga", newRand,size-3,0,0)
	
	CreateGlow(orb)
	orb.fontHolder = CreateFrame("FRAME",nil,orb)
	orb.fontHolder:SetFrameStrata("LOW")
	orb.fontHolder:SetFrameLevel(orb:GetFrameLevel() + 5)
	orb.fontHolder:SetAllPoints(orb)
	orb.fontHolder:EnableMouse(false)
	orb.font1 = orb.fontHolder:CreateFontString(nil, "OVERLAY")
	orb.font1:SetFont(RC32CharacterData.font,28,"THINOUTLINE")
	orb.font1:SetText("100")
	orb.font1:SetPoint("CENTER",0,15)
	orb.font2 = orb.fontHolder:CreateFontString(nil,"OVERLAY")
	orb.font2:SetFont(RC32CharacterData.font,16,"THINOUTLINE")
	orb.font2:SetText("100000")
	orb.font2:SetPoint("CENTER",0,-5)
	
	--position defaults
	orb:ClearAllPoints()
	orb:SetAllPoints(xmlOrbDisplayFrame2)
	
	--show the orb
	orb:Show()

	--fill the orb with colors! WOO!
	orb.filling:SetVertexColor(1,1,1,1)
	return orb
end

local function addArtwork(file,orb,name,offsetX,offsetY,height,width)
	local art = CreateFrame("Frame","RC32"..name,orb)
	art:SetPoint("CENTER",offsetX,offsetY)
	art:SetHeight(height)
	art:SetWidth(width)
	art:SetFrameStrata("MEDIUM")
	art.texture = art:CreateTexture(nil,"OVERLAY")
	art.texture:SetTexture(file)
	art.texture:SetAllPoints(art)
	return art
end

function RC32SetGlobalScale(val)
	val = val/100
	RC32CharacterData.healthOrb.scale = val
	RC32CharacterData.manaOrb.scale = val
	safeSetScale(healthOrb, val)
	safeSetScale(manaOrb, val)
end

function RC32SetOrbScale(orbType, val)
	val = val/100
	if orbType == "health" then
		RC32CharacterData.healthOrb.scale = val
		safeSetScale(healthOrb, val)
	elseif orbType == "mana" then
		RC32CharacterData.manaOrb.scale = val
		safeSetScale(manaOrb, val)
	elseif orbType == "pet" then
		RC32CharacterData.petOrb.scale = val
		safeSetScale(petOrb, val)
	end
end

function RC32SetPowerTrackerRotation(degrees)
	if segmentedPowerTracker then
		segmentedPowerTracker:SetRotation(degrees)
		-- Save to account-wide data so all characters share the same position
		if not RC32AccountData then RC32AccountData = {} end
		RC32AccountData.powerTrackerRotation = degrees
	end
end

function RC32SetPowerTrackerScale(val)
	if segmentedPowerTracker then
		safeSetScale(segmentedPowerTracker, val / 100)
		-- Save to account-wide data so all characters share the same scale
		if not RC32AccountData then RC32AccountData = {} end
		RC32AccountData.powerTrackerScale = val
	end
end

-- Initialize the max stack sound dropdown
function RC32_InitMaxStackSoundDropdown()
	local dropdown = RC32MaxStackSoundDropdown
	if not dropdown then return end
	
	UIDropDownMenu_SetWidth(dropdown, 100)
	UIDropDownMenu_SetButtonWidth(dropdown, 124)
	
	local selectedIndex = RC32CharacterData.powerFrame.maxStackSound or 1
	UIDropDownMenu_SetText(dropdown, RC32_MaxStackSounds[selectedIndex].name)
	
	UIDropDownMenu_Initialize(dropdown, function(self, level)
		for i, sound in ipairs(RC32_MaxStackSounds) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = sound.name
			info.value = i
			info.func = function(self)
				RC32CharacterData.powerFrame.maxStackSound = self.value
				UIDropDownMenu_SetText(dropdown, RC32_MaxStackSounds[self.value].name)
				-- Play preview sound on Master channel for louder volume
				if RC32_MaxStackSounds[self.value].id > 0 then
					PlaySound(RC32_MaxStackSounds[self.value].id, "Master")
				end
			end
			info.checked = (i == (RC32CharacterData.powerFrame.maxStackSound or 1))
			UIDropDownMenu_AddButton(info, level)
		end
	end)
end

-- Menu Background options
RC32_MenuBackgrounds = {
	[1] = {name = "Chicken", file = "CHICKEN_backdrop.tga"},
	[2] = {name = "Sindragosa", file = "Sindragosa.tga"},
	[3] = {name = "Lich King", file = "Lich_King.tga"},
	[4] = {name = "Lich King 2", file = "Lich_King_2.tga"},
	[5] = {name = "Illidan", file = "Illidan.tga"},
	[6] = {name = "Deathwing", file = "Deathwing.tga"},
	[7] = {name = "Alliance", file = "Alliance.tga"},
	[8] = {name = "Horde", file = "Horde.tga"},
}

function RC32_InitMenuBackgroundDropdown()
	local dropdown = RC32MenuBackgroundDropdown
	if not dropdown then return end
	
	UIDropDownMenu_SetWidth(dropdown, 120)
	UIDropDownMenu_SetButtonWidth(dropdown, 144)
	
	local selectedIndex = RC32AccountData and RC32AccountData.menuBackground or 1
	UIDropDownMenu_SetText(dropdown, RC32_MenuBackgrounds[selectedIndex].name)
	
	UIDropDownMenu_Initialize(dropdown, function(self, level)
		for i, bg in ipairs(RC32_MenuBackgrounds) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = bg.name
			info.value = i
			info.func = function(self)
				if not RC32AccountData then RC32AccountData = {} end
				RC32AccountData.menuBackground = self.value
				UIDropDownMenu_SetText(dropdown, RC32_MenuBackgrounds[self.value].name)
				RC32_SetMenuBackground(self.value)
			end
			info.checked = (i == (RC32AccountData and RC32AccountData.menuBackground or 1))
			UIDropDownMenu_AddButton(info, level)
		end
	end)
end

function RC32_SetMenuBackground(index)
	local bg = RC32_MenuBackgrounds[index]
	if bg and RC32GUIBackground then
		RC32GUIBackground:SetTexture("Interface\\AddOns\\RCDiabloOrbs\\images\\"..bg.file)
	end
	-- Set border color based on background
	-- Chicken = white, Sindragosa/Lich King/Lich King 2 = purple, Illidan = yellow, Deathwing = red, Alliance = blue, Horde = red
	local borderColors = {
		[1] = {r = 1, g = 1, b = 1},           -- Chicken = white
		[2] = {r = 0.8, g = 0.3, b = 1},       -- Sindragosa = purple
		[3] = {r = 0.8, g = 0.3, b = 1},       -- Lich King = purple
		[4] = {r = 0.8, g = 0.3, b = 1},       -- Lich King 2 = purple
		[5] = {r = 1, g = 1, b = 0.3},         -- Illidan = yellow
		[6] = {r = 1, g = 0.3, b = 0.3},       -- Deathwing = red
		[7] = {r = 0.3, g = 0.5, b = 1},       -- Alliance = blue
		[8] = {r = 1, g = 0.3, b = 0.3},       -- Horde = red
	}
	local color = borderColors[index] or {r = 1, g = 1, b = 1}
	RC32_SetBorderColor(color.r, color.g, color.b)
end

function RC32MonitorPowers(frame)
	local powerType
	powerFrame.text:SetPoint("CENTER",-1,0)
	if RC32className == "Warlock" then
		if not RC32_IS_CATA_OR_LATER then
			-- Pre-Cata warlocks don't have these resource types
			frame.backDrop:Hide()
			frame.text:Hide()
			return
		end
		local maxResource = 0
		local usable, nomana = IsUsableSpell("Metamorphosis")
		if usable or (not usable and nomana) then
			powerType = RC32_IS_MOP_OR_LATER and 15 or nil
			maxResource = 1000
		end
		usable, nomana = IsUsableSpell("Chaos Bolt")
		if usable or (not usable and nomana) then
			powerType = RC32_IS_MOP_OR_LATER and 14 or nil
			maxResource = 3
		end
		usable, nomana = IsUsableSpell("Soulburn")
		if usable or (not usable and nomana) then
			powerType = RC32_POWER_SOUL_SHARDS
			maxResource = 3
		end
		if not powerType then
			frame.backDrop:Hide()
			frame.text:Hide()
			return
		end
		local numShards = RC32_UnitPower("player",powerType)
		if RC32_IS_MOP_OR_LATER and powerType == 14 then
			numShards = (RC32_UnitPower("player",powerType,true)/10)
		end
		if numShards > 0 then
			if not frame.backDrop:IsVisible() then
				frame.backDrop:Show()
				frame.text:Show()
			end
		else
			if frame.backDrop:IsVisible() then
				frame.backDrop:Hide()
				frame.text:Hide()
			end
		end
		if numShards > 999 then
			powerFrame.text:SetFont(RC32CharacterData.font,15,"THINOUTLINE")
		elseif numShards > 99 then
			powerFrame.text:SetFont(RC32CharacterData.font,18,"THINOUTLINE")
		elseif numShards > 9 then
			powerFrame.text:SetFont(RC32CharacterData.font,24,"THINOUTLINE")
		else
			powerFrame.text:SetFont(RC32CharacterData.font,26,"THINOUTLINE")
		end
		frame.text:SetText(numShards)
		if numShards > 1 then
			powerFrame.text:SetPoint("CENTER",1,0)
		else
			powerFrame.text:SetPoint("CENTER",0,0)
		end
		if numShards >= maxResource then
			powerFrame.fontHolder.animGroup:Play()
		else
			powerFrame.fontHolder.animGroup:Stop()
		end
	elseif RC32className == "Paladin" then
		if not RC32_IS_CATA_OR_LATER or not RC32_POWER_HOLY_POWER then
			frame.backDrop:Hide()
			frame.text:Hide()
			return
		end
		powerType = RC32_POWER_HOLY_POWER
		local numHolyPower = RC32_UnitPower("player",powerType)
		if numHolyPower > 0 then
			if not frame.backDrop:IsVisible() then
				frame.backDrop:Show()
				frame.text:Show()
			end
		else
			if frame.backDrop:IsVisible() then
				frame.backDrop:Hide()
				frame.text:Hide()
			end
		end
		frame.text:SetText(numHolyPower)
		if numHolyPower > 1 then
			powerFrame.text:SetPoint("CENTER",1,0)
		end
		if numHolyPower >=3 then
			powerFrame.fontHolder.animGroup:Play()
		else
			powerFrame.fontHolder.animGroup:Stop()
		end
	elseif RC32className == "Monk" then
		if not RC32_IS_MOP_OR_LATER or not RC32_POWER_CHI then
			frame.backDrop:Hide()
			frame.text:Hide()
			return
		end
		powerType = RC32_POWER_CHI
		local numHolyPower = RC32_UnitPower("player",powerType)
		if numHolyPower > 0 then
			if not frame.backDrop:IsVisible() then
				frame.backDrop:Show()
				frame.text:Show()
			end
		else
			if frame.backDrop:IsVisible() then
				frame.backDrop:Hide()
				frame.text:Hide()
			end
		end
		frame.text:SetText(numHolyPower)
		if numHolyPower > 1 then
			powerFrame.text:SetPoint("CENTER",1,0)
		end
		if numHolyPower >=4 then
			powerFrame.fontHolder.animGroup:Play()
		else
			powerFrame.fontHolder.animGroup:Stop()
		end
	elseif RC32className == "Priest" then
		if not RC32_IS_CATA_OR_LATER or not RC32_POWER_SHADOW_ORBS then
			frame.backDrop:Hide()
			frame.text:Hide()
			return
		end
		powerType = RC32_POWER_SHADOW_ORBS
		local numHolyPower = RC32_UnitPower("player",powerType)
		if numHolyPower > 0 then
			if not frame.backDrop:IsVisible() then
				frame.backDrop:Show()
				frame.text:Show()
			end
		else
			if frame.backDrop:IsVisible() then
				frame.backDrop:Hide()
				frame.text:Hide()
			end
		end
		frame.text:SetText(numHolyPower)
		if numHolyPower > 1 then
			powerFrame.text:SetPoint("CENTER",1,0)
		end
		if numHolyPower >=3 then
			powerFrame.fontHolder.animGroup:Play()
		else
			powerFrame.fontHolder.animGroup:Stop()
		end
	elseif RC32className == "Rogue" or RC32className == "Druid" then
		local comboPoints = RC32_ComboPoints()
		if comboPoints > 0 then
			if not frame.backDrop:IsVisible() then
				frame.backDrop:Show()
				frame.text:Show()
			end
		else
			if frame.backDrop:IsVisible() then
				frame.backDrop:Hide()
				frame.text:Hide()
			end
		end
		frame.text:SetText(comboPoints)
		if comboPoints > 1 then
			powerFrame.text:SetPoint("CENTER",1,0)
		end
		if comboPoints >=5 then
			powerFrame.fontHolder.animGroup:Play()
		else
			powerFrame.fontHolder.animGroup:Stop()
		end
	elseif RC32className == "Mage" then
		--turns out there is no way to track the ice shards for Mage.  Stubbed for now.
	end

end

-- Segmented Power Tracker using curved arc segments
segmentedPowerTracker = nil  -- Global so XML can access it
local function CreateSegmentedPowerTracker(parentOrb, numSegments, orbSize)
	-- Create container frame, same size as the ring overlay
	local trackerSize = orbSize + 40
	local tracker = CreateFrame("Frame", "RC32SegmentedPowerTracker", parentOrb)
	tracker:SetSize(trackerSize, trackerSize)
	tracker:SetPoint("CENTER", parentOrb, "CENTER", 0, 0)
	tracker:SetFrameLevel(parentOrb:GetFrameLevel() + 1)
	
	tracker.segments = {}
	tracker.backdropSegments = {}
	tracker.numSegments = numSegments
	tracker.baseRotation = 0
	
	-- Get colors with fallback defaults
	local r, g, b = 1, 1, 1
	if RC32CharacterData and RC32CharacterData.healthOrb and RC32CharacterData.healthOrb.orbColor then
		r = RC32CharacterData.healthOrb.orbColor.r or 1
		g = RC32CharacterData.healthOrb.orbColor.g or 1
		b = RC32CharacterData.healthOrb.orbColor.b or 1
	end
	
	-- We have 4 ember segment textures, each covering ~22.5 degrees
	-- For classes with 3, 4, or 5 segments, we map them appropriately
	-- Texture 1 = leftmost (10 o'clock area), Texture 4 = rightmost (2 o'clock area)
	
	-- Create backdrop segments (grey, always visible)
	for i = 1, numSegments do
		local backdrop = tracker:CreateTexture(nil, "BACKGROUND")
		backdrop:SetSize(trackerSize, trackerSize)
		backdrop:SetPoint("CENTER", tracker, "CENTER", 0, 0)
		-- Use modulo to cycle through available textures if more than 4 segments
		local texIndex = ((i - 1) % 4) + 1
		backdrop:SetTexture("Interface\\AddOns\\RCDiabloOrbs\\images\\ember_segment_"..texIndex..".tga")
		backdrop:SetVertexColor(0.3, 0.3, 0.3, 0.6)  -- Grey, semi-transparent
		backdrop:Show()  -- Always visible
		tracker.backdropSegments[i] = backdrop
	end
	
	-- Create arc-shaped segments
	for i = 1, numSegments do
		local segment = tracker:CreateTexture(nil, "ARTWORK")
		segment:SetSize(trackerSize, trackerSize)
		segment:SetPoint("CENTER", tracker, "CENTER", 0, 0)
		-- Use modulo to cycle through available textures if more than 4 segments
		local texIndex = ((i - 1) % 4) + 1
		segment:SetTexture("Interface\\AddOns\\RCDiabloOrbs\\images\\ember_segment_"..texIndex..".tga")
		-- Use the health orb's class color
		segment:SetVertexColor(r, g, b, 1)
		segment:Hide()  -- Start hidden
		tracker.segments[i] = segment
	end
	
	-- Track previous power for sound trigger
	tracker.previousPower = 0
	
	-- Update function - Fill segments based on power
	tracker.UpdateSegments = function(self, currentPower)
		for i = 1, self.numSegments do
			if i <= currentPower then
				self.segments[i]:Show()
			else
				self.segments[i]:Hide()
			end
		end
		
		-- Play sound when reaching max stacks (and wasn't already at max)
		if currentPower >= self.numSegments and self.previousPower < self.numSegments then
			local soundIndex = RC32CharacterData.powerFrame.maxStackSound or 1
			local soundId = RC32_MaxStackSounds[soundIndex] and RC32_MaxStackSounds[soundIndex].id or 0
			if soundId > 0 then
				PlaySound(soundId, "Master")
			end
		end
		self.previousPower = currentPower
	end
	
	-- Update colors function (accepts optional r,g,b or uses class color)
	tracker.UpdateColors = function(self, r, g, b)
		local cr, cg, cb = r, g, b
		if not r then
			-- Use class color
			local currentClassNumber = getClassColor()
			local classColor = orbClassColors[currentClassNumber].health
			cr = classColor.r or 1
			cg = classColor.g or 1
			cb = classColor.b or 1
		end
		for i = 1, self.numSegments do
			self.segments[i]:SetVertexColor(cr, cg, cb, 1)
		end
	end
	
	-- Set rotation (in degrees, clockwise) - rotates entire tracker around the orb
	-- This rotates each texture by the same amount, causing the whole arc to spin around
	tracker.SetRotation = function(self, degrees)
		self.baseRotation = degrees
		-- WoW's SetRotation uses radians, positive = counter-clockwise
		-- So we negate to make positive degrees = clockwise
		local radians = -math.rad(degrees)
		for i = 1, self.numSegments do
			self.segments[i]:SetRotation(radians)
			self.backdropSegments[i]:SetRotation(radians)
		end
	end
	
	tracker:Show()
	return tracker
end

-- Segmented power tracker monitor function
-- Class power as a whole number of segments. If the game hides it (Retail /
-- WoW Forever in combat), work it out from the readable percentage instead.
local function RC32_SegmentsFrom(value, powerType)
	if not RC32_Secret(value) then
		return tonumber(value) or 0
	end
	local segs = segmentedPowerTracker and segmentedPowerTracker.numSegments or 5
	local curve = CurveConstants and CurveConstants.ScaleTo100
	local pct = RC32_Percent(UnitPowerPercent, "player", powerType, curve)
	if not pct then return 0 end
	if not curve then pct = pct * 100 end
	return math.floor(pct / 100 * segs + 0.5)
end

function RC32MonitorSegmentedPowers(frame)
	if not RC32CharacterData.powerFrame or not RC32CharacterData.powerFrame.show then
		return
	end
	
	local powerType
	local numPower = 0
	
	if RC32className == "Warlock" then
		if RC32_IS_MOP then
			-- Each MoP Warlock spec has its own secondary resource. Detect by spec
			-- (reliable) with a max-power probe as fallback. NOTE: Demonic Fury is
			-- power type 15, not 11 -- the old probe used 11, which is why
			-- Affliction (Soul Shards) never resolved correctly.
			local spec = GetSpecialization and GetSpecialization()
			if spec == 1 then
				powerType = RC32_POWER_SOUL_SHARDS      -- Affliction
			elseif spec == 2 then
				powerType = RC32_POWER_DEMONIC_FURY     -- Demonology
			elseif spec == 3 then
				powerType = RC32_POWER_BURNING_EMBERS   -- Destruction
			elseif RC32_UnitPowerMax("player", RC32_POWER_BURNING_EMBERS) > 0 then
				powerType = RC32_POWER_BURNING_EMBERS
			elseif RC32_UnitPowerMax("player", RC32_POWER_DEMONIC_FURY) > 0 then
				powerType = RC32_POWER_DEMONIC_FURY
			else
				powerType = RC32_POWER_SOUL_SHARDS
			end
			numPower = RC32_UnitPower("player", powerType)
			-- Soul Shards are already 0-4. Burning Embers and Demonic Fury are
			-- stored on larger scales, so convert them to a 0..numSegments fill.
			if powerType == RC32_POWER_BURNING_EMBERS or powerType == RC32_POWER_DEMONIC_FURY then
				local maxPower = RC32_UnitPowerMax("player", powerType)
				local segs = segmentedPowerTracker.numSegments or 4
				if maxPower and maxPower > 0 then
					numPower = math.floor((numPower / maxPower) * segs + 0.5)
				end
			end
		elseif RC32_IS_CATA_OR_LATER then
			-- Cata, and Retail where every spec uses Soul Shards
			powerType = RC32_POWER_SOUL_SHARDS
			numPower = RC32_UnitPower("player", powerType)
		end
	elseif RC32className == "Paladin" then
		if RC32_IS_CATA_OR_LATER and RC32_POWER_HOLY_POWER then
			powerType = RC32_POWER_HOLY_POWER
			numPower = RC32_UnitPower("player", powerType)
		end
	elseif RC32className == "Monk" then
		if RC32_IS_MOP_OR_LATER and RC32_POWER_CHI then
			powerType = RC32_POWER_CHI
			numPower = RC32_UnitPower("player", powerType)
		end
	elseif RC32className == "Rogue" or RC32className == "Druid" then
		numPower = RC32_ComboPoints()
		segmentedPowerTracker:UpdateSegments(numPower)
		return
	elseif RC32className == "Priest" then
		if RC32_IS_CATA_OR_LATER then
			powerType = RC32_GetShadowOrbPower()
			numPower = RC32_UnitPower("player", powerType)
		end
	elseif RC32className == "Shaman" then
		if RC32_IS_MOP_OR_LATER then
			powerType = 11  -- Maelstrom
			numPower = RC32_UnitPower("player", powerType)
		end
	end
	
	segmentedPowerTracker:UpdateSegments(RC32_SegmentsFrom(numPower, powerType))
end

local function createPowerFrame(file,orb,name,offsetX,offsetY,height,width)
	local powerFrame = CreateFrame("Frame","RC32"..name,orb)
	powerFrame:SetFrameStrata("BACKGROUND")
	powerFrame:SetPoint("CENTER",offsetX,offsetY)
	powerFrame:SetHeight(height)
	powerFrame:SetWidth(width)
	
	--gradient backdrop
	powerFrame.backDrop = CreateFrame("Frame","RC32"..name.."Backdrop",powerFrame)
	powerFrame.backDrop:SetAllPoints(true)
	powerFrame.backDrop.backTexture = powerFrame.backDrop:CreateTexture(nil,"BACKGROUND")
	powerFrame.backDrop.backTexture:SetTexture(images.."d32_powerFrame_backdrop.tga")
	powerFrame.backDrop.backTexture:SetAllPoints(powerFrame)
	
	--shadowed frame, colorizable
	powerFrame.texture = powerFrame.backDrop:CreateTexture(nil,"OVERLAY")
	powerFrame.texture:SetTexture(file)
	local orbColor = RC32CharacterData and RC32CharacterData.healthOrb and RC32CharacterData.healthOrb.orbColor
	if orbColor then
		powerFrame.texture:SetVertexColor(orbColor.r or 1, orbColor.g or 1, orbColor.b or 1, orbColor.a or 1)
	else
		powerFrame.texture:SetVertexColor(1, 1, 1, 1)
	end
	powerFrame.texture:SetAllPoints(true)
	
	--fontholder frame for animations
	powerFrame.fontHolder = CreateFrame("Frame",nil,powerFrame)
	powerFrame.fontHolder:SetFrameStrata("LOW")
	powerFrame.fontHolder:SetAllPoints(true)
	
	--text
	powerFrame.text = powerFrame.fontHolder:CreateFontString(nil,"OVERLAY")
	local fontPath = (RC32CharacterData and RC32CharacterData.font) or "Fonts\\FRIZQT__.TTF"
	powerFrame.text:SetFont(fontPath,29,"THINOUTLINE")
	powerFrame.text:SetPoint("CENTER",0,1)
	if orbColor then
		powerFrame.text:SetTextColor(orbColor.r or 1, orbColor.g or 1, orbColor.b or 1, orbColor.a or 1)
	else
		powerFrame.text:SetTextColor(1, 1, 1, 1)
	end
	powerFrame.text:SetText("1")
	
	local animGroup = powerFrame.fontHolder:CreateAnimationGroup()
	powerFrame.fontHolder.animGroup = animGroup
	
	local anim1 = powerFrame.fontHolder.animGroup:CreateAnimation("Alpha")
	anim1:SetFromAlpha(1)
	anim1:SetToAlpha(0)
	anim1:SetOrder(1)
	anim1:SetDuration(.7)
	powerFrame.fontHolder.anim1 = anim1
	
	local anim2 = powerFrame.fontHolder.animGroup:CreateAnimation("Alpha")
	anim2:SetFromAlpha(0)
	anim2:SetToAlpha(1)
	anim2:SetOrder(2)
	anim2:SetDuration(.7)
	powerFrame.fontHolder.anim2 = anim2
	
	animGroup:SetLooping("REPEAT")
	
	
	--updates and wh
	powerFrame:SetScript("OnUpdate",RC32MonitorPowers)
	powerFrame:Show()
	
	return powerFrame
end


function checkPetFontPlacement()
	if RC32CharacterData.petOrb.showValue and RC32CharacterData.petOrb.showPercentage then
		petOrb.font3:SetPoint("CENTER",-20,-8)
		petOrb.font4:SetPoint("CENTER",20,-8)
		petOrb.font1:SetPoint("CENTER",-20,5)
		petOrb.font2:SetPoint("CENTER",20,5)
		petOrb.font3:SetFont(RC32CharacterData.font,9,"THINOUTLINE")
		petOrb.font4:SetFont(RC32CharacterData.font,9,"THINOUTLINE")
	elseif RC32CharacterData.petOrb.showValue and not RC32CharacterData.petOrb.showPercentage then
		petOrb.font3:SetPoint("CENTER",-20,0)
		petOrb.font4:SetPoint("CENTER",20,0)
		petOrb.font3:SetFont(RC32CharacterData.font,11 * petOrb:GetScale(),"THINOUTLINE")
		petOrb.font4:SetFont(RC32CharacterData.font,11 * petOrb:GetScale(),"THINOUTLINE")
	elseif not RC32CharacterData.petOrb.showValue and RC32CharacterData.petOrb.showPercentage then
		petOrb.font1:SetPoint("CENTER",-20,0)
		petOrb.font2:SetPoint("CENTER",20,0)
	end
end

function setOrbFontPlacement(orb,orbData)
	orb.font1:Show()
	orb.font2:Show()
	if orbData.font1.show and orbData.font2.show then
		orb.font1:SetFont(RC32CharacterData.font,28,"THINOUTLINE")
		orb.font2:SetFont(RC32CharacterData.font,16,"THINOUTLINE")
		orb.font1:SetPoint("CENTER",0,15)
		orb.font2:SetPoint("CENTER",0,-5)
	elseif orbData.font1.show and not orbData.font2.show then
		orb.font1:SetFont(RC32CharacterData.font,28,"THINOUTLINE")
		orb.font1:SetPoint("CENTER",0,0)
		orb.font2:Hide()
	elseif orbData.font2.show and not orbData.font1.show then
		orb.font2:SetFont(RC32CharacterData.font,25,"THINOUTLINE")
		orb.font2:SetPoint("CENTER",0,0)
		orb.font1:Hide()
	else
		orb.font1:Hide()
		orb.font2:Hide()
	end
end

function checkXMLOrbFontPlacement()
	xmlOrbDisplayFrame2.orb.font1:Show()
	xmlOrbDisplayFrame2.orb.font2:Show()
	if RC32OrbPercentageCheckBox:GetChecked() and RC32OrbValueCheckBox:GetChecked() then
		xmlOrbDisplayFrame2.orb.font1:SetFont(RC32CharacterData.font,28,"THINOUTLINE")
		xmlOrbDisplayFrame2.orb.font2:SetFont(RC32CharacterData.font,16,"THINOUTLINE")
		xmlOrbDisplayFrame2.orb.font1:SetPoint("CENTER",0,15)
		xmlOrbDisplayFrame2.orb.font2:SetPoint("CENTER",0,-5)
	elseif RC32OrbPercentageCheckBox:GetChecked() and not RC32OrbValueCheckBox:GetChecked() then
		xmlOrbDisplayFrame2.orb.font1:SetFont(RC32CharacterData.font,32,"THINOUTLINE")
		xmlOrbDisplayFrame2.orb.font1:SetPoint("CENTER",0,0)
		xmlOrbDisplayFrame2.orb.font2:Hide()
	elseif RC32OrbValueCheckBox:GetChecked() and not RC32OrbPercentageCheckBox:GetChecked() then
		xmlOrbDisplayFrame2.orb.font2:SetFont(RC32CharacterData.font,32,"THINOUTLINE")
		xmlOrbDisplayFrame2.orb.font2:SetPoint("CENTER",0,0)
		xmlOrbDisplayFrame2.orb.font1:Hide()
	else
		xmlOrbDisplayFrame2.orb.font1:Hide()
		xmlOrbDisplayFrame2.orb.font2:Hide()
	end
end

function resetXMLTextBoxes()
	RC32OrbPercentageCheckBox:SetChecked(CommitButton.orbData.font1.show)
	RC32OrbValueCheckBox:SetChecked(CommitButton.orbData.font2.show)
end

local function checkDefaultsFromMemory()
	if not RC32CharacterData.healthOrb then RC32CharacterData.healthOrb = defaultsTable.healthOrb end
	if not RC32CharacterData.healthOrb.textures then RC32CharacterData.healthOrb.textures = defaultTextures.healthOrb end
	if not RC32CharacterData.healthOrb.textures.fill then RC32CharacterData.healthOrb.textures.fill = defaultTextures.healthOrb.fill end
	if not RC32CharacterData.healthOrb.textures.rotation then RC32CharacterData.healthOrb.textures.rotation = defaultTextures.healthOrb.rotation end
	if RC32CharacterData.healthOrb.font1.show == nil then RC32CharacterData.healthOrb.font1.show = defaultsTable.healthOrb.font1.show end
	if RC32CharacterData.healthOrb.font2.show == nil then RC32CharacterData.healthOrb.font2.show = defaultsTable.healthOrb.font2.show end
	if RC32CharacterData.healthOrb.show == nil then RC32CharacterData.healthOrb.show = defaultsTable.healthOrb.show end
	if not RC32CharacterData.healthOrb.formatting then RC32CharacterData.healthOrb.formatting = defaultsTable.healthOrb.formatting end
	if not RC32CharacterData.manaOrb then RC32CharacterData.manaOrb = defaultsTable.manaOrb end
	if not RC32CharacterData.manaOrb.textures then RC32CharacterData.manaOrb.textures = defaultTextures.manaOrb end
	if not RC32CharacterData.manaOrb.textures.fill then RC32CharacterData.manaOrb.textures.fill = defaultTextures.manaOrb.fill end
	if not RC32CharacterData.manaOrb.textures.rotation then RC32CharacterData.manaOrb.textures.rotation = defaultTextures.manaOrb.rotation end
	if RC32CharacterData.manaOrb.font1.show == nil then RC32CharacterData.manaOrb.font1.show = defaultsTable.manaOrb.font1.show end
	if RC32CharacterData.manaOrb.font2.show == nil then RC32CharacterData.manaOrb.font2.show = defaultsTable.manaOrb.font2.show end
	if RC32CharacterData.manaOrb.show == nil then RC32CharacterData.manaOrb.show = defaultsTable.manaOrb.show end
	if not RC32CharacterData.manaOrb.formatting then RC32CharacterData.manaOrb.formatting = defaultsTable.manaOrb.formatting end
	if not RC32CharacterData.druidColors then RC32CharacterData.druidColors = defaultsTable.druidColors end
	if not RC32CharacterData.combat then RC32CharacterData.combat = defaultsTable.combat end
	if not RC32CharacterData.combat.galaxy then RC32CharacterData.combat.galaxy = defaultsTable.combat.galaxy end
	if not RC32CharacterData.values then RC32CharacterData.values = defaultsTable.values  end
	if not RC32CharacterData.artwork then RC32CharacterData.artwork = defaultsTable.artwork end
	if not RC32CharacterData.font then RC32CharacterData.font = defaultsTable.font end
	if not RC32CharacterData.petOrb then RC32CharacterData.petOrb = defaultsTable.petOrb end
	if not RC32CharacterData.petOrb.scale then RC32CharacterData.petOrb.scale = defaultsTable.petOrb.scale end
	if RC32CharacterData.petWarningEnabled == nil then
		-- Auto-enable for classes that always have a permanent pet
		local cls = RC32className
		if cls == "Hunter" or cls == "Warlock" then
			RC32CharacterData.petWarningEnabled = true
		else
			RC32CharacterData.petWarningEnabled = false
		end
	end
	-- One-time migration: reset DK pet warning to off (was auto-true in older versions)
	if not RC32CharacterData.petWarningMigrated then
		RC32CharacterData.petWarningMigrated = true
		local cls = RC32className
		if cls == "Deathknight" or cls == "Death Knight" or cls == "DEATHKNIGHT" then
			RC32CharacterData.petWarningEnabled = false
		end
	end
	if RC32CharacterData.dotTrackerEnabled == nil then RC32CharacterData.dotTrackerEnabled = true end
	if not RC32CharacterData.powerFrame then RC32CharacterData.powerFrame = defaultsTable.powerFrame end
	if RC32CharacterData.powerFrame.maxStackSound == nil then RC32CharacterData.powerFrame.maxStackSound = defaultsTable.powerFrame.maxStackSound end
	if not RC32CharacterData.defaultPlayerFrame then RC32CharacterData.defaultPlayerFrame = defaultsTable.defaultPlayerFrame end
	if not RC32CharacterData.diseaseTracker then RC32CharacterData.diseaseTracker = { scale = 1.0 } end
	if not RC32CharacterData.dotTracker then RC32CharacterData.dotTracker = { scale = 1.0 } end
	-- Migrate old diseaseTracker positions to dotTracker
	if RC32CharacterData.diseaseTracker then
		local dt = RC32CharacterData.diseaseTracker
		if dt.diseaseFF and not RC32CharacterData.dotTracker.dot_FrostFever then
			RC32CharacterData.dotTracker.dot_FrostFever = dt.diseaseFF
		end
		if dt.diseaseBP and not RC32CharacterData.dotTracker.dot_BloodPlague then
			RC32CharacterData.dotTracker.dot_BloodPlague = dt.diseaseBP
		end
		if dt.scale and RC32CharacterData.dotTracker.scale == 1.0 then
			RC32CharacterData.dotTracker.scale = dt.scale
		end
	end
	
	-- Validate/repair color tables (fix any missing r, g, b, a components)
	local function validateColorTable(colorTable, defaultColor)
		if not colorTable then return defaultColor end
		colorTable.r = colorTable.r or (defaultColor and defaultColor.r) or 1
		colorTable.g = colorTable.g or (defaultColor and defaultColor.g) or 1
		colorTable.b = colorTable.b or (defaultColor and defaultColor.b) or 1
		colorTable.a = colorTable.a or (defaultColor and defaultColor.a) or 1
		return colorTable
	end
	
	-- Repair health orb colors
	RC32CharacterData.healthOrb.orbColor = validateColorTable(RC32CharacterData.healthOrb.orbColor, defaultsTable.healthOrb.orbColor)
	RC32CharacterData.healthOrb.galaxy = validateColorTable(RC32CharacterData.healthOrb.galaxy, defaultsTable.healthOrb.galaxy)
	RC32CharacterData.healthOrb.font1 = validateColorTable(RC32CharacterData.healthOrb.font1, defaultsTable.healthOrb.font1)
	RC32CharacterData.healthOrb.font2 = validateColorTable(RC32CharacterData.healthOrb.font2, defaultsTable.healthOrb.font2)
	
	-- Repair mana orb colors
	RC32CharacterData.manaOrb.orbColor = validateColorTable(RC32CharacterData.manaOrb.orbColor, defaultsTable.manaOrb.orbColor)
	RC32CharacterData.manaOrb.galaxy = validateColorTable(RC32CharacterData.manaOrb.galaxy, defaultsTable.manaOrb.galaxy)
	RC32CharacterData.manaOrb.font1 = validateColorTable(RC32CharacterData.manaOrb.font1, defaultsTable.manaOrb.font1)
	RC32CharacterData.manaOrb.font2 = validateColorTable(RC32CharacterData.manaOrb.font2, defaultsTable.manaOrb.font2)
	
	-- Repair combat colors
	if RC32CharacterData.combat then
		RC32CharacterData.combat.orbColor = validateColorTable(RC32CharacterData.combat.orbColor, defaultsTable.combat.orbColor)
		RC32CharacterData.combat.galaxy = validateColorTable(RC32CharacterData.combat.galaxy, defaultsTable.combat.galaxy)
		RC32CharacterData.combat.font1 = validateColorTable(RC32CharacterData.combat.font1, defaultsTable.combat.font1)
		RC32CharacterData.combat.font2 = validateColorTable(RC32CharacterData.combat.font2, defaultsTable.combat.font2)
	end
	
	-- Initialize account-wide data for power tracker rotation
	if not RC32AccountData then RC32AccountData = {} end
	if RC32AccountData.powerTrackerRotation == nil then RC32AccountData.powerTrackerRotation = 270 end
	if RC32AccountData.powerTrackerScale == nil then RC32AccountData.powerTrackerScale = 100 end
	
	
	if TruncatedValuesCheckButton then TruncatedValuesCheckButton:SetChecked(RC32CharacterData.values.formatted) end
	if ShowArtworkCheckButton then ShowArtworkCheckButton:SetChecked(RC32CharacterData.artwork.show) end
	if ShowHealthOrbCheckButton then ShowHealthOrbCheckButton:SetChecked(RC32CharacterData.healthOrb.show) end
	if ShowManaOrbCheckButton then ShowManaOrbCheckButton:SetChecked(RC32CharacterData.manaOrb.show) end
	if UsePetOrbCheckButton then UsePetOrbCheckButton:SetChecked(RC32CharacterData.petOrb.enabled) end
	if TrackCombatCheckButton then TrackCombatCheckButton:SetChecked(RC32CharacterData.combat.enabled) end
	if ShowPetOrbPercentagesCheckButton then ShowPetOrbPercentagesCheckButton:SetChecked(RC32CharacterData.petOrb.showPercentage) end
	if ShowPetOrbValuesCheckButton then ShowPetOrbValuesCheckButton:SetChecked(RC32CharacterData.petOrb.showValue) end
	if UsePowerTrackerCheckButton then UsePowerTrackerCheckButton:SetChecked(RC32CharacterData.powerFrame.show) end
	if ShowBlizzPlayerFrameCheckButton then ShowBlizzPlayerFrameCheckButton:SetChecked(RC32CharacterData.defaultPlayerFrame.show) end
	if ShowPetWarningCheckButton then ShowPetWarningCheckButton:SetChecked(RC32CharacterData.petWarningEnabled ~= false) end
	if ShowDotTrackerCheckButton then ShowDotTrackerCheckButton:SetChecked(RC32CharacterData.dotTrackerEnabled ~= false) end
		
	if not RC32CharacterData.petOrb.showValue then
		petOrb.font3:Hide()
		petOrb.font4:Hide()
	end
	if not RC32CharacterData.petOrb.showPercentage then
		petOrb.font1:Hide()
		petOrb.font2:Hide()
	end
	checkPetFontPlacement()
	
	if not RC32CharacterData.petOrb.enabled then
	 UnregisterUnitWatch(petOrb) 
	 petOrb:Hide()
	end
	if not RC32CharacterData.artwork.show then
		angelFrame:Hide()
		demonFrame:Hide()
	end
	
	-- Handle health orb visibility
	if not RC32CharacterData.healthOrb.show then
		healthOrb:SetScript("OnUpdate", nil)
		healthOrb:Hide()
		demonFrame:Hide()
		if segmentedPowerTracker then
			segmentedPowerTracker:SetScript("OnUpdate", nil)
			segmentedPowerTracker:Hide()
		end
	end
	
	-- Handle mana orb visibility
	if not RC32CharacterData.manaOrb.show then
		manaOrb:SetScript("OnUpdate", nil)
		manaOrb:Hide()
		angelFrame:Hide()
	end
	
	-- Handle segmented power tracker visibility
	if segmentedPowerTracker then
		if not RC32CharacterData.powerFrame.show then
			segmentedPowerTracker:SetScript("OnUpdate", nil)
			segmentedPowerTracker:Hide()
		else
			segmentedPowerTracker:SetScript("OnUpdate", RC32MonitorSegmentedPowers)
			segmentedPowerTracker:Show()
		end
	end
	
	-- Legacy powerFrame handling (if still exists)
	if powerFrame then
		if not RC32CharacterData.powerFrame.show then
			powerFrame:SetScript("OnUpdate",nil)
			powerFrame:Hide()
		end
	end
end

-- Helper function to safely get color values with fallbacks
local function safeColor(colorTable, defaultR, defaultG, defaultB, defaultA)
	if not colorTable then return defaultR or 1, defaultG or 1, defaultB or 1, defaultA or 1 end
	return colorTable.r or defaultR or 1, colorTable.g or defaultG or 1, colorTable.b or defaultB or 1, colorTable.a or defaultA or 1
end

-- Functions to toggle health and mana orb visibility
function RC32_ToggleHealthOrb(show)
	RC32CharacterData.healthOrb.show = show
	if show then
		healthOrb:SetScript("OnUpdate", monitorHealth)
		healthOrb:Show()
		-- Show demon artwork if artwork is enabled
		if RC32CharacterData.artwork.show then
			demonFrame:Show()
		end
		-- Show power tracker if enabled
		if segmentedPowerTracker and RC32CharacterData.powerFrame.show then
			segmentedPowerTracker:SetScript("OnUpdate", RC32MonitorSegmentedPowers)
			segmentedPowerTracker:Show()
		end
	else
		healthOrb:SetScript("OnUpdate", nil)
		healthOrb:Hide()
		demonFrame:Hide()
		-- Hide power tracker when health orb is hidden
		if segmentedPowerTracker then
			segmentedPowerTracker:SetScript("OnUpdate", nil)
			segmentedPowerTracker:Hide()
		end
	end
end

function RC32_ToggleManaOrb(show)
	RC32CharacterData.manaOrb.show = show
	if show then
		manaOrb:SetScript("OnUpdate", monitorPower)
		manaOrb:Show()
		-- Show angel artwork if artwork is enabled
		if RC32CharacterData.artwork.show then
			angelFrame:Show()
		end
	else
		manaOrb:SetScript("OnUpdate", nil)
		manaOrb:Hide()
		angelFrame:Hide()
	end
end

local function updateColorsFromMemory()
	--health orb fill, galaxy and font colors - USE SAVED COLORS
	local r,g,b,a = safeColor(RC32CharacterData.healthOrb.orbColor)
	healthOrb.filling:SetVertexColor(r,g,b,1)
	r,g,b,a = safeColor(RC32CharacterData.healthOrb.galaxy)
	healthOrb.galaxy1.texture:SetVertexColor(r,g,b,1)
	healthOrb.galaxy2.texture:SetVertexColor(r,g,b,1)
	healthOrb.galaxy3.texture:SetVertexColor(r,g,b,1)
	r,g,b,a = safeColor(RC32CharacterData.healthOrb.font1)
	healthOrb.font1:SetTextColor(r,g,b,a)
	r,g,b,a = safeColor(RC32CharacterData.healthOrb.font2)
	healthOrb.font2:SetTextColor(r,g,b,a)
	safeSetScale(healthOrb, RC32CharacterData.healthOrb.scale or 1)

	--mana orb fill, galaxy and font colors
	r,g,b,a = safeColor(RC32CharacterData.manaOrb.orbColor)
	manaOrb.filling:SetVertexColor(r,g,b,1)
	r,g,b,a = safeColor(RC32CharacterData.manaOrb.galaxy)
	manaOrb.galaxy1.texture:SetVertexColor(r,g,b,1)
	manaOrb.galaxy2.texture:SetVertexColor(r,g,b,1)
	manaOrb.galaxy3.texture:SetVertexColor(r,g,b,1)
	r,g,b,a = safeColor(RC32CharacterData.manaOrb.font1)
	manaOrb.font1:SetTextColor(r,g,b,a)
	r,g,b,a = safeColor(RC32CharacterData.manaOrb.font2)
	manaOrb.font2:SetTextColor(r,g,b,a)
	safeSetScale(manaOrb, RC32CharacterData.manaOrb.scale or 1)
	
	local pr, pg, pb, pa = healthOrb.filling:GetVertexColor()
	petOrb.filling1:SetVertexColor(pr or 1, pg or 1, pb or 1, 1)
	pr, pg, pb, pa = manaOrb.filling:GetVertexColor()
	petOrb.filling2:SetVertexColor(pr or 1, pg or 1, pb or 1, 1)
	petOrb.font1:SetTextColor(healthOrb.font1:GetTextColor())
	petOrb.font2:SetTextColor(manaOrb.font1:GetTextColor())
	petOrb.font3:SetTextColor(healthOrb.font2:GetTextColor())
	petOrb.font4:SetTextColor(manaOrb.font2:GetTextColor())
	safeSetScale(petOrb, RC32CharacterData.petOrb.scale)
	
	-- Update power tracker to class color and apply saved settings
	if segmentedPowerTracker then
		segmentedPowerTracker:UpdateColors()
		-- Apply saved rotation from account-wide data
		local savedRotation = RC32AccountData and RC32AccountData.powerTrackerRotation or 270
		segmentedPowerTracker:SetRotation(savedRotation)
		-- Apply saved scale from account-wide data
		local savedScale = RC32AccountData and RC32AccountData.powerTrackerScale or 75
		safeSetScale(segmentedPowerTracker, savedScale / 100)
	end
	
	-- Initialize scale sliders with saved values (inverted for vertical sliders)
	if RC32HealthScaleSlider then
		RC32HealthScaleSlider:SetValue(225 - (RC32CharacterData.healthOrb.scale) * 100)
		if RC32HealthScaleValue then
			RC32HealthScaleValue:SetText(math.floor((RC32CharacterData.healthOrb.scale) * 100) .. "%")
		end
	end
	if RC32ManaScaleSlider then
		RC32ManaScaleSlider:SetValue(225 - (RC32CharacterData.manaOrb.scale) * 100)
		if RC32ManaScaleValue then
			RC32ManaScaleValue:SetText(math.floor((RC32CharacterData.manaOrb.scale) * 100) .. "%")
		end
	end
	if RC32PetScaleSlider then
		RC32PetScaleSlider:SetValue(225 - (RC32CharacterData.petOrb.scale) * 100)
		if RC32PetScaleValue then
			RC32PetScaleValue:SetText(math.floor((RC32CharacterData.petOrb.scale) * 100) .. "%")
		end
	end
	-- Initialize power tracker rotation slider (convert from actual rotation to slider value)
	if RC32PowerTrackerRotationSlider then
		local savedRotation = RC32AccountData and RC32AccountData.powerTrackerRotation or 270
		-- Convert rotation back to slider value: slider = rotation - 270 (wrapped)
		local sliderVal = savedRotation - 270
		if sliderVal < 0 then sliderVal = sliderVal + 360 end
		RC32PowerTrackerRotationSlider:SetValue(sliderVal)
		if RC32RotateValue then
			RC32RotateValue:SetText(sliderVal .. "°")
		end
	end
	-- Initialize power tracker scale slider
	if RC32PowerTrackerScaleSlider then
		local savedScale = RC32AccountData and RC32AccountData.powerTrackerScale or 100
		RC32PowerTrackerScaleSlider:SetValue(225 - savedScale)
		if RC32PowerTrackerScaleValue then
			RC32PowerTrackerScaleValue:SetText(savedScale .. "%")
		end
	end

	setOrbFontPlacement(healthOrb,RC32CharacterData.healthOrb)
	setOrbFontPlacement(manaOrb,RC32CharacterData.manaOrb)
end

function RC32UpdateOrbColor(orb,orbColor,galaxyColor,font1Color,font2Color)
	local r, g, b, a = safeColor(orbColor)
	orb.filling:SetVertexColor(r, g, b, 1) -- Always full alpha on filling
	r, g, b, a = safeColor(galaxyColor)
	orb.galaxy1.texture:SetVertexColor(r, g, b, 1) -- Always full alpha on galaxy
	orb.galaxy2.texture:SetVertexColor(r, g, b, 1)
	orb.galaxy3.texture:SetVertexColor(r, g, b, 1)
	r, g, b, a = safeColor(font1Color)
	orb.font1:SetTextColor(r, g, b, a)
	r, g, b, a = safeColor(font2Color)
	orb.font2:SetTextColor(r, g, b, a)
end 

local function TryNewColors(restore)
	local r, g, b, a
	
	if restore then
		r, g, b, a = unpack(restore)
	else
		r, g, b = ColorPickerFrame:GetColorRGB()
		-- Handle opacity - newer API uses GetColorAlpha() which returns actual alpha (not inverted)
		if ColorPickerFrame.GetColorAlpha then
			a = ColorPickerFrame:GetColorAlpha()
		elseif OpacitySliderFrame and OpacitySliderFrame:IsShown() then
			a = 1 - OpacitySliderFrame:GetValue() -- Invert because old slider is inverted
		else
			a = ColorPickerFrame.currentAlpha or 1
		end
	end
	
	-- Ensure we have valid values
	r = r or 1
	g = g or 1
	b = b or 1
	a = a or 1

	if ColorPickerFrame.elementToChange == "Filling" then
		xmlOrbDisplayFrame2.orb.filling:SetVertexColor(r,g,b,1)
	elseif ColorPickerFrame.elementToChange == "Swirl" then
		xmlOrbDisplayFrame2.orb.galaxy1.texture:SetVertexColor(r,g,b,1)
		xmlOrbDisplayFrame2.orb.galaxy2.texture:SetVertexColor(r,g,b,1)
		xmlOrbDisplayFrame2.orb.galaxy3.texture:SetVertexColor(r,g,b,1)
	elseif ColorPickerFrame.elementToChange == "Font1" then
		xmlOrbDisplayFrame2.orb.font1:SetTextColor(r,g,b,a)
	elseif ColorPickerFrame.elementToChange == "Font2" then
		xmlOrbDisplayFrame2.orb.font2:SetTextColor(r,g,b,a) 
	end
end

function TryNewTextures(fillTexture,swirlTexture)
	if fillTexture then
		xmlOrbDisplayFrame2.orb.filling:SetTexture(fillTexture)
	end
	if swirlTexture then
		xmlOrbDisplayFrame2.orb.galaxy1.texture:SetTexture(swirlTexture.."1.tga")
		xmlOrbDisplayFrame2.orb.galaxy2.texture:SetTexture(swirlTexture.."2.tga")
		xmlOrbDisplayFrame2.orb.galaxy3.texture:SetTexture(swirlTexture.."3.tga")
	end
end

local function checkShapeShiftInfo()
		local form = GetShapeshiftForm()
		local druidFormTable = RC32CharacterData.manaOrb
		local changeOcurred = true
		if form == 1 then
			druidFormTable = RC32CharacterData.druidColors.bear
			previousPowerValue = RC32_Readable(RC32_UnitPower("player", RC32_POWER_RAGE), 0)
		elseif form == 3 then
			druidFormTable = RC32CharacterData.druidColors.cat
			previousPowerValue = RC32_Readable(RC32_UnitPower("player", RC32_POWER_ENERGY), 0)
		elseif form == 5 then
			changeOcurred = false
		elseif form == 0 then
			druidFormTable = RC32CharacterData.manaOrb
			previousPowerValue = RC32_Readable(RC32_UnitPower("player", RC32_POWER_MANA), 0)
		end
		RC32UpdateOrbColor(manaOrb,druidFormTable.orbColor,druidFormTable.galaxy,druidFormTable.font1,druidFormTable.font2)
end

-- Border Color Functions
function RC32_SetBorderColor(r, g, b)
	-- Try multiple ways to access the border texture
	local border = _G["RC32GUIBorder"]
	if border and border.SetVertexColor then
		border:SetVertexColor(r, g, b)
	end
end

local function UpdateOrbTextures()
	-- Ensure textures exist with fallback defaults
	local healthFill = (RC32CharacterData.healthOrb.textures and RC32CharacterData.healthOrb.textures.fill) or defaultTextures.healthOrb.fill
	local healthRotation = (RC32CharacterData.healthOrb.textures and RC32CharacterData.healthOrb.textures.rotation) or defaultTextures.healthOrb.rotation
	local manaFill = (RC32CharacterData.manaOrb.textures and RC32CharacterData.manaOrb.textures.fill) or defaultTextures.manaOrb.fill
	local manaRotation = (RC32CharacterData.manaOrb.textures and RC32CharacterData.manaOrb.textures.rotation) or defaultTextures.manaOrb.rotation
	
	healthOrb.filling:SetTexture(images..healthFill)
	healthOrb.galaxy1.texture:SetTexture(images..healthRotation.."1.tga")
	healthOrb.galaxy2.texture:SetTexture(images..healthRotation.."2.tga")
	healthOrb.galaxy3.texture:SetTexture(images..healthRotation.."3.tga")
	
	manaOrb.filling:SetTexture(images..manaFill)
	manaOrb.galaxy1.texture:SetTexture(images..manaRotation.."1.tga")
	manaOrb.galaxy2.texture:SetTexture(images..manaRotation.."2.tga")
	manaOrb.galaxy3.texture:SetTexture(images..manaRotation.."3.tga")
end

function shouldEnabledCheckboxBeChecked()
	if CommitButton and RC32OrbEnabledCheckbox then
		RC32OrbEnabledCheckbox:SetChecked(CommitButton.orbData.enabled)
	end
end

function RC32ApplyChanges()
	local activeElement = CommitButton.activeElement
	local r,g,b,a = xmlOrbDisplayFrame2.orb.filling:GetVertexColor()
	local fillColors = {r=0,g=0,b=0,a=0}
	fillColors.r, fillColors.g, fillColors.b, fillColors.a = r,g,b,a
	activeElement.orbColor.r, activeElement.orbColor.g, activeElement.orbColor.b, activeElement.orbColor.a = r,g,b,a

	local galaxyColors = {r=0,g=0,b=0,a=0}
	r,g,b,a = xmlOrbDisplayFrame2.orb.galaxy1.texture:GetVertexColor()
	galaxyColors.r, galaxyColors.g, galaxyColors.b, galaxyColors.a = r,g,b,a
	activeElement.galaxy.r, activeElement.galaxy.g, activeElement.galaxy.b, activeElement.galaxy.a = r,g,b,a
	
	local font1Color = {r=0,g=0,b=0,a=0}
	r,g,b,a = xmlOrbDisplayFrame2.orb.font1:GetTextColor()
	font1Color.r,font1Color.g,font1Color.b,font1Color.a = r,g,b,a
	activeElement.font1.r, activeElement.font1.g, activeElement.font1.b, activeElement.font1.a = r,g,b,a
	
	local font2Color = {r=0,g=0,b=0,a=0}
	r,g,b,a = xmlOrbDisplayFrame2.orb.font2:GetTextColor()
	font2Color.r,font2Color.g,font2Color.b,font2Color.a = r,g,b,a
	activeElement.font2.r, activeElement.font2.g, activeElement.font2.b, activeElement.font2.a = r,g,b,a
	
	-- Update the actual orb being edited with its saved colors
	RC32UpdateOrbColor(CommitButton.orb, activeElement.orbColor, activeElement.galaxy, activeElement.font1, activeElement.font2)
	
	-- Use stored texture indices from dropdown selections
	if RC32SelectedFillIndex ~= nil then
		CommitButton.textureElement.fill = RC32FillTextureNames[RC32SelectedFillIndex]
	end
	if RC32SelectedRotationIndex ~= nil then
		CommitButton.textureElement.rotation = RC32RotationTextureNames[RC32SelectedRotationIndex]
	end
	UpdateOrbTextures()

	if RC32OrbPercentageCheckBox:GetChecked() then
		CommitButton.orbData.font1.show = true
	else
		CommitButton.orbData.font1.show = false
	end

	if RC32OrbValueCheckBox:GetChecked() then
		CommitButton.orbData.font2.show = true
	else
		CommitButton.orbData.font2.show = false
	end

	setOrbFontPlacement(CommitButton.orb,CommitButton.orbData)
	
	--set pet fill colors to that of the fill colors of the health/mana orbs
	local pr, pg, pb, pa = healthOrb.filling:GetVertexColor()
	petOrb.filling1:SetVertexColor(pr or 1, pg or 1, pb or 1, 1)
	pr, pg, pb, pa = manaOrb.filling:GetVertexColor()
	petOrb.filling2:SetVertexColor(pr or 1, pg or 1, pb or 1, 1)
	petOrb.font1:SetTextColor(healthOrb.font1:GetTextColor())
	petOrb.font2:SetTextColor(manaOrb.font1:GetTextColor())
	petOrb.font3:SetTextColor(healthOrb.font2:GetTextColor())
	petOrb.font4:SetTextColor(manaOrb.font2:GetTextColor())
end

function RC32ColorPicker(xmlElement)
	local r,g,b,a
	if xmlElement == "Filling" then
		r,g,b,a = xmlOrbDisplayFrame2.orb.filling:GetVertexColor()
	elseif xmlElement == "Swirl" then
		r,g,b,a = xmlOrbDisplayFrame2.orb.galaxy1.texture:GetVertexColor()
	elseif xmlElement == "Font1" then
		r,g,b,a = xmlOrbDisplayFrame2.orb.font1:GetTextColor()
	elseif xmlElement == "Font2" then
		r,g,b,a = xmlOrbDisplayFrame2.orb.font2:GetTextColor()
	end
	
	-- Store which element we're changing
	ColorPickerFrame.elementToChange = xmlElement
	ColorPickerFrame.previousValues = {r, g, b, a}
	ColorPickerFrame.currentAlpha = a
	
	-- Use the modern ColorPickerFrame API (MoP Remix and later)
	if ColorPickerFrame.SetupColorPickerAndShow then
		local info = {
			swatchFunc = function() TryNewColors() end,
			opacityFunc = function() TryNewColors() end,
			cancelFunc = function() TryNewColors(ColorPickerFrame.previousValues) end,
			r = r,
			g = g,
			b = b,
			opacity = a and (1 - a) or 0, -- Invert for slider (0 = opaque, 1 = transparent)
			hasOpacity = true,
		}
		ColorPickerFrame:SetupColorPickerAndShow(info)
	else
		-- Fallback for older API
		ColorPickerFrame.func = TryNewColors
		ColorPickerFrame.opacityFunc = TryNewColors
		ColorPickerFrame.cancelFunc = function() TryNewColors(ColorPickerFrame.previousValues) end
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame.hasOpacity = true
		ColorPickerFrame.opacity = a and (1 - a) or 0
		ColorPickerFrame:Show()
	end
	
	makeFrameMovable(ColorPickerFrame, "RightButton")
	ColorPickerFrame:EnableKeyboard(false)
end

function RC32ResetToClassColors()
	-- Get the class colors based on which orb is being edited
	local classColor
	local isHealthOrb = (CommitButton.orb == healthOrb)
	
	if isHealthOrb then
		classColor = orbClassColors[charClassNumber].health
	else
		classColor = orbClassColors[charClassNumber].mana
	end
	
	-- Update the preview orb with class colors
	xmlOrbDisplayFrame2.orb.filling:SetVertexColor(classColor.r, classColor.g, classColor.b, classColor.a)
	xmlOrbDisplayFrame2.orb.galaxy1.texture:SetVertexColor(classColor.r, classColor.g, classColor.b, classColor.a)
	xmlOrbDisplayFrame2.orb.galaxy2.texture:SetVertexColor(classColor.r, classColor.g, classColor.b, classColor.a)
	xmlOrbDisplayFrame2.orb.galaxy3.texture:SetVertexColor(classColor.r, classColor.g, classColor.b, classColor.a)
	xmlOrbDisplayFrame2.orb.font1:SetTextColor(1, 1, 1, 1)
	xmlOrbDisplayFrame2.orb.font2:SetTextColor(1, 1, 1, 1)
end

function UpdateXMLTextures(orb)
	xmlOrbDisplayFrame2.orb.filling:SetTexture(orb.filling:GetTexture())
	xmlOrbDisplayFrame2.orb.galaxy1.texture:SetTexture(orb.galaxy1.texture:GetTexture())
	xmlOrbDisplayFrame2.orb.galaxy2.texture:SetTexture(orb.galaxy2.texture:GetTexture())
	xmlOrbDisplayFrame2.orb.galaxy3.texture:SetTexture(orb.galaxy3.texture:GetTexture())
	
	-- Reset selected texture indices when opening config
	RC32SelectedFillIndex = nil
	RC32SelectedRotationIndex = nil
	
	UIDropDownMenu_SetText(FillTexturesDropDown,"Choose one...")
	UIDropDownMenu_SetText(RotationTexturesDropDown,"Choose one...")
end

function UpdateXMLColors(orbColor,galaxyColor,font1,font2)
	xmlOrbDisplayFrame2.orb.filling:SetVertexColor(orbColor.r,orbColor.g,orbColor.b,orbColor.a)
	xmlOrbDisplayFrame2.orb.galaxy1.texture:SetVertexColor(galaxyColor.r,galaxyColor.g,galaxyColor.b,galaxyColor.a)
	xmlOrbDisplayFrame2.orb.galaxy2.texture:SetVertexColor(galaxyColor.r,galaxyColor.g,galaxyColor.b,galaxyColor.a)
	xmlOrbDisplayFrame2.orb.galaxy3.texture:SetVertexColor(galaxyColor.r,galaxyColor.g,galaxyColor.b,galaxyColor.a)
	xmlOrbDisplayFrame2.orb.font1:SetTextColor(font1.r,font1.g,font1.b,font1.a)
	xmlOrbDisplayFrame2.orb.font2:SetTextColor(font2.r,font2.g,font2.b,font2.a)
end

function UpdateXMLText(orb)
	xmlOrbDisplayFrame2.orb.font1:SetText(orb.font1:GetText())
	xmlOrbDisplayFrame2.orb.font2:SetText(orb.font2:GetText())
end

function FillXMLTemplate(frame)
	frame.orb = CreateXMLOrb(xmlOrbDisplayFrame2,"RC32_XMLOrb",150,defaultTextures.healthOrb.fill,defaultTextures.healthOrb.rotation)
	frame.orb.galaxy1.texture:SetAlpha(0.5)
	frame.orb.galaxy2.texture:SetAlpha(0.5)
	frame.orb.galaxy3.texture:SetAlpha(0.5)
	frame:SetScale(1.5)
end

------Health Orb Options Dropdown Stuff------
function CheckHealthOrbOptionValuesAgainstUIState()
	local selectedId = UIDropDownMenu_GetSelectedID(HealthOrbOptionsDropDown);
	if selectedId == 2 then
		CommitButton.activeElement = RC32CharacterData.combat
	elseif selectedId == 1 then
		CommitButton.activeElement = RC32CharacterData.healthOrb
		CommitButton.newActiveElement = RC32CharacterData.healthOrb
	end

	UpdateXMLColors(
		CommitButton.activeElement.orbColor,
		CommitButton.activeElement.galaxy,
		CommitButton.activeElement.font1,
		CommitButton.activeElement.font2)
end

function InitializeHealthOrbOptionsDropDown()
	CommitButton.activeElement = RC32CharacterData.healthOrb
	local fillOptions = {
	"Default",
	"Combat"
	}

	function HealthOrbOptionsDropDown:OnClick(value)
		UIDropDownMenu_SetSelectedID(HealthOrbOptionsDropDown,self:GetID())
		CheckHealthOrbOptionValuesAgainstUIState();
	end

	local function initMen(self, level)
		local stuff = UIDropDownMenu_CreateInfo()
		for k,v in pairs(fillOptions) do
		stuff = {}
		stuff.text = v
		stuff.value = v
		stuff.func = HealthOrbOptionsDropDown.OnClick
		UIDropDownMenu_AddButton(stuff, level)
		end
	end
	UIDropDownMenu_Initialize(HealthOrbOptionsDropDown, initMen)
	UIDropDownMenu_SetSelectedID(HealthOrbOptionsDropDown, 1)
	UIDropDownMenu_JustifyText(HealthOrbOptionsDropDown, "LEFT")
end

-------Mana Orb Options Dropdown Stuff-------
function CheckManaOrbOptionValuesAgainstUIState()
	local selectedId = UIDropDownMenu_GetSelectedID(ManaOrbOptionsDropDown);
	if selectedId == 3 then
		CommitButton.activeElement = RC32CharacterData.druidColors.cat
	elseif selectedId == 2 then
		CommitButton.activeElement = RC32CharacterData.druidColors.bear
	elseif selectedId == 1 then
		CommitButton.activeElement = RC32CharacterData.manaOrb
	end
	UpdateXMLColors(
		CommitButton.activeElement.orbColor,
		CommitButton.activeElement.galaxy,
		CommitButton.activeElement.font1,
		CommitButton.activeElement.font2)
end

function InitializeManaOrbOptionsDropDown()
	CommitButton.activeElement = RC32CharacterData.manaOrb
	local fillOptions2 = {
		"Default"
	}

	if RC32className == "Druid" then
		fillOptions2 = {
			"Default",
			"Bear",
			"Cat"
		}
	end

	function ManaOrbOptionsDropDown:OnClick(value)
		UIDropDownMenu_SetSelectedID(ManaOrbOptionsDropDown,self:GetID())
		CheckManaOrbOptionValuesAgainstUIState();
	end

	local function initMen(self, level)
	local stuff = UIDropDownMenu_CreateInfo()
	for k,v in pairs(fillOptions2) do
			stuff = {}
			stuff.text = v
			stuff.value = v
			stuff.func = ManaOrbOptionsDropDown.OnClick
			UIDropDownMenu_AddButton(stuff, level)
		end
	end
	UIDropDownMenu_Initialize(ManaOrbOptionsDropDown, initMen)
	UIDropDownMenu_SetSelectedID(ManaOrbOptionsDropDown, 1)
	UIDropDownMenu_JustifyText(ManaOrbOptionsDropDown, "LEFT")
end

--alloc the orbs and assign them to the health/mana orb variables, make them both movable from the get-go for testing
healthOrb = CreateOrb(nil,"RC32_HealthOrb",defaultOrbSize,defaultTextures.healthOrb.fill,defaultTextures.healthOrb.rotation,-250,0,"BOTTOM",monitorHealth)
manaOrb = CreateOrb(nil,"RC32_ManaOrb",defaultOrbSize,defaultTextures.manaOrb.fill,defaultTextures.manaOrb.rotation,250,0,"BOTTOM",monitorPower)
petOrb = CreatePetOrb(healthOrb,"RC32_PetOrb",87,-95,70,nil)
powerFrame = nil

-- Define segment counts per class (MoP 5.4.8)
-- Some classes/power types only exist in certain expansions
local classPowerSegments = {
	["Rogue"] = 5,      -- Combo Points (max 5) - all versions
	["Druid"] = 5,      -- Combo Points in cat form (max 5) - all versions
}

-- Add expansion-specific classes/power types
if RC32_IS_CATA_OR_LATER then
	classPowerSegments["Paladin"] = 3    -- Holy Power (max 3)
	classPowerSegments["Warlock"] = 4    -- Soul Shards (max 4)
	classPowerSegments["Priest"] = 3     -- Shadow Orbs (max 3)
end

if RC32_IS_MOP_OR_LATER then
	classPowerSegments["Monk"] = 4       -- Chi (max 4, can be 5 with talent)
	classPowerSegments["Shaman"] = 5     -- Maelstrom Weapon stacks (max 5)
end

-- Create segmented power tracker for supported classes
local numSegments = classPowerSegments[RC32className]
if numSegments then
	segmentedPowerTracker = CreateSegmentedPowerTracker(healthOrb, numSegments, defaultOrbSize)
	segmentedPowerTracker:SetScript("OnUpdate", RC32MonitorSegmentedPowers)
	-- Show the checkbox and rotation slider for classes that have power tracker
	if UsePowerTrackerCheckButton then
		UsePowerTrackerCheckButton:Show()
	end
	if RC32PowerTrackerRotationSlider then
		RC32PowerTrackerRotationSlider:Show()
	end
	if RC32PowerTrackerRotationSliderBackdrop then
		RC32PowerTrackerRotationSliderBackdrop:Show()
	end
	if RC32PowerTrackerResetButton then
		RC32PowerTrackerResetButton:Show()
	end
	if RC32PowerTrackerScaleSlider then
		RC32PowerTrackerScaleSlider:Show()
	end
	if RC32PowerTrackerScaleSliderBackdrop then
		RC32PowerTrackerScaleSliderBackdrop:Show()
	end
	if RC32PowerTrackerScaleResetButton then
		RC32PowerTrackerScaleResetButton:Show()
	end
	if RC32MaxStackSoundDropdown then
		RC32MaxStackSoundDropdown:Show()
	end
	if RC32MaxStackSoundLabelFrame then
		RC32MaxStackSoundLabelFrame:Show()
	end
else
	-- Hide the checkbox and rotation slider for classes that don't have power tracker
	if UsePowerTrackerCheckButton then
		UsePowerTrackerCheckButton:Hide()
	end
	if RC32PowerTrackerRotationSlider then
		RC32PowerTrackerRotationSlider:Hide()
	end
	if RC32PowerTrackerRotationSliderBackdrop then
		RC32PowerTrackerRotationSliderBackdrop:Hide()
	end
	if RC32PowerTrackerResetButton then
		RC32PowerTrackerResetButton:Hide()
	end
	if RC32PowerTrackerScaleSlider then
		RC32PowerTrackerScaleSlider:Hide()
	end
	if RC32PowerTrackerScaleSliderBackdrop then
		RC32PowerTrackerScaleSliderBackdrop:Hide()
	end
	if RC32PowerTrackerScaleResetButton then
		RC32PowerTrackerScaleResetButton:Hide()
	end
	if RC32MaxStackSoundDropdown then
		RC32MaxStackSoundDropdown:Hide()
	end
	if RC32MaxStackSoundLabelFrame then
		RC32MaxStackSoundLabelFrame:Hide()
	end
end
angelFrame = addArtwork(images.."d3_angel2test.tga",manaOrb,"AngelFrame",70,5,160,160)
demonFrame = addArtwork(images.."d3_demon2test.tga",healthOrb,"DemonFrame",-90,5,160,160)
makeFrameMovable(healthOrb)
makeFrameMovable(manaOrb)
makeFrameMovable(petOrb)





-- DK Disease Box Tracker on mana orb (MoP only)
-- DoT Tracker - Tracks personal debuffs on target for all classes
-- Square spell icons with countdown timers, shift+drag to move
---------------------------------------------------------------------------------------------------------------------------------------------------------------
do
	local ICON_SIZE = 50

	-- Class DoT definitions: { name = debuff name, spellId = for icon texture, saveKey = unique save key }
	local classDoTs = {
		["Death Knight"] = {
			{ name = "Frost Fever",    spellId = 55095, saveKey = "dot_FrostFever" },
			{ name = "Blood Plague",   spellId = 55078, saveKey = "dot_BloodPlague" },
		},
		["Warlock"] = {
			{ name = "Corruption",           spellId = 172,   saveKey = "dot_Corruption" },
			{ name = "Immolate",             spellId = 348,   saveKey = "dot_Immolate" },
			{ name = "Agony",                spellId = 980,   saveKey = "dot_Agony" },
			{ name = "Unstable Affliction",  spellId = 30108, saveKey = "dot_UnstableAffliction" },
			{ name = "Doom",                 spellId = 603,   saveKey = "dot_Doom" },
		},
		["Hunter"] = {
			{ name = "Serpent Sting",  spellId = 1978,  saveKey = "dot_SerpentSting" },
			{ name = "Black Arrow",    spellId = 3674,  saveKey = "dot_BlackArrow" },
		},
		["Druid"] = {
			{ name = "Moonfire",  spellId = 8921,   saveKey = "dot_Moonfire" },
			{ name = "Sunfire",   spellId = 93402,  saveKey = "dot_Sunfire" },
			{ name = "Rake",      spellId = 1822,   saveKey = "dot_Rake" },
			{ name = "Rip",       spellId = 1079,   saveKey = "dot_Rip" },
		},
		["Priest"] = {
			{ name = "Shadow Word: Pain",  spellId = 589,   saveKey = "dot_SWPain" },
			{ name = "Vampiric Touch",     spellId = 34914, saveKey = "dot_VampiricTouch" },
			{ name = "Devouring Plague",   spellId = 2944,  saveKey = "dot_DevouringPlague" },
		},
		["Mage"] = {
			{ name = "Living Bomb",    spellId = 44457,  saveKey = "dot_LivingBomb" },
			{ name = "Nether Tempest", spellId = 114923, saveKey = "dot_NetherTempest" },
			{ name = "Frost Bomb",     spellId = 112948, saveKey = "dot_FrostBomb" },
		},
		["Warrior"] = {
			{ name = "Rend",         spellId = 772,    saveKey = "dot_Rend" },
			{ name = "Deep Wounds",  spellId = 115767, saveKey = "dot_DeepWounds" },
		},
		["Rogue"] = {
			{ name = "Rupture",  spellId = 1943, saveKey = "dot_Rupture" },
			{ name = "Garrote",  spellId = 703,  saveKey = "dot_Garrote" },
		},
		["Paladin"] = {
			{ name = "Censure",  spellId = 31803, saveKey = "dot_Censure" },
		},
		["Shaman"] = {
			{ name = "Flame Shock",  spellId = 8050, saveKey = "dot_FlameShock" },
		},
		["Monk"] = {
			{ name = "Rising Sun Kick",  spellId = 130320, saveKey = "dot_RisingSunKick" },
		},
	}

	-- Aliases for different class name formats
	classDoTs["Deathknight"] = classDoTs["Death Knight"]
	classDoTs["DEATHKNIGHT"] = classDoTs["Death Knight"]

	-- Find our class DoTs
	local myDoTs = classDoTs[RC32className]
	if not myDoTs then
		-- Try localized display name
		myDoTs = classDoTs[RC32localizedDisplayName]
	end

	if myDoTs and #myDoTs > 0 then
		-- Filter to only spells that exist in this game version
		local validDoTs = {}
		for _, dot in ipairs(myDoTs) do
			local spellName, _, spellIcon = GetSpellInfo(dot.spellId)
			if spellName and spellIcon then
				table.insert(validDoTs, dot)
			end
		end

		if #validDoTs > 0 then
			local trackerFrames = {}

			for i, info in ipairs(validDoTs) do
				local box = CreateFrame("Frame", "RC32DotIcon"..i, UIParent)
				box:SetSize(ICON_SIZE, ICON_SIZE)
				box:SetFrameStrata("MEDIUM")
				box:SetFrameLevel(10)
				box:Hide()

				-- Default position: spread out from center
				local totalDots = #validDoTs
				local spacing = 55
				local totalWidth = (totalDots - 1) * spacing
				local defaultX = -totalWidth/2 + (i-1) * spacing
				box:SetPoint("CENTER", UIParent, "CENTER", defaultX, 80)

				-- Black border
				local border = box:CreateTexture(nil, "BACKGROUND")
				border:SetPoint("TOPLEFT", -2, 2)
				border:SetPoint("BOTTOMRIGHT", 2, -2)
				border:SetColorTexture(0, 0, 0, 1)

				-- Spell icon texture
				local icon = box:CreateTexture(nil, "ARTWORK")
				icon:SetAllPoints()
				icon:SetTexture(select(3, GetSpellInfo(info.spellId)))
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

				-- Darkened overlay for readability
				local darkOverlay = box:CreateTexture(nil, "ARTWORK", nil, 1)
				darkOverlay:SetAllPoints()
				darkOverlay:SetColorTexture(0, 0, 0, 0.3)

				-- Cooldown swipe overlay
				local cooldown = CreateFrame("Cooldown", "RC32DotCooldown"..i, box, "CooldownFrameTemplate")
				cooldown:SetAllPoints(icon)
				cooldown:SetFrameLevel(box:GetFrameLevel() + 1)
				pcall(function() cooldown:SetDrawEdge(true) end)
				pcall(function() cooldown:SetDrawSwipe(true) end)
				pcall(function() cooldown:SetHideCountdownNumbers(true) end)
				pcall(function() cooldown:SetSwipeColor(0, 0, 0, 0.6) end)
				-- Hide the built-in cooldown text if OmniCC or similar is present
				cooldown.noCooldownCount = true

				-- Text overlay frame (above cooldown swipe)
				local textOverlay = CreateFrame("Frame", nil, box)
				textOverlay:SetAllPoints()
				textOverlay:SetFrameLevel(cooldown:GetFrameLevel() + 2)

				-- Big timer text (on top of swipe)
				local timer = textOverlay:CreateFontString(nil, "OVERLAY")
				timer:SetFont("Fonts\\FRIZQT__.TTF", 22, "THICKOUTLINE")
				timer:SetPoint("CENTER", 0, 0)
				timer:SetTextColor(1, 1, 1, 1)
				timer:SetText("")

				-- Expiring glow (flashes when ≤5 seconds remain)
				local glow = textOverlay:CreateTexture(nil, "OVERLAY")
				glow:SetPoint("TOPLEFT", box, "TOPLEFT", -6, 6)
				glow:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 6, -6)
				glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
				glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
				glow:SetBlendMode("ADD")
				glow:Hide()

				-- Shift+drag to move
				box:SetMovable(true)
				box:EnableMouse(true)
				box:RegisterForDrag("LeftButton")
				box:SetScript("OnDragStart", function(self)
					if IsShiftKeyDown() then
						self:StartMoving()
					end
				end)
				box:SetScript("OnDragStop", function(self)
					self:StopMovingOrSizing()
					if RC32CharacterData.dotTracker then
						local point, _, relPoint, x, y = self:GetPoint(1)
						RC32CharacterData.dotTracker[info.saveKey] = {point=point, relPoint=relPoint, x=x, y=y}
					end
				end)

				trackerFrames[i] = {box=box, timer=timer, cooldown=cooldown, glow=glow, name=info.name, saveKey=info.saveKey, defaultX=defaultX}
			end

			-- Apply saved positions/scale (called after ADDON_LOADED)
			function RC32_RefreshDotPositions()
				local dt = RC32CharacterData.dotTracker
				if not dt then return end
				for i, tf in ipairs(trackerFrames) do
					local savedPos = dt[tf.saveKey]
					if savedPos then
						tf.box:ClearAllPoints()
						tf.box:SetPoint(savedPos.point, UIParent, savedPos.relPoint, savedPos.x, savedPos.y)
					end
					tf.box:SetScale(dt.scale or 1.0)
				end
			end

			-- Scale function
			local function RC32_SetDotScale(val)
				if RC32CharacterData.dotTracker then
					RC32CharacterData.dotTracker.scale = val
				end
				for i, tf in ipairs(trackerFrames) do
					tf.box:SetScale(val)
				end
				print("|cFF00FF00[RCDiabloOrbs]|r DoT tracker scale set to |cFFFFCC00" .. math.floor(val * 100) .. "%|r")
			end

			-- Reset positions
			local function RC32_ResetDotPositions()
				for i, tf in ipairs(trackerFrames) do
					if RC32CharacterData.dotTracker then
						RC32CharacterData.dotTracker[tf.saveKey] = nil
					end
					tf.box:ClearAllPoints()
					tf.box:SetPoint("CENTER", UIParent, "CENTER", tf.defaultX, 80)
				end
				print("|cFF00FF00[RCDiabloOrbs]|r DoT tracker positions reset.")
			end

			-- Slash command
			SLASH_RCDOTS1 = "/rcdots"
			SlashCmdList["RCDOTS"] = function(msg)
				msg = msg:lower():trim()
				if msg == "reset" then
					RC32_ResetDotPositions()
				elseif msg:match("^scale") then
					local val = tonumber(msg:match("scale%s+(.+)"))
					if val then
						RC32_SetDotScale(val / 100)
					else
						print("|cFF00FF00[RCDiabloOrbs]|r Usage: /rcdots scale 50-200")
					end
				else
					print("|cFFFFCC00[RCDiabloOrbs] DoT Tracker Commands:|r")
					print("  |cFFFFCC00Shift+drag|r - Move the DoT tracker icons")
					print("  |cFFFFCC00/rcdots scale 100|r - Set scale (50-200)")
					print("  |cFFFFCC00/rcdots reset|r - Reset to default positions")
				end
			end

			-- Keep old slash command as alias
			SLASH_RCDISEASE1 = "/rcdisease"
			SlashCmdList["RCDISEASE"] = SlashCmdList["RCDOTS"]

			-- Debuff scanner: find player's debuff on target
			local function getDebuffInfo(spellName)
				local idx = 1
				while true do
					local name, _, _, _, duration, expirationTime, caster = UnitDebuff("target", idx)
					if not name then break end
					-- hidden in combat on Retail / WoW Forever: can't tell, show nothing
					if RC32_Secret(name) or RC32_Secret(caster) or RC32_Secret(expirationTime) then return nil end
					if name == spellName and caster == "player" then
						local rem = expirationTime - GetTime()
						if rem > 0 then
							return rem, duration, expirationTime
						end
						return 0, 0, 0
					end
					idx = idx + 1
				end
				return nil
			end

			-- Toggle function for menu checkbox
			function RC32_ToggleDotTracker(enabled)
				RC32CharacterData.dotTrackerEnabled = enabled
				if not enabled then
					for i, tf in ipairs(trackerFrames) do
						tf.box:Hide()
						tf.glow:Hide()
					end
				end
			end

			-- Throttled OnUpdate scanner
			local elapsed_acc = 0
			local dotMonitor = CreateFrame("Frame")
			dotMonitor:SetScript("OnUpdate", function(self, elapsed)
				if RC32CharacterData and RC32CharacterData.dotTrackerEnabled == false then return end
				elapsed_acc = elapsed_acc + elapsed
				if elapsed_acc < 0.1 then return end
				elapsed_acc = 0
				local now = GetTime()
				for i, tf in ipairs(trackerFrames) do
					local rem, duration, expirationTime = getDebuffInfo(tf.name)
					if rem and rem > 0 then
						tf.box:Show()
						tf.timer:SetText(string.format("%.0f", rem))
						-- Set cooldown swipe (startTime, duration)
						if duration and duration > 0 then
							local startTime = expirationTime - duration
							if not tf.lastStart or tf.lastStart ~= startTime then
								tf.cooldown:SetCooldown(startTime, duration)
								tf.lastStart = startTime
							end
						end
						-- Flash glow when ≤5 seconds remain (pulse every second)
						if rem <= 5 then
							local pulse = math.floor(now * 2) % 2 -- toggles 0/1 twice per second
							if pulse == 0 then
								tf.glow:SetAlpha(0.8)
								tf.glow:Show()
							else
								tf.glow:SetAlpha(0.3)
								tf.glow:Show()
							end
							tf.timer:SetTextColor(1, 0.2, 0.2, 1) -- red text
						else
							tf.glow:Hide()
							tf.timer:SetTextColor(1, 1, 1, 1) -- white text
						end
					else
						tf.box:Hide()
						tf.timer:SetText("")
						tf.glow:Hide()
						tf.timer:SetTextColor(1, 1, 1, 1)
						tf.lastStart = nil
					end
				end
			end)
		end -- #validDoTs > 0
	end -- myDoTs
end


---------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Shared Profiles - account-wide settings sharing between characters
---------------------------------------------------------------------------------------------------------------------------------------------------------------
do
	-- Deep copy helper (ignores frames/functions, only copies pure data)
	local function deepCopy(t, seen)
		if type(t) ~= "table" then return t end
		seen = seen or {}
		if seen[t] then return seen[t] end
		local copy = {}
		seen[t] = copy
		for k, v in pairs(t) do
			if type(v) ~= "function" and type(v) ~= "userdata" then
				copy[k] = deepCopy(v, seen)
			end
		end
		return copy
	end

	-- Save current character settings as the shared profile
	function RC32_SaveSharedProfile()
		if not RC32AccountData then RC32AccountData = {} end
		if not RC32CharacterData then return false end
		RC32AccountData.sharedProfile = deepCopy(RC32CharacterData)
		RC32AccountData.sharedProfileTime = time()
		return true
	end

	-- Apply the shared profile to this character's data
	function RC32_LoadSharedProfile()
		if not RC32AccountData or not RC32AccountData.sharedProfile then return false end
		local copy = deepCopy(RC32AccountData.sharedProfile)
		-- Merge into RC32CharacterData (preserve the reference since it's saved-per-char)
		for k, v in pairs(copy) do
			RC32CharacterData[k] = v
		end
		return true
	end

	-- Popup confirmation dialog
	local function showConfirm(message, onYes)
		StaticPopupDialogs["RC32_PROFILE_CONFIRM"] = {
			text = message,
			button1 = "Yes",
			button2 = "Cancel",
			OnAccept = function() if onYes then onYes() end end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
		StaticPopup_Show("RC32_PROFILE_CONFIRM")
	end

	-- Options frame
	local f = CreateFrame("Frame", "RC32ProfilesFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(280, 260)
	f:SetFrameStrata("DIALOG")
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
			tile = true, tileSize = 32, edgeSize = 16,
			insets = { left = 5, right = 5, top = 5, bottom = 5 }
		})
	end
	f:Hide()

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", f, "TOP", 0, -14)
	title:SetText("|cFFFFCC00Settings Profiles|r")

	local desc = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	desc:SetPoint("TOP", title, "BOTTOM", 0, -8)
	desc:SetWidth(250)
	desc:SetJustifyH("CENTER")
	desc:SetText("Share your addon settings across\nall characters on this account.")

	-- Status line showing when the profile was last saved
	local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	status:SetPoint("TOP", desc, "BOTTOM", 0, -10)
	status:SetWidth(250)
	status:SetJustifyH("CENTER")

	local function updateStatus()
		if RC32AccountData and RC32AccountData.sharedProfile then
			local ts = RC32AccountData.sharedProfileTime
			local dateStr = ts and date("%Y-%m-%d %H:%M", ts) or "unknown"
			status:SetText("|cFF888888Shared profile last saved:|r\n|cFFFFFFFF" .. dateStr .. "|r")
		else
			status:SetText("|cFF888888No shared profile saved yet.|r")
		end
	end
	f:SetScript("OnShow", updateStatus)

	-- Save button
	local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	saveBtn:SetSize(230, 26)
	saveBtn:SetPoint("TOP", status, "BOTTOM", 0, -14)
	saveBtn:SetText("Save Current Settings as Shared")
	saveBtn:SetScript("OnClick", function()
		showConfirm(
			"Save this character's current settings\nas the shared profile?\n\nThis will overwrite any existing shared profile.",
			function()
				if RC32_SaveSharedProfile() then
					print("|cFF00FF00[RCDiabloOrbs]|r Shared profile saved.")
					updateStatus()
				else
					print("|cFFFF4444[RCDiabloOrbs]|r Failed to save shared profile.")
				end
			end)
	end)

	-- Load button
	local loadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	loadBtn:SetSize(230, 26)
	loadBtn:SetPoint("TOP", saveBtn, "BOTTOM", 0, -6)
	loadBtn:SetText("Load Shared Settings")
	loadBtn:SetScript("OnClick", function()
		if not RC32AccountData or not RC32AccountData.sharedProfile then
			print("|cFFFF4444[RCDiabloOrbs]|r No shared profile exists. Save one from another character first.")
			return
		end
		showConfirm(
			"Replace this character's settings\nwith the shared profile?\n\nYou'll need to /reload UI for all changes to apply.",
			function()
				if RC32_LoadSharedProfile() then
					print("|cFF00FF00[RCDiabloOrbs]|r Shared profile loaded. Type |cFFFFCC00/reload|r to apply all changes.")
				else
					print("|cFFFF4444[RCDiabloOrbs]|r Failed to load shared profile.")
				end
			end)
	end)

	-- Reload UI button
	local reloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	reloadBtn:SetSize(230, 26)
	reloadBtn:SetPoint("TOP", loadBtn, "BOTTOM", 0, -6)
	reloadBtn:SetText("Reload UI")
	reloadBtn:SetScript("OnClick", function() ReloadUI() end)

	-- Close button
	local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	closeBtn:SetSize(80, 22)
	closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
	closeBtn:SetText("Close")
	closeBtn:SetScript("OnClick", function() f:Hide() end)

	-- Toggle function called by the menu button
	function RC32_ToggleProfilesMenu()
		if f:IsShown() then
			f:Hide()
		else
			f:ClearAllPoints()
			if RC32GUI and RC32GUI:IsShown() then
				f:SetPoint("TOPLEFT", RC32GUI, "TOPRIGHT", 5, 0)
			else
				f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			end
			f:Show()
		end
	end
end

-- Battle Rez Panel - shows dead party/raid members for quick battle rez
-- Only active for Druids (Rebirth), Death Knights (Raise Ally), Warlocks (Soulstone)
---------------------------------------------------------------------------------------------------------------------------------------------------------------
do
	-- Spell IDs for battle rez spells (works across all locales)
	local BATTLE_REZ_IDS = {
		DRUID = 20484,       -- Rebirth
		DEATHKNIGHT = 61999, -- Raise Ally
		WARLOCK = 20707,     -- Soulstone
	}

	local _, classFile = UnitClass("player")
	local rezSpellID = BATTLE_REZ_IDS[classFile]
	local rezSpell = nil
	if rezSpellID then
		rezSpell = GetSpellInfo(rezSpellID) -- gets localized spell name, nil if spell doesn't exist in this version
	end

	if rezSpell then
		-- All Battle Rez settings are stored account-wide in RC32AccountData.battleRez
		-- so cols/rows/width/height/position/enabled are shared across all characters.
		-- One-time migration from RC32CharacterData for existing users:
		if not RC32AccountData then RC32AccountData = {} end
		if not RC32AccountData.battleRez then
			RC32AccountData.battleRez = {}
			-- Migrate any per-char settings we find
			if RC32CharacterData then
				local br = RC32AccountData.battleRez
				br.cols       = RC32CharacterData.battleRezCols
				br.rows       = RC32CharacterData.battleRezRows
				br.btnWidth   = RC32CharacterData.battleRezBtnWidth
				br.btnHeight  = RC32CharacterData.battleRezBtnHeight
				br.pos        = RC32CharacterData.battleRezPos
				br.enabled    = RC32CharacterData.battleRezEnabled
			end
		end
		-- Helper to access battle rez settings (creates with defaults if missing)
		local function brData()
			if not RC32AccountData then RC32AccountData = {} end
			if not RC32AccountData.battleRez then
				RC32AccountData.battleRez = {
					enabled = true,
					cols = 5,
					rows = 5,
					btnWidth = 100,
					btnHeight = 28,
				}
			end
			return RC32AccountData.battleRez
		end

		local MAX_SLOTS = 40
		local DEFAULT_BUTTON_HEIGHT = 28
		local DEFAULT_BUTTON_WIDTH = 100
		local BUTTON_GAP = 3
		local PANEL_WIDTH = DEFAULT_BUTTON_WIDTH + 16
		local PANEL_HEIGHT = MAX_SLOTS * (DEFAULT_BUTTON_HEIGHT + BUTTON_GAP) + 38

		-- Is this dead unit within battle-rez range? Prefer the actual rez spell's
		-- range, else UnitInRange (~40 yd). These range checks DO work inside
		-- instances (unlike UnitPosition). Returns true when range can't be
		-- determined, so we never dim spuriously.
		local function rezUnitInRange(unit)
			if not unit or not UnitExists(unit) then return true end
			if rezSpell then
				local ok, r = pcall(IsSpellInRange, rezSpell, unit)
				if ok then
					if r == 1 then return true end
					if r == 0 then return false end
				end
			end
			local inRange, checked = UnitInRange(unit)
			if RC32_Secret(inRange) or RC32_Secret(checked) then
				return true
			end
			if checked then
				return inRange and true or false
			end
			return true
		end

		-- Panel container (non-secure, so we can Show/Hide in combat)
		local panel = CreateFrame("Frame", "RC32BattleRezPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
		-- Anchor to the left of ElvUI main action bar if available, else default
		if _G["ElvUI_Bar1"] then
			panel:SetPoint("RIGHT", _G["ElvUI_Bar1"], "LEFT", -10, 0)
		else
			panel:SetPoint("BOTTOM", UIParent, "BOTTOM", -300, 150)
		end
		panel:SetFrameStrata("MEDIUM")
		panel:SetClampedToScreen(true) -- prevent dragging off-screen
		if panel.SetBackdrop then
			panel:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8X8",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = false, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 }
			})
			panel:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
			panel:SetBackdropBorderColor(0.4, 0.1, 0.1, 1)
		end
		panel:SetMovable(true)
		panel:EnableMouse(true)
		panel:RegisterForDrag("LeftButton")
		panel:SetScript("OnDragStart", function(self)
			if IsShiftKeyDown() then self:StartMoving() end
		end)
		panel:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			if RC32CharacterData then
				local point, _, relPoint, x, y = self:GetPoint(1)
				brData().pos = {point=point, relPoint=relPoint, x=x, y=y}
			end
		end)
		panel:SetAlpha(0)
		local titleBg = panel:CreateTexture(nil, "ARTWORK")
		titleBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
		titleBg:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
		titleBg:SetHeight(34)
		titleBg:SetColorTexture(0.3, 0.05, 0.05, 0.95)

		local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", titleBg, "TOP", 0, -3)
		title:SetText("|cFFFFCC00Battle Rez|r")

		-- Cooldown and charges status line
		local statusLine = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		statusLine:SetPoint("BOTTOM", titleBg, "BOTTOM", 0, 3)
		statusLine:SetText("")

		-- OnUpdate to track cooldown and charges
		local cdAccum = 0
		panel:SetScript("OnUpdate", function(self, elapsed)
			cdAccum = cdAccum + elapsed
			if cdAccum < 0.2 then return end
			cdAccum = 0

			local parts = {}

			-- Player's spell cooldown
			if rezSpellID then
				local start, duration, enabled = GetSpellCooldown(rezSpellID)
				if RC32_Secret(start) or RC32_Secret(duration) then
					start, duration = nil, nil -- hidden in combat on Retail / WoW Forever
				end
				if start and start > 0 and duration and duration > 1.5 then
					local remaining = (start + duration) - GetTime()
					if remaining > 0 then
						local mins = math.floor(remaining / 60)
						local secs = math.floor(remaining % 60)
						table.insert(parts, string.format("|cFFFF4444CD: %d:%02d|r", mins, secs))
					else
						table.insert(parts, "|cFF00FF00Ready|r")
					end
				else
					table.insert(parts, "|cFF00FF00Ready|r")
				end
			end

			-- How many combat rezzes the raid can use this encounter, and how many
			-- are left. MoP/Cata cap it per encounter: 1 in 10-player, 3 in 25-player
			-- (Flex 5.4 = 3 regardless of size). TBC/Wrath had no raid-wide cap
			-- (per-spell cooldowns only), so no count is shown there.
			local function readCharges(spellID)
				if not spellID then return nil end
				-- Live pool reads back from GetSpellCharges on a combat-rez spell, but
				-- only for a spell you actually KNOW (unknown spell returns nil).
				if C_Spell and C_Spell.GetSpellCharges then
					local info = C_Spell.GetSpellCharges(spellID)
					if type(info) == "table" and not RC32_Secret(info.maxCharges) and not RC32_Secret(info.currentCharges)
						and info.maxCharges and info.maxCharges > 0 then
						return info.currentCharges
					end
				end
				if GetSpellCharges then
					local cur, mx = GetSpellCharges(spellID)
					if cur and mx and mx > 0 then return cur end
				end
				return nil
			end

			local inInst, instType = IsInInstance()
			if RC32_IS_CATA_OR_LATER and inInst and instType == "raid" then
				-- Intended per-encounter cap by raid size.
				local maxRez
				local _, _, diffID, _, maxPlayers = GetInstanceInfo()
				if diffID == 14 then                         -- Flexible (5.4) = 3
					maxRez = 3
				elseif maxPlayers and maxPlayers > 0 then
					maxRez = (maxPlayers <= 10) and 1 or 3
				else
					local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
					maxRez = (n <= 10) and 1 or 3
				end

				if maxRez and maxRez > 0 then
					-- Live "available" from the shared pool if the client exposes it
					-- (read via the player's own known rez spell), capped to the cap.
					local cur = readCharges(rezSpellID) or readCharges(20484)
						or readCharges(61999) or readCharges(20707)
					local shown = cur or maxRez
					if shown > maxRez then shown = maxRez end
					local color = shown > 0 and "|cFF00FF00" or "|cFFFF4444"
					table.insert(parts, color .. "Rez: " .. shown .. "/" .. maxRez .. "|r")
				end
			end

			if #parts > 0 then
				statusLine:SetText(table.concat(parts, " |cFF666666|||r "))
			else
				statusLine:SetText("")
			end
		end)

		-- Create secure buttons with FIXED macrotext (never changes, so combat-safe)
		-- Each slot tries party then raid unit of the same index
		local buttons = {}

		-- Pure alpha-based visibility (panel & buttons stay Shown() forever, alpha hides).
		-- Required because Hide/Show are protected on secure buttons in combat,
		-- and the panel (which has secure children) inherits this restriction.
		local function safePanelShow()
			panel:SetAlpha(1)
		end
		local function safePanelHide()
			panel:SetAlpha(0)
		end
		local function safeShowBtn(btn)
			btn:SetAlpha(1)
		end
		local function safeHideBtn(btn)
			btn:SetAlpha(0)
			btn.unit = nil
		end
		for i = 1, MAX_SLOTS do
			local btn = CreateFrame("Button", "RC32RezBtn"..i, panel, "SecureActionButtonTemplate")
			btn:SetSize(DEFAULT_BUTTON_WIDTH, DEFAULT_BUTTON_HEIGHT)
			-- position set by RC32_RelayoutBattleRez below

			-- Outer frame border
			local outerBorder = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
			outerBorder:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
			outerBorder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
			outerBorder:SetColorTexture(0, 0, 0, 1)

			-- Main background (will be tinted with class color)
			local bg = btn:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(0.12, 0.12, 0.14, 0.95)
			btn.bg = bg

			-- Class color stripe on the left edge (Vuhdo-style indicator)
			local stripe = btn:CreateTexture(nil, "ARTWORK")
			stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
			stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
			stripe:SetWidth(5)
			stripe:SetColorTexture(0.5, 0.5, 0.5, 1)
			btn.stripe = stripe

			-- Subtle highlight gradient (top half lighter)
			local gloss = btn:CreateTexture(nil, "ARTWORK", nil, 1)
			gloss:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, 0)
			gloss:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
			gloss:SetHeight(DEFAULT_BUTTON_HEIGHT / 2)
			gloss:SetColorTexture(1, 1, 1, 0.06)

			-- Hover highlight
			local hl = btn:CreateTexture(nil, "HIGHLIGHT")
			hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 5, 0)
			hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
			hl:SetColorTexture(1, 0.3, 0.3, 0.25)

			-- Name label (left-aligned, fills the button)
			local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			nameText:SetPoint("LEFT", btn, "LEFT", 10, 0)
			nameText:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
			nameText:SetJustifyH("LEFT")
			nameText:SetWordWrap(false)
			nameText:SetText("")
			btn.text = nameText

			-- Store unit IDs for this slot (informational only)
			local partyUnit = "party"..i
			local raidUnit = "raid"..i

			-- Set FIXED secure attributes at creation (out of combat, safe to set).
			-- These NEVER change. Macro conditional [@unit,dead,help] picks the right target.
			btn:SetAttribute("type", "macro")
			btn:SetAttribute("macrotext", string.format(
				"/cast [@raid%d,dead,help][@party%d,dead,help] %s",
				i, i, rezSpell
			))
			btn:RegisterForClicks("AnyDown", "AnyUp")
			btn:RegisterForDrag("LeftButton")
			-- Shift+drag to move the panel (non-secure script, allowed)
			btn:SetScript("OnDragStart", function(self)
				-- StartMoving is blocked in combat (panel has secure children).
				if IsShiftKeyDown() and not InCombatLockdown() then panel:StartMoving() end
			end)
			btn:SetScript("OnDragStop", function(self)
				if not InCombatLockdown() then
					panel:StopMovingOrSizing()
				end
				if RC32CharacterData then
					local point, _, relPoint, x, y = panel:GetPoint(1)
					brData().pos = {point=point, relPoint=relPoint, x=x, y=y}
				end
			end)
			-- Start invisible via alpha (NOT Hide, because secure frames taint if Hide called in combat)
			btn:SetAlpha(0)

			-- Mouseover: show rez range, and distance when the API allows it.
			-- (UnitPosition/GetPlayerFacing return nil inside instances, so distance
			-- and any direction are only available in the open world.)
			btn:SetScript("OnEnter", function(self)
				if not self.unit or not UnitExists(self.unit) then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:ClearLines()
				GameTooltip:AddLine(UnitName(self.unit) or "?", 1, 1, 1)
				if rezUnitInRange(self.unit) then
					GameTooltip:AddLine("|cFF00FF00In rez range|r")
				else
					GameTooltip:AddLine("|cFFFF4444Out of rez range|r")
				end
				local px, py = UnitPosition("player")
				local ux, uy = UnitPosition(self.unit)
				if px and ux then
					local dx, dy = ux - px, uy - py
					local dist = math.sqrt(dx * dx + dy * dy)
					GameTooltip:AddLine(string.format("Distance: ~%d yds", math.floor(dist + 0.5)), 0.8, 0.8, 0.8)
				else
					GameTooltip:AddLine("|cFF888888Distance only shown outside instances|r")
				end
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			buttons[i] = btn
		end

		-- Relayout buttons in a grid based on saved cols/rows settings.
		-- Panel dynamically shrinks to fit only visible (alpha-1) buttons.
		function RC32_RelayoutBattleRez(visibleCount)
			local cols = brData().cols or 5
			local rows = brData().rows or 5
			local bw = brData().btnWidth or DEFAULT_BUTTON_WIDTH
			local bh = brData().btnHeight or DEFAULT_BUTTON_HEIGHT
			if cols < 1 then cols = 1 end
			if rows < 1 then rows = 1 end
			local maxSlots = cols * rows
			if maxSlots > MAX_SLOTS then maxSlots = MAX_SLOTS end

			local sizeCount = visibleCount or maxSlots
			if sizeCount > maxSlots then sizeCount = maxSlots end
			if sizeCount < 1 then sizeCount = 1 end

			-- All frame operations guarded — parent panel inherits protection from secure children
			if not InCombatLockdown() then
				for i = 1, MAX_SLOTS do
					buttons[i]:ClearAllPoints()
					buttons[i]:SetSize(bw, bh)
					if i <= maxSlots then
						local col = (i - 1) % cols
						local row = math.floor((i - 1) / cols)
						local x = 8 + col * (bw + BUTTON_GAP)
						local y = -44 - row * (bh + BUTTON_GAP)
						buttons[i]:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
					end
				end

				local usedCols = math.min(sizeCount, cols)
				local usedRows = math.ceil(sizeCount / cols)
				local newWidth = usedCols * bw + (usedCols - 1) * BUTTON_GAP + 16
				local newHeight = usedRows * (bh + BUTTON_GAP) + 50
				panel:SetSize(newWidth, newHeight)
			end
		end
		RC32_RelayoutBattleRez()

		-- Helper to set button visuals (class color stripe and background)
		local function setButtonPlayer(btn, name, classFile)
			local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
			if cc then
				btn.stripe:SetColorTexture(cc.r, cc.g, cc.b, 1)
				btn.bg:SetColorTexture(cc.r * 0.25, cc.g * 0.25, cc.b * 0.25, 0.95)
			else
				btn.stripe:SetColorTexture(0.5, 0.5, 0.5, 1)
				btn.bg:SetColorTexture(0.12, 0.12, 0.14, 0.95)
			end
			btn.text:SetText(name)
		end

		-- Update function: scans party/raid for dead members
		-- Each button[i] is permanently bound to party{i}/raid{i} via its fixed macrotext
		local testMode = false
		local function updateRezPanel()
			if testMode then return end -- skip real updates while testing
			if brData().enabled == false then
				safePanelHide()
				for i = 1, MAX_SLOTS do safeHideBtn(buttons[i]) end
				return
			end
			local inRaid = IsInRaid and IsInRaid()
			local scanMax = inRaid and 40 or 4
			local prefix = inRaid and "raid" or "party"
			local deadCount = 0

			for i = 1, MAX_SLOTS do
				local unit = prefix..i
				if i <= scanMax and UnitExists(unit) and RC32_True(UnitIsDeadOrGhost(unit)) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
					local name = UnitName(unit) or "?"
					local _, unitClass = UnitClass(unit)
					setButtonPlayer(buttons[i], name, unitClass)
					safeShowBtn(buttons[i])
					buttons[i].unit = unit
					-- Dim immediately if already out of range (ticker keeps it updated).
					buttons[i]:SetAlpha(rezUnitInRange(unit) and 1.0 or 0.4)
					deadCount = deadCount + 1
				else
					safeHideBtn(buttons[i])
				end
			end

			-- Show full configured grid when anyone is dead (no dynamic shrinking)
			-- This prevents buttons at high slot indices from being off-screen
			if deadCount > 0 then
				RC32_RelayoutBattleRez() -- no arg = full grid size
				safePanelShow()
			else
				safePanelHide()
			end
		end

		-- Keep out-of-range dead players dimmed as you (or they) move. SetAlpha is
		-- not protected, so this is safe in combat. Class colour is preserved; only
		-- the button's alpha changes.
		local DIM_ALPHA = 0.4
		local function refreshRezRangeDim()
			if brData().enabled == false then return end
			for i = 1, MAX_SLOTS do
				local btn = buttons[i]
				if btn and btn.unit then
					btn:SetAlpha(rezUnitInRange(btn.unit) and 1.0 or DIM_ALPHA)
				end
			end
		end
		if C_Timer and C_Timer.NewTicker then
			C_Timer.NewTicker(0.25, refreshRezRangeDim)
		end

		-- Apply saved position
		-- The panel parents SecureActionButtonTemplate buttons, so it inherits
		-- their protection: ClearAllPoints/SetPoint on it are BLOCKED in combat.
		-- If we're locked down, remember it and re-apply on PLAYER_REGEN_ENABLED.
		function RC32_RefreshBattleRezPos()
			if brData().pos then
				local pos = brData().pos
				C_Timer.After(0, function()
					if InCombatLockdown() then
						RC32_battleRezPosPending = true
						return
					end
					RC32_battleRezPosPending = false
					panel:ClearAllPoints()
					panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
				end)
			end
		end

		-- Events for death detection
		local ef = CreateFrame("Frame")
		ef:RegisterEvent("UNIT_HEALTH")
		ef:RegisterEvent("UNIT_FLAGS")
		ef:RegisterEvent("GROUP_ROSTER_UPDATE")
		ef:RegisterEvent("PLAYER_ENTERING_WORLD")
		ef:RegisterEvent("PLAYER_REGEN_ENABLED")
		ef:RegisterEvent("PLAYER_REGEN_DISABLED")
		-- Additional death detection events for MoP Classic compatibility
		pcall(function() ef:RegisterEvent("UNIT_HEALTH_FREQUENT") end) -- MoP variant
		pcall(function() ef:RegisterEvent("PARTY_MEMBER_DISABLE") end) -- party member dies
		pcall(function() ef:RegisterEvent("PARTY_MEMBER_ENABLE") end)  -- party member rezzes
		pcall(function() ef:RegisterEvent("UNIT_CONNECTION") end)      -- disconnect
		pcall(function() ef:RegisterEvent("INCOMING_RESURRECT_CHANGED") end)
		pcall(function() ef:RegisterEvent("UNIT_AURA") end)            -- aura changes on death
		-- Retail and WoW Forever don't let addons use the combat log (registering
		-- it is an error there); the OnUpdate scan below catches deaths anyway.
		pcall(ef.RegisterEvent, ef, "COMBAT_LOG_EVENT_UNFILTERED")
		ef:SetScript("OnEvent", function(self, event, ...)
			-- Combat ended: apply any position change we had to skip while locked down.
			if event == "PLAYER_REGEN_ENABLED" and RC32_battleRezPosPending then
				RC32_battleRezPosPending = false
				if RC32_RefreshBattleRezPos then RC32_RefreshBattleRezPos() end
			end
			if event == "COMBAT_LOG_EVENT_UNFILTERED" then
				-- Only trigger on death-related combat log events
				local _, subEvent = CombatLogGetCurrentEventInfo and CombatLogGetCurrentEventInfo() or select(1, ...)
				if not subEvent then subEvent = select(2, ...) end
				if subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED" or subEvent == "SPELL_RESURRECT" then
					updateRezPanel()
				end
			else
				updateRezPanel()
			end
		end)

		-- Fast OnUpdate scanner (0.2s) to catch deaths that events miss
		local accum = 0
		ef:SetScript("OnUpdate", function(self, elapsed)
			accum = accum + elapsed
			if accum >= 0.2 then
				accum = 0
				updateRezPanel()
			end
		end)

		-- Slash command for test mode
		SLASH_RCREZ1 = "/rcrez"
		SlashCmdList["RCREZ"] = function(msg)
			msg = (msg or ""):lower()
			msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
			if msg == "test" then
				testMode = true
				local fakeNames = {
					{"Healbot",   "PRIEST"},
					{"Tankzilla", "WARRIOR"},
					{"Pewpew",    "MAGE"},
					{"Stabby",    "ROGUE"},
					{"Sneaky",    "HUNTER"},
					{"Zappy",     "SHAMAN"},
					{"Bubbles",   "PALADIN"},
					{"Doomguy",   "WARLOCK"},
				}
				for i = 1, MAX_SLOTS do
					if fakeNames[i] then
						setButtonPlayer(buttons[i], fakeNames[i][1], fakeNames[i][2])
						safeShowBtn(buttons[i])
					else
						safeHideBtn(buttons[i])
					end
				end
				safePanelShow()
				print("|cFF00FF00[RCDiabloOrbs]|r Battle Rez |cFFFFCC00TEST MODE|r active. Spell: |cFFFFCC00" .. rezSpell .. "|r")
				print("  Type |cFFFFCC00/rcrez hide|r to dismiss and resume normal operation.")
			elseif msg == "hide" or msg == "off" then
				testMode = false
				for i = 1, MAX_SLOTS do safeHideBtn(buttons[i]) end
				safePanelHide()
				updateRezPanel()
				print("|cFF00FF00[RCDiabloOrbs]|r Battle Rez test mode disabled.")
			else
				print("|cFFFFCC00[RCDiabloOrbs Battle Rez]|r - Spell: |cFFFFCC00" .. rezSpell .. "|r")
				print("  |cFFFFCC00/rcrez test|r - Show test panel with fake dead players")
				print("  |cFFFFCC00/rcrez hide|r - Dismiss test panel")
				print("  Shift+drag the panel to reposition it.")
			end
		end

		-- Battle Rez Options popup (anchored to right of main menu)
		local optionsFrame = CreateFrame("Frame", "RC32BattleRezOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		optionsFrame:SetSize(240, 500)
		optionsFrame:SetFrameStrata("DIALOG")
		if optionsFrame.SetBackdrop then
			optionsFrame:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
				tile = true, tileSize = 32, edgeSize = 16,
				insets = { left = 5, right = 5, top = 5, bottom = 5 }
			})
		end
		optionsFrame:Hide()

		-- Title
		local optTitle = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		optTitle:SetPoint("TOP", optionsFrame, "TOP", 0, -14)
		optTitle:SetText("|cFFFF4444Battle Rez Options|r")

		-- Spell info line
		local spellInfo = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		spellInfo:SetPoint("TOP", optTitle, "BOTTOM", 0, -8)
		spellInfo:SetText("Spell: |cFFFFCC00" .. rezSpell .. "|r")

		-- Enable checkbox
		local enableCheck = CreateFrame("CheckButton", "RC32BattleRezEnableCheck", optionsFrame, "UICheckButtonTemplate")
		enableCheck:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 15, -55)
		enableCheck.text = enableCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		enableCheck.text:SetPoint("LEFT", enableCheck, "RIGHT", 2, 0)
		enableCheck.text:SetText("Enable Battle Rez Panel")
		enableCheck:SetScript("OnShow", function(self)
			self:SetChecked(brData().enabled ~= false)
		end)
		enableCheck:SetScript("OnClick", function(self)
			if not RC32CharacterData then RC32CharacterData = {} end
			brData().enabled = self:GetChecked()
			if not self:GetChecked() then
				safePanelHide()
				for i = 1, MAX_SLOTS do safeHideBtn(buttons[i]) end
			else
				updateRezPanel()
			end
		end)

		-- Test Mode button
		local testBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
		testBtn:SetSize(180, 24)
		testBtn:SetPoint("TOP", enableCheck, "BOTTOM", 70, -8)
		testBtn:SetText("Toggle Test Mode")
		testBtn:SetScript("OnClick", function()
			if testMode then
				testMode = false
				for i = 1, MAX_SLOTS do safeHideBtn(buttons[i]) end
				safePanelHide()
				updateRezPanel()
				print("|cFF00FF00[RCDiabloOrbs]|r Battle Rez test mode disabled.")
			else
				testMode = true
				local fakeNames = {
					{"Healbot", "PRIEST"}, {"Tankzilla", "WARRIOR"},
					{"Pewpew", "MAGE"}, {"Stabby", "ROGUE"},
					{"Sneaky", "HUNTER"}, {"Zappy", "SHAMAN"},
					{"Bubbles", "PALADIN"}, {"Doomguy", "WARLOCK"},
				}
				for i = 1, MAX_SLOTS do
					if fakeNames[i] then
						setButtonPlayer(buttons[i], fakeNames[i][1], fakeNames[i][2])
						safeShowBtn(buttons[i])
					else
						safeHideBtn(buttons[i])
					end
				end
				safePanelShow()
				print("|cFF00FF00[RCDiabloOrbs]|r Battle Rez test mode enabled.")
			end
		end)

		-- Columns slider
		local colsSlider = CreateFrame("Slider", "RC32BattleRezColsSlider", optionsFrame, "OptionsSliderTemplate")
		colsSlider:SetPoint("TOP", testBtn, "BOTTOM", 0, -24)
		colsSlider:SetWidth(180)
		colsSlider:SetMinMaxValues(1, 8)
		colsSlider:SetValueStep(1)
		colsSlider:SetObeyStepOnDrag(true)
		_G[colsSlider:GetName().."Low"]:SetText("1")
		_G[colsSlider:GetName().."High"]:SetText("8")
		local colsLabel = _G[colsSlider:GetName().."Text"]
		colsSlider:SetScript("OnShow", function(self)
			local v = brData().cols or 5
			self:SetValue(v)
			colsLabel:SetText("Columns: "..v)
		end)
		colsSlider:SetScript("OnValueChanged", function(self, value)
			value = math.floor(value + 0.5)
			brData().cols = value
			colsLabel:SetText("Columns: "..value)
			if RC32_RelayoutBattleRez then RC32_RelayoutBattleRez() end
		end)

		-- Rows slider
		local rowsSlider = CreateFrame("Slider", "RC32BattleRezRowsSlider", optionsFrame, "OptionsSliderTemplate")
		rowsSlider:SetPoint("TOP", colsSlider, "BOTTOM", 0, -22)
		rowsSlider:SetWidth(180)
		rowsSlider:SetMinMaxValues(1, 40)
		rowsSlider:SetValueStep(1)
		rowsSlider:SetObeyStepOnDrag(true)
		_G[rowsSlider:GetName().."Low"]:SetText("1")
		_G[rowsSlider:GetName().."High"]:SetText("40")
		local rowsLabel = _G[rowsSlider:GetName().."Text"]
		rowsSlider:SetScript("OnShow", function(self)
			local v = brData().rows or 5
			self:SetValue(v)
			rowsLabel:SetText("Rows: "..v)
		end)
		rowsSlider:SetScript("OnValueChanged", function(self, value)
			value = math.floor(value + 0.5)
			brData().rows = value
			rowsLabel:SetText("Rows: "..value)
			if RC32_RelayoutBattleRez then RC32_RelayoutBattleRez() end
		end)

		-- Width slider
		local widthSlider = CreateFrame("Slider", "RC32BattleRezWidthSlider", optionsFrame, "OptionsSliderTemplate")
		widthSlider:SetPoint("TOP", rowsSlider, "BOTTOM", 0, -22)
		widthSlider:SetWidth(180)
		widthSlider:SetMinMaxValues(60, 260)
		widthSlider:SetValueStep(5)
		widthSlider:SetObeyStepOnDrag(true)
		_G[widthSlider:GetName().."Low"]:SetText("60")
		_G[widthSlider:GetName().."High"]:SetText("260")
		local widthLabel = _G[widthSlider:GetName().."Text"]
		widthSlider:SetScript("OnShow", function(self)
			local v = brData().btnWidth or DEFAULT_BUTTON_WIDTH
			self:SetValue(v); widthLabel:SetText("Width: "..v)
		end)
		widthSlider:SetScript("OnValueChanged", function(self, value)
			value = math.floor(value/5 + 0.5) * 5
			brData().btnWidth = value
			widthLabel:SetText("Width: "..value)
			if RC32_RelayoutBattleRez then RC32_RelayoutBattleRez() end
		end)

		-- Height slider
		local heightSlider = CreateFrame("Slider", "RC32BattleRezHeightSlider", optionsFrame, "OptionsSliderTemplate")
		heightSlider:SetPoint("TOP", widthSlider, "BOTTOM", 0, -22)
		heightSlider:SetWidth(180)
		heightSlider:SetMinMaxValues(16, 48)
		heightSlider:SetValueStep(2)
		heightSlider:SetObeyStepOnDrag(true)
		_G[heightSlider:GetName().."Low"]:SetText("16")
		_G[heightSlider:GetName().."High"]:SetText("48")
		local heightLabel = _G[heightSlider:GetName().."Text"]
		heightSlider:SetScript("OnShow", function(self)
			local v = brData().btnHeight or DEFAULT_BUTTON_HEIGHT
			self:SetValue(v); heightLabel:SetText("Height: "..v)
		end)
		heightSlider:SetScript("OnValueChanged", function(self, value)
			value = math.floor(value/2 + 0.5) * 2
			brData().btnHeight = value
			heightLabel:SetText("Height: "..value)
			if RC32_RelayoutBattleRez then RC32_RelayoutBattleRez() end
		end)

		-- Reset Position button
		local resetBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
		resetBtn:SetSize(180, 24)
		resetBtn:SetPoint("TOP", heightSlider, "BOTTOM", 0, -14)
		resetBtn:SetText("Reset Panel Position")
		resetBtn:SetScript("OnClick", function()
			if InCombatLockdown() then
				print("|cFF00FF00[RCDiabloOrbs]|r Can't reposition the Battle Rez panel in combat - try again afterwards.")
				return
			end
			brData().pos = nil
			panel:ClearAllPoints()
			-- Anchor to the left of ElvUI main action bar if available, else default
		if _G["ElvUI_Bar1"] then
			panel:SetPoint("RIGHT", _G["ElvUI_Bar1"], "LEFT", -10, 0)
		else
			panel:SetPoint("BOTTOM", UIParent, "BOTTOM", -300, 150)
		end
			print("|cFF00FF00[RCDiabloOrbs]|r Battle Rez panel position reset.")
		end)

		-- Help text
		local helpText = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		helpText:SetPoint("BOTTOM", optionsFrame, "BOTTOM", 0, 40)
		helpText:SetWidth(200)
		helpText:SetJustifyH("CENTER")
		helpText:SetText("|cFF888888Shift+drag the Battle Rez\npanel to reposition it.|r")

		-- Close button
		local closeBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
		closeBtn:SetSize(80, 22)
		closeBtn:SetPoint("BOTTOM", optionsFrame, "BOTTOM", 0, 12)
		closeBtn:SetText("Close")
		closeBtn:SetScript("OnClick", function() optionsFrame:Hide() end)

		-- Toggle function called by the menu button
		function RC32_ToggleBattleRezOptions()
			if optionsFrame:IsShown() then
				optionsFrame:Hide()
			else
				-- Anchor to the right of RC32GUI
				optionsFrame:ClearAllPoints()
				if RC32GUI and RC32GUI:IsShown() then
					optionsFrame:SetPoint("TOPLEFT", RC32GUI, "TOPRIGHT", 5, 0)
				else
					optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
				end
				optionsFrame:Show()
			end
		end
	end
end


-- Pet missing warning flash
local RC32_petWarning = CreateFrame("Frame", "RC32PetWarning", UIParent)
RC32_petWarning:SetSize(400, 60)
RC32_petWarning:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 350)
RC32_petWarning:SetFrameStrata("HIGH")
RC32_petWarning:Hide()

-- X close button on the pet warning
local petWarningClose = CreateFrame("Button", nil, RC32_petWarning)
petWarningClose:SetSize(20, 20)
petWarningClose:SetPoint("TOPRIGHT", RC32_petWarning, "TOPRIGHT", -2, -2)
petWarningClose:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
petWarningClose:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
petWarningClose:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
petWarningClose:SetScript("OnClick", function()
    RC32CharacterData.petWarningEnabled = false
    RC32_petWarning:Hide()
    RC32_petWarningAnim:Stop()
    if ShowPetWarningCheckButton then ShowPetWarningCheckButton:SetChecked(false) end
    print("|cFF00FF00[RCDiabloOrbs]|r Pet warning disabled. Re-enable in the menu options.")
end)

local RC32_petWarningBG = RC32_petWarning:CreateTexture(nil, "BACKGROUND")
RC32_petWarningBG:SetAllPoints(RC32_petWarning)
RC32_petWarningBG:SetColorTexture(0.6, 0.1, 0.1, 0.85)

local RC32_petWarningText = RC32_petWarning:CreateFontString(nil, "OVERLAY")
RC32_petWarningText:SetFont(RC32CharacterData and RC32CharacterData.font or "Fonts\\FRIZQT__.TTF", 20, "THINOUTLINE")
RC32_petWarningText:SetAllPoints(RC32_petWarning)
RC32_petWarningText:SetJustifyH("CENTER")
RC32_petWarningText:SetJustifyV("MIDDLE")
RC32_petWarningText:SetText("⚠ No Pet!")

-- Flash animation
RC32_petWarningAnim = RC32_petWarning:CreateAnimationGroup()
RC32_petWarningAnim:SetLooping("REPEAT")
local RC32_petWarningFadeOut = RC32_petWarningAnim:CreateAnimation("Alpha")
RC32_petWarningFadeOut:SetFromAlpha(1)
RC32_petWarningFadeOut:SetToAlpha(0.2)
RC32_petWarningFadeOut:SetDuration(0.6)
RC32_petWarningFadeOut:SetOrder(1)
local RC32_petWarningFadeIn = RC32_petWarningAnim:CreateAnimation("Alpha")
RC32_petWarningFadeIn:SetFromAlpha(0.2)
RC32_petWarningFadeIn:SetToAlpha(1)
RC32_petWarningFadeIn:SetDuration(0.6)
RC32_petWarningFadeIn:SetOrder(2)

local function RC32_IsPetClass()
    local class = RC32className
    -- Only classes that ALWAYS have a permanent pet
    if class == "Hunter" or class == "Warlock" then return true end
    -- DKs are NOT auto-detected (only Unholy has a permanent pet and
    -- spec detection is unreliable in MoP Classic).
    -- DK players can manually enable via the "Show Pet Warning" checkbox.
    return false
end

-- Classes that can have a pet and therefore get the Yes/No reminder dialog.
-- Broader than RC32_IsPetClass() (which is only the always-pet classes used for
-- auto-enabling): this also includes DK, since only some DK specs have a pet.
local function RC32_ClassGetsPetDialog()
    local class = RC32className
    return class == "Hunter" or class == "Warlock"
        or class == "Deathknight" or class == "Death Knight" or class == "DEATHKNIGHT"
end

-- Reminder dialog: asks pet classes (Hunter, Warlock, DK) whether to show the pet warning
local RC32_specSwapPopup = CreateFrame("Frame", "RC32SpecSwapPopup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
RC32_specSwapPopup:SetSize(300, 80)
RC32_specSwapPopup:SetPoint("TOP", UIParent, "TOP", 0, -200)
RC32_specSwapPopup:SetFrameStrata("DIALOG")
RC32_specSwapPopup:Hide()
RC32_specSwapPopup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
})

local specPopupText = RC32_specSwapPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
specPopupText:SetPoint("TOP", RC32_specSwapPopup, "TOP", 0, -12)
specPopupText:SetWidth(270)
specPopupText:SetText("|cFFFF6600Enable pet reminder for this spec?|r")

local specPopupYes = CreateFrame("Button", nil, RC32_specSwapPopup, "UIPanelButtonTemplate")
specPopupYes:SetSize(80, 22)
specPopupYes:SetPoint("BOTTOMLEFT", RC32_specSwapPopup, "BOTTOMLEFT", 40, 10)
specPopupYes:SetText("Yes")
specPopupYes:SetScript("OnClick", function()
    RC32CharacterData.petWarningEnabled = true
    if ShowPetWarningCheckButton then ShowPetWarningCheckButton:SetChecked(true) end
    RC32_UpdatePetWarning()
    RC32_specSwapPopup:Hide()
end)

local specPopupNo = CreateFrame("Button", nil, RC32_specSwapPopup, "UIPanelButtonTemplate")
specPopupNo:SetSize(80, 22)
specPopupNo:SetPoint("BOTTOMRIGHT", RC32_specSwapPopup, "BOTTOMRIGHT", -40, 10)
specPopupNo:SetText("No")
specPopupNo:SetScript("OnClick", function()
    RC32CharacterData.petWarningEnabled = false
    if ShowPetWarningCheckButton then ShowPetWarningCheckButton:SetChecked(false) end
    RC32_petWarning:Hide()
    RC32_petWarningAnim:Stop()
    RC32_specSwapPopup:Hide()
end)

local RC32_loginTime = GetTime()

function RC32_ShowSpecSwapPopup(fromLogin)
    -- Show for any pet class (Hunter, Warlock, Death Knight)
    if not RC32_ClassGetsPetDialog() then return end
    -- Spec-change triggers are suppressed for 10s after login/reload/zone-in to
    -- avoid the game's own initialization spec events. A deliberate login trigger
    -- (fromLogin) is allowed through.
    if not fromLogin and (GetTime() - RC32_loginTime < 10) then return end
    RC32_specSwapPopup:Show()
    -- Auto-hide after 10 seconds if no response
    C_Timer.After(10, function()
        if RC32_specSwapPopup:IsShown() then
            RC32_specSwapPopup:Hide()
        end
    end)
end

function RC32_UpdatePetWarning()
    if RC32CharacterData and RC32CharacterData.petWarningEnabled == false then
        RC32_petWarning:Hide()
        RC32_petWarningAnim:Stop()
        return
    end
    -- Show for auto-pet classes (Hunter, Warlock) OR if user manually enabled
    local isPetClass = RC32_IsPetClass()
    local manuallyEnabled = RC32CharacterData and RC32CharacterData.petWarningEnabled == true and not isPetClass
    if not isPetClass and not manuallyEnabled then
        RC32_petWarning:Hide()
        RC32_petWarningAnim:Stop()
        return
    end
    if UnitExists("pet") or IsMounted() then
        RC32_petWarning:Hide()
        RC32_petWarningAnim:Stop()
    else
        -- Build label based on class
        local label = "⚠ No Pet!"
        if RC32className == "Hunter" then label = "⚠ Summon your pet!"
        elseif RC32className == "Warlock" then label = "⚠ Summon your demon!"
        elseif RC32className == "Deathknight" or RC32className == "Death Knight" or RC32className == "DEATHKNIGHT" then
            label = "⚠ Raise Dead!"
        end
        RC32_petWarningText:SetText(label)
        RC32_petWarning:Show()
        RC32_petWarningAnim:Play()
    end
end


local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterEvent("PLAYER_ALIVE")
if RC32_IS_MOP_OR_LATER then
	pcall(function() eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") end)
	pcall(function() eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED") end)
	pcall(function() eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE") end)
end
if RC32className == "Druid" then
	eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
end

local flagHide_PetFrame = false
function eventFrame:OnEvent(event,arg1,arg2)
	if event == "ADDON_LOADED" then
		checkDefaultsFromMemory()
		handlePlayerFrame(RC32CharacterData.defaultPlayerFrame.show)
		updateColorsFromMemory()
		UpdateOrbTextures()
		-- Health orb color is already set by updateColorsFromMemory() using class color
		local colorTable
		if RC32className == "Druid" then
			checkShapeShiftInfo()
		else
			RC32UpdateOrbColor(manaOrb,RC32CharacterData.manaOrb.orbColor,RC32CharacterData.manaOrb.galaxy,RC32CharacterData.manaOrb.font1,RC32CharacterData.manaOrb.font2)
		end
		-- Load saved menu background (also sets border color)
		if RC32AccountData and RC32AccountData.menuBackground then
			RC32_SetMenuBackground(RC32AccountData.menuBackground)
		else
			RC32_SetMenuBackground(1) -- Default to Chicken with white border
		end
		RC32GUI:Hide()
			-- Refresh DoT tracker positions from saved data
			if RC32_RefreshDotPositions then RC32_RefreshDotPositions() end
			-- Refresh Battle Rez panel position from saved data
			if RC32_RefreshBattleRezPos then RC32_RefreshBattleRezPos() end
			if RC32_RelayoutBattleRez then RC32_RelayoutBattleRez() end
			-- Show welcome popup after a short delay (to ensure UI is ready)
			C_Timer.After(1.5, function()
				RC32_ShowWelcomePopupOnLogin()
			end)
	elseif event == "VARIABLES_LOADED" then
		RC32MiniMapButtonPosition_LoadFromDefaults()
	elseif event == "UNIT_ENTERED_VEHICLE" then
		if arg1 == "player" then
			vehicleInUse = 1
			previousPowerValue = 0
			previousHealthValue = 0
		end
	elseif event == "UNIT_EXITED_VEHICLE" then
		if arg1 == "player" then
			vehicleInUse = 0
			previousHealthValue = 0
			previousPowerValue = 0
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if RC32CharacterData.combat.enabled then
			RC32UpdateOrbColor(healthOrb,RC32CharacterData.combat.orbColor,RC32CharacterData.combat.galaxy,RC32CharacterData.combat.font1,RC32CharacterData.combat.font2)
			local cr, cg, cb, ca = safeColor(RC32CharacterData.combat.orbColor)
			petOrb.filling1:SetVertexColor(cr, cg, cb, 1)
			-- Power tracker stays class color (no change)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if RC32CharacterData.combat.enabled then
			-- Use saved color for health orb when out of combat
			RC32UpdateOrbColor(healthOrb, RC32CharacterData.healthOrb.orbColor, RC32CharacterData.healthOrb.galaxy, RC32CharacterData.healthOrb.font1, RC32CharacterData.healthOrb.font2)
			local hr, hg, hb, ha = safeColor(RC32CharacterData.healthOrb.orbColor)
			petOrb.filling1:SetVertexColor(hr, hg, hb, 1)
			-- Power tracker stays class color (no change needed)
		end
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		checkShapeShiftInfo()
	elseif event == "UNIT_PET" then
		local name,realm = UnitName("pet")
		if not name then
			petOrb:SetScript("OnUpdate",nil)
		else
			petOrb:SetScript("OnUpdate",updatePetValues)
			previousPetHealth = RC32_Readable(UnitHealth("pet"), 0)
			previousPetPower = RC32_Readable(UnitPower("pet"), 0)
		end
		RC32_UpdatePetWarning()
	elseif event == "PLAYER_ENTERING_WORLD" then
		RC32_loginTime = GetTime()
		RC32_UpdatePetWarning()
		-- Detect a real login/reload (not every zone change) so the DK Yes/No
		-- dialog only appears at login. arg1 = isInitialLogin, arg2 = isReloadingUi.
		local isInitialLogin, isReloadingUi = arg1, arg2
		local isStartup
		if isInitialLogin == nil and isReloadingUi == nil then
			isStartup = not RC32_specPopupDidStartup
		else
			isStartup = (isInitialLogin == true) or (isReloadingUi == true)
		end
		if isStartup then RC32_specPopupDidStartup = true end
		C_Timer.After(3, function()
			RC32_UpdatePetWarning()
			-- Show the Yes/No dialog at login (DK-only guard is inside the function).
			if isStartup then RC32_ShowSpecSwapPopup(true) end
		end)
	elseif event == "PLAYER_ALIVE" then
		RC32_UpdatePetWarning()
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
		-- Real spec swap: refresh banner AND offer the Yes/No dialog.
		RC32_UpdatePetWarning()
		RC32_ShowSpecSwapPopup()
	elseif event == "PLAYER_TALENT_UPDATE" then
		-- Talent tweak is not a spec swap: refresh the banner only, no dialog.
		RC32_UpdatePetWarning()
	elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
		RC32_UpdatePetWarning()
	end
end

eventFrame:SetScript("OnEvent",eventFrame.OnEvent)

--slash command method	
local function CommandFunc(cmd)
	if cmd == "disable" then
		healthOrb:SetScript("OnUpdate",nil)
		manaOrb:SetScript("OnUpdate",nil)
		healthOrb:Hide()
		manaOrb:Hide()
	elseif cmd == "enable" then
		healthOrb:SetScript("OnUpdate",monitorHealth)
		manaOrb:SetScript("OnUpdate",monitorPower)
		healthOrb:Show()
		manaOrb:Show()
	elseif cmd == "help" then
		
	else
		Handle_RC32GUI()
	end
end

--setup the slash command stuff, hide the GUI
SlashCmdList["RCM"] = CommandFunc;
SLASH_RCM1 = "/rcm";
