--=========================================================================================
-- Next Action Guide display: the on-screen rotation prompt (Crusader Strike / Seal of
-- Command / Seal of Blood / twist icon, HOLD / RIDE overlay, Judgement cue, filler
-- icons and the optional rotation text below the frame).
-- Port of the archived build's nextaction.lua display half
-- (docs/swedge/SwedgeTimer_Forever/nextaction.lua 590-1011), minus practice mode and
-- edit mode. The decision engine lives in the pure st.nextaction module
-- (nextaction.lua); this file only builds the frame, feeds it the gathered inputs and
-- maps the engine output onto the widgets.
-- The guide never gates on st.is_mainline (the Forever client is Mainline-code but must
-- show it); swing activity decides instead.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LSM = LibStub("LibSharedMedia-3.0")
local LCG = LibStub("LibCustomGlow-1.0")
-- Cross-client API wrappers (see compat.lua).
local api = st.api

st.nextaction_ui = st.nextaction_ui or {}
local ui = st.nextaction_ui

--=========================================================================================
-- Display constants (authored at the archive's WeakAura scale, then SetScale'd as one
-- unit so every element keeps its exact relative size and position)
--=========================================================================================
local FADE_DURATION = 0.2               -- the WA's preset fade in/out time
local BASE_ICON_SIZE = 45               -- everything is authored at WA scale
local UPDATE_INTERVAL = 0.05            -- engine tick, matches the WA's aura poll cadence
-- Fallback swipe lengths, used only while no real duration has been observed yet (the
-- paladin module latches the length the client reported for each spell cooldown in
-- get_guide_cooldown_remaining and hands it over as inputs.cs_duration /
-- inputs.judge_duration; LibClassicDurations is aura-based and knows nothing about spell
-- cooldowns, so the latch is the only real source here).
local CS_COOLDOWN = 6                   -- fallback full CS cooldown (swipe duration), seconds
local JUDGEMENT_COOLDOWN = 8            -- fallback full Judgement cooldown (swipe duration)
-- Fallback seal swipe length: the vanilla/TBC seal duration the archived build used
-- (docs/swedge/SwedgeTimer_TBC/player.lua seal_1_duration). When LibClassicDurations
-- exists AND tracks the seal's aura (Classic Era / TBC Anniversary only, see the header
-- block in classes/paladin.lua), the paladin module latches that length into
-- self.soc_duration / self.sob_duration and that value is used instead; untracked auras,
-- Seal of Blood everywhere, and every other client family land on this constant.
local SEAL_DURATION = 30
-- Crisp circle texture ported from the archive's Images/ (shipped as
-- Media/Textures/circle_smooth.tga). The plain-texture fallback below stays for
-- profiles where the asset is missing; a missing texture file never raises.
local HOLD_CIRCLE_ASSET = true
local HOLD_CIRCLE_TEXTURE = "Interface\\AddOns\\SwedgeTimer\\Media\\Textures\\circle_smooth.tga"
local HOLD_CIRCLE_COLOR = {0.090, 0.067, 0.039, 0.45}
local HOLD_CIRCLE_SIZE = 40

--=========================================================================================
-- Icon helpers (archive create_wa_icon; icons come from compat's GetSpellInfo so both
-- the classic icon-path and the Mainline icon-id shapes work)
--=========================================================================================
local function get_spell_icon(spell_id)
    if not spell_id then
        return nil
    end
    return select(3, api.GetSpellInfo(spell_id))
end

