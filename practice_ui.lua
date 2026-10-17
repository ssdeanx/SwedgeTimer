--=========================================================================================
-- Twist Practice: the playable UI for the pure st.practice simulation engine (port phase 2).
--
-- Ported from the archived build's practice UI (docs/swedge/SwedgeTimer_Forever/practice.lua):
--   * control panel        558-914    (panel rows: title, speed/GCD + rotation lines,
--                                      two icon rows, hint, fight timer, fight button,
--                                      Bloodlust/Haste-pot/DST buttons, rotation selector,
--                                      timeline toggle - archive 558-914)
--   * haste buttons        761-796    (Bloodlust/Haste-pot countdown buttons, minus the
--                                      archived sound hook; DST rides a session-local
--                                      toggle since its db option is out of scope)
--   * rotation selector    807-871 + set_locked_rotation 1258-1304 (session-local lock on
--                                      sim.locked_rotation; haste is cleared on lock)
--   * result popup         524-541    + fade 3284-3301 + show_result 3655-3665
--   * result font update   3667-3672
--   * session start/stop   927-1165   (minus the archived hooks into bar/player functions;
--                                      this port mirrors the simulation onto the addon's own
--                                      bar state instead - see sync_to_addon)
--   * start_fight          2807-2889  (reduced to the engine's fight lifecycle + the
--                                      timeline/band reset and the always-show timeline)
--   * icon state updates   3535-3610  (cooldown swipes kept on the addon's set-once
--                                      pattern per nextaction_ui.lua, plus the archived
--                                      buff/active-seal border highlights)
--   * rotation display     1461-1662  (center-screen name/desc/icons driven by
--                                      st.nextaction.sequences; position is session-local)
--   * rotation tracking    1554-1579  (band logging into the ui-owned band array; the
--                                      engine helper track_rotation_band is pure)
--   * timeline data        1881-1898  (event/band collection on the ui-owned arrays;
--                                      rendering below is a trimmed port of 1900-2510)
--   * keybind capture      261-332 + 4142-4196 (fullscreen capture overlay; bindings live
--                                      in the session-local ui.keybinds table and are
--                                      applied with SetOverrideBindingClick)
--   * proc icons           2715-2802  (Bloodlust + DST icons with swipe + countdown)
--   * sync_state_to_player 2542-2587  (mapped onto ST.PALADIN.practice_sync)
--
-- The engine (practice.lua) is pure and owns no clock: this module owns the clock, the
-- frames and the mirroring onto the live addon state:
--   * Session: /st practice (or the options button) toggles a practice session; start()
--     resets the sim and immediately begins a fight (begin_fight + apply_haste). The
--     panel's Start/Stop Fight button restarts/ends fights within the session; its X
--     button (or /st practice again) stops the session (stop()).
--   * Driver: this module's own OnUpdate frame, NOT the paladin class hook. The class
--     hook only fires while the swing bar is shown, but the driver must keep running
--     while the bar is hidden (and while a real-combat pause is waiting to end); the
--     0.05 s compute throttle mirrors nextaction_ui's UPDATE_INTERVAL, and the result
--     popup fades on every frame for a smooth step between compute ticks.
--   * Real-combat pause (archive sim_on_swing 3434-3441, stricter here): while ST.in_combat
--     the sim is frozen entirely - no casts, no swing progression, no grading - and the
--     panel shows a paused hint. On resume every future sim deadline is shifted by the
--     pause duration (shift_sim_times) so nothing lands retroactively.
--   * Bridge: ST.mainhand/ST.gcd carry the simulated swing and GCD (sync_to_addon), the
--     seal state is mirrored by ST.PALADIN.practice_sync, and main.lua's hide_bar guard
--     keeps the mainhand bar visible for the session (the range-finder loop re-runs bar
--     visibility every 0.05 s).
--   * Icon swipes use the set-once latch pattern (nextaction_ui's set_icon_cooldown):
--     a swipe is started only when a cooldown appears or restarts, never re-set per frame.
--
-- Deviations / deferrals (documented for the later phases):
--   * Keybinds and bar mappings are session-local (ui.keybinds, from
--     st.practice.DEFAULT_KEYBINDS): the archived practice_key_* / practice_bar_mappings
--     persistence needs new options, which this lane may not add. Right-clicking a panel
--     icon assigns a key via the capture overlay; action-bar button discovery, manual
--     linking (click-catchers) and bar overlays plug in through ui.attach_overlay
--     (see the "Bar overlays (deferred)" section).
--   * The archive's calculate_spell_GCD_duration hook is emulated only through
--     gcd.spell_length here; the guide's cooldown inputs still come from the live
--     spell cooldowns until the phase-4 haste/rotation/guide integration.
--   * The AW combos (practice_aw_includes_pot/sob) need new options: not simulated,
--     not wired (engine and UI both skip them).
--   * practice_weapon_speed is read at session/fight start; changing it mid-session
--     takes effect at the next start_fight.
--   * The timeline has no db options here: it always shows on fight start (the archive's
--     "always" default), pixels-per-second and width are constants below, and the
--     position is session-local.
--   * The rotation display has no enable option: it shows during the session whenever
--     the rotation resolves. Its position is session-local (default CENTER + 0, +100).
--   * The DST proc rides the session-local ui.dst_enabled toggle (default off, the
--     archived practice_dst_enabled default); without new options it cannot persist.
--   * Archive quirk: the panel's gcd_dim texture was created but never shown
--     (update_icon_states only fired the gcd_cooldown swipe). Phase 2 shows the dim on
--     GCD-gated icons during the simulated GCD, which is what the panel description says.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LSM = LibStub("LibSharedMedia-3.0")
-- Cross-client API wrappers (see compat.lua).
local api = st.api

st.practice_ui = st.practice_ui or {}
local ui = st.practice_ui

--=========================================================================================
-- Display constants
--=========================================================================================
local UPDATE_INTERVAL = 0.05    -- simulation tick cadence (guide/WA poll parity)
local ICON_SIZE = 30            -- archive geometry
local ICON_SPACING = 4
local ICONS_PER_ROW = 5
local PANEL_WIDTH = 210
local PANEL_ANCHOR_GAP = 8      -- archive: panel TOPLEFT 8 px right of the bar TOPRIGHT
local RESULT_WIDTH = 200
local RESULT_HEIGHT = 50
local RESULT_FADE_SECONDS = 0.3 -- archive: the popup fades over its final 0.3 s
local RESULT_FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local RESULT_COLOR_HIT = {0, 1, 0, 1}
local RESULT_COLOR_MISS = {1, 0.2, 0.2, 1}
local HINT_ACTIVE = "Click an icon to cast. /st practice or the X button stops."
local HINT_STOPPED = "Press Start Fight, or cast seals with the icon grid."
local HINT_PAUSED = "Paused: in combat. Practice resumes when combat ends."

-- Rotation display (archive 1501-1552, session-local position).
local ROT_ICON_SIZE = 40
local ROT_ICON_SPACING = 6
local ROT_DISPLAY_MAX_ICONS = 5
local ROT_DISPLAY_DEFAULT_X = 0
local ROT_DISPLAY_DEFAULT_Y = 100

-- Timeline (archive 162-166 + 2369+, trimmed; no db options in this lane).
local TIMELINE_WIDTH = 600
local TIMELINE_PPS = 80
local TIMELINE_LANE_HEIGHT = 24
local TIMELINE_ICON_SIZE = 20
local TIMELINE_LABEL_WIDTH = 60
local TIMELINE_RULER_HEIGHT = 46
local ROTATION_BAND_ICON_SIZE = 14
local ROTATION_BAND_ICON_SPACING = 2
local ROTATION_BAND_MAX_ICONS = 5

-- Timeline lane -> spell id for lane icons and split-seal textures.
local LANE_SPELL_IDS = {
    sob = 31892, cs = 35395, consec = 26573, soc = 20375, judge = 20271,
}

-- Rotation step -> spell id for the rotation display icons (twist is split halves).
local STEP_SPELL_IDS = { cs = 35395, cs_late = 35395, blood_auto = 31892, cmd_auto = 20375 }
local BLOOD_SPELL_ID = 31892
local COMMAND_SPELL_ID = 20375
local BLOODLUST_SPELL_ID = 2825
local BLOODLUST_FALLBACK = "Interface\\Icons\\Spell_Nature_Bloodlust"
local DST_ITEM_ID = 28830
local DST_FALLBACK = "Interface\\Icons\\INV_Misc_Bone_06"

-- Per-rotation band colours (archive 2148-2158).
local ROTATION_BAND_COLORS = {
    ["1/2"] = { 0.12, 0.25, 0.50 },
    ["2/3"] = { 0.40, 0.15, 0.50 },
    ["1/3"] = { 0.15, 0.40, 0.25 },
    ["2/4"] = { 0.50, 0.30, 0.10 },
    ["2/5_blood"] = { 0.50, 0.12, 0.12 },
    ["2/5_command"] = { 0.45, 0.45, 0.12 },
    ["2/2/5"] = { 0.15, 0.35, 0.50 },
    ["2007"] = { 0.35, 0.20, 0.40 },
}
local ROTATION_BAND_FALLBACK = { 0.30, 0.30, 0.30 }

-- Rotation selector grid (archive 816-822).
local ROT_GRID = { { "auto", "1/2" }, { "2/3", "2/4" } }
local ROT_LABELS = { auto = "Raid Pull", ["1/2"] = "1/2", ["2/3"] = "2/3", ["2/4"] = "2/4" }

-- Bare modifier keys the capture overlay ignores (archive 237-242).
local IGNORE_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
    UNKNOWN = true,
}

-- Buff border highlights (archive update_icon_states 3564-3592).
local BORDER_IDLE = { 0.3, 0.3, 0.3, 0.8 }
local BORDER_SEAL = { 0.0, 0.8, 0.0, 0.9 }
local BORDER_AW = { 1.0, 0.8, 0.0, 0.9 }
local BORDER_HPOT = { 1.0, 0.55, 0.0, 0.9 }
local BORDER_ABACUS = { 0.6, 0.2, 0.8, 0.9 }

-- Future sim deadlines that the real-combat pause must carry over the pause (see
-- shift_sim_times). Cooldowns of abilities the sim tracks, buff windows, the seal fade,
-- the swing, the GCD and the queue timestamp all live on the same clock domain.
local SHIFTED_SIM_TIMES = {
    "swing_ends_at",
    "gcd_expires",
    "fading_seal_expires",
    "bl_buff_expires",
    "haste_pot_buff_expires",
    "abacus_buff_expires",
    "abacus_cooldown_expires",
    "dst_buff_expires",
    "dst_icd_expires",
    "cs_cooldown_expires",
    "judge_cooldown_expires",
    "consec_cooldown_expires",
    "aw_cooldown_expires",
    "aw_buff_expires",
    "queue_timestamp",
}

