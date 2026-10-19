-- tests/druid_state.lua: offline tests for the druid module (classes/druid.lua)
-- over the real compat.lua + utils.lua + druid_energy.lua in a sandbox.
-- Pins the post_init / on_combat_exit lifecycle hooks, the rage-cost evaluation and its
-- colour reset, the negative rank latch, the Maul option gate, the spellcast hooks and
-- the form-colour matrix, plus the tracker port: the energy tick anchor/fraction on the
-- per-frame hook, the form-label mapping and the throttled Mangle/Rip/Rake target scan
-- with its option gates, glow boundary and restacking.
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
-- loaded into it, then classes/druid.lua on top. Sandboxes are independent because the
-- module's resolved-rank cache is a file-scoped local: only a fresh load can re-exercise
-- the "resolve on first use" path.
local function build(opts)
    opts = opts or {}

    -- Mutable fixture state, shared with the stub closures.
    local sb = {
        clock = 0,
        power = 0,
        power_type = 0,           -- what UnitPowerType reports (3 = cat energy, 1 = bear)
        rage_cost = nil,          -- what GetSpellPowerCost returns (nil = no cost data)
        known = opts.known or {}, -- spell ids this client knows
        -- Spell names this client knows (knowledge-level, for the SoD rune probe).
        known_names = opts.known_names or {},
        current_spell = opts.current_spell, -- the only id IsCurrentSpell answers true for
        form = 0,                 -- what GetShapeshiftForm reports
        talents = opts.talents or {}, -- talent index -> rank (11 = moonkin, 19 = tree)
        target_auras = opts.target_auras or {}, -- what UnitAura("target", i) serves
        player_auras = opts.player_auras or {}, -- what UnitAura("player", i) serves
        -- call counters
        get_family_spell_id_calls = 0,
        get_spell_info_calls = 0,
        cost_queries = 0,
        is_current_spell_calls = 0,
        bar_color_calls = 0,
        set_vertex_calls = 0,
        talent_info_calls = 0,
        form_visibility_calls = 0,
        -- tracker counters (the druid tracker port: one shared UnitPower/UnitPowerType
        -- read per mainhand frame, plus the throttled target aura scan)
        unit_power_calls = 0,
        unit_power_type_calls = 0,
        unit_aura_calls = 0,
        target_aura_calls = 0,
        -- last observed values
        last_cost_id = nil,
        last_hand = nil,
        vertex = nil,
        -- Cooldown readings by query (id or name) -> { start, duration }.
        cooldowns_by_query = opts.cooldowns or {},
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
        if type(id) == "string" then
            -- Knowledge-level: a name answers only for a known spell.
            if sb.known_names[id] then
                return id, nil, 1, 0, 0, 0, 0
            end
            return nil
        end
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
    -- Knowledge-level id probe (compat resolves IsSpellKnown dynamically
    -- through _G, like the warrior/shaman fixtures): only known ids answer.
    env.IsSpellKnown = function(id)
        if sb.known[id] then
            return true
        end
        return nil
    end
    if not opts.no_unit_power then
        env.UnitPower = function()
            sb.unit_power_calls = sb.unit_power_calls + 1
            return sb.power
        end
    end
    env.UnitPowerType = function()
        sb.unit_power_type_calls = sb.unit_power_type_calls + 1
        return sb.power_type
    end
    env.UnitAura = function(unit, index, filter)
        sb.unit_aura_calls = sb.unit_aura_calls + 1
        if unit == "player" then
            local pentry = sb.player_auras[index]
            if not pentry then return nil end
            return pentry.name, nil, pentry.count, nil, pentry.duration,
                pentry.expiration, pentry.source, nil, nil, pentry.spell_id
        end
        if unit ~= "target" then
            return nil
        end
        sb.target_aura_calls = sb.target_aura_calls + 1
        local entry = sb.target_auras[index]
        if not entry then return nil end
        return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
            entry.source, nil, nil, entry.spell_id
    end
    env.IsCurrentSpell = function(id)
        sb.is_current_spell_calls = sb.is_current_spell_calls + 1
        return id == sb.current_spell
    end
    env.GetShapeshiftForm = function() return sb.form end
    -- Cooldown readings by query (id or name) -> { start, duration }; the default
    -- 0,0 is exactly what compat's no-probe fallback reports, so adding the stub
    -- leaves every pre-existing expectation untouched.
    env.GetSpellCooldown = function(query)
        local entry = sb.cooldowns_by_query[query]
        if entry then
            return entry[1], entry[2], 1, 1
        end
        return 0, 0, 0, 0
    end
    -- Classic GetTalentInfo(tab, index) -> name, icon, tier, column, rank, maxRank.
    env.GetTalentInfo = function(_, index)
        return "Talent", nil, 1, 1, (sb.talents[index] or 0), 1
    end

    -- compat.lua reads some legacy globals through _G (annotation-safe on Mainline-code
    -- clients); mirror the stubs for the duration of its load, then restore _G exactly.
    local mirrored = {}
    for name, value in pairs(env) do
        mirrored[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
        _G[name] = value
    end

    local st = {}
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)

    for name, previous in pairs(mirrored) do
        _G[name] = previous.value
        if not previous.present then _G[name] = nil end
    end

    -- The addon object: only the surface classes/druid.lua touches.
    local ST = { DRUID = {} }
    -- The real DRUID defaults (config_presets.lua), so a wrong colour is a module bug
    -- and not a fixture bug.
    local class_db = {
        enable_maul_color = true,
        maul_color = { 112, 19, 189, 1.0 },
        insufficient_rage_color = { 140, 140, 140, 1.0 },
        form_vis_normal = true,
        form_vis_bear = true,
        form_vis_cat = true,
        form_vis_moonkin = true,
        form_vis_tree = true,
        form_vis_travel = true,
        form_vis_flight = true,
        use_form_colors = true,
        form_color_bear = { 159, 4, 44, 1.0 },
        form_color_cat = { 189, 126, 9, 1.0 },
        form_color_moonkin = { 4, 148, 214, 1.0 },
        form_color_tree = { 4, 204, 124, 1.0 },
        form_color_travel = { 18, 85, 201, 1.0 },
        form_color_flight = { 18, 85, 201, 1.0 },
    }
    -- Texture/fontstring stubs recording what the tracker widgets draw, so positions,
    -- sizes, colours and visibility can be asserted without a real frame.
    local function make_texture()
        local t = { hidden = true }
        function t:SetDrawLayer() end
        function t:SetColorTexture(r, g, b, a) t.base_color = { r, g, b, a } end
        function t:SetWidth(w) t.width = w end
        function t:SetHeight(h) t.height = h end
        function t:SetPoint(point, anchor, rel_point, x, y)
            t.point, t.anchor, t.rel_point, t.offset, t.offset_y = point, anchor, rel_point, x, y
        end
        function t:ClearAllPoints()
            t.point, t.anchor, t.rel_point, t.offset, t.offset_y = nil, nil, nil, nil, nil
        end
        function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
        function t:Hide() t.hidden = true end
        function t:Show() t.hidden = false end
        function t:IsShown() return not t.hidden end
        return t
    end
    local function make_fontstring()
        local f = { hidden = true }
        function f:SetPoint(point, anchor, rel_point, x, y)
            f.point, f.anchor, f.rel_point, f.offset, f.offset_y = point, anchor, rel_point, x, y
        end
        function f:SetJustifyH() end
        function f:SetFont(font_path, size, flags) f.font = { font_path, size, flags } end
        function f:SetText(text) f.text = text end
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
    ST.player_class = "DRUID"
    ST.interfaces_are_initialised = false
    -- main.lua sets both of these in on_init, before any bar frame exists.
    ST.form_index = 0
    ST.is_cat_or_bear = false
    ST.should_show_bar_this_form = true
    ST.get_class_table = function() return class_db end
    ST.get_visuals_frame = function()
        if opts.no_visuals then return nil end
        return visuals
    end
    -- bars.lua's accessor, mirrored: the tracker widgets size against the live bar.
    ST.get_bar_visuals_width_and_height = function() return 100, 20 end
    -- main.lua declares this as a method (ST:convert_color), so the leading self must be
    -- swallowed here too.
    ST.convert_color = function(_, t, new_alpha)
        local r, g, b, a = unpack(t)
        a = new_alpha or a
        return r / 255, g / 255, b / 255, a
    end
    -- main.lua mirrors these two (the Wrath-only talent positions and the form
    -- visibility flag); same bodies, plus call counters so the mainhand-only placement
    -- of the refresh is observable.
    local talent_positions = {
        WRATH = { moonkin = { 1, 11 }, tree_of_life = { 3, 19 } },
    }
    ST.get_druid_talent_info = function()
        sb.talent_info_calls = sb.talent_info_calls + 1
        local positions = talent_positions[st.family]
        if not positions then
            ST.has_moonkin = false
            ST.has_tree_of_life = false
            return
        end
        ST.has_moonkin = select(5, st.api.GetTalentInfo(
            positions.moonkin[1], positions.moonkin[2])) == 1
        ST.has_tree_of_life = select(5, st.api.GetTalentInfo(
            positions.tree_of_life[1], positions.tree_of_life[2])) == 1
    end
    ST.determine_form_visibility_flag = function()
        sb.form_visibility_calls = sb.form_visibility_calls + 1
        local i = st.api.GetShapeshiftForm()
        local db = class_db
        ST.should_show_bar_this_form = false
        if i == 0 and db.form_vis_normal then
            ST.should_show_bar_this_form = true
        elseif i == 1 and db.form_vis_bear then
            ST.should_show_bar_this_form = true
        elseif i == 4 and db.form_vis_travel then
            ST.should_show_bar_this_form = true
        elseif i == 3 and db.form_vis_cat then
            ST.should_show_bar_this_form = true
        elseif i == 5 and db.form_vis_moonkin and ST.has_moonkin then
            ST.should_show_bar_this_form = true
        elseif i == 5 and db.form_vis_tree and ST.has_tree_of_life then
            ST.should_show_bar_this_form = true
        elseif i == 5 and (not ST.has_moonkin and not ST.has_tree_of_life) and db.form_vis_flight then
            ST.should_show_bar_this_form = true
        elseif i == 6 and db.form_vis_flight then
            ST.should_show_bar_this_form = true
        end
    end
    -- bars.lua dispatches the class hook as ST[player_class].set_bar_color(ST, hand);
    -- mirror that, recording every dispatch so "recolours only on a state change" is
    -- observable.
    ST.set_bar_color = function(self, hand)
        sb.bar_color_calls = sb.bar_color_calls + 1
        sb.last_hand = hand
        return ST.DRUID.set_bar_color(self, hand)
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

    -- Count resolver calls: the module calls api.get_family_spell_id through the api table,
    -- so wrapping the table entry after load is enough.
    local real_resolver = st.api.get_family_spell_id
    st.api.get_family_spell_id = function(ids)
        sb.get_family_spell_id_calls = sb.get_family_spell_id_calls + 1
        return real_resolver(ids)
    end

    -- The pure druid maths module loads before the class module (as the TOCs order it).
    local energy = assert(loadfile(ROOT .. "druid_energy.lua"))
    setfenv(energy, env)
    energy("SwedgeTimer", st)

    local mod = assert(loadfile(ROOT .. "classes/druid.lua"))
    setfenv(mod, env)
    mod("SwedgeTimer", st)

    sb.st = st
    sb.ST = ST
    sb.class_db = class_db
    sb.visuals = visuals
    sb.druid_energy = st.druid_energy
    return sb
end

--=========================================================================================
-- 0) The module loads and exposes every hook
--=========================================================================================
local base = build()
check(type(base.ST.DRUID) == "table", "classes/druid.lua loads and defines ST.DRUID")
for _, hook in ipairs({
    "on_rage_update", "on_spellcast_failed_quiet", "on_spellcast_succeeded",
    "on_current_spell_cast_changed", "post_init", "on_combat_exit", "set_bar_color",
}) do
    check(type(base.ST.DRUID[hook]) == "function", "DRUID." .. hook .. " is defined")
