--=========================================================================================
-- Rotation text: a free-standing label with the rotation pattern the class's rotation
-- source currently recommends ("2/3", "2/2/5", ...) - the same rotation the Next Action
-- Guide works from. Off by default; enable it in the settings, unlock it and drag it
-- anywhere. Classes without a rotation provider never show it.
--
-- Port of the archived build's rotationtext.lua (docs/swedge/SwedgeTimer_Forever/
-- rotationtext.lua; reference line numbers below are that file):
--   * practice-aware source        32-40
--   * format selection             42-58
--   * font / outline / colour      63-73
--   * frame construction           75-90
--   * visibility                   92-103
--   * alignment maths              105-147
--   * apply_settings               149-166
--   * render / throttled tick      168-203
--
-- FROZEN ROTATION-SOURCE CONTRACT: a class may expose
--   ST.<CLASS>.get_rotation_key(self) -> key | nil
-- returning a key of st.nextaction.sequences ("1/2", "2/3", "2/2/5", "2/4", "1/3",
-- "2/5_blood", "2/5_command", "2007") or nil when the class has no recommendation. The
-- paladin's provider is defined below (this module loads after main.lua, which creates
-- the class tables, and before classes/paladin.lua) and reuses the guide's own source,
-- so the label and the guide can never disagree. No provider => the module stays inert:
-- no frames are created and nothing ticks beyond the boot check.
--
-- Format keys, ported byte-for-byte from the archive (the "  -  " separator included):
--   key      -> "2/3"                     (display_names[key])
--   labelled -> "Rotation: 2/3"
--   steps    -> "CS, Twist, Twist"        (descriptions[key])
--   both     -> "2/3  -  CS, Twist, Twist"
-- A nil key renders as "" (still "visible": visibility is decided by the option gate);
-- an unknown key / unknown format value falls back to the key itself.
--
-- Deviations from the archive (all deliberate):
--   * No edit mode: "unlocked" (rotation_label_locked = false) is the positioning state,
--     the rule the rest of this codebase's frames use.
--   * The archive's ret_only spec gate is dropped (this addon has no ret-spec state -
--     the same deviation as hud.lua).
--   * No 0.35 disabled-preview tint: a disabled label is hidden.
--   * The label is created through this module's boot seam (RT.init / ensure_created)
--     because this port's change lane leaves the class post_init call sites untouched;
--     creation still waits for interfaces_are_initialised (post_init time) and defers
--     under combat lockdown, exactly like hud.lua.
--   * The driver frame is the one frame created at file load (it carries no visuals) and
--     is never hidden: the archive drove the tick from the label itself, whose OnUpdate
--     stops as soon as it hides - which is exactly the in_combat visibility transition.
--   * Settings changes are picked up by a HUD-style layout poll, so every option lands
--     without a per-option apply call.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LSM = LibStub("LibSharedMedia-3.0")

st.rotation_text = st.rotation_text or {}
local RT = st.rotation_text

--=========================================================================================
-- Constants
--=========================================================================================
local TICK = 0.1                        -- archive 16: update throttle (0.1 s)
local DEFAULT_X, DEFAULT_Y = 0, -150    -- archive 80 / core.lua 581-582
local DEFAULT_SCALE = 1
local COLOR_FALLBACK = { 255, 209, 0, 1 } -- archive {1.0, 0.82, 0.0, 1.0} in 0-255
local OUTLINE_MAP = { _none = "", outline = "OUTLINE", thick_outline = "THICKOUTLINE" }

-- The keys whose change re-applies the frame: position/scale/lock and every style key
-- (the alignment shift is applied in set_align, the format only changes the text). The
-- driver polls them like hud.lua's LAYOUT_KEYS, so the options need no apply calls.
local LAYOUT_KEYS = {
    "rotation_label_x", "rotation_label_y", "rotation_label_scale", "rotation_label_locked",
    "rotation_label_align", "rotation_label_format", "rotation_label_font",
    "rotation_label_size", "rotation_label_outline", "rotation_label_color",
}

