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
    function t:SetPoint() end
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
    function f:SetPoint() end
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

local function make_frame(name)
    local f = { name = name, shown = false }
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
    env.CreateFrame = function(...) return make_frame(select(2, ...)) end
    env.GetSpellInfo = function(spell)
        spell_info_reads = spell_info_reads + 1
        local info = spell_infos[spell]
        if info then
            return info.name, nil, info.icon, 0, 0, 0, spell
        end
        return nil
    end
    env.GetSpellCooldown = function(spell)
        local cd = cooldowns[spell]
        if cd then
            return cd.start or 0, cd.duration or 0, 1, 0
        end
        return 0, 0, 0, 0
    end
    env.GetSpellBaseCooldown = function() return 15000, 0 end
    env.IsSpellKnown = function(spell) return known_spells[spell] == true end
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
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibCustomGlow-1.0" then
            return LCG
        elseif major == "LibSharedMedia-3.0" then
            return LSM
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
    "update_seal_icons", "on_twist_attempt", "on_successful_twist",
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
    check(notices[1]:find("twist proc payloads", 1, true) ~= nil,
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

if failures == 0 then
    print("PASS  paladin_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  paladin_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
