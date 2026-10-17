-- tests/shaman_state.lua: offline tests for the shaman weave module
-- (classes/shaman.lua) over the real compat.lua + weave.lua in a sandbox.
-- Pins the pre-init guards (a live crash regression), catalog resolution, Maelstrom
-- cast-time integration, the cast start/stop/delay lifecycle, the single-walk aura scan,
-- spark monotonicity across swing rollovers, talent invalidation and the combat-exit
-- reset.
-- The sandbox simulates a TBC client (WOW_PROJECT_ID 5): Maelstrom Weapon does not
-- exist there, so the breakpoint markers + spark stay hidden and the effective cast
-- time ignores MW stacks; Wrath behaviour is pinned by temporarily overriding
-- st.family to "WRATH" (the gate reads it live), with bars_state.lua pinning the
-- Wrath visuals end to end independently.
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
-- Float-tolerant compare (haste multipliers are products of 1.30 and 1.10, which do
-- not land exactly on the decimal literal).
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > tol then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

-- Sandbox environment --------------------------------------------------------------------
local clock = 0
local aura_list = {}
local aura_calls = 0
-- TARGET auras are served separately from the player's: the flame shock scan reads
-- "target" and must never be miscounted as a player-weave walk.
local target_aura_list = {}
local target_aura_calls = 0
-- Spell cooldown fixture for the Stormstrike / Shamanistic Rage badges. compat.lua reads
-- the classic GetSpellCooldown global at load, so this must exist before compat runs.
local cooldowns = {}
local casting_impl = function() return nil end
local channel_impl = function() return nil end

-- Air-slot totem fixture for the twist reconciliation: nil serves MayReturnNothing
-- (no totem / no client read), otherwise { have, name, start, duration, icon,
-- modrate, spell } unpacked like the client's GetTotemInfo.
local totem_slot4 = nil

-- Mutable known-spell fixture: the catalogue-invalidation test drops back to a lower
-- Lightning Bolt rank and then learns the higher one, which is what makes a resolved
-- catalogue entry stale.
local known_spells = { [25449] = true, [25442] = true }

-- Bar width the visuals frame reports; a texture's horizontal offset is read back as a
-- fraction of it, which is how the spark/marker positions are asserted below.
local BAR_WIDTH = 100

-- Texture stub recording what on_bar_update draws, so the widgets' positions and colors
-- can be inspected without a real frame.
local function make_texture()
    local t = { hidden = true }
    function t:SetDrawLayer() end
    function t:SetTexCoord() end
    function t:SetColorTexture(r, g, b, a) t.base_color = { r, g, b, a } end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetTexture(tex) t.texture = tex end
    function t:ClearAllPoints()
        t.point, t.anchor, t.rel_point, t.offset, t.offset_y = nil, nil, nil, nil, nil
    end
    function t:SetPoint(point, anchor, rel_point, x, y)
        t.point, t.anchor, t.rel_point, t.offset, t.offset_y = point, anchor, rel_point, x, y
    end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

-- Font string stub for the flame shock label and the cooldown badges.
local function make_fontstring()
    local f = { hidden = true }
    function f:SetPoint(point, anchor, rel_point, x, y)
        f.point, f.anchor, f.rel_point, f.offset, f.offset_y = point, anchor, rel_point, x, y
    end
    function f:SetJustifyH() end
    function f:SetFont(font_path, size, flags) f.font = { font_path, size, flags } end
    function f:SetText(text) f.text = text end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

-- Visuals frame: setup_weave_visuals builds the mainhand widgets on it in post_init. The
-- offhand frame is separate so the spark mirror's hand-specific anchoring is observable.
local visuals_frame = {}
function visuals_frame:CreateTexture() return make_texture() end
function visuals_frame:CreateFontString() return make_fontstring() end

local offhand_visuals_frame = {}
function offhand_visuals_frame:CreateTexture() return make_texture() end
function offhand_visuals_frame:CreateFontString() return make_fontstring() end

local env = {}
for k, v in pairs(_G) do env[k] = v end
env.WOW_PROJECT_ID = 5
env.WOW_PROJECT_CLASSIC = 2
env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
env.WOW_PROJECT_WRATH_CLASSIC = 11
env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
env.WOW_PROJECT_MISTS_CLASSIC = 19
env.WOW_PROJECT_MAINLINE = 1
env.WOW_PROJECT_FOREVER = 18
env.GetTime = function() return clock end
env.GetSpellInfo = function(id)
    if id == 25449 then return "Lightning Bolt", nil, "icon_lb", 2500, 0, 30, 25449 end
    if id == 25448 then return "Lightning Bolt", nil, "icon_lb", 2000, 0, 30, 25448 end
    if id == 25442 then return "Chain Lightning", nil, "icon_cl", 2000, 0, 30, 25442 end
    -- Fixture-only stand-in for an unconfirmed higher Windfury Totem rank: not in
    -- the addon's twist id table, so only the live-name resolution path stamps it.
    if id == 10613 then return "Windfury Totem", nil, "icon_wf", 0, 0, 0, 10613 end
    if id == 8512 then return "Windfury Totem", nil, "icon_wf", 0, 0, 0, 8512 end
    return nil
end
env.IsSpellKnown = function(id) return known_spells[id] == true end
env.UnitAura = function(unit, index, filter)
    -- Player walks (weave + trackers) and target scans are counted separately so a gate
    -- test can prove the target scan never runs while the flame shock option is off.
    local entry
    if unit == "target" then
        target_aura_calls = target_aura_calls + 1
        entry = target_aura_list[index]
    else
        aura_calls = aura_calls + 1
        entry = aura_list[index]
    end
    if not entry then return nil end
    return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
        entry.source, nil, nil, entry.spell_id
end
env.GetSpellCooldown = function(id)
    local cd = cooldowns[id]
    if cd then return cd.start, cd.duration, 1, 1 end
    return 0, 0, 1, 1
