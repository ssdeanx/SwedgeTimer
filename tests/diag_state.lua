-- tests/diag_state.lua: offline tests for diag.lua (the print-only diagnostic report).
--
-- diag.lua is pure (no WoW API, no frames), so it is loaded into a plain sandbox and
-- exercised directly. This suite pins:
--   * it never throws: nil/garbage self, empty namespace, missing LibStub, absent or
--     throwing printers, hostile metatables - and it always emits at least the login line;
--   * "?" for every unknown (family, iface, version, engine, lrc, lcd, ldb, flags, guide
--     profile);
--   * the fields of the one-line login form and of the verbose extra lines, exactly;
--   * the fixed output cap and the numeric fallback when MAX_LINES is junk;
--   * the secrets line: api=no without C_Secrets (and for a non-table C_Secrets), api=yes
--     with the six restriction probes rendered true/false/?, including a throwing probe
--     and a hostile C_Secrets metatable;
--   * the ticks line: "?" sites in a default OFF session, the per-site counts and the
--     seconds attribution after wrap_onupdate ran with the profile gate on, the on=yes/no
--     marker, and a junk tick_sites never throwing;
--   * wrap_onupdate: the disabled gate returns the original function object untouched
--     (flat-zero overhead), the enabled gate counts per hand, passes elapsed through,
--     sums st.api.get_time attribution, and degrades when the clock is absent;
--   * family rendering for all eight compat families and the three swing-engine modes;
--   * the guide summary for all six provider classes (on/off/none/?) and the provider
--     count;
--   * the ids section: UNRESOLVED without an api, resolved name/icon/cast/known with a
--     stub api, throwing/partial probes degrade, and cap truncation with a +N count line;
--   * the error ring: record/install/chaining/restore never throw, the ring is bounded,
--     the verbose report prints newest-last and truncates inside MAX_LINES, login stays
--     one line, and the two empty states are distinguishable (F1: "nothing threw" with
--     the handler installed vs "nothing was watched" without it);
--   * the printer fallback (F3): an absent or shadowed global print hands the report to
--     the addon's chat printer and announces the switch once;
--   * static wiring: main.lua's init report call, the /st diag route, the OnUpdate hook
--     line's st.diag.wrap_onupdate gate, the engine tokens, addon_version exposure,
--     init_deadline_fired, diag.lua's purity, and its TOC placement.
-- Run from the repo root: lua5.1 tests/diag_state.lua  (any cwd works).

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
local function contains(text, needle, label)
    check(type(text) == "string" and text:find(needle, 1, true) ~= nil,
        label .. "  (expected '" .. tostring(needle) .. "' in '" .. tostring(text) .. "')")
