-- tests/warrior_state.lua: offline tests for the warrior module (classes/warrior.lua)
-- over the real compat.lua + utils.lua in a sandbox.
-- Pins the pre-init guards, the rage-cost evaluation and its colour reset, the negative
-- rank latch, Heroic Strike / Cleave spell-table hygiene, the Cleave option gate, the
-- Blood Surge glow state-change guard and the on-next-attack colour matrix.
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

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- One throwaway client profile per call: a fresh environment (a metatable over _G, so an
-- absent global is shadowed with nil rather than removed), the real compat.lua + utils.lua
-- loaded into it, then classes/warrior.lua on top. Sandboxes are independent because the
-- module's resolved-rank cache is a file-scoped local: only a fresh load can re-exercise
-- the "resolve on first use" path.
local function build(opts)
    opts = opts or {}

    -- Mutable fixture state, shared with the stub closures.
    local sb = {
        clock = 0,
        power = 0,
        rage_cost = nil,          -- what GetSpellPowerCost returns (nil = no cost data)
        known = opts.known or {}, -- spell ids this client knows
        current_spell = opts.current_spell, -- the only id IsCurrentSpell answers true for
        auras = {},               -- [{ name, id }] returned by UnitAura
        -- call counters
        get_family_spell_id_calls = 0,
        get_spell_info_calls = 0,
        cost_queries = 0,
        is_current_spell_calls = 0,
        bar_color_calls = 0,
        set_vertex_calls = 0,
        aura_scans = 0,
        -- last observed values
        last_cost_id = nil,
        last_aura_filter = nil,
        last_hand = nil,
        vertex = nil,
        glow = { starts = 0, stops = 0 },
        hooks = { glow_start = 0, glow_stop = 0 },
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
    env.GetTime = function() return sb.clock end
    env.GetSpellInfo = function(id)
        sb.get_spell_info_calls = sb.get_spell_info_calls + 1
        if sb.known[id] then
            return "Spell " .. tostring(id), nil, 1, 0, 0, 0, id
        end
        return nil
    end
    env.GetSpellPowerCost = function(id)
        sb.cost_queries = sb.cost_queries + 1
        sb.last_cost_id = id
        return sb.rage_cost
    end
    if not opts.no_unit_power then
        env.UnitPower = function() return sb.power end
    end
    env.IsCurrentSpell = function(id)
        sb.is_current_spell_calls = sb.is_current_spell_calls + 1
        return id == sb.current_spell
    end
    env.UnitAura = function(unit, index, filter)
        sb.last_aura_filter = filter
        sb.aura_scans = sb.aura_scans + 1
        local entry = sb.auras[index]
        if not entry then return nil end
        return entry.name, nil, entry.count, nil, nil, nil, nil, nil, nil, entry.id
    end

    -- compat.lua reads some legacy globals through _G (annotation-safe on Mainline-code
    -- clients); mirror the stubs for the duration of its load, then restore _G exactly.
    local mirrored = {}
    for _, name in ipairs({ "GetSpellPowerCost", "IsCurrentSpell", "UnitPower" }) do
        if env[name] ~= nil then
            mirrored[name] = rawget(_G, name)
            _G[name] = env[name]
        end
    end

    local st = {}
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)

    for name, previous in pairs(mirrored) do
        _G[name] = previous
    end

    -- The addon object: only the surface classes/warrior.lua touches.
    local ST = { WARRIOR = {} }
    -- The real WARRIOR defaults (config_presets.lua), so a wrong colour is a module bug
    -- and not a fixture bug.
    local class_db = {
        enable_hs_color = true,
        hs_color = { 130, 7, 9, 1.0 },
        enable_cleave_color = true,
        cleave_color = { 64, 130, 7, 1.0 },
        insufficient_rage_color = { 140, 140, 140, 1.0 },
        use_bloodsurge_glow = true,
        bloodsurge_glow_color = { 227, 57, 74, 1.0 },
        bloodsurge_glow_nlines = 12,
        bloodsurge_glow_freq = 0.1,
        bloodsurge_glow_line_length = 12,
        mainhand = { border_width = 2 },
    }
    local visuals = {
        bar = {
            SetVertexColor = function(_, r, g, b, a)
                sb.set_vertex_calls = sb.set_vertex_calls + 1
                sb.vertex = { r, g, b, a }
            end,
        },
    }
    local bar_frame = { name = "fake_bar_frame" }
    ST.interfaces_are_initialised = false
    ST.get_class_table = function() return class_db end
    ST.get_hand_table = function() return class_db.mainhand end
    ST.get_visuals_frame = function()
        if opts.no_visuals then return nil end
        return visuals
    end
    ST.get_bar_frame = function() return bar_frame end
    -- main.lua declares this as a method (ST:convert_color), so the leading self must be
    -- swallowed here too.
    ST.convert_color = function(_, t, new_alpha)
        local r, g, b, a = unpack(t)
        a = new_alpha or a
        return r / 255, g / 255, b / 255, a
    end
    -- bars.lua dispatches the class hook as ST[player_class].set_bar_color(ST, hand);
    -- mirror that, recording every dispatch so "recolours only on a state change" is
    -- observable.
    ST.set_bar_color = function(self, hand)
        sb.bar_color_calls = sb.bar_color_calls + 1
        sb.last_hand = hand
        return ST.WARRIOR.set_bar_color(self, hand)
    end

    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        end
        if major == "LibCustomGlow-1.0" then
            return {
                PixelGlow_Start = function(frame, color, nlines, freq, length, thickness)
                    sb.glow.starts = sb.glow.starts + 1
                    sb.glow.last_start = {
                        frame = frame, color = color, nlines = nlines,
                        freq = freq, length = length, thickness = thickness,
                    }
                end,
                PixelGlow_Stop = function(frame)
                    sb.glow.stops = sb.glow.stops + 1
                    sb.glow.last_stop_frame = frame
                end,
            }
        end
        return {}
    end

    local utils = assert(loadfile(ROOT .. "utils.lua"))
    setfenv(utils, env)
    utils("SwedgeTimer", st)

    -- Count resolver calls: the module calls api.get_family_spell_id through the api table,
    -- so wrapping the table entry after load is enough.
    local real_resolver = st.api.get_family_spell_id
    st.api.get_family_spell_id = function(ids)
        sb.get_family_spell_id_calls = sb.get_family_spell_id_calls + 1
        return real_resolver(ids)
    end

    local mod = assert(loadfile(ROOT .. "classes/warrior.lua"))
    setfenv(mod, env)
    mod("SwedgeTimer", st)

    -- Hook spies: process_bloodsurge resolves glow_start / glow_stop through self.WARRIOR
    -- at call time, so the wrappers are what the guard is measured against.
    local real_glow_start = ST.WARRIOR.glow_start
    ST.WARRIOR.glow_start = function(self, ...)
        sb.hooks.glow_start = sb.hooks.glow_start + 1
        return real_glow_start(self, ...)
    end
    local real_glow_stop = ST.WARRIOR.glow_stop
    ST.WARRIOR.glow_stop = function(self, ...)
        sb.hooks.glow_stop = sb.hooks.glow_stop + 1
        return real_glow_stop(self, ...)
    end

    sb.st = st
    sb.ST = ST
    sb.class_db = class_db
    sb.bar_frame = bar_frame
    return sb