end

--=========================================================================================
-- 1) post_init settles every flag the module reads before its first event
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    eq(ST.maul_queued, nil, "a fresh sandbox starts with no maul_queued")
    eq(ST.insufficient_rage, nil, "a fresh sandbox starts with no insufficient_rage")

    ST.DRUID.post_init(ST)
    eq(ST.maul_queued, false, "post_init settles maul_queued")
    eq(ST.insufficient_rage, false, "post_init settles insufficient_rage")

    -- A settled state means the first power tick cannot emit a spurious recolour.
    ST.interfaces_are_initialised = true
    sb.rage_cost = { { cost = 10 } }
    sb.power = 20
    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_rage_update(ST)
    eq(ST.insufficient_rage, false, "20 rage >= 10 cost after post_init -> sufficient")
    eq(sb.bar_color_calls, 0, "post_init leaves the bar idle on the first tick")
end

--=========================================================================================
-- 2) Pre-init safety: every hook runs with no init and no visuals frame
--=========================================================================================
-- 2a) The real pre-init state: nothing queued yet, so no hook may reach for the bar
--     texture that does not exist yet.
do
    local sb = build({ no_visuals = true })
    local ST = sb.ST
    ST.interfaces_are_initialised = false
    eq(ST.maul_queued, nil, "the pre-init sandbox starts with no queue flags")

    local hooks = {
        -- A real cast guid, never nil: # on a table with an embedded nil is
        -- implementation-defined in Lua 5.1, so the arg lists stay hole-free.
        { "on_spellcast_succeeded", { "target", "cast-1", 48480 } },
        { "on_spellcast_failed_quiet", { "target", "cast-1", 48480 } },
        { "on_current_spell_cast_changed", { false } },
        { "set_bar_color", { "mainhand" } },
        { "on_rage_update", {} },
        { "on_combat_exit", {} },
        { "post_init", {} },
        { "on_bar_update", { "mainhand" } },
    }
    for _, entry in ipairs(hooks) do
        for pass = 1, 2 do
            local ok, err = pcall(ST.DRUID[entry[1]], ST, unpack(entry[2]))
            check(ok, "pre-init " .. entry[1] .. " (pass " .. pass .. ") does not error ("
                .. tostring(err) .. ")")
        end
    end

    -- Nothing queued means nothing painted: the guards fire before any frame access.
    eq(sb.bar_color_calls, 4, "only the two spellcast clear paths dispatch a recolour (2 hooks x 2 passes)")
    eq(sb.set_vertex_calls, 0, "a pre-init dispatch with nothing queued paints nothing")

    -- Without a visuals frame the tracker path is inert before it reads any unit state.
    eq(sb.unit_power_calls, 0, "no visuals frame: on_bar_update performs no power reads")
    eq(sb.unit_power_type_calls, 0, "no visuals frame: no power-type reads")
    eq(sb.unit_aura_calls, 0, "no visuals frame: no aura reads")
end

-- 2b) Dirty flags carried into combat exit, still before init and still no visuals frame.
do
    local sb = build({ no_visuals = true, known = { [48480] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = false
    ST.maul_queued = true
    ST.insufficient_rage = true
    sb.rage_cost = { { cost = 30 } }
    sb.power = 0

    local ok, err = pcall(ST.DRUID.on_combat_exit, ST)
    check(ok, "pre-init combat exit with dirty flags does not error (" .. tostring(err) .. ")")
    eq(ST.maul_queued, false, "pre-init combat exit clears maul_queued")
    eq(ST.insufficient_rage, false, "pre-init combat exit clears insufficient_rage")
    eq(sb.bar_color_calls, 0, "pre-init combat exit skips the recolour (no init, no frame)")

    -- An unchanged rage reading must not dispatch a recolour either.
    ST.maul_queued = true
    ST.insufficient_rage = true
    local ok2, err2 = pcall(ST.DRUID.on_rage_update, ST)
    check(ok2, "an unchanged pre-init rage reading does not error (" .. tostring(err2) .. ")")
    eq(ST.insufficient_rage, true, "0 rage < 30 cost stays insufficient")
    eq(sb.bar_color_calls, 0, "an unchanged reading dispatches no recolour pre-init")
end

--=========================================================================================
-- 3) Rage state: cost vs current power, and the colour reset when it changes
--=========================================================================================
do
    local sb = build({ known = { [48480] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }

    sb.power = 5
    ST.DRUID.on_rage_update(ST)
    eq(sb.last_cost_id, 48480, "the queued Maul rank is the cost that gets queried")
    eq(ST.insufficient_rage, true, "5 rage < 10 cost -> insufficient")
    eq(sb.bar_color_calls, 1, "going insufficient recolours the bar")
    eq(sb.last_hand, "mainhand", "the recolour targets the mainhand bar")

    sb.power = 20
    ST.DRUID.on_rage_update(ST)
    eq(ST.insufficient_rage, false, "20 rage >= 10 cost -> sufficient")
    eq(sb.bar_color_calls, 2, "going sufficient recolours the bar back (colour-reset path)")

    -- Third tick with no state change: UNIT_POWER_FREQUENT fires several times a second.
    ST.DRUID.on_rage_update(ST)
    eq(ST.insufficient_rage, false, "an unchanged reading keeps the flag false")
    eq(sb.bar_color_calls, 2, "an unchanged reading does not recolour again")

    -- Nothing queued: a stale insufficient colour must be dropped.
    ST.maul_queued = false
    ST.insufficient_rage = true
    sb.bar_color_calls = 0
    ST.DRUID.on_rage_update(ST)
    eq(ST.insufficient_rage, false, "no queued Maul clears a stale insufficient flag")
    eq(sb.bar_color_calls, 1, "clearing the stale flag recolours once")

    sb.power = 0
    sb.bar_color_calls = 0
    ST.DRUID.on_rage_update(ST)
    eq(sb.bar_color_calls, 0, "idle rage ticks stay silent")
end

--=========================================================================================
-- 4) No cost data: unknown rank, or a client that cannot read costs
--=========================================================================================
do
    -- 4a) A client where no Maul rank resolves: the cost must never be queried and the
    -- state degrades to "sufficient" instead of claiming a shortage.
    local sb = build({ known = {} })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    ST.insufficient_rage = true
    sb.rage_cost = { { cost = 10 } }
    local ok, err = pcall(ST.DRUID.on_rage_update, ST)
    check(ok, "an unresolvable Maul rank does not error (" .. tostring(err) .. ")")
    eq(sb.cost_queries, 0, "an unresolvable rank never queries a spell cost")
    eq(ST.insufficient_rage, false, "an unresolvable rank degrades to sufficient")
end

do
    -- 4b) A rank resolves but GetSpellPowerCost returns nil (no cost data).
    local sb = build({ known = { [48480] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    ST.insufficient_rage = true
    sb.rage_cost = nil
    sb.power = 0
    local ok, err = pcall(ST.DRUID.on_rage_update, ST)
    check(ok, "a nil cost table does not error (" .. tostring(err) .. ")")
    eq(sb.cost_queries, 1, "the cost query still runs when the rank is known")
    eq(ST.insufficient_rage, false, "no cost data never claims insufficient rage")

    -- A cost entry without a numeric cost (secret value on a modern client) degrades too.
    sb.rage_cost = { { cost = "<secret>" } }
    local ok2, err2 = pcall(ST.DRUID.on_rage_update, ST)
    check(ok2, "a non-numeric cost does not error (" .. tostring(err2) .. ")")
    eq(ST.insufficient_rage, false, "a non-numeric cost degrades to sufficient")

    -- A non-numeric power reading degrades the same way instead of erroring.
    sb.rage_cost = { { cost = 10 } }
    sb.power = "<secret>"
    local ok3, err3 = pcall(ST.DRUID.on_rage_update, ST)
    check(ok3, "a non-numeric power reading does not error (" .. tostring(err3) .. ")")
    eq(ST.insufficient_rage, false, "a non-numeric power reading degrades to sufficient")
end

--=========================================================================================
-- 5) api.UnitPower absent entirely: the compat fallback keeps the comparison safe
--=========================================================================================
do
    local sb = build({ known = { [48480] = true }, no_unit_power = true })
    local ST = sb.ST
    check(type(sb.st.api.UnitPower) == "function", "compat provides an api.UnitPower fallback")
    eq(sb.st.api.UnitPower("player"), 0, "the fallback reports 0 rage")

    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }
    local ok, err = pcall(ST.DRUID.on_rage_update, ST)
    check(ok, "a missing UnitPower global does not error (" .. tostring(err) .. ")")
    eq(ST.insufficient_rage, true, "0 rage from the fallback is compared against the cost")
end

--=========================================================================================
-- 6) Rank latch: the resolver runs once, and a negative result stays latched
--=========================================================================================
do
    local sb = build({ known = {} })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }

    ST.DRUID.on_rage_update(ST)
    eq(sb.get_family_spell_id_calls, 1, "the first rage tick resolves the rank")
    ST.DRUID.on_rage_update(ST)
    ST.DRUID.on_rage_update(ST)
    eq(sb.get_family_spell_id_calls, 1, "a negative result is latched: no re-walk per tick")
    eq(ST.insufficient_rage, false, "latched false keeps the bar out of the rage colour")