--=========================================================================================
-- Small helpers
--=========================================================================================
-- Anchors a practice frame to the mainhand bar (the archive's geometry), falling back
-- to UIParent's centre when the bar frame does not exist. The frames are built in
-- post_init, after init_timers, so the fallback is only a guard.
local function anchor_to_mainhand_bar(self, frame, point, bar_point, x, y)
    frame:ClearAllPoints()
    local bar = self:get_bar_frame("mainhand")
    if bar then
        frame:SetPoint(point, bar, bar_point, x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- The equipped mainhand swing speed (the archive's UnitAttackSpeed source), or nil.
local function get_equipped_speed()
    local speed = api.UnitAttackSpeed("player")
    if type(speed) == "number" and speed > 0 then
        return speed
    end
    return nil
end

-- Base swing speed for a session: the configured override when set (a positive
-- practice_weapon_speed), else the equipped weapon, else the engine's 3.5 s fallback.
local function resolve_base_speed(db)
    local override = db.practice_weapon_speed
    if type(override) == "number" and override > 0 then
        return override
    end
    return get_equipped_speed() or 3.5
end

-- Icon texture for a spell id through the cross-client wrappers (nil when unknown).
local function spell_texture(spell_id)
    if not spell_id then
        return nil
    end
    if api.GetSpellInfo then
        local _, _, icon = api.GetSpellInfo(spell_id)
        if icon then
            return icon
        end
    end
    if GetSpellTexture then
        local icon = GetSpellTexture(spell_id)
        if icon then
            return icon
        end
    end
    return nil
end

-- Icon texture for an ability key (panel icons, timeline cast events).
local function ability_texture(key)
    local pr = st.practice
    local ab = pr and pr.ABILITIES[key]
    if not ab then
        return nil
    end
    if ab.texture then
        return ab.texture
    end
    return spell_texture(ab.spell_id)
end

-- Applies a started-or-updated cooldown swipe once per cooldown, following the
-- codebase's set-once latch pattern (nextaction_ui.lua set_icon_cooldown). `state` is
-- the per-swipe bookkeeping table ({swipe_set, swipe_prev}); an upward jump in
-- remaining means a new cooldown started without an observed gap.
local function set_swipe(state, cooldown, remaining, full_duration)
    remaining = remaining or 0
    if remaining > (state.swipe_prev or 0) + 0.1 then
        state.swipe_set = false
    end
    state.swipe_prev = remaining
    if remaining > 0 then
        if not state.swipe_set then
            cooldown:SetCooldown(api.get_time() - (full_duration - remaining), full_duration)
            state.swipe_set = true
        end
    elseif state.swipe_set then
        cooldown:SetCooldown(0, 0)
        state.swipe_set = false
    end
end

-- The archive's button widget (create_toggle_button 735-759), minus the toggle state
-- colours the practice UI sets through update_button.
local function create_button(parent, label)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(90, 22)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetPoint("CENTER", 0, 0)
    btn.label:SetFontObject(GameFontHighlightSmall)
    btn.label:SetText(label)
    return btn
end

-- One clickable ability icon (archive create_ability_row body 634-691, minus the
-- action-bar linking: right-click assigns a session-local key through the capture
-- overlay, left-click casts): icon texture, border, ability-cooldown swipe,
-- GCD swipe + GCD dim overlays, keybind label, left-click cast.
local function create_ability_icon(parent, key, ab)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon.key = key

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    local texture = ab.texture
    if not texture and ab.spell_id and api.GetSpellInfo then
        texture = select(3, api.GetSpellInfo(ab.spell_id))
    end
    if texture then
        icon.texture:SetTexture(texture)
    end
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    icon.border = icon:CreateTexture(nil, "OVERLAY", nil, 1)
    icon.border:SetPoint("TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    icon.border:SetDrawLayer("OVERLAY", -1)

    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawEdge(false)
    if icon.cooldown.SetHideCountdownNumbers then
        icon.cooldown:SetHideCountdownNumbers(true)
    end

    icon.gcd_cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.gcd_cooldown:SetAllPoints()
    icon.gcd_cooldown:SetDrawEdge(false)
    if icon.gcd_cooldown.SetHideCountdownNumbers then
        icon.gcd_cooldown:SetHideCountdownNumbers(true)
    end

    icon.gcd_dim = icon:CreateTexture(nil, "OVERLAY")
    icon.gcd_dim:SetAllPoints()
    icon.gcd_dim:SetColorTexture(0, 0, 0, 0.5)
    icon.gcd_dim:Hide()

    -- Keybind label (archive 666-670; text comes from update_keybind_labels).
    icon.keybind_text = icon:CreateFontString(nil, "OVERLAY")
    icon.keybind_text:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2)
    icon.keybind_text:SetFontObject(NumberFontNormalSmallGray or GameFontHighlightSmall)
    icon.keybind_text:SetText("")

    icon:EnableMouse(true)
    icon:SetScript("OnMouseDown", function(_, button)
        if not ui.active then
            return
        end
        if button == "RightButton" then
            ui.start_key_capture(ST, key)
        elseif button == "LeftButton" then
            ui.cast_key(ST, key)
        end
    end)

    -- Icon mapping for refresh_icons: the sim cooldown field where the engine keeps one
    -- (cs/judge/consec/aw/abacus - every ability with a cooldown), and whether the sim's
    -- GCD gates the cast (everything except Judgement, AW, the trinket and stopattack;
    -- see practice.lua cast()'s gate). Both swipe bookkeeping tables use the set-once
    -- latch above.
    icon.cooldown_field = (ab.cooldown and ab.cooldown > 0) and (key .. "_cooldown_expires") or nil
    icon.cooldown_full = ab.cooldown
    icon.gcd_gated = not (key == "judge" or ab.type == "buff" or ab.type == "haste_trinket"
        or ab.type == "stopattack")
    icon.ability_swipe = {}
    icon.gcd_swipe = {}
    return icon
end

--=========================================================================================
-- Frame construction (called once from ST.PALADIN.post_init, out of combat)
--=========================================================================================
function ui.init(self)
    if ui.panel then
        return
    end
    local pr = st.practice
    if not pr then
        -- The pure engine module is not loaded on this flavor: nothing to run.
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Frames are only ever created out of combat. The init deadline in main.lua can
        -- land while the player is already in combat (reload mid-fight): retry shortly
        -- instead of leaving practice unavailable for the rest of the session.
        if not ui.init_retry_armed then
            ui.init_retry_armed = true
            C_Timer.After(1, function()
                ui.init_retry_armed = false
                ui.init(self)
            end)
        end
        return
    end
    ui.sim = pr.new_sim()
    ui.bar_mappings = {}
    -- Reused output tables: no per-frame allocations (the engine fills them).
    ui.out = {}
    ui.grade_out = {}
    ui.cast_out = {}
    ui.combat_paused = false
    ui.result_remaining = 0
    ui.dst_enabled = false
    ui.keybinds = {}
    ui.timeline_events = {}
    ui.timeline_event_count = 0
    ui.timeline_bands = {}
    ui.timeline_band_count = 0
    ui.timeline_visible = false
    ui.timeline_needs_render = false
    ui.score = nil
    ui.bests = nil
    ui.last_score_text = nil
    ui.rot_x = ROT_DISPLAY_DEFAULT_X
    ui.rot_y = ROT_DISPLAY_DEFAULT_Y
    ui.current_display_rotation = nil
    ui.build_result_frame(self)
    ui.build_panel(self)
    ui.build_key_buttons(self)
    ui.build_rotation_display(self)
    ui.build_timeline(self)
    ui.build_proc_icons(self)
    ui.apply_settings(self)
end

function ui.build_result_frame(self)
    local result = CreateFrame("Frame", addon_name .. "PracticeResultFrame", UIParent)
    ui.result_frame = result
    result:SetSize(RESULT_WIDTH, RESULT_HEIGHT)
    anchor_to_mainhand_bar(self, result, "BOTTOM", "TOP", 0, 8)
    result:SetFrameStrata("HIGH")
    result.text = result:CreateFontString(nil, "OVERLAY")
    result.text:SetPoint("CENTER", 0, 0)
    result.text:SetShadowColor(0, 0, 0, 1)
    result.text:SetShadowOffset(2, -2)
    result.text:SetText("")
    ui.update_result_font(self)
    result:SetAlpha(0)
end

function ui.build_panel(self)
    local panel = CreateFrame("Frame", addon_name .. "PracticeControlFrame", UIParent,
        "BackdropTemplate")
    ui.panel = panel
    panel:SetSize(PANEL_WIDTH, 160) -- resized to the content below
    anchor_to_mainhand_bar(self, panel, "TOPLEFT", "TOPRIGHT", PANEL_ANCHOR_GAP, 0)
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    panel:SetScript("OnDragStart", function(f)
        -- Repositioning is only ever user-driven and never during lockdown.
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        f:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        ui.save_position(self)
    end)

    local y = -8

    -- Title (archive: "|cFFFF8800Twist Practice|r", GameFontNormal).
    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetPoint("TOP", panel, "TOP", 0, y)
    panel.title:SetFontObject(GameFontNormal)
    panel.title:SetText("|cFFFF8800Twist Practice|r")
    y = y - 16

    -- Close button = stop the session (archive close_btn 590-597).
    local close_btn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close_btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    close_btn:SetSize(20, 20)
    close_btn:SetScript("OnClick", function()
        ui.stop(ST)
    end)

    -- Speed / GCD info line.
    panel.info_text = panel:CreateFontString(nil, "OVERLAY")
    panel.info_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.info_text:SetFontObject(GameFontHighlightSmall)
    panel.info_text:SetText("Speed: --  GCD: --")
    y = y - 16

    -- Rotation line (archive update_info_display 3677-3687, second half).
    panel.rotation_text = panel:CreateFontString(nil, "OVERLAY")
    panel.rotation_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.rotation_text:SetFontObject(GameFontHighlightSmall)
    panel.rotation_text:SetText("Rotation: --")
    y = y - 16

    -- Ability grid: the engine's own order, two rows of five (archive row layout).
    local pr = st.practice
    local order = pr.ABILITY_ORDER
    local rows = math.ceil(#order / ICONS_PER_ROW)
    for row = 1, rows do
        local first = (row - 1) * ICONS_PER_ROW + 1
        local last = math.min(row * ICONS_PER_ROW, #order)
        local count = last - first + 1
        local total_width = count * ICON_SIZE + (count - 1) * ICON_SPACING
        local start_x = -total_width / 2 + ICON_SIZE / 2
        for i = first, last do
            local key = order[i]
            local icon = create_ability_icon(panel, key, pr.ABILITIES[key])
            icon:SetPoint("TOP", panel, "TOP",
                start_x + (i - first) * (ICON_SIZE + ICON_SPACING), y)
            panel.ability_icons = panel.ability_icons or {}
            panel.ability_icons[key] = icon
        end
        y = y - ICON_SIZE - 4
    end
    y = y - 2

    -- Hint line: doubles as the real-combat pause notice.
    panel.hint_text = panel:CreateFontString(nil, "OVERLAY")
    panel.hint_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.hint_text:SetWidth(PANEL_WIDTH - 16)
    panel.hint_text:SetWordWrap(true)
    panel.hint_text:SetJustifyH("CENTER")
    panel.hint_text:SetFont(STANDARD_TEXT_FONT, 9, "")
    panel.hint_text:SetTextColor(0.5, 0.5, 0.5, 0.8)
    panel.hint_text:SetText(HINT_STOPPED)
    y = y - 26

    -- Start/Stop Fight button.
    panel.fight_btn = create_button(panel, "Start Fight")
    panel.fight_btn:SetPoint("TOP", panel, "TOP", 0, y)
    panel.fight_btn:SetScript("OnClick", function()
        ui.toggle_fight(ST)
    end)
    y = y - 22

    -- Fight timer text (archive 875-879; empty outside fights).
    panel.fight_timer_text = panel:CreateFontString(nil, "OVERLAY")
    panel.fight_timer_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.fight_timer_text:SetFontObject(GameFontHighlightSmall)
    panel.fight_timer_text:SetText("")
    y = y - 14

    -- Session score line (scoring section below; empty until the first attempt).
    panel.score_text = panel:CreateFontString(nil, "OVERLAY")
    panel.score_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.score_text:SetFontObject(GameFontHighlightSmall)
    panel.score_text:SetText("")
    y = y - 14

    -- Haste buttons (archive 761-796): Bloodlust left, Haste Pot right, each with a
    -- countdown label. Bloodlust is silent during a fight (auto-controlled there).
    panel.bl_btn = create_button(panel, "Bloodlust")
    panel.bl_btn:ClearAllPoints()
    panel.bl_btn:SetPoint("TOPRIGHT", panel, "TOP", -2, y)
    panel.bl_btn:SetScript("OnClick", function()
        ui.click_haste(ST, "bl")
    end)
    panel.bl_btn.countdown = panel.bl_btn:CreateFontString(nil, "OVERLAY")
    panel.bl_btn.countdown:SetPoint("RIGHT", panel.bl_btn, "RIGHT", -4, 0)
    panel.bl_btn.countdown:SetFontObject(GameFontHighlightSmall)
    panel.bl_btn.countdown:SetText("")

    panel.hp_btn = create_button(panel, "Haste Pot")
    panel.hp_btn:ClearAllPoints()
    panel.hp_btn:SetPoint("TOPLEFT", panel, "TOP", 2, y)
    panel.hp_btn:SetScript("OnClick", function()
        ui.click_haste(ST, "hpot")
    end)
    panel.hp_btn.countdown = panel.hp_btn:CreateFontString(nil, "OVERLAY")
    panel.hp_btn.countdown:SetPoint("RIGHT", panel.hp_btn, "RIGHT", -4, 0)
    panel.hp_btn.countdown:SetFontObject(GameFontHighlightSmall)
    panel.hp_btn.countdown:SetText("")
    y = y - 28

    -- DST proc toggle (session-local; the archived practice_dst_enabled option is out
    -- of scope, so the toggle lives on the panel instead of in the options).
    panel.dst_btn = create_button(panel, "DST: Off")
    panel.dst_btn:SetPoint("TOP", panel, "TOP", 0, y)
    panel.dst_btn:SetScript("OnClick", function()
        ui.click_haste(ST, "dst")
    end)
    y = y - 28

    -- Rotation selector (archive 807-862): Raid Pull (auto) plus the three locked
    -- presets. Clicking the active preset reverts to auto (engine toggle semantics
    -- live in set_locked_rotation).
    local rot_label = panel:CreateFontString(nil, "OVERLAY")
    rot_label:SetPoint("TOP", panel, "TOP", 0, y)
    rot_label:SetFontObject(GameFontHighlightSmall)
    rot_label:SetText("Practice Rotation")
    y = y - 14

    panel.rot_buttons = {}
    local rot_btn_w, rot_btn_h = 88, 20
    local rot_btn_spacing = 2
    local rot_total_w = 2 * rot_btn_w + 1 * rot_btn_spacing
    for row_i, row in ipairs(ROT_GRID) do
        for col_i, rot_key in ipairs(row) do
            local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
            btn:SetSize(rot_btn_w, rot_btn_h)
            local bx = -rot_total_w / 2 + (col_i - 1) * (rot_btn_w + rot_btn_spacing)
                + rot_btn_w / 2
            local by = y - (row_i - 1) * (rot_btn_h + rot_btn_spacing)
            btn:SetPoint("TOP", panel, "TOP", bx, by)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 8, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
            btn.label = btn:CreateFontString(nil, "OVERLAY")
            btn.label:SetPoint("CENTER", 0, 0)
            btn.label:SetFontObject(GameFontHighlightSmall)
            btn.label:SetText(ROT_LABELS[rot_key] or rot_key)
            btn.rot_key = rot_key
            btn:SetScript("OnClick", function(self_btn)
                if self_btn.rot_key == "auto" then
                    ui.set_locked_rotation(ST, nil)
                else
                    ui.set_locked_rotation(ST, self_btn.rot_key)
                end
            end)
            panel.rot_buttons[rot_key] = btn
        end
    end
    y = y - (#ROT_GRID * (rot_btn_h + rot_btn_spacing) + 4)

    -- Timeline toggle button (archive 895-899).
    panel.timeline_btn = create_button(panel, "Timeline")
    panel.timeline_btn:ClearAllPoints()
    panel.timeline_btn:SetPoint("TOP", panel, "TOP", 0, y)
    panel.timeline_btn:SetScript("OnClick", function()
        ui.toggle_timeline(ST)
    end)
    y = y - 28

    panel:SetHeight(math.abs(y) + 8)
    panel:Hide()

    -- Driver: the module's own OnUpdate frame (see the header); hidden outside sessions.
    local driver = CreateFrame("Frame", addon_name .. "PracticeDriverFrame", UIParent)
    ui.driver = driver
    driver:SetScript("OnUpdate", function(_, elapsed)
        ui.tick(ST, elapsed)
    end)
    driver:Hide()

    ui.build_bar_mappings(self)
end

--=========================================================================================
-- Bar mappings (phase 2: the panel icon bar itself; action-bar overlays land in phase 3)
--=========================================================================================
function ui.build_bar_mappings(self)
    local panel = ui.panel
    if not panel or not panel.ability_icons then
        return
    end
    ui.bar_mappings = ui.bar_mappings or {}
    for key, icon in pairs(panel.ability_icons) do
        ui.bar_mappings[key] = icon
    end
end

--=========================================================================================
-- Keybinds: session-local capture + override bindings
--=========================================================================================

-- Invisible click targets for SetOverrideBindingClick (archive init 506-522). The
-- buttons live on the panel so they die with it; bindings are applied by
-- rebind_keys() and cleared on stop().
function ui.build_key_buttons(self)
    local panel = ui.panel
    if not panel then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    ui.buttons = ui.buttons or {}
    for _, key in ipairs(pr.ABILITY_ORDER) do
        if not ui.buttons[key] then
            local btn = CreateFrame("Button", addon_name .. "PracticeKey" .. key, panel)
            btn:SetSize(1, 1)
            btn:SetPoint("CENTER", panel, "CENTER", 0, 0)
            btn:EnableMouse(false)
            if btn.RegisterForClicks then
                btn:RegisterForClicks("AnyUp")
            end
            btn.key_name = addon_name .. "PracticeKey" .. key
            local capture = key
            btn:SetScript("OnClick", function()
                ui.cast_key(ST, capture)
            end)
            ui.buttons[key] = btn
        end
    end
end

-- Applies the session-local keybinds as override bindings (archive rebind_keys
-- 1309-1326, minus persistence). Safe to call under lockdown: it simply skips the
-- apply and leaves the labels alone.
function ui.rebind_keys(self)
    local panel = ui.panel
    if not panel or not ui.buttons then
        return
    end
    if not (ui.active and SetOverrideBindingClick and ClearOverrideBindings) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    ClearOverrideBindings(panel)
    local pr = st.practice
    if not pr then
        return
    end
    for _, key in ipairs(pr.ABILITY_ORDER) do
        local bind = ui.keybinds and ui.keybinds[key]
        local btn = ui.buttons[key]
        if bind and bind ~= "" and btn then
            local name = (btn.GetName and btn:GetName()) or btn.key_name
            SetOverrideBindingClick(panel, false, bind, name)
        end
    end
    ui.update_keybind_labels(self)
end

-- Refreshes the keybind labels on the panel icons from ui.keybinds.
function ui.update_keybind_labels(self)
    local panel = ui.panel
    if not panel or not panel.ability_icons then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    for _, key in ipairs(pr.ABILITY_ORDER) do
        local icon = panel.ability_icons[key]
        if icon and icon.keybind_text then
            local bind = ui.keybinds and ui.keybinds[key] or ""
            icon.keybind_text:SetText(pr.shorten_keybind(bind))
        end
    end
end

-- Modifier prefix from the current key state (archive get_modifier_prefix 228-234).
local function capture_modifier_prefix()
    local prefix = ""
    if IsControlKeyDown and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsAltKeyDown and IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsShiftKeyDown and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix
end

-- Lazily creates the fullscreen key-capture overlay (archive 261-332, trimmed: no
-- gamepad-emulator CVar probe beyond the guarded EnableGamePadButton hook).
local function get_or_create_key_capture_frame()
    if ui.key_capture_frame then
        return ui.key_capture_frame
    end
    local f = CreateFrame("Frame", addon_name .. "PracticeKeyCapture", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(true)
    if f.EnableMouseWheel then
        f:EnableMouseWheel(true)
    end
    if f.EnableKeyboard then
        f:EnableKeyboard(false)
    end

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.5)

    f.prompt = f:CreateFontString(nil, "OVERLAY")
    f.prompt:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    f.prompt:SetPoint("CENTER", 0, 20)
    f.prompt:SetTextColor(1, 1, 1, 1)

    f.hint = f:CreateFontString(nil, "OVERLAY")
    f.hint:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    f.hint:SetPoint("CENTER", 0, -10)
    f.hint:SetTextColor(0.7, 0.7, 0.7, 1)
    f.hint:SetText("ESC or right-click to cancel")

    f:SetScript("OnKeyDown", function(_, key)
        if IGNORE_KEYS[key] then
            return
        end
        if key == "ESCAPE" then
            ui.cancel_key_capture(ST)
            return
        end
        ui.finish_key_capture(ST, capture_modifier_prefix() .. key)
    end)

    f:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            return
        end
        if button == "RightButton" then
            ui.cancel_key_capture(ST)
            return
        end
        local mouse_map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
        local mapped = mouse_map[button] or button
        ui.finish_key_capture(ST, capture_modifier_prefix() .. mapped)
    end)

    f:SetScript("OnMouseWheel", function(_, delta)
        local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        ui.finish_key_capture(ST, capture_modifier_prefix() .. key)
    end)

    if f.EnableGamePadButton then
        f:SetScript("OnGamePadButtonDown", function(_, button)
            ui.finish_key_capture(ST, capture_modifier_prefix() .. button)
        end)
    end

    f:Hide()
    ui.key_capture_frame = f
    return f
end

-- Starts capturing a key for an ability (right-click a panel icon). Pre-init safe.
function ui.start_key_capture(self, ability_key)
    self = self or ST
    if not ui.active or not ability_key then
        return
    end
    ui.key_capture_ability = ability_key
    local pr = st.practice
    local name = (pr and pr.ABILITIES[ability_key] and pr.ABILITIES[ability_key].name)
        or ability_key
    local f = get_or_create_key_capture_frame()
    f.prompt:SetText("Press the key for |cFF00FFFF" .. name .. "|r")
    if f.EnableKeyboard then
        f:EnableKeyboard(true)
    end
    if f.EnableGamePadButton then
        f:EnableGamePadButton(true)
    end
    if f.SetPropagateKeyboardInput then
        f:SetPropagateKeyboardInput(false)
    end
    f:Show()
    self:Print(string.format("Press the key for %s (ESC to cancel).", name))
end

-- Stores a captured key (archive finish_key_capture 4157-4186, minus persistence).
function ui.finish_key_capture(self, bind)
    self = self or ST
    local ability_key = ui.key_capture_ability
    if not ability_key then
        return
    end
    ui.cancel_key_capture(self)
    ui.keybinds = ui.keybinds or {}
    ui.keybinds[ability_key] = bind
    if ui.active then
        ui.rebind_keys(self)
    end
    ui.update_keybind_labels(self)
    local pr = st.practice
    local name = (pr and pr.ABILITIES[ability_key] and pr.ABILITIES[ability_key].name)
        or ability_key
    self:Print(string.format("Practice key for %s set to %s.", name, bind))
end

function ui.cancel_key_capture(self)
    ui.key_capture_ability = nil
    local f = ui.key_capture_frame
    if f then
        if f.EnableKeyboard then
            f:EnableKeyboard(false)
        end
        if f.EnableGamePadButton then
            f:EnableGamePadButton(false)
        end
        f:Hide()
    end
end

-- Restores the default keybinds and detaches every overlay (archive
-- reset_all_mappings 3944-3964, minus persistence).
function ui.reset_keybinds(self)
    self = self or ST
    ui.detach_all_overlays(self)
    ui.keybinds = {}
    local pr = st.practice
    if pr then
        for key, bind in pairs(pr.DEFAULT_KEYBINDS) do
            ui.keybinds[key] = bind
        end
    end
    if ui.active then
        ui.rebind_keys(self)
    end
    ui.update_keybind_labels(self)
    self:Print("Practice keybinds have been reset.")
end

--=========================================================================================
-- Haste buttons + rotation selector
--=========================================================================================

-- Haste button clicks (archive bl/hp button bodies 762-789): Bloodlust refuses while
-- a fight runs (auto-controlled there) or the rotation is locked; the haste pot goes
-- through the direct setter so no GCD starts, like the archive's button path.
function ui.click_haste(self, which)
    self = self or ST
    if not ui.active then
        return
    end
    local pr = st.practice
    local sim = ui.sim
    if not pr or not sim then
        return
    end
    local now = api.get_time()
    if which == "bl" then
        if sim.fight_active or sim.locked_rotation or sim.has_bloodlust then
            return
        end
        if pr.set_bloodlust(sim, now, true) then
            pr.apply_haste(sim, ui.base_speed, now)
            ui.update_haste_buttons(self)
            ui.update_info(self)
            ui.sync_to_addon(self)
        end
    elseif which == "hpot" then
        if sim.has_haste_pot then
            return
        end
        if pr.set_haste_pot(sim, now, true) then
            pr.apply_haste(sim, ui.base_speed, now)
            ui.update_haste_buttons(self)
            ui.update_info(self)
            ui.sync_to_addon(self)
        end
    elseif which == "dst" then
        ui.dst_enabled = not ui.dst_enabled
        if not ui.dst_enabled then
            sim.has_dst = false
            sim.dst_buff_expires = 0
            pr.apply_haste(sim, ui.base_speed, now)
        end
        ui.update_haste_buttons(self)
        ui.update_proc_icons(self)
    end
end

-- Countdown + active/disabled visuals for the three haste buttons (archive
-- sim_update 3336-3364 countdown halves + set_haste_buttons_enabled 1234-1256).
function ui.update_haste_buttons(self)
    local panel = ui.panel
    if not panel then
        return
    end
    local sim = ui.sim
    local now = api.get_time()
    local locked = sim and sim.locked_rotation or nil
    if panel.bl_btn then
        local remaining = (sim and sim.has_bloodlust and sim.bl_buff_expires > now)
            and math.ceil(sim.bl_buff_expires - now) or 0
        if panel.bl_btn.countdown then
            panel.bl_btn.countdown:SetText(remaining > 0 and tostring(remaining) or "")
        end
        if sim and sim.has_bloodlust then
            panel.bl_btn:SetBackdropColor(0.1, 0.3, 0.6, 0.9)
            panel.bl_btn.label:SetText("|cFF00FFFFBloodlust|r")
        else
            panel.bl_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.bl_btn.label:SetText("Bloodlust")
        end
    end
    if panel.hp_btn then
        local remaining = (sim and sim.has_haste_pot and sim.haste_pot_buff_expires > now)
            and math.ceil(sim.haste_pot_buff_expires - now) or 0
        if panel.hp_btn.countdown then
            panel.hp_btn.countdown:SetText(remaining > 0 and tostring(remaining) or "")
        end
        if sim and sim.has_haste_pot then
            panel.hp_btn:SetBackdropColor(0.5, 0.3, 0.1, 0.9)
            panel.hp_btn.label:SetText("|cFFFF8800Haste Pot|r")
        else
            panel.hp_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.hp_btn.label:SetText("Haste Pot")
        end
    end
    if panel.dst_btn then
        if ui.dst_enabled then
            panel.dst_btn:SetBackdropColor(0.1, 0.4, 0.1, 0.9)
            panel.dst_btn.label:SetText("|cFF00FF00DST: On|r")
        else
            panel.dst_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.dst_btn.label:SetText("DST: Off")
        end
    end
    ui.set_haste_buttons_enabled(not locked)
end

-- Dims the Bloodlust/Haste-pot buttons while a rotation is locked (archive
-- set_haste_buttons_enabled 1234-1256).
function ui.set_haste_buttons_enabled(enabled)
    local panel = ui.panel
    if not panel then
        return
    end
    for _, btn in ipairs({ panel.bl_btn, panel.hp_btn }) do
        if btn then
            if enabled then
                btn:SetAlpha(1.0)
                btn:EnableMouse(true)
            else
                btn:SetAlpha(0.4)
                btn:EnableMouse(false)
            end
        end
    end
end

-- Locks (or unlocks, on a repeat click) a practice rotation (archive
-- set_locked_rotation 1258-1304): locking clears every haste effect and disables
-- the haste buttons; either way the speed/GCD are re-derived immediately.
function ui.set_locked_rotation(self, rot_key)
    self = self or ST
    local pr = st.practice
    local sim = ui.sim
    if not pr or not sim then
        return
    end
    if rot_key and rot_key == sim.locked_rotation then
        rot_key = nil
    end
    sim.locked_rotation = rot_key
    local now = api.get_time()
    if rot_key then
        pr.set_bloodlust(sim, now, false)
        pr.set_haste_pot(sim, now, false)
        sim.has_abacus = false
        sim.abacus_buff_expires = 0
        sim.has_dst = false
        sim.dst_buff_expires = 0
        ui.set_haste_buttons_enabled(false)
    else
        ui.set_haste_buttons_enabled(true)
    end
    pr.apply_haste(sim, ui.base_speed, now)
    local panel = ui.panel
    if panel and panel.rot_buttons then
        for key, btn in pairs(panel.rot_buttons) do
            local is_active = (key == "auto" and rot_key == nil) or (key == rot_key)
            if is_active then
                btn:SetBackdropColor(0.1, 0.4, 0.1, 0.9)
                btn.label:SetText("|cFF00FF00" .. (ROT_LABELS[key] or key) .. "|r")
            else
                btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
                btn.label:SetText(ROT_LABELS[key] or key)
            end
        end
    end
    ui.current_display_rotation = nil
    ui.update_rotation_display(self)
    ui.update_haste_buttons(self)
    ui.update_info(self)
    ui.refresh_icons(self)
    ui.sync_to_addon(self)
end

--=========================================================================================
-- Center-screen rotation display (archive 1461-1662)
--=========================================================================================

-- One rotation step icon (archive create_rotation_display_icon 1465-1498): a full
-- texture plus split halves for twist steps.
local function create_rotation_icon(parent, size)
    local icon_frame = CreateFrame("Frame", nil, parent)
    icon_frame:SetSize(size, size)

    icon_frame.border = icon_frame:CreateTexture(nil, "BACKGROUND")
    icon_frame.border:SetPoint("TOPLEFT", -1, 1)
    icon_frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    icon_frame.border:SetColorTexture(0, 0, 0, 0.8)

    icon_frame.texture = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.texture:SetAllPoints()
    icon_frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    icon_frame.twist_left = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.twist_left:SetPoint("TOPLEFT", 0, 0)
    icon_frame.twist_left:SetPoint("BOTTOMLEFT", 0, 0)
    icon_frame.twist_left:SetWidth(size / 2)
    icon_frame.twist_left:SetTexCoord(0.07, 0.5, 0.07, 0.93)
    icon_frame.twist_left:Hide()

    icon_frame.twist_right = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.twist_right:SetPoint("TOPRIGHT", 0, 0)
    icon_frame.twist_right:SetPoint("BOTTOMRIGHT", 0, 0)
    icon_frame.twist_right:SetWidth(size / 2)
    icon_frame.twist_right:SetTexCoord(0.5, 0.93, 0.07, 0.93)
    icon_frame.twist_right:Hide()

    icon_frame:Hide()
    return icon_frame
end

-- Paints one rotation step onto an icon frame (the archived
-- st.bar.set_rotation_icon_texture was never ported, so the mapping lives here):
-- twist is split Command/Blood halves, everything else a single spell texture.
local function set_step_texture(icon_frame, step)
    local left_hide, right_hide = true, true
    if step == "twist" then
        local cmd = spell_texture(COMMAND_SPELL_ID)
        local blood = spell_texture(BLOOD_SPELL_ID)
        if cmd then
            icon_frame.twist_left:SetTexture(cmd)
            left_hide = false
        end
        if blood then
            icon_frame.twist_right:SetTexture(blood)
            right_hide = false
        end
        if icon_frame.texture then
            icon_frame.texture:SetTexture(nil)
        end
    else
        local spell_id = STEP_SPELL_IDS[step]
        local tex = spell_texture(spell_id)
        if tex and icon_frame.texture then
            icon_frame.texture:SetTexture(tex)
        end
    end
    if left_hide then
        icon_frame.twist_left:Hide()
    else
        icon_frame.twist_left:Show()
    end
    if right_hide then
        icon_frame.twist_right:Hide()
    else
        icon_frame.twist_right:Show()
    end
end

-- Exposed for the timeline band icons (same step mapping).
function ui.set_step_texture(icon_frame, step)
    set_step_texture(icon_frame, step)
end

-- Builds the free-floating rotation display (archive create_rotation_display
-- 1501-1552, session-local position).
function ui.build_rotation_display(self)
    if not ui.panel then
        return
    end
    local frame = CreateFrame("Frame", addon_name .. "PracticeRotationDisplay", UIParent)
    ui.rotation_display = frame
    frame:SetSize(300, 100)
    frame:SetPoint("CENTER", UIParent, "CENTER", ui.rot_x or 0, ui.rot_y or 100)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(f)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        ui.save_rotation_position(self)
    end)

    frame.rotation_name = frame:CreateFontString(nil, "OVERLAY")
    frame.rotation_name:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    frame.rotation_name:SetPoint("BOTTOM", frame, "CENTER", 0, ROT_ICON_SIZE / 2 + 4)
    frame.rotation_name:SetTextColor(1, 0.82, 0, 1)
    frame.rotation_name:SetShadowColor(0, 0, 0, 1)
    frame.rotation_name:SetShadowOffset(1, -1)
    frame.rotation_name:SetText("")

    frame.desc_text = frame:CreateFontString(nil, "OVERLAY")
    frame.desc_text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    frame.desc_text:SetPoint("TOP", frame, "CENTER", 0, -(ROT_ICON_SIZE / 2 + 4))
    frame.desc_text:SetTextColor(0.65, 0.65, 0.65, 1)
    frame.desc_text:SetShadowColor(0, 0, 0, 1)
    frame.desc_text:SetShadowOffset(1, -1)
    frame.desc_text:SetText("")

    ui.rotation_icons = {}
    for i = 1, ROT_DISPLAY_MAX_ICONS do
        ui.rotation_icons[i] = create_rotation_icon(frame, ROT_ICON_SIZE)
    end
    frame:Hide()
end

-- Stores the dragged display position as a center offset (session-local).
function ui.save_rotation_position(self)
    local frame = ui.rotation_display
    if not frame or not UIParent then
        return
    end
    if not (frame.GetCenter and UIParent.GetCenter) then
        return
    end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then
        return
    end
    ui.rot_x = math.floor(cx - ux + 0.5)
    ui.rot_y = math.floor(cy - uy + 0.5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", ui.rot_x, ui.rot_y)
end

-- Updates the rotation display: texts + icons, static reference, no step tracking
-- (archive update_rotation_display 1582-1662). `rotation` may be passed by the tick
-- to avoid a second determine_rotation call.
function ui.update_rotation_display(self, rotation)
    local frame = ui.rotation_display
    if not frame then
        return
    end
    local pr = st.practice
    local sim = ui.sim
    if not pr or not sim then
        return
    end
    rotation = rotation or pr.determine_rotation(sim)
    if not ui.active or not rotation then
        ui.current_display_rotation = rotation
        frame:Hide()
        return
    end
    local na = st.nextaction
    local sequence = (na and na.sequences and na.sequences[rotation]) or {}
    if #sequence == 0 then
        ui.current_display_rotation = rotation
        frame:Hide()
        return
    end
    ui.current_display_rotation = rotation
    frame:Show()

    local display_name = (na and na.display_names and na.display_names[rotation]) or rotation
    local desc = (na and na.descriptions and na.descriptions[rotation]) or ""
    frame.rotation_name:SetText(display_name)
    frame.desc_text:SetText(desc)

    local size = ROT_ICON_SIZE
    local spacing = ROT_ICON_SPACING
    local num_icons = #sequence
    local total_width = (size * num_icons) + (spacing * (num_icons - 1))
    local start_x = -total_width / 2 + size / 2

    frame.rotation_name:ClearAllPoints()
    frame.rotation_name:SetPoint("BOTTOM", frame, "CENTER", 0, size / 2 + 4)
    frame.desc_text:ClearAllPoints()
    frame.desc_text:SetPoint("TOP", frame, "CENTER", 0, -(size / 2 + 4))
    frame:SetSize(math.max(total_width + 20, 100), size + 50)

    for i = 1, ROT_DISPLAY_MAX_ICONS do
        local icon_frame = ui.rotation_icons[i]
        if icon_frame then
            if i <= num_icons then
                icon_frame:SetSize(size, size)
                icon_frame.twist_left:SetWidth(size / 2)
                icon_frame.twist_right:SetWidth(size / 2)
                icon_frame:ClearAllPoints()
                local x_pos = start_x + (i - 1) * (size + spacing)
                icon_frame:SetPoint("CENTER", frame, "CENTER", x_pos, 0)
                set_step_texture(icon_frame, sequence[i])
                icon_frame:Show()
            else
                icon_frame:Hide()
            end
        end
    end
end

--=========================================================================================
-- Fight timeline (archive 1900-2510, trimmed)
--=========================================================================================

-- Timeline icon pool entry (archive get_timeline_icon 1901-1991, minus the
-- twist-overlay badge sub-frame: twists reuse the error-border-free split look).
local function get_timeline_icon(parent)
    ui.timeline_icon_pool = ui.timeline_icon_pool or {}
    ui.timeline_icon_pool_used = (ui.timeline_icon_pool_used or 0) + 1
    local idx = ui.timeline_icon_pool_used
    local pool = ui.timeline_icon_pool

    if pool[idx] then
        pool[idx]:Show()
        pool[idx].error_border:Hide()
        pool[idx].analysis_data = nil
        return pool[idx]
    end

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(TIMELINE_ICON_SIZE, TIMELINE_ICON_SIZE)

    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints()
    f.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.split_left = f:CreateTexture(nil, "ARTWORK")
    f.split_left:SetPoint("TOPLEFT", 0, 0)
    f.split_left:SetPoint("BOTTOMLEFT", 0, 0)
    f.split_left:SetWidth(TIMELINE_ICON_SIZE / 2)
    f.split_left:SetTexCoord(0.07, 0.5, 0.07, 0.93)
    f.split_left:Hide()

    f.split_right = f:CreateTexture(nil, "ARTWORK")
    f.split_right:SetPoint("TOPRIGHT", 0, 0)
    f.split_right:SetPoint("BOTTOMRIGHT", 0, 0)
    f.split_right:SetWidth(TIMELINE_ICON_SIZE / 2)
    f.split_right:SetTexCoord(0.5, 0.93, 0.07, 0.93)
    f.split_right:Hide()

    f.result_label = f:CreateFontString(nil, "OVERLAY")
    f.result_label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    f.result_label:SetPoint("BOTTOM", f, "TOP", 0, 0)
    f.result_label:SetText("")

    f.error_border = f:CreateTexture(nil, "BACKGROUND")
    f.error_border:SetPoint("TOPLEFT", -2, 2)
    f.error_border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.error_border:SetColorTexture(0.8, 0.1, 0.1, 0.7)
    f.error_border:Hide()

    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self_icon)
        if self_icon.analysis_data and not self_icon.analysis_data.correct and GameTooltip then
            local pr = st.practice
            local labels = (pr and pr.SWING_ACTION_LABELS) or {}
            local expected = labels[self_icon.analysis_data.expected]
                or self_icon.analysis_data.expected
            local actual = labels[self_icon.analysis_data.actual]
                or self_icon.analysis_data.actual
            GameTooltip:SetOwner(self_icon, "ANCHOR_TOP")
            GameTooltip:AddLine("Incorrect action", 1, 0.2, 0.2)
            GameTooltip:AddLine("You did: " .. actual, 1, 1, 1)
            GameTooltip:AddLine("Expected: " .. expected, 0, 1, 0)
            if self_icon.analysis_data.actual == "judge_command" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Judging Rank 1 SoC is a large DPS loss.", 1, 0.5, 0.5)
            end
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    pool[idx] = f
    return f
end

local function reset_timeline_icon_pool()
    if not ui.timeline_icon_pool then
        return
    end
    for i = 1, (ui.timeline_icon_pool_used or 0) do
        if ui.timeline_icon_pool[i] then
            ui.timeline_icon_pool[i]:Hide()
        end
    end
    ui.timeline_icon_pool_used = 0
end

-- Divider pool (archive 2001-2022).
local function get_timeline_divider(parent)
    ui.timeline_divider_pool = ui.timeline_divider_pool or {}
    ui.timeline_divider_pool_used = (ui.timeline_divider_pool_used or 0) + 1
    local idx = ui.timeline_divider_pool_used
    local pool = ui.timeline_divider_pool

    if pool[idx] then
        pool[idx]:Show()
        return pool[idx]
    end

    local t = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
    t:SetColorTexture(0.4, 0.4, 0.4, 0.3)
    pool[idx] = t
    return t
end

local function reset_timeline_divider_pool()
    if not ui.timeline_divider_pool then
        return
    end
    for i = 1, (ui.timeline_divider_pool_used or 0) do
        if ui.timeline_divider_pool[i] then
            ui.timeline_divider_pool[i]:Hide()
        end
    end
    ui.timeline_divider_pool_used = 0
end

-- Ruler tick pool (archive 2025-2057).
local function get_ruler_tick(parent)
    ui.timeline_ruler_pool = ui.timeline_ruler_pool or {}
    ui.timeline_ruler_pool_used = (ui.timeline_ruler_pool_used or 0) + 1
    local idx = ui.timeline_ruler_pool_used
    local pool = ui.timeline_ruler_pool

    if pool[idx] then
        pool[idx].tick:Show()
        pool[idx].label:Show()
        return pool[idx]
    end

    local tick = parent:CreateTexture(nil, "ARTWORK")
    tick:SetColorTexture(0.6, 0.6, 0.6, 0.5)

    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    label:SetTextColor(0.7, 0.7, 0.7, 1)

    local entry = { tick = tick, label = label }
    pool[idx] = entry
    return entry
end

local function reset_timeline_ruler_pool()
    if not ui.timeline_ruler_pool then
        return
    end
    for i = 1, (ui.timeline_ruler_pool_used or 0) do
        local entry = ui.timeline_ruler_pool[i]
        if entry then
            entry.tick:Hide()
            entry.label:Hide()
        end
    end
    ui.timeline_ruler_pool_used = 0
end

-- Rotation band pool (archive 2065-2119): header bg + lane tint + label + icons.
local function get_rotation_band(parent)
    ui.timeline_rotation_band_pool = ui.timeline_rotation_band_pool or {}
    ui.timeline_rotation_band_pool_used = (ui.timeline_rotation_band_pool_used or 0) + 1
    local idx = ui.timeline_rotation_band_pool_used
    local pool = ui.timeline_rotation_band_pool

    if pool[idx] then
        pool[idx].bg:Show()
        pool[idx].lane_tint:Show()
        pool[idx].label:Show()
        return pool[idx]
    end

    local bg = parent:CreateTexture(nil, "ARTWORK", nil, -1)
    local lane_tint = parent:CreateTexture(nil, "BORDER")
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")

    local icons = {}
    for i = 1, ROTATION_BAND_MAX_ICONS do
        icons[i] = create_rotation_icon(parent, ROTATION_BAND_ICON_SIZE)
    end

    local entry = { bg = bg, lane_tint = lane_tint, label = label, icons = icons }
    pool[idx] = entry
    return entry
end

local function reset_rotation_band_pool()
    if not ui.timeline_rotation_band_pool then
        return
    end
    for i = 1, (ui.timeline_rotation_band_pool_used or 0) do
        local entry = ui.timeline_rotation_band_pool[i]
        if entry then
            entry.bg:Hide()
            entry.lane_tint:Hide()
            entry.label:Hide()
            for j = 1, ROTATION_BAND_MAX_ICONS do
                if entry.icons[j] then
                    entry.icons[j]:Hide()
                end
            end
        end
    end
    ui.timeline_rotation_band_pool_used = 0
end

function ui.reset_timeline_pools()
    reset_timeline_icon_pool()
    reset_timeline_divider_pool()
    reset_timeline_ruler_pool()
    reset_rotation_band_pool()
end

-- Renders the rotation bands over the ruler + lane area (archive 2137-2218).
local function render_timeline_bands(scroll_child, total_width)
    reset_rotation_band_pool()
    local pr = st.practice
    local band_count = ui.timeline_band_count or 0
    if band_count == 0 or not pr then
        return
    end
    local content_time = math.max(pr.timeline_max_time(
        ui.timeline_events, ui.timeline_event_count) + 2, 10)
    local num_lanes = #(pr.TIMELINE_LANES or {})
    local lane_area_height = num_lanes * TIMELINE_LANE_HEIGHT
    local na = st.nextaction

    for i = 1, band_count do
        local band_data = ui.timeline_bands[i]
        if band_data then
            local start_x = band_data.start_time * TIMELINE_PPS
            local end_time = (i < band_count and ui.timeline_bands[i + 1])
                and ui.timeline_bands[i + 1].start_time or content_time
            local end_x = end_time * TIMELINE_PPS
            local width = math.max(end_x - start_x, 1)

            local entry = get_rotation_band(scroll_child)
            local color = ROTATION_BAND_COLORS[band_data.rotation] or ROTATION_BAND_FALLBACK

            entry.bg:ClearAllPoints()
            entry.bg:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", start_x, 0)
            entry.bg:SetSize(width, TIMELINE_RULER_HEIGHT)
            entry.bg:SetColorTexture(color[1], color[2], color[3], 0.55)

            entry.lane_tint:ClearAllPoints()
            entry.lane_tint:SetPoint("TOPLEFT", scroll_child, "TOPLEFT",
                start_x, -TIMELINE_RULER_HEIGHT)
            entry.lane_tint:SetSize(width, lane_area_height)
            entry.lane_tint:SetColorTexture(color[1], color[2], color[3], 0.08)

            local display_name = (na and na.display_names and na.display_names[band_data.rotation])
                or band_data.rotation
            entry.label:ClearAllPoints()
            entry.label:SetPoint("TOP", entry.bg, "TOP", 0, -1)
            entry.label:SetText(display_name)
            entry.label:SetTextColor(0.9, 0.9, 0.9, 1)

            local sequence = (na and na.sequences and na.sequences[band_data.rotation]) or {}
            local num_icons = #sequence
            local icons_total_width = (ROTATION_BAND_ICON_SIZE * num_icons)
                + (ROTATION_BAND_ICON_SPACING * math.max(num_icons - 1, 0))
            local band_center_x = start_x + width / 2
            local icons_start_x = band_center_x - icons_total_width / 2
            for j = 1, ROTATION_BAND_MAX_ICONS do
                local icon_frame = entry.icons[j]
                if j <= num_icons then
                    icon_frame:ClearAllPoints()
                    local ix = icons_start_x
                        + (j - 1) * (ROTATION_BAND_ICON_SIZE + ROTATION_BAND_ICON_SPACING)
                    icon_frame:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", ix, -14)
                    set_step_texture(icon_frame, sequence[j])
                    icon_frame:Show()
                else
                    icon_frame:Hide()
                end
            end
        end
    end
end

-- Renders the ruler ticks (archive 2221-2243).
local function render_timeline_ruler(scroll_child, total_width)
    reset_timeline_ruler_pool()
    local pr = st.practice
    if not pr then
        return
    end
    local max_time = pr.timeline_max_time(ui.timeline_events, ui.timeline_event_count)
    for sec = 0, math.ceil(max_time) do
        local x = sec * TIMELINE_PPS
        if x <= total_width then
            local entry = get_ruler_tick(scroll_child)
            entry.tick:SetSize(1, 8)
            entry.tick:ClearAllPoints()
            entry.tick:SetPoint("BOTTOMLEFT", scroll_child, "TOPLEFT", x, -TIMELINE_RULER_HEIGHT)
            local mins = math.floor(sec / 60)
            local secs = sec % 60
            entry.label:ClearAllPoints()
            entry.label:SetPoint("BOTTOM", entry.tick, "TOP", 0, 0)
            entry.label:SetText(string.format("%d:%02d", mins, secs))
            entry.label:Show()
        end
    end
end

-- Full re-render from the event data (archive render_timeline 2246-2366, trimmed).
function ui.render_timeline()
    ui.timeline_needs_render = false
    local frame = ui.timeline_frame
    if not frame or not frame.scroll_child then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    local content_time = math.max(pr.timeline_max_time(
        ui.timeline_events, ui.timeline_event_count) + 2, 10)
    local total_width = content_time * TIMELINE_PPS
    local scroll_child = frame.scroll_child
    scroll_child:SetWidth(total_width)

    ui.reset_timeline_pools()
    render_timeline_bands(scroll_child, total_width)
    render_timeline_ruler(scroll_child, total_width)

    if frame.lane_bgs then
        for _, bg in ipairs(frame.lane_bgs) do
            bg:SetWidth(total_width)
        end
    end

    local analysis = pr.analyze(ui.timeline_events, ui.timeline_event_count,
        ui.timeline_bands, ui.timeline_band_count)
    local num_lanes = #(pr.TIMELINE_LANES or {})
    for i = 1, (ui.timeline_event_count or 0) do
        local event = ui.timeline_events[i]
        local lane_idx = event and pr.TIMELINE_LANE_INDEX[event.lane]
        if lane_idx then
            local x = event.time * TIMELINE_PPS
            local y = -(TIMELINE_RULER_HEIGHT + (lane_idx - 1) * TIMELINE_LANE_HEIGHT
                + (TIMELINE_LANE_HEIGHT - TIMELINE_ICON_SIZE) / 2)
            local icon = get_timeline_icon(scroll_child)
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", x - TIMELINE_ICON_SIZE / 2, y)

            -- Melee with an active (non-twist) seal: split sword/seal icon.
            if event.lane == "melee" and event.seal_active and event.result ~= "twist" then
                icon.texture:Hide()
                icon.split_left:SetTexture(event.texture)
                local seal_spell = (event.seal_active == "blood")
                    and BLOOD_SPELL_ID or COMMAND_SPELL_ID
                local seal_tex = spell_texture(seal_spell)
                if seal_tex then
                    icon.split_right:SetTexture(seal_tex)
                end
                icon.split_left:Show()
                icon.split_right:Show()
            else
                if event.texture then
                    icon.texture:SetTexture(event.texture)
                end
                icon.texture:Show()
                icon.split_left:Hide()
                icon.split_right:Hide()
            end

            -- Grading mark for melee/judge swings (archive 2329-2344).
            if event.lane == "melee" or event.lane == "judge" then
                local verdict = analysis[i]
                icon.analysis_data = verdict
                if verdict and not verdict.skipped and not verdict.correct then
                    icon.error_border:Show()
                    icon.result_label:SetText("|cFFFF3333X|r")
                    icon.result_label:Show()
                else
                    icon.error_border:Hide()
                    icon.result_label:SetText("")
                    icon.result_label:Hide()
                end
            else
                icon.error_border:Hide()
                icon.analysis_data = nil
            end

            if event.lane == "melee" then
                local div = get_timeline_divider(scroll_child)
                div:SetSize(1, num_lanes * TIMELINE_LANE_HEIGHT)
                div:ClearAllPoints()
                div:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", x, -TIMELINE_RULER_HEIGHT)
            end
        end
    end

    if frame.scrollbar and frame.scroll_frame then
        local visible_width = frame.scroll_frame.GetWidth
            and frame.scroll_frame:GetWidth() or TIMELINE_WIDTH
        local max_scroll = math.max(total_width - visible_width, 0)
        frame.scrollbar:SetMinMaxValues(0, max_scroll)
        if ui.timeline_auto_scroll then
            frame.scrollbar:SetValue(max_scroll)
            if frame.scroll_frame.SetHorizontalScroll then
                frame.scroll_frame:SetHorizontalScroll(max_scroll)
            end
        end
    end
end

-- Builds the timeline frame hierarchy (archive create_timeline 2369-2510, trimmed).
function ui.build_timeline(self)
    if not ui.panel then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    local lanes = pr.TIMELINE_LANES or {}
    local num_lanes = #lanes
    local content_height = TIMELINE_RULER_HEIGHT + num_lanes * TIMELINE_LANE_HEIGHT
    local frame_height = content_height + 30

    local frame = CreateFrame("Frame", addon_name .. "PracticeTimeline", UIParent,
        "BackdropTemplate")
    ui.timeline_frame = frame
    frame:SetSize(TIMELINE_WIDTH + TIMELINE_LABEL_WIDTH + 16, frame_height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
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
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    frame:SetScript("OnDragStart", function(f)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
    end)

    local close_btn = CreateFrame("Button", nil, frame)
    close_btn:SetSize(16, 16)
    close_btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close_btn:SetScript("OnClick", function()
        ui.toggle_timeline(ST)
    end)

    local label_area = CreateFrame("Frame", nil, frame)
    label_area:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(4 + TIMELINE_RULER_HEIGHT))
    label_area:SetSize(TIMELINE_LABEL_WIDTH, num_lanes * TIMELINE_LANE_HEIGHT)
    for i, lane in ipairs(lanes) do
        local y = -((i - 1) * TIMELINE_LANE_HEIGHT)
        local lane_icon = label_area:CreateTexture(nil, "ARTWORK")
        lane_icon:SetSize(16, 16)
        lane_icon:SetPoint("LEFT", label_area, "TOPLEFT", 2, y - TIMELINE_LANE_HEIGHT / 2)
        lane_icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local spell_id = LANE_SPELL_IDS[lane.key]
        if spell_id then
            local tex = spell_texture(spell_id)
            if tex then
                lane_icon:SetTexture(tex)
            end
        elseif lane.key == "melee" then
            lane_icon:SetTexture(pr.MELEE_TEXTURE)
        end
        local lane_label = label_area:CreateFontString(nil, "OVERLAY")
        lane_label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        lane_label:SetPoint("LEFT", lane_icon, "RIGHT", 3, 0)
        lane_label:SetTextColor(0.8, 0.8, 0.8, 1)
        lane_label:SetText(lane.name)
    end

    local scroll_frame = CreateFrame("ScrollFrame", addon_name .. "PracticeTimelineSF", frame)
    scroll_frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + TIMELINE_LABEL_WIDTH, -4)
    scroll_frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 18)
    frame.scroll_frame = scroll_frame

    local scroll_child = CreateFrame("Frame", nil, scroll_frame)
    scroll_child:SetHeight(content_height)
    scroll_child:SetWidth(TIMELINE_WIDTH)
    if scroll_frame.SetScrollChild then
        scroll_frame:SetScrollChild(scroll_child)
    end
    frame.scroll_child = scroll_child

    frame.lane_bgs = {}
    for i = 1, num_lanes do
        local bg = scroll_child:CreateTexture(nil, "BACKGROUND")
        local shade = (i % 2 == 0) and 0.08 or 0.04
        bg:SetColorTexture(shade, shade, shade, 1)
        bg:SetHeight(TIMELINE_LANE_HEIGHT)
        bg:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", 0,
            -(TIMELINE_RULER_HEIGHT + (i - 1) * TIMELINE_LANE_HEIGHT))
        bg:SetWidth(TIMELINE_WIDTH)
        frame.lane_bgs[i] = bg
    end

    local scrollbar = CreateFrame("Slider", nil, frame, "BackdropTemplate")
    scrollbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6 + TIMELINE_LABEL_WIDTH, 4)
    scrollbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4)
    scrollbar:SetHeight(12)
    if scrollbar.SetMinMaxValues then
        scrollbar:SetMinMaxValues(0, 1)
    end
    if scrollbar.SetValue then
        scrollbar:SetValue(0)
    end
    if scrollbar.SetValueStep then
        scrollbar:SetValueStep(1)
    end
    if scrollbar.SetObeyStepOnDrag then
        scrollbar:SetObeyStepOnDrag(true)
    end
    if scrollbar.SetOrientation then
        scrollbar:SetOrientation("HORIZONTAL")
    end
    scrollbar:SetScript("OnValueChanged", function(_, value)
        if scroll_frame.SetHorizontalScroll then
            scroll_frame:SetHorizontalScroll(value)
        end
    end)
    frame.scrollbar = scrollbar

    if scroll_frame.EnableMouseWheel then
        scroll_frame:EnableMouseWheel(true)
    end
    scroll_frame:SetScript("OnMouseWheel", function(_, delta)
        local min_val, max_val = 0, 1
        if scrollbar.GetMinMaxValues then
            min_val, max_val = scrollbar:GetMinMaxValues()
        end
        local cur = (scrollbar.GetValue and scrollbar:GetValue()) or 0
        local step = TIMELINE_PPS * 2
        local new_val = math.max(min_val, math.min(max_val, cur - delta * step))
        if scrollbar.SetValue then
            scrollbar:SetValue(new_val)
        end
        if delta > 0 then
            ui.timeline_auto_scroll = false
        elseif new_val >= max_val then
            ui.timeline_auto_scroll = true
        end
    end)

    frame:Hide()
