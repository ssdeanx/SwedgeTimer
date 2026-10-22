-- tests/practice_progress_ui_state.lua: offline execution tests for the practice
-- progress UI (practice_progress_ui.lua) - the Progress options page's read model and
-- the practice stats frame (sparkline + tables + history).
--
-- Sandbox discipline: the three modules the lane owns / reads are loaded into a fresh
-- namespace under setfenv, over frame stubs that record what the UI draws. The real
-- practice_stats.lua and practice_progress.lua are loaded so the read model is the one
-- the pure modules actually produce - the suite never re-implements their maths.
--
-- Covered here:
--   * the load surface (no frame is created at file load - no default-visible change);
--   * the read model with NO data (a missing practice key, a missing half, a corrupt
--     blob, a wrong-typed blob): the page renders "no data" and never raises;
--   * the read model WITH data: the level, the XP, the per-drill mastery rows, the
--     achievements and the stats summary come from the pure modules' read model;
--   * the renderers (level line, XP bar, mastery table, achievements, stats summary)
--     and their empty-state behaviour;
--   * the stats frame: it is built on the first open, hidden otherwise, draws one
--     sparkline bar per session, fills the per-drill / per-class / history tables and
--     survives an empty history;
--   * the reset: the first call arms it, the second performs it, the cancel disarms
--     it, and the reset replaces only the practice key.
--
-- Run from the repo root: lua5.1 tests/practice_progress_ui_state.lua  (any cwd works).

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
local function contains(haystack, needle, label)
    checks = checks + 1
    if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
        failures = failures + 1
        print("FAIL  " .. label .. "  (missing '" .. tostring(needle) .. "' in '"
            .. tostring(haystack) .. "')")
    end
end

