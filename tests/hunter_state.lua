-- tests/hunter_state.lua: offline tests for the hunter module (classes/hunter.lua) over the
-- real compat.lua + utils.lua in a sandbox.
-- Pins post_init flag initialisation, the Raptor Strike and Steady Shot queue detection
-- and their option gates, the spellcast clear paths, the pre-init guards, the
-- on-next-attack colour matrix, the config/option wiring of the new keys, the
-- hunter_ui hook wiring (post_init/on_bar_update dispatch), the Multi-Shot cast-grace
-- classifier, and the hunter_ui sandbox (frame creation, off-gates skipping their
-- scans/API reads, deferred creation under lockdown, inert ranged hands).
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
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end
-- Compares the colour the module handed to the bar with a 0-255 db table, through the
-- same convert_color scaling main.lua applies.
local function colour_eq(vertex, db_table, label)
    checks = checks + 1
    if type(vertex) ~= "table" then
        failures = failures + 1
        print("FAIL  " .. label .. "  (no vertex colour was applied)")
        return
    end
    near(vertex[1], db_table[1] / 255, label .. " (red)")
    near(vertex[2], db_table[2] / 255, label .. " (green)")
    near(vertex[3], db_table[3] / 255, label .. " (blue)")
    near(vertex[4], db_table[4], label .. " (alpha)")
end

-- The Raptor Strike ranks in classes/hunter.lua, as of this revision. Used to size the
-- IsCurrentSpell probe count so the option gate can be measured without pinning a
-- specific probe order (pairs() order is not deterministic).
-- Eleven since the APL UTILITY lane (2026-10-20): the rank 8 the SoD and Forever
-- clients carry (14266) joined the table, so the queue probe covers it too.
local RAPTOR_RANKS = 11

-- The Steady Shot ranks in classes/hunter.lua, same purpose.
local STEADY_RANKS = 4

-- The Era Aimed Shot ranks in classes/hunter.lua (the six verified vanilla ranks).
local AIMED_RANKS = 6

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- One throwaway client profile per call: a fresh environment (a metatable over _G, so an
-- absent global is shadowed with nil rather than removed), the real compat.lua + utils.lua
-- loaded into it, then classes/hunter.lua on top.
local function build(opts)
    opts = opts or {}

    -- Mutable fixture state, shared with the stub closures.
    local sb = {
        clock = 0, -- suite time behind GetTime (the compat clock axis)
        player_auras = {}, -- [{ name, id, count, duration, expiration }] for "player"
        target_auras = nil, -- [{ name, id, count, duration, expiration, secret }] for "target"
        target_aura_queries = 0, -- every HARMFUL row read on the target
        current_spell = opts.current_spell, -- the only id IsCurrentSpell answers true for
        is_current_spell_calls = 0,
        is_current_spell_tokens = {}, -- every token IsCurrentSpell was probed with
        is_spell_known_tokens = {}, -- every token IsSpellKnown was probed with
        channel_spell = opts.channel_spell, -- the spell id UnitChannelInfo reports, or nil
        channel_calls = 0,
        bar_color_calls = 0,
        set_vertex_calls = 0,
        last_hand = nil,
        vertex = nil,
        -- Every GetSpellInfo query, in order (the name-vs-id direction proof).
        spell_queries = {},
        get_spell_info_calls = 0,
        -- The spell ids this client knows (they answer under their synthetic
        -- "Spell <id>" name, like a real client answers under its own name).
        known = opts.known or {},
        -- A client that cannot answer: its spell reads come back RESTRICTED (secret),
        -- so the resolver reports "unresolved" (retryable) instead of "absent"
        -- (final). The marker is the only value the secret check answers for.
        secret_spell_info = false,
        secret_marker = "<secret spell data>",
        -- The resolver counters (audit F4: the class resolves through the state API,
        -- never through the plain two-valued resolver).
        get_family_spell_id_calls = 0,
        get_family_spell_id_state_calls = 0,
    }

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = opts.project or 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    -- Suite clock + player HELPFUL auras (R4 lust-gate pins drive gather through
    -- the real compat scan; nothing else here reads them) and the target's
    -- HARMFUL debuffs (the Serpent Sting target scan). A debuff entry marked
    -- secret answers with the restricted marker, which compat's whole-entry
    -- degrade turns into an absent row (the R2 shape: a hidden row, not a
    -- truncated list).
    env.GetTime = function() return sb.clock end
    env.UnitAura = function(unit, index, filter)
        if unit == "player" and filter == "HELPFUL" then
            local entry = sb.player_auras[index]
            if not entry then return nil end
            return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
                nil, nil, nil, entry.id
        end
        if unit == "target" and filter == "HARMFUL" then
            sb.target_aura_queries = sb.target_aura_queries + 1
            local entry = sb.target_auras and sb.target_auras[index]
            if not entry then return nil end
            if entry.secret then return sb.secret_marker end
            return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
                nil, nil, nil, entry.id
        end
        return nil
    end
    -- Minimal client spell data: the reference Multi-Shot ranks resolve their localized
    -- name (get_cast_grace's name fallback); everything else is unknown to this fixture.
    -- Every query is recorded (the name-vs-id direction proof), and the client's shape
    -- is opt-in: opts.GetSpellInfo replaces the answers, opts.known adds spell ids
    -- under their synthetic "Spell <id>" names, opts.name_only_client builds the TBC
    -- client (names only, the C_Spell bridge carries the id -> name mapping) and the
    -- restricted client answers every read with a secret value (so the resolver
    -- reports "unresolved" - retryable - instead of "absent" - final).
    local name_only_client = opts.name_only_client == true
    env.GetSpellInfo = function(query)
        sb.get_spell_info_calls = sb.get_spell_info_calls + 1
        sb.spell_queries[#sb.spell_queries + 1] = query
        if sb.secret_spell_info then
            return sb.secret_marker
        end
        if opts.GetSpellInfo then
            return opts.GetSpellInfo(query)
        end
        if type(query) == "string" then
            -- The client's own name for a known spell answers too: a client that named
            -- a spell answers to that name (the TBC name path).
            local back = query:match("^Spell (%d+)$")
            local back_id = back and tonumber(back)
            if back_id and sb.known[back_id] then
                return query, nil, "icon", 0, 0, 0, back_id
            end
            return nil
        end
        if name_only_client then
            -- The TBC client indexes names only: an id query finds nothing.
            return nil
        end
        if sb.known[query] then
            return "Spell " .. tostring(query), nil, "icon", 0, 0, 0, query
        end
        if query == 2643 or query == 27021 then
            return "Multi-Shot", nil, "icon", 0, 0, 0, query
        end
        return nil
    end
    if name_only_client then
        -- The C_Spell namespace carries the id -> name mapping (the shape the compat
        -- lane verified on the client source: C_Spell.GetSpellInfo takes an id and
        -- answers with that spell's data).
        env.C_Spell = {
            GetSpellInfo = function(id)
                if sb.known[id] then
                    return { name = "Spell " .. tostring(id), spellID = id }
                end
                return nil
            end,
        }
    end
    -- The restricted-read marker: only the marker value is "secret", so every other
    -- read (numbers, booleans, names) keeps its normal meaning.
    env.issecretvalue = function(value)
        return value == sb.secret_marker
    end
    env.IsCurrentSpell = function(id)
        sb.is_current_spell_calls = sb.is_current_spell_calls + 1
        sb.is_current_spell_tokens[#sb.is_current_spell_tokens + 1] = id
        return id == sb.current_spell
    end
    -- Spell knowledge for the Wrath spec detector (Chimera = MM, Explosive = SV)
    -- and the SoD rune detector: opts.known_spells maps id -> true, defaulting to
    -- "nothing learned" so existing fixtures resolve nothing new. A function
    -- form records the probed token (used by the TBC name-resolution pins).
    env.IsSpellKnown = function(id)
        sb.is_spell_known_tokens[#sb.is_spell_known_tokens + 1] = id
        local known = opts.known_spells
        if type(known) == "function" then
            return known(id)
        end
        return known ~= nil and known[id] == true
    end
    -- UnitChannelInfo returns the spell id as the 8th value and has no castID (unlike
    -- UnitCastingInfo). nil models "not channelling", the classic non-channel payload.
    env.UnitChannelInfo = function()
        sb.channel_calls = sb.channel_calls + 1
        if sb.channel_spell == nil then
            return nil
        end
        return "Steady Shot", "", "icon", 1000, 2000, false, false, sb.channel_spell
    end

    -- Opt-in mana fixture for the OOM Viper probe (compat reads UnitPower through
    -- _G; absent reads the unknown 0/0 shape, which the probe maps to nil).
    if opts.mana ~= nil then
        env.UnitPower = function() return opts.mana.cur end
        env.UnitPowerMax = function() return opts.mana.max end
    end

    -- H1/H2 scripted reads: unit tokens for the target warning (H1) and a scripted
    -- live-cast payload for the clip sampler (H2, a function returning the 9-tuple or
    -- nil per call, so multi-frame casts can be scripted). Absent by default, which is
    -- the "client answers nothing" shape.
    if opts.unit_exists ~= nil then
        env.UnitExists = opts.unit_exists
    end
    if opts.unit_is_unit ~= nil then
        env.UnitIsUnit = opts.unit_is_unit
    end
    if opts.live_cast ~= nil then
        local scripted = opts.live_cast
        env.UnitCastingInfo = function(unit)
            if unit ~= "player" then
                return nil
            end
            if type(scripted) == "function" then
                return scripted()
            end
            return nil
        end
    end

    -- Opt-in state-API spies (absent = the client's answerless shape, as before).
    if opts.GetSpellCooldown ~= nil then
        env.GetSpellCooldown = opts.GetSpellCooldown
    end
    if opts.IsAutoRepeatSpell ~= nil then
        env.IsAutoRepeatSpell = opts.IsAutoRepeatSpell
    end
    if opts.IsSpellInRange ~= nil then
        env.IsSpellInRange = opts.IsSpellInRange
    end
    -- Opt-in movement spies for the weave-prog lane (absent = the client's
    -- answerless shape: compat reports nil, the prog holds).
    if opts.GetUnitSpeed ~= nil then
        env.GetUnitSpeed = opts.GetUnitSpeed
    end
    if opts.IsPlayerMoving ~= nil then
        env.IsPlayerMoving = opts.IsPlayerMoving
    end

    -- compat.lua reads several legacy globals through _G (annotation-safe on
    -- Mainline-code clients); mirror EVERY sandbox stub for the duration of its load,
    -- then restore _G exactly. Keys absent from _G are tracked by name: assigning nil
    -- into the mirrored table stores nothing (pairs skips it), so without the name
    -- list a stub for an absent global would leak permanently and a later sandbox
    -- without that stub would read a foreign function instead of nil.
    local mirrored = {}
    local mirrored_names = {}
    for name, value in pairs(env) do
        mirrored[name] = rawget(_G, name)
        mirrored_names[#mirrored_names + 1] = name
        _G[name] = value
    end

    local st = {}
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)

    for _, name in ipairs(mirrored_names) do
        _G[name] = mirrored[name]
    end

    -- The addon object: only the surface classes/hunter.lua touches.
    local ST = { HUNTER = {} }
    -- The real HUNTER defaults (config_presets.lua), so a wrong colour is a module bug
    -- and not a fixture bug. The Steady Shot queue colour ships off, mirroring the real
    -- defaults: a test must opt in before the steady paths do anything.
    local class_db = {
        enable_raptor_strike_color = true,
        raptor_strike_color = { 207, 58, 83, 1.0 },
        enable_steady_shot_color = false,
        steady_shot_color = { 211, 145, 12, 1.0 },
    }
    local visuals = {
        bar = {
            SetVertexColor = function(_, r, g, b, a)
                sb.set_vertex_calls = sb.set_vertex_calls + 1
                sb.vertex = { r, g, b, a }
            end,
        },
    }
    ST.interfaces_are_initialised = false
    ST.get_class_table = function() return class_db end
    -- The game client answers this (main.lua); the sandbox default is "every hand
    -- enabled", so a test opts out explicitly (the H2 sampler reads the gate).
    ST.bar_is_enabled = function(_, hand) return true end
    ST.get_visuals_frame = function()
        if opts.no_visuals then return nil end
        return visuals
    end
    -- main.lua declares convert_color as a method (ST:convert_color), so the leading self
    -- must be swallowed here too.
    ST.convert_color = function(_, t, new_alpha)
        local r, g, b, a = unpack(t)
        a = new_alpha or a
        return r / 255, g / 255, b / 255, a
    end
    -- bars.lua dispatches the class hook as ST[player_class].set_bar_color(ST, hand);
    -- mirror that, recording every dispatch.
    ST.set_bar_color = function(self, hand)
        sb.bar_color_calls = sb.bar_color_calls + 1
        sb.last_hand = hand
        return ST.HUNTER.set_bar_color(self, hand)
    end

    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        end
        return {}
    end

    local utils = assert(loadfile(ROOT .. "utils.lua"))
    setfenv(utils, env)
    utils("SwedgeTimer", st)

    -- Count resolver calls: the module calls api.get_family_spell_id_state through the
    -- api table, so wrapping the table entry after load is enough. The plain resolver
    -- is counted too: the class must not use it any more (audit F4).
    local real_resolver = st.api.get_family_spell_id
    local real_state_resolver = st.api.get_family_spell_id_state
    st.api.get_family_spell_id = function(ids)
        sb.get_family_spell_id_calls = sb.get_family_spell_id_calls + 1
        return real_resolver(ids)
    end
    st.api.get_family_spell_id_state = function(ids)
        sb.get_family_spell_id_state_calls = sb.get_family_spell_id_state_calls + 1
        return real_state_resolver(ids)
    end

    -- The real TOC order: the pure hunter_window module loads before the class module,
    -- which resolves its pure maths once at load time (the phase-1 foundation).
    local hunter_window_mod = assert(loadfile(ROOT .. "hunter_window.lua"))
    setfenv(hunter_window_mod, env)
    hunter_window_mod("SwedgeTimer", st)

    -- Extra namespace entries a test wants in place before the class module loads
    -- (e.g. a recording st.hunter_ui stand-in, exactly as the real TOC provides it).
    if opts.st_extras then
        for key, value in pairs(opts.st_extras) do
            st[key] = value
        end
    end

    local mod = assert(loadfile(ROOT .. "classes/hunter.lua"))
    setfenv(mod, env)
    mod("SwedgeTimer", st)
    -- classes/hunter.lua registers its body as a loader (operator order 2026-10-21:
    -- only the selected class executes). Activate it here, right after its file
    -- loads - the same load-time position its body occupied before the wrapper.
    assert(type(st.class_loaders) == "table"
        and type(st.class_loaders["HUNTER"]) == "function",
        "classes/hunter.lua registers the HUNTER loader")
    st.class_loaders["HUNTER"]()

    sb.st = st
    sb.ST = ST
    sb.class_db = class_db
    return sb
end

--=========================================================================================
-- 0) The module loads and exposes every hook
--=========================================================================================
local base = build()
check(type(base.ST.HUNTER) == "table", "classes/hunter.lua loads and defines ST.HUNTER")
for _, hook in ipairs({
    "post_init", "on_spellcast_failed_quiet", "on_spellcast_succeeded",
    "on_current_spell_cast_changed", "on_combat_exit", "set_bar_color",
    "on_bar_update", "get_cast_grace", "get_target_warning",
    "track_live_cast", "record_shot_sample", "reset_shot_log",
    "get_readiness_window", "get_iss_remaining", "is_viper_known",
    "is_viper_active", "get_mana_fraction", "get_oom_viper_prompt",
    "get_lnl_remaining", "get_lnl_prompt",
    "note_trap_cast", "update_trap", "get_trap_remaining",
    "clever_traps_mult", "get_trap_active_duration",
    "practice_cast_time", "practice_shot_label", "practice_shot_spell_id",
    "get_practice_scenario_key", "practice_new_session", "practice_begin_session",
    "practice_end_session", "practice_cast", "practice_tick", "practice_status",
    "practice_fight_elapsed", "practice_shift_pause",
}) do
    check(type(base.ST.HUNTER[hook]) == "function", "HUNTER." .. hook .. " is defined")
end

--=========================================================================================
-- 1) post_init creates the flag before any spellcast event can read it
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    eq(ST.raptor_strike_queued, nil, "the queue flag does not exist before post_init")
    eq(ST.steady_shot_queued, nil, "the steady queue flag does not exist before post_init")
    check(type(ST.HUNTER.post_init) == "function", "post_init is the flag initialiser")

    local ok, err = pcall(ST.HUNTER.post_init, ST)
    check(ok, "post_init runs in the sandbox (" .. tostring(err) .. ")")
    eq(ST.raptor_strike_queued, false, "post_init initialises raptor_strike_queued to false")
    eq(ST.steady_shot_queued, false, "post_init initialises steady_shot_queued to false")

    -- Idempotent, and it must also clear a flag left over from a previous session.
    ST.raptor_strike_queued = true
    ST.steady_shot_queued = true
    ST.HUNTER.post_init(ST)
    eq(ST.raptor_strike_queued, false, "post_init clears a stale queue flag")
    eq(ST.steady_shot_queued, false, "post_init clears a stale steady queue flag")
    ST.HUNTER.post_init(ST)
    eq(ST.raptor_strike_queued, false, "post_init is idempotent")
    eq(ST.steady_shot_queued, false, "post_init is idempotent for the steady flag")
end

--=========================================================================================
-- 2) The spellcast hooks clear the queue they own, and nothing else
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.raptor_strike_queued = true
    sb.vertex = nil

    local ok, err = pcall(ST.HUNTER.on_spellcast_succeeded, ST, "target", nil, 48996)
    check(ok, "a landed WotLK Raptor Strike does not error (" .. tostring(err) .. ")")
    eq(ST.raptor_strike_queued, false, "a landed Raptor Strike clears raptor_strike_queued")
    eq(sb.bar_color_calls, 1, "a landed Raptor Strike recolours once")
    eq(sb.last_hand, "mainhand", "the recolour targets the mainhand bar")
    -- The flag is cleared *before* the recolour, so the queue colour is handed straight
    -- back to the default: clearing a queue must not leave the RS colour on the bar.
    eq(sb.set_vertex_calls, 0, "clearing the queue hands the bar back to the default colour")

    -- Any rank of the family works, on both the landed and the failed-quiet path.
    for _, spell_id in ipairs({ 2973, 14261, 27014, 48995 }) do
        ST.raptor_strike_queued = true
        sb.bar_color_calls = 0
        ST.HUNTER.on_spellcast_succeeded(ST, "target", nil, spell_id)
        eq(ST.raptor_strike_queued, false, "rank " .. spell_id .. " clears the queue on success")
        eq(sb.bar_color_calls, 1, "rank " .. spell_id .. " recolours once on success")
    end

    ST.raptor_strike_queued = true
    sb.bar_color_calls = 0
    sb.vertex = nil
    ST.HUNTER.on_spellcast_failed_quiet(ST, "target", nil, 14260)
    eq(ST.raptor_strike_queued, false, "a failed Raptor Strike clears raptor_strike_queued")
    eq(sb.bar_color_calls, 1, "a failed Raptor Strike recolours once")
    eq(sb.set_vertex_calls, 0, "a failed cast hands the bar back to the default colour")

    -- A foreign spell id must change nothing.
    ST.raptor_strike_queued = true
    sb.bar_color_calls = 0
    sb.vertex = nil
    ST.HUNTER.on_spellcast_succeeded(ST, "target", "cast-9", 12345)
    eq(ST.raptor_strike_queued, true, "an unrelated spell id leaves raptor_strike_queued alone")
    eq(sb.bar_color_calls, 0, "an unrelated spell id does not recolour")
    eq(sb.vertex, nil, "an unrelated spell id does not touch the vertex colour")

    ST.HUNTER.on_spellcast_failed_quiet(ST, "target", nil, 12345)
    eq(ST.raptor_strike_queued, true, "an unrelated failed spell id leaves the flag alone")
    eq(sb.bar_color_calls, 0, "an unrelated failed spell id does not recolour")

    -- A nil spell id (interrupted cast with no id) must be ignored, not crash.
    local ok2, err2 = pcall(ST.HUNTER.on_spellcast_failed_quiet, ST, "target", nil, nil)
    check(ok2, "a nil spell id does not error (" .. tostring(err2) .. ")")
    eq(ST.raptor_strike_queued, true, "a nil spell id leaves the flag alone")
    eq(sb.bar_color_calls, 0, "a nil spell id does not recolour")
end

--=========================================================================================
-- 3) Pre-init safety: every hook runs with no init and no visuals frame
--=========================================================================================
-- The real pre-init state: nothing queued yet, so no hook may reach for the bar texture
-- that does not exist yet. (A queued ability can only exist after init - UNIT_SPELLCAST_*
-- only arrives in combat, and bars.lua's own dispatcher needs the frame too.)
do
    local sb = build({ no_visuals = true })
    local ST = sb.ST
    ST.interfaces_are_initialised = false
    -- post_init has not run: the flag is still nil, which is the worst case.
    eq(ST.raptor_strike_queued, nil, "the pre-init sandbox starts with no queue flag")

    local hooks = {
        -- A real cast guid, never nil: # on a table with an embedded nil is
        -- implementation-defined in Lua 5.1, so the arg lists stay hole-free.
        { "on_spellcast_succeeded", { "target", "cast-1", 48996 } },
        { "on_spellcast_failed_quiet", { "target", "cast-1", 48996 } },
        { "on_current_spell_cast_changed", { false } },
        { "set_bar_color", { "mainhand" } },
        { "on_combat_exit", {} },
    }
    for _, entry in ipairs(hooks) do
        for pass = 1, 2 do
            local ok, err = pcall(ST.HUNTER[entry[1]], ST, unpack(entry[2]))
            check(ok, "pre-init " .. entry[1] .. " (pass " .. pass .. ") does not error ("
                .. tostring(err) .. ")")
        end
    end

    -- Nothing queued means nothing painted: the guards fire before any frame access.
    eq(sb.bar_color_calls, 4, "only the two spellcast clear paths dispatch a recolour")
    eq(sb.set_vertex_calls, 0, "a pre-init dispatch with nothing queued paints nothing")
    eq(ST.raptor_strike_queued, false, "combat exit leaves the flag down pre-init")

    -- The colour option off is the other pre-init path: an immediate return, no probing.
    sb.class_db.enable_raptor_strike_color = false
    sb.is_current_spell_calls = 0
    local ok2, err2 = pcall(ST.HUNTER.on_current_spell_cast_changed, ST, false)
    check(ok2, "pre-init hook with the colour option off does not error (" .. tostring(err2) .. ")")
    eq(sb.is_current_spell_calls, 0, "pre-init hook with the option off probes nothing")

    -- A dirty flag entering combat exit pre-init is cleared without any frame access.
    ST.raptor_strike_queued = true
    local ok3, err3 = pcall(ST.HUNTER.on_combat_exit, ST)
    check(ok3, "pre-init combat exit with a dirty flag does not error (" .. tostring(err3) .. ")")
    eq(ST.raptor_strike_queued, false, "pre-init combat exit clears raptor_strike_queued")

    -- An unrelated spell id pre-init changes nothing.
    local recolours_before = sb.bar_color_calls
    ST.HUNTER.on_spellcast_succeeded(ST, "target", nil, 12345)
    ST.HUNTER.on_spellcast_failed_quiet(ST, "target", nil, 12345)
    eq(sb.bar_color_calls, recolours_before, "an unrelated spell id does not recolour pre-init")
    eq(sb.set_vertex_calls, 0, "no pre-init path ever painted the bar")

    -- The Steady Shot paths pre-init: option on, nothing queued, no visuals frame.
    -- Flags can only be nil or false here, the worst real case before bars.lua builds
    -- the frames.
    sb.class_db.enable_steady_shot_color = true
    sb.class_db.enable_raptor_strike_color = false
    sb.current_spell = nil
    sb.channel_spell = nil
    local steady_hooks = {
        { "on_spellcast_succeeded", { "target", "cast-2", 49052 } },
        { "on_spellcast_failed_quiet", { "target", "cast-2", 49052 } },
        { "on_current_spell_cast_changed", { false } },
        { "set_bar_color", { "mainhand" } },
        { "on_combat_exit", {} },
    }
    for _, entry in ipairs(steady_hooks) do
        local ok4, err4 = pcall(ST.HUNTER[entry[1]], ST, unpack(entry[2]))
        check(ok4, "pre-init steady " .. entry[1] .. " does not error ("
            .. tostring(err4) .. ")")
    end
    eq(ST.steady_shot_queued, false, "every pre-init steady path leaves the flag down")
    eq(sb.set_vertex_calls, 0, "no pre-init steady path ever painted the bar")

    -- A dirty steady flag entering combat exit pre-init is cleared without frame access.
    ST.steady_shot_queued = true
    local ok5, err5 = pcall(ST.HUNTER.on_combat_exit, ST)
    check(ok5, "pre-init steady combat exit does not error (" .. tostring(err5) .. ")")
    eq(ST.steady_shot_queued, false, "pre-init combat exit clears steady_shot_queued")
end

--=========================================================================================
-- 4) Queue detection and the enable_raptor_strike_color gate
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.raptor_strike_queued = false

    -- Option on, nothing queued: every rank is probed and the flag stays down.
    local ok, err = pcall(ST.HUNTER.on_current_spell_cast_changed, ST, false)
    check(ok, "the queue probe does not error (" .. tostring(err) .. ")")
    eq(sb.is_current_spell_calls, RAPTOR_RANKS, "an empty cast probes every Raptor Strike rank")
    eq(ST.raptor_strike_queued, false, "an empty cast leaves the queue flag down")
    eq(sb.bar_color_calls, 0, "an empty cast does not recolour")

    -- Option on, a Raptor Strike rank queued: the flag goes up and the bar is repainted.
    sb.current_spell = 48996
    sb.is_current_spell_calls = 0
    sb.vertex = nil
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(ST.raptor_strike_queued, true, "a queued Raptor Strike sets raptor_strike_queued")
    eq(sb.bar_color_calls, 1, "a queued Raptor Strike recolours once")
    eq(sb.last_hand, "mainhand", "queuing Raptor Strike recolours the mainhand bar")
    colour_eq(sb.vertex, sb.class_db.raptor_strike_color, "a queued Raptor Strike paints the RS colour")
    check(sb.is_current_spell_calls >= 1, "the probe ran against the rank table")

    -- Any rank of the family is detected, including the vanilla rank.
    sb.current_spell = 2973
    ST.raptor_strike_queued = false
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(ST.raptor_strike_queued, true, "the vanilla rank 2973 is detected as a queue")

    -- Queuing something else clears the flag.
    sb.current_spell = 12345
    ST.raptor_strike_queued = true
    sb.bar_color_calls = 0
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(ST.raptor_strike_queued, false, "an unrelated queued spell clears raptor_strike_queued")
    eq(sb.bar_color_calls, 0, "clearing a stale queue does not force a recolour")

    -- Option off: no probing at all, and the existing flag is left untouched.
    sb.class_db.enable_raptor_strike_color = false
    sb.current_spell = 48996
    ST.raptor_strike_queued = true
    sb.is_current_spell_calls = 0
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(sb.is_current_spell_calls, 0, "the colour option off means zero IsCurrentSpell calls")
    eq(ST.raptor_strike_queued, true, "the colour option off leaves the queue flag untouched")
    eq(sb.bar_color_calls, 0, "the colour option off does not recolour")

    -- is_cancelled is accepted and behaves like any other dispatch argument.
    sb.class_db.enable_raptor_strike_color = true
    sb.current_spell = nil
    sb.is_current_spell_calls = 0
    ST.HUNTER.on_current_spell_cast_changed(ST, true)
    eq(sb.is_current_spell_calls, RAPTOR_RANKS, "a cancelled-cast dispatch still runs the probe")
    eq(ST.raptor_strike_queued, false, "an empty cast clears a stale queue flag")
end

--=========================================================================================
-- 5) Combat exit wipes the queue
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.raptor_strike_queued = true

    local ok, err = pcall(ST.HUNTER.on_combat_exit, ST)
    check(ok, "on_combat_exit does not error (" .. tostring(err) .. ")")
    eq(ST.raptor_strike_queued, false, "combat exit clears raptor_strike_queued")
    eq(sb.bar_color_calls, 0, "combat exit does not recolour by itself")

    -- Pre-init combat exit is safe too, and idempotent.
    ST.interfaces_are_initialised = false
    ST.raptor_strike_queued = true
    local ok2, err2 = pcall(ST.HUNTER.on_combat_exit, ST)
    check(ok2, "pre-init combat exit does not error (" .. tostring(err2) .. ")")
    eq(ST.raptor_strike_queued, false, "pre-init combat exit clears raptor_strike_queued")
    ST.HUNTER.on_combat_exit(ST)
    eq(ST.raptor_strike_queued, false, "combat exit is idempotent")
end

--=========================================================================================
-- 6) The on-next-attack colour matrix
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    -- Offhand is never a class override.
    ST.raptor_strike_queued = true
    eq(ST.HUNTER.set_bar_color(ST, "offhand"), false, "the offhand bar returns false")

    -- Queued and enabled -> the configured Raptor Strike colour.
    sb.vertex = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), true, "a queued Raptor Strike claims the bar colour")
    colour_eq(sb.vertex, sb.class_db.raptor_strike_color, "a queued Raptor Strike paints the RS colour")

    -- Idle -> hand the bar back to the default behaviour.
    ST.raptor_strike_queued = false
    sb.vertex = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), false, "an idle hunter returns false (default colour)")
    eq(sb.set_vertex_calls, 1, "the idle case does not paint a vertex colour")

    -- A queued flag that only exists because post_init never ran (nil) is not a queue.
    ST.raptor_strike_queued = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), false, "a nil queue flag is treated as idle")

    -- Option off -> the queued ability is not a colour override at all.
    ST.raptor_strike_queued = true
    sb.class_db.enable_raptor_strike_color = false
    sb.vertex = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), false, "a disabled Raptor Strike colour returns false")
    eq(sb.set_vertex_calls, 1, "the disabled case does not paint a vertex colour")
end