end

-- Toggles the timeline frame (archive toggle_timeline 2513-2537).
function ui.toggle_timeline()
    local frame = ui.timeline_frame
    if not frame then
        return
    end
    if ui.timeline_visible then
        frame:Hide()
        ui.timeline_visible = false
    else
        frame:Show()
        ui.timeline_visible = true
        ui.timeline_needs_render = true
    end
    ui.update_timeline_button()
end

-- Refreshes just the timeline toggle button (fight start reuses it).
function ui.update_timeline_button()
    local panel = ui.panel
    if not panel or not panel.timeline_btn then
        return
    end
    if ui.timeline_visible then
        panel.timeline_btn:SetBackdropColor(0.1, 0.3, 0.1, 0.9)
        panel.timeline_btn.label:SetText("|cFF00FF00Timeline|r")
    else
        panel.timeline_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        panel.timeline_btn.label:SetText("Timeline")
    end
end

--=========================================================================================
-- Proc icons: Bloodlust + DST (archive 2715-2802)
--=========================================================================================

-- One proc icon: border, texture, cooldown swipe (set-once latch), countdown text.
local function create_proc_icon(key, texture)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(48, 48)
    local x = (key == "dst") and -30 or 30
    frame:SetPoint("CENTER", UIParent, "CENTER", x, 150)
    frame:SetFrameStrata("HIGH")

    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border:SetColorTexture(0, 0, 0, 0.8)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture(texture)

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetDrawEdge(false)
    if frame.cooldown.SetHideCountdownNumbers then
        frame.cooldown:SetHideCountdownNumbers(true)
    end

    frame.countdown = frame:CreateFontString(nil, "OVERLAY")
    frame.countdown:SetPoint("BOTTOM", frame, "BOTTOM", 0, -14)
    frame.countdown:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    frame.countdown:SetTextColor(1, 1, 1, 1)
    frame.countdown:SetText("")

    frame.proc_swipe = {}
    frame:Hide()
    return frame
