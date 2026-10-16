--=========================================================================================
-- Twist Practice: the playable UI for the pure st.practice simulation engine (port phase 2).
--
-- Ported from the archived build's practice UI (docs/swedge/SwedgeTimer_Forever/practice.lua):
--   * control panel        558-914    (minus keybind capture/mapping, haste toggles, the
--                                      rotation selector, the timeline toggle and the fight
--                                      timer text - those arrive in later phases)
--   * result popup         524-541    + fade 3284-3301 + show_result 3655-3665
--   * result font update   3667-3672
--   * session start/stop   927-1165   (minus the archived hooks into bar/player functions;
--                                      this port mirrors the simulation onto the addon's own
--                                      bar state instead - see sync_to_addon)
--   * start_fight          2807-2889  (reduced to the engine's fight lifecycle)
--   * icon state updates   3535-3610  (cooldown swipes kept on the addon's set-once
--                                      pattern per nextaction_ui.lua)
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
--   * "Bar mappings" in phase 2 are the panel icon bar: ability key -> icon frame
--     (build_bar_mappings). The archive's action-bar overlay/keybind mapping subsystem
--     (auto_detect_keybinds 3692+, bar_overlays, keybinds) and its persistence arrive in
--     phase 3 and will extend the same key set.
--   * The archive's calculate_spell_GCD_duration hook is emulated only through
--     gcd.spell_length here; the guide's cooldown inputs still come from the live
--     spell cooldowns until the phase-4 haste/rotation/guide integration.
--   * The DST proc (practice.maybe_dst_proc) is not rolled yet: it needs its enable
--     setting and the rotation lock, both phase 4.
--   * out.timeline_event is deliberately not collected (phase 6 timeline/analyze).
--   * practice_weapon_speed is read at session/fight start; changing it mid-session
--     takes effect at the next start_fight.
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
local function anchor_to_mainhand_bar(frame, point, bar_point, x, y)
    frame:ClearAllPoints()
    local bar = ST:get_bar_frame("mainhand")
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
-- keybind label and right-click linking): icon texture, border, ability-cooldown swipe,
-- GCD swipe + GCD dim overlays, left-click cast.
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

    icon:EnableMouse(true)
    icon:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
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
        -- Frames are only ever created out of combat (post_init runs at load time); if
        -- a client somehow reports lockdown here, fail quiet and let start() say so.
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
    ui.build_result_frame(self)
    ui.build_panel(self)
    ui.apply_settings(self)
end

function ui.build_result_frame(self)
    local result = CreateFrame("Frame", addon_name .. "PracticeResultFrame", UIParent)
    ui.result_frame = result
    result:SetSize(RESULT_WIDTH, RESULT_HEIGHT)
    anchor_to_mainhand_bar(result, "BOTTOM", "TOP", 0, 8)
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
    anchor_to_mainhand_bar(panel, "TOPLEFT", "TOPRIGHT", PANEL_ANCHOR_GAP, 0)
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
    -- Force the seal-colour latch so the new session re-applies the bar colour even if
    -- it opens with the same seals the previous session ended on.
    ui.last_seal_sig = nil
    ui.build_bar_mappings(self)
    ui.update_result_font(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_button(self)
    ui.update_hint(self)
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
    ui.update_button(self)
    ui.update_hint(self)
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
    ui.update_button(self)
    ui.update_hint(self)
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
    end
    -- The tick's merged cast flags (queue_ready from a queued ability, seal_faded,
    -- cooldown_set, ...) all land in the same mirror + icon refresh below.
    ui.sync_to_addon(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_button(self)
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
    -- The out flags nest inside the bridge: gcd_started -> the GCD mirror,
    -- seal_changed/twist_armed -> practice_sync, buff_changed/cooldown_set -> the icon
    -- swipes; sync + refresh handle every branch and are cheap.
    ui.sync_to_addon(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_button(self)
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
    anchor_to_mainhand_bar(panel, "TOPLEFT", "TOPRIGHT",
        (db.practice_panel_x or 0) + PANEL_ANCHOR_GAP, db.practice_panel_y or 0)
    if ui.result_frame then
        anchor_to_mainhand_bar(ui.result_frame, "BOTTOM", "TOP", 0, 8)
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
