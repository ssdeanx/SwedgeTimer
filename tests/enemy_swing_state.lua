-- tests/enemy_swing_state.lua: offline tests for enemy_swing.lua - the hostile-target
-- mainhand swing bar (SuperSwingTimer port).
--
-- Four sandboxes, each loading the real module file:
--   0. Static contract: the source never reads a raw clock, never gates on a
--      Mainline-code boolean, and keeps the compat api / CLEU names it needs.
--   1. WoW-free: loads with no CreateFrame/LibStub at all, pins every pure helper
--      (family matrix, off-hand rule, GUID matching, target eligibility, speed
--      precedence, cycle maths, rescale, visibility matrix, toggle read).
--   2. Frame sandbox (classic family): instrumented fake frames + a stubbed api, so the
--      driver's event registration, the lazy bar build on the mainhand bar frame, the
--      CLEU attribution (off-hand ignored, wrong source ignored, UNIT_DIED clears) and
--      the show/hide gates are checked against real code. Section 2b pins the M7
--      rendering: fallback cycles dim + show the target name, a dead clock hides.
--   3. Family matrix: FOREVER / RETAIL / UNKNOWN stay completely inert (no frame, no
--      event) even with an approving event probe; every classic-line family arms.
--      This is the mutation-proof section for the family gate.
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
-- lua5.1 tests/enemy_swing_state.lua  (any cwd works).

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

--=========================================================================================
-- 0. Static contract: clock rule, family-gate discipline, required compat names
--=========================================================================================
local src_file = assert(io.open(ROOT .. "enemy_swing.lua", "r"))
local src = src_file:read("*a")
src_file:close()
for _, token in ipairs({
    "GetTime(", "GetTimePreciseSec", "st.is_mainline",
}) do
    check(src:find(token, 1, true) == nil, "source has no " .. token .. " reference")
end
for _, token in ipairs({
    "st.api.get_time(", "CombatLogGetCurrentEventInfo", "family_supported",
}) do
    check(src:find(token, 1, true) ~= nil, "source uses " .. token)
end

--=========================================================================================
-- 1. WoW-free sandbox: load + every pure helper
--=========================================================================================
local st1 = { family = "ERA", api = { get_time = function() return 0 end } }
local env1 = setmetatable({}, { __index = _G })
local mod1 = assert(loadfile(ROOT .. "enemy_swing.lua"))
setfenv(mod1, env1)
local ok1, err1 = pcall(function() mod1("SwedgeTimer", st1) end)
check(ok1, "enemy_swing.lua loads under a WoW-free sandbox (" .. tostring(err1) .. ")")
local es = st1.enemy_swing
check(type(es) == "table", "st.enemy_swing table exists")
eq(es.active, false, "no CreateFrame: the module stays inactive")
check(es.runtime ~= nil and es.runtime.driver == nil, "no CreateFrame: no driver frame recorded")

-- constants ---------------------------------------------------------------
near(es.FALLBACK_SPEED, 2.0, "FALLBACK_SPEED == 2.0")
eq(es.CLEU_SUBEVENT_INDEX, 2, "CLEU subevent index == 2")
eq(es.CLEU_SOURCE_GUID_INDEX, 4, "CLEU source GUID index == 4")
eq(es.CLEU_TARGET_GUID_INDEX, 8, "CLEU target GUID index == 8")
eq(es.SWING_DAMAGE_OFFHAND_INDEX, 21, "SWING_DAMAGE offhand index == 21 (reference)")
eq(es.SWING_MISSED_OFFHAND_INDEX, 13, "SWING_MISSED offhand index == 13 (reference)")
eq(es.BAR_WIDTH, 200, "BAR_WIDTH == 200")
eq(es.BAR_HEIGHT, 10, "BAR_HEIGHT == 10")
eq(es.BAR_GAP, 2, "BAR_GAP == 2")
eq(es.BAR_PADDING, 1, "BAR_PADDING == 1")

-- family_supported: classic-line families only ------------------------------
eq(es.family_supported("ERA"), true, "family: ERA supported")
eq(es.family_supported("TBC"), true, "family: TBC supported")
eq(es.family_supported("WRATH"), true, "family: WRATH supported")
eq(es.family_supported("CATA"), true, "family: CATA supported")
eq(es.family_supported("MISTS"), true, "family: MISTS supported")
eq(es.family_supported("FOREVER"), false, "family: FOREVER inert (no classic combat log)")
eq(es.family_supported("RETAIL"), false, "family: RETAIL inert")
eq(es.family_supported("UNKNOWN"), false, "family: UNKNOWN inert")
eq(es.family_supported(nil), false, "family: nil inert")
eq(es.family_supported("era"), false, "family: lowercase never matches")
eq(es.family_supported(11509), false, "family: a version number never matches")

