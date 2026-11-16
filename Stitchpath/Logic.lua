-- Brewpath: the maths. No game calls, so it can be tested outside WoW.

local _, ns = ...
ns = ns or StitchpathNS

-- Chance a craft gives a skill point, by colour.
-- Orange always does; yellow usually; green rarely; grey never.
ns.CHANCE = { orange = 1.0, yellow = 0.75, green = 0.25, gray = 0 }
ns.COLOR_HEX = { orange = "ff8040", yellow = "ffff00", green = "40c040", gray = "808080" }

function ns.RouteStep(skill)
    for i, step in ipairs(ns.ROUTE) do
        if skill < step.to then return step, i end
    end
    return nil
end

function ns.RankFor(skill, maxSkill)
    -- the rank you have is the one whose cap equals your max skill
    for i, r in ipairs(ns.RANKS) do
        if r.cap == maxSkill then return r, ns.RANKS[i + 1] end
    end
    return nil, nil
end

-- Training advice: returns text or nil
function ns.TrainingAdvice(skill, maxSkill, playerLevel, faction)
    local _, nextRank = ns.RankFor(skill, maxSkill)
    if not nextRank then return nil end
    local where = nextRank.where[faction] or nextRank.where.Horde
    if skill >= maxSkill then
        local lvl = (playerLevel or 0) < nextRank.level and (" You need character level " .. nextRank.level .. " first.") or ""
        return "|cffff4040You're capped at " .. maxSkill .. ".|r Train " .. nextRank.name .. ": " .. where .. "." .. lvl, true
    elseif skill >= nextRank.trainAt then
        return "You can train " .. nextRank.name .. " now, before you hit the " .. maxSkill .. " cap: " .. where .. ".", false
    end
    return nil
end

-- Crafts needed to go from `skill` to `target` on one step, given the route's estimate
function ns.CraftsLeft(step, skill)
    if not step then return 0 end
    local span = step.to - step.from
    if span <= 0 then return 0 end
    local left = math.max(0, step.to - math.max(skill, step.from))
    return math.ceil(step.crafts * left / span)
end

-- Shopping list from `skill` up to `target` along the route.
-- have(itemID) -> count in bags; price(itemID) -> copper or nil
-- Returns list of { itemID, need, have, buy, price, cost } and the total cost
function ns.ShoppingList(skill, target, have, price)
    local need, produced = {}, {}
    for _, step in ipairs(ns.ROUTE) do
        if step.to > skill and step.from < target then
            local stepSkill = math.max(skill, step.from)
            local stepTo = math.min(target, step.to)
            local span = step.to - step.from
            local crafts = math.ceil(step.crafts * (stepTo - stepSkill) / span)
            for itemID, n in pairs(step.per) do
                need[itemID] = (need[itemID] or 0) + n * crafts
            end
            if step.makesItem then
                produced[step.makesItem] = (produced[step.makesItem] or 0) + crafts * (step.makes or 1)
            end
        end
    end
    -- Bolts: the ones you make for skill-ups get used by later recipes; any
    -- extra you need are made from raw cloth, so add that cloth to the list.
    local boltInfo = {}
    for bolt, recipe in pairs(ns.CONVERT or {}) do
        if need[bolt] then
            local h = have and have(bolt) or 0
            local short = math.max(0, need[bolt] - (produced[bolt] or 0) - h)
            boltInfo[bolt] = { short = short, made = produced[bolt] or 0 }
            for cloth, k in pairs(recipe) do
                need[cloth] = (need[cloth] or 0) + short * k
            end
        end
    end
    local list, total = {}, 0
    for itemID, n in pairs(need) do
        local h = have and have(itemID) or 0
        local entry
        if boltInfo[itemID] then
            entry = { itemID = itemID, need = n, have = h, buy = 0, crafted = true,
                      makeMore = boltInfo[itemID].short, made = boltInfo[itemID].made, cost = 0 }
        else
            local buy = math.max(0, n - h)
            local p = price and price(itemID)
            local cost = p and p * buy or nil
            if cost then total = total + cost end
            entry = { itemID = itemID, need = n, have = h, buy = buy, price = p, cost = cost }
        end
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b)
        if (a.crafted or false) ~= (b.crafted or false) then return not a.crafted end
        return (a.cost or 0) > (b.cost or 0)
    end)
    return list, total
end

-- Rank known recipes by cost per expected skill point.
-- recipes: { { id, name, color, reagents = { [itemID] = n }, available, yield } }
-- price(itemID) -> copper or nil; sellValue(itemID, n) optional -> copper you get back for the product
function ns.RankRecipes(recipes, price)
    local out = {}
    for _, r in ipairs(recipes) do
        local chance = ns.CHANCE[r.color] or 0
        if chance > 0 then
            local cost, unknown = 0, false
            for itemID, n in pairs(r.reagents or {}) do
                local p = price(itemID)
                if p then cost = cost + p * n else unknown = true end
            end
            out[#out + 1] = {
                id = r.id, name = r.name, color = r.color, chance = chance, cost = cost,
                perPoint = cost / chance, unknown = unknown, available = r.available or 0,
                reagents = r.reagents,
            }
        end
    end
    table.sort(out, function(a, b)
        -- recipes you can make right now with what you carry come first when nearly as cheap
        if a.unknown ~= b.unknown then return not a.unknown end
        if math.abs(a.perPoint - b.perPoint) > 1 then return a.perPoint < b.perPoint end
        return a.available > b.available
    end)
    return out
end

function ns.Money(copper)
    if not copper then return "?" end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = "|cffffd700" .. g .. "g|r" end
    if s > 0 then parts[#parts + 1] = "|cffc7c7cf" .. s .. "s|r" end
    if g == 0 and (c > 0 or s == 0) then parts[#parts + 1] = "|cffeda55f" .. c .. "c|r" end
    return table.concat(parts, " ")
end
