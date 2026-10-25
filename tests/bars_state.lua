-- tests/bars_state.lua: offline execution tests for the swing-timer bar module (bars.lua),
-- its per-frame driver (the real main.lua init/OnUpdate path) and the six class dispatch
-- hooks (classes/paladin.lua, warrior.lua, hunter.lua (+ hunter_ui.lua), shaman.lua,
-- druid.lua, rogue.lua) in a sandbox.
--
-- Why this exists: bars.lua was the last large module with zero execution coverage - and
-- it hid two real defects the first execution found: on_latency_update/on_gcd_length_change
-- iterated a hardcoded three-hand list and crashed post_init on every single-hand class
-- (PALADIN, DRUID), and a second ST:convert_color definition (loaded after main.lua's)
-- silently turned every 0-255 array colour into 0,0,0,0. Both are fixed and pinned below.
-- This suite loads the REAL modules over the real compat.lua + utils.lua in the TOC order
-- (pure helpers, then hunter_window/hunter_ui, then main.lua, bars.lua, ldb.lua,
-- config_presets/config, then the six class modules), runs the real OnInitialize ->
-- library-ready -> init_libs -> init_timers construction arc, and drives the OnUpdate
-- script bars.lua registers on each bar frame exactly as the client does.
--
-- Covered here:
--   1. Construction for all six classes (hand sets from main.lua's class_hands): the
--      documented frames/regions per hand with exact create counts, the class widget sets
--      (paladin twist band, warrior tracker set, hunter cast bar set, druid energy column,
--      shaman weave/tracker widgets, rogue tick spark/pool wash/window/swap/poison) and
--      the per-class default bar colour.
--   2. The OnUpdate state machine: fill fraction + texcoord over time, the bar texts and
--      their hide-inactive rules, the GCD underlay branches, the swing-anchored and
--      endofswing GCD markers (wrap/clamp), the deadzone width from latency, the class's
--      own hand set in on_latency_update/on_gcd_length_change, pause, swing-ended/is_full
--      states, show/hide and out-of-range dim through the real visibility passes, and the
--      mainhand-only LibDataBroker feed. Section 2b adds the degraded states: the
--      engine-dead render (H1) and the per-tick hook/zone isolation (H2).
--   3. The per-frame class dispatch (on_bar_update) must-show/must-not states: paladin
--      twist band alphas (marker/window/armed/attempt/success/impossible) driven by the
--      real CLEU chain; warrior Overpower flash pulse + Shield Block + Slam + debuff
--      bars; hunter cast bar live face/latency slice/window face/clip tint/range helper/
--      Rapid Fire/aspect icon/melee re-anchor; druid energy tick thresholds + form label
--      + debuff bars; shaman breakpoint marker + spark travel + offhand mirror + Windfury
--      ICD + Flame Shock + badges + shield charges.
--   4. The spellcast lifecycle dispatch (UNIT_SPELLCAST_* -> class on_spellcast_event)
--      for shaman (start/stop/succeeded, unrelated and non-player events inert) and
--      warrior (Slam start/stop, option gate), plus the hunter queue colours.
--   5. Pre-init safety: only AceDB's frame exists before OnInitialize, the early
--      GCD/latency reports touch no frame and are init-guarded, the paladin's own anchor
--      guard is inert pre-construction, and a re-entrant init_libs re-runs nothing.
--   6. Family gates: the CLEU registration matrix (every classic-line class yes -
--      G2: the neutral extra-attack/parry pre-pass is class-independent - Mainline-code
--      none), the Retail inert-stand-in notice + hidden twist band, the Forever
--      (Mainline-code) builds that must keep the twist band and weave marker, and
--      compat's interface-version fallback (16001 -> FOREVER, 11509 -> ERA).
--
-- Sandbox discipline (like tests/main_init_state.lua / practice_ui_state.lua): the
-- sandbox owns its global table (env._G = env), so compat.lua's rawget(_G, ...) legacy
-- probes read the stubs directly and nothing is mirrored onto the host process. The
-- other modules load under setfenv. Frame/texture/fontstring/line stubs RECORD every call so
-- the assertions can bite; the clock behind GetTime()/GetTimePreciseSec() and
-- st.api.get_time() is scripted; C_Timer callbacks are captured and fired by hand. Only
-- WoW frame APIs, the libraries and media are stubbed - every addon module under test is
-- the real file. max/min are provided as the WoW client's own globals.
-- Run from the repo root: lua5.1 tests/bars_state.lua  (any cwd works).

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
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > (tol or 1e-9) then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end
-- Compares a recorded {r, g, b, a} vertex/colour against a 0-255 db table through the
-- same convert_color scaling main.lua applies.
local function colour_eq(vertex, db_table, label)
    checks = checks + 1
    if type(vertex) ~= "table" then
        failures = failures + 1
        print("FAIL  " .. label .. "  (no colour was applied)")
        return
    end
    near(vertex[1], db_table[1] / 255, 1e-9, label .. " (red)")
    near(vertex[2], db_table[2] / 255, 1e-9, label .. " (green)")
    near(vertex[3], db_table[3] / 255, 1e-9, label .. " (blue)")
    near(vertex[4], db_table[4], 1e-9, label .. " (alpha)")
end

--=========================================================================================
-- Fixtures shared by every sandbox (the env stubs close over these tables)
--=========================================================================================
-- Spell data the client answers with. Only the ids the five classes' bar-facing features
-- resolve: shaman Lightning Bolt (the weave catalogue), hunter Auto Shot / Steady Shot,
-- warrior Slam / Shield Block / Overpower / Heroic Strike, paladin Exorcism base CD.
local SPELL_INFO = {
    [403] = { name = "Lightning Bolt", icon = "icon_lb", cast_ms = 2500 },
    [331] = { name = "Healing Wave", icon = "icon_hw", cast_ms = 3000 },
    [75] = { name = "Auto Shot", icon = "icon_autoshot", cast_ms = 0 },
    [56641] = { name = "Steady Shot", icon = "icon_steady", cast_ms = 1500 },
    [2973] = { name = "Raptor Strike", icon = "icon_raptor", cast_ms = 0 },
    [47475] = { name = "Slam", icon = "icon_slam", cast_ms = 1500 },
    [2565] = { name = "Shield Block", icon = "icon_shieldblock", cast_ms = 0 },
    [7384] = { name = "Overpower", icon = "icon_op", cast_ms = 0 },
    [78] = { name = "Heroic Strike", icon = "icon_hs", cast_ms = 0 },
    [879] = { name = "Exorcism", icon = "icon_exo", cast_ms = 0 },
    -- Seal of Command / Seal of Blood: the paladin seal-icon slots resolve their
    -- textures from the client's spell data (api.GetSpellInfo, third return).
    [20375] = { name = "Seal of Command", icon = "icon_soc", cast_ms = 0 },
    [31892] = { name = "Seal of Blood", icon = "icon_sob", cast_ms = 0 },
    [6807] = { name = "Maul", icon = "icon_maul", cast_ms = 0 },
    -- Multi-Shot ranks: the hunter cast-grace matcher resolves the client's own names for
    -- these ids; a healthy client always answers for its ranks (an unanswered client is
    -- the cold-cache case tests/hunter_state.lua's module notes, not this fixture's).
    [2643] = { name = "Multi-Shot", icon = "icon_multishot", cast_ms = 1500 },
    [27021] = { name = "Multi-Shot", icon = "icon_multishot", cast_ms = 1500 },
    -- Aspect of the Hawk: the hunter aspect-icon path resolves the icon texture from the
    -- client's spell data (hunter_ui.lua build), so the fixture must answer for one of
    -- the aspect ids for the icon to have a texture to show.
    [13165] = { name = "Aspect of the Hawk", icon = "icon_hawk", cast_ms = 0 },
}

--=========================================================================================
-- Frame / region stubs (record every call; sb.touches counts every mutation)
--=========================================================================================
-- The fixture is deliberately thin on frames: the client IS the frame API, so the stubs
-- only need the members the real modules under test call.
local function make_region_common(region, sb, kind)
    function region:SetPoint(point, ...)
        sb.touches = sb.touches + 1
        region.point = { point, ... }
    end
    function region:ClearAllPoints()
        sb.touches = sb.touches + 1
        region.point = nil
    end
    function region:Hide()
        sb.touches = sb.touches + 1
        region.shown = false
    end
    function region:Show()
        sb.touches = sb.touches + 1
        region.shown = true
    end
    function region:IsShown()
        return region.shown
    end
    function region:IsVisible()
        return region.shown
    end
    function region:SetWidth(w)
        sb.touches = sb.touches + 1
        region.width = w
    end
    function region:SetHeight(h)
        sb.touches = sb.touches + 1
        region.height = h
    end
    function region:SetSize(w, h)
        sb.touches = sb.touches + 1
        region.width, region.height = w, h
    end
    function region:GetWidth()
        return region.width
    end
    function region:GetHeight()
        return region.height
    end
    region.kind = kind
end

local function make_texture(sb)
    sb.textures_created = sb.textures_created + 1
    sb.touches = sb.touches + 1
    local t = { shown = true }
    make_region_common(t, sb, "texture")
    function t:SetTexCoord(...) t.texcoord = { ... } end
    function t:SetTexture(texture) t.texture = texture end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetColorTexture(r, g, b, a) t.color_texture = { r, g, b, a } end
    function t:SetDrawLayer(layer, sub) t.draw_layer = { layer, sub } end
    function t:SetAllPoints() end
    function t:SetAlpha(a) t.alpha = a end
    function t:SetBlendMode(mode) t.blend_mode = mode end
    return t
end

local function make_fontstring(sb)
    sb.fontstrings_created = sb.fontstrings_created + 1
    sb.touches = sb.touches + 1
    local f = { shown = true }
    make_region_common(f, sb, "fontstring")
    -- SoD-faithful: a nil font path latches nothing (the client refuses it), so a
    -- text that is written with no font on the FontString is the only way to get a
    -- blank label. GetFont answers what is actually latched.
    function f:SetFont(path, size, flags)
        if path == nil then
            return false
        end
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
    make_region_common(l, sb, "line")
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
    local f = {
        kind = "frame", frame_type = frame_type, name = name,
        parent = parent, template = template, shown = true,
    }
    make_region_common(f, sb, "frame")
    function f:SetScript(event, fn)
        sb.touches = sb.touches + 1
        f.scripts = f.scripts or {}
        f.scripts[event] = fn
    end
    function f:GetScript(event)
        return f.scripts and f.scripts[event] or nil
    end
    function f:RegisterEvent(event)
        f.events = f.events or {}
        f.events[event] = true
    end
    function f:UnregisterEvent(event)
        if f.events then f.events[event] = nil end
    end
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
    -- StatusBar surface (the hunter Rapid Fire bar).
    function f:SetMinMaxValues(min, max) f.min_value, f.max_value = min, max end
    function f:SetValue(value) f.value = value end
    function f:SetStatusBarTexture(texture) f.statusbar_texture = texture end
    function f:SetStatusBarColor(r, g, b, a) f.statusbar_color = { r, g, b, a } end
    -- Cooldown surface (plain frames in WoW carry it; the HUD module's tests use it too).
    function f:SetCooldown(start, duration) f.cooldown = { start, duration } end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers(hidden) f.hide_countdown = hidden end
    function f:SetBlendMode(mode) f.blend_mode = mode end
    return f
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- One throwaway client per call. opts:
--   class      the UnitClass class filename (uppercase, e.g. "PALADIN")
--   project    WOW_PROJECT_ID (default 11 = Wrath)
--   interface  GetBuildInfo's toc (default 38002)
--   engine     "vendored" (default) | "source" (a Forever-style PLAYER_SWING engine) |
--              "absent" (no engine: the inert stand-in, e.g. Retail)
local function build(opts)
    opts = opts or {}
    -- opts.project: the WOW_PROJECT_ID constant. false means "no constant at all", which
    -- exercises compat.lua's GetBuildInfo interface-version fallback.
    local project = opts.project
    if project == nil then
        project = 11
    elseif project == false then
        project = nil
    end
    local sb = {
        clock = 0,
        project = project,
        interface = opts.interface or 38002,
        engine = opts.engine or "vendored",
        frames_created = 0,
        textures_created = 0,
        fontstrings_created = 0,
        lines_created = 0,
        touches = 0,
        frames = {},
        events = {},
        unit_events = {},
        lwin_configs = {},
        lwin_restores = {},
        lsm_registers = {},
        font_requests = {},
        lcg_starts = 0,
        lcg_stops = 0,
        sounds = {},
        prints = {},
        -- Every call that reaches the CLIENT's global print (not the addon's chat path)
        -- lands here. The sandbox has no global print of its own, so this spy is what
        -- turns "the module printed through the global" into an assertion instead of a
        -- crash - see section 7.
        raw_prints = {},
        after = {},
        new_timers = {},
        lrc_cb = {},
        lgc_cb = {},
        llm_cb = {},
        stl_cb = {},
        auras = {},
        cooldowns = {},
        -- Lightning Bolt is the one weave-catalogue spell the fixture's client knows:
        -- resolve_family_spell drops ranks api.is_spell_known rejects, so without it the
        -- shaman catalogue would never resolve and every weave visual would stay inert.
        known_spells = { [403] = true },
        power = {},
        power_type = nil,
        power_token = nil,
        power_reads = 0,
        aura_reads = 0,
        cast = nil,
        channel = nil,
        target_exists = false,
        in_combat = false,
        lockdown = false,
        current_spell = nil,
        mh_speed = 2.6,
        oh_speed = 1.5,
        ranged_speed = 2.8,
        swing = {},
        spell_haste = 0,
        range_reads = 0,
        is_spell_in_range = nil,
        target_yards = 20, -- exact target distance (the sweet band is 5 < yd <= 10)
        is_auto_repeat = false,
        mounted = false,
        form_index = 0,
        ldb_calls = {},
        broker_obj = nil,
        hook_calls = {},
        st = {},
        ST = nil,
        env = nil,
    }

    -- Frames the fixture hands to the modules as named anchors behave like the client's:
    -- the module may set width/height/points and read them back.
    local UIParent = make_frame(sb, "Frame", "UIParent", nil, nil)
    sb.UIParent = UIParent

    -- Library stubs - registered into the REAL vendored LibStub below, so the modules'
    -- LibStub lookups go through the real library machinery. The fake surfaces carry only
    -- what the modules call; the vendored LibStub / CallbackHandler / AceDB themselves are
    -- the real shipped files (AceDB is what expands ST.defaults into the profile tables).
    local LSM = {
        Register = function(_, mediatype, key, path)
            sb.lsm_registers[#sb.lsm_registers + 1] = { media = mediatype, key = key, path = path }
        end,
        -- Media Fetch records the request and returns a stable path per mediatype so the
        -- text font assertions have a real value to compare.
        -- A statusbar fetch can legitimately come back NIL (the key is not in the
        -- registry - a registration that failed on this client - or the registered
        -- path is empty), so the fixture can model it: opts.lsm_missing_key makes
        -- that one key fetch nil, opts.lsm_missing_all makes EVERY statusbar fetch
        -- return nil.
        Fetch = function(_, mediatype, key)
            sb.font_requests[#sb.font_requests + 1] = { mediatype = mediatype, key = key }
            if mediatype == "font" then
                -- A font key that no longer resolves (the font lives in another
                -- addon's LSM registration) must degrade to a font that exists,
                -- never to a nil path.
                if opts.lsm_missing_font then
                    return nil
                end
                return "Fonts\\LSM.ttf"
            end
            if mediatype == "statusbar" then
                if opts.lsm_missing_all then
                    return nil
                end
                if opts.lsm_missing_key and key == opts.lsm_missing_key then
                    return nil
                end
            end
            return "Texture\\" .. tostring(key)
        end,
        HashTable = function(_, mediatype)
            return { ["fake-" .. tostring(mediatype)] = "Fake " .. tostring(mediatype) }
        end,
    }
    -- LibWindow-1.1's real signatures are dot-style: RegisterConfig(frame, storage,
    -- names) and RestorePosition(frame) (Libs/LibWindow-1.1/LibWindow-1.1.lua:89, 171),
    -- and every call site in the addon follows that shape.
    local LWIN = {
        RegisterConfig = function(frame, db)
            sb.lwin_configs[#sb.lwin_configs + 1] = { frame = frame, db = db }
        end,
        RestorePosition = function(frame)
            sb.lwin_restores[#sb.lwin_restores + 1] = frame
        end,
        SavePosition = function() end,
        OnDragStart = function() end,
        OnDragStop = function() end,
        OnMouseWheel = function() end,
    }
    local LCG = {
        PixelGlow_Start = function(frame, color, n, freq, length, th, x, y, border, key)
            sb.lcg_starts = sb.lcg_starts + 1
            sb.lcg_last_start = { frame = frame, color = color, n = n, freq = freq,
                length = length, th = th, key = key }
        end,
        PixelGlow_Stop = function(frame, key)
            sb.lcg_stops = sb.lcg_stops + 1
            sb.lcg_last_stop = { frame = frame, key = key }
        end,
    }
    local checker = function() return true end
    local LRC = {
        CHECKERS_CHANGED = "CHECKERS_CHANGED",
        MeleeRange = -1,
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
        GCD_STARTED = "GCD_STARTED",
        GCD_OVER = "GCD_OVER",
        GCD_DURATIONS_UPDATED = "GCD_DURATIONS_UPDATED",
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
    local source_engine = {
        available = true,
        RegisterCallback = function(_, event, fn) sb.stl_cb[event] = fn end,
        UnregisterCallback = function() end,
        SwingTimerInfo = function(_, hand)
            -- The Forever swing source reports the same shape as the vendored library.
            local t = sb.swing[hand] or { 3.4, sb.clock + 3.4, sb.clock }
            return t[1], t[2], t[3]
        end,
    }
    local broker = {
        NewDataObject = function(_, name, obj)
            sb.broker_name = name
            sb.broker_obj = obj
            return obj
        end,
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
    -- max/min are WoW client Lua globals (not stock Lua 5.1): bars.lua and paladin.lua
    -- call them bare exactly as the client provides them.
    env.max = math.max
    env.min = math.min
    env.UIParent = UIParent
    env.CreateFrame = function(frame_type, name, parent, template)
        local f = make_frame(sb, frame_type, name, parent, template)
        sb.frames[#sb.frames + 1] = f
        return f
    end
    env.UnitClass = function() return opts.class or "PALADIN", opts.class or "PALADIN" end
    env.UnitGUID = function() return "Player-1" end
    env.UnitExists = function(unit) return unit == "target" and sb.target_exists or false end
    env.UnitCanAttack = function() return sb.target_exists end
    env.UnitCreatureType = function() return "Humanoid" end
    env.UnitAura = function(unit, index)
        sb.aura_reads = sb.aura_reads + 1
        local list = sb.auras[unit]
        if not list then return nil end
        local entry = list[index]
        if not entry then return nil end
        return entry.name, entry.icon or "aura_icon", entry.count, entry.dispel,
            entry.duration, entry.expiration, entry.source, entry.stealable, entry.np, entry.spell_id
    end
    env.UnitCastingInfo = function()
        local c = sb.cast
        if not c then return nil end
        return c.name, "cast_text", c.icon or "cast_icon", c.start_ms, c.end_ms,
            false, 1, false, c.spell_id
    end
    env.UnitChannelInfo = function()
        local c = sb.channel
        if not c then return nil end
        return c.name, "channel_text", c.icon or "channel_icon", c.start_ms, c.end_ms,
            false, false, c.spell_id
    end
    env.UnitSpellHaste = function()
        if sb.spell_haste == 0 then return nil end
        return sb.spell_haste
    end
    env.GetSpellHaste = function() return nil end
    env.UnitPower = function(_, power_type)
        sb.power_reads = sb.power_reads + 1
        if power_type ~= nil then return sb.power[power_type] end
        return sb.power.default
    end
    env.UnitPowerMax = function() return sb.power.max end
    env.UnitPowerType = function()
        return sb.power_type, sb.power_token
    end
    env.UnitHealth = function() return 100 end
    env.UnitHealthMax = function() return 100 end
    env.IsCurrentSpell = function(spell_id) return spell_id == sb.current_spell end
    env.IsSpellInRange = function(spell, unit)
        sb.range_reads = sb.range_reads + 1
        if sb.is_spell_in_range ~= nil then
            return sb.is_spell_in_range(spell, unit)
        end
        return nil
    end
    -- Exact target distance (R3, 2026-10-21): the hunter sweet spot is a yards band.
    -- nil yards = unknown, so every probe is answerless and the strip hides.
    env.UnitDistanceSquared = function(unit)
        if sb.target_yards == nil then
            return 0, false
        end
        return sb.target_yards * sb.target_yards, true
    end
    env.IsAutoRepeatSpell = function() return sb.is_auto_repeat end
    env.IsMounted = function() return sb.mounted end
    env.GetSpellInfo = function(spell_id)
        local info = SPELL_INFO[spell_id]
        if not info then return nil end
        return info.name, "Rank 1", info.icon, info.cast_ms, 0, 0, spell_id
    end
    env.GetSpellCooldown = function(spell)
        local cd = sb.cooldowns[spell]
        if not cd then return 0, 0, 0, 0 end
        return cd.start or 0, cd.duration or 0, cd.enabled == false and 0 or 1, 1
    end
    env.GetSpellBaseCooldown = function() return 15000 end
    env.GetSpellPowerCost = function()
        return { { cost = sb.rage_cost or 15 } }
    end
    env.IsSpellKnown = function(spell_id) return sb.known_spells[spell_id] == true end
    env.GetActiveTalentGroup = function() return 1 end
    env.GetShapeshiftForm = function() return sb.form_index end
    env.GetTalentInfo = function() return nil, nil, nil, nil, 0 end
    env.GetNetStats = function() return 0, 0, 0, 0 end
    env.InCombatLockdown = function() return sb.lockdown end
    env.PlaySoundFile = function(path, channel)
        sb.sounds[#sb.sounds + 1] = { path = path, channel = channel }
    end
    env.RAID_CLASS_COLORS = {
        SHAMAN = { r = 0.25, g = 0.5, b = 0.75 },
        PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    }
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg) sb.prints[#sb.prints + 1] = tostring(msg) end,
    }
    -- The client's global print, spied. The addon's chat path is st.utils.print_msg
    -- (utils.lua -> DEFAULT_CHAT_FRAME:AddMessage), so a module that reaches the global
    -- instead shows up here - and never as an error.
    env.print = function(...)
        local first = select(1, ...)
        sb.raw_prints[#sb.raw_prints + 1] = tostring(first)
    end
    env.C_Timer = {
        After = function(delay, fn)
            sb.after[#sb.after + 1] = { delay = delay, cb = fn }
        end,
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

    -- The addon object. main.lua creates it through NewAddon and seeds the class tables,
    -- the hand containers and class_hands; the fixture only provides the Ace mixin surface
    -- main.lua calls (AceConsole Print, AceEvent RegisterEvent, AceConsole commands).
    local ST = {}
    sb.ST = ST
    function ST:RegisterEvent(event) sb.events[event] = (sb.events[event] or 0) + 1 end
    function ST:RegisterUnitEvent(event) sb.unit_events[event] = (sb.unit_events[event] or 0) + 1 end
    function ST:RegisterChatCommand(command, method) sb.commands = sb.commands or {}; sb.commands[command] = method end
    function ST:Print(msg) sb.prints[#sb.prints + 1] = tostring(msg) end
    -- main.lua's OnInitialize calls set_opts(); the options lane builds it (option_tables)
    -- and is covered by tests/options_load_state.lua, so the fixture provides the surface.
    function ST:set_opts() self.opts_table = { args = {} } end

    -- The real vendored LibStub + CallbackHandler + AceDB, loaded into the sandbox exactly
    -- as the TOC loads them. AceDB is what expands ST.defaults into the real profile tables
    -- (its '**' smart-defaults expansion is the behaviour bars.lua's construction reads), so
    -- the fixture does not hand-write any default. Loading a library chunk needs a few
    -- clientside globals stock Lua lacks (WoW's string shortcuts and the realm/race reads).
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

    -- Register the fixture's library surfaces through the real LibStub, so every module's
    -- LibStub lookup resolves through the shipped versioning machinery. The swing engine is
    -- only registered when the client profile has one (main.lua fetches it silently).
    local function register(major, minor, surface)
        local lib = env.LibStub:NewLibrary(major, minor)
        assert(lib, "the fixture library " .. major .. " registers")
        for key, value in pairs(surface) do
            lib[key] = value
        end
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
    if sb.engine == "vendored" then
        register("LibClassicSwingTimerAPI", 1000, STL)
    end

    -- compat.lua reads several legacy globals through rawget(_G, ...). The sandbox owns its
    -- global table (env._G = env), so those raw reads hit the stubs directly: nothing is
    -- mirrored onto the host process and no host global can leak in.
    local st = sb.st
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)

    -- The real TOC order, minus the modules this suite does not exercise (the option
    -- tables, HUD, practice UI, nextaction_ui and design modules): pure helpers first,
    -- then hunter_window/hunter_ui, main.lua (the construction driver), bars.lua (the
    -- module under test), ldb.lua (driven from bars.lua), the real config presets/defaults,
    -- then the six class modules.
    if sb.engine == "source" then
        st.swing_source = source_engine
    end

    local MODULES = {
        "utils.lua",
        "guard.lua",
        "twist.lua",
        "weave.lua",
        "druid_energy.lua",
        "hunter_window.lua",
        "hunter_ui.lua",
        "main.lua",
        "bars.lua",
        "ldb.lua",
        "config_presets.lua",
        "config.lua",
        "classes/druid.lua",
        "classes/hunter.lua",
        "classes/paladin.lua",
        "classes/shaman.lua",
        "classes/warrior.lua",
        "classes/rogue.lua",
    }
    for i = 1, #MODULES do
        local chunk = assert(loadfile(ROOT .. MODULES[i]))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        if not ok then
            print("FAIL  " .. MODULES[i] .. " does not load under the sandbox: " .. tostring(err))
            os.exit(1)
        end
        -- Class files register their body as a loader (operator order 2026-10-21:
        -- only the selected class executes). This sandbox activates every class it
        -- loads, as the shipped init does for the selected one.
        local class = MODULES[i]:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
        end
    end
    -- The fixture has already run every class loader above, exactly as the pre-loader
    -- files ran their bodies at load. main.lua's init calls activate_class() once, so
    -- mark activation done: a second run would replace the hooked class functions.
    ST.class_activated = true

    -- Instrument the two boundaries bars.lua drives, keeping the real code behind them:
    -- the class dispatch hook and the LibDataBroker feed.
    for _, class_key in ipairs({ "PALADIN", "WARRIOR", "HUNTER", "DRUID", "SHAMAN", "ROGUE" }) do
        local real_hook = ST[class_key].on_bar_update
        if real_hook then
            ST[class_key].on_bar_update = function(self, hand)
                sb.hook_calls[class_key] = (sb.hook_calls[class_key] or 0) + 1
                return real_hook(self, hand)
            end
        end
    end
    local real_ldb_update = st.ldb.update
    st.ldb.update = function(self, hand)
        sb.ldb_calls[hand] = (sb.ldb_calls[hand] or 0) + 1
        return real_ldb_update(self, hand)
    end

    sb.env = env
    return { env = env, st = st, ST = ST, sb = sb }
end

--=========================================================================================
-- Boot: the real OnInitialize -> library reports -> init_libs -> init_timers arc
--=========================================================================================
-- Models PLAYER_LOGIN's first LibGlobalCooldown report and a first latency reading (the
-- real libraries fire both), then the swing engine's and LibRangeCheck's ready callbacks.
local function boot(opts)
    local b = build(opts)
    local sb = b.sb
    b.ST:OnInitialize()
    local lgc = sb.lgc_cb["GCD_DURATIONS_UPDATED"]
    assert(lgc, "OnInitialize registered the GCD_DURATIONS_UPDATED callback")
    lgc("GCD_DURATIONS_UPDATED", 1.5, 1.5)
    local llm = sb.llm_cb["LATENCY_CHANGED"]
    assert(llm, "OnInitialize registered LLM's LATENCY_CHANGED callback")
    llm("LATENCY_CHANGED", 60, 150)
    if sb.engine == "vendored" or sb.engine == "source" then
        local stl = sb.stl_cb["SWING_TIMER_INFO_INITIALIZED"]
        assert(stl, "OnInitialize registered the swing-engine ready callback")
        stl()
    end
    local lrc = sb.lrc_cb["CHECKERS_CHANGED"]
    assert(lrc, "OnInitialize registered LRC's CHECKERS_CHANGED callback")
    lrc()
    return b
end

-- Drives the OnUpdate script bars.lua registered on the hand's bar frame, exactly as the
-- client does: script(frame, elapsed).
local function tick(b, hand, elapsed)
    local frame = b.ST:get_bar_frame(hand)
    local script = frame and frame:GetScript("OnUpdate")
    assert(script, "an OnUpdate script is registered for " .. tostring(hand))
    script(frame, elapsed or 0.05)
end

-- Starts a swing on a hand through the real SWING_TIMER_START handler (the engine's
-- documented entry): sets speed/ends_at/start, clears is_full and runs on_bar_active.
local function start_swing(b, hand, speed, remaining)
    b.ST:SWING_TIMER_START("SWING_TIMER_START", speed, b.sb.clock + remaining, hand)
end

local function visuals(b, hand)
    local state = b.ST[hand]
    assert(state and state.anchor_frame, "hand " .. tostring(hand) .. " is constructed")
    return state.anchor_frame.bar_frame.visuals_frame
end

local function hand_db(b, hand)
    return b.ST:get_hand_table(hand)
end

local function class_db(b)
    return b.ST:get_class_table()
end

-- Compares a recorded vertex/colour tuple against expected components (1e-9). Nil
-- components are skipped, so a caller can pin a subset. One check per call.
local function vertex_eq(got, want, label)
    checks = checks + 1
    if type(got) ~= "table" then
        failures = failures + 1
        print("FAIL  " .. label .. "  (no colour was applied)")
        return
    end
    for i = 1, 4 do
        if want[i] ~= nil and (type(got[i]) ~= "number" or math.abs(got[i] - want[i]) > 1e-9) then
            failures = failures + 1
            print("FAIL  " .. label .. "  (component " .. i .. " got " .. tostring(got[i])
                .. ", want " .. tostring(want[i]) .. ")")
            return
        end
    end
end

-- A dB colour table (0-255 RGB + 0-1 alpha) as the converted vertex tuple.
local function db_color(db_table)
    return { db_table[1] / 255, db_table[2] / 255, db_table[3] / 255, db_table[4] }
end

-- The frame created under a given name, or nil.
local function frame_named(sb, name)
    for i = 1, #sb.frames do
        if sb.frames[i].name == name then
            return sb.frames[i]
        end
    end
    return nil
end

-- Installs a player aura list (the fixture's UnitAura shape) and fires the real
-- UNIT_AURA handler so the class module refreshes through its production path.
local function set_player_auras(b, list)
    b.sb.auras.player = list
    b.ST:UNIT_AURA("UNIT_AURA", "player", false, nil)
end

-- Installs a target aura list (no event: the class hooks scan the target per frame).
local function set_target_auras(b, list)
    b.sb.auras.target = list
end

--=========================================================================================
-- 1) Construction for all six classes (the real init arc)
--=========================================================================================
-- Hand sets mirror main.lua's class_hands. Per hand bars.lua creates exactly 4 frames
-- (anchor, hiding anchor, bar frame, visuals frame), 3 textures (bar, gcd_bar, deadzone),
-- 3 fontstrings (left/center/right) and 2 lines (gcd markers). Two more frames exist in
-- every sandbox before any addon code runs: the fixture's UIParent and the vendored
-- AceDB-3.0's own frame (Libs/AceDB-3.0/AceDB-3.0.lua creates one at load). The class
-- modules add their own widgets on top; the expected extras are asserted per class.
local BOOT_FRAMES = 2  -- UIParent + AceDB's frame
local CLASSES = {
    { key = "PALADIN", hands = { "mainhand" },
      -- twist band (1 texture) + twist success text (1 fontstring) + hit-rate
      -- badge (1 fontstring) + judgement marker line (1 line) + reseal
      -- marker (1 texture, P1) + seal icons
      -- (2 icon textures, 2 timer texts, 1 container frame + 2 cooldown frames
      -- + 2 timer text frames) + JotC mini-bar (1 icon texture, 1 timer text,
      -- 1 container frame + 1 cooldown frame + 1 timer text frame) + CD icon
      -- row (7 icon textures, 1 container frame + 7 icon frames + 7 cooldown
      -- frames)
      textures = 12, fontstrings = 5, lines = 1, extra_frames = 23 },
    { key = "WARRIOR", hands = { "mainhand", "offhand", "ranged" },
      -- HU-22 lazy bars: the fixture carries the shipped defaults, where the
      -- warrior ranged bar ships disabled - so init builds mainhand+offhand
      -- only. `hands` stays the class truth (iter_hands authority); `built`
      -- is what the construction pins below assert.
      built = { "mainhand", "offhand" },
      -- shield block (3 texture) + slam (2 texture, 1 fontstring) + 5 debuffs
      -- (15 texture, 5 fontstring) + overpower (4 texture, 1 fontstring)
      -- + Rampage badge (1 fontstring) + rage-bank cue (1 texture,
      -- 1 fontstring) + Battle Shout badge (1 fontstring) + desync spark
      -- (1 texture, W1)
      textures = 26, fontstrings = 10, lines = 0, extra_frames = 0 },
    { key = "HUNTER", hands = { "mainhand", "offhand", "ranged" },
      -- hunter_ui: cast bar (4 texture, 1 fontstring) + range helper (1 texture)
      -- + rapid fire (1 texture, 1 fontstring) + aspect icon (2 texture) + 4 frames
      -- + movement-safe cast zone (2 texture) + Bestial Wrath / Frenzy badges
      -- (2 frames, 4 texture, 2 fontstring) + H1 target warning (1 fontstring)
      textures = 14, fontstrings = 5, lines = 0, extra_frames = 6 },
    { key = "DRUID", hands = { "mainhand" },
      -- energy column (2 texture) + GCD tick marker (1 texture) + Omen glow
      -- (1 texture) + form label (1 fontstring) + D5 shred countdown
      -- (1 fontstring) + D6 maul badge (1 fontstring) + D1 TTD readout
      -- (1 fontstring) + combo pips (5 texture,
      -- 1 frame) + 3 debuffs (9 texture, 3 fontstring)
      textures = 18, fontstrings = 7, lines = 0, extra_frames = 1 },
    { key = "SHAMAN", hands = { "mainhand", "offhand" },
      -- mainhand: 3 marker textures + spark + windfury (2) + flame shock (3 texture, 1 fontstring)
      -- + 2 badge fontstrings + 4 shield rects = 13; offhand: the spark mirror = 1
      textures = 14, fontstrings = 3, lines = 0, extra_frames = 0 },
    { key = "ROGUE", hands = { "mainhand", "offhand", "ranged" },
      -- HU-22 lazy bars: same shipped-default gate as the warrior - the rogue
      -- ranged bar ships disabled, so init builds mainhand+offhand only.
      built = { "mainhand", "offhand" },
      -- D3: mainhand only - tick spark + pooling wash + SS window band/text +
      -- swap band/text + poison reminder (4 extra textures, 3 extra fontstrings);
      -- the guide (nextaction_ui) and HUD suites are not loaded here so no frames
      -- come from them, and the cold spell book resolves nothing (no rogue names
      -- in the fixture client) without erroring.
      textures = 4, fontstrings = 3, lines = 0, extra_frames = 0 },
}

local function check_hand_regions(b, hand)
    local state = b.ST[hand]
    local anchor = state.anchor_frame
    check(anchor ~= nil, hand .. ": anchor frame created")
    check(anchor.hiding_anchor_frame ~= nil, hand .. ": hiding anchor frame created")
    local bar_frame = anchor.bar_frame
    check(bar_frame ~= nil, hand .. ": bar frame created")
    eq(bar_frame.template, "BackdropTemplate", hand .. ": bar frame inherits BackdropTemplate")
    -- configure_bar_outline legitimately runs twice during init: once from
    -- configure_bar_size_and_positions and once from the direct call in
    -- init_visuals_template. ApplyBackdrop is idempotent; pin the count so a lost call
    -- or a new sequence is visible.
    eq(bar_frame.backdrop_applied, 2, hand .. ": ApplyBackdrop ran via both init passes")
    check(bar_frame.backdropInfo ~= nil, hand .. ": backdropInfo built")
    eq(bar_frame.backdropInfo.edgeSize, hand_db(b, hand).border_width,
        hand .. ": border width from the hand db")
    local vf = bar_frame.visuals_frame
    check(vf ~= nil, hand .. ": visuals frame created")
    eq(vf.bar.texture, "Texture\\Wglass", hand .. ": bar texture from LSM")
    eq(vf.gcd_bar.texture, "Texture\\Wglass", hand .. ": gcd bar texture from LSM")
    check(vf.deadzone.texture ~= nil, hand .. ": deadzone texture set")
    check(vf.bar.texcoord == nil or type(vf.bar.texcoord) == "table", hand .. ": bar texture ready")
    check(type(vf.left_text.font) == "table", hand .. ": left text font applied")
    eq(vf.left_text.font[1], "Fonts\\LSM.ttf", hand .. ": left text uses the media font")
    eq(vf.gcd1a_marker.thickness, hand_db(b, hand).gcd1a_marker_width,
        hand .. ": gcd1a marker thickness from the db")
    eq(vf.gcd1b_marker.thickness, hand_db(b, hand).gcd1b_marker_width,
        hand .. ": gcd1b marker thickness from the db")
    check(vf.spark ~= nil, hand .. ": spark texture created")
    check(vf.flash ~= nil, hand .. ": flash texture created")
end

for i = 1, #CLASSES do
    do
        local spec = CLASSES[i]
        local b = boot({ class = spec.key })
        local sb = b.sb
        -- HU-22 lazy bars: construction pins assert the BUILT hands only (a
        -- hand gated off by db.enabled/weapon has no frames by design).
        local hands = spec.built or spec.hands

        -- Non-vacuity floor: every built hand built its full documented region set.
        local per_hand = { frames = 4, textures = 5, fontstrings = 3, lines = 2 }
        eq(sb.frames_created, BOOT_FRAMES + #hands * per_hand.frames + spec.extra_frames,
            spec.key .. ": exactly the documented frames were created")
        eq(sb.textures_created, #hands * per_hand.textures + spec.textures,
            spec.key .. ": exactly the documented textures were created")
        eq(sb.fontstrings_created, #hands * per_hand.fontstrings + spec.fontstrings,
            spec.key .. ": exactly the documented fontstrings were created")
        eq(sb.lines_created, #hands * per_hand.lines + spec.lines,
            spec.key .. ": exactly the documented lines were created")

        eq(#sb.lwin_configs, #hands, spec.key .. ": LibWindow.RegisterConfig ran once per hand")
        for h = 1, #hands do
            local hand = hands[h]
            check_hand_regions(b, hand)
            eq(sb.lwin_configs[h].frame, b.ST[hand].anchor_frame,
                spec.key .. " " .. hand .. ": config registration targets its anchor frame")
            eq(sb.lwin_configs[h].db, b.ST:get_hand_table(hand),
                spec.key .. " " .. hand .. ": config registration carries the hand db")
            -- The swing engine's reading is stored and the OnUpdate driver wired.
            local state = b.ST[hand]
            local expected = sb.swing[hand]
            if expected then
                near(state.speed, expected[1], 1e-9, spec.key .. " " .. hand .. ": engine speed stored")
            end
            check(type(state.onupdate) == "function", spec.key .. " " .. hand .. ": onupdate exists")
            local script = b.ST:get_bar_frame(hand):GetScript("OnUpdate")
            eq(script, state.onupdate, spec.key .. " " .. hand .. ": OnUpdate script is the hand's onupdate")
        end

        -- The classes really loaded and their post_init ran through main.lua's post_init.
        local class_hook = b.ST[spec.key] and b.ST[spec.key].on_bar_update
        check(type(class_hook) == "function", spec.key .. ": class module defines on_bar_update")
        eq(sb.hook_calls[spec.key], nil,
            spec.key .. ": no class hook fires during construction (only the per-frame path does)")

        -- Class widget sets -----------------------------------------------------------------
        local mh_vf = visuals(b, "mainhand")
        if spec.key == "PALADIN" then
            check(mh_vf.twist_band ~= nil, "PALADIN: twist band created at post_init")
            check(mh_vf.twist_text ~= nil, "PALADIN: twist success text created at post_init")
            eq(mh_vf.twist_text.font[2], 24, "PALADIN: twist text uses the configured size")
            check(mh_vf.judgement_marker ~= nil, "PALADIN: judgement marker line created at post_init")
            eq(mh_vf.judgement_marker.thickness, 2, "PALADIN: judgement marker thickness is the constant")
            eq(mh_vf.judgement_marker.shown, false, "PALADIN: judgement marker starts hidden")
            check(mh_vf.seal_icons ~= nil, "PALADIN: seal icon set created at post_init")
            eq(#mh_vf.seal_icons.slots, 2, "PALADIN: two seal icon slots created")
            eq(mh_vf.seal_icons.slots[1].spell_id, 20375, "PALADIN: slot 1 is Seal of Command")
            eq(mh_vf.seal_icons.slots[2].spell_id, 31892, "PALADIN: slot 2 is Seal of Blood")
            eq(mh_vf.seal_icons.slots[1].cooldown.reverse, true,
                "PALADIN: seal cooldown swipe is reversed")
            eq(mh_vf.seal_icons.slots[1].icon.shown, false, "PALADIN: seal icons start hidden")
            eq(mh_vf.seal_icons.slots[2].icon.shown, false, "PALADIN: seal slot 2 starts hidden")
            -- The default bar colour comes from the class set_bar_color dispatch (no seals).
            colour_eq(mh_vf.bar.color, hand_db(b, "mainhand").bar_color_default,
                "PALADIN: default bar colour applied through set_bar_color")
            check(sb.lcg_stops >= 1, "PALADIN: no Art of War proc means the glow is stopped")
        elseif spec.key == "WARRIOR" then
            check(mh_vf.warrior_shield_block ~= nil, "WARRIOR: Shield Block bar created")
            check(mh_vf.warrior_slam ~= nil, "WARRIOR: Slam cast bar created")
            eq(type(mh_vf.warrior_debuff), "table", "WARRIOR: debuff bar groups created")
            eq(#mh_vf.warrior_overpower_edges, 4, "WARRIOR: four Overpower flash edges created")
            check(mh_vf.warrior_overpower_text ~= nil, "WARRIOR: Overpower text created")
            colour_eq(mh_vf.bar.color, hand_db(b, "mainhand").bar_color_default,
                "WARRIOR: default bar colour applied")
        elseif spec.key == "HUNTER" then
            local ui = b.st.hunter_ui
            check(ui.ready == true, "HUNTER: hunter_ui built its widget set at post_init")
            check(ui.cast_frame ~= nil, "HUNTER: cast bar frame created")
            check(ui.range_helper ~= nil, "HUNTER: range helper created")
            check(ui.rapid_fire_bar ~= nil, "HUNTER: Rapid Fire bar created")
            check(ui.aspect_icon ~= nil, "HUNTER: aspect icon created")
            eq(ui.ranged_frame, b.ST:get_bar_frame("ranged"),
                "HUNTER: the widget set anchors on the ranged bar frame")
            -- The fixture supplies the layout fact the stub cannot compute: the cast bar is
            -- two-point anchored across the 275 px ranged bar, so GetWidth() reads 275.
            ui.cast_frame.width = hand_db(b, "ranged").bar_width
        elseif spec.key == "DRUID" then
            check(mh_vf.druid_energy_tick_bg ~= nil, "DRUID: energy tick background created")
            check(mh_vf.druid_energy_tick_fill ~= nil, "DRUID: energy tick fill created")
            check(mh_vf.druid_form_label ~= nil, "DRUID: form label created")
            eq(type(mh_vf.druid_debuff), "table", "DRUID: debuff bar groups created")
        elseif spec.key == "SHAMAN" then
            check(mh_vf.weave_marker ~= nil, "SHAMAN: breakpoint marker created")
            check(mh_vf.weave_marker_top ~= nil, "SHAMAN: top breakpoint marker created")
            check(mh_vf.weave_marker_bottom ~= nil, "SHAMAN: bottom breakpoint marker created")
            check(mh_vf.weave_spark ~= nil, "SHAMAN: cast spark created")
            check(mh_vf.weave_windfury_bg ~= nil, "SHAMAN: Windfury ICD strip created")
            check(mh_vf.weave_fs_bg ~= nil, "SHAMAN: Flame Shock bar created")
            eq(#mh_vf.weave_shield_rects, 4, "SHAMAN: four shield charge rects created")
            local oh_vf = visuals(b, "offhand")
            check(oh_vf.weave_spark_offhand ~= nil, "SHAMAN: offhand spark mirror created")
            check(b.ST.weave_catalog.LB ~= nil, "SHAMAN: the weave catalogue resolved Lightning Bolt")
            eq(b.ST.weave_catalog.LB.cast_seconds, 2.5, "SHAMAN: the catalogue carries the client cast time")
        elseif spec.key == "ROGUE" then
            check(mh_vf.rogue_tick_spark ~= nil, "ROGUE: energy tick spark created")
            check(mh_vf.rogue_pool_wash ~= nil, "ROGUE: pooling wash created")
            check(mh_vf.rogue_ss_band ~= nil, "ROGUE: SS window band created")
            check(mh_vf.rogue_ss_text ~= nil, "ROGUE: SS window text created")
            check(mh_vf.rogue_swap_band ~= nil, "ROGUE: weapon-swap band created")
            check(mh_vf.rogue_swap_text ~= nil, "ROGUE: weapon-swap text created")
            check(mh_vf.rogue_poison_text ~= nil, "ROGUE: poison reminder created")
        end

        -- Text/geometry state after construction: the sizes come from the hand db.
        local db = hand_db(b, "mainhand")
        near(mh_vf.width, db.bar_width - db.border_width * 2, 1e-9,
            spec.key .. ": visuals frame width is the bar width minus the border")
        near(mh_vf.height, db.bar_height - db.border_width * 2, 1e-9,
            spec.key .. ": visuals frame height is the bar height minus the border")
        near(b.ST.mainhand.vf_width, db.bar_width - db.border_width * 2, 1e-9,
            spec.key .. ": vf_width recorded on the hand state")
        local anchor = b.ST.mainhand.anchor_frame
        near(anchor.width, db.bar_width, 1e-9, spec.key .. ": anchor frame width from the db")
        near(anchor.height, db.bar_height, 1e-9, spec.key .. ": anchor frame height from the db")
        eq(anchor.bar_frame.strata, "MEDIUM", spec.key .. ": bar frame strata from the profile")
        eq(anchor.bar_frame.frame_level, 11, spec.key .. ": bar frame level is draw_level + 1")
        check(anchor.movable == false, spec.key .. ": frames start locked (post_init's lock_frames)")
        check(b.ST.interfaces_are_initialised == true, spec.key .. ": init completed")
    end
end

--=========================================================================================
-- 1b) HU-22 lazy bars: gated-off hands stay unbuilt and behave like disabled bars
--=========================================================================================
-- The fixture carries the shipped defaults, where the warrior and rogue ranged
-- bars ship disabled. Init must not create their frames; show/hide/tick paths
-- must treat them exactly like disabled bars (no error, no tick). Enabling the
-- hand and re-equipping (the engine lane's equip build point in main.lua)
-- builds it on demand with its tick installed.
do
    for _, cls in ipairs({ "WARRIOR", "ROGUE" }) do
        local b = boot({ class = cls })
        local T = b.ST
        eq(T:bar_is_built("ranged"), false, cls .. ": ranged starts unbuilt (shipped default off)")
        eq(T:get_anchor_frame("ranged"), nil, cls .. ": no anchor frame for the gated hand")
        eq(T:ensure_bar("ranged"), false, cls .. ": ensure_bar reports false while gated")
        local ok_hide, err_hide = pcall(T.hide_bar, T, "ranged")
        check(ok_hide, cls .. ": hiding an unbuilt hand does not error (" .. tostring(err_hide) .. ")")
        local ok_show, err_show = pcall(T.show_bar, T, "ranged")
        check(ok_show, cls .. ": showing an unbuilt gated hand does not error (" .. tostring(err_show) .. ")")
        eq(T:bar_is_built("ranged"), false, cls .. ": show on a gated hand builds nothing")
        eq(T:get_bar_frame("ranged"), nil, cls .. ": no bar frame, so no OnUpdate script")
        -- Enabling + (re-)equipping builds it through the equip build point.
        hand_db(b, "ranged").enabled = true
        T:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", 18, true)
        eq(T:bar_is_built("ranged"), true, cls .. ": the equip build point builds the enabled hand")
        local script = T:get_bar_frame("ranged"):GetScript("OnUpdate")
        eq(script, T.ranged.onupdate, cls .. ": the built hand's tick is installed")
    end
end

--=========================================================================================
-- 2) The OnUpdate state machine
--=========================================================================================
-- The OnUpdate script bars.lua registers on each hand's bar frame is the per-frame core:
-- fill fraction and texcoord, bar texts and their hide-inactive rules, the GCD underlay
-- and its two branches, swing-anchored GCD markers (wrap/clamp), the deadzone width from
-- latency, pause, swing-end/is_full and the visibility/dim passes. Driven here exactly
-- as the client does: script(frame, elapsed).
do
    local b = boot({ class = "PALADIN" })
    local sb = b.sb
    local ST = b.ST
    local vf = visuals(b, "mainhand")
    local db = hand_db(b, "mainhand")
    local w, h = vf.width, vf.height
    eq(w, 271, "state: visuals width is the db width minus the borders")
    eq(h, 16, "state: visuals height is the db height minus the borders")

    -- Before any swing the bar sits full and static.
    local ticks = 0
    tick(b, "mainhand"); ticks = ticks + 1
    near(vf.bar.width, 1, 1e-9, "full timer: bar width floors at 1 px")
    eq(vf.bar.texcoord[2], 0, "full timer: texcoord right edge at 0")
    eq(vf.left_text.text, "2.6", "full timer: attack-speed text shows the engine speed")
    eq(vf.right_text.shown, false, "full timer: swing-timer text hidden by hide-inactive")
    eq(sb.hook_calls.PALADIN, 1, "state: the tick dispatched the class hook exactly once")

    -- A swing starts: on_bar_active shows the deadzone and positions the markers.
    start_swing(b, "mainhand", 2.6, 2.6)
    eq(ST.mainhand.is_full, false, "swing start: is_full cleared")
    eq(vf.deadzone.shown, true, "swing start: deadzone shown (enabled hand, not full)")
    near(vf.deadzone.width, w * ((150 / 1000) / 2.6) * 1.1, 1e-9,
        "swing start: deadzone width from world latency and the scale factor")

    -- A quarter through the swing: fill fraction, texcoord and both texts track it.
    sb.clock = 0.65
    tick(b, "mainhand"); ticks = ticks + 1
    near(vf.bar.width, w * 0.25, 1e-9, "quarter swing: bar width is width * progress")
    eq(vf.bar.texcoord[2], 0.25, "quarter swing: texcoord right edge is the progress")
    eq(vf.left_text.text, "2.6", "quarter swing: left text keeps the speed")
    eq(vf.right_text.shown, true, "quarter swing: right text shows an active swing")
    eq(vf.right_text.text, "1.9", "quarter swing: swing timer formatted to a tenth")

    -- GCD underlay branch 1: the GCD ends inside the swing.
    ST:GCD_STARTED("GCD_STARTED", 1.5, 2.0)
    tick(b, "mainhand"); ticks = ticks + 1
    local timer_width = w * (0.65 / 2.6)
    near(vf.gcd_bar.width, w * (2.0 / 2.6) - timer_width, 1e-9,
        "gcd underlay: width spans from the bar edge to the gcd end")
    near(vf.gcd_bar.texcoord[1], 0.25, 1e-9, "gcd underlay: texcoord left is the progress")
    near(vf.gcd_bar.texcoord[2], 2.0 / 2.6, 1e-9, "gcd underlay: texcoord right is the gcd end")
    eq(vf.gcd_bar.shown, true, "gcd underlay: shown for a running gcd")
    eq(vf.gcd_bar.point[1], "TOPLEFT", "gcd underlay: anchored at the swing bar's edge")
    near(vf.gcd_bar.point[2], timer_width, 1e-9, "gcd underlay: x is the swing width")

    -- GCD underlay branch 2: the GCD extends past the swing end.
    ST.gcd.expires = 3.0
    sb.clock = 2.2
    tick(b, "mainhand"); ticks = ticks + 1
    local p2 = 2.2 / 2.6
    near(vf.bar.width, w * p2, 1e-9, "gcd underlay: bar width at 2.2 s")
    near(vf.gcd_bar.width, w - w * p2, 1e-9, "gcd underlay: past-end width is the remainder")
    near(vf.gcd_bar.texcoord[1], p2, 1e-9, "gcd underlay: past-end texcoord left is the progress")
    eq(vf.gcd_bar.texcoord[2], 1, "gcd underlay: past-end texcoord right is clamped to 1")
    eq(vf.gcd_bar.shown, true, "gcd underlay: past-end remainder is shown")

    -- Pause: the engine callback freezes the fill.
    ST:SWING_TIMER_PAUSED("SWING_TIMER_PAUSED", "mainhand")
    eq(ST.mainhand.is_paused, true, "pause: flag set through the engine callback")
    sb.clock = 2.4
    tick(b, "mainhand"); ticks = ticks + 1
    near(ST.mainhand.current_progress, p2, 1e-9, "pause: progress frozen while paused")
    near(vf.bar.width, w * p2, 1e-9, "pause: bar width frozen while paused")
    ST:SWING_TIMER_CLIPPED("SWING_TIMER_CLIPPED", "mainhand")
    eq(ST.mainhand.is_paused, false, "clip: the engine callback clears the pause")

    -- Past the swing end (not yet marked full): progress and texcoord clamp to 1.
    sb.clock = 3.0
    tick(b, "mainhand"); ticks = ticks + 1
    near(vf.bar.width, w, 1e-9, "past end: progress clamps to 1")
    eq(vf.bar.texcoord[2], 1, "past end: texcoord clamps to 1")
    eq(vf.right_text.text, "0.0", "past end: swing timer floors at 0.0")

    -- The engine reports the swing over: a full-delay timer marks the bar full and runs
    -- on_bar_inactive (hide-inactive rules touch markers, deadzone and texts).
    ST:SWING_TIMER_STOP("SWING_TIMER_STOP", "mainhand")
    eq(#sb.new_timers, 1, "stop: the full-delay timer was created")
    near(sb.new_timers[1].delay, 0.05, 1e-9, "stop: delay comes from the profile default")
    sb.new_timers[1].cb()
    eq(ST.mainhand.is_full, true, "stop: the timer marks the bar full")
    eq(vf.deadzone.shown, false, "stop: deadzone hides on the full transition")
    tick(b, "mainhand"); ticks = ticks + 1
    eq(vf.right_text.shown, false, "stop: swing-timer text hides while full")
    eq(vf.gcd1a_marker.shown, false, "stop: gcd markers hide on the full transition")

    -- End-of-swing GCD markers: positioned relative to the RIGHT edge at
    -- t_before / speed of the swing (the non-per-frame path).
    start_swing(b, "mainhand", 2.6, 2.6)
    near(ST.gcd.gcd1_phys_time_before_swing, 1.5, 1e-9,
        "markers: phys time before swing is the reported GCD")
    local mo = (1.5 / 2.6) * w * -1
    eq(vf.gcd1a_marker.start_point[1], "TOPRIGHT", "markers: 1a anchored right")
    near(vf.gcd1a_marker.start_point[2], mo, 1e-9, "markers: 1a start offset")
    near(vf.gcd1a_marker.end_point[3], h * db.gcd1a_marker_fractional_height * -1, 1e-9,
        "markers: 1a end offset")
    eq(vf.gcd1b_marker.start_point[1], "BOTTOMRIGHT", "markers: 1b anchored at the bottom edge")
    near(vf.gcd1b_marker.start_point[2], mo, 1e-9, "markers: 1b start offset (spell mode)")
    eq(vf.gcd1a_marker.shown, true, "markers: 1a shown on swing start")
    eq(vf.gcd1b_marker.shown, true, "markers: 1b shown on swing start")

    -- Must NOT: a full bar with hide-inactive hides the markers even with a valid offset;
    -- an offset past the bar end (progress >= 1) always hides them.
    local function go_full()
        ST:SWING_TIMER_UPDATE("SWING_TIMER_UPDATE", 2.6, sb.clock - 1, "mainhand")
        eq(ST.mainhand.is_full, true, "marker gate: SWING_TIMER_UPDATE past the end marks full")
    end
    go_full()
    ST:on_attack_speed_change("mainhand")
    eq(vf.gcd1a_marker.shown, false, "markers: full bar with hide-inactive hides 1a")
    eq(vf.gcd1b_marker.shown, false, "markers: full bar with hide-inactive hides 1b")
    start_swing(b, "mainhand", 2.6, 2.6)
    ST.mainhand.speed = 0.5
    ST:on_attack_speed_change("mainhand")
    eq(vf.gcd1a_marker.shown, false, "markers: an offset past the bar end hides 1a")
    ST.mainhand.speed = 2.6
    ST:on_attack_speed_change("mainhand")
    eq(vf.gcd1a_marker.shown, true, "markers: back inside the bar it shows again")

    -- Swing-anchored markers are the per-frame path's job (gcd1a here).
    db.gcd1a_marker_anchor = "swing"
    db.gcd1a_swing_anchor_wrap = true
    start_swing(b, "mainhand", 2.6, 2.6)
    sb.clock = ST.mainhand.start + 1.3 -- progress 0.5
    tick(b, "mainhand"); ticks = ticks + 1
    local combined = 0.5 + 1.5 / 2.6
    near(vf.gcd1a_marker.start_point[2], (combined - 1.0) * w, 1e-9,
        "swing marker: combined progress over 1 wraps")
    eq(vf.gcd1a_marker.start_point[1], "TOPLEFT", "swing marker: anchored at the left edge")
    eq(vf.gcd1a_marker.shown, true, "swing marker: shown while the swing runs")
    db.gcd1a_swing_anchor_wrap = false
    tick(b, "mainhand"); ticks = ticks + 1
    eq(vf.gcd1a_marker.shown, false, "swing marker: wrap off clamps and hides past the end")
    near(vf.gcd1a_marker.start_point[2], w, 1e-9, "swing marker: clamped offset is the full width")

    -- Latency change: the real LLM callback reaches on_latency_update, which must touch
    -- only the hands this class actually has (a paladin has no offhand/ranged frame).
    ST:LATENCY_CHANGED("LATENCY_CHANGED", 60, 300)
    near(vf.deadzone.width, w * ((300 / 1000) / 2.6) * 1.1, 1e-9,
        "latency change: deadzone width follows the new world latency")
    db.enable_deadzone = false
    ST:LATENCY_CHANGED("LATENCY_CHANGED", 60, 300)
    eq(vf.deadzone.shown, false, "latency change: a disabled deadzone stays hidden")
    db.enable_deadzone = true

    -- GCD length change: the real callback reaches on_gcd_length_change with the class's
    -- own hand set (same single-hand gate as the latency path). The endofswing anchor is
    -- restored first: in swing-anchor mode this pass is a no-op by design.
    db.gcd1a_marker_anchor = "endofswing"
    ST:GCD_DURATIONS_UPDATED("GCD_DURATIONS_UPDATED", 1.5, 1.5)
    eq(vf.gcd1a_marker.shown, true, "gcd length change: mainhand markers repositioned and shown")

    -- Bar texts: the range-finder mode and its unknown-bound spellings.
    db.center_text_enabled = true
    db.center_text_key = "range_finder"
    ST.target_min_range, ST.target_max_range = 5, 8
    tick(b, "mainhand"); ticks = ticks + 1
    eq(vf.center_text.text, "5 - 8", "range text: both bounds known")
    ST.target_min_range, ST.target_max_range = nil, 8
    tick(b, "mainhand"); ticks = ticks + 1
    eq(vf.center_text.text, "N/A - 8", "range text: unknown minimum")
    ST.target_min_range, ST.target_max_range = 5, nil
    tick(b, "mainhand"); ticks = ticks + 1
    eq(vf.center_text.text, "5 - N/A", "range text: unknown maximum")
    ST.target_min_range, ST.target_max_range = nil, nil
    tick(b, "mainhand"); ticks = ticks + 1
    eq(vf.center_text.text, "", "range text: both unknown renders empty")

    -- Visibility and dim passes (the real rangefinder-driven functions).
    ST.in_combat = false
    ST.has_attackable_target = false
    ST:set_bar_visibilities()
    eq(ST:get_bar_frame("mainhand").shown, false, "visibility: out of combat without a target hides")
    eq(ST:get_hiding_anchor_frame("mainhand").shown, false, "visibility: the hiding anchor hides too")
    ST.in_combat = true
    ST:set_bar_visibilities()
    eq(ST:get_bar_frame("mainhand").shown, true, "visibility: in combat shows the bar")
    db.show_condition = "both"
    db.require_in_range = true
    ST.has_attackable_target = true
    ST.in_melee_range = false
    ST:set_bar_visibilities()
    eq(ST:get_bar_frame("mainhand").shown, false, "visibility: both + out of range hides")
    ST.in_melee_range = true
    ST:set_bar_visibilities()
    eq(ST:get_bar_frame("mainhand").shown, true, "visibility: both + in range shows")
    db.show_condition = "either"
    db.require_in_range = false
    db.dim_oor = true
    ST.in_melee_range = false
    ST:handle_oor_hand("mainhand")
    eq(ST:get_bar_frame("mainhand").alpha, 0.6, "dim: out of range applies the dim alpha")
    ST.in_melee_range = true
    ST:handle_oor_hand("mainhand")
    eq(ST:get_bar_frame("mainhand").alpha, 1.0, "dim: in range restores full alpha")
    local cdb = class_db(b)
    cdb.class_enabled = false
    ST:set_bar_visibilities()
    eq(ST:get_bar_frame("mainhand").shown, false, "visibility: a disabled class hides every bar")
    cdb.class_enabled = true

    -- The LibDataBroker feed is driven from the mainhand tick (throttled internally).
    local ldb_before = sb.ldb_calls.mainhand
    sb.clock = sb.clock + 1.0
    tick(b, "mainhand"); ticks = ticks + 1
    eq(sb.ldb_calls.mainhand, ldb_before + 1, "ldb: the mainhand tick drives the broker feed")
    check(sb.broker_obj ~= nil, "ldb: the first tick created the data object")
    local remaining = ST.mainhand.ends_at - sb.clock
    if remaining < 0 then remaining = 0 end
    near(tonumber(sb.broker_obj.value), remaining, 0.006,
        "ldb: publishes the live swing remaining (%.2f string)")
    eq(sb.broker_obj.firstValue, 2.6, "ldb: publishes the hand speed as the bar value")

    -- One tick == one class-hook dispatch (the exact contract the mutation proof pins).
    -- `or 0` keeps the check evaluating (and failing) even if the dispatch were removed.
    local hooks_before = sb.hook_calls.PALADIN or 0
    tick(b, "mainhand"); ticks = ticks + 1
    eq(sb.hook_calls.PALADIN or 0, hooks_before + 1,
        "hook dispatch: every tick invokes the class hook exactly once")
    eq(sb.hook_calls.PALADIN or 0, ticks, "hook dispatch: tick count matches hook count")
end

--=========================================================================================
-- 2b) Degraded and isolated tick states (H1-render, H2)
--=========================================================================================
-- H1-render: the inert stand-in must never impersonate a live cycle. The bar dims,
-- paints an explicit "engine offline" label and keeps the fill static.
do
    local b = boot({ class = "PALADIN", engine = "absent" })
    local sb = b.sb
    local ST = b.ST
    local vf = visuals(b, "mainhand")
    eq(ST.swing_engine, "inert-standin", "H1: the absent engine selects the inert stand-in")
    eq(ST.mainhand.engine_dead, true, "H1: init_timers marks the dead engine per hand")
    eq(ST.mainhand.speed, nil, "H1: no plausible cycle speed is invented")
    tick(b, "mainhand")
    eq(vf.center_text.text, "engine offline", "H1: the bar names the degraded engine")
    eq(vf.center_text.shown, true, "H1: the offline label is visible")
    eq(vf.left_text.shown, false, "H1: configured left text is not left pretending")
    eq(vf.right_text.shown, false, "H1: configured right text is not left pretending")
    near(vf.bar.width, 1, 1e-9, "H1: the fill stays the neutral sliver")
    eq(vf.bar.alpha, 0.35, "H1: the bar is dimmed")
    check(sb.prints[#sb.prints] == nil or not sb.prints[#sb.prints]:find("Bar update error", 1, true),
        "H1: rendering the dead engine is not reported as a hook error")
end

-- H2: a throwing class hook is isolated after the fill/text painted; the first throw per
-- site prints once, every throw is counted, and the site quarantines after 25.
do
    local b = boot({ class = "PALADIN" })
    local sb = b.sb
    local ST = b.ST
    local vf = visuals(b, "mainhand")
    local real_hook = ST.PALADIN.on_bar_update
    local site = "class:PALADIN:on_bar_update"
    start_swing(b, "mainhand", 2.6, 2.6)
    sb.clock = 0.65
    ST.PALADIN.on_bar_update = function() error("class hook exploded") end
    local prints_before = #sb.prints
    local ok, err = pcall(tick, b, "mainhand")
    check(ok, "H2: a throwing class hook does not break the tick (" .. tostring(err) .. ")")
    near(vf.bar.width, vf.width * 0.25, 1e-9, "H2: the fill still painted before the hook")
    eq(vf.left_text.text, "2.6", "H2: the bar text still painted before the hook")
    eq(ST.bar_hook_errors.count, 1, "H2: the throw is counted")
    eq(ST.bar_hook_errors.by_site[site], 1, "H2: the counter is attributed to the class hook")
    eq(#sb.prints, prints_before + 1, "H2: the first throw prints exactly one chat line")
    check(type(sb.prints[#sb.prints]) == "string"
        and sb.prints[#sb.prints]:find("Bar update error in " .. site, 1, true) ~= nil,
        "H2: the notice names the failing site")

    for _ = 1, 3 do
        tick(b, "mainhand")
    end
    eq(ST.bar_hook_errors.by_site[site], 4, "H2: every throw keeps counting")
    eq(#sb.prints, prints_before + 1, "H2: repeated throws do not spam chat")

    for _ = 5, 25 do
        tick(b, "mainhand")
    end
    eq(ST.bar_hook_errors.by_site[site], 25, "H2: the site reaches the quarantine threshold")
    eq(ST.bar_hook_errors.quarantined[site], true, "H2: the site is quarantined for the session")
    check(type(sb.prints[#sb.prints]) == "string"
        and sb.prints[#sb.prints]:find("quarantined for this session", 1, true) ~= nil,
        "H2: the quarantine is announced, never silent")
    local counted = ST.bar_hook_errors.count
    tick(b, "mainhand")
    eq(ST.bar_hook_errors.count, counted, "H2: a quarantined hook is not called again")
    eq(ST.bar_hook_errors.by_site[site], 25, "H2: a quarantined hook does not keep counting")
    ST.PALADIN.on_bar_update = real_hook
end

-- H2: zone draws are isolated the same way, and one bad zone does not stop the next.
do
    local b = boot({ class = "PALADIN" })
    local sb = b.sb
    local ST = b.ST
    local good_runs = 0
    ST:register_zone("bad", function() error("zone exploded") end, 0)
    ST:register_zone("good", function() good_runs = good_runs + 1 end, 1)
    local ok, err = pcall(tick, b, "mainhand")
    check(ok, "H2: a throwing zone does not break the tick (" .. tostring(err) .. ")")
    eq(good_runs, 1, "H2: the later zone still runs after the bad zone threw")
    eq(ST.bar_hook_errors.by_site["zone:bad"], 1, "H2: the zone throw is counted by zone id")
    check(type(sb.prints[#sb.prints]) == "string"
        and sb.prints[#sb.prints]:find("Bar update error in zone:bad", 1, true) ~= nil,
        "H2: the zone notice names the zone id")
end

--=========================================================================================
-- 3) Class dispatch hooks (on_bar_update): must-show and must-not states per class
--=========================================================================================
-- PALADIN: twist window band + success text, driven by the real CLEU chain.
do
    local b = boot({ class = "PALADIN" })
    local sb = b.sb
    local ST = b.ST
    local vf = visuals(b, "mainhand")
    local cdb = class_db(b)
    local w, h = vf.width, vf.height
    local band, text = vf.twist_band, vf.twist_text
    check(band ~= nil and text ~= nil, "paladin: twist widgets exist")

    -- The real CLEU forwarding shape: main.lua's handler passes the event name through,
    -- the class handler reads (timestamp, subevent, hideCaster, sourceGUID, ...).
    local function cleu(subevent, source_guid, ...)
        ST:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED",
            1000, subevent, false, source_guid, "Tester", 0, 0,
            "Creature-1", "Dummy", 0, 0, ...)
    end

    -- Two seals + an active swing are the band's preconditions.
    start_swing(b, "mainhand", 2.6, 2.6)
    local soc, sor = 20375, 21084
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = soc },
    })
    eq(ST.has_soc, true, "paladin: Seal of Command parsed from the aura list")
    eq(ST.has_sor, false, "paladin: only Command is up")
    eq(ST.twist_active_seals_count, 1, "paladin: one active seal counted")

    -- Must SHOW: idle marker tint outside the window, window tint inside it.
    sb.clock = 2.0 -- remaining 0.6 > window 0.4
    tick(b, "mainhand")
    eq(band.shown, true, "paladin band: shown while twisting is possible")
    near(band.width, w * (0.4 / 2.6), 1e-9, "paladin band: covers the twist-window fraction")
    eq(band.height, h, "paladin band: full bar height")
    vertex_eq(band.color, { 1, 1, 1, 0.15 }, "paladin band: idle marker tint outside the window")
    sb.clock = 2.3 -- remaining 0.3 <= window
    tick(b, "mainhand")
    vertex_eq(band.color, { 1, 1, 1, 0.30 }, "paladin band: in-window tint")

    -- A second seal arms twisting: the band pulses in the twisting colour.
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = soc },
        { name = "Seal of Righteousness", spell_id = sor },
    })
    eq(ST.has_sor, true, "paladin: Seal of Righteousness parsed")
    eq(ST.twist_active_seals_count, 2, "paladin: two active seals counted")
    tick(b, "mainhand")
    vertex_eq(band.color, { 179 / 255, 26 / 255, 153 / 255, 0.35 + 0.15 * math.sin(2.3 * 8) },
        "paladin band: armed pulse tint with two seals")

    -- Attempt flash, armed through the real combat-log chain.
    eq(ST.twist_attempt_pending, false, "paladin CLEU: no attempt before the swing lands")
    cleu("SWING_DAMAGE", "Player-1")
    eq(ST.twist_attempt_pending, true, "paladin CLEU: two seals at the swing arm an attempt")
    tick(b, "mainhand")
    vertex_eq(band.color, { 179 / 255, 26 / 255, 153 / 255, 0.55 },
        "paladin band: attempt flash tint")

    -- Must NOT arm: a foreign source.
    ST.twist_attempt_pending = false
    cleu("SWING_DAMAGE", "Player-99")
    eq(ST.twist_attempt_pending, false, "paladin CLEU: a foreign source never arms")
    -- Must NOT arm: the next swing is an extra attack.
    cleu("SPELL_EXTRA_ATTACKS", "Player-1", 403, "Lightning Bolt", 1, 1)
    eq(ST.twist_extra_attacks_pending, 1, "paladin CLEU: extra attacks are counted")
    cleu("SWING_DAMAGE", "Player-1")
    eq(ST.twist_extra_attacks_pending, 0, "paladin CLEU: the swing consumes the extra attack")
    eq(ST.twist_attempt_pending, false, "paladin CLEU: an extra attack suppresses the attempt")

    -- Success: a Seal of Command proc while an attempt is pending.
    cleu("SWING_DAMAGE", "Player-1")
    eq(ST.twist_attempt_pending, true, "paladin CLEU: attempt armed again")
    cleu("SPELL_DAMAGE", "Player-1", 20424)
    eq(ST.twist_attempt_pending, false, "paladin CLEU: the Command proc consumes the attempt")
    eq(text.text, "Successful TWIST!", "paladin success: text set by the real proc chain")
    eq(text.shown, true, "paladin success: text shown")
    vertex_eq(text.color, { 90 / 255, 255 / 255, 90 / 255, 1 }, "paladin success: text colour")
    tick(b, "mainhand")
    vertex_eq(band.color, { 90 / 255, 255 / 255, 90 / 255, 0.55 }, "paladin band: success flash tint")
    near(text.alpha, 1, 1e-9, "paladin success: text starts fully opaque")
    sb.clock = sb.clock + 1.35 -- 0.15 s left of the 1.5 s duration
    tick(b, "mainhand")
    near(text.alpha, 0.5, 1e-9, "paladin success: text fades over its final 0.3 s")
    sb.clock = sb.clock + 0.3
    tick(b, "mainhand")
    eq(text.shown, false, "paladin success: text hides once the fade is over")
    eq(text.text, "", "paladin success: text is cleared once the fade is over")

    -- Impossible-twist warning: a running GCD plus calibrated lag cannot clear before the
    -- swing. Window entry clears it (go-time).
    local t0 = sb.clock
    start_swing(b, "mainhand", 5.0, 5.0)
    ST.gcd.expires = t0 + 5.0
    sb.clock = t0 + 2.0 -- remaining 3.0 > 0.4; gcd 3.0 + 0.225 lag > 3.0
    tick(b, "mainhand")
    eq(ST.twist_impossible, true, "paladin band: gcd + lag cannot clear before the swing")
    vertex_eq(band.color, { 212 / 255, 212 / 255, 3 / 255, 0.5 }, "paladin band: impossible tint")
    sb.clock = t0 + 4.8 -- remaining 0.2 <= window
    tick(b, "mainhand")
    eq(ST.twist_impossible, false, "paladin band: the warning clears inside the window")

    -- Must NOT show: no twist seal, a full bar, or the option off.
    set_player_auras(b, {})
    eq(ST.twist_active_seals_count, 0, "paladin band: seals cleared")
    start_swing(b, "mainhand", 2.6, 2.6)
    tick(b, "mainhand")
    eq(band.shown, false, "paladin band: hidden without a Command/Righteousness seal")
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = soc },
        { name = "Seal of Righteousness", spell_id = sor },
    })
    ST:SWING_TIMER_UPDATE("SWING_TIMER_UPDATE", 2.6, sb.clock - 1, "mainhand")
    tick(b, "mainhand")
    eq(band.shown, false, "paladin band: hidden while the bar is full")
    start_swing(b, "mainhand", 2.6, 2.6)
    cdb.twist_marker_enabled = false
    tick(b, "mainhand")
    eq(band.shown, false, "paladin band: hidden with the marker option off")
    cdb.twist_marker_enabled = true
    tick(b, "mainhand")
    eq(band.shown, true, "paladin band: back on with the option restored")
end

-- PALADIN: judgement marker line (Judgement coming off cooldown inside the swing).
do
    local b = boot({ class = "PALADIN" })
    local sb = b.sb
    local ST = b.ST
    local vf = visuals(b, "mainhand")
    local cdb = class_db(b)
    local w, h = vf.width, vf.height
    local marker = vf.judgement_marker
    check(marker ~= nil, "judgement: marker line exists")
    vertex_eq(marker.color_texture, { 230 / 255, 230 / 255, 3 / 255, 1 },
        "judgement: marker colour is the archived yellow")

    -- A seal worth judging is up, and Judgement leaves cooldown inside this swing:
    -- cooldown ends at 1.5, the clock reads 1.0 of a 2.6 swing.
    set_player_auras(b, {
        { name = "Seal of Blood", spell_id = 31892 },
    })
    start_swing(b, "mainhand", 2.6, 2.6)
    sb.cooldowns[20271] = { start = -6.5, duration = 8 }
    sb.clock = 1.0
    tick(b, "mainhand")
    local offset = (1.5 / 2.6) * w
    eq(marker.shown, true, "judgement: shown when the cooldown ends inside the swing")
    eq(marker.start_point[1], "TOPLEFT", "judgement: anchored at the left edge")
    near(marker.start_point[2], offset, 1e-9, "judgement: offset is (remaining + elapsed) / speed")
    near(marker.end_point[3], h * -1, 1e-9, "judgement: full bar height")

    -- Must NOT: the cooldown ends after this swing (7.0 s left of a 1.6 s swing).
    sb.cooldowns[20271] = { start = 0, duration = 8 }
    tick(b, "mainhand")
    eq(marker.shown, false, "judgement: hidden when the cooldown outlasts the swing")

    -- Must NOT: the GCD echo (1.5 s) is not a Judgement cooldown.
    sb.cooldowns[20271] = { start = 0.5, duration = 1.5 }
    sb.clock = 1.0
    tick(b, "mainhand")
    eq(marker.shown, false, "judgement: hidden for the GCD echo")

    -- Must NOT: Judgement ready (no cooldown at all).
    sb.cooldowns[20271] = nil
    tick(b, "mainhand")
    eq(marker.shown, false, "judgement: hidden while Judgement is ready")

    -- Must NOT: no seal worth judging, a full bar, or the option off.
    sb.cooldowns[20271] = { start = -6.5, duration = 8 }
    set_player_auras(b, {})
    tick(b, "mainhand")
    eq(marker.shown, false, "judgement: hidden without a judgement seal")
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = 20375 },
    })
    tick(b, "mainhand")
    eq(marker.shown, false, "judgement: Command alone is not a judgement seal")
    set_player_auras(b, {
        { name = "Seal of Blood", spell_id = 31892 },
    })
    ST:SWING_TIMER_UPDATE("SWING_TIMER_UPDATE", 2.6, sb.clock - 1, "mainhand")
    tick(b, "mainhand")
    eq(marker.shown, false, "judgement: hidden while the bar is full")
    start_swing(b, "mainhand", 2.6, 2.6)
    cdb.judgement_marker_enabled = false
    tick(b, "mainhand")
    eq(marker.shown, false, "judgement: hidden with the option off")
    cdb.judgement_marker_enabled = true
    tick(b, "mainhand")
    eq(marker.shown, true, "judgement: back on with the option restored")
end

-- PALADIN: standalone seal icons (one slot per twist seal, swipe + timer text).
do
    local b = boot({ class = "PALADIN" })
    local sb = b.sb
    local vf = visuals(b, "mainhand")
    local cdb = class_db(b)
    local set = vf.seal_icons
    check(set ~= nil, "seal icons: container set exists")
    eq(set.frame.shown, false, "seal icons: container starts hidden")

    -- One seal: slot 1 shows its icon, swipe and text; slot 2 stays dark.
    sb.clock = 0
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = 20375, expiration = 25 },
    })
    start_swing(b, "mainhand", 2.6, 2.6)
    tick(b, "mainhand")
    local s1, s2 = set.slots[1], set.slots[2]
    eq(s1.icon.texture, "icon_soc", "seal icons: slot 1 resolves the Command icon")
    eq(s1.icon.shown, true, "seal icons: slot 1 shown with Command up")
    eq(s1.cooldown.cooldown[1], -5, "seal icons: swipe starts at expiry minus the 30 s fallback")
    eq(s1.cooldown.cooldown[2], 30, "seal icons: swipe length is the fallback duration")
    eq(s1.cooldown.shown, true, "seal icons: swipe shown")
    eq(s1.timer.text, "25", "seal icons: timer text shows the remaining seconds")
    eq(s1.timer.shown, true, "seal icons: timer text shown")
    eq(s2.icon.shown, false, "seal icons: slot 2 hidden without Blood")
    eq(set.frame.shown, true, "seal icons: container shown while a seal is up")

    -- The swipe is set once per seal: re-ticking does not restart it.
    tick(b, "mainhand")
    eq(s1.cooldown.cooldown[1], -5, "seal icons: the swipe is not restarted every tick")

    -- The timer counts down with the clock.
    sb.clock = 1.5
    tick(b, "mainhand")
    eq(s1.timer.text, "23", "seal icons: timer text follows the clock")

    -- Two seals: both slots drive.
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = 20375, expiration = 25 },
        { name = "Seal of Blood", spell_id = 31892, expiration = 20 },
    })
    tick(b, "mainhand")
    eq(s2.icon.texture, "icon_sob", "seal icons: slot 2 resolves the Blood icon")
    eq(s2.icon.shown, true, "seal icons: slot 2 shown with Blood up")
    eq(s2.cooldown.cooldown[1], -10, "seal icons: slot 2 swipe starts at its own expiry")
    eq(s2.timer.text, "18", "seal icons: slot 2 timer counts its own remaining time")

    -- A seal without a usable expiry still shows its icon, but no swipe or text.
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = 20375 },
    })
    tick(b, "mainhand")
    eq(s1.icon.shown, true, "seal icons: icon shows without an expiry")
    eq(s1.cooldown.cooldown[1], 0, "seal icons: swipe cleared without an expiry")
    eq(s1.cooldown.shown, false, "seal icons: swipe hidden without an expiry")
    eq(s1.timer.shown, false, "seal icons: timer hidden without an expiry")

    -- No seals: everything hides and the swipe state resets.
    set_player_auras(b, {})
    tick(b, "mainhand")
    eq(s1.icon.shown, false, "seal icons: slot 1 hides with no seals")
    eq(s1.cooldown.cooldown[1], 0, "seal icons: swipe reset with no seals")
    eq(s1.timer.shown, false, "seal icons: timer hides with no seals")
    eq(set.frame.shown, false, "seal icons: container hides with no seals")

    -- Must NOT: the option off.
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = 20375, expiration = 25 },
    })
    cdb.seal_icons_enabled = false
    tick(b, "mainhand")
    eq(s1.icon.shown, false, "seal icons: hidden with the option off")
    eq(set.frame.shown, false, "seal icons: container hidden with the option off")
    cdb.seal_icons_enabled = true
    tick(b, "mainhand")
    eq(s1.icon.shown, true, "seal icons: back on with the option restored")
end

-- PALADIN: twist-success glow (Pixel on the mainhand bar at attempt time).
do
    local b = boot({ class = "PALADIN" })
    local sb = b.sb
    local ST = b.ST
    local cdb = class_db(b)
    local bar_frame = ST:get_bar_frame("mainhand")
    -- Baseline after the swing start: SWING_TIMER_START runs set_bar_color, whose
    -- Art of War pass stops its (keyless) glow once per swing.
    start_swing(b, "mainhand", 2.6, 2.6)
    local starts, stops = sb.lcg_starts, sb.lcg_stops

    -- Direct: the attempt starts one keyed Pixel glow with the db colour.
    ST.PALADIN.on_twist_attempt(ST)
    eq(sb.lcg_starts, starts + 1, "glow: the attempt starts the glow")
    eq(sb.lcg_last_start.frame, bar_frame, "glow: the glow targets the mainhand bar")
    eq(sb.lcg_last_start.key, "TwistSuccess", "glow: the attempt glow carries its key")
    eq(sb.lcg_last_start.n, 8, "glow: the line count is the archived Pixel parameter")
    near(sb.lcg_last_start.freq, 0.25, 1e-9, "glow: the frequency is the archived parameter")
    eq(sb.lcg_last_start.th, 2, "glow: the thickness is the archived parameter")
    vertex_eq(sb.lcg_last_start.color, { 0, 1, 0, 0.8 }, "glow: the colour converts the db default")

    -- The glow survives inside its duration and stops once past it.
    sb.clock = sb.clock + 0.2
    tick(b, "mainhand")
    eq(sb.lcg_stops, stops, "glow: no stop inside the duration")
    sb.clock = sb.clock + 0.5
    tick(b, "mainhand")
    eq(sb.lcg_stops, stops + 1, "glow: the per-frame hook stops the expired glow")
    eq(sb.lcg_last_stop.key, "TwistSuccess", "glow: the stop carries the attempt key")
    tick(b, "mainhand")
    eq(sb.lcg_stops, stops + 1, "glow: the stop fires exactly once")

    -- The real chain: a CLEU-armed attempt starts the glow too.
    set_player_auras(b, {
        { name = "Seal of Command", spell_id = 20375 },
        { name = "Seal of Righteousness", spell_id = 21084 },
    })
    local s2 = sb.lcg_starts
    ST:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED",
        1000, "SWING_DAMAGE", false, "Player-1", "Tester", 0, 0,
        "Creature-1", "Dummy", 0, 0)
    eq(sb.lcg_starts, s2 + 1, "glow: the CLEU attempt path starts the glow")

    -- Must NOT: the option off starts nothing.
    local s3 = sb.lcg_starts
    cdb.twist_success_glow_enabled = false
    ST.PALADIN.on_twist_attempt(ST)
    eq(sb.lcg_starts, s3, "glow: disabled starts no glow")
    -- Disabling mid-glow stops it on the next tick.
    cdb.twist_success_glow_enabled = true
    ST.PALADIN.on_twist_attempt(ST)
    cdb.twist_success_glow_enabled = false
    local p3 = sb.lcg_stops
    tick(b, "mainhand")
    eq(sb.lcg_stops, p3 + 1, "glow: disabling mid-glow stops it")

    -- Combat exit clears the pending glow.
    cdb.twist_success_glow_enabled = true
    ST.PALADIN.on_twist_attempt(ST)
    local p4 = sb.lcg_stops
    ST.PALADIN.on_combat_exit(ST)
    eq(ST.twist_glow_until, 0, "glow: combat exit clears the expiry")
    eq(sb.lcg_stops, p4 + 1, "glow: combat exit stops the glow")
end

-- WARRIOR: Overpower flash, Shield Block, Slam cast bar and the debuff bars.
do
    local b = boot({ class = "WARRIOR" })
    local sb = b.sb
    local ST = b.ST
    local vf = visuals(b, "mainhand")
    local cdb = class_db(b)
    local w = vf.width

    local function cleu(subevent, source_guid, ...)
        ST:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED",
            1000, subevent, false, source_guid, "Tester", 0, 0,
            "Creature-1", "Dummy", 0, 0, ...)
    end

    -- Overpower flash: must NOT show while no dodge window is armed.
    tick(b, "mainhand")
    for i = 1, #vf.warrior_overpower_edges do
        eq(vf.warrior_overpower_edges[i].shown, false,
            "warrior OP: edge " .. i .. " hidden without a proc")
    end
    eq(vf.warrior_overpower_text.shown, false, "warrior OP: text hidden without a proc")
    eq(ST.warrior_overpower_proc_until, nil, "warrior OP: no window armed initially")

    -- Must NOT arm: foreign source, non-dodge miss, non-melee spell.
    cleu("SWING_MISSED", "Player-99", "DODGE")
    eq(ST.warrior_overpower_proc_until, nil, "warrior OP: a foreign source never arms")
    cleu("SWING_MISSED", "Player-1", "PARRY")
    eq(ST.warrior_overpower_proc_until, nil, "warrior OP: a parry never arms")
    cleu("SPELL_MISSED", "Player-1", 403, "Lightning Bolt", 1, "DODGE")
    eq(ST.warrior_overpower_proc_until, nil, "warrior OP: a non-melee spell dodge never arms")

    -- Must arm: a player swing dodged. The pulse alpha is pinned exactly at pi/20.
    sb.clock = math.pi / 20
    cleu("SWING_MISSED", "Player-1", "DODGE")
    near(ST.warrior_overpower_proc_until, sb.clock + 5.0, 1e-9,
        "warrior OP: a dodged swing arms the 5 s window")
    tick(b, "mainhand")
    eq(vf.warrior_overpower_text.shown, true, "warrior OP: text shows while the window is live")
    eq(vf.warrior_overpower_text.text, "OP", "warrior OP: text reads OP")
    local pulse_alpha = 0.25 + 0.45 * (0.5 + 0.5 * math.sin(sb.clock * 10))
    for i = 1, #vf.warrior_overpower_edges do
        eq(vf.warrior_overpower_edges[i].shown, true, "warrior OP: edge " .. i .. " shows")
        vertex_eq(vf.warrior_overpower_edges[i].color_texture, { 1, 0.85, 0.10, pulse_alpha },
            "warrior OP: edge " .. i .. " pulse alpha")
    end

    -- A queued-ability dodge arms it too; a landed Overpower closes it.
    ST.warrior_overpower_proc_until = nil
    cleu("SPELL_MISSED", "Player-1", 78, "Heroic Strike", 1, "DODGE")
    near(ST.warrior_overpower_proc_until, sb.clock + 5.0, 1e-9,
        "warrior OP: a queued ability dodge arms the window")
    ST:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 7384)
    eq(ST.warrior_overpower_proc_until, nil, "warrior OP: a landed Overpower closes the window")
    tick(b, "mainhand")
    eq(vf.warrior_overpower_edges[1].shown, false, "warrior OP: edges hide when the window closes")

    -- Expiry clears it; the option gate hides an active flash.
    cleu("SWING_MISSED", "Player-1", "DODGE")
    sb.clock = sb.clock + 6.0
    tick(b, "mainhand")
    eq(ST.warrior_overpower_flash_on, false, "warrior OP: an expired window clears the flash")
    cleu("SWING_MISSED", "Player-1", "DODGE")
    tick(b, "mainhand")
    eq(vf.warrior_overpower_edges[1].shown, true, "warrior OP: a re-armed flash shows again")
    cdb.show_warrior_overpower_flash = false
    tick(b, "mainhand")
    eq(vf.warrior_overpower_edges[1].shown, false, "warrior OP: option off hides an active flash")
    cdb.show_warrior_overpower_flash = true

    -- Shield Block: a player helpful aura drives the 4 px bar and its icon.
    sb.clock = 10.0
    set_player_auras(b, {
        { name = "Shield Block", spell_id = 2565, count = 1, duration = 10, expiration = 16.0 },
    })
    tick(b, "mainhand")
    local sb_bar = vf.warrior_shield_block
    eq(sb_bar.bg.shown, true, "warrior shield block: backing shows while the aura is up")
    eq(sb_bar.fill.shown, true, "warrior shield block: fill shows")
    near(sb_bar.fill.width, w * (6.0 / 10.0), 1e-9,
        "warrior shield block: fill fraction from remaining/total")
    vertex_eq(sb_bar.fill.color, db_color(
        cdb.warrior_shield_block_bar_color),
        "warrior shield block: configured fill tint")
    eq(sb_bar.icon.texture, "icon_shieldblock",
        "warrior shield block: icon texture from the client spell data")
    eq(sb_bar.icon.shown, true, "warrior shield block: icon shown once resolved")
    -- Must NOT: the aura drops.
    set_player_auras(b, {})
    sb.clock = sb.clock + 0.1
    tick(b, "mainhand")
    eq(sb_bar.bg.shown, false, "warrior shield block: hides without the aura")

    -- Slam cast bar: the spellcast lifecycle records the cast, the tick draws it.
    local cast_start = 20.0
    sb.clock = cast_start
    sb.cast = { name = "Slam", spell_id = 47475, start_ms = cast_start * 1000, end_ms = (cast_start + 1.5) * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    eq(ST.warrior_slam_casting, true, "warrior slam: UNIT_SPELLCAST_START begins the cast")
    near(ST.warrior_slam_cast_duration, 1.5, 1e-9, "warrior slam: live cast window duration")
    sb.clock = cast_start + 0.75
    tick(b, "mainhand")
    local slam = vf.warrior_slam
    eq(slam.bg.shown, true, "warrior slam: bar shows mid-cast")
    near(slam.fill.width, w * 0.5, 1e-9, "warrior slam: fill is the cast progress")
    eq(slam.label.text, "SLAM 0.8s", "warrior slam: label carries the remaining tenth")
    -- Unrelated casts and the STOP family.
    ST:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player", "cast-1", 47475)
    eq(ST.warrior_slam_casting, false, "warrior slam: STOP ends the cast")
    tick(b, "mainhand")
    eq(slam.bg.shown, false, "warrior slam: bar hides after STOP")
    sb.cast = nil
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-2", 403)
    eq(ST.warrior_slam_casting, false, "warrior slam: an unrelated cast never starts the bar")
    -- Option off: the handler ignores START entirely.
    cdb.show_warrior_slam_cast_bar = false
    sb.cast = { name = "Slam", spell_id = 47475, start_ms = sb.clock * 1000, end_ms = (sb.clock + 1.5) * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-3", 47475)
    eq(ST.warrior_slam_casting, false, "warrior slam: option off ignores START")
    cdb.show_warrior_slam_cast_bar = true
    sb.cast = nil

    -- Debuff bars: one throttled target scan feeds all five.
    sb.clock = 30.0
    set_target_auras(b, {
        { name = "Deep Wounds", spell_id = 12721, count = 3, duration = 12, expiration = 38.0, source = "player" },
    })
    tick(b, "mainhand")
    local dw = vf.warrior_debuff.deep_wounds
    eq(dw.bg.shown, true, "warrior debuffs: Deep Wounds bar shows")
    near(dw.fill.width, w * (8.0 / 12.0), 1e-9, "warrior debuffs: fill fraction from remaining/total")
    eq(dw.label.text, "8", "warrior debuffs: whole-second label")
    eq(dw.glow.shown, false, "warrior debuffs: no glow outside the final 4 s")
    sb.clock = 35.0
    tick(b, "mainhand")
    eq(dw.glow.shown, true, "warrior debuffs: glow inside the final 4 s")
    -- Must NOT: a foreign-source debuff and the option gate.
    set_target_auras(b, {
        { name = "Deep Wounds", spell_id = 12721, count = 3, duration = 12, expiration = 40.0, source = "other" },
    })
    sb.clock = 36.0
    tick(b, "mainhand")
    eq(dw.bg.shown, false, "warrior debuffs: a foreign-source debuff is ignored")
    set_target_auras(b, {
        { name = "Deep Wounds", spell_id = 12721, count = 3, duration = 12, expiration = 40.0, source = "player" },
    })
    cdb.show_warrior_deep_wounds_bar = false
    sb.clock = 36.1
    tick(b, "mainhand")
    eq(dw.bg.shown, false, "warrior debuffs: the option off hides the bar")
    cdb.show_warrior_deep_wounds_bar = true

    -- Rage colouring through the real event and class hook.
    sb.power.default = 10
    ST.hs_queued = true
    ST:UNIT_POWER_FREQUENT("UNIT_POWER_FREQUENT", "player", "RAGE")
    vertex_eq(vf.bar.color, db_color(cdb.insufficient_rage_color),
        "warrior rage: insufficient rage tints grey")
    sb.power.default = 20
    ST:UNIT_POWER_FREQUENT("UNIT_POWER_FREQUENT", "player", "RAGE")
    vertex_eq(vf.bar.color, db_color(cdb.hs_color), "warrior rage: enough rage gives the HS tint")
    -- Must NOT react: a non-player unit or a non-rage power type.
    sb.power.default = 10
    ST:UNIT_POWER_FREQUENT("UNIT_POWER_FREQUENT", "target", "RAGE")
    ST:UNIT_POWER_FREQUENT("UNIT_POWER_FREQUENT", "player", "MANA")
    vertex_eq(vf.bar.color, db_color(cdb.hs_color), "warrior rage: unrelated power events do nothing")

    -- The broker feed is mainhand-only: the offhand tick must not reach it.
    tick(b, "offhand")
    eq(sb.ldb_calls.offhand, nil, "warrior ldb: the offhand tick never feeds the broker")
end

-- WARRIOR G1 (Era boot): INTERRUPTED/FAILED clears the HS/Cleave queue tint
-- (reference SuperSwingTimer_State.lua:1129-1149); the current-spell probe
-- re-arms a live queue (self-heal intact).
do
    local b = boot({ class = "WARRIOR", project = 2, interface = 11509 })
    local sb = b.sb
    local ST = b.ST
    eq(b.st.family, "ERA", "warrior G1: the Era boot maps to ERA")
    ST.hs_queued = true
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-9", 78)
    eq(ST.hs_queued, false, "warrior G1: INTERRUPTED clears the HS flag")
    eq(ST.cleave_queued, false, "warrior G1: INTERRUPTED leaves Cleave clear")
    ST.cleave_queued = true
    ST:UNIT_SPELLCAST_FAILED("UNIT_SPELLCAST_FAILED", "player", "cast-9", 845)
    eq(ST.cleave_queued, false, "warrior G1: FAILED clears the Cleave flag")
    ST.hs_queued = true
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-9", 403)
    eq(ST.hs_queued, true, "warrior G1: an unrelated interrupt keeps the flag")
    ST:UNIT_SPELLCAST_FAILED("UNIT_SPELLCAST_FAILED", "player", nil, nil)
    eq(ST.hs_queued, false, "warrior G1: a nil token clears the flag")
    sb.current_spell = 78
    ST:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
    eq(ST.hs_queued, true, "warrior G1: the current-spell probe re-arms a live queue")
    sb.current_spell = nil
end

-- WARRIOR G1 (TBC boot): name-carrying payloads (Anniversary R1) clear too.
do
    local b = boot({ class = "WARRIOR", project = 5, interface = 20506 })
    local sb = b.sb
    local ST = b.ST
    eq(b.st.family, "TBC", "warrior G1: the Anniversary boot maps to TBC")
    ST.hs_queued = true
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-9", "Heroic Strike")
    eq(ST.hs_queued, false, "warrior G1: an HS name interrupt clears the flag")
    ST.cleave_queued = true
    ST:UNIT_SPELLCAST_FAILED("UNIT_SPELLCAST_FAILED", "player", "cast-9", "Cleave")
    eq(ST.cleave_queued, false, "warrior G1: a Cleave name failure clears the flag")
    sb.current_spell = "Heroic Strike"
    ST:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
    eq(ST.hs_queued, true, "warrior G1: the TBC name probe re-arms a live queue")
    sb.current_spell = nil
end

-- WARRIOR G3 (Era boot): Slam START arms the swing pause (even with the slam
-- cast bar gated off - swing behavior, not display); the next mainhand START
-- (the lib's SUCCEEDED reset) converts to the pause-extended anchor.
do
    local b = boot({ class = "WARRIOR", project = 2, interface = 11509 })
    local sb = b.sb
    local ST = b.ST
    sb.clock = 50.0
    start_swing(b, "mainhand", 2.6, 2.0) -- ends at 52.0
    eq(ST.mainhand.ends_at, 52.0, "warrior G3: the live cycle anchors first")
    class_db(b).show_warrior_slam_cast_bar = false
    sb.cast = { name = "Slam", spell_id = 47475, start_ms = 50.0 * 1000, end_ms = 51.5 * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    check(ST.warrior_slam_pause ~= nil, "warrior G3: Slam START arms the pause")
    eq(ST.warrior_slam_pause and ST.warrior_slam_pause.mainhand_rem or nil, 2.0,
        "warrior G3: the pause records the remainder")
    eq(ST.mainhand.is_paused, true, "warrior G3: the bar freezes for the cast")
    sb.clock = 51.0
    start_swing(b, "mainhand", 2.6, 2.6) -- the lib's reset START
    eq(ST.mainhand.ends_at, 53.0, "warrior G3: the reset START extends by the remainder")
    eq(ST.warrior_slam_pause, nil, "warrior G3: the convert consumes the pause")
    eq(ST.mainhand.is_paused, false, "warrior G3: the bar unfreezes on convert")
    class_db(b).show_warrior_slam_cast_bar = true
    sb.cast = nil
end

-- WARRIOR G3 (Era boot): STOP clears without extending; INTERRUPTED extends by
-- the paused span, then clears (reference AdjustSwingTimesAfterPause).
do
    local b = boot({ class = "WARRIOR", project = 2, interface = 11509 })
    local sb = b.sb
    local ST = b.ST
    sb.clock = 60.0
    start_swing(b, "mainhand", 2.6, 2.0) -- ends at 62.0
    sb.cast = { name = "Slam", spell_id = 47475, start_ms = 60.0 * 1000, end_ms = 61.5 * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    ST:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player", "cast-1", 47475)
    eq(ST.warrior_slam_pause, nil, "warrior G3: STOP clears the pause")
    eq(ST.mainhand.ends_at, 62.0, "warrior G3: STOP extends nothing")
    eq(ST.mainhand.is_paused, false, "warrior G3: STOP unfreezes the bar")
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-2", 47475)
    check(ST.warrior_slam_pause ~= nil, "warrior G3: Slam START re-arms the pause")
    sb.clock = 60.5
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-2", 47475)
    eq(ST.warrior_slam_pause, nil, "warrior G3: INTERRUPTED consumes the pause")
    eq(ST.mainhand.ends_at, 62.5, "warrior G3: INTERRUPTED extends by the paused span")
    eq(ST.mainhand.is_paused, false, "warrior G3: INTERRUPTED unfreezes the bar")
    sb.cast = nil
end

-- WARRIOR G3 (Era boot): a pause older than its backstop never converts a
-- later real swing.
do
    local b = boot({ class = "WARRIOR", project = 2, interface = 11509 })
    local sb = b.sb
    local ST = b.ST
    sb.clock = 70.0
    start_swing(b, "mainhand", 2.6, 2.0) -- ends at 72.0
    sb.cast = { name = "Slam", spell_id = 47475, start_ms = 70.0 * 1000, end_ms = 71.5 * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    check(ST.warrior_slam_pause ~= nil, "warrior G3: the stale case arms first")
    sb.clock = 80.0 -- past the 71.5 + 2.0 backstop
    start_swing(b, "mainhand", 2.6, 2.6)
    eq(ST.mainhand.ends_at, 82.6, "warrior G3: a stale pause re-anchors normally")
    eq(ST.warrior_slam_pause, nil, "warrior G3: a stale pause is dropped")
    sb.cast = nil
end

-- WARRIOR G3 (TBC boot): Anniversary arms like Era (the pause behavior is
-- classic-line, not TBC-only).
do
    local b = boot({ class = "WARRIOR", project = 5, interface = 20506 })
    local sb = b.sb
    local ST = b.ST
    eq(b.st.family, "TBC", "warrior G3: the Anniversary boot maps to TBC")
    sb.clock = 50.0
    start_swing(b, "mainhand", 2.6, 2.0)
    sb.cast = { name = "Slam", spell_id = 47475, start_ms = 50.0 * 1000, end_ms = 51.5 * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    check(ST.warrior_slam_pause ~= nil, "warrior G3: Anniversary arms the pause")
    sb.cast = nil
end

-- WARRIOR G3 (Wrath boot): never arms - the lib pauses Slam natively there.
do
    local b = boot({ class = "WARRIOR" })
    local sb = b.sb
    local ST = b.ST
    sb.clock = 50.0
    start_swing(b, "mainhand", 2.6, 2.0)
    sb.cast = { name = "Slam", spell_id = 47475, start_ms = 50.0 * 1000, end_ms = 51.5 * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-1", 47475)
    eq(ST.warrior_slam_pause, nil, "warrior G3: Wrath never arms the pause")
    check(not ST.mainhand.is_paused, "warrior G3: Wrath leaves the bar unfrozen")
    sb.cast = nil
end

-- HUNTER: the ranged visual set (cast bar + window face, no-clip tint, range helper,
-- Rapid Fire bar, aspect icon) and the queue-colour dispatch.
do
    local b = boot({ class = "HUNTER" })
    local sb = b.sb
    local ST = b.ST
    local ui = b.st.hunter_ui
    local db = hand_db(b, "ranged")
    local cdb = class_db(b)
    local mh_vf = visuals(b, "mainhand")
    -- The cast bar is two-point anchored across the ranged bar; the stub cannot compute
    -- that width, so the fixture supplies the layout fact (as in section 1).
    ui.cast_frame.width = db.bar_width
    local cast_w = db.bar_width

    -- Live cast: fill progress, name + remaining text, latency end-slice.
    local t0 = 10.0
    sb.clock = t0
    start_swing(b, "ranged", 2.8, 2.8)
    sb.cast = { name = "Steady Shot", spell_id = 56641, start_ms = t0 * 1000, end_ms = (t0 + 1.5) * 1000 }
    tick(b, "ranged")
    eq(ui.cast_frame.shown, true, "hunter cast: frame shows during a live cast")
    eq(ui.cast_frame.text.text, "Steady Shot 1.5", "hunter cast: name + remaining text")
    near(ui.cast_frame.bar.width, 1, 1e-9, "hunter cast: zero progress floors the fill at 1 px")
    near(ui.cast_frame.latency.width, 0.1 * cast_w, 1e-9, "hunter cast: latency end-slice width")
    eq(ui.cast_frame.latency.shown, true, "hunter cast: latency end-slice shown")
    sb.clock = t0 + 0.75
    tick(b, "ranged")
    near(ui.cast_frame.bar.width, (0.75 / 1.5) * cast_w, 1e-9,
        "hunter cast: fill is the cast progress")
    eq(ui.cast_frame.text.text, "Steady Shot 0.8", "hunter cast: tenth-of-a-second text")

    -- No-clip tint: the steady-shot 0.5 s grace vs Multi-Shot's zero grace, at the same
    -- 0.9 s remaining and a 0.9 s time-to-next-shot.
    sb.clock = t0 + 1.9
    sb.cast = { name = "Steady Shot", spell_id = 56641, start_ms = (sb.clock - 0.1) * 1000, end_ms = (sb.clock + 0.9) * 1000 }
    tick(b, "ranged")
    eq(ui.cast_frame.tint.shown, true, "hunter tint: shown for a live cast")
    vertex_eq(ui.cast_frame.tint.color_texture, { 0.2, 0.78, 0.25, 0.4 },
        "hunter tint: steady shot fits the grace window (safe tint)")
    sb.cast = { name = "Multi-Shot", spell_id = 2643, start_ms = (sb.clock - 0.1) * 1000, end_ms = (sb.clock + 0.9) * 1000 }
    tick(b, "ranged")
    vertex_eq(ui.cast_frame.tint.color_texture, { 1, 0, 0, 0.4 },
        "hunter tint: multi-shot's zero grace flips it unsafe")
    sb.cast = { name = "Steady Shot", spell_id = 56641, start_ms = (sb.clock - 0.1) * 1000, end_ms = (sb.clock + 1.3) * 1000 }
    tick(b, "ranged")
    vertex_eq(ui.cast_frame.tint.color_texture, { 1, 0, 0, 0.4 },
        "hunter tint: a steady cast beyond the window is unsafe")

    -- Auto Shot window face and the no-cast hidden state.
    sb.cast = nil
    sb.clock = t0 + 2.3 -- window opens at t0+2.15 for a 0.15 s latency
    tick(b, "ranged")
    eq(ui.cast_frame.shown, true, "hunter window: the hidden Auto Shot window draws the bar")
    eq(ui.cast_frame.text.text, "Auto Shot 0.5", "hunter window: Auto Shot + remaining text")
    eq(ui.cast_frame.tint.shown, false, "hunter window: the window face carries no clip tint")
    sb.clock = t0 + 1.0
    tick(b, "ranged")
    eq(ui.cast_frame.shown, false, "hunter window: hidden outside the cast window")

    -- Melee re-anchor while the cast bar is visible (bars locked).
    sb.cast = { name = "Steady Shot", spell_id = 56641, start_ms = sb.clock * 1000, end_ms = (sb.clock + 1.5) * 1000 }
    tick(b, "ranged")
    eq(ui.cast_frame.shown, true, "hunter anchor: cast bar visible again")
    eq(ui.melee_anchored, true, "hunter anchor: melee bars re-anchor under the cast bar")
    local restores_before = #sb.lwin_restores
    sb.cast = nil
    sb.clock = sb.clock + 3.0 -- past the window: the cast face hides
    tick(b, "ranged")
    eq(ui.cast_frame.shown, false, "hunter anchor: cast bar hidden")
    eq(ui.melee_anchored, false, "hunter anchor: melee bars return to stored positions")
    check(#sb.lwin_restores > restores_before,
        "hunter anchor: restoring issued LibWindow.RestorePosition")

    -- Range helper: the four states and the all-unknown/absent-target hides.
    ST.has_attackable_target = true
    ui.helper_state = nil
    sb.is_spell_in_range = function(spell)
        return spell == ui.wing_clip_token
    end
    tick(b, "ranged")
    eq(ui.range_helper.shown, true, "hunter range: shown with an attackable target")
    vertex_eq(ui.range_helper.tex.color_texture, { 0.20, 0.85, 0.25, 1 },
        "hunter range: melee state colour")
    sb.is_spell_in_range = function(spell)
        if spell == ui.wing_clip_token then return false end
        return false
    end
    sb.target_yards = 7
    tick(b, "ranged")
    vertex_eq(ui.range_helper.tex.color_texture, { 0.98, 0.82, 0.18, 1 },
        "hunter range: sweet-spot state colour")
    sb.target_yards = 20
    sb.is_spell_in_range = function(spell)
        return spell == ui.auto_shot_token
    end
    tick(b, "ranged")
    vertex_eq(ui.range_helper.tex.color_texture, { 0.20, 0.55, 1.00, 1 },
        "hunter range: ranged state colour")
    sb.is_spell_in_range = function() return false end
    tick(b, "ranged")
    vertex_eq(ui.range_helper.tex.color_texture, { 0.50, 0.50, 0.50, 1 },
        "hunter range: out-of-range state colour")
    sb.is_spell_in_range = function() return nil end
    sb.target_yards = nil
    tick(b, "ranged")
    eq(ui.range_helper.shown, false, "hunter range: every probe unknown hides the strip")
    ST.has_attackable_target = false
    tick(b, "ranged")
    eq(ui.range_helper.shown, false, "hunter range: no attackable target keeps it hidden")
    ST.has_attackable_target = true

    -- Rapid Fire bar: aura duration, value and label.
    sb.clock = 40.0
    set_player_auras(b, {
        { name = "Rapid Fire", spell_id = 3045, duration = 15, expiration = 50.0 },
    })
    tick(b, "ranged")
    eq(ui.rapid_fire_bar.shown, true, "hunter rapid fire: bar shows with the aura")
    eq(ui.rapid_fire_bar.min_value, 0, "hunter rapid fire: min value 0")
    near(ui.rapid_fire_bar.max_value, 15, 1e-9, "hunter rapid fire: max is the aura duration")
    near(ui.rapid_fire_bar.value, 10, 1e-9, "hunter rapid fire: value is the remaining time")
    eq(ui.rapid_fire_bar.label.text, "10s", "hunter rapid fire: whole-second label")
    set_player_auras(b, {})
    sb.clock = 40.2
    tick(b, "ranged")
    eq(ui.rapid_fire_bar.shown, false, "hunter rapid fire: hides without the aura")
    cdb.hunter_rapid_fire_bar_enabled = false
    set_player_auras(b, {
        { name = "Rapid Fire", spell_id = 3045, duration = 15, expiration = 50.0 },
    })
    sb.clock = 40.4
    tick(b, "ranged")
    eq(ui.rapid_fire_bar.shown, false, "hunter rapid fire: the option gate hides it")
    cdb.hunter_rapid_fire_bar_enabled = true

    -- Aspect icon: aura id -> client spell texture.
    set_player_auras(b, {
        { name = "Aspect of the Hawk", spell_id = 13165 },
    })
    sb.clock = 41.0
    tick(b, "ranged")
    eq(ui.aspect_icon.shown, true, "hunter aspect: icon shows with the aura")
    eq(ui.aspect_icon.tex.texture, "icon_hawk", "hunter aspect: texture from the client spell data")
    set_player_auras(b, {})
    sb.clock = 41.4
    tick(b, "ranged")
    eq(ui.aspect_icon.shown, false, "hunter aspect: hidden without the aura")

    -- A disabled ranged hand silences the whole set, cast included.
    db.enabled = false
    sb.cast = { name = "Steady Shot", spell_id = 56641, start_ms = sb.clock * 1000, end_ms = (sb.clock + 1.5) * 1000 }
    tick(b, "ranged")
    eq(ui.cast_frame.shown, false, "hunter gate: a disabled ranged hand hides the cast bar")
    db.enabled = true
    sb.cast = nil

    -- Queue colouring through the real event chain.
    sb.current_spell = 2973
    ST:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
    eq(ST.raptor_strike_queued, true, "hunter queue: a current Raptor Strike sets the flag")
    vertex_eq(mh_vf.bar.color, db_color(cdb.raptor_strike_color),
        "hunter queue: the mainhand bar takes the Raptor Strike tint")
    ST:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 2973)
    eq(ST.raptor_strike_queued, false, "hunter queue: the succeeded cast clears the flag")
    sb.current_spell = 56641
    ST:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
    eq(ST.steady_shot_queued, false, "hunter queue: Steady Shot colouring is off by default")
end

-- HUNTER G1 (Era boot): INTERRUPTED/FAILED clears the Raptor/Steady tint by id;
-- the current-spell probe re-arms a live queue (self-heal intact).
do
    local b = boot({ class = "HUNTER", project = 2, interface = 11509 })
    local sb = b.sb
    local ST = b.ST
    eq(b.st.family, "ERA", "hunter G1: the Era boot maps to ERA")
    ST.raptor_strike_queued = true
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-9", 2973)
    eq(ST.raptor_strike_queued, false, "hunter G1: INTERRUPTED clears the Raptor flag")
    ST.steady_shot_queued = true
    ST:UNIT_SPELLCAST_FAILED("UNIT_SPELLCAST_FAILED", "player", "cast-9", 56641)
    eq(ST.steady_shot_queued, false, "hunter G1: FAILED clears the Steady flag")
    ST.raptor_strike_queued = true
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-9", 403)
    eq(ST.raptor_strike_queued, true, "hunter G1: an unrelated interrupt keeps the flag")
    ST:UNIT_SPELLCAST_FAILED("UNIT_SPELLCAST_FAILED", "player", nil, nil)
    eq(ST.raptor_strike_queued, false, "hunter G1: a nil token clears the flag")
    sb.current_spell = 2973
    ST:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
    eq(ST.raptor_strike_queued, true, "hunter G1: the current-spell probe re-arms a live queue")
    sb.current_spell = nil
end

-- HUNTER G1 (TBC boot): name-carrying payloads (Anniversary R1) clear too.
do
    local b = boot({ class = "HUNTER", project = 5, interface = 20506 })
    local sb = b.sb
    local ST = b.ST
    eq(b.st.family, "TBC", "hunter G1: the Anniversary boot maps to TBC")
    ST.raptor_strike_queued = true
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-9", "Raptor Strike")
    eq(ST.raptor_strike_queued, false, "hunter G1: a Raptor name interrupt clears the flag")
    ST.steady_shot_queued = true
    ST:UNIT_SPELLCAST_FAILED("UNIT_SPELLCAST_FAILED", "player", "cast-9", "Steady Shot")
    eq(ST.steady_shot_queued, false, "hunter G1: a Steady name failure clears the flag")
    class_db(b).enable_steady_shot_color = true
    sb.current_spell = "Steady Shot"
    ST:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
    eq(ST.steady_shot_queued, true, "hunter G1: the TBC name probe re-arms a live queue")
    sb.current_spell = nil
end

-- DRUID: the energy tick column, the form label and the target debuff bars.
do
    local b = boot({ class = "DRUID" })
    local sb = b.sb
    local ST = b.ST
    local vf = visuals(b, "mainhand")
    local cdb = class_db(b)
    local w, h = vf.width, vf.height

    -- Energy tick: anchored on the first sample, fraction over the 2 s cycle.
    sb.power_type, sb.power.default = 3, 40
    sb.clock = 0.0
    tick(b, "mainhand")
    eq(vf.druid_energy_tick_bg.shown, true, "druid tick: column shows in cat form (energy)")
    near(vf.druid_energy_tick_fill.height, 0, 1e-9, "druid tick: fraction starts at 0")
    vertex_eq(vf.druid_energy_tick_fill.color, db_color(cdb.druid_energy_tick_color),
        "druid tick: configured fill colour")
    sb.clock = 0.5
    tick(b, "mainhand")
    near(vf.druid_energy_tick_fill.height, h * 0.25, 1e-9, "druid tick: fill is the cycle fraction")
    -- A natural gain (19..22) re-anchors; a small gain does not.
    sb.power.default = 59
    sb.clock = 1.0
    tick(b, "mainhand")
    near(vf.druid_energy_tick_fill.height, 0, 1e-9, "druid tick: a 19-point gain re-anchors the cycle")
    sb.power.default = 60
    sb.clock = 1.5
    tick(b, "mainhand")
    near(vf.druid_energy_tick_fill.height, h * 0.25, 1e-9, "druid tick: a small gain never re-anchors")
    -- Must NOT: another power type (mana) hides the column.
    sb.power_type = 0
    tick(b, "mainhand")
    eq(vf.druid_energy_tick_bg.shown, false, "druid tick: hidden outside cat form")
    -- Must NOT: option off performs no power reads at all.
    cdb.show_druid_energy_tick = false
    sb.power_type = 3
    local reads = sb.power_reads
    tick(b, "mainhand")
    eq(sb.power_reads, reads, "druid tick: option off performs no power reads")
    eq(vf.druid_energy_tick_bg.shown, false, "druid tick: option off hides the column")
    cdb.show_druid_energy_tick = true

    -- Form label through the real UPDATE_SHAPESHIFT_FORM dispatch.
    sb.form_index = 1
    sb.power_type = 1
    ST:UPDATE_SHAPESHIFT_FORM("UPDATE_SHAPESHIFT_FORM")
    tick(b, "mainhand")
    eq(vf.druid_form_label.shown, true, "druid label: shown in form")
    eq(vf.druid_form_label.text, "Bear", "druid label: bear form from the rage power type")
    sb.form_index = 3
    sb.power_type = 3
    ST:UPDATE_SHAPESHIFT_FORM("UPDATE_SHAPESHIFT_FORM")
    tick(b, "mainhand")
    eq(vf.druid_form_label.text, "Cat", "druid label: cat form from the energy power type")
    sb.power_type = 0
    tick(b, "mainhand")
    eq(vf.druid_form_label.text, "Caster", "druid label: mana inside a form reads Caster")
    sb.form_index = 0
    sb.power_type = 3
    ST:UPDATE_SHAPESHIFT_FORM("UPDATE_SHAPESHIFT_FORM")
    tick(b, "mainhand")
    eq(vf.druid_form_label.shown, false, "druid label: hidden without a form")

    -- Debuff bars: one throttled target scan feeds Mangle/Rip/Rake.
    sb.clock = 10.0
    set_target_auras(b, {
        { name = "Rip", spell_id = 1079, count = 1, duration = 12, expiration = 22.0, source = "player" },
    })
    tick(b, "mainhand")
    local rip = vf.druid_debuff.rip
    eq(rip.bg.shown, true, "druid debuffs: Rip bar shows")
    near(rip.fill.width, w * 1.0, 1e-9, "druid debuffs: full-duration fill")
    eq(rip.glow.shown, false, "druid debuffs: no glow outside the final 4 s")
    sb.clock = 20.0
    tick(b, "mainhand")
    near(rip.fill.width, w * (2.0 / 12.0), 1e-9, "druid debuffs: fill follows the countdown")
    eq(rip.label.text, "2", "druid debuffs: whole-second label")
    eq(rip.glow.shown, true, "druid debuffs: glow inside the final 4 s")
    -- Name-fallback matching (no spell id on the payload).
    set_target_auras(b, {
        { name = "Mangle", duration = 12, expiration = 30.0, source = "player" },
    })
    sb.clock = 21.0
    tick(b, "mainhand")
    eq(vf.druid_debuff.mangle.bg.shown, true, "druid debuffs: the localized-name fallback matches Mangle")
    -- Must NOT: foreign source and the option gate.
    set_target_auras(b, {
        { name = "Rip", spell_id = 1079, duration = 12, expiration = 30.0, source = "other" },
    })
    sb.clock = 22.0
    tick(b, "mainhand")
    eq(rip.bg.shown, false, "druid debuffs: a foreign-source debuff is ignored")
    set_target_auras(b, {
        { name = "Rip", spell_id = 1079, duration = 12, expiration = 30.0, source = "player" },
    })
    cdb.show_druid_rip_bar = false
    sb.clock = 22.2
    tick(b, "mainhand")
    eq(rip.bg.shown, false, "druid debuffs: the option off hides the bar")
    cdb.show_druid_rip_bar = true

    -- Queue colouring (Maul) through the real dispatch and power event.
    sb.current_spell = 6807
    ST:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
    eq(ST.maul_queued, true, "druid queue: a current Maul sets the flag")
    vertex_eq(vf.bar.color, db_color(cdb.maul_color), "druid queue: the bar takes the Maul tint")
    sb.power.default = 10
    ST:UNIT_POWER_FREQUENT("UNIT_POWER_FREQUENT", "player", "RAGE")
    vertex_eq(vf.bar.color, db_color(cdb.insufficient_rage_color),
        "druid queue: insufficient rage tints grey")
end

-- DRUID G1 (Era boot): INTERRUPTED/FAILED clears the Maul tint by id; the
-- current-spell probe re-arms a live queue (self-heal intact).
do
    local b = boot({ class = "DRUID", project = 2, interface = 11509 })
    local sb = b.sb
    local ST = b.ST
    eq(b.st.family, "ERA", "druid G1: the Era boot maps to ERA")
    ST.maul_queued = true
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-9", 6807)
    eq(ST.maul_queued, false, "druid G1: INTERRUPTED clears the Maul flag")
    ST.maul_queued = true
    ST:UNIT_SPELLCAST_FAILED("UNIT_SPELLCAST_FAILED", "player", "cast-9", 403)
    eq(ST.maul_queued, true, "druid G1: an unrelated failure keeps the flag")
    ST:UNIT_SPELLCAST_FAILED("UNIT_SPELLCAST_FAILED", "player", nil, nil)
    eq(ST.maul_queued, false, "druid G1: a nil token clears the flag")
    sb.current_spell = 6807
    ST:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", false)
    eq(ST.maul_queued, true, "druid G1: the current-spell probe re-arms a live queue")
    sb.current_spell = nil
end

-- DRUID G1 (TBC boot): the Maul name (Anniversary) clears too.
do
    local b = boot({ class = "DRUID", project = 5, interface = 20506 })
    local ST = b.ST
    eq(b.st.family, "TBC", "druid G1: the Anniversary boot maps to TBC")
    ST.maul_queued = true
    ST:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-9", "Maul")
    eq(ST.maul_queued, false, "druid G1: a Maul name interrupt clears the flag")
end

-- SHAMAN: weave breakpoint markers + cast spark, offhand mirror, Windfury ICD,
-- Flame Shock bar, cooldown badges and shield charges.
do
    local b = boot({ class = "SHAMAN" })
    local sb = b.sb
    local ST = b.ST
    local vf = visuals(b, "mainhand")
    local oh_vf = visuals(b, "offhand")
    local cdb = class_db(b)
    local w = vf.width

    -- Zero latency so the breakpoint maths are pinned exactly.
    ST:LATENCY_CHANGED("LATENCY_CHANGED", 60, 0)

    -- Must NOT: no swing activity -> no markers.
    tick(b, "mainhand")
    eq(vf.weave_marker.shown, false, "shaman marker: hidden without an active swing")

    -- Breakpoint marker at the latest safe LB start of a 2.6 s swing.
    sb.clock = 0.0
    start_swing(b, "mainhand", 2.6, 2.6)
    tick(b, "mainhand")
    eq(vf.weave_marker.shown, true, "shaman marker: shown on an active swing")
    eq(vf.weave_marker.texture, "icon_lb", "shaman marker: LB icon from the catalogue")
    eq(vf.weave_marker.point[1], "CENTER", "shaman marker: centred anchoring")
    near(vf.weave_marker.point[4], ((2.6 - 2.5) / 2.6) * w, 1e-9,
        "shaman marker: located at the breakpoint fraction")
    vertex_eq(vf.weave_marker.color, { 0.45, 0.75, 1.0, 1 },
        "shaman marker: LB family colour at full alpha")
    eq(vf.weave_marker_top.shown, true, "shaman marker: top breakpoint icon shows")
    eq(vf.weave_marker_bottom.shown, true, "shaman marker: bottom breakpoint icon shows")

    -- Cast spark: travels from the cast start toward the projected landing.
    sb.clock = 0.26
    sb.cast = { name = "Lightning Bolt", spell_id = 403, start_ms = 260, end_ms = 2760 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "weave-1", 403)
    eq(ST.weave_is_casting, true, "shaman weave: UNIT_SPELLCAST_START begins the cast")
    near(ST.weave_cast_duration, 2.5, 1e-9, "shaman weave: live cast window duration")
    tick(b, "mainhand")
    local start_frac = 0.26 / 2.6
    eq(vf.weave_spark.shown, true, "shaman spark: shown during the cast")
    near(vf.weave_spark.point[4], start_frac * w, 1e-9, "shaman spark: starts at the cast-start fraction")
    vertex_eq(vf.weave_spark.color, { 1, 0.15, 0.15, 0.95 },
        "shaman spark: red while the cast clips the swing")
    sb.clock = 1.51
    tick(b, "mainhand")
    local prog = (1.51 - 0.26) / 2.5
    near(vf.weave_spark.point[4], (start_frac + (1 - start_frac) * prog) * w, 1e-9,
        "shaman spark: travels toward the projected landing")
    -- STOP hides the spark; the last-known family resolves on SUCCEEDED.
    sb.cast = nil
    ST:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player", "weave-1", 403)
    eq(ST.weave_is_casting, false, "shaman weave: UNIT_SPELLCAST_STOP ends the cast")
    tick(b, "mainhand")
    eq(vf.weave_spark.shown, false, "shaman spark: hidden after the cast ends")

    -- A cast that fits the swing tints the spark the shaman blue.
    start_swing(b, "mainhand", 2.6, 2.6)
    sb.clock = sb.clock + 0.05
    sb.cast = { name = "Lightning Bolt", spell_id = 403, start_ms = sb.clock * 1000, end_ms = (sb.clock + 2.5) * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "weave-2", 403)
    tick(b, "mainhand")
    vertex_eq(vf.weave_spark.color, { 0.25, 0.5, 0.75, 0.95 },
        "shaman spark: shaman blue when the cast fits the swing")

    -- Unrelated spells and non-player units never start the tracker.
    sb.cast = nil
    ST:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player", "weave-2", 403)
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-x", 56641)
    eq(ST.weave_is_casting, false, "shaman weave: an untracked spell never starts the tracker")
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "target", "cast-y", 403)
    eq(ST.weave_is_casting, false, "shaman weave: a non-player unit never starts the tracker")
    ST:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 403)
    eq(ST.weave_family, "LB", "shaman weave: SUCCEEDED records the last-known family")
    ST.weave_family = nil
    ST:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 56641)
    eq(ST.weave_family, nil, "shaman weave: an untracked SUCCEEDED leaves the family alone")

    -- Offhand spark mirror while dual-wielding.
    sb.cast = { name = "Lightning Bolt", spell_id = 403, start_ms = sb.clock * 1000, end_ms = (sb.clock + 2.5) * 1000 }
    ST:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "weave-3", 403)
    tick(b, "mainhand")
    tick(b, "offhand")
    eq(oh_vf.weave_spark_offhand.shown, true, "shaman offhand: the spark mirror shows while dual-wielding")
    near(oh_vf.weave_spark_offhand.point[4], vf.weave_spark.point[4], 1e-9,
        "shaman offhand: mirror tracks the mainhand spark")
    ST.offhand.has_weapon = false
    tick(b, "offhand")
    eq(oh_vf.weave_spark_offhand.shown, false, "shaman offhand: no offhand weapon hides the mirror")
    ST.offhand.has_weapon = true
    ST:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player", "weave-3", 403)
    sb.cast = nil

    -- Windfury ICD strip: buff + running swing; the three tint buckets.
    sb.clock = 10.0
    set_player_auras(b, { { name = "Windfury Weapon", spell_id = 8232 } })
    eq(ST.weave_windfury_active, true, "shaman windfury: the buff is tracked from the aura list")
    start_swing(b, "mainhand", 2.6, 2.6)
    sb.clock = 10.5
    tick(b, "mainhand")
    eq(vf.weave_windfury_bg.shown, true, "shaman windfury: strip shows while the buff is up")
    near(vf.weave_windfury_fill.width, 2.5, 1e-9, "shaman windfury: fill follows the 3 s ICD")
    vertex_eq(vf.weave_windfury_fill.color, { 1, 0, 0, 0.85 },
        "shaman windfury: red right after the swing")
    sb.clock = 12.0
    tick(b, "mainhand")
    near(vf.weave_windfury_fill.width, 1.0, 1e-9, "shaman windfury: fill at one second left")
    vertex_eq(vf.weave_windfury_fill.color, { 1, 0.65, 0, 0.85 }, "shaman windfury: orange mid-ICD")
    sb.clock = 12.7
    tick(b, "mainhand")
    vertex_eq(vf.weave_windfury_fill.color, { 0, 1, 0, 0.85 }, "shaman windfury: green when ready")
    set_player_auras(b, {})
    tick(b, "mainhand")
    eq(vf.weave_windfury_bg.shown, false, "shaman windfury: hidden without the buff")

    -- Flame Shock target bar: duration fill, label and the final-seconds glow.
    sb.clock = 20.0
    set_target_auras(b, {
        { name = "Flame Shock", spell_id = 8050, duration = 12, expiration = 30.0, source = "player" },
    })
    tick(b, "mainhand")
    near(vf.weave_fs_fill.width, 271 * (10 / 12), 1e-9, "shaman flame shock: fill from remaining/total")
    eq(vf.weave_fs_label.text, "10", "shaman flame shock: whole-second label")
    eq(vf.weave_fs_glow.shown, false, "shaman flame shock: no glow outside the final 4 s")
    sb.clock = 27.0
    tick(b, "mainhand")
    eq(vf.weave_fs_label.text, "3", "shaman flame shock: label counts down")
    eq(vf.weave_fs_glow.shown, true, "shaman flame shock: glow inside the final 4 s")
    cdb.show_shaman_flame_shock_bar = false
    tick(b, "mainhand")
    eq(vf.weave_fs_bg.shown, false, "shaman flame shock: the option off hides the bar")
    cdb.show_shaman_flame_shock_bar = true

    -- Cooldown badges: Stormstrike from the client cooldown, Shamanistic Rage from the
    -- aura expiry.
    sb.clock = 40.0
    sb.cooldowns[17364] = { start = sb.clock, duration = 30 }
    set_player_auras(b, {
        { name = "Shamanistic Rage", spell_id = 30823, expiration = 52.0 },
    })
    tick(b, "mainhand")
    eq(vf.weave_ss_text.text, "SS 30s", "shaman badges: SS text from the client cooldown")
    eq(vf.weave_ss_text.shown, true, "shaman badges: SS badge shown")
    eq(vf.weave_sr_text.text, "SR 12s", "shaman badges: SR text from the aura expiry")
    eq(vf.weave_sr_text.shown, true, "shaman badges: SR badge shown")
    cdb.show_shaman_cooldown_badges = false
    tick(b, "mainhand")
    eq(vf.weave_ss_text.shown, false, "shaman badges: option off hides the SS badge")
    eq(vf.weave_sr_text.shown, false, "shaman badges: option off hides the SR badge")
    cdb.show_shaman_cooldown_badges = true
    sb.cooldowns[17364] = nil
    set_player_auras(b, {})
    tick(b, "mainhand")
    eq(vf.weave_ss_text.shown, false, "shaman badges: no cooldown hides the SS badge")

    -- Shield charges: the aura scan sets type + count; the row draws per slot.
    set_player_auras(b, { { name = "Lightning Shield", spell_id = 324, count = 2 } })
    eq(ST.weave_shield_type, "lightning", "shaman shields: the shield type is tracked")
    eq(ST.weave_shield_charges, 2, "shaman shields: the charge count is tracked")
    tick(b, "mainhand")
    eq(vf.weave_shield_rects[1].shown, true, "shaman shields: slot 1 drawn")
    eq(vf.weave_shield_rects[4].shown, true, "shaman shields: four slots for lightning")
    vertex_eq(vf.weave_shield_rects[1].color, { 0.25, 0.72, 1.0, 0.90 },
        "shaman shields: a filled slot carries the shield colour")
    vertex_eq(vf.weave_shield_rects[3].color, { 0.25, 0.72, 1.0, 0.20 },
        "shaman shields: an empty slot is dimmed")
    set_player_auras(b, { { name = "Water Shield", spell_id = 24398, count = 3 } })
    tick(b, "mainhand")
    eq(vf.weave_shield_rects[3].shown, true, "shaman shields: water shield draws three slots")
    eq(vf.weave_shield_rects[4].shown, false, "shaman shields: the fourth slot hides for water")
    cdb.show_shaman_shield_charges = false
    tick(b, "mainhand")
    eq(vf.weave_shield_rects[1].shown, false, "shaman shields: option off hides the row")
    cdb.show_shaman_shield_charges = true
end

--=========================================================================================
-- 5) Pre-init safety
--=========================================================================================
-- The window between OnInitialize and the libraries reporting ready: the early
-- GCD/latency reports must be state-only, the paladin's per-frame hook must be inert
-- before its frames exist, and a re-entrant init_libs must re-run nothing.
do
    local b = build({ class = "PALADIN" })
    local sb = b.sb
    local ST = b.ST
    -- Only the vendored AceDB's own frame exists before OnInitialize; no addon frame has
    -- been created (AceDB's frame carries its own internal OnUpdate - not ours to pin).
    eq(#sb.frames, 1, "pre-init: only AceDB's frame exists before OnInitialize")
    eq(frame_named(sb, "SwedgeTimer_mainhand_AnchorFrame"), nil,
        "pre-init: no addon frame exists before OnInitialize")
    eq(ST.interfaces_are_initialised, false, "pre-init: interfaces are not initialised")

    ST:OnInitialize()
    eq(ST.mainhand.anchor_frame, nil, "pre-init: no hand frame exists yet")

    -- The libs report before the range/swing libraries are ready; every callback must be
    -- state-only in this window.
    local before = sb.touches
    ST.callback_event_handler("GCD_STARTED", 1.5, 2.0)
    eq(ST.gcd.expires, 2.0, "pre-init: GCD_STARTED records the expiry")
    ST.callback_event_handler("GCD_OVER")
    eq(ST.gcd.expires, 2.0, "pre-init: GCD_OVER inside the window is ignored (init guard)")
    ST.callback_event_handler("GCD_DURATIONS_UPDATED", 1.5, 1.5)
    eq(ST.gcd.phys_length, 1.5, "pre-init: GCD_DURATIONS_UPDATED records the lengths")
    ST.callback_event_handler("LATENCY_CHANGED", 60, 150)
    eq(ST.latency.world_ms, 150, "pre-init: LATENCY_CHANGED records the reading")
    eq(sb.touches, before, "pre-init: library reports touch no frame")
    eq(#sb.frames, 1, "pre-init: still no addon frame exists")

    -- The paladin's per-frame hook guards on the hand's anchor frame directly: it is
    -- inert in the pre-construction window (its guide/HUD branches are unloaded here).
    ST.PALADIN.on_bar_update(ST, "mainhand")
    eq(sb.touches, before, "pre-init: the paladin hook is inert before construction")

    -- The client then completes init through the real report callbacks.
    sb.lgc_cb["GCD_DURATIONS_UPDATED"]("GCD_DURATIONS_UPDATED", 1.5, 1.5)
    sb.llm_cb["LATENCY_CHANGED"]("LATENCY_CHANGED", 60, 150)
    sb.stl_cb["SWING_TIMER_INFO_INITIALIZED"]()
    sb.lrc_cb["CHECKERS_CHANGED"]()
    eq(ST.interfaces_are_initialised, true, "pre-init: the real reports complete init")
    eq(#sb.frames, 28, "pre-init: construction then created the four hand frames plus the "
        .. "paladin seal-icon set (container, 2 cooldowns, 2 timer frames)")
    eq(type(ST:get_bar_frame("mainhand"):GetScript("OnUpdate")), "function",
        "pre-init: the OnUpdate script is registered at construction")
    eq(sb.after[1].delay, 5, "pre-init: the init deadline is armed at 5 s")
    check(ST.init_deadline_fired == nil, "pre-init: the deadline never had to fire")

    -- init_libs is idempotent: a second call (e.g. a late report) re-runs nothing.
    local settled = sb.touches
    ST:init_libs()
    eq(sb.touches, settled, "pre-init: a re-entrant init_libs is a no-op")
end

--=========================================================================================
-- 6) Family gates
--=========================================================================================
-- The CLEU registration matrix, the Retail inert-stand-in path, the Forever
-- (Mainline-code, source-engine) paths that must NOT be gated on is_mainline, and the
-- compat interface-version fallback.
do
    -- Classic profile: family detection, probe spell and the CLEU matrix.
    local classic = boot({ class = "PALADIN" })
    eq(classic.st.family, "WRATH", "family: the wrath project id maps to WRATH")
    eq(classic.st.is_retail, false, "family: wrath is not retail")
    eq(classic.st.is_mainline, false, "family: wrath is not mainline code")
    eq(classic.st.gcd_probe_spell_id, 29515, "family: the classic gcd probe spell")
    eq(classic.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], 1,
        "family: the classic paladin registers the CLEU")

    local classic_warrior = boot({ class = "WARRIOR" })
    eq(classic_warrior.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], 1,
        "family: the classic warrior registers the CLEU")
    local classic_hunter = boot({ class = "HUNTER" })
    eq(classic_hunter.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], 1,
        "family: the classic hunter registers the CLEU (G2: neutral pre-pass)")
    local classic_shaman = boot({ class = "SHAMAN" })
    eq(classic_shaman.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], 1,
        "family: the classic shaman registers the CLEU (G2: neutral pre-pass)")
    local classic_druid = boot({ class = "DRUID" })
    eq(classic_druid.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], 1,
        "family: the classic druid registers the CLEU (G2: neutral pre-pass)")
    local classic_rogue = boot({ class = "ROGUE" })
    eq(classic_rogue.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], 1,
        "family: the classic rogue registers the CLEU (G2: neutral pre-pass)")

    -- Retail: the inert stand-in keeps the whole init arc alive, prints one notice and
    -- never registers the CLEU; the twist band is retail-gated.
    local retail_paladin = boot({ class = "PALADIN", project = 1, interface = 120100, engine = "absent" })
    eq(retail_paladin.st.family, "RETAIL", "family: project id 1 maps to RETAIL")
    eq(retail_paladin.st.is_retail, true, "family: retail is flagged as retail")
    eq(retail_paladin.st.is_mainline, true, "family: retail is mainline code")
    eq(retail_paladin.st.gcd_probe_spell_id, 61304, "family: the retail gcd probe spell")
    eq(retail_paladin.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], nil,
        "family: the retail paladin never registers the CLEU")
    eq(retail_paladin.ST.swing_engine, "inert-standin", "family: retail runs the inert stand-in")
    eq(retail_paladin.ST.interfaces_are_initialised, true, "family: retail still completes init")
    local notice
    for i = 1, #retail_paladin.sb.prints do
        if retail_paladin.sb.prints[i]:find("Swing timer bars are unavailable", 1, true) then
            notice = true
        end
    end
    check(notice, "family: retail prints the one-time unavailability notice")
    set_player_auras(retail_paladin, {
        { name = "Seal of Command", spell_id = 20375 },
        { name = "Seal of Righteousness", spell_id = 21084 },
    })
    start_swing(retail_paladin, "mainhand", 2.6, 2.6)
    tick(retail_paladin, "mainhand")
    local rvf = visuals(retail_paladin, "mainhand")
    eq(rvf.twist_band.shown, false, "family: retail hides the twist band")
    eq(rvf.twist_text.shown, false, "family: retail hides the twist text")
    eq(rvf.twist_text.text, "", "family: retail clears the twist text")
    eq(rvf.judgement_marker.shown, false, "family: retail hides the judgement marker")
    eq(rvf.seal_icons.frame.shown, false, "family: retail hides the seal icons")
    eq(rvf.seal_icons.slots[1].icon.shown, false, "family: retail hides seal slot 1 with seals up")

    local retail_warrior = boot({ class = "WARRIOR", project = 1, interface = 120100, engine = "absent" })
    eq(retail_warrior.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], nil,
        "family: the retail warrior never registers the CLEU")

    -- Forever: Mainline-code but driven by the source swing engine - the CLEU stays off
    -- and yet the twist band (paladin) and weave marker (shaman) must both show.
    local forever_paladin = boot({ class = "PALADIN", project = 18, interface = 16001, engine = "source" })
    eq(forever_paladin.st.family, "FOREVER", "family: CAMELOT maps to FOREVER")
    eq(forever_paladin.st.is_retail, false, "family: forever is not retail")
    eq(forever_paladin.st.is_mainline, true, "family: forever is mainline code")
    eq(forever_paladin.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], nil,
        "family: forever never registers the CLEU")
    eq(forever_paladin.ST.swing_engine, "forever-source", "family: forever runs the source swing engine")
    set_player_auras(forever_paladin, {
        { name = "Seal of Command", spell_id = 20375 },
        { name = "Seal of Righteousness", spell_id = 21084 },
    })
    start_swing(forever_paladin, "mainhand", 2.6, 2.6)
    forever_paladin.sb.clock = 1.0
    tick(forever_paladin, "mainhand")
    eq(visuals(forever_paladin, "mainhand").twist_band.shown, true,
        "family: the Forever paladin keeps the twist band (not gated on is_mainline)")
    -- The restored bar visuals are gated on is_retail, not is_mainline: seals with
    -- expiries drive the icons, and a Judgement cooldown inside the swing draws
    -- the marker, on the Forever client too.
    set_player_auras(forever_paladin, {
        { name = "Seal of Command", spell_id = 20375, expiration = 25 },
        { name = "Seal of Blood", spell_id = 31892, expiration = 20 },
    })
    forever_paladin.sb.cooldowns[20271] = { start = -6.5, duration = 8 }
    tick(forever_paladin, "mainhand")
    local fvf = visuals(forever_paladin, "mainhand")
    eq(fvf.seal_icons.slots[1].icon.shown, true,
        "family: the Forever paladin keeps the seal icons (not gated on is_mainline)")
    eq(fvf.seal_icons.slots[2].icon.shown, true,
        "family: the Forever paladin keeps seal slot 2 while twisting")
    eq(fvf.judgement_marker.shown, true,
        "family: the Forever paladin keeps the judgement marker (not gated on is_mainline)")

    local forever_shaman = boot({ class = "SHAMAN", project = 18, interface = 16001, engine = "source" })
    eq(forever_shaman.sb.events["COMBAT_LOG_EVENT_UNFILTERED"], nil,
        "family: the forever shaman never registers the CLEU")
    forever_shaman.sb.clock = 0.0
    start_swing(forever_shaman, "mainhand", 2.6, 2.6)
    tick(forever_shaman, "mainhand")
    eq(visuals(forever_shaman, "mainhand").weave_marker.shown, true,
        "family: the Forever shaman keeps the weave breakpoint marker (not gated on is_mainline)")

    -- Interface fallback (no WOW_PROJECT_ID at all): >= 16000 buckets as FOREVER before
    -- the major==1 rule can mislabel it as Era; 11509 stays Era.
    local fallback_forever = build({ class = "PALADIN", project = false, interface = 16001 })
    eq(fallback_forever.st.family, "FOREVER",
        "family: interface 16001 without a project id falls back to FOREVER")
    eq(fallback_forever.st.is_mainline, true, "family: the fallback FOREVER is mainline code")
    local fallback_era = build({ class = "PALADIN", project = false, interface = 11509 })
    eq(fallback_era.st.family, "ERA", "family: interface 11509 without a project id falls back to ERA")
    eq(fallback_era.st.is_mainline, false, "family: the fallback ERA is not mainline code")
