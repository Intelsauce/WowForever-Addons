-- Goldsight: main window, auction house panel, minimap button, settings.

local _, ns = ...

local W, H, ROWH, VISIBLE = 640, 490, 24, 13
local F, rows, tab, entries = nil, {}, "bags", {}
local scrollOffset = 0

local function Backdrop(f, a)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.07, a or 0.95)
    f:SetBackdropBorderColor(0.75, 0.62, 0.25, 1)
end

local function QualityColor(q)
    if ITEM_QUALITY_COLORS and q and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local function MakeRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(W - 44, ROWH)
    r:SetPoint("TOPLEFT", 14, -(i - 1) * ROWH)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROWH - 4, ROWH - 4)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetWidth(180)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.action = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.action:SetPoint("LEFT", 214, 0)
    r.action:SetWidth(130)
    r.action:SetJustifyH("LEFT")
    r.vend = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.vend:SetPoint("RIGHT", -190, 0)
    r.vend:SetJustifyH("RIGHT")
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("RIGHT", -95, 0)
    r.value:SetJustifyH("RIGHT")
    r.gain = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.gain:SetPoint("RIGHT", -4, 0)
    r.gain:SetJustifyH("RIGHT")
    r:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.entry.link then GameTooltip:SetHyperlink(self.entry.link) else GameTooltip:SetItemByID(self.entry.itemID) end
        local v = self.entry.verdict
        if v and v.reason then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(v.reason, 1, 1, 1, true)
        end
        if tab == "room" then
            GameTooltip:AddLine("Left-click: pick it up (then click outside your bags to destroy it)", 0.6, 0.6, 0.6)
            if (self.entry.quality or 0) <= 1 then
                GameTooltip:AddLine("Shift-click: delete it now", 1, 0.5, 0.5)
            end
            GameTooltip:AddLine("Right-click: keep it (never suggest it again)", 0.6, 0.6, 0.6)
        end
        if tab == "bags" then
            GameTooltip:AddLine(self.entry.ignored and "Right-click: allow selling again" or "Right-click: never sell this item", 0.6, 0.6, 0.6)
            if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
                GameTooltip:AddLine("Left-click: search for it on the auction house", 0.6, 0.6, 0.6)
            end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
        local e = self.entry
        if not e then return end
        if tab == "room" then
            if button == "RightButton" then
                ns.db.ignore[e.itemID] = true
                ns.Print((e.link or e.name) .. " will be kept. Undo in settings.")
                ns.RefreshAll()
            elseif IsShiftKeyDown() and (e.quality or 0) <= 1 then
                ns.DeleteSlot(e)
            else
                ns.PickupSlot(e)
            end
            return
        end
        if button == "RightButton" and tab == "bags" then
            ns.db.ignore[e.itemID] = (not ns.db.ignore[e.itemID]) or nil
            ns.RefreshAll()
        elseif button == "LeftButton" and AuctionHouseFrame and AuctionHouseFrame:IsShown() and C_AuctionHouse then
            local key = C_AuctionHouse.MakeItemKey(e.itemID)
            pcall(C_AuctionHouse.SendSearchQuery, key, {}, true)
        end
    end)
    return r
end