end

do
    local sb = build({ known = { [48480] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }

    ST.DRUID.on_rage_update(ST)
    check(sb.get_spell_info_calls > 0, "the first tick walks the rank table once")
    local after_first = sb.get_spell_info_calls
    ST.DRUID.on_rage_update(ST)
    eq(sb.get_spell_info_calls, after_first, "a positive rank is cached: no re-scan per tick")
end

do
    -- The rank table must resolve the highest id the client knows (WotLK) and the only
    -- id it knows (vanilla rank 1), otherwise the latch would lock in the wrong cost.
    local sb = build({ known = { [6807] = true, [8972] = true, [48479] = true, [48480] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    ST.insufficient_rage = false
    sb.rage_cost = { { cost = 10 } }
    ST.DRUID.on_rage_update(ST)
    eq(sb.last_cost_id, 48480, "the highest known Maul rank is the one queried")

    local sb2 = build({ known = { [6807] = true } })
    local ST2 = sb2.ST
    ST2.interfaces_are_initialised = true
    ST2.maul_queued = true
    ST2.insufficient_rage = false
    sb2.rage_cost = { { cost = 10 } }
    ST2.DRUID.on_rage_update(ST2)
    eq(sb2.last_cost_id, 6807, "a client that only knows rank 1 resolves rank 1")
end

--=========================================================================================
-- 7) Option gating: the Maul colour off must stop the probe and the flag
--=========================================================================================
do
    local sb = build({ known = { [48480] = true }, current_spell = 48480 })
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    -- Option off: a queued Maul on the client must not be probed at all.
    sb.class_db.enable_maul_color = false
    sb.is_current_spell_calls = 0
    local ok, err = pcall(ST.DRUID.on_current_spell_cast_changed, ST, false)
    check(ok, "the Maul option gate does not error (" .. tostring(err) .. ")")
    eq(ST.maul_queued, nil, "a queued Maul is ignored while its colour is disabled")
    eq(sb.is_current_spell_calls, 0, "a disabled Maul colour means no IsCurrentSpell probe")

    -- Option on: the queued Maul is picked up.
    sb.class_db.enable_maul_color = true
    sb.is_current_spell_calls = 0
    ST.DRUID.on_current_spell_cast_changed(ST, false)
    eq(ST.maul_queued, true, "a queued Maul sets maul_queued once enabled")
    eq(sb.last_hand, "mainhand", "queuing Maul recolours the mainhand bar")
    check(sb.is_current_spell_calls > 0, "the Maul table is probed when the option is on")

    -- A queued spell of another class clears a stale maul_queued.
    sb.current_spell = 12345
    ST.DRUID.on_current_spell_cast_changed(ST, false)
    eq(ST.maul_queued, false, "an unrelated spell clears a stale maul_queued")
end

--=========================================================================================
-- 8) Combat exit wipes the queued Maul state
--=========================================================================================
do
    local sb = build({ known = { [48480] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    ST.insufficient_rage = true
    sb.rage_cost = { { cost = 30 } }

    ST.DRUID.on_combat_exit(ST)
    eq(ST.maul_queued, false, "combat exit clears maul_queued")
    eq(ST.insufficient_rage, false, "combat exit clears insufficient_rage")
    eq(sb.bar_color_calls, 1, "combat exit recolours once after init")
end

--=========================================================================================
-- 9) The spellcast hooks clear the queue they own, and nothing else
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    ST.maul_queued = true
    ST.DRUID.on_spellcast_succeeded(ST, "target", "cast-1", 48480)
    eq(ST.maul_queued, false, "a landed Maul clears maul_queued")

    ST.maul_queued = true
    ST.DRUID.on_spellcast_failed_quiet(ST, "target", "cast-1", 9881)
    eq(ST.maul_queued, false, "a failed Maul clears maul_queued")

    sb.bar_color_calls = 0
    ST.maul_queued = true
    ST.DRUID.on_spellcast_succeeded(ST, "target", "cast-1", 12345)
    eq(ST.maul_queued, true, "an unrelated spell id leaves maul_queued alone")
    eq(sb.bar_color_calls, 0, "an unrelated spell id does not recolour")

    ST.DRUID.on_spellcast_failed_quiet(ST, "target", "cast-1", nil)
    eq(ST.maul_queued, true, "a nil spell id is ignored")
    eq(sb.bar_color_calls, 0, "a nil spell id does not recolour")
end

--=========================================================================================
-- 10) The colour matrix: Maul / insufficient rage, and the form colours
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true

    -- Offhand is never a class override, and must not run the form refresh.
    ST.maul_queued = true
    ST.insufficient_rage = true
    sb.talent_info_calls = 0
    sb.form_visibility_calls = 0
    eq(ST.DRUID.set_bar_color(ST, "offhand"), false, "the offhand bar returns false")
    eq(sb.talent_info_calls, 0, "the offhand bar skips get_druid_talent_info")
    eq(sb.form_visibility_calls, 0, "the offhand bar skips determine_form_visibility_flag")

    -- Maul queued and enabled -> the configured Maul colour.
    ST.insufficient_rage = false
    sb.vertex = nil
    eq(ST.DRUID.set_bar_color(ST, "mainhand"), true, "a queued Maul claims the bar colour")
    colour_eq(sb.vertex, sb.class_db.maul_color, "a queued Maul paints the Maul colour")
    eq(sb.talent_info_calls, 1, "the mainhand bar refreshes the druid talent flags")
    eq(sb.form_visibility_calls, 1, "the mainhand bar refreshes the form visibility flag")

    -- Queued but short of rage -> the insufficient-rage colour wins.
    ST.insufficient_rage = true
    sb.vertex = nil
    eq(ST.DRUID.set_bar_color(ST, "mainhand"), true, "a queued but unaffordable Maul claims the bar colour")
    colour_eq(sb.vertex, sb.class_db.insufficient_rage_color, "short of rage paints the insufficient-rage colour")

    -- Nothing queued -> hand the bar back to the default behaviour (no form, form 0).
    ST.maul_queued = false
    ST.insufficient_rage = false
    sb.vertex = nil
    eq(ST.DRUID.set_bar_color(ST, "mainhand"), false, "an idle druid in no form returns false (default colour)")

    -- Option off -> the queued Maul is not a colour override at all.
    ST.maul_queued = true
    sb.class_db.enable_maul_color = false
    sb.vertex = nil
    eq(ST.DRUID.set_bar_color(ST, "mainhand"), false, "a disabled Maul colour returns false")

    -- A disabled Maul colour still shows insufficient rage.
    ST.insufficient_rage = true
    sb.vertex = nil
    eq(ST.DRUID.set_bar_color(ST, "mainhand"), true, "a disabled Maul colour still shows insufficient rage")
    colour_eq(sb.vertex, sb.class_db.insufficient_rage_color, "a disabled Maul colour still paints insufficient rage")
end

do
    -- The form matrix, with six distinct sentinel colours so each branch is
    -- unambiguous (the shipped travel and flight colours are identical, which would
    -- otherwise let a wrong branch pass).
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = false
    ST.insufficient_rage = false
    local db = sb.class_db
    db.enable_maul_color = true
    db.use_form_colors = true
    local sentinels = {
        form_color_bear = { 10, 10, 10, 1.0 },
        form_color_travel = { 20, 20, 20, 1.0 },
        form_color_cat = { 30, 30, 30, 1.0 },
        form_color_moonkin = { 40, 40, 40, 1.0 },
        form_color_tree = { 50, 50, 50, 1.0 },
        form_color_flight = { 60, 60, 60, 1.0 },
    }
    for key, value in pairs(sentinels) do db[key] = value end

    local cases = {
        { 1, {}, sentinels.form_color_bear, "bear form paints the bear colour" },
        { 3, {}, sentinels.form_color_cat, "cat form paints the cat colour" },
        { 4, {}, sentinels.form_color_travel, "travel form paints the travel colour" },
        { 5, { [11] = 1 }, sentinels.form_color_moonkin, "moonkin form paints the moonkin colour" },
        { 5, { [19] = 1 }, sentinels.form_color_tree, "tree form paints the tree colour" },
        { 5, {}, sentinels.form_color_flight, "flight form (no moonkin/tree talent) paints the flight colour" },
        { 6, {}, sentinels.form_color_flight, "flight form 6 paints the flight colour" },
    }
    for _, case in ipairs(cases) do
        sb.form = case[1]
        sb.talents = case[2]
        ST.form_index = case[1]
        sb.vertex = nil
        eq(ST.DRUID.set_bar_color(ST, "mainhand"), true, case[4])
        colour_eq(sb.vertex, case[3], case[4])
    end

    -- The queued Maul colour outranks every form colour.
    sb.form = 1
    sb.talents = {}
    ST.form_index = 1
    ST.maul_queued = true
    ST.insufficient_rage = false
    sb.vertex = nil
    eq(ST.DRUID.set_bar_color(ST, "mainhand"), true, "a queued Maul outranks the bear form colour")
    colour_eq(sb.vertex, db.maul_color, "a queued Maul paints over the form colour")

    -- use_form_colors = false bypasses the whole matrix.
    ST.maul_queued = false
    db.use_form_colors = false
    for _, form in ipairs({ 1, 3, 4, 5, 6 }) do
        sb.form = form
        ST.form_index = form
        sb.vertex = nil
        eq(ST.DRUID.set_bar_color(ST, "mainhand"), false,
            "use_form_colors = false bypasses form " .. tostring(form))
    end

    -- The shipped defaults, so a fixture change cannot hide a wrong shipped colour.
    db.use_form_colors = true
    db.form_color_bear = { 159, 4, 44, 1.0 }
    sb.form = 1
    ST.form_index = 1
    sb.vertex = nil
    eq(ST.DRUID.set_bar_color(ST, "mainhand"), true, "the shipped bear colour claims the bar")
    colour_eq(sb.vertex, { 159, 4, 44, 1.0 }, "the shipped bear colour is painted")
end

--=========================================================================================
-- 11) The form refresh only runs where it can matter, and stays pre-init safe
--=========================================================================================
do
    local sb = build({ no_visuals = true, known = { [48480] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = false
    -- No form (index 0) so no colour branch matches: a pre-init dispatch must still
    -- reach the refresh and stop there, without touching the missing visuals frame.
    sb.form = 0
    sb.talents = { [11] = 1 }
    ST.form_index = 0

    local ok, err = pcall(ST.DRUID.set_bar_color, ST, "mainhand")
    check(ok, "a pre-init mainhand colour dispatch does not error (" .. tostring(err) .. ")")
    eq(sb.set_vertex_calls, 0, "a pre-init mainhand dispatch paints nothing")
    eq(ST.has_moonkin, true, "the mainhand refresh picks the moonkin talent up")
    eq(ST.should_show_bar_this_form, true, "the mainhand refresh still computes the form visibility flag")

    -- A non-Wrath client has no talent positions: both flags must settle to false
    -- rather than erroring.
    local sb2 = build({ project = 2 })
    local ST2 = sb2.ST
    local ok2, err2 = pcall(ST2.DRUID.set_bar_color, ST2, "mainhand")
    check(ok2, "the refresh on a non-Wrath client does not error (" .. tostring(err2) .. ")")
    eq(ST2.has_moonkin, false, "a non-Wrath client settles has_moonkin to false")
    eq(ST2.has_tree_of_life, false, "a non-Wrath client settles has_tree_of_life to false")
    eq(ST2.should_show_bar_this_form, true, "the non-Wrath form refresh still runs")
end

--=========================================================================================
-- 12) Druid trackers: the cat-form energy tick bar
--=========================================================================================
-- The anchor reset cannot ride main.lua's UNIT_POWER_FREQUENT dispatch (RAGE-only, see
-- main.lua:925-937), so the per-frame hook samples the live power value - the same read
-- the reference's render hook performs. The pure maths is pinned in druid_energy_state.
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    check(vf.druid_energy_tick_bg ~= nil, "post_init creates the energy tick backing")
    check(vf.druid_energy_tick_fill ~= nil, "post_init creates the energy tick fill")
    eq(vf.druid_energy_tick_bg.width, 4, "the tick column is the reference's 4 px wide")
    eq(vf.druid_energy_tick_bg.point, "BOTTOMLEFT", "the tick column anchors at the bar's bottom-left")
    eq(vf.druid_energy_tick_bg.offset, -6, "the column sits one gap + width left of the bar")

    sb.clock = 100
    sb.power = 40
    sb.power_type = 3
    ST.form_index = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not vf.druid_energy_tick_bg.hidden, "cat form shows the tick column")
    check(not vf.druid_energy_tick_fill.hidden, "the fill shows too")
    near(vf.druid_energy_tick_fill.height, 0, 1e-9, "a fresh anchor starts empty")
    near(vf.druid_energy_tick_bg.height, 20, 1e-9, "the column spans the bar height")

    sb.clock = 100.5
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 20 * 0.25, 1e-9, "the fill follows the 2 s cycle")

    -- A natural tick (+20) re-anchors; the fill restarts from 0.
    sb.clock = 101
    sb.power = 60
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 0, 1e-9, "a +20 gain re-anchors the cycle")
    sb.clock = 101.5
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 5, 1e-9, "the cycle restarts from the gain")

    -- A gain outside the 19-22 window (a refund, a potion) does not re-anchor.
    sb.clock = 102
    sb.power = 78
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 10, 1e-9, "a +18 gain does not re-anchor")

    -- Leaving cat form hides the column; re-entering re-seats the anchor.
    sb.clock = 103
    sb.power_type = 1
    sb.power = 10
    ST.form_index = 1
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_energy_tick_bg.hidden, "bear form hides the tick column")
    check(vf.druid_energy_tick_fill.hidden, "the fill hides with it")
    sb.clock = 104
    sb.power_type = 3
    sb.power = 40
    ST.form_index = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 0, 1e-9, "re-entering cat form re-seats the cycle")

    -- The option off performs no power reads at all and stays hidden.
    sb.class_db.show_druid_energy_tick = false
    sb.unit_power_calls = 0
    sb.clock = 105
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(sb.unit_power_calls, 0, "the option off performs no UnitPower reads")
    check(vf.druid_energy_tick_bg.hidden, "option off hides the tick column")
    check(vf.druid_energy_tick_fill.hidden, "option off hides the fill")

    -- Re-enabling re-seats instead of comparing against the stale baseline.
    sb.class_db.show_druid_energy_tick = true
    sb.clock = 106
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 0, 1e-9, "re-enabling re-seats the anchor")

    -- Colours: the configured table wins; the reference fallback covers a pre-options db.
    sb.class_db.druid_energy_tick_color = { 10, 20, 30, 0.5 }
    ST.DRUID.on_bar_update(ST, "mainhand")
    colour_eq(vf.druid_energy_tick_fill.color, { 10, 20, 30, 0.5 }, "the configured tick colour fills the bar")
    sb.class_db.druid_energy_tick_color = nil
    ST.DRUID.on_bar_update(ST, "mainhand")
    colour_eq(vf.druid_energy_tick_fill.color, { 255, 209, 46, 1.0 },
        "the reference fallback colour covers a missing db key")
