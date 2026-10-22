-- tests/bars_lazy_state.lua: offline proof for the HU-22 option-on build point.
--
-- The gap: enabling a disabled swing bar in /st options did nothing until reload -
-- no option-set path called the build. The landed contract is ST:ensure_bar (gate:
-- db.enabled AND in-use, idempotent, never destroys) in bars.lua plus
-- ST:bring_up_hand(hand) in main.lua, wired from init_timers and
-- PLAYER_EQUIPMENT_CHANGED. This suite pins the remaining build point: the
-- per-hand Enabled toggle in option_tables.lua (ST.opts_funcs[hand].enabled_setter)
-- writes the value and, on enable only, calls ST:bring_up_hand for that hand
-- (nil-safe when the seam is absent).
--
-- Legs (HUNTER: three hands, offhand enabled-by-default):
--   1. disabled + weaponed offhand is unbuilt after the real init arc (mainhand built).
--   2. option-on at runtime (the REAL enabled_setter) builds exactly once.
--   3. enable (still weaponless, stays unbuilt) + equip (PLAYER_EQUIPMENT_CHANGED)
--      builds with its OnUpdate tick installed and ticking clean.
--   4. disable path is a no-op: writes the db, builds nothing, leaves built hands
--      alone, and stays pcall-clean even with ST.bring_up_hand absent.
--   5. source pins: the Enabled widget routes to enabled_setter, the generic setter
--      never builds, the class master toggle is untouched.
-- Run from the repo root: lua5.1 tests/bars_lazy_state.lua  (any cwd works).

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

--=========================================================================================
-- Minimal frame stubs (same shape as bars_state.lua: record creation, carry scripts)
--=========================================================================================
local function make_region_common(region, sb)
    function region:SetPoint(point, ...) sb.touches = sb.touches + 1; region.point = { point, ... } end
    function region:ClearAllPoints() sb.touches = sb.touches + 1; region.point = nil end
    function region:Hide() sb.touches = sb.touches + 1; region.shown = false end
    function region:Show() sb.touches = sb.touches + 1; region.shown = true end
    function region:IsShown() return region.shown end
    function region:IsVisible() return region.shown end
    function region:SetWidth(w) sb.touches = sb.touches + 1; region.width = w end
    function region:SetHeight(h) sb.touches = sb.touches + 1; region.height = h end
    function region:SetSize(w, h) sb.touches = sb.touches + 1; region.width, region.height = w, h end
    function region:GetWidth() return region.width end
    function region:GetHeight() return region.height end
end

local function make_texture(sb)
    sb.textures_created = sb.textures_created + 1
    sb.touches = sb.touches + 1
    local t = { shown = true }
    make_region_common(t, sb)
    function t:SetTexCoord(...) t.texcoord = { ... } end
    function t:SetTexture(texture) t.texture = texture end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetColorTexture(r, g, b, a) t.color_texture = { r, g, b, a } end
    function t:SetDrawLayer(layer, sub) t.draw_layer = { layer, sub } end
    function t:SetAllPoints() end
    function t:SetAlpha(a) t.alpha = a end
    return t
end

local function make_fontstring(sb)
    sb.fontstrings_created = sb.fontstrings_created + 1
    sb.touches = sb.touches + 1
    local f = { shown = true }
    make_region_common(f, sb)
    function f:SetFont(path, size, flags)
        if path == nil then return false end
        f.font = { path, size, flags }
        return true
    end
    function f:GetFont() return f.font and f.font[1] or nil end
    function f:SetText(text) f.text = text end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:SetJustifyH(justify) f.justify = justify end
    function f:SetShadowColor(r, g, b, a) f.shadow_color = { r, g, b, a } end
    function f:SetShadowOffset(x, y) f.shadow_offset = { x, y } end
    function f:SetAlpha(a) f.alpha = a end
    function f:SetWordWrap(wrap) f.word_wrap = wrap end
    function f:SetFontObject(obj) f.font_object = obj end
    return f
end

local function make_line(sb)
    sb.lines_created = sb.lines_created + 1
    sb.touches = sb.touches + 1
    local l = { shown = true }
    make_region_common(l, sb)
    function l:SetColorTexture(r, g, b, a) l.color_texture = { r, g, b, a } end
    function l:SetThickness(t) l.thickness = t end
    function l:SetStartPoint(point, ...) l.start_point = { point, ... } end
    function l:SetEndPoint(point, ...) l.end_point = { point, ... } end
    function l:SetDrawLayer(layer, sub) l.draw_layer = { layer, sub } end
    return l
