--=========================================================================================
-- Cooldown HUD: a row of ability icons with cooldown swipes, remaining-time text,
-- desaturate / mana / range cues and a proc glow.
--
-- Ported from the archived build's hud.lua (docs/swedge/SwedgeTimer_Forever/hud.lua,
-- byte-identical to the *_TBC copy; reference line numbers below are that file):
--   * slot set and spell ids        28-49
--   * ability cooldown readers      74-99   (re-pointed at the class provider, see below)
--   * the running GCD               101-107 (now the class provider's input)
--   * no-mana / out-of-range reads  114-138 (now the class provider's input)
--   * trinket tracker               143-184 + state machine 459-485
--   * frame construction            189-260
--   * visibility                    265-289
--   * layout and style              294-363
--   * paint (state -> visuals)      368-415
--   * ability state                 418-453
--   * design-mode sample            487-523
--   * per-frame update              550-568
--
-- The archive scoped the HUD to the paladin: the slot list, the cooldown readers and
-- the special cases (seal-less Judgement, Undead/Demon Exorcism, ready Avenging Wrath)
-- all lived in hud.lua. This port GENERALISES the slot set so any class can plug in:
--
--   ST.<CLASS>.HUD_SLOTS = { <slot descriptor>, ... }
--   ST.<CLASS>.get_hud_state(self, slot, now) -> <state table>
--
-- The HUD renders whatever descriptors exist; the paladin's slots and provider live in
-- classes/paladin.lua. A class without HUD_SLOTS - or without a provider for its
-- "spell" slots - gets a silent no-op: nothing is created and nothing ticks.
--
-- FROZEN SLOT DESCRIPTOR CONTRACT (read once, at HUD creation; other class modules
-- implement this later):
--   key             unique settings suffix; the per-slot toggle is hud_show_<key>
--   title           display label (options text)
--   kind            "spell" (default) | "trinket"
--   spell           spell id whose icon the slot shows (spell kind)
--   cooldown_spell  optional id/name override for the provider's cooldown reads
--                   (reserved: the HUD never reads it itself)
--   texture         optional explicit texture override (beats the spell icon)
--   inv_slot        13 | 14 - the inventory slot for "trinket" kind
--
-- FROZEN PROVIDER CONTRACT - ST.<CLASS>.get_hud_state(self, slot, now) -> state:
--   Called at most once per HUD tick (0.05 s) per wanted, enabled slot. `now` is the
--   tick's api.get_time() reading (optional for the provider: it may call api.get_time()
--   itself). The provider MAY reuse one table per class - the HUD reads it immediately
--   and never keeps a reference. "trinket" slots are served by the HUD's own tracker
--   and need no provider entry.
--   state fields (all optional; nil means "not reported"):
--     remaining       seconds left of the cooldown / proc (0 = not running)
--     duration        full length of that cooldown / proc (0 or nil = no swipe)
--     start           swipe anchor in the api.get_time() domain; defaults to
--                     now - (duration - remaining)
--     reverse         true = reversed swipe (a proc's internal cooldown counts up)
--     text_remaining  countdown text override (defaults to remaining); swipes shorter
--                     than 2 s (the GCD) never show text
--     desaturate      true = grey the icon
--     usable          false = tint blue (no mana / insufficient resources)
--     in_range        false = tint red (target out of the ability's range)
--     glow            true = proc glow while hud_glow_enabled
--     count           reserved stack count (accepted, not painted yet)
--     texture         per-tick icon override (trinkets swap their texture with the item)
--     hidden          true = draw nothing for this slot this tick
--   The class modules also call st.hud.init(self) from post_init and may call
--   st.hud.on_bar_update(self, hand) from their per-frame class hook (it retries a
--   creation deferred by combat lockdown; the row itself ticks on its own driver).
--
-- Deviations from the archive (all deliberate):
--   * There is no edit mode here: "unlocked" (hud_locked = false) is the design mode -
--     the row stays visible for dragging and shows the archive's looping sample states.
--     The archive's 0.35 alpha tint of a disabled preview is dropped: a disabled HUD is
--     hidden (the next action guide's rule in this codebase).
--   * The archive's ret_only spec gate is dropped (this addon has no ret-spec state).
--   * The vendored LibCustomGlow (v16) has no ProcGlow; the glow uses PixelGlow with
--     the codebase's standard parameters (the guide's judgement glow).
--   * The trinket proc scan reads api.UnitAura (compat's cross-client normalised
--     reader) instead of the raw UnitBuff the archive used.
--   * CLEU trinket-ICD tracking is best-effort and strictly optional: where the event
--     cannot be registered or CombatLogGetCurrentEventInfo is missing, the trinket still
--     shows its on-use cooldown and proc buff - only the reversed ICD swipe is lost.
--   * The archive's swap-in of the running GCD, mana tint and range tint now happens in
--     the class provider (so this module stays class-agnostic); their state -> visual
--     mapping (the 2 s GCD text rule included) is unchanged and still lives here.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LSM = LibStub("LibSharedMedia-3.0")
local LCG = LibStub("LibCustomGlow-1.0")
-- Cross-client API wrappers (see compat.lua).
local api = st.api

st.hud = st.hud or {}
local HUD = st.hud

--=========================================================================================
-- Constants
--=========================================================================================
local TICK = 0.05                 -- archive 36: per-frame update throttle (0.05 s)
local WARN_SECONDS = 3            -- archive 37: red text under this many seconds
local GCD_TEXT_HIDE = 2           -- archive 38: swipes shorter than this show no text
local AURA_SCAN_LIMIT = 40        -- archive 164: buff scan cap
local DEFAULT_ICON_SIZE = 36      -- archive 237
local DEFAULT_X, DEFAULT_Y = 0, -236
local DEFAULT_SPACING = 2
local DEFAULT_SCALE = 1
local GLOW_KEY = "SwedgeTimerHud"
local GLOW_LINES = 8              -- same parameters as the guide's judgement glow
local GLOW_FREQUENCY = 0.25
local GLOW_LENGTH = 10
local GLOW_THICKNESS = 1
local TRINKET_SLOTS = { 13, 14 }
-- The WA's empty-slot icons (archive 35).
local TRINKET_FALLBACK_ICON = { [13] = 133450, [14] = 133448 }
local COLOR_NO_MANA = { 0.50, 0.50, 1.00 }        -- archive 56
local COLOR_OUT_OF_RANGE = { 1.00, 0.25, 0.25 }   -- archive 57
local COLOR_WHITE = { 1, 1, 1 }                   -- archive 58
-- Text colours are stored 0-255 (the codebase's class-colour convention, so the
-- standard color_getter / color_setter options work); these are the archive defaults
-- (archive 567-568) converted up.
local TEXT_COLOR_FALLBACK = { 250, 255, 0, 1 }
local TEXT_WARN_COLOR_FALLBACK = { 255, 102, 107, 1 }
local BORDER_COLOR_FALLBACK = { 0, 0, 0, 1 }
local OUTLINE_MAP = { _none = "", outline = "OUTLINE", thick_outline = "THICKOUTLINE" }

-- Class-provided slot geometry keys re-applied when any of them changes.
local LAYOUT_KEYS = {
    "hud_x", "hud_y", "hud_scale", "hud_icon_size", "hud_match_bar_width",
    "hud_spacing", "hud_orientation", "hud_border_size", "hud_border_color",
    "hud_font", "hud_text_size", "hud_text_outline", "hud_locked",
}

-- Optional client global, captured at load (the compat.lua pattern: rawget keeps
-- undefined-global reads annotation-safe). It degrades silently when absent - the HUD
-- must work without it. The inventory and combat-log reads go through compat's api.*
-- wrappers (the cross-client contract), never through raw client globals here.
local unit_guid = rawget(_G, "UnitGUID")

-- Trinket item id -> proc buff spell id (and internal cooldown seconds where the item
-- has one). Ported from the archive's st_data.lua trinket tables (128-199, the WA's
-- own data). NEEDS IN-CLIENT CONFIRMATION: the item ids, buff ids and ICD lengths
-- were assembled for the TBC/Forever clients and have not been verified against a
-- live combat log on every supported family here. Every `icd` value below is
-- UNCONFIRMED (competitor S1: the Anniversary trackers prove the demand, and the
-- Quagmire caveat shows Anniversary drift) - never invent a length; an item with
-- no confirmed length ships with no `icd` and loses only the reversed swipe.
local TRINKET_DATA = {
    [28830] = { buff = 34775, icd = 20 },   -- Dragonspine Trophy
    [29383] = { buff = 35166 },             -- Bloodlust Brooch
    [19343] = { buff = 23733 },             -- Scrolls of Blinding Light
    [23570] = { buff = 29602 },             -- Jom Gabbar
    [38290] = { buff = 51953 },             -- Dark Iron Smoking Pipe
    [38289] = { buff = 51952 },             -- Coren's Lucky Coin
    [38288] = { buff = 51954 },             -- Direbrew Hops
    [38287] = { buff = 51955 },             -- Empty Mug of Direbrew
    [29387] = { buff = 35169 },             -- Gnomeregan Auto-Blocker 600
    [29376] = { buff = 35165 },             -- Essence of the Martyr
    [28789] = { buff = 34747 },             -- Eye of Magtheridon
    [29370] = { buff = 35163 },             -- Icon of the Silver Crescent
    [28034] = { buff = 33649, icd = 50 },   -- Hourglass of the Unraveller
    [27891] = { buff = 33479 },             -- Adamantine Figurine
    [34473] = { buff = 45058, icd = 30 },   -- Commendation of Kael'thas
    [34472] = { buff = 45053, icd = 45 },   -- Shard of Contempt
    [32534] = { buff = 40538 },             -- Brooch of the Immortal King
    [30841] = { buff = 37879 },             -- Lower City Prayerbook
    [28727] = { buff = 29601 },             -- Pendant of the Violet Eye
    [28288] = { buff = 33807 },             -- Abacus of Violent Odds
    [28590] = { buff = 38332 },             -- Ribbon of Sacrifice
    [28528] = { buff = 34519 },             -- Moroes' Lucky Pocket Watch
    [28418] = { buff = 34321, icd = 45 },   -- Shiffar's Nexus-Horn
    [28370] = { buff = 34210, icd = 50 },   -- Bangle of Endless Blessings
    [28190] = { buff = 33370, icd = 45 },   -- Scarab of the Infinite Cycle
    [27683] = { buff = 33370, icd = 45 },   -- Quagmirran's Eye
    [35702] = { buff = 46784 },             -- Figurine - Shadowsong Panther
    [35700] = { buff = 46783 },             -- Figurine - Crimson Serpent
    [35693] = { buff = 46780 },             -- Figurine - Empyrean Tortoise
    [30627] = { buff = 42084, icd = 45 },   -- Tsunami Talisman
    [30626] = { buff = 38348, icd = 45 },   -- Sextant of Unstable Currents
    [33831] = { buff = 43716 },             -- Berserker's Call
    [33829] = { buff = 43712 },             -- Hex Shrunken Head
    [33828] = { buff = 43710 },             -- Tome of Diabolic Remedy
    [32505] = { buff = 40477 },             -- Madness of the Betrayer
    [32501] = { buff = 40464 },             -- Shadowmoon Insignia
    [32496] = { buff = 37656, icd = 50 },   -- Memento of Tyrande
    [32483] = { buff = 40396 },             -- The Skull of Gul'dan
    [34427] = { buff = 45040, icd = 45 },   -- Blackened Naaru Sliver
    [32486] = { buff = 40452, icd = 10 },   -- Ashtongue Talisman of Equilibrium
    [30450] = { buff = 37174, icd = 30 },   -- Warp-Spring Coil
    [30447] = { buff = 37198, icd = 45 },   -- Tome of Fiery Redemption
    [30663] = { buff = 37243, icd = 40 },   -- Fathom-Brooch of the Tidewalker
    [30619] = { buff = 38324, icd = 15 },   -- Fel Reaver's Piston
    [34470] = { buff = 45055, icd = 15 },   -- Timbal's Focusing Crystal
    [32770] = { buff = 41261, icd = 10 },   -- Skyguard Silver Cross
    [32771] = { buff = 41263, icd = 10 },   -- Airman's Ribbon of Gallantry
}

--=========================================================================================
-- Module state
--=========================================================================================
HUD.frame = HUD.frame or nil
HUD.icons = HUD.icons or {}
HUD.trinkets = HUD.trinkets or { [13] = {}, [14] = {} }
HUD.update_counter = 0
-- M1: CLEU registration failures are counted for /st diag plus a one-time chat.
-- The wiring that prints them (main.lua print_runtime_diag, diag.lua) is filed -
-- main.lua + diag.lua are out of scope for this lane - so the counter lives here.
HUD.cleu_register_errors = HUD.cleu_register_errors or 0
HUD.cleu_register_notified = HUD.cleu_register_notified or false

-- N2: per-icon isolation. The driver polls one provider per wanted icon; a throwing
-- slot must cost only its own icon, never the rest of the row. The contract lives in
-- guard.lua (one implementation for the whole addon): first throw prints once, every
-- throw counts in self.bar_hook_errors (read by /st diag), the site quarantines after
-- st.guard.QUARANTINE_THROWS. Degrade is hide, never stale.
--
-- What stays here is this module's own wording ("HUD ...") and its own site keys.
st.guard.label("hud", "HUD")
local HUD_HIDDEN_STATE = { hidden = true }

-- Provider call shape kept explicit for the wiring_check dispatcher
-- (`mod.get_hud_state(` is the dynamic call site); the shared guard (st.guard.run)
-- wraps this helper.
local function call_hud_provider(mod, self, slot, now)
    return mod.get_hud_state(self, slot, now)
end

local TRINKET_STATE = {}   -- one reused state table for the trinket machine
local PREVIEW_STATE = {}   -- one reused state table for the design-mode sample

--=========================================================================================
-- Small helpers
--=========================================================================================
-- The icon texture for a spell id through compat's GetSpellInfo (both the classic
-- icon-path and the Mainline icon-id shapes), nil when unresolved.
local function spell_icon(spell_id)
    if not spell_id then
        return nil
    end
    return select(3, api.GetSpellInfo(spell_id))
end

-- The db value when it looks like a colour table, else the fallback: the visuals must
-- survive a malformed profile.
local function color_or(db_value, fallback)
    if type(db_value) == "table" then
        return db_value
    end
    return fallback
end

--=========================================================================================
-- Contract validation (pure; used at creation)
--=========================================================================================
-- True when the HUD can render `slot`: a table with a non-empty key, a known kind, an
-- icon source and - for "spell" kind - a class provider to fill its state.
function HUD.validate_slot(slot, has_provider)
    if type(slot) ~= "table" then
        return false
    end
    if type(slot.key) ~= "string" or slot.key == "" then
        return false
    end
    local kind = slot.kind or "spell"
    if kind == "spell" then
        if not has_provider then
            return false
        end
        return slot.spell ~= nil or slot.texture ~= nil
    elseif kind == "trinket" then
        return slot.inv_slot == 13 or slot.inv_slot == 14
    end
    return false
end

--=========================================================================================
-- Trinket tracker (archive 143-184)
--=========================================================================================
function HUD.read_trinket(inv_slot)
    local t = HUD.trinkets[inv_slot]
    if not t then
        return
    end
    local item = api.GetInventoryItemID(inv_slot)
    if item ~= t.item then
        t.item = item
        local data = item and TRINKET_DATA[item] or nil
        t.buff = data and data.buff or nil
        t.icd = data and data.icd or nil
        t.texture = api.GetInventoryItemTexture(inv_slot) or TRINKET_FALLBACK_ICON[inv_slot]
        t.icd_expires = nil
        t.proc_expires, t.proc_duration = nil, nil
    end
end

function HUD.read_trinkets()
    for i = 1, #TRINKET_SLOTS do
        HUD.read_trinket(TRINKET_SLOTS[i])
    end
end

-- The proc buff's remaining time, from the player's auras (by spell id).
-- No early break (compat R2): nil is simply no match at this index, so a
-- restricted row above the buff never hides the proc; the 40-row cap bounds
-- the walk. J1 (hunter-proctor-fixes): nil-guard + cap is the contract.
local function scan_trinket_proc(t)
    t.proc_expires, t.proc_duration = nil, nil
    if not t.buff then
        return
    end
    for i = 1, AURA_SCAN_LIMIT do
        local name, _, _, _, duration, expires, _, _, _, spell_id = api.UnitAura("player", i, "HELPFUL")
        if name ~= nil then
            if spell_id == t.buff then
                t.proc_expires, t.proc_duration = expires, duration
                return
            end
        end
    end
end

-- Usable-only gate (operator order): a trinket shows only when it has a usable
-- effect. A known proc (TRINKET_DATA buff) or a live proc/ICD stamp is usable;
-- otherwise the slot probes the live item cooldown: an on-use trinket reports
-- enabled even while ready, a passive stat stick reports disabled. Unknown =
-- hide (never guess). Nil-safe: a missing cooldown reader reports disabled.
local function trinket_has_on_use(inv_slot)
    if type(api.GetInventoryItemCooldown) ~= "function" then
        return false
    end
    local _, _, use_enable = api.GetInventoryItemCooldown(inv_slot)
    return use_enable == 1 or use_enable == true
end

-- True when the tracked trinket is usable: a known proc buff, a live proc/ICD
-- stamp, or a live on-use flag. Empty slots (no item) are never usable. The
-- optional use_enable reuses the tick's cooldown read so trinket_state makes
-- one live call per tick; icon_should_show probes on its own (layout only).
function HUD.trinket_usable(t, inv_slot, use_enable)
    if type(t) ~= "table" or t.item == nil then
        return false
    end
    if t.buff ~= nil then
        return true
    end
    if t.proc_expires ~= nil or t.icd_expires ~= nil then
        return true
    end
    if use_enable == nil then
        return trinket_has_on_use(inv_slot)
    end
    return use_enable == 1 or use_enable == true
end

-- CLEU: the proc landing starts the trinket's internal cooldown (archive 174-184).
-- Strictly optional: see the header.
function HUD.on_aura_applied(self, dest_guid, spell_id, now)
    local me = self.player_guid or (unit_guid and unit_guid("player"))
    if me == nil or dest_guid ~= me then
        return
    end
    now = now or api.get_time()
    for i = 1, #TRINKET_SLOTS do
        local t = HUD.trinkets[TRINKET_SLOTS[i]]
        if t and t.buff and spell_id == t.buff and t.icd then
            t.icd_expires = now + t.icd
        end
    end
end

-- One CLEU payload, unpacked exactly like the archive (line 248): SPELL_AURA_APPLIED
-- carries the destination guid 8th and the spell id 12th.
function HUD.on_combat_log_event(self)
    local _, subevent, _, _, _, _, _, dest_guid, _, _, _, spell_id = api.CombatLogGetCurrentEventInfo()
    if subevent == "SPELL_AURA_APPLIED" then
        HUD.on_aura_applied(self, dest_guid, spell_id)
    end
end

-- Trinket icon state (archive 459-485): on-use cooldown > proc buff > internal
-- cooldown > idle. An on-use trinket starts its cooldown the moment it is pressed, so
-- that is what its icon counts; a proc trinket shows its buff while up, then its
-- internal cooldown as a reversed swipe. The state table is reused (no allocation).
function HUD.trinket_state(self, slot, now)
    local s = TRINKET_STATE
    s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
    s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
    s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
    local t = HUD.trinkets[slot.inv_slot]
    if not t then
        return nil
    end
    s.texture = t.texture
    scan_trinket_proc(t)
    local use_start, use_duration, use_enable = api.GetInventoryItemCooldown(slot.inv_slot)
    if not HUD.trinket_usable(t, slot.inv_slot, use_enable) then
        s.hidden = true
        return s
    end
    local on_use_cd = (use_enable == 1 or use_enable == true)
        and (use_duration or 0) > 1.5
        and ((use_start or 0) + (use_duration or 0)) > now
    if on_use_cd then
        s.start, s.duration = use_start, use_duration
        s.remaining = use_start + use_duration - now
        s.text_remaining = s.remaining
        s.desaturate = true
    elseif t.proc_expires and t.proc_expires > now then
        s.duration = t.proc_duration or 0
        s.start = t.proc_expires - s.duration
        s.remaining = t.proc_expires - now
        s.text_remaining = s.remaining
    elseif t.icd_expires and t.icd_expires > now then
        s.duration = t.icd
        s.start = t.icd_expires - t.icd
        s.remaining = t.icd_expires - now
        s.text_remaining = s.remaining
        s.reverse = true
    elseif t.icd_expires and t.icd_expires <= now then
        t.icd_expires = nil
    end
    -- No self is read on this path (the tracker is module state); kept in the signature
    -- for the provider-shaped call site that renders it.
    return s
end

--=========================================================================================
-- Frame construction (archive 189-260; called once, out of combat)
--=========================================================================================
-- SoD-safe fallback chain (never throws): LSM font -> STANDARD_TEXT_FONT ->
-- the classic client font. Every SetFont runs pcall-guarded: a missing font
-- degrades to the next fallback, never out of the HUD build.
local FONT_FALLBACK_PATH = "Fonts\\FRIZQT__.TTF"
local function apply_font(text, db)
    if type(text) ~= "table" or type(text.SetFont) ~= "function" then
        return
    end
    if type(db) ~= "table" then
        db = {}
    end
    local outline = OUTLINE_MAP[db.hud_text_outline] or "OUTLINE"
    local size = db.hud_text_size or 16
    local std = rawget(_G, "STANDARD_TEXT_FONT") or FONT_FALLBACK_PATH
    local path
    if type(LSM) == "table" and type(LSM.Fetch) == "function" and type(db.hud_font) == "string" then
        local ok_fetch, fetched = pcall(LSM.Fetch, LSM, "font", db.hud_font)
        if ok_fetch then
            path = fetched
        end
    end
    local ok
    if path then
        local ok_set, res = pcall(text.SetFont, text, path, size, outline)
        if ok_set then
            ok = res
        end
    end
    local has_font = false
    if type(text.GetFont) == "function" then
        local ok_get, got = pcall(text.GetFont, text)
        if ok_get then
            has_font = got ~= nil
        end
    end
    if ok == false or not has_font then
        pcall(text.SetFont, text, std, size, outline)
    end
end

local function create_icon(parent, slot, index, db)
    local f = CreateFrame("Frame", addon_name .. "HudIcon" .. index, parent)
    f.slot = slot
    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints()
    f.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.default_texture = slot.texture or spell_icon(slot.spell)
    if f.default_texture then
        f.texture:SetTexture(f.default_texture)
    end
    f.texture_key = f.default_texture

    f.border_frame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.border_frame:SetAllPoints()

    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    if f.cooldown.SetHideCountdownNumbers then
        f.cooldown:SetHideCountdownNumbers(true)
    end
    f.cooldown:SetDrawEdge(false)
    f.cooldown:Hide()

    f.text_frame = CreateFrame("Frame", nil, f)
    f.text_frame:SetAllPoints()
    f.text_frame:SetFrameLevel(f.cooldown:GetFrameLevel() + 1)
    f.text = f.text_frame:CreateFontString(nil, "OVERLAY")
    -- SoD crash fix: a FontString with no font throws on SetText ("Font not
    -- set"). Set the real font BEFORE the first SetText; apply_settings
    -- re-applies the LSM/db font after the row builds (the single restyle path).
    apply_font(f.text, db)
    f.text:SetPoint("CENTER", 0, 0)
    f.text:SetJustifyH("CENTER")
    f.text:SetShadowColor(0, 0, 0, 1)
    f.text:SetShadowOffset(0, 0)
    f.text:SetText("")

    f.cd_key = nil        -- what the swipe currently shows, to call SetCooldown once
    f.glowing = false
    f.desaturated = false
    f.tint = COLOR_WHITE
    f.text_hidden = false
    f.text_value = nil    -- the quantised value behind the current text
    f.text_color = nil
    -- Provider liveness baseline: the first tick observes without reflowing (so a
    -- live row never shifts on boot); a later flip reflows the row (see reflow_row).
    f.last_hidden = false
    return f
end

-- One renderable icon per valid descriptor; invalid ones (unusable kind, no icon
-- source, no provider for a spell slot) are skipped. Returns true when the HUD exists.
function HUD.create(self)
    local class_module = ST[self.player_class or ""]
    local slots = class_module and class_module.HUD_SLOTS
    HUD.class_module = class_module
    local has_provider = class_module ~= nil and type(class_module.get_hud_state) == "function"
    local usable = {}
    if type(slots) == "table" then
        for i = 1, #slots do
            local slot = slots[i]
            if HUD.validate_slot(slot, has_provider) then
                usable[#usable + 1] = slot
            end
        end
    end
    if #usable == 0 then
        -- Nothing to render on this class: stay a silent no-op (no frame, no driver).
        HUD.inert = true
        return false
    end

    local frame = CreateFrame("Frame", addon_name .. "HudFrame", UIParent)
    HUD.frame = frame
    frame:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
    frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        -- Repositioning is user-driven only, and never under lockdown.
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        if ST:get_class_table().hud_locked ~= false then
            return
        end
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        HUD.save_position(ST)
    end)

    HUD.icons = {}
    local db_for_font
    if type(self) == "table" and type(self.get_class_table) == "function" then
        local ok_db, got_db = pcall(self.get_class_table, self)
        if ok_db and type(got_db) == "table" then
            db_for_font = got_db
        end
    end
    for i = 1, #usable do
        local icon = create_icon(frame, usable[i], i, db_for_font)
        icon.show_key = "hud_show_" .. usable[i].key
        HUD.icons[#HUD.icons + 1] = icon
    end
    HUD.layout_cache = HUD.layout_cache or {}
    HUD.update_counter = 0
    HUD.read_trinkets()
    if HUD.has_trinket_slots() then
        HUD.build_event_frame()
    end
    HUD.build_driver()
    frame:Hide()
    HUD.apply_settings(self)
    return true
end

function HUD.has_trinket_slots()
    for i = 1, #HUD.icons do
        if HUD.icons[i].slot.inv_slot then
            return true
        end
    end
    return false
end

-- Trinket refresh events; the combat-log registration is probed and pcall-protected
-- because the classic combat log does not exist on every client family (see the
-- header - it is not required for the HUD to work).
function HUD.build_event_frame()
    if HUD.event_frame then
        return
    end
    local frame = CreateFrame("Frame", addon_name .. "HudEventFrame", UIParent)
    HUD.event_frame = frame
    frame:SetScript("OnEvent", function(_, event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            HUD.on_combat_log_event(ST)
        else
            HUD.read_trinkets()
        end
    end)
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    local utils = rawget(_G, "C_EventUtils")
    local valid = true
    if type(utils) == "table" and type(utils.IsEventValid) == "function" then
        valid = utils.IsEventValid("COMBAT_LOG_EVENT_UNFILTERED") and true or false
    end
    -- Fallback (hunter-audit item 5): the CLEU registration is probed +
    -- pcall-guarded because the classic combat log does not exist on every
    -- client. When it fails only the proc-ICD reversed swipe is lost: on-use
    -- cooldowns poll GetInventoryItemCooldown and proc buffs poll the aura list
    -- on every trinket_state tick, so both stay live without CLEU.
    if valid then
        local ok, err = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
        if not ok then
            -- M1: a discarded pcall used to hide a dead ICD feed. Count every
            -- failure (HUD.cleu_register_errors, read by the /st diag wiring
            -- filed alongside) and say so once in chat; the fallback above
            -- keeps on-use + proc reads live either way.
            HUD.cleu_register_errors = (HUD.cleu_register_errors or 0) + 1
            if HUD.cleu_register_notified ~= true then
                HUD.cleu_register_notified = true
                if st.utils and type(st.utils.print_msg) == "function" then
                    pcall(st.utils.print_msg, "SwedgeTimer: combat-log tracking for trinket internal cooldowns is unavailable; on-use cooldowns and proc buffs still work. (" .. tostring(err) .. ")")
                end
            end
        end
    end
end

-- The driver frame owns the per-frame update and is never hidden (the archive drove
-- the HUD from the player frame's always-running OnUpdate).
function HUD.build_driver()
    if HUD.driver then
        return
    end
    local driver = CreateFrame("Frame", addon_name .. "HudDriverFrame", UIParent)
    HUD.driver = driver
    driver:SetScript("OnUpdate", function(_, elapsed)
        HUD.on_update(ST, elapsed)
    end)
end

--=========================================================================================
-- Init (called from a class module's post_init; also retried per-frame after a
-- lockdown deferral)
--=========================================================================================
function HUD.init(self)
    self = self or ST
    if HUD.frame or HUD.inert then
        return
    end
    HUD.owner = self
    HUD.ensure_created(self)
end

function HUD.ensure_created(self)
    if HUD.frame then
        return true
    end
    if HUD.inert then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Frames are never created in combat; retried from the class hook (and by
        -- init() itself on the next /reload) once lockdown lifts.
        HUD.pending_create = true
        return false
    end
    HUD.pending_create = false
    return HUD.create(self or HUD.owner or ST)
end

function HUD.on_bar_update(self, hand)
    -- Called from a class module's per-frame hook: retries a creation deferred by
    -- lockdown, and picks layout changes up between the driver's ticks. The row
    -- itself is driven by HUD.on_update on its own driver frame.
    if not HUD.frame then
        HUD.ensure_created(self)
        return
    end
    if HUD.layout_changed(self) then
        HUD.apply_settings(self)
    end
end

--=========================================================================================
-- Visibility (archive 265-289)
--=========================================================================================
function HUD.should_show(self)
    local db = self:get_class_table()
    if self.db and self.db.profile and self.db.profile.enabled == false then
        return false
    end
    if db.class_enabled == false then
        return false
    end
    if db.hud_enabled == false then
        return false
    end
    if db.hud_locked == false then
        -- Unlocked: keep the row visible so it can be positioned (the guide's rule).
        return true
    end
    if st.practice_ui and st.practice_ui.is_active() then
        return true
    end
    local key = db.hud_visibility_key
    if key == "in_combat" then
        return self.in_combat == true
    elseif key == "in_combat_or_target" then
        if self.in_combat then
            return true
        end
        if UnitExists and UnitCanAttack then
            return UnitExists("target") and UnitCanAttack("player", "target") or false
        end
        return false
    end
    return true
end

-- True when this icon's slot should be drawn: its toggle is on, and an occupied
-- trinket slot is shown only outside design mode (the WA hides an empty one).
function HUD.icon_should_show(self, icon, designing)
    local db = self:get_class_table()
    if db[icon.show_key] == false then
        return false
    end
    local slot = icon.slot
    if slot.inv_slot and not designing then
        local t = HUD.trinkets[slot.inv_slot]
        return HUD.trinket_usable(t, slot.inv_slot)
    end
    return true
end

--=========================================================================================
-- Spell-known gate (leveling): an icon for a spell the player has not learned
-- stays hidden instead of showing a dead icon. Fail-visible: only a confirmed
-- "not_known" hides; "unknown" (the client could not answer) shows, and the
-- next tick asks again. Trinket slots and slots without a spell query are not
-- gated here (their own paths decide).
--=========================================================================================
-- Cache for the TBC id -> name resolution below (a name never changes; a cold
-- book retries on the next tick instead of latching nil).
HUD.known_names = HUD.known_names or {}

-- The family-correct knowledge query for a slot (the operator name-vs-id rule:
-- TBC Anniversary resolves by NAME, Classic Era by id). A slot that already
-- carries a name (rogue TBC slots, druid/shaman TBC-resolved mirrors) probes
-- it directly; a numeric id on TBC resolves through the client's own spell
-- data, falling back to the id on a cold book (never nil). Nil when the slot
-- carries no spell at all (an unresolved rogue slot) - the caller then defers
-- to the provider's own verdict.
local function hud_known_query(slot)
    local spell = slot and slot.spell or nil
    if spell == nil then
        return nil
    end
    if type(spell) == "string" then
        return spell
    end
    if type(spell) ~= "number" then
        return nil
    end
    if st.family ~= "TBC" then
        return spell
    end
    local cached = HUD.known_names[spell]
    if cached ~= nil then
        return cached
    end
    local ok, name = pcall(api.GetSpellInfo, spell)
    if ok and type(name) == "string" then
        HUD.known_names[spell] = name
        return name
    end
    return spell
end

-- True when the slot may show: the player knows the spell, or the client
-- could not answer the question (fail-visible). Only a confirmed "not_known"
-- hides the icon (leveling: the spell is not in the book yet). A slot without
-- a query, or a client without a knowledge probe, shows (never a guess).
function HUD.spell_known_allows(slot)
    if slot == nil or slot.inv_slot ~= nil then
        return true
    end
    local query = hud_known_query(slot)
    if query == nil then
        return true
    end
    if type(api.is_spell_known_state) == "function" then
        local known, state = api.is_spell_known_state(query)
        if state == "unknown" then
            return true
        end
        return known == true
    end
    if type(api.is_spell_known) == "function" then
        local ok, known = pcall(api.is_spell_known, query)
        if not ok then
            return true
        end
        return known == true
    end
    return true
end

--=========================================================================================
-- Layout and style (archive 294-363)
--=========================================================================================
-- Icon size that makes `count` icons with `spacing` between them exactly as wide as the
-- mainhand bar's visible outline.
function HUD.matched_icon_size(self, count, spacing)
    local db_hand = self:get_hand_table("mainhand") or {}
    local outline = db_hand.border_width or 0
    local width = (db_hand.bar_width or 275) + 2 * outline
    return math.max(8, (width - math.max(0, count - 1) * spacing) / count)
end

-- Effective visibility: toggle want x provider liveness. A slot the provider hides
-- (a dead spell, runeless-Era Mangle) draws nothing and reserves no row width.
-- icon.wanted is toggle-level (set by apply_settings / refresh_layout_cache);
-- icon.last_hidden is liveness-level (observed by update_display).
local function icon_effective(icon)
    return icon.wanted and icon.last_hidden ~= true
end

function HUD.apply_settings(self)
    self = self or ST
    local frame = HUD.frame
    if not frame then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        HUD.pending_apply = true
        return
    end
    HUD.pending_apply = false
    local db = self:get_class_table()
    local designing = db.hud_locked == false
    local enabled = db.hud_enabled ~= false
    local size = db.hud_icon_size or DEFAULT_ICON_SIZE
    local spacing = db.hud_spacing or DEFAULT_SPACING
    local vertical = db.hud_orientation == "vertical"
    local border = db.hud_border_size or 2
    local scale = db.hud_scale or DEFAULT_SCALE
    if scale <= 0 then
        scale = DEFAULT_SCALE
    end

    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER",
        (db.hud_x or DEFAULT_X) / scale, (db.hud_y or DEFAULT_Y) / scale)
    frame:SetMovable(not designing and enabled)
    frame:EnableMouse(not designing and enabled)

    local count = 0
    for i = 1, #HUD.icons do
        local icon = HUD.icons[i]
        icon.wanted = HUD.icon_should_show(self, icon, designing)
        if icon_effective(icon) then
            count = count + 1
        end
    end
    -- Match the bar: the row is exactly as wide as the bar AS DRAWN (outline included),
    -- the icons sized to fill it. Rows only - a column has no width to match.
    if db.hud_match_bar_width and not vertical and count > 0 then
        size = HUD.matched_icon_size(self, count, spacing)
    end
    HUD.current_icon_size = size
    local span = count * size + math.max(0, count - 1) * spacing
    if vertical then
        frame:SetSize(size, math.max(span, 1))
    else
        frame:SetSize(math.max(span, 1), size)
    end

    local border_color = color_or(db.hud_border_color, BORDER_COLOR_FALLBACK)
    local br, bg, bb, ba = self:convert_color(border_color)
    local offset = 0
    for i = 1, #HUD.icons do
        local icon = HUD.icons[i]
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        if icon_effective(icon) then
            if vertical then
                icon:SetPoint("TOP", frame, "TOP", 0, -offset)
            else
                icon:SetPoint("LEFT", frame, "LEFT", offset, 0)
            end
            offset = offset + size + spacing
            icon:Show()
        else
            if icon:IsShown() then
                icon:Hide()
            end
            if icon.glowing and LCG and LCG.PixelGlow_Stop then
                LCG.PixelGlow_Stop(icon, GLOW_KEY)
                icon.glowing = false
            end
        end
        if border > 0 then
            icon.border_frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = border })
            icon.border_frame:SetBackdropBorderColor(br, bg, bb, ba or 1)
            icon.border_frame:Show()
        else
            icon.border_frame:Hide()
        end
        apply_font(icon.text, db)
    end
    HUD.refresh_layout_cache(self)
    if HUD.should_show(self) then
        HUD.update_display(self)
    elseif frame:IsShown() then
        frame:Hide()
    end
end

--=========================================================================================
-- Hidden-flip reflow (gap closure)
--=========================================================================================
-- A provider-hidden slot reserves no row width: when a tick observes a hidden flip,
-- the row reflows (width, count, positions) without waiting for a settings change.
-- Layout-only: no provider calls (the tick already read every state), no
-- update_display (that would re-run every provider and break the HS §5
-- exactly-once pin). Combat-safe: Show/Hide + reposition on these non-secure row
-- frames only; under lockdown the reflow defers via pending_apply and the on_update
-- pending branch applies it (through apply_settings, which reads the same
-- icon_effective liveness) once combat lifts. Creation stays lockdown-gated in
-- ensure_created.
function HUD.reflow_row(self)
    self = self or ST
    local frame = HUD.frame
    if not frame then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        HUD.pending_apply = true
        return
    end
    local db = self:get_class_table()
    local size = db.hud_icon_size or DEFAULT_ICON_SIZE
    local spacing = db.hud_spacing or DEFAULT_SPACING
    local vertical = db.hud_orientation == "vertical"
    local count = 0
    for i = 1, #HUD.icons do
        if icon_effective(HUD.icons[i]) then
            count = count + 1
        end
    end
    -- Match the bar, like apply_settings: the row is exactly as wide as the bar AS
    -- DRAWN (outline included). Rows only - a column has no width to match.
    if db.hud_match_bar_width and not vertical and count > 0 then
        size = HUD.matched_icon_size(self, count, spacing)
    end
    HUD.current_icon_size = size
    local span = count * size + math.max(0, count - 1) * spacing
    if vertical then
        frame:SetSize(size, math.max(span, 1))
    else
        frame:SetSize(math.max(span, 1), size)
    end
    local offset = 0
    for i = 1, #HUD.icons do
        local icon = HUD.icons[i]
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        if icon_effective(icon) then
            if vertical then
                icon:SetPoint("TOP", frame, "TOP", 0, -offset)
            else
                icon:SetPoint("LEFT", frame, "LEFT", offset, 0)
            end
            offset = offset + size + spacing
            icon:Show()
        else
            if icon:IsShown() then
                icon:Hide()
            end
            if icon.glowing and LCG and LCG.PixelGlow_Stop then
                LCG.PixelGlow_Stop(icon, GLOW_KEY)
                icon.glowing = false
            end
        end
    end
end

--=========================================================================================
-- Settings-change detection (options, drags, trinket occupancy)
--=========================================================================================
function HUD.refresh_layout_cache(self)
    local db = self:get_class_table()
    local cache = HUD.layout_cache
    if not cache then
        cache = {}
        HUD.layout_cache = cache
    end
    for i = 1, #LAYOUT_KEYS do
        local key = LAYOUT_KEYS[i]
        cache[key] = db[key]
    end
    local designing = db.hud_locked == false
    for i = 1, #HUD.icons do
        local icon = HUD.icons[i]
        icon.wanted = HUD.icon_should_show(self, icon, designing)
    end
end

function HUD.layout_changed(self)
    local db = self:get_class_table()
    local cache = HUD.layout_cache
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
    local designing = db.hud_locked == false
    for i = 1, #HUD.icons do
        local icon = HUD.icons[i]
        if icon.wanted ~= HUD.icon_should_show(self, icon, designing) then
            changed = true
        end
    end
    return changed
end

-- Positions are stored as float-safe offsets from UIParent's centre; the frame is
-- scaled, so the maths converts through the scale (the guide's drag maths).
function HUD.save_position(self)
    self = self or ST
    local frame = HUD.frame
    if not frame then
        return
    end
    local scale = frame:GetScale() or 1
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then
        return
    end
    local db = self:get_class_table()
    db.hud_x = math.floor(cx * scale - ux + 0.5)
    db.hud_y = math.floor(cy * scale - uy + 0.5)
    HUD.apply_settings(self)
end

--=========================================================================================
-- Per-icon state -> visuals (archive 368-415)
--=========================================================================================
function HUD.format_time(r)
    if r < WARN_SECONDS then
        return string.format("%.1f", r)
    end
    return string.format("%d", math.floor(r + 0.5))
end

function HUD.paint(self, icon, s, now)
    if s.hidden then
        return
    end
    now = now or api.get_time()
    local db = self:get_class_table()

    -- texture: the static default from creation, or the state's per-tick override
    -- (a trinket swaps its texture with the equipped item)
    local texture = s.texture or icon.default_texture
    if texture ~= nil and texture ~= icon.texture_key then
        icon.texture_key = texture
        icon.texture:SetTexture(texture)
    end

    -- Swipe: one SetCooldown per distinct cooldown. The derived start of a counted-down
    -- cooldown is constant (end - duration), so the comparison re-sets only when a
    -- cooldown appears, restarts or changes shape - the archive's string-key rule
    -- without the per-tick string.
    if s.duration and s.duration > 0 and (s.remaining or 0) > 0 then
        local start = s.start or (now - (s.duration - s.remaining))
        local reverse = s.reverse and true or false
        if not icon.cd_key
            or math.abs((icon.cd_start or 0) - start) > 0.05
            or icon.cd_duration ~= s.duration
            or icon.cd_reverse ~= reverse then
            icon.cd_key = true
            icon.cd_start, icon.cd_duration, icon.cd_reverse = start, s.duration, reverse
            icon.cooldown:SetReverse(reverse)
            icon.cooldown:SetCooldown(start, s.duration)
            icon.cooldown:Show()
        end
    elseif icon.cd_key then
        icon.cd_key = nil
        icon.cd_start, icon.cd_duration, icon.cd_reverse = nil, nil, nil
        icon.cooldown:SetCooldown(0, 0)
        icon.cooldown:Hide()
    end

    -- Remaining time text. The quantised value gates the string rebuild, so no string
    -- work runs on a tick whose displayed value is unchanged. Swipes shorter than 2 s
    -- (the GCD) never carry text (archive 393-401 + 430-433).
    local text_remaining = s.text_remaining
    if text_remaining == nil then
        text_remaining = s.remaining
    end
    if db.hud_show_text and text_remaining and text_remaining > 0
        and not (s.duration and s.duration < GCD_TEXT_HIDE) then
        local rounded
        if text_remaining < WARN_SECONDS then
            rounded = math.floor(text_remaining * 10 + 0.5) / 10
        else
            rounded = math.floor(text_remaining + 0.5)
        end
        if rounded ~= icon.text_value then
            icon.text_value = rounded
            icon.text:SetText(HUD.format_time(text_remaining))
        end
        local color = (text_remaining < WARN_SECONDS)
            and color_or(db.hud_text_warn_color, TEXT_WARN_COLOR_FALLBACK)
            or color_or(db.hud_text_color, TEXT_COLOR_FALLBACK)
        if color ~= icon.text_color then
            icon.text_color = color
            local r, g, b, a = self:convert_color(color)
            icon.text:SetTextColor(r, g, b, a or 1)
        end
        if icon.text_hidden then
            icon.text_hidden = false
            icon.text:Show()
        end
    elseif not icon.text_hidden then
        icon.text_hidden = true
        icon.text_value = nil
        icon.text:Hide()
    end

    -- desaturate while on cooldown (or when the provider asks for it)
    local desaturate = (db.hud_desaturate and s.desaturate) and true or false
    if desaturate ~= icon.desaturated then
        icon.desaturated = desaturate
        icon.texture:SetDesaturated(desaturate)
    end

    -- no-mana (blue) and out-of-range (red) tints, mana first (archive 436-439)
    local tint
    if s.usable == false and db.hud_mana_tint then
        tint = COLOR_NO_MANA
    elseif s.in_range == false and db.hud_range_tint then
        tint = COLOR_OUT_OF_RANGE
    end
    tint = tint or COLOR_WHITE
    if tint ~= icon.tint then
        icon.tint = tint
        icon.texture:SetVertexColor(tint[1], tint[2], tint[3], 1)
    end

    -- proc glow
    local want_glow = (db.hud_glow_enabled and s.glow) and true or false
    if want_glow ~= icon.glowing then
        icon.glowing = want_glow
        if want_glow then
            if LCG and LCG.PixelGlow_Start then
                LCG.PixelGlow_Start(icon, nil, GLOW_LINES, GLOW_FREQUENCY, GLOW_LENGTH,
                    GLOW_THICKNESS, 0, 0, false, GLOW_KEY)
            end
        elseif LCG and LCG.PixelGlow_Stop then
            LCG.PixelGlow_Stop(icon, GLOW_KEY)
        end
    end
end

-- Design-mode samples (archive 487-523): every enabled icon in a representative state
-- on looping clocks, so the swipes and numbers run while the row is being positioned.
-- Paladin slot keys keep the archive's samples; an unknown slot returns nil so the
-- caller renders its live state instead.
function HUD.preview_state(self, slot, now)
    local s = PREVIEW_STATE
    s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
    s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
    s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
    if slot.inv_slot then
        local t = HUD.trinkets[slot.inv_slot]
        s.texture = (t and t.texture) or TRINKET_FALLBACK_ICON[slot.inv_slot]
        if slot.inv_slot == 13 then
            local loop = now % 30
            if loop < 10 then
                s.start, s.duration = now - loop, 10
                s.remaining, s.text_remaining = 10 - loop, 10 - loop
            else
                s.start, s.duration, s.reverse = now - (loop - 10), 20, true
                s.remaining, s.text_remaining = 30 - loop, 30 - loop
            end
        else
            local loop = now % 45
            s.start, s.duration = now - loop, 45
            s.remaining, s.text_remaining, s.desaturate = 45 - loop, 45 - loop, true
        end
    elseif slot.key == "cs" then
        local loop = now % 7.5
        if loop < 6 then
            s.start, s.duration = now - loop, 6
            s.remaining, s.text_remaining, s.desaturate = 6 - loop, 6 - loop, true
        end
    elseif slot.key == "consecration" then
        s.usable = false
    elseif slot.key == "exorcism" then
        s.glow = true
    elseif slot.key == "wings" then
        s.glow = true
    else
        return nil
    end
    return s
end

--=========================================================================================
-- Per-frame update (archive 525-568), called from the driver frame
--=========================================================================================
function HUD.update_display(self)
    self = self or ST
    local frame = HUD.frame
    if not frame then
        return
    end
    if not frame:IsShown() then
        frame:Show()
    end
    local db = self:get_class_table()
    local now = api.get_time()
    local preview = db.hud_locked == false
    local reflow_needed = false
    for i = 1, #HUD.icons do
        local icon = HUD.icons[i]
        if icon.wanted then
            local s
            if preview then
                s = HUD.preview_state(self, icon.slot, now)
            end
            if not s then
                if icon.slot.inv_slot then
                    s = HUD.trinket_state(self, icon.slot, now)
                elseif HUD.class_module then
                    local site = "hud:" .. tostring(icon.slot.key or "?")
                    -- Isolated through the shared contract (guard.lua): a quarantined
                    -- site is not called at all, a throwing provider costs only its
                    -- own icon - the row still paints.
                    local ok, state = st.guard.run(self, site, call_hud_provider,
                        HUD.class_module, self, icon.slot, now)
                    if ok then
                        s = state
                    else
                        s = HUD_HIDDEN_STATE
                    end
                end
            end
            if s and not s.hidden and not preview
                and not HUD.spell_known_allows(icon.slot) then
                -- The leveling gate: a spell the player has not learned draws
                -- nothing (fail-visible: only a confirmed unknown hides, so a
                -- client that cannot answer keeps the icon). The hide rides the
                -- existing hidden-flip path below, so the row reflows.
                s.hidden = true
            end
            if s and not s.hidden then
                -- First observation baselines without reflowing (a live row never
                -- shifts on boot); a later flip reflows after the loop.
                if icon.last_hidden == nil then
                    icon.last_hidden = false
                elseif icon.last_hidden ~= false then
                    icon.last_hidden = false
                    reflow_needed = true
                end
                -- A slot the provider hid on an earlier tick (druid Mangle on
                -- runeless Era, TF/Berserk where the client's spell data carries
                -- no such spell) revives here: the settings pass shows every
                -- wanted icon, so a dead slot must re-show to rejoin the row.
                if not icon:IsShown() then
                    icon:Show()
                end
                HUD.paint(self, icon, s, now)
            elseif s and s.hidden then
                if icon.last_hidden == nil then
                    icon.last_hidden = true
                elseif icon.last_hidden ~= true then
                    icon.last_hidden = true
                    reflow_needed = true
                end
                -- Provider-level hide wins over the toggle-level want: the slot
                -- stays built (a later liveness retry can revive it) but draws
                -- nothing. A stale proc glow stops with it, like the
                -- toggle-off path in apply_settings.
                if icon:IsShown() then
                    icon:Hide()
                end
                if icon.glowing and LCG and LCG.PixelGlow_Stop then
                    LCG.PixelGlow_Stop(icon, GLOW_KEY)
                    icon.glowing = false
                end
            end
        end
    end
    if reflow_needed then
        -- The flip is already painted (hide/show above); only the row geometry
        -- is still stale. Under lockdown it waits: repositioning can run in
        -- combat, but the lane defers the whole reflow so the row never shifts
        -- mid-fight, and the on_update pending branch applies it on exit.
        if InCombatLockdown and InCombatLockdown() then
            HUD.pending_apply = true
        else
            HUD.reflow_row(self)
        end
    end
end

function HUD.on_update(self, elapsed)
    self = self or ST
    local frame = HUD.frame
    if not frame then
        return
    end
    HUD.update_counter = HUD.update_counter + (elapsed or 0.016)
    if HUD.update_counter < TICK then
        return
    end
    HUD.update_counter = 0
    if HUD.pending_apply and not (InCombatLockdown and InCombatLockdown()) then
        HUD.apply_settings(self)
        return
    end
    if HUD.layout_changed(self) then
        HUD.apply_settings(self)
        return
    end
    if not HUD.should_show(self) then
        if frame:IsShown() then
            frame:Hide()
        end
        return
    end
    HUD.update_display(self)
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed hud.lua module correctly') end
