-- tests/warrior_state.lua: offline tests for the warrior module (classes/warrior.lua)
-- over the real compat.lua + utils.lua in a sandbox.
-- Pins the pre-init guards, the rage-cost evaluation and its colour reset, the negative
-- rank latch, Heroic Strike / Cleave spell-table hygiene, the Cleave option gate, the
-- Blood Surge glow state-change guard, the on-next-attack colour matrix, and the warrior
-- tracker set: the target debuff bars (id / localized-name / literal-name matching, the
-- caster filter, throttled merged scan, cached restack, glow and stack-count rendering),
-- the Shield Block bar, the Slam cast bar, the Overpower proc window (pure helpers,
-- CLEU arming, clear-on-cast, option gates and absent-data inertness), the Execute-phase
-- practice feed (record/track, the harness registry run/grade, the session arming and
-- the Era/TBC/Forever family matrix), and the designer/options wiring (the five
-- positionable elements and the Practice page entries).
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
        -- The cast time the client's spell data reports (ms); 0 = no cast time, the
        -- reference's 1.5 s default then applies.
        cast_ms = opts.cast_ms or 0,
        -- Every GetSpellInfo query, in order (the name-vs-id direction proof).
        spell_queries = {},
        -- A client that cannot answer at all: the stub raises, so compat's pcall
        -- reports "could not answer" ("unresolved") instead of "not here" ("absent").
        spell_info_throws = false,
        current_spell = opts.current_spell, -- the only id IsCurrentSpell answers true for
        auras = {},               -- [{ name, id }] returned by UnitAura for "player"
        target_auras = {},        -- [{ name, id, count, duration, expiration, source }] for "target"
        cast_live = nil,          -- { name, spell_id, start_ms, end_ms } for UnitCastingInfo
        -- call counters
        get_family_spell_id_calls = 0,
        get_family_spell_id_state_calls = 0,
        get_spell_info_calls = 0,
        cost_queries = 0,
        cost_query_log = {},
        cooldown_queries = 0,
        last_cooldown_query = nil,
        cooldowns = {},
        is_current_spell_calls = 0,
        is_current_query_log = {},
        known_query_log = {},
        bar_color_calls = 0,
        set_vertex_calls = 0,
        aura_scans = 0,
        unit_aura_calls = 0,
        target_aura_calls = 0,
        unit_casting_info_calls = 0,
        unit_channel_info_calls = 0,
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
    -- Name back-map for the synthetic "Spell <id>" names above, plus the
    -- real-name overrides a fixture sets for its own ids (a real client
    -- answers real spell names; the synthetic rule stands in elsewhere).
    local function id_for_name(name)
        if type(name) ~= "string" then
            return nil
        end
        if sb.real_names ~= nil and sb.real_names[name] ~= nil then
            return sb.real_names[name]
        end
        local id = name:match("^Spell (%d+)$")
        id = id and tonumber(id) or nil
        if id ~= nil and sb.known[id] then
            return id
        end
        return nil
    end
    -- The TBC Anniversary client answers by NAME (operator rule 2026-10-19): the id
    -- form finds nothing and the C_Spell namespace carries the id -> name mapping.
    -- opts.name_only_client turns the fixture into that client.
    local name_only_client = opts.name_only_client == true
    env.GetSpellInfo = function(query)
        sb.get_spell_info_calls = sb.get_spell_info_calls + 1
        sb.spell_queries[#sb.spell_queries + 1] = query
        if sb.spell_info_throws then
            error("restricted")
        end
        if sb.real_names ~= nil then
            for real_id, real_name in pairs(sb.real_names) do
                if real_id == query and sb.known[query] then
                    return real_name, nil, 1, sb.cast_ms, 0, 0, query
                end
            end
        end
        if type(query) == "string" then
            -- The client's own name for a known spell answers too: a client that named
            -- a spell answers to that name (the TBC name path).
            local back = id_for_name(query)
            if back ~= nil then
                return query, nil, 1, sb.cast_ms, 0, 0, back
            end
            return nil
        end
        if name_only_client then
            -- The TBC client indexes names only: an id query finds nothing.
            return nil
        end
        if sb.known[query] then
            return "Spell " .. tostring(query), nil, 1, sb.cast_ms, 0, 0, query
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
    env.GetSpellPowerCost = function(id)
        sb.cost_queries = sb.cost_queries + 1
        sb.last_cost_id = id
        sb.cost_query_log[#sb.cost_query_log + 1] = id
        return sb.rage_cost
    end
    -- Cooldown stub (absent before this lane): id-keyed like a client table,
    -- plus the name back-map so TBC name queries read the same fixture.
    -- Unknown reads idle (0, 0, 0, 0), the same shape the missing probe gave.
    env.GetSpellCooldown = function(spell)
        sb.cooldown_queries = sb.cooldown_queries + 1
        sb.last_cooldown_query = spell
        local cds = sb.cooldowns or {}
        local cd = cds[spell]
        if cd == nil and type(spell) == "string" then
            local id = id_for_name(spell)
            if id ~= nil then
                cd = cds[id]
            end
        end
        if cd ~= nil then
            return cd.start or 0, cd.duration or 0, 1, 0
        end
        return 0, 0, 0, 0
    end
    if not opts.no_unit_power then
        env.UnitPower = function() return sb.power end
    end
    env.IsCurrentSpell = function(spell)
        sb.is_current_spell_calls = sb.is_current_spell_calls + 1
        sb.is_current_query_log[#sb.is_current_query_log + 1] = spell
        if spell == sb.current_spell then
            return true
        end
        -- Name-shaped query (the TBC family): match the resolved name of the
        -- queued rank.
        if type(spell) == "string" and type(sb.current_spell) == "number" then
            local name = sb.real_names ~= nil and sb.real_names[sb.current_spell]
                or ("Spell " .. tostring(sb.current_spell))
            return spell == name
        end
        return false
    end
    -- Spell knowledge for the spec/rune/talent probes (Mortal Strike = arms,
    -- Raging Blow / Consumed by Rage = SoD, Bladestorm talented): the same
    -- known set that answers GetSpellInfo above, so the two never disagree.
    -- Mirrored into _G with the other stubs for the duration of the compat
    -- load (compat resolves IsSpellKnown dynamically through _G).
    env.IsSpellKnown = function(spell)
        sb.known_query_log[#sb.known_query_log + 1] = spell
        if sb.known[spell] == true then
            return true
        end
        -- Name-shaped probe (the TBC family): match the book entry filed
        -- under the spell's numeric id.
        local id = id_for_name(spell)
        return id ~= nil and sb.known[id] == true
    end
    env.UnitAura = function(unit, index, filter)
        sb.last_aura_filter = filter
        sb.aura_scans = sb.aura_scans + 1
        local entry
        if unit == "target" then
            sb.target_aura_calls = sb.target_aura_calls + 1
            entry = sb.target_auras[index]
        else
            sb.unit_aura_calls = sb.unit_aura_calls + 1
            entry = sb.auras[index]
        end
        if not entry then return nil end
        return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
            entry.source, nil, nil, entry.id
    end
    -- Classic payloads: UnitCastingInfo -> name, text, texture, startTimeMs, endTimeMs,
    -- isTradeSkill, castID, notInterruptible, spellID; UnitChannelInfo lacks castID.
    env.UnitCastingInfo = function(unit)
        sb.unit_casting_info_calls = sb.unit_casting_info_calls + 1
        if unit ~= "player" or not sb.cast_live then return nil end
        return sb.cast_live.name, nil, nil, sb.cast_live.start_ms, sb.cast_live.end_ms,
            false, 1, false, sb.cast_live.spell_id
    end
    env.UnitChannelInfo = function(unit)
        sb.unit_channel_info_calls = sb.unit_channel_info_calls + 1
        if unit ~= "player" then return nil end
        return nil
    end
    -- Stance fixture for the follow-up stance input: opts.shapeshift_form feeds
    -- compat's api.GetShapeshiftForm probe; absent keeps compat's no-probe
    -- fallback (0), which the gather maps to nil (unknown hides).
    sb.shapeshift_form = opts.shapeshift_form
    env.GetShapeshiftForm = function()
        if sb.shapeshift_form ~= nil then
            return sb.shapeshift_form
        end
        return nil
    end

    -- Opt-in health fixture (before the compat load, so compat's secret-guard
    -- wrapping observes the stubs per unit): read through sb fields, so tests
    -- can move the values mid-section. Any unit without a value reads nil (the
    -- compat fallback shape), which every consumer must treat as unknown.
    local health_opts = opts.health or {}
    sb.health_player_cur = health_opts.player and health_opts.player.cur
    sb.health_player_max = health_opts.player and health_opts.player.max
    sb.health_target_cur = health_opts.target and health_opts.target.cur
    sb.health_target_max = health_opts.target and health_opts.target.max
    sb.unit_health_calls = 0
    env.UnitHealth = function(unit)
        sb.unit_health_calls = sb.unit_health_calls + 1
        if unit == "player" then
            return sb.health_player_cur
        end
        return sb.health_target_cur
    end
    env.UnitHealthMax = function(unit)
        sb.unit_health_calls = sb.unit_health_calls + 1
        if unit == "player" then
            return sb.health_player_max
        end
        return sb.health_target_max
    end
    -- Opt-in usability probe (hud_no_mana and the W7 fallback read it through
    -- compat's (usable, insufficient) wrapper); left absent keeps compat's
    -- no-probe fallback, whose unknown reading renders as "no glow"/"no tint".
    env.IsSpellUsable = opts.usable

    -- compat.lua reads several legacy globals through _G (annotation-safe on
    -- Mainline-code clients); mirror EVERY sandbox stub for the duration of its load,
    -- then restore _G exactly. A hardcoded name list goes stale the moment compat adds
    -- another _G read - that is exactly how GetSpellInfo broke these suites.
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
        -- The real WARRIOR tracker defaults (config_presets.lua), so a wrong colour or a
        -- missing option key is a module bug and not a fixture bug.
        show_warrior_deep_wounds_bar = true,
        warrior_deep_wounds_bar_color = { 179, 38, 38, 0.90 },
        show_warrior_sunder_armor_bar = true,
        warrior_sunder_armor_bar_color = { 140, 89, 38, 0.90 },
        show_warrior_rend_bar = true,
        warrior_rend_bar_color = { 217, 38, 26, 0.90 },
        show_warrior_thunder_clap_bar = true,
        warrior_thunder_clap_bar_color = { 89, 140, 191, 0.90 },
        show_warrior_demo_shout_bar = true,
        warrior_demo_shout_bar_color = { 166, 128, 77, 0.90 },
        show_warrior_shield_block_bar = true,
        warrior_shield_block_bar_color = { 51, 140, 255, 0.90 },
        show_warrior_slam_cast_bar = true,
        show_warrior_overpower_flash = true,
        mainhand = { border_width = 2 },
    }
    -- Texture/fontstring stubs recording what the tracker widgets draw, so positions,
    -- sizes, colours, textures and visibility can be asserted without a real frame. The
    -- point/text-set counters make the cached-restack and label-write guards observable.
    local function make_texture()
        local t = { hidden = true, point_sets = 0 }
        function t:SetDrawLayer() end
        function t:SetColorTexture(r, g, b, a) t.base_color = { r, g, b, a } end
        function t:SetWidth(w) t.width = w end
        function t:SetHeight(h) t.height = h end
        function t:SetSize(w, h) t.width, t.height = w, h end
        function t:SetPoint(point, anchor, rel_point, x, y)
            t.point_sets = t.point_sets + 1
            t.point, t.anchor, t.rel_point, t.offset, t.offset_y = point, anchor, rel_point, x, y
        end
        function t:ClearAllPoints()
            t.point, t.anchor, t.rel_point, t.offset, t.offset_y = nil, nil, nil, nil, nil
        end
        function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
        function t:SetTexture(texture) t.texture = texture end
        function t:SetTexCoord(...) t.texcoord = { ... } end
        function t:Hide() t.hidden = true end
        function t:Show() t.hidden = false end
        function t:IsShown() return not t.hidden end
        return t
    end
    local function make_fontstring()
        local f = { hidden = true, text_sets = 0 }
        function f:SetPoint(...) f.point = { ... } end
        function f:SetJustifyH() end
        function f:SetFont(font_path, size, flags) f.font = { font_path, size, flags } end
        function f:SetText(text)
            f.text_sets = f.text_sets + 1
            f.text = text
        end
        function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
        function f:Hide() f.hidden = true end
        function f:Show() f.hidden = false end
        function f:IsShown() return not f.hidden end
        return f
    end
    local visuals = {
        bar = {
            SetVertexColor = function(_, r, g, b, a)
                sb.set_vertex_calls = sb.set_vertex_calls + 1
                sb.vertex = { r, g, b, a }
            end,
        },
        CreateTexture = function() return make_texture() end,
        CreateFontString = function() return make_fontstring() end,
    }
    local bar_frame = { name = "fake_bar_frame" }
    ST.interfaces_are_initialised = false
    ST.player_guid = "Player-1"
    ST.get_class_table = function() return class_db end
    ST.get_hand_table = function() return class_db.mainhand end
    ST.get_visuals_frame = function()
        if opts.no_visuals then return nil end
        return visuals
    end
    -- bars.lua's accessor, mirrored: the tracker widgets size against the live bar.
    ST.get_bar_visuals_width_and_height = function() return 100, 20 end
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

    -- The pure guide engine (the Slam safe-window verdict lives there; the
    -- widget calls it through a nil-guard so a flavor without this module
    -- keeps the white fill).
    local guide = assert(loadfile(ROOT .. "warrior_guide.lua"))
    setfenv(guide, env)
    guide("SwedgeTimer", st)

    -- Count resolver calls: the module calls api.get_family_spell_id_state through
    -- the api table, so wrapping the table entry after load is enough. The plain
    -- resolver is counted too: the class must not use it any more (audit F4).
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

    local mod = assert(loadfile(ROOT .. "classes/warrior.lua"))
    setfenv(mod, env)
    mod("SwedgeTimer", st)
    -- classes/warrior.lua registers its body as a loader (operator order 2026-10-21:
    -- only the selected class executes). Activate it here, right after its file
    -- loads - the same load-time position its body occupied before the wrapper.
    assert(type(st.class_loaders) == "table"
        and type(st.class_loaders["WARRIOR"]) == "function",
        "classes/warrior.lua registers the WARRIOR loader")
    st.class_loaders["WARRIOR"]()

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
    sb.visuals = visuals
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
    "on_bar_update", "on_spellcast_event", "on_combat_log_unfiltered",
    "setup_warrior_visuals", "get_debuff_remaining", "should_debuff_glow",
    "get_overpower_remaining", "get_rampage_display", "is_overpower_cast",
    "get_rampage_tier", "get_bank_state", "get_battle_shout_display",
    "composite_rage_gate", "gate_composite_action",
    "record_execute_sample", "track_execute_phase", "get_rotation_key",
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
    eq(sb.get_family_spell_id_state_calls, 1, "the first rage tick resolves the rank")
    eq(sb.get_family_spell_id_calls, 0, "the class resolves through the state API, not the plain one")
    ST.WARRIOR.on_rage_update(ST)
    ST.WARRIOR.on_rage_update(ST)
    eq(sb.get_family_spell_id_state_calls, 1, "a negative result is latched: no re-walk per tick")
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
    -- 29707 / 30324 are TBC Heroic Strike ranks 9-10, not Mortal Strike
    -- (wowsims/tbc-new fury + arms APLs cast 29707 tag1;
    -- wowhead.com/tbc/spell=30324 is Heroic Strike): the table must carry
    -- them, and no Mortal Strike id may hide in the table.
    check(code:find("29707", 1, true) ~= nil, "Heroic Strike 29707 is named in code")
    check(code:find("30324", 1, true) ~= nil, "Heroic Strike 30324 is named in code")

    local block = code:match("local%s+hs_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(block) == "string", "the Heroic Strike id table is found in the source")
    block = block or ""
    local hs = {}
    for n in block:gmatch("%d+") do hs[tonumber(n)] = true end
    eq(hs[47450], true, "the Heroic Strike table keeps the WotLK rank 47450")
    eq(hs[47449], true, "the Heroic Strike table keeps 47449")
    eq(hs[25286], true, "the Heroic Strike table keeps the TBC rank 25286")
    eq(hs[29707], true, "the Heroic Strike table keeps the TBC rank 29707")
    eq(hs[30324], true, "the Heroic Strike table keeps the TBC rank 30324")
    eq(hs[11567], true, "the Heroic Strike table keeps 11567")
    eq(hs[30330], nil, "the Heroic Strike table holds no Mortal Strike rank (30330)")
    eq(hs[12294], nil, "the Heroic Strike table holds no Mortal Strike rank (12294)")

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
-- 6b) Whirlwind / Rend table hygiene + the Hamstring weave probe
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "classes/warrior.lua", "r"))
    local source = f:read("*a")
    f:close()

    -- The Whirlwind table carries exactly the sim-cited base id: 11584/11585
    -- are Overpower (wowhead classic + the wowsims sims/APL casts), 25208 is
    -- Rend (wowhead tbc), 47436 is Battle Shout (wowhead wotlk), 6794 is
    -- Tiger's Fury, 6795 is Growl (wowhead classic), 47435 is a creature
    -- spell. Anchored on the constructor so the module's own eviction prose
    -- cannot trip the scan.
    local block = source:match("local%s+ww_ids%s*=%s*get_tab%s*%((.-)%)")
    check(type(block) == "string", "the Whirlwind id table is found in the source")
    block = block or ""
    local ww, n = {}, 0
    for id in block:gmatch("%d+") do ww[tonumber(id)] = true; n = n + 1 end
    eq(n, 1, "the Whirlwind table carries exactly one id")
    eq(ww[1680], true, "Whirlwind resolves through the sim-cited base id 1680")

    -- TBC Rend rank 8 belongs to the Rend table (it sat in ww_ids by mistake).
    local rend_block = source:match("local%s+rend_ids%s*=%s*get_tab%s*%((.-)%)") or ""
    check(rend_block:find("25208", 1, true) ~= nil, "TBC Rend 25208 lives in rend_ids")
end

do
    -- Hamstring weave probe: post_init-frozen knowledge, nil-safe on both
    -- sides. The base set carries the slot (sixth); no guide rule consumes
    -- the flag yet (the prompt + options wiring follow-up is filed in the
    -- desk journal). A cast matcher is deliberately NOT carried: no in-tree
    -- reader exists for one, and wire-not-strip removes reader-less hooks.
    local sb_known = build({ known = { [18499] = true } })
    sb_known.ST.interfaces_are_initialised = true
    sb_known.ST.WARRIOR.post_init(sb_known.ST)
    eq(sb_known.ST.warrior_has_hamstring, true, "a known Hamstring rank freezes the weave flag")
    local sb_unknown = build({ known = {} })
    sb_unknown.ST.interfaces_are_initialised = true
    sb_unknown.ST.WARRIOR.post_init(sb_unknown.ST)
    eq(sb_unknown.ST.warrior_has_hamstring, false, "an unknown Hamstring freezes the flag off")
    -- The base set names the slot sixth (known and unknown alike: the
    -- descriptor is frozen, the flag only gates the future prompt). Base
    -- runs on the Retail profile here (project 1); the Wrath default above
    -- keeps its fury set, so the slot pins need the base family.
    local sb_base_known = build({ project = 1, known = { [18499] = true } })
    sb_base_known.ST.interfaces_are_initialised = true
    sb_base_known.ST.WARRIOR.post_init(sb_base_known.ST)
    eq(sb_base_known.ST.WARRIOR.guide.slots[6].key, "hamstring",
        "a Hamstring-knowing base client declares the filler slot sixth")
    eq(sb_base_known.ST.WARRIOR.guide.slots[6].cooldown_key, "hamstring",
        "the Hamstring slot carries its cooldown_key")
    eq(sb_base_known.ST.WARRIOR.guide.slots[6].spell_id, 18499,
        "a known TBC Hamstring rank re-points the slot icon")
    local sb_base_unknown = build({ project = 1, known = {} })
    sb_base_unknown.ST.interfaces_are_initialised = true
    sb_base_unknown.ST.WARRIOR.post_init(sb_base_unknown.ST)
    eq(sb_base_unknown.ST.WARRIOR.guide.slots[6].key, "hamstring",
        "an unknowing base client still declares the filler slot (hidden until learned)")
    eq(sb_base_unknown.ST.WARRIOR.guide.slots[6].spell_id, 7373,
        "an unknown Hamstring keeps the rank-1 fallback")
    local sb_hud = sb_base_unknown.ST.WARRIOR.HUD_SLOTS
    eq(#sb_hud, 8, "base HUD declares six abilities plus the two trinkets")
    eq(sb_hud[6].key, "hamstring", "base HUD carries the Hamstring slot sixth")
    eq(sb_hud[6].spell, 7373, "base HUD Hamstring keeps the rank-1 fallback")
    eq(sb_hud[7].key, "trinket1", "base HUD keeps the trinkets last")
    -- Gather: known feeds true, unknown feeds nil (never false), and the
    -- swipe pair always resolves (ready when unlearned, never an error).
    local g_known = sb_base_known.ST.WARRIOR.gather_guide_inputs(sb_base_known.ST, {})
    eq(g_known.hamstring_known, true, "gather: a known Hamstring feeds the weave flag")
    eq(g_known.hamstring_remaining, 0, "gather: the known Hamstring reads ready")
    eq(g_known.hamstring_duration, nil, "gather: the known Hamstring latches no duration")
    local g_unknown = sb_base_unknown.ST.WARRIOR.gather_guide_inputs(sb_base_unknown.ST, {})
    eq(g_unknown.hamstring_known, nil, "gather: an unknown Hamstring feeds nil (never false)")
    eq(g_unknown.hamstring_remaining, 0, "gather: the unlearned Hamstring reads ready")
    eq(g_unknown.hamstring_duration, nil, "gather: the unlearned Hamstring latches no duration")
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
    eq(sb.is_current_spell_calls, 13, "only the 13 Heroic Strike ranks are probed")

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
-- 8b) SoD Blood Surge rune aura (413399) arms the same proc
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    -- The WotLK talent proc still arms (section 8 covers the glow transitions).
    sb.auras = { { name = "Blood Surge", id = 46916, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, true, "the WotLK Blood Surge aura arms the proc")
    -- The SoD rune aura arms the identical flag (both SoD APLs gate Slam
    -- 11605 on auraIsActive 413399).
    sb.auras = { { name = "Blood Surge", id = 413399, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, true, "the SoD Blood Surge rune aura arms the proc")
    -- Gone clears, and an unrelated aura never arms.
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, false, "a missing aura clears has_bloodsurge")
    sb.auras = { { name = "Blood Surge", id = 12345, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, false, "an unrelated aura id is not a Blood Surge proc")
end

--=========================================================================================
-- 8c) Secret-hole: a proc above a nil row is still detected (H1)
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    -- A nil row (a restricted entry degrades to absent) no longer ends the walk:
    -- the proc above the hole is still found.
    sb.auras = { [2] = { name = "Blood Surge", id = 46916, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, true, "H1: a proc above a nil row is still detected")
    -- The walk stays bounded at the 40-row cap.
    eq(sb.aura_scans, 40, "H1: the scan walks the full 40-row cap")
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

    -- Option off + affordable: a stale Cleave flag never tints (the enable
    -- gate sits before the queued check, the same shape as the HS branch, so
    -- a disabled colour with enough rage hands the bar back to default).
    ST.insufficient_rage = false
    sb.vertex = nil
    eq(ST.WARRIOR.set_bar_color(ST, "mainhand"), false, "a disabled Cleave colour with enough rage returns false")
    eq(sb.vertex, nil, "a disabled Cleave colour paints nothing while affordable")
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

--=========================================================================================
-- 12) Pre-init safety for the tracker hooks
--=========================================================================================
do
    local sb = build({ no_visuals = true })
    local ST = sb.ST
    ST.interfaces_are_initialised = false
    eq(ST.warrior_overpower_proc_until, nil, "the pre-init sandbox starts with no proc window")

    local hooks = {
        { "on_bar_update", { "mainhand" } },
        { "on_spellcast_event", { "UNIT_SPELLCAST_START", "player", "cast-1", 47475 } },
        { "on_combat_log_unfiltered", { "COMBAT_LOG_EVENT_UNFILTERED", 100, "SWING_MISSED",
            false, "Player-1", "Player", 0, 0, "Target-1", "Target", 0, 0, "DODGE" } },
        { "setup_warrior_visuals", {} },
    }
    for _, entry in ipairs(hooks) do
        for pass = 1, 2 do
            local ok, err = pcall(ST.WARRIOR[entry[1]], ST, unpack(entry[2]))
            check(ok, "pre-init " .. entry[1] .. " (pass " .. pass .. ") does not error ("
                .. tostring(err) .. ")")
        end
    end
    eq(ST.warrior_overpower_proc_until, nil, "a pre-init CLEU dodge does not arm the proc window")
    check(not ST.warrior_slam_casting, "a pre-init START does not begin a Slam cast")
    eq(sb.unit_casting_info_calls, 0, "pre-init spellcast events perform no cast reads")
end

--=========================================================================================
-- 13) Tracker options all off: no reads at all and every widget hidden
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local vf = sb.visuals
    local db = sb.class_db
    db.show_warrior_deep_wounds_bar = false
    db.show_warrior_sunder_armor_bar = false
    db.show_warrior_rend_bar = false
    db.show_warrior_thunder_clap_bar = false
    db.show_warrior_demo_shout_bar = false
    db.show_warrior_shield_block_bar = false
    db.show_warrior_slam_cast_bar = false
    db.show_warrior_overpower_flash = false
    check(vf.warrior_shield_block ~= nil, "post_init creates the Shield Block widgets")
    check(vf.warrior_slam ~= nil, "post_init creates the Slam widgets")
    check(vf.warrior_debuff ~= nil, "post_init creates the five debuff widget groups")
    check(vf.warrior_overpower_edges ~= nil and #vf.warrior_overpower_edges == 4,
        "post_init creates the four Overpower flash edges")

    sb.clock = 100
    sb.target_auras = {
        { name = "Rend", id = 772, source = "player", duration = 9, expiration = 109 },
    }
    sb.auras = {
        { name = "Shield Block", id = 2565, duration = 5, expiration = 105 },
    }
    sb.target_aura_calls = 0
    sb.unit_aura_calls = 0
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(sb.target_aura_calls, 0, "all off: no target aura reads")
    eq(sb.unit_aura_calls, 0, "all off: no player aura reads")
    check(vf.warrior_shield_block.bg.hidden, "all off: the Shield Block bar hides")
    check(vf.warrior_slam.bg.hidden, "all off: the Slam bar hides")
    check(vf.warrior_overpower_text.hidden, "all off: the Overpower flash stays hidden")
    for key in pairs(vf.warrior_debuff) do
        local bar = vf.warrior_debuff[key]
        check(bar.bg.hidden and bar.fill.hidden and bar.glow.hidden and bar.label.hidden,
            "all off: the " .. key .. " debuff bar is hidden")
    end
end

--=========================================================================================
-- 14) Target debuff bars: id / localized-name / literal-name matching, the caster filter,
-- expiry and the glow boundary
--=========================================================================================
do
    local sb = build({ known = { [772] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local bars = sb.visuals.warrior_debuff

    -- Id match at a clean remaining fraction.
    sb.clock = 200
    sb.target_auras = {
        { name = "localized rend", id = 772, source = "player", duration = 9, expiration = 206 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bars.rend.bg.hidden, "the player's Rend shows its bar")
    near(bars.rend.fill.width, 100 * (6 / 9), "the fill shows the remaining fraction")
    eq(bars.rend.label.text, "6", "the label shows whole seconds")
    check(bars.rend.glow.hidden, "no glow above the final 4 s")

    -- The localized name resolved from the client's own spell data matches without an id.
    sb.clock = 201
    sb.target_auras = {
        { name = "Spell 772", source = "player", duration = 9, expiration = 207 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bars.rend.bg.hidden, "the resolved localized name matches without an id")

    -- The literal English fallback matches even with no spell data resolved yet.
    sb.clock = 202
    sb.target_auras = {
        { name = "Deep Wound", source = "player", duration = 12, expiration = 208 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bars.deep_wounds.bg.hidden, "the literal English name matches as the fallback")
    eq(bars.deep_wounds.label.text, "6", "Deep Wounds' label counts its own duration")

    -- A foreign caster's debuff does not qualify.
    sb.clock = 203
    sb.target_auras = {
        { name = "Rend", id = 772, source = "other", duration = 9, expiration = 215 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bars.rend.bg.hidden, "another caster's debuff does not show the bar")

    -- Aura gone: every bar hides.
    sb.clock = 204
    sb.target_auras = {}
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bars.rend.bg.hidden and bars.deep_wounds.bg.hidden and bars.sunder_armor.bg.hidden
        and bars.thunder_clap.bg.hidden and bars.demo_shout.bg.hidden,
        "no matching auras: all debuff bars hide")

    -- Still-listed but expired: remaining floors at 0 and the glow never shows there.
    sb.clock = 205
    sb.target_auras = {
        { name = "Rend", id = 772, source = "player", duration = 9, expiration = 204 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bars.rend.bg.hidden, "an expired-but-listed aura still draws (the reference floors at 0)")
    eq(bars.rend.label.text, "0", "the expired bar reads 0")
    check(bars.rend.glow.hidden, "an expired bar does not glow")

    -- Glow boundary: on at exactly 4 s remaining, off just above.
    sb.clock = 206
    sb.target_auras = {
        { name = "Rend", id = 772, source = "player", duration = 9, expiration = 210 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bars.rend.glow.hidden, "the glow starts at exactly 4 s remaining")
    sb.clock = 206.1
    sb.target_auras[1].expiration = 210.4
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bars.rend.glow.hidden, "the glow stays off above 4 s")
end

--=========================================================================================
-- 15) Sunder Armor stacks, the shared stack walk, throttling and the cached restack
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local bars = sb.visuals.warrior_debuff

    sb.clock = 300
    sb.target_auras = {
        { name = "Deep Wound", source = "player", duration = 12, expiration = 312 },
        { name = "Sunder Armor", source = "player", duration = 30, expiration = 330, count = 3 },
        { name = "Rend", source = "player", duration = 9, expiration = 309 },
    }
    sb.target_aura_calls = 0
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not (bars.deep_wounds.bg.hidden or bars.sunder_armor.bg.hidden or bars.rend.bg.hidden),
        "the visible debuffs draw through one merged scan")
    eq(bars.deep_wounds.bg.offset_y, 2, "Deep Wounds occupies the bottom slot")
    eq(bars.sunder_armor.bg.offset_y, 10, "Sunder Armor stacks above Deep Wounds (6 px + 2 px gap)")
    eq(bars.rend.bg.offset_y, 18, "Rend stacks above Sunder Armor")
    eq(bars.sunder_armor.label.text, "3", "Sunder Armor's label shows its stack count")

    -- The merged scan is throttled to 0.05 s.
    local calls_before = sb.target_aura_calls
    sb.clock = 300.01
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(sb.target_aura_calls, calls_before, "the target scan is throttled to 0.05 s")

    -- Cached restack: an unchanged slot performs no anchor writes at all.
    local sets_before = bars.rend.bg.point_sets
    sb.clock = 300.1
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(bars.rend.bg.point_sets, sets_before, "an unchanged slot performs no anchor writes")

    -- Just one debuff up: it slides down to the bottom slot.
    sb.clock = 301
    sb.target_auras = {
        { name = "Rend", source = "player", duration = 9, expiration = 310 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(bars.rend.bg.offset_y, 2, "an alone Rend takes the bottom slot")

    -- A missing stack count still reads as one.
    sb.clock = 302
    sb.target_auras = {
        { name = "Sunder Armor", source = "player", duration = 30, expiration = 332 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(bars.sunder_armor.label.text, "1", "a missing stack count reads as one stack")

    -- One bar off: only that bar hides; the shared scan keeps feeding the others.
    sb.class_db.show_warrior_sunder_armor_bar = false
    sb.clock = 303
    sb.target_auras = {
        { name = "Deep Wound", source = "player", duration = 12, expiration = 315 },
        { name = "Sunder Armor", source = "player", duration = 30, expiration = 333, count = 2 },
    }
    calls_before = sb.target_aura_calls
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bars.sunder_armor.bg.hidden, "a disabled bar hides even while the debuff is up")
    check(not bars.deep_wounds.bg.hidden, "its enabled neighbour keeps drawing")
    check(sb.target_aura_calls > calls_before, "the shared scan still runs for the enabled bar")
    sb.class_db.show_warrior_sunder_armor_bar = true

    -- Colours: the configured table wins; the reference fallback covers a missing key.
    sb.clock = 304
    sb.target_auras = {
        { name = "Thunder Clap", source = "player", duration = 30, expiration = 334 },
    }
    sb.class_db.warrior_thunder_clap_bar_color = { 10, 20, 30, 0.4 }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    colour_eq(bars.thunder_clap.fill.color, { 10, 20, 30, 0.4 },
        "the configured Thunder Clap colour fills the bar")
    colour_eq(bars.thunder_clap.glow.color, { 10, 20, 30, 0.4 }, "the glow shares the fill colour")
    sb.class_db.warrior_thunder_clap_bar_color = nil
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    colour_eq(bars.thunder_clap.fill.color, { 89, 140, 191, 0.90 },
        "the reference fallback covers a missing db colour")
end

--=========================================================================================
-- 16) Shield Block bar: show/hide, icon, colour, option gate and the shared stack
--=========================================================================================
do
    local sb = build({ known = { [2565] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local bar = sb.visuals.warrior_shield_block

    sb.clock = 400
    sb.auras = {
        { name = "Battle Shout", id = 6673, duration = 120, expiration = 520 },
        { name = "Shield Block", id = 2565, duration = 5, expiration = 403 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bar.bg.hidden, "the Shield Block buff shows its bar")
    near(bar.fill.width, 100 * (3 / 5), "the fill shows the remaining fraction")
    eq(bar.bg.offset_y, 2, "Shield Block occupies the bottom slot")
    check(not bar.icon.hidden and bar.icon.texture ~= nil,
        "the spell icon shows once the client's spell data answered")

    -- The resolved localized name matches without an id; the colour is configurable.
    sb.clock = 401
    sb.auras = { { name = "Spell 2565", duration = 5, expiration = 405 } }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bar.bg.hidden, "the resolved localized name matches without an id")
    sb.class_db.warrior_shield_block_bar_color = { 7, 8, 9, 0.5 }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    colour_eq(bar.fill.color, { 7, 8, 9, 0.5 }, "the configured Shield Block colour fills the bar")

    -- The buff gone: the bar and the icon hide.
    sb.clock = 402
    sb.auras = { { name = "Battle Shout", id = 6673, duration = 120, expiration = 520 } }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bar.bg.hidden, "the bar hides when the aura is absent")
    check(bar.icon.hidden, "the icon hides with it")

    -- A listed aura without a usable duration never shows (the reference guard).
    sb.clock = 403
    sb.auras = { { name = "Shield Block", id = 2565 } }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bar.bg.hidden, "an aura without a duration never shows the bar")

    -- Option off: hidden and not a single player aura read.
    sb.class_db.show_warrior_shield_block_bar = false
    sb.auras = { { name = "Shield Block", id = 2565, duration = 5, expiration = 410 } }
    sb.unit_aura_calls = 0
    sb.clock = 404
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bar.bg.hidden, "the option off hides the bar")
    eq(sb.unit_aura_calls, 0, "the option off performs no player aura reads")

    -- Re-enabling scans again and shows the buff.
    sb.class_db.show_warrior_shield_block_bar = true
    sb.clock = 404.5
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bar.bg.hidden, "re-enabling the option shows the bar on the next tick")

    -- With only Shield Block on, the target scan is skipped entirely.
    sb.class_db.show_warrior_deep_wounds_bar = false
    sb.class_db.show_warrior_sunder_armor_bar = false
    sb.class_db.show_warrior_rend_bar = false
    sb.class_db.show_warrior_thunder_clap_bar = false
    sb.class_db.show_warrior_demo_shout_bar = false
    sb.target_aura_calls = 0
    sb.clock = 405
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(sb.target_aura_calls, 0, "only Shield Block on: no target aura reads")
end

--=========================================================================================
-- 17) Slam cast bar: tracking, progress, label, re-anchor and the option gate
--=========================================================================================
do
    local sb = build({ known = { [1464] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local bar = sb.visuals.warrior_slam

    -- START with a live window: start 100.0 s, end 102.5 s.
    sb.clock = 100
    sb.cast_live = { name = "Slam", spell_id = 47475, start_ms = 100000, end_ms = 102500 }
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    eq(ST.warrior_slam_casting, true, "a Slam cast start is tracked")
    near(ST.warrior_slam_cast_start, 100, "the live window's start is honoured")
    near(ST.warrior_slam_cast_duration, 2.5, "the live window's duration is honoured")

    sb.clock = 101
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bar.bg.hidden, "the cast bar shows while casting")
    near(bar.fill.width, 100 * 0.4, "the fill grows with the cast progress")
    eq(bar.label.text, "SLAM 1.5s", "the label shows the remaining time")

    -- The label only re-formats when its tenth-of-a-second readout changes.
    local sets_before = bar.label.text_sets
    sb.clock = 101.01
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(bar.label.text_sets, sets_before, "an unchanged tenth performs no label write")
    sb.clock = 101.5
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(bar.label.text_sets, sets_before + 1, "a changed tenth writes the label once")
    eq(bar.label.text, "SLAM 1.0s", "the label follows the countdown")

    -- DELAYED re-anchors the window without starting a new cast.
    sb.clock = 102
    sb.cast_live = { name = "Slam", spell_id = 47475, start_ms = 101500, end_ms = 104000 }
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_DELAYED", "player", "cast-1", 47475)
    near(ST.warrior_slam_cast_start, 101.5, "DELAYED re-anchors the cast start")
    near(ST.warrior_slam_cast_duration, 2.5, "DELAYED re-anchors the duration")
    sb.clock = 102.5
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    near(bar.fill.width, 100 * 0.4, "progress is measured against the re-anchored window")

    -- STOP hides the bar.
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", nil, nil)
    eq(ST.warrior_slam_casting, false, "the STOP event ends the cast")
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bar.bg.hidden, "the cast bar hides when the cast ends")

    -- No live window: the resolved rank's cast time falls back (the fixture's spell data
    -- carries no cast time, so the reference's 1.5 s default is used).
    sb.cast_live = nil
    sb.clock = 200
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-2", 1464)
    near(ST.warrior_slam_cast_duration, 1.5, "the fallback duration is the reference's 1.5 s")
    check(sb.unit_channel_info_calls > 0, "the live-window read falls through to the channel probe")
    sb.clock = 200.75
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    near(bar.fill.width, 50, "the fallback window drives the same progress fill")
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_INTERRUPTED", "player", nil, nil)
    eq(ST.warrior_slam_casting, false, "an interrupted cast ends the tracking")

    -- Name tokens match through the literal fallback and the resolved names.
    sb.clock = 300
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "Slam", nil)
    eq(ST.warrior_slam_casting, true, "a literal Slam name token is matched")
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", nil, nil)
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "Spell 1464", nil)
    eq(ST.warrior_slam_casting, true, "a resolved localized name token is matched")
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", nil, nil)

    -- An unrelated cast does not arm the bar.
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-9", 12345)
    eq(ST.warrior_slam_casting, false, "an unrelated cast is not tracked")

    -- Option off: the START performs no cast reads and the bar stays hidden.
    sb.class_db.show_warrior_slam_cast_bar = false
    sb.unit_casting_info_calls = 0
    sb.clock = 400
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    eq(ST.warrior_slam_casting, false, "the option off ignores a Slam start")
    eq(sb.unit_casting_info_calls, 0, "the option off performs no cast reads")
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bar.bg.hidden, "the option off keeps the cast bar hidden")
end

--=========================================================================================
-- 17b) The shared stack: Shield Block, Slam and the debuffs slide together
--=========================================================================================
do
    local sb = build({ known = { [2565] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local vf = sb.visuals

    sb.clock = 600
    sb.cast_live = { name = "Slam", spell_id = 47475, start_ms = 600000, end_ms = 601500 }
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    sb.auras = { { name = "Shield Block", id = 2565, duration = 5, expiration = 604 } }
    sb.target_auras = {
        { name = "Deep Wound", source = "player", duration = 12, expiration = 612 },
        { name = "Rend", source = "player", duration = 9, expiration = 609 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(vf.warrior_shield_block.bg.offset_y, 2, "Shield Block holds the slot closest to the bar")
    eq(vf.warrior_slam.bg.offset_y, 8, "the Slam bar stacks above Shield Block")
    eq(vf.warrior_debuff.deep_wounds.bg.offset_y, 14, "Deep Wounds stacks above the Slam bar")
    eq(vf.warrior_debuff.rend.bg.offset_y, 22, "Rend stacks above Deep Wounds")

    -- The Shield Block aura fades while the cast is still tracked: that slot collapses
    -- and everything above it slides down.
    sb.clock = 610
    sb.auras = {}
    sb.target_auras = {
        { name = "Deep Wound", source = "player", duration = 12, expiration = 622 },
        { name = "Rend", source = "player", duration = 9, expiration = 619 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(vf.warrior_shield_block.bg.hidden, "the faded Shield Block hides")
    eq(vf.warrior_slam.bg.offset_y, 2, "the tracked Slam bar slides into the bottom slot")
    eq(vf.warrior_debuff.deep_wounds.bg.offset_y, 8, "Deep Wounds slides down behind it")
    eq(vf.warrior_debuff.rend.bg.offset_y, 16, "Rend follows the slide")

    -- The cast ends: the debuffs slide back to the bar.
    ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", nil, nil)
    sb.clock = 611
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(vf.warrior_slam.bg.hidden, "the ended cast hides the Slam bar")
    eq(vf.warrior_debuff.deep_wounds.bg.offset_y, 2, "Deep Wounds returns to the bottom slot")
    eq(vf.warrior_debuff.rend.bg.offset_y, 10, "Rend stacks above it again")
end

--=========================================================================================
-- 18) Overpower proc window: pure helpers, CLEU arming, clear-on-cast, option gate
--=========================================================================================
do
    local sb = build({ known = { [7384] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local vf = sb.visuals

    -- Pure countdown helper.
    eq(ST.WARRIOR.get_overpower_remaining(nil, 100), nil, "an unset window has no remaining time")
    near(ST.WARRIOR.get_overpower_remaining(105, 100), 5, "an armed window counts down")
    eq(ST.WARRIOR.get_overpower_remaining(100, 100), nil, "a window at its end is over")
    eq(ST.WARRIOR.get_overpower_remaining(99, 100), nil, "an elapsed window is over")

    -- Pure matcher: ids, name tokens and resolved names.
    eq(ST.WARRIOR.is_overpower_cast(7384, nil, 100), true, "the rank-1 id matches")
    eq(ST.WARRIOR.is_overpower_cast(11585, nil, 100), true, "the rank-4 id matches (TBC+ casts)")
    eq(ST.WARRIOR.is_overpower_cast(11584, nil, 100), true, "the rank-3 id matches")
    eq(ST.WARRIOR.is_overpower_cast(7887, nil, 100), true, "the rank-2 id matches")
    eq(ST.WARRIOR.is_overpower_cast(1680, nil, 100), false, "the Whirlwind base id is not Overpower")
    eq(ST.WARRIOR.is_overpower_cast(nil, "Overpower", 100), true, "the literal name token matches")
    eq(ST.WARRIOR.is_overpower_cast(nil, "Spell 7384", 100), true, "the resolved localized name matches")
    eq(ST.WARRIOR.is_overpower_cast(12345, "cast-1", 100), false, "an unrelated cast does not match")

    local function cleu(subevent, ...)
        ST.WARRIOR.on_combat_log_unfiltered(ST, "COMBAT_LOG_EVENT_UNFILTERED", 100, subevent,
            false, "Player-1", "Player", 0, 0, "Target-1", "Target", 0, 0, ...)
    end

    -- A dodged swing arms the 5 s window and the flash appears.
    sb.clock = 100
    cleu("SWING_MISSED", "DODGE", false)
    near(ST.warrior_overpower_proc_until, 105, "a dodged swing arms the 5 s window")
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not vf.warrior_overpower_text.hidden, "the OP marker shows while the window is live")
    check(not vf.warrior_overpower_edges[1].hidden, "the flash edges show too")
    local alpha = vf.warrior_overpower_edges[1].base_color
        and vf.warrior_overpower_edges[1].base_color[4]
    check(type(alpha) == "number" and alpha >= 0.25 and alpha <= 0.7,
        "the edge pulse stays inside the reference's alpha band")

    -- Countdown: still shown just before the end, hidden at the end.
    sb.clock = 104.9
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not vf.warrior_overpower_text.hidden, "the flash holds until the window ends")
    sb.clock = 105
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(vf.warrior_overpower_text.hidden, "the flash hides when the window elapses")
    check(vf.warrior_overpower_edges[2].hidden, "every edge hides with it")

    -- A landed Overpower closes the window immediately (by id and by name token).
    sb.clock = 200
    cleu("SWING_MISSED", "DODGE", false)
    near(ST.warrior_overpower_proc_until, 205, "the window re-arms")
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", nil, 7384)
    eq(ST.warrior_overpower_proc_until, nil, "a landed Overpower clears the window")
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(vf.warrior_overpower_text.hidden, "the flash is gone after the cast")

    cleu("SWING_MISSED", "DODGE", false)
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "Overpower", nil)
    eq(ST.warrior_overpower_proc_until, nil, "a name-token Overpower cast clears the window")

    -- Foreign sources, non-dodges and unrelated spells never arm the window.
    ST.WARRIOR.on_combat_log_unfiltered(ST, "COMBAT_LOG_EVENT_UNFILTERED", 210,
        "SWING_MISSED", false, "Other-1", "Other", 0, 0, "Target-1", "Target", 0, 0, "DODGE", false)
    eq(ST.warrior_overpower_proc_until, nil, "another unit's dodge does not arm the window")
    cleu("SWING_MISSED", "PARRY", false)
    eq(ST.warrior_overpower_proc_until, nil, "a parried swing does not arm the window")

    -- The queued melee abilities arm through SPELL_MISSED; anything else does not.
    sb.clock = 210
    cleu("SPELL_MISSED", 25286, "Heroic Strike", 1, "DODGE")
    near(ST.warrior_overpower_proc_until, 215, "a dodged Heroic Strike arms the window")
    ST.warrior_overpower_proc_until = nil
    cleu("SPELL_MISSED", 25231, "Cleave", 1, "BLOCK")
    eq(ST.warrior_overpower_proc_until, nil, "a blocked Cleave does not arm the window")
    cleu("SPELL_MISSED", 12345, "Something", 1, "DODGE")
    eq(ST.warrior_overpower_proc_until, nil, "an unrelated dodged spell does not arm the window")

    -- R1: string payloads (the Anniversary shape) arm through the name fallback.
    sb.clock = 220
    cleu("SPELL_MISSED", "Heroic Strike", "Heroic Strike", 1, "DODGE")
    near(ST.warrior_overpower_proc_until, 225,
        "R1: a string Heroic Strike arms the window via the literal fallback")
    ST.warrior_overpower_proc_until = nil
    cleu("SPELL_MISSED", "Cleave", "Cleave", 1, "DODGE")
    near(ST.warrior_overpower_proc_until, 225,
        "R1: a string Cleave arms the window via the literal fallback")
    ST.warrior_overpower_proc_until = nil
    cleu("SPELL_MISSED", "Something", "Something", 1, "DODGE")
    eq(ST.warrior_overpower_proc_until, nil, "R1: an unrelated string never arms the window")
    cleu("SPELL_MISSED", nil, "Heroic Strike", 1, "DODGE")
    eq(ST.warrior_overpower_proc_until, nil, "R1: a nil id never arms, even with a proc name")

    -- Combat exit clears an armed window.
    cleu("SWING_MISSED", "DODGE", false)
    check(ST.warrior_overpower_proc_until ~= nil, "the window is armed before the exit")
    ST.WARRIOR.on_combat_exit(ST)
    eq(ST.warrior_overpower_proc_until, nil, "combat exit clears the window")

    -- Option off mid-window: the next tick hides the flash.
    sb.clock = 300
    cleu("SWING_MISSED", "DODGE", false)
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not vf.warrior_overpower_text.hidden, "the flash shows before the option is disabled")
    sb.class_db.show_warrior_overpower_flash = false
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(vf.warrior_overpower_text.hidden, "the option off hides the flash")
    check(vf.warrior_overpower_edges[1].hidden, "the option off hides the edges")
    sb.class_db.show_warrior_overpower_flash = true
end

--=========================================================================================
-- 18b) M3: unmatched Overpower-proc payloads are counted and announced once
--=========================================================================================
do
    local function cleu_spell_missed(S, ...)
        S.WARRIOR.on_combat_log_unfiltered(S, "COMBAT_LOG_EVENT_UNFILTERED", 300,
            "SPELL_MISSED", false, "Player-1", "Tester", 0, 0,
            "Creature-1", "Dummy", 0, 0, ...)
    end

    local sb = build({ known = { [7384] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local notices = {}
    sb.st.utils.print_msg = function(msg) notices[#notices + 1] = msg end

    sb.clock = 300
    cleu_spell_missed(ST, {}, "Heroic Strike", 1, "DODGE")
    eq(ST.warrior_unmatched_payloads, 1, "M3: a table-shaped id is counted")
    eq(#notices, 0, "M3: below the threshold stays quiet")
    cleu_spell_missed(ST, true, "Cleave", 1, "DODGE")
    eq(ST.warrior_unmatched_payloads, 2, "M3: a boolean-shaped id is counted")
    cleu_spell_missed(ST, {}, "Heroic Strike", 1, "DODGE")
    eq(ST.warrior_unmatched_payloads, 3, "M3: the counter keeps counting")
    eq(#notices, 1, "M3: one notice at the threshold")
    check((notices[1] or ""):find("Overpower proc payloads", 1, true) ~= nil,
        "M3: the notice names the payload problem")

    cleu_spell_missed(ST, {}, "Heroic Strike", 1, "DODGE")
    eq(ST.warrior_unmatched_payloads, 4, "M3: the counter keeps counting after the notice")
    eq(#notices, 1, "M3: the notice fires once per session")

    -- Readable shapes never count: numeric proc ids still arm, string ids still
    -- arm, and nil ids plus non-DODGE misses stay silent without counting.
    ST.warrior_overpower_proc_until = nil
    cleu_spell_missed(ST, 25286, "Heroic Strike", 1, "DODGE")
    check(ST.warrior_overpower_proc_until ~= nil, "M3: a readable proc still arms the window")
    ST.warrior_overpower_proc_until = nil
    cleu_spell_missed(ST, "Heroic Strike", "Heroic Strike", 1, "DODGE")
    check(ST.warrior_overpower_proc_until ~= nil, "M3: a readable string proc still arms")
    ST.warrior_overpower_proc_until = nil
    cleu_spell_missed(ST, nil, "Heroic Strike", 1, "DODGE")
    cleu_spell_missed(ST, {}, "Heroic Strike", 1, "BLOCK")
    eq(ST.warrior_unmatched_payloads, 4, "M3: readable and non-dodge shapes do not inflate the counter")
    check(ST.warrior_overpower_proc_until == nil, "M3: the counting path never arms the window")
end

--=========================================================================================
-- 19) Absent spell data (Retail profile): nothing draws, nothing errors
--=========================================================================================
do
    local sb = build({ project = 1 })
    local ST = sb.ST
    eq(sb.st.family, "RETAIL", "the sandbox profiles the Retail family")
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local vf = sb.visuals

    sb.clock = 500
    sb.target_auras = {
        { name = "Some Buff", id = 1234, source = "player", duration = 9, expiration = 509 },
    }
    sb.auras = { { name = "Some Aura", id = 4321, duration = 5, expiration = 505 } }
    local ok, err = pcall(ST.WARRIOR.on_bar_update, ST, "mainhand")
    check(ok, "the Retail profile draws without error (" .. tostring(err) .. ")")
    for key in pairs(vf.warrior_debuff) do
        check(vf.warrior_debuff[key].bg.hidden, "no spell data: the " .. key .. " bar stays hidden")
    end
    check(vf.warrior_shield_block.bg.hidden, "no spell data: the Shield Block bar stays hidden")
    check(vf.warrior_slam.bg.hidden, "no spell data: the Slam bar stays hidden")
    check(vf.warrior_overpower_text.hidden, "no spell data: the Overpower flash stays hidden")

    -- The proc window is only ever armed by the classic-line CLEU dispatch, which
    -- main.lua never registers on a Mainline-code client (pinned in the source check
    -- below): with no dispatch the flash can never appear.
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(vf.warrior_overpower_text.hidden, "with no dispatch the flash never appears")

    -- The hook itself is nil-safe on a Mainline-code profile: a payload that never
    -- arrives cannot error, and the call shape is tolerated if it ever is reached.
    local ok2, err2 = pcall(ST.WARRIOR.on_combat_log_unfiltered, ST,
        "COMBAT_LOG_EVENT_UNFILTERED", 500, "SWING_MISSED", false, "Player-1", "Player",
        0, 0, "Target-1", "Target", 0, 0, "DODGE", false)
    check(ok2, "an absent-data CLEU-shaped call does not error (" .. tostring(err2) .. ")")
    check((ST.warrior_overpower_proc_until or 0) == 0
        or ST.warrior_overpower_proc_until > 500,
        "a manual CLEU-shaped call cannot leave a stale past window")
end

--=========================================================================================
-- 20) Config/options parity and the main.lua combat-log wiring
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local new_toggle_keys = {
        "show_warrior_deep_wounds_bar", "show_warrior_sunder_armor_bar",
        "show_warrior_rend_bar", "show_warrior_thunder_clap_bar",
        "show_warrior_demo_shout_bar", "show_warrior_shield_block_bar",
        "show_warrior_slam_cast_bar", "show_warrior_overpower_flash",
    }
    local new_colour_keys = {
        "warrior_deep_wounds_bar_color", "warrior_sunder_armor_bar_color",
        "warrior_rend_bar_color", "warrior_thunder_clap_bar_color",
        "warrior_demo_shout_bar_color", "warrior_shield_block_bar_color",
    }

    local presets = read("config_presets.lua")
    local warrior_defaults = presets:match("ST%.WARRIOR%.defaults%s*=%s*%{(.-)$")
    check(warrior_defaults ~= nil, "the WARRIOR defaults block is found in config_presets.lua")
    warrior_defaults = warrior_defaults or ""
    local options = read("option_tables.lua")
    local warrior_opts = options:match("function ST%.class_opts_funcs%.WARRIOR%((.*)$")
    check(warrior_opts ~= nil, "the WARRIOR options function is found in option_tables.lua")
    warrior_opts = warrior_opts or ""
    for i = 1, #new_toggle_keys do
        local key = new_toggle_keys[i]
        check(warrior_defaults:find("%f[%a_]" .. key .. "%s*=%s*true") ~= nil,
            key .. " ships true in the WARRIOR defaults")
        local widget = warrior_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"toggle\"") ~= nil,
            key .. " has a toggle widget in the WARRIOR options section")
    end
    for i = 1, #new_colour_keys do
        local key = new_colour_keys[i]
        check(warrior_defaults:find("%f[%a_]" .. key .. "%s*=%s*{") ~= nil,
            key .. " has a colour default in the WARRIOR defaults")
        local widget = warrior_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"color\"") ~= nil,
            key .. " has a colour widget in the WARRIOR options section")
    end

    -- G2: the classic-line combat log gate covers every classic-line class (the
    -- neutral extra-attack/parry pre-pass is class-independent) and the handler keeps
    -- the paladin/warrior dispatch chains, with the init guard intact.
    local main_src = read("main.lua")
    local gate = main_src:match(
        "if not st%.is_mainline then[^\n]*")
    check(gate ~= nil,
        "the CLEU registration gate covers the classic line (G2 all-class)")

    local handler_lines = {}
    local in_handler = false
    for line in (main_src .. "\n"):gmatch("[^\n]+") do
        if line:find("function ST:COMBAT_LOG_EVENT_UNFILTERED", 1, true) then
            in_handler = true
        end
        if in_handler then
            handler_lines[#handler_lines + 1] = line
            if line:match("^end") then
                break
            end
        end
    end
    local handler = table.concat(handler_lines, "\n")
    check(handler:find("self%.PALADIN%.on_combat_log_unfiltered%(self, event, %.%.%.%)") ~= nil,
        "the combat-log handler dispatches the paladin chain")
    check(handler:find("self%.WARRIOR%.on_combat_log_unfiltered%(self, event, %.%.%.%)") ~= nil,
        "the combat-log handler dispatches the warrior hook")
    check(handler:find("interfaces_are_initialised", 1, true) ~= nil,
        "the combat-log handler keeps the init guard")
end

--=========================================================================================
-- 21) Rampage upkeep badge: pure display, aura plumbing, badge drawing, Retail inertness
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    -- Pure display helper: stacks + refresh window, or nil when the badge hides.
    eq(ST.WARRIOR.get_rampage_display(nil, nil, 100), nil, "no stacks: the badge hides")
    eq(ST.WARRIOR.get_rampage_display("3", 130, 100), nil, "a non-numeric stack count hides the badge")
    eq(ST.WARRIOR.get_rampage_display(0, 130, 100), nil, "zero stacks hide the badge")
    eq(ST.WARRIOR.get_rampage_display(-2, 130, 100), nil, "a negative stack count hides the badge")
    eq(ST.WARRIOR.get_rampage_display(5, 112, 100), "RAMPAGE x5 12s",
        "five stacks with 12 s left read RAMPAGE x5 12s")
    eq(ST.WARRIOR.get_rampage_display(5, 112.4, 100), "RAMPAGE x5 12s",
        "the countdown rounds to whole seconds")
    eq(ST.WARRIOR.get_rampage_display(5, 100, 100), nil, "an exactly elapsed window hides the badge")
    eq(ST.WARRIOR.get_rampage_display(5, 99, 100), nil, "an elapsed window hides the badge")
    eq(ST.WARRIOR.get_rampage_display(3, nil, 100), "RAMPAGE x3",
        "no expiration degrades to the stacks-only form")
    eq(ST.WARRIOR.get_rampage_display(3, 0, 100), "RAMPAGE x3",
        "a zero expiration degrades to the stacks-only form")

    -- Aura plumbing: one walk feeds Blood Surge and Rampage together.
    sb.clock = 100
    sb.auras = {
        { name = "Blood Surge", id = 46916, count = 1 },
        { name = "Rampage", id = 29838, count = 3, duration = 30, expiration = 130 },
    }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, true, "the shared walk still detects Blood Surge")
    eq(ST.warrior_rampage_stacks, 3, "the shared walk reads the Rampage stack count")
    eq(ST.warrior_rampage_expires, 130, "the shared walk reads the Rampage expiration")
    eq(sb.last_aura_filter, "HELPFUL", "the Rampage read uses the typed HELPFUL filter")

    -- Overcapped counts clamp to the 5-stack cap.
    sb.auras = {
        { name = "Rampage", id = 29838, count = 9, duration = 30, expiration = 130 },
    }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_rampage_stacks, 5, "a 9-stack reading clamps to the 5-stack cap")

    -- A missing count still means one stack; the literal name matches without an id.
    sb.auras = {
        { name = "Rampage", duration = 30, expiration = 130 },
    }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_rampage_stacks, 1, "a missing stack count reads as one stack")

    -- Aura gone: the state clears.
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_rampage_stacks, nil, "a faded buff clears the stack count")
    eq(ST.warrior_rampage_expires, nil, "a faded buff clears the expiration")

    -- Badge drawing through the real per-frame hook.
    ST.WARRIOR.post_init(ST)
    local badge = sb.visuals.warrior_rampage_text
    check(badge ~= nil, "post_init creates the Rampage badge widget")
    check(badge.hidden, "the badge starts hidden")
    sb.auras = {
        { name = "Rampage", id = 29838, count = 5, duration = 30, expiration = 112 },
    }
    ST.WARRIOR.on_aura_change(ST)
    sb.clock = 100
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not badge.hidden, "five live stacks show the badge")
    eq(badge.text, "RAMPAGE x5 12s", "the badge shows stacks + refresh window")
    near(badge.color[1], 46 / 255, "the badge colour converts to the green tier")
    near(badge.color[2], 204 / 255, "the badge colour converts to the green tier (green)")
    near(badge.color[3], 113 / 255, "the badge colour converts to the green tier (blue)")
    near(badge.color[4], 1.0, "the green tier keeps full alpha")

    -- The text is only re-set when the readout changes.
    local sets_before = badge.text_sets
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text_sets, sets_before, "an unchanged readout performs no text write")
    sb.clock = 101
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text, "RAMPAGE x5 11s", "the countdown follows the refresh window")
    eq(badge.text_sets, sets_before + 1, "a changed readout writes the text once")

    -- A lost stack re-formats; the option off hides; expiry hides without an event.
    sb.auras = {
        { name = "Rampage", id = 29838, count = 4, duration = 30, expiration = 131 },
    }
    ST.WARRIOR.on_aura_change(ST)
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text, "RAMPAGE x4 30s", "a lost stack re-formats the badge")
    sb.class_db.show_warrior_rampage_badge = false
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(badge.hidden, "the option off hides the badge")
    sb.class_db.show_warrior_rampage_badge = true
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not badge.hidden, "re-enabling the option shows the badge again")
    sb.clock = 200
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(badge.hidden, "an elapsed window hides the badge without a new aura event")
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(badge.hidden, "a faded buff hides the badge")

    -- The badge adds no client reads on the frame path: the aura event owns the state.
    sb.class_db.show_warrior_deep_wounds_bar = false
    sb.class_db.show_warrior_sunder_armor_bar = false
    sb.class_db.show_warrior_rend_bar = false
    sb.class_db.show_warrior_thunder_clap_bar = false
    sb.class_db.show_warrior_demo_shout_bar = false
    sb.class_db.show_warrior_shield_block_bar = false
    sb.class_db.show_warrior_overpower_flash = false
    ST.warrior_rampage_stacks = 5
    ST.warrior_rampage_expires = 312
    sb.clock = 300
    sb.unit_aura_calls = 0
    sb.target_aura_calls = 0
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(sb.unit_aura_calls, 0, "the badge performs no player aura reads on the frame path")
    eq(sb.target_aura_calls, 0, "the badge performs no target aura reads on the frame path")
    eq(badge.text, "RAMPAGE x5 12s", "the read-free tick still draws the badge")