--=========================================================================================
-- 7) Spell-table hygiene: the rank family is intact and Mortal Strike is not in it
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
    local source = f:read("*a")
    f:close()

    -- Drop comments so a source-level scan does not trip on the module's own prose.
    local function strip_comments(text)
        local out, i, n, quote = {}, 1, #text, nil
        while i <= n do
            local c = text:sub(i, i)
            local two = text:sub(i, i + 1)
            if quote then
                out[#out + 1] = c
                if c == "\\" then
                    out[#out + 1] = text:sub(i + 1, i + 1)
                    i = i + 2
                else
                    if c == quote then quote = nil end
                    i = i + 1
                end
            elseif two == "--" then
                local _, level_end = text:find("^%-%-%[(=*)%[", i)
                if level_end then
                    local _, _, level = text:find("^%-%-%[(=*)%[", i)
                    local close = "]" .. level .. "]"
                    local stop = text:find(close, level_end, true)
                    i = (stop and (stop + #close - 1)) or (n + 1)
                else
                    local nl = text:find("\n", i)
                    i = nl or (n + 1)
                end
            else
                if c == '"' or c == "'" then quote = c end
                out[#out + 1] = c
                i = i + 1
            end
        end
        return table.concat(out)
    end

    local code = strip_comments(source)
    local block = code:match("local%s+raptor_strike_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(block) == "string", "the Raptor Strike id table is found in the source")
    block = block or ""
    local ids = {}
    for n in block:gmatch("%d+") do ids[tonumber(n)] = true end
    local count = 0
    for _ in pairs(ids) do count = count + 1 end
    eq(count, RAPTOR_RANKS, "the Raptor Strike table still holds every rank")
    eq(ids[2973], true, "the table keeps the vanilla rank 2973")
    eq(ids[48996], true, "the table keeps the WotLK rank 48996")
    eq(ids[48995], true, "the table keeps 48995")
    eq(ids[27014], true, "the table keeps the TBC rank 27014")
    eq(ids[14266], true, "the table keeps the SoD/Forever rank 14266 (the APL utility lane)")
    check(ids[48996] and ids[2973], "the probe covers both ends of the rank ladder")

    -- The Steady Shot table follows the same discipline: every rank present and the
    -- module resolves it through the shared lookup helper.
    local steady_block = code:match("local%s+steady_shot_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(steady_block) == "string", "the Steady Shot id table is found in the source")
    steady_block = steady_block or ""
    local steady_ids = {}
    for n in steady_block:gmatch("%d+") do steady_ids[tonumber(n)] = true end
    local steady_count = 0
    for _ in pairs(steady_ids) do steady_count = steady_count + 1 end
    eq(steady_count, STEADY_RANKS, "the Steady Shot table holds every rank")
    eq(steady_ids[56641], true, "the table keeps 56641")
    eq(steady_ids[34120], true, "the table keeps the TBC-era 34120")
    eq(steady_ids[49051], true, "the table keeps 49051")
    eq(steady_ids[49052], true, "the table keeps the WotLK top rank 49052")

    -- The Era Aimed Shot table follows the same discipline: the six vanilla ranks,
    -- verified against classicdb.ch (19434 rank 1 through 20904 rank 6). No TBC/Wrath
    -- rank is listed: the guide's Aimed rule and slot are Era-only, so a later rank
    -- would never be read, and an id missing here simply never detects.
    local aimed_block = code:match("local%s+aimed_shot_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(aimed_block) == "string", "the Aimed Shot id table is found in the source")
    aimed_block = aimed_block or ""
    local aimed_ids = {}
    for n in aimed_block:gmatch("%d+") do aimed_ids[tonumber(n)] = true end
    local aimed_count = 0
    for _ in pairs(aimed_ids) do aimed_count = aimed_count + 1 end
    eq(aimed_count, AIMED_RANKS, "the Aimed Shot table holds the six vanilla ranks")
    eq(aimed_ids[19434], true, "the table keeps the rank-1 19434")
    eq(aimed_ids[20900], true, "the table keeps 20900 (rank 2)")
    eq(aimed_ids[20901], true, "the table keeps 20901 (rank 3)")
    eq(aimed_ids[20902], true, "the table keeps 20902 (rank 4)")
    eq(aimed_ids[20903], true, "the table keeps 20903 (rank 5)")
    eq(aimed_ids[20904], true, "the table keeps 20904 (rank 6)")
    check(aimed_ids[3034] ~= true and aimed_ids[14279] ~= true,
        "the table holds no Viper Sting id (3034/14279 are not Aimed ranks)")

    -- The TBC guide tables follow the same discipline: single-id families, so one
    -- numeric id each. A missing id would leave that guide prompt permanently inert.
    for _, entry in ipairs({
        { name = "kill_command_ids", id = 34026 },
        { name = "bestial_wrath_ids", id = 19574 },
        { name = "rapid_fire_ids", id = 3045 },
    }) do
        local entry_block = code:match("local%s+" .. entry.name .. "%s*=%s*get_tab%s*%((.-)%)")
        check(type(entry_block) == "string", "the " .. entry.name .. " table is found in the source")
        entry_block = entry_block or ""
        local entry_ids = {}
        for n in entry_block:gmatch("%d+") do entry_ids[tonumber(n)] = true end
        local entry_count = 0
        for _ in pairs(entry_ids) do entry_count = entry_count + 1 end
        eq(entry_count, 1, "the " .. entry.name .. " table holds its single id")
        eq(entry_ids[entry.id], true, "the " .. entry.name .. " table keeps " .. entry.id)
    end

    -- TBC WeakAura cross-check (docs/hunter-wa.json, wago eEJOoHci, toc 20505,
    -- CLIENT-OBSERVED): the pack's Auto/Multi castbar tracks CB.spellIDs
    -- multiShot {2643, 14288, 14289, 14290, 25294, 27021} with reset on Auto
    -- 75, and its cast tick resolves the weave names
    -- GetSpellInfo(2643/19434/34120). Every one of those ids already lives in
    -- its family table here; the WA set and the sim set (wowsims/tbc-new
    -- Steady 34120, Multi 27021, Arcane 27019) agree, and the APL UTILITY lane
    -- (2026-10-20) added the ranks the SoD/Forever/WotLK APLs cast: the Multi
    -- 49048 and the Arcane 14287 (the SoD APL i=23 and the Forever APL i=12).
    local multi_block = code:match("local%s+multi_shot_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(multi_block) == "string", "the Multi-Shot id table is found in the source")
    multi_block = multi_block or ""
    local multi_ids = {}
    for n in multi_block:gmatch("%d+") do multi_ids[tonumber(n)] = true end
    local multi_count = 0
    for _ in pairs(multi_ids) do multi_count = multi_count + 1 end
    eq(multi_count, 7, "the Multi-Shot table holds seven ranks (the WotLK rank joined)")
    for _, id in ipairs({ 2643, 14288, 14289, 14290, 25294, 27021, 49048 }) do
        eq(multi_ids[id], true, "the Multi-Shot table keeps " .. id)
    end
    -- Re-cut twice. The APL rotation lane (2026-10-20) re-scoped the scan to the
    -- arcane id TABLE itself (the ROTATION TABLE's citation of 14287 is a
    -- documentation id, not a rank-table entry). The APL UTILITY lane then ADDED
    -- 14287 to the table: the SoD and Forever clients carry that rank and their
    -- APLs cast it, so the utility layer's Arcane Shot read needs it. The TBC
    -- sim-optimal 27019 stays in the table beside it.
    local arcane_block = code:match("local%s+arcane_shot_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(arcane_block) == "string", "the Arcane Shot id table is found in the source")
    arcane_block = arcane_block or ""
    check(arcane_block:find("14287", 1, true) ~= nil,
        "the Arcane table keeps the SoD/Forever rank 14287 (the APL utility lane)")
    check(arcane_block:find("27019", 1, true) ~= nil,
        "the Arcane table keeps the sim-optimal 27019")
    check(arcane_block:find("49045", 1, true) ~= nil,
        "the Arcane table keeps the WotLK rank 49045")

    -- The Forever tables are deliberately EMPTY (UNCONFIRMED: the beta guides name
    -- Summon Hawk and Sniper Shot but publish no spell ids). An empty table
    -- resolves nothing, so both Forever prompts stay inert until an id confirms
    -- in-client - never a guessed id.
    for _, name in ipairs({ "summon_hawk_ids", "sniper_shot_ids" }) do
        local entry_block = code:match("local%s+" .. name .. "%s*=%s*get_tab%s*%((.-)%)")
        check(type(entry_block) == "string", "the " .. name .. " table is found in the source")
        entry_block = entry_block or ""
        local entry_ids = {}
        for n in entry_block:gmatch("%d+") do entry_ids[tonumber(n)] = true end
        local entry_count = 0
        for _ in pairs(entry_ids) do entry_count = entry_count + 1 end
        eq(entry_count, 0, "the " .. name .. " table holds no id (UNCONFIRMED)")
    end
    check(source:find("UNCONFIRMED: the beta guides name the spell but publish")
        ~= nil, "the Summon Hawk table carries its UNCONFIRMED provenance note")
    check(source:find("UNCONFIRMED, same rule as Summon Hawk above") ~= nil,
        "the Sniper Shot table carries its UNCONFIRMED provenance note")
end

--=========================================================================================
-- 8) Steady Shot queue detection and the enable_steady_shot_color gate
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.steady_shot_queued = false

    -- Option off (the real default): the raptor probe still runs, but the steady branch
    -- adds no IsCurrentSpell calls, never reads the channel and leaves the flag down.
    local ok, err = pcall(ST.HUNTER.on_current_spell_cast_changed, ST, false)
    check(ok, "the steady probe does not error with the option off (" .. tostring(err) .. ")")
    eq(sb.is_current_spell_calls, RAPTOR_RANKS, "the option off adds zero Steady Shot probes")
    eq(ST.steady_shot_queued, false, "the option off leaves steady_shot_queued down")
    eq(sb.channel_calls, 0, "the option off never reads the player channel")

    -- Option off with a queued Steady Shot id still detects nothing.
    sb.current_spell = 49052
    sb.is_current_spell_calls = 0
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(ST.steady_shot_queued, false, "a queued Steady Shot is ignored while the option is off")

    -- Option on, raptor off (the two gates are independent), nothing queued: every
    -- Steady Shot rank is probed and the flag stays down.
    sb.class_db.enable_steady_shot_color = true
    sb.class_db.enable_raptor_strike_color = false
    sb.current_spell = nil
    sb.is_current_spell_calls = 0
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(sb.is_current_spell_calls, STEADY_RANKS, "an empty cast probes every Steady Shot rank")
    eq(ST.steady_shot_queued, false, "an empty cast leaves the steady queue flag down")
    eq(sb.bar_color_calls, 0, "an empty cast does not recolour")

    -- Every rank of the family is detected.
    for _, spell_id in ipairs({ 56641, 34120, 49051, 49052 }) do
        sb.current_spell = spell_id
        ST.steady_shot_queued = false
        ST.HUNTER.on_current_spell_cast_changed(ST, false)
        eq(ST.steady_shot_queued, true, "rank " .. spell_id .. " is detected as a steady queue")
    end

    -- The WotLK top rank queued: the flag goes up and the bar is repainted in the
    -- configured Steady Shot colour.
    sb.current_spell = 49052
    sb.bar_color_calls = 0
    sb.vertex = nil
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(ST.steady_shot_queued, true, "a queued Steady Shot sets steady_shot_queued")
    eq(sb.bar_color_calls, 1, "a queued Steady Shot recolours once")
    eq(sb.last_hand, "mainhand", "queuing Steady Shot recolours the mainhand bar")
    colour_eq(sb.vertex, sb.class_db.steady_shot_color, "a queued Steady Shot paints the SS colour")

    -- Queuing something else clears the flag.
    sb.current_spell = 12345
    ST.steady_shot_queued = true
    sb.bar_color_calls = 0
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(ST.steady_shot_queued, false, "an unrelated queued spell clears steady_shot_queued")
    eq(sb.bar_color_calls, 0, "clearing a stale steady queue does not force a recolour")

    -- Mainline-code clients surface the queued Steady Shot as a channel instead of
    -- IsCurrentSpell. The channel spell id is the 8th value (no castID).
    sb.current_spell = nil
    sb.channel_spell = 49051
    ST.steady_shot_queued = false
    sb.bar_color_calls = 0
    sb.vertex = nil
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(ST.steady_shot_queued, true, "a matching player channel sets steady_shot_queued")
    eq(sb.bar_color_calls, 1, "the channel path recolours once")
    colour_eq(sb.vertex, sb.class_db.steady_shot_color, "the channel path paints the SS colour")

    -- A foreign channel id must not match.
    sb.channel_spell = 12345
    ST.steady_shot_queued = false
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(ST.steady_shot_queued, false, "an unrelated channel id leaves the flag down")

    -- No live channel (nil payload): no error, flag down.
    sb.channel_spell = nil
    local ok2, err2 = pcall(ST.HUNTER.on_current_spell_cast_changed, ST, false)
    check(ok2, "a nil channel payload does not error (" .. tostring(err2) .. ")")
    eq(ST.steady_shot_queued, false, "a nil channel payload leaves the flag down")

    -- The channel is only consulted when the IsCurrentSpell probe missed.
    sb.current_spell = 49052
    sb.channel_spell = 49052
    sb.channel_calls = 0
    ST.HUNTER.on_current_spell_cast_changed(ST, false)
    eq(sb.channel_calls, 0, "an IsCurrentSpell hit short-circuits the channel read")
end

--=========================================================================================
-- 9) The Steady Shot spellcast clears and combat exit
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.steady_shot_queued = true
    sb.vertex = nil

    local ok, err = pcall(ST.HUNTER.on_spellcast_succeeded, ST, "target", nil, 49052)
    check(ok, "a landed Steady Shot does not error (" .. tostring(err) .. ")")
    eq(ST.steady_shot_queued, false, "a landed Steady Shot clears steady_shot_queued")
    eq(sb.bar_color_calls, 1, "a landed Steady Shot recolours once")
    eq(sb.last_hand, "mainhand", "the steady recolour targets the mainhand bar")
    eq(sb.set_vertex_calls, 0, "clearing the steady queue hands the bar back to the default colour")

    -- Any rank clears on both the landed and the failed-quiet path.
    for _, spell_id in ipairs({ 56641, 34120, 49051, 49052 }) do
        ST.steady_shot_queued = true
        sb.bar_color_calls = 0
        ST.HUNTER.on_spellcast_succeeded(ST, "target", nil, spell_id)
        eq(ST.steady_shot_queued, false, "rank " .. spell_id .. " clears the steady queue on success")
        eq(sb.bar_color_calls, 1, "rank " .. spell_id .. " recolours once on success")

        ST.steady_shot_queued = true
        sb.bar_color_calls = 0
        ST.HUNTER.on_spellcast_failed_quiet(ST, "target", nil, spell_id)
        eq(ST.steady_shot_queued, false, "rank " .. spell_id .. " clears the steady queue on failure")
        eq(sb.bar_color_calls, 1, "rank " .. spell_id .. " recolours once on failure")
    end

    -- A foreign id must change neither flag.
    ST.steady_shot_queued = true
    ST.raptor_strike_queued = true
    sb.bar_color_calls = 0
    sb.vertex = nil
    ST.HUNTER.on_spellcast_succeeded(ST, "target", "cast-9", 12345)
    eq(ST.steady_shot_queued, true, "an unrelated spell id leaves steady_shot_queued alone")
    eq(ST.raptor_strike_queued, true, "an unrelated spell id leaves raptor_strike_queued alone")
    eq(sb.bar_color_calls, 0, "an unrelated spell id does not recolour")
    eq(sb.vertex, nil, "an unrelated spell id does not touch the vertex colour")

    ST.HUNTER.on_spellcast_failed_quiet(ST, "target", nil, 12345)
    eq(ST.steady_shot_queued, true, "an unrelated failed spell id leaves the steady flag alone")

    -- A raptor id must not clear the steady flag, and vice versa.
    ST.HUNTER.on_spellcast_succeeded(ST, "target", nil, 48996)
    eq(ST.raptor_strike_queued, false, "the raptor path still clears raptor_strike_queued")
    eq(ST.steady_shot_queued, true, "the raptor path leaves steady_shot_queued alone")

    ST.raptor_strike_queued = true
    ST.steady_shot_queued = true
    ST.HUNTER.on_spellcast_succeeded(ST, "target", nil, 56641)
    eq(ST.steady_shot_queued, false, "the steady path clears steady_shot_queued")
    eq(ST.raptor_strike_queued, true, "the steady path leaves raptor_strike_queued alone")

    -- A nil spell id (interrupted cast with no id) must be ignored, not crash.
    ST.steady_shot_queued = true
    local ok2, err2 = pcall(ST.HUNTER.on_spellcast_failed_quiet, ST, "target", nil, nil)
    check(ok2, "a nil spell id does not error on the steady path (" .. tostring(err2) .. ")")
    eq(ST.steady_shot_queued, true, "a nil spell id leaves the steady flag alone")

    -- Combat exit wipes the steady queue without recolouring by itself.
    sb.bar_color_calls = 0
    local ok3, err3 = pcall(ST.HUNTER.on_combat_exit, ST)
    check(ok3, "on_combat_exit does not error with a queued Steady Shot (" .. tostring(err3) .. ")")
    eq(ST.steady_shot_queued, false, "combat exit clears steady_shot_queued")
    eq(sb.bar_color_calls, 0, "combat exit does not recolour by itself")
end

--=========================================================================================
-- 10) The Steady Shot colour matrix
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    sb.class_db.enable_raptor_strike_color = false
    sb.class_db.enable_steady_shot_color = true

    -- Offhand is never a class override.
    ST.steady_shot_queued = true
    eq(ST.HUNTER.set_bar_color(ST, "offhand"), false, "the offhand bar returns false for a queued Steady Shot")

    -- Queued and enabled -> the configured Steady Shot colour.
    sb.vertex = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), true, "a queued Steady Shot claims the bar colour")
    colour_eq(sb.vertex, sb.class_db.steady_shot_color, "a queued Steady Shot paints the SS colour")

    -- Idle -> hand the bar back to the default behaviour.
    ST.steady_shot_queued = false
    sb.vertex = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), false, "an idle hunter returns false (default colour)")
    eq(sb.set_vertex_calls, 1, "the idle case does not paint a vertex colour")

    -- A nil flag (post_init never ran) is idle, not a queue.
    ST.steady_shot_queued = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), false, "a nil steady flag is treated as idle")

    -- Option off -> the queued ability is not a colour override at all.
    ST.steady_shot_queued = true
    sb.class_db.enable_steady_shot_color = false
    sb.vertex = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), false, "a disabled Steady Shot colour returns false")
    eq(sb.set_vertex_calls, 1, "the disabled steady case does not paint a vertex colour")

    -- With both queued and both enabled the raptor branch still wins (branch order).
    sb.class_db.enable_raptor_strike_color = true
    sb.class_db.enable_steady_shot_color = true
    ST.raptor_strike_queued = true
    ST.steady_shot_queued = true
    sb.vertex = nil
    eq(ST.HUNTER.set_bar_color(ST, "mainhand"), true, "the raptor branch claims the bar first")
    colour_eq(sb.vertex, sb.class_db.raptor_strike_color, "the raptor colour wins over the steady colour")
end

