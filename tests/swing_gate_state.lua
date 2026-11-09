-- tests/swing_gate_state.lua: offline tests for the single-TOC swing-library gate
-- (swing_lib_gate.lua + swing_lib_gate_release.lua, 2026-11-07).
--
-- WHY THE GATE EXISTS: the release ships ONE SwedgeTimer.toc, so the vendored
-- LibClassicSwingTimerAPI can no longer be omitted per flavor. It must run on the
-- classic-line clients (Era/TBC/Wrath) and be a no-op everywhere else (Forever, Retail,
-- Cata, Mists) without editing anything under Libs/. The gate pre-registers a stub at a
-- minor above the vendored one; LibStub:NewLibrary returns nil for an equal-or-higher
-- minor (Libs/LibStub/LibStub.lua:20-28), and the library returns at its guard.
--
-- Each scenario loads the REAL gate file against a fresh LibStub with the real
-- NewLibrary semantics, then asserts both directions:
--   * classic-line: no stub (the real library must load);
--   * every other client, including unknown/legacy: a tagged stub blocks MINOR 32;
--   * the release file removes the stub again, and leaves a real library untouched.
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
-- lua5.1 tests/swing_gate_state.lua  (any cwd works; ROOT follows arg[0]).

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

local MAJOR = "LibClassicSwingTimerAPI"
local GATE_PATH = ROOT .. "swing_lib_gate.lua"
local RELEASE_PATH = ROOT .. "swing_lib_gate_release.lua"