local function FillRows()
    for i = 1, VISIBLE do
        local r, e = rows[i], entries[i + scrollOffset]
        r.entry = e
        if not e then
            r:Hide()
        else
            r:Show()
            r.stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
            r.icon:SetTexture(e.icon or (e.verdict and e.verdict.info and e.verdict.info.icon) or 134400)
            local nm = e.name or (e.link and e.link:match("%[(.-)%]")) or ("item " .. e.itemID)
            r.name:SetText(nm .. ((e.count or 1) > 1 and ("  |cffaaaaaax" .. e.count .. "|r") or ""))
            r.name:SetTextColor(QualityColor(e.quality or (e.verdict and e.verdict.info and e.verdict.info.quality)))
            local v = e.verdict or {}
            local act = ns.ACTION_TEXT[v.action] or ""
            if e.ignored then act = "|cff8080ffKeeping|r" end
            if v.timing == "high" then act = act .. " |cff40ff40(high!)|r" end
            r.action:SetText(act)
            -- what a vendor would pay for this row
            local vendTotal
            if tab == "loot" then
                vendTotal = e.vendor
            elseif v.vendor ~= nil then
                vendTotal = v.vendorTotal
            end
            if vendTotal == nil then
                r.vend:SetText("|cff888888?|r")
            elseif vendTotal == 0 then
                r.vend:SetText("|cff888888-|r")
            else
                r.vend:SetText(ns.Money(vendTotal))
            end
            if tab == "room" then
                local idx = i + scrollOffset
                r.action:SetText(idx <= 3 and "|cffff8060Throw away first|r" or "")
                r.value:SetText(ns.Money(e.value or 0))
                r.gain:SetText("")
            elseif tab == "loot" then
                r.value:SetText(ns.Money(e.value or 0))
                r.gain:SetText("")
            else
                r.value:SetText(v.action == "none" and "|cff888888-|r" or ns.Money(v.best or 0))
                if (v.action == "auction" or v.action == "hold") and v.gain then
                    r.gain:SetText("|cff40ff40+" .. ns.Money(v.gain) .. "|r")
                else
                    r.gain:SetText("")
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local ORDER = { auction = 1, hold = 2, vendor = 3, none = 4 }

