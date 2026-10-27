-- tests/practice_timeline_state.lua: the MOVING practice timeline (the cue strip).
--
-- One self-contained suite for the whole timeline contract:
--   * the pure playhead / window / slice / cadence maths in practice.lua;
--   * the strip's schedule contract in practice_ui.lua (provider, cadence fallback,
--     empty provider, absent class, off, pool reuse, stop-clear, pause freeze).
--
-- The sandbox builds the REAL modules (compat / utils / guard / nextaction / weave /
-- practice / practice_ui) and only the strip itself - it never runs ui.init, so no
-- panel/result/keybind surface is faked here. That keeps this suite honest: every
-- assertion drives the shipped function, and the fixtures only supply the class
-- tables a class would publish.
--
-- Run from the repo root: lua5.1 tests/practice_timeline_state.lua  (any cwd works).

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
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- Minimal frame stubs: exactly the surface the cue strip touches
--=========================================================================================
local function make_texture()
    local t = { hidden = false }
    function t:SetAllPoints() end
    function t:SetPoint(point, anchor, relative_point, x, y)
        t.point = { point, anchor, relative_point, x, y }
    end
    function t:SetSize(w, h) t.width, t.height = w, h end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetTexCoord() end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetColorTexture(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetDrawLayer() end
    function t:SetAlpha(a) t.alpha = a end
    function t:ClearAllPoints() t.point = nil end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetFontObject(obj) f.font_object = obj end
    function f:SetFont(path, size, flags)
        if path == nil then
            return false
        end
        f.font = { path, size, flags }
        return true
    end
    function f:GetFont()
        if f.font then return f.font[1] end
        if f.font_object then return f.font_object end
        return nil
    end
    function f:SetText(text)
        if f.font == nil and f.font_object == nil then
            error("Font not set", 2)
        end
        f.text = text
    end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:SetWidth(w) f.width = w end
    function f:SetWordWrap(wrap) f.word_wrap = wrap end
    function f:SetJustifyH(j) f.justify = j end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

local function make_frame()
    local f = { shown = true }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetWidth(w) f.width = w end
    function f:SetHeight(h) f.height = h end
    function f:GetWidth() return f.width or 0 end
    function f:GetHeight() return f.height or 0 end
    function f:GetCenter() return f.center_x or 0, f.center_y or 0 end
    function f:SetPoint(point, anchor, relative_point, x, y)
        f.point = { point, anchor, relative_point, x, y }
    end
    function f:ClearAllPoints() f.point = nil end
    function f:SetFrameStrata(strata) f.strata = strata end
    function f:GetFrameStrata() return f.strata end
    function f:SetFrameLevel(level) f.frame_level = level end
    function f:GetFrameLevel() return f.frame_level or 0 end
    function f:SetClampedToScreen(clamped) f.clamped = clamped end
    function f:SetMovable(movable) f.movable = movable end
    function f:EnableMouse(enabled) f.mouse = enabled end
    function f:RegisterForDrag(button) f.drag_buttons = button end
    function f:SetParent(parent) f.parent = parent end
    function f:GetName() return f.name end
    function f:SetScript(event, fn)
        f.scripts = f.scripts or {}
        f.scripts[event] = fn
    end
    function f:GetScript(event) return f.scripts and f.scripts[event] or nil end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown end
    function f:SetAlpha(alpha) f.alpha = alpha end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:GetLeft() return f.left end
    function f:GetTop() return f.top end
    function f:GetRight() return f.right end
    function f:CreateTexture() return make_texture() end
    function f:CreateFontString() return make_fontstring() end
    function f:SetBackdrop(backdrop) f.backdrop = backdrop end
    function f:SetBackdropColor(r, g, b, a) f.backdrop_color = { r, g, b, a } end
    function f:SetBackdropBorderColor(r, g, b, a) f.backdrop_border_color = { r, g, b, a } end
    return f
end

--=========================================================================================
-- The sandbox: the real modules over a scripted clock
--=========================================================================================
local function build()
    local sb = { clock = 0, frames = {}, created = 0 }

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTime = function() return sb.clock end
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetBuildInfo = function() return "3.3.5", "12340", "today", 38002 end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GameFontNormal = "GameFontNormal"
    env.GameFontHighlightSmall = "GameFontHighlightSmall"
    env.NumberFontNormalSmallGray = "NumberFontNormalSmallGray"
    env.UIParent = make_frame()
    env.CreateFrame = function(kind, name, parent, template)
        sb.created = sb.created + 1
        local f = make_frame()
        f.kind, f.name, f.parent, f.template = kind, name, parent, template
        sb.frames[#sb.frames + 1] = f
        return f
    end
    env.InCombatLockdown = function() return false end
    env.C_Timer = { After = function() end }
    -- The client's spell data: enough for the lane icons and the cue art lookups.
    env.GetSpellInfo = function(spell_id)
        return "Spell " .. tostring(spell_id), nil, "icon_spell_" .. tostring(spell_id), 0, 0, 0, spell_id
    end
    env.GetSpellTexture = function(spell_id)
        return "icon_spell_" .. tostring(spell_id)
    end
    env.GetItemIcon = function(item_id) return "icon_item_" .. tostring(item_id) end
    env.UnitAttackSpeed = function() return 2.6 end
    env.IsControlKeyDown = function() return false end
    env.IsAltKeyDown = function() return false end
    env.IsShiftKeyDown = function() return false end

    local st = {}
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    -- compat reads several legacy globals through rawget(_G, ...): mirror them while
    -- it loads, then restore _G exactly (same discipline as practice_ui_state.lua).
    local mirrored, names = {}, {}
    for name, value in pairs(env) do
        mirrored[name] = rawget(_G, name)
        names[#names + 1] = name
        _G[name] = value
    end
    compat("SwedgeTimer", st)
    for _, name in ipairs(names) do
        _G[name] = mirrored[name]
    end

    for _, path in ipairs({ "utils.lua", "guard.lua", "nextaction.lua", "weave.lua", "practice.lua" }) do
        local chunk = assert(loadfile(ROOT .. path))
        setfenv(chunk, env)
        chunk("SwedgeTimer", st)
    end

    -- The addon object: only the surface the strip reads.
    local class_db = { practice_result_duration = 0.8 }
    local ST = { player_class = "PALADIN", active_class = "PALADIN", in_combat = false }
    function ST:Print() end
    function ST:get_class_table() return class_db end
    function ST:get_hand_table() return { text_font = "Expressway" } end
    function ST:get_bar_frame() return nil end
    function ST:set_bar_color() end
    function ST:show_bar() end
    function ST:on_bar_inactive() end
    function ST:handle_bar_visibility() end
    function ST:set_gcd_times_before_swing_seconds() end
    function ST:on_gcd_length_change() end

    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        end
        return {}
    end

    local pui = assert(loadfile(ROOT .. "practice_ui.lua"))
    setfenv(pui, env)
    local ok, err = pcall(pui, "SwedgeTimer", st)
    if not ok then
        print("FAIL  practice_ui.lua does not load under the timeline sandbox: " .. tostring(err))
        os.exit(1)
    end

    local ui = st.practice_ui
    -- The strip only needs a panel to hang off: ui.init is deliberately NOT run, so
    -- this suite owns no result frame, keybinds or proc icons.
    ui.panel = make_frame()

    sb.env, sb.st, sb.ST, sb.class_db = env, st, ST, class_db
    return { ui = ui, st = st, ST = ST, sb = sb, pr = st.practice, env = env }
end

--=========================================================================================
-- 1) The pure playhead maths: playhead_x / pps / event_x / window
--=========================================================================================
do
    local b = build()
    local pr = b.pr

    near(pr.TL_PLAYHEAD_FRACTION, 0.25, "the playhead sits a quarter of the way in")
    near(pr.TL_HORIZON_SECONDS, 10, "the visible horizon is ten seconds (the reference strip)")

    -- A 600 px strip at 25%: the playhead at 150 px, 75 px/s so six seconds fill
    -- the 450 px to its right (and 2 s of history fit on the left).
    near(pr.timeline_playhead_x(600, 0.25), 150, "playhead_x: 25% of 600 px is 150 px")
    near(pr.timeline_pps(600, 0.25, 6), 75, "pps: six seconds fill the 450 px right of the playhead")
    near(pr.timeline_playhead_x(600), 150, "playhead_x: the shipped fraction is the default")
    near(pr.timeline_playhead_x(0, 0.25), 0, "playhead_x: a zero strip answers 0")
    near(pr.timeline_playhead_x(600, -1), 0, "playhead_x: a negative fraction clamps to the left edge")
    near(pr.timeline_playhead_x(600, 2), 600, "playhead_x: a fraction above 1 clamps to the right edge")
    near(pr.timeline_pps(600, 0.25, 0), 0, "pps: a zero horizon has no scale")
    near(pr.timeline_pps(0, 0.25, 6), 0, "pps: a zero strip has no scale")

    -- NOW / PAST / FUTURE: an action at the clock sits ON the playhead, an upcoming
    -- one sits to its right, a past one to its left.
    near(pr.timeline_event_x(150, 10, 10, 75), 150, "event_x: at `now` the icon is on the playhead")
    near(pr.timeline_event_x(150, 11, 10, 75), 225, "event_x: one second ahead is one second right")
    near(pr.timeline_event_x(150, 9, 10, 75), 75, "event_x: one second late is one second left")
    near(pr.timeline_event_x(150, 12, 10, 0), 150, "event_x: a dead scale pins the icon to the playhead")
    eq(pr.timeline_event_x(150, nil, 10, 75), nil, "event_x: an unknown `at` places nothing")
    eq(pr.timeline_event_x(150, 10, nil, 75), nil, "event_x: an unknown `now` places nothing")

    -- The visible clock window: 2 s behind the playhead, 6 s ahead.
    local from_at, to_at = pr.timeline_window(10, 600, 75, 0.25)
    near(from_at, 8, "window: the left edge is the 2 s behind the playhead")
    near(to_at, 16, "window: the right edge is the six-second horizon")
    local dead_from, dead_to = pr.timeline_window(10, 600, 0, 0.25)
    near(dead_from, 10, "window: a dead scale collapses on `now` (left)")
    near(dead_to, 10, "window: a dead scale collapses on `now` (right)")
end

--=========================================================================================
-- 2) Horizon slicing
--=========================================================================================
do
    local b = build()
    local pr = b.pr
    local events = { { at = 7.9 }, { at = 8 }, { at = 10 }, { at = 13 }, { at = 16 }, { at = 16.1 } }

    local first, last = pr.timeline_slice(events, 6, 8, 16)
    eq(first, 2, "slice: the first event inside the window")
    eq(last, 5, "slice: the last event inside the window")
    local f2, l2 = pr.timeline_slice(events, 6, 9, 15)
    eq(f2, 3, "slice: a tighter window starts at the first covered event")
    eq(l2, 4, "slice: and ends at the last covered event")
    local f3, l3 = pr.timeline_slice(events, 6, 20, 30)
    eq(f3, nil, "slice: an empty window answers no first index")
    eq(l3, nil, "slice: an empty window answers no last index")
    eq(select(1, pr.timeline_slice(events, 0, 8, 16)), nil,
        "slice: a zero count reads nothing")
    eq(select(1, pr.timeline_slice(nil, 6, 8, 16)), nil, "slice: no array reads nothing")
    eq(select(1, pr.timeline_slice(events, 6, nil, 16)), nil,
        "slice: an unknown window bound reads nothing")
end

--=========================================================================================
-- 3) The neutral cadence schedule (provider absent)
--=========================================================================================
do
    local b = build()
    local pr = b.pr
    local rotation = {
        { action = "a", label = "A", spell_id = 101, live = true, engine = true },
        { action = "dead", label = "Dead", live = false, engine = true },
        { action = "noengine", label = "NoEngine", live = true, engine = false },
        { action = "b", label = "B", spell_id = 102, live = true, engine = true },
    }

    -- Two cues per 3.5 s cycle, spread evenly (1.75 s apart), anchored at 0.
    local out, count = pr.timeline_cadence(nil, rotation, 0, 0, 6, 1.5, 3.5)
    eq(count, 4, "cadence: four cues inside a six-second horizon")
    near(out[1].at, 0, "cadence: the first cue is at the anchor")
    near(out[2].at, 1.75, "cadence: the second cue is one cycle-step later")
    near(out[3].at, 3.5, "cadence: the third cue opens the next cycle")
    near(out[4].at, 5.25, "cadence: the fourth cue follows it")
    eq(out[1].key, "a", "cadence: the first cue is the first live+engine row")
    eq(out[2].key, "b", "cadence: dead rows are skipped (the next live+engine row)")
    eq(out[3].key, "a", "cadence: the walk continues past the skipped rows")
    eq(out[4].key, "b", "cadence: and keeps cycling the published order")
    eq(out[1].spell_id, 101, "cadence: the cue carries the row's spell id (art resolves later)")

    -- STABILITY: the same anchor gives the SAME absolute times as the clock moves,
    -- which is what makes the icons travel instead of standing still.
    local out2, count2 = pr.timeline_cadence(nil, rotation, 0, 5.2, 6, 1.5, 3.5)
    eq(count2, 4, "cadence: the later rebuild still fills the horizon")
    near(out2[1].at, 5.25, "cadence: the first future cue (past cues are dropped)")
    near(out2[2].at, 7, "cadence: the cycle that contains `now` keeps its times")
    local out3, count3 = pr.timeline_cadence(nil, rotation, 0, 5.2, 6, 1.5, 3.5)
    eq(count3, count2, "cadence: a rebuild at the same clock is identical")
    near(out3[1].at, out2[1].at, "cadence: and lands the same absolute time")

    -- Empty / missing rotation tables answer nothing (never a guessed cue).
    eq(select(2, pr.timeline_cadence(nil, {}, 0, 0, 6, 1.5, 3.5)), 0,
        "cadence: an empty rotation previews nothing")
    eq(select(2, pr.timeline_cadence(nil, nil, 0, 0, 6, 1.5, 3.5)), 0,
        "cadence: a missing rotation previews nothing")
    eq(select(2, pr.timeline_cadence(nil, { { action = "x", live = false } }, 0, 0, 6, 1.5, 3.5)), 0,
        "cadence: a rotation with no live+engine row previews nothing")

    -- The class's own cadence constants are honoured (a 1 s GCD inside a 6 s cycle
    -- is six cues one second apart).
    local out4, count4 = pr.timeline_cadence(nil, rotation, 0, 0, 6, 1, 6)
    eq(count4, 7, "cadence: a 1 s GCD in a 6 s cycle places seven cues (the horizon edge is inclusive)")
    near(out4[2].at, 1, "cadence: one second apart")
    near(out4[6].at, 5, "cadence: the sixth lands at 5 s")
    near(out4[7].at, 6, "cadence: the last sits exactly on the right edge")

    -- A horizon shorter than the first step still shows the anchor cue.
    local _, count5 = pr.timeline_cadence(nil, rotation, 0, 0, 0.5, 1.5, 3.5)
    eq(count5, 1, "cadence: a sub-step horizon still shows the cue at the anchor")

    -- Reusing the out table: the same slots are written, never re-allocated.
    local reused = {}
    local slot_before
    pr.timeline_cadence(reused, rotation, 0, 0, 6, 1.5, 3.5)
    slot_before = reused[1]
    pr.timeline_cadence(reused, rotation, 0, 0, 6, 1.5, 3.5)
    check(reused[1] == slot_before, "cadence: a rebuild reuses the caller's slot table")
