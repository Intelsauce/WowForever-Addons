-- Snapcast v1.0
-- Build macros by snapping blocks together, Scratch-style.
-- /snap, /snapcast or the minimap button to open.

local ADDON_NAME, ns = ...
local DB

local QUESTION_ICON = 134400
local MAX_CHARS = 255
local ROW = 40 -- tall enough for a big jigsaw knob hole above the text
local GAP = 0 -- blocks touch, so their notches lock together
local CANVAS_W = 556

------------------------------------------------------------------------
-- Definitions
------------------------------------------------------------------------
-- bright toy-brick colours
local COLORS = {
    spell  = { 0.05, 0.40, 0.82 }, -- blue
    item   = { 0.08, 0.58, 0.30 }, -- green
    attack = { 0.80, 0.12, 0.12 }, -- red
    chat   = { 0.95, 0.55, 0.08 }, -- orange
    ["if"] = { 0.98, 0.78, 0.10 }, -- yellow
    seq    = { 0.28, 0.58, 0.92 }, -- light blue
    stop   = { 0.64, 0.66, 0.68 }, -- light grey
    raw    = { 0.36, 0.38, 0.42 }, -- dark grey
}

local RESETS = {
    { id = "",          label = "never" },
    { id = "target",    label = "new target" },
    { id = "combat",    label = "leaving combat" },
    { id = "shift",     label = "holding Shift" },
    { id = "6",         label = "6 sec idle" },
    { id = "12",        label = "12 sec idle" },
    { id = "30",        label = "30 sec idle" },
    { id = "target/6",  label = "new target or 6 sec" },
    { id = "combat/12", label = "leaving combat or 12 sec" },
}

local CAST_UNITS = {
    { id = "default",      label = "target" },
    { id = "mouseover",    label = "mouseover" },
    { id = "focus",        label = "focus" },
    { id = "player",       label = "me" },
    { id = "cursor",       label = "cursor (ground)" },
    { id = "pet",          label = "my pet" },
    { id = "targettarget", label = "target's target" },
}
local COND_UNITS = {
    { id = "target",       label = "target" },
    { id = "mouseover",    label = "mouseover" },
    { id = "focus",        label = "focus" },
    { id = "player",       label = "me" },
    { id = "pet",          label = "my pet" },
    { id = "targettarget", label = "target's target" },
}
local UNIT_CHECKS = {
    { key = "exists", label = "exists" },
    { key = "help",   label = "is friendly" },
    { key = "harm",   label = "is an enemy" },
    { key = "dead",   label = "is dead" },
    { key = "nodead", label = "is alive" },
}
local COND_GROUPS = {
    { title = "Modifier key", items = {
        { key = "mod:shift", label = "Shift is held" },
        { key = "mod:ctrl",  label = "Ctrl is held" },
        { key = "mod:alt",   label = "Alt is held" },
        { key = "nomod",     label = "no modifier held" },
    } },
    { title = "Combat", items = {
        { key = "combat",   label = "I'm in combat" },
        { key = "nocombat", label = "I'm out of combat" },
    } },
    { title = "Stance / form", items = {
        { key = "stance:0", label = "no stance/form" },
        { key = "stance:1", label = "stance/form 1" },
        { key = "stance:2", label = "stance/form 2" },
        { key = "stance:3", label = "stance/form 3" },
        { key = "stance:4", label = "stance/form 4" },
        { key = "stance:5", label = "stance/form 5" },
        { key = "stance:6", label = "stance/form 6" },
    } },
    { title = "Other", items = {
        { key = "mounted",    label = "I'm mounted" },
        { key = "swimming",   label = "I'm swimming" },
        { key = "stealth",    label = "I'm stealthed" },
        { key = "group",      label = "I'm in a group" },
        { key = "group:raid", label = "I'm in a raid" },
        { key = "pet",        label = "I have a pet" },
        { key = "channeling", label = "I'm channeling" },
        { key = "nostealth",  label = "I'm not stealthed" },
        { key = "nopet",      label = "I have no pet" },
        { key = "btn:2",      label = "right-clicked" },
    } },
}
local CHANNELS = {
    { id = "s",  label = "say" },
    { id = "y",  label = "yell" },
    { id = "p",  label = "party" },
    { id = "ra", label = "raid" },
    { id = "i",  label = "instance" },
    { id = "e",  label = "emote" },
}

------------------------------------------------------------------------
-- Shapes
-- Every stack block has a notch on top. Round notches fit anywhere,
-- including inside an 'if'. Square notches (chat, if) only fit on the
-- main stack. Conditions are hexagons and spell slots are ovals.
------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\" .. (ADDON_NAME or "Snapcast") .. "\\media\\"
local CANVAS_BG = { 0.07, 0.07, 0.09 }
local NOTCH_X, NOTCH_W, NOTCH_H = 14, 40, 14 -- jigsaw knob position and size
local PAL_KNOB_W, PAL_KNOB_H = 28, 10           -- smaller knobs on the palette lists
local RADIUS = 4

local function SocketShape(node)
    if node.kind == "chat" or node.kind == "if" or node.kind == "raw" then return "square" end
    return "round"
end

local function NodesShape(nodes)
    for _, n in ipairs(nodes) do
        if SocketShape(n) == "square" then return "square" end
    end
    return "round"
end

local function TabTexture(shape)
    return MEDIA .. (shape == "square" and "knob_square" or "knob_round")
end

-- A rounded rectangle built from 3 strips and 4 corner textures.
local function NewRoundRect(f, layer, sub)
    local rr = {}
    for _, k in ipairs({ "top", "mid", "bot" }) do rr[k] = f:CreateTexture(nil, layer, nil, sub) end
    for _, k in ipairs({ "tl", "tr", "bl", "br" }) do
        local t = f:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(MEDIA .. "corner")
        rr[k] = t
    end
    rr.tl:SetTexCoord(0, 1, 0, 1)
    rr.tr:SetTexCoord(1, 0, 0, 1)
    rr.bl:SetTexCoord(0, 1, 1, 0)
    rr.br:SetTexCoord(1, 0, 1, 0)
    return rr
end

local function PaintRoundRect(rr, f, w, h, c, a, r)
    r = math.min(r or RADIUS, math.floor(math.min(w, h) / 2))
    a = a or 1
    local function put(t, x, y, tw, th)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        t:SetSize(math.max(tw, 0.01), math.max(th, 0.01))
    end
    put(rr.top, r, 0, w - 2 * r, r)
    put(rr.mid, 0, r, w, h - 2 * r)
    put(rr.bot, r, h - r, w - 2 * r, r)
    put(rr.tl, 0, 0, r, r)
    put(rr.tr, w - r, 0, r, r)
    put(rr.bl, 0, h - r, r, r)
    put(rr.br, w - r, h - r, r, r)
    for _, k in ipairs({ "top", "mid", "bot" }) do rr[k]:SetColorTexture(c[1], c[2], c[3], a) end
    for _, k in ipairs({ "tl", "tr", "bl", "br" }) do rr[k]:SetVertexColor(c[1], c[2], c[3], a) end
end

------------------------------------------------------------------------
-- Puzzle pieces: plastic shading; the knob/hole shapes are drawn separately.
-- Round knobs fit anywhere; square knobs only fit on the main stack.
------------------------------------------------------------------------
local function IsLight(c)
    return (0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]) > 0.6
end

local function NewBrickParts(f)
    f.body = NewRoundRect(f, "BACKGROUND", 1)
    f.hi = f:CreateTexture(nil, "BORDER") -- light edge on top
    f.hi:SetPoint("TOPLEFT", 2, -1)
    f.hi:SetPoint("TOPRIGHT", -2, -1)
    f.hi:SetHeight(2)
    f.sh = f:CreateTexture(nil, "BORDER") -- shadow along the bottom
    f.sh:SetPoint("BOTTOMLEFT", 2, 1)
    f.sh:SetPoint("BOTTOMRIGHT", -2, 1)
    f.sh:SetHeight(3)
end

local function PaintBrick(f, w, h, c, shape, alpha)
    alpha = alpha or 1
    PaintRoundRect(f.body, f, w, h, c, alpha, 3)
    f.hi:SetColorTexture(1, 1, 1, 0.30)
    f.sh:SetColorTexture(0, 0, 0, 0.30)
end

-- the "table" the pieces sit on: one flat colour, so holes can be cut by painting it
local function SetTable(tex)
    tex:SetColorTexture(CANVAS_BG[1], CANVAS_BG[2], CANVAS_BG[3], 1)
end

local function Lookup(list, field)
    local t = {}
    for _, v in ipairs(list) do t[v[field]] = v.label end
    return t
end
local CAST_UNIT_LABEL = Lookup(CAST_UNITS, "id")
local COND_UNIT_LABEL = Lookup(COND_UNITS, "id")
local UNIT_CHECK_LABEL = Lookup(UNIT_CHECKS, "key")
local CHANNEL_LABEL = Lookup(CHANNELS, "id")
local RESET_LABEL = Lookup(RESETS, "id")
local COND_LABEL = {}
for _, g in ipairs(COND_GROUPS) do
    for _, it in ipairs(g.items) do COND_LABEL[it.key] = it.label end
end

COND_LABEL["stance:1/3"] = "Bear or Cat form"
COND_LABEL["nomounted"] = "I'm not mounted"

local function CondLabel(c)
    if c.unit then
        return (COND_UNIT_LABEL[c.unit] or c.unit) .. " " .. (UNIT_CHECK_LABEL[c.key] or c.key)
    end
    return COND_LABEL[c.key] or c.key
end

local function Print(msg)
    print("|cffffcc33Snapcast:|r " .. msg)
end

local function CopyTable(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = CopyTable(v) end
    return c
end

local trim = ns.trim

------------------------------------------------------------------------
-- Spells / items
------------------------------------------------------------------------
local function SpellNameIcon(idOrName)
    if type(idOrName) == "string" then
        local base, r = idOrName:match("^(.-)%s*(%(%s*[Rr]ank%s*%d+%s*%))%s*$")
        if base then
            local n, ic = SpellNameIcon(base)
            return n and (n .. r) or nil, ic
        end
    end
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, idOrName)
        local ok2, ic = pcall(C_Spell.GetSpellTexture, idOrName)
        return ok and n or nil, ok2 and ic or nil
    end
    if GetSpellInfo then
        local n, _, ic = GetSpellInfo(idOrName)
        return n, ic
    end
end

local function ItemNameIcon(idOrName, link)
    local n, ic
    if type(idOrName) == "number" and C_Item and C_Item.GetItemNameByID then
        n = C_Item.GetItemNameByID(idOrName)
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
        local ok, iname, _, _, _, _, _, _, _, _, tex = pcall(getInfo, idOrName)
        if ok then n = n or iname; ic = tex end
    end
    if not n and link then n = link:match("%[(.-)%]") end
    if not ic and type(idOrName) == "number" then
        if C_Item and C_Item.GetItemIconByID then ic = C_Item.GetItemIconByID(idOrName)
        elseif GetItemIcon then ic = GetItemIcon(idOrName) end
    end
    return n, ic
end

-- What is on the mouse cursor right now? Returns kind ("spell"/"item"), name, icon.
local function ReadCursor()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        local n, ic
        if c then n, ic = SpellNameIcon(c) end
        if not n and C_SpellBook and C_SpellBook.GetSpellBookItemName and a then
            local ok, name = pcall(C_SpellBook.GetSpellBookItemName, a, b == "pet" and 1 or 0)
            if ok then n = name end
        end
        if n then return "spell", n, ic end
    elseif kind == "item" then
        local n, ic = ItemNameIcon(a, b)
        if n then return "item", n, ic end
    end
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local tree = {}
local slots = {}
local IsKnownName = function() return true end -- replaced once the spellbook reader exists
local explainMode = false
local selectedIcon -- nil = automatic (shows the spell the macro casts)
local drag = {}
local undoStack, redoStack, lastState, lastTree = {}, {}, nil, nil
local F, canvas, scroll, previewText, countText, warnText, nameBox, charCheck, tipCheck, dragBtn, measure
local Render -- forward

local function NewNode(kind)
    if kind == "spell" then return { kind = "cast", what = "spell", unit = "default" } end
    if kind == "item" then return { kind = "cast", what = "item", unit = "default" } end
    if kind == "attack" then return { kind = "attack" } end
    if kind == "chat" then return { kind = "chat", channel = "s", text = "" } end
    if kind == "if" then return { kind = "if", branches = { { conds = {}, body = {} } } } end
    if kind == "seq" then return { kind = "seq", reset = "", spells = { {}, {} } } end
    if kind == "stop" then return { kind = "stop" } end
    if kind == "raw" then return { kind = "raw", text = "" } end
