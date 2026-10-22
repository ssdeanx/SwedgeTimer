-- tests/paladin_state.lua: offline tests for the paladin module's build-out round-1
-- additions (classes/paladin.lua): P1 twist hit-rate counters + badge, P2 JotC
-- uptime mini-bar (scan + melee refresh + swipe/timer latch), P3 Bloodlust twist-
-- window override gate (the C2 contract consumer side), P6 AoW+Exorcism overlap
-- pulse (transition guard, Retail gate, teardown), P7 seal-icon texture latch,
-- and the CD icon group (row structure, glow lead, racial probe).
--
-- The sandbox loads the REAL compat.lua + utils.lua + twist.lua + nextaction.lua +
-- classes/paladin.lua over a frame/API stub environment (the hud_state.lua
-- pattern), so the module runs against the shipped cross-client wrappers and the
-- real pure engines. The clock is controllable (GetTime/GetTimePreciseSec both
-- report it), so every throttle/latch below is exercised deterministically.
-- Run from the repo root: lua5.1 tests/paladin_state.lua

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL  " .. label) end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then failures = failures + 1; print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")") end
end
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

local function read(path)
    local f = assert(io.open(ROOT .. path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

--=========================================================================================
-- Stub widgets (the frame/texture/fontstring/line surface the paladin module touches)
--=========================================================================================
local function make_texture()
    local t = { shown = false }
    function t:SetDrawLayer() end
    function t:SetPoint(...) t.point = { ... } end
    function t:ClearAllPoints() t.point = nil end
    function t:SetSize() end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetColorTexture() end
    function t:SetTexture(tex)
        t.texture = tex
        t.set_texture_calls = (t.set_texture_calls or 0) + 1
    end
    function t:SetTexCoord() end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:Show() t.shown = true end
    function t:Hide() t.shown = false end
    function t:IsShown() return t.shown == true end
    return t
end

local function make_fontstring()
    local f = { shown = false }
    function f:GetScale() return 1 end
    function f:SetPoint(...) f.point = { ... } end
    function f:ClearAllPoints() f.point = nil end
    function f:SetJustifyH() end
    function f:SetFont(path, size, flags) f.font = { path, size, flags } end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    function f:SetText(text)
        f.text = text
        f.set_text_calls = (f.set_text_calls or 0) + 1
    end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:SetAlpha(a) f.alpha = a end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown == true end
    return f
end

local function make_line()
    local l = { shown = false }
    function l:SetDrawLayer() end
    function l:SetThickness(thickness) l.thickness = thickness end
    function l:SetColorTexture() end
    function l:SetStartPoint() end
    function l:SetEndPoint() end
    function l:Show() l.shown = true end
    function l:Hide() l.shown = false end
    function l:IsShown() return l.shown == true end
    return l
end

local function make_frame(name, parent)
    local f = { name = name, parent = parent, shown = false }
    function f:GetScale() return 1 end
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetPoint(point, anchor, rel_point, x, y)
        f.point = { point, anchor, rel_point, x, y }
    end
    function f:ClearAllPoints() f.point = nil end
    function f:GetFrameLevel() return 5 end
    function f:SetFrameLevel(level) f.level = level end
    function f:CreateTexture() return make_texture() end
    function f:CreateFontString() return make_fontstring() end
    function f:CreateLine() return make_line() end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown == true end
    -- Cooldown frame API (harmless on plain frames; unreachable there).
    function f:SetCooldown(start, duration)
        f.cooldown_sets = (f.cooldown_sets or 0) + 1
        f.cooldown_start, f.cooldown_duration = start, duration
    end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers(flag) f.hide_numbers = flag end
    return f
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- opts.project: WOW_PROJECT_ID for the client profile (nil + a non-mapping interface
-- gives the UNKNOWN family). opts.interface: GetBuildInfo's TOC version.
-- opts.db: extra class-table keys merged over the fixture's shipped defaults.
local function build(opts)
    opts = opts or {}

    local clock = 100
    local player_auras = {}
    local target_auras = {}
    local spell_infos = {}
    local known_spells = {}
    local cooldowns = {}
    local target_exists = false
    local aura_reads = 0
    local spell_info_reads = 0
    local cooldown_queries = {}
    local known_queries = {}
    local lcg_starts = {}
    local lcg_stops = {}
    local play_sounds = {}
    local timer_afters = {}

    -- Class-table fixture: the shipped paladin defaults the code under test reads
    -- (config_presets.lua ST.PALADIN.defaults), plus opts.db overrides.
    local class_db = {
        use_seal_colors = true,
        soc_color = {47, 128, 10, 1.0},
        sov_color = {192, 60, 38, 1.0},
        sol_color = {6, 140, 104, 1.0},
        sow_color = {22, 100, 117, 1.0},
        sor_color = {207, 58, 165, 1.0},
        soj_color = {204, 185, 18, 1.0},
        sob_color = {219, 97, 28, 1.0},
        sotc_color = {230, 191, 107, 1.0},
        twist_enabled = true,
        twist_feedback_enabled = true,
        twist_marker_enabled = true,
        twist_padding_mode = "None",
        twist_window_padding_ms = 0,
        lag_detection_enabled = true,
        lag_multiplier = 1.4,
        lag_offset = 15,
        twist_success_text_enabled = true,
        twist_success_text_size = 24,
        twist_success_text_duration = 1.5,
        judgement_marker_enabled = true,
        seal_icons_enabled = true,
        twist_success_glow_enabled = true,
        twist_success_glow_duration = 0.4,
        twist_sound_enabled = false,
        twist_success_sound_enabled = false,
        use_aow_glow = true,
        require_exo_ready = true,
        aow_glow_color = { 209, 198, 115, 1.0 },
        aow_glow_nlines = 12,
        aow_glow_freq = 0.1,
        aow_glow_line_length = 12,
        nextaction_enabled = true,
        nextaction_locked = true,
        nextaction_icon_size = 45,
        nextaction_x = 0,
        nextaction_y = -180,
    }
    for k, v in pairs(opts.db or {}) do class_db[k] = v end
    local hand_db = { border_width = 2, text_font = "Expressway", bar_width = 275 }

    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    if opts.project ~= nil then env.WOW_PROJECT_ID = opts.project end
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return clock end
    env.GetTime = function() return clock end
    -- WoW's client environment exposes max/min as globals (the bar code uses them).
    env.max = math.max
    env.min = math.min
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", opts.interface or 20506 end
    env.GetLocale = function() return "enUS" end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.UIParent = make_frame("UIParent")
    env.CreateFrame = function(...) return make_frame(select(2, ...), select(3, ...)) end
    env.GetSpellInfo = function(spell)
        spell_info_reads = spell_info_reads + 1
        local info = spell_infos[spell]
        if info then
            return info.name, nil, info.icon, info.cast_ms or 0, 0, 0, spell
        end
        return nil
    end
    env.GetSpellCooldown = function(spell)
        cooldown_queries[#cooldown_queries + 1] = spell
        local cd = cooldowns[spell]
        if cd == nil and type(spell) == "string" then
            -- Name-shaped query (the TBC family): match the cooldown filed
            -- under the spell's numeric id.
            for id, info in pairs(spell_infos) do
                if info.name == spell and cooldowns[id] ~= nil then
                    cd = cooldowns[id]
                    break
                end
            end
        end
        if cd then
            return cd.start or 0, cd.duration or 0, 1, 0
        end
        return 0, 0, 0, 0
    end
    env.GetSpellBaseCooldown = function() return 15000, 0 end
    env.IsSpellKnown = function(spell)
        known_queries[#known_queries + 1] = spell
        if known_spells[spell] == true then
            return true
        end
        if type(spell) == "string" then
            -- Name-shaped probe (the TBC family): match the book entry filed
            -- under the spell's numeric id.
            for id, info in pairs(spell_infos) do
                if info.name == spell and known_spells[id] == true then
                    return true
                end
            end
        end
        return false
    end
    env.UnitAura = function(unit, index)
        aura_reads = aura_reads + 1
        local list = unit == "player" and player_auras
            or unit == "target" and target_auras or nil
        local entry = list and list[index]
        if not entry then return nil end
        return entry.name, entry.icon, entry.count, entry.dispel, entry.duration,
            entry.expiration, entry.source, nil, nil, entry.spell_id
    end
    env.UnitExists = function(unit)
        if unit == "target" then return target_exists end
        return true
    end
    env.UnitGUID = function() return "Player-1" end
    env.IsSpellUsable = function() return true, false end
    env.C_EventUtils = { IsEventValid = function() return true end }
    -- Classic combat log: present on classic-line clients, absent on
    -- Mainline-code ones (Retail, Forever). compat probes it for
    -- st.cleu_supported (R3); opts.cleu == false simulates a client without it.
    if opts.cleu ~= false then
        env.CombatLogGetCurrentEventInfo = function() return "mock-payload" end
    end
    env.C_Timer = {
        After = function(delay, fn)
            timer_afters[#timer_afters + 1] = { delay = delay, fn = fn }
        end,
    }
    env.PlaySoundFile = function(path, channel)
        play_sounds[#play_sounds + 1] = { path = path, channel = channel }
    end

    local LCG = {}
    function LCG.PixelGlow_Start(frame, color, lines, freq, len, thickness, x, y, border, key)
        lcg_starts[#lcg_starts + 1] = { key = key, frame = frame }
    end
    function LCG.PixelGlow_Stop(frame, key)
        lcg_stops[#lcg_stops + 1] = { key = key, frame = frame }
    end
    local LSM = {}
    function LSM.Fetch(_, mediatype)
        if mediatype == "font" then return "Fonts\\FRIZQT__.TTF" end
        return nil
    end

    local ST
    -- LibClassicDurations (the seal-duration library) is opt-in: without it the
    -- class sees no library at all (the shipped state on every client that does
    -- not load it). opts.lcd supplies a stand-in so the registration path can
    -- be exercised - a healthy one (register no-op) or a failing one (register
    -- throws), which is what the BS-8 counter pin needs.
    local LCD_STUB = opts.lcd
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibCustomGlow-1.0" then
            return LCG
        elseif major == "LibSharedMedia-3.0" then
            return LSM
        elseif major == "LibClassicDurations" then
            return LCD_STUB
        end
        return nil
    end

    ST = {
        PALADIN = {},
        player_class = "PALADIN",
        interfaces_are_initialised = true,
        in_combat = false,
        player_guid = "Player-1",
        mainhand = { speed = 3.0, start = clock, ends_at = clock + 3.0, is_full = false },
        gcd = {},
        db = { profile = {} },
    }
    function ST.get_class_table() return class_db end
    function ST.get_hand_table() return hand_db end
    -- Mirrors of main.lua's GCD accessors (the live provider calls them; the
    -- sandbox mainhand/gcd fixtures feed them the same way).
    function ST.get_spell_gcd_duration(self)
        return self.gcd.spell_length or 1.5
    end
    function ST.get_gcd_time_before_swing_seconds(self, hand)
        if hand ~= nil then
            local key = "gcd1_spell_time_before_swing_" .. tostring(hand)
            if self.gcd[key] ~= nil then
                return self.gcd[key]
            end
        end
        return self.gcd.gcd1_spell_time_before_swing or self:get_spell_gcd_duration()
    end
    function ST.convert_color(_, t, new_alpha)
        -- Mirrors main.lua's convert_color: the optional override wins over t[4].
        return t[1] / 255, t[2] / 255, t[3] / 255, new_alpha or t[4]
    end
    function ST.get_visuals_frame(_, hand)
        local s = ST[hand]
        local anchor = s and s.anchor_frame
        return anchor and anchor.bar_frame and anchor.bar_frame.visuals_frame
    end
    function ST.get_bar_frame(_, hand)
        local s = ST[hand]
        local anchor = s and s.anchor_frame
        return anchor and anchor.bar_frame
    end
    function ST.get_bar_visuals_width_and_height(_, hand) return 200, 16 end

    ST.mainhand.anchor_frame = make_frame("SwedgeTimer_mainhand_AnchorFrame")
    ST.mainhand.anchor_frame.bar_frame = make_frame("SwedgeTimer_mainhand_BarFrame")
    local vf = make_frame("visuals")
    vf.bar = make_texture()
    ST.mainhand.anchor_frame.bar_frame.visuals_frame = vf
    -- The class-colour dispatch (main.lua's set_bar_color reaches the class hook).
    function ST.set_bar_color(self, hand)
        return self.PALADIN.set_bar_color(self, hand)
    end

    local st = {}
    local modules = { "compat.lua", "utils.lua", "twist.lua", "nextaction.lua",
        "classes/paladin.lua" }
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        chunk("SwedgeTimer", st)
        -- classes/paladin.lua registers its body as a loader (operator order
        -- 2026-10-21: only the selected class executes). Activate it here, right
        -- after its file loads - the load-time position its body had before.
        if modules[i] == "classes/paladin.lua" then
            assert(type(st.class_loaders) == "table"
                and type(st.class_loaders["PALADIN"]) == "function",
                "classes/paladin.lua registers the PALADIN loader")
            st.class_loaders["PALADIN"]()
        end
    end

    return {
        env = env, st = st, ST = ST, vf = vf,
        class_db = class_db, hand_db = hand_db,
        spell_infos = spell_infos, known_spells = known_spells, cooldowns = cooldowns,
        player_auras = player_auras, target_auras = target_auras,
        lcg_starts = lcg_starts, lcg_stops = lcg_stops,
        play_sounds = play_sounds, timer_afters = timer_afters,
        set_clock = function(v) clock = v end,
        get_clock = function() return clock end,
        aura_reads = function() return aura_reads end,
        spell_info_reads = function() return spell_info_reads end,
        cooldown_queries = cooldown_queries,
        known_queries = known_queries,
        set_target_exists = function(v) target_exists = v end,
    }
end

-- Counts the recorded LCG calls carrying `key`.
local function count_keyed(list, key)
    local n = 0
    for i = 1, #list do
        if list[i].key == key then n = n + 1 end
    end
    return n
end

--=========================================================================================
-- 1) Surface + construction (post_init builds every round-1 widget)
--=========================================================================================
local main = build({})
local ST, vf = main.ST, main.vf
local P = ST.PALADIN

check(type(P) == "table", "classes/paladin.lua loads and defines ST.PALADIN")
for _, name in ipairs({ "post_init", "note_swing_landed", "aow_exo_pulse_start",
    "aow_exo_pulse_stop", "process_aow", "update_jotc_bar", "update_cd_icons",
    "update_seal_icons", "update_reseal_marker", "on_twist_attempt", "on_successful_twist",
    "get_twist_window_time_before_swing", "setup_twist_visuals", "setup_jotc_bar",
    "setup_cd_icons" }) do
    check(type(P[name]) == "function", "ST.PALADIN." .. name .. " defined")
end

P.post_init(ST)
eq(ST.exo_on_cooldown, false, "post_init: the exo cooldown latch starts clear")
eq(ST.exo_cooldown_time, 15, "post_init: the exo cooldown falls back to 15 s")
eq(ST.twist_score_attempts, 0, "post_init: session twist attempts start at 0")
eq(ST.twist_score_successes, 0, "post_init: session twist successes start at 0")
eq(ST.aow_exo_prev, false, "post_init: the overlap latch starts false (no boot pulse)")
eq(ST.aow_exo_pulse_until, 0, "post_init: no pulse is armed at boot")
eq(ST.jotc_tracked, false, "post_init: nothing tracked before the first scan")

check(vf.twist_band ~= nil, "post_init: the twist band exists")
check(vf.twist_text ~= nil, "post_init: the twist success text exists")
check(vf.twist_score_badge ~= nil, "post_init: the twist hit-rate badge exists")
eq(vf.twist_score_badge.font[2], 12, "post_init: the badge uses its own 12 pt size")
check(vf.judgement_marker ~= nil, "post_init: the judgement marker exists")
check(vf.seal_icons ~= nil, "post_init: the seal icon set exists")
eq(#vf.seal_icons.slots, 2, "post_init: two seal icon slots")
eq(vf.seal_icons.slots[1].spell_id, 20375, "post_init: slot 1 is Seal of Command")
eq(vf.seal_icons.slots[2].spell_id, 31892, "post_init: slot 2 is Seal of Blood on TBC")
check(vf.jotc_bar ~= nil, "post_init: the JotC mini-bar exists")
check(vf.cd_icons ~= nil, "post_init: the CD icon group exists")
check(vf.reseal_marker ~= nil, "post_init: the reseal marker exists")

-- CD row structure: six core slots + one racial slot, the approved order.
local cd_slots = vf.cd_icons.slots
eq(#cd_slots, 7, "cd icons: six core slots plus one racial slot")
local cd_core_ids = { 31884, 642, 853, 1026, 2812, 633 }
for i = 1, #cd_core_ids do
    eq(cd_slots[i].spell_id, cd_core_ids[i], "cd icons: core slot " .. i .. " id")
end
eq(cd_slots[5].kind, "hw", "cd icons: the Holy Wrath slot carries the resolver kind")
eq(cd_slots[7].kind, "racial", "cd icons: the last slot is the racial probe")
eq(cd_slots[7].spell_id, nil, "cd icons: the racial slot starts unresolved")

--=========================================================================================
-- 2) P1: twist hit-rate counters + badge
--=========================================================================================
do
    local b = build({})
    local T = b.ST
    T.PALADIN.post_init(T)

    T.PALADIN.on_twist_attempt(T)
    eq(T.twist_score_attempts, 1, "P1: an attempt counts")
    eq(T.twist_score_successes, 0, "P1: the attempt is not a success")
    T.PALADIN.on_successful_twist(T)
    eq(T.twist_score_successes, 1, "P1: a success counts")
    T.PALADIN.on_twist_attempt(T)
    eq(T.twist_score_attempts, 2, "P1: a second attempt counts")
    eq(b.class_db.twist_score_attempts, nil,
        "P1: the profile mirror stays untouched without the persist option")

    -- The badge paints from the counters while in combat (one string per state).
    local badge = b.vf.twist_score_badge
    b.class_db.twist_score_enabled = true
    T.in_combat = true
    T.mainhand.speed, T.mainhand.start = 3.0, b.get_clock()
    T.mainhand.ends_at, T.mainhand.is_full = b.get_clock() + 3.0, false
    T.PALADIN.on_bar_update(T, "mainhand")
    eq(badge.shown, true, "P1 badge: shown in combat with attempts")
    eq(badge.text, "50% (1/2)", "P1 badge: success rate + counts")
    local set_calls = badge.set_text_calls
    T.PALADIN.on_bar_update(T, "mainhand")
    eq(badge.set_text_calls, set_calls, "P1 badge: no re-set while the numbers are unchanged")

    T.in_combat = false
    T.PALADIN.on_bar_update(T, "mainhand")
    eq(badge.shown, false, "P1 badge: hidden outside combat")
    T.in_combat = true
    b.class_db.twist_score_enabled = nil
    T.PALADIN.on_bar_update(T, "mainhand")
    eq(badge.shown, false, "P1 badge: option nil keeps it hidden (default off)")

    -- Persistence is opt-in: a profile carrying counts restores them, and every
    -- later count mirrors back into the profile.
    local p = build({ db = {
        twist_score_persist = true,
        twist_score_attempts = 7,
        twist_score_successes = 5,
    } })
    local pT = p.ST
    pT.PALADIN.post_init(pT)
    eq(pT.twist_score_attempts, 7, "P1 persist: attempts restored from the profile")
    eq(pT.twist_score_successes, 5, "P1 persist: successes restored from the profile")
    pT.PALADIN.on_twist_attempt(pT)
    eq(pT.twist_score_attempts, 8, "P1 persist: the session count advances")
    eq(p.class_db.twist_score_attempts, 8, "P1 persist: the profile mirror advances")
    pT.PALADIN.on_successful_twist(pT)
    eq(p.class_db.twist_score_successes, 6, "P1 persist: successes mirror too")
end

--=========================================================================================
-- 3) P2: melee refresh semantics (note_swing_landed)
--=========================================================================================
do
    local b = build({})
    local T = b.ST
    T.PALADIN.post_init(T)

    b.set_clock(100)
    T.jotc_tracked, T.jotc_id = true, 21183
    T.jotc_expires, T.jotc_full = 115, 20
    T.PALADIN.note_swing_landed(T)
    eq(T.jotc_expires, 120, "P2: a live max-rank JotC extends to now + 20 s")

    T.jotc_expires = 115
    T.jotc_id = 20188   -- lower rank: fixed 10 s, never melee-refreshed
    T.PALADIN.note_swing_landed(T)
    eq(T.jotc_expires, 115, "P2: a lower rank is not refreshed by melee")

    T.jotc_id, T.jotc_expires = 21183, 95
    T.PALADIN.note_swing_landed(T)
    eq(T.jotc_expires, 95, "P2: an expired debuff is not resurrected by a swing")

    T.jotc_tracked = false
    T.jotc_expires = 115
    T.PALADIN.note_swing_landed(T)
    eq(T.jotc_expires, 115, "P2: nothing tracked means no refresh")

    T.jotc_tracked, T.jotc_id, T.jotc_expires, T.jotc_full = nil, nil, nil, nil
    local ok = pcall(T.PALADIN.note_swing_landed, T)
    check(ok, "P2: an empty JotC state never errors")

    -- Through the real combat-log chain: a plain swing lands the refresh; an
    -- extra-attack swing (consumed by the discipline above it) does not.
    b.set_clock(200)
    T.jotc_tracked, T.jotc_id = true, 21183
    T.jotc_expires, T.jotc_full = 215, 20
    T.twist_extra_attacks_pending = 0
    T.PALADIN.on_combat_log_unfiltered(T, "COMBAT_LOG_EVENT_UNFILTERED", 200,
        "SWING_DAMAGE", false, "Player-1", "Tester", 0, 0, "Creature-1", "Dummy", 0, 0)
    eq(T.jotc_expires, 220, "P2 CLEU: a real swing refreshes the tracked JotC")

    T.jotc_expires = 215
    T.twist_extra_attacks_pending = 1
    T.PALADIN.on_combat_log_unfiltered(T, "COMBAT_LOG_EVENT_UNFILTERED", 200,
        "SWING_DAMAGE", false, "Player-1", "Tester", 0, 0, "Creature-1", "Dummy", 0, 0)
    eq(T.jotc_expires, 215, "P2 CLEU: an extra-attack swing never refreshes")
end

--=========================================================================================
-- 4) P2: the JotC mini-bar (scan, swipe, timer latch, no churn)
--=========================================================================================
do
    local b = build({})
    local T = b.ST
    T.PALADIN.post_init(T)
    b.spell_infos[21183] = { name = "Judgement of the Crusader", icon = "icon_21183" }
    b.spell_infos[20188] = { name = "Judgement of the Crusader", icon = "icon_20188" }
    b.class_db.jotc_bar_enabled = true
    b.set_target_exists(true)

    local bar = b.vf.jotc_bar
    b.set_clock(100)
    b.target_auras[1] = { name = "Judgement of the Crusader", spell_id = 21183, expiration = 115 }
    T.PALADIN.update_jotc_bar(T, "mainhand")
    eq(bar.frame.shown, true, "P2 bar: shown while the tracked debuff is live")
    eq(bar.icon.texture, "icon_21183", "P2 bar: the max-rank icon")
    eq(bar.cooldown.cooldown_start, 95, "P2 bar: the swipe starts at expiry - 20 s")
    eq(bar.cooldown.cooldown_duration, 20, "P2 bar: the swipe is the 20 s max-rank length")
    eq(bar.timer.text, "15", "P2 bar: the timer text counts down")
    eq(bar.cooldown.reverse, true, "P2 bar: the swipe is reversed (seal-icon idiom)")

    -- No churn: within the 0.5 s scan throttle nothing re-resolves or re-sets.
    local reads, info_reads = b.aura_reads(), b.spell_info_reads()
    local tex_calls, cd_calls = bar.icon.set_texture_calls, bar.cooldown.cooldown_sets
    b.set_clock(100.1)
    T.PALADIN.update_jotc_bar(T, "mainhand")
    eq(b.aura_reads(), reads, "P2 bar: the aura scan stays throttled")
    eq(b.spell_info_reads(), info_reads, "P2 bar: the resolved texture is cached")
    eq(bar.icon.set_texture_calls, tex_calls, "P2 bar: no per-frame SetTexture")
    eq(bar.cooldown.cooldown_sets, cd_calls, "P2 bar: no redundant swipe re-set")

    -- The scan re-arms after the throttle and agrees with the (unchanged) aura.
    b.set_clock(100.6)
    T.PALADIN.update_jotc_bar(T, "mainhand")
    eq(b.aura_reads(), reads + 1, "P2 bar: the scan re-runs after 0.5 s")
    eq(bar.cooldown.cooldown_sets, cd_calls, "P2 bar: an unchanged expiry keeps the swipe")

    -- The melee refresh moves the tracked expiry; the game also moves the aura's
    -- own expirationTime, so the stub aura follows and the next scan agrees.
    T.PALADIN.note_swing_landed(T)
    eq(T.jotc_expires, 120.6, "P2 bar: the swing extended the tracked expiry")
    b.target_auras[1].expiration = 120.6
    b.set_clock(101.2)
    T.PALADIN.update_jotc_bar(T, "mainhand")
    eq(bar.cooldown.cooldown_start, 100.6, "P2 bar: the swipe restarts from the refresh")
    eq(bar.timer.text, "19", "P2 bar: the timer counts from the refreshed expiry")

    -- The debuff falls off: the bar clears and hides.
    b.target_auras[1] = nil
    b.set_clock(101.8)
    T.PALADIN.update_jotc_bar(T, "mainhand")
    eq(bar.frame.shown, false, "P2 bar: hidden once the scan misses")
    eq(bar.icon.shown, false, "P2 bar: the icon hides")
    eq(bar.timer.shown, false, "P2 bar: the timer hides")

    -- A lower rank tracks at its own fixed 10 s length.
    b.target_auras[1] = { name = "Judgement of the Crusader", spell_id = 20188, expiration = 110 }
    b.set_clock(102.4)
    T.PALADIN.update_jotc_bar(T, "mainhand")
    eq(T.jotc_id, 20188, "P2 bar: the lower rank is tracked")
    eq(bar.cooldown.cooldown_duration, 10, "P2 bar: the lower rank swipes over 10 s")
    eq(bar.cooldown.cooldown_start, 100, "P2 bar: the swipe start is expiry - 10 s")

    -- Option off hides everything without touching the tracker.
    b.class_db.jotc_bar_enabled = nil
    b.set_clock(103)
    T.PALADIN.update_jotc_bar(T, "mainhand")
    eq(bar.frame.shown, false, "P2 bar: option nil hides the bar (default off)")

    -- No target at all is a clean miss.
    b.class_db.jotc_bar_enabled = true
    b.set_target_exists(false)
    b.set_clock(103.6)
    T.PALADIN.update_jotc_bar(T, "mainhand")
    eq(bar.frame.shown, false, "P2 bar: no target hides the bar")
end

--=========================================================================================
-- 5) P6: AoW + Exorcism overlap pulse (transition guard, teardown, Retail gate)
--=========================================================================================
do
    local b = build({})
    local T = b.ST
    T.PALADIN.post_init(T)
    b.class_db.aow_exo_pulse_enabled = true
    b.set_clock(200)
    T.has_aow = true
    T.exo_on_cooldown = false

    local pulse_key = "AowExoOverlap"
    local starts = count_keyed(b.lcg_starts, pulse_key)
    T.PALADIN.process_aow(T)
    eq(count_keyed(b.lcg_starts, pulse_key), starts + 1,
        "P6: the first overlap transition pulses")
    eq(b.lcg_starts[starts + 1].key, pulse_key,
        "P6: the pulse uses its own glow key")
    near(T.aow_exo_pulse_until, 200.4, "P6: the pulse window is 0.4 s")

    T.PALADIN.process_aow(T)
    eq(count_keyed(b.lcg_starts, pulse_key), starts + 1,
        "P6: a persistent overlap does not re-pulse (no churn)")

    -- Casting Exorcism breaks the overlap; the cooldown ending re-arms it. Both
    -- edges go through the real cast path and its C_Timer completion.
    T.PALADIN.on_spellcast_succeeded(T, "target", "cast-guid", 879)
    eq(T.exo_on_cooldown, true, "P6: the exo cast starts the cooldown latch")
    eq(count_keyed(b.lcg_starts, pulse_key), starts + 1,
        "P6: no pulse while the exo gate holds")
    eq(#b.timer_afters, 1, "P6: the cooldown end is scheduled")
    b.timer_afters[1].fn()
    eq(T.exo_on_cooldown, false, "P6: the scheduled completion clears the latch")
    eq(count_keyed(b.lcg_starts, pulse_key), starts + 2,
        "P6: the returned overlap pulses again")

    -- Option off: the transition latch still updates, so enabling later cannot
    -- fire on a stale overlap.
    b.class_db.aow_exo_pulse_enabled = nil
    T.exo_on_cooldown = true
    T.PALADIN.process_aow(T)
    eq(T.aow_exo_prev, false, "P6: the latch tracks transitions with the option off")
    b.class_db.aow_exo_pulse_enabled = true
    T.exo_on_cooldown = false
    T.PALADIN.process_aow(T)
    eq(count_keyed(b.lcg_starts, pulse_key), starts + 3,
        "P6: enabling later pulses on the next real transition only")

    -- Teardown: the per-frame stop block owns expiry and the option-off stop.
    T.aow_exo_pulse_until = b.get_clock() + 0.4
    local stops = count_keyed(b.lcg_stops, pulse_key)
    T.PALADIN.on_bar_update(T, "mainhand")
    eq(count_keyed(b.lcg_stops, pulse_key), stops, "P6: a live pulse keeps glowing")
    b.set_clock(b.get_clock() + 0.4)
    T.PALADIN.on_bar_update(T, "mainhand")
    eq(count_keyed(b.lcg_stops, pulse_key), stops + 1, "P6: expiry stops the pulse")
    eq(T.aow_exo_pulse_until, 0, "P6: the expiry latch clears")

    T.aow_exo_pulse_until = b.get_clock() + 0.4
    b.class_db.aow_exo_pulse_enabled = nil
    T.PALADIN.on_bar_update(T, "mainhand")
    eq(count_keyed(b.lcg_stops, pulse_key), stops + 2,
        "P6: turning the option off stops a running pulse")
    b.class_db.aow_exo_pulse_enabled = true

    -- Combat exit tears down only a live pulse (a quiet exit costs no call).
    local exits = count_keyed(b.lcg_stops, pulse_key)
    T.aow_exo_pulse_until = 0
    T.PALADIN.on_combat_exit(T)
    eq(count_keyed(b.lcg_stops, pulse_key), exits,
        "P6: combat exit without a live pulse calls no stop")
    T.aow_exo_pulse_until = b.get_clock() + 0.4
    T.PALADIN.on_combat_exit(T)
    eq(count_keyed(b.lcg_stops, pulse_key), exits + 1,
        "P6: combat exit tears a live pulse down")
    eq(T.aow_exo_pulse_until, 0, "P6: the exit clears the pulse latch")

    -- Retail: the stand-in never pulses (its sibling visuals share the gate).
    local r = build({ project = 1, interface = 120100 })
    r.ST.PALADIN.post_init(r.ST)
    r.class_db.aow_exo_pulse_enabled = true
    r.ST.has_aow = true
    r.ST.exo_on_cooldown = false
    r.ST.PALADIN.process_aow(r.ST)
    eq(count_keyed(r.lcg_starts, pulse_key), 0, "P6 Retail: the pulse never arms")
    eq(r.ST.aow_exo_prev, true, "P6 Retail: the latch still tracks the overlap")
end

--=========================================================================================
-- 6) P7: seal-icon texture resolution (cache latch, retry, show transitions)
--=========================================================================================
do
    local b = build({})
    local T = b.ST
    T.PALADIN.post_init(T)
    local set = b.vf.seal_icons
    local slot = set.slots[1]
    b.set_clock(100)

    -- Cold spell data: no texture yet, nothing is cached, the icon stays hidden.
    T.has_soc, T.soc_expires, T.soc_duration = true, 120, nil
    T.PALADIN.update_seal_icons(T, "mainhand")
    eq(slot.cached_texture, nil, "P7: a cold resolution is not cached as a miss")
    eq(slot.icon.shown, false, "P7: a cold icon stays hidden")

    -- The data arrives: the next frame resolves and shows it (once).
    b.spell_infos[20375] = { name = "Seal of Command", icon = "icon_20375" }
    T.PALADIN.update_seal_icons(T, "mainhand")
    eq(slot.cached_texture, "icon_20375", "P7: the resolved texture is cached")
    eq(slot.icon.texture, "icon_20375", "P7: the icon paints the texture")
    eq(slot.icon.set_texture_calls, 1, "P7: one SetTexture for the show")
    eq(slot.cooldown.cooldown_start, 90, "P7: the swipe start is expiry - 30 s")
    eq(slot.cooldown.cooldown_duration, 30, "P7: the fallback seal length is 30 s")
    eq(slot.timer.text, "20", "P7: the timer counts the aura down")

    -- Steady state: no per-frame texture work (the churn fix), and the timer
    -- text only re-sets when its quantised value changes.
    local tex_calls, info_reads = slot.icon.set_texture_calls, b.spell_info_reads()
    b.set_clock(100.1)
    T.PALADIN.update_seal_icons(T, "mainhand")
    eq(slot.icon.set_texture_calls, tex_calls, "P7: no per-frame SetTexture")
    eq(b.spell_info_reads(), info_reads, "P7: no per-frame GetSpellInfo once resolved")
    T.soc_expires = 120.5
    b.set_clock(100.2)
    T.PALADIN.update_seal_icons(T, "mainhand")
    local text_calls = slot.timer.set_text_calls
    b.set_clock(100.3)
    T.PALADIN.update_seal_icons(T, "mainhand")
    eq(slot.timer.set_text_calls, text_calls, "P7: the timer text latches on change")

    -- Dropped seal: everything clears and hides; re-applying paints once more.
    T.has_soc = false
    b.set_clock(100.4)
    T.PALADIN.update_seal_icons(T, "mainhand")
    eq(slot.icon.shown, false, "P7: a dropped seal hides the icon")
    eq(slot.cooldown.shown, false, "P7: the swipe hides")
    T.has_soc, T.soc_expires = true, 140
    b.set_clock(100.5)
    T.PALADIN.update_seal_icons(T, "mainhand")
    eq(slot.icon.set_texture_calls, tex_calls + 1,
        "P7: the re-show is the only new SetTexture")

    -- Option off hides the whole set.
    b.class_db.seal_icons_enabled = false
    b.set_clock(100.6)
    T.PALADIN.update_seal_icons(T, "mainhand")
    eq(set.frame.shown, false, "P7: option off hides the seal-icon frame")

    -- Era: the second slot tracks the twist seal (Righteousness, 21084).
    local e = build({ project = 2, interface = 11509 })
    e.ST.PALADIN.post_init(e.ST)
    eq(e.vf.seal_icons.slots[2].spell_id, 21084,
        "P7 Era: slot 2 is Seal of Righteousness")
end

--=========================================================================================
-- 7) P3: Bloodlust twist-window override (C2 consumer gate)
--=========================================================================================
do
    local b = build({})
    local T = b.st
    local S = b.ST
    S.PALADIN.post_init(S)
    b.class_db.twist_lust_override_enabled = true
    S.latency = { world_ms = 0 }

    eq(T.lust_supported, true, "P3: the TBC family reports lust supported")
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "P3: without the buff the base window stands")

    b.player_auras[1] = { name = "Bloodlust", spell_id = 2825, expiration = b.get_clock() + 30 }
    b.set_clock(b.get_clock() + 0.5)
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.24,
        "P3: Bloodlust narrows the window to 0.6x")
    local reads = b.aura_reads()
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.24,
        "P3: the throttled scan keeps answering")
    eq(b.aura_reads(), reads, "P3: no re-scan inside the throttle")
    b.set_clock(b.get_clock() + 0.5)
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.24,
        "P3: the scan re-runs after the throttle")
    eq(b.aura_reads(), reads + 1, "P3: exactly one re-scan")

    b.class_db.twist_lust_override_enabled = nil
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "P3: option nil keeps the base window (default off)")

    b.class_db.twist_lust_override_enabled = true
    T.practice_ui = { is_active = function() return true end }
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "P3: a running practice session owns its own window")
    T.practice_ui = nil

    -- Era never arms: the C2 contract closes the gate even with the aura present.
    local e = build({ project = 2, interface = 11509 })
    e.class_db.twist_lust_override_enabled = true
    e.ST.latency = { world_ms = 0 }
    e.player_auras[1] = { name = "Bloodlust", spell_id = 2825, expiration = e.get_clock() + 30 }
    eq(e.st.lust_supported, false, "P3 Era: the C2 gate is closed")
    near(e.ST.PALADIN.get_twist_window_time_before_swing(e.ST), 0.4,
        "P3 Era: the window never narrows")

    -- The UNKNOWN fallback family is closed the same way.
    local u = build({ interface = 9999 })
    u.class_db.twist_lust_override_enabled = true
    u.ST.latency = { world_ms = 0 }
    u.player_auras[1] = { name = "Bloodlust", spell_id = 2825, expiration = u.get_clock() + 30 }
    eq(u.st.family, "UNKNOWN", "P3 UNKNOWN: the fallback family")
    eq(u.st.lust_supported, false, "P3 UNKNOWN: the C2 gate is closed")
    near(u.ST.PALADIN.get_twist_window_time_before_swing(u.ST), 0.4,
        "P3 UNKNOWN: the window never narrows")
