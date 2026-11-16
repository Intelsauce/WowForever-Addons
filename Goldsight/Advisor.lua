-- Goldsight: price math and the vendor-vs-auction decision.
-- Pure Lua, no game calls, so it can be tested outside WoW.

local _, ns = ...
ns = ns or {}
GoldsightNS = ns

------------------------------------------------------------------------
-- Money
------------------------------------------------------------------------
function ns.MoneyText(copper, plain)
    copper = math.floor((copper or 0) + 0.5)
    local neg = copper < 0
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if plain then
        if g > 0 then parts[#parts + 1] = g .. "g" end
        if s > 0 then parts[#parts + 1] = s .. "s" end
        if c > 0 or (g == 0 and s == 0) then parts[#parts + 1] = c .. "c" end
    else
        if g > 0 then parts[#parts + 1] = "|cffffd700" .. g .. "g|r" end
        if s > 0 then parts[#parts + 1] = "|cffc7c7cf" .. s .. "s|r" end
        if g == 0 and (c > 0 or s == 0) then parts[#parts + 1] = "|cffeda55f" .. c .. "c|r" end
    end
    return (neg and "-" or "") .. table.concat(parts, " ")
end

------------------------------------------------------------------------
-- Market price from a list of listings: { { unit = copper each, qty = n }, ... }
-- Uses the middle price of the cheapest 15% of units, so one odd cheap
-- listing doesn't set the price, but the price still reflects what you
-- would have to undercut.
-- Returns market, lowest, totalQuantity, numberOfListings
------------------------------------------------------------------------
function ns.MarketFromListings(listings)
    if not listings or #listings == 0 then return nil end
    table.sort(listings, function(a, b) return a.unit < b.unit end)
    local total = 0
    for _, l in ipairs(listings) do total = total + l.qty end
    local lowest = listings[1].unit
    if #listings <= 2 then return lowest, lowest, total, #listings end
    local slice = math.max(1, math.floor(total * 0.15 + 0.5))
    local target = slice / 2
    local seen = 0
    for _, l in ipairs(listings) do
        seen = seen + l.qty
        if seen >= target then
            return math.floor(l.unit + 0.5), lowest, total, #listings
        end
    end
    return lowest, lowest, total, #listings
end

------------------------------------------------------------------------
-- Daily history: rec.h = { [dayNumber] = market }
------------------------------------------------------------------------
function ns.Day(t) return math.floor(t / 86400) end

function ns.AddHistory(rec, day, market, keepDays)
    rec.h = rec.h or {}
    local old = rec.h[day]
    -- keep the lower of the day's readings: a fair "what it really sells for"
    if not old or market < old then rec.h[day] = market end
    keepDays = keepDays or 14
    for d in pairs(rec.h) do
        if d < day - keepDays then rec.h[d] = nil end
    end
end

-- The usual price: median of earlier days (today excluded so "now" can be
-- compared with it). Needs at least 2 earlier days.
function ns.Usual(rec, today)
    if not rec or not rec.h then return nil, 0 end
    local vals = {}
    for d, v in pairs(rec.h) do
        if d < today then vals[#vals + 1] = v end
    end
    if #vals < 2 then return nil, #vals end
    table.sort(vals)
    local mid = (#vals + 1) / 2
    local lo, hi = vals[math.floor(mid)], vals[math.ceil(mid)]
    return math.floor((lo + hi) / 2 + 0.5), #vals
end

------------------------------------------------------------------------
-- The decision
--
-- item  = { vendor = copper each or nil (unknown), count = n, bound = bool,
--           noValue = bool, stackable = bool, quality = 0..7 }
-- price = { market, lowest, listings, qty, age (seconds), usual, source } or nil
-- opt   = { cut = 0.05, minMargin = 0.10, minProfit = 100,
--           depositRate = 0.15, durationHours = 24 }
--
-- Returns { action = "vendor" | "auction" | "hold" | "none",
--           vendorTotal, auctionTotal, gain, sellChance, timing, reason, confidence }
------------------------------------------------------------------------
local DEFAULTS = { cut = 0.05, minMargin = 0.10, minProfit = 100, depositRate = 0.15, durationHours = 24 }

function ns.Decide(item, price, opt)
    opt = opt or DEFAULTS
    for k, v in pairs(DEFAULTS) do if opt[k] == nil then opt[k] = v end end
    local count = item.count or 1
    local V = item.vendor
    local r = { count = count }
    r.vendorTotal = (V or 0) * count

    if item.noValue and not price then
        r.action, r.reason = "none", "Can't be sold to a vendor."
        return r
    end
    if item.bound then
        if (V or 0) > 0 then
            r.action, r.reason = "vendor", "Soulbound, so it can't go on the auction house."
        else
            r.action, r.reason = "none", "Soulbound and worthless to vendors."
        end
        return r
    end
    if not price or not price.market or price.market <= 0 then
        if (V or 0) > 0 then
            r.action, r.reason = "vendor", "No auction price yet. Scan the auction house to compare."
            r.confidence = "low"
        else
            r.action, r.reason = "none", "No price known yet. Scan the auction house."
        end
        return r
    end

    -- chance an auction actually sells
    local p = item.stackable and 0.85 or 0.6
    if price.listings and not item.stackable and price.listings > 40 then p = p - 0.15 end -- crowded market
    if price.usual then p = p + 0.05 end                                                    -- sells regularly
    if (price.age or 0) > 86400 then p = p - 0.1 end                                        -- old data
    p = math.max(0.2, math.min(0.95, p))
    r.sellChance = p

    local deposit = (V or 0) * opt.depositRate * (opt.durationHours / 12)
    local net = price.market * (1 - opt.cut)
    -- sold: you get the price minus the cut (deposit refunded)
    -- not sold: the deposit is gone, but the item comes back and can still be vendored
    local expectedEach = p * net + (1 - p) * ((V or 0) - deposit)
    r.auctionEach = expectedEach
    r.auctionTotal = expectedEach * count
    r.gain = r.auctionTotal - r.vendorTotal
    r.confidence = ((price.age or 0) > 86400 or not price.listings) and "low" or "good"

    local beatsVendor = expectedEach >= (V or 0) * (1 + opt.minMargin) and r.gain >= opt.minProfit
    if not beatsVendor then
        r.action = "vendor"
        if V == nil then
            r.reason = "Vendor price unknown and the auction value is tiny."
        else
            r.reason = "The vendor pays about as much, with no deposit or waiting."
        end
        return r
    end

    r.action = "auction"
    r.reason = "Worth more on the auction house after the 5% cut."
    if V == nil then r.reason = r.reason .. " (Vendor price not known yet.)" end

    -- timing: compare now with the usual price
    if price.usual and price.usual > 0 then
        local ratio = price.market / price.usual
        r.ratio = ratio
        if ratio < 0.8 then
            local usualNet = price.usual * (1 - opt.cut)
            r.action = "hold"
            r.timing = "low"
            r.reason = string.format("Price is %d%% below usual right now. Hold it, or list near the usual %s.",
                math.floor((1 - ratio) * 100 + 0.5), ns.MoneyText(price.usual, true))
            r.holdGain = (p * usualNet + (1 - p) * ((V or 0) - deposit)) * count - r.vendorTotal
        elseif ratio > 1.2 then
            r.timing = "high"
            r.reason = string.format("Price is %d%% above usual: a good time to sell.", math.floor((ratio - 1) * 100 + 0.5))
        end
    end
    return r
end

ns.DEFAULT_OPTIONS = DEFAULTS