end

local function NodeColor(node)
    if node.kind == "cast" then return COLORS[node.what == "item" and "item" or "spell"] end
    return COLORS[node.kind]
end

local function NodeTitle(node)
    if node.kind == "cast" then
        if node.name then return (node.what == "item" and "use " or "cast ") .. node.name end
        return node.what == "item" and "use an item" or "cast a spell"
    end
    if node.kind == "attack" then return "start attacking" end
    if node.kind == "chat" then return "chat message" end
    if node.kind == "seq" then return "cast sequence" end
    if node.kind == "stop" then return "stop casting" end
    if node.kind == "raw" then return "custom line" end
    return "if / else"
end

-- Title for a drag ghost carrying one or more blocks
local function NodesTitle(nodes, title)
    if title then return title end
    if #nodes == 1 then return NodeTitle(nodes[1]) end
    return #nodes .. " blocks"
end

------------------------------------------------------------------------
-- Popup menu
------------------------------------------------------------------------
local menuFrame, menuCatcher, menuButtons = nil, nil, {}

local function HideMenu()
    if menuFrame then menuFrame:Hide(); menuCatcher:Hide() end
end

local function TooltipBackdrop(f, alpha)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.09, alpha or 0.97)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

-- items: { { text = "...", func = function() end, isTitle = bool }, ... }
local function ShowMenu(title, items)
    if not menuFrame then
        menuCatcher = CreateFrame("Button", nil, UIParent)
        menuCatcher:SetAllPoints(UIParent)
        menuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        menuCatcher:SetFrameLevel(1)
        menuCatcher:RegisterForClicks("AnyUp")
        menuCatcher:SetScript("OnClick", HideMenu)

        menuFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        menuFrame:SetFrameLevel(50)
        menuFrame:SetClampedToScreen(true)
        menuFrame:EnableMouse(true)
        TooltipBackdrop(menuFrame)
        menuFrame.title = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        menuFrame.title:SetPoint("TOPLEFT", 10, -8)
    end

    menuFrame.title:SetText(title or "")
    local width = math.max(menuFrame.title:GetStringWidth() + 20, 120)
    for i, it in ipairs(items) do
        local b = menuButtons[i]
        if not b then
            b = CreateFrame("Button", nil, menuFrame)
            b:SetHeight(18)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 10, 0)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.25)
            menuButtons[i] = b
        end
        b:SetParent(menuFrame)
        b:SetFrameLevel(menuFrame:GetFrameLevel() + 2)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 4, -24 - (i - 1) * 18)
        b:SetPoint("RIGHT", menuFrame, "RIGHT", -4, 0)
        b.text:SetText(it.text)
        if it.isTitle then
            b.text:SetFontObject("GameFontNormalSmall")
            b:SetScript("OnClick", nil)
            b:EnableMouse(false)
        else
            b.text:SetFontObject("GameFontHighlightSmall")
            b:EnableMouse(true)
            local func = it.func
            b:SetScript("OnClick", function() HideMenu(); if func then func() end end)
        end
        width = math.max(width, b.text:GetStringWidth() + 32)
        b:Show()
    end
    for i = #items + 1, #menuButtons do menuButtons[i]:Hide() end

    menuFrame:SetSize(width, 32 + #items * 18)
    local scale = menuFrame:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    menuFrame:ClearAllPoints()
    menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx / scale - 4, my / scale + 4)
    menuCatcher:Show()
    menuFrame:Show()
end

------------------------------------------------------------------------
-- Text input popup
------------------------------------------------------------------------
local inputFrame
local function ShowInput(prompt, initial, onAccept, opts)
    opts = opts or {}
    if not inputFrame then
        inputFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        inputFrame:SetSize(300, 96)
        inputFrame:SetPoint("CENTER", 0, 120)
        inputFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        inputFrame:SetFrameLevel(60)
        inputFrame:EnableMouse(true)
        TooltipBackdrop(inputFrame)
        inputFrame.prompt = inputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        inputFrame.prompt:SetPoint("TOP", 0, -12)
        local eb = CreateFrame("EditBox", nil, inputFrame, "InputBoxTemplate")
        eb:SetSize(250, 20)
        eb:SetPoint("TOP", 0, -34)
        eb:SetAutoFocus(true)
        inputFrame.eb = eb
        local ok = CreateFrame("Button", nil, inputFrame, "UIPanelButtonTemplate")
        ok:SetSize(80, 22)
        ok:SetPoint("BOTTOMRIGHT", inputFrame, "BOTTOM", -4, 10)
        ok:SetText("OK")
        local cancel = CreateFrame("Button", nil, inputFrame, "UIPanelButtonTemplate")
        cancel:SetSize(80, 22)
        cancel:SetPoint("BOTTOMLEFT", inputFrame, "BOTTOM", 4, 10)
        cancel:SetText("Cancel")
        local function accept()
            local text = eb:GetText()
            inputFrame:Hide()
            if inputFrame.onAccept then inputFrame.onAccept(text) end
        end
        inputFrame.ok, inputFrame.cancel = ok, cancel
        ok:SetScript("OnClick", accept)
        eb:SetScript("OnEnterPressed", accept)
        eb:SetScript("OnEscapePressed", function() inputFrame:Hide() end)
        cancel:SetScript("OnClick", function() inputFrame:Hide() end)
    end
    inputFrame.prompt:SetText(prompt)
    inputFrame.onAccept = onAccept
    local w = opts.wide and 460 or 300
    inputFrame:SetWidth(w)
    inputFrame.eb:SetWidth(w - 50)
    inputFrame.eb:SetMaxLetters(opts.wide and 0 or 255)
    inputFrame.ok:SetText(opts.copyOnly and "Done" or "OK")
    if opts.copyOnly then inputFrame.cancel:Hide() else inputFrame.cancel:Show() end
    inputFrame.eb:SetText(initial or "")
    inputFrame:Show()
    inputFrame.eb:SetFocus()
    inputFrame.eb:HighlightText()
end

------------------------------------------------------------------------
-- Widget pools (the canvas is redrawn from the tree after every change)
------------------------------------------------------------------------
local pools = {}
local function Acquire(kind, creator)
    local p = pools[kind]
    if not p then p = { free = {}, used = {} }; pools[kind] = p end
    local f = table.remove(p.free) or creator()
    p.used[#p.used + 1] = f
    f:Show()
    return f
end
local function ReleaseAll()
    for _, p in pairs(pools) do
        for _, f in ipairs(p.used) do
            f:Hide()
            f:ClearAllPoints()
            if f.ClearFocus then f:ClearFocus() end
            p.free[#p.free + 1] = f
        end
        wipe(p.used)
    end
end

local function CreateLabel()
    local l = CreateFrame("Frame", nil, canvas)
    l.fs = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l.fs:SetPoint("LEFT")
    l.fs:SetJustifyH("LEFT")
    return l
end

local BTN_SHAPES = {
    hex   = { tex = "hex_l",  cap = 7, extra = 6 },
    pill  = { tex = "pill_l", cap = 9, extra = 6 },
    round = { tex = "rcap_l", cap = 4, extra = 0 },
}

local function SetBtnColor(b, c, mult)
    local r, g, bl = math.min(1, c[1] * mult + (mult > 1 and 0.08 or 0)), math.min(1, c[2] * mult + (mult > 1 and 0.08 or 0)), math.min(1, c[3] * mult + (mult > 1 and 0.08 or 0))
    b.capL:SetVertexColor(r, g, bl, c[4])
    b.capR:SetVertexColor(r, g, bl, c[4])
    b.mid:SetColorTexture(r, g, bl, c[4])
end

local function CreateBtn()
    local b = CreateFrame("Button", nil, canvas)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.capL = b:CreateTexture(nil, "BACKGROUND")
    b.capR = b:CreateTexture(nil, "BACKGROUND")
    b.mid = b:CreateTexture(nil, "BACKGROUND")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b:SetScript("OnEnter", function(self)
        if self.baseColor then SetBtnColor(self, self.baseColor, 1.4) end
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if self.baseColor then SetBtnColor(self, self.baseColor, 1) end
        GameTooltip:Hide()
    end)
    return b
end

local function CreateEdit()
    local e = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    e:SetAutoFocus(false)
    e:SetHeight(20)
    e:SetMaxLetters(200)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

local function CreateInset()
    local f = CreateFrame("Frame", nil, canvas)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    SetTable(f.bg)
    f.bump = f:CreateTexture(nil, "ARTWORK")
    f.bump:SetTexture(MEDIA .. "knob_round")
    f.bump:SetPoint("TOPLEFT", 4 + NOTCH_X, 0)
    f.bump:SetSize(NOTCH_W, NOTCH_H)
    return f
end

local CanvasReceive -- forward
local StartCanvasDrag -- forward
local BlockMenu -- forward

local function CreateBlockFrame()
    local f = CreateFrame("Frame", nil, canvas)
    NewBrickParts(f)
    -- hole on top, painted in the colour of the piece above so its knob looks locked in
    f.notch = f:CreateTexture(nil, "ARTWORK")
    f.notch:SetPoint("TOPLEFT", NOTCH_X, 0)
    f.notch:SetSize(NOTCH_W, NOTCH_H)
    -- knob hanging below the last piece of a stack
    f.tab = f:CreateTexture(nil, "ARTWORK")
    f.tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", NOTCH_X, 0)
    f.tab:SetSize(NOTCH_W, NOTCH_H)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) StartCanvasDrag(self.node, self.list) end)
    f:SetScript("OnReceiveDrag", function() CanvasReceive() end)
    f:SetScript("OnMouseUp", function(self, button)
        if GetCursorInfo() then
            CanvasReceive()
        elseif button == "RightButton" then
            BlockMenu(self.node, self.list)
        end
    end)
    return f
end

-- Widget helpers ------------------------------------------------------
local function Place(widget, parent, x, rowTop, h)
    widget:SetParent(parent)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(rowTop + (ROW - h) / 2))
    widget:SetFrameLevel(parent:GetFrameLevel() + 2)
end

local function TextWidth(text, font)
    measure:SetFontObject(font or "GameFontHighlightSmall")
    measure:SetText(text)
    return math.ceil(measure:GetStringWidth())
end

local function Label(parent, text, x, rowTop, font)
    local l = Acquire("label", CreateLabel)
    l.fs:SetFontObject(font or "GameFontHighlight")
    if parent.color and IsLight(parent.color) then
        l.fs:SetTextColor(0.12, 0.09, 0.02)
    else
        l.fs:SetTextColor(1, 1, 1)
    end
    l.fs:SetText(text)
    local w = math.ceil(l.fs:GetStringWidth()) + 2
    l:SetSize(w, 16)
    Place(l, parent, x, rowTop, 16)
    return x + w + 4
end

local function BtnWidth(text, opts)
    local sh = BTN_SHAPES[(opts and opts.shape) or "round"]
    local w = (opts and opts.width) or (TextWidth(text) + 14 + sh.extra)
    if opts and opts.icon then w = w + 20 end
    return w
end

-- opts: width, icon, bg {r,g,b,a}, onClick(self, button), onReceive, tip
local function Btn(parent, text, x, rowTop, opts)
    opts = opts or {}
    local b = Acquire("btn", CreateBtn)
    local sh = BTN_SHAPES[opts.shape or "round"]
    b.text:SetText(text)
    local tc = opts.textColor or { 1, 1, 1 }
    b.text:SetTextColor(tc[1], tc[2], tc[3])
    b.text:ClearAllPoints()
    b.icon:ClearAllPoints()
    if opts.icon then
        b.icon:SetTexture(opts.icon)
        b.icon:SetPoint("LEFT", sh.cap - 2, 0)
        b.icon:Show()
        b.text:SetPoint("LEFT", sh.cap + 18, 0)
    else
        b.icon:Hide()
        b.text:SetPoint("CENTER")
    end
    local w = BtnWidth(text, opts)
    b:SetSize(w, 20)
    Place(b, parent, x, rowTop, 20)
    b.capL:SetTexture(MEDIA .. sh.tex)
    b.capL:SetTexCoord(0, 1, 0, 1)
    b.capL:ClearAllPoints()
    b.capL:SetPoint("TOPLEFT")
    b.capL:SetSize(sh.cap, 20)
    b.capR:SetTexture(MEDIA .. sh.tex)
    b.capR:SetTexCoord(1, 0, 0, 1)
    b.capR:ClearAllPoints()
    b.capR:SetPoint("TOPRIGHT")
    b.capR:SetSize(sh.cap, 20)
    b.mid:ClearAllPoints()
    b.mid:SetPoint("TOPLEFT", sh.cap, 0)
    b.mid:SetPoint("BOTTOMRIGHT", -sh.cap, 0)
    local bg = opts.bg or { 0, 0, 0, 0.45 }
    b.baseColor = bg
    SetBtnColor(b, bg, 1)
    b.tip = opts.tip
    b.slotTarget = opts.slotTarget
    b:SetScript("OnClick", opts.onClick)
    b:SetScript("OnReceiveDrag", opts.onReceive)
    return b, x + w + 4
