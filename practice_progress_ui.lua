--=========================================================================================
-- Practice progress UI: the Progress options page and the practice stats frame.
--
-- Design source: bench/practice_gamification_design_2026-10-19.md §3 (the stats
-- section: an options page "Progress" with the level, the XP bar, the per-drill mastery
-- table, the achievements list and the stats summary; a stats frame opened from the
-- page with the accuracy-over-time sparkline over the last 50 sessions, the full
-- per-drill and per-class tables and the history list) and §4 (the achievements).
--
-- This is the UI lane (spec §7 step 3). It READS the live data the hook lane (step 2)
-- writes into SwedgeTimerDB.profile.practice and renders it. It never recomputes a
-- number the pure modules own: every figure on the page comes from their read models -
--
--   * st.practice_stats.snapshot(stats_state)
--         -> the per-scope lifetime aggregates (runs / attempts / hits / misses /
--            accuracy lifetime + rolling-20 + last session / best session score / best
--            grade / time active) and the bounded session history
--   * st.practice_progress.profile_snapshot(progress, stats_snapshot, scope_key)
--         -> the level / renown / XP / per-drill mastery + tier / streaks / unlock flags
--
-- so the page can never disagree with the rules that produced the data.
--
-- Nil-safe by construction: every read goes through a guard that turns a missing table,
-- a missing key or a wrong type into zeros and an empty list. With no practice data at
-- all the page renders "No practice data yet" and the stats frame opens empty - never
-- an error (spec §6 "Guards").
--
-- No default-visible change: nothing is created or shown until the player opens the
-- stats frame from the Progress page. The frame is built on the first open and hidden
-- afterwards. The only write this module performs is the explicit, confirmed reset.
--
-- Load order: this module loads right after practice_progress.lua, so both pure modules
-- and practice.lua (the scenario catalogue that names the drills) are already loaded.
--=========================================================================================
local addon_name, st = ...

st.practice_progress_ui = st.practice_progress_ui or {}
local ui = st.practice_progress_ui

--=========================================================================================
-- Constants
--=========================================================================================

-- The account scope key. The pure modules own the name; the fallback keeps the frame
-- readable when the pure module is not loaded.
local ACCOUNT_SCOPE_FALLBACK = "GLOBAL"

-- The reserved drill bucket: the pure progression module files an attempt with no
-- usable drill id under this key (practice_progress.lua's record_attempt), so the
-- attempt's XP is still tracked and still capped. The hook lane records the SAME
-- key on the stats side, so the merged row is one coherent row - and here it gets a
-- display name instead of the raw key.
local UNKNOWN_DRILL_KEY = "_unknown"

-- The reset's arm window: how long the first click stays armed. The confirm must be
-- a deliberate, ADJACENT second click: a stale "Confirm" button that survives for
-- minutes can wipe every level, XP, mastery, achievement and saved session long
-- after the player clicked the wrong thing. Fifteen seconds is long enough for a
-- deliberate double-click and short enough that a player who comes back to the page
-- cannot hit a stale confirm by accident.
local RESET_ARM_SECONDS = 15

-- The text the page shows when there is nothing to show.
ui.NO_DATA_TEXT = "No practice data yet - run a practice drill to start earning XP."

-- Frame geometry (the stats frame).
local FRAME_WIDTH = 680
local FRAME_HEIGHT = 460
local COL_LEFT_X = 14
local COL_LEFT_WIDTH = 318
local COL_RIGHT_X = 348
local COL_RIGHT_WIDTH = 318
local ROW_HEIGHT = 14
local HEADER_HEIGHT = 16

-- Sparkline geometry.
local SPARK_HEIGHT = 84
local SPARK_BAR_MAX_WIDTH = 12
local SPARK_BAR_GAP = 1
local SPARK_MARKER_SIZE = 2

-- The row ceilings: the tables are fixed size, so their content is bounded.
local DRILL_ROW_MAX = 8
local CLASS_ROW_MAX = 9
local HISTORY_ROW_MAX = 50
local HISTORY_VISIBLE_ROWS = 13

-- The accuracy bands the sparkline colours by.
local SPARK_COLOR_HIGH = { 0.25, 0.85, 0.35 }
local SPARK_COLOR_MID = { 0.95, 0.80, 0.20 }
local SPARK_COLOR_LOW = { 0.90, 0.25, 0.20 }
local SPARK_HIGH_BAND = 0.85
local SPARK_MID_BAND = 0.60

-- The XP progress bar: 20 cells.
local XP_BAR_CELLS = 20

-- The table columns (x offset, width, justification). The widths add up to the column
-- width, so a row never spills into the next column.
local DRILL_COLUMNS = {
    { x = 0, width = 112, align = "LEFT" },
    { x = 116, width = 58, align = "LEFT" },
    { x = 176, width = 50, align = "RIGHT" },
    { x = 230, width = 42, align = "RIGHT" },
    { x = 276, width = 42, align = "RIGHT" },
}
local CLASS_COLUMNS = {
    { x = 0, width = 92, align = "LEFT" },
    { x = 96, width = 34, align = "RIGHT" },
    { x = 134, width = 34, align = "RIGHT" },
    { x = 172, width = 48, align = "RIGHT" },
    { x = 224, width = 40, align = "LEFT" },
    { x = 266, width = 52, align = "RIGHT" },
}
local HISTORY_COLUMNS = {
    { x = 0, width = 24, align = "LEFT" },
    { x = 28, width = 74, align = "LEFT" },
    { x = 106, width = 34, align = "RIGHT" },
    { x = 144, width = 48, align = "RIGHT" },
    { x = 196, width = 36, align = "RIGHT" },
    { x = 236, width = 60, align = "RIGHT" },
}

--=========================================================================================
-- Guards
--=========================================================================================

-- A finite number, or the fallback. Rejects non-numbers, NaN and the infinities.
local function num(value, fallback)
    if type(value) ~= "number" then return fallback end
    if value ~= value then return fallback end
    if value == math.huge or value == -math.huge then return fallback end
    return value
end

-- A finite, non-negative integer counter.
local function count(value)
    local v = num(value, 0)
    if v < 0 then return 0 end
    if v > 2 ^ 53 then return 2 ^ 53 end
    return math.floor(v)
end

-- A fraction clamped into 0..1.
local function clamp01(value)
    local v = num(value, 0)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- A chat notice, through the addon's own print helper (the addon's output policy: the
-- live error paths go through st.utils.print_msg, never a bare global print).
local function notify(message)
    if st.utils and type(st.utils.print_msg) == "function" then
        pcall(st.utils.print_msg, message)
    end