end
env.UnitCastingInfo = function() return casting_impl() end
env.UnitChannelInfo = function() return channel_impl() end
env.UnitSpellHaste = function() return 0 end
-- Secret-value probe: only the "SECRET" sentinel reads as restricted, so the
-- wrapper's whole-read degrade is pinnable without touching any other fixture.
env.issecretvalue = function(v) return v == "SECRET" end
env.GetTotemInfo = function(slot)
    if totem_slot4 == "THROW" then error("totem read failed") end
    if slot ~= 4 or totem_slot4 == nil then return nil end
    local t = totem_slot4
    return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
end
-- compat reads several legacy globals through _G (annotation-safe path); mirror every
-- sandbox stub for the duration of the loads below, then restore _G exactly. A
-- hardcoded name list goes stale the moment compat adds another _G read.
local mirrored_globals = {}
for name, value in pairs(env) do
    mirrored_globals[name] = rawget(_G, name)
    _G[name] = value
end

local st = {}
local class_db = { weave_mw_enabled = true }
local ST = { SHAMAN = {}, interfaces_are_initialised = false }
ST.get_class_table = function() return class_db end
ST.get_visuals_frame = function(_, hand)
    if hand == "offhand" then return offhand_visuals_frame end
    return visuals_frame
end
ST.get_bar_visuals_width_and_height = function() return BAR_WIDTH, 15 end

-- Scripted mainhand swing: a constant speed rolling over every `speed` seconds, exactly
-- like the swing engine advances d.start. on_bar_update reads d.start/d.ends_at live, so
-- stepping the clock through a rollover is what used to rewind the spark.
local function set_scripted_swing(t, speed)
    local start = math.floor((t / speed) + 1e-9) * speed
    ST.mainhand = { speed = speed, start = start, ends_at = start + speed, is_full = false }
end

-- The fraction of the bar at which a texture was last placed.
local function texture_fraction(t)
    if type(t.offset) ~= "number" then return nil end
    return t.offset / BAR_WIDTH
end

env.LibStub = function(major)
    if major == "AceAddon-3.0" then
        return { GetAddon = function() return ST end }
    end
    return {}
end

local compat = assert(loadfile(ROOT .. "compat.lua")); setfenv(compat, env); compat("SwedgeTimer", st)
local weave = assert(loadfile(ROOT .. "weave.lua")); setfenv(weave, env); weave("SwedgeTimer", st)
local shaman = assert(loadfile(ROOT .. "classes/shaman.lua")); setfenv(shaman, env); shaman("SwedgeTimer", st)
for name, previous in pairs(mirrored_globals) do
    _G[name] = previous
end
check(type(ST.SHAMAN.post_init) == "function", "classes/shaman.lua loads and defines its hooks")

-- 1) Pre-init safety: SUCCEEDED is dispatched without an init gate ----------------------
clock = 0
ST.interfaces_are_initialised = false
ST.weave_catalog = nil
local ok1, err1 = pcall(ST.SHAMAN.on_spellcast_succeeded, ST, "player", nil, 25449)
check(ok1, "pre-init SUCCEEDED does not error (" .. tostring(err1) .. ")")
local ok2, err2 = pcall(ST.SHAMAN.on_spellcast_succeeded, ST, "player", nil, 25449)
check(ok2, "repeated pre-init SUCCEEDED stays safe (" .. tostring(err2) .. ")")

-- With the init flag up but no catalog yet the nil guard must hold too.
ST.interfaces_are_initialised = true
local ok3, err3 = pcall(ST.SHAMAN.on_spellcast_succeeded, ST, "player", nil, 25449)
check(ok3, "SUCCEEDED with a nil catalog does not error (" .. tostring(err3) .. ")")
ST.interfaces_are_initialised = false

-- 2) post_init resolves the catalog ----------------------------------------------------
local ok4 = pcall(ST.SHAMAN.post_init, ST)
check(ok4, "post_init runs in the sandbox")
check(type(ST.weave_catalog) == "table", "post_init builds the weave catalog")
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.spell_id, 25449, "LB resolves to the highest known rank")
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.cast_seconds, 2.5, "LB cast time comes from GetSpellInfo")
eq(ST.weave_catalog.CL and ST.weave_catalog.CL.spell_id, 25442, "CL resolves to its known rank")
eq(ST.weave_catalog.HW, nil, "unknown families stay unresolved")

-- 3) Maelstrom Weapon stacks feed the effective cast time, gated per client ---------
-- The sandbox is a TBC client: Maelstrom Weapon does not exist there, so even five
-- stacks leave the full base cast time; the scan itself stays truthful.
eq(st.family, "TBC", "the sandbox simulates a TBC client")
eq(st.weave.has_maelstrom_weapon(st.family), false, "TBC has no Maelstrom Weapon")
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 5, "the scan stays truthful: five stacks are still read")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: no MW reduction despite the stacks")
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: the option-off path is the same base cast time")
class_db.weave_mw_enabled = true
-- A Wrath client keeps the exact historical behaviour (the option stays the
-- kill-switch where MW exists).
st.family = "WRATH"
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "Wrath: five stacks make the cast instant")
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "Wrath: MW can be disabled by option")
class_db.weave_mw_enabled = true
st.family = "TBC"
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 0, "no aura means zero stacks")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "base cast time without stacks")

-- 4) Cast lifecycle: start -> delayed -> stop ------------------------------------------
ST.interfaces_are_initialised = true
clock = 1.0
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 1000, 3500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-1", 25449)
eq(ST.weave_is_casting, true, "START begins the cast state")
eq(ST.weave_family, "LB", "START resolves the family from the spell id")
eq(ST.weave_cast_start_time, 1.0, "cast start comes from the client window")
eq(ST.weave_cast_end_time, 3.5, "cast end comes from the client window")
eq(ST.weave_cast_duration, 2.5, "cast duration is the live window length")

casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 1000, 4200, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_DELAYED", "player", "cast-1", 25449)
eq(ST.weave_cast_start_time, 1.0, "DELAYED keeps the original start anchor")
eq(ST.weave_cast_end_time, 4.2, "DELAYED re-anchors the end from the live window")
eq(ST.weave_cast_duration, 3.2, "DELAYED duration follows the live window")

ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-1")
eq(ST.weave_is_casting, false, "STOP ends the cast state")
eq(ST.weave_cast_end_time, nil, "STOP clears the end anchor")

