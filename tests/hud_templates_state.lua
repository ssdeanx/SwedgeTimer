-- tests/hud_templates_state.lua: offline pins for the ready-made Cooldown HUD
-- layout templates (bench/hud_templates_2026-10-19.md §§1-8).
--
-- What is pinned:
--   1) Every HUD class (paladin/warrior/hunter/druid/shaman/rogue) ships
--      ST.<TOKEN>.HUD_TEMPLATES with exactly the documented template ids.
--   2) Every template's slot set is the class's FULL slot set (explicit
--      true/false per key, so switching templates never leaves a stale slot
--      on) and every key names a real HUD_SLOTS descriptor in the class
--      module (warrior: the union over all family sets in classes/warrior.lua).
--   3) Geometry values are in sane ranges (size 8-64, spacing 0-16,
--      orientation enum) and match the documented per-template values.
--   4) ROGUE R-T3 + DRUID Claw ship_false: kidney/restealth/bandage/claw ship
--      an explicit false default (hidden, no default-visible change) and carry
--      their own toggle widgets (landed after the design pin; the template
--      still writes the db keys on explicit pick).
--   5) hud_template ships nil (= Custom: current behavior, zero
--      default-visible change); the template select get/set round-trips
--      through the real options tree (nil-safe, unknown-hides, Custom
--      fallback, dirty-detect-as-derived-state).
--
-- Mutation: drop/rename one slot key in any template -> the coverage or
-- membership check for that class fails.
-- Run from the repo root: lua5.1 tests/hud_templates_state.lua (any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL  " .. label) end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

local CLASS_TABLES = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}
local MODULES = {
    "utils.lua", "config_presets.lua", "config.lua", "rogue_guide.lua",
    "option_table_presets.lua", "option_tables.lua",
}

