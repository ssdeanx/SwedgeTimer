--=========================================================================================
-- Next Action Guide display: the on-screen rotation prompt, generalised behind a
-- per-class provider so any class module can drive it (the paladin ships the first
-- provider: ST.PALADIN.guide in classes/paladin.lua).
-- Port of the archived build's nextaction.lua display half
-- (docs/swedge/SwedgeTimer_Forever/nextaction.lua 590-1011), minus practice mode and
-- edit mode. The decision engine lives in the pure st.nextaction module
-- (nextaction.lua); this file builds the frame from the provider's slot set, feeds it
-- the gathered inputs and maps the provider output onto the widgets.
-- The guide never gates on st.is_mainline (the Forever client is Mainline-code but must
-- show it); swing activity decides instead.
--
-- FROZEN PROVIDER CONTRACT - ST.<CLASS>.guide = { ... }:
--
--   slots = { { key = "cs", spell_id = 35395, cooldown_key = "cs" }, ... }
--     Ordered set of the displayable slots. `key` is the slot identity: out.action,
--     out.filler_slot and out.judge_slot name a slot by this key. `spell_id` supplies
--     the icon texture. `cooldown_key` (optional) names the slot's swipe source in the
--     gather inputs: inputs[cooldown_key .. "_remaining"] (seconds),
--     inputs[cooldown_key .. "_duration"] (full swipe length; falls back to the slot's
--     swipe_duration below) and inputs[cooldown_key .. "_expires"] (an absolute expiry
--     in the api.get_time() domain, preferred when present - the seal-aura shape).
--     The shipped paladin set has eight entries (the composite twist icon plus the
--     judgement cue and the three fillers); other classes are expected to stay at six
--     or fewer.
--
--   gather = function(self, out) ... return out end
--     Writes the live inputs into the caller-owned reused table (or into the module's
--     own reused table) and returns it. Inputs are the engine's frozen name set
--     (nextaction.lua header) plus the display-only fields the slots' cooldown_keys
--     name above. Must not allocate per call.
--
--   evaluate = function(inputs, out) ... return out end
--     Pure. Writes the frozen display fields into the caller-owned reused table and
--     returns it. The table is reused, so every field must be written on every tick:
--       out.action            slot key or nil - the action icon to show
--       out.hold              bool - show the HOLD/RIDE overlay
--       out.hold_text         string or nil - the overlay text; nil falls back to the
--                             labels below
--       out.filler_slot       slot key or nil - shown over the action icon
--       out.judge_slot        slot key or nil - shown low-left unless a filler shows
--       out.rotation_key      string or nil - the rotation pattern key painted this
--                             tick (rotation_key() below is the live text source)
--       out.waiting_judgement bool - judgement-cue carry (paladin; others may ignore)
--     out.riding (the engine's optional field) selects the ride label when
--     out.hold_text is nil. out.hard_wait (optional bool, strictSequence wait)
--     paints WAIT instead of HOLD/RIDE while true (nil/false = archived text).
--     out.stopattack (optional bool, twist-now or judge inside the window)
--     paints STOP instead and shows the overlay even without out.hold.
--     out.prepull_ready (optional bool, pull inside the lead with no seal)
--     paints PULL the same way. out.mana_low (optional bool, mana-governor
--     ride) paints OOM while true. Priority: STOP, then PULL, then OOM,
--     then WAIT. The out-of-combat prepull cue reads inputs, not out (the
--     engine only ticks in combat): inputs.time_to_pull_seconds against the
--     engine's PREPULL_SEAL_LEAD_SECONDS with inputs.seal == "none".
--
--   rotation_key = function(inputs) return key or nil end   -- optional
--     Live rotation-pattern key for the text below the icons. Absent -> the in-guide
--     rotation text is never shown.
--   rotation_names = { [key] = display_text, ... }          -- optional display map
--     Resolves a rotation key to its display text (default: the key itself).
--   labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" } -- optional
--     Static captions: next_action is the text above the icons; hold/ride supply the
--     overlay text when out.hold_text is nil; wait (optional, default "WAIT")
--     supplies it while out.hard_wait is true; stop (optional, default "STOP")
--     while out.stopattack is true; prepull (optional, default "PULL") while
--     out.prepull_ready is true (either path); mana (optional, default "OOM")
--     while out.mana_low is true.
--
-- OPTIONAL SLOT DISPLAY FIELDS - every default reproduces the archive's plain 45x45
-- centre icon; the paladin provider exercises each one:
--   name_suffix      frame-name suffix (default: the slot key)
--   size = {w, h}    icon size (default 45x45)
--   level            Z level within the guide group, relative to the group frame
--                    (default 1)
--   offset = {x, y}  centre offset from the group centre (default 0, 0)
--   zoom             texture crop (the WA's zoom, default none)
--   keep_aspect      centre-crop for non-square icons
--   border_size      border edge size (default 2)
--   overlay = { spell_id=..., name_suffix=..., size=..., offset=..., level=...,
--               zoom=..., keep_aspect=..., border_size=... }
--                    a second icon drawn over the first (the paladin twist
--                    composite); its `level` is relative to the slot's icon (default 1)
--   label            caption fontstring drawn centred over the icon (e.g. "FILLER")
--   swipe_always     drive the cooldown swipe even while the icon is faded out
--                    (default: only while the icon is shown)
--   swipe_duration   fallback full swipe length in seconds when the inputs give none
--   idle_alpha       out-of-combat idle alpha for the slot (default 0 = hidden)
--   glow             Pixel-glow the icon while it is shown (the paladin judge cue)
--   glow_key         glow pairing key (default: "NextAction" .. key)
--
-- NO provider -> the UI is inert: no frame is created, nothing ticks, nothing errors
-- and ui.should_show() is false. classes/paladin.lua's post_init drives ui.init(self)
-- and the options panel / design mode keep driving the live frame through the
-- nextaction_* db keys and ui.apply_settings.
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
local FADE_DURATION = 0.2    -- the WA's preset fade in/out time
local BASE_ICON_SIZE = 45    -- everything is authored at WA scale
local UPDATE_INTERVAL = 0.05 -- engine tick, matches the WA's aura poll cadence
-- Cooldown swipe lengths are slot data now (slot.swipe_duration): the paladin provider
-- carries the archive's fallbacks (CS 6 s, Judgement 8 s, seals 30 s) and the real
-- length the client reported rides in the gather inputs (<cooldown_key>_duration,
-- latched by classes/paladin.lua's get_guide_cooldown_remaining and by the seal mirror
-- for the LibClassicDurations tear-down on Era/TBC). A slot with neither falls back to
-- the remaining time itself, which degrades gracefully.
-- Crisp circle texture ported from the archive's Images/ (shipped as
-- Media/Textures/circle_smooth.tga). The plain-texture fallback below stays for
-- profiles where the asset is missing; a missing texture file never raises.
local HOLD_CIRCLE_ASSET = true
local HOLD_CIRCLE_TEXTURE = "Interface\\AddOns\\SwedgeTimer\\Media\\Textures\\circle_smooth.tga"
local HOLD_CIRCLE_COLOR = { 0.090, 0.067, 0.039, 0.45 }
local HOLD_CIRCLE_SIZE = 40

--=========================================================================================
-- Provider dispatch (the frozen contract is documented in the header)
--=========================================================================================
-- The class module's ST.<CLASS>.guide table, or nil. Read at init and on every tick;
-- the reader never allocates. A class without a guide table (or a module without the
-- two contract functions) leaves the whole UI inert: no frame ever exists.
function ui.get_provider(self)
    local class_module = self[self.player_class or ""]
    local guide = class_module and class_module.guide
    if type(guide) == "table" and type(guide.gather) == "function"
        and type(guide.evaluate) == "function" then
        return guide
    end
    return nil
end

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

-- One slot's icon from its descriptor (see the optional display fields in the header):
-- a plain centred icon by default, with an optional overlay icon (the twist composite)
-- and an optional caption fontstring (the filler icons).
local function build_slot_icon(frame, slot)
    local size = slot.size
    local width = (size and size[1]) or BASE_ICON_SIZE
    local height = (size and size[2]) or BASE_ICON_SIZE
    local icon = create_wa_icon(frame, slot.name_suffix or slot.key, width, height,
        slot.spell_id, {
            cooldown = slot.cooldown_key ~= nil,
            level = slot.level or 1,
            zoom = slot.zoom,
            keep_aspect = slot.keep_aspect,
            border_size = slot.border_size,
        })
    local offset = slot.offset
    icon:SetPoint("CENTER", frame, "CENTER", (offset and offset[1]) or 0,
        (offset and offset[2]) or 0)

    local overlay = slot.overlay
    if type(overlay) == "table" then
        local o_size = overlay.size
        local overlay_icon = create_wa_icon(icon,
            overlay.name_suffix or ((slot.name_suffix or slot.key) .. "Overlay"),
            (o_size and o_size[1]) or width, (o_size and o_size[2]) or height,
            overlay.spell_id, {
                level = overlay.level or 1,
                zoom = overlay.zoom,
                keep_aspect = overlay.keep_aspect,
                border_size = overlay.border_size,
            })
        local o_offset = overlay.offset
        overlay_icon:SetPoint("CENTER", icon, "CENTER", (o_offset and o_offset[1]) or 0,
            (o_offset and o_offset[2]) or 0)
        overlay_icon:SetAlpha(1)
        icon.overlay = overlay_icon
    end

    if slot.label then
        local caption = icon:CreateFontString(nil, "OVERLAY")
        -- The shared chain keeps the file that renders first and always leaves a
        -- font that exists (a FontString with no font throws "Font not set" on
        -- its first SetText).
        st.utils.apply_font(caption, "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        caption:SetPoint("CENTER", icon, "CENTER", 0, 0)
        caption:SetTextColor(1, 1, 1, 1)
        caption:SetText(slot.label)
    end
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

--=========================================================================================
-- Frame construction (archive geometry; practice and edit-mode couplings removed)
--=========================================================================================
function ui.init(self)
    if ui.frame then
        return
    end
    local provider = ui.get_provider(self)
    if not provider then
        -- No class provider on this flavor/class: nothing to display, never a tick.
        ui.inert = true
        return
    end
    -- Collect the keyed slots first: a provider with nothing usable stays inert
    -- without creating a single frame.
    local slots = {}
    local n = 0
    local raw_slots = provider.slots
    if type(raw_slots) == "table" then
        for i = 1, #raw_slots do
            local slot = raw_slots[i]
            if type(slot) == "table" and type(slot.key) == "string" and slot.key ~= "" then
                n = n + 1
                slots[n] = slot
            end
        end
    end
    if n == 0 then
        ui.inert = true
        return
    end
    ui.inert = false
    local db = self:get_class_table()

    local frame = CreateFrame("Frame", addon_name .. "NextActionFrame", UIParent)
    ui.frame = frame
    frame:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
    frame:SetPoint("CENTER", UIParent, "CENTER", db.nextaction_x or 127, db.nextaction_y or -65)
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

    -- One icon per slot, in provider order, all stacked on the frame's center like the
    -- WA group; only the one the provider targets is faded in at a time. The per-slot
    -- derived fields (cooldown field names, glow key) are built once here, so the
    -- per-frame path does no string work and allocates nothing.
    ui.icons = {}
    ui.slot_index = {}
    ui.targets = {}
    ui.inputs = ui.inputs or {}
    for i = 1, n do
        local slot = slots[i]
        local icon = build_slot_icon(frame, slot)
        local sf = {
            slot = slot,
            icon = icon,
            fade = register_fade(icon),
            glowing = false,
        }
        if slot.cooldown_key then
            sf.remaining_key = slot.cooldown_key .. "_remaining"
            sf.duration_key = slot.cooldown_key .. "_duration"
            sf.expires_key = slot.cooldown_key .. "_expires"
        end
        if slot.glow then
            sf.glow_key = slot.glow_key or ("NextAction" .. slot.key)
        end
        ui.icons[i] = sf
        ui.slot_index[slot.key] = i
        ui.targets[i] = 0
    end

    -- HOLD / RIDE: dark translucent circle over the action icon with white text
    -- (the WA drew a near-black circle with Friz Quadrata 12 OUTLINE text).
    -- The font goes through the shared chain: the file that renders stays first,
    -- and a client that does not ship it still gets a font that exists (a
    -- FontString with no font throws "Font not set" on its first SetText).
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
    st.utils.apply_font(frame.hold.text, "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.hold.text:SetPoint("CENTER", frame.hold, "CENTER", 0, 0)
    frame.hold.text:SetTextColor(1, 1, 1, 1)
    frame.hold.text:SetText((provider.labels and provider.labels.hold) or "HOLD")
    frame.hold:SetAlpha(0)
    frame.hold.fade = register_fade(frame.hold, true)

    -- "Next action:" label above the icons (WA: Friz Quadrata 8 OUTLINE at (2,25)).
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(frame.label, "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    frame.label:SetPoint("CENTER", frame, "CENTER", 2, 25)
    frame.label:SetTextColor(1, 1, 1, 1)
    frame.label:SetShadowColor(0, 0, 0, 1)
    frame.label:SetShadowOffset(1, -1)
    frame.label:SetText((provider.labels and provider.labels.next_action) or "Next action:")

    -- Rotation pattern text below the icons (WA: font "2002" size 12 OUTLINE,
    -- bottom-anchored 40px below center). The shared chain keeps the font that
    -- renders: "Fonts\2002.TTF" first, then STANDARD_TEXT_FONT, then the classic
    -- client font - a client that does not ship the "2002" file still gets one.
    frame.rotation_text = frame:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(frame.rotation_text, "Fonts\\2002.TTF", 12, "OUTLINE")
    frame.rotation_text:SetPoint("BOTTOM", frame, "CENTER", 0, -40)
    frame.rotation_text:SetTextColor(1, 1, 1, 1)
    frame.rotation_text:SetShadowColor(0, 0, 0, 1)
    frame.rotation_text:SetShadowOffset(1, -1)

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
-- One hand's swing state counts as live when the engine is reporting a real cycle
-- (a zero/absent speed or a full bar is a stopped or never-started hand).
local function has_live_swing(d)
    return d ~= nil and d.speed ~= nil and d.speed > 0
        and d.ends_at ~= nil and d.start ~= nil and d.is_full ~= true
end

-- True when the guide may be shown: a class provider exists, the guide is enabled, and
-- either in combat or pinned always, with a live swing to guide. This is deliberately
-- NOT an st.is_mainline gate: the Forever client is Mainline-code but must show the
-- guide, and the Retail stand-in never reports a swing start, so the swing state keeps
-- it hidden there.
function ui.should_show(self)
    if not ui.get_provider(self) then
        return false
    end
    local db = self:get_class_table()
    -- No class row means no guide settings: the guide stays hidden (the state a
    -- switched-off guide paints). This runs on the guide's own per-frame update.
    if type(db) ~= "table" then
        return false
    end
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
    -- A live swing on ANY hand keeps the guide up. The mainhand-only gate made the
    -- guide dead for ranged play: a hunter at range never starts a mainhand cycle,
    -- so the class that needs the prompt most never saw it. Melee classes still ride
    -- their mainhand; the ranged hand only ever ticks when that class actually swings.
    if has_live_swing(self.mainhand) or has_live_swing(self.ranged) then
        return true
    end
    return false
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

-- Seal swipe: the same inverse swipe and the same "set once per cooldown" pattern as the
-- spell icons. expires is the seal aura's expirationTime, latched by the paladin module
-- in the same GetTime() domain as api.get_time(), so the remaining time is exact and
-- needs no per-frame state of its own. It is only ever non-zero while the aura is up (a
-- dropped seal clears the expiry, and the practice mirror supplies no expiry at all),
-- which is what keeps the swipe from appearing on a seal that is not there. full_duration
-- is the length LibClassicDurations reported for this aura (Era/TBC only) or nil, in
-- which case the slot's own swipe_duration applies — identical behaviour on every
-- family where the library does not load.
local function set_seal_icon_cooldown(icon, expires, full_duration)
    local remaining = 0
    if expires and expires > 0 then
        remaining = expires - api.get_time()
        if remaining < 0 then
            remaining = 0
        end
    end
    set_icon_cooldown(icon, remaining, full_duration or 30)
end

-- Rotation text (the provider's pattern key resolved through its display map) and
-- the static "Next action:" label.
local function update_texts(self, provider, inputs)
    local frame = ui.frame
    local db = self:get_class_table()
    local rotation_key
    if provider.rotation_key then
        rotation_key = provider.rotation_key(inputs)
    end
    if db.nextaction_show_rotation_text ~= false and rotation_key then
        local names = provider.rotation_names
        local display = (names and names[rotation_key]) or rotation_key
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

-- Active guidance: map the provider output onto the widgets (archive 896-926, minus
-- the design-mode preview branches). out.action / out.filler_slot / out.judge_slot are
-- the provider's slot keys; each one maps to that slot's icon. out.inputs_unknown
-- (M6) suppresses every advice target and paints the label as "…": the provider has
-- told us its core timing reads are unusable, so showing an action would be a guess.
local function display_active(self, provider, inputs, out)
    local frame = ui.frame
    local db = self:get_class_table()
    local icons = ui.icons
    local targets = ui.targets
    for i = 1, #icons do
        targets[i] = 0
    end

    local unknown = out.inputs_unknown == true
    local action_index = not unknown and out.action and ui.slot_index[out.action]
    if action_index then
        targets[action_index] = 1
    end

    local filler_index
    if not unknown and out.filler_slot and db.nextaction_show_fillers ~= false then
        filler_index = ui.slot_index[out.filler_slot]
        if filler_index then
            targets[filler_index] = 1
        end
    end

    -- The filler pops over the whole slot; suppress the judgement cue (and its glow,
    -- which would otherwise render through the filler icon) while it shows.
    if not unknown and out.judge_slot and db.nextaction_show_judgement ~= false then
        local judge_index = ui.slot_index[out.judge_slot]
        if judge_index and not (filler_index and targets[filler_index] > 0) then
            targets[judge_index] = 1
        end
    end

    local hold_target = 0
    if not unknown and (out.hold or out.stopattack == true or out.prepull_ready == true)
        and db.nextaction_hold_enabled ~= false then
        hold_target = 1
        local text = out.hold_text
        if out.stopattack == true then
            -- StopAttack discipline (classic IsUsingJudgementStopAttack and
            -- SoD StopAttack/StartAttack twists/judges): the sim stops the
            -- attack before a twist-now or a judge inside the window, so the
            -- frame surfaces the advisory as STOP. Distinct text so the stop
            -- reads apart from HOLD/RIDE; nil-safe (== true),
            -- unknown-suppressed (the outer gate) and hold-gated like the
            -- overlay itself. No db key. The macro that acts on it stays
            -- filed (addons cannot cast); this only paints the output.
            local labels = provider.labels
            text = (labels and labels.stop) or "STOP"
        elseif out.prepull_ready == true then
            -- Prepull seal cue (classic APL -1.5 s): seal down, pull inside
            -- the lead. The combat path paints it here; the pull-timer
            -- source itself is filed (main lane), so this stays
            -- display-inert until it feeds inputs.time_to_pull_seconds.
            local labels = provider.labels
            text = (labels and labels.prepull) or "PULL"
        elseif out.mana_low == true then
            -- Mana-governor ride: mana sits below the threshold, so the
            -- guide withholds the reseal and rides instead. Distinct text
            -- carries the reason; the Blood icon underneath still shows the
            -- ride. Nil-safe, unknown-suppressed, hold-gated. No db key.
            local labels = provider.labels
            text = (labels and labels.mana) or "OOM"
        elseif out.hard_wait == true then
            -- strictSequence hard-wait (SoD twist APLs): a held twist on a
            -- strict build waits the swing out instead of filling. Distinct
            -- text so the wait reads apart from HOLD/RIDE; nil-safe (nil =
            -- the archived text below), unknown-suppressed (the outer gate)
            -- and hold-gated like the overlay itself. No db key.
            local labels = provider.labels
            text = (labels and labels.wait) or "WAIT"
        elseif text == nil then
            local labels = provider.labels
            if out.riding then
                text = (labels and labels.ride) or "RIDE"
            else
                text = (labels and labels.hold) or "HOLD"
            end
        end
        frame.hold.text:SetText(text)
    end

    for i = 1, #icons do
        set_fade_target(icons[i].fade, targets[i])
    end
    set_fade_target(frame.hold.fade, hold_target)

    -- Cooldown swipes on the slots that name a cooldown_key (inverse, like the WA):
    -- an expiry takes the seal-aura path (recomputed against the clock, exactly like
    -- the old seal swipe), otherwise the remaining/duration inputs drive it. A slot
    -- without swipe_always only swipes while its icon is faded in; the set-once latch
    -- lives in set_icon_cooldown.
    for i = 1, #icons do
        local sf = icons[i]
        if sf.remaining_key then
            local full = inputs[sf.duration_key] or sf.slot.swipe_duration
            local expires = inputs[sf.expires_key]
            if expires ~= nil then
                set_seal_icon_cooldown(sf.icon, expires, full)
            else
                local remaining = inputs[sf.remaining_key] or 0
                if targets[i] == 0 and not sf.slot.swipe_always then
                    remaining = 0
                end
                set_icon_cooldown(sf.icon, remaining, full)
            end
        end
    end

    -- Pixel glow on a glow slot while it shows (WA subglow: Pixel, 8 lines, 0.25
    -- frequency, length 10, thickness 1; the paladin judgement cue).
    for i = 1, #icons do
        local sf = icons[i]
        if sf.glow_key then
            local on = targets[i] > 0
            if on and not sf.glowing then
                sf.glowing = true
                LCG.PixelGlow_Start(sf.icon, nil, 8, 0.25, 10, 1, 0, 0, false, sf.glow_key)
            elseif not on and sf.glowing then
                sf.glowing = false
                LCG.PixelGlow_Stop(sf.icon, sf.glow_key)
            end
        end
    end

    update_texts(self, provider, inputs)

    -- M6: unknown inputs render the guide's one explicit "no advice" state: the
    -- rotation text goes away (its key would be thresholded off a defaulted speed)
    -- and the caption becomes "…". The latch keeps SetText off the per-frame path.
    if unknown then
        frame.rotation_text:Hide()
        if frame.label_unknown ~= true then
            frame.label_unknown = true
            frame.label:SetText("…")
        end
    elseif frame.label_unknown then
        frame.label_unknown = false
        frame.label:SetText((provider.labels and provider.labels.next_action) or "Next action:")
    end
end

-- Idle: no active guidance (reachable only with the "always" visibility key). The
-- archive shows the seal opener dimmed (the paladin slot declares idle_alpha 0.5),
-- with no swipes or glow.
local function display_idle(self, provider, inputs)
    local frame = ui.frame
    local icons = ui.icons
    local targets = ui.targets
    for i = 1, #icons do
        local sf = icons[i]
        targets[i] = sf.slot.idle_alpha or 0
        set_fade_target(sf.fade, targets[i])
    end
    -- Prepull seal cue (the live pre-combat render: the engine only ticks in
    -- combat, so the idle frame reads the pull-timer inputs directly against
    -- the engine's own lead constant, no duplicated seconds). Nil-safe (no
    -- timer = the archived idle below); no unknown gate (a prepull precedes
    -- the swing by nature); no db key. The pull-timer source itself is filed
    -- (main lane), as is the family-specific seal choice, so this stays
    -- display-inert until inputs.time_to_pull_seconds is fed.
    local ttp = inputs.time_to_pull_seconds
    local lead = (st.nextaction and st.nextaction.PREPULL_SEAL_LEAD_SECONDS) or 1.5
    local prepull = type(ttp) == "number" and ttp == ttp and ttp >= 0 and ttp <= lead
        and inputs.seal == "none"
    if prepull then
        local soc_index = ui.slot_index["soc"]
        if soc_index then
            targets[soc_index] = 1
            set_fade_target(icons[soc_index].fade, 1)
        end
        local labels = provider.labels
        frame.hold.text:SetText((labels and labels.prepull) or "PULL")
        set_fade_target(frame.hold.fade, 1)
    else
        set_fade_target(frame.hold.fade, 0)
    end
    -- Archive parity: the idle opener carries no swipes, so every slot swipe is
    -- cleared here too (out of combat the engine is not consulted at all).
    for i = 1, #icons do
        local sf = icons[i]
        if sf.remaining_key then
            set_icon_cooldown(sf.icon, 0, inputs[sf.duration_key] or sf.slot.swipe_duration)
        end
        if sf.glow_key and sf.glowing then
            sf.glowing = false
            LCG.PixelGlow_Stop(sf.icon, sf.glow_key)
        end
    end
    update_texts(self, provider, inputs)
end

--=========================================================================================
-- Compute isolation (N1): the self-driver (frame OnUpdate + class hook) must never freeze
-- on a throwing provider. The contract lives in guard.lua (one implementation for the
-- whole addon): first throw prints once, every throw counts in self.bar_hook_errors
-- (read by /st diag), the site quarantines after st.guard.QUARANTINE_THROWS.
-- Degrade is unknown, never stale-confident: gather failure flags inputs_unknown (the
-- engine threads it into out), evaluate failure flags out directly.
--
-- What stays here is this module's own wording ("Next action ...") and its own site
-- keys.
--=========================================================================================
st.guard.label("nextaction", "Next action")

--=========================================================================================
-- Per-frame update (driven by the class hook and by the frame's own OnUpdate)
--=========================================================================================
function ui.update(self)
    local frame = ui.frame
    if not frame then
        return
    end
    local provider = ui.get_provider(self)
    if not provider then
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

    -- The provider owns the reused inputs table; the UI owns the reused output table.
    -- A provider that returns a non-table (exception-path degrade) leaves last tick's
    -- table in place: that is stale state, so it is flagged unknown (M6) and the
    -- guide shows "…" instead of advice built on stale reads. A throwing provider is
    -- isolated the same way (N1): counted + one-time notice + quarantine, never stale.
    local inputs
    -- Isolated through the shared contract (guard.lua): a quarantined site is not
    -- called at all, a throwing provider costs only this tick's guidance.
    local gathered_ok, gathered = st.guard.run(self, "nextaction:gather",
        provider.gather, self, ui.inputs)
    if gathered_ok and type(gathered) == "table" then
        inputs = gathered
    else
        inputs = ui.inputs
        inputs.inputs_unknown = true
    end
    if self.in_combat then
        -- Active guidance: one reused output table, no per-frame allocations.
        local out = ui.out
        if not out then
            out = {}
            ui.out = out
        end
        local evaluate_ok = st.guard.run(self, "nextaction:evaluate",
            provider.evaluate, inputs, out)
        if not evaluate_ok then
            out.inputs_unknown = true
        end
        -- The waiting-judgement state is a carry: this tick's output seeds the
        -- next tick's input.
        self.guide_waiting_judgement = out.waiting_judgement and true or false
        display_active(self, provider, inputs, out)
    else
        -- Idle: a finished fight must not carry its swing count or judgement wait
        -- into the next one.
        self.guide_melee_count = 0
        self.guide_waiting_judgement = false
        display_idle(self, provider, inputs)
    end
end

function ui.on_bar_update(self, hand)
    -- Drive from whichever hand the class actually swings: melee classes fire on the
    -- mainhand tick, and the hunter at range only ever has a ranged cycle (its class
    -- hook forwards both hands). The update is rate-limited by UPDATE_INTERVAL, so
    -- the second hand costs a clock read on most frames.
    if hand ~= "mainhand" and hand ~= "ranged" then
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
    -- No class row: there is nothing to apply. Hide the live frame (the same
    -- fail-closed state as an unauthorised guide) and leave it built.
    if type(db) ~= "table" then
        if frame:IsShown() then
            frame:Hide()
        end
        return
    end
    local enabled = db.nextaction_enabled ~= false
    local locked = db.nextaction_locked ~= false

    local scale = (db.nextaction_icon_size or BASE_ICON_SIZE) / BASE_ICON_SIZE
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        (db.nextaction_x or 127) / scale, (db.nextaction_y or -65) / scale)
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
