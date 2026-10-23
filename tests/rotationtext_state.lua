-- tests/rotationtext_state.lua: offline tests for the rotation label (rotationtext.lua).
--
-- The ported pure logic lives in rotationtext.lua's "PURE section"; this suite loads the
-- module in a minimal sandbox (the frame/driver creation only needs CreateFrame/UIParent
-- stubs) and pins:
--   * the format selection for all four archive formats over the real
--     st.nextaction.display_names / descriptions (nextaction.lua is loaded for this),
--     incl. nil/unknown keys and missing tables,
--   * the alignment-point maths (anchor_point_for / shift_align_offset),
--   * the option gates: a disabled (or provider-less / master-switched) label is hidden
--     and the source is never called (counting resolver),
--   * the paladin provider's live + practice-aware source selection,
--   * the creation gates (pre-init and combat-lockdown deferral, provider-less inert),
--   * config defaults, the PALADIN options widgets, the two Dropdown-SoundPreview
--     selects, the widgets.lua registrations, and the TOC load orders.
-- Run from the repo root: lua5.1 tests/rotationtext_state.lua  (any cwd works).

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

--=========================================================================================
-- Sandbox: load rotationtext.lua with the minimal frame/API stubs it touches
--=========================================================================================
local created_frames = 0
local lockdown = false

local function make_frame()
    created_frames = created_frames + 1
    local f = {}
    function f:SetScript() end
    function f:RegisterEvent() end
    return f
end

local ST = {
    PALADIN = {},
    player_class = "PALADIN",
    active_class = "PALADIN",
    -- The addon master switches the gate reads.
    db = { profile = { enabled = true } },
}
local st = { debug = false }

local env = setmetatable({}, { __index = _G })
env.LibStub = function(major)
    if major == "AceAddon-3.0" then
        return { GetAddon = function() return ST end }
    end
    return {}
end
env.CreateFrame = function() return make_frame() end
env.UIParent = {}
env.InCombatLockdown = function() return lockdown end

-- guard.lua owns the shared error-isolation contract (the TOCs load it right after
-- utils.lua and before every consumer).
local guard_chunk = assert(loadfile(ROOT .. "guard.lua"))
setfenv(guard_chunk, env)
guard_chunk("SwedgeTimer", st)

local chunk = assert(loadfile(ROOT .. "rotationtext.lua"))
setfenv(chunk, env)
local ok, err = pcall(chunk, "SwedgeTimer", st)
if not ok then
    print("FAIL  rotationtext.lua does not load under the sandbox: " .. tostring(err))
    os.exit(1)
end
local RT = st.rotation_text

check(type(RT) == "table", "rotationtext.lua defines st.rotation_text")
eq(created_frames, 1, "only the driver frame is created at file load")
check(RT.frame == nil, "the label frame is NOT created at file load")

-- C5 (class-isolation 2026-10-21): the paladin provider is the PALADIN's own
-- function in classes/paladin.lua. This suite extracts the marked block and
-- loads the SHIPPED source into its sandbox (no copy of the body here).
local rot_fh = assert(io.open(ROOT .. "rotationtext.lua", "r"))
local rot_src = rot_fh:read("*a")
rot_fh:close()
check(rot_src:find("ST.PALADIN.get_rotation_key", 1, true) == nil,
    "rotationtext.lua no longer defines the paladin provider (the class owns it)")
