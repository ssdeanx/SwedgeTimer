-- tests/appearance_defaults_state.lua: offline pins for the appearance/defaults side of
-- the 2026-10-25 operator orders - (1) the bar BACKDROP ships opaque and a one-time
-- migration raises only an untouched old default, (2) the ranged distance bar defaults ON
-- for hunters and stays opt-in for every other class.
--
-- Loads the REAL config_presets.lua and config.lua in a sandbox, and (section 8) the
-- SHIPPED Libs/AceDB-3.0/AceDB-3.0.lua, so the migration is driven both over plain shaped
-- fixtures and over a real AceDB profile object - the root carries the '**' defaults
-- metatable that CREATES a defaults table on a missing-key read (:88-107), which is the
-- F2 defect this suite now pins against. AceDB's copy defaults one fresh table per defaults
-- table with the leaves copied in, never aliasing the defaults table (:88-131).
--
-- What is pinned here:
--   1. shipped defaults: opaque black backdrop; the coloured fill, the border, the GCD
--      underlay and every theme preset keep their own colours;
--   2. a fresh profile (AceDB-shaped) is already opaque and the migration changes nothing
--      in it, nor does anything mutate ST.bar_defaults;
--   3. the migration raises ONLY exactly {0,0,0,0.85} - custom colours, near-miss alphas,
--      non-black RGB and an active "Classic Retro" preset are preserved;
--   4. idempotence: second run = 0 changes, and a seeded old default is not re-raised
--      after the flag exists (once per profile);
--   5. nil-safety: nil / non-table profile, corrupt class rows, non-table hands and
--      colours are skipped, never thrown on;
--   6. hunter default semantics: the shared default stays false for other classes, the
--      hunter default is true, and ST.weave_range_default_enabled (the options getter's
--      single source of truth) answers ON for a nil hunter value and OFF for nil on every
--      other class;
--   7. the real AceDB profile: the flag is read with rawget (a plain read creates and
--      persists a table), the marker is the plain boolean this migration writes - a table
--      left by the pre-fix read is NOT accepted as done - the raise applies across a
--      reload, and the run leaves no other key behind.
--
-- The option WIDGET's runtime behaviour (nil -> ON for HUNTER, explicit false -> off, and
-- the set_opts migration call) is pinned against the real generated options tree in
-- tests/options_load_state.lua - this suite never builds the options tree.
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
-- lua5.1 tests/appearance_defaults_state.lua  (any cwd works).

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

local CLASS_TOKENS = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}
local HANDS = { "mainhand", "offhand", "ranged" }

-- The old default this migration is allowed to raise, written out independently of the
-- module so a drift in ST.APPEARANCE_OLD_BACKGROUND_COLOR is caught (the suite compares
-- the two below).
local OLD_DEFAULT = { 0.0, 0.0, 0.0, 0.85 }
local NEW_DEFAULT = { 0.0, 0.0, 0.0, 1.0 }

--=========================================================================================
-- Sandbox: the real config modules
--=========================================================================================
-- The addon object's class tables: main.lua seeds ST.<TOKEN> = {} at file scope before
-- any config module loads (every TOC), and config_presets.lua writes .defaults onto them.
local ST = {}
for _, token in ipairs(CLASS_TOKENS) do ST[token] = {} end
local st = { debug = false, utils = { print_msg = function() end } }

-- A LibStub that answers BOTH shapes the real tree uses: `LibStub("AceAddon-3.0")` (the
-- config modules' GetAddon) and `LibStub:NewLibrary/GetLibrary` (the vendored AceDB-3.0
-- loaded below, so the '**'-shaped fixture is the SHIPPED database, not a hand-built
-- lookalike). Section 8 needs the real AceDB; every other section only uses the config
-- modules and is unaffected by it.
local libs = {}
local LibStub = {}
function LibStub:NewLibrary(major, minor)
    if libs[major] then return nil end -- the real LibStub refuses a duplicate major
    libs[major] = { major = major, minor = minor }
    return libs[major]
end
function LibStub:GetLibrary(major)
    return libs[major]
end
setmetatable(LibStub, { __call = function(_, major)
    if major == "AceAddon-3.0" then return { GetAddon = function() return ST end } end
    return libs[major]
end })