end

--=========================================================================================
-- 4) The strip's schedule: provider present / absent / empty / absent class
--=========================================================================================
local function make_strip(panel, class_key)
    local b = build()
    local ui, ST = b.ui, b.ST
    ST.active_class = class_key or "HUNTER"
    ST[ST.active_class] = { practice_panel = panel }
    ui.panel = make_frame()
    ui.build_playhead(ST)
    ui.active = true
    -- These fixtures model a RUNNING session (the movement/emphasis maths); a real
    -- session opens stopped until Start Fight (practice_ui_state pins that).
    ui.playhead_running = true
    return b, ui, ST
end

do
    -- Provider absent: the class publishes a rotation table -> the neutral preview.
    local b, ui, ST = make_strip(nil, "HUNTER")
    ST.HUNTER.practice_rotation = {
        { action = "steady", label = "Steady Shot", spell_id = 49001, live = true, engine = true },
        { action = "multi", label = "Multi-Shot", spell_id = 2643, live = true, engine = true },
    }
    ST.HUNTER.PRACTICE_GCD_SECONDS = 1.5
    ST.HUNTER.PRACTICE_CYCLE_SECONDS = 3.5
    ui.playhead_show(ST, 0)
    eq(ui.timeline_sched_source, "cadence", "no provider: the cadence preview drives the strip")
    eq(ui.playhead_frame.title.text, "Rotation cadence (preview)",
        "no provider: the strip is labelled as a preview")
    eq(ui.playhead_frame.shown, true, "no provider: the strip still shows")
    check((ui.timeline_sched_count or 0) >= 3, "no provider: the preview fills the horizon")
    eq(ui.timeline_sched[1].spell_id, 49001, "no provider: the cue carries the row's own spell id")

    -- The strip's icons MOVE with the clock (same events, smaller x as time passes).
    ui.playhead_draw(0)
    local x_at_zero = ui.playhead_icons[1].point[4]
    ui.playhead_draw(1)
    local x_at_one = ui.playhead_icons[1].point[4]
    near(x_at_zero - x_at_one, 45, "the cue travels 45 px left per second (600 px, 10 s horizon)")
    near(x_at_zero, 150 - 12, "the first cue starts on the playhead (icon centred on it)")

    -- A cue that has JUST crossed the playhead stays on the strip while it is still
    -- inside it (the press feedback), and only leaves the pool when it scrolls off.
    ui.playhead_draw(2)
    eq(ui.playhead_icons_used, 6, "every cue inside the strip is drawn, the crossed one included")
    eq(ui.playhead_icons[1]:IsShown(), true, "the crossed cue's icon is still on screen")
    near(ui.playhead_icons[1].point[4], 48,
        "the crossed cue sits two seconds (90 px) left of the playhead, still on the strip")

    -- Off: a stopped session never rebuilds its schedule and never draws.
    ui.active = false
    ui.playhead_refresh(ST, 2, true)
    eq(ui.timeline_sched_source, "cadence", "off: the schedule is not rebuilt")
    local x_before = ui.playhead_icons[1].point[4]
    ui.playhead_draw(3)
    near(ui.playhead_icons[1].point[4], x_before, "off: a draw with no session moves nothing")
    ui.active = true

    -- combat pause freezes the strip in place.
    ui.combat_paused = true
    ui.playhead_draw(4)
    near(ui.playhead_icons[1].point[4], x_before, "paused: the strip freezes with the drill")
    ui.combat_paused = false

    -- Pool reuse: drawing again creates no frame and keeps the same icon table.
    local created = b.sb.created
    local first_icon = ui.playhead_icons[1]
    ui.playhead_draw(1)
    eq(b.sb.created, created, "pool: a second draw creates no frame")
    check(ui.playhead_icons[1] == first_icon, "pool: the same icon slot is reused")

    -- Session stop clears: every icon hidden, the count zeroed, the frame hidden.
    ui.playhead_frame:Hide()
    ui.playhead_clear()
    eq(ui.timeline_sched_count, 0, "stop: the schedule count is cleared")
    eq(ui.playhead_icons_used, 0, "stop: no icon counts as used")
    local any_shown = false
    for i = 1, #ui.playhead_icons do
        if ui.playhead_icons[i]:IsShown() then
            any_shown = true
        end
    end
    eq(any_shown, false, "stop: every pooled icon is hidden")
