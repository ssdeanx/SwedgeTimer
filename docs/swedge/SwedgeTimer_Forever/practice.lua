-- practice.lua =========================================================================
-- Twist Practice Minigame: fully simulated seal twisting practice with keybinds,
-- ability cooldowns, haste toggles, and a control panel UI.
-- All spells are simulated (no mana cost, no real casts).
-- ======================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")
local SML = LibStub("LibSharedMedia-3.0")
local LCG = LibStub("LibCustomGlow-1.0")
local print = st.utils.print_msg

st.practice = {}

-- Core state
st.practice.active = false

-- UI frames
st.practice.control_frame = nil
st.practice.result_frame = nil
st.practice.result_visible = false
st.practice.result_timer = 0

-- Saved references to original functions (for hooking/restoring)
st.practice.orig = {}

-- Keybind button frames (invisible, used as click targets for SetOverrideBindingClick)
st.practice.buttons = {}

-- Action bar overlay state
st.practice.bar_mappings = {}   -- ability_key -> { slot=int, frame_name=string }
st.practice.bar_overlays = {}   -- ability_key -> { cooldown=CooldownFrame, gcd_dim=Texture }

-- Manual linking state
st.practice.linking_ability = nil   -- ability_key being linked, or nil
st.practice.linking_catchers = {}   -- temporary click-catcher frames

-- Key-capture state (fallback when keybind detection fails during linking)
st.practice.key_capture_frame = nil
st.practice.key_capture_ability = nil

-- Center-screen rotation display
st.practice.rotation_display = nil          -- Frame for the center-screen rotation display
st.practice.rotation_display_icons = {}     -- Icon frames for rotation steps
st.practice.rotation_display_max_icons = 5  -- Max icons (longest sequence is 5)
st.practice.current_display_rotation = nil  -- Tracks rotation for change detection
st.practice.display_rotation_sequence = {}  -- Current sequence array

-- Fight timeline
st.practice.timeline_events = {}
st.practice.timeline_event_count = 0
st.practice.timeline_frame = nil
st.practice.timeline_visible = false
st.practice.timeline_auto_scroll = true
st.practice.timeline_needs_render = false
st.practice.timeline_max_time = 0
-- Frame pools
st.practice.timeline_icon_pool = {}
st.practice.timeline_icon_pool_used = 0
st.practice.timeline_divider_pool = {}
st.practice.timeline_divider_pool_used = 0
st.practice.timeline_ruler_pool = { ticks = {}, labels = {} }
st.practice.timeline_ruler_pool_used = 0
-- Rotation bands (colored regions in ruler showing active rotation)
st.practice.timeline_rotation_bands = {}
st.practice.timeline_rotation_band_count = 0
st.practice.timeline_rotation_band_pool = {}
st.practice.timeline_rotation_band_pool_used = 0

--=========================================================================================
-- Simulated State
--=========================================================================================
st.practice.sim = {
    active_seals = {},          -- {command=true, blood=true}
    n_active_seals = 0,
    seal_1_label = nil,         -- Oldest seal (or only seal)
    seal_2_label = nil,         -- Newest seal (during twist window)
    fading_seal_label = nil,    -- Seal that's fading after a new seal was cast
    fading_seal_expires = 0,    -- GetTime() when fading seal disappears

    effective_speed = 3.5,      -- Weapon speed after haste
    effective_gcd = 1.5,        -- GCD after haste

    has_bloodlust = false,
    has_haste_pot = false,
    has_abacus = false,
    has_dst = false,
    bl_buff_expires = 0,            -- GetTime() when BL buff fades (40s duration)
    haste_pot_buff_expires = 0,     -- GetTime() when haste pot buff fades (15s duration)
    abacus_buff_expires = 0,        -- GetTime() when Abacus buff fades (10s duration)
    abacus_cooldown_expires = 0,    -- GetTime() when Abacus CD expires (120s)
    dst_buff_expires = 0,           -- GetTime() when DST buff fades (10s duration)
    dst_icd_expires = 0,            -- GetTime() when DST ICD expires (20s)

    cs_cooldown_expires = 0,
    judge_cooldown_expires = 0,
    consec_cooldown_expires = 0,
    aw_cooldown_expires = 0,
    aw_buff_expires = 0,            -- GetTime() when AW buff fades

    -- Boss fight state
    fight_active = false,
    fight_start_time = 0,
    fight_bl_delay = 0,
    fight_bl_fired = false,

    -- Stopattack state
    attack_paused = false,
    attack_pause_pending = false,
    swing_held = false,             -- Swing completed during stopattack, held until startattack

    -- Twist attempt tracking (true when a seal swap created dual-seal state this swing cycle)
    twist_attempted = false,

    -- Spell queue window state
    queued_ability = nil,       -- ability_key of the queued spell, or nil
    queue_timestamp = 0,        -- GetTime() when queued (for debug)
}

-- Rotation lock: nil = auto (dynamic), or a key from rotation_presets
st.practice.locked_rotation = nil

-- Presets mapping rotation key -> {speed, gcd} that produce that rotation via determine_rotation()
st.practice.rotation_presets = {
    ["1/2"]         = { speed = 3.5,  gcd = 1.5  },
    ["2/3"]         = { speed = 2.3,  gcd = 1.15 },
    ["2/4"]         = { speed = 1.8,  gcd = 1.15 },
}

--=========================================================================================
-- Ability Definitions
--=========================================================================================
local abilities = {
    soc   = { name = "Seal of Command",       spell_id = 20375,  type = "seal",    cooldown = 0,   seal_label = "command" },
    sob   = { name = "Seal of Blood",          spell_id = 31892,  type = "seal",    cooldown = 0,   seal_label = "blood" },
    sotc  = { name = "Seal of the Crusader",   spell_id = 21082,  type = "seal",    cooldown = 0,   seal_label = "crusader" },
    cs    = { name = "Crusader Strike",        spell_id = 35395,  type = "ability", cooldown = 6 },
    judge = { name = "Judgement",              spell_id = 20271,  type = "ability", cooldown = 8 },
    consec = { name = "Consecration",          spell_id = 26573,  type = "ability", cooldown = 8 },
    aw    = { name = "Avenging Wrath",         spell_id = 31884,  type = "buff",    cooldown = 180, duration = 20 },
    hpot  = { name = "Haste Potion",           spell_id = 28507,  type = "haste_consumable", cooldown = 0, duration = 15 },
    abacus = { name = "Abacus of Violent Odds", spell_id = 33807,  type = "haste_trinket",    cooldown = 120, duration = 10 },
    stop  = { name = "Stop Attack",  texture = "Interface\\Icons\\Ability_DualWield", type = "stopattack", cooldown = 0 },
}

-- Ordered list of ability keys for UI layout
local ability_order = { "soc", "sob", "cs", "judge", "sotc", "consec", "aw", "hpot", "abacus", "stop" }

-- Timeline lane definitions (ordered like WarcraftLogs)
local timeline_lanes = {
    { key = "sob",    name = "SoB",    spell_id = 31892 },
    { key = "melee",  name = "Melee",  texture = "Interface\\Icons\\INV_Sword_04" },
    { key = "cs",     name = "CS",     spell_id = 35395 },
    { key = "consec", name = "Consec", spell_id = 26573 },
    { key = "soc",    name = "SoC",    spell_id = 20375 },
    { key = "judge",  name = "Judge",  spell_id = 20271 },
}
local timeline_lane_index = {}
for i, lane in ipairs(timeline_lanes) do timeline_lane_index[lane.key] = i end

local seal_label_to_lane = { blood = "sob", command = "soc" }

-- Timeline UI constants
local TIMELINE_LANE_HEIGHT = 24
local TIMELINE_ICON_SIZE = 20
local TIMELINE_LABEL_WIDTH = 60
local TIMELINE_RULER_HEIGHT = 46

-- Map from ability key to the db setting key for its keybind
local keybind_db_keys = {
    soc = "practice_key_soc",
    sob = "practice_key_sob",
    cs = "practice_key_cs",
    judge = "practice_key_judge",
    sotc = "practice_key_sotc",
    consec = "practice_key_consec",
    aw = "practice_key_aw",
    hpot = "practice_key_hpot",
    abacus = "practice_key_abacus",
    stop = "practice_key_stopattack",
}

-- Abbreviate a WoW keybind string to max 3 characters for icon labels
local function shorten_keybind(key)
    if not key or key == "" then return "" end

    -- Strip and record modifier prefixes
    local mods = ""
    local base = key
    if base:find("^CTRL%-") then mods = "C"; base = base:sub(6) end
    if base:find("^SHIFT%-") then mods = "S"; base = base:sub(7) end
    if base:find("^ALT%-") then mods = "A"; base = base:sub(5) end

    -- Numpad keys → "N" + symbol/digit
    local np = base:match("^NUMPAD(.+)")
    if np then
        local np_map = {
            DECIMAL=".", PLUS="+", MINUS="-", MULTIPLY="*", DIVIDE="/",
        }
        base = "N" .. (np_map[np] or np)
    end

    -- Mouse keys
    if base == "MOUSEWHEELUP" then base = "MU"
    elseif base == "MOUSEWHEELDOWN" then base = "MD"
    elseif base:match("^BUTTON(%d)") then base = "M" .. base:match("^BUTTON(%d)")
    end

    -- Gamepad buttons
    local pad_map = {
        PAD1 = "P1", PAD2 = "P2", PAD3 = "P3", PAD4 = "P4",
        PADLSHOULDER = "LB", PADRSHOULDER = "RB",
        PADLTRIGGER = "LT", PADRTRIGGER = "RT",
        PADLSTICK = "LS", PADRSTICK = "RS",
        PADDUP = "DU", PADDDOWN = "DD", PADDLEFT = "DL", PADDRIGHT = "DR",
        PADFORWARD = "FW", PADBACK = "BK",
        PADLSTICKUP = "LU", PADLSTICKDOWN = "LD",
        PADLSTICKLEFT = "LL", PADLSTICKRIGHT = "LR",
        PADRSTICKUP = "RU", PADRSTICKDOWN = "RD",
        PADRSTICKLEFT = "RL", PADRSTICKRIGHT = "RR",
    }
    if pad_map[base] then base = pad_map[base] end

    local result = mods .. base
    return result:sub(1, 3)
end

-- Build modifier prefix string from current modifier key state
local function get_modifier_prefix()
    local prefix = ""
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix
end

-- Bare modifier keys to ignore in key capture
local ignore_keys = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
    UNKNOWN = true,
}

-- Gamepad buttons configured as modifier emulators (checked dynamically via CVars)
local function is_gamepad_emulator_button(button)
    if not GetCVar then return false end
    local emulate_cvars = {
        "GamePadEmulateShift",
        "GamePadEmulateCtrl",
        "GamePadEmulateAlt",
        "GamePadEmulateEsc",
    }
    for _, cvar in ipairs(emulate_cvars) do
        local val = GetCVar(cvar)
        if val and val == button then return true end
    end
    return false
end

-- Lazily create the fullscreen key-capture overlay
local function get_or_create_key_capture_frame()
    if st.practice.key_capture_frame then
        return st.practice.key_capture_frame
    end

    local f = CreateFrame("Frame", "SwedgeTimerKeyCapture", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:EnableKeyboard(false)

    -- Semi-transparent backdrop
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Prompt text
    f.prompt = f:CreateFontString(nil, "OVERLAY")
    f.prompt:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    f.prompt:SetPoint("CENTER", 0, 20)
    f.prompt:SetTextColor(1, 1, 1, 1)

    f.hint = f:CreateFontString(nil, "OVERLAY")
    f.hint:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    f.hint:SetPoint("CENTER", 0, -10)
    f.hint:SetTextColor(0.7, 0.7, 0.7, 1)
    f.hint:SetText("ESC or right-click to cancel")

    f:SetScript("OnKeyDown", function(self, key)
        if ignore_keys[key] then return end
        if key == "ESCAPE" then
            st.practice.cancel_key_capture()
            return
        end
        local bind = get_modifier_prefix() .. key
        st.practice.finish_key_capture(bind)
    end)

    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then return end
        if button == "RightButton" then
            st.practice.cancel_key_capture()
            return
        end
        local mouse_map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
        local mapped = mouse_map[button] or button
        local bind = get_modifier_prefix() .. mapped
        st.practice.finish_key_capture(bind)
    end)

    f:SetScript("OnMouseWheel", function(self, delta)
        local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        local bind = get_modifier_prefix() .. key
        st.practice.finish_key_capture(bind)
    end)

    -- Gamepad button capture (native controller support)
    if f.EnableGamePadButton then
        f:EnableGamePadButton(false)  -- enabled only in start_key_capture
        f:SetScript("OnGamePadButtonDown", function(self, button)
            if is_gamepad_emulator_button(button) then return end
            local bind = get_modifier_prefix() .. button
            st.practice.finish_key_capture(bind)
        end)
    end

    f:Hide()
    st.practice.key_capture_frame = f
    return f
end

-- Abilities that resume attack after stopattack
local stopattack_resume_abilities = { cs = true, judge = true, sob = true, aw = true }

-- Map action bar slot to binding name (module-scope, shared by auto-detect and linking)
local function slot_to_binding(slot)
    if slot >= 1 and slot <= 12 then
        return "ACTIONBUTTON" .. slot
    elseif slot >= 13 and slot <= 24 then
        -- Page 2 of main bar (shares ACTIONBUTTON bindings with page 1)
        return "ACTIONBUTTON" .. (slot - 12)
    elseif slot >= 25 and slot <= 36 then
        return "MULTIACTIONBAR3BUTTON" .. (slot - 24)
    elseif slot >= 37 and slot <= 48 then
        return "MULTIACTIONBAR4BUTTON" .. (slot - 36)
    elseif slot >= 49 and slot <= 60 then
        return "MULTIACTIONBAR2BUTTON" .. (slot - 48)
    elseif slot >= 61 and slot <= 72 then
        return "MULTIACTIONBAR1BUTTON" .. (slot - 60)
    end
    return nil
end

-- Discover all visible action bar button frames from any bar addon.
-- Returns: { [slot] = { frame=Frame, frame_name=string } }
local function discover_action_buttons(include_hidden)
    local result = {}

    local function is_usable(frame)
        if not frame then return false end
        if include_hidden then return true end
        return frame:IsVisible()
    end

    -- Bartender4: BT4Button1 through BT4Button120
    if _G["BT4Button1"] then
        for i = 1, 120 do
            local name = "BT4Button" .. i
            local frame = _G[name]
            if is_usable(frame) then
                local slot = frame:GetAttribute("action")
                if slot then
                    result[tonumber(slot)] = { frame = frame, frame_name = name }
                end
            end
        end
    end

    -- Dominos: creates its own frames (Blizzard originals are hidden)
    -- Bars 1-2 and 7-14: DominosActionButton1-168
    -- Bars 3-6: MultiBar*ActionButton (note "Action" in name, unlike Blizzard)
    if _G["DominosActionButton1"] then
        for i = 1, 168 do
            local name = "DominosActionButton" .. i
            local frame = _G[name]
            if is_usable(frame) then
                local slot = frame:GetAttribute("action")
                if slot then
                    result[tonumber(slot)] = { frame = frame, frame_name = name }
                end
            end
        end
        local dominos_multi = {
            "MultiBarRightActionButton",
            "MultiBarLeftActionButton",
            "MultiBarBottomRightActionButton",
            "MultiBarBottomLeftActionButton",
        }
        for _, prefix in ipairs(dominos_multi) do
            for i = 1, 12 do
                local name = prefix .. i
                local frame = _G[name]
                if is_usable(frame) then
                    local slot = frame:GetAttribute("action")
                    if slot then
                        result[tonumber(slot)] = { frame = frame, frame_name = name }
                    end
                end
            end
        end
    end

    -- ElvUI: creates its own action button frames (bars 1-10, 13-15)
    -- Keybinds use WoW API binding names, resolved in get_binding_for_slot
    if _G["ElvUI_Bar1Button1"] then
        for _, bar in ipairs({1,2,3,4,5,6,7,8,9,10,13,14,15}) do
            for i = 1, 12 do
                local name = "ElvUI_Bar" .. bar .. "Button" .. i
                local frame = _G[name]
                if is_usable(frame) then
                    local slot = frame:GetAttribute("action")
                    if slot then
                        result[tonumber(slot)] = { frame = frame, frame_name = name }
                    end
                end
            end
        end
    end

    -- Blizzard default (ElvUI hides these and creates its own frames above)
    local blizz_bars = {
        { prefix = "ActionButton",               offset = 0 },
        { prefix = "MultiBarRightButton",        offset = 24 },
        { prefix = "MultiBarLeftButton",         offset = 36 },
        { prefix = "MultiBarBottomRightButton",  offset = 48 },
        { prefix = "MultiBarBottomLeftButton",   offset = 60 },
    }
    for _, bar in ipairs(blizz_bars) do
        for i = 1, 12 do
            local slot = bar.offset + i
            if not result[slot] then  -- Don't override BT4 frames
                local name = bar.prefix .. i
                local frame = _G[name]
                if is_usable(frame) then
                    result[slot] = { frame = frame, frame_name = name }
                end
            end
        end
    end

    return result
end

-- Resolve the keybind for an action slot, checking addon bindings first then Blizzard.
local function get_binding_for_slot(slot, frame_name)
    if frame_name then
        -- Dominos: each button stores its binding command in the commandName attribute
        -- This handles all Dominos bars (both standard and CLICK-style bindings)
        local frame = _G[frame_name]
        if frame then
            local commandName = frame:GetAttribute("commandName")
            if commandName then
                local key = GetBindingKey(commandName)
                if key then return key end
            end
        end

        -- BT4-style click binding (e.g. "CLICK BT4Button1:LeftButton")
        local key = GetBindingKey("CLICK " .. frame_name .. ":LeftButton")
        if key then return key end

        -- ElvUI: binding names are determined by bar number, not action slot
        local elv_bar, elv_btn = frame_name:match("^ElvUI_Bar(%d+)Button(%d+)$")
        if elv_bar then
            local elv_binding_prefixes = {
                [1]  = "ACTIONBUTTON",
                [2]  = "ELVUIBAR2BUTTON",
                [3]  = "MULTIACTIONBAR3BUTTON",
                [4]  = "MULTIACTIONBAR4BUTTON",
                [5]  = "MULTIACTIONBAR2BUTTON",
                [6]  = "MULTIACTIONBAR1BUTTON",
            }
            -- Bars 7-10 and 13-15 use ELVUIBAR{N}BUTTON (TBC Classic)
            local prefix = elv_binding_prefixes[tonumber(elv_bar)]
                           or ("ELVUIBAR" .. elv_bar .. "BUTTON")
            key = GetBindingKey(prefix .. elv_btn)
            if key then return key end
        end
    end

    -- Standard Blizzard binding
    local binding_name = slot_to_binding(slot)
    if binding_name then
        local key = GetBindingKey(binding_name)
        if key then return key end
    end

    return nil