end

------------------------------------------------------------------------
-- Editing helpers
------------------------------------------------------------------------
local function FillFromCursor(node)
    local kind, name, icon = ReadCursor()
    if not name then return false end
    node.what = kind
    node.name = name
    node.icon = icon
    ClearCursor()
    Render()
    return true
end

local function SetNodeByName(node, text)
    text = trim(text)
    if text == "" then
        node.name, node.icon = nil, nil
        Render()
        return
    end
    node.name = text
    local sname, sicon = SpellNameIcon(text)
    if sname then
        node.what, node.icon = "spell", sicon
    else
        local iname, iicon = ItemNameIcon(text)
        if iname then
            node.what, node.icon = "item", iicon
        else
            node.icon = nil
        end
    end
    Render()
end

local function FindIndex(list, node)
    for i, n in ipairs(list) do if n == node then return i end end
end

function BlockMenu(node, list)
    ShowMenu(NodeTitle(node), {
        { text = "Duplicate", func = function()
            local i = FindIndex(list, node)
            if i then table.insert(list, i + 1, CopyTable(node)); Render() end
        end },
        { text = "Delete", func = function()
            local i = FindIndex(list, node)
            if i then table.remove(list, i); Render() end
        end },
    })
end

local function UnitMenu(title, units, onPick)
    local items = {}
    for _, u in ipairs(units) do
        items[#items + 1] = { text = u.label, func = function() onPick(u.id) end }
    end
    ShowMenu(title, items)
end

local function PickCondition(onPick)
    local items = {
        { text = "A unit is friendly / enemy / dead...", func = function()
            UnitMenu("Which unit?", COND_UNITS, function(unit)
                local checks = {}
                for _, c in ipairs(UNIT_CHECKS) do
                    checks[#checks + 1] = { text = (COND_UNIT_LABEL[unit]) .. " " .. c.label,
                        func = function() onPick({ key = c.key, unit = unit }) end }
                end
                ShowMenu("Check", checks)
            end)
        end },
    }
    for _, g in ipairs(COND_GROUPS) do
        items[#items + 1] = { text = g.title .. "...", func = function()
            local sub = {}
            for _, it in ipairs(g.items) do
                sub[#sub + 1] = { text = it.label, func = function() onPick({ key = it.key }) end }
            end
            ShowMenu(g.title, sub)
        end }
    end
    ShowMenu("Add a condition", items)
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------
local RenderList -- forward
local renderCtx = {} -- set by RenderList: colour of what's above, is this the last block

local function PaintBlock(f, h)
    f:SetHeight(h)
    PaintBrick(f, f.w, h, f.color, f.shape, 1)
end

local function NewBlock(node, list, x, y, w, h, depth)
    local f = Acquire("block", CreateBlockFrame)
    f:SetParent(canvas)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
    f:SetSize(w, h)
    f:SetFrameLevel(canvas:GetFrameLevel() + 2 + depth * 60 + math.min(renderCtx.index or 1, 50))
    local c = NodeColor(node)
    f.color, f.w, f.shape = c, w, SocketShape(node)
    PaintBlock(f, h)
    local above = renderCtx.above or CANVAS_BG
    f.notch:SetTexture(TabTexture(f.shape))
    f.notch:SetVertexColor(above[1], above[2], above[3], 1)
    if renderCtx.isLast then
        f.tab:SetTexture(TabTexture("round"))
        f.tab:SetVertexColor(c[1], c[2], c[3], 1)
        f.tab:Show()
    else
        f.tab:Hide()
    end
    renderCtx.above, renderCtx.isLast, renderCtx.index = nil, nil, nil
    f.node, f.list = node, list
    return f
end

local function RenderCast(node, list, x, y, w, depth)
    local f = NewBlock(node, list, x, y, w, ROW, depth)
    local cx = Label(f, node.what == "item" and "use" or "cast", 8, 0)
    local slotText = node.name or (node.what == "item" and "drop an item here" or "drop a spell here")
    local _
    _, cx = Btn(f, slotText, cx, 0, {
        icon = node.icon or QUESTION_ICON,
        bg = { 0, 0, 0, 0.55 },
        shape = "pill",
        textColor = (node.name and not IsKnownName(node.name, node.what)) and { 1, 0.4, 0.4 } or nil,
        tip = "Drag a spell from your spellbook (or an item from your bags) here.\nLeft-click to type a name. Right-click to clear.",
        onClick = function(_, button)
            if button == "RightButton" then
                node.name, node.icon = nil, nil
                Render()
            elseif not FillFromCursor(node) then
                ShowInput("Spell or item name:", node.name or "", function(text) SetNodeByName(node, text) end)
            end
        end,
        onReceive = function() FillFromCursor(node) end,
        slotTarget = node,
    })
    cx = Label(f, "on", cx, 0)
    Btn(f, (CAST_UNIT_LABEL[node.unit] or node.unit) .. " v", cx, 0, {
        tip = "Who to cast it on. 'target' is the normal behaviour.",
        onClick = function()
            UnitMenu("Cast on", CAST_UNITS, function(id) node.unit = id; Render() end)
        end,
    })
    return ROW
end

local function RenderAttack(node, list, x, y, w, depth)
    local f = NewBlock(node, list, x, y, w, ROW, depth)
    Label(f, "start attacking", 8, 0)
    return ROW
end

local function RenderStop(node, list, x, y, w, depth)
    local f = NewBlock(node, list, x, y, w, ROW, depth)
    Label(f, "stop casting", 8, 0)
    return ROW
end

local function RenderSeq(node, list, x, y, w, depth)
    local f = NewBlock(node, list, x, y, w, ROW, depth)
    local _
    local rowTop = 0
    local cx = Label(f, "cast in order", 8, rowTop)
    for si, s in ipairs(node.spells) do
        local text = s.name or "drop spell"
        if cx + BtnWidth(text, { icon = true }) > w - 8 then
            rowTop = rowTop + 24
            cx = 30
        end
        _, cx = Btn(f, text, cx, rowTop, {
            icon = s.icon or QUESTION_ICON,
            bg = { 0, 0, 0, 0.55 },
            shape = "pill",
            textColor = (s.name and not IsKnownName(s.name, s.what)) and { 1, 0.4, 0.4 } or nil,
            tip = "Step " .. si .. ". Drag a spell here, left-click to type one, right-click to remove this step.",
            onClick = function(_, button)
                if button == "RightButton" then
                    table.remove(node.spells, si)
                    Render()
                elseif not FillFromCursor(s) then
                    ShowInput("Spell or item name:", s.name or "", function(t) SetNodeByName(s, t) end)
                end
            end,
            onReceive = function() FillFromCursor(s) end,
            slotTarget = s,
        })
        if si < #node.spells then cx = Label(f, ">", cx, rowTop, "GameFontHighlightSmall") end
    end
    if cx + BtnWidth("+ step") > w - 8 then
        rowTop = rowTop + 24
        cx = 30
    end
    Btn(f, "+ step", cx, rowTop, {
        tip = "Add another spell to the sequence.",
        onClick = function() table.insert(node.spells, {}); Render() end,
    })
    rowTop = rowTop + 24
    local rx = Label(f, "start over on", 30, rowTop, "GameFontHighlightSmall")
    Btn(f, (RESET_LABEL[node.reset or ""] or node.reset) .. " v", rx, rowTop, {
        tip = "When the sequence goes back to the first spell.",
        onClick = function()
            UnitMenu("Start over on", RESETS, function(id) node.reset = id; Render() end)
        end,
    })
    local h = rowTop + ROW
    PaintBlock(f, h)
    return h
end

local function RenderChat(node, list, x, y, w, depth)
    local f = NewBlock(node, list, x, y, w, ROW, depth)
    local _, cx = Btn(f, (CHANNEL_LABEL[node.channel] or node.channel) .. " v", 8, 0, {
        onClick = function()
            UnitMenu("Send to", CHANNELS, function(id) node.channel = id; Render() end)
        end,
    })
    local e = Acquire("edit", CreateEdit)
    e:SetScript("OnTextChanged", nil)
    e:SetMaxLetters(200)
    e:SetText(node.text or "")
    e:SetSize(math.max(60, w - cx - 14), 20)
    Place(e, f, cx + 6, 0, 20)
    e:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            node.text = self:GetText()
            F.UpdatePreview()
        end
    end)
    return ROW
end

local function RenderRaw(node, list, x, y, w, depth)
    local f = NewBlock(node, list, x, y, w, ROW, depth)
    local cx = Label(f, "custom line", 8, 0, "GameFontHighlightSmall")
    local e = Acquire("edit", CreateEdit)
    e:SetScript("OnTextChanged", nil)
    e:SetMaxLetters(255)
    e:SetText(node.text or "")
    e:SetSize(math.max(60, w - cx - 14), 20)
    Place(e, f, cx + 6, 0, 20)
    e:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            node.text = self:GetText()
            F.UpdatePreview()
        end
    end)
    return ROW
end

