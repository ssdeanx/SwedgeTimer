--=========================================================================================
-- Hunter visual set: the cast bar above the ranged bar (a live cast with its name,
-- progress, latency end-slice and no-clip tint, else the hidden Auto Shot window), the
-- 4-state range helper strip, the Rapid Fire aura bar and the aspect icon.
--
-- Ported from the read-only reference SuperSwingTimer-WoW:
--   cast bar + window label    SuperSwingTimer_UI.lua:943-1095 (frame 673-762)
--   hidden cast window         SuperSwingTimer_UI.lua:418-428
--   no-clip tint               SuperSwingTimer_UI.lua:858-886
--   latency end-slice          SuperSwingTimer_UI.lua:890-941
--   cast-bar visibility        SuperSwingTimer_UI.lua:459-491
--   movement-safe cast zone    SuperSwingTimer_UI.lua:204-225 (IsRangedCastWindowSafe),
--                              805-850 (the overlay + threshold marker)
--   pet badges                 SuperSwingTimer_ClassMods.lua:6224-6385 (the tracked-icon
--                              pattern: icon + countdown + stacks + gold glow last 4 s)
--   range helper               SuperSwingTimer_ClassMods.lua:5538-5701
--   Rapid Fire bar             SuperSwingTimer_ClassMods.lua:5879-6024
--   aspect icon                SuperSwingTimer_ClassMods.lua:6026-6135
--   colours / heights          SuperSwingTimer_Constants.lua:160-167, 970-978, 1010
--
-- The pure maths live in hunter_window.lua (range_state, cast_bar_display,
-- latency_slice_fraction, clip_tint, cast_window, hidden_window, is_cast_safe,
-- time_until_next_shot); every timestamp here is in the api.get_time() domain. The
-- frames are created from the hunter class module's post_init (out of combat; a
-- creation that lands under combat lockdown is deferred to the next per-frame tick) and
-- driven by the class module's on_bar_update hook from the ranged bar while that bar is
-- visible, plus by the hunter hook installed on the hand's anchor frame below (HU-37) on
-- every frame where the ranged bar's own tick cannot run: main.lua's activity gate hides
-- the bar while the hand is idle, and a hidden frame runs no OnUpdate - so without that
-- hook a Steady Shot / Volley cast with Auto Shot off had no cast bar at all. The widgets
-- parent to the anchor frame, but every anchor and width is still keyed to the ranged bar
-- frame. The
-- cast bar anchors above the ranged bar (UIParent centre when no ranged bar frame exists
-- at all), and the whole set is a silent no-op while the ranged hand is disabled, so it
-- never shows on clients without a ranged swing (Retail).
--
-- The melee bars are pinned under the ranged bar at its width on request (2026-10-27:
-- "mh/oh should be small/thin ... same width as ranged bar and under it"). The anchor
-- target is the ranged bar itself, never the cast bar, so the Auto Shot hidden-window
-- face cannot move them; the 2026-10-25 "mixed up" regression came from the old
-- cast-bar-gated re-anchor. See apply_melee_stack below.
--=========================================================================================
local addon_name, st = ...
local LSM = LibStub("LibSharedMedia-3.0")
local api = st.api

st.hunter_ui = st.hunter_ui or {}
local ui = st.hunter_ui

-- Error-isolation labels for the per-subfeature guard sites registered in ui.update.
st.guard.label("hunter_ui", "Hunter UI")

--=========================================================================================
-- Constants (reference values in the comments)
--=========================================================================================
local CAST_BAR_GAP = 2                     -- HUNTER_CAST_BAR_GAP, Constants:162
local MELEE_STACK_GAP = 2                  -- gap between the ranged bar and the thin melee stack
local RANGE_HELPER_GAP = 3                 -- HUNTER_RANGE_HELPER_GAP, ClassMods.lua:5533
local RANGE_HELPER_WIDTH = 7               -- HUNTER_RANGE_HELPER_WIDTH, Constants:163
-- Sweet-spot band, expressed in exact yards (R3, 2026-10-21). The reference's index-3
-- CheckInteractDistance probe is the trade band at ~10 yd ("just outside melee"), so the
-- band is 5 < yards <= 10. 5 is main.lua's RF_MELEE_RANGE (the library's 5 yd item
-- ladder; see main.lua's range section) and the lower bound keeps a 4 yd reading with a
-- dead melee spell probe from being labelled "sweet". CheckInteractDistance is gone
-- from this file (protected on TBC Anniversary; compat exposes no wrapper at all).
-- Blizzard calls it only from secure popup code (UnitPopupSharedUtils.lua:194,
-- classic_anniversary); the addon block is the 2026-10-21 in-client
-- ADDON_ACTION_BLOCKED log, not a documented restriction.
local RANGE_HELPER_MELEE_RANGE = 5
local RANGE_HELPER_SWEET_SPOT = 10
local RAPID_FIRE_SPELL_ID = 3045           -- RAPID_FIRE_SPELL_ID, ClassMods.lua:5880
local RAPID_FIRE_FALLBACK_DURATION = 15    -- RAPID_FIRE_DURATION, ClassMods.lua:5882
local RAPID_FIRE_BAR_HEIGHT = 4            -- HUNTER_RAPID_FIRE_BAR_HEIGHT, Constants:167
local RAPID_FIRE_SCAN_INTERVAL = 0.1       -- rapidFireUpdateInterval, ClassMods.lua:5884
local ASPECT_SCAN_INTERVAL = 0.2           -- HUNTER_ASPECT_UPDATE_INTERVAL, ClassMods.lua:6114
local ASPECT_ICON_SIZE = 20                -- icon size (reference sized it to the strip)
local AURA_SCAN_LIMIT = 40                 -- reference aura scans, ClassMods.lua:5917
local AUTO_SHOT_ID = 75                    -- the Auto Shot spell (Constants:170)
local WING_CLIP_ID = 2974                  -- Wing Clip (Constants:172)
local RAPTOR_STRIKE_ID = 2973              -- the melee-range fallback token
local AUTO_SHOT_LABEL_KEY = "auto_shot"
local CAST_BAR_FALLBACK_HEIGHT = 15        -- HUNTER_CAST_BAR_HEIGHT, Constants:160
-- Width used only when no ranged bar exists to size the cast bar against (the fallback
-- anchor below); every healthy client builds a ranged bar for hunters.
local CAST_BAR_FALLBACK_WIDTH = 200
local CAST_BAR_FALLBACK_COLOR = {0.35, 0.65, 0.95, 1.0}   -- hunterCastBar, Constants:970
local RAPID_FIRE_BAR_COLOR = {0.15, 0.85, 0.45, 0.85}     -- rapidFireBar, Constants:1010
-- autoShotUnsafe {1, 0, 0, 0.4} with the reference's alpha clamp (0.4 * 0.6 -> 0.24),
-- SuperSwingTimer_UI.lua:918-921.
-- One visual language for the cast window (operator order 2026-10-28: "update the
-- other bars colors/alpha so they are in sync"): the safe face is white and the
-- unsafe face is red, at the same alphas on the zone and on the cast bar's own
-- overlay. The latency end-slice is the same red at the same alpha.
local LATENCY_SLICE_COLOR = {1, 0, 0, 0.4}
local RANGE_STATE_COLORS = {               -- hunterRange*, Constants:971-974
    melee = {0.20, 0.85, 0.25, 1},
    sweet_spot = {0.98, 0.82, 0.18, 1},
    ranged = {0.20, 0.55, 1.00, 1},
    out_of_range = {0.50, 0.50, 0.50, 1},
}
local CLIP_TINT_COLORS = {                 -- clipSafe / clipZone, Constants:975-976
    -- Same white/red pair and the same alphas as the Auto Shot zone (they describe
    -- the same window: safe = white, unsafe = red).
    clipSafe = {1, 1, 1, 0.55},
    clipZone = {1, 0, 0, 0.4},
}
-- Aspect of the Hawk (both ranks), Cheetah, Monkey, Pack, Wild, Viper, Beast
-- (ClassMods.lua:6026-6035).
local ASPECT_SPELL_IDS = {
    [13165] = true, [27044] = true, [5118] = true, [13163] = true,
    [13159] = true, [20190] = true, [34074] = true, [13171] = true,
}
-- Bestial Wrath (wowhead TBC spell 19574: 18 s buff, 2 min cooldown - the badge shows
-- the buff's duration, never the cooldown) and Frenzy Effect (wowhead TBC/WotLK spell
-- 19615: the pet's 8 s, 30% attack-speed buff; stacks up to 3, the community-tracked
-- BM pattern). Id-first matching with the localized-name fallback resolved from the
-- client's own spell data; an id missing from a client simply never matches, so the
-- badge stays inert there.
local BW_SPELL_ID = 19574
local FRENZY_EFFECT_ID = 19615
-- Badge geometry and cadence: same 20 px as the aspect icon, aura scans throttled to
-- the aspect cadence, gold glow inside the final 4 s (the reference glow window,
-- ClassMods.lua:6363-6372).
local BADGE_ICON_SIZE = 20
local BADGE_SCAN_INTERVAL = 0.2
local BADGE_GLOW_WINDOW = 4
-- The reference pulses the glow with a sine (ClassMods.lua:6366-6370); a static alpha
-- at the pulse's midpoint is used here instead - same signal, no per-frame colour
-- churn (documented deviation in the build-out report).
local BADGE_GLOW_COLOR = {1, 0.85, 0, 0.35}
-- Auto Shot cast window: the final 0.5 s of the ranged swing, at the END of the bar.
-- The width is the client's cast window and is NEVER widened by latency (operator
-- ruling 2026-10-22: latency is why a Steady Shot cast may land inside the zone, not
-- extra zone). The repaint stays: WHITE when stopping here is safe (stopped at or
-- before the window opened), red while moving through it or after a late stop.
-- Operator order 2026-10-28: the safe face is white, not green, and carries a little
-- more alpha - "so its easier to see if it landed in zone or not".
local CAST_ZONE_SAFE = {1, 1, 1, 0.55}
local CAST_ZONE_UNSAFE = {1, 0, 0, 0.4}
local CAST_ZONE_MARKER_WIDTH = 3            -- the reference's threshold marker (UI.lua:834)
-- Target-of-target warning (H1, bench/competitor_gaps_2026-10-19.md §Hunter): HST's
-- "target warning state ... when your target's target is you", as a red label above
-- the cast bar. Option-gated nil = off (hunter_target_warning_enabled strictly true
-- shows it; the options pass wires the default); an unknown state hides, so the label
-- only ever shows on an explicit true from ST.HUNTER.get_target_warning.
local TARGET_WARNING_TEXT = ">> TARGETING YOU <<"
local TARGET_WARNING_COLOR = {1, 0.15, 0.15, 1}
local TARGET_WARNING_GAP = 4
local TARGET_WARNING_TEXT_SIZE = 12
-- The anchor hook's own failure budget (H3 discipline, the power_bar/weave_range
-- pattern): after this many throwing ticks the hook gives up and the set is hidden
-- instead of spraying the client's error handler every frame. The value matches
-- guard.lua's shared quarantine threshold; the per-subfeature sites keep their own
-- counters there.
local TICK_QUARANTINE_THROWS = 25

