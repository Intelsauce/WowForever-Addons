-- Goldsight: collecting auction and vendor prices.
--
-- Auction prices come from (best first):
--   1. Goldsight's own full scan of the auction house (once every 15 minutes)
--   2. Anything you search or browse at the auction house
--   3. Other price addons if installed: auxForever, Auctionator, TradeSkillMaster

local _, ns = ...

local FULL_SCAN_COOLDOWN = 15 * 60
local STALE_OWN = 3 * 86400 -- own data older than this: prefer another addon's price if there is one

------------------------------------------------------------------------
-- Storing prices
------------------------------------------------------------------------
local function Store(itemID, market, lowest, qty, listings, source)
    if not itemID or not market or market <= 0 then return end
    local db = ns.db
    local rec = db.prices[itemID] or {}
    rec.m, rec.lo, rec.q, rec.l, rec.t, rec.s = market, lowest or market, qty, listings, time(), source
    ns.AddHistory(rec, ns.Day(time()), market, 14)
    db.prices[itemID] = rec
end
ns.StorePrice = Store

local function OwnName()
    return UnitName("player")
end

------------------------------------------------------------------------
-- Full scan (C_AuctionHouse.ReplicateItems)
------------------------------------------------------------------------
local scan = { state = "idle" }
ns.scan = scan

function ns.FullScanWait()
    local last = ns.db and ns.db.lastFullScan or 0
    return math.max(0, FULL_SCAN_COOLDOWN - (time() - last))
end

function ns.StartFullScan()
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
        ns.Print("full scans aren't available on this client.")
        return
    end
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        ns.Print("open the auction house first.")
        return
    end
    if scan.state ~= "idle" then
        ns.Print("a scan is already running.")
        return
    end
    local wait = ns.FullScanWait()
    if wait > 0 then
        ns.Print(string.format("the game allows one full scan every 15 minutes. Next one in %d:%02d.", wait / 60, wait % 60))
        return
    end
    scan.state = "waiting"
    scan.started = time()
    ns.db.lastFullScan = time()
    C_AuctionHouse.ReplicateItems()
    ns.Print("full scan started. The game may pause for a moment while it downloads every auction.")
    if ns.RefreshAHPanel then ns.RefreshAHPanel() end
end

local function FinishScan(agg)
    local items = 0
    for itemID, listings in pairs(agg) do
        local market, lowest, qty, n = ns.MarketFromListings(listings)
        Store(itemID, market, lowest, qty, n, "scan")
        items = items + 1
    end
    scan.state = "idle"
    ns.db.lastFullScanItems = items
    ns.Print(string.format("full scan done: priced %d items.", items))
    if ns.RefreshAll then ns.RefreshAll() end
end

