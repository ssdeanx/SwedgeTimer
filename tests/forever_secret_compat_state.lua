-- tests/forever_secret_compat_state.lua: offline verification of the restricted-read
-- (secret value) paths compat.lua gains for WoW Forever (Camelot 1.60 / Interface 16001).
--
-- On the Mainline-code clients a cooldown restriction (combat, encounter, challenge, PvP)
-- makes C_Spell.GetSpellCooldown return a SpellCooldownInfo whose startTime/duration are
-- SECRET, and C_UnitAuras.GetAuraDataByIndex RAISE (RequiresUnitAuraAccess,
-- FailureMode = "Error") on a secret aura row instead of reporting it absent. Both used to
-- degrade silently into "nothing is on cooldown" / a BugSack error.
--
-- This suite drives the REAL compat.lua through client stubs:
--   * api.UnitAura (C_UnitAuras branch): the C_Secrets per-index precheck skips a row the
--     client would raise on, the read itself is pcall-wrapped, and the classic global
--     branch is untouched (no precheck, no pcall, all ten values identical).
--   * api.GetSpellCooldown: all four classic returns are secret-checked, a restricted
--     SpellCooldownInfo is recovered through C_Spell.GetSpellCooldownDuration's
--     LuaDurationObject when that object reports HasSecretValues() == false, and otherwise
--     degrades to the all-zero shape with a fifth `restricted` return of true. The fallback
--     is Mainline-only, so Era/TBC/Wrath can never reach it.
--   * api.GetPlayerPower: the additive secret-SAFE reader for the primary-resource bar.
--     UnitPower/UnitPowerMax are SecretWhenUnitPowerRestricted/SecretWhenUnitPowerMaxRestricted
--     on origin/forever (UnitDocumentation.lua ~2732-2747 / ~2801-2824), so the widget path
--     must receive the RAW readings plus a restricted flag; the nil-on-secret
--     api.UnitPower/api.UnitPowerMax contract is unchanged for every arithmetic consumer
--     (classes/*.lua). Blizzard's own mana bar feeds the raw values to a StatusBar
--     (Blizzard_UnitFrame/Mainline/UnitFrame.lua:948-970).
--
-- Run from the repo root: lua5.1 tests/forever_secret_compat_state.lua  (any cwd works).

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

--=========================================================================================
-- Simulated secrets
--=========================================================================================
-- Real secrets keep their underlying type, so type() cannot see them; issecretvalue() is
-- the only probe. The fixtures mirror that: ordinary values flagged in a side table.
local SECRETS = {}
local function secret(value)
    SECRETS[value] = true
    return value
end

local SECRET_START = secret(900001)
local SECRET_DURATION = secret(900002)
local SECRET_ENABLED = secret(7)
local SECRET_MOD_RATE = secret(900003)
local SECRET_POWER = secret(910001)
local SECRET_POWER_MAX = secret(910002)

--=========================================================================================
-- Client fixtures
--=========================================================================================

local function aura_data(overrides)
    local data = {
        name = "Bloodlust", icon = 1, applications = 1, dispelName = "Magic",
        duration = 40, expirationTime = 140, sourceUnit = "player",
        isStealable = false, nameplateShowPersonal = true, spellId = 2825,
    }
    for k, v in pairs(overrides or {}) do data[k] = v end
    return data
end

local function classic_aura_row(overrides)
    local row = {
        name = "Bloodlust", icon = 1, applications = 1, dispelName = "Magic",
        duration = 40, expirationTime = 140, sourceUnit = "player",
        isStealable = false, nameplateShowPersonal = true, spellId = 2825,
    }
    for k, v in pairs(overrides or {}) do row[k] = v end
    return row
end

-- LuaDurationObject stub: the real object answers these four methods, and only
-- HasSecretValues is documented as never secret.
local function duration_object(remaining, total, start_time, has_secret)
    local object = {}
    function object:HasSecretValues() return has_secret end
    function object:GetRemainingDuration() return remaining end
    function object:GetTotalDuration() return total end
    function object:GetStartTime() return start_time end
    return object
end

local function throwing_duration_object()
    local object = {}
    function object:HasSecretValues() return false end
    function object:GetRemainingDuration() error("restricted") end
    function object:GetTotalDuration() error("restricted") end
    function object:GetStartTime() error("restricted") end
    return object
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- A fresh client per build: a throwaway global table (env._G = env, so compat's
-- rawget(_G, ...) probes read the stubs and nothing leaks onto the host). Client functions
-- read mutable sb fields, so a test flips a reading without reloading compat.
local function build(opts)
    opts = opts or {}
    local sb = {
        clock = 100,
        usable = true,
        insufficient = nil,
        classic_cooldown = { 5, 1.5, 1, 1 },
        classic_cooldown_calls = 0,
        info = { startTime = 5, duration = 1.5, isEnabled = true, modRate = 1 },
        info_by_token = {},
        info_calls = 0,
        duration_calls = 0,
        duration_ignore_gcd = nil,
        duration_object = nil,
        duration_throws = false,
        cooldown_secrecy = nil,
        state_throws = false,
        -- Duration-surface fixtures (Forever native text/colour path).
        binding = nil,
        binding_calls = 0,
        formatter = nil,
        formatter_calls = 0,
        abbrev_formatter = nil,
        abbrev_calls = 0,
        curve = nil,
        curve_points = nil,
        aura_table = aura_data(),
        aura = classic_aura_row(),
        aura_reads = 0,
        aura_raises = false,
        classic_aura_calls = 0,
        precheck_result = false,
        precheck_throws = false,
        precheck_calls = 0,
        has_secret_restrictions = false,
        -- Primary power: the raw reader passes these through; the nil-on-secret wrappers
        -- (api.UnitPower/api.UnitPowerMax) keep hiding a restricted value from arithmetic.
        power = 40,
        power_max = 100,
        power_calls = 0,
        power_max_calls = 0,
        power_unit = nil,
        power_type_arg = nil,
    }

    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = opts.project or 18
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_CAMELOT = 18
    env.GetBuildInfo = function() return "1.60.1", "00000", "today", opts.interface or 16001 end
    env.GetTime = function() return sb.clock end
    env.GetTimePreciseSec = function() return sb.clock end
    if opts.with_issecret ~= false then
        env.issecretvalue = function(value)
            return SECRETS[value] == true
        end
    end

    -- The classic globals: UnitAura is absent by default (the stubbed environment is the
    -- Mainline-code shape); GetSpellCooldown is present unless a build isolates C_Spell.
    if opts.classic_global ~= false then
        env.GetSpellCooldown = function()
            sb.classic_cooldown_calls = sb.classic_cooldown_calls + 1
            local cd = sb.classic_cooldown
            if not cd then return 0, 0, 0, 0 end
            return cd[1], cd[2], cd[3], cd[4]
        end
    end
    if opts.classic_aura then
        env.UnitAura = function()
            sb.classic_aura_calls = sb.classic_aura_calls + 1
            local row = sb.aura
            if not row then return nil end
            return row.name, row.icon, row.applications, row.dispelName, row.duration,
                row.expirationTime, row.sourceUnit, row.isStealable,
                row.nameplateShowPersonal, row.spellId
        end
    end

    -- UnitPower / UnitPowerMax: present on every shipped client, and the source of the
    -- primary power. They are absent only in the explicit "no power API" builds below.
    if opts.with_unit_power ~= false then
        env.UnitPower = function(unit, power_type)
            sb.power_calls = sb.power_calls + 1
            sb.power_unit = unit
            sb.power_type_arg = power_type
            return sb.power
        end
    end
    if opts.with_unit_power_max ~= false then
        env.UnitPowerMax = function(unit, power_type)
            sb.power_max_calls = sb.power_max_calls + 1
            return sb.power_max
        end
    end

    if opts.c_spell ~= false then
        env.C_Spell = {
            GetSpellCooldown = function(spell)
                sb.info_calls = sb.info_calls + 1
                if sb.state_throws then error("restricted state") end
                local info = sb.info_by_token[spell] or sb.info
                if not info then return nil end
                return {
                    startTime = info.startTime,
                    duration = info.duration,
                    isEnabled = info.isEnabled,
                    modRate = info.modRate,
                    -- NeverSecret fields: plain booleans even when timing is secret.
                    isOnGCD = info.isOnGCD,
                    isActive = info.isActive,
                }
            end,
            IsSpellUsable = function() return sb.usable, sb.insufficient end,
        }
        if opts.with_duration ~= false then
            env.C_Spell.GetSpellCooldownDuration = function(spell, ignore_gcd)
                sb.duration_calls = sb.duration_calls + 1
                sb.duration_token = spell
                sb.duration_ignore_gcd = ignore_gcd
                if sb.duration_throws then error("restricted") end
                return sb.duration_object
            end
        end
    end

    if opts.with_c_unit_auras ~= false then
        env.C_UnitAuras = {
            GetAuraDataByIndex = function()
                sb.aura_reads = sb.aura_reads + 1
                if sb.aura_raises then error("aura index is restricted") end
                return sb.aura_table
            end,
        }
    end

    if opts.with_c_secrets ~= false then
        env.C_Secrets = {
            ShouldUnitAuraIndexBeSecret = function(unit, index, filter)
                sb.precheck_calls = sb.precheck_calls + 1
                if sb.precheck_throws then error("restricted") end
                return sb.precheck_result
            end,
            HasSecretRestrictions = function()
                return sb.has_secret_restrictions
            end,
            ShouldSpellCooldownBeSecret = function(spell)
                sb.secrecy_token = spell
                return sb.cooldown_secrecy
            end,
        }
    end

    if opts.duration_surface then
        env.Enum = {
            SecondsFormatterAbbreviation = { None = 0, Truncate = 1, OneLetter = 2 },
            SecondsFormatterInterval = { Seconds = 0, Minutes = 1, Hours = 2, Days = 3 },
            SecondsFormatterRounding = { RoundUp = 0, Truncate = 1 },
            DurationTextBindingProperty = { RemainingDuration = 0, RemainingPercent = 1 },
        }
        env.C_StringUtil = {
            CreateSecondsFormatter = function()
                sb.formatter_calls = sb.formatter_calls + 1
                local f = sb.formatter or opts.formatter
                if f then return f end
                local formatter = { calls = {} }
                local function setter(name)
                    return function(_, value)
                        formatter.calls[name] = value
                        if formatter.throw_on == name then error("unexpected setter") end
                    end
                end
                formatter.SetDefaultAbbreviation = setter("SetDefaultAbbreviation")
                formatter.SetMinInterval = setter("SetMinInterval")
                formatter.SetMaxInterval = setter("SetMaxInterval")
                formatter.SetRounding = setter("SetRounding")
                formatter.SetDesiredUnitCount = setter("SetDesiredUnitCount")
                formatter.SetCanRoundUpLastUnit = setter("SetCanRoundUpLastUnit")
                formatter.SetMillisecondsThreshold = setter("SetMillisecondsThreshold")
                sb.formatter = formatter
                return formatter
            end,
            CreateNumericRuleFormatter = function()
                if opts.abbrev_throws then error("injected numeric-rule-formatter failure") end
                sb.abbrev_calls = sb.abbrev_calls + 1
                local formatter = { calls = {} }
                formatter.AddBreakpoint = function(_, breakpoint)
                    formatter.breakpoint = breakpoint
                    formatter.calls.AddBreakpoint = true
                end
                formatter.Format = function(_, value)
                    return tostring(math.floor(value))
                end
                sb.abbrev_formatter = formatter
                return formatter
            end,
        }
        env.C_CurveUtil = {
            CreateColorCurve = function()
                if opts.curve_throws then error("no curves") end
                local curve = { points = {} }
                function curve:AddPoint(x, color)
                    if opts.curve_point_throws then error("no point") end
                    curve.points[#curve.points + 1] = { x = x, color = color }
                end
                sb.curve = curve
                return curve
            end,
        }
        env.C_DurationUtil = {
            CreateDurationTextBinding = function()
                if opts.binding_throws then error("no binding") end
                sb.binding_calls = sb.binding_calls + 1
                return sb.binding or opts.binding or {}
            end,
        }
        if opts.drop_enum then
            env.Enum = nil
        end
        if opts.drop_duration_util then
            env.C_DurationUtil = nil
        end
        if opts.drop_string_util then
            env.C_StringUtil = nil
        end
    end

    local st = {}
    local chunk = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "SwedgeTimer", st)
    if not ok then
        failures = failures + 1
        print("FAIL  loading compat.lua: " .. tostring(err))
    end
    sb.env, sb.st = env, st
    return sb
end

-- The public wrapper returns the four classic values plus the restricted fifth; pack them
-- so each case can assert the fields it cares about without silently dropping a return.
local function cooldown(api, spell)
    local start_time, duration, enabled, mod_rate, restricted = api.GetSpellCooldown(spell)
    return {
        start = start_time,
        duration = duration,
        enabled = enabled,
        mod_rate = mod_rate,
        restricted = restricted,
    }
end

--=========================================================================================
-- 1. api.UnitAura: the C_UnitAuras branch
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    check(sb.env.UnitAura == nil, "sandbox: UnitAura is absent (Mainline-code shape)")

    -- Control: no secret, no precheck hit -> the ten-value classic shape.
    local name, icon, count, dispel, duration, expiration, source, stealable, personal,
    spell_id = api.UnitAura("player", 1, "HELPFUL")
    eq(name, "Bloodlust", "aura control: name passes through")
    eq(icon, 1, "aura control: icon passes through")
    eq(count, 1, "aura control: applications become the count")
    eq(dispel, "Magic", "aura control: dispelName passes through")
    eq(duration, 40, "aura control: duration passes through")
    eq(expiration, 140, "aura control: expirationTime passes through")
    eq(source, "player", "aura control: sourceUnit passes through")
    eq(stealable, false, "aura control: isStealable passes through")
    eq(personal, true, "aura control: nameplateShowPersonal passes through")
    eq(spell_id, 2825, "aura control: spellId passes through")
    eq(sb.aura_reads, 1, "aura control: GetAuraDataByIndex is called once")

    -- Precheck exactly true: the row is skipped and the API is NOT called.
    sb.precheck_result = true
    sb.aura_reads = 0
    sb.precheck_calls = 0
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, nil, "precheck true: the wrapper reports the row absent")
    eq(sb.aura_reads, 0, "precheck true: GetAuraDataByIndex is never called")
    eq(sb.precheck_calls, 1, "precheck true: the per-index probe is consulted first")

    -- Precheck truthy but not exactly true: still read (the contract is "exactly true").
    sb.precheck_result = 1
    sb.aura_reads = 0
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, "Bloodlust", "precheck truthy non-boolean: the row is still read")
    eq(sb.aura_reads, 1, "precheck truthy non-boolean: GetAuraDataByIndex is called")

    -- The API raising on a secret row is caught: absent, never a propagated error.
    sb.precheck_result = false
    sb.aura_raises = true
    local ok, value = pcall(api.UnitAura, "player", 1, "HELPFUL")
    check(ok, "aura API raise: the wrapper does not throw")
    eq(value, nil, "aura API raise: the row reads absent")

    -- A probe that itself throws is ignored (unknown is never "secret").
    sb.aura_raises = false
    sb.precheck_throws = true
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, "Bloodlust", "throwing precheck: the row is still read")
    sb.precheck_throws = false

    -- The whole-entry secret rule is unchanged: one secret field -> absent.
    sb.aura_table = aura_data({ duration = SECRET_DURATION })
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, nil, "secret aura field: the whole entry reads absent")
    sb.aura_table = aura_data()

    -- A client without C_Secrets keeps reading (the precheck is optional).
    local no_secrets = build({ with_c_secrets = false })
    eq(no_secrets.st.api.UnitAura("player", 1, "HELPFUL"), "Bloodlust",
        "no C_Secrets: the aura is still read")
    eq(no_secrets.aura_reads, 1, "no C_Secrets: GetAuraDataByIndex is called")

    -- A client without C_UnitAuras is the classic/absent shape, untouched by this branch.
    local no_c_unit_auras = build({ with_c_unit_auras = false })
    eq(no_c_unit_auras.st.api.UnitAura("player", 1, "HELPFUL"), nil,
        "no aura API at all: the wrapper reports absent")
end

--=========================================================================================
-- 2. api.UnitAura: the classic global branch (SEC-4, 2026-11-06)
--=========================================================================================
-- The classic global is a deprecation shim over the raisable C_UnitAuras read on clients
-- that ship it, so the branch now mirrors the C_UnitAuras one: the per-index C_Secrets
-- precheck first, then the call under pcall. A readable row is unchanged; a prechecked
-- index never reaches the global; a throwing global reads absent.
do
    -- (a) A readable classic row passes through byte-identically.
    local sb = build({ classic_aura = true })
    local api = sb.st.api

    local name, icon, count, dispel, duration, expiration, source, stealable, personal,
    spell_id = api.UnitAura("player", 1, "HELPFUL")
    eq(name, "Bloodlust", "classic aura: name unchanged")
    eq(icon, 1, "classic aura: icon unchanged")
    eq(count, 1, "classic aura: count unchanged")
    eq(dispel, "Magic", "classic aura: dispelName unchanged")
    eq(duration, 40, "classic aura: duration unchanged")
    eq(expiration, 140, "classic aura: expirationTime unchanged")
    eq(source, "player", "classic aura: sourceUnit unchanged")
    eq(stealable, false, "classic aura: isStealable unchanged")
    eq(personal, true, "classic aura: nameplateShowPersonal unchanged")
    eq(spell_id, 2825, "classic aura: spellId unchanged")
    eq(sb.precheck_calls, 1, "classic aura: the C_Secrets precheck is consulted")
    eq(sb.aura_reads, 0, "classic aura: C_UnitAuras is never called")
    eq(sb.classic_aura_calls, 1, "classic aura: the classic global is called once")

    -- The classic branch keeps its own whole-entry secret guard.
    sb.aura = classic_aura_row({ expirationTime = SECRET_DURATION })
    eq(api.UnitAura("player", 1, "HELPFUL"), nil,
        "classic aura secret field: the whole entry reads absent")

    -- (b) A prechecked restricted index reads absent and never reaches the global.
    local restricted = build({ classic_aura = true })
    restricted.precheck_result = true
    eq(restricted.st.api.UnitAura("player", 1, "HELPFUL"), nil,
        "classic aura precheck: a restricted index reads absent")
    eq(restricted.precheck_calls, 1, "classic aura precheck: the probe ran once")
    eq(restricted.classic_aura_calls, 0,
        "classic aura precheck: the classic global is never called for a restricted index")

    -- (c) A throwing classic global is contained by the pcall (Forever's shim can raise
    -- on a restricted row when C_Secrets is absent).
    local thrown = build({ classic_aura = true })
    thrown.env.UnitAura = function() error("restricted classic aura") end
    local ok, value = pcall(thrown.st.api.UnitAura, "player", 1, "HELPFUL")
    check(ok, "classic aura throw: a throwing classic global is contained")
    eq(value, nil, "classic aura throw: a throwing classic global reads absent")

    -- A classic-line client without C_Secrets: the precheck is an exact no-op.
    local no_secrets = build({ classic_aura = true, with_c_secrets = false })
    eq(no_secrets.st.api.UnitAura("player", 1, "HELPFUL"), "Bloodlust",
        "classic aura no C_Secrets: the readable row still passes through")
    eq(no_secrets.classic_aura_calls, 1,
        "classic aura no C_Secrets: the classic global is read once")
end

--=========================================================================================
-- 3. api.GetSpellCooldown: the four-value contract and the fifth `restricted`
--=========================================================================================
do
    -- Control on the Forever client: both sources readable -> unchanged four values, no flag.
    local sb = build()
    check(sb.st.is_mainline == true, "sandbox: Forever reports is_mainline")
    local cd = cooldown(sb.st.api, 2825)
    eq(cd.start, 5, "cooldown control: start passes through")
    eq(cd.duration, 1.5, "cooldown control: duration passes through")
    eq(cd.enabled, 1, "cooldown control: enabled passes through")
    eq(cd.mod_rate, 1, "cooldown control: modRate passes through")
    eq(cd.restricted, nil, "cooldown control: no restricted fifth")

    -- Control on a classic-line client (no C_Spell at all).
    local classic = build({ c_spell = false, project = 2 })
    check(classic.st.is_mainline == false, "sandbox: TBC is not Mainline-code")
    cd = cooldown(classic.st.api, 2825)
    eq(cd.start, 5, "classic cooldown control: start passes through")
    eq(cd.duration, 1.5, "classic cooldown control: duration passes through")
    eq(cd.enabled, 1, "classic cooldown control: enabled passes through")
    eq(cd.mod_rate, 1, "classic cooldown control: modRate passes through")
    eq(cd.restricted, nil, "classic cooldown control: no restricted fifth")

    -- Arity on a classic-line client: a readable read keeps the exact classic
    -- four-value shape, including the readable "not on cooldown" zero read (the case
    -- a restricted flag must never touch). Era/TBC/Wrath can never observe a fifth.
    local zero = build({ c_spell = false, project = 2 })
    zero.classic_cooldown = { 0, 0, 0, 0 }
    eq(select("#", zero.st.api.GetSpellCooldown(2825)), 4,
        "classic-line readable zero: exactly the classic four values")
    eq(cooldown(zero.st.api, 2825).restricted, nil,
        "classic-line readable zero: no restricted fifth")

    -- The restricted read is the ONLY shape that carries the fifth value.
    local arity = build({ c_spell = false })
    arity.classic_cooldown = { SECRET_START, SECRET_DURATION, 0, 0 }
    eq(select("#", arity.st.api.GetSpellCooldown(2825)), 5,
        "restricted read: the fifth value is present")

    -- All four classic returns are secret-checked: no comparison ever touches a secret.
    local secret_fields = {
        { "start", { SECRET_START, 1.5, 1, 1 } },
        { "duration", { 5, SECRET_DURATION, 1, 1 } },
        { "enabled", { 5, 1.5, SECRET_ENABLED, 1 } },
        { "modRate", { 5, 1.5, 1, SECRET_MOD_RATE } },
    }
    for i = 1, #secret_fields do
        local label, reading = secret_fields[i][1], secret_fields[i][2]
        local secret_sb = build({ c_spell = false })
        secret_sb.classic_cooldown = reading
        local ok, secret_cd = pcall(cooldown, secret_sb.st.api, 2825)
        check(ok, "secret classic " .. label .. ": the read does not throw")
        eq(secret_cd.start, 0, "secret classic " .. label .. ": start degrades")
        eq(secret_cd.duration, 0, "secret classic " .. label .. ": duration degrades")
        eq(secret_cd.enabled, 0, "secret classic " .. label .. ": enabled degrades")
        eq(secret_cd.mod_rate, 0, "secret classic " .. label .. ": modRate degrades")
        eq(secret_cd.restricted, true,
            "secret classic " .. label .. ": fifth flags the restricted read")
    end
end

--=========================================================================================
-- 4. The Mainline duration-object recovery
--=========================================================================================
do
    -- A readable object converts back into the classic four-value shape:
    -- start = now - (total - remaining), duration = total, enabled = 1, modRate = 1.
    local sb = build({ classic_global = false })
    sb.info = { startTime = SECRET_START, duration = SECRET_DURATION, isEnabled = true,
        modRate = 1 }
    sb.duration_object = duration_object(3, 12, 88, false)
    local cd = cooldown(sb.st.api, 2825)
    eq(cd.start, 91, "duration object: start = now - (total - remaining)")
    eq(cd.duration, 12, "duration object: duration = total")
    eq(cd.enabled, 1, "duration object: enabled = 1")
    eq(cd.mod_rate, 1, "duration object: modRate = 1")
    eq(cd.restricted, nil, "duration object: no restricted fifth")
    eq(sb.duration_calls, 1, "duration object: the fallback is consulted exactly once")
    eq(sb.duration_token, 2825, "duration object: the fallback queries the same spell")

    -- HasSecretValues() exactly true -> the individual reads are never trusted.
    sb.duration_object = duration_object(3, 12, 88, true)
    cd = cooldown(sb.st.api, 2825)
    check(cd.start == 0 and cd.duration == 0 and cd.enabled == 0 and cd.mod_rate == 0,
        "HasSecretValues true: the all-zero degraded shape")
    eq(cd.restricted, true, "HasSecretValues true: fifth flags the restricted read")

    -- Anything but exactly false declines (nil and truthy non-booleans included).
    sb.duration_object = duration_object(3, 12, 88, nil)
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "HasSecretValues nil: no duration is trusted")
    eq(cd.restricted, true, "HasSecretValues nil: fifth flags the restricted read")

    -- A failing individual read declines.
    sb.duration_object = throwing_duration_object()
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "throwing duration reads: no duration is trusted")
    eq(cd.restricted, true, "throwing duration reads: fifth flags the restricted read")

    -- A non-positive total is not a cooldown.
    sb.duration_object = duration_object(0, 0, 88, false)
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "zero total: no duration is reported")
    eq(cd.restricted, true, "zero total: fifth flags the restricted read")

    -- Non-finite readings are refused too.
    sb.duration_object = duration_object(math.huge, 12, 88, false)
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "infinite remaining: no duration is reported")
    eq(cd.restricted, true, "infinite remaining: fifth flags the restricted read")

    sb.duration_object = duration_object(0 / 0, 12, 88, false)
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "NaN remaining: no duration is reported")
    eq(cd.restricted, true, "NaN remaining: fifth flags the restricted read")

    -- Every individual read is required: one unusable answer declines the whole object.
    sb.duration_object = duration_object(3, 12, 88, false)
    sb.duration_object.GetRemainingDuration = function() return nil end
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "missing remaining: no duration is reported")
    eq(cd.restricted, true, "missing remaining: fifth flags the restricted read")

    sb.duration_object = duration_object(3, 12, 88, false)
    sb.duration_object.GetTotalDuration = function() return "12" end
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "non-numeric total: no duration is reported")
    eq(cd.restricted, true, "non-numeric total: fifth flags the restricted read")

    sb.duration_object = duration_object(3, 12, 88, false)
    sb.duration_object.GetStartTime = function() return nil end
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "missing object start: no duration is reported")
    eq(cd.restricted, true, "missing object start: fifth flags the restricted read")

    -- A secret duration alone (readable start) is not trusted either: the info table can
    -- hide each field independently, and a secret duration must never be compared.
    local secret_duration = build({ classic_global = false, with_duration = false })
    secret_duration.info = { startTime = 5, duration = SECRET_DURATION, isEnabled = true,
        modRate = 1 }
    local ok, secret_cd = pcall(cooldown, secret_duration.st.api, 2825)
    check(ok, "secret info duration alone: the read does not throw")
    if ok then
        eq(secret_cd.duration, 0, "secret info duration alone: no duration is reported")
        eq(secret_cd.restricted, true,
            "secret info duration alone: fifth flags the restricted read")
    end

    -- An object with no duration methods at all declines instead of throwing.
    sb.duration_object = {}
    cd = cooldown(sb.st.api, 2825)
    eq(cd.duration, 0, "object without methods: no duration is reported")
    eq(cd.restricted, true, "object without methods: fifth flags the restricted read")

    -- No probe at all on the client: degraded, flagged, no throw.
    local no_probe = build({ classic_global = false, with_duration = false })
    no_probe.info = { startTime = SECRET_START, duration = SECRET_DURATION, isEnabled = true,
        modRate = 1 }
    cd = cooldown(no_probe.st.api, 2825)
    check(cd.start == 0 and cd.duration == 0 and cd.enabled == 0 and cd.mod_rate == 0,
        "no duration probe: the all-zero degraded shape")
    eq(cd.restricted, true, "no duration probe: fifth flags the restricted read")

    -- The probe itself throwing is the same decline.
    local throws = build({ classic_global = false })
    throws.info = { startTime = SECRET_START, duration = SECRET_DURATION, isEnabled = true,
        modRate = 1 }
    throws.duration_throws = true
    cd = cooldown(throws.st.api, 2825)
    eq(cd.duration, 0, "throwing duration probe: no duration is reported")
    eq(cd.restricted, true, "throwing duration probe: fifth flags the restricted read")
end

--=========================================================================================
-- 4b. A readable source always wins over a restricted one
--=========================================================================================
-- The fifth return means "no source could answer", never "one source was restricted":
-- a readable reading (zeros included - that IS "not on cooldown") must survive a
-- restricted read from the other source, or a perfectly good cooldown is discarded and
-- an answerable tick is reported unknown.
do
    -- (a) The classic global is restricted, C_Spell answers: the C_Spell values stand
    -- and the flag clears. Before the fix the readable 12 s cooldown was thrown away
    -- and the public API returned the all-zero restricted shape.
    local sb = build()
    sb.classic_cooldown = { SECRET_START, SECRET_DURATION, SECRET_ENABLED, SECRET_MOD_RATE }
    sb.info = { startTime = 5, duration = 12, isEnabled = true, modRate = 1 }
    local cd = cooldown(sb.st.api, 2825)
    eq(cd.start, 5, "readable retail over restricted classic: start survives")
    eq(cd.duration, 12, "readable retail over restricted classic: duration survives")
    eq(cd.enabled, 1, "readable retail over restricted classic: enabled survives")
    eq(cd.mod_rate, 1, "readable retail over restricted classic: modRate survives")
    eq(cd.restricted, nil, "readable retail over restricted classic: no restricted fifth")

    -- (b) The primary read answers readably ("not on cooldown"), the alternate rank is
    -- restricted: the readable primary is never demoted to unknown.
    local primary = build({ classic_global = false, with_duration = false })
    primary.info_by_token[2825] = { startTime = 0, duration = 0, isEnabled = true,
        modRate = 1 }
    primary.info_by_token[32182] = { startTime = SECRET_START, duration = SECRET_DURATION,
        isEnabled = true, modRate = 1 }
    local primary_start, primary_duration, _, _, primary_flag =
        primary.st.api.GetSpellCooldown(2825, 32182)
    eq(primary_start, 0, "readable primary over restricted fallback: the primary reading stands")
    eq(primary_duration, 0, "readable primary over restricted fallback: no duration is invented")
    check(primary_flag ~= true,
        "readable primary over restricted fallback: the readable answer is not demoted")

    -- (c) The primary is restricted, the alternate rank answers readably (zeros): the
    -- readable fallback clears the flag. Before the fix the stale primary flag kept the
    -- whole read unknown.
    local fallback = build({ classic_global = false, with_duration = false })
    fallback.info_by_token[2825] = { startTime = SECRET_START, duration = SECRET_DURATION,
        isEnabled = true, modRate = 1 }
    fallback.info_by_token[32182] = { startTime = 0, duration = 0, isEnabled = true,
        modRate = 1 }
    local fb_start, fb_duration, _, _, fb_flag = fallback.st.api.GetSpellCooldown(2825, 32182)
    eq(fb_start, 0, "restricted primary over readable fallback: the readable zeros stand")
    eq(fb_duration, 0, "restricted primary over readable fallback: no duration is invented")
    check(fb_flag ~= true,
        "restricted primary over readable fallback: the flag clears")

    -- (d) Both restricted: the flag stands (nothing answered).
    local both = build({ classic_global = false, with_duration = false })
    both.info = { startTime = SECRET_START, duration = SECRET_DURATION, isEnabled = true,
        modRate = 1 }
    local d_start, d_duration, _, _, d_flag = both.st.api.GetSpellCooldown(2825, 32182)
    eq(d_start, 0, "both restricted: the all-zero degraded shape")
    eq(d_duration, 0, "both restricted: no duration is invented")
    eq(d_flag, true, "both restricted: the fifth still flags the unknown read")
end

--=========================================================================================
-- 5. The fallback is Mainline-only: Era/TBC/Wrath can never reach it
--=========================================================================================
do
    -- Synthetic classic-line client that still reports secret values (a real Era/TBC/Wrath
    -- client has no issecretvalue at all, so no restricted read can occur there). The
    -- st.is_mainline gate must keep the duration object out of the path regardless.
    local sb = build({ project = 2 })
    check(sb.st.is_mainline == false, "sandbox: TBC is not Mainline-code")
    sb.classic_cooldown = { SECRET_START, SECRET_DURATION, 1, 1 }
    sb.info = { startTime = SECRET_START, duration = SECRET_DURATION, isEnabled = true,
        modRate = 1 }
    sb.duration_object = duration_object(3, 12, 88, false)
    local cd = cooldown(sb.st.api, 2825)
    check(cd.start == 0 and cd.duration == 0 and cd.enabled == 0 and cd.mod_rate == 0,
        "classic-line family: the all-zero degraded shape")
    eq(cd.restricted, true, "classic-line family: fifth flags the restricted read")
    eq(sb.duration_calls, 0, "classic-line family: GetSpellCooldownDuration is never called")
end

--=========================================================================================
-- 6. Control: the rest of the C_Spell surface is untouched
--=========================================================================================
do
    local sb = build()
    local usable, insufficient = sb.st.api.IsSpellUsable(2825)
    eq(usable, true, "C_Spell.IsSpellUsable control: usable passes through")
    eq(insufficient, nil, "C_Spell.IsSpellUsable control: insufficient passes through")
end

--=========================================================================================
-- 7. api.GetPlayerPower: the RAW secret-safe reader for the power bar
--=========================================================================================
-- UnitPower/UnitPowerMax are SecretWhenUnitPowerRestricted / SecretWhenUnitPowerMaxRestricted
-- on origin/forever (UnitDocumentation.lua ~2732-2747, ~2801-2824). The widget branch must
-- receive the raw reading plus a flag, while the arithmetic wrappers keep reporting nil.
-- Blizzard's own mana bar passes the raw values into StatusBar:SetMinMaxValues/SetValue
-- (Blizzard_UnitFrame/Mainline/UnitFrame.lua:948-970), so a StatusBar can render them.
do
    local sb = build()
    local api = sb.st.api
    check(type(api.GetPlayerPower) == "function",
        "compat defines the raw secret-safe reader (api.GetPlayerPower)")
    if type(api.GetPlayerPower) == "function" then
        -- Control: a readable modern read -> raw pair + restricted exactly false (a caller
        -- compares the flag, so nil would be a lie).
        local value, max_value, restricted = api.GetPlayerPower(0)
        eq(value, 40, "raw reader control: the raw value passes through")
        eq(max_value, 100, "raw reader control: the raw max passes through")
        eq(restricted, false, "raw reader control: restricted is exactly false")
        eq(select("#", api.GetPlayerPower(0)), 3, "raw reader: exactly three returns")
        eq(sb.power_unit, "player", "raw reader: reads the player unit")
        eq(sb.power_type_arg, 0, "raw reader: passes the resolved power type through")

        -- A secret VALUE must come back raw (never nil - a nil is what hid the bar).
        sb.power = SECRET_POWER
        value, max_value, restricted = api.GetPlayerPower(0)
        eq(value, SECRET_POWER, "secret value: passed through raw, never nil'd")
        eq(max_value, 100, "secret value: the readable max passes through")
        eq(restricted, true, "secret value: the flag is set")

        -- A secret MAX is the same: raw max + flag (value still readable).
        sb.power, sb.power_max = 40, SECRET_POWER_MAX
        value, max_value, restricted = api.GetPlayerPower(0)
        eq(value, 40, "secret max: the readable value passes through")
        eq(max_value, SECRET_POWER_MAX, "secret max: passed through raw, never nil'd")
        eq(restricted, true, "secret max: the flag is set")

        -- Both restricted.
        sb.power, sb.power_max = SECRET_POWER, SECRET_POWER_MAX
        value, max_value, restricted = api.GetPlayerPower(0)
        eq(value, SECRET_POWER, "both secret: the value is raw")
        eq(max_value, SECRET_POWER_MAX, "both secret: the max is raw")
        eq(restricted, true, "both secret: the flag is set")

        -- The nil-on-secret contract of the pair every arithmetic consumer uses is
        -- UNCHANGED: the additive reader must not weaken it.
        eq(api.UnitPower("player", 0), nil,
            "api.UnitPower still reports nil on a secret (arithmetic contract intact)")
        eq(api.UnitPowerMax("player", 0), nil,
            "api.UnitPowerMax still reports nil on a secret (arithmetic contract intact)")
        sb.power, sb.power_max = 40, 100
        eq(api.UnitPower("player", 0), 40, "api.UnitPower control unchanged")
        eq(api.UnitPowerMax("player", 0), 100, "api.UnitPowerMax control unchanged")

        -- Classic-line clients: numbers + restricted exactly false.
        local classic = build({ project = 2 })
        value, max_value, restricted = classic.st.api.GetPlayerPower(0)
        eq(value, 40, "classic: raw value passes through")
        eq(max_value, 100, "classic: raw max passes through")
        eq(restricted, false, "classic: restricted is exactly false")

        -- A client with no issecretvalue at all (every Era/TBC/Wrath client): the flag can
        -- never be true, and the raw readings pass through.
        local no_probe = build({ project = 2, with_issecret = false })
        value, max_value, restricted = no_probe.st.api.GetPlayerPower(0)
        eq(value, 40, "no issecretvalue: the readable value passes through")
        eq(max_value, 100, "no issecretvalue: the readable max passes through")
        eq(restricted, false, "no issecretvalue: nothing can be secret")
        -- (The host-side SECRETS table cannot make a value secret when the client has no
        -- probe; that is the classic-line reality the flag contract must reflect.)
        no_probe.power = SECRET_POWER
        value, max_value, restricted = no_probe.st.api.GetPlayerPower(0)
        eq(value, SECRET_POWER, "no issecretvalue: the number still passes through raw")
        eq(max_value, 100, "no issecretvalue: the raw max still passes through")
        eq(restricted, false, "no issecretvalue: the flag stays false")

        -- Missing UnitPowerMax only: the value still passes through, nothing is invented.
        local no_max = build({ with_unit_power_max = false })
        value, max_value, restricted = no_max.st.api.GetPlayerPower(0)
        eq(value, 40, "no UnitPowerMax: the value passes through")
        eq(max_value, nil, "no UnitPowerMax: the max is nil, never invented")
        eq(restricted, false, "no UnitPowerMax: a readable value is not restricted")

        -- No power API at all: the reader exists and answers nils without throwing, and
        -- the old wrappers keep their 0 fallback.
        local absent = build({ with_unit_power = false, with_unit_power_max = false })
        check(type(absent.st.api.GetPlayerPower) == "function",
            "the reader exists on a client without UnitPower")
        local ok_read, absent_value, absent_max, absent_restricted =
            pcall(absent.st.api.GetPlayerPower, 0)
        check(ok_read, "no power API: the reader does not throw")
        eq(absent_value, nil, "no power API: the value is unknown")
        eq(absent_max, nil, "no power API: the max is unknown")
        eq(absent_restricted, false, "no power API: restricted is exactly false")
        eq(absent.st.api.UnitPower("player", 0), 0,
            "no power API: the additive reader does not change api.UnitPower's 0 fallback")
        eq(absent.st.api.UnitPowerMax("player", 0), 0,
            "no power API: api.UnitPowerMax's 0 fallback is unchanged")
    end
end


--=========================================================================================
-- 8. api.get_spell_cooldown_duration: the Forever opaque-handle reader
--=========================================================================================
-- T1 (bench/forever_hud_api_2026-11-08.md §4): C_Spell.GetSpellCooldownDuration carries no
-- SecretWhen* predicate, so its LuaDurationObject is a NON-secret handle whose values may be
-- secret. The addon holds the handle and hands it to the native sinks; it must never read a
-- number out of it. Forever-only + probe-gated, so every other client stays numeric.
do
    local sb = build()
    local api = sb.st.api
    local object = duration_object(3, 12, 88, false)
    sb.duration_object = object

    local got, has_secret = api.get_spell_cooldown_duration(2825)
    eq(got, object, "fduration: the opaque handle passes through")
    eq(has_secret, false, "fduration: HasSecretValues false is reported plain")
    eq(sb.duration_calls, 1, "fduration: the client reader is called once")
    eq(sb.duration_token, 2825, "fduration: the same spell id is queried")
    eq(sb.duration_ignore_gcd, false, "fduration: ignoreGCD defaults to false (the GCD is carried)")

    -- A secret-valued object is STILL usable: its secrecy lives inside the handle.
    sb.duration_object = duration_object(SECRET_DURATION, SECRET_DURATION, SECRET_DURATION, true)
    got, has_secret = api.get_spell_cooldown_duration(2825, true)
    check(got ~= nil, "fduration secret-valued: the handle is still returned")
    eq(has_secret, true, "fduration secret-valued: the probe answer is reported")
    eq(sb.duration_ignore_gcd, true, "fduration: ignoreGCD=true is forwarded")

    -- The probe answer must itself be plain: a secret answer declines.
    sb.duration_object = duration_object(3, 12, 88, secret(900042))
    eq(api.get_spell_cooldown_duration(2825), nil,
        "fduration: a secret HasSecretValues answer declines")

    -- An object without the probe is a plain handle: returned, flag nil.
    local bare = {}
    sb.duration_object = bare
    got, has_secret = api.get_spell_cooldown_duration(2825)
    eq(got, bare, "fduration: an object without the probe is returned")
    eq(has_secret, nil, "fduration: an absent probe reports no flag")

    -- A throwing probe / reader declines instead of propagating.
    sb.duration_object = { HasSecretValues = function() error("restricted") end }
    eq(api.get_spell_cooldown_duration(2825), nil, "fduration: a throwing probe declines")
    sb.duration_throws = true
    eq(api.get_spell_cooldown_duration(2825), nil, "fduration: a throwing reader declines")
    sb.duration_throws = false
    sb.duration_object = nil
    eq(api.get_spell_cooldown_duration(2825), nil, "fduration: a nil object is nil")

    -- Invalid token: no client call at all.
    sb.duration_calls = 0
    eq(api.get_spell_cooldown_duration({}), nil, "fduration: a table token declines")
    eq(sb.duration_calls, 0, "fduration: an invalid token never reaches the client")

    -- Non-Forever clients: the helper is an exact no-op (numeric paths untouched).
    local classic = build({ project = 2 })
    classic.duration_object = duration_object(3, 12, 88, false)
    eq(classic.st.api.get_spell_cooldown_duration(2825), nil,
        "fduration TBC: no duration object is produced")
    eq(classic.duration_calls, 0, "fduration TBC: the client reader is never called")
    local retail = build({ project = 1 })
    retail.duration_object = duration_object(3, 12, 88, false)
    eq(retail.st.api.get_spell_cooldown_duration(2825), nil,
        "fduration Retail: no duration object (Forever-only path)")
    eq(retail.duration_calls, 0, "fduration Retail: the client reader is never called")
    local absent = build({ with_duration = false })
    eq(absent.st.api.get_spell_cooldown_duration(2825), nil,
        "fduration: a client without the API answers nil")
end

--=========================================================================================
-- 9. api.get_spell_cooldown_state: the two NeverSecret SpellCooldownInfo fields
--=========================================================================================
-- isOnGCD / isActive stay plain booleans while the timing fields are secret
-- (SpellSharedDocumentation.lua:25,26,30), so the HUD/GCD can decide without a secret read.
do
    local sb = build()
    local api = sb.st.api
    sb.info = { startTime = SECRET_START, duration = SECRET_DURATION, isEnabled = true,
        modRate = 1, isOnGCD = false, isActive = true }
    local on_gcd, active = api.get_spell_cooldown_state(2825)
    eq(on_gcd, false, "fstate: isOnGCD passes through while the timing is secret")
    eq(active, true, "fstate: isActive passes through while the timing is secret")

    sb.info = { isOnGCD = 1, isActive = "yes" }
    on_gcd, active = api.get_spell_cooldown_state(2825)
    eq(on_gcd, false, "fstate: only exact true is a GCD")
    eq(active, false, "fstate: only exact true is active")

    -- A secret field declines the whole state (nothing is ever compared).
    sb.info = { isOnGCD = secret(900043), isActive = true }
    on_gcd, active = api.get_spell_cooldown_state(2825)
    eq(on_gcd, nil, "fstate: a secret isOnGCD declines the state")
    eq(active, nil, "fstate: the whole state declines with it")
    sb.info = { isOnGCD = false, isActive = secret(900044) }
    local second_on_gcd, second_active = api.get_spell_cooldown_state(2825)
    eq(second_on_gcd, nil, "fstate: a secret isActive declines on-GCD too")
    eq(second_active, nil, "fstate: a secret isActive declines the state")

    -- A throwing/missing read declines; nothing is compared.
    sb.state_throws = true
    on_gcd, active = api.get_spell_cooldown_state(2825)
    check(on_gcd == nil and active == nil, "fstate: a throwing read declines")
    sb.state_throws = false
    sb.info = nil
    on_gcd, active = api.get_spell_cooldown_state(2825)
    check(on_gcd == nil and active == nil, "fstate: a missing info declines")

    -- Non-Forever: two nil answers and no client call.
    local classic = build({ project = 2 })
    classic.info = { isOnGCD = true, isActive = true }
    eq(select("#", classic.st.api.get_spell_cooldown_state(2825)), 2,
        "fstate TBC: the helper still answers two values")
    eq(classic.st.api.get_spell_cooldown_state(2825), nil, "fstate TBC: no state is reported")
    eq(classic.info_calls, 0, "fstate TBC: the client is never queried")
end

--=========================================================================================
-- 10. api.get_spell_cooldown_secrecy: the client's own plain predicate answer
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api
    sb.cooldown_secrecy = true
    eq(api.get_spell_cooldown_secrecy(2825), true,
        "fsecrecy: the client's true answer passes through")
    eq(sb.secrecy_token, 2825, "fsecrecy: the same spell id is queried")
    sb.cooldown_secrecy = false
    eq(api.get_spell_cooldown_secrecy(2825), false,
        "fsecrecy: the client's false answer passes through")
    sb.cooldown_secrecy = nil
    eq(api.get_spell_cooldown_secrecy(2825), nil, "fsecrecy: an unanswered predicate is nil")
    sb.cooldown_secrecy = SECRET_DURATION
    eq(api.get_spell_cooldown_secrecy(2825), nil,
        "fsecrecy: a non-boolean answer is refused (never a secret branch)")

    -- No predicate / no Forever / no C_Secrets: nil, never a guess.
    local no_secrets = build({ with_c_secrets = false })
    eq(no_secrets.st.api.get_spell_cooldown_secrecy(2825), nil,
        "fsecrecy: a client without C_Secrets answers nil")
    local classic = build({ project = 2 })
    classic.cooldown_secrecy = true
    eq(classic.st.api.get_spell_cooldown_secrecy(2825), nil,
        "fsecrecy TBC: the Forever-only helper answers nil")
end

--=========================================================================================
-- 11. api.create_duration_text_binding / create_seconds_formatter / colour curve
--=========================================================================================
-- The native countdown path (T1 §5): the binding formats the opaque duration itself, the
-- formatter is configured with PLAIN arguments, and the colour curve is evaluated natively
-- against the secret remaining duration. Every helper is Forever-only and optional.
do
    local sb = build({ duration_surface = true })
    local api = sb.st.api

    local binding = api.create_duration_text_binding()
    check(binding ~= nil, "ftext: the binding is created")
    eq(sb.binding_calls, 1, "ftext: the client factory is called once")

    local formatter = api.create_seconds_formatter()
    check(formatter ~= nil, "ftext: the formatter is created")
    eq(sb.formatter_calls, 1, "ftext: the formatter factory is called once")
    eq(formatter.calls.SetDefaultAbbreviation, 0,
        "ftext: bare numbers (abbreviation None)")
    eq(formatter.calls.SetMinInterval, 0, "ftext: minimum interval is seconds")
    eq(formatter.calls.SetMaxInterval, 0,
        "ftext: cooldown text stays in plain seconds (no m/h abbreviations)")
    eq(formatter.calls.SetRounding, 1, "ftext: truncation (Blizzard's aura rounding)")
    eq(formatter.calls.SetDesiredUnitCount, 1, "ftext: one unit")
    eq(formatter.calls.SetCanRoundUpLastUnit, true, "ftext: last unit may round up")
    eq(formatter.calls.SetMillisecondsThreshold, 3,
        "ftext: one decimal below 3 s (the readable face's precision)")

    -- The unitless numeric face: an AbbreviatedNumberFormatter with its breakpoints
    -- cleared renders the raw number ("4", never "4 Seconds").
    local number_formatter = api.create_duration_number_formatter()
    check(number_formatter ~= nil, "ftext: the integer numeric formatter is created")
    eq(sb.abbrev_calls, 1, "ftext: the numeric formatter factory is called once")
    check(sb.abbrev_formatter ~= nil and sb.abbrev_formatter.calls.AddBreakpoint == true,
        "ftext: the integer rule is added")
    eq(sb.abbrev_formatter.breakpoint.threshold, 0, "ftext: the rule covers every value")
    eq(sb.abbrev_formatter.breakpoint.step, 1, "ftext: the rule rounds to whole seconds")
    eq(sb.abbrev_formatter.breakpoint.rounding, 2, "ftext: the rule truncates down")
    eq(sb.abbrev_formatter.breakpoint.format, "%.0f", "ftext: the rule formats an integer")
    eq(sb.abbrev_formatter.Format(nil, 2.518), "2", "ftext: 2.518 renders as a bare 2")

    local throwing_abbrev = build({ duration_surface = true, abbrev_throws = true })
    eq(throwing_abbrev.st.api.create_duration_number_formatter(), nil,
        "ftext: a throwing numeric-formatter factory answers nil")

    local curve, property = api.create_duration_text_color_curve(3,
        { r = 1, g = 0.4, b = 0.42, a = 1 }, { r = 0.98, g = 1, b = 0, a = 1 })
    check(curve ~= nil, "ftext: the colour curve is created")
    eq(property, 0, "ftext: the curve property is RemainingDuration")
    eq(#curve.points, 4, "ftext: the warn band is a step (4 points)")
    eq(curve.points[1].x, 0, "ftext: the curve starts at 0 s")
    eq(curve.points[2].x, 3, "ftext: the warn colour holds to 3 s")
    eq(curve.points[3].x, 3.01, "ftext: the normal colour starts just above 3 s")
    eq(curve.points[1].color.r, 1, "ftext: the warn colour components pass through")
    eq(curve.points[1].color.g, 0.4, "ftext: the warn colour green passes through")
    eq(curve.points[3].color.g, 1, "ftext: the normal colour components pass through")

    -- Bad colours decline rather than hand a malformed colour to the client.
    local bad_curve = api.create_duration_text_color_curve(3, { r = "red" }, { r = 1, g = 1, b = 1 })
    eq(bad_curve, nil, "ftext: a malformed warn colour declines")

    -- The formatter's setter block is pcall-guarded: an older setter set still yields a
    -- working formatter object (the binding keeps its defaults).
    local throwing = build({ duration_surface = true,
        formatter = { SetDefaultAbbreviation = function() error("no such setter") end } })
    check(throwing.st.api.create_seconds_formatter() ~= nil,
        "ftext: a throwing setter leaves a usable formatter")

    -- Missing surfaces / non-Forever clients: nil, never a throw.
    local no_binding = build({ duration_surface = true, binding_throws = true })
    eq(no_binding.st.api.create_duration_text_binding(), nil,
        "ftext: a throwing binding factory answers nil")
    local no_util = build({ duration_surface = true, drop_duration_util = true })
    eq(no_util.st.api.create_duration_text_binding(), nil,
        "ftext: a client without C_DurationUtil answers nil")
    local no_string_util = build({ duration_surface = true, drop_string_util = true })
    eq(no_string_util.st.api.create_seconds_formatter(), nil,
        "ftext: a client without C_StringUtil answers nil")
    eq(no_string_util.st.api.create_duration_number_formatter(), nil,
        "ftext: a client without C_StringUtil has no unitless formatter")
    local no_enum = build({ duration_surface = true, drop_enum = true })
    local enumless_curve = no_enum.st.api.create_duration_text_color_curve(3,
        { r = 1, g = 0, b = 0, a = 1 }, { r = 1, g = 1, b = 1, a = 1 })
    eq(enumless_curve, nil, "ftext: a client without the property enum answers nil")
    check(no_enum.st.api.create_seconds_formatter() ~= nil,
        "ftext: the formatter still builds without the enum (setters skipped)")
    check(no_enum.st.api.create_duration_number_formatter() ~= nil,
        "ftext: the unitless formatter does not need the property enum")
    local no_curve = build({ duration_surface = true, curve_throws = true })
    eq(no_curve.st.api.create_duration_text_color_curve(3,
        { r = 1, g = 0, b = 0, a = 1 }, { r = 1, g = 1, b = 1, a = 1 }), nil,
        "ftext: a throwing curve factory answers nil")

    local classic = build({ project = 2, duration_surface = true })
    eq(classic.st.api.create_duration_text_binding(), nil,
        "ftext TBC: no native binding is ever created")
    eq(classic.st.api.create_seconds_formatter(), nil,
        "ftext TBC: no native formatter is ever created")
    eq(classic.st.api.create_duration_number_formatter(), nil,
        "ftext TBC: no unitless numeric formatter is ever created")
    eq(classic.st.api.create_duration_text_color_curve(3,
        { r = 1, g = 0, b = 0, a = 1 }, { r = 1, g = 1, b = 1, a = 1 }), nil,
        "ftext TBC: no native colour curve is ever created")
    eq(classic.binding_calls, 0, "ftext TBC: the binding factory is never called")
end

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then
    os.exit(1)
end