--=========================================================================================
-- Helpers
--=========================================================================================

-- Raw world latency in seconds: the same basis the swing maths and the shaman/paladin
-- helpers consume.
local function world_latency_seconds(self)
    return ((self.latency and self.latency.world_ms) or 0) / 1000
end

-- Effective visibility (a hidden parent hides its children; the widgets below now hang
-- off the hand's anchor frame, so the ranged bar's own Hide() has to be read here).
local function frame_visible(frame)
    if not frame then
        return false
    end
    if frame.IsVisible then
        return frame:IsVisible() == true
    end
    return frame:IsShown() == true
end

-- Whether the hunter's ranged bar is usable right now: the ranged hand state exists and
-- the ranged hand is enabled. A hunter without a ranged weapon reads false, and so does
-- the Retail client, where UnitRangedDamage does not exist, so no ranged weapon is ever
-- detected. Everything in this module is a silent no-op while false.
--
-- The ACTIVITY gate is deliberately not part of this answer (main.lua's hand_is_in_use):
-- the set must keep painting while the activity gate hides the bar (HU-37). The CONFIG
-- half of the visibility rule is ranged_ui_allowed below.
local function ranged_bar_ready(self)
    return self.ranged ~= nil and self:bar_is_enabled("ranged") == true
end

-- The CONFIGURED half of the ranged bar's visibility (HU-37): the class/spec/hand enable
-- flags and, while the bar frame is hidden, the hand's own show rule - i.e. main.lua's
-- handle_bar_visibility MINUS the activity gate. The visual set is allowed to ignore
-- "the hand is idle", but it must never surface anything the configuration keeps hidden
-- (class switched off, a spec gate, a show rule such as "in combat only" during the
-- idle out-of-combat state).
--
-- The show-rule leg is evaluated only while the bar frame is NOT visible: a bar tick
-- means the bar is visible, and main.lua only shows a hand after the same rule passed,
-- so the answer is already known. Nil-safe: a sandbox that does not model main.lua
-- skips the legs it does not provide.
local function ranged_ui_allowed(self, db)
    if type(db) == "table" and db.class_enabled == false then
        return false
    end
    local check = self.check_bar_enable_settings
    if type(check) == "function" and check(self, db, "ranged") ~= true then
        return false
    end
    if not frame_visible(ui.ranged_frame) then
        local cond = self.hand_show_condition_met
        if type(cond) == "function" then
            local hand_db = self:get_hand_table("ranged")
            if type(hand_db) == "table" and cond(self, "ranged", hand_db) == false then
                return false
            end
        end
    end
    return true
end

-- Whether the hunter melee stack is on. Nil-safe: only an explicit false turns it
-- off, so a profile saved before the key existed reads the shipped ON behaviour.
local function melee_stack_on(self)
    local db = self:get_class_table()
    return type(db) == "table" and db.hunter_melee_stack ~= false
end

-- Is a melee hand built? HU-22 lazy bars means an unequipped/disabled hand has no
-- frames; a sandbox without bar_is_built is treated as built (its frames are the
-- fixture's own contract).
local function hand_is_built(self, hand)
    if type(self.bar_is_built) == "function" then
        return self:bar_is_built(hand) == true
    end
    local state = self[hand]
    return type(state) == "table" and state.anchor_frame ~= nil
end

--=========================================================================================
-- HU-37: the always-running hunter tick
--
-- The set used to be parented to the ranged bar frame and ticked only from its OnUpdate.
-- main.lua's activity gate hides that frame while the hand is idle (no Auto Shot
-- auto-repeat and no shot receipt inside the window), and a hidden frame runs no
-- OnUpdate - so a Steady Shot / Volley cast with Auto Shot off painted no cast bar at
-- all. The tick now rides the hand's ANCHOR frame: bars.lua's per-hand top-level frame
-- and the one hide_bar() never hides (it hides the bar frame and the hiding proxy), so
-- it stays shown for as long as the hand exists. The hook is hunter-installed and
-- hunter-owned; the host is that existing per-hand frame rather than a new one because
-- the build-time frame census (tests/bars_state.lua) pins the hunter widget count and is
-- outside this lane's write scope - the lazy-badge precedent: do not move that pin.
--
-- The widgets parent to the same anchor frame (so they render while the bar frame is
-- hidden) but keep EVERY anchor and width against the ranged bar frame. To render
-- identically, the host is put on the bar frame's own strata/level BEFORE the widgets
-- are created: a child created afterwards then defaults to bar-level + 1 (what it had as
-- the bar's child) and inherits the bar's strata. The ranged bar itself is never shown
-- from here: the activity gate owns its visibility.
--
-- Exactly one source per frame: while the ranged bar is visible and carries its own
-- OnUpdate, that tick drives the set (the pre-2026-10-28 source) and the anchor tick
-- defers; the anchor tick takes every frame the bar's tick cannot run.
--=========================================================================================

-- Is the ranged bar's own tick going to run this frame? True only when the bar frame is
-- actually visible AND carries its OnUpdate (the pre-fix source). A visible bar without
-- the script - a sandbox build, or frames that came up without bring_up_hand - leaves
-- the frame to the anchor tick rather than going blank.
local function ranged_tick_is_live()
    local frame = ui.ranged_frame
    if not frame_visible(frame) then
        return false
    end
    if type(frame.GetScript) ~= "function" then
        return false
    end
    return frame:GetScript("OnUpdate") ~= nil
end

-- Mirror the ranged bar's effective layering onto the tick host. The widgets used to
-- inherit the bar's strata/level as its children; the profile-wide draw_level /
-- frame_strata settings can move that frame after the build, so the host follows it
-- (one compare per frame, a Set only on a real change). In ui.build this runs BEFORE
-- the widgets exist, because a child's default frame level is assigned at creation.
local function sync_tick_host_layering()
    local host = ui.tick_host
    local bar = ui.ranged_frame
    if not host or not bar then
        return
    end
    if type(bar.GetFrameStrata) == "function" then
        local strata = bar:GetFrameStrata()
        if strata ~= nil and strata ~= ui.host_strata then
            ui.host_strata = strata
            if type(host.SetFrameStrata) == "function" then
                host:SetFrameStrata(strata)
            end
        end
    end
    if type(bar.GetFrameLevel) == "function" then
        local level = bar:GetFrameLevel()
        if type(level) == "number" and level ~= ui.host_level then
            ui.host_level = level
            if type(host.SetFrameLevel) == "function" then
                host:SetFrameLevel(level)
            end
        end
    end
end

-- Claim the hand's anchor frame as the tick host: put it on the ranged bar's layering
-- and install the hunter hook once. Returns nil when the hand has no anchor frame (no
-- built hand); in that degenerate build the ranged bar's own tick stays the only source,
-- which is exactly the pre-fix wiring.
local function claim_tick_host(self)
    local anchor = self.ranged and self.ranged.anchor_frame
    if not anchor then
        return nil
    end
    ui.tick_host = anchor
    sync_tick_host_layering()
    if not ui.tick_installed then
        ui.tick_installed = true
        anchor:SetScript("OnUpdate", function(_, elapsed)
            ui.poll(ui.owner)
        end)
    end
    return anchor
end

-- One anchor-tick frame: keep the host on the bar's layering, then update the set
-- unless the ranged bar's own tick is going to run this frame.
local function tick_once(self)
    sync_tick_host_layering()
    if ranged_tick_is_live() then
        return
    end
    ui.update(self)
end

-- The host's guarded entry (H3 discipline, the power_bar/weave_range pattern): a
-- throwing tick must never break the OnUpdate chain. The per-subfeature sites inside
-- ui.update already isolate their own throws, so this catches only the entry's own
-- failure path; after TICK_QUARANTINE_THROWS the hook gives up and the set hides.
function ui.poll(self)
    if not self then
        return
    end
    local ok, err = pcall(tick_once, self)
    if ok then
        ui.tick_failures = nil
        return
    end
    local failures = (ui.tick_failures or 0) + 1
    ui.tick_failures = failures
    ui.tick_last_error = tostring(err)
    if failures == 1 and type(st.utils) == "table"
        and type(st.utils.print_msg) == "function" then
        -- Best-effort chat line: a missing/broken chat frame must never re-break the
        -- OnUpdate chain this guard exists to protect.
        pcall(st.utils.print_msg,
            "Hunter UI update failed and was isolated: " .. tostring(err))
    end
    if failures >= TICK_QUARANTINE_THROWS then
        if ui.tick_host and type(ui.tick_host.SetScript) == "function" then
            ui.tick_host:SetScript("OnUpdate", nil)
        end
        ui.hide_all(self)
    end
end

-- Pin the thin melee bars under the ranged bar at its width. Runs on the ranged and
-- mainhand ticks (the ranged tick may be stopped while the bar is hidden). The anchor
-- target is the RANGED BAR, never the cast bar: the 2026-10-25 regression happened
-- because the old re-anchor was gated on cast-bar visibility, which is true for the
-- Auto Shot window in every ranged cycle. Here the position is the requested layout,
-- not a transient state, so the window cannot move it.
function ui.apply_melee_stack(self)
    if not melee_stack_on(self) or not ranged_bar_ready(self) then
        return
    end
    local ranged_state = self.ranged
    local ranged_anchor = ranged_state and ranged_state.anchor_frame
    local parent = ranged_anchor and ranged_anchor.bar_frame
    if parent == nil then
        return
    end
    local ranged_db = self:get_hand_table("ranged")
    local width = ranged_db and ranged_db.bar_width
    if type(width) ~= "number" or width <= 0 then
        -- A sandbox/flavor without the db width still has the live frame width.
        width = parent.GetWidth and parent:GetWidth()
    end
    if type(width) ~= "number" or width <= 0 then
        return
    end
    local configure = self.configure_bar_size_and_positions
    for _, hand in ipairs({ "mainhand", "offhand" }) do
        local state = self[hand]
        local anchor = state and state.anchor_frame
        if anchor ~= nil and hand_is_built(self, hand) then
            local bar_frame = anchor.bar_frame
            local current_width = bar_frame and bar_frame.GetWidth and bar_frame:GetWidth()
                or anchor.GetWidth and anchor:GetWidth()
            -- Half a UI unit of tolerance (2026-10-28, mainhand report: the thin bar
            -- sat at 100% and never animated). An exact compare re-ran the resize - and
            -- with it the fill's width reset - on any float/scale noise, once per tick.
            -- A real width change is whole units, so this tolerance cannot hide one.
            local matched = type(current_width) == "number" and current_width > 0
                and math.abs(current_width - width) <= 0.5
            if not matched and type(configure) == "function" then
                -- Resize WITHOUT writing bar_width: the user's saved width returns
                -- when the stack is switched off (configure with no override).
                configure(self, hand, width)
            end
            local point, relative, relative_point, x, y = anchor:GetPoint(1)
            if point ~= "TOPLEFT" or relative ~= parent
                or relative_point ~= "BOTTOMLEFT" or x ~= 0 or y ~= -MELEE_STACK_GAP then
                anchor:ClearAllPoints()
                anchor:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -MELEE_STACK_GAP)
            end
            parent = anchor
        end
    end
end

-- Turn the stack off: restore each built melee hand's own width and saved LibWindow
-- position. Only the geometry is restored; no saved key is written by either path.
function ui.restore_melee_layout(self)
    if type(self.configure_bar_size_and_positions) ~= "function" then
        return
    end
    for _, hand in ipairs({ "mainhand", "offhand" }) do
        if hand_is_built(self, hand) then
            self:configure_bar_size_and_positions(hand)
        end
    end
end

-- Resolve a spell id to the running client's token for range probes. The rule is
-- the operator's name-vs-id matrix, one family gate at a time: Classic Era (SoD
-- included), Forever, Cata/Mists/Retail and the unknown fallback take the numeric
-- ID; TBC Anniversary and Wrath/Titanforge take the localized NAME first and the
-- ID as the approved fallback (HU-34: "i never banned fallback to ids"). The
-- display name is the SECOND return so Era still has its label while probing by
-- id. A cold spell cache on a name family therefore degrades to the id, never to
-- a nil token.
local function resolve_spell(spell_id)
    local name = api.GetSpellInfo(spell_id)
    if type(name) ~= "string" then
        name = nil
    end
    if st.family == "TBC" or st.family == "WRATH" then
        if type(api.get_spell_query) == "function" then
            return api.get_spell_query(name, spell_id) or spell_id, name
        end
        return name or spell_id, name
    end
    return spell_id, name