local function paladin_block(open_marker, close_marker)
    local fh = assert(io.open(ROOT .. "classes/paladin.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    local a = src:find(open_marker, 1, true)
    local b = src:find(close_marker, 1, true)
    assert(a and b and a < b, "classes/paladin.lua provider markers not found")
    return src:sub(a + #open_marker, b - 1)
end
local pal_chunk = assert(loadstring(paladin_block(
    "-- >>> rotationtext provider >>>", "-- <<< rotationtext provider <<<")))
setfenv(pal_chunk, env)
env.ST = ST
env.st = st
pal_chunk()
eq(type(ST.PALADIN.get_rotation_key), "function",
    "classes/paladin.lua owns the paladin provider")

local entry_points = {
    "format_value", "anchor_point_for", "shift_align_offset", "should_show_state",
    "decide_update", "provider", "current_rotation", "resolve_live", "should_show",
    "create", "set_text", "set_align", "apply_settings", "refresh_layout_cache",
    "layout_changed", "save_position", "update_display", "on_update", "init", "ensure_created",
}
for i = 1, #entry_points do
    check(type(RT[entry_points[i]]) == "function",
        "rotationtext.lua exposes " .. entry_points[i])
end

-- The real rotation tables (the label must never duplicate them).
local na_st = {}
local na_chunk = assert(loadfile(ROOT .. "nextaction.lua"))
na_chunk("SwedgeTimer", na_st)
local NAMES = na_st.nextaction.display_names
local DESCS = na_st.nextaction.descriptions

--=========================================================================================
-- 1) Format selection: every key x all four archive formats, over the real tables
--=========================================================================================
local FORMAT_EXPECTED = {
    ["1/2"] = { name = "1/2", desc = "CS, Twist" },
    ["2/3"] = { name = "2/3", desc = "CS, Twist, Twist" },
    ["2/2/5"] = { name = "2/2/5", desc = "CS, Twist, CS (late), Auto, Twist" },
    ["2/4"] = { name = "2/4", desc = "CS, Twist, Auto, Twist" },
    ["1/3"] = { name = "1/3", desc = "CS, Auto, Twist" },
    ["2/5_blood"] = { name = "2/5 Blood", desc = "CS, Auto, Twist, Auto, Twist" },
    ["2/5_command"] = { name = "2/5 Command", desc = "CS, Cmd Auto, Twist, Cmd Auto, Twist" },
    ["2007"] = { name = "2007", desc = "Ride Blood & CS" },
}
for key, exp in pairs(FORMAT_EXPECTED) do
    eq(RT.format_value(key, "key", NAMES, DESCS), exp.name, key .. " key -> " .. exp.name)
    eq(RT.format_value(key, "labelled", NAMES, DESCS), "Rotation: " .. exp.name,
        key .. " labelled -> Rotation: " .. exp.name)
    eq(RT.format_value(key, "steps", NAMES, DESCS), exp.desc, key .. " steps -> " .. exp.desc)
    eq(RT.format_value(key, "both", NAMES, DESCS), exp.name .. "  -  " .. exp.desc,
        key .. " both -> " .. exp.name .. "  -  " .. exp.desc)
end
-- The default format is "key" (nil / unknown format values fall back to it).
eq(RT.format_value("2/3", nil, NAMES, DESCS), "2/3", "nil format behaves as key")
eq(RT.format_value("2/3", "garbage", NAMES, DESCS), "2/3", "unknown format behaves as key")

--=========================================================================================
-- 2) nil / unknown / missing-table handling
--=========================================================================================
eq(RT.format_value(nil, "key", NAMES, DESCS), "", "nil key -> empty text")
eq(RT.format_value(nil, "labelled", NAMES, DESCS), "", "nil key -> empty text (labelled)")
eq(RT.format_value("9/9", "key", NAMES, DESCS), "9/9", "unknown key -> the key itself")
eq(RT.format_value("9/9", "labelled", NAMES, DESCS), "Rotation: 9/9", "unknown key -> labelled")
eq(RT.format_value("9/9", "steps", NAMES, DESCS), "9/9", "unknown key -> steps falls back to the key")
eq(RT.format_value("9/9", "both", NAMES, DESCS), "9/9", "unknown key -> both falls back to the key")
eq(RT.format_value("2/3", "key", nil, nil), "2/3", "missing tables -> name is the key")
eq(RT.format_value("2/3", "steps", nil, nil), "2/3", "missing tables -> steps is the key")
eq(RT.format_value("2/3", "both", nil, nil), "2/3", "missing tables -> both is the name")
eq(RT.format_value("2/3", "steps", { ["2/3"] = "2/3" }, {}), "2/3",
    "known key without a description -> steps falls back to the name")
eq(RT.format_value("2/3", "both", { ["2/3"] = "2/3" }, {}), "2/3",
    "known key without a description -> both is the name alone")

--=========================================================================================
-- 3) Alignment maths (archive 105-147)
--=========================================================================================
eq(RT.anchor_point_for("left"), "LEFT", "align left -> LEFT")
eq(RT.anchor_point_for("right"), "RIGHT", "align right -> RIGHT")
eq(RT.anchor_point_for("center"), "CENTER", "align center -> CENTER")
eq(RT.anchor_point_for(nil), "CENTER", "nil align -> CENTER")
eq(RT.anchor_point_for("garbage"), "CENTER", "unknown align -> CENTER")

eq(RT.shift_align_offset("center", "center", 100, 80), 100, "same point: offset unchanged")
eq(RT.shift_align_offset("center", "left", 100, 80), 60, "center -> left moves the anchor in")
eq(RT.shift_align_offset("left", "center", 60, 80), 100, "left -> center restores the centre")
eq(RT.shift_align_offset("center", "right", 100, 80), 140, "center -> right moves the anchor out")
eq(RT.shift_align_offset("right", "center", 140, 80), 100, "right -> center restores the centre")
eq(RT.shift_align_offset("left", "right", 60, 80), 140, "left -> right is the same edge, opposite side")
eq(RT.shift_align_offset("right", "left", 140, 80), 60, "right -> left is the same edge, opposite side")
eq(RT.shift_align_offset("left", "center", RT.shift_align_offset("center", "left", 100, 80), 80), 100,
    "centre -> left -> centre round-trips")
eq(RT.shift_align_offset("center", "left", nil, nil), 0, "nil offset/width -> 0")
eq(RT.shift_align_offset("center", "left", 100, nil), 100, "nil width -> no shift (zero-width box)")
eq(RT.shift_align_offset("left", "left", 100, 80), 100, "same point ignores the width")

--=========================================================================================
-- 4) Option gates: hidden when disabled/provider-less/master-switched, no source calls
--=========================================================================================
local function gate(overrides)
    local s = {
        has_provider = true,
        global_enabled = true,
        class_enabled = true,
        label_enabled = true,
        locked = true,
        in_combat = false,
        practice_active = false,
        visibility_key = "always",
    }
    for k, v in pairs(overrides or {}) do
        s[k] = v
    end
    return s
end