end

--=========================================================================================
-- 0) The module loads and exposes every hook
--=========================================================================================
local base = build()
check(type(base.ST.WARRIOR) == "table", "classes/warrior.lua loads and defines ST.WARRIOR")
for _, hook in ipairs({
    "on_rage_update", "on_spellcast_failed_quiet", "on_spellcast_succeeded",
    "on_current_spell_cast_changed", "on_aura_change", "process_bloodsurge",
    "glow_start", "glow_stop", "on_combat_exit", "set_bar_color",
}) do
    check(type(base.ST.WARRIOR[hook]) == "function", "WARRIOR." .. hook .. " is defined")
end

--=========================================================================================
-- 1) Pre-init safety: every hook runs with no init and no visuals frame
--=========================================================================================
-- 1a) The real pre-init state: nothing queued yet, so no hook may reach for the bar
--     texture that does not exist yet.
do
    local sb = build({ no_visuals = true })
    local ST = sb.ST
    ST.interfaces_are_initialised = false
    eq(ST.hs_queued, nil, "the pre-init sandbox starts with no queue flags")

    local hooks = {
        -- A real cast guid, never nil: # on a table with an embedded nil is
        -- implementation-defined in Lua 5.1, so the arg lists stay hole-free.
        { "on_spellcast_succeeded", { "target", "cast-1", 47450 } },
        { "on_spellcast_failed_quiet", { "target", "cast-1", 47450 } },
        { "on_current_spell_cast_changed", { false } },
        { "set_bar_color", { "mainhand" } },
        { "on_rage_update", {} },
        { "on_combat_exit", {} },
    }
    for _, entry in ipairs(hooks) do
        for pass = 1, 2 do
            local ok, err = pcall(ST.WARRIOR[entry[1]], ST, unpack(entry[2]))
            check(ok, "pre-init " .. entry[1] .. " (pass " .. pass .. ") does not error ("
                .. tostring(err) .. ")")
        end
    end

    -- Nothing queued means nothing painted: the guards fire before any frame access.
    eq(sb.bar_color_calls, 4, "only the two spellcast clear paths dispatch a recolour (2 hooks x 2 passes)")
    eq(sb.set_vertex_calls, 0, "a pre-init dispatch with nothing queued paints nothing")
    eq(sb.glow.starts, 0, "no glow is started while uninitialised and idle")
