--=========================================================================================
-- AceGUI widgets for SwedgeTimer's options.
--
-- Port of the archived build's widgets.lua (docs/swedge/SwedgeTimer_Forever/widgets.lua;
-- reference line numbers below are that file):
--   * Dropdown-Left           8-26    left-aligned dropdown (used via AceConfig's
--                                     dialogControl for selects whose text was centred)
--   * Dropdown-SoundPreview  30-74    dropdown whose list entries preview their sound on
--                                     hover; the played handle is stopped before the next
--                                     preview so sweeping the list cannot stack sounds
--
-- The archive read the sound map from st.bar.twist_sounds. This build's map is a
-- file-local of classes/paladin.lua, so the accessor resolves it through the documented
-- chain below and no-ops silently when nothing resolves or the client lacks
-- PlaySoundFile (the frozen behaviour of the archive's guards).
--=========================================================================================
local addon_name, st = ...
local AceGUI = LibStub("AceGUI-3.0")

st.widgets = st.widgets or {}

-- Optional client globals (captured at load, the hud.lua convention): both degrade to a
-- silent no-op when absent.
local play_sound_file = rawget(_G, "PlaySoundFile")
local stop_sound = rawget(_G, "StopSound")

-- The addon object is created later in the load order (main.lua); resolved lazily and
-- memoised on first use.
local cached_addon
local function addon()
    if not cached_addon then
        cached_addon = LibStub("AceAddon-3.0"):GetAddon(addon_name, true)
    end
    return cached_addon
end

-- The shipped fallback channel. The only sound_channel default this build ships is the
-- PALADIN class row's (config_presets.lua:788); the profile root ships none, so "Master"
-- is also what a non-paladin class previews on.
local DEFAULT_SOUND_CHANNEL = "Master"

-- The audio channel for previews: the class table's sound_channel (this build's
-- location, the same value classes/paladin.lua's twist playback uses), then the
-- profile's own top-level sound_channel (the archive's location), then "Master".
--
-- EVERY read here is rawget, and the answer must be a STRING. Both the profile root and
-- each class row are AceDB tables carrying the '**' defaults metatable
-- (ST.defaults.profile['**'] = ST.class_defaults and each ST.<CLASS>.defaults['**'] =
-- ST.bar_defaults; Libs/AceDB-3.0/AceDB-3.0.lua:88-107): a plain read of an ABSENT key
-- runs __index, which CREATES a defaults-filled table, rawsets it into the saved profile
-- and returns it. A plain read therefore answers a truthy TABLE on most classes - the old
-- code handed exactly that to PlaySoundFile. rawget reads only what was actually saved
-- (the same lesson as the config.lua appearance migration), and the string requirement
-- keeps a corrupt saved value (a table, a number, a boolean) off the client call.
local function sound_channel()
    local ST = addon()
    if ST and type(ST.db) == "table" and type(ST.db.profile) == "table" then
        local profile = ST.db.profile
        -- rawget, not profile[class]: a class token the defaults do not list must stay
        -- absent instead of materialising a defaults row on a live profile.
        local class_db = type(ST.player_class) == "string"
            and rawget(profile, ST.player_class) or nil
        local channel = type(class_db) == "table" and rawget(class_db, "sound_channel") or nil
        if type(channel) ~= "string" then
            channel = rawget(profile, "sound_channel")
        end
        if type(channel) == "string" then
            return channel
        end
    end
    return DEFAULT_SOUND_CHANNEL
end

-- One upvalue of a function by name, through the standard Lua debug API; nil when the
-- API or the name is absent. pcall-guarded: probing must never raise.
local function find_upvalue(func, name)
    if type(func) ~= "function" or type(debug) ~= "table"
        or type(debug.getupvalue) ~= "function" then
        return nil
    end
    local i = 1
    while true do
        local ok, up_name, value = pcall(debug.getupvalue, func, i)
        if not ok or up_name == nil then
            return nil
        end
        if up_name == name then
            return value
        end
        i = i + 1
    end
end

