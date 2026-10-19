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
--   melee re-anchor            SuperSwingTimer_UI.lua:26-39, 1140-1146
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
-- driven by the class module's on_bar_update hook from the ranged bar (the mainhand
-- tick keeps the melee re-anchor in sync). The cast bar anchors above the ranged bar
-- (UIParent centre when no ranged bar frame exists at all), and the whole set is a
-- silent no-op while the ranged hand is disabled, so it never shows on clients without
-- a ranged swing (Retail).
--=========================================================================================
local addon_name, st = ...
local LSM = LibStub("LibSharedMedia-3.0")
local LWIN = LibStub("LibWindow-1.1")
local api = st.api

st.hunter_ui = st.hunter_ui or {}
local ui = st.hunter_ui

--=========================================================================================
-- Constants (reference values in the comments)
--=========================================================================================
local CAST_BAR_GAP = 2                     -- HUNTER_CAST_BAR_GAP, Constants:162
local MELEE_ANCHOR_GAP = 2                 -- reference melee/OH stack gap, UI.lua:36-37
local RANGE_HELPER_GAP = 3                 -- HUNTER_RANGE_HELPER_GAP, ClassMods.lua:5533
local RANGE_HELPER_WIDTH = 7               -- HUNTER_RANGE_HELPER_WIDTH, Constants:163
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
local LATENCY_SLICE_COLOR = {1, 0, 0, 0.24}
local RANGE_STATE_COLORS = {               -- hunterRange*, Constants:971-974
    melee = {0.20, 0.85, 0.25, 1},
    sweet_spot = {0.98, 0.82, 0.18, 1},
    ranged = {0.20, 0.55, 1.00, 1},
    out_of_range = {0.50, 0.50, 0.50, 1},
}
local CLIP_TINT_COLORS = {                 -- clipSafe / clipZone, Constants:975-976
    clipSafe = {0.2, 0.78, 0.25, 0.4},
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
-- Movement-safe cast zone: the final cast-window fraction of the ranged swing, green
-- when standing still is safe (stopped at or before the window opened), red otherwise
-- (autoShotSafe / autoShotUnsafe, Constants:977-978; same values as the clip tint).
local CAST_ZONE_SAFE = {0.2, 0.78, 0.25, 0.4}
local CAST_ZONE_UNSAFE = {1, 0, 0, 0.4}
local CAST_ZONE_MARKER_WIDTH = 3            -- the reference's threshold marker (UI.lua:834)

--=========================================================================================
-- Helpers
--=========================================================================================

-- Raw world latency in seconds: the same basis the swing maths and the shaman/paladin
-- helpers consume.
local function world_latency_seconds(self)
    return ((self.latency and self.latency.world_ms) or 0) / 1000
end

-- Effective visibility (a hidden parent hides its children; the widgets below are
-- children of the ranged bar frame, so Hide() on the bar must read as not visible here).
local function frame_visible(frame)
    if not frame then
        return false
    end
    if frame.IsVisible then
        return frame:IsVisible() == true
    end
    return frame:IsShown() == true
end

-- The hand's anchor frame, or nil before bars.lua builds it.
local function get_anchor(self, hand)
    local state = self[hand]
    if not state or not state.anchor_frame then
        return nil
    end
    return state.anchor_frame
end

-- Whether the hunter's ranged bar is usable right now: the ranged hand state exists and
-- the ranged hand is enabled. A hunter without a ranged weapon reads false, and so does
-- the Retail client, where UnitRangedDamage does not exist, so no ranged weapon is ever
-- detected. Everything in this module is a silent no-op while false.
local function ranged_bar_ready(self)
    return self.ranged ~= nil and self:bar_is_enabled("ranged") == true
end

-- Resolve a spell id to the running client's localized name, with the id as fallback
-- (IsSpellInRange and aura scans accept either; a client that knows the spell answers
-- the name form).
local function resolve_spell(spell_id)
    local name = api.GetSpellInfo(spell_id)
    return name or spell_id, name
end

--=========================================================================================
-- Frame construction (called once from ST.HUNTER.post_init, out of combat)
--=========================================================================================
local function create_cast_bar(ranged_frame, texture, font_path, db_hand)
    local parent = ranged_frame or UIParent
    local frame = CreateFrame("Frame", addon_name .. "HunterCastBar", parent)
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
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetTextColor(1, 1, 1, 1)
    frame.text:SetShadowColor(0, 0, 0, 1)
    frame.text:SetShadowOffset(1, -1)
    if font_path then
        frame.text:SetFont(font_path, db_hand.text_size or 12, "")
    end

    frame:Hide()
    return frame
end

local function create_range_helper(ranged_frame)
    local helper = CreateFrame("Frame", addon_name .. "HunterRangeHelper", ranged_frame)
    helper:SetWidth(RANGE_HELPER_WIDTH)
    helper.tex = helper:CreateTexture(nil, "ARTWORK")
    helper.tex:SetAllPoints()
    helper.tex:SetColorTexture(1, 1, 1, 1)
    helper:Hide()
    return helper
end

local function create_rapid_fire_bar(ranged_frame, texture)
    local bar = CreateFrame("StatusBar", addon_name .. "HunterRapidFireBar", ranged_frame)
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
    bar.label:SetPoint("LEFT", bar, "RIGHT", 2, 0)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetTextColor(unpack(RAPID_FIRE_BAR_COLOR))
    bar:Hide()
    return bar
end

local function create_aspect_icon(ranged_frame)
    local icon = CreateFrame("Frame", addon_name .. "HunterAspectIcon", ranged_frame)
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

local function create_badge(name, ranged_frame)
    -- The tracked-icon pattern (reference ClassMods.lua:6224-6279): icon texture with
    -- the standard inset, an additive gold glow overlay, one text. Callers place the
    -- text (BW: the countdown above the icon; Frenzy: the stack count bottom-right).
    local frame = CreateFrame("Frame", addon_name .. name, ranged_frame)
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
    frame.text:SetTextColor(1, 1, 1, 0.95)
    frame.text:Hide()
    frame:Hide()
    return frame
end

function ui.build(self, ranged_frame)
    local db_hand = self:get_hand_table("ranged")
    local texture = LSM:Fetch("statusbar", db_hand.bar_texture_key)
    local font_path = LSM:Fetch("font", db_hand.text_font)

    ui.ranged_frame = ranged_frame
    ui.cast_frame = create_cast_bar(ranged_frame, texture, font_path, db_hand)
    ui.range_helper = create_range_helper(ranged_frame)
    ui.rapid_fire_bar = create_rapid_fire_bar(ranged_frame, texture)
    ui.aspect_icon = create_aspect_icon(ranged_frame)

    -- Transition state: nil/false means "normal anchors".
    ui.melee_anchored = false
    ui.helper_top = nil
    ui.rf_anchor = nil
    ui.rf_width = nil
    ui.aspect_anchor = nil
    ui.cast_height = nil

    -- Client spell tokens (localized names with the ids as fallback).
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
    ui.bw_badge = create_badge("HunterBWBadge", ranged_frame)
    ui.bw_badge.text:SetPoint("BOTTOM", ui.bw_badge, "TOP", 0, 2)
    ui.bw_badge.text:SetJustifyH("CENTER")
    ui.frenzy_badge = create_badge("HunterFrenzyBadge", ranged_frame)
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
-- Melee re-anchor (reference UpdateHunterMeleeBarAnchor, UI.lua:26-39, 1140-1146)
--=========================================================================================
-- While the hunter cast bar is visible, the mainhand and offhand bars re-anchor into
-- the reference's stack on the side of the ranged bar away from the cast bar: the
-- mainhand directly beneath the ranged bar, the offhand directly beneath the mainhand,
-- 2 px gaps. When the cast bar hides, both return to their LibWindow positions. The
-- reference pins the bars with two-point anchors, which also couples their widths to
-- the anchor bar; SwedgeTimer's bars are independently sized, so the stacking is
-- applied as a vertical re-anchor of the stored position that keeps each bar's own
-- width and horizontal placement.
local function anchor_hand_top_below(frame, target_bottom)
    -- LWIN keeps the frame's own position in the hand's storage: restore it (scale and
    -- legacy points included), then shift the vertical component so the frame's top edge
    -- sits at `target_bottom` (a UIParent-domain y, LibWindow's own unit).
    LWIN.RestorePosition(frame)
    local point, _, _, x, y = frame:GetPoint(1)
    if not point then
        return
    end
    local scale = frame:GetScale() or 1
    local height = (frame:GetHeight() or 0) * scale
    local target_center = target_bottom - height / 2
    local _, center_y = frame:GetCenter()
    local shift = (center_y or target_center) * scale - target_center
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y - shift / scale)
end

function ui.sync_melee_anchor(self)
    -- The re-anchor is skipped while the bars are unlocked for positioning, so a drag can
    -- never save a shifted position as the new normal.
    local anchored = frame_visible(ui.cast_frame)
        and self:get_class_table().timers_locked ~= false
    if ui.melee_anchored == anchored then
        return
    end
    local mh = get_anchor(self, "mainhand")
    local oh = get_anchor(self, "offhand")
    if not anchored then
        -- Restore the normal (LibWindow) anchors. Also the path taken when the melee
        -- bars themselves are missing.
        if mh then
            LWIN.RestorePosition(mh)
        end
        if oh then
            LWIN.RestorePosition(oh)
        end
        ui.melee_anchored = false
        return
    end
    local ranged_frame = ui.ranged_frame
    if not (mh and ranged_frame) then
        return
    end
    ui.melee_anchored = true
    local ranged_scale = ranged_frame:GetScale() or 1
    local ranged_bottom = ranged_frame:GetBottom() * ranged_scale
    anchor_hand_top_below(mh, ranged_bottom - MELEE_ANCHOR_GAP)
    if oh then
        local mh_scale = mh:GetScale() or 1
        local stack_bottom = ranged_bottom - MELEE_ANCHOR_GAP - (mh:GetHeight() or 0) * mh_scale
        anchor_hand_top_below(oh, stack_bottom - MELEE_ANCHOR_GAP)
    end
end

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
    if spell_id == AUTO_SHOT_ID or name == ui.auto_shot_name then
        return nil
    end
    if type(cast_start) ~= "number" or type(cast_end) ~= "number" or cast_end <= cast_start then
        return nil
    end
    return name, spell_id, cast_start, cast_end
end

-- The hidden Auto Shot window of the current ranged cycle, cached on the phase-1 ranged
-- state fields (hunter_window.hidden_window; reference UI.lua:394-430). A cached window
-- counts while `now` is inside it; a future one stays cached so the per-frame path costs
-- two comparisons until it opens; everything else recomputes from the live swing state.
local function get_hidden_window(self, now)
    local ranged = self.ranged
    if not ranged then
        return nil, nil
    end
    local start = ranged.hidden_window_start
    local duration = ranged.hidden_window_duration
    if type(start) == "number" and type(duration) == "number" and duration > 0
        and now >= start and now <= start + duration then
        return start, duration
    end
    ranged.hidden_window_start = nil
    ranged.hidden_window_duration = nil
    local cycle_duration = ranged.synced_duration or ranged.speed
    if type(ranged.start) ~= "number" or type(cycle_duration) ~= "number" or cycle_duration <= 0 then
        return nil, nil
    end
    local window_start, window_end = st.hunter_window.hidden_window(
        ranged.start, cycle_duration, st.hunter_window.cast_window(world_latency_seconds(self)))
    if not window_start or now > window_end then
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
        elapsed = now - cast_start
    else
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
-- Movement-safe cast zone (reference UI.lua:204-225, 805-850)
--=========================================================================================
-- The final cast-window fraction of the ranged swing, tinted green when standing still
-- right now is safe (the player stopped at or before the window opened) and red when
-- still moving through it or stopped too late - the WeaponSwingTimer/SuperSwingTimer
-- "safe to move" standard (bench/verify_bank.md §5.1). The maths are the pure
-- hunter_window kernels (cast_window + is_stopped_position_safe); the movement state
-- (self.is_moving / self.last_stopped_moving_at) is main.lua's. Option-gated:
-- hunter_cast_zone_enabled strictly true shows it (nil = off; the options pass wires
-- the default), and a disabled zone performs no reads at all.
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
    local cast_window = st.hunter_window.cast_window(world_latency_seconds(self))
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
-- Range helper (reference ClassMods.lua:5538-5701)
--=========================================================================================
local function probe_in_range(token)
    if not token then
        return nil
    end
    return api.IsSpellInRange(token, "target")
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
    local melee = probe_in_range(ui.wing_clip_token)
    if melee == nil then
        melee = probe_in_range(ui.raptor_token)
    end
    local sweet = api.CheckInteractDistance("target", 3)
    local ranged = probe_in_range(ui.auto_shot_token)
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
-- Aspect icon (reference ClassMods.lua:6026-6135)
--=========================================================================================
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
    if ui.bw_badge then
        ui.bw_badge:Hide()
    end
    if ui.frenzy_badge then
        ui.frenzy_badge:Hide()
    end
    ui.zone_safe = nil
    ui.sync_melee_anchor(self)
end

function ui.update(self)
    -- Driven from the ranged bar's per-frame tick (ST.HUNTER.on_bar_update hook).
    if not ui.ready or not ranged_bar_ready(self) then
        if ui.ready then
            ui.hide_all(self)
        end
        return
    end
    local db = self:get_class_table()
    local now = api.get_time()
    ui.update_cast_bar(self, db, now)
    ui.sync_melee_anchor(self)
    ui.update_cast_zone(self, db, now)
    ui.update_range_helper(self, db)
    ui.update_rapid_fire(self, db, now)
    ui.update_pet_badges(self, db, now)
    ui.update_aspect_icon(self, db, now)
end

function ui.force_rapid_fire_refresh(self)
    -- Readiness (23989) resets Rapid Fire's cooldown; the reference forces the Rapid
    -- Fire bar's next scan immediately (ForceHunterRapidFireRefresh, ClassMods.lua:
    -- 5951-5956). Here the scan is driven by the ranged tick, so the force is a
    -- throttle bypass and the next tick reads the new state. Nil-safe before build:
    -- update_rapid_fire only runs once ui.ready is true.
    ui.rf_scan_at = nil
end

function ui.on_bar_update(self, hand)
    -- Dispatched from ST.HUNTER.on_bar_update for the mainhand and ranged bars. Retries
    -- the deferred frame creation; while the ranged bar is not ticking (it is hidden),
    -- the mainhand tick keeps the melee re-anchor in sync.
    if not ui.ready then
        ui.init(self)
        if not ui.ready then
            return
        end
    end
    if hand == "ranged" then
        ui.update(self)
    else
        ui.sync_melee_anchor(self)
    end
end

if st.debug then st.utils.print_msg('-- Parsed hunter_ui.lua module correctly') end
