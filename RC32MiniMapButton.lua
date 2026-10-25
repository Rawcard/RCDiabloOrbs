--Minimap stuff - will reorganize at a later time.
RC32FramesUnlocked = false
RC32MiniMapButtonPosition = {
	locationAngle = 45, --deg
	x = 52-(80*cos(45)),
	y = ((80*sin(45))-52)
}

-- Call this in a mod's initialization to move the minimap button to its saved position (also used in its movement)
-- ** do not call from the mod's OnLoad, VARIABLES_LOADED or later is fine. **
function RC32MiniMapButton_Reposition()
	RC32MiniMapButtonPosition.x = 52-(80*cos(RC32MiniMapButtonPosition.locationAngle))
	RC32MiniMapButtonPosition.y = ((80*sin(RC32MiniMapButtonPosition.locationAngle))-52)
	RC32MiniMapButton:SetPoint("TOPLEFT","Minimap","TOPLEFT",RC32MiniMapButtonPosition.x,RC32MiniMapButtonPosition.y)
end

function RC32MiniMapButtonPosition_LoadFromDefaults()
	RC32MiniMapButton:SetPoint("TOPLEFT","Minimap","TOPLEFT",RC32MiniMapButtonPosition.x,RC32MiniMapButtonPosition.y)
end
-- Only while the button is dragged this is called every frame
function RC32_Minimap_Update()

	local xpos,ypos = GetCursorPosition()
	local xmin,ymin = Minimap:GetLeft(), Minimap:GetBottom()

	xpos = xmin-xpos/UIParent:GetScale()+70 -- get coordinates as differences from the center of the minimap
	ypos = ypos/UIParent:GetScale()-ymin-70

	RC32MiniMapButtonPosition.locationAngle = math.deg(math.atan2(ypos,xpos)) -- save the degrees we are relative to the minimap center
	RC32MiniMapButton_Reposition() -- move the button
end

-- Put your code that you want on a minimap button click here.  arg1="LeftButton", "RightButton", etc
function RC32MiniMapButton_OnClick()
	Handle_RC32GUI()
end

function Handle_RC32GUI()
	if RC32GUI:IsVisible() then
		RC32GUI:Hide()
		PlaySound(830);  -- SPELLBOOKCLOSE
	else
		RC32GUI:Show()
		PlaySound(829);  -- SPELLBOOKOPEN
	end
end