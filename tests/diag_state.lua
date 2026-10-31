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
--   * the per-hand BAR STATE section (2026-10-28): one line per hand the class owns (the
--     addon's class_hands read, with the three-hand fallback when it is unreadable), every
--     field of a fully populated hand exactly, the offhand/ranged lines, the hunter queue
--     flags on the mainhand line only, a hidden/dimmed/unticked/stalled hand, a hostile or
--     partial frame degrading to "?", and the section's cap behaviour;
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
    -- 5 base lines + 3 BAR STATE lines (the three-hand fallback: this fixture has no
    -- class_hands) + 1 power line + 1 quarantine line + 67 ids + 1 errors-none. The
    -- per-hand section was added 2026-10-28; the power and quarantine lines were added by
    -- the publish-audit P4 pass on the same date (worst case 5+3+1+1+67+8 = 85 <= 88).
    eq(#captured, 78,
        "verbose: exactly 78 lines (5 base + 3 bars + 1 power + 1 quarantine + 67 ids + 1 errors-none)")
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
    contains(captured[6], "SwedgeTimer diag: bar mainhand", "verbose line 6 opens the bar section")
    contains(captured[8], "SwedgeTimer diag: bar ranged", "the bar section covers the three hands")
    contains(captured[9], "SwedgeTimer diag: power ", "the power line follows the bar section")
    contains(captured[10], "SwedgeTimer diag: quarantine ",
        "the quarantine line follows the power line")
    contains(captured[11], "SwedgeTimer diag: ids ", "verbose line 11 opens the ids section")
    contains(captured[77], "SwedgeTimer diag: ids 60052", "verbose: last wanted id (60052) renders")
    eq(captured[78], "SwedgeTimer diag: errors not observed (no error handler installed)",
        "verbose line 78 reports that no error handler was installed (F1)")

    self = healthy_self()
    self.init_deadline_fired = true
    check(run_report(st, self, true), "verbose with the deadline fired: no throw")
    contains(captured[2], "deadline=fired", "the fired init deadline is reported")

    check(run_report(st, {}, true), "verbose over an empty state: no throw")
    eq(#captured, 78, "verbose over an empty state still prints 78 lines")
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
    eq(#captured, 6, "MAX_LINES = 6 truncates the first section with an explicit +N count line")
    -- At cap 6 the five base lines leave one line, which the bar section owns: it prints
    -- its +N count line instead of a silent cut ("never a silent cut", diag.lua's rule).
    contains(captured[6], "+3 more (cap 6)", "the bar section carries the remaining count")
    st.diag.MAX_LINES = "junk"
    run_report(st, healthy_self(), true)
    eq(#captured, 78, "a non-numeric MAX_LINES falls back to the default cap")
    st.diag.MAX_LINES = 88
end

--=========================================================================================
-- 10. The secrets line: C_Secrets absent, present, and hostile
--=========================================================================================
do
    -- Absent (every classic client, and the offline harness): api=no, no probes touched.
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    check(run_report(st, healthy_self(), true), "no C_Secrets: verbose does not throw")
    eq(#captured, 78, "no C_Secrets: verbose still prints 78 lines")
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
-- 11b. Per-hand BAR STATE lines (2026-10-28): the silent-fault surface
--=========================================================================================
-- "/st diag works better, because it said there was no errors, meaning something was
-- missed/silent". A clean error ring proves nothing about the bars, so each owned hand gets
-- one line with the state the tick actually renders from. These pins are exact for a fully
-- populated hand and "?"-degrading for every unreadable one.
local function bar_state_fixture()
    local fill = {
        width = 135.5,
        GetWidth = function(self) return self.width end,
    }
    local visuals = { bar = fill }
    local bar_frame = {
        visible = true,
        alpha = 1.0,
        script = function() end,
        IsVisible = function(self) return self.visible end,
        IsShown = function(self) return self.visible end,
        GetAlpha = function(self) return self.alpha end,
        GetScript = function(self, kind) return kind == "OnUpdate" and self.script or nil end,
        visuals_frame = visuals,
    }
    local anchor = { bar_frame = bar_frame }
    local state = {
        anchor_frame = anchor,
        start = 100,
        speed = 2.6,
        ends_at = 102.6,
        current_progress = 0.5,
        is_full = false,
        is_paused = false,
        engine_dead = false,
        vf_width = 271,
    }
    return state, bar_frame
end

local function hand_self(className, hands)
    local self = healthy_self()
    self.player_class = className
    self.class_hands = { [className] = hands }
    self.db.profile[className] = {
        mainhand = { x = 0, y = -120 },
        offhand = { x = 0, y = -142 },
        ranged = { x = 0, y = -98 },
    }
    return self
end

do
    -- A fully populated three-hand class: every field, exact.
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st.api = { get_time = function() return 101.3 end }
    local self = hand_self("HUNTER", { "mainhand", "offhand", "ranged" })
    local mainhand, mainhand_frame = bar_state_fixture()
    -- Only the mainhand frame is mutated below; the other two hands just need a state table
    -- (the fixture returns the frame as its second value, which those two do not read).
    local offhand = bar_state_fixture()
    local ranged = bar_state_fixture()
    self.mainhand = mainhand
    self.offhand = offhand
    self.ranged = ranged
    self.HUNTER.raptor_strike_queued = false
    self.HUNTER.steady_shot_queued = true
    check(run_report(st, self, true), "populated hands: verbose does not throw")
    eq(captured[6],
        "SwedgeTimer diag: bar mainhand built=yes shown=yes why=- gate=n/a active=? win=? "
        .. "left=none src=none alpha=1.00 tick=yes start=100.00 "
        .. "speed=2.60 ends_at=102.60 now=101.30 progress=0.500 full=no paused=no dead=no "
        .. "vf_width=271.00 fill=135.50 pos=0,-120 queue=raptor:no,steady:yes",
        "the mainhand BAR STATE line carries every field, in order, with the queue flags")
    eq(captured[7],
        "SwedgeTimer diag: bar offhand built=yes shown=yes why=- gate=n/a active=? win=? "
        .. "left=none src=none alpha=1.00 tick=yes start=100.00 "
        .. "speed=2.60 ends_at=102.60 now=101.30 progress=0.500 full=no paused=no dead=no "
        .. "vf_width=271.00 fill=135.50 pos=0,-142",
        "the offhand line is the same fields with its own saved row and no queue flags")
    contains(captured[8], "bar ranged built=yes", "the ranged hand gets its own line")
    contains(captured[8], "pos=0,-98", "the ranged line reports its saved row")

    -- Hidden, dimmed, unticked, stalled: the four silent faults the operator cannot see.
    mainhand_frame.visible = false
    mainhand_frame.alpha = 0.6
    mainhand_frame.script = nil
    mainhand.current_progress = 0
    mainhand.is_full = true
    mainhand.is_paused = true
    mainhand.engine_dead = true
    self.HUNTER.raptor_strike_queued = true
    self.HUNTER.steady_shot_queued = nil
    check(run_report(st, self, true), "hidden hand: verbose does not throw")
    contains(captured[6], "shown=no", "a hidden bar reports shown=no")
    contains(captured[6], "why=?", "an unrecorded hide reason is unknown, never a guess")
    -- main.lua records the reason at the point it hides (this fixture stamps the field the
    -- same way): the line then names it instead of leaving shown=no unexplained.
    mainhand.hide_reason = "idle"
    check(run_report(st, self, true), "recorded hide reason: verbose does not throw")
    contains(captured[6], "shown=no why=idle gate=n/a",
        "a recorded hide reason renders as a token (P4-1: shown=no must say WHY)")
    contains(captured[6], "alpha=0.60", "the out-of-range dim is visible on the line")
    contains(captured[6], "tick=no", "a bar with no OnUpdate script reports tick=no")
    contains(captured[6], "progress=0.000", "a stalled bar reports progress=0.000")
    contains(captured[6], "full=yes paused=yes dead=yes", "the state flags render together")
    contains(captured[6], "queue=raptor:yes,steady:?", "an unset queue flag is unknown, not no")

    -- The hand list comes from the addon: a single-melee-hand class gets one line, not three.
    local st2 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local paladin = hand_self("PALADIN", { "mainhand" })
    paladin.mainhand = bar_state_fixture()
    check(run_report(st2, paladin, true), "single-hand class: verbose does not throw")
    eq(captured[6], "SwedgeTimer diag: bar mainhand built=yes shown=yes why=- gate=n/a "
        .. "active=? win=? left=none src=none alpha=1.00 tick=yes "
        .. "start=100.00 speed=2.60 ends_at=102.60 now=? progress=0.500 full=no paused=no "
        .. "dead=no vf_width=271.00 fill=135.50 pos=0,-120",
        "a one-hand class prints exactly one BAR STATE line")
    contains(captured[9], "ids ", "the ids section follows the single hand line")
    eq(#captured, 76, "5 base + 1 bar + power + quarantine + 67 ids + 1 errors-none")

    -- A frame that throws from every read must degrade to "?" per field, never throw.
    local st3 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local hostile = hand_self("ROGUE", { "mainhand", "offhand", "ranged" })
    local state = {
        start = 1, speed = 2, ends_at = 3,
        anchor_frame = { bar_frame = setmetatable({}, {
            __index = function() error("hostile frame") end,
        }) },
    }
    hostile.mainhand = state
    hostile.ROGUE.raptor_strike_queued = "junk"
    check(run_report(st3, hostile, true), "hostile frame: verbose does not throw")
    contains(captured[6], "bar mainhand built=no", "a frame whose reads throw renders unbuilt")
    contains(captured[6], "queue=raptor:?,steady:?", "a non-boolean queue flag renders ?")

    -- A hand with no frames at all (HU-22 lazy build) is "no" / "?", never an error.
    local st4 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local lazy = hand_self("WARRIOR", { "mainhand", "offhand", "ranged" })
    lazy.mainhand = { speed = 2.6, start = 100, ends_at = 102.6 }
    check(run_report(st4, lazy, true), "unbuilt hand: verbose does not throw")
    contains(captured[6], "bar mainhand built=no", "an unbuilt hand reports built=no")
    contains(captured[6], "shown=? why=unbuilt",
        "an unbuilt hand answers shown=? and why=unbuilt (no visibility decision ran)")
    contains(captured[6], "speed=2.60", "the seeded cycle still renders for an unbuilt hand")

    -- The section is capped like every other section: an explicit count, never a silent cut.
    local st5 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st5.diag.MAX_LINES = 6
    check(run_report(st5, healthy_self(), true), "capped bar section: verbose does not throw")
    contains(captured[6], "+3 more (cap 6)", "the capped bar section closes with its count")

    -- The saved row is read with rawget: AceDB's profile root and class rows carry a '**'
    -- metatable whose __index CREATES a defaults-filled sub-table for any missing key
    -- (Libs/AceDB-3.0/AceDB-3.0.lua:88-107). A /st diag must never write through a read -
    -- with a plain `profile[class]` this fixture would persist a phantom class row.
    local st6 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local created = 0
    local phantom_db = setmetatable({}, {
        __index = function(t, key)
            created = created + 1
            local row = setmetatable({}, {
                __index = function(row_table, hand_key)
                    created = created + 1
                    local tbl = { phantom = true }
                    rawset(row_table, hand_key, tbl)
                    return tbl
                end,
            })
            rawset(t, key, row)
            return row
        end,
    })
    -- DEMONHUNTER: a class token the guide summary does NOT iterate (only the six shipped
    -- provider classes are), so the ONLY reader of that profile key is the hand-row path
    -- under test. With rawget the key stays absent; a plain read would persist it.
    local phantom = hand_self("DEMONHUNTER", { "mainhand" })
    phantom.db.profile = phantom_db
    -- Seed the six guide rows the summary legitimately reads (the guide path is not the
    -- subject here; an absent row there is a separate, pre-existing read).
    for _, token in ipairs({ "PALADIN", "WARRIOR", "DRUID", "SHAMAN", "HUNTER", "ROGUE" }) do
        rawset(phantom_db, token, { nextaction_enabled = true })
    end
    phantom.mainhand = bar_state_fixture()
    check(run_report(st6, phantom, true), "AceDB-shaped profile: verbose does not throw")
    eq(created, 0, "the report indexes no missing profile key (rawget only, no phantom row)")
    eq(rawget(phantom_db, "DEMONHUNTER"), nil, "no class row was persisted by the report")
    contains(captured[6], "pos=?,?", "an unreadable saved row renders pos=?,?")


    -- Static wiring: the report is the ONLY caller and the section is pcall-guarded.
    local diag_src = read("diag.lua")
    check(diag_src:find("local function bar_lines(self)", 1, true) ~= nil,
        "diag.lua owns the bar-section builder")
    check(diag_src:find('append_section, out, bars, cap_inner, "bars"', 1, true) ~= nil,
        "the bar section goes through the capped append_section path")
    check(diag_src:find("class_hands", 1, true) ~= nil,
        "the hand list is read from the addon's class_hands table")
    check(diag_src:find("class_hands", 1, true) ~= nil and diag_src:find("BAR_HANDS", 1, true) ~= nil,
        "the three-hand fallback exists for an unreadable class_hands")
end

--=========================================================================================
-- 11c. The P4 additions (2026-10-28): power line, gate/receipt fields, quarantine sites
--=========================================================================================
-- The publish audit named four blind spots: no power-bar line at all, no activity-gate /
-- receipt fields (a gated hand looked switched off), no reason for shown=no, and
-- quarantine site names absent (only the total). Each is pinned here against the real
-- module in the same sandbox (print-only: no frame is created and no profile key written).
local function power_fixture()
    local frame = {
        visible = true,
        width = 275,
        height = 14,
        IsVisible = function(self) return self.visible end,
        IsShown = function(self) return self.visible end,
        GetWidth = function(self) return self.width end,
        GetHeight = function(self) return self.height end,
    }
    local anchor_frame = {
        visible = true,
        IsVisible = function(self) return self.visible end,
        IsShown = function(self) return self.visible end,
    }
    return {
        ready = true,
        frame = frame,
        -- The bar's own pure fill maths (power_bar.fraction shape): the report calls it so
        -- its fraction matches the painted fraction instead of re-implementing the clamp.
        fraction = function(value, max_value)
            if type(value) ~= "number" or type(max_value) ~= "number" or max_value <= 0 then
                return nil
            end
            if value >= max_value then
                return 1
            end
            return value / max_value
        end,
        last_state = {
            why = nil,
            anchor = anchor_frame,
            anchor_hand = "offhand",
            power_type = 0,
            value = 3000,
            max_value = 3000,
            fraction = 1,
        },
    }, frame, anchor_frame
end

do
    -- --- The power line: a painted bar, exact -----------------------------------------
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local pb = power_fixture()
    st.power_bar = pb
    st.api = {
        UnitPowerType = function(unit) return 0, "MANA" end,
        UnitPower = function(unit, power_type) return 3000 end,
        UnitPowerMax = function(unit, power_type) return 3000 end,
    }
    check(run_report(st, healthy_self(), true), "power painted: verbose does not throw")
    eq(captured[9],
        "SwedgeTimer diag: power ready=yes anchor=offhand anchor_shown=yes shown=yes "
        .. "width=275.00 height=14.00 type=0 token=MANA value=3000/3000 fraction=1.000 why=-",
        "the power line names the anchor hand, the geometry, the live reading and why=-")

    -- --- The power line: every hide reason is named -----------------------------------
    local frame
    pb, frame = power_fixture()
    frame.visible = false
    pb.last_state = { why = "no-anchor", anchor = nil, anchor_hand = nil }
    st.power_bar = pb
    check(run_report(st, healthy_self(), true), "power no-anchor: verbose does not throw")
    contains(captured[9], "anchor=none anchor_shown=no shown=no",
        "an unanchored power bar reports anchor=none and anchor_shown=no")
    contains(captured[9], "why=no-anchor",
        "the power line names the hide reason instead of only shown=no")

    local reasons = { "no-frame", "no-addon", "off", "no-api", "no-type", "no-value",
        "no-fraction" }
    for _, reason in ipairs(reasons) do
        pb.last_state = { why = reason }
        check(run_report(st, healthy_self(), true), "power reason " .. reason .. ": no throw")
        contains(captured[9], "why=" .. reason,
            "every pb.resolve hide token is named (" .. reason .. ")")
    end
    pb.last_state = { why = "unexpected-token" }
    check(run_report(st, healthy_self(), true), "power unknown reason: no throw")
    contains(captured[9], "why=?",
        "an unknown resolve token renders ? instead of leaking an unexpected field")

    -- --- The power line: module absent, never initialised, unreadable ---------------------------------
    local st2 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    check(run_report(st2, healthy_self(), true), "no power module: verbose does not throw")
    eq(captured[9], "SwedgeTimer diag: power module=no",
        "an absent power_bar module is named (never silently skipped)")

    local pb2 = power_fixture()
    pb2.ready = false
    st2.power_bar = pb2
    check(run_report(st2, healthy_self(), true), "power not ready: verbose does not throw")
    contains(captured[9], "power ready=no", "a bar that never initialised reports ready=no")
    contains(captured[9], "type=unknown token=unknown value=unknown fraction=?",
        "without st.api the power reading degrades to unknown (never a fake zero)")

    local pb3 = { ready = true, frame = {}, last_state = { why = "no-frame" } }
    st2.power_bar = pb3
    check(run_report(st2, healthy_self(), true), "power frame without reads: no throw")
    contains(captured[9], "shown=? width=? height=?",
        "a frame that cannot answer renders ? per field, never throws")

    -- --- The quarantine line: explicit empty state --------------------------------------
    local st3 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    local self3 = healthy_self()
    self3.bar_hook_errors = { count = 0, by_site = {}, quarantined = {} }
    check(run_report(st3, self3, true), "quarantine empty: verbose does not throw")
    eq(captured[10], "SwedgeTimer diag: quarantine total=0 sites=none",
        "a clean session says sites=none instead of printing a bare zero")

    -- --- The quarantine line: named sites, quarantined first, counts, [q] ---------------
    local self4 = healthy_self()
    self4.bar_hook_errors = {
        count = 31,
        by_site = { ["practice:tick"] = 4, ["hud:cs"] = 25, ["bars:mainhand:2"] = 2 },
        quarantined = { ["hud:cs"] = true },
    }
    check(run_report(st3, self4, true), "quarantine sites: verbose does not throw")
    eq(captured[10],
        "SwedgeTimer diag: quarantine total=31 sites=hud:cs=25[q],practice:tick=4,"
        .. "bars:mainhand:2=2",
        "every counted site is named with its count; quarantined first, then by volume")

    -- --- The quarantine line: a bounded tail, never a silent cut ------------------------
    local self5 = healthy_self()
    local by_site = { count = 0, by_site = {}, quarantined = {} }
    for i = 1, 10 do
        by_site.by_site["site:" .. tostring(i)] = i
        by_site.count = by_site.count + i
    end
    self5.bar_hook_errors = by_site
    check(run_report(st3, self5, true), "quarantine capped: verbose does not throw")
    contains(captured[10], "sites=site:10=10,site:9=9", "sites sort by volume, highest first")
    contains(captured[10], ",+2 more sites",
        "more than eight counted sites close with an explicit +N count, not a silent cut")

    -- --- The quarantine line: an unreadable counter is unknown, not zero ---------------
    local self6 = healthy_self()
    self6.bar_hook_errors = "junk"
    check(run_report(st3, self6, true), "quarantine unreadable: verbose does not throw")
    eq(captured[10], "SwedgeTimer diag: quarantine total=? sites=?",
        "an unreadable counter renders ? (never a misleading clean total)")

    local self6b = healthy_self()
    self6b.bar_hook_errors = { count = "junk", by_site = { ["hud:cs"] = 2 }, quarantined = {} }
    check(run_report(st3, self6b, true), "quarantine broken count: verbose does not throw")
    eq(captured[10], "SwedgeTimer diag: quarantine total=? sites=hud:cs=2",
        "an unreadable total stays unknown while the named sites still print")

    local self6c = healthy_self()
    self6c.bar_hook_errors = { count = 5 }
    check(run_report(st3, self6c, true), "quarantine no site map: verbose does not throw")
    eq(captured[10], "SwedgeTimer diag: quarantine total=5 sites=?",
        "a counter without its per-site map says sites=? instead of claiming none")

    -- --- Gate / receipt fields per hand -------------------------------------------------
    local st4 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st4.api = { get_time = function() return 101.3 end }
    local self7 = hand_self("HUNTER", { "mainhand", "offhand", "ranged" })
    local in_use = { offhand = true, ranged = false }
    self7.hand_visibility_needs_activity = function(_, hand)
        return hand == "offhand" or hand == "ranged"
    end
    self7.hand_is_in_use = function(_, hand) return in_use[hand] == true end
    self7.hand_activity_window = function(_, hand)
        if hand == "mainhand" then
            return nil
        end
        return 2.6
    end
    self7.mainhand = bar_state_fixture()
    self7.offhand = bar_state_fixture()
    self7.ranged = bar_state_fixture()
    self7.offhand.has_activity = true
    self7.offhand.last_activity_at = 100
    self7.offhand.activity_source = "cleu"
    self7.ranged.has_activity = false
    self7.ranged.auto_repeat_active = true
    check(run_report(st4, self7, true), "gate/receipt: verbose does not throw")
    contains(captured[6], "why=- gate=n/a active=? win=? left=none src=none",
        "the mainhand has no activity gate (gate=n/a) and no receipt")
    contains(captured[7], "gate=open active=yes win=2.60 left=1.30 src=cleu",
        "an offhand receipt opens the gate, names its source and shows the window left")
    contains(captured[8], "gate=closed active=no win=2.60 left=none src=auto-repeat",
        "an idle ranged hand closes the gate; Auto Shot armed is named as the in-use reason")

    -- A receipt older than the window floors at 0.00; a receipt with no named source is ?.
    self7.offhand.last_activity_at = 90
    self7.offhand.activity_source = nil
    check(run_report(st4, self7, true), "expired receipt: verbose does not throw")
    contains(captured[7], "left=0.00", "an expired receipt floors the remaining window at 0.00")
    contains(captured[7], "src=?", "a receipt with no recorded source renders ?, never none")

    -- No clock: left is ? (unknown is never a fake zero) while the receipt still renders.
    st4.api = {}
    check(run_report(st4, self7, true), "clockless receipt: verbose does not throw")
    contains(captured[7], "active=yes win=2.60 left=? src=?",
        "without a clock the window-left field is ?, never 0")

    -- Static wiring of the new readers (each builder is called under its own pcall).
    local diag_src = read("diag.lua")
    check(diag_src:find("local function power_line(self)", 1, true) ~= nil,
        "diag.lua owns the power-line builder")
    check(diag_src:find("local function quarantine_line(self)", 1, true) ~= nil,
        "diag.lua owns the quarantine-line builder")
    check(diag_src:find("pcall(power_line, self)", 1, true) ~= nil,
        "the power line is wired into the report under a pcall")
    check(diag_src:find("pcall(quarantine_line, self)", 1, true) ~= nil,
        "the quarantine line is wired into the report under a pcall")
    check(diag_src:find("hide_reason_text", 1, true) ~= nil,
        "the bar line reads the recorded hide reason")
    check(diag_src:find("activity_source", 1, true) ~= nil,
        "the bar line reads the receipt source token")
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
    -- P4-1 wiring: the hide reason is recorded where the decision hides the bar, and the
    -- receipt writer names its source. Both are read by the bar lines above.
    check(main:find("function ST:note_hand_hide_reason", 1, true) ~= nil,
        "main.lua records the hide reason at the visibility decision")
    for _, token in ipairs({ '"class-off"', '"off"', '"no-weapon"', '"spec"', '"form"',
            '"show-rule"', '"idle"' }) do
        check(main:find(token, 1, true) ~= nil,
            "the hide-reason token " .. token .. " is written in main.lua")
    end
    check(main:find("state.hide_reason = reason", 1, true) ~= nil,
        "note_hand_hide_reason stores the token on the hand state (the diag reads it)")
    -- Every branch that hides must record its reason right before the hide: a token that
    -- exists but is not wired to a hide would make the diag's why= field a lie.
    for _, token in ipairs({ "class-off", "off", "form", "spec", "show-rule", "idle" }) do
        local callsite = 'note_hand_hide_reason(hand, "' .. token .. '")'
        local start = main:find(callsite, 1, true)
        check(start ~= nil, "the hide-reason token " .. token .. " is wired at a decision point")
        if start then
            local window = main:sub(start, start + 160)
            check(window:find("hide_bar(hand)", 1, true) ~= nil,
                "the " .. token .. " reason is recorded immediately before the hide it explains")
        end
    end
    -- The disabled branch routes the reason through hand_disabled_reason (off / no-weapon).
    check(main:find('return "no-weapon"', 1, true) ~= nil,
        "the disabled branch distinguishes a missing weapon from a switched-off hand")
    local disabled_call = main:find("note_hand_hide_reason(hand, self:hand_disabled_reason(hand))", 1, true)
    check(disabled_call ~= nil, "the disabled branch records the routed reason")
    if disabled_call then
        check(main:sub(disabled_call, disabled_call + 160):find("hide_bar(hand)", 1, true) ~= nil,
            "the disabled branch records its reason immediately before the hide")
    end
    check(main:find("state.activity_source = source", 1, true) ~= nil,
        "note_hand_activity records the receipt source")
    for _, token in ipairs({ '"cleu"', '"forever"', '"shot"' }) do
        check(main:find(token, 1, true) ~= nil,
            "the receipt source token " .. token .. " is passed by its writer")
    end
    local power_bar_src = read("power_bar.lua")
    check(power_bar_src:find("function pb.resolve(ST)", 1, true) ~= nil,
        "power_bar.lua exposes the read-only state resolver the diag reads")
    check(power_bar_src:find("pb.last_state = state", 1, true) ~= nil,
        "pb.update stores the resolved state (the only writer of pb.last_state)")

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
    eq(#captured, 78,
        "ids no-api: 5 base + 3 bars + 1 power + 1 quarantine + 67 UNRESOLVED + 1 errors-none")
    contains(captured[11], "ids 1310785=UNRESOLVED", "ids no-api: first wanted id UNRESOLVED")
    contains(captured[77], "ids 60052=UNRESOLVED", "ids no-api: last wanted id UNRESOLVED")
    check(run_report(st, nil, true), "ids nil-self: verbose does not throw")
    contains(captured[11], "UNRESOLVED", "ids nil-self still degrades to UNRESOLVED")

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
    contains(captured[11], "ids 1310785 name=Sniper Shot", "resolved id renders the name")
    contains(captured[11], "icon=999", "resolved id renders the icon")
    contains(captured[11], "cast=1500", "resolved id renders the cast time")
    contains(captured[11], "known=true", "resolved id renders known=true")
    contains(captured[18], "ids 34428=UNRESOLVED", "a throwing GetSpellInfo degrades to UNRESOLVED")
    contains(captured[19], "ids 32216 name=Victorious", "partial probe still renders the name")
    contains(captured[19], "known=?", "a throwing is_spell_known renders ?")

    local st3 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st3.api = { GetSpellInfo = "junk", is_spell_known = "junk" }
    check(run_report(st3, healthy_self(), true), "ids junk-api: verbose does not throw")
    contains(captured[11], "UNRESOLVED", "a non-function GetSpellInfo degrades to UNRESOLVED")

    -- The ids tail is what the cap truncates once the fixed block is 10 lines (5 base +
    -- 3 bars + power + quarantine): at cap 13 two ids fit and the count line closes it.
    local st4 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    st4.diag.MAX_LINES = 13
    check(run_report(st4, healthy_self(), true), "ids capped: verbose does not throw")
    eq(#captured, 13, "MAX_LINES = 13 caps at thirteen lines")
    contains(captured[11], "ids 1310785", "the first wanted id fits at cap 13")
    contains(captured[13], "+65 more (cap 13)", "ids truncation carries the remaining count")
    -- Below the fixed block a cap cannot reach the ids at all: the bar section closes with
    -- its own explicit count line instead (pinned at MAX_LINES = 6 in section 9).
    st4.diag.MAX_LINES = 10
    run_report(st4, healthy_self(), true)
    eq(#captured, 10, "MAX_LINES = 10 stops at the fixed lines (no ids room)")
    contains(captured[10], "quarantine ", "the last fixed line printed under a small cap")
    st4.diag.MAX_LINES = 88

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
    -- The errors tail is what the cap truncates here: 5 base + 3 bars + power + quarantine
    -- + 67 ids = 77 lines, so at MAX_LINES = 80 the eight-entry ring keeps two lines plus
    -- an explicit count (the arithmetic has moved twice with the added sections).
    st4.diag.MAX_LINES = 80
    check(run_report(st4, healthy_self(), true), "errors capped: verbose does not throw")
    eq(#captured, 80, "errors truncation respects MAX_LINES")
    contains(captured[80], "errors +6 more (cap 80)", "errors truncation carries the remaining count")
    st4.diag.MAX_LINES = 88
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