end

--=========================================================================================
-- 13) Druid trackers: the mainhand form label
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    check(vf.druid_form_label ~= nil, "post_init creates the form label widget")

    ST.form_index = 3
    sb.power_type = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(vf.druid_form_label.text, "Cat", "energy power type labels the mainhand text Cat")
    check(not vf.druid_form_label.hidden, "the label shows while shapeshifted")

    ST.form_index = 1
    sb.power_type = 1
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(vf.druid_form_label.text, "Bear", "rage power type labels the mainhand text Bear")

    ST.form_index = 5
    sb.power_type = 0
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(vf.druid_form_label.text, "Caster", "mana-powered shapeshifts label the mainhand text Caster")

    -- No form: the overlay hides and the configured text modes are never written to.
    ST.form_index = 0
    sb.power_type = 0
    sb.class_db.left_text_key = "attack_speed"
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_form_label.hidden, "no form: the label hides")
    eq(sb.class_db.left_text_key, "attack_speed", "no form: the configured text mode is untouched")

    -- Option off hides the overlay even while shapeshifted.
    sb.class_db.show_druid_form_label = false
    ST.form_index = 3
    sb.power_type = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_form_label.hidden, "the label option off hides the widget")
end

--=========================================================================================
-- 14) All tracker options off: every widget hides and the frame reads nothing
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    local db = sb.class_db
    db.show_druid_energy_tick = false
    db.show_druid_form_label = false
    db.show_druid_mangle_bar = false
    db.show_druid_rip_bar = false
    db.show_druid_rake_bar = false
    ST.form_index = 3
    sb.power_type = 3
    sb.power = 50
    sb.target_auras = {
        { name = "Rip", spell_id = 1079, source = "player", duration = 12, expiration = 100 },
    }
    sb.unit_power_calls = 0
    sb.unit_power_type_calls = 0
    sb.unit_aura_calls = 0
    sb.target_aura_calls = 0
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(sb.unit_power_calls, 0, "all off: no UnitPower reads")
    eq(sb.unit_power_type_calls, 0, "all off: no UnitPowerType reads")
    eq(sb.unit_aura_calls, 0, "all off: no aura reads at all")
    eq(sb.target_aura_calls, 0, "all off: no target aura scans")
    check(vf.druid_energy_tick_bg.hidden and vf.druid_energy_tick_fill.hidden,
        "all off: the energy tick is hidden")
    check(vf.druid_form_label.hidden, "all off: the form label is hidden")
    for key in pairs(vf.druid_debuff) do
        local bar = vf.druid_debuff[key]
        check(bar.bg.hidden and bar.fill.hidden and bar.glow.hidden and bar.label.hidden,
            "all off: the " .. key .. " debuff bar is hidden")
    end
