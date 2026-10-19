-- tests/secret_guard_state.lua: offline verification of the secret-value (restricted
-- read) guards.
--
-- The Mainline-code clients (Retail, WoW Forever) can run a "secret value" regime in
-- which restricted reads (cooldowns, power, health, auras, stats, cast info) come back
-- opaque: type() still reports the underlying type, so a type() or "== nil" guard cannot
-- see them, while arithmetic, comparison or table indexing with one raises a Lua error.
-- The client probe that identifies such a value is issecretvalue(); this suite simulates
-- it without a client by flagging ordinary numbers/strings/tables as secret and driving
-- the REAL compat.lua wrappers plus the real consumer paths (LibGlobalCooldown, warrior,
-- druid, shaman, paladin, swing_source, main.lua's weapon check) through client stubs.
--
-- Every secret assertion is paired with a control assertion on an unrestricted reading,
-- so the guards must be exact no-ops when the value is not secret - the classic-client
-- regression baseline. The LibRangeCheck-2.0 guard patch is pinned textually, with an
-- in-suite bite-proof on a guard-stripped copy.
--
-- Run from the repo root: lua5.1 tests/secret_guard_state.lua  (any cwd works).

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
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > (tol or 1e-9) then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- Secret sentinels
--=========================================================================================
-- Real secrets keep the underlying type (a restricted number still reports "number"),
-- which is exactly why the type() guards cannot see them - so the simulated secrets are
-- ordinary values flagged in this side table, mirroring issecretvalue's contract: only
-- flagged values are secret, every other value is an honest reading. The number values
-- live outside any plausible reading domain so a leaked sentinel is recognisable and
-- cannot accidentally equal a real fixture value.
local SECRETS = {}
local function secret(value)
    SECRETS[value] = true
    return value
end

local SECRET_CD_START = secret(900001)
local SECRET_CD_DURATION = secret(900002)
local SECRET_CD_MOD_RATE = secret(900003)
local SECRET_CD_ENABLED = secret(7)            -- a "boolean" reading (truthy non-boolean)
local SECRET_POWER_RAGE = secret(-900001)      -- below any real rage cost
local SECRET_POWER_MANA = secret(900010)
local SECRET_POWER_MAX = secret(900011)
local SECRET_ENERGY = secret(-900002)
local SECRET_HEALTH = secret(900020)
local SECRET_SPEED = secret(900030)
local SECRET_RANGED_DAMAGE = secret(900031)
local SECRET_HASTE = secret(33)                -- plausible but flagged
local SECRET_COST = secret(77777)              -- impossible rage cost
local SECRET_CAST_START = secret(900150)
local SECRET_CAST_END = secret(900152.5)
local SECRET_CTYPE = secret("SECRET_UNDEAD")
local SECRET_AURA_DURATION = secret(900050)
local SECRET_AURA_SOURCE = secret("SECRET_SOURCE")
local SECRET_RANGE = secret("SECRET_RANGE")
local SECRET_RANGE_BOOL = secret(900060)
local SECRET_USABLE = secret(900080)
local SECRET_INSUFFICIENT = secret(900081)
local SECRET_BASE_COOLDOWN = secret(900090)
local SECRET_POWER_TYPE = secret(900100)
local SECRET_POWER_TOKEN = secret("SECRET_ENERGY")
local SECRET_INVENTORY_ID = secret(900110)
local SECRET_INVENTORY_TEXTURE = secret("SECRET_ICON")
local SECRET_INVENTORY_START = secret(900120)
local SECRET_INVENTORY_DURATION = secret(900121)
local SECRET_CHECK_DISTANCE = secret(900130)
local SECRET_RATING = secret({})               -- opaque table: arithmetic errors on it
local SECRET_RATING_BONUS = secret({})

local function probe_is_secret(value)
    return SECRETS[value] == true
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- One throwaway client per call: a fresh global table (env._G = env, so compat's
-- rawget(_G, ...) probes read the stubs and nothing leaks onto the host), the real
-- modules loaded in the repo's TOC order. Client functions read mutable sb fields, so a
-- test can flip a reading between calls without reloading the module (compat captures
-- the function objects once, at load).
local function make_frame(sb)
    local f = {}
    function f:RegisterEvent(name) self.events = self.events or {}; self.events[name] = true end
    function f:RegisterUnitEvent(name) self.events = self.events or {}; self.events[name] = true end
    function f:UnregisterEvent(name) if self.events then self.events[name] = nil end end
    function f:SetScript(script, fn) self.scripts = self.scripts or {}; self.scripts[script] = fn end
    function f:Hide() end
    function f:Show() end
    sb.frames = (sb.frames or 0) + 1
    sb.last_frame = f
    return f
end

local function build(opts)
    opts = opts or {}
    local sb = {
        clock = 100,
        frames = 0,
        fired = {},
        timers = {},
        glow_starts = 0,
        glow_stops = 0,
        bar_color_calls = 0,
        aura_calls = 0,
        target_exists = true,
        known = opts.known or {},
        spell_info = opts.spell_info or {},
        class_db = {},
    }

    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = opts.project or 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", opts.interface or 38002 end
    env.GetTime = function() return sb.clock end
    env.GetTimePreciseSec = function() return sb.clock end
    env.issecretvalue = function(value)
        return probe_is_secret(value)
    end
    env.CR_HASTE_SPELL = 20
    env.C_EventUtils = { IsEventValid = function() return true end }
    env.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
    env.CreateFrame = function() return make_frame(sb) end
    env.C_Timer = {
        After = function(delay, fn)
            sb.timers[#sb.timers + 1] = { delay = delay, fn = fn }
        end,
    }
    env.UnitClass = function() return "Player", opts.class or "WARRIOR" end
    env.UnitExists = function() return sb.target_exists ~= false end
    env.UnitCreatureType = function() return sb.creature_type end

    -- Classic-family stubs (present unless a specific profile omits them).
    if not opts.retail then
        env.GetSpellInfo = function(id)
            local info = sb.spell_info[id]
            if info then
                return info.name, nil, info.icon or 1, info.cast_ms or 0, 0, 0, id
            end
            return nil
        end
        env.GetSpellCooldown = function(spell)
            local cd = sb.cooldowns and sb.cooldowns[spell]
            if cd then return cd[1], cd[2], cd[3], cd[4] end
            return 0, 0, 0, 0
        end
        env.GetSpellBaseCooldown = function() return sb.base_cooldown end
        env.GetSpellPowerCost = function()
            if sb.power_cost == nil then return nil end
            return { { cost = sb.power_cost } }
        end
        env.IsSpellKnown = function(id) return sb.known[id] == true end
        env.IsSpellUsable = function() return sb.usable, sb.insufficient end
        env.IsSpellInRange = function() return sb.spell_in_range end
        env.CheckInteractDistance = function() return sb.check_distance end
        env.UnitPower = function() return sb.power end
        env.UnitPowerMax = function() return sb.power_max end
        env.UnitPowerType = function() return sb.power_type, sb.power_token end
        env.UnitHealth = function() return sb.health end
        env.UnitHealthMax = function() return sb.health_max end
        env.UnitAttackSpeed = function()
            local speeds = sb.attack_speed
            if not speeds then return nil end
            return speeds[1], speeds[2], speeds[3]
        end
        env.UnitRangedDamage = function() return sb.ranged_damage end
        env.UnitSpellHaste = function() return sb.spell_haste end
        env.GetSpellHaste = function() return sb.old_spell_haste end
        env.GetCombatRating = function() return sb.combat_rating end
        env.GetCombatRatingBonus = function() return sb.rating_bonus end
        env.GetInventoryItemID = function(unit, slot)
            sb.inventory_query = { unit, slot }
            return sb.inventory_id
        end
        env.GetInventoryItemTexture = function(unit, slot)
            sb.inventory_texture_query = { unit, slot }
            return sb.inventory_texture
        end
        env.GetInventoryItemCooldown = function(unit, slot)
            sb.inventory_cooldown_query = { unit, slot }
            local cd = sb.inventory_cooldown
            if cd then return cd[1], cd[2], cd[3] end
            return 0, 0, 0
        end
        env.UnitAura = function(unit, index)
            sb.aura_calls = sb.aura_calls + 1
            local row = sb.aura_rows and sb.aura_rows[index]
            if not row then return nil end
            return row.name, row.icon, row.count, row.dispel, row.duration, row.expiration,
                row.source, row.stealable, row.nameplate, row.spell_id
        end
        env.UnitCastingInfo = function()
            local p = sb.cast_payload
            if not p then return nil end
            return p.name, nil, nil, p.start_ms, p.end_ms, false, 1, false, p.spell_id
        end
        env.UnitChannelInfo = function()
            local p = sb.channel_payload
            if not p then return nil end
            return p.name, nil, nil, p.start_ms, p.end_ms, false, false, p.spell_id
        end
    else
        -- Mainline-code profile: the C_* namespaces replace the classic globals.
        env.C_Spell = {
            GetSpellCooldown = function()
                local spec = sb.c_spell_cooldown
                if not spec then return nil end
                return { startTime = spec[1], duration = spec[2], isEnabled = spec[3], modRate = spec[4] }
            end,
            IsSpellInRange = function() return sb.c_spell_range end,
        }
        env.C_UnitAuras = {
            GetAuraDataByIndex = function()
                return sb.aura_table
            end,
        }
    end

    local ST = {
        PALADIN = {}, WARRIOR = {}, DRUID = {}, SHAMAN = {},
        player_class = opts.class or "WARRIOR",
        interfaces_are_initialised = true,
        in_combat = true,
    }
    function ST:get_class_table() return sb.class_db end
    function ST:set_bar_color(hand)
        sb.bar_color_calls = sb.bar_color_calls + 1
        sb.last_hand = hand
    end
    function ST:convert_color(color) return color end
    function ST:get_bar_frame() return {} end
    function ST:get_hand_table() return sb.hand_db end
    function ST:get_spell_gcd_duration() return 1.5 end
    -- Mirror of main.lua:get_gcd_time_before_swing_seconds (the guide's reseal basis).
    function ST:get_gcd_time_before_swing_seconds(hand)
        if hand ~= nil then
            local key = "gcd1_spell_time_before_swing_" .. tostring(hand)
            if self.gcd[key] ~= nil then
                return self.gcd[key]
            end
        end
        return self.gcd.gcd1_spell_time_before_swing or self:get_spell_gcd_duration()
    end

    local function callbacks_for()
        local cb = {}
        function cb:Fire(event, ...)
            sb.fired[#sb.fired + 1] = { event = event, a = { ... } }
            local fn = sb.registered and sb.registered[event]
            if fn then fn(event, ...) end
        end
        function cb:RegisterCallback(event, fn)
            sb.registered = sb.registered or {}
            sb.registered[event] = fn
        end
        return cb
    end
    local LCG = {
        PixelGlow_Start = function() sb.glow_starts = sb.glow_starts + 1 end,
        PixelGlow_Stop = function() sb.glow_stops = sb.glow_stops + 1 end,
        AutoCastGlow_Start = function() end,
        AutoCastGlow_Stop = function() end,
        ButtonGlow_Start = function() end,
        ButtonGlow_Stop = function() end,
    }
    local LSM = { Fetch = function() return nil end }
    local libstub = setmetatable({
        NewLibrary = function(_, major)
            sb.libraries = sb.libraries or {}
            if not sb.libraries[major] then sb.libraries[major] = {} end
            return sb.libraries[major]
        end,
    }, {
        __call = function(_, major)
            if major == "AceAddon-3.0" then return { GetAddon = function() return ST end } end
            if major == "CallbackHandler-1.0" then return { New = function() return callbacks_for() end } end
            if major == "LibCustomGlow-1.0" then return LCG end
            if major == "LibSharedMedia-3.0" then return LSM end
            return nil
        end,
    })
    env.LibStub = libstub
    if opts.c_spellbook then
        env.C_SpellBook = {
            IsSpellKnown = function(id)
                sb.spellbook_calls = (sb.spellbook_calls or 0) + 1
                return sb.spellbook_known and sb.spellbook_known[id] == true
            end,
        }
    end

    local st = {}
    local modules = opts.modules or { "compat.lua" }
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        if not ok then
            failures = failures + 1
            print("FAIL  loading " .. modules[i] .. ": " .. tostring(err))
        end
    end

    sb.env, sb.st, sb.ST = env, st, ST
    return sb
end

local function has_fired(sb, event)
    for i = 1, #sb.fired do
        if sb.fired[i].event == event then return true end
    end
    return false
end

--=========================================================================================
-- 1. R1: compat's GetSpellCooldown (classic global and C_Spell shapes)
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    sb.cooldowns = { [29515] = { 5, 1.5, 1, 1 } }
    local a, b, c, d = api.GetSpellCooldown(29515)
    eq(a, 5, "R1 control: classic cooldown start passes through")
    eq(b, 1.5, "R1 control: classic cooldown duration passes through")
    eq(c, 1, "R1 control: classic cooldown enabled passes through")
    eq(d, 1, "R1 control: classic cooldown modRate passes through")

    sb.cooldowns = { [29515] = { SECRET_CD_START, SECRET_CD_DURATION, 1, 1 } }
    a, b, c, d = api.GetSpellCooldown(29515)
    eq(a, 0, "R1 secret start: reports the no-cooldown shape start")
    eq(b, 0, "R1 secret start: reports the no-cooldown shape duration")
    eq(c, 0, "R1 secret start: reports the no-cooldown shape enabled")
    eq(d, 0, "R1 secret start: reports the no-cooldown shape modRate")

    sb.cooldowns = { [29515] = { 5, SECRET_CD_DURATION, 1, 1 } }
    a, b = api.GetSpellCooldown(29515)
    eq(a, 0, "R1 secret duration only: start degrades")
    eq(b, 0, "R1 secret duration only: duration degrades")

    sb.cooldowns = { [29515] = { 5, 1.5, SECRET_CD_ENABLED, 1 } }
    a, b = api.GetSpellCooldown(29515)
    eq(a, 0, "R1 secret enabled only: start degrades")
    eq(b, 0, "R1 secret enabled only: duration degrades")

    sb.cooldowns = { [29515] = { 5, 1.5, 1, SECRET_CD_MOD_RATE } }
    a = api.GetSpellCooldown(29515)
    eq(a, 0, "R1 secret modRate only: start degrades")

    sb.cooldowns = nil
    a, b, c, d = api.GetSpellCooldown(29515)
    check(a == 0 and b == 0 and c == 0 and d == 0,
        "R1 unknown spell still reports the all-zero shape")
end

do
    -- Mainline shape: C_Spell.GetSpellCooldown returns a SpellCooldownInfo table.
    local sb = build({ retail = true, project = 1, interface = 120100 })
    local api = sb.st.api

    sb.c_spell_cooldown = { 5, 1.5, true, 1 }
    local a, b, c, d = api.GetSpellCooldown(61304)
    eq(a, 5, "R1 retail control: startTime passes through")
    eq(b, 1.5, "R1 retail control: duration passes through")
    eq(c, 1, "R1 retail control: true isEnabled becomes 1")
    eq(d, 1, "R1 retail control: modRate passes through")

    sb.c_spell_cooldown = { 5, 1.5, false, 1 }
    a, b, c = api.GetSpellCooldown(61304)
    eq(a, 5, "R1 retail disabled: startTime still readable")
    eq(b, 1.5, "R1 retail disabled: duration still readable")
    eq(c, 0, "R1 retail disabled: false isEnabled becomes 0")

    sb.c_spell_cooldown = { SECRET_CD_START, SECRET_CD_DURATION, true, 1 }
    a, b, c, d = api.GetSpellCooldown(61304)
    eq(a, 0, "R1 retail secret start/duration: no-cooldown start")
    eq(b, 0, "R1 retail secret start/duration: no-cooldown duration")
    eq(c, 0, "R1 retail secret start/duration: no-cooldown enabled")
    eq(d, 0, "R1 retail secret start/duration: no-cooldown modRate")

    sb.c_spell_cooldown = { 5, 1.5, SECRET_CD_ENABLED, 1 }
    a, b, c = api.GetSpellCooldown(61304)
    eq(a, 0, "R1 retail secret isEnabled: start degrades")
    eq(b, 0, "R1 retail secret isEnabled: duration degrades")
    eq(c, 0, "R1 retail secret isEnabled: enabled degrades")

    sb.c_spell_cooldown = nil
    a, b, c, d = api.GetSpellCooldown(61304)
    check(a == 0 and b == 0 and c == 0 and d == 0,
        "R1 retail unknown spell reports the all-zero shape")
end

--=========================================================================================
-- 2. R1: LibGlobalCooldown (poll, interrupted, ratings)
--=========================================================================================
do
    -- LibGlobalCooldown registers itself through LibStub:NewLibrary; the sandbox's
    -- registry hands back the same instance the module populated.
    local sb = build({ modules = { "compat.lua", "LibGlobalCooldown.lua" } })
    local lib = sb.env.LibStub.NewLibrary(nil, "LibGlobalCooldown", 1)
    check(type(lib) == "table", "LGC control: the library is registered through LibStub")
    sb.cooldowns = { [29515] = { 5, 1.5, 1, 1 } }

    -- A restricted read degrades to "no cooldown": no lock, no arithmetic, no event.
    sb.cooldowns = { [29515] = { SECRET_CD_START, SECRET_CD_DURATION, 1, 1 } }
    local ok = pcall(lib.poll_gcd, lib)
    check(ok, "LGC poll_gcd with a secret reading does not throw")
    eq(lib.gcd_duration, nil, "LGC poll_gcd with a secret reading never locks the GCD")
    check(not has_fired(sb, "GCD_STARTED"), "LGC poll_gcd with a secret reading fires no GCD_STARTED")

    -- Control: an unrestricted reading locks as before.
    sb.cooldowns = { [29515] = { 5, 1.5, 1, 1 } }
    sb.clock = 5
    ok = pcall(lib.poll_gcd, lib)
    check(ok, "LGC poll_gcd control does not throw")
    eq(lib.gcd_duration, 1.5, "LGC poll_gcd control locks the reported duration")
    check(has_fired(sb, "GCD_STARTED"), "LGC poll_gcd control fires GCD_STARTED")
    check(#sb.timers == 1, "LGC poll_gcd control schedules the release timer")

    -- Interrupted while locked: the stored shape (0) releases through the existing == 0
    -- early-out; a secret read can never reach the arithmetic.
    lib.gcd_duration = 1.5
    lib.gcd_started = 5
    lib.gcd_expires = 6.5
    sb.cooldowns = { [29515] = { SECRET_CD_START, SECRET_CD_DURATION, 1, 1 } }
    sb.fired = {}
    ok = pcall(lib.UNIT_SPELLCAST_INTERRUPTED, lib)
    check(ok, "LGC UNIT_SPELLCAST_INTERRUPTED with a secret reading does not throw")
    eq(lib.gcd_duration, nil, "LGC interrupted: the no-cooldown shape releases the lock")
    check(has_fired(sb, "GCD_OVER"), "LGC interrupted: the release fires GCD_OVER")

    -- Control: a live unrestricted cooldown keeps the lock.
    lib.gcd_duration = 1.5
    sb.cooldowns = { [29515] = { 5, 1.5, 1, 1 } }
    sb.fired = {}
    ok = pcall(lib.UNIT_SPELLCAST_INTERRUPTED, lib)
    check(ok, "LGC interrupted control does not throw")
    eq(lib.gcd_duration, 1.5, "LGC interrupted control keeps the lock")
    check(not has_fired(sb, "GCD_OVER"), "LGC interrupted control fires no GCD_OVER")

    -- Restricted haste rating: the update is skipped, never compared or stored.
    lib.current_spell_haste = nil
    sb.combat_rating = SECRET_RATING
    sb.fired = {}
    ok = pcall(lib.COMBAT_RATING_UPDATE, lib)
    check(ok, "LGC COMBAT_RATING_UPDATE with an opaque rating does not throw")
    eq(lib.current_spell_haste, nil, "LGC: a restricted rating never reaches the state")
    check(not has_fired(sb, "GCD_SPELL_UPDATED"), "LGC: a restricted rating fires no update")

    -- Control: an unrestricted rating updates and recalculates.
    sb.combat_rating = 100
    sb.rating_bonus = 0
    ok = pcall(lib.COMBAT_RATING_UPDATE, lib)
    check(ok, "LGC COMBAT_RATING_UPDATE control does not throw")
    eq(lib.current_spell_haste, 100, "LGC control: the rating is stored")
    check(has_fired(sb, "GCD_SPELL_UPDATED"), "LGC control: the recalculation fires")

    -- Restricted rating bonus inside the calculation: skipped, no arithmetic.
    lib.current_spell_gcd = nil
    sb.rating_bonus = SECRET_RATING_BONUS
    sb.fired = {}
    ok = pcall(lib.calculate_expected_spell_gcd, lib)
    check(ok, "LGC calculate with an opaque rating bonus does not throw")
    eq(lib.current_spell_gcd, nil, "LGC calculate: a restricted bonus leaves the estimate alone")
    check(not has_fired(sb, "GCD_SPELL_UPDATED"), "LGC calculate: a restricted bonus fires nothing")

    -- Control.
    lib.current_spell_gcd = nil
    sb.rating_bonus = 0
    ok = pcall(lib.calculate_expected_spell_gcd, lib)
    check(ok, "LGC calculate control does not throw")
    eq(lib.current_spell_gcd, 1.5, "LGC calculate control updates the estimate")
end

--=========================================================================================
-- 3. R2: UnitPower / UnitPowerMax / UnitPowerType wrappers
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    sb.power = 40
    sb.power_max = 100
    eq(api.UnitPower("player"), 40, "R2 control: UnitPower passes through")
    eq(api.UnitPowerMax("player"), 100, "R2 control: UnitPowerMax passes through")
    sb.power = SECRET_POWER_RAGE
    sb.power_max = SECRET_POWER_MAX
    eq(api.UnitPower("player"), nil, "R2 secret: UnitPower reports unknown (nil)")
    eq(api.UnitPowerMax("player"), nil, "R2 secret: UnitPowerMax reports unknown (nil)")

    sb.power_type = 3
    sb.power_token = "ENERGY"
    local pt, token = api.UnitPowerType("player")
    eq(pt, 3, "R2 control: UnitPowerType id passes through")
    eq(token, "ENERGY", "R2 control: UnitPowerType token passes through")
    sb.power_token = SECRET_POWER_TOKEN
    pt, token = api.UnitPowerType("player")
    eq(pt, nil, "R2 secret token: UnitPowerType id degrades with the token")
    eq(token, nil, "R2 secret token: the token reports unknown (nil)")
    sb.power_type = SECRET_POWER_TYPE
    pt, token = api.UnitPowerType("player")
    eq(pt, nil, "R2 secret: UnitPowerType reports unknown (nil)")
    eq(token, nil, "R2 secret: UnitPowerType token degrades with the id")
end

--=========================================================================================
-- 4. R2: warrior rage state and guide gather
--=========================================================================================
do
    local sb = build({
        modules = { "compat.lua", "utils.lua", "classes/warrior.lua" },
        spell_info = {
            [78] = { name = "Heroic Strike" },
            [845] = { name = "Cleave" },
            [1464] = { name = "Slam", cast_ms = 1500 },
        },
        known = { [78] = true, [845] = true },
    })
    local ST = sb.ST
    ST.hs_queued = true
    ST.insufficient_rage = false

    -- Control: readable rage below the cost flags insufficient.
    sb.power = 10
    sb.power_cost = 25
    local ok = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok, "warrior rage control does not throw")
    eq(ST.insufficient_rage, true, "warrior rage control: 10 < 25 is insufficient")

    -- Secret power: unknown, never a comparison.
    ST.insufficient_rage = true     -- leave it "stale" to prove the recalculation ran
    sb.power = SECRET_POWER_RAGE
    sb.bar_color_calls = 0
    ok = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok, "warrior rage with a secret power does not throw")
    eq(ST.insufficient_rage, false, "warrior rage: a secret power degrades to sufficient")
    eq(sb.bar_color_calls, 1, "warrior rage: a secret power recolours once for the state change")

    -- The state has settled: a repeated secret read has nothing new to recolour.
    sb.bar_color_calls = 0
    ok = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok, "warrior rage with a repeated secret reading does not throw")
    eq(ST.insufficient_rage, false, "warrior rage: a repeated secret power stays sufficient")
    eq(sb.bar_color_calls, 0, "warrior rage: no colour churn from a repeated secret reading")

    -- Secret cost: unknown, never a comparison.
    ST.insufficient_rage = false
    sb.power = 10
    sb.power_cost = SECRET_COST
    sb.bar_color_calls = 0
    ok = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok, "warrior rage with a secret cost does not throw")
    eq(ST.insufficient_rage, false, "warrior rage: a secret cost degrades to sufficient")
    eq(sb.bar_color_calls, 0, "warrior rage: a secret cost causes no colour change")

    -- Guide gather: every restricted input lands as unknown, cooldowns as 0.
    sb.power = SECRET_POWER_RAGE
    sb.health_max = 1000
    sb.health = SECRET_HEALTH
    sb.power_cost = SECRET_COST
    sb.cooldowns = {
        [78] = { SECRET_CD_START, SECRET_CD_DURATION, 1, 1 },
        [845] = { SECRET_CD_START, SECRET_CD_DURATION, 1, 1 },
    }
    ST.mainhand = { speed = 2.6, ends_at = 110 }
    ST.gcd = { expires = 101 }
    ST.warrior_overpower_proc_until = nil
    ST.warrior_slam_casting = false
    ST.has_bloodsurge = false
    local out = {}
    ok = pcall(ST.WARRIOR.gather_guide_inputs, ST, out)
    check(ok, "warrior gather with secret readings does not throw")
    eq(out.rage, nil, "warrior gather: a secret rage is unknown")
    eq(out.target_health_pct, nil, "warrior gather: secret health is unknown")
    eq(out.hs_cost, nil, "warrior gather: a secret HS cost is unknown")
    eq(out.cleave_cost, nil, "warrior gather: a secret Cleave cost is unknown")
    eq(out.hs_remaining, 0, "warrior gather: a secret HS cooldown reads idle")
    eq(out.hs_duration, nil, "warrior gather: a secret HS cooldown has no length")

    -- Control: honest readings flow through untouched.
    sb.power = 40
    sb.health = 500
    sb.power_cost = 15
    sb.cooldowns = {
        [78] = { 95, 10, 1, 1 },
        [845] = { 95, 10, 1, 1 },
    }
    out = {}
    ok = pcall(ST.WARRIOR.gather_guide_inputs, ST, out)
    check(ok, "warrior gather control does not throw")
    eq(out.rage, 40, "warrior gather control: rage passes through")
    eq(out.target_health_pct, 50, "warrior gather control: health percentage computes")
    eq(out.hs_cost, 15, "warrior gather control: HS cost passes through")
    eq(out.cleave_cost, 15, "warrior gather control: Cleave cost passes through")
    eq(out.hs_remaining, 5, "warrior gather control: HS cooldown remaining computes")
    eq(out.hs_duration, 10, "warrior gather control: HS cooldown duration passes through")
end

--=========================================================================================
-- 5. R2: druid rage state and guide gather
--=========================================================================================
do
    local sb = build({
        modules = { "compat.lua", "utils.lua", "druid_energy.lua", "classes/druid.lua" },
        spell_info = { [6807] = { name = "Maul" } },
        known = { [6807] = true },
    })
    local ST = sb.ST
    ST.maul_queued = true
    ST.insufficient_rage = false

    sb.power = 10
    sb.power_cost = 25
    local ok = pcall(ST.DRUID.on_rage_update, ST)
    check(ok, "druid rage control does not throw")
    eq(ST.insufficient_rage, true, "druid rage control: 10 < 25 is insufficient")

    ST.insufficient_rage = true
    sb.power = SECRET_POWER_RAGE
    ok = pcall(ST.DRUID.on_rage_update, ST)
    check(ok, "druid rage with a secret power does not throw")
    eq(ST.insufficient_rage, false, "druid rage: a secret power degrades to sufficient")

    ST.insufficient_rage = false
    sb.power = 10
    sb.power_cost = SECRET_COST
    ok = pcall(ST.DRUID.on_rage_update, ST)
    check(ok, "druid rage with a secret cost does not throw")
    eq(ST.insufficient_rage, false, "druid rage: a secret cost degrades to sufficient")

    -- Guide gather: bear form reads rage, cat form energy + combo points.
    ST.mainhand = { speed = 2.6, ends_at = 110 }
    ST.gcd = { expires = 101 }
    ST.maul_queued = false
    ST.insufficient_rage = false
    sb.power = SECRET_POWER_RAGE
    sb.power_cost = SECRET_COST
    ST.form_index = 1
    local out = {}
    ok = pcall(ST.DRUID.gather_guide_inputs, ST, out)
    check(ok, "druid gather (bear, secret) does not throw")
    eq(out.rage, nil, "druid gather: a secret rage is unknown")
    eq(out.maul_cost, nil, "druid gather: a secret Maul cost is unknown")

    sb.power = SECRET_ENERGY
    ST.form_index = 3
    out = {}
    ok = pcall(ST.DRUID.gather_guide_inputs, ST, out)
    check(ok, "druid gather (cat, secret) does not throw")
    eq(out.energy, nil, "druid gather: a secret energy is unknown")
    eq(out.combo_points, nil, "druid gather: secret combo points are unknown")

    -- Control: honest readings flow through untouched.
    sb.power = 40
    sb.power_cost = 15
    ST.form_index = 3
    out = {}
    ok = pcall(ST.DRUID.gather_guide_inputs, ST, out)
    check(ok, "druid gather (cat, control) does not throw")
    eq(out.energy, 40, "druid gather control: energy passes through")
    eq(out.combo_points, 40, "druid gather control: combo points pass through")
    eq(out.maul_cost, 15, "druid gather control: Maul cost passes through")

    ST.form_index = 1
    out = {}
    ok = pcall(ST.DRUID.gather_guide_inputs, ST, out)
    check(ok, "druid gather (bear, control) does not throw")
    eq(out.rage, 40, "druid gather control: rage passes through")
end

--=========================================================================================
-- 6. R3: UnitAura wrapper (classic global and C_UnitAuras) + warrior consumer
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    sb.aura_rows = { [1] = {
        name = "Blood Surge", icon = nil, count = nil, dispel = nil,
        duration = 10, expiration = 110, source = "player", stealable = false,
        nameplate = false, spell_id = 46916,
    } }
    local name, _, _, _, duration, expiration, source, _, _, spell_id =
        api.UnitAura("player", 1, "HELPFUL")
    eq(name, "Blood Surge", "R3 control: aura name passes through")
    eq(duration, 10, "R3 control: aura duration passes through")
    eq(expiration, 110, "R3 control: aura expiration passes through")
    eq(source, "player", "R3 control: aura source passes through")
    eq(spell_id, 46916, "R3 control: aura spell id passes through")

    -- One secret field makes the whole entry absent: every consumer loop breaks on nil.
    sb.aura_rows = { [1] = {
        name = "Blood Surge", duration = SECRET_AURA_DURATION, spell_id = 46916,
    } }
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, nil, "R3 secret duration: the whole entry reports absent")

    sb.aura_rows = { [1] = { name = "Blood Surge", source = SECRET_AURA_SOURCE, spell_id = 46916 } }
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, nil, "R3 secret source: the whole entry reports absent")

    sb.aura_rows = { [1] = { name = SECRET_CTYPE, spell_id = 46916 } }
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, nil, "R3 secret name: the whole entry reports absent")

    sb.aura_rows = nil
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, nil, "R3 empty slot still reports absent")
end