end

do
    -- Provider present: its events drive the strip, ascending, future-only.
    local reads = 0
    local panel = {
        updcoming = true,
        upcoming = function(_ui, now, horizon)
            reads = reads + 1
            return {
                { at = now - 1, key = "past", label = "Past" },      -- dropped
                { at = now + 0.5, key = "cs", label = "Crusader Strike", spell_id = 35395 },
                { at = now + 2, key = "judge", label = "Judgement", texture = "icon_judge" },
                { at = now + 30, key = "late", label = "Late" },     -- outside the horizon
            }
        end,
        timeline_title = "Hunter cues",
        timeline_lanes = { { key = "cast", name = "Cast" } },
    }
    local _, ui, ST = make_strip(panel, "HUNTER")
    ui.playhead_show(ST, 10)
    eq(reads, 1, "provider: the strip asks the class once per rebuild")
    eq(ui.timeline_sched_source, "upcoming", "provider: the class's own cues drive the strip")
    eq(ui.playhead_frame.title.text, "Hunter cues", "provider: the class's title is used")
    eq(ui.timeline_sched_count, 2, "provider: past cues and cues past the horizon are dropped")
    near(ui.timeline_sched[1].at, 10.5, "provider: the first future cue survives in order")
    eq(ui.timeline_sched[2].texture, "icon_judge", "provider: an explicit texture is kept")
    eq(ui.timeline_sched[1].spell_id, 35395, "provider: a spell id rides along for the art")

    -- The PRESS cue: the action whose second has arrived is lit; the rest sit back.
    eq(ui.playhead_icons[1].alpha, 0.7, "emphasis: a queued cue sits back")
    ui.playhead_draw(10.5)
    eq(ui.playhead_icons[1].alpha, 1, "emphasis: the cue lights when its second arrives")
    eq(ui.playhead_icons[1].border.color[1], 1, "emphasis: and its border turns gold")
    ui.playhead_draw(10.5 + 1.0)
    eq(ui.playhead_icons[1].alpha, 0.7, "emphasis: the cue dims again once the press window passes")

    -- An EMPTY answer is authoritative: no icons, no cadence fallback.
    panel.upcoming = function() return {} end
    ST.HUNTER.practice_rotation = {
        { action = "steady", label = "Steady Shot", live = true, engine = true },
    }
    ui.playhead_refresh(ST, 11, true)
    eq(ui.timeline_sched_source, "upcoming", "empty provider: still the provider source")
    eq(ui.timeline_sched_count, 0, "empty provider: nothing is cued")
    eq(ui.playhead_frame.title.text, "Hunter cues", "empty provider: the title does not flip to preview")

    -- A THROWING provider falls back to the cadence preview (never a blank strip).
    panel.upcoming = function() error("provider probe") end
    ui.playhead_refresh(ST, 12, true)
    eq(ui.timeline_sched_source, "cadence", "throwing provider: the preview carries the strip")
    check((ui.timeline_sched_count or 0) > 0, "throwing provider: the preview still cues")

    -- Default title when the class publishes none.
    panel.upcoming = function()
        reads = reads + 1
        return { { at = 13, key = "cs", label = "CS" } }
    end
    panel.timeline_title = nil
    ui.playhead_refresh(ST, 12.5, true)
    eq(ui.playhead_frame.title.text, "Upcoming actions", "no class title: the generic label")

    -- Off: a stopped session never reads the provider, even with the strip still on
    -- screen (the gates are independent).
    ui.active = false
    local reads_off = reads
    ui.playhead_refresh(ST, 99, true)
    eq(reads, reads_off, "off: a stopped session never reads the provider")
    ui.active = true