-- SUCCEEDED keeps the last family and ends the cast.
clock = 2.0
casting_impl = function() return nil end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-2", 25449)
eq(ST.weave_is_casting, true, "second START begins a new cast")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-2", 25449)
eq(ST.weave_is_casting, false, "SUCCEEDED ends the cast state")
eq(ST.weave_family, "LB", "SUCCEEDED keeps the last family for the marker")

-- 5) The init gate on the lifecycle hook ------------------------------------------------
ST.interfaces_are_initialised = false
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-3", 25449)
eq(ST.weave_is_casting, false, "spellcast events are ignored before init")
ST.interfaces_are_initialised = true

-- 6) Family toggles pick the first enabled family ---------------------------------------
class_db.weave_families = { LB = false, CL = true, HW = true, LHW = true, CH = true }
ST.weave_family = "LB"
local entry, family = ST.SHAMAN.get_weave_visual_spell(ST)
eq(family, "CL", "a disabled family falls through to the next enabled one")
eq(entry and entry.spell_id, 25442, "the fallback family's entry is returned")
class_db.weave_families = nil

-- 7) One aura walk feeds both weave inputs ----------------------------------------------
-- scan_weave_auras must serve BOTH the haste buffs and the Maelstrom stacks, so a change
-- of auras costs one UnitAura walk. The fixture keeps a neutral aura last and omits
-- Berserking, so the walk cannot early-exit: exactly one read per aura plus the
-- terminating nil read (4 auras + terminator = 5 calls).
aura_list = {
    { name = "Maelstrom Weapon", count = 3, spell_id = 408505 },
    { name = "Whirlwind" },
    { name = "Bloodlust", spell_id = 2825 },
    { name = "Lightning Shield" },
}
aura_calls = 0
ST.SHAMAN.on_aura_change(ST)
eq(aura_calls, 5, "one on_aura_change walks the auras once (4 auras + terminator)")
eq(ST.weave_mw_stacks, 3, "the single walk carries the Maelstrom stack count")
near(ST.weave_haste_mult, 1.30, 1e-9, "the single walk carries the Bloodlust haste multiplier")

-- Standalone fallback: refresh_weave_mw_stacks with no stacks argument walks on its own
-- and lands on the same count.
aura_calls = 0
ST.SHAMAN.refresh_weave_mw_stacks(ST)
check(aura_calls > 0, "standalone stack refresh performs its own aura walk")
eq(ST.weave_mw_stacks, 3, "standalone stack refresh yields the same count")

