-- tests/hunter_state.lua: offline tests for the hunter module (classes/hunter.lua) over the
-- real compat.lua + utils.lua in a sandbox.
-- Pins post_init flag initialisation, the Raptor Strike queue detection and its option
-- gate, the spellcast clear paths, the pre-init guards and the on-next-attack colour matrix.
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
        current_spell = opts.current_spell, -- the only id IsCurrentSpell answers true for
        is_current_spell_calls = 0,
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
    env.IsCurrentSpell = function(id)
        sb.is_current_spell_calls = sb.is_current_spell_calls + 1
        return id == sb.current_spell
    end

    -- compat.lua reads IsCurrentSpell through _G (it is absent on Mainline-code clients);
    -- mirror the stub for the duration of its load, then restore _G exactly.
    local mirrored_is_current_spell = rawget(_G, "IsCurrentSpell")
    _G.IsCurrentSpell = env.IsCurrentSpell

    local st = {}
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)

    _G.IsCurrentSpell = mirrored_is_current_spell

    -- The addon object: only the surface classes/hunter.lua touches.
    local ST = { HUNTER = {} }
    -- The real HUNTER defaults (config_presets.lua), so a wrong colour is a module bug
    -- and not a fixture bug.
    local class_db = {
        enable_raptor_strike_color = true,
        raptor_strike_color = { 207, 58, 83, 1.0 },
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
    check(type(ST.HUNTER.post_init) == "function", "post_init is the flag initialiser")

    local ok, err = pcall(ST.HUNTER.post_init, ST)
    check(ok, "post_init runs in the sandbox (" .. tostring(err) .. ")")
    eq(ST.raptor_strike_queued, false, "post_init initialises raptor_strike_queued to false")

    -- Idempotent, and it must also clear a flag left over from a previous session.
    ST.raptor_strike_queued = true
    ST.HUNTER.post_init(ST)
    eq(ST.raptor_strike_queued, false, "post_init clears a stale queue flag")
    ST.HUNTER.post_init(ST)
    eq(ST.raptor_strike_queued, false, "post_init is idempotent")
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
end

if failures == 0 then
    print("PASS  hunter_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  hunter_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end