end

--=========================================================================================
-- 22) Rampage on the Retail profile: no aura, no badge, no error
--=========================================================================================
do
    local sb = build({ project = 1 })
    local ST = sb.ST
    eq(sb.st.family, "RETAIL", "the sandbox profiles the Retail family")
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)

    sb.clock = 500
    sb.auras = { { name = "Some Aura", id = 4321, duration = 5, expiration = 505 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_rampage_stacks, nil, "no Rampage aura: no stacks on Retail either")
    local ok, err = pcall(ST.WARRIOR.on_bar_update, ST, "mainhand")
    check(ok, "the Retail profile draws the badge path without error (" .. tostring(err) .. ")")
    check(sb.visuals.warrior_rampage_text.hidden, "no Rampage aura: the badge stays hidden on Retail")
end

--=========================================================================================
-- 23) Spec / SoD probes, Sudden Death / Taste for Blood aura plumbing, the WotLK
-- Rend rank and the arms/SoD gather flags
--=========================================================================================
do
    -- Spec rule (documented): Mortal Strike known = arms. Each rank answers the
    -- probe on its own; no Mortal Strike id sits in the HS table (section 6).
    for _, ms_id in ipairs({ 12294, 21551, 21552, 21553, 25248, 30330, 47485, 47486 }) do
        local sb = build({ known = { [ms_id] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_is_arms, true,
            "Mortal Strike " .. ms_id .. " known freezes the arms branch")
        eq(ST.WARRIOR.guide.slots[4].key, "ms",
            "the arms slot set carries the ms slot")
    end
    do
        local sb = build({ known = { [47450] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_is_arms, false,
            "no Mortal Strike known freezes the fury branch")
        eq(ST.WARRIOR.guide.slots[5].key, "bt",
            "the fury slot set carries the BT slot")
        eq(ST.warrior_is_sod, false, "no runes freezes no SoD flag on Wrath")
    end

    -- SoD rule (documented): ERA family + Raging Blow or Consumed by Rage known.
    -- Either rune answers on its own; Era-base (neither) stays off; a Wrath
    -- client never reports SoD (the probe requires the ERA token).
    for _, rune_id in ipairs({ 402911, 425440 }) do
        local sb = build({ project = 2, known = { [rune_id] = true } })
        local ST = sb.ST
        eq(sb.st.family, "ERA", "the SoD probe sandbox runs the ERA family")
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_is_sod, true,
            "rune " .. rune_id .. " known freezes the SoD branch")
        eq(ST.WARRIOR.guide.slots[6].key, "raging_blow",
            "the SoD slot set carries the raging_blow slot")
    end
    do
        local sb = build({ project = 2, known = {} })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_is_sod, false, "Era-base (no runes) freezes no SoD flag")
        eq(ST.WARRIOR.guide.slots[1].key, "op", "Era-base keeps the op slot")
    end
    do
        local sb = build({ known = { [402911] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_is_sod, false,
            "the rune probe requires the ERA token (silent on Wrath)")
    end

    -- Sudden Death / Taste for Blood ride the shared aura walk (no extra reads).
    do
        local sb = build()
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.has_sudden_death, false, "post_init starts with no SD proc")
        eq(ST.has_tfb, false, "post_init starts with no TfB proc")
        sb.auras = {
            { name = "Sudden Death", id = 52437, count = 1 },
            { name = "Taste for Blood", id = 60503, count = 1 },
        }
        ST.WARRIOR.on_aura_change(ST)
        eq(ST.has_sudden_death, true, "the shared walk detects the SD proc aura")
        eq(ST.has_tfb, true, "the shared walk detects the TfB proc aura")
        eq(ST.has_bloodsurge, false, "the proc auras are not a Blood Surge proc")
        -- The literal English fallback matches without an id.
        sb.auras = { { name = "Sudden Death" }, { name = "Taste for Blood" } }
        ST.WARRIOR.on_aura_change(ST)
        eq(ST.has_sudden_death, true, "the literal SD name matches as the fallback")
        eq(ST.has_tfb, true, "the literal TfB name matches as the fallback")
        -- The SoD SD aura id matches too (in-game to confirm which id fires).
        sb.auras = { { name = "Sudden Death", id = 440495, count = 1 } }
        ST.WARRIOR.on_aura_change(ST)
        eq(ST.has_sudden_death, true, "the SoD SD aura id matches")
        -- Aura gone: both flags clear with the walk.
        sb.auras = {}
        ST.WARRIOR.on_aura_change(ST)
        eq(ST.has_sudden_death, false, "a faded SD proc clears the flag")
        eq(ST.has_tfb, false, "a faded TfB proc clears the flag")
    end

    -- The WotLK Rend rank (47465) matches the Rend tracker by id.
    do
        local sb = build()
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        local bars = sb.visuals.warrior_debuff
        sb.clock = 600
        sb.target_auras = {
            { name = "Rend", id = 47465, source = "player", duration = 15,
                expiration = 609 },
        }
        ST.WARRIOR.on_bar_update(ST, "mainhand")
        check(not bars.rend.bg.hidden, "the WotLK Rend rank shows its bar by id")
        eq(bars.rend.label.text, "9", "the WotLK Rend label counts its own duration")
    end

    -- The arms gather flags (frozen arms, live procs, nil core readers).
    do
        local sb = build({ known = { [47486] = true, [63784] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        sb.auras = {
            { name = "Sudden Death", id = 52437, count = 1 },
            { name = "Taste for Blood", id = 60503, count = 1 },
        }
        ST.WARRIOR.on_aura_change(ST)
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.wrath_arms, true, "arms gather: the frozen arms flag")
        eq(inputs.wrath_fury, nil, "arms gather: no fury flag")
        eq(inputs.bt_remaining, nil, "arms gather: no BT reader")
        eq(inputs.ww_remaining, nil, "arms gather: no WW reader")
        eq(inputs.hs_rage_floor, 50, "arms gather: the 50-rage dump floor")
        eq(inputs.sudden_death, true, "arms gather: the live SD proc")
        eq(inputs.tfb, true, "arms gather: the live TfB proc")
        eq(inputs.bladestorm_known, true, "arms gather: the live talent probe")
        eq(inputs.rend_remaining, nil, "arms gather: no target Rend reads as nil")
        eq(inputs.hs_cancel_cue, nil, "arms gather: no TBC HS-cancel cue")
        eq(inputs.victory_rush, nil, "arms gather: no Forever Victory Rush")
        -- Every action the arms branch can return names a declared slot.
        for _, action in ipairs({ "op", "execute", "rend", "ms",
            "bladestorm", "hs" }) do
            local found = false
            for i = 1, #ST.WARRIOR.guide.slots do
                if ST.WARRIOR.guide.slots[i].key == action then found = true end
            end
            check(found, "the arms slot set names " .. action)
        end
    end
end

--=========================================================================================
-- 24) Forever Bloodthrill: the aura arms the Overpower window (the second OP
-- source alongside the dodge window, which can never arm on Mainline clients)
--=========================================================================================
do
    local sb = build({ project = 18 })
    eq(sb.st.family, "FOREVER", "project 18 maps to FOREVER")
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    eq(ST.warrior_overpower_proc_until, nil, "post_init starts with no OP window")

    -- The UNCONFIRMED literal name arms the 5 s window on Forever.
    sb.clock = 500
    sb.auras = { { name = "Bloodthrill", count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    near(ST.warrior_overpower_proc_until, 505,
        "Bloodthrill arms the 5 s OP window on Forever")
    near(ST.WARRIOR.get_overpower_remaining(ST.warrior_overpower_proc_until, 502), 3,
        "the armed window counts down")
    eq(ST.has_bloodsurge, false, "Bloodthrill is not a Blood Surge proc")
    eq(ST.has_tfb, false, "Bloodthrill is not a Taste for Blood proc")

    -- The flash draws through the real per-frame hook while the window is live.
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not sb.visuals.warrior_overpower_text.hidden,
        "the Bloodthrill window shows the OP flash on Forever")
    eq(sb.visuals.warrior_overpower_text.text, "OP",
        "the Forever flash centres the OP marker")

    -- Aura gone: the stamp is left to lapse, like the dodge window.
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    near(ST.warrior_overpower_proc_until, 505,
        "a faded Bloodthrill leaves the stamp to lapse")
    eq(ST.WARRIOR.get_overpower_remaining(ST.warrior_overpower_proc_until, 506), nil,
        "the lapsed window reads nil")

    -- The same aura on a non-Forever client arms nothing.
    local wrath = build()
    eq(wrath.st.family, "WRATH", "the default sandbox runs the Wrath family")
    local WST = wrath.ST
    WST.interfaces_are_initialised = true
    WST.WARRIOR.post_init(WST)
    wrath.clock = 500
    wrath.auras = { { name = "Bloodthrill", count = 1 } }
    WST.WARRIOR.on_aura_change(WST)
    eq(WST.warrior_overpower_proc_until, nil,
        "Bloodthrill arms nothing outside Forever")
    WST.WARRIOR.on_bar_update(WST, "mainhand")
    check(wrath.visuals.warrior_overpower_text.hidden,
        "no window, no OP flash outside Forever")
end

--=========================================================================================
-- 25) Slam safe-window band: green when the cast lands before the next swing,
-- red when the swing lands mid-cast; Forever always reads clean (no swing reset)
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local bar = sb.visuals.warrior_slam
    ST.warrior_slam_casting = true
    ST.warrior_slam_cast_start = 100
    ST.warrior_slam_cast_duration = 1.5
    sb.clock = 100

    -- Cast completes (101.5) before the swing (110): clean, green.
    ST.mainhand = { ends_at = 110 }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bar.bg.hidden, "the Slam bar draws while casting")
    colour_eq(bar.fill.color, { 46, 204, 113, 1.0 },
        "cast lands before the swing -> green")

    -- Swing (100.5) lands mid-cast: clash, red.
    ST.mainhand = { ends_at = 100.5 }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    colour_eq(bar.fill.color, { 217, 38, 26, 0.90 },
        "swing lands mid-cast -> red")

    -- No swing data (no mainhand yet): the verdict answers nil and the fill is
    -- left untouched instead of erroring.
    local nb = build()
    local NST = nb.ST
    NST.interfaces_are_initialised = true
    NST.WARRIOR.post_init(NST)
    local nbar = nb.visuals.warrior_slam
    NST.warrior_slam_casting = true
    NST.warrior_slam_cast_start = 100
    NST.warrior_slam_cast_duration = 1.5
    nb.clock = 100
    NST.WARRIOR.on_bar_update(NST, "mainhand")
    check(not nbar.bg.hidden, "the Slam bar still draws without swing data")
    eq(nbar.fill.color, nil, "an unknown swing leaves the fill untouched")

    -- A flavor without the guide module: the nil-guard keeps the white fill
    -- instead of erroring.
    nb.st.warrior_guide = nil
    NST.mainhand = { ends_at = 100.5 }
    NST.WARRIOR.on_bar_update(NST, "mainhand")
    eq(nbar.fill.color, nil, "a missing guide module leaves the fill untouched")

    -- Forever: the same clash numbers read clean (Slam never resets the swing).
    local fsb = build({ project = 18 })
    local FST = fsb.ST
    FST.interfaces_are_initialised = true
    FST.WARRIOR.post_init(FST)
    local fbar = fsb.visuals.warrior_slam
    FST.warrior_slam_casting = true
    FST.warrior_slam_cast_start = 100
    FST.warrior_slam_cast_duration = 1.5
    FST.mainhand = { ends_at = 100.5 }
    fsb.clock = 100
    FST.WARRIOR.on_bar_update(FST, "mainhand")
    colour_eq(fbar.fill.color, { 46, 204, 113, 1.0 },
        "Forever: no swing reset -> always green")
end

--=========================================================================================
-- 26) Build-out W2: the composite rage gate (verify §4.2 - BINDING)
--=========================================================================================
-- The pure predicate row-table, the gate over the engine's Bloodthirst pick
-- ("BT first, WW next" on a short-fall, nil otherwise), the reserve semantics
-- (a queued HS/Cleave cost is protected ahead of the prompt) and the RIDE
-- pass-through (the engine rides a queue before any core prompt, so the gate
-- must never touch a held prompt).

do
    local sb = build()
    local ST = sb.ST

    check(ST.WARRIOR.composite_rage_gate(100, 30, 0) == true,
        "W2 gate: rage covers the cost")
    check(ST.WARRIOR.composite_rage_gate(29, 30, 0) == false,
        "W2 gate: rage below the cost withhold")
    check(ST.WARRIOR.composite_rage_gate(60, 25, 30) == true,
        "W2 gate: rage at cost + reserve still passes")
    check(ST.WARRIOR.composite_rage_gate(54, 25, 30) == false,
        "W2 gate: rage below cost + reserve withhold")
    check(ST.WARRIOR.composite_rage_gate(nil, 30, 0) == true,
        "W2 gate: unknown power is not a shortage")
    check(ST.WARRIOR.composite_rage_gate(29, nil, 0) == true,
        "W2 gate: unknown cost is not a shortage (degrade to allow)")
    check(ST.WARRIOR.composite_rage_gate(10, 10, nil) == true,
        "W2 gate: an unknown reserve degrades to absent")
    check(ST.WARRIOR.composite_rage_gate(9, 10, nil) == false,
        "W2 gate: degraded reserve still judges cost")

    -- Direct gate rows: the fresh out keeps hold fields visible.
    local out = { action = nil, hold = true, hold_text = "RIDE" }
    ST.WARRIOR.gate_composite_action({ rage = 5, hs_queued = true, hs_cost = 30 }, out)
    eq(out.action, nil, "W2 gate: a non-BT pick passes untouched (RIDE)")
    eq(out.hold_text, "RIDE", "W2 gate: a non-BT pick keeps its hold text")
    out = { action = "ww", hold = false }
    ST.WARRIOR.gate_composite_action({ rage = 29, ww_remaining = 1 }, out)
    eq(out.action, "ww", "W2 gate: a WW pick passes untouched")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action({ rage = nil, bt_cost = 30 }, out)
    eq(out.action, "bt", "W2 gate: unknown power keeps the BT prompt (label contract)")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action({ rage = 5, ww_remaining = nil, ww_cost = 25 }, out)
    eq(out.action, nil, "W2 gate: a gated BT with no WW read demotes to no prompt")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action({ rage = 29, ww_remaining = 0, ww_cost = 25 }, out)
    eq(out.action, "ww", "W2 gate: a gated BT falls back to ready+affordable WW")
    eq(out.hold, false, "W2 gate: the fallback keeps the hold shape")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action({ rage = 29, ww_remaining = 1 }, out)
    eq(out.action, nil, "W2 gate: a gated BT with WW on cooldown demotes to no prompt")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action(
        { rage = 5, hs_queued = true, hs_cost = 30, ww_remaining = 0, ww_cost = 25 }, out)
    eq(out.action, nil,
        "W2 gate: the HS reserve beats even the ready WW fallback (5 < 55)")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action(
        { rage = 29, cleave_queued = true, cleave_cost = 30, ww_remaining = 0, ww_cost = 25 }, out)
    eq(out.action, nil, "W2 gate: the Cleave reserve arms the same composite")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action(
        { rage = 57, hs_queued = true, hs_cost = 30, ww_remaining = 0, ww_cost = 25 }, out)
    eq(out.action, "ww", "W2 gate: the reserve carries onto the WW fallback (57 < 60, >= 55)")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action({ rage = 66, bt_cost = nil }, out)
    eq(out.action, "bt", "W2 gate: a muted BT cost falls back to the fixed cost (66 >= 30)")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action({ rage = 29, bt_cost = nil }, out)
    eq(out.action, nil, "W2 gate: the muted-cost fallback still withholds at the floor")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action(
        { rage = 29, bt_cost = nil, ww_cost = nil, ww_remaining = 0 }, out)
    eq(out.action, "ww", "W2 gate: both fallback costs still arm the WW fallback")
    out = { action = "bt", hold = false }
    ST.WARRIOR.gate_composite_action({ rage = 45, bt_cost = nil }, out)
    eq(out.action, "bt", "W2 gate: a muted BT cost passes above its fallback")

    -- Wrapper rows over the REAL engine: rule 5 (a ready core reader) feeds the
    -- gate directly, so the demote/fallback is observable end to end.
    local function core_inputs(rage)
        return {
            target_health_pct = 50,
            hs_queued = false,
            cleave_queued = false,
            bt_remaining = 0,
            ww_remaining = 0,
            bt_cost = 30,
            ww_cost = 25,
            rage = rage,
        }
    end
    out = ST.WARRIOR.guide.evaluate(core_inputs(70), {})
    eq(out.action, "bt", "W2 wrapper: the engine's core prompt is Bloodthirst")
    out = ST.WARRIOR.guide.evaluate(core_inputs(29), {})
    eq(out.action, "ww", "W2 wrapper: short rage demotes the pick to the WW core")
    local withheld = core_inputs(29)
    withheld.ww_remaining = 1
    out = ST.WARRIOR.guide.evaluate(withheld, {})
    eq(out.action, nil, "W2 wrapper: short rage + WW on cooldown prompts nothing")
    local ride = core_inputs(200)
    ride.hs_queued = true
    out = ST.WARRIOR.guide.evaluate(ride, {})
    eq(out.action, nil, "W2 wrapper: a queued HS rides before any core prompt")
    eq(out.hold_text, "RIDE", "W2 wrapper: the RIDE pass-through keeps its text")
end

--=========================================================================================
-- 27) Build-out W1: the rage-bank cue - the pure state, the widget draw path,
--     the read gating and the default-off toggle
--=========================================================================================

do
    local sb0 = build()
    local ST0 = sb0.ST
    eq(ST0.WARRIOR.get_bank_state(30, 20, 70, true), true, "W1 state: in the band at the floor")
    eq(ST0.WARRIOR.get_bank_state(30, 20, 70, false), false, "W1 state: out of combat never banks")
    eq(ST0.WARRIOR.get_bank_state(30, 20, 70, nil), false, "W1 state: unknown combat never banks")
    eq(ST0.WARRIOR.get_bank_state(nil, 20, 70, true), false, "W1 state: unknown health never arms")
    eq(ST0.WARRIOR.get_bank_state(30, nil, 70, true), false, "W1 state: unknown threshold never arms")
    eq(ST0.WARRIOR.get_bank_state(30, 20, nil, true), false, "W1 state: unknown rage never arms")
    eq(ST0.WARRIOR.get_bank_state(30, 20, 59, true), false, "W1 state: below the floor")
    eq(ST0.WARRIOR.get_bank_state(30, 20, 60, true), true, "W1 state: at the floor (inclusive)")
    eq(ST0.WARRIOR.get_bank_state(19.9, 20, 70, true), false, "W1 state: below the band")
    eq(ST0.WARRIOR.get_bank_state(20, 20, 70, true), true, "W1 state: at the band bottom (inclusive)")
    eq(ST0.WARRIOR.get_bank_state(34.9, 20, 70, true), true, "W1 state: inside the band top")
    eq(ST0.WARRIOR.get_bank_state(35, 20, 70, true), false, "W1 state: past the band top (exclusive)")
    eq(ST0.WARRIOR.get_bank_state(10, 20, 70, true), false, "W1 state: already in Execute -> no bank")

    -- Widget path: 30 % health (inside the default [20, 35) band), rage hits
    -- the floor in combat.
    local sb = build({ health = { player = { cur = 3000, max = 10000 } } })
    local ST = sb.ST
    ST.WARRIOR.post_init(ST)
    check(sb.visuals.warrior_bank ~= nil, "W1 cue: the widgets exist after setup")
    local bank_edge = sb.visuals.warrior_bank.edge
    local bank_text = sb.visuals.warrior_bank.text
    eq(bank_text.text, "BANK", "W1 cue: the static label is the creation-time write")
    check(bank_edge.hidden and bank_text.hidden, "W1 cue: both widgets start hidden")

    -- The nil-off default: the cue never shows while the toggle is unset,
    -- even with a fully armed state.
    ST.in_combat = true
    sb.power = 70
    sb.clock = 100
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bank_edge.hidden, "W1 cue: the unset toggle hides the edge (nil = off)")
    check(bank_text.hidden, "W1 cue: the unset toggle hides the text (nil = off)")
    eq(sb.unit_health_calls, 0, "W1 cue: the reads sit behind the toggle entirely")

    sb.class_db.show_warrior_bank_cue = true
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bank_edge.hidden, "W1 cue: the armed state shows the edge")
    check(not bank_text.hidden, "W1 cue: the armed state shows the text")
    check(sb.unit_health_calls > 0, "W1 cue: the reads run behind the toggle")
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bank_edge.hidden, "W1 cue: an unchanged state stays shown")

    sb.power = 59
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bank_edge.hidden, "W1 cue: rage below the floor hides the cue")
    check(bank_text.hidden, "W1 cue: rage below the floor hides the text")

    sb.power = 70
    sb.health_player_cur = 3550
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bank_edge.hidden, "W1 cue: past the band top hides the cue")

    sb.health_player_cur = 3400
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bank_edge.hidden, "W1 cue: back inside the band re-arms the cue")

    ST.in_combat = nil
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bank_edge.hidden, "W1 cue: combat exit hides the cue")

    -- The toggle off stops the reads too (the early exit precedes them).
    ST.in_combat = true
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bank_edge.hidden, "W1 cue: re-arms again")
    sb.class_db.show_warrior_bank_cue = false
    local reads_before_off = sb.unit_health_calls
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(bank_edge.hidden, "W1 cue: the toggle off hides the cue")
    eq(sb.unit_health_calls, reads_before_off, "W1 cue: the toggle off stops the reads")

    -- Unknown health in a build without the fixture never arms the cue
    -- (the nil read is not zero and never in-band).
    local nsb = build()
    local NST = nsb.ST
    NST.WARRIOR.post_init(NST)
    NST.in_combat = true
    nsb.power = 70
    nsb.class_db.show_warrior_bank_cue = true
    NST.WARRIOR.on_bar_update(NST, "mainhand")
    check(nsb.visuals.warrior_bank.edge.hidden, "W1 cue: unreadable health never arms")