end

--=========================================================================================
-- 15) Druid trackers: the Mangle / Rip / Rake target debuff bars
--=========================================================================================
do
    -- The known ids let the localized-name resolver answer from the client's own spell
    -- data (the fixture's GetSpellInfo reports "Spell <id>").
    local sb = build({ known = { [33983] = true, [27008] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    local bars = vf.druid_debuff
    check(bars ~= nil and bars.mangle and bars.rip and bars.rake,
        "post_init creates the three debuff bar groups")
    eq(bars.mangle.bg.height, 6, "the Mangle bar is the reference's 6 px tall")
    eq(bars.rake.bg.height, 5, "the Rake bar is the reference's 5 px tall")

    -- Id match: the aura id is in the table regardless of the (localized) name.
    sb.clock = 200
    sb.target_auras = {
        { name = "localized mangle", spell_id = 33983, source = "player", duration = 12, expiration = 208 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not bars.mangle.bg.hidden, "the player's Mangle shows its bar")
    near(bars.mangle.fill.width, 100 * (8 / 12), 1e-6, "the fill shows the remaining fraction")
    eq(bars.mangle.label.text, "8", "the label shows whole seconds")
    check(bars.mangle.glow.hidden, "no glow above the final 4 s")
    eq(bars.mangle.bg.offset_y, 2, "the bottom slot sits just above the bar")
    check(bars.rip.bg.hidden, "absent debuffs stay hidden")

    -- Localized-name match through the resolved spell data (no id on the aura).
    sb.clock = 201
    sb.target_auras = {
        { name = "Spell 27008", source = "player", duration = 12, expiration = 207 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not bars.rip.bg.hidden, "the resolved localized name matches without an id")
    near(bars.rip.fill.width, 100 * (6 / 12), 1e-6, "Rip's fill uses its own duration")

    -- Literal-name fallback.
    sb.clock = 202
    sb.target_auras = {
        { name = "Rake", source = "player", duration = 9, expiration = 207 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not bars.rake.bg.hidden, "the literal English name matches as the fallback")
    eq(bars.rake.label.text, "5", "Rake's label counts its own duration")

    -- A foreign caster's debuff does not qualify.
    sb.clock = 203
    sb.target_auras = {
        { name = "Rip", spell_id = 1079, source = "other", duration = 12, expiration = 215 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(bars.rip.bg.hidden, "another caster's debuff does not show the bar")

    -- Aura gone (target lost / debuff expired): every bar hides.
    sb.clock = 204
    sb.target_auras = {}
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(bars.mangle.bg.hidden and bars.rip.bg.hidden and bars.rake.bg.hidden,
        "no matching auras: all debuff bars hide")

    -- Still-listed but expired: remaining floors at 0 and the glow never shows there.
    sb.clock = 205
    sb.target_auras = {
        { name = "Rip", spell_id = 1079, source = "player", duration = 12, expiration = 204 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not bars.rip.bg.hidden, "an expired-but-listed aura still draws (the reference floors at 0)")
    eq(bars.rip.label.text, "0", "the expired bar reads 0")
    check(bars.rip.glow.hidden, "an expired bar does not glow")

    -- Glow boundary: on at exactly 4 s, off just above it.
    sb.clock = 206
    sb.target_auras = {
        { name = "Rip", spell_id = 1079, source = "player", duration = 12, expiration = 210 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not bars.rip.glow.hidden, "the glow starts at exactly 4 s remaining")
    sb.clock = 206.5
    sb.target_auras[1].expiration = 211
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(bars.rip.glow.hidden, "the glow stays off above 4 s")
end

--=========================================================================================
-- 16) Debuff restacking, throttling and the per-bar option gates
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local bars = sb.visuals.druid_debuff

    sb.clock = 300
    sb.target_auras = {
        { name = "Mangle", source = "player", duration = 12, expiration = 312 },
        { name = "Rip", source = "player", duration = 12, expiration = 312 },
        { name = "Rake", source = "player", duration = 9, expiration = 309 },
    }
    sb.target_aura_calls = 0
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not (bars.mangle.bg.hidden or bars.rip.bg.hidden or bars.rake.bg.hidden),
        "the full stack draws when all three debuffs are up")
    eq(bars.mangle.bg.offset_y, 2, "Mangle occupies the bottom slot")
    eq(bars.rip.bg.offset_y, 10, "Rip stacks above Mangle (6 px + 2 px gap)")
    eq(bars.rake.bg.offset_y, 18, "Rake stacks above Rip")

    local calls_before = sb.target_aura_calls
    sb.clock = 300.01
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(sb.target_aura_calls, calls_before, "the target scan is throttled to 0.05 s")

    -- Only Rip up: it drops to the bottom slot.
    sb.clock = 301
    sb.target_auras = {
        { name = "Rip", source = "player", duration = 12, expiration = 312 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(bars.rip.bg.offset_y, 2, "an alone Rip takes the bottom slot")

    -- One bar off: only that bar hides; the shared scan keeps feeding the others.
    sb.class_db.show_druid_rip_bar = false
    sb.clock = 302
    sb.target_auras = {
        { name = "Mangle", source = "player", duration = 12, expiration = 314 },
        { name = "Rip", source = "player", duration = 12, expiration = 314 },
    }
    calls_before = sb.target_aura_calls
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(bars.rip.bg.hidden, "a disabled bar hides even while the debuff is up")
    check(not bars.mangle.bg.hidden, "its enabled neighbour keeps drawing")
    check(sb.target_aura_calls > calls_before, "the shared scan still runs for the enabled bar")
    sb.class_db.show_druid_rip_bar = true

    -- Colours: the configured table wins; the reference fallback covers a missing key.
    sb.clock = 303
    sb.target_auras = {
        { name = "Mangle", source = "player", duration = 12, expiration = 315 },
        { name = "Rake", source = "player", duration = 9, expiration = 312 },
    }
    sb.class_db.druid_mangle_bar_color = { 10, 20, 30, 0.4 }
    ST.DRUID.on_bar_update(ST, "mainhand")
    colour_eq(bars.mangle.fill.color, { 10, 20, 30, 0.4 }, "the configured Mangle colour fills the bar")
    colour_eq(bars.mangle.glow.color, { 10, 20, 30, 0.4 }, "the glow shares the fill colour")
    colour_eq(bars.rake.fill.color, { 217, 102, 26, 0.90 }, "the reference fallback covers a missing db colour")
end

--=========================================================================================
-- 17) Config and options wiring: the new keys exist in both directions
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local new_toggle_keys = {
        "show_druid_energy_tick", "show_druid_form_label",
        "show_druid_mangle_bar", "show_druid_rip_bar", "show_druid_rake_bar",
    }
    local new_colour_keys = {
        "druid_energy_tick_color", "druid_mangle_bar_color",
        "druid_rip_bar_color", "druid_rake_bar_color",
    }

    local presets = read("config_presets.lua")
    local druid_defaults = presets:match("ST%.DRUID%.defaults%s*=%s*%{(.-)ST%.HUNTER%.defaults")
    check(druid_defaults ~= nil, "the DRUID defaults block is found in config_presets.lua")
    druid_defaults = druid_defaults or ""
    local options = read("option_tables.lua")
    local druid_opts = options:match("function ST%.class_opts_funcs%.DRUID%((.*)$")
    check(druid_opts ~= nil, "the DRUID options function is found in option_tables.lua")
    druid_opts = druid_opts or ""
    for i = 1, #new_toggle_keys do
        local key = new_toggle_keys[i]
        check(druid_defaults:find("%f[%a_]" .. key .. "%s*=%s*true") ~= nil,
            key .. " ships true in the DRUID defaults")
        local widget = druid_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"toggle\"") ~= nil,
            key .. " has a toggle widget in the DRUID options section")
    end
    for i = 1, #new_colour_keys do
        local key = new_colour_keys[i]
        check(druid_defaults:find("%f[%a_]" .. key .. "%s*=%s*{") ~= nil,
            key .. " has a colour default in the DRUID defaults")
        local widget = druid_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"color\"") ~= nil,
            key .. " has a colour widget in the DRUID options section")
    end
end

--=========================================================================================
-- 18) Era family: the Mangle HUD slot draws nothing (the spell does not exist there)
--=========================================================================================
do
    local sb = build({ project = 2 })
    local ST = sb.ST
    eq(sb.st.family, "ERA", "project 2 reports the ERA family")
    local mangle_slot = { key = "mangle", title = "Mangle", kind = "spell", spell = 33878 }
    local s = ST.DRUID.get_hud_state(ST, mangle_slot, 100)
    eq(s.hidden, true, "Era: the Mangle HUD slot is hidden")
    eq(s.remaining, nil, "Era: the hidden slot reports no cooldown")
    eq(s.duration, nil, "Era: the hidden slot reports no duration")
    -- A neighbouring slot is untouched by the gate (and the provider path stays
    -- total: the compat cooldown wrapper degrades to "ready" with no probe).
    local rip_slot = { key = "rip", title = "Rip", kind = "spell", spell = 1079 }
    local r = ST.DRUID.get_hud_state(ST, rip_slot, 100)
    eq(r.hidden, nil, "Era: the Rip HUD slot is not hidden")
    eq(r.remaining, nil, "Era: a ready Rip reports no cooldown")
end

--=========================================================================================
-- 19) TBC family: the Mangle HUD slot stays live (Mangle is TBC+; only Era hides)
--=========================================================================================
do
    local sb = build({ project = 5 })
    local ST = sb.ST
    eq(sb.st.family, "TBC", "project 5 reports the TBC family")
    local mangle_slot = { key = "mangle", title = "Mangle", kind = "spell", spell = 33878 }
    local s = ST.DRUID.get_hud_state(ST, mangle_slot, 100)
    eq(s.hidden, nil, "TBC: the Mangle HUD slot is not hidden")
end

--=========================================================================================
-- 20) SoD shares the ERA token: Mangle spell knowledge keeps the Mangle HUD
--     slot live (id-first and locale-independent, with the name fallback),
--     latched per session like the rank resolvers (each scenario is a fresh
--     sandbox)
--=========================================================================================
do
    local mangle_slot = { key = "mangle", title = "Mangle", kind = "spell", spell = 33878 }
    local era_sb = build({ project = 2 })
    eq(era_sb.st.family, "ERA", "project 2 reports the ERA family")
    local s = era_sb.ST.DRUID.get_hud_state(era_sb.ST, mangle_slot, 100)
    eq(s.hidden, true, "Era: the Mangle HUD slot is hidden without rune knowledge")
    eq(s.remaining, nil, "Era: the hidden slot reports no cooldown")
    eq(s.duration, nil, "Era: the hidden slot reports no duration")
    -- Id knowledge flips with no name answering (the non-enUS client:
    -- GetSpellInfo("Mangle") is nil there, IsSpellKnown(33983) is true).
    local id_sb = build({ project = 2, known = { [33983] = true } })
    eq(id_sb.ST.DRUID.get_hud_state(id_sb.ST, mangle_slot, 100).hidden, nil,
        "SoD: a known Mangle rank keeps the slot live with no name probe")
    -- The second Mangle rank id probes too.
    local id2_sb = build({ project = 2, known = { [33987] = true } })
    eq(id2_sb.ST.DRUID.get_hud_state(id2_sb.ST, mangle_slot, 100).hidden, nil,
        "SoD: the second Mangle rank id probes too")
    -- Name fallback: a rune the module never tracked by id still flips.
    local name_sb = build({ project = 2, known_names = { ["Savage Roar"] = true } })
    eq(name_sb.ST.DRUID.get_hud_state(name_sb.ST, mangle_slot, 100).hidden, nil,
        "SoD: a known Savage Roar keeps the slot live too (name fallback)")
    -- Session latch: forgetting mid-session keeps the slot live until /reload,
    -- while a fresh session without knowledge hides it again.
    name_sb.known_names = {}
    eq(name_sb.ST.DRUID.get_hud_state(name_sb.ST, mangle_slot, 200).hidden, nil,
        "the probe latches per session: forgetting mid-session needs /reload")
    local fresh_sb = build({ project = 2 })
    eq(fresh_sb.ST.DRUID.get_hud_state(fresh_sb.ST, mangle_slot, 100).hidden, true,
        "a fresh session without rune knowledge hides the slot again")
    -- A neighbouring slot is untouched by the gate (and the provider path stays
    -- total: the compat cooldown wrapper degrades to "ready" with no probe).
    local rip_slot = { key = "rip", title = "Rip", kind = "spell", spell = 1079 }
    local r = era_sb.ST.DRUID.get_hud_state(era_sb.ST, rip_slot, 100)
    eq(r.hidden, nil, "Era: the Rip HUD slot is not hidden")
    eq(r.remaining, nil, "Era: a ready Rip reports no cooldown")
end

--=========================================================================================
-- 21) The player-buff scan follows the guide gate: it runs while the guide is
--     enabled (even with every bar off) and reads nothing with the guide off
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local db = sb.class_db
    db.show_druid_energy_tick = false
    db.show_druid_form_label = false
    db.show_druid_mangle_bar = false
    db.show_druid_rip_bar = false
    db.show_druid_rake_bar = false
    db.nextaction_enabled = true
    ST.form_index = 3
    sb.power_type = 3
    sb.power = 50
    sb.target_auras = {}
    sb.unit_aura_calls = 0
    sb.target_aura_calls = 0
    local ok, err = pcall(ST.DRUID.on_bar_update, ST, "mainhand")
    check(ok, "the guide-gated player scan does not error (" .. tostring(err) .. ")")
    check(sb.unit_aura_calls > 0, "guide on, bars off: the player scan still reads auras")
    db.nextaction_enabled = false
    sb.unit_aura_calls = 0
    sb.target_aura_calls = 0
    local ok2, err2 = pcall(ST.DRUID.on_bar_update, ST, "mainhand")
    check(ok2, "the gated-off player scan does not error (" .. tostring(err2) .. ")")
    eq(sb.unit_aura_calls, 0, "guide off, bars off: no aura reads at all")
    eq(sb.target_aura_calls, 0, "guide off, bars off: no target aura scans either")
end

--=========================================================================================
-- 22) TBC: the energy tick keeps its phase across form flips (ticks don't reset
--     on shift - docs/research/tbc_minmax.md); every other family keeps the
--     reference re-seat (pinned in section 12 on the default WRATH sandbox)
--=========================================================================================
do
    local sb = build({ project = 5 })
    local ST = sb.ST
    eq(sb.st.family, "TBC", "project 5 reports the TBC family")
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    ST.form_index = 3
    sb.power_type = 3

    -- Seed the cycle in cat form, then advance half a cycle with no gain.
    sb.clock = 100
    sb.power = 40
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 0, "TBC: a fresh anchor starts empty")
    sb.clock = 101
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 10, "TBC: half a cycle in the fill is half")

    -- Flip to bear and back: the anchor survives, so the phase continues
    -- instead of restarting.
    sb.clock = 102
    sb.power_type = 1
    sb.power = 10
    ST.form_index = 1
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_energy_tick_bg.hidden, "TBC: bear form still hides the column")
    sb.clock = 103
    sb.power_type = 3
    sb.power = 40
    ST.form_index = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 10, "TBC: re-entering cat keeps the phase (no reset)")

    -- A garbage delta across the flip (cat energy minus bear rage landing in
    -- the 19-22 window) must not re-anchor: the baseline resets instead.
    sb.clock = 104
    sb.power_type = 1
    sb.power = 20
    ST.form_index = 1
    ST.DRUID.on_bar_update(ST, "mainhand")
    sb.clock = 105
    sb.power_type = 3
    sb.power = 41
    ST.form_index = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 10, "TBC: a cross-form 21 gain never re-anchors")

    -- A genuine same-form tick (+20) still re-anchors on TBC.
    sb.clock = 106
    sb.power = 61
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(vf.druid_energy_tick_fill.height, 0, "TBC: a genuine +20 tick still re-anchors")
end