end

--=========================================================================================
-- 8) CD icon group: row behavior, glow lead, racial probe, Retail gate
--=========================================================================================
do
    local b = build({})
    local T = b.ST
    T.PALADIN.post_init(T)
    b.spell_infos[31884] = { name = "Avenging Wrath", icon = "icon_31884" }
    b.spell_infos[642] = { name = "Divine Shield", icon = "icon_642" }
    b.spell_infos[20594] = { name = "Stoneform", icon = "icon_20594" }
    b.known_spells[20594] = true
    b.class_db.cd_icons_enabled = true
    b.set_clock(300)

    local set = b.vf.cd_icons
    b.cooldowns[31884] = { start = 300, duration = 30 }
    T.PALADIN.update_cd_icons(T, "mainhand")
    local aw = set.slots[1]
    eq(aw.texture_key, "icon_31884", "CD: the Avenging Wrath icon resolves")
    eq(aw.visible, true, "CD: a running cooldown joins the row")
    eq(aw.cooldown.cooldown_start, 300, "CD: the swipe start is the cooldown start")
    eq(aw.cooldown.cooldown_duration, 30, "CD: the swipe carries the full length")
    eq(set.frame.shown, true, "CD: the row shows while something is cooling down")
    eq(set.frame.width, 16, "CD: the adaptive row is one icon wide")
    eq(count_keyed(b.lcg_starts, "CdReadySoon"), 0, "CD: no glow outside the last 4 s")
    eq(set.slots[7].spell_id, 20594, "CD: the racial probe resolves Stoneform")
    eq(set.slots[7].visible, false, "CD: a ready racial stays out of the row")
    eq(set.anchor, "bar", "CD: with the JotC bar hidden the row hugs the bar")

    -- The gold glow arms once inside the final 4 s and never re-arms per frame.
    b.set_clock(300.6)
    b.cooldowns[31884] = { start = 300.6, duration = 3 }
    T.PALADIN.update_cd_icons(T, "mainhand")
    eq(count_keyed(b.lcg_starts, "CdReadySoon"), 1, "CD: the last-4s glow arms once")
    b.set_clock(300.7)
    T.PALADIN.update_cd_icons(T, "mainhand")
    eq(count_keyed(b.lcg_starts, "CdReadySoon"), 1, "CD: the glow latch holds per frame")

    -- The cooldown ends: the glow stops, the slot and the empty row hide.
    b.set_clock(303.7)
    b.cooldowns[31884] = nil
    T.PALADIN.update_cd_icons(T, "mainhand")
    eq(count_keyed(b.lcg_stops, "CdReadySoon"), 1, "CD: the glow stops at readiness")
    eq(aw.visible, false, "CD: the finished slot leaves the row")
    eq(set.frame.shown, false, "CD: an empty row hides")

    -- A GCD echo (duration <= 1.51 s) is never treated as a cooldown.
    b.cooldowns[642] = { start = 304.4, duration = 1.5 }
    b.set_clock(304.4)
    T.PALADIN.update_cd_icons(T, "mainhand")
    eq(set.slots[2].visible, false, "CD: the GCD echo is not a cooldown")
    eq(set.frame.shown, false, "CD: the echo keeps the row hidden")

    -- Option off hides the row and stops any glow.
    b.set_clock(305.1)
    b.cooldowns[31884] = { start = 305.1, duration = 30 }
    T.PALADIN.update_cd_icons(T, "mainhand")
    eq(set.frame.shown, true, "CD: a new cooldown shows the row again")
    b.class_db.cd_icons_enabled = nil
    b.set_clock(305.2)
    T.PALADIN.update_cd_icons(T, "mainhand")
    eq(set.frame.shown, false, "CD: option nil hides the row (default off)")

    -- The row re-anchors against the live JotC mini-bar when that shows.
    b.class_db.cd_icons_enabled = true
    b.class_db.jotc_bar_enabled = true
    b.spell_infos[21183] = { name = "Judgement of the Crusader", icon = "icon_21183" }
    b.set_target_exists(true)
    b.target_auras[1] = { name = "Judgement of the Crusader", spell_id = 21183, expiration = 320 }
    b.set_clock(305.7)
    T.PALADIN.update_jotc_bar(T, "mainhand")
    T.PALADIN.update_cd_icons(T, "mainhand")
    eq(b.vf.jotc_bar.frame.shown, true, "CD: the JotC bar is up")
    eq(set.anchor, "jotc", "CD: the row sits left of the JotC bar when it shows")

    -- Retail: the group stays inert.
    local r = build({ project = 1, interface = 120100 })
    r.ST.PALADIN.post_init(r.ST)
    r.class_db.cd_icons_enabled = true
    r.spell_infos[31884] = { name = "Avenging Wrath", icon = "icon_31884" }
    r.cooldowns[31884] = { start = r.get_clock(), duration = 30 }
    r.ST.PALADIN.update_cd_icons(r.ST, "mainhand")
    eq(r.vf.cd_icons.frame.shown, false, "CD Retail: the row never shows")
    eq(r.vf.cd_icons.slots[1].visible, false, "CD Retail: no slot joins the row")
end

--=========================================================================================
-- 9) Static wiring pins (the defects this suite must keep closed)
--=========================================================================================
do
    local src = read("classes/paladin.lua")
    check(src:find("self.PALADIN.aow_exo_pulse_start(self)", 1, true) ~= nil,
        "wiring: the overlap pulse is started at the transition")
    check(src:find("aow_exo_pulse_enabled == true and not st.is_retail", 1, true) ~= nil,
        "wiring: the pulse start carries the Retail gate")
    check(src:find("st.lust_supported == true", 1, true) ~= nil,
        "wiring: the lust override consumes the C2 family gate (closed-on-unknown)")
    check(src:find("self.PALADIN.note_swing_landed(self)", 1, true) ~= nil,
        "wiring: the CLEU swing branch refreshes the JotC debuff")
    check(src:find("twist_unmatched_payloads", 1, true) ~= nil,
        "wiring: the unmatched-payload counter exists (M3)")
    check(src:find("api.auras_may_be_secret", 1, true) ~= nil,
        "wiring: the lust-unknown probe is consumed (M5)")
    check(src:find("inputs.inputs_unknown", 1, true) ~= nil,
        "wiring: the gather declares unusable inputs (M6)")
    check(src:find("TWIST_STATE_SWING_UNKNOWN", 1, true) ~= nil,
        "wiring: the seal-data-unknown band state exists (M4)")
    check(src:find("is_proc_icd_clear", 1, true) ~= nil,
        "wiring: the CLEU swing branch consults the ICD gate (sim PPM/ICD)")
    check(src:find("twist_last_proc_at = api.get_time()", 1, true) ~= nil,
        "wiring: the proc stamps the ICD clock (sim PPM/ICD)")
    check(src:find("narrow_window_for_sod", 1, true) ~= nil,
        "wiring: SoD runes narrow the twist window (200 ms APLs)")
    check(src:find("cs_hold_remaining", 1, true) ~= nil,
        "wiring: the TBC pull hold feeds the CS override (Delay Major CDs)")
    check(src:find("auto_age_seconds", 1, true) ~= nil,
        "wiring: swing recency feeds the reseal guard (TBC auto age)")
    check(src:find("has_echo_command == false", 1, true) ~= nil,
        "wiring: the Forever Echo condition degrades the seal (empty = unknown)")
end

--=========================================================================================
-- 10) R4: lust-gate nil-semantics (closed-on-unknown)
--=========================================================================================
do
    local b = build({})
    local T = b.st
    local S = b.ST
    S.PALADIN.post_init(S)
    b.class_db.twist_lust_override_enabled = true
    S.latency = { world_ms = 0 }
    b.player_auras[1] = { name = "Bloodlust", spell_id = 2825, expiration = b.get_clock() + 30 }

    -- Explicit true: the window narrows (the P3 baseline).
    T.lust_supported = true
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.24,
        "R4: explicit true arms the lust scan")
    -- nil (a pre-C2 compat) stays off even with the aura present.
    T.lust_supported = nil
    S.twist_lust_at = nil
    S.twist_lust_remaining = nil
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "R4: nil lust_supported keeps the base window (closed-on-unknown)")
    -- false stays off too.
    T.lust_supported = false
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "R4: false lust_supported keeps the base window")
end

