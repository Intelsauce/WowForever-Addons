-- Brewpath: reads your alchemy skill and recipes from the game, prices them,
-- and shows what to craft, the route, and a shopping list.

local ADDON_NAME, ns = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
local DB

local function Print(msg) print("|cff40d0a0Brewpath:|r " .. msg) end
ns.Print = Print

------------------------------------------------------------------------
-- Prices
------------------------------------------------------------------------
local function ItemName(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name, _, quality, _, _, _, _, _, _, icon = pcall(get, id)
    if ok and name then return name, icon, quality end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return "item " .. id, 134400, 1
end

local function Have(id)
    local get = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, n = pcall(get, id)
    return ok and n or 0
end

-- returns copper, source
local function Price(id)
    if ns.VENDOR_GUESS[id] then
        if DB.buy[id] then return DB.buy[id], "vendor" end
        return ns.VENDOR_GUESS[id], "vendor (estimate)"
    end
    if GoldsightNS and GoldsightNS.GetPrice then
        local ok, p = pcall(GoldsightNS.GetPrice, id)
        if ok and p and p.market then return p.market, "Goldsight" end
    end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "Brewpath", id)
        if ok and type(v) == "number" and v > 0 then return v, "Auctionator" end
    end
    if AuxForeverAPI and AuxForeverAPI.GetLatestPrice then
        local ok, v = pcall(AuxForeverAPI.GetLatestPrice, id)
        if ok and type(v) == "number" and v > 0 then return v, "auxForever" end
    end
    if DB.lastPrice[id] then return DB.lastPrice[id], "last seen" end
    return nil
end
local function PriceOnly(id) return (Price(id)) end

------------------------------------------------------------------------
-- Your skill
------------------------------------------------------------------------
local function Skill()
    if GetProfessions then
        local a, b = GetProfessions()
        for _, idx in ipairs({ a, b }) do
            if idx then
                local ok, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx)
                if ok and skillLine == ns.ALCHEMY_SKILL_LINE then return rank, maxRank, name end
            end
        end
    end
    if DB and DB.skill then return DB.skill, DB.maxSkill end
    return nil
end

------------------------------------------------------------------------
-- Reading recipes from the open profession window
------------------------------------------------------------------------
local COLOR_BY_NUM = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }
local COLOR_BY_TEXT = { optimal = "orange", medium = "yellow", easy = "green", trivial = "gray" }

local function IsAlchemyOpen()
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and info and info.professionID then
            return info.professionID == ns.ALCHEMY_SKILL_LINE, info
        end
    end
    if GetTradeSkillLine then
        local ok, name, rank, maxRank = pcall(GetTradeSkillLine)
        if ok and name and name ~= "UNKNOWN" then
            local alchemyName = GetSpellInfo and GetSpellInfo(2259)
            return name == (alchemyName or "Alchemy"), { skillLevel = rank, maxSkillLevel = maxRank }
        end
    end
    return false
end

local function ReadModern(info)
    local recipes = {}
    local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
    for _, id in ipairs(ids) do
        local ok, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
        if ok and r and r.learned then
            local color = COLOR_BY_NUM[r.relativeDifficulty] or COLOR_BY_TEXT[r.difficulty] or "gray"
            local reagents = {}
            local ok2, schem = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
            if ok2 and schem and schem.reagentSlotSchematics then
                for _, slot in ipairs(schem.reagentSlotSchematics) do
                    local basic = slot.reagentType == nil or slot.reagentType == 1
                        or (Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Basic)
                    if basic and slot.reagents and slot.reagents[1] and slot.reagents[1].itemID then
                        reagents[slot.reagents[1].itemID] = slot.quantityRequired or 1
                    end
                end
            end
            recipes[#recipes + 1] = { id = id, name = r.name, color = color, reagents = reagents,
                                      available = r.numAvailable or 0, icon = r.icon }
        end
    end
    return recipes
end