--=========================================================================================
-- 10b) TBC name-resolution vs Era id-resolution (operator client fact)
--=========================================================================================
-- TBC Anniversary spell-state queries take NAMES, never bare ids; Classic Era
-- takes ids. spell_token()/queue_tokens() (classes/hunter.lua) implement the
-- split; the WA pack (docs/hunter-wa.json) proves the id->name leg with
-- GetSpellInfo(75/2973/2974/2643/19434/34120/34026/19574/3045/23989/34074).
do
    local TBC_SPELLS = {
        [75] = { "Auto Shot", 0 },
        [2973] = { "Raptor Strike", 0 },
        [2974] = { "Wing Clip", 0 },
        [2643] = { "Multi-Shot", 500 },
        [27021] = { "Multi-Shot", 500 },
        [19434] = { "Aimed Shot", 3000 },
        [20904] = { "Aimed Shot", 3000 },
        [34120] = { "Steady Shot", 1500 },
        [56641] = { "Steady Shot", 1500 },
        [34026] = { "Kill Command", 0 },
        [19574] = { "Bestial Wrath", 0 },
        [3045] = { "Rapid Fire", 0 },
        [23989] = { "Readiness", 0 },
        [34074] = { "Aspect of the Viper", 0 },
    }
    local function tbc_spell_info(id)
        local entry = TBC_SPELLS[id]
        if entry then
            return entry[1], nil, "icon_" .. id, entry[2], 0, 0, id
        end
        return nil
    end
    local function token_types(tokens)
        local strings, numbers = 0, 0
        for _, token in ipairs(tokens) do
            if type(token) == "string" then
                strings = strings + 1
            elseif type(token) == "number" then
                numbers = numbers + 1
            end
        end
        return strings, numbers
    end

    -- Queue probes: TBC reads one distinct family name (ten Raptor ranks share
    -- one read); Era reads every rank id.
    do
        local tbc = build({ project = 5, GetSpellInfo = tbc_spell_info,
            current_spell = "Raptor Strike" })
        tbc.ST.interfaces_are_initialised = true
        local ok, err = pcall(tbc.ST.HUNTER.on_current_spell_cast_changed, tbc.ST, false)
        check(ok, "the TBC name probe does not error (" .. tostring(err) .. ")")
        eq(tbc.ST.raptor_strike_queued, true, "TBC: the family name detects the queue")
        eq(tbc.is_current_spell_calls, 1, "TBC: ten Raptor ranks share one name read")
        local strings, numbers = token_types(tbc.is_current_spell_tokens)
        eq(numbers, 0, "TBC: no bare id reaches IsCurrentSpell")
        check(strings > 0, "TBC: the probe ran by name")
    end
    do
        -- Unknown spell data hides: no name, no probe, no crash.
        local cold = build({ project = 5, current_spell = "Raptor Strike" })
        cold.ST.interfaces_are_initialised = true
        local ok, err = pcall(cold.ST.HUNTER.on_current_spell_cast_changed, cold.ST, false)
        check(ok, "a cold TBC spell cache does not error (" .. tostring(err) .. ")")
        eq(cold.ST.raptor_strike_queued, false, "TBC: an unresolvable name never queues")
        eq(cold.is_current_spell_calls, 0, "TBC: an unresolvable name spends no probe")
    end
    do
        -- Era control: the same fixture by id (the default spell data answers
        -- nothing, so the id path needs no names at all). The loop returns on
        -- the first match, so only the recorded tokens' types are asserted.
        local era = build({ project = 2, current_spell = 2973 })
        era.ST.interfaces_are_initialised = true
        local ok, err = pcall(era.ST.HUNTER.on_current_spell_cast_changed, era.ST, false)
        check(ok, "the Era id probe does not error (" .. tostring(err) .. ")")
        eq(era.ST.raptor_strike_queued, true, "Era: the rank id detects the queue")
        local strings, numbers = token_types(era.is_current_spell_tokens)
        eq(strings, 0, "Era: only bare ids reach IsCurrentSpell")
        check(numbers > 0, "Era: the probe ran by id")
    end
    do
        -- Era probes every rank id when nothing matches (no early return).
        local sweep = build({ project = 2 })
        sweep.ST.interfaces_are_initialised = true
        pcall(sweep.ST.HUNTER.on_current_spell_cast_changed, sweep.ST, false)
        eq(sweep.is_current_spell_calls, 11, "Era: every Raptor rank id is probed")
    end

    -- Viper knowledge: TBC asks for the name, Era for the id.
    do
        local tbc = build({ project = 5, GetSpellInfo = tbc_spell_info,
            known_spells = { ["Aspect of the Viper"] = true } })
        eq(tbc.ST.HUNTER.is_viper_known(), true, "TBC: the Viper name reads known")
        local strings, numbers = token_types(tbc.is_spell_known_tokens)
        eq(numbers, 0, "TBC: no bare id reaches IsSpellKnown")
        check(strings > 0, "TBC: the knowledge probe ran by name")
        local era = build({ project = 2, known_spells = { [34074] = true } })
        eq(era.ST.HUNTER.is_viper_known(), true, "Era: the TBC Viper id reads known")
        local _, enumbers = token_types(era.is_spell_known_tokens)
        check(enumbers > 0, "Era: the knowledge probe ran by id")
    end

    -- Auto Shot sync + repeat: TBC asks by name, Era by id.
    do
        local cd_tokens, repeat_tokens = {}, {}
        local tbc = build({ project = 5, GetSpellInfo = tbc_spell_info,
            GetSpellCooldown = function(spell)
                cd_tokens[#cd_tokens + 1] = spell
                return 0, 0, 0, 0
            end,
            IsAutoRepeatSpell = function(spell)
                repeat_tokens[#repeat_tokens + 1] = spell
                return true
            end })
        tbc.ST.ranged = { start = 90, speed = 3.0 }
        tbc.ST.HUNTER.on_cooldown_update(tbc.ST)
        eq(#cd_tokens, 1, "TBC: the Auto sync spends one cooldown read")
        eq(cd_tokens[1], "Auto Shot", "TBC: the Auto sync reads by name")
        tbc.ST.HUNTER.on_autorrepeat_event(tbc.ST, false)
        eq(#repeat_tokens, 1, "TBC: the repeat probe runs once")
        eq(repeat_tokens[1], "Auto Shot", "TBC: the repeat probe reads by name")
        eq(tbc.ST.ranged.auto_repeat_active, true, "TBC: the repeat reading lands")
        local era_cd, era_repeat = {}, {}
        local era = build({ project = 2,
            GetSpellCooldown = function(spell)
                era_cd[#era_cd + 1] = spell
                return 0, 0, 0, 0
            end,
            IsAutoRepeatSpell = function(spell)
                era_repeat[#era_repeat + 1] = spell
                return true
            end })
        era.ST.ranged = { start = 90, speed = 3.0 }
        era.ST.HUNTER.on_cooldown_update(era.ST)
        eq(era_cd[1], 75, "Era: the Auto sync reads by id")
        era.ST.HUNTER.on_autorrepeat_event(era.ST, false)
        eq(era_repeat[1], 75, "Era: the repeat probe reads by id")
    end

    -- Gather cooldown + range reads: TBC by name, Era by id.
    do
        local cd_tokens, range_tokens = {}, {}
        local tbc = build({ project = 5, GetSpellInfo = tbc_spell_info,
            GetSpellCooldown = function(spell)
                cd_tokens[#cd_tokens + 1] = spell
                return 0, 0, 0, 0
            end,
            IsSpellInRange = function(spell)
                range_tokens[#range_tokens + 1] = spell
                return 1
            end })
        tbc.ST.HUNTER.post_init(tbc.ST)
        local gathered = tbc.ST.HUNTER.gather_guide_inputs(tbc.ST, {})
        eq(#cd_tokens, 5, "TBC: one cooldown read per prompt (steady/kc/bw/rf/multi)")
        local strings, numbers = token_types(cd_tokens)
        eq(numbers, 0, "TBC: no bare id reaches GetSpellCooldown")
        eq(strings, 5, "TBC: every cooldown read is by name")
        local want = { ["Steady Shot"] = true, ["Kill Command"] = true,
            ["Bestial Wrath"] = true, ["Rapid Fire"] = true, ["Multi-Shot"] = true }
        local covered = true
        for _, token in ipairs(cd_tokens) do
            if not want[token] then
                covered = false
            end
        end
        check(covered, "TBC: the cooldown reads cover the five TBC prompts by name")
        eq(#range_tokens, 1, "TBC: the range probe runs once per gather")
        eq(range_tokens[1], "Steady Shot", "TBC: the range probe reads by name")
        eq(gathered.target_in_range, 1, "TBC: the named range reading lands")
        eq(gathered.kc_known, true, "TBC: Kill Command still resolves")
        local era_cd, era_range = {}, {}
        local era = build({ project = 2,
            GetSpellCooldown = function(spell)
                era_cd[#era_cd + 1] = spell
                return 0, 0, 0, 0
            end,
            IsSpellInRange = function(spell)
                era_range[#era_range + 1] = spell
                return 1
            end })
        era.ST.HUNTER.post_init(era.ST)
        local egathered = era.ST.HUNTER.gather_guide_inputs(era.ST, {})
        local _, enumbers = token_types(era_cd)
        check(enumbers > 0, "Era: cooldown reads stay by id")
        eq(#era_range, 1, "Era: the range probe runs once per gather")
        eq(era_range[1], 56641, "Era: the range probe reads the steady rank id")
        eq(egathered.target_in_range, 1, "Era: the id range reading lands")
    end
end

--=========================================================================================
-- 11) Config and options wiring: inert by default, widgets present
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    -- config_presets.lua: the HUNTER defaults block carries the new keys, and the
    -- enable flag ships false so the feature is inert until the owner opts in.
    local presets = read("config_presets.lua")
    local hunter_defaults = presets:match("ST%.HUNTER%.defaults%s*=%s*%{(.-)ST%.MAGE%.defaults")
    check(hunter_defaults ~= nil, "the HUNTER defaults block is found in config_presets.lua")
    hunter_defaults = hunter_defaults or ""
    check(hunter_defaults:find("enable_steady_shot_color%s*=%s*false") ~= nil,
        "enable_steady_shot_color ships false (inert by default)")
    local sr, sg, sbl = hunter_defaults:match(
        "steady_shot_color%s*=%s*{%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*[%d%.]+%s*}")
    check(sr ~= nil and sg ~= nil and sbl ~= nil,
        "steady_shot_color is a 0-255 colour table in the HUNTER defaults")
    local rr, rg, rb = hunter_defaults:match(
        "raptor_strike_color%s*=%s*{%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    check(not (sr == rr and sg == rg and sbl == rb),
        "the Steady Shot colour is distinct from the Raptor Strike colour")

    -- option_tables.lua: the toggle and picker mirror the raptor widgets, with the
    -- orders continuing the section's numbering (2.x after the raptor 1.x group).
    local options = read("option_tables.lua")
    local hunter_opts = options:match(
        "function ST%.class_opts_funcs%.HUNTER%((.-)function ST%.class_opts_funcs%.")
    check(hunter_opts ~= nil, "the HUNTER options function is found in option_tables.lua")
    hunter_opts = hunter_opts or ""
    local toggle = hunter_opts:match("enable_steady_shot_color%s*=%s*{(.-)}")
    check(toggle ~= nil and toggle:find("type%s*=%s*\"toggle\"") ~= nil,
        "the steady option is a toggle")
    local picker = hunter_opts:match("%ssteady_shot_color%s*=%s*{(.-)}")
    check(picker ~= nil and picker:find("type%s*=%s*\"color\"") ~= nil,
        "the steady colour is a colour picker")
    check(picker ~= nil and picker:find("get%s*=%s*\"color_getter\"") ~= nil
        and picker:find("set%s*=%s*\"color_setter\"") ~= nil,
        "the steady colour uses the class colour get/set pair")
    local order = toggle and toggle:match("order%s*=%s*([%d%.]+)")
    check(order ~= nil and tonumber(order) >= 2,
        "the steady widgets continue the section's numbering")
end

--=========================================================================================
-- 12) hunter_ui hook wiring: post_init creates, on_bar_update dispatches
--=========================================================================================
do
    local calls = { init = 0, hands = {} }
    local hunter_ui = {
        init = function() calls.init = calls.init + 1 end,
        on_bar_update = function(_, hand) calls.hands[#calls.hands + 1] = hand end,
    }
    local sb = build({ st_extras = { hunter_ui = hunter_ui } })
    local ST = sb.ST

    eq(calls.init, 0, "hunter_ui.init is not called before post_init")
    local ok, err = pcall(ST.HUNTER.post_init, ST)
    check(ok, "post_init with hunter_ui present does not error (" .. tostring(err) .. ")")
    eq(calls.init, 1, "post_init drives st.hunter_ui.init once")

    local ok2, err2 = pcall(ST.HUNTER.on_bar_update, ST, "ranged")
    local ok3, err3 = pcall(ST.HUNTER.on_bar_update, ST, "mainhand")
    local ok4, err4 = pcall(ST.HUNTER.on_bar_update, ST, "offhand")
    check(ok2 and ok3 and ok4, "the per-frame hook dispatches without error ("
        .. tostring(err2 or err3 or err4) .. ")")
    eq(#calls.hands, 2, "only the ranged and mainhand ticks dispatch into hunter_ui")
    eq(calls.hands[1], "ranged", "the ranged tick dispatches first")
    eq(calls.hands[2], "mainhand", "the mainhand tick follows")

    -- Without st.hunter_ui the whole wiring stays inert (a flavor without hunter_ui).
    local plain = build()
    local ok5, err5 = pcall(plain.ST.HUNTER.post_init, plain.ST)
    local ok6, err6 = pcall(plain.ST.HUNTER.on_bar_update, plain.ST, "ranged")
    check(ok5 and ok6, "post_init and on_bar_update stay no-ops without st.hunter_ui ("
        .. tostring(err5 or err6) .. ")")
end

--=========================================================================================
-- 13) get_cast_grace: Multi-Shot carries no steady-shot grace
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    local hw = sb.st.hunter_window
    eq(ST.HUNTER.get_cast_grace(ST, 2643, nil), hw.MULTI_SHOT_GRACE,
        "Multi-Shot rank 1 (2643) reads the 0 grace")
    eq(ST.HUNTER.get_cast_grace(ST, 27021, nil), hw.MULTI_SHOT_GRACE,
        "the TBC top rank (27021) reads the 0 grace")
    eq(ST.HUNTER.get_cast_grace(ST, nil, "Multi-Shot"), hw.MULTI_SHOT_GRACE,
        "the localized Multi-Shot name reads the 0 grace")
    eq(ST.HUNTER.get_cast_grace(ST, 34120, "Steady Shot"), hw.STEADY_SHOT_GRACE,
        "Steady Shot reads the steady-shot grace")
    eq(ST.HUNTER.get_cast_grace(ST, 19434, "Aimed Shot"), hw.STEADY_SHOT_GRACE,
        "Aimed Shot reads the steady-shot grace (not a Multi-Shot rank: no 0 grace)")
    eq(ST.HUNTER.get_cast_grace(ST, 20904, nil), hw.STEADY_SHOT_GRACE,
        "the Aimed top rank reads the steady-shot grace by id alone")
    eq(ST.HUNTER.get_cast_grace(ST, 12345, "Aimed Shot"), hw.STEADY_SHOT_GRACE,
        "an unknown cast reads the steady-shot grace")
    eq(ST.HUNTER.get_cast_grace(ST, nil, nil), hw.STEADY_SHOT_GRACE,
        "no cast info at all reads the steady-shot grace")
    eq(ST.HUNTER.get_cast_grace(ST, nil, "Sniper Shot"), hw.STEADY_SHOT_GRACE,
        "the future Sniper Shot cast reads the steady-shot grace (not a Multi rank)")
    eq(ST.HUNTER.get_cast_grace(ST, nil, "Summon Hawk"), hw.STEADY_SHOT_GRACE,
        "the future Summon Hawk cast reads the steady-shot grace (unknown id)")
    eq(hw.MULTI_SHOT_GRACE, 0, "the multi-shot grace is 0")
    eq(hw.STEADY_SHOT_GRACE, 0.5, "the steady-shot grace is 0.5")
end

--=========================================================================================
-- 13b) Feign Death ranged-state clear and the Readiness Rapid Fire refresh
--=========================================================================================
do
    local refresh_calls = 0
    local sb = build({ st_extras = { hunter_ui = {
        force_rapid_fire_refresh = function() refresh_calls = refresh_calls + 1 end,
    } } })
    local ST = sb.ST

    -- Feign Death (5384): the class-owned ranged display state is cleared; the
    -- engine-owned fields are never touched (bars.lua's OnUpdate runs over them).
    ST.ranged = {
        auto_repeat_active = true,
        hidden_window_start = 1.5,
        hidden_window_duration = 0.55,
        synced_duration = 2.4,
        last_restart_at = 5,
        start = 1.0, speed = 2.4, ends_at = 3.4,
    }
    ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 5384)
    eq(ST.ranged.auto_repeat_active, false, "FD: the auto-repeat reading drops")
    eq(ST.ranged.hidden_window_start, nil, "FD: the cached hidden window is dropped")
    eq(ST.ranged.hidden_window_duration, nil, "FD: the cached window width is dropped")
    eq(ST.ranged.synced_duration, nil, "FD: the synced cycle length is dropped")
    eq(ST.ranged.last_restart_at, nil, "FD: the restart dedupe stamp is dropped")
    eq(ST.ranged.start, 1.0, "FD: the engine-owned anchor is never touched")
    eq(ST.ranged.speed, 2.4, "FD: the engine-owned speed is never touched")
    eq(ST.ranged.ends_at, 3.4, "FD: the engine-owned ends_at is never touched")

    -- Unrelated casts leave the ranged state alone.
    ST.ranged.hidden_window_start = 1.5
    ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 34120)
    eq(ST.ranged.hidden_window_start, 1.5, "a Steady Shot cast never clears the window")
    -- A nil ranged state is a safe no-op (pre-init).
    local plain = build()
    local ok, err = pcall(plain.ST.HUNTER.on_spellcast_succeeded, plain.ST, "player", nil, 5384)
    check(ok, "FD without a ranged state does not error (" .. tostring(err) .. ")")

    -- Readiness (23989) forces the Rapid Fire refresh through hunter_ui.
    eq(refresh_calls, 0, "Readiness: no refresh before the cast")
    ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 23989)
    eq(refresh_calls, 1, "Readiness: the cast forces the Rapid Fire refresh")
    ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 3045)
    eq(refresh_calls, 1, "an unrelated cast never forces the refresh")
    -- A flavor without hunter_ui stays inert.
    local no_ui = build()
    local ok2, err2 = pcall(no_ui.ST.HUNTER.on_spellcast_succeeded, no_ui.ST, "player", nil, 23989)
    check(ok2, "Readiness without hunter_ui does not error (" .. tostring(err2) .. ")")
end

--=========================================================================================
-- 14) hunter_ui sandbox: frames created, off-gates skip scans, inert paths
--=========================================================================================
-- A WoW-free region mock: only the members hunter_ui actually reads are real, every
-- other region method is a cached no-op. SetPoint/GetPoint track the anchors (the melee
-- re-anchor assertions read the resulting CENTER y), and the clock is a mutable field so
-- the throttled scans can be exercised deterministically.
--
-- build_ui is hoisted to file scope so the font section at the end of this file can
-- build the same sandbox.
local build_ui
do
    local function new_region(kind, name, parent)
        local region = {
            kind = kind, name = name, parent = parent,
            shown = true, width = 200, height = 15, scale = 1, frame_level = 1,
            center_y = 0, bottom = 0, points = {}, restored = 0,
        }
        setmetatable(region, {
            __index = function(t, key)
                -- WoW region methods are cached no-ops; data fields stay nil when a
                -- fixture leaves them unset (so bar_frame/text/tex read back nil, not a
                -- fabricated function).
                if type(key) ~= "string" or not key:match("^[A-Z]") then
                    return nil
                end
                local fn = function() end
                rawset(t, key, fn)
                return fn
            end,
        })
        function region:CreateTexture() return new_region("Texture", nil, self) end
        function region:CreateFontString() return new_region("FontString", nil, self) end
        function region:CreateFrame() return new_region("Frame", nil, self) end
        function region:SetPoint(point, relative, relative_point, x, y)
            self.points[#self.points + 1] = { point = point, relative = relative, x = x, y = y }
            if point == "CENTER" then
                self.center_y = y or 0
            end
        end
        function region:ClearAllPoints() self.points = {} end
        function region:GetPoint(index)
            local p = self.points[index or 1]
            if not p then
                return nil
            end
            return p.point, p.relative, p.point, p.x or 0, p.y or 0
        end
        function region:SetWidth(w) self.width = w end
        function region:GetWidth() return self.width end
        function region:SetHeight(h) self.height = h end
        function region:GetHeight() return self.height end
        function region:SetSize(w, h) self.width, self.height = w, h end
        function region:SetScale(s) self.scale = s end
        function region:GetScale() return self.scale end
        function region:SetFrameLevel(l) self.frame_level = l end
        function region:GetFrameLevel() return self.frame_level end
        function region:GetBottom() return self.bottom end
        function region:GetCenter() return 0, self.center_y end
        function region:Show() self.shown = true end
        function region:Hide() self.shown = false end
        function region:IsShown() return self.shown end
        function region:IsVisible() return self.shown end
        -- SoD-faithful FontString: SetFont(nil) latches nothing (false, like the
        -- client) and SetText with no font throws ("Font not set"). Every FontString
        -- the hunter UI creates must carry a font BEFORE its first SetText.
        function region:SetFont(path, size, flags)
            if kind ~= "FontString" then
                return true
            end
            if path == nil then
                return false
            end
            self.font = { path, size, flags }
            return true
        end
        function region:GetFont() return self.font and self.font[1] or nil end
        function region:SetText(text)
            if kind == "FontString" and self.font == nil then
                error("Font not set", 2)
            end
            self.text = text
        end
        function region:SetTexture(texture) self.texture = texture end
        function region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        function region:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
        return region
    end

    build_ui = function(opts)
        opts = opts or {}
        local sb = {
            now = opts.now or 0,
            calls = { cast = 0, aura = 0, in_range = 0, distance = 0, restore = 0 },
            live_cast = opts.live_cast,
            auras = opts.auras,
            pet_auras = opts.pet_auras,
            in_range = opts.in_range,
            target_yards = opts.target_yards,
            in_combat = opts.in_combat == true,
            ranged_available = opts.ranged_available ~= false,
            regions = {},
        }

        local env = setmetatable({}, { __index = _G })
        env.WOW_PROJECT_ID = 11
        env.WOW_PROJECT_CLASSIC = 2
        env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
        env.WOW_PROJECT_WRATH_CLASSIC = 11
        env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
        env.WOW_PROJECT_MISTS_CLASSIC = 19
        env.WOW_PROJECT_MAINLINE = 1
        env.WOW_PROJECT_FOREVER = 18
        env.UIParent = new_region("Frame", "UIParent", nil)
        env.CreateFrame = function(kind, name, parent)
            local region = new_region(kind or "Frame", name, parent)
            sb.regions[#sb.regions + 1] = region
            return region
        end
        env.InCombatLockdown = function() return sb.in_combat end
        env.GetTime = function() return sb.now end
        env.GetTimePreciseSec = function() return sb.now end
        -- The client's own standard font. The shared chain (utils.lua) reads it as
        -- the middle step: the LSM path, then STANDARD_TEXT_FONT, then the classic
        -- client font. A distinctive value proves which step carried the label.
        env.STANDARD_TEXT_FONT = "Fonts\\STANDARD.TTF"
        if opts.no_std_font then
            env.STANDARD_TEXT_FONT = nil
        end

        -- H1 scripted unit tokens (absent by default = the client answers nothing).
        if opts.unit_exists ~= nil then
            env.UnitExists = opts.unit_exists
        end
        if opts.unit_is_unit ~= nil then
            env.UnitIsUnit = opts.unit_is_unit
        end

        -- Minimal client spell data: the hunter tokens, the reference Multi-Shot ranks and
        -- the aspect table, so the token/name matchers resolve against a real client shape.
        local spell_data = {
            [75] = "Auto Shot", [2973] = "Raptor Strike", [2974] = "Wing Clip",
            [3045] = "Rapid Fire", [2643] = "Multi-Shot", [27021] = "Multi-Shot",
            [13165] = "Aspect of the Hawk", [27044] = "Aspect of the Hawk",
            [5118] = "Aspect of the Cheetah", [13163] = "Aspect of the Monkey",
            [13159] = "Aspect of the Pack", [20190] = "Aspect of the Wild",
            [34074] = "Aspect of the Viper", [13171] = "Aspect of the Beast",
            [19574] = "Bestial Wrath", [19615] = "Frenzy Effect",
        }
        env.GetSpellInfo = function(id)
            if opts.missing_spells and opts.missing_spells[id] then
                return nil
            end
            local name = spell_data[id]
            if not name then
                return nil
            end
            return name, nil, "icon_" .. id, 0, 0, 0, id
        end
        env.UnitCastingInfo = function()
            sb.calls.cast = sb.calls.cast + 1
            local cast = sb.live_cast
            if not cast then
                return nil
            end
            return cast.name, "", "cast_icon", cast.start_ms, cast.end_ms,
                false, 1, false, cast.spell_id
        end
        env.UnitChannelInfo = function() return nil end
        env.UnitAura = function(unit, index, filter)
            sb.calls.aura = sb.calls.aura + 1
            local list = sb.auras
            if unit ~= "player" then
                list = sb.pet_auras
            end
            local aura = list and list[index]
            if not aura then
                return nil
            end
            return aura.name, "", aura.count or 0, "", aura.duration, aura.expiration,
                nil, nil, nil, aura.spell_id
        end
        env.IsSpellInRange = function(spell, unit)
            sb.calls.in_range = sb.calls.in_range + 1
            if not sb.in_range then
                return nil
            end
            return sb.in_range[spell]
        end
        -- Exact target distance: the sweet spot is a yards band now (R3, 2026-10-21).
        -- nil yards = the client cannot answer (unknown), never a guess or a zero.
        env.UnitDistanceSquared = function(unit)
            sb.calls.distance = sb.calls.distance + 1
            if sb.target_yards == nil then
                return 0, false
            end
            return sb.target_yards * sb.target_yards, true
        end

        -- Opt-in mana + spell-knowledge fixtures for the OOM Viper probe (compat
        -- reads both through _G; absent reads the unknown shape). Placed before
        -- the compat load so the probes resolve like the class build() above.
        if opts.mana ~= nil then
            env.UnitPower = function() return opts.mana.cur end
            env.UnitPowerMax = function() return opts.mana.max end
        end
        if opts.known_spells ~= nil then
            env.IsSpellKnown = function(id)
                return opts.known_spells[id] == true
            end
        end

        -- compat.lua reads several legacy globals through _G; mirror EVERY stub for the
        -- duration of its load, then restore _G exactly. Absent keys are tracked by
        -- name (same discipline as build()): a nil entry stores nothing in the mirrored
        -- table and would otherwise leak the stub into every later sandbox.
        local mirrored = {}
        local mirrored_names = {}
        for name, value in pairs(env) do
            mirrored[name] = rawget(_G, name)
            mirrored_names[#mirrored_names + 1] = name
            _G[name] = value
        end

        local st = {}
        local compat = assert(loadfile(ROOT .. "compat.lua"))
        setfenv(compat, env)
        compat("SwedgeTimer", st)

        for _, name in ipairs(mirrored_names) do
            _G[name] = mirrored[name]
        end

        local ST = { HUNTER = {} }
        local class_db = {
            class_enabled = true,
            timers_locked = true,
            hunter_cast_bar_enabled = true,
            hunter_cast_bar_height = 15,
            hunter_cast_bar_color = { 0.35, 0.65, 0.95, 1.0 },
            hunter_range_helper_enabled = true,
            hunter_rapid_fire_bar_enabled = true,
            hunter_aspect_icon_enabled = true,
            -- H1 target warning ships off (nil = off); a test opts in explicitly.
            hunter_target_warning_enabled = opts.target_warning_enabled,
        }
        local hand_db = {
            ranged = { bar_texture_key = "Minimalist", text_font = "Expressway", text_size = 14 },
            mainhand = { bar_width = 200, bar_height = 14 },
            offhand = { bar_width = 200, bar_height = 14 },
        }
        local ranged_bar_frame = new_region("Frame", "RangedBarFrame", env.UIParent)
        ranged_bar_frame.width = 275
        ranged_bar_frame.height = 20
        ranged_bar_frame.bottom = opts.ranged_bottom or -120
        -- The bar's visuals frame is where bars.lua keeps the fill textures and the
        -- paladin/hunter overlays draw (the hunter cast zone parents here).
        ranged_bar_frame.visuals_frame = new_region("Frame", "RangedVisualsFrame", ranged_bar_frame)
        ranged_bar_frame.visuals_frame.width = 273
        ranged_bar_frame.visuals_frame.height = 18
        local ranged_anchor = new_region("Frame", "RangedAnchorFrame", env.UIParent)
        if not opts.no_ranged_frame then
            ranged_anchor.bar_frame = ranged_bar_frame
        end
        local mh_anchor = new_region("Frame", "MHAnchorFrame", env.UIParent)
        mh_anchor.height = 14
        mh_anchor.center_y = -142
        mh_anchor.points[1] = { point = "CENTER", relative = env.UIParent, x = 0, y = -142 }
        local oh_anchor = new_region("Frame", "OHAnchorFrame", env.UIParent)
        oh_anchor.height = 14
        oh_anchor.center_y = -158
        oh_anchor.points[1] = { point = "CENTER", relative = env.UIParent, x = 0, y = -158 }
        ST.latency = { world_ms = opts.world_ms or 0 }
        ST.has_attackable_target = opts.has_target ~= false
        ST.ranged = {
            anchor_frame = ranged_anchor,
            start = opts.ranged_start,
            speed = opts.ranged_speed,
            synced_duration = opts.ranged_synced,
        }
        ST.mainhand = { anchor_frame = mh_anchor }
        ST.offhand = { anchor_frame = oh_anchor }
        ST.get_class_table = function() return class_db end
        ST.get_hand_table = function(_, hand) return hand_db[hand] end
        ST.bar_is_enabled = function(_, hand) return hand == "ranged" and sb.ranged_available end

        env.LibStub = function(major)
            if major == "AceAddon-3.0" then
                return { GetAddon = function() return ST end }
            end
            if major == "LibSharedMedia-3.0" then
                return {
                    Fetch = function(_, kind, key)
                        if kind == "font" then
                            -- The font chain (utils.lua) has to survive a key that no
                            -- longer resolves (the operator's font lives in another
                            -- addon's LSM registration) and a Fetch that throws.
                            if opts.lsm_throw then
                                error("LSM fetch failed", 2)
                            end
                            if opts.lsm_font_nil then
                                return nil
                            end
                            return "Fonts\\FIXEDFONT.TTF"
                        end
                        return key
                    end,
                }
            end
            if major == "LibWindow-1.1" then
                return {
                    RestorePosition = function(frame)
                        sb.calls.restore = sb.calls.restore + 1
                        frame.restored = frame.restored + 1
                    end,
                }
            end
            return {}
        end

        -- The real TOC order: hunter_window before hunter_ui before classes/hunter.
        local utils = assert(loadfile(ROOT .. "utils.lua"))
        setfenv(utils, env)
        utils("SwedgeTimer", st)

        local hw_mod = assert(loadfile(ROOT .. "hunter_window.lua"))
        setfenv(hw_mod, env)
        hw_mod("SwedgeTimer", st)

        -- hunter_ui registers its per-subfeature guard labels/sites at load (R3).
        local guard_mod = assert(loadfile(ROOT .. "guard.lua"))
        setfenv(guard_mod, env)
        guard_mod("SwedgeTimer", st)

        local ui_mod = assert(loadfile(ROOT .. "hunter_ui.lua"))
        setfenv(ui_mod, env)
        ui_mod("SwedgeTimer", st)

        local class_mod = assert(loadfile(ROOT .. "classes/hunter.lua"))
        setfenv(class_mod, env)
        class_mod("SwedgeTimer", st)
        -- Same activation as build(): classes/hunter.lua registers its body as a
        -- loader (operator order 2026-10-21), so this sandbox must run it too.
        assert(type(st.class_loaders) == "table"
            and type(st.class_loaders["HUNTER"]) == "function",
            "classes/hunter.lua registers the HUNTER loader (build_ui)")
        st.class_loaders["HUNTER"]()

        sb.st = st
        sb.ST = ST
        sb.env = env
        sb.class_db = class_db
        sb.hand_db = hand_db
        sb.mh_anchor = mh_anchor
        sb.oh_anchor = oh_anchor
        sb.ranged_bar_frame = ranged_bar_frame
        return sb
    end

    -- 10c) Hunter UI range tokens: TBC names (nil when the data has not
    -- answered), Era names-or-id. build_ui is defined above, so these pins
    -- live here rather than in section 10b.
    do
        local tbc = build_ui({})
        tbc.st.family = "TBC" -- compat sets this before post_init in-game
        tbc.st.hunter_ui.build(tbc.ST, tbc.ranged_bar_frame)
        eq(tbc.st.hunter_ui.wing_clip_token, "Wing Clip", "TBC: the melee token is the name")
        eq(tbc.st.hunter_ui.raptor_token, "Raptor Strike", "TBC: the raptor token is the name")
        eq(tbc.st.hunter_ui.auto_shot_token, "Auto Shot", "TBC: the ranged token is the name")
        local cold = build_ui({ missing_spells = { [2974] = true } })
        cold.st.family = "TBC"
        cold.st.hunter_ui.build(cold.ST, cold.ranged_bar_frame)
        eq(cold.st.hunter_ui.wing_clip_token, nil,
            "TBC: an unanswered token hides (never a bare id)")
        eq(cold.st.hunter_ui.raptor_token, "Raptor Strike",
            "TBC: answered tokens still resolve")
        local era = build_ui({ missing_spells = { [2974] = true } })
        era.st.family = "ERA"
        era.st.hunter_ui.build(era.ST, era.ranged_bar_frame)
        eq(era.st.hunter_ui.wing_clip_token, 2974, "Era: an unanswered token keeps the id")
    end

    -- 14a) the creation is deferred under combat lockdown and runs on the next tick.
    do
        local sb = build_ui({ in_combat = true })
        sb.ST.HUNTER.post_init(sb.ST)
        eq(sb.st.hunter_ui.ready, nil, "no frames are created under combat lockdown")
        eq(sb.st.hunter_ui.cast_frame, nil, "the cast frame is deferred under lockdown")
        local ok, err = pcall(sb.ST.HUNTER.on_bar_update, sb.ST, "ranged")
        check(ok, "an in-combat ranged tick does not error (" .. tostring(err) .. ")")
        eq(sb.st.hunter_ui.ready, nil, "an in-combat tick still creates nothing")
        sb.in_combat = false
        local ok2, err2 = pcall(sb.ST.HUNTER.on_bar_update, sb.ST, "ranged")
        check(ok2, "the out-of-combat tick that creates the frames does not error ("
            .. tostring(err2) .. ")")
        eq(sb.st.hunter_ui.ready, true, "the next out-of-combat tick creates the widget set")
        check(sb.st.hunter_ui.cast_frame ~= nil, "the cast bar frame exists")
        check(sb.st.hunter_ui.range_helper ~= nil, "the range helper frame exists")
        check(sb.st.hunter_ui.rapid_fire_bar ~= nil, "the Rapid Fire bar exists")
        check(sb.st.hunter_ui.aspect_icon ~= nil, "the aspect icon frame exists")
    end

    -- 14b) a disabled ranged hand keeps everything inert (the Retail shape).
    do
        local sb = build_ui({ ranged_available = false })
        local ok, err = pcall(sb.ST.HUNTER.post_init, sb.ST)
        check(ok, "post_init with the ranged hand disabled does not error (" .. tostring(err) .. ")")
        eq(sb.st.hunter_ui.ready, nil, "no frames are created for a disabled ranged hand")
        local ok2, err2 = pcall(sb.ST.HUNTER.on_bar_update, sb.ST, "ranged")
        check(ok2, "the ranged tick with the hand disabled does not error (" .. tostring(err2) .. ")")
        eq(sb.st.hunter_ui.ready, nil, "the ranged tick stays inert for a disabled ranged hand")
        eq(sb.calls.cast, 0, "no casting reads while the ranged hand is disabled")
        eq(sb.calls.aura, 0, "no aura scans while the ranged hand is disabled")
        eq(sb.calls.in_range, 0, "no range reads while the ranged hand is disabled")
    end

    -- 14c) off-gates: every option off skips its widget's scans/API reads.
    do
        local sb = build_ui()
        sb.class_db.hunter_cast_bar_enabled = false
        sb.class_db.hunter_range_helper_enabled = false
        sb.class_db.hunter_rapid_fire_bar_enabled = false
        sb.class_db.hunter_aspect_icon_enabled = false
        sb.class_db.hunter_cast_zone_enabled = false
        sb.class_db.hunter_bw_badge_enabled = false
        sb.class_db.hunter_frenzy_stacks_enabled = false
        sb.auras = {
            { name = "Rapid Fire", spell_id = 3045, duration = 15, expiration = 10 },
            { name = "Aspect of the Hawk", spell_id = 13165, duration = 60, expiration = 60 },
        }
        sb.ST.HUNTER.post_init(sb.ST)
        local ok, err = pcall(sb.ST.HUNTER.on_bar_update, sb.ST, "ranged")
        check(ok, "an all-off tick does not error (" .. tostring(err) .. ")")
        eq(sb.calls.cast, 0, "the cast bar off means zero casting reads")
        eq(sb.calls.aura, 0, "the Rapid Fire and aspect options off mean zero aura scans")
        eq(sb.calls.in_range, 0, "the range helper off means zero spell-range reads")
        eq(sb.calls.distance, 0, "the range helper off means zero exact-distance reads")
        eq(sb.st.hunter_ui.cast_frame.shown, false, "the cast bar stays hidden")
        eq(sb.st.hunter_ui.range_helper.shown, false, "the range helper stays hidden")
        eq(sb.st.hunter_ui.rapid_fire_bar.shown, false, "the Rapid Fire bar stays hidden")
        eq(sb.st.hunter_ui.aspect_icon.shown, false, "the aspect icon stays hidden")
    end

    -- 14d) the Auto Shot window renders, hands over to a live cast, and the melee bars
    -- re-anchor while the cast bar is visible and restore when it hides.
    do
        local sb = build_ui({ ranged_start = -1.6, ranged_speed = 2 })
        sb.ST.HUNTER.post_init(sb.ST)
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        local ui = sb.st.hunter_ui

        check(sb.calls.cast > 0, "the cast bar reads the live cast every tick")
        eq(ui.cast_frame.shown, true, "the hidden Auto Shot window shows the cast bar")
        eq(ui.cast_frame.text.text, "Auto Shot 0.4", "the window label counts the remaining seconds")
        eq(ui.cast_frame.tint.shown, false, "the Auto Shot window carries no no-clip tint")
        local vertex = ui.cast_frame.bar.vertex
        check(vertex ~= nil and math.abs(vertex[1] - 0.35) < 1e-9
            and math.abs(vertex[2] - 0.65) < 1e-9 and math.abs(vertex[3] - 0.95) < 1e-9
            and math.abs(vertex[4] - 1.0) < 1e-9,
            "the window keeps the configured cast-bar colour (never the window colours)")
        near(sb.ST.ranged.hidden_window_start, -0.1,
            "the hidden window start is cached on the ranged state")
        near(sb.ST.ranged.hidden_window_duration, 0.5,
            "the hidden window duration is cached on the ranged state")

        -- An id-less live Auto Shot reading with a cold spell cache is still
        -- excluded (reference IsAutoShotSpell: id OR name): the window face
        -- persists instead of a bogus "Auto Shot" live cast.
        local saved_auto_name = ui.auto_shot_name
        ui.auto_shot_name = nil
        sb.live_cast = { name = "Auto Shot", start_ms = -500, end_ms = 1500 }
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.cast_frame.text.text, "Auto Shot 0.4",
            "an id-less Auto Shot with a cold cache keeps the window face")
        eq(ui.cast_frame.tint.shown, false,
            "an excluded Auto Shot carries no no-clip tint")
        ui.auto_shot_name = saved_auto_name
        sb.live_cast = nil
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")

        near(sb.mh_anchor.center_y, -129,
            "the mainhand re-anchors directly beneath the ranged bar while the cast bar shows")
        near(sb.oh_anchor.center_y, -145,
            "the offhand stacks beneath the mainhand")
        local restored_after_show = sb.mh_anchor.restored

        -- A live cast hands the bar over in the very next tick, no event needed.
        sb.live_cast = { name = "Steady Shot", spell_id = 34120, start_ms = -500, end_ms = 1500 }
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.cast_frame.text.text, "Steady Shot 1.5", "a live cast hands over to its own label")
        eq(ui.cast_frame.tint.shown, true, "an unsafe live cast carries the no-clip tint")
        local tint = ui.cast_frame.tint.color
        check(tint ~= nil and tint[1] == 1 and tint[2] == 0 and tint[3] == 0
            and math.abs(tint[4] - 0.4) < 1e-9, "the tint is the reference red for a clipping cast")

        sb.live_cast = nil
        sb.class_db.hunter_cast_bar_enabled = false
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.cast_frame.shown, false, "disabling the option hides the cast bar")
        eq(ui.melee_anchored, false, "hiding the cast bar restores the normal anchors")
        check(sb.mh_anchor.restored > restored_after_show,
            "the mainhand anchor was handed back to LibWindow")
        check(sb.oh_anchor.restored > restored_after_show,
            "the offhand anchor was handed back to LibWindow")
    end

    -- 14d2) a ranged re-anchor drops the previous cycle's cache: the cast bar
    -- hides instead of showing the dead window (the reference clears the cache
    -- on every StartSwing; the engine's START stamp is the re-anchor here).
    do
        local sb = build_ui({ ranged_start = -1.6, ranged_speed = 2 })
        sb.ST.HUNTER.post_init(sb.ST)
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        local ui = sb.st.hunter_ui
        eq(ui.cast_frame.shown, true, "the live window shows the cast bar first")
        sb.ST.ranged.start = 0.0
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.cast_frame.shown, false,
            "a re-anchored cycle drops the previous window cache")
        eq(sb.ST.ranged.hidden_window_start, nil,
            "the re-anchor clears the cached window start")
        eq(sb.ST.ranged.hidden_window_duration, nil,
            "the re-anchor clears the cached window width")
    end

    -- 14e) the range helper colour follows range_state's priority ladder.
    do
        local sb = build_ui({ has_target = true, in_range = { ["Auto Shot"] = 1 } })
        sb.ST.HUNTER.post_init(sb.ST)
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        local helper = sb.st.hunter_ui.range_helper
        check(helper.shown == true, "the range helper shows with an attackable target")
        check(helper.tex.color ~= nil and math.abs(helper.tex.color[3] - 1.00) < 1e-9,
            "a ranged-only reading paints the ranged colour")

        -- 7 yd = just outside melee, inside the reference's ~10 yd trade band.
        sb.target_yards = 7
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(helper.tex.color[1], 0.98, "a 7 yd reading paints the sweet-spot colour")

        sb.in_range = { ["Wing Clip"] = 1 }
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(helper.tex.color[2], 0.85, "melee range wins over the sweet spot")

        -- 25 yd: known, but outside the 5 < yards <= 10 band.
        sb.in_range = { ["Auto Shot"] = 0 }
        sb.target_yards = 25
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(helper.tex.color[1], 0.50, "a known distance outside every band paints out of range")

        -- Every probe answerless (nil) hides the strip instead of guessing.
        sb.in_range = nil
        sb.target_yards = nil
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(helper.shown, false, "every probe unknown hides the strip")

        sb.in_range = { ["Auto Shot"] = 1 }
        sb.target_yards = 12
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(helper.shown, true, "an answering probe brings the strip back")

        sb.ST.has_attackable_target = false
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(helper.shown, false, "no attackable target hides the strip")
    end

    -- 14f) Rapid Fire bar and aspect icon render from the player's helpful auras, with
    -- the scans throttled on the api.get_time() clock.
    do
        local sb = build_ui({ auras = {
            { name = "Rapid Fire", spell_id = 3045, duration = 15, expiration = 10 },
        } })
        sb.ST.HUNTER.post_init(sb.ST)
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        local ui = sb.st.hunter_ui
        check(sb.calls.aura > 0, "the aura scans ran")
        eq(ui.rapid_fire_bar.shown, true, "the Rapid Fire bar shows while the aura is up")
        eq(ui.rapid_fire_bar.label.text, "10s", "the Rapid Fire label counts whole seconds")
        eq(ui.aspect_icon.shown, false, "no aspect aura means no aspect icon")

        -- The next scan is throttled to 0.1 s; the changed aura list is only seen after
        -- the clock has advanced (now = 1 s), and the aspect icon follows the new aura.
        sb.now = 1
        sb.auras = {
            { name = "Aspect of the Cheetah", spell_id = 5118, duration = 60, expiration = 61 },
        }
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.rapid_fire_bar.shown, false, "a dropped Rapid Fire aura hides the bar")
        eq(ui.aspect_icon.shown, true, "the aspect aura shows the icon")
        eq(ui.aspect_icon.tex.texture, "icon_5118", "the icon uses the aspect's own texture")

        sb.auras = nil
        sb.now = 2
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.aspect_icon.shown, false, "a dropped aspect hides the icon")
    end

    -- 14g) without a ranged bar frame the cast bar still anchors (UIParent centre) and
    -- the whole set stays error-free.
    do
        local sb = build_ui({
            no_ranged_frame = true,
            live_cast = { name = "Aimed Shot", spell_id = 19434, start_ms = -500, end_ms = 2000 },
        })
        local ok, err = pcall(sb.ST.HUNTER.post_init, sb.ST)
        check(ok, "post_init without a ranged bar frame does not error (" .. tostring(err) .. ")")
        eq(sb.st.hunter_ui.ready, true, "the widget set still builds without a ranged bar frame")
        local ok2, err2 = pcall(sb.ST.HUNTER.on_bar_update, sb.ST, "ranged")
        check(ok2, "the ranged tick without a ranged bar frame does not error ("
            .. tostring(err2) .. ")")
        local ui = sb.st.hunter_ui
        eq(ui.cast_frame.shown, true, "a live cast shows the fallback-anchored cast bar")
        eq(ui.cast_frame.text.text, "Aimed Shot 2.0", "the fallback cast bar keeps its live label")
        local first_point = ui.cast_frame.points[1]
        eq(first_point and first_point.point, "CENTER",
            "the fallback cast bar anchors at the UIParent centre")
        check(sb.calls.in_range > 0, "the range helper still probes on the fallback path")
    end

    -- 14h) the movement-safe cast zone: geometry, the safe/unsafe colour ladder, the
    -- threshold marker and the off-gate.
    do
        local sb = build_ui({ ranged_start = -1.6, ranged_speed = 2, world_ms = 100 })
        sb.class_db.hunter_cast_zone_enabled = true
        sb.ST.HUNTER.post_init(sb.ST)
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        local ui = sb.st.hunter_ui
        check(ui.cast_zone ~= nil, "the cast zone texture is created on the visuals frame")
        eq(ui.cast_zone.parent.name, "RangedVisualsFrame",
            "the cast zone parents to the ranged visuals frame")
        eq(ui.cast_zone.shown, true, "the cast zone shows with a live ranged cycle")
        -- 0.5 base + 0.1 latency = 0.6 s window over a 2 s cycle on a 275 px bar.
        near(ui.cast_zone.width, 0.3 * 275, "the zone width is the window fraction")
        near(ui.cast_zone.color[1], 0.2,
            "standing still with no stop stamp reads the safe green")
        near(ui.cast_zone.color[2], 0.78, "the safe green's second channel")
        eq(ui.cast_zone_marker.shown, true, "the threshold marker shows with the zone")
        near(ui.cast_zone_marker.points[1].x, 275 - 0.3 * 275 - 1.5,
            "the marker sits on the window boundary")

        -- Still moving: unsafe red.
        sb.ST.is_moving = true
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(ui.cast_zone.color[1], 1, "still moving reads the unsafe red")
        near(ui.cast_zone.color[2], 0, "the unsafe red's second channel")
        -- Stopped after the window opened (open = -1.6 + 2 - 0.6 = -0.2): still unsafe.
        sb.ST.is_moving = false
        sb.ST.last_stopped_moving_at = 0.5
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(ui.cast_zone.color[1], 1, "a late stop reads the unsafe red")
        -- Stopped at or before the open: safe again.
        sb.ST.last_stopped_moving_at = -0.3
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(ui.cast_zone.color[1], 0.2, "an early stop reads the safe green")

        -- No live ranged cycle: the zone hides rather than guessing.
        sb.ST.ranged.start = nil
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.cast_zone.shown, false, "no ranged cycle hides the zone")
        eq(ui.cast_zone_marker.shown, false, "no ranged cycle hides the marker")
        sb.ST.ranged.start = -1.6

        -- The off-gate hides the zone again.
        sb.class_db.hunter_cast_zone_enabled = false
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.cast_zone.shown, false, "the option off hides the zone")
        eq(ui.cast_zone_marker.shown, false, "the option off hides the marker")
    end

    -- 14i) the H6 pet badges: BW duration + glow window, Frenzy stacks, the throttle
    -- and the off-gates.
    do
        local sb = build_ui({
            auras = { { name = "Bestial Wrath", spell_id = 19574, duration = 18, expiration = 18 } },
            pet_auras = { { name = "Frenzy Effect", spell_id = 19615, count = 3, duration = 8, expiration = 8 } },
        })
        sb.class_db.hunter_bw_badge_enabled = true
        sb.class_db.hunter_frenzy_stacks_enabled = true
        sb.ST.HUNTER.post_init(sb.ST)
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        local ui = sb.st.hunter_ui
        eq(ui.bw_badge.shown, true, "the BW badge shows with the aura")
        eq(ui.bw_badge.tex.texture, "icon_19574", "the BW badge icon comes from the spell data")
        eq(ui.bw_badge.text.text, "18", "the BW countdown reads whole seconds at/above 3 s")
        eq(ui.bw_badge.glow.shown, false, "no glow outside the final 4 s")
        eq(ui.frenzy_badge.shown, true, "the Frenzy badge shows with the pet aura")
        eq(ui.frenzy_badge.tex.texture, "icon_19615", "the Frenzy badge icon from the spell data")
        eq(ui.frenzy_badge.text.text, "3", "the Frenzy stack count")

        -- Inside the final 4 s the glow shows; below 3 s the text switches to decimals.
        sb.auras = { { name = "Bestial Wrath", spell_id = 19574, duration = 18, expiration = 3.4 } }
        sb.now = 0.25
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.bw_badge.glow.shown, true, "the gold glow shows inside the final 4 s")
        eq(ui.bw_badge.text.text, "3", "3.15 s remaining still reads whole seconds")
        sb.auras = { { name = "Bestial Wrath", spell_id = 19574, duration = 18, expiration = 2.7 } }
        sb.now = 0.5
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.bw_badge.text.text, "2.2", "below 3 s the countdown reads one decimal")

        -- The 0.2 s throttle: a dropped aura is only seen on the next poll.
        sb.auras = nil
        sb.pet_auras = nil
        sb.now = 0.55
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.bw_badge.shown, true, "the throttled tick keeps the stale badge")
        eq(ui.frenzy_badge.shown, true, "the throttled tick keeps the stale Frenzy badge")
        sb.now = 0.75
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.bw_badge.shown, false, "the next poll sees the dropped BW aura")
        eq(ui.bw_badge.glow.shown, false, "a hidden BW badge hides its glow")
        eq(ui.frenzy_badge.shown, false, "the next poll sees the dropped Frenzy aura")

        -- A single stack reads its count; a client without a count shows no text.
        sb.pet_auras = { { name = "Frenzy Effect", spell_id = 19615, count = 1, duration = 8, expiration = 9 } }
        sb.now = 1.0
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.frenzy_badge.shown, true, "the Frenzy badge shows at one stack")
        eq(ui.frenzy_badge.text.text, "1", "a single stack reads 1")
        sb.pet_auras = { { name = "Frenzy Effect", spell_id = 19615, duration = 8, expiration = 9.2 } }
        sb.now = 1.25
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.frenzy_badge.text.shown, false, "a client without a count shows no number")

        -- Off-gates: neither badge scans (the 14c all-off tick already pins the zero
        -- aura reads; this pins the per-widget hides).
        sb.class_db.hunter_bw_badge_enabled = false
        sb.class_db.hunter_frenzy_stacks_enabled = false
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.bw_badge.shown, false, "the BW option off hides the badge")
        eq(ui.frenzy_badge.shown, false, "the Frenzy option off hides the badge")
    end

    -- 14j) Readiness forces the Rapid Fire scan throttle (the reference's
    -- ForceHunterRapidFireRefresh translated to this architecture).
    do
        local sb = build_ui({
            auras = { { name = "Rapid Fire", spell_id = 3045, duration = 15, expiration = 5 } },
        })
        sb.ST.HUNTER.post_init(sb.ST)
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        local ui = sb.st.hunter_ui
        eq(ui.rapid_fire_bar.shown, true, "the Rapid Fire bar shows before the refresh")
        -- The aura drops; inside the 0.1 s throttle the bar keeps its state.
        sb.auras = nil
        sb.now = 0.05
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.rapid_fire_bar.shown, true, "the throttled tick keeps the stale bar")
        -- Readiness forces the next scan immediately.
        ui.force_rapid_fire_refresh(sb.ST)
        eq(ui.rf_scan_at, nil, "the forced refresh clears the scan throttle")
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        eq(ui.rapid_fire_bar.shown, false, "the forced tick sees the dropped aura")
    end
        -- 14k) H1 target warning: option gate, show truth, unknown hides.
    do
        local function built_ui(opts)
            local sb = build_ui(opts)
            sb.ST.HUNTER.post_init(sb.ST)
            sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
            return sb
        end

        -- The widget is built with the set and starts hidden.
        do
            local sb = built_ui({ ranged_start = 0, ranged_speed = 3.0 })
            check(sb.st.hunter_ui.target_warning ~= nil, "H1: the warning label is built")
            eq(sb.st.hunter_ui.target_warning:IsShown(), false, "H1: the label starts hidden")
        end

        -- Off (nil = off): no unit reads at all, even while targeted.
        do
            local sb = built_ui({
                ranged_start = 0, ranged_speed = 3.0,
                unit_exists = function() error("H1: the disabled widget must not read units") end,
                unit_is_unit = function() error("H1: the disabled widget must not read units") end,
            })
            local ok, err = pcall(sb.ST.HUNTER.on_bar_update, sb.ST, "ranged")
            check(ok, "H1: the disabled widget ticks cleanly (" .. tostring(err) .. ")")
            eq(sb.st.hunter_ui.target_warning:IsShown(), false, "H1: nil = off hides the label")
        end

        -- On and targeted: shown.
        do
            local sb = built_ui({
                ranged_start = 0, ranged_speed = 3.0,
                target_warning_enabled = true,
                unit_exists = function() return true end,
                unit_is_unit = function() return true end,
            })
            sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
            eq(sb.st.hunter_ui.target_warning:IsShown(), true, "H1: targeted shows the label")
        end

        -- On but looking elsewhere, or unknown: hidden.
        do
            local sb = built_ui({
                ranged_start = 0, ranged_speed = 3.0,
                target_warning_enabled = true,
                unit_exists = function() return true end,
                unit_is_unit = function() return false end,
            })
            sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
            eq(sb.st.hunter_ui.target_warning:IsShown(), false, "H1: not targeted hides the label")
            local sb2 = built_ui({
                ranged_start = 0, ranged_speed = 3.0,
                target_warning_enabled = true,
            })
            sb2.ST.HUNTER.on_bar_update(sb2.ST, "ranged")
            eq(sb2.st.hunter_ui.target_warning:IsShown(), false, "H1: unknown hides the label")
        end
    end

    -- Readiness 2x readout (hunter_open §1): the same RF bar + label, toggle-gated
    -- nil = off (no new widget, so the build census holds).
    do
        local ui_sb = build_ui()
        ui_sb.ST.HUNTER.post_init(ui_sb.ST)
        ui_sb.ST.HUNTER.on_spellcast_succeeded(ui_sb.ST, "player", nil, 23989)
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        local rf = ui_sb.st.hunter_ui.rapid_fire_bar
        check(rf.shown == false, "readiness: the unset toggle hides the bar with no aura (legacy)")
        ui_sb.class_db.hunter_readiness_badge_enabled = true
        ui_sb.now = 0.2
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        check(rf.shown == true, "readiness: the toggle on shows the bar while the window is live")
        eq(rf.label.text, "2x", "readiness: the bar reads 2x while the window is live")
        -- A live RF aura hands the bar back to the countdown.
        ui_sb.auras = { { name = "Rapid Fire", spell_id = 3045, duration = 15, expiration = 15 } }
        ui_sb.now = 5
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        eq(rf.label.text, "10s", "readiness: a live RF aura restores the countdown")
        -- An elapsed window hides the bar again (no aura).
        ui_sb.auras = nil
        ui_sb.now = 61
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        check(rf.shown == false, "readiness: an elapsed window hides the bar")
    end

    -- OOM Viper badge (hunter_open §2): lazily created only while enabled (nil =
    -- off creates nothing, so the build census holds), VIPER text while OOM.
    do
        local ui_sb = build_ui({ mana = { cur = 3, max = 100 }, known_spells = { [34074] = true } })
        ui_sb.ST.HUNTER.post_init(ui_sb.ST)
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        eq(ui_sb.st.hunter_ui.oom_badge, nil, "OOM: the unset toggle creates no widget (census holds)")
        ui_sb.class_db.hunter_oom_viper_badge_enabled = true
        ui_sb.now = 0.3
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        local badge = ui_sb.st.hunter_ui.oom_badge
        check(badge ~= nil, "OOM: the enabled tick creates the badge lazily")
        check(badge.shown == true, "OOM: low mana shows the badge")
        eq(badge.text.text, "VIPER", "OOM: the badge prompts the swap")
        -- An active Viper hides the badge; high or unknown mana hides it too.
        ui_sb.auras = { { name = "Aspect of the Viper", spell_id = 34074, duration = 60, expiration = 100 } }
        ui_sb.now = 0.6
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        check(badge.shown == false, "OOM: an active Viper hides the badge")
        local rich = build_ui({ mana = { cur = 80, max = 100 }, known_spells = { [34074] = true } })
        rich.ST.HUNTER.post_init(rich.ST)
        rich.class_db.hunter_oom_viper_badge_enabled = true
        rich.ST.HUNTER.on_bar_update(rich.ST, "ranged")
        check(rich.st.hunter_ui.oom_badge == nil or rich.st.hunter_ui.oom_badge.shown == false,
            "OOM: high mana never shows the badge")
        local strange = build_ui({ known_spells = { [34074] = true } })
        strange.ST.HUNTER.post_init(strange.ST)
        strange.class_db.hunter_oom_viper_badge_enabled = true
        strange.ST.HUNTER.on_bar_update(strange.ST, "ranged")
        check(strange.st.hunter_ui.oom_badge == nil or strange.st.hunter_ui.oom_badge.shown == false,
            "OOM: unknown mana never shows the badge")
    end

    -- LnL trap-proc badge (hunter_open §1): lazily created only while enabled
    -- (nil = off creates nothing, so the build census holds), LnL text while
    -- the trap-proc window is live.
    do
        local ui_sb = build_ui()
        ui_sb.auras = { { name = "Lock and Load", spell_id = 56344, duration = 22, expiration = 20 } }
        ui_sb.ST.HUNTER.post_init(ui_sb.ST)
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        eq(ui_sb.st.hunter_ui.lnl_badge, nil, "LnL: the unset toggle creates no widget (census holds)")
        ui_sb.class_db.hunter_lnl_badge_enabled = true
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        local badge = ui_sb.st.hunter_ui.lnl_badge
        check(badge ~= nil, "LnL: the enabled tick creates the badge lazily")
        check(badge.shown == true, "LnL: a live proc window shows the badge")
        eq(badge.text.text, "LnL", "LnL: the badge names the window")
        -- A spent window hides the badge again (past the rescan interval so the
        -- throttled probe re-reads).
        ui_sb.auras = {}
        ui_sb.now = 1
        ui_sb.ST.HUNTER.on_bar_update(ui_sb.ST, "ranged")
        check(badge.shown == false, "LnL: a spent window hides the badge")
    end

    -- Trap badge (hunter_wa_map §6 placed-phase display, nil = off):
    -- lazily created only while enabled (nil = off creates no widget, so the
    -- build census holds); countdown while a trap is armed.
    do
        local tui = build_ui()
        tui.ST.HUNTER.post_init(tui.ST)
        tui.ST.HUNTER.on_spellcast_succeeded(tui.ST, "player", nil, 1499)
        tui.ST.HUNTER.on_bar_update(tui.ST, "ranged")
        eq(tui.st.hunter_ui.trap_badge, nil, "trap badge: the unset toggle creates no widget (census holds)")
        tui.class_db.hunter_trap_badge_enabled = true
        tui.ST.HUNTER.on_bar_update(tui.ST, "ranged")
        local tbadge = tui.st.hunter_ui.trap_badge
        check(tbadge ~= nil, "trap badge: the enabled tick creates the badge lazily")
        check(tbadge.shown == true, "trap badge: an armed trap shows the badge")
        eq(tbadge.text.text, "60s", "trap badge: the countdown reads whole seconds")
        -- The throttled re-poll counts down; an expired window hides the badge.
        tui.now = 1
        tui.ST.HUNTER.on_bar_update(tui.ST, "ranged")
        eq(tbadge.text.text, "59s", "trap badge: the re-poll counts down")
        tui.now = 61
        tui.ST.HUNTER.on_bar_update(tui.ST, "ranged")
        check(tbadge.shown == false, "trap badge: an expired window hides the badge")
        -- Off again hides; unknown (no trap) hides too.
        tui.class_db.hunter_trap_badge_enabled = nil
        tui.ST.HUNTER.on_bar_update(tui.ST, "ranged")
        check(tbadge.shown == false, "trap badge: the toggle off hides the badge")
    end