--=========================================================================================
-- 11) R1: string-payload SoC success through the real CLEU chain
--=========================================================================================
do
    local function cleu_spell_damage(S, ...)
        S.PALADIN.on_combat_log_unfiltered(S, "COMBAT_LOG_EVENT_UNFILTERED", 200,
            "SPELL_DAMAGE", false, "Player-1", "Tester", 0, 0,
            "Creature-1", "Dummy", 0, 0, ...)
    end

    -- Numeric path (unchanged): the Command proc consumes the pending attempt.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    S.twist_attempt_pending = true
    cleu_spell_damage(S, 20424, "Seal of Command", 1, 10, 0)
    eq(S.twist_attempt_pending, false, "R1: numeric proc id consumes the pending attempt")
    check((S.twist_success_until or 0) > b.get_clock(), "R1: numeric proc arms success feedback")

    -- String in the id slot (the Anniversary shape): the literal English
    -- fallback lands it even with cold spell data.
    local s = build({})
    local T = s.ST
    T.PALADIN.post_init(T)
    T.twist_attempt_pending = true
    cleu_spell_damage(T, "Seal of Command", 1, 10, 0)
    eq(T.twist_attempt_pending, false, "R1: string payload consumes the pending attempt")
    check((T.twist_success_until or 0) > s.get_clock(), "R1: string payload arms success feedback")

    -- Localized name resolved from the client's own spell data.
    local l = build({})
    l.spell_infos[20424] = { name = "Heiliger Befehl", icon = "icon_20424" }
    local L = l.ST
    L.PALADIN.post_init(L)
    L.twist_attempt_pending = true
    cleu_spell_damage(L, "Heiliger Befehl", 1, 10, 0)
    eq(L.twist_attempt_pending, false, "R1: localized name consumes the pending attempt")

    -- An unrelated string never consumes.
    local u = build({})
    local U = u.ST
    U.PALADIN.post_init(U)
    U.twist_attempt_pending = true
    cleu_spell_damage(U, "Judgement of Command", 1, 10, 0)
    eq(U.twist_attempt_pending, true, "R1: an unrelated name keeps the attempt pending")

    -- No pending attempt: a proc arms nothing (string or numeric).
    local n = build({})
    local N = n.ST
    N.PALADIN.post_init(N)
    N.twist_attempt_pending = false
    cleu_spell_damage(N, "Seal of Command", 1, 10, 0)
    eq(N.twist_attempt_pending, false, "R1: no pending attempt means no success")
    eq(N.twist_success_until, nil, "R1: no pending attempt arms no feedback")
end

--=========================================================================================
-- 12) R3: P1 badge on a client without the classic combat log (Forever)
--=========================================================================================
do
    local f = build({ project = 18, interface = 16001, cleu = false })
    eq(f.st.family, "FOREVER", "R3: the Forever family profile")
    eq(f.st.cleu_supported, false, "R3: no CLEU global means the twist chain cannot arm")
    local F = f.ST
    F.PALADIN.post_init(F)
    f.class_db.twist_score_enabled = true
    F.in_combat = true
    F.mainhand.speed, F.mainhand.start = 3.0, f.get_clock()
    F.mainhand.ends_at, F.mainhand.is_full = f.get_clock() + 3.0, false
    F.PALADIN.on_bar_update(F, "mainhand")
    local badge = f.vf.twist_score_badge
    eq(badge.shown, true, "R3 Forever: the badge explains itself instead of hiding")
    eq(badge.text, "twist scoring: classic-line only", "R3 Forever: classic-line-only state")

    -- Even a nonzero count stays explained: attempts can never arm without CLEU.
    F.PALADIN.on_twist_attempt(F)
    F.PALADIN.on_bar_update(F, "mainhand")
    eq(badge.text, "twist scoring: classic-line only",
        "R3 Forever: the notice wins over a stale count")

    -- Classic-line with CLEU: zero attempts still hides (unchanged).
    local c = build({})
    eq(c.st.cleu_supported, true, "R3: the classic profile reports CLEU")
    local C = c.ST
    C.PALADIN.post_init(C)
    c.class_db.twist_score_enabled = true
    C.in_combat = true
    C.mainhand.speed, C.mainhand.start = 3.0, c.get_clock()
    C.mainhand.ends_at, C.mainhand.is_full = c.get_clock() + 3.0, false
    C.PALADIN.on_bar_update(C, "mainhand")
    eq(c.vf.twist_score_badge.shown, false, "R3 classic: zero attempts still hides the badge")
end

--=========================================================================================
-- 13) R2: secret-hole scans (no truncation below a restricted row)
--=========================================================================================
do
    -- parse_seals: a nil row above the seals no longer hides them.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    -- Index 1 degrades to absent (secret); the seals sit at 2-3.
    b.player_auras[2] = { name = "Seal of Command", spell_id = 20375, expiration = 120 }
    b.player_auras[3] = { name = "Seal of Blood", spell_id = 31892, expiration = 120 }
    S.PALADIN.on_aura_change(S)
    eq(S.has_soc, true, "R2: Command latches below a secret row")
    eq(S.has_sob, true, "R2: Blood latches below a secret row")
    eq(S.twist_active_seals_count, 2, "R2: both seals count below a secret row")

    -- JotC mini-bar scan: the debuff below a secret row still tracks.
    local j = build({})
    local J = j.ST
    J.PALADIN.post_init(J)
    j.spell_infos[21183] = { name = "Judgement of the Crusader", icon = "icon_21183" }
    j.class_db.jotc_bar_enabled = true
    j.set_target_exists(true)
    j.target_auras[2] = { name = "Judgement of the Crusader", spell_id = 21183, expiration = 115 }
    J.PALADIN.update_jotc_bar(J, "mainhand")
    eq(J.jotc_tracked, true, "R2: JotC tracks below a secret row")
    eq(j.vf.jotc_bar.frame.shown, true, "R2: the JotC bar shows below a secret row")
end

--=========================================================================================
-- 14) M3: unmatched twist-proc payloads are counted and announced once
--=========================================================================================
do
    local function cleu_spell_damage(S, ...)
        S.PALADIN.on_combat_log_unfiltered(S, "COMBAT_LOG_EVENT_UNFILTERED", 200,
            "SPELL_DAMAGE", false, "Player-1", "Tester", 0, 0,
            "Creature-1", "Dummy", 0, 0, ...)
    end

    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    local notices = {}
    b.st.utils.print_msg = function(msg) notices[#notices + 1] = msg end

    S.twist_attempt_pending = true
    cleu_spell_damage(S, nil, nil, 1, 10, 0)
    eq(S.twist_unmatched_payloads, 1, "M3: a payload with no id and no name is counted")
    cleu_spell_damage(S, {}, nil, 1, 10, 0)
    eq(S.twist_unmatched_payloads, 2, "M3: a table-shaped payload is counted")
    eq(#notices, 0, "M3: below the threshold stays quiet")
    cleu_spell_damage(S, nil, nil, 1, 10, 0)
    eq(S.twist_unmatched_payloads, 3, "M3: the counter keeps counting")
    eq(#notices, 1, "M3: one notice at the threshold")
    check((notices[1] or ""):find("twist proc payloads", 1, true) ~= nil,
        "M3: the notice names the payload problem")

    cleu_spell_damage(S, nil, nil, 1, 10, 0)
    eq(S.twist_unmatched_payloads, 4, "M3: the counter keeps counting after the notice")
    eq(#notices, 1, "M3: the notice fires once per session")

    -- Usable payload shapes never count (numeric id, string id, string name).
    cleu_spell_damage(S, 20424, "Seal of Command", 1, 10, 0)
    cleu_spell_damage(S, "Seal of Command", nil, 1, 10, 0)
    eq(S.twist_unmatched_payloads, 4, "M3: readable payload shapes do not inflate the counter")
end

--=========================================================================================
-- 15) M4: a distinct "seal data unknown" band state vs the genuine single-seal look
--=========================================================================================
do
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    S.in_combat = true
    b.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 120 }
    b.player_auras[2] = { name = "Seal of Blood", spell_id = 31892, expiration = 120 }
    S.PALADIN.on_aura_change(S)
    eq(S.twist_active_seals_count, 2, "M4 setup: two seals active")

    S.mainhand.speed, S.mainhand.start = 3.0, b.get_clock()
    S.mainhand.ends_at, S.mainhand.is_full = b.get_clock() + 3.0, false
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(b.vf.twist_band.shown, true, "M4: a usable swing keeps the ordinary band")

    -- Dead/stub engine: the swing record is unusable while the seals stay readable.
    S.mainhand.speed = nil
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(b.vf.twist_band.shown, true, "M4: the degraded state still shows the band")
    near(b.vf.twist_band.width, 200, "M4: the degraded band spans the whole bar")
    near(b.vf.twist_band.color[4], 0.10, "M4: the degraded band is dimmed, not the window tint")
    eq(b.vf.twist_text.text, "seal data unknown", "M4: the band says why it cannot time a twist")
    eq(b.vf.twist_text.shown, true, "M4: the unknown state is visible")

    -- Restoring the swing clears the state (normal hidden/idle text handling).
    S.mainhand.speed = 3.0
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(b.vf.twist_text.shown, false, "M4: the unknown text clears once the swing is usable")
    near(b.vf.twist_band.width, 200 * (0.4 / 3.0), "M4: the ordinary window band returns")

    -- No twist-capable seal (Command/Righteousness) stays the ordinary hidden look,
    -- even with a dead swing: that is the genuine single/none-seal state.
    b.player_auras[1] = { name = "Seal of Light", spell_id = 20165, expiration = 120 }
    b.player_auras[2] = nil
    S.PALADIN.on_aura_change(S)
    eq(S.twist_active_seals_count, 1, "M4 setup: one non-twist seal remains")
    S.mainhand.speed = nil
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(b.vf.twist_band.shown, false, "M4: no twist seal + unusable swing hides (no misfire state)")
    eq(b.vf.twist_text.shown, false, "M4: no twist seal stays silent")
end

--=========================================================================================
-- 16) M5: lust-unknown affordance under a secret-aura regime
--=========================================================================================
do
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    b.class_db.twist_lust_override_enabled = true
    S.latency = { world_ms = 0 }
    S.in_combat = true
    b.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 120 }
    b.player_auras[2] = { name = "Seal of Blood", spell_id = 31892, expiration = 120 }
    S.PALADIN.on_aura_change(S)
    S.mainhand.speed, S.mainhand.start = 3.0, b.get_clock()
    S.mainhand.ends_at, S.mainhand.is_full = b.get_clock() + 3.0, false

    local prev_secrets = rawget(_G, "C_Secrets")
    b.env.C_Secrets = nil
    S.twist_lust_at = nil
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "M5: a classic client scans normally")
    eq(S.twist_lust_unknown, false, "M5: no secrets API never reads unknown")

    -- Secret-aura regime, no visible lust: the window stays base but the reading is
    -- marked unknown and the band says so.
    b.env.C_Secrets = { ShouldAurasBeSecret = function() return true end }
    S.twist_lust_at = nil
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "M5: an inconclusive scan keeps the base window (never narrowed on a guess)")
    eq(S.twist_lust_unknown, true, "M5: the secret regime marks the lust reading unknown")
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(b.vf.twist_text.text, "lust unknown", "M5: the band surfaces the unknown lust reading")
    eq(b.vf.twist_band.shown, true, "M5: the window band keeps drawing")

    -- A visible Bloodlust makes the reading known again.
    b.player_auras[3] = { name = "Bloodlust", spell_id = 2825, expiration = b.get_clock() + 30 }
    S.twist_lust_at = nil
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.24,
        "M5: a visible lust narrows the window")
    eq(S.twist_lust_unknown, false, "M5: a visible lust clears the unknown state")

    -- The probe answering false is an honest "not restricted".
    b.env.C_Secrets = { ShouldAurasBeSecret = function() return false end }
    b.player_auras[3] = nil
    S.twist_lust_at = nil
    S.PALADIN.get_twist_window_time_before_swing(S)
    eq(S.twist_lust_unknown, false, "M5: probe false reads as an honest miss")

    b.env.C_Secrets = nil
    _G.C_Secrets = prev_secrets
end

--=========================================================================================
-- 17) G2/G3/G6: lust -> band composition, lag wiring, deadzone independence
--=========================================================================================
do
    -- G2: the window the player feels - live Bloodlust -> 0.6x window -> narrower band.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    b.class_db.twist_lust_override_enabled = true
    S.latency = { world_ms = 0 }
    S.in_combat = true
    b.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 120 }
    b.player_auras[2] = { name = "Seal of Blood", spell_id = 31892, expiration = 120 }
    S.PALADIN.on_aura_change(S)
    S.mainhand.speed, S.mainhand.start = 3.0, b.get_clock()
    S.mainhand.ends_at, S.mainhand.is_full = b.get_clock() + 3.0, false
    S.PALADIN.on_bar_update(S, "mainhand")
    near(b.vf.twist_band.width, 200 * (0.4 / 3.0), "G2: without lust the band is the base window")
    b.player_auras[3] = { name = "Bloodlust", spell_id = 2825, expiration = b.get_clock() + 30 }
    S.twist_lust_at = nil
    S.PALADIN.on_bar_update(S, "mainhand")
    near(b.vf.twist_band.width, 200 * (0.24 / 3.0),
        "G2: live Bloodlust narrows the drawn band through the real chain")

    -- Era: the C2 gate stays closed, so the same aura never narrows the band.
    local e = build({ project = 2, interface = 11509 })
    local E = e.ST
    E.PALADIN.post_init(E)
    e.class_db.twist_lust_override_enabled = true
    E.latency = { world_ms = 0 }
    E.in_combat = true
    e.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 120 }
    e.player_auras[2] = { name = "Seal of Righteousness", spell_id = 27155, expiration = 120 }
    E.PALADIN.on_aura_change(E)
    e.player_auras[3] = { name = "Bloodlust", spell_id = 2825, expiration = e.get_clock() + 30 }
    E.mainhand.speed, E.mainhand.start = 3.0, e.get_clock()
    E.mainhand.ends_at, E.mainhand.is_full = e.get_clock() + 3.0, false
    E.PALADIN.on_bar_update(E, "mainhand")
    near(e.vf.twist_band.width, 200 * (0.4 / 3.0), "G2 Era: the band never narrows")
end

do
    -- G3: lag calibration wiring (defaults 1.4/15, custom values, nil fallback) and
    -- G6: the deadzone calibration is never applied to the twist path.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    S.latency = { world_ms = 100 }
    b.class_db.twist_padding_mode = "Dynamic"
    b.class_db.twist_window_padding_ms = 0
    b.class_db.lag_multiplier = 1.4
    b.class_db.lag_offset = 15
    local dialect = 0.4 + (100 * 1.4 + 15) * 0.7 * 0.001
    near(S.PALADIN.get_twist_window_time_before_swing(S), dialect,
        "G3: the shipped defaults (1.4/15) calibrate the raw world latency")

    b.class_db.lag_multiplier = 2.0
    b.class_db.lag_offset = 0
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4 + 200 * 0.7 * 0.001,
        "G3: custom multiplier/offset drive the window")

    -- nil db keeps the same documented defaults (config_presets.lua:443-444).
    b.class_db.lag_multiplier = nil
    b.class_db.lag_offset = nil
    near(S.PALADIN.get_twist_window_time_before_swing(S), dialect,
        "G3: nil lag keys fall back to 1.4/15")

    -- G6: varying the deadzone calibration alone does not move the window.
    S.db.profile.deadzone_scale_factor = 5.0
    b.hand_db.enable_deadzone = true
    near(S.PALADIN.get_twist_window_time_before_swing(S), dialect,
        "G6: the deadzone calibration never leaks into the twist window")
    local src = read("classes/paladin.lua")
    check(src:find("db.lag_multiplier", 1, true) ~= nil, "G3 wiring: the window getter reads the lag keys")
    check(src:find("deadzone_scale_factor", 1, true) == nil,
        "G6 wiring: the paladin twist path never references the deadzone calibration")
end

--=========================================================================================
-- 18) P1: GCD-aware reseal marker (SST 3.1.0 shape, option-gated, unknown-hides)
--=========================================================================================
do
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    S.in_combat = true
    b.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 120 }
    b.player_auras[2] = { name = "Seal of Blood", spell_id = 31892, expiration = 120 }
    S.PALADIN.on_aura_change(S)
    S.mainhand.speed, S.mainhand.start = 3.0, b.get_clock()
    S.mainhand.ends_at, S.mainhand.is_full = b.get_clock() + 3.0, false
    S.gcd = { expires = b.get_clock() + 1.0 }
    b.class_db.reseal_marker_enabled = true

    S.PALADIN.on_bar_update(S, "mainhand")
    local marker = b.vf.reseal_marker
    eq(marker.shown, true, "P1 marker: shown with a running GCD inside a usable swing")
    near(marker.point[4], 200 * (1 / 3), "P1 marker: GCD-clear position (1-(3-1)/3 of 200)")

    -- A steady frame repositions when the GCD refreshes (the clear position is
    -- live, like the judgement marker): the swing end stays fixed while a fresh
    -- 1.5 s GCD starts 0.5 s in -> 1-(2.5-1.5)/3.0 = 2/3 of the bar.
    b.set_clock(b.get_clock() + 0.5)
    S.gcd = { expires = b.get_clock() + 1.5 }
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(marker.shown, true, "P1 marker: still shown as the swing advances")
    near(marker.point[4], 200 * (2 / 3), "P1 marker: a refreshed GCD moves it to 2/3")

    -- Option nil (default): hidden, no default-visible change.
    b.class_db.reseal_marker_enabled = nil
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(marker.shown, false, "P1 marker: option nil hides it (default off)")

    -- No running GCD: nothing to wait for, hidden.
    b.class_db.reseal_marker_enabled = true
    S.gcd = {}
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(marker.shown, false, "P1 marker: no running GCD hides it")

    -- A GCD outliving the swing cannot time a reseal: hidden.
    S.gcd = { expires = b.get_clock() + 5.0 }
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(marker.shown, false, "P1 marker: a GCD clearing after the swing hides it")

    -- Twist system off, no twist seal, full bar: all hidden.
    S.gcd = { expires = b.get_clock() + 0.5 }
    b.class_db.twist_enabled = false
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(marker.shown, false, "P1 marker: twist_enabled = false hides it")
    b.class_db.twist_enabled = true
    b.player_auras[1] = { name = "Seal of Light", spell_id = 20165, expiration = 120 }
    b.player_auras[2] = nil
    S.PALADIN.on_aura_change(S)
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(marker.shown, false, "P1 marker: no twist seal hides it")
    b.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 120 }
    b.player_auras[2] = { name = "Seal of Blood", spell_id = 31892, expiration = 120 }
    S.PALADIN.on_aura_change(S)
    S.mainhand.is_full = true
    S.PALADIN.on_bar_update(S, "mainhand")
    eq(marker.shown, false, "P1 marker: a full bar hides it")
    S.mainhand.is_full = false

    -- Retail: the stand-in never swings, so the marker stays hidden there.
    local r = build({ project = 1, interface = 120100 })
    r.ST.PALADIN.post_init(r.ST)
    r.class_db.reseal_marker_enabled = true
    r.ST.mainhand.speed, r.ST.mainhand.start = 3.0, r.get_clock()
    r.ST.mainhand.ends_at, r.ST.mainhand.is_full = r.get_clock() + 3.0, false
    r.ST.gcd = { expires = r.get_clock() + 1.0 }
    r.ST.PALADIN.on_bar_update(r.ST, "mainhand")
    eq(r.vf.reseal_marker.shown, false, "P1 marker Retail: never shows")

    -- Static wiring pins (the defects this suite must keep closed).
    local src = read("classes/paladin.lua")
    check(src:find("get_reseal_marker_fraction", 1, true) ~= nil,
        "P1 wiring: the marker reads the pure GCD-clear fraction")
    check(src:find("reseal_marker_enabled", 1, true) ~= nil,
        "P1 wiring: the marker rides its own option (nil = off)")
    check(src:find("vf.reseal_marker", 1, true) ~= nil,
        "P1 wiring: the marker widget is built on the visuals frame")
    local tsrc = read("twist.lua")
    check(tsrc:find("get_reseal_marker_fraction", 1, true) ~= nil,
        "P1 wiring: the pure helper lives in twist.lua (SST marker math)")
end

--=========================================================================================
-- 15) PPM/ICD attempt discipline through the real CLEU chain
--=========================================================================================
do
    local function cleu_swing(S)
        S.PALADIN.on_combat_log_unfiltered(S, "COMBAT_LOG_EVENT_UNFILTERED", 200,
            "SWING_DAMAGE", false, "Player-1", "Tester", 0, 0,
            "Creature-1", "Dummy", 0, 0)
    end
    local function cleu_proc(S)
        S.PALADIN.on_combat_log_unfiltered(S, "COMBAT_LOG_EVENT_UNFILTERED", 200,
            "SPELL_DAMAGE", false, "Player-1", "Tester", 0, 0,
            "Creature-1", "Dummy", 0, 0, 20424, "Seal of Command", 1, 10, 0)
    end
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    eq(S.twist_last_proc_at, nil, "ICD: no proc stamped at boot")
    b.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 200 }
    b.player_auras[2] = { name = "Seal of Blood", spell_id = 31892, expiration = 200 }
    S.PALADIN.on_aura_change(S)
    cleu_swing(S)
    eq(S.twist_attempt_pending, true, "ICD: a clean swing arms the attempt")
    eq(S.twist_score_attempts, 1, "ICD: the clean swing scores")
    eq(S.guide_last_auto_at, b.get_clock(), "auto-age: the swing stamps the last-auto clock")
    cleu_proc(S)
    eq(S.twist_attempt_pending, false, "ICD: the proc consumes the pending attempt")
    eq(S.twist_last_proc_at, b.get_clock(), "ICD: the proc stamps the ICD clock")
    cleu_swing(S)
    eq(S.twist_attempt_pending, false, "ICD: a swing inside the ICD arms nothing")
    eq(S.twist_score_attempts, 1, "ICD: the suppressed swing scores nothing")
    b.set_clock(b.get_clock() + 1.5)
    cleu_swing(S)
    eq(S.twist_attempt_pending, true, "ICD: past the window the swing arms again")
    eq(S.twist_score_attempts, 2, "ICD: the cleared swing scores")
    S.PALADIN.on_combat_exit(S)
    eq(S.twist_last_proc_at, nil, "ICD: combat exit clears the proc stamp")
    eq(S.guide_last_auto_at, nil, "auto-age: combat exit clears the auto stamp")
    eq(S.guide_combat_start_at, nil, "pull hold: combat exit clears the pull clock")
end

--=========================================================================================
-- 16) SoD twist window (200 ms on rune detection, padding rides on top)
--=========================================================================================
do
    local b = build({ project = 2, interface = 11509 })
    eq(b.st.family, "ERA", "SoD window: the Era family profile")
    local S = b.ST
    S.PALADIN.post_init(S)
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "SoD window: no runes keeps the 0.4 baseline")
    b.known_spells[35395] = true
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.2,
        "SoD window: a known CS rune narrows to 0.2")
    -- One build per remaining leg (the DS resolver caches + throttles).
    local d = build({ project = 2, interface = 11509 })
    local D = d.ST
    D.PALADIN.post_init(D)
    d.known_spells[53385] = true
    -- post_init resolves on a cold book (throttled retry); move past it.
    d.set_clock(d.get_clock() + 6)
    near(D.PALADIN.get_twist_window_time_before_swing(D), 0.2,
        "SoD window: a known DS rune narrows to 0.2")
    local m = build({ project = 2, interface = 11509 })
    local M = m.ST
    M.PALADIN.post_init(M)
    m.known_spells[348700] = true
    near(M.PALADIN.get_twist_window_time_before_swing(M), 0.2,
        "SoD window: a known Martyr rune narrows to 0.2")
    b.class_db.twist_padding_mode = "Fixed"
    b.class_db.twist_window_padding_ms = 100
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.3,
        "SoD window: user padding rides on top of the narrowed baseline")
    -- TBC never narrows, runes or not.
    local t = build({})
    local T = t.ST
    T.PALADIN.post_init(T)
    t.known_spells[35395] = true
    near(T.PALADIN.get_twist_window_time_before_swing(T), 0.4,
        "SoD window: TBC keeps the 0.4 baseline")