eq(RT.should_show_state(gate()), true, "enabled + always -> visible")
eq(RT.should_show_state(gate({ label_enabled = false })), false, "disabled -> hidden")
local nil_default = gate()
nil_default.label_enabled = nil
eq(RT.should_show_state(nil_default), false, "disabled (nil default) -> hidden")
eq(RT.should_show_state(gate({ has_provider = false })), false, "no provider -> hidden")
eq(RT.should_show_state(gate({ has_provider = false, practice_active = true })), false,
    "no provider hides even in practice")
eq(RT.should_show_state(gate({ global_enabled = false })), false, "addon master switch off -> hidden")
eq(RT.should_show_state(gate({ class_enabled = false })), false, "class switch off -> hidden")
eq(RT.should_show_state(gate({ locked = false })), true, "unlocked -> visible for positioning")
eq(RT.should_show_state(gate({ locked = false, in_combat = false, visibility_key = "in_combat" })), true,
    "unlocked overrides the in_combat key (positioning rule)")
eq(RT.should_show_state(gate({ practice_active = true })), true, "practice -> visible")
eq(RT.should_show_state(gate({ in_combat = true })), true, "always + in combat -> visible")
eq(RT.should_show_state(gate({ visibility_key = "in_combat", in_combat = false })), false,
    "in_combat key, out of combat -> hidden")
eq(RT.should_show_state(gate({ visibility_key = "in_combat", in_combat = true })), true,
    "in_combat key, in combat -> visible")
eq(RT.should_show_state(gate({ visibility_key = "garbage" })), true, "unknown visibility key -> always")
eq(RT.should_show_state(gate({ visibility_key = nil })), true, "nil visibility key -> always")
eq(RT.should_show_state(gate({ label_enabled = false, practice_active = true })), false,
    "disabled hides even in practice")

-- decide_update: the counting resolver proves the source is only called when visible.
local calls = 0
local function counting_resolver()
    calls = calls + 1
    return "2/3"
end
calls = 0
local hidden_visible, hidden_key = RT.decide_update(gate({ label_enabled = false }), counting_resolver)
eq(hidden_visible, false, "decide_update: disabled -> hidden")
eq(hidden_key, nil, "decide_update: disabled -> no key")
eq(calls, 0, "decide_update: disabled -> the source is never called")
calls = 0
local shown_visible, shown_key = RT.decide_update(gate(), counting_resolver)
eq(shown_visible, true, "decide_update: enabled -> visible")
eq(shown_key, "2/3", "decide_update: enabled -> the source's key")
eq(calls, 1, "decide_update: enabled -> exactly one source call")
calls = 0
local noprov_visible = RT.decide_update(gate({ has_provider = false }), counting_resolver)
eq(noprov_visible, false, "decide_update: no provider -> hidden")
eq(calls, 0, "decide_update: no provider -> no source call")
local noresolver_visible, noresolver_key = RT.decide_update(gate(), nil)
eq(noresolver_visible, true, "decide_update: visible without a resolver")
eq(noresolver_key, nil, "decide_update: no resolver -> nil key (renders as empty)")

--=========================================================================================
-- 5) The paladin provider: live guide source + practice-aware switch
--=========================================================================================
eq(RT.provider(ST) ~= nil, true, "provider: the paladin implements get_rotation_key")
local saved_class = ST.player_class
ST.player_class = "WARRIOR"
ST.active_class = "WARRIOR"
eq(RT.provider(ST), nil, "provider: a class without get_rotation_key has none")
-- C7: the ACTIVE class wins over the class being PLAYED.
ST.player_class = "WARRIOR"
ST.active_class = "PALADIN"
eq(RT.provider(ST) ~= nil, true,
    "provider: the ACTIVE class wins over the playing class")
ST.player_class = saved_class
ST.active_class = saved_class

st.nextaction = na_st.nextaction
local live_self = {
    mainhand = { speed = 2.3 },
    get_spell_gcd_duration = function() return 1.15 end,
}
eq(ST.PALADIN.get_rotation_key(live_self), "2/3",
    "provider(live): 2.3s swing / 1.15 G -> 2/3 (the guide's own thresholds)")
live_self.mainhand.speed = 3.5
live_self.get_spell_gcd_duration = function() return 1.5 end
eq(ST.PALADIN.get_rotation_key(live_self), "1/2", "provider(live): 3.5s swing -> 1/2")
live_self.mainhand.speed = 0
eq(ST.PALADIN.get_rotation_key(live_self), nil, "provider(live): no weapon speed -> nil")
live_self.mainhand = nil
eq(ST.PALADIN.get_rotation_key(live_self), nil, "provider(live): no mainhand state -> nil (no error)")

-- Practice sessions switch to the simulation's source (the archive's rule).
st.practice = { determine_rotation = function(sim) return "2/4", sim end }
st.practice_ui = { is_active = function() return true end, sim = {} }
local sim = select(2, ST.PALADIN.get_rotation_key(live_self))
eq(select(1, ST.PALADIN.get_rotation_key(live_self)), "2/4",
    "provider(practice): the simulation's rotation wins")
