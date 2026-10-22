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
local SECRET_RATING = secret({})               -- opaque table: arithmetic errors on it
local SECRET_RATING_BONUS = secret({})
local SECRET_ITEM_NAME = secret("SECRET_ITEM")
local SECRET_ITEM_CLASS = secret("SECRET_CLASS")
local SECRET_ITEM_SUBCLASS = secret("SECRET_SUBCLASS")
local SECRET_SPELL_NAME = secret("SECRET_SPELL_NAME")

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
            sb.spell_queries = sb.spell_queries or {}
            sb.spell_queries[#sb.spell_queries + 1] = id
            if sb.spell_info_throws then error("restricted") end
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
        -- A probe that DECLINES (returns nil) instead of answering: the knowledge chain
        -- must move on to the next probe. Opt-in, so the default profile keeps proving
        -- the answering shape.
        env.IsSpellKnown = function(id)
            if opts.known_declines then
                return nil
            end
            return sb.known[id] == true
        end
        env.IsSpellUsable = function() return sb.usable, sb.insufficient end
        env.IsSpellInRange = function() return sb.spell_in_range end
        -- Optional movement probes (the hunter weave-prog lane): installed only on
        -- demand, so the default profile keeps proving the absent-probe shape.
        if opts.unit_speed then
            env.GetUnitSpeed = opts.unit_speed
        end
        if opts.player_moving then
            env.IsPlayerMoving = opts.player_moving
        end
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
        -- Optional classic combat-log getter (the shared trinket-ICD path):
        -- installed before compat loads so the wrapper captures it; absent by
        -- default (nil reads as no combat log, the Mainline-code shape).
        if opts.combat_log then
            env.CombatLogGetCurrentEventInfo = function()
                return sb.combat_log_payload()
            end
        end
        -- Item probes, weapon enchant and unit identity (the rogue compat wrappers).
        -- Absent on demand (opts.omit_compat_probes) to prove the no-probe shapes.
        if not opts.omit_compat_probes then
            env.GetItemInfo = function(item)
                if sb.item_info_throws then error("restricted") end
                local info = sb.item_info and sb.item_info[item]
                if not info then return nil end
                if sb.item_info_table then
                    return {
                        itemName = info.name or "Table Item", itemLink = "table:link",
                        itemQuality = 2, itemLevel = 1, itemMinLevel = 1,
                        itemType = info.class or "Weapon", itemSubType = info.subclass,
                    }
                end
                return info.name or "Test Item", "item:link", 2, 1, 1,
                    info.class or "Weapon", info.subclass
            end
            env.GetItemCount = function()
                if sb.item_count_throws then error("restricted") end
                return sb.item_count
            end
            env.GetItemCooldown = function()
                if sb.item_cd_throws then error("restricted") end
                return sb.item_cd_start, sb.item_cd_duration, sb.item_cd_enabled
            end
            env.GetWeaponEnchantInfo = function()
                if sb.weapon_enchant_throws then error("restricted") end
                local w = sb.weapon_enchant
                if not w then
                    return false, nil, nil, nil, false
                end
                return w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8]
            end
            env.UnitGUID = function(unit)
                if sb.unit_guid_throws then error("restricted") end
                return sb.unit_guid and sb.unit_guid[unit] or nil
            end
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
        -- Fictional C_Spell knowledge probes (no client ships C_Spell.IsSpellKnown*):
        -- installed on demand so the suite can pin that compat never consults them.
        if opts.c_spell_known then
            env.C_Spell.IsSpellKnown = function() return true end
            env.C_Spell.IsSpellKnownOrOverridesKnown = function() return true end
        end
        env.C_UnitAuras = {
            GetAuraDataByIndex = function()
                return sb.aura_table
            end,
        }
    end

    -- Optional C_Item namespace (modern clients): answers even where the deprecated
    -- globals are not loaded. Separate from the classic block so a build can show both
    -- the preference (both sources present) and the fallback (C_Item alone).
    if opts.c_item then
        env.C_Item = {
            GetItemInfo = function(item)
                if sb.c_item_info_throws then error("restricted") end
                local info = sb.c_item_info and sb.c_item_info[item]
                if not info then return nil end
                return info.name or "C Item", "c:link", 2, 1, 1,
                    info.class or "Weapon", info.subclass
            end,
            GetItemCount = function()
                return sb.c_item_count
            end,
            GetItemCooldown = function()
                return sb.c_item_cd_start, sb.c_item_cd_duration, sb.c_item_cd_enabled
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
    -- Sibling-only profile: where IsSpellKnown is absent, IsSpellKnownOrInSpellBook
    -- answers instead.
    if opts.c_spellbook_in_book then
        env.C_SpellBook = {
            IsSpellKnownOrInSpellBook = function(id)
                sb.spellbook_calls = (sb.spellbook_calls or 0) + 1
                return sb.spellbook_in_book and sb.spellbook_in_book[id] == true
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
        -- Class files register their body as a loader (operator order 2026-10-21:
        -- only the selected class executes). This sandbox activates every class it
        -- loads, as the shipped init does for the selected one.
        local class = modules[i]:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
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
    eq(sb.aura_calls, 40, "warrior aura control: the scan walks the capped list (H1: no early break)")
    eq(sb.glow_starts, 1, "warrior aura control: the glow starts")

    -- Secret field: the entry is invisible, the scan walks past it, no glow.
    ST.bloodsurge_glow_active = false
    sb.aura_rows = { [1] = { name = "Blood Surge", duration = SECRET_AURA_DURATION, spell_id = 46916 } }
    sb.aura_calls = 0
    ok = pcall(ST.WARRIOR.on_aura_change, ST)
    check(ok, "warrior aura with a secret field does not throw")
    eq(ST.has_bloodsurge, false, "warrior aura: a secret aura is treated as absent")
    eq(sb.aura_calls, 40, "warrior aura: the scan walks past the secret row to the cap (H1)")
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
    local order_flag, order_state = sb.st.api.is_spell_known_state(78)
    eq(order_flag, true, "R7 state: an answering probe reads true")
    eq(order_state, "known", "R7 state: an answering probe reads the 'known' state")

    -- On a Mainline client the classic global is gone: C_SpellBook answers.
    local sb2 = build({ retail = true, project = 1, interface = 120100, c_spellbook = true })
    sb2.spellbook_known = { [78] = true, [999] = false }
    sb2.spellbook_calls = 0
    eq(sb2.st.api.is_spell_known(78), true, "R7 probe: C_SpellBook answers known spells")
    eq(sb2.st.api.is_spell_known(999), false, "R7 probe: C_SpellBook answers unknown spells")
    check(sb2.spellbook_calls >= 2, "R7 probe: the calls went to C_SpellBook")
    local probe_flag, probe_state = sb2.st.api.is_spell_known_state(78)
    eq(probe_flag, true, "R7 state: C_SpellBook reads true for a known spell")
    eq(probe_state, "known", "R7 state: C_SpellBook reads the 'known' state")
    local absent_flag, absent_state = sb2.st.api.is_spell_known_state(999)
    eq(absent_flag, false, "R7 state: C_SpellBook reads false for an unknown spell")
    eq(absent_state, "not_known", "R7 state: an answered 'no' reads the 'not_known' state")

    -- No probe at all: the boolean answer is false (fail-closed), and the state says WHY:
    -- the client could not answer, so this is NOT the claim "the player does not know it".
    local sb3 = build({ retail = true, project = 1, interface = 120100 })
    eq(sb3.st.api.is_spell_known(78), false, "R7 no probe: the boolean answers false (fail-closed)")
    local no_probe_flag, no_probe_state = sb3.st.api.is_spell_known_state(78)
    eq(no_probe_flag, false, "R7 no probe: the state answer is false as well")
    eq(no_probe_state, "unknown", "R7 no probe: the state says unknown - the client cannot answer")

    -- The C_Spell namespace is never consulted for knowledge (C_Spell.IsSpellKnown*
    -- exists on no client): even probes answering true there must not decide.
    local sb4 = build({ retail = true, project = 1, interface = 120100, c_spell_known = true })
    eq(sb4.st.api.is_spell_known(78), false, "R7 namespace: C_Spell knowledge probes are ignored")
    local ns_flag, ns_state = sb4.st.api.is_spell_known_state(78)
    eq(ns_flag, false, "R7 namespace: the ignored namespace decides nothing")
    eq(ns_state, "unknown", "R7 namespace: with no usable probe the state is unknown")

    -- The sibling probe: where only IsSpellKnownOrInSpellBook exists, it answers.
    local sb5 = build({ retail = true, project = 1, interface = 120100, c_spellbook_in_book = true })
    sb5.spellbook_in_book = { [78] = true, [999] = false }
    sb5.spellbook_calls = 0
    eq(sb5.st.api.is_spell_known(78), true, "R7 sibling: IsSpellKnownOrInSpellBook answers known spells")
    eq(sb5.st.api.is_spell_known(999), false, "R7 sibling: IsSpellKnownOrInSpellBook answers unknown spells")
    check(sb5.spellbook_calls >= 2, "R7 sibling: the calls went to C_SpellBook")
    local sib_flag, sib_state = sb5.st.api.is_spell_known_state(78)
    eq(sib_flag, true, "R7 state: the sibling probe reads true for a known spell")
    eq(sib_state, "known", "R7 state: the sibling probe reads the 'known' state")

    -- A probe that DECLINES (returns nil) does not decide: the chain moves on to the next
    -- probe. This is the difference between "no probe answered" and "the client says no".
    local sb6 = build({ c_spellbook = true, known_declines = true })
    sb6.spellbook_known = { [78] = true, [999] = false }
    local decline_flag, decline_state = sb6.st.api.is_spell_known_state(78)
    eq(decline_flag, true, "R7 decline: the next probe answers after a declining probe")
    eq(decline_state, "known", "R7 decline: the state is the answering probe's state")
    local decline2_flag, decline2_state = sb6.st.api.is_spell_known_state(999)
    eq(decline2_flag, false, "R7 decline: the next probe's 'no' answers false")
    eq(decline2_state, "not_known", "R7 decline: the next probe's 'no' reads the 'not_known' state")

    -- Every probe declines: the client still cannot answer, so the state is unknown.
    local sb7 = build({ known_declines = true })
    local all_flag, all_state = sb7.st.api.is_spell_known_state(78)
    eq(all_flag, false, "R7 decline-only: the boolean answers false (fail-closed)")
    eq(all_state, "unknown", "R7 decline-only: no probe answered, so the state is unknown")

    -- The boolean is BOOLEAN in every profile - it never answers nil. The consumers below
    -- depend on it: the rogue guide reads the raw return and tests it against false, and
    -- the diag readout renders a non-boolean as "?" instead of "false".
    eq(type(sb.st.api.is_spell_known(78)), "boolean", "R7 type: an answering profile returns a boolean")
    eq(type(sb2.st.api.is_spell_known(78)), "boolean", "R7 type: the C_SpellBook profile returns a boolean")
    eq(type(sb3.st.api.is_spell_known(78)), "boolean", "R7 type: the probe-less profile returns a boolean")
    eq(type(sb4.st.api.is_spell_known(78)), "boolean", "R7 type: the ignored-namespace profile returns a boolean")
    eq(type(sb5.st.api.is_spell_known(78)), "boolean", "R7 type: the sibling-probe profile returns a boolean")
    eq(type(sb6.st.api.is_spell_known(78)), "boolean", "R7 type: the declining-probe profile returns a boolean")
    eq(type(sb7.st.api.is_spell_known(78)), "boolean", "R7 type: the decline-only profile returns a boolean")
end

--=========================================================================================
-- 10b. M3: the spell-knowledge contract (the comment, the code and the callers agree)
--=========================================================================================
-- The deep audit's M3: the spell-knowledge comment claimed a client with none of the
-- probes "reports 'unknown'", while the code answered false. The behaviour was safe
-- (every caller treats false as fail-closed) but the CONTRACT was wrong, and a future
-- row that must hide when the client cannot answer had no way to tell "no probe
-- answered" from "the player does not know the spell".
--
-- The contract, pinned here:
--   api.is_spell_known is BINARY (true / false, never nil) - the two raw consumers in the
--   tree (rogue_guide.lua's "args.ar_known == false" and diag.lua's "type(known) ==
--   'boolean'") would both change behaviour on a nil, so the boolean may not fold the
--   third state into itself.
--   api.is_spell_known_state carries the third state (known / not_known / unknown) - the
--   same shape as api.get_family_spell_id_state - so the distinction is observable
--   through the API without touching a single caller.
--   The comment next to the wrapper must state exactly that, or the mismatch is back.
do
    local f = assert(io.open(ROOT .. "compat.lua", "r"))
    local src = f:read("*a")
    f:close()

    local start_at = src:find("-- Spell knowledge", 1, true)
    local stop_at = src:find("-- Spell cooldowns", 1, true)
    check(start_at ~= nil, "M3 setup: the spell-knowledge section exists in compat.lua")
    check(stop_at ~= nil and start_at ~= nil and stop_at > start_at,
        "M3 setup: the spell-knowledge section is bounded by the next section")
    local block = src:sub(start_at or 1, (stop_at or 1) - 1)

    -- The COMMENT half of the section (the code half is pinned by the behavioural checks
    -- above). A comment pin must not be satisfied by the code's own string literals.
    local comment_text = {}
    for line in (block .. "\n"):gmatch("([^\n]*)\n") do
        local stripped = line:match("^%s*(%-%-.*)$")
        if stripped then
            comment_text[#comment_text + 1] = stripped
        end
    end
    comment_text = table.concat(comment_text, "\n")

    -- The stale claim is gone: the code never answered "unknown" there, it answered false.
    check(comment_text:find('reports "unknown"', 1, true) == nil,
        "M3 contract: the stale 'reports unknown' claim is gone from the spell-knowledge comment")
    -- The contract the code implements is stated in the same comment.
    check(comment_text:find("binary", 1, true) ~= nil,
        "M3 contract: the comment states the binary contract")
    check(comment_text:find("never nil", 1, true) ~= nil,
        "M3 contract: the comment states that the answer is never nil")
    check(comment_text:find("not_known", 1, true) ~= nil,
        "M3 contract: the comment names the 'not_known' state")
    check(comment_text:find('"unknown"', 1, true) ~= nil,
        "M3 contract: the comment names the 'unknown' state")
    check(block:find("function api.is_spell_known_state", 1, true) ~= nil,
        "M3 contract: the state accessor lives in the documented section")

    -- The binary contract is load-bearing for the two raw consumers: pin their shapes, so
    -- a future edit that folds the third state into the boolean has to touch these pins.
    local rogue_f = assert(io.open(ROOT .. "classes/rogue.lua", "r"))
    local rogue_src = rogue_f:read("*a")
    rogue_f:close()
    local guide_f = assert(io.open(ROOT .. "rogue_guide.lua", "r"))
    local guide_src = guide_f:read("*a")
    guide_f:close()
    local diag_f = assert(io.open(ROOT .. "diag.lua", "r"))
    local diag_src = diag_f:read("*a")
    diag_f:close()
    -- The rogue provider feeds the RAW return (not a normalised boolean) into
    -- inputs.ar_known: the line must match exactly, so a normalisation there is noticed
    -- (it would silently drop the raw consumer this contract's justification rests on).
    local ar_raw, ar_normalised = 0, 0
    for line in rogue_src:gmatch("([^\n]*)\n") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed:find("inputs.ar_known", 1, true) and trimmed:find("api.is_spell_known", 1, true) then
            if trimmed == "inputs.ar_known = api.is_spell_known(ar_query)" then
                ar_raw = ar_raw + 1
            else
                ar_normalised = ar_normalised + 1
            end
        end
    end
    check(ar_raw == 1,
        "M3 contract: the rogue provider feeds the raw return into inputs.ar_known")
    check(ar_normalised == 0,
        "M3 contract: no normalisation sneaks into the rogue's ar_known feed")
    check(guide_src:find("args.ar_known == false", 1, true) ~= nil,
        "M3 contract: the rogue guide tests the raw return against false - nil would flip it")
    check(diag_src:find('type(known) == "boolean"', 1, true) ~= nil,
        "M3 contract: the diag readout renders a non-boolean as '?' - nil would change it")
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

    check(api.CheckInteractDistance == nil,
        "R10: the protected CheckInteractDistance wrapper is gone (exact yards only)")

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
-- 13c. Item probes / weapon enchant / unit identity (rogue compat move)
--=========================================================================================
do
    -- Classic globals answer (the pre-C_Item clients): every wrapper passes through.
    local sb = build()
    local api = sb.st.api

    sb.item_info = { [90001] = { name = "Test Blade", class = "Weapon", subclass = "Sword" } }
    local name, link, quality, level, min_level, item_type, item_sub_type = api.GetItemInfo(90001)
    eq(name, "Test Blade", "item info control: name passes through")
    eq(link, "item:link", "item info control: link passes through")
    eq(quality, 2, "item info control: quality passes through")
    eq(level, 1, "item info control: level passes through")
    eq(min_level, 1, "item info control: minLevel passes through")
    eq(item_type, "Weapon", "item info control: the item type is the 6th return")
    eq(item_sub_type, "Sword", "item info control: the item subtype is the 7th return")

    sb.item_info = nil
    eq(api.GetItemInfo(90001), nil, "item info: an unknown item reports nil")

    sb.item_info = { [90001] = { class = SECRET_ITEM_CLASS, subclass = "Sword" } }
    eq(api.GetItemInfo(90001), nil, "item info secret item type: the whole read reports nil")

    sb.item_info = { [90001] = { class = "Weapon", subclass = SECRET_ITEM_SUBCLASS } }
    eq(api.GetItemInfo(90001), nil, "item info secret item subtype: the whole read reports nil")

    sb.item_info = { [90001] = { name = SECRET_ITEM_NAME, subclass = "Sword" } }
    eq(api.GetItemInfo(90001), nil, "item info secret name: the whole read reports nil")

    sb.item_info = { [90001] = { subclass = "Sword" } }
    sb.item_info_throws = true
    eq(api.GetItemInfo(90001), nil, "item info: a throwing probe reports nil")
    sb.item_info_throws = false

    -- Table-shaped read (defensive path): unfolded to the classic positions.
    sb.item_info_table = true
    name, link, quality, level, min_level, item_type, item_sub_type = api.GetItemInfo(90001)
    eq(name, "Table Item", "item info table control: the table name is unfolded")
    eq(link, "table:link", "item info table control: itemLink is unfolded")
    eq(quality, 2, "item info table control: itemQuality is unfolded")
    eq(level, 1, "item info table control: itemLevel is unfolded")
    eq(min_level, 1, "item info table control: itemMinLevel is unfolded")
    eq(item_type, "Weapon", "item info table control: itemType lands at the item-type position")
    eq(item_sub_type, "Sword", "item info table control: itemSubType lands at the item-subtype position")
    sb.item_info = { [90001] = { class = "Weapon", subclass = SECRET_ITEM_SUBCLASS } }
    eq(api.GetItemInfo(90001), nil, "item info secret table subtype: reports nil")
    sb.item_info_table = nil
    sb.item_info = nil

    -- Item count.
    sb.item_count = 3
    eq(api.GetItemCount("Thistle Tea"), 3, "item count control: the count passes through")
    sb.item_count = nil
    eq(api.GetItemCount("Thistle Tea"), nil, "item count: no reading reports nil")
    sb.item_count = SECRET_USABLE
    eq(api.GetItemCount("Thistle Tea"), nil, "item count secret: reports unknown (nil)")
    sb.item_count = 3
    sb.item_count_throws = true
    eq(api.GetItemCount("Thistle Tea"), nil, "item count: a throwing probe reports nil")
    sb.item_count_throws = false
    sb.item_count = nil
    sb.item_count = "3"
    eq(api.GetItemCount("Thistle Tea"), nil, "item count: a non-number reading reports nil")
    sb.item_count = nil

    -- Item cooldown: normalised (start, duration, enabled); idle shape on every unknown.
    sb.item_cd_start, sb.item_cd_duration, sb.item_cd_enabled = 5, 300, 1
    local a, b, c = api.GetItemCooldown("Thistle Tea")
    check(a == 5 and b == 300 and c == 1,
        "item cooldown control: the triple passes through")
    sb.item_cd_start, sb.item_cd_duration, sb.item_cd_enabled =
        SECRET_INVENTORY_START, SECRET_INVENTORY_DURATION, 1
    a, b, c = api.GetItemCooldown("Thistle Tea")
    check(a == 0 and b == 0 and c == 0, "item cooldown secret: reports the idle shape")
    sb.item_cd_start, sb.item_cd_duration, sb.item_cd_enabled = nil, nil, nil
    a, b, c = api.GetItemCooldown("Thistle Tea")
    check(a == 0 and b == 0 and c == 0, "item cooldown: a blank read is the idle shape")
    sb.item_cd_throws = true
    a, b, c = api.GetItemCooldown("Thistle Tea")
    check(a == 0 and b == 0 and c == 0, "item cooldown: a throwing probe is the idle shape")
    sb.item_cd_throws = false

    -- Weapon enchant presence: four values per weapon slot; the OFFHAND presence is the
    -- 5th return (the 4th is the mainhand enchant id). A wrapper reading the 4th would
    -- misreport the position-pin payloads below.
    local has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, false, "weapon enchant control: the default read reports no enchant")
    eq(has_oh, false, "weapon enchant control: the default OH read reports no enchant")

    sb.weapon_enchant = { true, 3600, nil, true, false, nil, nil, nil }
    has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, true, "weapon enchant pin: MH true passes through")
    eq(has_oh, false, "weapon enchant pin: OH presence is the 5th value, never the 4th")

    sb.weapon_enchant = { false, nil, nil, nil, true, 3600, nil, nil }
    has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, false, "weapon enchant pin: MH false passes through")
    eq(has_oh, true, "weapon enchant pin: OH true comes from the 5th value")

    sb.weapon_enchant = { SECRET_USABLE, 3600, nil, nil, false, nil, nil, nil }
    has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, nil, "weapon enchant secret MH: reads unknown (nil)")
    eq(has_oh, nil, "weapon enchant secret MH: OH degrades with the read")

    sb.weapon_enchant = { true, 3600, nil, nil, SECRET_USABLE, nil, nil, nil }
    has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, nil, "weapon enchant secret OH: MH degrades with the read")
    eq(has_oh, nil, "weapon enchant secret OH: reads unknown (nil)")

    sb.weapon_enchant = { true, 3600, nil, nil, 12345, nil, nil, nil }
    has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, nil, "weapon enchant non-boolean OH: reads unknown (nil)")
    eq(has_oh, nil, "weapon enchant non-boolean OH: never claims a presence")

    sb.weapon_enchant_throws = true
    has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, nil, "weapon enchant: a throwing probe reads unknown (MH)")
    eq(has_oh, nil, "weapon enchant: a throwing probe reads unknown (OH)")
    sb.weapon_enchant_throws = false
    sb.weapon_enchant = nil

    -- Unit identity.
    sb.unit_guid = { target = "Creature-0-1-2-3" }
    eq(api.UnitGUID("target"), "Creature-0-1-2-3", "unit guid control: the guid passes through")
    sb.unit_guid.target = nil
    eq(api.UnitGUID("target"), nil, "unit guid: no unit reports nil")
    sb.unit_guid = { target = SECRET_ITEM_NAME }
    eq(api.UnitGUID("target"), nil, "unit guid secret: reports unknown (nil)")
    sb.unit_guid = { target = 12345 }
    eq(api.UnitGUID("target"), nil, "unit guid: a non-string reading reports nil")
    sb.unit_guid = nil
    sb.unit_guid_throws = true
    eq(api.UnitGUID("target"), nil, "unit guid: a throwing probe reports nil")
    sb.unit_guid_throws = false