-- The class module's private sound map. The class module's playback helper
-- (classes/paladin.lua's play_twist_sound) is a file-local closure captured by its
-- hooks, and the map is that closure's "twist_sounds" upvalue; recovering it reads the
-- single authoritative table instead of duplicating the 69 paths here. The
-- "TadaFanfare" spot-check rejects any wrong table. Delete this bridge once the class
-- module publishes the map (the lookup above prefers it).
local function recover_class_sound_map(ST)
    local class = ST and ST.player_class and ST[ST.player_class]
    if type(class) ~= "table" then
        return nil
    end
    local probes = { class.on_twist_attempt, class.on_bar_update, class.on_successful_twist }
    for i = 1, #probes do
        local play = find_upvalue(probes[i], "play_twist_sound")
        local map = play and find_upvalue(play, "twist_sounds")
        if type(map) == "table" and map["TadaFanfare"] ~= nil then
            return map
        end
    end
    return nil
end

-- The key -> file map, first hit wins (resolved once and cached):
--   1. st.widgets.twist_sounds      - explicit injection (tests / other classes)
--   2. ST.<CLASS>.twist_sounds      - the class module's published table
--   3. st.bar.twist_sounds          - the archive's published location
--   4. the recovered file-local (above) - today's only source
local sound_map_cache
local function sound_map()
    if sound_map_cache then
        return sound_map_cache
    end
    local map = st.widgets.twist_sounds
    local ST = addon()
    if type(map) ~= "table" and ST then
        local class = ST.player_class and ST[ST.player_class]
        map = class and class.twist_sounds
    end
    if type(map) ~= "table" and st.bar then
        map = st.bar.twist_sounds
    end
    if type(map) ~= "table" then
        map = recover_class_sound_map(ST)
    end
    if type(map) == "table" then
        sound_map_cache = map
        return map
    end
    return nil
end

-- The preview handle so "sweeping across the list" cannot stack sounds (archive 34-53).
-- pcall: a handle the client no longer knows (or a client whose StopSound throws) must
-- never raise out of a list rebuild.
local preview_handle
local function stop_preview()
    if preview_handle and stop_sound then
        pcall(stop_sound, preview_handle)
    end
    preview_handle = nil
end

-- Preview the sound registered under `key` (keys of the map / the option's values).
-- Silent no-op when the key, the map or PlaySoundFile is missing. This is the widget's
-- public entry point (the hover handler below uses it).
function st.widgets.preview_sound(key)
    if not play_sound_file then
        return
    end
    local map = sound_map()
    local path = key and map and map[key]
    -- PlaySoundFile takes a path string or a numeric fileDataID; anything else (a corrupt
    -- map entry) is a silent no-op rather than a client call with a bad argument.
    if type(path) ~= "string" and type(path) ~= "number" then
        return
    end
    stop_preview()
    -- pcall: a missing file, a bad channel or a client that throws instead of returning
    -- false must never error out of a dropdown hover. On failure nothing is latched, so
    -- the next hover is a clean attempt (the archive's guards were silent no-ops too).
    local ok, will_play, handle = pcall(play_sound_file, path, sound_channel())
    if ok and will_play then
        preview_handle = handle
    end
end

-- The hover handler the widget attaches to every list entry (archive 36-53).
local function item_on_enter(item)
    local value = item.userdata and item.userdata.value
    st.widgets.preview_sound(value)
end

--=========================================================================================
-- Widget registration (archive 8-74)
--=========================================================================================
-- A left-aligned dropdown for AceConfig's dialogControl.
do
    local widgetType = "Dropdown-Left"
    local widgetVersion = 1

    local function Constructor()
        -- Create a standard dropdown widget.
        local widget = AceGUI:Create("Dropdown")

        -- Left-align the selected text.
        if widget.text then
            widget.text:SetJustifyH("LEFT")
        end

        widget.type = widgetType
        return widget
    end

    AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)
end

-- A dropdown for the addon's sound settings: every list entry previews its sound on
-- hover. List keys must be keys of the class module's sound map.
do
    local widgetType = "Dropdown-SoundPreview"
    local widgetVersion = 1

    local function Constructor()
        local widget = AceGUI:Create("Dropdown")

        -- Hook every list item's hover after the list is (re)built.
        local orig_SetList = widget.SetList
        widget.SetList = function(self, list, order, itemType)
            orig_SetList(self, list, order, itemType)
            if self.pullout and self.pullout.items then
                for _, item in ipairs(self.pullout.items) do
                    item:SetCallback("OnEnter", item_on_enter)
                end
            end
        end

        widget.type = widgetType
        return widget
    end

    AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed widgets.lua module correctly') end