end

--=========================================================================================
-- 7) Output policy and error isolation
--=========================================================================================
-- Audit finding F12 (bench/deep_audit_2026-10-19.md:30) claimed bars.lua printed through
-- the client's raw global print. The file itself is the source of truth: it used to alias
-- print to st.utils.print_msg, so the message was already chat output - but the alias
-- made the call site unreadable (and that ambiguity is what the finding tripped over).
-- The policy that replaced it, pinned here:
--   - no bare print call survives anywhere in bars.lua (source scan, comments included),
--   - a refused design-mode element registration is reported through the chat frame and
--     never touches the client's global print,
--   - the pips row's design template degrades to "no cells" instead of indexing a nil
--     table when the geometry is degenerate,
--   - a throwing LibDataBroker feed is isolated by the bar's own per-tick guard instead
--     of escaping the tick.
do
    -- The source scan: "st.utils.print_msg(" never contains "print(", so every hit here
    -- is a bare call to the client's global print - live code or a commented-out debug
    -- line alike.
    local src_file = io.open(ROOT .. "bars.lua", "r")
    local src = src_file and src_file:read("*a") or nil
    if src_file then src_file:close() end
    check(src ~= nil, "output policy: bars.lua is readable")
    local bare = 0
    if src then
        for line in src:gmatch("[^\n]+") do
            if line:find("print%(") then
                bare = bare + 1
            end
        end
    end
    eq(bare, 0, "output policy: bars.lua calls no bare print (chat output is st.utils.print_msg)")

    -- A design-mode registry that refuses the element: the module must report it through
    -- the addon's chat path (DEFAULT_CHAT_FRAME), never through the client's global print.
    local b = boot({ class = "PALADIN" })
    local sb = b.sb
    b.st.designmode = {
        registry = { register = function() return nil, "duplicate element key 'x'" end },
        register_template = function() end,
    }
    local parent = { CreateTexture = function() return {} end }
    local before = #sb.prints
    local pips = b.ST:new_pips(parent, { design = { key = "x" } })
    check(pips ~= nil, "output policy: the pips widget is built even when the registration is refused")
    eq(#sb.raw_prints, 0, "output policy: the client's global print is never called by bars.lua")
    local reported = false
    for i = before + 1, #sb.prints do
        if sb.prints[i]:find("pips element not registered", 1, true)
            and sb.prints[i]:find("duplicate element key", 1, true) then
            reported = true
        end
    end
    check(reported, "output policy: a refused design registration is reported through the chat frame")

    -- Degenerate geometry: size 0 leaves row_boxes without cells. The template must
    -- degrade to "no cells" (its documented contract) instead of indexing a nil table.
    local g = boot({ class = "PALADIN" })
    local tpl
    g.st.designmode = {
        registry = { register = function() return { key = "y" } end },
        register_template = function(t) tpl = t end,
    }
    g.st.design = { row_boxes = function() return nil end }
    local degenerate = g.ST:new_pips({ CreateTexture = function() return {} end },
        { design = { key = "y" }, size = 0 })
    check(degenerate ~= nil, "output policy: a degenerate pips row still builds")
    check(tpl ~= nil, "output policy: the degenerate pips row still registers its template")
    local ok_cells, cells = pcall(function() return tpl.get_cells() end)
    check(ok_cells, "output policy: the degenerate pips template degrades instead of raising")
    eq(cells, nil, "output policy: the degenerate pips template reports no cells")

    -- A throwing broker feed must not escape the bar tick: the bar's own per-tick guard
    -- isolates it and counts it at its own site.
    local l = boot({ class = "PALADIN" })
    l.st.ldb.update = function() error("broker boom") end
    start_swing(l, "mainhand", 2.6, 2.6)
    local ok_tick = pcall(tick, l, "mainhand")
    check(ok_tick, "isolation: a throwing LibDataBroker feed does not escape the bar tick")
    local errs = l.ST.bar_hook_errors
    check(errs ~= nil and errs.by_site["ldb:update"] == 1,
        "isolation: the throwing feed is counted at its own isolation site")
end

--=========================================================================================
-- 8) F10: ONE shared guard (the isolation contract lives in guard.lua)
--
-- The contract (first throw prints once, every throw counts, quarantine after 25,
-- degrade to the caller's own result) used to be copy-pasted into six modules with
-- six quarantine constants, and the copies had already drifted. It now lives in one
-- place. These pins hold that: the shared module owns the threshold, the once-only
-- report and the counter table; every consumer keeps only its own wording and its
-- own site keys.
--=========================================================================================
do
    local function read_file(path)
        local f = io.open(ROOT .. path, "r")
        local text = f and f:read("*a") or nil
        if f then f:close() end
        return text
    end
    local guard_src = read_file("guard.lua")
    check(guard_src ~= nil, "the shared guard module is readable")
    check(guard_src:find("st.guard.QUARANTINE_THROWS = 25", 1, true) ~= nil,
        "the shared guard owns the one quarantine threshold (25)")
    check(guard_src:find("first_reported", 1, true) ~= nil,
        "the shared guard owns the once-only report bookkeeping")
    check(guard_src:find("bar_hook_errors", 1, true) ~= nil,
        "the shared guard counts on the counter the /st diag reader expects")
    check(guard_src:find("function st.guard.run", 1, true) ~= nil,
        "the shared guard exposes the one run entry point")
    for _, path in ipairs({ "bars.lua", "hud.lua", "nextaction_ui.lua",
        "practice_ui.lua", "rotationtext.lua" }) do
        local src = read_file(path)
        check(src ~= nil, path .. ": the consumer module is readable")
        check(src:find("QUARANTINE_THROWS = ", 1, true) == nil,
            path .. ": no second quarantine threshold")
        check(src:find("errors.by_site", 1, true) == nil,
            path .. ": no second counter bookkeeping")
        check(src:find("st.guard.", 1, true) ~= nil,
            path .. ": the module delegates to the shared guard")
    end
    -- The wording stays with the call site (the shared module never hard-codes it).
    local bars_src = read_file("bars.lua")
    check(bars_src:find('st.guard.label("zone", "Bar update")', 1, true) ~= nil,
        "bars: the bar wording stays at the call site")
end

--=========================================================================================
-- 9) Statusbar texture: the operator's default, the LSM registration, and the
--    nil-fetch degradation
--
-- The operator's texture (Media/StatusBar/Wglass.tga) is the DEFAULT status-bar
-- texture for the addon's progress bars - the swing bar and the GCD underlay. It is
-- registered in the "statusbar" registry, so it shows up in the existing texture
-- dropdown (values = LSM:HashTable("statusbar")) with no new widget. A fetch that
-- comes back nil must degrade to a shipped texture instead of leaving the bar
-- textureless, and a dead registry must still leave the bar with a texture.
--=========================================================================================
do
    local b = boot({ class = "PALADIN" })
    local sb = b.sb

    -- The media registration: the key the dropdown shows, in the statusbar registry,
    -- pointing at the operator's file.
    local wglass_registered = false
    local minimalist_registered = false
    for _, reg in ipairs(sb.lsm_registers) do
        if reg.media == "statusbar" then
            if reg.key == "Wglass"
                and reg.path == "Interface\\Addons\\SwedgeTimer\\Media\\StatusBar\\Wglass.tga" then
                wglass_registered = true
            elseif reg.key == "Minimalist" then
                minimalist_registered = true
            end
        end
    end
    check(wglass_registered,
        "statusbar: the Wglass medium is registered in the statusbar registry with the operator's path")
    check(minimalist_registered,
        "statusbar: the Minimalist fallback key stays registered")

    -- The shipped default: the progress bars take the operator's texture.
    local db_mainhand = hand_db(b, "mainhand")
    eq(db_mainhand.bar_texture_key, "Wglass", "statusbar: the swing bar's default is Wglass")
    eq(db_mainhand.gcd_texture_key, "Wglass", "statusbar: the GCD underlay's default is Wglass")
    -- The deadzone is a MARKER (a shaded latency region), not a progress bar: it keeps
    -- the plain fill and does not follow the progress bars' texture default.
    eq(db_mainhand.deadzone_texture_key, "Solid", "statusbar: the deadzone marker keeps Solid")
    local vf = visuals(b, "mainhand")
    eq(vf.bar.texture, "Texture\\Wglass", "statusbar: the swing bar renders the operator's texture")
    eq(vf.gcd_bar.texture, "Texture\\Wglass", "statusbar: the GCD underlay renders the operator's texture")
    eq(vf.deadzone.texture, "Texture\\Solid", "statusbar: the deadzone marker renders Solid")

    -- Degradation 1: the requested key fetches nil -> the shipped fallback key.
    local b2 = boot({ class = "PALADIN", lsm_missing_key = "Wglass" })
    local vf2 = visuals(b2, "mainhand")
    eq(vf2.bar.texture, "Texture\\Minimalist",
        "statusbar: a nil fetch degrades the swing bar to the shipped Minimalist texture")
    eq(vf2.gcd_bar.texture, "Texture\\Minimalist",
        "statusbar: a nil fetch degrades the GCD underlay to the shipped Minimalist texture")
    check(vf2.bar.texture ~= nil and vf2.gcd_bar.texture ~= nil,
        "statusbar: a nil fetch never leaves a bar textureless")

    -- Degradation 2: EVERY statusbar fetch comes back nil -> the client's white pixel.
    local b3 = boot({ class = "PALADIN", lsm_missing_all = true })
    local vf3 = visuals(b3, "mainhand")
    eq(vf3.bar.texture, "Interface\\Buttons\\WHITE8X8",
        "statusbar: a dead media registry still leaves the swing bar with the client's white pixel")
    eq(vf3.gcd_bar.texture, "Interface\\Buttons\\WHITE8X8",
        "statusbar: a dead media registry still leaves the GCD underlay textured")
    check(vf3.deadzone.texture ~= nil,
        "statusbar: a dead media registry still leaves the deadzone textured")
    check(vf3.bar.texture ~= nil and vf3.gcd_bar.texture ~= nil,
        "statusbar: a dead media registry never leaves a bar textureless")