end

--=========================================================================================
-- 15) New option keys: defaults and widgets exist in both directions
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local presets = read("config_presets.lua")
    local hunter_defaults = presets:match("ST%.HUNTER%.defaults%s*=%s*{(.-)ST%.MAGE%.defaults")
    check(hunter_defaults ~= nil, "the HUNTER defaults block is still found in config_presets.lua")
    hunter_defaults = hunter_defaults or ""

    local options = read("option_tables.lua")
    local hunter_opts = options:match(
        "function ST%.class_opts_funcs%.HUNTER%((.-)function ST%.class_opts_funcs%.")
    check(hunter_opts ~= nil, "the HUNTER options function is still found in option_tables.lua")
    hunter_opts = hunter_opts or ""

    local toggles = {
        "hunter_cast_bar_enabled", "hunter_range_helper_enabled",
        "hunter_rapid_fire_bar_enabled", "hunter_aspect_icon_enabled",
    }
    for i = 1, #toggles do
        local key = toggles[i]
        check(hunter_defaults:find(key .. "%s*=%s*true") ~= nil,
            key .. " ships true in the HUNTER defaults")
        local widget = hunter_opts:match("%f[%w_]" .. key .. "%s*=%s*{(.-)}")
        check(widget ~= nil and widget:find("type%s*=%s*\"toggle\"") ~= nil,
            key .. " is a toggle in the HUNTER options")
    end

    check(hunter_defaults:find("hunter_cast_bar_height%s*=%s*15%s*,") ~= nil,
        "hunter_cast_bar_height ships 15 in the HUNTER defaults")
    local height = hunter_opts:match("hunter_cast_bar_height%s*=%s*{(.-)}")
    check(height ~= nil and height:find("type%s*=%s*\"range\"") ~= nil,
        "hunter_cast_bar_height is a range widget in the HUNTER options")

    check(hunter_defaults:find(
        "hunter_cast_bar_color%s*=%s*{%s*0%.35%s*,%s*0%.65%s*,%s*0%.95%s*,%s*1%.0%s*}") ~= nil,
        "hunter_cast_bar_color ships the 0-1 default in the HUNTER defaults")
    local color = hunter_opts:match("hunter_cast_bar_color%s*=%s*{(.-)}")
    check(color ~= nil and color:find("type%s*=%s*\"color\"") ~= nil,
        "hunter_cast_bar_color is a colour picker in the HUNTER options")
    check(color ~= nil and color:find("get%s*=%s*\"hunter_cast_color_getter\"") ~= nil
        and color:find("set%s*=%s*\"hunter_cast_color_setter\"") ~= nil,
        "the cast-bar colour uses the 0-1 storage get/set pair")
end