end

-- The account scope key the pure modules use.
local function account_scope()
    local P = st.practice_progress
    if P and type(P.GLOBAL_SCOPE) == "string" and P.GLOBAL_SCOPE ~= "" then
        return P.GLOBAL_SCOPE
    end
    return ACCOUNT_SCOPE_FALLBACK
end

--=========================================================================================
-- Reading the live data
--=========================================================================================

-- The saved practice blob, or nil. Read defensively: the db may carry no practice key
-- at all (the hook lane wires it), and the blob itself may be the wrong type.
function ui.read_blob(ST)
    if type(ST) ~= "table" then return nil end
    if type(ST.get_profile_table) ~= "function" then return nil end
    local ok, profile = pcall(ST.get_profile_table, ST)
    if not ok or type(profile) ~= "table" then return nil end
    local blob = profile.practice
    if type(blob) ~= "table" then return nil end
    return blob
end

-- The two halves of the live data: the progress state and the stats state. Either may
-- be nil - that means "not there", never an error.
function ui.live_data(ST)
    local blob = ui.read_blob(ST)
    if not blob then return nil, nil end
    local progress = (type(blob.progress) == "table") and blob.progress or nil
    local stats = (type(blob.stats) == "table") and blob.stats or nil
    return progress, stats
end

-- The class key the saved data actually uses for the player's class. The lookup is
-- case-tolerant (the addon uses the uppercase class token; a save written by hand may
-- use the lowercase one) and returns the key as it is stored, so the pure modules'
-- exact-key lookups hit.
function ui.resolve_class_key(ST, progress, stats)
    local wanted = nil
    if type(ST) == "table" then
        if type(ST.player_class) == "string" and ST.player_class ~= "" then
            wanted = ST.player_class
        elseif type(ST.player_class_pretty) == "string" and ST.player_class_pretty ~= "" then
            wanted = ST.player_class_pretty
        end
    end
    if not wanted then return nil end
    local candidates = { wanted, string.upper(wanted), string.lower(wanted) }
    for _, source in ipairs({ progress, stats }) do
        local classes = (type(source) == "table") and source.classes or nil
        if type(classes) == "table" then
            for _, key in ipairs(candidates) do
                if type(classes[key]) == "table" then return key end
            end
        end
    end
    return wanted
end

-- The class key the page reads: the stored key for the player's class, or the addon's
-- own class token when there is no saved data at all.
function ui.current_class_key(ST)
    local progress, stats = ui.live_data(ST)
    local key = ui.resolve_class_key(ST, progress, stats)
    if key then return key end
    if type(ST) == "table" and type(ST.player_class) == "string" and ST.player_class ~= "" then
        return ST.player_class
    end
    return ""
end

-- A display name for a class key: "PALADIN" -> "Paladin".
function ui.pretty_class(key)
    if type(key) ~= "string" or key == "" then return "Unknown" end
    local first = key:match("^(%a)")
    if not first then return key end
    return first:upper() .. key:sub(2):lower()
end

-- The display name of a drill id. The pure modules store the drill id the hook lane
-- recorded; when that id is a registered practice scenario the scenario's own title is
-- the friendly name, and anything else falls back to the raw id (never a guess).
-- The reserved bucket is the one exception: it is a real row, so it gets a name
-- instead of the raw key (L2).
function ui.drill_name(id)
    if type(id) ~= "string" or id == "" then return "(unnamed drill)" end
    if id == UNKNOWN_DRILL_KEY then return "Unknown drill" end
    local harness = st.practice and st.practice.harness
    local scenarios = (type(harness) == "table") and harness.SCENARIOS or nil
    if type(scenarios) == "table" then
        local spec = scenarios[id]
        if type(spec) == "table" and type(spec.title) == "string" and spec.title ~= "" then
            return spec.title
        end
    end
    return id
end