-- The four client globals AceDB-3.0 touches at load (it builds its character/realm keys at
-- file scope) plus the frame it registers PLAYER_LOGOUT on. Only the library's own needs.
local function CreateFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[#self.events + 1] = event end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    return frame
end

local env = setmetatable({}, { __index = _G })
env._G = env -- the sandbox owns its globals (the tests/bars_state.lua convention)
env.LibStub = LibStub
env.CreateFrame = CreateFrame
env.GetRealmName = function() return "TestRealm" end
env.UnitName = function() return "Tester" end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.UnitRace = function() return "Human", "Human" end
env.UnitFactionGroup = function() return "Alliance" end
env.GetLocale = function() return "enUS" end
env.GetCurrentRegion = function() return 1 end
env.GetCurrentRegionName = function() return "US" end

-- Load order: the vendored database first (config.lua's defaults feed it in section 8),
-- then the two real config modules exactly as the TOC loads them.
for _, path in ipairs({ "Libs/AceDB-3.0/AceDB-3.0.lua", "config_presets.lua", "config.lua" }) do
    local chunk = assert(loadfile(ROOT .. path))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "SwedgeTimer", st)
    if not ok then
        print("FAIL  " .. path .. " does not load: " .. tostring(err))
        print(string.format("%d checks, %d failed", checks, failures + 1))
        os.exit(1)
    end
end
check(type(ST.defaults) == "table", "config.lua declares ST.defaults")
check(type(ST.bar_defaults) == "table", "config_presets.lua declares ST.bar_defaults")
check(type(ST.THEME_PRESETS) == "table", "config_presets.lua declares ST.THEME_PRESETS")
check(type(ST.migrate_appearance_defaults) == "function",
    "config.lua defines ST.migrate_appearance_defaults")
check(type(ST.weave_range_default_enabled) == "function",
    "config_presets.lua defines ST.weave_range_default_enabled")

local function colors_equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

--=========================================================================================
-- 1) Shipped defaults: the backdrop is opaque, everything else is untouched
--=========================================================================================
do
    local bg = ST.bar_defaults.background_color
    check(type(bg) == "table" and #bg == 4, "bar_defaults.background_color is a 4-element colour")
    eq(bg[1], 0.0, "backdrop red is black")
    eq(bg[2], 0.0, "backdrop green is black")
    eq(bg[3], 0.0, "backdrop blue is black")
    eq(bg[4], 1.0, "backdrop alpha ships OPAQUE (1.0) - the operator order")
    check(colors_equal(bg, NEW_DEFAULT), "the shipped backdrop is exactly {0,0,0,1.0}")

    -- The BACKDROP only: the coloured fill, its sibling textures and the border keep the
    -- values they shipped with. A change here means the wrong surface was made opaque.
    -- 2026-10-28: one opacity for every bar. The shared fill moved 0.85 -> 0.9 so it
    -- equals every per-hand fill (the hunter's three hands and the class rows all ship
    -- 0.9); the backdrop order above is still the thing this test guards.
    check(colors_equal(ST.bar_defaults.bar_color_default, { 93, 58, 207, 0.9 }),
        "the coloured progress FILL keeps colour and the harmonised 0.9 alpha")
    check(colors_equal(ST.bar_defaults.bar_color_gcd, { 140, 140, 140, 0.85 }),
        "the GCD underlay colour is untouched")
    check(colors_equal(ST.bar_defaults.border_color, { 40, 40, 40, 0.95 }),
        "the border colour is untouched")
    eq(ST.bar_defaults.background_texture_key, "Solid", "the backdrop texture is untouched")

    -- Theme presets keep their own backdrop alphas (the migration must never rewrite a
    -- preset - config_presets.lua declares 0.90 / 0.65 / 0.95 / 0.85).
    local want_alpha = { midnight = 0.90, glass = 0.65, elvui = 0.95, classic = 0.85 }
    local n_presets = 0
    for key, alpha in pairs(want_alpha) do
        local preset = ST.THEME_PRESETS[key]
        check(type(preset) == "table", "theme preset '" .. key .. "' exists")
        local color = type(preset) == "table" and preset.background_color or nil
        check(type(color) == "table" and color[4] == alpha,
            "theme preset '" .. key .. "' keeps its own backdrop alpha (" .. alpha .. ")")
        if type(color) == "table" and color[4] == 0.85 then
            check(colors_equal(color, OLD_DEFAULT),
                "the only preset colliding with the old default is 'classic' {0,0,0,0.85}")
        end
        n_presets = n_presets + 1
    end
    eq(n_presets, 4, "all four theme presets are pinned")

    -- The migration's own constants: the flag name is the versioned key the brief names,
    -- and the old default is the shipped pre-change value.
    eq(ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG, "appearance_defaults_213",
        "the migration flag is the versioned profile key")
    check(colors_equal(ST.APPEARANCE_OLD_BACKGROUND_COLOR, OLD_DEFAULT),
        "ST.APPEARANCE_OLD_BACKGROUND_COLOR is exactly the old {0,0,0,0.85} default")

    -- No class block overrides the backdrop: a per-class colour would silently defeat
    -- both the opaque default and the migration's exact-match rule.
    local f = assert(io.open(ROOT .. "config_presets.lua", "r"))
    local presets_src = f:read("*a")
    f:close()
    presets_src = presets_src:gsub("\r\n", "\n")
    local n_blocks = 0
    for _, token in ipairs(CLASS_TOKENS) do
        local block = presets_src:match("ST%." .. token .. "%.defaults%s*=%s*{(.-)\n%}") or ""
        check(block ~= "", token .. ": the defaults block is found")
        n_blocks = n_blocks + 1
        check(block:find("%f[%a_]background_color") == nil,
            token .. ": the defaults block overrides no backdrop colour")
    end
    eq(n_blocks, #CLASS_TOKENS, "every class defaults block is walked")
end

--=========================================================================================
-- 2) Fresh profile: AceDB-shaped, already opaque, migration is a no-op
--=========================================================================================
-- Emulates AceDB's copyDefaults (Libs/AceDB-3.0/AceDB-3.0.lua:88-131): a NEW table per
-- defaults table, leaves copied in, and the shared class_defaults fill whatever the class
-- defaults leave absent (the profile-level '**' pass, :121-123).
local function fill_missing(dest, src)
    for k, v in pairs(src) do
        if k ~= "**" then
            if type(v) == "table" then
                if type(dest[k]) ~= "table" then dest[k] = {} end
                fill_missing(dest[k], v)
            elseif dest[k] == nil then
                dest[k] = v
            end
        end
    end
end

local function fresh_class_row(token)
    local row = {}
    fill_missing(row, ST[token].defaults)   -- class defaults win
    fill_missing(row, ST.class_defaults)    -- shared defaults fill the rest
    for _, hand in ipairs(HANDS) do
        if type(row[hand]) == "table" then
            fill_missing(row[hand], ST.bar_defaults)
        end
    end
    return row
end

local function fresh_profile()
    local profile = {}
    for _, token in ipairs(CLASS_TOKENS) do
        profile[token] = fresh_class_row(token)
    end
    return profile
end

do
    local profile = fresh_profile()
    local hunter = profile.HUNTER
    check(type(hunter) == "table", "the fresh profile carries a HUNTER row")
    for _, hand in ipairs(HANDS) do
        local row = hunter[hand]
        check(type(row) == "table", "fresh HUNTER." .. hand .. " exists")
        check(type(row) == "table" and colors_equal(row.background_color, NEW_DEFAULT),
            "fresh HUNTER." .. hand .. " backdrop is opaque")
    end
    check(colors_equal(profile.PALADIN.mainhand.background_color, NEW_DEFAULT),
        "fresh PALADIN.mainhand backdrop is opaque")

    -- AceDB copies into a NEW table: the profile must never alias the defaults table, or
    -- a user colour pick would rewrite the shipped default for the rest of the session.
    check(hunter.mainhand.background_color ~= ST.bar_defaults.background_color,
        "the profile colour is a copy, not an alias of ST.bar_defaults")
    hunter.mainhand.background_color[4] = 0.5
    eq(ST.bar_defaults.background_color[4], 1.0,
        "mutating a profile colour leaves the shipped default alone")
    hunter.mainhand.background_color[4] = 1.0

    local raised = ST.migrate_appearance_defaults(profile)
    eq(raised, 0, "the migration raises nothing on a fresh profile")
    eq(profile.appearance_defaults_213, true, "the migration marks a fresh profile done")
    for _, token in ipairs(CLASS_TOKENS) do
        for _, hand in ipairs(HANDS) do
            local row = profile[token][hand]
            if type(row) == "table" then
                check(colors_equal(row.background_color, NEW_DEFAULT),
                    "fresh " .. token .. "." .. hand .. " stays opaque after the migration")
            end
        end
    end
end

--=========================================================================================
-- 3) Migration: only the exact old default moves; every other colour is preserved
--=========================================================================================
local function profile_with(rows)
    -- rows: { TOKEN = { hand = { background_color = {...}, theme_preset = ... } } }
    local profile = {}
    for token, hands in pairs(rows) do
        profile[token] = {}
        for hand, spec in pairs(hands) do
            profile[token][hand] = {
                background_color = spec.color,
                theme_preset = spec.preset,
            }
        end
    end
    return profile