-- 8) Spark monotonicity across a swing rollover -----------------------------------------
-- Runs as a Wrath client (the spark only draws where Maelstrom exists); the TBC
-- pin follows at the end of the section.
-- A 3s cast begun 0.5s into a 2s swing (rollover at t=2) must never move the spark
-- backwards: the projection is anchored to the swing the cast started in
-- (weave_cast_swing_start), not to whatever swing is current mid-cast.
st.family = "WRATH"
ST.interfaces_are_initialised = true
clock = 0.5
set_scripted_swing(clock, 2.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 500, 3500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-spark", 25449)
eq(ST.weave_cast_swing_start, 0, "cast start captures the swing anchor")
near(ST.weave_cast_start_swing_fraction, 0.25, 1e-9, "cast start fraction is measured against the captured swing")

local spark_fractions = {}
for i = 0, 30 do
    clock = 0.5 + i * 0.1
    set_scripted_swing(clock, 2.0)
    ST.SHAMAN.on_bar_update(ST, "mainhand")
    spark_fractions[#spark_fractions + 1] = texture_fraction(visuals_frame.weave_spark)
end
local monotonic = true
for i = 2, #spark_fractions do
    if spark_fractions[i] < spark_fractions[i - 1] - 1e-9 then
        monotonic = false
    end
end
check(monotonic, "spark fraction never moves backwards across the swing rollover")
near(spark_fractions[#spark_fractions], 1.0, 1e-6, "spark lands at ~1.0 by the end of the cast")
eq(ST.weave_cast_swing_start, 0, "the captured swing anchor survives the rollover")

-- end_weave_cast clears both anchors.
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-spark")
eq(ST.weave_is_casting, false, "STOP after the rollover ends the cast")
eq(ST.weave_cast_swing_start, nil, "end_weave_cast clears the swing anchor")
eq(ST.weave_cast_start_swing_fraction, nil, "end_weave_cast clears the cast start fraction")

-- Back on TBC the same cast draws nothing: tracking still runs (the family gate is
-- visuals-only), but no marker or spark may teach hard-cast weaving.
st.family = "TBC"
clock = 10.5
set_scripted_swing(clock, 2.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 10500, 13500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-tbc", 25449)
eq(ST.weave_is_casting, true, "TBC: cast tracking still runs without Maelstrom")
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "TBC: the marker stays hidden on an active swing")
check(visuals_frame.weave_spark.hidden, "TBC: the spark stays hidden during the cast")
check(visuals_frame.weave_marker_top.hidden, "TBC: the top marker stays hidden")
check(visuals_frame.weave_marker_bottom.hidden, "TBC: the bottom marker stays hidden")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-tbc")

-- 9) Combat exit ends an in-flight cast but keeps the resolved family ---------------------
-- A wipe fires no STOP, so the cast state would stay live forever; on_combat_exit must
-- clear it while weave_family (and with it the marker's breakpoint) survives.
ST.interfaces_are_initialised = true
clock = 5.0
set_scripted_swing(clock, 2.0)
casting_impl = function()
    return "Chain Lightning", "Chain Lightning", "icon_cl", 5000, 8000, false, 1, false, 25442
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-wipe", 25442)
eq(ST.weave_is_casting, true, "wipe scenario: the cast is in flight")
eq(ST.weave_family, "CL", "wipe scenario: the cast resolved its family")

local ok5 = pcall(ST.SHAMAN.on_combat_exit, ST)
check(ok5, "on_combat_exit does not error")
eq(ST.weave_is_casting, false, "combat exit ends the in-flight cast")
eq(ST.weave_cast_start_time, nil, "combat exit clears the cast start anchor")
eq(ST.weave_cast_end_time, nil, "combat exit clears the cast end anchor")
eq(ST.weave_cast_swing_start, nil, "combat exit clears the swing anchor")
eq(ST.weave_cast_start_swing_fraction, nil, "combat exit clears the start fraction")
eq(ST.weave_cast_duration, nil, "combat exit clears the cast duration")
eq(ST.weave_family, "CL", "combat exit keeps the last resolved family")

-- The kept family still resolves (the marker itself stays hidden on TBC: no Maelstrom
-- here; the Wrath draw is pinned in section 17).
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "TBC: the marker stays hidden after a combat exit")
eq(visuals_frame.weave_spark.hidden, true, "the spark is hidden after a combat exit")

-- Pre-init + no visuals: the reset must not error (nothing here reads the frame).
clock = 6.0
set_scripted_swing(clock, 2.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 6000, 9000, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-wipe-preinit", 25449)
local saved_frame_getter = ST.get_visuals_frame
local saved_marker, saved_spark = visuals_frame.weave_marker, visuals_frame.weave_spark
ST.get_visuals_frame = function() return nil end
visuals_frame.weave_marker, visuals_frame.weave_spark = nil, nil
ST.interfaces_are_initialised = false
local ok6, err6 = pcall(ST.SHAMAN.on_combat_exit, ST)
check(ok6, "pre-init on_combat_exit with no visuals does not error (" .. tostring(err6) .. ")")
eq(ST.weave_is_casting, false, "pre-init combat exit still clears the cast state")
visuals_frame.weave_marker, visuals_frame.weave_spark = saved_marker, saved_spark
ST.get_visuals_frame = saved_frame_getter
ST.interfaces_are_initialised = true

-- 10) Effective cast time with Maelstrom and haste ----------------------------------------
-- TBC first: the hasted base cast time applies, Maelstrom never reduces it here.
aura_list = {
    { name = "Maelstrom Weapon", count = 5, spell_id = 408505 },
    { name = "Bloodlust", spell_id = 2825 },
}
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_mw_stacks, 5, "five Maelstrom stacks are read by the merged scan")
near(ST.weave_haste_mult, 1.30, 1e-9, "Bloodlust sets the haste multiplier")
near(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5 / 1.30, 1e-9, "TBC: the hasted base cast time, no MW reduction")
class_db.weave_mw_enabled = false
near(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5 / 1.30, 1e-9, "TBC: option-off is the same hasted base cast time")
class_db.weave_mw_enabled = true
-- Wrath keeps the exact historical behaviour: five stacks stay instant under haste,
-- and disabling MW applies the hasted base cast time.
st.family = "WRATH"
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "Wrath: five stacks stay instant under haste")
class_db.weave_mw_enabled = false
near(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5 / 1.30, 1e-9, "Wrath: MW disabled applies the hasted base cast time")
class_db.weave_mw_enabled = true
st.family = "TBC"

-- Without haste, the TBC path is exactly the base cast time either way.
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_haste_mult, 1.0, 1e-9, "no buff restores the neutral haste multiplier")
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: option-off returns the base cast time")
class_db.weave_mw_enabled = true
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: five stacks still return the base cast time")
st.family = "WRATH"
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "Wrath: five stacks return 0 with MW enabled")
st.family = "TBC"
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 0, "aura fixture reset to no stacks")

-- 11) Talent changes invalidate the resolved catalogue -------------------------------------
-- resolve_weave_catalog only fills MISSING families, so a rank learned after post_init
-- must be picked up by dropping the stale entry in on_talents_changed first.
known_spells[25449] = nil              -- only the low Lightning Bolt rank is known now
known_spells[25448] = true
ST.weave_catalog.LB = nil
ST.SHAMAN.resolve_weave_catalog(ST)
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.spell_id, 25448, "the low rank resolves first")
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.cast_seconds, 2.0, "the low rank carries its own cast time")

-- A failed family's retry stamp is dropped too (a level-up must retry immediately, not
-- after the throttle window).
ST.weave_catalog_retry_at.HW = clock + 1000
known_spells[25449] = true             -- the higher rank is learned
ST.SHAMAN.on_talents_changed(ST)
eq(ST.weave_catalog.LB, nil, "on_talents_changed drops the resolved catalogue")
eq(ST.weave_catalog_retry_at.HW, nil, "on_talents_changed drops the retry stamps")

ST.SHAMAN.resolve_weave_catalog(ST)
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.spell_id, 25449, "re-resolution picks up the learned higher rank")
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.cast_seconds, 2.5, "the higher rank's cast time is re-read")
eq(ST.weave_catalog.CL and ST.weave_catalog.CL.spell_id, 25442, "other families re-resolve unchanged")
known_spells[25448] = nil              -- fixture restored: 25449 is the highest known rank

-- 12) Tracker option gates: all five off -> nothing drawn, no scans -----------------------
-- The gate contract for every new visual: an off option keeps the widgets hidden AND the
-- per-frame path performs no additional aura work (the flame shock target scan is the
-- only UnitAura read reachable from on_bar_update).
ST.interfaces_are_initialised = true
clock = 50
set_scripted_swing(clock, 2.0)
aura_list = {
    { name = "Windfury Weapon" },
    { name = "Lightning Shield", count = 3 },
    { name = "Shamanistic Rage", expiration = clock + 10 },
}
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_windfury_active, true, "windfury fixture resolves through the merged scan")
eq(ST.weave_shield_type, "lightning", "shield fixture resolves through the merged scan")
eq(ST.weave_shield_charges, 3, "shield charge count is read from the aura")
near(ST.weave_sr_expires, clock + 10, 1e-9, "shamanistic rage expiry is read from the aura")

