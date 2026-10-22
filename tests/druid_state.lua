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

-- Mirrored Unit* globals for the D1 sampler (restored per build, smoke pattern).
local mirrored_unit_globals = {}

-- The equipped-item probe reads the client's INVSLOT_* range through the real
-- global table at call time (compat.lua's rawget(_G, ...)), so the range is
-- mirrored into _G for the duration of the read and restored afterwards. The
-- slot range is the client's own: INVSLOT_FIRST_EQUIPPED ..
-- INVSLOT_LAST_EQUIPPED is 1..19 on every supported family.
local function with_equipment_range(fn)
    local previous_first = rawget(_G, "INVSLOT_FIRST_EQUIPPED")
    local previous_last = rawget(_G, "INVSLOT_LAST_EQUIPPED")
    _G.INVSLOT_FIRST_EQUIPPED = 1
    _G.INVSLOT_LAST_EQUIPPED = 19
    local ok, err = pcall(fn)
    _G.INVSLOT_FIRST_EQUIPPED = previous_first
    _G.INVSLOT_LAST_EQUIPPED = previous_last
    if not ok then error(err, 0) end
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
        target_guid = opts.target_guid, -- what UnitGUID("target") reports (D1 sampler)
        target_hp = opts.target_hp,     -- what UnitHealth("target") reports (D1 sampler)
        -- Spell names this client knows (knowledge-level, for the SoD rune probe).
        known_names = opts.known_names or {},
        -- Every GetSpellInfo query, in order (the name-vs-id direction proof).
        spell_queries = {},
        -- A client that cannot answer at all: the stub raises, so compat's pcall
        -- reports "could not answer" ("unresolved") instead of "not here" ("absent").
        spell_info_throws = false,
        current_spell = opts.current_spell, -- the only id IsCurrentSpell answers true for
        form = 0,                 -- what GetShapeshiftForm reports
        talents = opts.talents or {}, -- talent index -> rank (11 = moonkin, 19 = tree)
        target_auras = opts.target_auras or {}, -- what UnitAura("target", i) serves
        player_auras = opts.player_auras or {}, -- what UnitAura("player", i) serves
        -- call counters
        get_family_spell_id_calls = 0,
        get_family_spell_id_state_calls = 0,
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
        -- The equipped-item fixture (the Wolfshead Helm read): the equipped
        -- slot -> item id map the client's GetInventoryItemID serves, and the
        -- ids the class asked the probe for.
        equipment_items = opts.equipment_items,
        item_queries = {},
    }

    local env = setmetatable({}, { __index = _G })
    -- D1 TTD sampler reads target identity/health through compat (raw _G at load,
    -- like smoke.lua): mirror per-build stubs, restoring the previous build's
    -- first so sequential builds never leak into each other.
    for name, prev in pairs(mirrored_unit_globals) do
        if prev.present then
            _G[name] = prev.value
        else
            _G[name] = nil
        end
    end
    mirrored_unit_globals = {}
    local function mirror_unit_global(name, fn)
        if mirrored_unit_globals[name] == nil then
            mirrored_unit_globals[name] = {
                present = rawget(_G, name) ~= nil,
                value = rawget(_G, name),
            }
        end
        _G[name] = fn
    end
    mirror_unit_global("UnitGUID", function(unit)
        if unit == "target" then
            return sb.target_guid
        end
        return nil
    end)
    mirror_unit_global("UnitHealth", function(unit)
        if unit == "target" then
            return sb.target_hp
        end
        return nil
    end)
    env.WOW_PROJECT_ID = opts.project or 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    env.GetTime = function() return sb.clock end
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
        if type(query) == "string" then
            -- Knowledge-level: a name answers only for a known spell.
            if sb.known_names[query] then
                return query, nil, 1, 0, 0, 0, 0
            end
            -- The client's own name for a known spell answers too: a client that
            -- named a spell answers to that name (the TBC name path).
            local back = query:match("^Spell (%d+)$")
            local back_id = back and tonumber(back)
            if back_id and sb.known[back_id] then
                return query, nil, 1, 0, 0, 0, back_id
            end
            return nil
        end
        if name_only_client then
            -- The TBC client indexes names only: an id query finds nothing.
            return nil
        end
        if sb.known[query] then
            return "Spell " .. tostring(query), nil, 1, 0, 0, 0, query
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
    -- The equipped-item read (the Wolfshead Helm probe): the client answers the
    -- equipped slot -> item id, and nothing else. A sandbox without this stub is
    -- a client that cannot answer at all.
    if opts.equipment_items then
        env.GetInventoryItemID = function(unit, slot)
            if unit ~= "player" then return nil end
            return sb.equipment_items[slot]
        end
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
    -- The equipped-item probe: the class asks it for an item id, so the queried
    -- ids are recorded (the sim's own HasItemEquipped(8345) check) while the
    -- answer still comes from the real compat probe.
    local real_item_probe = st.api.is_item_equipped
    st.api.is_item_equipped = function(item_id)
        sb.item_queries[#sb.item_queries + 1] = item_id
        return real_item_probe(item_id)
    end

    -- The pure druid maths module loads before the class module (as the TOCs order it).
    local energy = assert(loadfile(ROOT .. "druid_energy.lua"))
    setfenv(energy, env)
    energy("SwedgeTimer", st)

    -- The pure decision engine (as the TOCs order it: before classes/druid.lua), so
    -- the practice surface pins below run the SHIPPED model and not a copy of it.
    local guide = assert(loadfile(ROOT .. "druid_guide.lua"))
    setfenv(guide, env)
    guide("SwedgeTimer", st)

    local mod = assert(loadfile(ROOT .. "classes/druid.lua"))
    setfenv(mod, env)
    mod("SwedgeTimer", st)
    -- classes/druid.lua registers its body as a loader (operator order 2026-10-21:
    -- only the selected class executes). Activate it here, right after its file
    -- loads - the same load-time position its body occupied before the wrapper.
    assert(type(st.class_loaders) == "table"
        and type(st.class_loaders["DRUID"]) == "function",
        "classes/druid.lua registers the DRUID loader")
    st.class_loaders["DRUID"]()

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
    eq(sb.get_family_spell_id_state_calls, 1, "the first rage tick resolves the rank")
    eq(sb.get_family_spell_id_calls, 0, "the class resolves through the state API, not the plain one")
    ST.DRUID.on_rage_update(ST)
    ST.DRUID.on_rage_update(ST)
    eq(sb.get_family_spell_id_state_calls, 1, "a negative result is latched: no re-walk per tick")
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
-- 28) D2 TF/Berserk + Claw HUD slots: the static list, the rank re-point and the
--     per-family liveness gates (Claw display-only; rule still filed)
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    local slots = ST.DRUID.HUD_SLOTS
    eq(#slots, 11, "eleven descriptors ship (seven rotational + TF/Berserk + two trinkets)")
    local by_key = {}
    for i = 1, #slots do by_key[slots[i].key] = slots[i] end
    eq(slots[7].key, "claw", "Claw mirrors the guide slot after Shred")
    eq(by_key.claw.spell, 9850, "Claw ships the sim Forever id (no rank table)")
    eq(slots[8].key, "tf", "TF follows the seven rotational slots")
    eq(slots[9].key, "berserk", "Berserk follows TF")
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
    eq(EST.DRUID.get_hud_state(EST, eslots[9], 100).hidden, true,
        "runeless Era hides Berserk (not baseline there)")
    local sod = build({ project = 2, known = { [33983] = true } })
    local SST = sod.ST
    SST.interfaces_are_initialised = true
    SST.DRUID.post_init(SST)
    eq(SST.DRUID.get_hud_state(SST, SST.DRUID.HUD_SLOTS[9], 100).hidden, nil,
        "the SoD rune basis flips Berserk live on the Era token")
    -- Era TF data keeps the TF slot live.
    local era_tf = build({ project = 2, known = { [9845] = true } })
    local ETST = era_tf.ST
    ETST.interfaces_are_initialised = true
    ETST.DRUID.post_init(ETST)
    eq(ETST.DRUID.get_hud_state(ETST, ETST.DRUID.HUD_SLOTS[8], 100).hidden, nil,
        "Era TF data keeps the TF slot live")
    -- Claw display mirror: nil toggle hides (no default-visible change), true
    -- shows the rotational GCD/ready path; no probe, no rule.
    eq(ST.DRUID.get_hud_state(ST, by_key.claw, 100).hidden, true,
        "nil hud_show_claw hides the Claw slot")
    sb.class_db.hud_show_claw = true
    local claw_live = ST.DRUID.get_hud_state(ST, by_key.claw, 100)
    eq(claw_live.hidden, nil, "hud_show_claw true shows the Claw slot")
    eq(claw_live.remaining, nil, "a ready Claw with no GCD reports no cooldown")
    ST.gcd = { expires = 101.4, spell_length = 1.5 }
    claw_live = ST.DRUID.get_hud_state(ST, by_key.claw, 100)
    near(claw_live.remaining, 1.4, "Claw takes the GCD swipe like the other rotationals")
    ST.gcd = {}
    sb.class_db.hud_show_claw = nil
    eq(ST.DRUID.get_hud_state(ST, by_key.claw, 100).hidden, true,
        "clearing the toggle hides Claw again")
end

-- The provider reads the D2 cooldowns by the client's own localized name and
-- glows while ready in combat.
do
    local sb = build({ known = { [50213] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local slots = ST.DRUID.HUD_SLOTS
    local tf = slots[8]
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

--=========================================================================================
-- D2 pure: proc-aware tick classifier (Combat-Potency-style grants never re-anchor)
--=========================================================================================
do
    local de = build().druid_energy
    -- adjust_gain_for_procs: nil-safe subtraction, legacy degrade on junk.
    eq(de.adjust_gain_for_procs(80, 60), 20, "D2: a TF+tick frame adjusts to the tick")
    eq(de.adjust_gain_for_procs(20, nil), 20, "D2: a nil proc grant degrades to the raw delta")
    eq(de.adjust_gain_for_procs(20, 0), 20, "D2: a zero proc grant degrades to the raw delta")
    eq(de.adjust_gain_for_procs(20, "60"), 20, "D2: a non-number proc grant degrades to the raw delta")
    eq(de.adjust_gain_for_procs(20, 0 / 0), 20, "D2: a NaN proc grant degrades to the raw delta")
    eq(de.adjust_gain_for_procs(nil, 60), nil, "D2: a missing delta reads nil")
    eq(de.adjust_gain_for_procs(0 / 0, 60), nil, "D2: a NaN delta reads nil")
    -- is_tick_gain: legacy parity with a nil grant.
    eq(de.is_tick_gain(19, nil), true, "D2: the lower bound still qualifies without a proc")
    eq(de.is_tick_gain(20, nil), true, "D2: the common tick still qualifies without a proc")
    eq(de.is_tick_gain(22, nil), true, "D2: the upper bound still qualifies without a proc")
    eq(de.is_tick_gain(18.999, nil), false, "D2: just below the window still misses without a proc")
    eq(de.is_tick_gain(22.001, nil), false, "D2: just above the window still misses without a proc")
    eq(de.is_tick_gain(nil, nil), false, "D2: a missing delta never qualifies")
    eq(de.is_tick_gain("20", nil), false, "D2: a non-number delta never qualifies")
    -- is_tick_gain: proc-aware (the Combat-Potency shapes: 15/25 never re-anchor,
    -- a tick hiding in the same frame still does).
    eq(de.is_tick_gain(80, 60), true, "D2: TF+tick in one frame still re-anchors")
    eq(de.is_tick_gain(60, 60), false, "D2: the proc alone never re-anchors")
    eq(de.is_tick_gain(20, 60), false, "D2: a capped proc partial never forges a tick")
    eq(de.is_tick_gain(35, 15), true, "D2: a masked tick recovers (combat-potency shape)")
    eq(de.is_tick_gain(15, 15), false, "D2: a 15-energy grant never re-anchors")
    eq(de.is_tick_gain(45, 25), true, "D2: a masked tick recovers (relentless shape)")
    eq(de.is_tick_gain(25, 25), false, "D2: a 25-energy grant never re-anchors")
end

--=========================================================================================
-- D1 pure: TTD readout formatter (unknown-hides, never a guessed number)
--=========================================================================================
do
    local de = build().druid_energy
    eq(de.format_time_to_die(8.2), "TTD 8s", "D1: the estimate formats as whole seconds")
    eq(de.format_time_to_die(8.5), "TTD 9s", "D1: the estimate rounds to nearest")
    eq(de.format_time_to_die(0), "TTD 0s", "D1: a zero estimate reads TTD 0s, never nil")
    eq(de.format_time_to_die(nil), nil, "D1: a missing estimate hides the readout")
    eq(de.format_time_to_die(0 / 0), nil, "D1: a NaN estimate hides the readout")
    eq(de.format_time_to_die(-1), nil, "D1: a negative estimate hides the readout")
    eq(de.format_time_to_die("8"), nil, "D1: a non-number estimate hides the readout")
end

--=========================================================================================
-- D1 wiring: TTD readout text (any form, option-gated, unknown-hides)
--=========================================================================================
do
    local sb = build({ target_guid = "Target-1", target_hp = 1000 })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local vf = sb.visuals
    check(vf.druid_ttd_text ~= nil, "D1: post_init creates the TTD readout text")

    sb.clock = 100
    sb.power = 40
    sb.power_type = 3
    ST.form_index = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_ttd_text.hidden, "D1: option nil hides the readout (default off)")

    -- Enable: the first sample seeds the baseline, still no estimate.
    sb.class_db.show_druid_ttd_readout = true
    sb.clock = 100.3
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_ttd_text.hidden, "D1: the first TTD sample seeds, no estimate yet")

    -- 1000 -> 900 over 0.3 s seeds 333.3 HP/s: 900 / 333.3 = 2.7 -> "TTD 3s".
    sb.target_hp = 900
    sb.clock = 100.6
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not vf.druid_ttd_text.hidden, "D1: a readable target shows the readout")
    eq(vf.druid_ttd_text.text, "TTD 3s", "D1: the readout shows the EMA estimate")

    -- Riding the EMA inside the throttle repaints nothing.
    local text_calls = vf.druid_ttd_text.set_text_calls
    sb.clock = 100.7
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(vf.druid_ttd_text.set_text_calls, text_calls, "D1: an unchanged readout costs no re-set")
    eq(vf.druid_ttd_text.text, "TTD 3s", "D1: the riding estimate keeps its text")

    -- Unreadable health hides and drops the baseline; the next sample re-seeds
    -- (hidden), the one after estimates again (800 -> 700 over 0.3 s seeds
    -- 333.3 HP/s: 700 / 333.3 = 2.1 -> "TTD 2s").
    sb.target_hp = nil
    sb.clock = 100.9
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_ttd_text.hidden, "D1: unreadable health hides the readout")
    sb.target_hp = 800
    sb.clock = 101.2
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_ttd_text.hidden, "D1: the re-seed estimates nothing yet")
    sb.target_hp = 700
    sb.clock = 101.5
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(not vf.druid_ttd_text.hidden, "D1: the second sample estimates again")
    eq(vf.druid_ttd_text.text, "TTD 2s", "D1: 700 hp at 333.3 HP/s reads TTD 2s")
    sb.class_db.show_druid_ttd_readout = nil
    sb.clock = 101.8
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(vf.druid_ttd_text.hidden, "D1: option nil hides the readout again")

    -- No target identity at all: no estimate, never a guessed number.
    local sb2 = build({})
    local ST2 = sb2.ST
    ST2.interfaces_are_initialised = true
    ST2.DRUID.post_init(ST2)
    sb2.class_db.show_druid_ttd_readout = true
    sb2.clock = 100
    sb2.power = 40
    sb2.power_type = 3
    ST2.form_index = 3
    ST2.DRUID.on_bar_update(ST2, "mainhand")
    check(sb2.visuals.druid_ttd_text.hidden, "D1: no target identity hides the readout")