end

-- Builds both proc icons, dimmed until their buffs run (archive start 1018-1033).
function ui.build_proc_icons(self)
    if not ui.panel then
        return
    end
    local bl_tex = spell_texture(BLOODLUST_SPELL_ID) or BLOODLUST_FALLBACK
    local dst_tex = DST_FALLBACK
    if GetItemIcon then
        dst_tex = GetItemIcon(DST_ITEM_ID) or DST_FALLBACK
    end
    ui.proc_icons = {
        bl = create_proc_icon("bl", bl_tex),
        dst = create_proc_icon("dst", dst_tex),
    }
end

-- Drives the proc icons from the sim buffs (archive sim_update 3346-3384 halves):
-- full alpha + swipe + countdown while the buff runs, dimmed/desaturated else.
function ui.update_proc_icons(self)
    local icons = ui.proc_icons
    if not icons then
        return
    end
    local sim = ui.sim
    local now = api.get_time()
    local function update_one(frame, active, expires, full_duration)
        if not frame then
            return
        end
        local remaining = (active and expires > now) and (expires - now) or 0
        set_swipe(frame.proc_swipe, frame.cooldown, remaining, full_duration)
        if remaining > 0 then
            frame:SetAlpha(1)
            if frame.icon.SetDesaturated then
                frame.icon:SetDesaturated(false)
            end
            frame.countdown:SetText(string.format("%d", math.ceil(remaining)))
        else
            frame:SetAlpha(0.4)
            if frame.icon.SetDesaturated then
                frame.icon:SetDesaturated(true)
            end
            frame.countdown:SetText("")
        end
    end
    if sim then
        update_one(icons.bl, sim.has_bloodlust, sim.bl_buff_expires, 40)
        update_one(icons.dst, sim.has_dst, sim.dst_buff_expires, 10)
    else
        update_one(icons.bl, false, 0, 40)
        update_one(icons.dst, false, 0, 10)
    end
