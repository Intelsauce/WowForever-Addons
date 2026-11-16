-- Coinpurse: your gold (and tracked currencies) on screen, with session and
-- daily change, gold per hour, and every character's gold on hover.
-- Drag to move. Right-click for options. /cp for commands.

local ADDON_NAME = ...
local DB, CHAR
local bar
local session = { start = nil, money = nil }

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

local function Print(msg) print("|cffffd700Coinpurse:|r " .. msg) end

local function Commas(n)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- 1234567 -> "123g 45s 67c" with coin icons; signed = show +/-
local function Money(copper, signed, short)
    copper = math.floor(copper or 0)
    local sign = ""
    if copper < 0 then sign = "-" elseif signed and copper > 0 then sign = "+" end
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = Commas(g) .. GOLD end
    if s > 0 and not (short and g >= 100) then parts[#parts + 1] = s .. SILVER end
    if (c > 0 or (g == 0 and s == 0)) and not (short and g > 0) then parts[#parts + 1] = c .. COPPER end
    return sign .. table.concat(parts, " ")
end

local function Today() return date("%Y-%m-%d") end

------------------------------------------------------------------------
-- Tracking
------------------------------------------------------------------------
local function Save()
    local money = GetMoney()
    CHAR.money = money
    CHAR.seen = time()
    if CHAR.day ~= Today() then
        CHAR.day = Today()
        CHAR.dayStart = money
    end
end

local function BagWorth()
    -- uses Goldsight's advice if it's installed
    if not (GoldsightNS and GoldsightNS.ScanBags and GoldsightNS.db) then return nil end
    local ok, entries = pcall(GoldsightNS.ScanBags)
    if not ok or not entries then return nil end
    local total = 0
    for _, e in ipairs(entries) do
        if not e.ignored and e.verdict and e.verdict.best then total = total + e.verdict.best end
    end
    return total
end

------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------
local function TrackedCurrencies()
    local list = {}
    if C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
        for i = 1, 5 do
            local ok, info = pcall(C_CurrencyInfo.GetBackpackCurrencyInfo, i)
            if ok and info and info.name then list[#list + 1] = info end
        end
    end
    return list
end

local function Update()
    if not bar or not CHAR then return end
    Save()
    local money = GetMoney()
    local text = Money(money, false, DB.short)
    if DB.showSession and session.money then
        local diff = money - session.money
        if diff ~= 0 then
            local col = diff > 0 and "|cff40ff40" or "|cffff5050"
            text = text .. "  " .. col .. Money(diff, true, true) .. "|r"
        end
    end
    if DB.showCurrencies then
        for _, c in ipairs(TrackedCurrencies()) do
            text = text .. "   |T" .. (c.iconFileID or 134400) .. ":12:12:0:0|t " .. Commas(c.quantity or 0)
        end
    end
    bar.text:SetText(text)
    bar:SetWidth(math.max(80, bar.text:GetStringWidth() + 20))
end

local function ShowTooltip(self)
    local money = GetMoney()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Coinpurse", 1, 0.82, 0)
    GameTooltip:AddDoubleLine("On this character", Money(money), 1, 1, 1, 1, 1, 1)
    if session.money then
        local diff = money - session.money
        local mins = math.max(1, (time() - session.start) / 60)
        GameTooltip:AddDoubleLine("This session (" .. math.floor(mins) .. "m)", Money(diff, true), 0.8, 0.8, 0.8,
            diff >= 0 and 0.3 or 1, diff >= 0 and 1 or 0.3, 0.3)
        if mins >= 5 then
            GameTooltip:AddDoubleLine("Per hour", Money(diff / mins * 60, true), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    if CHAR.dayStart then
        local d = money - CHAR.dayStart
        GameTooltip:AddDoubleLine("Today", Money(d, true), 0.8, 0.8, 0.8, d >= 0 and 0.3 or 1, d >= 0 and 1 or 0.3, 0.3)
    end
    local worth = BagWorth()
    if worth then
        GameTooltip:AddDoubleLine("Your bags are worth", Money(worth), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Gold + bags", Money(money + worth), 0.8, 0.8, 0.8, 1, 0.82, 0)
    end

    -- every character on this realm
    local realm = GetRealmName()
    local chars, total = {}, 0
    for name, c in pairs(DB.realms[realm] or {}) do
        chars[#chars + 1] = { name = name, money = c.money or 0, class = c.class }
        total = total + (c.money or 0)
    end
    if #chars > 1 then
        table.sort(chars, function(a, b) return a.money > b.money end)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Characters on " .. realm, 1, 0.82, 0)
        for _, c in ipairs(chars) do
            local col = (RAID_CLASS_COLORS and c.class and RAID_CLASS_COLORS[c.class]) or { r = 1, g = 1, b = 1 }
            GameTooltip:AddDoubleLine(c.name, Money(c.money), col.r, col.g, col.b, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Total", Money(total), 1, 0.82, 0, 1, 0.82, 0)
    end

    local cur = TrackedCurrencies()
    if #cur > 0 then
        GameTooltip:AddLine(" ")
        for _, c in ipairs(cur) do
            GameTooltip:AddDoubleLine("|T" .. (c.iconFileID or 134400) .. ":14:14:0:0|t " .. c.name, Commas(c.quantity or 0), 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(DB.locked and "Right-click for options" or "Drag to move. Right-click for options.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local menu
local function Options(anchor)
    if not menu then
        menu = CreateFrame("Frame", "CoinpurseMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("DIALOG")
        menu:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        menu:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
        menu.buttons = {}
        menu:EnableMouse(true)
        tinsert(UISpecialFrames, "CoinpurseMenu")
    end
    local items = {
        { DB.locked and "Unlock (allow dragging)" or "Lock in place", function() DB.locked = not DB.locked end },
        { (DB.showSession and "Hide" or "Show") .. " session change", function() DB.showSession = not DB.showSession end },
        { (DB.showCurrencies and "Hide" or "Show") .. " tracked currencies", function() DB.showCurrencies = not DB.showCurrencies end },
        { (DB.short and "Show" or "Hide") .. " silver/copper when rich", function() DB.short = not DB.short end },
        { "Size: smaller", function() DB.scale = math.max(0.6, (DB.scale or 1) - 0.1); bar:SetScale(DB.scale) end },
        { "Size: bigger", function() DB.scale = math.min(2, (DB.scale or 1) + 0.1); bar:SetScale(DB.scale) end },
        { "Start a new session", function() session.start, session.money = time(), GetMoney(); Print("new session started.") end },
        { "Close", function() end },
    }
    for i, it in ipairs(items) do
        local b = menu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetSize(200, 18)
            b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 18)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.25)
            menu.buttons[i] = b
        end
        b.text:SetText(it[1])
        b:SetScript("OnClick", function() menu:Hide(); it[2](); Update() end)
        b:Show()
    end
    menu:SetSize(216, 16 + #items * 18)
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
    menu:Show()
end

local function Build()
    bar = CreateFrame("Button", "CoinpurseBar", UIParent, "BackdropTemplate")
    bar:SetSize(160, 24)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:RegisterForClicks("RightButtonUp")
    bar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bar:SetBackdropColor(0, 0, 0, 0.65)
    bar:SetBackdropBorderColor(0.8, 0.65, 0.2, 0.9)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.text:SetPoint("CENTER", 0, 0)
    bar:SetScale(DB.scale or 1)
    local p = DB.pos
    bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])

    bar:SetScript("OnDragStart", function(self)
        if not DB.locked then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint(1)
        DB.pos = { point, rel, x, y }
    end)
    bar:SetScript("OnClick", function(self) Options(self) end)
    bar:SetScript("OnEnter", ShowTooltip)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if DB.hidden then bar:Hide() end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "CURRENCY_DISPLAY_UPDATE", "PLAYER_LOGOUT" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        CoinpurseDB = CoinpurseDB or {}
        DB = CoinpurseDB
        DB.realms = DB.realms or {}
        DB.pos = DB.pos or { "BOTTOMRIGHT", "BOTTOMRIGHT", -24, 130 }
        if DB.showSession == nil then DB.showSession = true end
        if DB.showCurrencies == nil then DB.showCurrencies = true end
        if DB.locked == nil then DB.locked = false end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not CHAR then
            local realm, name = GetRealmName(), UnitName("player")
            DB.realms[realm] = DB.realms[realm] or {}
            DB.realms[realm][name] = DB.realms[realm][name] or {}
            CHAR = DB.realms[realm][name]
            local _, class = UnitClass("player")
            CHAR.class = class
            session.start, session.money = time(), GetMoney()
            Build()
        end
        Update()
    elseif event == "PLAYER_LOGOUT" then
        if CHAR then Save() end
    else
        Update()
    end
end)

SLASH_COINPURSE1 = "/cp"
SLASH_COINPURSE2 = "/coinpurse"
SlashCmdList.COINPURSE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "lock" then
        DB.locked = true; Print("locked.")
    elseif msg == "unlock" then
        DB.locked = false; Print("unlocked: drag it where you like.")
    elseif msg == "reset" then
        DB.pos = { "BOTTOMRIGHT", "BOTTOMRIGHT", -24, 130 }
        DB.scale = 1
        bar:SetScale(1)
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -24, 130)
        Print("moved back to the bottom right.")
    elseif msg == "new" then
        session.start, session.money = time(), GetMoney(); Print("new session started.")
    elseif msg == "show" or msg == "hide" or msg == "toggle" then
        DB.hidden = not bar:IsShown() and false or true
        if msg == "show" then DB.hidden = false elseif msg == "hide" then DB.hidden = true end
        bar:SetShown(not DB.hidden)
    else
        Print("/cp lock  /cp unlock  /cp reset (move it back)  /cp new (new session)  /cp hide  /cp show")
        Print("Right-click the gold bar for more options.")
    end
    Update()
end