check(sim == st.practice_ui.sim, "provider(practice): the session's sim is the source input")
st.practice_ui.is_active = function() return false end
live_self.mainhand = { speed = 2.3 }
live_self.get_spell_gcd_duration = function() return 1.15 end
eq(ST.PALADIN.get_rotation_key(live_self), "2/3", "provider: non-active practice falls back to live")

-- Missing engine: silent nil, never an error.
local saved_na = st.nextaction
st.nextaction = nil
eq(ST.PALADIN.get_rotation_key(live_self), nil, "provider: missing st.nextaction -> nil")
st.nextaction = saved_na

--=========================================================================================
-- 6) Creation gates: pre-init, combat lockdown, provider-less inertness
--=========================================================================================
ST.interfaces_are_initialised = nil
eq(RT.ensure_created(ST), false, "pre-init: creation is refused")
eq(created_frames, 1, "pre-init: no frame is created")

ST.interfaces_are_initialised = true
lockdown = true
eq(RT.ensure_created(ST), false, "lockdown: creation is deferred")
eq(RT.pending_create, true, "lockdown: the deferral is recorded")
eq(created_frames, 1, "lockdown: no frame is created in combat")

lockdown = false
local provider = ST.PALADIN.get_rotation_key
ST.PALADIN.get_rotation_key = nil
eq(RT.ensure_created(ST), false, "no provider: creation is refused")
eq(RT.inert, true, "no provider: the module goes inert")
eq(RT.ensure_created(ST), false, "inert: an inert module never retries")
eq(created_frames, 1, "no provider: no frame is created")
ST.PALADIN.get_rotation_key = provider