end

local function make_frame(sb, frame_type, name, parent, template)
    sb.frames_created = sb.frames_created + 1
    sb.touches = sb.touches + 1
    local f = { kind = "frame", frame_type = frame_type, name = name,
        parent = parent, template = template, shown = true }
    make_region_common(f, sb)
    function f:SetScript(event, fn)
        sb.touches = sb.touches + 1
        f.scripts = f.scripts or {}
        f.scripts[event] = fn
    end
    function f:GetScript(event) return f.scripts and f.scripts[event] or nil end
    function f:RegisterEvent(event) f.events = f.events or {}; f.events[event] = true end
    function f:UnregisterEvent(event) if f.events then f.events[event] = nil end end
    function f:SetFrameStrata(strata) f.strata = strata end
    function f:SetFrameLevel(level) f.frame_level = level end
    function f:GetFrameLevel() return f.frame_level or 1 end
    function f:SetClampedToScreen(clamped) f.clamped = clamped end
    function f:SetMovable(movable) f.movable = movable end
    function f:EnableMouse(enabled) f.mouse = enabled end
    function f:RegisterForDrag(...) f.drag_buttons = { ... } end
    function f:SetAlpha(alpha) f.alpha = alpha end
    function f:SetScale(scale) f.scale = scale end
    function f:GetScale() return f.scale or 1 end
    function f:GetCenter() return f.center_x or 0, f.center_y or 0 end
    function f:GetPoint() return nil end
    function f:GetBottom() return f.bottom or 0 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:CreateTexture() return make_texture(sb) end
    function f:CreateFontString() return make_fontstring(sb) end
    function f:CreateLine() return make_line(sb) end
    function f:SetBackdrop(backdrop) f.backdrop = backdrop end
    function f:ApplyBackdrop() f.backdrop_applied = (f.backdrop_applied or 0) + 1 end
    function f:SetBackdropColor(r, g, b, a) f.backdrop_color = { r, g, b, a } end
    function f:SetBackdropBorderColor(r, g, b, a) f.backdrop_border_color = { r, g, b, a } end
    function f:SetMinMaxValues(min, max) f.min_value, f.max_value = min, max end
    function f:SetValue(value) f.value = value end
    function f:SetStatusBarTexture(texture) f.statusbar_texture = texture end
    function f:SetStatusBarColor(r, g, b, a) f.statusbar_color = { r, g, b, a } end
    function f:SetCooldown(start, duration) f.cooldown = { start, duration } end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers(hidden) f.hide_countdown = hidden end
    function f:SetBlendMode(mode) f.blend_mode = mode end
    return f
end

