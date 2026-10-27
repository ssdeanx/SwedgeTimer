-- tests/appearance_defaults_state.lua: offline pins for the appearance/defaults side of
-- the 2026-10-25 operator orders - (1) the bar BACKDROP ships opaque and a one-time
-- migration raises only an untouched old default, (2) the ranged distance bar defaults ON
-- for hunters and stays opt-in for every other class.
--
-- Loads the REAL config_presets.lua and config.lua in a sandbox (LibStub/AceAddon and the
-- st.debug trailer are the only things they touch at load) and drives
-- ST.migrate_appearance_defaults over profile fixtures shaped the way AceDB leaves them
-- (Libs/AceDB-3.0/AceDB-3.0.lua:88-131: one fresh table per defaults table, leaves
-- copied in - never an alias of the defaults table).
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
--      other class.
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
local env = setmetatable({}, { __index = _G })
env.LibStub = function(major)
    if major == "AceAddon-3.0" then return { GetAddon = function() return ST end } end
    return {}
end
for _, path in ipairs({ "config_presets.lua", "config.lua" }) do
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
    check(colors_equal(ST.bar_defaults.bar_color_default, { 93, 58, 207, 0.85 }),
        "the coloured progress FILL keeps its colour and alpha (not the operator's target)")
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

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