-- Every class key that has any recorded data, sorted. A class counts as "has data"
-- when its progress scope carries XP, a drill, a streak or an unlock, or its stats
-- scope carries a run, an attempt or a session in the history.
function ui.class_keys_with_data(ST)
    local progress, stats = ui.live_data(ST)
    local keys = {}
    local function note(key)
        if type(key) ~= "string" or key == "" then return end
        for _, existing in ipairs(keys) do
            if existing == key then return end
        end
        keys[#keys + 1] = key
    end
    local function scan(source)
        local classes = (type(source) == "table") and source.classes or nil
        if type(classes) ~= "table" then return end
        for key, scope in pairs(classes) do
            if type(scope) == "table" then
                local used = false
                if count(scope.xp) > 0 then used = true end
                if count(scope.runs) > 0 then used = true end
                if count(scope.attempts) > 0 then used = true end
                if count(scope.best_streak) > 0 then used = true end
                if count(scope.daily_streak) > 0 then used = true end
                if type(scope.drills) == "table" and next(scope.drills) ~= nil then used = true end
                if type(scope.unlocks) == "table" and next(scope.unlocks) ~= nil then used = true end
                if type(scope.history) == "table" and #scope.history > 0 then used = true end
                if used then note(key) end
            end
        end
    end
    scan(progress)
    scan(stats)
    table.sort(keys)
    return keys
end

--=========================================================================================
-- The read model
--=========================================================================================

-- The normalised read model of one scope. Every field is a plain number, string or
-- list, so the renderers never have to guard and the tests can assert on them.
--
-- scope_key is a class key or the account scope. nil means the account scope.
function ui.scope_model(ST, scope_key)
    if scope_key == nil then scope_key = account_scope() end

    local progress, stats = ui.live_data(ST)
    local P = st.practice_progress
    local S = st.practice_stats

    -- The stats read model (the pure module owns every number in it).
    local stats_snapshot = {}
    if S and type(S.snapshot) == "function" then
        local ok, snapshot = pcall(S.snapshot, stats)
        if ok and type(snapshot) == "table" then stats_snapshot = snapshot end
    end

    -- The progression read model: the level, the XP, the mastery tiers, the streaks and
    -- the unlock flags, merged with the stats scope.
    local snapshot = {}
    if P and type(P.profile_snapshot) == "function" then
        local ok, merged = pcall(P.profile_snapshot, progress, stats_snapshot, scope_key)
        if ok and type(merged) == "table" then snapshot = merged end
    end

    -- The stats scope of this key: the account scope, or the class scope.
    local stats_scope
    if scope_key == account_scope() then
        stats_scope = stats_snapshot.global
    else
        local classes = (type(stats_snapshot.classes) == "table") and stats_snapshot.classes or nil
        stats_scope = classes and classes[scope_key] or nil
    end
    stats_scope = (type(stats_scope) == "table") and stats_scope or {}

    local model = {
        scope = scope_key,
        is_account = (scope_key == account_scope()),
        has_data = false,
        level = 1,
        renown = 0,
        raw_level = 1,
        xp = 0,
        xp_into_level = 0,
        xp_for_next_level = 0,
        best_streak = 0,
        daily_streak = 0,
        drills = {},
        achievements = {},
        history = {},
        stats = {
            runs = 0,
            attempts = 0,
            hits = 0,
            misses = 0,
            accuracy = 0,
            rolling_accuracy = 0,
            last_session_accuracy = 0,
            best_session_score = 0,
            best_grade = "",
            best_s_streak = 0,
            time_active_seconds = 0,
            history_count = 0,
        },
    }

    local level = count(snapshot.level)
    if level >= 1 then model.level = level end
    model.renown = count(snapshot.renown)
    model.raw_level = count(snapshot.raw_level)
    model.xp = count(snapshot.xp)
    model.xp_into_level = count(snapshot.xp_into_level)
    model.xp_for_next_level = count(snapshot.xp_for_next_level)
    model.best_streak = count(snapshot.best_streak)
    model.daily_streak = count(snapshot.daily_streak)

    local stats_model = model.stats
    stats_model.runs = count(stats_scope.runs)
    stats_model.attempts = count(stats_scope.attempts)
    stats_model.hits = count(stats_scope.hits)
    stats_model.misses = count(stats_scope.misses)
    stats_model.accuracy = num(stats_scope.accuracy, 0)
    stats_model.rolling_accuracy = num(stats_scope.rolling_accuracy, 0)
    stats_model.last_session_accuracy = num(stats_scope.last_session_accuracy, 0)
    stats_model.best_session_score = count(stats_scope.best_session_score)
    stats_model.best_grade = (type(stats_scope.best_grade) == "string") and stats_scope.best_grade or ""
    stats_model.best_s_streak = count(stats_scope.best_s_streak)
    stats_model.time_active_seconds = count(stats_scope.time_active_seconds)
    stats_model.history_count = count(stats_scope.history_count)

    -- The per-drill rows: the merged progress + stats rows of the scope.
    local rows = (type(snapshot.drills) == "table") and snapshot.drills or {}
    local ids = {}
    for id in pairs(rows) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local row = rows[id]
        if type(row) == "table" then
            model.drills[#model.drills + 1] = {
                id = id,
                name = ui.drill_name(id),
                tier = (type(row.tier) == "string") and row.tier or "unranked",
                tier_name = (type(row.tier_name) == "string") and row.tier_name or "Unranked",
                ranked = row.ranked == true,
                accuracy = num(row.accuracy, 0),
                mastery_pct = num(row.mastery_pct, 0),
                attempts = count(row.attempts),
                hits = count(row.hits),
            }
        end
    end

    -- The achievements: the registry's achievement-kind definitions and their unlock
    -- state in this scope.
    local unlocked = (type(snapshot.unlocks) == "table") and snapshot.unlocks or {}
    local definitions = {}
    if P and type(P.unlock_definitions) == "function" then
        local ok, list = pcall(P.unlock_definitions, P.KIND_ACHIEVEMENT)
        if ok and type(list) == "table" then definitions = list end
    end
    for _, definition in ipairs(definitions) do
        if type(definition) == "table" then
            local id = (type(definition.id) == "string") and definition.id or ""
            model.achievements[#model.achievements + 1] = {
                id = id,
                label = (type(definition.label) == "string") and definition.label or id,
                unlocked = unlocked[id] == true,
            }
        end
    end

    -- The session history (oldest first, as the pure module keeps it).
    local history = (type(stats_scope.history) == "table") and stats_scope.history or {}
    -- M3 (progression audit 2026-10-20): the day is read SIGNED. The stats
    -- module's NO_DAY sentinel (-1) means "no date recorded"; count() clamped it
    -- to 0 (the epoch) and the row rendered as 1970-01-01 instead of "-".
    local no_day = -1
    if S and type(S.NO_DAY) == "number" then no_day = S.NO_DAY end
    for i = 1, #history do
        local entry = history[i]
        if type(entry) == "table" then
            model.history[#model.history + 1] = {
                score = count(entry.score),
                accuracy = num(entry.accuracy, 0),
                attempts = count(entry.attempts),
                hits = count(entry.hits),
                day = num(entry.day, no_day),
                duration = count(entry.duration),
            }
        end
    end

    model.has_data = (stats_model.runs > 0) or (stats_model.attempts > 0) or (model.xp > 0)
        or (#model.drills > 0) or (#model.history > 0)

    return model
end

-- The read model of the player's own class.
function ui.current_model(ST)
    return ui.scope_model(ST, ui.current_class_key(ST))
end

-- The read model of the account scope (every class).
function ui.account_model(ST)
    return ui.scope_model(ST, account_scope())
end

-- One row per class that has data: the level, the runs, the accuracy, the best grade
-- and the time active, read from the same read model the page uses.
function ui.class_model_rows(ST)
    local rows = {}
    for _, key in ipairs(ui.class_keys_with_data(ST)) do
        local model = ui.scope_model(ST, key)
        rows[#rows + 1] = {
            key = key,
            name = ui.pretty_class(key),
            level = model.level,
            runs = model.stats.runs,
            attempts = model.stats.attempts,
            accuracy = model.stats.accuracy,
            best_grade = model.stats.best_grade,
            time_active_seconds = model.stats.time_active_seconds,
        }
    end
    return rows
end

--=========================================================================================
-- Formatting
--=========================================================================================

-- A percentage from a 0..1 fraction.
local function pct_fraction(value)
    return string.format("%.1f%%", clamp01(value) * 100)
end

-- A percentage from a 0..100 value (the mastery read model uses points, the stats read
-- model uses a fraction - the two are never mixed).
local function pct_points(value)
    local v = num(value, 0)
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    return string.format("%.1f%%", v)
end

-- h:mm:ss of an accumulated duration. The stats module owns the format; the fallback
-- keeps the frame readable when the pure module is not loaded.
function ui.format_duration(seconds)
    local S = st.practice_stats
    if S and type(S.format_duration) == "function" then
        local ok, text = pcall(S.format_duration, seconds)
        if ok and type(text) == "string" then return text end
    end
    local total = count(seconds)
    return string.format("%d:%02d:%02d",
        math.floor(total / 3600), math.floor((total % 3600) / 60), total % 60)
end

-- A "YYYY-MM-DD" string for a civil day ordinal (days since 1970-01-01). The inverse
-- of the pure modules' day_ordinal(): the same proleptic Gregorian calendar, so a
-- saved ordinal renders the date it was recorded as. nil when there is no date (the
-- stats module's NO_DAY sentinel, -1, means "no date recorded").
function ui.format_day(ordinal)
    local raw = num(ordinal, nil)
    if raw == nil then return nil end
    if raw < 0 then return nil end
    local days = math.floor(raw)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524)
        - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    y = y + (m <= 2 and 1 or 0)
    return string.format("%04d-%02d-%02d", y, m, d)
end

--=========================================================================================
-- The page renderers (plain text; the options page feeds them to description widgets)
--=========================================================================================

-- The level and the XP inside it.
function ui.render_level(model)
    if type(model) ~= "table" or not model.has_data then return ui.NO_DATA_TEXT end
    local out = string.format("Level %d", model.level)
    if model.renown > 0 then
        out = out .. string.format("  (renown %d)", model.renown)
    end
    out = out .. string.format("\nXP %d / %d   (%d XP total)",
        model.xp_into_level, model.xp_for_next_level, model.xp)
    return out
end

-- The XP progress bar: 20 cells, filled proportionally to the XP inside the level.
function ui.render_xp_bar(model)
    if type(model) ~= "table" or not model.has_data then return "" end
    local need = count(model.xp_for_next_level)
    if need <= 0 then return "" end
    local into = count(model.xp_into_level)
    if into < 0 then into = 0 end
    if into > need then into = need end
    local filled = math.floor((into / need) * XP_BAR_CELLS + 0.5)
    if filled < 0 then filled = 0 end
    if filled > XP_BAR_CELLS then filled = XP_BAR_CELLS end
    local out = ""
    for i = 1, XP_BAR_CELLS do
        if i <= filled then out = out .. "#" else out = out .. "-" end
    end
    return out
end

-- The per-drill mastery table: tier, mastery percentage, attempts and accuracy.
function ui.render_mastery(model)
    if type(model) ~= "table" then return ui.NO_DATA_TEXT end
    if #model.drills == 0 then return "No drills practised yet." end
    local lines = {}
    for _, row in ipairs(model.drills) do
        lines[#lines + 1] = string.format("  %s - %s - %s mastery - %d attempts - %s accuracy",
            row.name, row.tier_name, pct_points(row.mastery_pct), row.attempts,
            pct_fraction(row.accuracy))
    end
    return table.concat(lines, "\n")
end

-- The achievements list: the unlocked ones marked, the locked ones not.
function ui.render_achievements(model)
    if type(model) ~= "table" then return ui.NO_DATA_TEXT end
    if #model.achievements == 0 then return "No achievements registered." end
    local unlocked = 0
    local lines = {}
    for _, achievement in ipairs(model.achievements) do
        if achievement.unlocked then unlocked = unlocked + 1 end
        lines[#lines + 1] = string.format("  [%s] %s",
            achievement.unlocked and "x" or " ", achievement.label)
    end
    return string.format("%d of %d unlocked\n%s", unlocked, #model.achievements,
        table.concat(lines, "\n"))
end

-- The lifetime stats summary: runs, attempts, accuracy (lifetime and rolling-20), the
-- time active, the best score, the best grade, the best streak and the DAILY
-- streak.
--
-- M4 (progression audit 2026-10-20): the daily streak was computed into the read
-- model and never displayed - the page showed the lifetime BEST streak where a
-- streak readout would go. The daily streak is a first-class progression metric (it
-- is the gate for the week_streak achievement), so it gets its own line here. It is
-- READ from the model (model.daily_streak), never recomputed here.
function ui.render_stats(model)
    if type(model) ~= "table" or not model.has_data then return ui.NO_DATA_TEXT end
    local stats = model.stats
    return string.format(
        "Runs %d  |  Attempts %d  |  Accuracy %s\n"
        .. "Rolling 20: %s  |  Last session: %s\n"
        .. "Time active %s  |  Best score %d  |  Best grade %s\n"
        .. "Best streak %d  |  Daily streak %d",
        stats.runs, stats.attempts, pct_fraction(stats.accuracy),
        pct_fraction(stats.rolling_accuracy), pct_fraction(stats.last_session_accuracy),
        ui.format_duration(stats.time_active_seconds), stats.best_session_score,
        (stats.best_grade ~= "" and stats.best_grade or "-"), model.best_streak,
        model.daily_streak)
end

-- The whole page as one block.
function ui.render_page(model)
    if type(model) ~= "table" then return ui.NO_DATA_TEXT end
    return table.concat({
        ui.render_level(model),
        ui.render_xp_bar(model),
        ui.render_mastery(model),
        ui.render_achievements(model),
        ui.render_stats(model),
    }, "\n")
end

--=========================================================================================
-- The reset
--=========================================================================================

-- The clock the reset's arm window is measured against: the addon's aligned clock
-- (the GetTime() domain, monotonic within a session). nil when the addon has no
-- clock - then the arm never expires on its own and only the Cancel button (or the
-- second click) disarms it.
function ui.now()
    local api = st.api
    if type(api) == "table" and type(api.get_time) == "function" then
        local ok, now = pcall(api.get_time)
        if ok and type(now) == "number" and now == now then
            return now
        end
    end
    return nil
end

-- Has the armed reset outlived its window? The deadline is checked LAZILY - at
-- every decision point (the button's label, the confirm click) - so an arm nobody
-- looks at again costs nothing and can never wipe anything.
function ui.reset_arm_expired()
    local armed_at = ui.reset_armed_at
    if type(armed_at) ~= "number" then
        return false
    end
    local now = ui.now()
    if type(now) ~= "number" then
        return false
    end
    return (now - armed_at) >= RESET_ARM_SECONDS
end

-- Is the reset armed (the first click pressed the button, the second one confirms)?
--
-- M5 (progression audit 2026-10-20): the arm never expired and nothing disarmed it
-- when the options panel closed, so a stale "Confirm: reset all practice progress"
-- button could wipe every level, XP, mastery, achievement and saved session long
-- after the first click scrolled out of sight - the arm's whole purpose defeated.
-- An arm older than RESET_ARM_SECONDS is EXPIRED and disarmed on the spot, so the
-- confirm must be a deliberate, adjacent second click. The options page re-reads the
-- armed state on every redraw (the button's label and the Cancel button's
-- visibility), so an expired arm cannot leave a stale "Confirm" behind either.
function ui.reset_armed()
    if ui.reset_state ~= "armed" then
        return false
    end
    if ui.reset_arm_expired() then
        ui.reset_state = nil
        ui.reset_armed_at = nil
        return false
    end
    return true
end

-- The reset action. The first call arms it; the second performs it. The options page
-- shows the armed state on the button, so one mis-click cannot wipe the saved data.
function ui.request_reset(ST)
    if ui.reset_armed() then
        ui.reset_state = nil
        ui.reset_armed_at = nil
        return ui.perform_reset(ST)
    end
    ui.reset_state = "armed"
    ui.reset_armed_at = ui.now()
    return false
end

-- Disarm the reset without performing it.
function ui.disarm_reset()
    ui.reset_state = nil
    ui.reset_armed_at = nil
end

-- The hook lane (practice_ui.lua) keeps the live progression state in its own cache
-- and writes it back into the profile on its next save. A reset must drop that cache
-- too, or the next save would restore the state the player just erased. Guarded: the
-- cache only exists once the hook lane has run.
local function clear_progress_cache()
    local pui = st.practice_ui
    if type(pui) ~= "table" then return end
    if pui.progress_profile ~= nil then pui.progress_profile = nil end
    if pui.progress_persistable ~= nil then pui.progress_persistable = nil end
    if pui.progress_last_save ~= nil then pui.progress_last_save = nil end
    -- M1 (deep audit 2026-10-20): the LIVE session's own counters go with the saved
    -- data. A session that kept its pre-reset attempts would award a completion
    -- bonus for attempts the player just erased and would show a stale "+N XP" on
    -- the badge; the session keeps running, but its progression bookkeeping starts
    -- over. The hook lane owns the session's shape, so the reset asks it for a
    -- fresh one (guarded: the lane may not be loaded).
    if type(pui.reset_progress_session) == "function" then
        pui.reset_progress_session()
    end
end

-- Perform the reset: replace the saved practice blob with a fresh profile. The other
-- saved variables are never touched - only the practice key is replaced.
function ui.perform_reset(ST)
    ui.reset_state = nil
    ui.reset_armed_at = nil
    if type(ST) ~= "table" or type(ST.get_profile_table) ~= "function" then return false end
    local ok, profile = pcall(ST.get_profile_table, ST)
    if not ok or type(profile) ~= "table" then return false end

    local blob = profile.practice
    local P = st.practice_progress
    -- A blob a NEWER build wrote is not ours to erase: the pure module leaves it
    -- alone, and so does the reset (the player can go back to that build).
    if type(blob) == "table" then
        local version = type(blob.schema_version) == "number" and blob.schema_version or nil
        local current = (P and type(P.SCHEMA_VERSION) == "number") and P.SCHEMA_VERSION or 1
        if version and version > current then
            notify("Practice progress was written by a newer build - not reset.")
            return false
        end
    end

    local fresh = nil
    if P and type(P.new_profile) == "function" then
        local built, built_profile = pcall(P.new_profile)
        if built and type(built_profile) == "table" then fresh = built_profile end
    end
    if not fresh then
        fresh = { schema_version = 1, progress = {}, stats = {} }
    end
    profile.practice = fresh
    clear_progress_cache()

    ui.refresh_frame(ST)
    ui.notify_options_refresh()
    notify("Practice progress reset.")
    return true
end

-- Ask AceConfig to redraw the open page so the description widgets pick up the new
-- numbers. Guarded: the registry only exists once the options dialog is loaded.
function ui.notify_options_refresh()
    if type(LibStub) ~= "function" then return end
    local ok, registry = pcall(LibStub, "AceConfigRegistry-3.0")
    if not ok or type(registry) ~= "table" then return end
    if type(registry.NotifyChange) ~= "function" then return end
    pcall(registry.NotifyChange, "SwedgeTimer_Options")
end

--=========================================================================================
-- The stats frame
--=========================================================================================

-- A label with the font set BEFORE the first SetText (the SoD crash rule: a FontString
-- without a font throws on SetText).
local function make_label(parent, x, y, width, align, font)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width or 100)
    fs:SetJustifyH(align or "LEFT")
    fs:SetFontObject(font or GameFontHighlightSmall)
    fs:SetText("")
    return fs
end

-- A table row: one FontString per column. The row is built once and reused for every
-- refresh (the text is set, the row is not rebuilt).
local function create_row(parent, y, columns)
    local labels = {}
    for i, column in ipairs(columns) do
        labels[i] = make_label(parent, column.x, y, column.width, column.align)
    end
    return labels
end

-- Set the text of a row from a list of column texts.
local function set_row(labels, texts)
    for i = 1, #labels do
        local fs = labels[i]
        if fs then
            local text = texts[i]
            fs:SetText((type(text) == "string") and text or "")
        end
    end
end

-- Hide every label of a row (an unused table row).
local function hide_row(labels)
    for i = 1, #labels do
        local fs = labels[i]
        if fs then fs:Hide() end
    end
end

-- Show every label of a row.
local function show_row(labels)
    for i = 1, #labels do
        local fs = labels[i]
        if fs then fs:Show() end
    end
end

-- A clickable label (a Button with a FontString on it).
local function make_button(parent, x, y, width, height, text, onclick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetFontObject(GameFontHighlightSmall)
    label:SetText(text)
    button.label = label
    button:SetScript("OnClick", onclick)
    return button
end

-- The sparkline colour of an accuracy.
local function spark_color(accuracy)
    if accuracy >= SPARK_HIGH_BAND then return SPARK_COLOR_HIGH end
    if accuracy >= SPARK_MID_BAND then return SPARK_COLOR_MID end
    return SPARK_COLOR_LOW
end

-- The sparkline bar (and its top marker) for one session. The textures are pooled and
-- reused across refreshes.
function ui.spark_bar(index)
    local bars = ui.spark_bars
    if not bars[index] then
        bars[index] = ui.spark:CreateTexture(nil, "ARTWORK")
        ui.spark_markers[index] = ui.spark:CreateTexture(nil, "OVERLAY")
    end
    return bars[index]
end

-- Build the stats frame. It is created on the first open and hidden afterwards, so
-- nothing of it is ever visible unless the player asks for it.
function ui.build_frame(ST)
    if ui.frame then return ui.frame end

    local frame = CreateFrame("Frame", addon_name .. "PracticeStatsFrame", UIParent, "BackdropTemplate")
    ui.frame = frame
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    frame:SetScript("OnDragStart", function(f)
        -- Repositioning is user-driven only, never during lockdown.
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
    end)
    frame:Hide()

    -- Title.
    local title = make_label(frame, 12, -10, 320, "LEFT", GameFontNormal)
    title:SetText("|cFFFF8800Practice Progress|r")
    frame.title = title

    -- Close button.
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetSize(20, 20)
    close:SetScript("OnClick", function()
        ui.close_frame(ST)
    end)
    frame.close_button = close

    -- The scope button (cycles through the scopes that have data) and the refresh
    -- button.
    local scope_button = make_button(frame, 12, -32, 220, 16, "Scope", function()
        ui.cycle_scope(ST)
    end)
    frame.scope_button = scope_button
    local refresh_button = make_button(frame, 240, -32, 80, 16, "Refresh", function()
        ui.refresh_frame(ST)
    end)
    frame.refresh_button = refresh_button

    -- The one-line summary under the header.
    local summary = make_label(frame, 12, -52, FRAME_WIDTH - 24, "LEFT")
    frame.summary = summary

    -- The sparkline (accuracy over the last sessions).
    local spark = CreateFrame("Frame", nil, frame)
    spark:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_LEFT_X, -78)
    spark:SetSize(COL_LEFT_WIDTH, SPARK_HEIGHT)
    ui.spark = spark
    ui.spark_bars = {}
    ui.spark_markers = {}
    local baseline = spark:CreateTexture(nil, "BACKGROUND")
    baseline:SetPoint("BOTTOMLEFT", spark, "BOTTOMLEFT", 0, 0)
    baseline:SetSize(COL_LEFT_WIDTH, 1)
    baseline:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    ui.spark_baseline = baseline

    local spark_caption = make_label(frame, COL_LEFT_X, -168, COL_LEFT_WIDTH, "LEFT")
    spark_caption:SetText("Accuracy over the last sessions (oldest left, newest right)")
    frame.spark_caption = spark_caption

    -- The per-drill table.
    local drill_header = make_label(frame, COL_LEFT_X, -190, COL_LEFT_WIDTH, "LEFT")
    drill_header:SetText("Drill mastery")
    frame.drill_header = drill_header
    ui.drill_header_row = create_row(frame, -190 - HEADER_HEIGHT, DRILL_COLUMNS)
    set_row(ui.drill_header_row, { "Drill", "Tier", "Mastery", "Attempts", "Accuracy" })
    ui.drill_rows = {}
    for i = 1, DRILL_ROW_MAX do
        ui.drill_rows[i] = create_row(frame, -190 - HEADER_HEIGHT - i * ROW_HEIGHT, DRILL_COLUMNS)
    end

    -- The per-class table.
    local class_header = make_label(frame, COL_RIGHT_X, -78, COL_RIGHT_WIDTH, "LEFT")
    class_header:SetText("Per class")
    frame.class_header = class_header
    ui.class_header_row = create_row(frame, -78 - HEADER_HEIGHT, CLASS_COLUMNS)
    set_row(ui.class_header_row,
        { "Class", "Level", "Runs", "Accuracy", "Best", "Time" })
    ui.class_row_labels = {}
    for i = 1, CLASS_ROW_MAX do
        ui.class_row_labels[i] = create_row(frame, -78 - HEADER_HEIGHT - i * ROW_HEIGHT, CLASS_COLUMNS)
    end

    -- The history list (newest first) in a wheel-driven viewport.
    local history_header = make_label(frame, COL_RIGHT_X, -236, COL_RIGHT_WIDTH, "LEFT")
    history_header:SetText("Session history")
    frame.history_header = history_header
    ui.history_header_row = create_row(frame, -236 - HEADER_HEIGHT, HISTORY_COLUMNS)
    set_row(ui.history_header_row,
        { "#", "Date", "Score", "Accuracy", "Attempts", "Duration" })

    local view = CreateFrame("Frame", nil, frame)
    view:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_RIGHT_X, -252)
    view:SetSize(COL_RIGHT_WIDTH, HISTORY_VISIBLE_ROWS * ROW_HEIGHT)
    ui.history_view = view
    ui.history_offset = 1
    ui.history_rows = {}
    for i = 1, HISTORY_VISIBLE_ROWS do
        ui.history_rows[i] = create_row(view, -(i - 1) * ROW_HEIGHT, HISTORY_COLUMNS)
    end

    -- The scroll indicator: a thumb that tracks the offset. The list is scrolled by
    -- this module (not by a client ScrollFrame), so the thumb is the only thing that
    -- has to agree with the rows - and both are computed here.
    local track = view:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPRIGHT", view, "TOPRIGHT", -2, 0)
    track:SetSize(3, HISTORY_VISIBLE_ROWS * ROW_HEIGHT)
    track:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    local thumb = view:CreateTexture(nil, "ARTWORK")
    thumb:SetPoint("TOPRIGHT", view, "TOPRIGHT", -2, 0)
    thumb:SetSize(3, 20)
    thumb:SetColorTexture(0.8, 0.8, 0.8, 0.9)
    ui.history_thumb = thumb

    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta)
        ui.scroll_history(delta)
    end)

    return frame