target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "player", duration = 12, expiration = clock + 8 },
}
cooldowns[17364] = { start = clock, duration = 8 }
cooldowns[30823] = { start = clock, duration = 60 }

local new_option_keys = {
    "show_shaman_breakpoint_markers", "show_shaman_windfury_icd",
    "show_shaman_flame_shock_bar", "show_shaman_cooldown_badges",
    "show_shaman_shield_charges",
}
local saved_options = {}
for i = 1, #new_option_keys do
    saved_options[i] = class_db[new_option_keys[i]]
    class_db[new_option_keys[i]] = false
end
target_aura_calls = 0
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(target_aura_calls, 0, "all tracker options off: on_bar_update performs no target scans")
check(visuals_frame.weave_windfury_bg.hidden, "windfury strip hidden when off")
check(visuals_frame.weave_windfury_fill.hidden, "windfury fill hidden when off")
check(visuals_frame.weave_fs_bg.hidden, "flame shock bar hidden when off")
check(visuals_frame.weave_fs_fill.hidden, "flame shock fill hidden when off")
check(visuals_frame.weave_fs_glow.hidden, "flame shock glow hidden when off")
check(visuals_frame.weave_fs_label.hidden, "flame shock label hidden when off")
check(visuals_frame.weave_ss_text.hidden, "SS badge hidden when off")
check(visuals_frame.weave_sr_text.hidden, "SR badge hidden when off")
check(visuals_frame.weave_marker_top.hidden, "top breakpoint marker hidden when off")
check(visuals_frame.weave_marker_bottom.hidden, "bottom breakpoint marker hidden when off")
local gated_rects = visuals_frame.weave_shield_rects
check(gated_rects[1].hidden and gated_rects[2].hidden and gated_rects[3].hidden and gated_rects[4].hidden,
    "shield rects hidden when off")
check(visuals_frame.weave_marker.hidden, "TBC: the main marker stays hidden with the trackers off")
for i = 1, #new_option_keys do
    class_db[new_option_keys[i]] = saved_options[i]
end
-- The same tick as a Wrath client draws the marker: the gate is the family, not the
-- options above.
st.family = "WRATH"
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden == false, "Wrath: the same tick draws the main marker")
st.family = "TBC"

-- 13) Windfury ICD strip buckets ----------------------------------------------------------
-- d.start is the current swing's start, i.e. the previous swing's landing time, which is
-- exactly the reference's lastSwing stamp, so the strip counts from the last swing.
clock = 50
set_scripted_swing(clock, 2.0)
aura_list = { { name = "Windfury Weapon" } }
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_windfury_bg.hidden, "windfury strip shows while the buff is up")
eq(visuals_frame.weave_windfury_fill.color[2], 0, "just procced reads red")
near(visuals_frame.weave_windfury_fill.width, 3, 1e-9, "full ICD fills the strip")
clock = 50.5
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(visuals_frame.weave_windfury_fill.width, 2.5, 1e-9, "fill width tracks the remaining ICD")
eq(visuals_frame.weave_windfury_fill.color[2], 0, "above 2s stays red")
clock = 52.0
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(visuals_frame.weave_windfury_fill.color[2], 0.65, 1e-9, "between 0.5s and 2s reads orange")
clock = 52.6
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_windfury_fill.color[2], 1, "below 0.5s reads green")
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
clock = 53
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_windfury_bg.hidden, "strip hides when Windfury drops")
aura_list = { { name = "Windfury (localized)", spell_id = 8232 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_windfury_active, true, "windfury also resolves by spell id")

-- 14) Flame Shock target bar ---------------------------------------------------------------
clock = 60
set_scripted_swing(clock, 2.0)
target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "player", duration = 12, expiration = 68 },
}
target_aura_calls = 0
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_fs_bg.hidden, "flame shock bar shows for the player's debuff")
near(visuals_frame.weave_fs_fill.width, BAR_WIDTH * (8 / 12), 1e-6, "fill fraction is remaining/total")
eq(visuals_frame.weave_fs_label.text, "8", "the seconds label counts down")
check(visuals_frame.weave_fs_glow.hidden, "no glow above the final 4 seconds")
eq(target_aura_calls, 1, "the scan stops at the matched target aura")
local fs_scan_calls = target_aura_calls
clock = 60.01
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(target_aura_calls, fs_scan_calls, "the target scan is throttled to 0.05 s")

clock = 65
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_fs_glow.hidden, "glow shows inside the final 4 seconds")
eq(visuals_frame.weave_fs_label.text, "3", "the label keeps counting down")

-- Another caster's Flame Shock does not qualify.
clock = 70
target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "other", duration = 12, expiration = clock + 8 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_fs_bg.hidden, "a debuff from another caster does not show the bar")

-- An unknown (localized) name still matches through the id table.
clock = 71
target_aura_list = {
    { name = "Flame Shock (localized)", spell_id = 8050, source = "player", duration = 12, expiration = clock + 8 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_fs_bg.hidden, "the id table matches when the name differs")

-- No debuff -> hidden, glow cache reset.
target_aura_list = {}
clock = 72
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_fs_bg.hidden, "bar hides when the debuff is gone")
check(visuals_frame.weave_fs_glow.hidden, "glow hides when the debuff is gone")

-- 15) Stormstrike / Shamanistic Rage badges ------------------------------------------------
clock = 80
aura_list = {}
ST.SHAMAN.on_aura_change(ST)                        -- no SR aura up
cooldowns[17364] = { start = 78, duration = 8 }     -- 6s left
cooldowns[30823] = { start = 79, duration = 60 }    -- 59s left
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_ss_text.text, "SS 6s", "SS badge shows the Stormstrike cooldown")
eq(visuals_frame.weave_sr_text.text, "SR 59s", "SR badge falls back to the cooldown")
check(not visuals_frame.weave_ss_text.hidden, "SS badge shows while on cooldown")
check(not visuals_frame.weave_sr_text.hidden, "SR badge shows while on cooldown")