end

--=========================================================================================
-- Initialization
--=========================================================================================
st.practice.init = function()
    -- Create invisible button frames for keybind targets
    -- Using regular Buttons (not SecureActionButtonTemplate) to avoid taint issues
    for _, key in ipairs(ability_order) do
        local btn_name = "SwedgeTimerPrac" .. key
        local btn = CreateFrame("Button", btn_name, UIParent)
        btn:SetSize(1, 1)
        btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        btn:EnableMouse(false)
        btn:RegisterForClicks("AnyUp")
        btn:SetScript("OnClick", function()
            if st.practice.active then
                st.practice.sim_cast(key)
            end
        end)
        st.practice.buttons[key] = btn
    end

    -- Create result text frame ("TWIST!" / "MISS" popup, anchored above bar)
    local result = CreateFrame("Frame", addon_name .. "PracticeResultFrame", UIParent)
    result:SetSize(200, 50)
    result:SetPoint("BOTTOM", st.bar.frame, "TOP", 0, 8)
    result:SetFrameStrata("HIGH")

    result.text = result:CreateFontString(nil, "OVERLAY")
    result.text:SetPoint("CENTER", 0, 0)
    result.text:SetShadowColor(0.0, 0.0, 0.0, 1.0)
    result.text:SetShadowOffset(2, -2)

    local db = ST.db.profile
    local font_path = SML:Fetch('font', SML.DefaultMedia.font)
    result.text:SetFont(font_path, db.practice_result_text_size, "OUTLINE")
    result.text:SetText("")
    result:SetAlpha(0)

    st.practice.result_frame = result

    -- Create the control panel frame
    st.practice.create_control_panel()

    -- Create the center-screen rotation display
    st.practice.create_rotation_display()

    -- Create the fight timeline
    st.practice.create_timeline()

    if st.debug then print('Practice mode initialised.') end
end

