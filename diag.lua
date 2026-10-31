--=========================================================================================
-- Diagnostics: one print-only self-report for the owner's test session.
--
-- Every failure mode in this addon is silent: the 5 s init deadline disarms a library with
-- one chat notice, nil-guards render nothing, the non-paladin guides default OFF, and
-- Retail hides swings on purpose - so a broken load and a clean one look identical
-- in-client. This module turns the login moment and /st diag into evidence.
--
-- Hard rules (enforced by tests/diag_state.lua):
--   * PRINT-ONLY. Nothing here writes SavedVariables: no frames are created, no
--     SavedVariables are written (the profile tables are only read), no events are
--     registered, no class logic is called, and no library interface is modified.
--     Two in-memory writers exist with the same split as before: the tick counter
--     wrapper writes diag.tick_sites and the chained error handler writes
--     diag.error_ring; the report itself only reads. The one chat touch is the
--     output path: when the global print is gone (F3), the report falls back to
--     the addon's own chat printer (st.utils.print_msg) and announces it once.
--   * It NEVER throws. The public body and every probe are pcall-wrapped, every read is
--     nil-safe, and a value that cannot be read renders as "?" instead of erroring.
--     Unknown spell ids render as UNRESOLVED.
--   * Output is capped to diag.MAX_LINES lines per report.
--
-- The login report (st.diag.report(self), called once at the end of init_libs) is one
-- line; /st diag adds the verbose lines. Field sources, all read-only:
--   st.family / st.interface_number  compat.lua's client-family detection
--   self.addon_version               main.lua's version (kept in sync with the TOCs)
--   self.swing_engine                the swing engine in use: "vendored-lib" |
--                                    "forever-source" | "inert-standin"
--   self.lrc_ready / lrc_unavailable LibRangeCheck state (the init-deadline fallback)
--   LibStub("LibClassicDurations")   the seal-cooldown library (Era/TBC only)
--   st.ldb.obj / st.ldb.init_attempted  the LibDataBroker feed (ldb.lua)
--   self.<CLASS>.guide               the frozen guide provider contract
--   self.db.profile[<CLASS>]         guide enablement (nextaction_enabled)
--   self.stl_ready / llm_ready / lrc_ready / lrc_unavailable  init readiness flags
--   self.interfaces_are_initialised  set by init_libs once everything is up
--   self.init_deadline_fired         set by the 5 s deadline when it had to rescue init
--   st.practice_ui / st.hud / st.rotation_text / st.designmode  the UI modules
--   C_Secrets                        the secret-value restriction predicates (Mainline)
--   diag.tick_sites                  the per-tick counters (written ONLY by main.lua's
--                                    OnUpdate counting wrapper installed through
--                                    wrap_onupdate; the report reads and stays print-only)
--   self.db.profile.diag_tick_counters  the enable gate wrap_onupdate reads (nil = off)
--   st.api.GetSpellInfo / is_spell_known  the wanted-id resolution (DATA-only list
--                                    WANTED_IDS cites bench/ids_research_2026-10-19.md)
--   diag.error_ring                  the chained-error ring (written ONLY by the
--                                    seterrorhandler chain; the report prints newest last)
--   diag._error_handler_installed    whether that chain is installed right now:
--                                    main.lua installs it in init_libs and removes it
--                                    again on PLAYER_LOGOUT, so the report can tell
--                                    "nothing threw" from "nothing was watched"
--   self[hand].anchor_frame.bar_frame / visuals_frame / visuals_frame.bar
--                                    the per-hand BAR STATE lines (frames are READ:
--                                    IsVisible/IsShown/GetAlpha/GetScript/GetWidth and
--                                    the hand's own state table - nothing is created,
--                                    shown, hidden or written)
--   self.class_hands / self.player_class  which hands exist for the class (one line each)
--   db.profile[<CLASS>][<hand>].x/.y  the saved LibWindow row (pos= in the hand line)
--   self.<CLASS>.raptor_strike_queued / .steady_shot_queued
--                                    the hunter queue-tint flags (mainhand line only)
--   self[hand].has_activity / .last_activity_at / .activity_source / .auto_repeat_active
--   self[hand].hide_reason           the activity receipt and the recorded hide reason
--                                    (written ONLY by main.lua's gate/visibility paths;
--                                    the report reads them - same writer/reader split as
--                                    diag.tick_sites)
--   self.hand_visibility_needs_activity / hand_is_in_use / hand_activity_window
--                                    main.lua's own read-only gate rule functions (called,
--                                    never class logic; they read state and the clock)
--   st.power_bar.frame / .ready / .last_state / .fraction
--                                    the power-bar line: the last resolved state the
--                                    driver stored (pb.last_state, written ONLY by
--                                    pb.update; .fraction is its pure fill maths) plus
--                                    the live st.api UnitPowerType/UnitPower/UnitPowerMax
--                                    readings (API reads, like GetSpellInfo)
--   self.bar_hook_errors.by_site / .quarantined
--                                    the guard quarantine line (written ONLY by
--                                    st.guard; the report names every site it counted)
--=========================================================================================
local _, st = ...

st.diag = st.diag or {}
local diag = st.diag

-- Hard output cap. The verbose report is the 5 base lines plus the power-bar line (added
-- 2026-10-28, publish-audit P4) plus the per-hand BAR STATE lines (one per hand the class
-- owns) plus the guard-quarantine line (P4) plus the ids section (one line per wanted id,
-- truncated with a +N count line when the cap binds) plus the error ring (newest last,
-- same cap rule). Worst case is 5 + 1 + 3 + 1 + 67 + 8 = 85 lines, so the cap stays 88
-- and the cap-binding tails keep their headroom. This stays headroom, never a silent cut.
local DEFAULT_MAX_LINES = 88
diag.MAX_LINES = DEFAULT_MAX_LINES
-- Bounded in-memory error ring (no SavedVariables writes; the report reads, the
-- chained handler writes - same split as diag.tick_sites).
diag.ERROR_MAX = 8

local PREFIX = "SwedgeTimer diag:"