-- The SR aura wins over the cooldown while it is up.
clock = 90
aura_list = { { name = "Shamanistic Rage", expiration = 95 } }
ST.SHAMAN.on_aura_change(ST)
cooldowns[30823] = { start = 85, duration = 60 }    -- would read 55s if the cooldown won
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_sr_text.text, "SR 5s", "the SR aura reading wins over the cooldown")

-- Both ready -> hidden.
clock = 100
cooldowns[17364] = nil
cooldowns[30823] = nil
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_ss_text.hidden, "SS badge hides when off cooldown")
check(visuals_frame.weave_sr_text.hidden, "SR badge hides when ready and down")

-- 16) Shield charge row ---------------------------------------------------------------------
-- Lightning Shield: 4 slots, the aura count fills them, the rest stay dimmed.
aura_list = { { name = "Lightning Shield", count = 2 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_shield_type, "lightning", "lightning shield detected by name")
eq(ST.weave_shield_charges, 2, "charge count read from the aura")
ST.SHAMAN.on_bar_update(ST, "mainhand")
local rects = visuals_frame.weave_shield_rects
near(rects[1].color[4], 0.9, 1e-9, "first Lightning Shield charge filled")
near(rects[2].color[4], 0.9, 1e-9, "second Lightning Shield charge filled")
near(rects[3].color[4], 0.2, 1e-9, "third Lightning Shield charge dimmed")
near(rects[4].color[4], 0.2, 1e-9, "fourth Lightning Shield charge dimmed")
check(not rects[4].hidden, "empty Lightning Shield slots stay visible (dimmed)")
eq(rects[1].anchor, visuals_frame, "the row anchors to the mainhand visuals frame")
eq(rects[1].offset, -6, "the row sits one gap left of the bar")
eq(rects[2].anchor, rects[1], "the row grows leftward, rect by rect")
eq(rects[1].height, 15, "rects span the bar height")

-- Water Shield: 3 slots; the fourth rect hides.
aura_list = { { name = "Water Shield", count = 1 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_shield_type, "water", "water shield detected by name")
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(rects[1].color[4], 0.9, 1e-9, "the filled Water Shield charge")
near(rects[2].color[4], 0.2, 1e-9, "second Water Shield charge dimmed")
near(rects[3].color[4], 0.2, 1e-9, "third Water Shield charge dimmed")
check(rects[4].hidden, "the fourth rect hides for the 3-slot Water Shield row")

-- A localized name still matches through the id table.
aura_list = { { name = "Water Shield (localized)", spell_id = 52127, count = 3 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_shield_type, "water", "shield detection falls back to the id table")

-- An unreadable count reads as the full row (reference fallback).
aura_list = { { name = "Lightning Shield" } }
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(ST.weave_shield_charges, nil, "a shield aura without a count stores no count")
near(rects[4].color[4], 0.9, 1e-9, "an unreadable charge count reads as full")

-- 17) Breakpoint markers and the offhand spark mirror ---------------------------------------
-- Runs as a Wrath client (the markers only draw where Maelstrom exists); the TBC pin
-- closes the section.
st.family = "WRATH"
-- A 4s swing with the 2.5s Lightning Bolt cast puts the marker at fraction 0.375.
aura_list = {}
ST.SHAMAN.on_aura_change(ST)        -- no MW stacks / haste
ST.weave_family = "LB"
clock = 113
set_scripted_swing(clock, 4.0)      -- swing starts at 112 (floor(113/4)*4)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 112000, 114500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-markers", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(visuals_frame.weave_marker.offset, 0.375 * BAR_WIDTH, 1e-6, "the main marker sits at the cutoff")
check(not visuals_frame.weave_marker_top.hidden, "top marker shows")
eq(visuals_frame.weave_marker_top.point, "BOTTOM", "top marker hangs from its bottom edge")
eq(visuals_frame.weave_marker_top.rel_point, "TOPLEFT", "top marker anchors above the bar")
near(visuals_frame.weave_marker_top.offset, 0.375 * BAR_WIDTH, 1e-6, "top marker anchored at the marker fraction")
near(visuals_frame.weave_marker_top.offset_y, 2, 1e-9, "top marker sits a gap above the bar")
check(not visuals_frame.weave_marker_bottom.hidden, "bottom marker shows")
near(visuals_frame.weave_marker_bottom.offset, 0.375 * BAR_WIDTH, 1e-6, "bottom marker anchored at the marker fraction")
eq(visuals_frame.weave_marker_bottom.anchor, visuals_frame, "single wield: bottom marker under the mainhand bar")
near(visuals_frame.weave_spark.offset, 25, 1e-6, "the spark travels from the cast start toward its landing")

ST.SHAMAN.on_bar_update(ST, "offhand")
local oh_spark = offhand_visuals_frame.weave_spark_offhand
check(oh_spark ~= nil, "the offhand spark widget exists")
check(oh_spark.hidden, "no offhand spark without an offhand weapon")

ST.offhand = { has_weapon = true, anchor_frame = { bar_frame = { IsShown = function() return true end } } }
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_marker_bottom.anchor, offhand_visuals_frame,
    "dual wield: the bottom marker drops below the offhand bar")
ST.SHAMAN.on_bar_update(ST, "offhand")
check(not oh_spark.hidden, "the offhand spark mirror shows while casting")
near(oh_spark.offset, visuals_frame.weave_spark.offset, 1e-6,
    "the mirror sits at the same fraction as the mainhand spark")
near(oh_spark.color[2], visuals_frame.weave_spark.color[2], 1e-9, "the mirror shares the mainhand tint")

-- The marker option gates the pair and the mirror.
class_db.show_shaman_breakpoint_markers = false
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker_top.hidden and visuals_frame.weave_marker_bottom.hidden,
    "off: the marker pair hides")
check(visuals_frame.weave_marker.hidden == false, "off: the main marker keeps drawing")
ST.SHAMAN.on_bar_update(ST, "offhand")
check(oh_spark.hidden, "off: the spark mirror hides")
class_db.show_shaman_breakpoint_markers = nil
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-markers")