end

do
    -- (a) the untouched old default on every hand of two classes: all raised.
    local profile = profile_with({
        HUNTER = {
            mainhand = { color = { 0.0, 0.0, 0.0, 0.85 } },
            offhand = { color = { 0.0, 0.0, 0.0, 0.85 } },
            ranged = { color = { 0.0, 0.0, 0.0, 0.85 } },
        },
        ROGUE = {
            mainhand = { color = { 0.0, 0.0, 0.0, 0.85 } },
            offhand = { color = { 0.0, 0.0, 0.0, 0.85 } },
        },
    })
    local raised = ST.migrate_appearance_defaults(profile)
    eq(raised, 5, "five untouched old defaults are raised")
    for _, token in ipairs({ "HUNTER", "ROGUE" }) do
        for _, hand in ipairs(HANDS) do
            local row = profile[token][hand]
            if type(row) == "table" then
                check(colors_equal(row.background_color, NEW_DEFAULT),
                    token .. "." .. hand .. " old default became opaque black")
            end
        end
    end
    eq(profile.appearance_defaults_213, true, "the run marks the profile")

    -- (b) custom colours are preserved - the user's pick AND every preset colour.
    local customs = {
        { name = "midnight preset", color = { 15, 18, 25, 0.90 } },
        { name = "glass preset", color = { 20, 25, 35, 0.65 } },
        { name = "flat preset", color = { 10, 10, 10, 0.95 } },
        { name = "opaque black", color = { 0, 0, 0, 1.0 } },
        { name = "black at 0.84", color = { 0, 0, 0, 0.84 } },
        { name = "black at 0.86", color = { 0, 0, 0, 0.86 } },
        { name = "red at the old alpha", color = { 1, 0, 0, 0.85 } },
        { name = "green at the old alpha", color = { 0, 1, 0, 0.85 } },
        { name = "blue at the old alpha", color = { 0, 0, 1, 0.85 } },
        { name = "user translucent", color = { 0, 0, 0, 0.30 } },
    }
    local preserved = profile_with({})
    preserved.PALADIN = {}
    for i, custom in ipairs(customs) do
        preserved.PALADIN["hand" .. i] = { background_color = custom.color }
    end
    local raised2 = ST.migrate_appearance_defaults(preserved)
    eq(raised2, 0, "no custom colour is raised")
    for i, custom in ipairs(customs) do
        check(colors_equal(preserved.PALADIN["hand" .. i].background_color, custom.color),
            "custom colour preserved: " .. custom.name)
    end

    -- (c) an ACTIVE theme preset owns its colour: 'Classic Retro' is exactly the old
    -- default, so the preset - not the migration - must win.
    local presets_profile = profile_with({
        PALADIN = {
            mainhand = { color = { 0, 0, 0, 0.85 }, preset = "classic" },
            offhand = { color = { 15, 18, 25, 0.90 }, preset = "midnight" },
            -- A stale/unknown preset name has no colour to own the value: the untouched
            -- old default is still the old default.
            ranged = { color = { 0, 0, 0, 0.85 }, preset = "removed-preset" },
        },
    })
    local raised3 = ST.migrate_appearance_defaults(presets_profile)
    eq(raised3, 1, "only the hand with no real preset owner is raised")
    check(colors_equal(presets_profile.PALADIN.mainhand.background_color, OLD_DEFAULT),
        "an active 'Classic Retro' preset keeps its 0.85 backdrop")
    check(colors_equal(presets_profile.PALADIN.offhand.background_color, { 15, 18, 25, 0.90 }),
        "an active 'Midnight Velvet' preset keeps its 0.90 backdrop")
    check(colors_equal(presets_profile.PALADIN.ranged.background_color, NEW_DEFAULT),
        "an unknown preset name does not block the migration")
