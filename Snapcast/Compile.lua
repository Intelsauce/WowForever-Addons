-- Snapcast: turns a tree of blocks into real macro text.
-- Kept separate from the UI so it can be tested on its own.

local _, ns = ...
ns = ns or {}
SnapcastNS = ns -- exposed for testing outside the game

local unpack = unpack or table.unpack

local function trim(s)
    return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1"))
end
ns.trim = trim

-- Conditions that are checked against a unit (@target, @mouseover, ...)
local UNIT_KEYS = { exists = true, help = true, harm = true, dead = true, nodead = true }
ns.UNIT_KEYS = UNIT_KEYS

local function Neg(atom)
    if atom:sub(1, 2) == "no" then return atom:sub(3) end
    return "no" .. atom
end

local function Bracket(unit, atoms)
    local p = {}
    if unit then p[#p + 1] = "@" .. unit end
    for _, a in ipairs(atoms) do p[#p + 1] = a end
    if #p == 0 then return "" end
    return "[" .. table.concat(p, ",") .. "]"
end

local function Join(a, b)
    if a == "" then return b end
    if b == "" then return a end
    return a .. " " .. b
end

local function ActionName(n)
    local name = trim(n.name)
    if name == "" then return nil end
    return name
end

local function CastUnit(n)
    if n.unit and n.unit ~= "default" then return n.unit end
    return nil
end

local function SeqLine(n, cond, warn)
    local names = {}
    for _, s in ipairs(n.spells or {}) do
        local nm = trim(s.name)
        if nm ~= "" then names[#names + 1] = nm end
    end
    if #names == 0 then
        warn("A cast sequence has no spells yet.")
        return nil
    end
    local line = "/castsequence"
    if cond and cond ~= "" then line = line .. " " .. cond end
    if n.reset and n.reset ~= "" then line = line .. " reset=" .. n.reset end
    return line .. " " .. table.concat(names, ", ")
end

local function CompileIf(node, lines, warn)
    -- Gather each branch's conditions.
    local branches = {}
    for _, br in ipairs(node.branches or {}) do
        local unit, atoms, hasUnitCheck = nil, {}, false
        for _, c in ipairs(br.conds or {}) do
            if c.unit then
                hasUnitCheck = true
                if unit and unit ~= c.unit then
                    warn("One 'if' checks two different units. WoW can only check one unit per condition, so the first one is used.")
                else
                    unit = c.unit
                end
            end
            atoms[#atoms + 1] = c.key
        end
        if #atoms == 0 then
            warn("An 'if' has no condition, so it always matches and the branches after it never run.")
        end
        branches[#branches + 1] = { unit = unit, atoms = atoms, body = br.body or {}, hasUnitCheck = hasUnitCheck }
    end
    if node.elseBody then
        branches[#branches + 1] = { unit = nil, atoms = {}, body = node.elseBody, isElse = true }
    end

    -- Condition text for a block that sits on its own line (stop casting,
    -- start attacking, cast sequence): its own branch's conditions AND
    -- "none of the earlier branches matched".
    -- Returns "" for "always", or nil when the branch can never be reached.
    local condCache = {}
    local function CondFor(i)
        if condCache[i] ~= nil then return condCache[i] or nil end
        local b = branches[i]
        local groups = { { unit = b.unit, atoms = { unpack(b.atoms) } } }
        for j = 1, i - 1 do
            local p = branches[j]
            if #p.atoms == 0 then
                condCache[i] = false
                return nil
            end
            if p.hasUnitCheck then
                warn("Blocks other than 'cast' after an 'if' that checks a unit can't skip that earlier check (a WoW limit), so they only use their own condition.")
            else
                local ng = {}
                for _, g in ipairs(groups) do
                    for _, a in ipairs(p.atoms) do
                        local copy = { unpack(g.atoms) }
                        copy[#copy + 1] = Neg(a)
                        ng[#ng + 1] = { unit = g.unit, atoms = copy }
                    end
                end
                groups = ng
                if #groups > 8 then
                    warn("A block is inside a long if/else chain, so it only uses its own condition.")
                    groups = { { unit = b.unit, atoms = { unpack(b.atoms) } } }
                    break
                end
            end
        end
        local parts = {}
        for _, g in ipairs(groups) do
            local br = Bracket(g.unit, g.atoms)
            if br == "" then
                condCache[i] = ""
                return ""
            end
            parts[#parts + 1] = br
        end
        local result = table.concat(parts, "")
        condCache[i] = result
        return result
    end

    local function Emit(kind, once, make)
        for i, b in ipairs(branches) do
            for _, n in ipairs(b.body) do
                if n.kind == kind then
                    local c = CondFor(i)
                    if c then
                        local line = make(n, c)
                        if line then lines[#lines + 1] = line end
                    end
                    if once then break end
                end
            end
        end
    end

    Emit("stop", true, function(_, c) return Join("/stopcasting", c) end)
    Emit("attack", true, function(_, c) return Join("/startattack", c) end)

    -- Cast/use lines: the k-th spell of every branch shares one line, so the
    -- first branch that matches wins, exactly like if / else if / else.
    local castLists, maxK, anyItem = {}, 0, false
    for i, b in ipairs(branches) do
        local cl = {}
        for _, n in ipairs(b.body) do
            if n.kind == "cast" then
                if ActionName(n) then
                    cl[#cl + 1] = n
                    if n.what == "item" then anyItem = true end
                else
                    warn("A cast/use block has an empty slot. Drag a spell or item into it.")
                end
            end
        end
        castLists[i] = cl
        if #cl > maxK then maxK = #cl end
    end
    for k = 1, maxK do
        local clauses, hasAction = {}, {}
        for i, b in ipairs(branches) do
            local a = castLists[i][k]
            local unit = b.unit
            if a and CastUnit(a) then
                if b.hasUnitCheck and b.unit ~= CastUnit(a) then
                    warn("A spell is cast 'on' a different unit than its 'if' checks. WoW applies the check to the 'on' unit.")
                end
                unit = CastUnit(a)
            end
            local br = Bracket(unit, b.atoms)
            if a then
                clauses[#clauses + 1] = Join(br, ActionName(a))
                hasAction[#clauses] = true
            elseif not b.isElse then
                clauses[#clauses + 1] = br -- condition matches but does nothing
                hasAction[#clauses] = false
            end
        end
        while #clauses > 0 and not hasAction[#clauses] do
            clauses[#clauses] = nil
        end
        if #clauses > 0 then
            lines[#lines + 1] = (anyItem and "/use " or "/cast ") .. table.concat(clauses, "; ")
        end
    end

    local anySeq = false
    Emit("seq", false, function(n, c)
        local line = SeqLine(n, c, warn)
        if line then anySeq = true end
        return line
    end)

    return maxK > 0 or anySeq
end

function ns.Compile(list, showTooltip)
    local lines, warns = {}, {}
    local function warn(msg)
        for _, w in ipairs(warns) do if w == msg then return end end
        warns[#warns + 1] = msg
    end

    local hasCast = false
    for _, node in ipairs(list or {}) do
        if node.kind == "cast" then
            local name = ActionName(node)
            if not name then
                warn("A cast/use block has an empty slot. Drag a spell or item into it.")
            else
                hasCast = true
                local verb = node.what == "item" and "/use " or "/cast "
                lines[#lines + 1] = verb .. Join(Bracket(CastUnit(node), {}), name)
            end
        elseif node.kind == "seq" then
            local line = SeqLine(node, nil, warn)
            if line then
                hasCast = true
                lines[#lines + 1] = line
            end
        elseif node.kind == "stop" then
            lines[#lines + 1] = "/stopcasting"
        elseif node.kind == "attack" then
            lines[#lines + 1] = "/startattack"
        elseif node.kind == "raw" then
            local text = trim(node.text)
            if text == "" then
                warn("A custom line is empty.")
            else
                lines[#lines + 1] = text
                local cmd = text:match("^/(%a+)")
                cmd = cmd and cmd:lower()
                if cmd == "cast" or cmd == "use" or cmd == "castsequence" or cmd == "castrandom" then hasCast = true end
            end
        elseif node.kind == "chat" then
            local text = trim(node.text)
            if text == "" then
                warn("A chat block has no message.")
            else
                lines[#lines + 1] = "/" .. (node.channel or "s") .. " " .. text
            end
        elseif node.kind == "if" then
            if CompileIf(node, lines, warn) then hasCast = true end
        end
    end

    if showTooltip and hasCast then
        table.insert(lines, 1, "#showtooltip")
    end
    return table.concat(lines, "\n"), warns
end

-- Stable text form of a block tree (used for undo/redo).
local function Serialize(v, out)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            out[#out + 1] = tostring(k) .. "="
            Serialize(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = t:sub(1, 1) .. tostring(v)
    end
end
function ns.Serialize(v)
    local out = {}
    Serialize(v, out)
    return table.concat(out)
end