-- WA icon zoom crops zoom/2 off each texture edge; keepAspectRatio additionally
-- narrows the horizontal range for non-square icons (center crop).
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
local function create_wa_icon(parent, name_suffix, width, height, spell_id, opts)
    opts = opts or {}
    local icon = CreateFrame("Frame", addon_name .. "NextAction" .. name_suffix, parent)
    icon:SetSize(width, height)
    icon:SetFrameLevel(parent:GetFrameLevel() + (opts.level or 1))

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    local texture = get_spell_icon(spell_id)
    if texture then
        icon.texture:SetTexture(texture)
    end
    if opts.keep_aspect then
        set_icon_texcoords(icon.texture, opts.zoom, width, height)
    else
        set_icon_texcoords(icon.texture, opts.zoom)
    end

    icon.border_frame = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    icon.border_frame:SetAllPoints()
    icon.border_frame:SetBackdrop({
        edgeFile = LSM:Fetch("border", "Blizzard Dialog"),
        edgeSize = opts.border_size or 2,
    })
    icon.border_frame:SetBackdropBorderColor(0, 0, 0, 1)

    if opts.cooldown then
        icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        icon.cooldown:SetAllPoints()
        icon.cooldown:SetReverse(true)
        if icon.cooldown.SetHideCountdownNumbers then
            icon.cooldown:SetHideCountdownNumbers(true)
        end
        icon.cooldown_set = false
    end

    icon:SetAlpha(0)
    return icon
end

--=========================================================================================
-- Fade system: elements animate their alpha toward a target, replicating the WA's fade
-- in/out preset animations (HOLD is instant, matching the WA)
--=========================================================================================
local fade_elements = {}