end

--=========================================================================================
-- 4) Idempotence: once per profile, and a second run changes nothing
--=========================================================================================
do
    local profile = profile_with({
        HUNTER = { mainhand = { color = { 0, 0, 0, 0.85 } } },
    })
    eq(ST.migrate_appearance_defaults(profile), 1, "first run raises the old default")
    eq(ST.migrate_appearance_defaults(profile), 0, "second run changes nothing")
    check(colors_equal(profile.HUNTER.mainhand.background_color, NEW_DEFAULT),
        "the raised value survives the second run")

    -- The flag is what makes it once-per-profile: a value re-seeded behind the flag (an
    -- old copy restored by a profile tool, say) is NOT raised on a later login.
    profile.HUNTER.mainhand.background_color = { 0.0, 0.0, 0.0, 0.85 }
    eq(ST.migrate_appearance_defaults(profile), 0, "the flag blocks a later re-run")
    check(colors_equal(profile.HUNTER.mainhand.background_color, OLD_DEFAULT),
        "a post-flag old value is left alone (the migration ran once)")
end

--=========================================================================================
-- 5) Nil-safety and corrupt saved data
--=========================================================================================
do
    for _, bad in ipairs({ false, 42, "profile", function() end }) do
        local ok, raised = pcall(ST.migrate_appearance_defaults, bad)
        check(ok, "a non-table profile does not throw (" .. type(bad) .. ")")
        eq(raised, 0, "a non-table profile migrates nothing (" .. type(bad) .. ")")
    end
    local ok_nil, raised_nil = pcall(ST.migrate_appearance_defaults, nil)
    check(ok_nil, "a nil profile does not throw")
    eq(raised_nil, 0, "a nil profile migrates nothing")

    -- Corrupt rows: a class row that is not a table, a hand that is not a table, and a
    -- colour that is not a table are all skipped - the sibling hands still migrate.
    local profile = {
        HUNTER = "corrupt",
        ROGUE = {
            mainhand = 7,
            offhand = { background_color = "black" },
            ranged = { background_color = { 0, 0, 0 } },
        },
        PALADIN = {
            mainhand = { background_color = { 0, 0, 0, 0.85 } },
        },
    }
    local ok_corrupt, raised_corrupt = pcall(ST.migrate_appearance_defaults, profile)
    check(ok_corrupt, "corrupt rows do not throw")
    eq(raised_corrupt, 1, "only the well-formed old default is raised")
    check(colors_equal(profile.PALADIN.mainhand.background_color, NEW_DEFAULT),
        "a well-formed sibling hand still migrates")
    eq(profile.appearance_defaults_213, true, "a corrupt profile is still marked done")
    eq(type(profile.ROGUE.offhand.background_color), "string",
        "a corrupt colour is left exactly as saved")

    -- An empty profile is a valid profile: nothing to raise, marked done.
    local empty = {}
    eq(ST.migrate_appearance_defaults(empty), 0, "an empty profile raises nothing")
    eq(empty.appearance_defaults_213, true, "an empty profile is marked done")
