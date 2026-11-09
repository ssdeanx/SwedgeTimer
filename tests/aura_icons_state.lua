-- tests/aura_icons_state.lua: offline verification of aura_icons.lua, the WoW
-- Forever-only per-class buff/debuff aura icon row above the top swing bars, plus its
-- options/defaults/TOC wiring.
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
-- lua5.1 tests/aura_icons_state.lua  (any cwd works; ROOT follows arg[0]).
--
-- WHAT IS PINNED HERE (each check is a statement about the real module code, loaded in
-- an instrumented frame sandbox - nothing is re-implemented in the test):
--   1. load-time gate: the module answers false on ERA/TBC/WRATH/CATA/MISTS/RETAIL and
--      on any Forever client missing the aura-container surface, with ZERO frames,
--      events, AuraContainer attempts and aura reads;
--   2. Forever happy path: exactly one driver, two native AuraContainer frames, one
--      AddAuraGroup each with the exact filter/unit/group key/layout/sort/maxDuration;
--      a second init is a no-op;
--   3. per-class includeSpellIDs: the exact id SET (independent tables below), the
--      shared/racial merge at container creation only, no cross-class leak, no
--      27019, no stance id, class arrays unmodified (purity);
--   4. own-caster debuff filter is "HARMFUL|PLAYER";
--   5. native-only: no aura-data read ever (unit-aura globals are booby-trapped);
--      the secrecy predicate only feeds diagnostics and can never change behaviour;
--   6. placement: topmost VISIBLE bar from plain geometry only, hide fallback, lazy
--      hands, re-anchor on move, size/spacing/grow pushes, no container geometry read,
--      secret geometry skipped without a throw;
--   7. throttled maintenance (0.15 s), forced pass on PLAYER_ENTERING_WORLD;
--   8. combat deferral (no AuraContainer in lockdown, retried and succeeds) and a
--      failed container/group creation retried without a latch;
--   9. options: nil follows the shipped default, == false hides, frames survive, the
--      reserved debuff band collapses; option_tables widgets are hidden on every
--      non-Forever family and wired to apply_settings;
--  10. config_presets defaults match the module's runtime defaults (one source);
--  11. single-TOC registration of the module + the suite registry line;
--  12. /tmp mutation proofs are run by the implementation lane, not this suite.
--
-- The module is Forever-only by contract: every non-Forever section below proves the
-- module is COMPLETELY inert there (no frame, no event, no aura read, no option side
-- effect), which is the hard requirement of the operator brief.

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

-- Stand-ins for opaque secret values: the module must route them through
-- st.api.is_secret and never compare/arithmetic them. SECRET is an opaque table;
-- SECRET_NUMBER simulates a SECRET NUMBER (the real client's secret values keep their
-- Lua type, so `type(value) == "number"` alone can never be the guard - only the
-- documented probe may reject them).
local SECRET = {}
local SECRET_NUMBER = 1e308
local H = nil -- the current harness; fake frames read it at call time

local function read_source(rel)
    local file = assert(io.open(ROOT .. rel, "r"), "cannot open " .. rel)
    local text = file:read("*a")
    file:close()
    return text
end

