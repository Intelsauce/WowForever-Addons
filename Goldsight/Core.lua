-- Goldsight: saved data, settings, events and small helpers.

local ADDON_NAME, ns = ...
GoldsightNS = ns
ns.ADDON = ADDON_NAME
ns.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"

local DEFAULTS = {
    cut = 0.05,             -- auction house cut
    minMargin = 0.10,       -- auction must beat vendor by 10%...
    minProfit = 500,        -- ...and by at least 5 silver per stack
    depositRate = 0.15,     -- deposit: 15% of vendor value per 12 hours
    durationHours = 24,
    sellMaxQuality = 2,     -- "Sell vendor items" sells up to green quality
    alertThreshold = 10000, -- chat alert for drops worth 1 gold or more
    tooltip = true,
    lootAlerts = true,
}

function ns.Print(msg)
    print("|cffffd700Goldsight:|r " .. msg)
end

function ns.Money(copper)
    return ns.MoneyText(copper)
end

function ns.Options()
    return ns.db.opt
end

-- Item info helpers (work on both the current and older client APIs)
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
function ns.ItemInfo(item)
    if not item then return end
    local ok, name, link, quality, _, _, _, _, maxStack, equipLoc, icon, sellPrice, classID, _, bindType =
        pcall(GetInfo, item)
    if not ok or not name then return end
    return { name = name, link = link, quality = quality, maxStack = maxStack or 1, equipLoc = equipLoc,
             icon = icon, sellPrice = sellPrice, classID = classID, bindType = bindType }
end

function ns.ItemID(link)
    if type(link) == "number" then return link end
    if type(link) ~= "string" then return end
    return tonumber(link:match("item:(%d+)"))
end

-- Event hub ---------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.Print("|cffff6060error|r in " .. event .. ": " .. tostring(err)) end
    end
end)

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    GoldsightDB = GoldsightDB or {}
    local db = GoldsightDB
    db.prices = db.prices or {}   -- [itemID] = { m = market, lo = lowest, q = qty, l = listings, t = time, s = source, h = history }
    db.vendor = db.vendor or {}   -- [itemID] = vendor price learned at a merchant
    db.ignore = db.ignore or {}   -- [itemID] = true: never sell / never advise
    db.opt = db.opt or {}
    for k, v in pairs(DEFAULTS) do
        if db.opt[k] == nil then db.opt[k] = v end
    end
    db.minimap = db.minimap or { angle = 150, hide = false }
    -- 1.0/1.1 put the button at 200 degrees, right on top of Snapcast's: move it once
    if not db.minimap.moved and db.minimap.angle == 200 then db.minimap.angle = 150 end
    db.minimap.moved = true
    ns.db = db
    if ns.OnLoaded then ns.OnLoaded() end
end)