-- swing_hand: only explicit true is off-hand --------------------------------
eq(es.swing_hand("SWING_DAMAGE", nil), "mainhand", "hand: SWING_DAMAGE nil offhand -> mainhand")
eq(es.swing_hand("SWING_DAMAGE", false), "mainhand", "hand: SWING_DAMAGE false -> mainhand")
eq(es.swing_hand("SWING_DAMAGE", true), "offhand", "hand: SWING_DAMAGE true -> offhand")
eq(es.swing_hand("SWING_MISSED", nil), "mainhand", "hand: SWING_MISSED nil -> mainhand")
eq(es.swing_hand("SWING_MISSED", true), "offhand", "hand: SWING_MISSED true -> offhand")
eq(es.swing_hand("SWING_MISSED", "true"), "mainhand", "hand: string 'true' is not off-hand")
eq(es.swing_hand("SPELL_DAMAGE", false), nil, "hand: non-swing subevent -> nil")
eq(es.swing_hand(nil, nil), nil, "hand: nil subevent -> nil")

-- source_is_tracked ----------------------------------------------------------
eq(es.source_is_tracked("Enemy-1", "Enemy-1"), true, "source: equal GUIDs match")
eq(es.source_is_tracked("Enemy-1", "Enemy-2"), false, "source: different GUIDs never match")
eq(es.source_is_tracked(nil, "Enemy-1"), false, "source: nil source never matches")
eq(es.source_is_tracked("Enemy-1", nil), false, "source: nil tracked never matches")
eq(es.source_is_tracked("", ""), false, "source: empty GUIDs never match")
eq(es.source_is_tracked(123, 123), false, "source: non-string GUIDs never match")

-- should_track_target --------------------------------------------------------
eq(es.should_track_target(true, true, "Enemy-1"), true, "target: exists + attackable + GUID -> tracked")
eq(es.should_track_target(false, true, "Enemy-1"), false, "target: absent -> not tracked")
eq(es.should_track_target(true, false, "Enemy-1"), false, "target: non-attackable -> not tracked")
eq(es.should_track_target(true, true, nil), false, "target: nil GUID -> not tracked")
eq(es.should_track_target(true, true, ""), false, "target: empty GUID -> not tracked")
eq(es.should_track_target(true, true, 42), false, "target: non-string GUID -> not tracked")
eq(es.should_track_target(nil, nil, "Enemy-1"), false, "target: nil readings -> not tracked")
eq(es.should_track_target(1, 1, "Enemy-1"), false, "target: numeric 1 is not true")

-- resolve_speed --------------------------------------------------------------
near(es.resolve_speed(2.6, 3.0), 2.6, "speed: live reading wins")
near(es.resolve_speed(nil, 3.0), 3.0, "speed: nil reading falls back to the cached speed")
near(es.resolve_speed(0, 3.0), 3.0, "speed: zero reading falls back to the cached speed")
near(es.resolve_speed(-1, 3.0), 3.0, "speed: negative reading falls back to the cached speed")
near(es.resolve_speed(nil, nil), 2.0, "speed: nothing usable -> 2.0 fallback")
near(es.resolve_speed(0, 0), 2.0, "speed: zero cached -> 2.0 fallback")
near(es.resolve_speed(nil, -2), 2.0, "speed: negative cached -> 2.0 fallback")
near(es.resolve_speed("2.6", 3.0), 3.0, "speed: non-number reading falls back")
near(es.resolve_speed(0 / 0, 3.0), 3.0, "speed: NaN reading falls back")

-- resolve_speed_with_source (M7 rendering provenance) ------------------------
local r_speed, r_source = es.resolve_speed_with_source(2.6, 3.0)
near(r_speed, 2.6, "source: live reading wins")
eq(r_source, "live", "source: a usable reading is marked live")
r_speed, r_source = es.resolve_speed_with_source(nil, 3.0)
near(r_speed, 3.0, "source: nil reading falls back to the cached speed")
eq(r_source, "cached", "source: the cached speed is marked cached")
r_speed, r_source = es.resolve_speed_with_source(nil, nil)
near(r_speed, 2.0, "source: nothing usable falls back to 2.0")
eq(r_source, "fallback", "source: the 2.0 estimate is marked fallback")
r_speed, r_source = es.resolve_speed_with_source(0, -2)
near(r_speed, 2.0, "source: unusable values fall back to 2.0")
eq(r_source, "fallback", "source: unusable cached speed is marked fallback")

