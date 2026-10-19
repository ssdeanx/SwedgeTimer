-- tests/warrior_state.lua: offline tests for the warrior module (classes/warrior.lua)
-- over the real compat.lua + utils.lua in a sandbox.
-- Pins the pre-init guards, the rage-cost evaluation and its colour reset, the negative
-- rank latch, Heroic Strike / Cleave spell-table hygiene, the Cleave option gate, the
-- Blood Surge glow state-change guard, the on-next-attack colour matrix, and the warrior
-- tracker set: the target debuff bars (id / localized-name / literal-name matching, the
-- caster filter, throttled merged scan, cached restack, glow and stack-count rendering),
-- the Shield Block bar, the Slam cast bar and the Overpower proc window (pure helpers,
-- CLEU arming, clear-on-cast, option gates and absent-data inertness).
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
        auras = {},               -- [{ name, id }] returned by UnitAura for "player"
        target_auras = {},        -- [{ name, id, count, duration, expiration, source }] for "target"
        cast_live = nil,          -- { name, spell_id, start_ms, end_ms } for UnitCastingInfo
        -- call counters
        get_family_spell_id_calls = 0,
        get_spell_info_calls = 0,
        cost_queries = 0,
        is_current_spell_calls = 0,
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
    -- Spell knowledge for the spec/rune/talent probes (Mortal Strike = arms,
    -- Raging Blow / Consumed by Rage = SoD, Bladestorm talented): the same
    -- known set that answers GetSpellInfo above, so the two never disagree.
    -- Mirrored into _G with the other stubs for the duration of the compat
    -- load (compat resolves IsSpellKnown dynamically through _G).
    env.IsSpellKnown = function(id)
        return sb.known[id] == true
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

    -- The classic-line combat log gate covers PALADIN + WARRIOR and the handler keeps
    -- both dispatch chains, with the init guard intact.
    local main_src = read("main.lua")
    local gate = main_src:match(
        "if %(self%.player_class == \"PALADIN\" or self%.player_class == \"WARRIOR\"%)[^\n]*")
    check(gate ~= nil and gate:find("not st%.is_mainline") ~= nil,
        "the CLEU registration gate covers PALADIN + WARRIOR on the classic line only")

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

if failures == 0 then
    print("PASS  warrior_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  warrior_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end