-- The classes that ship a guide provider. Guide enablement is the per-class
-- nextaction_enabled setting - exactly what nextaction_ui.should_show reads.
local PROVIDER_CLASSES = { "PALADIN", "WARRIOR", "DRUID", "SHAMAN", "HUNTER", "ROGUE" }

-- Wanted spell ids, DATA-only. Source: bench/ids_research_2026-10-19.md section 3
-- still-UNCONFIRMED (U1-U17) plus the per-class rank/aura ids referenced there.
-- Unknown/unresolvable prints as UNRESOLVED (never errors, never writes).
local WANTED_IDS = {
    -- U1 Forever rank tables + triggers
    1310785, 1310786, 1293525, 1293526, 1293527, 1293248, 1312639,
    -- U3 Victory Rush / Victorious
    34428, 32216,
    -- U9 Forever bonus kit
    14287, 25295, 14325, 25296, 14266, 14268, 1317257, 469145, 3045, 5384, 2643, 20904, 14271, 20572,
    -- U10 rogue per-client (Wrath / TBC / Forever / Era / SoD)
    57993, 51662, 26889, 58426, 57934, 51690, 48668,
    26864, 26863, 34413, 26862, 5938, 32645, 26867, 26865,
    11281, 1241584, 16511, 11294, 6774, 11275, 11300, 13750, 7676, 13877, 14177, 1310703,
    31016, 425096, 1856,
    -- U11 paladin (JotC)
    21183,
    -- U12 shaman (Stormstrike + SoD runes)
    17364, 440580, 408490, 408507, 425339, 408498, 408505, 425336,
    -- U13 warrior ranks
    11605, 25286, 20569,
    -- U14 druid (Berserk WotLK)
    50334,
    -- U17 Explosive Shot R3
    60052,
}

-- In-memory error ring (never SavedVariables, never chat). The report reads it;
-- the chained error handler below is the only writer.
diag.error_ring = diag.error_ring or {}
diag._prev_error_handler = diag._prev_error_handler
diag._error_handler_installed = diag._error_handler_installed or false
-- F3: one-time notice that the report left the global print and went to the chat.
diag._print_fallback_announced = diag._print_fallback_announced or false

--=========================================================================================
-- Emission (never throws)
--=========================================================================================
-- diag.sink is the test hook (tests/diag_state.lua captures lines through it); production
-- prints through the global print. Every path is pcall-wrapped: a protected, broken or
-- absent printer must degrade, never to an error.
--
-- F3 (deep audit 2026-10-19): the bare global print was the report's ONLY output path.
-- A client (or another addon) that removes or shadows it made the pcall fail and the
-- whole report vanish silently - a diagnostic that disappears is worse than one that
-- is wrong. The fallback is the addon's own printer (st.utils.print_msg, which writes
-- to the chat frame), and the switch is announced once, so a report that changed
-- channel is never mistaken for a report that never ran.
local function print_line(text)
    local sink = diag.sink
    if type(sink) == "function" then
        if pcall(sink, text) then
            return
        end
    end
    local printer = rawget(_G, "print")
    if type(printer) == "function" then
        if pcall(printer, text) then
            return
        end
    end
    -- The global print is absent or broken: fall back to the addon's chat printer.
    local utils = rawget(st, "utils")
    local print_msg = utils and rawget(utils, "print_msg")
    if type(print_msg) ~= "function" then
        -- No fallback available either: degrade to silence (never to an error).
        return
    end
    if not diag._print_fallback_announced then
        diag._print_fallback_announced = true
        pcall(print_msg, PREFIX .. " the global print is unavailable; the report goes to the chat frame")
    end
    pcall(print_msg, text)
end

--=========================================================================================
-- Nil-safe reads and probes (never throw)
--=========================================================================================
-- One read, pcall-wrapped so even a hostile metatable cannot escape.
local function read(root, key)
    if type(root) ~= "table" then
        return nil
    end
    local ok, value = pcall(function() return root[key] end)
    if ok then
        return value
    end
    return nil
end

-- Scalar rendering: strings/numbers/booleans print, anything else is "unknown".
local function show(value)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    return "?"
end

-- Readiness flags: true/false where set, "?" where the field does not exist yet.
local function flag(value)
    if value == nil then
        return "?"
    end
    if value then
        return "true"
    end
    return "false"
end

-- LibRangeCheck: ready, disabled by the init deadline (fallback), or unknown.
local function lrc_state(self)
    if read(self, "lrc_unavailable") == true then
        return "fallback"
    end
    if read(self, "lrc_ready") == true then
        return "ready"
    end
    return "?"
end

-- LibClassicDurations presence, through LibStub's silent form. Its absence is a
-- legitimate state (the library is Era/TBC-only); a broken or missing LibStub is unknown.
local function lcd_state()
    if type(LibStub) ~= "function" then
        return "?"
    end
    local ok, lib = pcall(LibStub, "LibClassicDurations", true)
    if not ok then
        return "?"
    end
    if lib ~= nil then
        return "present"
    end
    return "absent"
end

-- LibDataBroker object: created, pending (the lazy init has not run yet), absent (the
-- creation attempt failed - e.g. the library is missing), or unknown.
local function ldb_state()
    local l = read(st, "ldb")
    if type(l) ~= "table" then
        return "?"
    end
    if read(l, "obj") ~= nil then
        return "object"
    end
    if read(l, "init_attempted") == true then
        return "absent"
    end
    return "pending"
end

-- The frozen guide provider contract (nextaction_ui.get_provider): a table with gather
-- and evaluate functions. Read, never called.
local function has_guide_provider(self, class)
    local class_module = read(self, class)
    local guide = read(class_module, "guide")
    return type(guide) == "table"
        and type(guide.gather) == "function"
        and type(guide.evaluate) == "function"
end

-- "on"/"off" when a provider exists (nextaction_enabled gates the guide frame; nil counts
-- as on, the same rule nextaction_ui.should_show applies), "none" when the class module
-- has no provider loaded, "?" when the profile cannot be read.
local function guide_state(self, class)
    if not has_guide_provider(self, class) then
        return "none"
    end
    local profile = read(read(self, "db"), "profile")
    local db_class = read(profile, class)
    if type(db_class) ~= "table" then
        return "?"
    end
    if db_class.nextaction_enabled == false then
        return "off"
    end
    return "on"