end

--=========================================================================================
-- Frame construction (called once from ST.HUNTER.post_init, out of combat)
--
-- HU-37: each creator takes the CREATION parent (the hand's anchor frame, which the
-- activity gate never hides) separately from the ANCHOR target (the ranged bar frame).
-- The widgets render under the anchor while the activity gate hides the bar; every
-- SetPoint/width below still reads exactly what it read when they were the bar's
-- children.
--=========================================================================================
local function create_cast_bar(parent, ranged_frame, texture, font_path, db_hand)
    local frame = CreateFrame("Frame", addon_name .. "HunterCastBar",
        parent or ranged_frame or UIParent)
    frame:SetHeight(CAST_BAR_FALLBACK_HEIGHT)
    if ranged_frame then
        frame:SetPoint("BOTTOMLEFT", ranged_frame, "TOPLEFT", 0, CAST_BAR_GAP)
        frame:SetPoint("BOTTOMRIGHT", ranged_frame, "TOPRIGHT", 0, CAST_BAR_GAP)
    else
        -- No ranged bar on this client: keep the bar anchored and usable at the screen
        -- centre instead of leaving it unanchored (the reference simply hides it, UI.lua
        -- 676-681; this layout still sizes it so the widget stays visible on demand).
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetWidth(CAST_BAR_FALLBACK_WIDTH)
    end
    frame:SetFrameLevel(ranged_frame and ranged_frame:GetFrameLevel() + 2 or 1)
    frame:EnableMouse(false)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.8)

    -- The fill keeps the configured cast-bar colour and is never repainted by the Auto
    -- Shot window colours (reference UI.lua:858-860).
    frame.bar = frame:CreateTexture(nil, "ARTWORK")
    frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    if texture then
        frame.bar:SetTexture(texture)
    end

    -- No-clip tint: a translucent green/red overlay shown for live casts only.
    frame.tint = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.tint:SetAllPoints(frame.bar)
    frame.tint:Hide()

    -- Latency end-slice: right-anchored, width set per frame.
    frame.latency = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    frame.latency:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.latency:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.latency:SetColorTexture(unpack(LATENCY_SLICE_COLOR))
    frame.latency:Hide()

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    -- The font goes on BEFORE the first SetText: a FontString with no font throws
    -- "Font not set" on a real client. The chain (the LSM path, then
    -- STANDARD_TEXT_FONT, then the classic client font) never throws and always
    -- leaves a font that exists.
    st.utils.apply_font(frame.text, font_path, db_hand.text_size or 12, "")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetTextColor(1, 1, 1, 1)
    frame.text:SetShadowColor(0, 0, 0, 1)
    frame.text:SetShadowOffset(1, -1)

    frame:Hide()
    return frame
end

local function create_range_helper(parent, ranged_frame)
    local helper = CreateFrame("Frame", addon_name .. "HunterRangeHelper",
        parent or ranged_frame or UIParent)
    helper:SetWidth(RANGE_HELPER_WIDTH)
    helper.tex = helper:CreateTexture(nil, "ARTWORK")
    helper.tex:SetAllPoints()
    helper.tex:SetColorTexture(1, 1, 1, 1)
    helper:Hide()
    return helper
end

local function create_rapid_fire_bar(parent, ranged_frame, texture, font_path, text_size)
    local bar = CreateFrame("StatusBar", addon_name .. "HunterRapidFireBar",
        parent or ranged_frame or UIParent)
    bar:SetHeight(RAPID_FIRE_BAR_HEIGHT)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:EnableMouse(false)
    if texture then
        bar:SetStatusBarTexture(texture)
    end
    bar:SetStatusBarColor(unpack(RAPID_FIRE_BAR_COLOR))

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Whole-seconds label beside the bar (reference ClassMods.lua:5968-5974).
    bar.label = bar:CreateFontString(nil, "OVERLAY")
    -- The label is written per frame, so it carries a font from the start: a
    -- FontString with no font throws "Font not set" on the first SetText.
    st.utils.apply_font(bar.label, font_path, text_size, "")
    bar.label:SetPoint("LEFT", bar, "RIGHT", 2, 0)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetTextColor(unpack(RAPID_FIRE_BAR_COLOR))
    bar:Hide()
    return bar
end

local function create_aspect_icon(parent)
    local icon = CreateFrame("Frame", addon_name .. "HunterAspectIcon",
        parent or UIParent)
    icon:SetSize(ASPECT_ICON_SIZE, ASPECT_ICON_SIZE)
    icon:EnableMouse(false)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetDrawLayer("OVERLAY", -1)
    icon.border:SetColorTexture(0, 0, 0, 0.65)
    icon.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    icon:Hide()
    return icon
end

local function create_cast_zone(ranged_frame)
    -- The movement-safe cast zone lives on the ranged bar's visuals frame (the same
    -- surface the paladin twist band uses): a texture on the bar frame itself would
    -- render under the child visuals frame. Without a visuals frame (degenerate build)
    -- both textures stay nil and the update is a no-op. The zone is right-anchored and
    -- width-driven; the marker is a thin dark line at the window boundary.
    --
    -- HU-37: this one overlay stays on the bar's surface (a texture cannot be re-parented)
    -- and deliberately so. Its own update gate only paints inside a LIVE ranged cycle
    -- (update_cast_zone), and a live cycle always implies the activity gate shows the bar
    -- for that cycle's receipt window - so a zone painted while the bar is hidden is never
    -- observable today. It still TICKS from the anchor hook with the rest of the set (its
    -- update runs and hides itself when there is no live cycle).
    local parent = ranged_frame and ranged_frame.visuals_frame
    if not parent then
        return nil, nil
    end
    local zone = parent:CreateTexture(nil, "OVERLAY")
    zone:SetDrawLayer("OVERLAY", -2)
    zone:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    zone:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    zone:SetWidth(0)
    zone:Hide()
    local marker = parent:CreateTexture(nil, "OVERLAY")
    marker:SetDrawLayer("OVERLAY", -1)
    marker:SetColorTexture(0, 0, 0, 1)
    marker:SetWidth(CAST_ZONE_MARKER_WIDTH)
    marker:Hide()
    return zone, marker