--=========================================================================================
-- 7) Config, options, widgets and TOC wiring (static text checks)
--=========================================================================================
local function read(path)
    local f = assert(io.open(ROOT .. path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

do
    local presets = read("config_presets.lua")
    local shared = presets:match("ST%.class_defaults%s*=%s*{(.-)\n}") or ""
    check(shared ~= "", "the class_defaults block is found in config_presets.lua")
    local shared_defaults = {
        { "rotation_label_enabled", "false" },
        { "rotation_label_visibility_key", "\"always\"" },
        { "rotation_label_format", "\"key\"" },
        { "rotation_label_align", "\"center\"" },
        { "rotation_label_x", "0" },
        { "rotation_label_y", "%-150" },
        { "rotation_label_scale", "1" },
        { "rotation_label_locked", "true" },
        { "rotation_label_font", "\"Expressway\"" },
        { "rotation_label_size", "16" },
        { "rotation_label_outline", "\"outline\"" },
    }
    for i = 1, #shared_defaults do
        local default_key, value = shared_defaults[i][1], shared_defaults[i][2]
        check(shared:find("%f[%a_]" .. default_key .. "%s*=%s*" .. value) ~= nil,
            default_key .. " ships in the shared class defaults (value " .. value .. ")")
    end
    check(shared:find("rotation_label_color%s*=%s*{%s*255%s*,%s*209%s*,%s*0%s*,%s*1%s*}") ~= nil,
        "rotation_label_color ships as the archive's colour in 0-255 storage")

    local options = read("option_tables.lua")
    local paladin_opts = options:match("function ST%.class_opts_funcs%.PALADIN%((.*)$") or ""
    check(paladin_opts ~= "", "the PALADIN options function is found")
    local widget_types = {
        rotation_label_enabled = "toggle",
        rotation_label_locked = "toggle",
        rotation_label_visibility_key = "select",
        rotation_label_format = "select",
        rotation_label_align = "select",
        rotation_label_x = "input",
        rotation_label_y = "input",
        rotation_label_scale = "range",
        rotation_label_font = "select",
        rotation_label_size = "range",
        rotation_label_outline = "select",
        rotation_label_color = "color",
    }
    for widget_key, widget_type in pairs(widget_types) do
        local widget = paladin_opts:match("%f[%a_]" .. widget_key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"" .. widget_type .. "\"") ~= nil,
            widget_key .. " has a " .. widget_type .. " widget in the PALADIN options")
    end
    check(paladin_opts:find("rotation_label_align%s*=%s*{") ~= nil
        and paladin_opts:find("set%f[%A]") ~= nil
        and paladin_opts:find("st%.rotation_text%.set_align") ~= nil,
        "the alignment widget routes through st.rotation_text.set_align")

    local sound_selects = { "twist_sound_choice", "twist_success_sound_choice" }
    for i = 1, #sound_selects do
        local select_key = sound_selects[i]
        local widget = paladin_opts:match("%f[%a_]" .. select_key .. "%s*=%s*{(.-)\n%s*}") or ""
        check(widget:find("dialogControl%s*=%s*\"Dropdown%-SoundPreview\"") ~= nil,
            select_key .. " uses the Dropdown-SoundPreview widget")
    end

    local widgets_src = read("widgets.lua")
    check(widgets_src:find('"Dropdown-Left"', 1, true) ~= nil,
        "widgets.lua defines the Dropdown-Left widget")
    check(widgets_src:find('"Dropdown-SoundPreview"', 1, true) ~= nil,
        "widgets.lua defines the Dropdown-SoundPreview widget")
    check(widgets_src:find("RegisterWidgetType", 1, true) ~= nil
        and widgets_src:find("AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)", 1, true) ~= nil,
        "both widgets are registered with AceGUI")
    check(widgets_src:find("preview_sound", 1, true) ~= nil
        and widgets_src:find("PlaySoundFile", 1, true) ~= nil,
        "the sound preview plays through PlaySoundFile")
    check(widgets_src:find("recover_class_sound_map", 1, true) ~= nil,
        "the sound map resolver documents its class-map recovery")
end

do
    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Cata.toc", "SwedgeTimer_Mists.toc",
        "SwedgeTimer_Mainline.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local function pos(needle)
            return text:find(needle, 1, true)
        end
        local acegui = pos("Libs\\AceGUI-3.0\\AceGUI-3.0.xml")
        local widgets = pos("\nwidgets.lua")
        local options = pos("\noption_tables.lua")
        local main = pos("\nmain.lua")
        local hud = pos("\nhud.lua")
        local rotation = pos("\nrotationtext.lua")
        local presets = pos("\nconfig_presets.lua")
        check(acegui and widgets and options and acegui < widgets and widgets < options,
            tocs[i] .. ": widgets.lua loads after the AceGUI library and before option_tables.lua")
        check(main and hud and rotation and presets and main < rotation and hud < rotation
                and rotation < presets,
            tocs[i] .. ": rotationtext.lua loads after main.lua/hud.lua and before config_presets.lua")
    end
end

--=========================================================================================
-- 8) Non-paladin rotation sources: hunter, warrior, druid, shaman, rogue
--=========================================================================================
-- A richer sandbox than the minimal one above: the class modules need compat's
-- wrappers (api.*), utils' lookup builder and their pure guide engines. Each
-- get_rotation_key is exercised through the real gather + evaluate chain with
-- stubbed client answers.
do
    local cclock = 1000
    local ccooldowns = {}
    local cknown = {}
    local cpower_single, cpower_by_type = nil, {}
    local cpowercost_impl = nil
    local ctarget_exists = false
    local chealth, chealth_max = nil, nil
    local cclass_db = { class_enabled = true }

    local C_SPELL_INFOS = {
        [56641] = "Steady Shot", [2973] = "Raptor Strike", [34026] = "Kill Command",
        [2643] = "Multi-Shot", [19574] = "Bestial Wrath", [3045] = "Rapid Fire",
        [7384] = "Overpower", [5308] = "Execute", [1464] = "Slam",
        [78] = "Heroic Strike", [845] = "Cleave", [23881] = "Bloodthirst",
        [1680] = "Whirlwind", [6807] = "Maul", [33878] = "Mangle",
        [1079] = "Rip", [1822] = "Rake", [22568] = "Ferocious Bite",
        [5221] = "Shred", [17364] = "Stormstrike", [8050] = "Flame Shock",
        [403] = "Lightning Bolt", [1535] = "Fire Nova Totem",
        [8042] = "Earth Shock", [8512] = "Windfury Totem",
        [108] = "Sinister Strike", [102] = "Rupture", [109] = "Eviscerate",
        [110] = "Envenom", [103] = "Expose Armor", [111] = "Shiv",
        [106] = "Thistle Tea",
    }
    local C_CAST_TIMES = { [56641] = 1500, [2643] = 500 }

    local CST = {
        PALADIN = {}, HUNTER = {}, WARRIOR = {}, DRUID = {}, SHAMAN = {}, ROGUE = {},
        player_class = "PALADIN",
        db = { profile = { enabled = true } },
        interfaces_are_initialised = true,
    }
    function CST.get_class_table() return cclass_db end

    local cst = { debug = false }
    local cenv = setmetatable({}, { __index = _G })
    cenv._G = cenv
    cenv.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return CST end }
        elseif major == "LibCustomGlow-1.0" then
            return { PixelGlow_Start = function() end, PixelGlow_Stop = function() end }
        elseif major == "LibSharedMedia-3.0" then
            return { Fetch = function(_, mediatype)
                if mediatype == "font" then return "Fonts\\FRIZQT__.TTF" end
            end }
        end
        return {}
    end
    cenv.WOW_PROJECT_ID = 5
    cenv.WOW_PROJECT_CLASSIC = 2
    cenv.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    cenv.WOW_PROJECT_WRATH_CLASSIC = 11
    cenv.WOW_PROJECT_MAINLINE = 1
    cenv.GetTimePreciseSec = function() return cclock end
    cenv.GetTime = function() return cclock end
    cenv.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    cenv.GetLocale = function() return "enUS" end
    cenv.GetBuildInfo = function() return "0.0.0", "00000", "today", 20506 end
    cenv.UIParent = {}
    cenv.CreateFrame = function()
        return { SetScript = function() end, RegisterEvent = function() end }
    end
    cenv.InCombatLockdown = function() return false end
    cenv.GetSpellInfo = function(spell)
        local name = C_SPELL_INFOS[spell]
        if name then
            return name, nil, "icon_" .. tostring(spell), C_CAST_TIMES[spell] or 0, 0, 0, spell
        end
        return nil
    end
    cenv.GetSpellCooldown = function(spell)
        local cd = ccooldowns[spell]
        if cd then
            return cd.start or 0, cd.duration or 0, cd.enable or 1, 1
        end
        return 0, 0, 0, 0
    end
    cenv.IsSpellKnown = function(spell) return cknown[spell] == true end
    cenv.GetSpellPowerCost = function(spell)
        if cpowercost_impl then return cpowercost_impl(spell) end
        return nil
    end
    cenv.UnitPower = function(unit, power_type)
        if power_type ~= nil then return cpower_by_type[power_type] end
        return cpower_single
    end
    cenv.UnitHealth = function() return chealth end
    cenv.UnitHealthMax = function() return chealth_max end
    cenv.UnitAura = function() return nil end
    cenv.UnitCastingInfo = function() return nil end
    cenv.UnitChannelInfo = function() return nil end
    cenv.UnitExists = function() return ctarget_exists end
    cenv.UnitGUID = function() return "Player-1" end
    cenv.IsSpellInRange = function() return 1 end

    local cmodules = { "compat.lua", "utils.lua", "guard.lua", "hunter_window.lua", "weave.lua",
        "hunter_guide.lua", "warrior_guide.lua", "druid_guide.lua", "shaman_guide.lua",
        "rogue_guide.lua",
        "classes/hunter.lua", "classes/warrior.lua", "classes/druid.lua",
        "classes/shaman.lua", "classes/rogue.lua", "rotationtext.lua" }
    for i = 1, #cmodules do
        local cchunk = assert(loadfile(ROOT .. cmodules[i]))
        setfenv(cchunk, cenv)
        local cok, cerr = pcall(cchunk, "SwedgeTimer", cst)
        check(cok, cmodules[i] .. " loads in the class sandbox" ..
            (cok and "" or (": " .. tostring(cerr))))
        -- Operator order 2026-10-21: a wrapped class file registers its body as a
        -- loader; the sandbox activates it exactly as main.lua does at init.
        local class = cmodules[i]:match("classes/(%a+)%.lua")
        if class and type(cst.class_loaders) == "table"
            and type(cst.class_loaders[class:upper()]) == "function" then
            cst.class_loaders[class:upper()]()
        end
    end
    local RT2 = cst.rotation_text
    check(type(RT2) == "table", "the class sandbox exposes st.rotation_text")
    eq(cst.family, "TBC", "the class sandbox runs the TBC family")

    local function creset()
        cclock = 1000
        ccooldowns = {}
        cknown = {}
        cpower_single, cpower_by_type = nil, {}
        cpowercost_impl = nil
        ctarget_exists = false
        chealth, chealth_max = nil, nil
        CST.mainhand, CST.gcd, CST.latency = nil, {}, nil
        CST.in_combat = false
        CST.raptor_strike_queued, CST.steady_shot_queued = nil, nil
        CST.hs_queued, CST.cleave_queued, CST.insufficient_rage = nil, nil, nil
        CST.has_bloodsurge, CST.warrior_overpower_proc_until = nil, nil
        CST.warrior_slam_casting = nil
        CST.form_index, CST.maul_queued = nil, nil
        CST.weave_is_casting, CST.weave_fs_duration, CST.weave_fs_expires = nil, nil, nil
        CST.weave_windfury_active = nil
        cclass_db = { class_enabled = true }
    end

    -- Provider detection across the five new classes.
    for _, class in ipairs({ "HUNTER", "WARRIOR", "DRUID", "SHAMAN", "ROGUE" }) do
        CST.player_class = class