do
    -- Mainline shape: C_UnitAuras.GetAuraDataByIndex returns an AuraData table.
    local sb = build({ retail = true, project = 1, interface = 120100 })
    local api = sb.st.api

    sb.aura_table = {
        name = "Blood Surge", icon = 1, applications = nil, dispelName = nil,
        duration = 10, expirationTime = 110, sourceUnit = "player", isStealable = false,
        nameplateShowPersonal = false, spellId = 46916,
    }
    local name, _, _, _, duration, expiration, source, _, _, spell_id =
        api.UnitAura("player", 1, "HELPFUL")
    eq(name, "Blood Surge", "R3 retail control: aura name passes through")
    eq(duration, 10, "R3 retail control: aura duration passes through")
    eq(expiration, 110, "R3 retail control: aura expiration passes through")
    eq(source, "player", "R3 retail control: aura source passes through")
    eq(spell_id, 46916, "R3 retail control: aura spell id passes through")

    sb.aura_table.duration = SECRET_AURA_DURATION
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, nil, "R3 retail secret duration: the whole entry reports absent")

    sb.aura_table = nil
    name = api.UnitAura("player", 1, "HELPFUL")
    eq(name, nil, "R3 retail empty slot reports absent")
end

do
    local sb = build({
        modules = { "compat.lua", "utils.lua", "classes/warrior.lua" },
        spell_info = { [46916] = { name = "Blood Surge" } },
    })
    local ST = sb.ST
    ST.bloodsurge_glow_active = false
    sb.class_db = { use_bloodsurge_glow = true, bloodsurge_glow_color = { 255, 255, 255, 255 } }
    sb.hand_db = {}     -- the per-hand option table glow_start reads its border width from

    -- Control: a clean Blood Surge aura is seen and starts the glow.
    sb.aura_rows = { [1] = { name = "Blood Surge", duration = 10, spell_id = 46916 } }
    sb.aura_calls = 0
    local ok, err = pcall(ST.WARRIOR.on_aura_change, ST)
    check(ok, "warrior aura control does not throw (" .. tostring(err) .. ")")
    eq(ST.has_bloodsurge, true, "warrior aura control: the buff is detected")
    eq(sb.aura_calls, 2, "warrior aura control: the scan walks past the entry to the empty slot")
    eq(sb.glow_starts, 1, "warrior aura control: the glow starts")

    -- Secret field: the entry is invisible, the scan stops at it, no glow.
    ST.bloodsurge_glow_active = false
    sb.aura_rows = { [1] = { name = "Blood Surge", duration = SECRET_AURA_DURATION, spell_id = 46916 } }
    sb.aura_calls = 0
    ok = pcall(ST.WARRIOR.on_aura_change, ST)
    check(ok, "warrior aura with a secret field does not throw")
    eq(ST.has_bloodsurge, false, "warrior aura: a secret aura is treated as absent")
    eq(sb.aura_calls, 1, "warrior aura: the scan stops at the secret row")
    eq(sb.glow_starts, 1, "warrior aura: no glow from a secret aura")