function ns.RefreshAll()
    if ns.RefreshAHPanel then ns.RefreshAHPanel() end
    if not F or not F:IsShown() then return end
    if tab == "bags" then
        entries = ns.ScanBags()
        table.sort(entries, function(a, b)
            local oa, ob = ORDER[a.verdict.action] or 9, ORDER[b.verdict.action] or 9
            if a.ignored ~= b.ignored then return not a.ignored end
            if oa ~= ob then return oa < ob end
            return (a.verdict.best or 0) > (b.verdict.best or 0)
        end)
        local vend, vendN, auct, auctN = 0, 0, 0, 0
        local allVendor, unknown = 0, 0
        for _, e in ipairs(entries) do
            local v = e.verdict
            if not e.ignored then
                if v.action == "vendor" then vend = vend + v.vendorTotal; vendN = vendN + 1 end
                if v.action == "auction" or v.action == "hold" then auct = auct + v.auctionTotal; auctN = auctN + 1 end
                if v.vendor == nil and v.action ~= "none" then
                    unknown = unknown + 1
                else
                    allVendor = allVendor + (v.vendorTotal or 0)
                end
            end
        end
        F.summary:SetText(string.format("|cff40ff40Auction: %d item(s), about %s|r     |cffc0c0c0Vendor: %d item(s), %s|r",
            auctN, ns.Money(auct), vendN, ns.Money(vend)))
        local advised = vend + auct
        F.summary2:SetText(string.format("Sell everything to a vendor: |cffffffff%s|r     Following Goldsight: |cffffffff%s|r%s%s",
            ns.Money(allVendor), ns.Money(advised),
            advised > allVendor and ("  |cff40ff40(+" .. ns.Money(advised - allVendor) .. ")|r") or "",
            unknown > 0 and ("     |cff888888" .. unknown .. " with unknown vendor price|r") or ""))
        F.sellBtn:Show()
        F.resetBtn:Hide()
        F.stackBtn:Hide()
        F.sellBtn:SetEnabled(ns.atMerchant)
        F.sellBtn:SetText(ns.atMerchant and "Sell vendor items" or "Sell vendor items (open a vendor)")
        F.colValue:SetText("Best value")
        F.colGain:SetText("vs vendor")
    elseif tab == "room" then
        entries = ns.SlotCandidates()
        local free, total = ns.FreeSlots()
        local _, freed = ns.StackPlan()
        F.summary:SetText(string.format("Free bag slots: %s%d|r of %d.   %s   Cheapest slots are at the top.",
            free == 0 and "|cffff4040" or "|cff40ff40", free, total,
            freed > 0 and ("|cff40ff40Stacking frees " .. freed .. " for free.|r") or "No split stacks."))
        F.sellBtn:Hide()
        F.resetBtn:Hide()
        F.stackBtn:Show()
        F.stackBtn:SetEnabled(freed > 0)
        F.stackBtn:SetText(freed > 0 and ("Stack up (frees " .. freed .. ")") or "Stack up (nothing to merge)")
        local allVendor = 0
        for _, e in ipairs(entries) do allVendor = allVendor + (e.verdict.vendorTotal or 0) end
        F.summary2:SetText("Everything listed here sells to a vendor for " .. ns.Money(allVendor) .. ".")
        F.colValue:SetText("Worth")
        F.colGain:SetText("")
    else
        local s = ns.session
        entries = {}
        for _, e in ipairs(s.order) do
            local info = ns.ItemInfo(e.link or e.itemID)
            entries[#entries + 1] = { itemID = e.itemID, link = e.link, count = e.count, value = e.value, vendor = e.vendor,
                                      name = info and info.name, icon = info and info.icon, quality = info and info.quality,
                                      verdict = { action = e.action } }
        end
        table.sort(entries, function(a, b) return a.value > b.value end)
        local st = ns.SessionStats()
        F.summary:SetText(string.format("Session %dm   Gold looted %s   Items worth %s   |cffffd700%s / hour|r",
            st.minutes, ns.Money(st.gold), ns.Money(st.items), ns.Money(st.perHour)))
        F.summary2:SetText(string.format("If you vendored all of it: %s     Following Goldsight: %s",
            ns.Money(st.vendor), ns.Money(st.items)))
        F.sellBtn:Hide()
        F.resetBtn:Show()
        F.stackBtn:Hide()
        F.colValue:SetText("Worth")
        F.colGain:SetText("")
    end
    local maxOff = math.max(0, #entries - VISIBLE)
    if scrollOffset > maxOff then scrollOffset = maxOff end
    F.empty:SetShown(#entries == 0)
    F.empty:SetText((tab == "bags" and "Your bags are empty.") or (tab == "room" and "Nothing in your bags is safe to suggest throwing away.")
        or "Nothing looted yet this session.")
    for name, b in pairs(F.tabs) do b.sel:SetShown(name == tab) end
    FillRows()
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
local function Build()
    F = CreateFrame("Frame", "GoldsightFrame", UIParent, "BackdropTemplate")
    F:SetSize(W, H)
    F:SetPoint("CENTER", 220, 0)
    F:SetFrameStrata("HIGH")
    F:SetMovable(true)
    F:SetClampedToScreen(true)
    F:EnableMouse(true)
    F:RegisterForDrag("LeftButton")
    F:SetScript("OnDragStart", F.StartMoving)
    F:SetScript("OnDragStop", F.StopMovingOrSizing)
    Backdrop(F)
    tinsert(UISpecialFrames, "GoldsightFrame")

    local icon = F:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "icon")
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 14, -10)
    local title = F:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Goldsight")
    local close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    F.tabs = {}
    for i, t in ipairs({ { "bags", "Your bags" }, { "room", "Make room" }, { "loot", "Loot this session" } }) do
        local b = CreateFrame("Button", nil, F)
        b:SetSize(130, 22)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 134, -44)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.45)
        b.sel = b:CreateTexture(nil, "BORDER")
        b.sel:SetPoint("BOTTOMLEFT")
        b.sel:SetPoint("BOTTOMRIGHT")
        b.sel:SetHeight(2)
        b.sel:SetColorTexture(1, 0.82, 0, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("CENTER")
        fs:SetText(t[2])
        b:SetScript("OnClick", function() tab = t[1]; scrollOffset = 0; ns.RefreshAll() end)
        F.tabs[t[1]] = b
    end

    F.summary = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    F.summary:SetPoint("TOPLEFT", 16, -76)
    F.summary:SetPoint("TOPRIGHT", -16, -76)
    F.summary:SetJustifyH("LEFT")
    F.summary2 = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    F.summary2:SetPoint("TOPLEFT", 16, -94)
    F.summary2:SetPoint("TOPRIGHT", -16, -94)
    F.summary2:SetJustifyH("LEFT")
    F.summary2:SetTextColor(0.85, 0.85, 0.85)

    local function Col(text, x, anchor)
        local fs = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint(anchor or "TOPLEFT", x, -118)
        fs:SetText(text)
        return fs
    end
    Col("Item", 44)
    Col("Advice", 228)
    Col("Vendor", -220, "TOPRIGHT")
    F.colValue = Col("Best value", -125, "TOPRIGHT")
    F.colGain = Col("vs vendor", -34, "TOPRIGHT")

    local list = CreateFrame("Frame", nil, F)
    list:SetPoint("TOPLEFT", 0, -134)
    list:SetSize(W, ROWH * VISIBLE)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d)
        scrollOffset = math.max(0, math.min(math.max(0, #entries - VISIBLE), scrollOffset - d * 3))
        FillRows()
    end)
    for i = 1, VISIBLE do rows[i] = MakeRow(list, i) end
    F.empty = F:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    F.empty:SetPoint("TOP", list, "TOP", 0, -40)

    F.sellBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    F.sellBtn:SetSize(250, 24)
    F.sellBtn:SetPoint("BOTTOMLEFT", 14, 14)
    F.sellBtn:SetScript("OnClick", ns.SellVendorItems)
    F.sellBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Sells items marked 'Sell to vendor', 12 at a time so they stay in your buyback tab.", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Skips: items you've set to keep, equipment-set items, and anything above the quality limit in settings.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    F.sellBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    F.stackBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    F.stackBtn:SetSize(220, 24)
    F.stackBtn:SetPoint("BOTTOMLEFT", 14, 14)
    F.stackBtn:SetScript("OnClick", function() ns.StackUp() end)
    F.stackBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Merges split stacks of the same item, freeing bag slots without losing anything.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    F.stackBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    F.stackBtn:Hide()

    F.resetBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    F.resetBtn:SetSize(140, 24)
    F.resetBtn:SetPoint("BOTTOMLEFT", 14, 14)
    F.resetBtn:SetText("Start new session")
    F.resetBtn:SetScript("OnClick", ns.ResetSession)

    local scanInfo = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scanInfo:SetPoint("BOTTOMRIGHT", -16, 20)
    F.scanInfo = scanInfo
    F:SetScript("OnShow", function()
        local last = ns.db.lastFullScan
        scanInfo:SetText(last and ("Last full scan " .. ns.Ago(time() - last)) or "No full scan yet: open the auction house")
        ns.RefreshAll()
    end)
    F:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t > 30 and tab == "loot" then self.t = 0; ns.RefreshAll() end
    end)
    F:Hide()
end

function ns.ShowTab(name)
    if not F then Build() end
    tab = name
    scrollOffset = 0
    F:Show()
    ns.RefreshAll()
end

function ns.Toggle()
    if not F then Build() end
    if F:IsShown() then F:Hide() else F:Show() end
end

-- keep bag advice current
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.4, function() pending = false; ns.RefreshAll() end)
end
ns.On("BAG_UPDATE_DELAYED", Soon)
ns.On("GET_ITEM_INFO_RECEIVED", function() if F and F:IsShown() then Soon() end end)