local function register_fade(frame, instant)
    local el = { frame = frame, current = 0, target = 0, instant = instant }
    fade_elements[#fade_elements + 1] = el
    return el
end

local function set_fade_target(el, target)
    el.target = target
    if el.instant and el.current ~= target then
        el.current = target
        el.frame:SetAlpha(target)
    end
end

local function animate(elapsed)
    local step = elapsed / FADE_DURATION
    for i = 1, #fade_elements do
        local el = fade_elements[i]
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

local function set_element_targets(frame, cs_target, command_target, blood_target,
        twist_target, judge_target, hold_target, consec_target, exo_target)
    set_fade_target(frame.icon_cs.fade, cs_target)
    set_fade_target(frame.icon_command.fade, command_target)
    set_fade_target(frame.icon_blood.fade, blood_target)
    set_fade_target(frame.icon_twist.fade, twist_target)
    set_fade_target(frame.icon_judge.fade, judge_target)
    set_fade_target(frame.hold.fade, hold_target)
    set_fade_target(frame.filler_consec.fade, consec_target)
    set_fade_target(frame.filler_exo.fade, exo_target)
end

--=========================================================================================
-- Frame construction (archive geometry; practice and edit-mode couplings removed)
--=========================================================================================
function ui.init(self)
    if ui.frame then
        return
    end
    local na = st.nextaction
    if not na then
        -- The pure engine module is not loaded on this flavor: nothing to display.
        return
    end
    local db = self:get_class_table()

    local frame = CreateFrame("Frame", addon_name .. "NextActionFrame", UIParent)
    ui.frame = frame
    frame:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
    frame:SetPoint("CENTER", UIParent, "CENTER", db.nextaction_x or 0, db.nextaction_y or -180)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        if not ST:get_class_table().nextaction_locked then
            f:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        -- The frame is scaled, so convert its center into UIParent coordinates.
        local s = f:GetScale()
        local cx, cy = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local class_db = ST:get_class_table()
        class_db.nextaction_x = math.floor(cx * s - ux + 0.5)
        class_db.nextaction_y = math.floor(cy * s - uy + 0.5)
    end)

    -- Action icons, all stacked on the frame's center like the WA group; only one
    -- is faded in at a time.
    frame.icon_cs = create_wa_icon(frame, "IconCS", 45, 45, na.CS_SPELL_ID,
        { cooldown = true, level = 1 })
    frame.icon_cs:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame.icon_command = create_wa_icon(frame, "IconCommand", 45, 45, na.SOC_ID,
        { cooldown = true, level = 3 })
    frame.icon_command:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame.icon_blood = create_wa_icon(frame, "IconBlood", 45, 45, na.SOB_ID,
        { cooldown = true, level = 5 })
    frame.icon_blood:SetPoint("CENTER", frame, "CENTER", 0, 0)

    -- Twist: full Command icon with a half-width, center-cropped Blood icon over
    -- its right half (the WA's 'twist 1/2' + 'twist 2/2' pair).
    frame.icon_twist = CreateFrame("Frame", addon_name .. "NextActionTwist", frame)
    frame.icon_twist:SetSize(45, 45)
    frame.icon_twist:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.icon_twist:SetFrameLevel(frame:GetFrameLevel() + 7)
    frame.icon_twist.left = create_wa_icon(frame.icon_twist, "TwistLeft", 45, 45,
        na.SOC_ID, { level = 1 })
    frame.icon_twist.left:SetPoint("CENTER", frame.icon_twist, "CENTER", 0, 0)
    frame.icon_twist.left:SetAlpha(1)
    frame.icon_twist.right = create_wa_icon(frame.icon_twist, "TwistRight", 22.5, 45,
        na.SOB_ID, { keep_aspect = true, level = 2 })
    frame.icon_twist.right:SetPoint("CENTER", frame.icon_twist, "CENTER", 11.25, 0)
    frame.icon_twist.right:SetAlpha(1)
    frame.icon_twist:SetAlpha(0)

    -- Judgement cue: small icon low-left over the action icon (WA: 22.5x24.9 at
    -- (-9,-10), 1px border, inverse cooldown swipe, Pixel glow while shown).
    frame.icon_judge = create_wa_icon(frame, "JudgeTime", 22.5, 24.9, na.JUDGEMENT_SPELL_ID,
        { cooldown = true, keep_aspect = true, border_size = 1, level = 9 })
    frame.icon_judge:SetPoint("CENTER", frame, "CENTER", -9, -10)

    -- HOLD / RIDE: dark translucent circle over the action icon with white text
    -- (the WA drew a near-black circle with Friz Quadrata 12 OUTLINE text).
    frame.hold = CreateFrame("Frame", addon_name .. "NextActionHold", frame)
    frame.hold:SetSize(HOLD_CIRCLE_SIZE, HOLD_CIRCLE_SIZE)
    frame.hold:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.hold:SetFrameLevel(frame:GetFrameLevel() + 11)
    frame.hold.circle = frame.hold:CreateTexture(nil, "ARTWORK")
    frame.hold.circle:SetAllPoints()
    if HOLD_CIRCLE_ASSET then
        frame.hold.circle:SetTexture(HOLD_CIRCLE_TEXTURE)
    else
        -- Plain white disc stand-in, tinted dark below.
        frame.hold.circle:SetColorTexture(1, 1, 1, 1)
    end
    frame.hold.circle:SetVertexColor(unpack(HOLD_CIRCLE_COLOR))
    frame.hold.text = frame.hold:CreateFontString(nil, "OVERLAY")
    frame.hold.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.hold.text:SetPoint("CENTER", frame.hold, "CENTER", 0, 0)
    frame.hold.text:SetTextColor(1, 1, 1, 1)
    frame.hold.text:SetText("HOLD")
    frame.hold:SetAlpha(0)

    -- Filler icons pop over everything in the same slot (WA: Consecration zoom 0.2,
    -- Exorcism zoom 0.15, white FILLER label).
    frame.filler_consec = create_wa_icon(frame, "FillerC", 45, 45, na.CONSECRATION_SPELL_ID,
        { zoom = 0.2, level = 13 })
    frame.filler_consec:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.filler_exo = create_wa_icon(frame, "FillerE", 45, 45, na.EXORCISM_SPELL_ID,
        { zoom = 0.15, level = 14 })
    frame.filler_exo:SetPoint("CENTER", frame, "CENTER", 0, 0)
    for _, filler in ipairs({ frame.filler_consec, frame.filler_exo }) do
        filler.label = filler:CreateFontString(nil, "OVERLAY")
        filler.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        filler.label:SetPoint("CENTER", filler, "CENTER", 0, 0)
        filler.label:SetTextColor(1, 1, 1, 1)
        filler.label:SetText("FILLER")
    end

    -- "Next action:" label above the icons (WA: Friz Quadrata 8 OUTLINE at (2,25)).
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    frame.label:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    frame.label:SetPoint("CENTER", frame, "CENTER", 2, 25)
    frame.label:SetTextColor(1, 1, 1, 1)
    frame.label:SetShadowColor(0, 0, 0, 1)
    frame.label:SetShadowOffset(1, -1)
    frame.label:SetText("Next action:")

    -- Rotation pattern text below the icons (WA: font "2002" size 12 OUTLINE,
    -- bottom-anchored 40px below center).
    frame.rotation_text = frame:CreateFontString(nil, "OVERLAY")
    frame.rotation_text:SetFont("Fonts\\2002.TTF", 12, "OUTLINE")
    frame.rotation_text:SetPoint("BOTTOM", frame, "CENTER", 0, -40)
    frame.rotation_text:SetTextColor(1, 1, 1, 1)
    frame.rotation_text:SetShadowColor(0, 0, 0, 1)
    frame.rotation_text:SetShadowOffset(1, -1)

    -- Fade bookkeeping: HOLD shows/hides instantly like the WA; the rest fade.
    frame.icon_cs.fade = register_fade(frame.icon_cs)
    frame.icon_command.fade = register_fade(frame.icon_command)
    frame.icon_blood.fade = register_fade(frame.icon_blood)
    frame.icon_twist.fade = register_fade(frame.icon_twist)
    frame.icon_judge.fade = register_fade(frame.icon_judge)
    frame.hold.fade = register_fade(frame.hold, true)
    frame.filler_consec.fade = register_fade(frame.filler_consec)
    frame.filler_exo.fade = register_fade(frame.filler_exo)

    -- The guide must also hide and fade while the swing bars are hidden (the
    -- bar-driven class hook stops when a bar is hidden), so the frame ticks itself
    -- as well. Fades step by clock delta, and the compute half is throttled, so
    -- being driven from two places cannot double-step anything.
    frame:SetScript("OnUpdate", function()
        ui.update(ST)
    end)

    frame:Hide()
    ui.apply_settings(self)
end

--=========================================================================================
-- Display state
--=========================================================================================
-- True when the guide may be shown: enabled, and either in combat or pinned always,
-- with a live swing to guide. This is deliberately NOT an st.is_mainline gate: the
-- Forever client is Mainline-code but must show the guide, and the Retail stand-in
-- never reports a swing start, so the swing state keeps it hidden there.
function ui.should_show(self)
    local db = self:get_class_table()
    if db.nextaction_enabled == false then
        return false
    end
    if db.nextaction_locked == false then
        -- Unlocked: keep the frame visible so it can be positioned (archive rule).
        return true
    end
    if db.nextaction_visibility_key ~= "always" and not self.in_combat then
        return false
    end
    local d = self.mainhand
    if not (d and d.speed and d.speed > 0 and d.ends_at and d.start and not d.is_full) then
        return false
    end
    return true
end

-- Applies a started-or-updated cooldown swipe once per cooldown, following the
-- codebase's cooldown_set flag pattern (archive rule). An upward jump in remaining
-- means a new cooldown started without an observed gap (e.g. a spell-queued recast).
local function set_icon_cooldown(icon, remaining, full_duration)
    remaining = remaining or 0
    if remaining > (icon.cooldown_prev or 0) + 0.1 then
        icon.cooldown_set = false
    end
    icon.cooldown_prev = remaining
    if remaining > 0 then
        if not icon.cooldown_set then
            icon.cooldown:SetCooldown(api.get_time() - (full_duration - remaining), full_duration)
            icon.cooldown_set = true
        end
    else
        if icon.cooldown_set then
            icon.cooldown:SetCooldown(0, 0)
            icon.cooldown_set = false
        end
    end
end

-- Seal swipe, same inverse swizzle and same "set once per cooldown" pattern as the
-- spell icons: expires is the seal aura's expirationTime, latched by the paladin module
-- in the same GetTime() domain as api.get_time(), so the remaining time is exact and
-- needs no per-frame state of its own. It is only ever non-zero while the aura is up (a
-- dropped seal clears the expiry, and the practice mirror supplies no expiry at all),
-- which is what keeps the swipe from appearing on a seal that is not there. full_duration
-- is the length LibClassicDurations reported for this aura (Era/TBC only) or nil, in
-- which case the archived vanilla/TBC constant applies — identical behaviour on every
-- family where the library does not load.
local function set_seal_icon_cooldown(icon, expires, full_duration)
    local remaining = 0
    if expires and expires > 0 then
        remaining = expires - api.get_time()
        if remaining < 0 then
            remaining = 0
        end
    end
    set_icon_cooldown(icon, remaining, full_duration or SEAL_DURATION)
end

-- Rotation text (the engine's pattern key resolved through its display names) and
-- the static "Next action:" label.
local function update_texts(self, na, inputs)
    local frame = ui.frame
    local db = self:get_class_table()
    local rotation_key
    if na.calculate_rotation then
        rotation_key = na.calculate_rotation(inputs.speed, inputs.G)
    end
    if db.nextaction_show_rotation_text ~= false and rotation_key then
        local display = na.display_names and na.display_names[rotation_key] or rotation_key
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

-- Active guidance: map the engine output onto the widgets (archive 896-926, minus
-- the design-mode preview branches).
local function display_active(self, inputs, out)
    local frame = ui.frame
    local db = self:get_class_table()
    local cs_target, command_target, blood_target, twist_target = 0, 0, 0, 0
    local judge_target, hold_target, consec_target, exo_target = 0, 0, 0, 0

    if out.riding then
        -- Riding the active Seal of Blood (blood auto): show the Blood icon with
        -- the RIDE overlay until it is safe to reseal Command.
        blood_target = 1
    elseif out.action == "cs" then
        cs_target = 1
    elseif out.action == "soc" then
        command_target = 1
    elseif out.action == "twist" then
        twist_target = 1
    else
        blood_target = 1
    end
    if out.hold and db.nextaction_hold_enabled ~= false then
        hold_target = 1
        frame.hold.text:SetText(out.riding and "RIDE" or "HOLD")
    end
    if out.filler_kind and db.nextaction_show_fillers ~= false then
        if out.filler_kind == "exorcism" then
            exo_target = 1
        else
            consec_target = 1
        end
    end
    -- The filler pops over the whole slot; suppress the judgement cue (and its
    -- glow, which would otherwise render through the filler icon) while it shows.
    if out.judge_call and db.nextaction_show_judgement ~= false
        and consec_target == 0 and exo_target == 0 then
        judge_target = 1
    end

    set_element_targets(frame, cs_target, command_target, blood_target, twist_target,
        judge_target, hold_target, consec_target, exo_target)

    -- Cooldown swipes on the CS, Judgement and seal icons (inverse, like the WA). The
    -- remaining times are the same latched reads the engine consumed this tick; the swipe
    -- lengths prefer what the client actually reported (inputs.cs_duration /
    -- inputs.judge_duration, latched by the paladin module) and fall back to the
    -- constants. The seal swipes are driven from the seal mirror rather than the engine's
    -- pick, so they are correct on whichever seal icon is the one on screen.
    local cs_remaining = inputs.cs_remaining or out.cs_remaining or 0
    local judge_remaining = inputs.judge_remaining or out.judge_remaining or 0
    set_icon_cooldown(frame.icon_cs, cs_target > 0 and cs_remaining or 0,
        inputs.cs_duration or CS_COOLDOWN)
    set_icon_cooldown(frame.icon_judge, judge_target > 0 and judge_remaining or 0,
        inputs.judge_duration or JUDGEMENT_COOLDOWN)
    set_seal_icon_cooldown(frame.icon_command, self.soc_expires, self.soc_duration)
    set_seal_icon_cooldown(frame.icon_blood, self.sob_expires, self.sob_duration)

    -- Pixel glow on the Judgement cue (WA subglow: Pixel, 8 lines, 0.25 frequency,
    -- length 10, thickness 1).
    if judge_target > 0 and not ui.judge_glowing then
        ui.judge_glowing = true
        LCG.PixelGlow_Start(frame.icon_judge, nil, 8, 0.25, 10, 1, 0, 0, false, "NextActionJudge")
    elseif judge_target == 0 and ui.judge_glowing then
        ui.judge_glowing = false
        LCG.PixelGlow_Stop(frame.icon_judge, "NextActionJudge")
    end

    update_texts(self, st.nextaction, inputs)
end

-- Idle: no active guidance (reachable only with the "always" visibility key). The
-- archive shows the Seal of Blood opener dimmed, with no swipes or glow.
local function display_idle(self, inputs)
    local frame = ui.frame
    set_element_targets(frame, 0, 0, 0.5, 0, 0, 0, 0, 0)
    set_icon_cooldown(frame.icon_cs, 0, CS_COOLDOWN)
    set_icon_cooldown(frame.icon_judge, 0, JUDGEMENT_COOLDOWN)
    -- Archive parity: the idle opener carries no swipes, so the seal swipes are cleared
    -- here too (out of combat the engine is not consulted at all).
    set_icon_cooldown(frame.icon_command, 0, SEAL_DURATION)
    set_icon_cooldown(frame.icon_blood, 0, SEAL_DURATION)
    if ui.judge_glowing then
        ui.judge_glowing = false
        LCG.PixelGlow_Stop(frame.icon_judge, "NextActionJudge")
    end
    update_texts(self, st.nextaction, inputs)
end

--=========================================================================================
-- Per-frame update (driven by the paladin class hook and by the frame's own OnUpdate)
--=========================================================================================
function ui.update(self)
    local frame = ui.frame
    if not frame then
        return
    end
    local now = api.get_time()
    local elapsed = now - (ui.last_tick or now)
    ui.last_tick = now

    -- Alpha fades run every call; the compute+display half ticks at UPDATE_INTERVAL.
    if frame:IsShown() then
        animate(elapsed)
    end
    if now - (ui.last_compute or 0) < UPDATE_INTERVAL then
        return
    end
    ui.last_compute = now

    if not ui.should_show(self) then
        if frame:IsShown() then
            frame:Hide()
        end
        if not self.in_combat then
            -- Combat-scoped guide state resets with the fight (on_combat_exit also
            -- covers the case where the guide is already hidden when combat ends).
            self.guide_melee_count = 0
            self.guide_waiting_judgement = false
        end
        return
    end
    if not frame:IsShown() then
        frame:Show()
    end

    local na = st.nextaction
    if not na then
        return
    end
    local inputs = self.PALADIN.gather_guide_inputs(self)
    if self.in_combat then
        -- Active guidance: one reused output table, no per-frame allocations.
        local out = ui.out
        if not out then
            out = {}
            ui.out = out
        end
        na.evaluate(inputs, out)
        -- The waiting-judgement state is a carry: this tick's output seeds the
        -- next tick's input.
        self.guide_waiting_judgement = out.waiting_judgement and true or false
        display_active(self, inputs, out)
    else
        -- Idle: a finished fight must not carry its swing count or judgement wait
        -- into the next one.
        self.guide_melee_count = 0
        self.guide_waiting_judgement = false
        display_idle(self, inputs)
    end
end

function ui.on_bar_update(self, hand)
    -- Driven from the paladin class hook for the mainhand bar (the archive drove the
    -- guide from the player module's per-frame update).
    if hand ~= "mainhand" then
        return
    end
    ui.update(self)
end

--=========================================================================================
-- Settings
--=========================================================================================
-- Re-reads settings and applies them to the live frame; used at init and by the
-- options panel (call with or without the addon instance).
function ui.apply_settings(self)
    self = self or ST
    local frame = ui.frame
    if not frame then
        return
    end
    local db = self:get_class_table()
    local enabled = db.nextaction_enabled ~= false
    local locked = db.nextaction_locked ~= false

    local scale = (db.nextaction_icon_size or BASE_ICON_SIZE) / BASE_ICON_SIZE
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        (db.nextaction_x or 0) / scale, (db.nextaction_y or -180) / scale)
    frame:SetMovable(not locked and enabled)
    frame:EnableMouse(not locked and enabled)

    frame:SetAlpha(1)
    if ui.should_show(self) then
        ui.update(self)
    elseif frame:IsShown() then
        frame:Hide()
    end
end

if st.debug then st.utils.print_msg('-- Parsed nextaction_ui.lua module correctly') end
