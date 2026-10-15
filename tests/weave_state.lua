-- tests/weave_state.lua: unit tests for the pure weave math helpers in weave.lua.
-- Sandbox-loads weave.lua with a setmetatable environment (__index = _G); the module
-- needs no LibStub and no WoW globals. Plain Lua 5.1, no WoW client needed.
-- Run from the repo root: lua5.1 tests/weave_state.lua

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
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

local st = {}
local env = setmetatable({}, { __index = _G })
env.ST = st

local mod = assert(loadfile(ROOT .. "weave.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "weave.lua loads under the sandbox (" .. tostring(err) .. ")")
local weave = st.weave
check(type(weave) == "table", "st.weave table exists")

-- constants ----------------------------------------------------------------
eq(weave.MW_MAX_STACKS, 5, "MW_MAX_STACKS == 5")
near(weave.MW_PER_STACK, 0.20, "MW_PER_STACK == 0.20")

-- clamp_fraction -----------------------------------------------------------
eq(weave.clamp_fraction(0.5), 0.5, "clamp: 0.5 stays 0.5")
eq(weave.clamp_fraction(0), 0, "clamp: 0 stays 0")
eq(weave.clamp_fraction(1), 1, "clamp: 1 stays 1")
eq(weave.clamp_fraction(-0.2), 0, "clamp: negative floors to 0")
eq(weave.clamp_fraction(2), 1, "clamp: > 1 ceilings to 1")
eq(weave.clamp_fraction(nil), 0, "clamp: nil -> 0")
eq(weave.clamp_fraction("0.5"), 0, "clamp: non-number string -> 0")
eq(weave.clamp_fraction(true), 0, "clamp: non-number boolean -> 0")

-- get_haste_multiplier -----------------------------------------------------
eq(weave.get_haste_multiplier(0), 1, "haste: 0% -> 1")
near(weave.get_haste_multiplier(20), 1.2, "haste: 20% -> 1.2")
near(weave.get_haste_multiplier(100), 2, "haste: 100% -> 2")
eq(weave.get_haste_multiplier(nil), 1, "haste: nil -> 1")
eq(weave.get_haste_multiplier(-5), 1, "haste: negative -> 1")

-- get_max_haste_multiplier -------------------------------------------------
near(weave.get_max_haste_multiplier(20, 1.30), 1.30, "max haste: 1.30 buff beats 1.2 haste")
near(weave.get_max_haste_multiplier(20, 1.10), 1.2, "max haste: 1.2 haste beats 1.10 buff")
near(weave.get_max_haste_multiplier(50, 1.30), 1.5, "max haste: 1.5 haste beats 1.30 buff")
near(weave.get_max_haste_multiplier(100, 1.30), 2, "max haste: maxed, not multiplied (2, not 2.6)")
eq(weave.get_max_haste_multiplier(nil, nil), 1, "max haste: both nil -> 1")
eq(weave.get_max_haste_multiplier(0, 1), 1, "max haste: no haste, no buff -> 1")
near(weave.get_max_haste_multiplier(-5, 1.30), 1.30, "max haste: negative haste, buff wins")

-- get_maelstrom_multiplier -------------------------------------------------
eq(weave.get_maelstrom_multiplier(0), 1, "MW: 0 stacks -> 1")
near(weave.get_maelstrom_multiplier(1), 0.8, "MW: 1 stack -> 0.8")
near(weave.get_maelstrom_multiplier(3), 0.4, "MW: 3 stacks -> 0.4")
eq(weave.get_maelstrom_multiplier(5), 0, "MW: 5 stacks -> 0 (instant)")
eq(weave.get_maelstrom_multiplier(7), 0, "MW: 7 stacks clamped to 5 -> 0")
eq(weave.get_maelstrom_multiplier(-2), 1, "MW: negative stacks -> 0 stacks -> 1")
eq(weave.get_maelstrom_multiplier(nil), 1, "MW: nil -> 0 stacks -> 1")

-- get_effective_cast_time --------------------------------------------------
eq(weave.get_effective_cast_time(2.5, 1, 1, true), 0, "cast: instant flag -> 0")
eq(weave.get_effective_cast_time(2.5, 1, 0, false), 0, "cast: MW multiplier 0 -> 0")
eq(weave.get_effective_cast_time(2.5, 1, -0.5, false), 0, "cast: MW multiplier negative -> 0")
near(weave.get_effective_cast_time(2.5, 1, 1, false), 2.5, "cast: base only")
near(weave.get_effective_cast_time(2.5, 1.2, 1, false), 2.5 / 1.2, "cast: base / haste")
near(weave.get_effective_cast_time(2.5, 1, 0.4, false), 1.0, "cast: base * MW multiplier")
near(weave.get_effective_cast_time(2.5, 1.2, 0.4, false), (2.5 / 1.2) * 0.4, "cast: base / haste * MW")
near(weave.get_effective_cast_time(2.5, 0, 1, false), 2.5, "cast: zero haste treated as 1")
near(weave.get_effective_cast_time(2.5, -3, 1, false), 2.5, "cast: negative haste treated as 1")
eq(weave.get_effective_cast_time(0, 1, 1, false), 0, "cast: base 0 -> 0")
eq(weave.get_effective_cast_time(-2, 1, 1, false), 0, "cast: negative base -> 0")
eq(weave.get_effective_cast_time(nil, 1, 1, false), 0, "cast: nil base -> 0")
near(weave.get_effective_cast_time(2.5, 1, nil, false), 2.5, "cast: nil MW multiplier treated as 1")
near(weave.get_effective_cast_time(2.5, nil, 1, false), 2.5, "cast: nil haste treated as 1")
near(weave.get_effective_cast_time(2.5, 1, 1, nil), 2.5, "cast: nil instant flag -> not instant")

-- get_marker_fraction ------------------------------------------------------
near(weave.get_marker_fraction(4, 2.5, 0), 0.375, "marker: 4s swing, 2.5s cast, 0 latency -> 0.375")
near(weave.get_marker_fraction(4, 2.5, 0.1), 0.35, "marker: latency shifts the marker left")
near(weave.get_marker_fraction(4, 2, 0), 0.5, "marker: 2s cast -> 0.5")
near(weave.get_marker_fraction(4, 3.2, 0.2), 0.15, "marker: 3.4s cast+latency -> 0.15")
eq(weave.get_marker_fraction(4, 4, 0), 0, "marker: cast == duration -> 0 boundary")
eq(weave.get_marker_fraction(4, 3.5, 1), 0, "marker: cast+latency > duration clamps to 0")
eq(weave.get_marker_fraction(0, 2.5, 0), 0, "marker: zero duration -> 0")
eq(weave.get_marker_fraction(-1, 0, 0), 0, "marker: negative duration -> 0")
near(weave.get_marker_fraction(4, 2.5, nil), 0.375, "marker: nil latency treated as 0")
near(weave.get_marker_fraction(4, nil, 0), 1, "marker: nil cast treated as 0 -> 1")

-- get_safe_start_in --------------------------------------------------------
near(weave.get_safe_start_in(5, 1, 0.1, 2.5), 1.4, "safe start: window still open")
check(weave.get_safe_start_in(5, 1, 0.1, 2.5) > 0, "safe start: positive when open")
near(weave.get_safe_start_in(2, 1, 0.1, 2.5), -1.6, "safe start: negative when passed")
check(weave.get_safe_start_in(2, 1, 0.1, 2.5) < 0, "safe start: negative not clamped")
eq(weave.get_safe_start_in(3, 1, 0, 2), 0, "safe start: exact boundary -> 0")
near(weave.get_safe_start_in(3.5, 1, 0.25, 0.75), 1.5, "safe start: latency and cast both subtract")

-- get_clip_amount ----------------------------------------------------------
eq(weave.get_clip_amount(1, 0.1, 2.5, 5), 0, "clip: cast ends before the swing -> 0")
near(weave.get_clip_amount(3.9, 0.1, 2.5, 5), 1.5, "clip: overrun measured in seconds")
eq(weave.get_clip_amount(2.4, 0.1, 2.5, 5), 0, "clip: exactly at the swing -> 0 (strict >)")
near(weave.get_clip_amount(2.4001, 0.1, 2.5, 5), 0.0001, "clip: just past the swing -> small positive")
eq(weave.get_clip_amount(10, 0, 0, 5), 5, "clip: no cast, no latency")
near(weave.get_clip_amount(1, 0.1, 2.5, 3), 0.6, "clip: latency and remaining cast counted")

-- is_clipped ---------------------------------------------------------------
eq(weave.is_clipped(1, nil, 0.5), true, "clipped: positive clip amount")
eq(weave.is_clipped(0.001, nil, 0.5), true, "clipped: tiny positive clip amount")
eq(weave.is_clipped(0, 0.6, 0.5), true, "clipped: cast started after the marker")
eq(weave.is_clipped(0, 0.5, 0.5), false, "clipped: at the marker is not clipped (strict >)")
eq(weave.is_clipped(0, 0.4, 0.5), false, "clipped: started before the marker")
eq(weave.is_clipped(0, nil, 0.5), false, "clipped: no clip amount, no cast-start fraction")
eq(weave.is_clipped(nil, nil, nil), false, "clipped: all missing -> false")
eq(weave.is_clipped(0, 0.9, 0), true, "clipped: marker 0, started later")

-- get_projected_impact_fraction --------------------------------------------
near(weave.get_projected_impact_fraction(1, 1, 0.1, 0, 4), 0.525, "projected: (1+1+0.1)/4")
near(weave.get_projected_impact_fraction(2, 0, 0, 0, 4), 0.5, "projected: half the swing")
near(weave.get_projected_impact_fraction(1, 1, 0, 1, 4), 0.25, "projected: swing_start offsets")
eq(weave.get_projected_impact_fraction(3, 5, 1, 0, 4), 1, "projected: over the swing clamps to 1")
eq(weave.get_projected_impact_fraction(0, 0, 0, 4, 4), 0, "projected: before the swing clamps to 0")
eq(weave.get_projected_impact_fraction(1, 0.5, 0.25, 3, 4), 0, "projected: negative impact -> 0")
eq(weave.get_projected_impact_fraction(4, 0, 0, 4, 4), 0, "projected: exactly at swing end -> 0")

-- get_cast_start_fraction --------------------------------------------------
near(weave.get_cast_start_fraction(1, 0, 4), 0.25, "cast start: 1s into a 4s swing")
near(weave.get_cast_start_fraction(3, 0, 4), 0.75, "cast start: 3s into a 4s swing")
near(weave.get_cast_start_fraction(2, 1, 4), 0.25, "cast start: swing_start offsets")
eq(weave.get_cast_start_fraction(-1, 0, 4), 0, "cast start: before the swing clamps to 0")
eq(weave.get_cast_start_fraction(5, 0, 4), 1, "cast start: past the swing clamps to 1")
eq(weave.get_cast_start_fraction(nil, 0, 4), 0, "cast start: nil start -> 0")

-- get_spark_fraction -------------------------------------------------------
near(weave.get_spark_fraction(0.25, 0.75, 0.5), 0.5, "spark: halfway between start and landing")
near(weave.get_spark_fraction(0.25, 0.75, 0), 0.25, "spark: at progress 0 sits at the start")
near(weave.get_spark_fraction(0.25, 0.75, 1), 0.75, "spark: at progress 1 sits at the landing")
near(weave.get_spark_fraction(0.25, 0.75, nil), 0.25, "spark: nil progress treated as 0")
near(weave.get_spark_fraction(2, 0.75, 0.5), 0.875, "spark: start clamped to 1 before interpolating")
near(weave.get_spark_fraction(-1, 0.75, 0.5), 0.375, "spark: start clamped to 0 before interpolating")
near(weave.get_spark_fraction(0.25, 2, 0.5), 0.625, "spark: landing clamped to 1 before interpolating")
near(weave.get_spark_fraction(0.25, 0.75, 2), 0.75, "spark: progress > 1 clamped to 1")
near(weave.get_spark_fraction(0.25, 0.75, -1), 0.25, "spark: progress < 0 clamped to 0")
eq(weave.get_spark_fraction(nil, nil, nil), 0, "spark: all missing -> 0")

-- FAMILIES / SPELL_GROUPS / FAMILY_COLORS shape ----------------------------
eq(#weave.FAMILIES, 5, "FAMILIES has 5 entries")
eq(table.concat(weave.FAMILIES, ","), "LB,CL,HW,LHW,CH", "FAMILIES order is LB,CL,HW,LHW,CH")
eq(#weave.SPELL_GROUPS, 5, "SPELL_GROUPS has 5 groups")
eq(#weave.SPELL_GROUPS[1].ids, 12, "LB group lists 12 ranks")
eq(weave.SPELL_GROUPS[1].ids[1], 403, "LB lowest rank is 403")
eq(weave.SPELL_GROUPS[1].ids[12], 25449, "LB highest rank is 25449")
eq(weave.SPELL_GROUPS[2].ids[1], 421, "CL lowest rank is 421")
eq(weave.SPELL_GROUPS[5].ids[#weave.SPELL_GROUPS[5].ids], 25423, "CH highest rank is 25423")
for i = 1, #weave.SPELL_GROUPS do
    local group = weave.SPELL_GROUPS[i]
    local family = weave.FAMILIES[i] or ("?" .. tostring(i))
    eq(group.abbrev, family, "group " .. i .. " abbrev matches FAMILIES")
    check(type(group.label) == "string" and group.label ~= "", "group " .. i .. " has a label")
    check(type(group.ids) == "table" and #group.ids > 0, "group " .. i .. " has ids")
    local ascending, all_numbers = true, true
    for j = 1, #group.ids do
        if type(group.ids[j]) ~= "number" then all_numbers = false end
        if j > 1 and group.ids[j] <= group.ids[j - 1] then ascending = false end
    end
    check(ascending, "group " .. i .. " ids ascend (low -> high rank)")
    check(all_numbers, "group " .. i .. " ids are numbers")
end
for i = 1, #weave.FAMILIES do
    local family = weave.FAMILIES[i]
    local color = weave.FAMILY_COLORS[family] or {}
    check(weave.FAMILY_COLORS[family] ~= nil, "FAMILY_COLORS has " .. family)
    for k = 1, 4 do
        check(type(color[k]) == "number" and color[k] >= 0 and color[k] <= 1,
            "FAMILY_COLORS." .. family .. "[" .. k .. "] in [0, 1]")
    end
    eq(color[4], 1, "FAMILY_COLORS." .. family .. " alpha is 1")
end

if failures == 0 then
    print("PASS  weave_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  weave_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
