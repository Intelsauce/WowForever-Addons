-- Goldsight: making room in full bags without losing value.
--   * ranks every bag slot by what it's worth (cheapest first)
--   * merges split stacks, which frees slots for free
--   * when you loot with full bags, says whether the drop is worth more
--     than your cheapest slot, and offers to clear that slot

local _, ns = ...

local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

local function BagRange()
    return 0, (NUM_BAG_SLOTS or 4) -- normal bags only; the reagent bag can't take loot like gear
end

local function InSet(bag, slot)
    if C_Container.GetContainerItemEquipmentSetInfo then
        local ok, inSet = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
        return ok and inSet
    end
    return false
end

function ns.FreeSlots()
    local free, total = 0, 0
    local first, last = BagRange()
    for bag = first, last do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        local f, bagType = C_Container.GetContainerNumFreeSlots(bag)
        if n > 0 and (bagType == nil or bagType == 0) then
            total = total + n
            free = free + (f or 0)
        end
    end
    return free, total
end

------------------------------------------------------------------------
-- Every slot you could clear, cheapest first
------------------------------------------------------------------------
function ns.SlotCandidates()
    local list = {}
    local first, last = BagRange()
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local it = C_Container.GetContainerItemInfo(bag, slot)
            if it and it.itemID and not it.hasNoValue and not ns.db.ignore[it.itemID] then
                local info = ns.ItemInfo(it.hyperlink or it.itemID)
                local quest = info and info.classID == QUEST_CLASS
                if not quest and not InSet(bag, slot) then
                    local v = ns.Value(it.itemID, it.hyperlink, it.stackCount or 1, it.isBound, it.hasNoValue)
                    if v.action ~= "none" then
                        list[#list + 1] = {
                            bag = bag, slot = slot, itemID = it.itemID, link = it.hyperlink,
                            count = it.stackCount or 1, quality = it.quality, icon = it.iconFileID,
                            name = info and info.name, value = v.best or 0, verdict = v,
                        }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        return (a.quality or 0) < (b.quality or 0)
    end)
    return list
end