--=========================================================================================
-- 16) Wrath/SoD spell-table hygiene: the new rank families resolve, the Era
--     Aimed table stays vanilla-only
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
    local source = f:read("*a")
    f:close()

    local function strip_comments(text)
        local out, i, n, quote = {}, 1, #text, nil
        while i <= n do
            local c = text:sub(i, i)
            local two = text:sub(i, i + 1)
            if quote then
                out[#out + 1] = c
                if c == "\\" then
                    out[#out + 1] = text:sub(i + 1, i + 1)
                    i = i + 2
                else
                    if c == quote then quote = nil end
                    i = i + 1
                end
            elseif two == "--" then
                local _, level_end = text:find("^%-%-%[(=*)%[", i)
                if level_end then
                    local _, _, level = text:find("^%-%-%[(=*)%[", i)
                    local close = "]" .. level .. "]"
                    local stop = text:find(close, level_end, true)
                    i = (stop and (stop + #close - 1)) or (n + 1)
                else
                    local nl = text:find("\n", i)
                    i = nl or (n + 1)
                end
            else
                if c == '"' or c == "'" then quote = c end
                out[#out + 1] = c
                i = i + 1
            end
        end
        return table.concat(out)
    end

    local code = strip_comments(source)
    local function table_ids(name)
        local block = code:match("local%s+" .. name .. "%s*=%s*get_tab%s*%((.-)%)")
        check(type(block) == "string", "the " .. name .. " table is found in the source")
        block = block or ""
        local ids = {}
        for n in block:gmatch("%d+") do ids[tonumber(n)] = true end
        return ids
    end
    local function table_count(ids)
        local count = 0
        for _ in pairs(ids) do count = count + 1 end
        return count
    end

    local kill_shot = table_ids("kill_shot_ids")
    eq(table_count(kill_shot), 3, "the Kill Shot table holds both wotlk ids and the SoD rune")
    eq(kill_shot[53351], true, "the Kill Shot table keeps 53351")
    eq(kill_shot[34104], true, "the Kill Shot table keeps the older 34104")
    eq(kill_shot[409593], true, "the Kill Shot table keeps the SoD rune 409593 (the APL utility lane)")

    local chimera_wrath = table_ids("chimera_shot_wrath_ids")
    eq(table_count(chimera_wrath), 1, "the Wrath Chimera table holds its single id")
    eq(chimera_wrath[53209], true, "the Wrath Chimera table keeps 53209")

    local explosive = table_ids("explosive_shot_ids")
    eq(table_count(explosive), 3, "the Explosive table holds the base plus the downrank pair")
    eq(explosive[53301], true, "the Explosive table keeps 53301")
    eq(explosive[60052], true, "the Explosive table keeps the SIM-CONFIRMED R3 60052")
    eq(explosive[60053], true, "the Explosive table keeps the SIM-CONFIRMED R4 60053")

    local aimed_wrath = table_ids("aimed_shot_wrath_ids")
    eq(table_count(aimed_wrath), 2, "the Wrath Aimed table holds two ranks")
    eq(aimed_wrath[49050], true, "the Wrath Aimed table keeps 49050")
    eq(aimed_wrath[27065], true, "the Wrath Aimed table keeps the TBC 27065")

    local arcane = table_ids("arcane_shot_ids")
    eq(table_count(arcane), 3, "the Arcane table holds three ranks")
    eq(arcane[49045], true, "the Arcane table keeps 49045")
    eq(arcane[27019], true, "the Arcane table keeps the TBC 27019")
    eq(arcane[14287], true, "the Arcane table keeps the SoD/Forever 14287 (the APL utility lane)")

    local chimera_sod = table_ids("chimera_shot_sod_ids")
    eq(table_count(chimera_sod), 1, "the SoD Chimera table holds the rune id")
    eq(chimera_sod[409433], true, "the SoD Chimera table keeps 409433")

    -- The Era Aimed table stays vanilla-only: the Wrath ranks live in
    -- aimed_shot_wrath_ids, so the Era weave can never read a Wrath rank.
    local aimed = table_ids("aimed_shot_ids")
    eq(table_count(aimed), AIMED_RANKS, "the Era Aimed table still holds six ranks")
    check(aimed[49050] ~= true and aimed[27065] ~= true,
        "the Era Aimed table holds no Wrath rank (49050/27065 live elsewhere)")
    check(chimera_wrath[409433] ~= true and chimera_sod[53209] ~= true,
        "the Wrath and SoD Chimera tables never share an id")
end

--=========================================================================================
-- 17) Family slot sets, the knowledge-gated resolve and the SoD slot swap
--=========================================================================================
-- The guide slot set is picked by family at load (Wrath six, Era three, base six
-- elsewhere); the Wrath/SoD prompt ranks resolve at post_init only when the
-- player KNOWS them (data presence alone never prompts a talent). Fixtures spell
-- data below mirrors a client spell cache; known_spells mirrors the spellbook.
do
    local WRATH_SPELLS = {
        [53351] = "Kill Shot", [53209] = "Chimera Shot",
        [53301] = "Explosive Shot", [49050] = "Aimed Shot",
        [49045] = "Arcane Shot", [49052] = "Steady Shot", [48996] = "Raptor Strike",
    }
    local ERA_SPELLS = {
        [20904] = "Aimed Shot", [14265] = "Raptor Strike",
        [14290] = "Multi-Shot", [409433] = "Chimera Shot",
    }
    local function spell_info(map)
        return function(id)
            if map[id] then
                return map[id], nil, "icon_" .. id, 0, 0, 0, id
            end
            return nil
        end
    end
    local function slot_keys(ST)
        local keys = {}
        for i = 1, #ST.HUNTER.guide.slots do keys[#keys + 1] = ST.HUNTER.guide.slots[i].key end
        return table.concat(keys, ",")
    end

    -- The slot set is picked at load, before any post_init resolve. Every set
    -- now covers the actions its family's APL asks for (the APL UTILITY layer
    -- included), so the guide can light every line the engine can emit.
    eq(slot_keys(build({ project = 11 }).ST),
        "kill_shot,chimera,explosive,aimed,arcane,steady,aspect_viper,aspect_dragonhawk,"
            .. "silencing_shot,serpent,explosive_trap,multi,black_arrow",
        "WRATH loads the thirteen-slot Wrath set (the six arms plus the APL's utility spine)")
    eq(slot_keys(build({ project = 2 }).ST), "aimed,raptor,multi,rapid_fire,serpent",
        "ERA loads the Era set with the Rapid Fire and Serpent rows")
    eq(slot_keys(build({ project = 5 }).ST),
        "steady,raptor,kill_command,multi,bestial_wrath,rapid_fire,aspect_viper,aspect_hawk",
        "TBC keeps the base set plus its mana-swap rows")
    eq(slot_keys(build({ project = 14 }).ST),
        "steady,raptor,kill_command,multi,bestial_wrath,rapid_fire",
        "Cata keeps the frozen base set")

    -- Wrath MM: Chimera learned -> chimera_known, Explosive dark.
    do
        local sb = build({ project = 11, GetSpellInfo = spell_info(WRATH_SPELLS),
            known_spells = { [53209] = true, [49052] = true, [49050] = true } })
        local ST = sb.ST
        ST.HUNTER.post_init(ST)
        local slots = ST.HUNTER.guide.slots
        eq(#slots, 13, "Wrath MM declares the thirteen slots its APL asks for")
        eq(slots[2].spell_id, 53209, "Wrath MM resolves the Chimera icon")
        eq(slots[1].spell_id, 53351, "an unlearned Kill Shot keeps the rank-1 fallback")
        local gathered = ST.HUNTER.gather_guide_inputs(ST, {})
        eq(gathered.chimera_known, true, "Wrath MM: Chimera is known (the MM detector)")
        eq(gathered.explosive_known, false, "Wrath MM: Explosive is unknown")
        eq(gathered.killshot_known, false, "an unlearned Kill Shot never prompts")
        eq(gathered.steady_known, true, "Steady stays data-gated (trained by all)")
    end

    -- Wrath SV: Explosive learned -> explosive_known, Chimera dark.
    do
        local sb = build({ project = 11, GetSpellInfo = spell_info(WRATH_SPELLS),
            known_spells = { [53301] = true, [49052] = true } })
        local ST = sb.ST
        ST.HUNTER.post_init(ST)
        eq(ST.HUNTER.guide.slots[3].spell_id, 53301, "Wrath SV resolves the Explosive icon")
        local gathered = ST.HUNTER.gather_guide_inputs(ST, {})
        eq(gathered.explosive_known, true, "Wrath SV: Explosive is known (the SV detector)")
        eq(gathered.chimera_known, false, "Wrath SV: Chimera is unknown")
    end

    -- Wrath SV downrank coverage (the sim's 434 pair, R4 60053 / R3 60052):
    -- the highest rank the client knows resolves, so a downranking client
    -- prompts through its own rank.
    do
        local downrank_spells = {
            [53301] = "Explosive Shot", [60052] = "Explosive Shot",
            [60053] = "Explosive Shot", [49052] = "Steady Shot",
        }
        local full = build({ project = 11, GetSpellInfo = spell_info(downrank_spells),
            known_spells = { [60053] = true, [49052] = true } })
        full.ST.HUNTER.post_init(full.ST)
        eq(full.ST.HUNTER.guide.slots[3].spell_id, 60053,
            "Wrath SV resolves the R4 icon when the client knows it")
        eq(full.ST.HUNTER.gather_guide_inputs(full.ST, {}).explosive_known, true,
            "Wrath SV: the R4 rank prompts")
        -- Data alone never prompts (the knowledge gate): a client whose cache
        -- stops at R3 resolves R3, never the unknown R4.
        local r3_spells = {
            [53301] = "Explosive Shot", [60052] = "Explosive Shot",
            [49052] = "Steady Shot",
        }
        local partial = build({ project = 11, GetSpellInfo = spell_info(r3_spells),
            known_spells = { [60052] = true, [49052] = true } })
        partial.ST.HUNTER.post_init(partial.ST)
        eq(partial.ST.HUNTER.guide.slots[3].spell_id, 60052,
            "Wrath SV resolves the R3 icon when the cache stops there")
        eq(partial.ST.HUNTER.gather_guide_inputs(partial.ST, {}).explosive_known, true,
            "Wrath SV: the R3 rank prompts")
    end

    -- Wrath data without knowledge (levelling): no prompt rank resolves, the
    -- Steady filler alone survives.
    do
        local sb = build({ project = 11, GetSpellInfo = spell_info(WRATH_SPELLS) })
        local ST = sb.ST
        ST.HUNTER.post_init(ST)
        local gathered = ST.HUNTER.gather_guide_inputs(ST, {})
        eq(gathered.chimera_known, false, "unlearned Chimera never prompts (data is not enough)")
        eq(gathered.explosive_known, false, "unlearned Explosive never prompts")
        eq(gathered.killshot_known, false, "unlearned Kill Shot never prompts")
        eq(gathered.wrath_aimed_known, false, "unlearned Aimed never prompts")
        eq(gathered.arcane_known, false, "unlearned Arcane never prompts")
        eq(gathered.steady_known, true, "Steady still resolves from data alone")
        eq(gathered.target_hp_frac, nil, "no Kill Shot rank means no health probe either")
    end

    -- SoD (ERA token, rune learned): the Era set swaps to the SoD set.
    do
        local sb = build({ project = 2, GetSpellInfo = spell_info(ERA_SPELLS),
            known_spells = { [409433] = true } })
        local ST = sb.ST
        ST.HUNTER.post_init(ST)
        eq(slot_keys(ST),
            "chimera,aimed,raptor,multi,rapid_fire,bestial_wrath,kill_shot,raptor_strike,"
                .. "wyvern_strike,aspect_viper,arcane,aspect_falcon,wing_clip",
            "SoD swaps the Era set to the SoD set (the APL's utility spine included)")
        eq(ST.HUNTER.guide.slots[1].spell_id, 409433, "SoD resolves the Chimera rune icon")
        -- The SoD client HAS the Bestial Wrath (the 1.15.9 client's own spell data
        -- maps 19574 to the Beast Mastery skill line), so the SoD set declares the
        -- slot the Era-base set does not - and both surfaces carry the same id.
        eq(ST.HUNTER.guide.slots[6].key, "bestial_wrath",
            "SoD declares the Bestial Wrath slot the Era-base set drops")
        eq(ST.HUNTER.guide.slots[6].spell_id, 19574,
            "the SoD Bestial Wrath slot carries the client's own rank")
        local gathered = ST.HUNTER.gather_guide_inputs(ST, {})
        eq(gathered.chimera_known, true, "SoD: the learned rune weaves")
        eq(gathered.aimed_known, true, "SoD keeps the Era Aimed weave below Chimera")
    end

    -- Every non-SoD shape keeps the plain Era set: rune in data but unlearned,
    -- and the rune learned on a non-Era family (the family gate).
    do
        local unlearned = build({ project = 2, GetSpellInfo = spell_info(ERA_SPELLS) })
        unlearned.ST.HUNTER.post_init(unlearned.ST)
        eq(slot_keys(unlearned.ST), "aimed,raptor,multi,rapid_fire,serpent",
            "Era without the rune keeps the plain Era set")
        eq(unlearned.ST.HUNTER.gather_guide_inputs(unlearned.ST, {}).chimera_known, false,
            "Era without the rune never weaves Chimera")

        local tbc = build({ project = 5, GetSpellInfo = spell_info(ERA_SPELLS),
            known_spells = { [409433] = true } })
        tbc.ST.HUNTER.post_init(tbc.ST)
        eq(slot_keys(tbc.ST),
            "steady,raptor,kill_command,multi,bestial_wrath,rapid_fire,aspect_viper,aspect_hawk",
            "TBC never takes the SoD set even with the rune known")
    end
end

--=========================================================================================
-- H-HUD-1: the Era HUD ships the live slots (no dead Steady/KC) - and the pick is
-- BUILD-aware. The Era-BASE game never uses the 2.1 Bestial Wrath talent, but the
-- SoD build of the SAME 1.15.9 client HAS the spell (that client's own spell data
-- maps 19574 to the Beast Mastery skill line), so the SoD build keeps the slot.
-- bench/rogue_hunter_eratbc_2026-10-19.md §5. Same descriptors, same order.
--
-- The pick is decided at post_init (the class's own SoD probe - the Chimera Shot
-- rune), so every measurement below is taken AFTER the decision: the shipped
-- state, not the load-time one.
--=========================================================================================
do
    local function hud_keys(ST)
        local keys = {}
        for i = 1, #ST.HUNTER.HUD_SLOTS do keys[#keys + 1] = ST.HUNTER.HUD_SLOTS[i].key end
        return table.concat(keys, ",")
    end
    local function hud_slot(ST, key)
        for i = 1, #ST.HUNTER.HUD_SLOTS do
            if ST.HUNTER.HUD_SLOTS[i].key == key then return ST.HUNTER.HUD_SLOTS[i] end
        end
        return nil
    end
    eq(hud_keys(build({ project = 5 }).ST),
        "steady,raptor,kill_command,multi,bestial_wrath,rapid_fire,aimed,trinket1,trinket2",
        "TBC keeps the nine-slot HUD set")
    -- The Era-BASE build (the SoD rune is not known): the Bestial Wrath is dropped.
    local era = build({ project = 2 })
    era.ST.HUNTER.post_init(era.ST)
    eq(#era.ST.HUNTER.HUD_SLOTS, 6, "Era HUD: six live slots (three dead filtered)")
    eq(hud_keys(era.ST), "raptor,multi,rapid_fire,aimed,trinket1,trinket2",
        "Era HUD: only the live slots ship, guide order kept")
    local dead_ok = true
    for i = 1, #era.ST.HUNTER.HUD_SLOTS do
        local k = era.ST.HUNTER.HUD_SLOTS[i].key
        if k == "steady" or k == "kill_command" or k == "bestial_wrath" then dead_ok = false end
    end
    check(dead_ok, "Era HUD: no dead slot ships")
    -- The SoD build (the Chimera Shot rune known): the same client HAS the Bestial
    -- Wrath, so the slot ships there - carrying the client's own id.
    local sod = build({ project = 2,
        known_spells = { [409433] = true },
        known = { [409433] = true, [19574] = true } })
    sod.ST.HUNTER.post_init(sod.ST)
    eq(hud_keys(sod.ST), "raptor,multi,bestial_wrath,rapid_fire,aimed,trinket1,trinket2",
        "SoD keeps the Bestial Wrath slot the Era-base build drops")
    eq(#sod.ST.HUNTER.HUD_SLOTS, 7, "SoD HUD: seven live slots (the Bestial Wrath included)")
    local sod_bw = hud_slot(sod.ST, "bestial_wrath")
    check(sod_bw ~= nil, "SoD HUD: the Bestial Wrath slot ships")
    eq(sod_bw and sod_bw.spell, 19574,
        "SoD HUD: the Bestial Wrath slot carries the SoD client's own rank")
    -- The guide's SoD slot set declares the same slot with the same id: the two
    -- surfaces cannot disagree about which spells the running build has.
    local sod_guide_bw = nil
    for i = 1, #sod.ST.HUNTER.guide.slots do
        if sod.ST.HUNTER.guide.slots[i].key == "bestial_wrath" then
            sod_guide_bw = sod.ST.HUNTER.guide.slots[i]
        end
    end
    check(sod_guide_bw ~= nil, "SoD guide: the Bestial Wrath slot is declared")
    eq(sod_guide_bw and sod_guide_bw.spell_id, sod_bw and sod_bw.spell,
        "SoD: the guide and the HUD carry the same Bestial Wrath id")
end

--=========================================================================================
-- H-HUD-2: the HUD's Steady Shot id is FAMILY-CORRECT (the release-gate blocker
-- B2). The HUD used to carry ONE family-blind id (56641 - the vanilla rank),
-- which does not exist on the TBC client at all: the slot resolved to nothing
-- there (no name, no icon) and the suite never noticed, because it pinned the
-- slot KEYS and never a slot's id. bench/rogue_hunter_eratbc_2026-10-19.md §5
-- (H-HUD-2, settled by the corpus correction of 2026-10-20),
-- bench/rotation_gap_vs_apl_2026-10-20.md §0.0 H3 (TBC) and H4 (Forever).
--=========================================================================================
do
    local function hud_slot(ST, key)
        for i = 1, #ST.HUNTER.HUD_SLOTS do
            if ST.HUNTER.HUD_SLOTS[i].key == key then
                return ST.HUNTER.HUD_SLOTS[i]
            end
        end
        return nil
    end
    local function hud_keys(ST)
        local keys = {}
        for i = 1, #ST.HUNTER.HUD_SLOTS do keys[#keys + 1] = ST.HUNTER.HUD_SLOTS[i].key end
        return table.concat(keys, ",")
    end

    -- (a) TBC: the Steady slot carries the TBC rank (34120), never the vanilla
    --     56641 that the TBC client does not have.
    local tbc = build({ project = 5 })
    local tbc_steady = hud_slot(tbc.ST, "steady")
    check(tbc_steady ~= nil, "TBC HUD: the Steady slot ships")
    eq(tbc_steady.spell, 34120, "TBC HUD: the Steady slot carries the TBC rank 34120")
    check(tbc_steady.spell ~= 56641,
        "TBC HUD: the Steady slot never carries the vanilla rank 56641")

    -- (b) WRATH: the slot carries the 3.x rank (49052) before the client's own
    --     rank resolves, and the client's own rank after it does.
    local wrath = build({ project = 11 })
    eq(hud_slot(wrath.ST, "steady").spell, 49052,
        "Wrath HUD: the Steady slot carries the WotLK rank 49052")
    local wsb = build({ project = 11, known = { [49052] = true } })
    wsb.ST.HUNTER.resolve_guide_icons()
    eq(hud_slot(wsb.ST, "steady").spell, 49052,
        "Wrath HUD: the Steady slot carries the WotLK rank once the client confirms it")
    local wsb2 = build({ project = 11, known = { [49051] = true } })
    wsb2.ST.HUNTER.resolve_guide_icons()
    eq(hud_slot(wsb2.ST, "steady").spell, 49051,
        "Wrath HUD: the client's own Steady rank re-points the HUD slot")

    -- (c) FOREVER: the client has NO Steady Shot at all (§0.0 H4), so the slot
    --     is filtered out - the same rule the Era pick follows.
    local forever = build({ project = 18 })
    eq(forever.st.family, "FOREVER", "the project-18 fixture reads the FOREVER token")
    eq(hud_slot(forever.ST, "steady"), nil,
        "Forever HUD: no Steady slot ships (the client has no Steady Shot)")
    eq(hud_keys(forever.ST),
        "raptor,multi,bestial_wrath,rapid_fire,aimed,trinket1,trinket2",
        "Forever HUD: the seven live slots ship in guide order")

    -- (d) ERA: unchanged - the Steady slot never shipped there.
    local era = build({ project = 2 })
    eq(hud_slot(era.ST, "steady"), nil, "Era HUD: no Steady slot ships (unchanged)")

    -- (e) The TBC-name / Era-id discipline holds for the HUD's own resolution:
    --     the TBC client resolves the Steady rank BY NAME and the Era client by
    --     ID - the same rule the guide slot follows (the class resolves the rank
    --     once and both surfaces read that verdict).
    local tbc_name = build({ project = 5, name_only_client = true, known = { [34120] = true } })
    tbc_name.spell_queries = {}
    tbc_name.ST.HUNTER.resolve_guide_icons()
    eq(hud_slot(tbc_name.ST, "steady").spell, 34120,
        "TBC HUD: the Steady rank resolves through the NAME path")
    local asked_by_name = false
    for i = 1, #tbc_name.spell_queries do
        if type(tbc_name.spell_queries[i]) == "string" then asked_by_name = true end
    end
    check(asked_by_name, "TBC HUD: the client is asked for the Steady rank by NAME")
    local era_id = build({ project = 2, known = { [56641] = true } })
    era_id.spell_queries = {}
    era_id.ST.HUNTER.resolve_guide_icons()
    local era_asked_by_name = false
    for i = 1, #era_id.spell_queries do
        if type(era_id.spell_queries[i]) == "string" then era_asked_by_name = true end
    end
    check(not era_asked_by_name, "Era HUD: the client is never asked for a rank by name")
    -- Even a client that DOES know the vanilla rank ships no Steady slot on Era
    -- (the Era pick is a family decision, not a spell-data probe).
    eq(hud_slot(era_id.ST, "steady"), nil,
        "Era HUD: no Steady slot ships even when the client knows the rank")
end

--=========================================================================================
-- H-HUD-3: EVERY HUD spell slot is family-correct (the residual filed in
-- bench/hunter_steady_family_2026-10-20.md §6.1). The Steady slot was the only
-- family-correct one; every other slot carried ONE family-blind id, so a slot
-- could point at a spell the running client does not have - the WotLK client has
-- no vanilla Aimed Shot 19434 as its own shot and no vanilla Multi-Shot 2643 or
-- Raptor Strike 2973 as its own ranks, the Forever client has no Kill Command at
-- all. The ids below are the client's OWN rank per family (the evidence of record
-- is bench/hunter_hud_family_2026-10-20.md §2).
--
-- The four pins of this block:
--   (1) the EFFECTIVE id per family per slot;
--   (2) the per-family slot COUNT (a slot the client cannot have is dropped);
--   (3) the dead-slot rule: the shipped keys are exactly the live ones;
--   (4) the guide and the HUD agree (one owner for both surfaces).
--=========================================================================================
do
    local function hud_by_key(ST)
        local by_key = {}
        for i = 1, #ST.HUNTER.HUD_SLOTS do
            by_key[ST.HUNTER.HUD_SLOTS[i].key] = ST.HUNTER.HUD_SLOTS[i]
        end
        return by_key
    end
    local function guide_by_key(ST)
        local by_key = {}
        for i = 1, #ST.HUNTER.guide.slots do
            by_key[ST.HUNTER.guide.slots[i].key] = ST.HUNTER.guide.slots[i]
        end
        return by_key
    end

    -- The ERA family is picked per BUILD: the Era-BASE game drops the Bestial
    -- Wrath, the SoD build of the same 1.15.9 client keeps it (that client HAS
    -- the spell). Both rows are measured after the build decision, which the
    -- class's own SoD probe makes at post_init.
    local EXPECT = {
        { project = 2, family = "ERA", count = 6, sod = false,
          ids = { raptor = 14266, multi = 25294, rapid_fire = 3045, aimed = 20904 },
          dead = { "steady", "kill_command", "bestial_wrath" } },
        { project = 2, family = "ERA", count = 7, sod = true,
          ids = { raptor = 14266, multi = 25294, bestial_wrath = 19574,
            rapid_fire = 3045, aimed = 20904 },
          dead = { "steady", "kill_command" } },
        { project = 5, family = "TBC", count = 9,
          ids = { steady = 34120, raptor = 27014, kill_command = 34026, multi = 27021,
            bestial_wrath = 19574, rapid_fire = 3045, aimed = 27065 },
          dead = {} },
        { project = 11, family = "WRATH", count = 9,
          ids = { steady = 49052, raptor = 48996, kill_command = 34026, multi = 49048,
            bestial_wrath = 19574, rapid_fire = 3045, aimed = 49050 },
          dead = {} },
        { project = 18, family = "FOREVER", count = 7,
          ids = { raptor = 14266, multi = 2643, bestial_wrath = 19574,
            rapid_fire = 3045, aimed = 20904 },
          dead = { "steady", "kill_command" } },
        { project = 14, family = "CATA", count = 9,
          ids = { steady = 56641, raptor = 2973, kill_command = 34026, multi = 2643,
            bestial_wrath = 19574, rapid_fire = 3045, aimed = 19434 },
          dead = {} },
        -- The Mists client has no Raptor Strike id this tree knows, so the slot
        -- is DROPPED there (never pointed at a spell that client cannot have).
        { project = 19, family = "MISTS", count = 8,
          ids = { steady = 56641, kill_command = 34026, multi = 2643,
            bestial_wrath = 19574, rapid_fire = 3045, aimed = 19434 },
          dead = { "raptor" } },
        { project = 1, family = "RETAIL", count = 9,
          ids = { steady = 56641, raptor = 186270, kill_command = 34026, multi = 2643,
            bestial_wrath = 19574, rapid_fire = 257044, aimed = 19434 },
          dead = {} },
    }

    for _, case in ipairs(EXPECT) do
        -- A client whose spell data answers only the ids the SoD rows need, so
        -- the runtime re-point cannot move a slot the row is measuring.
        local function only(ids)
            return function(id)
                local name = ids[id]
                if name then return name, nil, "icon", 0, 0, 0, id end
                return nil
            end
        end
        local fixture_spell_info = nil
        if case.sod ~= nil then
            fixture_spell_info = only(case.sod
                and { [409433] = "Chimera Shot", [19574] = "Bestial Wrath" } or {})
        end
        local sb = build({ project = case.project,
            known_spells = case.sod and { [409433] = true } or nil,
            known = case.sod and { [409433] = true, [19574] = true } or nil,
            GetSpellInfo = fixture_spell_info })
        local label = case.family .. (case.sod and "/SoD" or (case.sod == false and "/base" or ""))
        eq(sb.st.family, case.family, label .. " HUD: the fixture reads the family token")
        -- The Era family's pick is decided at post_init (the class's own SoD
        -- probe), so the measurement below is taken after that decision.
        if case.sod ~= nil then
            sb.ST.HUNTER.post_init(sb.ST)
        end
        local by_key = hud_by_key(sb.ST)
        -- (1) the effective id per family per slot
        for key, id in pairs(case.ids) do
            check(by_key[key] ~= nil, label .. " HUD: the " .. key .. " slot ships")
            if by_key[key] then
                eq(by_key[key].spell, id, label .. " HUD: the " .. key .. " slot carries the client's own rank")
            end
        end
        -- (2) the per-family slot COUNT
        eq(#sb.ST.HUNTER.HUD_SLOTS, case.count,
            label .. " HUD: the family ships " .. case.count .. " slots")
        -- (3) the dead-slot rule: the shipped keys are exactly the live ones
        for _, dead in ipairs(case.dead) do
            eq(by_key[dead], nil,
                label .. " HUD: no " .. dead .. " slot ships (the client cannot have it)")
        end
        for key, id in pairs(case.ids) do
            check(by_key[key] ~= nil and by_key[key].spell == id,
                label .. " HUD: every live slot points at a spell the client has")
        end
        -- (4) the guide and the HUD agree on every key they share
        local g_by_key = guide_by_key(sb.ST)
        local shared, agree = 0, true
        for key, slot in pairs(by_key) do
            if slot.spell and g_by_key[key] then
                shared = shared + 1
                if g_by_key[key].spell_id ~= slot.spell then agree = false end
            end
        end
        check(shared > 0, label .. " HUD: the guide and the HUD share at least one slot")
        check(agree, label .. " HUD: the guide and the HUD carry the same id for every shared slot")
        -- The guide never declares a slot for a spell the client cannot have.
        local guide_dead = true
        for _, dead in ipairs(case.dead) do
            if g_by_key[dead] then guide_dead = false end
        end
        check(guide_dead, label .. " guide: no dead slot is declared")
    end

    -- The Mists Raptor rank is UNKNOWN, so the per-family table carries NO Mists
    -- cell for it: an id is never guessed, and the dead-slot filter drops the
    -- slot there (the Mists row above). The source pin keeps that contract
    -- checkable - a Mists cell in that table is the one thing that must not
    -- reappear.
    local src = (function()
        local f = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
        local s = f:read("*a")
        f:close()
        return s
    end)()
    local raptor_block = src:match("raptor = {(.-)\n    },") or ""
    check(raptor_block ~= "", "the per-family table's Raptor Strike block is found")
    check(raptor_block:find("MISTS%s*=") == nil,
        "the per-family table carries no Mists Raptor rank (an id is never guessed)")

    -- The family-blind ids the correction removed: no slot may carry them on a
    -- client that does not have that rank.
    local wrath = build({ project = 11 }).ST
    local w_by_key = hud_by_key(wrath)
    for _, blind in ipairs({ 19434, 2643, 2973 }) do
        local carries = false
        for _, slot in pairs(w_by_key) do
            if slot.spell == blind then carries = true end
        end
        check(not carries, "Wrath HUD: no slot carries the vanilla id " .. blind)
    end
    local forever = build({ project = 18 }).ST
    eq(hud_by_key(forever).kill_command, nil,
        "Forever HUD: the Kill Command slot is dropped (the client has no Kill Command)")
    eq(#forever.HUNTER.HUD_SLOTS, 7,
        "Forever HUD: the family ships seven slots (the two dead ones dropped)")
end

--=========================================================================================
-- H2 CUT: the lust scan is gone (operator order 2026-10-19,
-- bench/hunter_open_2026-10-19.md section 5). An aura on the player writes no
-- window and spends no scan, whatever the compat surface says. A reintroduced
-- producer fails the nil pins; the source pins prove the gate spelling is gone.
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    -- Bloodlust on the player with 30 s left on the suite clock (the old window).
    sb.player_auras = { { name = "Bloodlust", id = 2825, duration = 40, expiration = 30 } }

    -- Armed, unknown (pre-C2) and closed compat surfaces all yield no window.
    sb.st.lust_supported = true
    local out = ST.HUNTER.gather_guide_inputs(ST, {})
    eq(out.lust_remaining, nil, "H2 CUT: an armed compat yields no window")

    sb.st.lust_supported = nil
    out = ST.HUNTER.gather_guide_inputs(ST, {})
    eq(out.lust_remaining, nil, "H2 CUT: a pre-C2 compat yields no window")

    sb.st.lust_supported = false
    out = ST.HUNTER.gather_guide_inputs(ST, {})
    eq(out.lust_remaining, nil, "H2 CUT: a closed compat yields no window")

    -- Source pins: the gate spelling and the producer machinery are gone.
    local src = (function()
        local f = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
        local s = f:read("*a")
        f:close()
        return s
    end)()
    check(src:find("if st.lust_supported == true and lust_ids", 1, true) == nil,
        "H2 CUT: the lust gate spelling is gone from classes/hunter.lua")
    check(src:find("lust_remaining", 1, true) == nil,
        "H2 CUT: no lust field write remains in classes/hunter.lua")
    check(src:find("hunter_lust", 1, true) == nil,
        "H2 CUT: no lust throttle state remains in classes/hunter.lua")
end

--=========================================================================================
-- 18) H1: target-of-target warning state (two unit-token reads, no CLEU)
--=========================================================================================
do
    -- No unit APIs at all: unknown, never an error.
    do
        local sb = build()
        local ok, state = pcall(sb.ST.HUNTER.get_target_warning, sb.ST)
        check(ok, "get_target_warning without unit APIs does not error")
        eq(state, nil, "H1: no unit APIs read unknown")
    end

    -- No target: unknown, and the ToT token is never probed.
    do
        local sb = build({
            unit_exists = function() return false end,
            unit_is_unit = function() error("H1: UnitIsUnit must not run without a target") end,
        })
        local ok, state = pcall(sb.ST.HUNTER.get_target_warning, sb.ST)
        check(ok, "get_target_warning without a target does not error")
        eq(state, nil, "H1: no target reads unknown")
    end

    -- Target without a target-of-target: present but looking elsewhere.
    do
        local sb = build({
            unit_exists = function(unit)
                return unit == "target"
            end,
            unit_is_unit = function() error("H1: UnitIsUnit must not run without a ToT") end,
        })
        eq(sb.ST.HUNTER.get_target_warning(sb.ST), false, "H1: no ToT reads false")
    end

    -- Target on someone else: false.
    do
        local sb = build({
            unit_exists = function() return true end,
            unit_is_unit = function() return false end,
        })
        eq(sb.ST.HUNTER.get_target_warning(sb.ST), false, "H1: a target looking elsewhere reads false")
    end

    -- Target on the player: true (boolean and 1 spellings).
    do
        local sb = build({
            unit_exists = function() return true end,
            unit_is_unit = function() return true end,
        })
        eq(sb.ST.HUNTER.get_target_warning(sb.ST), true, "H1: the player's ToT reads true")
        local sb1 = build({
            unit_exists = function() return true end,
            unit_is_unit = function() return 1 end,
        })
        eq(sb1.ST.HUNTER.get_target_warning(sb1.ST), true, "H1: the 1 spelling reads true")
    end

    -- An unanswered comparison: unknown, never a guess.
    do
        local sb = build({
            unit_exists = function() return true end,
            unit_is_unit = function() return nil end,
        })
        eq(sb.ST.HUNTER.get_target_warning(sb.ST), nil, "H1: an unanswered comparison reads unknown")
    end
end

--=========================================================================================
-- 19) H2: shot log, clip sampler and combat-exit hygiene
--=========================================================================================
do
    -- record_shot_sample: first use creates the log; counters accumulate.
    do
        local sb = build()
        local ST = sb.ST
        eq(ST.hunter_shot_log, nil, "H2: no log before the first sample")
        ST.HUNTER.record_shot_sample(ST, false, 0.1)
        eq(#ST.hunter_shot_log, 1, "H2: the first sample creates the log")
        eq(ST.hunter_shots_total, 1, "H2: the total counts the first sample")
        eq(ST.hunter_shots_clipped, nil, "H2: a clean sample leaves the clip counter unset")
        ST.HUNTER.record_shot_sample(ST, true, nil)
        eq(#ST.hunter_shot_log, 2, "H2: samples append")
        eq(ST.hunter_shots_total, 2, "H2: the total accumulates")
        eq(ST.hunter_shots_clipped, 1, "H2: clips accumulate")
        eq(ST.hunter_shot_log[2].latency, nil, "H2: a non-number latency stores nil")
        -- A non-table owner is ignored, never an error.
        local ok, err = pcall(ST.HUNTER.record_shot_sample, nil, true, 0.1)
        check(ok, "H2: record on a non-table owner does not error (" .. tostring(err) .. ")")
    end

    -- The ring caps the stored samples while the counters stay cumulative.
    do
        local sb = build()
        local ST = sb.ST
        local max = ST.HUNTER.SHOT_LOG_MAX
        check(type(max) == "number" and max > 10, "H2: SHOT_LOG_MAX is a usable cap")
        for i = 1, max + 5 do
            ST.HUNTER.record_shot_sample(ST, i % 2 == 0, 0.1)
        end
        eq(#ST.hunter_shot_log, max, "H2: the log rings at SHOT_LOG_MAX")
        eq(ST.hunter_shots_total, max + 5, "H2: the total counts every sample")
    end

    -- reset_shot_log clears the log, the counters and any in-flight track.
    do
        local sb = build()
        local ST = sb.ST
        ST.HUNTER.record_shot_sample(ST, true, 0.1)
        ST.hunter_live_cast = { key = "k", clipped = true, judged = true }
        ST.HUNTER.reset_shot_log(ST)
        eq(#ST.hunter_shot_log, 0, "H2: reset empties the log")
        eq(ST.hunter_shots_total, 0, "H2: reset zeroes the total")
        eq(ST.hunter_shots_clipped, 0, "H2: reset zeroes the clip counter")
        eq(ST.hunter_live_cast, nil, "H2: reset clears the in-flight track")
        local ok, err = pcall(ST.HUNTER.reset_shot_log, nil)
        check(ok, "H2: reset on a non-table owner does not error (" .. tostring(err) .. ")")
    end

    -- A safe Steady Shot cast completes as a clean judged sample.
    do
        local live = { active = false, start_ms = 1000, end_ms = 2500 }
        local sb = build({
            live_cast = function()
                if not live.active then
                    return nil
                end
                return "Steady Shot", "", "icon", live.start_ms, live.end_ms,
                    false, 1, false, 56641
            end,
        })
        local ST = sb.ST
        ST.ranged = { start = 0, speed = 3.0 }
        sb.clock = 2.0
        live.active = true
        ST.HUNTER.track_live_cast(ST)
        check(ST.hunter_live_cast ~= nil, "H2: the live shot cast is tracked")
        live.active = false
        ST.HUNTER.track_live_cast(ST)
        eq(ST.hunter_live_cast, nil, "H2: the finished cast untracks")
        eq(#ST.hunter_shot_log, 1, "H2: the finished safe cast records one sample")
        eq(ST.hunter_shot_log[1].clipped, false, "H2: the safe cast is not a clip")
        eq(ST.hunter_shots_total, 1, "H2: the safe cast counts once")
        eq(ST.hunter_shots_clipped, nil, "H2: the safe cast clips nothing")
    end

    -- An unsafe cast (remaining past ttl + grace - buffer) records clipped.
    do
        local live = { active = false }
        local sb = build({
            live_cast = function()
                if not live.active then
                    return nil
                end
                return "Steady Shot", "", "icon", 1000, 4500, false, 1, false, 56641
            end,
        })
        local ST = sb.ST
        ST.ranged = { start = 0, speed = 3.0 }
        sb.clock = 2.0
        live.active = true
        ST.HUNTER.track_live_cast(ST)
        live.active = false
        ST.HUNTER.track_live_cast(ST)
        eq(#ST.hunter_shot_log, 1, "H2: the finished unsafe cast records one sample")
        eq(ST.hunter_shot_log[1].clipped, true, "H2: the unsafe cast is a clip")
        eq(ST.hunter_shots_clipped, 1, "H2: the clip counter counts the unsafe cast")
    end

    -- Latency compensation flips a boundary clip verdict: the same cast is safe on
    -- raw 50 ms but clips once the calibrated 300 ms is honored, and the stored
    -- sample keeps the compensated reading (ttl 1.0 + 0.5 grace: the raw 0.05
    -- buffer leaves 1.45 s of room, the calibrated 0.3 buffer only 1.2 s, and the
    -- 1.3 s remaining falls between them).
    do
        local function sample_with_latency(lat)
            local live = { active = true }
            local sb = build({ live_cast = function()
                if not live.active then
                    return nil
                end
                return "Steady Shot", "", "icon", 2000, 3300, false, 1, false, 56641
            end })
            local ST = sb.ST
            ST.latency = lat
            ST.ranged = { start = 0, speed = 3.0 }
            sb.clock = 2.0
            ST.HUNTER.track_live_cast(ST)
            live.active = false
            ST.HUNTER.track_live_cast(ST)
            return ST.hunter_shot_log[1]
        end
        local raw_sample = sample_with_latency({ world_ms = 50 })
        eq(raw_sample.clipped, false, "H2: the boundary cast is safe on raw latency")
        near(raw_sample.latency, 0.05, 1e-9, "H2: the sample keeps the raw reading")
        local comp_sample = sample_with_latency({ world_ms = 50, calibrated_world_ms = 300 })
        eq(comp_sample.clipped, true, "H2: the same cast clips on compensated latency")
        near(comp_sample.latency, 0.3, 1e-9, "H2: the sample keeps the compensated reading")
    end

    -- A foreign cast never tracks and never samples.
    do
        local sb = build({
            live_cast = function()
                return "Fireball", "", "icon", 1000, 2500, false, 1, false, 133
            end,
        })
        local ST = sb.ST
        ST.ranged = { start = 0, speed = 3.0 }
        sb.clock = 2.0
        ST.HUNTER.track_live_cast(ST)
        eq(ST.hunter_live_cast, nil, "H2: a foreign cast is not tracked")
        eq(ST.hunter_shot_log, nil, "H2: a foreign cast samples nothing")
    end

    -- No readable swing cycle: the cast drops its sample instead of recording clean.
    do
        local live = { active = true }
        local sb = build({
            live_cast = function()
                if not live.active then
                    return nil
                end
                return "Steady Shot", "", "icon", 1000, 2500, false, 1, false, 56641
            end,
        })
        local ST = sb.ST
        sb.clock = 2.0
        ST.HUNTER.track_live_cast(ST)
        live.active = false
        ST.HUNTER.track_live_cast(ST)
        eq(ST.hunter_live_cast, nil, "H2: the unjudged cast untracks")
        eq(ST.hunter_shot_log, nil, "H2: the unjudged cast drops its sample")
    end

    -- Chain-casts (no cast-free frame between) keep both samples.
    do
        local cast = 1
        local sb = build({
            live_cast = function()
                if cast == 0 then
                    return nil
                end
                if cast == 1 then
                    return "Steady Shot", "", "icon", 1000, 2500, false, 1, false, 56641
                end
                return "Steady Shot", "", "icon", 2600, 4100, false, 2, false, 56641
            end,
        })
        local ST = sb.ST
        ST.ranged = { start = 0, speed = 3.0 }
        sb.clock = 2.0
        ST.HUNTER.track_live_cast(ST)
        sb.clock = 2.6
        cast = 2
        ST.HUNTER.track_live_cast(ST)
        eq(#ST.hunter_shot_log, 1, "H2: the replaced judged cast records on swap")
        cast = 0
        ST.HUNTER.track_live_cast(ST)
        eq(#ST.hunter_shot_log, 2, "H2: chain-casts keep both samples")
    end

    -- on_bar_update drives the sampler on the ranged tick only.
    do
        local live = { active = true }
        local sb = build({
            live_cast = function()
                if not live.active then
                    return nil
                end
                return "Multi-Shot", "", "icon", 1000, 1500, false, 1, false, 2643
            end,
        })
        local ST = sb.ST
        ST.ranged = { start = 0, speed = 3.0 }
        sb.clock = 1.2
        ST.HUNTER.on_bar_update(ST, "mainhand")
        eq(ST.hunter_live_cast, nil, "H2: the mainhand tick never samples")
        ST.HUNTER.on_bar_update(ST, "ranged")
        check(ST.hunter_live_cast ~= nil, "H2: the ranged tick tracks the live cast")
        live.active = false
        ST.HUNTER.on_bar_update(ST, "ranged")
        eq(#ST.hunter_shot_log, 1, "H2: the ranged tick records the finished cast")
    end

    -- Combat exit clears the in-flight track but keeps the log for the report.
    do
        local sb = build()
        local ST = sb.ST
        ST.HUNTER.record_shot_sample(ST, true, 0.1)
        ST.hunter_live_cast = { key = "k", clipped = false, judged = true }
        ST.HUNTER.on_combat_exit(ST)
        eq(ST.hunter_live_cast, nil, "H2: combat exit clears the in-flight track")
        eq(#ST.hunter_shot_log, 1, "H2: combat exit keeps the log for the report")
    end
end

--=========================================================================================
-- Readiness double-RF window (hunter_open §1): the stamp, the pure window and the
-- RF bar 2x readout on the readiness toggle (nil = off, no default-visible change)
--=========================================================================================
do
    -- The pure window: armed, elapsed, unknown and custom-window branches.
    local H = build().ST.HUNTER
    eq(H.READINESS_DOUBLE_WINDOW, 60, "readiness: the provisional window is 60s")
    eq(H.get_readiness_window(0, 10), 50, "readiness: the window counts from the stamp")
    eq(H.get_readiness_window(0, 60), nil, "readiness: an exactly-elapsed window closes")
    eq(H.get_readiness_window(0, 61), nil, "readiness: an elapsed window closes")
    eq(H.get_readiness_window(nil, 10), nil, "readiness: a missing stamp opens no window")
    eq(H.get_readiness_window(0, nil), nil, "readiness: an unknown clock opens no window")
    eq(H.get_readiness_window(0, 10, 5), nil, "readiness: a custom window can already be shut")
    eq(H.get_readiness_window(0, 3, 5), 2, "readiness: a custom window counts when live")
    eq(H.get_readiness_window(0 / 0, 10), nil, "readiness: a NaN stamp opens no window")

    -- The stamp: post_init starts empty; Readiness fires it (alongside the RF
    -- refresh); combat exit clears it. The refresh stub carries no init, so the
    -- post_init pin runs in a plain sandbox (exactly like the 13b split).
    local plain = build()
    plain.ST.HUNTER.post_init(plain.ST)
    eq(plain.ST.hunter_readiness_at, nil, "readiness: no stamp after post_init")
    local refresh_calls = 0
    local sb = build({ st_extras = { hunter_ui = {
        force_rapid_fire_refresh = function() refresh_calls = refresh_calls + 1 end,
    } } })
    local ST = sb.ST
    ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 23989)
    eq(refresh_calls, 1, "readiness: the cast still forces the Rapid Fire refresh")
    eq(ST.hunter_readiness_at, 0, "readiness: the cast stamps the window (clock 0)")
    ST.HUNTER.on_combat_exit(ST)
    eq(ST.hunter_readiness_at, nil, "readiness: combat exit clears the stamp")
end

--=========================================================================================
-- ISS tint (hunter_open §1): the throttled proc probe and the Steady/Aimed HUD glow
-- (HUD only - the guide engine never reads it)
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    -- Id match, the rescan cache, re-scan, the name fallback and unrelated auras.
    sb.player_auras = { { name = "Improved Steady Shot", id = 53220, duration = 12, expiration = 10 } }
    sb.clock = 0
    eq(ST.HUNTER.get_iss_remaining(ST, 0), 10, "ISS: the id match returns the remaining window")
    sb.player_auras = {}
    eq(ST.HUNTER.get_iss_remaining(ST, 0.1), 10, "ISS: the rescan interval serves the cache")
    sb.clock = 1
    eq(ST.HUNTER.get_iss_remaining(ST, 1), nil, "ISS: past the interval the scan re-runs")
    sb.player_auras = { { name = "Improved Steady Shot", id = 999999, duration = 12, expiration = 9 } }
    sb.clock = 2
    eq(ST.HUNTER.get_iss_remaining(ST, 2), 7, "ISS: the English fallback matches by name")
    sb.player_auras = { { name = "Rapid Fire", id = 3045, duration = 15, expiration = 20 } }
    sb.clock = 3
    eq(ST.HUNTER.get_iss_remaining(ST, 3), nil, "ISS: an unrelated aura never matches")

    -- HUD glow: the steady + aimed slots only, toggle-gated nil = off.
    local by_key = {}
    for i = 1, #ST.HUNTER.HUD_SLOTS do
        by_key[ST.HUNTER.HUD_SLOTS[i].key] = ST.HUNTER.HUD_SLOTS[i]
    end
    sb.player_auras = { { name = "Improved Steady Shot", id = 53220, duration = 12, expiration = 30 } }
    sb.clock = 20
    local s = ST.HUNTER.get_hud_state(ST, by_key.steady, 20)
    eq(s.glow, nil, "ISS: the unset toggle never glows")
    sb.class_db.hunter_iss_badge_enabled = true
    s = ST.HUNTER.get_hud_state(ST, by_key.steady, 20)
    eq(s.glow, true, "ISS: the steady slot glows while banked")
    s = ST.HUNTER.get_hud_state(ST, by_key.aimed, 20)
    eq(s.glow, true, "ISS: the aimed slot glows while banked")
    s = ST.HUNTER.get_hud_state(ST, by_key.multi, 20)
    eq(s.glow, nil, "ISS: unrelated slots never glow")
    sb.player_auras = {}
    sb.clock = 21
    s = ST.HUNTER.get_hud_state(ST, by_key.steady, 21)
    eq(s.glow, nil, "ISS: a missing proc never glows")
end

--=========================================================================================
-- OOM Viper badge (hunter_open §2): the pure prompt and the lazily created widget
-- (nil = off - the build-time census holds until reconcile hoists it)
--=========================================================================================
do
    local H = build().ST.HUNTER
    eq(H.OOM_VIPER_FRAC, 0.05, "OOM: the swap band is 5%")
    eq(H.get_oom_viper_prompt(0.04, false, true, true), "VIPER", "OOM: low mana prompts")
    eq(H.get_oom_viper_prompt(0.05, false, true, true), "VIPER", "OOM: the band edge prompts")
    eq(H.get_oom_viper_prompt(0.06, false, true, true), nil, "OOM: mana above the band stays quiet")
    eq(H.get_oom_viper_prompt(0.01, true, true, true), nil, "OOM: an active Viper stays quiet")
    eq(H.get_oom_viper_prompt(0.01, false, false, true), nil, "OOM: an unknown Viper never prompts")
    eq(H.get_oom_viper_prompt(0.01, false, true, nil), nil, "OOM: the toggle off never prompts")
    eq(H.get_oom_viper_prompt(0.01, false, true, false), nil, "OOM: an explicit off never prompts")
    eq(H.get_oom_viper_prompt(nil, false, true, true), nil, "OOM: unknown mana never prompts")
    eq(H.get_oom_viper_prompt(0 / 0, false, true, true), nil, "OOM: NaN mana never prompts")

    -- Mana fraction + Viper knowledge/activity probes.
    local sb = build({ mana = { cur = 3, max = 100 } })
    eq(sb.ST.HUNTER.get_mana_fraction(), 0.03, "OOM: the fraction reads the power pair")
    eq(build().ST.HUNTER.get_mana_fraction(), nil, "OOM: an unreadable client hides")
    eq(sb.ST.HUNTER.is_viper_known(), false, "OOM: nothing learned means unknown Viper")
    eq(build({ known_spells = { [34074] = true } }).ST.HUNTER.is_viper_known(), true,
        "OOM: the TBC id reads known")
    eq(build({ known_spells = { [415423] = true } }).ST.HUNTER.is_viper_known(), true,
        "OOM: the SoD id reads known")
    eq(sb.ST.HUNTER.is_viper_active(), false, "OOM: no aura means inactive")
    sb.player_auras = { { name = "Aspect of the Viper", id = 34074, duration = 60, expiration = 100 } }
    sb.clock = 0
    eq(sb.ST.HUNTER.is_viper_active(), true, "OOM: the aura reads active")
end

--=========================================================================================
-- Lock and Load trap-proc badge (hunter_open §1): the throttled proc probe and the
-- pure prompt (badge layer only - the guide engine never reads it)
--=========================================================================================
do
    local H = build().ST.HUNTER
    eq(H.get_lnl_prompt(8, true), "LnL", "LnL: a live window prompts")
    eq(H.get_lnl_prompt(0.1, true), "LnL", "LnL: a nearly-spent window still prompts")
    eq(H.get_lnl_prompt(0, true), nil, "LnL: a spent window stays quiet")
    eq(H.get_lnl_prompt(-1, true), nil, "LnL: a negative window stays quiet")
    eq(H.get_lnl_prompt(8, nil), nil, "LnL: the toggle off never prompts")
    eq(H.get_lnl_prompt(8, false), nil, "LnL: an explicit off never prompts")
    eq(H.get_lnl_prompt(nil, true), nil, "LnL: an unknown window never prompts")
    eq(H.get_lnl_prompt(0 / 0, true), nil, "LnL: a NaN window never prompts")

    -- Throttled probe: the Wrath id, the rescan cache, re-scan, the SoD id, the
    -- English fallback and unrelated auras.
    local sb = build()
    local ST = sb.ST
    sb.player_auras = { { name = "Lock and Load", id = 56344, duration = 22, expiration = 10 } }
    sb.clock = 0
    eq(ST.HUNTER.get_lnl_remaining(ST, 0), 10, "LnL: the Wrath id returns the window")
    sb.player_auras = {}
    eq(ST.HUNTER.get_lnl_remaining(ST, 0.1), 10, "LnL: the rescan interval serves the cache")
    sb.clock = 1
    eq(ST.HUNTER.get_lnl_remaining(ST, 1), nil, "LnL: past the interval the scan re-runs")
    sb.player_auras = { { name = "Lock and Load", id = 415413, duration = 20, expiration = 19 } }
    sb.clock = 2
    eq(ST.HUNTER.get_lnl_remaining(ST, 2), 17, "LnL: the SoD id returns the window")
    sb.player_auras = { { name = "Lock and Load", id = 999999, duration = 20, expiration = 18 } }
    sb.clock = 3
    eq(ST.HUNTER.get_lnl_remaining(ST, 3), 15, "LnL: the English fallback matches by name")
    sb.player_auras = { { name = "Rapid Fire", id = 3045, duration = 15, expiration = 20 } }
    sb.clock = 4
    eq(ST.HUNTER.get_lnl_remaining(ST, 4), nil, "LnL: an unrelated aura never matches")
    -- The id matches without the name (a localized client renames the aura).
    sb.player_auras = { { name = "Unknown Aura", id = 415413, duration = 20, expiration = 25 } }
    sb.clock = 5
    eq(ST.HUNTER.get_lnl_remaining(ST, 5), 20, "LnL: the SoD id matches without the name")
end

--=========================================================================================
-- 19b) The class-side feature closures (the audit's H-03/H-05/H-16/H-17/H-18 rows):
-- the sourced ids and the gather wiring they close.
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    local H = ST.HUNTER

    -- Serpent Sting: the sourced ranks (Era r1, the later rank, the Wrath rank).
    check(type(H.SERPENT_STING_IDS) == "table", "the Serpent Sting ranks are exported")
    eq(H.SERPENT_STING_IDS[13554], true, "serpent: the Era rank 13554 is listed")
    eq(H.SERPENT_STING_IDS[25295], true, "serpent: the later rank 25295 is listed")
    eq(H.SERPENT_STING_IDS[49001], true, "serpent: the Wrath rank 49001 is listed")
    local serpent_count = 0
    for _ in pairs(H.SERPENT_STING_IDS) do serpent_count = serpent_count + 1 end
    eq(serpent_count, 3, "serpent: only the sourced ranks are listed")

    -- Improved Steady Shot: the sourced aura id and the sim's duration.
    eq(H.ISS_AURA_ID, 53220, "ISS: the aura id is the sim's 53220")
    eq(H.ISS_DURATION_SECONDS, 12, "ISS: the sim's window is 12 s")

    -- Readiness: the sim's cooldown, the smart double-RF delay and the reset list.
    eq(H.READINESS_COOLDOWN_SECONDS, 180, "readiness: the sim's cooldown is 3 minutes")
    eq(H.READINESS_RF_HOLD_SECONDS, 10, "readiness: the smart double-RF delay is 10 s")
    check(H.READINESS_RESET_COOLDOWNS.rapid_fire == true, "readiness: Rapid Fire is reset")
    check(H.READINESS_RESET_COOLDOWNS.chimera == true, "readiness: Chimera Shot is reset")
    check(H.READINESS_RESET_COOLDOWNS.multi == true, "readiness: Multi-Shot is reset")
    check(H.READINESS_RESET_COOLDOWNS.kill_shot == true, "readiness: Kill Shot is reset")

    -- The Wrath Lock and Load source traps: the sourced ids and their durations.
    eq(H.TRAP_SPELLS[63672], "black_arrow", "trap: the Wrath Black Arrow 63672 is tracked")
    eq(H.TRAP_SPELLS[49067], "explosive_trap", "trap: the Wrath Explosive Trap 49067 is tracked")
    eq(H.TRAP_ACTIVE_DURATIONS.black_arrow, 30, "trap: the Black Arrow runs 30 s")
    eq(H.TRAP_ACTIVE_DURATIONS.explosive_trap, 30, "trap: the Explosive Trap runs 30 s")

    -- The gather: the LnL window is wired to the class's own throttled probe, so the
    -- engine's W-LnL arm can fire; without the aura it stays unknown (nil).
    local lnl_sb = build()
    lnl_sb.clock = 0
    lnl_sb.player_auras = { { name = "Lock and Load", id = 56344, duration = 22, expiration = 10 } }
    local gathered = lnl_sb.ST.HUNTER.gather_guide_inputs(lnl_sb.ST, {})
    check(gathered.lnl_ready == true or gathered.lnl_ready == nil,
        "gather: the LnL window reads the probe (a live aura or unknown)")
    -- The probe answers a boolean: the class writes true when the window is live.
    eq(gathered.lnl_ready, true, "gather: a live Lock and Load aura opens the window")
    -- Without the aura the window is unknown (nil), never a guess.
    local plain_sb = build()
    plain_sb.clock = 0
    local plain = plain_sb.ST.HUNTER.gather_guide_inputs(plain_sb.ST, {})
    eq(plain.lnl_ready, nil, "gather: no Lock and Load aura leaves the window unknown")
    -- The Serpent knowledge is nil until the client confirms a rank; with no known
    -- rank the debuff scan does not run at all, so the debuff stays unknown and
    -- the guard never withholds.
    eq(plain.serpent_known, nil, "gather: an unconfirmed Serpent rank stays unknown")
    eq(plain.serpent_active, nil, "gather: an unconfirmed Serpent rank leaves the debuff unknown")
    eq(plain_sb.target_aura_queries, 0, "gather: an unconfirmed Serpent rank costs no target scan")
    -- A client that knows a Serpent rank reports the knowledge.
    local sting_sb = build({ known = { [13554] = true } })
    sting_sb.clock = 0
    local sting = sting_sb.ST.HUNTER.gather_guide_inputs(sting_sb.ST, {})
    check(sting.serpent_known == true or sting.serpent_known == nil,
        "gather: the Serpent knowledge is a boolean or unknown")
end

--=========================================================================================
-- 19c) The Serpent Sting TARGET-DEBUFF feed (BS-3): the three-state scan that gives
-- the naked-Chimera guard its debuff source.
--   true  = the sting is up on the target
--   false = the scan ran against a real target and the sting is not on it
--   nil   = unknown (no target, or the secret-aura regime can hide the row)
-- The predicate matches the NAME first and the id second (the TBC Anniversary
-- client resolves by name, so its Serpent rank ids are not the sourced ones), and
-- the guard's semantics do not change: only a KNOWN-down sting withholds the
-- prompt, an unknown debuff never does.
--=========================================================================================
do
    -- A client that knows a Serpent rank (the knowledge gate the guard reads):
    -- the spell data carries 13554 and this player has learned it.
    local function serpent_client(opts)
        opts = opts or {}
        opts.known = opts.known or { [13554] = true }
        opts.known_spells = opts.known_spells or { [13554] = true }
        local sb = build(opts)
        sb.clock = 0
        sb.ST.HUNTER.resolve_guide_icons()
        return sb
    end
    local function gather(sb)
        return sb.ST.HUNTER.gather_guide_inputs(sb.ST, {})
    end

    -- The knowledge gate: a client that knows a rank reports it.
    local known_sb = serpent_client({ unit_exists = function() return true end })
    eq(gather(known_sb).serpent_known, true,
        "serpent: a client that knows a Serpent rank reports the knowledge")

    -- The sting is up on the target: the NAME leg matches (the TBC-shaped client,
    -- whose Serpent rank id is not one of the sourced ids).
    local up = serpent_client({ unit_exists = function() return true end })
    up.target_auras = { { name = "Serpent Sting", id = 99999, count = 1,
        duration = 16, expiration = 12 } }
    eq(gather(up).serpent_active, true, "serpent: the sting on the target reads as up (by name)")

    -- The id leg: a localized client renames the debuff, but the sourced rank id
    -- still matches it.
    local by_id = serpent_client({ unit_exists = function() return true end })
    by_id.target_auras = { { name = "Giftnatternbiss", id = 49001, count = 1,
        duration = 16, expiration = 12 } }
    eq(gather(by_id).serpent_active, true,
        "serpent: a sourced rank id matches without the English name")

    -- The scan ran and the sting is not on the target: false (a known-down sting).
    local down = serpent_client({ unit_exists = function() return true end })
    down.target_auras = { { name = "Corruption", id = 11563, count = 1,
        duration = 6, expiration = 3 } }
    eq(gather(down).serpent_active, false,
        "serpent: a target without the sting reads as down")

    -- An unrelated debuff never matches (the scan is not an "any debuff" probe,
    -- and the name match is exact, never a prefix).
    local other = serpent_client({ unit_exists = function() return true end })
    other.target_auras = { { name = "Serpent Fang", id = 99998, count = 1,
        duration = 6, expiration = 3 } }
    eq(gather(other).serpent_active, false, "serpent: an unrelated debuff never matches")

    -- No target: there is nothing to scan, so the state is UNKNOWN (never "down").
    local no_target = serpent_client()
    no_target.target_auras = { { name = "Corruption", id = 11563, count = 1,
        duration = 6, expiration = 3 } }
    eq(gather(no_target).serpent_active, nil,
        "serpent: no target leaves the debuff unknown")
    eq(no_target.target_aura_queries, 0,
        "serpent: a client with no target spends no debuff scan")

    -- The secret-aura regime: a restricted row can hide the sting, so a missing
    -- sting is UNKNOWN, never "down".
    local secret = serpent_client({ unit_exists = function() return true end })
    secret.target_auras = { { name = "Serpent Sting", id = 49001, secret = true } }
    secret.st.api.auras_may_be_secret = function() return true end
    eq(gather(secret).serpent_active, nil,
        "serpent: a hidden debuff row reads as unknown, not as down")

    -- The same regime with a READABLE row: the scan still finds the sting (the
    -- regime alone does not blind the scan, only a hidden row does).
    local secret_readable = serpent_client({ unit_exists = function() return true end })
    secret_readable.target_auras = { { name = "Serpent Sting", id = 49001, count = 1,
        duration = 16, expiration = 12 } }
    secret_readable.st.api.auras_may_be_secret = function() return true end
    eq(gather(secret_readable).serpent_active, true,
        "serpent: a readable row still reads as up under the secret regime")

    -- The regime is off (the client says auras are not secret): a missing sting is
    -- an honest "down" again.
    local open = serpent_client({ unit_exists = function() return true end })
    open.target_auras = { { name = "Corruption", id = 11563, count = 1,
        duration = 6, expiration = 3 } }
    open.st.api.auras_may_be_secret = function() return false end
    eq(gather(open).serpent_active, false,
        "serpent: outside the secret regime a missing sting reads as down")

    -- With no known Serpent rank the guard can never withhold, so the scan does
    -- not run at all: no client pays for a scan it cannot use.
    local unknown_sb = build({ unit_exists = function() return true end })
    unknown_sb.clock = 0
    unknown_sb.target_auras = { { name = "Serpent Sting", id = 49001, count = 1,
        duration = 16, expiration = 12 } }
    local unknown_inputs = gather(unknown_sb)
    eq(unknown_inputs.serpent_known, nil,
        "serpent: an unlearned Serpent rank stays unknown")
    eq(unknown_inputs.serpent_active, nil,
        "serpent: an unlearned Serpent rank leaves the debuff unknown")
    eq(unknown_sb.target_aura_queries, 0,
        "serpent: an unlearned Serpent rank costs no target scan")
end

--=========================================================================================
-- 20) Melee-weave distance approximation (hunter_wa_map Secs 1-3, wago J3U7jOhMI)
--=========================================================================================
-- The WA's Dynamic switch (rotLogicMode 3) mapped onto our model: the live
-- band from main's LibRangeCheck poll (get_weave_band over ST's published
-- fields -- no new probe, no family branch, no C_ spell calls; TBC addon paths
-- stay NAME-based per operator ruling, WA-context C_-with-id is not addon
-- evidence). The inter-poll prog integrator is filed as a build spec (no live
-- caller without the widget lane -- see the note at the end of this block).
-- The engine reads the band but no rule yet (filed arm); the 50% tick, +/-0.7
-- geometry and red/purple WA colours are filed with the widget (our strip
-- keeps its palette).
do
    local H = build().ST.HUNTER

    -- Band: melee wins (the Mode-2 trigger analog), then ranged, then a known
    -- band beyond both, else unknown (never a guess).
    eq(H.get_weave_band(true, true, 0, 5), "melee",
        "band: melee wins over ranged")
    eq(H.get_weave_band(true, false, nil, nil), "melee",
        "band: melee alone reads melee")
    eq(H.get_weave_band(false, true, 0, 5), "ranged",
        "band: the hunter checker reads ranged")
    eq(H.get_weave_band(false, true, nil, nil), "ranged",
        "band: ranged needs no band")
    eq(H.get_weave_band(false, false, 40, nil), "out_of_range",
        "band: a known band beyond both checkers reads out of range")
    eq(H.get_weave_band(0, 0, 0, 5), "out_of_range",
        "band: 0/false probes read out of band, not unknown")
    eq(H.get_weave_band(false, false, nil, nil), nil,
        "band: all-false with no band reads unknown (hides, never far)")
    eq(H.get_weave_band(nil, nil, nil, nil), nil,
        "band: all-unknown reads unknown (hides, never far)")

    -- Family-independence: the same lib fields give the same band on TBC and
    -- Era (no family branch in the hunter path -- the lib's init is main-owned).
    do
        local tbc = build({ project = 5 })
        tbc.ST.in_melee_range = true
        eq(tbc.ST.HUNTER.get_weave_band(tbc.ST.in_melee_range,
            tbc.ST.in_ranged_range, tbc.ST.target_min_range,
            tbc.ST.target_max_range), "melee",
            "band: TBC melee reads melee with no spell probe")
        local era = build({ project = 2 })
        era.ST.in_melee_range = true
        eq(era.ST.HUNTER.get_weave_band(era.ST.in_melee_range,
            era.ST.in_ranged_range, era.ST.target_min_range,
            era.ST.target_max_range), "melee",
            "band: Era melee reads melee with no spell probe")
    end

    -- Gather end-to-end: the band rides the published lib fields, nothing else.
    do
        local sb = build()
        local ST = sb.ST
        eq(ST.HUNTER.gather_guide_inputs(ST, {}).weave_band, nil,
            "gather: no lib state reads unknown (never a guess)")
        ST.in_melee_range = true
        eq(ST.HUNTER.gather_guide_inputs(ST, {}).weave_band, "melee",
            "gather: the lib melee flip lands in the inputs")
        ST.in_melee_range = false
        ST.in_ranged_range = true
        eq(ST.HUNTER.gather_guide_inputs(ST, {}).weave_band, "ranged",
            "gather: the hunter checker lands in the inputs")
        ST.in_ranged_range = false
        ST.target_min_range, ST.target_max_range = 40, nil
        eq(ST.HUNTER.gather_guide_inputs(ST, {}).weave_band, "out_of_range",
            "gather: a known far band lands in the inputs")
        -- Every field is written on every call (the frozen input discipline).
        local out = { weave_band = "stale" }
        ST.in_melee_range, ST.in_ranged_range = nil, nil
        ST.target_min_range, ST.target_max_range = nil, nil
        eq(ST.HUNTER.gather_guide_inputs(ST, out).weave_band, nil,
            "gather: a stale band is cleared when the lib goes quiet")
    end

    -- Prog (the WA's per-frame integrator: speed/7*delta, 4.6 flip, cross
    -- reset, target-motion snap, +/-0.7 range) is FILED as a build spec in
    -- bench/hunter_weave_distance_2026-10-19.md: its live inputs (player
    -- speed/direction, target motion) need compat probes and its only caller
    -- is the filed widget, so landing it here would be a dead hook
    -- (wiring_check check 2). The band above is the wired half.
end

--=========================================================================================
-- 20b) Filed WA leftovers: no hand-rolled item probe, no C_Spell, no CLEU in scope
--=========================================================================================
-- The 5 yd item leg lives in the vendored LibRangeCheck-2.0 (item 8149 is
-- its 5-yard checker) and main's rf_update publishes it -- the hunter scope
-- spends no item probe of its own. TBC addon paths stay NAME-based with no
-- exceptions (operator ruling: the WA's C_Spell-with-id works in the WA
-- context, not the addon context -- take the MODEL, never the call shapes).
-- The live trap active-phase machines need main.lua CLEU registration (out of
-- scope, and only the active phase: the placed phase arms off the existing
-- spellcast hook).
-- This block pins the filed state in the three implementation files.
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end
    local impl = read("classes/hunter.lua") .. read("hunter_guide.lua")
        .. read("hunter_ui.lua")
    check(impl:find("IsItemInRange") == nil,
        "filed: no IsItemInRange probe in the hunter scope (lib owns 8149)")
    check(impl:find("item:8149") == nil,
        'filed: no "item:8149" query in the hunter scope (lib owns 8149)')
    check(impl:find("C_Spell") == nil,
        "filed: no C_Spell call in the hunter scope (TBC addon paths stay name-based)")
    check(impl:find("COMBAT_LOG_EVENT_UNFILTERED") == nil,
        "filed: no CLEU registration in the hunter scope (trap active-phase stays filed)")
end

--=========================================================================================
-- 20c) Melee-weave prog: the pure step (operator-reported WA dynamics, verbatim)
--=========================================================================================
-- bench/hunter_weave_distance_2026-10-19.md prog spec: prog in [-0.7, +0.7], melee
-- negative / ranged positive, re-anchor (lib melee flip -> 0, beats everything) >
-- target snap (+/-0.7 on the current side, +0.7 from exactly 0) > unknown/degenerate
-- hold (prev, defaults 0) > integrate (dir * (speed/7) * delta, clamped) with the
-- backpedal flip (speed < 4.6 flips dir, boundary-exact: 4.6 keeps).
do
    local H = build().ST.HUNTER
    local LIM, RUN, BACK = H.WEAVE_PROG_LIMIT, H.WEAVE_PROG_RUN_SPEED,
        H.WEAVE_PROG_BACKPEDAL_SPEED
    eq(LIM, 0.7, "prog: the bar range is +/-0.7")
    eq(RUN, 7, "prog: the step normalises by full run speed 7")
    eq(BACK, 4.6, "prog: the backpedal band sits below 4.6")

    -- Unknown inputs default: prev 0, dir +1 (the ranged side, matching the snap).
    do
        local prog, dir = H.step_weave_prog(nil, nil, nil, nil, nil, nil, nil)
        eq(prog, 0, "prog: all-unknown holds at the 0 default")
        eq(dir, 1, "prog: an unknown dir defaults to +1")
        prog, dir = H.step_weave_prog(0, 0, nil, nil, nil, nil, nil)
        eq(prog, 0, "prog: a non-sign dir still holds at 0")
        eq(dir, 1, "prog: a non-sign dir reads as +1")
        prog, dir = H.step_weave_prog(0 / 0, 1, 7, 0.5, false, false, nil)
        near(prog, 0.5, "prog: a NaN prev restarts from 0, then integrates")
        eq(dir, 1, "prog: run speed keeps dir after a NaN prev")
    end

    -- Integrate: dir * (speed/7) * delta, clamped to the bar.
    do
        local prog, dir = H.step_weave_prog(0, 1, 7, 0.5, false, false, nil)
        near(prog, 0.5, "prog: full run speed covers 0.5 in half a second")
        eq(dir, 1, "prog: run speed keeps dir")
        prog, dir = H.step_weave_prog(0.5, -1, 7, 0.5, false, false, nil)
        near(prog, 0, "prog: dir -1 walks back toward melee")
        eq(dir, -1, "prog: run speed keeps a -1 dir")
        prog = H.step_weave_prog(0.6, 1, 7, 1, false, false, nil)
        eq(prog, 0.7, "prog: the top clamp holds +0.7")
        prog = H.step_weave_prog(-0.6, -1, 7, 1, false, false, nil)
        eq(prog, -0.7, "prog: the bottom clamp holds -0.7")
    end

    -- Backpedal band: speed < 4.6 flips dir for the next tick; 4.6 itself keeps.
    do
        local prog, dir = H.step_weave_prog(0, 1, 3.5, 1, false, false, nil)
        near(prog, 0.5, "prog: the slow step still integrates")
        eq(dir, -1, "prog: backpedal speed flips dir")
        prog, dir = H.step_weave_prog(0, 1, 4.59, 1, false, false, nil)
        near(prog, 4.59 / 7, "prog: 4.59 still integrates the slow step")
        eq(dir, -1, "prog: 4.59 flips (just inside the band)")
        prog, dir = H.step_weave_prog(0, 1, 4.6, 1, false, false, nil)
        near(prog, 4.6 / 7, "prog: 4.6 still integrates the step")
        eq(dir, 1, "prog: 4.6 keeps dir (boundary-exact)")
        prog, dir = H.step_weave_prog(0.3, 1, 0, 0.5, false, false, nil)
        eq(prog, 0.3, "prog: standing still moves nothing")
        eq(dir, -1, "prog: standing still still flips dir (spec-literal)")
    end

    -- Re-anchor: a lib melee flip forces 0, beating the snap and the integrate.
    do
        local prog, dir = H.step_weave_prog(0.5, 1, 7, 0.5, true, false, nil)
        eq(prog, 0, "prog: melee enter re-anchors to 0")
        eq(dir, 1, "prog: melee enter keeps dir")
        prog, dir = H.step_weave_prog(-0.5, -1, 7, 0.5, false, true, nil)
        eq(prog, 0, "prog: melee exit re-anchors to 0")
        eq(dir, -1, "prog: melee exit keeps dir")
        prog, dir = H.step_weave_prog(0.5, 1, 7, 0.5, true, false, true)
        eq(prog, 0, "prog: re-anchor beats the target snap")
        eq(dir, 1, "prog: re-anchor keeps dir")
        prog = H.step_weave_prog(0.5, 1, 7, 0.5, nil, false, nil)
        near(prog, 0.7, "prog: an unknown flip is no edge (integrates, clamped)")
        prog = H.step_weave_prog(0.5, 1, 7, 0.5, true, nil, nil)
        near(prog, 0.7, "prog: an unknown previous flip is no edge")
    end

    -- Target-motion snap on the current side (+0.7 from exactly 0); only == true snaps.
    do
        local prog, dir = H.step_weave_prog(-0.2, 1, 7, 0.5, false, false, true)
        eq(prog, -0.7, "prog: a moving target snaps the melee side to -0.7")
        eq(dir, 1, "prog: the melee snap keeps dir")
        prog, dir = H.step_weave_prog(0.2, -1, 7, 0.5, false, false, true)
        eq(prog, 0.7, "prog: a moving target snaps the ranged side to +0.7")
        eq(dir, -1, "prog: the snap keeps dir")
        prog = H.step_weave_prog(0, 1, 7, 0.5, false, false, true)
        eq(prog, 0.7, "prog: the snap from exactly 0 takes the ranged side")
        prog, dir = H.step_weave_prog(0.2, 1, 0, 0.5, false, false, 1)
        eq(prog, 0.2, "prog: a non-true target flag never snaps (integrates the 0 step)")
        eq(dir, -1, "prog: the 0 step still flips dir")
    end

    -- Unknown/degenerate inputs hold prev with dir unchanged.
    do
        local prog, dir = H.step_weave_prog(0.3, -1, nil, 0.5, false, false, nil)
        eq(prog, 0.3, "prog: unanswered speed holds prev")
        eq(dir, -1, "prog: the hold keeps dir")
        prog, dir = H.step_weave_prog(0.3, -1, 0 / 0, 0.5, false, false, nil)
        eq(prog, 0.3, "prog: NaN speed holds")
        eq(dir, -1, "prog: NaN speed keeps dir")
        prog = H.step_weave_prog(0.3, -1, -1, 0.5, false, false, nil)
        eq(prog, 0.3, "prog: negative speed holds")
        prog = H.step_weave_prog(0.3, -1, math.huge, 0.5, false, false, nil)
        eq(prog, 0.3, "prog: infinite speed holds (never a clamped slam)")
        prog = H.step_weave_prog(0.3, -1, 7, nil, false, false, nil)
        eq(prog, 0.3, "prog: an unknown delta holds (first tick after enable)")
        prog = H.step_weave_prog(0.3, -1, 7, 0, false, false, nil)
        eq(prog, 0.3, "prog: a 0 delta holds (same-frame double tick)")
        prog = H.step_weave_prog(0.3, -1, 7, -0.5, false, false, nil)
        eq(prog, 0.3, "prog: a negative delta holds")
        prog = H.step_weave_prog(0.3, -1, 7, 0 / 0, false, false, nil)
        eq(prog, 0.3, "prog: a NaN delta holds")
    end
end

--=========================================================================================
-- 20d) Melee-weave prog: live wiring (toggle gate, lib flip, combat-exit clear)
--=========================================================================================
-- update_weave_prog is the pure step's only caller (wiring_check check 2) and runs from
-- on_bar_update; the toggle reads == true (nil = off: no reads, no state), the lib flip
-- re-anchors, combat exit clears the per-fight state.
do
    -- Toggle off (the shipped default, nil): no state is created and no client probe
    -- runs at all (a disabled widget performs no reads).
    do
        local reads = 0
        local sb = build({
            GetUnitSpeed = function() reads = reads + 1 end,
            IsPlayerMoving = function() reads = reads + 1 end,
        })
        local ST = sb.ST
        ST.HUNTER.update_weave_prog(ST)
        eq(ST.hunter_weave_prog, nil, "prog: disabled creates no prog state")
        eq(ST.hunter_weave_dir, nil, "prog: disabled creates no dir state")
        eq(ST.hunter_weave_last_t, nil, "prog: disabled stamps no clock")
        eq(reads, 0, "prog: disabled performs no client reads")
    end

    -- Nil-safe on degenerate selves.
    do
        local ok, err = pcall(build().ST.HUNTER.update_weave_prog, {})
        check(ok, "prog: a self without a class table does not error ("
            .. tostring(err) .. ")")
        ok, err = pcall(build().ST.HUNTER.update_weave_prog, nil)
        check(ok, "prog: a nil self does not error (" .. tostring(err) .. ")")
    end

    -- Toggle on: the first tick holds at the 0 default (no last stamp yet), the next
    -- tick integrates live speed over the suite clock.
    do
        local speeds = { player = 7, target = 0 }
        local sb = build({
            GetUnitSpeed = function(unit) return speeds[unit] end,
            IsPlayerMoving = function() return true end,
        })
        local ST = sb.ST
        sb.class_db.hunter_weave_prog_enabled = true
        ST.HUNTER.update_weave_prog(ST)
        eq(ST.hunter_weave_prog, 0, "prog: the first tick holds at 0 (unknown delta)")
        eq(ST.hunter_weave_dir, 1, "prog: the first tick carries dir +1")
        sb.clock = 0.5
        ST.HUNTER.update_weave_prog(ST)
        near(ST.hunter_weave_prog, 0.5, "prog: run speed integrates over delta")
        -- The lib flip re-anchors mid-fight.
        ST.in_melee_range = false
        sb.clock = 1.0
        ST.HUNTER.update_weave_prog(ST)
        near(ST.hunter_weave_prog, 0.7, "prog: no flip, no snap: integrates to the clamp")
        ST.in_melee_range = true
        sb.clock = 1.5
        ST.HUNTER.update_weave_prog(ST)
        eq(ST.hunter_weave_prog, 0, "prog: the lib melee flip re-anchors live")
        -- A moving target snaps live (from re-anchored 0 to the ranged side).
        speeds.target = 3
        sb.clock = 2.0
        ST.HUNTER.update_weave_prog(ST)
        eq(ST.hunter_weave_prog, 0.7, "prog: target motion snaps live")
        -- Unanswered speed while the player is known-moving holds prev (no 0-fill:
        -- the player may be moving; only a confirmed-not-moving reads as 0).
        speeds.player = nil
        speeds.target = 0
        sb.clock = 2.5
        ST.HUNTER.update_weave_prog(ST)
        eq(ST.hunter_weave_prog, 0.7, "prog: unanswered speed + moving player holds")
        eq(ST.hunter_weave_dir, 1, "prog: the hold keeps dir")
    end

    -- The not-moving 0-fill: no speed probe, player confirmed still -> 0 speed.
    do
        local sb = build({
            GetUnitSpeed = function() return nil end,
            IsPlayerMoving = function() return false end,
        })
        local ST = sb.ST
        sb.class_db.hunter_weave_prog_enabled = true
        ST.hunter_weave_prog = 0.3
        ST.hunter_weave_dir = 1
        ST.hunter_weave_last_t = 0
        sb.clock = 0.5
        ST.HUNTER.update_weave_prog(ST)
        eq(ST.hunter_weave_prog, 0.3, "prog: confirmed still holds prog")
        eq(ST.hunter_weave_dir, -1, "prog: the 0 step still flips dir")
    end

    -- Unanswered speed with unknown motion holds prev (never a 0 guess).
    do
        local sb = build({
            GetUnitSpeed = function() return nil end,
            IsPlayerMoving = function() return nil end,
        })
        local ST = sb.ST
        sb.class_db.hunter_weave_prog_enabled = true
        ST.hunter_weave_prog = 0.3
        ST.hunter_weave_dir = -1
        ST.hunter_weave_last_t = 0
        sb.clock = 0.5
        ST.HUNTER.update_weave_prog(ST)
        eq(ST.hunter_weave_prog, 0.3, "prog: unknown speed + unknown motion holds prev")
        eq(ST.hunter_weave_dir, -1, "prog: the hold keeps dir")
    end

    -- on_bar_update drives the update (the live caller): the ranged tick advances prog.
    do
        local speeds = { player = 7, target = 0 }
        local sb = build({
            GetUnitSpeed = function(unit) return speeds[unit] end,
            IsPlayerMoving = function() return true end,
        })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        sb.class_db.hunter_weave_prog_enabled = true
        ST.HUNTER.on_bar_update(ST, "ranged")
        eq(ST.hunter_weave_prog, 0, "prog: the ranged tick seeds the state")
        sb.clock = 0.5
        ST.HUNTER.on_bar_update(ST, "ranged")
        near(ST.hunter_weave_prog, 0.5, "prog: the ranged tick integrates")
        ST.HUNTER.on_bar_update(ST, "offhand")
        near(ST.hunter_weave_prog, 0.5, "prog: other hands never drive the update")
    end

    -- Combat exit clears the per-fight state (a minutes-old stamp must not slam the
    -- next pull to a limit); the band repopulates from the lib poll.
    do
        local sb = build()
        local ST = sb.ST
        ST.hunter_weave_prog = 0.5
        ST.hunter_weave_dir = -1
        ST.hunter_weave_prev_melee = true
        ST.hunter_weave_last_t = 90
        ST.HUNTER.on_combat_exit(ST)
        eq(ST.hunter_weave_prog, nil, "prog: combat exit clears prog")
        eq(ST.hunter_weave_dir, nil, "prog: combat exit clears dir")
        eq(ST.hunter_weave_prev_melee, nil, "prog: combat exit clears the melee leg")
        eq(ST.hunter_weave_last_t, nil, "prog: combat exit clears the stamp")
    end
end

--=========================================================================================
-- 21) Trap data hygiene (hunter_wa_map §6, wago eEJOoHci- TBC pack)
--=========================================================================================
-- WA CLIENT-OBSERVED (the pack ran on a TBC client), SIM-UNCONFIRMED as timings:
-- the five castable trap ids, the 60 s placed window, the per-trap active
-- lengths and the Clever-adjusted Freezing/Frost pair. Effect ids ride comments
-- only (the filed CLEU lane's plug-in point).
do
    local f = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
    local source = f:read("*a")
    f:close()

    local block = source:match("ST%.HUNTER%.TRAP_SPELLS%s*=%s*{(.-)}")
    check(type(block) == "string", "the TRAP_SPELLS table is found in the source")
    block = block or ""
    local ids = {}
    for n in block:gmatch("%[(%d+)%]") do ids[tonumber(n)] = true end
    local count = 0
    for _ in pairs(ids) do count = count + 1 end
    eq(count, 7, "TRAP_SPELLS holds the five WA trap ids plus the two Wrath LnL sources")
    for _, id in ipairs({ 34600, 13813, 13795, 1499, 13809 }) do
        eq(ids[id], true, "TRAP_SPELLS keeps " .. id .. " (WA CLIENT-OBSERVED)")
    end
    eq(source:find("TRAP_PLACED_DURATION%s*=%s*60[^%.%d]", 1) ~= nil, true,
        "the placed window is the WA 60 s")
    for _, pair in ipairs({ { "snake", 15 }, { "explosive", 20 },
        { "immolation", 15 }, { "freezing", 20 }, { "frost", 30 } }) do
        check(source:find(pair[1] .. "%s*=%s*" .. pair[2], 1) ~= nil,
            "the " .. pair[1] .. " active length is the WA " .. pair[2] .. " s")
    end
    for _, id in ipairs({ 13812, 13797, 3355, 13810 }) do
        check(source:find(tostring(id), 1, true) ~= nil,
            "effect id " .. id .. " is recorded for the filed CLEU lane")
    end
    check(source:find('TRAP_CLEVER_KEYS%s*=%s*{%s*freezing%s*=%s*true%s*,%s*frost%s*=%s*true%s*}', 1) ~= nil,
        "only Freezing/Frost ride the Clever multiplier (WA)")
    check(source:find("CLEVER_TRAPS_BONUS%s*=%s*0%.15", 1) ~= nil,
        "the Clever bonus is the WA 0.15 per rank")
    check(source:find("19239", 1, true) ~= nil,
        "the Clever probe id 19239 is recorded (filed compat probe)")
end

--=========================================================================================
-- 22) Clever Traps math + active durations (pure, nil-safe)
--=========================================================================================
do
    local H = build().ST.HUNTER
    eq(H.clever_traps_mult(nil), 1.0, "clever: unknown rank reads 1.0 (never guess)")
    eq(H.clever_traps_mult(0), 1.0, "clever: rank 0 reads 1.0")
    eq(H.clever_traps_mult(-1), 1.0, "clever: a negative rank reads 1.0")
    eq(H.clever_traps_mult(0 / 0), 1.0, "clever: NaN reads 1.0")
    eq(H.clever_traps_mult("2"), 1.0, "clever: a non-number reads 1.0")
    eq(H.clever_traps_mult(1), 1.15, "clever: rank 1 reads 1.15 (WA 1 + 0.15 x rank)")
    eq(H.clever_traps_mult(2), 1.30, "clever: rank 2 reads 1.30")
    eq(H.clever_traps_mult(3), 1.45, "clever: rank 3 reads 1.45")

    eq(H.get_trap_active_duration("freezing", nil), 20, "active: Freezing untalented is 20 s")
    eq(H.get_trap_active_duration("freezing", 1), 23, "active: Freezing rank 1 is 23 s")
    eq(H.get_trap_active_duration("frost", 2), 39, "active: Frost rank 2 is 39 s")
    eq(H.get_trap_active_duration("snake", 3), 15, "active: Snake ignores the talent")
    eq(H.get_trap_active_duration("explosive", 2), 20, "active: Explosive ignores the talent")
    eq(H.get_trap_active_duration("immolation", 1), 15, "active: Immolation ignores the talent")
    eq(H.get_trap_active_duration("bogus", 2), nil, "active: an unknown key never guesses")
    eq(H.get_trap_active_duration(nil, 2), nil, "active: a nil key never guesses")
end

--=========================================================================================
-- 23) Trap placed-phase wiring (spellcast hook arms, bar tick expires)
--=========================================================================================
do
    -- post_init starts empty (no live trap, no Clever rank until the filed probe).
    do
        local sb = build()
        sb.ST.HUNTER.post_init(sb.ST)
        eq(sb.ST.hunter_trap, nil, "trap: no trap after post_init")
        eq(sb.ST.hunter_clever_rank, nil, "trap: no Clever rank after post_init")
    end

    -- A landed trap cast arms the tracker with the WA 60 s window.
    do
        local sb = build()
        local ST = sb.ST
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 1499)
        check(type(ST.hunter_trap) == "table", "trap: a Freezing cast arms the tracker")
        eq(ST.hunter_trap.key, "freezing", "trap: the 1499 cast arms Freezing")
        eq(ST.hunter_trap.phase, "placed", "trap: the wired phase is placed")
        eq(ST.hunter_trap.spell_id, 1499, "trap: the cast id is kept for the icon lane")
        eq(ST.hunter_trap.placed_at, 0, "trap: the stamp is the suite clock")
        eq(ST.hunter_trap.duration, 60, "trap: the window is the WA 60 s")
        eq(ST.hunter_trap.active_duration, 20, "trap: the Clever-adjusted active length is stamped")
    end

    -- A second trap replaces the first (one trap at a time, WA otherTraps verbatim).
    do
        local sb = build()
        local ST = sb.ST
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 1499)
        sb.clock = 10
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 13813)
        eq(ST.hunter_trap.key, "explosive", "trap: the second cast replaces the first")
        eq(ST.hunter_trap.placed_at, 10, "trap: the replacement re-stamps the clock")
    end

    -- Foreign and nil ids arm nothing; failed casts arm nothing.
    do
        local sb = build()
        local ST = sb.ST
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 12345)
        eq(ST.hunter_trap, nil, "trap: a foreign id arms nothing")
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, nil)
        eq(ST.hunter_trap, nil, "trap: a nil id arms nothing")
        ST.HUNTER.on_spellcast_failed_quiet(ST, "player", nil, 1499)
        eq(ST.hunter_trap, nil, "trap: a failed cast arms nothing")
        local ok, err = pcall(ST.HUNTER.note_trap_cast, nil, 1499)
        check(ok, "trap: a nil self does not error (" .. tostring(err) .. ")")
        ok, err = pcall(ST.HUNTER.update_trap, nil)
        check(ok, "trap: expiry on a nil self does not error (" .. tostring(err) .. ")")
    end

    -- Expiry: holds inside the window, clears on its edge; malformed clears, an
    -- unknown clock holds.
    do
        local sb = build()
        local ST = sb.ST
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 1499)
        ST.HUNTER.update_trap(ST, 59.9)
        check(ST.hunter_trap ~= nil, "trap: 59.9 s holds the placed trap")
        near(ST.HUNTER.get_trap_remaining(ST, 59.9), 0.1, "trap: the remaining counts down")
        ST.HUNTER.update_trap(ST, 60)
        eq(ST.hunter_trap, nil, "trap: the 60 s edge expires the trap")
        eq(ST.HUNTER.get_trap_remaining(ST, 60), nil, "trap: an expired window reads nil")
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 1499)
        ST.HUNTER.update_trap(ST, 0 / 0)
        check(ST.hunter_trap ~= nil, "trap: an unknown clock holds (never guess)")
        eq(ST.HUNTER.get_trap_remaining(ST, 0 / 0), nil, "trap: an unknown clock reads nil")
        eq(ST.HUNTER.get_trap_remaining(ST, nil), 60, "trap: a nil now reads the live clock")
        ST.hunter_trap = {}
        ST.HUNTER.update_trap(ST, 10)
        eq(ST.hunter_trap, nil, "trap: a malformed state clears")
        ST.hunter_trap = {}
        eq(ST.HUNTER.get_trap_remaining(ST, 10), nil, "trap: a malformed state reads nil")
        eq(ST.HUNTER.get_trap_remaining(nil, 10), nil, "trap: a nil self reads nil")
    end

    -- on_bar_update drives the expiry on the live tick; combat exit keeps the
    -- armed trap (it must survive the pull; the 60 s window bounds it).
    do
        local sb = build()
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 13809)
        sb.clock = 61
        ST.HUNTER.on_bar_update(ST, "mainhand")
        eq(ST.hunter_trap, nil, "trap: the bar tick expires the window")
        ST.HUNTER.on_spellcast_succeeded(ST, "player", nil, 13809)
        ST.HUNTER.on_combat_exit(ST)
        check(ST.hunter_trap ~= nil, "trap: combat exit keeps the armed trap (documented)")
    end

    -- Sim wins by construction: the engine never reads trap state (no APL
    -- branches on trap timing, hunter_open §1). No gather input, no rule arm.
    -- The subject is the class's FREEZING TRAP placement state (the armed-trap
    -- timer the class keeps): the APL UTILITY layer's Explosive Trap and
    -- Immolation Trap rows are their own SPELLS with their own cooldowns (the
    -- WotLK mm/sv APLs' i=6 and the Forever APL's i=5), not the placement
    -- state, so the pin reads the placement names.
    do
        local f = assert(io.open(ROOT .. "hunter_guide.lua", "r"))
        local guide_src = f:read("*a")
        f:close()
        check(guide_src:find("inputs%.trap", 1, true) == nil,
            "trap: the pure engine declares no trap input")
        check(guide_src:find("trap_placed", 1, true) == nil,
            "trap: the pure engine declares no trap gate")
        check(guide_src:find("hunter_trap", 1, true) == nil,
            "trap: the pure engine never reads the class's armed-trap state")
        check(guide_src:find("inputs%.rotation_tier", 1, true) == nil,
            "trap: the tier readout stays out of the engine too (display-only)")
        local f2 = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
        local class_src = f2:read("*a")
        f2:close()
        check(class_src:find("inputs%.trap", 1, true) == nil,
            "trap: the gather writes no trap input")
        check(class_src:find("inputs%.hunter_trap", 1, true) == nil,
            "trap: the gather leaks no trap state")
    end