--=========================================================================================
-- Control Panel UI
--=========================================================================================
st.practice.create_control_panel = function()
    local db = ST.db.profile

    local panel = CreateFrame("Frame", addon_name .. "PracticeControlFrame", UIParent, "BackdropTemplate")
    panel:SetSize(210, 290)
    panel:SetPoint("TOPLEFT", st.bar.frame, "TOPRIGHT", 8, 0)
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local y_offset = -8

    -- Title bar
    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetPoint("TOP", panel, "TOP", 0, y_offset)
    panel.title:SetFontObject(GameFontNormal)
    panel.title:SetText("|cFFFF8800Twist Practice|r")
    y_offset = y_offset - 16

    -- Close button
    local close_btn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close_btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    close_btn:SetSize(20, 20)
    close_btn:SetScript("OnClick", function()
        if st.practice.active then
            st.practice.stop()
        end
    end)

    -- Speed / GCD / Rotation info line
    panel.info_text = panel:CreateFontString(nil, "OVERLAY")
    panel.info_text:SetPoint("TOP", panel, "TOP", 0, y_offset)
    panel.info_text:SetFontObject(GameFontHighlightSmall)
    panel.info_text:SetText("Speed: 3.5s  GCD: 1.5s")
    y_offset = y_offset - 14

    panel.rotation_text = panel:CreateFontString(nil, "OVERLAY")
    panel.rotation_text:SetPoint("TOP", panel, "TOP", 0, y_offset)
    panel.rotation_text:SetFontObject(GameFontHighlightSmall)
    panel.rotation_text:SetText("Rotation: --")
    y_offset = y_offset - 18

    -- Separator
    local sep1 = panel:CreateTexture(nil, "ARTWORK")
    sep1:SetHeight(1)
    sep1:SetPoint("LEFT", panel, "LEFT", 6, 0)
    sep1:SetPoint("RIGHT", panel, "RIGHT", -6, 0)
    sep1:SetPoint("TOP", panel, "TOP", 0, y_offset)
    sep1:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    y_offset = y_offset - 6

    -- Ability icons - Row 1: Seals + melee abilities
    -- Row 2: Utility + items
    local icon_size = 30
    local icon_spacing = 4
    local row1_keys = { "soc", "sob", "sotc", "cs", "judge" }
    local row2_keys = { "consec", "aw", "stop", "hpot", "abacus" }

    panel.ability_icons = {}

    local function create_ability_row(keys, row_y)
        local total_width = #keys * icon_size + (#keys - 1) * icon_spacing
        local start_x = -total_width / 2 + icon_size / 2

        for i, key in ipairs(keys) do
            local ab = abilities[key]
            local x = start_x + (i - 1) * (icon_size + icon_spacing)

            local icon_frame = CreateFrame("Frame", nil, panel)
            icon_frame:SetSize(icon_size, icon_size)
            icon_frame:SetPoint("TOP", panel, "TOP", x, row_y)

            -- Icon texture
            icon_frame.tex = icon_frame:CreateTexture(nil, "ARTWORK")
            icon_frame.tex:SetAllPoints()
            icon_frame.tex:SetTexture(ab.texture or GetSpellTexture(ab.spell_id))
            icon_frame.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Cooldown overlay
            icon_frame.cooldown = CreateFrame("Cooldown", nil, icon_frame, "CooldownFrameTemplate")
            icon_frame.cooldown:SetAllPoints()
            icon_frame.cooldown:SetDrawEdge(false)
            icon_frame.cooldown:SetHideCountdownNumbers(true)

            -- GCD dim overlay
            icon_frame.gcd_dim = icon_frame:CreateTexture(nil, "OVERLAY")
            icon_frame.gcd_dim:SetAllPoints()
            icon_frame.gcd_dim:SetColorTexture(0, 0, 0, 0.5)
            icon_frame.gcd_dim:Hide()

            -- GCD cooldown swipe overlay
            icon_frame.gcd_cooldown = CreateFrame("Cooldown", nil, icon_frame, "CooldownFrameTemplate")
            icon_frame.gcd_cooldown:SetAllPoints()
            icon_frame.gcd_cooldown:SetDrawEdge(false)
            icon_frame.gcd_cooldown:SetHideCountdownNumbers(true)

            -- Keybind label
            icon_frame.keybind_text = icon_frame:CreateFontString(nil, "OVERLAY")
            icon_frame.keybind_text:SetPoint("BOTTOM", icon_frame, "BOTTOM", 0, 2)
            icon_frame.keybind_text:SetFontObject(NumberFontNormalSmallGray)
            icon_frame.keybind_text:SetText(shorten_keybind(db[keybind_db_keys[key]]))

            -- Click handler: left = cast, right = start linking
            icon_frame:EnableMouse(true)
            icon_frame:SetScript("OnMouseDown", function(self, button)
                if not st.practice.active then return end
                if button == "RightButton" then
                    st.practice.start_linking(key)
                else
                    st.practice.sim_cast(key)
                end
            end)

            -- Border
            icon_frame.border = icon_frame:CreateTexture(nil, "OVERLAY", nil, 1)
            icon_frame.border:SetPoint("TOPLEFT", -1, 1)
            icon_frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
            icon_frame.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
            icon_frame.border:SetDrawLayer("OVERLAY", -1)

            panel.ability_icons[key] = icon_frame
        end
    end

    create_ability_row(row1_keys, y_offset)
    y_offset = y_offset - icon_size - 4
    create_ability_row(row2_keys, y_offset)
    y_offset = y_offset - icon_size - 6

    -- Mapping hint text
    panel.hint_text = panel:CreateFontString(nil, "OVERLAY")
    panel.hint_text:SetPoint("TOP", panel, "TOP", 0, y_offset)
    panel.hint_text:SetWidth(panel:GetWidth() - 16)
    panel.hint_text:SetWordWrap(true)
    panel.hint_text:SetFont(STANDARD_TEXT_FONT, 9, "")
    panel.hint_text:SetTextColor(0.5, 0.5, 0.5, 0.8)
    panel.hint_text:SetText("Right-click icon to map to action bar")
    y_offset = y_offset - 14

    -- Reset mappings button (small red link below hint text)
    panel.reset_mappings_btn = CreateFrame("Button", nil, panel)
    panel.reset_mappings_btn:SetSize(40, 12)
    panel.reset_mappings_btn:SetPoint("TOP", panel, "TOP", 0, y_offset)

    local reset_label = panel.reset_mappings_btn:CreateFontString(nil, "OVERLAY")
    reset_label:SetAllPoints()
    reset_label:SetFont(STANDARD_TEXT_FONT, 9, "")
    reset_label:SetTextColor(0.8, 0.3, 0.3, 0.8)
    reset_label:SetText("(Reset)")

    panel.reset_mappings_btn:SetScript("OnClick", function()
        st.practice.reset_all_mappings()
    end)
    y_offset = y_offset - 14

    -- Separator
    local sep2 = panel:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("LEFT", panel, "LEFT", 6, 0)
    sep2:SetPoint("RIGHT", panel, "RIGHT", -6, 0)
    sep2:SetPoint("TOP", panel, "TOP", 0, y_offset)
    sep2:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    y_offset = y_offset - 8

    -- Haste toggle buttons
    local function create_toggle_button(parent, label, y_pos, on_click)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(90, 22)
        btn:SetPoint("TOP", parent, "TOP", 0, y_pos)
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

        btn.active = false
        btn:SetScript("OnClick", function(self)
            on_click(self)
        end)

        return btn
    end

    -- Bloodlust button (left) - timed activation (40s)
    panel.bl_btn = create_toggle_button(panel, "Bloodlust", y_offset, function(self)
        local sim = st.practice.sim
        if sim.fight_active then
            -- During boss fight, BL is auto-controlled
            -- (silent)
            return
        end
        if sim.has_bloodlust then return end  -- Already active, no toggling off
        st.practice.activate_bloodlust()
    end)
    panel.bl_btn:SetPoint("TOP")
    panel.bl_btn:ClearAllPoints()
    panel.bl_btn:SetPoint("TOPRIGHT", panel, "TOP", -2, y_offset)

    -- Countdown text on BL button
    panel.bl_btn.countdown = panel.bl_btn:CreateFontString(nil, "OVERLAY")
    panel.bl_btn.countdown:SetPoint("RIGHT", panel.bl_btn, "RIGHT", -4, 0)
    panel.bl_btn.countdown:SetFontObject(GameFontHighlightSmall)
    panel.bl_btn.countdown:SetText("")

    -- Haste Potion button (right) - timed activation (15s)
    panel.hp_btn = create_toggle_button(panel, "Haste Pot", y_offset, function(self)
        if st.practice.sim.has_haste_pot then return end  -- Already active, no toggling off
        st.practice.activate_haste_pot()
    end)
    panel.hp_btn:ClearAllPoints()
    panel.hp_btn:SetPoint("TOPLEFT", panel, "TOP", 2, y_offset)

    -- Countdown text on HP button
    panel.hp_btn.countdown = panel.hp_btn:CreateFontString(nil, "OVERLAY")
    panel.hp_btn.countdown:SetPoint("RIGHT", panel.hp_btn, "RIGHT", -4, 0)
    panel.hp_btn.countdown:SetFontObject(GameFontHighlightSmall)
    panel.hp_btn.countdown:SetText("")

    y_offset = y_offset - 28

    -- Separator (before boss fight section)
    local sep_fight = panel:CreateTexture(nil, "ARTWORK")
    sep_fight:SetHeight(1)
    sep_fight:SetPoint("LEFT", panel, "LEFT", 6, 0)
    sep_fight:SetPoint("RIGHT", panel, "RIGHT", -6, 0)
    sep_fight:SetPoint("TOP", panel, "TOP", 0, y_offset)
    sep_fight:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    y_offset = y_offset - 6

    -- Rotation selector section
    local rot_label = panel:CreateFontString(nil, "OVERLAY")
    rot_label:SetPoint("TOP", panel, "TOP", 0, y_offset)
    rot_label:SetFontObject(GameFontHighlightSmall)
    rot_label:SetText("Practice Rotation")
    y_offset = y_offset - 14

    panel.rot_buttons = {}

    local rot_grid = {
        { "auto", "1/2" },
        { "2/3",  "2/4" },
    }
    local rot_labels = {
        auto = "Raid Pull", ["1/2"] = "1/2", ["2/3"] = "2/3", ["2/4"] = "2/4",
    }

    local rot_btn_w, rot_btn_h = 88, 20
    local rot_btn_spacing = 2
    local rot_total_w = 2 * rot_btn_w + 1 * rot_btn_spacing

    for row_i, row in ipairs(rot_grid) do
        for col_i, rot_key in ipairs(row) do
            local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
            btn:SetSize(rot_btn_w, rot_btn_h)
            local bx = -rot_total_w / 2 + (col_i - 1) * (rot_btn_w + rot_btn_spacing) + rot_btn_w / 2
            local by = y_offset - (row_i - 1) * (rot_btn_h + rot_btn_spacing)
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
            btn.label:SetText(rot_labels[rot_key] or rot_key)

            btn.rot_key = rot_key
            btn:SetScript("OnClick", function(self)
                if self.rot_key == "auto" then
                    st.practice.set_locked_rotation(nil)
                else
                    st.practice.set_locked_rotation(self.rot_key)
                end
            end)

            panel.rot_buttons[rot_key] = btn
        end
    end

    y_offset = y_offset - (#rot_grid * (rot_btn_h + rot_btn_spacing) + 4)

    -- Separator (before boss fight section)
    local sep_rot = panel:CreateTexture(nil, "ARTWORK")
    sep_rot:SetHeight(1)
    sep_rot:SetPoint("LEFT", panel, "LEFT", 6, 0)
    sep_rot:SetPoint("RIGHT", panel, "RIGHT", -6, 0)
    sep_rot:SetPoint("TOP", panel, "TOP", 0, y_offset)
    sep_rot:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    y_offset = y_offset - 6

    -- Boss fight section
    -- Fight timer text (visible only during fights, placed above the button)
    panel.fight_timer_text = panel:CreateFontString(nil, "OVERLAY")
    panel.fight_timer_text:SetPoint("TOP", panel, "TOP", 0, y_offset)
    panel.fight_timer_text:SetFontObject(GameFontHighlightSmall)
    panel.fight_timer_text:SetText("")
    y_offset = y_offset - 14

    -- Start/Stop Fight button
    panel.fight_btn = create_toggle_button(panel, "Start Fight", y_offset, function(self)
        if st.practice.sim.fight_active then
            st.practice.stop_fight()
        else
            st.practice.start_fight()
        end
    end)
    panel.fight_btn:ClearAllPoints()
    panel.fight_btn:SetPoint("TOP", panel, "TOP", 0, y_offset)

    y_offset = y_offset - 28

    -- Timeline toggle button
    panel.timeline_btn = create_toggle_button(panel, "Timeline", y_offset, function(self)
        st.practice.toggle_timeline()
    end)
    panel.timeline_btn:ClearAllPoints()
    panel.timeline_btn:SetPoint("TOP", panel, "TOP", 0, y_offset)

    y_offset = y_offset - 28

    -- Resize panel to fit content
    panel:SetHeight(math.abs(y_offset) + 8)

    -- OnUpdate for simulation ticks
    panel:SetScript("OnUpdate", function(self, elapsed)
        if not st.practice.active then return end
        st.practice.sim_update(elapsed)
    end)

    panel:Hide()
    st.practice.control_frame = panel
end

--=========================================================================================
-- Start / Stop / Toggle
--=========================================================================================
st.practice.toggle = function()
    if st.practice.active then
        st.practice.stop()
    else
        st.practice.start()
    end
end

st.practice.start = function()
    if st.practice.active then return end

    -- Hook functions: save originals then replace
    st.practice.orig.should_show_bar = st.bar.should_show_bar
    st.bar.should_show_bar = function()
        if st.practice.active then return true end
        return st.practice.orig.should_show_bar()
    end

    st.practice.orig.update_weapon_speed = st.player.update_weapon_speed
    st.player.update_weapon_speed = function()
        if st.practice.active then return end
        st.practice.orig.update_weapon_speed()
    end

    st.practice.orig.parse_auras = st.player.parse_auras
    st.player.parse_auras = function()
        if st.practice.active then
            st.practice.sync_state_to_player()
            return
        end
        st.practice.orig.parse_auras()
    end

    st.practice.orig.calculate_spell_GCD_duration = st.player.calculate_spell_GCD_duration
    st.player.calculate_spell_GCD_duration = function()
        if st.practice.active then
            st.player.spell_gcd_duration = st.practice.sim.effective_gcd
            return st.practice.sim.effective_gcd
        end
        return st.practice.orig.calculate_spell_GCD_duration()
    end

    st.practice.orig.process_possible_spell_cooldown = st.player.process_possible_spell_cooldown
    st.player.process_possible_spell_cooldown = function(force_flag)
        if st.practice.active then return end
        st.practice.orig.process_possible_spell_cooldown(force_flag)
    end

    -- Hook update_swing_timer to gate on fight_active
    st.practice.orig.update_swing_timer = st.player.update_swing_timer
    st.player.update_swing_timer = function(elapsed)
        if st.practice.active then
            if not st.practice.sim.fight_active then return end
        end
        st.practice.orig.update_swing_timer(elapsed)
    end

    -- Hook process_gcd_end to fire queued spells
    st.practice.orig.process_gcd_end = st.player.process_gcd_end
    st.player.process_gcd_end = function()
        st.practice.orig.process_gcd_end()
        if st.practice.active then
            st.practice.process_spell_queue()
        end
    end

    -- Activate practice mode
    st.practice.active = true
    -- Don't set is_attacking yet — wait for "Start Fight"

    -- Reset sim state
    st.practice.reset_sim_state()

    -- Calculate effective speed/GCD with current haste settings
    st.practice.recalc_speed()

    -- Force bar visible (but not ticking yet)
    st.bar.show_or_hide_bar()

    -- Restore persisted bar mappings from DB
    local saved_mappings = ST.db.profile.practice_bar_mappings
    if saved_mappings then
        for key, mapping in pairs(saved_mappings) do
            if not st.practice.bar_mappings[key] then
                st.practice.bar_mappings[key] = { slot = mapping.slot, frame_name = mapping.frame_name }
            end
        end
    end

    -- Auto-detect keybinds & bar mappings if none are saved yet
    local has_mappings = false
    for _ in pairs(st.practice.bar_mappings) do has_mappings = true; break end
    if not has_mappings then
        st.practice.auto_detect_keybinds()
    end

    -- Create action bar overlays for any existing mappings
    st.practice.create_all_bar_overlays()

    -- Create proc icons (dimmed/desaturated for positioning before fight starts)
    local db = ST.db.profile
    if db.practice_dst_enabled then
        local dst_tex = GetItemIcon(28830) or "Interface\\Icons\\INV_Misc_Bone_06"
        local dst_frame = st.practice.create_proc_icon("dst", dst_tex, -30, 150)
        dst_frame.icon:SetDesaturated(true)
        dst_frame:SetAlpha(0.4)
        dst_frame:Show()
    end
    do
        local bl_tex = select(3, GetSpellInfo(2825)) or "Interface\\Icons\\Spell_Nature_Bloodlust"
        local bl_frame = st.practice.create_proc_icon("bl", bl_tex, 30, 150)
        bl_frame.icon:SetDesaturated(true)
        bl_frame:SetAlpha(0.4)
        bl_frame:Show()
    end

    -- Apply keybind overrides
    st.practice.rebind_keys()

    -- Show control panel
    if st.practice.control_frame then
        st.practice.control_frame:Show()
        st.practice.update_info_display()
        st.practice.update_keybind_labels()
    end

    -- Restore rotation lock visuals if a rotation was previously locked
    if st.practice.locked_rotation then
        local saved = st.practice.locked_rotation
        st.practice.locked_rotation = nil  -- Clear so set_locked_rotation doesn't toggle off
        st.practice.set_locked_rotation(saved)
    end

    -- Show rotation display
    st.practice.current_display_rotation = nil
    st.practice.display_rotation_sequence = {}
    st.practice.update_rotation_display()

    print("Practice Mode |cFF00FF00started|r. Use keybinds to practice seal twisting. Type |cFF00FF00/st practice|r to stop.")
end

st.practice.stop = function()
    if not st.practice.active then return end

    -- Cancel any active key capture or linking
    st.practice.cancel_key_capture()
    st.practice.cancel_linking()

    -- Stop boss fight if active
    if st.practice.sim.fight_active then
        st.practice.stop_fight()
    end

    -- Hide all proc icons
    if st.practice.proc_icons then
        for _, frame in pairs(st.practice.proc_icons) do
            frame:Hide()
        end
    end

    -- Remove all action bar overlays
    st.practice.remove_all_bar_overlays()

    -- Deactivate
    st.practice.active = false

    -- Restore all hooked functions
    if st.practice.orig.should_show_bar then
        st.bar.should_show_bar = st.practice.orig.should_show_bar
    end
    if st.practice.orig.update_weapon_speed then
        st.player.update_weapon_speed = st.practice.orig.update_weapon_speed
    end
    if st.practice.orig.parse_auras then
        st.player.parse_auras = st.practice.orig.parse_auras
    end
    if st.practice.orig.calculate_spell_GCD_duration then
        st.player.calculate_spell_GCD_duration = st.practice.orig.calculate_spell_GCD_duration
    end
    if st.practice.orig.process_possible_spell_cooldown then
        st.player.process_possible_spell_cooldown = st.practice.orig.process_possible_spell_cooldown
    end
    if st.practice.orig.update_swing_timer then
        st.player.update_swing_timer = st.practice.orig.update_swing_timer
    end
    if st.practice.orig.process_gcd_end then
        st.player.process_gcd_end = st.practice.orig.process_gcd_end
    end
    st.practice.orig = {}

    -- Clear keybind overrides
    if st.practice.control_frame then
        ClearOverrideBindings(st.practice.control_frame)
    end

    -- Reset player state
    st.player.is_attacking = false
    st.player.swing_timer = 0.00001
    st.player.n_active_seals = 0
    st.player.active_seals = {}
    st.player.seal_1_label = nil
    st.player.seal_2_label = nil
    st.player.has_bloodlust = false
    st.player.has_breath_haste = false
    st.player.gcd_lockout = false
    st.player.active_gcd_remaining = 0

    -- Clear judgement tracking state
    st.player.judgement_being_tracked = false
    st.player.judgement_cd_remaining = 0
    st.player.judgement_on_cooldown = false
    if st.bar.frame and st.bar.frame.judgement_line then
        st.bar.frame.judgement_line:Hide()
    end

    -- Restore real weapon speed and GCD
    st.player.update_weapon_speed()
    st.player.calculate_spell_GCD_duration()

    -- Hide practice UI
    if st.practice.control_frame then
        st.practice.control_frame:Hide()
    end
    if st.practice.result_frame then
        st.practice.result_visible = false
        st.practice.result_frame:SetAlpha(0)
    end

    -- Hide rotation display
    if st.practice.rotation_display then
        st.practice.rotation_display:Hide()
    end
    st.practice.current_display_rotation = nil
    st.practice.display_rotation_sequence = {}

    -- Hide timeline
    if st.practice.timeline_frame then
        st.practice.timeline_frame:Hide()
    end
    st.practice.timeline_visible = false

    -- Let normal bar visibility take over
    st.bar.show_or_hide_bar()
    st.bar.update_bar_on_aura_change()

    print("Practice Mode |cFFFF0000stopped|r.")
end

--=========================================================================================
-- Sim State Reset
--=========================================================================================
st.practice.reset_sim_state = function()
    local sim = st.practice.sim
    sim.active_seals = {}
    sim.n_active_seals = 0
    sim.seal_1_label = nil
    sim.seal_2_label = nil
    sim.fading_seal_label = nil
    sim.fading_seal_expires = 0

    sim.has_bloodlust = false
    sim.has_haste_pot = false
    sim.bl_buff_expires = 0
    sim.haste_pot_buff_expires = 0

    sim.cs_cooldown_expires = 0
    sim.judge_cooldown_expires = 0
    sim.consec_cooldown_expires = 0
    sim.aw_cooldown_expires = 0
    sim.aw_buff_expires = 0

    -- Reset fight state
    sim.fight_active = false
    sim.fight_start_time = 0
    sim.fight_bl_delay = 0
    sim.fight_bl_fired = false

    -- Reset stopattack and twist tracking state
    sim.attack_paused = false
    sim.attack_pause_pending = false
    sim.swing_held = false
    sim.twist_attempted = false

    -- Reset spell queue
    sim.queued_ability = nil
    sim.queue_timestamp = 0

    -- Reset haste toggle buttons visually
    if st.practice.control_frame then
        local panel = st.practice.control_frame
        if panel.bl_btn then
            panel.bl_btn.active = false
            panel.bl_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.bl_btn.label:SetText("Bloodlust")
            if panel.bl_btn.countdown then panel.bl_btn.countdown:SetText("") end
        end
        if panel.hp_btn then
            panel.hp_btn.active = false
            panel.hp_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.hp_btn.label:SetText("Haste Pot")
            if panel.hp_btn.countdown then panel.hp_btn.countdown:SetText("") end
        end
        if panel.fight_btn then
            panel.fight_btn.label:SetText("Start Fight")
            panel.fight_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        end
        if panel.fight_timer_text then
            panel.fight_timer_text:SetText("")
        end
    end
end

--=========================================================================================
-- Rotation Lock
--=========================================================================================
st.practice.set_haste_buttons_enabled = function(enabled)
    local panel = st.practice.control_frame
    if not panel then return end
    if enabled then
        if panel.bl_btn then
            panel.bl_btn:SetAlpha(1.0)
            panel.bl_btn:EnableMouse(true)
        end
        if panel.hp_btn then
            panel.hp_btn:SetAlpha(1.0)
            panel.hp_btn:EnableMouse(true)
        end
    else
        if panel.bl_btn then
            panel.bl_btn:SetAlpha(0.4)
            panel.bl_btn:EnableMouse(false)
        end
        if panel.hp_btn then
            panel.hp_btn:SetAlpha(0.4)
            panel.hp_btn:EnableMouse(false)
        end
    end
end

st.practice.set_locked_rotation = function(rot_key)
    -- Toggle: clicking the already-selected rotation reverts to Auto
    if rot_key and rot_key == st.practice.locked_rotation then
        rot_key = nil
    end

    st.practice.locked_rotation = rot_key

    -- Update selector button visuals
    local panel = st.practice.control_frame
    if panel and panel.rot_buttons then
        local lbl = {
            auto = "Raid Pull", ["1/2"] = "1/2", ["2/3"] = "2/3", ["2/4"] = "2/4",
        }
        for key, btn in pairs(panel.rot_buttons) do
            local is_active = (key == "auto" and rot_key == nil) or (key == rot_key)
            if is_active then
                btn:SetBackdropColor(0.1, 0.4, 0.1, 0.9)
                btn.label:SetText("|cFF00FF00" .. (lbl[key] or key) .. "|r")
            else
                btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
                btn.label:SetText(lbl[key] or key)
            end
        end
    end

    if rot_key then
        -- Locking: deactivate all haste effects
        local sim = st.practice.sim
        if sim.has_bloodlust then st.practice.deactivate_bloodlust() end
        if sim.has_haste_pot then st.practice.deactivate_haste_pot() end
        if sim.has_abacus then st.practice.deactivate_abacus() end
        if sim.has_dst then st.practice.deactivate_dst() end

        -- Disable haste buttons
        st.practice.set_haste_buttons_enabled(false)
    else
        -- Unlocking: re-enable haste buttons
        st.practice.set_haste_buttons_enabled(true)
    end

    st.practice.recalc_speed()

    -- Force rotation display update
    st.practice.current_display_rotation = nil
    st.practice.update_rotation_display()
end

--=========================================================================================
-- Keybind System
--=========================================================================================
st.practice.rebind_keys = function()
    if not st.practice.control_frame then return end
    local owner = st.practice.control_frame
    ClearOverrideBindings(owner)

    if not st.practice.active then return end

    local db = ST.db.profile
    for _, key in ipairs(ability_order) do
        local bind_key = db[keybind_db_keys[key]]
        if bind_key and bind_key ~= "" then
            local btn_name = "SwedgeTimerPrac" .. key
            SetOverrideBindingClick(owner, false, bind_key, btn_name)
        end
    end

    st.practice.update_keybind_labels()
end

st.practice.update_keybind_labels = function()
    if not st.practice.control_frame or not st.practice.control_frame.ability_icons then return end
    local db = ST.db.profile
    for _, key in ipairs(ability_order) do
        local icon = st.practice.control_frame.ability_icons[key]
        if icon and icon.keybind_text then
            icon.keybind_text:SetText(shorten_keybind(db[keybind_db_keys[key]]))
        end
    end
end

--=========================================================================================
-- Speed / GCD Recalculation
--=========================================================================================
st.practice.recalc_speed = function()
    local db = ST.db.profile
    local sim = st.practice.sim

    -- If rotation is locked, use preset speed/gcd directly
    if st.practice.locked_rotation then
        local preset = st.practice.rotation_presets[st.practice.locked_rotation]
        if preset then
            sim.effective_speed = preset.speed
            sim.effective_gcd = preset.gcd

            -- Inject into player state
            st.player.current_weapon_speed = preset.speed
            st.player.prev_weapon_speed = preset.speed
            st.player.spell_gcd_duration = preset.gcd
            st.player.has_bloodlust = false
            st.player.has_breath_haste = false

            -- Update bar markers
            st.bar.set_marker_offsets()

            -- Rescale existing swing timer if active
            if st.practice.active and st.player.swing_timer > preset.speed then
                st.player.swing_timer = preset.speed
            end

            -- Update info display
            st.practice.update_info_display()
            return
        end
    end

    -- Base weapon speed
    local base_speed = db.practice_weapon_speed
    if base_speed <= 0 then
        base_speed = UnitAttackSpeed("player") or 3.5
    end

    -- Apply haste
    local speed = base_speed
    local gcd = 1.5

    -- Sum haste rating from all sources (additive within rating category)
    local total_haste_rating = 0
    if sim.has_haste_pot then total_haste_rating = total_haste_rating + 400 end
    if sim.has_dst then total_haste_rating = total_haste_rating + 325 end
    if sim.has_abacus then total_haste_rating = total_haste_rating + 260 end

    -- Convert rating to percentage (15.77 rating per 1% at level 70)
    local haste_from_rating = total_haste_rating / 15.77 / 100
    speed = speed / (1 + haste_from_rating)
    gcd = gcd / (1 + haste_from_rating)

    -- Bloodlust is a separate multiplicative category
    if sim.has_bloodlust then
        speed = speed / 1.3
        gcd = gcd / 1.3
    end
    gcd = math.max(1.0, gcd)

    -- Round to 3dp
    speed = math.floor(speed * 1000 + 0.5) / 1000
    gcd = math.floor(gcd * 1000 + 0.5) / 1000

    sim.effective_speed = speed
    sim.effective_gcd = gcd

    -- Inject into player state
    st.player.current_weapon_speed = speed
    st.player.prev_weapon_speed = speed
    st.player.spell_gcd_duration = gcd
    st.player.has_bloodlust = sim.has_bloodlust
    st.player.has_breath_haste = false

    -- Update bar markers
    st.bar.set_marker_offsets()

    -- Rescale existing swing timer if active
    if st.practice.active and st.player.swing_timer > speed then
        st.player.swing_timer = speed
    end

    -- Update info display
    st.practice.update_info_display()
end

--=========================================================================================
-- Rotation Calculation (simulated)
--=========================================================================================
st.practice.determine_rotation = function()
    if st.practice.locked_rotation then
        return st.practice.locked_rotation
    end
    local sim = st.practice.sim
    local attackSpeed = sim.effective_speed
    local gcd = sim.effective_gcd
    local haste = 1.5 - gcd

    if attackSpeed > 2.6 then
        return "1/2"
    elseif attackSpeed >= math.max(1.9, 2 * gcd - 0.35) and haste > 0.1 then
        return "2/3"
    elseif attackSpeed >= 2.4 or (attackSpeed >= 2.3 and haste > 0.05) then
        return "2/2/5"
    elseif attackSpeed >= math.max(1.5, 1.5 * gcd + 0.05) and haste > 0.1 then
        return "2/4"
    elseif attackSpeed >= 1.9 then
        return "1/3"
    elseif attackSpeed >= (gcd + 0.07) then
        return "2/5_blood"
    elseif attackSpeed > 1.0 then
        return "2/5_command"
    elseif attackSpeed >= 0.01 then
        return "2007"
    end
    return nil
end

--=========================================================================================
-- Center-Screen Rotation Display
--=========================================================================================

-- Create a single rotation display icon (same visual pattern as bar.lua rotation icons)
st.practice.create_rotation_display_icon = function(index, parent, size)
    local icon_frame = CreateFrame("Frame", addon_name .. "PracticeRotIcon" .. index, parent)
    icon_frame:SetSize(size, size)

    -- Subtle dark border behind the icon (game-style)
    icon_frame.border = icon_frame:CreateTexture(nil, "BACKGROUND")
    icon_frame.border:SetPoint("TOPLEFT", -1, 1)
    icon_frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    icon_frame.border:SetColorTexture(0, 0, 0, 0.8)

    -- Main icon texture
    icon_frame.texture = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.texture:SetAllPoints()
    icon_frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- For twist icons: left half texture (Command)
    icon_frame.twist_left = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.twist_left:SetPoint("TOPLEFT", 0, 0)
    icon_frame.twist_left:SetPoint("BOTTOMLEFT", 0, 0)
    icon_frame.twist_left:SetWidth(size / 2)
    icon_frame.twist_left:SetTexCoord(0.07, 0.5, 0.07, 0.93)
    icon_frame.twist_left:Hide()

    -- For twist icons: right half texture (Blood)
    icon_frame.twist_right = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.twist_right:SetPoint("TOPRIGHT", 0, 0)
    icon_frame.twist_right:SetPoint("BOTTOMRIGHT", 0, 0)
    icon_frame.twist_right:SetWidth(size / 2)
    icon_frame.twist_right:SetTexCoord(0.5, 0.93, 0.07, 0.93)
    icon_frame.twist_right:Hide()

    icon_frame:Hide()
    return icon_frame
end

-- Create the center-screen rotation display frame (free-floating, no box)
st.practice.create_rotation_display = function()
    local db = ST.db.profile
    local size = db.practice_rotation_display_icon_size

    -- Invisible anchor frame for dragging and positioning
    local frame = CreateFrame("Frame", addon_name .. "PracticeRotationDisplay", UIParent)
    frame:SetSize(300, 100)
    frame:SetPoint("CENTER", UIParent, "CENTER", db.practice_rotation_display_x, db.practice_rotation_display_y)
    frame:SetFrameStrata("HIGH")

    -- Make moveable/draggable with position persistence
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        ST.db.profile.practice_rotation_display_x = math.floor(cx - ux + 0.5)
        ST.db.profile.practice_rotation_display_y = math.floor(cy - uy + 0.5)
    end)

    -- Rotation name text (gold, top — the main label)
    frame.rotation_name = frame:CreateFontString(nil, "OVERLAY")
    frame.rotation_name:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    frame.rotation_name:SetPoint("BOTTOM", frame, "CENTER", 0, size / 2 + 4)
    frame.rotation_name:SetTextColor(1, 0.82, 0, 1)
    frame.rotation_name:SetShadowColor(0, 0, 0, 1)
    frame.rotation_name:SetShadowOffset(1, -1)
    frame.rotation_name:SetText("")

    -- Description text (muted, below icons)
    frame.desc_text = frame:CreateFontString(nil, "OVERLAY")
    frame.desc_text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    frame.desc_text:SetPoint("TOP", frame, "CENTER", 0, -(size / 2 + 4))
    frame.desc_text:SetTextColor(0.65, 0.65, 0.65, 1)
    frame.desc_text:SetShadowColor(0, 0, 0, 1)
    frame.desc_text:SetShadowOffset(1, -1)
    frame.desc_text:SetText("")

    -- Create icon frames (parented to the anchor, positioned at center)
    st.practice.rotation_display_icons = {}
    for i = 1, st.practice.rotation_display_max_icons do
        local icon = st.practice.create_rotation_display_icon(i, frame, size)
        st.practice.rotation_display_icons[i] = icon
    end

    frame:Hide()
    st.practice.rotation_display = frame