-- Back on TBC an active swing with a cast in flight draws neither marker nor spark.
st.family = "TBC"
clock = 200
set_scripted_swing(clock, 4.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 200000, 202500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-tbc-markers", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "TBC: no main marker on an active swing")
check(visuals_frame.weave_spark.hidden, "TBC: no spark during the cast")
ST.SHAMAN.on_bar_update(ST, "offhand")
check(offhand_visuals_frame.weave_spark_offhand.hidden, "TBC: no offhand mirror during the cast")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-tbc-markers")

-- 19) Aura-observed MW enablement (SoD shares the ERA token) -------------------------
-- SoD HAS the MW rune (408505) while Era-base has nothing: the first observed
-- aura/stack signal latches weave_mw_observed and re-enables the markers and the
-- MW cast-time reduction; Era-base (never observed) stays off; TBC stays off even
-- when observed; the weave_mw_enabled option stays the kill-switch everywhere.
st.family = "ERA"
ST.weave_mw_observed = false
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 0, "SoD setup: no aura means zero stacks")
eq(ST.weave_mw_observed, false, "SoD setup: an empty scan never latches observed")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "Era-base: never observed stays at the base cast time")

-- Era-base draws nothing on an active swing.
clock = 300
set_scripted_swing(clock, 4.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 300000, 302500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-era-base", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "Era-base: no main marker without an observed MW aura")
check(visuals_frame.weave_spark.hidden, "Era-base: no spark without an observed MW aura")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-era-base")

-- The first observed aura latches; a later empty scan clears stacks, not the latch.
aura_list = { { name = "Maelstrom Weapon", count = 3, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 3, "SoD: the rune aura stacks are read")
eq(ST.weave_mw_observed, true, "SoD: the first observed aura latches enablement")
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 0, "SoD: a dropped aura reads zero stacks")
eq(ST.weave_mw_observed, true, "SoD: the latch survives a dropped aura (zero stacks is not absence of MW)")

-- Observed stacks reduce the cast time (3 stacks -> 2.5 * 0.4 = 1.0; 5 -> instant).
aura_list = { { name = "Maelstrom Weapon", count = 3, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
near(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 1.0, 1e-9, "SoD: three observed stacks reduce the cast time")
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "SoD: five observed stacks make the cast instant")

-- Observed markers draw on an active swing (no stacks: 2.5s cast on a 4s swing).
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_observed, true, "SoD: the latch holds with no live aura")
clock = 313
set_scripted_swing(clock, 4.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 312000, 314500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-sod", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden == false, "SoD: the marker draws once MW is observed")
near(visuals_frame.weave_marker.offset, 0.375 * BAR_WIDTH, 1e-6, "SoD: the marker sits at the cutoff")
check(visuals_frame.weave_spark.hidden == false, "SoD: the spark draws once MW is observed")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-sod")

-- The option stays the kill-switch even when observed.
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "SoD: option-off returns the base cast time despite the latch")
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "SoD: option-off hides the marker despite the latch")
class_db.weave_mw_enabled = true

-- TBC stays off even with the latch set (no MW there).
st.family = "TBC"
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: five stacks still return the base cast time with the latch set")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-tbc-latch", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "TBC: no main marker even with the latch set")
check(visuals_frame.weave_spark.hidden, "TBC: no spark even with the latch set")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-tbc-latch")

-- Fixture restored: TBC client, option on, no live aura, latch cleared.
st.family = "TBC"
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
ST.weave_mw_observed = false
casting_impl = function() return nil end

-- 20) Totem-twist live stamp: SUCCEEDED commits + air-slot reconciliation -------------
-- post_init starts the stamp unknown; Windfury (id, live spell name, name token)
-- and Grace of Air (name token, air-slot totemName) SUCCEEDED commits stamp it;
-- weave casts and unknown spells do not; the pre-init gate holds; the air-slot poll
-- adopts a twist totem's startTime when the stamp is unknown or older, ignores
-- non-twist totems / absent reads / bad stamps, and never rewinds a fresher commit.
ST.SHAMAN.post_init(ST)
eq(ST.weave_twist_last_drop, nil, "post_init starts the twist stamp unknown")
eq(ST.weave_magma_last_drop, nil, "post_init starts the magma stamp unknown")
ST.interfaces_are_initialised = true
local fam_before_twist = ST.weave_family

clock = 500
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-1", 8512)
eq(ST.weave_twist_last_drop, 500, "Windfury by id stamps the drop time")
eq(ST.weave_family, fam_before_twist, "a twist commit never resolves a weave family")

clock = 501
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-lb", 25449)
eq(ST.weave_twist_last_drop, 500, "a weave cast does not move the twist stamp")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-unknown", 99999)
eq(ST.weave_twist_last_drop, 500, "an unknown spell does not move the twist stamp")

clock = 502
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "Grace of Air Totem", 99999)
eq(ST.weave_twist_last_drop, 502, "Grace of Air by name token stamps the drop time")

clock = 503
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-2", 10613)
eq(ST.weave_twist_last_drop, 503, "an unconfirmed WF rank stamps through its live spell name")

clock = 504
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-nil", nil)
eq(ST.weave_twist_last_drop, 503, "a nil spell id neither stamps nor errors")

-- Magma maintain commits: the unconfirmed rank-1 id, the name token and the live
-- spell name all stamp; weave casts, twist drops and unknown spells do not move
-- the magma stamp (and magma commits never resolve a weave family).
clock = 510
local fam_before_magma = ST.weave_family
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-magma-1", 8190)
eq(ST.weave_magma_last_drop, 510, "Magma by id stamps the drop time")
eq(ST.weave_family, fam_before_magma, "a magma commit never resolves a weave family")
eq(ST.weave_twist_last_drop, 503, "a magma commit never moves the twist stamp")
clock = 511
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "Magma Totem", 99999)
eq(ST.weave_magma_last_drop, 511, "Magma by name token stamps the drop time")
clock = 512
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-lb-magma", 25449)
eq(ST.weave_magma_last_drop, 511, "a weave cast does not move the magma stamp")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-twist-magma", 8512)
eq(ST.weave_magma_last_drop, 511, "a twist drop does not move the magma stamp")
eq(ST.weave_twist_last_drop, 512, "the twist drop still stamps its own clock")
clock = 513
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-nil-magma", nil)
eq(ST.weave_magma_last_drop, 511, "a nil spell id neither stamps magma nor errors")