CST.active_class = class
        check(RT2.provider(CST) ~= nil,
            "provider: " .. class .. " implements get_rotation_key")
    end
    CST.player_class = "MAGE"
CST.active_class = "MAGE"
    eq(RT2.provider(CST), nil, "provider: a class without get_rotation_key has none")
    CST.player_class = "PALADIN"
CST.active_class = "PALADIN"

    -- Hunter: idle, RIDE, then the Kill Command priority.
    do
        CST.player_class = "HUNTER"
CST.active_class = "HUNTER"
        creset()
        eq(CST.HUNTER.get_rotation_key(CST), nil, "hunter rotation: idle -> nil")
        CST.raptor_strike_queued = true
        eq(CST.HUNTER.get_rotation_key(CST), "RIDE", "hunter rotation: queued -> RIDE")
        CST.raptor_strike_queued = nil
        cknown[34026] = true
        CST.HUNTER.resolve_guide_icons()
        eq(CST.HUNTER.get_rotation_key(CST), "Kill Command",
            "hunter rotation: ready Kill Command names the localized spell")
        eq(RT2.current_rotation(CST), "Kill Command",
            "hunter rotation: the consumer reads the same label")
        eq(RT2.format_value("Kill Command", "key", NAMES, DESCS), "Kill Command",
            "hunter rotation: an unknown key renders as itself (no consumer change)")
        local saved = cst.hunter_guide
        cst.hunter_guide = nil
        eq(CST.HUNTER.get_rotation_key(CST), nil, "hunter rotation: missing engine -> nil")
        cst.hunter_guide = saved
    end

    -- Warrior: the TBC reader-ready default, the Overpower precedence, RIDE.
    do
        CST.player_class = "WARRIOR"