end

--=========================================================================================
-- 7. R4: UnitHealth / UnitHealthMax wrappers
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    sb.health = 500
    sb.health_max = 1000
    eq(api.UnitHealth("target"), 500, "R4 control: UnitHealth passes through")
    eq(api.UnitHealthMax("target"), 1000, "R4 control: UnitHealthMax passes through")
    sb.health = SECRET_HEALTH
    sb.health_max = 1000
    eq(api.UnitHealth("target"), nil, "R4 secret: UnitHealth reports unknown (nil)")
    eq(api.UnitHealthMax("target"), 1000, "R4: the readable Max is unaffected")
    sb.health_max = SECRET_POWER_MAX
    eq(api.UnitHealthMax("target"), nil, "R4 secret: UnitHealthMax reports unknown (nil)")
end

--=========================================================================================
-- 8. R5: UnitAttackSpeed / UnitRangedDamage + the main.lua check_weapons shape
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    sb.attack_speed = { 2.6, 1.8 }
    local mh, oh = api.UnitAttackSpeed("player")
    eq(mh, 2.6, "R5 control: mainhand speed passes through")
    eq(oh, 1.8, "R5 control: offhand speed passes through")

    -- The exact main.lua check_weapons offhand decision (main.lua:654-661).
    sb.attack_speed = { 2.6, 1.8 }
    local _, speed_offhand = api.UnitAttackSpeed("player")
    speed_offhand = speed_offhand or 0
    eq(speed_offhand == 0, false, "R5 control: a readable offhand counts as a weapon")

    sb.attack_speed = { 2.6, SECRET_SPEED }
    _, speed_offhand = api.UnitAttackSpeed("player")
    speed_offhand = speed_offhand or 0
    eq(speed_offhand, 0, "R5 secret offhand: the whole read degrades to no weapon")
    mh, oh = api.UnitAttackSpeed("player")
    eq(mh, nil, "R5 secret offhand: the mainhand degrades with the read")
    eq(oh, nil, "R5 secret offhand: the offhand degrades with the read")

    sb.attack_speed = nil
    mh, oh = api.UnitAttackSpeed("player")
    eq(mh, nil, "R5: an absent weapon reports nil, not 0")
    eq(oh, nil, "R5: an absent offhand reports nil too")

    sb.ranged_damage = 2.5
    eq(api.UnitRangedDamage("player"), 2.5, "R5 control: UnitRangedDamage passes through")
    sb.ranged_damage = SECRET_RANGED_DAMAGE
    eq(api.UnitRangedDamage("player"), nil, "R5 secret: UnitRangedDamage reports unknown (nil)")
