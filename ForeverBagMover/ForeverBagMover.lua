-- Forever Bag Mover v1.1
-- Adds a grab bar along the top of every bag window. Drag the bar to move the bag.
-- Positions are saved and restored every time the bags open.
--
-- /bagmover          show help / confirm the addon is loaded
-- /bagmover lock     hide the grab bars, bags stay put
-- /bagmover unlock   show the grab bars again
-- /bagmover reset    forget saved positions

local ADDON_NAME = ...
local DB
local handles = {}
local pendingApply = false

local function Print(msg)
    print("|cff33ff99Bag Mover:|r " .. msg)
end

local function CantTouch(frame)
    return InCombatLockdown() and frame:IsProtected()
end

local function ForEachBagFrame(fn)
    if ContainerFrameCombinedBags then
        fn(ContainerFrameCombinedBags)
    end
    local count = NUM_CONTAINER_FRAMES or 13
    for i = 1, count do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            fn(frame)
        end
    end
end

local function SavePosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    DB.positions[frame:GetName()] = { "TOPLEFT", "BOTTOMLEFT", left * scale, top * scale }
end

local function ApplyPosition(frame)
    if frame.bagMoverDragging then return end
    local pos = DB and DB.positions[frame:GetName()]
    if not pos then return end
    if CantTouch(frame) then
        pendingApply = true
        return
    end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3] / scale, pos[4] / scale)
end

local function ApplyAll()
    ForEachBagFrame(function(frame)
        if frame:IsShown() then
            ApplyPosition(frame)
        end
    end)
end

local function UpdateHandleVisibility()
    for _, handle in pairs(handles) do
        if DB.locked then handle:Hide() else handle:Show() end
    end
end

local function SetupFrame(frame)
    if handles[frame] or CantTouch(frame) then return end

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- A grab bar across the top of the bag, above the item slots.
    local handle = CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, 0) -- leave the close button clickable
    handle:SetHeight(26)
    handle:SetFrameLevel(frame:GetFrameLevel() + 20)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")

    local glow = handle:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetColorTexture(0.2, 1, 0.6, 0.25)
    glow:Hide()

    handle:SetScript("OnEnter", function(self)
        glow:Show()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to move bag")
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function()
        glow:Hide()
        GameTooltip:Hide()
    end)

    handle:SetScript("OnDragStart", function()
        if DB.locked or CantTouch(frame) then return end
        frame.bagMoverDragging = true
        frame:StartMoving()
    end)

    handle:SetScript("OnDragStop", function()
        if not frame.bagMoverDragging then return end
        frame:StopMovingOrSizing()
        frame.bagMoverDragging = nil
        frame:SetUserPlaced(false)
        SavePosition(frame)
        ApplyPosition(frame)
    end)

    handles[frame] = handle
    if DB.locked then handle:Hide() end

    -- Blizzard re-lays out bags when they open; put ours back right after.
    frame:HookScript("OnShow", function(self)
        ApplyPosition(self)
        C_Timer.After(0, function() ApplyPosition(self) end)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ForeverBagMoverDB = ForeverBagMoverDB or {}
        DB = ForeverBagMoverDB
        DB.positions = DB.positions or {}
        if DB.locked == nil then DB.locked = false end

    elseif event == "PLAYER_LOGIN" then
        ForEachBagFrame(SetupFrame)
        if type(UpdateContainerFrameAnchors) == "function" then
            hooksecurefunc("UpdateContainerFrameAnchors", ApplyAll)
        end
        Print("loaded. Open your bags and drag the bar along the top. /bagmover for options.")

    elseif event == "PLAYER_REGEN_ENABLED" then
        ForEachBagFrame(SetupFrame)
        if pendingApply then
            pendingApply = false
            ApplyAll()
        end
    end
end)

SLASH_FOREVERBAGMOVER1 = "/bagmover"
SLASH_FOREVERBAGMOVER2 = "/bm"
SlashCmdList.FOREVERBAGMOVER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "lock" then
        DB.locked = true
        UpdateHandleVisibility()
        Print("bags locked.")
    elseif msg == "unlock" then
        DB.locked = false
        UpdateHandleVisibility()
        Print("bags unlocked - drag the bar along the top of a bag.")
    elseif msg == "reset" then
        wipe(DB.positions)
        CloseAllBags()
        Print("positions reset. Reopen your bags to see the default layout.")
    else
        Print("drag the bar along the top of a bag to move it" .. (DB.locked and " (currently LOCKED)." or "."))
        Print("/bagmover lock | unlock | reset")
    end
end