end

--=========================================================================================
-- Bar overlays (action-bar mirrors): mechanism ships, discovery is deferred
--=========================================================================================
-- The overlay object model (archive create_bar_overlay 3799-3901, minus the hotkey
-- mirror) is fully implemented below and driven every tick by update_overlays(),
-- with press flashes fired from cast_key(). What is NOT here: finding the parent
-- action-bar button automatically. That needs the archived discover_action_buttons
-- (BT4/Dominos/ElvUI/Blizzard _G scan) plus the manual linking click-catchers and
-- persisted mappings (new options), all deferred. Plug-in: call
--   st.practice_ui.attach_overlay(ST, ability_key, parent_frame)
-- once the parent is known (e.g. from a future linking pass); detach_overlay and
-- detach_all_overlays undo it. Until then overlays stay empty and cost nothing.
function ui.attach_overlay(self, ability_key, parent_frame)
    self = self or ST
    local pr = st.practice
    local ab = pr and pr.ABILITIES[ability_key]
    if not ab or not parent_frame then
        return
    end
    ui.detach_overlay(self, ability_key)
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local container = CreateFrame("Frame", nil, parent_frame)
    container:SetAllPoints()
    if parent_frame.GetFrameStrata and container.SetFrameStrata then
        container:SetFrameStrata(parent_frame:GetFrameStrata())
    end
    if parent_frame.GetFrameLevel and container.SetFrameLevel then
        container:SetFrameLevel(parent_frame:GetFrameLevel() + 5)
    end

    local icon_tex = container:CreateTexture(nil, "ARTWORK")
    icon_tex:SetAllPoints()
    local tex = ability_texture(ability_key)
    if tex then
        icon_tex:SetTexture(tex)
        icon_tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local cd = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(true)
    end

    local dim = container:CreateTexture(nil, "OVERLAY")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.5)
    dim:Hide()

    local gcd_cd = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
    gcd_cd:SetAllPoints()
    gcd_cd:SetDrawEdge(false)
    if gcd_cd.SetHideCountdownNumbers then
        gcd_cd:SetHideCountdownNumbers(true)
    end

    local flash = container:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints()
    flash:SetColorTexture(1, 1, 1, 0)
    flash:Hide()

    local cd_text_frame = CreateFrame("Frame", nil, container)
    cd_text_frame:SetAllPoints()
    local cd_text = cd_text_frame:CreateFontString(nil, "OVERLAY")
    cd_text:SetPoint("CENTER", container, "CENTER", 0, 0)
    cd_text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    cd_text:SetTextColor(1, 1, 1, 1)
    cd_text:Hide()

    ui.overlays = ui.overlays or {}
    ui.overlays[ability_key] = {
        container = container,
        cooldown = cd,
        cooldown_set = false,
        cooldown_state = {},
        gcd_dim = dim,
        gcd_cooldown = gcd_cd,
        gcd_state = {},
        flash = flash,
        flash_timer = 0,
        cd_text = cd_text,
    }