end

do
    -- Forever swing engine: the raw UnitAttackSpeed site must keep its schedule.
    local sb = build({
        modules = { "compat.lua", "swing_source.lua" },
        project = 18,
        interface = 16001,
    })
    local st = sb.st
    local src = st.swing_source
    check(src ~= nil and src.available == true, "swing_source: available on FOREVER")
    local frame = sb.last_frame
    check(frame ~= nil and frame.scripts ~= nil and frame.scripts.OnEvent ~= nil,
        "swing_source: the engine OnEvent script was captured")

    local function fire(event, ...)
        frame.scripts.OnEvent(frame, event, ...)
    end

    fire("PLAYER_SWING", 2.6, 0)
    local speed, expiration = src:SwingTimerInfo("mainhand")
    eq(speed, 2.6, "swing_source control: the cycle starts at the payload speed")

    -- A restricted speed reading: no update, the cycle keeps its schedule.
    sb.attack_speed = { SECRET_SPEED }
    sb.fired = {}
    local ok = pcall(fire, "UNIT_ATTACK_SPEED")
    check(ok, "swing_source UNIT_ATTACK_SPEED with a secret reading does not throw")
    eq(has_fired(sb, "SWING_TIMER_UPDATE"), false, "swing_source: a secret speed fires no update")
    local speed2, expiration2 = src:SwingTimerInfo("mainhand")
    eq(speed2, 2.6, "swing_source: the cycle keeps its scheduled speed")
    eq(expiration2, expiration, "swing_source: the cycle keeps its scheduled expiration")

    -- Control: an honest speed rescales the remaining time.
    sb.attack_speed = { 1.3 }
    sb.fired = {}
    ok = pcall(fire, "UNIT_ATTACK_SPEED")
    check(ok, "swing_source UNIT_ATTACK_SPEED control does not throw")
    eq(has_fired(sb, "SWING_TIMER_UPDATE"), true, "swing_source control: a readable speed rescales")
    local speed3 = src:SwingTimerInfo("mainhand")
    near(speed3, 1.3, 1e-9, "swing_source control: the cycle reports the new speed")