end

do
    -- C_Item is preferred where it is callable; the classic globals are the fallback.
    local sb = build({ c_item = true })
    local api = sb.st.api

    sb.c_item_info = { [90001] = { name = "C Blade", class = "Weapon", subclass = "Sword" } }
    sb.item_info = { [90001] = { name = "Global Blade", class = "Weapon", subclass = "Dagger" } }
    local name, _, _, _, _, _, item_sub_type = api.GetItemInfo(90001)
    eq(name, "C Blade", "C_Item preference: the C_Item read wins when callable")
    eq(item_sub_type, "Sword", "C_Item preference: the C_Item item subtype answers")

    sb.c_item_count = 2
    sb.item_count = 7
    eq(api.GetItemCount("Thistle Tea"), 2, "C_Item count preference: the C_Item read wins")

    sb.c_item_cd_start, sb.c_item_cd_duration, sb.c_item_cd_enabled = 9, 60, 1
    sb.item_cd_start, sb.item_cd_duration, sb.item_cd_enabled = 1, 2, 1
    local a, b = api.GetItemCooldown("Thistle Tea")
    check(a == 9 and b == 60, "C_Item cooldown preference: the C_Item read wins")
end

do
    -- A modern client whose deprecated globals are not loaded: C_Item alone answers.
    local sb = build({ c_item = true, omit_compat_probes = true })
    local api = sb.st.api

    sb.c_item_info = { [90001] = { class = "Weapon", subclass = "Sword" } }
    local _, _, _, _, _, item_type, item_sub_type = api.GetItemInfo(90001)
    eq(item_type, "Weapon", "C_Item fallback: item info answers without the globals")
    eq(item_sub_type, "Sword", "C_Item fallback: the item subtype answers without the globals")
    sb.c_item_count = 4
    eq(api.GetItemCount("Thistle Tea"), 4, "C_Item fallback: count answers without the globals")
    sb.c_item_cd_start, sb.c_item_cd_duration, sb.c_item_cd_enabled = 9, 60, 1
    local a, b, c = api.GetItemCooldown("Thistle Tea")
    check(a == 9 and b == 60 and c == 1,
        "C_Item fallback: cooldown answers without the globals")
    -- UnitGUID and GetWeaponEnchantInfo have no C_Item twin: still the unknown shapes.
    local has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, nil, "C_Item fallback: weapon enchant still reads unknown (nil)")
    eq(has_oh, nil, "C_Item fallback: weapon enchant OH still reads unknown (nil)")
    eq(api.UnitGUID("target"), nil, "C_Item fallback: unit guid still reads nil")