end

--=========================================================================================
-- 17) TBC pull hold + swing recency through the gather
--=========================================================================================
do
    local b = build({})
    eq(b.st.family, "TBC", "pull hold: the default profile is TBC")
    local S = b.ST
    S.PALADIN.post_init(S)
    local inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.cs_hold_remaining, nil, "pull hold: out of combat the hold reads nil")
    eq(inputs.reseal_auto_guard_seconds, 0.5, "reseal guard: TBC arms the 0.5 s age guard")
    eq(inputs.auto_age_seconds, nil, "auto-age: no swing yet reads unknown")
    eq(inputs.fight_remaining_pct, nil, "filed: no fight-remaining source reads nil")
    eq(inputs.how_cast_seconds, nil, "cast-time probe: non-Era/Forever never feeds")
    S.in_combat = true
    inputs = S.PALADIN.gather_guide_inputs(S)
    near(inputs.cs_hold_remaining, 11, "pull hold: combat start arms the 11 s hold")
    b.set_clock(b.get_clock() + 5)
    inputs = S.PALADIN.gather_guide_inputs(S)
    near(inputs.cs_hold_remaining, 6, "pull hold: the hold counts down with the fight")
    b.set_clock(b.get_clock() + 6.5)
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.cs_hold_remaining, nil, "pull hold: past 11 s the hold clears")
    S.PALADIN.note_swing_landed(S)
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.auto_age_seconds, 0, "auto-age: a fresh swing reads 0")
    b.set_clock(b.get_clock() + 1)
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.auto_age_seconds, 1, "auto-age: the age counts up")
    S.in_combat = false
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.cs_hold_remaining, nil, "pull hold: leaving combat clears the hold")
    -- Non-TBC: no hold, no guard (archived reseal everywhere else).
    local e = build({ project = 2, interface = 11509 })
    local E = e.ST
    E.PALADIN.post_init(E)
    E.in_combat = true
    local einputs = E.PALADIN.gather_guide_inputs(E)
    eq(einputs.cs_hold_remaining, nil, "pull hold: Era never holds CS")
    eq(einputs.reseal_auto_guard_seconds, nil, "reseal guard: Era keeps the archived reseal")
end

--=========================================================================================
-- 18) Forever Echo maintenance (an id the client has not named stays unknown
--     = archived)
--=========================================================================================
do
    local f = build({ project = 18, interface = 16001 })
    eq(f.st.family, "FOREVER", "echo: the Forever family profile")
    local F = f.ST
    F.PALADIN.post_init(F)
    f.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 200 }
    F.PALADIN.on_aura_change(F)
    eq(F.has_soc, true, "echo: Command latches")
    eq(F.has_echo_command, nil, "echo: an unconfirmed id stays unknown")
    eq(F.has_echo_twist, nil, "echo: an unconfirmed twist id stays unknown")
    local inputs = F.PALADIN.gather_guide_inputs(F)
    eq(inputs.seal, "soc", "echo: unknown Echo keeps the archived seal input")
    F.has_echo_command = false
    inputs = F.PALADIN.gather_guide_inputs(F)
    eq(inputs.seal, "none", "echo: an inactive Echo degrades the seal to recast")
    F.has_echo_command = true
    inputs = F.PALADIN.gather_guide_inputs(F)
    eq(inputs.seal, "soc", "echo: an active Echo keeps the seal")
end

--=========================================================================================
-- 18b) BS-5: the Forever name-anchored ids (Echo of Command / Echo of
--      Righteousness / Holy Strike) - web-confirmed, client-unconfirmed,
--      name-resolved. The name is the key: a wrong id degrades to unknown and
--      never to a wrong prompt.
--=========================================================================================
do
    -- The id tables carry the web-confirmed ids (bench/ids_research_2026-10-19.md
    -- §2 - wowhead's own redirect slugs) and the standing is written down. The
    -- pins read the table bodies, not the comments that quote the same numbers
    -- (the source is CRLF; the read is normalized so the pin reads the same on
    -- any platform).
    local src = read("classes/paladin.lua")
    local flat = src:gsub("\r\n", "\n")
    check(flat:find("    1311703,\n})", 1, true) ~= nil,
        "ids: the Echo of Command id is in the table")
    check(flat:find("    1311704,\n})", 1, true) ~= nil,
        "ids: the Echo of Righteousness id is in the table")
    check(flat:find("    10333,\n})", 1, true) ~= nil,
        "ids: the Holy Strike id is in the table")
    check(flat:find("web-confirmed, client-unconfirmed, name-resolved", 1, true) ~= nil,
        "ids: the standing reads web-confirmed, client-unconfirmed, name-resolved")

    -- The client names the confirmed ids: the Echo latches, and the Holy Strike
    -- probe answers from the spell book.
    local f = build({ project = 18, interface = 16001 })
    f.spell_infos[1311703] = { name = "Echo of Command", icon = "icon_1311703" }
    f.spell_infos[1311704] = { name = "Echo of Righteousness", icon = "icon_1311704" }
    f.spell_infos[10333] = { name = "Holy Strike", icon = "icon_10333" }
    f.known_spells[10333] = true
    local F = f.ST
    F.PALADIN.post_init(F)
    f.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 200 }
    F.PALADIN.on_aura_change(F)
    eq(F.has_soc, true, "ids: Command latches")
    -- The id is proven, but no Echo aura is up: the state reads "down".
    eq(F.has_echo_command, false,
        "ids: a proven id reads down when the Echo aura is absent")
    eq(F.has_echo_twist, false,
        "ids: a proven twist id reads down when the Echo aura is absent")
    -- The Echo aura is up: it latches on its proven id.
    f.player_auras[2] = { name = "Echo of Command", spell_id = 1311703, expiration = 200 }
    F.PALADIN.on_aura_change(F)
    eq(F.has_echo_command, true, "ids: the Echo aura latches on its proven id")
    -- The Holy Strike probe resolves through the same discipline.
    eq(F.holy_strike_known, true, "ids: Holy Strike resolves from the spell book")
    local inputs = F.PALADIN.gather_guide_inputs(F)
    eq(inputs.holy_strike_known, true,
        "ids: the gather publishes the Holy Strike plug-in point")

    -- A WRONG id: the client names the web ids as other spells. Nothing
    -- latches, the state stays unknown and the seal input keeps its archived
    -- value - the guide never prompts a wrong reseal.
    local w = build({ project = 18, interface = 16001 })
    w.spell_infos[1311703] = { name = "Fireball", icon = "icon_1311703" }
    w.spell_infos[1311704] = { name = "Cone of Cold", icon = "icon_1311704" }
    w.spell_infos[10333] = { name = "Frostbolt", icon = "icon_10333" }
    local W = w.ST
    W.PALADIN.post_init(W)
    w.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 200 }
    w.player_auras[2] = { name = "Fireball", spell_id = 1311703, expiration = 200 }
    w.player_auras[3] = { name = "Echo of Command", spell_id = 999999, expiration = 200 }
    W.PALADIN.on_aura_change(W)
    eq(W.has_echo_command, nil,
        "ids: a wrong id never latches (the name is the key)")
    eq(W.has_echo_twist, nil, "ids: a wrong twist id never latches")
    eq(W.holy_strike_known, nil,
        "ids: a wrong id leaves the Holy Strike probe unknown")
    local winputs = W.PALADIN.gather_guide_inputs(W)
    eq(winputs.seal, "soc",
        "ids: a wrong id keeps the archived seal input (no wrong prompt)")
    eq(winputs.holy_strike_known, nil,
        "ids: a wrong id publishes an unknown plug-in point")
end

--=========================================================================================
-- 19) Follow-up provider feeds: cast-time probe, mana cap, rank-1, strict, filed nils
--=========================================================================================
do
    -- Cast-time probe: a cold book reads nil (archived hp-only rule).
    local b = build({ project = 2, interface = 11509 })
    local S = b.ST
    S.PALADIN.post_init(S)
    local inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.how_cast_seconds, nil, "cast-time probe: a cold book reads nil")
    -- Known spell, no spell data: still nil, never a guessed number.
    b.set_clock(b.get_clock() + 6)
    b.known_spells[24275] = true
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.how_cast_seconds, nil, "cast-time probe: an unresolvable cast reads nil")
    -- Known spell with data: milliseconds become seconds.
    b.spell_infos[24275] = { name = "Hammer of Wrath", icon = "icon_24275", cast_ms = 2500 }
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.how_cast_seconds, 2.5, "cast-time probe: 2500 ms reads 2.5 s")
    -- Instant reads 0 (a real answer, not unknown).
    local c = build({ project = 2, interface = 11509 })
    local C = c.ST
    C.PALADIN.post_init(C)
    c.set_clock(c.get_clock() + 6)
    c.known_spells[24275] = true
    c.spell_infos[24275] = { name = "Hammer of Wrath", icon = "icon_24275" }
    local cin = C.PALADIN.gather_guide_inputs(C)
    eq(cin.how_cast_seconds, 0, "cast-time probe: an instant cast reads 0")
end
do
    -- Mana-sustain governor groundwork: unset reads nil (governor off).
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    local inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.twist_mana_threshold, nil, "mana cap: unset reads nil (governor off)")
    local m = build({ db = { twist_mana_threshold_pct = 25 } })
    local M = m.ST
    M.PALADIN.post_init(M)
    local minputs = M.PALADIN.gather_guide_inputs(M)
    eq(minputs.twist_mana_threshold, 25, "mana cap: a set key forwards")
    local w = build({ db = { twist_mana_threshold_pct = "lots" } })
    local W = w.ST
    W.PALADIN.post_init(W)
    local winputs = W.PALADIN.gather_guide_inputs(W)
    eq(winputs.twist_mana_threshold, nil, "mana cap: a non-number reads nil")
end
do
    -- Rank-1 reader, strict gate, and the still-filed nils.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    local inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.soc_rank1_known, false, "rank-1: an unknown book reads false")
    eq(inputs.strict_sequence, false, "strict: TBC never runs strictSequence")
    eq(inputs.time_to_pull_seconds, nil, "filed: no pull timer reads nil")
    eq(inputs.seal_remaining_seconds, nil, "filed: no seal source reads nil")
    b.known_spells[20375] = true
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.soc_rank1_known, true, "rank-1: a known book rank 1 reads true")
    -- SoD twist build: Era + rune detection arms the strict wait.
    local d = build({ project = 2, interface = 11509 })
    local D = d.ST
    D.PALADIN.post_init(D)
    d.known_spells[53385] = true
    d.set_clock(d.get_clock() + 6)
    local dinputs = D.PALADIN.gather_guide_inputs(D)
    eq(dinputs.strict_sequence, true, "strict: a SoD rune build runs strictSequence")
end
do
    -- Display mapping: every advisory reaches the display table the frame reads.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    local function guide_out(overrides)
        local t = {
            speed = 3.0, swing_remaining = 3.0, G = 1.5, gcd_remaining = 0,
            twist_window = 0.4, reaction = 0.1, cs_remaining = 6,
            judge_remaining = 6, seal = "none", cs_delay_max = 1.7,
            melee_count = 0, mana_pct = 50,
        }
        for k, v in pairs(overrides or {}) do t[k] = v end
        return S.PALADIN.guide.evaluate(t, {})
    end
    local out = guide_out({ seal = "soc", swing_remaining = 0.3 })
    eq(out.stopattack, true, "mapping: the stopattack advisory reaches the display")
    eq(out.prepull_ready, false, "mapping: no prepull without a countdown")
    eq(out.hard_wait, false, "mapping: no hard wait without strict")
    out = guide_out({ time_to_pull_seconds = 1.0 })
    eq(out.prepull_ready, true, "mapping: the prepull window reaches the display")
    out = guide_out({ seal = "sob", swing_remaining = 0.5, strict_sequence = true })
    eq(out.hard_wait, true, "mapping: the hard wait reaches the display")
    out = guide_out({ soc_rank1_known = true })
    eq(out.rank1_advice, true, "mapping: the rank-1 advisory reaches the display")
    out = guide_out({ fcfs_mode = "sod", exo_remaining = 0, cs_remaining = 0,
        judge_remaining = 0, seal_remaining_seconds = 0.5 })
    eq(out.seal_maintenance, true, "mapping: the maintenance advisory reaches the display")
    eq(out.judge_slot, "judge", "mapping: maintenance judges through the judge slot")
    -- The provider owns data, the frame owns text: even on a hard wait the
    -- mapping keeps the archived HOLD/RIDE text (nextaction_ui paints WAIT).
    out = guide_out({ seal = "sob", swing_remaining = 0.5, strict_sequence = true })
    eq(out.hold_text, "RIDE", "mapping: a hard wait keeps the archived hold text")
    out = guide_out({ seal = "soc", swing_remaining = 0.3 })
    eq(out.hold_text, "HOLD", "mapping: a plain hold keeps the archived hold text")
end
do
    -- Hard-wait render (nextaction_ui display_active): strict wait paints WAIT.
    local src = read("nextaction_ui.lua")
    check(src:find("out.hard_wait == true", 1, true) ~= nil,
        "hard-wait render: the overlay reads the strict wait nil-safe (== true)")
    check(src:find('(labels and labels.wait) or "WAIT"', 1, true) ~= nil,
        "hard-wait render: the strict wait paints WAIT (optional labels.wait)")
end
do
    -- Mana-governor surfacing (display mapping only): OOM reads while the
    -- governor withholds a reseal (a threshold is set, mana sits below it,
    -- and the engine rides). No engine rule is steered here.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    local function guide_out(overrides)
        local t = {
            speed = 3.0, swing_remaining = 3.0, G = 1.5, gcd_remaining = 0,
            twist_window = 0.4, reaction = 0.1, cs_remaining = 6,
            judge_remaining = 6, seal = "none", cs_delay_max = 1.7,
            melee_count = 0, mana_pct = 50,
        }
        for k, v in pairs(overrides or {}) do t[k] = v end
        return S.PALADIN.guide.evaluate(t, {})
    end
    local out = guide_out({ seal = "sob", swing_remaining = 0.5,
        twist_mana_threshold = 30, mana_pct = 10 })
    eq(out.mana_low, true, "mapping: a throttled ride surfaces OOM")
    out = guide_out({ seal = "sob", swing_remaining = 0.5,
        twist_mana_threshold = 30, mana_pct = 50 })
    eq(out.mana_low, false, "mapping: mana above the threshold reads no OOM")
    out = guide_out({ seal = "sob", swing_remaining = 0.5, mana_pct = 10 })
    eq(out.mana_low, false, "mapping: no threshold reads no OOM (governor off)")
    out = guide_out({ seal = "soc", swing_remaining = 0.3,
        twist_mana_threshold = 30, mana_pct = 10 })
    eq(out.mana_low, false, "mapping: OOM only reads on the governor's ride")
    out = guide_out({ seal = "sob", swing_remaining = 0.5,
        twist_mana_threshold = "lots", mana_pct = 10 })
    eq(out.mana_low, false, "mapping: a non-number threshold reads no OOM")
    out = guide_out({ seal = "sob", swing_remaining = 0.5,
        twist_mana_threshold = 30, mana_pct = 30 })
    eq(out.mana_low, false, "mapping: mana at the threshold is not below it")
end
do
    -- Stopattack / prepull / mana-low renders (nextaction_ui): each advisory
    -- paints its own overlay text, nil-safe and unknown-suppressed, with no
    -- db key. The idle prepull reads the pull-timer inputs directly (the
    -- engine only ticks in combat).
    local src = read("nextaction_ui.lua")
    check(src:find("out.stopattack == true", 1, true) ~= nil,
        "stopattack render: the overlay reads the advisory nil-safe (== true)")
    check(src:find('(labels and labels.stop) or "STOP"', 1, true) ~= nil,
        "stopattack render: the advisory paints STOP (optional labels.stop)")
    check(src:find("out.prepull_ready == true", 1, true) ~= nil,
        "prepull render: the overlay reads the prepull window nil-safe (== true)")
    check(src:find('(labels and labels.prepull) or "PULL"', 1, true) ~= nil,
        "prepull render: the window paints PULL (optional labels.prepull)")
    check(src:find("out.mana_low == true", 1, true) ~= nil,
        "mana render: the overlay reads the governor ride nil-safe (== true)")
    check(src:find('(labels and labels.mana) or "OOM"', 1, true) ~= nil,
        "mana render: the governor ride paints OOM (optional labels.mana)")
    check(src:find("inputs.time_to_pull_seconds", 1, true) ~= nil,
        "prepull idle: the out-of-combat frame reads the pull-timer inputs")
    check(src:find("(out.hold or out.stopattack == true", 1, true) ~= nil,
        "stopattack render: the advisory forces the overlay without hold")
    local stop_at = src:find("if out.stopattack == true then", 1, true)
    local pull_at = src:find("elseif out.prepull_ready == true then", 1, true)
    local oom_at = src:find("elseif out.mana_low == true then", 1, true)
    local wait_at = src:find("elseif out.hard_wait == true then", 1, true)
    check(stop_at ~= nil and pull_at ~= nil and oom_at ~= nil and wait_at ~= nil
        and stop_at < pull_at and pull_at < oom_at and oom_at < wait_at,
        "advisory render: STOP, then PULL, then OOM, then WAIT")
    check(src:find("rank1", 1, true) == nil,
        "rank-1 filed: no rank-1 render ships in nextaction_ui")
end
do
    -- Rank-1 slot FILED (no live slot): the advice rides the same spell id
    -- (20375, na.SOC_ID) the soc/twist slots already carry, so a distinct
    -- slot would duplicate the icon with no distinct texture; a distinct
    -- render needs a UI decision + options opt-in, both out of scope and
    -- forbidden as inert toggles. The advisory stays threaded (pinned
    -- above) and display-inert until that lane. Locked here so the future
    -- wire updates this test instead of shipping silently.
    local b = build({})
    local S = b.ST
    local found = false
    for i = 1, #S.PALADIN.guide.slots do
        if S.PALADIN.guide.slots[i].key == "rank1" then found = true end
    end
    check(found == false, "rank-1 filed: no rank1 slot ships (classes/paladin.lua:2941)")
end

--=========================================================================================
-- 20) SoD paladin variants: slots, seal latch, gather inputs + mode selection
-- (bench/sod_paladin_variants_2026-10-19.md §3-§7)
--=========================================================================================
do
    -- Slots: the shipped ten stand (guide_contract pins them). Shockadin HS/AM
    -- slots ride the generic mapping: the engine prompts filler_kind
    -- "holy_shock"/"aura_mastery" and the frame lights the matching slot.
    local b = build({})
    local S = b.ST
    eq(#S.PALADIN.guide.slots, 12, "sod variants: twelve slots ship (HS/AM live + the WotLK APL band)")
    local hs_found, am_found = false, false
    for i = 1, #S.PALADIN.guide.slots do
        local k = S.PALADIN.guide.slots[i].key
        if k == "holy_shock" then hs_found = true end
        if k == "aura_mastery" then am_found = true end
    end
    check(hs_found == true, "sod variants: holy_shock slot ships")
    check(am_found == true, "sod variants: aura_mastery slot ships")

    -- Seal of Martyrdom aura (407798) latches the twist-seal flag: the stack
    -- maintenance times SoM through the sob channel (bench §3).
    local e = build({ project = 2, interface = 11509 })
    local E = e.ST
    E.PALADIN.post_init(E)
    e.player_auras[1] = { name = "Seal of Martyrdom", spell_id = 407798,
        expiration = e.get_clock() + 30 }
    E.PALADIN.on_aura_change(E)
    eq(E.has_sob, true, "sod variants: SoM 407798 latches has_sob")
    eq(E.twist_active_seals_count, 1, "sod variants: SoM counts one seal")
end
do
    -- Non-Era (TBC default): every new input is nil (unknown-hides), the mode
    -- is nil (archived twist tree), no default-visible change.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    local inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.fcfs_mode, nil, "sod variants: TBC keeps the archived mode")
    eq(inputs.holy_power_stacks, nil, "sod variants: TBC stacks read nil")
    eq(inputs.sunlight_remaining, nil, "sod variants: TBC sunlight reads nil")
    eq(inputs.sod_dual_seal_active, false, "sod variants: TBC dual reads false")
    eq(inputs.soc_remaining_seconds, nil, "sod variants: TBC soc timer reads nil")

    -- Era, no runes: SoD cold (no CS/DS/Martyr) — mode nil, inputs nil.
    local c = build({ project = 2, interface = 11509 })
    local C = c.ST
    C.PALADIN.post_init(C)
    local cin = C.PALADIN.gather_guide_inputs(C)
    eq(cin.fcfs_mode, nil, "sod variants: Era without runes keeps the archived mode")
    eq(cin.strict_sequence, false, "sod variants: Era without runes is not strict")
    eq(cin.holy_power_stacks, nil, "sod variants: cold stacks read nil")

    -- Era SoD Exodin (CS rune, no variant signals): mode sod, new inputs
    -- nil (unknown-hides), strict true.
    local d = build({ project = 2, interface = 11509 })
    local D = d.ST
    D.PALADIN.post_init(D)
    d.known_spells[35395] = true
    local din = D.PALADIN.gather_guide_inputs(D)
    eq(din.fcfs_mode, "sod", "sod variants: CS rune selects Exodin")
    eq(din.strict_sequence, true, "sod variants: a SoD rune build is strict")
    eq(din.holy_power_stacks, nil, "sod variants: cold Holy Power reads nil")
    eq(din.sod_dual_seal_active, false, "sod variants: single seal is not dual")
    eq(din.soc_remaining_seconds, nil, "sod variants: no SoC aura reads nil")