CST.active_class = "WARRIOR"
        creset()
        eq(CST.WARRIOR.get_rotation_key(CST), "Bloodthirst",
            "warrior rotation: the TBC reader-ready default is Bloodthirst")
        CST.warrior_overpower_proc_until = cclock + 5
        eq(CST.WARRIOR.get_rotation_key(CST), "Overpower",
            "warrior rotation: a live dodge window pre-empts Bloodthirst")
        CST.warrior_overpower_proc_until = nil
        CST.hs_queued = true
        eq(CST.WARRIOR.get_rotation_key(CST), "RIDE",
            "warrior rotation: a queued Heroic Strike rides")
        CST.hs_queued = nil
        local saved = cst.warrior_guide
        cst.warrior_guide = nil
        eq(CST.WARRIOR.get_rotation_key(CST), nil, "warrior rotation: missing engine -> nil")
        cst.warrior_guide = saved
    end

    -- Druid: form-gated, bear Maul, TBC cat Rip.
    do
        CST.player_class = "DRUID"
CST.active_class = "DRUID"
        creset()
        eq(CST.DRUID.get_rotation_key(CST), nil, "druid rotation: no form -> nil")
        CST.form_index = 1
        CST.maul_queued = true
        eq(CST.DRUID.get_rotation_key(CST), "RIDE", "druid rotation: queued Maul -> RIDE")
        CST.maul_queued = nil
        cpower_by_type[1] = 100
        cpowercost_impl = function() return { { cost = 10 } } end
        eq(CST.DRUID.get_rotation_key(CST), "Maul",
            "druid rotation: affordable Maul in bear form")
        CST.form_index = 3
        cpower_by_type[3], cpower_by_type[4] = 100, 5
        eq(CST.DRUID.get_rotation_key(CST), "Rip",
            "druid rotation: 5 CP with Rip down on TBC prompts Rip")
        local saved = cst.druid_guide
        cst.druid_guide = nil
        eq(CST.DRUID.get_rotation_key(CST), nil, "druid rotation: missing engine -> nil")
        cst.druid_guide = saved
    end

    -- Shaman: Flame Shock default, Stormstrike when it is up, RIDE on a cast.
    do
        CST.player_class = "SHAMAN"
CST.active_class = "SHAMAN"
        creset()
        eq(CST.SHAMAN.get_rotation_key(CST), "Flame Shock",
            "shaman rotation: a missing Flame Shock prompts Flame Shock")
        CST.weave_fs_duration, CST.weave_fs_expires = 12, cclock + 10
        eq(CST.SHAMAN.get_rotation_key(CST), "Stormstrike",
            "shaman rotation: with Flame Shock up, ready Stormstrike prompts")
        CST.weave_fs_duration, CST.weave_fs_expires = nil, nil
        CST.weave_is_casting = true
        eq(CST.SHAMAN.get_rotation_key(CST), "RIDE",
            "shaman rotation: a cast in flight rides")
        CST.weave_is_casting = nil
        local saved_weave = cst.weave
        cst.weave = nil
        eq(CST.SHAMAN.get_rotation_key(CST), nil, "shaman rotation: missing weave math -> nil")
        cst.weave = saved_weave
        local saved = cst.shaman_guide
        cst.shaman_guide = nil
        eq(CST.SHAMAN.get_rotation_key(CST), nil, "shaman rotation: missing engine -> nil")
        cst.shaman_guide = saved
    end

    -- Rogue: unknown, POOL, then the named builder (the hunter shape: the action's
    -- localized name from the guide's own slot descriptors, hold_text while
    -- holding, nil when idle).
    do
        CST.player_class = "ROGUE"
CST.active_class = "ROGUE"
        creset()
        eq(CST.ROGUE.get_rotation_key(CST), nil, "rogue rotation: unknown inputs -> nil")
        cpower_by_type[3] = 50
        cpower_by_type[4] = 0
        eq(CST.ROGUE.get_rotation_key(CST), "POOL", "rogue rotation: pooling -> POOL")
        cpower_by_type[3] = 90
        -- The builder slot carries its resolved spell id (the client answered it),
        -- so the label reads the localized name, not the action key.
        for i = 1, #CST.ROGUE.guide.slots do
            if CST.ROGUE.guide.slots[i].key == "builder" then
                CST.ROGUE.guide.slots[i].spell_id = 108
            end
        end
        eq(CST.ROGUE.get_rotation_key(CST), "Sinister Strike",
            "rogue rotation: a spend names the localized builder")
        eq(RT2.current_rotation(CST), "Sinister Strike",
            "rogue rotation: the consumer reads the same label")
        eq(RT2.format_value("Sinister Strike", "key", NAMES, DESCS), "Sinister Strike",
            "rogue rotation: an unknown key renders as itself (no consumer change)")
        local saved = cst.rogue_guide
        cst.rogue_guide = nil
        eq(CST.ROGUE.get_rotation_key(CST), nil, "rogue rotation: missing engine -> nil")
        cst.rogue_guide = saved
    end
    CST.player_class = "PALADIN"
CST.active_class = "PALADIN"
end