-- The documented contract (design §§1-6/8): template ids, the full slot set
-- each template must cover explicitly, and the per-template geometry.
-- Warrior slots are the union over every family set in classes/warrior.lua
-- (op/execute/slam/hs/cleave/bt/ww + rend/ms/bladestorm + raging_blow +
-- hamstring + sunder + trinkets); W-T3 ships the provisional arms/SoD union
-- (design §2; sunder rides only W-T2 family-full). Paladin slots are the
-- archive 7 + the SoD/shockadin mirror 5 (soc/sob/how/holy_shock/
-- aura_mastery, bench/paladin_styles_2026-10-19.md §0: P-T2 only) + the WotLK
-- APL's utility band 2 (hor / how_wrath, the APL utility layer, bench/
-- paladin_apl_utility_build_2026-10-20.md §2). Rogue slots are the full 13
-- (design §6 + coldblood); druid slots are the full 11 (guide order + claw).
-- ship_false keys (rogue R-T3 row, druid claw, the paladin's WotLK band) ship
-- an explicit false default + widget instead of true.
local CLASSES = {
    { pretty = "Paladin", lower = "paladin", token = "PALADIN",
      templates = { "twist_core", "full_ret", "minimal" },
      slots = { "cs", "judgement", "consecration", "exorcism",
          "trinket1", "trinket2", "wings", "soc", "sob", "how",
          "holy_shock", "aura_mastery", "hor", "how_wrath" },
      -- The WotLK utility band ships OFF (the druid Claw shape): the provider
      -- hides the mirrors unless the key reads exactly true, so false and nil
      -- both hide. The slots and their toggles still exist - only the default
      -- changed. Per template, the family-specific slots follow the SoD-native
      -- rule (bench/paladin_styles_2026-10-19.md §0: SoD-native slots extend
      -- P-T2, not P-T1): the band rides the "full" template (P-T2 is "all
      -- visible", bench/hud_templates_2026-10-19.md §1) and stays off in P-T1
      -- and P-T3 - the same shape as the druid's Claw (false in the defaults,
      -- on in D-T2).
      ship_false = { hor = true, how_wrath = true },
      template_values = {
          twist_core = { hor = false, how_wrath = false },
          full_ret = { hor = true, how_wrath = true },
          minimal = { hor = false, how_wrath = false },
      },
      geometry = {
          twist_core = { size = 36, spacing = 2, orientation = "horizontal", match = false },
          full_ret = { size = 36, spacing = 2, orientation = "horizontal", match = true },
          minimal = { size = 28, spacing = 2, orientation = "horizontal", match = false },
      } },
    { pretty = "Warrior", lower = "warrior", token = "WARRIOR",
      templates = { "fury_core", "full_trinkets", "arms_sod" },
      slots = { "op", "execute", "slam", "hs", "cleave", "bt", "ww",
          "rend", "ms", "bladestorm", "raging_blow", "hamstring", "sunder",
          "trinket1", "trinket2" },
      -- The Sunder mirror ships OFF (operator ruling): the provider hides it
      -- unless the key reads exactly true, so false and nil both hide. The slot
      -- and its toggle still exist - only the default changed.
      ship_false = { sunder = true },
      geometry = {
          fury_core = { size = 36, spacing = 2, orientation = "horizontal", match = false },
          full_trinkets = { size = 36, spacing = 2, orientation = "horizontal", match = true },
          arms_sod = { size = 36, spacing = 2, orientation = "horizontal", match = false },
      } },
    { pretty = "Hunter", lower = "hunter", token = "HUNTER",
      templates = { "shot_rotation", "full_bm", "minimal_glow" },
      slots = { "steady", "raptor", "kill_command", "multi",
          "bestial_wrath", "rapid_fire", "aimed", "trinket1", "trinket2" },
      geometry = {
          shot_rotation = { size = 36, spacing = 2, orientation = "horizontal", match = false },
          full_bm = { size = 36, spacing = 2, orientation = "horizontal", match = true },
          minimal_glow = { size = 28, spacing = 2, orientation = "horizontal", match = false },
      } },
    { pretty = "Druid", lower = "druid", token = "DRUID",
      templates = { "bleed_core", "full_feral", "bear_guard" },
      slots = { "maul", "mangle", "rip", "rake", "bite", "shred", "claw",
          "tf", "berserk", "trinket1", "trinket2" },
      ship_false = { claw = true },
      geometry = {
          bleed_core = { size = 36, spacing = 2, orientation = "horizontal", match = false },
          full_feral = { size = 36, spacing = 2, orientation = "horizontal", match = true },
          bear_guard = { size = 32, spacing = 2, orientation = "horizontal", match = false },
      } },
    { pretty = "Shaman", lower = "shaman", token = "SHAMAN",
      templates = { "twist_core", "full_weave", "minimal" },
      slots = { "stormstrike", "flameshock", "weave", "firenova",
          "earthshock", "twist", "lightningshield", "searing", "coe",
          "trinket1", "trinket2" },
      -- The three maintain mirrors ship OFF and stay off in every template
      -- (no template pick surfaces upkeep icons unasked; the full-set promise
      -- holds for all 11 slots).
      ship_false = { lightningshield = true, searing = true, coe = true },
      template_values = {
          twist_core = { lightningshield = false, searing = false, coe = false },
          full_weave = { lightningshield = false, searing = false, coe = false },
          minimal = { lightningshield = false, searing = false, coe = false },
      },
      geometry = {
          twist_core = { size = 36, spacing = 2, orientation = "horizontal", match = false },
          full_weave = { size = 36, spacing = 2, orientation = "horizontal", match = true },
          minimal = { size = 28, spacing = 2, orientation = "horizontal", match = false },
      } },
    { pretty = "Rogue", lower = "rogue", token = "ROGUE",
      templates = { "core", "full_cds", "pvp_utility" },
      slots = { "snd", "rupture", "ea", "ar", "bf", "tea", "kick",
          "kidney", "restealth", "bandage", "coldblood", "trinket1", "trinket2" },
      ship_false = { kidney = true, restealth = true, bandage = true },
      geometry = {
          core = { size = 36, spacing = 2, orientation = "horizontal", match = false },
          full_cds = { size = 36, spacing = 2, orientation = "horizontal", match = true },
          pvp_utility = { size = 32, spacing = 4, orientation = "vertical", match = false },
      } },
}

local function read_file(path)
    local f = assert(io.open(ROOT .. path, "r"))
    local text = f:read("*a")
    f:close()
    return text:gsub("\r\n", "\n")
end

--=========================================================================================
-- Sandbox: load the real config_presets.lua (template tables) and, for the
-- widget behaviour pins, the real options tree (same module set as
-- tests/options_load_state.lua).
--=========================================================================================
local function load_modules(class_pretty)
    local sb = {}

    local ST = {}
    for _, name in ipairs(CLASS_TABLES) do ST[name] = {} end
    sb.profile, sb.class_db, sb.hand_dbs = {}, {}, {}
    function ST:get_class_hands()
        local hands = self.class_hands[self.player_class]
        if hands == nil and type(self.player_class) == "string" then
            hands = self.class_hands[string.upper(self.player_class)]
        end
        return hands or {}
    end
    function ST:iter_hands()
        local hands = self:get_class_hands()
        local i, n = 0, #hands
        return function()
            i = i + 1
            if i <= n then return hands[i] end
        end
    end
    ST.class_hands = {
        DEATHKNIGHT = {"mainhand", "offhand"},
        DRUID = {"mainhand"},
        HUNTER = {"mainhand", "offhand", "ranged"},
        MAGE = {"mainhand", "ranged"},
        PALADIN = {"mainhand"},
        PRIEST = {"mainhand", "ranged"},
        ROGUE = {"mainhand", "offhand", "ranged"},
        SHAMAN = {"mainhand", "offhand"},
        WARLOCK = {"mainhand", "ranged"},
        WARRIOR = {"mainhand", "offhand", "ranged"},
    }
    function ST:generic_iter(array)
        local i, n = 0, #array
        return function()
            i = i + 1
            if i <= n then return array[i] end
        end
    end
    function ST:get_profile_table() return sb.profile end
    function ST:get_class_table() return sb.class_db end
    function ST:get_hand_table(hand)
        sb.hand_dbs[hand] = sb.hand_dbs[hand] or {}
        return sb.hand_dbs[hand]
    end
    function ST:convert_color(t, alpha) return t[1] / 255, t[2] / 255, t[3] / 255, alpha or t[4] end
    function ST:convert_color_up(t) return { t[1] * 255, t[2] * 255, t[3] * 255, t[4] } end
    sb.ST = ST

    local LSM = {
        Fetch = function(_, mediatype, key) return key end,
        HashTable = function(_, mediatype) return { ["fake-" .. mediatype] = "Fake " .. mediatype } end,
        Register = function() end,
    }
    local LWIN = { SavePosition = function() end, RestorePosition = function() end }
    local AC = {
        RegisterOptionsTable = function(_, name, table)
            sb.registered_name, sb.registered_table = name, table
        end,
    }
    local ACR = { NotifyChange = function() end, RegisterOptionsTable = function() end }
    local DB = { New = function() return { profile = sb.profile } end }

    local env = setmetatable({}, { __index = _G })
    env.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    env.UnitClass = function() return class_pretty, string.upper(class_pretty) end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then return { GetAddon = function() return ST end } end
        if major == "LibSharedMedia-3.0" then return LSM end
        if major == "LibWindow-1.1" then return LWIN end
        if major == "AceConfig-3.0" then return AC end
        if major == "AceConfigRegistry-3.0" then return ACR end
        if major == "AceDB-3.0" then return DB end
        return {}
    end

    local st = {}
    for _, path in ipairs(MODULES) do
        local chunk = assert(loadfile(ROOT .. path))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        if not ok then
            return nil, path .. " does not load: " .. tostring(err)
        end
    end
    sb.st, sb.env = st, env
    return sb
end

local function build(class_pretty)
    local sb, err = load_modules(class_pretty)
    if not sb then return nil, err end
    local ST = sb.ST
    ST.player_class_pretty, ST.player_class = sb.env.UnitClass("player")
    local ok, serr = pcall(ST.set_opts, ST)
    if not ok then
        return nil, "set_opts() fails: " .. tostring(serr)
    end
    return sb
end

local function template_widget(sb)
    local panel = sb.ST.opts_table.args.class
    local args = panel and panel.args or {}
    return args.hud_template
end

--=========================================================================================
-- 1) Template tables: ids, labels, full slot coverage, geometry
--=========================================================================================
do
    local presets_src = read_file("config_presets.lua")
    for _, class in ipairs(CLASSES) do
        local sb, err = load_modules(class.pretty)
        check(sb ~= nil, class.pretty .. ": the modules load"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            local templates = sb.ST[class.token] and sb.ST[class.token].HUD_TEMPLATES
            check(type(templates) == "table",
                class.pretty .. ": ST." .. class.token .. ".HUD_TEMPLATES exists")
            if type(templates) == "table" then
                local count = 0
                for _ in pairs(templates) do count = count + 1 end
                eq(count, #class.templates,
                    class.pretty .. ": ships exactly the documented templates")
                for _, id in ipairs(class.templates) do
                    local t = templates[id]
                    check(type(t) == "table",
                        class.pretty .. ": template '" .. id .. "' exists")
                    if type(t) == "table" then
                        check(type(t.label) == "string" and t.label ~= "",
                            class.pretty .. ": '" .. id .. "' carries a label")
                        -- Full coverage: the template names every slot of the
                        -- class explicitly (no stale slots when switching).
                        check(type(t.slots) == "table",
                            class.pretty .. ": '" .. id .. "' carries a slots table")
                        if type(t.slots) == "table" then
                            local n = 0
                            for _ in pairs(t.slots) do n = n + 1 end
                            eq(n, #class.slots,
                                class.pretty .. ": '" .. id .. "' covers the full slot set")
                            for _, slot in ipairs(class.slots) do
                                check(t.slots[slot] == true or t.slots[slot] == false,
                                    class.pretty .. ": '" .. id .. "' sets '" .. slot
                                    .. "' explicitly")
                            end
                        end
                        -- The per-template value of the slots whose place in a
                        -- template is documented (the family-specific band).
                        if class.template_values and class.template_values[id] then
                            for slot, want in pairs(class.template_values[id]) do
                                local got = nil
                                if type(t.slots) == "table" then got = t.slots[slot] end
                                eq(got, want,
                                    class.pretty .. ": '" .. id .. "' sets '" .. slot
                                    .. "' to " .. tostring(want))
                            end
                        end
                        -- Geometry: documented values, sane ranges.
                        local want = class.geometry[id]
                        eq(t.hud_icon_size, want.size,
                            class.pretty .. ": '" .. id .. "' icon size")
                        eq(t.hud_spacing, want.spacing,
                            class.pretty .. ": '" .. id .. "' spacing")
                        eq(t.hud_orientation, want.orientation,
                            class.pretty .. ": '" .. id .. "' orientation")
                        eq(t.hud_match_bar_width, want.match,
                            class.pretty .. ": '" .. id .. "' match_bar_width")
                        check(type(t.hud_icon_size) == "number"
                                and t.hud_icon_size >= 8 and t.hud_icon_size <= 64,
                            class.pretty .. ": '" .. id .. "' size in range 8-64")
                        check(type(t.hud_spacing) == "number"
                                and t.hud_spacing >= 0 and t.hud_spacing <= 16,
                            class.pretty .. ": '" .. id .. "' spacing in range 0-16")
                        check(t.hud_orientation == "horizontal"
                                or t.hud_orientation == "vertical",
                            class.pretty .. ": '" .. id .. "' orientation is the enum")
                    end
                end
            end
        end

        -- Every template key names a real HUD_SLOTS descriptor in the class
        -- module (warrior: the union over all family sets in the file).
        local class_src = read_file("classes/" .. class.lower .. ".lua")
        local block = presets_src:match(
            class.token .. "%.HUD_TEMPLATES%s*=%s*{(.-)\n}\n")
        check(block ~= nil,
            class.pretty .. ": the HUD_TEMPLATES source block is found")
        if block then
            for _, slot in ipairs(class.slots) do
                check(class_src:find('key%s*=%s*"' .. slot .. '"') ~= nil,
                    class.pretty .. ": '" .. slot .. "' names a HUD_SLOTS descriptor")
            end
        end
    end
end

--=========================================================================================
-- 2) Defaults surface: hud_show_<key> ships true (ship_false keys ship false);
--    hud_template ships nil. Widget pins live below per key set.
--=========================================================================================
do
    local presets_src = read_file("config_presets.lua")
    local function defaults_block(token)
        return presets_src:match("ST%." .. token .. "%.defaults%s*=%s*{(.-)\n%}") or ""
    end
    for _, class in ipairs(CLASSES) do
        local block = defaults_block(class.token)
        check(block ~= "", class.pretty .. ": the defaults block is found")
        for _, slot in ipairs(class.slots) do
            local default_key = "hud_show_" .. slot
            if class.exempt and class.exempt[slot] then
                check(block:find("%f[%a_]" .. default_key .. "%s*=") == nil,
                    class.pretty .. ": " .. default_key
                    .. " ships NO default (exempted, followups lane owns it)")
            elseif class.ship_false and class.ship_false[slot] then
                check(block:find("%f[%a_]" .. default_key .. "%s*=%s*false") ~= nil,
                    class.pretty .. ": " .. default_key
                    .. " ships false (hidden, no default-visible change)")
                check(block:find("%f[%a_]" .. default_key .. "%s*=%s*true") == nil,
                    class.pretty .. ": " .. default_key .. " ships no true default")
            else
                check(block:find("%f[%a_]" .. default_key .. "%s*=%s*true") ~= nil,
                    class.pretty .. ": " .. default_key .. " ships true in the defaults")
            end
        end
        -- nil default: the key is documented as Custom, never true/a string.
        check(block:find("hud_template") ~= nil,
            class.pretty .. ": hud_template is a documented default key")
        check(block:find("%f[%a_]hud_template%s*=%s*true") == nil
                and block:find('%f[%a_]hud_template%s*=%s*"') == nil,
            class.pretty .. ": hud_template ships no visible default (nil = Custom)")
    end

    -- Widget surface for the non-true defaults: `exempt` keys (none currently)
    -- have no option widget (a follow-up owns them); `ship_false` keys carry
    -- their own toggle widget (nil-safe-off). Slot toggle widgets are declared
    -- as { key = "hud_show_<slot>", ... } in the hud_rotation_widgets call or
    -- as hud_show_<slot> = { ... } in the paladin panel; a prose mention never
    -- takes either form.
    local tables_src = read_file("option_tables.lua")
    for _, class in ipairs(CLASSES) do
        if class.exempt or class.ship_false then
            local pstart = tables_src:find("function ST%.class_opts_funcs%."
                .. class.token .. "%(self%)")
            local pstop = pstart and tables_src:find("\nfunction ST", pstart + 1)
                or nil
            local panel_src = (pstart and pstop)
                and tables_src:sub(pstart, pstop) or ""
            check(panel_src ~= "",
                class.pretty .. ": the panel source is found for the widget pin")
            if class.exempt then
                for slot in pairs(class.exempt) do
                    check(panel_src:find('key = "hud_show_' .. slot .. '"', 1, true) == nil
                            and panel_src:find("hud_show_" .. slot .. " = {", 1, true) == nil,
                        class.pretty .. ": hud_show_" .. slot
                        .. " has no toggle widget of its own (exempted)")
                end
            end
            if class.ship_false then
                for slot in pairs(class.ship_false) do
                    check(panel_src:find('key = "hud_show_' .. slot .. '"', 1, true) ~= nil
                            or panel_src:find("hud_show_" .. slot .. " = {", 1, true) ~= nil,
                        class.pretty .. ": hud_show_" .. slot
                        .. " has a toggle widget of its own (nil-safe-off)")
                end
            end
        end
    end