end

-- Track the active rotation and log rotation-change bands to the timeline.
-- This must run regardless of whether the rotation display HUD is enabled — the
-- timeline's colored bands and wrong/correct grading are built from these bands.
st.practice.update_rotation_tracking = function()
    if not st.practice.active then return end

    local rotation = st.practice.determine_rotation()
    if not rotation then return end

    if rotation ~= st.practice.current_display_rotation then
        st.practice.current_display_rotation = rotation
        st.practice.display_rotation_sequence = st.rotation.sequences[rotation] or {}

        -- Log rotation change to timeline bands
        local sim = st.practice.sim
        if sim.fight_active then
            local t = GetTime() - sim.fight_start_time
            st.practice.timeline_rotation_band_count = st.practice.timeline_rotation_band_count + 1
            st.practice.timeline_rotation_bands[st.practice.timeline_rotation_band_count] = {
                start_time = t,
                rotation = rotation,
            }
            st.practice.timeline_needs_render = true
        end
    end
end

-- Update the rotation display: texts and icons (static reference, no step tracking)
st.practice.update_rotation_display = function()
    -- Rotation tracking is baked in and independent of the HUD toggle
    st.practice.update_rotation_tracking()

    local frame = st.practice.rotation_display
    if not frame then return end

    local db = ST.db.profile
    if not db.practice_rotation_display_enabled or not st.practice.active then
        if frame:IsShown() then
            frame:Hide()
        end
        return
    end

    local rotation = st.practice.current_display_rotation
    if not rotation then
        if frame:IsShown() then
            frame:Hide()
        end
        return
    end

    local sequence = st.practice.display_rotation_sequence
    local num_icons = #sequence
    if num_icons == 0 then
        if frame:IsShown() then
            frame:Hide()
        end
        return
    end

    frame:Show()

    -- Update text elements
    frame.rotation_name:SetText(st.rotation.display_names[rotation] or rotation)
    frame.desc_text:SetText(st.rotation.descriptions[rotation] or "")

    -- Icon sizing and positioning (centered horizontally on the frame)
    local size = db.practice_rotation_display_icon_size
    local spacing = db.practice_rotation_display_icon_spacing
    local total_width = (size * num_icons) + (spacing * (num_icons - 1))
    local start_x = -total_width / 2 + size / 2

    -- Reanchor text to track icon layout
    frame.rotation_name:ClearAllPoints()
    frame.rotation_name:SetPoint("BOTTOM", frame, "CENTER", 0, size / 2 + 4)
    frame.desc_text:ClearAllPoints()
    frame.desc_text:SetPoint("TOP", frame, "CENTER", 0, -(size / 2 + 4))

    -- Resize frame to fit
    frame:SetSize(math.max(total_width + 20, 100), size + 50)

    for i = 1, st.practice.rotation_display_max_icons do
        local icon_frame = st.practice.rotation_display_icons[i]
        if i <= num_icons then
            -- Size
            icon_frame:SetSize(size, size)
            icon_frame.twist_left:SetWidth(size / 2)
            icon_frame.twist_right:SetWidth(size / 2)

            -- Position (centered on frame)
            icon_frame:ClearAllPoints()
            local x_pos = start_x + (i - 1) * (size + spacing)
            icon_frame:SetPoint("CENTER", frame, "CENTER", x_pos, 0)

            -- Set texture using the existing bar utility
            st.bar.set_rotation_icon_texture(icon_frame, sequence[i])

            -- Static full brightness (no step tracking)
            icon_frame.texture:SetVertexColor(1, 1, 1, 1)
            icon_frame.twist_left:SetVertexColor(1, 1, 1, 1)
            icon_frame.twist_right:SetVertexColor(1, 1, 1, 1)
            icon_frame:SetAlpha(1)

            icon_frame:Show()
        else
            icon_frame:Hide()
        end
    end
end

--=========================================================================================
-- Fight Timeline
--=========================================================================================

-- Swing correctness helpers
local function classify_swing_event(event)
    if event.result == "twist" then
        return "twist"
    elseif event.seal_active == "blood" then
        return "blood_auto"
    elseif event.seal_active == "command" then
        return "cmd_auto"
    else
        return "no_seal"
    end
end

-- Human-readable labels for tooltip display
local swing_action_labels = {
    blood_auto = "Seal of Blood auto",
    cmd_auto = "Seal of Command auto",
    twist = "Twist",
    no_seal = "Auto (no seal)",
    cs = "Crusader Strike + SoB auto",
    judge_blood = "Judge (Seal of Blood)",
    judge_command = "Judge (Seal of Command)",
}

-- CS segment expected patterns (derived from rotation sequences, strip cs/cs_late, add implicit auto)
local cs_segment_patterns = {
    ["1/2"] = {"blood_auto", "twist"},
    ["2/3"] = {"blood_auto", "twist", "twist"},
    ["1/3"] = {"blood_auto", "blood_auto", "twist"},
    ["2/4"] = {"blood_auto", "twist", "blood_auto", "twist"},
    ["2/5_blood"] = {"blood_auto", "blood_auto", "twist", "blood_auto", "twist"},
    ["2/5_command"] = {"cmd_auto", "cmd_auto", "twist", "cmd_auto", "twist"},
    ["2/2/5"] = {
        {"blood_auto", "twist"},
        {"blood_auto", "blood_auto", "twist"},
    },
    ["2007"] = {"blood_auto", "blood_auto"},
}

-- Implicit auto type for each rotation (cmd_auto only for 2/5_command)
local implicit_auto_for_rotation = {
    ["1/2"] = "blood_auto",
    ["2/3"] = "blood_auto",
    ["1/3"] = "blood_auto",
    ["2/4"] = "blood_auto",
    ["2/5_blood"] = "blood_auto",
    ["2/5_command"] = "cmd_auto",
    ["2/2/5"] = "blood_auto",
    ["2007"] = "blood_auto",
}