--=========================================================================================
-- 23) D3 pips wiring: the installed bars-design factory (ST:new_pips, colon shape)
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    local factory_calls = 0
    local widget = {
        set = function(self, count) self.count = count end,
        glow_full = function(self, full) self.full = full end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
    ST.new_pips = function(self, parent, opts)
        factory_calls = factory_calls + 1
        widget.self, widget.parent, widget.opts = self, parent, opts
        return widget
    end
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    eq(factory_calls, 1, "post_init creates the pips through ST:new_pips once")
    eq(widget.self, ST, "the factory receives the addon as self (the colon shape)")
    eq(widget.parent, sb.visuals, "the pips parent is the mainhand visuals frame")
    eq(widget.opts.point, "BOTTOMLEFT", "the construction anchor is the bar's bottom-left")
    eq(widget.opts.x, 0, "no horizontal offset")
    eq(widget.opts.y, -18, "the row sits clear of the centred D5/D6 readout")
    eq(widget.opts.design.key, "druid_pips", "the design target carries a stable key")
    eq(widget.opts.design.title, "Combo Points", "and a readable title")
    eq(sb.visuals.druid_pips, widget, "the widget lands on the visuals frame")
    -- Idempotent: a second setup never re-creates.
    ST.DRUID.setup_druid_visuals(ST)
    eq(factory_calls, 1, "a second setup never re-creates the pips")
    -- Cat form drives the live combo count; 5 lights the full glow.
    local db = sb.class_db
    db.show_druid_pips = true
    ST.form_index = 3
    sb.power_type = 3
    sb.power = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(widget.count, 3, "cat form feeds the live combo count")
    eq(widget.full, false, "three combo points carry no full glow")
    eq(widget.shown, true, "the pips show in cat form")
    sb.power = 5
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(widget.count, 5, "the fifth combo point feeds through")
    eq(widget.full, true, "five combo points light the full glow")
    -- Bear form hides the row.
    sb.power_type = 1
    sb.power = 50
    ST.form_index = 1
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(widget.shown, false, "bear form hides the pips")
    -- An unreadable count hides instead of drawing a lie.
    ST.form_index = 3
    sb.power_type = 3
    sb.power = nil
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(widget.shown, false, "an unreadable combo count hides the pips")
    -- Toggle off hides and never touches the widget.
    db.show_druid_pips = nil
    sb.power = 2
    widget.count = nil
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(widget.shown, false, "the toggle off hides the pips")
    eq(widget.count, nil, "the toggle off never re-sets the widget")

    -- No factory (a flavor without bars.lua): the wiring stays inert, no error.
    local bare = build()
    local BST = bare.ST
    BST.interfaces_are_initialised = true
    BST.DRUID.post_init(BST)
    eq(bare.visuals.druid_pips, nil, "without a factory no widget is created")
    bare.class_db.show_druid_pips = true
    BST.form_index = 3
    bare.power_type = 3
    bare.power = 4
    local ok, err = pcall(BST.DRUID.on_bar_update, BST, "mainhand")
    check(ok, "the factory-less wiring does not error (" .. tostring(err) .. ")")

    -- A factory that throws degrades to "no widget", never an error.
    local broken = build()
    local XST = broken.ST
    XST.new_pips = function() error("boom") end
    XST.interfaces_are_initialised = true
    local ok2, err2 = pcall(XST.DRUID.post_init, XST)
    check(ok2, "a throwing factory does not break post_init (" .. tostring(err2) .. ")")
    eq(broken.visuals.druid_pips, nil, "a throwing factory leaves no widget")
end

--=========================================================================================
-- 24) D5 energy-deficit countdown: the "Shred in Xs" text
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    local db = sb.class_db
    db.show_druid_shred_countdown = true
    -- The tick bar off: the countdown alone keeps the energy sampler alive.
    db.show_druid_energy_tick = false
    db.show_druid_form_label = false
    ST.form_index = 3
    sb.power_type = 3
    sb.clock = 100
    sb.power = 20
    sb.unit_power_calls = 0
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(sb.unit_power_calls > 0,
        "the countdown keeps the energy sampler alive with the bar off")
    eq(vf.druid_shred_countdown.text, "Shred in 4s",
        "22 energy short is two ticks -> 4 s")
    check(not vf.druid_shred_countdown.hidden, "the countdown shows while short")
    sb.clock = 101
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(vf.druid_shred_countdown.text, "Shred in 3s", "half a cycle later the wait is 3 s")
    -- Affordable: hidden.
    sb.power = 42
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_shred_countdown.hidden, "affordable energy hides the countdown")
    -- Unreadable energy: hidden.
    sb.power = nil
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_shred_countdown.hidden, "unreadable energy hides the countdown")
    -- Off-cat: hidden.
    sb.power = 20
    sb.power_type = 1
    ST.form_index = 1
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_shred_countdown.hidden, "bear form hides the countdown")
    -- The toggle off reads nothing at all (bars off too).
    db.show_druid_shred_countdown = nil
    sb.power_type = 3
    ST.form_index = 3
    sb.unit_power_calls = 0
    sb.unit_power_type_calls = 0
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(sb.unit_power_calls, 0, "countdown off + bars off: no power reads")
    eq(sb.unit_power_type_calls, 0, "countdown off + bars off: no power-type reads")
    check(vf.druid_shred_countdown.hidden, "countdown off hides the text")