local function ReadClassic()
    local recipes = {}
    for i = 1, GetNumTradeSkills() do
        local name, kind, available = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
            local reagents = {}
            for j = 1, GetTradeSkillNumReagents(i) do
                local link = GetTradeSkillReagentItemLink(i, j)
                local _, _, n = GetTradeSkillReagentInfo(i, j)
                local id = link and tonumber(link:match("item:(%d+)"))
                if id then reagents[id] = n or 1 end
            end
            recipes[#recipes + 1] = { id = i, classicIndex = i, name = name, color = COLOR_BY_TEXT[kind] or "gray",
                                      reagents = reagents, available = available or 0 }
        end
    end
    return recipes
end

local function ReadRecipes()
    local open, info = IsAlchemyOpen()
    if not open then return end
    local recipes
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        recipes = ReadModern(info)
    elseif GetNumTradeSkills then
        recipes = ReadClassic()
    end
    if not recipes or #recipes == 0 then return end
    DB.recipes = recipes
    if info and info.skillLevel then DB.skill, DB.maxSkill = info.skillLevel, info.maxSkillLevel end
    DB.recipesAt = DB.skill
    ns.windowOpen = true
    if ns.Refresh then ns.Refresh() end
end

------------------------------------------------------------------------
-- Learning vial prices at vendors
------------------------------------------------------------------------
local function LearnVendor()
    local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
    for i = 1, n do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        if id and ns.VENDOR_GUESS[id] then
            local price, qty
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
                if ok and info then price, qty = info.price, info.stackCount end
            end
            if not price and GetMerchantItemInfo then
                local _, _, p, q = GetMerchantItemInfo(i)
                price, qty = p, q
            end
            if price and price > 0 then DB.buy[id] = math.floor(price / math.max(1, qty or 1) + 0.5) end
        end
    end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local W, H, ROWH, VISIBLE = 640, 470, 24, 13
local F, rows, tab, shopTarget = nil, {}, "craft", "step"

local function Backdrop(f)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.04, 0.07, 0.07, 0.96)
    f:SetBackdropBorderColor(0.3, 0.8, 0.65, 1)
end

local function WhereText(id)
    local w = ns.WHERE[id]
    if not w then return nil end
    return w.how .. ": " .. w.zones
end