-- Evaluate one CS-delimited segment of melee swings against the expected pattern
-- Returns results_fragment (event_index -> result) and next sub_pattern_idx
local function evaluate_segment(segment_swings, rotation, is_opener, sub_pattern_idx)
    local results_fragment = {}
    local patterns = cs_segment_patterns[rotation]
    if not patterns then
        for _, sw in ipairs(segment_swings) do
            results_fragment[sw.event_index] = { skipped = true }
        end
        return results_fragment, sub_pattern_idx
    end

    local implicit_auto = implicit_auto_for_rotation[rotation] or "blood_auto"

    -- Opener (before first CS): lenient on ordering, but limited to pattern length.
    -- Beyond pattern length, CS should have been cast — extra swings are wrong.
    if is_opener then
        -- Determine max opener length from the pattern
        local opener_pattern
        local is_alternating = (rotation == "2/2/5")
        if is_alternating then
            opener_pattern = patterns[sub_pattern_idx or 1]
        else
            opener_pattern = patterns
        end
        local max_opener = opener_pattern and #opener_pattern or 999

        for j, sw in ipairs(segment_swings) do
            local actual = sw.classified
            if j <= max_opener then
                if actual == "twist" or actual == implicit_auto then
                    results_fragment[sw.event_index] = {
                        expected = actual,
                        actual = actual,
                        correct = true,
                    }
                else
                    results_fragment[sw.event_index] = {
                        expected = implicit_auto,
                        actual = actual,
                        correct = false,
                    }
                end
            else
                -- CS should have been cast by now
                results_fragment[sw.event_index] = {
                    expected = "cs",
                    actual = actual,
                    correct = false,
                }
            end
        end
        return results_fragment, sub_pattern_idx
    end

    -- Select the expected pattern for this segment
    local pattern
    local next_sub_idx = sub_pattern_idx
    local is_alternating = (rotation == "2/2/5")

    if is_alternating then
        -- Use the current sub-pattern only (don't cycle into next)
        local idx = sub_pattern_idx or 1
        pattern = patterns[idx]
        next_sub_idx = (idx % #patterns) + 1
    else
        pattern = patterns
    end

    -- Compare position-by-position against pattern
    -- Beyond pattern length: CS should have been used — mark everything extra as wrong
    for j, sw in ipairs(segment_swings) do
        if j <= #pattern then
            local expected_action = pattern[j]
            results_fragment[sw.event_index] = {
                expected = expected_action,
                actual = sw.classified,
                correct = (expected_action == sw.classified),
            }
        else
            results_fragment[sw.event_index] = {
                expected = "cs",
                actual = sw.classified,
                correct = false,
            }
        end
    end

    return results_fragment, next_sub_idx
end

-- Analyze each melee swing against the rotation pattern using CS-anchored segments
-- Returns results[event_index] = { expected, actual, correct } or { skipped = true }
--
-- CS events act as segment boundaries. Swings between two CS casts form a segment
-- that is evaluated independently. Mistakes in one segment cannot cascade to the next.
local function analyze_swing_correctness()
    local results = {}
    local band_count = st.practice.timeline_rotation_band_count
    if band_count == 0 then return results end

    local current_band = 1
    local rotation = st.practice.timeline_rotation_bands[1].rotation
    local is_opener = true
    local sub_pattern_idx = 1
    local current_segment = {}

    local function flush_segment()
        if #current_segment > 0 then
            local fragment, next_sub = evaluate_segment(
                current_segment, rotation, is_opener, sub_pattern_idx
            )
            for idx, result in pairs(fragment) do
                results[idx] = result
            end
            sub_pattern_idx = next_sub
        end
        current_segment = {}
    end

    for i = 1, st.practice.timeline_event_count do
        local event = st.practice.timeline_events[i]

        -- Check if we crossed into a new rotation band
        if current_band < band_count then
            local next_band = st.practice.timeline_rotation_bands[current_band + 1]
            if event.time >= next_band.start_time then
                -- Evaluate current segment against OLD rotation, then reset
                flush_segment()
                current_band = current_band + 1
                rotation = next_band.rotation
                is_opener = true
                sub_pattern_idx = 1
            end
        end

        if event.lane == "cs" then
            -- CS boundary: evaluate current segment, start fresh
            flush_segment()
            is_opener = false
        elseif event.lane == "melee" then
            current_segment[#current_segment + 1] = {
                event_index = i,
                classified = classify_swing_event(event),
            }
        elseif event.lane == "judge" and event.seal_active == "command" then
            -- Judge with SoC is always wrong (independent of segment analysis)
            results[i] = {
                expected = "judge_blood",
                actual = "judge_command",
                correct = false,
            }
        end
    end

    -- Evaluate final (possibly incomplete) segment
    flush_segment()

    return results
end

-- Log a timeline event
st.practice.log_timeline_event = function(lane, texture, result, seal_active)
    local sim = st.practice.sim
    if not sim.fight_active then return end

    local t = GetTime() - sim.fight_start_time
    st.practice.timeline_event_count = st.practice.timeline_event_count + 1
    st.practice.timeline_events[st.practice.timeline_event_count] = {
        time = t,
        lane = lane,
        texture = texture,
        result = result,
        seal_active = seal_active,
    }
    if t > st.practice.timeline_max_time then
        st.practice.timeline_max_time = t
    end
    st.practice.timeline_needs_render = true
end

-- Frame pool: timeline icons
local function get_timeline_icon(parent)
    local pool = st.practice.timeline_icon_pool
    st.practice.timeline_icon_pool_used = st.practice.timeline_icon_pool_used + 1
    local idx = st.practice.timeline_icon_pool_used

    if pool[idx] then
        pool[idx]:Show()
        pool[idx].error_border:Hide()
        pool[idx].twist_overlay:Hide()
        pool[idx].analysis_data = nil
        return pool[idx]
    end

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(TIMELINE_ICON_SIZE, TIMELINE_ICON_SIZE)

    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints()
    f.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Split textures for melee+seal composite icon
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
    f.result_label:SetPoint("TOP", f, "BOTTOM", 0, 2)
    f.result_label:SetText("")

    f.error_border = f:CreateTexture(nil, "BACKGROUND")
    f.error_border:SetPoint("TOPLEFT", -2, 2)
    f.error_border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.error_border:SetColorTexture(0.8, 0.1, 0.1, 0.7)
    f.error_border:Hide()

    -- Twist overlay badge (small split Command/Blood icon at bottom-right)
    local twist_size = math.floor(TIMELINE_ICON_SIZE * 0.6)
    f.twist_overlay = CreateFrame("Frame", nil, f)
    f.twist_overlay:SetSize(twist_size, twist_size)
    f.twist_overlay:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
    f.twist_overlay:SetFrameLevel(f:GetFrameLevel() + 2)

    f.twist_overlay.left = f.twist_overlay:CreateTexture(nil, "OVERLAY", nil, 2)
    f.twist_overlay.left:SetPoint("TOPLEFT", 0, 0)
    f.twist_overlay.left:SetPoint("BOTTOMLEFT", 0, 0)
    f.twist_overlay.left:SetWidth(twist_size / 2)
    f.twist_overlay.left:SetTexCoord(0.07, 0.5, 0.07, 0.93)

    f.twist_overlay.right = f.twist_overlay:CreateTexture(nil, "OVERLAY", nil, 2)
    f.twist_overlay.right:SetPoint("TOPRIGHT", 0, 0)
    f.twist_overlay.right:SetPoint("BOTTOMRIGHT", 0, 0)
    f.twist_overlay.right:SetWidth(twist_size / 2)
    f.twist_overlay.right:SetTexCoord(0.5, 0.93, 0.07, 0.93)

    f.twist_overlay:Hide()

    -- Tooltip for incorrect actions
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if self.analysis_data and not self.analysis_data.correct then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local expected = swing_action_labels[self.analysis_data.expected] or self.analysis_data.expected
            local actual = swing_action_labels[self.analysis_data.actual] or self.analysis_data.actual
            GameTooltip:AddLine("Incorrect action", 1, 0.2, 0.2)
            GameTooltip:AddLine("You did: " .. actual, 1, 1, 1)
            GameTooltip:AddLine("Expected: " .. expected, 0, 1, 0)
            if self.analysis_data.actual == "judge_command" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Judging Rank 1 SoC is a large DPS loss.", 1, 0.5, 0.5)
            end
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    pool[idx] = f
    return f
end

local function reset_timeline_icon_pool()
    for i = 1, st.practice.timeline_icon_pool_used do
        st.practice.timeline_icon_pool[i]:Hide()
    end
    st.practice.timeline_icon_pool_used = 0
end

-- Frame pool: vertical divider lines
local function get_timeline_divider(parent)
    local pool = st.practice.timeline_divider_pool
    st.practice.timeline_divider_pool_used = st.practice.timeline_divider_pool_used + 1
    local idx = st.practice.timeline_divider_pool_used

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
    for i = 1, st.practice.timeline_divider_pool_used do
        st.practice.timeline_divider_pool[i]:Hide()
    end
    st.practice.timeline_divider_pool_used = 0
end

-- Frame pool: ruler ticks and labels
local function get_ruler_tick(parent)
    local pool = st.practice.timeline_ruler_pool.ticks
    st.practice.timeline_ruler_pool_used = st.practice.timeline_ruler_pool_used + 1
    local idx = st.practice.timeline_ruler_pool_used

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
    local pool = st.practice.timeline_ruler_pool.ticks
    for i = 1, st.practice.timeline_ruler_pool_used do
        if pool[i] then
            pool[i].tick:Hide()
            pool[i].label:Hide()
        end
    end
    st.practice.timeline_ruler_pool_used = 0
end

-- Rotation band pool functions
-- Each band entry has: bg (header), lane_tint (lanes), label, icons[]
local ROTATION_BAND_ICON_SIZE = 14
local ROTATION_BAND_ICON_SPACING = 2
local ROTATION_BAND_MAX_ICONS = 5  -- max icons per band (longest sequence)

local function get_rotation_band(parent)
    local pool = st.practice.timeline_rotation_band_pool
    st.practice.timeline_rotation_band_pool_used = st.practice.timeline_rotation_band_pool_used + 1
    local idx = st.practice.timeline_rotation_band_pool_used

    if pool[idx] then
        pool[idx].bg:Show()
        pool[idx].lane_tint:Show()
        pool[idx].label:Show()
        return pool[idx]
    end

    -- Header background
    local bg = parent:CreateTexture(nil, "ARTWORK", nil, -1)

    -- Lane tint (extends through all event rows)
    local lane_tint = parent:CreateTexture(nil, "BORDER")

    -- Rotation name label
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")

    -- Icon frames for rotation sequence
    local icons = {}
    for i = 1, ROTATION_BAND_MAX_ICONS do
        local icon_frame = CreateFrame("Frame", nil, parent)
        icon_frame:SetSize(ROTATION_BAND_ICON_SIZE, ROTATION_BAND_ICON_SIZE)

        icon_frame.texture = icon_frame:CreateTexture(nil, "OVERLAY")
        icon_frame.texture:SetAllPoints()
        icon_frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Split textures for twist icons
        icon_frame.twist_left = icon_frame:CreateTexture(nil, "OVERLAY")
        icon_frame.twist_left:SetPoint("TOPLEFT", 0, 0)
        icon_frame.twist_left:SetPoint("BOTTOMLEFT", 0, 0)
        icon_frame.twist_left:SetWidth(ROTATION_BAND_ICON_SIZE / 2)
        icon_frame.twist_left:SetTexCoord(0.07, 0.5, 0.07, 0.93)
        icon_frame.twist_left:Hide()

        icon_frame.twist_right = icon_frame:CreateTexture(nil, "OVERLAY")
        icon_frame.twist_right:SetPoint("TOPRIGHT", 0, 0)
        icon_frame.twist_right:SetPoint("BOTTOMRIGHT", 0, 0)
        icon_frame.twist_right:SetWidth(ROTATION_BAND_ICON_SIZE / 2)
        icon_frame.twist_right:SetTexCoord(0.5, 0.93, 0.07, 0.93)
        icon_frame.twist_right:Hide()

        icon_frame:Hide()
        icons[i] = icon_frame
    end

    local entry = { bg = bg, lane_tint = lane_tint, label = label, icons = icons }
    pool[idx] = entry
    return entry
end

local function reset_rotation_band_pool()
    local pool = st.practice.timeline_rotation_band_pool
    for i = 1, st.practice.timeline_rotation_band_pool_used do
        if pool[i] then
            pool[i].bg:Hide()
            pool[i].lane_tint:Hide()
            pool[i].label:Hide()
            for j = 1, ROTATION_BAND_MAX_ICONS do
                pool[i].icons[j]:Hide()
            end
        end
    end
    st.practice.timeline_rotation_band_pool_used = 0
end

-- Render rotation bands in the timeline ruler area + lane tints
local function render_timeline_rotation_bands(scroll_child, total_width, pps)
    reset_rotation_band_pool()

    local band_count = st.practice.timeline_rotation_band_count
    if band_count == 0 then return end

    local content_time = math.max(st.practice.timeline_max_time + 2, 10)
    local num_lanes = #timeline_lanes
    local lane_area_height = num_lanes * TIMELINE_LANE_HEIGHT

    -- Per-rotation colors so each rotation is visually distinct
    local rotation_colors = {
        ["1/2"]         = { 0.12, 0.25, 0.50 },  -- Blue
        ["2/3"]         = { 0.40, 0.15, 0.50 },  -- Purple
        ["1/3"]         = { 0.15, 0.40, 0.25 },  -- Green
        ["2/4"]         = { 0.50, 0.30, 0.10 },  -- Orange
        ["2/5_blood"]   = { 0.50, 0.12, 0.12 },  -- Red
        ["2/5_command"] = { 0.45, 0.45, 0.12 },  -- Yellow
        ["2/2/5"]       = { 0.15, 0.35, 0.50 },  -- Teal
        ["2007"]        = { 0.35, 0.20, 0.40 },  -- Mauve
    }
    local fallback_color = { 0.30, 0.30, 0.30 }

    for i = 1, band_count do
        local band_data = st.practice.timeline_rotation_bands[i]
        local start_x = band_data.start_time * pps
        local end_time = (i < band_count)
            and st.practice.timeline_rotation_bands[i + 1].start_time
            or content_time
        local end_x = end_time * pps
        local width = math.max(end_x - start_x, 1)

        local entry = get_rotation_band(scroll_child)
        local color = rotation_colors[band_data.rotation] or fallback_color

        -- Header background band (ruler area, moderately visible)
        entry.bg:ClearAllPoints()
        entry.bg:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", start_x, 0)
        entry.bg:SetSize(width, TIMELINE_RULER_HEIGHT)
        entry.bg:SetColorTexture(color[1], color[2], color[3], 0.55)

        -- Lane tint (very low opacity, extends through all event rows)
        entry.lane_tint:ClearAllPoints()
        entry.lane_tint:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", start_x, -TIMELINE_RULER_HEIGHT)
        entry.lane_tint:SetSize(width, lane_area_height)
        entry.lane_tint:SetColorTexture(color[1], color[2], color[3], 0.08)

        -- Rotation name label (top of header)
        local display_name = st.rotation.display_names[band_data.rotation] or band_data.rotation
        entry.label:ClearAllPoints()
        entry.label:SetPoint("TOP", entry.bg, "TOP", 0, -1)
        entry.label:SetText(display_name)
        entry.label:SetTextColor(0.9, 0.9, 0.9, 1)

        -- Rotation sequence icons (middle, between name and ruler numbers)
        local sequence = st.rotation.sequences[band_data.rotation] or {}
        local num_icons = #sequence
        local icons_total_width = (ROTATION_BAND_ICON_SIZE * num_icons) + (ROTATION_BAND_ICON_SPACING * math.max(num_icons - 1, 0))

        -- Center icons within the band
        local band_center_x = start_x + width / 2
        local icons_start_x = band_center_x - icons_total_width / 2

        -- Icons sit below the label, above the ruler numbers
        local icon_y = -14

        for j = 1, ROTATION_BAND_MAX_ICONS do
            local icon_frame = entry.icons[j]
            if j <= num_icons then
                icon_frame:ClearAllPoints()
                local ix = icons_start_x + (j - 1) * (ROTATION_BAND_ICON_SIZE + ROTATION_BAND_ICON_SPACING)
                icon_frame:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", ix, icon_y)

                -- Use the existing utility to set the icon texture
                st.bar.set_rotation_icon_texture(icon_frame, sequence[j])
                icon_frame:Show()
            else
                icon_frame:Hide()
            end
        end
    end
end

-- Render the ruler (time ticks along top of scroll child)
local function render_timeline_ruler(scroll_child, total_width, pps)
    reset_timeline_ruler_pool()

    local max_time = st.practice.timeline_max_time
    -- Tick every second
    for sec = 0, math.ceil(max_time) do
        local x = sec * pps
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

-- Main render function: full re-render from event data using frame pools
st.practice.render_timeline = function()
    st.practice.timeline_needs_render = false

    local frame = st.practice.timeline_frame
    if not frame then return end

    local db = ST.db.profile
    local pps = db.practice_timeline_pixels_per_second
    local scroll_child = frame.scroll_child
    local scroll_frame = frame.scroll_frame

    -- Calculate content width from max event time (minimum 10 seconds)
    local content_time = math.max(st.practice.timeline_max_time + 2, 10)
    local total_width = content_time * pps

    scroll_child:SetWidth(total_width)

    -- Reset all pools
    reset_timeline_icon_pool()
    reset_timeline_divider_pool()
    reset_timeline_ruler_pool()
    reset_rotation_band_pool()

    -- Render ruler
    render_timeline_rotation_bands(scroll_child, total_width, pps)
    render_timeline_ruler(scroll_child, total_width, pps)

    -- Render lane backgrounds (alternating shade)
    -- These are created once in create_timeline, just update width
    if frame.lane_bgs then
        for i, bg in ipairs(frame.lane_bgs) do
            bg:SetWidth(total_width)
        end
    end

    -- Analyze swing correctness against rotation patterns
    local swing_analysis = analyze_swing_correctness()

    -- Render events
    local num_lanes = #timeline_lanes
    for i = 1, st.practice.timeline_event_count do
        local event = st.practice.timeline_events[i]
        local lane_idx = timeline_lane_index[event.lane]
        if lane_idx then
            local x = event.time * pps
            local y = -(TIMELINE_RULER_HEIGHT + (lane_idx - 1) * TIMELINE_LANE_HEIGHT + (TIMELINE_LANE_HEIGHT - TIMELINE_ICON_SIZE) / 2)

            local icon = get_timeline_icon(scroll_child)
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", x - TIMELINE_ICON_SIZE / 2, y)

            -- Melee swings: split icon (sword left + seal right) when seal active but not a twist
            if event.lane == "melee" and event.seal_active and event.result ~= "twist" then
                icon.texture:Hide()
                icon.split_left:SetTexture(event.texture)  -- Sword (left half)
                local seal_spell = (event.seal_active == "blood") and 31892 or 20375
                icon.split_right:SetTexture(GetSpellTexture(seal_spell))  -- Seal (right half)
                icon.split_left:Show()
                icon.split_right:Show()
            else
                icon.texture:SetTexture(event.texture)
                icon.texture:Show()
                icon.split_left:Hide()
                icon.split_right:Hide()
            end

            -- Twist indicator: small split Command/Blood icon overlay
            if event.result == "twist" then
                local cmd_tex = GetSpellTexture(20375)
                local blood_tex = GetSpellTexture(31892)
                if cmd_tex and blood_tex then
                    icon.twist_overlay.left:SetTexture(cmd_tex)
                    icon.twist_overlay.right:SetTexture(blood_tex)
                    icon.twist_overlay:Show()
                end
                icon.result_label:SetText("")
                icon.result_label:Hide()
            else
                icon.twist_overlay:Hide()
                icon.result_label:SetText("")
                icon.result_label:Hide()
            end

            -- Per-swing correctness indicator + tooltip data
            if event.lane == "melee" or event.lane == "judge" then
                local analysis = swing_analysis[i]
                icon.analysis_data = analysis
                if analysis and not analysis.skipped and not analysis.correct then
                    icon.error_border:Show()
                    -- Override result label to red X
                    icon.result_label:SetText("|cFFFF3333X|r")
                    icon.result_label:Show()
                else
                    icon.error_border:Hide()
                end
            else
                icon.error_border:Hide()
                icon.analysis_data = nil
            end

            -- Swing dividers for melee lane
            if event.lane == "melee" then
                local div = get_timeline_divider(scroll_child)
                div:SetSize(1, num_lanes * TIMELINE_LANE_HEIGHT)
                div:ClearAllPoints()
                div:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", x, -TIMELINE_RULER_HEIGHT)
            end
        end
    end

    -- Update scrollbar range
    local visible_width = scroll_frame:GetWidth()
    local max_scroll = math.max(total_width - visible_width, 0)
    frame.scrollbar:SetMinMaxValues(0, max_scroll)

    -- Auto-scroll to end if enabled
    if st.practice.timeline_auto_scroll then
        frame.scrollbar:SetValue(max_scroll)
        scroll_frame:SetHorizontalScroll(max_scroll)
    end
end

-- Create the timeline frame hierarchy
st.practice.create_timeline = function()
    local db = ST.db.profile
    local num_lanes = #timeline_lanes
    local content_height = TIMELINE_RULER_HEIGHT + num_lanes * TIMELINE_LANE_HEIGHT
    local frame_height = content_height + 30  -- room for scrollbar + padding

    -- Main frame
    local frame = CreateFrame("Frame", addon_name .. "PracticeTimeline", UIParent, "BackdropTemplate")
    frame:SetSize(db.practice_timeline_width + TIMELINE_LABEL_WIDTH + 16, frame_height)
    frame:SetPoint("CENTER", UIParent, "CENTER", db.practice_timeline_x, db.practice_timeline_y)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        ST.db.profile.practice_timeline_x = math.floor(cx - ux + 0.5)
        ST.db.profile.practice_timeline_y = math.floor(cy - uy + 0.5)
    end)

    -- Close button
    local close_btn = CreateFrame("Button", nil, frame)
    close_btn:SetSize(16, 16)
    close_btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close_btn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close_btn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    close_btn:SetScript("OnClick", function()
        st.practice.toggle_timeline()
    end)

    -- Left sidebar: lane labels
    local label_area = CreateFrame("Frame", nil, frame)
    label_area:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(4 + TIMELINE_RULER_HEIGHT))
    label_area:SetSize(TIMELINE_LABEL_WIDTH, num_lanes * TIMELINE_LANE_HEIGHT)

    for i, lane in ipairs(timeline_lanes) do
        local y = -((i - 1) * TIMELINE_LANE_HEIGHT)

        -- Lane icon
        local lane_icon = label_area:CreateTexture(nil, "ARTWORK")
        lane_icon:SetSize(16, 16)
        lane_icon:SetPoint("LEFT", label_area, "TOPLEFT", 2, y - TIMELINE_LANE_HEIGHT / 2)
        lane_icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if lane.spell_id then
            lane_icon:SetTexture(GetSpellTexture(lane.spell_id))
        elseif lane.texture then
            lane_icon:SetTexture(lane.texture)
        end

        -- Lane label
        local lane_label = label_area:CreateFontString(nil, "OVERLAY")
        lane_label:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        lane_label:SetPoint("LEFT", lane_icon, "RIGHT", 3, 0)
        lane_label:SetTextColor(0.8, 0.8, 0.8, 1)
        lane_label:SetText(lane.name)
    end

    -- ScrollFrame for timeline content
    local scroll_frame = CreateFrame("ScrollFrame", addon_name .. "PracticeTimelineSF", frame)
    scroll_frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + TIMELINE_LABEL_WIDTH, -4)
    scroll_frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 18)
    frame.scroll_frame = scroll_frame

    -- Scroll child (the canvas)
    local scroll_child = CreateFrame("Frame", nil, scroll_frame)
    scroll_child:SetHeight(content_height)
    scroll_child:SetWidth(db.practice_timeline_width)
    scroll_frame:SetScrollChild(scroll_child)
    frame.scroll_child = scroll_child

    -- Lane background strips (alternating shade, on scroll child)
    frame.lane_bgs = {}
    for i = 1, num_lanes do
        local bg = scroll_child:CreateTexture(nil, "BACKGROUND")
        local shade = (i % 2 == 0) and 0.08 or 0.04
        bg:SetColorTexture(shade, shade, shade, 1)
        bg:SetHeight(TIMELINE_LANE_HEIGHT)
        bg:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", 0, -(TIMELINE_RULER_HEIGHT + (i - 1) * TIMELINE_LANE_HEIGHT))
        bg:SetWidth(db.practice_timeline_width)
        frame.lane_bgs[i] = bg
    end

    -- Horizontal scrollbar (Slider)
    local scrollbar = CreateFrame("Slider", nil, frame, "BackdropTemplate")
    scrollbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6 + TIMELINE_LABEL_WIDTH, 4)
    scrollbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4)
    scrollbar:SetHeight(12)
    scrollbar:SetMinMaxValues(0, 1)
    scrollbar:SetValue(0)
    scrollbar:SetValueStep(1)
    scrollbar:SetObeyStepOnDrag(true)
    scrollbar:SetOrientation("HORIZONTAL")
    scrollbar:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    local thumb = scrollbar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(24, 16)
    scrollbar:SetThumbTexture(thumb)

    scrollbar:SetScript("OnValueChanged", function(self, value)
        scroll_frame:SetHorizontalScroll(value)
    end)
    frame.scrollbar = scrollbar

    -- Mouse wheel → horizontal scroll
    scroll_frame:EnableMouseWheel(true)
    scroll_frame:SetScript("OnMouseWheel", function(self, delta)
        local pps = ST.db.profile.practice_timeline_pixels_per_second
        local step = pps * 2  -- scroll ~2 seconds worth per wheel tick
        local min_val, max_val = scrollbar:GetMinMaxValues()
        local cur = scrollbar:GetValue()
        local new_val = math.max(min_val, math.min(max_val, cur - delta * step))
        scrollbar:SetValue(new_val)

        -- Scrolling backward disables auto-scroll; reaching end re-enables
        if delta > 0 then
            st.practice.timeline_auto_scroll = false
        elseif new_val >= max_val then
            st.practice.timeline_auto_scroll = true
        end
    end)

    frame:Hide()
    st.practice.timeline_frame = frame
end

-- Toggle timeline visibility
st.practice.toggle_timeline = function()
    local frame = st.practice.timeline_frame
    if not frame then return end

    if st.practice.timeline_visible then
        frame:Hide()
        st.practice.timeline_visible = false
    else
        frame:Show()
        st.practice.timeline_visible = true
        st.practice.timeline_needs_render = true
    end

    -- Update toggle button visual
    local panel = st.practice.control_frame
    if panel and panel.timeline_btn then
        if st.practice.timeline_visible then
            panel.timeline_btn:SetBackdropColor(0.1, 0.3, 0.1, 0.9)
            panel.timeline_btn.label:SetText("|cFF00FF00Timeline|r")
        else
            panel.timeline_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.timeline_btn.label:SetText("Timeline")
        end
    end
end

--=========================================================================================
-- Sync Simulated State -> st.player.*
--=========================================================================================
st.practice.sync_state_to_player = function()
    local sim = st.practice.sim

    st.player.active_seals = {}
    for seal_label, _ in pairs(sim.active_seals) do
        st.player.active_seals[seal_label] = true
    end
    st.player.n_active_seals = sim.n_active_seals
    st.player.seal_1_label = sim.seal_1_label
    st.player.seal_2_label = sim.seal_2_label
    st.player.active_seal_1 = sim.seal_1_label
    st.player.active_seal_2 = sim.seal_2_label
    st.player.has_bloodlust = sim.has_bloodlust
    st.player.has_breath_haste = false
    st.player.has_dst = sim.has_dst
    st.player.has_abacus = sim.has_abacus

    -- Set seal timing data for icon cooldowns
    local now = GetTime()
    if sim.seal_1_label then
        st.player.seal_1_label = sim.seal_1_label
        if st.player.seal_1_start_time == 0 then
            st.player.seal_1_start_time = now
            st.player.seal_1_expires = now + 30
            st.player.seal_1_duration = 30
            st.player.seal_1_cooldown_set = false
        end
    else
        st.player.seal_1_label = nil
        st.player.seal_1_start_time = 0
        st.player.seal_1_expires = 0
    end
    if sim.seal_2_label then
        st.player.seal_2_label = sim.seal_2_label
        if st.player.seal_2_start_time == 0 then
            st.player.seal_2_start_time = now
            st.player.seal_2_expires = now + 30
            st.player.seal_2_duration = 30
            st.player.seal_2_cooldown_set = false
        end
    else
        st.player.seal_2_label = nil
        st.player.seal_2_start_time = 0
        st.player.seal_2_expires = 0
    end
end