-- The project constants as the clients expose them (only their distinctness matters to
-- the gate; the values mirror compat.lua's comparisons).
local PROJECT = {
    MAINLINE = 1,
    CLASSIC = 2,
    BURNING_CRUSADE = 5,
    WRATH = 11,
    CATACLYSM = 14,
    MISTS = 19,
    CAMELOT = 18,
}

-- A minimal LibStub with the vendored implementation's exact NewLibrary contract.
local function make_libstub()
    local ls = { libs = {}, minors = {} }
    function ls:NewLibrary(major, minor)
        local old = self.minors[major]
        if old and old >= minor then
            return nil
        end
        self.minors[major], self.libs[major] = minor, self.libs[major] or {}
        return self.libs[major], old
    end
    return ls
end

local function load_chunk(path)
    local fn, err = loadfile(path)
    assert(fn, err)
    return fn
end

local function run_gate(st)
    load_chunk(GATE_PATH)("SwedgeTimer", st or {})
end

local function run_release(st)
    load_chunk(RELEASE_PATH)("SwedgeTimer", st or {})
end

-- Run the gate under one client identity and return the fresh LibStub registry.
-- project: WOW_PROJECT_ID value (nil = legacy/private client).
-- build_toc: interface number returned by GetBuildInfo when project is nil.
local function scenario(project, build_toc)
    local ls = make_libstub()
    _G.LibStub = ls
    _G.WOW_PROJECT_ID = project
    _G.WOW_PROJECT_MAINLINE = PROJECT.MAINLINE
    _G.WOW_PROJECT_CLASSIC = PROJECT.CLASSIC
    _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = PROJECT.BURNING_CRUSADE
    _G.WOW_PROJECT_WRATH_CLASSIC = PROJECT.WRATH
    _G.WOW_PROJECT_CATACLYSM_CLASSIC = PROJECT.CATACLYSM
    _G.WOW_PROJECT_MISTS_CLASSIC = PROJECT.MISTS
    _G.WOW_PROJECT_CAMELOT = PROJECT.CAMELOT
    if build_toc ~= nil then
        _G.GetBuildInfo = function()
            return "1.0.0", "build", "date", build_toc
        end
    else
        _G.GetBuildInfo = nil
    end
    run_gate()
    return ls
end

--=========================================================================================
-- 1. Classic-line clients: the gate must do NOTHING (the real library loads)
--=========================================================================================
for _, row in ipairs({
    { "Era", PROJECT.CLASSIC },
    { "TBC Anniversary", PROJECT.BURNING_CRUSADE },
    { "Wrath Titanforge", PROJECT.WRATH },
}) do
    local ls = scenario(row[2], nil)
    eq(ls.libs[MAJOR], nil, row[1] .. ": the gate registers no stub (classic library allowed)")
    eq(ls.minors[MAJOR], nil, row[1] .. ": no minor is reserved")
    -- The real library's own registration must still succeed afterwards.
    local lib = ls:NewLibrary(MAJOR, 32)
    check(lib ~= nil, row[1] .. ": the real library can still register at MINOR 32")
    eq(ls.minors[MAJOR], 32, row[1] .. ": the real MINOR is recorded")
end

--=========================================================================================
-- 2. Gated clients: a tagged stub at the gate minor blocks the vendored library
--=========================================================================================
for _, row in ipairs({
    { "WoW Forever", PROJECT.CAMELOT },
    { "Retail", PROJECT.MAINLINE },
    { "Cata", PROJECT.CATACLYSM },
    { "Mists", PROJECT.MISTS },
    { "unknown project", 99 },
}) do
    local ls = scenario(row[2], nil)
    local stub = ls.libs[MAJOR]
    check(stub ~= nil, row[1] .. ": the gate registers a stub")
    eq(stub and stub.__st_gate_stub, true, row[1] .. ": the stub is tagged __st_gate_stub")
    eq(ls.minors[MAJOR], 1000000, row[1] .. ": the stub reserves GATE_MINOR")
    eq(ls:NewLibrary(MAJOR, 32), nil, row[1] .. ": the vendored MINOR 32 is blocked")
end

--=========================================================================================
-- 3. Legacy clients without WOW_PROJECT_ID: mirror compat's interface fallback
--=========================================================================================
do
    local classic = scenario(nil, 11509)
    eq(classic.libs[MAJOR], nil, "interface 11509 (Era): classic library allowed")
    local tbc = scenario(nil, 20506)
    eq(tbc.libs[MAJOR], nil, "interface 20506 (TBC): classic library allowed")
    local wrath = scenario(nil, 38002)
    eq(wrath.libs[MAJOR], nil, "interface 38002 (Wrath): classic library allowed")
    local forever = scenario(nil, 16001)
    check(forever.libs[MAJOR] ~= nil, "interface 16001 (Forever): the gate blocks the library")
    local cata = scenario(nil, 40402)
    check(cata.libs[MAJOR] ~= nil, "interface 40402 (Cata): the gate blocks the library")
    local mists = scenario(nil, 50500)
    check(mists.libs[MAJOR] ~= nil, "interface 50500 (Mists): the gate blocks the library")
    local retail = scenario(nil, 120105)
    check(retail.libs[MAJOR] ~= nil, "interface 120105 (Retail): the gate blocks the library")
    local bare = scenario(nil, nil)
    check(bare.libs[MAJOR] ~= nil, "no project id and no build info: the gate fails safe (blocked)")
end

--=========================================================================================
-- 4. The release file: remove the stub, never touch a real library
--=========================================================================================
do
    -- Gated client: the vendored library returned at its guard, so the stub is still
    -- registered when the release runs; it must disappear from the shared registry.
    local ls = scenario(PROJECT.CAMELOT, nil)
    check(ls.libs[MAJOR] ~= nil, "release: the gated client starts with the stub present")
    eq(ls:NewLibrary(MAJOR, 32), nil, "release: MINOR 32 was blocked before the release")
    run_release()
    eq(ls.libs[MAJOR], nil, "release: the stub is removed from LibStub.libs")
    eq(ls.minors[MAJOR], nil, "release: the reserved minor is removed from LibStub.minors")
    -- With the registry clean, another addon's real copy can register normally.
    local other = ls:NewLibrary(MAJOR, 32)
    check(other ~= nil, "release: another addon can register the real library afterwards")
    eq(other and other.__st_gate_stub, nil, "release: the other addon's copy is not the stub")
end

do
    -- Classic-line client: the real library registered itself; the release must leave it.
    local ls = scenario(PROJECT.CLASSIC, nil)
    local real = ls:NewLibrary(MAJOR, 32)
    check(real ~= nil, "release: the classic client registered the real library")
    run_release()
    eq(ls.libs[MAJOR], real, "release: the real library object is untouched")
    eq(ls.minors[MAJOR], 32, "release: the real minor is untouched")
end

--=========================================================================================
-- 5. Static contract: main.lua treats the tagged stub as absent
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "main.lua", "r"))
    local text = f:read("*a")
    f:close()
    check(text:find("__st_gate_stub", 1, true) ~= nil,
        "main.lua checks the gate tag before selecting an engine")
    check(text:find("STL = nil", 1, true) ~= nil,
        "main.lua drops the tagged stub")
end

print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
os.exit(0)