end

do
    -- The class table is absent: no provider, no rotation -> nothing to show.
    local b = build()
    local ui, ST = b.ui, b.ST
    ST.active_class = "MAGE" -- no ST.MAGE module in this sandbox
    ui.panel = make_frame()
    ui.build_playhead(ST)
    ui.active = true
    eq(ui.playhead_available(), false, "no class table: no timeline is available")
    eq(ui.playhead_show(ST, 0), false, "no class table: the strip refuses to show")
    eq(ui.playhead_frame.shown, false, "no class table: the frame stays hidden")
    ui.playhead_refresh(ST, 0, true)
    eq(ui.timeline_sched_count, nil, "no class table: no schedule is built at all")
    eq(ui.timeline_sched_source, nil, "no class table: no cue source is recorded")
end

do
    -- Lane rows: a class that publishes lanes gets one row per lane.
    local panel = {
        upcoming = function(_ui, now)
            return {
                { at = now + 1, key = "a", label = "A", lane = "one" },
                { at = now + 2, key = "b", label = "B", lane = "two" },
            }
        end,
        timeline_lanes = { { key = "one", name = "One" }, { key = "two", name = "Two" } },
    }
    local _, ui, ST = make_strip(panel, "HUNTER")
    -- The reference layout: 56 px ruler band + one 30 px lane per lane + 14 px chrome.
    eq(ui.playhead_frame.height, 56 + 2 * 30 + 14, "lanes: the strip grows one row per lane")
    ui.playhead_show(ST, 0)
    eq(ui.playhead_icons[1].point[5], 0, "lanes: the first lane sits on the top row")
    eq(ui.playhead_icons[2].point[5], -30, "lanes: the second lane sits one 30 px row down")

