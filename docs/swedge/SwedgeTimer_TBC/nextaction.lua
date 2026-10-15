-- nextaction.lua ======================================================================
-- Next Action Guide: a port of the "Ret Next Action Guide" WeakAura by Fonsas &
-- Surveillant (wago.io/vlUi-HXuB). Recommends the next action in real time — cast
-- Seal of Command, cast Seal of Blood, twist now, or Crusader Strike — with HOLD,
-- Judgement, and filler (Consecration/Exorcism) cues.
--
-- Unlike the WeakAura, which inferred state from the combat log, this module reads
-- SwedgeTimer's own tracked state (st.player swing timer / seals / GCD). Practice
-- mode injects simulated state into those same st.player fields, so the engine works
-- during practice automatically; only ability cooldowns need a practice branch
-- (st.practice.sim.*_cooldown_expires instead of GetSpellCooldown).
--=======================================================================================
local addon_name, st = ...
local print = st.utils.print_msg
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")

st.nextaction = {}

-- Engine output, read by the display code
st.nextaction.action = "sob"            -- "soc" | "sob" | "twist" | "cs"
st.nextaction.hold = false              -- true = don't press anything yet
st.nextaction.judge_call = false        -- true = judge the active Seal of Blood first
st.nextaction.filler_kind = nil         -- "consecration" | "exorcism" | nil
st.nextaction.rotation_key = nil        -- e.g. "2/3", keys from st.rotation.sequences
st.nextaction.riding = false            -- true = ride the active Seal of Blood (blood auto)
st.nextaction.idle = true               -- engine not actively guiding (out of combat / no fight)

-- Engine internals
st.nextaction.melee_count = 0           -- landed swings while the engine is active
st.nextaction.waiting_judgement = false
st.nextaction.update_counter = 0
st.nextaction.update_interval = 0.05    -- engine tick, matches the aura poll cadence
st.nextaction.cs_expires = 0            -- latched end of the last real CS cooldown seen

local CS_SPELL_ID = 35395
local JUDGEMENT_SPELL_ID = 20271
local SOC_TEXTURE_ID = 20375
local SOB_TEXTURE_ID = 31892
local CONSECRATION_SPELL_ID = 26573
local EXORCISM_SPELL_ID = 879
local CS_COOLDOWN = 6
local JUDGEMENT_COOLDOWN = 8