end

--=========================================================================================
-- M1: filed prog row - the weave prog state is write-only until the widget lane.
-- No frame reads hunter_weave_prog (grep-pin pattern): the toggle-gated writer
-- (classes/hunter.lua update_weave_prog) owns it, hunter_ui.lua never consumes it.
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "hunter_ui.lua", "r"))
    local ui_src = f:read("*a")
    f:close()
    check(ui_src:find("hunter_weave_prog", 1, true) == nil,
        "M1: no frame reads hunter_weave_prog (prog stays write-only until the widget lane)")
end

--=========================================================================================
-- P: forced-move drill shot table (the panel's simulated casts)
--=========================================================================================
-- The drill's simulated shots: keys, labels and cast times. Cast times mirror the
-- guide's frozen base casts (no invented numbers); spell ids ride the class rank
-- tables (icon resolution only).
do
    local sb = build()
    local H = sb.ST.HUNTER

    eq(H.PRACTICE_SCENARIO_KEY, "hunter_forced_move",
        "drill: the registry scenario key")
    eq(H.get_practice_scenario_key(), "hunter_forced_move",
        "drill: the key accessor (the UI routing consumer)")

    check(type(H.PRACTICE_SHOTS) == "table", "drill: the shot table exists")
    eq(#H.PRACTICE_SHOTS, 3, "drill: three simulated shots")
    eq(H.PRACTICE_SHOT_ORDER[1], "steady", "drill: shot order starts with steady")
    eq(H.PRACTICE_SHOT_ORDER[2], "multi", "drill: shot order continues with multi")
    eq(H.PRACTICE_SHOT_ORDER[3], "aimed", "drill: shot order ends with aimed")

    eq(H.practice_cast_time("steady"), 1.5, "drill: steady sim cast 1.5 s")
    eq(H.practice_cast_time("multi"), 0.5, "drill: multi sim cast 0.5 s")
    eq(H.practice_cast_time("aimed"), 3.0, "drill: aimed sim cast 3.0 s")
    eq(H.practice_cast_time("sniper"), nil,
        "drill: unknown shot reads nil (never a guessed cast)")
    eq(H.practice_cast_time(nil), nil, "drill: nil shot reads nil")

    eq(H.practice_shot_label("steady"), "Steady Shot", "drill: steady label")
    eq(H.practice_shot_label("multi"), "Multi-Shot", "drill: multi label")
    eq(H.practice_shot_label("aimed"), "Aimed Shot", "drill: aimed label")
    eq(H.practice_shot_label("bogus"), nil, "drill: unknown shot has no label")

    -- Cast times match the guide's frozen base casts exactly (loaded pure here so
    -- the drill cannot drift from the engine it practices).
    local genv = setmetatable({}, { __index = _G })
    local gmod = assert(loadfile(ROOT .. "hunter_guide.lua"))
    setfenv(gmod, genv)
    local okg, errg = pcall(function() gmod("SwedgeTimer", sb.st) end)
    check(okg, "drill: hunter_guide.lua loads pure (" .. tostring(errg) .. ")")
    local hg = sb.st.hunter_guide
    eq(H.practice_cast_time("steady"), hg.STEADY_CAST_SECONDS_DEFAULT,
        "drill: steady mirrors the guide base cast")
    eq(H.practice_cast_time("multi"), hg.MULTI_CAST_SECONDS_DEFAULT,
        "drill: multi mirrors the guide base cast")
    eq(H.practice_cast_time("aimed"), hg.AIMED_CAST_SECONDS_DEFAULT,
        "drill: aimed mirrors the guide base cast")
    eq(H.practice_cast_time("steady"), H.CAST_TIME_FALLBACK.steady.TBC,
        "drill: steady mirrors the per-client TBC fallback")
    eq(H.practice_cast_time("multi"), H.CAST_TIME_FALLBACK.multi.ERA,
        "drill: multi mirrors the per-client Era fallback")
    eq(H.practice_cast_time("aimed"), H.CAST_TIME_FALLBACK.aimed.ERA,
        "drill: aimed mirrors the per-client Era fallback")
end

--=========================================================================================
-- Per-client cast-time fallbacks (the hunter seam's cast-time table)
--=========================================================================================
-- ST.HUNTER.CAST_TIME_FALLBACK scopes the cold-cache fallback by family (sim/archive
-- sourced, CLIENT-UNCONFIRMED where tagged in classes/hunter.lua); the live
-- GetSpellInfo probe always wins when the spell data answers. TBC-name / Era-id
-- discipline holds throughout: the table is keyed by the compat family token, and
-- the state queries behind every probe already run by name on TBC and by id on
-- Era (§10b above).
do
    local tbc = build({ project = 5 })
    eq(tbc.st.family, "TBC", "the project-5 fixture reads the TBC family token")
    eq(tbc.ST.HUNTER.cast_time_fallback("steady"), 1.5,
        "TBC: the Steady fallback reads 1.5 s")
    eq(tbc.ST.HUNTER.cast_time_fallback("multi"), 0.5,
        "TBC: the Multi fallback reads 0.5 s")
    eq(tbc.ST.HUNTER.cast_time_fallback("aimed"), nil,
        "TBC: no Aimed fallback (the Era weave never fires here)")
    eq(tbc.ST.HUNTER.cast_time_fallback("sniper"), nil,
        "TBC: no Sniper fallback (the Forever cast never fires here)")
    local era = build({ project = 2 })
    eq(era.st.family, "ERA", "the project-2 fixture reads the ERA family token")
    eq(era.ST.HUNTER.cast_time_fallback("steady"), nil,
        "Era: no Steady fallback (the spell does not exist here)")
    eq(era.ST.HUNTER.cast_time_fallback("multi"), 0.5,
        "Era: the Multi fallback reads 0.5 s")
    eq(era.ST.HUNTER.cast_time_fallback("aimed"), 3.0,
        "Era: the Aimed fallback reads 3.0 s")
    local wrath = build({ project = 11 })
    eq(wrath.ST.HUNTER.cast_time_fallback("steady"), 1.5,
        "Wrath: the Steady fallback reads 1.5 s")
    eq(wrath.ST.HUNTER.cast_time_fallback("multi"), 0.5,
        "Wrath: the Multi fallback reads 0.5 s")
    eq(wrath.ST.HUNTER.cast_time_fallback("aimed"), nil,
        "Wrath: no Aimed fallback (the Wrath prompt is instant)")
    local fw = build({ project = 18 })
    eq(fw.ST.HUNTER.cast_time_fallback("steady"), nil,
        "Forever: no Steady fallback (the client has no Steady Shot at all)")
    eq(fw.ST.HUNTER.cast_time_fallback("sniper"), 4.0,
        "Forever: the Sniper fallback reads 4.0 s")
    eq(fw.ST.HUNTER.cast_time_fallback("multi"), nil,
        "Forever: no Multi fallback (Multi never prompts here)")
    eq(tbc.ST.HUNTER.cast_time_fallback("bogus"), nil,
        "an unknown shot reads nil (never a guessed cast)")
    eq(tbc.ST.HUNTER.cast_time_fallback(nil), nil,
        "a nil shot reads nil")
end

--=========================================================================================
-- Q: drill icon spell ids (family rank, unknown hides)
--=========================================================================================
do
    -- Default fixture spell data knows Multi-Shot ranks 2643/27021 only.
    local sb = build()
    local H = sb.ST.HUNTER
    eq(H.practice_shot_spell_id("multi"), 27021,
        "drill: multi resolves the highest known rank")
    eq(H.practice_shot_spell_id("steady"), nil,
        "drill: steady unknown hides (never a guessed id)")
    eq(H.practice_shot_spell_id("aimed"), nil,
        "drill: aimed unknown hides (never a guessed id)")
    eq(H.practice_shot_spell_id("bogus"), nil,
        "drill: unknown shot resolves nil")
    eq(H.practice_shot_spell_id(nil), nil,
        "drill: nil shot resolves nil")

    -- A client that knows a Steady rank resolves it (TBC Anniversary shape).
    local tbc = build({ project = 5,
        GetSpellInfo = function(id)
            if id == 34120 then return "Steady Shot", nil, "icon", 0, 0, 0, id end
            return nil
        end,
    })
    eq(tbc.ST.HUNTER.practice_shot_spell_id("steady"), 34120,
        "drill: TBC steady resolves the client rank")

    -- An absent resolver answers nil instead of throwing. The class resolves through
    -- the state API (audit F4), so that is the entry point the guard reads; a fresh
    -- sandbox keeps the cached resolution above out of the answer.
    local bare = build()
    bare.st.api.get_family_spell_id_state = nil
    eq(bare.ST.HUNTER.practice_shot_spell_id("multi"), nil,
        "drill: absent resolver hides (never throws)")
end

--=========================================================================================
-- R: drill session lifecycle (through the real harness shell)
--=========================================================================================
-- Start/run/grade exactly as the panel drives it: new session, begun windows run,
-- simulated casts grade S/A/B/C/D/F, ticks report window transitions, stop ends it.
local function load_practice(st)
    local penv = setmetatable({}, { __index = _G })
    local pmod = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(pmod, penv)
    local ok, err = pcall(function() pmod("SwedgeTimer", st) end)
    check(ok, "drill: practice.lua loads (" .. tostring(err) .. ")")
end

do
    local sb = build({ project = 5 })
    load_practice(sb.st)
    local H = sb.ST.HUNTER
    local pr = sb.st.practice
    check(pr ~= nil and pr.harness ~= nil, "drill: the harness shell exists")

    -- Registry discovery: the top-level Practice tab lists this drill for hunters.
    local found = pr.harness.scenarios_for_class("HUNTER")
    eq(#found, 1, "drill: one hunter scenario is registered")
    eq(found[1].key, "hunter_forced_move",
        "drill: the hunter scenario is the forced-move drill")

    local now = 1000
    local sess = H.practice_new_session(now)
    check(type(sess) == "table", "drill: new session")
    eq(sess.active, false, "drill: a new session is unbegun (no windows yet)")
    eq(H.practice_begin_session(sess, now), true, "drill: begin runs the windows")
    check(sess.active == true and #sess.windows == 5,
        "drill: begun session carries the five windows")
    eq(H.practice_begin_session(sess, now), false,
        "drill: re-begin is rejected (no double run)")
    eq(H.practice_begin_session(nil, now), false,
        "drill: begin on nil is rejected")

    -- Grades: inside a window is F, running into the next is C, margin bands the rest.
    local w1, w2 = sess.windows[1], sess.windows[2]
    eq(H.practice_cast(sess, w1.start_time + 0.1, "steady"), "F",
        "drill: casting inside a move window is F")
    eq(H.practice_cast(sess, w2.start_time - 1.0, "steady"), "C",
        "drill: a cast running into the next window is C")
    eq(H.practice_cast(sess, w2.start_time - 1.8, "steady"), "B",
        "drill: a 0.3 s margin is B")
    eq(H.practice_cast(sess, w2.start_time - 2.5, "steady"), "A",
        "drill: a 1.0 s margin is A")
    local last = sess.windows[#sess.windows]
    eq(H.practice_cast(sess, last.end_time + 10, "steady"), "S",
        "drill: a clear cast with margin is S")

    -- Unscorable casts never grade (unknown shot, idle run, malformed session).
    eq(H.practice_cast(sess, now, "bogus"), nil,
        "drill: unknown shot never grades")
    local idle = H.practice_new_session(now)
    eq(H.practice_cast(idle, now, "steady"), nil,
        "drill: casts outside a run never score")
    eq(H.practice_cast(nil, now, "steady"), nil,
        "drill: nil session never grades")

    -- Ticks report the window transitions; the info clock reads the fight start.
    local out = H.practice_tick(sess, w1.start_time, 0.05, {})
    eq(out.move_started, true, "drill: the tick opens the window")
    out = H.practice_tick(sess, w1.end_time + 0.01, 0.05, {})
    eq(out.move_ended, true, "drill: the tick closes the window")
    local idle_out = H.practice_tick(idle, now, 0.05, nil)
    check(type(idle_out) == "table", "drill: idle tick answers a table")
    eq(idle_out.move_started, nil, "drill: idle tick reports no transition")

    -- Status line: idle / press-fight / MOVE / countdown / clear.
    eq(H.practice_status(nil, now), "Drill idle",
        "drill: nil session reads idle")
    eq(H.practice_status(idle, now), "Press Start Fight",
        "drill: unbegun session prompts the fight")
    eq(H.practice_status(sess, w1.start_time + 0.1), "MOVE - hold casts!",
        "drill: open window prompts the move")
    check(H.practice_status(sess, w1.end_time + 1, now):find("Move in") ~= nil,
        "drill: closed window counts the next move down")
    eq(H.practice_status(sess, last.end_time + 10), "Windows clear - cast freely",
        "drill: no windows left reads clear")

    -- Fight clock and the combat-pause shift.
    near(H.practice_fight_elapsed(sess, now + 5), 5,
        "drill: the fight clock reads the run start")
    eq(H.practice_fight_elapsed(idle, now), nil,
        "drill: idle run has no fight clock")
    eq(H.practice_fight_elapsed(nil, now), nil,
        "drill: nil session has no fight clock")
    local started_at, first_start = sess.started_at, sess.windows[1].start_time
    H.practice_shift_pause(sess, 5)
    eq(sess.started_at, started_at + 5,
        "drill: the pause shifts the fight start")
    eq(sess.windows[1].start_time, first_start + 5,
        "drill: the pause shifts the windows")
    H.practice_shift_pause(sess, 0)
    eq(sess.windows[1].start_time, first_start + 5,
        "drill: a zero shift is a no-op")
    H.practice_shift_pause(sess, 0 / 0)
    eq(sess.windows[1].start_time, first_start + 5,
        "drill: a NaN shift is a no-op")
    H.practice_shift_pause(nil, 5)
    check(true, "drill: shifting nil never throws")

    -- Scoring rides the shared accumulator (session score + bests downstream).
    local score = pr.new_score()
    local grade = H.practice_cast(sess, last.end_time + 10, "multi")
    pr.record_attempt(score, grade, nil)
    local summary = pr.score_summary(score)
    eq(summary.attempts, 1, "drill: the graded cast records one attempt")
    eq(summary.hits, 1, "drill: a clean cast is a hit")
    pr.harness.record_session_attempt(sess,
        H.practice_cast(sess, w1.start_time + 0.1, "steady"))
    local sess_summary = pr.harness.session_summary(sess)
    eq(sess_summary.attempts, 1, "drill: the session scores the F attempt")
    eq(sess_summary.hits, 0, "drill: the F attempt is not a hit")

    -- Stop ends the run; casts after stop never score again.
    eq(H.practice_end_session(sess, now), true, "drill: stop ends the run")
    eq(H.practice_end_session(sess, now), false,
        "drill: double stop is rejected")
    eq(H.practice_end_session(nil, now), false,
        "drill: stop on nil is rejected")
    eq(H.practice_cast(sess, last.end_time + 10, "steady"), nil,
        "drill: casts after stop never score")

    -- Absent shell degrades to nil/false (never throws, never half-runs).
    sb.st.practice = nil
    eq(H.practice_new_session(now), nil, "drill: absent shell news nil")
    eq(H.practice_begin_session(sess, now), false,
        "drill: absent shell begins nothing")
    eq(H.practice_end_session(sess, now), false,
        "drill: absent shell ends nothing")
    eq(H.practice_cast(sess, now, "steady"), nil,
        "drill: absent shell grades nothing")
    check(type(H.practice_tick(sess, now, 0.05, nil)) == "table",
        "drill: absent shell ticks a table")
    eq(H.practice_status(sess, now), "Drill idle",
        "drill: absent shell reads idle")
end

--=========================================================================================
-- S: post_init wires the practice panel (guarded, idempotent)
--=========================================================================================
do
    -- The spy stand-in proves post_init calls practice_ui.init once per run.
    local calls = 0
    local sb = build({ st_extras = {
        practice_ui = { init = function() calls = calls + 1 end },
    } })
    local ok, err = pcall(sb.ST.HUNTER.post_init, sb.ST)
    check(ok, "drill: post_init holds with the practice module ("
        .. tostring(err) .. ")")
    eq(calls, 1, "drill: post_init builds the practice panel")
    sb.ST.HUNTER.post_init(sb.ST)
    eq(calls, 2, "drill: post_init re-inits cleanly (ui.init guards the rebuild)")

    -- Absent module stays inert: no panel call, no throw, no state.
    local bare = build()
    local ok2, err2 = pcall(bare.ST.HUNTER.post_init, bare.ST)
    check(ok2, "drill: post_init holds without the practice module ("
        .. tostring(err2) .. ")")
end

--=========================================================================================
-- T: three-runtime matrix (Era / TBC Anniversary / Forever)
--=========================================================================================
-- The drill is family-independent (pure shell + compat shims, no combat log, no new
-- event registration), so the same session runs and grades on all three runtimes.
-- Client-unknown spell data hides (nil) on every one; nothing throws on any client.
do
    local want_family = { [2] = "ERA", [5] = "TBC", [18] = "FOREVER" }
    for _, project in ipairs({ 2, 5, 18 }) do
        local sb = build({ project = project })
        eq(sb.st.family, want_family[project],
            "drill: project " .. project .. " maps to " .. want_family[project])
        load_practice(sb.st)
        local H = sb.ST.HUNTER
        local now = 500
        local sess = H.practice_new_session(now)
        check(sess ~= nil, "drill: session news on " .. want_family[project])
        eq(H.practice_begin_session(sess, now), true,
            "drill: run begins on " .. want_family[project])
        local w1 = sess.windows[1]
        eq(H.practice_cast(sess, w1.start_time + 0.1, "steady"), "F",
            "drill: window cast grades F on " .. want_family[project])
        local out = H.practice_tick(sess, w1.start_time, 0.05, {})
        eq(out.move_started, true,
            "drill: window opens on " .. want_family[project])
        eq(H.practice_end_session(sess, now), true,
            "drill: run ends on " .. want_family[project])
        local ok, err = pcall(sb.ST.HUNTER.post_init, sb.ST)
        check(ok, "drill: post_init holds on " .. want_family[project]
            .. " (" .. tostring(err) .. ")")

        -- Cold spell cache on every runtime: unknown hides, never throws.
        local cold = build({ project = project,
            GetSpellInfo = function() return nil end,
        })
        eq(cold.ST.HUNTER.practice_shot_spell_id("steady"), nil,
            "drill: cold steady hides on " .. want_family[project])
        eq(cold.ST.HUNTER.practice_shot_spell_id("multi"), nil,
            "drill: cold multi hides on " .. want_family[project])
        eq(cold.ST.HUNTER.practice_shot_spell_id("aimed"), nil,
            "drill: cold aimed hides on " .. want_family[project])
        local okc, errc = pcall(cold.ST.HUNTER.post_init, cold.ST)
        check(okc, "drill: cold-cache post_init holds on " .. want_family[project]
            .. " (" .. tostring(errc) .. ")")
    end
end

--=========================================================================================
-- U: designer coverage (every hunter element rides a registry descriptor)
--=========================================================================================
-- Diffed against docs/swedge/SwedgeTimer_TBC/editmode.lua ELEMENTS (bar, seal icons,
-- success text, NAG, HUD, rotation text, virtual effects, practice rotation, practice
-- timeline): this build registers bars/HUD/rottext/NAG/practice panel + the two
-- delegated practice displays, and hunter's bar children move with the bar overlay
-- (the registry doctrine, not separate targets). Pins: hunter resolves each of its
-- five elements, and the registry holds their descriptors.
do
    local sb = build({ project = 5 })
    local ST = sb.ST
    local H = ST.HUNTER

    -- Cooldown HUD: slots + provider (the hud descriptor's frame source).
    check(type(H.HUD_SLOTS) == "table" and #H.HUD_SLOTS > 0,
        "designer: hunter HUD slots exist")
    check(type(H.get_hud_state) == "function",
        "designer: hunter HUD provider exists")

    -- Next Action Guide: family slot set + gather + evaluate (the nag descriptor).
    check(type(H.guide) == "table" and type(H.guide.slots) == "table"
        and #H.guide.slots > 0,
        "designer: hunter guide slots exist")
    check(type(H.gather_guide_inputs) == "function"
        and type(H.guide.evaluate) == "function",
        "designer: hunter guide gather/evaluate exist")

    -- Rotation label: the contract resolves (idle reads nil, never a guess).
    check(type(H.get_rotation_key) == "function",
        "designer: hunter rotation-key contract exists")
    eq(H.get_rotation_key(ST), nil,
        "designer: idle hunter reads no rotation key (unknown hides)")

    -- Practice panel: post_init builds it (section S) and the drill key routes it.
    eq(H.get_practice_scenario_key(), "hunter_forced_move",
        "designer: the practice panel runs the hunter drill")

    -- Registry shape: the five hunter-ridden descriptors exist in designmode.lua.
    -- Bars register through the bar_descriptor(hand) constructor (one per hand),
    -- the rest by literal key.
    local f = assert(io.open(ROOT .. "designmode.lua", "r"))
    local dm_src = f:read("*a")
    f:close()
    check(dm_src:find('bar_descriptor("ranged")', 1, true) ~= nil,
        "designer: designmode holds the bar_ranged descriptor")
    for _, key in ipairs({ "hud", "rottext", "nag", "practice_panel" }) do
        check(dm_src:find('"' .. key .. '"', 1, true) ~= nil,
            "designer: designmode holds the " .. key .. " descriptor")
    end

    -- Hunter visual set (cast bar, range helper, Rapid Fire bar, aspect icon,
    -- badges): children of the ranged bar frame, so they move with the bar_ranged
    -- overlay - no separate descriptors (the registry doctrine). The shot report
    -- frame is filed: it needs a registry entry plus the central count update
    -- (bench report), so no descriptor ships from this lane.
    local f2 = assert(io.open(ROOT .. "bench/hunter_practice_designer_2026-10-19.md", "r"))
    local bench_note = f2:read("*a")
    f2:close()
    check(bench_note:find("hunter_report", 1, true) ~= nil,
        "designer: the shot-report follow-up is filed with its descriptor spec")
end

--=========================================================================================
-- 24) Shared class order: the per-frame hook and the post_init init order (F8 + F9)
--=========================================================================================
-- The six class modules are copy-paste siblings and used to diverge on two orders:
-- the hunter ticked the HUD before the guide, and the paladin built the practice
-- surface before the HUD. The shared contract is now pinned here, per class:
--   * the per-frame class hook ticks the guide BEFORE the HUD;
--   * post_init builds the guide, then the HUD, then the practice surface.
-- Both the runtime order (spies record the calls) and the source order (the call
-- sites) are pinned, so a reordering in either place fails this suite.
do
    local fh = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    -- Comment lines are dropped first: a call quoted inside a comment (the paladin
    -- HUD block quotes st.hud.init(self)) must not be read as the call itself.
    local code = {}
    for line in src:gmatch("[^\r\n]+") do
        if line:match("^%s*%-%-") == nil then
            code[#code + 1] = line
        end
    end
    code = table.concat(code, "\n")
    local at_guide_tick = code:find("st.nextaction_ui.on_bar_update(self, hand)", 1, true)
    local at_hud_tick = code:find("st.hud.on_bar_update(self, hand)", 1, true)
    local at_guide_init = code:find("st.nextaction_ui.init(self)", 1, true)
    local at_hud_init = code:find("st.hud.init(self)", 1, true)
    local at_practice_init = code:find("st.practice_ui.init(self)", 1, true)
    check(at_guide_tick ~= nil and at_hud_tick ~= nil,
        "order: the class hook drives both the guide and the HUD")
    check(at_guide_init ~= nil and at_hud_init ~= nil and at_practice_init ~= nil,
        "order: post_init drives the guide, the HUD and the practice surface")
    check(at_guide_tick < at_hud_tick,
        "order: the guide tick comes before the HUD tick")
    check(at_guide_init < at_hud_init and at_hud_init < at_practice_init,
        "order: post_init builds the guide, then the HUD, then the practice surface")

    -- Runtime order: the spies record the calls the class actually makes.
    local sbox = build()
    local T = sbox.ST
    local init_order = {}
    local saved = {
        nextaction_ui = sbox.st.nextaction_ui,
        hud = sbox.st.hud,
        practice_ui = sbox.st.practice_ui,
    }
    sbox.st.nextaction_ui = { init = function() init_order[#init_order + 1] = "guide" end }
    sbox.st.hud = { init = function() init_order[#init_order + 1] = "hud" end }
    sbox.st.practice_ui = {
        init = function() init_order[#init_order + 1] = "practice" end,
        is_active = function() return false end,
    }
    local ok_init, err_init = pcall(T.HUNTER.post_init, T)
    check(ok_init, "order: post_init runs with the order spies (" .. tostring(err_init) .. ")")
    eq(init_order[1], "guide", "order: post_init builds the guide first")
    eq(init_order[2], "hud", "order: post_init builds the HUD second")
    eq(init_order[3], "practice", "order: post_init builds the practice surface third")
    eq(#init_order, 3, "order: post_init builds exactly the three surfaces")

    local tick_order = {}
    sbox.st.nextaction_ui = {
        apply_settings = function() end,
        on_bar_update = function() tick_order[#tick_order + 1] = "guide" end,
    }
    sbox.st.hud = { on_bar_update = function() tick_order[#tick_order + 1] = "hud" end }
    local ok_tick, err_tick = pcall(T.HUNTER.on_bar_update, T, "mainhand")
    check(ok_tick, "order: the class hook runs with the order spies (" .. tostring(err_tick) .. ")")
    eq(tick_order[1], "guide", "order: the guide ticks before the HUD")
    eq(tick_order[2], "hud", "order: the HUD ticks after the guide")
    eq(#tick_order, 2, "order: the class hook ticks the guide and the HUD once each")

    sbox.st.nextaction_ui = saved.nextaction_ui
    sbox.st.hud = saved.hud
    sbox.st.practice_ui = saved.practice_ui

end

--=========================================================================================
-- 25) Audit F4 (plain-resolver callers): the guide's rank resolution tells "absent"
--     from "unresolved"
--     The resolver's verdict is three-valued (bench/f4_family_spell_id_2026-10-19.md):
--     a client that refutes every candidate is FINAL (the negative latches), a client
--     that cannot answer is RETRYABLE (nothing latches, the next attempt asks again).
--     Both resolution directions are pinned too: the TBC client resolves by NAME, the
--     Era client by ID.
--=========================================================================================
do
    -- The guide slot a key names (the slot set is family-dependent, so the pins read
    -- the slot by its key instead of by its index).
    local function slot_by_key(slots, key)
        for i = 1, #slots do
            if slots[i].key == key then
                return slots[i]
            end
        end
        return nil
    end

    -- (a) The class resolves through the state API, never through the plain resolver.
    local sb = build({ known = { [34120] = true } })
    local ST = sb.ST
    ST.HUNTER.resolve_guide_icons()
    eq(sb.get_family_spell_id_calls, 0,
        "F4 guide: the class never uses the plain resolver")
    check(sb.get_family_spell_id_state_calls > 0,
        "F4 guide: the class resolves through the state API")
    eq(slot_by_key(ST.HUNTER.guide.slots, "steady").spell_id, 34120,
        "F4 guide: the Steady slot carries the client's rank")
    -- The drill's shot icon shares the guide's verdict: no second walk.
    local after_guide = sb.get_family_spell_id_state_calls
    eq(ST.HUNTER.practice_shot_spell_id("steady"), 34120,
        "F4 drill: the drill icon reads the resolved rank")
    eq(sb.get_family_spell_id_state_calls, after_guide,
        "F4 drill: the drill shares the guide's verdict (no second walk)")

    -- (b) ABSENT: the client refutes every Steady rank. The negative is FINAL - the
    --     table is never walked again, not even after the retry window.
    local ab = build()
    local ABT = ab.ST
    ABT.HUNTER.resolve_guide_icons()
    local after_absent = ab.get_family_spell_id_state_calls
    check(after_absent > 0, "F4 absent: the client is asked")
    ab.clock = 6
    ABT.HUNTER.gather_guide_inputs(ABT, {})
    eq(ab.get_family_spell_id_state_calls, after_absent,
        "F4 absent: the negative is final (never re-walked)")

    -- (c) UNRESOLVED: the client cannot answer (its spell reads come back restricted).
    --     Nothing is latched, so the per-frame path asks again once the retry backoff
    --     has passed - a cold spell book can no longer poison the rank for the session.
    local us = build()
    us.secret_spell_info = true
    local UST = us.ST
    UST.HUNTER.resolve_guide_icons()
    local after_unresolved = us.get_family_spell_id_state_calls
    check(after_unresolved > 0, "F4 unresolved: the client is asked")
    -- Still silent: the retry backoff holds the walk (no hot loop per frame).
    UST.HUNTER.gather_guide_inputs(UST, {})
    eq(us.get_family_spell_id_state_calls, after_unresolved,
        "F4 unresolved: the retry backoff holds the walk")
    -- The drill's own read is bounded by the same backoff (it is not the per-frame path,
    -- but it must not walk the table either while the client cannot answer).
    UST.HUNTER.practice_shot_spell_id("steady")
    eq(us.get_family_spell_id_state_calls, after_unresolved,
        "F4 unresolved: the drill's read inside the backoff window does not walk")
    -- The client answers again after the backoff: the rank resolves and the guide's
    -- known-flag flips (the prompt that was hidden while the client could not answer).
    us.secret_spell_info = false
    us.known[34120] = true
    us.clock = 6
    local us_inputs = UST.HUNTER.gather_guide_inputs(UST, {})
    check(us.get_family_spell_id_state_calls > after_unresolved,
        "F4 unresolved: the attempt after the backoff asks again")
    eq(us_inputs.steady_known, true,
        "F4 unresolved: the late answer reaches the guide (the rank is known)")
    eq(slot_by_key(UST.HUNTER.guide.slots, "steady").spell_id, 34120,
        "F4 unresolved: the late answer re-points the guide slot")

    -- (d) ERA: the rank resolves by ID - the client is never asked by name.
    local era = build({ project = 2, known = { [19434] = true } })
    local ERT = era.ST
    era.spell_queries = {}
    ERT.HUNTER.resolve_guide_icons()
    eq(slot_by_key(ERT.HUNTER.guide.slots, "aimed").spell_id, 19434,
        "F4 Era: the rank resolves by ID and latches")
    local era_asked_by_name = false
    for i = 1, #era.spell_queries do
        if type(era.spell_queries[i]) == "string" then
            era_asked_by_name = true
        end
    end
    check(not era_asked_by_name, "F4 Era: the client is never asked by name")

    -- (e) TBC: a client that answers NO id resolves the rank through the NAME path
    --     (the operator rule: the TBC client indexes names, never bare ids).
    local tbc = build({ project = 5, name_only_client = true, known = { [34120] = true } })
    local TBT = tbc.ST
    tbc.spell_queries = {}
    TBT.HUNTER.resolve_guide_icons()
    eq(slot_by_key(TBT.HUNTER.guide.slots, "steady").spell_id, 34120,
        "F4 TBC: the rank resolves through the NAME path (the client answers no id)")
    local tbc_asked_by_name = false
    for i = 1, #tbc.spell_queries do
        if type(tbc.spell_queries[i]) == "string" then
            tbc_asked_by_name = true
        end
    end
    check(tbc_asked_by_name, "F4 TBC: the client is asked by NAME")
end

--=========================================================================================
-- 26) The APL rotation layer's READ contract (the APL utility rows, 2026-10-20)
--=========================================================================================
-- The rotation table carries the APL's utility/spine rows (the Serpent Sting
-- upkeep, the aspect swaps, the Kill Shot execute - the APL gap analysis,
-- bench/rotation_gap_vs_apl_2026-10-20.md §2). Two flags, cross-class (HU-13,
-- the orchestrator ruling of 2026-10-20):
--   live   the line's READ exists in the shipped tree today AND the line can be
--          evaluated from it
--   engine the frozen guide engine has an arm that can ask for it
-- After the APL UTILITY lane every row of every family but one carries both:
--   live = true, engine ~= false   the read landed and the arm landed
--   live = false, engine = false    the row still waits for a read, and it
--                                    names that exact read in `needs`
-- The ONE row still filed is the Forever Aimed Shot: its read needs the
-- gather's aimed block ungated for the Forever family, which the lane did not
-- touch (the guide's own Forever set declares no Aimed slot either).
do
    local sb = build({ project = 11 })
    local rotations = sb.ST.HUNTER.PRACTICE_ROTATIONS
    local compat_f = assert(io.open(ROOT .. "compat.lua", "r"))
    local compat_source = compat_f:read("*a")
    compat_f:close()

    -- The rows still waiting for a read (the family and the action key).
    local FILED_ROWS = {
        FOREVER = { aimed = true },
    }
    local filed_seen = {}
    for family in pairs(rotations) do
        for i = 1, #rotations[family] do
            local entry = rotations[family][i]
            local filed = FILED_ROWS[family] ~= nil and FILED_ROWS[family][entry.action] == true
            -- HU-13's two flags are STRICT BOOLEANS on every row: a truthiness
            -- test (entry.engine ~= false) would pass for nil, 0 and any truthy
            -- string, and a row with no arm must never look engine-facing.
            check(type(entry.live) == "boolean",
                family .. ": the row " .. tostring(entry.action) .. " declares the live flag")
            check(type(entry.engine) == "boolean",
                family .. ": the row " .. tostring(entry.action) .. " declares the engine flag")
            -- The cross-row rule (the other five classes enforce it): a row that
            -- waits for a read names that read - never an empty `needs`.
            if entry.live == false then
                check(type(entry.needs) == "string" and entry.needs ~= "",
                    family .. ": the row " .. tostring(entry.action)
                        .. " names the read it waits for")
            end
            if filed then
                filed_seen[family .. ":" .. entry.action] = true
                eq(entry.live, false,
                    family .. ": the row " .. tostring(entry.action) .. " still waits for its read")
                eq(entry.engine, false,
                    family .. ": the row " .. tostring(entry.action) .. " has no engine arm yet")
            else
                eq(entry.live, true,
                    family .. ": the row " .. tostring(entry.action) .. " has its read")
                check(entry.engine == true,
                    family .. ": the row " .. tostring(entry.action) .. " is engine-facing")
            end
        end
    end
    for family in pairs(FILED_ROWS) do
        for action in pairs(FILED_ROWS[family]) do
            eq(filed_seen[family .. ":" .. action], true,
                family .. ": the filed row " .. tostring(action) .. " is in the table")
        end
    end

    -- Every filed read uses a compat wrapper that exists today (no new client API).
    for family in pairs(rotations) do
        for i = 1, #rotations[family] do
            local entry = rotations[family][i]
            if entry.live == false then
                check(type(entry.needs) == "string" and entry.needs ~= "",
                    family .. ": the row " .. tostring(entry.action)
                        .. " files the read it needs")
                local wrappers = {}
                for name in tostring(entry.needs):gmatch("api%.([A-Za-z_]+)") do
                    wrappers[name] = true
                end
                check(next(wrappers) ~= nil,
                    family .. ": the filed read of " .. tostring(entry.action)
                        .. " names a compat wrapper")
                for name in pairs(wrappers) do
                    local defined = compat_source:find("function api." .. name .. "(", 1, true) ~= nil
                        or compat_source:find("api." .. name .. " =", 1, true) ~= nil
                    check(defined,
                        family .. ": the filed read of " .. tostring(entry.action)
                            .. " uses the existing compat wrapper api." .. name)
                end
            end
        end
    end
end

--=========================================================================================
-- 27) The APL UTILITY layer's live reads (the utility lane, 2026-10-20)
--=========================================================================================
-- Every line the engine can now ask for is read from the live client through
-- the EXISTING compat wrappers (no new client API):
--   api.GetSpellCooldown   the cooldown lines (the ability off cooldown)
--   api.scan_player_aura    the aspect swaps (a player BUFF, three-state)
--   api.scan_unit_aura      the Hunter's Mark (a target DEBUFF, three-state)
-- The gather writes one known flag, one cooldown and one aura state per line,
-- and every field is written on EVERY call (the frozen input discipline): a
-- line that does not apply to this family reads false/nil, never a stale value.
do
    -- A client whose spell data and spellbook carry the utility lines (the
    -- ranks the APLs cite), so the resolver and the knowledge gate both answer.
    local UTILITY_WRATH_SPELLS = {
        [34074] = "Aspect of the Viper", [61847] = "Aspect of the Dragonhawk",
        [34490] = "Silencing Shot", [49001] = "Serpent Sting",
        [49067] = "Explosive Trap", [63672] = "Black Arrow",
        [49048] = "Multi-Shot", [49052] = "Steady Shot",
    }
    local function utility_spell_info(map)
        return function(id)
            if map[id] then
                return map[id], nil, "icon_" .. id, 0, 0, 0, id
            end
            return nil
        end
    end
    local UTILITY_WRATH_KNOWN = {
        [34074] = true, [61847] = true, [34490] = true, [49001] = true,
        [49067] = true, [63672] = true, [49048] = true, [49052] = true,
    }
    local sb = build({ project = 11, GetSpellInfo = utility_spell_info(UTILITY_WRATH_SPELLS),
        known_spells = UTILITY_WRATH_KNOWN })
    local ST = sb.ST
    ST.HUNTER.post_init(ST)
    local gathered = ST.HUNTER.gather_guide_inputs(ST, {})

    -- The cooldown lines: known and off cooldown (the client answers no
    -- cooldown, so the read is 0 = ready).
    eq(gathered.silencing_shot_known, true, "the WotLK Silencing Shot resolves on a client that knows it")
    eq(gathered.silencing_shot_remaining_cd, 0, "the Silencing Shot reads its cooldown")
    eq(gathered.explosive_trap_known, true, "the WotLK Explosive Trap resolves on a client that knows it")
    eq(gathered.explosive_trap_remaining_cd, 0, "the Explosive Trap reads its cooldown")
    eq(gathered.black_arrow_known, true, "the WotLK Black Arrow resolves on a client that knows it")
    eq(gathered.black_arrow_remaining_cd, 0, "the Black Arrow reads its cooldown")
    -- The utility Multi-Shot (the WotLK rank): known and off cooldown.
    eq(gathered.utility_multi_known, true, "the WotLK Multi-Shot resolves for the utility layer")
    eq(gathered.utility_multi_remaining_cd, 0, "the utility Multi-Shot reads its cooldown")
    -- The aura lines: the buff is KNOWN DOWN (the scan ran and the buff is not
    -- up), so the engine may ask for the line.
    eq(gathered.aspect_viper_known, true, "the Aspect of the Viper resolves on a client that knows it")
    eq(gathered.aspect_viper_active, false, "the Aspect of the Viper reads down (the buff is not up)")
    eq(gathered.aspect_dragonhawk_known, true, "the Aspect of the Dragonhawk resolves")
    eq(gathered.aspect_dragonhawk_active, false, "the Aspect of the Dragonhawk reads down")
    -- The SAME read with the buff UP: the scan finds it, so the line is never
    -- asked for (the buff-up rule). A read that always answered "down" would
    -- break this pin.
    do
        local up = build({ project = 11, GetSpellInfo = utility_spell_info(UTILITY_WRATH_SPELLS),
            known_spells = UTILITY_WRATH_KNOWN })
        up.player_auras = {
            { name = "Aspect of the Viper", id = 34074, count = 1, duration = 20, expiration = 120 },
        }
        up.ST.HUNTER.post_init(up.ST)
        local up_gathered = up.ST.HUNTER.gather_guide_inputs(up.ST, {})
        eq(up_gathered.aspect_viper_active, true,
            "the Aspect of the Viper reads UP when the buff is on the player")
    end
    -- The Serpent Sting: the knowledge flag and the three-state target read.
    eq(gathered.serpent_known, true, "the Serpent Sting knowledge flag resolves")
    check(gathered.serpent_active == nil or gathered.serpent_active == false,
        "the Serpent Sting target read is three-state")
    -- A line that does not apply to this family reads false, never a stale value.
    eq(gathered.aspect_hawk_known, false,
        "the TBC Aspect of the Hawk never reads on a Wrath client")
    eq(gathered.hunters_mark_known, false,
        "the Forever Hunter's Mark never reads on a Wrath client")
    eq(gathered.wing_clip_known, false,
        "the SoD/Forever Wing Clip never reads on a Wrath client")

    -- The SoD client: the ERA token with the Chimera rune known. The SoD's own
    -- utility lines (the Raptor Strike, the Wyvern Strike, the Aspect of the
    -- Falcon) read on that family and only there.
    local sod_sb = build({ project = 2 })
    sod_sb.ST.HUNTER.post_init(sod_sb.ST)
    local sod_gathered = sod_sb.ST.HUNTER.gather_guide_inputs(sod_sb.ST, {})
    eq(sod_gathered.aspect_hawk_known, false,
        "the TBC Aspect of the Hawk never reads on an Era client")
    eq(sod_gathered.hunters_mark_known, false,
        "the Forever Hunter's Mark never reads on an Era client")

    -- The TBC client: the mana-swap rows.
    local tbc = build({ project = 5 })
    tbc.ST.HUNTER.post_init(tbc.ST)
    local tbc_gathered = tbc.ST.HUNTER.gather_guide_inputs(tbc.ST, {})
    check(tbc_gathered.aspect_hawk_known ~= nil,
        "the gather writes the known flag for the Aspect of the Hawk")
    eq(tbc_gathered.aspect_dragonhawk_known, false,
        "the WotLK Aspect of the Dragonhawk never reads on a TBC client")
    -- The Rapid Fire read now covers the Era family too (the ERA APL's i=1).
    local era = build({ project = 2 })
    era.ST.HUNTER.post_init(era.ST)
    local era_gathered = era.ST.HUNTER.gather_guide_inputs(era.ST, {})
    check(era_gathered.rf_known ~= nil,
        "the gather writes the Rapid Fire known flag on the Era family")

    -- The Hunter's Mark (the Forever APL's i=2): the mark on the TARGET, read
    -- through the target scan. The same read with the mark UP proves the scan
    -- really looks (a read that always answered "down" would break it).
    local FOREVER_SPELLS = {
        [14325] = "Hunter's Mark", [14305] = "Immolation Trap",
        [14271] = "Mongoose Bite", [14268] = "Wing Clip",
        [14266] = "Raptor Strike", [2643] = "Multi-Shot",
    }
    local forever = build({ project = 18,
        GetSpellInfo = utility_spell_info(FOREVER_SPELLS),
        known_spells = { [14325] = true, [14305] = true, [14271] = true,
            [14268] = true, [14266] = true, [2643] = true },
        unit_exists = function() return true end })
    forever.ST.HUNTER.post_init(forever.ST)
    local forever_gathered = forever.ST.HUNTER.gather_guide_inputs(forever.ST, {})
    eq(forever_gathered.hunters_mark_known, true,
        "the Forever Hunter's Mark resolves on a client that knows it")
    forever.target_auras = {
        { name = "Hunter's Mark", id = 14325, count = 1, duration = 20, expiration = 120 },
    }
    local up_gathered = forever.ST.HUNTER.gather_guide_inputs(forever.ST, {})
    eq(up_gathered.hunters_mark_active, true,
        "the Hunter's Mark reads UP when the mark is on the target")
end

--=========================================================================================
-- U: the NEUTRAL action set and the practice-panel ability list
--
-- The class publishes ST.HUNTER.practice_neutral_actions (the contract fixed by the
-- orchestrator, practice.lua's class contract block): the keys the practice panel
-- offers but the rotation never grades. A key that is neither a rotation action nor
-- neutral stays a mis-pick, so the set is a deliberate, CLOSED list.
--
-- The publish is FAMILY-SCOPED (a family key -> a set of action keys, resolved for the
-- running client family - st.family). The Raptor Strike is the one key a BUILD can
-- change: the SoD build runs on the Era client (the engine's publish reads st.family
-- only) and the SoD rotation DOES ask for the Raptor Strike - so the class's own
-- build decision drops the key there. A rotation action can never be neutral.
--=========================================================================================
do
    local published = base.ST.HUNTER.practice_neutral_actions
    eq(type(published), "table", "neutral: the hunter publishes a neutral action set")

    local COMMON = { "concussive_shot", "food", "healthstone", "healing_potion", "sprint" }
    local BUCKETS = {
        ERA = { "concussive_shot", "food", "healthstone", "healing_potion", "raptor", "sprint" },
        TBC = { "concussive_shot", "food", "healthstone", "healing_potion", "raptor", "sprint" },
        WRATH = { "concussive_shot", "food", "healthstone", "healing_potion", "sprint" },
        FOREVER = { "concussive_shot", "food", "healthstone", "healing_potion", "sprint" },
    }
    local function sorted(list)
        local out = {}
        for i = 1, #list do out[i] = list[i] end
        table.sort(out)
        return out
    end
    local function same_set(a, b)
        if #a ~= #b then return false end
        for i = 1, #a do
            if a[i] ~= b[i] then return false end
        end
        return true
    end
    local function bucket_keys(bucket)
        local out = {}
        for k, v in pairs(bucket) do
            if v == true then out[#out + 1] = k end
        end
        return sorted(out)
    end

    for family, want in pairs(BUCKETS) do
        local bucket = published[family]
        eq(type(bucket), "table", "neutral: the " .. family .. " bucket is a set")
        if type(bucket) == "table" then
            local want_sorted = sorted(want)
            check(same_set(bucket_keys(bucket), want_sorted),
                "neutral: the " .. family .. " bucket is exactly {"
                .. table.concat(want_sorted, ", ") .. "}")
            for k, v in pairs(bucket) do
                check(type(k) == "string" and k ~= "" and v == true,
                    "neutral: the " .. family .. " bucket holds key = true entries")
            end
        end
    end

    -- NO ROTATION ACTION IS EVER PUBLISHED AS NEUTRAL: the engine grades the
    -- EXPECTED action first, so a rotation press still hits - but a rotation
    -- action published as neutral would make a WRONG rotation press free.
    -- The SoD slice runs on the Era client, so its bucket is the ERA one - and it
    -- is the PICKED one (the SoD build's rotation asks for the Raptor Strike), so
    -- the SoD slice is checked on a SoD sandbox.
    local era = build({ project = 2 })
    era.ST.HUNTER.post_init(era.ST)
    local sod = build({ project = 2,
        known_spells = { [409433] = true },
        known = { [409433] = true, [19574] = true } })
    sod.ST.HUNTER.post_init(sod.ST)
    for _, family in ipairs({ "ERA", "SOD", "TBC", "WRATH", "FOREVER" }) do
        local is_sod = (family == "SOD")
        local module = is_sod and sod.ST.HUNTER or base.ST.HUNTER
        local bucket = is_sod and sod.ST.HUNTER.practice_neutral_actions.ERA
            or published[family]
        local entries = module.practice_rotation_for(family)
        check(type(entries) == "table" and #entries > 0,
            "neutral: the " .. family .. " rotation slice resolves")
        if type(entries) == "table" and type(bucket) == "table" then
            for i = 1, #entries do
                local entry = entries[i]
                if type(entry) == "table" and type(entry.action) == "string" then
                    check(bucket[entry.action] ~= true,
                        "neutral: the rotation action " .. entry.action
                        .. " is not published as neutral on " .. family)
                end
            end
        end
    end

    -- THE BUILD PICK: the Era-base build keeps the Raptor Strike (its rotation
    -- never asks for that spell), the SoD build drops it (the SoD rotation asks
    -- for it, under the key `raptor_strike`).
    eq(era.ST.HUNTER.practice_neutral_actions.ERA.raptor, true,
        "neutral: the Era-base build publishes the Raptor Strike")
    eq(sod.ST.HUNTER.practice_rotation_family(), "SOD",
        "neutral: the SoD build is the SoD rotation family")
    eq(sod.ST.HUNTER.practice_neutral_actions.ERA.raptor, nil,
        "neutral: the SoD build drops the Raptor Strike (a rotation action there)")

    -- THE PRACTICE-PANEL ABILITY LIST: the common abilities the panel offers but
    -- the rotation never grades. Every entry names the client's spell, carries a
    -- label and cites at least one spell id - an ability whose id nobody can
    -- source is not published at all.
    local common = base.ST.HUNTER.practice_common_actions
    eq(type(common), "table", "panel: the hunter publishes a practice-panel ability list")
    check(#common > 0, "panel: the practice-panel ability list is not empty")
    for i = 1, #common do
        local action = common[i]
        eq(type(action), "table", "panel: common action " .. tostring(i) .. " is a table")
        eq(type(action.key), "string", "panel: common action " .. tostring(i) .. " carries a key")
        eq(type(action.label), "string", "panel: common action " .. tostring(action.key)
            .. " carries a label")
        eq(type(action.names), "table", "panel: common action " .. tostring(action.key)
            .. " carries the client's spell name")
        check(#action.names > 0, "panel: common action " .. tostring(action.key)
            .. " names the client's spell")
        eq(type(action.ids), "table", "panel: common action " .. tostring(action.key)
            .. " cites a spell id")
        check(#action.ids > 0, "panel: common action " .. tostring(action.key)
            .. " cites at least one spell id")
        for j = 1, #action.ids do
            eq(type(action.ids[j]), "number", "panel: common action " .. tostring(action.key)
                .. " cites a numeric spell id")
        end
        -- Published as neutral on every family the class publishes a bucket for.
        for _, family in ipairs({ "ERA", "TBC", "WRATH", "FOREVER" }) do
            eq(published[family][action.key], true, "panel: " .. tostring(action.key)
                .. " is published as neutral on " .. family)
        end
        -- Never a rotation action on any family the hunter plays.
        for _, family in ipairs({ "ERA", "SOD", "TBC", "WRATH", "FOREVER" }) do
            local entries = base.ST.HUNTER.practice_rotation_for(family)
            local rotation = false
            for k = 1, #entries do
                if entries[k].action == action.key then rotation = true end
            end
            check(not rotation, "panel: the common ability " .. tostring(action.key)
                .. " is not a rotation action on " .. family)
        end
    end
    -- The five common abilities are exactly the ones the publish names.
    eq(#common, 5, "panel: the hunter publishes five common abilities")
    local common_keys = {}
    for i = 1, #common do common_keys[common[i].key] = true end
    for _, key in ipairs(COMMON) do
        eq(common_keys[key], true, "panel: the common ability " .. key .. " is published")
    end

    -- THE WIDENING SEAM: the class publishes the widened slot list and applies it
    -- to the guide slot list (the shaman's apply_family_slots precedent), so the
    -- practice panel offers the common abilities.
    eq(type(base.ST.HUNTER.practice_panel_slots), "function",
        "panel: the class publishes the panel slot list")
    eq(type(base.ST.HUNTER.apply_practice_panel_actions), "function",
        "panel: the class publishes the widening seam")
    local seam = build({ project = 11,
        known = { [5116] = true, [2983] = true, [5720] = true, [439] = true, [433] = true } })
    local seamST = seam.ST
    local before = #seamST.HUNTER.guide.slots
    local widened = seamST.HUNTER.practice_panel_slots()
    eq(type(widened), "table", "panel: the panel slot list is a table")
    eq(#widened, before + 5, "panel: the panel slot list carries the common abilities")
    seamST.HUNTER.apply_practice_panel_actions()
    eq(#seamST.HUNTER.guide.slots, before + 5,
        "panel: the widening seam appends the common abilities to the slot list")
    seamST.HUNTER.apply_practice_panel_actions()
    eq(#seamST.HUNTER.guide.slots, before + 5,
        "panel: the widening seam is idempotent")
    -- The widened slots carry their own icons (the client's own rank) and the
    -- common marker the seam looks for.
    local common_slot = nil
    for i = 1, #seamST.HUNTER.guide.slots do
        local slot = seamST.HUNTER.guide.slots[i]
        if type(slot) == "table" and slot.key == "concussive_shot" then common_slot = slot end
    end
    check(common_slot ~= nil, "panel: the Concussive Shot joins the slot list")
    eq(common_slot and common_slot.spell_id, 5116,
        "panel: the Concussive Shot carries the client's own spell id")
    eq(common_slot and common_slot.practice_common, true,
        "panel: the common slot carries the common marker")
    -- UNKNOWN-HIDES: a client that does not have the spell never gets the button.
    local blind = build({ project = 11 })
    eq(#blind.ST.HUNTER.practice_panel_slots(), #blind.ST.HUNTER.guide.slots,
        "panel: a client without the spells is offered no common ability")
    -- The WIRING: post_init widens the panel's slot list (the seam runs inside the
    -- practice block, after the guide frame has built its icons).
    local wired = build({ project = 11,
        known = { [5116] = true, [2983] = true, [5720] = true, [439] = true, [433] = true },
        st_extras = { practice_ui = { init = function() end } } })
    local before_wired = #wired.ST.HUNTER.guide.slots
    wired.ST.HUNTER.post_init(wired.ST)
    eq(#wired.ST.HUNTER.guide.slots, before_wired + 5,
        "panel: post_init widens the panel's slot list with the common abilities")
end

-- ---- the shipped comment matches the code (the final-gate claim) -------------
-- The FOR THE RECORD note claimed "the NAME-first resolution finds the client's
-- own rank": the classic-line name leg is UNCONFIRMED in-client (the audit's
-- §6 C1) and the id table is the citation and the fallback - the client's own
-- rank only where that id still exists on it. The pins keep the stale claim OUT
-- and the corrected statement IN (source-shape pins, so a correct rewording
-- still passes).
--
-- THE MATCH IS ON PROSE, NOT ON SOURCE LINES: the claim is wrapped across
-- three source lines here, so the file is flattened (the line-leading comment
-- marker dropped, the lines joined with one space) and the sentence is matched
-- whole.
do
    local function prose(path)
        local fh = io.open(path, "r")
        local src = fh and fh:read("*a") or ""
        if fh then fh:close() end
        local parts = {}
        for line in (src:gsub("\r\n", "\n")):gmatch("[^\n]*") do
            parts[#parts + 1] = (line:gsub("^%s*%-%-%s*", ""))
        end
        return (table.concat(parts, " "):gsub("%s+", " "))
    end
    local p = prose(ROOT .. "classes/hunter.lua")
    check(p:find("every client family answers its own rank art", 1, true) == nil,
        "comment: the stale 'every client family answers its own rank art' claim is gone")
    check(p:find("the NAME-first resolution finds the client's own rank", 1, true) == nil,
        "comment: the stale 'the NAME-first resolution finds the client's own rank' claim is gone")
    check(p:find("answers its own rank id", 1, true) ~= nil,
        "comment: the resolver note says what the code does")
    check(p:find("the NAME-first leg finds the client's own rank only where the client ANSWERS the name", 1, true) ~= nil,
        "comment: the FOR THE RECORD note states the name leg as conditional and UNCONFIRMED")
end

--=========================================================================================
-- 28) The font chain: no FontString is ever given text without a font
--
-- The operator's TBC client reported `FontString:SetText(): Font not set` at
-- hunter_ui.lua:309 - the H1 target-warning label was given its text before any
-- SetFont, so the client rejected the text. The sandbox above is SoD-faithful
-- (SetText with no font throws, SetFont(nil) latches nothing), so a font-stripped
-- build dies in this section.
--
-- The chain is shared (utils.lua): the LSM path, then STANDARD_TEXT_FONT, then
-- the classic client font - every step pcall-guarded, never throwing.
--=========================================================================================
do
    -- The target warning is written once, at creation: a build without a font
    -- throws "Font not set" right here.
    local sb = build_ui({ target_warning_enabled = true })
    local ok_build, err_build = pcall(sb.ST.HUNTER.post_init, sb.ST)
    check(ok_build, "font: the hunter UI builds with no font error (" .. tostring(err_build) .. ")")

    local ui = sb.st.hunter_ui
    check(ui.target_warning ~= nil, "font: the target-warning label exists")
    eq(ui.target_warning:GetFont(), "Fonts\\FIXEDFONT.TTF",
        "font: the target-warning label carries the LSM font path")
    eq(ui.target_warning.text, ">> TARGETING YOU <<",
        "font: the target-warning label still carries its text")
    eq(ui.cast_frame.text:GetFont(), "Fonts\\FIXEDFONT.TTF",
        "font: the cast-bar text carries the LSM font path")
    eq(ui.rapid_fire_bar.label:GetFont(), "Fonts\\FIXEDFONT.TTF",
        "font: the Rapid Fire label carries a font (it is written per frame)")
    eq(ui.bw_badge.text:GetFont(), "Fonts\\FIXEDFONT.TTF",
        "font: the Blood Frenzy badge text carries a font")
    eq(ui.frenzy_badge.text:GetFont(), "Fonts\\FIXEDFONT.TTF",
        "font: the Frenzy badge text carries a font")

    -- A key that no longer resolves (the operator's font lives in another addon's
    -- LSM registration): the chain falls back and the build still works.
    local n = build_ui({ lsm_font_nil = true })
    local ok_n, err_n = pcall(n.ST.HUNTER.post_init, n.ST)
    check(ok_n, "font: an unresolvable LSM font never throws (" .. tostring(err_n) .. ")")
    eq(n.st.hunter_ui.target_warning:GetFont(), "Fonts\\STANDARD.TTF",
        "font: an unresolvable LSM font falls back to STANDARD_TEXT_FONT")

    -- STANDARD missing too: the classic client font carries the label.
    local m = build_ui({ lsm_font_nil = true, no_std_font = true })
    local ok_m, err_m = pcall(m.ST.HUNTER.post_init, m.ST)
    check(ok_m, "font: no LSM font and no STANDARD never throws (" .. tostring(err_m) .. ")")
    eq(m.st.hunter_ui.target_warning:GetFont(), "Fonts\\FRIZQT__.TTF",
        "font: the classic client font is the last resort")

    -- A throwing Fetch: pcall-guarded, falls back, never throws.
    local t = build_ui({ lsm_throw = true })
    local ok_t, err_t = pcall(t.ST.HUNTER.post_init, t.ST)
    check(ok_t, "font: a throwing LSM Fetch never throws (" .. tostring(err_t) .. ")")
    check(t.st.hunter_ui.target_warning:GetFont() ~= nil,
        "font: a throwing Fetch still leaves a font latched")

    -- The shared chain (utils.lua) on its own: it never throws, and it always
    -- leaves a font that exists.
    local u = build_ui({})
    local ok_fetch, path = pcall(u.st.utils.fetch_font_path, "Expressway")
    check(ok_fetch, "font: the LSM key resolution never throws")
    eq(path, "Fonts\\FIXEDFONT.TTF", "font: the LSM key resolves to the registered path")
    local ok_none, none = pcall(u.st.utils.fetch_font_path, nil)
    check(ok_none and none == nil, "font: a nil key resolves to nil and never throws")
    local ok_empty, empty = pcall(u.st.utils.fetch_font_path, "")
    check(ok_empty and empty == nil, "font: an empty key resolves to nil and never throws")

    -- A missing LSM library: type-guarded, never throws.
    local saved_libstub = u.env.LibStub
    u.env.LibStub = function() return nil end
    local ok_nolsm, nolsm = pcall(u.st.utils.fetch_font_path, "Expressway")
    u.env.LibStub = saved_libstub
    check(ok_nolsm and nolsm == nil,
        "font: a missing LSM library resolves to nil and never throws")

    -- A FontString that cannot take a font: the chain reports it and never throws.
    local hostile = {}
    local ok_hostile, applied = pcall(u.st.utils.apply_font, hostile, "Fonts\\X.TTF", 12, "")
    check(ok_hostile and applied == false,
        "font: a FontString without SetFont is refused and never thrown")

    -- A FontString whose SetFont throws: the chain degrades and never throws.
    local throwing = {
        SetFont = function() error("no font", 2) end,
        GetFont = function() return nil end,
    }
    local ok_throw, applied_throw = pcall(u.st.utils.apply_font, throwing, "Fonts\\X.TTF", 12, "")
    check(ok_throw, "font: a throwing SetFont never escapes the chain")
    check(applied_throw == false, "font: a throwing SetFont is reported as not applied")

    -- A FontString that refuses the first path (SetFont returns false) still gets
    -- the next candidate.
    local refusing = { font = nil }
    function refusing:SetFont(font_path)
        if font_path == "Fonts\\X.TTF" then
            return false
        end
        self.font = font_path
        return true
    end
    function refusing:GetFont() return self.font end
    local ok_ref, applied_ref = pcall(u.st.utils.apply_font, refusing, "Fonts\\X.TTF", 12, "")
    check(ok_ref and applied_ref == true, "font: a refused path degrades to the next candidate")
    eq(refusing.font, "Fonts\\STANDARD.TTF",
        "font: the refused path falls back to STANDARD_TEXT_FONT")

    -- The last resort: with STANDARD missing, the classic client font carries it.
    local saved_std = u.env.STANDARD_TEXT_FONT
    u.env.STANDARD_TEXT_FONT = nil
    local last = { font = nil }
    function last:SetFont(font_path) self.font = font_path return true end
    function last:GetFont() return self.font end
    local ok_last, applied_last = pcall(u.st.utils.apply_font, last, nil, 12, "")
    u.env.STANDARD_TEXT_FONT = saved_std
    check(ok_last and applied_last == true, "font: a nil path still leaves a font")
    eq(last.font, "Fonts\\FRIZQT__.TTF", "font: the classic client font is the last resort")

    -- Source order: the font goes on before the first SetText, in the source too.
    local fh = assert(io.open(ROOT .. "hunter_ui.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    local apos = src:find("st.utils.apply_font(label, font_path, TARGET_WARNING_TEXT_SIZE", 1, true)
    local tpos = src:find("label:SetText(TARGET_WARNING_TEXT)", 1, true)
    check(apos ~= nil and tpos ~= nil and apos < tpos,
        "font: the target-warning label is fonted before its first SetText (source order)")
    check(src:find(":SetFont(", 1, true) == nil,
        "font: hunter_ui.lua has no direct SetFont call (the shared chain owns every font)")
end

if failures == 0 then
    print("PASS  hunter_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  hunter_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end