end

do
    -- Nothing at all answers (absent globals and namespace): the documented unknown shapes.
    local sb = build({ omit_compat_probes = true })
    local api = sb.st.api

    eq(api.GetItemInfo(90001), nil, "absent probes: item info reports nil")
    eq(api.GetItemCount("Thistle Tea"), nil, "absent probes: item count reports nil")
    local a, b, c = api.GetItemCooldown("Thistle Tea")
    check(a == 0 and b == 0 and c == 0, "absent probes: item cooldown reports the idle shape")
    local has_mh, has_oh = api.GetWeaponEnchantInfo()
    eq(has_mh, nil, "absent probes: weapon enchant reports unknown (nil)")
    eq(has_oh, nil, "absent probes: weapon enchant OH reports unknown (nil)")
    eq(api.UnitGUID("target"), nil, "absent probes: unit guid reports nil")
end

--=========================================================================================
-- 13c-bis. The item-info contract (L4): one normalised shape, whatever probe answered
--=========================================================================================
-- The publish-gate re-audit's L4: compat.lua's GetItemInfo wrapper named its 6th/7th
-- returns "class, subclass" - the CLASSIC GLOBAL's naming - while the PREFERRED probe
-- (C_Item.GetItemInfo) returns them as itemType / itemSubType on every branch
-- (ItemDocumentation.lua:621-622 live, :409-410 classic-line, :643-644 origin/forever;
-- the same multi-return in Blizzard's own code at
-- Blizzard_ItemButton/Shared/ItemButtonTemplate.lua:187 on all five branches).
-- The VALUES were always right - position 7 is the item's subtype string in both shapes
-- (the behavioural pins above prove it) - but the NAMES were not honest about which probe
-- answered, and the classic global's own naming is not citable from the reference tree at
-- all (a native C API with no Lua definition and no FrameXML call site on any branch).
--
-- The contract pinned here:
--   api.GetItemInfo returns name, link, quality, level, min_level, item_type, item_sub_type
--   - position 6 is the item's TYPE string and position 7 the item's SUBTYPE string,
--     whichever probe answered (C_Item names them itemType / itemSubType, the classic
--     global names them class / subclass).
--   The wrapper's locals carry the normalised names, the comment states the contract, and
--   the rogue's only consumer (classes/rogue.lua item_subclass) reads the same positions.
do
    local f = assert(io.open(ROOT .. "compat.lua", "r"))
    local src = f:read("*a")
    f:close()

    local start_at = src:find("-- Item info:", 1, true)
    local stop_at = src:find("-- Item count:", 1, true)
    check(start_at ~= nil, "L4 setup: the item-info section exists in compat.lua")
    check(stop_at ~= nil and start_at ~= nil and stop_at > start_at,
        "L4 setup: the item-info section is bounded by the next section")
    local block = src:sub(start_at or 1, (stop_at or 1) - 1)

    -- The COMMENT half of the section (the code half is pinned by the behavioural checks
    -- above). A comment pin must not be satisfied by the code's own string literals.
    local comment_text = {}
    for line in (block .. "\n"):gmatch("([^\n]*)\n") do
        local stripped = line:match("^%s*(%-%-.*)$")
        if stripped then
            comment_text[#comment_text + 1] = stripped
        end
    end
    comment_text = table.concat(comment_text, "\n")

    -- The contract the code implements is stated in the same comment.
    check(comment_text:find("CONTRACT", 1, true) ~= nil,
        "L4 contract: the comment states the contract")
    check(comment_text:find("item_type", 1, true) ~= nil,
        "L4 contract: the comment names the 6th return item_type")
    check(comment_text:find("item_sub_type", 1, true) ~= nil,
        "L4 contract: the comment names the 7th return item_sub_type")
    check(comment_text:find("TYPE", 1, true) ~= nil,
        "L4 contract: the comment says position 6 is the item's type")
    check(comment_text:find("SUBTYPE", 1, true) ~= nil,
        "L4 contract: the comment says position 7 is the item's subtype")
    -- The stale names must not come back as the CONTRACT's names. They may still be named
    -- as the CLASSIC GLOBAL's names (that is the fact being normalised away).
    check(comment_text:find("class, subclass", 1, true) == nil,
        "L4 contract: the old 'class, subclass' contract naming is gone from the comment")
    check(comment_text:find("itemType", 1, true) ~= nil,
        "L4 contract: the comment records the C_Item probe's own field names")
    check(comment_text:find("itemSubType", 1, true) ~= nil,
        "L4 contract: the comment records the C_Item probe's own field names")

    -- The wrapper's locals carry the normalised names (the shape the rogue consumer reads).
    check(block:find("min_level, item_type, item_sub_type =", 1, true) ~= nil,
        "L4 contract: the wrapper's 6th/7th locals are item_type / item_sub_type")
    check(block:find("level, min_level, item_type, item_sub_type", 1, true) ~= nil,
        "L4 contract: the wrapper returns the normalised shape")
    check(block:find("min_level, class, subclass", 1, true) == nil,
        "L4 contract: the old 'class, subclass' locals are gone from the wrapper")

    -- The rogue's only consumer reads the same two positions under the same names.
    local rogue_f = assert(io.open(ROOT .. "classes/rogue.lua", "r"))
    local rogue_src = rogue_f:read("*a")
    rogue_f:close()
    local rogue_start = rogue_src:find("local function item_subclass", 1, true)
    local rogue_stop = rogue_src:find("\nend", rogue_start or 1, true)
    check(rogue_start ~= nil and rogue_stop ~= nil,
        "L4 contract: the rogue's item_subclass helper exists")
    local rogue_block = rogue_src:sub(rogue_start or 1, (rogue_stop or 1) + 3)
    check(rogue_block:find("item_type, item_sub_type = api.GetItemInfo", 1, true) ~= nil,
        "L4 contract: the rogue reads the normalised 6th/7th positions")
    check(rogue_block:find("_, _, _, _, _, class, subclass", 1, true) == nil,
        "L4 contract: the old 'class, subclass' read is gone from the rogue")
end

--=========================================================================================
-- 13c-ter. The totem-slot citation (L2): the client's own constants, per branch
--=========================================================================================
-- The publish-gate re-audit's L2: the compat.lua totem comment cited
-- "Blizzard_FrameXMLBase/Constants.lua:239-244" for the 1=Fire / 2=Earth / 3=Water /
-- 4=Air slot map. The real per-branch truth (verified against the reference repo,
-- bench/perclient_api_truth_2026-10-20.md):
--   classic-line : Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:286-289
--   origin/forever: Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:226-229
--   live          : Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:241-244
-- The un-suffixed Constants.lua does not exist on the classic-line branches at all, and
-- 239-244 is not the block on any branch.
do
    local f = assert(io.open(ROOT .. "compat.lua", "r"))
    local src = f:read("*a")
    f:close()

    local start_at = src:find("-- Totems ---", 1, true)
    local stop_at = src:find("-- Item probes", 1, true)
    check(start_at ~= nil, "L2 setup: the totem section exists in compat.lua")
    check(stop_at ~= nil and start_at ~= nil and stop_at > start_at,
        "L2 setup: the totem section is bounded by the next section")
    local block = src:sub(start_at or 1, (stop_at or 1) - 1)

    local comment_text = {}
    for line in (block .. "\n"):gmatch("([^\n]*)\n") do
        local stripped = line:match("^%s*(%-%-.*)$")
        if stripped then
            comment_text[#comment_text + 1] = stripped
        end
    end
    comment_text = table.concat(comment_text, "\n")

    check(comment_text:find("Classic/Constants.lua:286-289", 1, true) ~= nil,
        "L2 citation: the classic-line totem constants cite Classic/Constants.lua:286-289")
    check(comment_text:find("Blizzard_FrameXMLBase/Constants.lua:226-229", 1, true) ~= nil,
        "L2 citation: the forever totem constants cite Constants.lua:226-229")
    check(comment_text:find("Blizzard_FrameXMLBase/Constants.lua:241-244", 1, true) ~= nil,
        "L2 citation: the live totem constants cite Constants.lua:241-244")
    check(comment_text:find("Constants.lua:239-244", 1, true) == nil,
        "L2 citation: the wrong 239-244 citation is gone")
    -- The slot constants are EVIDENCE, never a runtime dependency: the addon hard-codes
    -- 1/2/3/4, so the comment must say so (otherwise a reader assumes the globals exist).
    check(comment_text:find("hard-codes", 1, true) ~= nil,
        "L2 citation: the comment says the slot numbers are hard-coded, not read")
end

--=========================================================================================
-- 13d. S1 lust-consumer reads: scan_player_aura over the Bloodlust shape
--=========================================================================================
-- The shaman S1 lust badge (classes/shaman.lua update_lust_state) depends on exactly
-- two compat behaviours: the player-aura scan reports a matching lust aura's
-- remaining time (nil, nil on a miss), and an absent row above the buff never
-- truncates the walk (the R2 rule at the scan level). The ids themselves
-- (2825 / 32182) stay owned by the class module - this pins the probe shape only.
do
    local sb = build()
    local api = sb.st.api
    local function lust_predicate(spell_id, name)
        return (spell_id and (spell_id == 2825 or spell_id == 32182))
            or name == "Bloodlust" or name == "Heroism"
    end

    sb.clock = 100
    sb.aura_rows = {
        { name = "Bloodlust", spell_id = 2825, expiration = 130 },
    }
    local remaining = api.scan_player_aura(lust_predicate)
    eq(remaining, 30, "S1 scan: a live Bloodlust reads its remaining time")

    sb.aura_rows = {}
    local miss_remaining, miss_stacks = api.scan_player_aura(lust_predicate)
    eq(miss_remaining, nil, "S1 scan: a miss reads nil remaining")
    eq(miss_stacks, nil, "S1 scan: a miss reads nil stacks")

    -- A nil row above the buff does not truncate the walk.
    sb.aura_rows = {
        [2] = { name = "Heroism", spell_id = 32182, expiration = 140 },
    }
    remaining = api.scan_player_aura(lust_predicate)
    eq(remaining, 40, "S1 scan: the walk continues past an absent row")
end

--=========================================================================================
-- 13e. X1 trinket-ICD hook: the combat-log getter probe pair
--=========================================================================================
-- The shared trinket row (hud.lua) arms its reversed ICD swipe from
-- SPELL_AURA_APPLIED through api.CombatLogGetCurrentEventInfo, and stays silent
-- where the classic combat log does not exist (the Mainline-code shape). This
-- pins the probe pair only: the payload passes through where present, nil where
-- absent - the HUD-level absent behaviour is pinned in hud_state section 11.
do
    local sb = build({ combat_log = true })
    sb.combat_log_payload = function()
        return 1, "SPELL_AURA_APPLIED", false, "Player-1", "Player", 0, 0,
            "Player-1", "Player", 0, 0, 34775, "Lust for Battle", 1, "BUFF"
    end
    local timestamp, subevent = sb.st.api.CombatLogGetCurrentEventInfo()
    eq(timestamp, 1, "CLEU control: the payload passes through")
    eq(subevent, "SPELL_AURA_APPLIED", "CLEU control: the subevent passes through")

    local bare = build()
    eq(bare.st.api.CombatLogGetCurrentEventInfo(), nil,
        "CLEU absent: no combat log reads as no payload")
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
-- 15. Name-vs-id helper (operator 2026-10-19): TBC by NAME, Era by id
--=========================================================================================
do
    -- TBC Anniversary: the helper returns the NAME (never a bare id).
    local tbc = build({ project = 5, interface = 20506 })
    check(type(tbc.st.api.get_spell_query) == "function",
        "name-vs-id: the shared helper exists")
    eq(tbc.st.api.get_spell_query("Bloodlust", 2825), "Bloodlust",
        "name-vs-id TBC: Bloodlust resolves by NAME")
    eq(tbc.st.api.get_spell_query("Kick", 107), "Kick",
        "name-vs-id TBC: Kick resolves by NAME")

    -- Era: the helper returns the numeric ID.
    local era = build({ project = 2, interface = 11509 })
    eq(era.st.api.get_spell_query("Bloodlust", 2825), 2825,
        "name-vs-id Era: Bloodlust resolves by ID")
    eq(era.st.api.get_spell_query("Kick", 107), 107,
        "name-vs-id Era: Kick resolves by ID")

    -- Non-TBC families (Wrath) follow the Era shape (id-only, never NAME-only).
    local wrath = build({ project = 11, interface = 38002 })
    eq(wrath.st.api.get_spell_query("Kick", 107), 107,
        "name-vs-id Wrath: non-TBC resolves by ID")

    -- Nil-safety: a missing name on TBC degrades to nil (unknown-hides);
    -- a missing id elsewhere degrades the same way.
    eq(tbc.st.api.get_spell_query(nil, 2825), nil,
        "name-vs-id TBC: a missing name is unknown (never a bare id)")
    eq(era.st.api.get_spell_query("Kick", nil), nil,
        "name-vs-id Era: a missing id is unknown")
end

--=========================================================================================
-- 15b. The family rank walk follows the same rule (audit F4): TBC asks the
-- client by NAME, Era by ID, and "not here" stays apart from "could not
-- answer" so a caller never latches a false negative.
--=========================================================================================
do
    -- TBC: the client indexes names, so the walk resolves through the name path.
    local tbc_walk = build({ project = 5, interface = 20506 })
    tbc_walk.spell_info[29707] = { name = "Heroic Strike" }
    tbc_walk.spell_info["Heroic Strike"] = { name = "Heroic Strike" }
    eq(tbc_walk.st.api.get_family_spell_id({47450, 30324, 29707, 25286, 78}), 29707,
        "name-vs-id TBC: the rank walk resolves through the NAME path")
    local tbc_id, tbc_state = tbc_walk.st.api.get_family_spell_id_state({47450, 30324, 29707, 25286, 78})
    eq(tbc_id, 29707, "name-vs-id TBC: the state variant resolves the same rank")
    eq(tbc_state, "resolved", "name-vs-id TBC: the state variant reports 'resolved'")

    -- Era: the same table resolves through the id path.
    local era_walk = build({ project = 2, interface = 11509 })
    era_walk.spell_info[29707] = { name = "Heroic Strike" }
    eq(era_walk.st.api.get_family_spell_id({47450, 30324, 29707, 25286, 78}), 29707,
        "name-vs-id Era: the rank walk resolves through the ID path")
    local era_id, era_state = era_walk.st.api.get_family_spell_id_state({47450, 30324, 29707, 25286, 78})
    eq(era_id, 29707, "name-vs-id Era: the state variant resolves the same rank")
    eq(era_state, "resolved", "name-vs-id Era: the state variant reports 'resolved'")

    -- "Not here" (the client answered: no such spell) and "could not answer" (the
    -- client could not be read) must stay apart - the second is retryable, the
    -- first is final.
    local absent_id, absent_state = era_walk.st.api.get_family_spell_id_state({48480, 47450})
    eq(absent_id, nil, "name-vs-id: a rank the client does not have resolves nil")
    eq(absent_state, "absent", "name-vs-id: a rank the client does not have reports 'absent'")

    local unreadable = build({ project = 5, interface = 20506 })
    unreadable.spell_info_throws = true
    local unknown_id, unknown_state = unreadable.st.api.get_family_spell_id_state({29707, 78})
    eq(unknown_id, nil, "name-vs-id: an unreadable client resolves no rank")
    eq(unknown_state, "unresolved", "name-vs-id: an unreadable client reports 'unresolved'")
    eq(unreadable.st.api.get_family_spell_id({29707, 78}), nil,
        "name-vs-id: an unreadable client never claims a rank")

    -- A restricted (secret) spell name is never used as a query and never
    -- compared: the walk reports "unresolved" and claims no rank.
    local restricted = build({ project = 5, interface = 20506 })
    restricted.spell_info[29707] = { name = SECRET_SPELL_NAME }
    local restricted_id, restricted_state = restricted.st.api.get_family_spell_id_state({29707, 78})
    eq(restricted_id, nil, "name-vs-id: a restricted spell name resolves no rank")
    eq(restricted_state, "unresolved", "name-vs-id: a restricted spell name reports 'unresolved'")
    local leaked = false
    for i = 1, #(restricted.spell_queries or {}) do
        if restricted.spell_queries[i] == SECRET_SPELL_NAME then leaked = true end
    end
    check(not leaked, "name-vs-id: a restricted spell name never leaves as a query")
end

--=========================================================================================
-- 16. R11: movement probes (hunter weave-prog): GetUnitSpeed + IsPlayerMoving
--=========================================================================================
do
    -- Absent probes (every profile by default): unknown, never a reading.
    local sb = build()
    eq(sb.st.api.GetUnitSpeed("player"), nil, "R11 absent: GetUnitSpeed is unknown (nil)")
    eq(sb.st.api.IsPlayerMoving(), nil, "R11 absent: IsPlayerMoving is unknown (nil)")

    -- Retail profile: also absent (no probe installed there either).
    local rsb = build({ retail = true, project = 1, interface = 120100 })
    eq(rsb.st.api.GetUnitSpeed("player"), nil, "R11 retail absent: GetUnitSpeed is unknown")
    eq(rsb.st.api.IsPlayerMoving(), nil, "R11 retail absent: IsPlayerMoving is unknown")
end

do
    -- Holder tables (declared before the build: an opts closure cannot see the
    -- `local sb` being assigned, so it reads these instead).
    local speeds = { player = 6, target = nil }
    local motion = { moving = true }
    local sb = build({
        unit_speed = function(unit) return speeds[unit] end,
        player_moving = function() return motion.moving end,
    })
    local api = sb.st.api

    eq(api.GetUnitSpeed("player"), 6, "R11 control: current speed passes through")
    eq(api.IsPlayerMoving(), true, "R11 control: moving passes through")
    speeds.player = 0
    motion.moving = false
    eq(api.GetUnitSpeed("player"), 0, "R11 control: standing still reads 0")
    eq(api.IsPlayerMoving(), false, "R11 control: still reads false")
    speeds.target = 3
    eq(api.GetUnitSpeed("target"), 3, "R11 control: target speed reads per unit")
    speeds.target = nil
    eq(api.GetUnitSpeed("target"), nil, "R11 control: no target reading is unknown")

    -- Secret regime: restricted readings degrade to unknown, never a comparison.
    -- (6 is the control speed: the suite flags 7 as SECRET_CD_ENABLED.)
    speeds.player = SECRET_SPEED
    eq(api.GetUnitSpeed("player"), nil, "R11 secret: speed reports unknown (nil)")
    motion.moving = SECRET_RANGE_BOOL
    eq(api.IsPlayerMoving(), nil, "R11 secret: motion reports unknown (nil)")

    -- Degenerate readings: NaN / negative / infinite / non-number speed is unknown.
    speeds.player = 0 / 0
    eq(api.GetUnitSpeed("player"), nil, "R11 degenerate: NaN speed is unknown")
    speeds.player = -1
    eq(api.GetUnitSpeed("player"), nil, "R11 degenerate: negative speed is unknown")
    speeds.player = math.huge
    eq(api.GetUnitSpeed("player"), nil, "R11 degenerate: infinite speed is unknown")
    speeds.player = "fast"
    eq(api.GetUnitSpeed("player"), nil, "R11 degenerate: non-number speed is unknown")

    -- A non-boolean motion reading is unknown.
    motion.moving = "yes"
    eq(api.IsPlayerMoving(), nil, "R11 degenerate: non-boolean motion is unknown")
end

do
    -- Throwing probes degrade to unknown instead of erroring.
    local sb = build({
        unit_speed = function() error("restricted") end,
        player_moving = function() error("restricted") end,
    })
    eq(sb.st.api.GetUnitSpeed("player"), nil, "R11 throwing: speed is unknown")
    eq(sb.st.api.IsPlayerMoving(), nil, "R11 throwing: motion is unknown")
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
