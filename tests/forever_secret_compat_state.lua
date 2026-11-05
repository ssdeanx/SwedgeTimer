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
        duration_object = nil,
        duration_throws = false,
        aura_table = aura_data(),
        aura = classic_aura_row(),
        aura_reads = 0,
        aura_raises = false,
        classic_aura_calls = 0,
        precheck_result = false,
        precheck_throws = false,
        precheck_calls = 0,
        has_secret_restrictions = false,
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
    env.issecretvalue = function(value)
        return SECRETS[value] == true
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

    if opts.c_spell ~= false then
        env.C_Spell = {
            GetSpellCooldown = function(spell)
                sb.info_calls = sb.info_calls + 1
                local info = sb.info_by_token[spell] or sb.info
                if not info then return nil end
                return {
                    startTime = info.startTime,
                    duration = info.duration,
                    isEnabled = info.isEnabled,
                    modRate = info.modRate,
                }
            end,
            IsSpellUsable = function() return sb.usable, sb.insufficient end,
        }
        if opts.with_duration ~= false then
            env.C_Spell.GetSpellCooldownDuration = function(spell)
                sb.duration_calls = sb.duration_calls + 1
                sb.duration_token = spell
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
        }
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
-- 2. api.UnitAura: the classic global branch stays byte-identical in behaviour
--=========================================================================================
do
    -- C_Secrets says "secret" but the classic branch must not consult it: Era/TBC/Wrath
    -- never run the C_UnitAuras path.
    local sb = build({ classic_aura = true, precheck_result = true })
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
    eq(sb.precheck_calls, 0, "classic aura: the C_Secrets precheck is never consulted")
    eq(sb.aura_reads, 0, "classic aura: C_UnitAuras is never called")
    eq(sb.classic_aura_calls, 1, "classic aura: the classic global is called once")

    -- The classic branch keeps its own whole-entry secret guard.
    sb.aura = classic_aura_row({ expirationTime = SECRET_DURATION })
    eq(api.UnitAura("player", 1, "HELPFUL"), nil,
        "classic aura secret field: the whole entry reads absent")
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

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then
    os.exit(1)
end
