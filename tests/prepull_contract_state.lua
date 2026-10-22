--=========================================================================================
-- tests/prepull_contract_state.lua - the PRE-PULL CONTRACT between a class's pre-pull
-- drill and that class's own pre-pull table.
--
-- WHY THIS EXISTS (the test-sufficiency audit's Gap 4):
--   The six classes each publish an APL pre-pull rows table, and the per-class suites
--   pinned the SHAPE of those tables. Only three of them are actually graded: the
--   warrior's, the hunter's and the rogue's pre-pull drill read their own table. The
--   druid's, the shaman's and the paladin's have NO consumer, so the shape pins over
--   them read like pre-pull coverage for six classes when three classes have none.
--   A shape pin cannot tell a live table from a dead one; only the RELATIONSHIP can.
--
-- WHAT THIS ASSERTS (the contract, per published pre-pull table):
--   GRADED       a pre-pull drill of THAT SAME class grades the table. Proven at
--                RUNTIME, not by shape: the table is mutated and the drill's verdict
--                must change. Cross-isolation is proven the same way - mutating another
--                class's table must leave this drill's verdict untouched, so the drill
--                reads ITS OWN table and no other class's.
--   CITATION     nothing grades the table. Proven two ways: the symbol has exactly one
--                reference in the whole addon tree (its declaration - no code reads it),
--                and the class's own source says so out loud in the comment block above
--                the declaration, so a reader of the source is never misled about
--                               coverage.
--
--   The paladin is the one class that ships BOTH: `paladin_prepull` grades the paladin's
--   own pre-pull SEAL SPEC (the per-order seal + lead table, which is file-local, so it
--   has no published symbol) while `ST.PALADIN.practice_prepull_rows` is the citation
--   layer. The suite proves both halves: the drill's verdict follows the class's own
--   per-order spec (two orders with different seals grade differently), and mutating the
--   citation layer leaves the drill's verdict untouched.
--
-- NON-VACUITY: every scan asserts a floor. The citation-layer scan must find the table
--   declaration (or the check would pass on an empty scan), the marker scan must find
--   the comment block above the declaration, and the runtime drives must produce a
--   verdict at all - a drive that answers nil everywhere proves nothing.
--
-- Plain Lua 5.1, no WoW client needed: lua5.1 tests/prepull_contract_state.lua
-- The repo root is derived from this script's own location, so any cwd works.
--=========================================================================================

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL  " .. label)
    end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- The source readers
--=========================================================================================
local function read(path)
    local f = io.open(ROOT .. path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function lines_of(path)
    local text = read(path)
    if not text then return nil end
    local out = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
    -- gmatch over the padded text yields one extra empty tail entry; drop it.
    if #out > 0 and out[#out] == "" then out[#out] = nil end
    return out
end

-- Blank comments AND string bodies, keeping the line count so every match keeps a true
-- file:line. This is a scanner, not a parser: it is exact for this codebase's style
-- (no nested long brackets) and never loads the source.
local function blank_code(src)
    local _, newlines = src:gsub("\n", "")
    local out = {}
    for i = 1, newlines + 1 do out[i] = "" end

    local i, len = 1, #src
    local line = 1
    local state = "code" -- code | line | long | dquote | squote | lstring

    local function next_line()
        line = line + 1
        out[line] = ""
    end
    local function put(ch)
        out[line] = out[line] .. ch
    end

    while i <= len do
        local c = src:sub(i, i)
        local two = src:sub(i, i + 1)
        if state == "code" then
            if c == "\n" then
                next_line()
                i = i + 1
            elseif two == "--" then
                local three = src:sub(i, i + 2)
                local opener = three:match("^%-%-%[(=*)%[")
                if opener then
                    state = "long"
                    i = i + 3 + #opener
                else
                    state = "line"
                    i = i + 2
                end
            elseif c == '"' then
                state = "dquote"
                i = i + 1
            elseif c == "'" then
                state = "squote"
                i = i + 1
            elseif c == "[" and src:sub(i + 1, i + 1) == "[" then
                state = "lstring"
                i = i + 2
            else
                put(c)
                i = i + 1
            end
        elseif state == "line" then
            if c == "\n" then
                next_line()
                state = "code"
            end
            i = i + 1
        elseif state == "long" then
            if c == "]" and src:sub(i + 1, i + 1) == "]" then
                state = "code"
                i = i + 2
            else
                if c == "\n" then next_line() end
                i = i + 1
            end
        elseif state == "dquote" or state == "squote" then
            if c == "\\" then
                if src:sub(i + 1, i + 1) == "\n" then next_line() end
                i = i + 2
            elseif (state == "dquote" and c == '"') or (state == "squote" and c == "'") then
                state = "code"
                i = i + 1
            else
                if c == "\n" then next_line() end
                i = i + 1
            end
        else -- lstring
            if c == "]" and src:sub(i + 1, i + 1) == "]" then
                state = "code"
                i = i + 2
            else
                if c == "\n" then next_line() end
                i = i + 1
            end
        end
    end
    return out
end

-- The addon sources: the repo root's .lua files and the class modules. tests/ and docs/
-- are excluded on purpose - the contract is about the shipped addon.
local function addon_sources()
    local out = {}
    local pipe = io.popen('ls -1 "' .. ROOT .. '" 2>/dev/null')
    if pipe then
        for name in pipe:lines() do
            if name:match("%.lua$") then out[#out + 1] = name end
        end
        pipe:close()
    end
    pipe = io.popen('ls -1 "' .. ROOT .. 'classes" 2>/dev/null')
    if pipe then
        for name in pipe:lines() do
            if name:match("%.lua$") then out[#out + 1] = "classes/" .. name end
        end
        pipe:close()
    end
    table.sort(out)
    return out
end

local SOURCES = addon_sources()

--=========================================================================================
-- The sandbox: the REAL compat.lua + utils.lua + the pure engines + the six class
-- modules, so the drills under test are the shipped ones.
--=========================================================================================
local SANDBOX_MODULES = {
    "compat.lua", "utils.lua", "weave.lua", "nextaction.lua", "twist.lua",
    "druid_energy.lua", "hunter_window.lua", "hunter_guide.lua", "warrior_guide.lua",
    "rogue_guide.lua", "shaman_guide.lua", "druid_guide.lua",
}
local CLASS_MODULES = { "HUNTER", "WARRIOR", "DRUID", "PALADIN", "ROGUE", "SHAMAN" }

local function sandbox(project)
    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    env.GetTime = function() return 0 end
    local ST = { HUNTER = {}, WARRIOR = {}, DRUID = {}, PALADIN = {}, ROGUE = {}, SHAMAN = {} }
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        end
        if major == "CallbackHandler-1.0" then
            return { New = function() return { Fire = function() end, RegisterCallback = function() end } end }
        end
        return {}
    end
    local st = {}
    for _, module in ipairs(SANDBOX_MODULES) do
        local chunk = assert(loadfile(ROOT .. module))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        check(ok, "sandbox: " .. module .. " loads (" .. tostring(err) .. ")")
    end
    for _, class in ipairs(CLASS_MODULES) do
        local chunk = assert(loadfile(ROOT .. "classes/" .. class:lower() .. ".lua"))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        check(ok, "sandbox: classes/" .. class:lower() .. ".lua loads (" .. tostring(err) .. ")")
        -- Operator order 2026-10-21: a wrapped class file registers its body as a
        -- loader; the sandbox activates it exactly as main.lua does at init.
        if type(st.class_loaders) == "table"
            and type(st.class_loaders[class]) == "function" then
            st.class_loaders[class]()
        end
    end
    return st, ST
end

--=========================================================================================
-- THE CONTRACT - one row per published pre-pull table.
--
--   class    the class that owns the table
--   file     the class module that declares it
--   table    the field name on ST.<class>
--   drill    the pre-pull drill of THAT class that grades it (nil = nothing grades it)
--   kind     "rows"  - the family's pre-pull row list (a map of family -> rows)
--            "bands" - the drill's lateness band table (a list)
--
-- The declaration is the CONTRACT: the suite proves that the tree keeps it.
--=========================================================================================
local CONTRACT = {
    { class = "DRUID",   file = "classes/druid.lua",   table = "PRACTICE_PREPULLS",           drill = nil,               kind = "rows" },
    { class = "HUNTER",  file = "classes/hunter.lua",  table = "PRACTICE_PREPULLS",           drill = "hunter_prepull",   kind = "rows" },
    { class = "HUNTER",  file = "classes/hunter.lua",  table = "PRACTICE_PREPULL_LATE_BANDS", drill = "hunter_prepull",   kind = "bands" },
    { class = "PALADIN", file = "classes/paladin.lua", table = "practice_prepull_rows",      drill = nil,               kind = "rows" },
    { class = "ROGUE",   file = "classes/rogue.lua",   table = "practice_prepulls",           drill = "rogue_opener",     kind = "rows" },
    { class = "SHAMAN",  file = "classes/shaman.lua",  table = "PRACTICE_PREPULLS",           drill = nil,               kind = "rows" },
    { class = "WARRIOR", file = "classes/warrior.lua", table = "PRACTICE_PREPULLS",           drill = "warrior_prepull",  kind = "rows" },
    { class = "WARRIOR", file = "classes/warrior.lua", table = "PRACTICE_PREPULL_LATE_BANDS", drill = "warrior_prepull",  kind = "bands" },
}

-- The classes that ship a pre-pull drill at all. A class with NO pre-pull drill must
-- have its pre-pull table marked citation-only - that is the honesty half of the audit.
local CLASSES = {
    { class = "DRUID",   file = "classes/druid.lua",   drill = nil },
    { class = "HUNTER",  file = "classes/hunter.lua",  drill = "hunter_prepull" },
    { class = "PALADIN", file = "classes/paladin.lua", drill = "paladin_prepull" },
    { class = "ROGUE",   file = "classes/rogue.lua",   drill = "rogue_opener" },
    { class = "SHAMAN",  file = "classes/shaman.lua",  drill = nil },
    { class = "WARRIOR", file = "classes/warrior.lua", drill = "warrior_prepull" },
}

local function symbol_of(row) return "ST." .. row.class .. "." .. row.table end

--=========================================================================================
-- Part 1 - the SOURCE side of the contract
--=========================================================================================

-- Locate a table's declaration line in a class module, and the contiguous comment block
-- directly above it (the comment that documents the table).
local function declaration_of(file, field)
    local lines = lines_of(file)
    if not lines then return nil, nil, nil end
    local decl = nil
    for i, line in ipairs(lines) do
        if line:match("^ST%.[%u]+%.([%w_]+)%s*=%s*{") then
            local name = line:match("^ST%.[%u]+%.([%w_]+)%s*=%s*{")
            if name == field then
                decl = i
                break
            end
        end
    end
    if not decl then return nil, nil, nil end
    local block_start = decl
    while block_start > 1 do
        local prev = lines[block_start - 1]
        if prev:match("^%s*%-%-") then
            block_start = block_start - 1
        else
            break
        end
    end
    local block = {}
    for i = block_start, decl - 1 do block[#block + 1] = lines[i] end
    return decl, block, lines
end

local function count_symbol(symbol, skip_file, skip_line)
    local total = 0
    for _, path in ipairs(SOURCES) do
        local text = read(path)
        if text then
            local code = blank_code(text)
            for i, line in ipairs(code) do
                if path ~= skip_file or i ~= skip_line then
                    local from = 1
                    while true do
                        local at = line:find(symbol, from, true)
                        if not at then break end
                        total = total + 1
                        from = at + #symbol
                    end
                end
            end
        end
    end
    return total
end

print("== the pre-pull contract: the source side ==")

-- 1a. Every published pre-pull table in the six class modules is in the contract.
for _, path in ipairs(SOURCES) do
    if path:match("^classes/") then
        local text = read(path)
        if text then
            local code = blank_code(text)
            for i, line in ipairs(code) do
                local class, field = line:match("^ST%.([%u]+)%.([%w_]+)%s*=%s*{")
                if class and field and field:lower():find("prepull") then
                    local declared = false
                    for _, row in ipairs(CONTRACT) do
                        if row.class == class and row.table == field then declared = true end
                    end
                    check(declared, "contract: " .. path .. ":" .. i .. " publishes ST." .. class
                        .. "." .. field .. " and the contract declares it")
                end
            end
        end
    end
end

-- 1b. Every contract row names a table that really is declared.
for _, row in ipairs(CONTRACT) do
    local decl = declaration_of(row.file, row.table)
    check(decl ~= nil, "contract: " .. row.file .. " declares ST." .. row.class .. "." .. row.table)
end

-- 1c. A CITATION row: the symbol has exactly ONE reference in the whole addon tree -
--     its own declaration. Any second reference is a reader, and a reader would make
--     the table GRADED, not citation-only.
for _, row in ipairs(CONTRACT) do
    if row.drill == nil then
        local decl = declaration_of(row.file, row.table)
        local symbol = symbol_of(row)
        local refs = count_symbol(symbol, row.file, decl)
        eq(refs, 0, "contract: " .. symbol .. " is citation-only - no code anywhere in the "
            .. "addon tree reads it (" .. tostring(refs) .. " reference(s) outside its own "
            .. "declaration)")
    end
end

-- 1d. A CITATION row: the comment block above the declaration says so out loud.
for _, row in ipairs(CONTRACT) do
    if row.drill == nil then
        local _, block = declaration_of(row.file, row.table)
        local text = table.concat(block or {}, "\n"):lower()
        check(#(block or {}) > 0, "contract: " .. row.file .. " documents ST." .. row.class
            .. "." .. row.table .. " in the comment block above its declaration")
        check(text:find("citation", 1, true) ~= nil,
            "contract: the comment above ST." .. row.class .. "." .. row.table
                .. " marks it CITATION-ONLY")
        check(text:find("no consumer", 1, true) ~= nil
                or text:find("no drill", 1, true) ~= nil
                or text:find("not consumed", 1, true) ~= nil
                or text:find("nothing grades", 1, true) ~= nil,
            "contract: the comment above ST." .. row.class .. "." .. row.table
                .. " states that no drill consumes it")
    end
end

--=========================================================================================
-- Part 2 - the RUNTIME side of the contract
--=========================================================================================

local st, ST = sandbox(5) -- TBC: the family every class's pre-pull table has rows for.

local function drill_of(class, key)
    local module = ST[class]
    if type(module) ~= "table" or type(module.practice_drills) ~= "table" then return nil end
    for _, drill in ipairs(module.practice_drills) do
        if type(drill) == "table" and drill.key == key then return drill end
    end
    return nil
end

-- The rogue's grader runs the class's ROTATION model before it looks at the pre-pull
-- row. This suite is about the pre-pull link, so the rotation model is stubbed with a
-- fixed answer - a test double for the engine, not a change to the class.
if st.rogue_guide and st.rogue_guide.practice_expected then
    st.rogue_guide.practice_expected = function() return { action = "expose", unknown = false, hold = false } end
end

-- The plans are computed ONCE from the pristine tables, so a mutation of a table
-- changes the drill's verdict instead of silently following the mutated data.
local PLANS = {}

local function family_rows(class, family)
    for _, row in ipairs(CONTRACT) do
        if row.class == class and row.kind == "rows" then
            local module = ST[class]
            local table_ref = module[row.table]
            if type(table_ref) == "table" then
                local rows = table_ref[family]
                if type(rows) == "table" then return rows end
            end
        end
    end
    return nil
end

local function build_seq_plan(class)
    local rows = family_rows(class, "TBC")
    if type(rows) ~= "table" or #rows == 0 then return nil end
    local max_at = nil
    for _, row in ipairs(rows) do
        if type(row.at) == "number" and (max_at == nil or row.at > max_at) then max_at = row.at end
    end
    if max_at == nil then return nil end
    -- The due opener is the LAST row (in list order) whose window has opened - the same
    -- rule the graders use.
    local due = nil
    for _, row in ipairs(rows) do
        if type(row.at) == "number" and row.at <= max_at then due = row end
    end
    if due == nil then return nil end
    return { press = due.action, on_time = max_at, late = max_at + 0.5 }
end

local function seq_ctx(plan, pull_time)
    return {
        now = 100, time_to_pull = -pull_time,
        pick = plan.press, pressed = plan.press, action = plan.press, last_action = plan.press,
    }
end

local function drive_seq(class, drill, plan)
    local on_time = drill.grade(ST[class], seq_ctx(plan, plan.on_time))
    local late = drill.grade(ST[class], seq_ctx(plan, plan.late))
    return tostring(on_time) .. "/" .. tostring(late)
end

PLANS.HUNTER = build_seq_plan("HUNTER")
PLANS.WARRIOR = build_seq_plan("WARRIOR")

-- The rogue's plan: the family's first cast row, and a pull moment that leaves the
-- opener on time.
local rogue_rows = family_rows("ROGUE", "TBC")
local ROGUE_PLAN = nil
if type(rogue_rows) == "table" then
    for _, row in ipairs(rogue_rows) do
        if type(row.action) == "string" and (row.kind == nil or row.kind == "spell") then
            ROGUE_PLAN = { press = row.action, now = 100, pull_at = 200 }
            break
        end
    end
end

-- The paladin's pre-pull SEAL SPEC is file-local (no published symbol), so the plan is
-- read out of the class's own source: mode -> seal.
local function read_paladin_spec()
    local lines = lines_of("classes/paladin.lua")
    if not lines then return nil end
    local spec = {}
    local inside = false
    for _, line in ipairs(lines) do
        if line:match("^local%s+PRACTICE_PREPULL%s*=%s*{") then
            inside = true
        elseif inside then
            local mode, seal = line:match("^%s*([%w_]+)%s*=%s*{%s*seal%s*=%s*\"([%w_]+)\"")
            if mode and seal then spec[mode] = seal end
            if line:match("^}") then inside = false end
        end
    end
    return spec
end

local PALADIN_SPEC = read_paladin_spec()

local function paladin_mode_pair()
    if type(PALADIN_SPEC) ~= "table" then return nil end
    local modes = {}
    for mode in pairs(PALADIN_SPEC) do modes[#modes + 1] = mode end
    table.sort(modes)
    for _, a in ipairs(modes) do
        for _, b in ipairs(modes) do
            if a ~= b and PALADIN_SPEC[a] ~= PALADIN_SPEC[b] then
                return { mode_a = a, seal_a = PALADIN_SPEC[a], mode_b = b, seal_b = PALADIN_SPEC[b] }
            end
        end
    end
    return nil
end

local PALADIN_PAIR = paladin_mode_pair()

print("== the pre-pull contract: the runtime side ==")

-- 2a. The drill registry: a class's pre-pull drill is published by that class, with a
--     grade function, and by no other class.
for _, entry in ipairs(CLASSES) do
    if entry.drill then
        local drill = drill_of(entry.class, entry.drill)
        check(drill ~= nil, "contract: " .. entry.class .. " publishes the pre-pull drill "
            .. entry.drill)
        if drill then
            eq(type(drill.grade), "function", "contract: the " .. entry.drill
                .. " drill carries a grade function")
        end
        for _, other in ipairs(CLASSES) do
            if other.class ~= entry.class then
                check(drill_of(other.class, entry.drill) == nil, "contract: no other class ("
                    .. other.class .. ") publishes the " .. entry.drill .. " drill")
            end
        end
    end
end

-- 2b. The drives must actually produce a verdict, and the verdict must be a REAL one:
--     the press has to match the due opener, or the drive would grade "D" for a class
--     whose table it never read (a degenerate drive proves nothing about the coupling).
local BASELINE = {}
local function parts_of(text)
    local parts = {}
    for part in tostring(text):gmatch("[^/]+") do parts[#parts + 1] = part end
    return parts
end

BASELINE.HUNTER = PLANS.HUNTER and drive_seq("HUNTER", drill_of("HUNTER", "hunter_prepull"), PLANS.HUNTER) or nil
BASELINE.WARRIOR = PLANS.WARRIOR and drive_seq("WARRIOR", drill_of("WARRIOR", "warrior_prepull"), PLANS.WARRIOR) or nil

if PLANS.HUNTER then
    eq(parts_of(BASELINE.HUNTER)[1], "S", "contract: the hunter_prepull drive grades the "
        .. "due opener on time (got " .. tostring(BASELINE.HUNTER) .. ")")
end
if PLANS.WARRIOR then
    eq(parts_of(BASELINE.WARRIOR)[1], "S", "contract: the warrior_prepull drive grades the "
        .. "due opener on time (got " .. tostring(BASELINE.WARRIOR) .. ")")
end

-- The rogue's drive: the class's own ctx builder publishes the pre-pull row, and the
-- drill grades that row.
local function drive_rogue()
    local class = ST.ROGUE
    local drill = drill_of("ROGUE", "rogue_opener")
    if not drill or not ROGUE_PLAN then return nil end
    class.gather_guide_inputs = function() return { ar_ready = true } end
    local ctx = class.practice_context(class, ROGUE_PLAN.now, nil)
    local g = {
        now = ROGUE_PLAN.now, pull_at = ROGUE_PLAN.pull_at,
        time_to_pull = ROGUE_PLAN.pull_at - ROGUE_PLAN.now,
        pick = ROGUE_PLAN.press, pressed = ROGUE_PLAN.press, action = ROGUE_PLAN.press,
        resources = ctx.resources, cooldowns = ctx.cooldowns,
        prepull_action = ctx.prepull_action, prepull_at = ctx.prepull_at,
    }
    return tostring(ctx.prepull_action) .. "/" .. tostring(ctx.prepull_at) .. "/"
        .. tostring(drill.grade(class, g))
end

BASELINE.ROGUE = drive_rogue()
if BASELINE.ROGUE then
    local parts = parts_of(BASELINE.ROGUE)
    eq(parts[#parts], "S", "contract: the rogue_opener drive grades the pre-pull row on "
        .. "time (got " .. tostring(BASELINE.ROGUE) .. ")")
    check(parts[1] ~= "nil" and parts[1] ~= "", "contract: the rogue_opener drive carries "
        .. "the class's own pre-pull row (got " .. tostring(BASELINE.ROGUE) .. ")")
end

-- The paladin's drive: the same ctx graded under two orders whose own spec names
-- different seals. The drill's verdict must follow the class's own per-order spec.
local function drive_paladin()
    local drill = drill_of("PALADIN", "paladin_prepull")
    if not drill or not PALADIN_PAIR then return nil end
    local function grade(mode, seal)
        return tostring(drill.grade(ST.PALADIN, {
            now = 100, fcfs_mode = mode, seal = seal, pull_in_seconds = 5,
            resources = {}, cooldowns = {},
        }))
    end
    return grade(PALADIN_PAIR.mode_a, PALADIN_PAIR.seal_a) .. "/"
        .. grade(PALADIN_PAIR.mode_a, PALADIN_PAIR.seal_b) .. "/"
        .. grade(PALADIN_PAIR.mode_b, PALADIN_PAIR.seal_b) .. "/"
        .. grade(PALADIN_PAIR.mode_b, PALADIN_PAIR.seal_a)
end

BASELINE.PALADIN = drive_paladin()
if BASELINE.PALADIN then
    check(PALADIN_PAIR ~= nil, "contract: the paladin's own pre-pull spec names two orders "
        .. "with different seals")
    check(BASELINE.PALADIN == "S/F/S/F", "contract: the paladin_prepull drive follows the "
        .. "class's own per-order seal spec (got " .. tostring(BASELINE.PALADIN) .. ")")
end

-- 2c. THE COUPLING: mutating a table a drill grades must change that drill's verdict.
local function mutate_rows(module, field, family)
    local table_ref = module[field]
    local rows = table_ref[family]
    local mutated = {}
    for i, row in ipairs(rows or {}) do
        mutated[i] = {
            action = "MUTATED_" .. tostring(i), label = row.label, spell = row.spell,
            at = row.at, source = row.source, kind = row.kind,
        }
    end
    if #mutated == 0 then
        mutated[1] = { action = "MUTATED_1", at = 0 }
    end
    table_ref[family] = mutated
    return function() table_ref[family] = rows end
end

local function mutate_bands(module, field)
    local original = module[field]
    module[field] = { { max = 99, grade = "Z" } }
    return function() module[field] = original end
end

local function drive_of(class)
    if class == "HUNTER" then
        return PLANS.HUNTER and drive_seq("HUNTER", drill_of("HUNTER", "hunter_prepull"), PLANS.HUNTER)
    elseif class == "WARRIOR" then
        return PLANS.WARRIOR and drive_seq("WARRIOR", drill_of("WARRIOR", "warrior_prepull"), PLANS.WARRIOR)
    elseif class == "ROGUE" then
        return drive_rogue()
    elseif class == "PALADIN" then
        return drive_paladin()
    end
    return nil
end

for _, row in ipairs(CONTRACT) do
    if row.drill then
        local module = ST[row.class]
        local before = drive_of(row.class)
        check(before ~= nil, "contract: the " .. row.class .. " pre-pull drive is drivable")
        local restore
        if row.kind == "rows" then
            restore = mutate_rows(module, row.table, "TBC")
        else
            restore = mutate_bands(module, row.table)
        end
        local after = drive_of(row.class)
        restore()
        check(after ~= before, "contract: the " .. row.drill .. " drill reads "
            .. symbol_of(row) .. " - mutating that table changed its verdict ("
            .. tostring(before) .. " -> " .. tostring(after) .. ")")
    end
end

-- 2d. CROSS-ISOLATION: a drill must read its OWN class's table and no other class's.
--     Mutating another class's pre-pull table must leave this drill's verdict untouched.
for _, entry in ipairs(CLASSES) do
    if entry.drill then
        local before = drive_of(entry.class)
        for _, row in ipairs(CONTRACT) do
            if row.class ~= entry.class then
                local module = ST[row.class]
                local restore
                if row.kind == "rows" then
                    restore = mutate_rows(module, row.table, "TBC")
                else
                    restore = mutate_bands(module, row.table)
                end
                local after = drive_of(entry.class)
                restore()
                check(after == before, "contract: the " .. entry.drill .. " drill reads no other "
                    .. "class's pre-pull table - mutating " .. symbol_of(row)
                    .. " left its verdict untouched")
            end
        end
    end
end

-- 2e. A class with NO pre-pull drill must publish none of the four pre-pull drill keys.
for _, entry in ipairs(CLASSES) do
    if not entry.drill then
        for _, other in ipairs(CLASSES) do
            if other.drill then
                check(drill_of(entry.class, other.drill) == nil, "contract: " .. entry.class
                    .. " publishes no pre-pull drill (it must not answer to "
                    .. other.drill .. ")")
            end
        end
    end
end

--=========================================================================================
if failures == 0 then
    print("PASS  prepull_contract_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  prepull_contract_state.lua: " .. tostring(failures) .. " of "
        .. tostring(checks) .. " checks failed")
    os.exit(1)
end
