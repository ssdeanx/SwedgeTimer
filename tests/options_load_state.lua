-- tests/options_load_state.lua: offline load + structure checks for the real options
-- tables (config_presets.lua -> config.lua -> option_table_presets.lua -> option_tables.lua)
-- under AceAddon / LibSharedMedia / LibWindow / AceConfig stubs.
--
-- Why this exists: the option tables are built dynamically per class by ST:set_opts()
-- at addon init. Nothing offline has ever LOADED or BUILT them, so a malformed widget
-- (a range without min/max/step, a select without values, an execute without func, an
-- order that is not a number, a group table aliased under two keys) ships silently and
-- surfaces only as an in-game AceConfig error. This suite loads the real modules for
-- every player class (all 9 hand sets, including the 5 classes with class-specific
-- panels), runs the real set_opts() generator, registers the produced table through an
-- AceConfig stub exactly like main.lua does, and walks the whole tree.
--
-- A REAL defect found while building this suite is pinned in section 3: the shipped
-- player_class / class_hands casing mismatch makes the true OnInitialize order
-- (main.lua:281 -> main.lua:303) fail before any option tree exists on a live client.
-- The walk therefore normalises ST.class_hands to the uppercase keys main.lua:81 uses
-- (so the full tree, class panels included, can be walked at all), and section 3 runs
-- the untampered order as an ACCEPTED known defect: it prints the evidence every run,
-- and the run FAILS if the defect stops reproducing so the acceptance gets removed.
--
-- Ground rules for the walk:
--   * Every entry in a group's args must be a table with a known `type`.
--   * toggle / input / color / range / select: `get` and `set` present (function, handler
--     method name, or false - the AceConfig contract).
--   * range: min, max and step are numbers (min <= max), plus get/set.
--   * select: `values` (table or function), plus get/set.
--   * execute: `func` is a function.
--   * header / description: `name` is a string or function.
--   * group: `args` is a table; groups are walked recursively.
--   * every `order` that is present is a number (groups and widgets alike).
--   * duplicate keys within one args table cannot survive Lua table construction, so the
--     walkable form of "no duplicate widget keys" is the one aliasing can still produce:
--     the SAME widget table under two keys of one group, or the same group/args table
--     reachable at two paths in the tree. Both fail the check. The per-group key count
--     is reported so a silently collapsed constructor is still visible in the numbers.
--
-- Not loaded here: main.lua (AceDB/AceConfigDialog/profile registration is its own
-- path, pinned by tests/main_init_state.lua); the widget get/set closures are inspected,
-- not executed - their behaviour is the job of the per-module state tests.
-- Run from the repo root: lua5.1 tests/options_load_state.lua  (any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL  " .. label) end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end
-- main.lua's class_hands (uppercase class tokens), mirrored here because main.lua itself is
-- NOT loaded in this sandbox (see the header). main.lua defines it at file scope before
-- option_tables.lua loads in every TOC; load_modules seeds it for the same reason, so a
-- re-added lowercase redefinition in option_tables.lua would clobber it and fail the
-- load-time checks below. The source check at the walk pins this mirror against main.lua.
local MAIN_CLASS_HANDS = {
    DEATHKNIGHT = {"mainhand", "offhand"},
    DRUID = {"mainhand"},
    HUNTER = {"mainhand", "offhand", "ranged"},
    MAGE = {"mainhand", "ranged"},
    PALADIN = {"mainhand"},
    PRIEST = {"mainhand", "ranged"},
    ROGUE = {"mainhand", "offhand", "ranged"},
    SHAMAN = {"mainhand", "offhand"},
    WARLOCK = {"mainhand", "ranged"},
    WARRIOR = {"mainhand", "offhand", "ranged"},
}

-- Non-vacuity floors drawn from the tree this was added against: 9 classes x
-- 73..313 widgets = 1857 widgets / 249 groups / 3149 orders across all classes.
local WIDGET_FLOOR = 800
local GROUP_FLOOR = 100
local ORDER_FLOOR = 1000
local PER_TYPE_FLOOR = {
    toggle = 40, range = 15, select = 10, input = 1, execute = 1, color = 5,
}

local CLASSES = {
    "Paladin", "Warrior", "Hunter", "Shaman", "Druid",
    "Mage", "Warlock", "Priest", "Rogue",
}
local CLASS_TABLES = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}
local KNOWN_TYPES = {
    group = true, header = true, description = true,
    toggle = true, range = true, select = true, input = true, execute = true, color = true,
}
local MODULES = {
    "utils.lua", "config_presets.lua", "config.lua", "rogue_guide.lua",
    -- The practice progression lane (the Progress options page reads them):
    -- practice_stats.lua loads first, practice_progress.lua composes the saved profile
    -- from both halves, practice_progress_ui.lua is the page's read model. They are
    -- pure modules - no WoW API, no frames at load.
    "practice_stats.lua", "practice_progress.lua", "practice_progress_ui.lua",
    "option_table_presets.lua", "option_tables.lua",
}

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- Load the real modules into a fresh namespace. Returns ST, st, env, sb - or nil + error.
-- This stops right before set_opts() so the runtime-casing probe can run the REAL
-- initialization order without the test-side normalisation the walk needs.
local function load_modules(class_pretty)
    local sb = { hash_calls = {}, registered = {} }

    -- The addon object: the class tables main.lua seeds, the db accessors the generators
    -- close over, and the hand iteration (copied from main.lua - the generators consume
    -- it at build time).
    local ST = {}
    for _, name in ipairs(CLASS_TABLES) do ST[name] = {} end
    sb.profile, sb.class_db, sb.hand_dbs = {}, {}, {}
    -- Copied from main.lua (get_class_hands + iter_hands): the generators consume these at
    -- build time, so the fixture must match the shipped implementation.
    function ST:get_class_hands()
        local hands = self.class_hands[self.player_class]
        if hands == nil and type(self.player_class) == "string" then
            hands = self.class_hands[string.upper(self.player_class)]
        end
        return hands or {}
    end
    function ST:iter_hands()
        local hands = self:get_class_hands()
        local i, n = 0, #hands
        return function()
            i = i + 1
            if i <= n then return hands[i] end
        end
    end
    -- main.lua seeds class_hands at file scope before option_tables.lua loads (every TOC):
    -- seed the mirror here so a reintroduced clobber is visible to the checks below.
    ST.class_hands = MAIN_CLASS_HANDS
    function ST:generic_iter(array)
        local i, n = 0, #array
        return function()
            i = i + 1
            if i <= n then return array[i] end
        end
    end
    function ST:get_profile_table() return sb.profile end
    function ST:get_class_table() return sb.class_db end
    function ST:get_hand_table(hand)
        sb.hand_dbs[hand] = sb.hand_dbs[hand] or {}
        return sb.hand_dbs[hand]
    end
    function ST:convert_color(t, alpha) return t[1] / 255, t[2] / 255, t[3] / 255, alpha or t[4] end
    function ST:convert_color_up(t) return { t[1] * 255, t[2] * 255, t[3] * 255, t[4] } end
    sb.ST = ST

    local LSM = {
        Fetch = function(_, mediatype, key) return key end,
        HashTable = function(_, mediatype)
            sb.hash_calls[#sb.hash_calls + 1] = mediatype
            return { ["fake-" .. mediatype] = "Fake " .. mediatype }
        end,
        Register = function() end,
    }
    local LWIN = { SavePosition = function() end, RestorePosition = function() end }
    local AC = {
        RegisterOptionsTable = function(_, name, table)
            sb.registered[#sb.registered + 1] = { name = name, table = table }
        end,
    }
    local ACR = { NotifyChange = function() end, RegisterOptionsTable = function() end }
    local DB = { New = function() return { profile = sb.profile } end }

    local env = setmetatable({}, { __index = _G })
    env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    -- UnitClass's second return is the uppercase class FILENAME ("PALADIN"): Blizzard's
    -- own classic source compares exactly that value to quoted class filenames
    -- (wow-ui-source Interface/AddOns/Blizzard_FrameXMLUtil/Classic/AuraUtil.lua:3-4),
    -- and this repo's utils.lua:52-57 / main.lua:226 assume it too.
    env.UnitClass = function() return class_pretty, string.upper(class_pretty) end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then return { GetAddon = function() return ST end } end
        if major == "LibSharedMedia-3.0" then return LSM end
        if major == "LibWindow-1.1" then return LWIN end
        if major == "AceConfig-3.0" then return AC end
        if major == "AceConfigRegistry-3.0" then return ACR end
        if major == "AceDB-3.0" then return DB end
        return {}
    end

    local st = {}
    for _, path in ipairs(MODULES) do
        local chunk = assert(loadfile(ROOT .. path))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        if not ok then
            return nil, path .. " does not load: " .. tostring(err)
        end
    end
    sb.st, sb.env = st, env
    return ST, st, env, sb
end

-- Build the full option tree the way the addon INTENDS to at OnInitialize:
--   * main.lua:281 already ran (player_class = UnitClass's class filename, uppercase);
--   * ST.class_hands is normalised to main.lua:81's uppercase keys.
-- The second step papers over the live casing defect recorded in section 3 (the shipped
-- option_tables.lua:83-93 table is lowercase-keyed, so the untampered runtime order
-- crashes before any tree exists) - without it there is nothing to walk at all.
local function build(class_pretty)
    local ST, st, env, sb = load_modules(class_pretty)
    if not ST then return nil, st end

    -- main.lua:281, verbatim: player_class_pretty, player_class = UnitClass("player").
    ST.player_class_pretty, ST.player_class = env.UnitClass("player")
    -- class_hands is main.lua's table, seeded by load_modules in the real file order;
    -- nothing to normalise any more - the casing defect that required this is fixed.

    local ok, err = pcall(ST.set_opts, ST)
    if not ok then
        return nil, "set_opts() fails: " .. tostring(err)
    end

    -- main.lua's registration step, over the stub: proves the produced table is the
    -- registrable object.
    local AC = env.LibStub("AceConfig-3.0")
    AC:RegisterOptionsTable("SwedgeTimer_Options", ST.opts_table)
    sb.ST, sb.st, sb.env = ST, st, env
    return sb
end

--=========================================================================================
-- Tree walker: malformed widgets, orders, aliasing
--=========================================================================================
local function is_handler(v)
    return type(v) == "function" or type(v) == "string" or v == false
end

local function walk(root)
    local stats = { widgets = 0, groups = 0, orders = 0, keys = 0, per_type = {} }
    local violations = {}
    local seen = {}   -- table -> path, for aliasing (a duplicate key's surviving form)
    local function bad(path, msg)
        violations[#violations + 1] = path .. ": " .. msg
    end

    local function visit_group(t, path)
        stats.groups = stats.groups + 1
        if type(t.args) ~= "table" then
            bad(path, "group without an args table")
            return
        end
        if t.name ~= nil and type(t.name) ~= "string" and type(t.name) ~= "function" then
            bad(path, "group name is neither a string nor a function")
        end
        if t.order ~= nil then
            stats.orders = stats.orders + 1
            if type(t.order) ~= "number" then
                bad(path, "group order is not a number: " .. tostring(t.order))
            end
        end
        local by_widget = {}
        for key, v in pairs(t.args) do
            local wpath = path .. ".args." .. key
            stats.keys = stats.keys + 1
            if type(v) ~= "table" then
                bad(wpath, "widget is not a table (" .. type(v) .. ")")
            else
                if v.order ~= nil then
                    stats.orders = stats.orders + 1
                    if type(v.order) ~= "number" then
                        bad(wpath, "order is not a number: " .. tostring(v.order))
                    end
                end
                if type(v.type) ~= "string" then
                    bad(wpath, "widget has no string type")
                elseif not KNOWN_TYPES[v.type] then
                    bad(wpath, "unknown widget type '" .. tostring(v.type) .. "'")
                else
                    stats.per_type[v.type] = (stats.per_type[v.type] or 0) + 1
                    local wtype = v.type
                    if wtype == "toggle" or wtype == "input" or wtype == "color" then
                        if not is_handler(v.get) then bad(wpath, wtype .. " has no usable get") end
                        if not is_handler(v.set) then bad(wpath, wtype .. " has no usable set") end
                    elseif wtype == "range" then
                        if not is_handler(v.get) then bad(wpath, "range has no usable get") end
                        if not is_handler(v.set) then bad(wpath, "range has no usable set") end
                        if type(v.min) ~= "number" then
                            bad(wpath, "range min is not a number: " .. tostring(v.min))
                        end
                        if type(v.max) ~= "number" then
                            bad(wpath, "range max is not a number: " .. tostring(v.max))
                        end
                        if type(v.step) ~= "number" then
                            bad(wpath, "range step is not a number: " .. tostring(v.step))
                        end
                        if type(v.min) == "number" and type(v.max) == "number" and v.min > v.max then
                            bad(wpath, "range min > max")
                        end
                    elseif wtype == "select" then
                        if not is_handler(v.get) then bad(wpath, "select has no usable get") end
                        if not is_handler(v.set) then bad(wpath, "select has no usable set") end
                        if type(v.values) ~= "table" and type(v.values) ~= "function" then
                            bad(wpath, "select has no values table/function")
                        end
                        -- sorting protocol (AceConfigDialog FeedGroup, TBC options
                        -- crash 2026-10-21): sorting is a literal key array or a
                        -- function CALLED WITH the info table that returns the key
                        -- array - never a two-arg comparator. A comparator receives
                        -- (info, nil) and throws "compare table with nil" when the
                        -- options open. Simulate the FeedGroup loop: resolve the
                        -- array, then require every listed key to exist in values
                        -- and every values key to be listed.
                        if v.sorting ~= nil then
                            local order
                            if type(v.sorting) == "function" then
                                local ok, res = pcall(v.sorting, { options = {}, appName = "test" })
                                if not ok then
                                    bad(wpath, "select sorting throws when called with info: " .. tostring(res))
                                else
                                    order = res
                                end
                            elseif type(v.sorting) == "table" then
                                order = v.sorting
                            else
                                bad(wpath, "select sorting is neither array nor function")
                            end
                            if order ~= nil then
                                if type(order) ~= "table" then
                                    bad(wpath, "select sorting did not resolve to a key array")
                                elseif type(v.values) == "table" then
                                    local listed = {}
                                    for _, skey in ipairs(order) do
                                        if v.values[skey] == nil then
                                            bad(wpath, "select sorting lists unknown key " .. tostring(skey))
                                        end
                                        listed[skey] = true
                                    end
                                    for skey in pairs(v.values) do
                                        if not listed[skey] then
                                            bad(wpath, "select sorting omits values key " .. tostring(skey))
                                        end
                                    end
                                end
                            end
                        end
                    elseif wtype == "execute" then
                        if type(v.func) ~= "function" then bad(wpath, "execute has no func") end
                    elseif wtype == "header" or wtype == "description" then
                        if type(v.name) ~= "string" and type(v.name) ~= "function" then
                            bad(wpath, "missing name")
                        end
                    end
                    if wtype ~= "group" and wtype ~= "header" and wtype ~= "description" then
                        stats.widgets = stats.widgets + 1
                    end
                    if by_widget[v] then
                        bad(wpath, "aliases the same widget as args." .. by_widget[v])
                    end
                    by_widget[v] = key
                end
                if v.type == "group" then
                    if seen[v] then
                        bad(wpath, "reuses the group table already at " .. seen[v])
                    else
                        seen[v] = wpath
                        visit_group(v, wpath)
                    end
                end
            end
        end
    end

    seen[root] = "opts_table"
    visit_group(root, "opts_table")
    return stats, violations
end

--=========================================================================================
-- 1) Load surface (one class) + aggregate walk over every class
--=========================================================================================
local base, base_err = build("Paladin")
if not base then
    print("FAIL  options sandbox: " .. tostring(base_err))
    os.exit(1)
end
check(type(base.st.utils) == "table", "utils.lua loaded (st.utils)")
check(type(base.ST.opts_table) == "table", "ST.opts_table exists")
check(type(base.ST.opts_table.args) == "table" and next(base.ST.opts_table.args) ~= nil,
    "set_opts() fills opts_table.args")
check(base.ST.player_class == "PALADIN",
    "player_class follows main.lua:281 at build time (UnitClass's uppercase class filename)")

-- option_tables.lua must NOT redefine class_hands: it used to clobber main.lua's uppercase
-- table with lowercase keys, crashing ST:iter_hands() during OnInitialize at login. The
-- uppercase table must survive the load and the lookup accessor must be case-tolerant.
local load_ST = load_modules("Paladin")
check(load_ST ~= nil, "a second, unmodified load for the load-time casing")
check(load_ST.class_hands["PALADIN"] ~= nil,
    "class_hands keeps main.lua's uppercase PALADIN key after option_tables.lua loads")
check(load_ST.class_hands["paladin"] == nil,
    "option_tables.lua does not reintroduce a lowercase class_hands table")
check(type(load_ST.get_class_hands) == "function"
        and type(load_ST:get_class_hands()) == "table" and #load_ST:get_class_hands() >= 1,
    "get_class_hands tolerates the load-time lowercase player_class")

-- The class_activation select's sort order (TBC options crash 2026-10-21):
-- Auto lists first, then the six classes alphabetically.
do
    local ca = base.ST.opts_table.args.class_activation
    check(type(ca) == "table" and ca.type == "select",
        "class_activation select exists at top level")
    check(type(ca.sorting) == "table" and ca.sorting[1] == "Auto"
            and ca.sorting[2] == "DRUID" and #ca.sorting == 7,
        "class_activation sorting is the literal Auto-first array")
end

-- The mirror must match main.lua's real table (whitespace-insensitive, plain find).
do
    local f = io.open(ROOT .. "main.lua")
    local src = (f and f:read("*a") or ""):gsub("\r\n", "\n")
    if f then f:close() end
    local block = src:match("ST%.class_hands%s*=%s*{(.-)\n}") or ""
    local norm = block:gsub("%s+", "")
    local mismatches = 0
    for class, hands in pairs(MAIN_CLASS_HANDS) do
        local quoted = {}
        for i, hand in ipairs(hands) do quoted[i] = '"' .. hand .. '"' end
        local want = class .. "={" .. table.concat(quoted, ",") .. "}"
        if not norm:find(want, 1, true) then mismatches = mismatches + 1 end
    end
    check(norm ~= "", "main.lua defines ST.class_hands")
    check(mismatches == 0, "the mirrored class_hands table matches main.lua (mismatches: "
        .. mismatches .. ")")
    check(norm:find("paladin={", 1, true) == nil, "main.lua keys class_hands by uppercase token only")
end
check(#base.hash_calls > 0, "the LSM HashTable seam is exercised at build time")
for _, media in ipairs({ "statusbar", "border", "font" }) do
    local seen = false
    for _, kind in ipairs(base.hash_calls) do
        if kind == media then seen = true break end
    end
    check(seen, "LSM:HashTable('" .. media .. "') is requested")
end
check(#base.registered == 1, "the produced table registers through AceConfig")
check(base.registered[1].name == "SwedgeTimer_Options",
    "the registration uses the addon's options key")
check(base.registered[1].table == base.ST.opts_table,
    "the registration carries the produced table")
check(base.ST.opts_table.args.design_mode ~= nil, "the Design Mode panel is generated")
check(base.ST.opts_table.args.positions ~= nil, "the position panel is generated")
check(base.ST.opts_table.args.class ~= nil, "the class panel is generated")

local totals = { widgets = 0, groups = 0, orders = 0, keys = 0, per_type = {} }
local class_widgets = {}
for _, class in ipairs(CLASSES) do
    local sb, err = build(class)
    if not sb then
        failures = failures + 1
        print("FAIL  " .. class .. ": " .. tostring(err))
    else
        local stats, violations = walk(sb.ST.opts_table)
        class_widgets[#class_widgets + 1] = stats.widgets
        check(stats.widgets > 0, class .. ": set_opts() produces widgets")
        totals.widgets = totals.widgets + stats.widgets
        totals.groups = totals.groups + stats.groups
        totals.orders = totals.orders + stats.orders
        totals.keys = totals.keys + stats.keys
        for t, n in pairs(stats.per_type) do
            totals.per_type[t] = (totals.per_type[t] or 0) + n
        end
        for _, v in ipairs(violations) do
            failures = failures + 1
            print("FAIL  " .. class .. " " .. v)
        end
        -- Every class's tree contains at least the info/positions/behaviour groups.
        check(stats.groups >= 5, class .. ": the walk visits the group tree (" .. stats.groups .. ")")
    end
end

print(string.format(
    "ok   options tree: %d class(es), %d widget(s), %d group(s), %d args key(s), %d order(s)",
    #class_widgets, totals.widgets, totals.groups, totals.keys, totals.orders))

--=========================================================================================
-- 2) Non-vacuity floors
--=========================================================================================
checks = checks + 1
if totals.widgets >= WIDGET_FLOOR then
    print(string.format("ok   non-vacuity: %d widget(s) walked across all classes (floor %d)",
        totals.widgets, WIDGET_FLOOR))
else
    failures = failures + 1
    print(string.format(
        "FAIL non-vacuity: only %d widget(s) walked across all classes, below floor %d - "
        .. "the walk is not seeing the generated tables", totals.widgets, WIDGET_FLOOR))
end
checks = checks + 1
if totals.groups >= GROUP_FLOOR then
    print(string.format("ok   non-vacuity: %d group(s) walked (floor %d)", totals.groups, GROUP_FLOOR))
else
    failures = failures + 1
    print(string.format("FAIL non-vacuity: only %d group(s) walked, below floor %d",
        totals.groups, GROUP_FLOOR))
end
checks = checks + 1
if totals.orders >= ORDER_FLOOR then
    print(string.format("ok   non-vacuity: %d order field(s) checked (floor %d)",
        totals.orders, ORDER_FLOOR))
else
    failures = failures + 1
    print(string.format("FAIL non-vacuity: only %d order field(s) checked, below floor %d",
        totals.orders, ORDER_FLOOR))
end

-- Every type in the required-field map must actually occur, or its validators are dead.
for _, wtype in ipairs({ "toggle", "range", "select", "input", "execute", "color" }) do
    local n = totals.per_type[wtype] or 0
    checks = checks + 1
    if n >= PER_TYPE_FLOOR[wtype] then
        print(string.format("ok   non-vacuity: %d %s widget(s) (floor %d)",
            n, wtype, PER_TYPE_FLOOR[wtype]))
    else
        failures = failures + 1
        print(string.format(
            "FAIL non-vacuity: only %d %s widget(s), below floor %d - its required fields "
            .. "are not being checked", n, wtype, PER_TYPE_FLOOR[wtype]))
    end
end

--=========================================================================================
-- 3) The runtime casing fix (this used to be an accepted defect)
--=========================================================================================
-- The shipped load order used to make the REAL OnInitialize path fail before any options
-- tree existed:
--   * main.lua sets player_class to UnitClass's class FILENAME ("PALADIN", uppercase;
--     Blizzard's classic AuraUtil.lua compares exactly that value to "PALADIN");
--   * option_tables.lua redefined ST.class_hands with LOWERCASE keys, overwriting
--     main.lua's uppercase table because option_tables.lua loads later in every TOC;
--   * so set_opts() -> generate_bar_position_options_table -> ST:iter_hands() indexed nil
--     and aborted the rest of init at login.
-- The redefinition is gone and the lookup is case-tolerant; this block runs the true order
-- (no normalisation) and requires a clean build. If the defect ever returns, these checks
-- fail with the original evidence.
do
    local ST, _, env = load_modules("Paladin")
    if not ST then
        failures = failures + 1
        print("FAIL  runtime casing probe: modules do not load")
    else
        -- main.lua:281, then main.lua:303's self:set_opts().
        ST.player_class_pretty, ST.player_class = env.UnitClass("player")
        check(ST.class_hands[ST.player_class] ~= nil,
            "class_hands resolves the runtime class token (" .. tostring(ST.player_class) .. ")")
        local hands_ok, hands = pcall(ST.get_class_hands, ST)
        check(hands_ok and type(hands) == "table" and #hands >= 1,
            "get_class_hands returns the runtime hands")
        local ok, err = pcall(ST.set_opts, ST)
        check(ok, "runtime set_opts() builds the tree with the shipped casing (" ..
            tostring(err) .. ")")
    end
end

--=========================================================================================
-- 4) Non-paladin HUD/rotation wiring: hunter, warrior, druid, shaman
--=========================================================================================
-- The four classes define HUD_SLOTS + get_rotation_key in their class modules but
-- historically had neither hud_show_<key> defaults nor HUD/rotation option
-- sections (only PALADIN had them). This section pins the three-way parity:
--   (a) every HUD_SLOTS key in classes/<class>.lua has a hud_show_<key> = true
--       default in that class's config_presets.lua block;
--   (b) the built class panel carries the shared hud_*/rotation_label_* widgets
--       with the same types as the paladin's sections, plus one toggle per slot;
--   (c) widget orders inside each class panel are unique (a collision silently
--       stacks two widgets on one AceConfig row).
-- ON-consistency (owner order 2026-10-19 on-by-default package): the HUD master
-- hud_enabled ships true in the shared class_defaults (pinned in section 17;
-- rotation_label_enabled still ships false, checked in section 1 /
-- rotationtext_state.lua), so the per-slot `true` defaults surface together
-- with the bars on a fresh profile.
do
    local HUD_CLASSES = {
        { pretty = "Hunter", lower = "hunter", token = "HUNTER",
          slots = { "steady", "raptor", "kill_command", "multi",
              "bestial_wrath", "rapid_fire", "aimed", "trinket1", "trinket2" } },
        { pretty = "Warrior", lower = "warrior", token = "WARRIOR",
          slots = { "op", "execute", "slam", "hs", "cleave", "bt", "ww",
              "rend", "ms", "bladestorm", "raging_blow", "hamstring", "sunder",
              "trinket1", "trinket2" },
          -- The Sunder mirror ships OFF (operator ruling): the provider hides it
          -- unless the key reads exactly true, so false and nil both hide. The
          -- slot and its toggle still exist - only the default changed.
          off_slots = { "sunder" } },
        { pretty = "Druid", lower = "druid", token = "DRUID",
          slots = { "maul", "mangle", "rip", "rake", "bite", "shred",
              "tf", "berserk", "trinket1", "trinket2" } },
        { pretty = "Shaman", lower = "shaman", token = "SHAMAN",
          slots = { "stormstrike", "flameshock", "weave", "firenova",
              "earthshock", "twist", "trinket1", "trinket2" } },
        { pretty = "Rogue", lower = "rogue", token = "ROGUE",
          slots = { "snd", "rupture", "ea", "ar", "bf", "tea", "kick",
              "coldblood", "trinket1", "trinket2" } },
    }
    local HUD_SHARED_TYPES = {
        hud_enabled = "toggle", hud_locked = "toggle",
        hud_visibility_key = "select", hud_icon_size = "range",
        hud_match_bar_width = "toggle", hud_spacing = "range",
        hud_orientation = "select", hud_scale = "range",
        hud_x = "input", hud_y = "input",
        hud_show_text = "toggle", hud_font = "select",
        hud_text_size = "range", hud_text_outline = "select",
        hud_text_color = "color", hud_text_warn_color = "color",
        hud_border_size = "range", hud_border_color = "color",
        hud_glow_enabled = "toggle", hud_desaturate = "toggle",
        hud_mana_tint = "toggle", hud_range_tint = "toggle",
    }
    local ROTATION_SHARED_TYPES = {
        rotation_label_enabled = "toggle", rotation_label_locked = "toggle",
        rotation_label_visibility_key = "select", rotation_label_format = "select",
        rotation_label_align = "select", rotation_label_x = "input",
        rotation_label_y = "input", rotation_label_scale = "range",
        rotation_label_font = "select", rotation_label_size = "range",
        rotation_label_outline = "select", rotation_label_color = "color",
    }
    local function read_file(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text:gsub("\r\n", "\n")
    end
    local presets_src = read_file("config_presets.lua")
    for _, class in ipairs(HUD_CLASSES) do
        -- (a1) the class module declares every expected slot descriptor: the
        -- warrior's slots are conditional on family (cleave vs bt/ww), so the
        -- source union must carry every expected key.
        local class_src = read_file("classes/" .. class.lower .. ".lua")
        for _, slot in ipairs(class.slots) do
            check(class_src:find('key%s*=%s*"' .. slot .. '"') ~= nil,
                class.pretty .. ": the class module declares the '" .. slot .. "' slot")
        end

        -- (a2) every slot has a hud_show_<slot> = true default in the class block
        -- - except the off-by-default mirrors, which ship false (the provider
        -- hides them unless the key reads exactly true: nil = off, the druid
        -- Claw shape).
        local block = presets_src:match("ST%." .. class.token .. "%.defaults%s*=%s*{(.-)\n%}")
        check(block ~= nil, class.pretty .. ": the defaults block is found")
        block = block or ""
        local off_slots = {}
        for _, slot in ipairs(class.off_slots or {}) do
            off_slots[slot] = true
        end
        for _, slot in ipairs(class.slots) do
            local default_key = "hud_show_" .. slot
            if off_slots[slot] then
                check(block:find("%f[%a_]" .. default_key .. "%s*=%s*false") ~= nil,
                    class.pretty .. ": " .. default_key
                    .. " ships false in the defaults (hidden, no default-visible change)")
                check(block:find("%f[%a_]" .. default_key .. "%s*=%s*true") == nil,
                    class.pretty .. ": " .. default_key .. " ships no true default")
            else
                check(block:find("%f[%a_]" .. default_key .. "%s*=%s*true") ~= nil,
                    class.pretty .. ": " .. default_key .. " ships true in the defaults")
            end
        end

        -- (b) the built class panel carries the shared widgets plus per-slot toggles.
        local sb, err = build(class.pretty)
        check(sb ~= nil, class.pretty .. ": the options tree builds"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            check(sb.ST.opts_table.args.class ~= nil,
                class.pretty .. ": the class panel is generated")
            local args = sb.ST.opts_table.args.class
                and sb.ST.opts_table.args.class.args or {}
            local function widget_type(key)
                local w = args[key]
                if type(w) ~= "table" then return nil end
                return w.type
            end
            for key, widget_type_want in pairs(HUD_SHARED_TYPES) do
                check(widget_type(key) == widget_type_want,
                    class.pretty .. ": " .. key .. " has a " .. widget_type_want
                    .. " widget (got " .. tostring(widget_type(key)) .. ")")
            end
            for key, widget_type_want in pairs(ROTATION_SHARED_TYPES) do
                check(widget_type(key) == widget_type_want,
                    class.pretty .. ": " .. key .. " has a " .. widget_type_want
                    .. " widget (got " .. tostring(widget_type(key)) .. ")")
            end
            for _, slot in ipairs(class.slots) do
                local default_key = "hud_show_" .. slot
                check(widget_type(default_key) == "toggle",
                    class.pretty .. ": " .. default_key .. " has a toggle widget"
                    .. " (got " .. tostring(widget_type(default_key)) .. ")")
            end
            -- The alignment widget routes through the label's own set_align so the
            -- label does not jump when the anchor changes (the paladin contract).
            local align = args.rotation_label_align or {}
            check(type(align.set) == "function",
                class.pretty .. ": the alignment widget carries a set function")

            -- (c) every order in the class panel is unique. Previously scoped to
            -- orders >= 8.0 because the shipped warrior trackers carried a
            -- pre-existing collision (show_warrior_deep_wounds_bar at 3.1 vs
            -- warrior_demo_shout_bar_color at 3.10, numerically equal); the
            -- settings-build lane renumbered the whole warrior 3.1-3.19 band to
            -- 3.10-3.28 in file order (bench/settings_audit_2026-10-19.md W-O1),
            -- so the exemption is gone and the full panel is pinned.
            local orders, dupes = {}, 0
            for key, w in pairs(args) do
                if type(w) == "table" and type(w.order) == "number" then
                    if orders[w.order] then dupes = dupes + 1 end
                    orders[w.order] = key
                end
            end
            check(dupes == 0, class.pretty .. ": the class panel has no "
                .. "order collisions (" .. dupes .. " duplicate(s))")
        end
    end
end

--=========================================================================================
-- 5) Warrior Rampage badge wiring: default + toggle
--=========================================================================================
-- The badge reads show_warrior_rampage_badge == false as hidden
-- (classes/warrior.lua update_warrior_rampage_badge), so it is default-on: the
-- default ships true and the tracker-section toggle hides it.
do
    local f = assert(io.open(ROOT .. "config_presets.lua", "r"))
    local presets_src = f:read("*a")
    f:close()
    presets_src = presets_src:gsub("\r\n", "\n")
    local wblock = presets_src:match("ST%.WARRIOR%.defaults%s*=%s*{(.-)\n%}")
    check(wblock ~= nil, "WARRIOR: the defaults block is found")
    wblock = wblock or ""
    check(wblock:find("%f[%a_]show_warrior_rampage_badge%s*=%s*true") ~= nil,
        "WARRIOR: show_warrior_rampage_badge ships true in the defaults")
    local sb, err = build("Warrior")
    check(sb ~= nil, "WARRIOR: the options tree builds"
        .. (sb and "" or (": " .. tostring(err))))
    if sb then
        local args = sb.ST.opts_table.args.class
            and sb.ST.opts_table.args.class.args or {}
        local w = args.show_warrior_rampage_badge
        local got = (type(w) == "table") and w.type or nil
        check(got == "toggle",
            "WARRIOR: show_warrior_rampage_badge has a toggle widget (got "
            .. tostring(got) .. ")")
        if type(w) == "table" then
            check(w.get ~= nil and w.set ~= nil,
                "WARRIOR: the Rampage toggle carries get/set")
            check(type(w.order) == "number",
                "WARRIOR: the Rampage toggle carries a numeric order")
        end
    end
end

--=========================================================================================
-- 6) Round-1 options pass: every new toggle is wired and stays OFF by default
--=========================================================================================
-- The build-out round's reports document one new toggle set per lane; this pass adds the
-- AceConfig widgets. Each `== true`-read key must carry a toggle in its class panel and
-- must NOT ship a true default (nil/absent = off - no default-visible change). The two
-- D2 HUD slots are the hide-on-false shape (`== false` hides, like every sibling slot
-- toggle), so they ship true and are pinned as such. The two profile-level keys ship
-- false in config.lua. A wired default flipped to true is caught by the defaults-source
-- checks below (this suite's mutation proof for the pass).
do
    local CLASS_TOGGLES = {
        { pretty = "Paladin", token = "PALADIN", keys = {
            "twist_score_enabled", "twist_score_persist", "jotc_bar_enabled",
            "twist_lust_override_enabled", "aow_exo_pulse_enabled", "cd_icons_enabled",
            "reseal_marker_enabled" } },
        { pretty = "Warrior", token = "WARRIOR", keys = {
            "show_warrior_bank_cue", "show_warrior_battle_shout_badge",
            "show_warrior_desync_alert", "show_warrior_commanding_suppression" } },
        { pretty = "Hunter", token = "HUNTER", keys = {
            "hunter_bw_badge_enabled",
            "hunter_frenzy_stacks_enabled", "hunter_multi_target",
            "hunter_target_warning_enabled", "hunter_readiness_badge_enabled",
            "hunter_iss_badge_enabled", "hunter_oom_viper_badge_enabled",
            "hunter_lnl_badge_enabled", "hunter_weave_prog_enabled" } },
        { pretty = "Shaman", token = "SHAMAN", keys = {
            "show_shaman_stormstrike_bar", "show_shaman_wf_hold_tint",
            "show_shaman_rockbiter_badge", "show_shaman_spell_positions",
            "show_shaman_dw_sync", "show_shaman_lust_status" } },
        { pretty = "Druid", token = "DRUID", keys = {
            "show_druid_pips", "show_druid_shred_countdown", "show_druid_maul_badge",
            "show_druid_omen_glow", "show_druid_gcd_tick", "show_druid_ttd_readout" } },
    }
    -- Hide-on-false keys: true mirrors the sibling slot toggles and changes no behaviour.
    -- hunter_cast_zone_enabled ships true by operator ruling 2026-10-22 (the red Auto
    -- Shot cast window is the stop reference the hunter rotation is read against).
    local DEFAULT_ON = {
        { pretty = "Druid", token = "DRUID", keys = { "hud_show_tf", "hud_show_berserk" } },
        { pretty = "Hunter", token = "HUNTER", keys = { "hunter_cast_zone_enabled" } },
    }
    local f = assert(io.open(ROOT .. "config_presets.lua", "r"))
    local presets_src = f:read("*a")
    f:close()
    presets_src = presets_src:gsub("\r\n", "\n")

    local function defaults_block(token)
        return presets_src:match("ST%." .. token .. "%.defaults%s*=%s*{(.-)\n%}") or ""
    end

    local function check_class_toggles(class, want_default)
        local sb, err = build(class.pretty)
        check(sb ~= nil, class.pretty .. ": the options tree builds for the new toggles"
            .. (sb and "" or (": " .. tostring(err))))
        if not sb then return end
        local panel = sb.ST.opts_table.args.class
        local args = panel and panel.args or {}
        local handler = panel and panel.handler
        local block = defaults_block(class.token)
        check(block ~= "", class.pretty .. ": the defaults block is found for the new toggles")
        for _, key in ipairs(class.keys) do
            local w = args[key]
            check(type(w) == "table" and w.type == "toggle",
                class.pretty .. ": " .. key .. " has a toggle widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                check(type(w.order) == "number",
                    class.pretty .. ": " .. key .. " carries a numeric order")
                -- The widget must read the same class key the class code reads:
                -- resolve the handler name through the class group's handler and run
                -- the getter against the sandbox class table (the setter's refresh
                -- chain belongs to the per-module state suites; resolution only here).
                local getter = type(w.get) == "function" and w.get
                    or (type(w.get) == "string" and type(handler) == "table" and handler[w.get])
                    or nil
                local setter = type(w.set) == "function" and w.set
                    or (type(w.set) == "string" and type(handler) == "table" and handler[w.set])
                    or nil
                check(type(getter) == "function", class.pretty .. ": " .. key .. "'s get resolves")
                check(type(setter) == "function", class.pretty .. ": " .. key .. "'s set resolves")
                if type(getter) == "function" then
                    sb.class_db[key] = true
                    check(getter(nil, { "class", key }) == true,
                        class.pretty .. ": " .. key .. "'s getter reads the class key (true)")
                    sb.class_db[key] = nil
                    check(not getter(nil, { "class", key }),
                        class.pretty .. ": " .. key .. "'s getter reads the class key (nil = off)")
                end
                if want_default then
                    check(block:find("%f[%a_]" .. key .. "%s*=%s*true") ~= nil,
                        class.pretty .. ": " .. key .. " ships true in the defaults")
                else
                    check(block:find("%f[%a_]" .. key .. "%s*=%s*true") == nil,
                        class.pretty .. ": " .. key .. " does NOT ship a true default (nil = off)")
                end
            end
        end
    end

    for _, class in ipairs(CLASS_TOGGLES) do
        check_class_toggles(class, false)
    end
    for _, class in ipairs(DEFAULT_ON) do
        check_class_toggles(class, true)
    end

    -- design_mouse_anchor (designmode.lua): an inline widget in the Design Mode group;
    -- nil = off and the shared class defaults do not ship it true.
    local sb = build("Paladin")
    check(sb ~= nil, "design: the options tree builds")
    if sb then
        local group = sb.ST.opts_table.args.design_mode
        local w = group and group.args and group.args.design_mouse_anchor
        check(type(w) == "table" and w.type == "toggle",
            "design: design_mouse_anchor has a toggle widget (got "
            .. tostring(type(w) == "table" and w.type or nil) .. ")")
        if type(w) == "table" then
            check(type(w.order) == "number",
                "design: design_mouse_anchor carries a numeric order")
            if type(w.get) == "function" and type(w.set) == "function" then
                sb.class_db.design_mouse_anchor = true
                check(w.get() == true, "design: the widget reads design_mouse_anchor (true)")
                sb.class_db.design_mouse_anchor = nil
                check(w.get() ~= true, "design: the widget reads design_mouse_anchor (nil = off)")
            else
                check(false, "design: the widget carries get/set functions")
            end
        end
    end
    local cblock = presets_src:match("ST%.class_defaults%s*=%s*{(.-)\n%}") or ""
    check(cblock ~= "", "design: the shared class_defaults block is found")
    check(cblock:find("%f[%a_]design_mouse_anchor%s*=%s*true") == nil,
        "design: design_mouse_anchor does NOT ship a true default")

    -- The two profile-level keys (diag_tick_counters, enemy_swing_enabled): Behaviour
    -- panel widgets reading the profile table, shipped false in config.lua. They
    -- moved out of the top level in the 2026-10-19 Behaviour population (no copy
    -- left behind); the group carries the global handler so the string get/set
    -- resolve exactly as before.
    local cf = assert(io.open(ROOT .. "config.lua", "r"))
    local config_src = cf:read("*a")
    cf:close()
    config_src = config_src:gsub("\r\n", "\n")
    local psb = build("Paladin")
    check(psb ~= nil, "profile: the options tree builds")
    for _, key in ipairs({ "diag_tick_counters", "enemy_swing_enabled" }) do
        check(config_src:find("%f[%a_]" .. key .. "%s*=%s*false") ~= nil,
            "profile: " .. key .. " ships false in config.lua defaults")
        check(config_src:find("%f[%a_]" .. key .. "%s*=%s*true") == nil,
            "profile: " .. key .. " does not ship a true default")
        if psb then
            local bgroup = psb.ST.opts_table.args.behaviour
            check(type(bgroup) == "table" and bgroup.type == "group",
                "profile: the Behaviour panel exists for " .. key)
            local w = bgroup and bgroup.args and bgroup.args[key]
            check(type(w) == "table" and w.type == "toggle",
                "profile: " .. key .. " has a Behaviour toggle widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            check(psb.ST.opts_table.args[key] == nil,
                "profile: " .. key .. " leaves no top-level copy (moved, not copied)")
            if type(w) == "table" then
                local handler = (bgroup and bgroup.handler)
                    or psb.ST.opts_table.handler
                local getter = type(w.get) == "function" and w.get
                    or (type(handler) == "table" and handler[w.get]) or nil
                check(type(getter) == "function", "profile: " .. key .. "'s get resolves")
                if type(getter) == "function" then
                    psb.profile[key] = true
                    check(getter(nil, { key }) == true,
                        "profile: " .. key .. "'s getter reads the profile key (true)")
                    psb.profile[key] = false
                    check(getter(nil, { key }) == false,
                        "profile: " .. key .. "'s getter reads the profile key (false)")
                end
            end
        end
    end
end

--=========================================================================================
-- 6b) Hunter shot-report button: execute widget routing into practice_ui
--=========================================================================================
-- The H2 report frame (practice_ui.lua toggle_hunter_report, hidden by default) is
-- reachable from the hunter options panel. The button carries no db key (nothing to
-- default), so it is pinned here instead of the toggle table above: execute type with
-- a numeric order, a name that reflects the frame state, and a func that routes into
-- the practice_ui toggle (nil-safe when practice_ui is absent).
do
    local sb, err = build("Hunter")
    check(sb ~= nil, "report: the options tree builds"
        .. (sb and "" or (": " .. tostring(err))))
    if sb then
        local panel = sb.ST.opts_table.args.class
        local args = panel and panel.args or {}
        local w = args.hunter_shot_report
        check(type(w) == "table" and w.type == "execute",
            "report: hunter_shot_report is an execute widget (got "
            .. tostring(type(w) == "table" and w.type or nil) .. ")")
        if type(w) == "table" then
            check(type(w.order) == "number",
                "report: hunter_shot_report carries a numeric order")
            check(type(w.func) == "function",
                "report: hunter_shot_report carries a func")
            -- The func routes into the practice_ui toggle: stub the surface and count.
            local calls = 0
            sb.st.practice_ui = {
                hunter_report_visible = false,
                toggle_hunter_report = function(self)
                    calls = calls + 1
                end,
            }
            local ok, ferr = pcall(w.func)
            check(ok, "report: the func does not error (" .. tostring(ferr) .. ")")
            check(calls == 1, "report: the func routes into toggle_hunter_report")
            -- The name reflects the frame state (Show while hidden, Hide while shown).
            if type(w.name) == "function" then
                sb.st.practice_ui.hunter_report_visible = false
                check(w.name() == "Show Shot Report",
                    "report: the button offers Show while the frame is hidden")
                sb.st.practice_ui.hunter_report_visible = true
                check(w.name() == "Hide Shot Report",
                    "report: the button offers Hide while the frame is shown")
            else
                check(false, "report: hunter_shot_report carries a stateful name function")
            end
            -- Nil-safe: no practice_ui (a flavor without it) never errors.
            sb.st.practice_ui = nil
            local ok2, ferr2 = pcall(w.func)
            check(ok2, "report: the func does not error without practice_ui ("
                .. tostring(ferr2) .. ")")
        end
    end
end

--=========================================================================================
-- 7) Options-grade wiring pins: the Task-A dead locals stay gone, names unchanged
--=========================================================================================
-- Each luacheck unused/shadow warning in the options files was traced and either
-- wired or removed-with-rationale (bench/buildout_options-grade_2026-10-17.md).
-- These source checks pin the removals so a reintroduced dead local fails here,
-- and the runtime checks pin that the removals changed no displayed name.
do
    local function read_source(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end
    local config_src = read_source("config.lua")
    check(config_src:find("local LSM") == nil,
        "wiring: config.lua fetches no LSM handle (defaults are plain keys)")
    check(config_src:find("local LWIN") == nil,
        "wiring: config.lua fetches no LWIN handle (positions resolve in bars.lua)")
    check(config_src:find("local addon_name, st") ~= nil,
        "wiring: config.lua still binds st (the debug trailer reads st.debug)")
    local presets_src = read_source("config_presets.lua")
    check(presets_src:find("local LSM") == nil,
        "wiring: config_presets.lua fetches no LSM handle (plain default values)")
    local table_presets_src = read_source("option_table_presets.lua")
    check(table_presets_src:find("local addon_name, st") == nil,
        "wiring: option_table_presets.lua leaves the st vararg unbound (never used)")
    check(table_presets_src:find('LibStub%("LibSharedMedia%-3%.0"%)') ~= nil,
        "wiring: option_table_presets.lua keeps its LSM handle (values = LSM:HashTable)")
    local tables_src = read_source("option_tables.lua")
    check(tables_src:find("\nlocal print =") == nil,
        "wiring: option_tables.lua defines no print alias (only commented-out uses)")
    check(tables_src:find("local title = settings%.title") == nil,
        "wiring: generate_hand_options_table fetches no dead title local")
    local _, n_english = tables_src:gsub('local _, english_class = UnitClass%("player"%)', "")
    check(n_english == 1,
        "wiring: exactly one english_class binding remains (module scope, line 78)")
    check(tables_src:find("color_getter = function%(self") == nil,
        "wiring: class color_getter names no shadowing self param")
    check(tables_src:find("color_setter = function%(self") == nil,
        "wiring: class color_setter names no shadowing self param")

    -- The removals changed no displayed name: hand groups still carry panel_title.
    local psb = build("Paladin")
    check(psb ~= nil, "wiring: the options tree builds for the name pins")
    if psb then
        local mh = psb.ST.opts_table.args.mainhand
        check(type(mh) == "table" and mh.name == "Mainhand",
            "wiring: paladin mainhand group still named by panel_title (got "
            .. tostring(type(mh) == "table" and mh.name or nil) .. ")")
    end
    local wsb = build("Warrior")
    if wsb then
        local names = { mainhand = "Mainhand", offhand = "Offhand", ranged = "Ranged" }
        for hand, want in pairs(names) do
            local g = wsb.ST.opts_table.args[hand]
            check(type(g) == "table" and g.name == want,
                "wiring: warrior " .. hand .. " group still named by panel_title (got "
                .. tostring(type(g) == "table" and g.name or nil) .. ")")
        end
    end
end

--=========================================================================================
-- 8) Options-followup pins: warrior arms/SoD slot toggles, practice reset
--    re-anchor, pips x/y probe
--=========================================================================================
do
    local function read_followup_source(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end

    -- (a) The four arms/SoD slot toggles ride the hud_show_tf hide-on-false shape:
    -- hud.lua derives the db key from the slot key and hides on == false, so the
    -- shipped true defaults preserve the always-drawn rendering (no visible change).
    local hud_src = read_followup_source("hud.lua")
    check(hud_src:find('show_key = "hud_show_"', 1, true) ~= nil,
        "followup: hud.lua derives the toggle key from the slot key (hud_show_..key)")
    check(hud_src:find("db[icon.show_key] == false", 1, true) ~= nil,
        "followup: hud.lua hides the slot on == false (hide-on-false shape)")
    local wsb = build("Warrior")
    check(wsb ~= nil, "followup: the warrior options tree builds")
    if wsb then
        local panel = wsb.ST.opts_table.args.class
        local args = panel and panel.args or {}
        local handler = panel and panel.handler
        for _, key in ipairs({ "hud_show_rend", "hud_show_ms",
            "hud_show_bladestorm", "hud_show_raging_blow" }) do
            local w = args[key]
            check(type(w) == "table" and w.type == "toggle",
                "followup: " .. key .. " has a toggle widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                local getter = type(w.get) == "function" and w.get
                    or (type(w.get) == "string" and type(handler) == "table" and handler[w.get])
                    or nil
                local setter = type(w.set) == "function" and w.set
                    or (type(w.set) == "string" and type(handler) == "table" and handler[w.set])
                    or nil
                check(type(getter) == "function", "followup: " .. key .. "'s get resolves")
                check(type(setter) == "function", "followup: " .. key .. "'s set resolves")
                if type(getter) == "function" then
                    wsb.class_db[key] = true
                    check(getter(nil, { "class", key }) == true,
                        "followup: " .. key .. "'s getter reads the class key (true)")
                    wsb.class_db[key] = nil
                    check(getter(nil, { "class", key }) ~= false,
                        "followup: " .. key .. "'s getter reads the class key (nil = drawn)")
                end
            end
        end
    end

    -- (b) practice_reset_position re-anchors through the panel's own position
    -- applier (practice_ui.lua apply_settings re-reads the zeroed offsets and
    -- defers internally under combat lockdown), mirroring the update_result_font
    -- seam in the same options section.
    local tables_src = read_followup_source("option_tables.lua")
    check(tables_src:find("practice_ui.apply_settings", 1, true) ~= nil,
        "followup: the reset path routes through practice_ui.apply_settings")
    local psb = build("Paladin")
    check(psb ~= nil, "followup: the paladin options tree builds for the reset pin")
    if psb then
        local panel = psb.ST.opts_table.args.class
        local w = panel and panel.args and panel.args.practice_reset_position
        check(type(w) == "table" and type(w.func) == "function",
            "followup: practice_reset_position carries an execute func")
        if type(w) == "table" and type(w.func) == "function" then
            local applied = 0
            psb.st.practice_ui = { apply_settings = function() applied = applied + 1 end }
            psb.class_db.practice_panel_x = 42
            psb.class_db.practice_panel_y = -17
            w.func()
            check(psb.class_db.practice_panel_x == 0 and psb.class_db.practice_panel_y == 0,
                "followup: the reset zeroes the panel offsets")
            check(applied == 1, "followup: the reset re-anchors through apply_settings")
            psb.st.practice_ui = nil
            psb.class_db.practice_panel_x = 42
            psb.class_db.practice_panel_y = -17
            local ok = pcall(w.func)
            check(ok, "followup: the reset runs with no practice_ui loaded")
            check(psb.class_db.practice_panel_x == 0 and psb.class_db.practice_panel_y == 0,
                "followup: the reset zeroes the offsets with no practice_ui loaded")
        end
    end

    -- (c) Pips x/y probe: the bars.lua factory consumes opts.x/opts.y, but the only
    -- call site (druid.lua) passes literals and no druid_pips_x/y db key exists
    -- anywhere, so there is nothing to wire (no options without a consumer).
    local bars_src = read_followup_source("bars.lua")
    check(bars_src:find("tonumber(opts.x)", 1, true) ~= nil,
        "followup: the pips factory consumes opts.x")
    check(bars_src:find("tonumber(opts.y)", 1, true) ~= nil,
        "followup: the pips factory consumes opts.y")
    local druid_src = read_followup_source("classes/druid.lua")
    check(druid_src:find("druid_pips_x", 1, true) == nil,
        "followup: no druid_pips_x db key exists at the call site")
    check(druid_src:find("druid_pips_y", 1, true) == nil,
        "followup: no druid_pips_y db key exists at the call site")
    local presets_src = read_followup_source("config_presets.lua")
    check(presets_src:find("druid_pips_x", 1, true) == nil,
        "followup: no druid_pips_x default exists (correctly unwired)")
    check(presets_src:find("druid_pips_y", 1, true) == nil,
        "followup: no druid_pips_y default exists (correctly unwired)")
    check(tables_src:find("druid_pips_x", 1, true) == nil,
        "followup: no druid_pips_x widget exists (correctly unwired)")
end

--=========================================================================================
-- 9) ROGUE panel: panel <-> defaults <-> class-key round-trip
--=========================================================================================
-- The ROGUE section must reach parity with the other five class panels: every
-- class-table key classes/rogue.lua reads (db.<key>) has a widget AND a shipped
-- default, every widget resolves its get/set through the class handler, the
-- opt-in toggles stay nil-safe/off, every colour row is disabled-gated by its own
-- toggle, and the panel copy describes shipped behaviour only - the cues lane
-- landed the tick/pool/SS/swap/poison visuals and the HUD glow, so the
-- "future slice" wording must never come back.
do
    local function read_rogue_file(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end

    local class_src = read_rogue_file("classes/rogue.lua")
    local tables_src = read_rogue_file("option_tables.lua")
    local presets_src = read_rogue_file("config_presets.lua")
    local block = presets_src:match("ST%.ROGUE%.defaults%s*=%s*{(.-)\n%}") or ""
    check(block ~= "", "ROGUE: the defaults block is found for the round-trip")

    -- (a) Copy: shipped reality only. The rogue's own section source is sliced out
    -- so another panel's wording can never mask a stale rogue string.
    local rstart = tables_src:find("function ST%.class_opts_funcs%.ROGUE%(self%)")
    local rstop = tables_src:find("function ST:generate_bar_position_options_table", rstart or 1)
    check(rstart ~= nil, "ROGUE: the class panel source is found")
    check(rstop ~= nil, "ROGUE: the panel source is bounded by the next generator")
    local rogue_src = (rstart and rstop) and tables_src:sub(rstart, rstop) or ""
    local function no_phrase(phrase)
        check(rogue_src:find(phrase, 1, true) == nil,
            "ROGUE copy: stale phrase '" .. phrase .. "' is gone")
    end
    no_phrase("Slice A")
    no_phrase("later slice")
    no_phrase("the energy slice")
    no_phrase("the visuals land")
    no_phrase("ships no")
    no_phrase("will land")
    no_phrase("lands with")
    no_phrase("not yet wired")
    no_phrase("future slice")
    no_phrase("coming later")
    no_phrase("TODO")
    check(rogue_src:find("slice", 1, true) == nil,
        "ROGUE copy: no lowercase 'slice' wording remains")
    check(rogue_src:lower():find("glow", 1, true) ~= nil,
        "ROGUE copy: the shipped HUD glow is documented")
    check(rogue_src:find("0.1-0.2", 1, true) ~= nil,
        "ROGUE copy: the Sinister Strike window carries its shipped timing")
    check(rogue_src:find("GCD + swing reset", 1, true) ~= nil,
        "ROGUE copy: the weapon-swap cost is carried")

    -- (b) The built panel resolves every rogue widget through the class handler.
    local sb = build("Rogue")
    check(sb ~= nil, "ROGUE: the options tree builds for the round-trip")
    local panel = sb and sb.ST.opts_table.args.class
    local args = panel and panel.args or {}
    local handler = panel and panel.handler
    local function resolve(w, name)
        local f = w and w[name]
        if type(f) == "function" then return f, "inline" end
        if type(f) == "string" and type(handler) == "table" then
            local method = handler[f]
            if type(method) == "function" then return method, "handler" end
        end
        return nil, nil
    end
    local function get_value(w, info)
        local f, mode = resolve(w, "get")
        if not f then return nil end
        if mode == "inline" then return f(info) end
        return f(handler, info)
    end

    -- (c) Class -> panel -> defaults: every db.<key> the class reads must exist in
    -- both the panel and the shipped defaults (the three-way contract).
    local consumed, seen_count = {}, 0
    for key in class_src:gmatch("db%.([%a_][%w_]*)") do
        if not consumed[key] then
            consumed[key] = true
            seen_count = seen_count + 1
        end
    end
    check(seen_count >= 20,
        "ROGUE: the class key scan is non-vacuous (" .. seen_count .. " keys)")
    local consumed_sorted = {}
    for key in pairs(consumed) do consumed_sorted[#consumed_sorted + 1] = key end
    table.sort(consumed_sorted)
    for _, key in ipairs(consumed_sorted) do
        local w = args[key]
        check(type(w) == "table", "ROGUE panel: class key " .. key .. " has a widget")
        check(block:find("%f[%a_]" .. key .. "%s*=") ~= nil,
            "ROGUE defaults: class key " .. key .. " ships in the defaults block")
        if type(w) == "table" then
            local getter = resolve(w, "get")
            local setter = resolve(w, "set")
            check(type(getter) == "function", "ROGUE panel: " .. key .. "'s get resolves")
            check(type(setter) == "function", "ROGUE panel: " .. key .. "'s set resolves")
        end
    end

    -- (d) Round-trip per widget type through the real handlers. Generic class
    -- setters reconfigure the live bars, so they are resolution-checked only;
    -- inline setters are exercised. Every get reads the key the class reads.
    for _, key in ipairs(consumed_sorted) do
        local w = args[key]
        local info = { "class", key }
        local wtype = type(w) == "table" and w.type or nil
        if wtype == "toggle" then
            sb.class_db[key] = true
            check(get_value(w, info) == true,
                "ROGUE round-trip: " .. key .. " reads true when set")
            sb.class_db[key] = nil
            check(get_value(w, info) ~= true,
                "ROGUE round-trip: " .. key .. " reads nil = off")
        elseif wtype == "color" then
            sb.class_db[key] = { 255, 128, 0, 1 }
            local r, g, b, a = get_value(w, info)
            check(type(r) == "number" and type(g) == "number" and type(b) == "number"
                    and type(a) == "number",
                "ROGUE round-trip: " .. key .. " reads a colour table")
            check(type(r) == "number" and math.abs(r - 1) < 1e-6,
                "ROGUE round-trip: " .. key .. " converts 0-255 RGB")
            check(math.abs(g - 128 / 255) < 1e-6,
                "ROGUE round-trip: " .. key .. " converts the green channel")
        elseif wtype == "input" then
            local f, mode = resolve(w, "set")
            if mode == "inline" then
                f(info, "42")
                check(sb.class_db[key] == 42,
                    "ROGUE round-trip: " .. key .. "'s setter writes the key")
                check(get_value(w, info) == "42",
                    "ROGUE round-trip: " .. key .. "'s getter reads it back")
                sb.class_db[key] = nil
            end
        elseif wtype == "range" then
            local f, mode = resolve(w, "set")
            if mode == "inline" then
                -- The guide thresholds: nil = the engine default, never an empty field.
                sb.class_db[key] = nil
                local before = get_value(w, info)
                check(type(before) == "number",
                    "ROGUE threshold: " .. key .. " shows a number with no db value")
                f(info, 6)
                check(sb.class_db[key] == 6,
                    "ROGUE threshold: " .. key .. "'s setter writes the key")
                check(get_value(w, info) == 6,
                    "ROGUE threshold: " .. key .. "'s getter reads it back")
                sb.class_db[key] = nil
            else
                sb.class_db[key] = 33
                check(get_value(w, info) == 33,
                    "ROGUE round-trip: " .. key .. "'s getter reads the key")
                sb.class_db[key] = nil
            end
        end
    end

    -- (e) Every Round-2 opt-in carries its control (the brief's key list), so a
    -- lost widget fails even if classes/rogue.lua also stops reading the key.
    local REQUIRED = {
        show_rogue_energy_tick = "toggle", rogue_energy_tick_color = "color",
        show_rogue_pool_tint = "toggle", rogue_pool_tint_color = "color",
        rogue_pool_band_pre = "range", rogue_pool_band_post = "range",
        show_rogue_ss_window = "toggle", rogue_ss_color = "color",
        show_rogue_swap_cue = "toggle", rogue_swap_color = "color",
        show_rogue_poison_cue = "toggle", rogue_poison_color = "color",
        rogue_ea_duty = "toggle",
        rogue_rupture_refresh = "range", rogue_rupture_min_ttd = "range",
        rogue_finisher_min_cp = "range", rogue_ea_refresh = "range",
        rogue_shiv_refresh = "range", rogue_tea_energy_max = "range",
        nextaction_enabled = "toggle", nextaction_locked = "toggle",
        nextaction_visibility_key = "select", nextaction_icon_size = "range",
        nextaction_x = "input", nextaction_y = "input",
    }
    local required_keys = {}
    for key in pairs(REQUIRED) do required_keys[#required_keys + 1] = key end
    table.sort(required_keys)
    for _, key in ipairs(required_keys) do
        local w = args[key]
        local got = type(w) == "table" and w.type or nil
        check(got == REQUIRED[key],
            "ROGUE controls: " .. key .. " is a " .. REQUIRED[key] .. " (got "
            .. tostring(got) .. ")")
    end

    -- (f) Opt-in toggles stay nil-safe/off; the guide master + HUD slot toggles
    -- ship on (owner order 2026-10-19 on-by-default package: the HUD master now
    -- ships on too, so the guide + slots surface on a fresh profile); every
    -- colour ships a 0-255 RGB + 0-1 alpha table so a colour getter never
    -- indexes nil.
    for _, key in ipairs({
        "show_rogue_energy_tick", "show_rogue_pool_tint",
        "show_rogue_swap_cue",
        "show_rogue_poison_cue", "rogue_ea_duty",
    }) do
        check(block:find("%f[%a_]" .. key .. "%s*=%s*false") ~= nil,
            "ROGUE defaults: " .. key .. " ships false (nil = off)")
    end
    -- On-by-default package (OWNER ORDER 2026-10-19): the rogue guide master
    -- ships on. Nil-safe: nextaction_ui.should_show hides on == false, so nil
    -- reads as on, matching true.
    check(block:find("%f[%a_]nextaction_enabled%s*=%s*true") ~= nil,
        "ROGUE defaults: nextaction_enabled ships true (on-by-default, owner order)")
    check(block:find("%f[%a_]nextaction_enabled%s*=%s*false") == nil,
        "ROGUE defaults: nextaction_enabled ships no false default")
    -- Redzone exception (OWNER ORDER 2026-10-19, rogue-redzone): the Era SS
    -- window ships visible - the explicit gate for this default-visible change.
    -- The class gates on == true, so nil still reads off.
    check(block:find("%f[%a_]show_rogue_ss_window%s*=%s*true") ~= nil,
        "ROGUE defaults: show_rogue_ss_window ships true (Era red zone, owner order)")
    check(block:find("%f[%a_]nextaction_locked%s*=%s*true") ~= nil,
        "ROGUE defaults: nextaction_locked ships true")
    for _, key in ipairs({
        "rogue_energy_tick_color", "rogue_pool_tint_color",
        "rogue_ss_color", "rogue_swap_color", "rogue_poison_color",
    }) do
        local r, g, b, a = block:match("%f[%a_]" .. key
            .. "%s*=%s*{%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*([%d%.]+)%s*}")
        local ok = r ~= nil and tonumber(r) <= 255 and tonumber(g) <= 255
            and tonumber(b) <= 255 and tonumber(a) >= 0 and tonumber(a) <= 1
        check(ok, "ROGUE defaults: " .. key .. " ships a 0-255 RGB + 0-1 alpha colour")
    end
    do
        local r, g, b = block:match("%f[%a_]rogue_ss_color"
            .. "%s*=%s*{%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        check(r ~= nil and tonumber(r) >= 200 and tonumber(g) <= 100
                and tonumber(b) <= 100,
            "ROGUE defaults: rogue_ss_color ships red (owner order)")
    end

    -- The six guide thresholds ship the pure engine's own defaults (the pure
    -- module loads in this sandbox), so the panel value and the engine can never
    -- drift apart silently.
    local GUIDE_DEFAULTS = {
        { key = "rogue_rupture_refresh", constant = "RUPTURE_REFRESH_DEFAULT" },
        { key = "rogue_rupture_min_ttd", constant = "RUPTURE_MIN_TTD_DEFAULT" },
        { key = "rogue_finisher_min_cp", constant = "FINISHER_MIN_CP_DEFAULT" },
        { key = "rogue_ea_refresh", constant = "EA_REFRESH_DEFAULT" },
        { key = "rogue_shiv_refresh", constant = "SHIV_REFRESH_DEFAULT" },
        { key = "rogue_tea_energy_max", constant = "TEA_ENERGY_MAX_DEFAULT" },
    }
    local rg = sb and sb.st.rogue_guide
    check(type(rg) == "table", "ROGUE: the pure guide loads in the options sandbox")
    for _, spec in ipairs(GUIDE_DEFAULTS) do
        local want = rg and rg[spec.constant]
        local got = tonumber(block:match("%f[%a_]" .. spec.key .. "%s*=%s*(%d+%.?%d*)"))
        check(type(want) == "number" and got == want,
            "ROGUE defaults: " .. spec.key .. " ships the engine default ("
            .. tostring(want) .. ", got " .. tostring(got) .. ")")
        local w = args[spec.key]
        if type(w) == "table" then
            sb.class_db[spec.key] = nil
            check(get_value(w, { "class", spec.key }) == want,
                "ROGUE threshold: " .. spec.key .. " falls back to the engine default")
        end
    end

    -- (g) Every colour row is disabled-gated by its own toggle, like the siblings.
    local COLOUR_GATES = {
        { colour = "rogue_energy_tick_color", toggle = "show_rogue_energy_tick" },
        { colour = "rogue_pool_tint_color", toggle = "show_rogue_pool_tint" },
        { colour = "rogue_ss_color", toggle = "show_rogue_ss_window" },
        { colour = "rogue_swap_color", toggle = "show_rogue_swap_cue" },
        { colour = "rogue_poison_color", toggle = "show_rogue_poison_cue" },
    }
    for _, pair in ipairs(COLOUR_GATES) do
        local w = args[pair.colour]
        check(type(w) == "table" and type(w.disabled) == "function",
            "ROGUE gate: " .. pair.colour .. " carries a disabled function")
        if type(w) == "table" and type(w.disabled) == "function" then
            sb.class_db[pair.toggle] = nil
            check(w.disabled() and true or false,
                "ROGUE gate: " .. pair.colour .. " is disabled while "
                .. pair.toggle .. " is off")
            sb.class_db[pair.toggle] = true
            check(not w.disabled(),
                "ROGUE gate: " .. pair.colour .. " enables with " .. pair.toggle)
            sb.class_db[pair.toggle] = nil
        end
    end
end

--=========================================================================================
-- 10) Sim-value sweep: shipped numeric defaults vs bench/*_rotation_audit_2026-10-19.md
--=========================================================================================
-- Job 1 (sim values): every shipped rotation number below is either updated to
-- the sim-exact value with a code comment citing the source, or kept with a
-- reason in config_presets.lua. This section pins the landed values so a
-- future edit that reintroduces a sim-contradicted default fails here.
-- UI positions/sizes/colours are not rotation numbers and are not swept.
do
    local function read_presets()
        local f = assert(io.open(ROOT .. "config_presets.lua", "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end
    local presets_src = read_presets()
    local function defaults_block(token)
        return presets_src:match("ST%." .. token .. "%.defaults%s*=%s*{(.-)\n%}") or ""
    end
    local function num(block, key)
        -- Line-anchored: prose comments elsewhere in the block may name a
        -- value (e.g. "sim-exact zero"), so only a real default line counts.
        return tonumber(block:match("\n%s*" .. key .. "%s*=%s*(%d+%.?%d*)"))
    end

    -- (a) SHAMAN Flame Shock refresh: the sim-exact value is 0 (expiry-only) and it
    -- SHIPS 0. Every sim re-applies only when the dot is INACTIVE (audit cross-sim
    -- finding 3: SoD P6/P4, Era default, TBC default, Forever testing.build all use
    -- `not dotIsActive`; none refresh early), so 0 is the sim value and the engine
    -- honors explicit 0 (recast-when-missing). The flip 3->0 landed together with its
    -- tests/shaman_guide_state.lua pins (BS-4c, one writer per file): the gather's
    -- default threshold is 0 and the rule-6 boundary pins read "refresh on expiry".
    do
        local block = defaults_block("SHAMAN")
        check(block ~= "", "SIM: the SHAMAN defaults block is found")
        check(num(block, "guide_flameshock_refresh") == 0,
            "SIM: guide_flameshock_refresh ships 0 (the sim-exact expiry-only value; got "
            .. tostring(num(block, "guide_flameshock_refresh")) .. ")")
        -- The widget still tunes it (0-10 s range): 0 means recast-when-missing.
        local sb, err = build("Shaman")
        check(sb ~= nil, "SIM: the shaman options tree builds"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            local args = sb.ST.opts_table.args.class
                and sb.ST.opts_table.args.class.args or {}
            local w = args.guide_flameshock_refresh
            check(type(w) == "table" and w.type == "range",
                "SIM: guide_flameshock_refresh keeps its range widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
        end
    end

    -- (b) WARRIOR Execute range: sim-exact 20. Era isExecutePhase E20 (both
    -- APLs), TBC execute.go E20-only, SoD E20-or-Sudden-Death, Forever
    -- Victory Rush is Victorious-gated (audit §2 M4). No change; pinned.
    do
        local block = defaults_block("WARRIOR")
        check(num(block, "guide_execute_pct") == 20,
            "SIM: guide_execute_pct ships 20 (E20 on every sim client; got "
            .. tostring(num(block, "guide_execute_pct")) .. ")")
    end

    -- (c) DRUID Rip/Rake refresh: kept 4 with reason (legacy fallback). All
    -- sims with a row are expiry-only (TBC ripNow/rakeNow, Wrath ripNow/rakeNow,
    -- Forever F3/F4 expiry-only, SoD canRip never-clips — audit T-1/W-5/F-3/S-6),
    -- and the TBC/SoD/WRATH/FOREVER chains already refresh on expiry without
    -- reading these windows. The shipped 4s windows only run on the legacy
    -- fallback chain (unknown families such as Cata/Mists, no sim in scope).
    do
        local block = defaults_block("DRUID")
        check(num(block, "guide_rip_refresh") == 4,
            "SIM: guide_rip_refresh ships 4 (legacy fallback; sim chains are expiry-only; got "
            .. tostring(num(block, "guide_rip_refresh")) .. ")")
        check(num(block, "guide_rake_refresh") == 4,
            "SIM: guide_rake_refresh ships 4 (legacy fallback; sim chains are expiry-only; got "
            .. tostring(num(block, "guide_rake_refresh")) .. ")")
    end

    -- (d) PALADIN filler mana 35/30 + CS delay 900: kept with reason (no single
    -- sim value). TBC sim defaults fillers to false (opt-in; engine matches
    -- whenever the target count is known); Forever sim gates on mana >= 10%
    -- (audit TBC + Forever GAPs) — lowering to 10 would over-prompt on TBC.
    -- CS 900ms is the researched pull-phase compromise (TBC sim holds via the
    -- 11 s Delay Major CDs variable; audit TBC CONFLICT) with the pull-hold
    -- latch engine-side.
    do
        local block = defaults_block("PALADIN")
        check(num(block, "nextaction_filler_mana_consecration") == 35,
            "SIM: nextaction_filler_mana_consecration ships 35 (no single sim value; got "
            .. tostring(num(block, "nextaction_filler_mana_consecration")) .. ")")
        check(num(block, "nextaction_filler_mana_exorcism") == 30,
            "SIM: nextaction_filler_mana_exorcism ships 30 (no single sim value; got "
            .. tostring(num(block, "nextaction_filler_mana_exorcism")) .. ")")
        check(num(block, "nextaction_cs_max_delay_ms") == 900,
            "SIM: nextaction_cs_max_delay_ms ships 900 (researched, not sim; got "
            .. tostring(num(block, "nextaction_cs_max_delay_ms")) .. ")")
    end

    -- (e) ROGUE thresholds + pool bands: kept with reason (unknown-family
    -- fallback; per-client sim numbers already live engine-side in
    -- rogue_guide.lua family tables — audit T-M1/V-G6/W-M1 pool, H4 EA,
    -- H10 Tea, T-G3/H9 rupture, T-C1/W-M2/V-G3 floors, E-M1 5CP, E-G4 3s).
    -- The shipped values are the ERA/WRATH shape (E-G4 MATCH at 3s, E-M1
    -- MATCH at 5CP, W-M2 MATCH at 8s for 1CP); TBC/FOREVER sim rows ride the
    -- family tables whenever the db override is nil. Section 9 already pins
    -- each ships the engine default; this pins the sim provenance explicitly.
    do
        local block = defaults_block("ROGUE")
        check(num(block, "rogue_pool_band_pre") == 65,
            "SIM: rogue_pool_band_pre ships 65 (ERA/WRATH fallback; TBC 71 + FOREVER 75 in POOL_BANDS)")
        check(num(block, "rogue_pool_band_post") == 85,
            "SIM: rogue_pool_band_post ships 85 (ERA/WRATH fallback; TBC 71 + FOREVER 75 in POOL_BANDS)")
        check(num(block, "rogue_rupture_refresh") == 4,
            "SIM: rogue_rupture_refresh ships 4 (ERA/WRATH; TBC/FOREVER 0 in RUPTURE_REFRESH_BY_FAMILY)")
        check(num(block, "rogue_rupture_min_ttd") == 8,
            "SIM: rogue_rupture_min_ttd ships 8 (sourced 1CP row; per-client floors in RUPTURE_MIN_TTD_BY_FAMILY)")
        check(num(block, "rogue_finisher_min_cp") == 5,
            "SIM: rogue_finisher_min_cp ships 5 (ERA/TBC; WRATH 4 + FOREVER 3 in FINISHER_MIN_CP_BY_FAMILY)")
        check(num(block, "rogue_ea_refresh") == 3,
            "SIM: rogue_ea_refresh ships 3 (ERA IEA MATCH; TBC 6 + FOREVER 16 in EA_REFRESH_BY_FAMILY)")
        check(num(block, "rogue_shiv_refresh") == 2,
            "SIM: rogue_shiv_refresh ships 2 (watch-list window, no sim row; filed Mutilate+EA context)")
        check(num(block, "rogue_tea_energy_max") == 40,
            "SIM: rogue_tea_energy_max ships 40 (WRATH; ERA 29 + TBC 30 + FOREVER 15 in TEA_ENERGY_MAX_BY_FAMILY)")
    end

    -- (f) HUNTER: no rotation threshold defaults ship (the guide carries none;
    -- audit ranks LnL/Serpent/Arcane/Sniper as missing inputs/slots, filed).
    do
        local block = defaults_block("HUNTER")
        check(block:find("%f[%a_]guide_[%a_]*refresh%s*=") == nil
                and block:find("%f[%a_]guide_execute_pct%s*=") == nil
                and block:find("%f[%a_]rogue_") == nil,
            "SIM: HUNTER ships no refresh/threshold defaults (inputs/slots filed, not tunables)")
    end
end

--=========================================================================================
-- 11) Options-complete + wowsims synergy block
--=========================================================================================
-- Job 2: for every class with a panel, every class-table key the class reads
-- has a widget (toggle/color/range) and the wowsims synergy block is present.
-- Anything needing a class-file change is a filed follow-up, not a guess:
-- hunter_multi_target has shipped a widget with no consumer since the round-1
-- pass (manual multi-target needs a guide/gather wire) — pinned here as the
-- filed follow-up so a future wire closes it instead of silently shipping.
do
    local PANELS = { "Paladin", "Warrior", "Hunter", "Shaman", "Druid", "Rogue" }
    local SIM_URLS = {
        Paladin = { "wowsims/classic", "wowsims/sod", "wowsims/tbc%-new", "wowsims/forever" },
        Warrior = { "wowsims/classic", "wowsims/sod", "wowsims/tbc%-new", "wowsims/forever" },
        Hunter = { "wowsims/classic", "wowsims/sod", "wowsims/tbc%-new", "wowsims/wotlk", "wowsims/forever" },
        Shaman = { "wowsims/classic", "wowsims/sod", "wowsims/tbc%-new", "wowsims/forever" },
        Druid = { "wowsims/classic", "wowsims/sod", "wowsims/tbc%-new", "wowsims/wotlk", "wowsims/forever" },
        Rogue = { "wowsims/classic", "wowsims/sod", "wowsims/tbc%-new", "wowsims/wotlk", "wowsims/forever" },
    }
    for _, pretty in ipairs(PANELS) do
        local sb, err = build(pretty)
        check(sb ~= nil, "WOWSIMS: the " .. pretty .. " options tree builds"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            local args = sb.ST.opts_table.args.class
                and sb.ST.opts_table.args.class.args or {}
            -- (a) The synergy block: header + description, text-only.
            local header, desc = args.wowsims_header, args.wowsims_desc
            check(type(header) == "table" and header.type == "header",
                "WOWSIMS: " .. pretty .. " carries a wowsims_header (got "
                .. tostring(type(header) == "table" and header.type or nil) .. ")")
            check(type(desc) == "table" and desc.type == "description",
                "WOWSIMS: " .. pretty .. " carries a wowsims_desc (got "
                .. tostring(type(desc) == "table" and desc.type or nil) .. ")")
            if type(header) == "table" then
                check(type(header.order) == "number",
                    "WOWSIMS: " .. pretty .. " header carries a numeric order")
            end
            if type(desc) == "table" then
                check(type(desc.order) == "number",
                    "WOWSIMS: " .. pretty .. " desc carries a numeric order")
                local text = type(desc.name) == "string" and desc.name or ""
                for _, url in ipairs(SIM_URLS[pretty]) do
                    check(text:find(url) ~= nil,
                        "WOWSIMS: " .. pretty .. " desc names " .. url .. " as display text")
                end
                check(text:lower():find("practice the sim in%-game", 1) ~= nil,
                    "WOWSIMS: " .. pretty .. " desc carries the practice-the-sim-in-game positioning")
                -- Text-only: WoW cannot open external links, so the block must
                -- never fake clickability (no func, no get/set, no input).
                check(desc.func == nil,
                    "WOWSIMS: " .. pretty .. " desc carries no func (text-only, no fake link)")
                check(desc.get == nil and desc.set == nil,
                    "WOWSIMS: " .. pretty .. " desc carries no get/set (text-only)")
            end
        end
    end

    -- (b) Filed follow-up: hunter_multi_target ships a widget with no consumer.
    -- The round-1 pass added the toggle (manual multi-target needs a
    -- guide/gather wire: hunter_guide has no multi_target input and no gather
    -- writes it). Removing the widget would break the section-6 pin and hide
    -- the intent; wiring it needs a class-file change (OUT of this lane), so
    -- it stays as the filed follow-up and fails here the moment it gains a
    -- consumer without a test update or loses its widget without the wire.
    do
        local function read_source(path)
            local f = assert(io.open(ROOT .. path, "r"))
            local src = f:read("*a")
            f:close()
            return src:gsub("\r\n", "\n")
        end
        local hsb, herr = build("Hunter")
        check(hsb ~= nil, "FOLLOWUP: the hunter options tree builds"
            .. (hsb and "" or (": " .. tostring(herr))))
        if hsb then
            local args = hsb.ST.opts_table.args.class
                and hsb.ST.opts_table.args.class.args or {}
            check(type(args.hunter_multi_target) == "table"
                    and args.hunter_multi_target.type == "toggle",
                "FOLLOWUP: hunter_multi_target keeps its toggle widget (filed wire owed)")
        end
        local guide_src = read_source("hunter_guide.lua")
        local class_src = read_source("classes/hunter.lua")
        local ui_src = read_source("hunter_ui.lua")
        local consumed = guide_src:find("multi_target") ~= nil
            or class_src:find("multi_target") ~= nil
            or ui_src:find("multi_target") ~= nil
        -- The widget source itself mentions the key; the three consumer files
        -- must not (until the wire lands). Strip the widget file from this check.
        check(not consumed,
            "FOLLOWUP: hunter_multi_target has no guide/gather/UI consumer yet (wire filed, not guessed)")
    end
end

--=========================================================================================
-- 12) HUD layout template select: widget surface + nil default + curated tables
--=========================================================================================
-- bench/hud_templates_2026-10-19.md §7: each of the six HUD classes carries one
-- hud_template select (order 8.02) whose values are Custom + the class's
-- template ids; the curated sets live in ST.<TOKEN>.HUD_TEMPLATES;
-- hud_template ships nil (Custom = current behavior, zero default-visible
-- change). The deep slot/geometry/persistence contract is pinned by
-- tests/hud_templates_state.lua; this section pins the options-tree surface
-- only (widget shape, values, nil-safe get/set resolution, nil default).
do
    local TEMPLATE_IDS = {
        Paladin = { "twist_core", "full_ret", "minimal" },
        Warrior = { "fury_core", "full_trinkets", "arms_sod" },
        Hunter = { "shot_rotation", "full_bm", "minimal_glow" },
        Druid = { "bleed_core", "full_feral", "bear_guard" },
        Shaman = { "twist_core", "full_weave", "minimal" },
        Rogue = { "core", "full_cds", "pvp_utility" },
    }
    local TOKEN = {
        Paladin = "PALADIN", Warrior = "WARRIOR", Hunter = "HUNTER",
        Druid = "DRUID", Shaman = "SHAMAN", Rogue = "ROGUE",
    }
    -- Gallery display strings (bench/weakaura_templates_2026-10-19.md §3):
    -- shortlist 1 keeps the R-T1 UxkIny anchor name, shortlist 5 the W-T1
    -- Fury Core name; every other entry keeps its design-spec name. Exact
    -- match so a gallery rename fails here, not in-client.
    local VALUES = {
        Paladin = { twist_core = "P-T1 Twist Core", full_ret = "P-T2 Full Ret + Trinkets", minimal = "P-T3 Minimal" },
        Warrior = { fury_core = "W-T1 Fury Core", full_trinkets = "W-T2 Full + Trinkets", arms_sod = "W-T3 Arms / SoD (provisional)" },
        Hunter = { shot_rotation = "H-T1 Shot Rotation", full_bm = "H-T2 Full BM + Trinkets", minimal_glow = "H-T3 Minimal + Glow" },
        Druid = { bleed_core = "D-T1 Bleed Core", full_feral = "D-T2 Full Feral + Pops", bear_guard = "D-T3 Bear Guard" },
        Shaman = { twist_core = "S-T1 Twist Core", full_weave = "S-T2 Full Enhance + Weave", minimal = "S-T3 Minimal" },
        Rogue = { core = "R-T1 UxkIny-style Core", full_cds = "R-T2 Full + CDs + Trinkets", pvp_utility = "R-T3 PvP Utility (provisional)" },
    }
    local f = assert(io.open(ROOT .. "config_presets.lua", "r"))
    local presets_src = f:read("*a")
    f:close()
    presets_src = presets_src:gsub("\r\n", "\n")
    local function defaults_block(token)
        return presets_src:match("ST%." .. token .. "%.defaults%s*=%s*{(.-)\n%}") or ""
    end
    for pretty, ids in pairs(TEMPLATE_IDS) do
        local token = TOKEN[pretty]
        local sb, err = build(pretty)
        check(sb ~= nil, "TEMPLATE: the " .. pretty .. " options tree builds"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            local panel = sb.ST.opts_table.args.class
            local args = panel and panel.args or {}
            local w = args.hud_template
            check(type(w) == "table" and w.type == "select",
                "TEMPLATE: " .. pretty .. " hud_template is a select (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                check(w.order == 8.02,
                    "TEMPLATE: " .. pretty .. " hud_template sits at order 8.02")
                check(type(w.values) == "table" and w.values.custom == "Custom",
                    "TEMPLATE: " .. pretty .. " values carry Custom")
                for _, id in ipairs(ids) do
                    check(type(w.values[id]) == "string",
                        "TEMPLATE: " .. pretty .. " values name '" .. id .. "'")
                end
                for id, want in pairs(VALUES[pretty]) do
                    check(w.values[id] == want,
                        "GALLERY: " .. pretty .. " values name '" .. id .. "' exactly")
                end
                check(type(w.get) == "function",
                    "TEMPLATE: " .. pretty .. " get resolves")
                check(type(w.set) == "function",
                    "TEMPLATE: " .. pretty .. " set resolves")
                -- Nil-safe get: fresh profile reads Custom through the handler.
                if type(w.get) == "function" then
                    sb.class_db.hud_template = nil
                    check(w.get() == "custom",
                        "TEMPLATE: " .. pretty .. " nil reads Custom")
                end
                -- The curated table ships with exactly these ids.
                local templates = sb.ST[token] and sb.ST[token].HUD_TEMPLATES
                check(type(templates) == "table",
                    "TEMPLATE: " .. pretty .. " ST." .. token
                    .. ".HUD_TEMPLATES exists")
                if type(templates) == "table" then
                    local n = 0
                    for _ in pairs(templates) do n = n + 1 end
                    check(n == #ids,
                        "TEMPLATE: " .. pretty .. " ships the documented ids")
                    for _, id in ipairs(ids) do
                        check(type(templates[id]) == "table",
                            "TEMPLATE: " .. pretty .. " ships '" .. id .. "'")
                    end
                end
            end
        end
        local block = defaults_block(token)
        check(block ~= "", "TEMPLATE: " .. pretty .. " defaults block is found")
        check(block:find("%f[%a_]hud_template%s*=%s*nil") ~= nil,
            "TEMPLATE: " .. pretty .. " hud_template ships nil (Custom)")
        check(block:find("%f[%a_]hud_template%s*=%s*true") == nil
                and block:find('%f[%a_]hud_template%s*=%s*"') == nil,
            "TEMPLATE: " .. pretty .. " hud_template ships no visible default")
        check(block:find("%f[%a_]hud_template%s*=%s*false") == nil,
            "TEMPLATE: " .. pretty .. " hud_template is nil, not false")
    end
end

--=========================================================================================
-- 13) Paladin mana governor + filed follow-ups (hard-wait, shaman F7, druid RipCP)
--=========================================================================================
-- (a) twist_mana_threshold_pct: the consumer (classes/paladin.lua:3281-3285)
-- reads it nil-safe (non-number/NaN = off = archived). The widget is a 0-100
-- range with a nil-safe inline getter (a fresh profile renders 0 = off, never
-- an empty slider: AceConfigDialog feeds get straight into Slider:SetValue,
-- which errors on nil). The SHIPPED default is 0 - the documented OFF state
-- (BS-7 / P-22): 0 and nil both never throttle (mana_pct never reads below 0,
-- so mana_pct < 0 is false; nextaction.lua:556-557), so 0 displays the off
-- state honestly, re-disables the governor and changes nothing on a fresh
-- profile. The cited source (docs/research/tbc_minmax.md:27 - "twisting at
-- 100% uptime ooms in 1-2 min without mana support") names NO percentage, and
-- a non-zero default would change the live TBC guide's prompts with no
-- operator gate - so the value ships off and the player sets the percent
-- deliberately. The setter is the class generic.
-- (b)(c) filed with file:line per wire-not-strip: the consumer does not
-- exist yet, so NO widget ships (an unread key would be an inert toggle).
-- (d) WIRED: the gather feeds db.guide_rip_min_cp raw
-- (classes/druid.lua:1707) and the engine clamps 2-5 / defaults nil to 4
-- (druid_guide.lua:515-520) - every built widget has its consumer cited.
-- Each pin asserts the key stays correctly UNWIRED (no widget, no default)
-- so the future wire updates the test instead of shipping silently.
--   (b) hard-wait: out.hard_wait (nextaction.lua:836-849) has no db key; the
--       hold-state render is filed at nextaction_ui (bench
--       /paladin_followups_2026-10-19.md §3; feed classes/paladin.lua:2897).
--   (c) shaman F7 dedicated hold/SR/ES (bench/shaman follow-up): the live
--       hold opt-in stays the tint reuse (classes/shaman.lua:2600);
--       weave.should_pause_twist_for_mana is UNWIRED (weave.lua:632-637);
--       the SR/ES thresholds are engine constants only
--       (shaman_guide.lua:244-252 - the panel exposes only Flame Shock).
--   (d) druid RipCP WIRED: the gather reads db.guide_rip_min_cp
--       (classes/druid.lua:1707); the engine default is RIP_MIN_CP_TBC
--       = 4 (druid_guide.lua:401,515-520). Widget + default ship below.
do
    local function read_source_13(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end
    local presets_src = read_source_13("config_presets.lua")
    local tables_src = read_source_13("option_tables.lua")
    local function defaults_block_13(token)
        return presets_src:match("ST%." .. token .. "%.defaults%s*=%s*{(.-)\n%}") or ""
    end
    local function no_default_line(block, key)
        return block:match("\n%s*" .. key .. "%s*=") == nil
    end

    -- (a) The mana widget round-trips through the real tree.
    local psb, perr = build("Paladin")
    check(psb ~= nil, "MANA: the paladin options tree builds"
        .. (psb and "" or (": " .. tostring(perr))))
    if psb then
        local panel = psb.ST.opts_table.args.class
        local args = panel and panel.args or {}
        local handler = panel and panel.handler
        local w = args.twist_mana_threshold_pct
        check(type(w) == "table" and w.type == "range",
            "MANA: twist_mana_threshold_pct is a range widget (got "
            .. tostring(type(w) == "table" and w.type or nil) .. ")")
        if type(w) == "table" then
            check(w.min == 0 and w.max == 100 and type(w.step) == "number",
                "MANA: the range spans 0-100 (percent)")
            check(type(w.order) == "number",
                "MANA: the range carries a numeric order")
            check(type(w.get) == "function",
                "MANA: the getter is inline (nil-safe, never an empty slider)")
            if type(w.get) == "function" then
                psb.class_db.twist_mana_threshold_pct = nil
                check(w.get() == 0,
                    "MANA: nil reads 0 (off, archived behaviour)")
                psb.class_db.twist_mana_threshold_pct = 35
                check(w.get() == 35,
                    "MANA: a set value reads back")
                psb.class_db.twist_mana_threshold_pct = "lots"
                check(w.get() == 0,
                    "MANA: a non-number reads 0 (off, like the consumer)")
                psb.class_db.twist_mana_threshold_pct = nil
            end
            -- The setter resolves through the class handler (resolution only:
            -- the generic setter's bar-reconfigure chain belongs to the
            -- per-module state suites, per section 6).
            local setter = type(w.set) == "string" and type(handler) == "table"
                and handler[w.set] or nil
            check(type(setter) == "function",
                "MANA: the setter resolves through the class handler")
        end
        -- No widget collides with it: the twist-section orders stay unique.
        local seen, dupes = {}, 0
        for key, widget in pairs(args) do
            if type(widget) == "table" and type(widget.order) == "number"
                and widget.order >= 3.0 and widget.order < 5.0 then
                if seen[widget.order] then dupes = dupes + 1 end
                seen[widget.order] = key
            end
        end
        check(dupes == 0, "MANA: the paladin 3.x/4.x orders stay unique ("
            .. dupes .. " duplicate(s))")
    end
    local pblock = defaults_block_13("PALADIN")
    check(pblock ~= "", "MANA: the PALADIN defaults block is found")
    local mana_num = tonumber(pblock:match("\n%s*twist_mana_threshold_pct%s*=%s*(%d+%.?%d*)"))
    eq(mana_num, 0,
        "MANA: twist_mana_threshold_pct ships 0 (the documented off state; 0 and nil "
        .. "behave identically - the governor never fires at 0)")
    check(tables_src:find("twist_mana_threshold_pct") ~= nil,
        "MANA: the widget source exists (consumer at classes/paladin.lua:3281)")

    -- (b) Hard-wait: no widget, no default (render filed, not guessed).
    do
        local hsb, herr = build("Paladin")
        check(hsb ~= nil, "HARDWAIT: the paladin options tree builds"
            .. (hsb and "" or (": " .. tostring(herr))))
        if hsb then
            local args = hsb.ST.opts_table.args.class
                and hsb.ST.opts_table.args.class.args or {}
            check(args.hard_wait == nil,
                "HARDWAIT: no hard_wait widget ships (render filed at nextaction_ui)")
            check(args.strict_sequence == nil,
                "HARDWAIT: no strict_sequence widget ships (engine input only)")
        end
        check(no_default_line(pblock, "hard_wait"),
            "HARDWAIT: no hard_wait default ships")
        check(no_default_line(pblock, "strict_sequence"),
            "HARDWAIT: no strict_sequence default ships")
    end

    -- (c) Shaman F7: the dedicated hold/SR/ES keys stay unwired; the six live
    -- opt-ins keep their widgets (section 6) and nil-off defaults.
    do
        local ssb, serr = build("Shaman")
        check(ssb ~= nil, "SHAMAN-F7: the shaman options tree builds"
            .. (ssb and "" or (": " .. tostring(serr))))
        if ssb then
            local args = ssb.ST.opts_table.args.class
                and ssb.ST.opts_table.args.class.args or {}
            check(type(args.show_shaman_wf_hold_tint) == "table"
                    and args.show_shaman_wf_hold_tint.type == "toggle",
                "SHAMAN-F7: the live hold opt-in keeps its toggle (tint reuse)")
            for key in pairs(args) do
                local is_hold = key ~= "show_shaman_wf_hold_tint" and key:find("hold")
                check(not is_hold,
                    "SHAMAN-F7: no dedicated hold widget ships (got '" .. key .. "')")
                local is_dedicated = key:find("mana_pause") or key:find("sr_threshold")
                    or key:find("es_floor") or key:find("stormstrike_hold")
                check(not is_dedicated,
                    "SHAMAN-F7: no dedicated SR/ES widget ships (got '" .. key .. "')")
            end
        end
        local sblock = defaults_block_13("SHAMAN")
        check(sblock ~= "", "SHAMAN-F7: the SHAMAN defaults block is found")
        for _, key in ipairs({ "stormstrike_hold", "mana_pause",
            "sr_threshold", "es_floor" }) do
            check(sblock:find(key, 1, true) == nil,
                "SHAMAN-F7: no '" .. key .. "' default ships (correctly unwired)")
        end
    end

    -- (d) Druid RipCP WIRED: the gather feeds db.guide_rip_min_cp raw
    -- (classes/druid.lua:1707); the engine clamps 2-5 and defaults nil to
    -- RIP_MIN_CP_TBC = 4 (druid_guide.lua:515-520). The widget is the
    -- guide_rip_refresh shape (range + generic getter/setter); the shipped
    -- 4 renders the archived behaviour (nil reads 4 engine-side).
    do
        local dsb, derr = build("Druid")
        check(dsb ~= nil, "RIPCP: the druid options tree builds"
            .. (dsb and "" or (": " .. tostring(derr))))
        if dsb then
            local panel = dsb.ST.opts_table.args.class
            local args = panel and panel.args or {}
            local handler = panel and panel.handler
            local w = args.guide_rip_min_cp
            check(type(w) == "table" and w.type == "range",
                "RIPCP: guide_rip_min_cp is a range widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                check(w.min == 2 and w.max == 5 and w.step == 1,
                    "RIPCP: the range spans 2-5 step 1 (filed shape)")
                check(w.order == 7.96,
                    "RIPCP: the widget sits at order 7.96 (after rake 7.959, got "
                    .. tostring(w.order) .. ")")
                local get_ok = (type(w.get) == "string" and type(handler) == "table"
                    and type(handler[w.get]) == "function") or type(w.get) == "function"
                check(get_ok,
                    "RIPCP: the getter resolves (generic, like guide_rip_refresh)")
                local set_ok = (type(w.set) == "string" and type(handler) == "table"
                    and type(handler[w.set]) == "function") or type(w.set) == "function"
                check(set_ok,
                    "RIPCP: the setter resolves (generic, like guide_rip_refresh)")
                local rr, rk = args.guide_rip_refresh, args.guide_rake_refresh
                check(type(rr) == "table" and rr.order ~= w.order
                        and type(rk) == "table" and rk.order ~= w.order,
                    "RIPCP: no order collision with the refresh windows")
            end
        end
        local dblock = defaults_block_13("DRUID")
        check(dblock ~= "", "RIPCP: the DRUID defaults block is found")
        check(dblock:match("\n%s*guide_rip_min_cp%s*=%s*4") ~= nil,
            "RIPCP: guide_rip_min_cp ships 4 (archived = engine default 4)")
        check(tables_src:find("guide_rip_min_cp", 1, true) ~= nil,
            "RIPCP: the widget source exists (consumer at classes/druid.lua:1707)")
    end
end

--=========================================================================================
-- 14) Settings-audit build pins (bench/settings_audit_2026-10-19.md)
--=========================================================================================
-- Every audit row is either built here or filed with reason. Filed (NOT built,
-- must stay absent): P-M2 HS/AM HUD widgets, W-M1 hamstring toggle, H-M2
-- guide-only HUD toggles (chimera/explosive/arcane/kill_shot/sniper/hawk).
-- WIRED: R-M1 kidney/restealth/bandage widgets + D-1 claw widget (live
-- consumers cited below). Copy/order only: no default-visible change, no new
-- widgets beyond the audit/parity spec.
do
    local function read_source_14(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end
    local tables_src = read_source_14("option_tables.lua")

    -- D-C1 REAL BUG: maul desc names Maul, never Heroic Strike; name qualified.
    check(tables_src:find('desc="Color to use when Maul is queued."', 1, true) ~= nil,
        "AUDIT D-C1: the maul desc names Maul")
    check(tables_src:find('desc="Color to use when Heroic Strike is queued."', 1, true) == nil
        or tables_src:find('name="Heroic Strike color"', 1, true) ~= nil,
        "AUDIT D-C1: no stray Heroic Strike desc outside the warrior color")
    do
        local msb, merr = build("Druid")
        check(msb ~= nil, "AUDIT D-C1: the druid tree builds"
            .. (msb and "" or (": " .. tostring(merr))))
        if msb then
            local args = msb.ST.opts_table.args.class.args or {}
            check(type(args.maul_color) == "table" and args.maul_color.name == "Maul color",
                "AUDIT D-C1: maul_color is named Maul color")
            check(type(args.enable_maul_color) == "table"
                and args.enable_maul_color.name == "Enable Maul color",
                "AUDIT D-C2: the maul toggle casing is fixed")
        end
    end

    -- X1: bare Enables qualified; the six NAG masters stay bare Enable.
    for _, spec in ipairs({
        { key = "use_seal_colors", want = "Enable seal colors" },
        { key = "use_aow_glow", want = "Enable Art of War glow" },
        { key = "use_bloodsurge_glow", want = "Enable Bloodsurge glow" },
        { key = "enable_raptor_strike_color", want = "Enable Raptor Strike color" },
        { key = "enable_steady_shot_color", want = "Enable Steady Shot color" },
        { key = "hunter_cast_bar_enabled", want = "Enable cast bar" },
        { key = "hunter_target_warning_enabled", want = "Enable target warning" },
        { key = "hunter_range_helper_enabled", want = "Enable range helper" },
        { key = "hunter_rapid_fire_bar_enabled", want = "Enable Rapid Fire bar" },
        { key = "hunter_aspect_icon_enabled", want = "Enable aspect icon" },
        { key = "use_form_colors", want = "Enable form colors" },
        { key = "weave_enabled", want = "Enable spell weaving" },
    }) do
        check(tables_src:find('name = "' .. spec.want .. '"', 1, true) ~= nil,
            "AUDIT X1: " .. spec.key .. " reads '" .. spec.want .. "'")
    end
    for _, pretty in ipairs({ "Paladin", "Warrior", "Hunter", "Shaman", "Druid", "Rogue" }) do
        local sb, err = build(pretty)
        check(sb ~= nil, "AUDIT X1: the " .. pretty .. " tree builds"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            local args = sb.ST.opts_table.args.class.args or {}
            local w = args.nextaction_enabled
            check(type(w) == "table" and w.name == "Enable",
                "AUDIT X1: " .. pretty .. " NAG master stays bare Enable")
        end
    end

    -- X2: bare Colors qualified (incl. the shared label color).
    for _, spec in ipairs({
        { key = "hs_color", want = "Heroic Strike color" },
        { key = "cleave_color", want = "Cleave color" },
        { key = "raptor_strike_color", want = "Raptor Strike color" },
        { key = "steady_shot_color", want = "Steady Shot color" },
        { key = "hunter_cast_bar_color", want = "Cast bar color" },
        { key = "aow_glow_color", want = "Art of War glow color" },
        { key = "maul_color", want = "Maul color" },
    }) do
        check(tables_src:find('name="' .. spec.want .. '"', 1, true) ~= nil
            or tables_src:find('name = "' .. spec.want .. '"', 1, true) ~= nil,
            "AUDIT X2: " .. spec.key .. " reads '" .. spec.want .. "'")
    end
    do
        local psb = build("Paladin")
        check(psb ~= nil, "AUDIT X2: the paladin tree builds for the label pin")
        if psb then
            local args = psb.ST.opts_table.args.class.args or {}
            local found_label = false
            for _, w in pairs(args) do
                if type(w) == "table" and w.type == "color" and w.name == "Label color" then
                    found_label = true
                end
                if type(w) == "table" and w.type == "color" and w.name == "Color" then
                    found_label = false
                    break
                end
            end
            check(found_label, "AUDIT X2: no bare Color remains (label reads Label color)")
        end
    end

    -- X3/X5: frame locks + visibility qualified.
    check(tables_src:find('name = "Lock HUD frame"', 1, true) ~= nil,
        "AUDIT X3: HUD locks read Lock HUD frame")
    check(tables_src:find('name = "Lock guide frame"', 1, true) ~= nil,
        "AUDIT X3: guide locks read Lock guide frame")
    check(tables_src:find('name = "Lock label frame"', 1, true) ~= nil,
        "AUDIT X3: label locks read Lock label frame")
    check(tables_src:find('name = "Lock frame"', 1, true) == nil,
        "AUDIT X3: no bare Lock frame remains")
    check(tables_src:find('name = "Show label"', 1, true) ~= nil,
        "AUDIT X5: rotation visibility reads Show label")
    check(tables_src:find('name = "Show text"', 1, true) == nil,
        "AUDIT X5: no bare Show text remains")

    -- X4: per-class format values (keys unchanged, display class-relevant).
    do
        local wants = {
            Paladin = "CS, Twist, Twist",
            Warrior = "OP, Execute, Slam",
            Hunter = "Steady, Auto, Steady",
            Druid = "Mangle, Rip, Rake",
            Shaman = "SS, FS, LB",
            Rogue = "SS, Rupture, Eviscerate",
        }
        for pretty, steps in pairs(wants) do
            local sb, err = build(pretty)
            check(sb ~= nil, "AUDIT X4: the " .. pretty .. " tree builds"
                .. (sb and "" or (": " .. tostring(err))))
            if sb then
                local args = sb.ST.opts_table.args.class.args or {}
                local w = args.rotation_label_format
                check(type(w) == "table" and type(w.values) == "table",
                    "AUDIT X4: " .. pretty .. " format carries values")
                if type(w) == "table" and type(w.values) == "table" then
                    check(w.values.steps == steps,
                        "AUDIT X4: " .. pretty .. " steps read '" .. steps
                        .. "' (got '" .. tostring(w.values.steps) .. "')")
                    check(w.values.key ~= nil and w.values.labelled ~= nil
                        and w.values.both ~= nil,
                        "AUDIT X4: " .. pretty .. " keeps the four format keys")
                end
            end
        end
    end

    -- Paladin copy + order.
    check(tables_src:find('name = "Twist attempt flash"', 1, true) ~= nil,
        "AUDIT P-C1: the twist flash is renamed")
    check(tables_src:find('name="Twist armed color"', 1, true) ~= nil,
        "AUDIT P-C2: the armed color is renamed")
    check(tables_src:find('name="Twist impossible color"', 1, true) ~= nil,
        "AUDIT P-C3: the impossible color is renamed")
    check(tables_src:find('name = "Impossible-twist warning"', 1, true) ~= nil,
        "AUDIT P-C4: the lag warning is renamed")
    check(tables_src:find("Fixed uses the offset below; None disables the padding.", 1, true) ~= nil,
        "AUDIT P-C5: the padding desc names all three modes")
    check(tables_src:find('name = "Show frame title"', 1, true) ~= nil,
        "AUDIT P-C6: the frame title is renamed")
    check(tables_src:find("Only weapon speed, result styling and panel position ship as options", 1, true) ~= nil,
        "AUDIT P-C7: the practice desc names the shipped subset")
    do
        local psb = build("Paladin")
        if psb then
            local args = psb.ST.opts_table.args.class.args or {}
            local fb, gl = args.twist_feedback_enabled, args.twist_success_glow_enabled
            check(type(fb) == "table" and type(fb.disabled) == "function"
                and fb.disabled(),
                "AUDIT P-O1: the attempt flash gates on twist_enabled")
            check(type(gl) == "table" and type(gl.disabled) == "function"
                and gl.disabled(),
                "AUDIT P-O1: the success glow gates on twist_enabled")
            check(type(args.seal_tracker_header) == "table"
                and args.seal_tracker_header.order == 3.984,
                "AUDIT P-O2: the seal tracker header sits at 3.984")
            check(type(args.mana_header) == "table" and args.mana_header.order == 3.46,
                "AUDIT P-O3: the mana header sits at 3.46")
            check(type(args.twist_mana_threshold_pct) == "table"
                and args.twist_mana_threshold_pct.order == 3.47,
                "AUDIT P-O3: the mana governor sits at 3.47")
        end
    end

    -- Warrior copy + order.
    check(tables_src:find('name="Queued-but-unaffordable color"', 1, true) ~= nil,
        "AUDIT W-C2: the rage color is renamed")
    check(tables_src:find('name = "Queued-ability BANK cue"', 1, true) ~= nil,
        "AUDIT W-C3: the BANK cue is renamed")
    check(tables_src:find('name = "Offhand desync spark"', 1, true) ~= nil,
        "AUDIT W-C4: the desync spark is renamed")
    check(tables_src:find("Talent detection is a heuristic; verify in-client.", 1, true) ~= nil,
        "AUDIT W-C5: the talent caveat ships")
    do
        local wsb = build("Warrior")
        if wsb then
            local args = wsb.ST.opts_table.args.class.args or {}
            check(type(args.warrior_demo_shout_bar_color) == "table"
                and args.warrior_demo_shout_bar_color.order == 3.19,
                "AUDIT W-O1: the demo color sits at 3.19 (collision gone)")
            check(type(args.show_warrior_deep_wounds_bar) == "table"
                and args.show_warrior_deep_wounds_bar.order == 3.10,
                "AUDIT W-O1: the band opens at 3.10")
            check(type(args.guide_execute_pct) == "table"
                and args.guide_execute_pct.order == 4.131,
                "AUDIT W-O2: the execute threshold sits at 4.131")
        end
    end

    -- Hunter copy + order.
    check(tables_src:find("not wired yet", 1, true) ~= nil,
        "AUDIT H-C1: the multi-target name owns the unwired state")
    check(tables_src:find("tint green while stopping is safe", 1, true) ~= nil,
        "AUDIT H-C2: the cast tint desc drops the jargon")
    check(tables_src:find('name = "Steady Shot proc tint (ISS)"', 1, true) ~= nil,
        "AUDIT H-C3: the ISS badge is renamed")
    check(tables_src:find('name = "Low-mana Viper badge (OOM)"', 1, true) ~= nil,
        "AUDIT H-C4: the OOM badge is renamed")
    check(tables_src:find('name = "Trap-proc badge (Lock and Load)"', 1, true) ~= nil,
        "AUDIT H-C5: the LnL badge is renamed")
    check(tables_src:find('name = "Readiness double-Rapid Fire window"', 1, true) ~= nil,
        "AUDIT H-C6: the readiness window is renamed")
    check(tables_src:find("Works without the cast bar.", 1, true) ~= nil,
        "AUDIT H-O3: the cast zone owns its independence")
    do
        local hsb = build("Hunter")
        if hsb then
            local args = hsb.ST.opts_table.args.class.args or {}
            check(type(args.hunter_multi_target) == "table"
                and args.hunter_multi_target.order == 7.101,
                "AUDIT H-O1: multi-target sits at 7.101")
            check(type(args.shot_report_header) == "table"
                and args.shot_report_header.order == 7.5,
                "AUDIT H-O2: the shot report header sits at 7.5")
            check(type(args.hunter_shot_report) == "table"
                and args.hunter_shot_report.order == 7.52,
                "AUDIT H-O2: the shot report button sits at 7.52")
        end
    end

    -- Shaman copy + order.
    check(tables_src:find('name = "Dual-wield sync / Flurry readout"', 1, true) ~= nil,
        "AUDIT S-C1: the DW readout is expanded")
    check(tables_src:find('name = "Stormstrike + Shamanistic Rage badges"', 1, true) ~= nil,
        "AUDIT S-C3: the cooldown badges name both")
    check(tables_src:find('name = "Safe-cast position row"', 1, true) ~= nil,
        "AUDIT S-C4: the spell row is renamed")
    check(tables_src:find("Count Maelstrom Weapon stacks toward the cast time", 1, true) ~= nil,
        "AUDIT S-C5: the MW desc names the action")
    check(tables_src:find("Trinket internal cooldowns stay on the", 1, true) == nil,
        "AUDIT S-C2: the lust tail no longer answers the trinket question")
    do
        local ssb = build("Shaman")
        if ssb then
            local args = ssb.ST.opts_table.args.class.args or {}
            check(type(args.show_shaman_stormstrike_bar) == "table"
                and args.show_shaman_stormstrike_bar.order == 2.31,
                "AUDIT S-O1: the Stormstrike bar sits at 2.31")
            check(type(args.badges_header) == "table"
                and args.badges_header.order == 2.65,
                "AUDIT S-O1: the badge header sits at 2.65")
            check(type(args.guide_flameshock_refresh) == "table"
                and args.guide_flameshock_refresh.order == 3.101,
                "AUDIT S-O2: the Flame Shock threshold sits at 3.101")
        end
    end

    -- Druid order + spacers.
    do
        local dsb = build("Druid")
        if dsb then
            local args = dsb.ST.opts_table.args.class.args or {}
            check(type(args.class_header) == "table" and args.class_header.order == 6.0,
                "AUDIT D-O1: maul opens at 6.0")
            check(type(args.rage_desc) == "table" and args.rage_desc.order == 6.51,
                "AUDIT D-O1: rage sits at 6.51")
            check(type(args.trackers_header) == "table" and args.trackers_header.order == 7.0,
                "AUDIT D-O1: trackers open at 7.0")
            check(type(args.nag_header) == "table" and args.nag_header.order == 7.95,
                "AUDIT D-O1: the guide opens at 7.95")
            local hud = args.hud_header
            check(type(hud) == "table" and hud.order == 8.0,
                "AUDIT D-O1: the HUD still opens at 8.0 (after the guide)")
            check(type(args.show_druid_pips) == "table"
                and args.show_druid_pips.name == "Combo-point pips",
                "AUDIT D-C3: the pips are renamed")
            check(type(args.show_druid_maul_badge) == "table"
                and args.show_druid_maul_badge.name == "Rage-cap Maul badge",
                "AUDIT D-C4: the maul badge is renamed")
            check(type(args.show_druid_ttd_readout) == "table"
                and args.show_druid_ttd_readout.name == "Target time-to-die readout",
                "AUDIT D-C5: the TTD readout is renamed")
        end
    end
    check(tables_src:find("lb02", 1, true) == nil,
        "AUDIT D-O2: the druid spacer is gone")
    check(tables_src:find("\n        lb0 = {", 1, true) == nil
        and tables_src:find("\n        lb1 = {", 1, true) == nil
        and tables_src:find("\n        lb2 = {", 1, true) == nil
        and tables_src:find("\n        lb02 = {", 1, true) == nil,
        "AUDIT D-O2/W-O2: no active spacer widget remains")

    -- Rogue copy + order (R-C4 kept by designer call: long but accurate).
    check(tables_src:find("Pool: don\'t spend below (pre-tick)", 1, true) ~= nil,
        "AUDIT R-C1: the pre-tick band names the action")
    check(tables_src:find("Pool: don\'t spend below (post-tick)", 1, true) ~= nil,
        "AUDIT R-C1: the post-tick band names the action")
    check(tables_src:find('name = "Thistle Tea drink-at energy"', 1, true) ~= nil,
        "AUDIT R-C2: the tea threshold is renamed")
    check(tables_src:find('name = "Rupture skip-if-dying-within (s)"', 1, true) ~= nil,
        "AUDIT R-C3: the rupture skip names the semantics")
    check(tables_src:find("the guide never suggests Expose Armor while off", 1, true) ~= nil,
        "AUDIT R-C5: the duty desc states the off-behavior")
    do
        local rsb = build("Rogue")
        if rsb then
            local args = rsb.ST.opts_table.args.class.args or {}
            check(type(args.rogue_ea_duty) == "table"
                and args.rogue_ea_duty.order == 2.03,
                "AUDIT R-O1: the duty toggle sits at 2.03")
        end
    end

    -- Filed decisions stay filed (no widgets, no defaults); wired decisions
    -- carry their widget pins (P-M2 paladin mirror slots + W-M1 warrior
    -- hamstring/sunder, both landed hud-styles-build 2026-10-19).
    do
        -- WIRED P-M2 (bench/paladin_styles_2026-10-19.md §0): the SoD/shockadin
        -- mirror slot toggles. Consumers: classes/paladin.lua:3396-3409
        -- HUD_SLOTS + :3657-3774 provider (unknown-hide). Defaults ship true
        -- (pinned hud_state §12 + hud_templates_state §2); the HUD master stays
        -- off, so nothing surfaces until enabled.
        local psb = build("Paladin")
        if psb then
            local args = psb.ST.opts_table.args.class.args or {}
            local handler = psb.ST.opts_table.args.class.handler
            local want_order = { hud_show_soc = 8.48, hud_show_sob = 8.49,
                hud_show_how = 8.50, hud_show_holy_shock = 8.51,
                hud_show_aura_mastery = 8.52 }
            for key, order in pairs(want_order) do
                local w = args[key]
                check(type(w) == "table" and w.type == "toggle",
                    "WIRED P-M2: " .. key .. " has a toggle widget (got "
                    .. tostring(type(w) == "table" and w.type or nil) .. ")")
                if type(w) == "table" then
                    check(w.order == order,
                        "WIRED P-M2: " .. key .. " sits at " .. order)
                    local getter = type(w.get) == "function" and w.get
                        or (type(w.get) == "string" and type(handler) == "table"
                            and handler[w.get]) or nil
                    local setter = type(w.set) == "function" and w.set
                        or (type(w.set) == "string" and type(handler) == "table"
                            and handler[w.set]) or nil
                    check(type(getter) == "function",
                        "WIRED P-M2: " .. key .. "'s get resolves")
                    check(type(setter) == "function",
                        "WIRED P-M2: " .. key .. "'s set resolves")
                end
            end
        end
        -- WIRED P-BAND (the WotLK APL's utility band): the two display-only
        -- mirrors (Hand of Reckoning 67485, the WotLK Hammer of Wrath 48806).
        -- Consumers: classes/paladin.lua's HUD_SLOTS descriptors + the provider
        -- gate in get_hud_state, which reads hud_show_<key> == true (nil = off).
        -- The defaults ship FALSE (the druid Claw shape: the mirror is hidden
        -- until the player turns it on - no default-visible change), and the
        -- panel is the only way to turn it on.
        local bsb = build("Paladin")
        if bsb then
            local args = bsb.ST.opts_table.args.class.args or {}
            local handler = bsb.ST.opts_table.args.class.handler
            local band_order = { hud_show_hor = 8.53, hud_show_how_wrath = 8.54 }
            for key, order in pairs(band_order) do
                local w = args[key]
                check(type(w) == "table" and w.type == "toggle",
                    "WIRED P-BAND: " .. key .. " has a toggle widget (got "
                    .. tostring(type(w) == "table" and w.type or nil) .. ")")
                if type(w) == "table" then
                    check(w.order == order,
                        "WIRED P-BAND: " .. key .. " sits at " .. order)
                    local getter = type(w.get) == "function" and w.get
                        or (type(w.get) == "string" and type(handler) == "table"
                            and handler[w.get]) or nil
                    local setter = type(w.set) == "function" and w.set
                        or (type(w.set) == "string" and type(handler) == "table"
                            and handler[w.set]) or nil
                    check(type(getter) == "function",
                        "WIRED P-BAND: " .. key .. "'s get resolves")
                    check(type(setter) == "function",
                        "WIRED P-BAND: " .. key .. "'s set resolves")
                    -- The toggle is nil-safe: an unset key reads nil (the
                    -- sandbox's fresh profile) and the provider treats nil as
                    -- off - the shipped default is false (pinned below), and
                    -- both hide.
                    check(getter ~= nil and getter(nil, { key }) == nil,
                        "WIRED P-BAND: " .. key .. " reads nil when the key is unset")
                end
            end
            -- The defaults: false, never true (the display-only shape).
            local pblock = read_source_14("config_presets.lua"):match(
                "ST%.PALADIN%.defaults%s*=%s*{(.-)\n%}") or ""
            check(pblock ~= "", "WIRED P-BAND: the PALADIN defaults block is found")
            for _, key in ipairs({ "hud_show_hor", "hud_show_how_wrath" }) do
                check(pblock:find("%f[%a_]" .. key .. "%s*=%s*false") ~= nil,
                    "WIRED P-BAND: " .. key .. " ships false in the PALADIN defaults")
                check(pblock:find("%f[%a_]" .. key .. "%s*=%s*true") == nil,
                    "WIRED P-BAND: " .. key .. " ships no true default")
            end
            -- The consumer reads the key (the option gate is what hides the
            -- slot until the player turns it on).
            local psrc_band = read_source_14("classes/paladin.lua")
            check(psrc_band:find("hud_show_", 1, true) ~= nil,
                "WIRED P-BAND: the paladin provider reads the hud_show_ keys")
        end
        -- WIRED W-M1 (closes designer-templates G1 + the sunder union gap):
        -- hamstring + sunder slot toggles. Consumers: classes/warrior.lua
        -- HUD_SLOTS descriptors + generic name-based provider. Defaults ship
        -- true (pinned hud_templates_state §2 + §4 below).
        local wsb = build("Warrior")
        if wsb then
            local args = wsb.ST.opts_table.args.class.args or {}
            local handler = wsb.ST.opts_table.args.class.handler
            local prev_order = 0
            for _, key in ipairs({ "hud_show_hamstring", "hud_show_sunder",
                "hud_show_trinket1", "hud_show_trinket2" }) do
                local w = args[key]
                check(type(w) == "table" and w.type == "toggle",
                    "WIRED W-M1: " .. key .. " has a toggle widget (got "
                    .. tostring(type(w) == "table" and w.type or nil) .. ")")
                if type(w) == "table" then
                    check(type(w.order) == "number",
                        "WIRED W-M1: " .. key .. " carries a numeric order")
                    check(w.order > prev_order,
                        "WIRED W-M1: " .. key .. " keeps panel order")
                    prev_order = w.order
                    local getter = type(w.get) == "function" and w.get
                        or (type(w.get) == "string" and type(handler) == "table"
                            and handler[w.get]) or nil
                    local setter = type(w.set) == "function" and w.set
                        or (type(w.set) == "string" and type(handler) == "table"
                            and handler[w.set]) or nil
                    check(type(getter) == "function",
                        "WIRED W-M1: " .. key .. "'s get resolves")
                    check(type(setter) == "function",
                        "WIRED W-M1: " .. key .. "'s set resolves")
                end
            end
        end
        local hsb = build("Hunter")
        if hsb then
            local args = hsb.ST.opts_table.args.class.args or {}
            for _, slot in ipairs({ "chimera", "explosive", "arcane",
                "kill_shot", "sniper", "hawk" }) do
                check(args["hud_show_" .. slot] == nil,
                    "FILED H-M2: no hud_show_" .. slot .. " ships")
            end
        end
        -- WIRED R-M1 (bench/settings_audit_2026-10-19.md R-M1): the three
        -- short-CD slot toggles. Consumers: classes/rogue.lua:442 shortcd_wanted
        -- (db["hud_show_" .. key] == true, nil = off) + :1047-1049 HUD_SLOTS +
        -- :1268-1332 provider. Defaults ship false = hidden (no default-visible
        -- change; R-T3 template turns them on).
        local rsb = build("Rogue")
        if rsb then
            local args = rsb.ST.opts_table.args.class.args or {}
            local handler = rsb.ST.opts_table.args.class.handler
            local rblock = read_source_14("config_presets.lua"):match(
                "ST%.ROGUE%.defaults%s*=%s*{(.-)\n%}") or ""
            local rsrc = read_source_14("classes/rogue.lua")
            check(rsrc:find("shortcd_wanted", 1, true) ~= nil,
                "R-M1: the shortcd_wanted consumer exists")
            for _, slot in ipairs({ "kidney", "restealth", "bandage" }) do
                local key = "hud_show_" .. slot
                local w = args[key]
                check(type(w) == "table" and w.type == "toggle",
                    "R-M1: " .. key .. " has a toggle widget (got "
                    .. tostring(type(w) == "table" and w.type or nil) .. ")")
                if type(w) == "table" then
                    check(type(w.order) == "number",
                        "R-M1: " .. key .. " carries a numeric order")
                    local getter = type(w.get) == "function" and w.get
                        or (type(w.get) == "string" and type(handler) == "table"
                            and handler[w.get]) or nil
                    local setter = type(w.set) == "function" and w.set
                        or (type(w.set) == "string" and type(handler) == "table"
                            and handler[w.set]) or nil
                    check(type(getter) == "function",
                        "R-M1: " .. key .. "'s get resolves")
                    check(type(setter) == "function",
                        "R-M1: " .. key .. "'s set resolves")
                    if type(getter) == "function" then
                        rsb.class_db[key] = true
                        check(getter(nil, { "class", key }) == true,
                            "R-M1: " .. key .. "'s getter reads the class key (true)")
                        rsb.class_db[key] = nil
                        check(not getter(nil, { "class", key }),
                            "R-M1: " .. key .. "'s getter reads the class key (nil = off)")
                    end
                    check(rsrc:find('key%s*=%s*"' .. slot .. '"') ~= nil,
                        "R-M1: the '" .. slot .. "' HUD_SLOTS descriptor exists")
                end
                check(rblock:find("%f[%a_]" .. key .. "%s*=%s*false") ~= nil,
                    "R-M1: " .. key .. " ships false (hidden, no default-visible change)")
                check(rblock:find("%f[%a_]" .. key .. "%s*=%s*true") == nil,
                    "R-M1: " .. key .. " ships no true default")
            end
        end
        -- WIRED D-1 (bench/hud_parity_2026-10-19.md D-1): the Claw slot toggle.
        -- Consumers: classes/druid.lua:1979 HUD_SLOTS + :2217-2222 provider
        -- (hud_show_claw == true shows, nil = off). Default ships false = hidden
        -- (no default-visible change).
        do
            local dsb = build("Druid")
            check(dsb ~= nil, "D-1: the druid options tree builds"
                .. (dsb and "" or ""))
            if dsb then
                local args = dsb.ST.opts_table.args.class.args or {}
                local handler = dsb.ST.opts_table.args.class.handler
                local w = args.hud_show_claw
                check(type(w) == "table" and w.type == "toggle",
                    "D-1: hud_show_claw has a toggle widget (got "
                    .. tostring(type(w) == "table" and w.type or nil) .. ")")
                if type(w) == "table" then
                    check(type(w.order) == "number",
                        "D-1: hud_show_claw carries a numeric order")
                    local getter = type(w.get) == "function" and w.get
                        or (type(w.get) == "string" and type(handler) == "table"
                            and handler[w.get]) or nil
                    local setter = type(w.set) == "function" and w.set
                        or (type(w.set) == "string" and type(handler) == "table"
                            and handler[w.set]) or nil
                    check(type(getter) == "function",
                        "D-1: hud_show_claw's get resolves")
                    check(type(setter) == "function",
                        "D-1: hud_show_claw's set resolves")
                    if type(getter) == "function" then
                        dsb.class_db.hud_show_claw = true
                        check(getter(nil, { "class", "hud_show_claw" }) == true,
                            "D-1: hud_show_claw's getter reads the class key (true)")
                        dsb.class_db.hud_show_claw = nil
                        check(not getter(nil, { "class", "hud_show_claw" }),
                            "D-1: hud_show_claw's getter reads the class key (nil = off)")
                    end
                end
                local dblock = read_source_14("config_presets.lua"):match(
                    "ST%.DRUID%.defaults%s*=%s*{(.-)\n%}") or ""
                check(dblock:find("%f[%a_]hud_show_claw%s*=%s*false") ~= nil,
                    "D-1: hud_show_claw ships false (hidden, no default-visible change)")
                check(dblock:find("%f[%a_]hud_show_claw%s*=%s*true") == nil,
                    "D-1: hud_show_claw ships no true default")
                local dsrc = read_source_14("classes/druid.lua")
                check(dsrc:find('key%s*=%s*"claw"') ~= nil,
                    "D-1: the 'claw' HUD_SLOTS descriptor exists")
                check(dsrc:find("hud_show_claw", 1, true) ~= nil,
                    "D-1: the hud_show_claw consumer exists")
            end
        end
    end
end


--=========================================================================================
-- 15) SoD shaman options reports: paladin-only Practice scoping + Design Mode
--    toggle hardening (bench/options_sod_fix_2026-10-19.md)
--=========================================================================================
-- (1) No Practice section on shaman is CORRECT, not a bug: the practice session
-- is the paladin twist sim (practice_ui.init runs only from ST.PALADIN.post_init;
-- classes/shaman.lua documents "No practice branch"). The shaman_weave scenario
-- in practice.lua is pure math with no practice_ui consumer, so there is nothing
-- to route a widget to (no inert toggles). Filed spec lives on the bench; these
-- pins lock the scoping so a future consumer forces the matching widget, and a
-- future widget forces the matching consumer.
-- (2) The Design Mode page builds unconditionally (all classes, all flavors), but
-- its dynamic-name toggle threw on a partially loaded designmode.lua (st.designmode
-- present without is_active/toggle): a throwing name blanks the page in AceConfig.
-- The widget is now callable-guarded; these pins lock the guard and the nil-safe
-- reads on a fresh shaman profile.
do
    local function read_source_15(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end

    -- (a) Practice scoping: shaman wired (Weave Practice), paladin wired, hunter report separate.
    local ssb, serr = build("Shaman")
    check(ssb ~= nil, "SODOPT: the shaman options tree builds"
        .. (ssb and "" or (": " .. tostring(serr))))
    if ssb then
        local args = ssb.ST.opts_table.args.class.args or {}
        check(type(args.practice_toggle) == "table" and args.practice_toggle.type == "execute",
            "SODOPT: shaman carries practice_toggle (Weave Practice page)")
        check(type(args.practice_weapon_speed) == "table" and args.practice_weapon_speed.type == "range",
            "SODOPT: shaman carries practice_weapon_speed")
        check(type(args.practice_reset_position) == "table" and args.practice_reset_position.type == "execute",
            "SODOPT: shaman carries practice_reset_position")
        check(args.hunter_shot_report == nil,
            "SODOPT: shaman carries no hunter_shot_report (hunter log only)")
        local group = ssb.ST.opts_table.args.design_mode
        check(type(group) == "table" and group.type == "group",
            "SODOPT: the Design Mode group builds on shaman")
        if type(group) == "table" then
            local want = {
                design_desc = "description", design_toggle = "execute",
                design_grid_enabled = "toggle", design_grid = "range",
                design_snap = "toggle", design_snap_threshold = "range",
                design_mouse_anchor = "toggle", design_note = "description",
                hud_header = "header", hud_desc = "description",
                hud_template = "select", hud_orientation = "select",
                hud_icon_size = "range", hud_spacing = "range",
                hud_match_bar_width = "toggle", hud_scale = "range",
                hud_zoom = "toggle",
            }
            local n = 0
            for _ in pairs(group.args or {}) do n = n + 1 end
            check(n == 17, "SODOPT: the Design Mode group carries 17 widgets (got "
                .. n .. ")")
            for key, wtype in pairs(want) do
                local w = (group.args or {})[key]
                check(type(w) == "table" and w.type == wtype,
                    "SODOPT: Design Mode widget " .. key .. " is " .. wtype
                    .. " (got " .. tostring(type(w) == "table" and w.type or nil)
                    .. ")")
            end
        end
    end
    local psb = build("Paladin")
    check(psb ~= nil, "SODOPT: the paladin options tree builds")
    if psb then
        local pargs = psb.ST.opts_table.args.class.args or {}
        check(type(pargs.practice_toggle) == "table"
            and pargs.practice_toggle.type == "execute",
            "SODOPT: paladin keeps its practice_toggle (the wired session)")
    end

    -- (b) The shaman weave drill has a UI caller: the Weave Practice page routes
    -- through the shared session, so the widgets are correctly wired (not a gap).
    local pui_src = read_source_15("practice_ui.lua")
    check(pui_src:lower():find("shaman") ~= nil,
        "SODOPT: practice_ui.lua names a shaman consumer")
    check(pui_src:lower():find("weave") ~= nil,
        "SODOPT: practice_ui.lua names a weave consumer")
    local pal_src = read_source_15("classes/paladin.lua")
    check(pal_src:find("practice_ui.init", 1, true) ~= nil,
        "SODOPT: ST.PALADIN.post_init builds the practice session")
    local sham_src = read_source_15("classes/shaman.lua")
    check(sham_src:find("practice_ui.init", 1, true) ~= nil,
        "SODOPT: ST.SHAMAN.post_init builds the practice session")
    check(sham_src:find("Twist Practice is paladin-only", 1, true) ~= nil,
        "SODOPT: shaman documents the paladin-only practice branch")

    -- (c) design_toggle hardening: callable guards + nil-safe behaviour.
    local tables_src = read_source_15("option_tables.lua")
    check(tables_src:find('type(st.designmode.is_active) == "function"', 1, true) ~= nil,
        "SODOPT: design_toggle guards is_active with a callable check")
    check(tables_src:find('type(st.designmode.toggle) == "function"', 1, true) ~= nil,
        "SODOPT: design_toggle guards toggle with a callable check")
    if ssb then
        local w = ssb.ST.opts_table.args.design_mode
            and ssb.ST.opts_table.args.design_mode.args.design_toggle
        check(type(w) == "table" and type(w.name) == "function"
            and type(w.func) == "function",
            "SODOPT: design_toggle carries a dynamic name and a func")
        if type(w) == "table" and type(w.name) == "function" then
            ssb.st.designmode = nil
            local ok1, name1 = pcall(w.name)
            check(ok1 and name1 == "Start Design Mode",
                "SODOPT: the name offers Start with no designmode loaded")
            local okf1 = pcall(w.func)
            check(okf1, "SODOPT: the func no-ops with no designmode loaded")
            ssb.st.designmode = {}
            local ok2, name2 = pcall(w.name)
            check(ok2 and name2 == "Start Design Mode",
                "SODOPT: the name offers Start on a hollow designmode (was a throw)")
            local okf2 = pcall(w.func)
            check(okf2, "SODOPT: the func no-ops on a hollow designmode (was a throw)")
            ssb.st.designmode = { is_active = function() return false end,
                toggle = function() end }
            local ok3, name3 = pcall(w.name)
            check(ok3 and name3 == "Start Design Mode",
                "SODOPT: the name offers Start while the session is inactive")
            ssb.st.designmode = { is_active = function() return true end,
                toggle = function() end }
            local ok4, name4 = pcall(w.name)
            check(ok4 and name4 == "Stop Design Mode",
                "SODOPT: the name offers Stop while the session is active")
            local calls = 0
            ssb.st.designmode = { toggle = function() calls = calls + 1 end }
            local okf3 = pcall(w.func)
            check(okf3 and calls == 1,
                "SODOPT: the func routes into designmode.toggle")
        end
        -- Fresh shaman profile reads: grid on at 24, snap on at 8, mouse anchor off.
        local g = ssb.ST.opts_table.args.design_mode.args
        ssb.st.designmode = nil
        ssb.class_db.design_grid_enabled = nil
        ssb.class_db.design_grid = nil
        ssb.class_db.design_snap = nil
        ssb.class_db.design_snap_threshold = nil
        ssb.class_db.design_mouse_anchor = nil
        check(g.design_grid_enabled.get() == true,
            "SODOPT: grid defaults on (nil = on)")
        check(g.design_grid.get() == 24,
            "SODOPT: grid step defaults to 24")
        check(g.design_grid.disabled() == false,
            "SODOPT: grid step enabled while grid is on")
        check(g.design_snap.get() == true,
            "SODOPT: snap defaults on (nil = on)")
        check(g.design_snap_threshold.get() == 8,
            "SODOPT: snap threshold defaults to 8")
        check(g.design_mouse_anchor.get() ~= true,
            "SODOPT: mouse anchor defaults off (nil = off)")
    end
end


--=========================================================================================
-- 16) Practice toggle execution + top-level Practice fallbacks
--=========================================================================================
-- G3 (H7 callable-guard pins, warrior pattern): every class toggle's dynamic
-- name and func survive a missing or hollow practice_ui, and route into the
-- shared session when it is live. M4: the top-level Practice page enumerates
-- all six drills and its nil-unsafe gets fall back to the shipped defaults.
do
    local cases = {
        { class = "Paladin", key = "practice_toggle", label = "paladin" },
        { class = "Hunter", key = "hunter_practice_toggle", label = "hunter" },
        { class = "Druid", key = "druid_practice_toggle", label = "druid" },
        { class = "Shaman", key = "practice_toggle", label = "shaman" },
        { class = "Rogue", key = "practice_toggle", label = "rogue" },
        { class = "Warrior", key = "practice_toggle", label = "warrior" },
    }
    for _, case in ipairs(cases) do
        local sb = build(case.class)
        check(sb ~= nil, "G3: the " .. case.label .. " options tree builds")
        if sb then
            local args = sb.ST.opts_table.args.class.args or {}
            local w = args[case.key]
            check(type(w) == "table" and w.type == "execute",
                "G3: " .. case.label .. " carries " .. case.key)
            if type(w) == "table" then
                -- Missing module: the name offers Start, the func no-ops.
                sb.st.practice_ui = nil
                local ok1, name1 = pcall(w.name)
                check(ok1 and name1 == "Start Practice",
                    "G3: " .. case.label .. " name offers Start with no practice_ui")
                local okf1 = pcall(w.func)
                check(okf1, "G3: " .. case.label .. " func no-ops with no practice_ui")
                -- Hollow module: the same (a throw here blanked the page).
                sb.st.practice_ui = {}
                local ok2, name2 = pcall(w.name)
                check(ok2 and name2 == "Start Practice",
                    "G3: " .. case.label .. " name offers Start on a hollow practice_ui")
                local okf2 = pcall(w.func)
                check(okf2, "G3: " .. case.label .. " func no-ops on a hollow practice_ui")
                -- Live module: the name follows is_active, the func routes.
                local toggles = 0
                sb.st.practice_ui = {
                    is_active = function() return false end,
                    toggle = function() toggles = toggles + 1 end,
                }
                local ok3, name3 = pcall(w.name)
                check(ok3 and name3 == "Start Practice",
                    "G3: " .. case.label .. " name offers Start while inactive")
                local okf3 = pcall(w.func)
                check(okf3 and toggles == 1,
                    "G3: " .. case.label .. " func routes into practice_ui.toggle")
                sb.st.practice_ui = {
                    is_active = function() return true end,
                    toggle = function() end,
                }
                local ok4, name4 = pcall(w.name)
                check(ok4 and name4 == "Stop Practice",
                    "G3: " .. case.label .. " name offers Stop while active")
            end
        end
    end

    -- M4: the top-level page names every drill and reads nil-safe.
    local tb = build("Paladin")
    check(tb ~= nil, "M4: the paladin options tree builds")
    if tb then
        local pargs = tb.ST.opts_table.args.practice.args or {}
        local desc = pargs.practice_desc and pargs.practice_desc.name or ""
        for _, word in ipairs({ "paladin", "hunter", "shaman", "rogue", "druid", "warrior" }) do
            check(desc:lower():find(word, 1, true) ~= nil,
                "M4: the Practice desc enumerates the " .. word .. " drill")
        end
        check(pargs.practice_weapon_speed.get() == 0, "M4: weapon speed falls back to 0")
        check(pargs.practice_result_duration.get() == 0.8, "M4: result duration falls back to 0.8")
        check(pargs.practice_result_text_size.get() == 28, "M4: result text size falls back to 28")
    end
end

--=========================================================================================
-- 17) On-by-default package + Behaviour panel population (owner order 2026-10-19)
--=========================================================================================
-- (a) The guide + HUD ship ON: hud_enabled ships true in the shared class_defaults
-- (rotation_label_enabled still ships false), and nextaction_enabled ships true in
-- all six guide classes (PALADIN already did). Nil-safe: hud.should_show hides
-- on == false and apply_settings enables on ~= false; nextaction_ui.should_show
-- hides on == false — so nil reads as on, matching true. The five flipped guide
-- descs name the on-by-default state; the two profile behaviour keys stay false
-- in config.lua (untouched file, read-only pins here).
-- (b) The Behaviour panel is populated: timers_locked (class, inline lock/unlock),
-- enemy_swing_enabled + diag_tick_counters (profile, global handler) live under
-- opts_table.args.behaviour with no top-level copies left (moved, not copied);
-- welcome_message stays top-level (login text, not timer behaviour); per-hand
-- visibility stays in the hand panels (main.lua handle_bar_visibility reads the
-- per-hand db tables there — a global copy would orphan).
do
    local function read_source_17(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end
    local presets_src = read_source_17("config_presets.lua")
    local tables_src = read_source_17("option_tables.lua")
    local function defaults_block_17(token)
        if token == "class_defaults" then
            return presets_src:match("ST%.class_defaults%s*=%s*{(.-)\n%}") or ""
        end
        return presets_src:match("ST%." .. token .. "%.defaults%s*=%s*{(.-)\n%}") or ""
    end

    -- (a1) HUD master ships true; the label master still ships false.
    local shared = defaults_block_17("class_defaults")
    check(shared ~= "", "ONBYDEFAULT: the shared class_defaults block is found")
    check(shared:find("%f[%a_]hud_enabled%s*=%s*true") ~= nil,
        "ONBYDEFAULT: hud_enabled ships true (on-by-default package, owner order)")
    check(shared:find("%f[%a_]hud_enabled%s*=%s*false") == nil,
        "ONBYDEFAULT: hud_enabled ships no false default")
    check(shared:find("rotation_label_enabled%s*=%s*false") ~= nil,
        "ONBYDEFAULT: rotation_label_enabled still ships false (unchanged)")

    -- (a2) Every guide class ships nextaction_enabled true (PALADIN kept).
    for _, token in ipairs({ "DRUID", "HUNTER", "PALADIN", "ROGUE", "SHAMAN", "WARRIOR" }) do
        local block = defaults_block_17(token)
        check(block ~= "", "ONBYDEFAULT: the " .. token .. " defaults block is found")
        check(block:find("%f[%a_]nextaction_enabled%s*=%s*true") ~= nil,
            "ONBYDEFAULT: " .. token .. " nextaction_enabled ships true")
        check(block:find("%f[%a_]nextaction_enabled%s*=%s*false") == nil,
            "ONBYDEFAULT: " .. token .. " nextaction_enabled ships no false default")
    end

    -- (a3) The five flipped guide descs name the on-by-default state (no pin
    -- covered them; a revert to "(off by default)" fails here).
    local on_count = 0
    for _ in tables_src:gmatch("On%-screen rotation prompt %(on by default%)") do
        on_count = on_count + 1
    end
    check(on_count == 5, "ONBYDEFAULT: five guide descs read (on by default) (got "
        .. on_count .. ")")
    for _, frag in ipairs({
        "Overpower, Execute, Slam", "Steady Shot when the cast",
        "in bear %(Maul / Mangle%)", "Stormstrike, Flame Shock, or the weave",
        "the ability to press",
    }) do
        -- The descs span two concatenated literals, so match the frag then look
        -- back at the head of its literal for the on-by-default marker.
        local at = tables_src:find(frag)
        local head = (at ~= nil) and tables_src:sub(math.max(1, at - 200), at) or ""
        check(at ~= nil and head:find("On%-screen rotation prompt %(on by default%)", 1) ~= nil,
            "ONBYDEFAULT: the guide desc near '" .. frag .. "' reads on-by-default")
    end

    -- (b1) The Behaviour panel exists, is non-empty, and carries the three moves.
    local bsb = build("Shaman")
    check(bsb ~= nil, "ONBYDEFAULT: the shaman options tree builds for the Behaviour pins")
    if bsb then
        local bgroup = bsb.ST.opts_table.args.behaviour
        check(type(bgroup) == "table" and bgroup.type == "group",
            "ONBYDEFAULT: the Behaviour panel exists (got "
            .. tostring(type(bgroup) == "table" and bgroup.type or nil) .. ")")
        local bargs = bgroup and bgroup.args or {}
        local n, orders, dupes = 0, {}, 0
        for key, w in pairs(bargs) do
            if type(w) == "table" then
                n = n + 1
                if type(w.order) == "number" then
                    if orders[w.order] then dupes = dupes + 1 end
                    orders[w.order] = key
                end
            end
        end
        check(n >= 3, "ONBYDEFAULT: the Behaviour panel is populated (" .. n .. " widgets)")
        check(dupes == 0, "ONBYDEFAULT: Behaviour orders are unique (" .. dupes .. " duplicate(s))")
        local want = { timers_locked = "toggle", enemy_swing_enabled = "toggle",
            diag_tick_counters = "toggle" }
        local handler = (bgroup and bgroup.handler) or bsb.ST.opts_table.handler
        for key, wtype in pairs(want) do
            local w = bargs[key]
            check(type(w) == "table" and w.type == wtype,
                "ONBYDEFAULT: Behaviour carries " .. key .. " as a " .. wtype .. " (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                check(type(w.order) == "number",
                    "ONBYDEFAULT: " .. key .. " carries a numeric order")
                local getter = type(w.get) == "function" and w.get
                    or (type(w.get) == "string" and type(handler) == "table"
                        and handler[w.get]) or nil
                local setter = type(w.set) == "function" and w.set
                    or (type(w.set) == "string" and type(handler) == "table"
                        and handler[w.set]) or nil
                check(type(getter) == "function",
                    "ONBYDEFAULT: " .. key .. "'s get resolves")
                check(type(setter) == "function",
                    "ONBYDEFAULT: " .. key .. "'s set resolves")
            end
            check(bsb.ST.opts_table.args[key] == nil,
                "ONBYDEFAULT: " .. key .. " leaves no top-level copy (moved, not copied)")
        end
        -- welcome_message stays top-level (login text, not timer behaviour).
        local wel = bsb.ST.opts_table.args.welcome_message
        check(type(wel) == "table" and wel.type == "toggle",
            "ONBYDEFAULT: welcome_message stays top-level (got "
            .. tostring(type(wel) == "table" and wel.type or nil) .. ")")
        -- Per-hand visibility stays in the hand panels (per-hand db scope).
        local mh = bsb.ST.opts_table.args.mainhand
        check(type(mh) == "table" and type(mh.args) == "table"
                and type(mh.args.show_behaviour) == "table",
            "ONBYDEFAULT: show_behaviour stays in the mainhand panel (per-hand scope)")
        -- timers_locked keeps its live lock/unlock side effect through the move.
        local tw = bargs.timers_locked
        if type(tw) == "table" and type(tw.set) == "function" then
            local locked, unlocked = 0, 0
            bsb.ST.lock_frames = function() locked = locked + 1 end
            bsb.ST.unlock_frames = function() unlocked = unlocked + 1 end
            bsb.class_db.timers_locked = false
            tw.set(nil, true)
            check(locked == 1 and bsb.class_db.timers_locked == true,
                "ONBYDEFAULT: timers_locked set(true) locks the frames")
            tw.set(nil, false)
            check(unlocked == 1 and bsb.class_db.timers_locked == false,
                "ONBYDEFAULT: timers_locked set(false) unlocks the frames")
        else
            check(false, "ONBYDEFAULT: timers_locked carries an inline set (side-effect pin)")
        end
    end

    -- (b2) Each moved widget keeps its live consumer (source pins; the consumer
    -- files are out of this lane, so the pins cite file:line, not behaviour).
    local main_src = read_source_17("main.lua")
    check(main_src:find("db_class.timers_locked", 1, true) ~= nil,
        "ONBYDEFAULT: main.lua reads timers_locked (lock consumer cited)")
    check(main_src:find("handle_bar_visibility", 1, true) ~= nil,
        "ONBYDEFAULT: main.lua reads handle_bar_visibility (visibility consumer cited)")
    local diag_src = read_source_17("diag.lua")
    check(diag_src:find('diag_tick_counters") ~= true', 1, true) ~= nil,
        "ONBYDEFAULT: diag.lua gates on diag_tick_counters ~= true (consumer cited)")
    local es_src = read_source_17("enemy_swing.lua")
    check(es_src:find("enemy_swing_enabled == true", 1, true) ~= nil,
        "ONBYDEFAULT: enemy_swing.lua gates on enemy_swing_enabled == true (consumer cited)")
end

--=========================================================================================
-- 18) Shaman SoD hardening: callable guards + design_toggle trace (owner report)
--=========================================================================================
-- The field symptom (shaman SoD: HUD section not findable, design mode empty) is
-- the throwing-widget-blanks-the-page class this suite already pins twice
-- (SODOPT design_toggle, G3 practice toggles). This section extends the rule to
-- every remaining st.* method call the shaman panel + top-level groups can make:
-- each must be callable-guarded (type() == "function"), never bare-nil-guarded,
-- so a hollow module (table present, method missing) degrades to a no-op instead
-- of blanking the page. It then traces design_toggle -> designmode.toggle for a
-- shaman with no HUD frame and no practice panel (st.hud / st.practice_ui nil):
-- the toggle must still route (the overlays skip nil frames by registry design,
-- bars included — a missing HUD frame never aborts the toggle).
do
    local function read_source_18(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end
    local tables_src = read_source_18("option_tables.lua")

    -- (a) Source pins: no bare-nil-guarded st.* method call survives. Every
    -- remaining `if st.<mod> then st.<mod>.<fn>(...) end` shape fails here.
    check(tables_src:find("if st.designmode then", 1, true) == nil,
        "HARDEN: no bare-nil-guarded st.designmode call survives")
    check(tables_src:find("if st.rotation_text then", 1, true) == nil,
        "HARDEN: no bare-nil-guarded st.rotation_text call survives")
    check(tables_src:find('type(st.designmode.refresh_grid) == "function"', 1, true) ~= nil,
        "HARDEN: refresh_grid carries a callable guard")
    check(tables_src:find('type(st.rotation_text.set_align) == "function"', 1, true) ~= nil,
        "HARDEN: set_align carries a callable guard")
    -- The pre-existing guards stay (SODOPT + G3 + practice seams, not re-proved).
    for _, frag in ipairs({
        'type(st.designmode.is_active) == "function"',
        'type(st.designmode.toggle) == "function"',
        'type(st.practice_ui.toggle) == "function"',
        'type(st.practice_ui.apply_settings) == "function"',
        'type(st.practice_ui.update_result_font) == "function"',
    }) do
        check(tables_src:find(frag, 1, true) ~= nil,
            "HARDEN: the '" .. frag .. "' guard stays")
    end

    -- (b) Runtime pins: every display-time function on the shaman path pcall-survives
    -- hollow modules (each st.* a method-less table in turn, then all hollow at
    -- once) with a minimal db (nil keys exercise every nil-safe fallback).
    local hsb = build("Shaman")
    check(hsb ~= nil, "HARDEN: the shaman options tree builds")
    if hsb then
        -- Stub the class-side frame calls the moved timers_locked set needs.
        hsb.ST.lock_frames = function() end
        hsb.ST.unlock_frames = function() end
        local groups = {
            top = hsb.ST.opts_table.args,
            behaviour = (hsb.ST.opts_table.args.behaviour or {}).args or {},
            design = (hsb.ST.opts_table.args.design_mode or {}).args or {},
            practice = (hsb.ST.opts_table.args.practice or {}).args or {},
            class = ((hsb.ST.opts_table.args.class or {}).args or {}),
        }
        local hollow_each = {
            { designmode = {} }, { practice_ui = {} }, { rotation_text = {} },
            { designmode = {}, practice_ui = {}, rotation_text = {} },
        }
        for _, hollow in ipairs(hollow_each) do
            for mod in pairs({ designmode = 1, practice_ui = 1, rotation_text = 1 }) do
                hsb.st[mod] = hollow[mod]
            end
            local label = "{"
            for mod in pairs(hollow) do label = label .. mod .. "=hollow " end
            label = label .. "}"
            for gname, args in pairs(groups) do
                for key, w in pairs(args) do
                    if type(w) == "table" then
                        local wpath = gname .. "." .. key
                        if type(w.name) == "function" then
                            local ok, err = pcall(w.name)
                            check(ok, "HARDEN " .. label .. " " .. wpath
                                .. " name survives (err: " .. tostring(err) .. ")")
                        end
                        if type(w.get) == "function" then
                            local ok, err = pcall(w.get, nil, { "class", key })
                            check(ok, "HARDEN " .. label .. " " .. wpath
                                .. " get survives (err: " .. tostring(err) .. ")")
                        end
                        if type(w.disabled) == "function" then
                            local ok, err = pcall(w.disabled)
                            check(ok, "HARDEN " .. label .. " " .. wpath
                                .. " disabled survives (err: " .. tostring(err) .. ")")
                        end
                        if type(w.values) == "function" then
                            local ok, err = pcall(w.values)
                            check(ok, "HARDEN " .. label .. " " .. wpath
                                .. " values survives (err: " .. tostring(err) .. ")")
                        end
                        if type(w.func) == "function" then
                            local ok, err = pcall(w.func)
                            check(ok, "HARDEN " .. label .. " " .. wpath
                                .. " func no-ops hollow (err: " .. tostring(err) .. ")")
                        end
                    end
                end
            end
        end
        -- Sets with benign values no-op hollow too (input sets get a
        -- non-numeric string so tonumber declines the write without throwing).
        hsb.st.designmode, hsb.st.practice_ui, hsb.st.rotation_text = {}, {}, {}
        local function pcall_set(w, info, value)
            if type(w) ~= "table" then return true end
            if type(w.set) == "function" then
                return pcall(w.set, info, value)
            elseif type(w.set) == "string" then
                return true
            end
            return true
        end
        for gname, args in pairs(groups) do
            for key, w in pairs(args) do
                if type(w) == "table" and w.type ~= nil then
                    local ok = true
                    if w.type == "toggle" then
                        ok = pcall_set(w, { "class", key }, true)
                    elseif w.type == "range" then
                        ok = pcall_set(w, { "class", key },
                            (tonumber(w.min) or 0) + (tonumber(w.step) or 1))
                    elseif w.type == "input" then
                        ok = pcall_set(w, { "class", key }, "not-a-number")
                    elseif w.type == "color" then
                        if type(w.set) == "function" then
                            ok = pcall(w.set, { "class", key }, 1, 1, 1, 1)
                        end
                    elseif w.type == "select" then
                        local probe = type(w.values) == "table" and next(w.values) or nil
                        ok = pcall_set(w, { "class", key }, probe)
                    end
                    check(ok, "HARDEN {all hollow} " .. gname .. "." .. key
                        .. " set no-ops hollow")
                end
            end
        end

        -- (c) design_toggle trace: no HUD frame, no practice panel — the toggle
        -- still routes into designmode.toggle (nil frames skip overlays by
        -- registry design; only an absent toggle method no-ops).
        hsb.st.hud, hsb.st.practice_ui = nil, nil
        local w = hsb.ST.opts_table.args.design_mode
            and hsb.ST.opts_table.args.design_mode.args.design_toggle
        check(type(w) == "table" and type(w.func) == "function",
            "HARDEN: design_toggle carries a func")
        if type(w) == "table" and type(w.func) == "function" then
            local calls = 0
            hsb.st.designmode = { toggle = function() calls = calls + 1 end }
            local ok, err = pcall(w.func)
            check(ok, "HARDEN: design_toggle runs with no HUD frame/practice panel ("
                .. tostring(err) .. ")")
            check(calls == 1, "HARDEN: design_toggle routes into designmode.toggle")
            hsb.st.designmode = {}
            local ok2, err2 = pcall(w.func)
            check(ok2, "HARDEN: design_toggle no-ops on a hollow designmode ("
                .. tostring(err2) .. ")")
        end
    end
end

--=========================================================================================
-- 19) Paladin parity: every class panel matches the reference (owner order)
--=========================================================================================
-- Paladin's panel is the reference. Each of the other five class panels carries
-- the same structural sections: the 6-key NAG master set, the shared HUD core
-- (header + masters + cues + template), the rotation core, the wowsims block,
-- the nag header/desc, and a practice header + toggle. Per-class extras stay
-- per-class (paladin-only mana/fillers/reaction, per-class slots, drill copy).
-- Two real gaps closed here (both in this lane's files, both consumer-backed):
-- (a) Druid wrote 7 orphan practice keys (druid_practice_* with no consumer and
-- no defaults; the session reads unprefixed keys) — renamed to the live
-- unprefixed keys the session reads, with DRUID defaults to match.
-- (b) Hunter had no practice knobs (only toggle + report) while its drill shows
-- the shared grade popup and panel — the 7 knob widgets added (no
-- weapon-speed: the forced-move drill runs no drill swing, practice_ui.lua:4115,
-- so that key would be an orphan here), with HUNTER defaults to match.
do
    local function read_source_19(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end
    local presets_src = read_source_19("config_presets.lua")
    local tables_src = read_source_19("option_tables.lua")
    local pui_src = read_source_19("practice_ui.lua")
    local function defaults_block_19(token)
        return presets_src:match("ST%." .. token .. "%.defaults%s*=%s*{(.-)\n%}") or ""
    end

    -- (a) Structural parity: every class panel carries every reference section.
    local GUIDE = { "nextaction_enabled", "nextaction_locked",
        "nextaction_visibility_key", "nextaction_icon_size",
        "nextaction_x", "nextaction_y" }
    local HUD_CORE = { "hud_header", "hud_enabled", "hud_locked",
        "hud_visibility_key", "hud_template", "hud_glow_enabled",
        "hud_desaturate", "hud_mana_tint", "hud_range_tint" }
    local ROT_CORE = { "rotation_label_header", "rotation_label_enabled",
        "rotation_label_align", "rotation_label_format", "rotation_label_color" }
    for _, pretty in ipairs({ "Paladin", "Warrior", "Hunter", "Shaman", "Druid", "Rogue" }) do
        local sb, err = build(pretty)
        check(sb ~= nil, "PARITY: the " .. pretty .. " options tree builds"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            local args = sb.ST.opts_table.args.class
                and sb.ST.opts_table.args.class.args or {}
            for _, key in ipairs(GUIDE) do
                check(type(args[key]) == "table",
                    "PARITY: " .. pretty .. " carries the guide " .. key)
            end
            for _, key in ipairs(HUD_CORE) do
                check(type(args[key]) == "table",
                    "PARITY: " .. pretty .. " carries " .. key)
            end
            for _, key in ipairs(ROT_CORE) do
                check(type(args[key]) == "table",
                    "PARITY: " .. pretty .. " carries " .. key)
            end
            for _, key in ipairs({ "wowsims_header", "wowsims_desc",
                "nag_header", "nag_desc" }) do
                check(type(args[key]) == "table",
                    "PARITY: " .. pretty .. " carries " .. key)
            end
            local has_ptoggle = args.practice_toggle ~= nil
                or args.hunter_practice_toggle ~= nil
                or args.druid_practice_toggle ~= nil
            check(has_ptoggle,
                "PARITY: " .. pretty .. " carries a practice toggle entry")
        end
    end

    -- (b) Druid: the orphan prefixed keys are gone; the live unprefixed keys ship
    -- with widgets + defaults.
    for _, key in ipairs({ "druid_practice_weapon_speed",
        "druid_practice_result_duration", "druid_practice_result_text_size",
        "druid_practice_result_color_hit", "druid_practice_result_color_miss",
        "druid_practice_panel_x", "druid_practice_panel_y" }) do
        check(tables_src:find("%f[%a_]" .. key .. "%s*=", 1) == nil,
            "PARITY: orphan key " .. key .. " is gone")
    end
    do
        local dsb = build("Druid")
        check(dsb ~= nil, "PARITY: the druid options tree builds")
        if dsb then
            local args = dsb.ST.opts_table.args.class
                and dsb.ST.opts_table.args.class.args or {}
            for _, key in ipairs({ "practice_weapon_speed",
                "practice_result_duration", "practice_result_text_size",
                "practice_result_color_hit", "practice_result_color_miss",
                "practice_panel_x", "practice_panel_y",
                "practice_reset_position" }) do
                check(type(args[key]) == "table",
                    "PARITY: druid carries live " .. key)
            end
            -- The renamed text-size widget keeps the live update_result_font seam.
            local w = args.practice_result_text_size
            if type(w) == "table" then
                dsb.st.practice_ui = nil
                local ok = pcall(w.set, nil, 30)
                check(ok and dsb.class_db.practice_result_text_size == 30,
                    "PARITY: druid text size writes with no practice_ui loaded")
            end
        end
        local dblock = defaults_block_19("DRUID")
        check(dblock ~= "", "PARITY: the DRUID defaults block is found")
        for _, spec in ipairs({
            { key = "practice_result_duration", want = "0%.8" },
            { key = "practice_result_text_size", want = "28" },
            { key = "practice_weapon_speed", want = "0" },
            { key = "practice_panel_x", want = "0" },
            { key = "practice_panel_y", want = "0" },
        }) do
            check(dblock:match("\n%s*" .. spec.key .. "%s*=%s*" .. spec.want) ~= nil,
                "PARITY: DRUID defaults ship " .. spec.key .. " = " .. spec.want)
        end
        for _, key in ipairs({ "practice_result_color_hit",
            "practice_result_color_miss" }) do
            check(dblock:match("\n%s*" .. key .. "%s*=%s*{") ~= nil,
                "PARITY: DRUID defaults ship " .. key)
        end
    end

    -- (c) Hunter: the 7 knob widgets ship with live get/set; the 6 defaults ship
    -- (no weapon_speed: no drill swing, so it would be an orphan).
    do
        local hsb = build("Hunter")
        check(hsb ~= nil, "PARITY: the hunter options tree builds")
        if hsb then
            local args = hsb.ST.opts_table.args.class
                and hsb.ST.opts_table.args.class.args or {}
            local handler = hsb.ST.opts_table.args.class.handler
            for _, key in ipairs({ "practice_result_duration",
                "practice_result_text_size", "practice_result_color_hit",
                "practice_result_color_miss", "practice_panel_x",
                "practice_panel_y", "practice_reset_position" }) do
                local w = args[key]
                check(type(w) == "table",
                    "PARITY: hunter carries " .. key)
                if type(w) == "table" then
                    check(type(w.order) == "number",
                        "PARITY: hunter " .. key .. " carries a numeric order")
                    local getter = type(w.get) == "function" and w.get
                        or (type(w.get) == "string" and type(handler) == "table"
                            and handler[w.get]) or nil
                    check(type(getter) == "function" or w.type == "execute",
                        "PARITY: hunter " .. key .. "'s get resolves")
                end
            end
            check(args.practice_weapon_speed == nil,
                "PARITY: hunter ships no weapon-speed knob (no drill swing)")
        end
        local hblock = defaults_block_19("HUNTER")
        check(hblock ~= "", "PARITY: the HUNTER defaults block is found")
        check(hblock:match("\n%s*practice_result_duration%s*=%s*0%.8") ~= nil,
            "PARITY: HUNTER defaults ship practice_result_duration = 0.8")
        check(hblock:match("\n%s*practice_result_text_size%s*=%s*28") ~= nil,
            "PARITY: HUNTER defaults ship practice_result_text_size = 28")
        check(hblock:match("\n%s*practice_panel_x%s*=%s*0") ~= nil
                and hblock:match("\n%s*practice_panel_y%s*=%s*0") ~= nil,
            "PARITY: HUNTER defaults ship practice_panel_x/y = 0")
        check(hblock:match("\n%s*practice_weapon_speed%s*=") == nil,
            "PARITY: HUNTER defaults ship no weapon speed (correctly absent)")
    end

    -- (d) Consumers cited (practice_ui.lua reads the unprefixed keys generically,
    -- so every drill — including hunter and druid — honors them).
    check(pui_src:find("db.practice_weapon_speed", 1, true) ~= nil,
        "PARITY: the session reads practice_weapon_speed (fight start)")
    check(pui_src:find("db.practice_result_text_size", 1, true) ~= nil,
        "PARITY: the session reads practice_result_text_size (grade popup)")
    check(pui_src:find("db.practice_panel_x or 0", 1, true) ~= nil,
        "PARITY: the session reads practice_panel_x (shared panel)")
end

--=========================================================================================
-- 20) The Progress page (practice_progress_ui.lua): the top-level group, its widgets,
--     its renderers and the reset wiring
--=========================================================================================
-- The Progress page (design spec §3) is a NEW top-level group next to Practice. It
-- shows the level, the XP bar, the per-drill mastery table, the achievements list, the
-- lifetime stats summary and a confirmed reset.
--
-- What is pinned here:
--   (a) the group exists in EVERY class's tree, is a group, and sits next to Practice
--       (its order is one step behind the Practice group's);
--   (b) its widget set is exactly the expected one, and NONE of its widgets carries a
--       get/set - the page writes no db key of its own, so it cannot collide with a
--       practice / design / class-slot key;
--   (c) the description widgets render real text: with no practice data they say so,
--       and with a saved profile they carry the level, the mastery rows, the
--       achievements and the stats numbers;
--   (d) the reset is a two-step action (arm, then confirm) and the Cancel button
--       disarms it;
--   (e) the "Open the stats frame" button is wired to the stats frame's opener.
do
    local PROGRESS_WIDGETS = {
        progress_desc = "description",
        progress_level = "description",
        progress_xp_bar = "description",
        progress_mastery_header = "header",
        progress_mastery = "description",
        progress_achievements_header = "header",
        progress_achievements = "description",
        progress_stats_header = "header",
        progress_stats = "description",
        progress_account = "description",
        progress_open_stats = "execute",
        progress_reset_header = "header",
        progress_reset = "execute",
        progress_reset_cancel = "execute",
    }
    local PRACTICE_KEYS = {
        "practice_desc", "practice_toggle", "practice_sim_header", "practice_weapon_speed",
        "practice_aw_includes_pot", "practice_aw_includes_sob", "practice_dst_enabled",
        "practice_spell_queue_window", "practice_fight_header", "practice_bl_delay",
        "practice_rotation_header", "practice_rotation_desc", "practice_timeline_header",
        "practice_timeline_desc", "practice_feedback_header", "practice_result_duration",
        "practice_result_text_size", "practice_result_color_hit", "practice_result_color_miss",
    }

    -- (a) + (b) the group and its widgets, in every class's tree.
    for _, pretty in ipairs(CLASSES) do
        local sb, err = build(pretty)
        check(sb ~= nil, "PROGRESS: the " .. pretty .. " options tree builds"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            local group = sb.ST.opts_table.args.progress
            check(type(group) == "table", "PROGRESS: " .. pretty .. " carries the Progress page")
            if type(group) == "table" then
                eq(group.type, "group", "PROGRESS: " .. pretty .. " -> the page is a group")
                check(type(group.name) == "string", "PROGRESS: " .. pretty .. " -> the page has a name")
                check(type(group.order) == "number",
                    "PROGRESS: " .. pretty .. " -> the page has a numeric order")
                local practice = sb.ST.opts_table.args.practice
                check(practice ~= nil and type(practice.order) == "number",
                    "PROGRESS: " .. pretty .. " -> the Practice group has a numeric order")
                if practice and type(practice.order) == "number" then
                    check(group.order > practice.order,
                        "PROGRESS: " .. pretty .. " -> the page sits after Practice")
                    check(group.order - practice.order <= 0.05,
                        "PROGRESS: " .. pretty .. " -> the page sits next to Practice")
                end
                local args = group.args or {}
                for key, want_type in pairs(PROGRESS_WIDGETS) do
                    local widget = args[key]
                    check(type(widget) == "table",
                        "PROGRESS: " .. pretty .. " carries " .. key)
                    if type(widget) == "table" then
                        eq(widget.type, want_type,
                            "PROGRESS: " .. pretty .. " -> " .. key .. " is a " .. want_type)
                        -- No get/set: the page reads the saved data, it never writes a
                        -- db key (the reset goes through the module, not a widget).
                        check(widget.get == nil and widget.set == nil,
                            "PROGRESS: " .. pretty .. " -> " .. key .. " writes no db key")
                    end
                end
                -- The page must not reuse a key that already belongs to another panel.
                local practice_args = (type(practice) == "table" and practice.args) or {}
                for key in pairs(PROGRESS_WIDGETS) do
                    check(practice_args[key] == nil,
                        "PROGRESS: " .. pretty .. " -> " .. key .. " does not collide with Practice")
                end
                -- The Practice panel keeps every key it had (this lane must not touch
                -- the practice / design / class-slot keys).
                for _, key in ipairs(PRACTICE_KEYS) do
                    check(type(practice_args[key]) == "table",
                        "PROGRESS: " .. pretty .. " -> the Practice panel still carries " .. key)
                end
            end
        end
    end

    -- (c) the renderers: no data, then data.
    local sb = build("Paladin")
    check(sb ~= nil, "PROGRESS: the paladin options tree builds")
    if sb then
        local args = sb.ST.opts_table.args.progress.args

        -- No practice data yet: the page says so and never raises.
        eq(sb.profile.practice, nil, "PROGRESS: the sandbox profile starts with no practice key")
        local level_text = args.progress_level.name()
        check(type(level_text) == "string" and #level_text > 0,
            "PROGRESS: the level line renders with no data")
        check(level_text:find("No practice data", 1, true) ~= nil,
            "PROGRESS: the level line says 'no data' with no data")
        local stats_text = args.progress_stats.name()
        check(type(stats_text) == "string" and stats_text:find("No practice data", 1, true) ~= nil,
            "PROGRESS: the stats line says 'no data' with no data")
        check(type(args.progress_mastery.name()) == "string",
            "PROGRESS: the mastery block renders with no data")
        check(type(args.progress_achievements.name()) == "string",
            "PROGRESS: the achievements block renders with no data")

        -- With a saved profile: the page carries the real numbers.
        local P = sb.st.practice_progress
        local S = sb.st.practice_stats
        local progress_state = P.new_state()
        local stats_state = S.new_state()
        local session = P.new_session()
        for _ = 1, 25 do
            P.record_attempt(progress_state, session, "PALADIN", "paladin_twist", "S", 20000)
            S.record_attempt(stats_state, "PALADIN", "S", "paladin_twist")
        end
        P.end_session(progress_state, session, "PALADIN", 20000)
        S.record_session(stats_state, "PALADIN", { attempts = 25, hits = 25, score = 90,
            best_grade = "S" }, 60, 20000)
        progress_state.classes.PALADIN.unlocks.first_s = true
        sb.profile.practice = {
            schema_version = 1,
            progress = progress_state,
            stats = stats_state,
        }

        level_text = args.progress_level.name()
        check(level_text:find("Level ", 1, true) ~= nil,
            "PROGRESS: the level line names the level with data")
        check(level_text:find("XP ", 1, true) ~= nil,
            "PROGRESS: the level line carries the XP with data")
        local bar = args.progress_xp_bar.name()
        check(type(bar) == "string" and #bar == 20,
            "PROGRESS: the XP bar renders 20 cells with data")
        local mastery = args.progress_mastery.name()
        check(mastery:find("paladin_twist", 1, true) ~= nil,
            "PROGRESS: the mastery block names the drill with data")
        check(mastery:find("attempts", 1, true) ~= nil,
            "PROGRESS: the mastery block carries the attempts with data")
        local achievements = args.progress_achievements.name()
        check(achievements:find("1 of 7 unlocked", 1, true) ~= nil,
            "PROGRESS: the achievements block counts the unlocks with data")
        stats_text = args.progress_stats.name()
        check(stats_text:find("Runs 1", 1, true) ~= nil,
            "PROGRESS: the stats line shows the runs with data")
        check(stats_text:find("Attempts 25", 1, true) ~= nil,
            "PROGRESS: the stats line shows the attempts with data")
        check(stats_text:find("Rolling 20", 1, true) ~= nil,
            "PROGRESS: the stats line shows the rolling-20 accuracy with data")
        check(stats_text:find("Best grade S", 1, true) ~= nil,
            "PROGRESS: the stats line shows the best grade with data")

        -- (d) the reset: arm, confirm, cancel.
        local module = sb.st.practice_progress_ui
        check(type(module) == "table", "PROGRESS: the page's read model module is loaded")
        local reset = args.progress_reset
        local cancel = args.progress_reset_cancel
        eq(reset.name(), "Reset all practice progress", "PROGRESS: the reset button starts disarmed")
        eq(module.reset_armed(), false, "PROGRESS: the reset starts disarmed")
        reset.func()
        eq(module.reset_armed(), true, "PROGRESS: the first click arms the reset")
        eq(reset.name(), "Confirm: reset all practice progress",
            "PROGRESS: the armed reset button asks for the confirmation")
        eq(cancel.hidden(), false, "PROGRESS: the cancel button appears while the reset is armed")
        cancel.func()
        eq(module.reset_armed(), false, "PROGRESS: the cancel disarms the reset")
        eq(reset.name(), "Reset all practice progress",
            "PROGRESS: the cancelled reset button goes back to its label")
        eq(cancel.hidden(), true, "PROGRESS: the cancel button hides again")
        reset.func()
        reset.func()
        eq(module.reset_armed(), false, "PROGRESS: the confirmed reset disarms itself")
        check(sb.profile.practice ~= nil and sb.profile.practice.progress ~= progress_state,
            "PROGRESS: the confirmed reset replaced the saved progress")
        local level_after = args.progress_level.name()
        check(level_after:find("No practice data", 1, true) ~= nil,
            "PROGRESS: the page reads as empty after the reset")

        -- (e) the stats frame button is wired to the frame's opener.
        local opened = 0
        local real_open = module.open_frame
        module.open_frame = function() opened = opened + 1 end
        args.progress_open_stats.func()
        module.open_frame = real_open
        eq(opened, 1, "PROGRESS: the stats frame button opens the stats frame")
    end
end

--=========================================================================================
-- 21) Output policy: config_presets.lua reaches the chat path, never the global print
--=========================================================================================
-- The bars lane (bench/bars_print_policy_2026-10-19.md) removed the
-- `local print = st.utils.print_msg` alias from bars.lua and routed its module-parse
-- trailer through st.utils.print_msg explicitly. config_presets.lua carried the same
-- bare global print in its trailer; the policy that replaced it is pinned here:
--   - no bare print call survives anywhere in config_presets.lua (source scan, comments
--     included),
--   - config_presets.lua defines no print alias (the ambiguous identifier is gone),
--   - the module-parse trailer reaches the chat frame when the debug switch is on,
--   - the client's global print is never called.
do
    local function read_source_21(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end
    local presets_src = read_source_21("config_presets.lua")

    -- The source scan: "st.utils.print_msg(" never contains "print(", so every hit here
    -- is a bare call to the client's global print - live code or a commented-out debug
    -- line alike.
    local bare = 0
    for line in presets_src:gmatch("[^\n]+") do
        if line:find("print%(") then
            bare = bare + 1
        end
    end
    eq(bare, 0,
        "output policy: config_presets.lua calls no bare print (chat output is st.utils.print_msg)")
    check(presets_src:find("\nlocal print =", 1, true) == nil,
        "output policy: config_presets.lua defines no print alias")

    -- The trailer itself. A dedicated sandbox, so the debug switch can be opened
    -- WITHOUT dragging config.lua (a sibling lane's file, still on the old path) into
    -- the measurement. utils.lua loads first exactly as the TOC orders it, and the
    -- switch is flipped afterwards - utils.lua sets st.debug = false as it loads.
    local chat, raw_prints = {}, {}
    local ST = {}
    for _, name in ipairs(CLASS_TABLES) do ST[name] = {} end
    local env = setmetatable({}, { __index = _G })
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg) chat[#chat + 1] = tostring(msg) end,
    }
    -- The client's global print, spied: the addon's chat path is st.utils.print_msg
    -- (utils.lua -> DEFAULT_CHAT_FRAME:AddMessage), so a module that reaches the global
    -- shows up here instead of as stray console output.
    env.print = function(...)
        local first = select(1, ...)
        raw_prints[#raw_prints + 1] = tostring(first)
    end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then return { GetAddon = function() return ST end } end
        return {}
    end
    local st = {}
    local utils = assert(loadfile(ROOT .. "utils.lua"))
    setfenv(utils, env)
    utils("SwedgeTimer", st)
    -- The debug switch is off by default (utils.lua sets st.debug = false); turn it on
    -- so the module-parse trailer actually runs and its output path is observable.
    st.debug = true
    local presets = assert(loadfile(ROOT .. "config_presets.lua"))
    setfenv(presets, env)
    local ok, err = pcall(presets, "SwedgeTimer", st)
    check(ok, "output policy: config_presets.lua loads with the debug switch on ("
        .. tostring(err) .. ")")
    eq(#raw_prints, 0,
        "output policy: the client's global print is never called by config_presets.lua")
    local reported = false
    for i = 1, #chat do
        if chat[i]:find("Parsed config_presets.lua module correctly", 1, true) then
            reported = true
        end
    end
    check(reported, "output policy: config_presets.lua's module trailer reaches the chat frame")
end

--=========================================================================================
-- 22) The practice mode select (the shared rotation-scenario + drill engine lane)
--=========================================================================================
-- The Practice page surfaces the new modes: "class" is the shipped per-class
-- session (the default - a fresh profile behaves exactly as before), "scenario"
-- runs the class's own rotation and "drills" runs the class's focused drill list.
-- The widget is nil-safe: an unset (or unknown) value means the class session.
do
    local sb = build("Paladin")
    check(sb ~= nil, "PRACTICE-MODE: the paladin options tree builds")
    if sb then
        local page = sb.ST.opts_table.args.practice
        local args = (type(page) == "table" and page.args) or {}
        local widget = args.practice_mode
        check(type(widget) == "table" and widget.type == "select",
            "PRACTICE-MODE: the Practice page carries the practice_mode select")
        if type(widget) == "table" then
            check(type(widget.values) == "table", "PRACTICE-MODE: the select carries its values")
            check(widget.values.class ~= nil, "PRACTICE-MODE: the select offers the class session")
            check(widget.values.scenario ~= nil,
                "PRACTICE-MODE: the select offers the rotation scenario")
            check(widget.values.drills ~= nil, "PRACTICE-MODE: the select offers the drill list")
            -- Nil-safe: an unset db key reads the shipped class session.
            eq(widget.get(), "class", "PRACTICE-MODE: an unset mode reads the class session")
            sb.class_db.practice_mode = "scenario"
            eq(widget.get(), "scenario", "PRACTICE-MODE: the saved mode reads back")
            widget.set(nil, "drills")
            eq(sb.class_db.practice_mode, "drills", "PRACTICE-MODE: the select writes the class table")
            eq(widget.get(), "drills", "PRACTICE-MODE: the written mode reads back")
            -- An unknown value falls back to the class session (never a wrong mode).
            sb.class_db.practice_mode = "nonsense"
            eq(widget.get(), "class", "PRACTICE-MODE: an unknown mode reads the class session")
            sb.class_db.practice_mode = nil
        end
        -- The availability note renders (with or without the practice engine).
        local note = args.practice_mode_note
        check(type(note) == "table" and note.type == "description",
            "PRACTICE-MODE: the page carries the availability note")
        if type(note) == "table" then
            local text = note.name()
            check(type(text) == "string" and #text > 0,
                "PRACTICE-MODE: the availability note renders")
            -- The truth for the family the player is on: the rotation scenario
            -- needs a LIVE swing engine, and the client that keeps the inert
            -- stand-in cannot run it. The note must say so (the option must not
            -- advertise a session the client cannot run).
            local saved_practice = sb.st.practice
            local saved_engine = sb.ST.swing_engine
            sb.st.practice = {
                harness = {
                    practice_scenario_available = function() return true end,
                    practice_drills = function() return { { key = "x", label = "x" } } end,
                },
            }
            sb.ST.swing_engine = "inert-standin"
            local dead = note.name()
            check(type(dead) == "string"
                and dead:find("cannot run on this client", 1, true) ~= nil,
                "PRACTICE-MODE: the note says the scenario cannot run on this client")
            sb.ST.swing_engine = saved_engine
            local live = note.name()
            check(type(live) == "string"
                and live:find("cannot run on this client", 1, true) == nil,
                "PRACTICE-MODE: the note stays quiet on a client that can run it")
            sb.st.practice = saved_practice
            sb.ST.swing_engine = saved_engine
        end
        -- The mode select never leaks into another page.
        local progress_args = (sb.ST.opts_table.args.progress or {}).args or {}
        check(progress_args.practice_mode == nil,
            "PRACTICE-MODE: the Progress page does not carry the mode select")
    end
end

--=========================================================================================
-- 23) The two shaman maintain mirrors: hud_show_lightningshield / hud_show_searing
--=========================================================================================
-- bench/shaman_slots_2026-10-19.md §2 filed the options half of the two maintain
-- mirrors the shaman-slots lane shipped (the guide slots 16/17 got their HUD mirrors
-- and their provider; the widget + the default were the options pass's job).
--
-- The live consumer is classes/shaman.lua:
--   * ST.SHAMAN.HUD_SLOTS declares the "lightningshield" and "searing" descriptors;
--   * ST.SHAMAN.get_hud_state reads hud_db["hud_show_" .. slot.key] == true and hides
--     the slot otherwise - nil = off (the HUD itself hides only on == false, so the
--     provider-level hide is the no-default-visible gate).
-- Both defaults ship false (the druid Claw mirror's shape): a fresh profile shows the
-- row exactly as before, and the two mirrors stay hidden until the player asks for them.
do
    local function read_source_23(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end

    local ssb, serr = build("Shaman")
    check(ssb ~= nil, "S-M1: the shaman options tree builds"
        .. (ssb and "" or (": " .. tostring(serr))))
    if ssb then
        local args = ssb.ST.opts_table.args.class.args or {}
        local handler = ssb.ST.opts_table.args.class.handler
        -- The shared class setter reaches into main.lua / bars.lua, which this sandbox
        -- does not load - stub the calls it makes so the write itself can be pinned
        -- (the same shape section 17 uses for timers_locked).
        for _, fn in ipairs({
            "determine_form_visibility_flag", "configure_texts",
            "configure_bar_size_and_positions", "configure_bar_appearances",
            "configure_bar_outline", "configure_gcd_markers",
            "set_gcd_marker_positions", "handle_bar_visibility",
        }) do
            ssb.ST[fn] = ssb.ST[fn] or function() end
        end
        for _, spec in ipairs({
            { key = "hud_show_lightningshield" },
            { key = "hud_show_searing" },
        }) do
            local w = args[spec.key]
            check(type(w) == "table" and w.type == "toggle",
                "S-M1: " .. spec.key .. " has a toggle widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                check(type(w.order) == "number",
                    "S-M1: " .. spec.key .. " carries a numeric order")
                check(type(w.name) == "string" and #w.name > 0,
                    "S-M1: " .. spec.key .. " carries a name")
                check(type(w.desc) == "string" and #w.desc > 0,
                    "S-M1: " .. spec.key .. " carries a description")
                local getter = type(w.get) == "function" and w.get
                    or (type(w.get) == "string" and type(handler) == "table"
                        and handler[w.get]) or nil
                local setter = type(w.set) == "function" and w.set
                    or (type(w.set) == "string" and type(handler) == "table"
                        and handler[w.set]) or nil
                check(type(getter) == "function",
                    "S-M1: " .. spec.key .. "'s get resolves")
                check(type(setter) == "function",
                    "S-M1: " .. spec.key .. "'s set resolves")
                if type(getter) == "function" then
                    ssb.class_db[spec.key] = true
                    check(getter(nil, { "class", spec.key }) == true,
                        "S-M1: " .. spec.key .. "'s getter reads the class key (true)")
                    ssb.class_db[spec.key] = nil
                    check(not getter(nil, { "class", spec.key }),
                        "S-M1: " .. spec.key .. "'s getter reads the class key (nil = off)")
                end
                if type(setter) == "function" then
                    setter(nil, { "class", spec.key }, true)
                    check(ssb.class_db[spec.key] == true,
                        "S-M1: " .. spec.key .. "'s setter writes the class key")
                    ssb.class_db[spec.key] = nil
                end
            end
        end
        -- The slot toggles keep the row's order: the two maintain mirrors sit between
        -- the rotation slots and the trinkets, mirroring ST.SHAMAN.HUD_SLOTS.
        local o_twist = type(args.hud_show_twist) == "table" and args.hud_show_twist.order
        local o_ls = type(args.hud_show_lightningshield) == "table"
            and args.hud_show_lightningshield.order
        local o_searing = type(args.hud_show_searing) == "table"
            and args.hud_show_searing.order
        local o_tr1 = type(args.hud_show_trinket1) == "table" and args.hud_show_trinket1.order
        check(type(o_ls) == "number" and type(o_searing) == "number"
                and type(o_twist) == "number" and type(o_tr1) == "number",
            "S-M1: the shaman slot toggles carry comparable orders")
        if type(o_ls) == "number" and type(o_searing) == "number"
                and type(o_twist) == "number" and type(o_tr1) == "number" then
            check(o_twist < o_ls and o_ls < o_searing and o_searing < o_tr1,
                "S-M1: the maintain toggles sit between the rotation slots and the trinkets")
        end
        -- The glow copy names the two mirrors (the "no other icon glows" line used to
        -- contradict them - the mirrors glow while their upkeep is due).
        local glow = args.hud_glow_enabled
        if type(glow) == "table" and type(glow.desc) == "string" then
            check(glow.desc:find("Lightning Shield", 1, true) ~= nil
                    and glow.desc:find("Searing Totem", 1, true) ~= nil,
                "S-M1: the glow copy names the two maintain mirrors")
        else
            check(false, "S-M1: the glow copy names the two maintain mirrors")
        end
    end

    -- The defaults: false in ST.SHAMAN.defaults, and no true anywhere in that block.
    local sblock = read_source_23("config_presets.lua"):match(
        "ST%.SHAMAN%.defaults%s*=%s*{(.-)\n}") or ""
    check(sblock ~= "", "S-M1: the ST.SHAMAN.defaults block is found")
    for _, key in ipairs({ "hud_show_lightningshield", "hud_show_searing" }) do
        check(sblock:find("%f[%a_]" .. key .. "%s*=%s*false") ~= nil,
            "S-M1: " .. key .. " ships false (hidden, no default-visible change)")
        check(sblock:find("%f[%a_]" .. key .. "%s*=%s*true") == nil,
            "S-M1: " .. key .. " ships no true default")
    end

    -- The live consumer is cited (source pins - classes/shaman.lua is out of this
    -- lane's scope, so the pins name the descriptor + the gate, not a behaviour).
    local shsrc = read_source_23("classes/shaman.lua")
    -- Scoped to the HUD_SLOTS table itself: the guide slots carry the same slot keys
    -- (the guide's own descriptors), so an unscoped find would pass on the wrong one.
    local hud_slots = shsrc:match("ST%.SHAMAN%.HUD_SLOTS%s*=%s*{(.-)\n}") or ""
    check(hud_slots ~= "", "S-M1: the ST.SHAMAN.HUD_SLOTS table is found")
    check(hud_slots:find('key%s*=%s*"lightningshield"') ~= nil,
        "S-M1: the 'lightningshield' HUD_SLOTS descriptor exists")
    check(hud_slots:find('key%s*=%s*"searing"') ~= nil,
        "S-M1: the 'searing' HUD_SLOTS descriptor exists")
    check(shsrc:find('hud_show_', 1, true) ~= nil,
        "S-M1: the hud_show_ consumer exists")
    check(shsrc:find('hud_show_"%s*%.%.%s*slot%.key%]%s*~=%s*true') ~= nil,
        "S-M1: the provider gate reads hud_show_<key> == true (nil = off)")
end

--=========================================================================================
-- 24) Gamification visibility: the level badge, the XP bar and the chat notices
--=========================================================================================
-- The operator asked for visible practice levels/XP ("start at lvl 1, gain xp each
-- practice, level up"). That request IS the gate for this default-visible change,
-- and it is recorded in config_presets.lua next to the default it gates.
--
-- The whole visible surface rides ONE db key on the class table: practice_panel_badge.
-- practice_ui.lua reads it nil-safely (== true), so nil and false both hide the badge
-- AND silence the notices; the default only reaches a FRESH profile (AceDB: a saved
-- value wins over the default, so a profile that turned it off keeps it off).
--
-- These pins are BEHAVIOURAL, not textual: a mini sandbox loads the real
-- practice_stats.lua + practice_progress.lua + practice_ui.lua (the two pure modules
-- and the live hook module - no WoW API, no frames) and drives the real session path
-- (begin_progress_session -> record_progress_attempt -> end_progress_session), so a
-- mutant that drops the default or ungates the notice dies here.
do
    local function read_source_24(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end

    -- The AceDB class table, built the way AceDB-3.0 builds it (copyDefaults: a
    -- value that is already present is never overwritten): the SAVED profile values
    -- win, then the class-specific defaults, then the shared '**' defaults
    -- (ST.class_defaults) fill whatever is still absent.
    local function merged_class_table(class_token, saved)
        local out = {}
        for k, v in pairs(saved or {}) do out[k] = v end
        for k, v in pairs(base.ST.class_defaults) do
            if out[k] == nil then out[k] = v end
        end
        for k, v in pairs(base.ST[class_token].defaults or {}) do
            if out[k] == nil then out[k] = v end
        end
        return out
    end

    -- The mini sandbox: the two pure modules + the live hook module, a stub addon
    -- object (the class table + the profile table + the chat print) and a clock.
    local function badge_sandbox(class_db)
        local prints = {}
        local profile = {}
        local db = class_db or {}
        -- active_class: the shared layer's one class fact (class-isolation 2026-10-21);
        -- this sandbox drives the progression hooks directly, so it stands in for
        -- main.lua's activation.
        local ST = { player_class = "PALADIN", active_class = "PALADIN",
            db = { profile = profile } }
        function ST:get_class_table() return db end
        function ST:get_profile_table() return profile end
        function ST:Print(msg) prints[#prints + 1] = tostring(msg) end
        local st = {
            api = { get_time = function() return 0 end },
            guard = { refusal = function() end, label = function() end },
        }
        local env = setmetatable({}, { __index = _G })
        env.LibStub = function(major)
            if major == "AceAddon-3.0" then return { GetAddon = function() return ST end } end
            if major == "LibSharedMedia-3.0" then
                return { Fetch = function(_, _, key) return key end }
            end
            return {}
        end
        for _, path in ipairs({ "practice_stats.lua", "practice_progress.lua", "practice_ui.lua" }) do
            local chunk = assert(loadfile(ROOT .. path))
            setfenv(chunk, env)
            local ok, err = pcall(chunk, "SwedgeTimer", st)
            if not ok then return nil, path .. " does not load: " .. tostring(err) end
        end
        return { st = st, ST = ST, class_db = db, prints = prints }
    end

    -- One live session: start -> the graded attempts -> the session end (the session
    -- end is where the achievement notices fire).
    local function run_session(class_db, grades)
        local box, err = badge_sandbox(class_db)
        if not box then return nil, err end
        local ui = box.st.practice_ui
        ui.begin_progress_session(box.ST, 0)
        for _, grade in ipairs(grades) do
            ui.record_progress_attempt(box.ST, grade)
        end
        ui.end_progress_session(box.ST, 5)
        return box
    end

    local function printed(box, needle)
        for _, line in ipairs(box.prints) do
            if line:find(needle, 1, true) ~= nil then return true end
        end
        return false
    end

    -- (a) The default is TRUE, it lives in the shared class defaults, and the
    -- operator order is recorded in the code as the gate for it.
    local presets_src = read_source_24("config_presets.lua")
    local shared_block = presets_src:match("ST%.class_defaults%s*=%s*{(.-)\n}") or ""
    check(shared_block ~= "", "GAMVIS: the shared class defaults block is found")
    eq(base.ST.class_defaults.practice_panel_badge, true,
        "GAMVIS: practice_panel_badge ships true in ST.class_defaults")
    local key_defaults = 0
    for _ in presets_src:gmatch("%f[%a_]practice_panel_badge%s*=") do
        key_defaults = key_defaults + 1
    end
    eq(key_defaults, 1, "GAMVIS: the key carries exactly one default in config_presets.lua")
    check(presets_src:find("%f[%a_]practice_panel_badge%s*=%s*true") ~= nil,
        "GAMVIS: that one default is true")
    check(presets_src:find("%f[%a_]practice_panel_badge%s*=%s*false") == nil,
        "GAMVIS: the key ships no false default")
    check(shared_block:find("operator order", 1, true) ~= nil,
        "GAMVIS: the operator order is named as the gate inside the class defaults")
    -- The fresh-profile inheritance path: config.lua hands the shared defaults to
    -- every class table through AceDB's '**' section.
    check(type(base.ST.defaults) == "table" and type(base.ST.defaults.profile) == "table"
            and base.ST.defaults.profile["**"] == base.ST.class_defaults,
        "GAMVIS: config.lua inherits the shared class defaults into every class table")

    -- (b) A fresh profile shows the surface; a profile that turned it off keeps it
    -- off, and an old profile with no key at all still hides it (nil = off).
    for _, token in ipairs(CLASS_TABLES) do
        eq(merged_class_table(token, {}).practice_panel_badge, true,
            "GAMVIS: a fresh " .. token .. " profile has the badge on")
        eq(merged_class_table(token, { practice_panel_badge = false }).practice_panel_badge, false,
            "GAMVIS: a " .. token .. " profile that turned the badge off keeps it off")
        check(base.ST[token].defaults.practice_panel_badge == nil,
            "GAMVIS: the " .. token .. " defaults never override the shared badge default")
    end

    -- (c) The badge widget exists and its toggle round-trips through the class table.
    local sb, sb_err = badge_sandbox(merged_class_table("PALADIN", {}))
    check(sb ~= nil, "GAMVIS: the badge sandbox loads the real modules"
        .. (sb and "" or (": " .. tostring(sb_err))))
    if sb then
        local ui = sb.st.practice_ui
        check(type(ui) == "table", "GAMVIS: practice_ui exposes its module table")
        check(type(ui.badge_is_enabled) == "function",
            "GAMVIS: the badge read entry point exists")
        check(type(ui.set_badge_enabled) == "function",
            "GAMVIS: the badge write entry point exists")
        eq(ui.badge_is_enabled(sb.ST), true,
            "GAMVIS: a fresh profile reads the badge on (the default reached the class table)")
        ui.set_badge_enabled(sb.ST, false)
        eq(sb.class_db.practice_panel_badge, false,
            "GAMVIS: turning the badge off writes false to the class table")
        eq(ui.badge_is_enabled(sb.ST), false,
            "GAMVIS: the read sees the badge off after the write")
        ui.set_badge_enabled(sb.ST, true)
        eq(sb.class_db.practice_panel_badge, true,
            "GAMVIS: turning the badge on writes true to the class table")
        eq(ui.badge_is_enabled(sb.ST), true,
            "GAMVIS: the read sees the badge on after the write")
    end
    -- The badge widget itself: the frame plus its four readouts (the level text, the
    -- XP text, the level bar and the session XP) are all built with it.
    local pu_src = read_source_24("practice_ui.lua")
    check(pu_src:find("ui.badge_frame%s*=%s*badge") ~= nil,
        "GAMVIS: the badge frame is built with the panel")
    for _, field in ipairs({ "level", "xp", "bar_fill", "session" }) do
        check(pu_src:find("badge%." .. field .. "%s*=") ~= nil,
            "GAMVIS: the badge carries its " .. field .. " readout")
    end
    -- One key, one surface: the module reads and writes no second badge key.
    local other_keys = {}
    for key in pu_src:gmatch("db%.([%w_]*badge[%w_]*)") do
        other_keys[key] = true
    end
    local key_list = {}
    for key in pairs(other_keys) do key_list[#key_list + 1] = key end
    table.sort(key_list)
    eq(table.concat(key_list, ","), "practice_panel_badge",
        "GAMVIS: the badge rides exactly one db key")

    -- (d) The chat notices ride the SAME key: with the badge off nothing is printed
    -- (the progression still runs silently), with the badge on the level-up and the
    -- achievement notices fire.
    local legacy, legacy_err = run_session({}, { "A", "A" })
    check(legacy ~= nil, "GAMVIS: the notice session runs on an old profile"
        .. (legacy and "" or (": " .. tostring(legacy_err))))
    if legacy then
        eq(#legacy.prints, 0, "GAMVIS: no chat notice fires with no db key at all")
    end
    local off = run_session(merged_class_table("PALADIN", { practice_panel_badge = false }),
        { "A", "A" })
    check(off ~= nil, "GAMVIS: the notice session runs with the badge off")
    if off then
        eq(#off.prints, 0, "GAMVIS: no chat notice fires while the badge is off")
    end
    local fresh = run_session(merged_class_table("PALADIN", {}), { "A", "A" })
    check(fresh ~= nil, "GAMVIS: the notice session runs on a fresh profile")
    if fresh then
        check(printed(fresh, "Practice level up"),
            "GAMVIS: the level-up notice fires on a fresh profile")
    end
    local fresh_s = run_session(merged_class_table("PALADIN", {}), { "S" })
    check(fresh_s ~= nil, "GAMVIS: the achievement session runs on a fresh profile")
    if fresh_s then
        check(printed(fresh_s, "Practice achievement unlocked"),
            "GAMVIS: the achievement notice fires on a fresh profile")
    end
    local off_s = run_session(merged_class_table("PALADIN", { practice_panel_badge = false }),
        { "S" })
    check(off_s ~= nil, "GAMVIS: the achievement session runs with the badge off")
    if off_s then
        eq(#off_s.prints, 0,
            "GAMVIS: no achievement notice fires while the badge is off")
    end

    -- (e) The badge TOGGLE widget (HU-9). The key had NO options widget anywhere, so
    -- with the surface visible by default there was no in-game way to turn it off
    -- (only a SavedVariables edit). The widget lives on the Progress page and drives
    -- the module's OWN entry points (ui.badge_is_enabled / ui.set_badge_enabled) -
    -- the same surface (c) pins - so the widget is wired to the real module, not to
    -- a copy of its logic.
    do
        local ob, ob_err = build("Paladin")
        check(ob ~= nil, "GAMVIS: the options tree builds for the badge widget"
            .. (ob and "" or (": " .. tostring(ob_err))))
        if ob then
            local page = ob.ST.opts_table.args.progress
            check(type(page) == "table" and type(page.args) == "table",
                "GAMVIS: the Progress page exists")
            local w = page and page.args and page.args.progress_badge
            check(type(w) == "table" and w.type == "toggle",
                "GAMVIS: the Progress page carries the badge toggle widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                check(type(w.order) == "number",
                    "GAMVIS: the badge toggle carries a numeric order")
                check(type(w.get) == "function" and type(w.set) == "function",
                    "GAMVIS: the badge toggle carries an inline get/set")
                -- Nil-safe with no practice_ui module loaded: the getter reads false
                -- and the setter is a no-op (a half-loaded addon never breaks the page).
                check(ob.st.practice_ui == nil,
                    "GAMVIS: the options sandbox has no practice_ui module")
                eq(w.get(), false, "GAMVIS: the getter reads false with no module")
                w.set(nil, false)
                -- The REAL module: the widget drives the documented entry points.
                local box, err = badge_sandbox({})
                check(box ~= nil, "GAMVIS: the real module sandbox loads for the widget"
                    .. (box and "" or (": " .. tostring(err))))
                if box then
                    ob.st.practice_ui = box.st.practice_ui
                    ob.class_db.practice_panel_badge = true
                    eq(w.get(), true,
                        "GAMVIS: the toggle reads the real module (the badge is on)")
                    w.set(nil, false)
                    eq(ob.class_db.practice_panel_badge, false,
                        "GAMVIS: the toggle writes false to the class table")
                    eq(w.get(), false,
                        "GAMVIS: the toggle reads back off after the write")
                    w.set(nil, true)
                    eq(ob.class_db.practice_panel_badge, true,
                        "GAMVIS: the toggle writes true back")
                    eq(w.get(), true,
                        "GAMVIS: the toggle reads back on")
                    ob.st.practice_ui = nil
                end
            end
        end
    end
end

--=========================================================================================
-- 25) The Forever Rend upkeep toggle (W-15 / BS-7)
--=========================================================================================
-- The Forever APL's Rend-weave group (11574, refresh <= 3 s) is toggle-gated
-- (bench/class_features_drills_2026-10-19.md:292). The PURE rule is live -
-- warrior_guide.lua's should_maintain_rend_outside_arms with REND_REFRESH_DEFAULT = 3,
-- called from rule R - but the provider (classes/warrior.lua) feeds
-- rend_upkeep_enabled only on SoD (Blood Frenzy rune 412507 known), so on the Forever
-- client the rule is dormant.
--
-- This section pins the options half the warrior lane filed here (the provider read
-- is classes/warrior.lua:3049-3053 - the warrior lane's file):
--   * the widget exists on the warrior panel and is nil-safe (nil = off);
--   * NO default ships - the key stays off until the player arms it;
--   * the engine half (the rule + the refresh window) is in the tree;
--   * whenever the provider read lands, it reads the key as == true.
do
    local function read_source_25(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end

    -- (a) The widget: a toggle on the warrior panel, nil-safe, round-tripping through
    -- the class table.
    local wb, werr = build("Warrior")
    check(wb ~= nil, "REND: the warrior options tree builds"
        .. (wb and "" or (": " .. tostring(werr))))
    if wb then
        local args = wb.ST.opts_table.args.class
            and wb.ST.opts_table.args.class.args or {}
        local w = args.guide_forever_rend_upkeep
        check(type(w) == "table" and w.type == "toggle",
            "REND: the Forever Rend toggle is a toggle widget (got "
            .. tostring(type(w) == "table" and w.type or nil) .. ")")
        if type(w) == "table" then
            check(type(w.order) == "number", "REND: the toggle carries a numeric order")
            check(type(w.get) == "function" and type(w.set) == "function",
                "REND: the toggle carries an inline get/set")
            if type(w.get) == "function" and type(w.set) == "function" then
                -- Nil-safe: an unset key reads OFF (nil = off, never a crash).
                wb.class_db.guide_forever_rend_upkeep = nil
                eq(w.get(), false, "REND: an unset key reads off (nil = off)")
                w.set(nil, true)
                eq(wb.class_db.guide_forever_rend_upkeep, true,
                    "REND: turning it on writes true to the class table")
                eq(w.get(), true, "REND: the getter reads back on")
                w.set(nil, false)
                eq(wb.class_db.guide_forever_rend_upkeep, false,
                    "REND: turning it off writes false to the class table")
                eq(w.get(), false, "REND: the getter reads back off")
                wb.class_db.guide_forever_rend_upkeep = nil
            end
        end
    end

    -- (b) No default ships: the key is OFF on a fresh profile (nil = off), so the
    -- rule the widget arms has never run on Forever without a deliberate choice.
    local presets_src = read_source_25("config_presets.lua")
    local wblock = presets_src:match("ST%.WARRIOR%.defaults%s*=%s*{(.-)\n}") or ""
    check(wblock ~= "", "REND: the WARRIOR defaults block is found")
    check(wblock:match("\n%s*guide_forever_rend_upkeep%s*=") == nil,
        "REND: no default ships for guide_forever_rend_upkeep (nil = off)")
    check(wblock:find("guide_forever_rend_upkeep", 1, true) ~= nil,
        "REND: the key is documented in the WARRIOR defaults block")

    -- (c) The engine half is live: the pure rule + the refresh window constant.
    local guide_src = read_source_25("warrior_guide.lua")
    check(guide_src:find("should_maintain_rend_outside_arms") ~= nil,
        "REND: the engine's Rend upkeep rule exists (warrior_guide.lua)")
    check(guide_src:find("REND_REFRESH_DEFAULT") ~= nil,
        "REND: the engine's Rend refresh window constant exists (warrior_guide.lua)")

    -- (d) The provider read is the FILED line (classes/warrior.lua - the warrior
    -- lane's file). Whenever it lands it must read the key as == true (nil = off),
    -- so a missing key can never arm the rule.
    local warrior_src = read_source_25("classes/warrior.lua")
    check(warrior_src:find("guide_forever_rend_upkeep") == nil
            or warrior_src:find("guide_forever_rend_upkeep%s*==%s*true") ~= nil,
        "REND: the provider reads the key as == true (nil = off) when it is wired")
end

--=========================================================================================
-- 26) The Call of the Elements HUD mirror: the hud_show_coe widget + its default
--=========================================================================================
-- The shaman lane shipped the Call of the Elements guide slot + HUD mirror
-- (bench/shaman_coe_ss_2026-10-19.md: the "coe" descriptor in
-- ST.SHAMAN.HUD_SLOTS, the water-totem clock and the provider branch in
-- ST.SHAMAN.get_hud_state) and filed the options half here: the mirror hides
-- unless its toggle reads exactly true (nil = off), so without a widget the
-- player has no in-game way to turn the mirror on.
--
-- The live consumer (classes/shaman.lua):
--   * ST.SHAMAN.HUD_SLOTS declares the "coe" descriptor;
--   * ST.SHAMAN.get_hud_state reads hud_db["hud_show_" .. slot.key] == true and
--     hides the slot otherwise (nil = off - the HUD itself hides only on
--     == false, so the provider-level hide is the no-default-visible gate).
-- The default ships false, the druid Claw mirror's shape: a fresh profile shows
-- the row exactly as before and the mirror stays hidden until it is asked for.
do
    local function read_source_26(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end

    local csb, cerr = build("Shaman")
    check(csb ~= nil, "COE: the shaman options tree builds"
        .. (csb and "" or (": " .. tostring(cerr))))
    if csb then
        local args = csb.ST.opts_table.args.class.args or {}
        local handler = csb.ST.opts_table.args.class.handler
        -- The shared class setter reaches into main.lua / bars.lua, which this sandbox
        -- does not load - stub the calls it makes so the write itself can be pinned
        -- (the same shape section 23 uses for the two maintain mirrors).
        for _, fn in ipairs({
            "determine_form_visibility_flag", "configure_texts",
            "configure_bar_size_and_positions", "configure_bar_appearances",
            "configure_bar_outline", "configure_gcd_markers",
            "set_gcd_marker_positions", "handle_bar_visibility",
        }) do
            csb.ST[fn] = csb.ST[fn] or function() end
        end
        local w = args.hud_show_coe
        check(type(w) == "table" and w.type == "toggle",
            "COE: hud_show_coe has a toggle widget (got "
            .. tostring(type(w) == "table" and w.type or nil) .. ")")
        if type(w) == "table" then
            check(type(w.order) == "number", "COE: hud_show_coe carries a numeric order")
            check(type(w.name) == "string" and #w.name > 0,
                "COE: hud_show_coe carries a name")
            check(type(w.desc) == "string" and #w.desc > 0,
                "COE: hud_show_coe carries a description")
            local getter = type(w.get) == "function" and w.get
                or (type(w.get) == "string" and type(handler) == "table"
                    and handler[w.get]) or nil
            local setter = type(w.set) == "function" and w.set
                or (type(w.set) == "string" and type(handler) == "table"
                    and handler[w.set]) or nil
            check(type(getter) == "function", "COE: hud_show_coe's get resolves")
            check(type(setter) == "function", "COE: hud_show_coe's set resolves")
            if type(getter) == "function" then
                csb.class_db.hud_show_coe = true
                check(getter(nil, { "class", "hud_show_coe" }) == true,
                    "COE: hud_show_coe's getter reads the class key (true)")
                csb.class_db.hud_show_coe = nil
                check(not getter(nil, { "class", "hud_show_coe" }),
                    "COE: hud_show_coe's getter reads the class key (nil = off)")
            end
            if type(setter) == "function" then
                setter(nil, { "class", "hud_show_coe" }, true)
                check(csb.class_db.hud_show_coe == true,
                    "COE: hud_show_coe's setter writes the class key")
                csb.class_db.hud_show_coe = nil
            end
        end
        -- The row's order mirrors ST.SHAMAN.HUD_SLOTS: the mirror sits after the
        -- Searing Totem and before the trinkets.
        local o_searing = type(args.hud_show_searing) == "table"
            and args.hud_show_searing.order
        local o_coe = type(args.hud_show_coe) == "table" and args.hud_show_coe.order
        local o_tr1 = type(args.hud_show_trinket1) == "table" and args.hud_show_trinket1.order
        check(type(o_coe) == "number" and type(o_searing) == "number"
                and type(o_tr1) == "number",
            "COE: the shaman slot toggles carry comparable orders")
        if type(o_coe) == "number" and type(o_searing) == "number"
                and type(o_tr1) == "number" then
            check(o_searing < o_coe and o_coe < o_tr1,
                "COE: the mirror sits between the maintain toggles and the trinkets")
        end
        -- The glow copy names the third mirror (the "no other icon glows" line
        -- would contradict it otherwise).
        local glow = args.hud_glow_enabled
        if type(glow) == "table" and type(glow.desc) == "string" then
            check(glow.desc:find("Call of the Elements", 1, true) ~= nil,
                "COE: the glow copy names the Call of the Elements mirror")
        else
            check(false, "COE: the glow copy names the Call of the Elements mirror")
        end
    end

    -- The default: false in ST.SHAMAN.defaults, and no true anywhere in that block.
    local sblock = read_source_26("config_presets.lua"):match(
        "ST%.SHAMAN%.defaults%s*=%s*{(.-)\n}") or ""
    check(sblock ~= "", "COE: the ST.SHAMAN.defaults block is found")
    check(sblock:find("%f[%a_]hud_show_coe%s*=%s*false") ~= nil,
        "COE: hud_show_coe ships false (hidden, no default-visible change)")
    check(sblock:find("%f[%a_]hud_show_coe%s*=%s*true") == nil,
        "COE: hud_show_coe ships no true default")

    -- The live consumer is cited (classes/shaman.lua is not this file's business,
    -- so the pins name the descriptor + the gate, not a behaviour).
    local shsrc = read_source_26("classes/shaman.lua")
    local hud_slots = shsrc:match("ST%.SHAMAN%.HUD_SLOTS%s*=%s*{(.-)\n}") or ""
    check(hud_slots ~= "", "COE: the ST.SHAMAN.HUD_SLOTS table is found")
    check(hud_slots:find('key%s*=%s*"coe"') ~= nil,
        "COE: the 'coe' HUD_SLOTS descriptor exists")
    check(shsrc:find('hud_show_"%s*%.%.%s*slot%.key%]%s*~=%s*true') ~= nil,
        "COE: the provider gate reads hud_show_<key> == true (nil = off)")
    check(shsrc:find('slot%.key%s*==%s*"coe"') ~= nil,
        "COE: the provider names the 'coe' slot in its gate")
end

--=========================================================================================
-- 27) The shaman's shock-filler choice widget (the APL utility lane's residual)
--=========================================================================================
-- The TBC APL's Shocks group picks ONE filler: the valueVariables default is
-- Earth Shock (the group's row 3, 25454 r8) and the ALTERNATIVE is Frost Shock
-- (the group's row 2, 25464 r5). The live gather never stated the choice, so the
-- engine's rule 13b arm was dark on every live client - the lane filed "the
-- Frost Shock choice as an option".
--
-- The widget (option_tables.lua's guide_filler_shock select) and its default
-- (config_presets.lua's guide_filler_shock) are the two halves the residual
-- asked for. The default ships the APL's own default ("earth"), so a fresh
-- profile behaves exactly as before: the Earth Shock filler, no Frost Shock
-- prompt. The class maps the option's "frost" value to the engine's frozen
-- token (classes/shaman.lua's gather) - the behaviour itself is pinned by
-- tests/shaman_state.lua.
do
    local function read_source_27(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return src:gsub("\r\n", "\n")
    end

    -- The widget -----------------------------------------------------------------
    local fsb, fserr = build("Shaman")
    check(fsb ~= nil, "FSOPT: the shaman options tree builds"
        .. (fsb and "" or (": " .. tostring(fserr))))
    if fsb then
        local args = fsb.ST.opts_table.args.class.args or {}
        local w = args.guide_filler_shock
        check(type(w) == "table" and w.type == "select",
            "FSOPT: guide_filler_shock has a select widget (got "
            .. tostring(type(w) == "table" and w.type or nil) .. ")")
        if type(w) == "table" then
            check(type(w.values) == "table" and w.values.earth ~= nil
                and w.values.frost ~= nil,
                "FSOPT: the widget offers both fillers (earth and frost)")
            check(w.get == "getter" and w.set == "setter",
                "FSOPT: the widget uses the shared class getter/setter")
            check(type(w.name) == "string" and w.name ~= "",
                "FSOPT: the widget carries a name")
            check(type(w.desc) == "string" and w.desc ~= "",
                "FSOPT: the widget carries a description")
        end
    end

    -- The default ----------------------------------------------------------------
    local sblock = read_source_27("config_presets.lua"):match(
        "ST%.SHAMAN%.defaults%s*=%s*{(.-)\n}") or ""
    check(sblock ~= "", "FSOPT: the ST.SHAMAN.defaults block is found")
    check(sblock:find('%f[%a_]guide_filler_shock%s*=%s*"earth"') ~= nil,
        "FSOPT: guide_filler_shock ships 'earth' (the APL's default - no default-visible change)")
    check(sblock:find('%f[%a_]guide_filler_shock%s*=%s*"frost"') == nil,
        "FSOPT: guide_filler_shock ships no frost default")

    -- The consumer is cited (the behaviour itself is pinned in tests/shaman_state.lua).
    local shsrc = read_source_27("classes/shaman.lua")
    check(shsrc:find("db%.guide_filler_shock") ~= nil,
        "FSOPT: the class reads the option (db.guide_filler_shock)")
    check(shsrc:find("FILLER_SHOCK_OPTION_FROST") ~= nil,
        "FSOPT: the class owns the option's value keys")
    -- The read is guarded: the class file is loadable without the guide module
    -- (tests/secret_guard_state.lua loads it that way), so the engine's token is
    -- read through a nil-safe guard. The TBC-only branch never runs in that
    -- suite's WRATH profile, so the guard is pinned here by its source shape.
    check(shsrc:find("filler_guide and db%.guide_filler_shock") ~= nil,
        "FSOPT: the choice read is guarded (no guide module -> no choice)")
end


--=========================================================================================
-- 28) The statusbar texture default: the operator's texture on the progress bars
--
-- The operator's texture (Media/StatusBar/Wglass.tga) is the DEFAULT status-bar
-- texture for the addon's progress bars (the swing bar and the GCD underlay). It is
-- registered in the "statusbar" registry, so the EXISTING texture dropdowns offer it
-- (values = LSM:HashTable("statusbar")) with no new widget. The deadzone is a
-- MARKER, not a progress bar, so it keeps the plain "Solid" fill.
--
-- These are SOURCE pins on the three files that own the decision: the media
-- registration (main.lua), the shipped defaults (config_presets.lua) and the
-- dropdown's value source (option_table_presets.lua). The RUNTIME half - the bars
-- actually render the operator's texture, and a nil fetch degrades instead of
-- leaving a bar textureless - is pinned in tests/bars_state.lua.
--=========================================================================================
do
    local function read_source_28(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local src = f:read("*a")
        f:close()
        return (src:gsub("\r\n", "\n"))
    end

    -- The media registration ----------------------------------------------------
    local main_src = read_source_28("main.lua")
    check(main_src:find('"statusbar",%s*"Wglass",%s*%[%[Interface\\Addons\\SwedgeTimer\\Media\\StatusBar\\Wglass%.tga%]%]') ~= nil,
        "SBAR: main.lua registers the Wglass statusbar medium at the operator's path")
    check(main_src:find('"statusbar",%s*"Minimalist"') ~= nil,
        "SBAR: the Minimalist statusbar medium stays registered (the fallback key)")

    -- The shipped defaults ------------------------------------------------------
    local presets_src = read_source_28("config_presets.lua")
    local bar_defaults = presets_src:match("ST%.bar_defaults%s*=%s*{(.-)\n}") or ""
    check(bar_defaults ~= "", "SBAR: the ST.bar_defaults block is found")
    check(bar_defaults:find('%f[%a_]bar_texture_key%s*=%s*"Wglass"') ~= nil,
        "SBAR: the swing bar's default texture is the operator's Wglass")
    check(bar_defaults:find('%f[%a_]gcd_texture_key%s*=%s*"Wglass"') ~= nil,
        "SBAR: the GCD underlay's default texture is the operator's Wglass")
    check(bar_defaults:find('%f[%a_]deadzone_texture_key%s*=%s*"Solid"') ~= nil,
        "SBAR: the deadzone marker keeps the plain Solid fill")
    -- No class block overrides the texture: a per-class override would silently
    -- override the default for that class, so the default would not be the default.
    local class_blocks = 0
    for class in presets_src:gmatch("ST%.([A-Z]+)%.defaults%s*=%s*{(.-)\n}") do
        class_blocks = class_blocks + 1
        local block = presets_src:match("ST%." .. class .. "%.defaults%s*=%s*{(.-)\n}") or ""
        check(block:find("%f[%a_]bar_texture_key") == nil,
            "SBAR: the " .. class .. " defaults block pins no bar texture")
        check(block:find("%f[%a_]gcd_texture_key") == nil,
            "SBAR: the " .. class .. " defaults block pins no GCD texture")
    end
    check(class_blocks >= 9,
        "SBAR: the class defaults blocks are all walked (got " .. tostring(class_blocks) .. ")")

    -- The dropdown ---------------------------------------------------------------
    -- The texture widgets take their values from the statusbar hash table, so a
    -- registered medium shows up with no new widget. The key is what the user sees.
    local table_presets_src = read_source_28("option_table_presets.lua")
    local _, n_statusbar = table_presets_src:gsub('LSM:HashTable%("statusbar"%)', "")
    check(n_statusbar >= 4,
        "SBAR: the texture dropdowns read the statusbar hash table (got " .. tostring(n_statusbar) .. ")")
    check(table_presets_src:find('LSM30_Statusbar') ~= nil,
        "SBAR: the texture dropdowns use the shared-media statusbar widget")
end


print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