end

--=========================================================================================
-- 3) Widget behaviour through the real options tree: nil-safe get, apply,
--    Custom fallback, unknown-hides, dirty-detect-as-derived-state.
--=========================================================================================
do
    for _, class in ipairs(CLASSES) do
        local sb, err = build(class.pretty)
        check(sb ~= nil, class.pretty .. ": the options tree builds"
            .. (sb and "" or (": " .. tostring(err))))
        if sb then
            local w = template_widget(sb)
            check(type(w) == "table" and w.type == "select",
                class.pretty .. ": hud_template is a select widget (got "
                .. tostring(type(w) == "table" and w.type or nil) .. ")")
            if type(w) == "table" then
                check(w.order == 8.02,
                    class.pretty .. ": hud_template sits at order 8.02")
                check(type(w.values) == "table" and w.values.custom == "Custom",
                    class.pretty .. ": the values carry Custom")
                for _, id in ipairs(class.templates) do
                    check(type(w.values[id]) == "string",
                        class.pretty .. ": the values name template '" .. id .. "'")
                end
                check(type(w.get) == "function" and type(w.set) == "function",
                    class.pretty .. ": hud_template carries get/set functions")

                -- Fresh profile (nil everywhere): Custom, zero visible change.
                sb.class_db = {}
                eq(w.get(), "custom",
                    class.pretty .. ": nil db reads Custom")
                local before = 0
                for _ in pairs(sb.class_db) do before = before + 1 end
                w.set(nil, "custom")
                local after = 0
                for _ in pairs(sb.class_db) do after = after + 1 end
                eq(sb.class_db.hud_template, nil,
                    class.pretty .. ": picking Custom stores nil")
                eq(after, before,
                    class.pretty .. ": picking Custom writes nothing else")

                -- Apply the first template: full slot set + geometry + stored id.
                local id = class.templates[1]
                local templates = sb.ST[class.token].HUD_TEMPLATES
                local t = templates[id]
                w.set(nil, id)
                eq(sb.class_db.hud_template, id,
                    class.pretty .. ": the pick persists the template id")
                eq(w.get(), id,
                    class.pretty .. ": a fresh apply reads back the template")
                for _, slot in ipairs(class.slots) do
                    eq(sb.class_db["hud_show_" .. slot], t.slots[slot],
                        class.pretty .. ": apply writes hud_show_" .. slot)
                end
                eq(sb.class_db.hud_icon_size, t.hud_icon_size,
                    class.pretty .. ": apply writes the icon size")
                eq(sb.class_db.hud_spacing, t.hud_spacing,
                    class.pretty .. ": apply writes the spacing")
                eq(sb.class_db.hud_orientation, t.hud_orientation,
                    class.pretty .. ": apply writes the orientation")
                eq(sb.class_db.hud_match_bar_width, t.hud_match_bar_width,
                    class.pretty .. ": apply writes match_bar_width")

                -- Any manual tweak reads back as Custom (dirty-detect).
                local first_slot = "hud_show_" .. class.slots[1]
                sb.class_db[first_slot] = not t.slots[class.slots[1]]
                eq(w.get(), "custom",
                    class.pretty .. ": a manual slot tweak reads Custom")
                sb.class_db.hud_icon_size = (t.hud_icon_size == 36) and 28 or 36
                w.set(nil, id)
                eq(w.get(), id,
                    class.pretty .. ": reselect re-applies after a tweak")
                sb.class_db.hud_icon_size = (t.hud_icon_size == 36) and 28 or 36
                eq(w.get(), "custom",
                    class.pretty .. ": a manual geometry tweak reads Custom")

                -- Unknown stored id hides (never a guessed template).
                sb.class_db.hud_template = "bogus_template_id"
                eq(w.get(), "custom",
                    class.pretty .. ": an unknown stored id reads Custom")
                local snapshot = {}
                for k, v in pairs(sb.class_db) do snapshot[k] = v end
                w.set(nil, "bogus_template_id")
                eq(sb.class_db.hud_template, nil,
                    class.pretty .. ": picking unknown stores nil")
                for k, v in pairs(snapshot) do
                    if k ~= "hud_template" then
                        eq(sb.class_db[k], v,
                            class.pretty .. ": picking unknown leaves '" .. k .. "' alone")
                    end
                end
            end
        end
    end
