-- Snapcast: plain-English explanations, share codes, and turning
-- existing macro text back into blocks. No UI code here.

local _, ns = ...
ns = ns or SnapcastNS
local trim = ns.trim

------------------------------------------------------------------------
-- Cleaning (used for anything that comes from a share code)
------------------------------------------------------------------------
-- Names can't contain anything that would start a new macro line or
-- change the meaning of a macro option.
local function CleanName(v, max)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[\r\n|;%[%]]", " "):gsub(",", " ")
    v = trim(v):gsub("^/+", "")
    if v == "" then return nil end
    return v:sub(1, max or 100)
end

local function CleanText(v, max)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[\r\n|]", " ")
    return v:sub(1, max or 200)
end

local function CleanIcon(v)
    if type(v) == "number" then return v end
    if type(v) == "string" and v:match("^[%w_\\/%.%-]+$") then return v end
end

local function CleanKey(v)
    if type(v) == "string" and #v <= 40 and v:match("^[%w:/_%.]+$") then return v:lower() end
end

local function CleanUnit(v)
    if type(v) == "string" and #v <= 20 and v:match("^%a+%d*$") then return v:lower() end
end

local KINDS = { cast = true, attack = true, chat = true, ["if"] = true, seq = true, stop = true, raw = true }
local CHANNELS = { s = true, y = true, p = true, ra = true, i = true, e = true }