end
local function read(path)
    local f = assert(io.open(ROOT .. path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

--=========================================================================================
-- Sandbox
--=========================================================================================
local captured = {}

local function capture_line(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    captured[#captured + 1] = table.concat(parts, "\t")
end

-- A copy of the global environment with env._G = env, so a probe that nils a global cannot
-- leak into the harness and vice versa.
local function make_env()
    local env = {}
    for k, v in pairs(_G) do
        env[k] = v
    end
    env._G = env
    return env
end

-- Loads diag.lua into a fresh sandbox.
-- opts.print: print replacement; nil = the line-capture function, false = no printer.
-- opts.libstub: LibStub replacement; nil = no LibStub global at all.
-- opts.st: namespace table to load into (default: a fresh table).
local function load_diag(opts)
    opts = opts or {}
    local env = make_env()
    if opts.print == nil then
        env.print = capture_line
    else
        env.print = opts.print
    end
    if opts.libstub ~= nil then
        env.LibStub = opts.libstub
    end
    local st = opts.st or {}
    local chunk = assert(loadfile(ROOT .. "diag.lua"))
    setfenv(chunk, env)
    chunk("SwedgeTimer", st)
    return st, env
end

-- Runs report and returns (ok, err); `captured` holds the printed lines afterwards.
local function run_report(st, self, verbose)
    captured = {}
    return pcall(st.diag.report, self, verbose)
end

--=========================================================================================
-- Fixtures
--=========================================================================================
local function provider()
    return { gather = function() end, evaluate = function() end }
end

local function healthy_self()
    return {
        addon_version = "9.9.9",
        swing_engine = "vendored-lib",
        stl_ready = true,
        llm_ready = false,
        lrc_ready = true,
        lrc_unavailable = false,
        init_deadline_fired = false,
        interfaces_are_initialised = true,
        db = {
            profile = {
                PALADIN = { nextaction_enabled = true },
                WARRIOR = { nextaction_enabled = false },
                DRUID = { nextaction_enabled = true },
                SHAMAN = { nextaction_enabled = false },
                HUNTER = {},
                ROGUE = {},
            },
        },
        PALADIN = { guide = provider() },
        WARRIOR = { guide = provider() },
        DRUID = { guide = provider() },
        SHAMAN = { guide = provider() },
        HUNTER = { guide = provider() },
        ROGUE = { guide = provider() },
    }
end

local function healthy_st()
    return {
        family = "WRATH",
        interface_number = 38002,
        practice_ui = {},
        hud = {},
        rotation_text = {},
        designmode = {},
        ldb = { obj = {} },
    }
end

local HEALTHY_LINE = table.concat({
    "SwedgeTimer diag: family=WRATH iface=38002 version=9.9.9 engine=vendored-lib",
    "lrc=ready lcd=absent ldb=object",
    "guides=PALADIN:on WARRIOR:off DRUID:on SHAMAN:off HUNTER:on ROGUE:on",
}, " ")

--=========================================================================================
-- 1. Module shape and idempotent load
--=========================================================================================
do
    local st = load_diag()
    check(type(st.diag) == "table", "diag.lua defines st.diag")
    check(type(st.diag.report) == "function", "st.diag.report is a function")
    check(type(st.diag.MAX_LINES) == "number" and st.diag.MAX_LINES >= 3,
        "diag.MAX_LINES is a number of at least 3 lines")
    check(st.diag.sink == nil, "no test sink is installed by default (production uses print)")
    local again = load_diag({ st = st })
    check(again.diag == st.diag, "loading diag.lua twice keeps the same st.diag table")
end

--=========================================================================================
-- 2. The healthy login form: one line, exact fields
--=========================================================================================
do
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local self = healthy_self()
    local ok = run_report(st, self, false)
    check(ok, "report(self) does not throw on a fully populated state")
    eq(#captured, 1, "the login form prints exactly one line")
    eq(captured[1], HEALTHY_LINE, "the login line matches the exact expected field list")
    contains(captured[1], "SwedgeTimer diag:", "the report is prefixed for chat identification")
end

--=========================================================================================
-- 3. Never throws; "?" for unknowns
--=========================================================================================
do
    local st = load_diag()
    local ok = run_report(st, nil, false)
    check(ok, "report(nil) does not throw")
    eq(#captured, 1, "report(nil) still prints the login line")
    contains(captured[1], "family=?", "empty state: family renders ?")
    contains(captured[1], "iface=?", "empty state: interface renders ?")
    contains(captured[1], "version=?", "empty state: version renders ?")
    contains(captured[1], "engine=?", "empty state: engine renders ?")
    contains(captured[1], "lrc=?", "empty state: LibRangeCheck renders ?")
    contains(captured[1], "lcd=?", "empty state: LibClassicDurations renders ?")
    contains(captured[1], "ldb=?", "empty state: LibDataBroker renders ?")
    for _, class in ipairs({ "PALADIN", "WARRIOR", "DRUID", "SHAMAN", "HUNTER", "ROGUE" }) do
        contains(captured[1], class .. ":none", "empty state: " .. class .. " has no provider")
    end

    check(run_report(st, false, false), "report(false) does not throw")
    check(run_report(st, "garbage", false), "report('garbage') does not throw")
    check(run_report(st, 0, false), "report(0) does not throw")
    check(run_report(st, {}, true), "report({}) verbose does not throw")
end

do
    local st = load_diag()
    local self = {
        addon_version = function() end,
        swing_engine = {},
        db = "junk",
        PALADIN = { guide = provider() },
    }
    check(run_report(st, self, false), "report with garbage field types does not throw")
    contains(captured[1], "version=?", "a function version renders ?")
    contains(captured[1], "engine=?", "a table engine renders ?")
    contains(captured[1], "PALADIN:?", "a provider with an unreadable profile renders ?")

    local module = {
        PALADIN = { guide = { gather = function() end } }, -- evaluate missing
        db = { profile = { PALADIN = {} } },
    }
    check(run_report(st, module, false), "report with an incomplete provider does not throw")
    contains(captured[1], "PALADIN:none", "a provider without evaluate() counts as none")

    local st2 = load_diag()
    st2.family = {}
    st2.interface_number = function() end
    check(run_report(st2, {}, false), "report with garbage namespace fields does not throw")
    contains(captured[1], "family=?", "a table family renders ?")
    contains(captured[1], "iface=?", "a function interface renders ?")
end

--=========================================================================================
-- 4. Read-only: a strict metatable must never see a method call
--=========================================================================================
do
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local self = setmetatable(healthy_self(), {
        __index = function() error("diag must never call a self method") end,
    })
    local ok = run_report(st, self, false)
    check(ok, "report against a strict self does not throw")
    eq(captured[1], HEALTHY_LINE, "strict self: no method call was attempted (exact line)")
end

--=========================================================================================
-- 5. Printer robustness
--=========================================================================================
do
    local st = load_diag({ print = false })
    check(run_report(st, healthy_self(), false), "an absent print global does not throw")
    check(run_report(st, healthy_self(), true), "an absent print global: verbose does not throw")

    -- F3 (deep audit 2026-10-19): the global print was the report's only output path,
    -- so a client (or another addon) that removed it made the whole report vanish
    -- silently. The fallback is the addon's own chat printer, and the switch is
    -- announced once.
    local chat = {}
    local st_fb = load_diag({ print = false, st = healthy_st(), libstub = function() return nil end })
    st_fb.utils = {
        print_msg = function(msg) chat[#chat + 1] = tostring(msg) end,
    }
    check(run_report(st_fb, healthy_self(), false), "F3: a report without a global print does not throw")
    check(#chat > 0, "F3: the report falls back to the addon's chat printer")
    contains(chat[1], "the global print is unavailable",
        "F3: the fallback announces that it took over")
    eq(#chat, 2, "F3: the fallback announces the switch once, then prints the line")
    contains(chat[2], HEALTHY_LINE, "F3: the fallback prints the whole report line")
    check(run_report(st_fb, healthy_self(), false), "F3: a second report without a global print does not throw")
    eq(#chat, 3, "F3: the fallback is announced only once per session")

    -- A broken (non-function) print is the same case: the fallback takes over.
    local chat2 = {}
    local st_brk = load_diag({ print = "not a function", st = healthy_st(), libstub = function() return nil end })
    st_brk.utils = {
        print_msg = function(msg) chat2[#chat2 + 1] = tostring(msg) end,
    }
    check(run_report(st_brk, healthy_self(), false), "F3: a non-function print does not throw")
    check(#chat2 > 0, "F3: a shadowed print falls back to the chat printer too")

    -- No fallback available at all: degrade to silence, never to an error.
    local st_none = load_diag({ print = false, st = healthy_st(), libstub = function() return nil end })
    check(run_report(st_none, healthy_self(), false),
        "F3: with neither print nor a chat printer the report degrades to silence")

    st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st.diag.sink = function() error("broken sink") end
    check(run_report(st, healthy_self(), false), "a throwing sink does not throw")

    st.diag.sink = function(text) captured[#captured + 1] = "sink:" .. text end
    local ok = run_report(st, healthy_self(), false)
    check(ok and captured[1] == "sink:" .. HEALTHY_LINE,
        "the sink hook receives the login line when installed")
end

--=========================================================================================
-- 6. Families (all eight compat families) and the three swing-engine modes
--=========================================================================================
do
    local families = { "ERA", "TBC", "WRATH", "CATA", "MISTS", "RETAIL", "FOREVER", "UNKNOWN" }
    for i = 1, #families do
        local st = load_diag()
        st.family = families[i]
        check(run_report(st, {}, false), "family " .. families[i] .. ": report does not throw")
        contains(captured[1], "family=" .. families[i], "family " .. families[i] .. " renders")
    end

    local engines = { "vendored-lib", "forever-source", "inert-standin" }
    for i = 1, #engines do
        local st = load_diag()
        check(run_report(st, { swing_engine = engines[i] }, false),
            "engine " .. engines[i] .. ": report does not throw")
        contains(captured[1], "engine=" .. engines[i], "engine " .. engines[i] .. " renders")
    end
end

--=========================================================================================
-- 7. LibRangeCheck / LibClassicDurations / LibDataBroker states
--=========================================================================================
do
    local st = load_diag()
    check(run_report(st, { lrc_ready = true, lrc_unavailable = false }, false),
        "lrc ready: no throw")
    contains(captured[1], "lrc=ready", "lrc_ready without the deadline renders ready")
    check(run_report(st, { lrc_ready = true, lrc_unavailable = true }, false),
        "lrc fallback: no throw")
    contains(captured[1], "lrc=fallback", "the deadline fallback renders fallback")
    check(run_report(st, { lrc_ready = false, lrc_unavailable = false }, false),
        "lrc pending: no throw")
    contains(captured[1], "lrc=?", "a pending LibRangeCheck renders ?")

    st = load_diag({ libstub = function(major)
        if major == "LibClassicDurations" then
            return {}
        end
        return nil
    end })
    check(run_report(st, {}, false), "lcd present: no throw")
    contains(captured[1], "lcd=present", "a registered LibClassicDurations renders present")

    st = load_diag({ libstub = function() return nil end })
    check(run_report(st, {}, false), "lcd absent: no throw")
    contains(captured[1], "lcd=absent", "an unregistered LibClassicDurations renders absent")

    st = load_diag({ libstub = function() error("LibStub exploded") end })
    check(run_report(st, {}, false), "lcd erroring LibStub: no throw")
    contains(captured[1], "lcd=?", "a throwing LibStub renders ?")

    st = load_diag()
    st.ldb = { obj = {} }
    check(run_report(st, {}, false), "ldb object: no throw")
    contains(captured[1], "ldb=object", "a created LibDataBroker object renders object")
    st.ldb = { init_attempted = true }
    check(run_report(st, {}, false), "ldb absent: no throw")
    contains(captured[1], "ldb=absent", "a failed creation attempt renders absent")
    st.ldb = {}
    check(run_report(st, {}, false), "ldb pending: no throw")
    contains(captured[1], "ldb=pending", "an un-attempted lazy init renders pending")
    st.ldb = nil
    check(run_report(st, {}, false), "ldb missing module: no throw")
    contains(captured[1], "ldb=?", "a missing ldb module renders ?")
end

--=========================================================================================
-- 8. Guides: per-class on/off/none/? and the provider count
--=========================================================================================
do
    local st = load_diag()
    local self = healthy_self()
    check(run_report(st, self, false), "healthy guides: no throw")
    contains(captured[1], "guides=PALADIN:on WARRIOR:off DRUID:on SHAMAN:off HUNTER:on ROGUE:on",
        "all six guide states render in provider order")
    local expected = {
        PALADIN = "on", WARRIOR = "off", DRUID = "on", SHAMAN = "off", HUNTER = "on",
        ROGUE = "on",
    }
    for class, state in pairs(expected) do
        contains(captured[1], class .. ":" .. state, class .. " renders " .. state)
    end

    -- A class whose module did not load its provider.
    self = healthy_self()
    self.SHAMAN = {}
    check(run_report(st, self, true), "missing provider: no throw")
    contains(captured[1], "SHAMAN:none", "a missing provider renders none")
    contains(captured[3], "providers=5/6", "the provider count drops with a missing provider")

    -- ROGUE absent degrades the same way: none in the guide summary, count 5/6.
    self = healthy_self()
    self.ROGUE = {}
    check(run_report(st, self, true), "rogue missing provider: no throw")
    contains(captured[1], "ROGUE:none", "a missing ROGUE provider renders none")
    contains(captured[3], "providers=5/6", "the provider count drops with ROGUE absent")

    -- A provider present, but no profile table for it.
    self = healthy_self()
    self.db.profile.WARRIOR = nil
    check(run_report(st, self, false), "missing profile: no throw")
    contains(captured[1], "WARRIOR:?", "a provider without a readable profile renders ?")

    -- nextaction_enabled = nil counts as on (nextaction_ui's ~= false gate).
    self = healthy_self()
    self.db.profile.HUNTER = { nextaction_enabled = nil }
    check(run_report(st, self, false), "nil nextaction_enabled: no throw")
    contains(captured[1], "HUNTER:on", "nil nextaction_enabled counts as on")

    -- No providers at all.
    check(run_report(st, {}, true), "no providers: no throw")
    contains(captured[3], "providers=0/6", "the provider count is 0/6 with no class modules")
end

--=========================================================================================
-- 9. Verbose form: the extra lines and the cap
--=========================================================================================
do
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local self = healthy_self()

    check(run_report(st, self, false), "non-verbose: no throw")
    local login_line = captured[1]
    eq(#captured, 1, "non-verbose: exactly one line")

    check(run_report(st, self, true), "verbose: no throw")
    eq(#captured, 73, "verbose: exactly 73 lines (5 base + 67 ids + 1 errors-none)")
    eq(captured[1], login_line, "verbose: line 1 is the same login line")
    eq(captured[2],
        "SwedgeTimer diag: flags stl_ready=true llm_ready=false lrc_ready=true "
        .. "lrc_unavailable=false deadline=no init=yes",
        "verbose line 2 is the exact readiness-flag line")
    eq(captured[3],
        "SwedgeTimer diag: modules practice=yes hud=yes rotation=yes design=yes providers=6/6",
        "verbose line 3 is the exact module/provider line")
    eq(captured[4],
        "SwedgeTimer diag: ticks on=no mainhand=? offhand=? ranged=? cpu=?",
        "verbose line 4 is the exact ticks line (default OFF session: no counters installed)")
    eq(captured[5],
        "SwedgeTimer diag: secrets api=no",
        "verbose line 5 is the exact secrets line (no C_Secrets in this sandbox)")
    contains(captured[6], "SwedgeTimer diag: ids ", "verbose line 6 opens the ids section")
    contains(captured[72], "SwedgeTimer diag: ids 60052", "verbose: last wanted id (60052) renders")
    eq(captured[73], "SwedgeTimer diag: errors not observed (no error handler installed)",
        "verbose line 73 reports that no error handler was installed (F1)")

    self = healthy_self()
    self.init_deadline_fired = true
    check(run_report(st, self, true), "verbose with the deadline fired: no throw")
    contains(captured[2], "deadline=fired", "the fired init deadline is reported")

    check(run_report(st, {}, true), "verbose over an empty state: no throw")
    eq(#captured, 73, "verbose over an empty state still prints 73 lines")
    contains(captured[2], "stl_ready=? llm_ready=? lrc_ready=? lrc_unavailable=?",
        "unset readiness flags render ?")
    contains(captured[2], "deadline=no init=no", "empty state: deadline/init render no")

    local empty_st = load_diag()
    run_report(empty_st, {}, true)
    contains(captured[3], "practice=no hud=no rotation=no design=no",
        "unloaded UI modules render no")
    contains(captured[3], "providers=0/6", "an empty namespace has no providers")

    -- The hard cap: the report must never exceed MAX_LINES, and MAX_LINES must fall back
    -- to a safe default when it is not a number.
    st.diag.MAX_LINES = 1
    check(run_report(st, healthy_self(), true), "capped verbose: no throw")
    eq(#captured, 1, "MAX_LINES = 1 caps the verbose report at one line")
    st.diag.MAX_LINES = 2
    run_report(st, healthy_self(), true)
    eq(#captured, 2, "MAX_LINES = 2 caps the verbose report at two lines")
    st.diag.MAX_LINES = 6
    run_report(st, healthy_self(), true)
    eq(#captured, 6, "MAX_LINES = 6 truncates ids with an explicit +N count line")
    contains(captured[6], "+67 more (cap 6)", "ids truncation carries the remaining count")
    st.diag.MAX_LINES = "junk"
    run_report(st, healthy_self(), true)
    eq(#captured, 73, "a non-numeric MAX_LINES falls back to the default cap")
    st.diag.MAX_LINES = 85
end

--=========================================================================================
-- 10. The secrets line: C_Secrets absent, present, and hostile
--=========================================================================================
do
    -- Absent (every classic client, and the offline harness): api=no, no probes touched.
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    check(run_report(st, healthy_self(), true), "no C_Secrets: verbose does not throw")
    eq(#captured, 73, "no C_Secrets: verbose still prints 73 lines")
    eq(captured[5], "SwedgeTimer diag: secrets api=no",
        "no C_Secrets: the secrets line reports api=no")

    -- Present: readable booleans render true/false; a throwing probe, a non-boolean
    -- probe and a missing probe all render ?.
    local st2, env2 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    env2.C_Secrets = {
        HasSecretRestrictions = function() return true end,
        ShouldCooldownsBeSecret = function() return false end,
        ShouldAurasBeSecret = function() error("probe exploded") end,
        ShouldUnitPowerBeSecret = function(unit) return unit == "player" end,
        ShouldUnitStatsBeSecret = function() return "junk" end,
        -- ShouldUnitSpellCastingBeSecret missing on purpose.
    }
    check(run_report(st2, healthy_self(), true), "C_Secrets present: verbose does not throw")
    eq(captured[5],
        "SwedgeTimer diag: secrets api=yes restrictions=true cd=false aura=? power=true stats=? cast=?",
        "the secrets line renders api=yes and every predicate (readable/missing/throwing)")

    -- Non-table C_Secrets (a broken global) must degrade to api=no, never error.
    local st3, env3 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    env3.C_Secrets = "junk"
    check(run_report(st3, healthy_self(), true), "non-table C_Secrets: verbose does not throw")
    eq(captured[5], "SwedgeTimer diag: secrets api=no",
        "a non-table C_Secrets renders api=no")

    -- A hostile C_Secrets whose probe access throws: every probe renders ?.
    local st4, env4 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    env4.C_Secrets = setmetatable({}, {
        __index = function() error("hostile C_Secrets") end,
    })
    check(run_report(st4, healthy_self(), true), "hostile C_Secrets: verbose does not throw")
    eq(captured[5],
        "SwedgeTimer diag: secrets api=yes restrictions=? cd=? aura=? power=? stats=? cast=?",
        "a hostile C_Secrets renders ? for every probe")
end

--=========================================================================================
-- 11. Per-tick counters: wrap_onupdate and the ticks line
--=========================================================================================
do
    local original = function(elapsed) end

    -- Disabled gate: every non-true value (nil default, false, junk) installs the original
    -- function object untouched - the hook is byte-identical and adds zero per-tick cost.
    local st = load_diag()
    check(st.diag.wrap_onupdate({}, "mainhand", original) == original,
        "wrap_onupdate without a profile gate returns the original function")
    check(st.diag.wrap_onupdate({ db = { profile = {} } }, "mainhand", original) == original,
        "wrap_onupdate with an unset gate returns the original function")
    check(st.diag.wrap_onupdate(
            { db = { profile = { diag_tick_counters = false } } }, "mainhand", original) == original,
        "wrap_onupdate with the gate false returns the original function")
    check(st.diag.wrap_onupdate(
            { db = { profile = { diag_tick_counters = "yes" } } }, "mainhand", original) == original,
        "wrap_onupdate with a non-boolean gate returns the original function")
    check(st.diag.wrap_onupdate({}, "mainhand", nil) == nil,
        "wrap_onupdate passes through a missing original")
    eq(next(st.diag.tick_sites), nil, "a default OFF session never records a tick site")
    check(run_report(st, {}, true), "verbose over an OFF session: no throw")
    eq(captured[4], "SwedgeTimer diag: ticks on=no mainhand=? offhand=? ranged=? cpu=?",
        "the OFF ticks line renders ? per site and ? cpu")
end

do
    -- Enabled gate: the wrapper counts per hand, forwards elapsed, and measures seconds
    -- through the injected st.api clock.
    local st = load_diag()
    local ran = {}
    local original = function(elapsed) ran[#ran + 1] = elapsed end
    local now = 100.0
    st.api = { get_time = function() now = now + 0.001; return now end }
    local self = { db = { profile = { diag_tick_counters = true } } }
    local mainhand = st.diag.wrap_onupdate(self, "mainhand", original)
    check(type(mainhand) == "function" and mainhand ~= original,
        "wrap_onupdate with the gate true installs a counting wrapper")
    mainhand(0.016)
    mainhand(0.017)
    mainhand(0.018)
    local offhand_local = st.diag.wrap_onupdate(self, "offhand", original)
    offhand_local(0.019)
    eq(ran[1], 0.016, "the wrapper forwards the elapsed argument to the original")
    eq(#ran, 4, "the original ran exactly once per wrapped tick")
    eq(st.diag.tick_sites.mainhand.ticks, 3,
        "the mainhand counter counts every wrapped tick")
    eq(st.diag.tick_sites.offhand.ticks, 1, "the offhand counter counts separately")
    check(type(st.diag.tick_sites.mainhand.seconds) == "number"
        and math.abs(st.diag.tick_sites.mainhand.seconds - 0.003) < 1e-9,
        "the measured seconds accumulate across the wrapped ticks")
    check(st.diag.tick_sites.ranged == nil,
        "an unwrapped hand has no tick site")

    -- The ticks line: stable labels, per-site counts, unknown hands as ?, seconds summed.
    run_report(st, self, true)
    eq(captured[4], "SwedgeTimer diag: ticks on=yes mainhand=3 offhand=1 ranged=? cpu=0.00s",
        "the ON ticks line renders the counts and the summed seconds at two decimals")
    eq(st.diag.tick_sites.mainhand.ticks, 3,
        "the report is print-only: reading it never advances a counter")
end

do
    -- Degraded attribution: no st.api clock - ticks keep counting, seconds stay unknown.
    local st = load_diag()
    local original = function() end
    local self = { db = { profile = { diag_tick_counters = true } } }
    local wrapper = st.diag.wrap_onupdate(self, "ranged", original)
    wrapper(nil)
    wrapper(nil)
    eq(st.diag.tick_sites.ranged.ticks, 2, "the counter runs without a clock")
    check(st.diag.tick_sites.ranged.seconds == nil,
        "an unmeasured clock leaves the seconds unknown, not zero")
    run_report(st, self, true)
    eq(captured[4], "SwedgeTimer diag: ticks on=yes mainhand=? offhand=? ranged=2 cpu=?",
        "without a clock the seconds render ? instead of a fake zero")
end

do
    -- Never throws: junk module state degrades to "?" rather than erroring.
    local st = load_diag()
    st.diag.tick_sites = "junk"
    check(run_report(st, {}, true), "a junk tick_sites table: verbose does not throw")
    contains(captured[4], "ticks on=no mainhand=?", "a junk tick_sites renders the ? line")
    st.diag.tick_sites = setmetatable({}, { __index = function() error("hostile") end })
    check(run_report(st, {}, true), "a hostile tick_sites metatable: verbose does not throw")
    contains(captured[4], "mainhand=?", "a hostile tick_sites renders ? per site")
end

--=========================================================================================
-- 12. Static wiring: main.lua hooks, purity, TOC placement
--=========================================================================================
do
    local main = read("main.lua")
    check(main:find("ST.addon_version = version", 1, true) ~= nil,
        "main.lua exposes the addon version for the report")
    check(main:find('"vendored-lib"', 1, true) ~= nil,
        "main.lua records the vendored-lib engine")
    check(main:find('"forever-source"', 1, true) ~= nil,
        "main.lua records the forever-source engine")
    check(main:find('"inert-standin"', 1, true) ~= nil,
        "main.lua records the inert-standin engine")
    check(main:find("init_deadline_fired = true", 1, true) ~= nil,
        "main.lua records the init deadline firing")
    check(main:find("st.diag.report(self)", 1, true) ~= nil,
        "init_libs calls the login report")
    check(main:find("st.diag.report(self, true)", 1, true) ~= nil,
        "/st diag calls the verbose report")
    check(main:find('arg == "diag"', 1, true) ~= nil,
        "main.lua handles the diag argument")
    check(main:find('if st.diag and st.diag.wrap_onupdate then', 1, true) ~= nil,
        "main.lua's OnUpdate hook line gates the counting wrapper on st.diag")
    check(main:find('st.diag.wrap_onupdate(self, hand, onupdate)', 1, true) ~= nil,
        "main.lua passes the addon self, the hand and the original to wrap_onupdate")
    check(main:find('SetScript("OnUpdate", onupdate)', 1, true) ~= nil,
        "main.lua installs the (possibly counted) onupdate as the bar frame's script")
    -- F1: the error-handler chain has one installer and one remover, both in main.lua.
    check(main:find("st.diag.install_error_handler()", 1, true) ~= nil,
        "main.lua installs the chained error handler")
    check(main:find("st.diag.uninstall_error_handler()", 1, true) ~= nil,
        "main.lua removes the chained error handler again")
    check(main:find('self:RegisterEvent("PLAYER_LOGOUT")', 1, true) ~= nil,
        "main.lua registers PLAYER_LOGOUT for the uninstall")

    local diag_src = read("diag.lua")
    check(diag_src:find("function diag.wrap_onupdate", 1, true) ~= nil,
        "diag.lua exposes the OnUpdate counting wrapper")
    check(diag_src:find('rawget(utils, "print_msg")', 1, true) ~= nil,
        "diag.lua falls back to the addon's chat printer when print is gone")
    -- Purity is checked against executable code: whole-line comments (the header explains
    -- these rules and may name them) are stripped first.
    local code_only = {}
    for line in diag_src:gmatch("[^\r\n]+") do
        if not line:match("^%s*%-%-") then
            code_only[#code_only + 1] = line
        end
    end
    local diag_code = table.concat(code_only, "\n")
    check(diag_code:find("CreateFrame") == nil, "diag.lua creates no frames")
    check(diag_code:find("GetTime") == nil, "diag.lua uses no clock")
    check(diag_code:find("RegisterEvent") == nil, "diag.lua registers no events")
    check(diag_code:find("RegisterCallback") == nil, "diag.lua registers no lib callbacks")
    check(diag_code:find("SavedVariables") == nil, "diag.lua never names SavedVariables in code")
    check(diag_code:find("DEFAULT_CHAT_FRAME") == nil, "diag.lua never touches the chat frame directly")

    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Cata.toc", "SwedgeTimer_Mists.toc",
        "SwedgeTimer_Mainline.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local diag_at = text:find("\ndiag.lua", 1, true)
        local hud_at = text:find("\nhud.lua", 1, true)
        check(diag_at ~= nil and hud_at ~= nil and hud_at < diag_at,
            tocs[i] .. " lists diag.lua after hud.lua (with the UI modules)")
    end

    -- The Cata/Mists TOCs must not ship LibClassicSwingTimerAPI: those flavors leave the
    -- library's spell tables nil (indexing errors), and main.lua falls back to the inert
    -- stand-in when the library is absent.
    for _, toc in ipairs({ "SwedgeTimer_Cata.toc", "SwedgeTimer_Mists.toc" }) do
        check(read(toc):find("LibClassicSwingTimerAPI") == nil,
            toc .. " does not ship the bits-y LibClassicSwingTimerAPI")
    end
end

--=========================================================================================
-- 13. Wanted-id resolution: UNRESOLVED, resolved, hostile, truncation
--=========================================================================================
do
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    check(run_report(st, healthy_self(), true), "ids no-api: verbose does not throw")
    eq(#captured, 73, "ids no-api: 5 base + 67 UNRESOLVED + 1 errors-none")
    contains(captured[6], "ids 1310785=UNRESOLVED", "ids no-api: first wanted id UNRESOLVED")
    contains(captured[72], "ids 60052=UNRESOLVED", "ids no-api: last wanted id UNRESOLVED")
    check(run_report(st, nil, true), "ids nil-self: verbose does not throw")
    contains(captured[6], "UNRESOLVED", "ids nil-self still degrades to UNRESOLVED")

    local st2 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st2.api = {
        GetSpellInfo = function(id)
            if id == 1310785 then
                return "Sniper Shot", nil, 999, 1500, 0, 30, id
            end
            if id == 34428 then
                error("probe exploded")
            end
            if id == 32216 then
                return "Victorious", nil, nil, "junk", 0, 0, id
            end
            return nil
        end,
        is_spell_known = function(id)
            if id == 1310785 then
                return true
            end
            if id == 32216 then
                error("known exploded")
            end
            return false
        end,
    }
    check(run_report(st2, healthy_self(), true), "ids stub-api: verbose does not throw")
    contains(captured[6], "ids 1310785 name=Sniper Shot", "resolved id renders the name")
    contains(captured[6], "icon=999", "resolved id renders the icon")
    contains(captured[6], "cast=1500", "resolved id renders the cast time")
    contains(captured[6], "known=true", "resolved id renders known=true")
    contains(captured[13], "ids 34428=UNRESOLVED", "a throwing GetSpellInfo degrades to UNRESOLVED")
    contains(captured[14], "ids 32216 name=Victorious", "partial probe still renders the name")
    contains(captured[14], "known=?", "a throwing is_spell_known renders ?")

    local st3 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st3.api = { GetSpellInfo = "junk", is_spell_known = "junk" }
    check(run_report(st3, healthy_self(), true), "ids junk-api: verbose does not throw")
    contains(captured[6], "UNRESOLVED", "a non-function GetSpellInfo degrades to UNRESOLVED")

    local st4 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st4.diag.MAX_LINES = 10
    check(run_report(st4, healthy_self(), true), "ids capped: verbose does not throw")
    eq(#captured, 10, "MAX_LINES = 10 caps at ten lines")
    contains(captured[10], "+63 more (cap 10)", "ids truncation carries the remaining count")
    st4.diag.MAX_LINES = 85

    local diag_src = read("diag.lua")
    check(diag_src:find("WANTED_IDS", 1, true) ~= nil, "diag.lua keeps the DATA-only wanted-id list")
    check(diag_src:find("bench/ids_research_2026-10-19.md", 1, true) ~= nil,
        "diag.lua cites the ids research bench file")
end

--=========================================================================================
-- 14. Error ring: record, chain/restore, bound, report prints + truncates
--=========================================================================================
do
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    check(pcall(st.diag.record_error, nil), "record nil: never throws")
    check(pcall(st.diag.record_error, {}), "record table: never throws")
    st.diag.error_ring = {}
    st.diag.record_error("first\nsecond")
    eq(st.diag.error_ring[1], "first second", "record flattens newlines to one chat line")
    st.diag.record_error(string.rep("x", 500))
    check(#st.diag.error_ring[2] <= 200, "record truncates long messages")

    st.diag.error_ring = {}
    st.diag.ERROR_MAX = 3
    st.diag.record_error("e1")
    st.diag.record_error("e2")
    st.diag.record_error("e3")
    st.diag.record_error("e4")
    st.diag.record_error("e5")
    eq(#st.diag.error_ring, 3, "the ring respects ERROR_MAX")
    eq(st.diag.error_ring[1], "e3", "the ring evicts oldest first")
    eq(st.diag.error_ring[3], "e5", "the ring keeps newest last")
    st.diag.ERROR_MAX = 8

    local st2, env2 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    check(st2.diag.install_error_handler() == false,
        "install without seterrorhandler returns false")
    local set_arg
    local prev_called = {}
    local fake_prev = function(msg) prev_called[#prev_called + 1] = msg end
    env2.seterrorhandler = function(h) set_arg = h end
    env2.geterrorhandler = function() return fake_prev end
    check(st2.diag.install_error_handler() == true, "install with fakes returns true")
    check(type(set_arg) == "function", "install sets a chained handler")
    st2.diag.error_ring = {}
    set_arg("boom")
    eq(#prev_called, 1, "the chained handler calls the previous handler")
    eq(prev_called[1], "boom", "the previous handler gets the same message")
    eq(st2.diag.error_ring[1], "boom", "the chained handler records the message")
    check(st2.diag.uninstall_error_handler() == true, "uninstall returns true")
    check(set_arg == fake_prev, "uninstall restores the previous handler")
    check(st2.diag.install_error_handler() == true, "re-install after uninstall returns true")
    st2.diag.uninstall_error_handler()

    local st3 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st3.diag.error_ring = {}
    st3.diag.record_error("err-one")
    st3.diag.record_error("err-two")
    check(run_report(st3, healthy_self(), false), "errors login: non-verbose does not throw")
    eq(#captured, 1, "errors login: non-verbose stays one line")
    check(run_report(st3, healthy_self(), true), "errors verbose: does not throw")
    contains(captured[#captured - 1], "err-one", "the ring prints oldest first")
    contains(captured[#captured], "err-two", "the ring prints newest last")

    local st4 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st4.diag.error_ring = {}
    for i = 1, 8 do
        st4.diag.record_error("e" .. tostring(i))
    end
    st4.diag.MAX_LINES = 75
    check(run_report(st4, healthy_self(), true), "errors capped: verbose does not throw")
    eq(#captured, 75, "errors truncation respects MAX_LINES")
    contains(captured[75], "+6 more (cap 75)", "errors truncation carries the remaining count")
    st4.diag.MAX_LINES = 85
end

--=========================================================================================
-- 14b. F1: the two empty states are distinguishable
--=========================================================================================
-- The chain was never installed, so "errors none" was a false negative: with no
-- handler there was nothing that could ever have been observed. The report must say
-- which of the two empty states it is - "nothing threw" (handler installed) is not
-- "nothing was watched" (no handler).
do
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st.diag.error_ring = {}
    check(run_report(st, healthy_self(), true), "F1: no handler: verbose does not throw")
    contains(captured[#captured], "errors not observed (no error handler installed)",
        "F1: without a handler the empty ring reports that nothing was watched")

    local st2, env2 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    env2.seterrorhandler = function() end
    env2.geterrorhandler = function() return nil end
    check(st2.diag.install_error_handler() == true, "F1: the handler installs with a fake client")
    eq(st2.diag._error_handler_installed, true, "F1: the install flag records the installed chain")
    st2.diag.error_ring = {}
    check(run_report(st2, healthy_self(), true), "F1: installed handler: verbose does not throw")
    contains(captured[#captured], "errors none (handler installed, nothing thrown)",
        "F1: with the handler installed the empty ring reports that nothing threw")
    check(st2.diag.uninstall_error_handler() == true, "F1: the handler uninstalls again")
    eq(st2.diag._error_handler_installed, false, "F1: the install flag is cleared by the uninstall")
    check(run_report(st2, healthy_self(), true), "F1: after the uninstall: verbose does not throw")
    contains(captured[#captured], "errors not observed (no error handler installed)",
        "F1: after the uninstall the empty ring reports that nothing is watched")
end

if failures == 0 then
    print("PASS  diag_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  diag_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