end

-- The cost is family-gated: TBC reads the verified 42, Era has no verified cost.
do
    local tbc = build({ project = 5 })
    eq(tbc.st.family, "TBC", "project 5 reports the TBC family")
    local TST = tbc.ST
    TST.interfaces_are_initialised = true
    TST.DRUID.post_init(TST)
    tbc.class_db.show_druid_shred_countdown = true
    TST.form_index = 3
    tbc.power_type = 3
    tbc.clock = 50
    tbc.power = 20
    TST.DRUID.on_bar_update(TST, "mainhand")
    eq(tbc.visuals.druid_shred_countdown.text, "Shred in 4s",
        "TBC uses the verified 42-energy cost")

    local era = build({ project = 2 })
    eq(era.st.family, "ERA", "project 2 reports the ERA family")
    local EST = era.ST
    EST.interfaces_are_initialised = true
    EST.DRUID.post_init(EST)
    era.class_db.show_druid_shred_countdown = true
    EST.form_index = 3
    era.power_type = 3
    era.clock = 50
    era.power = 20
    EST.DRUID.on_bar_update(EST, "mainhand")
    check(era.visuals.druid_shred_countdown.hidden,
        "Era has no verified Shred cost -> no countdown")
end

--=========================================================================================
-- 25) D6 Maul-efficiency badge: at-cap time and capped-gain events
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    local db = sb.class_db
    -- Toggle off: on_rage_update reads no power at all.
    sb.unit_power_calls = 0
    ST.DRUID.on_rage_update(ST)
    eq(sb.unit_power_calls, 0, "badge off: on_rage_update reads no power")
    check(vf.druid_maul_badge_text.hidden, "badge off: the text stays hidden")

    db.show_druid_maul_badge = true
    ST.in_combat = true
    ST.form_index = 1
    sb.power_type = 1
    -- The first capped reading opens the segment (no event: no previous reading).
    sb.clock = 100
    sb.power = 100
    ST.DRUID.on_rage_update(ST)
    eq(ST.druid_maul_badge_since, 100, "the first capped reading opens the segment")
    eq(ST.druid_maul_badge_events, nil, "no event without a previous reading")
    -- A same-value capped update counts nothing.
    sb.clock = 103
    ST.DRUID.on_rage_update(ST)
    eq(ST.druid_maul_badge_events, nil, "a same-value capped update counts no event")
    -- A spend to 60 closes the segment: 3 s at cap.
    sb.power = 60
    ST.DRUID.on_rage_update(ST)
    near(ST.druid_maul_badge_seconds, 3, 1e-9, "leaving the cap banks the at-cap seconds")
    eq(ST.druid_maul_badge_since, nil, "the segment closes")
    -- A gain landing back on the cap counts one capped event.
    sb.clock = 104
    sb.power = 100
    ST.DRUID.on_rage_update(ST)
    eq(ST.druid_maul_badge_events, 1, "a gain landing on the cap counts a capped event")
    -- The per-frame sync shows the badge in bear form with whole seconds.
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(vf.druid_maul_badge_text.text, "Cap 3s", "the badge reads the banked seconds")
    check(not vf.druid_maul_badge_text.hidden, "the badge shows in bear form")
    -- Cat form closes the open segment and hides the text.
    sb.clock = 105
    sb.power_type = 3
    sb.power = 50
    ST.form_index = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    near(ST.druid_maul_badge_seconds, 4, 1e-9, "leaving bear closes the open segment")
    check(vf.druid_maul_badge_text.hidden, "the badge hides outside bear form")
    -- The toggle going off also closes the segment (no reads).
    ST.form_index = 1
    sb.power_type = 1
    sb.clock = 106
    db.show_druid_maul_badge = nil
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(ST.druid_maul_badge_since, nil, "the toggle off closes the open segment")
    check(vf.druid_maul_badge_text.hidden, "the toggle off hides the badge")
    -- Combat exit resets the fight readout.
    db.show_druid_maul_badge = true
    ST.DRUID.on_combat_exit(ST)
    eq(ST.druid_maul_badge_seconds, nil, "combat exit resets the badge")
    eq(ST.druid_maul_badge_events, nil, "combat exit resets the event count")
    eq(ST.druid_maul_badge_rage, nil, "combat exit drops the rage baseline")
    -- Out of combat: readings never accumulate.
    sb.clock = 200
    sb.power = 100
    ST.in_combat = false
    ST.DRUID.on_rage_update(ST)
    eq(ST.druid_maul_badge_since, nil, "out of combat the cap never opens a segment")
end