-- new_cycle ------------------------------------------------------------------
local cycle = es.new_cycle(10, 2)
check(cycle ~= nil and cycle.start == 10 and cycle.speed == 2, "cycle: valid input arms the cycle")
eq(es.new_cycle(10, 2, "fallback").source, "fallback", "cycle: the provenance is carried")
eq(es.new_cycle(10, 0), nil, "cycle: zero speed -> nil")
eq(es.new_cycle(10, -1), nil, "cycle: negative speed -> nil")
eq(es.new_cycle(nil, 2), nil, "cycle: nil start -> nil")
eq(es.new_cycle(10, nil), nil, "cycle: nil speed -> nil")
eq(es.new_cycle("10", 2), nil, "cycle: string start -> nil")

-- cycle_progress -------------------------------------------------------------
near(es.cycle_progress({ start = 10, speed = 2 }, 10), 0, "progress: at the swing -> 0")
near(es.cycle_progress({ start = 10, speed = 2 }, 11), 0.5, "progress: midpoint -> 0.5")
near(es.cycle_progress({ start = 10, speed = 2 }, 12), 1, "progress: at the expected next swing -> 1")
near(es.cycle_progress({ start = 10, speed = 2 }, 13), 1, "progress: past the end clamps to 1")
near(es.cycle_progress({ start = 10, speed = 2 }, 9), 0, "progress: before the swing clamps to 0")
eq(es.cycle_progress(nil, 10), nil, "progress: nil cycle -> nil")
eq(es.cycle_progress({ start = 10, speed = 0 }, 10), nil, "progress: zero speed -> nil")
eq(es.cycle_progress({ start = 10, speed = 2 }, nil), nil, "progress: nil clock -> nil")
eq(es.cycle_progress({ start = "x", speed = 2 }, 10), nil, "progress: non-number start -> nil")

-- cycle_remaining ------------------------------------------------------------
near(es.cycle_remaining({ start = 10, speed = 2 }, 11), 1, "remaining: mid-cycle -> 1")
near(es.cycle_remaining({ start = 10, speed = 2 }, 9), 3, "remaining: before the swing -> full + skew")
near(es.cycle_remaining({ start = 10, speed = 2 }, 13), 0, "remaining: past the end clamps to 0")
eq(es.cycle_remaining(nil, 10), nil, "remaining: nil cycle -> nil")
eq(es.cycle_remaining({ start = 10, speed = 2 }, nil), nil, "remaining: nil clock -> nil")
eq(es.cycle_remaining({ start = 10, speed = -1 }, 10), nil, "remaining: non-positive speed -> nil")

-- rescale_cycle --------------------------------------------------------------
local rescaled = es.rescale_cycle({ start = 10, speed = 2 }, 1, 11)
check(rescaled ~= nil, "rescale: valid inputs return a cycle")
near(rescaled.start, 10.5, "rescale: start keeps the remaining time proportional (10.5)")
near(rescaled.speed, 1, "rescale: speed is the new speed")
local unchanged = { start = 10, speed = 2 }
check(es.rescale_cycle(unchanged, 2.005, 11) == unchanged, "rescale: a change under 0.01s keeps the same table")
local expired = es.rescale_cycle({ start = 0, speed = 2 }, 4, 5)
near(expired.start, 1, "rescale: an expired cycle rescales from 0 remaining (start 1)")
near(expired.speed, 4, "rescale: expired cycle takes the new speed")
eq(es.rescale_cycle(nil, 1, 11), nil, "rescale: nil cycle -> nil")
eq(es.rescale_cycle({ start = 10, speed = 0 }, 1, 11), nil, "rescale: zero old speed -> nil")
eq(es.rescale_cycle({ start = 10, speed = 2 }, 0, 11), nil, "rescale: zero new speed -> nil")
eq(es.rescale_cycle({ start = 10, speed = 2 }, 1, nil), nil, "rescale: nil clock -> nil")

-- should_show ----------------------------------------------------------------
eq(es.should_show(true, "Enemy-1", true), true, "show: enabled + target + combat -> visible")
eq(es.should_show(false, "Enemy-1", true), false, "show: toggle off -> hidden")
eq(es.should_show(true, nil, true), false, "show: no target -> hidden")
eq(es.should_show(true, "", true), false, "show: empty GUID -> hidden")
eq(es.should_show(true, "Enemy-1", false), false, "show: out of combat -> hidden")
eq(es.should_show(true, "Enemy-1", nil), false, "show: unknown combat state -> hidden")
eq(es.should_show(1, "Enemy-1", true), false, "show: numeric 1 is not an enabled toggle")