end

--=========================================================================================
-- 28) Build-out W3: rampage refresh tiers - the pure tier matrix and the badge
--     recolouring on the draw path
--=========================================================================================

do
    local sb0 = build()
    local ST0 = sb0.ST
    eq(ST0.WARRIOR.get_rampage_tier(nil, nil, 0), nil, "W3 tier: no buff -> no tier")
    eq(ST0.WARRIOR.get_rampage_tier(0, 100, 90), nil, "W3 tier: zero stacks -> no tier")
    eq(ST0.WARRIOR.get_rampage_tier(5, nil, 0), "amber", "W3 tier: no expiry reads amber (uncertain)")
    eq(ST0.WARRIOR.get_rampage_tier(5, 0, 0), "amber", "W3 tier: a zero expiry reads amber")
    eq(ST0.WARRIOR.get_rampage_tier(5, 13.5, 0), "green", "W3 tier: well-maintained -> green")
    eq(ST0.WARRIOR.get_rampage_tier(5, 4.01, 0), "green", "W3 tier: outside the glow window -> green")
    eq(ST0.WARRIOR.get_rampage_tier(5, 4.0, 0), "amber", "W3 tier: at the glow window edge -> amber")
    eq(ST0.WARRIOR.get_rampage_tier(5, 2.01, 0), "amber", "W3 tier: between 2 and 4 -> amber")
    eq(ST0.WARRIOR.get_rampage_tier(5, 2.0, 0), "red", "W3 tier: at the 2 s edge -> red")
    eq(ST0.WARRIOR.get_rampage_tier(5, 4.5, 5), "red", "W3 tier: elapsed -> red")

    -- The draw path recolours the badge as the window decays, and an
    -- expiry-less buff reads the uncertain amber on the widget itself.
    local sb = build()
    local ST = sb.ST
    ST.WARRIOR.post_init(ST)
    local badge = sb.visuals.warrior_rampage_text
    sb.auras = { { name = "Rampage", id = 29838, count = 5, duration = 30, expiration = 1430 } }
    ST.WARRIOR.on_aura_change(ST)
    sb.clock = 1400
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text, "RAMPAGE x5 30s", "W3 badge: the fresh window readout")
    colour_eq(badge.color, { 46, 204, 113, 1.0 }, "W3 badge: a fresh window reads green")
    sb.clock = 1426
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    colour_eq(badge.color, { 255, 140, 26, 0.95 }, "W3 badge: inside the glow window reads amber")
    sb.clock = 1428.5
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    colour_eq(badge.color, { 217, 38, 26, 1.0 }, "W3 badge: inside the final 2 s reads red")
    sb.auras = { { name = "Rampage", id = 29838, count = 4, duration = 30 } }
    ST.WARRIOR.on_aura_change(ST)
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not badge.hidden, "W3 badge: an expiry-less buff still draws")
    colour_eq(badge.color, { 255, 140, 26, 0.95 }, "W3 badge: an unknown window reads amber")
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(badge.hidden, "W3 badge: a faded buff hides the badge")
end

--=========================================================================================
-- 29) Build-out W7: the HUD readiness-glow fallback - probe-only, never gated
--     on st.is_mainline, the live window short-circuits, scope pinned to OP
--=========================================================================================

do
    local usable_calls = 0
    local sb = build({
        known = { [7384] = true },
        usable = function(id)
            usable_calls = usable_calls + 1
            return id == "Spell 7384"
        end,
    })
    local ST = sb.ST
    ST.WARRIOR.post_init(ST)
    local slot = ST.WARRIOR.HUD_SLOTS[1]
    eq(slot.key, "op", "W7 probe: the slot under test is Overpower")

    -- A live dodge window drives the glow and short-circuits the probe.
    sb.clock = 500
    ST.warrior_overpower_proc_until = 505
    local s = ST.WARRIOR.get_hud_state(ST, slot, 500)
    eq(s.glow, true, "W7 probe: a live window glows")
    eq(usable_calls, 0, "W7 probe: a live window skips the probe")
    ST.warrior_overpower_proc_until = nil

    -- A stamp that is set but elapsed is the window's own verdict: the glow
    -- stops and the probe is not consulted (the hud_state binding pin,
    -- mirrored here so the lifecycle rule is provable inside this suite).
    ST.warrior_overpower_proc_until = 499
    local probe_calls_before = usable_calls
    s = ST.WARRIOR.get_hud_state(ST, slot, 500)
    eq(s.glow, false, "W7 probe: an elapsed window stops the glow")
    eq(usable_calls, probe_calls_before, "W7 probe: an elapsed window skips the probe")
    ST.warrior_overpower_proc_until = nil

    -- Empty stamp: the probe runs and arms the fallback.
    s = ST.WARRIOR.get_hud_state(ST, slot, 500)
    check(usable_calls > 0, "W7 probe: an empty stamp runs the probe")
    eq(s.glow, true, "W7 probe: a usable spell arms the fallback glow")
    local unchanged = usable_calls
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(usable_calls >= unchanged, "W7 probe: the draw pass survives the fallback")

    -- The probe answering false (or unknown) never arms a glow.
    local nope = build({
        known = { [7384] = true },
        usable = function() return false end,
    })
    local NOP = nope.ST
    NOP.WARRIOR.post_init(NOP)
    NOP.warrior_overpower_proc_until = nil
    s = NOP.WARRIOR.get_hud_state(NOP, NOP.WARRIOR.HUD_SLOTS[1], 500)
    eq(s.glow, false, "W7 probe: an unusable reading keeps the glow off")

    local herd = build({
        known = { [7384] = true },
        usable = function() return nil end,
    })
    local HUDP = herd.ST
    HUDP.WARRIOR.post_init(HUDP)
    s = HUDP.WARRIOR.get_hud_state(HUDP, HUDP.WARRIOR.HUD_SLOTS[1], 500)
    eq(s.glow, false, "W7 probe: an unknown reading renders no glow")

    -- No probe at all (the older families' shape): nil-safe, no glow.
    local bare = build()
    local BST = bare.ST
    BST.WARRIOR.post_init(BST)
    BST.warrior_overpower_proc_until = nil
    s = BST.WARRIOR.get_hud_state(BST, BST.WARRIOR.HUD_SLOTS[1], 500)
    eq(s.glow, false, "W7 probe: a client with no probe renders no glow")

    -- Scope pin: the fallback arms the Overpower slot only.
    local exec = ST.WARRIOR.HUD_SLOTS[2]
    eq(exec.key, "execute", "W7 probe: the second slot is Execute")
    s = ST.WARRIOR.get_hud_state(ST, exec, 500)
    eq(s.glow, false, "W7 probe: the fallback never arms the Execute slot")
end

--=========================================================================================
-- 30) Build-out: the Battle Shout badge - capture plumbing (rank ids, literal
--     name, the fallback shadow, later-expiring wins, absence clears) and the
--     badge draw on the nil-off default toggle
--=========================================================================================

