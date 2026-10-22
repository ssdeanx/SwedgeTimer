-- tests/twist_state.lua: unit tests for the pure twist state helpers in twist.lua.
local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL  " .. label) end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then failures = failures + 1; print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")") end
end

local st = { twist = nil }
st.utils = { print_msg = function(...) end, convert_lookup_table = function(l)
    local tab={} for i=1,#l do tab[l[i]]=true end return tab end }

local env = {}
for k, v in pairs(_G) do env[k] = v end
env.LibStub = function(major)
    if major == "AceAddon-3.0" then
        return { GetAddon = function() return st end }
    end
    return {}
end
env.ST = st
env.UnitGUID = function() return nil end

local mod = assert(loadfile(ROOT .. "twist.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "twist.lua loads under the sandbox (" .. tostring(err) .. ")")
local twist = st.twist
check(type(twist) == "table", "st.twist table exists")

-- is_twist_seal_active
eq(twist.is_twist_seal_active(true, false), true, "soc active => twist seals active")
eq(twist.is_twist_seal_active(false, true), true, "sor active => twist seals active")
eq(twist.is_twist_seal_active(false, false), false, "no twist seal => false")

-- normalize + detect_twist_attempt
eq(twist.normalize_seal_count(2.7), 2, "normalize floors")
eq(twist.normalize_seal_count(-1), 0, "normalize clamps negative")
eq(twist.detect_twist_attempt(false, true, 2), true, "sealed + count 2 => attempt")
eq(twist.detect_twist_attempt(true, true, 2), false, "extra attack suppresses attempt")
eq(twist.detect_twist_attempt(false, true, 1), false, "single seal => no attempt")
eq(twist.detect_twist_attempt(false, false, 2), false, "no discipline => no attempt")

-- detect_twist_success
check(twist.detect_twist_success(true, 20424), "SoC proc lands the success")
eq(twist.detect_twist_success(false, 20424), false, "no pending => no success")
eq(twist.detect_twist_success(true, 9999), false, "non-proc => no success")
check(twist.detect_twist_success(true, 20947), "rank5 proc")
check(twist.detect_twist_success(true, 29385), "tbc rank6 proc")

for _, id in ipairs({20424,20944,20945,20946,20947,29385}) do
    check(twist.SOC_PROC_IDS[id], "SOC_PROC_IDS contains " .. id)
end
eq(twist.SOC_PROC_IDS[12345], nil, "non-proc id absent")

-- R1: string-payload success (Anniversary shape). The numeric path above is
-- untouched and stays byte-identical.
eq(twist.SOC_PROC_NAME_FALLBACK, "Seal of Command", "the literal English proc name")
check(twist.detect_twist_success_name(true, "Seal of Command", nil),
    "literal fallback lands with no resolved names")
check(twist.detect_twist_success_name(true, "Heiliger Befehl", { ["Heiliger Befehl"] = true }),
    "resolved localized name lands")
eq(twist.detect_twist_success_name(true, "Judgement of Command", nil), false,
    "an unrelated name never lands")
eq(twist.detect_twist_success_name(false, "Seal of Command", nil), false,
    "no pending => no success by name")
eq(twist.detect_twist_success_name(true, nil, nil), false,
    "a non-string name never lands")
eq(twist.detect_twist_success_name(true, 20424, nil), false,
    "a numeric id takes the numeric path, not the name path")

-- get_window_seconds
eq(twist.get_window_seconds("None", 120, 50), 0.4, "None: 0.4 baseline")
local dynamic = twist.get_window_seconds("Dynamic", 200, 0)
check(math.abs(dynamic - 0.54) < 1e-9, "Dynamic: 0.4 + 0.7*0.2 = 0.54 (got " .. tostring(dynamic) .. ")")
eq(twist.get_window_seconds("Fixed", 0, 100), 0.5, "Fixed: 0.4 + 0.1")
local fixed_cap = twist.get_window_seconds("Fixed", 0, 999999)
check(math.abs(fixed_cap - 0.8) < 1e-9, "Fixed padding capped to 400 ms, total <= 0.8 (got " .. tostring(fixed_cap) .. ")")
eq(twist.get_window_seconds("Dynamic", -50, -10), 0.4, "negative inputs clamped to zero")
eq(twist.BASE_WINDOW_SECONDS, 0.4, "BASE_WINDOW_SECONDS == 0.4")

-- is_twist_impossible (archive semantics, player.lua:743-771): warn while a running
-- GCD + calibrated lag will not clear before the swing lands, but only before the
-- twist window opens; inside the window the warning clears.
check(twist.is_twist_impossible(true, 1.0, 1.05, 100, 1.4, 15, 0.4),
    "impossible: running gcd+lag won't clear before the swing (1.05+0.155 > 1.0)")
eq(twist.is_twist_impossible(true, 0.3, 2.0, 100, 1.4, 15, 0.4), false,
    "inside the twist window the warning clears")
eq(twist.is_twist_impossible(false, 1.0, 2.0, 100, 1.4, 15, 0.4), false, "disabled => never impossible")
eq(twist.is_twist_impossible(true, 2.0, 0.5, 100, 1.4, 15, 0.4), false, "gcd clears well before the swing")
eq(twist.is_twist_impossible(true, 0.5, 0.0, 0, 1.4, 0, 0.4), false, "no gcd/lag => not impossible")
check(twist.is_twist_impossible(true, 0.5, 0.0, 400, 1.4, 15, 0.4),
    "very high latency alone overruns the remaining time (0.575 > 0.5)")
-- boundary/repeatable semantics
eq(twist.is_twist_impossible(true, 0.4, 9.0, 0, 1.4, 0, 0.4), false, "remaining == window => warning already cleared")
eq(twist.is_twist_impossible(true, 1.0, 1.0, 0, 1.4, 0, 0.4), false, "gcd == remaining => not impossible (strict >)")
eq(twist.is_twist_impossible(true, -1.0, 9.0, 0, 1.4, 0, 0.4), false, "negative remaining clamps and reads as inside the window")
check(twist.is_twist_impossible(true, 1.0, 1.0, 100, nil, 0, 0.4), "nil multiplier falls back to 1.4 (1.0+0.14 > 1.0)")

-- P1: GCD-aware reseal marker fraction (SST 3.1.0 shape, offline-testable math)
local rm = twist.get_reseal_marker_fraction
check(type(rm) == "function", "get_reseal_marker_fraction exists")
check(math.abs(rm(3.0, 3.0, 1.0) - 1 / 3) < 1e-9,
    "fresh swing, 1 s GCD: marker at 1/3 (got " .. tostring(rm(3.0, 3.0, 1.0)) .. ")")
eq(rm(3.0, 3.0, 3.0), 1.0, "GCD clearing exactly at the swing end reads 1.0")
eq(rm(3.0, 2.0, 0.5), 0.5, "mid-swing GCD clear reads 0.5")
eq(rm(3.0, 1.0, 1.0), 1.0, "GCD clearing with 1 s left reads 1.0")
eq(rm(3.0, 4.0, 1.0), 0.0, "a GCD clearing at the swing start reads 0.0")
eq(rm(3.0, 0.4, 0.5), nil, "a GCD outliving the swing hides (unknown-hides)")
eq(rm(3.0, 3.0, 0), nil, "no running GCD hides (nothing to wait for)")
eq(rm(3.0, 3.0, -1), nil, "a negative GCD hides")
eq(rm(3.0, 3.0, nil), nil, "a missing GCD hides")
eq(rm(3.0, 3.0, 0 / 0), nil, "a NaN GCD hides")
eq(rm(3.0, nil, 1.0), nil, "a missing remaining hides")
eq(rm(3.0, 0 / 0, 1.0), nil, "a NaN remaining hides")
eq(rm(0, 1.0, 1.0), nil, "a zero swing duration hides")
eq(rm(-3.0, 1.0, 1.0), nil, "a negative swing duration hides")
eq(rm(nil, 1.0, 1.0), nil, "a missing swing duration hides")
eq(rm(0 / 0, 1.0, 1.0), nil, "a NaN swing duration hides")
eq(rm("3.0", 1.0, 1.0), nil, "a non-number duration hides")
eq(rm(3.0, -1.0, 0.5), nil, "a landed swing (negative remaining) hides")
eq(rm(3.0, 0, 0.5), nil, "a GCD clearing after a landed swing hides")

-- SoD twist window (all SoD twist APLs twist inside 200 ms, not 400 ms)
eq(twist.SOD_WINDOW_SECONDS, 0.2, "SOD_WINDOW_SECONDS == 0.2")
eq(twist.narrow_window_for_sod(0.4, true), 0.2, "sod: the 0.4 baseline narrows to 0.2")
check(math.abs(twist.narrow_window_for_sod(0.54, true) - 0.34) < 1e-9,
    "sod: user padding rides on top of the narrowed baseline")
eq(twist.narrow_window_for_sod(0.4, false), 0.4, "sod=false keeps the window")
eq(twist.narrow_window_for_sod(0.4, nil), 0.4, "sod=nil keeps the window")
eq(twist.narrow_window_for_sod(nil, true), nil, "sod: a nil window passes through")
eq(twist.narrow_window_for_sod("0.4", true), "0.4", "sod: a non-number window passes through")
eq(twist.narrow_window_for_sod(0.21, true), 0.2, "sod: the narrowed window floors at 0.2")

-- PPM/ICD attempt discipline (both sims: 7 PPM, 1 s ICD, white hits only)
eq(twist.SOC_PROC_ICD_SECONDS, 1, "SOC_PROC_ICD_SECONDS == 1")
check(twist.is_proc_icd_clear(100, nil), "icd: no proc yet => the swing may proc")
eq(twist.is_proc_icd_clear(100.5, 100), false, "icd: half a second after the proc => no attempt")
eq(twist.is_proc_icd_clear(100.9, 100), false, "icd: still inside the window => no attempt")
check(twist.is_proc_icd_clear(101, 100), "icd: the boundary clears (strict <)")
check(twist.is_proc_icd_clear(103, 100), "icd: well past the window => the swing may proc")
check(twist.is_proc_icd_clear(nil, 100), "icd: an unusable clock degrades to the archived attempt")
check(twist.is_proc_icd_clear(0 / 0, 100), "icd: a NaN clock degrades to the archived attempt")
check(twist.is_proc_icd_clear(103, nil), "icd: an unusable stamp degrades to the archived attempt")
check(twist.is_proc_icd_clear(103, 0 / 0), "icd: a NaN stamp degrades to the archived attempt")

if failures == 0 then
    print("PASS  twist_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  twist_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end