end

do
    -- Scale (operator reference 2026-10-26: the timeline is a full-width band). The
    -- track is the screen width minus the frame margins and the frame's own rail,
    -- clamped to the 600 px fallback and a 2000 px ceiling. Pure maths, pinned here.
    local b = build()
    local ui = b.ui
    eq(ui.timeline_track_width(110, 600, 1920), 1778,
        "scale: a 1920 px screen gives the strip a 1778 px track")
    eq(ui.timeline_track_width(60, 600, 1920), 1828,
        "scale: the log's narrower rail gets a wider track")
    eq(ui.timeline_track_width(110, 600, 0), 600,
        "scale: a zero screen width falls back to the archive track")
    eq(ui.timeline_track_width(110, 600, nil), 600,
        "scale: an unsized sandbox screen falls back (UIParent reports no width)")
    eq(ui.timeline_track_width(110, 600, 800), 658,
        "scale: a small screen shrinks the track")
    eq(ui.timeline_track_width(110, 600, 700), 600,
        "scale: the 600 px minimum wins on a tiny screen")
    eq(ui.timeline_track_width(110, 600, 3000), 2000,
        "scale: a huge screen caps the track at 2000 px")
end

do
    -- A sized client builds BOTH frames full width: the strip (screen minus rail and
    -- margins) and the log (screen minus its own rail), with the ruler's second tick
    -- running down the lanes like the reference's gridlines.
    local b = build()
    local ui, ST = b.ui, b.ST
    b.env.UIParent:SetSize(1920, 1080)
    ST.active_class = "PALADIN"
    ST.PALADIN = {
        practice_rotation = { { action = "cs", label = "Crusader Strike", live = true, engine = true } },
    }
    ui.panel = make_frame()
    ui.build_timeline(ST)
    eq(ui.timeline_width, 1828, "scale: the log's track is the screen width")
    eq(ui.timeline_frame.width, 1828 + 60 + 16, "scale: the log frame spans the screen")
    ui.build_playhead(ST)
    eq(ui.playhead_track_width, 1778, "scale: the built strip's track is the screen width")
    eq(ui.playhead_frame.width, 110 + 1778 + 12, "scale: the strip frame spans the screen")
    eq(ui.playhead_frame.height, 56 + 6 * 30 + 14,
        "scale: six 30 px lanes under a 56 px ruler")
    ui.active = true
    ui.playhead_running = true
    ui.playhead_origin = 0
    ui.playhead_show(ST, 0)
    eq(ui.playhead_ruler_pool[1].tick.height, 6 * 30,
        "scale: the second tick is a full-height gridline")
    eq(ui.playhead_ruler_pool[1].tick.point[1], "TOPLEFT",
        "scale: the gridline hangs down the lanes from the track top")