--=========================================================================================
-- N3: source isolation - a throwing get_rotation_key hides the label, never the driver.
-- First throw prints once, every throw counts in ST.bar_hook_errors (the /st diag
-- counter), the site quarantines after 25. Degrade hides, never stale.
--=========================================================================================
do
    local fake_text = {}
    function fake_text:SetText(t) self.text = t end
    function fake_text:GetStringWidth() return 40 end
    function fake_text:GetStringHeight() return 16 end
    function fake_text:ClearAllPoints() end
    function fake_text:SetPoint() end
    function fake_text:SetJustifyH() end
    function fake_text:SetShadowColor() end
    function fake_text:SetShadowOffset() end
    local fake_frame = { shown = true }
    function fake_frame:IsShown() return self.shown end
    function fake_frame:Hide() self.shown = false end
    function fake_frame:Show() self.shown = true end
    function fake_frame:SetSize() end
    fake_frame.text = fake_text
    local saved_frame, saved_key, saved_dirty = RT.frame, RT.current_key, RT.dirty
    local saved_errors = ST.bar_hook_errors
    ST.bar_hook_errors = nil
    RT.frame = fake_frame
    RT.current_key = nil
    RT.dirty = true
    local fake_self = {
        PALADIN = ST.PALADIN,
        player_class = "PALADIN",
        active_class = "PALADIN",
        db = { profile = { enabled = true } },
        in_combat = false,
        mainhand = { speed = 2.3 },
    }
    function fake_self:get_class_table()
        return {
            class_enabled = true, rotation_label_enabled = true,
            rotation_label_locked = true, rotation_label_visibility_key = "always",
            rotation_label_format = "key",
        }
    end
    function fake_self:get_spell_gcd_duration() return 1.15 end
    local real_key = ST.PALADIN.get_rotation_key
    ST.PALADIN.get_rotation_key = function() error("N3 probe throw") end
    local notices = {}
    fake_self.Print = function(_, msg) notices[#notices + 1] = tostring(msg) end
    local nok, nerr = pcall(RT.update_display, fake_self)
    check(nok, "N3: a throwing source does not break the driver (" .. tostring(nerr) .. ")")
    eq(fake_frame.shown, false, "N3: the label hides on a source throw, never stale")
    eq(fake_self.bar_hook_errors.count, 1, "N3: the throw is counted")
    eq(fake_self.bar_hook_errors.by_site["rotationtext:get_rotation_key"], 1, "N3: the counter names the source")
    eq(#notices, 1, "N3: the first throw prints exactly one chat line")
    for _ = 1, 3 do
        fake_frame.shown = true
        RT.update_display(fake_self)
    end
    eq(fake_self.bar_hook_errors.by_site["rotationtext:get_rotation_key"], 4, "N3: every throw keeps counting")
    eq(#notices, 1, "N3: repeated throws do not spam chat")
    for _ = 5, 25 do
        fake_frame.shown = true
        RT.update_display(fake_self)
    end
    eq(fake_self.bar_hook_errors.by_site["rotationtext:get_rotation_key"], 25, "N3: the site reaches the quarantine threshold")
    eq(fake_self.bar_hook_errors.quarantined["rotationtext:get_rotation_key"], true, "N3: the site is quarantined for the session")
    local counted = fake_self.bar_hook_errors.count
    fake_frame.shown = true
    RT.update_display(fake_self)
    eq(fake_self.bar_hook_errors.count, counted, "N3: a quarantined source is not called again")
    ST.PALADIN.get_rotation_key = real_key
    ST.bar_hook_errors = saved_errors
    RT.frame, RT.current_key, RT.dirty = saved_frame, saved_key, saved_dirty
end

--=========================================================================================
-- 8) F10: the rotation label's source isolation is the shared guard (one implementation)
--=========================================================================================
do
    local rt_src = read("rotationtext.lua")
    check(rt_src:find("st.guard.run", 1, true) ~= nil,
        "the rotation label isolates a throwing source through the shared guard")
    check(rt_src:find("QUARANTINE_THROWS = ", 1, true) == nil,
        "the rotation label keeps no second quarantine threshold")
    check(rt_src:find("errors.by_site", 1, true) == nil,
        "the rotation label keeps no second counter bookkeeping")
    check(rt_src:find('st.guard.label("rotationtext", "Rotation text")', 1, true) ~= nil,
        "the rotation wording stays at the call site")
end

--=========================================================================================
-- NILSWEEP (2026-10-22): the label driver with no class row. No row means no label
-- settings: a live label hides and the tick returns, never a nil read out of
-- layout_changed/apply_settings. The unguarded code throws, so the leg is red-first.
--=========================================================================================
do
    local saved_frame, saved_counter, saved_inert = RT.frame, RT.update_counter, RT.inert
    local shown = true
    local fake_frame = {}
    function fake_frame:IsShown() return shown end
    function fake_frame:Hide() shown = false end
    local fake_self = { db = { profile = { enabled = true } } }
    function fake_self:get_class_table() return nil end
    RT.inert = false
    RT.update_counter = 0
    RT.frame = fake_frame
    local r1ok, r1err = pcall(RT.on_update, fake_self, 2)
    check(r1ok, "NILSWEEP R1 on_update tolerates a missing class row (error: " .. tostring(r1err) .. ")")
    eq(shown, false, "NILSWEEP R1 the label hides without a class row")
    RT.frame, RT.update_counter, RT.inert = saved_frame, saved_counter, saved_inert
end

if failures == 0 then
    print("PASS  rotationtext_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  rotationtext_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