end

local function create_target_warning(cast_frame, font_path)
    -- H1 target warning label (see the TARGET_WARNING_* constants): a red text line
    -- above the cast bar, CENTER-fallback when no frame exists to hang it on.
    local parent = cast_frame or UIParent
    local label = parent:CreateFontString(nil, "OVERLAY")
    -- The font goes on BEFORE the text: a FontString with no font throws
    -- "Font not set" on a real client (the label is written once, at creation).
    -- The chain never throws and always leaves a font that exists.
    st.utils.apply_font(label, font_path, TARGET_WARNING_TEXT_SIZE, "OUTLINE")
    label:SetText(TARGET_WARNING_TEXT)
    label:SetTextColor(unpack(TARGET_WARNING_COLOR))
    if cast_frame then
        label:SetPoint("BOTTOM", cast_frame, "TOP", 0, TARGET_WARNING_GAP)
    else
        label:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    label:Hide()
    return label
end

local function create_badge(name, parent, font_path, text_size)
    -- The tracked-icon pattern (reference ClassMods.lua:6224-6279): icon texture with
    -- the standard inset, an additive gold glow overlay, one text. Callers place the
    -- text (BW: the countdown above the icon; Frenzy: the stack count bottom-right).
    local frame = CreateFrame("Frame", addon_name .. name, parent or UIParent)
    frame:SetSize(BADGE_ICON_SIZE, BADGE_ICON_SIZE)
    frame:EnableMouse(false)
    frame.tex = frame:CreateTexture(nil, "ARTWORK")
    frame.tex:SetAllPoints()
    frame.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.glow:SetAllPoints()
    frame.glow:SetColorTexture(unpack(BADGE_GLOW_COLOR))
    if frame.glow.SetBlendMode then
        frame.glow:SetBlendMode("ADD")
    end
    frame.glow:Hide()
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    -- The badge text is written per frame, so it carries a font from the start: a
    -- FontString with no font throws "Font not set" on the first SetText.
    st.utils.apply_font(frame.text, font_path, text_size, "")
    frame.text:SetTextColor(1, 1, 1, 0.95)
    frame.text:Hide()
    frame:Hide()
    return frame
end

function ui.build(self, ranged_frame)
    local db_hand = self:get_hand_table("ranged")
    -- No ranged row means no configuration to build the hunter UI from. Report
    -- "not ready" so ui.init's per-tick retry can pick it up (profile switch),
    -- instead of throwing out of the class hook on a nil field.
    if type(db_hand) ~= "table" then
        return false
    end
    local texture = LSM:Fetch("statusbar", db_hand.bar_texture_key)
    -- The font path is resolved through the shared chain (utils.lua): a key that no
    -- longer resolves (the font lives in another addon's LSM registration) must not
    -- leave a FontString without a font - the fallback chain takes over.
    local font_path = st.utils.fetch_font_path(db_hand.text_font)
    local text_size = db_hand.text_size or 12

    -- HU-37: the tick host is claimed BEFORE the widgets so their default frame levels
    -- (host level + 1) are the bar-child levels they had before, and so the set has a
    -- never-hidden parent from its first frame. The ranged bar frame is still the ANCHOR
    -- target for every widget below. A hand with no anchor frame (degenerate build)
    -- keeps the pre-fix wiring: children of the bar frame, ticked by its own OnUpdate.
    ui.owner = self
    ui.ranged_frame = ranged_frame
    local parent = ui.tick_host or claim_tick_host(self)
    if not parent and ranged_frame then
        parent = ranged_frame
    end
    ui.cast_frame = create_cast_bar(parent, ranged_frame, texture, font_path, db_hand)
    ui.range_helper = create_range_helper(parent, ranged_frame)
    ui.rapid_fire_bar = create_rapid_fire_bar(parent, ranged_frame, texture,
        font_path, text_size)
    ui.aspect_icon = create_aspect_icon(parent)
    -- H1 target warning (option-gated nil = off; text set once, visibility per frame).
    ui.target_warning = create_target_warning(ui.cast_frame, font_path)

    -- Transition state: nil/false means "normal anchors". (The melee stack is stateless:
    -- apply_melee_stack compares the live anchor points each tick, so a toggle-off or a
    -- drag is handled without a cached "was stacked" flag.)
    ui.helper_top = nil
    ui.rf_anchor = nil
    ui.rf_width = nil
    ui.aspect_anchor = nil
    ui.cast_height = nil

    -- Client spell tokens (Era ids; TBC/Wrath localized names with the ids as fallback).
    ui.wing_clip_token = resolve_spell(WING_CLIP_ID)
    ui.raptor_token = resolve_spell(RAPTOR_STRIKE_ID)
    ui.auto_shot_token, ui.auto_shot_name = resolve_spell(AUTO_SHOT_ID)
    local _, rapid_fire_name = resolve_spell(RAPID_FIRE_SPELL_ID)
    ui.rapid_fire_name = rapid_fire_name

    -- Aspect aura matchers: spell ids always, localized names resolved from the
    -- client's own spell data (a localized aura name never matches the English list).
    ui.aspect_names = {}
    ui.aspect_textures = {}
    for spell_id in pairs(ASPECT_SPELL_IDS) do
        local aspect_name, _, icon = api.GetSpellInfo(spell_id)
        if aspect_name then
            ui.aspect_names[aspect_name] = spell_id
            ui.aspect_textures[spell_id] = icon
        end
    end

    -- Movement-safe cast zone (option-gated; nil = off) and the H6 pet badges. The
    -- zone lives on the ranged bar's visuals frame (nil when that is absent, in which
    -- case its update is a no-op). Badge text placement follows the reference: BW's
    -- countdown above the icon, Frenzy's stack count bottom-right.
    ui.cast_zone, ui.cast_zone_marker = create_cast_zone(ranged_frame)
    ui.bw_badge = create_badge("HunterBWBadge", parent, font_path, text_size)
    ui.bw_badge.text:SetPoint("BOTTOM", ui.bw_badge, "TOP", 0, 2)
    ui.bw_badge.text:SetJustifyH("CENTER")
    ui.frenzy_badge = create_badge("HunterFrenzyBadge", parent, font_path, text_size)
    ui.frenzy_badge.text:SetPoint("BOTTOMRIGHT", ui.frenzy_badge, "BOTTOMRIGHT", -1, 1)
    ui.frenzy_badge.text:SetJustifyH("RIGHT")

    -- Badge spell tokens: localized names and icon textures from the client's own data
    -- (the ids stay the primary matcher, so a cold cache only disables the name
    -- fallback and leaves a texture-less badge hidden).
    ui.bw_name, _, ui.bw_texture = api.GetSpellInfo(BW_SPELL_ID)
    ui.frenzy_name, _, ui.frenzy_texture = api.GetSpellInfo(FRENZY_EFFECT_ID)
    if ui.bw_texture then
        ui.bw_badge.tex:SetTexture(ui.bw_texture)
    end
    if ui.frenzy_texture then
        ui.frenzy_badge.tex:SetTexture(ui.frenzy_texture)
    end

    -- Transition caches for the new widgets (nil = "no change seen yet").
    ui.zone_width = nil
    ui.zone_left = nil
    ui.zone_safe = nil
    ui.bw_anchor = nil
    ui.frenzy_anchor = nil
    ui.badge_scan_at = nil
    ui.bw_text = nil
    ui.frenzy_text = nil

    ui.ready = true
end

function ui.init(self)
    -- Called from ST.HUNTER.post_init; also retried from the per-frame hook when the
    -- creation was deferred (combat lockdown) or the ranged bar was not ready yet.
    if ui.ready then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if not ranged_bar_ready(self) then
        return
    end
    local ranged_state = self.ranged
    local ranged_frame
    if ranged_state and ranged_state.anchor_frame then
        ranged_frame = ranged_state.anchor_frame.bar_frame
    end
    ui.build(self, ranged_frame)
end

--=========================================================================================
-- Melee bar stack (2026-10-27 operator request)
--=========================================================================================
-- The thin mainhand/offhand bars are pinned directly under the ranged bar at the ranged
-- bar's width (ranged -> MH -> OH). This is a stable layout, not a transient cast-bar
-- state: the anchor target is the ranged bar frame, so the Auto Shot hidden-window face
-- (the old 2026-10-25 regression trigger) cannot move them. The stack is off-switchable
-- (hunter_melee_stack = false) and restores each hand's own width + LibWindow position.
--
-- The reference's UpdateHunterMeleeBarAnchor (SuperSwingTimer_UI.lua:31-44) is not
-- ported: it gated the stack on cast-bar visibility and hid the MH bar at range. This
-- addon deliberately keeps the melee cycle visible for melee weaving; only the geometry
-- policy is adopted.

--=========================================================================================
-- Cast bar
--=========================================================================================

-- Read the live player cast through compat's folding wrapper (a cast first, a channel
-- second). Auto Shot readings are ignored here: they drive the hidden window label
-- instead (reference UI.lua:1030-1043), and a cast without usable bounds cannot drive a
-- progress bar at all.
local function read_live_cast()
    local name, spell_id, cast_start, cast_end = api.UnitCastingSpell("player")
    if not name then
        return nil
    end
    -- Auto Shot exclusion (reference IsAutoShotSpell: id OR name): the older
    -- classic payloads carry no numeric id (compat folds them to nil) and the
    -- build-time name is nil while the spell data has not answered, so either
    -- check alone lets a live Auto Shot reading through as a "cast" instead of
    -- the hidden window. The English fallback covers a cold cache the same way
    -- the reference's `or "Auto Shot"` does.
    local auto_name = ui.auto_shot_name or "Auto Shot"
    if spell_id == AUTO_SHOT_ID or name == auto_name then
        return nil
    end
    if type(cast_start) ~= "number" or type(cast_end) ~= "number" or cast_end <= cast_start then
        return nil
    end
    return name, spell_id, cast_start, cast_end