end

do
    -- The reference layout (operator screenshot 2026-10-26): the strip wears the
    -- archive timeline's chrome - a left rail with one icon + name per lane, a ruler
    -- with m:ss labels, alternating lane strips and a close X - while the cues still
    -- travel toward the fixed playhead.
    local b = build()
    local ui, ST, sb = b.ui, b.ST, b.sb
    ST.active_class = "PALADIN"
    ST.PALADIN = {
        practice_rotation = {
            { action = "cs", label = "Crusader Strike", live = true, engine = true },
            { action = "judge", label = "Judgement", spell_id = 20271, live = true, engine = true },
            { action = "consec", label = "Consecration", spell_id = 26573, live = true, engine = true },
        },
    }
    ui.panel = make_frame()
    ui.build_playhead(ST)
    ui.active = true
    ui.playhead_running = true

    -- The paladin's six sim lanes are the reference's rail (SoB / Melee / CS / ...).
    eq(ui.playhead_row_count, 6, "layout: the paladin strip has the sim's six lanes")
    eq(#ui.playhead_frame.lane_labels, 6, "layout: one rail entry per lane")
    eq(ui.playhead_frame.lane_labels[1].label.text, "SoB", "layout: the first lane names SoB")
    eq(ui.playhead_frame.lane_labels[2].label.text, "Melee", "layout: the second names Melee")
    eq(ui.playhead_frame.lane_labels[6].label.text, "Judge", "layout: the last names Judge")
    eq(ui.playhead_frame.lane_labels[1].icon.texture, "icon_spell_31892",
        "layout: the rail icon is the lane spell's art")

    -- Alternating lane strips: one per lane, the reference's chunky row height.
    eq(#ui.playhead_frame.lane_bgs, 6, "layout: a backdrop strip per lane")
    eq(ui.playhead_frame.lane_bgs[1].height, 30, "layout: lane rows are 30 px")

    -- Ruler: the session clock rides the cues; 0:00 sits on the playhead at the start.
    ui.playhead_origin = 0
    eq(ui.playhead_show(ST, 0), true, "layout: the strip shows for the session")
    check((ui.playhead_ruler_used or 0) >= 6, "layout: the ruler fills the visible window")
    eq(ui.playhead_icons[1].step_key, "cs",
        "layout: a cue with no id of its own uses the practice step art")
    eq(ui.playhead_icons[1].texture.texture, "icon_spell_35395",
        "layout: the CS cue shows the panel's Crusader Strike art")
    local function playhead_tick_text()
        local px = b.pr.timeline_playhead_x(600, b.pr.TL_PLAYHEAD_FRACTION)
        for i = 1, (ui.playhead_ruler_used or 0) do
            local entry = ui.playhead_ruler_pool[i]
            if entry and entry.x and math.abs(entry.x - px) < 0.01 then
                return entry.label.text
            end
        end
        return nil
    end
    eq(playhead_tick_text(), "0:00", "layout: the playhead's tick reads 0:00 at the start")
    ui.playhead_draw(1)
    eq(playhead_tick_text(), "0:01", "layout: the ruler scrolls under the fixed playhead")
    -- The cues land on their own lanes (the same lane map the recorded log uses).
    local lanes_used = {}
    for i = 1, (ui.playhead_icons_used or 0) do
        lanes_used[ui.playhead_icons[i].point[5]] = true
    end
    eq(lanes_used[-60], true, "layout: a CS cue sits on the third lane row (2 * 30 px)")

    -- Rotation band: the reference's top-centre route label + sequence icons.
    ui.current_display_rotation = "1/2"
    ui.playhead_draw(0)
    eq(ui.playhead_frame.band_label.text, b.st.nextaction.display_names["1/2"],
        "layout: the band names the resolved rotation")
    eq(ui.playhead_frame.band_icons[1].shown, true,
        "layout: the band paints the rotation's first step")

    -- The close X hides the strip; a later session show brings it back.
    local close
    for i = 1, #sb.frames do
        local f = sb.frames[i]
        if f.kind == "Button" and f.parent == ui.playhead_frame then
            close = f
            break
        end
    end
    check(close ~= nil, "layout: the strip owns a close button")
    eq(close.label.text, "X", "layout: the close button reads X")
    close.scripts.OnClick(close)
    eq(ui.playhead_frame.shown, false, "layout: the close button hides the strip")
    eq(ui.playhead_show(ST, 1), true, "layout: a later session show brings it back")
    eq(ui.playhead_frame.shown, true, "layout: the strip is visible again")

    -- The twist cue dresses as the practice display's split Command/Blood icon.
    ui.playhead_dress(ui.playhead_icons[1], { key = "twist", label = "Twist" })
    eq(ui.playhead_icons[1].twist_left.hidden, false, "layout: the twist cue shows its left half")
    eq(ui.playhead_icons[1].twist_right.hidden, false, "layout: the twist cue shows its right half")
    eq(ui.playhead_icons[1].twist_left.texture, "icon_spell_20375",
        "layout: the twist's left half is the Command seal art")
    eq(ui.playhead_icons[1].twist_right.texture, "icon_spell_31892",
        "layout: the twist's right half is the Blood seal art")
end

--=========================================================================================
-- 5) The strip's OnUpdate: one hook, only while the strip is shown
--=========================================================================================
do
    local _, ui, ST = make_strip({
        upcoming = function(_ui, now) return { { at = now + 1, key = "cs", label = "CS" } } end,
    }, "HUNTER")
    local on_update = ui.playhead_frame:GetScript("OnUpdate")
    check(type(on_update) == "function", "the strip owns exactly one OnUpdate hook")
    eq(ui.playhead_frame.shown, false, "the strip starts hidden until a session shows it")

    -- Shown and running: the hook redraws from the schedule.
    ui.playhead_show(ST, 0)
    eq(ui.playhead_frame.shown, true, "a session shows the strip")
    local x_before = ui.playhead_icons[1].point[4]
    on_update(ui.playhead_frame, 0.05)
    near(ui.playhead_icons[1].point[4], x_before, "the hook draws at the same clock")

    -- Hidden (stop, or History open): the client stops calling OnUpdate, and a
    -- direct call is inert too - the strip never draws while it is not on screen.
    ui.playhead_frame:Hide()
    ui.playhead_draw(5)
    near(ui.playhead_icons[1].point[4], x_before, "a hidden strip does not move")
end

--=========================================================================================
-- 7) Every class gets both frames: a drill class previews its OWN published order
--    (never the paladin sim's rows, and never a rotation row the panel cannot press)
--=========================================================================================
do
    local b = build()
    local ui, ST = b.ui, b.ST
    ST.active_class = "MAGE"
    ST.MAGE = {
        practice_panel = {
            drill_key = "mage_drill",
            scenario_key = function() return "mage_drill" end,
            order = function() return { "fireball", "frostbolt" } end,
            label = function(key)
                return key == "fireball" and "Fireball" or "Frostbolt"
            end,
            spell_id = function(key)
                return key == "fireball" and 133 or 116
            end,
        },
        -- The class's APL rotation also carries a row its drill panel cannot press:
        -- a cue for it could never become the graded attempt.
        practice_rotation = {
            { action = "fireball", label = "Fireball", live = true, engine = true },
            { action = "combustion", label = "Combustion", live = true, engine = true },
        },
    }
    ui.panel = make_frame()
    ui.build_playhead(ST)
    ui.active = true
    eq(ui.playhead_available(), true, "class order: a drill class still gets the timeline")
    eq(ui.playhead_show(ST, 0), true, "class order: the strip shows for that class")
    check((ui.timeline_sched_count or 0) > 0, "class order: its own order schedules cues")
    eq(ui.timeline_sched[1].spell_id, 133, "class order: the cue carries the class's own spell id")
    eq(ui.timeline_sched[1].label, "Fireball", "class order: and its own label")
    local unpressed
    for i = 1, (ui.timeline_sched_count or 0) do
        local key = ui.timeline_sched[i].key
        if key ~= "fireball" and key ~= "frostbolt" then
            unpressed = key
        end
    end
    eq(unpressed, nil, "class order: a cue the drill cannot press is never scheduled")
end

--=========================================================================================
-- 8) A route that opens the strip without stating a run state opens it STOPPED
--    (operator rule 2026-10-26: the top strip moves ONLY while a fight runs)
--=========================================================================================
do
    local b = build()
    local ui, ST = b.ui, b.ST
    ST.active_class = "HUNTER"
    ST.HUNTER = { practice_panel = {
        upcoming = function(_ui, now)
            return { { at = now + 1, key = "cs", label = "CS" } }
        end,
    } }
    ui.panel = make_frame()
    ui.build_playhead(ST)
    ui.active = true
    eq(ui.playhead_show(ST, 5), true, "no run state: the strip still opens")
    eq(ui.playhead_frozen_at, 5, "no run state: it opens frozen at that second")
    eq(ui.playhead_running, nil, "no run state: no fight is claimed")
    local x = ui.playhead_icons[1].point[4]
    ui.playhead_draw(9)
    near(ui.playhead_icons[1].point[4], x, "no run state: the cues do not move")