--=========================================================================================
-- Timed Haste Buff Activation
--=========================================================================================
st.practice.activate_bloodlust = function()
    local sim = st.practice.sim
    if sim.has_bloodlust then return end  -- Guard against double-activation
    if st.practice.locked_rotation then return end

    sim.has_bloodlust = true
    sim.bl_buff_expires = GetTime() + 40

    st.practice.recalc_speed()

    -- Activate BL proc icon
    local bl_frame = st.practice.proc_icons and st.practice.proc_icons["bl"]
    if bl_frame then
        bl_frame:SetAlpha(1)
        bl_frame.icon:SetDesaturated(false)
        bl_frame.cooldown:SetCooldown(GetTime(), 40)
        bl_frame.countdown:SetText("40")
    end

    -- Play bloodlust sound
    local sound_path = st.bar.twist_sounds["Bloodlust"]
    if sound_path then
        PlaySoundFile(sound_path, ST.db.profile.sound_channel or "Master")
    end

    -- Update button visual
    local panel = st.practice.control_frame
    if panel and panel.bl_btn then
        panel.bl_btn.active = true
        panel.bl_btn:SetBackdropColor(0.1, 0.3, 0.6, 0.9)
        panel.bl_btn.label:SetText("|cFF00FFFFBloodlust|r")
    end
end

st.practice.deactivate_bloodlust = function()
    local sim = st.practice.sim
    sim.has_bloodlust = false
    sim.bl_buff_expires = 0

    st.practice.recalc_speed()

    -- Return BL proc icon to dimmed/desaturated state
    local bl_frame = st.practice.proc_icons and st.practice.proc_icons["bl"]
    if bl_frame then
        bl_frame:SetAlpha(0.4)
        bl_frame.icon:SetDesaturated(true)
        bl_frame.cooldown:Clear()
        bl_frame.countdown:SetText("")
    end

    -- Update button visual
    local panel = st.practice.control_frame
    if panel and panel.bl_btn then
        panel.bl_btn.active = false
        panel.bl_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        panel.bl_btn.label:SetText("Bloodlust")
        if panel.bl_btn.countdown then
            panel.bl_btn.countdown:SetText("")
        end
    end
end

st.practice.activate_haste_pot = function()
    local sim = st.practice.sim
    if sim.has_haste_pot then return end  -- Guard against double-activation
    if st.practice.locked_rotation then return end

    sim.has_haste_pot = true
    sim.haste_pot_buff_expires = GetTime() + 15

    st.practice.recalc_speed()

    -- Update button visual
    local panel = st.practice.control_frame
    if panel and panel.hp_btn then
        panel.hp_btn.active = true
        panel.hp_btn:SetBackdropColor(0.5, 0.3, 0.1, 0.9)
        panel.hp_btn.label:SetText("|cFFFF8800Haste Pot|r")
    end
end

st.practice.deactivate_haste_pot = function()
    local sim = st.practice.sim
    sim.has_haste_pot = false
    sim.haste_pot_buff_expires = 0

    st.practice.recalc_speed()

    -- Update button visual
    local panel = st.practice.control_frame
    if panel and panel.hp_btn then
        panel.hp_btn.active = false
        panel.hp_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        panel.hp_btn.label:SetText("Haste Pot")
        if panel.hp_btn.countdown then
            panel.hp_btn.countdown:SetText("")
        end
    end
end

st.practice.activate_abacus = function()
    local sim = st.practice.sim
    if sim.has_abacus then return end  -- Guard against double-activation

    sim.has_abacus = true
    sim.abacus_buff_expires = GetTime() + 10
    sim.abacus_cooldown_expires = GetTime() + 120

    st.practice.recalc_speed()

    -- Reset bar overlay flag so overlay picks up the new cooldown
    local overlay = st.practice.bar_overlays["abacus"]
    if overlay then overlay.cooldown_set = false end
end

st.practice.deactivate_abacus = function()
    local sim = st.practice.sim
    sim.has_abacus = false
    sim.abacus_buff_expires = 0

    st.practice.recalc_speed()
end

-- Shared proc icon table
st.practice.proc_icons = {}

st.practice.create_proc_icon = function(key, texture, x_offset, y_offset)
    -- Remove existing icon for this key
    if st.practice.proc_icons[key] then
        st.practice.proc_icons[key]:Hide()
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(48, 48)
    frame:SetPoint("CENTER", UIParent, "CENTER", x_offset or 0, y_offset or 150)
    frame:SetFrameStrata("HIGH")

    -- Make moveable/draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetClampedToScreen(true)

    -- Border (matches rotation display icon style)
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border:SetColorTexture(0, 0, 0, 0.8)

    -- Icon texture
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(texture)
    frame.icon = icon

    -- Cooldown swipe
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    frame.cooldown = cooldown

    -- Countdown text
    local countdown = frame:CreateFontString(nil, "OVERLAY")
    countdown:SetPoint("BOTTOM", frame, "BOTTOM", 0, -14)
    countdown:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    countdown:SetTextColor(1, 1, 1, 1)
    frame.countdown = countdown

    st.practice.proc_icons[key] = frame
    return frame
end

st.practice.activate_dst = function()
    local sim = st.practice.sim
    if sim.has_dst then return end  -- Guard against double-activation

    sim.has_dst = true
    sim.dst_buff_expires = GetTime() + 10
    sim.dst_icd_expires = GetTime() + 20

    st.practice.recalc_speed()

    -- Activate DST proc icon
    local frame = st.practice.proc_icons and st.practice.proc_icons["dst"]
    if frame then
        frame:SetAlpha(1)
        frame.icon:SetDesaturated(false)
        frame.cooldown:SetCooldown(GetTime(), 10)
        frame.countdown:SetText("10")
    end
end

st.practice.deactivate_dst = function()
    local sim = st.practice.sim
    sim.has_dst = false
    sim.dst_buff_expires = 0

    st.practice.recalc_speed()

    -- Return DST proc icon to dimmed/desaturated state
    local frame = st.practice.proc_icons and st.practice.proc_icons["dst"]
    if frame then
        frame:SetAlpha(0.4)
        frame.icon:SetDesaturated(true)
        frame.cooldown:Clear()
        frame.countdown:SetText("")
    end
end

--=========================================================================================
-- Boss Fight Mode
--=========================================================================================
st.practice.start_fight = function()
    local sim = st.practice.sim
    if sim.fight_active then return end

    local db = ST.db.profile
    sim.fight_active = true
    sim.fight_start_time = GetTime()
    sim.fight_bl_delay = db.practice_bl_delay
    sim.fight_bl_fired = st.practice.locked_rotation and true or false
    sim.attack_paused = false
    sim.attack_pause_pending = false
    sim.queued_ability = nil
    sim.queue_timestamp = 0

    -- Start the swing timer (was deferred from start())
    st.player.is_attacking = true
    st.player.reset_swing_timer()

    -- Start fight with Seal of Blood active
    sim.active_seals = {}
    sim.active_seals["blood"] = true
    sim.n_active_seals = 1
    sim.seal_1_label = "blood"
    sim.seal_2_label = nil
    sim.fading_seal_label = nil
    sim.fading_seal_expires = 0
    st.practice.sync_state_to_player()
    st.player.seal_1_cooldown_set = false
    for _, seal_key in ipairs({"soc", "sob", "sotc"}) do
        local overlay = st.practice.bar_overlays[seal_key]
        if overlay then overlay.cooldown_set = false end
    end
    st.bar.update_bar_on_aura_change()

    -- If BL delay is 0, fire immediately (skip if rotation is locked)
    if not st.practice.locked_rotation and sim.fight_bl_delay == 0 then
        sim.fight_bl_fired = true
        st.practice.activate_bloodlust()
    end

    -- Update button visual
    local panel = st.practice.control_frame
    if panel and panel.fight_btn then
        panel.fight_btn.label:SetText("|cFFFF0000Stop Fight|r")
        panel.fight_btn:SetBackdropColor(0.4, 0.1, 0.1, 0.9)
    end

    -- Gray out manual BL button during fight (skip if already disabled by rotation lock)
    if not st.practice.locked_rotation and panel and panel.bl_btn then
        panel.bl_btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    end

    -- Clear timeline data and show timeline if enabled
    st.practice.timeline_events = {}
    st.practice.timeline_event_count = 0
    st.practice.timeline_max_time = 0
    st.practice.timeline_auto_scroll = true
    st.practice.timeline_needs_render = true

    -- Clear and initialize rotation bands
    st.practice.timeline_rotation_bands = {}
    st.practice.timeline_rotation_band_count = 0
    local initial_rot = st.practice.determine_rotation()
    if initial_rot then
        st.practice.timeline_rotation_band_count = 1
        st.practice.timeline_rotation_bands[1] = {
            start_time = 0,
            rotation = initial_rot,
        }
    end

    if db.practice_timeline_enabled and st.practice.timeline_frame then
        if db.practice_timeline_mode ~= "after_twist" then
            st.practice.timeline_frame:Show()
            st.practice.timeline_visible = true
            -- Update toggle button visual
            if panel and panel.timeline_btn then
                panel.timeline_btn:SetBackdropColor(0.1, 0.3, 0.1, 0.9)
                panel.timeline_btn.label:SetText("|cFF00FF00Timeline|r")
            end
        end
    end
end

st.practice.stop_fight = function()
    local sim = st.practice.sim
    if not sim.fight_active then return end

    sim.queued_ability = nil
    sim.queue_timestamp = 0
    sim.fight_active = false
    sim.fight_start_time = 0
    sim.fight_bl_delay = 0
    sim.fight_bl_fired = false
    sim.attack_paused = false
    sim.attack_pause_pending = false
    sim.swing_held = false

    -- Deactivate timed buffs
    if sim.has_bloodlust then st.practice.deactivate_bloodlust() end
    if sim.has_haste_pot then st.practice.deactivate_haste_pot() end
    if sim.has_abacus then st.practice.deactivate_abacus() end
    if sim.has_dst then st.practice.deactivate_dst() end

    -- Reset all cooldowns
    sim.cs_cooldown_expires = 0
    sim.judge_cooldown_expires = 0
    sim.consec_cooldown_expires = 0
    sim.aw_cooldown_expires = 0
    sim.aw_buff_expires = 0
    sim.abacus_cooldown_expires = 0
    sim.dst_icd_expires = 0

    -- Clear bar overlay cooldown spinners
    for _, key in ipairs({"cs", "judge", "consec", "aw", "abacus"}) do
        local overlay = st.practice.bar_overlays[key]
        if overlay and overlay.cooldown_set then
            overlay.cooldown:Clear()
            overlay.cooldown_set = false
        end
    end

    -- Reset judgement tracking
    st.player.judgement_on_cooldown = false
    st.player.judgement_cd_remaining = 0

    -- Stop attacking (swing timer freezes until next fight)
    st.player.is_attacking = false

    -- Update button visuals
    local panel = st.practice.control_frame
    if panel and panel.fight_btn then
        panel.fight_btn.label:SetText("Start Fight")
        panel.fight_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    end
    if panel and panel.fight_timer_text then
        panel.fight_timer_text:SetText("")
    end

    -- Re-enable manual BL button (skip if rotation lock keeps it disabled)
    if not st.practice.locked_rotation and panel and panel.bl_btn then
        panel.bl_btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    end

    -- Trigger final timeline render (data preserved for post-fight review)
    st.practice.timeline_needs_render = true
end

--=========================================================================================
-- Simulated Cast
--=========================================================================================
st.practice.sim_cast = function(ability_key)
    if not st.practice.active then return end

    local ab = abilities[ability_key]
    if not ab then return end

    if ability_key == "stop" then
        st.practice.sim_stopattack()
        return
    end

    local now = GetTime()
    local sim = st.practice.sim

    -- Check GCD (Judgement, Wings, and trinkets are off-GCD — skip check)
    if ability_key ~= "judge" and ab.type ~= "buff" and ab.type ~= "haste_trinket" then
        if st.player.gcd_lockout and st.player.active_gcd_remaining > 0 then
            -- Spell queue: if within the last N seconds of GCD, queue instead of dropping
            local queue_window = ST.db.profile.practice_spell_queue_window
            if queue_window > 0 and st.player.active_gcd_remaining <= queue_window then
                st.practice.sim.queued_ability = ability_key
                st.practice.sim.queue_timestamp = GetTime()
            end
            return
        end
    end

    -- Resume from stopattack if this ability triggers it
    if (st.practice.sim.attack_paused or st.practice.sim.attack_pause_pending) and stopattack_resume_abilities[ability_key] then
        -- Twist macro: resuming with same seal already active (e.g., SoB while SoB is up)
        -- Swap to opposite seal first so sim_cast_seal creates dual-seal state (twist)
        if ab.type == "seal" and sim.n_active_seals == 1 and sim.seal_1_label == ab.seal_label then
            local opposite = ab.seal_label == "blood" and "command" or "blood"
            sim.active_seals = {}
            sim.active_seals[opposite] = true
            sim.seal_1_label = opposite
        end
        st.practice.sim_startattack()
    end

    if ab.type == "seal" then
        st.practice.sim_cast_seal(ability_key, ab)
    elseif ab.type == "ability" then
        st.practice.sim_cast_ability(ability_key, ab, now)
    elseif ab.type == "buff" then
        st.practice.sim_cast_buff(ability_key, ab, now)
    elseif ab.type == "haste_consumable" then
        if st.practice.locked_rotation then return end
        st.practice.activate_haste_pot()
        st.practice.start_sim_gcd()
        st.practice.sync_state_to_player()
        st.bar.update_bar_on_new_gcd()
    elseif ab.type == "haste_trinket" then
        if st.practice.locked_rotation then return end
        -- Check cooldown
        local cd_key = ability_key .. "_cooldown_expires"
        if sim[cd_key] and sim[cd_key] > now then
            -- (silent)
            return
        end
        st.practice.activate_abacus()
        st.practice.sync_state_to_player()
    end

    -- Flash the mapped action bar button to simulate a press
    st.practice.flash_bar_button(ability_key)
end

st.practice.sim_cast_seal = function(ability_key, ab)
    local sim = st.practice.sim
    local seal_label = ab.seal_label
    local now = GetTime()

    -- If the same seal is already active (only seal), do nothing meaningful but still trigger GCD
    -- If a different seal is active, set up dual-seal state
    if sim.n_active_seals > 0 then
        -- Check if we already have 2 seals and the new one is different from both
        -- In any case: old seal(s) start fading, new seal becomes active
        local old_label = sim.seal_1_label

        if old_label and old_label ~= seal_label then
            -- Dual seal state: old seal fades after 400ms
            sim.fading_seal_label = old_label
            sim.fading_seal_expires = now + 0.4
            sim.twist_attempted = true

            -- Both seals active now
            sim.active_seals = {}
            sim.active_seals[old_label] = true
            sim.active_seals[seal_label] = true
            sim.n_active_seals = 2
            sim.seal_1_label = old_label
            sim.seal_2_label = seal_label

        else
            -- Same seal recast or already have this seal
            sim.active_seals = {}
            sim.active_seals[seal_label] = true
            sim.n_active_seals = 1
            sim.seal_1_label = seal_label
            sim.seal_2_label = nil
            sim.fading_seal_label = nil
            sim.fading_seal_expires = 0
        end
    else
        -- No seal active, just apply
        sim.active_seals = {}
        sim.active_seals[seal_label] = true
        sim.n_active_seals = 1
        sim.seal_1_label = seal_label
        sim.seal_2_label = nil
    end

    -- Start simulated GCD
    st.practice.start_sim_gcd()

    -- Sync state and update visuals
    st.practice.sync_state_to_player()
    -- Reset cooldown set flags so icons update
    st.player.seal_1_cooldown_set = false
    st.player.seal_2_cooldown_set = false
    -- Reset bar overlay flags for all seal abilities so overlays pick up new seal timing
    for _, seal_key in ipairs({"soc", "sob", "sotc"}) do
        local overlay = st.practice.bar_overlays[seal_key]
        if overlay then overlay.cooldown_set = false end
    end
    st.bar.update_bar_on_aura_change()
    st.bar.update_bar_on_new_gcd()

    -- Log seal cast to timeline
    if sim.fight_active then
        local lane = seal_label_to_lane[ab.seal_label]
        if lane then
            st.practice.log_timeline_event(lane, GetSpellTexture(ab.spell_id))
        end
    end
end