end

--=========================================================================================
-- D2 wiring: SoD TF proc edge (capped partial never forges, combo still anchors)
--=========================================================================================
do
    -- SoD: ERA family plus the Mangle rune known, so the TF +60 attribution is live.
    local sb = build({ project = 2, known = { [33983] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    eq(ST.druid_tf_was_active, nil, "D2: the TF edge starts unsettled")
    eq(ST.druid_proc_gain, nil, "D2: no proc grant is pending at boot")

    sb.clock = 100
    sb.power = 0
    sb.power_type = 3
    ST.form_index = 3
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(ST.druid_energy_anchor, 100, "D2: the first cat sample seats the anchor")
    eq(ST.druid_proc_gain, nil, "D2: no TF edge means no proc grant")

    -- TF + tick in one uncapped frame (0 + 60 + 20 = 80): the adjusted 20 anchors.
    sb.player_auras[1] = { name = "Tiger's Fury", source = "player",
        duration = 6, expiration = 107 }
    sb.clock = 101
    sb.power = 80
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(ST.druid_tf_was_active, true, "D2: the TF rising edge latches")
    eq(ST.druid_energy_anchor, 101, "D2: the TF+tick frame still re-anchors")
    eq(ST.druid_proc_gain, nil, "D2: the grant is one-shot (consumed by the sample)")

    -- TF alone (delta 60, no tick): the adjusted 0 never anchors.
    sb.clock = 102
    sb.power = 140
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(ST.druid_energy_anchor, 101, "D2: the proc alone never moves the anchor")

    -- Capped TF partial (80 + 60 capped to 100, delta 20, no tick): the adjusted
    -- -40 never forges the anchor the legacy window would have stamped.
    sb.player_auras[1] = nil
    sb.clock = 103
    sb.power = 80
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(ST.druid_tf_was_active, false, "D2: the faded buff clears the edge")
    sb.player_auras[1] = { name = "Tiger's Fury", source = "player",
        duration = 6, expiration = 110 }
    sb.clock = 104
    sb.power = 100
    ST.DRUID.on_bar_update(ST, "mainhand")
    eq(ST.druid_energy_anchor, 101, "D2: a capped proc partial never forges the anchor")
    eq(ST.druid_proc_gain, nil, "D2: the forged grant is consumed too")

    -- Control: off the SoD gate (Wrath) the same edge stamps nothing and the
    -- legacy window decides alone (no honest TF amount exists there to attribute).
    local wb = build({ project = 11, known = { [33983] = true } })
    local WST = wb.ST
    WST.interfaces_are_initialised = true
    WST.DRUID.post_init(WST)
    wb.clock = 100
    wb.power = 80
    wb.power_type = 3
    WST.form_index = 3
    WST.DRUID.on_bar_update(WST, "mainhand")
    wb.player_auras[1] = { name = "Tiger's Fury", source = "player",
        duration = 6, expiration = 107 }
    wb.clock = 101
    wb.power = 100
    WST.DRUID.on_bar_update(WST, "mainhand")
    eq(WST.druid_proc_gain, nil, "D2: off-SoD the TF edge stamps no grant")
    eq(WST.druid_energy_anchor, 101, "D2: off-SoD the legacy window decides alone")
end

--=========================================================================================
-- Follow-up groundwork: the tick-remaining + window helpers and the fight clock
--=========================================================================================
do
    local de = build().druid_energy
    -- get_tick_remaining: seconds to the next tick from the tracker's anchor.
    eq(de.get_tick_remaining(100, 100, 2), 2, "tick: a fresh anchor waits a full cycle")
    eq(de.get_tick_remaining(100, 101, 2), 1, "tick: half a cycle in waits 1 s")
    near(de.get_tick_remaining(100, 101.5, 2), 0.5, "tick: the phase counts down")
    eq(de.get_tick_remaining(100, 102, 2), 2, "tick: on the boundary the next cycle waits full")
    eq(de.get_tick_remaining(nil, 101, 2), nil, "tick: a missing anchor reads nil (unknown)")
    eq(de.get_tick_remaining(100, nil, 2), nil, "tick: a missing clock reads nil")
    eq(de.get_tick_remaining(0 / 0, 101, 2), nil, "tick: a NaN anchor reads nil")
    eq(de.get_tick_remaining(100, 0 / 0, 2), nil, "tick: a NaN clock reads nil")
    eq(de.get_tick_remaining(102, 100, 2), 2, "tick: a future anchor reads the full cycle")
    eq(de.get_tick_remaining(100, 101, nil), 1, "tick: a missing cycle falls back to 2 s")
    eq(de.get_tick_remaining(100, 101, 0), 1, "tick: a non-positive cycle falls back to 2 s")
    -- is_energy_in_window: the trick bands, both ends inclusive, nil-safe.
    eq(de.is_energy_in_window(35, 35, 39), true, "window: the low bound qualifies")
    eq(de.is_energy_in_window(39, 35, 39), true, "window: the high bound qualifies")
    eq(de.is_energy_in_window(37, 35, 39), true, "window: inside qualifies")
    eq(de.is_energy_in_window(34.999, 35, 39), false, "window: below misses")
    eq(de.is_energy_in_window(39.001, 35, 39), false, "window: above misses")
    eq(de.is_energy_in_window(nil, 35, 39), false, "window: unreadable energy never opens")
    eq(de.is_energy_in_window(0 / 0, 35, 39), false, "window: NaN energy never opens")
    eq(de.is_energy_in_window(37, nil, 39), false, "window: an unreadable bound never opens")
end

-- The fight clock lifecycle: nil at boot, cleared on combat exit.
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    eq(ST.druid_fight_start_at, nil, "fight clock: post_init starts with no stamp")
    -- A stale stamp dies with the fight.
    ST.druid_fight_start_at = 100
    ST.DRUID.on_combat_exit(ST)
    eq(ST.druid_fight_start_at, nil, "fight clock: combat exit clears the stamp")
    -- Pre-init combat exit stays safe (no stamp, no error).
    local bare = build({ no_visuals = true })
    local ok, err = pcall(bare.ST.DRUID.on_combat_exit, bare.ST)
    check(ok, "fight clock: pre-init combat exit does not error (" .. tostring(err) .. ")")
    eq(bare.ST.druid_fight_start_at, nil, "fight clock: pre-init exit leaves no stamp")
end

-- RipCP gather wiring: the module feeds db.guide_rip_min_cp raw (nil until
-- the widget ships); the engine defaults to 4 and clamps 2-5.
do
    local sb = build()
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    eq(ST.DRUID.gather_guide_inputs(ST, {}).rip_min_cp, nil,
        "gather: no RipCP option -> nil (engine defaults to 4)")
    sb.class_db.guide_rip_min_cp = 2
    eq(ST.DRUID.gather_guide_inputs(ST, {}).rip_min_cp, 2,
        "gather: the low-end RipCP override feeds through")
    sb.class_db.guide_rip_min_cp = 5
    eq(ST.DRUID.gather_guide_inputs(ST, {}).rip_min_cp, 5,
        "gather: the high-end RipCP override feeds through")
    sb.class_db.guide_rip_min_cp = 1
    eq(ST.DRUID.gather_guide_inputs(ST, {}).rip_min_cp, 1,
        "gather: a below-range RipCP passes through raw (the engine clamps to 4)")
    sb.class_db.guide_rip_min_cp = nil
    eq(ST.DRUID.gather_guide_inputs(ST, {}).rip_min_cp, nil,
        "a missing RipCP option clears back to nil")
    -- Stale reuse: a previous override never survives a missing option.
    sb.class_db.guide_rip_min_cp = 3
    local reused = { rip_min_cp = 3 }
    eq(ST.DRUID.gather_guide_inputs(ST, reused).rip_min_cp, 3,
        "gather: the wired override rides the reused table")
    sb.class_db.guide_rip_min_cp = nil
    eq(ST.DRUID.gather_guide_inputs(ST, reused).rip_min_cp, nil,
        "gather: a stale RipCP override is cleared")
end

-- 31) Name-vs-id rule (bench/lessons.md): TBC Anniversary resolves by NAME
-- never bare id; Classic Era by id. Classification: gather slots (Maul/Mangle
-- costs), cooldown reads (TF/Berserk/SP/FF via resolve_cooldown_query),
-- known-spell probes (SoD ERA-only, never on TBC), HUD/rotation lookups and
-- the Maul queue hooks branch via st.family (spell_query); aura scans match
-- id OR name (nil-safe fallback) and are pinned by the debuff/player sections
-- above. Both resolutions are pinned here.
do
    -- Maul queue hook: TBC NAME, Era id.
    local tbc_sb = build({ project = 5, known = { [48480] = true }, current_spell = "Maul" })
    local TST = tbc_sb.ST
    TST.interfaces_are_initialised = true
    TST.DRUID.post_init(TST)
    tbc_sb.is_current_spell_calls = 0
    TST:get_class_table().enable_maul_color = true
    TST.DRUID.on_current_spell_cast_changed(TST, false)
    eq(TST.maul_queued, true, "TBC: the Maul queue answers the NAME probe")
    local era_sb = build({ project = 2, known = { [48480] = true }, current_spell = 48480 })
    local EST = era_sb.ST
    EST.interfaces_are_initialised = true
    EST.DRUID.post_init(EST)
    EST:get_class_table().enable_maul_color = true
    EST.DRUID.on_current_spell_cast_changed(EST, false)
    eq(EST.maul_queued, true, "Era: the Maul queue answers the id probe")

    -- Maul cost: TBC NAME, Era id (recorded GetSpellPowerCost query).
    tbc_sb.cost_queries = 0
    tbc_sb.last_cost_id = nil
    TST.maul_queued = true
    TST.DRUID.on_rage_update(TST)
    eq(tbc_sb.last_cost_id, "Maul", "TBC: Maul cost reads by NAME, never bare id")
    era_sb.cost_queries = 0
    era_sb.last_cost_id = nil
    EST.maul_queued = true
    EST.DRUID.on_rage_update(EST)
    check(type(era_sb.last_cost_id) == "number", "Era: Maul cost reads by id")

    -- Guide slots: TBC carry NAMES (GetSpellInfo takes names there), Era keeps ids.
    eq(type(TST.DRUID.guide.slots[1].spell_id) == "string", true, "TBC: guide slots carry names")
    eq(EST.DRUID.guide.slots[1].spell_id, 48480, "Era: guide slots keep the rank-resolved id")
end

--=========================================================================================
-- 30) Practice seam: practice_sync + the post_init practice_ui hook
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    -- practice_sync reports no seal state (the druid has none to mirror).
    eq(ST.DRUID.practice_sync(ST), 0, "practice_sync reports zero seal state")
    check(ST.has_soc == nil and ST.has_sob == nil,
        "practice_sync stamps no paladin seal fields")
    local ok, err = pcall(ST.DRUID.practice_sync, ST)
    check(ok, "pre-init practice_sync does not error (" .. tostring(err) .. ")")

    -- post_init builds the shared session UI when the module is present: the
    -- options Practice toggle (and the shared session flow) needs it on a druid.
    local init_self = nil
    sb.st.practice_ui = { init = function(self) init_self = self end }
    ST.DRUID.post_init(ST)
    eq(init_self, ST, "post_init inits the shared practice UI")
    -- Without the module the hook stays inert (every earlier post_init call in
    -- this file proves the nil path: st.practice_ui is nil by default).
    local bare = build()
    local ok2, err2 = pcall(bare.ST.DRUID.post_init, bare.ST)
    check(ok2, "post_init without the practice module does not error (" .. tostring(err2) .. ")")
end

--=========================================================================================
-- 31) Practice routing wrappers degrade to nil without the practice modules
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    eq(sb.st.practice, nil, "the default sandbox loads no practice module")
    eq(ST.DRUID.practice_scenario_key(), nil, "no practice module: no scenario key")
    eq(ST.DRUID.new_practice_session(0), nil, "no practice module: no session starts")
    eq(ST.DRUID.practice_drill_key(), "druid_powershift_rework",
        "the class names its own drill even without the practice module")
    local out = {}
    eq(ST.DRUID.tick_practice_session(nil, 0, 0.05, out), out,
        "no session: the tick returns the out table untouched")
    eq(ST.DRUID.tick_practice_session(nil, 0, 0.05, nil), nil,
        "no session and no out table: the tick stays nil-safe")
    eq(ST.DRUID.practice_shift(nil, 0), nil, "no session: no shift grades")
    eq(ST.DRUID.practice_summary(nil), nil, "no session: no summary")
    eq(ST.DRUID.end_practice_session(nil, 0), false, "no session: end reports false")
end