do
    local sb = build()
    local ST = sb.ST

    -- A client-reported expiry is captured verbatim.
    sb.auras = { { name = "Battle Shout", id = 6673, duration = 120, expiration = 130 } }
    sb.clock = 10
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_battle_shout_expires, 130, "BS capture: the reported expiry is kept")
    -- A rank-table match wins over an unrelated localized name.
    sb.auras = { { name = "Amp clamor", id = 2048, duration = 120, expiration = 55 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_battle_shout_expires, 55, "BS capture: rank ids match before names")
    -- The English literal fallback (the Rampage scan's convention).
    sb.auras = { { name = "Battle Shout", id = 999999, duration = 120, expiration = 77 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_battle_shout_expires, 77, "BS capture: the literal name fallback matches")
    -- A non-matching aura never captures.
    sb.auras = { { name = "Bloodsurge", id = 46916, duration = 5, expiration = 99 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_battle_shout_expires, nil, "BS capture: an unrelated aura is ignored")
    -- A client-reported no-expiry arms the fallback shadow (now + duration).
    sb.clock = 40
    sb.auras = { { name = "Battle Shout", id = 6673, duration = 120 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_battle_shout_expires, 160, "BS capture: a missing expiry arms the shadow")
    -- The later-expiring match wins inside one walk.
    sb.auras = {
        { name = "Battle Shout", id = 6673, duration = 120, expiration = 100 },
        { name = "Battle Shout", id = 2048, duration = 120, expiration = 200 },
    }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_battle_shout_expires, 200, "BS capture: the later-expiring match wins")
    -- Absence clears.
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_battle_shout_expires, nil, "BS capture: a faded buff clears the capture")

    -- The badge draw on the nil-off default toggle.
    ST.WARRIOR.post_init(ST)
    local badge = sb.visuals.warrior_battle_shout_text
    check(badge ~= nil, "BS badge: the widget exists after setup")
    sb.clock = 100
    sb.auras = { { name = "Battle Shout", id = 6673, duration = 120, expiration = 130 } }
    ST.WARRIOR.on_aura_change(ST)
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(badge.hidden, "BS badge: the unset toggle hides the badge (nil = off)")

    sb.class_db.show_warrior_battle_shout_badge = true
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not badge.hidden, "BS badge: the toggle on shows a live buff")
    eq(badge.text, "BS 30s", "BS badge: the badge counts the reported expiry")
    local sets = badge.text_sets
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text_sets, sets, "BS badge: an unchanged readout performs no text write")
    sb.clock = 124
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text, "BS 6s", "BS badge: the countdown follows the expiry stamp")
    sb.clock = 131
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(badge.hidden, "BS badge: an elapsed window hides the badge")

    -- Combat exit does NOT clear the buff (it persists between fights).
    ST.WARRIOR.on_combat_exit(ST)
    eq(ST.warrior_battle_shout_expires, 130, "BS badge: combat exit keeps the buff state")

    -- The toggle off hides a still-live badge.
    sb.class_db.show_warrior_battle_shout_badge = false
    sb.clock = 100
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(badge.hidden, "BS badge: the toggle off hides a live badge")
end

--=========================================================================================
-- W2: Commanding Shout coverage - capture plumbing and the suppression draw on
-- the suppression toggle (nil = off, the legacy Battle Shout readout)
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST

    -- A client-reported Commanding expiry is captured verbatim (rank id path).
    sb.auras = { { name = "Commanding Shout", id = 469, duration = 120, expiration = 130 } }
    sb.clock = 10
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_commanding_expires, 130, "CMD capture: the reported expiry is kept")
    -- The literal English fallback matches when the id is unknown to the client.
    sb.auras = { { name = "Commanding Shout", id = 999999, duration = 120, expiration = 77 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_commanding_expires, 77, "CMD capture: the literal name fallback matches")
    -- An unrelated aura never captures.
    sb.auras = { { name = "Bloodsurge", id = 46916, duration = 5, expiration = 99 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_commanding_expires, nil, "CMD capture: an unrelated aura is ignored")
    -- A client-reported no-expiry arms the audit shadow (now + 120).
    sb.clock = 40
    sb.auras = { { name = "Commanding Shout", id = 469, duration = 120 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_commanding_expires, 160, "CMD capture: a missing expiry arms the shadow")
    -- The later-expiring match wins inside one walk.
    sb.auras = {
        { name = "Commanding Shout", id = 469, duration = 120, expiration = 100 },
        { name = "Commanding Shout", id = 3411, duration = 120, expiration = 200 },
    }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_commanding_expires, 200, "CMD capture: the later-expiring match wins")
    -- Battle Shout capture is independent (both buffs coexist in one walk).
    sb.auras = {
        { name = "Battle Shout", id = 6673, duration = 120, expiration = 300 },
        { name = "Commanding Shout", id = 469, duration = 120, expiration = 200 },
    }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_battle_shout_expires, 300, "W2: Battle Shout still captures alongside Commanding")
    eq(ST.warrior_commanding_expires, 200, "W2: Commanding still captures alongside Battle Shout")
    -- Absence clears.
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_commanding_expires, nil, "CMD capture: a faded buff clears the capture")

    -- The badge draw on the suppression toggle (the same widget, no new frame).
    ST.WARRIOR.post_init(ST)
    local badge = sb.visuals.warrior_battle_shout_text
    check(badge ~= nil, "W2: the badge widget exists after setup")
    sb.auras = {
        { name = "Battle Shout", id = 6673, duration = 120, expiration = 300 },
        { name = "Commanding Shout", id = 469, duration = 120, expiration = 200 },
    }
    ST.WARRIOR.on_aura_change(ST)
    sb.class_db.show_warrior_battle_shout_badge = true

    -- Legacy path: the suppression toggle unset shows Battle Shout while covered.
    sb.clock = 100
    sb.class_db.show_warrior_commanding_suppression = nil
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not badge.hidden, "W2: the unset suppression toggle shows Battle Shout (legacy)")
    eq(badge.text, "BS 200s", "W2: the legacy readout counts the Battle Shout expiry")

    -- Suppression on: the same widget shows the Commanding countdown instead.
    sb.class_db.show_warrior_commanding_suppression = true
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not badge.hidden, "W2: the suppressed badge stays visible as the CMD readout")
    eq(badge.text, "CMD 100s", "W2: the suppressed badge counts the Commanding expiry")
    local sets = badge.text_sets
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text_sets, sets, "W2: an unchanged readout performs no text write")

    -- The toggle off shows Battle Shout even while covered.
    sb.class_db.show_warrior_commanding_suppression = false
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text, "BS 200s", "W2: the toggle off shows Battle Shout while covered")

    -- An elapsed Commanding window falls back to the Battle Shout readout.
    sb.class_db.show_warrior_commanding_suppression = true
    sb.clock = 205
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(badge.text, "BS 95s", "W2: an elapsed Commanding window falls back to Battle Shout")

    -- Both windows elapsed hides the badge; combat exit keeps the stamps.
    sb.clock = 305
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(badge.hidden, "W2: elapsed windows hide the badge")
    ST.WARRIOR.on_combat_exit(ST)
    eq(ST.warrior_commanding_expires, 200, "W2: combat exit keeps the Commanding stamp")
    eq(ST.warrior_battle_shout_expires, 300, "W2: combat exit keeps the Battle Shout stamp")
end

