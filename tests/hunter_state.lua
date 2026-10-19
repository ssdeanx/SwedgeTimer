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
local RAPTOR_RANKS = 10

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
        current_spell = opts.current_spell, -- the only id IsCurrentSpell answers true for
        is_current_spell_calls = 0,
        channel_spell = opts.channel_spell, -- the spell id UnitChannelInfo reports, or nil
        channel_calls = 0,
        bar_color_calls = 0,
        set_vertex_calls = 0,
        last_hand = nil,
        vertex = nil,
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
    -- the real compat scan; nothing else here reads them).
    env.GetTime = function() return sb.clock end
    env.UnitAura = function(unit, index, filter)
        if unit ~= "player" or filter ~= "HELPFUL" then return nil end
        local entry = sb.player_auras[index]
        if not entry then return nil end
        return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
            nil, nil, nil, entry.id
    end
    -- Minimal client spell data: the reference Multi-Shot ranks resolve their localized
    -- name (get_cast_grace's name fallback); everything else is unknown to this fixture.
    env.GetSpellInfo = opts.GetSpellInfo or function(id)
        if id == 2643 or id == 27021 then
            return "Multi-Shot", nil, "icon", 0, 0, 0, id
        end
        return nil
    end
    env.IsCurrentSpell = function(id)
        sb.is_current_spell_calls = sb.is_current_spell_calls + 1
        return id == sb.current_spell
    end
    -- Spell knowledge for the Wrath spec detector (Chimera = MM, Explosive = SV)
    -- and the SoD rune detector: opts.known_spells maps id -> true, defaulting to
    -- "nothing learned" so existing fixtures resolve nothing new.
    env.IsSpellKnown = function(id)
        local known = opts.known_spells
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

    -- compat.lua reads several legacy globals through _G (annotation-safe on
    -- Mainline-code clients); mirror EVERY sandbox stub for the duration of its load,
    -- then restore _G exactly.
    local mirrored = {}
    for name, value in pairs(env) do
        mirrored[name] = rawget(_G, name)
        _G[name] = value
    end

    local st = {}
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)

    for name, previous in pairs(mirrored) do
        _G[name] = previous
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
    "on_bar_update", "get_cast_grace",
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
        function region:SetText(text) self.text = text end
        function region:SetTexture(texture) self.texture = texture end
        function region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        function region:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
        return region
    end

    local function build_ui(opts)
        opts = opts or {}
        local sb = {
            now = opts.now or 0,
            calls = { cast = 0, aura = 0, in_range = 0, interact = 0, restore = 0 },
            live_cast = opts.live_cast,
            auras = opts.auras,
            pet_auras = opts.pet_auras,
            in_range = opts.in_range,
            sweet = opts.sweet,
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
        env.CheckInteractDistance = function(unit, index)
            sb.calls.interact = sb.calls.interact + 1
            if sb.sweet == nil then
                return nil
            end
            return sb.sweet
        end

        -- compat.lua reads several legacy globals through _G; mirror EVERY stub for the
        -- duration of its load, then restore _G exactly (same discipline as build()).
        local mirrored = {}
        for name, value in pairs(env) do
            mirrored[name] = rawget(_G, name)
            _G[name] = value
        end

        local st = {}
        local compat = assert(loadfile(ROOT .. "compat.lua"))
        setfenv(compat, env)
        compat("SwedgeTimer", st)

        for name, previous in pairs(mirrored) do
            _G[name] = previous
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

        local ui_mod = assert(loadfile(ROOT .. "hunter_ui.lua"))
        setfenv(ui_mod, env)
        ui_mod("SwedgeTimer", st)

        local class_mod = assert(loadfile(ROOT .. "classes/hunter.lua"))
        setfenv(class_mod, env)
        class_mod("SwedgeTimer", st)

        sb.st = st
        sb.ST = ST
        sb.class_db = class_db
        sb.hand_db = hand_db
        sb.mh_anchor = mh_anchor
        sb.oh_anchor = oh_anchor
        sb.ranged_bar_frame = ranged_bar_frame
        return sb
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
        eq(sb.calls.interact, 0, "the range helper off means zero interaction-distance reads")
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

    -- 14e) the range helper colour follows range_state's priority ladder.
    do
        local sb = build_ui({ has_target = true, in_range = { ["Auto Shot"] = 1 } })
        sb.ST.HUNTER.post_init(sb.ST)
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        local helper = sb.st.hunter_ui.range_helper
        check(helper.shown == true, "the range helper shows with an attackable target")
        check(helper.tex.color ~= nil and math.abs(helper.tex.color[3] - 1.00) < 1e-9,
            "a ranged-only reading paints the ranged colour")

        sb.sweet = true
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(helper.tex.color[1], 0.98, "a sweet-spot reading paints its own colour")

        sb.in_range = { ["Wing Clip"] = 1 }
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(helper.tex.color[2], 0.85, "melee range wins over the sweet spot")

        sb.in_range = { ["Auto Shot"] = 0 }
        sb.sweet = false
        sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
        near(helper.tex.color[1], 0.50, "no band paints out of range")

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
    eq(table_count(kill_shot), 2, "the Kill Shot table holds both wotlk ids")
    eq(kill_shot[53351], true, "the Kill Shot table keeps 53351")
    eq(kill_shot[34104], true, "the Kill Shot table keeps the older 34104")

    local chimera_wrath = table_ids("chimera_shot_wrath_ids")
    eq(table_count(chimera_wrath), 1, "the Wrath Chimera table holds its single id")
    eq(chimera_wrath[53209], true, "the Wrath Chimera table keeps 53209")

    local explosive = table_ids("explosive_shot_ids")
    eq(table_count(explosive), 1, "the Explosive table holds only the confirmed rank")
    eq(explosive[53301], true, "the Explosive table keeps 53301")

    local aimed_wrath = table_ids("aimed_shot_wrath_ids")
    eq(table_count(aimed_wrath), 2, "the Wrath Aimed table holds two ranks")
    eq(aimed_wrath[49050], true, "the Wrath Aimed table keeps 49050")
    eq(aimed_wrath[27065], true, "the Wrath Aimed table keeps the TBC 27065")

    local arcane = table_ids("arcane_shot_ids")
    eq(table_count(arcane), 2, "the Arcane table holds two ranks")
    eq(arcane[49045], true, "the Arcane table keeps 49045")
    eq(arcane[27019], true, "the Arcane table keeps the TBC 27019")

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

    -- The slot set is picked at load, before any post_init resolve.
    eq(slot_keys(build({ project = 11 }).ST), "kill_shot,chimera,explosive,aimed,arcane,steady",
        "WRATH loads the six-slot Wrath set")
    eq(slot_keys(build({ project = 2 }).ST), "aimed,raptor,multi",
        "ERA loads the three-slot Era set")
    eq(slot_keys(build({ project = 5 }).ST),
        "steady,raptor,kill_command,multi,bestial_wrath,rapid_fire",
        "TBC keeps the frozen base set")
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
        eq(#slots, 6, "Wrath MM still declares six slots")
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

    -- SoD (ERA token, rune learned): the Era set swaps to the four-slot set.
    do
        local sb = build({ project = 2, GetSpellInfo = spell_info(ERA_SPELLS),
            known_spells = { [409433] = true } })
        local ST = sb.ST
        ST.HUNTER.post_init(ST)
        eq(slot_keys(ST), "chimera,aimed,raptor,multi",
            "SoD swaps the Era set to the four-slot Chimera set")
        eq(ST.HUNTER.guide.slots[1].spell_id, 409433, "SoD resolves the Chimera rune icon")
        local gathered = ST.HUNTER.gather_guide_inputs(ST, {})
        eq(gathered.chimera_known, true, "SoD: the learned rune weaves")
        eq(gathered.aimed_known, true, "SoD keeps the Era Aimed weave below Chimera")
    end

    -- Every non-SoD shape keeps the plain Era set: rune in data but unlearned,
    -- and the rune learned on a non-Era family (the family gate).
    do
        local unlearned = build({ project = 2, GetSpellInfo = spell_info(ERA_SPELLS) })
        unlearned.ST.HUNTER.post_init(unlearned.ST)
        eq(slot_keys(unlearned.ST), "aimed,raptor,multi",
            "Era without the rune keeps the three-slot set")
        eq(unlearned.ST.HUNTER.gather_guide_inputs(unlearned.ST, {}).chimera_known, false,
            "Era without the rune never weaves Chimera")

        local tbc = build({ project = 5, GetSpellInfo = spell_info(ERA_SPELLS),
            known_spells = { [409433] = true } })
        tbc.ST.HUNTER.post_init(tbc.ST)
        eq(slot_keys(tbc.ST),
            "steady,raptor,kill_command,multi,bestial_wrath,rapid_fire",
            "TBC never takes the SoD set even with the rune known")
    end
end

--=========================================================================================
-- R4: lust-gate nil-semantics (closed-on-unknown) through the real gather
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    -- Bloodlust on the player with 30 s left on the suite clock.
    sb.player_auras = { { name = "Bloodlust", id = 2825, duration = 40, expiration = 30 } }

    -- Explicit true: the guide sees the lust window.
    sb.st.lust_supported = true
    local out = ST.HUNTER.gather_guide_inputs(ST, {})
    eq(out.lust_remaining, 30, "R4: explicit true arms the lust scan")

    -- nil (a pre-C2 compat) stays off even with the aura present.
    sb.st.lust_supported = nil
    ST.hunter_lust_at = nil
    ST.hunter_lust_remaining = nil
    out = ST.HUNTER.gather_guide_inputs(ST, {})
    eq(out.lust_remaining, nil, "R4: nil lust_supported reports no window (closed-on-unknown)")

    -- false stays off too.
    sb.st.lust_supported = false
    out = ST.HUNTER.gather_guide_inputs(ST, {})
    eq(out.lust_remaining, nil, "R4: false lust_supported reports no window")

    -- R4 standardisation: the hunter consumer is the closed-on-unknown spelling,
    -- identical to the paladin's (classes/paladin.lua:1101). A truthy non-true value
    -- must not arm the scan - that is the whole point of == true.
    local src = (function()
        local f = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
        local s = f:read("*a")
        f:close()
        return s
    end)()
    check(src:find("if st.lust_supported == true and lust_ids", 1, true) ~= nil,
        "R4: the hunter lust gate is the closed-on-unknown (== true) spelling")
    sb.st.lust_supported = 1
    ST.hunter_lust_at = nil
    ST.hunter_lust_remaining = nil
    out = ST.HUNTER.gather_guide_inputs(ST, {})
    eq(out.lust_remaining, nil, "R4: a truthy non-true gate never arms the scan")
end

if failures == 0 then
    print("PASS  hunter_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  hunter_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end