end

--=========================================================================================
-- 6) Ranged distance bar: hunter ON, every other class opt-in
--=========================================================================================
do
    -- Shipped defaults, read raw (the AceDB class_defaults fill happens at login, so the
    -- shared table must say false on its own).
    eq(ST.class_defaults.weave_range_enabled, false,
        "the shared weave_range default stays false (opt-in for other classes)")
    eq(ST.HUNTER.defaults.weave_range_enabled, true,
        "the HUNTER defaults turn the ranged distance bar ON (the operator gate)")

    -- The options getter's single source of truth: the class's own defaults.
    eq(ST.weave_range_default_enabled("HUNTER"), true, "nil hunter value reads ON")
    eq(ST.weave_range_default_enabled("hunter"), true, "the reader tolerates a lowercase token")
    for _, token in ipairs(CLASS_TOKENS) do
        if token ~= "HUNTER" then
            eq(ST.weave_range_default_enabled(token), false,
                "nil " .. token .. " value reads OFF (opt-in)")
        end
    end
    for _, bad in ipairs({ nil, 42, false, "NOT_A_CLASS" }) do
        local ok, value = pcall(ST.weave_range_default_enabled, bad)
        check(ok, "the reader does not throw on " .. type(bad))
        eq(value, false, "the reader answers OFF for an unknown token (" .. tostring(bad) .. ")")
    end

    -- The migration never touches the toggle: an appearance migration must not change
    -- which bar is enabled.
    local profile = profile_with({
        HUNTER = { mainhand = { color = { 0, 0, 0, 0.85 } } },
    })
    profile.HUNTER.weave_range_enabled = false
    ST.migrate_appearance_defaults(profile)
    eq(profile.HUNTER.weave_range_enabled, false,
        "the appearance migration leaves the weave_range toggle alone")