st.practice.sim_cast_ability = function(ability_key, ab, now)
    local sim = st.practice.sim

    -- Check cooldown
    local cd_key = ability_key .. "_cooldown_expires"
    if sim[cd_key] and sim[cd_key] > now then
        -- (silent)
        return
    end

    -- Special: Judgement requires an active seal
    local judged_seal = nil
    if ability_key == "judge" then
        if sim.n_active_seals == 0 then
            -- (silent)
            return
        end
        -- Capture which seal is being judged before consuming
        if sim.active_seals["command"] then
            judged_seal = "command"
        elseif sim.active_seals["blood"] then
            judged_seal = "blood"
        end
        -- Judgement consumes all active seals
        sim.active_seals = {}
        sim.n_active_seals = 0
        sim.seal_1_label = nil
        sim.seal_2_label = nil
        sim.fading_seal_label = nil
        sim.fading_seal_expires = 0

        -- Reset seal timing in player state
        st.player.seal_1_start_time = 0
        st.player.seal_1_expires = 0
        st.player.seal_2_start_time = 0
        st.player.seal_2_expires = 0
    end

    -- Start cooldown
    if ab.cooldown > 0 then
        sim[cd_key] = now + ab.cooldown
        -- Reset bar overlay flag so overlay picks up the new cooldown
        local overlay = st.practice.bar_overlays[ability_key]
        if overlay then overlay.cooldown_set = false end
    end

    -- Start simulated GCD (Judgement doesn't trigger GCD)
    if ability_key ~= "judge" then
        st.practice.start_sim_gcd()
    end

    -- Judgement consumes seals — reset bar overlay flags for all seal abilities
    if ability_key == "judge" then
        for _, seal_key in ipairs({"soc", "sob", "sotc"}) do
            local seal_overlay = st.practice.bar_overlays[seal_key]
            if seal_overlay and seal_overlay.cooldown_set then
                seal_overlay.cooldown:Clear()
                seal_overlay.cooldown_set = false
            end
        end
    end

    -- Judgement indicator: set tracking state directly (can't use GetSpellCooldown in sim)
    if ability_key == "judge" then
        st.player.judgement_being_tracked = true
        st.player.judgement_cd_remaining = ab.cooldown  -- 10s
        st.player.judgement_on_cooldown = true
    end

    -- Log ability cast to timeline
    if sim.fight_active and (ability_key == "cs" or ability_key == "judge" or ability_key == "consec") then
        st.practice.log_timeline_event(ability_key, GetSpellTexture(ab.spell_id), nil, judged_seal)
    end

    -- Sync and update
    st.practice.sync_state_to_player()
    st.bar.update_bar_on_aura_change()
    st.bar.update_bar_on_new_gcd()
end

st.practice.sim_cast_buff = function(ability_key, ab, now)
    local sim = st.practice.sim

    -- Check cooldown
    local cd_key = ability_key .. "_cooldown_expires"
    if sim[cd_key] and sim[cd_key] > now then
        -- (silent)
        return
    end

    -- Start cooldown
    if ab.cooldown > 0 then
        sim[cd_key] = now + ab.cooldown
        -- Reset bar overlay flag so overlay picks up the new cooldown
        local overlay = st.practice.bar_overlays[ability_key]
        if overlay then overlay.cooldown_set = false end
    end

    -- Apply buff (Avenging Wrath)
    if ability_key == "aw" and ab.duration then
        sim.aw_buff_expires = now + ab.duration

        -- AW + Pot combo: also activate haste pot if setting enabled
        if ST.db.profile.practice_aw_includes_pot then
            st.practice.activate_haste_pot()
        end

        -- AW + SoB combo: also cast Seal of Blood if setting enabled and GCD is free
        if ST.db.profile.practice_aw_includes_sob then
            if not (st.player.gcd_lockout and st.player.active_gcd_remaining > 0) then
                st.practice.sim_cast_seal("sob", abilities["sob"])
            end
        end
    end

    -- Sync and update (AW is off-GCD, no GCD trigger needed)
    st.practice.sync_state_to_player()
end

--=========================================================================================
-- Simulated GCD
--=========================================================================================
st.practice.start_sim_gcd = function()
    local sim = st.practice.sim
    st.player.gcd_lockout = true
    st.reported_gcd_lockout = false
    st.player.active_gcd_full_duration = sim.effective_gcd
    st.player.active_gcd_remaining = sim.effective_gcd

    -- Check for impossible twists (same as real mode)
    st.player.check_impossible_twists()

    -- Fire GCD swipe animation on control panel icons and bar overlays
    local now = GetTime()
    local duration = sim.effective_gcd
    local panel = st.practice.control_frame
    if panel and panel.ability_icons then
        for _, key in ipairs(ability_order) do
            local ab = abilities[key]
            if ab.cooldown == 0 then
                local icon = panel.ability_icons[key]
                if icon and icon.gcd_cooldown then
                    icon.gcd_cooldown:SetCooldown(now, duration)
                end
                local overlay = st.practice.bar_overlays[key]
                if overlay and overlay.gcd_cooldown then
                    overlay.gcd_cooldown:SetCooldown(now, duration)
                end
            end
        end
    end
end

--=========================================================================================
-- Spell Queue Processing
--=========================================================================================
st.practice.process_spell_queue = function()
    local sim = st.practice.sim
    local queued = sim.queued_ability
    if not queued then return end

    -- Clear queue first
    sim.queued_ability = nil
    sim.queue_timestamp = 0

    -- Guards
    if not st.practice.active then return end
    if not sim.fight_active then return end
    if sim.attack_paused then return end

    -- Re-validate ability exists
    local ab = abilities[queued]
    if not ab then return end

    -- Re-validate cooldowns at fire time
    local now = GetTime()
    if ab.type == "ability" then
        local cd_key = queued .. "_cooldown_expires"
        if sim[cd_key] and sim[cd_key] > now then return end
    end

    -- Fire through normal sim_cast (GCD is now clear)
    st.practice.sim_cast(queued)
end

--=========================================================================================
-- Per-Frame Simulation Update
--=========================================================================================
st.practice.sim_update = function(elapsed)
    if not st.practice.active then return end

    local sim = st.practice.sim
    local now = GetTime()

    -- Handle result text fade animation
    if st.practice.result_visible then
        st.practice.result_timer = st.practice.result_timer - elapsed
        if st.practice.result_timer <= 0 then
            st.practice.result_visible = false
            st.practice.result_frame:SetAlpha(0)
        elseif st.practice.result_timer < 0.3 then
            st.practice.result_frame:SetAlpha(st.practice.result_timer / 0.3)
        else
            st.practice.result_frame:SetAlpha(1)
        end
    end

    -- Tick fading seal timer
    if sim.fading_seal_label and sim.fading_seal_expires > 0 then
        if now >= sim.fading_seal_expires then
            -- Remove the fading (old) seal
            local fading = sim.fading_seal_label
            sim.active_seals[fading] = nil
            sim.fading_seal_label = nil
            sim.fading_seal_expires = 0

            -- Recalculate seal state
            sim.n_active_seals = 0
            sim.seal_1_label = nil
            sim.seal_2_label = nil
            for label, _ in pairs(sim.active_seals) do
                sim.n_active_seals = sim.n_active_seals + 1
                if not sim.seal_1_label then
                    sim.seal_1_label = label
                else
                    sim.seal_2_label = label
                end
            end

            -- Sync to player
            st.practice.sync_state_to_player()
            st.bar.update_bar_on_aura_change()
        end
    end

    -- Tick AW buff
    if sim.aw_buff_expires > 0 and now >= sim.aw_buff_expires then
        sim.aw_buff_expires = 0
    end

    -- Tick Bloodlust buff timer
    if sim.has_bloodlust and sim.bl_buff_expires > 0 then
        if now >= sim.bl_buff_expires then
            st.practice.deactivate_bloodlust()
        else
            local panel = st.practice.control_frame
            if panel and panel.bl_btn and panel.bl_btn.countdown then
                panel.bl_btn.countdown:SetText(string.format("|cFFFFFFFF%d|r", math.ceil(sim.bl_buff_expires - now)))
            end

            -- Update BL proc icon countdown
            local bl_frame = st.practice.proc_icons and st.practice.proc_icons["bl"]
            if bl_frame and bl_frame:IsShown() and bl_frame:GetAlpha() > 0.5 then
                bl_frame.countdown:SetText(string.format("%d", math.ceil(sim.bl_buff_expires - now)))
            end
        end
    end

    -- Tick Haste Potion buff timer
    if sim.has_haste_pot and sim.haste_pot_buff_expires > 0 then
        if now >= sim.haste_pot_buff_expires then
            st.practice.deactivate_haste_pot()
        else
            local panel = st.practice.control_frame
            if panel and panel.hp_btn and panel.hp_btn.countdown then
                panel.hp_btn.countdown:SetText(string.format("|cFFFFFFFF%d|r", math.ceil(sim.haste_pot_buff_expires - now)))
            end
        end
    end

    -- Tick Abacus buff timer
    if sim.has_abacus and sim.abacus_buff_expires > 0 then
        if now >= sim.abacus_buff_expires then
            st.practice.deactivate_abacus()
        end
    end

    -- Tick DST buff timer
    if sim.has_dst and sim.dst_buff_expires > 0 then
        if now >= sim.dst_buff_expires then
            st.practice.deactivate_dst()
        else
            -- Update DST proc icon countdown
            local dst_frame = st.practice.proc_icons and st.practice.proc_icons["dst"]
            if dst_frame and dst_frame:IsShown() and dst_frame:GetAlpha() > 0.5 then
                dst_frame.countdown:SetText(string.format("%d", math.ceil(sim.dst_buff_expires - now)))
            end
        end
    end

    -- Tick boss fight timer
    if sim.fight_active then
        local panel = st.practice.control_frame
        local elapsed_fight = now - sim.fight_start_time
        if panel and panel.fight_timer_text then
            local mins = math.floor(elapsed_fight / 60)
            local secs = math.floor(elapsed_fight % 60)
            panel.fight_timer_text:SetText(string.format("Fight: %d:%02d", mins, secs))
        end
        -- Auto-fire BL at configured delay (skip if rotation is locked)
        if not st.practice.locked_rotation and not sim.fight_bl_fired and sim.fight_bl_delay > 0 and elapsed_fight >= sim.fight_bl_delay then
            sim.fight_bl_fired = true
            st.practice.activate_bloodlust()
        end
    end

    -- Update ability icon cooldown overlays and GCD dimming
    st.practice.update_icon_states(now)

    -- Update center-screen rotation display
    st.practice.update_rotation_display()

    -- Render timeline if needed
    if st.practice.timeline_needs_render and st.practice.timeline_visible then
        st.practice.render_timeline()
    end

    -- Detect swing completion (only when fight is active and not paused by stopattack)
    if sim.fight_active and not sim.attack_paused
       and st.player.swing_timer <= 0 and st.player.reported_swing_timer_complete then
        if sim.attack_pause_pending then
            -- Swing completed during stopattack: hold it until startattack resumes
            sim.attack_pause_pending = false
            sim.attack_paused = true
            sim.swing_held = true
        else
            st.practice.sim_on_swing()
        end
    end
end

--=========================================================================================
-- Swing Completion Evaluation
--=========================================================================================
st.practice.sim_on_swing = function()
    local db = ST.db.profile
    local sim = st.practice.sim

    -- If player is in real combat, pause scoring
    if st.core.in_combat then
        if st.practice.control_frame then
            st.practice.control_frame.title:SetText("|cFFFF8800Twist Practice|r |cFFFF0000(paused)|r")
        end
        st.player.reset_swing_timer()
        return
    end

    -- Restore title if it was paused
    if st.practice.control_frame then
        st.practice.control_frame.title:SetText("|cFFFF8800Twist Practice|r")
    end

    -- Log melee swing to timeline (determine result before twist/miss branching)
    local swing_result = (sim.n_active_seals >= 2) and "twist" or "miss"
    -- Track which seal was active at swing time for split-icon display
    local swing_seal = nil
    if sim.active_seals["blood"] then
        swing_seal = "blood"
    elseif sim.active_seals["command"] then
        swing_seal = "command"
    end
    st.practice.log_timeline_event("melee", "Interface\\Icons\\INV_Sword_04", swing_result, swing_seal)

    -- Show feedback when a twist was attempted (seal swap happened this swing cycle)
    if sim.twist_attempted then
        if sim.n_active_seals >= 2 then
            -- Show "TWIST!" feedback
            st.practice.show_result("TWIST!", db.practice_result_color_hit)

            -- Trigger existing twist feedback system (sound/glow)
            st.bar.on_twist_attempt()

            -- Show timeline on first twist if mode is "after_twist"
            if db.practice_timeline_enabled and not st.practice.timeline_visible
                and db.practice_timeline_mode == "after_twist" and st.practice.timeline_frame then
                st.practice.timeline_frame:Show()
                st.practice.timeline_visible = true
                st.practice.timeline_needs_render = true
                local panel = st.practice.control_frame
                if panel and panel.timeline_btn then
                    panel.timeline_btn:SetBackdropColor(0.1, 0.3, 0.1, 0.9)
                    panel.timeline_btn.label:SetText("|cFF00FF00Timeline|r")
                end
            end
        else
            st.practice.show_result("MISS", db.practice_result_color_miss)
        end

        sim.twist_attempted = false
    end

    -- After a successful twist, the older seal is consumed, newer stays
    if sim.n_active_seals >= 2 then
        if sim.fading_seal_label then
            sim.active_seals[sim.fading_seal_label] = nil
            sim.fading_seal_label = nil
            sim.fading_seal_expires = 0
        elseif sim.seal_1_label and sim.seal_2_label then
            -- Remove the oldest seal (seal_1), keep seal_2
            sim.active_seals[sim.seal_1_label] = nil
        end

        -- Recalculate seal state
        sim.n_active_seals = 0
        sim.seal_1_label = nil
        sim.seal_2_label = nil
        for label, _ in pairs(sim.active_seals) do
            sim.n_active_seals = sim.n_active_seals + 1
            if not sim.seal_1_label then
                sim.seal_1_label = label
            else
                sim.seal_2_label = label
            end
        end
    end

    -- Reset swing timer for next cycle
    st.player.reset_swing_timer()

    -- DST proc check (skip if rotation is locked)
    if ST.db.profile.practice_dst_enabled and not st.practice.locked_rotation then
        local dst_now = GetTime()
        if sim.dst_icd_expires <= dst_now then  -- ICD expired
            local ppm = 4.0
            local proc_chance = ppm * sim.effective_speed / 60
            if math.random() < proc_chance then
                st.practice.activate_dst()
            end
        end
    end

    -- Sync state
    st.practice.sync_state_to_player()
    st.bar.update_bar_on_aura_change()

end

--=========================================================================================
-- Icon State Updates (cooldown spirals + GCD dim)
--=========================================================================================
st.practice.update_icon_states = function(now)
    if not st.practice.control_frame or not st.practice.control_frame.ability_icons then return end

    local sim = st.practice.sim
    local panel = st.practice.control_frame
    local gcd_active = st.player.gcd_lockout and st.player.active_gcd_remaining > 0

    for _, key in ipairs(ability_order) do
        local icon = panel.ability_icons[key]
        if icon then
            local ab = abilities[key]

            -- Cooldown spiral for abilities with cooldowns
            if ab.type == "ability" or ab.type == "buff" or ab.type == "haste_trinket" then
                local cd_key = key .. "_cooldown_expires"
                local expires = sim[cd_key] or 0
                if expires > now then
                    local remaining = expires - now
                    local total_cd = ab.cooldown
                    local start_time = expires - total_cd
                    icon.cooldown:SetCooldown(start_time, total_cd)
                else
                    icon.cooldown:Clear()
                end
            else
                icon.cooldown:Clear()
            end

            -- AW buff indicator: highlight the icon border when buff is active
            if key == "aw" and sim.aw_buff_expires > now then
                icon.border:SetColorTexture(1.0, 0.8, 0.0, 0.9)
            elseif key == "aw" then
                icon.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
            end

            -- Haste Pot buff indicator: highlight border when buff is active
            if key == "hpot" and sim.has_haste_pot then
                icon.border:SetColorTexture(1.0, 0.55, 0.0, 0.9)
            elseif key == "hpot" then
                icon.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
            end

            -- Abacus buff indicator: highlight border when buff is active
            if key == "abacus" and sim.has_abacus then
                icon.border:SetColorTexture(0.6, 0.2, 0.8, 0.9)
            elseif key == "abacus" then
                icon.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
            end

            -- Active seal indicator: highlight border for active seals
            if ab.type == "seal" then
                if sim.active_seals[ab.seal_label] then
                    icon.border:SetColorTexture(0.0, 0.8, 0.0, 0.9)
                else
                    icon.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
                end
            end

            -- Update corresponding action bar overlay (if mapped)
            local overlay = st.practice.bar_overlays[key]
            if overlay then
                -- Cooldown spiral on action bar button (set-once pattern)
                if ab.type == "ability" or ab.type == "buff" or ab.type == "haste_trinket" then
                    local cd_key = key .. "_cooldown_expires"
                    local expires = sim[cd_key] or 0
                    if expires > now then
                        if not overlay.cooldown_set then
                            local total_cd = ab.cooldown
                            local start_time = expires - total_cd
                            overlay.cooldown:SetCooldown(start_time, total_cd)
                            overlay.cooldown_set = true
                        end
                    else
                        if overlay.cooldown_set then
                            overlay.cooldown:Clear()
                            overlay.cooldown_set = false
                        end
                    end
                else
                    overlay.cooldown:Clear()
                    overlay.cooldown_set = false
                end

                -- Update cooldown countdown text
                if overlay.cd_text then
                    if ab.type == "ability" or ab.type == "buff" or ab.type == "haste_trinket" then
                        local cd_key2 = key .. "_cooldown_expires"
                        local expires2 = sim[cd_key2] or 0
                        if expires2 > now then
                            local remaining = expires2 - now
                            overlay.cd_text:SetText(string.format("%d", math.ceil(remaining)))
                            overlay.cd_text:Show()
                        else
                            overlay.cd_text:Hide()
                        end
                    else
                        overlay.cd_text:Hide()
                    end
                end

                -- Fade the press-flash
                if overlay.flash_timer > 0 then
                    overlay.flash_timer = overlay.flash_timer - 0.016  -- ~60fps
                    if overlay.flash_timer <= 0 then
                        overlay.flash:Hide()
                        overlay.flash:SetVertexColor(1, 1, 1, 0)
                    else
                        local alpha = 0.6 * (overlay.flash_timer / 0.15)
                        overlay.flash:SetVertexColor(1, 1, 1, alpha)
                    end
                end
            end
        end
    end
end

--=========================================================================================
-- Result Text Display
--=========================================================================================
st.practice.show_result = function(text, color)
    if not st.practice.result_frame then return end
    local db = ST.db.profile

    st.practice.result_frame.text:SetText(text)
    st.practice.result_frame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    st.practice.result_visible = true
    st.practice.result_timer = db.practice_result_duration
    st.practice.result_frame:SetAlpha(1)
end

st.practice.update_result_text_font = function()
    if not st.practice.result_frame then return end
    local db = ST.db.profile
    local font_path = SML:Fetch('font', SML.DefaultMedia.font)
    st.practice.result_frame.text:SetFont(font_path, db.practice_result_text_size, "OUTLINE")
end

--=========================================================================================
-- Info & Stats Display
--=========================================================================================
st.practice.update_info_display = function()
    if not st.practice.control_frame then return end
    local sim = st.practice.sim
    local panel = st.practice.control_frame

    panel.info_text:SetText(string.format("Speed: %.1fs  GCD: %.2fs", sim.effective_speed, sim.effective_gcd))

    local rotation = st.practice.determine_rotation()
    local rotation_name = rotation and (st.rotation.display_names[rotation] or rotation) or "--"
    panel.rotation_text:SetText("Rotation: " .. rotation_name)
end

--=========================================================================================
-- Auto-Detect Keybinds from Action Bars
--=========================================================================================
st.practice.auto_detect_keybinds = function()
    local db = ST.db.profile

    -- Map spell IDs to practice ability keys
    local spell_to_ability = {}
    -- Seals
    for id, _ in pairs(st.data.soc_ids) do spell_to_ability[id] = "soc" end
    for id, _ in pairs(st.data.sob_ids) do spell_to_ability[id] = "sob" end
    for id, _ in pairs(st.data.sotc_ids) do spell_to_ability[id] = "sotc" end
    -- Abilities
    for id, _ in pairs(st.data.cs_spell_ids) do spell_to_ability[id] = "cs" end
    spell_to_ability[20271] = "judge"    -- Judgement
    spell_to_ability[26573] = "consec"   -- Consecration (Rank 6)
    spell_to_ability[27173] = "consec"   -- Consecration (Rank 7 / TBC)
    -- Buff
    spell_to_ability[31884] = "aw"       -- Avenging Wrath
    -- Haste Potion
    spell_to_ability[28507] = "hpot"     -- Haste Potion

    -- Spell name to ability key (for macro parsing)
    local name_to_ability = {
        ["Seal of Command"] = "soc",
        ["Seal of Blood"] = "sob",
        ["Seal of the Crusader"] = "sotc",
        ["Seal of the Martyr"] = "sob",  -- Alliance equivalent of SoB
        ["Crusader Strike"] = "cs",
        ["Judgement"] = "judge",
        ["Consecration"] = "consec",
        ["Avenging Wrath"] = "aw",
    }

    -- Discover visible action bar buttons (supports BT4, Blizzard, ElvUI)
    local visible_buttons = discover_action_buttons()

    local found = {}
    local found_count = 0

    -- Scan action bar slots 1-120 (BT4 can map slots beyond 72)
    for slot = 1, 120 do
        local action_type, id, sub_type = GetActionInfo(slot)
        local ability_key = nil

        if action_type == "spell" and id then
            ability_key = spell_to_ability[id]
        elseif action_type == "macro" and id then
            -- Parse macro body for known spell names
            local macro_body = GetMacroBody(id)
            if macro_body then
                for spell_name, ab_key in pairs(name_to_ability) do
                    if macro_body:find(spell_name) then
                        -- Only assign if not already found a more specific match
                        if not ability_key then
                            ability_key = ab_key
                        end
                    end
                end
                -- Also check for /stopattack macro
                if not ability_key and macro_body:find("/stopattack") then
                    ability_key = "stop"
                end
            end
        end

        if ability_key and not found[ability_key] then
            local btn_info = visible_buttons[slot]
            local frame_name = btn_info and btn_info.frame_name or nil
            local key1 = get_binding_for_slot(slot, frame_name)
            if key1 then
                local db_key = keybind_db_keys[ability_key]
                if db_key then
                    db[db_key] = key1
                    found[ability_key] = key1
                    found_count = found_count + 1
                    local ab = abilities[ability_key]
                    print(string.format("  %s -> |cFF00FF00%s|r", ab and ab.name or ability_key, key1))

                    -- Store bar mapping for overlay system (and persist to DB)
                    if frame_name then
                        st.practice.bar_mappings[ability_key] = { slot = slot, frame_name = frame_name }
                        db.practice_bar_mappings[ability_key] = { slot = slot, frame_name = frame_name }
                    end
                end
            end
        end
    end

    if found_count > 0 then
        print(string.format("Auto-detected |cFF00FF00%d|r keybind(s) from action bars.", found_count))
    else
        print("No matching abilities found on action bars.")
    end

    -- Refresh keybinds if practice is active
    if st.practice.active then
        st.practice.rebind_keys()
        -- Recreate bar overlays with new mappings
        st.practice.remove_all_bar_overlays()
        st.practice.create_all_bar_overlays()
    end

    -- Update keybind labels on control panel
    st.practice.update_keybind_labels()
end

--=========================================================================================
-- Action Bar Overlay System
--=========================================================================================
st.practice.create_bar_overlay = function(ability_key)
    local mapping = st.practice.bar_mappings[ability_key]
    if not mapping then return end

    -- Remove existing overlay for this key first
    st.practice.remove_bar_overlay(ability_key)

    local parent = _G[mapping.frame_name]
    if not parent then return end

    -- Show the parent button if it's hidden (e.g. empty action bar slot)
    -- so our overlay is visible. Track this so remove_bar_overlay can undo it.
    local forced_visible = false
    if not parent:IsVisible() then
        parent:Show()
        forced_visible = true
    end

    -- Container frame parented to the action button, raised above its children
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    container:SetFrameStrata(parent:GetFrameStrata())
    container:SetFrameLevel(parent:GetFrameLevel() + 5)

    -- Full icon texture covering the real button so WoW's usability dimming is hidden
    local ab = abilities[ability_key]
    local icon_tex = container:CreateTexture(nil, "ARTWORK")
    icon_tex:SetAllPoints(parent)
    local tex_path = ab.texture or GetSpellTexture(ab.spell_id)
    if tex_path then
        icon_tex:SetTexture(tex_path)
        icon_tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Cooldown swipe overlay
    local cd = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
    cd:SetAllPoints(parent)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(true)

    -- GCD dim overlay
    local dim = container:CreateTexture(nil, "OVERLAY")
    dim:SetAllPoints(parent)
    dim:SetColorTexture(0, 0, 0, 0.5)
    dim:Hide()

    -- GCD cooldown swipe overlay
    local gcd_cd = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
    gcd_cd:SetAllPoints(parent)
    gcd_cd:SetDrawEdge(false)
    gcd_cd:SetHideCountdownNumbers(true)

    -- Flash texture for button press effect
    local flash = container:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints(parent)
    flash:SetColorTexture(1, 1, 1, 0)
    flash:Hide()

    -- Cooldown countdown text (on raised frame so it renders above the cooldown swipe)
    local cd_text_frame = CreateFrame("Frame", nil, container)
    cd_text_frame:SetAllPoints(parent)
    cd_text_frame:SetFrameLevel(container:GetFrameLevel() + 10)
    local cd_text = cd_text_frame:CreateFontString(nil, "OVERLAY")
    cd_text:SetPoint("CENTER", parent, "CENTER", 0, 0)
    cd_text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    cd_text:SetTextColor(1, 1, 1, 1)
    cd_text:Hide()

    -- Mirror the keybind text above the overlay so hotkey labels stay visible
    local db_key = keybind_db_keys[ability_key]
    local bind_text = db_key and shorten_keybind(ST.db.profile[db_key]) or ""
    if bind_text ~= "" then
        local hotkey_mirror = cd_text_frame:CreateFontString(nil, "OVERLAY")
        hotkey_mirror:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -3)
        local hotkey_src = parent.HotKey
        if hotkey_src then
            local font, size, flags = hotkey_src:GetFont()
            if font then
                hotkey_mirror:SetFont(font, size, flags)
            end
            hotkey_mirror:SetTextColor(hotkey_src:GetTextColor())
        else
            hotkey_mirror:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            hotkey_mirror:SetTextColor(0.6, 0.6, 0.6, 1)
        end
        hotkey_mirror:SetText(bind_text)
        hotkey_mirror:Show()
    end

    st.practice.bar_overlays[ability_key] = {
        container = container,
        icon_tex = icon_tex,
        cooldown = cd,
        cooldown_set = false,
        gcd_dim = dim,
        gcd_cooldown = gcd_cd,
        flash = flash,
        flash_timer = 0,
        cd_text = cd_text,
        forced_visible = forced_visible,
        parent_frame = forced_visible and parent or nil,
    }
end

st.practice.remove_bar_overlay = function(ability_key)
    local overlay = st.practice.bar_overlays[ability_key]
    if not overlay then return end

    if overlay.cooldown then
        overlay.cooldown:Clear()
        overlay.cooldown:Hide()
    end
    if overlay.gcd_dim then
        overlay.gcd_dim:Hide()
    end
    if overlay.flash then
        overlay.flash:Hide()
    end
    if overlay.cd_text then
        overlay.cd_text:Hide()
    end
    if overlay.container then
        overlay.container:Hide()
    end

    -- Re-hide parent button if we forced it visible for an empty slot
    if overlay.forced_visible and overlay.parent_frame then
        overlay.parent_frame:Hide()
    end

    st.practice.bar_overlays[ability_key] = nil
end

st.practice.remove_all_bar_overlays = function()
    -- Collect keys first to avoid modifying table during iteration
    local keys = {}
    for key, _ in pairs(st.practice.bar_overlays) do
        table.insert(keys, key)
    end
    for _, key in ipairs(keys) do
        st.practice.remove_bar_overlay(key)
    end
    st.practice.bar_overlays = {}
end

st.practice.reset_all_mappings = function()
    -- Remove visual overlays
    st.practice.remove_all_bar_overlays()
    -- Clear runtime mappings
    st.practice.bar_mappings = {}
    -- Clear persisted mappings
    ST.db.profile.practice_bar_mappings = {}
    -- Reset keybinds to defaults
    local defaults = { soc="1", sob="2", cs="3", judge="4", sotc="5",
                       consec="6", aw="7", hpot="8", abacus="9", stop="" }
    for key, default_bind in pairs(defaults) do
        local db_key = keybind_db_keys[key]
        if db_key then ST.db.profile[db_key] = default_bind end
    end
    -- Re-apply keybinds and update labels
    if st.practice.active then
        st.practice.rebind_keys()
    end
    st.practice.update_keybind_labels()
    print("All button mappings and keybinds have been reset.")
end

st.practice.create_all_bar_overlays = function()
    for key, _ in pairs(st.practice.bar_mappings) do
        st.practice.create_bar_overlay(key)
    end
end

-- Flash the action bar button to simulate a press
st.practice.flash_bar_button = function(ability_key)
    local overlay = st.practice.bar_overlays[ability_key]
    if not overlay or not overlay.flash then return end

    overlay.flash:SetVertexColor(1, 1, 1, 0.6)
    overlay.flash:Show()
    overlay.flash_timer = 0.15  -- Flash duration
end

--=========================================================================================
-- Manual Linking (Right-click control panel icon -> click action bar button)
--=========================================================================================
st.practice.start_linking = function(ability_key)
    -- Cancel any existing linking first
    st.practice.cancel_linking()

    st.practice.linking_ability = ability_key

    local ab = abilities[ability_key]
    local name = ab and ab.name or ability_key
    print(string.format("Click the action bar button for |cFF00FFFF%s|r... (right-click or ESC to cancel)", name))

    -- Show linking prompt on hint text
    local panel = st.practice.control_frame
    if panel and panel.hint_text then
        panel.hint_text:SetTextColor(0, 1, 1, 1)
        panel.hint_text:SetText("Click action bar button for " .. name)
    end

    -- Glow the control panel icon
    if panel and panel.ability_icons and panel.ability_icons[ability_key] then
        LCG.PixelGlow_Start(panel.ability_icons[ability_key], {0, 1, 1, 1}, 8, 0.25, nil, 2, 1, 1, false, "Linking")
    end

    -- Fullscreen backdrop: right-click or Escape anywhere cancels linking
    local backdrop = CreateFrame("Frame", nil, UIParent)
    backdrop:SetAllPoints(UIParent)
    backdrop:SetFrameStrata("DIALOG")
    backdrop:SetFrameLevel(0)
    backdrop:EnableMouse(true)
    backdrop:EnableKeyboard(true)
    backdrop:SetPropagateKeyboardInput(false)
    backdrop:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then
            st.practice.cancel_linking()
        end
    end)
    backdrop:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            st.practice.cancel_linking()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    if backdrop.EnableGamePadButton then
        backdrop:EnableGamePadButton(true)
        backdrop:SetScript("OnGamePadButtonDown", function(self, button)
            if not is_gamepad_emulator_button(button) then
                st.practice.cancel_linking()
            end
        end)
    end
    table.insert(st.practice.linking_catchers, backdrop)

    -- Create click-catcher frames over all action bar buttons (including empty/hidden slots).
    -- Parented to UIParent with DIALOG strata so they sit above secure action buttons.
    -- Uses discover_action_buttons(true) to include hidden buttons for empty slot linking.
    local all_buttons = discover_action_buttons(true)

    for slot, btn_info in pairs(all_buttons) do
        local ab_btn = btn_info.frame
        local fname = btn_info.frame_name

        -- Parent to UIParent, position over the action button
        -- Hidden/empty buttons may report 0 size; use 36x36 fallback
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetFrameStrata("DIALOG")
        local w, h = ab_btn:GetWidth(), ab_btn:GetHeight()
        if w < 1 or h < 1 then w, h = 36, 36 end
        catcher:SetSize(w, h)
        catcher:SetPoint("CENTER", ab_btn, "CENTER", 0, 0)
        catcher:EnableMouse(true)
        catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Cyan highlight so the user can see clickable buttons
        local highlight = catcher:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0, 1, 1, 0.25)

        catcher:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                st.practice.cancel_linking()
            else
                st.practice.on_linking_click(ability_key, slot, fname)
            end
        end)

        table.insert(st.practice.linking_catchers, catcher)
    end