--=========================================================================================
-- Frame stubs (record what the stats frame draws)
--=========================================================================================
local function make_texture()
    local t = { hidden = false }
    function t:SetAllPoints() end
    function t:SetPoint() end
    function t:SetSize(w, h) t.width, t.height = w, h end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetTexCoord() end
    function t:SetTexture(texture) t.texture = texture end
    function t:SetColorTexture(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetVertexColor(r, g, b, a) t.vertex_color = { r, g, b, a } end
    function t:ClearAllPoints() t.cleared = true end
    function t:SetDrawLayer() end
    function t:SetAlpha(alpha) t.alpha = alpha end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:ClearAllPoints() f.point_cleared = true end
    function f:SetFontObject(obj) f.font_object = obj end
    -- SoD-faithful: a FontString without a font throws on SetText. Every label the
    -- module draws must set its font first.
    function f:SetFont(path, size, flags)
        if path == nil then return false end
        f.font = { path, size, flags }
        return true
    end
    function f:GetFont() return f.font and f.font[1] or nil end
    function f:SetText(text)
        if f.font == nil and f.font_object == nil then
            error("Font not set", 2)
        end
        f.text = text
    end
    function f:GetText() return f.text end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:SetShadowColor(r, g, b, a) f.shadow_color = { r, g, b, a } end
    function f:SetShadowOffset(x, y) f.shadow_offset = { x, y } end
    function f:SetWidth(w) f.width = w end
    function f:SetWordWrap(wrap) f.word_wrap = wrap end
    function f:SetJustifyH(justify) f.justify = justify end
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
    function f:EnableMouseWheel(enabled) f.mouse_wheel = enabled end
    function f:RegisterForDrag(button) f.drag_buttons = button end
    function f:GetName() return f.key_name end
    function f:SetParent(parent) f.parent = parent end
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
    function f:CreateTexture() return make_texture() end
    function f:CreateFontString() return make_fontstring() end
    function f:SetBackdrop(backdrop) f.backdrop = backdrop end
    function f:SetBackdropColor(r, g, b, a) f.backdrop_color = { r, g, b, a } end
    function f:SetBackdropBorderColor(r, g, b, a) f.backdrop_border_color = { r, g, b, a } end
    function f:SetAllPoints() end
    -- ScrollFrame surface.
    function f:SetScrollChild(child) f.scroll_child = child end
    function f:GetScrollChild() return f.scroll_child end
    function f:SetVerticalScroll(offset) f.vertical_scroll = offset end
    function f:GetVerticalScroll() return f.vertical_scroll or 0 end
    function f:GetVerticalScrollRange() return f.vertical_range or 0 end
    return f
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
--
-- opts.blob:     the raw value of db.profile.practice (nil = the key is absent).
-- opts.no_modules: the pure modules are not loaded (a client without them).
-- opts.no_profile: ST has no get_profile_table at all.
local function build(opts)
    opts = opts or {}

    local sb = { frames = {}, created_frames = 0, prints = {}, notified = 0, clock = 0 }

    local profile = {}
    if opts.blob ~= nil then
        profile.practice = opts.blob
    end

    local ST = { player_class = "PALADIN", player_class_pretty = "Paladin" }
    function ST:get_profile_table() return profile end
    sb.profile = profile

    local env = setmetatable({}, { __index = _G })
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg)
        sb.prints[#sb.prints + 1] = tostring(msg)
    end }
    env.GameFontNormal = "GameFontNormal"
    env.GameFontHighlightSmall = "GameFontHighlightSmall"
    env.UIParent = make_frame()
    env.CreateFrame = function(kind, name, parent, template)
        sb.created_frames = sb.created_frames + 1
        local f = make_frame()
        f.kind, f.name, f.parent, f.template = kind, name, parent, template
        sb.frames[#sb.frames + 1] = f
        return f
    end
    env.InCombatLockdown = function() return false end
    env.LibStub = function(major)
        if major == "AceConfigRegistry-3.0" then
            return { NotifyChange = function() sb.notified = sb.notified + 1 end }
        end
        return {}
    end

    local st = {}

    -- The addon's aligned clock (the GetTime() domain). The reset's arm window is
    -- measured against it, so the sandbox advances it to expire an arm.
    st.api = {
        get_time = function() return sb.clock end,
    }

    -- The practice scenario catalogue (the drill display names). The real registry
    -- lives in practice.lua; this fixture mirrors its keys and titles, and the source
    -- pin below keeps the fixture from drifting away from the shipped registry.
    st.practice = {
        harness = {
            SCENARIOS = {
                paladin_twist = { key = "paladin_twist", title = "Twist practice" },
                hunter_forced_move = { key = "hunter_forced_move", title = "Forced-move drill" },
                rogue_energy_pool = { key = "rogue_energy_pool", title = "Energy-pooling drill" },
            },
        },
    }

    local utils = assert(loadfile(ROOT .. "utils.lua"))
    setfenv(utils, env)
    utils("SwedgeTimer", st)

    if not opts.no_modules then
        local stats = assert(loadfile(ROOT .. "practice_stats.lua"))
        setfenv(stats, env)
        stats("SwedgeTimer", st)

        local progress = assert(loadfile(ROOT .. "practice_progress.lua"))
        setfenv(progress, env)
        progress("SwedgeTimer", st)
    end

    local ui = assert(loadfile(ROOT .. "practice_progress_ui.lua"))
    setfenv(ui, env)
    local ok, err = pcall(ui, "SwedgeTimer", st)
    if not ok then
        print("FAIL  practice_progress_ui.lua does not load under the sandbox: " .. tostring(err))
        os.exit(1)
    end

    sb.env, sb.st = env, st
    return { env = env, st = st, ST = ST, sb = sb, ui = st.practice_progress_ui }
end

-- A saved profile with real content: one class with XP, drills, a session history and
-- two unlocked achievements. Built through the pure modules so the saved blob is the
-- shape the hook lane writes.
local function make_blob()
    local st = {}
    -- The pure modules are loaded into a bare namespace (no WoW API needed).
    local env = setmetatable({}, { __index = _G })
    local stats = assert(loadfile(ROOT .. "practice_stats.lua"))
    setfenv(stats, env)
    stats("SwedgeTimer", st)
    local progress = assert(loadfile(ROOT .. "practice_progress.lua"))
    setfenv(progress, env)
    progress("SwedgeTimer", st)
    local progress_state = st.practice_progress.new_state()
    local stats_state = st.practice_stats.new_state()

    local P = st.practice_progress
    local S = st.practice_stats

    -- Session one: 30 S-grade attempts on one drill and 10 misses on another.
    local session = P.new_session()
    for _ = 1, 30 do
        P.record_attempt(progress_state, session, "PALADIN", "paladin_twist", "S", 20000)
        S.record_attempt(stats_state, "PALADIN", "S", "paladin_twist")
    end
    for _ = 1, 10 do
        P.record_attempt(progress_state, session, "PALADIN", "hunter_forced_move", "F", 20000)
        S.record_attempt(stats_state, "PALADIN", "F", "hunter_forced_move")
    end
    P.end_session(progress_state, session, "PALADIN", 20000)
    S.record_session(stats_state, "PALADIN", { attempts = 40, hits = 30, score = 75,
        best_grade = "S" }, 120, 20000)

    -- Session two (the next calendar day): 12 more hits on the twist drill. Two
    -- sessions, so the history's newest-first order is pinned.
    local second = P.new_session()
    for _ = 1, 12 do
        P.record_attempt(progress_state, second, "PALADIN", "paladin_twist", "S", 20001)
        S.record_attempt(stats_state, "PALADIN", "S", "paladin_twist")
    end
    P.end_session(progress_state, second, "PALADIN", 20001)
    S.record_session(stats_state, "PALADIN", { attempts = 12, hits = 12, score = 90,
        best_grade = "S" }, 45, 20001)

    -- A second class with a smaller amount of data.
    local other = P.new_session()
    for _ = 1, 5 do
        P.record_attempt(progress_state, other, "ROGUE", "rogue_energy_pool", "A", 20000)
        S.record_attempt(stats_state, "ROGUE", "A", "rogue_energy_pool")
    end
    P.end_session(progress_state, other, "ROGUE", 20000)
    S.record_session(stats_state, "ROGUE", { attempts = 5, hits = 5, score = 80,
        best_grade = "A" }, 30, 20000)

    -- Two unlocked achievements in the PALADIN scope.
    progress_state.classes.PALADIN.unlocks.first_s = true
    progress_state.classes.PALADIN.unlocks.hundred_attempts = true

    return {
        schema_version = 1,
        progress = progress_state,
        stats = stats_state,
    }
end

--=========================================================================================
-- 1) Load surface: the module exposes its documented entry points and creates nothing
--=========================================================================================
local base = build({ blob = make_blob() })
local ui = base.ui
local sb = base.sb

-- The drill-name fixture must not drift away from the shipped scenario registry: the
-- real titles live in practice.lua, and the fixture above mirrors them.
do
    local f = io.open(ROOT .. "practice.lua", "r")
    local source = (f and f:read("*a") or ""):gsub("\r\n", "\n")
    if f then f:close() end
    for _, spec in ipairs({
        { key = "paladin_twist", title = "Twist practice" },
        { key = "hunter_forced_move", title = "Forced-move drill" },
        { key = "rogue_energy_pool", title = "Energy-pooling drill" },
    }) do
        check(source:find('key = "' .. spec.key .. '"', 1, true) ~= nil,
            "practice.lua registers the scenario " .. spec.key)
        check(source:find('title = "' .. spec.title .. '"', 1, true) ~= nil,
            "practice.lua titles the scenario " .. spec.key)
    end