--=========================================================================================
-- Sandbox builder (HUNTER; the real module chain incl. the option tables)
--=========================================================================================
local function build()
    local sb = {
        clock = 0, project = 11, interface = 38002, engine = "vendored",
        frames_created = 0, textures_created = 0, fontstrings_created = 0,
        lines_created = 0, touches = 0, frames = {}, events = {}, unit_events = {},
        lwin_configs = {}, lwin_restores = {}, lsm_registers = {}, font_requests = {},
        lcg_starts = 0, lcg_stops = 0, sounds = {}, prints = {}, raw_prints = {},
        after = {}, new_timers = {}, lrc_cb = {}, lgc_cb = {}, llm_cb = {}, stl_cb = {},
        auras = {}, cooldowns = {}, known_spells = {}, power = {},
        target_exists = false, in_combat = false, lockdown = false,
        current_spell = nil, mh_speed = 2.6, oh_speed = 1.5, ranged_speed = 2.8,
        swing = {}, spell_haste = 0, is_auto_repeat = false, mounted = false,
        form_index = 0, ldb_calls = {}, hook_calls = {}, st = {},
    }
    local UIParent = make_frame(sb, "Frame", "UIParent", nil, nil)
    sb.UIParent = UIParent

    local LSM = {
        Register = function(_, mediatype, key, path)
            sb.lsm_registers[#sb.lsm_registers + 1] = { media = mediatype, key = key, path = path }
        end,
        Fetch = function(_, mediatype, key)
            sb.font_requests[#sb.font_requests + 1] = { mediatype = mediatype, key = key }
            if mediatype == "font" then return "Fonts\\LSM.ttf" end
            return "Texture\\" .. tostring(key)
        end,
        HashTable = function(_, mediatype) return { ["fake-" .. tostring(mediatype)] = "Fake" } end,
    }
    local LWIN = {
        RegisterConfig = function(frame, db)
            sb.lwin_configs[#sb.lwin_configs + 1] = { frame = frame, db = db }
        end,
        RestorePosition = function(frame) sb.lwin_restores[#sb.lwin_restores + 1] = frame end,
        SavePosition = function() end, OnDragStart = function() end,
        OnDragStop = function() end, OnMouseWheel = function() end,
    }
    local LCG = {
        PixelGlow_Start = function() sb.lcg_starts = sb.lcg_starts + 1 end,
        PixelGlow_Stop = function() sb.lcg_stops = sb.lcg_stops + 1 end,
    }
    local checker = function() return true end
    local LRC = {
        CHECKERS_CHANGED = "CHECKERS_CHANGED", MeleeRange = -1,
        RegisterCallback = function(_, event, fn) sb.lrc_cb[event] = fn end,
        GetHarmMaxChecker = function() return checker end,
        GetHarmMinChecker = function() return checker end,
        GetRange = function() return 0, 8 end,
    }
    local LLM = {
        LATENCY_CHANGED = "LATENCY_CHANGED",
        RegisterCallback = function(_, event, fn) sb.llm_cb[event] = fn end,
    }
    local LGC = {
        GCD_STARTED = "GCD_STARTED", GCD_OVER = "GCD_OVER", GCD_DURATIONS_UPDATED = "GCD_DURATIONS_UPDATED",
        RegisterCallback = function(_, event, fn) sb.lgc_cb[event] = fn end,
    }
    local STL = {
        RegisterCallback = function(_, event, fn) sb.stl_cb[event] = fn end,
        UnregisterCallback = function() end,
        SwingTimerInfo = function(_, hand)
            local t = sb.swing[hand] or { 2.6, sb.clock + 2.6, sb.clock }
            return t[1], t[2], t[3]
        end,
    }
    local broker = {
        NewDataObject = function(_, name, obj) sb.broker_obj = obj; return obj end,
        GetDataObjectByName = function() return sb.broker_obj end,
    }

    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.WOW_PROJECT_ID = sb.project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_CAMELOT = 18
    env.GetTime = function() return sb.clock end
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetBuildInfo = function() return "3.3.5", "12340", "today", sb.interface end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.floor = math.floor
    env.max = math.max
    env.min = math.min
    env.UIParent = UIParent
    env.CreateFrame = function(frame_type, name, parent, template)
        local f = make_frame(sb, frame_type, name, parent, template)
        sb.frames[#sb.frames + 1] = f
        return f
    end
    env.UnitClass = function() return "Hunter", "HUNTER" end
    env.UnitGUID = function() return "Player-1" end
    env.UnitExists = function(unit) return unit == "target" and sb.target_exists or false end
    env.UnitCanAttack = function() return sb.target_exists end
    env.UnitCreatureType = function() return "Humanoid" end
    env.UnitAura = function() return nil end
    env.UnitCastingInfo = function() return nil end
    env.UnitChannelInfo = function() return nil end
    env.UnitSpellHaste = function() return nil end
    env.GetSpellHaste = function() return nil end
    env.UnitPower = function() return nil end
    env.UnitPowerMax = function() return 100 end
    env.UnitPowerType = function() return 0, nil end
    env.UnitHealth = function() return 100 end
    env.UnitHealthMax = function() return 100 end
    env.IsCurrentSpell = function(spell_id) return spell_id == sb.current_spell end
    env.IsSpellInRange = function() return nil end
    env.UnitDistanceSquared = function() return 400, true end
    env.IsAutoRepeatSpell = function() return sb.is_auto_repeat end
    env.IsMounted = function() return sb.mounted end
    env.GetSpellInfo = function() return nil end
    env.GetSpellCooldown = function() return 0, 0, 0, 0 end
    env.GetSpellBaseCooldown = function() return 15000 end
    env.GetSpellPowerCost = function() return { { cost = 15 } } end
    env.IsSpellKnown = function(spell_id) return sb.known_spells[spell_id] == true end
    env.GetActiveTalentGroup = function() return 1 end
    env.GetShapeshiftForm = function() return sb.form_index end
    env.GetTalentInfo = function() return nil, nil, nil, nil, 0 end
    env.GetNetStats = function() return 0, 0, 0, 0 end
    env.InCombatLockdown = function() return sb.lockdown end
    env.PlaySoundFile = function(path, channel)
        sb.sounds[#sb.sounds + 1] = { path = path, channel = channel }
    end
    env.RAID_CLASS_COLORS = { SHAMAN = { r = 0.25, g = 0.5, b = 0.75 } }
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg) sb.prints[#sb.prints + 1] = tostring(msg) end,
    }
    env.print = function(...)
        sb.raw_prints[#sb.raw_prints + 1] = tostring(select(1, ...))
    end
    env.C_Timer = {
        After = function(delay, fn) sb.after[#sb.after + 1] = { delay = delay, cb = fn } end,
        NewTimer = function(delay, fn)
            local timer = { delay = delay, cb = fn }
            function timer:Cancel() self.cancelled = true end
            sb.new_timers[#sb.new_timers + 1] = timer
            return timer
        end,
    }
    env.C_EventUtils = { IsEventValid = function() return true end }
    env.UnitAttackSpeed = function() return sb.mh_speed, sb.oh_speed end
    env.UnitRangedDamage = function() return sb.ranged_speed end

    local ST = {}
    sb.ST = ST
    function ST:RegisterEvent(event) sb.events[event] = (sb.events[event] or 0) + 1 end
    function ST:RegisterUnitEvent(event) sb.unit_events[event] = (sb.unit_events[event] or 0) + 1 end
    function ST:RegisterChatCommand(command, method)
        sb.commands = sb.commands or {}
        sb.commands[command] = method
    end
    function ST:Print(msg) sb.prints[#sb.prints + 1] = tostring(msg) end
    function ST:set_opts() self.opts_table = { args = {} } end

    env.strmatch = string.match
    env.strfind = string.find
    env.strsub = string.sub
    env.strlower = string.lower
    env.format = string.format
    env.GetRealmName = function() return "TestRealm" end
    env.GetCurrentRegion = function() return 1 end
    env.GetLocale = function() return "enUS" end
    env.UnitName = function() return "Tester" end
    env.UnitRace = function() return "Human", "Human" end
    env.UnitFactionGroup = function() return "Alliance", "Alliance" end

    local function load_into_env(path)
        local chunk = assert(loadfile(ROOT .. path))
        setfenv(chunk, env)
        return chunk
    end
    load_into_env("Libs/LibStub/LibStub.lua")("SwedgeTimer", sb.st)
    load_into_env("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")("SwedgeTimer", sb.st)
    load_into_env("Libs/AceDB-3.0/AceDB-3.0.lua")("SwedgeTimer", sb.st)

    local function register(major, minor, surface)
        local lib = env.LibStub:NewLibrary(major, minor)
        assert(lib, "the fixture library " .. major .. " registers")
        for key, value in pairs(surface) do lib[key] = value end
        return lib
    end
    local ace_addon = register("AceAddon-3.0", 1000, {})
    ace_addon.NewAddon = function() return sb.ST end
    ace_addon.GetAddon = function() return sb.ST end
    register("LibSharedMedia-3.0", 1000, LSM)
    register("LibWindow-1.1", 1000, LWIN)
    register("LibCustomGlow-1.0", 1000, LCG)
    register("LibRangeCheck-2.0", 1000, LRC)
    register("LibLatencyMonitor", 1000, LLM)
    register("LibGlobalCooldown", 1000, LGC)
    register("LibDataBroker-1.1", 1000, broker)
    register("AceConfig-3.0", 1000, { RegisterOptionsTable = function() end })
    register("AceConfigDialog-3.0", 1000, { AddToBlizOptions = function() end, Open = function() end })
    register("AceConfigRegistry-3.0", 1000, { NotifyChange = function() end })
    register("AceDBOptions-3.0", 1000, { GetOptionsTable = function() return {} end })
    register("LibClassicSwingTimerAPI", 1000, STL)

    local st = sb.st
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)

    local MODULES = {
        "utils.lua", "guard.lua", "twist.lua", "weave.lua", "druid_energy.lua",
        "hunter_window.lua", "hunter_ui.lua", "main.lua", "bars.lua", "ldb.lua",
        "config_presets.lua", "config.lua",
        "classes/druid.lua", "classes/hunter.lua", "classes/paladin.lua",
        "classes/shaman.lua", "classes/warrior.lua", "classes/rogue.lua",
        "option_table_presets.lua", "option_tables.lua",
    }
    for i = 1, #MODULES do
        local chunk = assert(loadfile(ROOT .. MODULES[i]))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        if not ok then
            print("FAIL  " .. MODULES[i] .. " does not load under the sandbox: " .. tostring(err))
            os.exit(1)
        end
        local class = MODULES[i]:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
        end
    end
    ST.class_activated = true

    sb.env = env
    return { env = env, st = st, ST = ST, sb = sb }
end

-- The real init arc: OnInitialize -> library ready -> init_libs -> init_timers.
local function boot(opts)
    local b = build()
    if opts and opts.pre_init then opts.pre_init(b) end
    b.ST:OnInitialize()
    local lgc = b.sb.lgc_cb["GCD_DURATIONS_UPDATED"]
    assert(lgc, "OnInitialize registered the GCD_DURATIONS_UPDATED callback")
    lgc("GCD_DURATIONS_UPDATED", 1.5, 1.5)
    local llm = b.sb.llm_cb["LATENCY_CHANGED"]
    assert(llm, "OnInitialize registered LLM's LATENCY_CHANGED callback")
    llm("LATENCY_CHANGED", 60, 150)
    local stl = b.sb.stl_cb["SWING_TIMER_INFO_INITIALIZED"]
    assert(stl, "OnInitialize registered the swing-engine ready callback")
    stl()
    local lrc = b.sb.lrc_cb["CHECKERS_CHANGED"]
    assert(lrc, "OnInitialize registered LRC's CHECKERS_CHANGED callback")
    lrc()
    -- The option-set path under test: per-hand case dict + setter functions.
    b.ST:set_opts_case_dict()
    b.ST:set_opts_funcs()
    return b
end

--=========================================================================================
-- 1. disabled + weaponed hand is unbuilt after the real init arc
--=========================================================================================
do
    local b = boot({ pre_init = function(bb)
        -- Offhand stays weaponed (oh_speed 1.5) but its bar ships disabled here.
        bb.ST.HUNTER.defaults.offhand.enabled = false
    end })
    local sb = b.sb
    check(sb.oh_speed == 1.5, "fixture: offhand weapon equipped (speed 1.5)")
    eq(b.ST:get_hand_table("offhand").enabled, false, "offhand db reads disabled")
    check(b.ST:bar_is_built("mainhand"), "enabled mainhand builds at init")
    check(not b.ST:bar_is_built("offhand"), "disabled+weaponed offhand is unbuilt at init")
    check(b.ST:get_anchor_frame("offhand") == nil, "disabled+weaponed offhand has no anchor frame")
    check(not b.ST:ensure_bar("offhand"), "ensure_bar reports false for the gated-off hand")
    local ok_show = pcall(b.ST.show_bar, b.ST, "offhand")
    check(ok_show, "show_bar on the unbuilt hand is a no-op (no error)")
    local ok_hide = pcall(b.ST.hide_bar, b.ST, "offhand")
    check(ok_hide, "hide_bar on the unbuilt hand is a no-op (no error)")
end

--=========================================================================================
-- 2. option-on at runtime builds exactly once (the REAL enabled_setter)
--=========================================================================================
do
    local b = boot({ pre_init = function(bb)
        bb.ST.HUNTER.defaults.offhand.enabled = false
    end })
    local sb, ST = b.sb, b.ST
    check(type(ST.opts_funcs.offhand.enabled_setter) == "function",
        "the offhand setter seam exists after set_opts_funcs")
    local before = sb.frames_created
    ST.opts_funcs.offhand.enabled_setter(nil, { "enabled" }, true)
    eq(ST:get_hand_table("offhand").enabled, true, "option-on writes the db")
    check(ST:bar_is_built("offhand"), "option-on builds the hand")
    eq(sb.frames_created - before, 4, "option-on creates exactly one hand's frames (4)")
    local second = sb.frames_created
    ST.opts_funcs.offhand.enabled_setter(nil, { "enabled" }, true)
    eq(sb.frames_created - second, 0, "option-on again builds nothing (idempotent)")
    local ok, brought = pcall(ST.bring_up_hand, ST, "offhand")
    check(ok and brought, "direct bring_up_hand still reports true for the built hand")
    eq(sb.frames_created - second, 0, "direct bring_up_hand builds nothing twice")
end

--=========================================================================================
-- 3. enable (weaponless, stays unbuilt) + equip builds with a live tick
--=========================================================================================
do
    local b = boot({ pre_init = function(bb)
        bb.ST.HUNTER.defaults.offhand.enabled = false
        bb.sb.oh_speed = 0 -- weaponless at boot: check_weapons latches has_weapon false
    end })
    local sb, ST = b.sb, b.ST
    ST.opts_funcs.offhand.enabled_setter(nil, { "enabled" }, true)
    eq(ST:get_hand_table("offhand").enabled, true, "enabled with no weapon writes the db")
    check(not ST:bar_is_built("offhand"), "enabled but weaponless hand stays unbuilt")
    check(ST.interfaces_are_initialised, "init arc completed (equip path armed)")
    sb.oh_speed = 1.5 -- the equip: an offhand weapon arrives
    ST:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", 17, true)
    check(ST.offhand.has_weapon, "equip flips has_weapon")
    check(ST:bar_is_built("offhand"), "enable + equip builds the hand")
    local bar_frame = ST:get_bar_frame("offhand")
    check(bar_frame ~= nil, "enable + equip yields a bar frame")
    check(bar_frame:GetScript("OnUpdate") ~= nil, "enable + equip installs the tick")
    ST:SWING_TIMER_START("SWING_TIMER_START", 1.5, sb.clock + 1.5, "offhand")
    local script = bar_frame:GetScript("OnUpdate")
    local ok = pcall(script, bar_frame, 0.05)
    check(ok, "the equipped hand's tick runs clean after a swing starts")
end

--=========================================================================================
-- 4. disable path stays a no-op (and the seam is nil-safe)
--=========================================================================================
do
    local b = boot()
    local sb, ST = b.sb, b.ST
    check(ST:bar_is_built("offhand"), "fixture: default offhand builds (enabled + weaponed)")
    local built_frames = sb.frames_created
    -- Spy the seam: disabling must not call it.
    local calls = 0
    local real_bring = ST.bring_up_hand
    ST.bring_up_hand = function(self, hand) calls = calls + 1; return real_bring(self, hand) end
    ST.opts_funcs.offhand.enabled_setter(nil, { "enabled" }, false)
    eq(ST:get_hand_table("offhand").enabled, false, "disable writes the db")
    eq(calls, 0, "disable never calls bring_up_hand")
    eq(sb.frames_created, built_frames, "disable creates no frames")
    check(ST:bar_is_built("offhand"), "disable does not tear a built hand down")
    check(ST:bar_is_built("mainhand"), "disable leaves the other hands alone")
    ST.bring_up_hand = real_bring
    -- Nil-safe: the seam absent (suites that stub main.lua) stays pcall-clean.
    ST.bring_up_hand = nil
    local ok = pcall(ST.opts_funcs.offhand.enabled_setter, nil, { "enabled" }, true)
    check(ok, "option-on with no bring_up_hand is pcall-clean")
    eq(ST:get_hand_table("offhand").enabled, true, "option-on with no seam still writes the db")
end

--=========================================================================================
-- 5. source pins: widget routing, generic setter purity, class master untouched
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "option_tables.lua", "r"))
    local src = f:read("*a")
    f:close()
    local widget = src:match("(%s+enabled = {\n%s+type = \"toggle\",\n%s+order = 0%.01,\n%s+name = \"Enabled\",.-\n%s+},)")
    check(widget ~= nil, "the Enabled widget block is found in option_tables.lua")
    check(widget ~= nil and widget:find('set = "enabled_setter"', 1, true) ~= nil,
        "the Enabled widget routes to enabled_setter")
    check(widget ~= nil and widget:find('get = "getter"', 1, true) ~= nil,
        "the Enabled widget keeps the generic getter")
    -- The generic setter must not build (every other widget shares it).
    local generic = src:match("ST%.opts_funcs%[hand%]%.setter = function%(.-%)\n(.-)\n        end")
    check(generic ~= nil, "the generic setter block is found")
    check(generic ~= nil and generic:find("bring_up_hand", 1, true) == nil,
        "the generic setter never builds")
    -- The class master toggle (option_tables.lua:131) is not the per-hand switch.
    check(src:find("db.class_enabled = value", 1, true) ~= nil,
        "the class master toggle still writes class_enabled inline (untouched)")
end

print("checks: " .. checks .. ", failures: " .. failures)
if failures > 0 then os.exit(1) end
print("PASS bars_lazy_state (" .. checks .. " checks)")