local function CleanConds(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, c in ipairs(list) do
        if type(c) == "table" and #out < 4 then
            local key = CleanKey(c.key)
            if key then out[#out + 1] = { key = key, unit = CleanUnit(c.unit) } end
        end
    end
    return out
end

local function CleanList(list, depth)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, n in ipairs(list) do
        if type(n) == "table" and KINDS[n.kind] and #out < 40 then
            local k, c = n.kind, nil
            if k == "cast" then
                c = { kind = "cast", what = n.what == "item" and "item" or "spell", name = CleanName(n.name),
                      icon = CleanIcon(n.icon), unit = CleanUnit(n.unit) or "default" }
            elseif k == "chat" then
                c = { kind = "chat", channel = CHANNELS[n.channel] and n.channel or "s", text = CleanText(n.text) or "" }
            elseif k == "raw" then
                if depth == 0 then c = { kind = "raw", text = CleanText(n.text, 255) or "" } end
            elseif k == "seq" then
                c = { kind = "seq", reset = (type(n.reset) == "string" and n.reset:match("^[%w/]*$")) and n.reset or "", spells = {} }
                if type(n.spells) == "table" then
                    for _, sp in ipairs(n.spells) do
                        if type(sp) == "table" and #c.spells < 12 then
                            c.spells[#c.spells + 1] = { name = CleanName(sp.name), icon = CleanIcon(sp.icon),
                                                        what = sp.what == "item" and "item" or "spell" }
                        end
                    end
                end
            elseif k == "if" then
                if depth == 0 and type(n.branches) == "table" then
                    c = { kind = "if", branches = {} }
                    for _, br in ipairs(n.branches) do
                        if type(br) == "table" and #c.branches < 6 then
                            c.branches[#c.branches + 1] = { conds = CleanConds(br.conds), body = CleanList(br.body, 1) }
                        end
                    end
                    if type(n.elseBody) == "table" then c.elseBody = CleanList(n.elseBody, 1) end
                    if #c.branches == 0 then c = nil end
                end
            else
                c = { kind = k }
            end
            if c then out[#out + 1] = c end
        end
    end
    return out
end
ns.CleanTree = function(t) return CleanList(t, 0) end

------------------------------------------------------------------------
-- Share codes:  SC1:{...}  (older MB1: codes still import)
------------------------------------------------------------------------
local ESC = { ["\\"] = "\\\\", ['"'] = '\\"', ["|"] = "\\p", ["\n"] = "\\n" }
local UNESC = { ["\\"] = "\\", ['"'] = '"', p = "|", n = "\n" }

local function Enc(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do
            Enc(v[i], out)
            out[#out + 1] = ","
        end
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            out[#out + 1] = k .. "="
            Enc(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = '"' .. v:gsub('[\\"|\n]', ESC) .. '"'
    elseif t == "number" then
        out[#out + 1] = tostring(v)
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    else
        out[#out + 1] = "F"
    end
end

function ns.Encode(tree)
    local out = {}
    Enc(tree, out)
    return "SC1:" .. table.concat(out)
end

local function Dec(s)
    local pos = 1
    local function fail(msg) error({ mb = msg }, 0) end
    local value
    local function str()
        pos = pos + 1
        local buf = {}
        while true do
            local c = s:sub(pos, pos)
            if c == "" then fail("the code is cut off") end
            if c == '"' then pos = pos + 1 break end
            if c == "\\" then
                local u = UNESC[s:sub(pos + 1, pos + 1)]
                if not u then fail("the code is damaged") end
                buf[#buf + 1] = u
                pos = pos + 2
            else
                buf[#buf + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(buf)
    end
    function value(depth)
        if depth > 12 then fail("the code is too deeply nested") end
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local t, n = {}, 0
            while true do
                c = s:sub(pos, pos)
                if c == "}" then pos = pos + 1 return t end
                if c == "" then fail("the code is cut off") end
                local key = s:match("^([%a_][%w_]*)=", pos)
                if key then
                    pos = pos + #key + 1
                    t[key] = value(depth + 1)
                else
                    n = n + 1
                    if n > 200 then fail("the code is too big") end
                    t[n] = value(depth + 1)
                end
                if s:sub(pos, pos) == "," then pos = pos + 1 end
            end
        elseif c == '"' then
            return str()
        elseif c == "T" then
            pos = pos + 1
            return true
        elseif c == "F" then
            pos = pos + 1
            return false
        end
        local num = s:match("^%-?%d+%.?%d*", pos)
        if num then
            pos = pos + #num
            return tonumber(num)
        end
        fail("the code is damaged")
    end
    local ok, res = pcall(value, 0)
    if not ok then return nil, type(res) == "table" and res.mb or "the code is damaged" end
    if pos <= #s then return nil, "the code has extra text at the end" end
    return res
end

-- Returns tree, or nil + reason. Everything is cleaned before use.
function ns.Decode(code)
    if type(code) ~= "string" then return nil, "no code" end
    code = trim(code)
    if #code > 20000 then return nil, "the code is too big" end
    local body = code:match("^SC1:(.*)$") or code:match("^MB1:(.*)$")
    if not body then return nil, "that isn't a Snapcast code (they start with SC1:)" end
    local t, err = Dec(body)
    if not t then return nil, err end
    if type(t) ~= "table" then return nil, "the code is damaged" end
    local tree = CleanList(t, 0)
    if #tree == 0 then return nil, "the code has no blocks in it" end
    return tree
end

-- Custom lines that run code deserve a second look before saving.
function ns.RiskyLines(tree)
    local risky = {}
    for _, n in ipairs(tree) do
        if n.kind == "raw" then
            local cmd = (n.text or ""):match("^%s*/(%S+)")
            cmd = cmd and cmd:lower()
            if cmd == "run" or cmd == "script" or cmd == "dump" or cmd == "click" then
                risky[#risky + 1] = n.text
            end
        end
    end
    return risky
end

------------------------------------------------------------------------
-- Macro text -> blocks
------------------------------------------------------------------------
local CHAT = { s = "s", say = "s", y = "y", yell = "y", sh = "y", shout = "y", p = "p", party = "p",
               ra = "ra", raid = "ra", i = "i", instance = "i", e = "e", em = "e", emote = "e", me = "e" }
local UNIT_BASE = { exists = true, help = true, harm = true, dead = true }

local function IsUnitKey(key)
    return UNIT_BASE[key] or UNIT_BASE[key:gsub("^no", "")] or false
end

-- "[a,b][c] rest" -> { "a,b", "c" }, "rest"
local function SplitGroups(text)
    local groups, rest = {}, text
    while true do
        rest = rest:gsub("^%s+", "")
        local inner, after = rest:match("^%[([^%]]*)%](.*)$")
        if not inner then break end
        groups[#groups + 1] = inner
        rest = after
    end
    return groups, rest
end

-- "@mouseover,help,nodead" -> conds, unit, hasUnitCheck   (nil if unsupported)
local function ParseGroup(inner)
    local conds, unit, hasUnit = {}, nil, false
    for rawPart in (inner .. ","):gmatch("([^,]*),") do
        local part = trim(rawPart)
        if part ~= "" then
            local u = part:match("^@(.+)$") or part:match("^[Tt][Aa][Rr][Gg][Ee][Tt]=(.+)$")
            if u then
                unit = CleanUnit(trim(u))
                if not unit then return nil end
            else
                local key = CleanKey(part)
                if not key then return nil end
                conds[#conds + 1] = { key = key }
            end
        end
    end
    if #conds > 4 then return nil end
    for _, c in ipairs(conds) do
        if IsUnitKey(c.key) then
            c.unit = unit or "target"
            hasUnit = true
        end
    end
    return conds, unit, hasUnit
end

local function CastNode(name, isItem, unit)
    name = CleanName(name)
    if not name then return nil end
    if unit == "target" then unit = nil end
    return { kind = "cast", what = isItem and "item" or "spell", name = name, unit = unit or "default" }
end

local function ParseCast(rest, isItem)
    local parsed = {}
    for clause in (rest .. ";"):gmatch("([^;]*);") do
        local groups, action = SplitGroups(clause)
        if #groups > 1 then return nil end
        local p = { conds = {}, action = trim(action) }
        if #groups == 1 then
            p.conds, p.unit, p.hasUnit = ParseGroup(groups[1])
            if not p.conds then return nil end
        end
        parsed[#parsed + 1] = p
    end
    -- trailing "; " produces an empty last clause
    if #parsed > 1 and #parsed[#parsed].conds == 0 and parsed[#parsed].action == "" and not parsed[#parsed].unit then
        parsed[#parsed] = nil
    end
    if #parsed == 1 and #parsed[1].conds == 0 then
        return CastNode(parsed[1].action, isItem, parsed[1].unit)
    end
    local node = { kind = "if", branches = {} }
    for _, p in ipairs(parsed) do
        local cast = p.action ~= "" and CastNode(p.action, isItem, (not p.hasUnit) and p.unit or nil) or nil
        if p.action ~= "" and not cast then return nil end
        if #p.conds == 0 then
            node.elseBody = { cast }
            break
        end
        if #node.branches >= 6 then return nil end
        node.branches[#node.branches + 1] = { conds = p.conds, body = { cast } }
    end
    if #node.branches == 0 then return node.elseBody and node.elseBody[1] end
    return node
end

-- wrap a single block in an 'if' when the line had conditions
local function Wrap(groups, block)
    if #groups == 0 then return block end
    if #groups > 1 then return nil end
    local conds, unit, hasUnit = ParseGroup(groups[1])
    if not conds then return nil end
    if unit and not hasUnit then return nil end -- e.g. /startattack [@focus]
    if #conds == 0 then return block end
    return { kind = "if", branches = { { conds = conds, body = { block } } } }
end

local function ParseLine(line)
    local cmd, rest = line:match("^/(%S+)%s*(.*)$")
    if not cmd then return nil end
    cmd = cmd:lower()
    if cmd == "cast" or cmd == "use" or cmd == "spell" then
        return ParseCast(rest, cmd == "use")
    elseif cmd == "castsequence" then
        local groups, after = SplitGroups(rest)
        local reset = after:match("^reset=(%S+)%s+")
        if reset then after = after:gsub("^reset=%S+%s+", "") end
        local seq = { kind = "seq", reset = (reset and reset:match("^[%w/]+$")) and reset or "", spells = {} }
        for part in (after .. ","):gmatch("([^,]*),") do
            local name = CleanName(part)
            if name then seq.spells[#seq.spells + 1] = { name = name } end
        end
        if #seq.spells == 0 then return nil end
        return Wrap(groups, seq)
    elseif cmd == "stopcasting" then
        return Wrap((SplitGroups(rest)), { kind = "stop" })
    elseif cmd == "startattack" then
        local groups, after = SplitGroups(rest)
        if trim(after) ~= "" then return nil end
        return Wrap(groups, { kind = "attack" })
    elseif CHAT[cmd] then
        if rest:match("^%s*%[") then return nil end
        local text = CleanText(trim(rest))
        if not text or text == "" then return nil end
        return { kind = "chat", channel = CHAT[cmd], text = text }
    end
    return nil
end

-- Returns tree, showTooltip, number of lines kept as custom lines
function ns.ParseMacro(body)
    local tree, showTip, custom = {}, false, 0
    for rawLine in ((body or "") .. "\n"):gmatch("([^\n]*)\n") do
        local line = trim(rawLine)
        if line ~= "" then
            local lower = line:lower()
            if lower:match("^#showtooltip") then
                showTip = true
            elseif not lower:match("^#show") then
                local node = ParseLine(line)
                if not node then
                    node = { kind = "raw", text = line:sub(1, 255) }
                    custom = custom + 1
                end
                tree[#tree + 1] = node
            else
                tree[#tree + 1] = { kind = "raw", text = line }
                custom = custom + 1
            end
        end
    end
    return tree, showTip, custom
end

------------------------------------------------------------------------
-- Plain English
------------------------------------------------------------------------
local UNIT_PHRASE = {
    default = "your target", target = "your target", mouseover = "whoever is under your mouse",
    focus = "your focus", player = "yourself", cursor = "the spot under your mouse",
    pet = "your pet", targettarget = "your target's target",
}
local CHANNEL_PHRASE = { s = "say", y = "yell", p = "tell your party", ra = "tell your raid", i = "tell your instance group", e = "emote" }
local RESET_PHRASE = {
    target = "when you change target", combat = "when you leave combat", shift = "when you hold Shift",
    ctrl = "when you hold Ctrl", alt = "when you hold Alt",
}

local function Up(id) return UNIT_PHRASE[id or "default"] or id end

local function ResetPhrase(reset)
    if not reset or reset == "" then return "" end
    local parts = {}
    for p in reset:gmatch("[^/]+") do
        if tonumber(p) then parts[#parts + 1] = "after " .. p .. " seconds without pressing it"
        else parts[#parts + 1] = RESET_PHRASE[p] or p end
    end
    return " (starts over " .. table.concat(parts, " or ") .. ")"
end

local function Action(n, ctxUnit)
    if n.kind == "cast" then
        local name = (n.name and trim(n.name) ~= "") and n.name or "(empty slot)"
        local unit = (n.unit and n.unit ~= "default") and n.unit or ctxUnit
        if n.what == "item" then
            return "use " .. name .. ((unit and unit ~= "target") and (" on " .. Up(unit)) or "")
        end
        if not unit or unit == "default" then return "cast " .. name end
        return "cast " .. name .. " on " .. Up(unit)
    elseif n.kind == "seq" then
        local names = {}
        for _, sp in ipairs(n.spells or {}) do names[#names + 1] = sp.name or "(empty)" end
        return "cast the next spell of " .. table.concat(names, " > ") .. ResetPhrase(n.reset)
    elseif n.kind == "stop" then
        return "stop whatever you're casting"
    elseif n.kind == "attack" then
        return "turn on auto-attack"
    elseif n.kind == "chat" then
        return (CHANNEL_PHRASE[n.channel] or "say") .. ' "' .. (n.text or "") .. '"'
    elseif n.kind == "raw" then
        local line = trim(n.text or "")
        return line == "" and "(empty custom line)" or ("run the line " .. line)
    end
    return "?"
end

local function Cap(s) return (s:gsub("^%l", string.upper)) end

local function Actions(body, ctxUnit)
    if not body or #body == 0 then return "do nothing" end
    local parts = {}
    for _, n in ipairs(body) do parts[#parts + 1] = Action(n, ctxUnit) end
    return table.concat(parts, ", then ")
end

-- condLabel(c) gives the UI wording for a condition, e.g. "Shift is held"
function ns.Explain(tree, condLabel)
    local out = { "When you press it:" }
    if #tree == 0 then return "Nothing yet - add some blocks." end
    for _, n in ipairs(tree) do
        if n.kind == "if" then
            for i, br in ipairs(n.branches or {}) do
                local cs, unit = {}, nil
                for _, c in ipairs(br.conds or {}) do
                    cs[#cs + 1] = condLabel(c)
                    unit = unit or c.unit
                end
                local cond = #cs > 0 and table.concat(cs, " and ") or "(no condition yet)"
                out[#out + 1] = "- " .. (i == 1 and "If " or "Otherwise, if ") .. cond .. ": " .. Actions(br.body, unit) .. "."
            end
            if n.elseBody then
                out[#out + 1] = "- Otherwise: " .. Actions(n.elseBody) .. "."
            end
        else
            out[#out + 1] = "- " .. Cap(Action(n)) .. "."
        end
    end
    return table.concat(out, "\n")
end