--=========================================================================================
-- 26) Omen of Clarity proc glow (discover #8): the guarded proc id on the column
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    local db = sb.class_db
    -- Guide off, omen toggle on: the scan runs for the glow alone.
    db.nextaction_enabled = false
    db.show_druid_omen_glow = true
    ST.form_index = 3
    sb.power_type = 3
    sb.power = 50
    sb.player_auras = {
        { name = "Clearcasting", spell_id = 16870, source = "player",
            duration = 15, expiration = 110 },
    }
    sb.unit_aura_calls = 0
    sb.clock = 100
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(sb.unit_aura_calls > 0,
        "the omen toggle keeps the player scan alive with the guide off")
    check(not vf.druid_omen_glow.hidden, "the proc glows on the energy column")
    -- A different buff never lights it.
    sb.player_auras = {
        { name = "Tiger's Fury", spell_id = 5217, source = "player",
            duration = 6, expiration = 105 },
    }
    sb.clock = 101
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_omen_glow.hidden, "another buff never lights the omen glow")
    -- The tick bar off: nothing to outline.
    sb.player_auras = {
        { name = "Clearcasting", spell_id = 16870, source = "player",
            duration = 15, expiration = 120 },
    }
    db.show_druid_energy_tick = false
    sb.clock = 102
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_omen_glow.hidden, "with the tick bar off the glow hides")
    db.show_druid_energy_tick = true
    -- Toggle off + guide off: no aura reads at all.
    db.show_druid_omen_glow = nil
    sb.unit_aura_calls = 0
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(sb.unit_aura_calls, 0, "omen off + guide off: no aura reads at all")
    check(vf.druid_omen_glow.hidden, "omen off hides the glow")
end

--=========================================================================================
-- 27) GCD tick overlay (discover #4): the marker on the energy column
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    local db = sb.class_db
    db.show_druid_gcd_tick = true
    ST.form_index = 3
    sb.power_type = 3
    sb.power = 20
    sb.clock = 100
    sb.unit_power_calls = 0
    ST.gcd = { expires = 100.5 }
    ST.DRUID.on_bar_update(ST, "mainhand")
    local marker = vf.druid_energy_gcd_marker
    check(not marker.hidden, "a running GCD shows the marker")
    near(marker.offset_y, 5, 1e-9,
        "the marker sits at the GCD-end fraction (0.5/2 of a 20 px column)")
    eq(marker.anchor, vf.druid_energy_tick_bg, "the marker rides the column")
    -- The GCD done: hidden.
    ST.gcd = { expires = 99 }
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(marker.hidden, "an elapsed GCD hides the marker")
    -- The tick bar off: hidden even with a GCD running.
    ST.gcd = { expires = sb.clock + 0.5 }
    db.show_druid_energy_tick = false
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(marker.hidden, "no column -> no marker")
    db.show_druid_energy_tick = true
    -- The toggle off: hidden.
    db.show_druid_gcd_tick = nil
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(marker.hidden, "the toggle off hides the marker")
end

--=========================================================================================
-- 28) D2 TF/Berserk HUD slots: the static list, the rank re-point and the
--     per-family liveness gates
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    local slots = ST.DRUID.HUD_SLOTS
    eq(#slots, 10, "ten descriptors ship (six rotational + TF/Berserk + two trinkets)")
    local by_key = {}
    for i = 1, #slots do by_key[slots[i].key] = slots[i] end
    eq(slots[7].key, "tf", "TF follows the six rotational slots")
    eq(slots[8].key, "berserk", "Berserk follows TF")
    eq(by_key.berserk.spell, 50334, "Berserk ships the WotLK id")
    eq(by_key.tf.spell, 9845, "TF ships the Era/TBC rank as its fallback icon")

    -- No TF/Berserk spell data at all: both slots hide.
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    eq(ST.DRUID.get_hud_state(ST, by_key.tf, 100).hidden, true,
        "no TF data on the client hides the slot")
    eq(ST.DRUID.get_hud_state(ST, by_key.berserk, 100).hidden, true,
        "no Berserk data on the client hides the slot")
    -- The probe retries at the names-retry cadence: spell data arriving late
    -- (or the literal name resolving) flips the slot.
    sb.known_names = { ["Tiger's Fury"] = true }
    eq(ST.DRUID.get_hud_state(ST, by_key.tf, 104).hidden, true,
        "before the retry cadence the slot stays hidden")
    eq(ST.DRUID.get_hud_state(ST, by_key.tf, 106).hidden, nil,
        "the retry flips TF live when the name resolves")
    -- The positive latch: forgetting mid-session keeps the slot until /reload.
    sb.known_names = {}
    eq(ST.DRUID.get_hud_state(ST, by_key.tf, 200).hidden, nil,
        "the liveness probe latches positives per session")
    -- Berserk: the id resolving (WotLK) flips it.
    sb.known = { [50334] = true }
    eq(ST.DRUID.get_hud_state(ST, by_key.berserk, 200).hidden, nil,
        "a resolving Berserk id flips the slot")

    -- Runeless Era hides Berserk; the SoD rune basis flips it live.
    local era = build({ project = 2 })
    local EST = era.ST
    EST.interfaces_are_initialised = true
    EST.DRUID.post_init(EST)
    local eslots = EST.DRUID.HUD_SLOTS
    eq(EST.DRUID.get_hud_state(EST, eslots[8], 100).hidden, true,
        "runeless Era hides Berserk (not baseline there)")
    local sod = build({ project = 2, known = { [33983] = true } })
    local SST = sod.ST
    SST.interfaces_are_initialised = true
    SST.DRUID.post_init(SST)
    eq(SST.DRUID.get_hud_state(SST, SST.DRUID.HUD_SLOTS[8], 100).hidden, nil,
        "the SoD rune basis flips Berserk live on the Era token")
    -- Era TF data keeps the TF slot live.
    local era_tf = build({ project = 2, known = { [9845] = true } })
    local ETST = era_tf.ST
    ETST.interfaces_are_initialised = true
    ETST.DRUID.post_init(ETST)
    eq(ETST.DRUID.get_hud_state(ETST, ETST.DRUID.HUD_SLOTS[7], 100).hidden, nil,
        "Era TF data keeps the TF slot live")
end

-- The provider reads the D2 cooldowns by the client's own localized name and
-- glows while ready in combat.
do
    local sb = build({ known = { [50213] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local slots = ST.DRUID.HUD_SLOTS
    local tf = slots[7]
    eq(tf.spell, 50213, "post_init re-points TF at the highest resolving rank")
    ST.in_combat = true
    sb.clock = 700
    -- Ready in combat: the glow is on, no swipe (off the GCD).
    ST.gcd = { expires = 700.8, spell_length = 1.5 }
    local s = ST.DRUID.get_hud_state(ST, tf, 700)
    eq(s.glow, true, "a ready TF glows in combat")
    eq(s.remaining, nil, "a ready TF carries no swipe")
    -- Burning: the client's reading shows by the resolved name.
    sb.cooldowns_by_query = { ["Spell 50213"] = { 690, 30 } }
    s = ST.DRUID.get_hud_state(ST, tf, 700)
    near(s.remaining, 20, 1e-9, "a burning TF reports the client's cooldown")
    eq(s.duration, 30, "the full duration rides the swipe")
    eq(s.desaturate, true, "a burning TF greys the icon")
    eq(s.glow, false, "a burning TF does not glow")
    -- A GCD-length echo is filtered, not counted.
    sb.cooldowns_by_query = { ["Spell 50213"] = { 699, 1.5 } }
    s = ST.DRUID.get_hud_state(ST, tf, 700)
    eq(s.remaining, nil, "the GCD echo is filtered, not a TF cooldown")
    sb.cooldowns_by_query = {}
    -- Out of combat: no glow.
    ST.in_combat = false
    s = ST.DRUID.get_hud_state(ST, tf, 700)
    eq(s.glow, false, "out of combat the ready TF does not glow")
end

--=========================================================================================
-- R2: secret-hole scans (no truncation below a restricted row)
--=========================================================================================
do
    -- Target merged scan: Mangle below a secret row still draws.
    local sb = build({ known = { [33983] = true, [27008] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local bars = sb.visuals.druid_debuff
    sb.clock = 200
    -- Index 1 degrades to absent (secret); the player's Mangle sits at index 2.
    sb.target_auras = {
        [2] = { name = "localized mangle", spell_id = 33983, source = "player", duration = 12, expiration = 208 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not bars.mangle.bg.hidden, "R2: Mangle draws below a secret row")
    near(bars.mangle.fill.width, 100 * (8 / 12), 1e-6, "R2: the fill shows the remaining fraction")
    eq(bars.mangle.label.text, "8", "R2: the label shows whole seconds")

    -- Player buff scan: Clearcasting below a secret row still lights the omen glow.
    local pb = build()
    local PST = pb.ST
    PST.interfaces_are_initialised = true
    PST.DRUID.post_init(PST)
    local pdb = pb.class_db
    pdb.nextaction_enabled = false
    pdb.show_druid_omen_glow = true
    PST.form_index = 3
    pb.power_type = 3
    pb.power = 50
    pb.player_auras = {
        [2] = { name = "Clearcasting", spell_id = 16870, source = "player",
            duration = 15, expiration = 110 },
    }
    pb.clock = 100
    PST.DRUID.on_bar_update(PST, "mainhand")
    check(not pb.visuals.druid_omen_glow.hidden, "R2: Clearcasting glows below a secret row")
end

if failures == 0 then
    print("PASS  druid_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  druid_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end