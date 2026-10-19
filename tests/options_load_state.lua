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
    "utils.lua", "config_presets.lua", "config.lua", "option_table_presets.lua", "option_tables.lua",
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
-- OFF-consistency: the masters hud_enabled / rotation_label_enabled ship false in
-- the shared class_defaults (checked in section 1 / rotationtext_state.lua), so
-- the per-slot `true` defaults surface nothing until enabled.
do
    local HUD_CLASSES = {
        { pretty = "Hunter", lower = "hunter", token = "HUNTER",
          slots = { "steady", "raptor", "kill_command", "multi",
              "bestial_wrath", "rapid_fire", "aimed", "trinket1", "trinket2" } },
        { pretty = "Warrior", lower = "warrior", token = "WARRIOR",
          slots = { "op", "execute", "slam", "hs", "cleave", "bt", "ww",
              "rend", "ms", "bladestorm", "raging_blow",
              "trinket1", "trinket2" } },
        { pretty = "Druid", lower = "druid", token = "DRUID",
          slots = { "maul", "mangle", "rip", "rake", "bite", "shred",
              "tf", "berserk", "trinket1", "trinket2" } },
        { pretty = "Shaman", lower = "shaman", token = "SHAMAN",
          slots = { "stormstrike", "flameshock", "weave", "firenova",
              "earthshock", "twist", "trinket1", "trinket2" } },
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

        -- (a2) every slot has a hud_show_<slot> = true default in the class block.
        local block = presets_src:match("ST%." .. class.token .. "%.defaults%s*=%s*{(.-)\n%}")
        check(block ~= nil, class.pretty .. ": the defaults block is found")
        block = block or ""
        for _, slot in ipairs(class.slots) do
            local default_key = "hud_show_" .. slot
            check(block:find("%f[%a_]" .. default_key .. "%s*=%s*true") ~= nil,
                class.pretty .. ": " .. default_key .. " ships true in the defaults")
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

            -- (c) every order in the added HUD/rotation range is unique. Scoped to
            -- orders >= 8.0 (the range this lane owns): the shipped warrior
            -- trackers carry a pre-existing collision outside this lane
            -- (show_warrior_deep_wounds_bar at 3.1 vs
            -- warrior_demo_shout_bar_color at 3.10, numerically equal), left
            -- untouched - reordering that panel needs in-client confirmation.
            local orders, dupes = {}, 0
            for key, w in pairs(args) do
                if type(w) == "table" and type(w.order) == "number"
                    and w.order >= 8.0 then
                    if orders[w.order] then dupes = dupes + 1 end
                    orders[w.order] = key
                end
            end
            check(dupes == 0, class.pretty .. ": the HUD/rotation widgets have no "
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
            "twist_lust_override_enabled", "aow_exo_pulse_enabled", "cd_icons_enabled" } },
        { pretty = "Warrior", token = "WARRIOR", keys = {
            "show_warrior_bank_cue", "show_warrior_battle_shout_badge" } },
        { pretty = "Hunter", token = "HUNTER", keys = {
            "hunter_cast_zone_enabled", "hunter_bw_badge_enabled",
            "hunter_frenzy_stacks_enabled", "hunter_multi_target" } },
        { pretty = "Shaman", token = "SHAMAN", keys = {
            "show_shaman_stormstrike_bar", "show_shaman_wf_hold_tint",
            "show_shaman_rockbiter_badge", "show_shaman_spell_positions",
            "show_shaman_dw_sync" } },
        { pretty = "Druid", token = "DRUID", keys = {
            "show_druid_pips", "show_druid_shred_countdown", "show_druid_maul_badge",
            "show_druid_omen_glow", "show_druid_gcd_tick" } },
    }
    -- Hide-on-false keys: true mirrors the sibling slot toggles and changes no behaviour.
    local DEFAULT_ON = {
        { pretty = "Druid", token = "DRUID", keys = { "hud_show_tf", "hud_show_berserk" } },
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

    -- The two profile-level keys (diag_tick_counters, enemy_swing_enabled): top-level
    -- widgets reading the profile table, shipped false in config.lua.
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
            local w = psb.ST.opts_table.args[key]
            check(type(w) == "table" and w.type == "toggle",
                "profile: " .. key .. " has a top-level toggle widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                local handler = psb.ST.opts_table.handler
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
-- Summary
--=========================================================================================
print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