end
do
    -- Stack mode: SoD rune + both seals live + no shock/wrath signal.
    local b = build({ project = 2, interface = 11509 })
    local S = b.ST
    S.PALADIN.post_init(S)
    b.known_spells[35395] = true
    b.player_auras[1] = { name = "Seal of Command", spell_id = 20375,
        expiration = b.get_clock() + 30 }
    b.player_auras[2] = { name = "Seal of Martyrdom", spell_id = 407798,
        expiration = b.get_clock() + 20 }
    S.PALADIN.on_aura_change(S)
    local inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.fcfs_mode, "sod_stack", "sod variants: dual seals select stack mode")
    eq(inputs.sod_dual_seal_active, true, "sod variants: dual seals latch active")
    near(inputs.soc_remaining_seconds, 30, "sod variants: SoC timer reads 30 s")
    near(inputs.som_remaining_seconds, 20, "sod variants: SoM timer reads 20 s")

    -- Holy-Power stacks + set-known ride the aura scan (counts, not convention).
    b.player_auras[3] = { name = "Holy Power", spell_id = 1226461, count = 3,
        expiration = b.get_clock() + 30 }
    b.player_auras[4] = { name = "S03 Scarlet Enclave Ret 2P Bonus",
        spell_id = 1226460, expiration = b.get_clock() + 30 }
    S.PALADIN.on_aura_change(S)
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.holy_power_stacks, 3, "sod variants: Holy Power stacks read 3")
    eq(inputs.holy_power_set_known, true, "sod variants: set aura reads known")

    -- Shock mode wins over stack: HS known is the most-distinctive signal.
    b.known_spells[20930] = true
    b.set_clock(b.get_clock() + 6)
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.fcfs_mode, "sod_shock", "sod variants: HS known outranks stack")
    eq(inputs.sod_hs_known, true, "sod variants: HS signal latches")
    eq(inputs.hs_remaining, 0, "sod variants: HS ready reads 0 while off cooldown")
    -- Live: an active HS cooldown reads its remaining seconds.
    b.cooldowns[20930] = { start = b.get_clock() - 10, duration = 30 }
    inputs = S.PALADIN.gather_guide_inputs(S)
    near(inputs.hs_remaining, 20, "sod variants: HS on cooldown reads remaining")
    -- Cold: HS unknown on this client resolves to no id, so the cooldown reads
    -- nil (unknown-hides) rather than ready.
    local c = build({ project = 2, interface = 11509 })
    local CS = c.ST
    CS.PALADIN.post_init(CS)
    c.known_spells[35395] = true
    local cold_inputs = CS.PALADIN.gather_guide_inputs(CS)
    eq(cold_inputs.sod_hs_known, false, "sod variants: HS signal unlatches while unknown")
    eq(cold_inputs.hs_remaining, nil, "sod variants: HS unknown reads nil (cold hides)")
    -- Precedence: shock outranks wrath-like when both signals are live
    -- (HS-known is the most-distinctive signal; documented order).
    b.player_auras[5] = { name = "S03 T2 Ret 2P Bonus", spell_id = 467518,
        expiration = b.get_clock() + 30 }
    S.PALADIN.on_aura_change(S)
    inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.fcfs_mode, "sod_shock", "sod variants: HS known outranks wrath signal")
end
do
    -- Wrath-like mode: T2-2pc aura (467518) selects it over stack.
    local b = build({ project = 2, interface = 11509 })
    local S = b.ST
    S.PALADIN.post_init(S)
    b.known_spells[35395] = true
    b.player_auras[1] = { name = "Seal of Command", spell_id = 20375,
        expiration = b.get_clock() + 30 }
    b.player_auras[2] = { name = "Seal of Martyrdom", spell_id = 407798,
        expiration = b.get_clock() + 30 }
    b.player_auras[3] = { name = "S03 T2 Ret 2P Bonus", spell_id = 467518,
        expiration = b.get_clock() + 30 }
    b.player_auras[4] = { name = "Templar", spell_id = 1226464,
        expiration = b.get_clock() + 0.5 }
    S.PALADIN.on_aura_change(S)
    local inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.fcfs_mode, "sod_wrath", "sod variants: T2 aura selects wrath-like")
    eq(inputs.sod_t2_known, true, "sod variants: T2 gate reads known")
    near(inputs.templar_wrath_remaining, 0.5, "sod variants: Templar wait reads 0.5 s")

    -- Sunlight/Templar-stack + Naxx/Libram ride the same scan.
    b.player_auras[5] = { name = "Sunlight", spell_id = 1239543,
        expiration = b.get_clock() + 1.0 }
    b.player_auras[6] = { name = "Templar", spell_id = 1240574,
        expiration = b.get_clock() + 1.2 }
    b.player_auras[7] = { name = "Naxx Ret 6P Bonus", spell_id = 1219193,
        expiration = b.get_clock() + 30 }
    b.player_auras[8] = { name = "Libram of Sanctity", spell_id = 1214298,
        expiration = b.get_clock() + 30 }
    b.known_spells[407624] = true
    S.PALADIN.on_aura_change(S)
    inputs = S.PALADIN.gather_guide_inputs(S)
    near(inputs.sunlight_remaining, 1.0, "sod variants: Sunlight reads 1 s")
    near(inputs.templar_stack_remaining, 1.2, "sod variants: Templar-stack reads 1.2 s")
    eq(inputs.sod_naxx_known, true, "sod variants: Naxx gate reads known")
    eq(inputs.sod_libram_known, true, "sod variants: Libram gate reads known")
    eq(inputs.am_rune_known, true, "sod variants: AM rune reads known")
end
do
    -- Display mapping: the new filler kinds reach their slots, and the
    -- variant advisories ride the seal_maintenance channel the frame owns.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    local function guide_out(overrides)
        local t = {
            speed = 3.0, swing_remaining = 3.0, G = 1.5, gcd_remaining = 0,
            twist_window = 0.4, reaction = 0.1, cs_remaining = 6,
            judge_remaining = 6, seal = "none", cs_delay_max = 1.7,
            melee_count = 0, mana_pct = 50,
        }
        for k, v in pairs(overrides or {}) do t[k] = v end
        return S.PALADIN.guide.evaluate(t, {})
    end
    local out = guide_out({ fcfs_mode = "sod_shock", holy_power_stacks = 3,
        exo_remaining = 6, am_remaining = 6, hs_remaining = 0, cs_remaining = 6,
        am_rune_known = true, sod_libram_known = true })
    eq(out.filler_slot, "holy_shock", "sod variants: HS prompts its slot")
    out = guide_out({ fcfs_mode = "sod_shock", holy_power_stacks = 3,
        exo_remaining = 6, am_remaining = 0, hs_remaining = 6, cs_remaining = 6,
        am_rune_known = true, sod_libram_known = true })
    eq(out.filler_slot, "aura_mastery", "sod variants: AM prompts its slot")
    out = guide_out({ fcfs_mode = "sod_shock", holy_power_stacks = 2,
        exo_remaining = 6, am_remaining = 0, hs_remaining = 0, cs_remaining = 0,
        am_rune_known = true, sod_libram_known = true })
    eq(out.action, "cs", "sod variants: below 3 stacks CS wins the tick")
    eq(out.filler_slot, nil, "sod variants: HS/AM withhold below 3 stacks")
    out = guide_out({ fcfs_mode = "sod_stack", holy_power_stacks = 3,
        holy_power_set_known = true, sod_dual_seal_active = true,
        ds_remaining = 6, cs_remaining = 0, exo_remaining = 6,
        cons_remaining = 8, judge_remaining = 0,
        soc_remaining_seconds = 0.5, som_remaining_seconds = 5.0 })
    eq(out.seal_maintenance, true, "sod variants: stack timers raise maintenance")
    eq(out.judge_slot, nil, "sod variants: stack maintenance never elevates Judge")
    out = guide_out({ fcfs_mode = "sod_wrath", holy_power_stacks = 3,
        holy_power_set_known = true, sod_t2_known = true,
        ds_remaining = 5.0, cs_remaining = 0, exo_remaining = 0,
        judge_remaining = 6, cons_remaining = 8,
        templar_wrath_remaining = 0.5 })
    eq(out.seal_maintenance, true, "sod variants: Templar wait raises maintenance")
    eq(out.hold, true, "sod variants: Templar wait holds on DS")

    -- Static wiring pins (the defects this suite must keep closed).
    local src = read("classes/paladin.lua")
    check(src:find("407798", 1, true) ~= nil,
        "sod variants wiring: SoM aura id ships in the seal table")
    check(src:find("sod_dual_seal_active", 1, true) ~= nil,
        "sod variants wiring: the stack dual gate feeds the engine")
    check(src:find("holy_power_stacks", 1, true) ~= nil,
        "sod variants wiring: Holy-Power stacks feed the engine (1226461)")
    check(src:find("sod_t2_known", 1, true) ~= nil,
        "sod variants wiring: the T2 Judge gate feeds the engine (467518)")
    check(src:find("sod_naxx_known", 1, true) ~= nil,
        "sod variants wiring: the Naxx HW gate feeds the engine (1219193)")
    check(src:find("sod_libram_known", 1, true) ~= nil,
        "sod variants wiring: the Libram AM gate feeds the engine (1214298)")
    check(src:find("sunlight_remaining", 1, true) ~= nil,
        "sod variants wiring: Sunlight feeds the engine (1239543)")
    check(src:find("templar_wrath_remaining", 1, true) ~= nil,
        "sod variants wiring: wrath Templar feeds the engine (1226464)")
    check(src:find("241037", 1, true) ~= nil,
        "sod variants wiring: the on-use opener role is filed UNCONFIRMED (no icon)")
    local nsrc = read("nextaction.lua")
    check(nsrc:find("FCFS_ORDER_SOD_STACK", 1, true) ~= nil,
        "sod variants wiring: the stack order ships in the engine")
    check(nsrc:find("FCFS_ORDER_SOD_SHOCK", 1, true) ~= nil,
        "sod variants wiring: the shock order ships in the engine")
    check(nsrc:find("FCFS_ORDER_SOD_WRATH", 1, true) ~= nil,
        "sod variants wiring: the wrath-like order ships in the engine")
    check(nsrc:find("SOD_WRATH_CONS_FALLBACK_SECONDS", 1, true) ~= nil,
        "sod variants wiring: the Cons fallback constant ships")
end

--=========================================================================================
-- 21) Name-vs-id rule (operator 2026-10-19; bench/lessons.md): TBC resolves
-- by NAME, never bare id; Era resolves by id. Family branching via st.family.
--=========================================================================================
do
    -- TBC cooldown queries carry the localized name; Era queries carry the id.
    local b = build({})
    eq(b.st.family, "TBC", "name-vs-id: the default profile is TBC")
    local S = b.ST
    S.PALADIN.post_init(S)
    b.spell_infos[35395] = { name = "Crusader Strike", icon = "icon_35395" }
    b.known_spells[35395] = true
    b.spell_infos[20375] = { name = "Seal of Command", icon = "icon_20375" }
    b.known_spells[20375] = true
    local inputs = S.PALADIN.gather_guide_inputs(S)
    eq(inputs.cs_known, true, "name-vs-id TBC: a known CS rune probes true by name")
    eq(inputs.soc_rank1_known, true, "name-vs-id TBC: rank-1 probes true by name")
    local saw_cs_name = false
    for i = 1, #b.cooldown_queries do
        if b.cooldown_queries[i] == "Crusader Strike" then
            saw_cs_name = true
        end
    end
    check(saw_cs_name, "name-vs-id TBC: the known rank is queried by name")
    local saw_string_probe = false
    for i = 1, #b.known_queries do
        if type(b.known_queries[i]) == "string" then
            saw_string_probe = true
        end
    end
    check(saw_string_probe, "name-vs-id TBC: knowledge probes are names")

    -- Era: the same fixture probes and queries by id.
    local e = build({ project = 2, interface = 11509 })
    eq(e.st.family, "ERA", "name-vs-id: the Era profile")
    local E = e.ST
    E.PALADIN.post_init(E)
    e.spell_infos[35395] = { name = "Crusader Strike", icon = "icon_35395" }
    e.known_spells[35395] = true
    e.spell_infos[20375] = { name = "Seal of Command", icon = "icon_20375" }
    e.known_spells[20375] = true
    local einputs = E.PALADIN.gather_guide_inputs(E)
    eq(einputs.cs_known, true, "name-vs-id Era: a known CS rune probes true by id")
    eq(einputs.soc_rank1_known, true, "name-vs-id Era: rank-1 probes true by id")
    for i = 1, #e.cooldown_queries do
        check(type(e.cooldown_queries[i]) == "number",
            "name-vs-id Era: every cooldown query is an id")
    end
    for i = 1, #e.known_queries do
        check(type(e.known_queries[i]) == "number",
            "name-vs-id Era: every knowledge probe is an id")
    end

    -- TBC seal latch: right name + wrong id latches (name path); right id +
    -- wrong name still latches (the cold-book id fallback smoke.lua pins).
    local n = build({})
    local N = n.ST
    N.PALADIN.post_init(N)
    n.spell_infos[20375] = { name = "Seal of Command", icon = "icon_20375" }
    n.player_auras[1] = { name = "Seal of Command", spell_id = 99999, expiration = 200 }
    N.PALADIN.on_aura_change(N)
    eq(N.has_soc, true, "name-vs-id TBC: a resolved name latches with a wrong id")
    n.player_auras[1] = { name = "Bogus Seal", spell_id = 20375, expiration = 200 }
    N.PALADIN.on_aura_change(N)
    eq(N.has_soc, true, "name-vs-id TBC: the id fallback latches with a wrong name")

    -- TBC cold book (no spell data): the id fallback latches, an
    -- unresolvable name never does.
    local c = build({})
    local C = c.ST
    C.PALADIN.post_init(C)
    c.player_auras[1] = { name = "Seal of Command", spell_id = 20375, expiration = 200 }
    C.PALADIN.on_aura_change(C)
    eq(C.has_soc, true, "name-vs-id TBC cold: the id fallback latches")
    c.player_auras[1] = { name = "Seal of Command", spell_id = 99999, expiration = 200 }
    C.PALADIN.on_aura_change(C)
    eq(C.has_soc, false, "name-vs-id TBC cold: an unresolvable name never latches")

    -- Era: the mirror image (id path only).
    local r = build({ project = 2, interface = 11509 })
    local R = r.ST
    R.PALADIN.post_init(R)
    r.spell_infos[20375] = { name = "Seal of Command", icon = "icon_20375" }
    r.player_auras[1] = { name = "Seal of Command", spell_id = 99999, expiration = 200 }
    R.PALADIN.on_aura_change(R)
    eq(R.has_soc, false, "name-vs-id Era: a bare name never latches with a wrong id")
    r.player_auras[1] = { name = "Bogus Seal", spell_id = 20375, expiration = 200 }
    R.PALADIN.on_aura_change(R)
    eq(R.has_soc, true, "name-vs-id Era: the id latches with a wrong name")
end
do
    -- JotC scan: TBC matches the localized name only; Era matches the id only.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    b.spell_infos[21183] = { name = "Judgement of the Crusader", icon = "icon_21183" }
    b.set_target_exists(true)
    b.target_auras[1] = { name = "Judgement of the Crusader", spell_id = 99999,
        expiration = b.get_clock() + 15 }
    local inputs = S.PALADIN.gather_guide_inputs(S)
    near(inputs.jotc_remaining, 15, "name-vs-id TBC: JotC tracks by name with a wrong id")
    b.target_auras[1] = { name = "Bogus Debuff", spell_id = 21183,
        expiration = b.get_clock() + 15 }
    S.guide_jotc_at = nil
    inputs = S.PALADIN.gather_guide_inputs(S)
    near(inputs.jotc_remaining, 15, "name-vs-id TBC: the id fallback tracks with a wrong name")

    local e = build({ project = 2, interface = 11509 })
    local E = e.ST
    E.PALADIN.post_init(E)
    e.spell_infos[21183] = { name = "Judgement of the Crusader", icon = "icon_21183" }
    e.set_target_exists(true)
    e.target_auras[1] = { name = "Judgement of the Crusader", spell_id = 99999,
        expiration = e.get_clock() + 15 }
    local einputs = E.PALADIN.gather_guide_inputs(E)
    eq(einputs.jotc_remaining, nil, "name-vs-id Era: a bare name never tracks")
    e.target_auras[1] = { name = "Bogus Debuff", spell_id = 21183,
        expiration = e.get_clock() + 15 }
    E.guide_jotc_at = nil
    einputs = E.PALADIN.gather_guide_inputs(E)
    near(einputs.jotc_remaining, 15, "name-vs-id Era: JotC tracks by id with a wrong name")
end
do
    -- Lust scan: TBC matches the Bloodlust name only.
    local b = build({})
    local S = b.ST
    S.PALADIN.post_init(S)
    b.class_db.twist_lust_override_enabled = true
    S.latency = { world_ms = 0 }
    b.player_auras[1] = { name = "Bloodlust", spell_id = 99999,
        expiration = b.get_clock() + 30 }
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.24,
        "name-vs-id TBC: Bloodlust tracks by name with a wrong id")
    b.player_auras[1] = { name = "Bogus Buff", spell_id = 2825,
        expiration = b.get_clock() + 30 }
    S.twist_lust_at = nil
    near(S.PALADIN.get_twist_window_time_before_swing(S), 0.4,
        "name-vs-id TBC: a bare lust id never tracks")

    -- Slots stay numeric ids on both families (icon descriptors resolved via
    -- GetSpellInfo, which takes ids on every family).
    eq(#S.PALADIN.guide.slots, 12, "name-vs-id TBC: twelve slots still ship")
    eq(S.PALADIN.guide.slots[1].spell_id, 35395, "name-vs-id TBC: slots keep numeric ids")
    eq(S.PALADIN.HUD_SLOTS[1].spell, 35395, "name-vs-id TBC: HUD slots keep numeric ids")

    -- Static wiring pins (the defects this suite must keep closed).
    local src = read("classes/paladin.lua")
    check(src:find("api.get_spell_query", 1, true) ~= nil,
        "name-vs-id wiring: queries go through compat's family helper")
    check(src:find('st.family == "TBC"', 1, true) ~= nil,
        "name-vs-id wiring: the family branch is st.family, never a version string")
    check(src:find("resolve_spell_name", 1, true) ~= nil,
        "name-vs-id wiring: names resolve through the client's own GetSpellInfo")
    check(src:find("aura_matches", 1, true) ~= nil,
        "name-vs-id wiring: aura scans match through the shared matcher")
    check(src:find("is_spell_known_query", 1, true) ~= nil,
        "name-vs-id wiring: knowledge probes go through the family query")
end

--=========================================================================================
-- Designer: bar children are positioned through the design registry
--=========================================================================================
-- The archive registers seal icons + success text as independent design elements
-- (editmode.lua ELEMENTS "icons" + "success"). The current build parents both to
-- the mainhand bar (they move with the bar overlay); a design-mode drag detaches
-- them to UIParent offsets, double-click reset re-attaches. These pins hold the
-- contract the two designmode descriptors consume.
do
    local b = build({})
    local T = b.ST
    T.PALADIN.post_init(T)
    local bar_frame = T.mainhand.anchor_frame.bar_frame

    -- Bar-attached by default: the sidebars ride the mainhand bar frame.
    eq(b.vf.seal_icons.frame.parent, bar_frame,
        "designer: seal icons parent to the mainhand bar frame")
    eq(b.vf.jotc_bar.frame.parent, bar_frame,
        "designer: the JotC mini-bar parents to the mainhand bar frame")
    eq(b.vf.cd_icons.frame.parent, bar_frame,
        "designer: the CD icon group parents to the mainhand bar frame")

    -- The designer apply/save/reset seams exist.
    for _, name in ipairs({ "apply_seal_icons_anchor", "save_seal_icons_position",
        "reset_seal_icons_position", "apply_twist_text_anchor",
        "save_twist_text_position", "reset_twist_text_position" }) do
        check(type(T.PALADIN[name]) == "function",
            "designer: ST.PALADIN." .. name .. " defined")
    end

    -- Detach round-trip: drag writes detached offsets + re-anchors to UIParent.
    T.PALADIN.save_seal_icons_position(T, 40, -200)
    eq(b.class_db.seal_icons_detached, true,
        "designer: dragging the seal icons detaches them")
    eq(b.class_db.seal_icons_x, 40, "designer: detached seal X stored")
    eq(b.class_db.seal_icons_y, -200, "designer: detached seal Y stored")
    local point = b.vf.seal_icons.frame.point
    eq(point[1], "CENTER", "designer: detached seals anchor centre")
    eq(point[2], b.env.UIParent, "designer: detached seals anchor to UIParent")
    eq(point[4], 40, "designer: detached seal X applied")
    eq(point[5], -200, "designer: detached seal Y applied")
    T.PALADIN.on_bar_update(T, "mainhand")
    eq(b.vf.seal_icons.frame.point[1], "CENTER",
        "designer: the per-frame updater keeps the detached anchor")

    -- Reset re-attaches left of the bar.
    T.PALADIN.reset_seal_icons_position(T)
    eq(b.class_db.seal_icons_detached, nil,
        "designer: reset re-attaches the seal icons")
    eq(b.class_db.seal_icons_x, nil, "designer: reset clears detached X")
    point = b.vf.seal_icons.frame.point
    eq(point[1], "LEFT", "designer: re-attached seals anchor left")
    eq(point[2], bar_frame, "designer: re-attached seals anchor to the bar")

    -- Success text: the same detach shape on the font string.
    T.PALADIN.save_twist_text_position(T, -30, 120)
    eq(b.class_db.twist_text_detached, true,
        "designer: dragging the success text detaches it")
    local tpoint = b.vf.twist_text.point
    eq(tpoint[1], "CENTER", "designer: detached text anchors centre")
    eq(tpoint[2], b.env.UIParent, "designer: detached text anchors to UIParent")
    T.PALADIN.reset_twist_text_position(T)
    eq(b.class_db.twist_text_detached, nil,
        "designer: reset re-attaches the success text")
    tpoint = b.vf.twist_text.point
    eq(tpoint[1], "BOTTOM", "designer: re-attached text anchors bottom")
    eq(tpoint[2], b.vf, "designer: re-attached text anchors to the visuals frame")

    -- Design mode force-shows both elements so their overlays can grab them
    -- (archive live-preview parity); gameplay hiding is untouched.
    local d = build({})
    local DT = d.ST
    DT.PALADIN.post_init(DT)
    DT.PALADIN.on_bar_update(DT, "mainhand")
    eq(d.vf.seal_icons.frame:IsShown(), false,
        "designer: seal icons stay hidden outside design with no seals")
    d.st.designmode = { is_active = function() return true end }
    DT.PALADIN.on_bar_update(DT, "mainhand")
    eq(d.vf.seal_icons.frame:IsShown(), true,
        "designer: design mode force-shows the seal row for the overlay")
    eq(d.vf.twist_text:IsShown(), true,
        "designer: design mode previews the success text for the overlay")
    eq(d.vf.twist_text.text, "Successful TWIST!",
        "designer: the preview paints the success literal")
    d.st.designmode = nil
    DT.PALADIN.on_bar_update(DT, "mainhand")
    eq(d.vf.seal_icons.frame:IsShown(), false,
        "designer: leaving design re-hides the seal row")
    eq(d.vf.twist_text:IsShown(), false,
        "designer: leaving design re-hides the preview text")

    -- TBC Anniversary family: the same designer contract (classic API, no Retail gate).
    local t = build({ project = 5, interface = 20506 })
    local TT = t.ST
    TT.PALADIN.post_init(TT)
    t.st.designmode = { is_active = function() return true end }
    TT.PALADIN.on_bar_update(TT, "mainhand")
    eq(t.vf.seal_icons.frame:IsShown(), true,
        "designer TBC: design mode force-shows the seal row")
    eq(t.vf.twist_text:IsShown(), true,
        "designer TBC: design mode previews the success text")

    -- Forever family (Mainline-code, native swing): same contract, CLEU absent.
    local f = build({ project = 18, interface = 16001, cleu = false })
    local FT = f.ST
    FT.PALADIN.post_init(FT)
    f.st.designmode = { is_active = function() return true end }
    FT.PALADIN.on_bar_update(FT, "mainhand")
    eq(f.vf.seal_icons.frame:IsShown(), true,
        "designer Forever: design mode force-shows the seal row")
    eq(f.vf.twist_text:IsShown(), true,
        "designer Forever: design mode previews the success text")

    -- Retail: the twist visuals stay hidden (no swing engine), design or not.
    local r = build({ project = 1, interface = 120100 })
    local RT = r.ST
    RT.PALADIN.post_init(RT)
    r.st.designmode = { is_active = function() return true end }
    RT.PALADIN.on_bar_update(RT, "mainhand")
    eq(r.vf.seal_icons.frame:IsShown(), false,
        "designer Retail: the seal row stays hidden (no swing engine)")
    eq(r.vf.twist_text:IsShown(), false,
        "designer Retail: the success text stays hidden")

    -- post_init builds every designer-facing module through its own seam.
    local w = build({})
    local WT = w.ST
    local seen = {}
    w.st.nextaction_ui = { init = function(self) seen.nextaction = self end }
    w.st.practice_ui = { init = function(self) seen.practice = self end,
        is_active = function() return false end }
    w.st.hud = { init = function(self) seen.hud = self end }
    WT.PALADIN.post_init(WT)
    eq(seen.nextaction, WT, "designer: post_init builds the Next Action Guide frame")
    eq(seen.practice, WT, "designer: post_init builds the practice frames")
    eq(seen.hud, WT, "designer: post_init builds the Cooldown HUD frame")
end

--=========================================================================================
-- Practice bridge: the session owns the seal state end to end
--=========================================================================================
do
    local b = build({})
    local T = b.ST
    -- Without a session the sim is absent: sync returns the live count, untouched.
    T.twist_active_seals_count = 2
    eq(T.PALADIN.practice_sync(T), 2,
        "practice: no session leaves the live seal count alone")
    -- A running session mirrors the sim seals and clears everything else.
    b.st.practice_ui = {
        is_active = function() return true end,
        sim = { active_seals = { command = true }, n_active_seals = 1 },
    }
    T.has_sob = true
    T.has_aow = true
    T.soc_expires = 123
    eq(T.PALADIN.practice_sync(T), 1, "practice: sync takes the sim seal count")
    eq(T.has_soc, true, "practice: sync mirrors the sim Command seal")
    eq(T.has_sob, false, "practice: sync clears non-sim seals")
    eq(T.has_aow, false, "practice: sync clears proc flags")
    eq(T.soc_expires, nil, "practice: sync clears live expiries")
    -- parse_seals branches into the sync while the session runs...
    T.has_soc = false
    eq(T.PALADIN.parse_seals(T), 1, "practice: parse_seals yields to the session sim")
    eq(T.has_soc, true, "practice: the parse path mirrors the sim")
    -- ...and reads real auras once it stops.
    b.st.practice_ui = { is_active = function() return false end }
    eq(T.PALADIN.parse_seals(T), 0, "practice: no session parses zero seals from empty auras")
end

--=========================================================================================
-- Practice page: the top-level tab routes the existing session seam
--=========================================================================================
do
    local cenv = {}
    for k, v in pairs(_G) do cenv[k] = v end
    cenv._G = cenv
    cenv.UnitClass = function() return "Paladin", "PALADIN" end
    local class_db = {}
    local OST = { player_class = "paladin", player_class_pretty = "Paladin" }
    function OST.get_class_table() return class_db end
    function OST.get_profile_table() return {} end
    cenv.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return OST end }
        end
        return {}
    end
    local toggled = 0
    local nst = {
        practice_ui = {
            is_active = function() return false end,
            toggle = function(self) toggled = toggled + 1 end,
        },
    }
    local chunk, load_err = loadfile(ROOT .. "option_tables.lua")
    check(chunk ~= nil, "page: option_tables.lua loads (" .. tostring(load_err) .. ")")
    if chunk then
        setfenv(chunk, cenv)
        local run_ok, run_err = pcall(chunk, "SwedgeTimer", nst)
        check(run_ok, "page: option_tables.lua runs (" .. tostring(run_err) .. ")")
        if run_ok then
            OST:generate_top_level_options_table()
            local page = OST.opts_table.args.practice
            check(type(page) == "table" and page.type == "group",
                "page: the top-level Practice group builds")
            if type(page) == "table" then
                eq(page.order, 1.46, "page: the Practice group order")
                eq(page.name, "Practice", "page: the Practice group name")
                local toggle = page.args.practice_toggle
                check(type(toggle) == "table" and toggle.type == "execute",
                    "page: Start/Stop Practice execute ships")
                if type(toggle) == "table" then
                    check(type(toggle.func) == "function",
                        "page: the toggle carries the session seam")
                    check(type(toggle.name) == "function",
                        "page: the toggle label follows the session state")
                    if type(toggle.func) == "function" then
                        toggle.func()
                        eq(toggled, 1, "page: the toggle starts the existing session (no new invocation)")
                    end
                    if type(toggle.name) == "function" then
                        eq(toggle.name(), "Start Practice", "page: idle label")
                        nst.practice_ui.is_active = function() return true end
                        eq(toggle.name(), "Stop Practice", "page: active label")
                    end
                end
                -- Drill rows: nil-safe off defaults, live round-trip on the class table.
                for _, key in ipairs({ "practice_aw_includes_pot",
                    "practice_aw_includes_sob", "practice_dst_enabled" }) do
                    local w = page.args[key]
                    check(type(w) == "table" and w.type == "toggle",
                        "page: " .. key .. " ships as a toggle")
                    if type(w) == "table" then
                        eq(w.get(), false, "page: " .. key .. " defaults off (nil-safe)")
                        w.set(nil, true)
                        eq(class_db[key], true, "page: " .. key .. " writes the class table")
                        eq(w.get(), true, "page: " .. key .. " reads back on")
                    end
                end
                local queue = page.args.practice_spell_queue_window
                check(type(queue) == "table" and queue.type == "range",
                    "page: the queue window ships as a range")
                if type(queue) == "table" then
                    eq(queue.get(), 400, "page: queue window defaults 400 ms")
                    queue.set(nil, 200)
                    eq(class_db.practice_spell_queue_window, 0.2,
                        "page: queue window stores seconds")
                end
                local bl = page.args.practice_bl_delay
                check(type(bl) == "table" and bl.type == "range",
                    "page: Bloodlust delay ships as a range")
                if type(bl) == "table" then
                    eq(bl.get(), 0, "page: Bloodlust delay defaults 0")
                    bl.set(nil, 30)
                    eq(class_db.practice_bl_delay, 30,
                        "page: Bloodlust delay stores")
                end
                -- The class panel keeps its own widgets (the page mirrors, never moves them).
                check(type(OST.class_opts_funcs) == "table"
                    and type(OST.class_opts_funcs.PALADIN) == "function",
                    "page: the paladin class panel still builds (untouched)")
            end
        end
    end