end

check(type(ui) == "table", "practice_progress_ui.lua defines st.practice_progress_ui")
eq(sb.created_frames, 0, "no frame is created at file load (no default-visible change)")
eq(ui.frame, nil, "the stats frame does not exist at file load")
eq(ui.is_open(base.ST), false, "the stats frame is not open at file load")

local ENTRY_POINTS = {
    "read_blob", "live_data", "resolve_class_key", "current_class_key", "pretty_class",
    "drill_name", "class_keys_with_data", "scope_model", "current_model", "account_model",
    "class_model_rows", "format_duration", "format_day",
    "render_level", "render_xp_bar", "render_mastery", "render_achievements",
    "render_stats", "render_page",
    "reset_armed", "request_reset", "disarm_reset", "perform_reset",
    "reset_arm_expired", "now",
    "notify_options_refresh",
    "build_frame", "refresh_frame", "open_frame", "close_frame", "toggle_frame",
    "is_open", "frame_scope", "frame_scopes", "cycle_scope", "scope_label",
    "render_sparkline", "render_history_rows", "scroll_history", "spark_bar",
}
for i = 1, #ENTRY_POINTS do
    check(type(ui[ENTRY_POINTS[i]]) == "function",
        "practice_progress_ui.lua exposes " .. ENTRY_POINTS[i])
end