end

-- 1b) Dirty flags carried into combat exit, still before init and still no visuals frame.
do
    local sb = build({ no_visuals = true, known = { [47450] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = false
    ST.hs_queued = true
    ST.cleave_queued = true
    ST.insufficient_rage = true
    sb.rage_cost = { { cost = 30 } }
    sb.power = 0

    local ok, err = pcall(ST.WARRIOR.on_combat_exit, ST)
    check(ok, "pre-init combat exit with dirty flags does not error (" .. tostring(err) .. ")")
    eq(ST.hs_queued, false, "pre-init combat exit clears hs_queued")
    eq(ST.cleave_queued, false, "pre-init combat exit clears cleave_queued")
    eq(ST.insufficient_rage, false, "pre-init combat exit clears insufficient_rage")
    eq(sb.bar_color_calls, 0, "pre-init combat exit skips the recolour (no init, no frame)")

    -- An unchanged rage reading must not dispatch a recolour either.
    ST.hs_queued = true
    ST.insufficient_rage = true
    local ok2, err2 = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok2, "an unchanged pre-init rage reading does not error (" .. tostring(err2) .. ")")
    eq(ST.insufficient_rage, true, "0 rage < 30 cost stays insufficient")
    eq(sb.bar_color_calls, 0, "an unchanged reading dispatches no recolour pre-init")
end

--=========================================================================================
-- 2) Rage state: cost vs current power, and the colour reset when it changes
--=========================================================================================
do
    local sb = build({ known = { [47450] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }

    sb.power = 5
    ST.WARRIOR.on_rage_update(ST)
    eq(sb.last_cost_id, 47450, "the queued Heroic Strike rank is the cost that gets queried")
    eq(ST.insufficient_rage, true, "5 rage < 10 cost -> insufficient")
    eq(sb.bar_color_calls, 1, "going insufficient recolours the bar")
    eq(sb.last_hand, "mainhand", "the recolour targets the mainhand bar")

    sb.power = 20
    ST.WARRIOR.on_rage_update(ST)
    eq(ST.insufficient_rage, false, "20 rage >= 10 cost -> sufficient")
    eq(sb.bar_color_calls, 2, "going sufficient recolours the bar back (colour-reset path)")

    -- Third tick with no state change: UNIT_POWER_FREQUENT fires several times a second.
    ST.WARRIOR.on_rage_update(ST)
    eq(ST.insufficient_rage, false, "an unchanged reading keeps the flag false")
    eq(sb.bar_color_calls, 2, "an unchanged reading does not recolour again")

    -- Nothing queued: a stale insufficient colour must be dropped.
    ST.hs_queued = false
    ST.insufficient_rage = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_rage_update(ST)
    eq(ST.insufficient_rage, false, "no queued ability clears a stale insufficient flag")
    eq(sb.bar_color_calls, 1, "clearing the stale flag recolours once")

    sb.power = 0
    sb.bar_color_calls = 0
    ST.WARRIOR.on_rage_update(ST)
    eq(sb.bar_color_calls, 0, "idle rage ticks stay silent")
end

--=========================================================================================
-- 3) No cost data: unknown rank, or a client that cannot read costs
--=========================================================================================
do
    -- 3a) A client where no Heroic Strike rank resolves: the cost must never be queried
    -- and the state degrades to "sufficient" instead of claiming a shortage.
    local sb = build({ known = {} })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    ST.insufficient_rage = true
    sb.rage_cost = { { cost = 10 } }
    local ok, err = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok, "an unresolvable Heroic Strike rank does not error (" .. tostring(err) .. ")")
    eq(sb.cost_queries, 0, "an unresolvable rank never queries a spell cost")
    eq(ST.insufficient_rage, false, "an unresolvable rank degrades to sufficient")