end

--=========================================================================================
-- 22) Shared class order: the per-frame hook and the post_init init order (F8 + F9)
--=========================================================================================
-- The six class modules are copy-paste siblings and used to diverge on two orders:
-- the hunter ticked the HUD before the guide, and the paladin built the practice
-- surface before the HUD. The shared contract is now pinned here, per class:
--   * the per-frame class hook ticks the guide BEFORE the HUD;
--   * post_init builds the guide, then the HUD, then the practice surface.
-- Both the runtime order (spies record the calls) and the source order (the call
-- sites) are pinned, so a reordering in either place fails this suite.
do
    local fh = assert(io.open(ROOT .. "classes/paladin.lua", "r"))
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
    local ok_init, err_init = pcall(T.PALADIN.post_init, T)
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
    local ok_tick, err_tick = pcall(T.PALADIN.on_bar_update, T, "mainhand")
    check(ok_tick, "order: the class hook runs with the order spies (" .. tostring(err_tick) .. ")")
    eq(tick_order[1], "guide", "order: the guide ticks before the HUD")
    eq(tick_order[2], "hud", "order: the HUD ticks after the guide")
    eq(#tick_order, 2, "order: the class hook ticks the guide and the HUD once each")

    sbox.st.nextaction_ui = saved.nextaction_ui
    sbox.st.hud = saved.hud
    sbox.st.practice_ui = saved.practice_ui

end

--=========================================================================================
-- Practice contract: the rotation table, the scenario step and the three drills
-- (bench/class_features_drills_2026-10-19.md §2 D-P1/D-P2/D-P3 and S-P).
-- The sandbox is the TBC family (the twist tree); the FCFS families are
-- exercised through the context's fcfs_mode, which the contract honours.
--=========================================================================================
do
    local b = build({})
    local PC = b.ST.PALADIN
    local na = b.st.nextaction

    -- The rotation table ------------------------------------------------------
    check(type(PC.practice_rotation) == "table", "practice: the rotation table exists")
    check(#PC.practice_rotation > 0, "practice: the rotation table is not empty")
    local seen_actions = {}
    for i = 1, #PC.practice_rotation do
        local entry = PC.practice_rotation[i]
        check(type(entry.action) == "string" and entry.action ~= "",
            "practice: rotation entry " .. i .. " names an action")
        check(type(entry.label) == "string" and entry.label ~= "",
            "practice: rotation entry " .. i .. " names a label")
        check(type(entry.orders) == "table" and #entry.orders > 0,
            "practice: rotation entry " .. i .. " names its orders")
        seen_actions[entry.action] = true
    end
    for _, key in ipairs({ "soc", "sob", "twist", "cs", "judge", "ds", "cons",
        "exo", "how", "hw" }) do
        check(seen_actions[key] == true,
            "practice: the rotation table carries the " .. key .. " action")
    end
    -- The per-order priority is the engine's own table (no copy can drift).
    eq(PC.practice_orders.wrath, na.FCFS_ORDERS.wrath,
        "practice: the Wrath order is the engine's table")
    eq(PC.practice_orders.sod, na.FCFS_ORDERS.sod,
        "practice: the Exodin order is the engine's table")
    eq(PC.practice_orders.twist[1], "cs",
        "practice: the twist order starts with the Crusader Strike override")
    local sod = PC.practice_rotation_for("sod")
    check(type(sod) == "table", "practice: the Exodin rotation exists")
    eq(#sod, 6, "practice: the Exodin rotation has six actions")
    eq(sod[1].action, "exo", "practice: the Exodin rotation starts with Exorcism")
    eq(sod[2].action, "cs", "practice: the Exodin rotation puts Crusader Strike second")
    eq(sod[6].action, "how", "practice: the Exodin rotation ends with Hammer of Wrath")
    eq(PC.practice_rotation_for("nope"), nil,
        "practice: an unknown order has no rotation")
    eq(PC.practice_scenario_key, "paladin_rotation",
        "practice: the scenario key is the spec's S-P key")

    -- The scenario step -------------------------------------------------------
    local twist_ctx = {
        now = 100, swing_remaining = 3.0, gcd_remaining = 0, speed = 3.0,
        gcd_duration = 1.5, seal = "soc", resources = { mana_pct = 0 },
        cooldowns = { judge = 0, cs = 999 },
    }
    local step = PC.practice_scenario_step(nil, twist_ctx)
    check(type(step) == "table", "practice: the step answers with a decision")
    eq(step.action, "twist", "practice: the twist tree cues the twist before the window")
    check(type(step.reason) == "string" and step.reason ~= "",
        "practice: the step carries a reason")
    -- An unreadable context answers nil (unknown), never a guessed action.
    eq(PC.practice_scenario_step(nil, { now = 100, seal = "soc",
        resources = {}, cooldowns = {} }), nil,
        "practice: an unreadable context answers nil (unknown)")
    -- The FCFS path: the frozen order decides (Exorcism first in Exodin).
    local fcfs_ctx = {
        now = 100, swing_remaining = 3.0, gcd_remaining = 0, speed = 3.0,
        gcd_duration = 1.5, seal = "none", fcfs_mode = "sod",
        resources = { mana_pct = 100 },
        cooldowns = { exo = 0, cs = 6, ds = 999, judge = 999, cons = 999, how = 999 },
    }
    step = PC.practice_scenario_step(nil, fcfs_ctx)
    check(type(step) == "table", "practice: the FCFS step answers with a decision")
    eq(step.action, "exo", "practice: the Exodin order prompts Exorcism first")
    -- Nothing ready in the FCFS order: the rotation wants nothing pressed. That
    -- is a HOLD - a DECISION (HU-8), not an unknown: the step states it, so the
    -- engine can tell it apart from a state the class cannot read.
    local idle_ctx = {
        now = 100, swing_remaining = 3.0, gcd_remaining = 0, speed = 3.0,
        seal = "none", fcfs_mode = "sod", resources = { mana_pct = 100 },
        cooldowns = { exo = 999, cs = 999, ds = 999, judge = 999, cons = 999 },
    }
    local idle_step = PC.practice_scenario_step(nil, idle_ctx)
    check(type(idle_step) == "table" and idle_step.hold == true,
        "practice: an idle FCFS tick states an explicit hold")
    eq(idle_step.action, nil, "practice: the hold names no action")
    check(type(idle_step.reason) == "string" and idle_step.reason ~= "",
        "practice: the hold carries the engine's own reason")
    -- The riding case (the Blood seal rides the swing): nothing to press - a hold.
    local ride_ctx = {
        now = 100, swing_remaining = 1.0, gcd_remaining = 0, speed = 3.0,
        gcd_duration = 1.5, seal = "sob", resources = { mana_pct = 0 },
        cooldowns = { judge = 0, cs = 999 },
    }
    local ride_step = PC.practice_scenario_step(nil, ride_ctx)
    check(type(ride_step) == "table" and ride_step.hold == true,
        "practice: the ride states an explicit hold")
    eq(ride_step.action, nil, "practice: the ride names no action")
    check(type(ride_step.reason) == "string" and ride_step.reason ~= "",
        "practice: the ride carries the engine's own reason")
    -- An unknown Judgement cooldown never invents a Judgement cue.
    local no_judge_ctx = {
        now = 100, swing_remaining = 3.0, gcd_remaining = 0, speed = 3.0,
        gcd_duration = 1.5, seal = "sob", resources = { mana_pct = 0 },
        cooldowns = { cs = 999 },
    }
    local no_judge_step = PC.practice_scenario_step(nil, no_judge_ctx)
    check(no_judge_step == nil or no_judge_step.action ~= "judge",
        "practice: an unknown judge cooldown never cues a judgement")
    -- The seal state is read from the session's active seals when the context
    -- does not name one (the Blood seal is what the Judgement cue rides on).
    local seal_session = { state = { active_seals = { blood = true } } }
    local seal_ctx = {
        now = 100, swing_remaining = 3.0, gcd_remaining = 0, speed = 3.0,
        gcd_duration = 1.5, resources = { mana_pct = 0 },
        cooldowns = { judge = 0, cs = 999 },
    }
    local seal_step = PC.practice_scenario_step(seal_session, seal_ctx)
    check(type(seal_step) == "table" and seal_step.action == "judge",
        "practice: the session's Blood seal carries the Judgement cue")

    -- The drills ---------------------------------------------------------------
    check(type(PC.practice_drills) == "table", "practice: the drill list exists")
    eq(#PC.practice_drills, 3, "practice: the paladin ships three drills")
    local by_key = {}
    for i = 1, #PC.practice_drills do
        local drill = PC.practice_drills[i]
        check(type(drill.key) == "string" and drill.key ~= "",
            "practice: drill " .. i .. " has a key")
        check(type(drill.label) == "string" and drill.label ~= "",
            "practice: drill " .. i .. " has a label")
        check(type(drill.grade) == "function", "practice: drill " .. i .. " has a grader")
        by_key[drill.key] = drill
    end
    for _, key in ipairs({ "paladin_fcfs_priority", "paladin_prepull",
        "paladin_judge_fit" }) do
        check(by_key[key] ~= nil, "practice: the drill " .. key .. " exists")
    end

    -- D-P1: the priority order.
    local priority = by_key.paladin_fcfs_priority
    local pick_ctx = {}
    for k, v in pairs(fcfs_ctx) do pick_ctx[k] = v end
    pick_ctx.last_action = "exo"
    eq(priority.grade(nil, pick_ctx), "S",
        "practice: the priority drill grades a correct pick S")
    local miss_ctx = {}
    for k, v in pairs(fcfs_ctx) do miss_ctx[k] = v end
    miss_ctx.last_action = "cs"
    eq(priority.grade(nil, miss_ctx), "F",
        "practice: the priority drill grades a mis-pick F")
    -- The counters accumulate per session (the spec's bands).
    local session = {}
    local first_pick = {}
    for k, v in pairs(pick_ctx) do first_pick[k] = v end
    first_pick.decision_index = 1
    local second_miss = {}
    for k, v in pairs(miss_ctx) do second_miss[k] = v end
    second_miss.decision_index = 2
    local third_miss = {}
    for k, v in pairs(miss_ctx) do third_miss[k] = v end
    third_miss.decision_index = 3
    eq(priority.grade(session, first_pick), "S",
        "practice: the first correct pick is S")
    eq(priority.grade(session, second_miss), "A",
        "practice: one mis-pick drops the band to A")
    eq(priority.grade(session, third_miss), "B",
        "practice: two mis-picks drop the band to B")
    -- A new sample (the decision index restarts) starts the counters over.
    local new_sample = {}
    for k, v in pairs(pick_ctx) do new_sample[k] = v end
    new_sample.decision_index = 1
    eq(priority.grade(session, new_sample), "S",
        "practice: a new sample restarts the counters")
    -- Nothing to judge: the answer is nil, never a wrong grade.
    eq(priority.grade(nil, { now = 100, resources = {}, cooldowns = {} }), nil,
        "practice: the priority drill answers nil when it cannot judge")

    -- D-P2: the opener (the prepull seal).
    local prepull = by_key.paladin_prepull
    eq(prepull.grade(nil, { now = 100, seal = "soc", seal_due = "soc",
        prepull_lead = 1.5, pull_in_seconds = 5, resources = {},
        cooldowns = {} }), "S",
        "practice: the prepull drill grades an early seal S")
    eq(prepull.grade(nil, { now = 100, seal = "soc", seal_due = "soc",
        prepull_lead = 1.5, pull_in_seconds = 1.0, resources = {},
        cooldowns = {} }), "A",
        "practice: the prepull drill grades a half-second-late seal A")
    eq(prepull.grade(nil, { now = 100, seal = "soc", seal_due = "soc",
        prepull_lead = 1.5, pull_in_seconds = 0.0, resources = {},
        cooldowns = {} }), "C",
        "practice: the prepull drill grades a one-and-a-half-second-late seal C")
    eq(prepull.grade(nil, { now = 100, seal = "soc", seal_due = "soc",
        prepull_lead = 1.5, pull_in_seconds = -1.0, resources = {},
        cooldowns = {} }), "D",
        "practice: the prepull drill grades a seal up only after the pull D")
    eq(prepull.grade(nil, { now = 100, seal = "sob", seal_due = "soc",
        prepull_lead = 1.5, pull_in_seconds = 5, resources = {},
        cooldowns = {} }), "F",
        "practice: the prepull drill grades the wrong seal F")
    eq(prepull.grade(nil, { now = 100, seal = "none", seal_due = "soc",
        prepull_lead = 1.5, pull_in_seconds = 5, resources = {},
        cooldowns = {} }), "F",
        "practice: the prepull drill grades a missing seal F")
    eq(prepull.grade(nil, { now = 100, resources = {}, cooldowns = {} }), nil,
        "practice: the prepull drill answers nil without a seal state")

    -- D-P3: the Judgement decision.
    local judge = by_key.paladin_judge_fit
    local judge_ctx = {
        now = 100, swing_remaining = 3.0, gcd_remaining = 0, speed = 3.0,
        gcd_duration = 1.5, seal = "sob", resources = { mana_pct = 0 },
        cooldowns = { judge = 0, cs = 999 },
    }
    local judged_ctx = {}
    for k, v in pairs(judge_ctx) do judged_ctx[k] = v end
    judged_ctx.last_action = "judge"
    eq(judge.grade(nil, judged_ctx), "S",
        "practice: the judge drill grades a correct verdict S")
    local unjudged_ctx = {}
    for k, v in pairs(judge_ctx) do unjudged_ctx[k] = v end
    unjudged_ctx.last_action = "cs"
    eq(judge.grade(nil, unjudged_ctx), "F",
        "practice: the judge drill grades the wrong verdict F")
    -- The lateness bands: the cue time is the reference, the GCD the unit.
    local late_ctx = {}
    for k, v in pairs(judged_ctx) do late_ctx[k] = v end
    late_ctx.cue_at = 99.5
    eq(judge.grade(nil, late_ctx), "A",
        "practice: a press a third of a GCD late drops the band to A")
    late_ctx.cue_at = 99.0
    eq(judge.grade(nil, late_ctx), "B",
        "practice: a press two thirds of a GCD late drops the band to B")
    late_ctx.cue_at = 98.75
    eq(judge.grade(nil, late_ctx), "C",
        "practice: a press one GCD late drops the band to C")
    late_ctx.cue_at = 97.0
    eq(judge.grade(nil, late_ctx), "D",
        "practice: a press more than one GCD late drops the band to D")
    -- An unknown Judgement cooldown means an unknown verdict: nil, never F.
    local unknown_judge = {}
    for k, v in pairs(judge_ctx) do unknown_judge[k] = v end
    unknown_judge.cooldowns = { cs = 999 }
    unknown_judge.last_action = "judge"
    eq(judge.grade(nil, unknown_judge), nil,
        "practice: the judge drill answers nil without a judge cooldown")

    -- The context adapter for the shipped practice sim -------------------------
    local sim = {
        swing_ends_at = 103.0, gcd_expires = 101.0, effective_speed = 3.5,
        effective_gcd = 1.5, cs_cooldown_expires = 106.0,
        judge_cooldown_expires = 108.0, consec_cooldown_expires = 0,
        active_seals = { command = true },
    }
    local ctx = PC.practice_context(sim, 100, "cs")
    eq(ctx.now, 100, "practice: the context adapter carries the clock")
    eq(ctx.swing_remaining, 3.0, "practice: the context adapter reads the swing clock")
    eq(ctx.gcd_remaining, 1.0, "practice: the context adapter reads the GCD clock")
    eq(ctx.speed, 3.5, "practice: the context adapter reads the weapon speed")
    eq(ctx.cooldowns.cs, 6.0, "practice: the context adapter reads the cooldowns")
    eq(ctx.seal, "soc", "practice: the context adapter reads the seal state")
    eq(ctx.last_action, "cs", "practice: the context adapter carries the press")
end

--=========================================================================================
-- 23) BS-8 item 1: a failed LibClassicDurations registration is counted
--=========================================================================================
-- The registration's pcall result used to be dropped, so a library-side failure
-- was invisible: the guide silently fell back to its hardcoded seal length.
-- The class now counts the failure (ST.PALADIN.lcd_register_errors); the
-- shared engine's runtime-diag line reads the number (main.lua owns the
-- reader), so the class side only has to count it exactly once.
do
    -- A healthy library: the registration succeeds and nothing is counted.
    local ok = build({ lcd = {
        GetAuraDurationByUnit = function() end,
        Register = function() end,
    } })
    eq(ok.ST.PALADIN.lcd_register_errors, 0, "lcd: the counter starts at zero")
    ok.ST.PALADIN.post_init(ok.ST)
    eq(ok.ST.PALADIN.lcd_register_errors, 0,
        "lcd: a healthy registration counts nothing")

    -- A failing library: exactly one count per failed registration, and the
    -- failure stays isolated (post_init still completes).
    local bad = build({ lcd = {
        GetAuraDurationByUnit = function() end,
        Register = function() error("register failed") end,
    } })
    eq(bad.ST.PALADIN.lcd_register_errors, 0, "lcd: the counter starts at zero")
    bad.ST.PALADIN.post_init(bad.ST)
    eq(bad.ST.PALADIN.lcd_register_errors, 1,
        "lcd: a failed registration counts exactly once")
    check(bad.vf.twist_band ~= nil,
        "lcd: a failed registration does not break post_init")
end

--=========================================================================================
-- 24) HU-8: the class states its hold, and the pull moment reaches the ctx
--=========================================================================================
-- The operator ruling (hands-up HU-8, resolved 2026-10-19): a HOLD is a DECISION and
-- an unknown is not. The paladin's twist tree answers a HOLD (the RIDE window, the
-- FCFS "nothing is ready") and the step must SAY so: casting during the hold is an
-- illegal cast, doing nothing is correct, and a state the class cannot read stays
-- unknown (no attempt at all).
do
    local b = build({})
    -- The shared engine grades the step (the pure practice engine loads into the
    -- sandbox; the addon object carries the class module).
    local pmod = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(pmod, b.env)
    local okp, errp = pcall(function() pmod("SwedgeTimer", b.st) end)
    check(okp, "hold: practice.lua loads in the paladin sandbox (" .. tostring(errp) .. ")")
    local H = b.st.practice and b.st.practice.harness
    check(type(H) == "table", "hold: the shared harness is loaded")

    local idle_ctx = {
        now = 100, swing_remaining = 3.0, gcd_remaining = 0, speed = 3.0,
        seal = "none", fcfs_mode = "sod", resources = { mana_pct = 100 },
        cooldowns = { exo = 999, cs = 999, ds = 999, judge = 999, cons = 999 },
    }
    local unknown_ctx = { now = 100, seal = "soc", resources = {}, cooldowns = {} }

    -- The hold statement: the accessor keeps it (the engine's contract).
    local hold_answer = H.practice_scenario_step("PALADIN", nil, idle_ctx)
    check(type(hold_answer) == "table" and hold_answer.hold == true,
        "hold: the idle tick states an explicit hold")
    eq(hold_answer.action, nil, "hold: the hold statement names no action")
    check(type(hold_answer.reason) == "string" and hold_answer.reason ~= "",
        "hold: the hold statement carries the engine's reason")

    -- The three states, through the engine's own decision:
    --   hold + a cast  -> the illegal cast (an attempt, an F)
    --   hold + nothing -> a correct hold (no attempt, no points)
    --   unknown        -> unknown (no attempt)
    local run = H.new_rotation_run()
    local cast = H.rotation_run_decide(run, hold_answer.action, "cs", hold_answer.hold)
    eq(cast.outcome, "illegal_cast", "hold: a cast during the hold is an illegal cast")
    eq(H.ROTATION_OUTCOME_GRADES[cast.outcome], "F", "hold: the illegal cast grades F")
    eq(run.mispicks, 1, "hold: the illegal cast counts against the run's band")
    local idle_run = H.new_rotation_run()
    local idle = H.rotation_run_decide(idle_run, hold_answer.action, nil, hold_answer.hold)
    eq(idle.outcome, "hold_ok", "hold: doing nothing during the hold is correct")
    eq(H.ROTATION_OUTCOME_GRADES[idle.outcome], nil,
        "hold: a correct hold records no attempt (no points)")
    eq(idle_run.mispicks, 0, "hold: a correct hold is never a mis-pick")
    -- The unknown: a state the class cannot read stays unknown.
    local unknown_answer = H.practice_scenario_step("PALADIN", nil, unknown_ctx)
    eq(unknown_answer, nil, "hold: an unreadable state stays unknown (no hold statement)")
    local unknown_run = H.new_rotation_run()
    local unknown = H.rotation_run_decide(unknown_run, nil, "cs")
    eq(unknown.outcome, "unknown", "hold: an unknown step stays unknown")
    eq(H.ROTATION_OUTCOME_GRADES[unknown.outcome], nil,
        "hold: an unknown decision records no attempt")
    eq(unknown_run.mispicks, 0, "hold: an unknown decision is never a mis-pick")
end

-- The live pull moment in the class's own ctx (BS-8 item 2 / P-17): the prepull
-- step judges the pull window from the SAME moment the live guide reads, so the
-- class's ctx builder carries it.
do
    local b = build({})
    b.ST.pull_at = 1234
    b.ST.pull_in_seconds = function(self, now) return self.pull_at - now end
    local ctx = b.ST.PALADIN.practice_context(b.ST, 1000, nil)
    eq(ctx.pull_at, 1234, "pull: the ctx carries the absolute pull moment")
    eq(ctx.pull_in_seconds, 234, "pull: the ctx carries the countdown to the pull")
    -- Unknown stays unknown: a client with no armed clock publishes nothing.
    local bare = build({})
    local bare_ctx = bare.ST.PALADIN.practice_context(bare.ST, 1000, nil)
    eq(bare_ctx.pull_at, nil, "pull: an unarmed clock publishes no pull moment")
    eq(bare_ctx.pull_in_seconds, nil, "pull: an unarmed clock publishes no countdown")
    -- A non-numeric clock is never a guess.
    local broken = build({})
    broken.ST.pull_at = "soon"
    broken.ST.pull_in_seconds = function() return "soon" end
    local broken_ctx = broken.ST.PALADIN.practice_context(broken.ST, 1000, nil)
    eq(broken_ctx.pull_at, nil, "pull: a non-numeric moment is never published")
    eq(broken_ctx.pull_in_seconds, nil, "pull: a non-numeric countdown is never published")
end

--=========================================================================================
-- 25) The live-shaped ctx decides (F1), the rotation table is cited (F6), the running
--     order's slice is reachable (F8) and the APL layer carries the APL's rows
--
-- F1 (the audit's CRITICAL): the class's own ctx builder shadowed the shared
-- engine's gather-based fallback and was written for the TWIST SIM (it read the
-- session's swing_ends_at / gcd_expires / active_seals). Called with the addon
-- object - the shape the shared panel uses - those fields do not exist, the
-- inputs builder refused, the decision was nil and EVERY scenario step was
-- UNKNOWN (ten unknown steps, no attempt, no XP). The builder now falls back to
-- the class's OWN gathered guide inputs when the session state cannot answer the
-- timing, and the sim-shaped path is untouched.
--=========================================================================================
do
    local b = build({})
    local PC = b.ST.PALADIN

    -- ---- F1: the live-shaped ctx decides ---------------------------------------
    local ctx = PC.practice_context(b.ST, b.get_clock(), nil)
    check(type(ctx) == "table", "F1: the ctx builder answers a table")
    check(type(ctx.swing_remaining) == "number",
        "F1: the live ctx carries the swing clock (the gather's own read)")
    check(type(ctx.gcd_remaining) == "number",
        "F1: the live ctx carries the GCD clock")
    check(type(ctx.seal) == "string",
        "F1: the live ctx carries the seal state")
    check(type(ctx.resources) == "table" and ctx.resources.mana_pct ~= nil,
        "F1: the live ctx carries the gathered resources")
    check(ctx.cooldowns ~= nil and ctx.cooldowns.cs ~= nil,
        "F1: the live ctx carries the gathered cooldown rows")
    -- The decision: the scenario must DECIDE, not answer UNKNOWN.
    local decision = PC.practice_decision(b.ST, ctx)
    check(type(decision) == "table",
        "F1: the live-shaped ctx decides (the scenario is not UNKNOWN)")
    if type(decision) == "table" then
        check(decision.action ~= nil or decision.hold == true,
            "F1: the live-shaped decision names an action or an explicit hold")
    end
    local step = PC.practice_scenario_step(b.ST, ctx)
    check(type(step) == "table" and (step.action ~= nil or step.hold == true),
        "F1: the live-shaped scenario step answers (an action or a hold)")
    -- The shared engine's own grading of that step: the step must NOT be UNKNOWN.
    local pmod = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(pmod, b.env)
    local okp, errp = pcall(function() pmod("SwedgeTimer", b.st) end)
    check(okp, "F1: practice.lua loads in the paladin sandbox (" .. tostring(errp) .. ")")
    local H = b.st.practice and b.st.practice.harness
    check(type(H) == "table", "F1: the shared harness is loaded")
    local graded = H.practice_scenario_step("PALADIN", b.ST, ctx)
    check(type(graded) == "table" and (graded.action ~= nil or graded.hold == true),
        "F1: the shared engine grades the live-shaped step (not UNKNOWN)")
    -- The sim shape still answers on its own (the twist sim keeps its path).
    local sim = {
        swing_ends_at = 103.0, gcd_expires = 101.0, effective_speed = 3.5,
        effective_gcd = 1.5, active_seals = { command = true },
    }
    local sim_ctx = PC.practice_context(sim, 100, nil)
    eq(sim_ctx.swing_remaining, 3.0, "F1: the sim-shaped ctx still reads the sim clock")
    eq(sim_ctx.gcd_remaining, 1.0, "F1: the sim-shaped ctx still reads the sim GCD")
    eq(sim_ctx.seal, "soc", "F1: the sim-shaped ctx still reads the sim seals")
    eq(sim_ctx.speed, 3.5,
        "F1: the sim shape wins over the live fallback (the twist sim is untouched)")

    -- ---- F6: every rotation row is cited ---------------------------------------
    for i = 1, #PC.practice_rotation do
        local entry = PC.practice_rotation[i]
        check(type(entry.source) == "string" and entry.source ~= "",
            "F6: rotation entry " .. entry.action .. " cites its APL row")
        check(type(entry.note) == "string" and entry.note ~= "",
            "F6: rotation entry " .. entry.action .. " states what the row is")
        check(type(entry.families) == "table" and next(entry.families) ~= nil,
            "F6: rotation entry " .. entry.action .. " gates its families")
        -- The family gate: an id is only valid on a family the row plays.
        if type(entry.ids) == "table" then
            for family, id in pairs(entry.ids) do
                check(type(id) == "number",
                    "F6: rotation entry " .. entry.action .. " carries a numeric id for " .. family)
                check(entry.families[family] == true,
                    "F6: rotation entry " .. entry.action .. " gates the " .. family .. " id")
            end
        end
        -- The TBC family resolves every spell by NAME: a TBC row carries no
        -- numeric id, and names the spell instead (a macro row names neither).
        if entry.families and entry.families.TBC == true then
            check(entry.ids == nil or entry.ids.TBC == nil,
                "F6: rotation entry " .. entry.action .. " carries no numeric TBC id")
            local has_id = entry.ids ~= nil and next(entry.ids) ~= nil
            check((type(entry.tbc_name) == "string" and entry.tbc_name ~= "")
                or not has_id,
                "F6: rotation entry " .. entry.action .. " names the TBC spell")
        end
    end

    -- ---- F8: the running order's slice is reachable ----------------------------
    local slice = PC.practice_rotation_for()
    check(type(slice) == "table" and #slice > 0,
        "F8: the argument-free rotation_for answers the running order's slice")
    eq(slice[1].action, "cs",
        "F8: the running slice is the twist order (the TBC sandbox's order)")
    -- The live gather publishes the running order: it is the only place that
    -- knows which SoD variant the client plays.
    local gathered = PC.gather_guide_inputs(b.ST, {})
    check(type(gathered) == "table", "F8: the gather answers")
    eq(PC.practice_running_order, "twist",
        "F8: the gather publishes the running order (the twist tree on TBC)")
    -- Every shipped order has a slice (the SoD variants included).
    for _, order in ipairs({ "twist", "wrath", "sod", "sod_stack", "sod_shock",
        "sod_wrath" }) do
        local s = PC.practice_rotation_for(order)
        check(type(s) == "table" and #s > 0,
            "F8: the " .. order .. " rotation slice exists")
    end
    eq(PC.practice_rotation_for("nope"), nil,
        "F8: an unknown order still has no rotation")

    -- The SoD client: the ERA token with the SoD runes known names the Exodin
    -- order in the live gather, so the practice slice follows the live variant.
    local era = build({ project = 2 })
    era.known_spells[35395] = true
    local ectx = era.ST.PALADIN.practice_context(era.ST, era.get_clock(), nil)
    eq(era.ST.PALADIN.practice_running_order, "sod",
        "F8: the live gather names the SoD Exodin order on the SoD client")
    eq(ectx.fcfs_mode, "sod",
        "F8: the live ctx carries the FCFS mode the gather decided")
    local eslice = era.ST.PALADIN.practice_rotation_for()
    eq(eslice[1].action, "exo",
        "F8: the running slice is the Exodin order (Exorcism first)")
    eq(eslice[2].action, "cs",
        "F8: the Exodin slice puts Crusader Strike second")

    -- ---- M2: the family gate on the rotation slice -----------------------------
    -- The slice is the ORDER's rows, narrowed to the rows the running client's
    -- APL plays (each row's own `families` set - the same predicate the rogue,
    -- warrior and druid slices use, classes/rogue.lua:2858). The twist order is
    -- shared by the classic line (ERA / TBC / FOREVER), so the gate is what
    -- keeps one client's button out of another client's panel: the TBC
    -- rotation can never ask for the execute Hammer of Wrath (`how` is ERA /
    -- SOD / FOREVER), and pressing that button graded out_of_order = F for a
    -- spell the rotation never wanted.
    local tbc_slice = PC.practice_rotation_for("twist")
    local tbc_keys = {}
    for i = 1, #tbc_slice do tbc_keys[tbc_slice[i].action] = true end
    check(tbc_keys.how ~= true,
        "M2: the TBC slice carries no execute Hammer of Wrath (the TBC rotation never asks for it)")
    check(tbc_keys.cs == true,
        "M2: the TBC slice keeps Crusader Strike (the TBC APL plays it)")
    check(tbc_keys.judge == true and tbc_keys.twist == true and tbc_keys.soc == true
        and tbc_keys.sob == true,
        "M2: the TBC slice keeps the Judgement cue and the seal work")
    check(tbc_keys.cons == true and tbc_keys.exo == true,
        "M2: the TBC slice keeps the filler rows the TBC APL plays")
    -- The same order on another client: the plain Era client plays no Crusader
    -- Strike and no Seal of Blood, and its own execute Hammer of Wrath stays.
    local plain_era = build({ project = 2 })
    local era_slice = plain_era.ST.PALADIN.practice_rotation_for("twist")
    local era_keys = {}
    for i = 1, #era_slice do era_keys[era_slice[i].action] = true end
    check(era_keys.how == true,
        "M2: the Era slice keeps the execute Hammer of Wrath")
    check(era_keys.cs ~= true,
        "M2: the Era slice carries no Crusader Strike (the Era client has no such spell)")
    check(era_keys.sob ~= true,
        "M2: the Era slice carries no Seal of Blood (the Era client has no such seal)")
    -- The gate narrows, it never empties: every client that can run the
    -- rotation (the live swing engine) names at least one row.
    check(#tbc_slice > 0 and #era_slice > 0,
        "M2: the gate narrows the slice, it never empties it")
    -- The WotLK client: the band rows ride the Wrath order, and the Era
    -- execute Hammer of Wrath is not one of them.
    local wrath_slice_m2 = PC.practice_rotation_for("wrath")
    local wrath_keys = {}
    for i = 1, #wrath_slice_m2 do wrath_keys[wrath_slice_m2[i].action] = true end
    check(wrath_keys.hor == true and wrath_keys.how_wrath == true,
        "M2: the WotLK slice keeps the APL's utility band")
    check(wrath_keys.how ~= true,
        "M2: the WotLK slice carries no Era execute Hammer of Wrath")
    -- The SoD client: the SoD game runs on the ERA client, so the ORDER names
    -- the family (the SoD variants are their own orders) and the SoD rows stay.
    local sod_slice_m2 = era.ST.PALADIN.practice_rotation_for("sod")
    local sod_keys = {}
    for i = 1, #sod_slice_m2 do sod_keys[sod_slice_m2[i].action] = true end
    check(sod_keys.how == true and sod_keys.cs == true and sod_keys.sob ~= true,
        "M2: the SoD slice keeps the SoD rows (the order names the SoD family)")
    -- The gate rides the APL-row path too (the cited rows the shipped orders do
    -- not name). Every row there is engine-less today, so the shape carries the
    -- pin: a row another family's APL plays must never reach this client's
    -- button vocabulary.
    local pal_src_m2 = read("classes/paladin.lua")
    local apl_at = pal_src_m2:find(
        "local entry = ST.PALADIN.practice_rotation_entry(spec.action)", 1, true)
    check(apl_at ~= nil, "M2: the paladin source carries the APL-row path")
    if apl_at then
        local apl_stop = pal_src_m2:find("return out", apl_at, true)
        local apl_block = apl_stop and pal_src_m2:sub(apl_at, apl_stop) or ""
        check(apl_block:find("entry.families[family] == true", 1, true) ~= nil,
            "M2: the APL-row path carries the family gate too")
    end

    -- ---- The APL layer ---------------------------------------------------------
    local hor = PC.practice_rotation_entry("hor")
    check(type(hor) == "table",
        "APL: the rotation table carries the Hand of Reckoning row")
    if type(hor) == "table" then
        eq(hor.ids.WRATH, 67485, "APL: Hand of Reckoning is 67485 on WotLK")
        eq(hor.families.WRATH, true, "APL: Hand of Reckoning is Wrath-gated")
        check(hor.source:find("default.apl.json", 1, true) ~= nil,
            "APL: the Hand of Reckoning row cites the WotLK APL")
    end
    local howw = PC.practice_rotation_entry("how_wrath")
    check(type(howw) == "table",
        "APL: the rotation table carries the WotLK Hammer of Wrath row")
    if type(howw) == "table" then
        eq(howw.ids.WRATH, 48806, "APL: the WotLK Hammer of Wrath is 48806")
        eq(howw.families.WRATH, true, "APL: the WotLK Hammer of Wrath is Wrath-gated")
        -- The sim citation: ExtraCastCondition lives at :31-32 of the fetched
        -- file (:18 is the ManaCost line - the citation was off by 13 and is
        -- corrected, bench/paladin_apl_utility_build_2026-10-20.md).
        check(howw.source:find("hammer_of_wrath.go:31-32", 1, true) ~= nil,
            "APL: the WotLK Hammer of Wrath row cites the verified sim lines")
        check(howw.source:find("hammer_of_wrath.go:18", 1, true) == nil,
            "APL: the WotLK Hammer of Wrath row carries no stale sim line")
    end
    -- The rows are reachable: the WotLK slice carries them.
    local wrath_slice = PC.practice_rotation_for("wrath")
    local in_slice = {}
    for i = 1, #wrath_slice do
        in_slice[wrath_slice[i].action] = true
    end
    check(in_slice.hor == true,
        "APL: the WotLK slice carries the Hand of Reckoning row")
    check(in_slice.how_wrath == true,
        "APL: the WotLK slice carries the WotLK Hammer of Wrath row")
    -- Holy Wrath: the SoD stack build's APL row. The WotLK APL has none, and
    -- the row says so (bench/rotation_gap_vs_apl_2026-10-20.md §6.4).
    local hw = PC.practice_rotation_entry("hw")
    check(type(hw) == "table", "APL: the rotation table carries the Holy Wrath row")
    if type(hw) == "table" then
        eq(hw.families.SOD, true, "APL: Holy Wrath is the SoD stack build's row")
        check(hw.source:find("NO Holy Wrath row", 1, true) ~= nil,
            "APL: the Holy Wrath row states the WotLK APL has no such row")
    end
    -- HU-12: the combat rotation carries no PRE-PULL row; the pre-pull table does.
    for i = 1, #PC.practice_rotation do
        local entry = PC.practice_rotation[i]
        check(entry.source:find("Sanctity Aura", 1, true) == nil,
            "HU-12: the combat rotation carries no Sanctity Aura pre-pull row")
        check(entry.source:find("Retribution Aura", 1, true) == nil,
            "HU-12: the combat rotation carries no Retribution Aura pre-pull row")
    end
    local prepull = PC.practice_prepull_rows
    check(type(prepull) == "table" and #prepull == 11,
        "HU-12: the pre-pull table carries the APL's pre-pull rows")
    if type(prepull) == "table" and #prepull == 11 then
        eq(prepull[1].id, 20218, "HU-12: the pre-pull table carries Sanctity Aura (20218)")
        eq(prepull[1].families.TBC, true, "HU-12: Sanctity Aura is TBC-gated")
        eq(prepull[1].lead, 18.5, "HU-12: Sanctity Aura goes up 18.5 s before the pull")
        eq(prepull[2].id, 10301, "HU-12: the pre-pull table carries 10301 (Retribution Aura)")
        eq(prepull[2].families.FOREVER, true, "HU-12: 10301 is Forever-gated")
        eq(prepull[2].lead, 10, "HU-12: 10301 goes up 10 s before the pull")
        eq(prepull[2].label, "Retribution Aura",
            "HU-12: 10301 is Retribution Aura (the name is confirmed - the gap analysis said Redemption)")
        -- The TBC pre-pull groups (PrepullSeal / PrepullJudge / PullSeal).
        eq(prepull[3].id, 20375, "HU-12: the TBC PrepullSeal group carries Seal of Command (20375)")
        eq(prepull[3].lead, 1.5, "HU-12: the TBC PrepullSeal group is at -1.5 s")
        eq(prepull[3].families.TBC, true, "HU-12: the TBC Seal of Command pre-pull is TBC-gated")
        eq(prepull[4].id, 27158, "HU-12: the TBC PrepullSeal group carries Seal of the Crusader (27158)")
        eq(prepull[4].lead, 1.5, "HU-12: the TBC Seal of the Crusader pre-pull is at -1.5 s")
        eq(prepull[5].id, 20271, "HU-12: the TBC PrepullJudge group carries Judgement (20271)")
        eq(prepull[5].lead, 0, "HU-12: the TBC Judgement pre-pull is at 0 s")
        eq(prepull[6].id, 31892, "HU-12: the TBC PullSeal group carries Seal of Blood (31892)")
        eq(prepull[6].lead, 0, "HU-12: the TBC Seal of Blood pull is at 0 s")
        eq(prepull[7].id, 20375, "HU-12: the TBC PullSeal group's other branch is Seal of Command (20375)")
        eq(prepull[7].lead, 0, "HU-12: the TBC Seal of Command pull is at 0 s")
        -- The Forever pre-pull rows (twist_of_light).
        eq(prepull[8].id, 20920, "HU-12: the Forever pre-pull carries Seal of Command (20920 r5)")
        eq(prepull[8].lead, 3, "HU-12: the Forever Seal of Command pre-pull is at -3 s")
        eq(prepull[8].families.FOREVER, true, "HU-12: the Forever Seal of Command pre-pull is Forever-gated")
        eq(prepull[9].id, 20308, "HU-12: the Forever pre-pull carries Seal of the Crusader (20308 r6)")
        eq(prepull[9].lead, 1.5, "HU-12: the Forever Seal of the Crusader pre-pull is at -1.5 s")
        -- The SoD stack pre-pull rows.
        eq(prepull[10].id, 20920, "HU-12: the SoD stack pre-pull carries Seal of Command (20920 r5)")
        eq(prepull[10].lead, 3, "HU-12: the SoD Seal of Command pre-pull is at -3 s")
        eq(prepull[10].families.SOD, true, "HU-12: the SoD Seal of Command pre-pull is SoD-gated")
        eq(prepull[11].id, 407798, "HU-12: the SoD stack pre-pull carries Seal of Martyrdom (407798)")
        eq(prepull[11].lead, 1.5, "HU-12: the SoD Seal of Martyrdom pre-pull is at -1.5 s")
        -- Every pre-pull row is cited and family-gated; none of them is a
        -- combat rotation row.
        for i = 1, #prepull do
            check(type(prepull[i].source) == "string" and prepull[i].source ~= "",
                "HU-12: every pre-pull row cites its APL")
            check(type(prepull[i].families) == "table",
                "HU-12: every pre-pull row carries a family gate")
        end
    end
end

--=========================================================================================
-- 26) The APL UTILITY LAYER (bench/paladin_apl_utility_build_2026-10-20.md)
--
-- The rotation table carries the APL's utility rows: cited, family-gated, with
-- HU-13's two flags (live = the read exists; engine = the frozen engine has an
-- arm). The armed rows ride the engine's Wrath order and light a guide slot;
-- the un-armed rows ship with the exact read they wait for in `needs` and stay
-- out of the practice panel's button vocabulary.
--=========================================================================================
do
    local b = build({})
    local PC = b.ST.PALADIN

    -- ---- the flags are on every row (HU-13's two STRICT booleans) -------------
    -- A truthiness test (`entry.live ~= nil`) would pass for "no", 0 and "" - a
    -- paladin row marked "armed" with a truthy non-boolean would then be offered
    -- as a scorable answer. Both flags are BOOLEANS, never a truthy stand-in.
    local flags_ok, needs_ok = true, true
    for i = 1, #PC.practice_rotation do
        local entry = PC.practice_rotation[i]
        if type(entry.live) ~= "boolean" or type(entry.engine) ~= "boolean" then
            flags_ok = false
        end
        -- The cross-row rule the other five classes enforce: a row that is not
        -- fully usable names what it still waits for, in `needs` - never an
        -- empty string. The paladin files on the ARM axis (its three armed rows
        -- are live but claim no arm), so the rule covers BOTH axes: a row that
        -- is unread (live == false) or that carries no arm (engine == false)
        -- must name its need.
        if (entry.live == false or entry.engine == false)
            and (type(entry.needs) ~= "string" or entry.needs == "") then
            needs_ok = false
        end
    end
    check(flags_ok,
        "HU-13: every rotation row declares the live and engine flags as BOOLEANS")
    check(needs_ok,
        "HU-13: every rotation row that waits for a read or for an arm names it in `needs`")

    -- ---- the ids' single source of truth ---------------------------------------
    check(type(PC.APL_UTILITY) == "table", "utility: the APL id table exists")
    eq(PC.APL_UTILITY.hor.id, 67485, "utility: the id table carries Hand of Reckoning 67485")
    eq(PC.APL_UTILITY.how_wrath.id, 48806, "utility: the id table carries Hammer of Wrath 48806")
    eq(PC.APL_UTILITY.judgement_of_wisdom.id, 53408,
        "utility: the id table carries Judgement of Wisdom 53408")
    eq(PC.APL_UTILITY.holy_strike.id, 10333, "utility: the id table carries Holy Strike 10333")
    eq(PC.APL_UTILITY.divine_favor.id, 20216, "utility: the id table carries Divine Favor 20216")

    -- ---- Hand of Reckoning (the WotLK APL's i=1): ARMED ------------------------
    local hor = PC.practice_rotation_entry("hor")
    check(type(hor) == "table", "utility: the rotation table carries Hand of Reckoning")
    if type(hor) == "table" then
        eq(hor.ids.WRATH, 67485, "utility: Hand of Reckoning is 67485")
        eq(hor.families.WRATH, true, "utility: Hand of Reckoning is Wrath-gated")
        eq(hor.live, true, "utility: Hand of Reckoning's read exists (live)")
        eq(hor.engine, true, "utility: Hand of Reckoning has an engine arm")
        check(hor.source:find("default.apl.json", 1, true) ~= nil,
            "utility: the Hand of Reckoning row cites the WotLK APL")
        check(hor.source:find("i=1", 1, true) ~= nil,
            "utility: the Hand of Reckoning row cites the APL's position")
    end

    -- ---- Hammer of Wrath (the WotLK APL's i=2): ARMED --------------------------
    local howw = PC.practice_rotation_entry("how_wrath")
    check(type(howw) == "table", "utility: the rotation table carries the WotLK Hammer of Wrath")
    if type(howw) == "table" then
        eq(howw.ids.WRATH, 48806, "utility: the WotLK Hammer of Wrath is 48806")
        eq(howw.families.WRATH, true, "utility: the WotLK Hammer of Wrath is Wrath-gated")
        eq(howw.live, true, "utility: the WotLK Hammer of Wrath's read exists (live)")
        eq(howw.engine, true, "utility: the WotLK Hammer of Wrath has an engine arm")
        check(howw.source:find("i=2", 1, true) ~= nil,
            "utility: the WotLK Hammer of Wrath row cites the APL's position")
        check(howw.source:find("20%", 1, true) ~= nil,
            "utility: the WotLK Hammer of Wrath row cites the execute-phase gate")
    end

    -- ---- Judgement of Wisdom (the WotLK APL's i=3): FILED ----------------------
    local jow = PC.practice_rotation_entry("judgement_of_wisdom")
    check(type(jow) == "table", "utility: the rotation table carries Judgement of Wisdom")
    if type(jow) == "table" then
        eq(jow.ids.WRATH, 53408, "utility: Judgement of Wisdom is 53408")
        eq(jow.families.WRATH, true, "utility: Judgement of Wisdom is Wrath-gated")
        eq(jow.live, true, "utility: Judgement of Wisdom's read exists (live)")
        eq(jow.engine, false, "utility: Judgement of Wisdom claims NO engine arm")
        check(type(jow.needs) == "string" and jow.needs ~= "",
            "utility: Judgement of Wisdom names the read it waits for")
        check(jow.needs:find("cooldown", 1, true) ~= nil,
            "utility: Judgement of Wisdom's filing names the shared cooldown")
    end

    -- ---- Holy Strike (the Forever APL's i=3/i=7): FILED -----------------------
    local hs = PC.practice_rotation_entry("holy_strike")
    check(type(hs) == "table", "utility: the rotation table carries Holy Strike")
    if type(hs) == "table" then
        eq(hs.ids.FOREVER, 10333, "utility: Holy Strike is 10333")
        eq(hs.families.FOREVER, true, "utility: Holy Strike is Forever-gated")
        eq(hs.live, true, "utility: Holy Strike's read exists (live)")
        eq(hs.engine, false, "utility: Holy Strike claims NO engine arm")
        check(type(hs.needs) == "string" and hs.needs ~= "",
            "utility: Holy Strike names the read it waits for")
    end

    -- ---- Divine Favor (the Forever APL's i=8): FILED --------------------------
    local df = PC.practice_rotation_entry("divine_favor")
    check(type(df) == "table", "utility: the rotation table carries Divine Favor")
    if type(df) == "table" then
        eq(df.ids.FOREVER, 20216, "utility: Divine Favor is 20216")
        eq(df.families.FOREVER, true, "utility: Divine Favor is Forever-gated")
        eq(df.live, true, "utility: Divine Favor's read exists (live)")
        eq(df.engine, false, "utility: Divine Favor claims NO engine arm")
        check(type(df.needs) == "string" and df.needs ~= "",
            "utility: Divine Favor names the read it waits for")
        eq(df.label, "Divine Favor", "utility: the Divine Favor row's label names the spell")
        check(df.source:find("Divine Favor", 1, true) ~= nil,
            "utility: the Divine Favor row names the spell (the corpus said Devotion Aura)")
        check(df.source:find("NAME CORRECTION", 1, true) ~= nil,
            "utility: the Divine Favor row carries the corpus correction")
        check(df.source:find("20216", 1, true) ~= nil,
            "utility: the Divine Favor row cites its id")
    end

    -- ---- the corpus corrections the lane proved --------------------------------
    local judge = PC.practice_rotation_entry("judge")
    check(type(judge) == "table" and judge.source:find("Judgement of Wisdom", 1, true) ~= nil,
        "correction: the shipped judge row names 53408 Judgement of Wisdom")
    check(type(judge) == "table" and judge.source:find("JUDGEMENT OF LIGHT 53408", 1, true) == nil,
        "correction: the shipped judge row no longer calls 53408 Judgement of Light")
    local prepull = PC.practice_prepull_rows
    check(type(prepull) == "table" and prepull[2].label == "Retribution Aura",
        "correction: 10301 is Retribution Aura (the corpus said Redemption)")

    -- ---- the slice: the engine-facing rows only -------------------------------
    local wrath_slice = PC.practice_rotation_for("wrath")
    local in_slice = {}
    for i = 1, #wrath_slice do
        in_slice[wrath_slice[i].action] = true
    end
    check(in_slice.hor == true, "utility: the Wrath slice carries Hand of Reckoning")
    check(in_slice.how_wrath == true, "utility: the Wrath slice carries the WotLK Hammer of Wrath")
    check(in_slice.judgement_of_wisdom ~= true,
        "utility: a row with no engine arm stays out of the practice button vocabulary")
    check(#wrath_slice > 0 and wrath_slice[1].action == "hor",
        "utility: the Wrath slice leads with the APL's top row")
    local twist_slice = PC.practice_rotation_for("twist")
    local in_twist = {}
    for i = 1, #twist_slice do
        in_twist[twist_slice[i].action] = true
    end
    check(in_twist.holy_strike ~= true,
        "utility: Holy Strike (no arm) stays out of the practice button vocabulary")
    check(in_twist.divine_favor ~= true,
        "utility: Divine Favor (no arm) stays out of the practice button vocabulary")

    -- ---- the guide slots ------------------------------------------------------
    local slots = PC.guide.slots
    eq(#slots, 12, "utility: the guide carries the two new APL-band slots")
    local slot_keys = {}
    for i = 1, #slots do
        slot_keys[slots[i].key] = slots[i]
    end
    check(type(slot_keys.hor) == "table" and slot_keys.hor.spell_id == 67485,
        "utility: the guide has a Hand of Reckoning slot (67485)")
    check(type(slot_keys.how_wrath) == "table" and slot_keys.how_wrath.spell_id == 48806,
        "utility: the guide has a WotLK Hammer of Wrath slot (48806)")
end

-- ---- the gather's reads: the WotLK utility band --------------------------------
do
    local w = build({ project = 11, interface = 38002 })
    local W = w.ST
    W.PALADIN.post_init(W)
    local inputs = W.PALADIN.gather_guide_inputs(W)
    eq(w.st.family, "WRATH", "utility gather: the Wrath family profile")
    eq(inputs.hor_remaining, nil,
        "utility gather: an unknown Hand of Reckoning reads nil (unknown-hides)")
    eq(inputs.how_wrath_remaining, nil,
        "utility gather: an unknown WotLK Hammer of Wrath reads nil (unknown-hides)")
    w.known_spells[67485] = true
    w.known_spells[48806] = true
    inputs = W.PALADIN.gather_guide_inputs(W)
    eq(inputs.hor_remaining, 0, "utility gather: a known Hand of Reckoning reads ready")
    eq(inputs.how_wrath_remaining, 0, "utility gather: a known WotLK Hammer of Wrath reads ready")
    -- A real cooldown reads the remaining seconds.
    w.set_clock(w.get_clock() + 10)
    w.cooldowns[67485] = { start = w.get_clock(), duration = 30 }
    inputs = W.PALADIN.gather_guide_inputs(W)
    eq(inputs.hor_remaining, 30, "utility gather: a live Hand of Reckoning cooldown reads through")
    -- The execute gate's read: the target health reaches the WotLK client.
    check(type(inputs.target_health_pct) == "number" or inputs.target_health_pct == nil,
        "utility gather: the Wrath target health is a number or nil (never a guess)")
end
do
    -- Every other family: the band reads nil (the rows never leak across).
    local e = build({ project = 2, interface = 11509 })
    local E = e.ST
    E.PALADIN.post_init(E)
    local inputs = E.PALADIN.gather_guide_inputs(E)
    eq(inputs.hor_remaining, nil, "utility gather: the Era client never reads Hand of Reckoning")
    eq(inputs.how_wrath_remaining, nil,
        "utility gather: the Era client never reads the WotLK Hammer of Wrath")
    -- The family gate is a real gate: the Era client never even asks its book
    -- about the WotLK-only spells.
    local asked = false
    for i = 1, #e.known_queries do
        local q = e.known_queries[i]
        if q == 67485 or q == 48806 then
            asked = true
        end
    end
    check(asked == false,
        "utility gather: the Era client never asks its book about the WotLK-only spells")
end

-- ---- the engine's answer reaches the practice key space ----------------------
do
    local b = build({})
    local PC = b.ST.PALADIN
    -- The engine's Wrath order asks for Hand of Reckoning first; the practice
    -- mapping must name the press (the panel grades the key).
    local na = b.st.nextaction
    local out = {}
    na.evaluate_fcfs({
        fcfs_mode = "wrath", G = 1.5, gcd_remaining = 0,
        cs_known = true, cs_remaining = 0, judge_remaining = 0,
        ds_remaining = 0, cons_remaining = 0, exo_remaining = 0,
        hw_remaining = 0, how_remaining = 0,
        hor_remaining = 0, how_wrath_remaining = 0,
        target_health_pct = 10, mana_pct = 100, creature_type = "Undead",
        has_aow = true,
    }, out)
    eq(out.action, "hor", "utility engine: a ready Hand of Reckoning wins the Wrath order")
    local decision = PC.practice_decision(b.ST, {
        now = 100, swing_remaining = 1, gcd_remaining = 0, seal = "soc",
        fcfs_mode = "wrath", cs_known = true,
        cooldowns = { hor = 0, how_wrath = 0 },
        resources = { target_health_pct = 10, mana_pct = 100, creature_type = "Undead" },
    })
    check(type(decision) == "table", "utility engine: the practice decision answers")
    if type(decision) == "table" then
        eq(decision.action, "hor",
            "utility engine: the practice key space names Hand of Reckoning")
    end
end

-- ---- the NEUTRAL publish is family-scoped (the Seal of the Crusader) --------
-- The audit (bench/final_gate_audit_2026-10-20.md MEDIUM-2) found the flat
-- publish claiming the Seal of the Crusader on the 4.0+ clients, where the
-- spell was removed in 4.0 - a dead button on the Cata and the Mists panel.
-- The publish is now ONE BUCKET PER FAMILY: the classic line keeps the seal,
-- the 4.0+ clients publish the same set without it. Every other key stays on
-- every family (the class publishes no rotation there, so none of them is
-- rotation-ranked and each is a legitimate, ungraded press).
do
    local FAMILIES = {
        { project = 2, interface = 11509, family = "ERA", seal = true },
        { project = 5, interface = 20506, family = "TBC", seal = true },
        { project = 11, interface = 38002, family = "WRATH", seal = true },
        { project = 18, interface = 16001, family = "FOREVER", seal = true },
        { project = 14, interface = 40402, family = "CATA", seal = false },
        { project = 19, interface = 50500, family = "MISTS", seal = false },
        { project = 1, interface = 120100, family = "RETAIL", seal = false },
    }
    -- The keys every family publishes (the twist sim's own grid keys and the
    -- common abilities the practice panel offers).
    local SHARED = {
        "aw", "hpot", "abacus", "stop", "holy_light", "flash_of_light",
        "lay_on_hands", "divine_shield", "bop", "food",
    }
    for _, spec in ipairs(FAMILIES) do
        local b = build({ project = spec.project, interface = spec.interface })
        local PC = b.ST.PALADIN
        local published = PC.practice_neutral_actions
        eq(type(published), "table", "neutral publish: the paladin publishes a set")
        -- family-scoped: every entry is a bucket, never a flat key
        local flat_key = nil
        for key, value in pairs(published) do
            if type(value) ~= "table" then flat_key = key end
        end
        check(flat_key == nil,
            "neutral publish: the publish is family-scoped (one bucket per family)"
            .. (flat_key and (" (a flat key: " .. tostring(flat_key) .. ")") or ""))
        local set = PC.practice_neutral_set()
        eq(type(set), "table", "neutral publish: the " .. spec.family .. " bucket resolves")
        if type(set) == "table" then
            eq(set.sotc == true, spec.seal,
                "neutral publish: the Seal of the Crusader is neutral on " .. spec.family
                .. " (the 4.0 clients removed the spell)")
            for _, key in ipairs(SHARED) do
                eq(set[key] == true, true,
                    "neutral publish: " .. key .. " stays neutral on " .. spec.family)
            end
            -- nothing else is published
            for key, value in pairs(set) do
                check(key ~= "" and value == true,
                    "neutral publish: every published key on " .. spec.family .. " is a true flag")
            end
        end
    end
end

-- ---- the style constants ride the module table (the local ceiling) ---------
-- The class module sits at Lua 5.1's 200-local ceiling, so its display
-- constants live on the module table (the class's own APL_UTILITY precedent).
-- The values are the archive's own, unchanged by the move - pinned here so a
-- later edit cannot quietly change one.
do
    local b = build({})
    local PC = b.ST.PALADIN
    eq(type(PC.aow_pulse), "table", "style: the overlap pulse rides the module table")
    eq(PC.aow_pulse.key, "AowExoOverlap", "style: the overlap pulse keeps its glow key")
    eq(PC.aow_pulse.seconds, 0.4, "style: the overlap pulse keeps its 0.4 s length")
    eq(PC.aow_pulse.lines, 8, "style: the overlap pulse keeps its line count")
    eq(PC.aow_pulse.frequency, 0.25, "style: the overlap pulse keeps its frequency")
    eq(PC.aow_pulse.thickness, 2, "style: the overlap pulse keeps its thickness")
    eq(type(PC.aow_pulse.color), "table", "style: the overlap pulse carries a colour")
    eq(PC.aow_pulse.color[1], 255, "style: the overlap pulse colour keeps its red channel")
    eq(type(PC.twist_colors), "table", "style: the twist colours ride the module table")
    eq(PC.twist_colors.marker[4], 0.35, "style: the twist marker colour keeps its alpha")
    eq(PC.twist_colors.twisting[2], 26, "style: the twisting colour keeps its green channel")
    eq(PC.twist_colors.cant[1], 212, "style: the cant-twist colour keeps its red channel")
    eq(PC.twist_colors.success[2], 255, "style: the twist-success colour keeps its green channel")
    eq(PC.twist_colors.glow[2], 255, "style: the twist glow colour keeps its green channel")
    eq(type(PC.twist_glow), "table", "style: the twist glow rides the module table")
    eq(PC.twist_glow.key, "TwistSuccess", "style: the twist glow keeps its glow key")
    eq(PC.twist_glow.lines, 8, "style: the twist glow keeps its line count")
    eq(PC.twist_glow.frequency, 0.25, "style: the twist glow keeps its frequency")
    eq(PC.twist_glow.thickness, 2, "style: the twist glow keeps its thickness")
end

-- ---- the shipped comment matches the code (the audit's HIGH-2) --------------
-- The resolver note claimed "every client family answers its own rank art":
-- the fallback hands the ERA corpus's rank-1 id, not the client's own art, and
-- the classic-line name leg is UNCONFIRMED in-client. The pin keeps the stale
-- claim OUT (a source-shape pin on its ABSENCE, so a correct rewording passes).
do
    local f = io.open(ROOT .. "classes/paladin.lua", "r")
    local src = f and f:read("*a") or ""
    if f then f:close() end
    local flat = src:gsub("\r\n", "\n")
    check(flat:find("every client family answers its own rank art", 1, true) == nil,
        "comment: the stale 'every client family answers its own rank art' claim is gone")
    check(flat:find("answers its own rank id", 1, true) ~= nil,
        "comment: the resolver note says what the code does")
end

--=========================================================================================
-- R1 name-carrying payloads: a landed Exorcism arms the cooldown latch by id
-- or by name on every family (id primary, name secondary). Exorcism is an
-- instant, so SUCCEEDED is its only event; a TBC Anniversary payload carries
-- the name in the guid slot with a nil id. A foreign name changes nothing.
--=========================================================================================
do
    -- Era: the numeric id arms the latch, and the literal English name does too.
    local b = build({ project = 2 })
    local T = b.ST
    T.exo_on_cooldown = false
    T.PALADIN.on_spellcast_succeeded(T, "target", "cast-1", 879)
    eq(T.exo_on_cooldown, true, "Era: a numeric-id Exorcism arms the latch")

    T.exo_on_cooldown = false
    b.timer_afters = {}
    T.PALADIN.on_spellcast_succeeded(T, "target", "Exorcism", nil)
    eq(T.exo_on_cooldown, true, "Era: the Exorcism name arms the latch too")

    -- The client's own localized name arms it through the resolved spell data.
    T.exo_on_cooldown = false
    b.timer_afters = {}
    b.spell_infos[879] = { name = "Exorcismo", icon = "icon_exo" }
    T.PALADIN.on_spellcast_succeeded(T, "target", "Exorcismo", nil)
    eq(T.exo_on_cooldown, true, "Era: the localized name arms the latch too")

    -- A foreign name must change nothing.
    T.exo_on_cooldown = false
    b.timer_afters = {}
    T.PALADIN.on_spellcast_succeeded(T, "target", "Scare Beast", nil)
    eq(T.exo_on_cooldown, false, "Era: an unrelated name leaves the latch alone")
end

do
    -- TBC Anniversary: the name rides the guid slot with a nil id; a numeric
    -- id still arms the latch through the rank table.
    local b = build({ project = 5 })
    local T = b.ST
    T.exo_on_cooldown = false
    T.PALADIN.on_spellcast_succeeded(T, "target", "Exorcism", nil)
    eq(T.exo_on_cooldown, true, "TBC: a name-carrying Exorcism arms the latch")

    T.exo_on_cooldown = false
    b.timer_afters = {}
    T.PALADIN.on_spellcast_succeeded(T, "target", "cast-2", 27138)
    eq(T.exo_on_cooldown, true, "TBC: a numeric TBC-rank id still arms the latch")

    -- A foreign name must change nothing.
    T.exo_on_cooldown = false
    b.timer_afters = {}
    T.PALADIN.on_spellcast_succeeded(T, "target", "Scare Beast", nil)
    eq(T.exo_on_cooldown, false, "TBC: an unrelated name leaves the latch alone")
end

if failures == 0 then
    print("PASS  paladin_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  paladin_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