--=========================================================================================
-- 2) The read model with NO data: nil-safe, never an error
--=========================================================================================
do
    local b = build({})
    local m = b.ui
    local model = m.current_model(b.ST)
    check(type(model) == "table", "no practice key: the read model is still a table")
    eq(model.has_data, false, "no practice key: the scope reads as empty")
    eq(model.level, 1, "no practice key: the level is the starting level")
    eq(#model.drills, 0, "no practice key: no drill rows")
    eq(#model.history, 0, "no practice key: no history")
    eq(model.stats.runs, 0, "no practice key: no runs")
    eq(m.render_level(model), m.NO_DATA_TEXT, "no practice key: the level line reads 'no data'")
    eq(m.render_stats(model), m.NO_DATA_TEXT, "no practice key: the stats line reads 'no data'")
    eq(m.render_xp_bar(model), "", "no practice key: the XP bar is empty")
    eq(m.render_mastery(model), "No drills practised yet.", "no practice key: no drills message")
    contains(m.render_achievements(model), "0 of 7 unlocked",
        "no practice key: the achievements list is still shown (the registry is static)")
    check(type(m.render_page(model)) == "string", "no practice key: the page renders a string")
end

-- A corrupt blob (the wrong type) and a blob with a corrupt half.
do
    local b = build({ blob = "not a table" })
    local model = b.ui.current_model(b.ST)
    eq(model.has_data, false, "a non-table practice blob reads as empty")
    eq(b.ui.render_stats(model), b.ui.NO_DATA_TEXT, "a non-table practice blob renders 'no data'")

    local b2 = build({ blob = { schema_version = 1, progress = 5, stats = "x" } })
    local model2 = b2.ui.current_model(b2.ST)
    eq(model2.has_data, false, "a blob with corrupt halves reads as empty")
    eq(model2.level, 1, "a blob with corrupt halves keeps the starting level")
    eq(#model2.history, 0, "a blob with corrupt halves has no history")
end

-- The pure modules are not loaded at all (a client without them).
do
    local b = build({ blob = make_blob(), no_modules = true })
    local model = b.ui.current_model(b.ST)
    check(type(model) == "table", "no pure modules: the read model is still a table")
    eq(model.has_data, false, "no pure modules: the scope reads as empty")
    eq(b.ui.render_level(model), b.ui.NO_DATA_TEXT, "no pure modules: the page renders 'no data'")
    -- The duration formatter falls back to its own h:mm:ss when the stats module is
    -- not there to own the format.
    eq(b.ui.format_duration(3661), "1:01:01", "no pure modules: the duration fallback formats")
    eq(b.ui.format_duration(0), "0:00:00", "no pure modules: the duration fallback handles zero")
end

-- A malformed progress scope (bad types inside) must not raise.
do
    local b = build({ blob = {
        schema_version = 1,
        progress = { classes = { PALADIN = { xp = "lots", drills = 7 } }, global = 3 },
        stats = { classes = { PALADIN = { runs = "many", history = 5 } }, global = true },
    } })
    local ok, model = pcall(b.ui.current_model, b.ST)
    check(ok, "a malformed scope does not raise")
    if ok then
        eq(model.has_data, false, "a malformed scope reads as empty")
        eq(model.xp, 0, "a malformed scope has no XP")
    end
end

--=========================================================================================
-- 3) The read model WITH data: the numbers come from the pure modules
--=========================================================================================
local blob = make_blob()
local live = build({ blob = blob })
local lsb = live.sb
local lmodel = live.ui.current_model(live.ST)

eq(lsb.created_frames, 0, "no frame is created while reading the data")
check(lmodel.has_data, "the saved profile reads as data")
eq(lmodel.scope, "PALADIN", "the read model reads the player's own class scope")
check(lmodel.level >= 1, "the level is at least the starting level")
-- The XP is NOT the raw grade points: the anti-grind daily cap (3 x the drill's
-- median attempt XP) limits the twist drill to 300 XP per calendar day, the all-miss
-- drill earns nothing, and each completed session adds the flat +25 completion
-- bonus. Session one earns 300 + 25, session two 300 + 25 (12 attempts, so the
-- bonus applies again).
eq(lmodel.xp, 650, "the XP honours the daily per-drill cap and the session bonus")
eq(#lmodel.drills, 2, "both practised drills appear in the per-drill rows")
eq(lmodel.stats.runs, 2, "the class ran two sessions")
eq(lmodel.stats.attempts, 52, "the class made 52 attempts")
eq(lmodel.stats.hits, 42, "the class hit 42 times")
eq(lmodel.stats.misses, 10, "the class missed 10 times")
near(lmodel.stats.accuracy, 42 / 52, "the lifetime accuracy is the hit rate")
-- The rolling window holds the LAST 20 attempts: 10 misses followed by 12 hits.
near(lmodel.stats.rolling_accuracy, 0.6, "the rolling-20 accuracy is the last 20 attempts")
eq(lmodel.stats.best_grade, "S", "the best grade is the best single attempt")
eq(lmodel.stats.best_session_score, 90, "the best session score is recorded")
eq(lmodel.stats.time_active_seconds, 165, "the time active is recorded")
eq(lmodel.best_streak, 30, "the best streak is the run of 30 hits")
eq(#lmodel.history, 2, "the history holds the two sessions")
eq(lmodel.history[1].score, 75, "the older history entry carries the session score")
near(lmodel.history[1].accuracy, 0.75, "the older history entry carries the session accuracy")
eq(lmodel.history[1].day, 20000, "the older history entry carries the session day")
eq(lmodel.history[2].score, 90, "the newer history entry carries the session score")
near(lmodel.history[2].accuracy, 1, "the newer history entry carries the session accuracy")
eq(lmodel.history[2].day, 20001, "the newer history entry carries the session day")

-- The drill rows: the tier comes from the mastery rules (42 attempts clears the
-- 20-attempt volume gate and 100% accuracy clears the 60% Bronze gate, but the
-- 50-attempt Silver gate is not reached).
local twist_row, miss_row
for _, row in ipairs(lmodel.drills) do
    if row.id == "paladin_twist" then twist_row = row end
    if row.id == "hunter_forced_move" then miss_row = row end
end
check(twist_row ~= nil, "the twist drill has a row")
check(miss_row ~= nil, "the forced-move drill has a row")
if twist_row then
    eq(twist_row.attempts, 42, "the twist row counts the attempts")
    eq(twist_row.tier, "bronze", "the twist drill reached Bronze")
    eq(twist_row.tier_name, "Bronze", "the twist drill shows the Bronze tier")
    eq(twist_row.ranked, true, "the twist drill passed the 20-attempt volume gate")
    near(twist_row.mastery_pct, 100, "the twist drill's mastery is 100%")
    near(twist_row.accuracy, 1, "the twist drill's accuracy is 100%")
    eq(twist_row.name, "Twist practice", "the twist drill is named after its scenario")
end
if miss_row then
    near(miss_row.accuracy, 0, "the forced-move drill's accuracy is 0%")
    near(miss_row.mastery_pct, 0, "the forced-move drill's mastery is 0%")
    eq(miss_row.tier, "unranked", "the forced-move drill is unranked below 20 attempts")
    eq(miss_row.name, "Forced-move drill", "the forced-move drill is named after its scenario")
end

-- The achievements: the registry's definitions and the scope's unlock flags.
eq(#lmodel.achievements, 7, "the registry holds the seven spec achievements")
local unlocked_count = 0
for _, achievement in ipairs(lmodel.achievements) do
    if achievement.unlocked then unlocked_count = unlocked_count + 1 end
end
eq(unlocked_count, 2, "the scope holds the two unlocked achievements")
local saw_locked, saw_unlocked = false, false
for _, achievement in ipairs(lmodel.achievements) do
    if achievement.id == "first_s" then saw_unlocked = achievement.unlocked end
    if achievement.id == "ten_hours" then saw_locked = achievement.unlocked end
end
eq(saw_unlocked, true, "first_s reads as unlocked")
eq(saw_locked, false, "ten_hours reads as locked")

-- The class list and the per-class rows.
local keys = live.ui.class_keys_with_data(live.ST)
eq(#keys, 2, "two classes carry data")
eq(keys[1], "PALADIN", "the class list is sorted")
eq(keys[2], "ROGUE", "the class list holds the rogue scope")
local rows = live.ui.class_model_rows(live.ST)
eq(#rows, 2, "the per-class table has a row per class with data")
eq(rows[1].name, "Paladin", "the per-class row names the class")
eq(rows[2].runs, 1, "the rogue row carries its run count")

-- The account scope aggregates both classes.
local account = live.ui.account_model(live.ST)
check(account.has_data, "the account scope reads as data")
eq(account.stats.attempts, 57, "the account scope counts every class's attempts")
eq(account.stats.runs, 3, "the account scope counts every class's runs")
eq(#account.drills, 3, "the account scope merges every class's drills")

--=========================================================================================
-- 4) The renderers
--=========================================================================================
do
    local m = live.ui
    local level = m.render_level(lmodel)
    contains(level, "Level ", "the level line names the level")
    contains(level, "XP ", "the level line carries the XP")
    contains(level, "total", "the level line carries the lifetime XP")

    local bar = m.render_xp_bar(lmodel)
    eq(#bar, 20, "the XP bar is 20 cells wide")
    check(bar:find("#", 1, true) ~= nil, "the XP bar has filled cells")

    local mastery = m.render_mastery(lmodel)
    contains(mastery, "Unranked", "the mastery table shows the tier")
    contains(mastery, "attempts", "the mastery table shows the attempts")
    contains(mastery, "accuracy", "the mastery table shows the accuracy")

    local achievements = m.render_achievements(lmodel)
    contains(achievements, "2 of 7 unlocked", "the achievements list counts the unlocks")
    contains(achievements, "[x]", "the achievements list marks the unlocked ones")
    contains(achievements, "[ ]", "the achievements list marks the locked ones")

    local stats = m.render_stats(lmodel)
    contains(stats, "Runs 2", "the stats summary shows the runs")
    contains(stats, "Attempts 52", "the stats summary shows the attempts")
    contains(stats, "80.8%", "the stats summary shows the accuracy")
    contains(stats, "Rolling 20", "the stats summary shows the rolling-20 accuracy")
    contains(stats, "Time active", "the stats summary shows the time active")
    contains(stats, "Best score", "the stats summary shows the best score")
    contains(stats, "Best grade S", "the stats summary shows the best grade")
    contains(stats, "Best streak", "the stats summary shows the best streak")
    -- M4 (progression audit 2026-10-20): the DAILY streak is computed into the read
    -- model and was never displayed - the page showed the lifetime best streak
    -- where a streak readout would go. It is a first-class progression metric (the
    -- gate for the week_streak achievement), so it must be on the page - read from
    -- the model, never recomputed here.
    contains(stats, "Daily streak", "the stats summary shows the daily streak")
    contains(stats, "Daily streak " .. tostring(lmodel.daily_streak),
        "the stats summary shows the model's daily streak value")
    eq(lmodel.daily_streak, 2, "the read model carries the two-day daily streak")

    check(type(m.render_page(lmodel)) == "string", "the whole page renders a string")
    contains(m.render_page(lmodel), "Level ", "the whole page carries the level")

    eq(m.format_duration(3661), "1:01:01", "a duration renders as h:mm:ss")
    eq(m.format_duration(-5), "0:00:00", "a negative duration renders as zero")
    eq(m.format_day(0), "1970-01-01", "the day ordinal 0 is 1970-01-01")
    eq(m.format_day(20000), "2024-10-04", "the day ordinal 20000 is 2024-10-04")
    eq(m.format_day(-1), nil, "a missing day renders as nil")
end

--=========================================================================================
-- 5) The stats frame
--=========================================================================================
do
    local b = build({ blob = blob })
    local m, S = b.ui, b.ST
    eq(b.sb.created_frames, 0, "the frame is not built before the first open")

    local opened = m.open_frame(S)
    eq(opened, true, "the frame opens")
    check(b.sb.created_frames > 0, "the frame is built on the first open")
    check(m.frame ~= nil, "the frame exists after the open")
    eq(m.is_open(S), true, "the frame reports itself as open")
    eq(m.frame.shown, true, "the frame is shown after the open")

    -- The sparkline: one bar per session, oldest left, newest right.
    eq(#m.spark_bars, 2, "the sparkline draws one bar per session")
    eq(m.spark_bars[1].height, math.floor(0.75 * 84), "the older bar's height is its accuracy")
    eq(m.spark_bars[2].height, math.floor(1.0 * 84), "the newer bar's height is its accuracy")
    eq(m.spark_bars[1].hidden, false, "the bar is visible")
    eq(m.spark_markers[1].hidden, false, "the bar's top marker is visible")
    check(m.spark_bars[1].color ~= nil, "the bar carries its accuracy colour")

    -- The scope label and the summary line.
    eq(m.scope_label(S, "PALADIN"), "Paladin", "the scope label names the class")
    eq(m.scope_label(S, "GLOBAL"), "All classes", "the account scope reads 'All classes'")
    contains(m.frame.summary.text, "Paladin", "the summary names the scope")
    contains(m.frame.summary.text, "Level", "the summary carries the level")
    -- M4 (progression audit 2026-10-20): the frame's summary line carries the daily
    -- streak too - the model owns the number.
    contains(m.frame.summary.text, "Daily streak", "the summary carries the daily streak")
    contains(m.frame.summary.text, "Daily streak " .. tostring(lmodel.daily_streak),
        "the summary carries the model's daily streak value")

    -- The per-drill table (the rows are sorted by drill id, so the forced-move drill
    -- comes before the twist drill).
    local first_drill_row = m.drill_rows and m.drill_rows[1]
    check(first_drill_row ~= nil, "the first drill row exists")
    if first_drill_row then
        eq(first_drill_row[1].text, "Forced-move drill", "the drill row names the drill")
        eq(first_drill_row[2].text, "Unranked", "the drill row shows the tier")
        eq(first_drill_row[4].text, "10", "the drill row shows the attempts")
        eq(first_drill_row[5].text, "0.0%", "the drill row shows the accuracy")
    end
    local second_drill_row = m.drill_rows and m.drill_rows[2]
    check(second_drill_row ~= nil, "the second drill row exists")
    if second_drill_row then
        eq(second_drill_row[1].text, "Twist practice", "the second drill row names the drill")
        eq(second_drill_row[2].text, "Bronze", "the second drill row shows the tier")
        eq(second_drill_row[4].text, "42", "the second drill row shows the attempts")
        eq(second_drill_row[5].text, "100.0%", "the second drill row shows the accuracy")
    end

    -- The per-class table (two classes have data, so it is shown).
    local first_class_row = m.class_row_labels and m.class_row_labels[1]
    check(first_class_row ~= nil, "the first class row exists")
    if first_class_row then
        eq(first_class_row[1].text, "Paladin", "the class row names the class")
        eq(first_class_row[2].text, tostring(lmodel.level), "the class row shows the level")
        eq(first_class_row[3].text, "2", "the class row shows the runs")
        eq(first_class_row[1].hidden, false, "the per-class row is shown")
    end
    eq(m.frame.class_header.hidden, false, "the per-class header is shown with two classes")

    -- The history list: newest first.
    local first_history_row = m.history_rows and m.history_rows[1]
    check(first_history_row ~= nil, "the first history row exists")
    if first_history_row then
        eq(first_history_row[1].text, "1", "the newest history row is numbered first")
        eq(first_history_row[2].text, "2024-10-05", "the newest history row shows the date")
        eq(first_history_row[3].text, "90", "the newest history row shows the score")
        eq(first_history_row[4].text, "100.0%", "the newest history row shows the accuracy")
        eq(first_history_row[5].text, "12", "the newest history row shows the attempts")
        eq(first_history_row[6].text, "0:00:45", "the newest history row shows the duration")
    end
    local second_history_row = m.history_rows and m.history_rows[2]
    check(second_history_row ~= nil, "the second history row exists")
    if second_history_row then
        eq(second_history_row[1].text, "2", "the older history row is numbered second")
        eq(second_history_row[2].text, "2024-10-04", "the older history row shows the date")
        eq(second_history_row[3].text, "75", "the older history row shows the score")
        eq(second_history_row[4].text, "75.0%", "the older history row shows the accuracy")
        eq(second_history_row[5].text, "40", "the older history row shows the attempts")
        eq(second_history_row[6].text, "0:02:00", "the older history row shows the duration")
    end

    -- The scope cycle walks the scopes that have data.
    local scopes = m.frame_scopes(S)
    eq(#scopes, 3, "the scopes are the two classes plus the account scope")
    eq(m.frame_scope(S), "PALADIN", "the frame starts on the player's own class")
    m.cycle_scope(S)
    eq(m.frame_scope_key, "ROGUE", "the cycle moves to the next scope")
    m.cycle_scope(S)
    eq(m.frame_scope_key, "GLOBAL", "the cycle reaches the account scope")
    m.cycle_scope(S)
    eq(m.frame_scope_key, "PALADIN", "the cycle wraps around")

    -- Closing hides the frame again.
    m.close_frame(S)
    eq(m.is_open(S), false, "the frame reports itself as closed")
    eq(m.frame.shown, false, "the frame is hidden after the close")
    m.toggle_frame(S)
    eq(m.is_open(S), true, "the toggle reopens the frame")
    eq(m.frame.shown, true, "the toggled frame is shown")
end

-- The per-class table hides when only one class has data (it would just repeat the
-- summary line).
do
    local single = make_blob()
    single.progress.classes.ROGUE = nil
    single.stats.classes.ROGUE = nil
    local b = build({ blob = single })
    local m, S = b.ui, b.ST
    m.open_frame(S)
    eq(#m.class_model_rows(S), 1, "only the paladin scope has data")
    eq(m.frame.class_header.hidden, true, "the per-class table hides with one class")
    eq(m.class_row_labels[1][1].hidden, true, "the per-class rows hide with one class")
end

-- The frame with no data: it opens empty and never raises.
do
    local b = build({})
    local m, S = b.ui, b.ST
    local ok = pcall(m.open_frame, S)
    check(ok, "the frame opens with no data at all")
    eq(m.is_open(S), true, "the empty frame is open")
    eq(#m.spark_bars, 0, "the empty sparkline draws no bars")
    contains(m.frame.summary.text, "No practice data yet", "the empty frame says 'no data'")
    contains(m.frame.spark_caption.text, "No sessions", "the empty frame says no sessions")
    check(m.history_rows[1][1].hidden, "the empty history hides its rows")
    check(m.drill_rows[1][1].hidden, "the empty drill table hides its rows")
    eq(m.frame.class_header.hidden, true, "the per-class table hides with no class data")
    local close_ok = pcall(m.close_frame, S)
    check(close_ok, "the empty frame closes")
end

-- The history list scrolls: with more sessions than the viewport can show, the wheel
-- moves the window over the older sessions and back.
do
    local env = setmetatable({}, { __index = _G })
    local pure = {}
    local stats_mod = assert(loadfile(ROOT .. "practice_stats.lua"))
    setfenv(stats_mod, env)
    stats_mod("SwedgeTimer", pure)
    local progress_mod = assert(loadfile(ROOT .. "practice_progress.lua"))
    setfenv(progress_mod, env)
    progress_mod("SwedgeTimer", pure)
    local stats_state = pure.practice_stats.new_state()
    local progress_state = pure.practice_progress.new_state()
    -- 20 sessions, oldest first.
    for i = 1, 20 do
        pure.practice_stats.record_session(stats_state, "PALADIN",
            { attempts = 4, hits = 3, score = 50 + i, best_grade = "A" }, 10, 20000 + i)
        local session = pure.practice_progress.new_session()
        for _ = 1, 4 do
            pure.practice_progress.record_attempt(progress_state, session, "PALADIN",
                "paladin_twist", "A", 20000 + i)
        end
        pure.practice_progress.end_session(progress_state, session, "PALADIN", 20000 + i)
    end
    local b = build({ blob = {
        schema_version = 1, progress = progress_state, stats = stats_state,
    } })
    local m, S = b.ui, b.ST
    m.open_frame(S)
    eq(m.history_offset, 1, "the history starts at the newest session")
    eq(m.history_rows[1][3].text, "70", "the first visible row is the newest session")
    eq(m.history_rows[1][1].text, "1", "the first visible row is numbered first")

    -- The wheel scrolls towards the older sessions (a positive delta scrolls up).
    local wheel = m.history_view:GetScript("OnMouseWheel")
    check(type(wheel) == "function", "the history viewport has a mouse-wheel handler")
    if wheel then
        wheel(m.history_view, 1)
        eq(m.history_offset, 4, "the wheel moved the window three rows down")
        eq(m.history_rows[1][1].text, "4", "the first visible row is the fourth session")
        eq(m.history_rows[1][3].text, "67", "the first visible row shows the older session")
        wheel(m.history_view, -1)
        eq(m.history_offset, 1, "the wheel scrolled back to the newest")
    end
    -- The offset is clamped to the end of the list.
    for _ = 1, 40 do m.scroll_history(1) end
    eq(m.history_offset, 8, "the offset is clamped to the last page (20 - 13 + 1)")
    for _ = 1, 40 do m.scroll_history(-1) end
    eq(m.history_offset, 1, "the offset is clamped to the newest session")
end

--=========================================================================================
-- 6) The reset: arm, confirm, cancel
--=========================================================================================
do
    local b = build({ blob = blob })
    local m, S = b.ui, b.ST
    eq(m.reset_armed(), false, "the reset starts disarmed")
    eq(m.request_reset(S), false, "the first reset call only arms it")
    eq(m.reset_armed(), true, "the reset is armed after the first call")
    eq(b.sb.profile.practice, blob, "the armed reset has not touched the saved blob")

    m.disarm_reset()
    eq(m.reset_armed(), false, "the cancel disarms the reset")
    eq(b.sb.profile.practice, blob, "the cancelled reset has not touched the saved blob")

    m.request_reset(S)
    eq(m.reset_armed(), true, "the reset is armed again")
    eq(m.request_reset(S), true, "the second reset call performs it")
    eq(m.reset_armed(), false, "the performed reset disarms itself")
    check(b.sb.profile.practice ~= blob, "the performed reset replaced the saved blob")
    check(type(b.sb.profile.practice) == "table", "the replaced blob is a table")
    check(type(b.sb.profile.practice.progress) == "table", "the fresh blob carries a progress half")
    check(type(b.sb.profile.practice.stats) == "table", "the fresh blob carries a stats half")
    check(b.sb.notified > 0, "the reset asks AceConfig to redraw the page")

    -- After the reset the page reads as empty again.
    local model = m.current_model(S)
    eq(model.has_data, false, "the page reads as empty after the reset")
    eq(m.render_stats(model), m.NO_DATA_TEXT, "the page renders 'no data' after the reset")
end

-- The reset must not touch anything but the practice key.
do
    local other = { welcome_message = true }
    local profile = { practice = blob, other = other, welcome_message = true }
    local b = build({ blob = blob })
    local m = b.ui
    -- Point the sandbox at its own profile table.
    local saved = b.ST.get_profile_table
    b.ST.get_profile_table = function() return profile end
    local ok = pcall(m.perform_reset, b.ST)
    check(ok, "the reset runs against a profile table")
    check(profile.practice ~= blob, "the reset replaced the practice key")
    eq(profile.other, other, "the reset left the other profile keys alone")
    eq(profile.welcome_message, true, "the reset left the sibling profile keys alone")
    b.ST.get_profile_table = saved
end

-- The reset with no profile table at all must not raise.
do
    local b = build({ blob = blob })
    local ok = pcall(b.ui.perform_reset, { player_class = "PALADIN" })
    check(ok, "the reset survives a missing profile table")
end

-- A blob written by a NEWER build is not ours to erase.
do
    local newer = { schema_version = 99, progress = {}, stats = {} }
    local b = build({ blob = newer })
    local result = b.ui.perform_reset(b.ST)
    eq(result, false, "the reset refuses a blob from a newer build")
    eq(b.sb.profile.practice, newer, "the newer blob was left alone")
end

-- The reset drops the hook lane's live cache, or its next save would restore the
-- state the player just erased. It also asks the hook lane to clear the LIVE
-- session's counters: a session that kept its pre-reset attempts would award a
-- completion bonus for attempts the player just erased (M1, deep audit 2026-10-20).
do
    local b = build({ blob = blob })
    local cache = { progress = {}, stats = {} }
    local resets = 0
    b.st.practice_ui = {
        progress_profile = cache,
        progress_persistable = true,
        progress_last_save = 123,
        reset_progress_session = function()
            resets = resets + 1
            return true
        end,
    }
    b.ui.perform_reset(b.ST)
    eq(b.st.practice_ui.progress_profile, nil, "the reset dropped the hook lane's live cache")
    eq(b.st.practice_ui.progress_persistable, nil, "the reset dropped the persistable flag")
    eq(b.st.practice_ui.progress_last_save, nil, "the reset dropped the last-save stamp")
    eq(resets, 1, "the reset asked the hook lane to clear the live session's counters")
end

-- A hook lane WITHOUT the reset entry point (an older build, or a client where the
-- lane is not loaded) must not break the reset.
do
    local b = build({ blob = blob })
    b.st.practice_ui = { progress_profile = { progress = {}, stats = {} } }
    local ok, err = pcall(b.ui.perform_reset, b.ST)
    check(ok, "the reset survives a hook lane without the session-reset entry point ("
        .. tostring(err) .. ")")
    eq(b.st.practice_ui.progress_profile, nil, "the reset still dropped the live cache")
end

--=========================================================================================
-- 7) L2 (progression audit 2026-10-20): the reserved "_unknown" bucket is a
-- coherent row and it carries a display name instead of the raw key.
--=========================================================================================
do
    local m = live.ui
    eq(m.drill_name("_unknown"), "Unknown drill",
        "the reserved bucket has a display name, not the raw key")

    -- The blob the fixed hook writes: an attempt with no usable drill id is recorded
    -- on BOTH sides under the same reserved key, so the merged row's accuracy is a
    -- measurement and not a fabricated zero.
    local unknown = make_blob()
    unknown.progress.classes.PALADIN.drills._unknown = {
        attempts = 4, hits = 3, recent = { "S", "A", "S", "F" },
        daily_xp = 0, daily_day = nil,
    }
    unknown.stats.classes.PALADIN.drills._unknown = { attempts = 4, hits = 3 }
    local b = build({ blob = unknown })
    local model = b.ui.current_model(b.ST)
    local row = nil
    for _, candidate in ipairs(model.drills) do
        if candidate.id == "_unknown" then row = candidate end
    end
    check(row ~= nil, "the reserved bucket has a row")
    if row then
        eq(row.name, "Unknown drill", "the reserved row is named, not keyed by the raw id")
        eq(row.attempts, 4, "the reserved row counts the attempts")
        near(row.accuracy, 0.75, "the reserved row's accuracy is the stats side's measurement")
    end
    local rendered = b.ui.render_mastery(model)
    contains(rendered, "Unknown drill", "the mastery table names the reserved bucket")
    check(rendered:find("_unknown", 1, true) == nil,
        "the mastery table never shows the raw reserved key")
end

--=========================================================================================
-- 8) M5 (progression audit 2026-10-20): the reset's armed state EXPIRES.
--=========================================================================================
do
    local b = build({ blob = blob })
    local m, S = b.ui, b.ST
    eq(m.reset_armed(), false, "the reset starts disarmed")
    eq(m.request_reset(S), false, "the first reset call only arms it")
    eq(m.reset_armed(), true, "the reset is armed after the first call")
    eq(b.sb.profile.practice, blob, "the armed reset has not touched the saved blob")

    -- Inside the arm window the arm holds: a deliberate, adjacent second click works.
    b.sb.clock = b.sb.clock + 5
    eq(m.reset_armed(), true, "the arm survives inside its window")

    -- The window elapses: the arm is EXPIRED, not still waiting for a confirm.
    b.sb.clock = b.sb.clock + 20
    eq(m.reset_armed(), false, "the expired arm is disarmed on the spot")
    eq(m.reset_state, nil, "the expired arm left no state behind")

    -- A click on the stale "Confirm" button does NOT wipe anything: it re-arms.
    eq(m.request_reset(S), false, "the click after the expiry only re-arms the reset")
    eq(b.sb.profile.practice, blob, "the stale confirm did not touch the saved blob")
    eq(m.reset_armed(), true, "the re-armed reset is armed again")

    -- A deliberate, adjacent second click still performs the reset.
    eq(m.request_reset(S), true, "the second click within the window performs the reset")
    check(b.sb.profile.practice ~= blob, "the performed reset replaced the saved blob")
    eq(m.reset_armed(), false, "the performed reset disarms itself")
end

--=========================================================================================
-- 9) M3 (progression audit 2026-10-20): the "no date recorded" sentinel reaches the
-- renderer.
--
-- The stats module's NO_DAY sentinel (-1) means "no date recorded". The read model
-- read the day with count(), which clamps a negative to 0 - the epoch - so a
-- no-date session rendered 1970-01-01 instead of "-". The day is read SIGNED now,
-- so the sentinel survives all the way to the renderer.
--=========================================================================================
do
    -- A blob with one session that has NO date at all.
    local st = {}
    local env = setmetatable({}, { __index = _G })
    local stats_mod = assert(loadfile(ROOT .. "practice_stats.lua"))
    setfenv(stats_mod, env)
    stats_mod("SwedgeTimer", st)
    local progress_mod = assert(loadfile(ROOT .. "practice_progress.lua"))
    setfenv(progress_mod, env)
    progress_mod("SwedgeTimer", st)
    local P, S = st.practice_progress, st.practice_stats
    local progress_state = P.new_state()
    local stats_state = S.new_state()
    local session = P.new_session()
    P.record_attempt(progress_state, session, "PALADIN", "paladin_twist", "S", nil)
    S.record_attempt(stats_state, "PALADIN", "S", "paladin_twist")
    P.end_session(progress_state, session, "PALADIN", nil)
    S.record_session(stats_state, "PALADIN", { attempts = 1, hits = 1, score = 100,
        best_grade = "S" }, 30, nil)
    -- The pure module stores the sentinel, not the epoch.
    eq(stats_state.classes.PALADIN.history[1].day, S.NO_DAY,
        "M3: the stats module stores the no-day sentinel")

    local b = build({ blob = { schema_version = 1, progress = progress_state,
        stats = stats_state } })
    local m = b.ui
    local model = m.scope_model(b.ST, "PALADIN")
    eq(#model.history, 1, "M3: the no-date session is in the history")
    eq(model.history[1].day, S.NO_DAY,
        "M3: the no-day sentinel survives the read model")
    eq(m.format_day(model.history[1].day), nil,
        "M3: the sentinel renders as no date at all")

    -- The renderer: the row shows "-", never 1970-01-01.
    eq(m.open_frame(b.ST), true, "M3: the stats frame opens")
    local row = m.history_rows and m.history_rows[1]
    check(row ~= nil, "M3: the history row exists")
    if row then
        eq(row[2].text, "-", "M3: a no-date session renders as '-'")
        check(row[2].text ~= "1970-01-01",
            "M3: a no-date session never renders as the epoch")
    end
end

--=========================================================================================
-- Summary
--=========================================================================================
print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