end

-- The scopes the stats frame can show: every class that has data, plus the account
-- scope. The frame's scope is one of them.
function ui.frame_scopes(ST)
    local scopes = {}
    for _, key in ipairs(ui.class_keys_with_data(ST)) do
        scopes[#scopes + 1] = key
    end
    scopes[#scopes + 1] = account_scope()
    return scopes
end

-- The scope the frame currently shows. It starts on the player's own class when that
-- class has data, then on the first class that has data, then on the account scope.
function ui.frame_scope(ST)
    local scopes = ui.frame_scopes(ST)
    if #scopes == 0 then return account_scope() end
    local current = ui.current_class_key(ST)
    for _, key in ipairs(scopes) do
        if key == current then return key end
    end
    return scopes[1]
end

-- Move the frame to the next scope.
function ui.cycle_scope(ST)
    local scopes = ui.frame_scopes(ST)
    if #scopes <= 1 then return end
    local current = ui.frame_scope_key or scopes[1]
    local index = 1
    for i, key in ipairs(scopes) do
        if key == current then
            index = i
            break
        end
    end
    local next_index = (index % #scopes) + 1
    ui.frame_scope_key = scopes[next_index]
    ui.history_offset = 1
    ui.refresh_frame(ST)
end

-- The scope label: the pretty class name, or "All classes" for the account scope.
function ui.scope_label(ST, scope_key)
    if scope_key == account_scope() then return "All classes" end
    local current = ui.current_class_key(ST)
    if scope_key == current then
        if type(ST) == "table" and type(ST.player_class_pretty) == "string"
            and ST.player_class_pretty ~= "" then
            return ST.player_class_pretty
        end
    end
    return ui.pretty_class(scope_key)
end

-- Draw the sparkline: one bar per session, oldest left, newest right.
function ui.render_sparkline(model)
    if not ui.spark then return end
    local history = model.history
    local total = #history
    if total > HISTORY_ROW_MAX then total = HISTORY_ROW_MAX end

    local bar_width = math.floor((COL_LEFT_WIDTH - (total - 1) * SPARK_BAR_GAP) / math.max(total, 1))
    if bar_width > SPARK_BAR_MAX_WIDTH then bar_width = SPARK_BAR_MAX_WIDTH end
    if bar_width < 1 then bar_width = 1 end
    local group = total * bar_width + math.max(total - 1, 0) * SPARK_BAR_GAP
    local start = (COL_LEFT_WIDTH - group) / 2

    for i = 1, total do
        local entry = history[i]
        local accuracy = clamp01(entry.accuracy)
        local height = math.floor(accuracy * SPARK_HEIGHT)
        if height < 1 then height = 1 end
        local x = start + (i - 1) * (bar_width + SPARK_BAR_GAP)
        local bar = ui.spark_bar(i)
        local marker = ui.spark_markers[i]
        bar:Show()
        marker:Show()
        bar:SetSize(bar_width, height)
        bar:SetPoint("BOTTOMLEFT", ui.spark, "BOTTOMLEFT", x, 0)
        local r, g, b = spark_color(accuracy)
        bar:SetColorTexture(r, g, b, 0.85)
        marker:SetSize(SPARK_MARKER_SIZE, SPARK_MARKER_SIZE)
        marker:SetPoint("BOTTOMLEFT", ui.spark, "BOTTOMLEFT",
            x + (bar_width - SPARK_MARKER_SIZE) / 2, height)
        marker:SetColorTexture(r, g, b, 1)
    end
    for i = total + 1, #ui.spark_bars do
        ui.spark_bars[i]:Hide()
        ui.spark_markers[i]:Hide()
    end
end

-- Redraw the stats frame from the live data.
function ui.refresh_frame(ST)
    local frame = ui.frame
    if not frame then return end

    -- The scope: the one the frame was put on, as long as it still exists. A scope
    -- whose data vanished (a reset) falls back to the player's own class.
    local scope_key = ui.frame_scope_key
    local known = false
    for _, key in ipairs(ui.frame_scopes(ST)) do
        if key == scope_key then known = true break end
    end
    if not known then scope_key = ui.frame_scope(ST) end
    local model = ui.scope_model(ST, scope_key)
    local label = ui.scope_label(ST, scope_key)
    ui.frame_model = model

    if frame.scope_button and frame.scope_button.label then
        frame.scope_button.label:SetText("Scope: " .. label)
    end
    if frame.summary then
        if model.has_data then
            -- M4 (progression audit 2026-10-20): the daily streak is on the frame's
            -- summary line too, read from the model (never recomputed here).
            frame.summary:SetText(string.format(
                "%s - Level %d  |  Runs %d  |  Accuracy %s  |  Daily streak %d",
                label, model.level, model.stats.runs,
                string.format("%.1f%%", clamp01(model.stats.accuracy) * 100),
                model.daily_streak))
        else
            frame.summary:SetText(label .. " - " .. ui.NO_DATA_TEXT)
        end
    end

    -- The sparkline.
    ui.render_sparkline(model)
    if frame.spark_caption then
        local sessions = #model.history
        if sessions == 0 then
            frame.spark_caption:SetText("No sessions recorded yet")
        else
            frame.spark_caption:SetText(string.format(
                "Accuracy over the last %d session(s) (oldest left, newest right)", sessions))
        end
    end

    -- The per-drill table.
    for i = 1, DRILL_ROW_MAX do
        local row = ui.drill_rows[i]
        local data = model.drills[i]
        if data then
            show_row(row)
            set_row(row, {
                data.name,
                data.tier_name,
                string.format("%.1f%%", math.min(math.max(data.mastery_pct, 0), 100)),
                tostring(data.attempts),
                string.format("%.1f%%", clamp01(data.accuracy) * 100),
            })
        else
            hide_row(row)
        end
    end

    -- The per-class table: only worth a panel when more than one class has data
    -- (with one class it would just repeat the summary line).
    local class_rows = ui.class_model_rows(ST)
    local show_classes = (#class_rows > 1)
    if frame.class_header then
        frame.class_header:SetText("Per class")
        if show_classes then
            frame.class_header:Show()
        else
            frame.class_header:Hide()
        end
    end
    if ui.class_header_row then
        if show_classes then
            show_row(ui.class_header_row)
        else
            hide_row(ui.class_header_row)
        end
    end
    for i = 1, CLASS_ROW_MAX do
        local row = ui.class_row_labels[i]
        local data = class_rows[i]
        if data and show_classes then
            show_row(row)
            set_row(row, {
                data.name,
                tostring(data.level),
                tostring(data.runs),
                string.format("%.1f%%", clamp01(data.accuracy) * 100),
                (data.best_grade ~= "" and data.best_grade or "-"),
                ui.format_duration(data.time_active_seconds),
            })
        else
            hide_row(row)
        end
    end

    -- The history list, newest first.
    ui.render_history_rows(model)
end

-- Lay out the history rows for the current offset. The list is newest first, and the
-- offset is the index (1-based) of the first visible row in that order.
function ui.render_history_rows(model)
    if type(model) ~= "table" then return end
    local history = model.history
    local total = #history
    if total > HISTORY_ROW_MAX then total = HISTORY_ROW_MAX end
    local visible = HISTORY_VISIBLE_ROWS

    -- The offset never runs past the end of the list.
    local offset = ui.history_offset or 1
    if offset < 1 then offset = 1 end
    local last_offset = total - visible + 1
    if last_offset < 1 then last_offset = 1 end
    if offset > last_offset then offset = last_offset end
    ui.history_offset = offset

    for i = 1, visible do
        local row = ui.history_rows[i]
        local index = offset + i - 1
        local entry = history[total - index + 1]
        if entry then
            show_row(row)
            set_row(row, {
                tostring(index),
                ui.format_day(entry.day) or "-",
                tostring(entry.score),
                string.format("%.1f%%", clamp01(entry.accuracy) * 100),
                tostring(entry.attempts),
                ui.format_duration(entry.duration),
            })
        else
            hide_row(row)
        end
    end

    -- The scroll thumb: its height is the visible share of the list, its position the
    -- offset.
    if ui.history_thumb then
        local viewport = visible * ROW_HEIGHT
        local content = total * ROW_HEIGHT
        if total <= visible then
            ui.history_thumb:SetSize(3, viewport)
            ui.history_thumb:SetPoint("TOPRIGHT", ui.history_view, "TOPRIGHT", -2, 0)
        else
            local thumb_height = math.max(16, math.floor(viewport * viewport / content))
            local travel = viewport - thumb_height
            local span = total - visible
            local y = -math.floor(travel * (offset - 1) / math.max(span, 1))
            ui.history_thumb:SetSize(3, thumb_height)
            ui.history_thumb:SetPoint("TOPRIGHT", ui.history_view, "TOPRIGHT", -2, y)
        end
    end
end

-- Scroll the history list by a wheel delta (positive scrolls up, towards the older
-- sessions). The offset is clamped to the list.
function ui.scroll_history(delta)
    local step = num(delta, 0)
    if step == 0 then return end
    local offset = (ui.history_offset or 1) + (step > 0 and 3 or -3)
    ui.history_offset = offset
    ui.render_history_rows(ui.frame_model)
end

-- Open the stats frame (building it on the first open).
function ui.open_frame(ST)
    local frame = ui.build_frame(ST)
    if not frame then return false end
    ui.frame_scope_key = ui.frame_scope_key or ui.frame_scope(ST)
    ui.history_offset = 1
    ui.refresh_frame(ST)
    frame:Show()
    ui.frame_open = true
    return true
end

-- Close the stats frame.
function ui.close_frame(ST)
    if ui.frame then ui.frame:Hide() end
    ui.frame_open = false
end

-- Toggle the stats frame.
function ui.toggle_frame(ST)
    if ui.is_open(ST) then
        ui.close_frame(ST)
        return false
    end
    return ui.open_frame(ST)
end

-- Is the stats frame open?
function ui.is_open(ST)
    return ui.frame_open == true
end