end

--=========================================================================================
-- 9. R6: UnitSpellHaste / GetSpellHaste wrappers + the shaman haste consumer
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    sb.spell_haste = 30
    sb.old_spell_haste = 25
    eq(api.UnitSpellHaste("player"), 30, "R6 control: UnitSpellHaste passes through")
    eq(api.GetSpellHaste(), 25, "R6 control: GetSpellHaste passes through")
    sb.spell_haste = SECRET_HASTE
    sb.old_spell_haste = SECRET_HASTE
    eq(api.UnitSpellHaste("player"), nil, "R6 secret: UnitSpellHaste reports unknown (nil)")
    eq(api.GetSpellHaste(), nil, "R6 secret: GetSpellHaste reports unknown (nil)")
end

do
    local sb = build({
        modules = { "compat.lua", "utils.lua", "weave.lua", "classes/shaman.lua" },
        spell_info = {
            [403] = { name = "Lightning Bolt", cast_ms = 2500 },
            [331] = { name = "Healing Wave", cast_ms = 3000 },
        },
        known = { [403] = true },
    })
    local ST = sb.ST
    ST.mainhand = { speed = 2.6, ends_at = 110, start = 108, is_full = false }
    ST.gcd = { expires = 101 }
    ST.weave_mw_stacks = 0
    ST.weave_catalog = {}
    ST.weave_catalog_retry_at = {}

    sb.spell_haste = 30
    local ok = pcall(ST.SHAMAN.refresh_weave_haste, ST, 1)
    check(ok, "shaman haste control does not throw")
    near(ST.weave_haste_mult, 1.3, 1e-9, "shaman haste control: 30% reads as 1.3x")

    sb.spell_haste = SECRET_HASTE
    ok = pcall(ST.SHAMAN.refresh_weave_haste, ST, 1)
    check(ok, "shaman haste with a secret reading does not throw")
    near(ST.weave_haste_mult, 1, 1e-9, "shaman haste: a secret reading degrades to no haste")

    -- Cast window: the compat cast wrapper feeds the real consumer (shaman.lua:366-376).
    ok = pcall(ST.SHAMAN.resolve_weave_catalog, ST)
    check(ok, "shaman catalog resolves for the cast-window checks")
    check(ST.weave_catalog.LB ~= nil, "shaman catalog: Lightning Bolt resolved")

    sb.cast_payload = { name = "Lightning Bolt", start_ms = SECRET_CAST_START, end_ms = SECRET_CAST_END, spell_id = 403 }
    ok = pcall(ST.SHAMAN.on_spellcast_event, ST, "UNIT_SPELLCAST_START", "player", nil, 403)
    check(ok, "shaman cast start with a secret window does not throw")
    eq(ST.weave_is_casting, true, "shaman cast start: the cast starts from the payload")
    eq(ST.weave_cast_start_time, sb.clock, "shaman cast start: a secret window falls back to now")
    eq(ST.weave_cast_end_time, nil, "shaman cast start: a secret window has no end")

    -- Control: the live window is honoured (start/end come from the payload).
    ok = pcall(ST.SHAMAN.on_spellcast_event, ST, "UNIT_SPELLCAST_STOP", "player")
    check(ok, "shaman cast stop does not throw")
    sb.cast_payload = { name = "Lightning Bolt", start_ms = 150, end_ms = 152.5, spell_id = 403 }
    ok = pcall(ST.SHAMAN.on_spellcast_event, ST, "UNIT_SPELLCAST_START", "player", nil, 403)
    check(ok, "shaman cast start control does not throw")
    near(ST.weave_cast_start_time, 0.15, 1e-9, "shaman cast control: the live start is honoured")
    near(ST.weave_cast_end_time, 0.1525, 1e-9, "shaman cast control: the live end is honoured")

    -- Guide gather: a secret Stormstrike cooldown reads idle.
    sb.cooldowns = { [17364] = { SECRET_CD_START, SECRET_CD_DURATION, 1, 1 } }
    sb.cast_payload = nil
    local out = {}
    ok = pcall(ST.SHAMAN.gather_guide_inputs, ST, out)
    check(ok, "shaman gather with a secret cooldown does not throw")
    eq(out.stormstrike_remaining, 0, "shaman gather: a secret cooldown reads idle")
    eq(out.stormstrike_duration, nil, "shaman gather: a secret cooldown has no length")

    sb.cooldowns = { [17364] = { 90, 30, 1, 1 } }
    out = {}
    ok = pcall(ST.SHAMAN.gather_guide_inputs, ST, out)
    check(ok, "shaman gather control does not throw")
    near(out.stormstrike_remaining, 20, 1e-9, "shaman gather control: cooldown remaining computes")
    eq(out.stormstrike_duration, 30, "shaman gather control: cooldown duration passes through")