------------------------------------------------------------------------
-- Panel on the auction house
------------------------------------------------------------------------
local ahPanel
local function BuildAHPanel()
    if ahPanel or not AuctionHouseFrame then return end
    local p = CreateFrame("Frame", nil, AuctionHouseFrame, "BackdropTemplate")
    p:SetSize(200, 104)
    p:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -24)
    Backdrop(p, 0.95)
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -10)
    t:SetText("Goldsight")
    p.info = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.info:SetPoint("TOP", 0, -28)
    p.info:SetWidth(184)
    p.scan = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.scan:SetSize(170, 22)
    p.scan:SetPoint("TOP", 0, -50)
    p.scan:SetScript("OnClick", ns.StartFullScan)
    p.scan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reads every auction at once and prices everything. The game allows this once every 15 minutes.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.scan:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local open = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    open:SetSize(170, 22)
    open:SetPoint("TOP", 0, -74)
    open:SetText("What should I sell?")
    open:SetScript("OnClick", function()
        if not F then Build() end
        tab = "bags"
        F:Show()
        ns.RefreshAll()
    end)
    p:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t > 1 then self.t = 0; ns.RefreshAHPanel() end
    end)
    ahPanel = p
end

function ns.RefreshAHPanel(done, total)
    if not ahPanel then return end
    local n = 0
    for _ in pairs(ns.db.prices) do n = n + 1 end
    local scan = ns.scan
    if scan.state == "reading" and done and total then
        ahPanel.info:SetText(string.format("Reading auctions... %d%%", math.floor(done / total * 100)))
        ahPanel.scan:SetEnabled(false)
        ahPanel.scan:SetText("Scanning...")
        return
    elseif scan.state == "waiting" then
        ahPanel.info:SetText("Downloading auctions...")
        ahPanel.scan:SetEnabled(false)
        ahPanel.scan:SetText("Scanning...")
        return
    end
    local last = ns.db.lastFullScan
    ahPanel.info:SetText(string.format("%d items priced\n%s", n, last and ("full scan " .. ns.Ago(time() - last)) or "no full scan yet"))
    local wait = ns.FullScanWait()
    ahPanel.scan:SetEnabled(wait == 0)
    ahPanel.scan:SetText(wait == 0 and "Full scan" or string.format("Full scan in %d:%02d", wait / 60, wait % 60))