end

do
    -- 3b) A rank resolves but GetSpellPowerCost returns nil (no cost data).
    local sb = build({ known = { [47450] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    ST.insufficient_rage = true
    sb.rage_cost = nil
    sb.power = 0
    local ok, err = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok, "a nil cost table does not error (" .. tostring(err) .. ")")
    eq(sb.cost_queries, 1, "the cost query still runs when the rank is known")
    eq(ST.insufficient_rage, false, "no cost data never claims insufficient rage")

    -- A cost entry without a numeric cost (secret value on a modern client) degrades too.
    sb.rage_cost = { { cost = "<secret>" } }
    local ok2, err2 = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok2, "a non-numeric cost does not error (" .. tostring(err2) .. ")")
    eq(ST.insufficient_rage, false, "a non-numeric cost degrades to sufficient")
end

--=========================================================================================
-- 4) api.UnitPower absent entirely: the compat fallback keeps the comparison safe
--=========================================================================================
do
    local sb = build({ known = { [47450] = true }, no_unit_power = true })
    local ST = sb.ST
    check(type(sb.st.api.UnitPower) == "function", "compat provides an api.UnitPower fallback")
    check(type(sb.st.api.UnitPowerMax) == "function", "compat provides an api.UnitPowerMax fallback")
    eq(sb.st.api.UnitPower("player"), 0, "the fallback reports 0 rage")

    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }
    local ok, err = pcall(ST.WARRIOR.on_rage_update, ST)
    check(ok, "a missing UnitPower global does not error (" .. tostring(err) .. ")")
    eq(ST.insufficient_rage, true, "0 rage from the fallback is compared against the cost")
end

--=========================================================================================
-- 5) Rank latch: the resolver runs once, and a negative result stays latched
--=========================================================================================
do
    local sb = build({ known = {} })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }

    ST.WARRIOR.on_rage_update(ST)
    eq(sb.get_family_spell_id_calls, 1, "the first rage tick resolves the rank")
    ST.WARRIOR.on_rage_update(ST)
    ST.WARRIOR.on_rage_update(ST)
    eq(sb.get_family_spell_id_calls, 1, "a negative result is latched: no re-walk per tick")
    eq(ST.insufficient_rage, false, "latched false keeps the bar out of the rage colour")
end