end

--=========================================================================================
-- 7) Wiring: set_opts runs the migration (the behavioural pin is in options_load_state)
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "option_tables.lua", "r"))
    local src = f:read("*a")
    f:close()
    src = src:gsub("\r\n", "\n")
    local _, n_calls = src:gsub("migrate_appearance_defaults", "")
    check(n_calls >= 2,
        "option_tables.lua both resolves and calls the migration (got " .. n_calls .. ")")
    local set_opts_at = src:find("function ST:set_opts()", 1, true)
    local call_at = src:find("migrate_appearance_defaults", set_opts_at or 1, true)
    check(set_opts_at ~= nil and call_at ~= nil and call_at > set_opts_at,
        "the call sits inside ST:set_opts (the seam main.lua:424 invokes after AceDB)")

    local g = assert(io.open(ROOT .. "config_presets.lua", "r"))
    local presets = g:read("*a")
    g:close()
    presets = presets:gsub("\r\n", "\n")
    local hunter_block = presets:match("ST%.HUNTER%.defaults%s*=%s*{(.-)\n%}") or ""
    check(hunter_block:find("%f[%a_]weave_range_enabled%s*=%s*true") ~= nil,
        "the HUNTER defaults block ships weave_range_enabled = true (source pin)")
    local class_block = presets:match("ST%.class_defaults%s*=%s*{(.-)\n%}") or ""
    check(class_block:find("%f[%a_]weave_range_enabled%s*=%s*false") ~= nil,
        "the shared class_defaults block ships weave_range_enabled = false (source pin)")
end

--=========================================================================================
-- 8) The REAL AceDB profile: the '**' metatable, the flag read, and the reload path
--=========================================================================================
-- Sections 2-5 build plain profile tables. That is exactly why the shipped defect (F2)
-- survived them: on a live profile the root is an AceDB table carrying the '**' defaults
-- metatable (ST.defaults.profile['**'] = ST.class_defaults; Libs/AceDB-3.0/AceDB-3.0.lua:
-- 88-107), whose __index CREATES a defaults-filled table, rawsets it on the profile and
-- returns it. `if profile[FLAG] then` was therefore truthy on the FIRST login, the
-- migration returned 0 forever, and the 2026-10-25 order (backdrop 0.85 -> 1.0) never
-- reached a saved profile. This section drives the real vendored AceDB object, so the
-- fixture cannot drift from the client's own database behaviour.
local AceDB = assert(libs["AceDB-3.0"], "the vendored AceDB-3.0 is loaded into the sandbox")
local FLAG = ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG

-- One boot/reload of the real database. `sv` is the SavedVariables table: passing the SAME
-- table back to AceDB:New is a reload (the defaults changed but AceDB only fills keys that
-- are ABSENT - which is precisely why a saved 0.85 leaf needed a migration at all).
local function ace_boot(sv)
    local db = AceDB:New(sv, ST.defaults, true)
    return db, db.profile, sv
end

local function raw_key_count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