------------------------------------------------------------------------
-- Stacking split stacks
------------------------------------------------------------------------
-- Returns one round of moves and how many slots stacking would free in total
function ns.StackPlan()
    local byItem = {}
    local first, last = BagRange()
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local it = C_Container.GetContainerItemInfo(bag, slot)
            if it and it.itemID and not it.isLocked then
                local info = ns.ItemInfo(it.hyperlink or it.itemID)
                local max = info and info.maxStack or 1
                local count = it.stackCount or 1
                if max > 1 and count < max then
                    local key = it.itemID .. (it.isBound and ":b" or "")
                    byItem[key] = byItem[key] or {}
                    table.insert(byItem[key], { bag = bag, slot = slot, count = count, max = max })
                end
            end
        end
    end
    local moves, freed = {}, 0
    for _, stacks in pairs(byItem) do
        if #stacks >= 2 then
            local total = 0
            for _, s in ipairs(stacks) do total = total + s.count end
            local need = math.ceil(total / stacks[1].max)
            freed = freed + (#stacks - need)
            if #stacks > need then
                table.sort(stacks, function(a, b) return a.count > b.count end)
                moves[#moves + 1] = { from = stacks[#stacks], to = stacks[1] }
            end
        end
    end
    return moves, freed
end

function ns.StackUp(round)
    round = round or 1
    if InCombatLockdown() then
        ns.Print("can't move items in combat.")
        return
    end
    local moves = ns.StackPlan()
    if #moves == 0 then
        ns.Print(round == 1 and "nothing to stack: no split stacks." or "all stacked up.")
        if ns.RefreshAll then ns.RefreshAll() end
        if ns.CheckFullBags then ns.CheckFullBags() end
        return
    end
    ClearCursor()
    for _, m in ipairs(moves) do
        C_Container.PickupContainerItem(m.from.bag, m.from.slot)
        C_Container.PickupContainerItem(m.to.bag, m.to.slot)
        ClearCursor()
    end
    if round < 15 then
        C_Timer.After(0.4, function() ns.StackUp(round + 1) end)
    end
end

------------------------------------------------------------------------
-- Clearing a slot
------------------------------------------------------------------------
local function Label(c)
    return (c.link or c.name or "item") .. ((c.count or 1) > 1 and ("x" .. c.count) or "")
end

function ns.PickupSlot(c)
    if InCombatLockdown() then return end
    ClearCursor()
    C_Container.PickupContainerItem(c.bag, c.slot)
    ns.Print("picked up " .. Label(c) .. ". Click outside your bags to destroy it, or click a bag slot to put it back.")
end

-- One-click delete, only for gray and white items (anything better goes
-- through the game's own "are you sure" dialog via PickupSlot)
function ns.DeleteSlot(c)
    if InCombatLockdown() then return end
    if (c.quality or 0) > 1 then
        ns.PickupSlot(c)
        return
    end
    local now = C_Container.GetContainerItemInfo(c.bag, c.slot)
    if not now or now.itemID ~= c.itemID then
        ns.Print("that item has moved. Try again.")
        return
    end
    ClearCursor()
    C_Container.PickupContainerItem(c.bag, c.slot)
    local ok = pcall(DeleteCursorItem)
    if ok then
        ns.Print("deleted " .. Label(c) .. " (worth " .. ns.Money(c.value) .. ").")
    else
        ClearCursor()
        ns.Print("the game didn't allow that. Drag the item out of your bags to delete it.")
    end
    C_Timer.After(0.4, function()
        if ns.RefreshAll then ns.RefreshAll() end
        if ns.CheckFullBags then ns.CheckFullBags() end
    end)
end

------------------------------------------------------------------------
-- Bags full while looting
------------------------------------------------------------------------
local pendingLoot, lastShown = {}, 0
local popup

-- Would this drop slide into a stack you already have?
local function FitsExisting(itemID, qty)
    local first, last = BagRange()
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local it = C_Container.GetContainerItemInfo(bag, slot)
            if it and it.itemID == itemID then
                local info = ns.ItemInfo(itemID)
                if info and (info.maxStack or 1) - (it.stackCount or 1) >= (qty or 1) then return true end
            end
        end
    end
    return false
end

local function BuildPopup()
    local p = CreateFrame("Frame", "GoldsightRoomPopup", UIParent, "BackdropTemplate")
    p:SetSize(300, 150)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    p:SetBackdropBorderColor(0.9, 0.4, 0.2, 1)
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -10)
    t:SetText("Goldsight: bags full")
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.text:SetPoint("TOPLEFT", 12, -30)
    p.text:SetWidth(276)
    p.text:SetJustifyH("LEFT")
    p.text:SetSpacing(2)
    p.stack = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.stack:SetSize(130, 22)
    p.stack:SetPoint("BOTTOMLEFT", 10, 38)
    p.stack:SetScript("OnClick", function() ns.StackUp() end)
    p.clear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.clear:SetSize(140, 22)
    p.clear:SetPoint("BOTTOMRIGHT", -10, 38)
    p.clear:SetScript("OnClick", function(self) if self.cand then ns.DeleteSlot(self.cand) end end)
    p.list = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.list:SetSize(276, 22)
    p.list:SetPoint("BOTTOM", 0, 10)
    p.list:SetText("Show everything, cheapest first")
    p.list:SetScript("OnClick", function()
        if ns.ShowTab then ns.ShowTab("room") end
    end)
    p:Hide()
    return p
end

-- Looks at the open loot window (if any) and your bags, and says what to do
function ns.CheckFullBags(force)
    if not ns.db then return end
    local free = ns.FreeSlots()
    if free > 0 and not force then
        if popup then popup:Hide() end
        return
    end
    -- the most valuable drop that needs a new slot
    local best
    for _, l in pairs(pendingLoot) do
        local id = ns.ItemID(l.link)
        if id and not FitsExisting(id, l.qty) then
            local v = ns.Value(id, l.link, l.qty or 1)
            if not best or (v.best or 0) > best.value then
                best = { link = l.link, qty = l.qty or 1, value = v.best or 0 }
            end
        end
    end
    if not best and not force then return end
    if free > 0 then return end

    local cand = ns.SlotCandidates()[1]
    local _, freed = ns.StackPlan()
    local lines = {}
    local recommend = false
    if freed > 0 then
        -- free space costs nothing: no need to throw anything away
        local what = best and (" so you can take " .. best.link .. (best.qty > 1 and (" x" .. best.qty) or "")) or ""
        lines[#lines + 1] = string.format("|cff40ff40Stack up|r: merging split stacks frees %d slot(s)%s without losing anything.", freed, what)
    elseif cand then
        local cl = (cand.link or cand.name) .. (cand.count > 1 and (" x" .. cand.count) or "")
        if best then
            local bl = best.link .. (best.qty > 1 and (" x" .. best.qty) or "")
            if cand.value < best.value then
                recommend = true
                lines[#lines + 1] = string.format("%s is worth %s.\nYour cheapest slot is %s, worth %s. Clear it to take the drop: +%s.",
                    bl, ns.Money(best.value), cl, ns.Money(cand.value), ns.Money(best.value - cand.value))
            else
                lines[#lines + 1] = string.format("%s is only worth %s.\nEverything in your bags is worth more, so leave it.",
                    bl, ns.Money(best.value))
            end
        else
            recommend = true
            lines[#lines + 1] = string.format("Your cheapest slot is %s, worth %s.", cl, ns.Money(cand.value))
        end
        if ns.atMerchant and recommend then
            lines[#lines + 1] = "|cffffd040You're at a vendor: sell it instead of deleting.|r"
        end
    elseif freed == 0 then
        lines[#lines + 1] = "Nothing in your bags is safe to suggest throwing away."
    end

    popup = popup or BuildPopup()
    popup.text:SetText(table.concat(lines, "\n\n"))
    popup:SetHeight(math.max(130, (popup.text:GetStringHeight() or 40) + 110))
    popup.stack:SetShown(freed > 0)
    popup.stack:SetText("Stack up (+" .. freed .. " slot" .. (freed == 1 and "" or "s") .. ")")
    popup.clear:SetShown(recommend and cand ~= nil)
    popup.clear.cand = cand
    if cand then
        popup.clear:SetText(((cand.quality or 0) <= 1) and "Delete cheapest" or "Pick up cheapest")
    end
    popup:ClearAllPoints()
    if LootFrame and LootFrame:IsShown() then
        popup:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 8, 0)
    else
        popup:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    popup:Show()

    if time() - lastShown > 10 then
        lastShown = time()
        ns.Print((lines[1]:gsub("\n", " ")))
    end
end

ns.On("LOOT_READY", function()
    wipe(pendingLoot)
    for i = 1, GetNumLootItems() do
        local ok, link = pcall(GetLootSlotLink, i)
        if ok and type(link) == "string" then
            local _, _, qty = GetLootSlotInfo(i)
            pendingLoot[i] = { link = link, qty = qty }
        end
    end
    C_Timer.After(0.3, function() ns.CheckFullBags() end)
end)
ns.On("LOOT_SLOT_CLEARED", function(slot) pendingLoot[slot] = nil end)
ns.On("LOOT_CLOSED", function()
    wipe(pendingLoot)
    if popup then popup:Hide() end
end)
ns.On("UI_ERROR_MESSAGE", function(_, msg)
    local ok, full = pcall(function()
        return msg and (msg == ERR_INV_FULL or msg == ERR_LOOT_INV_FULL or msg == ERR_BAG_FULL)
    end)
    if ok and full then ns.CheckFullBags(true) end
end)