end

local function provider_count(self)
    local n = 0
    for i = 1, #PROVIDER_CLASSES do
        if has_guide_provider(self, PROVIDER_CLASSES[i]) then
            n = n + 1
        end
    end
    return n
end

--=========================================================================================
-- Per-tick budget counters (the hand-bar OnUpdate sites)
--=========================================================================================
-- main.lua's OnUpdate hook line (init_timers) installs either the original hand.onupdate
-- or, through diag.wrap_onupdate below, a counting wrapper. The gate is the profile key
-- diag_tick_counters: strictly true turns the counters on for the whole session, every
-- other value (including nil - the default) installs the original function object
-- untouched, so a default session keeps a byte-identical hook and flat-zero added
-- overhead per frame tick. The toggle takes effect on the next login/reload; the options
-- pass owns the widget and the documented default.
-- Ownership: only the wrapper (called from main.lua's hook) writes diag.tick_sites; the
-- report below reads it, therefore report stays print-only. Installing the wrapper is
-- never a frame creation, event registration or SavedVariables write.
diag.tick_sites = diag.tick_sites or {} -- hand -> { ticks = <n>, seconds = <t> }
local TICK_HANDS = { "mainhand", "offhand", "ranged" }

function diag.wrap_onupdate(self, hand, original)
    if type(original) ~= "function" then
        return original
    end
    if read(read(read(self, "db"), "profile"), "diag_tick_counters") ~= true then
        return original
    end
    if type(diag.tick_sites) ~= "table" then
        diag.tick_sites = {}
    end
    -- Attribution clock: the aligned clock in compat (st.api.get_time), which wraps raw
    -- GetTimePreciseSec and never throws. A sandbox or broken compat simply leaves the
    -- seconds unmeasured (nil keeps them "?", unknown is never rendered as zero) while
    -- the tick counts keep running.
    local clock = nil
    if type(st.api) == "table" and type(st.api.get_time) == "function" then
        clock = st.api.get_time
    end
    local site = { ticks = 0, seconds = clock and 0 or nil }
    diag.tick_sites[hand] = site
    return function(elapsed)
        site.ticks = site.ticks + 1
        if clock then
            local before = clock()
            original(elapsed)
            local after = clock()
            if type(after) == "number" and type(before) == "number" then
                site.seconds = site.seconds + (after - before)
            end
        else
            original(elapsed)
        end
    end
end

--=========================================================================================
-- Line construction
--=========================================================================================
local function guides_text(self)
    local parts = {}
    for i = 1, #PROVIDER_CLASSES do
        parts[#parts + 1] = PROVIDER_CLASSES[i] .. ":" .. guide_state(self, PROVIDER_CLASSES[i])
    end
    return "guides=" .. table.concat(parts, " ")
end

-- The login line: family, interface, version, engine, LibRangeCheck, LibClassicDurations,
-- LibDataBroker and every guide's state. One line, always printed.
local function config_line(self)
    return string.format(
        "%s family=%s iface=%s version=%s engine=%s lrc=%s lcd=%s ldb=%s %s",
        PREFIX,
        show(read(st, "family")),
        show(read(st, "interface_number")),
        show(read(self, "addon_version")),
        show(read(self, "swing_engine")),
        lrc_state(self),
        lcd_state(),
        ldb_state(),
        guides_text(self))
end

-- Verbose line: the init readiness flags and the deadline/init state.
local function flags_line(self)
    return string.format(
        "%s flags stl_ready=%s llm_ready=%s lrc_ready=%s lrc_unavailable=%s deadline=%s init=%s",
        PREFIX,
        flag(read(self, "stl_ready")),
        flag(read(self, "llm_ready")),
        flag(read(self, "lrc_ready")),
        flag(read(self, "lrc_unavailable")),
        read(self, "init_deadline_fired") == true and "fired" or "no",
        read(self, "interfaces_are_initialised") == true and "yes" or "no")
end

-- Verbose line: the UI modules this TOC set loaded and the guide-provider count.
local function loaded_text(module)
    if module ~= nil then
        return "yes"
    end
    return "no"
end

local function modules_line(self)
    return string.format(
        "%s modules practice=%s hud=%s rotation=%s design=%s providers=%d/%d",
        PREFIX,
        loaded_text(read(st, "practice_ui")),
        loaded_text(read(st, "hud")),
        loaded_text(read(st, "rotation_text")),
        loaded_text(read(st, "designmode")),
        provider_count(self),
        #PROVIDER_CLASSES)
end

-- Per-site tick count render: the number, or "?" wherever the counting wrapper was not
-- installed for that hand (a default OFF session) or the count is unreadable. The labels
-- are stable over every state so /st diag output stays greppable session over session.
local function ticks_site_value(hand)
    local site = read(diag.tick_sites, hand)
    if type(site) == "table" and type(site.ticks) == "number" then
        return tostring(site.ticks)
    end
    return "?"
end

-- On-update time attribution: the summed measured seconds over every recorded site, or
-- "?" when no site has a readable seconds field (counting off, or no clock captured).
local function ticks_cpu_value()
    if type(diag.tick_sites) ~= "table" then
        return "?"
    end
    local seconds = nil
    for _, site in pairs(diag.tick_sites) do
        if type(site) == "table" and type(site.seconds) == "number" then
            seconds = (seconds or 0) + site.seconds
        end
    end
    if seconds == nil then
        return "?"
    end
    return string.format("%.2fs", seconds)
end

-- Verbose line: what each OnUpdate site ran and how long it took (the C4 tick-budget
-- audit, the /tmw cpu analogue); the counting gate is documented at diag.wrap_onupdate.
local function ticks_line()
    local on = "no"
    for i = 1, #TICK_HANDS do
        if type(read(diag.tick_sites, TICK_HANDS[i])) == "table" then
            on = "yes"
        end
    end
    return string.format(
        "%s ticks on=%s mainhand=%s offhand=%s ranged=%s cpu=%s",
        PREFIX,
        on,
        ticks_site_value("mainhand"),
        ticks_site_value("offhand"),
        ticks_site_value("ranged"),
        ticks_cpu_value())
end

--=========================================================================================
-- Per-hand bar state (verbose only; reads frames, never creates or mutates one)
--=========================================================================================
-- Operator order 2026-10-28: "/st diag works better, because it said there was no errors,
-- meaning something was missed/silent". A clean error ring is not proof the bars work: a
-- bar can be unbuilt, hidden, unticked, alpha-dimmed, stalled at zero progress or painting
-- a stale fill with nothing thrown anywhere. One line per hand the class actually owns
-- (main.lua's class_hands, read only), fields in a fixed order so the output is greppable
-- session over session:
--   built    - the frames exist (HU-22 lazy build; "no" is also the not-configured state)
--   shown    - the bar frame is on screen right now
--   why      - a short reason when the hand is NOT on screen (publish-audit P4-1):
--              unbuilt | class-off | off | no-weapon | spec | form | show-rule | idle;
--              "-" while shown, "?" when that cannot be read (main.lua records the token
--              where the visibility decision hides the bar)
--   gate     - the activity gate: open | closed | n/a (the mainhand has no gate) | ?
--   active   - the has_activity receipt flag (yes/no/?)
--   win      - this hand's activity window in seconds
--   left     - seconds left in that window; none with no receipt, ? when unknown
--   src      - what proved the activity: cleu | forever | shot | auto-repeat | none | ?
--   alpha    - the bar frame's alpha (the out-of-range dim writes this)
--   tick     - an OnUpdate script is installed on the bar frame
--   start / speed / ends_at / now / progress - the swing cycle the tick renders from
--   full / paused / dead - the state flags the tick branches on
--   vf_width - the visuals width the fill maths uses
--   fill     - the fill texture's actual width in px (1 = the neutral sliver)
--   pos      - the saved LibWindow row (x,y) the bar is placed at
--   queue    - the hunter Raptor/Steady queue-tint flags, on the MAINHAND line only (they
--              are class-level flags and they recolour the mainhand fill)
-- Every value runs through the same pcall/type guards as the rest of the module: an
-- unreadable field renders "?" and never throws. The hand list is read from the addon, so
-- a single-melee-hand class (paladin/druid) gets one line, not three.
local BAR_HANDS = { "mainhand", "offhand", "ranged" }

-- The hand tokens this class owns. Falls back to the three generic hands when the addon's
-- table is unreadable (a sandbox, a pre-init self): a hand the class does not own then
-- renders as unbuilt, which is the informative answer, never an error.
local function class_hand_tokens(self)
    local class = read(self, "player_class")
    local hands = read(read(self, "class_hands"), class)
    if type(hands) == "table" and #hands > 0 then
        return hands
    end
    return BAR_HANDS
end

-- Seconds / pixel widths / alpha: two decimals, or "?" (unknown is never rendered as 0).
local function number_text(value)
    if type(value) ~= "number" then
        return "?"
    end
    return string.format("%.2f", value)
end

-- Bar progress fraction: three decimals so a near-stalled tick is visible.
local function progress_text(value)
    if type(value) ~= "number" then
        return "?"
    end
    return string.format("%.3f", value)
end

-- State flag: only real booleans answer yes/no; unset is "?".
local function yes_no(value)
    if value == true then
        return "yes"
    end
    if value == false then
        return "no"
    end
    return "?"
end

-- One frame method call under pcall; nil when the method is absent or throws. Extra
-- arguments are forwarded (GetScript needs the event name).
local function frame_read(frame, name, ...)
    local method = read(frame, name)
    if type(method) ~= "function" then
        return nil
    end
    local ok, value = pcall(method, frame, ...)
    if ok then
        return value
    end
    return nil
end

-- The saved LibWindow row for one hand (profile[<class>][<hand>]), read-only. rawget is
-- deliberate: AceDB gives the profile root and every class row a '**' metatable whose
-- __index CREATES a defaults-filled sub-table for a missing key
-- (Libs/AceDB-3.0/AceDB-3.0.lua:88-107) - a diagnostic must never write through a read.
local function profile_hand(self, hand)
    local profile = read(read(self, "db"), "profile")
    if type(profile) ~= "table" then
        return nil
    end
    local class = read(self, "player_class")
    if class == nil then
        return nil
    end
    local class_row = rawget(profile, class)
    if type(class_row) ~= "table" then
        return nil
    end
    return rawget(class_row, hand)
end

-- The hunter Raptor/Steady queue-tint flags: class-level state that recolours the mainhand
-- fill, so it renders on the mainhand line only, and only when the class exposes it.
local function queue_text(self, hand)
    if hand ~= "mainhand" then
        return ""
    end
    local class_module = read(self, read(self, "player_class"))
    local raptor = read(class_module, "raptor_strike_queued")
    local steady = read(class_module, "steady_shot_queued")
    if raptor == nil and steady == nil then
        return ""
    end
    return " queue=raptor:" .. yes_no(raptor) .. ",steady:" .. yes_no(steady)
end

-- Call one of the addon's own read-only rule functions (main.lua's gate helpers). nil when
-- the function is absent, a sandbox stubbed it out or it throws - the same "unknown"
-- contract as every other field. This is not class logic: the three helpers read state
-- and the aligned clock only.
local function call_self(self, name, ...)
    local fn = read(self, name)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, self, ...)
    if ok then
        return value
    end
    return nil
end

-- The activity gate for one hand, as the report renders it (2026-10-28, publish-audit
-- P4-1: a bar hidden by the gate looked exactly like a bar switched off):
--   gate   - "n/a" when the hand has no activity gate (the mainhand), else open/closed/?
--   active - the has_activity receipt flag (yes/no/?)
--   win    - the hand's own activity window in seconds ("?" when unreadable)
--   left   - seconds left in the window ("none" with no receipt, "?" when the clock or
--            the window is unknown - a receipt with no clock is never rendered as 0)
--   src    - the receipt source token ("cleu" | "forever" | "shot"), "auto-repeat" when
--            only the Auto Shot armed reading keeps the hand in use, "none", or "?"
local function gate_text(self, hand)
    if call_self(self, "hand_visibility_needs_activity", hand) ~= true then
        return "n/a"
    end
    local in_use = call_self(self, "hand_is_in_use", hand)
    if in_use == true then
        return "open"
    end
    if in_use == false then
        return "closed"
    end
    return "?"
end

local function window_text(self, hand)
    local window = call_self(self, "hand_activity_window", hand)
    if type(window) ~= "number" then
        return "?"
    end
    return string.format("%.2f", window)
end

local function window_left_text(state, window, now)
    if read(state, "has_activity") ~= true then
        return "none"
    end
    local last = read(state, "last_activity_at")
    if type(window) ~= "number" or type(last) ~= "number" or type(now) ~= "number" then
        return "?"
    end
    local left = window - (now - last)
    if left < 0 then
        left = 0
    end
    return string.format("%.2f", left)
end

local function receipt_source_text(state, hand)
    if read(state, "has_activity") == true then
        local source = read(state, "activity_source")
        if type(source) == "string" and source ~= "" then
            return source
        end
        -- A receipt recorded by a writer this build no longer names: unknown, not "none".
        return "?"
    end
    if hand == "ranged" and read(state, "auto_repeat_active") == true then
        return "auto-repeat"
    end
    return "none"
end

-- A short reason for shown=no ("-" when the bar is on screen, "?" when the state is
-- unreadable). The tokens are main.lua's own hide reasons, recorded where the visibility
-- decision hides the bar (see main.lua: note_hand_hide_reason); an unbuilt hand is
-- answered here because it never reaches that decision.
local function hide_reason_text(state, built, shown)
    if not built then
        return "unbuilt"
    end
    if shown == true then
        return "-"
    end
    if shown == false then
        local reason = read(state, "hide_reason")
        if type(reason) == "string" and reason ~= "" then
            return reason
        end
    end
    return "?"
end

-- One hand's BAR STATE line. The caller pcall's this too, so an unreadable field can only
-- cost its own line.
local function bar_line(self, hand)
    local state = read(self, hand)
    local anchor = read(state, "anchor_frame")
    local bar_frame = read(anchor, "bar_frame")
    local visuals = read(bar_frame, "visuals_frame")
    local fill = read(visuals, "bar")
    local built = bar_frame ~= nil and visuals ~= nil
    local shown, tick, alpha = nil, nil, nil
    if built then
        shown = frame_read(bar_frame, "IsVisible")
        if type(shown) ~= "boolean" then
            shown = frame_read(bar_frame, "IsShown")
        end
        if type(shown) ~= "boolean" then
            shown = nil
        end
        if type(read(bar_frame, "GetScript")) == "function" then
            -- The event name matters: GetScript() without it answers nil on a real frame.
            tick = frame_read(bar_frame, "GetScript", "OnUpdate") ~= nil
        end
        alpha = frame_read(bar_frame, "GetAlpha")
    end
    -- The aligned clock compat reports (nothing here reads the raw clock or the profile).
    local now = nil
    local api_table = read(st, "api")
    local clock = read(api_table, "get_time")
    if type(clock) == "function" then
        local ok_clock, value = pcall(clock)
        if ok_clock and type(value) == "number" then
            now = value
        end
    end
    local row = profile_hand(self, hand)
    local window = call_self(self, "hand_activity_window", hand)
    return string.format(
        "%s bar %s built=%s shown=%s why=%s gate=%s active=%s win=%s left=%s src=%s"
            .. " alpha=%s tick=%s start=%s speed=%s ends_at=%s now=%s progress=%s"
            .. " full=%s paused=%s dead=%s vf_width=%s fill=%s pos=%s,%s%s",
        PREFIX,
        tostring(hand),
        built and "yes" or "no",
        yes_no(shown),
        hide_reason_text(state, built, shown),
        gate_text(self, hand),
        yes_no(read(state, "has_activity")),
        window_text(self, hand),
        window_left_text(state, window, now),
        receipt_source_text(state, hand),
        number_text(alpha),
        yes_no(tick),
        number_text(read(state, "start")),
        number_text(read(state, "speed")),
        number_text(read(state, "ends_at")),
        number_text(now),
        progress_text(read(state, "current_progress")),
        yes_no(read(state, "is_full")),
        yes_no(read(state, "is_paused")),
        yes_no(read(state, "engine_dead")),
        number_text(read(state, "vf_width")),
        number_text(frame_read(fill, "GetWidth")),
        show(read(row, "x")),
        show(read(row, "y")),
        queue_text(self, hand))
end

-- The BAR STATE section: one line per owned hand, in the class's own hand order.
local function bar_lines(self)
    local hands = class_hand_tokens(self)
    local out = {}
    for i = 1, #hands do
        local hand = hands[i]
        local ok, line = pcall(bar_line, self, hand)
        if ok and type(line) == "string" then
            out[#out + 1] = line
        else
            out[#out + 1] = PREFIX .. " bar " .. tostring(hand) .. " unavailable"
        end
    end
    return out
end

-- Secret-value restriction predicates (Mainline clients) - the switches that decide
-- whether restricted reads come back as opaque secrets. C_Secrets is absent on classic
-- clients, where the line is just "secrets api=no". Every probe is pcall'd; a missing,
-- throwing or non-boolean probe renders "?" rather than erroring.
local SECRET_PROBES = {
    { "restrictions", "HasSecretRestrictions",          {} },
    { "cd",           "ShouldCooldownsBeSecret",        {} },
    { "aura",         "ShouldAurasBeSecret",            {} },
    { "power",        "ShouldUnitPowerBeSecret",        { "player" } },
    { "stats",        "ShouldUnitStatsBeSecret",        {} },
    { "cast",         "ShouldUnitSpellCastingBeSecret", { "player" } },
}

local function secret_probe_flag(c_secrets, name, args)
    local probe = read(c_secrets, name)
    if type(probe) ~= "function" then
        return "?"
    end
    local ok, value = pcall(probe, unpack(args))
    if ok and type(value) == "boolean" then
        return value and "true" or "false"
    end
    return "?"
end

local function secrets_line()
    local c_secrets = rawget(_G, "C_Secrets")
    if type(c_secrets) ~= "table" then
        return PREFIX .. " secrets api=no"
    end
    local parts = { "secrets api=yes" }
    for i = 1, #SECRET_PROBES do
        local probe = SECRET_PROBES[i]
        parts[#parts + 1] = probe[1] .. "="
            .. secret_probe_flag(c_secrets, probe[2], probe[3])
    end
    return PREFIX .. " " .. table.concat(parts, " ")
end

--=========================================================================================
-- Power bar (verbose only; 2026-10-28 publish-audit P4-1)
--=========================================================================================
-- The audit's "Power bar orphaned: NO line at all" gap. The bar hides for five different
-- reasons (off / no melee row / no power API / no power type / no usable reading) and an
-- anchored-but-empty bar looks exactly like one that was never built. One line, always in
-- the verbose report, so an orphaned bar is attributable:
--   ready        - pb.init created the frames (no = the module never initialised)
--   anchor       - the owning melee hand named by the last refresh (offhand | mainhand |
--                  none), from pb.last_state (written only by pb.update)
--   anchor_shown - whether that owning row is on screen right now
--   shown / width / height - the bar frame itself
--   type / token / value / fraction - the LIVE primary-power reading (st.api, the same
--                  calls the bar paints from; unknown when the client restricts it)
--   why          - the last refresh's hide token (pb.resolve), "-" while painted
local POWER_WHY = {
    ["no-frame"] = true,
    ["no-addon"] = true,
    ["off"] = true,
    ["no-anchor"] = true,
    ["no-api"] = true,
    ["no-type"] = true,
    ["no-value"] = true,
    ["no-fraction"] = true,
}

local function power_live_text(pb)
    local api_table = read(st, "api")
    if type(api_table) ~= "table" then
        return "unknown", "unknown", "unknown", "?"
    end
    local type_fn = read(api_table, "UnitPowerType")
    local value_fn = read(api_table, "UnitPower")
    local max_fn = read(api_table, "UnitPowerMax")
    local power_type, token = nil, nil
    if type(type_fn) == "function" then
        local ok, kind, kind_token = pcall(type_fn, "player")
        if ok then
            if type(kind) == "number" then
                power_type = kind
            end
            if type(kind_token) == "string" and kind_token ~= "" then
                token = kind_token
            end
        end
    end
    if power_type == nil then
        return "unknown", "unknown", "unknown", "?"
    end
    local value, max_value = nil, nil
    if type(value_fn) == "function" then
        local ok, reading = pcall(value_fn, "player", power_type)
        if ok and type(reading) == "number" then
            value = reading
        end
    end
    if type(max_fn) == "function" then
        local ok, reading = pcall(max_fn, "player", power_type)
        if ok and type(reading) == "number" then
            max_value = reading
        end
    end
    local type_text = tostring(power_type)
    local token_text = token or "?"
    if value == nil or max_value == nil then
        return type_text, token_text, "unknown", "?"
    end
    local fraction = nil
    local fraction_fn = read(pb, "fraction")
    if type(fraction_fn) == "function" then
        local ok, reading = pcall(fraction_fn, value, max_value)
        if ok and type(reading) == "number" then
            fraction = reading
        end
    elseif max_value > 0 then
        fraction = value / max_value
    end
    local fraction_text = type(fraction) == "number" and progress_text(fraction) or "?"
    return type_text, token_text, tostring(value) .. "/" .. tostring(max_value), fraction_text
end

local function power_line(self)
    local pb = read(st, "power_bar")
    if type(pb) ~= "table" then
        return PREFIX .. " power module=no"
    end
    local frame = read(pb, "frame")
    local state = read(pb, "last_state")
    local anchor = read(state, "anchor_hand")
    if type(anchor) ~= "string" or anchor == "" then
        anchor = "none"
    end
    local anchor_shown = "?"
    local anchor_frame = read(state, "anchor")
    if anchor_frame ~= nil then
        local visible = frame_read(anchor_frame, "IsVisible")
        if type(visible) ~= "boolean" then
            visible = frame_read(anchor_frame, "IsShown")
        end
        if type(visible) == "boolean" then
            anchor_shown = visible and "yes" or "no"
        end
    elseif anchor == "none" then
        anchor_shown = "no"
    end
    local shown = nil
    if frame ~= nil then
        shown = frame_read(frame, "IsVisible")
        if type(shown) ~= "boolean" then
            shown = frame_read(frame, "IsShown")
        end
        if type(shown) ~= "boolean" then
            shown = nil
        end
    end
    local why = "-"
    if shown ~= true then
        local reason = read(state, "why")
        if type(reason) == "string" and POWER_WHY[reason] == true then
            why = reason
        else
            why = "?"
        end
    end
    local type_text, token_text, value_text, fraction_text = power_live_text(pb)
    return string.format(
        "%s power ready=%s anchor=%s anchor_shown=%s shown=%s width=%s height=%s"
            .. " type=%s token=%s value=%s fraction=%s why=%s",
        PREFIX,
        read(pb, "ready") == true and "yes" or "no",
        anchor,
        anchor_shown,
        yes_no(shown),
        number_text(frame_read(frame, "GetWidth")),
        number_text(frame_read(frame, "GetHeight")),
        type_text,
        token_text,
        value_text,
        fraction_text,
        why)
end

--=========================================================================================
-- Guard quarantine (verbose only; 2026-10-28 publish-audit P4-2 / C2a)
--=========================================================================================
-- st.guard quarantines a throwing site after 25 failures, announces it once, then never
-- calls it again - so a per-tick subsystem can be dead for the session. /st diag used to
-- print only the total (main.lua's bar_hook_errors=<n>), which named nothing. This line
-- names every site the guard counted with its count, sorted quarantined-first then by
-- volume (deterministic across sessions), capped with an explicit "+N more sites" tail.
local QUARANTINE_SITES_MAX = 8

local function quarantine_line(self)
    local errors = read(self, "bar_hook_errors")
    if type(errors) ~= "table" then
        return PREFIX .. " quarantine total=? sites=?"
    end
    local total = read(errors, "count")
    -- An unreadable count is unknown, never a fake clean zero.
    local total_text = type(total) == "number" and tostring(total) or "?"
    local by_site = read(errors, "by_site")
    if type(by_site) ~= "table" then
        -- A guard table without its per-site map cannot name anything: say so.
        return PREFIX .. " quarantine total=" .. total_text .. " sites=?"
    end
    local quarantined = read(errors, "quarantined")
    local sites = {}
    for site, count in pairs(by_site) do
        if type(count) == "number" then
            local is_quarantined = type(quarantined) == "table"
                and read(quarantined, site) == true
            sites[#sites + 1] = {
                site = tostring(site),
                count = count,
                quarantined = is_quarantined,
            }
        end
    end
    if #sites == 0 then
        return PREFIX .. " quarantine total=" .. total_text .. " sites=none"
    end
    table.sort(sites, function(a, b)
        if a.quarantined ~= b.quarantined then
            return a.quarantined
        end
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.site < b.site
    end)
    local parts = {}
    local shown_count = #sites
    if shown_count > QUARANTINE_SITES_MAX then
        shown_count = QUARANTINE_SITES_MAX
    end
    for i = 1, shown_count do
        local entry = sites[i]
        parts[#parts + 1] = entry.site .. "=" .. tostring(entry.count)
            .. (entry.quarantined and "[q]" or "")
    end
    local tail = ""
    if #sites > shown_count then
        tail = ",+" .. tostring(#sites - shown_count) .. " more sites"
    end
    return PREFIX .. " quarantine total=" .. total_text
        .. " sites=" .. table.concat(parts, ",") .. tail
end

--=========================================================================================
-- Wanted-id resolution (verbose only; print-only, never writes)
--=========================================================================================
-- One line per wanted id through st.api.GetSpellInfo (the cross-client spell probe in
-- compat.lua): name/icon/cast/known where the client answers, UNRESOLVED otherwise.
-- known comes from st.api.is_spell_known where present, "?" where the probe is
-- absent or throws. Every read is pcall-guarded; a missing api degrades every id to
-- UNRESOLVED instead of erroring.
local function ids_one(id, get_info, is_known_fn)
    if type(id) ~= "number" then
        return PREFIX .. " ids ?=UNRESOLVED"
    end
    if type(get_info) ~= "function" then
        return PREFIX .. " ids " .. tostring(id) .. "=UNRESOLVED"
    end
    local ok, name, _, icon, cast = pcall(get_info, id)
    if not ok or type(name) ~= "string" then
        return PREFIX .. " ids " .. tostring(id) .. "=UNRESOLVED"
    end
    local known_txt = "?"
    if type(is_known_fn) == "function" then
        local ok_known, known = pcall(is_known_fn, id)
        if ok_known and type(known) == "boolean" then
            known_txt = known and "true" or "false"
        end
    end
    local icon_txt = "?"
    if type(icon) == "string" or type(icon) == "number" then
        icon_txt = tostring(icon)
    end
    local cast_txt = "?"
    if type(cast) == "number" then
        cast_txt = tostring(cast)
    end
    return PREFIX .. " ids " .. tostring(id) .. " name=" .. name
        .. " icon=" .. icon_txt .. " cast=" .. cast_txt .. " known=" .. known_txt
end

local function ids_lines()
    if type(WANTED_IDS) ~= "table" then
        return {}
    end
    local get_info
    local is_known_fn
    if type(st.api) == "table" then
        get_info = st.api.GetSpellInfo
        is_known_fn = st.api.is_spell_known
    end
    local out = {}
    for i = 1, #WANTED_IDS do
        local ok, line = pcall(ids_one, WANTED_IDS[i], get_info, is_known_fn)
        if ok and type(line) == "string" then
            out[#out + 1] = line
        else
            out[#out + 1] = PREFIX .. " ids ?=UNRESOLVED"
        end
    end
    return out
end

--=========================================================================================
-- In-game error ring (verbose only; in-memory, never SavedVariables)
--=========================================================================================
-- seterrorhandler chaining: install keeps + calls the previous handler, the chained
-- handler records into diag.error_ring (bounded by diag.ERROR_MAX, oldest evicted,
-- newest last) and never throws. Uninstall restores the previous handler. The report
-- reads the ring; only the handler writes it.
function diag.record_error(msg)
    pcall(function()
        if type(diag.error_ring) ~= "table" then
            diag.error_ring = {}
        end
        local text
        if type(msg) == "string" then
            text = msg
        else
            local ok_str, as_str = pcall(tostring, msg)
            text = (ok_str and type(as_str) == "string") and as_str or "?"
        end
        local ok_flat, flat = pcall(string.gsub, text, "[\r\n]+", " ")
        if ok_flat and type(flat) == "string" then
            text = flat
        end
        if #text > 200 then
            text = string.sub(text, 1, 200)
        end
        if type(diag.ERROR_MAX) ~= "number" or diag.ERROR_MAX < 1 then
            diag.ERROR_MAX = 8
        end
        diag.error_ring[#diag.error_ring + 1] = text
        while #diag.error_ring > diag.ERROR_MAX do
            table.remove(diag.error_ring, 1)
        end
    end)
end

function diag.install_error_handler()
    local ok, installed = pcall(function()
        local set_h = rawget(_G, "seterrorhandler")
        local get_h = rawget(_G, "geterrorhandler")
        if type(set_h) ~= "function" then
            return false
        end
        if diag._error_handler_installed == true then
            return true
        end
        local prev
        if type(get_h) == "function" then
            local ok_get, cur = pcall(get_h)
            if ok_get and type(cur) == "function" then
                prev = cur
            end
        end
        diag._prev_error_handler = prev
        local function chained(msg)
            pcall(function()
                diag.record_error(msg)
            end)
            if type(prev) == "function" then
                pcall(prev, msg)
            end
        end
        diag._chained_handler = chained
        local ok_set = pcall(set_h, chained)
        if ok_set then
            diag._error_handler_installed = true
            return true
        end
        return false
    end)
    if ok and installed == true then
        return true
    end
    return false
end

function diag.uninstall_error_handler()
    local ok, restored = pcall(function()
        if diag._error_handler_installed ~= true then
            return false
        end
        local set_h = rawget(_G, "seterrorhandler")
        if type(set_h) ~= "function" then
            diag._error_handler_installed = false
            return false
        end
        local prev = diag._prev_error_handler
        if type(prev) == "function" then
            pcall(set_h, prev)
        end
        diag._error_handler_installed = false
        diag._prev_error_handler = nil
        diag._chained_handler = nil
        return true
    end)
    if ok and restored == true then
        return true
    end
    return false
end

local function error_lines()
    local ring = read(diag, "error_ring")
    if type(ring) ~= "table" or #ring == 0 then
        -- F1 (deep audit 2026-10-19): an empty ring means two different things and
        -- the report must say which one it is. With the chained handler installed,
        -- "none" means nothing threw; without it, nothing could have been observed
        -- at all - a false negative that reads exactly like a clean session.
        if read(diag, "_error_handler_installed") == true then
            return { PREFIX .. " errors none (handler installed, nothing thrown)" }
        end
        return { PREFIX .. " errors not observed (no error handler installed)" }
    end
    local out = {}
    for i = 1, #ring do
        local msg = ring[i]
        if type(msg) ~= "string" then
            msg = "?"
        end
        out[#out + 1] = PREFIX .. " errors [" .. tostring(i) .. "]=" .. msg
    end
    return out
end

-- Append a section inside the outer cap: fits whole, otherwise fits what remains
-- and closes with an explicit +N count line (never a silent cut).
local function append_section(out, section_lines, cap, label)
    if type(out) ~= "table" or type(section_lines) ~= "table" or #section_lines == 0 then
        return
    end
    if type(cap) ~= "number" then
        return
    end
    local remaining = cap - #out
    if remaining <= 0 then
        return
    end
    if #section_lines <= remaining then
        for i = 1, #section_lines do
            out[#out + 1] = section_lines[i]
        end
        return
    end
    if remaining == 1 then
        out[#out + 1] = PREFIX ..
        " " .. label .. " +" .. tostring(#section_lines) .. " more (cap " .. tostring(cap) .. ")"
        return
    end
    for i = 1, remaining - 1 do
        out[#out + 1] = section_lines[i]
    end
    out[#out + 1] = PREFIX ..
    " " .. label .. " +" .. tostring(#section_lines - (remaining - 1)) .. " more (cap " .. tostring(cap) .. ")"
end

--=========================================================================================
-- Public entry point
--=========================================================================================
-- st.diag.report(self, verbose): print the report. Never throws, never writes. Each line
-- is built under its own pcall, so one unreadable field can only cost its own line.
-- Verbose adds flags/modules/ticks/secrets plus the power-bar line, the per-hand BAR STATE
-- section, the guard-quarantine line, the ids section (wanted-id resolution) and the error
-- ring (newest last); every section respects MAX_LINES with an explicit +N count line when
-- the cap binds. Login (non-verbose) stays one line.
function diag.report(self, verbose)
    local ok, lines = pcall(function()
        local out = {}
        local built, line = pcall(config_line, self)
        out[#out + 1] = built and line or (PREFIX .. " config unavailable")
        if verbose then
            local flags_ok, flags = pcall(flags_line, self)
            out[#out + 1] = flags_ok and flags or (PREFIX .. " flags unavailable")
            local modules_ok, modules = pcall(modules_line, self)
            out[#out + 1] = modules_ok and modules or (PREFIX .. " modules unavailable")
            local ticks_ok, ticks = pcall(ticks_line)
            out[#out + 1] = ticks_ok and ticks or (PREFIX .. " ticks unavailable")
            local secrets_ok, secrets = pcall(secrets_line)
            out[#out + 1] = secrets_ok and secrets or (PREFIX .. " secrets unavailable")
            local cap_inner = tonumber(diag.MAX_LINES) or DEFAULT_MAX_LINES
            -- Per-hand bar state: the lines that make a SILENT bar fault visible (a bar
            -- that is unbuilt/hidden/unticked/dimmed/stalled with nothing thrown). Capped
            -- through the same append_section as the ids/errors tails, with an explicit +N
            -- count line when the cap binds - never a silent cut.
            local bars_ok, bars = pcall(bar_lines, self)
            if bars_ok and type(bars) == "table" then
                local ok_app = pcall(append_section, out, bars, cap_inner, "bars")
                if not ok_app then
                    out[#out + 1] = PREFIX .. " bars unavailable"
                end
            else
                out[#out + 1] = PREFIX .. " bars unavailable"
            end
            -- The power bar: one fixed line right after the bar block, so an
            -- orphaned/disabled/mis-anchored power bar can never be confused with one
            -- that is simply not there (P4-1).
            local power_ok, power = pcall(power_line, self)
            out[#out + 1] = power_ok and power or (PREFIX .. " power unavailable")
            -- The guard quarantine: one line naming every throwing/quarantined site, so a
            -- dead per-tick subsystem is attributable instead of a bare total (P4-2).
            local quarantine_ok, quarantine = pcall(quarantine_line, self)
            out[#out + 1] = quarantine_ok and quarantine
                or (PREFIX .. " quarantine unavailable")
            local ids_ok, ids = pcall(ids_lines)
            if ids_ok and type(ids) == "table" then
                local ok_app = pcall(append_section, out, ids, cap_inner, "ids")
                if not ok_app then
                    out[#out + 1] = PREFIX .. " ids unavailable"
                end
            else
                out[#out + 1] = PREFIX .. " ids unavailable"
            end
            local err_ok, errs = pcall(error_lines)
            if err_ok and type(errs) == "table" then
                pcall(append_section, out, errs, cap_inner, "errors")
            end
        end
        return out
    end)
    if not ok or type(lines) ~= "table" then
        print_line(PREFIX .. " report failed (see the Lua error log)")
        return
    end
    local cap = tonumber(diag.MAX_LINES) or DEFAULT_MAX_LINES
    for i = 1, #lines do
        if i > cap then
            break
        end
        print_line(lines[i])
    end
end