--=========================================================================================
-- Fake client surface
--=========================================================================================
local function new_button()
    local b = { textures = {}, fontstrings = {}, calls = {} }
    local function count(key) b.calls[key] = (b.calls[key] or 0) + 1 end
    function b:SetSize(width, height)
        count("SetSize")
        self.width, self.height = width, height
    end
    function b:CreateTexture()
        local t = { points = {} }
        -- Dot functions with an explicit region parameter: a colon method here would
        -- shadow the button's own `self` upvalue (luacheck 421) for no benefit.
        function t.SetAllPoints(region) region.all_points = true end
        function t.SetTexCoord(region, ...) region.texcoord = { ... } end
        function t.SetColorTexture(region, ...) region.color = { ... } end
        function t.SetPoint(region, ...) region.points[#region.points + 1] = { ... } end
        function t.SetWidth(region, value) region.width = value end
        function t.SetHeight(region, value) region.height = value end
        self.textures[#self.textures + 1] = t
        return t
    end
    function b:CreateFontString()
        local f = { points = {} }
        function f.SetPoint(region, ...) region.points[#region.points + 1] = { ... } end
        function f.SetJustifyH(region, value) region.justify = value end
        self.fontstrings[#self.fontstrings + 1] = f
        return f
    end
    function b:SetIcon(texture)
        count("SetIcon")
        if H and H.button_icon_raises then error("injected SetIcon failure") end
        if H and H.button_icon_raises_once then
            H.button_icon_raises_once = false
            error("injected SetIcon failure")
        end
        self.icon = texture
    end
    function b:SetDurationText(fontstring, options)
        count("SetDurationText")
        self.duration_text = fontstring
        self.duration_options = options
    end
    function b:SetApplicationCount(fontstring, options)
        count("SetApplicationCount")
        self.application_count = fontstring
        self.application_options = options
    end
    function b:SetDurationBar(statusbar, options)
        count("SetDurationBar")
        self.duration_bar = statusbar
        self.duration_bar_options = options
    end
    return b
end

local function new_frame(kind, name, parent, template)
    local frame = {
        kind = kind, name = name, parent = parent, template = template,
        shown = false, points = {}, calls = {}, groups = {}, group_keys = {},
        events = {}, scripts = {}, layout_calls = {}, children = {},
        width = nil, height = nil, strata = nil, unit = nil, enabled = nil,
    }
    local function count(key) frame.calls[key] = (frame.calls[key] or 0) + 1 end

    function frame:SetSize(width, height) count("SetSize"); self.width, self.height = width, height end
    function frame:SetFrameStrata(value) count("SetFrameStrata"); self.strata = value end
    function frame:SetUnit(value) count("SetUnit"); self.unit = value end
    function frame:AddAuraGroup(key, filter, options)
        count("AddAuraGroup")
        if H.fail_add_group then error("injected AddAuraGroup failure") end
        if self.groups[key] ~= nil then error("aura group already exists") end
        self.groups[key] = { filter = filter, options = options }
        self.group_keys[#self.group_keys + 1] = key
        -- The client allocates a batch of frames up-front and runs initializeFrame on
        -- each (FrameCreationBatchSize = 10 upstream); two is enough to prove the
        -- style callback reaches the button object table.
        self.children[key] = {}
        for index = 1, 2 do
            local button = new_button()
            if type(options.initializeFrame) == "function" then
                options.initializeFrame(button)
            end
            self.children[key][index] = button
        end
    end
    function frame:HasAuraGroup(key)
        count("HasAuraGroup")
        return self.groups[key] ~= nil
    end
    function frame:SetFlowLayoutAnchorPoint(value)
        count("SetFlowLayoutAnchorPoint")
        self.flow_anchor = value
    end
    function frame:SetFlowLayoutGrowthDirection(horizontal, vertical)
        count("SetFlowLayoutGrowthDirection")
        self.grow_direction = { horizontal, vertical }
    end
    function frame:SetAuraGroupLayout(key, options)
        count("SetAuraGroupLayout")
        self.layout_calls[#self.layout_calls + 1] = { key = key, options = options }
    end
    function frame:SetEnabled(value) count("SetEnabled"); self.enabled = value end
    function frame:Show() count("Show"); self.shown = true end
    function frame:Hide() count("Hide"); self.shown = false end
    function frame:ClearAllPoints() count("ClearAllPoints"); self.points = {} end
    function frame:SetPoint(...)
        count("SetPoint")
        if H.fail_setpoint then error("injected SetPoint failure") end
        local point, relative, relative_point, x, y = ...
        self.points = { { point = point, relative = relative, relative_point = relative_point, x = x, y = y } }
    end
    function frame:SetScript(script, fn) count("SetScript"); self.scripts[script] = fn end
    function frame:SetWidth(value) count("SetWidth"); self.width = value end
    function frame:SetHeight(value) count("SetHeight"); self.height = value end
    function frame:SetStatusBarTexture(value) count("SetStatusBarTexture"); self.statusbar_texture = value end
    function frame:SetStatusBarColor(...) count("SetStatusBarColor"); self.statusbar_color = { ... } end
    function frame:SetMinMaxValues(minimum, maximum)
        count("SetMinMaxValues")
        self.minimum, self.maximum = minimum, maximum
    end
    function frame:SetValue(value) count("SetValue"); self.value = value end
    function frame:RegisterEvent(event)
        count("RegisterEvent")
        self.events[#self.events + 1] = event
        H.events[#H.events + 1] = event
    end
    -- Aura frame enumeration: the sanctioned (and possibly secret) count/accessor.
    function frame:GetAuraGroupFrameCount(key)
        H.enumeration_reads = H.enumeration_reads + 1
        if H.enumeration_raises then error("injected enumeration failure") end
        if H.enumeration_secret then return SECRET_NUMBER end
        local frames = self.children[key]
        return frames and #frames or 0
    end
    function frame:GetAuraGroupFrame(key, index)
        H.enumeration_reads = H.enumeration_reads + 1
        if H.enumeration_raises then error("injected enumeration failure") end
        local frames = self.children[key]
        return frames and frames[index] or nil
    end
    -- Forbidden measurements: the client can write container geometry through
    -- secretwrap, so the module must NEVER read these. Counted, and they can be made
    -- to return a secret or raise to prove the module would not survive using them.
    local function geometry_read()
        H.container_geometry_reads = H.container_geometry_reads + 1
        if H.geometry_raises then error("injected container geometry read") end
        if H.geometry_secret then return SECRET_NUMBER end
        return nil
    end
    function frame:GetHeight() return geometry_read() or self.height end
    function frame:GetWidth() return geometry_read() or self.width end
    function frame:GetTop() return geometry_read() end
    function frame:GetBottom() return geometry_read() end
    function frame:GetLeft() return geometry_read() end
    function frame:GetPoint() geometry_read(); return nil end
    function frame:GetSize() return geometry_read() end
    function frame:IsShown()
        H.container_geometry_reads = H.container_geometry_reads + 1
        return self.shown
    end
    return frame
end

local function add_bar(harness, hand, top, visible)
    local bar = { hand = hand, top = top, visible = visible ~= false }
    function bar:IsShown()
        harness.bar_show_reads = harness.bar_show_reads + 1
        if self.shown_secret then return SECRET end
        if self.shown_raises then error("injected IsShown failure") end
        return self.visible
    end
    function bar:GetTop()
        harness.bar_top_reads = harness.bar_top_reads + 1
        if self.top_secret then return SECRET end
        if self.top_raises then error("injected GetTop failure") end
        return self.top
    end
    function bar:GetEffectiveScale() return 1 end
    harness.bars[hand] = bar
    return bar
end

local function new_harness(opts)
    opts = opts or {}
    local h = {
        created = {}, events = {}, prints = {}, bars = {},
        clock = 100,
        combat = false,
        fail_container_create = false,
        fail_add_group = false,
        fail_setpoint = false,
        create_raises = false,
        enumeration_raises = false,
        enumeration_secret = false,
        enumeration_reads = 0,
        container_geometry_reads = 0,
        bar_top_reads = 0,
        bar_show_reads = 0,
        aura_reads = 0,
        secret_predicate_calls = 0,
        aura_secret = false,
        secret_raises = false,
        container_attempts = 0,
        create_calls = 0,
        bar_calls = 0,
        race_file = opts.race_file,
        race_localized = opts.race_localized,
        unit_race_calls = 0,
        unit_race_raises = false,
        button_icon_raises = false,
    }
    H = h

    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.UIParent = new_frame("UIParent", "UIParent", nil)
    env.CreateFrame = function(kind, name, parent, template)
        h.create_calls = h.create_calls + 1
        if h.create_raises then error("injected CreateFrame failure") end
        if kind == "AuraContainer" then
            h.container_attempts = h.container_attempts + 1
            if h.fail_container_create then return nil end
        end
        local frame = new_frame(kind, name, parent, template)
        -- Only TOP-LEVEL frames count as "the row's frames": the debuff duration bar is
        -- created on the aura button's object table by the style callback.
        if parent == env.UIParent then
            h.created[#h.created + 1] = frame
        end
        return frame
    end
    env.InCombatLockdown = function() return h.combat == true end
    env.UnitRace = function(unit)
        h.unit_race_calls = h.unit_race_calls + 1
        if h.unit_race_raises then error("injected UnitRace failure") end
        if unit ~= "player" then return nil end
        return h.race_localized, h.race_file
    end
    env.GetTime = function() return h.clock end
    if opts.no_util ~= true then env.C_AuraContainerUtil = {} end
    if opts.no_sort_method ~= true then env.AuraContainerSortMethod = { Default = 0, Expiration = 4 } end
    if opts.no_sort_direction ~= true then env.AuraContainerSortDirection = { Normal = 0, Reverse = 1 } end
    env.AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 } }
    env.C_Secrets = {
        ShouldAurasBeSecret = function()
            h.secret_predicate_calls = h.secret_predicate_calls + 1
            if h.secret_raises then error("injected secrecy predicate failure") end
            return h.aura_secret == true
        end,
    }
    env.C_UnitAuras = {
        GetAuraDataByIndex = function() h.aura_reads = h.aura_reads + 1; error("C_UnitAuras must never be read") end,
        GetAuraDataBySlot = function() h.aura_reads = h.aura_reads + 1; error("C_UnitAuras must never be read") end,
        GetAuraDataByAuraInstanceID = function() h.aura_reads = h.aura_reads + 1; error("C_UnitAuras must never be read") end,
        GetPlayerAuraBySpellID = function() h.aura_reads = h.aura_reads + 1; error("C_UnitAuras must never be read") end,
        GetAuraDataBySpellName = function() h.aura_reads = h.aura_reads + 1; error("C_UnitAuras must never be read") end,
    }
    env.UnitAura = function() h.aura_reads = h.aura_reads + 1; error("UnitAura must never be called") end
    h.env = env

    h.st = {
        family = opts.family or "FOREVER",
        api = {
            get_time = function() return h.clock end,
            is_secret = function(value) return value == SECRET or value == SECRET_NUMBER end,
        },
        utils = { print_msg = function(message) h.prints[#h.prints + 1] = tostring(message) end },
    }

    local class = opts.class or "WARRIOR"
    h.class_db = { class_enabled = true }
    h.ST = {
        player_class = class,
        hands = opts.hands or { "mainhand", "offhand", "ranged" },
        db = { profile = { frame_strata = "MEDIUM" } },
    }
    h.ST.db.profile[class] = h.class_db
    function h.ST:iter_hands()
        local hands = self.hands
        local index = 0
        return function()
            index = index + 1
            return hands[index]
        end
    end
    function h.ST:get_bar_frame(hand) return h.bars[hand] end
    function h.ST:get_class_hands() return self.hands end
    function h.ST:get_class_table() return self.db.profile[self.player_class] end
    function h.ST:get_profile_table() return self.db.profile end
    function h.ST:show_bar() h.bar_calls = h.bar_calls + 1 end
    function h.ST:hide_bar() h.bar_calls = h.bar_calls + 1 end
    function h.ST:Print(message) h.prints[#h.prints + 1] = tostring(message) end

    if opts.no_bars ~= true then
        add_bar(h, "mainhand", 400, true)
        add_bar(h, "offhand", 380, true)
        add_bar(h, "ranged", 500, true)
    end

    local chunk = assert(loadfile(ROOT .. "aura_icons.lua"))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "SwedgeTimer", h.st)
    h.load_ok = ok
    h.load_error = err
    h.A = h.st.aura_icons
    return h
end

local function created_of_kind(h, kind)
    local list = {}
    for index = 1, #h.created do
        if h.created[index].kind == kind then list[#list + 1] = h.created[index] end
    end
    return list
end

local function find_frame(h, name)
    for index = 1, #h.created do
        if h.created[index].name == name then return h.created[index] end
    end
    return nil
end

local function boot(opts)
    local h = new_harness(opts)
    local ok, result = pcall(h.A.init, h.ST)
    h.init_ok = ok
    h.init_error = result
    h.inited = (ok and result == true)
    return h
end

local function pass(h, elapsed)
    h.A.on_update(elapsed or 0.15)
end

local function count_calls(h, kind)
    local total = 0
    for index = 1, #h.created do
        total = total + (h.created[index].calls[kind] or 0)
    end
    return total
end

local function set_of(list)
    local set = {}
    for index = 1, #(list or {}) do
        local id = list[index]
        set[id] = (set[id] or 0) + 1
    end
    return set
end

local function same_set(got, want, label)
    local got_set, want_set = set_of(got), set_of(want)
    local missing, extra = {}, {}
    for id in pairs(want_set) do
        if got_set[id] == nil then missing[#missing + 1] = tostring(id) end
    end
    for id in pairs(got_set) do
        if want_set[id] == nil then extra[#extra + 1] = tostring(id) end
    end
    table.sort(missing)
    table.sort(extra)
    check(#missing == 0 and #extra == 0,
        label .. "  (missing: " .. table.concat(missing, ",") ..
        "; extra: " .. table.concat(extra, ",") .. ")")
end

local function deep_copy(list)
    local out = {}
    for index = 1, #(list or {}) do out[index] = list[index] end
    return out
end

--=========================================================================================
-- Independent id tables (from bench/aura_row_reference_2026-11-08.md §4, post-merge)
--=========================================================================================
-- Written out separately from the module so the module cannot drift: a missing/extra id
-- in either file fails these checks. Order is the reference's; the module preserves its
-- class prefix and appends the shared/racial ids at build time.
local EXPECTED_BUFFS = {
    WARRIOR = {
        7384, 7887, 11584, 11585, 2565, 12319, 12320, 12292, 1719, 12328, 20230, 871,
        12975, 23920, 18499, 30033, 2687, 12317, 23881, 23892, 23893, 23894, 1329555,
        402927, 1310222, 1240193,
    },
    PALADIN = {
        31884, 642, 1020, 10278, 1022, 5599, 20925, 20927, 20928, 1239570, 498, 5573,
        20049, 20050, 1310735, 679, 1311606,
    },
    SHAMAN = {
        30823, 16280, 16256, 29180, 425336, 408505, 408498, 1223031, 408341,
    },
    DRUID = {
        16870, 5217, 22842, 22812, 1850, 9821, 5229, 29166, 407995, 16958, 1223246,
        417051,
    },
    ROGUE = {
        5171, 6774, 13750, 13877, 14177, 5277, 2983, 8696, 11305, 1856, 1857, 14179,
        14183, 36554, 31209, 14278, 1329328, 1310703, 1329283, 399956, 1329256, 1328825,
    },
    HUNTER = {
        19574, 3045, 34692, 6150, 34949, 34477, 19552, 1317257, 19306, 1495, 2973,
    },
}

local EXPECTED_DEBUFFS = {
    WARRIOR = {
        772, 6546, 6547, 6548, 11572, 11573, 11574, 12721, 12834, 7386, 7405, 8380,
        11596, 11597, 25225, 6343, 8198, 8204, 8205, 11580, 11581, 1160, 6190, 11554,
        11555, 11556, 402927, 1310222, 1240193,
    },
    PALADIN = {
        20188, 20300, 20301, 20302, 20303, 20185, 20344, 20345, 20346, 20186, 20354,
        20355, 20183, 20411, 20412, 20413, 20414, 679, 1311606,
    },
    SHAMAN = {
        8050, 8052, 8053, 10447, 10448, 29228, 17364, 8056, 8058, 10472, 10473, 8042,
        8044, 8045, 8046, 10412, 10413, 10414, 408341,
    },
    DRUID = {
        1079, 9492, 9493, 9752, 9894, 9896, 27008, 1822, 1823, 1824, 9904, 27006,
        1328617, 1328616, 414644, 1235826, 1235827, 770, 778, 9749, 9907, 99, 1735,
        9490, 9747, 9898, 407995, 16958, 1223246, 417051,
    },
    ROGUE = {
        1943, 8637, 8639, 8640, 11273, 11274, 11275, 26867, 8647, 8649, 8650, 11197,
        11198, 26996, 16511, 1329283, 399956, 1329256, 1328825,
    },
    HUNTER = {
        1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, 2974, 14267,
        14268, 5116, 13585, 13586, 13587, 13588, 13589, 13590, 27068, 13795, 14302,
        13813, 14303, 14304, 14305, 1499, 14310, 14311, 3355, 14308, 14309, 13809,
        13810, 1130, 14323, 14324, 14325, 1310533, 1265831, 1317257, 19306, 1495, 2973,
    },
}

local EXPECTED_SHARED = { 2825, 32182, 35476, 35477, 28507 }

-- The 18 FOREVER_NEW_ABILITY_CANDIDATES the reference merges into BOTH lists.
local CANDIDATES_BY_CLASS = {
    WARRIOR = { [402927] = true, [1310222] = true, [1240193] = true },
    PALADIN = { [679] = true, [1311606] = true },
    SHAMAN = { [408341] = true },
    DRUID = { [407995] = true, [16958] = true, [1223246] = true, [417051] = true },
    ROGUE = { [1329283] = true, [399956] = true, [1329256] = true, [1328825] = true },
    HUNTER = { [1317257] = true, [19306] = true, [1495] = true, [2973] = true },
}

local CLASSES = { "WARRIOR", "PALADIN", "SHAMAN", "DRUID", "ROGUE", "HUNTER" }

local EXPECTED_COUNTS = {
    buffs = { WARRIOR = 26, PALADIN = 17, SHAMAN = 9, DRUID = 12, ROGUE = 22, HUNTER = 11 },
    debuffs = { WARRIOR = 29, PALADIN = 19, SHAMAN = 19, DRUID = 30, ROGUE = 19, HUNTER = 44 },
}

-- A representative stance id per class (the reference's single-slot tier; the row must
-- never show a stance). Not exhaustive - one id per stance family is enough to prove
-- the tiers stayed separate.
local STANCE_IDS = {
    2457, 71, 2458, -- warrior stances
    1787, 1786, 1785, 1784, -- rogue stealth
    9634, 5487, 768, 24858, 783, 1066, -- druid forms
    10432, 10431, 8134, 945, 905, 325, 324, 52127, -- shaman shields
    20920, 20375, 1311649, 20308, 20293, 20357, 20349, 20165, -- paladin seals
    27044, 25296, 13165, 34074, 13163, 5118, 13161, 20190, 20043, -- hunter aspects
}

-- An id unique to each class (never shared/racial/candidate) - proves no cross leak.
local SIGNATURE_BUFFS = { WARRIOR = 7384, PALADIN = 31884, SHAMAN = 30823, DRUID = 16870, ROGUE = 5171, HUNTER = 19574 }
local SIGNATURE_DEBUFFS = { WARRIOR = 772, PALADIN = 20188, SHAMAN = 8050, DRUID = 1079, ROGUE = 1943, HUNTER = 1978 }

--=========================================================================================
-- 1. Load-time gate: non-Forever families are COMPLETELY inert
--=========================================================================================
local NON_FOREVER = { "ERA", "TBC", "WRATH", "CATA", "MISTS", "RETAIL" }
for _, family in ipairs(NON_FOREVER) do
    local h = new_harness({ family = family })
    eq(h.load_ok, true, family .. ": the module loads in plain Lua")
    check(type(h.A) == "table", family .. ": the module namespace exists")
    eq(h.A.available, false, family .. ": available is false")
    local available, reason = h.A.gate()
    eq(available, false, family .. ": gate() answers false")
    eq(reason, "family", family .. ": gate() names the family as the reason")
    eq(h.A.options_visible(), false, family .. ": the option controls are hidden")
    local inited = h.A.init(h.ST)
    eq(inited, false, family .. ": init is a no-op")
    eq(#h.created, 0, family .. ": ZERO frames created")
    eq(#h.events, 0, family .. ": ZERO events registered")
    eq(h.container_attempts, 0, family .. ": ZERO AuraContainer creation attempts")
    eq(h.aura_reads, 0, family .. ": ZERO aura reads")
    eq(h.secret_predicate_calls, 0, family .. ": the secrecy predicate is not even consulted")
    h.A.apply_settings(h.ST)
    h.A.on_update(0)
    eq(#h.created, 0, family .. ": apply_settings/on_update stay inert")
    check(type(h.A.diagnostics()) == "table", family .. ": diagnostics still answers a table")
end

-- Forever WITHOUT the native surface: every layer of the gate fails closed.
do
    local missing = {
        { name = "C_AuraContainerUtil", opts = { no_util = true }, reason = "C_AuraContainerUtil" },
        { name = "AuraContainerSortMethod", opts = { no_sort_method = true }, reason = "AuraContainerSortMethod" },
        { name = "AuraContainerSortDirection", opts = { no_sort_direction = true }, reason = "AuraContainerSortDirection" },
    }
    for _, case in ipairs(missing) do
        local h = new_harness(case.opts)
        eq(h.A.available, false, "missing " .. case.name .. ": available is false")
        local available, reason = h.A.gate()
        eq(available, false, "missing " .. case.name .. ": gate() answers false")
        eq(reason, case.reason, "missing " .. case.name .. ": gate() names the missing global")
        eq(h.A.init(h.ST), false, "missing " .. case.name .. ": init is a no-op")
        eq(#h.created, 0, "missing " .. case.name .. ": zero frames")
        eq(h.container_attempts, 0, "missing " .. case.name .. ": no AuraContainer attempt")
    end
end

--=========================================================================================
-- 2. Forever happy path: exactly one driver + two native containers
--=========================================================================================
local function assert_happy_path(h, label)
    local containers = created_of_kind(h, "AuraContainer")
    eq(#containers, 2, label .. ": exactly two native AuraContainer frames")
    eq(#h.created, 3, label .. ": driver + two containers, nothing else")
    local driver = find_frame(h, "SwedgeTimerAuraIconsDriver")
    check(driver ~= nil, label .. ": the driver frame exists by name")
    eq(driver and driver.kind, "Frame", label .. ": the driver is a plain Frame")
    eq(driver and driver.parent, h.env.UIParent, label .. ": the driver is parented to UIParent")
    check(driver and type(driver.scripts.OnUpdate) == "function", label .. ": the driver owns OnUpdate")
    check(driver and type(driver.scripts.OnEvent) == "function", label .. ": the driver owns OnEvent")
    eq(h.events and #h.events, 1, label .. ": exactly one event is registered")
    eq(h.events[1], "PLAYER_ENTERING_WORLD", label .. ": the event is PLAYER_ENTERING_WORLD")

    local buffs = find_frame(h, "SwedgeTimerAuraIconsBuffs")
    local debuffs = find_frame(h, "SwedgeTimerAuraIconsDebuffs")
    check(buffs ~= nil and debuffs ~= nil, label .. ": one container per row")
    eq(buffs and buffs.unit, "player", label .. ": the buff container's unit is player")
    eq(debuffs and debuffs.unit, "target", label .. ": the debuff container's unit is target")
    eq(#(buffs and buffs.group_keys or {}), 1, label .. ": one buff group")
    eq(#(debuffs and debuffs.group_keys or {}), 1, label .. ": one debuff group")
    eq(buffs and buffs.group_keys[1], "buffs", label .. ": the buff group key is buffs")
    eq(debuffs and debuffs.group_keys[1], "debuffs", label .. ": the debuff group key is debuffs")
    local buff_group = buffs and buffs.groups.buffs
    local debuff_group = debuffs and debuffs.groups.debuffs
    check(buff_group ~= nil and debuff_group ~= nil, label .. ": both groups were registered")
    if buff_group == nil or debuff_group == nil then return end
    eq(buff_group.filter, "HELPFUL", label .. ": the buff filter is HELPFUL")
    eq(debuff_group.filter, "HARMFUL|PLAYER", label .. ": the debuff filter is HARMFUL|PLAYER (own caster)")
    local buff_options = buff_group.options
    local debuff_options = debuff_group.options
    check(type(buff_options.candidateFilters) == "table", label .. ": the buff group carries candidateFilters")
    check(type(buff_options.initializeFrame) == "function", label .. ": the buff group has an initializeFrame")
    check(type(debuff_options.initializeFrame) == "function", label .. ": the debuff group has an initializeFrame")
    eq(buff_options.candidateFilters.maxDuration, 180, label .. ": buff maxDuration is 180 (hides permanent auras)")
    eq(debuff_options.candidateFilters.maxDuration, nil, label .. ": the debuff group has NO maxDuration")
    check(type(buff_options.candidateFilters.includeSpellIDs) == "table", label .. ": buff includeSpellIDs is a set")
    check(buff_options.candidateFilters.includeSpellIDs[7384] == true, label .. ": buff includeSpellIDs is keyed by id")
    eq(buff_options.candidateFilters.includeSpellIDs[1], nil, label .. ": includeSpellIDs is a map, not an array")
    eq(buff_options.layout.elementWidth, 27, label .. ": buff element width is the default 27")
    eq(buff_options.layout.elementHeight, 27, label .. ": buff element height is the default 27")
    eq(buff_options.layout.elementSpacing, 3, label .. ": buff element spacing is the default 3")
    eq(debuff_options.layout.elementWidth, 27, label .. ": debuff element width is 27")
    eq(debuff_options.layout.elementSpacing, 3, label .. ": debuff element spacing is 3")
    eq(buff_options.sortMethod, h.env.AuraContainerSortMethod.Expiration, label .. ": buffs sort by expiration")
    eq(buff_options.sortDirection, h.env.AuraContainerSortDirection.Normal, label .. ": buffs sort normal")
    eq(debuff_options.sortMethod, h.env.AuraContainerSortMethod.Expiration, label .. ": debuffs sort by expiration")
    eq(buffs.calls.SetEnabled or 0, 1, label .. ": the buff container is enabled once")
    eq(debuffs.calls.SetEnabled or 0, 1, label .. ": the debuff container is enabled once")
    eq(buffs.flow_anchor, "BOTTOMLEFT", label .. ": the buff row flow-anchors bottom-left")
    eq(debuffs.flow_anchor, "BOTTOMLEFT", label .. ": the debuff row flow-anchors bottom-left")
    check(buffs.grow_direction ~= nil and buffs.grow_direction[1] == 1 and buffs.grow_direction[2] == -1,
        label .. ": the buff row grows right/down")
    check(debuffs.grow_direction ~= nil and debuffs.grow_direction[1] == 1 and debuffs.grow_direction[2] == -1,
        label .. ": the debuff row grows right/down")
    check(buffs.shown == true, label .. ": the buff row is shown out of combat with a visible bar")
    check(debuffs.shown == true, label .. ": the debuff row is shown out of combat with a visible bar")
    eq(buffs.strata, "MEDIUM", label .. ": the container inherits the profile frame strata")
    -- The placeholder size the client replaces through its own layout pass.
    eq(buffs.calls.SetSize or 0, 1, label .. ": the buff container is sized once at creation")
end

do
    local h = boot({})
    eq(h.init_ok, true, "happy path: init does not throw")
    eq(h.inited, true, "happy path: init returns true")
    check(type(h.A) == "table", "happy path: the module namespace exists")
    assert_happy_path(h, "happy path")
    eq(h.A.state.ready, true, "happy path: state.ready is true")
    eq(h.A.state.attempts, 1, "happy path: one creation attempt")
    eq(h.A.state.error, nil, "happy path: no error recorded")

    -- Idempotence: a second init creates nothing, registers nothing and does not bump
    -- the attempt counter.
    local frames_before, events_before = #h.created, #h.events
    local groups_before = count_calls(h, "AddAuraGroup")
    eq(h.A.init(h.ST), true, "idempotent: a second init still answers true")
    eq(#h.created, frames_before, "idempotent: a second init creates no frames")
    eq(#h.events, events_before, "idempotent: a second init registers no events")
    eq(count_calls(h, "AddAuraGroup"), groups_before, "idempotent: a second init adds no aura group")
    eq(h.A.state.attempts, 1, "idempotent: a second init does not count an attempt")
end

-- Two inits through a second entry point after a state reset cannot double-create the
-- named frames either: init is the only creator, and it is idempotent by state.
do
    local h = boot({})
    local before = #h.created
    for _ = 1, 5 do h.A.init(h.ST) end
    eq(#h.created, before, "idempotence under repeated calls: no frame growth")
end

--=========================================================================================
-- 3. Source discipline: native only, no aura-data code, no SuperSwingTimer names
--=========================================================================================
do
    local source = read_source("aura_icons.lua")
    check(not source:find("UnitAura", 1, true),
        "source: no UnitAura reference (it does not exist on Forever and must never be called)")
    check(not source:find("C_UnitAuras", 1, true),
        "source: no C_UnitAuras reference (native containers only; zero aura-data reads)")
    check(not source:find("AuraData", 1, true),
        "source: no AuraData field read anywhere")
    check(not source:find("GetPlayerAuraBySpellID", 1, true),
        "source: no GetPlayerAuraBySpellID (RequiresNonSecretAura)")
    for _, token in ipairs({
        "ns.isForever", "ns.hasAuraContainer", "ns.foreverAura", "ns.mhBar",
        "ns.rangedBar", "ns.WrapLegacyIconUpdaters", "ns.DB_DEFAULTS",
        "showWarriorBuffIcons", "DEBUFF_BARS_BY_CLASS",
    }) do
        check(not source:find(token, 1, true),
            "source: no SuperSwingTimer-only name '" .. token .. "'")
    end
    check(source:find("FOREVER", 1, true) ~= nil, "source: the Forever gate is visible in the module")
end

--=========================================================================================
-- 4. Per-class includeSpellIDs: exact sets, shared/racial merge, no leak, purity
--=========================================================================================
eq(#EXPECTED_SHARED, 5, "reference: five shared buff ids")
do
    local h = new_harness({})
    check(type(h.A.BUFFS) == "table" and type(h.A.DEBUFFS) == "table",
        "lists: the module publishes BUFFS and DEBUFFS")
    same_set(h.A.SHARED, EXPECTED_SHARED, "lists: A.SHARED is the five documented ids")
    local racial_keys = 0
    for _ in pairs(h.A.RACIAL or {}) do racial_keys = racial_keys + 1 end
    eq(racial_keys, 10, "lists: A.RACIAL has the ten documented race keys")
    for _, class in ipairs(CLASSES) do
        eq(#(h.A.BUFFS[class] or {}), EXPECTED_COUNTS.buffs[class],
            "lists: " .. class .. " buff count matches the reference")
        eq(#(h.A.DEBUFFS[class] or {}), EXPECTED_COUNTS.debuffs[class],
            "lists: " .. class .. " debuff count matches the reference")
        same_set(h.A.BUFFS[class], EXPECTED_BUFFS[class],
            "lists: " .. class .. " buff ids are exactly the reference's")
        same_set(h.A.DEBUFFS[class], EXPECTED_DEBUFFS[class],
            "lists: " .. class .. " debuff ids are exactly the reference's")
    end
end

-- 27019 (the TBC Serpent Sting rank) is excluded everywhere; 25295 is the Forever rank.
do
    local h = new_harness({})
    local found = false
    for _, class in ipairs(CLASSES) do
        if (set_of(h.A.DEBUFFS[class]))[27019] then found = true end
        if (set_of(h.A.BUFFS[class]))[27019] then found = true end
    end
    eq(found, false, "27019: the TBC-only rank never appears in any list")
    check((set_of(h.A.DEBUFFS.HUNTER))[25295] == 1, "27019: the Forever Serpent Sting rank 25295 is present")
    -- The removed druid ids must stay out (reference §4.5).
    for _, removed in ipairs({ 33876, 33878, 16857 }) do
        check((set_of(h.A.DEBUFFS.DRUID))[removed] == nil,
            "removed: druid " .. removed .. " is never in the debuff list")
        check((set_of(h.A.BUFFS.DRUID))[removed] == nil,
            "removed: druid " .. removed .. " is never in the buff list")
    end
end

-- Stance ids never leak into either row, and neither row carries the other's tier.
do
    local h = new_harness({})
    for _, class in ipairs(CLASSES) do
        local buffs, debuffs = set_of(h.A.BUFFS[class]), set_of(h.A.DEBUFFS[class])
        for _, stance in ipairs(STANCE_IDS) do
            check(buffs[stance] == nil and debuffs[stance] == nil,
                "stance segregation: " .. class .. " does not carry stance id " .. stance)
        end
    end
end

-- The buff/debuff overlap is exactly the documented 18 new-ability candidates, per class.
do
    local h = new_harness({})
    for _, class in ipairs(CLASSES) do
        local buffs, debuffs = set_of(h.A.BUFFS[class]), set_of(h.A.DEBUFFS[class])
        local overlap = {}
        for id in pairs(buffs) do
            if debuffs[id] then overlap[#overlap + 1] = id end
        end
        local expected = {}
        for id in pairs(CANDIDATES_BY_CLASS[class]) do expected[#expected + 1] = id end
        same_set(overlap, expected,
            "overlap: " .. class .. " buff/debuff overlap is exactly the merged candidates")
    end
end

-- Container creation: exact includeSpellIDs sets (class + shared + racial), per class.
do
    local racial_id = 20600 -- Human / Perception
    for _, class in ipairs(CLASSES) do
        local h = boot({ class = class, race_file = "Human", race_localized = "Human" })
        eq(h.inited, true, "class " .. class .. ": init succeeds")
        local buffs = find_frame(h, "SwedgeTimerAuraIconsBuffs")
        local debuffs = find_frame(h, "SwedgeTimerAuraIconsDebuffs")
        if buffs == nil or debuffs == nil then
            check(false, "class " .. class .. ": both containers exist")
        else
            local want_buffs = deep_copy(EXPECTED_BUFFS[class])
            for _, id in ipairs(EXPECTED_SHARED) do want_buffs[#want_buffs + 1] = id end
            want_buffs[#want_buffs + 1] = racial_id
            same_set(buffs.groups.buffs.options.candidateFilters.includeSpellIDs and
                (function()
                    local list = {}
                    for id in pairs(buffs.groups.buffs.options.candidateFilters.includeSpellIDs) do
                        list[#list + 1] = id
                    end
                    return list
                end)() or {}, want_buffs,
                "class " .. class .. ": buff includeSpellIDs = class + shared + racial")
            same_set(debuffs.groups.debuffs.options.candidateFilters.includeSpellIDs and
                (function()
                    local list = {}
                    for id in pairs(debuffs.groups.debuffs.options.candidateFilters.includeSpellIDs) do
                        list[#list + 1] = id
                    end
                    return list
                end)() or {}, EXPECTED_DEBUFFS[class],
                "class " .. class .. ": debuff includeSpellIDs = the class list only")
            eq(buffs.groups.buffs.options.maxFrameCount, math.min(#want_buffs, 16),
                "class " .. class .. ": buff maxFrameCount = min(list, 16)")
            eq(debuffs.groups.debuffs.options.maxFrameCount, math.min(#EXPECTED_DEBUFFS[class], 16),
                "class " .. class .. ": debuff maxFrameCount = min(list, 16)")
            -- No cross-class leak: the other classes' signature ids never appear.
            for _, other in ipairs(CLASSES) do
                if other ~= class then
                    check(buffs.groups.buffs.options.candidateFilters.includeSpellIDs[SIGNATURE_BUFFS[other]] == nil,
                        "no leak: " .. class .. " buff set excludes " .. other .. "'s signature")
                    check(debuffs.groups.debuffs.options.candidateFilters.includeSpellIDs[SIGNATURE_DEBUFFS[other]] == nil,
                        "no leak: " .. class .. " debuff set excludes " .. other .. "'s signature")
                end
            end
            -- Shared ids never appear in the debuff row; racial ids never either.
            check(debuffs.groups.debuffs.options.candidateFilters.includeSpellIDs[2825] == nil,
                "merge rule: shared ids are buff-only")
            check(debuffs.groups.debuffs.options.candidateFilters.includeSpellIDs[racial_id] == nil,
                "merge rule: racial ids are buff-only")
            check(buffs.groups.buffs.options.candidateFilters.includeSpellIDs[27019] == nil,
                "merge rule: the TBC-only id never reaches the client set")
        end
    end
end

-- Racial merge: file token first, localized name second, both keys for Undead, unknown
-- races add nothing, and the class arrays stay pure (the merge never mutates them).
do
    local h = new_harness({})
    same_set(h.A.racial_ids("Orc"), { 20572 }, "racial: Orc -> Blood Fury")
    same_set(h.A.racial_ids("Troll"), { 26297 }, "racial: Troll -> Berserking")
    same_set(h.A.racial_ids("Human"), { 20600 }, "racial: Human -> Perception")
    same_set(h.A.racial_ids("Dwarf"), { 20594 }, "racial: Dwarf -> Stoneform")
    same_set(h.A.racial_ids("Gnome"), { 20589 }, "racial: Gnome -> Escape Artist")
    same_set(h.A.racial_ids("NightElf"), { 58984 }, "racial: NightElf -> Shadowmeld")
    same_set(h.A.racial_ids("Draenei"), { 28880 }, "racial: Draenei -> Gift of the Naaru")
    same_set(h.A.racial_ids("BloodElf"), { 28730 }, "racial: BloodElf -> Arcane Torrent")
    same_set(h.A.racial_ids("Undead"), { 7744 }, "racial: Undead -> Will of the Forsaken")
    same_set(h.A.racial_ids("Scourge"), { 7744 }, "racial: Scourge (file token) -> Will of the Forsaken")
    same_set(h.A.racial_ids("Worgen"), {}, "racial: an unknown race adds nothing")
    same_set(h.A.racial_ids(nil), {}, "racial: nil is harmless")
    same_set(h.A.racial_ids(42), {}, "racial: a non-string token is harmless")

    local before = deep_copy(h.A.BUFFS.WARRIOR)
    local list = h.A.build_buff_list("WARRIOR", "Scourge", "Undead")
    same_set(h.A.BUFFS.WARRIOR, before, "purity: build_buff_list never mutates the class array")
    check((set_of(list))[7744] == 1, "purity: the merged list carries the racial id once")
    check((set_of(list))[2825] == 1, "purity: the merged list carries each shared id once")
    same_set(h.A.build_debuff_list("WARRIOR"), EXPECTED_DEBUFFS.WARRIOR,
        "purity: build_debuff_list is the class list only")
    same_set(h.A.build_buff_list("MAGE", "Human", "Human"), { 2825, 32182, 35476, 35477, 28507, 20600 },
        "purity: an unknown class gets shared + racial, never another class's list")
    same_set(h.A.build_debuff_list("MAGE"), {}, "purity: an unknown class has an empty debuff list")
end

-- player_racial_ids(): reads UnitRace, file token first, localized fallback, secret-safe.
do
    local h = new_harness({})
    h.race_file, h.race_localized = "Scourge", "Undead"
    same_set(h.A.player_racial_ids(), { 7744 }, "player racial: Scourge/Undead resolves")
    h.race_file, h.race_localized = "Unknown", "Troll"
    same_set(h.A.player_racial_ids(), { 26297 }, "player racial: unknown file token falls back to the localized name")
    h.race_file, h.race_localized = "Unknown", "Unknown"
    same_set(h.A.player_racial_ids(), {}, "player racial: an unknown race adds nothing")
    h.unit_race_raises = true
    same_set(h.A.player_racial_ids(), {}, "player racial: a throwing UnitRace is harmless")
    h.unit_race_raises = false
    h.race_file, h.race_localized = SECRET, SECRET
    same_set(h.A.player_racial_ids(), {}, "player racial: a secret race token adds nothing (never indexed)")
    local h2 = new_harness({})
    h2.env.UnitRace = nil
    same_set(h2.A.player_racial_ids(), {}, "player racial: a client without UnitRace is harmless")
end

-- Fail closed: a class with no list creates NOTHING (not even the driver), and never
-- shows another class's auras.
do
    local h = new_harness({ class = "MAGE" })
    h.ST.db.profile.MAGE = {}
    eq(h.A.init(h.ST), false, "no class list: init answers false")
    eq(#h.created, 0, "no class list: zero frames")
    eq(h.container_attempts, 0, "no class list: no AuraContainer attempt")
    eq(h.A.state.no_class_list, true, "no class list: the reason is recorded (fail closed)")
    eq(#h.events, 0, "no class list: no event")
end

--=========================================================================================
-- 5. Native-only + secrecy: identical behaviour in both secrecy states, zero reads
--=========================================================================================
do
    local secret_on = boot({})
    secret_on.aura_secret = true
    local secret_off = boot({})

    eq(secret_on.aura_reads, 0, "secrecy: zero aura-data reads while auras are secret")
    eq(secret_off.aura_reads, 0, "secrecy: zero aura-data reads while auras are readable")
    eq(secret_on.secret_predicate_calls, 0,
        "secrecy: init never consults the secrecy predicate (the native path is secrecy-agnostic)")
    eq(secret_off.secret_predicate_calls, 0, "secrecy: same on the readable client")

    local function buff_set(h)
        local list = {}
        for id in pairs(find_frame(h, "SwedgeTimerAuraIconsBuffs").groups.buffs.options.candidateFilters.includeSpellIDs) do
            list[#list + 1] = id
        end
        return list
    end
    local function debuff_set(h)
        local list = {}
        for id in pairs(find_frame(h, "SwedgeTimerAuraIconsDebuffs").groups.debuffs.options.candidateFilters.includeSpellIDs) do
            list[#list + 1] = id
        end
        return list
    end
    same_set(buff_set(secret_on), buff_set(secret_off),
        "secrecy: the buff id set is identical in both states")
    same_set(debuff_set(secret_on), debuff_set(secret_off),
        "secrecy: the debuff id set is identical in both states")
    eq(find_frame(secret_on, "SwedgeTimerAuraIconsDebuffs").groups.debuffs.filter, "HARMFUL|PLAYER",
        "secrecy: the own-caster filter is identical in both states")

    -- The predicate feeds diagnostics only; it is fail-closed and never throws.
    eq(secret_on.A.aura_data_secret(), true, "secrecy: diagnostics reports the secret state")
    eq(secret_off.A.aura_data_secret(), false, "secrecy: diagnostics reports the readable state")
    secret_off.secret_raises = true
    eq(secret_off.A.aura_data_secret(), true, "secrecy: a throwing predicate fails closed")
    local no_secrets = new_harness({})
    no_secrets.env.C_Secrets = nil
    eq(no_secrets.A.aura_data_secret(), nil, "secrecy: a client without C_Secrets answers nil")
    check(no_secrets.A.diagnostics().aura_secret == nil, "secrecy: diagnostics carries the nil answer")
end

--=========================================================================================
-- 6. Placement: topmost VISIBLE bar, plain geometry only
--=========================================================================================
local buffs_row, debuffs_row
local function rows(h)
    return find_frame(h, "SwedgeTimerAuraIconsBuffs"), find_frame(h, "SwedgeTimerAuraIconsDebuffs")
end
local function clear_calls(h)
    for index = 1, #h.created do
        h.created[index].calls = {}
        h.created[index].layout_calls = {}
    end
    h.bar_top_reads = 0
    h.enumeration_reads = 0
end
local function point_of(frame)
    return frame.points[1]
end

do
    local h = boot({})
    -- The shipped aura row is a hunter feature; pin the hunter fallback (15 px) and the
    -- hunter widget anchor in this block.
    h.ST.player_class = "HUNTER"
    h.A.anchor(h.ST, true)
    buffs_row, debuffs_row = rows(h)
    local buff_point, debuff_point = point_of(buffs_row), point_of(debuffs_row)
    check(buff_point ~= nil and debuff_point ~= nil, "anchor: both rows are anchored")
    eq(debuff_point.point, "BOTTOM", "anchor: the debuff row BOTTOM")
    eq(debuff_point.relative, h.bars.ranged, "anchor: the debuff row anchors to the topmost visible bar (ranged)")
    eq(debuff_point.relative_point, "TOP", "anchor: ... at that bar's TOP")
    eq(debuff_point.x, 0, "anchor: no horizontal nudge")
    eq(debuff_point.y, 15, "anchor: no visible cast bar means at least 15 px above the ranged bar")
    eq(buff_point.relative, h.bars.ranged, "anchor: the buff row uses the same topmost bar")
    eq(buff_point.y, 58, "anchor: the buff row reserves the debuff band above the 15 px gap")
    eq(h.container_geometry_reads, 0, "anchor: the containers are NEVER measured")
    eq(h.enumeration_reads, 0, "anchor: no aura-frame enumeration on a plain pass")

    -- The hunter Auto Shot cast bar / Rapid Fire / target warning is the anchor when its
    -- plain GetTop is above the topmost swing bar, so the aura row cannot cover it
    -- (operator screenshot 2026-11-09). No cast-bar height is guessed.
    clear_calls(h)
    h.ST.hunter_ui = {
        cast_frame = { IsShown = function() return true end, GetTop = function() return 900 end },
        rapid_fire_bar = { IsShown = function() return true end, GetTop = function() return 920 end },
        target_warning = { IsShown = function() return true end, GetTop = function() return 930 end },
    }
    h.A.anchor(h.ST, true)
    eq(point_of(debuffs_row).relative, h.ST.hunter_ui.target_warning,
        "anchor: the debuff row rides the highest hunter widget (target warning)")
    eq(point_of(debuffs_row).y, 12,
        "anchor: the debuff row adds the explicit hunter clearance")
    eq(point_of(buffs_row).relative, h.ST.hunter_ui.target_warning,
        "anchor: the buff row uses the same hunter anchor")
    eq(point_of(buffs_row).y, 55,
        "anchor: the buff row stacks above the debuff band")
    eq(h.container_geometry_reads, 0,
        "anchor: anchoring to the hunter widget never measures an aura container")
    -- A hidden cast bar must not reserve space: the row falls back to 15 px above the
    -- ranged bar (operator rule: only anchor to the Auto Shot bar while it is shown).
    h.ST.hunter_ui.cast_frame.IsShown = function() return false end
    h.ST.hunter_ui.rapid_fire_bar.IsShown = function() return false end
    h.ST.hunter_ui.target_warning.IsShown = function() return false end
    h.A.anchor(h.ST, true)
    eq(point_of(debuffs_row).relative, h.bars.ranged,
        "anchor: a hidden cast bar falls back to the ranged bar")
    eq(point_of(debuffs_row).y, 15, "anchor: the fallback is the explicit 15 px gap")
    h.ST.hunter_ui = nil
    h.A.anchor(h.ST, true)
    eq(point_of(debuffs_row).relative, h.bars.ranged,
        "anchor: removing the hunter widgets restores the swing-bar anchor")
    eq(point_of(debuffs_row).y, 15, "anchor: the hunter fallback gap stays 15 px")
    clear_calls(h)

    -- Ranged hidden -> mainhand becomes the topmost visible bar.
    clear_calls(h)
    h.bars.ranged.visible = false
    pass(h)
    eq(point_of(debuffs_row).relative, h.bars.mainhand, "anchor: hiding the ranged bar falls back to mainhand")
    eq(point_of(buffs_row).relative, h.bars.mainhand, "anchor: the buff row follows the same fallback")
    eq(buffs_row.calls.SetPoint, 1, "anchor: exactly one SetPoint per row on a bar change")
    eq(debuffs_row.calls.SetPoint, 1, "anchor: exactly one SetPoint per row on a bar change (debuff)")

    -- Unchanged geometry -> the pass is idempotent (no SetPoint at all).
    clear_calls(h)
    pass(h)
    eq(buffs_row.calls.SetPoint, nil, "anchor: an unchanged pass re-points nothing (buff)")
    eq(debuffs_row.calls.SetPoint, nil, "anchor: an unchanged pass re-points nothing (debuff)")

    -- A bar MOVE re-anchors (drag / layout policy / UI scale).
    clear_calls(h)
    h.bars.mainhand.top = h.bars.mainhand.top + 100
    pass(h)
    eq(buffs_row.calls.SetPoint, 1, "anchor: a bar move re-anchors the buff row")
    eq(debuffs_row.calls.SetPoint, 1, "anchor: a bar move re-anchors the debuff row")

    -- Mainhand hidden -> offhand. All hidden -> rows hidden, no SetPoint.
    h.bars.mainhand.visible = false
    clear_calls(h)
    pass(h)
    eq(point_of(debuffs_row).relative, h.bars.offhand, "anchor: mainhand hidden falls back to offhand")
    h.bars.offhand.visible = false
    clear_calls(h)
    pass(h)
    eq(buffs_row.shown, false, "anchor: with every bar hidden the buff row hides")
    eq(debuffs_row.shown, false, "anchor: with every bar hidden the debuff row hides")
    eq(buffs_row.calls.SetPoint, nil, "anchor: hiding never issues a SetPoint (buff)")
    eq(debuffs_row.calls.SetPoint, nil, "anchor: hiding never issues a SetPoint (debuff)")

    -- A bar appearing again re-anchors and re-shows.
    h.bars.offhand.visible = true
    clear_calls(h)
    pass(h)
    eq(buffs_row.shown, true, "anchor: a reappearing bar re-shows the buff row")
    eq(point_of(buffs_row).relative, h.bars.offhand, "anchor: and re-points it at the visible bar")

    -- A lazy hand (no frame yet) is skipped, not an error: restore the full stack.
    h.bars.mainhand.visible = true
    h.bars.mainhand.top = 400
    h.bars.ranged.visible = true
    h.bars.offhand = nil
    local ok = pcall(pass, h)
    eq(ok, true, "anchor: a nil bar frame for an unbuilt hand is skipped without throwing")
    eq(point_of(buffs_row).relative, h.bars.ranged, "anchor: the remaining bars still resolve the top")
    eq(h.container_geometry_reads, 0, "anchor: still no container measurement")
end

-- The pure selector: geometry only, deterministic tie-break, secret-safe.
do
    local h = new_harness({})
    local bar, top = h.A.topmost_visible_bar(h.ST)
    eq(bar, h.bars.ranged, "selector: the highest visible top wins")
    eq(top, 500, "selector: the winning top is returned")
    h.bars.ranged.visible = false
    bar = h.A.topmost_visible_bar(h.ST)
    eq(bar, h.bars.mainhand, "selector: a hidden top bar is not considered")
    h.bars.offhand.top = 400
    h.bars.mainhand.visible = false
    bar = h.A.topmost_visible_bar(h.ST)
    eq(bar, h.bars.offhand, "selector: the next visible bar wins")
    h.bars.mainhand.visible = true
    h.bars.mainhand.top = 400
    bar = h.A.topmost_visible_bar(h.ST)
    eq(bar, h.bars.mainhand, "selector: an exact tie keeps the first hand in class order")
    -- Secret / throwing geometry is skipped, never compared.
    h.bars.ranged.top = SECRET_NUMBER
    h.bars.ranged.visible = true
    h.bars.mainhand.top_raises = true
    h.bars.offhand.visible = false
    local ok, result = pcall(h.A.topmost_visible_bar, h.ST)
    eq(ok, true, "selector: secret/throwing bar geometry never throws")
    eq(result, nil, "selector: secret geometry cannot choose a bar")
    -- A secret IsShown is not visible.
    h.bars.ranged.top = 900
    h.bars.ranged.shown_secret = true
    eq(h.A.topmost_visible_bar(h.ST), nil, "selector: a secret IsShown is treated as not visible")
end

do
    local h = boot({})
    local buffs_here = rows(h)
    h.bars.ranged.top = SECRET_NUMBER
    h.bars.mainhand.top = 400
    clear_calls(h)
    pass(h)
    eq(point_of(buffs_here).relative, h.bars.mainhand,
        "secret: a secret bar top is skipped and the next plain bar is chosen")
    h.bars.ranged.top = SECRET_NUMBER
    h.bars.mainhand.visible = false
    h.bars.offhand.visible = false
    clear_calls(h)
    pass(h)
    eq(buffs_here.shown, false, "secret-only stack: rows hide when no plain top exists")
    eq(h.container_geometry_reads, 0, "secret-only stack: the containers are never measured")
end

--=========================================================================================
-- 7. Options drive layout and visibility; the reserved band collapses
--=========================================================================================
do
    local h = boot({})
    buffs_row, debuffs_row = rows(h)
    eq(h.A.option_enabled(nil), true, "options: nil enabled follows the shipped default (on)")
    eq(h.A.option_enabled({ aura_icons_enabled = false }), false, "options: explicit false disables")
    eq(h.A.option_debuffs(nil), true, "options: nil show_debuffs follows the shipped default (on)")
    eq(h.A.option_size(nil), 27, "options: nil size is the shipped 27")
    eq(h.A.option_size({ aura_icons_size = 30 }), 30, "options: a stored size is honoured")
    eq(h.A.option_size({ aura_icons_size = 1 }), 12, "options: a too-small size clamps to 12")
    eq(h.A.option_size({ aura_icons_size = 500 }), 48, "options: a too-large size clamps to 48")
    eq(h.A.option_spacing(nil), 3, "options: nil spacing is the shipped 3")
    eq(h.A.option_spacing({ aura_icons_spacing = -4 }), 0, "options: negative spacing clamps to 0")
    eq(h.A.option_grow({ aura_icons_grow = "left" }), "left", "options: grow left is honoured")
    eq(h.A.option_grow({ aura_icons_grow = "up" }), "right", "options: an unknown grow direction falls back to right")

    -- Disabled hides both rows but never destroys the frames.
    clear_calls(h)
    h.class_db.aura_icons_enabled = false
    pass(h)
    eq(buffs_row.shown, false, "options: enabled == false hides the buff row")
    eq(debuffs_row.shown, false, "options: enabled == false hides the debuff row")
    check(h.A.state.rows.buffs.container ~= nil, "options: the frames survive being hidden")
    eq(#created_of_kind(h, "AuraContainer"), 2, "options: no container was destroyed")

    -- nil means on again (the shipped default).
    clear_calls(h)
    h.class_db.aura_icons_enabled = nil
    pass(h)
    eq(buffs_row.shown, true, "options: nil enabled shows the buff row again")
    eq(debuffs_row.shown, true, "options: nil enabled shows the debuff row again")

    -- Debuffs off: the debuff row hides and the reserved band collapses.
    clear_calls(h)
    h.class_db.aura_icons_show_debuffs = false
    pass(h)
    eq(debuffs_row.shown, false, "options: show_debuffs == false hides the debuff row")
    eq(buffs_row.shown, true, "options: the buff row stays")
    eq(point_of(buffs_row).y, 6, "options: with no debuff row the band collapses to BAR_GAP")
    eq(point_of(buffs_row).relative, h.bars.ranged, "options: the collapse keeps the top bar")

    h.class_db.aura_icons_show_debuffs = nil
    clear_calls(h)
    pass(h)
    eq(debuffs_row.shown, true, "options: nil show_debuffs shows the debuff row again")
    eq(point_of(buffs_row).y, 49, "options: the band is reserved again")

    -- Size change: layout pushed to both containers, frames resized, band re-anchored.
    clear_calls(h)
    h.class_db.aura_icons_size = 30
    pass(h)
    eq(#buffs_row.layout_calls, 1, "options: a size change pushes the buff layout once")
    eq(#debuffs_row.layout_calls, 1, "options: a size change pushes the debuff layout once")
    eq(buffs_row.layout_calls[1].options.elementWidth, 30, "options: the pushed element width is 30")
    eq(buffs_row.layout_calls[1].options.elementSpacing, 3, "options: the pushed spacing is unchanged")
    eq(buffs_row.children.buffs[1].calls.SetSize or 0, 2,
        "options: existing buff buttons are resized (init + resize)")
    eq(debuffs_row.children.debuffs[1].calls.SetSize or 0, 2,
        "options: existing debuff buttons are resized (init + resize)")
    eq(point_of(buffs_row).y, 52, "options: the buff band follows the new icon size")
    eq(h.enumeration_reads, 6, "options: the resize enumerates each group once (1 count + 2 frames per row)")
    eq(h.container_geometry_reads, 0, "options: the resize never measures the container")

    -- Spacing-only change: layout pushed, but no re-anchor (the band did not change).
    clear_calls(h)
    h.class_db.aura_icons_spacing = 5
    pass(h)
    eq(#buffs_row.layout_calls, 1, "options: a spacing change pushes the buff layout")
    eq(buffs_row.layout_calls[1].options.elementSpacing, 5, "options: the pushed spacing is 5")
    eq(buffs_row.calls.SetPoint, nil, "options: a spacing-only change re-points nothing")
    eq(h.enumeration_reads, 0, "options: a spacing-only change does not enumerate frames")

    -- Grow change: flow-layout direction only.
    clear_calls(h)
    h.class_db.aura_icons_grow = "left"
    pass(h)
    eq(buffs_row.flow_anchor, "BOTTOMRIGHT", "options: grow left flow-anchors the buff row bottom-right")
    eq(debuffs_row.flow_anchor, "BOTTOMRIGHT", "options: grow left flow-anchors the debuff row bottom-right")
    check(buffs_row.grow_direction[1] == -1 and buffs_row.grow_direction[2] == -1,
        "options: grow left sets the left/down flow direction")
    eq(buffs_row.calls.SetPoint, nil, "options: grow left does not re-point the row")
    h.class_db.aura_icons_grow = "right"
    pass(h)
    eq(buffs_row.flow_anchor, "BOTTOMLEFT", "options: grow right restores the bottom-left anchor")

    -- A secret frame count must be skipped, never compared (the client can shroud it).
    h.class_db.aura_icons_size = 40
    h.enumeration_secret = true
    local ok = pcall(h.A.apply_settings, h.ST)
    eq(ok, true, "options: a secret aura-frame count is skipped without throwing")
    eq(h.container_geometry_reads, 0, "options: a secret count path still never measures the container")
    h.enumeration_secret = false

    -- A throwing SetPoint is isolated and retried; it never breaks the pass.
    h.fail_setpoint = true
    h.bars.ranged.top = h.bars.ranged.top + 50
    local pass_ok = pcall(pass, h)
    eq(pass_ok, true, "anchor: a throwing SetPoint never breaks the maintenance pass")
    h.fail_setpoint = false
    clear_calls(h)
    pass(h)
    eq(buffs_row.calls.SetPoint, 1, "anchor: the failed re-anchor is retried on the next pass")
end

--=========================================================================================
-- 8. Throttle: 0.15 s maintenance, 0 forces a pass, PLAYER_ENTERING_WORLD forces one
--=========================================================================================
do
    local h = boot({})
    buffs_row, debuffs_row = rows(h)
    clear_calls(h)
    h.A.on_update(0.05)
    eq(h.bar_top_reads, 0, "throttle: the first 0.05 s does no work")
    h.A.on_update(0.05)
    eq(h.bar_top_reads, 0, "throttle: 0.10 s still does no work")
    h.A.on_update(0.05)
    check(h.bar_top_reads > 0, "throttle: the 0.15 s boundary runs exactly one pass")
    clear_calls(h)
    h.A.on_update(0)
    check(h.bar_top_reads > 0, "throttle: elapsed 0 forces a pass")
    eq(h.A.MAINTAIN_INTERVAL, 0.15, "throttle: the maintenance interval is the documented 0.15 s")

    -- PLAYER_ENTERING_WORLD forces a re-anchor even when nothing measurable changed.
    clear_calls(h)
    h.A.on_event("PLAYER_ENTERING_WORLD")
    eq(buffs_row.calls.SetPoint, 1, "event: PLAYER_ENTERING_WORLD re-anchors the buff row")
    eq(debuffs_row.calls.SetPoint, 1, "event: PLAYER_ENTERING_WORLD re-anchors the debuff row")
    clear_calls(h)
    h.A.on_event("PLAYER_LOGIN")
    eq(buffs_row.calls.SetPoint, nil, "event: an unrelated event is a no-op")
end

--=========================================================================================
-- 9. Combat deferral and creation-failure retry (no latch)
--=========================================================================================
do
    local h = new_harness({})
    h.combat = true
    local ok, result = pcall(h.A.init, h.ST)
    eq(ok, true, "combat: init does not throw")
    eq(result, false, "combat: init answers false while locked down")
    eq(#created_of_kind(h, "AuraContainer"), 0, "combat: ZERO AuraContainer frames in lockdown")
    eq(h.container_attempts, 0, "combat: no AuraContainer creation is even attempted")
    eq(h.A.state.deferred, "combat", "combat: the deferral is recorded")
    check(h.A.state.driver ~= nil, "combat: the plain poll driver exists so the retry can happen")
    eq(#h.events, 1, "combat: the retry event registration is in place")

    h.combat = false
    local pass_ok = pcall(pass, h)
    eq(pass_ok, true, "combat: the deferred creation retries without throwing")
    eq(#created_of_kind(h, "AuraContainer"), 2, "combat: the retry creates both containers out of combat")
    eq(h.A.state.ready, true, "combat: the retry reaches ready")
    eq(h.A.state.deferred, nil, "combat: the deferral is cleared")
end

do
    local h = new_harness({})
    h.fail_container_create = true
    local ok, result = pcall(h.A.init, h.ST)
    eq(ok, true, "create failure: init does not throw")
    eq(result, false, "create failure: init answers false")
    eq(h.container_attempts, 2, "create failure: both template variants are probed")
    check(h.A.state.inert ~= true, "create failure: no permanent latch on template failure")
    check(type(h.A.state.error) == "string", "create failure: the failure is recorded")
    check(h.A.state.driver ~= nil, "create failure: the retry driver exists")
    h.fail_container_create = false
    h.clock = h.clock + 1
    pass(h)
    eq(h.A.state.ready, true, "create failure: a later attempt succeeds (no latch)")
    eq(#created_of_kind(h, "AuraContainer"), 2, "create failure: exactly two containers after recovery")
    eq(h.A.state.error, nil, "create failure: the error clears on success")
end

do
    local h = new_harness({})
    h.fail_add_group = true
    local ok, result = pcall(h.A.init, h.ST)
    eq(ok, true, "group failure: init does not throw")
    eq(result, false, "group failure: init answers false")
    eq(#created_of_kind(h, "AuraContainer"), 2, "group failure: the containers were created once")
    check(h.A.state.ready ~= true, "group failure: the module is not ready")
    check(type(h.A.state.error) == "string", "group failure: the failure is recorded")
    h.fail_add_group = false
    h.clock = h.clock + 1
    pass(h)
    eq(h.A.state.ready, true, "group failure: the retry builds the rows")
    eq(#created_of_kind(h, "AuraContainer"), 2, "group failure: the retry REUSES the containers")
    eq(h.A.state.error, nil, "group failure: the error clears")
    eq(h.bar_calls, 0, "group failure: the swing bars are never shown/hidden by the module")
end

do
    local h = new_harness({})
    h.create_raises = true
    local ok, result = pcall(h.A.init, h.ST)
    eq(ok, true, "broken environment: init does not throw when CreateFrame throws")
    eq(result, false, "broken environment: init answers false")
    eq(#h.created, 0, "broken environment: nothing was created")
end

--=========================================================================================
-- 10. Button styling: the exact initializeFrame the client receives
--=========================================================================================
do
    local h = boot({})
    h.env.Enum = { StatusBarTimerDirection = { RemainingTime = 3 } }
    local buffs = find_frame(h, "SwedgeTimerAuraIconsBuffs")
    local debuffs = find_frame(h, "SwedgeTimerAuraIconsDebuffs")
    local buff_style = buffs.groups.buffs.options.initializeFrame
    local debuff_style = debuffs.groups.debuffs.options.initializeFrame

    local button = new_button()
    buff_style(button)
    eq(button.calls.SetSize or 0, 1, "style: the buff button is sized once")
    eq(button.width, 27, "style: the buff button uses the configured icon edge")
    eq(button.height, 27, "style: the buff button is square")
    eq(button.calls.SetIcon or 0, 1, "style: the buff button hands the client an icon texture")
    check(button.icon ~= nil, "style: the icon texture was registered")
    check(#button.textures >= 2, "style: the button carries the icon and its border")
    eq(button.calls.SetDurationText or 0, 1, "style: the buff button carries the client-owned duration text")
    eq(button.calls.SetApplicationCount or 0, 1, "style: the buff button carries the client-owned stack count")
    eq(button.calls.SetDurationBar, nil, "style: the buff row has NO duration bar in v1")

    local dbutton = new_button()
    debuff_style(dbutton)
    eq(dbutton.calls.SetDurationBar or 0, 1, "style: the debuff button carries the duration bar")
    eq(dbutton.duration_bar_options and dbutton.duration_bar_options.direction, 3,
        "style: the debuff duration bar counts remaining time")
    eq(dbutton.width, 27, "style: the debuff button is the same edge")

    -- The callback reads the CURRENT size, so buttons the client creates after a
    -- settings change are styled with the new edge (not a capture-time constant).
    h.class_db.aura_icons_size = 30
    local later = new_button()
    buff_style(later)
    eq(later.width, 30, "style: a later button is styled with the current icon size")

    -- Every style step is isolated: a throwing setters aborts styling, never the init.
    check(pcall(buff_style, { SetSize = function() error("injected SetSize failure") end }),
        "style: a throwing SetSize never escapes the callback")
    h.button_icon_raises = true
    check(pcall(buff_style, new_button()),
        "style: a throwing SetIcon never escapes the callback")
    h.button_icon_raises = false
end

--=========================================================================================
-- 11. Diagnostics: one nil-safe read model (for a later /st diag lane and in-client probes)
--=========================================================================================
do
    local h = new_harness({})
    local ok, d = pcall(h.A.diagnostics)
    eq(ok, true, "diagnostics: answers on a never-initialised module")
    check(type(d) == "table", "diagnostics: returns a table")
    eq(d.available, true, "diagnostics: reports availability")
    eq(d.ready, false, "diagnostics: reports not-ready before init")
    eq(d.buff, false, "diagnostics: no buff container yet")
    eq(d.debuff, false, "diagnostics: no debuff container yet")

    h = boot({})
    h.aura_secret = true
    d = h.A.diagnostics()
    eq(d.ready, true, "diagnostics: ready after init")
    eq(d.buff, true, "diagnostics: buff container present")
    eq(d.debuff, true, "diagnostics: debuff container present")
    eq(d.buff_shown, true, "diagnostics: buff row shown")
    eq(d.debuff_shown, true, "diagnostics: debuff row shown")
    eq(d.attempts, 1, "diagnostics: one attempt")
    eq(d.aura_secret, true, "diagnostics: the aura secrecy state is reported")
    eq(d.size, 27, "diagnostics: the effective icon size is reported")
    eq(d.spacing, 3, "diagnostics: the effective spacing is reported")
    eq(d.grow, "right", "diagnostics: the effective grow direction is reported")
    eq(d.bar, true, "diagnostics: the top bar was resolved")
    eq(d.error, nil, "diagnostics: no error")

    local non_forever = new_harness({ family = "ERA" })
    d = non_forever.A.diagnostics()
    eq(d.available, false, "diagnostics: non-Forever reports unavailable")
    eq(d.ready, false, "diagnostics: non-Forever is never ready")
end

--=========================================================================================
-- 12. Option widgets: hidden on every non-Forever family, wired to apply_settings
--=========================================================================================
do
    local h = boot({})
    local libs = { ["LibSharedMedia-3.0"] = {}, ["LibWindow-1.1"] = {} }
    local LibStub = setmetatable({}, {
        __call = function(_, major)
            if major == "AceAddon-3.0" then
                return { GetAddon = function() return h.ST end }
            end
            return libs[major]
        end,
    })
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.LibStub = LibStub
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.UnitRace = function() return "Human", "Human" end
    local chunk = assert(loadfile(ROOT .. "option_tables.lua"))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "SwedgeTimer", h.st)
    eq(ok, true, "options: option_tables.lua loads in the sandbox (" .. tostring(err) .. ")")
    -- option_tables.lua's file-scope legacy lowercases the class token; main.lua's
    -- OnInitialize sets the uppercase token at runtime. Restore the runtime shape.
    h.ST.player_class = "WARRIOR"
    local args = h.ST:aura_icon_options_args()
    check(type(args) == "table", "options: the aura icon widget set builds")

    for _, key in ipairs({
        "aura_icons_desc", "aura_icons_header", "aura_icons_enabled",
        "aura_icons_show_debuffs", "aura_icons_size", "aura_icons_spacing",
        "aura_icons_grow",
    }) do
        check(args[key] ~= nil, "options: the '" .. key .. "' widget exists")
    end

    local widgets = { "aura_icons_enabled", "aura_icons_show_debuffs", "aura_icons_size",
        "aura_icons_spacing", "aura_icons_grow" }
    for _, key in ipairs(widgets) do
        local widget = args[key]
        check(widget ~= nil and type(widget.hidden) == "function",
            "options: " .. key .. " carries the family hidden rule")
        check(widget ~= nil and type(widget.order) == "number" and widget.order > 2.7,
            "options: " .. key .. " sits after the HUD block (order > 2.7)")
        check(widget ~= nil and type(widget.get) == "function", "options: " .. key .. " has a getter")
        check(widget ~= nil and type(widget.set) == "function", "options: " .. key .. " has a setter")
        check(widget ~= nil and type(widget.desc) == "string" and widget.desc ~= "",
            "options: " .. key .. " documents itself")
    end
    eq(args.aura_icons_header.type, "header", "options: the section header is a header")
    eq(args.aura_icons_size.type, "range", "options: the size widget is a range")
    eq(args.aura_icons_size.min, 12, "options: the size range starts at 12 px")
    eq(args.aura_icons_size.max, 48, "options: the size range ends at 48 px")
    eq(args.aura_icons_size.step, 1, "options: the size range steps by 1 px")
    eq(args.aura_icons_spacing.min, 0, "options: the spacing range starts at 0 px")
    eq(args.aura_icons_spacing.max, 12, "options: the spacing range ends at 12 px")
    eq(args.aura_icons_grow.type, "select", "options: the grow widget is a select")
    eq(args.aura_icons_grow.values.right, "Grow right", "options: grow right is offered")
    eq(args.aura_icons_grow.values.left, "Grow left", "options: grow left is offered")

    -- Visible on a Forever client, hidden when the family is not Forever (the whole
    -- point of the gate: no control prints on a classic client).
    for _, key in ipairs(widgets) do
        eq(args[key].hidden(), false, "options: " .. key .. " is visible on WoW Forever")
    end
    h.st.family = "ERA"
    for _, key in ipairs(widgets) do
        eq(args[key].hidden(), true, "options: " .. key .. " is hidden on Era")
    end
    h.st.family = "FOREVER"
    local saved = h.st.aura_icons
    h.st.aura_icons = nil
    for _, key in ipairs(widgets) do
        eq(args[key].hidden(), true,
            "options: " .. key .. " fails closed when the module is absent")
    end
    h.st.aura_icons = saved

    -- Getters answer the shipped defaults through a nil class row.
    eq(args.aura_icons_enabled.get(), true, "options: enabled defaults on")
    eq(args.aura_icons_show_debuffs.get(), true, "options: show_debuffs defaults on")
    eq(args.aura_icons_size.get(), 27, "options: size defaults to 27")
    eq(args.aura_icons_spacing.get(), 3, "options: spacing defaults to 3")
    eq(args.aura_icons_grow.get(), "right", "options: grow defaults to right")

    -- Setters write the class row and apply immediately.
    clear_calls(h)
    args.aura_icons_enabled.set(nil, false)
    eq(h.class_db.aura_icons_enabled, false, "options: the enabled setter writes the db key")
    eq(find_frame(h, "SwedgeTimerAuraIconsBuffs").shown, false,
        "options: the enabled setter applies immediately (row hidden)")
    args.aura_icons_enabled.set(nil, true)
    eq(h.class_db.aura_icons_enabled, true, "options: the enabled setter writes true back")
    eq(find_frame(h, "SwedgeTimerAuraIconsBuffs").shown, true,
        "options: the enabled setter applies immediately (row shown)")

    args.aura_icons_show_debuffs.set(nil, false)
    eq(h.class_db.aura_icons_show_debuffs, false, "options: the show_debuffs setter writes the db key")
    eq(find_frame(h, "SwedgeTimerAuraIconsDebuffs").shown, false,
        "options: the show_debuffs setter applies immediately")
    args.aura_icons_show_debuffs.set(nil, true)

    clear_calls(h)
    args.aura_icons_size.set(nil, 30)
    eq(h.class_db.aura_icons_size, 30, "options: the size setter writes the db key")
    eq(find_frame(h, "SwedgeTimerAuraIconsBuffs").layout_calls[1].options.elementWidth, 30,
        "options: the size setter pushes the layout through apply_settings")
    eq(point_of(find_frame(h, "SwedgeTimerAuraIconsBuffs")).y, 52,
        "options: the size setter re-anchors the row immediately")

    args.aura_icons_spacing.set(nil, 5)
    eq(h.class_db.aura_icons_spacing, 5, "options: the spacing setter writes the db key")
    args.aura_icons_grow.set(nil, "left")
    eq(h.class_db.aura_icons_grow, "left", "options: the grow setter writes the db key")
    eq(find_frame(h, "SwedgeTimerAuraIconsBuffs").flow_anchor, "BOTTOMRIGHT",
        "options: the grow setter pushes the flow direction immediately")
end

--=========================================================================================
-- 13. Shipped defaults: config_presets.lua matches the module's runtime defaults
--=========================================================================================
do
    local ST = {}
    for _, token in ipairs({
        "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST",
        "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
    }) do ST[token] = {} end
    local st = { debug = false, utils = { print_msg = function() end } }
    local LibStub = setmetatable({}, {
        __call = function(_, major)
            if major == "AceAddon-3.0" then
                return { GetAddon = function() return ST end }
            end
            return {}
        end,
    })
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.LibStub = LibStub
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.UnitRace = function() return "Human", "Human" end
    local chunk = assert(loadfile(ROOT .. "config_presets.lua"))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "SwedgeTimer", st)
    eq(ok, true, "defaults: config_presets.lua loads in the sandbox (" .. tostring(err) .. ")")
    local defaults = ST.class_defaults
    check(type(defaults) == "table", "defaults: ST.class_defaults exists")
    eq(defaults.aura_icons_enabled, true, "defaults: the aura row ships ON for Forever")
    eq(defaults.aura_icons_show_debuffs, true, "defaults: the debuff row ships ON")
    eq(defaults.aura_icons_size, 27, "defaults: the icon edge ships at 27 px")
    eq(defaults.aura_icons_spacing, 3, "defaults: the icon spacing ships at 3 px")
    eq(defaults.aura_icons_grow, "right", "defaults: the row grows right")

    local h = new_harness({})
    eq(defaults.aura_icons_enabled, h.A.DEFAULTS.enabled,
        "defaults: config_presets and the module agree on enabled")
    eq(defaults.aura_icons_show_debuffs, h.A.DEFAULTS.show_debuffs,
        "defaults: config_presets and the module agree on show_debuffs")
    eq(defaults.aura_icons_size, h.A.DEFAULTS.size,
        "defaults: config_presets and the module agree on size")

    -- A profile saved under the old 22 px default migrates once to the new 27 px edge.
    local mh = new_harness({})
    mh.class_db.aura_icons_size = 22
    eq(mh.A.init(mh.ST), true, "migration: init succeeds on an old profile")
    eq(mh.class_db.aura_icons_size, 27, "migration: the old 22 px edge becomes 27")
    eq(mh.class_db.aura_icons_size_27, true, "migration: the one-time marker is written")
    eq(defaults.aura_icons_spacing, h.A.DEFAULTS.spacing,
        "defaults: config_presets and the module agree on spacing")
    eq(defaults.aura_icons_grow, h.A.DEFAULTS.grow,
        "defaults: config_presets and the module agree on grow")
    -- The neighbouring shared defaults this lane must not move.
    eq(defaults.weave_range_enabled, false, "defaults: the shared weave_range default is untouched")
    eq(defaults.power_bar_enabled, true, "defaults: the shared power bar default is untouched")
    eq(defaults.hud_enabled, true, "defaults: the shared HUD default is untouched")
end

--=========================================================================================
-- 14. Single-TOC registration + harness registry + the main.lua init seam
--=========================================================================================
do
    local toc = read_source("SwedgeTimer.toc")
    local aura_count, aura_at, hud_at, line_index = 0, nil, nil, 0
    for line in toc:gmatch("[^\n]+") do
        line_index = line_index + 1
        local path = line:match("^%s*([^%s]+)%s*$")
        if path == "aura_icons.lua" then
            aura_count = aura_count + 1
            aura_at = line_index
        elseif path == "hud.lua" then
            hud_at = line_index
        end
    end
    eq(aura_count, 1, "toc: aura_icons.lua is listed exactly once")
    check(hud_at ~= nil and aura_at ~= nil and aura_at > hud_at,
        "toc: aura_icons.lua loads after hud.lua")
    check(aura_at ~= nil and aura_at < line_index, "toc: aura_icons.lua is not the TOC tail")
    check(not toc:find("aura_icons%.lua\r", 1), "toc: LF endings preserved (no CR before newline)")

    local run = read_source("tests/run.sh")
    local _, suite_hits = run:gsub('run "lua5%.1 tests/aura_icons_state%.lua" lua5%.1 tests/aura_icons_state%.lua', "")
    eq(suite_hits, 1, "harness: tests/aura_icons_state.lua is registered exactly once")

    local main = read_source("main.lua")
    local _, seams = main:gsub("function ST:init_aura_icons%(%)", "")
    eq(seams, 1, "main.lua: the guarded aura-row seam is defined exactly once")
    local _, calls = main:gsub("self:init_aura_icons%(%)", "")
    eq(calls, 1, "main.lua: the seam is called exactly once")
    local post_at = main:find("function ST:post_init%(%)")
    local call_at = main:find("self:init_aura_icons%(%)")
    local next_fn = post_at and main:find("\nfunction ST:", post_at) or nil
    check(post_at ~= nil and call_at ~= nil and call_at > post_at
        and (next_fn == nil or call_at < next_fn),
        "main.lua: the seam call sits inside post_init (after the bars exist)")
    check(main:find("pcall%(A%.init", 1) ~= nil,
        "main.lua: the seam pcall-isolates the module so a throw costs only the row")
    check(main:find("aura_icons", 1, true) ~= nil, "main.lua: the seam is wired")
end

--=========================================================================================
print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