end

function ui.detach_overlay(self, ability_key)
    if not ui.overlays then
        return
    end
    local overlay = ui.overlays[ability_key]
    if not overlay then
        return
    end
    if overlay.container then
        overlay.container:Hide()
    end
    ui.overlays[ability_key] = nil
end

function ui.detach_all_overlays(self)
    if not ui.overlays then
        return
    end
    local keys = {}
    for key in pairs(ui.overlays) do
        keys[#keys + 1] = key
    end
    for _, key in ipairs(keys) do
        ui.detach_overlay(self, key)
    end
    ui.overlays = {}
end

-- Press flash (archive flash_bar_button 3973-3980).
function ui.flash_overlay(self, ability_key)
    if not ui.overlays then
        return
    end
    local overlay = ui.overlays[ability_key]
    if not overlay or not overlay.flash then
        return
    end
    if overlay.flash.SetVertexColor then
        overlay.flash:SetVertexColor(1, 1, 1, 0.6)
    end
    overlay.flash:Show()
    overlay.flash_timer = 0.15
end

-- Per-tick overlay drive (archive update_icon_states 3594-3647, set-once variant):
-- cooldown swipes latch like the panel icons, plus countdown text + flash fade.
function ui.update_overlays(self, now)
    if not ui.overlays then
        return
    end
    local sim = ui.sim
    if not sim then
        return
    end
    now = now or api.get_time()
    local pr = st.practice
    local gcd_remaining = 0
    if sim.gcd_active and sim.gcd_expires > now then
        gcd_remaining = sim.gcd_expires - now
    end
    for key, overlay in pairs(ui.overlays) do
        local ab = pr.ABILITIES[key]
        if ab and (ab.type == "ability" or ab.type == "buff" or ab.type == "haste_trinket") then
            local expires = sim[key .. "_cooldown_expires"] or 0
            local remaining = (expires > now) and (expires - now) or 0
            if not overlay.cooldown_set and remaining > 0 then
                overlay.cooldown:SetCooldown(expires - ab.cooldown, ab.cooldown)
                overlay.cooldown_set = true
            elseif overlay.cooldown_set and remaining <= 0 then
                overlay.cooldown:SetCooldown(0, 0)
                overlay.cooldown_set = false
            end
            if overlay.cd_text then
                if remaining > 0 then
                    overlay.cd_text:SetText(string.format("%d", math.ceil(remaining)))
                    overlay.cd_text:Show()
                else
                    overlay.cd_text:Hide()
                end
            end
        elseif overlay.cooldown then
            overlay.cooldown:SetCooldown(0, 0)
            overlay.cooldown_set = false
            if overlay.cd_text then
                overlay.cd_text:Hide()
            end
        end
        if overlay.gcd_dim then
            local gated = not (key == "judge" or ab.type == "buff"
                or ab.type == "haste_trinket" or ab.type == "stopattack")
            if gated then
                set_swipe(overlay.gcd_state, overlay.gcd_cooldown, gcd_remaining,
                    sim.effective_gcd)
                if gcd_remaining > 0 then
                    overlay.gcd_dim:Show()
                else
                    overlay.gcd_dim:Hide()
                end
            end
        end
        if overlay.flash_timer > 0 then
            overlay.flash_timer = overlay.flash_timer - 0.016
            if overlay.flash_timer <= 0 then
                overlay.flash_timer = 0
                overlay.flash:Hide()
                if overlay.flash.SetVertexColor then
                    overlay.flash:SetVertexColor(1, 1, 1, 0)
                end
            elseif overlay.flash.SetVertexColor then
                overlay.flash:SetVertexColor(1, 1, 1, 0.6 * (overlay.flash_timer / 0.15))
            end
        end
    end
end
--=========================================================================================
-- Session lifecycle
--=========================================================================================
function ui.is_active()
    -- True while a practice session runs (the paladin module's gates read this).
    return ui.active == true
end

function ui.toggle(self)
    self = self or ST
    if ui.active then
        ui.stop(self)
    else
        ui.start(self)
    end
end

function ui.start(self)
    self = self or ST
    if ui.active then
        return
    end
    local pr = st.practice
    if not pr or not ui.panel then
        self:Print("Practice mode is not available.")
        return
    end
    if self.in_combat or (InCombatLockdown and InCombatLockdown()) then
        self:Print("Practice mode cannot be started in combat.")
        return
    end

    local db = self:get_class_table()
    local sim = ui.sim
    local now = api.get_time()

    ui.base_speed = resolve_base_speed(db)
    -- Stash the live GCD values for stop() to restore (the client's lib repopulates
    -- them on the next real cast; expires is nil-ed like GCD_OVER does).
    ui.saved_gcd_duration = self.gcd.duration
    ui.saved_gcd_spell_length = self.gcd.spell_length
    ui.saved_hand_speed = self.mainhand.speed

    -- Fresh state, fresh speed, then the fight: apply_haste before begin_fight so a
    -- previous session's haste cannot leave a too-fast first swing in place, and again
    -- after it so the immediate Bloodlust (bl_delay 0) rescales the swing.
    pr.reset(sim)
    pr.apply_haste(sim, ui.base_speed, now)
    pr.begin_fight(sim, now, {})
    pr.apply_haste(sim, ui.base_speed, now)

    ui.active = true
    ui.combat_paused = false
    ui.last_compute = 0
    ui.result_remaining = 0
    -- Session-local keybinds (archived defaults; capture edits this table).
    ui.keybinds = {}
    for key, bind in pairs(pr.DEFAULT_KEYBINDS) do
        ui.keybinds[key] = bind
    end
    ui.dst_enabled = false
    -- Fresh session score; bests load from the addon's own class profile table
    -- (nil-safe on a fresh profile) and the score line repaints from empty.
    ui.score = pr.new_score()
    ui.load_bests(self)
    ui.last_score_text = nil
    -- Fresh timeline data; the opening band tracks the current rotation.
    ui.timeline_events = {}
    ui.timeline_event_count = 0
    ui.timeline_bands, ui.timeline_band_count =
        pr.bands_for_fight(pr.determine_rotation(sim))
    ui.timeline_auto_scroll = true
    ui.timeline_needs_render = true
    -- Force the seal-colour latch so the new session re-applies the bar colour even if
    -- it opens with the same seals the previous session ended on.
    ui.last_seal_sig = nil
    ui.last_rotation_line = nil
    ui.last_fight_text = nil
    ui.current_display_rotation = nil
    ui.build_bar_mappings(self)
    ui.update_result_font(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_score(self)
    ui.update_button(self)
    ui.update_hint(self)
    ui.update_haste_buttons(self)
    ui.update_keybind_labels(self)
    ui.rebind_keys(self)
    ui.update_rotation_display(self)
    ui.update_proc_icons(self)
    if ui.proc_icons then
        if ui.proc_icons.bl then
            ui.proc_icons.bl:Show()
        end
        if ui.proc_icons.dst then
            ui.proc_icons.dst:Show()
        end
    end
    if ui.timeline_frame then
        ui.timeline_frame:Show()
        ui.timeline_visible = true
        ui.render_timeline()
    end
    ui.apply_settings(self)
    ui.panel:Show()
    ui.driver:Show()
    ui.sync_to_addon(self)

    self:Print("Practice mode started. Type /st practice to stop.")
end

function ui.stop(self)
    self = self or ST
    if not ui.active then
        return
    end
    ui.active = false
    ui.combat_paused = false

    local pr = st.practice
    local sim = ui.sim
    if pr and sim then
        if sim.fight_active then
            pr.end_fight(sim)
        end
        pr.reset(sim)
    end
    -- A session can end mid-fight, so bests save here as well as at fight end.
    ui.maybe_save_bests(self)

    ui.cancel_key_capture(self)
    if ClearOverrideBindings and ui.panel and not (InCombatLockdown and InCombatLockdown()) then
        ClearOverrideBindings(ui.panel)
    end
    ui.detach_all_overlays(self)

    ui.result_remaining = 0
    if ui.result_frame then
        ui.result_frame:SetAlpha(0)
    end
    if ui.panel then
        ui.panel:Hide()
    end
    if ui.driver then
        ui.driver:Hide()
    end
    if ui.rotation_display then
        ui.rotation_display:Hide()
    end
    ui.current_display_rotation = nil
    if ui.timeline_frame then
        ui.timeline_frame:Hide()
    end
    ui.timeline_visible = false
    ui.timeline_needs_render = false
    ui.timeline_events = {}
    ui.timeline_event_count = 0
    ui.timeline_bands = {}
    ui.timeline_band_count = 0
    if ui.proc_icons then
        if ui.proc_icons.bl then
            ui.proc_icons.bl:Hide()
        end
        if ui.proc_icons.dst then
            ui.proc_icons.dst:Hide()
        end
    end
    ui.clear_addon_state(self)

    self:Print("Practice mode stopped.")
end

-- Start/Stop Fight: toggle a fight inside an already running session (the archive split
-- start()/start_fight(); phase 2 starts the first fight with the session).
function ui.toggle_fight(self)
    self = self or ST
    if not ui.active then
        return
    end
    if ui.sim.fight_active then
        ui.stop_fight(self)
    else
        ui.start_fight(self)
    end
end

function ui.start_fight(self)
    self = self or ST
    if not ui.active or (ui.sim and ui.sim.fight_active) then
        return
    end
    if self.in_combat or (InCombatLockdown and InCombatLockdown()) then
        self:Print("Practice fights cannot be started in combat.")
        return
    end
    local pr = st.practice
    local sim = ui.sim
    local now = api.get_time()
    pr.apply_haste(sim, ui.base_speed, now)
    pr.begin_fight(sim, now, {})
    pr.apply_haste(sim, ui.base_speed, now)
    -- Fresh timeline data with the opening band; the timeline shows on every fight
    -- (the archive's "always" default; there is no mode option in this lane).
    ui.timeline_events = {}
    ui.timeline_event_count = 0
    ui.timeline_bands, ui.timeline_band_count =
        pr.bands_for_fight(pr.determine_rotation(sim))
    ui.timeline_auto_scroll = true
    ui.timeline_needs_render = true
    ui.last_fight_text = nil
    if ui.timeline_frame then
        ui.timeline_frame:Show()
        ui.timeline_visible = true
        ui.update_timeline_button()
        ui.render_timeline()
    end
    ui.update_button(self)
    ui.update_hint(self)
    ui.update_haste_buttons(self)
    ui.update_score(self)
    ui.sync_to_addon(self)
end

function ui.stop_fight(self)
    self = self or ST
    local pr = st.practice
    local sim = ui.sim
    if not pr or not sim or not sim.fight_active then
        return
    end
    pr.end_fight(sim)
    pr.apply_haste(sim, ui.base_speed, api.get_time())
    ui.result_remaining = 0
    if ui.result_frame then
        ui.result_frame:SetAlpha(0)
    end
    -- Final render for post-fight review; the data and the frame stay up.
    ui.timeline_needs_render = true
    if ui.timeline_visible then
        ui.render_timeline()
    end
    if ui.panel and ui.panel.fight_timer_text then
        ui.panel.fight_timer_text:SetText("")
    end
    ui.last_fight_text = nil
    ui.update_button(self)
    ui.update_hint(self)
    -- The fight's attempts are final: persist personal bests and repaint the line.
    ui.maybe_save_bests(self)
    ui.update_score(self)
    ui.sync_to_addon(self)
end

--=========================================================================================
-- Driver: per-frame simulation tick
--=========================================================================================
function ui.tick(self, elapsed)
    if not ui.active then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end

    -- The result popup fades on every frame for a smooth step between compute ticks.
    ui.update_result_fade(elapsed)

    local now = api.get_time()
    if now - (ui.last_compute or 0) < UPDATE_INTERVAL then
        return
    end
    ui.last_compute = now

    if ui.pending_apply and not (InCombatLockdown and InCombatLockdown()) then
        ui.apply_settings(self)
    end

    -- Real combat pauses the simulation entirely: no casts, no swing progression, no
    -- grading (the archive only paused grading; phase 2 freezes the whole sim so a real
    -- fight cannot be double-counted or raced).
    if self.in_combat then
        if not ui.combat_paused then
            ui.combat_paused = true
            ui.combat_pause_start = now
            ui.update_hint(self)
        end
        ui.sync_to_addon(self)
        ui.update_button(self)
        return
    end
    if ui.combat_paused then
        ui.combat_paused = false
        ui.shift_sim_times(ui.sim, now - (ui.combat_pause_start or now))
        ui.update_hint(self)
    end

    local sim = ui.sim
    local out = ui.out
    pr.tick(sim, now, elapsed, out)
    if out.buffs_changed or out.bl_fired or out.buff_changed then
        -- A haste source started or expired (the tick's own buffs_changed / bl_fired,
        -- or buff_changed merged from a queue-fired cast): re-derive speed and GCD.
        pr.apply_haste(sim, ui.base_speed, now)
    end
    if out.swing_ready then
        -- A swing landed: restart the next swing (the engine's contract keeps the
        -- restart with the caller), then grade the landing. A real-combat pause skips
        -- this whole tick, which is how grading is suspended there.
        pr.start_swing(sim, now)
        local grade = ui.grade_out
        pr.on_swing(sim, now, grade)
        if grade.feedback then
            ui.show_result(self, grade.feedback)
        end
        -- Scoring: a graded attempt (grade is nil for swings with no attempt) feeds
        -- the running session score and repaints the panel score line.
        if grade.grade and ui.score then
            pr.record_attempt(ui.score, grade.grade, grade.lead_ms)
            ui.update_score(self)
        end
        -- Timeline: mirror the swing event with its fight-relative time.
        ui.timeline_event_count = pr.push_timeline_event(ui.timeline_events,
            ui.timeline_event_count, sim, now, "melee", pr.MELEE_TEXTURE,
            grade.result, grade.timeline_event and grade.timeline_event.seal)
        ui.timeline_needs_render = true
        -- DST proc roll (archive sim_on_swing 3515-3525): session toggle + unlocked.
        if ui.dst_enabled and not sim.locked_rotation then
            local roll = (ui.random or math.random)()
            if pr.maybe_dst_proc(sim, now, roll) then
                pr.apply_haste(sim, ui.base_speed, now)
            end
        end
    end
    if sim.fight_active then
        -- Fight clock, rotation bands, rotation display.
        ui.update_fight_timer(self, now)
        local rotation = pr.determine_rotation(sim)
        if rotation then
            local before = ui.timeline_band_count
            ui.timeline_band_count = pr.track_rotation_band(ui.timeline_bands,
                ui.timeline_band_count, rotation, now - sim.fight_start_time)
            if ui.timeline_band_count ~= before then
                ui.timeline_needs_render = true
            end
        end
        ui.update_rotation_display(self, rotation)
    end
    if ui.timeline_needs_render and ui.timeline_visible then
        ui.render_timeline()
    end
    -- The tick's merged cast flags (queue_ready from a queued ability, seal_faded,
    -- cooldown_set, ...) all land in the same mirror + icon refresh below.
    ui.sync_to_addon(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_button(self)
    ui.update_haste_buttons(self)
    ui.update_proc_icons(self)
    ui.update_overlays(self, now)
end

--=========================================================================================
-- Bridge: mirror the simulation onto the addon's live state
--=========================================================================================
function ui.sync_to_addon(self)
    self = self or ST
    local sim = ui.sim
    if not sim then
        return
    end
    local now = api.get_time()

    -- Swing mirror (main.lua's bars read these fields and compare to GetTime()).
    local d = self.mainhand
    d.speed = sim.effective_speed
    if sim.swing_active then
        d.start = sim.swing_ends_at - sim.effective_speed
        d.ends_at = sim.swing_ends_at
        d.is_paused = false
    else
        -- No swing in flight (attack hold, or a fight that has not started): hold an
        -- empty bar instead of animating a swing that is not happening.
        d.start = now
        d.ends_at = now + sim.effective_speed
        d.current_progress = 0
        d.is_paused = true
    end
    d.is_full = false
    if sim.attack_paused or sim.attack_pause_pending or ui.combat_paused then
        d.is_paused = true
    end

    -- GCD mirror. duration/expires feed the bar's GCD underlay and markers;
    -- spell_length feeds the guide's G input through main.lua's
    -- get_spell_gcd_duration / set_gcd_times_before_swing_seconds.
    local g = self.gcd
    local gcd_changed = (g.duration ~= sim.effective_gcd) or (g.spell_length ~= sim.effective_gcd)
    g.duration = sim.effective_gcd
    g.spell_length = sim.effective_gcd
    g.expires = (sim.gcd_active and math.max(sim.gcd_expires, now)) or nil
    if gcd_changed then
        if g.phys_length then
            self:set_gcd_times_before_swing_seconds()
        end
        self:on_gcd_length_change()
    end

    -- Seal mirror: the twist visuals, bar colours and the guide read the sim state.
    -- The bar's seal colour is re-applied whenever the mirrored seal set changes (the
    -- archive did the same through update_bar_on_aura_change in start_fight/sim_cast);
    -- without it the simulation's seal swaps would be invisible on the bar itself.
    local seal_sig = (sim.seal_1_label or "-") .. "/" .. (sim.seal_2_label or "-")
    self.PALADIN.practice_sync(self)
    if seal_sig ~= ui.last_seal_sig then
        ui.last_seal_sig = seal_sig
        self:set_bar_color("mainhand")
    end
    -- Practice owns the mainhand bar while the session runs (main.lua's hide_bar guard
    -- covers the range-finder loop, which re-runs bar visibility every 0.05 s).
    self:show_bar("mainhand")
end

-- Shifts every still-future simulation deadline by `shift` seconds - the real-combat
-- pause of the sim. Deadlines that already passed before the pause stay expired, so an
-- expiring buff cannot be kept alive by combat.
function ui.shift_sim_times(sim, shift)
    if not sim or not shift or shift <= 0 then
        return
    end
    local now = api.get_time()
    for i = 1, #SHIFTED_SIM_TIMES do
        local field = SHIFTED_SIM_TIMES[i]
        local value = sim[field]
        if type(value) == "number" and value > now then
            sim[field] = value + shift
        end
    end
end

-- Restores the addon's live state after the session ends: the swing bar goes to its
-- idle (full) look, the real GCD values come back, and the real auras take over.
function ui.clear_addon_state(self)
    local now = api.get_time()
    local d = self.mainhand
    d.speed = ui.saved_hand_speed or d.speed
    local speed = d.speed or 3.5
    -- The idle look of a timer whose swing just ended (progress clamps to 1).
    d.start = now - speed
    d.ends_at = now
    d.current_progress = 1
    d.is_full = true
    d.is_paused = false
    self:on_bar_inactive("mainhand")

    local g = self.gcd
    g.duration = ui.saved_gcd_duration
    g.spell_length = ui.saved_gcd_spell_length
    g.expires = nil
    if g.phys_length then
        self:set_gcd_times_before_swing_seconds()
    end
    self:on_gcd_length_change()

    -- Real auras take over again (also restores the bar's seal colour).
    self.PALADIN.on_aura_change(self)
    self:handle_bar_visibility("mainhand")
end

--=========================================================================================
-- Simulated casts
--=========================================================================================
function ui.cast_key(self, key)
    self = self or ST
    if not ui.active then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    if self.in_combat then
        -- The grid is silent while the real-combat pause freezes the simulation.
        return
    end

    local sim = ui.sim
    local now = api.get_time()
    local out = ui.cast_out
    pr.cast(sim, key, now, out)
    if out.buff_changed then
        -- Haste pot / Abacus change the effective speed and GCD.
        pr.apply_haste(sim, ui.base_speed, now)
    end
    -- Timeline: seals log on their seal lane, cs/judge/consec on their own lane
    -- (archive sim_cast_seal 3087-3093 + sim_cast_ability 3165-3168).
    local lane = pr.cast_timeline_lane(key)
    if lane and sim.fight_active then
        local ab = pr.ABILITIES[key]
        local seal_active = nil
        if ab.type == "seal" then
            seal_active = ab.seal_label
        elseif key == "judge" then
            seal_active = out.judged_seal
        end
        ui.timeline_event_count = pr.push_timeline_event(ui.timeline_events,
            ui.timeline_event_count, sim, now, lane, ability_texture(key), nil,
            seal_active)
        ui.timeline_needs_render = true
    end
    ui.flash_overlay(self, key)
    -- The out flags nest inside the bridge: gcd_started -> the GCD mirror,
    -- seal_changed/twist_armed -> practice_sync, buff_changed/cooldown_set -> the icon
    -- swipes; sync + refresh handle every branch and are cheap.
    ui.sync_to_addon(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_button(self)
    if out.buff_changed then
        ui.update_haste_buttons(self)
        ui.update_proc_icons(self)
    end
    ui.update_overlays(self, now)
end

--=========================================================================================
-- Icon states (set-once swipes, per nextaction_ui.lua)
--=========================================================================================
function ui.refresh_icons(self)
    local sim = ui.sim
    if not sim then
        return
    end
    local now = api.get_time()
    local gcd_remaining = 0
    if sim.gcd_active and sim.gcd_expires > now then
        gcd_remaining = sim.gcd_expires - now
    end
    for _, icon in pairs(ui.bar_mappings) do
        if icon.cooldown_field then
            local expires = sim[icon.cooldown_field] or 0
            local remaining = (expires > now) and (expires - now) or 0
            set_swipe(icon.ability_swipe, icon.cooldown, remaining, icon.cooldown_full)
        end
        if icon.gcd_gated then
            set_swipe(icon.gcd_swipe, icon.gcd_cooldown, gcd_remaining, sim.effective_gcd)
            if gcd_remaining > 0 then
                icon.gcd_dim:Show()
            else
                icon.gcd_dim:Hide()
            end
        end
        -- Buff / active-seal border highlights (archive update_icon_states 3564-3592).
        if icon.border and icon.border.SetColorTexture and icon.key then
            local key = icon.key
            local border = BORDER_IDLE
            if key == "aw" and sim.aw_buff_expires > now then
                border = BORDER_AW
            elseif key == "hpot" and sim.has_haste_pot then
                border = BORDER_HPOT
            elseif key == "abacus" and sim.has_abacus then
                border = BORDER_ABACUS
            else
                local pr = st.practice
                local ab = pr and pr.ABILITIES[key]
                if ab and ab.type == "seal" and sim.active_seals[ab.seal_label] then
                    border = BORDER_SEAL
                end
            end
            icon.border:SetColorTexture(border[1], border[2], border[3], border[4])
        end
    end
end

--=========================================================================================
-- Panel display updates
--=========================================================================================
function ui.update_info(self)
    local panel = ui.panel
    if not panel or not panel.info_text then
        return
    end
    local sim = ui.sim
    if not sim then
        return
    end
    local text = string.format("Speed: %.1fs  GCD: %.2fs", sim.effective_speed or 0,
        sim.effective_gcd or 0)
    if text ~= ui.last_info_text then
        ui.last_info_text = text
        panel.info_text:SetText(text)
    end
    -- Rotation line (archive update_info_display 3684-3686, via st.nextaction names).
    if panel.rotation_text then
        local pr = st.practice
        local rotation = pr and pr.determine_rotation(sim)
        local na = st.nextaction
        local name = rotation
            and ((na and na.display_names and na.display_names[rotation]) or rotation)
            or "--"
        local line = "Rotation: " .. name
        if line ~= ui.last_rotation_line then
            ui.last_rotation_line = line
            panel.rotation_text:SetText(line)
        end
    end
end

-- Fight clock line (archive sim_update 3387-3394, text half).
function ui.update_fight_timer(self, now)
    local panel = ui.panel
    if not panel or not panel.fight_timer_text then
        return
    end
    local sim = ui.sim
    local pr = st.practice
    local text = ""
    if sim and sim.fight_active and pr then
        now = now or api.get_time()
        text = pr.format_fight_time(now - sim.fight_start_time)
    end
    if text ~= ui.last_fight_text then
        ui.last_fight_text = text
        panel.fight_timer_text:SetText(text)
    end
end

function ui.update_button(self)
    local panel = ui.panel
    if not panel or not panel.fight_btn then
        return
    end
    local active = ui.sim and ui.sim.fight_active
    if active == ui.last_button_active then
        return
    end
    ui.last_button_active = active
    if active then
        panel.fight_btn.label:SetText("|cFFFF0000Stop Fight|r")
        panel.fight_btn:SetBackdropColor(0.4, 0.1, 0.1, 0.9)
    else
        panel.fight_btn.label:SetText("Start Fight")
        panel.fight_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    end
end

function ui.update_hint(self)
    local panel = ui.panel
    if not panel or not panel.hint_text then
        return
    end
    local text
    if ui.combat_paused then
        text = HINT_PAUSED
    elseif ui.sim and not ui.sim.fight_active then
        text = HINT_STOPPED
    else
        text = HINT_ACTIVE
    end
    if text ~= ui.last_hint_text then
        ui.last_hint_text = text
        panel.hint_text:SetText(text)
    end
end

--=========================================================================================
-- Result popup ("TWIST!" / "MISS")
--=========================================================================================
function ui.show_result(self, feedback)
    local result = ui.result_frame
    if not result then
        return
    end
    local db = self:get_class_table()
    local color
    if feedback == "TWIST!" then
        color = db.practice_result_color_hit or RESULT_COLOR_HIT
    else
        color = db.practice_result_color_miss or RESULT_COLOR_MISS
    end
    result.text:SetText(feedback)
    result.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    ui.result_duration = db.practice_result_duration or 0.8
    ui.result_remaining = ui.result_duration
    result:SetAlpha(1)
end

-- Archive fade (sim_update 3290-3301): full alpha until the last 0.3 s of the timer,
-- then a linear fade over that window.
function ui.update_result_fade(elapsed)
    if not ui.result_remaining or ui.result_remaining <= 0 then
        return
    end
    ui.result_remaining = ui.result_remaining - (elapsed or 0)
    local result = ui.result_frame
    if not result then
        return
    end
    if ui.result_remaining <= 0 then
        ui.result_remaining = 0
        result:SetAlpha(0)
    elseif ui.result_remaining < RESULT_FADE_SECONDS then
        result:SetAlpha(ui.result_remaining / RESULT_FADE_SECONDS)
    else
        result:SetAlpha(1)
    end
end

function ui.update_result_font(self)
    local result = ui.result_frame
    if not result then
        return
    end
    local db = self:get_class_table()
    local hand_db = self:get_hand_table("mainhand")
    local font_path = LSM:Fetch("font", hand_db.text_font or "Expressway")
        or RESULT_FALLBACK_FONT
    result.text:SetFont(font_path, db.practice_result_text_size or 28, "OUTLINE")
end

--=========================================================================================
-- Practice scoring: running session score + persistent personal bests
--=========================================================================================
-- Bests live in the addon's own class profile table (db.practice_bests, next to the
-- other practice_* keys this module already reads): AceDB persists the profile table
-- to SavedVariables, so no new options and no defaults entries are needed. Reads are
-- nil-safe (a fresh profile has no bests yet); writes never touch tables outside the
-- addon's own db. Practice stays paladin-only: the score accumulates twist attempts,
-- and only the paladin twist sim produces those.
function ui.load_bests(self)
    self = self or ST
    ui.bests = nil
    if not self.get_class_table then
        return
    end
    local db = self:get_class_table()
    local saved = db and db.practice_bests
    if type(saved) ~= "table" then
        return
    end
    ui.bests = {
        score = (type(saved.score) == "number") and saved.score or 0,
        hit_rate = (type(saved.hit_rate) == "number") and saved.hit_rate or 0,
        mean_error_ms = (type(saved.mean_error_ms) == "number")
            and saved.mean_error_ms or nil,
        grade = (type(saved.grade) == "string") and saved.grade or nil,
        attempts = (type(saved.attempts) == "number") and saved.attempts or 0,
    }
end

-- Persists personal bests when the session improved them: a higher session score
-- wins outright, an equal score with a tighter mean error wins the tiebreak, and the
-- best single-attempt grade rides along (rank-ordered, never downgrades). Fights with
-- no attempts save nothing. Only the addon's own class table is written.
function ui.maybe_save_bests(self)
    self = self or ST
    local pr = st.practice
    if not pr or not ui.score or not self.get_class_table then
        return
    end
    local summary = pr.score_summary(ui.score)
    if (summary.attempts or 0) == 0 then
        return
    end
    local db = self:get_class_table()
    if type(db) ~= "table" then
        return
    end
    local best = ui.bests
    local improved_score = false
    if not best then
        improved_score = true
    elseif summary.score > (best.score or 0) then
        improved_score = true
    elseif summary.score == (best.score or 0)
        and summary.mean_error_ms and best.mean_error_ms
        and summary.mean_error_ms < best.mean_error_ms then
        improved_score = true
    end
    local rank = pr.GRADE_RANK or {}
    local grade = best and best.grade or nil
    if summary.best_grade
        and (not grade or (rank[summary.best_grade] or 0) > (rank[grade] or 0)) then
        grade = summary.best_grade
    end
    local improved_grade = grade ~= (best and best.grade)
    if not improved_score and not improved_grade then
        return
    end
    local next_best = {
        score = improved_score and summary.score or (best and best.score or 0),
        hit_rate = improved_score and summary.hit_rate or (best and best.hit_rate or 0),
        mean_error_ms = improved_score and summary.mean_error_ms
            or (best and best.mean_error_ms),
        attempts = improved_score and summary.attempts or (best and best.attempts or 0),
        grade = grade,
    }
    ui.bests = next_best
    db.practice_bests = {
        score = next_best.score,
        hit_rate = next_best.hit_rate,
        mean_error_ms = next_best.mean_error_ms,
        attempts = next_best.attempts,
        grade = next_best.grade,
    }
end

-- "Best: 91 (S)" for the score line; "--" when no best is stored yet.
function ui.best_score_text()
    local best = ui.bests
    if not best or type(best.score) ~= "number" then
        return "--"
    end
    if best.grade then
        return string.format("%d (%s)", best.score, best.grade)
    end
    return tostring(best.score)
end

-- Repaints the panel score line: running score, hits/attempts, mean timing error,
-- last grade and the persistent best. Reuses the panel frame; no new frames.
function ui.update_score(self)
    local panel = ui.panel
    if not panel or not panel.score_text then
        return
    end
    local pr = st.practice
    local text
    if pr and ui.score and (ui.score.attempts or 0) > 0 then
        local summary = pr.score_summary(ui.score)
        local err = (summary.mean_error_ms ~= nil)
            and string.format("%dms", math.floor(summary.mean_error_ms + 0.5)) or "--"
        text = string.format("Score %d %d/%d %s %s Best %s",
            summary.score, summary.hits, summary.attempts, err,
            summary.last_grade or "-", ui.best_score_text())
    else
        local best = ui.best_score_text()
        text = (best ~= "--") and ("Score -- Best " .. best) or "Score --"
    end
    if text ~= ui.last_score_text then
        ui.last_score_text = text
        panel.score_text:SetText(text)
    end
end

--=========================================================================================
-- Panel position
--=========================================================================================
-- Re-anchors the panel (and the result popup) from the saved offsets; the offsets are
-- added to the archive's 8 px default gap so the defaults (0, 0) reproduce the archive
-- layout exactly. Never runs during combat lockdown: a deferred apply waits for the
-- driver tick.
function ui.apply_settings(self)
    self = self or ST
    local panel = ui.panel
    if not panel then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        ui.pending_apply = true
        return
    end
    ui.pending_apply = false
    local db = self:get_class_table()
    anchor_to_mainhand_bar(self, panel, "TOPLEFT", "TOPRIGHT",
        (db.practice_panel_x or 0) + PANEL_ANCHOR_GAP, db.practice_panel_y or 0)
    if ui.result_frame then
        anchor_to_mainhand_bar(self, ui.result_frame, "BOTTOM", "TOP", 0, 8)
    end
end

-- Stores the dragged position as offsets from the bar's top-right corner (the panel is
-- a UIParent child with scale 1 and the bar defaults to scale 1; a rescaled bar only
-- affects where a stored offset lands, never the frame maths).
function ui.save_position(self)
    local panel = ui.panel
    local bar = self:get_bar_frame("mainhand")
    if not panel or not bar then
        return
    end
    local left, top = panel:GetLeft(), panel:GetTop()
    local bar_right, bar_top = bar:GetRight(), bar:GetTop()
    if not (left and top and bar_right and bar_top) then
        return
    end
    local db = self:get_class_table()
    db.practice_panel_x = math.floor(left - bar_right - PANEL_ANCHOR_GAP + 0.5)
    db.practice_panel_y = math.floor(top - bar_top + 0.5)
    ui.apply_settings(self)
end

if st.debug then st.utils.print_msg('-- Parsed practice_ui.lua module correctly') end