end

--=========================================================================================
-- 10) The font chain: a bar text never carries a nil font
--
-- The bar texts are written per frame, so every one of them must carry a font
-- before its first SetText - a FontString with no font throws "Font not set" on a
-- real client. The shared chain (utils.lua) resolves the LSM key and falls back
-- through STANDARD_TEXT_FONT to the classic client font, so a key that no longer
-- resolves (the font lives in another addon's LSM registration) degrades instead
-- of handing SetFont a nil path.
--=========================================================================================
do
    -- The normal path: the media font is the one that lands.
    local b = boot({ class = "PALADIN" })
    local vf = visuals(b, "mainhand")
    check(vf.left_text:GetFont() ~= nil, "font: the left bar text carries a font")
    check(vf.center_text:GetFont() ~= nil, "font: the center bar text carries a font")
    check(vf.right_text:GetFont() ~= nil, "font: the right bar text carries a font")
    eq(vf.left_text:GetFont(), "Fonts\\LSM.ttf", "font: the left bar text uses the media font")

    -- The degradation path: the font key no longer resolves. The bar build must
    -- not throw (the old path handed SetFont a nil) and the texts must still
    -- carry a font that exists.
    local ok, err = pcall(function()
        local b2 = boot({ class = "PALADIN", lsm_missing_font = true })
        local vf2 = visuals(b2, "mainhand")
        check(vf2.left_text:GetFont() ~= nil,
            "font: an unresolvable font key still leaves the left text with a font")
        check(vf2.center_text:GetFont() ~= nil,
            "font: an unresolvable font key still leaves the center text with a font")
        check(vf2.right_text:GetFont() ~= nil,
            "font: an unresolvable font key still leaves the right text with a font")
        eq(vf2.left_text:GetFont(), "Fonts\\FRIZQT__.TTF",
            "font: an unresolvable font key falls back to the standard client font")
    end)
    check(ok, "font: an unresolvable font key never throws out of the bar build ("
        .. tostring(err) .. ")")

    -- Source: bars.lua has no direct SetFont call - the shared chain owns every font.
    local fh = assert(io.open(ROOT .. "bars.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    check(src:find(":SetFont(", 1, true) == nil,
        "font: bars.lua has no direct SetFont call (the shared chain owns every font)")
    check(src:find("st.utils.fetch_font_path", 1, true) ~= nil,
        "font: bars.lua resolves the font key through the shared chain")
end

if failures == 0 then
    print("PASS  bars_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  bars_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