end

ns.On("AUCTION_HOUSE_SHOW", function()
    BuildAHPanel()
    if ahPanel then ahPanel:Show(); ns.RefreshAHPanel() end
end)

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local mm
local function PlaceMM()
    local a = math.rad(ns.db.minimap.angle or 150)
    local r = (Minimap:GetWidth() / 2) + 10
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
local function UpdateMM()
    if not mm then return end
    if ns.db.minimap.hide then mm:Hide() else mm:Show(); PlaceMM() end
end
local function BuildMM()
    if mm or not Minimap then return end
    local b = CreateFrame("Button", "GoldsightMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(ns.MEDIA .. "icon")
    ic:SetSize(21, 21)
    ic:SetPoint("TOPLEFT", 6, -5)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if Settings and Settings.OpenToCategory and ns.settingsID then
                pcall(Settings.OpenToCategory, ns.settingsID)
            else
                ns.Print("type /gs options")
            end
        else
            ns.Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            if not mx then return end
            local cx, cy = GetCursorPosition()
            local sc = Minimap:GetEffectiveScale()
            local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
            ns.db.minimap.angle = math.deg(atan2(cy / sc - my, cx / sc - mx))
            PlaceMM()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Goldsight", 1, 0.82, 0)
        local st = ns.SessionStats()
        GameTooltip:AddLine("This session: " .. ns.Money(st.total) .. " (" .. ns.Money(st.perHour) .. "/hour)", 1, 1, 1)
        GameTooltip:AddLine("Left-click: what to sell", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mm = b
    UpdateMM()
end

------------------------------------------------------------------------
-- Settings (Options > AddOns > Goldsight)
------------------------------------------------------------------------
local function BuildSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local p = CreateFrame("Frame")
    local o = ns.db.opt
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("Goldsight")
    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
    sub:SetText("Tells you what to auction and what to vendor. Open it with /gs or the minimap button.")

    local y = -60
    local refreshers = {}
    local function Check(label, key, onChange)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, y)
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(label)
        cb:SetScript("OnClick", function(self)
            o[key] = self:GetChecked() and true or false
            if onChange then onChange() end
        end)
        refreshers[#refreshers + 1] = function() cb:SetChecked(o[key]) end
        y = y - 30
    end
    -- number box: shown/edited in "display" units
    local function Number(label, get, set, hint)
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 20, y - 4)
        fs:SetText(label)
        local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        eb:SetSize(70, 20)
        eb:SetPoint("TOPLEFT", 330, y)
        eb:SetAutoFocus(false)
        local h = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("LEFT", eb, "RIGHT", 8, 0)
        h:SetText(hint or "")
        local function apply(self)
            local v = tonumber(self:GetText())
            if v then set(v) end
            self:SetText(tostring(get()))
            self:ClearFocus()
            ns.RefreshAll()
        end
        eb:SetScript("OnEnterPressed", apply)
        eb:SetScript("OnEditFocusLost", apply)
        refreshers[#refreshers + 1] = function() eb:SetText(tostring(get())) end
        y = y - 30
    end

    Check("Show advice in item tooltips", "tooltip")
    Check("Tell me in chat when a valuable item drops", "lootAlerts")
    Check("Show the minimap button", "showMM", function() ns.db.minimap.hide = not o.showMM; UpdateMM() end)
    o.showMM = not ns.db.minimap.hide
    y = y - 6
    Number("Only auction if it beats the vendor by at least", function() return math.floor(o.minMargin * 100 + 0.5) end,
        function(v) o.minMargin = math.max(0, v) / 100 end, "%")
    Number("...and gains at least this much per stack", function() return o.minProfit / 100 end,
        function(v) o.minProfit = math.max(0, math.floor(v * 100)) end, "silver")
    Number("Auction house cut", function() return math.floor(o.cut * 100 + 0.5) end,
        function(v) o.cut = math.max(0, math.min(50, v)) / 100 end, "%")
    Number("Auction length for the deposit estimate", function() return o.durationHours end,
        function(v) o.durationHours = (v <= 12 and 12) or (v <= 24 and 24) or 48 end, "hours (12, 24 or 48)")
    Number("Valuable drop alert from", function() return o.alertThreshold / 10000 end,
        function(v) o.alertThreshold = math.max(0, math.floor(v * 10000)) end, "gold")
    Number("'Sell vendor items' sells up to quality", function() return o.sellMaxQuality end,
        function(v) o.sellMaxQuality = math.max(0, math.min(4, math.floor(v))) end, "0 gray, 1 white, 2 green, 3 blue, 4 purple")

    local reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    reset:SetSize(200, 22)
    reset:SetPoint("TOPLEFT", 20, y - 10)
    reset:SetText("Forget 'never sell' items")
    reset:SetScript("OnClick", function() wipe(ns.db.ignore); ns.RefreshAll(); ns.Print("cleared your keep list.") end)

    p:SetScript("OnShow", function()
        o.showMM = not ns.db.minimap.hide
        for _, f in ipairs(refreshers) do f() end
    end)
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, p, "Goldsight")
    if ok and cat then
        pcall(Settings.RegisterAddOnCategory, cat)
        ns.settingsID = cat.GetID and cat:GetID() or cat.ID
    end
end

ns.On("PLAYER_LOGIN", function()
    BuildMM()
    pcall(BuildSettings)
    ns.Print("loaded. Left-click the minimap coin or type /gs to see what to sell.")
end)

SLASH_GOLDSIGHT1 = "/gs"
SLASH_GOLDSIGHT2 = "/goldsight"
SlashCmdList.GOLDSIGHT = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "scan" then
        ns.StartFullScan()
    elseif msg == "room" then
        ns.ShowTab("room")
        ns.CheckFullBags(true)
    elseif msg == "reset" then
        ns.ResetSession()
        ns.Print("new loot session started.")
    elseif msg == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        UpdateMM()
    elseif msg == "options" then
        if Settings and Settings.OpenToCategory and ns.settingsID then pcall(Settings.OpenToCategory, ns.settingsID) end
    elseif msg == "help" then
        ns.Print("/gs  open the window   /gs room  what to throw away   /gs scan  full auction scan   /gs reset  new loot session")
        ns.Print("/gs minimap  show/hide the button   /gs options  settings")
    else
        ns.Toggle()
    end
end