end

-- The hidden Auto Shot window of the current ranged cycle, cached on the phase-1 ranged
-- state fields (hunter_window.hidden_window; reference UI.lua:394-430). Only an
-- inside window is cached: past and future recompute every tick like the reference
-- (UI.lua:421-426 returns nil without caching outside the window), so the
-- per-frame cost is one pure-arithmetic call until the window opens.
local function get_hidden_window(self, now)
    local ranged = self.ranged
    if not ranged then
        return nil, nil
    end
    local cycle_duration = ranged.synced_duration or ranged.speed
    -- Provenance (see gather_guide_inputs): the cache counts only while it still
    -- ends on the live cycle's end. A ranged re-anchor the hunter sync did not
    -- clear (the engine's START/UPDATE stamps next to the sync's own clears; the
    -- reference clears on every StartSwing) leaves a stale end behind, and the
    -- stale bounds must lose to the live recompute.
    local live_end
    if type(ranged.start) == "number" and type(cycle_duration) == "number"
        and cycle_duration > 0 then
        live_end = ranged.start + cycle_duration
    end
    local start = ranged.hidden_window_start
    local duration = ranged.hidden_window_duration
    if type(start) == "number" and type(duration) == "number" and duration > 0
        and live_end ~= nil and math.abs((start + duration) - live_end) <= 1e-9
        and now >= start and now <= start + duration then
        return start, duration
    end
    ranged.hidden_window_start = nil
    ranged.hidden_window_duration = nil
    if live_end == nil then
        return nil, nil
    end
    local window_start, window_end = st.hunter_window.hidden_window(
        ranged.start, cycle_duration, st.hunter_window.cast_window(world_latency_seconds(self)))
    if not window_start or type(now) ~= "number" or now < window_start or now > window_end then
        -- Outside (past or future): never cache. The reference recomputes a
        -- future window every tick instead of holding it (UI.lua:421-423).
        return nil, nil
    end
    ranged.hidden_window_start = window_start
    ranged.hidden_window_duration = window_end - window_start
    return window_start, window_end - window_start
end

local function hide_cast_bar()
    local frame = ui.cast_frame
    if not frame then
        return
    end
    if frame:IsShown() then
        frame:Hide()
    end
    frame.tint:Hide()
    frame.latency:Hide()
    ui.tint_key = nil
    -- The cast is gone: drop the fill anchor so the next cast re-anchors on its own
    -- first tick instead of inheriting the previous cast's elapsed time.
    ui.cast_key = nil
    ui.cast_anchor = nil
end

local function update_cast_text(mode, name, remaining, spell_id)
    -- One SetText per tenth of a second and per label identity, mirroring the
    -- reference's _lastRemTenth / _lastCastSpellId gates (UI.lua:1075-1095).
    local rem_tenth = math.floor(remaining * 10 + 0.5)
    local key = AUTO_SHOT_LABEL_KEY
    if mode == "cast" then
        key = spell_id or name
    end
    if ui.label_tenth == rem_tenth and ui.label_key == key then
        return
    end
    ui.label_tenth, ui.label_key = rem_tenth, key
    local frame = ui.cast_frame
    if mode == "cast" then
        frame.text:SetText(string.format("%s %.1f", name or "Cast", remaining))
    else
        frame.text:SetText(string.format("Auto Shot %.1f", remaining))
    end
end

function ui.update_cast_bar(self, db, now)
    local frame = ui.cast_frame
    if db.hunter_cast_bar_enabled == false then
        hide_cast_bar()
        return
    end

    -- Height and colour are read live so the options apply without a reload.
    local height = db.hunter_cast_bar_height or CAST_BAR_FALLBACK_HEIGHT
    if ui.cast_height ~= height then
        ui.cast_height = height
        frame:SetHeight(height)
    end
    local color = db.hunter_cast_bar_color or CAST_BAR_FALLBACK_COLOR
    local r = color[1] or color.r or CAST_BAR_FALLBACK_COLOR[1]
    local g = color[2] or color.g or CAST_BAR_FALLBACK_COLOR[2]
    local b = color[3] or color.b or CAST_BAR_FALLBACK_COLOR[3]
    local a = color[4] or color.a or CAST_BAR_FALLBACK_COLOR[4]
    if ui.cast_color_r ~= r or ui.cast_color_g ~= g
        or ui.cast_color_b ~= b or ui.cast_color_a ~= a then
        ui.cast_color_r, ui.cast_color_g, ui.cast_color_b, ui.cast_color_a = r, g, b, a
        frame.bar:SetVertexColor(r, g, b, a)
    end

    local cast_name, cast_spell_id, cast_start, cast_end = read_live_cast()
    local window_start, window_duration = get_hidden_window(self, now)
    local mode = st.hunter_window.cast_bar_display(
        cast_name ~= nil, window_start, window_duration, now)
    if mode == "hidden" then
        hide_cast_bar()
        return
    end

    -- Progress through the active face, clamped like the reference before it is drawn.
    local duration, elapsed
    if mode == "cast" then
        duration = cast_end - cast_start
        -- Fill anchor on OUR clock. The cast's absolute start stamp sits on the client
        -- clock; when that axis sits at any offset from api.get_time(), now - cast_start
        -- is negative and the bar freezes at zero while the label sits on the full
        -- duration - the "bar comes up but does nothing" shape. A cast is identified by
        -- (name, spell id, end stamp); on first sight the anchor is back-dated by the
        -- elapsed the two clocks agree on, or starts now when they do not.
        local cast_key = tostring(cast_name) .. "|" .. tostring(cast_spell_id)
            .. "|" .. tostring(cast_end)
        if ui.cast_key ~= cast_key then
            ui.cast_key = cast_key
            local stamped = now - cast_start
            if type(stamped) == "number" and stamped > 0 and stamped <= duration then
                ui.cast_anchor = now - stamped
            else
                ui.cast_anchor = now
            end
        end
        elapsed = now - (ui.cast_anchor or now)
    else
        ui.cast_key = nil
        ui.cast_anchor = nil
        duration = window_duration
        elapsed = now - window_start
        cast_name = nil
        cast_spell_id = nil
    end
    if elapsed < 0 then
        elapsed = 0
    elseif elapsed > duration then
        elapsed = duration
    end
    local remaining = duration - elapsed
    if mode ~= "cast" then
        -- H1 shot clock: the window face's countdown is the HOLD-seconds kernel over
        -- the same bounds cast_bar_display just matched (the moment the window closes
        -- and the next Auto Shot fires). Falls back to the clamped arithmetic only if
        -- the kernel is absent (a flavor without hunter_window).
        remaining = st.hunter_window.hold_seconds(window_start, window_duration, now)
            or remaining
    end

    local bar_width = frame:GetWidth() or 0
    local progress = 0
    if duration > 0 then
        progress = elapsed / duration
    end
    frame.bar:SetWidth(math.max(1, progress * bar_width))

    -- No-clip tint: live casts only, never the Auto Shot window (its bar keeps the
    -- configured colour, reference UI.lua:858-860).
    local tint_key
    if mode == "cast" then
        local ttl = st.hunter_window.time_until_next_shot(
            now, self.ranged.start, self.ranged.synced_duration or self.ranged.speed, nil)
        if ttl ~= nil then
            local grace = st.hunter_window.STEADY_SHOT_GRACE
            if self.HUNTER and self.HUNTER.get_cast_grace then
                grace = self.HUNTER.get_cast_grace(self, cast_spell_id, cast_name)
            end
            tint_key = st.hunter_window.clip_tint(st.hunter_window.is_cast_safe(
                remaining, ttl, grace, world_latency_seconds(self)))
        end
    end
    local tint = tint_key and CLIP_TINT_COLORS[tint_key]
    if tint then
        if ui.tint_key ~= tint_key then
            ui.tint_key = tint_key
            frame.tint:SetColorTexture(tint[1], tint[2], tint[3], tint[4])
        end
        frame.tint:Show()
    else
        ui.tint_key = nil
        frame.tint:Hide()
    end

    -- Latency end-slice: the final latency_window/duration of the bar (reference
    -- UI.lua:890-941 draws it for the hidden window label too).
    local slice = st.hunter_window.latency_slice_fraction(
        world_latency_seconds(self), duration)
    if slice > 0 then
        frame.latency:SetWidth(slice * bar_width)
        frame.latency:Show()
    else
        frame.latency:Hide()
    end

    update_cast_text(mode, cast_name, remaining, cast_spell_id)

    if not frame:IsShown() then
        frame:Show()
    end
end

