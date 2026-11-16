-- Goldsight: your bags, selling to vendors, loot tracking and tooltips.

local _, ns = ...

------------------------------------------------------------------------
-- Valuing one item
------------------------------------------------------------------------
-- item: itemID or link; count; bound (optional); noValue (optional)
function ns.Value(itemID, link, count, bound, noValue)
    local info = ns.ItemInfo(link or itemID)
    local price = ns.GetPrice(itemID, link)
    local vendor = ns.VendorPrice(itemID)
    if noValue then vendor = 0 end
    local verdict = ns.Decide({
        vendor = vendor, count = count or 1, bound = bound, noValue = noValue,
        stackable = info and (info.maxStack or 1) > 1, quality = info and info.quality,
    }, price, ns.db.opt)
    verdict.price, verdict.vendor, verdict.info = price, vendor, info
    -- the most you can expect to get for it
    if verdict.action == "auction" or verdict.action == "hold" then
        verdict.best = verdict.auctionTotal
    else
        verdict.best = verdict.vendorTotal
    end
    return verdict
end

------------------------------------------------------------------------
-- Bags
------------------------------------------------------------------------
local function LastBag()
    return (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + ((NUM_TOTAL_EQUIPPED_BAG_SLOTS and 0) or 1)
end

-- Returns a list of grouped entries:
-- { itemID, link, name, icon, quality, count, slots = { {bag, slot, count}, ... }, verdict }
function ns.ScanBags()
    local groups, order = {}, {}
    if not C_Container then return order end
    for bag = 0, LastBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local it = C_Container.GetContainerItemInfo(bag, slot)
            if it and it.itemID then
                local key = it.itemID .. (it.isBound and ":b" or "")
                local g = groups[key]
                if not g then
                    g = { itemID = it.itemID, link = it.hyperlink, icon = it.iconFileID, quality = it.quality,
                          bound = it.isBound, noValue = it.hasNoValue, count = 0, slots = {} }
                    groups[key] = g
                    order[#order + 1] = g
                end
                g.count = g.count + (it.stackCount or 1)
                g.slots[#g.slots + 1] = { bag = bag, slot = slot, count = it.stackCount or 1 }
            end
        end
    end
    for _, g in ipairs(order) do
        local info = ns.ItemInfo(g.link or g.itemID)
        if not info and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, g.itemID) end
        g.name = info and info.name or (g.link and g.link:match("%[(.-)%]")) or ("item " .. g.itemID)
        g.ignored = ns.db.ignore[g.itemID] and true or false
        g.verdict = ns.Value(g.itemID, g.link, g.count, g.bound, g.noValue)
    end
    return order
end

------------------------------------------------------------------------
-- Selling to a vendor: 12 per click, so everything stays in your buyback tab
------------------------------------------------------------------------
ns.atMerchant = false
ns.On("MERCHANT_SHOW", function() ns.atMerchant = true; if ns.RefreshAll then ns.RefreshAll() end end)
ns.On("MERCHANT_CLOSED", function() ns.atMerchant = false; if ns.RefreshAll then ns.RefreshAll() end end)

local function InEquipmentSet(bag, slot)
    if C_Container and C_Container.GetContainerItemEquipmentSetInfo then
        local ok, inSet = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
        return ok and inSet
    end
    return false
end

-- The items "Sell vendor items" would sell
function ns.VendorList(entries)
    local list = {}
    local maxQ = ns.db.opt.sellMaxQuality
    for _, g in ipairs(entries or ns.ScanBags()) do
        local v = g.verdict
        if v.action == "vendor" and not g.ignored and (v.vendor or 0) > 0 and (g.quality or 0) <= maxQ then
            list[#list + 1] = g
        end
    end
    return list
end

local pendingSale -- { [itemID] = { count, money before } } to learn real vendor prices
function ns.SellVendorItems()
    if not ns.atMerchant then
        ns.Print("open a vendor first.")
        return
    end
    if InCombatLockdown() then return end
    local sold, money = 0, 0
    for _, g in ipairs(ns.VendorList()) do
        for _, s in ipairs(g.slots) do
            if sold >= 12 then break end
            if not InEquipmentSet(s.bag, s.slot) then
                local now = C_Container.GetContainerItemInfo(s.bag, s.slot)
                if now and now.itemID == g.itemID then -- still the same item
                    C_Container.UseContainerItem(s.bag, s.slot)
                    sold = sold + 1
                    money = money + (g.verdict.vendor or 0) * (now.stackCount or 1)
                end
            end
        end
        if sold >= 12 then break end
    end
    if sold == 0 then
        ns.Print("nothing to sell.")
    else
        local left = #ns.VendorList() > 0
        ns.Print(string.format("sold %d stack(s) for about %s.%s", sold, ns.Money(money),
            left and " Click again for the next batch." or ""))
        ns.session.vendored = (ns.session.vendored or 0) + money
    end
    C_Timer.After(0.6, function() if ns.RefreshAll then ns.RefreshAll() end end)
end

------------------------------------------------------------------------
-- Loot tracking (this session)
------------------------------------------------------------------------
ns.session = { start = time(), items = {}, order = {}, gold = 0, value = 0 }

function ns.ResetSession()
    ns.session = { start = time(), items = {}, order = {}, gold = 0, value = 0 }
    if ns.RefreshAll then ns.RefreshAll() end
end

local lootCache, moneyBefore = {}, nil

local function Record(link, qty)
    local itemID = ns.ItemID(link)
    if not itemID then return end
    qty = math.max(1, qty or 1)
    local s = ns.session
    local e = s.items[itemID]
    if not e then
        e = { itemID = itemID, link = link, count = 0, value = 0 }
        s.items[itemID] = e
        s.order[#s.order + 1] = e
    end
    local v = ns.Value(itemID, link, qty)
    e.count = e.count + qty
    e.value = e.value + (v.best or 0)
    e.vendor = (e.vendor or 0) + (v.vendorTotal or 0)
    s.vendorValue = (s.vendorValue or 0) + (v.vendorTotal or 0)
    e.action = v.action
    s.value = s.value + (v.best or 0)
    local o = ns.db.opt
    if o.lootAlerts and (v.best or 0) >= o.alertThreshold then
        local where = (v.action == "auction" or v.action == "hold") and "on the auction house" or "at a vendor"
        ns.Print(string.format("%s%s is worth %s %s.", link, qty > 1 and ("x" .. qty) or "", ns.Money(v.best), where))
    end
    if ns.RefreshAll then ns.RefreshAll() end
end

ns.On("LOOT_READY", function()
    wipe(lootCache)
    moneyBefore = GetMoney()
    for i = 1, GetNumLootItems() do
        local ok, link = pcall(GetLootSlotLink, i)
        if ok and type(link) == "string" then
            local _, _, qty = GetLootSlotInfo(i)
            lootCache[i] = { link = link, qty = qty }
        end
    end
end)
ns.On("LOOT_SLOT_CLEARED", function(slot)
    local c = lootCache[slot]
    if c then
        lootCache[slot] = nil
        Record(c.link, c.qty)
    end
end)
ns.On("LOOT_CLOSED", function()
    if moneyBefore then
        local diff = GetMoney() - moneyBefore
        if diff > 0 then ns.session.gold = ns.session.gold + diff end
        moneyBefore = nil
        if ns.RefreshAll then ns.RefreshAll() end
    end
end)

function ns.SessionStats()
    local s = ns.session
    local hours = math.max(1 / 60, (time() - s.start) / 3600)
    local total = s.gold + s.value
    return { minutes = math.floor((time() - s.start) / 60), gold = s.gold, items = s.value, vendor = s.vendorValue or 0,
             total = total, perHour = total / hours }
end

------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------
local ACTION_TEXT = {
    auction = "|cff40ff40Auction it|r",
    hold = "|cffffd040Auction, but hold|r",
    vendor = "|cffc0c0c0Sell to vendor|r",
    none = "|cff808080No value|r",
}
ns.ACTION_TEXT = ACTION_TEXT

local function Ago(sec)
    if not sec then return "" end
    if sec < 3600 then return math.floor(sec / 60) .. "m ago" end
    if sec < 86400 then return math.floor(sec / 3600) .. "h ago" end
    return math.floor(sec / 86400) .. "d ago"
end
ns.Ago = Ago

local function AddLines(tt, itemID, link, count)
    if not ns.db or not ns.db.opt.tooltip or not itemID then return end
    local v = ns.Value(itemID, link, count or 1)
    if v.action == "none" and not v.price then return end
    tt:AddLine(" ")
    local left = "|cffffd700Goldsight|r  " .. (ACTION_TEXT[v.action] or "")
    if (count or 1) > 1 then left = left .. "  |cffaaaaaa(x" .. count .. ")|r" end
    if v.action == "auction" or v.action == "hold" then
        left = left .. "  |cff40ff40+" .. ns.Money(v.gain) .. "|r"
    end
    tt:AddLine(left)
    local vend = v.vendor and ns.Money(v.vendor) or "?"
    if v.vendor and (count or 1) > 1 then
        vend = vend .. " each |cffaaaaaa(x" .. count .. ": " .. ns.Money(v.vendor * count) .. ")|r"
    else
        vend = vend .. " each"
    end
    local ah = v.price and ns.Money(v.price.market) or "no data"
    tt:AddDoubleLine("Vendor " .. vend, "AH " .. ah .. " each", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    if v.price then
        local bits = {}
        if v.price.usual then bits[#bits + 1] = "usual " .. ns.Money(v.price.usual) end
        if v.price.listings then bits[#bits + 1] = v.price.listings .. " listed" end
        if v.price.source and v.price.source ~= "scan" and v.price.source ~= "search" and v.price.source ~= "browse" then
            bits[#bits + 1] = "from " .. v.price.source
        elseif v.price.age then
            bits[#bits + 1] = Ago(v.price.age)
        end
        tt:AddLine(table.concat(bits, " · "), 0.6, 0.6, 0.6)
    end
    if v.timing == "high" then
        tt:AddLine("Price is high right now: good time to sell.", 0.4, 1, 0.4, true)
    elseif v.action == "hold" then
        tt:AddLine(v.reason, 1, 0.82, 0.25, true)
    end
end

local function OnItemTooltip(tt, data)
    if tt ~= GameTooltip and tt ~= ItemRefTooltip and tt ~= ShoppingTooltip1 then
        -- other tooltips are fine too, but keep comparisons tidy
        if tt.GetName and tt:GetName() and tt:GetName():find("Shopping") then return end
    end
    local link
    if tt.GetItem then
        local ok, _, l = pcall(tt.GetItem, tt)
        if ok then link = l end
    end
    local itemID = (data and data.id) or ns.ItemID(link)
    if not itemID then return end
    -- judge the amount you actually carry, or a full stack if you have none,
    -- since the 'worth listing' rule is per stack
    local count = 1
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, n = pcall(getCount, itemID)
    if ok and type(n) == "number" and n > 0 then
        count = n
    else
        local info = ns.ItemInfo(itemID)
        if info and (info.maxStack or 1) > 1 then count = info.maxStack end
    end
    pcall(AddLines, tt, itemID, link, count)
end

ns.On("PLAYER_LOGIN", function()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) OnItemTooltip(tt, nil) end)
    end
end)