end

st.practice.on_linking_click = function(ability_key, slot, frame_name)
    -- Store bar mapping (and persist to DB)
    st.practice.bar_mappings[ability_key] = { slot = slot, frame_name = frame_name }
    ST.db.profile.practice_bar_mappings[ability_key] = { slot = slot, frame_name = frame_name }

    -- Resolve keybind from the slot (supports BT4 and Blizzard bindings)
    local key1 = get_binding_for_slot(slot, frame_name)
    if key1 then
        local db_key = keybind_db_keys[ability_key]
        if db_key then
            ST.db.profile[db_key] = key1
        end
    else
        -- Keybind detection failed (e.g. modifier keybinds) — prompt user to press the key
        st.practice.cancel_linking()
        st.practice.start_key_capture(ability_key)
        return
    end

    -- Create bar overlay if practice is active
    if st.practice.active then
        st.practice.remove_bar_overlay(ability_key)
        st.practice.create_bar_overlay(ability_key)
        st.practice.rebind_keys()
    end

    -- Print confirmation
    local ab = abilities[ability_key]
    local name = ab and ab.name or ability_key
    local key_text = ST.db.profile[keybind_db_keys[ability_key]] or "none"
    print(string.format("Linked |cFF00FFFF%s|r to |cFF00FF00%s|r (key: %s)", name, frame_name, key_text))

    -- Update keybind label on control panel icon
    st.practice.update_keybind_labels()

    -- Finish linking
    st.practice.cancel_linking()
end

st.practice.cancel_linking = function()
    st.practice.cancel_key_capture()
    if not st.practice.linking_ability then return end

    -- Stop glow on control panel icon
    local panel = st.practice.control_frame
    local key = st.practice.linking_ability
    if panel and panel.ability_icons and panel.ability_icons[key] then
        LCG.PixelGlow_Stop(panel.ability_icons[key], "Linking")
    end

    -- Restore hint text
    if panel and panel.hint_text then
        panel.hint_text:SetTextColor(0.5, 0.5, 0.5, 0.8)
        panel.hint_text:SetText("Right-click icon to map to action bar")
    end

    -- Remove all click-catchers
    for _, catcher in ipairs(st.practice.linking_catchers) do
        catcher:Hide()
        catcher:SetParent(nil)
    end
    st.practice.linking_catchers = {}
    st.practice.linking_ability = nil
end

--=========================================================================================
-- Key Capture (fallback when keybind detection fails during linking)
--=========================================================================================
st.practice.start_key_capture = function(ability_key)
    st.practice.key_capture_ability = ability_key

    local f = get_or_create_key_capture_frame()
    local ab = abilities[ability_key]
    local name = ab and ab.name or ability_key
    f.prompt:SetText("Press the key bound to |cFF00FFFF" .. name .. "|r")
    f:EnableKeyboard(true)
    if f.EnableGamePadButton then f:EnableGamePadButton(true) end
    f:SetPropagateKeyboardInput(false)
    f:Show()

    print(string.format("Could not detect keybind for |cFF00FFFF%s|r. Press the key now (ESC to cancel).", name))
end

st.practice.finish_key_capture = function(bind)
    local ability_key = st.practice.key_capture_ability
    if not ability_key then return end

    -- Dismiss the fullscreen capture overlay before creating bar overlay
    st.practice.cancel_key_capture()

    -- Store keybind
    local db_key = keybind_db_keys[ability_key]
    if db_key then
        ST.db.profile[db_key] = bind
    end

    -- Create bar overlay if practice is active
    if st.practice.active then
        st.practice.remove_bar_overlay(ability_key)
        st.practice.create_bar_overlay(ability_key)
        st.practice.rebind_keys()
    end

    -- Update keybind labels
    st.practice.update_keybind_labels()

    -- Print confirmation
    local ab = abilities[ability_key]
    local name = ab and ab.name or ability_key
    local mapping = st.practice.bar_mappings[ability_key]
    local frame_name = mapping and mapping.frame_name or "?"
    print(string.format("Linked |cFF00FFFF%s|r to |cFF00FF00%s|r (key: %s)", name, frame_name, bind))
end

st.practice.cancel_key_capture = function()
    st.practice.key_capture_ability = nil
    local f = st.practice.key_capture_frame
    if f then
        f:EnableKeyboard(false)
        if f.EnableGamePadButton then f:EnableGamePadButton(false) end
        f:Hide()
    end
end

--=========================================================================================
-- Stopattack / Startattack
--=========================================================================================
st.practice.sim_stopattack = function()
    local sim = st.practice.sim
    if not sim.fight_active or sim.attack_paused or sim.attack_pause_pending then return end
    sim.queued_ability = nil
    sim.queue_timestamp = 0
    -- If the swing timer already completed (bar is full/at 0), pause immediately
    if st.player.swing_timer <= 0 and st.player.reported_swing_timer_complete then
        sim.attack_paused = true
        return
    end
    -- Mid-swing: let current swing finish, then pause
    sim.attack_pause_pending = true
end

st.practice.sim_startattack = function()
    local held = st.practice.sim.swing_held
    st.practice.sim.attack_paused = false
    st.practice.sim.attack_pause_pending = false
    st.practice.sim.swing_held = false
    if not held then
        -- Normal resume: start a fresh swing
        st.player.reset_swing_timer()
    end
    -- If swing was held, don't reset timer — swing_timer is still at 0
    -- with reported_complete = true. The next on_update frame will detect
    -- this and fire sim_on_swing with the current seal state (twist window).
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed practice.lua module correctly') end