end

--=========================================================================================
-- 10. R7: the C_SpellBook.IsSpellKnown probe and the chain order
--=========================================================================================
do
    -- Chain order: with the classic global present it must keep answering, exactly as
    -- before the probe was added (the new probe is a fallback, not a replacement).
    local sb = build({ c_spellbook = true, known = { [78] = true } })
    sb.spellbook_known = { [78] = false }
    sb.spellbook_calls = 0
    eq(sb.st.api.is_spell_known(78), true, "R7 order: the classic global keeps answering")
    eq(sb.spellbook_calls, 0, "R7 order: C_SpellBook is not consulted when the chain answers")

    -- On a Mainline client the classic global is gone: C_SpellBook answers.
    local sb2 = build({ retail = true, project = 1, interface = 120100, c_spellbook = true })
    sb2.spellbook_known = { [78] = true, [999] = false }
    sb2.spellbook_calls = 0
    eq(sb2.st.api.is_spell_known(78), true, "R7 probe: C_SpellBook answers known spells")
    eq(sb2.st.api.is_spell_known(999), false, "R7 probe: C_SpellBook answers unknown spells")
    check(sb2.spellbook_calls >= 2, "R7 probe: the calls went to C_SpellBook")

    -- No probe at all: unknown, never an error.
    local sb3 = build({ retail = true, project = 1, interface = 120100 })
    eq(sb3.st.api.is_spell_known(78), false, "R7 no probe: reports unknown (false)")
end

--=========================================================================================
-- 11. R8: IsSpellInRange (classic global, C_Spell, and the paladin HUD)
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    sb.spell_in_range = 1
    eq(api.IsSpellInRange("Exorcism", "target"), 1, "R8 control: classic 1 passes through")
    sb.spell_in_range = 0
    eq(api.IsSpellInRange("Exorcism", "target"), 0, "R8 control: classic 0 passes through")
    sb.spell_in_range = nil
    eq(api.IsSpellInRange("Exorcism", "target"), nil, "R8 control: classic nil passes through")
    sb.spell_in_range = SECRET_RANGE
    eq(api.IsSpellInRange("Exorcism", "target"), nil, "R8 secret: the classic global degrades to unknown")