local function ReagentText(per)
    local parts = {}
    for id, n in pairs(per) do
        parts[#parts + 1] = n .. " " .. (ItemName(id))
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function MakeRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(W - 28, ROWH)
    r:SetPoint("TOPLEFT", 14, -(i - 1) * ROWH)
    r:RegisterForClicks("LeftButtonUp")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROWH - 4, ROWH - 4)
    r.icon:SetPoint("LEFT", 2, 0)
    r.c1 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.c1:SetPoint("LEFT", ROWH + 4, 0)
    r.c1:SetWidth(250)
    r.c1:SetJustifyH("LEFT")
    r.c1:SetWordWrap(false)
    r.c2 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.c2:SetPoint("LEFT", 290, 0)
    r.c2:SetWidth(80)
    r.c2:SetJustifyH("RIGHT")
    r.c3 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.c3:SetPoint("LEFT", 380, 0)
    r.c3:SetWidth(80)
    r.c3:SetJustifyH("RIGHT")
    r.c4 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.c4:SetPoint("LEFT", 470, 0)
    r.c4:SetWidth(130)
    r.c4:SetJustifyH("RIGHT")
    r.wide = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.wide:SetPoint("LEFT", 200, 0)
    r.wide:SetPoint("RIGHT", -6, 0)
    r.wide:SetJustifyH("LEFT")
    r.wide:SetWordWrap(false)
    r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.btn:SetSize(52, 20)
    r.btn:SetPoint("RIGHT", -2, 0)
    r:SetScript("OnEnter", function(self)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:SetText(self.tipTitle or "", 1, 0.82, 0) end
            for _, line in ipairs(self.tip) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function SetHeaders(a, b, c, d)
    F.h1:SetText(a or ""); F.h2:SetText(b or ""); F.h3:SetText(c or ""); F.h4:SetText(d or "")
end

local function SearchAH(id)
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() and C_AuctionHouse then
        pcall(C_AuctionHouse.SendSearchQuery, C_AuctionHouse.MakeItemKey(id), {}, true)
        return true
    end
end

local function Craft(rec, n)
    if InCombatLockdown() then return end
    if not ns.windowOpen then
        Print("open your Alchemy window first.")
        return
    end
    local ok
    if rec.classicIndex and DoTradeSkill then
        ok = pcall(DoTradeSkill, rec.classicIndex, n)
    elseif C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
        ok = pcall(C_TradeSkillUI.CraftRecipe, rec.id, n)
    end
    if not ok then Print("the game didn't allow that. Craft it from the Alchemy window.") end
end

local function FillCraft()
    local skill = Skill()
    local list = DB.recipes and ns.RankRecipes(DB.recipes, PriceOnly) or {}
    F.empty:SetShown(#list == 0)
    F.empty:SetText(DB.recipes and "Nothing gives skill-ups right now. Train the next recipes, or check the Route tab."
        or "Open your Alchemy window once so Brewpath can read your recipes.")
    if DB.recipes and DB.recipesAt and skill and skill > DB.recipesAt then
        F.note:SetText("|cffffd040Colours are from skill " .. DB.recipesAt .. ". Open your Alchemy window to update them.|r")
    else
        F.note:SetText("Cheapest skill points first. Orange always gives a point, yellow usually, green rarely.")
    end
    SetHeaders("Recipe", "Cost per craft", "Per skill point", "Can make")
    for i = 1, VISIBLE do
        local r, e = rows[i], list[i]
        r.btn:Hide()
        r.itemID = nil
        r:SetScript("OnClick", nil)
        r.wide:SetText("")
        if not e then r:Hide() else
            r:Show()
            r.bg:SetColorTexture(1, 1, 1, i == 1 and 0.08 or 0)
            r.icon:SetTexture(e.icon or 134400)
            r.c1:SetText("|cff" .. ns.COLOR_HEX[e.color] .. e.name .. "|r" .. (i == 1 and "  |cff40ff40best|r" or ""))
            r.c2:SetText(e.unknown and "|cff888888?|r" or ns.Money(e.cost))
            r.c3:SetText(e.unknown and "|cff888888?|r" or ns.Money(e.perPoint))
            r.c4:SetText(tostring(e.available))
            r.btn:SetShown(ns.windowOpen and e.available > 0)
            r.btn:SetText("Craft")
            r.btn:SetScript("OnClick", function() Craft(e, 1) end)
            r.tipTitle = e.name
            r.tip = { "Needs: " .. ReagentText(e.reagents),
                      string.format("Skill-up chance: %d%% (%s)", e.chance * 100, e.color),
                      e.unknown and "Some reagent prices are unknown: scan the auction house with Goldsight." or nil }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Where each route recipe comes from
-- ---------------------------------------------------------------------------
local KIND_LABEL = {
    known   = "|cffaaaaaaKnown|r",
    trainer = "|cff80c0ffTrainer|r",
    vendor  = "|cffffd040Vendor|r",
    quest   = "|cffff9040Quest|r",
}

local function RecipeKind(step)
    local s = (step.source or ""):lower()
    if s:find("^known") then return "known" end
    if s == "trainer" then return "trainer" end
    if s:find("quest") then return "quest" end
    return "vendor"
end

local function KnownRecipe(name)
    if not DB.recipes then return nil end
    for _, rec in ipairs(DB.recipes) do
        if rec.name == name then return true end
    end
    return false
end

-- The lowest trainer rank that teaches a recipe used from `from` skill.
local function TrainerRankFor(from)
    for _, rank in ipairs(ns.RANKS) do
        if from < rank.cap then return rank end
    end
    return ns.RANKS[#ns.RANKS]
end

local function MyFaction()
    local f = UnitFactionGroup("player")
    return (f == "Horde" or f == "Alliance") and f or nil
end

-- Returns a short one-liner and a list of tooltip lines.
local function RecipeWhere(step)
    local kind = RecipeKind(step)
    local faction = MyFaction()
    if kind == "known" then
        return "Known when you learn Alchemy", { "You already have this from the start." }
    elseif kind == "trainer" then
        local rank = TrainerRankFor(step.from)
        local lines = { "Train it from an Alchemy trainer (" .. rank.name .. " or higher)." }
        if rank.name == "Apprentice" then
            return "Any Alchemy trainer", lines
        end
        local who = faction and rank.where[faction]
        if who then
            lines[#lines + 1] = "|cff40ff90" .. rank.name .. " trainers:|r " .. who
        else
            lines[#lines + 1] = "|cff40ff90Horde:|r " .. rank.where.Horde
            lines[#lines + 1] = "|cff40ff90Alliance:|r " .. rank.where.Alliance
        end
        lines[#lines + 1] = "Higher-rank trainers also teach it."
        return rank.name .. " trainer: " .. (who or "see tooltip"), lines
    end
    -- vendor / quest: prefer the detailed RECIPE_VENDORS entry for this faction
    local lines, short = {}, nil
    for _, rv in ipairs(ns.RECIPE_VENDORS) do
        if rv.recipe:sub(1, #step.recipe) == step.recipe
           and (not rv.faction or not faction or rv.faction == faction) then
            lines[#lines + 1] = rv.vendors
            short = short or rv.vendors
        end
    end
    if #lines == 0 then lines[1] = step.source end
    lines[#lines + 1] = "Some recipes are bind-on-pickup: get them on the character who levels Alchemy."
    return short or step.source, lines
end
ns.RecipeKind, ns.RecipeWhere, ns.TrainerRankFor = RecipeKind, RecipeWhere, TrainerRankFor

local function FillRoute()
    local skill = Skill() or 1
    local _, cur = ns.RouteStep(skill)
    F.empty:Hide()
    local maxOff = math.max(0, #ns.ROUTE - VISIBLE)
    if F.routeOffset == nil then
        F.routeOffset = math.max(0, math.min(maxOff, (cur or #ns.ROUTE) - 4))
    end
    F.routeOffset = math.max(0, math.min(maxOff, F.routeOffset))
    F.note:SetText(ns.SOURCE_NOTE .. (maxOff > 0 and "  |cffffffffScroll for more.|r" or ""))
    SetHeaders("Recipe", "Skill", "Crafts", "Get recipe from")
    for i = 1, VISIBLE do
        local idx = i + F.routeOffset
        local r, step = rows[i], ns.ROUTE[idx]
        r.btn:Hide()
        r.itemID = nil
        r:SetScript("OnClick", nil)
        r.wide:SetText("")
        if not step then r:Hide() else
            r:Show()
            local done = skill >= step.to
            local now = idx == cur
            r.bg:SetColorTexture(0.3, 1, 0.7, now and 0.12 or 0)
            r.icon:SetTexture(done and 136814 or "Interface\\Icons\\Trade_Alchemy")
            r.icon:SetDesaturated(not done and not now)
            r.icon:SetAlpha((done or now) and 1 or 0.6)
            local col = done and "|cff808080" or (now and "|cff40ff90" or "|cffffffff")
            r.c1:SetText(col .. step.recipe .. "|r" .. (now and "  |cff40ff90< you are here|r" or ""))
            r.c2:SetText(step.from .. " - " .. step.to)
            r.c3:SetText(now and (ns.CraftsLeft(step, skill) .. " left") or ("about " .. step.crafts))
            local kind = RecipeKind(step)
            local learned = kind ~= "known" and KnownRecipe(step.recipe)
            r.c4:SetText(learned and "|cff40ff40Learned|r" or KIND_LABEL[kind])
            r.tipTitle = step.recipe .. "  (" .. step.from .. "-" .. step.to .. ")"
            r.tip = { "Each craft: " .. ReagentText(step.per), " ",
                      "|cffffd040Get the recipe:|r" .. (learned and "  |cff40ff40(you know it)|r" or "") }
            local _, whereLines = RecipeWhere(step)
            for _, l in ipairs(whereLines) do table.insert(r.tip, l) end
            table.insert(r.tip, " ")
            for id in pairs(step.per) do
                local w = WhereText(id)
                if w then table.insert(r.tip, "|cff40ff90" .. (ItemName(id)) .. "|r - " .. w) end
            end
            if step.makes then table.insert(r.tip, "Makes " .. step.makes .. " per craft.") end
            if step.note then table.insert(r.tip, step.note) end
            if step.alt then table.insert(r.tip, "|cffffd040Alternative:|r " .. step.alt) end
        end
    end
end

local function ShopTargetSkill(skill, maxSkill)
    if shopTarget == "step" then
        local step = ns.RouteStep(skill)
        return step and step.to or 300
    elseif shopTarget == "cap" then
        return math.max(skill + 1, maxSkill or 75)
    end
    return 300
end

local function FillWhere()
    local skill = Skill() or 1
    F.empty:Hide()
    F.note:SetText("Recipes you still need (and where to learn them), then materials. Hover a row for the full list. (classic) = original-game location, not yet confirmed for Forever.")
    SetHeaders("Item / recipe", "", "", "")
    F.h2:SetText("")
    -- recipes you still need to buy, then materials in route order
    local list, seen = {}, {}
    local seenRecipe = {}
    for _, step in ipairs(ns.ROUTE) do
        if step.to > skill and not seenRecipe[step.recipe]
           and RecipeKind(step) ~= "known" and not KnownRecipe(step.recipe) then
            seenRecipe[step.recipe] = true
            list[#list + 1] = { recipe = step }
        end
    end
    for _, step in ipairs(ns.ROUTE) do
        if step.to > skill then
            local ids = {}
            for id in pairs(step.per) do ids[#ids + 1] = id end
            table.sort(ids)
            for _, id in ipairs(ids) do
                if not seen[id] then
                    seen[id] = true
                    list[#list + 1] = { itemID = id, step = step }
                end
            end
        end
    end
    for i = 1, VISIBLE do
        local r, e = rows[i], list[i + (F.whereOffset or 0)]
        r.btn:Hide()
        r.c2:SetText(""); r.c3:SetText(""); r.c4:SetText("")
        r:SetScript("OnClick", nil)
        if not e then
            r:Hide()
            r.wide:SetText("")
        else
            r:Show()
            r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
            if e.recipe then
                r.itemID = nil
                r.icon:SetTexture(134939) -- recipe scroll
                local step = e.recipe
                local kind = RecipeKind(step)
                local short, lines = RecipeWhere(step)
                r.c1:SetText("|cffffd040" .. step.recipe .. "|r")
                r.wide:SetText(KIND_LABEL[kind] .. "  |cffaaaaaa" .. short .. "|r")
                r.tipTitle = "Recipe: " .. step.recipe
                r.tip = { "Needed at skill " .. step.from .. " (" .. step.from .. "-" .. step.to .. ")."
                          .. (DB.recipes and "" or "  Open your Alchemy window so Brewpath can hide recipes you know."), " " }
                for _, l in ipairs(lines) do table.insert(r.tip, l) end
            else
                local name, icon = ItemName(e.itemID)
                local w = ns.WHERE[e.itemID]
                r.itemID = e.itemID
                r.icon:SetTexture(icon)
                r.c1:SetText(name .. "  |cff888888(" .. (w and w.how or "?") .. ")|r")
                r.wide:SetText("|cffaaaaaa" .. (w and w.zones or "unknown") .. "|r")
                r.tip = { " ", w and ("|cff40ff90" .. w.how .. "|r: " .. w.zones) or "Location unknown.",
                          "First needed for " .. e.step.recipe .. " (" .. e.step.from .. "-" .. e.step.to .. ")." }
            end
        end
    end
    F.whereCount = #list
    if #list > VISIBLE then
        F.note:SetText(F.note:GetText() .. "  |cffffffffScroll for more.|r")
    end
end

local function FillShop()
    local skill, maxSkill = Skill()
    skill = skill or 1
    local target = ShopTargetSkill(skill, maxSkill)
    local list, total = ns.ShoppingList(skill, target, Have, PriceOnly)
    F.empty:SetShown(#list == 0)
    F.empty:SetText("Nothing to buy: you're done!")
    F.note:SetText(string.format("For skill %d to %d you'll need about |cffffffff%s|r more. Left-click an item at the auction house to search for it.",
        skill, target, ns.Money(total)))
    SetHeaders("Item", "Need / have", "Buy", "Cost")
    for i = 1, VISIBLE do
        local r, e = rows[i], list[i]
        r.btn:Hide()
        if not e then r:Hide() else
            r:Show()
            local name, icon = ItemName(e.itemID)
            r.bg:SetColorTexture(1, 1, 1, 0)
            r.icon:SetTexture(icon)
            r.c1:SetText((e.buy == 0 and "|cff808080" or "|cffffffff") .. name .. "|r")
            r.c2:SetText(e.need .. " / " .. e.have)
            r.c3:SetText(e.buy == 0 and "|cff40ff40got it|r" or tostring(e.buy))
            r.c4:SetText(e.buy == 0 and "" or ns.Money(e.cost))
            r.itemID = e.itemID
            local _, src = Price(e.itemID)
            r.tip = { " ", "Price: " .. (e.price and (ns.Money(e.price) .. " each") or "unknown") .. (src and (" (" .. src .. ")") or "") }
            local w = WhereText(e.itemID)
            if w then table.insert(r.tip, "|cff40ff90" .. w .. "|r") end
            r:SetScript("OnClick", function()
                if not SearchAH(e.itemID) then
                    if ns.VENDOR_GUESS[e.itemID] then
                        Print(name .. " is sold by Alchemy Supplies and Trade Supplies vendors.")
                    else
                        Print("open the auction house to search for " .. name .. ".")
                    end
                end
            end)
        end
    end
end

function ns.Refresh()
    if not F or not F:IsShown() then return end
    local skill, maxSkill = Skill()
    if skill then
        local rank = ns.RankFor(skill, maxSkill)
        F.skill:SetText(string.format("Alchemy |cffffffff%d / %d|r  %s", skill, maxSkill, rank and ("(" .. rank.name .. ")") or ""))
        F.bar:SetWidth(math.max(1, (W - 32) * skill / 300))
        local advice = ns.TrainingAdvice(skill, maxSkill, UnitLevel("player"), UnitFactionGroup("player"))
        F.advice:SetText(advice or "")
    else
        F.skill:SetText("You don't know Alchemy yet. Learn it from any Alchemy trainer.")
        F.bar:SetWidth(1)
        F.advice:SetText("")
    end
    for name, b in pairs(F.tabs) do b.sel:SetShown(name == tab) end
    for _, b in pairs(F.targets) do b:SetShown(tab == "shop") end
    for key, b in pairs(F.targets) do b.sel:SetShown(key == shopTarget) end
    for i = 1, VISIBLE do
        rows[i].c1:SetWidth(tab == "where" and 168 or 250)
        if tab ~= "where" then rows[i].wide:SetText("") end
    end
    if tab == "craft" then FillCraft() elseif tab == "route" then FillRoute()
    elseif tab == "where" then FillWhere() else FillShop() end
    ns.Layout()
end

-- Stack everything top to bottom so long text never overlaps the next part,
-- whatever font size the game uses.
local function TextH(fs)
    if not fs or (fs:GetText() or "") == "" then return 0 end
    return math.ceil(fs:GetStringHeight() or 12)
end

function ns.Layout()
    if not F then return end
    local y = 74
    local ah = TextH(F.advice)
    if ah > 0 then y = y + ah + 8 end
    local tabs = {}
    for _, b in pairs(F.tabs) do tabs[#tabs + 1] = b end
    for _, b in pairs(F.targets) do tabs[#tabs + 1] = b end
    for _, b in ipairs(tabs) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", b.x, -y)
    end
    y = y + 22 + 10
    F.note:ClearAllPoints()
    F.note:SetPoint("TOPLEFT", 16, -y)
    F.note:SetPoint("TOPRIGHT", -16, -y)
    local nh = TextH(F.note)
    if nh > 0 then y = y + nh + 10 end
    local hh = 0
    for _, h in ipairs({ F.h1, F.h2, F.h3, F.h4 }) do
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", h.x, -y)
        hh = math.max(hh, TextH(h))
    end
    if hh > 0 then y = y + hh + 6 end
    F.list:ClearAllPoints()
    F.list:SetPoint("TOPLEFT", 0, -y)
    F:SetHeight(y + ROWH * VISIBLE + 14)
end

local function Tab(parent, label, x, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, -86)
    b.x = x
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    b.sel = b:CreateTexture(nil, "BORDER")
    b.sel:SetPoint("BOTTOMLEFT")
    b.sel:SetPoint("BOTTOMRIGHT")
    b.sel:SetHeight(2)
    b.sel:SetColorTexture(0.3, 1, 0.7, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function Build()
    F = CreateFrame("Frame", "BrewpathFrame", UIParent, "BackdropTemplate")
    F:SetSize(W, H)
    F:SetPoint("CENTER", -200, 0)
    F:SetFrameStrata("HIGH")
    F:SetMovable(true)
    F:SetClampedToScreen(true)
    F:EnableMouse(true)
    F:RegisterForDrag("LeftButton")
    F:SetScript("OnDragStart", F.StartMoving)
    F:SetScript("OnDragStop", F.StopMovingOrSizing)
    Backdrop(F)
    tinsert(UISpecialFrames, "BrewpathFrame")

    local icon = F:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "icon")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 14, -10)
    local title = F:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Brewpath")
    local close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    F.skill = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    F.skill:SetPoint("TOPLEFT", 16, -46)
    local track = F:CreateTexture(nil, "BACKGROUND")
    F.track = track
    track:SetPoint("TOPLEFT", 16, -64)
    track:SetSize(W - 32, 6)
    track:SetColorTexture(0, 0, 0, 0.6)
    F.bar = F:CreateTexture(nil, "ARTWORK")
    F.bar:SetPoint("TOPLEFT", track, "TOPLEFT")
    F.bar:SetHeight(6)
    F.bar:SetColorTexture(0.3, 0.9, 0.6, 1)
    F.advice = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    F.advice:SetPoint("TOPLEFT", 16, -74)
    F.advice:SetPoint("TOPRIGHT", -16, -74)
    F.advice:SetJustifyH("LEFT")

    F.tabs = {
        craft = Tab(F, "Craft now", 14, 100, function() tab = "craft"; ns.Refresh() end),
        route = Tab(F, "Route 1-300", 118, 100, function() tab = "route"; F.routeOffset = nil; ns.Refresh() end),
        shop = Tab(F, "Shopping list", 222, 100, function() tab = "shop"; ns.Refresh() end),
        where = Tab(F, "Where to find", 326, 100, function() tab = "where"; F.whereOffset = 0; ns.Refresh() end),
    }
    F.targets = {}
    for i, t in ipairs({ { "step", "Step" }, { "cap", "My cap" }, { "max", "To 300" } }) do
        local b = Tab(F, t[2], 434 + (i - 1) * 52, 50, function() shopTarget = t[1]; ns.Refresh() end)
        F.targets[t[1]] = b
    end

    F.note = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    F.note:SetPoint("TOPLEFT", 16, -116)
    F.note:SetPoint("TOPRIGHT", -16, -116)
    F.note:SetJustifyH("LEFT")
    F.note:SetTextColor(0.8, 0.8, 0.8)

    local function H(x, w, justify)
        local fs = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", x, -144)
        fs.x = x
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "LEFT")
        return fs
    end
    F.h1 = H(14 + ROWH + 4, 200)
    F.h2 = H(14 + 290, 80, "RIGHT")
    F.h3 = H(14 + 380, 80, "RIGHT")
    F.h4 = H(14 + 470, 130, "RIGHT")
    for _, h in ipairs({ F.h1, F.h2, F.h3, F.h4 }) do h:SetWordWrap(false) end

    local list = CreateFrame("Frame", nil, F)
    F.list = list
    list:SetPoint("TOPLEFT", 0, -158)
    list:SetSize(W, ROWH * VISIBLE)
    for i = 1, VISIBLE do rows[i] = MakeRow(list, i) end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        if tab == "where" then
            local maxOff = math.max(0, (F.whereCount or 0) - VISIBLE)
            F.whereOffset = math.max(0, math.min(maxOff, (F.whereOffset or 0) - delta * 3))
        elseif tab == "route" then
            F.routeOffset = (F.routeOffset or 0) - delta
        else
            return
        end
        ns.Refresh()
    end)
    F.empty = F:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    F.empty:SetPoint("TOP", list, "TOP", 0, -40)
    F.empty:SetWidth(W - 60)

    F:SetScript("OnShow", ns.Refresh)
    F:Hide()
end

function ns.Toggle()
    if not F then Build() end
    if F:IsShown() then F:Hide() else F:Show() end
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local mm
local function PlaceMM()
    local a = math.rad(DB.minimap.angle or 250)
    local r = (Minimap:GetWidth() / 2) + 10
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
local function BuildMM()
    if mm or not Minimap then return end
    local b = CreateFrame("Button", "BrewpathMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(MEDIA .. "icon")
    ic:SetSize(21, 21)
    ic:SetPoint("TOPLEFT", 6, -5)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", ns.Toggle)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            if not mx then return end
            local cx, cy = GetCursorPosition()
            local sc = Minimap:GetEffectiveScale()
            local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
            DB.minimap.angle = math.deg(atan2(cy / sc - my, cx / sc - mx))
            PlaceMM()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Brewpath", 0.25, 0.85, 0.65)
        local skill, maxSkill = Skill()
        GameTooltip:AddLine(skill and ("Alchemy " .. skill .. " / " .. maxSkill) or "Alchemy not learned", 1, 1, 1)
        GameTooltip:AddLine("Click: what to craft next", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mm = b
    if DB.minimap.hide then b:Hide() else PlaceMM() end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
                     "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_CLOSE", "MERCHANT_SHOW",
                     "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local pending
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        BrewpathDB = BrewpathDB or {}
        DB = BrewpathDB
        DB.buy = DB.buy or {}
        DB.lastPrice = DB.lastPrice or {}
        DB.minimap = DB.minimap or { angle = 250, hide = false }
    elseif event == "PLAYER_LOGIN" then
        BuildMM()
        Print("loaded. Click the minimap flask or type /bp for what to craft next.")
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        if pending then return end
        pending = true
        C_Timer.After(0.3, function()
            pending = false
            pcall(ReadRecipes)
        end)
    elseif event == "TRADE_SKILL_CLOSE" then
        ns.windowOpen = false
        ns.Refresh()
    elseif event == "MERCHANT_SHOW" then
        pcall(LearnVendor)
        ns.Refresh()
    else
        -- remember the latest auction prices we've seen, so they survive without Goldsight
        if GoldsightNS and GoldsightNS.GetPrice then
            for _, id in pairs(ns.ITEMS) do
                local ok, p = pcall(GoldsightNS.GetPrice, id)
                if ok and p and p.market then DB.lastPrice[id] = p.market end
            end
        end
        ns.Refresh()
    end
end)

SLASH_BREWPATH1 = "/bp"
SLASH_BREWPATH2 = "/brewpath"
SlashCmdList.BREWPATH = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "minimap" then
        DB.minimap.hide = not DB.minimap.hide
        if mm then if DB.minimap.hide then mm:Hide() else mm:Show(); PlaceMM() end end
    elseif msg == "route" or msg == "shop" or msg == "craft" or msg == "where" then
        tab = msg
        if not F then Build() end
        F.routeOffset, F.whereOffset = nil, 0
        F:Show()
        ns.Refresh()
    else
        ns.Toggle()
    end
end