-- Localized spell names for name-based cooldown lookups (GetSpellCooldown by id
-- can't distinguish ranks; by name it works for whatever rank is known)
local CONSECRATION_NAME = GetSpellInfo(CONSECRATION_SPELL_ID)
local EXORCISM_NAME = GetSpellInfo(EXORCISM_SPELL_ID)

-- UnitCreatureType returns localized strings; these are the Undead/Demon names in
-- all TBC client locales (unknown locales fall back to the Consecration suggestion)
local EXORCISM_TARGET_TYPES = {
    ["Undead"] = true, ["Demon"] = true,
    ["Untoter"] = true, ["Dämon"] = true,
    ["Mort-vivant"] = true, ["Démon"] = true,
    ["No-muerto"] = true, ["Demonio"] = true,
    ["Morto-vivo"] = true, ["Demônio"] = true,
    ["Нежить"] = true, ["Демон"] = true,
    ["언데드"] = true, ["악마"] = true,
    ["亡灵"] = true, ["恶魔"] = true,
    ["不死族"] = true, ["惡魔"] = true,
}
st.nextaction.exorcism_target_types = EXORCISM_TARGET_TYPES   -- shared with the cooldown HUD

--=========================================================================================
-- State readers (practice-aware)
--=========================================================================================

-- Live spell cooldowns via GetSpellCooldown, handling the GCD echo: the API reports
-- whichever cooldown ends later, so a real ability cooldown shows its full duration
-- (6s/8s/15s) while a spell whose cooldown ends before the running GCD reports the
-- GCD's ~1.5s duration instead. When latch_key is given, the last real cooldown's
-- end time is remembered on st.nextaction[latch_key] so the true remaining time can
-- still be derived during the echo window.
local function get_live_cooldown_remaining(spell, latch_key)
    local now = GetTime()
    local start_time, duration = GetSpellCooldown(spell)
    if not start_time or not duration or duration == 0 then
        return 0
    end
    if duration > 1.51 then
        if latch_key then
            st.nextaction[latch_key] = start_time + duration
        end
        local remaining = start_time + duration - now
        if remaining < 0 then remaining = 0 end
        return remaining
    end
    -- GCD echo: the real cooldown (if any) ends before this GCD does
    if not latch_key then
        return 0
    end
    local remaining = (st.nextaction[latch_key] or 0) - now
    if remaining <= 0 then
        return 0
    end
    local echo_end = start_time + duration - now
    if remaining > echo_end then
        remaining = echo_end
    end
    return remaining
end

local function get_sim_cooldown_remaining(expires)
    local remaining = (expires or 0) - GetTime()
    if remaining < 0 then remaining = 0 end
    return remaining
end

st.nextaction.get_cs_remaining = function()
    if st.practice and st.practice.active then
        return get_sim_cooldown_remaining(st.practice.sim.cs_cooldown_expires)
    end
    if IsSpellKnown and not IsSpellKnown(CS_SPELL_ID) then
        -- Without the Crusader Strike talent the guide must never recommend it
        return 999
    end
    return get_live_cooldown_remaining(CS_SPELL_ID, "cs_expires")
end

st.nextaction.get_judge_remaining = function()
    if st.practice and st.practice.active then
        return get_sim_cooldown_remaining(st.practice.sim.judge_cooldown_expires)
    end
    return get_live_cooldown_remaining(JUDGEMENT_SPELL_ID)
end

-- Returns remaining, known for one filler spell ("consecration" | "exorcism")
st.nextaction.get_filler_remaining = function(kind)
    if st.practice and st.practice.active then
        if kind == "exorcism" then
            return 0, true
        end
        return get_sim_cooldown_remaining(st.practice.sim.consec_cooldown_expires), true
    end
    local name = kind == "exorcism" and EXORCISM_NAME or CONSECRATION_NAME
    if not name then
        return 0, false
    end
    local start_time = GetSpellCooldown(name)
    if not start_time then
        return 0, false
    end
    return get_live_cooldown_remaining(name), true
end

local function get_seal_remaining(label)
    local now = GetTime()
    if st.player.seal_1_label == label and st.player.seal_1_expires and st.player.seal_1_expires > 0 then
        return st.player.seal_1_expires - now
    end
    if st.player.seal_2_label == label and st.player.seal_2_expires and st.player.seal_2_expires > 0 then
        return st.player.seal_2_expires - now
    end
    return nil
end

-- Active seal for the decision tree: "sob", "soc", or "none". Blood wins during the
-- dual-seal twist window (the correct next step after twisting is to re-seal Command).
-- Command only counts with >1s remaining, matching the WeakAura. Practice-mode sim
-- seals never expire (their synced expiry is stamped once and can go stale), so the
-- freshness check only applies to live play.
st.nextaction.get_active_seal = function()
    local seals = st.player.active_seals or {}
    if seals["blood"] then
        return "sob"
    end
    if seals["command"] then
        if st.practice and st.practice.active then
            return "soc"
        end
        local remaining = get_seal_remaining("command")
        if remaining == nil or remaining > 1 then
            return "soc"
        end
    end
    return "none"
end

--=========================================================================================
-- Decision engine
-- Direct port of the WeakAura's HOLD aura logic. The WA worked in absolute GetTime()
-- timestamps; here everything is in seconds relative to now, derived from the
-- countdown-style st.player.swing_timer.
--=========================================================================================

st.nextaction.compute = function()
    local db = ST.db.profile
    local speed = st.player.current_weapon_speed
    local swing_remaining = st.player.swing_timer
    local G = st.player.spell_gcd_duration
    local gcd_remaining = 0
    if st.player.gcd_lockout and st.player.active_gcd_remaining > 0 then
        gcd_remaining = st.player.active_gcd_remaining
    end
    -- Practice grades twists against its exact 400ms fading-seal window; the bar's
    -- lag-padded window would cue the twist too early there and get graded MISS
    local twist_window
    if st.practice and st.practice.active then
        twist_window = 0.4
    else
        twist_window = st.bar.get_twist_window_time_before_swing()
    end
    local reaction = (db.nextaction_reaction_time_ms or 100) / 1000

    -- Time from now until each landmark, mirroring the WA's nextSwing / divWhen /
    -- twistGap and their next-swing equivalents. "div" is the last moment a seal GCD
    -- can start and still finish before the twist window opens.
    local rel_swing = swing_remaining - reaction / 2
    local rel_div = swing_remaining - twist_window - G - reaction / 2
    local rel_gap = swing_remaining - twist_window - reaction / 4
    local rel_div2 = swing_remaining + speed - twist_window - G
    local rel_gap2 = swing_remaining + speed - twist_window

    local prediction_land = gcd_remaining + G

    local cs_remaining = st.nextaction.get_cs_remaining()
    local judge_remaining = st.nextaction.get_judge_remaining()
    local seal = st.nextaction.get_active_seal()

    local action = st.nextaction.action
    local hold = false
    local filler = false
    local riding = false
    local prediction_hold = 10

    local function where_is_swing_at()
        if rel_div < 0 and rel_gap < 0 and rel_swing < 0 then
            return "swing ready"
        elseif rel_div > 0 then
            return "before div"
        elseif rel_gap < 0 then
            return "in twist"
        elseif rel_swing > 0 then
            return "after div"
        else
            return "swing ready"
        end
    end

    if seal == "sob" then
        -- Blood is up: decide directly from the swing timer whether a twist for
        -- THIS swing still fits (reseal Command) or whether the swing lands as a
        -- blood auto (ride it). The reseal deadline is the bar's own GCD marker:
        -- Command's GCD must free before the swing lands so Blood can be recast
        -- inside the twist window.
        action = "soc"
        local reseal_deadline = st.bar.get_gcd_time_before_swing() + reaction
        if (swing_remaining - gcd_remaining) > reseal_deadline then
            -- Reseal now (or queue it for the end of the running GCD)
            prediction_hold = reaction + math.max(rel_gap, 0)
        elseif rel_gap > 0 then
            -- Blood auto: ride the seal, resealing only once the twist window
            -- opens (a reseal inside the window preserves the blood swing)
            hold = true
            riding = true
            filler = true
            prediction_hold = reaction + math.max(prediction_land, rel_gap2)
        else
            -- Window open: resealing now preserves the blood swing
            prediction_hold = reaction + rel_gap2
        end
    elseif gcd_remaining > 0 then
        -- GCD busy: decide based on when it frees relative to the swing landmarks
        local check = gcd_remaining
        if rel_div >= check then
            -- GCD frees before div
            if seal ~= "soc" then
                action = "soc"
                prediction_hold = reaction + rel_gap
            else
                action = "twist"
                hold = true
                filler = true
                prediction_hold = reaction + rel_gap
            end
        elseif check > rel_gap and check < rel_swing then
            -- GCD frees inside the twist gap
            if seal == "soc" then
                action = "twist"
                prediction_hold = -1
            else
                if cs_remaining <= check + G then
                    action = "soc"
                else
                    action = "sob"
                end
                prediction_hold = reaction + gcd_remaining
            end
        elseif check < rel_gap then
            -- GCD frees after div but before the twist gap
            if seal == "soc" then
                action = "twist"
                hold = true
                prediction_hold = reaction + rel_gap
            else
                if cs_remaining <= check + G then
                    action = "soc"
                else
                    action = "sob"
                end
                prediction_hold = reaction + gcd_remaining
            end
        elseif rel_div2 >= check then
            -- GCD frees before the next swing's div
            if seal ~= "soc" then
                action = "soc"
                prediction_hold = reaction + math.max(prediction_land, rel_gap2)
            else
                action = "twist"
                hold = true
                filler = true
                prediction_hold = reaction + math.max(prediction_land, rel_gap2)
            end
        else
            -- GCD frees after the next swing's div
            if seal == "soc" then
                action = "twist"
                hold = true
                prediction_hold = reaction + math.max(prediction_land, rel_gap2)
            else
                action = "soc"
                prediction_hold = reaction + gcd_remaining
            end
        end
    else
        -- GCD ready: decide based on where the swing is right now
        local at = where_is_swing_at()
        if at == "before div" or at == "swing ready" then
            if seal ~= "soc" then
                action = "soc"
                prediction_hold = reaction + rel_gap
            else
                action = "twist"
                hold = true
                filler = true
                prediction_hold = reaction + rel_gap
            end
        elseif at == "in twist" then
            if seal == "soc" then
                action = "twist"
                prediction_hold = -1
            else
                if cs_remaining <= G then
                    action = "soc"
                else
                    action = "sob"
                end
                prediction_hold = 0
            end
        elseif at == "after div" then
            if seal == "soc" then
                action = "twist"
                hold = true
                prediction_hold = reaction + rel_gap
            else
                if cs_remaining <= G then
                    action = "soc"
                else
                    action = "sob"
                end
                prediction_hold = 0
            end
        end
    end

    if prediction_hold < 0 then
        prediction_hold = 0
    end

    -- No filler if CS comes back before the current GCD would finish
    if filler and (cs_remaining + 0.05) < G then
        filler = false
    end

    -- Crusader Strike override: if delaying CS any longer would exceed the allowed
    -- delay budget, CS becomes the next action
    local cs_delay_max = (db.nextaction_cs_max_delay_ms or 1700) / 1000
    if action == "twist" then
        cs_delay_max = cs_delay_max + 0.1
    end
    local cs_when = prediction_hold + G + reaction
    local cs_delay = cs_remaining - cs_when + cs_delay_max
    if cs_delay <= 0 then
        action = "cs"
        hold = false
        riding = false
        if gcd_remaining <= 0 then
            if cs_remaining > 0.1 then
                hold = true
            end
        else
            if cs_remaining + 0.1 > gcd_remaining then
                hold = true
            end
        end
    end

    -- Filler suggestion (Consecration / Exorcism) when there's room in the rotation.
    -- The kind is chosen first (target type + mana), then gated on that spell's own
    -- cooldown being back by the time the GCD frees.
    local filler_kind = nil
    if filler and speed > 2.2 and st.nextaction.melee_count > 2 then
        local candidate = nil
        if st.practice and st.practice.active then
            candidate = "consecration"
        else
            local mana_max = UnitPowerMax("player")
            local mana_pct = 0
            if mana_max and mana_max > 0 then
                mana_pct = UnitPower("player") / mana_max * 100
            end
            local creature_type = UnitExists("target") and UnitCreatureType("target") or nil
            if creature_type and EXORCISM_TARGET_TYPES[creature_type] then
                if mana_pct > (db.nextaction_filler_mana_exorcism or 30) then
                    candidate = "exorcism"
                end
            else
                if mana_pct > (db.nextaction_filler_mana_consecration or 35) then
                    candidate = "consecration"
                end
            end
        end
        if candidate then
            local remaining, known = st.nextaction.get_filler_remaining(candidate)
            if known and remaining <= gcd_remaining then
                filler_kind = candidate
            end
        end
    end

    -- Judgement cue: judge the active Seal of Blood before twisting back to Command.
    -- Suppressed while riding — judging would consume the seal and ruin the blood
    -- auto; the cue appears once the ride ends at the reseal point.
    local judge_call = false
    if action == "soc" and seal == "sob" and not riding then
        local a_rel
        if where_is_swing_at() == "before div" then
            a_rel = rel_div
        else
            a_rel = rel_div2
        end
        if judge_remaining < a_rel then
            judge_call = true
            if judge_remaining > 0 and speed > 2.3 then
                if not hold then
                    hold = true
                    st.nextaction.waiting_judgement = true
                end
            elseif st.nextaction.waiting_judgement then
                hold = false
                st.nextaction.waiting_judgement = false
            end
        end
    else
        st.nextaction.waiting_judgement = false
    end

    st.nextaction.action = action
    st.nextaction.hold = hold
    st.nextaction.riding = riding
    st.nextaction.judge_call = judge_call
    st.nextaction.filler_kind = filler_kind
    st.nextaction.cs_remaining = cs_remaining
    st.nextaction.judge_remaining = judge_remaining
end

--=========================================================================================
-- Visibility and activity gates
--=========================================================================================

-- Zone gate: the guide can be limited to certain zone types (e.g. raids only, or
-- nothing in battlegrounds/arenas). Keyed by the instance type IsInInstance() reports.
local ZONE_SETTING = {
    none = "nextaction_zone_world",
    party = "nextaction_zone_party",
    raid = "nextaction_zone_raid",
    pvp = "nextaction_zone_pvp",
    arena = "nextaction_zone_arena",
}

st.nextaction.zone_allowed = function()
    local db = ST.db.profile
    local _, instance_type = IsInInstance()
    local key = ZONE_SETTING[instance_type or "none"] or "nextaction_zone_world"
    local allowed = db[key]
    if allowed == nil then
        return true
    end
    return allowed
end

st.nextaction.should_show = function()
    local db = ST.db.profile
    -- Design mode shows the guide (ghosted when disabled) so it can be arranged
    if st.editmode and st.editmode.active and st.editmode.active() then
        return true
    end
    if not db.nextaction_enabled then
        return false
    end
    if st.practice and st.practice.active then
        return true
    end
    -- The unlocked override outranks ret_only so the frame can always be positioned
    if not db.nextaction_locked then
        return true
    end
    if db.ret_only and not st.utils.is_ret_spec then
        return false
    end
    if not st.nextaction.zone_allowed() then
        return false
    end
    if db.nextaction_visibility_key == "always" then
        return true
    end
    return st.core.in_combat
end

-- True when the engine should actively compute recommendations; otherwise the
-- display shows a dimmed idle state
st.nextaction.engine_active = function()
    if st.practice and st.practice.active then
        -- Practice scoring pauses during real combat; suppress guidance too
        return st.practice.sim.fight_active and not st.core.in_combat
    end
    return st.core.in_combat
end

--=========================================================================================
-- Per-frame update, called from st.player.frame_on_update
--=========================================================================================

st.nextaction.on_update = function(elapsed)
    if not st.nextaction.frame then
        return
    end
    -- Alpha fades run every frame; the engine below ticks at update_interval
    if st.nextaction.frame:IsShown() and st.nextaction.animate then
        st.nextaction.animate(elapsed or 0.016)
    end
    st.nextaction.update_counter = st.nextaction.update_counter + (elapsed or 0.016)
    if st.nextaction.update_counter < st.nextaction.update_interval then
        return
    end
    st.nextaction.update_counter = 0

    if not st.nextaction.should_show() then
        if st.nextaction.frame:IsShown() then
            st.nextaction.frame:Hide()
        end
        st.nextaction.melee_count = 0
        return
    end

    if st.nextaction.engine_active() then
        st.nextaction.idle = false
        st.nextaction.compute()
    else
        st.nextaction.idle = true
        st.nextaction.melee_count = 0
        st.nextaction.action = "sob"
        st.nextaction.hold = false
        st.nextaction.riding = false
        st.nextaction.judge_call = false
        st.nextaction.filler_kind = nil
        st.nextaction.waiting_judgement = false
    end

    if st.practice and st.practice.active then
        st.nextaction.rotation_key = st.practice.determine_rotation()
    elseif st.rotation and st.rotation.calculate_rotation then
        st.nextaction.rotation_key = st.rotation.calculate_rotation()
    end

    st.nextaction.update_display()
end

--=========================================================================================
-- Display
-- Faithful recreation of the WeakAura's visuals: all icons stacked at the same point
-- and cross-faded over 0.2s (the WA's preset fade), full uncropped spell textures
-- with a thin "Blizzard Dialog" border, an inverse cooldown swipe on the Crusader
-- Strike and Judgement icons, a Pixel glow on the Judgement cue, a dark 80px HOLD
-- circle with white HOLD text (shown instantly, no fade), filler icons that pop over
-- everything with a FILLER label, the "Next action:" label above the icons and the
-- rotation text below them.
--=========================================================================================

local SML = LibStub("LibSharedMedia-3.0")
local LCG = LibStub("LibCustomGlow-1.0")

local FADE_DURATION = 0.2               -- the WA's preset fade in/out time
local BASE_ICON_SIZE = 45               -- everything is authored at WA scale, then SetScale'd
-- Bundled crisp anti-aliased circle (the WA used WeakAuras' Circle_Smooth2.tga,
-- which we can't reference). Sized to the icon and translucent so the recommended
-- action stays visible under the HOLD cue.
local HOLD_CIRCLE_TEXTURE = "Interface\\AddOns\\SwedgeTimer\\Images\\circle_smooth.tga"
local HOLD_CIRCLE_COLOR = {0.090, 0.067, 0.039, 0.45}
local HOLD_CIRCLE_SIZE = 40

-- WA icon zoom crops zoom/2 off each texture edge; keepAspectRatio additionally
-- narrows the horizontal range for non-square icons (center crop)
local function set_icon_texcoords(tex, zoom, aspect_width, aspect_height)
    local crop = (zoom or 0) / 2
    local left, right, top, bottom = crop, 1 - crop, crop, 1 - crop
    if aspect_width and aspect_height and aspect_width < aspect_height then
        local span = (right - left) * (aspect_width / aspect_height)
        local mid = (left + right) / 2
        left, right = mid - span / 2, mid + span / 2
    end
    tex:SetTexCoord(left, right, top, bottom)
end

-- One WA-style icon: full texture, "Blizzard Dialog" border, optional inverse
-- cooldown swipe. Created at alpha 0; visibility is driven by the fade system.
local function create_wa_icon(parent, name_suffix, width, height, spell_texture_id, opts)
    opts = opts or {}
    local icon = CreateFrame("Frame", addon_name .. "NextAction" .. name_suffix, parent)
    icon:SetSize(width, height)
    icon:SetFrameLevel(parent:GetFrameLevel() + (opts.level or 1))

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    if spell_texture_id then
        icon.texture:SetTexture(GetSpellTexture(spell_texture_id))
    end
    if opts.keep_aspect then
        set_icon_texcoords(icon.texture, opts.zoom, width, height)
    else
        set_icon_texcoords(icon.texture, opts.zoom)
    end

    icon.border_frame = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    icon.border_frame:SetAllPoints()
    icon.border_frame:SetBackdrop({
        edgeFile = SML:Fetch("border", "Blizzard Dialog"),
        edgeSize = opts.border_size or 2,
    })
    icon.border_frame:SetBackdropBorderColor(0, 0, 0, 1)

    if opts.cooldown then
        icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        icon.cooldown:SetAllPoints()
        icon.cooldown:SetReverse(true)
        icon.cooldown:SetHideCountdownNumbers(true)
        icon.cooldown_set = false
    end

    icon:SetAlpha(0)
    return icon
end

--=========================================================================================
-- Fade system: elements animate their alpha toward a target, replicating the WA's
-- fade in/out preset animations (HOLD is instant, matching the WA)
--=========================================================================================

st.nextaction.fade_elements = {}

local function register_fade(frame_, instant)
    local el = { frame = frame_, current = 0, target = 0, instant = instant }
    table.insert(st.nextaction.fade_elements, el)
    return el
end

local function set_fade_target(el, target)
    el.target = target
    if el.instant and el.current ~= target then
        el.current = target
        el.frame:SetAlpha(target)
    end
end

st.nextaction.animate = function(elapsed)
    local step = elapsed / FADE_DURATION
    for i = 1, #st.nextaction.fade_elements do
        local el = st.nextaction.fade_elements[i]
        if el.current ~= el.target then
            if el.current < el.target then
                el.current = math.min(el.target, el.current + step)
            else
                el.current = math.max(el.target, el.current - step)
            end
            el.frame:SetAlpha(el.current)
        end
    end
end

--=========================================================================================
-- Frame construction
--=========================================================================================

st.nextaction.init = function()
    local db = ST.db.profile

    -- Count landed swings by wrapping the swing reset, which runs exactly once per
    -- completed swing in both live mode (CLEU swing events) and practice mode
    -- (sim_on_swing); practice does not hook or replace this function
    if not st.nextaction.swing_hook_installed then
        st.nextaction.swing_hook_installed = true
        local orig_reset_swing_timer = st.player.reset_swing_timer
        st.player.reset_swing_timer = function(...)
            if st.nextaction.engine_active and st.nextaction.engine_active() then
                st.nextaction.melee_count = st.nextaction.melee_count + 1
            end
            return orig_reset_swing_timer(...)
        end
    end

    local frame = CreateFrame("Frame", addon_name .. "NextActionFrame", UIParent)
    st.nextaction.frame = frame
    frame:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
    frame:SetPoint("CENTER", UIParent, "CENTER", db.nextaction_x, db.nextaction_y)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ST.db.profile.nextaction_locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- The frame is scaled, so convert its center into UIParent coordinates
        local s = self:GetScale()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        ST.db.profile.nextaction_x = math.floor(cx * s - ux + 0.5)
        ST.db.profile.nextaction_y = math.floor(cy * s - uy + 0.5)
    end)

    -- Action icons, all stacked on the frame's center like the WA group; only one
    -- is faded in at a time. WA geometry: 45x45, zoom 0, 2px Blizzard Dialog border.
    frame.icon_cs = create_wa_icon(frame, "IconCS", 45, 45, CS_SPELL_ID,
        { cooldown = true, level = 1 })
    frame.icon_cs:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame.icon_command = create_wa_icon(frame, "IconCommand", 45, 45, SOC_TEXTURE_ID,
        { level = 3 })
    frame.icon_command:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame.icon_blood = create_wa_icon(frame, "IconBlood", 45, 45, SOB_TEXTURE_ID,
        { level = 5 })
    frame.icon_blood:SetPoint("CENTER", frame, "CENTER", 0, 0)

    -- Twist: full Command icon with a half-width, center-cropped Blood icon over
    -- its right half (the WA's 'twist 1/2' + 'twist 2/2' pair)
    frame.icon_twist = CreateFrame("Frame", addon_name .. "NextActionTwist", frame)
    frame.icon_twist:SetSize(45, 45)
    frame.icon_twist:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.icon_twist:SetFrameLevel(frame:GetFrameLevel() + 7)
    frame.icon_twist.left = create_wa_icon(frame.icon_twist, "TwistLeft", 45, 45, SOC_TEXTURE_ID,
        { level = 1 })
    frame.icon_twist.left:SetPoint("CENTER", frame.icon_twist, "CENTER", 0, 0)
    frame.icon_twist.left:SetAlpha(1)
    frame.icon_twist.right = create_wa_icon(frame.icon_twist, "TwistRight", 22.5, 45, SOB_TEXTURE_ID,
        { keep_aspect = true, level = 2 })
    frame.icon_twist.right:SetPoint("CENTER", frame.icon_twist, "CENTER", 11.25, 0)
    frame.icon_twist.right:SetAlpha(1)
    frame.icon_twist:SetAlpha(0)

    -- Judgement cue: small icon low-left over the action icon (WA: 22.5x24.9 at
    -- (-9,-10), 1px border, inverse cooldown swipe, Pixel glow while shown)
    frame.icon_judge = create_wa_icon(frame, "JudgeTime", 22.5, 24.9, JUDGEMENT_SPELL_ID,
        { cooldown = true, keep_aspect = true, border_size = 1, level = 9 })
    frame.icon_judge:SetPoint("CENTER", frame, "CENTER", -9, -10)

    -- HOLD: dark translucent circle over the action icon with white HOLD text
    -- (the WA drew a near-black circle with Friz Quadrata 12 OUTLINE text)
    frame.hold = CreateFrame("Frame", addon_name .. "NextActionHold", frame)
    frame.hold:SetSize(HOLD_CIRCLE_SIZE, HOLD_CIRCLE_SIZE)
    frame.hold:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.hold:SetFrameLevel(frame:GetFrameLevel() + 11)
    frame.hold.circle = frame.hold:CreateTexture(nil, "ARTWORK")
    frame.hold.circle:SetAllPoints()
    frame.hold.circle:SetTexture(HOLD_CIRCLE_TEXTURE)
    frame.hold.circle:SetVertexColor(unpack(HOLD_CIRCLE_COLOR))
    frame.hold.text = frame.hold:CreateFontString(nil, "OVERLAY")
    frame.hold.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.hold.text:SetPoint("CENTER", frame.hold, "CENTER", 0, 0)
    frame.hold.text:SetTextColor(1, 1, 1, 1)
    frame.hold.text:SetText("HOLD")
    frame.hold:SetAlpha(0)

    -- Filler icons pop over everything in the same slot (WA: Consecration zoom 0.2,
    -- Exorcism zoom 0.15, white FILLER label bottom-right)
    frame.filler_consec = create_wa_icon(frame, "FillerC", 45, 45, CONSECRATION_SPELL_ID,
        { zoom = 0.2, level = 13 })
    frame.filler_consec:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.filler_exo = create_wa_icon(frame, "FillerE", 45, 45, EXORCISM_SPELL_ID,
        { zoom = 0.15, level = 14 })
    frame.filler_exo:SetPoint("CENTER", frame, "CENTER", 0, 0)
    for _, filler in ipairs({ frame.filler_consec, frame.filler_exo }) do
        filler.label = filler:CreateFontString(nil, "OVERLAY")
        filler.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        filler.label:SetPoint("CENTER", filler, "CENTER", 0, 0)
        filler.label:SetTextColor(1, 1, 1, 1)
        filler.label:SetText("FILLER")
    end

    -- "Next action:" label above the icons (WA: Friz Quadrata 8 OUTLINE at (2,25))
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    frame.label:SetPoint("CENTER", frame, "CENTER", 2, 25)
    frame.label:SetTextColor(1, 1, 1, 1)
    frame.label:SetShadowColor(0, 0, 0, 1)
    frame.label:SetShadowOffset(1, -1)
    frame.label:SetText("Next action:")

    -- Rotation pattern text below the icons (WA: font "2002" size 12 OUTLINE,
    -- bottom-anchored 40px below center)
    frame.rotation_text = frame:CreateFontString(nil, "OVERLAY")
    frame.rotation_text:SetFont("Fonts\\2002.TTF", 12, "OUTLINE")
    frame.rotation_text:SetPoint("BOTTOM", frame, "CENTER", 0, -40)
    frame.rotation_text:SetTextColor(1, 1, 1, 1)
    frame.rotation_text:SetShadowColor(0, 0, 0, 1)
    frame.rotation_text:SetShadowOffset(1, -1)

    -- Fade bookkeeping: HOLD shows/hides instantly like the WA; the rest fade
    st.nextaction.fade_elements = {}
    frame.icon_cs.fade = register_fade(frame.icon_cs)
    frame.icon_command.fade = register_fade(frame.icon_command)
    frame.icon_blood.fade = register_fade(frame.icon_blood)
    frame.icon_twist.fade = register_fade(frame.icon_twist)
    frame.icon_judge.fade = register_fade(frame.icon_judge)
    frame.hold.fade = register_fade(frame.hold, true)
    frame.filler_consec.fade = register_fade(frame.filler_consec)
    frame.filler_exo.fade = register_fade(frame.filler_exo)

    frame:Hide()
    st.nextaction.apply_settings()
end

-- Applies a started-or-updated cooldown swipe once per cooldown, following the
-- codebase's cooldown_set flag pattern. An upward jump in remaining means a new
-- cooldown started without an observed gap (e.g. spell-queued recast) — re-arm.
local function set_icon_cooldown(icon, remaining, full_duration)
    remaining = remaining or 0
    if remaining > (icon.cooldown_prev or 0) + 0.1 then
        icon.cooldown_set = false
    end
    icon.cooldown_prev = remaining
    if remaining > 0 then
        if not icon.cooldown_set then
            icon.cooldown:SetCooldown(GetTime() - (full_duration - remaining), full_duration)
            icon.cooldown_set = true
        end
    else
        if icon.cooldown_set then
            icon.cooldown:SetCooldown(0, 0)
            icon.cooldown_set = false
        end
    end
end

st.nextaction.update_display = function()
    local frame = st.nextaction.frame
    if not frame then
        return
    end
    local db = ST.db.profile

    if not frame:IsShown() then
        frame:Show()
    end

    local cs_target, command_target, blood_target, twist_target = 0, 0, 0, 0
    local judge_target, hold_target, consec_target, exo_target = 0, 0, 0, 0
    local previewing = st.editmode and st.editmode.active and st.editmode.active()

    if previewing then
        frame:SetAlpha(db.nextaction_enabled and 1 or 0.35)
        local phase = st.bar and st.bar.preview_phase
        if phase == "blood" then
            -- simulation, Blood swing: reseal Command (judge the Blood first)
            command_target = 1
            if db.nextaction_show_judgement then judge_target = 1 end
        elseif phase == "twisting" then
            -- simulation, inside the window: twist now
            twist_target = 1
        else
            -- static sample / simulation before the window: the twist cue, holding
            twist_target = 1
            if db.nextaction_hold_enabled then
                hold_target = 1
                frame.hold.text:SetText("HOLD")
            end
            if phase == nil and db.nextaction_show_judgement then judge_target = 1 end
        end
    elseif st.nextaction.idle then
        -- No active guidance (out of combat / practice fight not running): show the
        -- Seal of Blood opener dimmed
        blood_target = 0.5
    else
        local action = st.nextaction.action
        if st.nextaction.riding then
            -- Riding the active Seal of Blood (blood auto): show the Blood icon
            -- with the RIDE overlay until it's safe to reseal Command
            blood_target = 1
        elseif action == "cs" then
            cs_target = 1
        elseif action == "soc" then
            command_target = 1
        elseif action == "twist" then
            twist_target = 1
        else
            blood_target = 1
        end
        if st.nextaction.hold and db.nextaction_hold_enabled then
            hold_target = 1
            frame.hold.text:SetText(st.nextaction.riding and "RIDE" or "HOLD")
        end
        if st.nextaction.filler_kind and db.nextaction_show_fillers then
            if st.nextaction.filler_kind == "exorcism" then
                exo_target = 1
            else
                consec_target = 1
            end
        end
        -- The filler pops over the whole slot; suppress the judgement cue (and its
        -- glow, which would otherwise render through the filler icon) while it shows
        if st.nextaction.judge_call and db.nextaction_show_judgement
            and consec_target == 0 and exo_target == 0 then
            judge_target = 1
        end
    end

    set_fade_target(frame.icon_cs.fade, cs_target)
    set_fade_target(frame.icon_command.fade, command_target)
    set_fade_target(frame.icon_blood.fade, blood_target)
    set_fade_target(frame.icon_twist.fade, twist_target)
    set_fade_target(frame.icon_judge.fade, judge_target)
    set_fade_target(frame.hold.fade, hold_target)
    set_fade_target(frame.filler_consec.fade, consec_target)
    set_fade_target(frame.filler_exo.fade, exo_target)

    -- Cooldown swipes on the CS and Judgement icons (inverse, like the WA)
    if cs_target > 0 then
        set_icon_cooldown(frame.icon_cs, st.nextaction.cs_remaining, CS_COOLDOWN)
    else
        set_icon_cooldown(frame.icon_cs, 0, CS_COOLDOWN)
    end
    if judge_target > 0 then
        set_icon_cooldown(frame.icon_judge, st.nextaction.judge_remaining, JUDGEMENT_COOLDOWN)
    else
        set_icon_cooldown(frame.icon_judge, 0, JUDGEMENT_COOLDOWN)
    end

    -- Pixel glow on the Judgement cue (WA subglow: Pixel, 8 lines, 0.25 frequency,
    -- length 10, thickness 1)
    if judge_target > 0 and not st.nextaction.judge_glowing then
        st.nextaction.judge_glowing = true
        LCG.PixelGlow_Start(frame.icon_judge, nil, 8, 0.25, 10, 1, 0, 0, false, "NextActionJudge")
    elseif judge_target == 0 and st.nextaction.judge_glowing then
        st.nextaction.judge_glowing = false
        LCG.PixelGlow_Stop(frame.icon_judge, "NextActionJudge")
    end

    local rotation_key = st.nextaction.rotation_key
    if previewing and not rotation_key then rotation_key = "2/3" end
    if db.nextaction_show_rotation_text and rotation_key then
        local display = st.rotation and st.rotation.display_names
            and st.rotation.display_names[rotation_key]
            or rotation_key
        frame.rotation_text:SetText(display)
        frame.rotation_text:Show()
    else
        frame.rotation_text:Hide()
    end

    if db.nextaction_show_label == false then
        frame.label:Hide()
    else
        frame.label:Show()
    end
end

-- Re-reads settings and applies them to the live frame; used by the options panel
-- and by import refresh
st.nextaction.apply_settings = function()
    local frame = st.nextaction.frame
    if not frame then
        return
    end
    local db = ST.db.profile
    local enabled = db.nextaction_enabled
    local locked = db.nextaction_locked

    -- The display is authored at the WA's 45px geometry and scaled as one unit so
    -- every element keeps its exact relative size and position
    local scale = (db.nextaction_icon_size or BASE_ICON_SIZE) / BASE_ICON_SIZE
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        (db.nextaction_x or 0) / scale, (db.nextaction_y or 0) / scale)
    frame:SetMovable(not locked and enabled)
    frame:EnableMouse(not locked and enabled)
    if db.nextaction_show_label == false then
        frame.label:Hide()
    else
        frame.label:Show()
    end

    frame:SetAlpha(1)
    if st.nextaction.should_show() then
        st.nextaction.update_display()
    else
        frame:Hide()
    end
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed nextaction.lua module correctly') end