--=========================================================================================
-- Auto Shot cast window (red zone; reference UI.lua:204-225, 805-850)
--=========================================================================================
-- The final 0.5 s of the ranged swing, drawn at the END of the bar. Two separate
-- contracts (operator ruling 2026-10-22):
--   width  - the client's cast window, fixed at 0.5 s. Latency is NEVER added: latency
--            is why a Steady Shot cast may land inside the zone without clipping, not
--            extra zone. A cast must still land before the window closes.
--   colour - repainted green when stopping right now is safe (stopped at or before the
--            window opened) and red while still moving through it or after a late stop.
-- Option-gated: hunter_cast_zone_enabled shows it (ships on), and a disabled zone
-- performs no reads at all.
function ui.update_cast_zone(self, db, now)
    local zone = ui.cast_zone
    if not zone then
        return
    end
    local marker = ui.cast_zone_marker
    if db.hunter_cast_zone_enabled ~= true then
        ui.zone_safe = nil
        zone:Hide()
        if marker then
            marker:Hide()
        end
        return
    end
    local ranged = self.ranged
    local cycle_duration = ranged and (ranged.synced_duration or ranged.speed)
    if not (ranged and type(ranged.start) == "number"
        and type(cycle_duration) == "number" and cycle_duration > 0
        and type(now) == "number" and now <= ranged.start + cycle_duration) then
        -- No live ranged cycle: nothing to bound the window with, so the zone hides
        -- rather than guessing (the reference's non-swinging early out).
        ui.zone_safe = nil
        zone:Hide()
        if marker then
            marker:Hide()
        end
        return
    end
    local cast_window = st.hunter_window.cast_window()
    local bar_width = (ui.ranged_frame and ui.ranged_frame:GetWidth()) or 0
    local width = math.min((cast_window / cycle_duration) * bar_width, bar_width)
    if width < 0 then
        width = 0
    end
    local safe = st.hunter_window.is_stopped_position_safe(
        self.is_moving == true, self.last_stopped_moving_at,
        ranged.start, cycle_duration, cast_window)
    if ui.zone_safe ~= safe then
        ui.zone_safe = safe
        local color = safe and CAST_ZONE_SAFE or CAST_ZONE_UNSAFE
        zone:SetColorTexture(color[1], color[2], color[3], color[4])
    end
    if ui.zone_width ~= width then
        ui.zone_width = width
        zone:SetWidth(width)
    end
    -- The threshold marker sits on the window boundary (the reference's markerLeft,
    -- UI.lua:834-841), anchored off the zone's parent so it spans the full bar height.
    local left = bar_width - width - CAST_ZONE_MARKER_WIDTH * 0.5
    if left < 0 then
        left = 0
    end
    if ui.zone_left ~= left then
        ui.zone_left = left
        local parent = ui.ranged_frame and ui.ranged_frame.visuals_frame
        if marker and parent then
            marker:ClearAllPoints()
            marker:SetPoint("TOPLEFT", parent, "LEFT", left, 0)
            marker:SetPoint("BOTTOMLEFT", parent, "LEFT", left, 0)
        end
    end
    zone:Show()
    if marker then
        marker:Show()
    end
end

--=========================================================================================
-- Target-of-target warning (H1, competitor_gaps)
--=========================================================================================
-- Red "targeting you" label above the cast bar. Option-gated nil = off
-- (hunter_target_warning_enabled strictly true shows; the options pass wires the
-- default): a disabled widget performs no unit reads at all. Unknown hides: the label
-- only shows on an explicit true from ST.HUNTER.get_target_warning.
function ui.update_target_warning(self, db)
    local label = ui.target_warning
    if not label then
        return
    end
    if db.hunter_target_warning_enabled ~= true then
        if label:IsShown() then
            label:Hide()
        end
        return
    end
    local warn
    if self.HUNTER and self.HUNTER.get_target_warning then
        warn = self.HUNTER.get_target_warning(self)
    end
    if warn == true then
        if not label:IsShown() then
            label:Show()
        end
    else
        if label:IsShown() then
            label:Hide()
        end
    end
end

--=========================================================================================
-- Range helper (reference ClassMods.lua:5538-5701)
--=========================================================================================
-- One range probe. A nil answer means the client could not answer the query form,
-- not that the target is out of range; on a name family that is exactly when the
-- approved id fallback is tried before the state is called unknown.
local function probe_in_range(token, fallback_id)
    if not token then
        return nil
    end
    local answer = api.IsSpellInRange(token, "target")
    if answer == nil and fallback_id ~= nil and fallback_id ~= token then
        answer = api.IsSpellInRange(fallback_id, "target")
    end
    return answer
end

function ui.update_range_helper(self, db)
    local helper = ui.range_helper
    if db.hunter_range_helper_enabled == false then
        if helper:IsShown() then
            helper:Hide()
        end
        return
    end

    -- The strip hugs the left edge of the ranged bar and grows up over the cast bar
    -- while that is visible (reference GetHunterRangeHelperAnchors, ClassMods.lua:5637-5650).
    -- Without a ranged bar (degenerate client) it falls back to the cast bar / UIParent.
    local ranged_frame = ui.ranged_frame or UIParent
    local top = ranged_frame
    if frame_visible(ui.cast_frame) then
        top = ui.cast_frame
    end
    if ui.helper_top ~= top then
        ui.helper_top = top
        helper:ClearAllPoints()
        helper:SetPoint("TOPRIGHT", top, "TOPLEFT", -RANGE_HELPER_GAP, 0)
        helper:SetPoint("BOTTOMRIGHT", ranged_frame, "BOTTOMLEFT", -RANGE_HELPER_GAP, 0)
    end

    -- The reference hides the strip without an attackable target, and when every probe
    -- is answerless (nil): a real 0 still reports out_of_range, an unknown one hides.
    if not self.has_attackable_target then
        if helper:IsShown() then
            helper:Hide()
        end
        return
    end
    local melee = probe_in_range(ui.wing_clip_token, WING_CLIP_ID)
    if melee == nil then
        melee = probe_in_range(ui.raptor_token, RAPTOR_STRIKE_ID)
    end
    -- Sweet spot from exact yards, one probe per update. nil = the client cannot answer
    -- (unknown, so it must not count as "a probe answered"); false = known to be outside
    -- the band (the old CheckInteractDistance probe answered false there too).
    local yards = api.UnitDistance("target")
    local sweet = nil
    if yards ~= nil then
        sweet = yards > RANGE_HELPER_MELEE_RANGE and yards <= RANGE_HELPER_SWEET_SPOT
    end
    local ranged = probe_in_range(ui.auto_shot_token, AUTO_SHOT_ID)
    if melee == nil and sweet == nil and ranged == nil then
        if helper:IsShown() then
            helper:Hide()
        end
        return
    end

    local state = st.hunter_window.range_state(melee, sweet, ranged)
    if ui.helper_state ~= state then
        ui.helper_state = state
        local c = RANGE_STATE_COLORS[state] or RANGE_STATE_COLORS.out_of_range
        helper.tex:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    if not helper:IsShown() then
        helper:Show()
    end
end

--=========================================================================================
-- Rapid Fire bar (reference ClassMods.lua:5879-6024)
--=========================================================================================
function ui.update_rapid_fire(self, db, now)
    local bar = ui.rapid_fire_bar
    if db.hunter_rapid_fire_bar_enabled == false then
        if bar:IsShown() then
            bar:Hide()
        end
        return
    end
    if ui.rf_scan_at and now < ui.rf_scan_at then
        return
    end
    ui.rf_scan_at = now + RAPID_FIRE_SCAN_INTERVAL

    -- The reference anchors the bar above the ranged bar; the cast bar occupies that
    -- spot in this layout, so the Rapid Fire bar stacks above the cast bar while it is
    -- visible and sits directly on the ranged bar otherwise (UIParent centre without a
    -- ranged bar at all).
    local ranged_frame = ui.ranged_frame
    local anchor_target = ranged_frame or UIParent
    if frame_visible(ui.cast_frame) then
        anchor_target = ui.cast_frame
    end
    if ui.rf_anchor ~= anchor_target then
        ui.rf_anchor = anchor_target
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOM", anchor_target, "TOP", 0, 2)
    end
    local width = ranged_frame and ranged_frame:GetWidth() or ui.cast_frame:GetWidth()
    if ui.rf_width ~= width then
        ui.rf_width = width
        bar:SetWidth(width)
    end

    -- Scan the player's helpful auras for the Rapid Fire buff.
    local duration, expiration
    for index = 1, AURA_SCAN_LIMIT do
        local name, _, _, _, aura_duration, aura_expiration, _, _, _, aura_spell_id =
            api.UnitAura("player", index, "HELPFUL")
        if not name then
            break
        end
        if aura_spell_id == RAPID_FIRE_SPELL_ID or name == ui.rapid_fire_name then
            duration, expiration = aura_duration, aura_expiration
            break
        end
    end
    if not duration and not expiration then
        -- Readiness 2x window (hunter_open §1): while the double-RF window is
        -- live and no RF aura is up, the bar shows full with a "2x" readout (the
        -- same bar + label, so the build-time widget census holds). Option-gated
        -- nil = off; unknown hides.
        if db.hunter_readiness_badge_enabled == true and self.HUNTER
            and self.HUNTER.get_readiness_window then
            local window_remaining = self.HUNTER.get_readiness_window(
                self.hunter_readiness_at, now)
            if window_remaining ~= nil then
                bar:SetMinMaxValues(0, RAPID_FIRE_FALLBACK_DURATION)
                bar:SetValue(RAPID_FIRE_FALLBACK_DURATION)
                bar.label:SetText("2x")
                if not bar:IsShown() then
                    bar:Show()
                end
                return
            end
        end
        -- Only shown while the aura's duration is up, never for its cooldown.
        if bar:IsShown() then
            bar:Hide()
        end
        return
    end

    local remaining = 0
    if type(expiration) == "number" and expiration > 0 then
        remaining = math.max(expiration - now, 0)
    elseif type(duration) == "number" and duration > 0 then
        remaining = duration
    end
    local full = RAPID_FIRE_FALLBACK_DURATION
    if type(duration) == "number" and duration > 0 then
        full = duration
    end
    bar:SetMinMaxValues(0, full)
    bar:SetValue(remaining)
    bar.label:SetText(string.format("%.0fs", remaining))
    if not bar:IsShown() then
        bar:Show()
    end
end

--=========================================================================================
-- Pet badges: Bestial Wrath duration + pet Frenzy stacks (H6)
--=========================================================================================
-- The tracked-icon pattern (reference ClassMods.lua:6224-6385): the BW badge shows the
-- buff's remaining duration with a gold glow inside the final 4 s; the Frenzy badge
-- shows the pet's stack count while the 30%-attack-speed buff is up. Both are
-- option-gated off by default (hunter_bw_badge_enabled / hunter_frenzy_stacks_enabled
-- strictly true shows; nil = off, wired by the options pass) and their scans are
-- throttled to the aspect cadence. BW reads the player's own buffs through compat's
-- frozen scan_player_aura contract; Frenzy reads the pet's buffs through the same
-- UnitAura wrapper (a different unit - the scan helper is player-only by contract).
local function badge_row_anchor(db)
    -- Continue the aspect icon's fallback chain: the badge row sits left of the aspect
    -- icon when that is enabled, else left of the range helper when that is, else left
    -- of the bar itself (UIParent centre without a ranged frame).
    if db.hunter_aspect_icon_enabled ~= false and ui.aspect_icon then
        return ui.aspect_icon
    end
    if db.hunter_range_helper_enabled ~= false and ui.range_helper then
        return ui.range_helper
    end
    return ui.ranged_frame or UIParent
end

local function update_bw_badge()
    local badge = ui.bw_badge
    if not ui.bw_texture then
        if badge:IsShown() then
            badge:Hide()
        end
        return
    end
    local remaining = api.scan_player_aura(function(spell_id, name)
        return spell_id == BW_SPELL_ID or (ui.bw_name ~= nil and name == ui.bw_name)
    end)
    if type(remaining) ~= "number" or remaining <= 0 then
        badge.glow:Hide()
        if badge:IsShown() then
            badge:Hide()
        end
        return
    end
    -- Countdown: whole seconds at or above 3 s, one decimal below (the reference
    -- durationText rule, ClassMods.lua:6374-6378).
    local text
    if remaining >= 3 then
        text = string.format("%.0f", remaining)
    else
        text = string.format("%.1f", remaining)
    end
    if ui.bw_text ~= text then
        ui.bw_text = text
        badge.text:SetText(text)
    end
    if remaining <= BADGE_GLOW_WINDOW then
        badge.glow:Show()
    else
        badge.glow:Hide()
    end
    if not badge.text:IsShown() then
        badge.text:Show()
    end
    if not badge:IsShown() then
        badge:Show()
    end
end

local function update_frenzy_badge()
    local badge = ui.frenzy_badge
    if not ui.frenzy_texture then
        if badge:IsShown() then
            badge:Hide()
        end
        return
    end
    local found = false
    local count
    for index = 1, AURA_SCAN_LIMIT do
        local name, _, aura_count, _, _, _, _, _, _, aura_spell_id =
            api.UnitAura("pet", index, "HELPFUL")
        if not name then
            break
        end
        if aura_spell_id == FRENZY_EFFECT_ID
            or (ui.frenzy_name ~= nil and name == ui.frenzy_name) then
            found = true
            count = aura_count
            break
        end
    end
    if not found then
        if badge:IsShown() then
            badge:Hide()
        end
        return
    end
    -- The stack count the client reports (1..3); a client that reports no count shows
    -- the icon alone rather than a fabricated 1.
    local text
    if type(count) == "number" and count >= 1 then
        text = tostring(count)
    end
    if ui.frenzy_text ~= text then
        ui.frenzy_text = text
        if text then
            badge.text:SetText(text)
        end
    end
    if text then
        if not badge.text:IsShown() then
            badge.text:Show()
        end
    else
        badge.text:Hide()
    end
    if not badge:IsShown() then
        badge:Show()
    end
end

function ui.update_pet_badges(self, db, now)
    local bw_badge = ui.bw_badge
    local frenzy_badge = ui.frenzy_badge
    if not (bw_badge and frenzy_badge) then
        return
    end
    local bw_on = db.hunter_bw_badge_enabled == true
    local frenzy_on = db.hunter_frenzy_stacks_enabled == true
    if not bw_on and bw_badge:IsShown() then
        bw_badge:Hide()
    end
    if not frenzy_on and frenzy_badge:IsShown() then
        frenzy_badge:Hide()
    end
    if not (bw_on or frenzy_on) then
        return
    end
    -- Anchors: recomputed only when the row target changes (an option flip or the
    -- frame set), never per tick.
    local anchor = badge_row_anchor(db)
    if ui.bw_anchor ~= anchor then
        ui.bw_anchor = anchor
        bw_badge:ClearAllPoints()
        bw_badge:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    end
    local frenzy_anchor = (bw_on and bw_badge) or anchor
    if ui.frenzy_anchor ~= frenzy_anchor then
        ui.frenzy_anchor = frenzy_anchor
        frenzy_badge:ClearAllPoints()
        frenzy_badge:SetPoint("RIGHT", frenzy_anchor, "LEFT", -2, 0)
    end
    -- Throttled scans: the badges hold their last state between polls.
    if ui.badge_scan_at and now < ui.badge_scan_at then
        return
    end
    ui.badge_scan_at = now + BADGE_SCAN_INTERVAL
    if bw_on then
        update_bw_badge()
    end
    if frenzy_on then
        update_frenzy_badge()
    end
end

--=========================================================================================
-- OOM Viper badge (hunter_open §2)
--=========================================================================================
-- "VIPER" badge while mana sits below the swap band, Viper is known but not
-- active (the TBC <5% swap edge; SoD's Viper id differs, both probed).
-- Option-gated nil = off; unknown hides. The widget is created lazily on the
-- first enabled tick (never in build) so the build-time widget census
-- (bars_state, reconcile-owned) is untouched until reconcile hoists it.
local function ensure_oom_badge()
    if ui.oom_badge then
        return ui.oom_badge
    end
    local badge = create_badge("HunterOomViperBadge", ui.tick_host or ui.ranged_frame)
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge.text:SetJustifyH("CENTER")
    ui.oom_badge = badge
    return badge
end

function ui.update_oom_viper(self, db, now)
    local badge = ui.oom_badge
    if db.hunter_oom_viper_badge_enabled ~= true then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    local H = self.HUNTER
    if not (H and H.get_oom_viper_prompt and H.get_mana_fraction
        and H.is_viper_active and H.is_viper_known) then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    -- Throttled like the pet badges: the badge holds its last state between polls.
    if ui.oom_scan_at and now < ui.oom_scan_at then
        return
    end
    ui.oom_scan_at = now + BADGE_SCAN_INTERVAL
    local prompt = H.get_oom_viper_prompt(H.get_mana_fraction(),
        H.is_viper_active(), H.is_viper_known(), true)
    if prompt == nil then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    badge = ensure_oom_badge()
    -- Badge row: left of the Frenzy badge when that is on, else left of the BW
    -- badge when that is on, else the row anchor (the pet-badge chain's pattern).
    local anchor = badge_row_anchor(db)
    if db.hunter_bw_badge_enabled == true and ui.bw_badge then
        anchor = ui.bw_badge
    end
    if db.hunter_frenzy_stacks_enabled == true and ui.frenzy_badge then
        anchor = ui.frenzy_badge
    end
    if ui.oom_anchor ~= anchor then
        ui.oom_anchor = anchor
        badge:ClearAllPoints()
        badge:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    end
    if ui.oom_text ~= prompt then
        ui.oom_text = prompt
        badge.text:SetText(prompt)
    end
    if not badge.text:IsShown() then
        badge.text:Show()
    end
    if not badge:IsShown() then
        badge:Show()
    end
end

--=========================================================================================
-- Lock and Load trap-proc badge (hunter_open §1)
--=========================================================================================
-- "LnL" badge while the trap-proc window is live (the Wrath 56344 / SoD 415413
-- proc ids, SIM-CONFIRMED, CLIENT-UNCONFIRMED - see classes/hunter.lua).
-- Badge layer only: the guide engine never reads it. Option-gated nil = off
-- (hunter_lnl_badge_enabled, wired by the options pass); unknown hides. The
-- widget is created lazily on the first enabled tick (never in build) so the
-- build-time widget census (bars_state, reconcile-owned) is untouched until
-- reconcile hoists it - the OOM badge's pattern verbatim.
local function ensure_lnl_badge()
    if ui.lnl_badge then
        return ui.lnl_badge
    end
    local badge = create_badge("HunterLnlBadge", ui.tick_host or ui.ranged_frame)
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge.text:SetJustifyH("CENTER")
    ui.lnl_badge = badge
    return badge
end

function ui.update_lnl_badge(self, db, now)
    local badge = ui.lnl_badge
    if db.hunter_lnl_badge_enabled ~= true then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    local H = self.HUNTER
    if not (H and H.get_lnl_prompt and H.get_lnl_remaining) then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    -- Throttled like the pet badges: the badge holds its last state between polls.
    if ui.lnl_scan_at and now < ui.lnl_scan_at then
        return
    end
    ui.lnl_scan_at = now + BADGE_SCAN_INTERVAL
    local prompt = H.get_lnl_prompt(H.get_lnl_remaining(self, now), true)
    if prompt == nil then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    badge = ensure_lnl_badge()
    -- Badge row: left of the OOM badge when that is on, else left of the
    -- Frenzy badge when that is on, else left of the BW badge when that is on,
    -- else the row anchor (the OOM badge's chain extended by one).
    local anchor = badge_row_anchor(db)
    if db.hunter_bw_badge_enabled == true and ui.bw_badge then
        anchor = ui.bw_badge
    end
    if db.hunter_frenzy_stacks_enabled == true and ui.frenzy_badge then
        anchor = ui.frenzy_badge
    end
    if db.hunter_oom_viper_badge_enabled == true and ui.oom_badge then
        anchor = ui.oom_badge
    end
    if ui.lnl_anchor ~= anchor then
        ui.lnl_anchor = anchor
        badge:ClearAllPoints()
        badge:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    end
    if ui.lnl_text ~= prompt then
        ui.lnl_text = prompt
        badge.text:SetText(prompt)
    end
    if not badge.text:IsShown() then
        badge.text:Show()
    end
    if not badge:IsShown() then
        badge:Show()
    end
end

--=========================================================================================
-- Trap badge (hunter_wa_map §6: the placed-phase display)
--=========================================================================================
-- Countdown while a trap is armed on the ground (the wired placed phase; the
-- filed active phase rides the same badge when the CLEU lane lands - the state
-- shape already carries phase). Option-gated nil = off
-- (hunter_trap_badge_enabled, options pass wires the default); unknown hides.
-- The widget is created lazily on the first enabled tick (never in build) so
-- the build-time widget census (bars_state, reconcile-owned) is untouched until
-- reconcile hoists it - the OOM/LnL badge pattern verbatim.
local function ensure_trap_badge()
    if ui.trap_badge then
        return ui.trap_badge
    end
    local badge = create_badge("HunterTrapBadge", ui.tick_host or ui.ranged_frame)
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge.text:SetJustifyH("CENTER")
    ui.trap_badge = badge
    return badge
end

function ui.update_trap_badge(self, db, now)
    local badge = ui.trap_badge
    if db.hunter_trap_badge_enabled ~= true then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    local H = self.HUNTER
    if not (H and H.get_trap_remaining) then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    -- Throttled like the pet badges: the badge holds its last state between polls.
    if ui.trap_scan_at and now < ui.trap_scan_at then
        return
    end
    ui.trap_scan_at = now + BADGE_SCAN_INTERVAL
    local remaining = H.get_trap_remaining(self, now)
    if remaining == nil then
        if badge and badge:IsShown() then
            badge:Hide()
        end
        return
    end
    badge = ensure_trap_badge()
    -- Badge row: left of the LnL badge when that is on, else left of the OOM
    -- badge when that is on, else the pet-badge chain (the LnL pattern extended).
    local anchor = badge_row_anchor(db)
    if db.hunter_bw_badge_enabled == true and ui.bw_badge then
        anchor = ui.bw_badge
    end
    if db.hunter_frenzy_stacks_enabled == true and ui.frenzy_badge then
        anchor = ui.frenzy_badge
    end
    if db.hunter_oom_viper_badge_enabled == true and ui.oom_badge then
        anchor = ui.oom_badge
    end
    if db.hunter_lnl_badge_enabled == true and ui.lnl_badge then
        anchor = ui.lnl_badge
    end
    if ui.trap_anchor ~= anchor then
        ui.trap_anchor = anchor
        badge:ClearAllPoints()
        badge:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    end
    local text = string.format("%.0fs", remaining)
    if ui.trap_text ~= text then
        ui.trap_text = text
        badge.text:SetText(text)
    end
    if not badge.text:IsShown() then
        badge.text:Show()
    end
    if not badge:IsShown() then
        badge:Show()
    end
end
function ui.update_aspect_icon(self, db, now)
    local icon = ui.aspect_icon
    if db.hunter_aspect_icon_enabled == false then
        if icon:IsShown() then
            icon:Hide()
        end
        return
    end

    -- Left of the range strip, or of the ranged bar when the strip is disabled
    -- (reference fallback, ClassMods.lua:6038-6046; UIParent centre without a ranged bar).
    local anchor_target = ui.ranged_frame or UIParent
    if db.hunter_range_helper_enabled ~= false then
        anchor_target = ui.range_helper
    end
    if ui.aspect_anchor ~= anchor_target then
        ui.aspect_anchor = anchor_target
        icon:ClearAllPoints()
        if anchor_target == ui.range_helper then
            icon:SetPoint("RIGHT", anchor_target, "LEFT", -2, 0)
        else
            icon:SetPoint("TOPRIGHT", anchor_target, "TOPLEFT", -2, 0)
        end
    end

    -- Throttled aura scan (reference HUNTER_ASPECT_UPDATE_INTERVAL).
    if ui.aspect_scan_at and now < ui.aspect_scan_at then
        return
    end
    ui.aspect_scan_at = now + ASPECT_SCAN_INTERVAL
    local aspect_id
    for index = 1, AURA_SCAN_LIMIT do
        local name, _, _, _, _, _, _, _, _, aura_spell_id =
            api.UnitAura("player", index, "HELPFUL")
        if not name then
            break
        end
        if type(aura_spell_id) == "number" and ASPECT_SPELL_IDS[aura_spell_id] then
            aspect_id = aura_spell_id
            break
        end
        aspect_id = ui.aspect_names[name]
        if aspect_id then
            break
        end
    end
    local texture = aspect_id and ui.aspect_textures[aspect_id]
    if not texture then
        if icon:IsShown() then
            icon:Hide()
        end
        return
    end
    if ui.aspect_texture ~= texture then
        ui.aspect_texture = texture
        icon.tex:SetTexture(texture)
    end
    if not icon:IsShown() then
        icon:Show()
    end
end

--=========================================================================================
-- Per-frame entry points
--=========================================================================================
function ui.hide_all(self)
    hide_cast_bar()
    if ui.range_helper then
        ui.range_helper:Hide()
    end
    if ui.rapid_fire_bar then
        ui.rapid_fire_bar:Hide()
    end
    if ui.aspect_icon then
        ui.aspect_icon:Hide()
    end
    if ui.cast_zone then
        ui.cast_zone:Hide()
    end
    if ui.cast_zone_marker then
        ui.cast_zone_marker:Hide()
    end
    if ui.target_warning then
        ui.target_warning:Hide()
    end
    if ui.bw_badge then
        ui.bw_badge:Hide()
    end
    if ui.frenzy_badge then
        ui.frenzy_badge:Hide()
    end
    if ui.oom_badge then
        ui.oom_badge:Hide()
    end
    if ui.lnl_badge then
        ui.lnl_badge:Hide()
    end
    if ui.trap_badge then
        ui.trap_badge:Hide()
    end
    ui.zone_safe = nil
    ui.oom_scan_at = nil
    ui.lnl_scan_at = nil
    ui.trap_scan_at = nil
end

function ui.update(self)
    -- Two tick sources, never both in one frame (HU-37): the ranged bar's per-frame
    -- tick while that bar is visible, and the anchor hook (ui.poll) whenever that tick
    -- cannot run. The ACTIVITY gate is not an input here - the set must paint
    -- a cast, a proc badge or a range reading while the bar itself stays hidden.
    if not ui.ready or not ranged_bar_ready(self) then
        if ui.ready then
            ui.hide_all(self)
        end
        return
    end
    local db = self:get_class_table()
    -- No class row means no hunter settings: every updater below reads db, so the
    -- honest state is "hidden" (the same state a switched-off HUD paints), not a
    -- guard-quarantine storm from a nil read.
    if type(db) ~= "table" then
        ui.hide_all(self)
        return
    end
    -- The configured half of the bar's visibility (class/spec/hand enable flags and
    -- the hand's own show rule). Ignoring the activity gate must not resurrect a set the
    -- user's own configuration keeps hidden.
    if not ranged_ui_allowed(self, db) then
        ui.hide_all(self)
        return
    end
    local now = api.get_time()
    -- R3 (2026-10-21): every sub-feature is its own guarded site, so one throwing
    -- updater cannot take the rest of the hunter UI down - the retired
    -- CheckInteractDistance probe did exactly that through the class hook. The guard
    -- announces the first throw per site, counts it and quarantines after
    -- st.guard.QUARANTINE_THROWS (25).
    st.guard.run(self, "hunter_ui:cast_bar", ui.update_cast_bar, self, db, now)
    st.guard.run(self, "hunter_ui:cast_zone", ui.update_cast_zone, self, db, now)
    st.guard.run(self, "hunter_ui:target_warning", ui.update_target_warning, self, db)
    st.guard.run(self, "hunter_ui:range_helper", ui.update_range_helper, self, db)
    st.guard.run(self, "hunter_ui:rapid_fire", ui.update_rapid_fire, self, db, now)
    st.guard.run(self, "hunter_ui:pet_badges", ui.update_pet_badges, self, db, now)
    st.guard.run(self, "hunter_ui:oom_viper", ui.update_oom_viper, self, db, now)
    st.guard.run(self, "hunter_ui:lnl_badge", ui.update_lnl_badge, self, db, now)
    st.guard.run(self, "hunter_ui:trap_badge", ui.update_trap_badge, self, db, now)
    st.guard.run(self, "hunter_ui:aspect_icon", ui.update_aspect_icon, self, db, now)
end

function ui.force_rapid_fire_refresh(self)
    -- Readiness (23989) resets Rapid Fire's cooldown; the reference forces the Rapid
    -- Fire bar's next scan immediately (ForceHunterRapidFireRefresh, ClassMods.lua:
    -- 5951-5956). Here the scan is driven by the ranged tick (or the anchor hook while the
    -- bar is hidden), so the force is a throttle bypass and the next tick reads the new
    -- state. Nil-safe before build: update_rapid_fire only runs once ui.ready is true.
    ui.rf_scan_at = nil
end

function ui.on_bar_update(self, hand)
    -- Dispatched from ST.HUNTER.on_bar_update for the mainhand and ranged bars. The
    -- mainhand tick retries the deferred frame creation (a lockdown build is retried
    -- from whichever bar ticks first) and keeps the melee stack applied while the ranged
    -- bar is hidden. The ranged tick drives the visual set exactly as it always has -
    -- but only while the bar is visible; the anchor hook (ui.poll) covers every frame
    -- this hook cannot reach because the activity gate hid the bar (HU-37).
    if not ui.ready then
        ui.init(self)
        if not ui.ready then
            return
        end
    end
    if hand == "mainhand" or hand == "ranged" then
        st.guard.run(self, "hunter_ui:melee_stack", ui.apply_melee_stack, self)
    end
    if hand == "ranged" then
        ui.update(self)
    end
end

if st.debug then st.utils.print_msg('-- Parsed hunter_ui.lua module correctly') end