end

--=========================================================================================
-- 4) Gallery provenance: the weakaura-templates shortlist maps onto the entries above.
--=========================================================================================
-- bench/weakaura_templates_2026-10-19.md §3 shortlist (TBC + Classic Era/SoD
-- only; WOTLK-flagged D2/D3 are NOT gallery inputs, so no template draws WotLK
-- kit — evidenced by §1: every slot set covers exactly the class HUD_SLOTS
-- keys, which are the Era/SoD+TBC kits):
--   1) R-T1 UxkIny-style Core is the anchor (A3, TBC 2.4.3): exact label pinned.
--   2) S-T1/S-T2 vs the Sabimaru SoD+Era suite (A2): visual-check target, in-client.
--   3) Core rows vs the Luxthos Era line (A1): visual-check target, in-client.
--   4) Minimal rows vs minimalist swing bars (B3): precedent cite.
--   5) W-T1 copy names the yellow/green queue-color reads (B1, shipped HS tint).
--   6) Dora TBC swing/weave visuals (§D1): bar/weave-domain borrows, out of scope.
--   7) Ralgathor cast-zone bracket + per-spell toggles (§D3, WOTLK-flagged):
--      concept borrow only — per-spell toggles already ship as weave_families.
-- The exact display labels below are pinned so a gallery rename fails loudly.
-- Mutation: relabel any template -> the check for that class fails.
do
    local LABELS = {
        paladin = { twist_core = "P-T1 Twist Core",
            full_ret = "P-T2 Full Ret + Trinkets", minimal = "P-T3 Minimal" },
        warrior = { fury_core = "W-T1 Fury Core",
            full_trinkets = "W-T2 Full + Trinkets",
            arms_sod = "W-T3 Arms / SoD (provisional)" },
        hunter = { shot_rotation = "H-T1 Shot Rotation",
            full_bm = "H-T2 Full BM + Trinkets",
            minimal_glow = "H-T3 Minimal + Glow" },
        druid = { bleed_core = "D-T1 Bleed Core",
            full_feral = "D-T2 Full Feral + Pops", bear_guard = "D-T3 Bear Guard" },
        shaman = { twist_core = "S-T1 Twist Core",
            full_weave = "S-T2 Full Enhance + Weave", minimal = "S-T3 Minimal" },
        rogue = { core = "R-T1 UxkIny-style Core",
            full_cds = "R-T2 Full + CDs + Trinkets",
            pvp_utility = "R-T3 PvP Utility (provisional)" },
    }
    for _, class in ipairs(CLASSES) do
        local sb, err = load_modules(class.pretty)
        if sb then
            local templates = sb.ST[class.token] and sb.ST[class.token].HUD_TEMPLATES
            if type(templates) == "table" then
                for id, want in pairs(LABELS[class.lower]) do
                    local t = templates[id]
                    eq(type(t) == "table" and t.label or nil, want,
                        "GALLERY: " .. class.pretty .. " '" .. id
                        .. "' keeps its gallery label")
                end
            end
        else
            check(false, "GALLERY: " .. class.pretty .. " modules load ("
                .. tostring(err) .. ")")
        end
    end
end

print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