ST.interfaces_are_initialised = false
clock = 505
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-pre", 8512)
eq(ST.weave_twist_last_drop, 512, "twist commits are ignored before init")
eq(ST.weave_magma_last_drop, 511, "magma commits are ignored before init")
ST.interfaces_are_initialised = true

totem_slot4 = nil
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 512, "an absent air totem leaves the stamp alone")
totem_slot4 = { have = true, name = "Searing Totem", start = 600, spell = 943 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 512, "a non-twist air totem never stamps")
totem_slot4 = { have = true, name = "Windfury Totem", start = 600, spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 600, "a newer twist totem clock is adopted")
totem_slot4 = { have = true, name = "Grace of Air Totem", start = 550, spell = 99999 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 600, "a stale poll reading never rewinds a fresher commit")
ST.weave_twist_last_drop = nil
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 550, "an unknown stamp adopts the twist totem clock by name")
totem_slot4 = { have = false, name = "Windfury Totem", start = 700, spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 550, "an inactive slot leaves the stamp alone")
totem_slot4 = { have = true, name = "Windfury Totem", start = "soon", spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 550, "a non-number startTime leaves the stamp alone")
totem_slot4 = { have = true, name = "Windfury Totem", start = 0, spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 550, "a zero startTime leaves the stamp alone")
totem_slot4 = { have = true, name = "Windfury Totem (localized)", start = 700, spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 700, "the spell id matches when the totem name differs")
totem_slot4 = { have = 1, name = "Grace of Air Totem", start = 710 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 710, "a numeric haveTotem with no spell id still adopts by name")
-- The compat wrapper contract, through the live module: a valid air-slot read
-- passes through verbatim, while an empty slot, a throwing read and a secret
-- field all degrade to nil (absent).
totem_slot4 = { have = true, name = "Windfury Totem", start = 720, duration = 120,
    icon = "icon_wf", modrate = 1, spell = 8512 }
local wh, wn, ws, wd, wi, wm, wp = st.api.GetTotemInfo(4)
eq(wh, true, "the wrapper passes haveTotem through")
eq(wn, "Windfury Totem", "the wrapper passes totemName through")
eq(ws, 720, "the wrapper passes startTime through")
eq(wd, 120, "the wrapper passes duration through")
eq(wi, "icon_wf", "the wrapper passes icon through")
eq(wm, 1, "the wrapper passes modRate through")
eq(wp, 8512, "the wrapper passes spellID through")
eq(st.api.GetTotemInfo(2), nil, "a slot with no totem reads absent")
totem_slot4 = nil
eq(st.api.GetTotemInfo(4), nil, "an empty air slot reads absent")
totem_slot4 = "THROW"
local ok_throw = pcall(st.api.GetTotemInfo, 4)
check(ok_throw, "a throwing totem read degrades instead of erroring")
totem_slot4 = { have = true, name = "Windfury Totem", start = "SECRET", spell = 8512 }
eq(st.api.GetTotemInfo(4), nil, "a secret field degrades the whole read to absent")
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 710, "a secret totem read leaves the stamp alone")
totem_slot4 = nil
eq(ST.weave_is_casting, false, "twist commits leave no cast in flight")

-- 21) Rage of the Farseer lust -------------------------------------------------------
-- Farseer (Forever personal Bloodlust, UNCONFIRMED - name-only match, no spell id
-- published) feeds the Bloodlust leg of the buff-haste multiplier through the same
-- single aura walk. Never present off Forever, so every other family is unaffected.
aura_list = { { name = "Rage of the Farseer" } }
aura_calls = 0
ST.SHAMAN.on_aura_change(ST)
eq(aura_calls, 2, "farseer: the lust feeds through the same single walk (1 aura + terminator)")
near(ST.weave_haste_mult, 1.30, 1e-9, "farseer: the personal lust reads as the 30% Bloodlust leg")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5 / 1.30, 1e-9, "TBC: the farseer haste shortens the base cast time")
aura_list = { { name = "Rage of the Farseer" }, { name = "Bloodlust", spell_id = 2825 } }
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_haste_mult, 1.30, 1e-9, "farseer: lust never stacks with Bloodlust (one leg, maxed)")
-- Name-only match proof: no spell id is published for Farseer, so an unknown
-- (or wrong) id must never defeat the name match.
aura_list = { { name = "Rage of the Farseer", spell_id = 99999 } }
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_haste_mult, 1.30, 1e-9, "farseer: the name match ignores an unconfirmed id")
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_haste_mult, 1.0, 1e-9, "a dropped lust restores the neutral haste multiplier")
casting_impl = function() return nil end

-- 18) Config and options wiring: the five new keys exist in both directions ---------------
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local presets = read("config_presets.lua")
    local shaman_defaults = presets:match("ST%.SHAMAN%.defaults%s*=%s*%{(.-)ST%.WARLOCK%.defaults")
    check(shaman_defaults ~= nil, "the SHAMAN defaults block is found in config_presets.lua")
    shaman_defaults = shaman_defaults or ""
    local options = read("option_tables.lua")
    local shaman_opts = options:match("function ST%.class_opts_funcs%.SHAMAN%((.*)$")
    check(shaman_opts ~= nil, "the SHAMAN options function is found in option_tables.lua")
    shaman_opts = shaman_opts or ""
    for i = 1, #new_option_keys do
        local key = new_option_keys[i]
        check(shaman_defaults:find("%f[%a_]" .. key .. "%s*=%s*true") ~= nil,
            key .. " ships true in the SHAMAN defaults")
        local widget = shaman_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"toggle\"") ~= nil,
            key .. " has a toggle widget in the SHAMAN options section")
    end
end

if failures == 0 then
    print("PASS  shaman_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  shaman_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