--=========================================================================================
-- 32) Practice drill end-to-end: the wrapper starts the class's OWN drill and grades
--     through it (never the retired built-in)
--=========================================================================================
do
    -- The pure engine loads standalone (no WoW API, no addon state).
    local practice_st = {}
    local chunk = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(chunk, setmetatable({}, { __index = _G }))
    chunk("SwedgeTimer", practice_st)
    local H = practice_st.practice.harness
    check(H.get_scenario("druid_powershift") ~= nil, "the registry carries druid_powershift")
    eq(H.get_scenario("druid_powershift").class, "DRUID", "the drill is classed DRUID")
    local found = false
    for _, spec in ipairs(H.scenarios_for_class("DRUID")) do
        if spec.key == "druid_powershift" then
            found = true
        end
    end
    check(found, "scenarios_for_class(DRUID) routes to the drill")
    -- The retired built-in stays registered for backward compatibility and names
    -- the class drill that owns the skill (the engine's delegation map).
    eq(H.SUPERSEDED_DRILLS.druid_powershift, "druid_powershift_rework",
        "the built-in drill names the class drill that owns the shift rule")

    -- The wrappers drive the class's OWN drill through the shared scoring pipeline.
    -- The Era build is the one with a shift trigger (the sim's cost trigger); the
    -- families without one answer nil (unknown-hides, never a guess).
    local sb = build({ project = 2 })
    local ST = sb.ST
    sb.st.practice = practice_st.practice
    eq(ST.DRUID.practice_scenario_key(), "druid_powershift",
        "the wrapper resolves the DRUID drill key")
    eq(ST.DRUID.practice_drill_key(), "druid_powershift_rework",
        "the class publishes the drill its session runs")
    local session = ST.DRUID.new_practice_session(0)
    check(session ~= nil, "the wrapper starts a drill run")
    if session == nil then
        check(false, "no drill run: session pins skipped, never throw")
    else
        eq(session.active, true, "the run begins active")
        eq(session.key, "druid_powershift_rework",
            "the run is the class's own drill, not the retired built-in")
        local tick_out = {}
        ST.DRUID.tick_practice_session(session, 0, 0.05, tick_out)
        eq(tick_out.energy, 0, "the first tick establishes the regen baseline")
        ST.DRUID.tick_practice_session(session, 1, 0.05, tick_out)
        eq(tick_out.energy, 10, "the run clock advances the energy pool")
        eq(ST.DRUID.practice_shift(session, 1), "S",
        "shifting at 10 energy grades S through the class drill")
        eq(session.state.energy, 50, "the fixed refund lands in the pool")
        eq(session.state.shifts, 1, "the shift is counted")
        eq(ST.DRUID.practice_shift(session, 2), "A",
        "shifting at 50 energy grades A through the class drill")
        local summary = ST.DRUID.practice_summary(session)
        eq(summary.attempts, 2, "both shifts recorded on the session score")
        eq(summary.score, 90, "S (100) + A (80) average 90")
        eq(summary.best_grade, "S", "the best grade rides the summary")
        check(ST.DRUID.end_practice_session(session, 2), "ending an active run reports true")
        eq(ST.DRUID.end_practice_session(session, 2), false,
        "ending an ended run reports false")
    end
end

--=========================================================================================
-- 33) Practice wiring: the DRUID options entry + the shared bridge branches
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end
    check(read("classes/druid.lua"):find("st%.practice_ui%.init%(self%)", 1) ~= nil,
        "classes/druid.lua: post_init inits the shared practice UI")
    local options = read("option_tables.lua")
    local druid_block = options:match(
        "ST%.class_opts_funcs%.DRUID%(.-ST%.class_opts_funcs%.SHAMAN") or ""
    check(druid_block ~= "", "the DRUID options block is found ahead of SHAMAN")
    check(druid_block:find("%f[%a_]druid_practice_toggle%s*=") ~= nil,
        "the DRUID section carries a Practice toggle entry")
    check(druid_block:find("st%.practice_ui%.toggle%(ST%)") ~= nil,
        "the DRUID Practice entry invokes the shared session toggle")
    -- class-isolation 2026-10-21: the shared bridge carries no DRUID branch - it
    -- asks the ACTIVE class's provider, and the druid module owns the seam.
    local bridge = read("practice_ui.lua")
    local _, druid_branches = bridge:gsub('player_class == "DRUID"', "")
    eq(druid_branches, 0, "the shared bridge carries no DRUID branch (the provider owns it)")
    check(bridge:find("function ui.practice_panel()", 1, true) ~= nil,
        "the shared bridge asks the ACTIVE class's provider")
    local druid_src = read("classes/druid.lua")
    check(druid_src:find("sync_sim = function(self)", 1, true) ~= nil,
        "the DRUID sync seam is the druid module's own provider seam")
    check(druid_src:find("ST.DRUID.practice_sync(self)", 1, true) ~= nil,
        "the DRUID sync seam calls ST.DRUID.practice_sync, never the paladin mirror")
end

--=========================================================================================
-- 34) Designer: every element the druid creates is positionable in design mode
--=========================================================================================
do
    local sb = build()
    local ST = sb.ST
    -- Cooldown HUD (the hud design target's live content).
    check(type(ST.DRUID.HUD_SLOTS) == "table", "the druid defines HUD slots")
    check(#ST.DRUID.HUD_SLOTS > 0, "the HUD slot list is non-empty")
    for i = 1, #ST.DRUID.HUD_SLOTS do
        local slot = ST.DRUID.HUD_SLOTS[i]
        check(type(slot.key) == "string" and type(slot.title) == "string",
            "HUD slot " .. i .. " carries the design contract shape")
    end
    check(type(ST.DRUID.get_hud_state) == "function", "the druid defines the HUD provider")
    -- Next Action Guide + rotation label (the nag + rottext targets' content).
    check(type(ST.DRUID.guide) == "table", "the druid defines the guide provider")
    check(type(ST.DRUID.guide.slots) == "table" and #ST.DRUID.guide.slots > 0,
        "the guide slot set is non-empty")
    check(type(ST.DRUID.get_rotation_key) == "function",
        "the druid defines the rotation source")
    -- post_init builds the HUD + guide frames the designer moves.
    local hud_self, nag_self = nil, nil
    sb.st.hud = { init = function(self) hud_self = self end }
    sb.st.nextaction_ui = { init = function(self) nag_self = self end }
    ST.DRUID.post_init(ST)
    eq(hud_self, ST, "post_init builds the druid HUD frame")
    eq(nag_self, ST, "post_init builds the druid guide frame")
    -- The design registry covers every element the druid creates: the swing bars,
    -- the HUD, the rotation label, the guide, and the practice panel + rotation +
    -- timeline. Bar-relative sidebars ride the bar overlay by design (and the pips
    -- row registers itself with a stable key, pinned in section 23).
    local f = assert(io.open(ROOT .. "designmode.lua", "r"))
    local design = f:read("*a")
    f:close()
    check(design:find('key = "bar_"', 1, true) ~= nil,
        "designmode covers the druid swing bars")
    for _, key in ipairs({ "hud", "rottext", "nag", "practice_panel" }) do
        check(design:find('key = "' .. key .. '"', 1, true) ~= nil,
            "designmode covers the druid " .. key .. " element")
    end
    check(design:find('practice_descriptor("practice_rotation"', 1, true) ~= nil,
        "designmode covers the practice rotation display")
    check(design:find('practice_descriptor("practice_timeline"', 1, true) ~= nil,
        "designmode covers the practice timeline")
end

--=========================================================================================
-- 35) Family matrix: the new seams behave identically on Era / TBC / Wrath / Forever
--=========================================================================================
-- None of the practice/design seams branch on family (no name-vs-id, no probe, no
-- client API at all): the same calls return the same values on the classic line and
-- on the Mainline-code Forever client. Anything client-unknown hides (nil-safe),
-- never throws.
do
    local practice_st = {}
    local chunk = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(chunk, setmetatable({}, { __index = _G }))
    chunk("SwedgeTimer", practice_st)
    for _, project in ipairs({ 2, 5, 11, 18 }) do
        local sb = build({ project = project })
        local ST = sb.ST
        sb.st.practice = practice_st.practice
        local tag = "project " .. project .. " (" .. sb.st.family .. ")"
        local ok, err = pcall(ST.DRUID.post_init, ST)
        check(ok, tag .. ": post_init does not error (" .. tostring(err) .. ")")
        eq(ST.DRUID.practice_sync(ST), 0, tag .. ": practice_sync reports zero")
        eq(ST.DRUID.practice_scenario_key(), "druid_powershift",
            tag .. ": the drill key resolves")
        local session = ST.DRUID.new_practice_session(0)
        check(session ~= nil and session.active == true,
            tag .. ": a drill run starts")
        if session == nil then
            check(false, tag .. ": no drill run, session pins skipped")
        else
            eq(session.key, "druid_powershift_rework",
                tag .. ": the run is the class's own drill")
            -- The class's own shift rule grades the attempt, and it only has a
            -- trigger where a sim does (the TBC fixed line, the classic/sod cost
            -- trigger): the families without one answer nil (unknown-hides).
            local grade = ST.DRUID.practice_shift(session, 0)
            if project == 2 or project == 5 then
                eq(grade, "S", tag .. ": the first shift grades S")
            else
                eq(grade, nil, tag .. ": no shift trigger on this family grades nothing")
            end
            check(ST.DRUID.end_practice_session(session, 0),
            tag .. ": the run ends")
        end
    end
end

--=========================================================================================
-- 36) Shared class order: the per-frame hook and the post_init init order (F8 + F9)
--=========================================================================================
-- The six class modules are copy-paste siblings and used to diverge on two orders:
-- the hunter ticked the HUD before the guide, and the paladin built the practice
-- surface before the HUD. The shared contract is now pinned here, per class:
--   * the per-frame class hook ticks the guide BEFORE the HUD;
--   * post_init builds the guide, then the HUD, then the practice surface.
-- Both the runtime order (spies record the calls) and the source order (the call
-- sites) are pinned, so a reordering in either place fails this suite.
do
    local fh = assert(io.open(ROOT .. "classes/druid.lua", "r"))
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
    local ok_init, err_init = pcall(T.DRUID.post_init, T)
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
    local ok_tick, err_tick = pcall(T.DRUID.on_bar_update, T, "mainhand")
    check(ok_tick, "order: the class hook runs with the order spies (" .. tostring(err_tick) .. ")")
    eq(tick_order[1], "guide", "order: the guide ticks before the HUD")
    eq(tick_order[2], "hud", "order: the HUD ticks after the guide")
    eq(#tick_order, 2, "order: the class hook ticks the guide and the HUD once each")

    sbox.st.nextaction_ui = saved.nextaction_ui
    sbox.st.hud = saved.hud
    sbox.st.practice_ui = saved.practice_ui

end

--=========================================================================================
-- 37) Audit F4 (class side): the rank latch tells "absent" from "unresolved"
--     The resolver's verdict is three-valued (bench/f4_family_spell_id_2026-10-19.md):
--     a client that refutes every candidate is FINAL (the negative latches), a client
--     that cannot answer is RETRYABLE (nothing latches, the next attempt asks again).
--     Both resolution directions are pinned too: the TBC client resolves by NAME, the
--     Era client by ID.
--=========================================================================================
do
    -- (a) ABSENT: the client refutes every Maul rank. The negative is FINAL - it
    --     latches and the table is never walked again, not even after the retry window.
    local ab = build({ known = {} })
    local ABT = ab.ST
    ABT.interfaces_are_initialised = true
    ABT.maul_queued = true
    ab.rage_cost = { { cost = 10 } }
    ABT.DRUID.on_rage_update(ABT)
    eq(ab.get_family_spell_id_state_calls, 1, "F4 absent: the client is asked once")
    eq(ab.cost_queries, 0, "F4 absent: a refuted rank reads no rage cost")
    ab.clock = 6
    ABT.DRUID.on_rage_update(ABT)
    eq(ab.get_family_spell_id_state_calls, 1, "F4 absent: the negative is final (never re-walked)")

    -- (b) UNRESOLVED: the client cannot answer (its GetSpellInfo raises). Nothing is
    --     latched, so the next attempt asks again once the retry backoff has passed -
    --     a cold spell book can no longer poison the rank for the rest of the session.
    local us = build({ known = {} })
    local UST = us.ST
    UST.interfaces_are_initialised = true
    UST.maul_queued = true
    us.rage_cost = { { cost = 10 } }
    us.spell_info_throws = true
    UST.DRUID.on_rage_update(UST)
    eq(us.get_family_spell_id_state_calls, 1, "F4 unresolved: the client is asked once")
    eq(us.cost_queries, 0, "F4 unresolved: an unanswered rank reads no rage cost")
    -- Still silent: the retry backoff holds the walk (no hot loop per bar frame).
    UST.DRUID.on_rage_update(UST)
    eq(us.get_family_spell_id_state_calls, 1, "F4 unresolved: the retry backoff holds the walk")
    -- The client answers again after the backoff: the rank resolves and latches.
    us.spell_info_throws = false
    us.known[48480] = true
    us.clock = 6
    UST.DRUID.on_rage_update(UST)
    eq(us.get_family_spell_id_state_calls, 2, "F4 unresolved: the attempt after the backoff asks again")
    eq(us.cost_queries, 1, "F4 unresolved: the resolved rank reaches the cost query")
    eq(us.last_cost_id, 48480, "F4 unresolved: the cost reads the rank the client confirmed")
    -- The resolved rank latches: no further walk.
    UST.DRUID.on_rage_update(UST)
    eq(us.get_family_spell_id_state_calls, 2, "F4 unresolved: the resolved rank latches")

    -- (c) ERA: the rank resolves by ID - the client is never asked by name.
    local era = build({ project = 2, known = { [48480] = true } })
    local ERT = era.ST
    ERT.interfaces_are_initialised = true
    era.spell_queries = {}
    ERT.DRUID.resolve_guide_icons()
    eq(ERT.DRUID.guide.slots[1].spell_id, 48480, "F4 Era: the rank resolves by ID and latches")
    local era_asked_by_name = false
    for i = 1, #era.spell_queries do
        if type(era.spell_queries[i]) == "string" then era_asked_by_name = true end
    end
    check(not era_asked_by_name, "F4 Era: the client is never asked by name")

    -- (d) TBC: a client that answers NO id resolves the rank through the NAME path
    --     (the operator rule: the TBC client indexes names, never bare ids).
    local tbc = build({ project = 5, name_only_client = true, known = { [48480] = true } })
    local TBT = tbc.ST
    TBT.interfaces_are_initialised = true
    TBT.DRUID.post_init(TBT)
    tbc.rage_cost = { { cost = 10 } }
    eq(tbc.st.api.GetSpellInfo(48480), nil, "F4 TBC: the name-only client answers no id")
    local tbc_inputs = TBT.DRUID.gather_guide_inputs(TBT, {})
    eq(tbc_inputs.maul_cost, 10,
        "F4 TBC: the rank resolves through the NAME path (the client answers no id)")
    local tbc_asked_by_name = false
    for i = 1, #tbc.spell_queries do
        if type(tbc.spell_queries[i]) == "string" then tbc_asked_by_name = true end
    end
    check(tbc_asked_by_name, "F4 TBC: the client is asked by NAME")
end

--=========================================================================================
-- 36) Practice surface: the rotation table, the scenario step and the druid drills
--=========================================================================================
-- The shared practice engine looks the class surface up by player_class: the rotation
-- table, the scenario step and the drill list. The scenario step and the priority
-- drill run the SHIPPED guide engine (the pure module is loaded into the sandbox
-- above), so these pins are the real decision model, not a copy of it.
do
    local sb = build()
    local ST = sb.ST
    local rotation = ST.DRUID.practice_rotation
    check(type(rotation) == "table", "the druid ships a rotation table")
    check(#rotation > 0, "the rotation table is not empty")
    -- Every entry names an action, a family gate, a label and its source. The gate
    -- rides in two shapes: the sim priority rows carry the single `family` of the
    -- slice they belong to, the APL utility spine carries the cross-class
    -- `families` set.
    local families = {}
    for i = 1, #rotation do
        local entry = rotation[i]
        check(type(entry.action) == "string" and entry.action ~= "",
            "rotation entry " .. tostring(i) .. " names an action")
        local gated = (type(entry.family) == "string" and entry.family ~= "")
            or (type(entry.families) == "table")
        check(gated, "rotation entry " .. tostring(i) .. " names its family gate")
        check(type(entry.label) == "string" and entry.label ~= "",
            "rotation entry " .. tostring(i) .. " carries a label")
        check(type(entry.source) == "string"
            and (entry.source:find("sim ", 1, true) ~= nil
                or entry.source:find("wowsims/", 1, true) ~= nil),
            "rotation entry " .. tostring(i) .. " cites its source")
        -- HU-13's two flags ride every row: the read and the arm.
        check(entry.live == true or entry.live == false,
            "rotation entry " .. tostring(i) .. " carries the live flag")
        check(entry.engine == true or entry.engine == false,
            "rotation entry " .. tostring(i) .. " carries the engine flag")
        if entry.family then
            families[entry.family] = true
        end
        if type(entry.families) == "table" then
            for family in pairs(entry.families) do
                families[family] = true
            end
        end
    end
    for _, family in ipairs({ "ERA", "SOD", "TBC", "WRATH", "FOREVER", "BEAR" }) do
        check(families[family] == true, "the rotation table covers " .. family)
    end
    -- The Wrath slice is the sim's priority order (the audit's W1-W9 chain).
    local wrath = ST.DRUID.practice_rotation_for("WRATH")
    eq(#wrath, 10, "the Wrath slice carries the sim's ten priority slots")
    eq(wrath[1].action, "tigers_fury", "Wrath: Tiger's Fury is the first priority")
    eq(wrath[2].action, "faerie_fire", "Wrath: the Faerie Fire fish follows")
    eq(wrath[3].action, "berserk", "Wrath: Berserk follows the fish")
    eq(wrath[4].action, "savage_roar", "Wrath: the Roar upkeep follows")
    eq(wrath[5].action, "shred", "Wrath: the Omen proc is a free Shred")
    eq(wrath[6].action, "rip", "Wrath: the Rip finisher follows the proc")
    eq(wrath[7].action, "mangle", "Wrath: Mangle sits above Rake")
    eq(wrath[8].action, "rake", "Wrath: Rake follows Mangle")
    eq(wrath[9].action, "bite", "Wrath: the execute Bite sits above the builder")
    eq(wrath[10].action, "shred", "Wrath: the builder is the last resort")
    -- The SoD slice leads with the two cooldowns and the Roar upkeep.
    local sod = ST.DRUID.practice_rotation_for("SOD")
    eq(sod[1].action, "tigers_fury", "SoD: Tiger's Fury is the first priority")
    eq(sod[2].action, "berserk", "SoD: Berserk follows Tiger's Fury")
    eq(sod[3].action, "savage_roar", "SoD: the Roar upkeep is the first branch")
    -- The Era slice: the Omen proc first, then the Rip, then the builder.
    local era = ST.DRUID.practice_rotation_for("ERA")
    eq(era[1].action, "shred", "Era: the Omen proc is the sim's first branch")
    eq(era[2].action, "rip", "Era: the Rip finisher follows")
    -- The bear chain is its own slice (shared by every family).
    local bear = ST.DRUID.practice_rotation_for("BEAR")
    eq(#bear, 3, "the bear chain carries three slots")
    eq(bear[1].action, "ride", "bear: a queued Maul rides the swing")
    eq(bear[2].action, "maul", "bear: the Maul comes next")
    eq(bear[3].action, "mangle", "bear: the Mangle is the fallback")
    -- The family helper: the running client (the sandbox is the Wrath project).
    eq(ST.DRUID.practice_rotation_family(), "WRATH", "the rotation family follows the client")
    eq(#ST.DRUID.practice_rotation_for("NOPE"), 0, "an unknown family has no rotation slice")

    -- The scenario step: the shipped guide engine's own answer.
    local step = ST.DRUID.practice_scenario_step
    check(type(step) == "function", "the druid ships a scenario step")
    local rip_state = {
        family = "WRATH", form_index = 3, combo_points = 5, energy = 50,
        rip_remaining = 0, rake_remaining = 10, mangle_remaining = 10,
        sr_remaining = 20, tf_ready = false, ff_ready = false, berserk_ready = false,
    }
    local expected = step(ST, rip_state)
    check(type(expected) == "table", "the scenario step answers an action")
    eq(expected.action, "rip", "the scenario step answers the guide's own Rip")
    check(type(expected.reason) == "string" and #expected.reason > 0,
        "the scenario step carries a reason")
    -- A spell-naming hold is a CALL too: the key is the spell's, not the overlay
    -- text. Nine of the guide's ten hold texts name a spell to PRESS, so the step
    -- is a decision to cast and never an explicit hold statement (the operator
    -- ruling HU-8: a hold is a decision to CAST NOTHING - the druid's guide names
    -- the spell instead).
    local held = step(ST, {
        family = "WRATH", form_index = 3, combo_points = 0, energy = 10,
        tf_ready = true, gcd_remaining = 0, clearcast = false,
    })
    eq(held.action, "tigers_fury", "a Tiger's Fury hold is the spell key")
    eq(held.hold, nil,
        "a spell-naming hold states no hold: the guide names a spell to press")
    -- The ONE exception: the bear chain's "RIDE" (the queued Maul) means PRESS
    -- NOTHING, so it is stated as a hold - never as an action. A synthetic "ride"
    -- key would be a button the player can only press dishonestly (points for
    -- idling, which the engine's contract forbids) and would bank a false
    -- mis-pick in the priority drill for every real pick.
    local held_bear = step(ST, {
        family = "WRATH", form_index = 1, rage = 0, maul_queued = true,
    })
    eq(held_bear.action, nil,
        "the queued Maul names no action: RIDE means press nothing")
    eq(held_bear.hold, true, "the queued Maul states an explicit hold")
    eq(held_bear.reason, "RIDE", "the hold carries the guide's own caption")
    -- A proven false survives the merge: the SoD S2 branch reads tf_ready == false.
    eq(step(ST, {
        family = "ERA", sod_runes = true, form_index = 3, combo_points = 0, energy = 60,
        tf_ready = false, berserk_ready = true,
    }).action, "berserk", "a proven 'Tiger's Fury is on cooldown' survives the merge")
    -- The Omen proc is a free Shred.
    eq(step(ST, {
        family = "WRATH", form_index = 3, combo_points = 0, energy = 50, clearcast = true,
        rip_remaining = 10, rake_remaining = 10, mangle_remaining = 10, sr_remaining = 20,
    }).action, "shred", "the Omen proc is a free Shred")
    -- The state may sit in ctx.resources / ctx.cooldowns too.
    eq(step(ST, {
        family = "WRATH", form_index = 3, combo_points = 5, energy = 50,
        resources = { rip_remaining = 0, rake_remaining = 10, mangle_remaining = 10,
            sr_remaining = 20 },
        cooldowns = { tf_ready = false, ff_ready = false, berserk_ready = false },
    }).action, "rip", "the ctx may carry the state in resources / cooldowns")
    -- The engine's own cooldown table drops the "_remaining" suffix.
    eq(step(ST, {
        family = "WRATH", form_index = 3, combo_points = 5,
        resources = { energy = 50 },
        cooldowns = { rip = 0, rake = 10, mangle = 10, sr = 20 },
    }).action, "rip", "the engine's stripped cooldown names feed the guide inputs")
    -- An undecidable state answers nil (the engine grades "unknown").
    eq(step(ST, nil), nil, "no ctx: no decision")
    eq(step(ST, { family = "WRATH", form_index = 0 }), nil, "an unknown form decides nothing")
    -- The live path: the class gathers its own state (the engine's own rule: a class
    -- that needs more gathers it itself).
    local live = build()
    live.ST.form_index = 3
    live.power_type = 3
    live.power = 50
    live.clock = 10
    local live_step = live.ST.DRUID.practice_scenario_step(live.ST, { now = 10 })
    check(type(live_step) == "table" and type(live_step.action) == "string",
        "the scenario step answers from the class's own gathered state")
    check(type(live_step.reason) == "string" and #live_step.reason > 0,
        "the live step carries a reason too")
    -- Retail: the guide itself is inert there, so the scenario decides nothing.
    local retail = build({ project = 1 })
    eq(retail.ST.DRUID.practice_scenario_step(retail.ST,
        { family = "RETAIL", form_index = 3, combo_points = 5, energy = 50 }), nil,
        "Retail: the guide is inert, so the scenario decides nothing")

    -- The drill list: the audit's target set (D-D1..D-D4).
    local drills = ST.DRUID.practice_drills
    check(type(drills) == "table", "the druid ships a drill list")
    eq(#drills, 4, "the druid ships the four audited drills")
    local by_key = {}
    for i = 1, #drills do
        local drill = drills[i]
        check(type(drill.key) == "string" and drill.key ~= "",
            "drill " .. tostring(i) .. " has a key")
        check(type(drill.label) == "string" and drill.label ~= "",
            "drill " .. tostring(i) .. " has a label")
        check(type(drill.grade) == "function", "drill " .. tostring(i) .. " grades")
        by_key[drill.key] = drill
    end
    for _, key in ipairs({ "druid_finisher_order", "druid_powershift_rework",
        "druid_roar_upkeep", "druid_bite_execute" }) do
        check(by_key[key] ~= nil, "the drill set carries " .. key)
    end

    -- D-D1: the priority drill grades the guide's own pick.
    local order = by_key.druid_finisher_order.grade
    local order_ctx = {
        family = "WRATH", form_index = 3, combo_points = 5, energy = 50,
        rip_remaining = 0, rake_remaining = 10, mangle_remaining = 10, sr_remaining = 20,
    }
    local hit = {}
    for k, v in pairs(order_ctx) do hit[k] = v end
    hit.last_action = "rip"
    eq(order(ST, hit), "S", "the priority drill: the guide's own pick is an S")
    local miss = {}
    for k, v in pairs(order_ctx) do miss[k] = v end
    miss.last_action = "shred"
    eq(order(ST, miss), "F", "the priority drill: a wrong pick without a ledger is an F")
    -- With the engine's ledger the band is the spec's window over the last ten picks.
    local ledger = {}
    local windowed = {}
    for k, v in pairs(order_ctx) do windowed[k] = v end
    windowed.state = ledger
    windowed.last_action = "shred"
    eq(order(ST, windowed), "A", "the priority drill: one mis-pick in the window is an A")
    windowed.last_action = "rip"
    eq(order(ST, windowed), "A", "the priority drill: the window keeps the mis-pick")
    eq(order(ST, nil), nil, "the priority drill: no state grades nothing")

    -- D-D2: the shift drill grades the SIM's trigger, not the shipped 20-energy rule
    -- (the operator ruling: a drill must mirror the real thing).
    local shift = by_key.druid_powershift_rework.grade
    eq(shift(ST, { family = "TBC", energy = 8, last_action = "shift" }), "S",
        "the shift drill: below the sim's 10-energy line is an S")
    eq(shift(ST, { family = "TBC", energy = 15, last_action = "shift" }), "A",
        "the shift drill: 5 above the sim's line is an A (the 20-energy rule would say S)")
    eq(shift(ST, { family = "TBC", energy = 25, last_action = "shift" }), "B",
        "the shift drill: 15 above the sim's line is a B")
    eq(shift(ST, { family = "TBC", energy = 45, last_action = "shift" }), "D",
        "the shift drill: far above the sim's line is a wasted shift")
    eq(shift(ST, { family = "TBC", energy = 100, last_action = "shift" }), "F",
        "the shift drill: a capped pool is an F (the shift was never taken)")
    -- ERA / SoD: the cost trigger - the energy at the next tick below the builder cost.
    eq(shift(ST, { family = "ERA", energy = 30, last_action = "shift" }), "S",
        "the shift drill: below the builder cost the sim shifts")
    eq(shift(ST, { family = "ERA", energy = 45, last_action = "shift" }), "A",
        "the shift drill: 3 above the builder cost is an A")
    eq(shift(ST, { family = "SOD", energy = 30, last_action = "shift" }), "S",
        "the shift drill: the SoD token shifts on the same cost trigger")
    eq(shift(ST, { family = "ERA", energy = 35, tick_remaining = 1, last_action = "shift" }),
        "A", "the shift drill: the energy at the next tick is what the sim reads")
    eq(shift(ST, { family = "ERA", energy = 35, tick_remaining = 1, mangle_cost = 50,
        last_action = "shift" }), "S",
        "the shift drill: the live builder cost moves the line")
    -- No shift basis on Wrath / Forever; no energy: no grade; a spend: not an attempt.
    eq(shift(ST, { family = "WRATH", energy = 5, last_action = "shift" }), nil,
        "the shift drill: Wrath has no shift basis")
    eq(shift(ST, { family = "FOREVER", energy = 5, last_action = "shift" }), nil,
        "the shift drill: Forever has no shift basis")
    eq(shift(ST, { family = "TBC" }), nil, "the shift drill: an unknown energy grades nothing")
    eq(shift(ST, { family = "TBC", energy = 8, last_action = "shred" }), "S",
        "the shift drill: it judges the moment, so a spend does not change the verdict")

    -- D-D3: the Roar upkeep (the sim refreshes on expiry and clips to cover the end).
    local roar = by_key.druid_roar_upkeep.grade
    eq(roar(ST, { family = "ERA", sr_remaining = 0, last_action = "savage_roar" }), nil,
        "the Roar drill: the Era sim has no Savage Roar")
    eq(roar(ST, { family = "TBC", sr_remaining = 0, last_action = "savage_roar" }), nil,
        "the Roar drill: the TBC sim has no Savage Roar")
    eq(roar(ST, { family = "SOD", sr_remaining = 0, combo_points = 3,
        sr_expired_seconds = 0 }), "S",
        "the Roar drill: an on-time repair is an S")
    eq(roar(ST, { family = "SOD", sr_remaining = 0, combo_points = 3,
        sr_expired_seconds = 3 }), "B",
        "the Roar drill: a repair 3 s late is a B")
    eq(roar(ST, { family = "SOD", sr_remaining = 0, combo_points = 3,
        sr_expired_seconds = 9 }), "C",
        "the Roar drill: a lapsed upkeep is a C")
    eq(roar(ST, { family = "SOD", sr_remaining = 0, combo_points = 3,
        builders_since_expiry = 2 }), "D",
        "the Roar drill: a lapsed upkeep that burned a builder is a D")
    eq(roar(ST, { family = "SOD", sr_remaining = 5, combo_points = 3,
        time_to_die = 20 }), "S",
        "the Roar drill: the cover-to-end clip is an S")
    eq(roar(ST, { family = "SOD", sr_remaining = 5, combo_points = 3 }), nil,
        "the Roar drill: a cast while the Roar is up is not an upkeep event")
    eq(roar(ST, { family = "SOD", sr_remaining = 0, combo_points = 3, sr_seen = false }),
        "F", "the Roar drill: a Roar never maintained is an F")
    eq(roar(ST, { family = "SOD" }), nil, "the Roar drill: an unknown Roar state grades nothing")

    -- D-D4: the execute (the sim Bites only at the end, with both minima met).
    local bite = by_key.druid_bite_execute.grade
    eq(bite(ST, { family = "ERA", time_to_die = 5, last_action = "bite" }), nil,
        "the execute drill: the Era sim never Bites")
    eq(bite(ST, { family = "SOD", time_to_die = 5, last_action = "bite" }), nil,
        "the execute drill: the SoD sim never Bites")
    eq(bite(ST, { family = "WRATH", time_to_die = 5, combo_points = 5,
        rip_remaining = 8, sr_remaining = 8, last_action = "bite" }), "S",
        "the execute drill: the Bite in the window with both minima is an S")
    eq(bite(ST, { family = "WRATH", time_to_die = 5, combo_points = 5,
        rip_remaining = 2, sr_remaining = 8, last_action = "bite" }), "A",
        "the execute drill: one minimum short by 2 s is an A")
    eq(bite(ST, { family = "WRATH", time_to_die = 5, combo_points = 5,
        rip_remaining = 0, sr_remaining = 8, last_action = "bite" }), "B",
        "the execute drill: one minimum short by 4 s is a B")
    eq(bite(ST, { family = "WRATH", time_to_die = 60, combo_points = 5,
        rip_remaining = 8, sr_remaining = 8, last_action = "bite" }), "D",
        "the execute drill: a mid-fight Bite is a D")
    eq(bite(ST, { family = "WRATH", time_to_die = 15, combo_points = 5,
        rip_remaining = 8, sr_remaining = 8, last_action = "bite" }), "C",
        "the execute drill: a Bite just outside the window is a C")
    eq(bite(ST, { family = "WRATH", time_to_die = 5, combo_points = 5 }), "F",
        "the execute drill: no Bite in the window is an F")
    eq(bite(ST, { family = "WRATH", time_to_die = 5, combo_points = 5,
        last_action = "bite" }), nil,
        "the execute drill grades nothing on an unknown minimum")
end

--=========================================================================================
-- 37) The class-side feature closures: the world latency and the Omen-ICD probe
--=========================================================================================
do
    -- The latency: the sim's Tiger's Fury leeway reads max(gcd_remaining, latency),
    -- so the W1 line needs the real reading instead of the GCD remainder alone.
    local sb = build()
    local ST = sb.ST
    ST.latency = { world_ms = 120 }
    local inputs = ST.DRUID.gather_guide_inputs(ST, {})
    near(inputs.latency, 0.12, "the gather reads the raw world latency in seconds")
    ST.latency = { world_ms = nil }
    local unmeasured = ST.DRUID.gather_guide_inputs(ST, {})
    eq(unmeasured.latency, nil, "an unmeasured latency reads nil (the W1 line degrades)")
    ST.latency = nil
    eq(ST.DRUID.gather_guide_inputs(ST, {}).latency, nil,
        "no latency table at all: the input stays unknown")

    -- The Omen of Clarity's internal cooldown: the proc buff is the witness.
    local osb = build()
    local OST = osb.ST
    OST.interfaces_are_initialised = true
    OST.DRUID.post_init(OST)
    osb.class_db.nextaction_enabled = true
    OST.form_index = 3
    osb.power_type = 3
    osb.power = 50
    osb.clock = 100
    osb.player_auras = {
        { name = "Clearcasting", spell_id = 16870, source = "player",
            duration = 10, expiration = 110 },
    }
    OST.DRUID.on_bar_update(OST, "mainhand")
    local during = OST.DRUID.gather_guide_inputs(OST, {})
    eq(during.clearcast, true, "the proc reads as a Clearcast")
    eq(during.omen_icd_ready, false, "the Omen proc up: the ICD is not ready")
    -- The proc is gone and a full proc window has passed: the lockout has expired.
    osb.player_auras = {}
    osb.clock = 101
    OST.DRUID.on_bar_update(OST, "mainhand")
    local early = OST.DRUID.gather_guide_inputs(OST, {})
    eq(early.omen_icd_ready, nil,
        "the proc just fell: the lockout window has not passed yet, so the ICD stays unknown")
    osb.clock = 111
    OST.DRUID.on_bar_update(OST, "mainhand")
    local after = OST.DRUID.gather_guide_inputs(OST, {})
    eq(after.clearcast, nil, "the proc is gone: no Clearcast")
    eq(after.omen_icd_ready, true, "the Omen lockout window has passed: the ICD is ready")
    -- A fresh sandbox has never seen a proc: the ICD stays unknown.
    local fresh = build()
    fresh.ST.interfaces_are_initialised = true
    fresh.ST.DRUID.post_init(fresh.ST)
    fresh.class_db.nextaction_enabled = true
    fresh.clock = 100
    fresh.ST.DRUID.on_bar_update(fresh.ST, "mainhand")
    eq(fresh.ST.DRUID.gather_guide_inputs(fresh.ST, {}).omen_icd_ready, nil,
        "no proc seen yet: the Omen ICD stays unknown (the fish stays dormant)")

    -- The Roar's own window: the class remembers the aura's expiry and whether the
    -- Roar was ever up this fight (the upkeep drill's two measures).
    local ssb = build()
    local SST = ssb.ST
    SST.interfaces_are_initialised = true
    SST.DRUID.post_init(SST)
    ssb.class_db.nextaction_enabled = true
    ssb.clock = 100
    ssb.player_auras = {
        { name = "Savage Roar", spell_id = 52610, source = "player",
            duration = 30, expiration = 130 },
    }
    SST.DRUID.on_bar_update(SST, "mainhand")
    local with_roar = SST.DRUID.gather_guide_inputs(SST, {})
    check(with_roar.sr_remaining ~= nil, "the Roar aura feeds the Roar input")
    eq(with_roar.sr_seen, true, "the Roar was up this fight")
    eq(with_roar.sr_expired_seconds, nil, "the Roar is up: no expired measure")
    -- The Roar falls: the class knows how long it has been down.
    ssb.player_auras = {}
    ssb.clock = 133
    SST.DRUID.on_bar_update(SST, "mainhand")
    local without = SST.DRUID.gather_guide_inputs(SST, {})
    near(without.sr_expired_seconds, 3, "the Roar has been down for 3 s")
    -- A fight that never saw the Roar: the class says so (in combat, scan ran).
    local nb = build()
    local NST = nb.ST
    NST.interfaces_are_initialised = true
    NST.DRUID.post_init(NST)
    NST.in_combat = true
    nb.class_db.nextaction_enabled = true
    nb.clock = 100
    NST.DRUID.on_bar_update(NST, "mainhand")
    eq(NST.DRUID.gather_guide_inputs(NST, {}).sr_seen, false,
        "in combat with a scan and no Roar: the Roar was never up")
    -- The gathered verdict reaches the drill: a proven false must survive the merge.
    local roar_drill = NST.DRUID.practice_drills[3].grade
    eq(roar_drill(NST, { sr_remaining = 0 }), "F",
        "the Roar drill: the gathered 'never maintained' verdict grades the F")
    -- The fight ends: the latch dies with it.
    NST.DRUID.on_combat_exit(NST)
    eq(NST.DRUID.gather_guide_inputs(NST, {}).sr_seen, nil,
        "the fight's end clears the Roar latch")
end

--=========================================================================================
-- 38) The Wolfshead Helm probe (bench/filed_closure_sweep_2026-10-19.md §7 BS-2): the
--     gather publishes the tri-state; nothing consumes it yet
--=========================================================================================
-- The sim's own check is HasItemEquipped(8345) (tbc-new feralcat.go) and 8345 is the
-- wowhead-confirmed Wolfshead Helm. The read path is compat.lua's api.is_item_equipped
-- (true / false / nil - unknown is never false). The input is a RESERVED plug-in point:
-- the Furor half of the powershift basis is still unproven (DU-16), so no rule reads it
-- and the SHIFT branch stays removed.
do
    -- The Helm is worn: the probe answers true.
    local sb = build({ equipment_items = { [1] = 8345 } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    local worn
    with_equipment_range(function()
        worn = ST.DRUID.gather_guide_inputs(ST, {})
    end)
    eq(worn.wolfshead_equipped, true,
        "the gather: the equipped Wolfshead Helm reads true")
    eq(sb.item_queries[#sb.item_queries], 8345,
        "the gather asks the probe for the sim's own id (8345)")

    -- The read works and no equipped slot holds it: a proven false, NOT nil.
    local other = build({ equipment_items = { [1] = 12345 } })
    local OST = other.ST
    OST.interfaces_are_initialised = true
    OST.DRUID.post_init(OST)
    local readable
    with_equipment_range(function()
        readable = OST.DRUID.gather_guide_inputs(OST, {})
    end)
    eq(readable.wolfshead_equipped, false,
        "the gather: a readable non-match reads false (not nil)")

    -- The client cannot answer at all: unknown, never a guess about the gear.
    local blind = build()
    local BST = blind.ST
    BST.interfaces_are_initialised = true
    BST.DRUID.post_init(BST)
    local unknown
    with_equipment_range(function()
        unknown = BST.DRUID.gather_guide_inputs(BST, {})
    end)
    eq(unknown.wolfshead_equipped, nil,
        "the gather: an unreadable equipment read stays unknown (nil)")

    -- An empty equipment map is not a proof either: no readable slot at all, so
    -- the read is unknown, never "not equipped".
    local empty = build({ equipment_items = {} })
    local EST = empty.ST
    EST.interfaces_are_initialised = true
    EST.DRUID.post_init(EST)
    local blank
    with_equipment_range(function()
        blank = EST.DRUID.gather_guide_inputs(EST, {})
    end)
    eq(blank.wolfshead_equipped, nil,
        "the gather: no readable equipped slot stays unknown (never false)")

    -- Stale reuse: a previous true never survives an unreadable read.
    local reused = { wolfshead_equipped = true }
    local cleared
    with_equipment_range(function()
        cleared = BST.DRUID.gather_guide_inputs(BST, reused)
    end)
    eq(cleared.wolfshead_equipped, nil,
        "the gather: a stale Helm reading is cleared when the read goes unknown")
    eq(reused.wolfshead_equipped, nil,
        "the gather: the reused table never keeps a stale Helm reading")

    -- The throttled read (the hot-read fix): the probe walks all 19 equipped
    -- slots, so reading it on every gather costs ~380 item reads/s at the
    -- guide's 0.05 s tick - for an input no rule reads yet. Inside the throttle
    -- window the cached answer is published and the probe is not asked again;
    -- once the window closes the probe runs again and a gear change shows up.
    local calls_before = #sb.item_queries
    for _ = 1, 20 do
        with_equipment_range(function()
            ST.DRUID.gather_guide_inputs(ST, {})
        end)
    end
    eq(#sb.item_queries - calls_before, 0,
        "the gather: twenty gathers inside the throttle window never re-read the gear")
    eq(ST.DRUID.gather_guide_inputs(ST, {}).wolfshead_equipped, true,
        "the gather: the cached answer is published between refreshes")

    -- The window closes: the probe runs again and a gear change becomes visible.
    other.clock = other.clock + 2
    other.equipment_items[1] = 8345
    local refreshed
    with_equipment_range(function()
        refreshed = OST.DRUID.gather_guide_inputs(OST, {})
    end)
    eq(refreshed.wolfshead_equipped, true,
        "the gather: after the throttle window the gear change is visible")
    eq(#other.item_queries, 2,
        "the gather: the probe runs again once the throttle window has passed")
end

--=========================================================================================
-- The pull moment in the ctx (BS-8 item 2 / P-17) + the "no hold" contract
--=========================================================================================
-- The druid publishes NO ctx builder: the shared engine's fallback builder owns the
-- ctx, and it is the one that carries the live pull clock (the engine's
-- apply_pull_clock). So the class-side read has no builder to land in, and the
-- class's step must never disturb a pull-carrying ctx.
-- The druid has NO general hold concept: nine of the guide's ten hold texts name a
-- spell to PRESS, so a step is either an action or unknown - never an explicit hold
-- statement. The tenth ("RIDE", the bear chain's queued Maul) is the press-nothing
-- hold and IS stated as one (section 41 below).
do
    local sb = build()
    local ST = sb.ST
    eq(ST.DRUID.practice_context, nil,
        "pull: the druid publishes no ctx builder (the engine's fallback owns it)")
    local answer = ST.DRUID.practice_scenario_step(ST, { now = 10,
        family = "WRATH", form_index = 3, combo_points = 5, energy = 50,
        rip_remaining = 0, rake_remaining = 10, mangle_remaining = 10,
        sr_remaining = 20, pull_at = 120, pull_in_seconds = 20 })
    eq(answer and answer.action, "rip",
        "pull: a pull-carrying ctx still answers the engine's own verdict")
    eq(answer and answer.hold, nil, "pull: an action step states no hold")

    -- The engine's own rule for a step with neither an action nor a hold: it stays
    -- UNKNOWN, and an unknown decision records no attempt (never a wrong grade).
    local practice_st = {}
    local chunk = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(chunk, setmetatable({}, { __index = _G }))
    chunk("SwedgeTimer", practice_st)
    practice_st.DRUID = ST.DRUID
    local H = practice_st.practice and practice_st.practice.harness
    check(type(H) == "table", "hold: the shared harness is loaded")
    local unknown_answer = H.practice_scenario_step("DRUID", ST, nil)
    eq(unknown_answer, nil, "hold: an unreadable state stays unknown (no hold statement)")
    local unknown_run = H.new_rotation_run()
    local unknown = H.rotation_run_decide(unknown_run, nil, "shred")
    eq(unknown.outcome, "unknown", "hold: an unknown step stays unknown")
    eq(H.ROTATION_OUTCOME_GRADES[unknown.outcome], nil,
        "hold: an unknown decision records no attempt")
    eq(unknown_run.mispicks, 0, "hold: an unknown decision is never a mis-pick")
end

--=========================================================================================
-- 39) The APL utility layer (the rotation table's utility spine) + the pre-pull table
--=========================================================================================
-- The wowsims APLs carry an upkeep/cooldown layer the sim's own rotation.go does not
-- (bench/rotation_gap_vs_apl_2026-10-20.md section 4.3): the form upkeep, the party
-- buff rider, the mana tool, the burst cooldowns and the builder the APL names. The
-- spine rows carry the per-family spell id, the APL citation and HU-13's two flags
-- (`live` = the read exists, `engine` = the frozen engine has an arm).
do
    local sb = build()
    local ST = sb.ST
    local rotation = ST.DRUID.practice_rotation
    local by_action = {}
    for i = 1, #rotation do
        local entry = rotation[i]
        if entry.families then
            local list = by_action[entry.action] or {}
            list[#list + 1] = entry
            by_action[entry.action] = list
        end
    end

    -- The Cat Form upkeep: the APL's form row on four families, ARMED since
    -- 2026-10-20 (the gate the lane filed is now the class's own Feral-tree
    -- probe plus the player's Cat Form aura plus the form state).
    local cat_form = by_action.cat_form
    check(cat_form ~= nil, "utility: the rotation table carries the Cat Form row")
    local cat_row = cat_form and cat_form[#cat_form]
    if cat_row then
        eq(cat_row.ids.ERA, 768, "utility: Cat Form is 768 on Era")
        eq(cat_row.ids.SOD, 768, "utility: Cat Form is 768 on SoD")
        eq(cat_row.ids.TBC, 768, "utility: Cat Form is 768 on TBC")
        eq(cat_row.ids.FOREVER, 768, "utility: Cat Form is 768 on Forever")
        eq(cat_row.families.WRATH, nil, "utility: the WotLK APL carries no Cat Form row")
        eq(cat_row.live, true, "utility: the Cat Form read exists")
        eq(cat_row.engine, true, "utility: the Cat Form line has an engine arm")
        check(type(cat_row.gate) == "string" and cat_row.gate:find("feral_spec", 1, true) ~= nil,
            "utility: the Cat Form row names the spec gate the arm proves")
        check(cat_row.gate:find("cat_form_active", 1, true) ~= nil,
            "utility: the Cat Form row names the Cat Form aura proof")
        check(cat_row.needs == nil,
            "utility: the Cat Form row carries no filed need any more")
        check(cat_row.source:find("i=14", 1, true) ~= nil,
            "utility: the Cat Form row cites the Era APL index")
        check(cat_row.source:find("i=0", 1, true) ~= nil,
            "utility: the Cat Form row cites the SoD APL index")
        check(cat_row.source:find("i=1", 1, true) ~= nil,
            "utility: the Cat Form row cites the Forever APL index")
    end

    -- The Leader of the Pack (the Era APL's i=1): the client's own id (17007), not
    -- the id the APL casts (13494 - "Haste" in the 1.15 client).
    local lop = by_action.leader_of_the_pack
    check(lop ~= nil, "utility: the rotation table carries the Leader of the Pack row")
    local lop_row = lop and lop[#lop]
    if lop_row then
        eq(lop_row.ids.ERA, 17007, "utility: the Leader of the Pack is 17007 on Era")
        eq(lop_row.families.SOD, nil, "utility: the SoD APL carries no Leader of the Pack row")
        eq(lop_row.live, true, "utility: the Leader of the Pack read exists")
        eq(lop_row.engine, true, "utility: the Leader of the Pack has an engine arm")
        check(lop_row.source:find("13494", 1, true) ~= nil,
            "utility: the Leader of the Pack row names the APL's dead id")
    end

    -- The Faerie Fire upkeep (the Era and TBC rows).
    local ff = by_action.faerie_fire
    check(ff ~= nil, "utility: the rotation table carries the Faerie Fire upkeep row")
    local ff_row = ff and ff[#ff]
    if ff_row then
        eq(ff_row.ids.ERA, 17392, "utility: the Era Faerie Fire is 17392")
        eq(ff_row.ids.TBC, 27011, "utility: the TBC Faerie Fire is 27011")
        eq(ff_row.live, true, "utility: the Faerie Fire read exists")
        eq(ff_row.engine, true, "utility: the Faerie Fire upkeep has an engine arm")
    end

    -- The Claw builder: the read that decides "the Shred cannot land" does not
    -- exist, so the row is filed (live = false, engine = false).
    local claw = by_action.claw
    check(claw ~= nil, "utility: the rotation table carries the Claw row")
    local claw_row = claw and claw[#claw]
    if claw_row then
        eq(claw_row.ids.ERA, 9850, "utility: the Claw is 9850 on Era")
        eq(claw_row.ids.FOREVER, 9850, "utility: the Claw is 9850 on Forever")
        eq(claw_row.live, false, "utility: the Claw read does not exist yet")
        eq(claw_row.engine, false, "utility: the Claw line has no engine arm")
        check(type(claw_row.needs) == "string" and claw_row.needs:find("can_shred", 1, true) ~= nil,
            "utility: the Claw row names the read it waits for")
    end

    -- The Innervate (the mana row on three families).
    local inn = by_action.innervate
    check(inn ~= nil, "utility: the rotation table carries the Innervate row")
    local inn_row = inn and inn[#inn]
    if inn_row then
        eq(inn_row.ids.ERA, 29166, "utility: the Innervate is 29166 on Era")
        eq(inn_row.ids.SOD, 29166, "utility: the Innervate is 29166 on SoD")
        eq(inn_row.ids.FOREVER, 29166, "utility: the Innervate is 29166 on Forever")
        eq(inn_row.families.TBC, nil, "utility: the TBC APL carries no Innervate row")
        eq(inn_row.live, true, "utility: the Innervate read exists")
        eq(inn_row.engine, true, "utility: the Innervate has an engine arm")
    end

    -- The Elune's Light (the Forever row): the id is the APL's own, the name is
    -- UNCONFIRMED outside the APL.
    local el = by_action.elunes_light
    check(el ~= nil, "utility: the rotation table carries the Elune's Light row")
    local el_row = el and el[#el]
    if el_row then
        eq(el_row.ids.FOREVER, 1259799, "utility: the Elune's Light is 1259799 on Forever")
        eq(el_row.families.ERA, nil, "utility: the Elune's Light is the Forever row")
        eq(el_row.live, true, "utility: the Elune's Light read exists")
        eq(el_row.engine, true, "utility: the Elune's Light has an engine arm")
        check(el_row.source:find("UNCONFIRMED", 1, true) ~= nil,
            "utility: the Elune's Light row marks the name UNCONFIRMED")
    end

    -- The Bloodlust (the TBC row): the line CANNOT be evaluated - 2825 is the
    -- Shaman's Bloodlust, a spell the druid does not have, and the APL's own
    -- gate (the "Bloodlust Time" variable) has no addon counterpart. Both flags
    -- say so.
    local bl = by_action.bloodlust
    check(bl ~= nil, "utility: the rotation table carries the Bloodlust row")
    local bl_row = bl and bl[#bl]
    if bl_row then
        eq(bl_row.ids.TBC, 2825, "utility: the Bloodlust is 2825 on TBC")
        eq(bl_row.live, false, "utility: the Bloodlust line cannot be evaluated")
        eq(bl_row.engine, false, "utility: the Bloodlust line has no engine arm")
        check(type(bl_row.needs) == "string" and bl_row.needs:find("GetSpellCooldown", 1, true) ~= nil,
            "utility: the Bloodlust row names the read it has and the gate it lacks")
        check(bl_row.needs:find("shaman", 1, true) ~= nil,
            "utility: the Bloodlust row names the spell the druid cannot cast")
        check(bl_row.needs:find("Bloodlust Time", 1, true) ~= nil,
            "utility: the Bloodlust row names the APL's own variable")
    end

    -- The shipped sim rows carry their per-family id too (the gap analysis found
    -- every one of them id-less).
    local ids_by_rule = {}
    for i = 1, #rotation do
        local entry = rotation[i]
        if entry.rule then
            ids_by_rule[entry.rule] = entry.ids
        end
    end
    eq(ids_by_rule.S1 and ids_by_rule.S1.SOD, 417045,
        "utility: the SoD Tiger's Fury row carries its rune id")
    eq(ids_by_rule.S2 and ids_by_rule.S2.SOD, 417141,
        "utility: the SoD Berserk row carries its rune id")
    eq(ids_by_rule.S3 and ids_by_rule.S3.SOD, 407988,
        "utility: the SoD Savage Roar row carries its rune id")
    eq(ids_by_rule.T2 and ids_by_rule.T2.TBC, 33983,
        "utility: the TBC Mangle row carries its id")
    eq(ids_by_rule.T5 and ids_by_rule.T5.TBC, 27002,
        "utility: the TBC Shred row carries its id")
    eq(ids_by_rule.F1 and ids_by_rule.F1.FOREVER, 1322605,
        "utility: the Forever Shifting Power row carries its id")
    eq(ids_by_rule.F5, nil,
        "utility: the Forever slice carries no Mangle row (the client has no Mangle)")
    -- HU-14 (closed 2026-10-20): the FOREVER rotation names no Mangle at all.
    local forever_mangle_rows = 0
    for i = 1, #rotation do
        local entry = rotation[i]
        if entry.action == "mangle" and entry.family == "FOREVER" then
            forever_mangle_rows = forever_mangle_rows + 1
        end
        if entry.action == "mangle" and entry.families and entry.families.FOREVER == true then
            forever_mangle_rows = forever_mangle_rows + 1
        end
    end
    eq(forever_mangle_rows, 0,
        "utility: no rotation row names a Mangle for the Forever client")
    -- The ERA reconciliation: the APL's i=1 row casts 13494 ("Haste" on the 1.15
    -- client - a dead row) and the APL has NO Rip row at all, so the table's
    -- Leader of the Pack row carries the CLIENT's own id and the Rip row says
    -- so in its source.
    eq(ids_by_rule.E1 and ids_by_rule.E1.ERA, 9896,
        "utility: the Era Rip row carries the client's Rip r6 (the APL has no Rip row)")
    local era_rip_row = nil
    local era_lop_row = nil
    for i = 1, #rotation do
        local entry = rotation[i]
        if entry.rule == "E1" then
            era_rip_row = entry
        end
        if entry.action == "leader_of_the_pack" then
            era_lop_row = entry
        end
    end
    check(era_rip_row ~= nil, "utility: the Era slice carries its Rip row")
    if era_rip_row then
        check(era_rip_row.source:find("NO Rip row", 1, true) ~= nil,
            "utility: the Era Rip row states that the Era APL has no Rip row")
    end
    check(era_lop_row ~= nil, "utility: the Era slice carries its Leader of the Pack row")
    if era_lop_row then
        check(era_lop_row.source:find("dead as written", 1, true) ~= nil,
            "utility: the Leader of the Pack row states that the APL's row is dead")
        eq(era_lop_row.ids.ERA, 17007,
            "utility: the Leader of the Pack row carries the client's own id, not the APL's 13494")
    end

    -- The slices: the utility rows join the families the APL plays them on.
    local era = ST.DRUID.practice_rotation_for("ERA")
    local era_actions = {}
    for i = 1, #era do
        era_actions[era[i].action] = true
    end
    check(era_actions.cat_form == true, "utility: the Era slice carries the Cat Form row")
    check(era_actions.leader_of_the_pack == true,
        "utility: the Era slice carries the Leader of the Pack row")
    check(era_actions.faerie_fire == true,
        "utility: the Era slice carries the Faerie Fire upkeep row")
    check(era_actions.innervate == true, "utility: the Era slice carries the Innervate row")
    local sod = ST.DRUID.practice_rotation_for("SOD")
    local sod_actions = {}
    for i = 1, #sod do
        sod_actions[sod[i].action] = true
    end
    check(sod_actions.cat_form == true, "utility: the SoD slice carries the Cat Form row")
    check(sod_actions.innervate == true, "utility: the SoD slice carries the Innervate row")
    check(sod_actions.leader_of_the_pack == nil,
        "utility: the SoD slice carries no Leader of the Pack row")
    local tbc = ST.DRUID.practice_rotation_for("TBC")
    local tbc_actions = {}
    for i = 1, #tbc do
        tbc_actions[tbc[i].action] = true
    end
    check(tbc_actions.bloodlust == true, "utility: the TBC slice carries the Bloodlust row")
    check(tbc_actions.cat_form == true, "utility: the TBC slice carries the Cat Form row")
    check(tbc_actions.innervate == nil, "utility: the TBC slice carries no Innervate row")
    local forever = ST.DRUID.practice_rotation_for("FOREVER")
    local forever_actions = {}
    for i = 1, #forever do
        forever_actions[forever[i].action] = true
    end
    check(forever_actions.elunes_light == true,
        "utility: the Forever slice carries the Elune's Light row")
    check(forever_actions.claw == true, "utility: the Forever slice carries the Claw row")
    check(forever_actions.mangle == nil,
        "utility: the Forever slice names no Mangle (the client has no Mangle)")
    check(forever_actions.bloodlust == nil,
        "utility: the Forever slice carries no Bloodlust row")
    -- The WotLK APL carries no utility row at all: its slice stays the sim's ten.
    local wrath = ST.DRUID.practice_rotation_for("WRATH")
    eq(#wrath, 10, "utility: the WotLK slice stays the sim's ten priority slots")
    for i = 1, #wrath do
        check(wrath[i].families == nil, "utility: the WotLK slice carries no utility row")
    end

    -- The pre-pull table (HU-12): the APL's pre-pull rows never join the combat
    -- rotation - they live in their own table.
    local prepulls = ST.DRUID.PRACTICE_PREPULLS
    check(type(prepulls) == "table", "utility: the druid ships a pre-pull table")
    check(type(prepulls.ERA) == "table", "utility: the pre-pull table carries the Era opener")
    check(type(prepulls.SOD) == "table", "utility: the pre-pull table carries the SoD opener")
    check(type(prepulls.TBC) == "table", "utility: the pre-pull table carries the TBC opener")
    check(type(prepulls.WRATH) == "table", "utility: the pre-pull table carries the WotLK opener")
    eq(prepulls.ERA[1].spell, 17392, "utility: the Era opener is the Faerie Fire (Feral)")
    eq(prepulls.ERA[1].at, -1.0, "utility: the Era opener fires 1 s before the pull")
    eq(prepulls.ERA[2].spell, 9846, "utility: the Era opener's second row is the Tiger's Fury")
    eq(prepulls.ERA[2].at, -3.5, "utility: the Tiger's Fury fires 3.5 s before the pull")
    eq(prepulls.SOD[1].spell, 407988, "utility: the SoD opener is the Savage Roar")
    eq(prepulls.SOD[1].at, -8, "utility: the SoD opener fires 8 s before the pull")
    eq(prepulls.TBC[1].spell, 768, "utility: the TBC opener is the Cat Form")
    eq(prepulls.TBC[1].at, -10, "utility: the TBC opener fires 10 s before the pull")
    eq(prepulls.WRATH[1].spell, 50334, "utility: the WotLK opener is the Berserk")
    eq(prepulls.WRATH[1].at, -1, "utility: the WotLK opener fires 1 s before the pull")
    -- The pre-pull rows never join the combat rotation.
    for i = 1, #rotation do
        local entry = rotation[i]
        check(entry.at == nil, "utility: no combat rotation row carries a pre-pull offset")
    end
end

--=========================================================================================
-- 40) The form upkeep's class-side reads: the Feral-tree spec probe and the
--     Cat Form aura (the rotation table's cat_form row's gate)
--=========================================================================================
-- The Cat Form arm (druid_guide.lua's U-CF line) needs three proofs: the class
-- must prove the player is a Feral-tree druid (the family's Feral-tree talent,
-- through api.is_spell_known) and must prove the Cat Form aura is absent (the
-- player's own aura walk). Unknown stays unknown: an unreadable read never
-- prompts.
do
    local function gather_with(opts)
        local sb = build(opts)
        local ST = sb.ST
        ST.interfaces_are_initialised = true
        ST.DRUID.post_init(ST)
        return sb, ST, ST.DRUID.gather_guide_inputs(ST, {})
    end
    -- The Era client's probe is the Faerie Fire (Feral) (17392) - a Feral-tree
    -- talent (wowsims/classic sim/druid/faerie_fire.go:26).
    local _, _, era_feral = gather_with({ project = 2, known = { [17392] = true } })
    eq(era_feral.feral_spec, true,
        "form upkeep: a known Faerie Fire (Feral) proves the Feral tree on Era")
    local _, _, era_caster = gather_with({ project = 2 })
    eq(era_caster.feral_spec, false,
        "form upkeep: an unknown Faerie Fire (Feral) never proves the Feral tree")
    -- The TBC client's probe is the Faerie Fire (Feral) r5 (27011) - the TBC sim
    -- gates the spell on the Feral talent (wowsims/tbc-new sim/druid/
    -- faerie_fire.go:49).
    local _, _, tbc_feral = gather_with({ project = 5, known = { [27011] = true } })
    eq(tbc_feral.feral_spec, true,
        "form upkeep: a known Faerie Fire (Feral) proves the Feral tree on TBC")
    -- The Forever client's probe is the Leader of the Pack (17007) - the Feral
    -- Combat tree talent (wowsims/forever sim/druid/druid.go:115).
    local _, _, forever_feral = gather_with({ project = 18, known = { [17007] = true } })
    eq(forever_feral.feral_spec, true,
        "form upkeep: a known Leader of the Pack proves the Feral tree on Forever")
    -- The WotLK client has no Cat Form row, so it carries no probe at all.
    local _, _, wrath = gather_with({ project = 11, known = { [17007] = true } })
    eq(wrath.feral_spec, nil,
        "form upkeep: the WotLK client has no Cat Form row, so no spec probe")
    -- The Cat Form aura: the player's own aura walk answers up / proven absent /
    -- not answered yet.
    local sb = build({ project = 2, known = { [17392] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    eq(ST.DRUID.gather_guide_inputs(ST, {}).cat_form_active, nil,
        "form upkeep: before the aura walk answers, the Cat Form aura stays unknown")
    sb.class_db.nextaction_enabled = true
    sb.clock = 100
    sb.player_auras = {
        { name = "Cat Form", spell_id = 768, source = "player",
            duration = 3600, expiration = 3700 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    local with_aura = ST.DRUID.gather_guide_inputs(ST, {})
    eq(with_aura.cat_form_active, true,
        "form upkeep: the Cat Form aura reads up when the walk finds it")
    sb.player_auras = {}
    sb.clock = 101
    ST.DRUID.on_bar_update(ST, "mainhand")
    local without_aura = ST.DRUID.gather_guide_inputs(ST, {})
    eq(without_aura.cat_form_active, false,
        "form upkeep: a vanished Cat Form aura reads proven absent")
end

--=========================================================================================
-- 41) The press-nothing hold (the bear chain's RIDE) - the deep-audit's H1
--=========================================================================================
-- The druid was the only class of six that turned the guide's HOLD into a synthetic
-- ACTION: `druid_expected` mapped EVERY hold text to a key, so the bear chain's
-- "RIDE" (a queued Maul - the guide rides the queue the player already placed, so the
-- player presses NO key) became a "ride" action.
--
-- The consequences were wrong grades in both directions: pressing nothing (correct)
-- read as a MISS (F, the streak broke and the band decayed), pressing the rendered
-- "ride" button read as a correct S with points - points for idling, which the
-- engine's contract forbids (a correct hold records no attempt) - and the class's own
-- priority drill banked a false mis-pick for every real pick.
--
-- The fix keeps the nine SPELL-NAMING holds as actions (the guide has no slot for the
-- spell, so the hold overlay names it) and states the ONE press-nothing hold as a
-- hold: { action = nil, hold = true, reason = "RIDE" }.
do
    local sb = build()
    local ST = sb.ST
    local step = ST.DRUID.practice_scenario_step

    -- The RIDE state: the bear form with a queued Maul.
    local ride_ctx = { family = "WRATH", form_index = 1, rage = 0, maul_queued = true }

    -- 1. The class's own step: a hold, never an action.
    local answer = step(ST, ride_ctx)
    check(type(answer) == "table", "ride: the step answers the guide's verdict")
    eq(answer.action, nil, "ride: the step names no action (press nothing)")
    eq(answer.hold, true, "ride: the step states an explicit hold")
    eq(answer.reason, "RIDE", "ride: the hold carries the guide's own caption")

    -- 2. The shared engine's accessor keeps the hold statement (the engine's
    --    contract: a step with no action and a hold is a hold, not an unknown).
    local practice_st = {}
    local chunk = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(chunk, setmetatable({}, { __index = _G }))
    chunk("SwedgeTimer", practice_st)
    practice_st.DRUID = ST.DRUID
    local H = practice_st.practice and practice_st.practice.harness
    check(type(H) == "table", "ride: the shared harness is loaded")
    local engine_answer = H.practice_scenario_step("DRUID", ST, ride_ctx)
    check(type(engine_answer) == "table" and engine_answer.hold == true,
        "ride: the engine's accessor keeps the hold statement")
    eq(engine_answer.action, nil, "ride: the engine's accessor names no action")

    -- 3. The three states through the engine's own decision:
    --      hold + a cast   -> the illegal cast (an attempt, an F)
    --      hold + nothing  -> a correct hold (no attempt, no points)
    --      unknown         -> unknown (no attempt)
    local run = H.new_rotation_run()
    local cast = H.rotation_run_decide(run, engine_answer.action, "maul", engine_answer.hold)
    eq(cast.outcome, "illegal_cast", "ride: a cast during the hold is an illegal cast")
    eq(H.ROTATION_OUTCOME_GRADES[cast.outcome], "F", "ride: the illegal cast grades F")
    eq(run.mispicks, 1, "ride: the illegal cast counts against the run's band")
    local idle_run = H.new_rotation_run()
    local idle = H.rotation_run_decide(idle_run, engine_answer.action, nil, engine_answer.hold)
    eq(idle.outcome, "hold_ok", "ride: doing nothing during the hold is correct")
    eq(H.ROTATION_OUTCOME_GRADES[idle.outcome], nil,
        "ride: a correct hold records no attempt (no points for idling)")
    eq(idle_run.mispicks, 0, "ride: a correct hold is never a mis-pick")
    local unknown_run = H.new_rotation_run()
    local unknown = H.rotation_run_decide(unknown_run, nil, "maul")
    eq(unknown.outcome, "unknown", "ride: an unknown step stays unknown")
    eq(H.ROTATION_OUTCOME_GRADES[unknown.outcome], nil,
        "ride: an unknown decision records no attempt")

    -- 4. The priority drill skips the hold: no attempt, and NO mis-pick banked in
    --    the drill's own window (the ledger stays empty).
    local order = nil
    for i = 1, #ST.DRUID.practice_drills do
        if ST.DRUID.practice_drills[i].key == "druid_finisher_order" then
            order = ST.DRUID.practice_drills[i].grade
        end
    end
    check(type(order) == "function", "ride: the priority drill is registered")
    local ledger = {}
    local drill_ctx = { family = "WRATH", form_index = 1, rage = 0, maul_queued = true,
        last_action = "maul", state = ledger }
    eq(order(ST, drill_ctx), nil, "ride: the priority drill grades nothing on a hold")
    eq(ledger.druid_priority_window, nil,
        "ride: the priority drill banks no mis-pick on a hold")

    -- 5. A spell-naming hold still grades as that spell (the druid's guide names
    --    the spell to press, so the step and the drill stay actions).
    local tf_ctx = { family = "WRATH", form_index = 3, combo_points = 0, energy = 10,
        tf_ready = true, gcd_remaining = 0, clearcast = false }
    eq(step(ST, tf_ctx).action, "tigers_fury",
        "ride: a spell-naming hold still grades as that spell")
    local tf_drill = { family = "WRATH", form_index = 3, combo_points = 0, energy = 10,
        tf_ready = true, gcd_remaining = 0, clearcast = false, last_action = "tigers_fury" }
    eq(order(ST, tf_drill), "S",
        "ride: the priority drill grades the named spell as a hit")

    -- 6. The scenario vocabulary: no "ride" button. The panel's buttons are the
    --    published rotation slice plus the keys the class asks for; no published
    --    slice carries a "ride" key and the class never asks for one.
    for _, family in ipairs({ "ERA", "SOD", "TBC", "WRATH", "FOREVER" }) do
        local slice = ST.DRUID.practice_rotation_for(family)
        for i = 1, #slice do
            check(slice[i].action ~= "ride",
                "ride: the " .. family .. " slice carries no 'ride' key")
        end
    end
    local published = ST.DRUID.practice_rotation_for()
    for i = 1, #published do
        check(published[i].action ~= "ride",
            "ride: the published slice carries no 'ride' key")
    end
    eq(step(ST, ride_ctx).action, nil,
        "ride: the class never asks the panel for a 'ride' key")

    -- 7. The class's hold vocabulary: the press-nothing set is exactly the guide's
    --    one press-nothing hold, and the spell-naming set never names it.
    local nothing = ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING
    local keys = ST.DRUID.PRACTICE_HOLD_KEYS
    check(type(nothing) == "table" and type(keys) == "table",
        "ride: the class publishes its hold vocabulary")
    eq(nothing["RIDE"], true, "ride: RIDE is the press-nothing hold")
    eq(keys["RIDE"], nil, "ride: RIDE is never a spell-naming hold")
    local nothing_count = 0
    for text in pairs(nothing) do
        nothing_count = nothing_count + 1
        check(keys[text] == nil, "ride: " .. text .. " is not in both hold tables")
    end
    eq(nothing_count, 1, "ride: the guide has exactly one press-nothing hold")
end

--=========================================================================================
-- 42) M2 (re-audit 2026-10-20): an UNKNOWN hold text is UNKNOWN, never a guessed key
--=========================================================================================
-- The class used to fall back to the hold text's slug ("SOME FUTURE HOLD" ->
-- "some_future_hold"), so a hold text in neither published table became a
-- synthetic ACTION - the deep audit's H1 shape (the class invents a button the
-- player can only press dishonestly). The closed-vocabulary pin
-- (tests/druid_guide_state.lua) is the tripwire that keeps a new hold text from
-- ever reaching the class; this is the behaviour behind it: the unknown case
-- answers UNKNOWN - no attempt, no wrong action.
do
    local sb = build()
    local ST = sb.ST
    local guide = sb.st.druid_guide
    local real_evaluate = guide.evaluate
    local function unknown_hold(_inputs, out)
        out.hold = true
        out.hold_text = "SOME FUTURE HOLD"
    end

    -- 1. The scenario step: UNKNOWN, so the engine grades "unknown" and the panel
    --    asks for no button at all.
    guide.evaluate = unknown_hold
    local ok, answer = pcall(ST.DRUID.practice_scenario_step, ST, {
        family = "WRATH", form_index = 3, combo_points = 0, energy = 10,
    })
    guide.evaluate = real_evaluate
    check(ok, "M2: an unknown hold text does not raise (" .. tostring(answer) .. ")")
    eq(answer, nil, "M2: an unknown hold text is UNKNOWN (the step answers nil)")

    -- 2. The priority drill: nothing to grade, so no attempt and no mis-pick.
    local order = nil
    for i = 1, #ST.DRUID.practice_drills do
        if ST.DRUID.practice_drills[i].key == "druid_finisher_order" then
            order = ST.DRUID.practice_drills[i].grade
        end
    end
    check(type(order) == "function", "M2: the priority drill is registered")
    if type(order) == "function" then
        local ledger = {}
        guide.evaluate = unknown_hold
        local ok2, grade = pcall(order, ST, {
            family = "WRATH", form_index = 3, combo_points = 0, energy = 10,
            last_action = "shred", state = ledger,
        })
        guide.evaluate = real_evaluate
        check(ok2, "M2: the drill does not raise on an unknown hold (" .. tostring(grade) .. ")")
        eq(grade, nil, "M2: an unknown hold text grades nothing (no attempt)")
        eq(ledger.druid_priority_window, nil,
            "M2: an unknown hold text banks no mis-pick in the priority drill")
    end

    -- 3. The production source never slugs a hold text into a key.
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end
    local src = read("classes/druid.lua")
    check(src:find('hold_text:lower()', 1, true) == nil,
        "M2: the class never slugs an unknown hold text into an action key")
end

--=========================================================================================
-- The NEUTRAL action set and the practice-panel ability list
--
-- The class publishes ST.DRUID.practice_neutral_actions (the contract fixed by the
-- orchestrator, practice.lua's class contract block): the keys the practice panel
-- offers but the rotation never grades. A key that is neither a rotation action nor
-- neutral stays a mis-pick, so the set is a deliberate, CLOSED list.
--
-- The publish is FAMILY-SCOPED (a family key -> a set of action keys, resolved for the
-- running client family - st.family). The Rake is the one key a BUILD can change: the
-- SoD build runs on the Era client (the engine's publish reads st.family only) and
-- the SoD rotation DOES ask for the Rake (its upkeep S7) - so the class's own build
-- decision drops the key there. A rotation action can never be neutral.
--=========================================================================================
do
    local published = base.ST.DRUID.practice_neutral_actions
    eq(type(published), "table", "neutral: the druid publishes a neutral action set")

    local COMMON = { "cheetah", "food", "healthstone", "healing_potion", "healing_touch",
        "regrowth", "rejuvenation" }
    local BUCKETS = {
        ERA = { "cheetah", "food", "healthstone", "healing_potion", "healing_touch",
            "rake", "regrowth", "rejuvenation" },
        TBC = { "cheetah", "food", "healthstone", "healing_potion", "healing_touch",
            "rake", "regrowth", "rejuvenation" },
        WRATH = { "cheetah", "food", "healthstone", "healing_potion", "healing_touch",
            "regrowth", "rejuvenation" },
        FOREVER = { "cheetah", "food", "healthstone", "healing_potion", "healing_touch",
            "regrowth", "rejuvenation" },
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
    -- is the PICKED one (the SoD build's rotation asks for the Rake), so the SoD
    -- slice is checked on a SoD sandbox.
    local era = build({ project = 2 })
    era.ST.DRUID.post_init(era.ST)
    -- The class's own build decision (the SoD rune basis): reading the rotation
    -- family latches the probe, and the latch corrects the publish.
    eq(era.ST.DRUID.practice_rotation_family(), "ERA",
        "neutral: the Era-base build is the Era rotation family")
    local sod = build({ project = 2, known_names = { ["Mangle"] = "Mangle" } })
    -- The class's own build decision (the SoD rune basis): reading the rotation
    -- family latches the probe, and the latch corrects the publish.
    eq(sod.ST.DRUID.practice_rotation_family(), "SOD",
        "neutral: the SoD build is the SoD rotation family")
    eq(sod.ST.DRUID.practice_neutral_actions.ERA.rake, nil,
        "neutral: the SoD build drops the Rake (a rotation action there)")
    for _, family in ipairs({ "ERA", "SOD", "TBC", "WRATH", "FOREVER" }) do
        local is_sod = (family == "SOD")
        local module = is_sod and sod.ST.DRUID or base.ST.DRUID
        local bucket = is_sod and sod.ST.DRUID.practice_neutral_actions.ERA
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

    -- THE BUILD PICK: the Era-base build keeps the Rake (its cat rotation asks
    -- for neither the Rake nor the Bite), the SoD build drops it (the SoD
    -- rotation asks for the Rake, under the key `rake`).
    eq(era.ST.DRUID.practice_neutral_actions.ERA.rake, true,
        "neutral: the Era-base build publishes the Rake")

    -- THE PRACTICE-PANEL ABILITY LIST: the common abilities the panel offers but
    -- the rotation never grades. Every entry names the client's spell, carries a
    -- label and cites at least one spell id - an ability whose id nobody can
    -- source is not published at all.
    local common = base.ST.DRUID.practice_common_actions
    eq(type(common), "table", "panel: the druid publishes a practice-panel ability list")
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
        -- Never a rotation action on any family the druid plays.
        for _, family in ipairs({ "ERA", "SOD", "TBC", "WRATH", "FOREVER" }) do
            local entries = base.ST.DRUID.practice_rotation_for(family)
            local rotation = false
            for k = 1, #entries do
                if entries[k].action == action.key then rotation = true end
            end
            check(not rotation, "panel: the common ability " .. tostring(action.key)
                .. " is not a rotation action on " .. family)
        end
    end
    -- The seven common abilities are exactly the ones the publish names.
    eq(#common, 7, "panel: the druid publishes seven common abilities")
    local common_keys = {}
    for i = 1, #common do common_keys[common[i].key] = true end
    for _, key in ipairs(COMMON) do
        eq(common_keys[key], true, "panel: the common ability " .. key .. " is published")
    end

    -- THE WIDENING SEAM: the class publishes the widened slot list and applies it
    -- to the guide slot list (the shaman's apply_family_slots precedent), so the
    -- practice panel offers the common abilities.
    eq(type(base.ST.DRUID.practice_panel_slots), "function",
        "panel: the class publishes the panel slot list")
    eq(type(base.ST.DRUID.apply_practice_panel_actions), "function",
        "panel: the class publishes the widening seam")
    local seam = build({ project = 11,
        known = { [5185] = true, [774] = true, [8936] = true, [5118] = true,
            [5720] = true, [439] = true, [433] = true } })
    local seamST = seam.ST
    local before = #seamST.DRUID.guide.slots
    local widened = seamST.DRUID.practice_panel_slots()
    eq(type(widened), "table", "panel: the panel slot list is a table")
    eq(#widened, before + 7, "panel: the panel slot list carries the common abilities")
    seamST.DRUID.apply_practice_panel_actions()
    eq(#seamST.DRUID.guide.slots, before + 7,
        "panel: the widening seam appends the common abilities to the slot list")
    seamST.DRUID.apply_practice_panel_actions()
    eq(#seamST.DRUID.guide.slots, before + 7,
        "panel: the widening seam is idempotent")
    -- The widened slots carry their own icons (the client's own rank) and the
    -- common marker the seam looks for.
    local common_slot = nil
    for i = 1, #seamST.DRUID.guide.slots do
        local slot = seamST.DRUID.guide.slots[i]
        if type(slot) == "table" and slot.key == "healing_touch" then common_slot = slot end
    end
    check(common_slot ~= nil, "panel: the Healing Touch joins the slot list")
    eq(common_slot and common_slot.spell_id, 5185,
        "panel: the Healing Touch carries the client's own spell id")
    eq(common_slot and common_slot.practice_common, true,
        "panel: the common slot carries the common marker")
    -- UNKNOWN-HIDES: a client that does not have the spell never gets the button.
    local blind = build({ project = 11 })
    eq(#blind.ST.DRUID.practice_panel_slots(), #blind.ST.DRUID.guide.slots,
        "panel: a client without the spells is offered no common ability")
    -- The WIRING: post_init widens the panel's slot list (the seam runs inside the
    -- practice block, after the guide frame has built its icons).
    local wired = build({ project = 11,
        known = { [5185] = true, [774] = true, [8936] = true, [5118] = true,
            [5720] = true, [439] = true, [433] = true } })
    wired.st.practice_ui = { init = function() end }
    local before_wired = #wired.ST.DRUID.guide.slots
    wired.ST.DRUID.post_init(wired.ST)
    eq(#wired.ST.DRUID.guide.slots, before_wired + 7,
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
    local p = prose(ROOT .. "classes/druid.lua")
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
-- R1 name-carrying payloads: the Maul queue tint clears by id or by name on
-- every family (id primary, name secondary). Era rides numeric ids, TBC
-- Anniversary can ride the name in the guid slot with a nil id (compat.lua);
-- either shape clears on either client. A foreign name changes nothing.
--=========================================================================================
do
    -- Era: the numeric-id success clears, and the literal English name clears too.
    local sb = build({ project = 2, known = { [9881] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_succeeded(ST, "target", "cast-1", 9881)
    eq(ST.maul_queued, false, "Era: a numeric-id Maul success clears the tint")
    eq(sb.bar_color_calls, 1, "Era: the id clear recolours once")

    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_succeeded(ST, "target", "Maul", nil)
    eq(ST.maul_queued, false, "Era: the English name clears the tint too")
    eq(sb.bar_color_calls, 1, "Era: the name clear recolours once")

    -- The client's own localized name clears through the resolved spell data.
    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_succeeded(ST, "target", "Spell 9881", nil)
    eq(ST.maul_queued, false, "Era: the localized name clears the tint too")
    eq(sb.bar_color_calls, 1, "Era: the localized clear recolours once")

    -- A foreign name must change nothing.
    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_succeeded(ST, "target", "Scare Beast", nil)
    eq(ST.maul_queued, true, "Era: an unrelated name leaves the tint alone")
    eq(sb.bar_color_calls, 0, "Era: an unrelated name triggers no recolour")
end

do
    -- TBC Anniversary: the name rides the guid slot with a nil id; a numeric
    -- id still clears through the rank table.
    local sb = build({ project = 5, name_only_client = true, known = { [26996] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_succeeded(ST, "target", "Maul", nil)
    eq(ST.maul_queued, false, "TBC: a name-carrying Maul success clears the tint")
    eq(sb.bar_color_calls, 1, "TBC: the name clear recolours once")

    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_succeeded(ST, "target", "cast-2", 26996)
    eq(ST.maul_queued, false, "TBC: a numeric id still clears the tint")
    eq(sb.bar_color_calls, 1, "TBC: the id clear recolours once")

    -- The quiet-failure and interrupt paths ride the same matcher.
    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_failed_quiet(ST, "target", "Maul", nil)
    eq(ST.maul_queued, false, "TBC: a name-carrying quiet failure clears the tint")
    eq(sb.bar_color_calls, 1, "TBC: the quiet name clear recolours once")

    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_event(ST, "UNIT_SPELLCAST_FAILED", "player", "Maul", nil)
    eq(ST.maul_queued, false, "TBC: a name-carrying interrupt clears the tint")
    eq(sb.bar_color_calls, 1, "TBC: the interrupt name clear recolours once")

    -- A foreign name must change nothing.
    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_succeeded(ST, "target", "Scare Beast", nil)
    eq(ST.maul_queued, true, "TBC: an unrelated name leaves the tint alone")
    eq(sb.bar_color_calls, 0, "TBC: an unrelated name triggers no recolour")
end

do
    -- Era quiet-failure and interrupt paths ride the same matcher.
    local sb = build({ project = 2, known = { [9881] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_failed_quiet(ST, "target", "cast-3", 9881)
    eq(ST.maul_queued, false, "Era: a numeric-id quiet failure clears the tint")
    eq(sb.bar_color_calls, 1, "Era: the quiet id clear recolours once")

    ST.maul_queued = true
    sb.bar_color_calls = 0
    ST.DRUID.on_spellcast_event(ST, "UNIT_SPELLCAST_INTERRUPTED", "player", "cast-4", 9881)
    eq(ST.maul_queued, false, "Era: a numeric-id interrupt clears the tint")
    eq(sb.bar_color_calls, 1, "Era: the interrupt id clear recolours once")
end

--=========================================================================================
-- Faerie Fire guide read: rank id, literal English names, or the client's own
-- localized names land it on every family. A name-carrying/id-less Anniversary
-- row still reports the debuff instead of staying unknown forever.
--=========================================================================================
do
    -- Era: the rank id lands the read.
    local sb = build({ project = 2, known = { [17392] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    sb.clock = 300
    sb.target_auras = {
        { name = "Faerie Fire", spell_id = 17392, source = "player", duration = 40, expiration = 330 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    local out = ST.DRUID.gather_guide_inputs(ST, {})
    eq(out.ff_debuff_remaining, 30, "Era: the FF id lands the guide read")

    -- The literal English name lands it without any id.
    sb.clock = 301
    sb.target_auras = {
        { name = "Faerie Fire", spell_id = nil, source = "player", duration = 40, expiration = 331 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    out = ST.DRUID.gather_guide_inputs(ST, {})
    eq(out.ff_debuff_remaining, 30, "Era: the FF name lands the guide read without an id")
end

do
    -- TBC Anniversary: a name-carrying/id-less row lands the read.
    local sb = build({ project = 5, name_only_client = true, known = { [27011] = true } })
    local ST = sb.ST
    ST.interfaces_are_initialised = true
    ST.DRUID.post_init(ST)
    sb.clock = 400
    sb.target_auras = {
        { name = "Faerie Fire", spell_id = nil, source = "player", duration = 40, expiration = 430 },
    }
    ST.DRUID.on_bar_update(ST, "mainhand")
    local out = ST.DRUID.gather_guide_inputs(ST, {})
    eq(out.ff_debuff_remaining, 30, "TBC: an id-less FF row lands the guide read")

    -- No aura on the target: the walk answered, so the read is absent (false).
    sb.clock = 401
    sb.target_auras = {}
    ST.DRUID.on_bar_update(ST, "mainhand")
    out = ST.DRUID.gather_guide_inputs(ST, {})
    eq(out.ff_debuff_remaining, false, "TBC: no FF aura reads absent, not unknown")
end

if failures == 0 then
    print("PASS  druid_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  druid_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end