local function RenderIf(node, list, x, y, w, depth)
    local container = NewBlock(node, list, x, y, w, 10, depth)
    local top = y
    local cy = y
    local chipBg = { 0.35, 0.22, 0, 0.75 }

    local function Header(text, branchIndex, br, removable, onRemove)
        local rowTop = cy - top
        local cx = Label(container, text, 8, rowTop)
        if br then
            for ci, c in ipairs(br.conds) do
                local label = CondLabel(c)
                if cx + BtnWidth(label, { shape = "hex" }) > w - 60 then
                    rowTop = rowTop + 24
                    cx = 40
                end
                local _
                _, cx = Btn(container, label, cx, rowTop, {
                    bg = chipBg,
                    shape = "hex",
                    tip = "Click to change or remove this condition.",
                    onClick = function()
                        ShowMenu(label, {
                            { text = "Change...", func = function()
                                PickCondition(function(nc) br.conds[ci] = nc; Render() end)
                            end },
                            { text = "Remove", func = function() table.remove(br.conds, ci); Render() end },
                        })
                    end,
                })
                if ci < #br.conds then cx = Label(container, "and", cx, rowTop, "GameFontHighlightSmall") end
            end
            if #br.conds < 4 then
                local addText = #br.conds == 0 and "+ condition" or "+ and"
                if cx + BtnWidth(addText, { shape = "hex" }) > w - 30 then
                    rowTop = rowTop + 24
                    cx = 40
                end
                Btn(container, addText, cx, rowTop, {
                    shape = "hex",
                    bg = { 0, 0, 0, 0.3 },
                    tip = "Add a condition. All conditions on this line must be true.",
                    onClick = function()
                        PickCondition(function(nc) table.insert(br.conds, nc); Render() end)
                    end,
                })
            end
        end
        if removable then
            Btn(container, "x", w - 24, cy - top, { width = 18, tip = "Remove this branch", onClick = onRemove })
        end
        cy = top + rowTop + ROW
    end

    local function Body(bodyList)
        local bodyTop = cy
        cy = RenderList(bodyList, x + 18, cy, w - 22, depth + 1, container.color)
        if #bodyList > 0 then cy = cy + NOTCH_H end -- room for the last piece's knob
        local inset = Acquire("inset", CreateInset)
        inset.bump:SetVertexColor(container.color[1], container.color[2], container.color[3], 1)
        inset.bump:SetShown(#bodyList == 0)
        inset:SetParent(container)
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", container, "TOPLEFT", 14, -(bodyTop - top))
        inset:SetSize(w - 18, cy - bodyTop)
        inset:SetFrameLevel(container:GetFrameLevel() + 1)
    end

    for bi, br in ipairs(node.branches) do
        Header(bi == 1 and "if" or "else if", bi, br, bi > 1, function()
            table.remove(node.branches, bi)
            Render()
        end)
        Body(br.body)
    end
    if node.elseBody then
        Header("else", nil, nil, true, function() node.elseBody = nil; Render() end)
        Body(node.elseBody)
    end

    -- footer
    local rowTop = cy - top
    local _, fx = Btn(container, "+ else if", 8, rowTop - 2, {
        onClick = function()
            table.insert(node.branches, { conds = {}, body = {} })
            Render()
        end,
    })
    if not node.elseBody then
        Btn(container, "+ else", fx, rowTop - 2, {
            onClick = function() node.elseBody = {}; Render() end,
        })
    end
    cy = cy + ROW - 4
    PaintBlock(container, cy - top)
    return cy - top
end

local function RenderNode(node, list, x, y, w, depth)
    if node.kind == "cast" then return RenderCast(node, list, x, y, w, depth) end
    if node.kind == "attack" then return RenderAttack(node, list, x, y, w, depth) end
    if node.kind == "chat" then return RenderChat(node, list, x, y, w, depth) end
    if node.kind == "if" then return RenderIf(node, list, x, y, w, depth) end
    if node.kind == "seq" then return RenderSeq(node, list, x, y, w, depth) end
    if node.kind == "stop" then return RenderStop(node, list, x, y, w, depth) end
    if node.kind == "raw" then return RenderRaw(node, list, x, y, w, depth) end
    return 0
end

function RenderList(list, x, y, w, depth, mouthColor)
    for i, node in ipairs(list) do
        slots[#slots + 1] = { list = list, index = i, x = x, y = y, w = w, depth = depth }
        renderCtx.above = (i == 1) and (mouthColor or CANVAS_BG) or NodeColor(list[i - 1])
        renderCtx.isLast = (i == #list)
        renderCtx.index = i
        local h = RenderNode(node, list, x, y, w, depth)
        y = y + h + GAP
    end
    slots[#slots + 1] = { list = list, index = #list + 1, x = x, y = y, w = w, depth = depth }
    if #list == 0 then
        local l = Acquire("label", CreateLabel)
        l.fs:SetFontObject("GameFontDisableSmall")
        l.fs:SetTextColor(0.6, 0.6, 0.6)
        if depth == 0 then
            l.fs:SetText("Drag blocks here from the left, or drag spells straight from your spellbook (P).")
        else
            l.fs:SetText("drop blocks here")
        end
        l:SetSize(w, 16)
        l:SetParent(canvas)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", canvas, "TOPLEFT", x + (depth > 0 and 44 or 6), -(y + 4))
        l:SetFrameLevel(canvas:GetFrameLevel() + 3 + depth * 6)
        y = y + 22
    end
    return y
end

-- Record the tree for undo whenever it changed since the last snapshot.
local function Snapshot()
    local s = ns.Serialize(tree)
    if lastState == nil then
        lastState, lastTree = s, CopyTable(tree)
    elseif s ~= lastState then
        undoStack[#undoStack + 1] = lastTree
        if #undoStack > 50 then table.remove(undoStack, 1) end
        wipe(redoStack)
        lastState, lastTree = s, CopyTable(tree)
    end
end

local function Undo()
    Snapshot() -- commit any typing first
    local prev = table.remove(undoStack)
    if not prev then return end
    redoStack[#redoStack + 1] = CopyTable(tree)
    tree = CopyTable(prev)
    lastState, lastTree = ns.Serialize(tree), CopyTable(tree)
    Render()
end

local function Redo()
    local nxt = table.remove(redoStack)
    if not nxt then return end
    undoStack[#undoStack + 1] = CopyTable(tree)
    tree = CopyTable(nxt)
    lastState, lastTree = ns.Serialize(tree), CopyTable(tree)
    Render()
end

function Render()
    if not F then return end
    if not drag.nodes then Snapshot() end
    if F.undoBtn then
        F.undoBtn:SetEnabled(#undoStack > 0)
        F.redoBtn:SetEnabled(#redoStack > 0)
    end
    ReleaseAll()
    wipe(slots)
    local bottom = RenderList(tree, 8, 8, CANVAS_W - 16, 0)
    canvas:SetHeight(math.max(bottom + 40, scroll:GetHeight()))
    F.UpdatePreview()
end

------------------------------------------------------------------------
-- Dragging blocks
------------------------------------------------------------------------
local ghost, indicator

local function CursorOnCanvas()
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then return end
    local scale = canvas:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    return mx / scale - left, top - my / scale
end

local function FindSlot()
    if not scroll:IsMouseOver() then return nil end
    local cx, cy = CursorOnCanvas()
    if not cx then return nil end
    local best, bestScore
    for _, s in ipairs(slots) do
        local score = math.abs(cy - s.y) + math.max(0, s.x - cx) * 0.6
        if not bestScore or score < bestScore then best, bestScore = s, score end
    end
    return best
end

local function SlotProblem(nodes, slot)
    if slot.depth > 0 then
        for _, node in ipairs(nodes) do
            if node.kind == "chat" then
                return "Square-knob pieces only fit on the main stack: WoW can't make chat messages conditional."
            end
            if node.kind == "if" then
                return "Square-knob pieces only fit on the main stack: an 'if' can't go inside another 'if' yet (use 'else if')."
            end
            if node.kind == "raw" then
                return "Square-knob pieces only fit on the main stack: custom lines can't be made conditional by an 'if'."
            end
        end
    end
end

local function ShowIndicator(slot, bad, shape)
    if not slot then indicator:Hide() return end
    indicator:ClearAllPoints()
    indicator:SetPoint("TOPLEFT", canvas, "TOPLEFT", slot.x, -(slot.y - 1))
    indicator:SetSize(slot.w, NOTCH_H + 2)
    local c = bad and { 1, 0.25, 0.25 } or { 0.35, 1, 0.45 }
    indicator.line:SetColorTexture(c[1], c[2], c[3], 0.95)
    indicator.shape:SetTexture(TabTexture(shape))
    indicator.shape:SetVertexColor(c[1], c[2], c[3], 0.95)
    if bad then
        indicator.label:SetText("doesn't fit here")
        indicator.label:Show()
    else
        indicator.label:Hide()
    end
    indicator:Show()
end

local function InsertNodes(list, index, nodes)
    for i, n in ipairs(nodes) do table.insert(list, index + i - 1, n) end
end

local function EndDrag()
    ghost:SetScript("OnUpdate", nil)
    ghost:Hide()
    indicator:Hide()
    local nodes = drag.nodes
    local focus
    if GetMouseFoci then focus = GetMouseFoci()[1] elseif GetMouseFocus then focus = GetMouseFocus() end
    local slot = FindSlot()
    local problem = slot and SlotProblem(nodes, slot)
    local one = #nodes == 1 and nodes[1]
    if focus and focus.slotTarget and one and one.kind == "cast" and one.name then
        local t = focus.slotTarget
        t.name, t.icon, t.what = one.name, one.icon, one.what
        if drag.origin then InsertNodes(drag.origin.list, drag.origin.index, nodes) end
    elseif slot and not problem then
        InsertNodes(slot.list, slot.index, nodes)
    elseif problem then
        Print(problem)
        if drag.origin then InsertNodes(drag.origin.list, drag.origin.index, nodes) end
    elseif drag.fromPalette then
        -- A click (or release) on the palette button adds the blocks at the end.
        if drag.fromPalette:IsMouseOver() then InsertNodes(tree, #tree + 1, nodes) end
    end
    -- dropped outside the canvas when moving an existing block: it's deleted
    drag.nodes, drag.origin, drag.fromPalette = nil, nil, nil
    Render()
end

local function BeginDrag(nodes, title)
    drag.nodes = nodes
    local c = #nodes == 1 and NodeColor(nodes[1]) or COLORS["if"]
    local shape = NodesShape(nodes)
    ghost.text:SetText(NodesTitle(nodes, title))
    local gw = ghost.text:GetStringWidth() + NOTCH_X + NOTCH_W + 20
    ghost:SetWidth(gw)
    PaintBrick(ghost, gw, 30, c, shape, 0.92)
    ghost:SetHeight(30)
    ghost.notch:SetTexture(TabTexture(shape))
    ghost.notch:SetVertexColor(0.04, 0.04, 0.05, 1)
    ghost.tab:SetVertexColor(c[1], c[2], c[3], 0.92)
    if IsLight(c) then ghost.text:SetTextColor(0.12, 0.09, 0.02) else ghost.text:SetTextColor(1, 1, 1) end
    ghost:Show()
    ghost:SetScript("OnUpdate", function(self)
        local scale = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx / scale + 8, my / scale - 8)
        local slot = FindSlot()
        ShowIndicator(slot, slot and SlotProblem(drag.nodes, slot), shape)
        if not IsMouseButtonDown("LeftButton") then EndDrag() end
    end)
end

function StartCanvasDrag(node, list)
    if drag.nodes then return end
    local i = FindIndex(list, node)
    if not i then return end
    table.remove(list, i)
    drag.origin = { list = list, index = i }
    drag.nodes = { node }
    Render()
    BeginDrag({ node })
end

-- A spell/item from the spellbook or bags dropped on the canvas
function CanvasReceive()
    local kind, name, icon = ReadCursor()
    if not name then return end
    local node = { kind = "cast", what = kind, name = name, icon = icon, unit = "default" }
    local slot = FindSlot()
    if slot then
        table.insert(slot.list, slot.index, node)
    else
        table.insert(tree, node)
    end
    ClearCursor()
    Render()
end

------------------------------------------------------------------------
-- Save / load
------------------------------------------------------------------------
local function FirstIcon(list)
    for _, n in ipairs(list) do
        if n.kind == "cast" and n.icon then return n.icon end
        if n.kind == "seq" then
            for _, sp in ipairs(n.spells) do
                if sp.icon then return sp.icon end
            end
        end
        if n.kind == "if" then
            for _, br in ipairs(n.branches) do
                local ic = FirstIcon(br.body)
                if ic then return ic end
            end
            if n.elseBody then
                local ic = FirstIcon(n.elseBody)
                if ic then return ic end
            end
        end
    end
end

local function SaveMacro()
    if InCombatLockdown() then
        Print("macros can't be saved during combat.")
        return
    end
    local name = trim(nameBox:GetText())
    if name == "" then
        Print("give your macro a name first.")
        nameBox:SetFocus()
        return
    end
    local body, warns = ns.Compile(tree, tipCheck:GetChecked())
    if body == "" then
        Print("the macro is empty. Add some blocks first.")
        return
    end
    if #body > MAX_CHARS then
        Print("the macro is " .. #body .. " characters; WoW allows " .. MAX_CHARS .. ". Remove a block or two.")
        return
    end

    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then
        EditMacro(idx, name, selectedIcon or QUESTION_ICON, body)
    else
        local ok, res = pcall(CreateMacro, name, selectedIcon or QUESTION_ICON, body, charCheck:GetChecked() and true or nil)
        if not ok or not res then
            Print("couldn't create the macro. Your macro slots may be full.")
            return
        end
    end

    DB.builds[name] = { tree = CopyTable(tree), perChar = charCheck:GetChecked() and true or false,
                        tooltip = tipCheck:GetChecked() and true or false, icon = selectedIcon }
    Print("saved '" .. name .. "'. Drag the icon next to Save onto your action bar.")
    F.UpdatePreview()
end

local function PickupSaved()
    local name = trim(nameBox:GetText())
    local idx = name ~= "" and GetMacroIndexByName(name)
    if not idx or idx == 0 then
        Print("save the macro first, then drag this icon to your bar.")
        return
    end
    if InCombatLockdown() then return end
    PickupMacro(idx)
end

local function LoadBuild(name)
    local b = DB.builds[name]
    if not b then return end
    tree = CopyTable(b.tree)
    nameBox:SetText(name)
    charCheck:SetChecked(b.perChar)
    tipCheck:SetChecked(b.tooltip ~= false)
    selectedIcon = b.icon
    Render()
end

local function OpenWowMacro(index)
    if InCombatLockdown() then return end
    local name, icon, body = GetMacroInfo(index)
    if not name then return end
    local t, tip, custom = ns.ParseMacro(body or "")
    tree = t
    if icon == QUESTION_ICON or icon == "Interface\\Icons\\INV_Misc_QuestionMark" then icon = nil end
    selectedIcon = icon
    nameBox:SetText(name)
    charCheck:SetChecked(index > (MAX_ACCOUNT_MACROS or 120))
    tipCheck:SetChecked(tip)
    Render()
    Print("opened '" .. name .. "' as blocks" ..
        (custom > 0 and (" (" .. custom .. " line(s) kept as custom lines)") or "") .. ". Save to update it.")
end

local function WowMacroMenu(page)
    local numA, numC = GetNumMacros()
    local base = MAX_ACCOUNT_MACROS or 120
    local list = {}
    for i = 1, numA or 0 do list[#list + 1] = i end
    for i = base + 1, base + (numC or 0) do list[#list + 1] = i end
    local per = 18
    local first = (page - 1) * per + 1
    local items = {}
    for k = first, math.min(#list, first + per - 1) do
        local idx = list[k]
        local mname = GetMacroInfo(idx)
        if mname then
            items[#items + 1] = { text = mname .. (idx > base and "  |cff888888(character)|r" or ""), func = function() OpenWowMacro(idx) end }
        end
    end
    if #list == 0 then items[1] = { text = "You don't have any macros yet", isTitle = true } end
    if first + per - 1 < #list then
        items[#items + 1] = { text = "More...", func = function() WowMacroMenu(page + 1) end }
    end
    ShowMenu("Open one of your macros as blocks", items)
end

local function ShareCode()
    if #tree == 0 then
        Print("add some blocks first.")
        return
    end
    ShowInput("Share code - press Ctrl+C to copy, then paste it anywhere", ns.Encode(tree), nil, { wide = true, copyOnly = true })
end

local function ImportCode()
    ShowInput("Paste a Snapcast code (starts with SC1:)", "", function(text)
        local t, err = ns.Decode(text)
        if not t then
            Print("couldn't import: " .. err .. ".")
            return
        end
        tree = t
        Render()
        Print("imported " .. #t .. " block(s). Look them over, then name and save.")
        for _, line in ipairs(ns.RiskyLines(t)) do
            Print("|cffff6060careful:|r this code includes a line that runs a script: " .. line)
        end
    end, { wide = true })
end

local function OpenMenu()
    local names = {}
    for name in pairs(DB.builds) do names[#names + 1] = name end
    table.sort(names)
    local items = {}
    if #names == 0 then
        items[1] = { text = "Nothing saved yet", isTitle = true }
    end
    for _, name in ipairs(names) do
        items[#items + 1] = { text = name, func = function() LoadBuild(name) end }
    end
    if #names > 0 then
        items[#items + 1] = { text = "Forget a saved layout...", func = function()
            local del = {}
            for _, name in ipairs(names) do
                del[#del + 1] = { text = name, func = function()
                    DB.builds[name] = nil
                    Print("forgot the block layout for '" .. name .. "' (the macro itself is untouched).")
                end }
            end
            ShowMenu("Forget layout", del)
        end }
    end
    table.insert(items, 1, { text = "One of your WoW macros...", func = function() WowMacroMenu(1) end })
    table.insert(items, 2, { text = "Saved block layouts", isTitle = true })
    ShowMenu("Open", items)
end

local function NewBuild()
    wipe(tree)
    nameBox:SetText("")
    selectedIcon = nil
    Render()
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Templates
------------------------------------------------------------------------
local function Cast(unit) return { kind = "cast", what = "spell", unit = unit or "default" } end
local function If(branches, elseBody) return { kind = "if", branches = branches, elseBody = elseBody } end

local TEMPLATES = {
    { name = "Mouseover heal",
      desc = "Heals the friend under your mouse if they're alive, otherwise your target. Drop your heal into both slots.",
      make = function() return {
          If({ { conds = { { key = "help", unit = "mouseover" }, { key = "nodead", unit = "mouseover" } }, body = { Cast() } } }, { Cast() }),
      } end },
    { name = "Shift for 2nd spell",
      desc = "One button, two spells: the first while Shift is held, the second normally.",
      make = function() return {
          If({ { conds = { { key = "mod:shift" } }, body = { Cast() } } }, { Cast() }),
      } end },
    { name = "Alt to self-cast",
      desc = "Casts on your target normally, or on yourself while Alt is held.",
      make = function() return {
          If({ { conds = { { key = "mod:alt" } }, body = { Cast("player") } } }, { Cast() }),
      } end },
    { name = "Interrupt",
      desc = "Stops your own cast and interrupts your target. Hold Shift to interrupt your focus instead.",
      make = function() return {
          { kind = "stop" },
          If({ { conds = { { key = "mod:shift" }, { key = "exists", unit = "focus" } }, body = { Cast("focus") } } }, { Cast() }),
      } end },
    { name = "Focus, else target",
      desc = "Casts on your focus if it's an enemy, otherwise on your target.",
      make = function() return {
          If({ { conds = { { key = "harm", unit = "focus" } }, body = { Cast("focus") } } }, { Cast() }),
      } end },
    { name = "Attack + spell",
      desc = "Turns on auto-attack and casts a spell.",
      make = function() return { { kind = "attack" }, Cast() } end },
    { name = "Trinket + spell",
      desc = "Uses a trinket (drag it from your character sheet or bags) and casts a spell.",
      make = function() return { { kind = "cast", what = "item", unit = "default" }, Cast() } end },
    { name = "Cast + announce",
      desc = "Casts a spell and tells your party. %t becomes your target's name.",
      make = function() return { Cast(), { kind = "chat", channel = "p", text = "Casting on %t!" } } end },
    { name = "Ground spell at cursor",
      desc = "Drops a ground-targeted spell right where your mouse is, with no extra click.",
      make = function() return { Cast("cursor") } end },
    { name = "Rotation sequence",
      desc = "Casts the next spell in the list each press. Starts over when you pick a new target.",
      make = function() return { { kind = "seq", reset = "target", spells = { {}, {}, {} } } } end },
}

------------------------------------------------------------------------
-- Your spells (read from the spellbook)
------------------------------------------------------------------------
local function RankNum(sub)
    if type(sub) ~= "string" then return nil end
    return tonumber(sub:match("(%d+)"))
end

-- Several spellbook slots can hold ranks of one spell: keep one entry per
-- name with the highest rank seen (if you know Rank 5 you know 1-4 too).
local function AddSpell(group, seen, name, icon, sub, spellID)
    if not sub and spellID and C_Spell and C_Spell.GetSpellSubtext then
        local ok, st = pcall(C_Spell.GetSpellSubtext, spellID)
        if ok then sub = st end
    end
    local rank = (type(sub) == "string" and sub:lower():find("rank")) and RankNum(sub) or nil
    local sp = seen[name]
    if sp then
        if rank and (not sp.maxRank or rank > sp.maxRank) then sp.maxRank = rank; sp.icon = icon or sp.icon end
        return
    end
    sp = { name = name, icon = icon, maxRank = rank }
    seen[name] = sp
    group.spells[#group.spells + 1] = sp
end

local function GetPlayerSpells()
    local out = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        local spellType = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if line and not line.shouldHide and not line.isGuild and not line.offSpecID then
                local group = { name = line.name or "?", spells = {} }
                local seen = {}
                local first = (line.itemIndexOffset or 0) + 1
                for slot = first, first + (line.numSpellBookItems or 0) - 1 do
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                    if info and info.name and info.itemType == spellType and not info.isPassive and not info.isOffSpec then
                        AddSpell(group, seen, info.name, info.iconID, info.subName, info.spellID or info.actionID)
                    end
                end
                if #group.spells > 0 then out[#out + 1] = group end
            end
        end
    elseif GetNumSpellTabs then
        for i = 1, GetNumSpellTabs() do
            local name, _, offset, num, isGuild, offspec = GetSpellTabInfo(i)
            if not isGuild and (not offspec or offspec == 0) then
                local group = { name = name or "?", spells = {} }
                local seen = {}
                for slot = offset + 1, offset + num do
                    local kind = GetSpellBookItemInfo(slot, "spell")
                    local passive = IsPassiveSpell and IsPassiveSpell(slot, "spell")
                    if kind == "SPELL" and not passive then
                        local n, sub = GetSpellBookItemName(slot, "spell")
                        local ic = GetSpellBookItemTexture and GetSpellBookItemTexture(slot, "spell")
                        if n then AddSpell(group, seen, n, ic, sub) end
                    end
                end
                if #group.spells > 0 then out[#out + 1] = group end
            end
        end
    end
    return out
end

-- Spell check: is this name in your spellbook (or bags, for items)?
local knownCache
IsKnownName = function(name, what)
    if not name or name == "" then return true end
    if DB and DB.spellCheck == false then return true end
    if what == "item" then
        if tonumber(name) then return true end -- equipment slot number, e.g. 13
        local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(name)) or (GetItemCount and GetItemCount(name))
        if count == nil then return true end
        local equipped = (C_Item and C_Item.IsEquippedItem and C_Item.IsEquippedItem(name)) or (IsEquippedItem and IsEquippedItem(name))
        return (count > 0) or (equipped and true) or false
    end
    if not knownCache then
        knownCache = {}
        local ok, groups = pcall(GetPlayerSpells)
        if ok then
            for _, g in ipairs(groups) do
                for _, sp in ipairs(g.spells) do knownCache[sp.name:lower()] = sp.maxRank or true end
            end
        end
    end
    if next(knownCache) == nil then return true end -- spellbook not readable: don't nag
    local base, r = name:match("^(.-)%s*%(%s*[Rr]ank%s*(%d+)%s*%)%s*$")
    if base then
        local max = knownCache[base:lower()]
        if max == nil or max == false then return false end
        return max == true or tonumber(r) <= max
    end
    return knownCache[name:lower()] and true or false
end

local function UnknownWarnings(list, out)
    for _, n in ipairs(list) do
        if n.kind == "cast" and n.name and not IsKnownName(n.name, n.what) then
            out[#out + 1] = n.name
        elseif n.kind == "seq" then
            for _, sp in ipairs(n.spells or {}) do
                if sp.name and not IsKnownName(sp.name, sp.what) then out[#out + 1] = sp.name end
            end
        elseif n.kind == "if" then
            for _, br in ipairs(n.branches) do UnknownWarnings(br.body, out) end
            if n.elseBody then UnknownWarnings(n.elseBody, out) end
        end
    end
    return out
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
local function AddTooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A palette entry you can drag onto the canvas (or click to add at the end).
-- tall = true: room for a two-line name (class macros, templates)
local function DragSource(parent, y, text, color, makeNodes, title, tip, shape, tall)
    local h = tall and 36 or 26
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(148, h)
    b:SetPoint("TOPLEFT", 10, y)
    NewBrickParts(b)
    b.h = h
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 2)
    hl:SetColorTexture(1, 1, 1, 0.12)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetJustifyH("LEFT")
    b.notch = b:CreateTexture(nil, "ARTWORK")
    b.notch:SetPoint("TOPLEFT", 10, 0)
    b.notch:SetSize(PAL_KNOB_W, PAL_KNOB_H)
    function b.Paint(c, sh)
        PaintBrick(b, 148, h, c, sh or "round", 1)
        b.notch:SetTexture(TabTexture(sh or "round"))
        b.notch:SetVertexColor(0.05, 0.05, 0.07, 1)
        if IsLight(c) then b.text:SetTextColor(0.12, 0.09, 0.02) else b.text:SetTextColor(1, 1, 1) end
    end
    b.Paint(color, shape)
    if tall then
        b.text:SetPoint("TOPLEFT", 8, -PAL_KNOB_H - 2)
        b.text:SetPoint("BOTTOMRIGHT", -6, 3)
        b.text:SetJustifyV("MIDDLE")
        b.text:SetWordWrap(true)
        if b.text.SetMaxLines then b.text:SetMaxLines(2) end
    else
        b.text:SetPoint("LEFT", 10 + PAL_KNOB_W + 6, -2)
        b.text:SetPoint("RIGHT", -6, -2)
        b.text:SetWordWrap(false)
    end
    b.text:SetText(text)
    b:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or drag.nodes then return end
        drag.fromPalette = self
        BeginDrag(makeNodes(), type(title) == "function" and title() or title)
    end)
    AddTooltip(b, tip or "Drag onto the canvas, or click to add at the end.")
    return b
end

local function PaletteButton(parent, kind, text, y)
    local probe = NewNode(kind)
    return DragSource(parent, y, text, NodeColor(probe), function() return { NewNode(kind) } end, nil, nil, SocketShape(probe))
end

local spellsPage, spellSearch, spellScroll, spellList
local BuildClassPage -- forward
local spellRows = {}
local expandedRanks = {} -- spell name -> true when its ranks are listed

local function RefreshSpells()
    if not spellsPage or not spellsPage:IsShown() then return end
    local filter = trim(spellSearch:GetText()):lower()
    local ok, groups = pcall(GetPlayerSpells)
    if not ok then groups = {} end
    for _, r in ipairs(spellRows) do r:Hide() end
    local y, n = 0, 0
    local function Row()
        n = n + 1
        local r = spellRows[n]
        if not r then
            r = CreateFrame("Button", nil, spellList)
            r:SetSize(150, 20)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(18, 18)
            r.icon:SetPoint("LEFT", 2, 0)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 24, 0)
            r.text:SetPoint("RIGHT", -2, 0)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            r.rank:SetPoint("RIGHT", -18, 0)
            r.rank:SetJustifyH("RIGHT")
            r.more = CreateFrame("Button", nil, r)
            r.more:SetSize(16, 16)
            r.more:SetPoint("RIGHT", 0, 0)
            r.more.t = r.more:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.more.t:SetPoint("CENTER")
            local mhl = r.more:CreateTexture(nil, "HIGHLIGHT")
            mhl:SetAllPoints()
            mhl:SetColorTexture(1, 1, 1, 0.2)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.15)
            spellRows[n] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", spellList, "TOPLEFT", 0, -y)
        r:Show()
        r.rank:SetText("")
        r.more:Hide()
        r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetAlpha(1)
        r.text:SetPoint("RIGHT", -2, 0)
        y = y + 20
        return r
    end
    for _, g in ipairs(groups) do
        local matches = {}
        for _, sp in ipairs(g.spells) do
            if filter == "" or sp.name:lower():find(filter, 1, true) then matches[#matches + 1] = sp end
        end
        if #matches > 0 then
            local h = Row()
            h.icon:Hide()
            h.text:SetFontObject("GameFontNormalSmall")
            h.text:SetPoint("LEFT", 2, 0)
            h.text:SetText(g.name)
            h.hl:Hide()
            h:SetScript("OnMouseDown", nil)
            h:SetScript("OnEnter", nil)
            for _, sp in ipairs(matches) do
                local r = Row()
                r.icon:Show()
                r.icon:SetTexture(sp.icon or QUESTION_ICON)
                r.text:SetFontObject("GameFontHighlightSmall")
                r.text:SetPoint("LEFT", 24, 0)
                r.text:SetText(sp.name)
                r.hl:Show()
                r:SetScript("OnMouseDown", function(self, button)
                    if button ~= "LeftButton" or drag.nodes then return end
                    drag.fromPalette = self
                    BeginDrag({ { kind = "cast", what = "spell", name = sp.name, icon = sp.icon, unit = "default" } })
                end)
                if sp.maxRank then
                    local open = expandedRanks[sp.name]
                    r.text:SetPoint("RIGHT", -44, 0)
                    r.rank:SetText("R" .. sp.maxRank)
                    if sp.maxRank > 1 then
                        r.more:Show()
                        r.more.t:SetText(open and "-" or "+")
                        r.more:SetScript("OnClick", function()
                            expandedRanks[sp.name] = not expandedRanks[sp.name] or nil
                            RefreshSpells()
                        end)
                        AddTooltip(r.more, open and "Hide ranks" or "Show every rank of " .. sp.name)
                    end
                    AddTooltip(r, "Rank " .. sp.maxRank .. " (your highest). Without a rank the macro always casts your highest rank.\nClick + to pick a lower rank, e.g. a cheap rank to save mana.\nDrag onto the canvas or into a slot, or click to add at the end.")
                    if open and sp.maxRank > 1 then
                        for rk = sp.maxRank, 1, -1 do
                            local rr = Row()
                            local full = sp.name .. "(Rank " .. rk .. ")"
                            rr.icon:Show()
                            rr.icon:SetTexture(sp.icon or QUESTION_ICON)
                            rr.icon:SetPoint("LEFT", 14, 0)
                            rr.icon:SetAlpha(0.7)
                            rr.text:SetFontObject("GameFontHighlightSmall")
                            rr.text:SetPoint("LEFT", 36, 0)
                            rr.text:SetText("|cffaaaaaaRank " .. rk .. "|r" .. (rk == sp.maxRank and "  |cff40ff40max|r" or ""))
                            rr.hl:Show()
                            rr:SetScript("OnMouseDown", function(self, button)
                                if button ~= "LeftButton" or drag.nodes then return end
                                drag.fromPalette = self
                                BeginDrag({ { kind = "cast", what = "spell", name = full, icon = sp.icon, unit = "default" } })
                            end)
                            AddTooltip(rr, "Casts exactly " .. full .. ".")
                        end
                    end
                else
                    AddTooltip(r, "Drag onto the canvas or into a slot, or click to add at the end.")
                end
            end
        end
    end
    if n == 0 then
        local r = Row()
        r.icon:Hide()
        r.hl:Hide()
        r.text:SetFontObject("GameFontDisableSmall")
        r.text:SetPoint("LEFT", 2, 0)
        r.text:SetText(filter ~= "" and "No matching spells." or "No spells found.")
        r:SetScript("OnMouseDown", nil)
        r:SetScript("OnEnter", nil)
    end
    spellList:SetHeight(math.max(y, 10))
    spellScroll:SetVerticalScroll(0)
end

-- A slot dropped from a spell row onto a block's slot uses the normal cursor;
-- dragging rows uses Snapcast' own drag, so it can land anywhere on the canvas.

local function DetectRole()
    if GetSpecialization and GetSpecializationRole then
        local ok, spec = pcall(GetSpecialization)
        if ok and spec then
            local ok2, role = pcall(GetSpecializationRole, spec)
            if ok2 then
                if role == "TANK" then return "tank" end
                if role == "HEALER" then return "healer" end
                if role == "DAMAGER" then return "dps" end
            end
        end
    end
    return "all"
end

local function RoleMatches(entryRole, role)
    if role == "all" or entryRole == "any" then return true end
    for r in entryRole:gmatch("[^,]+") do
        if r == role then return true end
    end
    return false
end

local ROLE_TEXT = { tank = "Tank", healer = "Healer", dps = "DPS", any = "Any role" }

function BuildClassPage(page)
    local _, playerClass = UnitClass("player")
    local state = { class = ns.LIBRARY[playerClass or ""] and playerClass or "WARRIOR", role = DetectRole() }
    local rows, roleBtns = {}, {}

    local classBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    classBtn:SetSize(148, 20)
    classBtn:SetPoint("TOPLEFT", 10, -2)

    local Refresh
    local roles = { { "all", "All" }, { "tank", "Tank" }, { "healer", "Heal" }, { "dps", "DPS" } }
    for i, r in ipairs(roles) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(35, 18)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 37.5, -26)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        b.sel = b:CreateTexture(nil, "BORDER")
        b.sel:SetPoint("BOTTOMLEFT")
        b.sel:SetPoint("BOTTOMRIGHT")
        b.sel:SetHeight(2)
        b.sel:SetColorTexture(1, 0.82, 0, 1)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(r[2])
        b.role = r[1]
        b:SetScript("OnClick", function() state.role = r[1]; Refresh() end)
        roleBtns[i] = b
    end

    for i = 1, 10 do
        local row
        row = DragSource(page, -50 - (i - 1) * 40, "", { 0.22, 0.2, 0.28, 0.95 },
            function() return row.entry.make() end, function() return row.entry.name end, nil, "round", true)
        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            local body = ns.Compile(e.make(), true)
            local roleText = {}
            for r in e.role:gmatch("[^,]+") do roleText[#roleText + 1] = ROLE_TEXT[r] or r end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.name, 1, 0.82, 0)
            GameTooltip:AddLine(table.concat(roleText, ", "), 0.6, 0.8, 1)
            GameTooltip:AddLine(e.desc, 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            for line in (body .. "\n"):gmatch("([^\n]*)\n") do GameTooltip:AddLine(line, 0.7, 0.7, 0.7) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Drag onto the canvas or click to add.", 0.5, 1, 0.5)
            GameTooltip:Show()
        end)
        rows[i] = row
    end

    local empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", 12, -56)
    empty:SetWidth(146)
    empty:SetJustifyH("LEFT")
    empty:SetText("No macros for this role. Try All.")

    function Refresh()
        classBtn:SetText((ns.CLASS_NAMES[state.class] or state.class) .. " v")
        for _, b in ipairs(roleBtns) do
            local on = b.role == state.role
            b.sel:SetShown(on)
            if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.7, 0.7, 0.7) end
        end
        local shown = 0
        for _, e in ipairs(ns.LIBRARY[state.class] or {}) do
            if RoleMatches(e.role, state.role) and shown < #rows then
                shown = shown + 1
                local row = rows[shown]
                row.entry = e
                row.text:SetText(e.name)
                local nodes = e.make()
                row.Paint(NodeColor(nodes[1]), NodesShape(nodes))
                row:Show()
            end
        end
        for i = shown + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
        empty:SetShown(shown == 0)
    end

    classBtn:SetScript("OnClick", function()
        local items = {}
        for _, c in ipairs(ns.CLASS_ORDER) do
            items[#items + 1] = { text = ns.CLASS_NAMES[c], func = function() state.class = c; Refresh() end }
        end
        ShowMenu("Class", items)
    end)
    Refresh()
end

local function BuildPalette(palette)
    local tabs, pages = {}, {}
    local function SelectTab(i)
        for j, pg in ipairs(pages) do
            if i == j then pg:Show() else pg:Hide() end
            if i == j then tabs[j].text:SetTextColor(1, 0.82, 0) else tabs[j].text:SetTextColor(0.7, 0.7, 0.7) end
            tabs[j].sel:SetShown(i == j)
        end
        if i == 2 then RefreshSpells() end
    end
    for i, name in ipairs({ "Blocks", "Spells", "Class", "Basic" }) do
        local t = CreateFrame("Button", nil, palette)
        t:SetSize(38, 20)
        t:SetPoint("TOPLEFT", 6 + (i - 1) * 39, -8)
        local bg = t:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        t.sel = t:CreateTexture(nil, "BORDER")
        t.sel:SetPoint("BOTTOMLEFT")
        t.sel:SetPoint("BOTTOMRIGHT")
        t.sel:SetHeight(2)
        t.sel:SetColorTexture(1, 0.82, 0, 1)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t.text:SetPoint("CENTER")
        t.text:SetText(name)
        t:SetScript("OnClick", function() SelectTab(i) end)
        tabs[i] = t
        local pg = CreateFrame("Frame", nil, palette)
        pg:SetPoint("TOPLEFT", 0, -32)
        pg:SetPoint("BOTTOMRIGHT", 0, 0)
        pages[i] = pg
    end

    -- Blocks
    local bp = pages[1]
    PaletteButton(bp, "spell",  "cast a spell",    -4)
    PaletteButton(bp, "item",   "use an item",     -34)
    PaletteButton(bp, "seq",    "cast sequence",   -64)
    PaletteButton(bp, "stop",   "stop casting",    -94)
    PaletteButton(bp, "attack", "start attacking", -124)
    PaletteButton(bp, "chat",   "chat message",    -154)
    PaletteButton(bp, "if",     "if / else",       -184)
    PaletteButton(bp, "raw",    "custom line",     -214)
    local tips = bp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tips:SetPoint("TOPLEFT", 12, -250)
    tips:SetWidth(146)
    tips:SetJustifyH("LEFT")
    tips:SetSpacing(3)
    tips:SetText(
        "|cffffd100Tips|r\n" ..
        "- Drag spells from the Spells tab, your spellbook or your bags onto the canvas or into a slot.\n\n" ..
        "- Drag a block to move it. Drag it off the canvas to delete it.\n\n" ..
        "- Round knob: fits anywhere. Square knob: main stack only.\n\n" ..
        "- Right-click a block to duplicate or delete it. Ctrl+Z undo.")

    -- Spells
    spellsPage = pages[2]
    spellSearch = CreateFrame("EditBox", nil, spellsPage, "InputBoxTemplate")
    spellSearch:SetSize(138, 20)
    spellSearch:SetPoint("TOPLEFT", 16, -2)
    spellSearch:SetAutoFocus(false)
    spellSearch:SetScript("OnEnterPressed", spellSearch.ClearFocus)
    spellSearch:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    spellSearch:SetScript("OnTextChanged", function() RefreshSpells() end)
    local hint = spellSearch:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("search...")
    spellSearch:HookScript("OnEditFocusGained", function() hint:Hide() end)
    spellSearch:HookScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
    spellScroll = CreateFrame("ScrollFrame", nil, spellsPage)
    spellScroll:SetPoint("TOPLEFT", 8, -28)
    spellScroll:SetPoint("BOTTOMRIGHT", -8, 8)
    spellList = CreateFrame("Frame", nil, spellScroll)
    spellList:SetSize(150, 10)
    spellScroll:SetScrollChild(spellList)
    spellScroll:EnableMouseWheel(true)
    spellScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, spellList:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 40)))
    end)

    -- Class library
    BuildClassPage(pages[3])

    -- Basic templates
    local tp = pages[4]
    for i, tpl in ipairs(TEMPLATES) do
        DragSource(tp, -4 - (i - 1) * 40, tpl.name, NodeColor(tpl.make()[1]), tpl.make, tpl.name,
            tpl.desc .. "\n\n|cff88ff88Drag onto the canvas or click to add, then fill the empty slots.|r",
            NodesShape(tpl.make()), true)
    end

    SelectTab(1)
end

------------------------------------------------------------------------
-- Icon picker (like Blizzard's macro icon chooser)
------------------------------------------------------------------------
local ICON_COLS, ICON_ROWS, ICON_SIZE, ICON_GAP = 10, 7, 36, 4
local iconPicker
local iconCache = {}

local function AddAll(dst, fillFunc)
    if type(fillFunc) ~= "function" then return end
    local tmp = {}
    if pcall(fillFunc, tmp) then
        for _, v in ipairs(tmp) do dst[#dst + 1] = v end
    end
end

-- tab: "spells" (your spellbook), "spell" (all spell icons), "item" (all item icons)
-- returns a list of { icon = fileID/path, name = optional }
local function IconList(tab, filter)
    if tab == "spells" then
        local out, seen = {}, {}
        local ok, groups = pcall(GetPlayerSpells)
        if ok then
            for _, g in ipairs(groups) do
                for _, sp in ipairs(g.spells) do
                    if sp.icon and not seen[sp.icon]
                        and (filter == "" or sp.name:lower():find(filter, 1, true)) then
                        seen[sp.icon] = true
                        out[#out + 1] = { icon = sp.icon, name = sp.name }
                    end
                end
            end
        end
        return out
    end
    if not iconCache[tab] then
        local raw = {}
        if tab == "spell" then
            AddAll(raw, GetLooseMacroIcons)
            AddAll(raw, GetMacroIcons)
        else
            AddAll(raw, GetLooseMacroItemIcons)
            AddAll(raw, GetMacroItemIcons)
        end
        local out, seen = {}, {}
        for _, v in ipairs(raw) do
            if v and not seen[v] then
                seen[v] = true
                out[#out + 1] = { icon = v }
            end
        end
        iconCache[tab] = out
    end
    return iconCache[tab]
end

local function ShowIconPicker()
    if not iconPicker then
        local p = CreateFrame("Frame", "SnapcastIconPicker", UIParent, "BackdropTemplate")
        local gridW = ICON_COLS * (ICON_SIZE + ICON_GAP)
        local gridH = ICON_ROWS * (ICON_SIZE + ICON_GAP)
        p:SetSize(gridW + 56, gridH + 178)
        p:SetFrameStrata("DIALOG")
        p:SetClampedToScreen(true)
        p:EnableMouse(true)
        p:SetMovable(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", p.StartMoving)
        p:SetScript("OnDragStop", p.StopMovingOrSizing)
        TooltipBackdrop(p, 0.97)
        tinsert(UISpecialFrames, "SnapcastIconPicker")

        local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -12)
        title:SetText("Choose an icon")
        local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)

        -- current choice
        p.current = p:CreateTexture(nil, "ARTWORK")
        p.current:SetSize(40, 40)
        p.current:SetPoint("TOPLEFT", 16, -34)
        p.currentText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        p.currentText:SetPoint("LEFT", p.current, "RIGHT", 8, 0)
        p.currentText:SetWidth(200)
        p.currentText:SetJustifyH("LEFT")

        local auto = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        auto:SetSize(150, 22)
        auto:SetPoint("TOPRIGHT", -16, -42)
        auto:SetText("Automatic (?)")
        auto:SetScript("OnClick", function()
            selectedIcon = nil
            p.Refresh()
            F.UpdatePreview()
        end)
        auto:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("The question-mark icon: with 'Show spell icon' ticked, the button shows whatever spell the macro is about to cast.", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        auto:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- tabs
        p.tab = "spells"
        p.tabs = {}
        -- tabs: plain text with a gold underline on the selected one
        local tabW = math.floor((gridW - 8) / 3)
        for i, t in ipairs({ { "spells", "Your spells" }, { "spell", "All spell icons" }, { "item", "Item icons" } }) do
            local b = CreateFrame("Button", nil, p)
            b:SetSize(tabW, 24)
            b:SetPoint("TOPLEFT", 18 + (i - 1) * (tabW + 4), -84)
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
            b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            b.label:SetPoint("CENTER", 0, 1)
            b.label:SetText(t[2])
            b.id = t[1]
            b:SetScript("OnClick", function() p.tab = t[1]; p.offset = 0; p.Refresh() end)
            p.tabs[i] = b
        end

        -- own row under the tabs, so nothing overlaps
        p.search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        p.search:SetSize(gridW - 10, 20)
        p.search:SetPoint("TOPLEFT", 24, -116)
        p.search:SetAutoFocus(false)
        p.search:SetScript("OnTextChanged", function() p.offset = 0; p.Refresh() end)
        p.search:SetScript("OnEnterPressed", p.search.ClearFocus)
        p.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
        local hint = p.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", 2, 0)
        hint:SetText("search spells...")
        p.search:HookScript("OnEditFocusGained", function() hint:Hide() end)
        p.search:HookScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
        p.browseHint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        p.browseHint:SetPoint("TOPLEFT", 20, -120)
        p.browseHint:SetText("Scroll with the mouse wheel to browse.")

        -- grid
        p.grid = CreateFrame("Frame", nil, p)
        p.grid:SetSize(gridW, gridH)
        p.grid:SetPoint("TOPLEFT", 18, -146)
        p.grid:EnableMouseWheel(true)
        p.buttons = {}
        for r = 0, ICON_ROWS - 1 do
            for c = 0, ICON_COLS - 1 do
                local b = CreateFrame("Button", nil, p.grid)
                b:SetSize(ICON_SIZE, ICON_SIZE)
                b:SetPoint("TOPLEFT", c * (ICON_SIZE + ICON_GAP), -r * (ICON_SIZE + ICON_GAP))
                b.tex = b:CreateTexture(nil, "ARTWORK")
                b.tex:SetAllPoints()
                b.sel = b:CreateTexture(nil, "OVERLAY")
                b.sel:SetPoint("TOPLEFT", -3, 3)
                b.sel:SetPoint("BOTTOMRIGHT", 3, -3)
                b.sel:SetColorTexture(1, 0.82, 0, 0.6)
                b.sel:SetDrawLayer("BACKGROUND")
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.25)
                b:SetScript("OnClick", function(self)
                    selectedIcon = self.icon
                    p.Refresh()
                    F.UpdatePreview()
                end)
                b:SetScript("OnEnter", function(self)
                    if self.name then
                        GameTooltip:SetOwner(self, "ANCHOR_TOP")
                        GameTooltip:SetText(self.name, 1, 1, 1)
                        GameTooltip:Show()
                    end
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                p.buttons[#p.buttons + 1] = b
            end
        end

        p.slider = CreateFrame("Slider", nil, p)
        p.slider:SetOrientation("VERTICAL")
        p.slider:SetSize(16, gridH)
        p.slider:SetPoint("TOPLEFT", p.grid, "TOPRIGHT", 6, 0)
        local track = p.slider:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(0, 0, 0, 0.5)
        p.slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        p.slider:SetValueStep(1)
        p.slider:SetObeyStepOnDrag(true)
        p.slider:SetScript("OnValueChanged", function(_, v)
            v = math.floor(v + 0.5)
            if v ~= p.offset then p.offset = v; p.Refresh(true) end
        end)
        local function Wheel(_, delta)
            local v = math.max(0, math.min(p.maxOffset or 0, (p.offset or 0) - delta * 2))
            if v ~= p.offset then
                p.offset = v
                p.Refresh()
            end
        end
        p.grid:SetScript("OnMouseWheel", Wheel)
        p:EnableMouseWheel(true)
        p:SetScript("OnMouseWheel", Wheel)

        p.count = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        p.count:SetPoint("BOTTOMLEFT", 18, 16)

        local done = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        done:SetSize(90, 22)
        done:SetPoint("BOTTOMRIGHT", -16, 12)
        done:SetText("Done")
        done:SetScript("OnClick", function() p:Hide() end)

        p.offset = 0
        function p.Refresh(fromSlider)
            for _, b in ipairs(p.tabs) do
                local on = b.id == p.tab
                b.sel:SetShown(on)
                if on then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(0.75, 0.75, 0.75) end
            end
            p.search:SetShown(p.tab == "spells")
            p.browseHint:SetShown(p.tab ~= "spells")
            local filter = p.tab == "spells" and trim(p.search:GetText()):lower() or ""
            local list = IconList(p.tab, filter)
            local rowsTotal = math.ceil(#list / ICON_COLS)
            local maxOffset = math.max(0, rowsTotal - ICON_ROWS)
            if p.offset > maxOffset then p.offset = maxOffset end
            p.maxOffset = maxOffset
            if not fromSlider then
                p.slider:SetMinMaxValues(0, maxOffset)
                p.slider:SetValue(p.offset)
            end
            p.slider:SetShown(maxOffset > 0)
            for i, b in ipairs(p.buttons) do
                local e = list[p.offset * ICON_COLS + i]
                if e then
                    b.icon, b.name = e.icon, e.name
                    b.tex:SetTexture(e.icon)
                    b.sel:SetShown(selectedIcon ~= nil and e.icon == selectedIcon)
                    b:Show()
                else
                    b.icon, b.name = nil, nil
                    b:Hide()
                end
            end
            if #list == 0 then
                p.count:SetText(p.tab == "spells" and "No matching spells." or "This icon list isn't available here.")
            else
                p.count:SetText(#list .. " icons")
            end
            p.current:SetTexture(selectedIcon or FirstIcon(tree) or QUESTION_ICON)
            p.currentText:SetText(selectedIcon and "Chosen icon" or
                "Automatic: the button shows the spell the macro is about to cast.")
        end

        p:SetPoint("LEFT", F, "RIGHT", 4, 0)
        iconPicker = p
    end
    iconPicker:Show()
    iconPicker.Refresh()
end

local function BuildUI()
    F = CreateFrame("Frame", "SnapcastFrame", UIParent, "BackdropTemplate")
    F:SetSize(780, 600)
    F:SetPoint("CENTER")
    F:SetFrameStrata("HIGH")
    F:SetMovable(true)
    F:SetClampedToScreen(true)
    F:EnableMouse(true)
    F:RegisterForDrag("LeftButton")
    F:SetScript("OnDragStart", F.StartMoving)
    F:SetScript("OnDragStop", F.StopMovingOrSizing)
    F:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    F:Hide()
    F:SetScale(DB.scale or 1)
    tinsert(UISpecialFrames, "SnapcastFrame")

    measure = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measure:Hide()

    local title = F:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Snapcast")

    local close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Palette ---------------------------------------------------------
    local palette = CreateFrame("Frame", nil, F, "BackdropTemplate")
    palette:SetPoint("TOPLEFT", 16, -40)
    palette:SetSize(168, 500)
    TooltipBackdrop(palette, 0.6)
    BuildPalette(palette)

    -- Undo / redo -----------------------------------------------------
    local undoBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    undoBtn:SetSize(56, 20)
    undoBtn:SetPoint("TOPRIGHT", -94, -14)
    undoBtn:SetText("Undo")
    undoBtn:SetScript("OnClick", Undo)
    local redoBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    redoBtn:SetSize(56, 20)
    redoBtn:SetPoint("LEFT", undoBtn, "RIGHT", 4, 0)
    redoBtn:SetText("Redo")
    redoBtn:SetScript("OnClick", Redo)
    F.undoBtn, F.redoBtn = undoBtn, redoBtn

    local explainBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    explainBtn:SetSize(76, 20)
    explainBtn:SetPoint("RIGHT", undoBtn, "LEFT", -10, 0)
    explainBtn:SetText("Explain")
    explainBtn:SetScript("OnClick", function(self)
        explainMode = not explainMode
        self:SetText(explainMode and "Macro text" or "Explain")
        F.UpdatePreview()
    end)

    local shareBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    shareBtn:SetSize(60, 20)
    shareBtn:SetPoint("TOPLEFT", 22, -14)
    shareBtn:SetText("Share")
    shareBtn:SetScript("OnClick", ShareCode)
    local importBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    importBtn:SetSize(60, 20)
    importBtn:SetPoint("LEFT", shareBtn, "RIGHT", 4, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", ImportCode)

    F:EnableKeyboard(true)
    if F.SetPropagateKeyboardInput then F:SetPropagateKeyboardInput(true) end
    F:SetScript("OnKeyDown", function(self, key)
        local handled = false
        if IsControlKeyDown() and key == "Z" then
            if IsShiftKeyDown() then Redo() else Undo() end
            handled = true
        elseif IsControlKeyDown() and key == "Y" then
            Redo()
            handled = true
        end
        if not InCombatLockdown() and self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(not handled)
        end
    end)

    -- Canvas ----------------------------------------------------------
    local canvasBox = CreateFrame("Frame", nil, F, "BackdropTemplate")
    canvasBox:SetPoint("TOPLEFT", 190, -40)
    canvasBox:SetSize(574, 336)
    TooltipBackdrop(canvasBox, 0.85)

    scroll = CreateFrame("ScrollFrame", nil, canvasBox)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(CANVAS_W, 300)
    scroll:SetScrollChild(canvas)
    local function OnWheel(_, delta)
        local maxScroll = math.max(0, canvas:GetHeight() - scroll:GetHeight())
        local v = math.min(maxScroll, math.max(0, scroll:GetVerticalScroll() - delta * 30))
        scroll:SetVerticalScroll(v)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", OnWheel)
    canvas:EnableMouseWheel(true)
    canvas:SetScript("OnMouseWheel", OnWheel)
    canvas:EnableMouse(true)
    canvas:SetScript("OnReceiveDrag", function() CanvasReceive() end)
    canvas:SetScript("OnMouseUp", function() if GetCursorInfo() then CanvasReceive() end end)

    local canvasBg = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
    canvasBg:SetAllPoints()
    SetTable(canvasBg)

    indicator = CreateFrame("Frame", nil, canvas)
    indicator:SetFrameLevel(canvas:GetFrameLevel() + 250)
    indicator.line = indicator:CreateTexture(nil, "OVERLAY")
    indicator.line:SetPoint("TOPLEFT")
    indicator.line:SetPoint("TOPRIGHT")
    indicator.line:SetHeight(2)
    indicator.shape = indicator:CreateTexture(nil, "OVERLAY")
    indicator.shape:SetPoint("TOPLEFT", NOTCH_X, -1)
    indicator.shape:SetSize(NOTCH_W, NOTCH_H)
    indicator.label = indicator:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    indicator.label:SetPoint("LEFT", indicator.shape, "RIGHT", 6, -2)
    indicator.label:SetTextColor(1, 0.35, 0.35)
    indicator:Hide()

    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetHeight(26)
    NewBrickParts(ghost)
    ghost.notch = ghost:CreateTexture(nil, "ARTWORK")
    ghost.notch:SetPoint("TOPLEFT", NOTCH_X, 0)
    ghost.notch:SetSize(NOTCH_W, NOTCH_H)
    ghost.tab = ghost:CreateTexture(nil, "ARTWORK")
    ghost.tab:SetPoint("TOPLEFT", ghost, "BOTTOMLEFT", NOTCH_X, 0)
    ghost.tab:SetSize(NOTCH_W, NOTCH_H)
    ghost.tab:SetTexture(MEDIA .. "knob_round")
    ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ghost.text:SetPoint("LEFT", NOTCH_X + NOTCH_W + 6, -2)
    ghost:Hide()

    -- Preview ---------------------------------------------------------
    local previewBox = CreateFrame("Frame", nil, F, "BackdropTemplate")
    previewBox:SetPoint("TOPLEFT", 190, -382)
    previewBox:SetSize(574, 104)
    TooltipBackdrop(previewBox, 0.9)
    local pl = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pl:SetPoint("TOPLEFT", 10, -8)
    pl:SetText("Macro text")
    F.previewLabel = pl
    countText = previewBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("TOPRIGHT", -10, -8)
    previewText = previewBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", 10, -24)
    previewText:SetPoint("BOTTOMRIGHT", -10, 8)
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")

    warnText = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warnText:SetPoint("TOPLEFT", 194, -490)
    warnText:SetWidth(566)
    warnText:SetJustifyH("LEFT")
    warnText:SetTextColor(1, 0.6, 0.2)

    -- Bottom bar ------------------------------------------------------
    local nl = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nl:SetPoint("BOTTOMLEFT", 24, 26)
    nl:SetText("Name")
    nameBox = CreateFrame("EditBox", nil, F, "InputBoxTemplate")
    nameBox:SetSize(120, 20)
    nameBox:SetPoint("LEFT", nl, "RIGHT", 10, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(16)
    nameBox:SetScript("OnEnterPressed", nameBox.ClearFocus)
    nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

    charCheck = CreateFrame("CheckButton", nil, F, "UICheckButtonTemplate")
    charCheck:SetSize(24, 24)
    charCheck:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
    local cl = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cl:SetPoint("LEFT", charCheck, "RIGHT", 0, 0)
    cl:SetText("This character only")

    tipCheck = CreateFrame("CheckButton", nil, F, "UICheckButtonTemplate")
    tipCheck:SetSize(24, 24)
    tipCheck:SetPoint("LEFT", cl, "RIGHT", 10, 0)
    tipCheck:SetChecked(true)
    tipCheck:SetScript("OnClick", function() F.UpdatePreview() end)
    local tl = F:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tl:SetPoint("LEFT", tipCheck, "RIGHT", 0, 0)
    tl:SetText("Show spell icon")

    local newBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    newBtn:SetSize(56, 22)
    newBtn:SetPoint("LEFT", tl, "RIGHT", 14, 0)
    newBtn:SetText("New")
    newBtn:SetScript("OnClick", NewBuild)

    local openBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    openBtn:SetSize(56, 22)
    openBtn:SetPoint("LEFT", newBtn, "RIGHT", 4, 0)
    openBtn:SetText("Open")
    openBtn:SetScript("OnClick", OpenMenu)

    local saveBtn = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
    saveBtn:SetSize(70, 22)
    saveBtn:SetPoint("LEFT", openBtn, "RIGHT", 10, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", SaveMacro)

    dragBtn = CreateFrame("Button", nil, F)
    dragBtn:SetSize(32, 32)
    dragBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    dragBtn.icon = dragBtn:CreateTexture(nil, "ARTWORK")
    dragBtn.icon:SetAllPoints()
    dragBtn.icon:SetTexture(QUESTION_ICON)
    local dhl = dragBtn:CreateTexture(nil, "HIGHLIGHT")
    dhl:SetAllPoints()
    dhl:SetColorTexture(1, 1, 1, 0.2)
    dragBtn:RegisterForDrag("LeftButton")
    dragBtn:SetScript("OnDragStart", PickupSaved)
    dragBtn:SetScript("OnClick", ShowIconPicker)
    dragBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Macro icon", 1, 0.82, 0)
        GameTooltip:AddLine("Click: choose an icon", 1, 1, 1)
        GameTooltip:AddLine("Drag: put the saved macro on your action bar", 1, 1, 1)
        GameTooltip:Show()
    end)
    dragBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function F.UpdatePreview()
        local body, warns = ns.Compile(tree, tipCheck:GetChecked())
        if explainMode then
            F.previewLabel:SetText("What it does")
            previewText:SetText(ns.Explain(tree, CondLabel))
        elseif body == "" then
            F.previewLabel:SetText("Macro text")
            previewText:SetText("|cff888888(empty - drag some blocks onto the canvas)|r")
        else
            F.previewLabel:SetText("Macro text")
            previewText:SetText(body)
        end
        local unknown = UnknownWarnings(tree, {})
        for i = 1, math.min(#unknown, 2) do
            table.insert(warns, 1, "'" .. unknown[i] .. "' isn't in your spellbook or bags - check the spelling, or you haven't learned it yet.")
        end
        local n = #body
        if n > MAX_CHARS then
            countText:SetText("|cffff4040" .. n .. " / " .. MAX_CHARS .. " - too long|r")
        else
            countText:SetText(n .. " / " .. MAX_CHARS)
        end
        warnText:SetText(table.concat(warns, "\n"))
        dragBtn.icon:SetTexture(selectedIcon or FirstIcon(tree) or QUESTION_ICON)
        if iconPicker and iconPicker:IsShown() then iconPicker.Refresh() end
    end

    F:SetScript("OnShow", Render)
end

local function Toggle()
    if InCombatLockdown() then
        Print("open me after combat.")
        return
    end
    if not F then BuildUI() end
    if F:IsShown() then F:Hide() else F:Show() end
end

------------------------------------------------------------------------
-- Options
------------------------------------------------------------------------
local minimapBtn, settingsPanel
local UpdateMinimapButton -- forward

local function OnOff(v) return v and "|cff40ff40On|r" or "|cffff6060Off|r" end

local function SetScaleOption(v)
    DB.scale = v
    if F then F:SetScale(v) end
end

local function SetMinimapShown(show)
    DB.minimap.hide = not show
    UpdateMinimapButton()
    if settingsPanel then settingsPanel.Refresh() end
    if not show then Print("minimap button hidden. Type /snap minimap to bring it back.") end
end

local function OptionsMenu()
    ShowMenu("Snapcast", {
        { text = "Open the builder", func = Toggle },
        { text = "Spell check: " .. OnOff(DB.spellCheck ~= false), func = function()
            DB.spellCheck = DB.spellCheck == false
            if settingsPanel then settingsPanel.Refresh() end
            if F and F:IsShown() then Render() end
        end },
        { text = "Window size: " .. math.floor((DB.scale or 1) * 100 + 0.5) .. "%", func = function()
            local items = {}
            for _, v in ipairs({ 0.8, 0.9, 1, 1.1, 1.25 }) do
                items[#items + 1] = { text = math.floor(v * 100 + 0.5) .. "%", func = function() SetScaleOption(v) end }
            end
            ShowMenu("Window size", items)
        end },
        { text = "Reset window position", func = function()
            if F then F:ClearAllPoints(); F:SetPoint("CENTER") end
        end },
        { text = "Hide minimap button", func = function() SetMinimapShown(false) end },
    })
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local function PlaceMinimapButton()
    local a = math.rad(DB.minimap.angle or 215)
    local r = (Minimap:GetWidth() / 2) + 10
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function UpdateMinimapButton()
    if not minimapBtn then return end
    if DB.minimap.hide then minimapBtn:Hide() else minimapBtn:Show(); PlaceMinimapButton() end
end

local function CreateMinimapButton()
    if minimapBtn or not Minimap then return end
    local b = CreateFrame("Button", "SnapcastMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "icon")
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", 6, -5)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then OptionsMenu() else Toggle() end
    end)
    b:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 7, -6) end)
    b:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 6, -5) end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            if not mx then return end
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
            DB.minimap.angle = math.deg(atan2(cy - my, cx - mx))
            PlaceMinimapButton()
        end)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Snapcast", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: open the macro builder", 1, 1, 1)
        GameTooltip:AddLine("Right-click: options", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapBtn = b
    UpdateMinimapButton()
end

------------------------------------------------------------------------
-- Settings page (Game Menu > Options > AddOns > Snapcast)
------------------------------------------------------------------------
local function RegisterSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local p = CreateFrame("Frame")
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Snapcast")
    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Build macros by snapping blocks together. Open it with /snap or the minimap button.")

    local function Check(label, y, get, set)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, y)
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(label)
        cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        cb.get = get
        return cb
    end
    local c1 = Check("Show the minimap button", -64, function() return not DB.minimap.hide end, SetMinimapShown)
    local c2 = Check("Spell check (red names for spells you don't know)", -94,
        function() return DB.spellCheck ~= false end,
        function(v) DB.spellCheck = v; if F and F:IsShown() then Render() end end)

    local open = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", 20, -134)
    open:SetText("Open the builder")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel) end
        Toggle()
    end)

    function p.Refresh()
        c1:SetChecked(c1.get())
        c2:SetChecked(c2.get())
    end
    p:SetScript("OnShow", p.Refresh)
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, p, "Snapcast")
    if ok and cat then
        pcall(Settings.RegisterAddOnCategory, cat)
        settingsPanel = p
    end
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        SnapcastDB = SnapcastDB or {}
        DB = SnapcastDB
        DB.builds = DB.builds or {}
        DB.minimap = DB.minimap or { angle = 215, hide = false }
        if DB.spellCheck == nil then DB.spellCheck = true end
        DB.scale = DB.scale or 1
    elseif event == "PLAYER_LOGIN" then
        CreateMinimapButton()
        pcall(RegisterSettings)
        Print("loaded. Click the minimap button or type /snap to build a macro.")
    elseif event == "SPELLS_CHANGED" then
        knownCache = nil
        RefreshSpells()
        if F and F:IsShown() then Render() end
    end
end)

SLASH_SNAPCAST1 = "/snap"
SLASH_SNAPCAST2 = "/snapcast"
SLASH_SNAPCAST3 = "/mb"
SlashCmdList.SNAPCAST = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "minimap" then
        SetMinimapShown(DB.minimap.hide)
    elseif msg == "options" then
        OptionsMenu()
    else
        Toggle()
    end
end