--=========================================================================================
-- R1 (localized): a string matching the client's own rank names arms the window
--=========================================================================================
do
    local sb = build({ known = { [25286] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)

    local function cleu(subevent, ...)
        ST.WARRIOR.on_combat_log_unfiltered(ST, "COMBAT_LOG_EVENT_UNFILTERED", 100, subevent,
            false, "Player-1", "Player", 0, 0, "Target-1", "Target", 0, 0, ...)
    end

    -- The fixture's GetSpellInfo answers "Spell <id>" for known ids, so the
    -- resolved localized name for the known TBC Heroic Strike rank matches.
    sb.clock = 100
    cleu("SPELL_MISSED", "Spell 25286", "Spell 25286", 1, "DODGE")
    near(ST.warrior_overpower_proc_until, 105,
        "R1: a resolved localized rank name arms the window")
    ST.warrior_overpower_proc_until = nil
    cleu("SPELL_MISSED", "Spell 99999", "Spell 99999", 1, "DODGE")
    eq(ST.warrior_overpower_proc_until, nil,
        "R1: an unresolvable localized name never arms the window")
end

--=========================================================================================
-- R2: secret-hole aura walks (no truncation below a restricted row)
--=========================================================================================
do
    -- Target merged scan: the debuff below a secret row still draws.
    local sb = build({ known = { [772] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    local bars = sb.visuals.warrior_debuff

    sb.clock = 200
    -- Index 1 degrades to absent (secret); the player's Rend sits at index 2.
    sb.target_auras = {
        [2] = { name = "Rend", id = 772, source = "player", duration = 9, expiration = 206 },
    }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not bars.rend.bg.hidden, "R2: Rend draws below a secret row")
    near(bars.rend.fill.width, 100 * (6 / 9), "R2: the fill shows the remaining fraction")

    -- Shield Block player scan: the buff below a secret row still shows.
    local pb = build({ known = { [2565] = true } })
    local PST = pb.ST
    PST.interfaces_are_initialised = true
    PST.WARRIOR.post_init(PST)
    local bar = pb.visuals.warrior_shield_block
    pb.clock = 400
    pb.auras = {
        [2] = { name = "Shield Block", id = 2565, duration = 5, expiration = 403 },
    }
    PST.WARRIOR.on_bar_update(PST, "mainhand")
    check(not bar.bg.hidden, "R2: Shield Block shows below a secret row")
end

--=========================================================================================
-- 31) Competitor-gaps W1: the desync spark - the pure verdict is pinned in
--     warrior_guide_state.lua; here the default-off gate, the widget draw path
--     (verdict tint + OH-landing position), the unknown-hides and the churn
--     guards. No client reads exist on this path (the swing engine's own
--     stamps only); Retail stays hidden with no error.
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    eq(ST.warrior_desync_shown, false, "W1 desync: post_init starts unshown")
    eq(ST.warrior_desync_verdict, nil, "W1 desync: post_init starts with no verdict")
    local spark = sb.visuals.warrior_desync.spark
    check(spark ~= nil, "W1 desync: post_init creates the spark widget")
    check(spark.hidden, "W1 desync: the spark starts hidden")

    -- Armed dual-wield stamps: both hands land at 102.5.
    sb.clock = 100
    ST.mainhand = { speed = 2.5, ends_at = 102.5, start = 100.0 }
    ST.offhand = { speed = 2.0, ends_at = 102.5, start = 100.5, has_weapon = true }

    -- The nil-off default: fully armed, still hidden.
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(spark.hidden, "W1 desync: the unset toggle hides the spark (nil = off)")
    eq(ST.warrior_desync_shown, false, "W1 desync: the unset toggle leaves the shown flag down")
    eq(ST.warrior_desync_verdict, nil, "W1 desync: the unset toggle keeps no verdict")

    sb.class_db.show_warrior_desync_alert = false
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(spark.hidden, "W1 desync: the explicit toggle off hides the spark")

    -- Armed: coincident landings -> clash, amber, right edge.
    sb.class_db.show_warrior_desync_alert = true
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not spark.hidden, "W1 desync: coincident landings show the spark")
    eq(ST.warrior_desync_shown, true, "W1 desync: the shown flag latches")
    eq(ST.warrior_desync_verdict, "clash", "W1 desync: coincident landings read clash")
    colour_eq(spark.color, { 255, 170, 0, 0.95 }, "W1 desync: clash tints the spark amber")
    eq(spark.point_sets, 2, "W1 desync: the first show anchors twice (bottom + top)")
    eq(spark.offset, 99, "W1 desync: a right-edge landing sits at pixel 99")

    -- An unchanged tick: no re-anchor churn.
    local sets_before = spark.point_sets
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(spark.point_sets, sets_before, "W1 desync: an unchanged pixel performs no anchor writes")
    check(not spark.hidden, "W1 desync: the spark stays shown")

    -- Separated landings inside the same MH swing -> clean, green, mid-bar.
    sb.clock = 100
    ST.mainhand = { speed = 2.0, ends_at = 102.0, start = 100.0 }
    ST.offhand = { speed = 2.0, ends_at = 101.0, start = 99.0, has_weapon = true }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    eq(ST.warrior_desync_verdict, "clean", "W1 desync: a 1 s gap reads clean")
    colour_eq(spark.color, { 46, 204, 113, 1.0 }, "W1 desync: clean tints the spark green")
    eq(spark.offset, 49, "W1 desync: the mid-swing OH landing sits at pixel 49")

    -- An OH landing past the MH landing: unplaceable, hides.
    ST.offhand = { speed = 2.0, ends_at = 103.0, start = 101.0, has_weapon = true }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(spark.hidden, "W1 desync: an OH landing outside the MH swing hides the spark")
    eq(ST.warrior_desync_verdict, nil, "W1 desync: unplaceable clears the verdict")

    -- Back inside, then the offhand goes missing: hides again.
    ST.offhand = { speed = 2.0, ends_at = 101.0, start = 99.0, has_weapon = true }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not spark.hidden, "W1 desync: back inside re-arms the spark")
    ST.offhand = nil
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(spark.hidden, "W1 desync: a missing offhand table hides the spark")
    ST.offhand = { speed = 2.0, ends_at = 101.0, start = 99.0, has_weapon = false }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(spark.hidden, "W1 desync: no offhand weapon (shield) hides the spark")

    -- Non-numeric stamps: never guess.
    ST.offhand = { speed = 2.0, ends_at = nil, start = 99.0, has_weapon = true }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(spark.hidden, "W1 desync: an unknown OH stamp hides the spark")
    local nan = 0 / 0
    ST.mainhand = { speed = 2.5, ends_at = nan, start = 99.5 }
    ST.offhand = { speed = 2.0, ends_at = 101.0, start = 99.0, has_weapon = true }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(spark.hidden, "W1 desync: a NaN MH stamp hides the spark")

    -- Toggle off mid-alert: hides, clears verdict + pixel.
    ST.mainhand = { speed = 2.5, ends_at = 102.5, start = 100.0 }
    ST.offhand = { speed = 2.0, ends_at = 102.5, start = 100.5, has_weapon = true }
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(not spark.hidden, "W1 desync: re-arms before the toggle-off")
    sb.class_db.show_warrior_desync_alert = false
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(spark.hidden, "W1 desync: the toggle off hides a live spark")
    eq(ST.warrior_desync_verdict, nil, "W1 desync: the toggle off clears the verdict")
end

-- Retail profile: no swing stamps, no error, no spark.
do
    local sb = build({ project = 1 })
    local ST = sb.ST
    eq(sb.st.family, "RETAIL", "W1 desync: the sandbox profiles the Retail family")
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    sb.class_db.show_warrior_desync_alert = true
    sb.clock = 500
    local ok, err = pcall(ST.WARRIOR.on_bar_update, ST, "mainhand")
    check(ok, "W1 desync: the Retail profile draws without error (" .. tostring(err) .. ")")
    check(sb.visuals.warrior_desync.spark.hidden,
        "W1 desync: no swing data keeps the spark hidden on Retail")
end

--=========================================================================================
-- 32) Filed rules, now live (warrior-rotfix journal 2026-10-19): Sunder
-- upkeep (TBC + Forever, rule S + slots), Rend upkeep outside arms (SoD
-- rune-gated, rule R + slot; Forever toggle filed), the SoD OP stance-dance
-- (rule D + SoD op slot; gate aura UNCONFIRMED, stance map UNCONFIRMED),
-- Hamstring weave (rule W on Era-base, threshold 80 live; other families
-- filed), and the HELD Wrath/SoD floors. The rule matrix pins live in
-- tests/warrior_guide_state.lua; here the source shape, the frozen probes,
-- the gather mapping and the new slot sets. Victory Rush stays OUT
-- (operator SKIP).
--=========================================================================================
do
    -- The Rend rune lives in the source as a CONFIRMED local, the stance aura as UNCONFIRMED.
    -- The stance SPELL ids (2457/2458/71 - the sim's own stance auras, fetched
    -- 2026-10-19) are now carried too: they have a reader (the aura walk reads
    -- the client's stance buff), so wire-not-strip keeps them wired instead of
    -- filing them in the journal.
    local f = assert(io.open(ROOT .. "classes/warrior.lua", "r"))
    local source = f:read("*a")
    f:close()
    check(source:find("local sod_rend_rune_id = 412507 -- CONFIRMED (Blood Frenzy, operator in-client 2026-10-19)", 1, true) ~= nil,
        "the SoD Rend rune id is carried as CONFIRMED")
    check(source:find("local sod_stance_aura_id = 426969 -- UNCONFIRMED", 1, true) ~= nil,
        "the SoD stance-dance gate aura id is carried as UNCONFIRMED")
    check(source:find("[2457] = \"battle\"", 1, true) ~= nil,
        "the Battle stance id is carried with its key")
    check(source:find("WARRIOR_STANCES.ids[spell_id]", 1, true) ~= nil,
        "the stance ids are read by the aura walk (a reader exists, so they are wired)")

    -- Post_init freezes: the Rend-rune flag follows the spellbook, the gate
    -- aura starts absent. The rune never widens SoD detection (pinned below).
    do
        local sb = build({ project = 2, known = { [402911] = true, [412507] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_is_sod, true, "SoD: the rune pair keeps the SoD branch")
        eq(ST.warrior_has_sod_rend_rune, true, "SoD: the known Rend rune freezes on")
    end
    do
        local sb = build({ project = 2, known = { [402911] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_has_sod_rend_rune, false, "SoD: an unknown Rend rune freezes off")
        eq(ST.has_sod_stance_aura, false, "post_init starts with no gate aura")
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sod_rend_rune_known, nil, "SoD gather: an unknown rune reads nil (hidden)")
    end
    do
        -- A secret (non-true) reading never arms: the == true freeze degrades it to off/hidden.
        local sb = build({ project = 2, known = { [402911] = true, [412507] = "<secret>" } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_has_sod_rend_rune, false, "SoD: a secret Rend rune freezes off")
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sod_rend_rune_known, nil, "SoD gather: a secret rune reads nil (hidden)")
    end
    do
        -- The rune alone never flips SoD: ERA + 412507 without Raging Blow /
        -- Consumed by Rage stays Era-base (floor 40, Era slots).
        local sb = build({ project = 2, known = { [412507] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(ST.warrior_is_sod, false, "the Rend rune alone never widens SoD detection")
        eq(ST.warrior_has_sod_rend_rune, true, "the rune flag still freezes on alone")
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sod, nil, "rune-alone gather: no SoD branch flag")
        eq(inputs.hs_rage_floor, 40, "rune-alone gather: the Era 40 floor stands")
        eq(inputs.sod_rend_rune_known, true, "rune-alone gather: the rune input rides")
    end

    -- Gate-aura plumbing: id-only match (no name fallback exists), cleared
    -- when the aura fades, inert on families that never read it.
    do
        local sb = build({ project = 2, known = { [402911] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        sb.clock = 700
        sb.auras = { { name = "Some Buff", id = 426969, count = 1 } }
        ST.WARRIOR.on_aura_change(ST)
        eq(ST.has_sod_stance_aura, true, "the gate aura id arms the flag (name ignored)")
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sod_stance_aura, true, "SoD gather: the live gate aura rides")
        sb.auras = {}
        ST.WARRIOR.on_aura_change(ST)
        eq(ST.has_sod_stance_aura, false, "a faded gate aura clears the flag")
        inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sod_stance_aura, nil, "SoD gather: a faded aura reads nil")
    end

    -- TBC gather: Sunder upkeep rides (stacks + countdown), Rend stays nil
    -- (no TBC rend upkeep - Forever + SoD only), floor 40.
    do
        local sb = build({ project = 5 })
        local ST = sb.ST
        eq(sb.st.family, "TBC", "the Sunder sandbox profiles the TBC family")
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        sb.clock = 800
        sb.target_auras = {
            { name = "Sunder Armor", id = 7386, source = "player", count = 3,
                duration = 30, expiration = 806 },
        }
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sunder_stacks, 3, "TBC gather: Sunder stacks ride")
        eq(inputs.sunder_remaining, 6, "TBC gather: Sunder countdown rides")
        eq(inputs.sunder_duration, 30, "TBC gather: Sunder duration rides")
        eq(inputs.rend_remaining, nil, "TBC gather: no Rend upkeep (Forever + SoD only)")
        eq(inputs.rend_duration, nil, "TBC gather: no Rend duration either")
        eq(inputs.hs_rage_floor, 40, "TBC gather: the 40 floor stands")
        eq(inputs.stance_form, nil, "TBC gather: no stance probe reads nil")
        eq(inputs.sod_stance_aura, nil, "TBC gather: no gate aura")
        eq(inputs.sod_rend_rune_known, nil, "TBC gather: no rune flag")
    end
    do
        -- No Sunder on the target: all three read nil (unknown hides).
        local sb = build({ project = 5 })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        sb.clock = 800
        sb.target_auras = {}
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sunder_stacks, nil, "TBC gather: no Sunder stacks reads nil")
        eq(inputs.sunder_remaining, nil, "TBC gather: no Sunder countdown reads nil")
        eq(inputs.sunder_duration, nil, "TBC gather: no Sunder duration reads nil")
    end
    do
        -- A client that omits the aura duration: the 30 s reference fallback
        -- covers it (warrior_debuff_defs above), so the window still reads.
        local sb = build({ project = 5 })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        sb.clock = 800
        sb.target_auras = {
            { name = "Sunder Armor", id = 7386, source = "player", count = 2,
                duration = nil, expiration = 806 },
        }
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sunder_stacks, 2, "TBC gather: stacks ride without a duration")
        eq(inputs.sunder_remaining, 6, "TBC gather: countdown rides without a duration")
        eq(inputs.sunder_duration, 30, "TBC gather: the 30 s fallback covers it")
    end

    -- Forever gather: Sunder + Rend windows ride, floor nil (no core reader).
    do
        local sb = build({ project = 18 })
        local ST = sb.ST
        eq(sb.st.family, "FOREVER", "the upkeep sandbox profiles Forever")
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        sb.clock = 900
        sb.target_auras = {
            { name = "Sunder Armor", id = 11597, source = "player", count = 5,
                duration = 30, expiration = 920 },
            { name = "Rend", id = 11574, source = "player", count = 1,
                duration = 15, expiration = 902 },
        }
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sunder_stacks, 5, "Forever gather: capped Sunder stacks ride")
        eq(inputs.sunder_remaining, 20, "Forever gather: Sunder countdown rides")
        eq(inputs.rend_remaining, 2, "Forever gather: Rend countdown rides")
        eq(inputs.rend_duration, 15, "Forever gather: Rend duration rides")
        eq(inputs.hs_rage_floor, nil, "Forever gather: no floor (no core reader)")
        eq(inputs.sod_stance_aura, nil, "Forever gather: no SoD gate aura")
    end

    -- SoD gather: Rend window + rune + stance ride; floor 60 HELD (design
    -- decision owed, not a number to copy - warrior_guide.lua).
    do
        local sb = build({ project = 2, known = { [402911] = true, [412507] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        sb.clock = 1000
        sb.auras = { { name = "Some Buff", id = 426969, count = 1 } }
        ST.WARRIOR.on_aura_change(ST)
        sb.target_auras = {
            { name = "Rend", id = 11574, source = "player", count = 1,
                duration = 15, expiration = 1001 },
        }
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sod, true, "SoD gather: the SoD branch flag")
        eq(inputs.rend_remaining, 1, "SoD gather: Rend countdown rides")
        eq(inputs.hs_rage_floor, 60, "SoD gather: the HELD 60 pool floor")
        eq(inputs.sod_stance_aura, true, "SoD gather: the gate aura rides")
        eq(inputs.sod_rend_rune_known, true, "SoD gather: the rune rides")
        eq(inputs.sunder_stacks, nil, "SoD gather: no Sunder upkeep (TBC + Forever only)")
        eq(inputs.sunder_remaining, nil, "SoD gather: no Sunder countdown either")
    end

    -- Wrath fury gather: none of the follow-up inputs ride (family gating).
    do
        local sb = build()
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        sb.clock = 1100
        sb.auras = { { name = "Some Buff", id = 426969, count = 1 } }
        ST.WARRIOR.on_aura_change(ST)
        sb.target_auras = {
            { name = "Sunder Armor", id = 25225, source = "player", count = 5,
                duration = 30, expiration = 1120 },
        }
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.sunder_stacks, nil, "Wrath gather: Sunder stays nil (TBC + Forever only)")
        eq(inputs.rend_remaining, nil, "Wrath fury gather: Rend stays nil (arms only)")
        eq(inputs.hs_rage_floor, 50, "Wrath gather: the HELD 50 floor")
        -- Presence-only, like sudden_death/tfb: the aura rides wherever it is
        -- seen (consumption stays gated on the filed SoD rule, so no prompt).
        eq(inputs.sod_stance_aura, true, "Wrath gather: a seen aura rides (filed rule gates it)")
        eq(inputs.sod_rend_rune_known, nil, "Wrath gather: no rune flag")
    end

    -- Stance-form mapping: a real form rides, 0/nil/NaN hide (unknown hides).
    do
        local sb = build({ shapeshift_form = 2 })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.stance_form, 2, "a reported stance form rides the gather")
    end
    do
        local sb = build({ shapeshift_form = 0 })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.stance_form, nil, "form 0 (unshifted/probe missing) hides")
    end
    do
        local sb = build({ shapeshift_form = 0 / 0 })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.stance_form, nil, "a NaN form hides")
    end
end

--=========================================================================================
-- Name-vs-id rule (operator 2026-10-19; bench/lessons.md): TBC resolves by
-- NAME with the id fallback; Era resolves by id only. Family branching via
-- st.family, never version strings.
--=========================================================================================
do
    -- IsCurrentSpell: the known rank is queried by name on TBC, by id on Era;
    -- a cold TBC book falls back to ids.
    local sb = build({ project = 5, known = { [25286] = true }, current_spell = 25286 })
    local ST = sb.ST
    eq(sb.st.family, "TBC", "name-vs-id: the queue sandbox profiles TBC")
    ST.interfaces_are_initialised = true
    ST.WARRIOR.on_current_spell_cast_changed(ST, false)
    eq(ST.hs_queued, true, "name-vs-id TBC: a queued Heroic Strike is detected by name")
    local saw_name = false
    for i = 1, #sb.is_current_query_log do
        if sb.is_current_query_log[i] == "Spell 25286" then
            saw_name = true
        end
    end
    check(saw_name, "name-vs-id TBC: the known rank is queried by name")
    local cold = build({ project = 5, known = {}, current_spell = 25286 })
    cold.ST.interfaces_are_initialised = true
    cold.ST.WARRIOR.on_current_spell_cast_changed(cold.ST, false)
    eq(cold.ST.hs_queued, true, "name-vs-id TBC cold: the id fallback still detects")
    for i = 1, #cold.is_current_query_log do
        check(type(cold.is_current_query_log[i]) == "number",
            "name-vs-id TBC cold: every query falls back to an id")
    end
    local eb = build({ project = 2, known = { [25286] = true }, current_spell = 25286 })
    eb.ST.interfaces_are_initialised = true
    eb.ST.WARRIOR.on_current_spell_cast_changed(eb.ST, false)
    eq(eb.ST.hs_queued, true, "name-vs-id Era: a queued Heroic Strike is detected by id")
    for i = 1, #eb.is_current_query_log do
        check(type(eb.is_current_query_log[i]) == "number",
            "name-vs-id Era: every IsCurrentSpell query is an id")
    end
end
do
    -- Blood Surge aura: TBC matches the resolved name or the id fallback;
    -- Era matches the id only.
    local sb = build({ project = 5, known = { [46916] = true } })
    sb.real_names = { [46916] = "Blood Surge" }
    local ST = sb.ST
    eq(sb.st.family, "TBC", "name-vs-id: the proc sandbox profiles TBC")
    ST.interfaces_are_initialised = true
    sb.auras = { { name = "Blood Surge", id = 99999, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, true, "name-vs-id TBC: a resolved name arms with a wrong id")
    sb.auras = { { name = "Bogus Proc", id = 46916, count = 1 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, true, "name-vs-id TBC: the id fallback arms with a wrong name")
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.has_bloodsurge, false, "name-vs-id TBC: a missing aura clears")
    local eb = build({ project = 2, known = { [46916] = true } })
    eb.real_names = { [46916] = "Blood Surge" }
    local EST = eb.ST
    EST.interfaces_are_initialised = true
    eb.auras = { { name = "Blood Surge", id = 99999, count = 1 } }
    EST.WARRIOR.on_aura_change(EST)
    eq(EST.has_bloodsurge, false, "name-vs-id Era: a bare name never arms with a wrong id")
    eb.auras = { { name = "Bogus Proc", id = 46916, count = 1 } }
    EST.WARRIOR.on_aura_change(EST)
    eq(EST.has_bloodsurge, true, "name-vs-id Era: the id arms with a wrong name")
end
do
    -- Rage costs: the query key is the resolved name on TBC, the id on Era.
    local sb = build({ project = 5, known = { [47450] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    sb.rage_cost = { { cost = 10 } }
    sb.power = 5
    ST.WARRIOR.on_rage_update(ST)
    eq(ST.insufficient_rage, true, "name-vs-id TBC: 5 rage < 10 cost -> insufficient")
    eq(sb.last_cost_id, "Spell 47450", "name-vs-id TBC: the cost query is the name")
    local eb = build({ project = 2, known = { [47450] = true } })
    local EST = eb.ST
    EST.interfaces_are_initialised = true
    EST.hs_queued = true
    eb.rage_cost = { { cost = 10 } }
    eb.power = 5
    EST.WARRIOR.on_rage_update(EST)
    eq(EST.insufficient_rage, true, "name-vs-id Era: 5 rage < 10 cost -> insufficient")
    eq(eb.last_cost_id, 47450, "name-vs-id Era: the cost query is the id")
end

do
    -- Knowledge probes: a known id is probed by name on TBC, by id on Era.
    local qb = build({ project = 5, known = { [412507] = true } })
    qb.ST.interfaces_are_initialised = true
    qb.ST.WARRIOR.post_init(qb.ST)
    eq(qb.ST.warrior_has_sod_rend_rune, true, "name-vs-id TBC: the known rune probes true by name")
    local saw_probe_name = false
    for i = 1, #qb.known_query_log do
        if qb.known_query_log[i] == "Spell 412507" then
            saw_probe_name = true
        end
    end
    check(saw_probe_name, "name-vs-id TBC: the rune probe is the resolved name")
    local qe = build({ project = 2, known = { [412507] = true } })
    qe.ST.interfaces_are_initialised = true
    qe.ST.WARRIOR.post_init(qe.ST)
    eq(qe.ST.warrior_has_sod_rend_rune, true, "name-vs-id Era: the known rune probes true by id")
    for i = 1, #qe.known_query_log do
        check(type(qe.known_query_log[i]) == "number",
            "name-vs-id Era: every knowledge probe is an id")
    end
end

do
    -- Static wiring pins (the defects this suite must keep closed).
    local f = assert(io.open(ROOT .. "classes/warrior.lua", "r"))
    local source = f:read("*a")
    f:close()
    check(source:find("api.get_spell_query", 1, true) ~= nil,
        "name-vs-id wiring: queries go through compat's family helper")
    check(source:find('st.family == "TBC"', 1, true) ~= nil,
        "name-vs-id wiring: the family branch is st.family, never a version string")
    check(source:find("resolve_spell_name", 1, true) ~= nil,
        "name-vs-id wiring: names resolve through the client's own GetSpellInfo")
    check(source:find("aura_matches", 1, true) ~= nil,
        "name-vs-id wiring: the Blood Surge scan matches through the shared matcher")
    check(source:find("is_spell_known_query", 1, true) ~= nil,
        "name-vs-id wiring: knowledge probes go through the family query")
end

--=========================================================================================
-- 33) Filed rules, now live: the weave threshold + Rend enable mapping, the
-- new guide/HUD slot sets and the Sunder icon resolve. No options/config
-- touched (toggles ship with the options lane); Victory Rush untouched.
--=========================================================================================
do
    -- The weave threshold rides Era-base (80 live), nil everywhere else; the
    -- Rend enable rides SoD + rune, or the player's own Forever toggle (W-15).
    local function inputs_for(opts)
        local sb = build(opts)
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        return ST.WARRIOR.gather_guide_inputs(ST, {})
    end
    eq(inputs_for({ project = 2 }).hamstring_rage_threshold, 80,
        "Era-base gather: the 80-rage weave threshold rides")
    eq(inputs_for({ project = 2 }).rend_upkeep_enabled, nil,
        "Era-base gather: no Rend enable (SoD rune-gated)")
    eq(inputs_for({}).hamstring_rage_threshold, nil,
        "Wrath gather: no weave threshold")
    eq(inputs_for({}).rend_upkeep_enabled, nil,
        "Wrath gather: no Rend enable")
    eq(inputs_for({ project = 5 }).hamstring_rage_threshold, nil,
        "TBC gather: no weave threshold (number filed)")
    eq(inputs_for({ project = 5 }).rend_upkeep_enabled, nil,
        "TBC gather: no Rend enable (Forever + SoD only)")
    eq(inputs_for({ project = 2, known = { [402911] = true } }).rend_upkeep_enabled, nil,
        "SoD gather: no Rend enable without the rune")
    eq(inputs_for({ project = 18 }).hamstring_rage_threshold, nil,
        "Forever gather: no weave threshold (toggle filed)")
    eq(inputs_for({ project = 18 }).rend_upkeep_enabled, nil,
        "Forever gather: no Rend enable while the player's toggle is unset (W-15)")
    do
        local sb = build({ project = 2, known = { [402911] = true, [412507] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
        eq(inputs.rend_upkeep_enabled, true,
            "SoD+rune gather: the Rend enable rides")
        eq(inputs.hamstring_rage_threshold, nil,
            "SoD gather: no weave threshold (number filed)")
    end

    -- The Sunder icon resolves through the client's own ranks, rank-1
    -- fallback where the book lacks it (no Sunder book entry in any
    -- fixture: the id ships as the fallback, like hamstring).
    do
        local sb = build({ project = 5 })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        local slots = ST.WARRIOR.guide.slots
        eq(#slots, 15, "TBC guide: fifteen slots (the utility spine's eight rows)")
        eq(slots[7].key, "sunder", "TBC guide: the seventh slot names sunder")
        eq(slots[7].cooldown_key, "sunder", "the Sunder slot carries its cooldown_key")
        eq(slots[7].swipe_duration, 1.5, "the Sunder slot carries the GCD-length swipe fallback")
        eq(slots[7].spell_id, 7386, "TBC Sunder keeps the rank-1 fallback")
        eq(ST.WARRIOR.guide.slots[7].spell_id, 7386, "the Sunder resolve keeps the fallback")
    end
    do
        -- Forever set + HUD mirror (seven abilities plus the two trinkets).
        local sb = build({ project = 18 })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        local slots = ST.WARRIOR.guide.slots
        local expected = { "op", "execute", "slam", "hs", "cleave",
            "hamstring", "sunder" }
        eq(#slots, 13, "Forever guide: thirteen slots (the utility spine's six rows)")
        for i = 1, #expected do
            eq(slots[i].key, expected[i], "Forever guide slot " .. i .. " is " .. expected[i])
        end
        local hud = ST.WARRIOR.HUD_SLOTS
        eq(#hud, 9, "Forever HUD: seven abilities plus the two trinkets")
        local hkeys = { "op", "execute", "slam", "hs", "cleave", "hamstring",
            "sunder", "trinket1", "trinket2" }
        for i = 1, #hkeys do
            eq(hud[i].key, hkeys[i], "Forever HUD slot " .. i .. " is " .. hkeys[i])
        end
        eq(hud[7].spell, 7386, "Forever HUD: Sunder keeps the rank-1 fallback")
    end
    do
        -- Era set + HUD mirror (seven abilities plus the two trinkets).
        local sb = build({ project = 2 })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(#ST.WARRIOR.guide.slots, 13, "Era guide: thirteen slots (the utility spine's six rows)")
        eq(ST.WARRIOR.guide.slots[7].key, "hamstring",
            "Era guide: the seventh slot names hamstring")
        local hud = ST.WARRIOR.HUD_SLOTS
        eq(#hud, 9, "Era HUD: seven abilities plus the two trinkets")
        eq(hud[7].key, "hamstring", "Era HUD: the seventh slot names hamstring")
    end
    do
        -- SoD set + HUD mirror (eight abilities plus the two trinkets).
        local sb = build({ project = 2, known = { [402911] = true } })
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.WARRIOR.post_init(ST)
        eq(#ST.WARRIOR.guide.slots, 12, "SoD guide: twelve slots (the utility spine's four rows)")
        eq(ST.WARRIOR.guide.slots[7].key, "rend",
            "SoD guide: the seventh slot names rend")
        eq(ST.WARRIOR.guide.slots[8].key, "op",
            "SoD guide: the eighth slot names op")
        local hud = ST.WARRIOR.HUD_SLOTS
        eq(#hud, 10, "SoD HUD: eight abilities plus the two trinkets")
        eq(hud[7].key, "rend", "SoD HUD: the seventh slot names rend")
        eq(hud[8].key, "op", "SoD HUD: the eighth slot names op")
    end
    do
        -- Wrath fury + arms + base sets hold their frozen shapes.
        local sb = build()
        sb.ST.interfaces_are_initialised = true
        sb.ST.WARRIOR.post_init(sb.ST)
        eq(#sb.ST.WARRIOR.guide.slots, 10, "Wrath fury guide: ten slots (the utility spine's four rows)")
        local arms = build({ known = { [47486] = true } })
        arms.ST.interfaces_are_initialised = true
        arms.ST.WARRIOR.post_init(arms.ST)
        eq(#arms.ST.WARRIOR.guide.slots, 8, "Wrath arms guide: eight slots (the utility spine's two rows)")
        local cata = build({ project = 14 })
        cata.ST.interfaces_are_initialised = true
        cata.ST.WARRIOR.post_init(cata.ST)
        eq(#cata.ST.WARRIOR.guide.slots, 6, "non-core guide: six slots (unchanged)")
        eq(#cata.ST.WARRIOR.HUD_SLOTS, 8, "non-core HUD: eight slots (unchanged)")
    end
end

--=========================================================================================
-- P) Execute drill: the warrior_execute registry entry runs end-to-end (the
-- practice half routing). The harness is loaded into the sandbox exactly like
-- tests/practice_state.lua loads it (weave + nextaction first, mirroring the
-- TOC order); every pin below drives the real registry spec.
--=========================================================================================
do
    local function ensure_harness(sb)
        if sb.st.practice and sb.st.practice.harness then
            return sb.st.practice.harness
        end
        local env = setmetatable({ ST = sb.st }, { __index = _G })
        local wmod = assert(loadfile(ROOT .. "weave.lua"))
        setfenv(wmod, env)
        wmod("SwedgeTimer", sb.st)
        local nmod = assert(loadfile(ROOT .. "nextaction.lua"))
        setfenv(nmod, env)
        nmod("SwedgeTimer", sb.st)
        local pmod = assert(loadfile(ROOT .. "practice.lua"))
        setfenv(pmod, env)
        pmod("SwedgeTimer", sb.st)
        return sb.st.practice.harness
    end

    -- Registry routing: the warrior drill is registered for WARRIOR only.
    local sb = build()
    local H = ensure_harness(sb)
    check(type(H) == "table", "W6 drill: the practice harness loads into the sandbox")
    local wspecs = H.scenarios_for_class("WARRIOR")
    eq(#wspecs, 1, "W6 drill: exactly one scenario is registered for WARRIOR")
    eq(wspecs[1].key, "warrior_execute", "W6 drill: the warrior scenario is warrior_execute")
    eq(wspecs[1].kind, "execute_phase", "W6 drill: the warrior scenario kind is execute_phase")
    eq(H.get_scenario("warrior_execute").class, "WARRIOR",
        "W6 drill: the spec names the WARRIOR class")
    check(H.get_scenario("no_such_drill") == nil,
        "W6 drill: an unknown scenario key reads nil")

    -- Session run: unknown keys are rejected, HP crossings drive the flags.
    local none, err = H.new_session("no_such_drill", 0)
    check(none == nil and type(err) == "string",
        "W6 drill: a session for an unknown key is refused with an error")
    local ex = H.new_session("warrior_execute", 0)
    check(ex ~= nil, "W6 drill: the execute session builds")
    eq(H.begin_session(ex, 0), true, "W6 drill: the execute session begins")
    eq(H.execute_phase_update(ex.state, 1, 0.5), nil,
        "W6 drill: above the threshold no crossing fires")
    eq(H.execute_phase_update(ex.state, 2, 0.20), "entered",
        "W6 drill: crossing 20% enters the phase")
    eq(H.execute_phase_update(ex.state, 3, 0.10), nil,
        "W6 drill: staying inside fires nothing")
    eq(H.query(ex, "in_execute_phase", 3), true,
        "W6 drill: the query reports the phase")
    check(H.query(ex, "phase_time", 5) == 3,
        "W6 drill: the query reports the phase time")
    eq(H.execute_phase_update(ex.state, 4, 0.35), "exited",
        "W6 drill: re-crossing exits the phase")
    eq(H.query(ex, "in_execute_phase", 4), false,
        "W6 drill: the query reports the exit")
    eq(H.execute_phase_update(ex.state, 5, "x"), nil,
        "W6 drill: an unknown HP reading changes nothing")

    -- Session run through the exact-time event hook (the live feed shape).
    local ex2 = H.new_session("warrior_execute", 10)
    H.begin_session(ex2, 10)
    local eout = {}
    eq(H.scenario_event(ex2, 0.5, 11), nil,
        "W6 drill: the event above the threshold grades nothing")
    eq(H.scenario_event(ex2, 0.15, 12), "entered",
        "W6 drill: the event crossing enters the phase")
    H.tick_session(ex2, 13, 0.05, eout)
    eq(eout.execute_phase_entered, false,
        "W6 drill: the entry does not re-fire on the tick")
    eq(H.scenario_event(ex2, 0.4, 14), "exited",
        "W6 drill: the event leaving exits the phase")
    H.tick_session(ex2, 15, 0.05, eout)
    eq(eout.execute_phase_exited, false,
        "W6 drill: the exit does not re-fire on the tick")

    -- Grade: the pooled-rage bands at the entry (full = S, empty = F).
    local ex3 = H.new_session("warrior_execute", 20)
    H.begin_session(ex3, 20)
    eq(H.grade_execute_entry(ex3.state, 100), "S",
        "W6 drill: full rage at entry is S")
    eq(H.grade_execute_entry(ex3.state, 80), "A",
        "W6 drill: 80% rage at entry is A")
    eq(H.grade_execute_entry(ex3.state, 50), "B",
        "W6 drill: half rage at entry is B")
    eq(H.grade_execute_entry(ex3.state, 30), "C",
        "W6 drill: 30% rage at entry is C")
    eq(H.grade_execute_entry(ex3.state, 10), "D",
        "W6 drill: 10% rage at entry is D")
    eq(H.grade_execute_entry(ex3.state, 0), "F",
        "W6 drill: empty rage at entry is F")
    eq(H.grade_execute_entry(ex3.state, nil), nil,
        "W6 drill: a missing rage reading grades nothing")
    eq(H.grade_execute_entry(ex3.state, 120), "S",
        "W6 drill: over-target rage clamps to S")

    -- Scoring: graded attempts accumulate through the shared pipeline.
    local ex4 = H.new_session("warrior_execute", 30)
    H.begin_session(ex4, 30)
    H.record_session_attempt(ex4, H.grade_execute_entry(ex4.state, 100), nil)
    local summary = H.session_summary(ex4)
    eq(summary.attempts, 1, "W6 drill: the graded entry is recorded")
    eq(summary.best_grade, "S", "W6 drill: the best grade is kept")
    eq(H.end_session(ex4, 40), true, "W6 drill: the session ends")
end

--=========================================================================================
-- Q) Execute drill: the live feed (record/track), the session arming and the
-- Era/TBC/Forever family matrix. Anything client-unknown hides (nil-safe),
-- never throws.
--=========================================================================================
do
    -- record_execute_sample: nil-safe, log-on-first-use, harness-graded.
    local sb = build()
    local ST = sb.ST
    ST.WARRIOR.record_execute_sample(nil, 0.15, 100)
    check(ST.warrior_execute_log == nil,
        "W6 feed: a non-table owner records nothing")
    ST.WARRIOR.record_execute_sample(ST, 0.15, 100)
    check(type(ST.warrior_execute_log) == "table"
        and #ST.warrior_execute_log == 1,
        "W6 feed: the first sample creates the log")
    -- No harness is loaded in this sandbox: an unreadable grader grades nil.
    local first = ST.warrior_execute_log[1]
    eq(first.hp_fraction, 0.15, "W6 feed: the sample keeps the HP fraction")
    eq(first.rage, 100, "W6 feed: the sample keeps the rage")
    eq(first.drill, "warrior_execute_burn",
        "W6 feed: the sample names the class's own drill, not the retired built-in")
    eq(first.grade, nil, "W6 feed: no harness grades nil (never a guess)")
    eq(ST.warrior_execute_entries_total, 1,
        "W6 feed: the entry counter counts ungraded samples")
    check(ST.warrior_execute_entries_graded == nil,
        "W6 feed: the graded counter stays unset without a grade")

    -- With the real harness loaded the same sample grades through its bands.
    local H = (function()
        local env = setmetatable({ ST = sb.st }, { __index = _G })
        local wmod = assert(loadfile(ROOT .. "weave.lua"))
        setfenv(wmod, env)
        wmod("SwedgeTimer", sb.st)
        local nmod = assert(loadfile(ROOT .. "nextaction.lua"))
        setfenv(nmod, env)
        nmod("SwedgeTimer", sb.st)
        local pmod = assert(loadfile(ROOT .. "practice.lua"))
        setfenv(pmod, env)
        pmod("SwedgeTimer", sb.st)
        return sb.st.practice.harness
    end)()
    check(type(H) == "table" and type(H.grade_execute_entry) == "function",
        "W6 feed: the harness grader loads")
    ST.WARRIOR.record_execute_sample(ST, 0.15, 100)
    eq(ST.warrior_execute_log[2].grade, "S",
        "W6 feed: full rage at entry grades S through the harness")
    ST.WARRIOR.record_execute_sample(ST, 0.15, 0)
    eq(ST.warrior_execute_log[3].grade, "F",
        "W6 feed: empty rage at entry grades F through the harness")
    ST.WARRIOR.record_execute_sample(ST, 0.15, nil)
    eq(ST.warrior_execute_log[4].grade, nil,
        "W6 feed: unreadable rage grades nil (unknown hides)")
    ST.WARRIOR.record_execute_sample(ST, 0.15, 0 / 0)
    local nan_row = ST.warrior_execute_log[#ST.warrior_execute_log]
    eq(nan_row.rage, nil, "W6 feed: a NaN rage reads as unknown")
    eq(nan_row.grade, nil, "W6 feed: a NaN rage never grades")
    ST.WARRIOR.record_execute_sample(ST, 0 / 0, 80)
    local nan_hp = ST.warrior_execute_log[#ST.warrior_execute_log]
    eq(nan_hp.hp_fraction, nil, "W6 feed: a NaN HP fraction reads as unknown")
    eq(ST.warrior_execute_entries_total, 6,
        "W6 feed: the entry counter counts every sample")
    eq(ST.warrior_execute_entries_graded, 3,
        "W6 feed: the graded counter counts only graded samples")

    -- Bounded ring: the oldest samples drop first, newest wins.
    local cap = ST.WARRIOR.EXECUTE_LOG_MAX
    eq(cap, 200, "W6 feed: the log ring caps at 200 samples")
    for _ = 1, cap + 5 do
        ST.WARRIOR.record_execute_sample(ST, 0.15, 100)
    end
    eq(#ST.warrior_execute_log, cap,
        "W6 feed: the log never grows past the cap")
end

do
    -- track_execute_phase: armed by the practice session, silent otherwise.
    local sb = build()
    local ST = sb.ST
    local start_calls = sb.unit_health_calls
    ST.WARRIOR.track_execute_phase(nil)
    ST.WARRIOR.track_execute_phase(ST)
    eq(sb.unit_health_calls, start_calls,
        "W6 track: with no session the sampler performs no reads at all")
    eq(ST.warrior_execute_log, nil,
        "W6 track: with no session nothing is recorded")
    sb.st.practice_ui = { is_active = function() return false end }
    sb.health_target_cur, sb.health_target_max = 1500, 10000
    sb.power = 100
    ST.WARRIOR.track_execute_phase(ST)
    check(ST.warrior_execute_log == nil,
        "W6 track: an inactive session records nothing")

    -- The real harness grades the live samples (same loader as section P).
    local henv = setmetatable({ ST = sb.st }, { __index = _G })
    local hwmod = assert(loadfile(ROOT .. "weave.lua"))
    setfenv(hwmod, henv)
    hwmod("SwedgeTimer", sb.st)
    local hnmod = assert(loadfile(ROOT .. "nextaction.lua"))
    setfenv(hnmod, henv)
    hnmod("SwedgeTimer", sb.st)
    local hpmod = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(hpmod, henv)
    hpmod("SwedgeTimer", sb.st)
    check(type(sb.st.practice.harness.grade_execute_entry) == "function",
        "W6 track: the harness grader loads for the live feed")

    -- Unknown HP hides: a missing target max reads no sample.
    sb.st.practice_ui.is_active = function() return true end
    sb.health_target_cur, sb.health_target_max = nil, nil
    local idle_calls = sb.unit_health_calls
    ST.WARRIOR.track_execute_phase(ST)
    check(ST.warrior_execute_log == nil,
        "W6 track: an unreadable target HP records nothing")
    check(sb.unit_health_calls > idle_calls,
        "W6 track: the unknown read still probes the client once")

    -- The crossing records one sample; staying inside fires nothing.
    sb.health_target_cur, sb.health_target_max = 5000, 10000
    ST.WARRIOR.track_execute_phase(ST)
    check(ST.warrior_execute_log == nil,
        "W6 track: above the threshold nothing records")
    check(ST.warrior_execute_phase_active ~= true,
        "W6 track: above the threshold the latch stays down")
    sb.health_target_cur = 1500
    ST.WARRIOR.track_execute_phase(ST)
    eq(#ST.warrior_execute_log, 1,
        "W6 track: crossing into Execute range records one sample")
    eq(ST.warrior_execute_phase_active, true,
        "W6 track: the crossing arms the latch")
    eq(ST.warrior_execute_log[1].grade, "S",
        "W6 track: the crossing grades the pooled rage (100 = S)")
    sb.health_target_cur = 1000
    ST.WARRIOR.track_execute_phase(ST)
    eq(#ST.warrior_execute_log, 1,
        "W6 track: staying inside fires nothing")
    sb.health_target_cur = 5000
    ST.WARRIOR.track_execute_phase(ST)
    eq(#ST.warrior_execute_log, 1,
        "W6 track: leaving records nothing")
    eq(ST.warrior_execute_phase_active, false,
        "W6 track: leaving re-arms the latch")
    sb.health_target_cur = 1500
    ST.WARRIOR.track_execute_phase(ST)
    eq(#ST.warrior_execute_log, 2,
        "W6 track: re-entering records again")

    -- The guide's own threshold decides the edge (nil-safe on a bad value).
    sb.class_db.guide_execute_pct = 0 / 0
    sb.health_target_cur = 5000
    ST.WARRIOR.track_execute_phase(ST)
    sb.health_target_cur = 1500
    ST.WARRIOR.track_execute_phase(ST)
    eq(#ST.warrior_execute_log, 3,
        "W6 track: a NaN threshold falls back to 20")
    sb.class_db.guide_execute_pct = nil
end

do
    -- Session arming + Era/TBC/Forever matrix: the sampler runs un-gated on
    -- every family (no family branch exists to pin) and never throws where
    -- the client answers nothing.
    local function crossing_on(project)
        local sb = build({ project = project })
        local ST = sb.ST
        sb.st.practice_ui = { is_active = function() return true end }
        sb.health_target_cur, sb.health_target_max = 5000, 10000
        sb.power = 90
        ST.WARRIOR.track_execute_phase(ST)
        sb.health_target_cur = 1500
        ST.WARRIOR.track_execute_phase(ST)
        return sb, ST
    end
    local era_sb, era_st = crossing_on(2)
    eq(era_sb.st.family, "ERA", "W6 matrix: project 2 maps to ERA")
    eq(#era_st.warrior_execute_log, 1,
        "W6 matrix: Era crossings record")
    local tbc_sb, tbc_st = crossing_on(5)
    eq(tbc_sb.st.family, "TBC", "W6 matrix: project 5 maps to TBC")
    eq(#tbc_st.warrior_execute_log, 1,
        "W6 matrix: TBC crossings record")
    local fvr_sb, fvr_st = crossing_on(18)
    eq(fvr_sb.st.family, "FOREVER", "W6 matrix: project 18 maps to FOREVER")
    eq(#fvr_st.warrior_execute_log, 1,
        "W6 matrix: Forever crossings record")
    -- Retail answers the same reads: logging stays harmless (the report is
    -- hidden there like everywhere until opened).
    local _, ret_st = crossing_on(1)
    eq(#ret_st.warrior_execute_log, 1,
        "W6 matrix: the sampler never throws, whatever the family")
    -- Unknown everywhere: missing target + missing power still records the
    -- crossing shape with nils, never an error.
    local usb = build()
    local UST = usb.ST
    usb.st.practice_ui = { is_active = function() return true end }
    local ok, err = pcall(UST.WARRIOR.track_execute_phase, UST)
    check(ok, "W6 matrix: no target and no power never throw ("
        .. tostring(err) .. ")")
    check(UST.warrior_execute_log == nil,
        "W6 matrix: an unreadable target records nothing")
end

do
    -- post_init builds the practice session surface (both-ways start): the
    -- options toggle and /st practice route into the same st.practice_ui, and
    -- the designer practice targets hang off the built panel.
    local sb = build()
    local ST = sb.ST
    local init_calls = 0
    sb.st.practice_ui = {
        is_active = function() return false end,
        init = function() init_calls = init_calls + 1 end,
    }
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    eq(init_calls, 1,
        "W6 wiring: post_init builds the practice session surface once")
    eq(ST.warrior_execute_log, nil,
        "W6 wiring: post_init starts with no Execute log")
    eq(ST.warrior_execute_phase_active, false,
        "W6 wiring: post_init starts with the phase latch down")
    -- A flavor without the practice files stays inert (the paladin guards it
    -- the same way): the pre-existing nil-practice_ui post_init pins above
    -- already prove the guarded path never errors.
end

do
    -- on_bar_update drives the sampler on the mainhand tick: a live crossing
    -- through the real tick records, even with no visuals frame (logging needs
    -- no frame).
    local sb = build({ no_visuals = true })
    local ST = sb.ST
    sb.st.practice_ui = { is_active = function() return true end }
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    sb.health_target_cur, sb.health_target_max = 5000, 10000
    sb.power = 100
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(ST.warrior_execute_log == nil,
        "W6 drive: the real tick above the threshold records nothing")
    sb.health_target_cur = 1500
    ST.WARRIOR.on_bar_update(ST, "mainhand")
    check(type(ST.warrior_execute_log) == "table"
        and #ST.warrior_execute_log == 1,
        "W6 drive: the real tick records the crossing without visuals")
end

--=========================================================================================
-- R) Designer: every element the warrior creates is positionable in design mode
-- (the archive editmode.lua ELEMENTS shape: key/title/frame/save/reset). The
-- registry itself is generic (designmode.lua); these pins prove the warrior
-- side of each seam: the frames exist and the save paths route through the
-- owning module.
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    -- The five positionable elements and their save seams all exist. Bars ride
    -- the bar_descriptor helper (one registration per hand); the rest carry
    -- literal keys.
    local dm = read("designmode.lua")
    for _, hand in ipairs({ "mainhand", "offhand", "ranged" }) do
        check(dm:find('bar_descriptor("' .. hand .. '")', 1, true) ~= nil,
            "designer: designmode.lua registers the bar_" .. hand .. " element")
    end
    for _, key in ipairs({
        "hud", "rottext", "nag",
        "practice_panel",
    }) do
        check(dm:find('key = "' .. key .. '"', 1, true) ~= nil,
            "designer: designmode.lua registers the " .. key .. " element")
    end
    for _, key in ipairs({ "practice_rotation", "practice_timeline" }) do
        check(dm:find('practice_descriptor("' .. key .. '"', 1, true) ~= nil,
            "designer: designmode.lua registers the " .. key .. " element")
    end
    check(dm:find("pui.design_targets", 1, true) ~= nil,
        "designer: the rotation/timeline delegate to the practice module")

    -- The warrior builds every frame the descriptors ride.
    local warrior_src = read("classes/warrior.lua")
    check(warrior_src:find("st.hud.init(self)", 1, true) ~= nil,
        "designer: post_init builds the Cooldown HUD frame")
    check(warrior_src:find("st.nextaction_ui.init(self)", 1, true) ~= nil,
        "designer: post_init builds the Next Action Guide frame")
    check(warrior_src:find("st.practice_ui.init(self)", 1, true) ~= nil,
        "designer: post_init builds the practice surface (panel + targets)")
    check(warrior_src:find("st.hud.on_bar_update(self, hand)", 1, true) ~= nil,
        "designer: on_bar_update drives the HUD layout poll")
    check(warrior_src:find("st.nextaction_ui.on_bar_update(self, hand)", 1, true) ~= nil,
        "designer: on_bar_update drives the guide layout poll")

    -- The rotation label provider exists (the generic frame reads it).
    local rsb = build()
    check(type(rsb.ST.WARRIOR.get_rotation_key) == "function",
        "designer: the warrior rotation-label provider exists")

    -- The Practice page lives in the warrior options with both-ways start:
    -- the session toggle routes into st.practice_ui.toggle (the same call
    -- /st practice makes in main.lua) and the drill report routes into the
    -- warrior report toggle.
    local opts = read("option_tables.lua")
    local warrior_opts = opts:match("function ST%.class_opts_funcs%.WARRIOR%((.*)$") or ""
    for _, key in ipairs({
        "practice_toggle", "practice_weapon_speed",
        "practice_result_duration", "practice_result_text_size",
        "practice_result_color_hit", "practice_result_color_miss",
        "practice_panel_x", "practice_panel_y", "practice_reset_position",
        "warrior_execute_report",
    }) do
        check(warrior_opts:find("%f[%a_]" .. key .. "%s*=", 1) ~= nil,
            "designer: the warrior options carry " .. key)
    end
    local toggle_widget = warrior_opts:match("practice_toggle%s*=%s*{(.-)\n        }") or ""
    check(toggle_widget:find('type%s*=%s*"execute"') ~= nil,
        "designer: practice_toggle is an execute widget")
    check(toggle_widget:find("practice_ui.toggle", 1, true) ~= nil,
        "designer: practice_toggle routes into st.practice_ui.toggle")
    local report_widget = warrior_opts:match("warrior_execute_report%s*=%s*{(.-)\n        }") or ""
    check(report_widget:find('type%s*=%s*"execute"') ~= nil,
        "designer: warrior_execute_report is an execute widget")
    check(report_widget:find("toggle_warrior_execute_report", 1, true) ~= nil,
        "designer: warrior_execute_report routes into the report toggle")
end

--=========================================================================================
-- 34) Shared class order: the per-frame hook and the post_init init order (F8 + F9)
--=========================================================================================
-- The six class modules are copy-paste siblings and used to diverge on two orders:
-- the hunter ticked the HUD before the guide, and the paladin built the practice
-- surface before the HUD. The shared contract is now pinned here, per class:
--   * the per-frame class hook ticks the guide BEFORE the HUD;
--   * post_init builds the guide, then the HUD, then the practice surface.
-- Both the runtime order (spies record the calls) and the source order (the call
-- sites) are pinned, so a reordering in either place fails this suite.
do
    local fh = assert(io.open(ROOT .. "classes/warrior.lua", "r"))
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
    local ok_init, err_init = pcall(T.WARRIOR.post_init, T)
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
    local ok_tick, err_tick = pcall(T.WARRIOR.on_bar_update, T, "mainhand")
    check(ok_tick, "order: the class hook runs with the order spies (" .. tostring(err_tick) .. ")")
    eq(tick_order[1], "guide", "order: the guide ticks before the HUD")
    eq(tick_order[2], "hud", "order: the HUD ticks after the guide")
    eq(#tick_order, 2, "order: the class hook ticks the guide and the HUD once each")

    sbox.st.nextaction_ui = saved.nextaction_ui
    sbox.st.hud = saved.hud
    sbox.st.practice_ui = saved.practice_ui

end

--=========================================================================================
-- 35) Audit F4 (class side): the rank latch tells "absent" from "unresolved"
--     The resolver's verdict is three-valued (bench/f4_family_spell_id_2026-10-19.md):
--     a client that refutes every candidate is FINAL (the negative latches), a client
--     that cannot answer is RETRYABLE (nothing latches, the next attempt asks again).
--     Both resolution directions are pinned too: the TBC client resolves by NAME, the
--     Era client by ID.
--=========================================================================================
do
    -- (a) ABSENT: the client refutes every Heroic Strike rank. The negative is FINAL -
    --     it latches and the table is never walked again, not even after the retry
    --     window.
    local ab = build({ known = {} })
    local ABT = ab.ST
    ABT.interfaces_are_initialised = true
    ABT.hs_queued = true
    ab.rage_cost = { { cost = 10 } }
    ABT.WARRIOR.on_rage_update(ABT)
    eq(ab.get_family_spell_id_state_calls, 1, "F4 absent: the client is asked once")
    eq(ab.cost_queries, 0, "F4 absent: a refuted rank reads no rage cost")
    ab.clock = 6
    ABT.WARRIOR.on_rage_update(ABT)
    eq(ab.get_family_spell_id_state_calls, 1, "F4 absent: the negative is final (never re-walked)")

    -- (b) UNRESOLVED: the client cannot answer (its GetSpellInfo raises). Nothing is
    --     latched, so the next attempt asks again once the retry backoff has passed -
    --     a cold spell book can no longer poison the rank for the rest of the session.
    local us = build({ known = {} })
    local UST = us.ST
    UST.interfaces_are_initialised = true
    UST.hs_queued = true
    us.rage_cost = { { cost = 10 } }
    us.spell_info_throws = true
    UST.WARRIOR.on_rage_update(UST)
    eq(us.get_family_spell_id_state_calls, 1, "F4 unresolved: the client is asked once")
    eq(us.cost_queries, 0, "F4 unresolved: an unanswered rank reads no rage cost")
    -- Still silent: the retry backoff holds the walk (no hot loop per bar frame).
    UST.WARRIOR.on_rage_update(UST)
    eq(us.get_family_spell_id_state_calls, 1, "F4 unresolved: the retry backoff holds the walk")
    -- The client answers again after the backoff: the rank resolves and latches.
    us.spell_info_throws = false
    us.known[47450] = true
    us.clock = 6
    UST.WARRIOR.on_rage_update(UST)
    eq(us.get_family_spell_id_state_calls, 2, "F4 unresolved: the attempt after the backoff asks again")
    eq(us.cost_queries, 1, "F4 unresolved: the resolved rank reaches the cost query")
    eq(us.last_cost_id, 47450, "F4 unresolved: the cost reads the rank the client confirmed")
    -- The resolved rank latches: no further walk.
    UST.WARRIOR.on_rage_update(UST)
    eq(us.get_family_spell_id_state_calls, 2, "F4 unresolved: the resolved rank latches")

    -- (c) ERA: the rank resolves by ID - the client is never asked by name.
    local era = build({ project = 2, known = { [47450] = true } })
    local ERT = era.ST
    ERT.interfaces_are_initialised = true
    era.spell_queries = {}
    ERT.WARRIOR.resolve_guide_icons()
    eq(ERT.WARRIOR.guide.slots[4].spell_id, 47450, "F4 Era: the rank resolves by ID and latches")
    local era_asked_by_name = false
    for i = 1, #era.spell_queries do
        if type(era.spell_queries[i]) == "string" then era_asked_by_name = true end
    end
    check(not era_asked_by_name, "F4 Era: the client is never asked by name")

    -- (d) TBC: a client that answers NO id resolves the rank through the NAME path
    --     (the operator rule: the TBC client indexes names, never bare ids).
    local tbc = build({ project = 5, name_only_client = true, known = { [47450] = true } })
    local TBT = tbc.ST
    TBT.interfaces_are_initialised = true
    eq(tbc.st.api.GetSpellInfo(47450), nil, "F4 TBC: the name-only client answers no id")
    TBT.WARRIOR.resolve_guide_icons()
    eq(TBT.WARRIOR.guide.slots[4].spell_id, 47450,
        "F4 TBC: the rank resolves through the NAME path (the client answers no id)")
    local tbc_asked_by_name = false
    for i = 1, #tbc.spell_queries do
        if type(tbc.spell_queries[i]) == "string" then tbc_asked_by_name = true end
    end
    check(tbc_asked_by_name, "F4 TBC: the client is asked by NAME")
end

--=========================================================================================
-- 36) Audit F4 (plain-resolver callers): the Slam cast bar's fallback duration
--     resolves the rank through the cached, three-valued resolver
--     A per-cast caller must not walk the rank table on every cast, and a client that
--     cannot answer ("unresolved") must not be mistaken for a client that refutes the
--     spell ("absent"): the first cast resolves the rank, every later cast reads the
--     cache, and a client that answers late is asked again after the retry backoff.
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

    -- One Slam cast with no live window: the fallback duration path runs.
    local function slam_cast(sb, ST, spell_id)
        sb.cast_live = nil
        ST.WARRIOR.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-1", spell_id)
        return ST.warrior_slam_cast_duration
    end

    -- (a) The class resolves through the state API, never through the plain resolver,
    --     and a Slam cast never walks the rank table twice.
    local sb = build({ known = { [1464] = true }, cast_ms = 2000 })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    near(slam_cast(sb, ST, 1464), 2.0,
        "F4 slam: the first cast resolves the rank and reads its cast time")
    eq(sb.get_family_spell_id_state_calls, 1, "F4 slam: the client is asked once")
    eq(sb.get_family_spell_id_calls, 0,
        "F4 slam: the class never uses the plain resolver")
    near(slam_cast(sb, ST, 1464), 2.0,
        "F4 slam: a later cast reads the cached rank (same duration)")
    eq(sb.get_family_spell_id_state_calls, 1,
        "F4 slam: a later cast does not walk the rank table again")

    -- (b) ABSENT: the client refutes every Slam rank. The negative is FINAL - the
    --     table is never walked again, not even after the retry window.
    local ab = build({ known = {} })
    local ABT = ab.ST
    ABT.interfaces_are_initialised = true
    near(slam_cast(ab, ABT, 1464), 1.5,
        "F4 slam absent: a refuted rank falls back to the reference's 1.5 s")
    eq(ab.get_family_spell_id_state_calls, 1, "F4 slam absent: the client is asked once")
    ab.clock = 6
    near(slam_cast(ab, ABT, 1464), 1.5, "F4 slam absent: the fallback is unchanged")
    eq(ab.get_family_spell_id_state_calls, 1,
        "F4 slam absent: the negative is final (never re-walked)")

    -- (c) UNRESOLVED: the client cannot answer (its GetSpellInfo raises). Nothing is
    --     latched, so the next cast asks again once the retry backoff has passed - a
    --     cold spell book can no longer poison the cast time for the whole session.
    local us = build({ known = {}, cast_ms = 2000 })
    local UST = us.ST
    UST.interfaces_are_initialised = true
    us.spell_info_throws = true
    near(slam_cast(us, UST, 1464), 1.5,
        "F4 slam unresolved: an unanswered rank falls back to the reference's 1.5 s")
    eq(us.get_family_spell_id_state_calls, 1,
        "F4 slam unresolved: the client is asked once")
    -- The backoff holds the walk: a cast inside the window asks nothing more.
    near(slam_cast(us, UST, 1464), 1.5, "F4 slam unresolved: the fallback is unchanged")
    eq(us.get_family_spell_id_state_calls, 1,
        "F4 slam unresolved: the retry backoff holds the walk")
    -- The client answers after the backoff: the rank resolves and reaches the
    -- cast-time read.
    us.spell_info_throws = false
    us.known[1464] = true
    us.clock = 6
    near(slam_cast(us, UST, 1464), 2.0,
        "F4 slam unresolved: the late answer reaches the cast-time read")
    eq(us.get_family_spell_id_state_calls, 2,
        "F4 slam unresolved: the attempt after the backoff asks again")

    -- (d) ERA: the rank resolves by ID - the client is never asked by name.
    local era = build({ project = 2, known = { [1464] = true }, cast_ms = 2000 })
    local ERT = era.ST
    ERT.interfaces_are_initialised = true
    era.spell_queries = {}
    near(slam_cast(era, ERT, 1464), 2.0, "F4 slam Era: the rank resolves by ID")
    local era_asked_by_name = false
    for i = 1, #era.spell_queries do
        if type(era.spell_queries[i]) == "string" then
            era_asked_by_name = true
        end
    end
    check(not era_asked_by_name, "F4 slam Era: the client is never asked by name")

    -- (e) TBC: the rank resolves through the NAME path (the operator rule: the TBC
    --     client indexes names, never bare ids). The guide slot carries the rank the
    --     name path resolved, and the client was asked by NAME.
    local tbc = build({ project = 5, name_only_client = true, known = { [11604] = true } })
    local TBT = tbc.ST
    TBT.interfaces_are_initialised = true
    tbc.spell_queries = {}
    TBT.WARRIOR.resolve_guide_icons()
    eq(slot_by_key(TBT.WARRIOR.guide.slots, "slam").spell_id, 11604,
        "F4 slam TBC: the rank resolves through the NAME path (the client answers no id)")
    local tbc_asked_by_name = false
    for i = 1, #tbc.spell_queries do
        if type(tbc.spell_queries[i]) == "string" then
            tbc_asked_by_name = true
        end
    end
    check(tbc_asked_by_name, "F4 slam TBC: the client is asked by NAME")
end

--=========================================================================================
-- 33) The stance read + the stance gates (the sims' own stance registration:
-- wowsims/classic sim/warrior/stances.go - Battle 2457, Defensive 71, Berserker
-- 2458; fetched 2026-10-19). The stance comes from the client's own stance
-- aura in the existing walk, never from the form index (that map stays
-- UNCONFIRMED). An unknown stance withholds nothing.
--=========================================================================================
do
    local sb = build({ project = 2 })
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    -- The walk reads the stance: the id first, the label as the fallback.
    sb.auras = { { name = "Battle Stance", id = 2457 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_stance, "battle", "stance: the Battle stance aura (2457) reads as battle")
    sb.auras = { { name = "Berserker Stance", id = 2458 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_stance, "berserker", "stance: the Berserker stance aura (2458) reads as berserker")
    sb.auras = { { name = "Defensive Stance", id = 71 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_stance, "defensive", "stance: the Defensive stance aura (71) reads as defensive")
    -- The name fallback (a client that reports another id for the stance buff).
    sb.auras = { { name = "Battle Stance", id = 99999 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_stance, "battle", "stance: the stance label answers when the id does not")
    -- No stance aura (or a stance with no cited id): unknown, and unknown hides.
    sb.auras = { { name = "Rampage", id = 29838 } }
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_stance, nil, "stance: no stance aura reads as unknown")
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    eq(ST.warrior_stance, nil, "stance: an empty aura list reads as unknown")
end

do
    -- The gather feeds the stance on the families whose sims gate the casts
    -- (ERA incl. SoD, TBC) and nowhere else.
    local era = build({ project = 2 })
    local ERT = era.ST
    ERT.interfaces_are_initialised = true
    era.auras = { { name = "Berserker Stance", id = 2458 } }
    ERT.WARRIOR.on_aura_change(ERT)
    local inputs = ERT.WARRIOR.gather_guide_inputs(ERT, {})
    eq(inputs.stance, "berserker", "stance: the Era gather feeds the stance")

    local tbc = build({ project = 5 })
    local TBT = tbc.ST
    TBT.interfaces_are_initialised = true
    tbc.auras = { { name = "Battle Stance", id = 2457 } }
    TBT.WARRIOR.on_aura_change(TBT)
    inputs = TBT.WARRIOR.gather_guide_inputs(TBT, {})
    eq(inputs.stance, "battle", "stance: the TBC gather feeds the stance")

    local wrath = build({ project = 11 })
    local WRT = wrath.ST
    WRT.interfaces_are_initialised = true
    wrath.auras = { { name = "Battle Stance", id = 2457 } }
    WRT.WARRIOR.on_aura_change(WRT)
    inputs = WRT.WARRIOR.gather_guide_inputs(WRT, {})
    eq(inputs.stance, nil, "stance: the Wrath gather feeds no stance (no Wrath sim line)")
end

--=========================================================================================
-- 34) The practice surface: the rotation table, the scenario step and the
-- warrior's OWN drills (the audited target set,
-- bench/class_features_drills_2026-10-19.md section 2.2 (C)/(D)). The shared
-- engine owns the registration - the class only exposes the three surfaces
-- the orchestrator's contract names.
--=========================================================================================
do
    local function load_guide(sb)
        if sb.st.warrior_guide then
            return sb.st.warrior_guide
        end
        local env = setmetatable({ ST = sb.st }, { __index = _G })
        local gmod = assert(loadfile(ROOT .. "warrior_guide.lua"))
        setfenv(gmod, env)
        gmod("SwedgeTimer", sb.st)
        return sb.st.warrior_guide
    end
    local function load_practice(sb)
        if sb.st.practice and sb.st.practice.harness then
            return sb.st.practice
        end
        local env = setmetatable({ ST = sb.st }, { __index = _G })
        for _, mod in ipairs({ "weave.lua", "nextaction.lua", "practice.lua" }) do
            local chunk = assert(loadfile(ROOT .. mod))
            setfenv(chunk, env)
            chunk("SwedgeTimer", sb.st)
        end
        return sb.st.practice
    end

    local sb = build({ project = 2 })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    load_guide(sb)
    local pr = load_practice(sb)

    -- (a) The rotation table: the engine's compiled order, every line cited.
    local rot = ST.WARRIOR.practice_rotation
    check(type(rot) == "table", "practice: the rotation table is exposed")
    local order = {}
    for i = 1, #rot do
        order[#order + 1] = rot[i].action
        check(type(rot[i].source) == "string" and #rot[i].source > 20,
            "practice: the rotation entry " .. tostring(rot[i].action) .. " cites its sim source")
        check(type(rot[i].reason) == "string" and #rot[i].reason > 0,
            "practice: the rotation entry " .. tostring(rot[i].action) .. " carries a reason")
    end
    eq(table.concat(order, ","),
        "op,execute,slam,sunder,rend,bt,ww,raging_blow,bladestorm,ms,hamstring,hs,cleave,"
            .. "battle_stance,berserker_stance,gladiator_stance,bloodrage,battle_shout,"
            .. "recklessness,death_wish,sweeping_strikes,thunder_clap,shattering_throw,"
            .. "heroic_throw,berserker_rage,blood_fury",
        "practice: the rotation table is the engine's compiled rule order then the "
            .. "APL's utility spine (section 38 pins the second block)")
    local cites = table.concat((function()
        local parts = {}
        for i = 1, #rot do parts[i] = rot[i].source end
        return parts
    end)(), " ")
    check(cites:find("wowsims/classic sim/warrior/bloodthirst.go", 1, true) ~= nil,
        "practice: the Bloodthirst line cites the sim spell file")
    check(cites:find("tbc%-new ui/specs/warrior/dps/apls/fury.apl.json") ~= nil
        or cites:find("tbc-new fury APL", 1, true) ~= nil,
        "practice: the rotation cites the TBC fury APL")

    -- (b) The scenario step: the engine's pick, or nil when it has none.
    local step = ST.WARRIOR.practice_scenario_step(ST, {
        now = 0,
        last_action = "op",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            overpower_remaining = 5, swing_remaining = 2 },
        cooldowns = { op = 0 },
    })
    check(type(step) == "table", "practice: the scenario step answers a table")
    eq(step and step.action, "op", "practice: the scenario step names the engine's pick")
    eq(step and step.reason, "Overpower window (dodge proc)",
        "practice: the scenario step carries the reason")
    -- A guide HOLD is a DECISION now (HU-8): the step states it explicitly, so
    -- the engine can grade a cast during it as an illegal cast and an idle tick
    -- as correct (no attempt). The three states are pinned in section 37.
    local hold = ST.WARRIOR.practice_scenario_step(ST, {
        now = 0,
        last_action = "hs",
        resources = { rage = 10, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            swing_remaining = 2 },
        cooldowns = {},
    })
    check(type(hold) == "table" and hold.hold == true,
        "practice: a HOLD verdict states an explicit hold")
    eq(hold.action, nil, "practice: the hold statement names no action")
    eq(hold.reason, "HOLD", "practice: the hold carries the guide's own caption")
    eq(ST.WARRIOR.practice_scenario_step(ST, nil), nil,
        "practice: no context answers nil")

    -- (c) The warrior's own drills: the audited keys, in order, each with a
    -- label and a grade function.
    local drills = ST.WARRIOR.practice_drills
    check(type(drills) == "table", "practice: the drill list is exposed")
    eq(#drills, 6, "practice: the warrior owns six drills (the pre-pull opener included)")
    local keys = {}
    for i = 1, #drills do
        keys[#keys + 1] = drills[i].key
        check(type(drills[i].label) == "string" and #drills[i].label > 0,
            "practice: the drill " .. tostring(drills[i].key) .. " carries a label")
        check(type(drills[i].grade) == "function",
            "practice: the drill " .. tostring(drills[i].key) .. " carries a grade function")
    end
    eq(table.concat(keys, ","),
        "warrior_core_order,warrior_ww_delay,warrior_sunder_upkeep,warrior_execute_burn,warrior_hs_queue,warrior_prepull",
        "practice: the drill keys are the audited ones plus the queue window and the opener")
    local drill = {}
    for i = 1, #drills do drill[drills[i].key] = drills[i] end

    -- The class names the drill that owns the execute-phase skill: the retired
    -- built-in ("warrior_execute") stays registered for backward compatibility and
    -- the engine's supersession map points at the class's own drill, so the class's
    -- session never runs the built-in.
    eq(ST.WARRIOR.practice_drill_key(), "warrior_execute_burn",
        "practice: the class names the drill that owns the execute phase")
    local H = pr.harness
    check(H.get_scenario("warrior_execute") ~= nil,
        "practice: the retired built-in stays registered")
    eq(H.SUPERSEDED_DRILLS.warrior_execute, "warrior_execute_burn",
        "practice: the built-in drill names the class drill that owns the skill")
    local wsrc = (function()
        local f = assert(io.open(ROOT .. "classes/warrior.lua", "r"))
        local text = f:read("*a")
        f:close()
        return text
    end)()
    check(wsrc:find('new_session("warrior_execute"', 1, true) == nil,
        "practice: the class module never starts the retired built-in")

    -- D-W1: the core rotation.
    local core = drill["warrior_core_order"].grade
    eq(core(ST, {
        now = 0, last_action = "op",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            overpower_remaining = 5, swing_remaining = 2 },
        cooldowns = { op = 0 },
    }), "S", "D-W1: the engine's own pick is an S")
    eq(core(ST, {
        now = 0, last_action = "hs",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            overpower_remaining = 5, swing_remaining = 2 },
        cooldowns = { op = 0 },
    }), "D", "D-W1: a mis-pick is a D")
    eq(core(ST, {
        now = 0, last_action = "hs",
        resources = { rage = 40, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            swing_remaining = 2, sunder_stacks = 2, sunder_remaining = 30 },
        cooldowns = { bt = 1 },
    }), "F", "D-W1: a spend that starved a core inside the reserve window is an F")
    eq(core(ST, {
        now = 0, last_action = nil,
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            overpower_remaining = 5, swing_remaining = 2 },
        cooldowns = { op = 0 },
    }), nil, "D-W1: no press answers nil (unknown, never a wrong action)")

    -- D-W2: the core window (the sim's Delay Check).
    local ww = drill["warrior_ww_delay"].grade
    eq(ww(ST, {
        now = 0, last_action = "ww",
        resources = { rage = 50 }, cooldowns = { bt = 3.0 },
    }), "S", "D-W2: a Whirlwind press 1.5 s clear of Bloodthirst is an S")
    eq(ww(ST, {
        now = 0, last_action = "ww",
        resources = { rage = 50 }, cooldowns = { bt = 2.0 },
    }), "A", "D-W2: a half-second of clearance is an A")
    eq(ww(ST, {
        now = 0, last_action = "ww",
        resources = { rage = 50 }, cooldowns = { bt = 1.0 },
    }), "D", "D-W2: a press inside the Delay Check window is a D")
    eq(ww(ST, {
        now = 0, last_action = "ww",
        resources = { rage = 50 }, cooldowns = { bt = 0 },
    }), "F", "D-W2: a press that took a ready Bloodthirst's GCD is an F")
    eq(ww(ST, {
        now = 0, last_action = "ww",
        resources = { rage = 10 }, cooldowns = { bt = 3.0 },
    }), "F", "D-W2: a press with no rage for either core is an F")
    eq(ww(ST, {
        now = 0, last_action = "bt",
        resources = { rage = 50 }, cooldowns = { bt = 3.0 },
    }), nil, "D-W2: a non-Whirlwind press is not this drill's decision")
    eq(ww(ST, {
        now = 0, last_action = "ww",
        resources = { rage = 50 }, cooldowns = {},
    }), nil, "D-W2: an unknown Bloodthirst reading answers nil")

    -- D-W3: the debuff upkeep.
    local sunder = drill["warrior_sunder_upkeep"].grade
    eq(sunder(ST, {
        now = 0, last_action = "sunder",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            swing_remaining = 2, sunder_stacks = 4, sunder_remaining = 30 },
        cooldowns = {},
    }), "S", "D-W3: a re-stack that leaves five stacks is an S")
    eq(sunder(ST, {
        now = 0, last_action = "sunder",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            swing_remaining = 2, sunder_stacks = 2, sunder_remaining = 30 },
        cooldowns = {},
    }), "B", "D-W3: a re-stack that leaves three stacks is a B")
    eq(sunder(ST, {
        now = 0, last_action = "hs",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            swing_remaining = 2, sunder_stacks = 2, sunder_remaining = 30 },
        cooldowns = {},
    }), "F", "D-W3: a dropped upkeep is an F (the debuff runs out)")
    eq(sunder(ST, {
        now = 0, last_action = "sunder",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            overpower_remaining = 5, swing_remaining = 2, sunder_stacks = 2,
            sunder_remaining = 30 },
        cooldowns = { op = 0 },
    }), "F", "D-W3: a press the rotation should have yielded is an F")
    eq(sunder(ST, {
        now = 0, last_action = "sunder",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            swing_remaining = 2, sunder_remaining = 5 },
        cooldowns = {},
    }), nil, "D-W3: an unknown stack count answers nil")

    -- D-W4: the execute burn.
    local burn = drill["warrior_execute_burn"].grade
    eq(burn(ST, {
        now = 0, last_action = "execute",
        resources = { rage = 100, hs_cost = 15, target_health_pct = 10, execute_pct = 20,
            swing_remaining = 2 },
        cooldowns = { execute = 0 },
    }), "S", "D-W4: a full-pool burn is an S")
    eq(burn(ST, {
        now = 0, last_action = "execute",
        resources = { rage = 60, hs_cost = 15, target_health_pct = 10, execute_pct = 20,
            swing_remaining = 2 },
        cooldowns = { execute = 0 },
    }), "C", "D-W4: a short-pool burn is a C")
    eq(burn(ST, {
        now = 3, last_action = "execute",
        resources = { rage = 100, hs_cost = 15, target_health_pct = 10, execute_pct = 20,
            swing_remaining = 2, phase_started_at = 0 },
        cooldowns = { execute = 0 },
    }), "A", "D-W4: a full-pool burn two GCDs late is an A")
    eq(burn(ST, {
        now = 0, last_action = "bt",
        resources = { rage = 100, hs_cost = 15, target_health_pct = 10, execute_pct = 20,
            swing_remaining = 2, execute_spam = true },
        cooldowns = { execute = 0, bt = 0 },
    }), "F", "D-W4: the core spent during the phase is an F (no burn)")
    eq(burn(ST, {
        now = 0, last_action = "execute",
        resources = { rage = 100, hs_cost = 15, target_health_pct = 10, execute_pct = 20,
            swing_remaining = 2 },
        cooldowns = { execute = 0, bt = 0 },
    }), nil, "D-W4: with the core holding the GCD the drill has no decision")
    eq(burn(ST, {
        now = 0, last_action = "execute",
        resources = { rage = 100, hs_cost = 15, target_health_pct = 50, execute_pct = 20,
            swing_remaining = 2 },
        cooldowns = { execute = 0 },
    }), "F", "D-W4: Execute above the threshold is an F")
    eq(burn(ST, {
        now = 0, last_action = "hs",
        resources = { rage = 100, hs_cost = 15, target_health_pct = 50, execute_pct = 20,
            swing_remaining = 2 },
        cooldowns = { execute = 0 },
    }), nil, "D-W4: outside the phase the drill has no decision")
    eq(burn(ST, {
        now = 0, last_action = "execute",
        resources = { rage = 100, hs_cost = 15, execute_pct = 20, swing_remaining = 2 },
        cooldowns = { execute = 0 },
    }), nil, "D-W4: an unknown target health answers nil")

    -- D-W5: the Heroic Strike / Cleave queue window (the operator's offhand
    -- drill). The offhand's next swing has to land inside the queued ability:
    -- the press window is the gap between the mainhand's last swing and the
    -- offhand's next one. The margin is the room on the tighter side.
    local queue = drill["warrior_hs_queue"].grade
    local function queue_ctx(press, speed, swing, offhand, dual)
        return {
            now = 0, last_action = press,
            resources = { dual_wielding = dual, speed = speed,
                swing_remaining = swing, offhand_swing_remaining = offhand },
        }
    end
    eq(queue(ST, queue_ctx("hs", 2.6, 2.1, 0.8, true)), "S",
        "D-W5: a press with room on both sides is an S")
    eq(queue(ST, queue_ctx("hs", 2.6, 2.3, 0.8, true)), "S",
        "D-W5: a 300 ms margin on the tighter side is an S")
    eq(queue(ST, queue_ctx("cleave", 2.6, 2.2, 0.2, true)), "A",
        "D-W5: a press with 200 ms on the tighter side is an A")
    eq(queue(ST, queue_ctx("hs", 2.6, 2.5, 0.12, true)), "B",
        "D-W5: a press with 100 ms on the tighter side is a B")
    eq(queue(ST, queue_ctx("hs", 2.6, 2.5, 0.05, true)), "C",
        "D-W5: a press with 50 ms on the tighter side is a C")
    eq(queue(ST, queue_ctx("hs", 2.6, 2.595, 0.5, true)), "D",
        "D-W5: a press a hair from an edge is a D")
    eq(queue(ST, queue_ctx("hs", 2.6, 1.0, 1.5, true)), "F",
        "D-W5: the offhand landing after the ability fires is an F")
    eq(queue(ST, queue_ctx("hs", 2.6, 1.0, 1.0, true)), "F",
        "D-W5: a coincident offhand landing is an F (the window is empty)")
    eq(queue(ST, queue_ctx("hs", 2.6, 0.5, 2.4, true)), "F",
        "D-W5: a press after the offhand already swung is an F")
    eq(queue(ST, queue_ctx("hs", 2.6, 2.1, 0.8, false)), nil,
        "D-W5: a one-armed warrior has no offhand swing to catch (nil)")
    eq(queue(ST, queue_ctx("bt", 2.6, 2.1, 0.8, true)), nil,
        "D-W5: a non-HS/Cleave press is not this drill's decision")
    eq(queue(ST, {
        now = 0, last_action = "hs",
        resources = { dual_wielding = true, speed = 2.6, swing_remaining = 2.1 },
    }), nil, "D-W5: an unknown offhand landing answers nil")
    eq(queue(ST, {
        now = 0, last_action = "hs",
        resources = { dual_wielding = true, speed = 0, swing_remaining = 2.1,
            offhand_swing_remaining = 0.8 },
    }), nil, "D-W5: an unknown weapon speed answers nil")
    eq(queue(ST, nil), nil, "D-W5: no context answers nil")

    -- (d) The shared model is the one the drills read for the rage state.
    check(pr ~= nil and pr.harness ~= nil, "practice: the shared model loads into the sandbox")
    check(pr.rage_can_spend ~= nil and pr.new_rage_state ~= nil,
        "practice: the shared rage model is available to the drills")
end

--=========================================================================================
-- 34) The queue drill's own inputs: the gather's offhand swing readings (the
-- addon's own swing data, where the sim is silent) and the Forever Rend
-- toggle read (W-15: the provider carries the key the options pass shipped).
--=========================================================================================
do
    -- (a) The offhand swing cycle.
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    sb.clock = 100
    ST.mainhand = { speed = 2.6, ends_at = 102.6, start = 100.0 }
    ST.offhand = { speed = 2.6, ends_at = 101.3, start = 98.7, has_weapon = true }
    local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
    near(inputs.offhand_swing_remaining, 1.3, 1e-9,
        "gather: the offhand's next landing rides")
    near(inputs.offhand_swing_speed, 2.6, 1e-9,
        "gather: the offhand's weapon speed rides")
    eq(inputs.dual_wielding, true, "gather: the two-weapons flag rides")
    near(inputs.speed, 2.6, 1e-9, "gather: the mainhand's weapon speed rides")

    -- No offhand weapon (a shield, or one hand only): the readings stay nil and
    -- the queue drill has no decision to grade (unknown hides).
    ST.offhand = { speed = 2.6, ends_at = 101.3, start = 98.7, has_weapon = false }
    inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
    eq(inputs.offhand_swing_remaining, nil,
        "gather: no offhand weapon, no offhand landing")
    eq(inputs.offhand_swing_speed, nil,
        "gather: no offhand weapon, no offhand speed")
    eq(inputs.dual_wielding, nil, "gather: no offhand weapon, no two-weapons flag")
    ST.offhand = nil
    inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
    eq(inputs.offhand_swing_remaining, nil,
        "gather: a missing offhand table reads as no offhand")
    eq(inputs.dual_wielding, nil,
        "gather: a missing offhand table reads as not dual wielding")

    -- (b) W-15: the Forever Rend toggle reaches the rule (nil = off).
    local fsb = build({ project = 18 })
    local FST = fsb.ST
    FST.interfaces_are_initialised = true
    FST.WARRIOR.post_init(FST)
    eq(FST.WARRIOR.gather_guide_inputs(FST, {}).rend_upkeep_enabled, nil,
        "W-15: the Forever gather feeds nil while the toggle is unset")
    fsb.class_db.guide_forever_rend_upkeep = true
    eq(FST.WARRIOR.gather_guide_inputs(FST, {}).rend_upkeep_enabled, true,
        "W-15: the Forever toggle (== true) arms the Rend upkeep")
    fsb.class_db.guide_forever_rend_upkeep = false
    eq(FST.WARRIOR.gather_guide_inputs(FST, {}).rend_upkeep_enabled, nil,
        "W-15: an explicit false leaves the Forever Rend rule dormant")
    fsb.class_db.guide_forever_rend_upkeep = nil

    -- The toggle is Forever-only: it never arms the rule on another family.
    local tsb = build({ project = 5 })
    local TST = tsb.ST
    TST.interfaces_are_initialised = true
    TST.WARRIOR.post_init(TST)
    tsb.class_db.guide_forever_rend_upkeep = true
    eq(TST.WARRIOR.gather_guide_inputs(TST, {}).rend_upkeep_enabled, nil,
        "W-15: the Forever toggle never arms the rule on the TBC family")
    tsb.class_db.guide_forever_rend_upkeep = nil
end

--=========================================================================================
-- 37) HU-8: the warrior states its hold (the guide's own verdict)
--=========================================================================================
-- The operator ruling (hands-up HU-8, resolved 2026-10-19): a HOLD is a DECISION and
-- an unknown is not. The warrior's guide answers two holds the practice path can
-- reach - the RIDE window (a queued HS/Cleave the player already placed) and the
-- HOLD window (the filler's rage shortfall) - and the step must SAY so: casting
-- during the hold is an illegal cast, doing nothing is correct, and a state the
-- class cannot read stays unknown (no attempt at all). The hold text is the
-- guide's own caption, never a re-decided one.
--
-- The guide's third hold verdict, the CANCEL cue (a queued spend the Execute press
-- kills), NAMES the Execute - the guide's own verdict pins that shape at the guide
-- level (tests/warrior_guide_state.lua: out.action == "execute", out.hold == true,
-- out.hold_text == "CANCEL"). A step that names an action stays an action, so the
-- practice pick and the live pick (which lights the Execute) can never disagree;
-- the cue itself is a live-gather reading the practice path never fed, so the
-- practice path never produces that verdict.
do
    local sb = build({ project = 2 })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    -- The shared engine loads into its own environment (like section 34): the
    -- AceAddon stub hands it the ADDON OBJECT, so the engine resolves the
    -- warrior's class module from the object (the class table lives there).
    local env = setmetatable({ ST = sb.st }, { __index = _G })
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return sb.ST end }
        end
        return {}
    end
    for _, mod in ipairs({ "weave.lua", "nextaction.lua", "practice.lua" }) do
        local chunk = assert(loadfile(ROOT .. mod))
        setfenv(chunk, env)
        chunk("SwedgeTimer", sb.st)
    end
    local H = sb.st.practice.harness
    check(type(H) == "table", "hold: the shared harness is loaded")

    -- (a) The RIDE window: a queued HS the player already placed (the guide's
    -- rule 4, warrior_guide.lua:1300-1303 - no action, hold = true).
    local ride_ctx = {
        now = 0, last_action = "hs",
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            swing_remaining = 2, hs_queued = true },
        cooldowns = {},
    }
    local ride = ST.WARRIOR.practice_scenario_step(ST, ride_ctx)
    check(type(ride) == "table" and ride.hold == true,
        "hold: a queued HS states an explicit hold")
    eq(ride.action, nil, "hold: the ride names no action")
    eq(ride.reason, "RIDE", "hold: the ride carries the guide's own caption")

    -- (b) The HOLD window: the filler's rage shortfall (the guide's rule 7,
    -- warrior_guide.lua:1397-1399 - no action, hold = true).
    local hold_ctx = {
        now = 0, last_action = "hs",
        resources = { rage = 10, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            swing_remaining = 2 },
        cooldowns = {},
    }
    local hold = ST.WARRIOR.practice_scenario_step(ST, hold_ctx)
    check(type(hold) == "table" and hold.hold == true,
        "hold: a rage shortfall states an explicit hold")
    eq(hold.action, nil, "hold: the hold names no action")
    eq(hold.reason, "HOLD", "hold: the hold carries the guide's own caption")

    -- (c) The unknown: a state the guide cannot read stays unknown - never a hold.
    local unknown_ctx = {
        now = 0, last_action = "hs",
        resources = {},
        cooldowns = {},
    }
    eq(ST.WARRIOR.practice_scenario_step(ST, unknown_ctx), nil,
        "hold: an unreadable state stays unknown (no hold statement)")

    -- (d) The three states, through the engine's own decision:
    --   hold + a cast  -> the illegal cast (an attempt, an F)
    --   hold + nothing -> a correct hold (no attempt, no points)
    --   unknown        -> unknown (no attempt)
    local answer = H.practice_scenario_step("WARRIOR", ST, hold_ctx)
    check(type(answer) == "table" and answer.hold == true,
        "hold: the accessor keeps the warrior's hold statement")
    eq(answer.action, nil, "hold: the hold statement names no action")
    check(type(answer.reason) == "string" and answer.reason ~= "",
        "hold: the hold statement carries the guide's reason")
    local run = H.new_rotation_run()
    local cast = H.rotation_run_decide(run, answer.action, "hs", answer.hold)
    eq(cast.outcome, "illegal_cast", "hold: a cast during the hold is an illegal cast")
    eq(H.ROTATION_OUTCOME_GRADES[cast.outcome], "F", "hold: the illegal cast grades F")
    eq(run.mispicks, 1, "hold: the illegal cast counts against the run's band")
    local idle_run = H.new_rotation_run()
    local idle = H.rotation_run_decide(idle_run, answer.action, nil, answer.hold)
    eq(idle.outcome, "hold_ok", "hold: doing nothing during the hold is correct")
    eq(H.ROTATION_OUTCOME_GRADES[idle.outcome], nil,
        "hold: a correct hold records no attempt (no points)")
    eq(idle_run.mispicks, 0, "hold: a correct hold is never a mis-pick")
    local unknown_run = H.new_rotation_run()
    local unknown = H.rotation_run_decide(unknown_run, nil, "hs")
    eq(unknown.outcome, "unknown", "hold: an unknown step stays unknown")
    eq(H.ROTATION_OUTCOME_GRADES[unknown.outcome], nil,
        "hold: an unknown decision records no attempt")
    eq(unknown_run.mispicks, 0, "hold: an unknown decision is never a mis-pick")
end

--=========================================================================================
-- 38) The APL's utility spine + the pre-pull table (the gap analysis's warrior
-- section: bench/rotation_gap_vs_apl_2026-10-20.md section 1). The shipped
-- rotation carried 13 keys, every one of them a damage ability or a debuff
-- upkeep: no stance, no shout, no rage tool, no cooldown pop, and no Thunder
-- Clap / Shattering Throw / Heroic Throw on WotLK. The operator's named set
-- (Charge, Battle Stance, Berserker Stance, Bloodrage) lands here - Charge in
-- the PRE-PULL table (the APL carries it as a pre-pull row, not a rotation
-- row), the rest in the rotation table.
--
-- What this section pins:
--   * the two blocks of the rotation table (the compiled rule order, then the
--     APL's utility spine);
--   * every utility line's id path, name path, family gate and citation;
--   * the two corrections the operator named (Bloodrage 2687 is on ALL FIVE
--     families; the shipped hamstring row's 18499 is Berserker Rage, not
--     "Improved Hamstring");
--   * no prompt: the guide's own vocabulary (read out of its source) holds
--     none of the utility keys, so a line no engine action can produce never
--     prompts;
--   * the pre-pull rows live in their own table, and Charge / Intercept are in
--     no rotation block.
--=========================================================================================
do
    local sb = build({ project = 2 })
    local ST = sb.ST
    local rot = ST.WARRIOR.practice_rotation

    local compiled = "op,execute,slam,sunder,rend,bt,ww,raging_blow,bladestorm,ms,hamstring,hs,cleave"
    local utility_keys = {
        "battle_stance", "berserker_stance", "gladiator_stance", "bloodrage",
        "battle_shout", "recklessness", "death_wish", "sweeping_strikes",
        "thunder_clap", "shattering_throw", "heroic_throw", "berserker_rage",
        "blood_fury",
    }
    local utility = table.concat(utility_keys, ",")

    -- (a) The two blocks.
    local keys = {}
    for i = 1, #rot do keys[#keys + 1] = rot[i].action end
    eq(table.concat(keys, ","), compiled .. "," .. utility,
        "APL: the rotation table is the compiled rule order then the APL's utility spine")
    eq(#rot, 13 + #utility_keys,
        "APL: the rotation table carries the compiled order and the utility spine")

    local by_action = {}
    for i = 1, #rot do by_action[rot[i].action] = rot[i] end

    -- (b) Every utility line: the id path, the name path, the family gate, the
    -- live flag, the filed need and the citation.
    local expect = {
        battle_stance = { id = 2457, name = "Battle Stance",
            families = { "ERA", "TBC", "FOREVER" } },
        berserker_stance = { id = 2458, name = "Berserker Stance",
            families = { "ERA", "TBC", "WRATH", "FOREVER" } },
        gladiator_stance = { id = 412513, name = "Gladiator Stance",
            families = { "ERA" } },
        bloodrage = { id = 2687, name = "Bloodrage",
            families = { "ERA", "TBC", "WRATH", "FOREVER" } },
        battle_shout = { ids = { ERA = 25289, TBC = 2048, FOREVER = 25289 },
            name = "Battle Shout", families = { "ERA", "TBC", "FOREVER" } },
        recklessness = { id = 1719, name = "Recklessness",
            families = { "ERA", "TBC", "FOREVER" } },
        death_wish = { ids = { ERA = 12328, TBC = 12292, FOREVER = 12328 },
            name = "Death Wish", families = { "ERA", "TBC", "FOREVER" } },
        sweeping_strikes = { id = 12723, name = "Sweeping Strikes",
            families = { "TBC", "FOREVER" } },
        thunder_clap = { id = 47502, name = "Thunder Clap",
            families = { "WRATH" } },
        shattering_throw = { id = 64382, name = "Shattering Throw",
            families = { "WRATH" } },
        heroic_throw = { id = 57755, name = "Heroic Throw",
            families = { "WRATH" } },
        berserker_rage = { id = 18499, name = "Berserker Rage",
            families = { "ERA", "TBC", "FOREVER" } },
        blood_fury = { id = 20572, name = "Blood Fury",
            families = { "ERA" } },
    }
    for i = 1, #utility_keys do
        local key = utility_keys[i]
        local entry = by_action[key]
        local want = expect[key]
        check(type(entry) == "table", "APL: the utility line " .. key .. " exists")
        if type(entry) == "table" then
            eq(entry.label, want.name,
                "APL: " .. key .. " carries the spell name as its label")
            eq(entry.spell_name, want.name,
                "APL: " .. key .. " carries the TBC name path")
            if want.ids then
                eq(type(entry.spell_ids), "table",
                    "APL: " .. key .. " carries the per-family id form")
                for family, id in pairs(want.ids) do
                    eq(entry.spell_ids and entry.spell_ids[family], id,
                        "APL: " .. key .. " carries the " .. family .. " id")
                end
                eq(entry.spell_id, nil,
                    "APL: " .. key .. " does not carry a single-family id")
            else
                eq(entry.spell_id, want.id,
                    "APL: " .. key .. " carries the id the Era-style clients resolve by")
                eq(entry.spell_ids, nil,
                    "APL: " .. key .. " does not carry the per-family id form")
            end
            eq(table.concat(entry.families or {}, ","), table.concat(want.families, ","),
                "APL: " .. key .. " is family-gated to the APLs that carry it")
            eq(entry.live, true,
                "APL: " .. key .. " is live (its read exists and the line can be evaluated)")
            eq(entry.engine, key ~= "gladiator_stance",
                "APL: " .. key .. " carries the engine flag (the Gladiator Stance "
                    .. "row has no arm)")
            check(type(entry.needs) == "string" and #entry.needs > 20,
                "APL: " .. key .. " files the read and the rule it waits for")
            check(type(entry.source) == "string" and #entry.source > 40,
                "APL: " .. key .. " cites its sim source")
            check(type(entry.reason) == "string" and #entry.reason > 0,
                "APL: " .. key .. " carries a reason")
        end
    end

    -- (c) The citations: the APL file and the priority index, per family.
    local cites = {
        battle_stance = { "phase_6_dw.apl.json [1]", "fury.apl.json [16]",
            "arms.apl.json [17]", "[13] and [25] (2457)" },
        berserker_stance = { "dps_no_reck.apl.json [24]", "phase_6_dw.apl.json [2]",
            "fury.apl.json [16]", "arms.apl.json [19]", "wowsims/wotlk" },
        gladiator_stance = { "phase_6_dw.apl.json [0]", "proto/warrior.proto:131",
            "stances.go:212" },
        bloodrage = { "dps_no_reck.apl.json [21]", "phase_6_dw.apl.json [7]",
            "fury.apl.json [20]", "arms.apl.json [21]", "arms.apl.json [28]",
            "fury.apl.json [23]", "wowsims/wotlk" },
        battle_shout = { "dps_no_reck.apl.json [23]", "fury.apl.json [22]",
            "arms.apl.json [22]", "arms.apl.json [29]", "fury.apl.json [25]" },
        recklessness = { "phase_6_dw.apl.json [14]", "fury.apl.json [9]",
            "arms.apl.json [9]", "arms.apl.json [11]" },
        death_wish = { "dps_no_reck.apl.json [3]", "phase_6_dw.apl.json [12]",
            "fury.apl.json [8]", "arms.apl.json [8]", "arms.apl.json [10]" },
        sweeping_strikes = { "fury.apl.json [10]", "arms.apl.json [10]",
            "arms.apl.json [12]", "fury.apl.json [12]" },
        thunder_clap = { "arms.apl.json [11]", "thunder_clap.go:16" },
        shattering_throw = { "fury.apl.json [9]", "shattering_throw.go:15" },
        heroic_throw = { "fury.apl.json [15]", "heroic_throw.go:11" },
        berserker_rage = { "dps_no_reck.apl.json [22]", "fury.apl.json [21]",
            "fury.apl.json [24]" },
        blood_fury = { "dps_no_reck.apl.json [7]" },
    }
    for i = 1, #utility_keys do
        local key = utility_keys[i]
        local src = by_action[key] and by_action[key].source or ""
        for j = 1, #cites[key] do
            check(src:find(cites[key][j], 1, true) ~= nil,
                "APL: the " .. key .. " line cites " .. cites[key][j])
        end
    end

    -- (d) The two corrections the operator named.
    eq(table.concat(by_action["bloodrage"].families, ","), "ERA,TBC,WRATH,FOREVER",
        "APL: Bloodrage 2687 is gated on all five families (the SoD branch rides the ERA token)")
    check(by_action["bloodrage"].source:find("phase_6_dw.apl.json [7]", 1, true) ~= nil,
        "APL: the Bloodrage line cites the SoD APL's row")
    local ham = by_action["hamstring"]
    check(ham.source:find("casts 18499", 1, true) == nil,
        "APL: the hamstring row no longer names 18499 as the TBC cast")
    check(ham.source:find("BERSERKER RAGE", 1, true) ~= nil,
        "APL: the hamstring row records the 18499 correction")
    check(ham.source:find("25212", 1, true) ~= nil,
        "APL: the hamstring row names the TBC Hamstring id")
    eq(by_action["berserker_rage"].spell_id, 18499,
        "APL: 18499 is the Berserker Rage id (not Hamstring)")
    eq(by_action["berserker_rage"].label, "Berserker Rage",
        "APL: the 18499 line is labelled Berserker Rage")

    -- (e) The engine's vocabulary: the compiled rule order (read out of the guide's
    -- own source) plus the utility spine (the rows the engine can now ask for).
    -- The compiled order still emits the same twelve keys - the thirteen compiled
    -- keys minus cleave, which no rule ever outputs (warrior_guide.lua's header).
    -- The utility spine adds the ten cooldown rows and the two stance rows; the
    -- Gladiator Stance row has no arm (the SoD APL gates it on a rune aura the
    -- client cannot answer), so it stays out of the vocabulary.
    local gsrc = (function()
        local f = assert(io.open(ROOT .. "warrior_guide.lua", "r"))
        local text = f:read("*a")
        f:close()
        return text
    end)()
    local emitted = {}
    for key in gsrc:gmatch('action%s*=%s*"([a-z_]+)"') do emitted[key] = true end
    local emitted_list = {}
    for key in pairs(emitted) do emitted_list[#emitted_list + 1] = key end
    table.sort(emitted_list)
    eq(table.concat(emitted_list, ","),
        "bladestorm,bt,execute,hamstring,hs,ms,op,raging_blow,rend,slam,sunder,ww",
        "APL: the compiled rule order still emits the same twelve keys")
    eq(emitted["cleave"], nil,
        "APL: the engine never emits cleave, so that compiled line is documentation too")
    -- The utility spine's own vocabulary (the engine's table + the stance arms).
    local pure = {}
    do
        local strict = {
            type = type, tonumber = tonumber, tostring = tostring,
            pairs = pairs, ipairs = ipairs, math = math, string = string,
        }
        setmetatable(strict, { __index = function() error("unexpected global") end })
        local chunk = assert(loadfile(ROOT .. "warrior_guide.lua"))
        setfenv(chunk, strict)
        chunk("SwedgeTimer", pure)
    end
    local spine = pure.warrior_guide.UTILITY_LINES
    check(type(spine) == "table", "APL: the engine publishes the utility spine's line table")
    local spine_keys = {}
    for key in pairs(spine) do spine_keys[#spine_keys + 1] = key end
    table.sort(spine_keys)
    eq(table.concat(spine_keys, ","),
        "battle_shout,berserker_rage,blood_fury,bloodrage,death_wish,heroic_throw,"
            .. "recklessness,shattering_throw,sweeping_strikes,thunder_clap",        "APL: the utility spine carries the ten cooldown rows")
    for i = 1, #utility_keys do
        local key = utility_keys[i]
        local has_arm = (spine[key] ~= nil) or key == "battle_stance"
            or key == "berserker_stance"
        eq(has_arm, key ~= "gladiator_stance",
            "APL: the engine has an arm for " .. key .. " (or deliberately none)")
        eq(by_action[key].engine, key ~= "gladiator_stance",
            "APL: the " .. key .. " row's engine flag matches the arm")
    end

    -- (f) The pre-pull table: the APL's pre-pull rows, per family, with the
    -- offset relative to the pull.
    local pre = ST.WARRIOR.PRACTICE_PREPULLS
    check(type(pre) == "table", "APL: the pre-pull table is exposed")
    local families = {}
    for family in pairs(pre) do families[#families + 1] = family end
    table.sort(families)
    eq(table.concat(families, ","), "FOREVER,SOD,TBC,WRATH",
        "APL: the pre-pull table covers the families whose APL carries pre-pull rows")
    local prepull_rows = {
        SOD = {
            { "berserker_stance", 2458, -1 },
            { "bloodrage", 2687, -5 },
        },
        TBC = {
            { "berserker_rage", 18499, -4.5 },
            { "bloodrage", 2687, -3 },
            { "battle_shout", 2048, -3 },
            { "charge", 11578, -0.9 },
            { "intercept", 25275, -0.9 },
        },
        FOREVER = {
            { "berserker_rage", 18499, -4.5 },
            { "battle_stance", 2457, -4 },
            { "bloodrage", 2687, -3 },
            { "battle_shout", 25289, -3 },
            { "charge", 11578, -0.9 },
            { "intercept", 20617, -0.9 },
        },
        WRATH = {
            { "berserker_stance", 2458, -20 },
            { "bloodrage", 2687, -10 },
            { "berserker_rage", 18499, -5 },
            { "recklessness", 1719, -3 },
            { "battle_stance", 2457, -2 },
            { "death_wish", 12292, -1.5 },
        },
    }
    for _, family in ipairs({ "SOD", "TBC", "FOREVER", "WRATH" }) do
        local rows = prepull_rows[family]
        local list = pre[family]
        check(type(list) == "table" and #list == #rows,
            "APL: the " .. family .. " pre-pull list carries " .. #rows .. " rows")
        if type(list) == "table" then
            for i = 1, #rows do
                local want = rows[i]
                local row = list[i]
                eq(row.action, want[1],
                    "APL: the " .. family .. " pre-pull row " .. i .. " names " .. want[1])
                eq(row.spell, want[2],
                    "APL: the " .. family .. " pre-pull row " .. i .. " carries the id")
                eq(row.at, want[3],
                    "APL: the " .. family .. " pre-pull row " .. i .. " carries the offset")
                check(type(row.label) == "string" and #row.label > 0,
                    "APL: the " .. family .. " pre-pull row " .. i .. " carries a label")
                check(type(row.source) == "string" and #row.source > 20,
                    "APL: the " .. family .. " pre-pull row " .. i .. " cites its source")
            end
        end
    end
    -- The pre-pull rows cite the APL's own prepull block and its offsets.
    check(pre.TBC[4].source:find("Pre-pull: Move", 1, true) ~= nil,
        "APL: the TBC Charge row cites the `Pre-pull: Move` group")
    check(pre.TBC[5].source:find("25275", 1, true) ~= nil,
        "APL: the TBC Intercept row carries the TBC client's rank 5")
    check(pre.FOREVER[6].source:find("20617", 1, true) ~= nil,
        "APL: the Forever Intercept row carries the Forever client's rank 3")
    check(pre.WRATH[6].source:find("12292", 1, true) ~= nil,
        "APL: the WotLK Death Wish row carries the WotLK client's id")
    check(pre.SOD[1].source:find("-1s", 1, true) ~= nil,
        "APL: the SoD Berserker Stance row cites its offset")

    -- (g) Charge and Intercept are pre-pull rows: they are in no rotation
    -- block (the operator's HU-12 ruling), and every pre-pull row names a key
    -- the rotation table knows.
    eq(by_action["charge"], nil,
        "APL: Charge is a pre-pull row, not a rotation line")
    eq(by_action["intercept"], nil,
        "APL: Intercept is a pre-pull row, not a rotation line")
    for _, family in ipairs({ "SOD", "TBC", "FOREVER", "WRATH" }) do
        local list = pre[family]
        for i = 1, #list do
            local key = list[i].action
            check(by_action[key] ~= nil or key == "charge" or key == "intercept",
                "APL: the " .. family .. " pre-pull row " .. key .. " names a known key")
        end
    end
end

--=========================================================================================
-- 39) The utility spine: the provider's reads (the family gate, the cooldown, the
-- buff) and the pre-pull drill (the hunter's shape).
--=========================================================================================
do
    -- (a) The TBC family: the APL's rows are read, the rows the family's APL does
    -- not carry stay dark, and the order lists carry the APL's own priority order.
    local sb = build({ project = 5, known = {
        [12292] = true, [1719] = true, [12723] = true, [2687] = true,
        [18499] = true, [2048] = true, [2457] = true, [2458] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.WARRIOR.post_init(ST)
    ST.WARRIOR.on_aura_change(ST)
    local inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
    eq(table.concat(inputs.utility_order, ","), "death_wish,recklessness,sweeping_strikes",
        "utility: the TBC APL's HIGH rows are the three cooldown pops above the core")
    eq(table.concat(inputs.utility_order_low, ","), "bloodrage,berserker_rage,battle_shout",
        "utility: the TBC APL's LOW rows close its list")
    eq(inputs.death_wish_known, true, "utility: the TBC client knows Death Wish")
    eq(inputs.death_wish_remaining, 0, "utility: Death Wish reads ready")
    eq(inputs.death_wish_buff, false, "utility: the Death Wish buff reads not up")
    eq(inputs.battle_shout_known, true, "utility: the TBC client knows Battle Shout")
    eq(inputs.sweeping_strikes_known, true, "utility: the TBC client knows Sweeping Strikes")
    eq(inputs.thunder_clap_known, nil,
        "utility: a row the family's APL does not carry stays unread")
    eq(inputs.blood_fury_known, nil,
        "utility: Blood Fury is an Era row, not a TBC one")
    eq(inputs.utility_wanted_stance, "berserker",
        "utility: the TBC upkeep row wants Berserker Stance")
    -- The TBC client resolves by NAME: the utility row's cooldown query carries the
    -- localized name, not the bare id (the operator's name-vs-id rule).
    sb.cooldown_queries = 0
    sb.last_cooldown_query = nil
    ST.WARRIOR.gather_guide_inputs(ST, {})
    eq(type(sb.last_cooldown_query), "string",
        "utility: the TBC cooldown query carries the localized name, not the id")
    check(sb.cooldown_queries > 0, "utility: the TBC gather queried the rows' cooldowns")
    eq(inputs.utility_weave, true, "utility: the TBC APL weaves into Battle Stance")
    eq(inputs.utility_stance, nil,
        "utility: the stance read is unknown until the aura walk finds one")
    -- The stance read: the aura walk stamps the stance, the gather feeds it.
    sb.auras = { { name = "Battle Stance", id = 2457 } }
    ST.WARRIOR.on_aura_change(ST)
    inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
    eq(inputs.utility_stance, "battle", "utility: the stance walk feeds the utility read")
    eq(inputs.utility_stance, ST.warrior_stance,
        "utility: the utility read is the class's own stance stamp")
    -- The buff read: the aura walk stamps the row's buff.
    sb.auras = { { name = "Battle Shout", id = 2048 } }
    ST.WARRIOR.on_aura_change(ST)
    inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
    eq(inputs.battle_shout_buff, true, "utility: the Battle Shout buff reads up")
    sb.auras = {}
    ST.WARRIOR.on_aura_change(ST)
    inputs = ST.WARRIOR.gather_guide_inputs(ST, {})
    eq(inputs.battle_shout_buff, false, "utility: the Battle Shout buff reads not up again")
    -- (b) The Era family: the Era rows are read, the SoD-only rows are not.
    local era = build({ project = 2, known = { [12328] = true, [20572] = true,
        [2687] = true, [18499] = true, [25289] = true, [2458] = true } })
    local EST = era.ST
    EST.interfaces_are_initialised = true
    EST.WARRIOR.post_init(EST)
    EST.WARRIOR.on_aura_change(EST)
    local einputs = EST.WARRIOR.gather_guide_inputs(EST, {})
    eq(table.concat(einputs.utility_order, ""),
        "", "utility: the Era APL has no HIGH row")
    eq(table.concat(einputs.utility_order_low, ","),
        "death_wish,blood_fury,bloodrage,berserker_rage,battle_shout",
        "utility: the Era APL's rows all sit below the core")
    eq(einputs.gladiator_stance_known, nil,
        "utility: a row with no engine arm is never read")
    eq(einputs.utility_weave, nil,
        "utility: the Era APL carries no Battle Stance row, so it never weaves")
    -- (c) The SoD branch: its own rows (the SoD APL carries no Battle Shout, no
    -- Berserker Rage and no Blood Fury row).
    local sod = build({ project = 2, known = { [402911] = true, [12328] = true,
        [1719] = true, [2687] = true, [2457] = true, [2458] = true } })
    local SST = sod.ST
    SST.interfaces_are_initialised = true
    SST.WARRIOR.post_init(SST)
    SST.WARRIOR.on_aura_change(SST)
    local sinputs = SST.WARRIOR.gather_guide_inputs(SST, {})
    eq(table.concat(sinputs.utility_order, ","), "death_wish,recklessness",
        "utility: the SoD APL's rows above the core")
    eq(table.concat(sinputs.utility_order_low, ""),
        "", "utility: the SoD APL has no LOW row")
    eq(sinputs.battle_shout_known, nil,
        "utility: the SoD APL carries no Battle Shout row")
    eq(sinputs.utility_weave, true, "utility: the SoD APL weaves into Battle Stance")

    -- (d) The pre-pull drill (the hunter's shape): the family's own rows, in their
    -- own order, and the combat rotation never asks for them.
    local drill
    for i = 1, #ST.WARRIOR.practice_drills do
        if ST.WARRIOR.practice_drills[i].key == "warrior_prepull" then
            drill = ST.WARRIOR.practice_drills[i]
        end
    end
    check(drill ~= nil, "prepull: the warrior ships the opener drill")
    check(type(drill.grade) == "function", "prepull: the opener drill carries a grade function")
    local grade = drill.grade
    -- The TBC sequence: Berserker Rage at -4.5 s, then the Bloodrage and the
    -- Battle Shout at -3 s, then the Charge and the Intercept at -0.9 s.
    eq(grade(ST, { now = 10, pull_at = 14.5, last_action = "berserker_rage" }), "S",
        "prepull: the first opener on time is an S")
    eq(grade(ST, { now = 10, pull_at = 14.5, last_action = "charge" }), "D",
        "prepull: a different opener is a D")
    eq(grade(ST, { now = 10, pull_at = 14.5 }), "S",
        "prepull: the moment inside the due opener's window is an S")
    eq(grade(ST, { now = 13, pull_at = 14.5, last_action = "battle_shout" }), "B",
        "prepull: the Battle Shout opener 1.5 s late is a B (the hunter's band)")
    eq(grade(ST, { now = 13, pull_at = 14.5, last_action = "berserker_rage" }), "D",
        "prepull: the missed opener is a D")
    eq(grade(ST, { now = 13, pull_at = 14.5 }), "S",
        "prepull: the moment before the next opener is an S")
    eq(grade(ST, { now = 10, pull_at = 14.5, last_action = "charge" }), "D",
        "prepull: the pre-pull row the rotation never carries is still the due one")
    -- A client with no sourced pre-pull sequence (the Era build) never grades.
    local era_drill
    for i = 1, #EST.WARRIOR.practice_drills do
        if EST.WARRIOR.practice_drills[i].key == "warrior_prepull" then
            era_drill = EST.WARRIOR.practice_drills[i]
        end
    end
    eq(era_drill.grade(EST, { now = 10, pull_at = 14.5, last_action = "berserker_rage" }), nil,
        "prepull: the Era build carries no pre-pull rows, so the drill stays unknown")
    -- (e) The practice scenario asks for a utility row: the caller's cooldowns and
    -- flags decide, exactly like the live guide (the same engine, the same gates).
    local step = ST.WARRIOR.practice_scenario_step
    check(type(step) == "function", "practice: the warrior exposes the scenario step")
    local pick = step(ST, { now = 10, last_action = nil,
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            bloodrage_known = true, bloodrage_buff = false, bloodrage_rage_max = 90 },
        cooldowns = { bloodrage = 0 } })
    eq(pick and pick.action, "bloodrage",
        "practice: the scenario asks for the utility row whose read says so")
    local buffed = step(ST, { now = 10, last_action = nil,
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            bloodrage_known = true, bloodrage_buff = true, bloodrage_rage_max = 90 },
        cooldowns = { bloodrage = 0 } })
    check(buffed == nil or buffed.action ~= "bloodrage",
        "practice: the scenario never asks for a utility row whose buff is up")
    local cooling = step(ST, { now = 10, last_action = nil,
        resources = { rage = 50, hs_cost = 15, target_health_pct = 100, execute_pct = 20,
            bloodrage_known = true, bloodrage_buff = false, bloodrage_rage_max = 90 },
        cooldowns = { bloodrage = 12 } })
    check(cooling == nil or cooling.action ~= "bloodrage",
        "practice: the scenario never asks for a utility row on cooldown")

    -- The combat rotation never asks for a pre-pull row.
    local rot = ST.WARRIOR.practice_rotation
    local prepull_in_rotation = false
    for i = 1, #rot do
        if rot[i].action == "charge" or rot[i].action == "intercept" then
            prepull_in_rotation = true
        end
    end
    check(prepull_in_rotation == false,
        "prepull: the combat rotation never carries a pre-pull row")
end

--=========================================================================================
-- 40) The residuals the utility lane filed (bench/warrior_apl_utility_live_2026-10-20.md
-- §7 and the filed residuals):
--   (a) the rotation slice the practice panel publishes (the hunter's shape - the
--       other classes expose practice_rotation_for and the panel calls it);
--   (b) the APL's execute-phase clause on the rage dump - the ONE of the three
--       unmodelled APL gates whose read EXISTS (the class already knows the
--       phase);
--   (c) the Gladiator Stance row's sharper filing (the gate is the T1 damage SET
--       bonus, not a rune; the missing read is the set-membership read).
--=========================================================================================
do
    local function slice_keys(list)
        local out = {}
        for i = 1, #(list or {}) do out[#out + 1] = list[i].action end
        return table.concat(out, ",")
    end

    -- (a) The accessors.
    local tbc = build({ project = 5, known = { [12292] = true, [1719] = true,
        [12723] = true, [2687] = true, [18499] = true, [2048] = true } })
    local TST = tbc.ST
    TST.interfaces_are_initialised = true
    TST.WARRIOR.post_init(TST)
    TST.WARRIOR.on_aura_change(TST)
    check(type(TST.WARRIOR.practice_rotation_for) == "function",
        "residuals: the warrior publishes a rotation slice (the panel calls it)")
    check(type(TST.WARRIOR.practice_rotation_family) == "function",
        "residuals: the warrior publishes the rotation family (the panel reads it)")
    eq(TST.WARRIOR.practice_rotation_family(), "TBC",
        "residuals: the TBC client plays the TBC slice")
    eq(slice_keys(TST.WARRIOR.practice_rotation_for("TBC")),
        "op,execute,slam,sunder,bt,ww,hs,battle_stance,berserker_stance,bloodrage,"
            .. "battle_shout,recklessness,death_wish,sweeping_strikes,berserker_rage",
        "residuals: the TBC slice is the class's own TBC vocabulary, in the table's order")
    eq(slice_keys(TST.WARRIOR.practice_rotation_for()),
        slice_keys(TST.WARRIOR.practice_rotation_for("TBC")),
        "residuals: the argument-free call answers the running client's own slice")
    eq(#TST.WARRIOR.practice_rotation_for("NOPE"), 0,
        "residuals: a family with no APL publishes no slice")
    eq(TST.WARRIOR.practice_rotation_family("NOPE"), "TBC",
        "residuals: the family accessor answers the running client")
    -- The rows the engine can never ask for stay out of the strip: cleave (no rule
    -- outputs it) and the Gladiator Stance row (no arm).
    check(TST.WARRIOR.practice_rotation_for("TBC")[1].action ~= "cleave",
        "residuals: the strip carries no row the engine never emits")
    for i = 1, #TST.WARRIOR.practice_rotation_for("TBC") do
        local entry = TST.WARRIOR.practice_rotation_for("TBC")[i]
        check(entry.action ~= "cleave" and entry.action ~= "gladiator_stance",
            "residuals: the strip carries no unaskable row (" .. entry.action .. ")")
        check(type(entry.label) == "string" and entry.label ~= "",
            "residuals: the strip row " .. entry.action .. " carries a label")
    end
    -- The same invariant on every family: cleave is in the Forever vocabulary
    -- (the Forever guide carries the slot), and the engine never emits it.
    for _, family in ipairs({ "ERA", "SOD", "TBC", "WRATH", "FOREVER" }) do
        local list = TST.WARRIOR.practice_rotation_for(family)
        for i = 1, #list do
            check(list[i].action ~= "cleave",
                "residuals: the " .. family .. " strip carries no cleave (the engine never emits it)")
            check(list[i].action ~= "gladiator_stance",
                "residuals: the " .. family .. " strip carries no gladiator_stance (no arm)")
        end
    end
    -- The Era client: its own vocabulary (no Sunder - the Era client has no
    -- Sunder spell - no Rend, no Raging Blow: those are the SoD branch's rows).
    local era = build({ project = 2, known = { [12328] = true, [20572] = true,
        [2687] = true, [18499] = true, [25289] = true } })
    local EST = era.ST
    EST.interfaces_are_initialised = true
    EST.WARRIOR.post_init(EST)
    EST.WARRIOR.on_aura_change(EST)
    eq(EST.WARRIOR.practice_rotation_family(), "ERA",
        "residuals: the plain Era client plays the Era slice")
    eq(slice_keys(EST.WARRIOR.practice_rotation_for("ERA")),
        "op,execute,slam,bt,ww,hamstring,hs,berserker_stance,bloodrage,battle_shout,"
            .. "death_wish,berserker_rage,blood_fury",
        "residuals: the Era slice is the class's own Era vocabulary")
    -- The SoD branch (the ERA token with the SoD rune): its own APL, its own slice.
    local sod = build({ project = 2, known = { [402911] = true, [12328] = true,
        [1719] = true, [2687] = true, [2457] = true, [2458] = true } })
    local SST = sod.ST
    SST.interfaces_are_initialised = true
    SST.WARRIOR.post_init(SST)
    SST.WARRIOR.on_aura_change(SST)
    eq(SST.WARRIOR.practice_rotation_family(), "SOD",
        "residuals: the SoD branch plays its own slice")
    eq(slice_keys(SST.WARRIOR.practice_rotation_for("SOD")),
        "op,execute,slam,rend,bt,ww,raging_blow,hs,battle_stance,berserker_stance,"
            .. "recklessness,death_wish",
        "residuals: the SoD slice is the class's own SoD vocabulary")
    -- The SoD APL's [7] Bloodrage row is NOT in the engine's SoD order (the
    -- utility lane's order table), so the SoD strip carries no Bloodrage: the
    -- strip mirrors what the engine can ask, not what the APL lists. FILED with
    -- the bench report (the order table's gap).
    check(SST.WARRIOR.practice_rotation_for("SOD")[1] ~= nil
        and slice_keys(SST.WARRIOR.practice_rotation_for("SOD")):find("bloodrage", 1, true) == nil,
        "residuals: the SoD strip carries no row the engine never asks for")
    -- The WotLK family: the spec picks the vocabulary (fury by default, arms when
    -- Mortal Strike is known).
    local wrath = build({ project = 11, known = { [23881] = true, [1680] = true } })
    local WST = wrath.ST
    WST.interfaces_are_initialised = true
    WST.WARRIOR.post_init(WST)
    WST.WARRIOR.on_aura_change(WST)
    eq(WST.WARRIOR.practice_rotation_family(), "WRATH",
        "residuals: the WotLK client plays the WotLK slice")
    eq(slice_keys(WST.WARRIOR.practice_rotation_for("WRATH")),
        "op,execute,slam,bt,ww,hs,berserker_stance,bloodrage,shattering_throw,heroic_throw",
        "residuals: the WotLK fury slice is the class's own fury vocabulary")
    local arms = build({ project = 11, known = { [12294] = true, [2687] = true } })
    local AST = arms.ST
    AST.interfaces_are_initialised = true
    AST.WARRIOR.post_init(AST)
    AST.WARRIOR.on_aura_change(AST)
    eq(AST.warrior_is_arms, true, "residuals: the Mortal Strike probe freezes the arms branch")
    eq(slice_keys(AST.WARRIOR.practice_rotation_for("WRATH")),
        "op,execute,rend,bladestorm,ms,hs,bloodrage,thunder_clap",
        "residuals: the WotLK arms slice is the class's own arms vocabulary")
    -- The Forever client.
    local forever = build({ project = 18, known = { [12328] = true, [1719] = true,
        [12723] = true, [2687] = true, [25289] = true } })
    local FST = forever.ST
    FST.interfaces_are_initialised = true
    FST.WARRIOR.post_init(FST)
    FST.WARRIOR.on_aura_change(FST)
    eq(FST.WARRIOR.practice_rotation_family(), "FOREVER",
        "residuals: the Forever client plays the Forever slice")
    eq(slice_keys(FST.WARRIOR.practice_rotation_for("FOREVER")),
        "op,execute,slam,sunder,hamstring,hs,battle_stance,bloodrage,battle_shout,"
            .. "recklessness,death_wish,sweeping_strikes",
        "residuals: the Forever slice is the class's own Forever vocabulary")

    -- (b) The APL's execute-phase clause on the dump: the provider arms the gate
    -- only on the families whose APL forbids the dump inside the phase (TBC and
    -- Forever); the Era APL allows it, and the SoD / WotLK APLs carry no clause.
    eq(TST.WARRIOR.gather_guide_inputs(TST, {}).execute_phase_dump_gate, true,
        "execute-phase gate: the TBC client arms the APL's phase clause")
    eq(FST.WARRIOR.gather_guide_inputs(FST, {}).execute_phase_dump_gate, true,
        "execute-phase gate: the Forever client arms the APL's phase clause")
    eq(EST.WARRIOR.gather_guide_inputs(EST, {}).execute_phase_dump_gate, nil,
        "execute-phase gate: the Era client keeps the dump (the Era APL allows it)")
    eq(SST.WARRIOR.gather_guide_inputs(SST, {}).execute_phase_dump_gate, nil,
        "execute-phase gate: the SoD client keeps the dump (no clause in its APL)")
    eq(WST.WARRIOR.gather_guide_inputs(WST, {}).execute_phase_dump_gate, nil,
        "execute-phase gate: the WotLK client keeps the dump (no HS row in its APL)")

    -- The practice surface honours the gate when the context carries it (the
    -- scenario's own context decides, exactly like the other family flags).
    local step = TST.WARRIOR.practice_scenario_step
    local in_phase = { now = 10, last_action = nil,
        resources = { rage = 50, hs_cost = 15, target_health_pct = 10, execute_pct = 20,
            swing_remaining = 2 },
        cooldowns = { execute = 5 } }
    local gated = { now = 10, last_action = nil,
        resources = { rage = 50, hs_cost = 15, target_health_pct = 10, execute_pct = 20,
            swing_remaining = 2, execute_phase_dump_gate = true },
        cooldowns = { execute = 5 } }
    local ungated = step(TST, in_phase)
    check(ungated ~= nil and ungated.action == "hs",
        "execute-phase gate: without the flag the practice dump still fires in the phase")
    local gated_pick = step(TST, gated)
    check(gated_pick == nil or gated_pick.action ~= "hs",
        "execute-phase gate: with the flag the practice dump is withheld in the phase")

    -- (c) The Gladiator Stance row: the gate is the T1 damage SET bonus, and the
    -- missing read is named. The row stays engine = false.
    local rot = TST.WARRIOR.practice_rotation
    local gladiator
    for i = 1, #rot do
        if rot[i].action == "gladiator_stance" then gladiator = rot[i] end
    end
    check(gladiator ~= nil, "residuals: the Gladiator Stance row is in the table")
    eq(gladiator.engine, false,
        "residuals: the Gladiator Stance row still has no arm (no honest gate)")
    eq(gladiator.live, true,
        "residuals: the Gladiator Stance row's read exists")
    local needs = gladiator.needs or ""
    check(needs:find("457817", 1, true) ~= nil and needs:find("464241", 1, true) ~= nil,
        "residuals: the filing names the two auras the SoD APL gates the row on")
    check(needs:find("item_sets_pve_phase_4.go", 1, true) ~= nil,
        "residuals: the filing names the set-bonus source (the gate is an equipment fact)")
    check(needs:find("is_item_equipped", 1, true) ~= nil,
        "residuals: the filing names the missing read (the equipped-item / set read)")
    check(needs:find("Spell.csv", 1, true) ~= nil,
        "residuals: the filing names the client-side half that IS readable")
end

--=========================================================================================
-- The NEUTRAL action set (the practice panel's legitimate-but-ungraded presses)
--
-- The class publishes ST.WARRIOR.practice_neutral_actions (the contract fixed by
-- the orchestrator, practice.lua's class contract block). The engine treats a
-- press of one of these keys as NEUTRAL: no attempt, no points, no streak change,
-- and NOT a mis-pick. A key that is neither a rotation action nor neutral stays
-- a mis-pick, so the set is a deliberate, CLOSED list - never "everything except
-- the rotation".
--
-- The publish is FAMILY-SCOPED (a family key -> a set of action keys), because
-- the answer is family-dependent: the class's own Cleave row is an ERA/TBC row
-- (families = { "ERA", "TBC" }) and its engine arm is filed (engine = false), so
-- on the Forever client - whose guide slots offer Cleave and whose rotation names
-- no Cleave row - a Cleave press is legitimate but never graded. On the
-- families whose rotation DOES carry a Cleave row the key is a rotation action,
-- so it is deliberately not published there. The Battle Shout row is the mirror
-- case: an APL utility row on ERA, TBC and FOREVER, and NO row on the WotLK
-- client, whose guide slots do not offer the key either - so it is published for
-- WRATH alone.
--
-- Every bucket ALSO carries the class's common abilities (the practice-panel
-- ability list: a potion, food, a movement ability) - the abilities the panel
-- offers but the rotation never grades.
--=========================================================================================
do
    local sb = build()
    local M = sb.ST.WARRIOR
    local published = M.practice_neutral_actions
    eq(type(published), "table", "neutral: the warrior publishes a neutral action set")
    eq(type(published.FOREVER), "table", "neutral: the Forever client publishes a bucket")
    eq(published.FOREVER.cleave, true, "neutral: Cleave is neutral on the Forever client")
    for family, bucket in pairs(published) do
        eq(type(bucket), "table", "neutral: the " .. tostring(family) .. " bucket is a set")
        for key in pairs(bucket) do
            eq(bucket[key], true, "neutral: the " .. tostring(family)
                .. " bucket holds key = true entries")
        end
    end
    -- Only the four client families publish a bucket (a family the class does not
    -- describe answers nil in the engine, and never a guess).
    for key in pairs(published) do
        check(key == "ERA" or key == "TBC" or key == "WRATH" or key == "FOREVER",
            "neutral: only a client family publishes a bucket (found " .. tostring(key) .. ")")
    end

    -- The rotation slice of each family (the class's own published slice).
    local function slice_keys(family)
        local out = {}
        local entries = M.practice_rotation_for(family)
        for i = 1, #entries do
            local e = entries[i]
            if type(e) == "table" and type(e.action) == "string" then out[e.action] = true end
        end
        return out
    end

    -- THE GRADING-INTEGRITY PIN: a rotation action can never be neutral. The
    -- engine grades the EXPECTED action first, so a rotation press still hits -
    -- but a rotation action published as neutral would make a WRONG rotation
    -- press free.
    for family, bucket in pairs(published) do
        local keys = slice_keys(family)
        for key in pairs(bucket) do
            check(keys[key] ~= true,
                "neutral: " .. tostring(key) .. " is not a rotation action on " .. tostring(family)
                .. " (a rotation action can never be neutral)")
        end
    end

    -- The Forever slice really carries no Cleave row (the key is legitimate and
    -- ungraded THERE), and the class's own rotation TABLE still carries the
    -- Cleave row for the ERA/TBC clients - the APL spine row, with its engine
    -- arm filed (the frozen engine cannot ask for Cleave). That is why the
    -- publish is family-scoped: the key is a rotation row on the classic line
    -- and a legitimate ungraded press on the Forever client.
    local forever_keys = slice_keys("FOREVER")
    check(forever_keys.cleave ~= true,
        "neutral: the Forever rotation names no Cleave row (the press is ungraded)")
    local table_cleave = false
    for i = 1, #M.practice_rotation do
        local e = M.practice_rotation[i]
        if type(e) == "table" and e.action == "cleave" then
            table_cleave = true
            -- the row's family gate is a LIST here (the warrior's own shape)
            local gated = {}
            if type(e.families) == "table" then
                for _, fam in ipairs(e.families) do gated[fam] = true end
                for key, value in pairs(e.families) do
                    if type(key) == "string" and value == true then gated[key] = true end
                end
            end
            check(gated.ERA == true and gated.TBC == true,
                "neutral: the class's own Cleave row is an ERA/TBC row")
            check(e.engine == false,
                "neutral: the Cleave row's engine arm is filed (the rotation cannot ask for it)")
        end
    end
    check(table_cleave,
        "neutral: the class's rotation table carries the Cleave row (the APL spine)")

    -- THE BATTLE SHOUT ROW: it is an APL utility row on ERA, TBC and FOREVER, and
    -- on no WotLK row - so it is neutral on the WotLK client alone, and the
    -- classic line keeps it as a rotation action (a wrong Battle Shout press must
    -- never be free).
    local utility_battle_shout = false
    for i = 1, #M.practice_rotation do
        local e = M.practice_rotation[i]
        if type(e) == "table" and e.action == "battle_shout" then
            utility_battle_shout = true
        end
    end
    check(utility_battle_shout,
        "neutral: the class's rotation table carries the Battle Shout row (the APL spine)")
    check(slice_keys("ERA").battle_shout == true,
        "neutral: the Era rotation names a Battle Shout row")
    check(slice_keys("TBC").battle_shout == true,
        "neutral: the TBC rotation names a Battle Shout row")
    check(slice_keys("FOREVER").battle_shout == true,
        "neutral: the Forever rotation names a Battle Shout row")
    check(slice_keys("WRATH").battle_shout ~= true,
        "neutral: the WotLK rotation names no Battle Shout row")
    eq(published.WRATH.battle_shout, true,
        "neutral: Battle Shout is neutral on the WotLK client")
    eq(published.ERA.battle_shout, nil,
        "neutral: Battle Shout is not neutral on the Era client (a rotation row)")
    eq(published.TBC.battle_shout, nil,
        "neutral: Battle Shout is not neutral on the TBC client (a rotation row)")
    eq(published.FOREVER.battle_shout, nil,
        "neutral: Battle Shout is not neutral on the Forever client (a rotation row)")

    -- THE PRACTICE-PANEL ABILITY LIST: the common abilities the panel offers but
    -- the rotation never grades. Every entry names the client's spell, carries a
    -- label and cites at least one spell id - an ability whose id nobody can
    -- source is not published at all.
    local common = M.practice_common_actions
    eq(type(common), "table", "panel: the warrior publishes a practice-panel ability list")
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
        -- Every common ability the class offers is published as neutral on the
        -- families the panel offers it on (a legitimate press is never a mis-pick).
        local gated = action.families
        local families = { "ERA", "TBC", "WRATH", "FOREVER" }
        if type(gated) == "table" then
            families = {}
            for _, fam in ipairs(gated) do families[#families + 1] = fam end
        end
        for _, fam in ipairs(families) do
            eq(type(published[fam]), "table", "panel: the " .. fam .. " bucket exists")
            eq(published[fam][action.key], true, "panel: " .. tostring(action.key)
                .. " is neutral on " .. fam .. " (the panel offers it there)")
        end
    end
    -- The common abilities are never rotation actions on the families the panel
    -- offers them on (the grading-integrity pin above says the same thing about
    -- the publish; this one says it about the LIST).
    for i = 1, #common do
        local action = common[i]
        local gated = action.families
        local families = { "ERA", "TBC", "WRATH", "FOREVER" }
        if type(gated) == "table" then
            families = {}
            for _, fam in ipairs(gated) do families[#families + 1] = fam end
        end
        for _, fam in ipairs(families) do
            check(slice_keys(fam)[action.key] ~= true,
                "panel: the common ability " .. tostring(action.key)
                .. " is not a rotation action on " .. fam)
        end
    end
    -- The panel's widening seam: the class publishes the widened slot list and
    -- applies it to the guide slot list (the shaman's apply_family_slots
    -- precedent), so the practice panel offers the common abilities.
    eq(type(M.practice_panel_slots), "function",
        "panel: the class publishes the panel slot list")
    eq(type(M.apply_practice_panel_actions), "function",
        "panel: the class publishes the widening seam")
    local widened = M.practice_panel_slots()
    eq(type(widened), "table", "panel: the panel slot list is a table")
    check(#widened >= #M.guide.slots, "panel: the panel slot list carries the guide slots")
end

-- ---- the style constants ride the module table (the local ceiling) ---------
-- The class module sits at Lua 5.1's 200-local ceiling, so its display
-- constants live on the module table (the class's own WARRIOR_UTILITY
-- precedent). The values are the reference's own, unchanged by the move -
-- pinned here so a later edit cannot quietly change one.
do
    local M = build().ST.WARRIOR
    eq(type(M.hud_style), "table", "style: the HUD style rides the module table")
    eq(M.hud_style.op_edge_color[1], 1, "style: the Overpower edge colour keeps its red channel")
    eq(M.hud_style.op_text_color[3], 0.2, "style: the Overpower text colour keeps its blue channel")
    eq(M.hud_style.op_pulse_hz, 10, "style: the Overpower pulse keeps its 10 Hz rate")
    eq(M.hud_style.slam_label_color[3], 0.15, "style: the slam label colour keeps its blue channel")
    eq(M.hud_style.slam_safe_color[2], 204, "style: the slam safe colour keeps its green channel")
    eq(type(M.bar_style), "table", "style: the bar style rides the module table")
    eq(M.bar_style.shield_block_fallback_color[3], 255, "style: the Shield Block colour keeps its blue channel")
    eq(M.bar_style.slam_clash_color[1], 217, "style: the slam clash colour keeps its red channel")
    eq(M.bar_style.desync_spark_width, 2, "style: the desync spark keeps its 2 px width")
    eq(M.bar_style.desync_clash_color[1], 255, "style: the desync clash colour keeps its red channel")
    eq(M.bar_style.rampage_badge_color[2], 140, "style: the Rampage badge colour keeps its green channel")
    eq(M.bar_style.bank_band, 15, "style: the rage-bank band keeps its 15 % width")
    eq(M.bar_style.bank_rage_floor, 60, "style: the rage-bank floor keeps its 60 rage floor")
    eq(M.bar_style.bank_edge_color[3], 0, "style: the rage-bank edge colour keeps its blue channel")
    eq(M.bar_style.bank_text_color[4], 1.0, "style: the rage-bank text colour keeps its alpha")
    eq(M.bar_style.battle_shout_badge_color[1], 240, "style: the Battle Shout badge colour keeps its red channel")
    -- The clean desync tint IS the Slam safe colour, and the Rampage tiers reuse
    -- it plus the badge colour - the same sharing the constants had.
    eq(M.bar_style.desync_clean_color, M.hud_style.slam_safe_color,
        "style: the clean desync tint is the Slam safe colour")
    eq(type(M.bar_style.rampage_tier_colors), "table", "style: the Rampage tiers ride the module table")
    eq(M.bar_style.rampage_tier_colors.green, M.hud_style.slam_safe_color,
        "style: the green Rampage tier is the Slam safe colour")
    eq(M.bar_style.rampage_tier_colors.amber, M.bar_style.rampage_badge_color,
        "style: the amber Rampage tier is the badge colour")
    eq(M.bar_style.rampage_tier_colors.red[1], 217, "style: the red Rampage tier keeps its red channel")
    -- The HUD's own two tables moved the same way.
    eq(type(M.HUD_COOLDOWN_FALLBACK), "table", "style: the HUD cooldown fallback rides the module table")
    eq(M.HUD_COOLDOWN_FALLBACK.bladestorm, 90, "style: the Bladestorm fallback keeps its 90 s swipe")
    eq(type(M.HUD_SKIP_GCD), "table", "style: the HUD skip set rides the module table")
end

-- ---- the shipped comments match the code (the audit's MEDIUM-3) -------------
-- The audit found two shipped comments contradicting the code they describe:
-- the ability-list note claimed the common abilities have no key in the
-- warrior's own list (the class publishes exactly those keys), and the
-- resolver note claimed "every client family answers its own rank art" (the
-- fallback hands the ERA corpus's rank-1 id, not the client's own art). The
-- pins below keep the stale claims OUT; they are source-shape pins on the
-- ABSENCE of a phrase, so a correct rewording still passes.
do
    local f = io.open(ROOT .. "classes/warrior.lua", "r")
    local src = f and f:read("*a") or ""
    if f then f:close() end
    local flat = src:gsub("\r\n", "\n")
    check(flat:find("have NO\n--     key in the warrior's own ability list", 1, true) == nil,
        "comment: the stale 'no key in the warrior's own ability list' claim is gone")
    check(flat:find("every client family answers its own rank art", 1, true) == nil,
        "comment: the stale 'every client family answers its own rank art' claim is gone")
    check(flat:find("answers its own rank id", 1, true) ~= nil,
        "comment: the resolver note says what the code does")
    check(flat:find("the class's own PRACTICE-PANEL ability list", 1, true) ~= nil,
        "comment: the ability-list note points at the practice-panel ability list")
end

--=========================================================================================
-- R1 name-carrying payloads: the HS / Cleave queue tints clear by id or by
-- name on every family (id primary, name secondary). Era rides numeric ids,
-- TBC Anniversary can ride the name in the guid slot (or the spell id slot)
-- with a nil id; either shape clears its own ability only. A foreign name
-- changes nothing.
--=========================================================================================
do
    -- Era: the numeric-id success clears HS, and the literal name clears too.
    local sb = build({ project = 2, known = { [25286] = true, [25231] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    ST.cleave_queued = false
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "cast-1", 25286)
    eq(ST.hs_queued, false, "Era: a numeric-id HS success clears the HS tint")
    eq(sb.bar_color_calls, 1, "Era: the HS id clear recolours once")

    ST.hs_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "Heroic Strike", nil)
    eq(ST.hs_queued, false, "Era: the HS name clears the HS tint too")
    eq(sb.bar_color_calls, 1, "Era: the HS name clear recolours once")

    -- Cleave rides its own arm: the numeric id and the name both clear it.
    ST.cleave_queued = true
    ST.hs_queued = false
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "cast-2", 25231)
    eq(ST.cleave_queued, false, "Era: a numeric-id Cleave success clears the Cleave tint")
    eq(sb.bar_color_calls, 1, "Era: the Cleave id clear recolours once")

    ST.cleave_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "Cleave", nil)
    eq(ST.cleave_queued, false, "Era: the Cleave name clears the Cleave tint too")
    eq(sb.bar_color_calls, 1, "Era: the Cleave name clear recolours once")

    -- A foreign name must change nothing.
    ST.hs_queued = true
    ST.cleave_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "Scare Beast", nil)
    eq(ST.hs_queued, true, "Era: an unrelated name leaves the HS tint alone")
    eq(ST.cleave_queued, true, "Era: an unrelated name leaves the Cleave tint alone")
    eq(sb.bar_color_calls, 0, "Era: an unrelated name triggers no recolour")
end

do
    -- TBC Anniversary: the name rides the guid slot with a nil id, or the
    -- spell id slot with a dummy guid; a numeric id still clears.
    local sb = build({ project = 5, name_only_client = true,
        known = { [29707] = true, [25231] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "Heroic Strike", nil)
    eq(ST.hs_queued, false, "TBC: a name-carrying HS success clears the HS tint")
    eq(sb.bar_color_calls, 1, "TBC: the HS name clear recolours once")

    ST.cleave_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "cast-guid", "Cleave")
    eq(ST.cleave_queued, false, "TBC: a name-in-id-slot Cleave success clears the Cleave tint")
    eq(sb.bar_color_calls, 1, "TBC: the Cleave name clear recolours once")

    ST.hs_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "cast-3", 29707)
    eq(ST.hs_queued, false, "TBC: a numeric id still clears the HS tint")
    eq(sb.bar_color_calls, 1, "TBC: the HS id clear recolours once")

    -- The quiet-failure path rides the same matcher.
    ST.hs_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_failed_quiet(ST, "target", "Heroic Strike", nil)
    eq(ST.hs_queued, false, "TBC: a name-carrying quiet HS failure clears the tint")
    eq(sb.bar_color_calls, 1, "TBC: the quiet HS name clear recolours once")

    -- A foreign name must change nothing.
    ST.hs_queued = true
    ST.cleave_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_succeeded(ST, "target", "Scare Beast", nil)
    eq(ST.hs_queued, true, "TBC: an unrelated name leaves the HS tint alone")
    eq(ST.cleave_queued, true, "TBC: an unrelated name leaves the Cleave tint alone")
    eq(sb.bar_color_calls, 0, "TBC: an unrelated name triggers no recolour")
end

do
    -- Era quiet-failure path rides the same matcher.
    local sb = build({ project = 2, known = { [25286] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.hs_queued = true
    sb.bar_color_calls = 0
    ST.WARRIOR.on_spellcast_failed_quiet(ST, "target", "cast-4", 25286)
    eq(ST.hs_queued, false, "Era: a numeric-id quiet HS failure clears the tint")
    eq(sb.bar_color_calls, 1, "Era: the quiet HS id clear recolours once")
end

if failures == 0 then
    print("PASS  warrior_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  warrior_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end