do
    local sb = build({ known = { [47450] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }

    ST.WARRIOR.on_rage_update(ST)
    check(sb.get_spell_info_calls > 0, "the first tick walks the rank table once")
    local after_first = sb.get_spell_info_calls
    ST.WARRIOR.on_rage_update(ST)
    eq(sb.get_spell_info_calls, after_first, "a positive rank is cached: no re-scan per tick")
end

--=========================================================================================
-- 6) Spell-table hygiene: Mortal Strike must not sit in the Heroic Strike table
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "classes/warrior.lua", "r"))
    local source = f:read("*a")
    f:close()

    -- Drop comments so a source-level scan does not trip on the module's own prose, which
    -- names the excluded Mortal Strike ids.
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
    check(code ~= "", "the source scan strips comments and keeps code")
    check(not code:find("29707", 1, true), "Mortal Strike 29707 appears nowhere in code")
    check(not code:find("30324", 1, true), "Mortal Strike 30324 appears nowhere in code")

    local block = code:match("local%s+hs_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(block) == "string", "the Heroic Strike id table is found in the source")
    block = block or ""
    local hs = {}
    for n in block:gmatch("%d+") do hs[tonumber(n)] = true end
    eq(hs[47450], true, "the Heroic Strike table keeps the WotLK rank 47450")
    eq(hs[47449], true, "the Heroic Strike table keeps 47449")
    eq(hs[25286], true, "the Heroic Strike table keeps the TBC rank 25286")
    eq(hs[11567], true, "the Heroic Strike table keeps 11567")
    eq(hs[29707], nil, "the Heroic Strike table holds no Mortal Strike rank")
    eq(hs[30324], nil, "the Heroic Strike table holds no Mortal Strike rank")

    -- The Cleave table is scanned for the same hygiene (it is the second lookup the
    -- on-next-attack probe walks).
    local cleave_block = code:match("local%s+cleave_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(cleave_block) == "string", "the Cleave id table is found in the source")
    cleave_block = cleave_block or ""
    local cleave = {}
    for n in cleave_block:gmatch("%d+") do cleave[tonumber(n)] = true end
    eq(cleave[47520], true, "the Cleave table keeps the WotLK rank 47520")
    eq(cleave[845], true, "the Cleave table keeps the vanilla rank 845")
end

--=========================================================================================
-- 7) Cleave gating: the option off must stop the probe and the flag
--=========================================================================================
do
    local sb = build({ known = { [25286] = true }, current_spell = 25231 })
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    -- Option off: Cleave is queued on the client but the flag must never be set, and the
    -- Cleave table must not be probed at all.
    sb.class_db.enable_cleave_color = false
    sb.is_current_spell_calls = 0
    local ok, err = pcall(ST.WARRIOR.on_current_spell_cast_changed, ST, false)
    check(ok, "the Cleave option gate does not error (" .. tostring(err) .. ")")
    eq(ST.cleave_queued, false, "a queued Cleave is ignored while its colour is disabled")
    eq(sb.is_current_spell_calls, 11, "only the 11 Heroic Strike ranks are probed")

    -- Option on: the queued Cleave is picked up.
    sb.class_db.enable_cleave_color = true
    sb.is_current_spell_calls = 0
    ST.WARRIOR.on_current_spell_cast_changed(ST, false)
    eq(ST.cleave_queued, true, "a queued Cleave sets cleave_queued once enabled")
    check(sb.is_current_spell_calls > 11, "the Cleave table is probed only when enabled")
    eq(sb.last_hand, "mainhand", "queuing Cleave recolours the mainhand bar")

    -- Heroic Strike still wins over Cleave and clears the Cleave flag.
    sb.current_spell = 25286
    ST.WARRIOR.on_current_spell_cast_changed(ST, false)
    eq(ST.hs_queued, true, "a queued Heroic Strike sets hs_queued")
    eq(ST.cleave_queued, false, "a queued Heroic Strike clears a stale cleave_queued")

    -- Both colour options off: the hook returns without probing anything.
    sb.class_db.enable_hs_color = false
    sb.class_db.enable_cleave_color = false
    sb.current_spell = 25286
    sb.is_current_spell_calls = 0
    ST.WARRIOR.on_current_spell_cast_changed(ST, false)
    eq(sb.is_current_spell_calls, 0, "both options off means no IsCurrentSpell probe")
    eq(ST.hs_queued, true, "both options off leaves the existing flag untouched")

    -- Heroic Strike option off on its own: the Cleave probe still runs.
    sb.class_db.enable_cleave_color = true
    sb.is_current_spell_calls = 0
    ST.WARRIOR.on_current_spell_cast_changed(ST, false)
    eq(sb.is_current_spell_calls, 8, "a disabled Heroic Strike colour probes only the 8 Cleave ranks")

    -- Queuing up on a spell of another class clears the Heroic Strike flag.
    sb.class_db.enable_hs_color = true
    sb.current_spell = 12345
    ST.WARRIOR.on_current_spell_cast_changed(ST, false)
    eq(ST.hs_queued, false, "an unrelated spell clears a stale hs_queued")
end

--=========================================================================================
-- 8) Blood Surge glow: transitions only, never a repeated start
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.has_bloodsurge = false
    ST.bloodsurge_glow_active = false
    sb.auras = { { name = "Blood Surge", id = 46916, count = 1 } }

    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, true, "the Blood Surge aura is detected")
    eq(sb.last_aura_filter, "HELPFUL", "the aura scan passes the typed HELPFUL filter")
    eq(sb.hooks.glow_start, 1, "a proc starts the glow exactly once")
    eq(sb.glow.starts, 1, "LibCustomGlow got a single PixelGlow_Start")
    eq(ST.bloodsurge_glow_active, true, "the glow is marked active")
    check(type(sb.glow.last_start) == "table", "the glow start reached LibCustomGlow")
    eq(sb.glow.last_start and sb.glow.last_start.frame, sb.bar_frame, "the glow is on the mainhand bar frame")
    eq(sb.glow.last_start and sb.glow.last_start.nlines, 12, "the configured glow line count is used")
    eq(sb.glow.last_start and sb.glow.last_start.freq, 0.1, "the configured glow frequency is used")
    eq(sb.glow.last_start and sb.glow.last_start.length, 12, "the configured glow line length is used")
    eq(sb.glow.last_start and sb.glow.last_start.thickness, 2, "the hand border width drives the glow thickness")
    near(sb.glow.last_start and sb.glow.last_start.color and sb.glow.last_start.color[1],
        227 / 255, "the configured glow colour is converted")

    -- A second aura event with the proc still up must not churn the glow pool.
    ST.WARRIOR.on_aura_change(ST)
    ST.WARRIOR.on_aura_change(ST)
    eq(sb.hooks.glow_start, 1, "a repeated aura event does not restart the glow")
    eq(sb.glow.starts, 1, "LibCustomGlow is not asked to start twice")

    -- Proc gone -> one stop.
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, false, "a missing aura clears has_bloodsurge")
    eq(sb.hooks.glow_stop, 1, "the proc expiring stops the glow once")
    eq(sb.glow.stops, 1, "LibCustomGlow got a single PixelGlow_Stop")

    -- Still no aura -> still no second stop.
    ST.WARRIOR.on_aura_change(ST)
    eq(sb.glow.stops, 1, "a repeated no-aura event does not stop the glow twice")

    -- Option off with the proc up: no glow at all.
    sb.class_db.use_bloodsurge_glow = false
    sb.auras = { { name = "Blood Surge", id = 46916, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, true, "the aura is still tracked while the glow is disabled")
    eq(sb.hooks.glow_start, 1, "use_bloodsurge_glow = false never starts the glow")
    eq(sb.hooks.glow_stop, 1, "use_bloodsurge_glow = false does not stop an already idle glow")

    -- Option switched off while the glow is live -> exactly one stop.
    sb.class_db.use_bloodsurge_glow = true
    ST.WARRIOR.on_aura_change(ST)
    eq(sb.hooks.glow_start, 2, "re-enabling the option starts the glow again")
    sb.class_db.use_bloodsurge_glow = false
    ST.WARRIOR.on_aura_change(ST)
    eq(sb.hooks.glow_stop, 2, "turning the option off mid-proc stops the glow once")
    eq(sb.glow.stops, 2, "LibCustomGlow is not asked to stop twice for one transition")

    -- An unrelated aura leaves the glow alone.
    sb.class_db.use_bloodsurge_glow = true
    sb.auras = { { name = "Rampage", id = 29838, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, false, "an unrelated aura is not a Blood Surge proc")
    eq(sb.hooks.glow_start, 2, "an unrelated aura does not start the glow")
    eq(sb.hooks.glow_stop, 2, "an unrelated aura does not stop the glow")

    -- A fresh proc with the option back on starts it again.
    sb.auras = { { name = "Blood Surge", id = 46916, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(sb.hooks.glow_start, 3, "a fresh proc restarts the glow once")
    eq(sb.glow.starts, 3, "LibCustomGlow saw exactly three starts in total")
end

--=========================================================================================
-- 9) Combat exit wipes every queued state
--=========================================================================================
do
    local sb = build({ known = { [47450] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    ST.cleave_queued = true
    ST.insufficient_rage = true
    -- A settled glow state (as after any bar update earlier in the fight): combat exit
    -- must not touch the LibCustomGlow pool.
    ST.bloodsurge_glow_active = false
    sb.rage_cost = { { cost = 30 } }

    ST.WARRIOR.on_combat_exit(ST)
    eq(ST.hs_queued, false, "combat exit clears hs_queued")
    eq(ST.cleave_queued, false, "combat exit clears cleave_queued")
    eq(ST.insufficient_rage, false, "combat exit clears insufficient_rage")
    eq(sb.bar_color_calls, 1, "combat exit recolours once after init")
    eq(sb.hooks.glow_stop, 0, "combat exit does not churn a glow that was never running")
end

--=========================================================================================
-- 10) The on-next-attack colour matrix
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    -- Offhand is never a class override.
    ST.hs_queued = true
    ST.cleave_queued = true
    ST.insufficient_rage = false
    eq(ST.WARRIOR.set_bar_color(ST, "offhand"), false, "the offhand bar returns false")

    -- Heroic Strike queued and enabled -> the configured HS colour.
    sb.vertex = nil
    eq(ST.WARRIOR.set_bar_color(ST, "mainhand"), true, "a queued Heroic Strike claims the bar colour")
    colour_eq(sb.vertex, sb.class_db.hs_color, "a queued Heroic Strike paints the HS colour")

    -- Cleave queued -> the configured Cleave colour.
    ST.hs_queued = false
    ST.cleave_queued = true
    sb.vertex = nil
    eq(ST.WARRIOR.set_bar_color(ST, "mainhand"), true, "a queued Cleave claims the bar colour")
    colour_eq(sb.vertex, sb.class_db.cleave_color, "a queued Cleave paints the Cleave colour")

    -- Queued but short of rage -> the insufficient-rage colour wins.
    ST.insufficient_rage = true
    sb.vertex = nil
    eq(ST.WARRIOR.set_bar_color(ST, "mainhand"), true, "a queued but unaffordable ability claims the bar colour")
    colour_eq(sb.vertex, sb.class_db.insufficient_rage_color, "short of rage paints the insufficient-rage colour")

    ST.cleave_queued = false
    ST.hs_queued = true
    sb.vertex = nil
    eq(ST.WARRIOR.set_bar_color(ST, "mainhand"), true, "a short-of-rage Heroic Strike also claims the bar colour")
    colour_eq(sb.vertex, sb.class_db.insufficient_rage_color, "a short-of-rage Heroic Strike paints the insufficient-rage colour")

    -- Nothing queued -> hand the bar back to the default behaviour.
    ST.hs_queued = false
    ST.insufficient_rage = false
    sb.vertex = nil
    eq(ST.WARRIOR.set_bar_color(ST, "mainhand"), false, "an idle warrior returns false (default colour)")

    -- Option off -> the queued ability is not a colour override at all.
    ST.hs_queued = true
    sb.class_db.enable_hs_color = false
    sb.vertex = nil
    eq(ST.WARRIOR.set_bar_color(ST, "mainhand"), false, "a disabled Heroic Strike colour returns false")
    sb.class_db.enable_hs_color = true
    sb.class_db.enable_cleave_color = false
    ST.hs_queued = false
    ST.cleave_queued = true
    ST.insufficient_rage = true
    sb.vertex = nil
    eq(ST.WARRIOR.set_bar_color(ST, "mainhand"), true, "a disabled Cleave colour still shows insufficient rage")
end

--=========================================================================================
-- 11) The spellcast hooks clear the queue they own, and nothing else
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    ST.hs_queued = true
    ST.cleave_queued = true
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", nil, 25286)
    eq(ST.hs_queued, false, "a landed Heroic Strike clears hs_queued")
    eq(ST.cleave_queued, true, "a landed Heroic Strike leaves cleave_queued alone")

    ST.cleave_queued = true
    ST.WARRIOR.on_spellcast_failed_quiet(ST, "target", nil, 25231)
    eq(ST.cleave_queued, false, "a failed Cleave clears cleave_queued")

    sb.bar_color_calls = 0
    ST.hs_queued = true
    ST.cleave_queued = true
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", nil, 12345)
    eq(ST.hs_queued, true, "an unrelated spell id leaves hs_queued alone")
    eq(ST.cleave_queued, true, "an unrelated spell id leaves cleave_queued alone")
    eq(sb.bar_color_calls, 0, "an unrelated spell id does not recolour")

    ST.WARRIOR.on_spellcast_failed_quiet(ST, "target", nil, nil)
    eq(ST.hs_queued, true, "a nil spell id is ignored")
    eq(sb.bar_color_calls, 0, "a nil spell id does not recolour")
end

if failures == 0 then
    print("PASS  warrior_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  warrior_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end