RT.update_counter = 0

--=========================================================================================
-- PURE section (WoW-free): format selection, alignment maths and the per-tick gate.
-- Exercised directly by tests/rotationtext_state.lua.
--=========================================================================================

-- Format the rotation key (archive 42-58). `names`/`descs` are the source's
-- display_names / descriptions tables; a missing key or description degrades to the key
-- / the name. nil key renders as ""; any text ("" included) is drawn - visibility is
-- decided by should_show_state, not by the key's presence.
function RT.format_value(key, fmt, names, descs)
    if not key then
        return ""
    end
    names = names or {}
    descs = descs or {}
    local name = names[key] or key
    local desc = descs[key] or ""
    if fmt == "labelled" then
        return "Rotation: " .. name
    elseif fmt == "steps" then
        return desc ~= "" and desc or name
    elseif fmt == "both" then
        return desc ~= "" and (name .. "  -  " .. desc) or name
    end
    return name -- "key" (and any unknown format value): the display name alone
end

-- The label's anchor point for an alignment value (archive 108-112).
function RT.anchor_point_for(align)
    if align == "left" then
        return "LEFT"
    elseif align == "right" then
        return "RIGHT"
    end
    return "CENTER"
end

-- Alignment change without the label jumping (archive 127-147): the stored offset is
-- the offset of the anchor edge (LEFT/RIGHT) or centre from the screen centre; shifting
-- turns it into the offset of the new anchor edge. `x` and `w` are both in the stored
-- (screen-pixel) domain - callers pass the frame's on-screen width.
function RT.shift_align_offset(old_align, new_align, x, w)
    local old_point = RT.anchor_point_for(old_align)
    local new_point = RT.anchor_point_for(new_align)
    x = x or 0
    w = w or 0
    if old_point == new_point then
        return x
    end
    local centre = x
    if old_point == "LEFT" then
        centre = x + w / 2
    elseif old_point == "RIGHT" then
        centre = x - w / 2
    end
    if new_point == "LEFT" then
        return centre - w / 2
    elseif new_point == "RIGHT" then
        return centre + w / 2
    end
    return centre
end