-- feature_enabled ------------------------------------------------------------
eq(es.feature_enabled(nil), false, "toggle: nil addon -> off")
eq(es.feature_enabled({}), false, "toggle: no db -> off")
eq(es.feature_enabled({ db = {} }), false, "toggle: no profile -> off")
eq(es.feature_enabled({ db = { profile = {} } }), false, "toggle: missing key -> off")
eq(es.feature_enabled({ db = { profile = { enemy_swing_enabled = false } } }), false, "toggle: false -> off")
eq(es.feature_enabled({ db = { profile = { enemy_swing_enabled = 1 } } }), false, "toggle: 1 -> off")
eq(es.feature_enabled({ db = { profile = { enemy_swing_enabled = true } } }), true, "toggle: explicit true -> on")

--=========================================================================================
-- 2. Frame sandbox: instrumented stubs, classic family
--=========================================================================================

local function make_texture()
    local t = {}
    function t:SetPoint(...) t.point = { ... } end
    function t:SetAllPoints(target) t.all_points = target end
    function t:SetColorTexture(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetWidth(w) t.width = w end
    function t:SetTexCoord(...) t.texcoord = { ... } end
    function t:Show() t.shown = true end
    function t:Hide() t.shown = false end
    function t:IsShown() return t.shown ~= false end
    return t
end

local function make_fontstring()
    local fs = { text_sets = 0 }
    function fs:SetPoint(...) fs.point = { ... } end
    function fs:SetJustifyH(justify) fs.justify = justify end
    function fs:SetTextColor(...) fs.color = { ... } end
    function fs:SetShadowColor() end
    function fs:SetShadowOffset() end
    function fs:SetText(text) fs.text = text; fs.text_sets = fs.text_sets + 1 end
    function fs:Show() fs.shown = true end
    function fs:Hide() fs.shown = false end
    function fs:IsShown() return fs.shown ~= false end
    return fs
end

local function make_frame(name, parent)
    local f = {
        name = name, parent = parent, shown = false, frame_level = 1,
        events = {}, textures = {}, fontstrings = {}, scripts = {},
    }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetPoint(...) f.point = { ... } end
    function f:SetFrameLevel(level) f.frame_level = level end
    function f:GetFrameLevel() return f.frame_level end
    function f:CreateTexture() local t = make_texture(); table.insert(f.textures, t); return t end
    function f:CreateFontString()
        local fs = make_fontstring()
        table.insert(f.fontstrings, fs)
        return fs
    end
    function f:SetScript(event, fn) f.scripts[event] = fn end
    function f:GetScript(event) return f.scripts[event] end
    function f:RegisterEvent(event) table.insert(f.events, event) end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown end
    return f
end

-- One throwaway client per call. opts:
--   family         st.family (default "ERA")
--   probe          C_EventUtils.IsEventValid stub, or nil for no probe
--   with_frames    false to load without CreateFrame (default true)
--   get_bar_frame  override for the addon's bar-stack getter
--   with_addon     false to load without an addon object at all
local function make_client(opts)
    opts = opts or {}
    local c = {
        clock = 0, frames = {}, by_name = {},
        target_exists = false, target_attackable = false,
        target_guid = nil, target_name = nil,
        affecting_combat = false, payload = nil, target_speed = nil,
    }

    c.mh_bar = make_frame("SwedgeTimer_mainhand_TimerFrame", nil)
    c.mh_bar.frame_level = 5

    local env = setmetatable({}, { __index = _G })
    if opts.with_frames ~= false then
        env.CreateFrame = function(_, name, parent)
            local f = make_frame(name, parent)
            c.frames[#c.frames + 1] = f
            if name then c.by_name[name] = f end
            return f
        end
    end
    if opts.probe then
        env.C_EventUtils = { IsEventValid = opts.probe }
    end
    env.UnitExists = function(unit) return unit == "target" and c.target_exists == true or false end
    env.UnitCanAttack = function() return c.target_attackable == true end
    env.UnitGUID = function(unit)
        if unit == "target" then return c.target_guid end
        return "Player-1"
    end
    env.UnitName = function(unit)
        if unit == "target" then return c.target_name end
        return "Tester"
    end
    env.UnitAffectingCombat = function() return c.affecting_combat == true end

    c.api = {
        get_time = function() return c.clock end,
        UnitAttackSpeed = function(unit) c.speed_unit = unit; return c.target_speed end,
        CombatLogGetCurrentEventInfo = function()
            if c.payload then
                return unpack(c.payload, 1, c.payload.n or #c.payload)
            end
        end,
    }

    if opts.with_addon ~= false then
        c.addon = { db = { profile = {} } }
        c.addon.get_bar_frame = opts.get_bar_frame or function(_, hand)
            if hand == "mainhand" then return c.mh_bar end
            return nil
        end
    end
    if opts.with_libstub ~= false then
        env.LibStub = function(major)
            if major == "AceAddon-3.0" then
                return { GetAddon = function() return c.addon end }
            end
            return {}
        end
    end

    local st = { family = opts.family or "ERA", api = c.api }
    local chunk = assert(loadfile(ROOT .. "enemy_swing.lua"))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "SwedgeTimer", st)
    c.loaded, c.load_error = ok, err
    c.st, c.env, c.es = st, env, st.enemy_swing
    c.driver = c.by_name["SwedgeTimerEnemySwingDriver"]

    function c:fire(event, ...)
        if not c.driver or not c.driver.scripts.OnEvent then
            return nil
        end
        return c.driver.scripts.OnEvent(c.driver, event, ...)
    end
    function c:bar()
        return c.by_name["SwedgeTimerEnemySwingBar"]
    end
    function c:paint()
        local bar = c:bar()
        if bar and bar.scripts.OnUpdate then
            bar.scripts.OnUpdate(bar, 0.016)
        end
    end
    function c:enable() c.addon.db.profile.enemy_swing_enabled = true end
    function c:track(guid, name)
        c.target_exists, c.target_attackable = true, true
        c.target_guid, c.target_name = guid, name
    end
    function c:payload_for(subevent, source_guid, offhand_index, offhand, target_guid)
        local p = {
            n = 21, [1] = 100, [2] = subevent, [3] = false,
            [4] = source_guid, [8] = target_guid or "Player-1",
        }
        if offhand_index then p[offhand_index] = offhand end
        c.payload = p
    end
    return c
end

local c = make_client()
check(c.loaded, "classic sandbox: enemy_swing.lua loads (" .. tostring(c.load_error) .. ")")
eq(c.es.active, true, "classic sandbox: module active on ERA")
check(c.driver ~= nil, "classic sandbox: driver frame exists by name")
eq(#c.frames, 1, "classic sandbox: only the driver frame is built at load")
eq(table.concat(c.driver.events, ","),
    "PLAYER_ENTERING_WORLD,PLAYER_TARGET_CHANGED,UNIT_ATTACK_SPEED,"
    .. "PLAYER_REGEN_DISABLED,PLAYER_REGEN_ENABLED,COMBAT_LOG_EVENT_UNFILTERED",
    "classic sandbox: driver registers exactly the six events, in order")

-- off by default: nothing is built, nothing shows -----------------------------
c:track("Enemy-1", "Enemy One")
c:fire("PLAYER_TARGET_CHANGED")
eq(#c.frames, 1, "toggle off: no bar frame is built")
eq(c:bar(), nil, "toggle off: no bar frame exists")

-- enable + target + combat: the bar builds and shows ---------------------------
c:enable()
c:fire("PLAYER_TARGET_CHANGED")
local bar = c:bar()
check(bar ~= nil, "toggle on: the bar frame is built on the mainhand bar frame")
eq(bar.parent, c.mh_bar, "bar is parented to the mainhand bar frame (layout hook)")
eq(bar.point[1], "TOP", "bar anchors by its TOP")
eq(bar.point[2], c.mh_bar, "bar anchors relative to the mainhand bar frame")
eq(bar.point[3], "BOTTOM", "bar anchors to the bar frame's BOTTOM")
eq(bar.point[4], 0, "bar anchor x offset is 0")
eq(bar.point[5], -c.es.BAR_GAP, "bar anchor y offset is -BAR_GAP")
eq(bar.width, c.es.BAR_WIDTH, "bar width is BAR_WIDTH")
eq(bar.height, c.es.BAR_HEIGHT, "bar height is BAR_HEIGHT")
eq(bar.frame_level, c.mh_bar.frame_level + 2, "bar frame level is parent + 2")
eq(#bar.textures, 2, "bar has background and fill textures")
eq(#bar.fontstrings, 1, "bar has one text")
eq(bar.textures[2].color[1], 1, "fill is the reference red")
eq(bar.textures[2].color[2], 0, "fill green channel is 0")
eq(bar.textures[2].color[3], 0, "fill blue channel is 0")
eq(bar.scripts.OnUpdate, c.es.on_update, "bar OnUpdate is wired to the module's paint")
eq(bar.shown, false, "tracked but out of combat: the bar stays hidden")
eq(c.es.runtime.tracked_guid, "Enemy-1", "target GUID tracked")
eq(c.es.runtime.tracked_name, "Enemy One", "target name tracked")

c:fire("PLAYER_REGEN_DISABLED")
eq(c.es.runtime.in_combat, true, "regen disabled: in combat")
eq(bar.shown, true, "in combat with a tracked target: the bar shows")
c:paint()
eq(bar.text.text, "Enemy One", "no cycle yet: the text shows the target name")
eq(bar.textures[2].width, 1, "no cycle yet: the fill is the 1 px sliver")

-- CLEU attribution -------------------------------------------------------------
c:payload_for("SWING_DAMAGE", "Enemy-1", c.es.SWING_DAMAGE_OFFHAND_INDEX, false)
c.target_speed = 2.6
c:fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(c.speed_unit, "target", "swing start reads UnitAttackSpeed('target')")
eq(c.es.runtime.cycle.start, 0, "mainhand SWING_DAMAGE starts the cycle at the clock")
near(c.es.runtime.cycle.speed, 2.6, "cycle speed is the live reading")
c:paint()
eq(bar.text.text, "2.6", "full cycle: the text shows the remaining seconds")
eq(bar.textures[2].width, 1, "at the swing: the fill is the 1 px sliver")
eq(bar.textures[2].texcoord[2], 0, "at the swing: the texture coord is 0")

c.clock = 1.3
c:paint()
near(bar.textures[2].width, (c.es.BAR_WIDTH - 2) * 0.5, "mid-cycle: the fill is half the inner width")
near(bar.textures[2].texcoord[2], 0.5, "mid-cycle: the texture coord is 0.5")
eq(bar.text.text, "1.3", "mid-cycle: the text shows the remaining tenth")

-- off-hand hits never restart the cycle ----------------------------------------
c:payload_for("SWING_DAMAGE", "Enemy-1", c.es.SWING_DAMAGE_OFFHAND_INDEX, true)
c:fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(c.es.runtime.cycle.start, 0, "off-hand SWING_DAMAGE is ignored")

-- another unit's swing is ignored ----------------------------------------------
c:payload_for("SWING_DAMAGE", "Other-9", c.es.SWING_DAMAGE_OFFHAND_INDEX, false)
c:fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(c.es.runtime.cycle.start, 0, "a swing from another GUID is ignored")

-- a non-swing subevent from the target is ignored -------------------------------
c:payload_for("SPELL_DAMAGE", "Enemy-1", c.es.SWING_DAMAGE_OFFHAND_INDEX, false)
c:fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(c.es.runtime.cycle.start, 0, "a non-swing subevent is ignored")

-- SWING_MISSED mainhand restarts; its off-hand variant does not -----------------
c.clock = 2
c:payload_for("SWING_MISSED", "Enemy-1", c.es.SWING_MISSED_OFFHAND_INDEX, false)
c:fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(c.es.runtime.cycle.start, 2, "mainhand SWING_MISSED restarts the cycle")
c.clock = 3
c:payload_for("SWING_MISSED", "Enemy-1", c.es.SWING_MISSED_OFFHAND_INDEX, true)
c:fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(c.es.runtime.cycle.start, 2, "off-hand SWING_MISSED is ignored")

-- UNIT_ATTACK_SPEED rescales the remaining time --------------------------------
-- cycle { start = 2, speed = 2.6 }; now = 4 -> remaining 0.6, new speed 1.3
-- -> new remaining 0.3, start = 4 + 0.3 - 1.3 = 3.0
c.clock = 4
c.target_speed = 1.3
c:fire("UNIT_ATTACK_SPEED")
near(c.es.runtime.cycle.start, 3.0, "attack-speed change rescales the remaining time")
near(c.es.runtime.cycle.speed, 1.3, "attack-speed change takes the new speed")
local stable_cycle = c.es.runtime.cycle
c:fire("UNIT_ATTACK_SPEED")
check(c.es.runtime.cycle == stable_cycle, "an unchanged reading keeps the same cycle table")
c.target_speed = nil
c:fire("UNIT_ATTACK_SPEED")
check(c.es.runtime.cycle == stable_cycle, "a nil reading keeps the cycle")
c.target_speed = 1.3

-- target switching --------------------------------------------------------------
c.target_attackable = false
c:fire("PLAYER_TARGET_CHANGED")
eq(c.es.runtime.tracked_guid, nil, "a non-attackable target clears the tracked GUID")
eq(c.es.runtime.cycle, nil, "a target change drops the cycle")
eq(bar.shown, false, "a cleared target hides the bar")

c:track("Enemy-2", "Enemy Two")
c:fire("PLAYER_TARGET_CHANGED")
eq(c.es.runtime.tracked_guid, "Enemy-2", "the new hostile target is tracked")
eq(bar.shown, true, "still in combat: the bar shows for the new target")
c:paint()
eq(bar.text.text, "Enemy Two", "no cycle on the new target: the text shows its name")

-- UNIT_DIED clears the tracked target -------------------------------------------
c:payload_for("UNIT_DIED", nil, nil, nil, "Enemy-2")
c:fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(c.es.runtime.tracked_guid, nil, "UNIT_DIED clears the tracked target")
eq(bar.shown, false, "UNIT_DIED hides the bar")

-- combat exit clears and hides; re-entry shows again ----------------------------
c:track("Enemy-3", "Enemy Three")
c:fire("PLAYER_TARGET_CHANGED")
eq(bar.shown, true, "re-targeted in combat: shown")
c:fire("PLAYER_REGEN_ENABLED")
eq(c.es.runtime.in_combat, false, "regen enabled: out of combat")
eq(c.es.runtime.cycle, nil, "combat exit clears the cycle")
eq(bar.shown, false, "combat exit hides the bar")
c:fire("PLAYER_REGEN_DISABLED")
eq(bar.shown, true, "combat re-entry shows the bar again")

-- world entry resets state and re-reads the target/combat probe -----------------
c.affecting_combat = true
c:fire("PLAYER_ENTERING_WORLD")
eq(c.es.runtime.tracked_guid, "Enemy-3", "world entry re-tracks the live target")
eq(c.es.runtime.in_combat, true, "world entry adopts UnitAffectingCombat")
eq(bar.shown, true, "world entry with combat + target: shown")

-- a nil combat-log payload is ignored -------------------------------------------
c.payload = nil
check(pcall(function() c:fire("COMBAT_LOG_EVENT_UNFILTERED") end),
    "a nil combat-log payload does not throw")

-- an addon object that is not up yet degrades to hidden, never errors -----------
c.addon = nil
check(pcall(function() c:fire("PLAYER_TARGET_CHANGED") end),
    "no addon object: the target-change event does not throw")
eq(bar.shown, false, "no addon object: the bar hides")
c.addon = { db = { profile = { enemy_swing_enabled = true } } }
c.addon.get_bar_frame = function(_, hand)
    if hand == "mainhand" then return c.mh_bar end
    return nil
end

-- toggle off hides on the next event; the frame is never rebuilt ----------------
c:fire("PLAYER_TARGET_CHANGED")
eq(bar.shown, true, "toggle back on: the bar shows again")
c.addon.db.profile.enemy_swing_enabled = false
c:fire("PLAYER_TARGET_CHANGED")
eq(bar.shown, false, "toggle off: the next event hides the bar")
eq(#c.frames, 2, "the bar frame is built once and never rebuilt")

-- bars not up yet: the getter error is swallowed and retried ---------------------
local c2 = make_client({
    get_bar_frame = function() error("anchor_frame is nil") end,
})
check(c2.loaded, "late-bars sandbox: module loads")
c2:enable()
c2:track("Enemy-1", "Enemy One")
c2:fire("PLAYER_REGEN_DISABLED")
check(pcall(function() c2:fire("PLAYER_TARGET_CHANGED") end),
    "a bar-stack getter error does not throw")
eq(c2:bar(), nil, "no bar frame while the bar stack is not up")
c2.addon.get_bar_frame = function(_, hand)
    if hand == "mainhand" then return c2.mh_bar end
    return nil
end
c2:fire("PLAYER_TARGET_CHANGED")
check(c2:bar() ~= nil, "once the bar stack is up, the next event builds the bar")

-- 2b) M7: fallback-speed cycles render distinctly; a nil clock hides, never freezes ----
do
    local cf = make_client()
    cf:enable()
    cf:track("Enemy-1", "Enemy One")
    cf:fire("PLAYER_TARGET_CHANGED")
    cf:fire("PLAYER_REGEN_DISABLED")
    local es_bar = cf:bar()
    check(es_bar ~= nil, "M7 sandbox: the bar is built once armed")
    cf.target_speed = nil -- no live reading and no cached cycle: the 2.0 fallback
    cf:payload_for("SWING_DAMAGE", "Enemy-1", cf.es.SWING_DAMAGE_OFFHAND_INDEX, false)
    cf:fire("COMBAT_LOG_EVENT_UNFILTERED")
    local m7_cycle = cf.es.runtime.cycle
    check(m7_cycle ~= nil, "M7: a fallback cycle still arms")
    eq(m7_cycle.source, "fallback", "M7: an unmeasured cycle is marked fallback")
    near(m7_cycle.speed, cf.es.FALLBACK_SPEED, "M7: the fallback cycle uses 2.0")
    cf:paint()
    eq(es_bar.text.text, "Enemy One", "M7: a fallback cycle shows the target name, not a fake countdown")
    near(es_bar.textures[2].color[4], 0.35, "M7: the fallback fill is dimmed")
    eq(es_bar.textures[2].texcoord[2], 0, "M7: the fallback cycle still paints its progress")

    -- A live reading upgrades the cycle: full colour and the countdown return.
    cf.clock = 1.0
    cf.target_speed = 2.4
    cf:payload_for("SWING_DAMAGE", "Enemy-1", cf.es.SWING_DAMAGE_OFFHAND_INDEX, false)
    cf:fire("COMBAT_LOG_EVENT_UNFILTERED")
    m7_cycle = cf.es.runtime.cycle
    eq(m7_cycle.source, "live", "M7: a measured cycle is marked live")
    cf:paint()
    eq(es_bar.text.text, "2.4", "M7: a measured cycle shows the countdown again")
    near(es_bar.textures[2].color[4], 1.0, "M7: the measured fill is undimmed")
    near(es_bar.textures[2].color[1], 1.0, "M7: the measured fill is the reference red")

    -- A dead clock hides the bar instead of freezing the last paint.
    cf.clock = nil
    cf:paint()
    eq(es_bar.shown, false, "M7: a nil clock hides the bar")
    cf.clock = 2.0
    cf:fire("PLAYER_TARGET_CHANGED")
    eq(es_bar.shown, true, "M7: a returning clock plus an event shows the bar again")
end

--=========================================================================================
-- 3. Family matrix: classic families arm, Mainline-code families stay inert
--=========================================================================================
for _, family in ipairs({ "ERA", "TBC", "WRATH", "CATA", "MISTS" }) do
    local cf = make_client({ family = family })
    check(cf.loaded, family .. ": module loads (" .. tostring(cf.load_error) .. ")")
    eq(cf.es.active, true, family .. ": module active")
    check(cf.driver ~= nil, family .. ": driver frame created")
    eq(#cf.frames, 1, family .. ": only the driver frame exists at load")
    eq(#cf.driver.events, 6, family .. ": all six events registered")
end

for _, family in ipairs({ "FOREVER", "RETAIL", "UNKNOWN" }) do
    local cf = make_client({ family = family })
    check(cf.loaded, family .. ": module loads (" .. tostring(cf.load_error) .. ")")
    eq(cf.es.active, false, family .. ": module inactive (no classic combat log)")
    eq(#cf.frames, 0, family .. ": no frame is created")
    check(cf.driver == nil, family .. ": no driver frame exists")
end

do
    -- An approving event probe must not arm the module off-family: the family gate
    -- dominates (the Forever lesson).
    local cf = make_client({ family = "FOREVER", probe = function() return true end })
    check(cf.loaded, "forever probe-approving sandbox: module loads")
    eq(cf.es.active, false, "forever with an approving probe stays inactive")
    eq(#cf.frames, 0, "forever with an approving probe creates no frame")
end
do
    -- A rejecting probe on a classic family leaves the module inert as well.
    local cf = make_client({ family = "ERA", probe = function() return false end })
    check(cf.loaded, "era probe-rejecting sandbox: module loads")
    eq(cf.es.active, false, "era with a rejecting probe stays inactive")
    eq(#cf.frames, 0, "era with a rejecting probe creates no frame")
end
do
    -- No addon object / no LibStub at all: the module still loads and arms, but never
    -- touches the addon (every consumer degrades to hidden).
    local cf = make_client({ with_addon = false, with_libstub = false })
    check(cf.loaded, "addon-less sandbox: module loads (" .. tostring(cf.load_error) .. ")")
    eq(cf.es.active, true, "addon-less sandbox: the driver still arms on ERA")
    check(pcall(function() cf:fire("PLAYER_TARGET_CHANGED") end),
        "addon-less sandbox: events do not throw")
    eq(#cf.frames, 1, "addon-less sandbox: no bar frame is built")
end

--=========================================================================================
print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