end

do
    local sb = build({ retail = true, project = 1, interface = 120100 })
    local api = sb.st.api

    sb.c_spell_range = true
    eq(api.IsSpellInRange(879, "target"), 1, "R8 retail control: true normalises to 1")
    sb.c_spell_range = false
    eq(api.IsSpellInRange(879, "target"), 0, "R8 retail control: false normalises to 0")
    sb.c_spell_range = nil
    eq(api.IsSpellInRange(879, "target"), nil, "R8 retail control: nil stays unknown")
    sb.c_spell_range = "junk"
    eq(api.IsSpellInRange(879, "target"), nil, "R8 retail: an out-of-contract return is unknown")
    sb.c_spell_range = SECRET_RANGE_BOOL
    eq(api.IsSpellInRange(879, "target"), nil, "R8 retail secret: the probe degrades to unknown")
end

--=========================================================================================
-- 12. R9 + the paladin HUD: secret creature type, range tint, cooldowns
--=========================================================================================
do
    local sb = build({
        modules = { "compat.lua", "utils.lua", "twist.lua", "nextaction.lua", "classes/paladin.lua" },
        spell_info = {
            [879] = { name = "Exorcism" },
            [26573] = { name = "Consecration" },
            [35395] = { name = "Crusader Strike" },
            [20271] = { name = "Judgement" },
        },
        known = { [879] = true, [26573] = true, [35395] = true, [20271] = true },
    })
    local ST = sb.ST
    ST.mainhand = { speed = 2.6, ends_at = 110, start = 108, is_full = false }
    ST.gcd = { expires = 101 }
    ST.latency = { world_ms = 30 }
    ST.has_soc = false
    ST.has_sob = false
    sb.class_db = {
        nextaction_reaction_time_ms = 100,
        nextaction_cs_max_delay_ms = 1700,
        lag_multiplier = 1.4,
        lag_offset = 15,
        hud_mana_tint = true,
        hud_range_tint = true,
    }

    -- Guide gather: a secret creature type is unknown (never indexed as a key).
    sb.creature_type = SECRET_CTYPE
    sb.cooldowns = { [35395] = { SECRET_CD_START, SECRET_CD_DURATION, 1, 1 } }
    sb.power = SECRET_POWER_MANA
    sb.power_max = SECRET_POWER_MAX
    local out = {}
    local ok, err = pcall(ST.PALADIN.gather_guide_inputs, ST, out)
    check(ok, "paladin gather with secret readings does not throw (" .. tostring(err) .. ")")
    eq(out.creature_type, nil, "paladin gather: a secret creature type is unknown")
    eq(out.mana_pct, 0, "paladin gather: secret mana is unknown (0%)")
    eq(out.cs_remaining, 0, "paladin gather: a secret CS cooldown reads ready")

    -- Control: honest readings flow through untouched.
    sb.creature_type = "Undead"
    sb.cooldowns = { [35395] = { 95, 10, 1, 1 } }
    sb.power = 50
    sb.power_max = 100
    out = {}
    ok = pcall(ST.PALADIN.gather_guide_inputs, ST, out)
    check(ok, "paladin gather control does not throw")
    eq(out.creature_type, "Undead", "paladin gather control: creature type passes through")
    eq(out.mana_pct, 50, "paladin gather control: mana percentage computes")
    near(out.cs_remaining, 5, 1e-9, "paladin gather control: CS cooldown remaining computes")

    -- HUD exorcism slot: secret readings tint nothing wrongly and never error.
    ST.in_combat = true
    ST.twist_active_seals_count = 1
    sb.creature_type = SECRET_CTYPE
    sb.spell_in_range = SECRET_RANGE
    sb.cooldowns = { ["Exorcism"] = { SECRET_CD_START, SECRET_CD_DURATION, 1, 1 } }
    local s
    ok = pcall(function()
        s = ST.PALADIN.get_hud_state(ST, { key = "exorcism", spell = 879 }, 100)
    end)
    check(ok, "paladin HUD (secret creature type/range/cooldown) does not throw")
    eq(s.desaturate, true, "paladin HUD: a secret creature type greys the Exorcism icon")
    eq(s.glow, false, "paladin HUD: a secret creature type never glows")
    eq(s.in_range, nil, "paladin HUD: a secret range probe is unknown, not out of range")

    -- Control: an Undead target glows, a real out-of-range reading tints.
    sb.creature_type = "Undead"
    sb.spell_in_range = 0
    sb.cooldowns = {}
    sb.usable = false
    sb.insufficient = true
    ok = pcall(function()
        s = ST.PALADIN.get_hud_state(ST, { key = "exorcism", spell = 879 }, 100)
    end)
    check(ok, "paladin HUD control does not throw")
    eq(s.desaturate, nil, "paladin HUD control: an Undead target is not greyed (exorcisable)")
    eq(s.glow, true, "paladin HUD control: ready + in combat glows")
    eq(s.in_range, false, "paladin HUD control: a real 0 marks out of range")
    eq(s.usable, false, "paladin HUD control: a real insufficient reading tints")
end