do
    -- (a) The fixture is genuinely '**'-shaped, or nothing below would prove anything.
    local _, profile = ace_boot({})
    local root_mt = getmetatable(profile)
    check(type(root_mt) == "table" and type(root_mt.__index) == "function",
        "ACEDB: the profile root carries AceDB's '**' __index metatable")
    check(getmetatable(rawget(profile, "WARRIOR")) ~= nil,
        "ACEDB: a class row carries its own '**' metatable")
    eq(getmetatable(rawget(rawget(profile, "WARRIOR"), "mainhand")), nil,
        "ACEDB: a hand table has NO metatable (the migration's leaf reads cannot create)")
    -- The trap, on the real object: a plain read of an absent key CREATES a defaults
    -- table and rawsets it. This is the shape that killed the migration.
    eq(rawget(profile, "appearance_probe_absent"), nil, "ACEDB: the probe key starts absent")
    local created = profile.appearance_probe_absent
    check(type(created) == "table", "ACEDB: a plain read of an absent key answers a TABLE")
    check(rawget(profile, "appearance_probe_absent") == created,
        "ACEDB: that plain read PERSISTED the table on the profile (rawget sees it)")
    rawset(profile, "appearance_probe_absent", nil)

    -- (b) F2.1: the migration's flag read does not trigger the metatable, the flag write
    -- stores the plain boolean, and the migration therefore RUNS on a live profile.
    eq(rawget(profile, FLAG), nil, "ACEDB: a fresh real profile carries no migration flag")
    profile.WARRIOR.mainhand.background_color = { 0.0, 0.0, 0.0, 0.85 }
    profile.WARRIOR.offhand.background_color = { 0.0, 0.0, 0.0, 0.85 }
    profile.WARRIOR.ranged.background_color = { 0.0, 0.0, 0.0, 0.85 }
    local root_keys_before = raw_key_count(profile)
    local warrior_keys_before = raw_key_count(rawget(profile, "WARRIOR"))
    eq(ST.migrate_appearance_defaults(profile), 3,
        "ACEDB: the migration raises the saved old defaults (F2: it returned 0 forever)")
    check(colors_equal(profile.WARRIOR.mainhand.background_color, NEW_DEFAULT)
        and colors_equal(profile.WARRIOR.offhand.background_color, NEW_DEFAULT)
        and colors_equal(profile.WARRIOR.ranged.background_color, NEW_DEFAULT),
        "ACEDB: every saved 0.85 hand became opaque")

    -- F2.1: the stored marker is a plain value. A boolean is the only shape this
    -- migration writes; a table here is what the defective read created instead.
    eq(rawget(profile, FLAG), true, "ACEDB: the flag is the plain boolean true")
    eq(type(rawget(profile, FLAG)), "boolean",
        "ACEDB: the flag value is a boolean, NOT a created defaults table")
    -- No silent junk: the run adds the flag and touches nothing else at the root, and a
    -- class row never gains a hand/section the migration did not find.
    eq(raw_key_count(profile), root_keys_before + 1,
        "ACEDB: the migration adds exactly one profile-root key (the flag)")
    eq(raw_key_count(rawget(profile, "WARRIOR")), warrior_keys_before,
        "ACEDB: the migration adds no class-row key")
    eq(rawget(rawget(profile, "PALADIN"), "offhand"), nil,
        "ACEDB: a hand the class row does not carry stays ABSENT (no read created it)")
    check(getmetatable(rawget(profile, "WARRIOR")) ~= nil,
        "ACEDB: the class row still carries its metatable after the run")

    -- (c) F2.2 on the real object: only the exact untouched old default moves. A custom
    -- colour, a preset-owned old default and a near-miss alpha are all preserved.
    local _, profile_c = ace_boot({})
    profile_c.ROGUE.mainhand.background_color = { 15, 18, 25, 0.90 }
    profile_c.ROGUE.offhand.background_color = { 0.0, 0.0, 0.0, 0.85 }
    profile_c.ROGUE.offhand.theme_preset = "classic" -- ships exactly {0,0,0,0.85}
    profile_c.ROGUE.ranged.background_color = { 0.0, 0.0, 0.0, 0.86 }
    eq(ST.migrate_appearance_defaults(profile_c), 0,
        "ACEDB: a custom colour, a preset-owned old default and a near-miss are untouched")
    check(colors_equal(profile_c.ROGUE.mainhand.background_color, { 15, 18, 25, 0.90 }),
        "ACEDB: the custom colour is preserved")
    check(colors_equal(profile_c.ROGUE.offhand.background_color, OLD_DEFAULT),
        "ACEDB: the active 'Classic Retro' preset keeps its 0.85 backdrop")
    check(colors_equal(profile_c.ROGUE.ranged.background_color, { 0.0, 0.0, 0.0, 0.86 }),
        "ACEDB: a near-miss alpha is not touched")
    -- The same stored colour with NO preset owner: the old default is raised (a separate
    -- profile - the first one is already marked done, which is the next check).
    local _, profile_c2 = ace_boot({})
    profile_c2.ROGUE.offhand.background_color = { 0.0, 0.0, 0.0, 0.85 }
    eq(ST.migrate_appearance_defaults(profile_c2), 1,
        "ACEDB: an un-owned old default on the same row migrates")
    check(colors_equal(profile_c2.ROGUE.offhand.background_color, NEW_DEFAULT),
        "ACEDB: the un-owned old default became opaque")

    -- (d) F2.3 + the reason the migration exists: AceDB keeps a saved 0.85 across a
    -- reload onto the new defaults, and the flag makes the raise once-per-profile.
    local _, profile_old, sv_old = ace_boot({})
    profile_old.HUNTER.mainhand.background_color = { 0.0, 0.0, 0.0, 0.85 }
    local _, profile_reload = ace_boot(sv_old)
    eq(profile_reload.HUNTER.mainhand.background_color[4], 0.85,
        "ACEDB: a reload onto the new defaults KEEPS the saved 0.85 (why F2 mattered)")
    eq(rawget(profile_reload, FLAG), nil, "ACEDB: the reloaded profile starts unmarked")
    eq(ST.migrate_appearance_defaults(profile_reload), 1,
        "ACEDB: the fixed build raises the saved old default after the reload")
    eq(profile_reload.HUNTER.mainhand.background_color[4], 1.0,
        "ACEDB: the reloaded hand is opaque")
    -- A second login over the same SavedVariables: the flag is a real saved boolean and
    -- the migration is a no-op.
    local _, profile_second = ace_boot(sv_old)
    eq(rawget(profile_second, FLAG), true,
        "ACEDB: the flag survives the reload as the plain boolean true")
    eq(profile_second.HUNTER.mainhand.background_color[4], 1.0,
        "ACEDB: the raised value survives the reload")
    eq(ST.migrate_appearance_defaults(profile_second), 0,
        "ACEDB: a second login returns 0 (once per profile)")
    -- Re-seeding an old default behind the flag is not raised again.
    profile_second.HUNTER.mainhand.background_color = { 0.0, 0.0, 0.0, 0.85 }
    eq(ST.migrate_appearance_defaults(profile_second), 0,
        "ACEDB: the saved flag blocks a later re-run")

    -- (e) THE POLLUTED FLAG. The defective build's read left a created defaults table at
    -- the flag key in every session it ran (AceDB strips it on the logout that follows,
    -- but a profile tool / hand-copied SavedVariables / a client that skips the handler
    -- can hand one back). A table is not a run marker: the defective code returned 0
    -- BEFORE its own write, so it never marked anything. A truthy test would leave those
    -- profiles at 0.85 forever - the same silent failure in a new shape.
    local _, profile_p = ace_boot({})
    profile_p.WARRIOR.mainhand.background_color = { 0.0, 0.0, 0.0, 0.85 }
    local junk = profile_p[FLAG] -- exactly what config.lua:162 did before the fix
    eq(type(junk), "table", "ACEDB: the pre-fix read creates a table at the flag key")
    eq(type(rawget(profile_p, FLAG)), "table", "ACEDB: and persists it on the profile")
    eq(ST.migrate_appearance_defaults(profile_p), 1,
        "ACEDB: a created table is NOT a run marker - the migration still raises the default")
    eq(rawget(profile_p, FLAG), true,
        "ACEDB: the run REPLACES the junk table with the plain true")
    eq(profile_p.WARRIOR.mainhand.background_color[4], 1.0,
        "ACEDB: the polluted profile finally gets the 2026-10-25 order")

    -- (f) ONE LEVEL DOWN: the class-row read has the same trap shape (the class row carries
    -- its own '**' = ST.bar_defaults metatable). A row a profile does not carry must stay
    -- ABSENT - a plain profile[token] read would create a defaults-filled row through
    -- '__index' and persist it.
    local _, profile_r = ace_boot({})
    rawset(profile_r, "MAGE", nil) -- e.g. a profile restored without that class row
    eq(rawget(profile_r, "MAGE"), nil, "ACEDB: the removed class row starts absent")
    local r_keys_before = raw_key_count(profile_r)
    eq(ST.migrate_appearance_defaults(profile_r), 0,
        "ACEDB: a profile without a class row still migrates (nothing to raise)")
    eq(rawget(profile_r, "MAGE"), nil,
        "ACEDB: the migration did NOT recreate the absent class row")
    eq(raw_key_count(profile_r), r_keys_before + 1,
        "ACEDB: it added the flag key and nothing else")
end


print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
