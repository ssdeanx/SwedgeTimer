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
--   * family rendering for all eight compat families and the three swing-engine modes;
--   * the guide summary for all five provider classes (on/off/none/?) and the provider
--     count;
--   * static wiring: main.lua's init report call, the /st diag route, the engine tokens,
--     addon_version exposure, init_deadline_fired, diag.lua's purity, and its TOC
--     placement.
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
            },
        },
        PALADIN = { guide = provider() },
        WARRIOR = { guide = provider() },
        DRUID = { guide = provider() },
        SHAMAN = { guide = provider() },
        HUNTER = { guide = provider() },
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
    "guides=PALADIN:on WARRIOR:off DRUID:on SHAMAN:off HUNTER:on",
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
    for _, class in ipairs({ "PALADIN", "WARRIOR", "DRUID", "SHAMAN", "HUNTER" }) do
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
    contains(captured[1], "guides=PALADIN:on WARRIOR:off DRUID:on SHAMAN:off HUNTER:on",
        "all five guide states render in provider order")
    local expected = {
        PALADIN = "on", WARRIOR = "off", DRUID = "on", SHAMAN = "off", HUNTER = "on",
    }
    for class, state in pairs(expected) do
        contains(captured[1], class .. ":" .. state, class .. " renders " .. state)
    end

    -- A class whose module did not load its provider.
    self = healthy_self()
    self.SHAMAN = {}
    check(run_report(st, self, true), "missing provider: no throw")
    contains(captured[1], "SHAMAN:none", "a missing provider renders none")
    contains(captured[3], "providers=4/5", "the provider count drops with a missing provider")

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
    contains(captured[3], "providers=0/5", "the provider count is 0/5 with no class modules")
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
    eq(#captured, 4, "verbose: exactly four lines")
    eq(captured[1], login_line, "verbose: line 1 is the same login line")
    eq(captured[2],
        "SwedgeTimer diag: flags stl_ready=true llm_ready=false lrc_ready=true "
        .. "lrc_unavailable=false deadline=no init=yes",
        "verbose line 2 is the exact readiness-flag line")
    eq(captured[3],
        "SwedgeTimer diag: modules practice=yes hud=yes rotation=yes design=yes providers=5/5",
        "verbose line 3 is the exact module/provider line")
    eq(captured[4],
        "SwedgeTimer diag: secrets api=no",
        "verbose line 4 is the exact secrets line (no C_Secrets in this sandbox)")

    self = healthy_self()
    self.init_deadline_fired = true
    check(run_report(st, self, true), "verbose with the deadline fired: no throw")
    contains(captured[2], "deadline=fired", "the fired init deadline is reported")

    check(run_report(st, {}, true), "verbose over an empty state: no throw")
    eq(#captured, 4, "verbose over an empty state still prints four lines")
    contains(captured[2], "stl_ready=? llm_ready=? lrc_ready=? lrc_unavailable=?",
        "unset readiness flags render ?")
    contains(captured[2], "deadline=no init=no", "empty state: deadline/init render no")

    local empty_st = load_diag()
    run_report(empty_st, {}, true)
    contains(captured[3], "practice=no hud=no rotation=no design=no",
        "unloaded UI modules render no")
    contains(captured[3], "providers=0/5", "an empty namespace has no providers")

    -- The hard cap: the report must never exceed MAX_LINES, and MAX_LINES must fall back
    -- to a safe default when it is not a number.
    st.diag.MAX_LINES = 1
    check(run_report(st, healthy_self(), true), "capped verbose: no throw")
    eq(#captured, 1, "MAX_LINES = 1 caps the verbose report at one line")
    st.diag.MAX_LINES = 2
    run_report(st, healthy_self(), true)
    eq(#captured, 2, "MAX_LINES = 2 caps the verbose report at two lines")
    st.diag.MAX_LINES = "junk"
    run_report(st, healthy_self(), true)
    eq(#captured, 4, "a non-numeric MAX_LINES falls back to the default cap")
    st.diag.MAX_LINES = 6
end

--=========================================================================================
-- 10. The secrets line: C_Secrets absent, present, and hostile
--=========================================================================================
do
    -- Absent (every classic client, and the offline harness): api=no, no probes touched.
    local st = load_diag({ st = healthy_st(), libstub = function() return nil end })
    check(run_report(st, healthy_self(), true), "no C_Secrets: verbose does not throw")
    eq(#captured, 4, "no C_Secrets: verbose still prints four lines")
    eq(captured[4], "SwedgeTimer diag: secrets api=no",
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
    eq(captured[4],
        "SwedgeTimer diag: secrets api=yes restrictions=true cd=false aura=? power=true stats=? cast=?",
        "the secrets line renders api=yes and every predicate (readable/missing/throwing)")

    -- Non-table C_Secrets (a broken global) must degrade to api=no, never error.
    local st3, env3 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    env3.C_Secrets = "junk"
    check(run_report(st3, healthy_self(), true), "non-table C_Secrets: verbose does not throw")
    eq(captured[4], "SwedgeTimer diag: secrets api=no",
        "a non-table C_Secrets renders api=no")

    -- A hostile C_Secrets whose probe access throws: every probe renders ?.
    local st4, env4 = load_diag({ st = healthy_st(), libstub = function() return nil end })
    env4.C_Secrets = setmetatable({}, {
        __index = function() error("hostile C_Secrets") end,
    })
    check(run_report(st4, healthy_self(), true), "hostile C_Secrets: verbose does not throw")
    eq(captured[4],
        "SwedgeTimer diag: secrets api=yes restrictions=? cd=? aura=? power=? stats=? cast=?",
        "a hostile C_Secrets renders ? for every probe")
end

--=========================================================================================
-- 11. Static wiring: main.lua hooks, purity, TOC placement
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

    local diag_src = read("diag.lua")
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

if failures == 0 then
    print("PASS  diag_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  diag_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