--=========================================================================================
-- 13. R10: remaining wrappers (inventory, distance, usability, base cooldown, casts)
--=========================================================================================
do
    local sb = build()
    local api = sb.st.api

    sb.inventory_id = 12345
    sb.inventory_texture = "icon_tex"
    sb.inventory_cooldown = { 5, 30, 1 }
    eq(api.GetInventoryItemID(13), 12345, "R10 control: inventory item id passes through")
    eq(sb.inventory_query[1], "player", "R10 control: the item id read is the player's")
    eq(api.GetInventoryItemTexture(13), "icon_tex", "R10 control: inventory texture passes through")
    local a, b, c = api.GetInventoryItemCooldown(13)
    check(a == 5 and b == 30 and c == 1,
        "R10 control: inventory cooldown passes through (5/30/1)")

    sb.inventory_id = SECRET_INVENTORY_ID
    sb.inventory_texture = SECRET_INVENTORY_TEXTURE
    sb.inventory_cooldown = { SECRET_INVENTORY_START, SECRET_INVENTORY_DURATION, 1 }
    eq(api.GetInventoryItemID(13), nil, "R10 secret: inventory item id reports unknown (nil)")
    eq(api.GetInventoryItemTexture(13), nil, "R10 secret: inventory texture reports unknown (nil)")
    a, b, c = api.GetInventoryItemCooldown(13)
    check(a == 0 and b == 0 and c == 0, "R10 secret: inventory cooldown reports the idle shape")

    sb.check_distance = true
    eq(api.CheckInteractDistance("target", 3), true, "R10 control: CheckInteractDistance passes through")
    sb.check_distance = SECRET_CHECK_DISTANCE
    eq(api.CheckInteractDistance("target", 3), nil, "R10 secret: CheckInteractDistance reports unknown (nil)")

    sb.usable = true
    sb.insufficient = false
    local usable, insufficient = api.IsSpellUsable(879)
    eq(usable, true, "R10 control: IsSpellUsable passes through usable")
    eq(insufficient, false, "R10 control: IsSpellUsable passes through insufficientPower")
    sb.usable = SECRET_USABLE
    sb.insufficient = SECRET_INSUFFICIENT
    usable, insufficient = api.IsSpellUsable(879)
    eq(usable, nil, "R10 secret: IsSpellUsable usable reports unknown (nil)")
    eq(insufficient, nil, "R10 secret: IsSpellUsable insufficientPower reports unknown (nil)")

    sb.base_cooldown = 15000
    local ba, bb = api.GetSpellBaseCooldown(879)
    eq(ba, 15000, "R10 control: GetSpellBaseCooldown passes through")
    eq(bb, nil, "R10 control: the second return stays nil when the client reports one value")
    sb.base_cooldown = SECRET_BASE_COOLDOWN
    ba, bb = api.GetSpellBaseCooldown(879)
    check(ba == 0 and bb == 0,
        "R10 secret: GetSpellBaseCooldown reports the absent-client shape (0, 0)")

    -- The pass-through is deliberate: the smoke suite pins GetSpellPowerCost's identity,
    -- so the secret handling lives at the consumers (rage_cost_of in warrior/druid).
    check(api.GetSpellPowerCost == sb.env.GetSpellPowerCost,
        "R10 pin: GetSpellPowerCost stays a pass-through (consumer-guarded)")
    sb.power_cost = SECRET_COST
    local costs = api.GetSpellPowerCost(78)
    eq(costs[1].cost, SECRET_COST, "R10 pin: the raw cost is untouched at the wrapper")

    -- Casting: a secret payload reads as "no cast" (the whole-payload degrade).
    sb.cast_payload = { name = "Lightning Bolt", start_ms = 150, end_ms = 152.5, spell_id = 403 }
    local name, _, _, start_ms, end_ms, _, _, _, spell_id = api.UnitCastingInfo("player")
    eq(name, "Lightning Bolt", "R10 control: UnitCastingInfo name passes through")
    eq(start_ms, 150, "R10 control: UnitCastingInfo start passes through")
    eq(end_ms, 152.5, "R10 control: UnitCastingInfo end passes through")
    eq(spell_id, 403, "R10 control: UnitCastingInfo spell id passes through")

    sb.cast_payload = { name = "Lightning Bolt", start_ms = SECRET_CAST_START, end_ms = SECRET_CAST_END, spell_id = 403 }
    name = api.UnitCastingInfo("player")
    eq(name, nil, "R10 secret: a secret cast payload reports no cast")

    sb.channel_payload = { name = "Lightning Bolt", start_ms = SECRET_CAST_START, end_ms = SECRET_CAST_END, spell_id = 403 }
    name = api.UnitChannelInfo("player")
    eq(name, nil, "R10 secret: a secret channel payload reports no channel")
    sb.channel_payload = { name = "Lightning Bolt", start_ms = 150, end_ms = 152.5, spell_id = 403 }
    name, _, _, start_ms, end_ms = api.UnitChannelInfo("player")
    eq(name, "Lightning Bolt", "R10 control: UnitChannelInfo name passes through")
    eq(start_ms, 150, "R10 control: UnitChannelInfo start passes through")
    eq(end_ms, 152.5, "R10 control: UnitChannelInfo end passes through")

    -- The folded reader (api.UnitCastingSpell) consumes the sanitized sources.
    sb.cast_payload = { name = "Lightning Bolt", start_ms = 150, end_ms = 152.5, spell_id = 403 }
    sb.channel_payload = nil
    local cname, cspell, cstart, cend = api.UnitCastingSpell("player")
    eq(cname, "Lightning Bolt", "R10 control: UnitCastingSpell folds a live cast")
    eq(cspell, 403, "R10 control: UnitCastingSpell keeps the spell id")
    near(cstart, 0.15, 1e-9, "R10 control: UnitCastingSpell start in seconds")
    near(cend, 0.1525, 1e-9, "R10 control: UnitCastingSpell end in seconds")

    sb.cast_payload = { name = "Lightning Bolt", start_ms = SECRET_CAST_START, end_ms = SECRET_CAST_END, spell_id = 403 }
    cname = api.UnitCastingSpell("player")
    eq(cname, nil, "R10 secret: UnitCastingSpell reports no cast")
end

--=========================================================================================
-- 13b. M5 observability: api.auras_may_be_secret (release in the secret regime)
--=========================================================================================
do
    local sb = build({})
    local api = sb.st.api
    check(type(api.auras_may_be_secret) == "function",
        "M5 probe: the compat wrapper is exported")

    -- Control: a classic client has no C_Secrets at all -> nil (unknown, never "no").
    sb.env.C_Secrets = nil
    eq(api.auras_may_be_secret(), nil, "M5 probe: no C_Secrets reads nil (control)")

    -- The client's own answers pass through.
    sb.env.C_Secrets = { ShouldAurasBeSecret = function() return true end }
    eq(api.auras_may_be_secret(), true, "M5 probe: secret auras -> true")
    sb.env.C_Secrets = { ShouldAurasBeSecret = function() return false end }
    eq(api.auras_may_be_secret(), false, "M5 probe: unrestricted auras -> false")

    -- Unknown shapes degrade to nil instead of guessing.
    sb.env.C_Secrets = { ShouldAurasBeSecret = function() return "yes" end }
    eq(api.auras_may_be_secret(), nil, "M5 probe: a non-boolean answer reads unknown")
    sb.env.C_Secrets = { ShouldAurasBeSecret = function() error("restricted") end }
    eq(api.auras_may_be_secret(), nil, "M5 probe: a throwing probe reads unknown")
    sb.env.C_Secrets = { ShouldAurasBeSecret = 1 }
    eq(api.auras_may_be_secret(), nil, "M5 probe: a missing function reads unknown")
    sb.env.C_Secrets = "SECRET"
    eq(api.auras_may_be_secret(), nil, "M5 probe: a non-table C_Secrets reads unknown")
    sb.env.C_Secrets = nil
end

--=========================================================================================
-- 14. Static pin: the vendored LibRangeCheck-2.0 guard (with an in-suite bite-proof)
--=========================================================================================
local function rangecheck_guard_failures(src)
    -- Counts the violated invariants for the two guarded registrations. The vendored
    -- 2.0 is deprecated upstream; the guard mirrors the maintained fork
    -- (LibRangeCheck-3.0, WeakAuras), and these invariants pin it against re-vendoring.
    local failed = 0
    local function guarded_register(event)
        local guard = 'C_EventUtils.IsEventValid("' .. event .. '")'
        local register = 'frame:RegisterEvent("' .. event .. '")'
        local guard_at = src:find(guard, 1, true)
        local register_at = src:find(register, 1, true)
        local registers = 0
        local pos = 1
        while true do
            local found = src:find(register, pos, true)
            if not found then break end
            registers = registers + 1
            pos = found + 1
        end
        if registers ~= 1 then failed = failed + 1 end
        if guard_at == nil or register_at == nil or guard_at >= register_at then
            failed = failed + 1
        end
    end
    guarded_register("LEARNED_SPELL_IN_TAB")
    guarded_register("PLAYER_TALENT_UPDATE")
    return failed
end

do
    local path = ROOT .. "Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua"
    local f = assert(io.open(path, "r"))
    local src = f:read("*a")
    f:close()
    eq(rangecheck_guard_failures(src), 0,
        "LibRangeCheck pin: both registrations are guarded and none is unguarded")

    -- Bite-proof: strip the LEARNED_SPELL_IN_TAB guard and the same invariants must fail.
    local guard_line = 'if not C_EventUtils or C_EventUtils.IsEventValid("LEARNED_SPELL_IN_TAB") then'
    local at = src:find(guard_line, 1, true)
    check(at ~= nil, "LibRangeCheck bite-proof setup: the guard line exists")
    local mutated = src:sub(1, (at or 1) - 1) .. src:sub((at or 1) + #guard_line)
    check(rangecheck_guard_failures(mutated) > 0,
        "LibRangeCheck bite-proof: the guard-stripped copy fails the pin")
end

--=========================================================================================
-- Non-vacuity floor
--=========================================================================================
check(checks >= 100, "non-vacuity floor: the suite exercised at least 100 checks")

if failures == 0 then
    print("PASS  secret_guard_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  secret_guard_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