-- Whether the label may show, from plain state fields (no db/API reads). Order mirrors
-- the archive's should_show (92-103) with this build's master switches (hud.lua's rule)
-- and the frozen contract's "no provider => hide":
--   has_provider    a class source exists (st.<CLASS>.get_rotation_key)
--   global_enabled  db.profile.enabled (addon master switch)
--   class_enabled   db.class_enabled (class switch)
--   label_enabled   db.rotation_label_enabled
--   locked          db.rotation_label_locked ~= false
--   in_combat / practice_active / visibility_key  as the names say
function RT.should_show_state(s)
    if not s.has_provider then
        return false
    end
    if s.global_enabled == false or s.class_enabled == false then
        return false
    end
    if s.label_enabled ~= true then
        return false
    end
    if s.locked == false then
        return true -- unlocked: keep it visible so it can be positioned (guide rule)
    end
    if s.practice_active then
        return true -- Practice Mode always shows it (archive rule)
    end
    if s.visibility_key == "in_combat" then
        return s.in_combat == true
    end
    return true
end

-- The per-tick gate + source read. `resolve_key` is invoked ONLY when the gate passes,
-- so a hidden (or disabled) label performs no source calls at all - pinned by
-- tests/rotationtext_state.lua's counting resolver. Returns (false, nil) to hide, or
-- (true, key) to draw the key's formatted text (nil key -> the empty text).
function RT.decide_update(s, resolve_key)
    if not RT.should_show_state(s) then
        return false, nil
    end
    local key = resolve_key and resolve_key() or nil
    return true, key
end

--=========================================================================================
-- Rotation source (archive 32-40) and the paladin provider
--=========================================================================================

-- The ACTIVE class module that implements the frozen provider contract, or nil.
-- C7 (class-isolation 2026-10-21): the module is the one main.lua activated
-- (ST.active_class), never the class being played - an explicit non-playing pick
-- owns its own rotation text. No active class => no provider => the label hides.
function RT.provider(self)
    local class_module = self[self.active_class or ""]
    if class_module and type(class_module.get_rotation_key) == "function" then
        return class_module
    end
    return nil
end

-- The provider's call, or nil when the class has none (the label would hide anyway).
function RT.current_rotation(self)
    local provider = RT.provider(self)
    if not provider then
        return nil
    end
    return provider.get_rotation_key(self)
end

-- The live resolver, bound through module state so decide_update can stay a pure
-- two-argument function without allocating a closure on every tick.
function RT.resolve_live()
    return RT.current_rotation(RT.live_self or ST)
end

-- The paladin provider is the PALADIN's own function and lives in
-- classes/paladin.lua (class-isolation 2026-10-21 C5): this shared module only
-- asks the ACTIVE class through RT.provider and treats "no get_rotation_key" as
-- "no rotation text" - never an error, never a guess.

--=========================================================================================
-- Live tick state (one reused table: no per-tick allocations)
--=========================================================================================
local state = {}

-- N3: source isolation. The driver polls the class get_rotation_key every tick; a
-- throwing source must hide the label, never freeze the driver. The contract lives in
-- guard.lua (one implementation for the whole addon): first throw prints once, every
-- throw counts in self.bar_hook_errors (read by /st diag), the site quarantines after
-- st.guard.QUARANTINE_THROWS. Degrade is hide, never stale.
--
-- What stays here is this module's own wording ("Rotation text ...") and its own site
-- key.
local ROTATION_ERROR_SITE = "rotationtext:get_rotation_key"

st.guard.label("rotationtext", "Rotation text")

local function fill_state(self)
    local db = self:get_class_table()
    state.has_provider = RT.provider(self) ~= nil
    state.global_enabled = self.db and self.db.profile and self.db.profile.enabled
    state.class_enabled = db.class_enabled
    state.label_enabled = db.rotation_label_enabled
    state.locked = db.rotation_label_locked ~= false
    state.in_combat = self.in_combat
    state.practice_active = st.practice_ui ~= nil and st.practice_ui.is_active() == true
    state.visibility_key = db.rotation_label_visibility_key
    state.format = db.rotation_label_format
    state.names = st.nextaction and st.nextaction.display_names
    state.descs = st.nextaction and st.nextaction.descriptions
    return state
end

function RT.should_show(self)
    return RT.should_show_state(fill_state(self or ST))
end

--=========================================================================================
-- Frame (archive 75-90; created only out of combat, after the addon's interfaces are up)
--=========================================================================================
local function apply_font(self, fs)
    local db = self:get_class_table()
    local path = LSM:Fetch("font", db.rotation_label_font)
    local outline = OUTLINE_MAP[db.rotation_label_outline] or "OUTLINE"
    local size = db.rotation_label_size or 16
    local ok = path and fs:SetFont(path, size, outline)
    if ok == false or not fs:GetFont() then
        fs:SetFont(STANDARD_TEXT_FONT, size, outline)
    end
    local color = db.rotation_label_color
    if type(color) ~= "table" then
        color = COLOR_FALLBACK
    end
    local r, g, b, a = self:convert_color(color)
    fs:SetTextColor(r, g, b, a or 1)
end

function RT.create(self)
    if RT.frame then
        return true
    end
    local frame = CreateFrame("Frame", addon_name .. "RotationTextFrame", UIParent)
    RT.frame = frame
    frame:SetSize(80, 24)
    frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        -- Repositioning is user-driven only, and never under lockdown.
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        if ST:get_class_table().rotation_label_locked ~= false then
            return
        end
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        RT.save_position(ST)
    end)
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetJustifyH("CENTER")
    frame.text:SetShadowColor(0, 0, 0, 1)
    frame.text:SetShadowOffset(1, -1)
    frame:Hide()
    RT.apply_settings(self)
    return true
end

-- Writes the text and fits the frame around it exactly (no side padding, so the anchor
-- edge IS the text edge - the archive's rule).
function RT.set_text(text)
    local frame = RT.frame
    if not frame then
        return
    end
    frame.text:SetText(text or "")
    local w = frame.text:GetStringWidth() or 40
    local h = (frame.text:GetStringHeight() or 16) + 4
    frame:SetSize(math.max(w, 10), math.max(h, 12))
end

-- Alignment without the label jumping (archive 127-147): the stored offset moves from
-- the old anchor point to the new one. `w` is the frame's on-screen width; the stored
-- offsets are screen pixels (the scale is divided out in apply_settings), so both are
-- converted through the frame's scale here.
function RT.set_align(align)
    local db = ST:get_class_table()
    local frame = RT.frame
    local old_align = db.rotation_label_align
    if frame and RT.anchor_point_for(old_align) ~= RT.anchor_point_for(align) then
        local w = (frame:GetWidth() or 0) * (frame:GetScale() or 1)
        db.rotation_label_x = RT.shift_align_offset(old_align, align, db.rotation_label_x, w)
    end
    db.rotation_label_align = align
    RT.dirty = true
    RT.apply_settings(ST)
end

--=========================================================================================
-- Settings (archive 149-166, plus hud.lua's layout poll and lockdown deferral)
--=========================================================================================
function RT.apply_settings(self)
    self = self or ST
    local frame = RT.frame
    if not frame then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        RT.pending_apply = true
        return
    end
    RT.pending_apply = false
    local db = self:get_class_table()
    local scale = db.rotation_label_scale or DEFAULT_SCALE
    if scale <= 0 then
        scale = DEFAULT_SCALE
    end
    local point = RT.anchor_point_for(db.rotation_label_align)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, "CENTER",
        (db.rotation_label_x or DEFAULT_X) / scale, (db.rotation_label_y or DEFAULT_Y) / scale)
    frame.text:ClearAllPoints()
    frame.text:SetPoint(point, frame, point, 0, 0)
    frame.text:SetJustifyH(point)
    apply_font(self, frame.text)
    local locked = db.rotation_label_locked ~= false
    local enabled = db.rotation_label_enabled ~= false
    frame:SetMovable(not locked and enabled)
    frame:EnableMouse(not locked and enabled)
    RT.refresh_layout_cache(self)
    RT.dirty = true
    if RT.should_show(self) then
        RT.update_display(self)
    elseif frame:IsShown() then
        frame:Hide()
    end
end

function RT.refresh_layout_cache(self)
    local db = (self or ST):get_class_table()
    local cache = RT.layout_cache
    if not cache then
        cache = {}
        RT.layout_cache = cache
    end
    for i = 1, #LAYOUT_KEYS do
        local key = LAYOUT_KEYS[i]
        cache[key] = db[key]
    end
end

function RT.layout_changed(self)
    local db = (self or ST):get_class_table()
    local cache = RT.layout_cache
    if not cache then
        return true
    end
    local changed = false
    for i = 1, #LAYOUT_KEYS do
        local key = LAYOUT_KEYS[i]
        local value = db[key]
        if cache[key] ~= value then
            cache[key] = value
            changed = true
        end
    end
    return changed
end

-- Positions are stored as the offset of the label's anchor edge/point from UIParent's
-- centre, in screen pixels (the frame's scale is converted through - the guide/HUD drag
-- maths, extended to the anchor edge for left/right alignment).
function RT.save_position(self)
    local frame = RT.frame
    if not frame then
        return
    end
    local db = (self or ST):get_class_table()
    local scale = frame:GetScale() or 1
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then
        return
    end
    local point = RT.anchor_point_for(db.rotation_label_align)
    local centre_x = cx * scale - ux
    local w = (frame:GetWidth() or 0) * scale
    local anchor_x = centre_x
    if point == "LEFT" then
        anchor_x = centre_x - w / 2
    elseif point == "RIGHT" then
        anchor_x = centre_x + w / 2
    end
    db.rotation_label_x = math.floor(anchor_x + 0.5)
    db.rotation_label_y = math.floor(cy * scale - uy + 0.5)
    RT.apply_settings(self)
end

--=========================================================================================
-- Render (archive 168-190, minus the edit-mode simulation branches)
--=========================================================================================
function RT.update_display(self)
    self = self or ST
    local frame = RT.frame
    if not frame then
        return
    end
    RT.live_self = self
    local s = fill_state(self)
    local visible, key
    -- Isolated through the shared contract (guard.lua): a quarantined source is not
    -- called at all, a throwing source hides the label - never a stale one.
    local ok, v, k = st.guard.run(self, ROTATION_ERROR_SITE, RT.decide_update, s, RT.resolve_live)
    if ok then
        visible, key = v, k
    else
        visible, key = false, nil
    end
    if not visible then
        if frame:IsShown() then
            frame:Hide()
        end
        return
    end
    if not frame:IsShown() then
        frame:Show()
    end
    -- Re-render only when the key or an applied setting changed: no string work on a
    -- tick whose displayed text is unchanged.
    if key ~= RT.current_key or RT.dirty then
        RT.current_key = key
        RT.dirty = false
        RT.set_text(RT.format_value(key, s.format, s.names, s.descs))
    end
end

--=========================================================================================
-- Throttled tick (archive 192-203), driven by the module's own driver frame
--=========================================================================================
function RT.on_update(self, elapsed)
    self = self or ST
    if RT.inert or not self.db then
        return
    end
    -- Per-frame entry: the layout poll and apply_settings below read the class
    -- row. No row means no label settings, so a live label hides (the state a
    -- switched-off label paints) instead of throwing out of the driver tick.
    local class_db = self.get_class_table and self:get_class_table() or nil
    if type(class_db) ~= "table" then
        if RT.frame and RT.frame:IsShown() then
            RT.frame:Hide()
        end
        return
    end
    RT.update_counter = RT.update_counter + (elapsed or 0.016)
    if RT.update_counter < TICK then
        return
    end
    RT.update_counter = 0
    if RT.pending_apply and not (InCombatLockdown and InCombatLockdown()) then
        RT.apply_settings(self)
        return
    end
    if not RT.frame then
        -- Boot retry: the label appears once post_init has run (see the header) on a
        -- class with a rotation provider; a provider-less class goes inert here.
        RT.ensure_created(self)
        return
    end
    if RT.layout_changed(self) then
        RT.apply_settings(self)
        return
    end
    RT.update_display(self)
end

--=========================================================================================
-- Boot seam (hud.lua's deferral contract, self-driven because this lane's TOCs have no
-- post_init call site to add)
--=========================================================================================
-- The canonical creation entry, matching the other UI modules (hud.lua / practice_ui.lua
-- expose init(self) for a class module's post_init). Both this and the driver tick land
-- in ensure_created.
function RT.init(self)
    self = self or ST
    return RT.ensure_created(self)
end

function RT.ensure_created(self)
    self = self or ST
    if RT.frame then
        return true
    end
    if RT.inert then
        return false
    end
    if not self.interfaces_are_initialised then
        return false
    end
    if not RT.provider(self) then
        -- No provider on this class: a silent no-op (no frame, nothing ticking).
        RT.inert = true
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Frames are never created in combat; the driver retries once lockdown lifts.
        RT.pending_create = true
        return false
    end
    RT.pending_create = false
    return RT.create(self)
end

-- The module's driver frame: the one frame created at file load (addon files only load
-- out of combat). It carries no visuals; every visual is created through ensure_created,
-- which checks combat lockdown. It is never hidden because a hidden frame receives no
-- OnUpdate, and the in_combat visibility key needs exactly that transition.
RT.driver = CreateFrame("Frame", addon_name .. "RotationTextDriverFrame", UIParent)
RT.driver:SetScript("OnUpdate", function(_, elapsed)
    RT.on_update(ST, elapsed)
end)

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed rotationtext.lua module correctly') end
