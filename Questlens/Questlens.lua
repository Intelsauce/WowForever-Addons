-- Questlens: target a mob and see which of your quests it counts toward,
-- and how many more you need, right under the target frame.
--
-- Where the information comes from:
--   1. the quest lines the game itself puts in the mob's tooltip
--      (kill counts and quest items it can drop)
--   2. a backup that matches the mob's name against your quest log, plus
--      quest items Questlens has seen this kind of mob drop before

local ADDON_NAME = ...
local DB
local panel, lines = nil, {}
local MAX_LINES = 5

local function Print(msg) print("|cff66ccffQuestlens:|r " .. msg) end

local KILL_ICON = "Interface\\Icons\\Ability_DualWield"
local ITEM_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local function NpcID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function Progress(text)
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    return tonumber(have), tonumber(need)
end

-- "Kobold Vermin slain: 4/10" or "4/10 Kobold Vermin slain" -> "Kobold Vermin slain"
local function ObjectiveName(text)
    local s = text:gsub("%d+%s*/%s*%d+", ""):gsub("^%s*[%-:]?%s*", ""):gsub("%s*[:%-]%s*$", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ItemName(text)
    -- item objectives read "Wolf Meat: 3/8"; strip any "slain"/"collected" style suffix
    local n = ObjectiveName(text)
    return (n:gsub("%s+[Cc]ollected$", ""))
end

------------------------------------------------------------------------
-- Icons for quest items: remembered from your bags and from loot, or looked
-- up by name when the game already knows the item
------------------------------------------------------------------------
local function RememberIcon(name, icon)
    if type(name) == "string" and icon then DB.icons[name:lower()] = icon end
end

local function IconFor(name)
    if not name then return nil end
    local key = name:lower()
    if DB.icons[key] then return DB.icons[key] end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if instant then
        local ok, itemID, _, _, _, icon = pcall(instant, name)
        if ok and icon then
            DB.icons[key] = icon
            return icon
        end
    end
    return nil
end

local function ScanBagsForIcons()
    if not C_Container then return end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local it = C_Container.GetContainerItemInfo(bag, slot)
            if it and it.hyperlink and it.iconFileID then
                local name = it.hyperlink:match("%[(.-)%]")
                if name and not DB.icons[name:lower()] then RememberIcon(name, it.iconFileID) end
            end
        end
    end
end

------------------------------------------------------------------------
-- 1. The game's own tooltip quest lines
------------------------------------------------------------------------
local LT = Enum and Enum.TooltipDataLineType or {}

local function FromTooltip(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or not data or not data.lines then return nil end
    local out, quest = {}, nil
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and text ~= "" then
            if (LT.QuestTitle and line.type == LT.QuestTitle) then
                quest = text
            elseif (LT.QuestObjective and line.type == LT.QuestObjective) or (quest and text:find("%d+%s*/%s*%d+")) then
                local have, need = Progress(text)
                local name = ObjectiveName(text)
                if need then
                    out[#out + 1] = { text = name, have = have, need = need, quest = quest,
                                      kind = name:lower():find("slain") and "kill" or "item" }
                elseif text:find("^%s*%-") then
                    -- objectives without a count, e.g. " - Find the camp"
                    out[#out + 1] = { text = name, quest = quest, kind = "other",
                                      done = line.completed == true }
                end
            elseif LT.QuestPlayer and line.type == LT.QuestPlayer then
                -- a party member's name above their own progress: skip theirs
                quest = nil
            end
        end
    end
    return out
end

------------------------------------------------------------------------
-- 2. Backup: match the quest log
------------------------------------------------------------------------
local function ForEachObjective(fn)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local objs = C_QuestLog.GetQuestObjectives(info.questID) or {}
            for _, o in ipairs(objs) do
                if o.text then fn(info, o) end
            end
        end
    end
end

local function FromQuestLog(name, npcID)
    local out = {}
    if not name then return out end
    local lname = name:lower()
    local drops = npcID and DB.drops[npcID]
    ForEachObjective(function(info, o)
        local have, need = o.numFulfilled, o.numRequired
        if not need or need == 0 then have, need = Progress(o.text) end
        local text = ObjectiveName(o.text)
        local ltext = text:lower()
        if o.type == "monster" and ltext:find(lname, 1, true) then
            out[#out + 1] = { text = text, have = have, need = need, quest = info.title, kind = "kill", done = o.finished }
        elseif o.type == "item" and drops and drops[ItemName(o.text):lower()] then
            out[#out + 1] = { text = text, have = have, need = need, quest = info.title, kind = "item", done = o.finished, learned = true }
        end
    end)
    return out
end

------------------------------------------------------------------------
-- Learning which mobs drop which quest items
------------------------------------------------------------------------
local function QuestItemNames()
    local set = {}
    ForEachObjective(function(_, o)
        if o.type == "item" then set[ItemName(o.text):lower()] = true end
    end)
    return set
end

local function LearnFromLoot()
    if not GetNumLootItems then return end
    local wanted = QuestItemNames()
    if not next(wanted) then return end
    for slot = 1, GetNumLootItems() do
        local ok, link = pcall(GetLootSlotLink, slot)
        local itemName = ok and type(link) == "string" and link:match("%[(.-)%]")
        if itemName and wanted[itemName:lower()] then
            local icon = GetLootSlotInfo and select(1, GetLootSlotInfo(slot))
            if icon then RememberIcon(itemName, icon) end
        end
        if itemName and wanted[itemName:lower()] and GetLootSourceInfo then
            local sources = { GetLootSourceInfo(slot) }
            for i = 1, #sources, 2 do
                local guid = sources[i]
                if type(guid) == "string" then
                    local kind, _, _, _, _, id = strsplit("-", guid)
                    id = tonumber(id)
                    if id and (kind == "Creature" or kind == "Vehicle") then
                        DB.drops[id] = DB.drops[id] or {}
                        DB.drops[id][itemName:lower()] = true
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Putting it together
------------------------------------------------------------------------
local function Collect()
    if not UnitExists("target") or UnitIsPlayer("target") then return {} end
    local ok, isDead = pcall(UnitIsDead, "target")
    local okName, name = pcall(UnitName, "target")
    if not okName or type(name) ~= "string" then name = nil end
    local npcID = NpcID("target")

    local items = FromTooltip("target")
    if not items or #items == 0 then
        items = FromQuestLog(name, npcID)
    else
        -- add learned drops the tooltip didn't mention
        local have = {}
        for _, it in ipairs(items) do have[it.text:lower()] = true end
        for _, it in ipairs(FromQuestLog(name, npcID)) do
            if it.kind == "item" and not have[it.text:lower()] then items[#items + 1] = it end
        end
    end
    -- cache for combat, keyed by the kind of mob (progress is refreshed from the log)
    if npcID and #items > 0 then
        DB.lastSeen[npcID] = {}
        for _, it in ipairs(items) do
            table.insert(DB.lastSeen[npcID], { text = it.text, quest = it.quest, kind = it.kind })
        end
    end
    return items, (ok and isDead)
end

------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------
local function Anchor()
    panel:ClearAllPoints()
    if DB.pos then
        panel:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4])
    elseif TargetFrame then
        panel:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", 24, 8)
    else
        panel:SetPoint("TOP", UIParent, "TOP", 120, -170)
    end
end

local function Build()
    panel = CreateFrame("Frame", "QuestlensPanel", UIParent, "BackdropTemplate")
    panel:SetSize(230, 24)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.7)
    panel:SetBackdropBorderColor(0.4, 0.75, 1, 0.8)
    panel:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        DB.pos = { p, rp, x, y }
    end)
    panel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Questlens", 0.4, 0.8, 1)
        for _, l in ipairs(lines) do
            if l:IsShown() and l.quest then
                GameTooltip:AddDoubleLine(l.label:GetText(), l.quest, 1, 1, 1, 1, 0.82, 0)
            end
        end
        GameTooltip:AddLine("Shift-drag to move. /ql reset puts it back.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    panel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    for i = 1, MAX_LINES do
        local l = CreateFrame("Frame", nil, panel)
        l:SetSize(222, 18)
        l:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 18)
        l.icon = l:CreateTexture(nil, "ARTWORK")
        l.icon:SetSize(16, 16)
        l.icon:SetPoint("LEFT", 0, 0)
        -- green tick that sits on the icon when the objective is finished
        l.check = l:CreateTexture(nil, "OVERLAY")
        l.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        l.check:SetSize(14, 14)
        l.check:SetPoint("BOTTOMRIGHT", l.icon, "BOTTOMRIGHT", 5, -3)
        l.check:Hide()
        local ag = l.check.CreateAnimationGroup and l.check:CreateAnimationGroup()
        if ag and ag.CreateAnimation then
            local grow = ag:CreateAnimation("Scale")
            if grow.SetScale then grow:SetScale(2, 2) elseif grow.SetScaleFrom then grow:SetScaleFrom(2, 2); grow:SetScaleTo(1, 1) end
            grow:SetDuration(0.01)
            grow:SetOrder(1)
            local back = ag:CreateAnimation("Scale")
            if back.SetScale then back:SetScale(0.5, 0.5) elseif back.SetScaleFrom then back:SetScaleFrom(2, 2); back:SetScaleTo(1, 1) end
            back:SetDuration(0.35)
            back:SetOrder(2)
            l.pop = ag
        end
        l.count = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l.count:SetPoint("LEFT", l.icon, "RIGHT", 4, 0)
        l.count:SetWidth(40)
        l.count:SetJustifyH("LEFT")
        l.label = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l.label:SetPoint("LEFT", l.count, "RIGHT", 2, 0)
        l.label:SetPoint("RIGHT", 0, 0)
        l.label:SetJustifyH("LEFT")
        l.label:SetWordWrap(false)
        lines[i] = l
    end
    Anchor()
    panel:Hide()
end

local seenDone = {}  -- objective key -> false (seen unfinished) / true (finished)

local function Show(items, isDead)
    if not panel then return end
    if not items or #items == 0 or DB.hidden then
        panel:Hide()
        return
    end
    local n = 0
    for _, it in ipairs(items) do
        if n >= MAX_LINES then break end
        n = n + 1
        local l = lines[n]
        local done = it.done or (it.need and it.have and it.have >= it.need)
        l.icon:SetTexCoord(0, 1, 0, 1)
        if it.kind == "kill" then
            -- the mob's own face, if the game will draw it
            local ok = SetPortraitTexture and pcall(SetPortraitTexture, l.icon, "target")
            if not ok then l.icon:SetTexture(KILL_ICON) end
        elseif it.kind == "item" then
            local icon = IconFor(ItemName(it.text))
            if icon then
                l.icon:SetTexture(icon)
                l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the icon border
            else
                l.icon:SetTexture(ITEM_ICON)
            end
        else
            l.icon:SetTexture(QUEST_ICON)
        end
        if it.need then
            local col = done and "|cff40ff40" or (it.have and it.have > 0 and "|cffffd100" or "|cffffffff")
            l.count:SetText(col .. (it.have or 0) .. "/" .. it.need .. "|r")
            if done then l.count:SetText("|cff40ff40" .. it.need .. "/" .. it.need .. "|r") end
        else
            l.count:SetText(done and "|cff40ff40done|r" or "")
        end
        local label = it.text
        if done then
            label = "|cff808080" .. label .. "|r  |cff40ff40Done!|r"
        elseif it.kind == "item" and it.need and it.have then
            label = label .. "  |cffaaaaaa(" .. (it.need - it.have) .. " more)|r"
        elseif it.kind == "kill" and it.need and it.have then
            label = label .. "  |cffaaaaaa(" .. (it.need - it.have) .. " more)|r"
        end
        if it.learned then label = label .. " |cff66ccff*|r" end
        l.check:SetShown(done and true or false)
        local key = (it.quest or "") .. "|" .. (it.text or "")
        if done then
            if seenDone[key] == false then
                -- just finished: pop the tick and play the objective sound
                if l.pop then l.pop:Stop(); l.pop:Play() end
                if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_OBJECTIVE_COMPLETE then
                    pcall(PlaySound, SOUNDKIT.UI_QUEST_OBJECTIVE_COMPLETE)
                end
            end
            seenDone[key] = true
        elseif seenDone[key] == nil then
            seenDone[key] = false
        end
        l.label:SetText(label)
        l.quest = it.quest and ((done and "|cff40ff40" or "|cffffd100") .. it.quest .. "|r") or nil
        l:Show()
    end
    for i = n + 1, MAX_LINES do lines[i]:Hide(); lines[i].quest = nil end
    panel:SetHeight(8 + n * 18)
    panel:SetAlpha(isDead and 0.6 or 1)
    panel:Show()
end

local function Refresh()
    if not panel then return end
    local ok, items, isDead = pcall(Collect)
    if not ok then items = nil end
    -- in combat the game may hide tooltip details: fall back to what we saw last time
    if (not items or #items == 0) and InCombatLockdown() then
        local npcID = NpcID("target")
        local cached = npcID and DB.lastSeen[npcID]
        if cached then
            items = {}
            for _, c in ipairs(cached) do
                local it = { text = c.text, quest = c.quest, kind = c.kind }
                -- refresh the count from the quest log
                ForEachObjective(function(info, o)
                    if info.title == c.quest and ObjectiveName(o.text) == c.text then
                        it.have, it.need, it.done = o.numFulfilled, o.numRequired, o.finished
                    end
                end)
                items[#items + 1] = it
            end
        end
    end
    Show(items, isDead)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED", "QUEST_LOG_UPDATE",
                     "UNIT_QUEST_LOG_CHANGED", "LOOT_READY", "UNIT_FLAGS", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local pending
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function() pending = false; Refresh() end)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        QuestlensDB = QuestlensDB or {}
        DB = QuestlensDB
        DB.drops = DB.drops or {}
        DB.lastSeen = DB.lastSeen or {}
        DB.icons = DB.icons or {}
    elseif event == "PLAYER_LOGIN" then
        Build()
        pcall(ScanBagsForIcons)
    elseif event == "BAG_UPDATE_DELAYED" then
        pcall(ScanBagsForIcons)
        Soon()
    elseif event == "LOOT_READY" then
        pcall(LearnFromLoot)
    elseif event == "UNIT_FLAGS" then
        if arg1 == "target" then Soon() end
    else
        Soon()
    end
end)

SLASH_QUESTLENS1 = "/ql"
SLASH_QUESTLENS2 = "/questlens"
SlashCmdList.QUESTLENS = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        DB.pos = nil
        Anchor()
        Print("moved back under the target frame.")
    elseif msg == "hide" then
        DB.hidden = true
        Refresh()
        Print("hidden. /ql show brings it back.")
    elseif msg == "show" then
        DB.hidden = false
        Refresh()
    elseif msg == "forget" then
        wipe(DB.drops)
        wipe(DB.lastSeen)
        Print("forgot everything learned about quest drops.")
    else
        Print("target a mob to see how it fits your quests. Shift-drag the panel to move it.")
        Print("/ql reset  /ql hide  /ql show  /ql forget")
    end
end