end

--=========================================================================================
-- 9) The sim strip previews the class's FAMILY-GATED rotation slice when it
--    publishes one (a row another family's APL plays is never a cue here)
--=========================================================================================
do
    local b = build()
    local ui, ST = b.ui, b.ST
    ST.active_class = "PALADIN"
    ST.PALADIN = {
        practice_rotation = {
            { action = "how_wrath", label = "Hammer of Wrath", live = true, engine = true },
            { action = "judge", label = "Judgement", live = true, engine = true },
        },
        practice_rotation_for = function()
            return {
                { action = "judge", label = "Judgement", live = true, engine = true },
            }
        end,
    }
    ui.panel = make_frame()
    ui.build_playhead(ST)
    ui.active = true
    ui.playhead_running = true
    eq(ui.playhead_show(ST, 0), true, "rotation slice: the strip opens")
    eq(ui.timeline_sched[1].key, "judge",
        "rotation slice: the family-gated row drives the strip")
    local foreign
    for i = 1, (ui.timeline_sched_count or 0) do
        if ui.timeline_sched[i].key ~= "judge" then
            foreign = ui.timeline_sched[i].key
        end
    end
    eq(foreign, nil, "rotation slice: another family's row is never a cue")
    -- A throwing slice falls back to the full table (never a blank strip).
    ST.PALADIN.practice_rotation_for = function() error("slice probe") end
    ui.playhead_refresh(ST, 0, true)
    check((ui.timeline_sched_count or 0) > 0,
        "rotation slice: a throwing slice falls back to the full table")
    eq(ui.timeline_sched_source, "cadence", "rotation slice: still the cadence preview")
end

if failures == 0 then
    print("PASS  practice_timeline_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  practice_timeline_state.lua: " .. tostring(failures) .. " of "
        .. tostring(checks) .. " checks failed")
    os.exit(1)
end