local function ProcessReplicate()
    if scan.state ~= "waiting" then return end
    scan.state = "reading"
    local total = C_AuctionHouse.GetNumReplicateItems() or 0
    local me = OwnName()
    local agg, i = {}, 0
    local function step()
        local stop = math.min(total - 1, i + 1500)
        for k = i, stop do
            local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID =
                pcall(C_AuctionHouse.GetReplicateItemInfo, k)
            if ok and itemID and buyout and buyout > 0 and count and count > 0 and owner ~= me then
                local t = agg[itemID]
                if not t then t = {}; agg[itemID] = t end
                t[#t + 1] = { unit = buyout / count, qty = count }
            end
        end
        i = stop + 1
        if ns.RefreshAHPanel then ns.RefreshAHPanel(i, total) end
        if i < total then
            C_Timer.After(0, step)
        else
            FinishScan(agg)
        end
    end
    if total == 0 then
        scan.state = "idle"
        ns.Print("the scan came back empty. Try again in 15 minutes.")
        return
    end
    step()
end
ns.On("REPLICATE_ITEM_LIST_UPDATE", ProcessReplicate)
ns.On("AUCTION_HOUSE_CLOSED", function()
    if scan.state ~= "idle" then scan.state = "idle" end
end)

------------------------------------------------------------------------
-- Prices picked up while you browse and search
------------------------------------------------------------------------
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    local results = C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults() or {}
    for _, r in ipairs(results) do
        local id = r.itemKey and r.itemKey.itemID
        local rec = id and ns.db.prices[id]
        -- a fresh full-scan price is better than a browse minimum
        if id and r.minPrice and r.minPrice > 0 and not (rec and rec.s == "scan" and time() - rec.t < 3600) then
            Store(id, r.minPrice, r.minPrice, r.totalQuantity, nil, "browse")
        end
    end
end)

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    local listings = {}
    for i = 1, n do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.quantity and not r.containsOwnerItem then
            listings[#listings + 1] = { unit = r.unitPrice, qty = r.quantity }
        end
    end
    if #listings > 0 then
        local market, lowest, qty, count = ns.MarketFromListings(listings)
        Store(itemID, market, lowest, qty, count, "search")
        if ns.RefreshAll then ns.RefreshAll() end
    end
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if not itemKey or not itemKey.itemID then return end
    local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
    local listings = {}
    for i = 1, n do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
            listings[#listings + 1] = { unit = r.buyoutAmount / math.max(1, r.quantity or 1), qty = r.quantity or 1 }
        end
    end
    if #listings > 0 then
        local market, lowest, qty, count = ns.MarketFromListings(listings)
        Store(itemKey.itemID, market, lowest, qty, count, "search")
        if ns.RefreshAll then ns.RefreshAll() end
    end
end)

------------------------------------------------------------------------
-- Other addons' prices (used when Goldsight has none, or only old ones)
------------------------------------------------------------------------
local function OtherAddonPrice(itemID, link)
    local function num(ok, v) if ok and type(v) == "number" and v > 0 then return v end end
    if AuxForeverAPI then
        local v = num(pcall(AuxForeverAPI.GetLatestPrice, itemID)) or (link and num(pcall(AuxForeverAPI.GetLatestPrice, link)))
        if v then
            local usual = AuxForeverAPI.GetUsualPrice and (num(pcall(AuxForeverAPI.GetUsualPrice, itemID)) or
                (link and num(pcall(AuxForeverAPI.GetUsualPrice, link))))
            return v, "auxForever", usual
        end
    end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local v = num(pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "Goldsight", itemID))
        if v then return v, "Auctionator" end
    end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local v = num(pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", "i:" .. itemID))
        if v then return v, "TSM" end
    end
end

-- Returns a price table for ns.Decide, or nil
function ns.GetPrice(itemID, link)
    if not itemID or not ns.db then return nil end
    local rec = ns.db.prices[itemID]
    local today = ns.Day(time())
    if rec and (time() - rec.t) < STALE_OWN then
        local usual = ns.Usual(rec, today)
        return { market = rec.m, lowest = rec.lo, listings = rec.l, qty = rec.q, age = time() - rec.t,
                 usual = usual, source = rec.s, time = rec.t }
    end
    local v, src, usual = OtherAddonPrice(itemID, link)
    if v then
        return { market = v, lowest = v, age = 0, usual = usual, source = src }
    end
    if rec then
        return { market = rec.m, lowest = rec.lo, listings = rec.l, qty = rec.q, age = time() - rec.t,
                 usual = ns.Usual(rec, today), source = rec.s, time = rec.t }
    end
end

------------------------------------------------------------------------
-- Vendor prices
------------------------------------------------------------------------
function ns.VendorPrice(itemID)
    local info = ns.ItemInfo(itemID)
    if info and info.sellPrice and info.sellPrice > 0 then return info.sellPrice end
    local learned = ns.db and ns.db.vendor[itemID]
    if learned then return learned end
    return nil -- unknown (Forever sometimes reports 0 until you visit a vendor)
end

-- At a merchant, the tooltip for each bag item carries the real sell price.
local function LearnVendorPricesFromBags()
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem and C_Container) then return end
    local sellType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not ns.db.vendor[info.itemID] then
                local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
                if ok and data and data.lines then
                    for _, line in ipairs(data.lines) do
                        local price = line.price or (line.args and line.args.price)
                        if price and price > 0 and (not sellType or line.type == sellType) then
                            ns.db.vendor[info.itemID] = math.floor(price / math.max(1, info.stackCount or 1) + 0.5)
                            break
                        end
                    end
                end
            end
        end
    end
end
ns.On("MERCHANT_SHOW", function() pcall(LearnVendorPricesFromBags) end)
